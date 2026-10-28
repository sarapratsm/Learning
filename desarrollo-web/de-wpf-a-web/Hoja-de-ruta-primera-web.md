# Hoja de ruta: tu primera web con C#

## ¿Qué es?

Es un recorrido por **ocho hitos**, de una carpeta vacía a una web publicada, pensado para quien ya programa en C# con WPF. Cada hito tiene un entregable pequeño, los conceptos que necesitas para lograrlo, la ficha de esta colección que conviene leer antes y un criterio para saber que está hecho.

Asume **.NET 10** (la versión LTS vigente en octubre de 2026, con soporte hasta el 14 de noviembre de 2028 según la política de soporte de Microsoft). Si instalas .NET 8 o .NET 9, los comandos son los mismos, pero su soporte termina el 10 de noviembre de 2026.

## ¿Por qué existe?

Las fichas de esta colección explican conceptos sueltos: HTTP, Razor, inyección de dependencias, middleware. Quien llega de WPF suele perderse en otra cosa: **no sabe en qué orden aplicarlos** ni qué es "suficiente" para una primera web. La hoja de ruta hace de pegamento: te dice qué construir primero, qué leer justo antes y cuándo parar.

> Si vienes de WPF, piensa en esto como el equivalente a empezar con una ventana con una lista, añadir un formulario, conectar una base de datos y, al final, generar el instalador. Cambia el orden de las piezas, no la lógica de ir de menos a más.

## Qué enfoque elegir para la primera web

C# ofrece varias formas de hacer web. Para una primera web, elige solo una:

| Enfoque | Qué es | Curva desde WPF | Elígelo si... | Ficha |
|---|---|---|---|---|
| **Razor Pages** | El servidor genera cada página en HTML | Baja: una página `.cshtml` se parece a un XAML con code-behind | Quieres la primera web más sencilla, con formularios y listas | [Razor Pages y MVC](Razor-Pages-y-MVC.md) |
| **MVC** | Lo mismo, repartido en controlador, modelo y vista | Media | Ya conoces MVC o prevés una app grande | [Razor Pages y MVC](Razor-Pages-y-MVC.md) |
| **Blazor** | Interfaz interactiva escrita en C#, con componentes y binding | Baja en la forma de pensar, más conceptos nuevos (modos de render) | Necesitas mucha interactividad y no quieres escribir JavaScript | [Blazor](Blazor.md) |
| **API + frontend aparte** | Un backend que devuelve JSON y una interfaz en JavaScript | Alta: dos proyectos y dos tecnologías | Ya tienes un frontend, o necesitas una API para móvil | [Web API y REST](Web-API-y-REST.md) |

**Recomendación para empezar desde WPF: Razor Pages.** Es el camino con menos piezas nuevas: sigues en C#, la página y su lógica viven juntas y no necesitas JavaScript para tener una web útil. Esta hoja de ruta lo usa. Los demás enfoques están al final, en «Y después».

## El proyecto de ejemplo: un catálogo de productos

Construirás, hito a hito, un **catálogo de productos**: una lista, una ficha de detalle, un formulario para añadir productos y, al final, la web publicada. Es lo bastante pequeño para acabarlo y lo bastante completo para tocar todas las piezas.

## Los ocho hitos

### Hito 1: una web que arranca

**Qué construyes.** El proyecto vacío generado por la plantilla, funcionando en tu máquina.

**Antes de empezar, lee** [Modelo cliente-servidor](Modelo-Cliente-Servidor.md), [HTTP](HTTP.md) y [ASP.NET Core](ASP-NET-Core.md).

**Qué tienes que haber entendido.** Que tu programa es ahora un servidor que escucha peticiones, no una ventana (en WPF era el `App` y su bucle de mensajes). Que `Program.cs` es el punto de arranque (ver [Hosts y builders](Hosts-y-Builders.md)).

```bash
dotnet --version                 # debe empezar por 10.
dotnet new webapp -n Catalogo    # plantilla de Razor Pages
cd Catalogo
dotnet watch                     # arranca y recarga al guardar
```

`dotnet watch` arranca la web y la reinicia al guardar un cambio: es el equivalente a editar y ver el resultado sin volver a lanzar la aplicación a mano.

