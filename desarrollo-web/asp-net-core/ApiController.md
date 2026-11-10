# [ApiController]

## ¿Qué es?

`[ApiController]` es un atributo que se pone sobre la clase de un controlador (o sobre el ensamblado entero) para activar un paquete de convenciones pensadas para APIs HTTP: validación automática del modelo con respuesta `400`, inferencia del origen de cada parámetro, obligación de usar *attribute routing* y errores en formato `ProblemDetails`. No añade endpoints ni serializa nada: cambia cómo MVC trata las acciones de esa clase antes y después de ejecutarlas.

## ¿Por qué existe?

Una API que recibe un `CrearPedidoRequest` repite en cada acción el mismo andamiaje: comprobar `ModelState.IsValid`, devolver `BadRequest(ModelState)`, anotar con `[FromBody]` el parámetro que viene en el cuerpo, dar el mismo formato a todos los errores. Es código idéntico en cien acciones, y el día que se olvida en una, esa acción acepta datos inválidos sin avisar.

`[ApiController]` mueve ese andamiaje al framework. Funciona como un *filter* y unas convenciones que MVC aplica al arrancar y en cada petición, de modo que la acción solo contiene la lógica del endpoint.

> Si conoces los atributos como mecanismo del lenguaje ([ver ficha de Atributos](../../lenguajes/csharp-dotnet/caracteristicas-del-lenguaje/Atributos.md)), este es un caso típico: una etiqueta inerte que el framework lee por reflection al construir el modelo de controladores.

## ¿Cuándo y para qué se usa?

En cualquier controlador que sirva una API: la de una tienda online que expone `/api/productos` y `/api/pedidos` a una SPA, a una app móvil o a otros servicios. La convención habitual es ponerlo en todos los controladores de la API (o una vez a nivel de ensamblado, ver más abajo). No se usa en controladores que devuelven vistas HTML: ahí el cliente es un navegador, no un consumidor de JSON.

Qué estilos de programación web ofrece el framework y dónde encaja esta opción se explica en [Modelos de programación web](Modelos-de-programacion-web.md). Qué es una API REST, en [REST](../../arquitectura-de-software/tipos-de-apis/REST.md).

Las salidas citadas provienen de un proyecto `Tienda.Api` (`dotnet new webapi --use-controllers`, SDK de .NET 10.0.401, `net10.0`) ejecutado el 2026-11-10 y atacado con `curl`. Los `curl` muestran solo el código de estado, la cabecera `Content-Type` y el cuerpo; se omiten `Date`, `Server` y `Transfer-Encoding`. El valor de `traceId` cambia en cada petición, y el puerto (`6700` en los comandos) varía de un ejemplo a otro. Las salidas de arranque y de `Controller` provienen de proyectos auxiliares del mismo SDK, cuyo ensamblado y nombres de acción (`Api2`, `Api3`, `A`) aparecen en los mensajes. Se ejecutaron: validación, binding, `415`, `404`, origen inferido de `ILogger<T>`, atributo de ensamblado, las cinco opciones de `ApiBehaviorOptions` indicadas como ejecutadas, `Controller` frente a `ControllerBase` y los dos errores de arranque. No se ejecutó la inferencia de `IFormFile` ni la de `[FromServices]` con un servicio propio: la tabla de inferencia sigue la documentación oficial, salvo las filas de tipo complejo, de ruta, de query y de `ILogger<T>`.

## El controlador de referencia

El controlador de los ejemplos, con el mínimo que `[ApiController]` necesita, y el DTO de entrada:

```csharp
using System.ComponentModel.DataAnnotations;

public class CrearPedidoRequest
{
    [Required]
    [EmailAddress]
    public string? EmailCliente { get; set; }

    [Range(1, 100)]
    public int Cantidad { get; set; }
}

public record PedidoResponse(int Id, string EmailCliente, int Cantidad);
```

```csharp
using Microsoft.AspNetCore.Mvc;

[ApiController]
[Route("api/pedidos")]
public class PedidosController : ControllerBase
{
    [HttpPost]
    public IActionResult Crear(CrearPedidoRequest request)
        => Ok(new PedidoResponse(4711, request.EmailCliente!, request.Cantidad));

    [HttpGet("{id:int}")]
    public IActionResult Obtener(int id)
        => id == 4711 ? Ok(new PedidoResponse(4711, "ana@example.com", 2)) : NotFound();

    [HttpGet]
    public IActionResult Listar(int pagina = 1) => Ok(new { pagina });
}
```

