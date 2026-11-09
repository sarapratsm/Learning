# Retos Avanzados

## ¿Qué es?

Los problemas de convivencia que aparecen cuando una aplicación multi-tenant crece y sus datos ya están aislados: un *tenant* (empresa cliente) que acapara los recursos, configuración propia de cada tenant, cachés que mezclan datos y fugas por canales distintos de la base de datos (logs, ficheros, correos).

## ¿Por qué existe?

El aislamiento de datos es el punto de partida. Cuando una aplicación se comparte entre muchos clientes, también se comparten la CPU, la memoria, la caché, las colas de trabajos y los límites de la API; y cada cliente espera que la aplicación se comporte como si fuera solo suya: su idioma, su moneda, sus funciones activadas.

> En el edificio de apartamentos, una vez resuelto que nadie entra en un piso ajeno, quedan los problemas de convivencia: el vecino ruidoso, la decoración de cada casa, el ascensor saturado a las 8:00 y el buzón donde el correo de un piso acaba en otro.

## ¿Cuándo y para qué se usa?

Estos retos se vuelven urgentes cuando el producto pasa de unos pocos clientes a muchos, o cuando aparece un cliente que consume mucho más que el resto. En una aplicación de gestión de pedidos con los tenants `acme` y `globex`, el síntoma típico es una llamada de soporte: «desde esta mañana todo va lento» (un tenant ha lanzado una importación enorme), «veo un precio que no es el mío» (caché sin prefijo) o «no sabemos qué cliente provocó el error de las 3:00» (logs sin tenant).

## El vecino ruidoso

El problema del vecino ruidoso (*noisy neighbor*) aparece cuando la actividad de un tenant degrada el servicio de otro por compartir recursos. La guía de Azure Architecture Center sobre este antipatrón lo trata como un problema de gobierno de recursos y propone, entre otras medidas, imponer cuotas con los patrones *Throttling* o *Rate Limiting*. El aislamiento de datos no lo resuelve: `globex` no ve los pedidos de `acme` y aun así sufre sus picos de tráfico.

### Límite por tenant en HTTP

El limitador de ASP.NET Core (`AddRateLimiter`) admite particiones: cada clave de partición tiene sus propios contadores. Con el `TenantId` como clave, cada tenant tiene su propio cupo y agotarlo no afecta a los demás. El ejemplo resuelve el tenant por subdominio solo para ser breve (cómo se resuelve de verdad está en [Identificación del Tenant](Identificacion-del-Tenant.md)) y lee el límite del propio tenant:

```csharp
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.OnRejected = (context, _) =>
    {
        if (context.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter))
            context.HttpContext.Response.Headers.RetryAfter =
                ((int)retryAfter.TotalSeconds).ToString();
        return ValueTask.CompletedTask;
    };

    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(http =>
    {
        var subdomain = http.Request.Host.Host.Split('.')[0];
        if (!tenants.TryGetValue(subdomain, out var tenant))
            return RateLimitPartition.GetNoLimiter("unknown");   // lo rechaza otra capa

        return RateLimitPartition.GetFixedWindowLimiter(tenant.Id, _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = tenant.RequestsPerWindow,
            Window = TimeSpan.FromSeconds(30),
            QueueLimit = 0,
        });
    });
});

app.UseRateLimiter();
```

Con `acme` en el plan gratuito (3 peticiones por ventana de 30 segundos) y `globex` en el premium (10), se lanzan cinco peticiones a `acme` y dos a `globex` con `curl` contra el servidor local, cambiando la cabecera `Host`:

```bash
for i in 1 2 3 4 5; do
  curl -s -o /dev/null -D - -H "Host: acme.miapp.ejemplo.com" http://localhost:6431/api/orders
done
```

```text
HTTP/1.1 200 OK
HTTP/1.1 200 OK
HTTP/1.1 200 OK
HTTP/1.1 429 Too Many Requests   Retry-After: 30
HTTP/1.1 429 Too Many Requests   Retry-After: 30
```

```bash
curl -si -H "Host: globex.miapp.ejemplo.com" http://localhost:6431/api/orders
```

```text
HTTP/1.1 200 OK
pedidos de globex
```

