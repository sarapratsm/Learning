# Tipos de retorno de una acción

## ¿Qué es?

El tipo de retorno de una acción es lo que un método de un controlador (o un *handler* de Minimal APIs) declara que devuelve para que ASP.NET Core construya la respuesta HTTP: código de estado, cabeceras y cuerpo. No se escribe la respuesta a mano; se devuelve un objeto que la describe y el framework la materializa. Las opciones son devolver el dato directamente (`T`), **`IActionResult`**, **`ActionResult<T>`** y, con los tipos de Minimal APIs, **`IResult`** y **`TypedResults`**.

## ¿Por qué existe?

Una respuesta HTTP no son solo datos: es un código de estado (`200`, `201`, `404`...), a veces cabeceras (`Location`) y a veces un cuerpo. Un método de C# solo devuelve un tipo fijo, así que hace falta un contrato que cubra «un `200` con un producto» y «un `404` sin cuerpo» en la misma firma. Ese contrato es `IActionResult` (y su variante tipada `ActionResult<T>`): una interfaz que representa «algo que sabe convertirse en una respuesta HTTP».

> Si ya conoces C#: `IActionResult` es una `interface` como cualquier otra. `Ok(...)` o `NotFound()` son fábricas que devuelven clases que la implementan (`OkObjectResult`, `NotFoundResult`...). El método declara el contrato y devuelve la implementación que toque en cada ejecución.

## ¿Cuándo y para qué se usa?

En **toda** acción. En la API de la tienda (`Tienda.Api`): `GET /api/pedidos/4711` devuelve `200` con el pedido o `404` si no existe; `POST /api/pedidos` devuelve `201` con la cabecera `Location`; `DELETE /api/pedidos/4711` devuelve `204`; un pedido ya enviado que se intenta cancelar devuelve `409`. Cada desenlace es un código distinto y el tipo de retorno es lo que permite expresarlos desde el mismo método.

La validación de la entrada ([Validación con Data Annotations](Validacion-con-DataAnnotations.md)) y de dónde sale cada parámetro ([Model binding](Model-Binding.md)) quedan fuera: aquí solo se trata lo que sale.

Las salidas citadas provienen de un proyecto `Tienda.Api` (SDK 10.0.401, `net10.0`, `Microsoft.AspNetCore.OpenApi` 10.0.12) ejecutado el 2026-11-10 y atacado con `curl`. Se han omitido las cabeceras `Date` y `Server`.

## Las tres formas básicas en un controlador

Los ejemplos usan estos tipos (abreviados a lo necesario):

```csharp
public enum EstadoPedido { Pendiente, Pagado, Enviado }

public record ProductoResponse(int Id, string Nombre, decimal Precio, string? Descripcion);
public record PedidoResponse(int Id, EstadoPedido Estado, decimal Total, DateTime CreadoEn, string? Observaciones);
public record CrearPedidoRequest(int ProductoId, int Cantidad);
```

### 1. Devolver el dato directamente

Cuando la acción no tiene más desenlace que el éxito, se declara el tipo concreto y el framework lo envuelve en un `200`.

```csharp
[ApiController]
[Route("api/productos")]
public class ProductosController : ControllerBase
{
    [HttpGet]
    public IEnumerable<ProductoResponse> Listar() => Datos.Productos;   // Datos: lista en memoria del ejemplo
}
```

```text
$ curl -i http://localhost:6740/api/productos
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

[{"id":1,"nombre":"Teclado mecánico","precio":89.90,"descripcion":null},{"id":2,"nombre":"Ratón inalámbrico","precio":24.50,"descripcion":"Ergonómico"}]
```

El tipo es completo para OpenAPI y no hay ruido. El límite: no hay forma de devolver un `404` o un `400` desde esa firma salvo lanzando una excepción.

### 2. `IActionResult`: cualquier resultado, sin tipo de datos

Un método que puede devolver desenlaces distintos declara el contrato y usa los *helpers* de `ControllerBase`.

```csharp
[HttpGet("opaco/{id:int}")]
public IActionResult ObtenerOpaco(int id)
{
    var producto = Datos.Productos.FirstOrDefault(p => p.Id == id);
    if (producto is null) return NotFound();   // 404
    return Ok(producto);                       // 200 + JSON
}
```