**Hecho cuando** el navegador abre la dirección que imprime la consola (algo como `https://localhost:7xxx`) y muestra la página de inicio de la plantilla.

### Hito 2: una página con una lista

**Qué construyes.** Una página `/Productos` que muestra una lista fija de productos.

**Antes, lee** [HTML y CSS](HTML-y-CSS.md) y [Razor Pages y MVC](Razor-Pages-y-MVC.md).

**Qué tienes que haber entendido.** Que el navegador recibe HTML, no objetos C#. Que el `.cshtml` es la vista (tu XAML) y el `.cshtml.cs` su code-behind. Que `OnGet` se ejecuta al abrir la página, como un `Loaded`.

Crea `Pages/Productos/Index.cshtml.cs`:

```csharp
namespace Catalogo.Pages.Productos;

public record Producto(int Id, string Nombre, decimal Precio);

public class IndexModel : PageModel
{
    public List<Producto> Productos { get; } =
    [
        new(1, "Teclado mecánico", 79.90m),
        new(2, "Ratón inalámbrico", 24.50m),
    ];
}
```

Y `Pages/Productos/Index.cshtml`:

```cshtml
@page
@model Catalogo.Pages.Productos.IndexModel

<h1>Productos</h1>
<ul>
@foreach (var producto in Model.Productos)
{
    <li>@producto.Nombre — @producto.Precio €</li>
}
</ul>
```

Los fragmentos de esta hoja de ruta omiten los `using` para ir al grano: el editor te sugiere los que falten (`Microsoft.AspNetCore.Mvc.RazorPages` para `PageModel`, `Microsoft.AspNetCore.Mvc` para `IActionResult`, `System.ComponentModel.DataAnnotations` para `[Required]`, `Microsoft.AspNetCore.Authorization` para `[Authorize]` y `Microsoft.EntityFrameworkCore` para EF Core).

**Hecho cuando** `/Productos` muestra los dos productos y un cambio en el nombre de uno se ve al recargar.

### Hito 3: un servicio inyectado

**Qué construyes.** Un repositorio en memoria que entrega los productos, en lugar de tenerlos escritos en la página.

**Antes, lee** [Inyección de dependencias](Inyeccion-de-Dependencias.md).

**Qué tienes que haber entendido.** Que la página no crea sus dependencias: las pide en el constructor y ASP.NET Core se las da. Que el tiempo de vida importa: un servicio `Singleton` lo comparten todas las peticiones, así que debe tolerar acceso simultáneo (en WPF solo había una persona delante de la pantalla).

Mueve `Producto` a su propio fichero (`Producto.cs`) y añade:

```csharp
public interface IProductoRepository
{
    IReadOnlyList<Producto> ObtenerTodos();
    void Crear(string nombre, decimal precio);
}

public class ProductoRepositorioMemoria : IProductoRepository
{
    private readonly List<Producto> _productos = [new(1, "Teclado mecánico", 79.90m)];
    private readonly object _bloqueo = new();

    public IReadOnlyList<Producto> ObtenerTodos()
    {
        lock (_bloqueo) return _productos.ToList();
    }

    public void Crear(string nombre, decimal precio)
    {
        lock (_bloqueo) _productos.Add(new Producto(_productos.Count + 1, nombre, precio));
    }
}
```

Regístralo en `Program.cs`, antes de `builder.Build()`, y pídelo en la página:

```csharp
builder.Services.AddSingleton<IProductoRepository, ProductoRepositorioMemoria>();
```

```csharp
public class IndexModel(IProductoRepository repositorio) : PageModel
{
    public IReadOnlyList<Producto> Productos { get; private set; } = [];

    public void OnGet() => Productos = repositorio.ObtenerTodos();
}
```

**Hecho cuando** la lista sigue viéndose igual pero los datos ya no están escritos en la página.

### Hito 4: un formulario con validación

**Qué construyes.** Una página `/Productos/Crear` para añadir un producto, con mensajes si los datos no son válidos.

**Antes, lee** la sección de formularios de [Razor Pages y MVC](Razor-Pages-y-MVC.md) y, si quieres reglas más ricas que los atributos, [FluentValidation](FluentValidation.md).

