# Model binding ([From...])

## ¿Qué es?

El *model binding* es el proceso por el que ASP.NET Core rellena los parámetros de una acción con datos de la petición HTTP: convierte el texto de la URL, de la query string, de las cabeceras o del cuerpo en `int`, `DateTime`, enums y objetos de C#. Los atributos `[FromBody]`, `[FromQuery]`, `[FromRoute]`, `[FromHeader]`, `[FromForm]`, `[FromServices]` y `[FromKeyedServices]` indican **de dónde** sale cada valor.

## ¿Por qué existe?

Una petición HTTP es texto: una URL, unas cabeceras y un cuerpo. Una acción es un método tipado de C#. Sin un binder, cada acción empezaría leyendo `Request.Query["pagina"]`, convirtiéndolo con `int.TryParse`, y devolviendo un `400` a mano si falla. El model binding hace esa traducción una vez, de forma uniforme, y registra en el `ModelState` lo que no pudo convertir.

Una petición trae datos en varios sitios a la vez (`/api/productos/42?pagina=2`, una cabecera `X-Tenant-Id`, un JSON en el cuerpo), y el framework necesita saber qué trozo corresponde a cada parámetro. Los atributos `[From...]` lo declaran.

> Si vienes de SQL, es el equivalente a los parámetros de una consulta preparada: cada `@param` tiene un origen y un tipo, y el motor hace la conversión.

## ¿Cuándo y para qué se usa?

Aparecen en la firma de cada acción de una API: el `id` de la URL de `/api/pedidos/4711`, la página y el orden de un listado de `/api/productos`, el `CrearPedidoRequest` en JSON de un `POST`, un identificador de inquilino en una cabecera, un archivo adjunto en un formulario. Con [`[ApiController]`](ApiController.md) muchos se infieren y se pueden omitir; conviene conocerlos para saber qué infiere el framework, para los casos en que no acierta y para entender los errores `400` que produce el binding.

Las salidas citadas provienen de una aplicación `Tienda.Api` con .NET SDK 10.0.401, ejecutada el 2026-11-10 en una máquina con cultura `es-ES` y atacada con `curl`. Las respuestas `ProblemDetails` llevan un campo `traceId` que se omite en los ejemplos (`"traceId":"00-…"`).

## Los orígenes: un atributo por sitio

Todos los ejemplos usan un controlador con `[ApiController]`. Cada uno muestra la acción y la respuesta real.

### `[FromRoute]` y `[FromQuery]`: URL y query string

`[FromRoute]` toma el valor de un segmento de la plantilla de ruta; `[FromQuery]`, de la query string. `Name` permite que el nombre público difiera del nombre del parámetro.

```csharp
[ApiController]
[Route("api/productos")]
public class ProductosController : ControllerBase
{
    [HttpGet("{id}")]
    public IActionResult Detalle([FromRoute] int id, [FromQuery] int pagina = 1,
        [FromQuery(Name = "tam")] int tamano = 20)
        => Ok(new { id, pagina, tamano });
}
```

```bash
curl "http://localhost:6720/api/productos/42?pagina=2&tam=10"
```

```json
{"id":42,"pagina":2,"tamano":10}
```

Un parámetro simple de la query que no llega **no es un error**: queda con su valor por defecto (`pagina = 1`, o `0`/`null` si no lo declaras). Para exigirlo existe `[BindRequired]` (más abajo). Las restricciones de ruta (`{id:int}`) están en [Enrutado y verbos HTTP](Enrutado-y-Verbos.md).

### `[FromBody]`: el cuerpo, normalmente JSON

`[FromBody]` deserializa el cuerpo de la petición con *input formatters* (por defecto `System.Text.Json`) hacia el tipo del parámetro.

```csharp
public record LineaRequest(string Sku, int Cantidad);

public record CrearPedidoRequest(string Cliente, List<LineaRequest> Lineas,
    EstadoPedido Estado = EstadoPedido.Borrador);

[ApiController]
[Route("api/pedidos")]
public class PedidosController : ControllerBase
{
    [HttpPost]
    public IActionResult Crear([FromBody] CrearPedidoRequest request)
        => Created("/api/pedidos/4711", request);
}
```