`acme` agota su cuota y recibe `429` con `Retry-After`; `globex`, en el mismo servidor y en el mismo momento, sigue recibiendo `200`. La cabecera `Retry-After` la escribe `OnRejected` a partir de los metadatos del *lease* (`MetadataName.RetryAfter`); sin ella, el limitador solo devuelve el código de estado. Las salidas provienen de una ejecución con .NET 10 el 2026-11-09 (ASP.NET Core `Microsoft.AspNetCore.RateLimiting`, incluido en el *shared framework*).

### Cuotas por plan

La política anterior ya lee el límite del tenant: `tenant.RequestsPerWindow` vale 3 para el plan gratuito y 10 para el premium. Los límites no se escriben en el código sino en el `Tenant` (o en su plan), para cambiarlos sin desplegar. Para un panel de administración o una API pública con audiencias distintas (personas, otros sistemas, la propia plataforma), los límites de uso por audiencia se tratan en [APIs por Audiencia](../tipos-de-apis/APIs-por-Audiencia.md).

### Más allá de HTTP: trabajos en segundo plano

Limitar peticiones no protege las colas de trabajos. Si `acme` encola 10 000 informes y todos los trabajos comparten una única cola FIFO, los trabajos de `globex` esperan detrás de todos ellos. La solución es una cola por tenant con reparto rotatorio (*round robin*): el procesador toma un trabajo de cada tenant por turno.

El experimento usa un `Channel<T>` compartido frente a un `Channel<T>` por tenant, con 1000 trabajos de `acme` llegados antes que 3 de `globex` y un solo procesador:

```csharp
// Un Channel por tenant y reparto rotatorio
var perTenant = new Dictionary<string, Channel<Job>>();
foreach (var j in jobs)
{
    if (!perTenant.TryGetValue(j.TenantId, out var ch))
        perTenant[j.TenantId] = ch = Channel.CreateUnbounded<Job>();
    ch.Writer.TryWrite(j);
}
var pending = perTenant.Values.ToList();
while (pending.Count > 0)
{
    foreach (var ch in pending.ToList())
    {
        if (ch.Reader.TryRead(out var job)) order.Add(job);   // un trabajo por tenant y vuelta
        else pending.Remove(ch);
    }
}
```

```text
== Cola compartida
primeros 6: acme-1, acme-2, acme-3, acme-4, acme-5, acme-6
globex-1 en la posición 1001; globex-2 en la posición 1002; globex-3 en la posición 1003
== Reparto rotatorio
primeros 6: acme-1, globex-1, acme-2, globex-2, acme-3, globex-3
globex-1 en la posición 2; globex-2 en la posición 4; globex-3 en la posición 6
```

Con la cola compartida, `globex` espera a que terminen los 1000 trabajos de `acme`; con el reparto, su primer trabajo sale en la posición 2. El código de producción necesita además un procesador que espere cuando todas las colas están vacías y una cola nueva cuando aparece un tenant; lo ejecutado aquí es el orden de procesamiento. Cuando el trabajo se ejecuta fuera de la petición, cada trabajo debe llevar su tenant y fijarlo antes de ejecutarse (ver [Tenant Context](Tenant-Context.md)).

### Consultas y base de datos

- **Consultas pesadas:** un tiempo máximo por consulta (`CommandTimeout`) y paginación obligatoria con un tamaño máximo de página evitan que un tenant con millones de filas devuelva todas en una sola petición.
- **Recursos de la base de datos:** con una base por tenant, cada tenant consume su propia base y el ruido queda contenido; con esquema por tenant, comparten el servidor pero no las tablas; con una base compartida y columna `TenantId`, comparten todo, también el plan de ejecución y los bloqueos. La comparativa completa está en [Estrategias de Aislamiento](Estrategias-de-Aislamiento.md).

## Configuración por tenant

Cada cliente quiere personalizar la aplicación: tema, idioma, moneda y funciones activadas según su plan (*feature flags*). Esa configuración se guarda asociada al `TenantId`, en una columna JSON del propio `Tenant` o en una tabla de ajustes con una fila por tenant, y se lee con caché porque se necesita en casi todas las peticiones.

Las opciones por tenant con `IOptionsSnapshot` o `IOptionsMonitor` requieren una fábrica de opciones propia por tenant; la opción más sencilla que funciona es un servicio `ITenantSettings` que consulta la tabla y guarda el resultado en `IMemoryCache` con una clave que incluye el tenant:

```csharp
record TenantSettings(string Theme = "claro", string Language = "es",
    string Currency = "EUR", HashSet<string>? Features = null)
{
    public bool Has(string feature) => Features?.Contains(feature) == true;
}

interface ITenantSettings { Task<TenantSettings> GetAsync(); void Invalidate(string tenantId); }

class CachedTenantSettings(SettingsStore store, IMemoryCache cache, ITenantContext tenant) : ITenantSettings
{
    static string Key(string id) => $"tenant:{id}:settings";

    public async Task<TenantSettings> GetAsync()
    {
        var id = tenant.TenantId;
        return (await cache.GetOrCreateAsync(Key(id), async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10);
            var json = await store.LoadJsonAsync(id);   // una fila JSON por tenant
            return json is null ? new TenantSettings()
                : JsonSerializer.Deserialize<TenantSettings>(json)!;
        }))!;
    }

    public void Invalidate(string tenantId) => cache.Remove(Key(tenantId));
}
```

Con `acme` guardado como `{"Theme":"oscuro","Features":["export_pdf"]}` y `globex` como `{"Language":"en","Currency":"USD"}`, se piden los ajustes de `acme`, `globex` y de nuevo `acme`; después se cambia el tema de `acme` en la base:

```text
acme: tema=oscuro idioma=es moneda=EUR export_pdf=True (lecturas a BD: 1)
globex: tema=claro idioma=en moneda=USD export_pdf=False (lecturas a BD: 2)
acme: tema=oscuro idioma=es moneda=EUR export_pdf=True (lecturas a BD: 2)
-- acme cambia su tema a 'claro' en la BD, sin invalidar
acme: tema=oscuro
acme tras Invalidate: tema=claro (lecturas a BD: 3)
```

La segunda lectura de `acme` no toca la base (sigue en 2 lecturas), y el cambio no se ve hasta que se invalida la entrada: quien guarda los ajustes (la pantalla de configuración del tenant) debe llamar a `Invalidate`. La caducidad de 10 minutos acota cuánto puede durar un valor viejo si alguien olvida invalidar; con varias instancias de la aplicación, la caché en memoria de cada una se invalida por separado, y ahí hace falta una caché distribuida o un tiempo de vida corto (ver [Estrategias de Invalidación](../../bases-de-datos/caching/Estrategias-de-Invalidacion.md)).

### El valor por defecto que se hereda sin saberlo

En la salida, `globex` aparece con `tema=claro` y `idioma=es` aunque nadie lo eligió: son los valores por defecto del registro `TenantSettings`. Un tenant que no ha configurado un valor lo hereda del valor global, y cuando ese valor global cambia (por ejemplo, el IVA o la moneda por defecto), cambia para todos los tenants que no lo tenían fijado, sin que lo sepan. Dos defensas: guardar en el alta del tenant los valores que importan de verdad (moneda, zona horaria) en lugar de depender del valor por defecto, y tratar un cambio de valor por defecto como un cambio que afecta a todos los clientes.

## Caché

Una caché compartida es la fuente clásica de fugas entre tenants: si la clave no incluye el tenant, el primer tenant que guarda un dato lo sirve a todos los demás.

### El fallo: clave sin prefijo

`acme` guarda el producto 42 en una `IMemoryCache` y después `globex` lo pide con la misma clave:

```csharp
var raw = new MemoryCache(new MemoryCacheOptions());
raw.Set("product:42", "Tornillo de Acme (3,20 EUR)", TimeSpan.FromMinutes(5));   // acme guarda
Console.WriteLine("globex lee product:42 -> " + raw.Get<string>("product:42"));  // globex lee
```

```text
== Clave sin prefijo
globex lee product:42 -> Tornillo de Acme (3,20 EUR)
```

`globex` recibe el producto y el precio de `acme`, aunque la consulta a la base estuviera perfectamente filtrada: la fuga ocurre en la caché.

### La solución: un envoltorio que antepone el tenant

Prefijar cada clave a mano falla en cuanto alguien se olvida una vez. La defensa es un envoltorio `TenantCache` que antepone `tenant:{id}:` a todas las claves y que sea la única forma de acceder a la caché: ningún otro código inyecta `IMemoryCache` directamente (la excepción son los componentes de infraestructura, como `ITenantSettings`, que construyen su clave con el tenant).

