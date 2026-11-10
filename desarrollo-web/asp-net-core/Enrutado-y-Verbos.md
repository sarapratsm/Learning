# Enrutado y verbos HTTP

## ¿Qué es?

El **enrutado** (*routing*) es el mecanismo de ASP.NET Core que decide qué código ejecuta cada petición según su **URL** y su **verbo HTTP**. En un controlador se declara con atributos junto a cada método: `[Route]` fija una plantilla de URL y `[HttpGet]`, `[HttpPost]`, `[HttpPut]`, `[HttpPatch]` y `[HttpDelete]` fijan el verbo. A esa técnica se le llama *attribute routing*.

## ¿Por qué existe?

Una petición llega como texto: `GET /api/pedidos/4711/lineas`. Alguien tiene que convertirlo en «llama al método `Lineas` con `id = 4711`». ASP.NET Core resuelve esa traducción al arrancar: recorre los controladores, lee los atributos y construye una **tabla de rutas** (cada fila es un *endpoint*: una plantilla, un verbo y el método a ejecutar). En cada petición, el middleware de routing busca en esa tabla la fila que encaja y deja el resultado para que el resto del *pipeline* lo ejecute.

Declarar la ruta al lado del método tiene una ventaja práctica: al leer el código se ve qué URL atiende cada acción, sin consultar un fichero de configuración aparte.

> Si vienes del mundo de las bases de datos, la tabla de rutas se parece a un índice: se construye una vez y cada petición hace una búsqueda, no un recorrido de todos los controladores.

Los atributos son metadatos que el framework lee por *reflection* al arrancar ([ver Atributos](../../lenguajes/csharp-dotnet/caracteristicas-del-lenguaje/Atributos.md)); no hacen nada por sí mismos.

## ¿Cuándo y para qué se usa?

En cuanto una API tiene más de un endpoint. En la API de una tienda online (`Tienda.Api`), `/api/productos` y `/api/pedidos` son dos recursos, y cada operación (listar, ver uno, crear, reemplazar, modificar, borrar) es un método con su verbo y su plantilla. Las convenciones de qué verbo corresponde a qué operación forman parte del estilo REST ([REST](../../arquitectura-de-software/tipos-de-apis/REST.md)); aquí interesa cómo se declaran y cómo se resuelven en ASP.NET Core.

Las salidas citadas provienen de un proyecto `dotnet new web` con controladores, .NET SDK 10.0.401, ejecutado el 2026-11-10 con `dotnet run` y atacado con `curl`. Los controladores están abreviados respecto al código probado: devuelven datos fijos con `Ok(...)` para centrar la atención en la ruta.

## Un controlador con sus rutas

El **prefijo común** se declara con `[Route]` en la clase y cada método añade su parte con un atributo de verbo:

```csharp
[ApiController]
[Route("api/[controller]")]            // prefijo: /api/Productos
public class ProductosController : ControllerBase
{
    [HttpGet]                                          // GET    /api/productos
    public IActionResult Listar() => Ok(new[] { "teclado", "ratón" });

    [HttpGet("{id:int}", Name = "ObtenerProducto")]    // GET    /api/productos/42
    public IActionResult Obtener(int id) => Ok(new { id, nombre = "teclado" });

    [HttpPut("{id:int}")]                              // PUT    /api/productos/42
    public IActionResult Reemplazar(int id) => NoContent();

    [HttpPatch("{id:int}")]                            // PATCH  /api/productos/42
    public IActionResult Modificar(int id) => NoContent();

    [HttpDelete("{id:int}")]                           // DELETE /api/productos/42
    public IActionResult Borrar(int id) => NoContent();
}
```

Las plantillas del atributo de verbo se **concatenan** con la del `[Route]` de la clase. Qué devuelve cada `Ok(...)` o `NoContent()` se explica en [Tipos de retorno de una acción](Tipos-de-Retorno-de-una-Accion.md); `[ApiController]`, en [ApiController](ApiController.md).