Funciona, pero la firma no dice qué datos devuelve. El coste aparece en el documento OpenAPI (ver más abajo): sin anotaciones, la respuesta `200` no tiene esquema.

### 3. `ActionResult<T>`: el dato o un resultado

`ActionResult<T>` admite **o** un `T` **o** cualquier `IActionResult`. La conversión de `T` a `200` es implícita.

```csharp
[HttpGet("{id:int}", Name = "ObtenerProducto")]
public ActionResult<ProductoResponse> Obtener(int id)
{
    var producto = Datos.Productos.FirstOrDefault(p => p.Id == id);
    if (producto is null) return NotFound();
    return producto;   // se envuelve solo en un 200 + JSON
}
```

```text
$ curl -i http://localhost:6740/api/productos/1
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

{"id":1,"nombre":"Teclado mecánico","precio":89.90,"descripcion":null}

$ curl -i http://localhost:6740/api/productos/99
HTTP/1.1 404 Not Found
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.5","title":"Not Found","status":404,"traceId":"00-9e78d95e78ce19b4bdc68a8826f2ab90-c42666c95be6612e-00"}
```

Observación: `NotFound()` no devuelve el cuerpo vacío que cabría esperar, sino un `ProblemDetails` (formato de error estándar, más abajo); lo produce el pipeline en este proyecto, que tiene `[ApiController]`, `AddProblemDetails()` y `UseStatusCodePages()`.

### Asíncrono: `Task<T>`

Las acciones que esperan E/S se declaran `async` y el tipo de retorno se envuelve en `Task<>`. Todo lo anterior es igual.

```csharp
[HttpGet("{id:int}")]
public async Task<ActionResult<PedidoResponse>> Obtener(int id, CancellationToken ct)
{
    var pedido = await _repositorio.ObtenerAsync(id, ct);   // _repositorio: dependencia inyectada (no incluida)
    return pedido is null ? NotFound() : pedido.ADto();     // ADto(): mapeo a PedidoResponse (no incluido)
}
```

La versión síncrona de este patrón (`if` + `return`) es la que se ejecutó; el ejemplo asíncrono no se ejecutó tal cual. El operador ternario compila porque ambas ramas convergen en `ActionResult<PedidoResponse>` mediante la conversión implícita.

## Los *helpers* y los códigos de estado

Cada *helper* de `ControllerBase` empaqueta un código de estado y, si procede, un cuerpo.

| Helper | Estado | Uso típico |
|---|---|---|
| `Ok(obj)` | 200 | Lectura correcta. |
| `Created`, `CreatedAtAction`, `CreatedAtRoute` | 201 + `Location` | Recurso creado. |
| `NoContent()` | 204 | Éxito sin cuerpo (`DELETE`, `PUT` sin devolver el recurso). |
| `BadRequest(...)` | 400 | Petición mal formada. |
| `Unauthorized()` / `Forbid()` | 401 / 403 | Sin identidad / sin permiso (ver [Authorize](Authorize.md)). |
| `NotFound()` | 404 | El recurso no existe. |
| `Conflict(...)` | 409 | Choque con el estado actual (pedido ya enviado). |
| `Problem(...)` | el indicado | Error con `ProblemDetails` y estado a medida. |
| `ValidationProblem(...)` | 400 | Errores de validación en formato estándar. |

### Crear: `201` con cabecera `Location`

`CreatedAtAction` (por nombre de acción) y `CreatedAtRoute` (por nombre de ruta) generan el `201` y rellenan `Location` con la URL del recurso nuevo, calculada con el enrutado. La ruta de destino debe existir y aceptar los valores que se pasan.

```csharp
[HttpPost]
public ActionResult<ProductoResponse> Crear(CrearProductoRequest request)
{
    var nuevo = new ProductoResponse(Datos.Productos.Max(p => p.Id) + 1, request.Nombre, request.Precio, null);
    Datos.Productos.Add(nuevo);
    return CreatedAtAction(nameof(Obtener), new { id = nuevo.Id }, nuevo);
}
```

```text
$ curl -i -X POST http://localhost:6740/api/productos -H "Content-Type: application/json" -d '{"nombre":"Monitor","precio":199}'
HTTP/1.1 201 Created
Content-Type: application/json; charset=utf-8
Location: http://localhost:6740/api/productos/3

{"id":3,"nombre":"Monitor","precio":199,"descripcion":null}
```