Y en `Program.cs`, el registro mínimo de controladores (se mantiene así en todos los ejemplos salvo donde se indique):

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers();
var app = builder.Build();
app.MapControllers();
app.Run();
```

Las reglas de validación (`[Required]`, `[Range]`, `[EmailAddress]`) son [Data Annotations](Validacion-con-DataAnnotations.md); el atributo `[ApiController]` no las define, solo hace que se apliquen solas.

## Qué activa, comportamiento a comportamiento

### 1. Validación automática: un 400 antes de entrar en la acción

Si el modelo de entrada no cumple sus reglas, la acción **no se ejecuta**: un filtro (`ModelStateInvalidFilter`) corta la petición y responde `400` con un `ValidationProblemDetails`.

```bash
curl -i -X POST localhost:6700/api/pedidos \
  -H 'Content-Type: application/json' \
  -d '{"emailCliente":"no-es-email","cantidad":0}'
```

```text
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"Cantidad":["The field Cantidad must be between 1 and 100."],"EmailCliente":["The EmailCliente field is not a valid e-mail address."]},"traceId":"00-98f57af7ed1ee218fd0a059f83f9cabd-78aa99caee4d69cd-00"}
```

El cuerpo sigue el estándar [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) (*Problem Details for HTTP APIs*): `type`, `title` y `status` describen el error, `errors` es un diccionario campo → lista de mensajes y `traceId` es el identificador de la petición para buscarla en los logs. El `Content-Type` es `application/problem+json`, no `application/json`.

Un campo ausente falla igual:

```bash
curl -i -X POST localhost:6700/api/pedidos -H 'Content-Type: application/json' -d '{"cantidad":2}'
```

```text
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"EmailCliente":["The EmailCliente field is required."]},"traceId":"00-61f20f9c44e9934e3eecd965764ae3d9-7a7216561be38d45-00"}
```

Con un cuerpo válido (`{"emailCliente":"ana@example.com","cantidad":2}`) la acción se ejecuta y devuelve `200` con `{"id":4711,"emailCliente":"ana@example.com","cantidad":2}`.

El filtro actúa sobre **todo** el `ModelState`, no solo sobre el cuerpo: también falla si un parámetro simple no se puede convertir. Con `GET /api/pedidos?pagina=abc` (el parámetro es un `int`):

```text
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"pagina":["The value 'abc' is not valid."]},"traceId":"00-5a00a1424d1acf63ef6ac2d64ec9d3c7-955c3d473d2a6232-00"}
```

### 2. Errores de binding: el mismo 400, con mensajes distintos

Cuando el fallo no es de una regla de validación sino de la lectura del JSON, la respuesta tiene la misma forma, pero los mensajes y las claves de `errors` cambian. Con un tipo equivocado (`"cantidad":"dos"` donde se espera un entero):

```text
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"request":["The request field is required."],"$.cantidad":["The JSON value could not be converted to System.Int32. Path: $.cantidad | LineNumber: 0 | BytePositionInLine: 42."]},"traceId":"00-88dc98fcc141bb50a7471730526529f4-14dac66d6ca44922-00"}
```

Con un JSON truncado (`{"emailCliente":`):

```text
{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"request":["The request field is required."],"$.emailCliente":["Expected depth to be zero at the end of the JSON payload. There is an open JSON object or array that should be closed. Path: $.emailCliente | LineNumber: 0 | BytePositionInLine: 16."]},"traceId":"00-c38b9721037fb2396a0a86aca64c772f-331d05b2be4863c4-00"}
```

Y sin cuerpo (`POST` sin `-d`):

```text
{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"":["A non-empty request body is required."],"request":["The request field is required."]},"traceId":"00-353061ac28aa6fd90a14b3d9b590272d-380f302a8132c042-00"}
```

Tres detalles que desconciertan la primera vez:

- La clave `$.cantidad` es la **ruta JSON** del campo problemático (el prefijo `$` es la raíz), no el nombre de una propiedad del DTO.
- Cuando el JSON no se puede leer, el modelo llega `null` y aparece además `"request":["The request field is required."]`: el nombre es el del **parámetro de la acción** (`request`). El mensaje que explica la causa real es el otro.
- El mensaje de `JsonException` incluye `LineNumber` y `BytePositionInLine`, útiles para depurar pero que quizá no quieras exponer a clientes externos (ver «Personalizar» más abajo).

Si el `Content-Type` no es uno que el servidor sepa leer, no es un `400`, es un `415`, también con formato `ProblemDetails`:

```bash
curl -i -X POST localhost:6700/api/pedidos -H 'Content-Type: text/plain' -d 'hola'
```

```text
HTTP/1.1 415 Unsupported Media Type
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.16","title":"Unsupported Media Type","status":415,"traceId":"00-8c53c1aa417088a3c3de663ba3cd4d58-b564bc85b46680ef-00"}
```

Cómo lee el binder cada origen de datos y qué hace con los fallos se explica en [Model binding](Model-Binding.md).

### 3. Inferencia del origen de los parámetros

Sin `[ApiController]`, un parámetro sin atributo se busca en la ruta, la query y el formulario, **nunca en el cuerpo JSON**. Con él, MVC deduce el origen de cada parámetro según su tipo y según la plantilla de ruta:

| Parámetro | Origen inferido |
|---|---|
| Tipo complejo (clase, `record`), p. ej. `CrearPedidoRequest` | `[FromBody]` |
| `IFormFile`, `IFormFileCollection` | `[FromForm]` |
| Nombre que aparece en la plantilla de ruta (`{id}`) | `[FromRoute]` |
| Cualquier otro tipo simple (`int`, `string`, `Guid`...) | `[FromQuery]` |
| Tipo registrado en el contenedor de DI (p. ej. `ILogger<T>`) | `[FromServices]` |

La inferencia de `[FromServices]` existe desde .NET 7 y se puede apagar con `DisableImplicitFromServicesParameters`. La acción siguiente declara un `int` de la ruta, un `string` de la query y un servicio, sin ningún atributo en los parámetros:

```csharp
[HttpGet("origen/{id}")]
public IActionResult Origen(int id, string q, ILogger<PedidosController> log)
    => Ok(new { id, q, log = log.GetType().Name });