**Qué tienes que haber entendido.** Que un formulario es un `POST`, no un evento `Click`. Que se valida **siempre en el servidor** (ver [Modelo cliente-servidor](Modelo-Cliente-Servidor.md)). Que tras un `POST` correcto se redirige (patrón *Post-Redirect-Get*) para que recargar la página no reenvíe el formulario.

`Pages/Productos/Crear.cshtml.cs`:

```csharp
public class CrearModel(IProductoRepository repositorio) : PageModel
{
    [BindProperty]
    public NuevoProducto Nuevo { get; set; } = new();

    public IActionResult OnPost()
    {
        if (!ModelState.IsValid) return Page();
        repositorio.Crear(Nuevo.Nombre, Nuevo.Precio);
        return RedirectToPage("Index");
    }

    public class NuevoProducto
    {
        [Required, StringLength(80)]
        public string Nombre { get; set; } = "";

        [Range(0.01, 100000)]
        public decimal Precio { get; set; }
    }
}
```

`Pages/Productos/Crear.cshtml`:

```cshtml
@page
@model Catalogo.Pages.Productos.CrearModel

<form method="post">
    <label asp-for="Nuevo.Nombre"></label>
    <input asp-for="Nuevo.Nombre" />
    <span asp-validation-for="Nuevo.Nombre"></span>

    <label asp-for="Nuevo.Precio"></label>
    <input asp-for="Nuevo.Precio" />
    <span asp-validation-for="Nuevo.Precio"></span>

    <button type="submit">Guardar</button>
</form>
```

**Hecho cuando** enviar el formulario vacío muestra los errores, enviarlo bien te lleva a la lista con el producto nuevo y al pulsar F5 en la lista no se crea nada duplicado.

### Hito 5: una base de datos de verdad

**Qué construyes.** Que los productos sobrevivan a reiniciar la aplicación, guardándolos en una base de datos SQLite.

**Antes, lee** [Entity Framework Core](../../bases-de-datos/acceso-a-datos-dotnet/Entity-Framework-Core.md).

**Qué tienes que haber entendido.** Que en WPF bastaba con tener los datos en memoria; en web un servidor se reinicia y se replica, así que lo que importa debe vivir en una base de datos. Que el contexto de EF Core es un servicio de vida *scoped* (uno por petición), no *singleton*.

```bash
dotnet add package Microsoft.EntityFrameworkCore.Sqlite
dotnet add package Microsoft.EntityFrameworkCore.Design
dotnet tool install --global dotnet-ef
```

`Producto` pasa de `record` a clase con propiedades `Id`, `Nombre` y `Precio`. Después, el contexto y el repositorio:

```csharp
public class CatalogoDb(DbContextOptions<CatalogoDb> opciones) : DbContext(opciones)
{
    public DbSet<Producto> Productos => Set<Producto>();
}

public class ProductoRepositorioEf(CatalogoDb db) : IProductoRepository
{
    public IReadOnlyList<Producto> ObtenerTodos() => db.Productos.ToList();

    public void Crear(string nombre, decimal precio)
    {
        db.Productos.Add(new Producto { Nombre = nombre, Precio = precio });
        db.SaveChanges();
    }
}
```

En `Program.cs` sustituye el registro del hito 3 (ya no es `Singleton`):

```csharp
builder.Services.AddDbContext<CatalogoDb>(o => o.UseSqlite("Data Source=catalogo.db"));
builder.Services.AddScoped<IProductoRepository, ProductoRepositorioEf>();
```

```bash
dotnet ef migrations add Inicial
dotnet ef database update
```

**Hecho cuando** creas un producto, paras la aplicación con Ctrl+C, la vuelves a arrancar y el producto sigue en la lista.

### Hito 6: rutas y errores

**Qué construyes.** Una página de detalle `/Productos/Detalle/3` y una respuesta correcta cuando el producto no existe.

**Antes, lee** [Routing y Middleware](Routing-y-Middleware.md).

**Qué tienes que haber entendido.** Que la URL es la forma de pedir cada pantalla (en WPF navegabas con un `Frame` o abrías una ventana). Que toda petición atraviesa una cadena de pasos (middleware) y que la plantilla ya trae la gestión de errores en producción.

Crea `Pages/Productos/Detalle.cshtml` con una ruta que recibe el identificador:

```cshtml
@page "{id:int}"
@model Catalogo.Pages.Productos.DetalleModel

<h1>@Model.Producto!.Nombre</h1>
<p>@Model.Producto.Precio €</p>
```

y en `Detalle.cshtml.cs`, el modelo que lo busca (añade `ObtenerPorId(int id)` al repositorio, que devuelve `Producto?`):

```csharp
public class DetalleModel(IProductoRepository repositorio) : PageModel
{
    public Producto? Producto { get; private set; }

    public IActionResult OnGet(int id)
    {
        Producto = repositorio.ObtenerPorId(id);
        if (Producto is null) return NotFound();
        return Page();
    }
}
```

**Hecho cuando** `/Productos/Detalle/1` muestra el producto y `/Productos/Detalle/999` devuelve un 404 en lugar de una excepción.

### Hito 7 (opcional): quién puede añadir productos

**Qué construyes.** Que solo las personas con cuenta puedan abrir `/Productos/Crear`.

**Antes, lee** [Autenticación y estado web](Autenticacion-y-Estado-Web.md).

**Qué tienes que haber entendido.** Que HTTP no tiene memoria: el servidor reconoce a cada persona en cada petición con una cookie. La forma más corta es crear el proyecto del hito 1 con la plantilla que ya trae cuentas de usuario (`dotnet new webapp -n Catalogo -au Individual`, con SQLite por defecto) y proteger la página:

```csharp
[Authorize]
public class CrearModel(IProductoRepository repositorio) : PageModel
```

**Hecho cuando** abrir `/Productos/Crear` sin iniciar sesión te lleva a la página de acceso, y tras iniciar sesión te deja entrar.

### Hito 8: publicarla

**Qué construyes.** La web funcionando fuera de tu máquina.

**Antes, lee** [ASP.NET Core](ASP-NET-Core.md) (apartado de arranque) y la guía de [primeros pasos con ASP.NET Core](../asp-net-core/README.md), que incluye el despliegue.

**Qué tienes que haber entendido.** Que publicar es generar una carpeta con todo lo necesario y copiarla a un servidor. Por defecto el despliegue es **dependiente del framework**: el servidor necesita tener instalado el runtime de ASP.NET Core de la versión que usas.

```bash
dotnet publish -c Release -o ./publicar
dotnet publicar/Catalogo.dll        # pruébala localmente antes de subirla
```

| Opción de alojamiento | Cuándo encaja |
|---|---|
| Servicio gestionado (por ejemplo, Azure App Service) | Quieres olvidarte del servidor |
| Servidor propio: Windows con IIS o servicio de Windows, Linux con Nginx como proxy inverso | Ya tienes servidor o quieres controlarlo |
| Contenedor Docker | Quieres el mismo paquete en tu máquina y en producción |

Tres cosas que revisar antes de abrirla al mundo: que la configuración sale del entorno (no del código), que las contraseñas y claves **no** están en el repositorio y que el fichero de la base de datos SQLite vive en una ruta que no se borra al desplegar.

**Hecho cuando** una persona ajena a tu máquina abre la dirección pública, ve el catálogo y, tras crear un producto y reiniciar la aplicación del servidor, el producto sigue ahí.

## Errores frecuentes del primer proyecto

| Síntoma | Causa habitual | Qué hacer |
|---|---|---|
| El formulario devuelve `400` sin explicación | Falta el token anti-falsificación, por ejemplo al enviar a mano con JavaScript | Envía el token; no desactives la comprobación |
| Al validar mal, la página sale rota o vacía | `OnPost` no vuelve a ejecutar `OnGet`, y los datos auxiliares no se cargan | Extrae esa carga a un método y llámalo en ambos |
| Los datos desaparecen al reiniciar | Siguen en memoria (hitos 2 a 4) | Pasa al hito 5 |
| `Cannot consume scoped service ... from singleton ...` | Un servicio `Singleton` depende del contexto de EF Core, que es *scoped* | Registra el repositorio como `Scoped` |
| Funciona en tu máquina y no en el servidor | El runtime de .NET de esa versión no está instalado | Instálalo, o publica de forma autocontenida |
| El producto nuevo aparece duplicado al recargar | El `POST` devuelve la página en lugar de redirigir | Usa *Post-Redirect-Get* (hito 4) |