`Location` sale como URL absoluta (esquema y host de la petición), apuntando a `Obtener`. Para pedidos se usa `CreatedAtRoute("ObtenerPedido", new { id = pedido.Id }, dto)`, que obtiene la misma cabecera a partir del nombre de ruta (`Name = "ObtenerPedido"` en el `[HttpGet]`): `Location: http://localhost:6740/api/pedidos/4713`.

### Borrar y conflicto

```csharp
[HttpDelete("{id:int}")]
public IActionResult Cancelar(int id)
{
    var pedido = Datos.Pedidos.FirstOrDefault(p => p.Id == id);
    if (pedido is null) return NotFound();
    if (pedido.Estado == EstadoPedido.Enviado)
        return Conflict(new ProblemDetails { Title = "Pedido ya enviado", Detail = $"El pedido {id} no se puede cancelar.", Status = 409 });
    Datos.Pedidos.Remove(pedido);
    return NoContent();
}
```

```text
$ curl -i -X DELETE http://localhost:6740/api/pedidos/4712        # estado Enviado
HTTP/1.1 409 Conflict
Content-Type: application/problem+json; charset=utf-8

{"title":"Pedido ya enviado","status":409,"detail":"El pedido 4712 no se puede cancelar."}

$ curl -i -X DELETE http://localhost:6740/api/pedidos/4711        # estado Pagado
HTTP/1.1 204 No Content

$ curl -i -X DELETE http://localhost:6740/api/pedidos/4711        # ya borrado
HTTP/1.1 404 Not Found
```

El `409` lleva solo los campos que se pusieron en el `ProblemDetails`; el `404` lleva además `type` y `traceId` porque los rellena el pipeline. Conviene que todos los errores del API tengan la misma forma: ver «`ProblemDetails`» más abajo.

## `ProblemDetails`: el formato estándar de error

**`ProblemDetails`** es el JSON de error definido por el RFC 9457 (sucesor del RFC 7807), con el tipo de contenido `application/problem+json`. Sus campos: `type` (URI que identifica la clase de problema), `title` (resumen corto), `status` (código HTTP), `detail` (explicación de este caso) e `instance` (URI de esta ocurrencia); admite campos extra (`traceId`, `errors`...). Un cliente que conoce el formato puede tratar cualquier error de cualquier endpoint de la misma manera.

### `Problem(...)` y `ValidationProblem(...)`

`Problem` construye un `ProblemDetails` con el estado que se indique; `ValidationProblem` construye el de validación, con un diccionario `errors` por campo.

```csharp
[HttpPost]
public ActionResult<PedidoResponse> Crear(CrearPedidoRequest request)
{
    if (!Datos.Productos.Any(p => p.Id == request.ProductoId))
        return Problem(
            title: "Producto inexistente",
            detail: $"No existe el producto {request.ProductoId}.",
            statusCode: StatusCodes.Status422UnprocessableEntity);

    if (request.Cantidad > 10)
    {
        ModelState.AddModelError(nameof(request.Cantidad), "Máximo 10 unidades por pedido.");
        return ValidationProblem(ModelState);
    }

    // ... crear el pedido y devolver CreatedAtRoute(...) (abreviado)
}
```

```text
$ curl -i -X POST http://localhost:6740/api/pedidos -H "Content-Type: application/json" -d '{"productoId":77,"cantidad":2}'
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc4918#section-11.2","title":"Producto inexistente","status":422,"detail":"No existe el producto 77.","traceId":"00-bb440f89e54d645cad831d3a8e1018c7-c6a26c7e41695253-00"}

$ curl -i -X POST http://localhost:6740/api/pedidos -H "Content-Type: application/json" -d '{"productoId":1,"cantidad":50}'
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"Cantidad":["Máximo 10 unidades por pedido."]},"traceId":"00-3f33b05941ac5d9c993efb044bc55002-b21cc3091900ebb0-00"}
```

Qué hace cada uno: `Problem` rellena `type` y `title` con valores por defecto según el estado si no se indican (el `type` de un `422` apunta al RFC 4918); `ValidationProblem` fija `400` y añade `errors`. La validación automática de `[ApiController]` produce exactamente este formato (ver [ApiController](ApiController.md)).