```

```text
$ curl localhost:6700/api/pedidos/origen/5?q=x
{"id":5,"q":"x","log":"Logger`1"}
```

Hay una limitación que da errores de arranque. El cuerpo se lee una sola vez, así que solo un parámetro puede venir de él. Con dos tipos complejos en la misma acción:

```csharp
[HttpPost]
public IActionResult Crear(CrearPedidoRequest a, CrearPedidoRequest b) => Ok();
```

la aplicación **no arranca** (la excepción salta en `app.MapControllers()`, al construir el modelo de controladores):

```text
Unhandled exception. System.InvalidOperationException: Action 'Api2.PedidosController.A (Api2)' has more than one parameter that was specified or inferred as bound from request body. Only one parameter per action may be bound from body. Inspect the following parameters, and use 'FromQueryAttribute' to specify bound from query, 'FromRouteAttribute' to specify bound from route, and 'FromBodyAttribute' for parameters to be bound from body:
CrearPedidoRequest a
CrearPedidoRequest b
```

La solución es agrupar los dos objetos en un único DTO, o marcar uno con `[FromQuery]`/`[FromRoute]`.

### 4. Exigencia de attribute routing

Con `[ApiController]`, **cada acción debe tener una ruta por atributo** (`[Route]` en la clase más `[HttpGet]` en el método, o `[HttpGet("api/pedidos")]` completo en el método). Una acción sin ruta por atributo impide arrancar:

```csharp
[ApiController]
public class PedidosController : ControllerBase
{
    public IActionResult Listar() => Ok();   // sin [Route] ni [HttpGet]
}
```

```text
Unhandled exception. System.InvalidOperationException: Action 'Api3.PedidosController.Listar (Api3)' does not have an attribute route. Action methods on controllers annotated with ApiControllerAttribute must be attribute routed.
```

Qué hacen `[Route]`, `[HttpGet]` y las plantillas de ruta se explica en [Enrutado y verbos HTTP](Enrutado-y-Verbos.md). Aquí basta saber que el enrutado convencional (`MapControllerRoute` con un patrón `{controller}/{action}`) no puede servir a un controlador con este atributo.

### 5. ProblemDetails para los códigos de error sin cuerpo

Cuando una acción devuelve un resultado de error sin cuerpo (`NotFound()`, `Unauthorized()`, `Forbid()`...), con `[ApiController]` MVC le añade un `ProblemDetails` (la opción se llama *client error mapping*: asigna a cada código `4xx` un `type` y un `title`). Mismo código, con y sin el atributo:

```bash
curl -i localhost:6700/api/pedidos/9999        # con [ApiController]
```

```text
HTTP/1.1 404 Not Found
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.5","title":"Not Found","status":404,"traceId":"00-634ea1c85252a8497dfd695f2a635923-120ffb869d149c65-00"}
```

```bash
curl -i localhost:6700/api/sin/pedidos/9999    # mismo NotFound(), controlador sin [ApiController]
```

```text
HTTP/1.1 404 Not Found
Content-Length: 0
```

Un cliente puede tratar así todos los errores de la API con una única rutina que lee `application/problem+json`. Qué helpers devuelven qué código, y cuándo conviene devolver un cuerpo propio, está en [Tipos de retorno de una acción](Tipos-de-Retorno-de-una-Accion.md).

Un `404` que viene del enrutado (ninguna ruta coincide) no pasa por este mecanismo, porque no llegó a ninguna acción: `GET /api/pedidos/abc` (con la ruta `{id:int}`) responde `404` con `Content-Length: 0`.

## ControllerBase frente a Controller

Un controlador de API hereda de `ControllerBase`. `Controller` hereda de `ControllerBase` y le añade soporte para vistas: `View()`, `PartialView()`, `ViewData`, `ViewBag`, `TempData`. Para una API es peso muerto y confunde, porque `AddControllers()` no registra los servicios de vistas.

Comprobado con un controlador `[ApiController]` que hereda de `Controller` y está registrado con `AddControllers()`:

```csharp
[ApiController, Route("api/pedidos")]
public class PedidosController : Controller
{
    [HttpGet("json")]  public IActionResult J() => Ok(new { ok = true });
    [HttpGet("vista")] public IActionResult V() => View();
}
```

```text
$ curl -i localhost:6700/api/pedidos/json    # cabeceras abreviadas
HTTP/1.1 200 OK
{"ok":true}

