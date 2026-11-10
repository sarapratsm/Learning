# [Authorize] y [AllowAnonymous]

## ¿Qué es?

`[Authorize]` es el atributo que protege un endpoint: solo deja pasar a las peticiones autenticadas y, opcionalmente, a las que cumplan ciertos roles o políticas. `[AllowAnonymous]` es su contrario: abre una excepción para que pase cualquiera. Ambos viven en `Microsoft.AspNetCore.Authorization`, y el framework los aplica **antes** de que se ejecute el código de la acción.

## ¿Por qué existe?

Casi ninguna API es del todo pública: el catálogo lo ve cualquiera, pero «mis pedidos» exige saber quién eres y borrar un producto exige un perfil concreto. Sin un mecanismo declarativo habría que comprobar la identidad y los permisos a mano al inicio de cada método, y bastaría olvidarse de una comprobación para dejar un endpoint abierto. El atributo declara la regla **encima** del endpoint y el framework la hace cumplir.

> Si vienes de SQL, piensa en `[Authorize]` como un `GRANT` sobre el endpoint: la regla vive en el objeto protegido, no en las consultas que lo usan.

Hay dos preguntas distintas que no conviene mezclar, y ASP.NET Core las resuelve en dos etapas:

| Etapa | Pregunta | Middleware | Resultado si falla |
|---|---|---|---|
| Autenticación | ¿Quién eres? | `UseAuthentication()` | `401 Unauthorized` |
| Autorización | ¿Puedes hacer esto? | `UseAuthorization()` | `403 Forbidden` (o `401` si no hay identidad) |

La diferencia conceptual está en [Autenticación vs Autorización](../../seguridad/autenticacion-y-autorizacion/Autenticacion-vs-Autorizacion.md), y el formato del token que se usa aquí, en [JWT](../../seguridad/autenticacion-y-autorizacion/JWT.md). Esta ficha se centra en cómo se declara y se comprueba el acceso en ASP.NET Core.

## ¿Cuándo y para qué se usa?

En una tienda online (`Tienda.Api`, con las rutas `/api/productos` y `/api/pedidos`) hay tres roles: `Cliente`, `Empleado` y `Administrador` (los mismos que en [RBAC y Claims](../../seguridad/autenticacion-y-autorizacion/RBAC-y-Claims.md)). El catálogo es público, el pedido #4711 solo lo ve su cliente o el personal de la tienda, y borrar un producto es cosa del `Administrador`. Cada una de esas reglas se expresa con un atributo, una política o una comprobación sobre el recurso, según lo fina que sea.

Las salidas citadas provienen de `Tienda.Api` (.NET SDK 10.0.401, `Microsoft.AspNetCore.Authentication.JwtBearer` 10.0.14) ejecutado el 2026-11-10 y atacado con `curl`. Donde el texto abrevia un fichero, lo indica.

## Puesta en marcha: JWT de prueba y primer endpoint protegido

Para que `[Authorize]` tenga algo que comprobar hace falta un mecanismo de autenticación. Aquí se usa un JWT firmado con clave simétrica; el esquema `Bearer` lee el token de la cabecera `Authorization: Bearer <token>`.

```csharp
// Program.cs (abreviado: sin los registros de política ni de controladores, que aparecen más abajo)
var clave = new SymmetricSecurityKey(
    Encoding.UTF8.GetBytes("clave-de-prueba-solo-para-desarrollo-32+bytes!")); // solo para pruebas

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o => o.TokenValidationParameters = new TokenValidationParameters
    {
        ValidIssuer = "Tienda.Api",
        ValidAudience = "Tienda.Clientes",
        IssuerSigningKey = clave
    });
builder.Services.AddAuthorization();

var app = builder.Build();
app.UseAuthentication();   // 1.º: construye el usuario a partir del token
app.UseAuthorization();    // 2.º: decide si ese usuario puede entrar
```

Para probar sin un servidor de identidad, un endpoint de desarrollo emite tokens con `JwtSecurityTokenHandler` (nunca debe llegar a producción):