### Errores no controlados: `AddProblemDetails` e `IExceptionHandler`

Una excepción que nadie captura acaba en el middleware de excepciones (`UseExceptionHandler`). Con `AddProblemDetails()` registrado, ese middleware responde con un `ProblemDetails` en vez de una página o un cuerpo vacío. `IExceptionHandler` permite decidir, **por tipo de excepción**, qué respuesta se da; devolver `false` pasa la excepción al siguiente manejador (o al comportamiento por defecto).

```csharp
// Program.cs (abreviado a lo relevante)
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<ManejadorDeExcepciones>();

var app = builder.Build();
app.UseExceptionHandler();
app.UseStatusCodePages();     // rellena también los 404/405 vacíos con ProblemDetails

class ManejadorDeExcepciones(IProblemDetailsService problemDetails) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext ctx, Exception ex, CancellationToken ct)
    {
        if (ex is not PedidoYaEnviadoException) return false;       // las demás, al comportamiento por defecto
        ctx.Response.StatusCode = StatusCodes.Status409Conflict;
        return await problemDetails.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = ctx,
            Exception = ex,
            ProblemDetails = new ProblemDetails { Title = "Pedido ya enviado", Detail = ex.Message, Status = 409 }
        });
    }
}
```

Con una acción que lanza `PedidoYaEnviadoException` (la que maneja el manejador) y otra que lanza `InvalidOperationException("detalle interno")` (que ningún manejador reconoce):

```text
$ curl -i -X POST http://localhost:6740/api/pedidos/4712/reembolso
HTTP/1.1 409 Conflict
Content-Type: application/problem+json
Cache-Control: no-cache,no-store

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.10","title":"Pedido ya enviado","status":409,"detail":"El pedido 4712 ya está enviado.","traceId":"00-6f0113ca805f73fe5532124811dd691b-06c987d1d4f00409-00"}

$ curl -i -X POST http://localhost:6740/api/pedidos/4712/fallo
HTTP/1.1 500 Internal Server Error
Content-Type: application/problem+json; charset=utf-8
Cache-Control: no-cache,no-store

{"type":"https://tools.ietf.org/html/rfc9110#section-15.6.1","title":"An error occurred while processing your request.","status":500,"traceId":"00-4d3ab560508bbab545ea91dc0556a9a9-c4112a7120005fc7-00"}
```

Con el entorno `Development` y este registro, el `500` genérico **no** incluye el mensaje (`detalle interno`) ni la traza: solo el `traceId`, que sirve para localizar la excepción en el log (la excepción completa se registra con nivel `fail` en el log de la aplicación). El mensaje de la excepción solo llega al cliente si el manejador lo pone en `detail`, así que ahí hay que decidir qué es seguro exponer.

## `IResult` y `TypedResults`

`IResult` es el contrato equivalente de Minimal APIs. `Results.Ok(...)`, `Results.NotFound()` y compañía devuelven `IResult` (sin tipo); **`TypedResults`** devuelve el tipo concreto (`Ok<T>`, `NotFound`), y la unión **`Results<Ok<T>, NotFound>`** declara los desenlaces posibles en la firma. Es el equivalente de `ActionResult<T>` pero con todos los casos nombrados: el compilador impide devolver uno no declarado y OpenAPI los lee sin anotaciones.

```csharp
app.MapGet("/api/minimal/pedidos/{id:int}", Results<Ok<PedidoResponse>, NotFound> (int id) =>
{
    var p = Datos.Pedidos.FirstOrDefault(x => x.Id == id);
    return p is null
        ? TypedResults.NotFound()
        : TypedResults.Ok(new PedidoResponse(p.Id, p.Estado, p.Total, p.CreadoEn, p.Observaciones));
});
```

### ¿Se pueden usar en un controlador?

Sí, en .NET 10 (comprobado). Un método de controlador puede devolver `IResult` o `Results<...>`:

```csharp
[HttpGet("tipado/{id:int}")]
public Results<Ok<PedidoResponse>, NotFound> ObtenerTipado(int id)
{
    var pedido = Datos.Pedidos.FirstOrDefault(p => p.Id == id);
    return pedido is null ? TypedResults.NotFound() : TypedResults.Ok(ADto(pedido));
}

[HttpGet("iresult/{id:int}")]
public IResult ObtenerIResult(int id) =>
    Datos.Pedidos.FirstOrDefault(p => p.Id == id) is { } pedido
        ? TypedResults.Ok(ADto(pedido))
        : TypedResults.Problem(statusCode: 404, title: "Pedido no encontrado");
```