```csharp
class TenantCache(IMemoryCache inner, ITenantContext tenant)
{
    string Key(string key) => $"tenant:{tenant.TenantId}:{key}";
    public bool TryGet<T>(string key, out T? value) => inner.TryGetValue(Key(key), out value);
    public void Set<T>(string key, T value, TimeSpan ttl) => inner.Set(Key(key), value, ttl);
    public void Remove(string key) => inner.Remove(Key(key));
}
```

La comprobación guarda como `acme` y lee como `globex` y como `acme`:

```text
== TenantCache
globex lee product:42 -> (vacío)
acme lee product:42   -> Tornillo de Acme (3,20 EUR)
```

Un test que ejecute esa misma secuencia y falle si `globex` obtiene un valor protege la regla frente a cambios futuros.

### Caché distribuida y caché de salida HTTP

**Redis (descrito, no ejecutado):** la misma regla con el mismo prefijo: las claves son `tenant:acme:product:42`. Para eliminar todas las claves de un tenant (por ejemplo, al darlo de baja) se recorren las claves con el patrón `tenant:acme:*` con `SCAN`, nunca con `KEYS` en producción, porque bloquea el servidor. Detalles en [Redis](../../bases-de-datos/caching/Redis.md) y [Estrategias de Invalidación](../../bases-de-datos/caching/Estrategias-de-Invalidacion.md).

**Caché de salida HTTP:** la respuesta cacheada de un endpoint que depende del tenant tiene que variar por tenant. La política de *output caching* de ASP.NET Core permite añadir un valor a la clave con `VaryByValue`. Con un tenant que llega en una cabecera `X-Tenant`, un endpoint sin `VaryBy` y otro con él:

```csharp
builder.Services.AddOutputCache(options =>
{
    options.AddPolicy("PorTenant", p => p.Expire(TimeSpan.FromSeconds(60))
        .VaryByValue(ctx => new KeyValuePair<string, string>("tenant",
            ctx.Request.Headers["X-Tenant"].ToString())));
    options.AddPolicy("SinVary", p => p.Expire(TimeSpan.FromSeconds(60)));
});

app.UseOutputCache();
app.MapGet("/api/dashboard-mal", (HttpContext http) => $"panel de {http.Request.Headers["X-Tenant"]}")
   .CacheOutput("SinVary");
app.MapGet("/api/dashboard-bien", (HttpContext http) => $"panel de {http.Request.Headers["X-Tenant"]}")
   .CacheOutput("PorTenant");
```

```bash
curl -s -H "X-Tenant: acme"   localhost:6431/api/dashboard-mal     # panel de acme
curl -s -H "X-Tenant: globex" localhost:6431/api/dashboard-mal     # panel de acme  (fuga)
curl -s -H "X-Tenant: acme"   localhost:6431/api/dashboard-bien    # panel de acme
curl -s -H "X-Tenant: globex" localhost:6431/api/dashboard-bien    # panel de globex
```

Sin `VaryByValue`, `globex` recibe el panel de `acme` durante todo el tiempo de vida de la entrada. La política por defecto del *output caching* ya incluye el host en la clave, de modo que con tenant por subdominio las respuestas ya se separan; el peligro está en los tenants que se identifican por cabecera, ruta o *claim* del token.

## Fugas por el lateral

El filtro por `TenantId` protege las consultas; los datos de un tenant también salen por otros canales.

### Dónde puede fugarse un dato

| Canal | Cómo se fuga | Defensa | Dónde se trata |
|---|---|---|---|
| Consulta | Una consulta sin filtro por `TenantId` | Filtro automático por fila | [Aislamiento por Fila](Aislamiento-por-Fila.md) |
| Caché | Clave sin el tenant | `TenantCache` como único acceso; `VaryBy` en la caché de salida | Sección Caché |
| Log | Línea sin tenant, o con datos de otro tenant | *Scope* con `TenantId`; no volcar entidades completas | Sección Fugas por el lateral |
| Fichero | Carpeta común, ruta con `..` o nombre controlado por quien sube el fichero | Ruta por tenant y comprobación de que no sale de ella | Sección Fugas por el lateral |
| Cola o trabajo | El trabajo corre sin tenant o con el de otro | El trabajo lleva su `TenantId` y fija el contexto | [Tenant Context](Tenant-Context.md) |
| Correo y enlaces | Enlace o remitente del tenant equivocado | Generar el enlace desde el tenant del mensaje | Sección Fugas por el lateral |
| Informe y exportación | Consulta sin filtro, o con `IgnoreQueryFilters` | Misma consulta filtrada; la excepción es explícita y auditada | [Aislamiento por Fila](Aislamiento-por-Fila.md) |
| Búsqueda e índice | Un índice compartido sin filtro por tenant | Filtro por tenant obligatorio en cada consulta al índice | Sección Fugas por el lateral |