```text
$ curl -i http://localhost:6710/api/Productos/42
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

{"id":42,"nombre":"teclado"}
```

### Tokens `[controller]` y `[action]`

Entre corchetes se escriben **tokens**, que el framework sustituye al construir la tabla:

| Token | Se sustituye por | Ejemplo |
|---|---|---|
| `[controller]` | Nombre de la clase sin el sufijo `Controller` | `ProductosController` → `Productos` |
| `[action]` | Nombre del método | `Enlaces` → `enlaces` en `[HttpGet("[action]")]` |
| `[area]` | Nombre del área (agrupación opcional de controladores) | No se usa aquí |

El token conserva las mayúsculas de la clase (`Productos`), pero la comparación con la URL **no distingue mayúsculas**: `/api/productos/42`, `/API/PRODUCTOS/42/` y `/api/Productos/42` llegan al mismo método (comprobado; la barra final también se tolera).

```text
$ curl -i http://localhost:6710/API/PRODUCTOS/42/
HTTP/1.1 200 OK
...
{"id":42,"nombre":"teclado"}
```

Con el token, renombrar la clase renombra la URL y rompe a los clientes sin que el compilador avise. En una API pública suele ser más seguro escribir el literal (`[Route("api/productos")]`), que es lo que usan los controladores de `PedidosController` en el resto de ejemplos.

### Rutas absolutas: `~/` y `/`

Una plantilla que empieza por `~/` o `/` **ignora el prefijo** del controlador:

```csharp
[HttpGet("~/api/catalogo")]     // GET /api/catalogo, no /api/productos/api/catalogo
public IActionResult Catalogo() => Ok("catalogo");
```

Útil para un caso suelto; si hay que usarlo a menudo, ese método probablemente pertenece a otro controlador.

## Parámetros de ruta y restricciones

Las partes entre llaves son **parámetros de ruta**: huecos que se rellenan con el segmento correspondiente de la URL y se entregan al parámetro del método con el mismo nombre (de dónde sale cada valor lo detalla [Model binding](Model-Binding.md)).

Tras los dos puntos se escribe una **restricción** (*route constraint*): una condición que el segmento debe cumplir para que la ruta encaje. Si no la cumple, esa ruta se descarta como candidata, el método nunca se ejecuta y, si ninguna otra ruta encaja, el resultado es un `404`.

| Plantilla | Encaja con | No encaja con |
|---|---|---|
| `{id:int}` | `/api/productos/42` | `/api/productos/abc` |
| `{codigo:guid}` | `/ref/3f2504e0-4f89-11d3-9a0c-0305e82c3301` | `/ref/not-a-guid` |
| `{sku:alpha}` | `abc` | `a-b`, `42` |
| `{n:min(1)}`, `{s:minlength(3)}` | Valores dentro del rango o de la longitud | Fuera de ellos |
| `{categoria?}` | `/categoria` y `/categoria/perifericos` | (el `?` marca el parámetro como opcional) |
| `{sku:regex(...)}` | Lo que cumple la expresión regular | Lo demás |

```csharp
[HttpGet("categoria/{categoria?}")]                       // parámetro opcional
public IActionResult PorCategoria(string? categoria) =>
    Ok(new { categoria = categoria ?? "(todas)" });

[HttpGet("ref/{codigo:guid}")]
public IActionResult PorGuid(Guid codigo) => Ok(new { codigo });
```

```text
$ curl -i http://localhost:6710/api/productos/categoria
HTTP/1.1 200 OK
{"categoria":"(todas)"}

$ curl -i http://localhost:6710/api/productos/categoria/perifericos
HTTP/1.1 200 OK
{"categoria":"perifericos"}

$ curl -i http://localhost:6710/api/productos/ref/not-a-guid
HTTP/1.1 404 Not Found
Content-Length: 0
```

