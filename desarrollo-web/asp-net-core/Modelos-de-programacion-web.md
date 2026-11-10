# Modelos de programación web de ASP.NET Core

## ¿Qué es?

ASP.NET Core ofrece varias formas de definir qué código atiende una petición HTTP y qué se devuelve: los **modelos de programación web**. Son cinco: **MVC** (controladores y vistas Razor), **Razor Pages** (una página con su lógica al lado), **Web API con controladores** (controladores que devuelven JSON), **Minimal APIs** (endpoints declarados en `Program.cs`) y **Blazor** (interfaces hechas con componentes en C#). Todos comparten el mismo servidor, inyección de dependencias, configuración y *middleware*.

## ¿Por qué existe?

No todas las aplicaciones web producen lo mismo: unas devuelven páginas HTML completas, otras exponen datos en JSON para una app móvil o un frontend de React, y otras son interfaces interactivas que reaccionan sin recargar la página. Un único estilo obligaría a usar la misma herramienta para problemas distintos. ASP.NET Core separa el motor común (el que explica [De .NET Core a ASP.NET Core](De-NET-Core-a-ASP-NET-Core.md)) de los modelos que se montan encima, y se elige el que encaja con la salida que se quiere producir.

> Si vienes de Spring, es la diferencia entre `@Controller` con plantillas Thymeleaf y `@RestController`: mismo contenedor, estilos distintos según lo que se devuelve.

## ¿Cuándo y para qué se usa?

La tienda online (`Tienda.Api`) puede necesitar varios modelos a la vez: un catálogo público con HTML que indexen los buscadores, una API `/api/productos` para la app móvil, un panel de administración con formularios y, quizá, una pantalla de gestión de pedidos muy interactiva. La pregunta que decide el modelo es **qué se devuelve** (HTML, JSON o una interfaz con estado) y **quién lo consume**.

Cada sección siguiente implementa el mismo caso, **listar y crear un producto**, en cada estilo. Los cuatro primeros viven en una sola aplicación (la que demuestra, en la sección de mezcla, que conviven); Blazor va en una aplicación aparte porque su plantilla trae su propia estructura. Las salidas citadas provienen de código ejecutado el 2026-11-10 con el SDK de .NET 10.0.401.

## El caso común: listar y crear un producto

Los cuatro estilos de servidor comparten estos tipos y este almacén en memoria (sustituye a un repositorio real):

```csharp
public record ProductoResponse(int Id, string Nombre, decimal Precio);

public record CrearProductoRequest(string Nombre, decimal Precio);

public class ProductoStore
{
    private readonly List<ProductoResponse> _productos =
        [new(1, "Teclado", 49.90m), new(2, "Ratón", 19.90m)];

    public IReadOnlyList<ProductoResponse> Listar() => _productos;

    public ProductoResponse Crear(CrearProductoRequest request)
    {
        var producto = new ProductoResponse(_productos.Count + 1, request.Nombre, request.Precio);
        _productos.Add(producto);
        return producto;
    }
}
```

Ningún tipo de este bloque conoce HTTP. Es la frontera que importa en la sección de Clean Architecture: cada modelo de programación es un traductor entre HTTP y estas dos operaciones.

## MVC: controlador + vista

**MVC** (Modelo-Vista-Controlador) reparte la petición en tres piezas: el **controlador** recibe la petición y decide qué hacer, el **modelo** son los datos y la **vista** es una plantilla Razor (`.cshtml`, HTML con C# incrustado) que produce el HTML. El controlador hereda de `Controller` (que, a diferencia de `ControllerBase`, sabe devolver vistas).

```csharp
[Route("mvc/productos")]
public class ProductosMvcController(ProductoStore store) : Controller
{
    [HttpGet("")]
    public IActionResult Index() => View(store.Listar());

    [HttpPost("")]
    public IActionResult Crear([FromForm] CrearProductoRequest request)
    {
        store.Crear(request);
        return RedirectToAction(nameof(Index));
    }
}
```

```razor
@* Views/ProductosMvc/Index.cshtml *@
@model IReadOnlyList<Tienda.Api.ProductoResponse>
<h1>Productos (MVC)</h1>
<ul>
@foreach (var p in Model)
{
    <li>@p.Nombre - @p.Precio</li>
}
</ul>
<form method="post">
    <input name="Nombre" /><input name="Precio" />
    <button>Crear</button>
</form>
```

`View(store.Listar())` busca la vista por convención: `Views/<nombre del controlador sin "Controller">/<nombre de la acción>.cshtml`. `GET /mvc/productos` devuelve HTML:

```text
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8

<h1>Productos (MVC)</h1>
<ul>
    <li>Teclado - 49,90</li>
    <li>Rat&#xF3;n - 19,90</li>
</ul>
<form method="post">
    <input name="Nombre" /><input name="Precio" />
    <button>Crear</button>
<input name="__RequestVerificationToken" type="hidden" value="CfDJ8JT6XEpy..." /></form>
```

Tres detalles de la salida real:

- El `<form method="post">` recibe solo un campo oculto `__RequestVerificationToken`: es el **token antifalsificación** (protección contra CSRF, peticiones POST lanzadas desde otra web con la sesión de la persona). Lo inyecta el *tag helper* de formularios. Un controlador MVC **no lo exige por sí solo**: un POST sin token (`curl -X POST /mvc/productos -d "Nombre=X&Precio=1"`) devolvió `302` y creó el producto. Para exigirlo hay que decorar la acción con `[ValidateAntiForgeryToken]` o aplicar `AutoValidateAntiforgeryToken` globalmente; Razor Pages, en cambio, lo valida automáticamente.
- `49,90` y no `49.90`: Razor formatea con la cultura del proceso (aquí `es-ES`). Una API JSON no lo hace; las vistas, sí.
- `Ratón` sale como `Rat&#xF3;n`: Razor codifica en HTML por defecto, lo que evita XSS sin hacer nada.

El POST, con el token y su cookie, crea el producto y redirige (patrón *Post/Redirect/Get*, que evita reenviar el formulario al recargar):

```text
HTTP/1.1 302 Found
Location: /mvc/productos
```

Tras el POST, el listado incluye `Monitor - 199,00`.

## Razor Pages: la página como unidad

**Razor Pages** elimina el reparto en tres piezas y agrupa por página: un `.cshtml` con el HTML y su clase **`PageModel`** (`.cshtml.cs`) con la lógica. La URL sale de la directiva `@page`, no de un atributo de ruta ni de un controlador. Por dentro usa la misma maquinaria que MVC (vistas Razor, *tag helpers*, *model binding*, filtros), solo cambia la forma de organizar.

```csharp
// Pages/Productos.cshtml.cs
public class ProductosModel(ProductoStore store) : PageModel
{
    public IReadOnlyList<ProductoResponse> Productos { get; private set; } = [];

    [BindProperty]
    public CrearProductoRequest Nuevo { get; set; } = new("", 0);

    public void OnGet() => Productos = store.Listar();

    public IActionResult OnPost()
    {
        store.Crear(Nuevo);
        return RedirectToPage();
    }
}
```

```razor
@* Pages/Productos.cshtml *@
@page "/paginas/productos"
@model Tienda.Api.Pages.ProductosModel
<h1>Productos (Razor Pages)</h1>
<ul>
@foreach (var p in Model.Productos)
{
    <li>@p.Nombre - @p.Precio</li>
}
</ul>
<form method="post">
    <input asp-for="Nuevo.Nombre" /><input asp-for="Nuevo.Precio" />
    <button>Crear</button>
</form>
```

Los métodos `OnGet` y `OnPost` son **manejadores** (*handlers*) por convención de nombre: `OnGet` atiende el GET, `OnPost` el POST. `[BindProperty]` pide que el formulario rellene la propiedad `Nuevo` (el [model binding](Model-Binding.md) funciona igual que en un controlador). La respuesta del GET tiene la misma forma que la de MVC:

```text
<h1>Productos (Razor Pages)</h1>
<ul>
    <li>Teclado - 49,90</li>
    <li>Rat&#xF3;n - 19,90</li>
</ul>
<form method="post">
    <input type="text" data-val="true" data-val-required="The Nombre field is required." id="Nuevo_Nombre" name="Nuevo.Nombre" value="" /><input type="text" data-val="true" data-val-number="The field Precio must be a number." data-val-required="The Precio field is required." id="Nuevo_Precio" name="Nuevo.Precio" value="0,00" />
    <button>Crear</button>
<input name="__RequestVerificationToken" type="hidden" value="CfDJ8JT6XEpy..." /></form>
```

Con `asp-for`, el *tag helper* genera `name="Nuevo.Nombre"`, el `id` y los atributos `data-val-*` con los que la validación en cliente sabe qué comprobar (la validación en sí está en [Validación con Data Annotations](Validacion-con-DataAnnotations.md)). El POST con token devuelve `302` a `/paginas/productos` y el producto aparece en el listado.

## Web API con controladores: el mismo patrón sin vistas

La **Web API con controladores** es el modelo de [`[ApiController]`](ApiController.md): el controlador hereda de `ControllerBase` (sin vistas), y lo que devuelve se serializa a JSON.

```csharp
[ApiController]
[Route("api/productos")]
public class ProductosApiController(ProductoStore store) : ControllerBase
{
    [HttpGet]
    public IEnumerable<ProductoResponse> Listar() => store.Listar();

    [HttpPost]
    public ActionResult<ProductoResponse> Crear(CrearProductoRequest request)
    {
        var creado = store.Crear(request);
        return Created($"/api/productos/{creado.Id}", creado);
    }
}
```

`GET /api/productos`:

```text
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

[{"id":1,"nombre":"Teclado","precio":49.90},{"id":2,"nombre":"Ratón","precio":19.90}]
```

`POST /api/productos` con `{"nombre":"Auriculares","precio":39.5}`:

```text
HTTP/1.1 201 Created
Content-Type: application/json; charset=utf-8
Location: /api/productos/5

{"id":5,"nombre":"Auriculares","precio":39.5}
```

Y sin `nombre`, `[ApiController]` corta la petición antes de llegar a la acción:

```text
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json; charset=utf-8

{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"Nombre":["The Nombre field is required."]},"traceId":"00-908cd92b6a96e4e9bd31a4e6d8affb3a-b5073bfb0421056e-00"}
```

Esta validación automática no es del modelo de programación sino del atributo `[ApiController]`; el detalle está en [ApiController](ApiController.md) y qué devolver en cada caso, en [Tipos de retorno de una acción](Tipos-de-Retorno-de-una-Accion.md). Las URL y verbos se explican en [Enrutado y verbos HTTP](Enrutado-y-Verbos.md).

## Minimal APIs: endpoints sin controladores

Las **Minimal APIs** declaran la ruta y su código directamente en `Program.cs`, sin clase de controlador. Los parámetros se resuelven por tipo: lo que está registrado en DI se inyecta, un tipo complejo se lee del cuerpo JSON.

```csharp
app.MapGet("/minimal/productos", (ProductoStore store) => store.Listar());

app.MapPost("/minimal/productos", (CrearProductoRequest request, ProductoStore store) =>
{
    var creado = store.Crear(request);
    return Results.Created($"/minimal/productos/{creado.Id}", creado);
});
```

La respuesta del GET es el mismo JSON que en la API con controladores, y el POST devuelve `201 Created` con `Location: /minimal/productos/6` y el cuerpo `{"id":6,"nombre":"Alfombrilla","precio":9.9}`. La diferencia llega al enviar un cuerpo sin `nombre`:

```text
HTTP/1.1 201 Created
Content-Type: application/json; charset=utf-8
Location: /minimal/productos/7

{"id":7,"nombre":null,"precio":9.9}
```

Una Minimal API **no valida de forma automática**: no hay equivalente de `[ApiController]` y el producto se crea con `nombre` nulo. En .NET 10 la validación se activa registrando `AddValidation()` y marcando el tipo con atributos de DataAnnotations. Comprobado con un proyecto aparte:

```csharp
builder.Services.AddValidation();
// ...
public record CrearProductoRequest([property: Required] string Nombre, decimal Precio);
```

```text
HTTP/1.1 400 Bad Request
Content-Type: application/json; charset=utf-8

{"title":"One or more validation errors occurred.","errors":{"Nombre":["The Nombre field is required."]}}
```

Las Minimal APIs soportan grupos de rutas (`MapGroup`), filtros de endpoint e inyección de dependencias; no son un modo reducido ni «solo para prototipos».

## Blazor: la interfaz como componentes en C#

**Blazor** construye la interfaz con **componentes** (ficheros `.razor`: HTML + C#, con estado y eventos), a la manera de React o Angular pero en C#. La plantilla vigente en .NET 10 es la **Blazor Web App** (`dotnet new blazor`); `blazorwasm` crea una aplicación WebAssembly independiente. La plantilla antigua `blazorserver` ya no existe en el SDK 10.0.401 (`dotnet new list blazor` solo lista `blazor` y `blazorwasm`).

La terminología vigente separa el modelo de alojamiento del **modo de renderizado**, que se decide por componente o por página:

| Modo de renderizado | Directiva | Dónde se ejecuta el C# | Interactividad |
|---|---|---|---|
| Servidor estático (*static SSR*) | ninguna (es el modo por defecto) | Servidor, una vez por petición | No: formularios y enlaces normales |
| Servidor interactivo | `@rendermode InteractiveServer` | Servidor, con una conexión SignalR abierta | Sí, cada evento viaja al servidor |
| WebAssembly interactivo | `@rendermode InteractiveWebAssembly` | Navegador (WebAssembly) | Sí, sin ir al servidor |
| Automático | `@rendermode InteractiveAuto` | Servidor primero; WebAssembly cuando termina de descargarse | Sí |

Los tres modos interactivos **prerenderizan** en el servidor: el HTML inicial ya contiene el contenido (esto es lo que ven los buscadores y lo que muestra `curl`), y luego la interactividad se «engancha».

La plantilla se creó con `dotnet new blazor -n Tienda.Web -int Auto --empty` (`-int` elige los modos interactivos habilitados; `--empty` omite las páginas de ejemplo). Genera dos proyectos, `Tienda.Web` (servidor) y `Tienda.Web.Client` (los componentes que se pueden ejecutar en el navegador). El caso de la tienda, en renderizado estático:

```razor
@* Tienda.Web/Components/Pages/Productos.razor *@
@page "/blazor/productos"

<h1>Productos (Blazor, renderizado estático)</h1>
<ul>
    @foreach (var p in Almacen.Productos)
    {
        <li>@p.Nombre - @p.Precio</li>
    }
</ul>

<EditForm Model="Nuevo" FormName="crear-producto" OnValidSubmit="Crear">
    <InputText @bind-Value="Nuevo.Nombre" />
    <InputNumber @bind-Value="Nuevo.Precio" />
    <button>Crear</button>
</EditForm>

@code {
    [SupplyParameterFromForm]
    private NuevoProducto Nuevo { get; set; } = new();

    private void Crear() => Almacen.Productos.Add((Nuevo.Nombre ?? "", Nuevo.Precio));

    public class NuevoProducto
    {
        public string? Nombre { get; set; }
        public decimal Precio { get; set; }
    }

    public static class Almacen   // sustituye a ProductoStore en esta app de prueba
    {
        public static List<(string Nombre, decimal Precio)> Productos { get; } =
            [("Teclado", 49.90m), ("Ratón", 19.90m)];
    }
}
```

`curl http://localhost:6772/blazor/productos` devuelve HTML (abreviado: se omiten la cabecera `<head>` y los `<script>` finales):

```text
<h1>Productos (Blazor, renderizado estático)</h1>
<ul><li>Teclado - 49,90</li><li>Rat&#xF3;n - 19,90</li></ul>

<form method="post" action="/blazor/productos"><input type="hidden" name="_handler" value="crear-producto" /><input type="hidden" name="__RequestVerificationToken" value="CfDJ8JT6XEpy..." /><input name="Nuevo.Nombre" class="valid" />
    <input step="any" type="number" name="Nuevo.Precio" class="valid" value="0" />
    <button>Crear</button></form>
```

Es un formulario HTML normal: el POST con `_handler=crear-producto` (el `FormName`) y el token devuelve `200 OK` con la página ya actualizada, que incluye `Webcam - 59,9`. Sin interactividad, Blazor se comporta como Razor Pages con otra sintaxis.

Un componente interactivo se marca con el modo. Con `@rendermode InteractiveAuto` en `Tienda.Web.Client/Contador.razor`:

```razor
@page "/contador"
@rendermode InteractiveAuto

<p>Pulsaciones: @cuenta</p>
<button @onclick="() => cuenta++">Sumar</button>

@code {
    private int cuenta;
}
```

El HTML prerenderizado que sirve `curl` ya contiene `<p>Pulsaciones: 0</p>` y el botón, precedidos y seguidos de comentarios `<!--Blazor:{"type":"auto","prerenderId":"..."}-->` con los metadatos que usa el script `blazor.web.js` para activar el componente en el navegador. **No se ejecutó** la parte interactiva (clics, conexión SignalR, descarga del WebAssembly): `curl` no ejecuta JavaScript. Solo se comprobó que compila y que el prerenderizado sale con ese HTML.

## Mezclar modelos en una sola aplicación

Los modelos no son excluyentes: son piezas que se registran en el mismo `Program.cs`. La aplicación de las secciones anteriores contiene a la vez un controlador MVC con vistas, una Razor Page, una API con controladores y una Minimal API:

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSingleton<ProductoStore>();
builder.Services.AddControllersWithViews();   // MVC + Web API con controladores
builder.Services.AddRazorPages();             // Razor Pages

var app = builder.Build();

app.UseAntiforgery();

app.MapControllers();   // los controladores MVC y de API
app.MapRazorPages();

app.MapGet("/minimal/productos", (ProductoStore store) => store.Listar());
app.MapPost("/minimal/productos", (CrearProductoRequest request, ProductoStore store) =>
{
    var creado = store.Crear(request);
    return Results.Created($"/minimal/productos/{creado.Id}", creado);
});

app.Run();
```

Con esa sola aplicación en marcha, las cuatro URL responden y comparten el mismo `ProductoStore`: el producto creado por `POST /api/productos` aparece en `GET /minimal/productos` (el listado final incluyó los productos creados por los cuatro caminos, con ids del 1 al 7).

| URL | Modelo | Devuelve |
|---|---|---|
| `/mvc/productos` | MVC | HTML |
| `/paginas/productos` | Razor Pages | HTML |
| `/api/productos` | Web API con controladores | JSON |
| `/minimal/productos` | Minimal API | JSON |

Dos notas del registro de servicios: `AddControllersWithViews()` cubre MVC y la API con controladores a la vez (`AddControllers()` sirve solo para API: no registra vistas), y Razor Pages añade su propio `AddRazorPages()`. Blazor se registra con `AddRazorComponents()` y `MapRazorComponents<App>()`, y también puede convivir con el resto en la misma aplicación: la plantilla `blazor` ya lo hace con el servidor que aloja los componentes.

## Cómo elegir

| Necesidad | Modelo que encaja | Por qué |
|---|---|---|
| API pura (JSON para móvil, SPA u otros servicios) | Web API con controladores o Minimal APIs | Sin vistas ni estado de sesión de UI; validación y convenciones HTTP |
| Web con SEO (catálogo, blog, contenido público) | Razor Pages o MVC | HTML completo en la primera respuesta |
| Muchos formularios y pantallas CRUD | Razor Pages | Una página por caso de uso, lógica junto al HTML |
| Aplicación interactiva (edición en vivo, paneles, tablero) | Blazor | Estado y eventos en C#, sin escribir JavaScript |
| Equipo con experiencia en C#, sin frontend dedicado | Razor Pages o Blazor | Todo el código en un solo lenguaje |
| Equipo con frontend separado (React, Angular, Vue) | API (controladores o Minimal) | El HTML lo produce el otro equipo |
| API grande, con filtros, versionado y muchas convenciones | Controladores | Filtros, convenciones y atributos maduros |
| Microservicio pequeño con pocos endpoints | Minimal APIs | Menos ceremonia |

Estas recomendaciones son criterios, no reglas: las dos filas de API conviven, y no hay una frontera técnica entre «grande» y «pequeño».

## Cuándo NO usar cada modelo

- **MVC**: no para una API que solo devuelve JSON (acabarías con vistas, `ViewData` y la jerarquía `Controller` sin usarlas; `ControllerBase` es suficiente). Tampoco como primera elección en una web nueva de formularios: Razor Pages ordena mejor el trabajo por página.
- **Razor Pages**: no para una API consumida por otras aplicaciones ni para una interfaz con mucha interactividad en vivo (cada acción recarga la página o requiere JavaScript propio). Ni para aplicaciones con flujos de navegación muy complejos entre muchas vistas que comparten lógica, donde MVC separa mejor.
- **Web API con controladores**: no para un endpoint suelto o dos; la clase, los atributos y el registro de controladores son más ceremonia de la necesaria.
- **Minimal APIs**: no se validan solas (la salida de la sección anterior lo muestra) y, sin disciplina, `Program.cs` acaba siendo un fichero de cientos de líneas; agrupa con `MapGroup` y mueve los endpoints a métodos o clases estáticas cuando crezcan.
- **Blazor**: no para un sitio de contenido donde el SEO y el tiempo de primera carga mandan y casi no hay interactividad: el renderizado estático lo cubre sin coste, pero entonces Razor Pages es más simple. En modo `InteractiveServer`, cada cliente mantiene una conexión SignalR y estado en la memoria del servidor; en `InteractiveWebAssembly`, hay que descargar el runtime y la aplicación antes de ser interactiva, y el código de componentes cliente es visible para quien lo descargue (nada de secretos ahí).

## Como capa de presentación en Clean Architecture

Estos modelos deciden **cómo entra una petición HTTP**; [Clean Architecture](../../arquitectura-de-software/clean-architecture/Clean-Architecture.md) decide **cómo se organizan las capas** (dominio, casos de uso, infraestructura). No compiten: ASP.NET Core ocupa el borde, el proyecto `Tienda.Api`, y es un **adaptador de entrada** (el vocabulario está en [Puertos y Adaptadores](../../arquitectura-de-software/clean-architecture/Puertos-y-Adaptadores.md)): traduce HTTP a una llamada a un caso de uso y la respuesta del caso de uso a HTTP, sin contener reglas de negocio.

Las secciones anteriores lo muestran en pequeño: los cuatro modelos de servidor (MVC, Razor Pages, API con controladores y Minimal API) llaman al mismo `ProductoStore` y ninguno de sus métodos conoce HTTP, cabeceras ni `IActionResult`. Cambiar de un modelo a otro (o añadir uno) no toca la capa interna. En una solución real, el papel de `ProductoStore` lo ocupa un caso de uso de `Tienda.Aplicacion`, que `Tienda.Api` referencia como describe la [Regla de Dependencia](../../arquitectura-de-software/clean-architecture/Regla-de-Dependencia.md).

Consecuencias prácticas para la capa de presentación:

- Los DTO de entrada y salida (`CrearPedidoRequest`, `PedidoResponse`) pertenecen a `Tienda.Api`; las entidades del dominio no se exponen por HTTP.
- Las anotaciones de validación de formato (`[Required]`, `[Range]`) van en los DTO de la capa de presentación; las reglas de negocio, en el dominio o en los casos de uso. Ver [Validación con Data Annotations](Validacion-con-DataAnnotations.md).
- La autenticación y la autorización pertenecen a la presentación como mecanismo ([Authorize](Authorize.md)); los conceptos están en [Autenticación y autorización](../../seguridad/autenticacion-y-autorizacion/).

## Errores frecuentes

**`500` y en el log `The view 'Index' was not found`.** La causa es el nombre de la carpeta de vistas: la convención usa el nombre del controlador sin el sufijo `Controller`. Con `ProductosMvcController`, la vista debía estar en `Views/ProductosMvc/Index.cshtml`, no en `Views/Productos/`. El mensaje real, con las rutas que probó el motor:

```text
System.InvalidOperationException: The view 'Index' was not found. The following locations were searched:
/Views/ProductosMvc/Index.cshtml
/Views/Shared/Index.cshtml
/Pages/Shared/Index.cshtml
```

La respuesta HTTP no trae cuerpo (`Content-Length: 0`): hay que mirar el log.

**Un POST a una Razor Page responde `400 Bad Request` con cuerpo vacío.** Falta el token antifalsificación, que Razor Pages valida automáticamente. Comprobado: `curl -X POST /paginas/productos -d "Nuevo.Nombre=X&Nuevo.Precio=1"` sin token ni cookie devuelve `400` y `Content-Length: 0`. Un `<form method="post">` dentro de una vista Razor lo incluye solo gracias al *tag helper* de formularios (lo activa `@addTagHelper *, Microsoft.AspNetCore.Mvc.TagHelpers` en `_ViewImports.cshtml`).

**Un controlador con `View()` que no compila o falla por falta de servicios.** `AddControllers()` registra solo lo necesario para API; las vistas requieren `AddControllersWithViews()` (con `AddControllers()` y `View()` la petición da 500: `No service for type '...ITempDataDictionaryFactory' has been registered`, comprobado el 2026-11-10 en un proyecto aparte; ver [[ApiController]](ApiController.md)).

**Una Minimal API acepta datos inválidos sin quejarse.** Sin `AddValidation()` no hay validación automática; la sección de Minimal APIs muestra el `201` con `"nombre":null`.

**Un componente interactivo de Blazor en el proyecto equivocado.** Con `InteractiveWebAssembly` o `InteractiveAuto`, el componente debe estar en el proyecto `.Client`, porque es el que se compila a WebAssembly. Un componente en el proyecto servidor con esos modos no podría ejecutarse en el navegador.

## Buenas prácticas avanzadas

- **Elige por la forma de la salida y por quién la consume, no por costumbre.** Un tutorial que empieza por MVC no implica que MVC sea el modelo de una API; empezar por ahí para devolver solo JSON deja vistas y jerarquías sin usar.
- **Mantén la acción o el endpoint finos.** Recibir, delegar en un caso de uso y traducir el resultado. Si hay consultas o reglas de negocio dentro de un controlador, un manejador de Razor Page o una lambda de `MapPost`, la lógica se ha filtrado a la presentación y no se puede reutilizar desde otro modelo.
- **Mezcla modelos cuando cada uno aporta algo, y comparten la capa interna.** Un panel de administración en Razor Pages y una API pública en Minimal APIs pueden vivir en el mismo `Tienda.Api` y llamar a los mismos casos de uso; lo que no conviene es duplicar la lógica en cada uno.
- **En Minimal APIs, activa la validación y agrupa pronto.** `AddValidation()` y `MapGroup("/api/productos")` con filtros comunes evitan el `Program.cs` de cientos de líneas y los endpoints sin validar.
- **Decide el modo de renderizado de Blazor por componente, no por aplicación.** Lo estático (listados, páginas de contenido) se queda en SSR y solo lo interactivo paga el coste de una conexión SignalR o de la descarga de WebAssembly; `--all-interactive` en la plantilla activa interactividad global y es la opción que menos conviene si la mayoría de las páginas no la necesitan.
- **No uses el modo de renderizado como frontera de seguridad.** Todo componente que se ejecute en WebAssembly es código descargable; las reglas de autorización y los secretos viven en el servidor, detrás de una API o de un componente de servidor.

## Documentación oficial

- [Choose an ASP.NET Core web UI](https://learn.microsoft.com/aspnet/core/tutorials/choose-web-ui) — la comparativa oficial de los modelos de interfaz, con criterios de elección.
- [Apps de API de ASP.NET Core](https://learn.microsoft.com/aspnet/core/fundamentals/apis) — compara Minimal APIs y controladores y enlaza a ambos tutoriales.
- [Modos de renderizado de ASP.NET Core Blazor](https://learn.microsoft.com/aspnet/core/blazor/components/render-modes) — la terminología vigente de los modos (estático, servidor, WebAssembly, automático) y cuándo usar cada uno.
- [Introducción a Razor Pages](https://learn.microsoft.com/aspnet/core/razor-pages/) — manejadores, `PageModel` y enrutado de páginas.

## Recursos didácticos

Generar un proyecto de cada tipo y comparar sus `Program.cs` es la forma más rápida de verlos lado a lado: `dotnet new mvc`, `dotnet new razor`, `dotnet new webapi` y `dotnet new blazor`. `dotnet new list` muestra las plantillas disponibles en la versión instalada del SDK.

---

*En resumen: ASP.NET Core ofrece cinco modelos (MVC, Razor Pages, Web API con controladores, Minimal APIs y Blazor) sobre el mismo motor; se elige por la forma de la salida (HTML, JSON o interfaz con estado), se pueden mezclar en una sola aplicación, y todos son solo la capa de presentación que traduce HTTP a casos de uso.*
