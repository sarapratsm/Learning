# Identificación del Tenant

## ¿Qué es?

Es el paso por el que una aplicación multi-tenant averigua, al principio de cada petición, a qué tenant (a qué empresa cliente) pertenece. En inglés se llama *tenant resolution*. Su resultado es un único dato —«esta petición es de `acme`»— del que dependen todas las decisiones posteriores.

## ¿Por qué existe?

Una aplicación SaaS de gestión de pedidos atiende con el mismo código y la misma URL base (`miapp.ejemplo.com`) a Acme S.L. (`acme`) y a Globex S.A. (`globex`). Cuando llega `GET /orders`, algo tiene que decidir de quién son los pedidos que se devuelven. Los filtros por `TenantId`, el aislamiento de datos y la elección de la base de datos parten todos de ese dato: si es incorrecto, el resto funciona perfectamente… sobre el tenant equivocado.

> Es la recepción de un edificio de oficinas compartido: antes de dejar subir a nadie, recepción mira la acreditación y decide a qué planta va. Si se fía de lo que la persona dice («vengo a Globex») en vez de comprobar su acreditación, el resto de la seguridad del edificio da igual.

## ¿Cuándo y para qué se usa?

Ocurre en cada petición HTTP, en un *middleware* (pieza que se ejecuta antes del código de negocio, ver [Routing y Middleware](../../desarrollo-web/de-wpf-a-web/Routing-y-Middleware.md)), y deja el tenant en el contexto de la petición, que se desarrolla en [Tenant Context](Tenant-Context.md). Qué se hace con ese tenant (filtrar filas, abrir otra base) está en [Aislamiento por Fila](Aislamiento-por-Fila.md) y [Estrategias de Aislamiento](Estrategias-de-Aislamiento.md).

## De dónde sale el tenant

La pregunta decisiva no es «qué es más cómodo», sino **quién controla el valor**. Lo que controla el cliente puede falsearse; lo que firma el servidor, no.

| Origen | Ejemplo | Quién controla el valor | Ventajas | Riesgos |
|---|---|---|---|---|
| Subdominio | `acme.miapp.ejemplo.com` | El cliente puede escribir cualquier `Host`, pero solo llega a la aplicación si el DNS y el proxy lo encaminan | Visible, sin cambiar las rutas, cookies separadas por origen | Hay que gestionar DNS y certificados (comodín); subdominios reservados; `Host` manipulable si el proxy no lo fija |
| Dominio propio del cliente | `pedidos.cliente.com` | Quien controle el DNS del dominio | Marca blanca | Hay que verificar que el cliente es dueño del dominio (ver más abajo) |
| Prefijo de ruta | `/t/acme/orders` | El cliente | No requiere DNS | Mezcla tenant y rutas; el cliente lo cambia con solo editar la URL |
| Cabecera | `X-Tenant-Id: acme` | El cliente | Cómodo en APIs entre sistemas | Cualquiera puede enviar otro valor; no sirve en navegación normal |
| Claim del token | `tenant_id` dentro de un JWT firmado | El servidor que emite el token | No falsificable sin la clave de firma | Exige autenticación previa; una persona en varios tenants necesita un token por tenant |

Ninguno es suficiente solo en todos los casos. La regla práctica: **el tenant de una petición autenticada se toma o se contrasta con el claim firmado**; el subdominio, la ruta o la cabecera sirven para *ubicar* al visitante (sobre todo antes de iniciar sesión), nunca para *autorizarlo*. Para qué es un JWT y cómo se valida está en [JWT](../../seguridad/autenticacion-y-autorizacion/JWT.md).

### El ataque: cambiar la cabecera

Servidor mínimo con dos rutas. En ambas hay que enviar un token válido; la primera toma el tenant de la cabecera `X-Tenant-Id`:

```csharp
// ❌ El tenant sale de una cabecera que controla el cliente.
app.MapGet("/unsafe/orders", (HttpContext http) =>
{
    var tenantId = int.Parse(http.Request.Headers["X-Tenant-Id"].ToString());
    return Results.Ok(orders.Where(o => o.TenantId == tenantId));
}).RequireAuthorization();
```