```bash
curl -i -X POST http://localhost:6720/api/pedidos -H "Content-Type: application/json" \
  -d '{"cliente":"Ana","lineas":[{"sku":"TEC-01","cantidad":2}]}'
```

```text
HTTP/1.1 201 Created
Content-Type: application/json; charset=utf-8
Location: /api/pedidos/4711

{"cliente":"Ana","lineas":[{"sku":"TEC-01","cantidad":2}],"estado":0}
```

El `Content-Type: application/json` es obligatorio: sin él, el cuerpo no se lee y la respuesta es `415 Unsupported Media Type`.

### `[FromHeader]`: una cabecera HTTP

```csharp
[HttpGet("cabecera")]
public IActionResult Cabecera([FromHeader(Name = "X-Tenant-Id")] string tenantId)
    => Ok(new { tenantId });
```

```bash
curl -H "X-Tenant-Id: acme" http://localhost:6720/api/productos/cabecera
# {"tenantId":"acme"}
```

Sin `Name`, el binder busca una cabecera llamada igual que el parámetro (`tenantId`), cosa poco habitual en HTTP, donde las cabeceras llevan guiones. Si la cabecera falta, un `string` no anulable produce un `400` (la sección de errores muestra el mensaje).

### `[FromForm]`: formularios y archivos

`[FromForm]` lee `application/x-www-form-urlencoded` y `multipart/form-data`, el formato de los formularios HTML y de la subida de archivos. Un `IFormFile` se enlaza como archivo.

```csharp
[HttpPost("formulario")]
public IActionResult Formulario([FromForm] string cliente, [FromForm] IFormFile? adjunto)
    => Ok(new { cliente, adjunto = adjunto?.FileName, bytes = adjunto?.Length });
```

```bash
curl -X POST http://localhost:6720/api/pedidos/formulario -F cliente=Ana -F adjunto=@win.ini
# {"cliente":"Ana","adjunto":"win.ini","bytes":92}
```

Si el cliente manda JSON a una acción que espera un formulario, `cliente` queda sin valor y el binding responde `400` con `The cliente field is required.`

### `[FromServices]` y `[FromKeyedServices]`: el contenedor de dependencias

Estos dos no leen la petición: piden un servicio al contenedor de [inyección de dependencias](De-NET-Core-a-ASP-NET-Core.md). `[FromServices]` resuelve por tipo; `[FromKeyedServices("clave")]`, introducido en .NET 8 y vigente en .NET 10, resuelve por tipo **y clave**, cuando hay varias implementaciones registradas de la misma interfaz.

```csharp
// Program.cs
builder.Services.AddSingleton<IDescuentos, DescuentosFijos>();
builder.Services.AddKeyedSingleton<INotificador, NotificadorEmail>("email");
builder.Services.AddKeyedSingleton<INotificador, NotificadorSms>("sms");

// Controlador
[HttpGet("servicios")]
public IActionResult Servicios([FromServices] IDescuentos descuentos,
    [FromKeyedServices("email")] INotificador email,
    [FromKeyedServices("sms")] INotificador sms)
    => Ok(new { descuento = descuentos.Para("x"), email = email.Canal, sms = sms.Canal });
```

```json
{"descuento":5,"email":"email","sms":"sms"}
```

En un controlador, lo normal es inyectar por constructor lo que usa casi toda la clase y dejar `[FromServices]` para la dependencia que solo necesita una acción.

## Sin atributo: qué infiere el framework

Sin `[From...]`, el comportamiento depende de si el controlador lleva `[ApiController]`.

**Con `[ApiController]`** la inferencia sigue reglas fijas:

| Tipo del parámetro | Origen inferido |
|---|---|
| Tipo complejo (clase, record) | `[FromBody]` |
| `IFormFile`, `IFormFileCollection` | `[FromForm]` |
| Simple (`int`, `string`, `Guid`, enum, `DateTime`...) cuyo nombre aparece en la plantilla de ruta | `[FromRoute]` |
| Cualquier otro simple | `[FromQuery]` |
| Servicio registrado en el contenedor (desde .NET 7) | `[FromServices]` |