```csharp
app.MapPost("/dev/token", (string sub, string rol) =>
{
    var claims = new List<Claim> { new("sub", sub), new("name", sub), new("role", rol) };
    var token = new JwtSecurityToken("Tienda.Api", "Tienda.Clientes", claims,
        expires: DateTime.UtcNow.AddMinutes(15),
        signingCredentials: new SigningCredentials(clave, SecurityAlgorithms.HmacSha256));
    return new { access_token = new JwtSecurityTokenHandler().WriteToken(token) };
}).AllowAnonymous();
```

Y un endpoint que exige estar autenticado:

```csharp
app.MapGet("/api/estado", () => "ok").RequireAuthorization();
```

Qué responde, sin token, con un token válido y con un token manipulado (`$ANA` es el token de `ana`, rol `Cliente`):

```text
$ curl -i http://localhost:6750/api/estado
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer

$ curl -i -H "Authorization: Bearer $ANA" http://localhost:6750/api/estado
HTTP/1.1 200 OK

$ curl -i -H "Authorization: Bearer ${ANA}x" http://localhost:6750/api/estado
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer error="invalid_token", error_description="The signature key was not found"
```

La cabecera `WWW-Authenticate` es la forma que tiene el servidor de decir «autentícate así». Cuando el token existe pero no vale, añade `error="invalid_token"` y el motivo.

## 401 frente a 403

Los dos códigos responden a preguntas diferentes, y confundirlos hace que el cliente reaccione mal:

| Código | Significado | Qué debe hacer el cliente |
|---|---|---|
| `401 Unauthorized` | No se sabe quién eres: falta el token, está mal firmado o caducó | Volver a autenticarse (o renovar el token) |
| `403 Forbidden` | Se sabe quién eres, pero no tienes permiso | Nada: reautenticarse no cambia el resultado |

Se ve con el mismo endpoint de borrado, llamado por distintos roles (`$ADM` es el token de un `Administrador`):

```csharp
[Authorize(Roles = "Administrador")]
[HttpDelete("{id:int}")]
public IActionResult Borrar(int id) => NoContent();
```

```text
$ curl -i -X DELETE http://localhost:6750/api/productos/5
HTTP/1.1 401 Unauthorized                 <- sin token: no sabe quién eres

$ curl -i -X DELETE -H "Authorization: Bearer $ANA" http://localhost:6750/api/productos/5
HTTP/1.1 403 Forbidden                    <- ana es Cliente: sabe quién es, no puede

$ curl -i -X DELETE -H "Authorization: Bearer $ADM" http://localhost:6750/api/productos/5
HTTP/1.1 204 No Content
```

Un token caducado es un `401`, no un `403`, y el mensaje lo dice:

```text
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer error="invalid_token", error_description="The token expired at '11/10/2026 09:48:54'"
```

La respuesta `403` de `[Authorize]` no lleva cuerpo (`Content-Length: 0`): si el cliente necesita un motivo legible, hay que personalizarlo (ver «Buenas prácticas avanzadas»).

## Los atributos, caso por caso

### `[Authorize]` en la acción y en la clase

Puesto en una acción, protege solo esa acción. Puesto en la clase, protege todas sus acciones:

```csharp
[Authorize]
[ApiController]
[Route("api/pedidos")]
public class PedidosController : ControllerBase
{
    [HttpGet("{id:int}")]
    public IActionResult Obtener(int id) => ...;   // exige estar autenticado
}
```

Sin token, `GET /api/pedidos/4711` devuelve `401`; con un token válido pasa.

### `[AllowAnonymous]`: una excepción dentro de una clase protegida

```csharp
[Authorize]                                  // toda la clase protegida...
public class PedidosController : ControllerBase
{
    [AllowAnonymous]                         // ...salvo esta acción
    [HttpGet("publico")]
    public IActionResult Publico() => Ok("estados de pedido");
}
```

```text
$ curl -i http://localhost:6750/api/pedidos/publico
HTTP/1.1 200 OK
```

`[AllowAnonymous]` gana siempre sobre cualquier `[Authorize]`, incluido el heredado de la clase o impuesto por una política por defecto. Por eso es el atributo que más conviene revisar.

### Roles: `[Authorize(Roles = "...")]`

Una lista separada por comas es un **O**: basta con tener uno de los roles. Varios atributos apilados son un **Y**: hay que cumplirlos todos.