Los pedidos son `{ Id = 1, TenantId = 1, Total = 120 }` (de `acme`) y `{ Id = 2, TenantId = 2, Total = 990 }` (de `globex`). Ana es usuaria de `acme`: su token lleva `tenant_id = 1`. Con su propio tenant y después cambiando la cabecera:

```bash
TOKEN=$(curl -s -X POST localhost:6417/login/ana/1)

curl -si localhost:6417/unsafe/orders -H "Authorization: Bearer $TOKEN" -H "X-Tenant-Id: 1"
curl -si localhost:6417/unsafe/orders -H "Authorization: Bearer $TOKEN" -H "X-Tenant-Id: 2"
```

```text
HTTP/1.1 200 OK
[{"id":1,"tenantId":1,"total":120}]

HTTP/1.1 200 OK
[{"id":2,"tenantId":2,"total":990}]
```

La segunda respuesta es el pedido de Globex entregado a una persona de Acme: autenticada, con un token legítimo y sin explotar ningún fallo del código de filtrado. El error está solo en haber confiado en la cabecera. La versión correcta toma el tenant del claim y, si la cabecera viene, la contrasta:

```csharp
// ✅ El tenant sale del claim firmado; la cabecera, si viene, solo se contrasta.
app.MapGet("/safe/orders", (HttpContext http) =>
{
    var tenantId = int.Parse(http.User.FindFirst("tenant_id")!.Value);

    if (http.Request.Headers.TryGetValue("X-Tenant-Id", out var header)
        && header.ToString() != tenantId.ToString())
    {
        return Results.Json(new { error = "El tenant indicado no coincide con el del token." },
            statusCode: StatusCodes.Status403Forbidden);
    }

    return Results.Ok(orders.Where(o => o.TenantId == tenantId));
}).RequireAuthorization();
```

```text
$ curl -si localhost:6417/safe/orders -H "Authorization: Bearer $TOKEN" -H "X-Tenant-Id: 2"
HTTP/1.1 403 Forbidden
{"error":"El tenant indicado no coincide con el del token."}

$ curl -si localhost:6417/safe/orders -H "Authorization: Bearer $TOKEN"
HTTP/1.1 200 OK
[{"id":1,"tenantId":1,"total":120}]
```

Se ejecutó con ASP.NET Core 10 y `Microsoft.AspNetCore.Authentication.JwtBearer` 10.0.14. Un `403` y no un `404`: la persona está autenticada y se le niega un tenant que no es el suyo.

## Un middleware de resolución completo

La resolución por `Host` se compone de tres piezas: un resolvedor que decide qué tenant corresponde a la petición, un almacén que lo busca, y un middleware que corta la petición si no hay tenant utilizable y lo deja en el contexto si lo hay.

### Las piezas

```csharp
public sealed record Tenant(int Id, string Name, string Subdomain, bool IsActive);

public interface ITenantStore
{
    Task<Tenant?> FindBySubdomainAsync(string subdomain, CancellationToken ct);
}

public interface ITenantResolver
{
    /// <summary>Tenant de la petición, o null si no corresponde a ninguno.</summary>
    Task<Tenant?> ResolveAsync(HttpContext http, CancellationToken ct);
}

public sealed class HostTenantResolver(ITenantStore store, IConfiguration config) : ITenantResolver
{
    private readonly string _baseDomain = config["BaseDomain"] ?? "miapp.ejemplo.com";

    public async Task<Tenant?> ResolveAsync(HttpContext http, CancellationToken ct)
    {
        var subdomain = TenantHost.ExtractSubdomain(http.Request.Host.Value, _baseDomain);
        return subdomain is null ? null : await store.FindBySubdomainAsync(subdomain, ct);
    }
}
```