Un caso con las tres reglas a la vez (`request` complejo → cuerpo, `id` no está en la ruta → query):

```csharp
[HttpPost("sin-atributo")]
public IActionResult SinAtributo(CrearPedidoRequest request, int id) => Ok(new { request, id });
```

```bash
curl -X POST "http://localhost:6720/api/pedidos/sin-atributo?id=7" \
  -H "Content-Type: application/json" -d '{"cliente":"Ana","lineas":[]}'
# {"request":{"cliente":"Ana","lineas":[],"estado":0},"id":7}
```

La excepción habitual es un objeto de filtros que debe venir de la query: la regla lo mandaría al cuerpo, así que requiere `[FromQuery]` explícito.

**Sin `[ApiController]`** (un controlador MVC clásico), el binder busca cada parámetro, por nombre, en este orden y se queda con el primer valor que encuentra: **formulario, datos de ruta y query string**. Un tipo complejo sin atributo **no** lee el cuerpo JSON. Comprobado con `id` presente en la ruta, la query y el formulario a la vez:

```csharp
[Route("api/clasico")]
public class ClasicoController : ControllerBase
{
    [HttpPost("orden/{id}")]
    public IActionResult Orden(int id) => Ok(new { id });
}
```

```bash
curl -X POST "http://localhost:6720/api/clasico/orden/1?id=2"                       # {"id":1}
curl -X POST "http://localhost:6720/api/clasico/orden/1?id=2" -d id=3               # {"id":3}
curl -X POST "http://localhost:6720/api/clasico/orden/1?id=2" \
  -H "Content-Type: application/json" -d '{"id":4}'                                 # {"id":1}
```

La ruta gana a la query; el formulario gana a ambas; el cuerpo JSON se ignora. Es una razón práctica para declarar el origen: un valor que llega por dos sitios puede sustituir silenciosamente al esperado.

## Tipos complejos, colecciones, enums y fechas

### Objetos y colecciones desde la query string

Un `[FromQuery]` sobre una clase enlaza cada propiedad con el parámetro de igual nombre (sin distinguir mayúsculas). Una colección se enlaza **repitiendo la clave**:

```csharp
public class FiltroProductos
{
    public string? Texto { get; set; }
    public decimal? PrecioMax { get; set; }
    public EstadoPedido? Estado { get; set; }
    public DateTime? Desde { get; set; }
    public int[] Categorias { get; set; } = [];
}

[HttpGet("filtro")]
public IActionResult Filtro([FromQuery] FiltroProductos filtro) => Ok(filtro);

[HttpGet("por-ids")]
public IActionResult PorIds([FromQuery] int[] ids) => Ok(new { ids });
```

```bash
curl "http://localhost:6720/api/productos/filtro?texto=teclado&precioMax=19.5&estado=Pagado&desde=2026-11-10&categorias=1&categorias=7"
# {"texto":"teclado","precioMax":19.5,"estado":2,"desde":"2026-11-10T00:00:00","categorias":[1,7]}

curl "http://localhost:6720/api/productos/por-ids?ids=1&ids=2&ids=3"     # {"ids":[1,2,3]}
curl "http://localhost:6720/api/productos/por-ids?ids=1,2"               # 400
```

Lista separada por comas (`ids=1,2`) **no** se interpreta como dos valores: se intenta convertir `1,2` a `int` y responde `400` con `"ids":["The value '1,2' is not valid."]`. Si se quiere esa sintaxis hay que recibir un `string` y dividirlo, o escribir un binder propio.

### Enums

Desde la query o el formulario, un enum acepta su **nombre** (sin distinguir mayúsculas) o su **valor numérico**, y rechaza lo desconocido. Comprobado con `EstadoPedido { Borrador, Confirmado, Pagado, Cancelado }`:

| Entrada | Resultado |
|---|---|
| `estado=Pagado` o `estado=pagado` | `Pagado` |
| `estado=2` | `Pagado` |
| `estado=Inexistente` | `400`: `"estado":["The value 'Inexistente' is not valid."]` |
| `estado=99` | `400`: `"estado":["The value '99' is invalid."]` |