## Y después

Cuando la primera web esté publicada, elige **una** línea para seguir, según lo que te haga falta:

- **Interactividad sin recargar la página**: [JavaScript y el navegador](JavaScript-y-el-Navegador.md), o [Blazor](Blazor.md) si prefieres seguir en C#.
- **Una API para una app móvil o un frontend aparte**: [Web API y REST](Web-API-y-REST.md) y [Comunicación entre frontend y backend](Comunicacion-Frontend-Backend.md).
- **Datos en tiempo real**: [SignalR](SignalR.md).
- **Organizar mejor el código del servidor**: [Clean Architecture](../../arquitectura-de-software/clean-architecture/README.md).
- **Una web accesible y para varios idiomas**: [Accesibilidad web](../accesibilidad-web/README.md) y [Webs multiidioma](../webs-multiidioma/README.md).

## Buenas prácticas avanzadas

- **No saltes el hito 5 "para ir más rápido"** — mantener los datos en memoria parece cómodo, pero es el error de diseño más caro de una primera web: un singleton con una lista funciona con una sola persona y se corrompe con dos peticiones simultáneas, y lo que guardas desaparece al reiniciar. Pasa a una base de datos en cuanto algo deba sobrevivir.
- **Valida en la página y vuelve a comprobar en el repositorio lo que importe** — los atributos del hito 4 protegen el formulario, pero cualquier persona puede construir una petición a mano. Lo que no puede romperse (un precio negativo, un nombre vacío) debe rechazarse también en la lógica que guarda.
- **Usa modelos de vista para los formularios, no tus entidades** — `NuevoProducto` solo tiene los campos que el formulario debe poder tocar. Si enlazaras la entidad completa, quien manipule la petición podría rellenar campos que no ofreces (por ejemplo un `Id` o una marca de administrador).
- **Ejecuta `dotnet publish` y arranca el resultado antes de subirlo** — el modo de desarrollo perdona cosas que producción no: ficheros que no se copian, configuración que solo existe en tu máquina o variables de entorno distintas. Comprobar la carpeta publicada en local detecta la mayoría de esos fallos en un minuto.
- **Versiona con Git desde el hito 1 y confirma al acabar cada hito** — cada hito es un punto de retorno. Si el hito 5 sale mal, vuelves al 4 sin perder nada, y el historial te cuenta cómo evolucionó el proyecto.

## Documentación oficial

- [Tutorial de Razor Pages en ASP.NET Core](https://learn.microsoft.com/aspnet/core/tutorials/razor-pages/razor-pages-start) — un tutorial paso a paso muy cercano al proyecto de esta hoja de ruta; útil si quieres contrastar cada hito.
- [Plantillas de `dotnet new`](https://learn.microsoft.com/dotnet/core/tools/dotnet-new-sdk-templates) — la lista de plantillas y sus opciones (`webapp`, `mvc`, `blazor`, `webapi`) para cuando quieras otro enfoque.
- [Hospedar y desplegar ASP.NET Core](https://learn.microsoft.com/aspnet/core/host-and-deploy/) — publicar, gestor de procesos, proxy inverso, Docker y Azure; el hito 8 en detalle.
- [Política de soporte de .NET](https://dotnet.microsoft.com/platform/support/policy/dotnet-core) — qué versiones están soportadas y hasta cuándo, para elegir la que instalar.

## Recursos didácticos

- [Crear páginas Razor en ASP.NET Core (Microsoft Learn)](https://learn.microsoft.com/training/modules/create-razor-pages-aspnet-core/) — un módulo guiado con ejercicios, para reforzar los hitos 1 a 4 con otro ejemplo.
- [Aprende ASP.NET (dotnet.microsoft.com)](https://dotnet.microsoft.com/learn/aspnet) — el punto de entrada oficial con tutoriales cortos, como un «hola mundo» web en pocos minutos.

---

*En resumen: tu primera web con C# es un catálogo que creces en ocho hitos —arrancar, listar, inyectar, validar, persistir, enrutar, proteger y publicar—, y la mejor decisión del principio es elegir un solo enfoque (Razor Pages) y acabarlo.*