```csharp
[Authorize(Roles = "Empleado,Administrador")]      // O: cualquiera de los dos
[HttpGet("gestion")]
public IActionResult Gestion() => Ok("gestión");

[Authorize(Roles = "Empleado")]                    // Y: ser Empleado
[Authorize(Roles = "Administrador")]               //    y además Administrador
[HttpGet("auditoria")]
public IActionResult Auditoria() => Ok("auditoría");
```

```text
$ curl -i -H "Authorization: Bearer $EMP" http://localhost:6750/api/pedidos/gestion
HTTP/1.1 200 OK

$ curl -i -H "Authorization: Bearer $ADM" http://localhost:6750/api/pedidos/auditoria
HTTP/1.1 403 Forbidden           <- un Administrador sin el rol Empleado no cumple el Y
```

### Políticas: reglas más finas que un rol

Una **política** es una regla con nombre registrada en el arranque, que luego se referencia desde el atributo. `AddAuthorizationBuilder()` (desde .NET 7) permite encadenarlas:

```csharp
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("PlanPremium", p => p.RequireClaim("plan", "premium"))
    .AddPolicy("EsPersonal", p => p.RequireAssertion(ctx =>
        ctx.User.IsInRole("Empleado") || ctx.User.IsInRole("Administrador")));
```

- `RequireClaim("plan", "premium")` exige un *claim* concreto con ese valor.
- `RequireAssertion` recibe el contexto y devuelve `true` o `false`: sirve para reglas pequeñas que combinan varias condiciones sin escribir una clase.

Se usan desde el atributo o, en Minimal APIs, con `RequireAuthorization("nombre")`:

```csharp
[Authorize(Policy = "EsPersonal")]
[HttpGet]
public IActionResult Listar() => Ok(store.Pedidos);
```

```csharp
app.MapGet("/api/premium", () => "premium").RequireAuthorization("PlanPremium");
```

```text
$ curl -i -H "Authorization: Bearer $ANA" http://localhost:6750/api/pedidos       # Cliente
HTTP/1.1 403 Forbidden
$ curl -i -H "Authorization: Bearer $EMP" http://localhost:6750/api/pedidos       # Empleado
HTTP/1.1 200 OK
$ curl -i -H "Authorization: Bearer $ANA" http://localhost:6750/api/premium       # sin claim plan
HTTP/1.1 403 Forbidden
$ curl -i -H "Authorization: Bearer $PREM" http://localhost:6750/api/premium      # plan=premium
HTTP/1.1 200 OK
```

### Minimal APIs: `RequireAuthorization()` y `AllowAnonymous()`

Una Minimal API no tiene clases donde colgar atributos; usa métodos encadenados sobre el endpoint, con el mismo efecto:

```csharp
app.MapGet("/api/estado", () => "ok").RequireAuthorization();      // = [Authorize]
app.MapGet("/api/salud",  () => "sano").AllowAnonymous();          // = [AllowAnonymous]
app.MapGroup("/api/pedidos").RequireAuthorization();               // protege todo un grupo
```

Los atributos también funcionan sobre una lambda: `app.MapGet("/x", [Authorize] () => "...")`. Sin ejecutar en las pruebas: `MapGroup(...).RequireAuthorization()` y los atributos sobre lambdas; sí se ejecutaron `RequireAuthorization()`, `RequireAuthorization("PlanPremium")` y `AllowAnonymous()` sobre endpoints sueltos.

## Autorización basada en recursos: «un cliente solo ve su pedido»

Un rol responde «¿puede esta persona ver pedidos?»; no responde «¿puede ver **este** pedido?». Esa segunda pregunta necesita el objeto y se comprueba en código con `IAuthorizationService`.

❌ Solo con `[Authorize]`: cualquier cliente autenticado puede leer el pedido de otro cliente cambiando el id de la URL (un fallo conocido como acceso directo inseguro a objetos, IDOR):

```csharp
[HttpGet("inseguro/{id:int}")]
public IActionResult Inseguro(int id) =>
    store.Pedidos.FirstOrDefault(p => p.Id == id) is { } p ? Ok(p) : NotFound();
```