El valor `99` no es un nombre ni corresponde a un miembro definido, y el mensaje cambia a `is invalid`. En el cuerpo JSON el comportamiento es distinto (ver más abajo): por defecto, solo se aceptan números.

### Fechas

Un `DateTime` de la query se interpreta con el formato que reconozca la cultura invariante, y conserva el `Kind` según lleve o no zona:

```bash
curl "http://localhost:6720/api/productos/fecha?desde=2026-11-10T10:00:00Z&estado=2"
# {"desde":"2026-11-10T10:00:00Z","desdeKind":"Utc","estado":2}

curl "http://localhost:6720/api/productos/fecha?desde=10/11/2026&estado=pagado"
# {"desde":"2026-10-11T00:00:00","desdeKind":"Unspecified","estado":2}
```

`10/11/2026` se leyó como **11 de octubre** (mes/día), aunque la máquina tenía cultura `es-ES`: la query usa siempre la cultura invariante. Con ISO 8601 (`2026-11-10T10:00:00Z`) no hay ambigüedad.

## Cuando el valor no se puede convertir

Si el texto no encaja con el tipo, el binder no lanza una excepción: anota el fallo en el `ModelState` y la acción decide. Con `[ApiController]` la acción **no llega a ejecutarse** y la respuesta es un `400` con `ProblemDetails`, cuyo campo `errors` agrupa los mensajes por nombre de parámetro:

```bash
curl -i "http://localhost:6720/api/productos/42?pagina=abc"
```

```text
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"pagina":["The value 'abc' is not valid."]},"traceId":"00-…"}
```

Varios fallos se acumulan en la misma respuesta: `?desde=ayer&estado=Inexistente` devuelve `"desde":["The value 'ayer' is not valid."]` y `"estado":["The value 'Inexistente' is not valid."]`.

Sin `[ApiController]`, el `ModelState` queda lleno pero nadie lo mira: la acción se ejecuta con el valor por defecto (`id = 0`). Hay que comprobarlo a mano:

```csharp
[Route("api/clasico")]
public class ClasicoController : ControllerBase
{
    [HttpGet("{id}")]
    public IActionResult Get(int id)
    {
        if (!ModelState.IsValid)
            return BadRequest(ModelState.ToDictionary(k => k.Key, v => new
            {
                v.Value!.AttemptedValue,
                Errores = v.Value.Errors.Select(e => e.ErrorMessage)
            }));
        return Ok(new { id });
    }
}
```

```bash
curl http://localhost:6720/api/clasico/abc
# {"id":{"attemptedValue":"abc","errores":["The value 'abc' is not valid."]}}
```

`AttemptedValue` conserva el texto original que llegó, útil para devolverlo al usuario en un formulario. El formato de estos errores y cómo personalizarlos está en [`[ApiController]`](ApiController.md); las reglas de validación (`[Required]`, `[Range]`...) se explican en [Validación con Data Annotations](Validacion-con-DataAnnotations.md).

## El cuerpo JSON: qué tolera y qué rechaza

`[FromBody]` no usa el binder de valores sino un *input formatter*, y sus reglas son las de `System.Text.Json` con los valores por defecto de ASP.NET Core. Los resultados, con `CrearPedidoRequest`:

**Campos desconocidos: se ignoran en silencio.** Y los nombres no distinguen mayúsculas:

```bash
curl -i -X POST http://localhost:6720/api/pedidos -H "Content-Type: application/json" \
  -d '{"CLIENTE":"Ana","lineas":[{"Sku":"TEC-01","cantidad":2,"descuento":99}],"esAdmin":true}'
```

```text
HTTP/1.1 201 Created

{"cliente":"Ana","lineas":[{"sku":"TEC-01","cantidad":2}],"estado":0}
```

`CLIENTE` se asignó a `Cliente`; `descuento` y `esAdmin` no existen en el tipo y desaparecen sin error.

**Tipo erróneo: `400` con la ruta JSON del fallo.**

```bash
curl -X POST http://localhost:6720/api/pedidos -H "Content-Type: application/json" \
  -d '{"cliente":"Ana","lineas":[{"sku":"TEC-01","cantidad":"dos"}]}'
```