```text
$ curl -i http://localhost:6740/api/pedidos/tipado/4712
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

{"id":4712,"estado":"Enviado","total":24.50,"creadoEn":"2026-11-09T18:00:00Z","observaciones":null}

$ curl -i http://localhost:6740/api/pedidos/iresult/1
HTTP/1.1 404 Not Found
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.5","title":"Pedido no encontrado","status":404,"traceId":"00-d42fda2eee6e03d7e13af49107ed6f58-31d03962558d3754-00"}
```

Pero hay una diferencia que conviene conocer: los resultados `IResult` se serializan con las opciones JSON **HTTP** (`ConfigureHttpJsonOptions`), mientras que `ActionResult<T>` y los *helpers* usan las opciones **MVC** (`AddControllers().AddJsonOptions`). Si se configuran solo las de MVC, los dos caminos del mismo controlador serializan distinto (ver «Serialización»). La mezcla en un mismo controlador funciona, pero lo más coherente es elegir un estilo por proyecto: ver [Modelos de programación web](Modelos-de-programacion-web.md) para elegir entre controladores y Minimal APIs.

## OpenAPI: `[ProducesResponseType]` y `[Produces]`

Una acción declara en su firma lo que devuelve **en el caso feliz**; los demás desenlaces (404, 409...) son invisibles para el generador. **OpenAPI** es la especificación que describe una API en un documento JSON (rutas, parámetros, respuestas); lo consumen Swagger UI, generadores de clientes y herramientas de pruebas. Desde .NET 9 la generación viene integrada: `builder.Services.AddOpenApi()` y `app.MapOpenApi()` (paquete `Microsoft.AspNetCore.OpenApi`) publican el documento en `/openapi/v1.json`; la plantilla `dotnet new webapi` ya lo incluye. Dos atributos controlan lo que sale:

- **`[ProducesResponseType<T>(estado)]`** declara una respuesta posible: estado y tipo del cuerpo. Admite varias por acción.
- **`[Produces("application/json")]`** restringe los tipos de contenido que ofrece la acción (o el controlador entero).

### Qué documenta cada tipo de retorno

Qué contiene el documento generado (`/openapi/v1.json`) para cada forma de declarar el retorno, en la misma acción de lectura con `404`:

| Acción | Respuestas en el documento |
|---|---|
| `ActionResult<ProductoResponse>` sin anotaciones (devuelve `404` a veces) | Solo `200` con esquema `ProductoResponse` |
| `IActionResult` sin anotaciones | `200` **sin `content`** (no hay esquema) |
| `IActionResult` con `[ProducesResponseType<ProductoResponse>(200)]` y `[ProducesResponseType(404)]` | `200` con `ProductoResponse` y `404` |
| `Results<Ok<PedidoResponse>, NotFound>` (controlador o Minimal API) | `200` con `PedidoResponse` y `404`, sin anotaciones |

Fragmento real del documento generado (`GET /api/productos/opaco/{id}`, `IActionResult` sin anotaciones):

```json
"/api/productos/opaco/{id}": { "get": { "responses": { "200": { "description": "OK" } } } }
```

Y el de `POST /api/pedidos`, que devuelve `201` pero lleva `ActionResult<PedidoResponse>` sin anotaciones (el generador solo documentó un `200`):

```json
"responses": { "200": { "description": "OK", "content": { "application/json": { "schema": { "$ref": "#/components/schemas/PedidoResponse" } } } } }
```

Con las anotaciones del ejemplo, abreviado, el mismo endpoint pasa a documentar lo que realmente puede devolver:

```csharp
[HttpPost]
[ProducesResponseType<PedidoResponse>(StatusCodes.Status201Created)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status422UnprocessableEntity)]
[ProducesResponseType<ValidationProblemDetails>(StatusCodes.Status400BadRequest)]
public ActionResult<PedidoResponse> Crear(CrearPedidoRequest request) { /* ... */ }
```