### Logs con el tenant en cada línea

Un *scope* de `ILogger` añade datos a todas las líneas escritas dentro de él. Abierto al resolver el tenant (por ejemplo en un *middleware*), cada línea de la petición lleva el `TenantId`:

```csharp
using (log.BeginScope("TenantId={TenantId}", tenantId))
{
    log.LogInformation("Pedido {OrderId} creado", 1001);
    log.LogWarning("Pago rechazado en el pedido {OrderId}", 1001);
}
```

```text
info: Orders[0] => TenantId=acme Pedido 1001 creado
warn: Orders[0] => TenantId=acme Pago rechazado en el pedido 1001
info: Orders[0] => TenantId=globex Pedido 1001 creado
warn: Orders[0] => TenantId=globex Pago rechazado en el pedido 1001
info: Orders[0] Línea fuera de scope
```

Con el `TenantId` en cada línea, investigar una incidencia es filtrar por tenant; sin él, el mismo `Pedido 1001` es indistinguible entre clientes. La última línea muestra lo que ocurre fuera del *scope*: sin tenant. El proveedor de consola necesita `IncludeScopes = true` para mostrar los *scopes*. Además, el log no debe volcar entidades completas ni datos de un tenant en el registro de otro: se registra el identificador, no el contenido.

Las métricas por tenant llevan el tenant como etiqueta, con cuidado: cada valor distinto crea una serie nueva, y con miles de tenants la cardinalidad se dispara; en ese caso se etiqueta por plan o por tramo de tamaño.

### Ficheros: la ruta con `..`

Con un almacenamiento por tenant, la ruta se construye con el `TenantId` (`storage/acme/factura-1001.pdf`, o un contenedor por tenant en un almacenamiento en la nube). La trampa es que el nombre del fichero lo controla quien lo sube o lo pide: `../globex/factura-2002.pdf` sale de la carpeta de `acme` y entra en la de `globex`. La comprobación resuelve la ruta completa y verifica que sigue dentro de la carpeta del tenant:

```csharp
public static string Resolve(string tenantId, string fileName)
{
    var tenantRoot = Path.GetFullPath(Path.Combine(Root, tenantId)) + Path.DirectorySeparatorChar;
    var full = Path.GetFullPath(Path.Combine(tenantRoot, fileName));
    if (!full.StartsWith(tenantRoot, StringComparison.OrdinalIgnoreCase))
        throw new InvalidOperationException($"Ruta fuera del espacio del tenant: {fileName}");
    return full;
}
```

```text
factura-1001.pdf             -> C:\Users\...\storage-demo\acme\factura-1001.pdf
../globex/factura-2002.pdf   -> Ruta fuera del espacio del tenant: ../globex/factura-2002.pdf
sub/../../globex/x.pdf       -> Ruta fuera del espacio del tenant: sub/../../globex/x.pdf
```

Sin la comprobación, `Path.GetFullPath(Path.Combine(Root, "acme", "../globex/factura-2002.pdf"))` devuelve `...\storage-demo\globex\factura-2002.pdf`. La separación final (`DirectorySeparatorChar`) en la carpeta del tenant evita que `acme-2` pase por una carpeta que solo empieza igual que `acme`. En Linux la comparación de rutas distingue mayúsculas; `OrdinalIgnoreCase` es la opción segura en Windows y conservadora en Linux.

### Correo, enlaces y mensajes de error

Los enlaces de un correo se generan desde el tenant del mensaje, no del contexto de quien lo envía: `https://acme.miapp.ejemplo.com/orders/1001` para `acme`. Un correo enviado desde un trabajo en segundo plano sin contexto de tenant sale con el dominio equivocado o sin tenant. Del mismo modo, los mensajes de error no incluyen datos de otro tenant: un `404` con «el pedido 1001 pertenece a otro cliente» confirma que existe; la respuesta correcta es la misma que para un pedido que no existe.