```json
{"title":"One or more validation errors occurred.","status":400,"errors":{"request":["The request field is required."],"$.lineas[0].cantidad":["The JSON value could not be converted to Tienda.Api.Modelos.LineaRequest. Path: $.lineas[0].cantidad | LineNumber: 0 | BytePositionInLine: 59."]}}
```

La clave `$.lineas[0].cantidad` señala el campo exacto. Hay dos rarezas en el mensaje: el texto menciona `LineaRequest` (el tipo que se construía) y no `Int32`, porque los `record` con constructor se deserializan por parámetros; y aparece un `"request":["The request field is required."]` adicional, ruido causado por el mismo fallo (el parámetro quedó sin valor). El dato útil es la clave que empieza por `$.`.

**Otros casos comprobados:**

| Petición | Respuesta |
|---|---|
| JSON truncado (`{"cliente":`) | `400`, `"$.cliente":["Expected depth to be zero at the end of the JSON payload…"]` |
| Cuerpo vacío o `null` | `400`, `"":["A non-empty request body is required."]` |
| Sin `Content-Type` | `415 Unsupported Media Type` |
| Falta una propiedad que no admite nulos (`{"lineas":[]}`) | `400`, `"Cliente":["The Cliente field is required."]` |
| `"estado":"Pagado"` (nombre del enum) | `400`, `"$.estado":["The JSON value could not be converted to …CrearPedidoRequest…"]` |
| `"estado":2` | Acepta (`Pagado`) |

La penúltima fila sorprende: en JSON, un enum solo admite el número por defecto. Para admitir nombres hay que registrar el conversor, y el mismo bloque permite **rechazar** los campos desconocidos en lugar de ignorarlos:

```csharp
builder.Services.AddControllers().AddJsonOptions(o =>
{
    o.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter());
    o.JsonSerializerOptions.UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow;
});
```

Con esa configuración (probada en un proyecto aparte):

```text
{"cliente":"Ana","estado":"Pagado"}   ->  200  {"cliente":"Ana","estado":"Pagado"}
{"cliente":"Ana","esAdmin":true}      ->  400  "$.esAdmin":["The JSON property 'esAdmin' could not be mapped to any .NET member contained in type 'CrearPedidoRequest'."]
{"cliente":"Ana","estado":"Inventado"} -> 400
```

Que falte `Cliente` sea un `400` se debe a que MVC trata como obligatoria toda propiedad no anulable cuando está activo `<Nullable>enable</Nullable>`: es validación, no binding, y se explica en [Validación con Data Annotations](Validacion-con-DataAnnotations.md).

### Solo un `[FromBody]` por acción

El cuerpo es un flujo que se lee una vez. Dos parámetros que provengan de él no son posibles, y el error no aparece al llamar a la acción sino **al arrancar la aplicación**:

```csharp
[HttpPost] public IActionResult Post([FromBody] A a, [FromBody] B b) => Ok();
```

```text
Unhandled exception. System.InvalidOperationException: Action 'DosController.Post (dosbody)' has more than one parameter that was specified or inferred as bound from request body. Only one parameter per action may be bound from body. Inspect the following parameters, and use 'FromQueryAttribute' to specify bound from query, 'FromRouteAttribute' to specify bound from route, and 'FromBodyAttribute' for parameters to be bound from body:
A a
B b
```

La salida es agrupar ambos en un único tipo (`record CrearPedidoRequest(A A, B B)`). El mismo error aparece si, con `[ApiController]`, dos tipos complejos se infieren del cuerpo.

## `[BindNever]` y `[BindRequired]`

Son atributos de propiedad que ajustan el binder: `[BindNever]` indica que la propiedad **no debe** enlazarse nunca; `[BindRequired]` que **debe** venir en la petición (a diferencia de `[Required]`, que valida el valor ya enlazado: la diferencia importa en tipos por valor, donde «no enviado» y `0` son indistinguibles).

```csharp
public class PedidoConAtributos
{
    [BindNever]    public int Id { get; set; }
    [BindRequired] public string Cliente { get; set; } = "";
    public decimal Total { get; set; }
}
```