`ITenantStore` es la consulta a la base de datos (en las pruebas, un diccionario en memoria con `acme` y `globex` activos e `initech` suspendido). `TenantHost.ExtractSubdomain` se desarrolla en la sección siguiente. La interfaz mínima del contexto, para que el resto del código lea el tenant, y su implementación, que solo el middleware rellena:

```csharp
public interface ITenantContext { Tenant? Tenant { get; } }

public sealed class TenantContext : ITenantContext
{
    public Tenant? Tenant { get; private set; }
    public void Set(Tenant tenant) => Tenant = tenant;
}
```

Cómo vive ese contexto durante la petición, por qué es `Scoped` y qué pasa con `AsyncLocal` y con los hilos en segundo plano está en [Tenant Context](Tenant-Context.md).

### El middleware

```csharp
public sealed class TenantResolutionMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext http, ITenantResolver resolver, TenantContext tenantContext)
    {
        var tenant = await resolver.ResolveAsync(http, http.RequestAborted);

        if (tenant is null)
        {
            http.Response.StatusCode = StatusCodes.Status404NotFound;
            await http.Response.WriteAsJsonAsync(new { error = "Tenant desconocido." });
            return;
        }

        if (!tenant.IsActive)
        {
            http.Response.StatusCode = StatusCodes.Status403Forbidden;
            await http.Response.WriteAsJsonAsync(new { error = "Tenant suspendido." });
            return;
        }

        tenantContext.Set(tenant);
        await next(http);
    }
}
```

Los servicios `Scoped` (`TenantContext`) se piden como parámetros de `InvokeAsync`, no en el constructor: el constructor de un middleware se ejecuta una vez, y un servicio con ámbito de petición no existe todavía. Sin tenant válido no se llama a `next`: ningún código posterior se ejecuta «sin tenant».

### Registro y pipeline

```csharp
builder.Services.AddMemoryCache();
builder.Services.AddSingleton<InMemoryTenantStore>();      // almacén de la demo; en producción, la base de datos
builder.Services.AddSingleton(sp => new CachedTenantStore(
    sp.GetRequiredService<InMemoryTenantStore>(),
    sp.GetRequiredService<IMemoryCache>(),
    TimeSpan.FromSeconds(30)));                            // la caché se explica más abajo
builder.Services.AddSingleton<ITenantStore>(sp => sp.GetRequiredService<CachedTenantStore>());
builder.Services.AddSingleton<ITenantResolver, HostTenantResolver>();
builder.Services.AddScoped<TenantContext>();
builder.Services.AddScoped<ITenantContext>(sp => sp.GetRequiredService<TenantContext>());

var app = builder.Build();

app.UseAuthentication();                                   // 1.º quién es
app.UseMiddleware<TenantResolutionMiddleware>();           // 2.º de qué tenant es la petición
app.UseMiddleware<TenantMatchesTokenMiddleware>();         // 3.º si coinciden (más abajo)
app.UseAuthorization();                                    // 4.º qué puede hacer

app.MapGet("/", (ITenantContext tenant) => $"Hola, {tenant.Tenant!.Name}");
```

Salidas reales con `Host:` distintos (ASP.NET Core 10, servidor en `localhost:6418`):

```bash
curl -si localhost:6418/ -H "Host: acme.miapp.ejemplo.com"
curl -si localhost:6418/ -H "Host: GLOBEX.miapp.ejemplo.com:6418"
curl -si localhost:6418/ -H "Host: desconocido.miapp.ejemplo.com"
curl -si localhost:6418/ -H "Host: initech.miapp.ejemplo.com"
```

```text
HTTP/1.1 200 OK
Hola, Acme S.L.

HTTP/1.1 200 OK
Hola, Globex S.A.

HTTP/1.1 404 Not Found
{"error":"Tenant desconocido."}

HTTP/1.1 403 Forbidden
{"error":"Tenant suspendido."}
```

Desconocido es `404` (no hay nada que mostrar) y suspendido es `403` (existe, pero no se le atiende). Un `404` uniforme para ambos oculta qué empresas son clientes; un `403` distinto ayuda a quien soporta la plataforma. Es una decisión de producto: lo que importa es no continuar.