```json
"responses": {
  "201": { "description": "Created", "content": { "application/json": { "schema": { "$ref": "#/components/schemas/PedidoResponse" } } } },
  "422": { "description": "Unprocessable Entity", "content": { "application/json": { "schema": { "$ref": "#/components/schemas/ProblemDetails" } } } },
  "400": { "description": "Bad Request", "content": { "application/json": { "schema": { "$ref": "#/components/schemas/ValidationProblemDetails" } } } }
}
```

### Tipos de contenido

Sin `[Produces]`, cada respuesta con cuerpo se documenta con **tres** tipos de contenido (`text/plain`, `application/json` y `text/json`), porque los formateadores de salida de MVC los ofrecen todos. Con `[Produces("application/json")]` en el controlador solo queda `application/json`, como en el fragmento anterior. `[Produces("text/plain")]` sobre un `ActionResult<string>` cambia además el tipo real de la respuesta:

```text
$ curl -i http://localhost:6740/api/productos/1/texto
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8

Producto 1
```

### Las anotaciones no se comprueban

Las anotaciones documentan, no ejecutan: si la acción devuelve `404` y se anota `409`, el documento miente y nada falla. Cuando se usa `Results<...>` ese desfase no puede ocurrir, porque las respuestas se leen del propio tipo.

## Serialización

El cuerpo lo escribe `System.Text.Json` con los valores por defecto de ASP.NET Core:

- **camelCase** en los nombres de propiedad: `ProductoId` sale como `productoId`.
- **Los `null` se escriben** (`"descripcion":null`). Para omitirlos en controladores: `AddControllers().AddJsonOptions(o => o.JsonSerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)`; la respuesta pasa a `{"id":1,"nombre":"Teclado mecánico","precio":89.90}`.
- **Los enums salen como número** (`"estado":2`) salvo que se registre `JsonStringEnumConverter`.

Con `JsonStringEnumConverter` añadido solo en `AddControllers().AddJsonOptions(...)`, los dos caminos del mismo proyecto divergían:

```text
$ curl http://localhost:6740/api/pedidos/4712            # ActionResult<T>: opciones MVC
{"id":4712,"estado":"Enviado", ...}
$ curl http://localhost:6740/api/pedidos/tipado/4712     # Results<...>: opciones HTTP
{"id":4712,"estado":2, ...}
```

y el documento OpenAPI describía `EstadoPedido` como `{"type":"integer"}`, es decir, un contrato distinto del cuerpo real de los controladores. El generador de OpenAPI y `IResult` leen las opciones HTTP; MVC, las suyas. Poner el atributo en el propio tipo evita configurarlo dos veces y deja las tres vías de acuerdo:

```csharp
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum EstadoPedido { Pendiente, Pagado, Enviado }
```

Con el atributo (y sin `AddJsonOptions` para el enum), ambas rutas devuelven `"estado":"Enviado"` y el documento OpenAPI dice `{"enum":["Pendiente","Pagado","Enviado"]}`. Lo mismo vale para `WhenWritingNull`: configurado solo en MVC, `GET /api/pedidos/tipado/4712` sigue escribiendo `"observaciones":null` mientras `GET /api/productos` ya omite `descripcion`. Para unificar el resto de opciones, se configuran las dos: `AddControllers().AddJsonOptions(...)` y `builder.Services.ConfigureHttpJsonOptions(...)`.

## Streaming con `IAsyncEnumerable<T>`

Una acción puede devolver `IAsyncEnumerable<T>` para entregar una colección larga conforme se produce, sin acumularla entera en memoria. El cliente recibe un array JSON normal.

```csharp
[HttpGet("lento")]
public async IAsyncEnumerable<int> Lento()      // tres elementos, uno por segundo
{
    for (var i = 1; i <= 3; i++) { await Task.Delay(1000); yield return i; }
}
```

```text
$ curl -s -o /dev/null -w "primer byte: %{time_starttransfer}s  total: %{time_total}s\n" http://localhost:6740/api/pedidos/lento
primer byte: 1.015403s  total: 3.036894s
$ curl -s http://localhost:6740/api/pedidos/lento
[1,2,3]
```

La respuesta empieza a llegar en cuanto sale el primer elemento (1 s), no cuando acaba el último (3 s). Lo mismo ocurre con un `MapGet` de Minimal API que devuelva `IAsyncEnumerable<int>` (primer byte 1,01 s, total 3,02 s). Medido con .NET 10; en versiones anteriores MVC acumulaba la secuencia completa antes de responder (según la documentación, no comprobado aquí).