Con `[FromForm]` (y con `[FromQuery]`) funcionan como dicen:

```bash
curl -X POST http://localhost:6720/api/atributos/form -d id=99 -d cliente=Ana -d total=5
# {"id":0,"cliente":"Ana","total":5}              <- id=99 ignorado

curl -X POST http://localhost:6720/api/atributos/form -d id=99 -d total=5
# 400  "Cliente":["A value for the 'Cliente' parameter or property was not provided."]
```

**Con `[FromBody]` JSON, no tienen ningún efecto.** El mismo tipo recibido del cuerpo:

```bash
curl -X POST http://localhost:6720/api/pedidos/atributos -H "Content-Type: application/json" \
  -d '{"id":99,"cliente":"Ana","total":5}'
# {"id":99,"cliente":"Ana","total":5}             <- BindNever no impidió asignar id

curl -X POST http://localhost:6720/api/pedidos/atributos -H "Content-Type: application/json" \
  -d '{"total":5}'
# 200 {"id":0,"cliente":"","total":5}             <- BindRequired no exigió cliente
```

`System.Text.Json` no consulta los atributos del model binder. Defenderse del *sobreposting* en un cuerpo JSON no puede apoyarse en `[BindNever]`.

## Sobreposting: no enlazar la entidad

El *sobreposting* (*over-posting* o *mass assignment*) consiste en que el cliente envíe propiedades que la API no pensaba aceptar y el binder las asigne porque existen en el tipo. Si la acción recibe directamente la entidad `Pedido`, el cliente decide hasta su total y su estado:

```csharp
public class Pedido
{
    public int Id { get; set; }
    public string Cliente { get; set; } = "";
    public EstadoPedido Estado { get; set; } = EstadoPedido.Borrador;
    public decimal Total { get; set; }
    public decimal DescuentoPorcentaje { get; set; }
}
```

❌ **Enlazar la entidad:**

```csharp
[HttpPost("mal")]
public IActionResult Crear([FromBody] Pedido pedido)
    => Created("/api/pedidos/4711", pedido);
```

```bash
curl -X POST http://localhost:6720/api/pedidos/mal -H "Content-Type: application/json" \
  -d '{"cliente":"Ana","estado":2,"total":0.01,"descuentoPorcentaje":100,"id":1}'
# 201  {"id":1,"cliente":"Ana","estado":2,"total":0.01,"descuentoPorcentaje":100}
```

Un pedido nuevo nace ya `Pagado` (`estado: 2`), por un céntimo y con 100 % de descuento, y con un `Id` elegido por quien llama, que si luego se guarda con Entity Framework puede **sobrescribir** otro pedido.

✅ **Un DTO con solo lo que el cliente puede decidir:**

```csharp
public class CrearPedidoDto
{
    [Required] public string Cliente { get; set; } = "";
}

[HttpPost("bien")]
public IActionResult Crear([FromBody] CrearPedidoDto dto)
{
    var pedido = new Pedido { Id = 4711, Cliente = dto.Cliente };
    return Created("/api/pedidos/4711", pedido);
}
```

```bash
curl -X POST http://localhost:6720/api/pedidos/bien -H "Content-Type: application/json" \
  -d '{"cliente":"Ana","estado":2,"total":0.01,"descuentoPorcentaje":100,"id":1}'
# 201  {"id":4711,"cliente":"Ana","estado":0,"total":0,"descuentoPorcentaje":0}
```

Las propiedades extra se ignoran porque no existen en el DTO; el identificador, el estado inicial y el total los decide el servidor (el total se calcularía a partir de las líneas y los precios del catálogo). Un DTO separado de la entidad es la defensa fiable en cualquier formato de entrada; `[BindNever]` solo protege formularios y query, y `UnmappedMemberHandling.Disallow` convierte el intento en un `400` visible en lugar de un descarte silencioso. Cómo organizar DTO, entidad y casos de uso está en [Clean Architecture](../../arquitectura-de-software/clean-architecture/Clean-Architecture.md).

## Equivalencias en Minimal APIs