$ curl -i localhost:6700/api/pedidos/vista
HTTP/1.1 500 Internal Server Error
Content-Length: 0
```

En el log del servidor: `System.InvalidOperationException: No service for type 'Microsoft.AspNetCore.Mvc.ViewFeatures.ITempDataDictionaryFactory' has been registered.`

Heredar de `Controller` no impide que la API funcione, pero abre la puerta a código que solo falla en ejecución. Las vistas se habilitan con `AddControllersWithViews()`, que es para aplicaciones MVC con HTML (ver [Modelos de programación web](Modelos-de-programacion-web.md)).

## Sin el atributo: el contraste completo

Un controlador idéntico al de referencia, con la misma ruta base, sin `[ApiController]`:

```csharp
[Route("api/sin/pedidos")]
public class SinAtributoController : ControllerBase
{
    [HttpPost]
    public IActionResult Crear(CrearPedidoRequest request)
        => Ok(new PedidoResponse(4711, request.EmailCliente ?? "(null)", request.Cantidad));
}
```

Se envía un cuerpo JSON **válido**:

```bash
curl -i -X POST localhost:6700/api/sin/pedidos \
  -H 'Content-Type: application/json' \
  -d '{"emailCliente":"ana@example.com","cantidad":2}'
```

```text
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

{"id":4711,"emailCliente":"(null)","cantidad":0}
```

Es la diferencia más peligrosa: la petición es correcta, la respuesta es `200`, y el modelo llegó **vacío**. Sin `[ApiController]`, el parámetro complejo `request` se buscó en la query y el formulario, no en el cuerpo, y no encontró nada. El mismo DTO enviado por query string sí se rellena:

```text
$ curl -X POST "localhost:6700/api/sin/pedidos?emailCliente=ana@example.com&cantidad=2"
{"id":4711,"emailCliente":"ana@example.com","cantidad":2}
```

Con datos inválidos, nada los rechaza. Todas estas peticiones devuelven `200`, con el modelo vacío o con valores sin validar:

| Petición | Con `[ApiController]` | Sin `[ApiController]` |
|---|---|---|
| Cuerpo `{"emailCliente":"no-es-email","cantidad":0}` | `400` con `errors` | `200`, modelo vacío |
| Cuerpo `{"emailCliente":"a@b.com","cantidad":"dos"}` | `400` | `200`, modelo vacío |
| JSON truncado | `400` | `200`, modelo vacío |
| Sin cuerpo | `400` | `200`, modelo vacío |
| `Content-Type: text/plain` | `415` | `200`, modelo vacío |
| `GET ?pagina=abc` (parámetro `int pagina = 1`) | `400` | `200`, `{"pagina":1}` (usa el valor por defecto) |
| `NotFound()` | `404` con `ProblemDetails` | `404` con cuerpo vacío |

Para obtener sin el atributo el mismo comportamiento hace falta escribir todo a mano en cada acción:

```csharp
[HttpPost("explicito")]
public IActionResult CrearExplicito([FromBody] CrearPedidoRequest request)
{
    if (!ModelState.IsValid) return BadRequest(ModelState);
    return Ok();
}
```

```text
HTTP/1.1 400 Bad Request
Content-Type: application/json; charset=utf-8