El cuerpo es un array, no un flujo de eventos: para empujar datos al cliente indefinidamente (notificaciones, progreso) se usa Server-Sent Events u otro canal, fuera de alcance aquí. Un `IAsyncEnumerable<PedidoResponse>` se documenta en OpenAPI como `array` de `PedidoResponse`.

## Cuál elegir

| Situación | Tipo de retorno |
|---|---|
| Solo hay éxito (`GET` de una lista, sin errores posibles) | `T` directamente (`IEnumerable<T>`, `Task<T>`) |
| Éxito con dato y desenlaces de error (`404`, `409`...), estilo controlador | `ActionResult<T>` + `[ProducesResponseType]` para los errores |
| Respuesta sin cuerpo o de formas distintas (`DELETE`, `POST` que crea) | `IActionResult` + `[ProducesResponseType]` en cada caso |
| Minimal API, o controlador donde se quiere que el compilador exija los desenlaces | `Results<Ok<T>, NotFound, ...>` con `TypedResults` |
| Devolver el `201` con `Location` | `CreatedAtAction` / `CreatedAtRoute` |
| Cualquier error con cuerpo | `Problem` / `ValidationProblem` / `ProblemDetails` |
| Colección grande o producida de forma incremental | `IAsyncEnumerable<T>` |
| Error inesperado | Excepción + `IExceptionHandler` (no un `try/catch` por acción) |

Cuándo **no**: `IActionResult` sin anotar en un API con OpenAPI (el contrato queda opaco); `Results.*` sin tipos (`IResult` pelado) cuando se podría usar `TypedResults`; `T` directo cuando ya se sabe que habrá un desenlace distinto del éxito.

## Errores frecuentes

**Síntoma: el cliente recibe `200 OK` con `{"error":"Producto no encontrado"}`.** Causa: devolver `Ok(new { error = ... })` para un fallo. Salida real:

```text
$ curl -i http://localhost:6740/api/productos/mal/99
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

{"error":"Producto no encontrado"}
```

El código de estado miente: cualquier cliente, *proxy*, reintento automático o herramienta de monitorización lo contará como éxito, y el cliente tiene que mirar dentro del cuerpo para saber qué pasó. El contraste correcto:

```csharp
// ❌ el fallo viaja con 200
if (producto is null) return Ok(new { error = "Producto no encontrado" });

// ✅ el estado dice la verdad; el cuerpo detalla
if (producto is null) return NotFound();
```

**Síntoma: `204 No Content` cuando se esperaba `404`.** Causa: devolver `null` en una acción con `ActionResult<T>` (o `T`). Con `return Datos.Productos.FirstOrDefault(p => p.Id == id)!;`:

```text
$ curl -i http://localhost:6740/api/productos/nulo/99
HTTP/1.1 204 No Content
```

Un `null` no es «no encontrado»: el formateador de salida lo traduce a `204`. Un `if (x is null) return NotFound();` explícito evita el problema.

**Síntoma: `InvalidOperationException: Record type 'Tienda.Api.CrearProductoRequest' has validation metadata defined on property 'Nombre' that will be ignored. 'Nombre' is a parameter in the record primary constructor and validation metadata must be associated with the constructor parameter.`** Causa: en un `record` de constructor primario se escribió `[property: Required]`; la validación de un registro se asocia al parámetro, no a la propiedad. Apareció como `500` en `POST /api/productos` al validar el cuerpo. Corrección: `record CrearProductoRequest([Required] string Nombre, decimal Precio)`. Detalle de la validación en [Validación con Data Annotations](Validacion-con-DataAnnotations.md).

**Síntoma: el documento OpenAPI no muestra la respuesta `404` (o `201`, o `409`).** Causa: ni `ActionResult<T>` ni `IActionResult` declaran los errores; el generador solo ve el caso feliz y, para `IActionResult` sin anotar, ni siquiera el tipo. Se resuelve con `[ProducesResponseType]` o con `Results<...>`.

**Síntoma: `"estado":2` en un endpoint y `"estado":"Enviado"` en otro.** Causa: opciones JSON de MVC distintas a las HTTP (ver «Serialización»).