```text
$ curl -i -H "Authorization: Bearer $LUIS" http://localhost:6750/api/pedidos/inseguro/4711
HTTP/1.1 200 OK
{"id":4711,"clienteId":"ana","total":59.90}         <- luis lee el pedido de ana
```

✅ Con un requisito y un *handler* que recibe el recurso. Primero el requisito y su comprobación (`Pedido` es la entidad del pedido, con `Id`, `ClienteId` y `Total`):

```csharp
public class MismoClienteRequirement : IAuthorizationRequirement;

public class PedidoAuthorizationHandler : AuthorizationHandler<MismoClienteRequirement, Pedido>
{
    protected override Task HandleRequirementAsync(AuthorizationHandlerContext context,
        MismoClienteRequirement requirement, Pedido pedido)
    {
        var esPersonal = context.User.IsInRole("Empleado") || context.User.IsInRole("Administrador");
        var esDueno = context.User.FindFirstValue(ClaimTypes.NameIdentifier) == pedido.ClienteId;
        if (esPersonal || esDueno) context.Succeed(requirement);
        return Task.CompletedTask;
    }
}
```

Se registra el requisito como política y el *handler* en el contenedor de dependencias:

```csharp
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("PuedeVerPedido", p => p.Requirements.Add(new MismoClienteRequirement()));
builder.Services.AddSingleton<IAuthorizationHandler, PedidoAuthorizationHandler>();
```

Y la acción carga el pedido, pregunta por él y responde en consecuencia:

```csharp
[HttpGet("{id:int}")]
public async Task<IActionResult> Obtener(int id)
{
    var pedido = store.Pedidos.FirstOrDefault(p => p.Id == id);
    if (pedido is null) return NotFound();

    var resultado = await authz.AuthorizeAsync(User, pedido, "PuedeVerPedido");
    if (!resultado.Succeeded) return Forbid();

    return Ok(pedido);
}
```

```text
$ curl -i -H "Authorization: Bearer $LUIS" http://localhost:6750/api/pedidos/4711
HTTP/1.1 403 Forbidden
$ curl -i -H "Authorization: Bearer $ANA" http://localhost:6750/api/pedidos/4711
HTTP/1.1 200 OK        {"id":4711,"clienteId":"ana","total":59.90}
$ curl -i -H "Authorization: Bearer $EMP" http://localhost:6750/api/pedidos/4711
HTTP/1.1 200 OK        <- el personal ve cualquier pedido
```

`IAuthorizationService` se inyecta como cualquier servicio (aquí por constructor primario). `Forbid()` produce el `403` con el esquema de autenticación configurado.

## Cerrar por defecto: política por defecto y `FallbackPolicy`

Con `[Authorize]` por controlador, basta olvidarlo en uno para dejarlo abierto. La alternativa es exigir autenticación en **todo** endpoint que no declare nada, con la *fallback policy*:

```csharp
builder.Services.AddAuthorizationBuilder()
    .SetFallbackPolicy(new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build());
```

Con ella, `GET /api/productos` (sin atributo alguno) pasa a exigir token, y solo lo marcado con `[AllowAnonymous]` o `.AllowAnonymous()` queda abierto:

```text
$ curl -i http://localhost:6752/api/productos                  # sin atributos
HTTP/1.1 401 Unauthorized
$ curl -i http://localhost:6752/api/pedidos/publico            # [AllowAnonymous]
HTTP/1.1 200 OK
$ curl -i http://localhost:6752/api/salud                      # .AllowAnonymous() en Minimal API
HTTP/1.1 200 OK
```

Hay dos políticas con nombre parecido que no se deben confundir:

| Política | Se aplica cuando... | Se configura con |
|---|---|---|
| Por defecto (`DefaultPolicy`) | El endpoint tiene `[Authorize]` sin argumentos | `SetDefaultPolicy(...)` |
| Alternativa (`FallbackPolicy`) | El endpoint **no** tiene ningún metadato de autorización | `SetFallbackPolicy(...)` |

La política por defecto cambia qué significa un `[Authorize]` pelado (por ejemplo, exigir además un claim); la *fallback* es la que convierte «todo abierto salvo lo marcado» en «todo cerrado salvo lo marcado». `SetDefaultPolicy` no se ejecutó en las pruebas; la descripción sigue la documentación oficial.