{"Cantidad":["The field Cantidad must be between 1 and 100."],"EmailCliente":["The EmailCliente field is not a valid e-mail address."]}
```

Y aun así el resultado no es el mismo: `BadRequest(ModelState)` devuelve un `application/json` con el diccionario de errores sin `type`, `title`, `status` ni `traceId`, y no es `application/problem+json`.

## Personalizar y desactivar: `ApiBehaviorOptions`

Cada comportamiento tiene una opción en `ApiBehaviorOptions`, configurable en `Program.cs`:

```csharp
builder.Services.Configure<ApiBehaviorOptions>(options =>
{
    // ...
});
```

| Opción | Efecto |
|---|---|
| `SuppressModelStateInvalidFilter` | Desactiva el 400 automático por `ModelState` inválido. |
| `InvalidModelStateResponseFactory` | Sustituye la respuesta del 400 automático por la que construyas. |
| `SuppressInferBindingSourcesForParameters` | Desactiva la inferencia de `[FromBody]`/`[FromQuery]`/`[FromRoute]`. |
| `SuppressMapClientErrors` | Desactiva el `ProblemDetails` de los códigos `4xx` sin cuerpo. |
| `ClientErrorMapping` | Diccionario código → `type`/`title`/`link` para personalizar ese `ProblemDetails`. |
| `DisableImplicitFromServicesParameters` | Desactiva la inferencia de `[FromServices]` (desde .NET 7). |
| `SuppressConsumesConstraintForFormFileParameters` | Desactiva que los parámetros `IFormFile` impongan `multipart/form-data`. |

Las cinco primeras se ejecutaron; las dos últimas no se probaron y se citan por la documentación oficial.

### Desactivar la validación automática

Con `SuppressModelStateInvalidFilter = true` el mismo `POST` inválido de antes (`{"emailCliente":"x","cantidad":0}`) entra en la acción:

```csharp
builder.Services.Configure<ApiBehaviorOptions>(o => o.SuppressModelStateInvalidFilter = true);
```

```text
HTTP/1.1 200 OK
{"id":4711,"emailCliente":"x","cantidad":0}
```

La acción recibe el modelo inválido y es responsabilidad de ella consultar `ModelState.IsValid`. Es útil si validas con otra herramienta (por ejemplo FluentValidation, que se encarga de devolver su propio resultado).

### Cambiar la forma del 400

Para mantener la validación automática y cambiar solo la respuesta, `InvalidModelStateResponseFactory` recibe el `ActionContext` y devuelve el `IActionResult` que quieras. Ejemplo que cambia el código a `422` y el título:

```csharp
builder.Services.Configure<ApiBehaviorOptions>(o =>
    o.InvalidModelStateResponseFactory = ctx => new UnprocessableEntityObjectResult(
        new ValidationProblemDetails(ctx.ModelState) { Status = 422, Title = "Pedido inválido" }));
```

```text
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/problem+json; charset=utf-8