Las Minimal APIs (ver [Modelos de programación web](Modelos-de-programacion-web.md)) usan los mismos atributos `[From...]` y la misma inferencia, pero con otro motor de binding, con diferencias reales:

```csharp
var min = app.MapGroup("/min");

min.MapGet("/productos/{id}", (int id, int pagina = 1,
    [FromHeader(Name = "X-Tenant-Id")] string? tenant = null) => new { id, pagina, tenant });

min.MapGet("/ids", (int[] ids) => ids);

min.MapPost("/pedidos", (CrearPedidoRequest request) =>
    TypedResults.Created("/min/pedidos/4711", request));

min.MapGet("/servicios", (IDescuentos d, [FromKeyedServices("sms")] INotificador n)
    => new { d = d.Para("x"), n = n.Canal });
```

```bash
curl -H "X-Tenant-Id: acme" "http://localhost:6720/min/productos/42?pagina=2"
# {"id":42,"pagina":2,"tenant":"acme"}
curl "http://localhost:6720/min/ids?ids=1&ids=2"          # [1,2]
```

La inferencia es la misma en lo esencial (ruta si el nombre está en la plantilla, query en otro caso, cuerpo para tipos complejos, servicios del contenedor sin atributo). Las diferencias:

- **`[AsParameters]`** agrupa varios parámetros en un tipo, como hace `[FromQuery]` sobre una clase en MVC. Cada miembro admite su propio atributo `[From...]`:

  ```csharp
  min.MapGet("/filtro", ([AsParameters] FiltroMin f) => f);

  record FiltroMin(int Pagina, string? Texto, [FromHeader(Name = "X-Tenant-Id")] string? Tenant);
  ```

  ```bash
  curl -H "X-Tenant-Id: acme" "http://localhost:6720/min/filtro?pagina=3&texto=teclado"
  # {"pagina":3,"texto":"teclado","tenant":"acme"}
  ```

- **El error de conversión no es un `ProblemDetails`.** `GET /min/productos/abc` responde `400` con un texto de excepción (`BadHttpRequestException: Failed to bind parameter "int id" from "abc".`) en el entorno `Development`, y un `400` **de cuerpo vacío** en `Production`. No hay `ModelState` ni `errors` por campo: para devolver `ProblemDetails` hay que configurarlo aparte.
- **No hay `ModelState`, ni `[BindNever]`/`[BindRequired]`, ni validación automática** con Data Annotations. En Minimal APIs, la validación declarativa es opcional y se activa explícitamente (ver [Validación con Data Annotations](Validacion-con-DataAnnotations.md)).
- **Un tipo sin `required` acepta `null`.** `POST /min/pedidos` con `{"lineas":[]}` responde `201` y devuelve `"cliente":null`, a diferencia de MVC, que rechaza la ausencia de `Cliente` con el `400` ya visto.
- **Cuerpo ausente:** `400` con `Implicit body inferred for parameter "request" but no body was provided. Did you mean to use a Service instead?`. Sin `Content-Type` JSON, `415`.
- **`TypedResults`** devuelve el resultado con su tipo concreto (`TypedResults.Created(...)`, `TypedResults.Ok(...)`) y permite declarar en la firma las alternativas posibles con `Results<Ok<string>, BadRequest<string>>`, de modo que el compilador sabe qué respuestas existen y OpenAPI las documenta sin `[ProducesResponseType]`. Qué se puede devolver desde una acción MVC está en [Tipos de retorno de una acción](Tipos-de-Retorno-de-una-Accion.md).

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `400` con `"id":["The value 'abc' is not valid."]` | El texto no se convierte al tipo del parámetro. Ocurre antes de ejecutar la acción. |
| `400` con `"X-Tenant-Id":["The tenantId field is required."]` | La cabecera falta y el parámetro `string` no es anulable. Declara `string?` si es opcional. |
| `415 Unsupported Media Type` en un `POST` con cuerpo | Falta `Content-Type: application/json` en la petición. |
| `400` con `"":["A non-empty request body is required."]` | Cuerpo vacío o literal `null` hacia un `[FromBody]`. |
| `400` con `"$.estado":["The JSON value could not be converted to…"]` | Se envió el nombre de un enum (`"Pagado"`) sin `JsonStringEnumConverter`, o un tipo equivocado. |
| `InvalidOperationException: … more than one parameter that was specified or inferred as bound from request body` al arrancar | Dos parámetros del cuerpo en la misma acción. Agrúpalos en un único tipo. |
| `415 Unsupported Media Type` en un `GET` con un objeto de filtros | Sin `[FromQuery]`, `[ApiController]` infiere que el tipo complejo viene del cuerpo y espera un JSON que un `GET` no trae. |
| Un campo del JSON llega a `null` o `0` sin error | El nombre no coincide con ninguna propiedad y los desconocidos se ignoran en silencio. Revisa el nombre, o rechaza lo desconocido con `UnmappedMemberHandling.Disallow`. |
| `[BindNever]` o `[BindRequired]` «no hacen nada» | La acción recibe un cuerpo JSON: esos atributos solo actúan en el binder de valores (query, formulario, ruta). |
| El valor decimal llega multiplicado por diez | Un formulario se interpretó con la cultura del servidor (ver más abajo). |

