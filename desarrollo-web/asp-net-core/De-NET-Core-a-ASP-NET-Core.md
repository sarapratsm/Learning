# De .NET Core a ASP.NET Core

## ¿Qué es?

ASP.NET Core es el framework web de .NET: un conjunto de librerías que se montan sobre el mismo runtime que ya usas para una aplicación de consola y lo convierten en un servidor HTTP. Sigues escribiendo C#; lo que cambia es **qué dispara tu código**. En una consola lo dispara `Main` al arrancar el proceso; en ASP.NET Core lo dispara una petición HTTP que llega por la red, y llegan miles durante la vida de un solo proceso.

Los términos que aparecen a lo largo de la guía:

- **Kestrel**: el servidor HTTP incluido en ASP.NET Core. Abre el puerto, entiende HTTP y entrega cada petición a tu código.
- **Host**: el objeto que mantiene vivo el proceso y agrupa lo que la aplicación necesita para funcionar: servidor, configuración, logging y contenedor de inyección de dependencias.
- **Middleware**: un componente de la tubería por la que pasa cada petición. Recibe la petición, puede hacer algo antes y después de llamar al siguiente y, si quiere, no llamarlo.
- **Endpoint**: el destino final de una petición (una acción de controlador o una *minimal API*), elegido por la URL y el verbo.
- **Ámbito (*scope*)**: la unidad de vida de ciertos servicios. En una aplicación web, un ámbito equivale a una petición.

## ¿Por qué existe?

Una consola arranca, hace su trabajo y termina. Un servicio web hace lo contrario: **no termina**, escucha en un puerto, atiende a muchos clientes a la vez y debe repartir cada petición al código correcto. Montarlo a mano sobre .NET (abrir sockets, interpretar HTTP, gestionar hilos, leer configuración, registrar logs) es posible, pero es trabajo repetido en cada proyecto. ASP.NET Core lo entrega ya cableado: servidor, configuración, logging, inyección de dependencias y una tubería de middleware para lo transversal (errores, autenticación, compresión).