## Orden en el pipeline

El middleware se ejecuta en el orden en que se registra, y la documentación de ASP.NET Core advierte de que ese orden puede ser crítico para la seguridad. Para la resolución, dos reglas:

1. **Antes de todo lo que use el tenant**: autorización basada en tenant, endpoints, acceso a datos.
2. **Después de la autenticación, si el tenant sale del token o se contrasta con él**: antes de `UseAuthentication`, `HttpContext.User` está vacío.

Si el tenant se resuelve por `Host` y además se contrasta con el claim, hay un contraste que depende de la autenticación:

```csharp
// Contrasta el tenant del host con el claim del token.
public sealed class TenantMatchesTokenMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext http, ITenantContext tenantContext)
    {
        if (http.User.Identity?.IsAuthenticated == true)
        {
            var claim = http.User.FindFirstValue("tenant_id");
            if (claim != tenantContext.Tenant!.Id.ToString())
            {
                http.Response.StatusCode = StatusCodes.Status403Forbidden;
                await http.Response.WriteAsJsonAsync(new { error = "El token no pertenece a este tenant." });
                return;
            }
        }
        await next(http);
    }
}
```

Las peticiones anónimas (la página de inicio de sesión, por ejemplo) pasan sin contraste; las autenticadas deben coincidir. Ana (`acme`, `tenant_id = 1`) pide `/orders` en el host de `acme` y en el de `globex`, con el orden correcto:

```text
$ curl -si localhost:6418/orders -H "Host: acme.miapp.ejemplo.com" -H "Authorization: Bearer $TOKEN"
HTTP/1.1 200 OK
[{"id":1,"tenantId":1,"total":120}]

$ curl -si localhost:6418/orders -H "Host: globex.miapp.ejemplo.com" -H "Authorization: Bearer $TOKEN"
HTTP/1.1 403 Forbidden
{"error":"El token no pertenece a este tenant."}
```

Con el orden invertido (resolución y contraste antes de `UseAuthentication`):

```csharp
app.UseMiddleware<TenantResolutionMiddleware>();
app.UseMiddleware<TenantMatchesTokenMiddleware>();
app.UseAuthentication();       // ❌ demasiado tarde
app.UseAuthorization();
```

```text
$ curl -si localhost:6419/orders -H "Host: globex.miapp.ejemplo.com" -H "Authorization: Bearer $TOKEN"
HTTP/1.1 200 OK
[{"id":2,"tenantId":2,"total":990}]
```

Al ejecutarse el contraste, nadie estaba autenticado todavía, así que `IsAuthenticated` era `false` y se saltó la comprobación; después `UseAuthentication` identificó a Ana y la autorización la dejó pasar. No hay ningún error ni ninguna excepción: el fallo es silencioso y el resultado, el pedido de Globex en manos de Acme. Más sobre el orden del pipeline en [Routing y Middleware](../../desarrollo-web/de-wpf-a-web/Routing-y-Middleware.md).

## Resolución por subdominio robusta

Extraer el subdominio con `host.Split('.')[0]` falla con casi cualquier valor real. El `Host` puede traer puerto, mayúsculas, un punto final o un `www.`, y algunos subdominios no son de ningún cliente.

```csharp
public static partial class TenantHost
{
    private static readonly HashSet<string> Reserved =
        new(StringComparer.OrdinalIgnoreCase) { "admin", "www", "api", "mail", "staging" };

    [GeneratedRegex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$")]
    private static partial Regex Label();

    /// <summary>Devuelve el subdominio del tenant, o null si el host no identifica a ninguno.</summary>
    public static string? ExtractSubdomain(string? host, string baseDomain)
    {
        if (string.IsNullOrWhiteSpace(host)) return null;

        var name = new HostString(host.Trim()).Host        // sin puerto
            .TrimEnd('.')                                   // "acme.miapp.ejemplo.com." es válido en DNS
            .ToLowerInvariant();

        var suffix = "." + baseDomain.ToLowerInvariant();
        if (!name.EndsWith(suffix, StringComparison.Ordinal)) return null;

        var label = name[..^suffix.Length];
        if (label.StartsWith("www.", StringComparison.Ordinal)) label = label[4..];

        if (!Label().IsMatch(label)) return null;           // vacío, "a.b" u otros caracteres
        return Reserved.Contains(label) ? null : label;
    }
}
```