**Síntoma: `"title":"An error occurred while processing your request."` sin más información.** Causa: es el `500` genérico del manejador de excepciones; no hay `IExceptionHandler` para esa excepción y la respuesta no expone el mensaje a propósito. El dato útil es el `traceId` y el log del servidor.

## Buenas prácticas avanzadas

- **Anota los errores aunque uses `ActionResult<T>`.** `ActionResult<T>` documenta solo el `200`; sin `[ProducesResponseType<ProblemDetails>(404)]` (o la unión `Results<...>`), el cliente generado desde OpenAPI no tiene tipo para los fallos y lanza una excepción genérica. Es la diferencia entre un contrato real y uno parcial.
- **Un único manejador de errores en lugar de `try/catch` por acción.** Mapea excepciones de dominio (`PedidoYaEnviadoException` → `409`) en un `IExceptionHandler`; las acciones se quedan con el camino feliz y el formato de error es uniforme. Devuelve `false` para las que no reconoces, de modo que el resto sigue por el comportamiento por defecto.
- **Elige qué entra en `detail`.** El `500` por defecto no filtra el mensaje de la excepción, y es lo correcto; cuando un manejador escribe `ex.Message` en `detail`, ese texto sale al cliente. Revisa que no incluya datos internos (cadenas de conexión, nombres de tablas, rutas del servidor).
- **Configura las opciones JSON dos veces, o en el tipo.** `AddControllers().AddJsonOptions` y `ConfigureHttpJsonOptions` son independientes; el generador de OpenAPI y `IResult` leen la segunda, `ActionResult<T>` la primera. Un `[JsonConverter]` sobre el enum o el tipo mantiene el contrato escrito y el documentado de acuerdo sin depender de la configuración global.
- **No devuelvas la entidad de la base de datos; devuelve el DTO de respuesta.** Serializar una entidad de EF Core arrastra propiedades de navegación (ciclos, carga innecesaria, campos que no deben salir). Mapea a `PedidoResponse` y devuelve ese tipo; la firma y el contrato OpenAPI quedan estables aunque cambie la entidad. Ver [Entity Framework Core](../../bases-de-datos/acceso-a-datos-dotnet/Entity-Framework-Core.md).
- **Prueba el contrato con la API real.** Una prueba de integración con `WebApplicationFactory` que compruebe estado, `Content-Type` y cabecera `Location` detecta justo los desfases que las anotaciones no comprueban (ver [WebApplicationFactory](../../testing/testing-dotnet/WebApplicationFactory.md)).

## Documentación oficial

- [Controller action return types in ASP.NET Core web API](https://learn.microsoft.com/aspnet/core/web-api/action-return-types) — la comparación oficial entre `T`, `IActionResult` y `ActionResult<T>`; empieza por aquí para la parte de controladores.
- [Handle errors in ASP.NET Core APIs](https://learn.microsoft.com/aspnet/core/fundamentals/error-handling-api) — `AddProblemDetails`, `IExceptionHandler` y `UseStatusCodePages`, con las opciones de personalización de `ProblemDetails`.
- [Generate OpenAPI documents](https://learn.microsoft.com/aspnet/core/fundamentals/openapi/aspnetcore-openapi) — `AddOpenApi`/`MapOpenApi`, transformadores y cómo se leen `[ProducesResponseType]` y los tipos de retorno.
- [RFC 9457: Problem Details for HTTP APIs](https://www.rfc-editor.org/rfc/rfc9457) — la fuente normativa de los campos `type`, `title`, `status`, `detail` e `instance`.

## Recursos didácticos

- [http.cat](https://http.cat/) — cada código de estado HTTP ilustrado con un gato; útil para recordar cuándo toca un `204`, un `409` o un `422`.
- [REST](../../arquitectura-de-software/tipos-de-apis/REST.md) — qué código de estado corresponde a cada verbo y desenlace desde el punto de vista del diseño de la API.

---

*En resumen: una acción no escribe la respuesta HTTP, devuelve un objeto que la describe (`T` si solo hay éxito, `ActionResult<T>` o `Results<...>` si hay errores posibles) y el código de estado debe decir la verdad: un fallo con `200` y un error en el cuerpo es el error clásico; `ProblemDetails` es el formato estándar de los fallos y `[ProducesResponseType]` lo que lleva esos fallos al contrato OpenAPI.*