## Buenas prácticas avanzadas

- **Recibe siempre un DTO de entrada, nunca la entidad.** Es la única defensa contra el sobreposting que funciona igual en JSON, formulario y query. `[BindNever]` no protege el cuerpo JSON, como muestra la salida de arriba.
- **La cultura afecta al formulario, no a la query.** Query string y ruta se interpretan con la cultura invariante; los campos de un formulario, con la cultura del servidor. En la máquina de las pruebas (`es-ES`), `total=1.5` en un formulario produjo `15` **sin error**, y `total=1,5` produjo `1.5`; en la query ocurrió al revés (`1,5` → `15`, `1.5` → `1.5`). Un mismo servidor puede interpretar distinto el mismo decimal según el origen. En APIs, prefiere JSON (que usa siempre el punto) y fechas ISO 8601.
- **Una colección es `?ids=1&ids=2`, no `?ids=1,2`.** Si el contrato público necesita comas, documenta que se recibe un `string` y se divide a mano; no esperes que el binder lo haga.
- **Rechaza lo que no esperabas.** `UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow` convierte un campo mal escrito (`"cantidd"`) en un `400` en lugar de un `0` silencioso; el precio es que añadir campos nuevos en un cliente más moderno rompe contra un servidor antiguo, así que encaja mejor en APIs internas que en públicas.
- **Distingue «no enviado» de «enviado vacío» con tipos anulables.** Un `int` o un `bool` sin enviar valen `0` o `false`, y un parámetro de query ausente no es un error. Usa `int?` para detectar la ausencia, y `[BindRequired]` (en query/formulario) o el modificador `required` de C# 11 (en el cuerpo JSON produce `JSON deserialization for type 'ConRequired' was missing required properties including: 'cliente'.`) para exigirla.
- **Los parámetros opcionales de una query se declaran con valor por defecto o `?`.** `[FromQuery] int pagina = 1` define el comportamiento si falta; sin valor por defecto, un `int` ausente es `0`, que casi nunca es lo que se quería.

## Documentación oficial

- [Model Binding in ASP.NET Core](https://learn.microsoft.com/aspnet/core/mvc/models/model-binding) — orden de los orígenes, tipos compatibles y binders personalizados; empieza por la tabla de atributos y por «Sources».
- [Parameter binding in Minimal APIs](https://learn.microsoft.com/aspnet/core/fundamentals/minimal-apis/parameter-binding) — reglas de inferencia, `[AsParameters]` y `BindAsync`/`TryParse` para tipos propios.
- [Create web APIs with ASP.NET Core: binding source parameter inference](https://learn.microsoft.com/aspnet/core/web-api/#binding-source-parameter-inference) — la tabla exacta de qué infiere `[ApiController]` para cada tipo.

---

*En resumen: los atributos `[From...]` dicen de qué parte de la petición sale cada parámetro, el binder anota en el `ModelState` lo que no puede convertir (y `[ApiController]` lo convierte en un `400`), y para no dejar que el cliente decida campos que no le tocan, la acción recibe un DTO y no la entidad.*