## Cómo se leen los claims: `role` frente a `ClaimTypes.Role`

`IsInRole("Administrador")` y `[Authorize(Roles = ...)]` buscan un claim cuyo **tipo** sea el que la identidad declara como «tipo de rol», por defecto `ClaimTypes.Role` (`http://schemas.microsoft.com/ws/2008/06/identity/claims/role`). Pero un JWT lleva el claim con el nombre corto `role`. El puente es el **mapeo de claims entrantes** (`MapInboundClaims`, activado por defecto), que traduce nombres cortos a los largos de .NET.

Con el mapeo por defecto, un token con `role = Administrador` produce estos claims (consulta de un endpoint de diagnóstico que lista `User.Claims`):

```text
"nombre": null, "esAdmin": true,
claims: [
  "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier = root",   <- era "sub"
  "name = root",                                                                   <- sin traducir
  "http://schemas.microsoft.com/ws/2008/06/identity/claims/role = Administrador",  <- era "role"
  ...
]
```

Dos detalles de esa salida: `sub` y `role` se traducen, pero `name` no, así que `User.Identity.Name` es `null` aunque el token lleve `name`.

Al desactivar el mapeo (`o.MapInboundClaims = false`, lo habitual cuando se quiere trabajar con los nombres del estándar) el efecto es el contrario y silencioso: el claim sigue llamándose `role`, `IsInRole` no lo encuentra y el administrador recibe `403` en un endpoint que antes le dejaba pasar:

```text
"nombre": null, "esAdmin": false,
claims: [ "sub = root", "name = root", "role = Administrador", ... ]

$ curl -i -X DELETE -H "Authorization: Bearer $ADM" http://localhost:6751/api/productos/5
HTTP/1.1 403 Forbidden           <- con MapInboundClaims = false y sin más configuración
```

La solución es decir a la validación qué claims son el nombre y el rol:

```csharp
.AddJwtBearer(o =>
{
    o.MapInboundClaims = false;
    o.TokenValidationParameters.RoleClaimType = "role";
    o.TokenValidationParameters.NameClaimType = "name";
    // ...resto de TokenValidationParameters
});
```

```text
"nombre": "root", "esAdmin": true       -> DELETE con el token del administrador: 204 No Content
```

## Errores frecuentes

| Síntoma | Causa y arreglo |
|---|---|
| `500` con `InvalidOperationException: No authenticationScheme was specified, and there was no DefaultChallengeScheme found. The default schemes can be set using either AddAuthentication(string defaultScheme) or AddAuthentication(Action<AuthenticationOptions> configureOptions).` | Hay `[Authorize]` pero no se llamó a `AddAuthentication(...)`: ningún esquema sabe cómo responder al `401`. Registra el esquema (`AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(...)`). Solo falla en los endpoints protegidos; los públicos siguen respondiendo `200`. |
| `500` con `InvalidOperationException: Endpoint HTTP: GET /api/estado contains authorization metadata, but a middleware was not found that supports authorization.` | Se llamó a `UseRouting()` explícitamente y falta `UseAuthorization()` entre `UseRouting` y el mapeo de endpoints. |
| `401` con un token válido en un endpoint `[Authorize]` | El orden de los middleware: `UseAuthorization()` se ejecuta antes que `UseAuthentication()` y evalúa la petición sin usuario. Con `app.UseAuthorization(); app.UseAuthentication();` el mismo token válido que daba `200` pasó a dar `401`. |
| `403` a un usuario que sí tiene el rol en el token | El claim del rol no coincide con el tipo que espera la identidad: `MapInboundClaims = false` sin `RoleClaimType = "role"` (ver la sección anterior). |
| `401` con `error_description="The signature key was not found"` | El token se firmó con otra clave, o se alteró; no es un problema de permisos. |
| Un token recién caducado todavía pasa | La validación de JWT tolera 5 minutos de desfase de reloj (`ClockSkew`). Un token que caducó hace un minuto sigue dando `200`; uno caducado hace diez da `401` con `The token expired at '...'`. |
| `User.Identity.Name` es `null` con un token que lleva `name` | El mapeo por defecto no traduce `name`; configura `NameClaimType` o lee `User.FindFirstValue("name")`. |
| El endpoint «protegido» responde `200` sin token | Hay un `[AllowAnonymous]` en la acción que gana al `[Authorize]` de la clase, o el endpoint no tiene ningún `[Authorize]` y no hay `FallbackPolicy`. |