## Informes entre tenants y tenants especiales

**Informes y consultas entre tenants.** La plataforma necesita a veces ver todos los tenants (facturación, estadísticas de uso). Ese acceso va por un permiso de administración de la plataforma, solo en el panel `admin.miapp.ejemplo.com`, explícito en el código y auditado (quién consultó qué y cuándo). La forma de saltarse el filtro por fila (`IgnoreQueryFilters`) y por qué debe ser excepcional se explica en [Aislamiento por Fila](Aislamiento-por-Fila.md).

**Un tenant con datos propios muy grandes.** Cuando un tenant tiene un volumen o unas necesidades (retención, cifrado, ventanas de mantenimiento) muy distintos del resto, lo habitual es moverlo a su propia base de datos en lugar de complicar la base compartida; el criterio y el coste de esa decisión están en [Estrategias de Aislamiento](Estrategias-de-Aislamiento.md).

### Cuándo NO complicarse

Con pocos tenants de tamaño parecido, un límite global de peticiones y una caché con prefijo de tenant bastan. Las colas por tenant, los límites por plan y la base dedicada se justifican cuando un tenant concreto ya ha causado un problema medible, no antes.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| Un tenant ve un producto, un precio o un panel de otro | Clave de caché sin el tenant, o respuesta cacheada sin `VaryBy` |
| Los trabajos de los demás tenants tardan horas cuando uno lanza una importación | Cola compartida sin reparto por tenant |
| Un tenant nuevo aparece con tema, idioma o moneda que nadie eligió, y todos cambian a la vez | Configuración global heredada como valor por defecto |
| Un fichero subido por un tenant aparece en la carpeta o la descarga de otro | Ficheros en una carpeta común, o ruta construida con un nombre sin validar |
| No se puede saber qué cliente provocó un error | Logs sin `TenantId` en el *scope* |
| Un correo enviado desde un trabajo lleva el enlace de otro tenant | El trabajo no fijó el contexto antes de generar el enlace |

## Buenas prácticas avanzadas

- **Haz que el prefijo del tenant sea imposible de olvidar.** Una regla de revisión no basta: `TenantCache` es la única clase que recibe `IMemoryCache` o `IDistributedCache`, y un test arquitectónico o una revisión de dependencias falla si otra la inyecta.
- **Limita por tenant y por operación cara.** Un límite global de peticiones por tenant no distingue una lectura barata de una exportación de millones de filas: los endpoints caros tienen su propia política con un límite mucho más bajo.
- **Reparte el trabajo en segundo plano por tenant desde el primer día.** Cambiar una cola compartida por una por tenant cuando ya hay clientes grandes obliga a migrar trabajos pendientes; con un `Channel<T>` por tenant o una tabla de trabajos con `TenantId` es barato desde el principio.
- **Responde con `429` y `Retry-After`, no con un error genérico.** Los clientes bien hechos esperan y reintentan; sin la cabecera, reintentan de inmediato y empeoran el ruido que se quería contener.
- **Invalida la configuración al guardarla, no al caducar.** Si la pantalla de ajustes del tenant no llama a `Invalidate`, el cambio tarda hasta el tiempo de vida de la caché en verse; es el origen de «he cambiado el logo y sigue el antiguo».
- **Etiqueta con cardinalidad acotada.** El `TenantId` como etiqueta de métrica sirve con decenas de tenants; con miles, agrupa por plan.

## Documentación oficial

- [Limitación de velocidad en ASP.NET Core](https://learn.microsoft.com/aspnet/core/performance/rate-limit) — la sección sobre particiones (`PartitionedRateLimiter`) y sobre `OnRejected` con `Retry-After`; es la referencia para ajustar algoritmos y políticas con nombre.
- [Antipatrón Noisy Neighbor (Azure Architecture Center)](https://learn.microsoft.com/azure/architecture/antipatterns/noisy-neighbor/noisy-neighbor) — define el problema, cómo detectarlo y las medidas de gobierno de recursos; útil al decidir cuándo pasar a un tenant a recursos dedicados.

---

*En resumen: aislados los datos, la convivencia exige que ningún tenant agote lo compartido y que nada (una caché, un log, un fichero, una cola) lleve datos de un tenant a otro.*