> Analogía: una app de consola es un **cocinero que prepara un único plato por encargo y se va a casa**. Un servidor web es un **restaurante abierto todo el día**: la cocina nunca cierra, llegan comandas (peticiones) de muchas mesas a la vez, cada comanda pasa por el mismo recorrido (recepción, sala, cocina, pase) y el cocinero ya no decide cuándo trabaja, sino que **le llaman cuando llega una comanda**. Todo lo que sabes cocinar (C#, LINQ, `async`) sigue valiendo.

## ¿Cuándo y para qué se usa?

Es la base de cualquier backend web en C#: la API de una tienda online (`Tienda.Api`, con rutas como `/api/productos` y `/api/pedidos`), un panel de administración, un servicio interno que consumen otros equipos. Cuando un proyecto tiene un `Program.cs` que empieza por `WebApplication.CreateBuilder(args)`, es una aplicación ASP.NET Core.

No hace falta para una herramienta de línea de comandos, un proceso por lotes ni una librería: para un servicio que no recibe HTTP, el host genérico (`Host.CreateApplicationBuilder`) da la misma configuración, logging y DI sin servidor web.

Las salidas citadas provienen de un proyecto `Tienda.Api` creado con `dotnet new web` (SDK 10.0.401, `net10.0`) y ejecutado el 2026-11-10 con `dotnet run` y `curl`. Las trazas de log están abreviadas donde se indica.

## La plantilla mínima de .NET 10, línea a línea

`dotnet new web -n Tienda.Api` genera un proyecto vacío cuyo `Program.cs` es, íntegro:

```csharp
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "Hello World!");

app.Run();
```

| Línea | Qué hace |
|---|---|
| `WebApplication.CreateBuilder(args)` | Crea el *builder* y le entrega los argumentos de la línea de comandos. Registra de entrada Kestrel, la configuración, el logging y la DI (se detalla más abajo). |
| `builder.Build()` | Cierra el registro de servicios: construye el contenedor de DI y devuelve la `WebApplication`. Después de esta línea ya no se pueden añadir servicios; solo se configura el pipeline. |
| `app.MapGet("/", ...)` | Declara un endpoint: las peticiones `GET /` ejecutan la lambda, y lo que devuelve se escribe como respuesta. |
| `app.Run()` | Arranca Kestrel y **bloquea hasta que el proceso se detiene** (Ctrl+C, `SIGTERM`). Es el `while(true)` de la analogía: no vuelve. |

No hay `using` ni `Main` porque el SDK activa `ImplicitUsings` y C# permite instrucciones de nivel superior. El `.csproj` lo confirma: `Sdk="Microsoft.NET.Sdk.Web"` (el SDK web, que añade el *shared framework* `Microsoft.AspNetCore.App` sin tener que referenciar paquetes) y `<TargetFramework>net10.0</TargetFramework>`.

El mismo `Program.cs` con las tres fases que conviene distinguir al leer cualquier proyecto:

```csharp
// 1. REGISTRO: qué servicios existen (antes de Build)
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddScoped<IPedidoRepositorio, PedidoRepositorio>();

// 2. CONSTRUCCIÓN: se congela el contenedor
var app = builder.Build();

// 3. PIPELINE Y ENDPOINTS: qué hace cada petición (después de Build)
app.UseMiddleware<RegistroMiddleware>();
app.MapGet("/api/productos", () => ...);

app.Run();                     // 4. ARRANQUE: escucha y no vuelve
```

Con `dotnet new webapi`, la plantilla añade `builder.Services.AddOpenApi()`, `app.MapOpenApi()` dentro de `if (app.Environment.IsDevelopment())`, `app.UseHttpsRedirection()` y un endpoint de ejemplo `/weatherforecast`. El esqueleto es el mismo.

## Qué registra `WebApplication.CreateBuilder` por defecto

`CreateBuilder` no es una línea inocente: deja preparado casi todo lo que una aplicación web necesita. Para comprobar qué hay, se puede preguntar al propio sistema; por ejemplo, la lista de **proveedores de configuración** (cada uno es un origen de valores), de menor a mayor prioridad, en una ejecución en `Development`:

```csharp
app.MapGet("/api/proveedores", (IConfiguration cfg) =>
    ((IConfigurationRoot)cfg).Providers.Select(p => p.ToString()));
```

```bash
curl -s localhost:6760/api/proveedores
```

```text
["MemoryConfigurationProvider",
 "EnvironmentVariablesConfigurationProvider Prefix: 'ASPNETCORE_'",
 "MemoryConfigurationProvider",
 "EnvironmentVariablesConfigurationProvider Prefix: 'DOTNET_'",
 "CommandLineConfigurationProvider",
 "JsonConfigurationProvider for 'appsettings.json' (Optional)",
 "JsonConfigurationProvider for 'appsettings.Development.json' (Optional)",
 "JsonConfigurationProvider for 'Tienda.Api.settings.json' (Optional)",
 "JsonConfigurationProvider for 'Tienda.Api.settings.Development.json' (Optional)",
 "EnvironmentVariablesConfigurationProvider",
 "CommandLineConfigurationProvider",
 "Microsoft.Extensions.Configuration.ChainedConfigurationProvider"]
```

(Salida reformateada en varias líneas; el JSON original viene en una sola.) Las piezas que importan:

| Pieza | Qué trae por defecto |
|---|---|
| Servidor | **Kestrel**, como servidor HTTP. La respuesta de cualquier `curl -i` lo delata: `Server: Kestrel`. |
| Configuración | `appsettings.json`, `appsettings.{Entorno}.json`, variables de entorno y argumentos de línea de comandos, fusionados en un solo `IConfiguration`. En `Development`, además, los *user secrets* si el proyecto define un `UserSecretsId`. |
| Logging | `ILogger<T>` listo para inyectar, con salida a consola. Los niveles salen de la sección `Logging` de la configuración. |
| Inyección de dependencias | Un contenedor (`builder.Services`) con los servicios del framework ya registrados, y validación de ámbitos activa en `Development` (ver más abajo). |

Dos detalles más que no se ven en el `Program.cs`: en `Development`, el framework añade **solo y al principio del pipeline** una página de excepciones (`DeveloperExceptionPageMiddleware`; aparece en las trazas de la sección de entornos), y la maquinaria de enrutado (`UseRouting`/`UseEndpoints`) se activa implícitamente al llamar a `MapGet`/`MapControllers`.

## El ciclo de vida de una petición y el pipeline de middleware

Una petición `GET /api/productos` llega a Kestrel, que construye un `HttpContext` (la petición y la respuesta juntas) y lo pasa por una **cadena de middlewares**. Cada uno recibe el contexto y una referencia al siguiente (`next`). Lo que hace antes de `await next(...)` ocurre a la **ida**; lo que hace después, a la **vuelta**, cuando la respuesta ya se está generando. El último eslabón es el endpoint.

```text
petición ──► [A] ──► [B] ──► [C] ──► endpoint
respuesta ◄── [A] ◄── [B] ◄── [C] ◄──┘
```

Para ver el orden real, tres middlewares que solo escriben en el log. El primero es una clase; los otros dos, lambdas con `app.Use`. Aparecen en el pipeline **en el orden en que se declaran**:

```csharp
app.UseMiddleware<RegistroMiddleware>();            // [A]

app.Use(async (context, next) =>                    // [B]
{
    app.Logger.LogInformation("  [B] entra");
    await next(context);
    app.Logger.LogInformation("  [B] sale con {Estado}", context.Response.StatusCode);
});

app.Use(async (context, next) =>                    // [C]
{
    if (context.Request.Headers.ContainsKey("X-Mantenimiento"))
    {
        app.Logger.LogInformation("    [C] cortocircuito: no llama a next");
        context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
        await context.Response.WriteAsync("En mantenimiento");
        return;                                     // no llama a next
    }
    app.Logger.LogInformation("    [C] entra");
    await next(context);
    app.Logger.LogInformation("    [C] sale");
});

app.MapGet("/api/productos", (ILogger<Program> log) =>
{
    log.LogInformation("      endpoint /api/productos");
    return new[] { new { Id = 1, Nombre = "Teclado" } };
});

public class RegistroMiddleware(RequestDelegate next, ILogger<RegistroMiddleware> log)
{
    public async Task InvokeAsync(HttpContext context)
    {
        log.LogInformation("[A] entra: {Metodo} {Ruta}", context.Request.Method, context.Request.Path);
        await next(context);
        log.LogInformation("[A] sale con {Estado}", context.Response.StatusCode);
    }
}
```

Una petición normal deja esto en el log (se omite la línea `info: categoría[0]` que precede a cada mensaje):

```bash
curl -i localhost:6760/api/productos
```

```text
[A] entra: GET /api/productos
  [B] entra
    [C] entra
      endpoint /api/productos
    [C] sale
  [B] sale con 200
[A] sale con 200
```

La sangría muestra el anidamiento: entran en orden A, B, C, el endpoint, y salen **en orden inverso** C, B, A. Respuesta: `200 OK` con `[{"id":1,"nombre":"Teclado"}]`.

### El cortocircuito

Un middleware que **no llama a `next`** corta la cadena: lo que viene detrás no se ejecuta, y la respuesta vuelve por los que ya habían entrado. Con la cabecera `X-Mantenimiento`:

```bash
curl -i -H "X-Mantenimiento: 1" localhost:6760/api/productos
```

```text
HTTP/1.1 503 Service Unavailable
Server: Kestrel

En mantenimiento
```

```text
[A] entra: GET /api/productos
  [B] entra
    [C] cortocircuito: no llama a next
  [B] sale con 503
[A] sale con 503
```

El endpoint nunca se ejecutó (no hay línea `endpoint /api/productos`), pero A y B sí ven la vuelta, y B lee el `503` que puso C. Así funcionan por dentro la autenticación que responde `401`, la redirección a HTTPS o los ficheros estáticos: cada uno decide si la petición merece seguir.

Dos consecuencias prácticas:

- **El orden es parte del comportamiento.** Un middleware de autenticación debe ir antes del que resuelve el endpoint, y el que captura excepciones, lo más arriba posible para envolver a los demás.
- **`Use` encadena, `Run` termina.** `app.Run(handler)` registra un middleware terminal (sin `next`); no lo confundas con `app.Run()` sin argumentos, que arranca el servidor.

Los tres modelos de programación que producen endpoints (controladores, *minimal APIs*, Razor Pages) se comparan en [Modelos de programación web](Modelos-de-programacion-web.md).

## `builder.Services`: registrar servicios y sus tiempos de vida

El contenedor de inyección de dependencias entrega a cada clase lo que pide en su constructor. Qué instancia entrega depende del **tiempo de vida** con el que se registró el servicio:

| Registro | Una instancia por... | Uso típico |
|---|---|---|
| `AddSingleton<T>()` | toda la aplicación | caché en memoria, clientes HTTP configurados, estado compartido y seguro entre hilos |
| `AddScoped<T>()` | petición HTTP (un ámbito) | el `DbContext` de Entity Framework, la unidad de trabajo de la petición |
| `AddTransient<T>()` | cada vez que se pide | servicios ligeros y sin estado |

Para ver la diferencia se registran tres clases idénticas, cada una con un identificador generado en el constructor, y un endpoint que pide **dos de las scoped y dos de las transient** en la misma petición:

```csharp
builder.Services.AddSingleton<ContadorSingleton>();
builder.Services.AddScoped<ContadorScoped>();
builder.Services.AddTransient<ContadorTransient>();

public class ContadorSingleton { public Guid Id { get; } = Guid.NewGuid(); }
public class ContadorScoped    { public Guid Id { get; } = Guid.NewGuid(); }
public class ContadorTransient { public Guid Id { get; } = Guid.NewGuid(); }

app.MapGet("/api/ids", (ContadorSingleton s, ContadorScoped sc1, ContadorScoped sc2,
                         ContadorTransient t1, ContadorTransient t2) => new
{
    singleton = s.Id,
    scoped = new[] { sc1.Id, sc2.Id },
    transient = new[] { t1.Id, t2.Id },
});
```

Dos peticiones seguidas:

```bash
curl -s localhost:6760/api/ids
curl -s localhost:6760/api/ids
```

```json
{"singleton":"d4aae85e-...","scoped":["b78d0c66-...","b78d0c66-..."],"transient":["917dcdce-...","c82b17e9-..."]}
{"singleton":"d4aae85e-...","scoped":["25d80e71-...","25d80e71-..."],"transient":["11b3752d-...","5e226421-..."]}
```

(Identificadores abreviados con `...`.) Qué muestra cada columna:

- **Singleton**: el mismo identificador en las dos peticiones. Una sola instancia hasta que muere el proceso.
- **Scoped**: dentro de una petición, las dos referencias son la misma instancia; **entre peticiones cambia**.
- **Transient**: cuatro identificadores distintos en total, también dentro de la misma petición.

### Error de ámbitos: un Singleton que depende de un Scoped

Un servicio Singleton vive toda la aplicación; si recibe un Scoped en el constructor, ese Scoped se queda **capturado** (*captive dependency*) y deja de renovarse por petición. Con un `DbContext` capturado, significa datos obsoletos y acceso concurrente a un objeto que no es seguro entre hilos. Registro del error:

```csharp
builder.Services.AddSingleton<CatalogoEnCache>();

public class CatalogoEnCache(ContadorScoped contador) { public Guid Id => contador.Id; }
```

En `Development`, el contenedor valida los ámbitos y la aplicación **no arranca**:

```text
Unhandled exception. System.AggregateException: Some services are not able to be constructed
(Error while validating the service descriptor 'ServiceType: CatalogoEnCache Lifetime: Singleton
ImplementationType: CatalogoEnCache': Cannot consume scoped service 'ContadorScoped' from
singleton 'CatalogoEnCache'.)
```

El mismo código en `Production` arranca sin error, porque la validación solo está activa en `Development`. El fallo entonces es silencioso. Con un endpoint `/api/captive` que devuelve `CatalogoEnCache.Id`, dos peticiones seguidas en `Production`:

```text
"849718e6-9a27-473f-a371-d16aa8efad04"
"849718e6-9a27-473f-a371-d16aa8efad04"
```

El mismo identificador, mientras `/api/ids` seguía dando un scoped distinto por petición: el scoped quedó congelado en la primera. Arreglo: o el servicio pasa a Scoped, o el Singleton pide un `IServiceScopeFactory` y crea un ámbito explícito cada vez que lo necesita.

La regla de dependencias: un servicio solo puede depender de otros con tiempo de vida **igual o mayor** que el suyo (Transient puede usar Scoped y Singleton; Scoped puede usar Singleton; Singleton solo Singleton).

## Configuración: `IConfiguration` e `IOptions`

La configuración es un diccionario plano de claves con `:` como separador (`Tienda:Nombre`), alimentado por varios orígenes. **Gana el último origen que define la clave.** El orden por defecto, de menor a mayor prioridad, es el de la lista de proveedores mostrada antes: `appsettings.json`, `appsettings.{Entorno}.json`, *user secrets* (solo en `Development`), variables de entorno y argumentos de línea de comandos.

Para comprobarlo se define la misma clave en todos los sitios. En `appsettings.json`: `"Tienda": { "Nombre": "appsettings.json", "MaxLineas": 20 }`; en `appsettings.Development.json`: `"Tienda": { "Nombre": "appsettings.Development.json" }`. Un endpoint lee la clave directamente y, además, la sección enlazada a una clase `TiendaOptions`:

```csharp
builder.Services.Configure<TiendaOptions>(builder.Configuration.GetSection("Tienda"));

public class TiendaOptions
{
    public string Nombre { get; set; } = "(por defecto en código)";
    public int MaxLineas { get; set; } = 10;
}

app.MapGet("/api/config", (IConfiguration cfg, IOptions<TiendaOptions> opt) => new
{
    configuration = cfg["Tienda:Nombre"],
    options = opt.Value,
});
```

Cuatro ejecuciones, añadiendo un origen más prioritario cada vez:

| Cómo se lanza | `configuration` | `options` |
|---|---|---|
| `Production` (sin `Development.json`) | `appsettings.json` | `{"nombre":"appsettings.json","maxLineas":20}` |
| `Development` | `appsettings.Development.json` | `{"nombre":"appsettings.Development.json","maxLineas":20}` |
| `Development` + `Tienda__Nombre=variable-de-entorno` | `variable-de-entorno` | `{"nombre":"variable-de-entorno","maxLineas":20}` |
| lo anterior + `-- --Tienda:Nombre=argumento --Tienda:MaxLineas=99` | `argumento` | `{"nombre":"argumento","maxLineas":99}` |

Observaciones:

- `maxLineas` solo lo define `appsettings.json` (20) hasta que el argumento lo sustituye por 99: la fusión es **clave a clave**, no fichero a fichero.
- En una variable de entorno el separador `:` se escribe **`__`** (doble guion bajo), porque algunos sistemas no admiten `:` en los nombres: `Tienda__Nombre`.
- Los argumentos van tras `--` en `dotnet run`, para que los reciba la aplicación y no la CLI: `dotnet run -- --Tienda:Nombre=argumento`.

`IConfiguration` sirve para leer claves sueltas; para una sección completa, el patrón habitual es **enlazarla a una clase** y recibir `IOptions<T>`, como arriba. Cómo se validan las opciones al arrancar y la diferencia entre `IOptions`, `IOptionsSnapshot` e `IOptionsMonitor` se explica en [Microsoft.Extensions.Options](../../lenguajes/csharp-dotnet/Microsoft-Extensions-Options.md).

## Entornos: `Development` frente a `Production`

El entorno es una cadena que lee la variable `ASPNETCORE_ENVIRONMENT`. Si no existe, el valor es **`Production`**: se comprobó lanzando la aplicación sin la variable y sin perfil de lanzamiento, y el log dice `Hosting environment: Production`. De ahí salen dos efectos: qué ficheros `appsettings.{Entorno}.json` se cargan, y qué hace el código que consulta `app.Environment.IsDevelopment()`.

Lo que cambia de verdad es poco y concreto. La prueba es un endpoint que lanza una excepción:

```csharp
app.MapGet("/api/boom", () => { throw new InvalidOperationException("El pedido #4711 no se pudo cargar"); });
```

En `Development`, la respuesta lleva el mensaje, la traza y hasta la ruta del fichero fuente:

```text
HTTP/1.1 500 Internal Server Error
Content-Type: text/plain; charset=utf-8

System.InvalidOperationException: El pedido #4711 no se pudo cargar
   at Program.<>c.<<Main>$>b__0_5() in C:\...\Tienda.Api\Program.cs:line 60
   ...
```

En `Production`, la misma petición:

```text
HTTP/1.1 500 Internal Server Error
Content-Length: 0
Server: Kestrel
```

Cuerpo vacío: la causa solo está en el log del servidor (`fail: Microsoft.AspNetCore.Server.Kestrel[13] ... An unhandled exception was thrown by the application`). Dejar la página de excepciones en producción regalaría a cualquiera la estructura interna de la aplicación; por eso no se activa sola. La salida de errores controlada para clientes de una API (un `ProblemDetails` con `app.UseExceptionHandler`) es la alternativa de producción.

Resumen de lo que depende del entorno por defecto:

| | `Development` | `Production` |
|---|---|---|
| Página de excepciones con traza | sí, añadida automáticamente | no |
| Validación de ámbitos de DI (el error de Singleton con Scoped) | sí | no |
| `appsettings.{Entorno}.json` | `appsettings.Development.json` | `appsettings.Production.json` |
| *User secrets* | se cargan | no se cargan |

## Hosting: Kestrel, y dónde se ejecuta

Kestrel es siempre el servidor que ejecuta tu código. Lo que cambia es lo que hay delante:

- **Directo** (lo habitual en desarrollo): Kestrel escucha en el puerto y atiende al cliente.
- **Detrás de un *reverse proxy*** (Nginx, un balanceador, IIS): el proxy termina TLS y reenvía a Kestrel. Es la configuración de producción recomendada.
- **IIS *in-process* u *out-of-process***: en Windows con IIS, la aplicación puede ejecutarse dentro del proceso de IIS (*in-process*, sin Kestrel) o en un proceso aparte al que IIS reenvía (*out-of-process*, con Kestrel). Se menciona para reconocer los términos; no se probó en esta guía.

El detalle de publicar y exponer la aplicación está en [Despliegue](Despliegue.md).

## Ejecutar y desarrollar: `dotnet run`, `dotnet watch` y `launchSettings.json`

`dotnet run` compila y arranca el proyecto. Al ejecutarlo se vio esta primera línea:

```text
Usando la configuración de inicio de ...\Tienda.Api\Properties\launchSettings.json...
```

`Properties/launchSettings.json` es un fichero **solo de desarrollo local**: define perfiles de arranque que `dotnet run` y el IDE leen, y que **no se publica**. Contenido generado por `dotnet new web` (recortado):

```json
{
  "profiles": {
    "http": {
      "commandName": "Project",
      "dotnetRunMessages": true,
      "launchBrowser": true,
      "applicationUrl": "http://localhost:5218",
      "environmentVariables": { "ASPNETCORE_ENVIRONMENT": "Development" }
    },
    "https": {
      "applicationUrl": "https://localhost:7091;http://localhost:5218",
      "...": "mismas claves que el perfil http (abreviado)"
    }
  }
}
```

Esto explica por qué **en local siempre estás en `Development` sin haberlo pedido**: el perfil pone `ASPNETCORE_ENVIRONMENT`. Los puertos (5218, 7091) los elige la plantilla al generar el proyecto, y `--urls` en la línea de comandos los sustituye. Para lanzar sin perfil, y ver el comportamiento real de producción, se usa `--no-launch-profile`:

```bash
ASPNETCORE_ENVIRONMENT=Production dotnet run --no-launch-profile --urls http://localhost:6761
```

`dotnet watch` es `dotnet run` más un vigilante de ficheros: al guardar un cambio, recompila y reinicia la aplicación. Se comprobó cambiando el nombre de un producto en `Program.cs` mientras `dotnet watch` ejecutaba la aplicación; tras guardar, `/api/productos` respondió con el nuevo nombre sin intervención. Se lanza con `dotnet watch --no-hot-reload` para recompilar y reiniciar siempre; sin esa opción, intenta aplicar los cambios en caliente sin reiniciar el proceso (no se probó el modo en caliente).

| | `dotnet run` | `dotnet watch` |
|---|---|---|
| Recompila al cambiar código | no | sí |
| Reinicia la app | no | sí (o aplica el cambio en caliente) |
| Para qué | probar una vez, scripts, comprobar producción | desarrollo diario |

Ninguno de los dos es la forma de ejecutar en producción: allí se publica y se ejecuta el resultado ([Despliegue](Despliegue.md)).

## Errores frecuentes

| Síntoma | Causa | Arreglo |
|---|---|---|
| `Cannot consume scoped service 'ContadorScoped' from singleton 'CatalogoEnCache'` al arrancar | Un Singleton recibe un Scoped en el constructor | Pasar el servicio a Scoped, o crear un ámbito con `IServiceScopeFactory` dentro del Singleton |
| Los datos de una petición aparecen en otra, solo en producción | La misma captura de Scoped, sin la validación que lo avisa en `Development` | Probar con `ASPNETCORE_ENVIRONMENT=Development` o activar `ValidateScopes` también en producción (ver Buenas prácticas) |
| El `curl` devuelve `500` con cuerpo vacío | Entorno `Production`: la excepción no se muestra | Leer el log del servidor; no activar la página de excepciones en producción |
| El valor de `appsettings.Production.json` no se aplica | El entorno efectivo es `Development` (lo pone `launchSettings.json`) | Lanzar con `--no-launch-profile` o fijar `ASPNETCORE_ENVIRONMENT` |
| `--Tienda:Nombre=x` se ignora con `dotnet run` | Faltó el `--` que separa argumentos de la CLI y de la aplicación | `dotnet run -- --Tienda:Nombre=x` |
| `Tienda:Nombre` en una variable de entorno no se lee | Se escribió con `:` | Escribir `Tienda__Nombre` |
| `dotnet build`/`watch` falla con `MSB3027 ... el archivo se ha bloqueado por: "Tienda.Api (14188)"` | Queda una instancia de la aplicación en ejecución que bloquea el `.exe` | Cerrar ese proceso (el mensaje da su PID) y repetir |

## Buenas prácticas avanzadas

- **`async` de arriba abajo, sin `.Result` ni `.Wait()`.** En consola bloquear una `Task` pasa desapercibido; en un servidor ocupa un hilo del *thread pool* que debería atender a otros clientes. Bajo carga, bastan unos cuantos para agotarlo (*thread pool starvation*): el servidor deja de responder sin lanzar excepciones.
- **Una sola instancia no es «estado de la petición».** Los Singleton se comparten entre hilos concurrentes: lo mutable dentro de un Singleton necesita sincronización o estructuras concurrentes. Para guardar algo por petición se usa un servicio Scoped, nunca un campo estático.
- **Los secretos no van en `appsettings.json`**, que acaba en el repositorio. En desarrollo, `dotnet user-secrets`; en producción, variables de entorno o un almacén de secretos. Como todo cae en el mismo `IConfiguration`, el código no cambia.
- **Valida los ámbitos también en el entorno que más importa.** Si el despliegue de producción ejecuta código que no se ejerció en desarrollo, `builder.Host.UseDefaultServiceProvider(o => { o.ValidateScopes = true; o.ValidateOnBuild = true; })` hace que el fallo aparezca al arrancar, también en `Production` (comprobado el 2026-11-10: con esa línea, el Singleton con Scoped de arriba impidió arrancar en `Production`).
- **Todo middleware que escribe respuesta o la puede cortar va en el orden correcto, y los transversales primero.** Captura de errores, redirección a HTTPS, autenticación y autorización se colocan antes que los endpoints; ponerlos después los deja sin efecto.
- **Una configuración tipada y validada al arrancar** (`IOptions<T>` con validación) detiene el proceso con un mensaje claro si falta una clave, en vez de fallar con una excepción nula en la primera petición que la usa.

## Documentación oficial

- [Descripción general de ASP.NET Core](https://learn.microsoft.com/es-es/aspnet/core/fundamentals/): índice de los fundamentos (host, middleware, DI, configuración, entornos).
- [Middleware de ASP.NET Core](https://learn.microsoft.com/es-es/aspnet/core/fundamentals/middleware/): orden recomendado del pipeline y el diagrama de ida y vuelta.
- [Inyección de dependencias en ASP.NET Core](https://learn.microsoft.com/es-es/aspnet/core/fundamentals/dependency-injection): tiempos de vida y la validación de ámbitos.
- [Usar varios entornos en ASP.NET Core](https://learn.microsoft.com/es-es/aspnet/core/fundamentals/environments): qué carga cada entorno y cómo se fija.

## Recursos didácticos

El SDK monta un proyecto de ejemplo en segundos con `dotnet new web` (el mínimo mostrado arriba) o `dotnet new webapi` (con OpenAPI y un endpoint de muestra): lo más rápido para tocar un `Program.cs` real. Para los códigos de estado HTTP, <https://http.cat/> los explica con gatos.

---

*En resumen: ASP.NET Core es el mismo .NET de una consola convertido en un servidor que no termina: `CreateBuilder` deja listos Kestrel, configuración, logging y DI; cada petición cruza una cadena de middlewares (ida en orden, vuelta en orden inverso, y cualquiera puede cortarla), el tiempo de vida del servicio decide si se comparte con toda la aplicación, la petición o nadie, y el entorno (`Development` por `launchSettings.json`, `Production` por defecto) decide cuánto detalle se enseña.*