En .NET 10, con `WebApplication`, **omitir** `UseAuthentication()` o `UseAuthorization()` no rompe nada mientras no se llame a `UseRouting()` a mano: el host los añade solos si hay servicios de autenticación y de autorización registrados. Se comprobó quitando cada llamada por separado: `/api/estado` siguió devolviendo `401` sin token y `200` con token. Esa red de seguridad desaparece en cuanto el orden se escribe a mano de forma incorrecta (ver la tabla) o se usa `UseRouting()` sin `UseAuthorization()`; por eso conviene escribir siempre ambas llamadas, en el orden correcto.

## Buenas prácticas avanzadas

- **Combina rol y recurso, no los sustituyas.** `[Authorize(Roles = "Cliente")]` deja pasar a cualquier cliente; la comprobación `AuthorizeAsync(User, pedido, ...)` decide cuál de sus pedidos ve. Quien confía solo en el rol tiene una IDOR en cada ruta con id.
- **Cierra por defecto con `FallbackPolicy` y audita los `[AllowAnonymous]`.** El fallo típico de seguridad no es una regla mal escrita, sino un endpoint nuevo al que nadie le puso atributo. Con la política de reserva, olvidarse cierra; sin ella, abre.
- **Decide con claims que emitió el servidor, no con datos de la petición.** Los roles y el id del cliente salen del token firmado; un `clienteId` leído de la URL o del cuerpo se compara con el claim, nunca lo sustituye.
- **Un `403` sin cuerpo no ayuda al cliente que consume la API.** Si el contrato de la API usa `ProblemDetails` ([REST](../../arquitectura-de-software/tipos-de-apis/REST.md)), personaliza la respuesta con `AuthenticationSchemeOptions.Events` (`OnForbidden`, `OnChallenge` en JwtBearer) o un `IAuthorizationMiddlewareResultHandler` propio, en lugar de devolver cuerpos distintos desde cada acción.
- **Devuelve `404` en vez de `403` cuando existir ya es información.** Si un cliente pide el pedido de otra persona, un `403` confirma que ese id existe. Para recursos sensibles, la acción puede responder `404` tanto al inexistente como al ajeno, usando el mismo `AuthorizeAsync` y cambiando solo el código devuelto.
- **Pasa `AllowAnonymous` por un revisor de código, no solo por el compilador.** Un atributo en una clase base o en un controlador heredado abre todas las acciones derivadas sin que se vea en ellas; busca `AllowAnonymous` en cada revisión de seguridad.

## Documentación oficial

- [Introducción a la autorización en ASP.NET Core](https://learn.microsoft.com/aspnet/core/security/authorization/introduction) — el punto de entrada: cómo se relacionan atributo, política y requisito.
- [Autorización basada en políticas](https://learn.microsoft.com/aspnet/core/security/authorization/policies) — `AddPolicy`, `FallbackPolicy` y la política por defecto, con todas las opciones del builder.
- [Autorización basada en recursos](https://learn.microsoft.com/aspnet/core/security/authorization/resourcebased) — `IAuthorizationService` y los *handlers* que reciben el recurso.
- [Autenticación con JWT Bearer](https://learn.microsoft.com/aspnet/core/security/authentication/configure-jwt-bearer-authentication) — configuración del esquema y de `TokenValidationParameters`, incluido el mapeo de claims.

---

*En resumen: `[Authorize]` declara quién puede entrar y `[AllowAnonymous]` abre huecos puntuales; el `401` significa «no sé quién eres» y el `403` «sé quién eres y no puedes», un rol no dice si el pedido es tuyo (para eso está `IAuthorizationService`), y una `FallbackPolicy` convierte «protegido si me acuerdo» en «protegido salvo lo que abro a propósito».*