| `Host` recibido | Resultado | Motivo |
|---|---|---|
| `acme.miapp.ejemplo.com` | `acme` | Caso normal |
| `ACME.miapp.ejemplo.com:5001` | `acme` | Se quitan puerto y mayúsculas |
| `acme.miapp.ejemplo.com.` | `acme` | El punto final es un nombre DNS válido |
| `www.acme.miapp.ejemplo.com` | `acme` | Se ignora un `www.` inicial |
| `www.miapp.ejemplo.com`, `admin…`, `API…` | `null` | Subdominios reservados de la plataforma |
| `miapp.ejemplo.com` | `null` | Dominio base, sin tenant |
| `a.b.acme.miapp.ejemplo.com` | `null` | Más de una etiqueta |
| `acme.otro.com`, `evilmiapp.ejemplo.com`, `acme.miapp.ejemplo.com.evil.com` | `null` | No termina en `.miapp.ejemplo.com` |
| `-acme.miapp.ejemplo.com`, vacío, ausente | `null` | Etiqueta inválida o sin dato |

Los casos de la tabla, como prueba de xUnit (los 15 pasan en .NET 10):

```csharp
public class TenantHostTests
{
    [Theory]
    [InlineData("acme.miapp.ejemplo.com", "acme")]
    [InlineData("ACME.miapp.ejemplo.com:5001", "acme")]
    [InlineData("acme.miapp.ejemplo.com.", "acme")]
    [InlineData("www.acme.miapp.ejemplo.com", "acme")]
    [InlineData("www.miapp.ejemplo.com", null)]
    [InlineData("admin.miapp.ejemplo.com", null)]
    [InlineData("API.miapp.ejemplo.com", null)]
    [InlineData("miapp.ejemplo.com", null)]
    [InlineData("a.b.acme.miapp.ejemplo.com", null)]
    [InlineData("acme.otro.com", null)]
    [InlineData("evilmiapp.ejemplo.com", null)]
    [InlineData("acme.miapp.ejemplo.com.evil.com", null)]
    [InlineData("-acme.miapp.ejemplo.com", null)]
    [InlineData("", null)]
    [InlineData(null, null)]
    public void ExtractSubdomain(string? host, string? expected)
        => Assert.Equal(expected, TenantHost.ExtractSubdomain(host, "miapp.ejemplo.com"));
}
```

Que los subdominios reservados devuelvan `null` evita que `admin.miapp.ejemplo.com` (el panel de la plataforma) se trate como un tenant llamado `admin`. Y la lista debe aplicarse también en el alta: un cliente que registre `admin` o `www` no debe poder.

### La caché del almacén

Consultar la base de datos en cada petición no escala. Un decorador con `IMemoryCache` guarda el resultado con expiración:

```csharp
public sealed class CachedTenantStore(ITenantStore inner, IMemoryCache cache, TimeSpan ttl) : ITenantStore
{
    public async Task<Tenant?> FindBySubdomainAsync(string subdomain, CancellationToken ct)
    {
        // GetOrCreateAsync también guarda los null: un subdominio inventado no llega a la base en cada petición.
        return await cache.GetOrCreateAsync($"tenant:{subdomain}", async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = ttl;
            return await inner.FindBySubdomainAsync(subdomain, ct);
        });
    }

    public void Invalidate(string subdomain) => cache.Remove($"tenant:{subdomain}");
}
```

El precio es que **un tenant suspendido sigue activo hasta que la entrada caduque**. Con una caducidad de 30 s, y sin invalidar, tras suspender `acme`:

```text
$ curl -s localhost:6418/_demo/suspend/acme
suspendido
$ curl -si localhost:6418/ -H "Host: acme.miapp.ejemplo.com"
HTTP/1.1 200 OK
Hola, Acme S.L.
```

Invalidando la entrada en el momento de suspender:

```text
$ curl -s "localhost:6418/_demo/suspend/acme?invalidate=true"
suspendido
$ curl -si localhost:6418/ -H "Host: acme.miapp.ejemplo.com"
HTTP/1.1 403 Forbidden
{"error":"Tenant suspendido."}
```

| Decisión | Efecto |
|---|---|
| TTL largo (minutos) | Pocas consultas; un tenant suspendido o comprometido sigue entrando ese tiempo |
| TTL corto (segundos) | Ventana pequeña; más consultas a la base |
| Invalidar al suspender | Efecto inmediato en una sola instancia |
| Varias instancias de la aplicación | `IMemoryCache` es local a cada proceso: la invalidación solo llega a una; hace falta TTL corto o una caché compartida (ver [Redis](../../bases-de-datos/caching/Redis.md) y [Estrategias de Invalidación](../../bases-de-datos/caching/Estrategias-de-Invalidacion.md)) |

Cachear también los `null` protege a la base de un barrido de subdominios inventados, pero retrasa unos segundos la aparición de un tenant recién creado.

## Combinar varias fuentes

Cuando una petición trae dos indicaciones (el host y el claim del token), no se elige entre ellas: se comparan y, si no coinciden, se rechaza. Es lo que hace `TenantMatchesTokenMiddleware`, visto en el apartado del orden. La diferencia entre las dos respuestas posibles:

| Situación | Respuesta |
|---|---|
| Host y claim coinciden | Continuar |
| Host y claim difieren | `403`: la persona está autenticada, pero en otro tenant |
| Host desconocido o tenant suspendido | `404` / `403` en el middleware de resolución |
| Sin token (anónima) | Continuar hasta que la autorización decida (`401` en las rutas protegidas) |

No hay que «corregir» la diferencia ni preferir una fuente: una discrepancia es una petición mal formada o un intento de acceso indebido. Cuando una misma persona pertenece a varios tenants, cambiar de organización es pedir un token nuevo con otro `tenant_id`, no mandar un parámetro junto al token viejo.

## Dominios propios de los clientes

Un cliente puede querer `pedidos.cliente.com` en lugar de `acme.miapp.ejemplo.com`. El almacén necesita una tabla de dominios y un resolvedor que busque por `Host` completo:

| `CustomDomain` | `TenantId` | `VerificationToken` | `VerifiedAt` |
|---|---|---|---|
| `pedidos.cliente.com` | 1 | `miapp-verify=9f3c…` | `2026-11-02T10:15:00Z` |

Solo se resuelven los dominios con `VerifiedAt` informado. Si no se verifica, cualquiera puede registrar `pedidos.otracompania.com` como dominio propio y, el día que ese dominio apunte a la aplicación, recibir su tráfico. La verificación de propiedad es un registro DNS TXT que la persona administradora del dominio debe poder crear y que la aplicación comprueba: se pide crear `_miapp-challenge.pedidos.cliente.com` con valor `miapp-verify=9f3c…`; la aplicación consulta ese TXT y, solo si el valor coincide con el token guardado, marca el dominio como verificado. La biblioteca estándar de .NET no consulta registros TXT (se usa una biblioteca de DNS o el proveedor). Esta parte no se ha ejecutado en esta máquina: el esquema es ilustrativo.

## Fuera de una petición HTTP

Los mensajes de una cola y las tareas programadas no tienen `Host` ni token. El tenant debe viajar en el propio mensaje y restablecerse al procesarlo:

```csharp
public sealed record OrderCreated(int OrderId, int TenantId);   // el tenant va dentro

// Al consumir: se resuelve el tenant por su Id y se pone en el contexto del ámbito del mensaje.
using var scope = scopeFactory.CreateScope();
var tenant = await store.FindByIdAsync(message.TenantId, ct);
scope.ServiceProvider.GetRequiredService<TenantContext>().Set(tenant!);
```