{"title":"Pedido inválido","status":422,"errors":{"Cantidad":["The field Cantidad must be between 1 and 100."],"EmailCliente":["The EmailCliente field is not a valid e-mail address."]}}
```

La respuesta ya no lleva `type` ni `traceId`: la fábrica sustituye a la que añadía esos campos. Si los quieres, hay que ponerlos tú (`Type`, `Extensions["traceId"]`).

### Desactivar la inferencia de origen

Con `SuppressInferBindingSourcesForParameters = true`, el `POST` válido del primer ejemplo ya no lee el cuerpo y el DTO llega vacío; el filtro de validación sigue activo y rechaza lo que ve:

```text
HTTP/1.1 400 Bad Request
{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"Cantidad":["The field Cantidad must be between 1 and 100."],"EmailCliente":["The EmailCliente field is required."]},"traceId":"00-39e72ad9fafcee00cad8ef544eb582fb-4b42ce615a383770-00"}
```

Es una buena demostración de que las convenciones son independientes: el cuerpo era correcto y la petición falla porque el origen ya no se infiere y habría que escribir `[FromBody]`.

### Cambiar o quitar el ProblemDetails de los errores sin cuerpo

`ClientErrorMapping` es un diccionario indexado por código de estado. Cambiando el título del `404`:

```csharp
builder.Services.Configure<ApiBehaviorOptions>(o => o.ClientErrorMapping[404].Title = "Recurso inexistente");
```

```text
HTTP/1.1 404 Not Found
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.5","title":"Recurso inexistente","status":404,"traceId":"00-8a0d05303b9381de1ee2e1dfac0fac3e-eb6f59d3cda0dbc3-00"}
```

Y con `SuppressMapClientErrors = true`, `GET /api/pedidos/9999` vuelve a responder `404` con `Content-Length: 0`.

## Aplicarlo a todo el ensamblado

En lugar de repetirlo en cada controlador, el atributo se puede declarar una vez para todo el proyecto, en cualquier fichero `.cs` y fuera de cualquier tipo, antes de las declaraciones (un atributo de ensamblado debe ir al principio del fichero, tras los `using`):

```csharp
using Microsoft.AspNetCore.Mvc;