Las restricciones de tipo (`int`, `guid`) hacen más que validar: **sirven para elegir ruta** (ver [Ambigüedad de rutas](#ambigüedad-de-rutas)). Pero no sustituyen a la validación del contenido: `{id:int}` acepta `-5` y `0`.

### Expresiones regulares en la plantilla

`regex(...)` acepta una expresión, con una trampa: dentro de la plantilla, `{`, `}`, `[` y `]` se **duplican** para distinguirlos de los delimitadores de la propia plantilla. Una referencia de producto como `TEC-0001` (tres letras, guion, cuatro dígitos):

```csharp
[HttpGet(@"{sku:regex(^[[A-Z]]{{3}}-\d{{4}}$)}")]     // expresión real: ^[A-Z]{3}-\d{4}$
public IActionResult PorSku(string sku) => Ok(new { sku });
```

```text
$ curl http://localhost:6710/api/productos/TEC-0001
{"sku":"TEC-0001"}
$ curl -i http://localhost:6710/api/productos/abc
HTTP/1.1 404 Not Found
```

Si la regla de formato crece, es mejor validar en el método y devolver un error con información que dejar que la ruta responda un `404` mudo.

## Rutas anidadas

Cuando un recurso pertenece a otro (las líneas de un pedido), la URL lo refleja con segmentos consecutivos y cada parámetro mantiene su nombre:

```csharp
[ApiController]
[Route("api/pedidos")]
public class PedidosController : ControllerBase
{
    [HttpGet("{id:int}", Name = "ObtenerPedido")]          // /api/pedidos/4711
    public IActionResult Obtener(int id) => Ok(new { id });

    [HttpGet("{id:int}/lineas")]                           // /api/pedidos/4711/lineas
    public IActionResult Lineas(int id) =>
        Ok(new[] { new { pedido = id, linea = 1 } });

    [HttpGet("{id:int}/lineas/{lineaId:int}")]             // /api/pedidos/4711/lineas/2
    public IActionResult Linea(int id, int lineaId) =>
        Ok(new { pedido = id, linea = lineaId });
}
```

```text
$ curl http://localhost:6710/api/pedidos/4711/lineas
[{"pedido":4711,"linea":1}]

$ curl http://localhost:6710/api/pedidos/4711/lineas/2
{"pedido":4711,"linea":2}
```

Las tres rutas viven en el mismo controlador porque la raíz del recurso es el pedido. Una ruta anidada solo debería llevar un nivel: `/api/pedidos/4711/lineas/2` es legible; `/api/clientes/7/pedidos/4711/lineas/2` obliga al cliente a conocer toda la cadena, cuando `/api/pedidos/4711/lineas/2` basta (el pedido ya identifica al cliente).

## Nombres de ruta y generación de URLs

El enrutado también funciona al revés: dado un endpoint y sus valores, **genera** la URL. Para ello se le da un nombre a la ruta con `Name`:

```csharp
[HttpGet("{id:int}", Name = "ObtenerProducto")]
public IActionResult Obtener(int id) => Ok(new { id });

[HttpPost]
public IActionResult Crear([FromBody] CrearPedidoRequest r) =>
    CreatedAtRoute("ObtenerProducto", new { id = 99 }, new { id = 99 });   // abreviado: aquí no se crea nada
```

`CreatedAtRoute` responde `201 Created` y rellena la cabecera `Location` con la URL generada a partir del nombre y del valor de `id`. En `PedidosController`, el mismo patrón con `"ObtenerPedido"`:

```text
$ curl -i -X POST http://localhost:6710/api/pedidos \
       -H 'Content-Type: application/json' \
       -d '{"clienteId":7,"lineas":[{"sku":"TEC-0001","cantidad":1}]}'
HTTP/1.1 201 Created
Content-Type: application/json; charset=utf-8
Location: http://localhost:6710/api/pedidos/4711

{"id":4711}
```

Fuera de las acciones (en un servicio, en un enlace dentro de una respuesta) se usa `Url.Link` o `Url.Action`:

```csharp
Url.Link("ObtenerProducto", new { id = 42 })   // http://localhost:6710/api/productos/42   (URL absoluta)
Url.Action(nameof(Destacados))                 // /api/productos/destacados                (relativa)
```

El nombre debe ser **único en toda la aplicación** salvo que las rutas con el mismo nombre tengan la misma plantilla. Si no, la aplicación **no arranca**:

```text
Unhandled exception. System.InvalidOperationException: The following errors occurred with attribute routing information:

Error 1:
Attribute routes with the same name 'Obtener' must have the same template:
Action: 'ProductosController.PorId (Ambig)' - Template: 'api/productos/{id:int}'
Action: 'ProductosController.Destacados (Ambig)' - Template: 'api/productos/destacados'
```

La opción `AddRouting(o => o.LowercaseUrls = true)` hace que las URL **generadas** salgan en minúsculas: con ella, `Url.Link` devolvió `/api/productos/42` aunque el token `[controller]` produce `Productos`. No cambia qué URL entrantes se aceptan (esas ya ignoraban las mayúsculas).

## Versión en la URL

La forma más simple de versionar una API es poner la versión en la ruta y tener un controlador por versión:

```csharp
[ApiController]
[Route("api/v1/pedidos")]
public class PedidosV1Controller : ControllerBase
{
    [HttpGet("{id:int}")]
    public IActionResult Obtener(int id) => Ok(new { version = 1, id });
}

[ApiController]
[Route("api/v2/pedidos")]
public class PedidosV2Controller : ControllerBase
{
    [HttpGet("{id:int}")]
    public IActionResult Obtener(int id) => Ok(new { version = 2, id, estado = "Confirmado" });
}
```

```text
$ curl http://localhost:6710/api/v1/pedidos/4711
{"version":1,"id":4711}

$ curl http://localhost:6710/api/v2/pedidos/4711
{"version":2,"id":4711,"estado":"Confirmado"}
```

Las plantillas son distintas (`v1` y `v2` son segmentos literales), así que no hay ambigüedad. Para versionar también por cabecera o por parámetro de consulta, o para marcar versiones como obsoletas, existe el paquete NuGet `Asp.Versioning.Mvc`; no se ejecutó.

## 404, 405 y 415: cuál es cuál

El enrutado y la lectura del cuerpo producen tres códigos distintos que se confunden con facilidad. Salidas reales con las rutas de arriba:

| Situación | Código | Quién lo produce |
|---|---|---|
| Ninguna plantilla encaja con la URL (o una restricción la descarta) | `404 Not Found` | El routing |
| La URL encaja con alguna plantilla, pero ninguna acepta ese verbo | `405 Method Not Allowed` y cabecera `Allow` | El routing |
| La ruta y el verbo encajan, pero el `Content-Type` del cuerpo no lo acepta ningún *input formatter* | `415 Unsupported Media Type` | El model binding, ya dentro de la acción |

```text
$ curl -i http://localhost:6710/api/nada
HTTP/1.1 404 Not Found
Content-Length: 0

$ curl -i http://localhost:6710/api/pedidos/abc
HTTP/1.1 404 Not Found
Content-Length: 0
```

El `404` no lleva cuerpo. La URL `/api/pedidos/abc` existe como patrón, pero `abc` no es un `int`; el cliente no puede distinguir «el pedido no existe» de «esa ruta no existe». Un `NotFound()` devuelto desde la acción es otra cosa: la ruta sí encajó y el pedido concreto no está.

```text
$ curl -i -X POST http://localhost:6710/api/productos/42
HTTP/1.1 405 Method Not Allowed
Content-Length: 0
Allow: DELETE, GET, PATCH, PUT

$ curl -i -X DELETE http://localhost:6710/api/productos
HTTP/1.1 405 Method Not Allowed
Allow: GET, POST
```

El `405` es informativo: la cabecera `Allow` lista exactamente los verbos declarados para esa URL. Dos detalles comprobados:

- Una acción `[HttpGet]` **no atiende `HEAD`**: `curl -I http://localhost:6710/api/productos/42` responde `405` con `Allow: DELETE, GET, PATCH, PUT`. Para atenderlo se añade `[HttpHead("{id:int}")]` a la acción (comprobado: con él, `curl -I` responde `200`).
- `OPTIONS` también devuelve `405` mientras no se configure CORS (comprobado sin CORS: `405`).

```text
$ curl -i -X POST http://localhost:6710/api/pedidos \
       -H 'Content-Type: text/plain' -d 'hola'
HTTP/1.1 415 Unsupported Media Type
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.16","title":"Unsupported Media Type","status":415,"traceId":"00-64ecf618c773a1dae9b6b03f2402539c-49dd310f785df7f0-00"}
```

El `415` aparece también cuando **falta** la cabecera `Content-Type`: `curl -X POST http://localhost:6710/api/pedidos -d '{"clienteId":7}'` envía `application/x-www-form-urlencoded` por defecto y recibe el mismo `415`; un `POST` sin cuerpo ni cabecera, igual. El cuerpo `application/json` bien formado pero con un tipo equivocado (`"clienteId":"x"`) ya no es un `415` sino un `400` de validación; los detalles están en [Model binding](Model-Binding.md).

## Ambigüedad de rutas

Si una petición encaja con **dos o más endpoints con la misma prioridad**, el routing no elige: lanza `AmbiguousMatchException`. Dos acciones con la misma plantilla y el mismo verbo, aunque con distinto nombre de parámetro:

```csharp
[HttpGet("{id:int}")]
public IActionResult PorId(int id) => Ok("PorId");

[HttpGet("{codigo:int}")]            // misma forma que la anterior
public IActionResult PorCodigo(int codigo) => Ok("PorCodigo");
```

Al compilar, el analizador de ASP.NET Core ya avisa:

```text
warning ASP0023: Route '{id:int}' conflicts with another action route. An HTTP request that matches multiple routes
results in an ambiguous match error. Fix the conflict by changing the route's pattern, HTTP method, or route constraints.
```

El aviso es solo un *warning*: la aplicación arranca, y la petición falla en ejecución:

```text
$ curl -i http://localhost:6711/api/productos/5
HTTP/1.1 500 Internal Server Error
```

El mensaje real aparece en el registro del servidor (en entorno `Production`, el cliente solo recibe el `500` sin cuerpo):

```text
Microsoft.AspNetCore.Routing.Matching.AmbiguousMatchException: The request matched multiple endpoints. Matches:

ProductosController.PorCodigo (Ambig)
ProductosController.PorId (Ambig)
```

Los nombres entre paréntesis son el ensamblado (aquí, el proyecto de prueba se llamaba `Ambig`).

### Qué gana cuando varias rutas encajan

No toda coincidencia múltiple es ambigua. El routing asigna una **precedencia** a cada plantilla según su forma, y elige la más específica. Sobre un controlador con estas cuatro acciones, declaradas en este orden:

```csharp
[HttpGet("{id:int}")]      public IActionResult PorId(int id)         => Ok("PorId");
[HttpGet("{nombre}")]      public IActionResult Generica(string nombre) => Ok("Generica");
[HttpGet("destacados")]    public IActionResult Destacados()           => Ok("Destacados");
[HttpGet("{sku:alpha}")]   public IActionResult Alfa(string sku)       => Ok("Alfa");
```

| URL | Acción que responde | Por qué |
|---|---|---|
| `/api/productos/5` | `PorId` | Parámetro con restricción (`int`) gana al parámetro sin restricción |
| `/api/productos/destacados` | `Destacados` | El segmento literal gana a cualquier parámetro |
| `/api/productos/abc` | `Alfa` | `alpha` es una restricción y `{nombre}` no lo es |
| `/api/productos/a-b` | `Generica` | `alpha` no encaja; solo queda el parámetro libre |

Se comprobó que **el orden de declaración en el fichero no cuenta**: `Destacados` se declaró después de `Generica` y aun así gana. Esto corrige la idea extendida de «pon las rutas más específicas primero»: en el enrutado por *endpoints* de ASP.NET Core, la especificidad la decide la plantilla.

Lo que **no** distingue la precedencia: dos plantillas con la misma forma y las mismas restricciones (el caso de arriba), y dos parámetros libres (`{nombre}/detalle` y `{slug}/detalle`). Para esos casos hay tres salidas, por orden de preferencia:

1. **Cambiar la plantilla** para que sea distinta (`{id:int}` y `por-codigo/{codigo:int}`).
2. **Cambiar el verbo**, si las operaciones son realmente distintas.
3. **Fijar un orden explícito** con la propiedad `Order` (número menor, mayor prioridad):

```csharp
[HttpGet("{id:int}", Order = 1)]     public IActionResult PorId(int id) => Ok("PorId");
[HttpGet("{codigo:int}", Order = 2)] public IActionResult PorCodigo(int codigo) => Ok("PorCodigo");
```

```text
$ curl -i http://localhost:6711/api/productos/5
HTTP/1.1 200 OK
PorId
```

`Order` funciona, pero deja una ruta que nunca se ejecutará para ese patrón: suele indicar un error de diseño.

## Correspondencia con Minimal APIs

Las Minimal APIs (ver [Modelos de programación web](Modelos-de-programacion-web.md)) usan el mismo motor de routing: plantillas, restricciones, precedencia, `404`/`405` y la cabecera `Allow` son idénticos. Cambia dónde se declara la ruta:

| Controlador | Minimal API |
|---|---|
| `[HttpGet("{id:int}")]` | `app.MapGet("/api/min/productos/{id:int}", (int id) => ...)` |
| `[HttpPost]` | `app.MapPost("/api/min/productos", () => ...)` |
| `[HttpPut]`, `[HttpDelete]` | `app.MapPut(...)`, `app.MapDelete(...)` |
| `[HttpPatch]` | `app.MapPatch(...)`, o `app.MapMethods(ruta, ["PATCH"], ...)` |
| `[Route("api/pedidos")]` en la clase | `var g = app.MapGroup("/api/pedidos");` y `g.MapGet("/{id:int}", ...)` |
| `Name = "ObtenerPedido"` | `.WithName("ObtenerPedido")` |
| Varios verbos en una ruta | `app.MapMethods(ruta, ["GET", "HEAD"], ...)` |

Se ejecutaron `MapGet`, `MapPost` y `MapMethods` con `["PATCH"]`; `MapPut`, `MapDelete`, `MapPatch`, `MapGroup` y `WithName` se citan por la documentación y no se ejecutaron. Las mismas respuestas que con controladores:

```text
$ curl http://localhost:6710/api/min/productos/42
{"id":42}

$ curl -i -X POST http://localhost:6710/api/min/productos/42
HTTP/1.1 405 Method Not Allowed
Allow: GET, PATCH

$ curl -i http://localhost:6710/api/min/productos/x
HTTP/1.1 404 Not Found
```

`GET` sobre `MapGet` tampoco responde `HEAD` (`curl -I` devolvió `405`).

## Errores frecuentes

| Síntoma | Causa y solución |
|---|---|
| `500` y `AmbiguousMatchException: The request matched multiple endpoints` | Dos acciones con la misma plantilla, mismas restricciones y mismo verbo (a veces en controladores distintos). Cambiar la plantilla o el verbo; `Order` es el último recurso. Aparece como aviso `ASP0023` al compilar: tratar ese aviso como error evita llegar a producción |
| La aplicación no arranca con `Attribute routes with the same name 'X' must have the same template` | Dos acciones usan el mismo `Name`. Los nombres de ruta son únicos en toda la aplicación |
| `404` con cuerpo vacío para una URL que parece correcta | El segmento no cumple una restricción (`/api/pedidos/abc` con `{id:int}`) o la ruta no se declaró. Revisar la plantilla completa: prefijo de clase más plantilla del método |
| `405` con `Allow` en una URL que sí existe | El verbo no coincide con ninguna acción para esa plantilla. La cabecera `Allow` lista los verbos válidos |
| `405` en `HEAD` o `OPTIONS` | `[HttpGet]` no atiende `HEAD`; `OPTIONS` no se atiende sin CORS |
| `415` en un `POST` que debería funcionar | Falta `Content-Type: application/json` (en `curl`, `-H 'Content-Type: application/json'` junto a `-d`) |
| La URL en `Location` sale con mayúsculas (`/api/Productos/99`) | El token `[controller]` conserva las mayúsculas de la clase. `AddRouting(o => o.LowercaseUrls = true)` normaliza las URL generadas |
| La regex de una restricción da error o no encaja | Dentro de la plantilla, `{`, `}`, `[` y `]` se escriben duplicados (`[[A-Z]]`, `{{3}}`) |

## Buenas prácticas avanzadas

- **Nada de verbos en la URL.** El verbo HTTP ya expresa la acción: `POST /api/pedidos`, no `POST /api/pedidos/crear`. La misma URL con otro verbo es otra operación, y eso hace la API predecible y cacheable (un `GET` se puede cachear, un `POST` no).
- **Distingue entre «no existe la ruta» y «no existe el recurso».** Una restricción `{id:int}` devuelve un `404` mudo para `abc`; el método puede devolver un `404` con `ProblemDetails` explicativo para el pedido `99999`. Si el cliente necesita saber cuál de los dos casos es, no restrinjas en la ruta y valida dentro de la acción.
- **Trata `ASP0023` como error de compilación.** Con `<WarningsAsErrors>ASP0023</WarningsAsErrors>` en el `.csproj` (comprobado: el build falla con `error ASP0023`), la ambigüedad, que de otro modo solo se descubre al ejecutar la petición, pasa a ser un fallo de compilación.
- **Escribe literales en las rutas públicas y reserva `[controller]` para las internas.** Renombrar una clase con `[Route("api/[controller]")]` cambia la URL pública sin ningún aviso, y los clientes empiezan a recibir `404`.
- **Pon un nombre a las rutas que apuntan a un recurso y genera las URL con él.** Con `CreatedAtRoute` y `Url.Link` el `Location` se mantiene correcto aunque cambie la plantilla; concatenar cadenas a mano se desincroniza en silencio.
- **Pon un test de integración sobre `404`/`405`/`415`.** Las reglas de enrutado se rompen con refactors pequeños (un prefijo cambiado, un verbo equivocado) y solo las detecta una petición real; [WebApplicationFactory](../../testing/testing-dotnet/WebApplicationFactory.md) permite hacerlo sin levantar un servidor externo.

## Documentación oficial

- [Routing en ASP.NET Core](https://learn.microsoft.com/es-es/aspnet/core/fundamentals/routing) — el motor de routing: plantillas, restricciones, precedencia y generación de URL. Empieza por «Route constraints» y «Route template precedence and ordering».
- [Enrutamiento a acciones de controlador](https://learn.microsoft.com/es-es/aspnet/core/mvc/controllers/routing) — attribute routing en controladores: `[Route]`, tokens, `Name`, `Order` y rutas absolutas.
- [Asp.Versioning en GitHub](https://github.com/dotnet/aspnet-api-versioning) — la librería de versionado de APIs (por URL, cabecera o consulta), cuando la versión en la ruta literal se queda corta.

## Recursos didácticos

- [http.cat](https://http.cat/) — cada código de estado HTTP ilustrado con un gato; sirve para fijar de golpe cuándo se usa el `404`, el `405` o el `415`.

---

*En resumen: `[Route]` y los atributos de verbo declaran qué URL y qué verbo activan cada método; el routing responde `404` si ninguna plantilla encaja, `405` (con `Allow`) si la URL existe pero no con ese verbo, y `AmbiguousMatchException` si dos rutas empatan en prioridad, y gana la plantilla más específica, no la declarada primero.*