(`FindByIdAsync` no está en `ITenantStore` de arriba: se añadiría igual que `FindBySubdomainAsync`; este fragmento no se ha compilado.) Un mensaje sin `TenantId`, o procesado en un hilo con otro tenant heredado, es una fuga por el camino que no pasa por el middleware. El contenedor de contexto y su comportamiento en segundo plano están en [Tenant Context](Tenant-Context.md); los problemas de jobs y logs, en [Retos Avanzados](Retos-Avanzados.md).

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| Una persona de un tenant ve pedidos de otro cambiando una cabecera, la ruta o un parámetro | El tenant sale de un valor que controla el cliente y no se contrasta con el token |
| La comprobación contra el token «pasa» siempre y nada falla | El middleware de resolución o de contraste está antes de `UseAuthentication`: `User` aún vacío |
| Un dominio que no es de ningún cliente muestra los datos de un tenant | Un host desconocido cae en un «tenant por defecto» en vez de devolver `404` |
| Alguien registra `admin` o `www` y suplanta páginas de la plataforma | Subdominios reservados sin proteger en el alta ni en la resolución |
| Un tenant suspendido sigue accediendo varios minutos | La caché de la resolución no se invalida al desactivarlo; o hay varias instancias con cachés locales |
| `acme` no se encuentra con `ACME.miapp.ejemplo.com:443` | El `Host` se compara sin normalizar (mayúsculas, puerto, punto final) |
| Tras un proxy, todos los hosts son `localhost` o el interno | El proxy no reenvía `Host`/`X-Forwarded-Host`, o la aplicación no lo configura |

## Buenas prácticas avanzadas

- **Lee del token firmado antes que de lo que el cliente envía.** El claim `tenant_id` lo escribe quien emite el token; el subdominio, la ruta y la cabecera los escribe quien hace la petición. Para una petición autenticada, el claim manda y lo demás se contrasta.
- **Un host o tenant desconocido nunca cae en un valor por defecto.** Un «tenant por defecto» convierte cualquier error de configuración en una fuga. `404` o `403`, y el código posterior no se ejecuta.
- **Reserva los subdominios peligrosos antes de abrir el registro.** `www`, `api`, `admin`, `mail` o `staging` se bloquean en el alta y en la resolución; añadirlos después, con tenants ya registrados, es mucho más incómodo.
- **Limita los hosts que la aplicación acepta y fija quién escribe el `Host`.** Detrás de un proxy inverso, el proxy debe fijar `Host`/`X-Forwarded-Host`, y la aplicación debe configurar los hosts permitidos (`AllowedHosts`) y el *middleware* de cabeceras reenviadas; de lo contrario la identidad del tenant descansa en una cabecera inyectable.
- **Decide el TTL de la caché como un límite de seguridad.** Es el tiempo máximo que un tenant suspendido puede seguir entrando; combina TTL corto con invalidación al suspender.
- **Cambiar de organización es reemitir el token.** No es un parámetro extra junto al token viejo: la persona elige tenant y el servidor emite un token nuevo con el claim correcto.

## Documentación oficial

- [Middleware de ASP.NET Core](https://learn.microsoft.com/aspnet/core/fundamentals/middleware/): la sección «Middleware order» explica por qué el orden de registro importa para la seguridad; consúltala al colocar la resolución respecto a la autenticación.
- [Map requests to tenants in a multitenant solution](https://learn.microsoft.com/azure/architecture/guide/multitenant/considerations/map-requests) (Azure Architecture Center): compara dominios, ruta, cabeceras, claims, claves de API y proxies inversos como origen del tenant, y recomienda validar siempre que la petición está autorizada para ese tenant; léela al elegir el origen.

---

*En resumen: el tenant es la acreditación de la recepción, y solo es de fiar la que firma el servidor: lo que el cliente escribe en la URL o en una cabecera se contrasta, nunca se cree.*