[assembly: ApiController]
```

Un controlador sin `[ApiController]` en su clase, con la misma acción de antes:

```csharp
[Route("api/pedidos")]
public class PedidosController : ControllerBase
{
    [HttpPost]
    public IActionResult Crear(CrearPedidoRequest r) => Ok();
}
```

```text
$ curl -i -X POST localhost:6700/api/pedidos -H 'Content-Type: application/json' -d '{"cantidad":1}'
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"EmailCliente":["The EmailCliente field is required."]},"traceId":"00-28671af9e7dfd0568c6eaf64b79eb700-4fb6d169e26b21d0-00"}
```

Es el comportamiento del atributo de clase sin haberlo escrito en la clase. Una consecuencia práctica (no ejecutada, deducida de que el atributo de ensamblado equivale al de clase): **todos** los controladores del ensamblado quedan sujetos a la exigencia de attribute routing. Si el mismo proyecto aloja controladores que devuelven vistas con enrutado convencional, no se puede usar el atributo de ensamblado.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| La aplicación no arranca con `Action '...' does not have an attribute route. Action methods on controllers annotated with ApiControllerAttribute must be attribute routed.` | Una acción de un controlador con `[ApiController]` no tiene `[Route]` ni `[HttpGet]`/`[HttpPost]`... con plantilla. El error salta al arrancar, no al primer request. |
| La aplicación no arranca con `... has more than one parameter that was specified or inferred as bound from request body.` | Dos parámetros de tipo complejo en la misma acción. Agrupa los dos en un DTO, o marca uno con `[FromQuery]`/`[FromRoute]`. |
| La acción recibe el DTO con todo a `null`/`0` y responde `200` aunque el JSON sea correcto | El controlador no tiene `[ApiController]` (ni lo hereda del ensamblado) y el parámetro no lleva `[FromBody]`: se buscó en la query y el formulario. |
| Un parámetro `string` en la query da `400` con `The q field is required.` | Con el contexto de nulabilidad activado, un `string` no anulable se trata como obligatorio aunque no lleve `[Required]`. Declara `string? q` o dale un valor por defecto si es opcional. Comprobado con `GET /api/pedidos/origen/5` (sin `?q=`) en un proyecto con `<Nullable>enable</Nullable>`. |
| Cada error de JSON trae además `"request":["The request field is required."]` | El binding del cuerpo falló, el modelo es `null` y la validación lo marca como requerido. El mensaje útil es el otro (`$.campo`). |
| `500` con `No service for type '...ITempDataDictionaryFactory' has been registered` al llamar a `View()` | El controlador hereda de `Controller` pero la aplicación usa `AddControllers()`. En una API, hereda de `ControllerBase` y no uses `View()`. |
| `415 Unsupported Media Type` en un `POST` que debería funcionar | El cliente no manda `Content-Type: application/json`. Con `[ApiController]` el cuerpo solo se lee con un tipo que el servidor pueda deserializar. |
| El 400 de validación no tiene el formato que esperabas | `InvalidModelStateResponseFactory` o un filtro propio lo está reemplazando, o el controlador no tiene el atributo y devuelve `BadRequest(ModelState)` a mano. |

## Buenas prácticas avanzadas

- **Pon el atributo en una clase base, o en el ensamblado, en vez de repetirlo** — un olvido en un único controlador deja ese controlador sin validación ni inferencia (con el síntoma silencioso de la sección «Sin el atributo»). Una clase base `ApiControllerBase` con `[ApiController]` y `[Route("api/[controller]")]` (según la documentación, el atributo se hereda; no se comprobó), o `[assembly: ApiController]`, lo hacen imposible de olvidar. El atributo de ensamblado solo es viable si todo el proyecto es API.
- **Personaliza con `InvalidModelStateResponseFactory` en lugar de suprimir el filtro** — suprimirlo devuelve a cada acción la responsabilidad de validar, y vuelve el riesgo de olvidos. La fábrica permite cambiar el código, el `title` o añadir un `traceId`, un código de error propio o un enlace, manteniendo el comportamiento automático en un único sitio.
- **No pongas `[FromBody]` donde ya se infiere, pero sí en los casos ambiguos** — para un DTO de entrada la inferencia basta, y el atributo es ruido. Pónlo cuando el tipo sea simple y deba venir del cuerpo (por ejemplo, un `string` suelto), o cuando quieras que el código lo diga sin depender de la regla.
- **No mezcles `[ApiController]` con validación a mano sin saber por qué** — con el atributo activo, `if (!ModelState.IsValid)` dentro de la acción es código muerto para los errores de binding y de Data Annotations (la acción ni se ejecuta). Solo tiene sentido para validaciones de negocio que añades tú a `ModelState` (por ejemplo `ModelState.AddModelError(...)` tras consultar la base de datos), y entonces conviene devolver `ValidationProblem(ModelState)` para mantener el mismo formato.
- **Documenta los códigos que el atributo añade** — el `400` de validación y el `ProblemDetails` de los `4xx` los añade el framework, y no hace falta repetirlos; el resto (`404`, `409`...) los declara cada acción con `[ProducesResponseType]`, y quien consume la API los necesita en el contrato.
- **No expongas los mensajes de `JsonException` a clientes externos sin pensarlo** — como se vio, el cuerpo del `400` incluye `Path`, `LineNumber` y `BytePositionInLine`. Si la API es pública y quieres mensajes más sobrios, sustituye `InvalidModelStateResponseFactory` y filtra los mensajes que salgan de la deserialización.

## Documentación oficial

- [Crear APIs web con ASP.NET Core: el atributo ApiController](https://learn.microsoft.com/aspnet/core/web-api/#apicontroller-attribute) — la lista oficial de comportamientos (inferencia de origen, validación automática, `ProblemDetails`) y de cómo desactivarlos, con la tabla de reglas de inferencia.
- [Opciones de ApiBehaviorOptions](https://learn.microsoft.com/dotnet/api/microsoft.aspnetcore.mvc.apibehavioroptions) — referencia de todas las propiedades configurables, incluidas las que no se han tratado aquí.
- [RFC 9457: Problem Details for HTTP APIs](https://www.rfc-editor.org/rfc/rfc9457) — la norma que define el formato `application/problem+json`, para entender qué significan `type`, `title`, `status` y las extensiones.

---

*En resumen: `[ApiController]` convierte las convenciones de una API (validación con 400, inferencia de `[FromBody]`, rutas por atributo y errores en `ProblemDetails`) en comportamiento por defecto del framework; sin él, un cuerpo JSON válido puede llegar vacío a la acción y un cuerpo inválido, pasar sin queja.*
