# WebApplicationFactory

## ¿Qué es?

`WebApplicationFactory<Program>` (del paquete `Microsoft.AspNetCore.Mvc.Testing`) arranca una aplicación ASP.NET Core completa dentro del proceso del test: la inyección de dependencias, el middleware, las rutas y la serialización reales, pero sin abrir ningún puerto. Entrega un `HttpClient` cuyas peticiones llegan directamente a ese host en memoria.

## ¿Por qué existe?

Probar una API «de verdad» exigía desplegarla, arrancarla, lanzar peticiones contra `localhost:5000` y confiar en que el puerto estuviera libre. `WebApplicationFactory` elimina todo eso: el test crea la aplicación real, le sustituye lo que no debe tocarse en un test (la base de datos, la pasarela de pago, el reloj) y la ataca por HTTP desde el mismo proceso. El resultado es un test de la API entera con la ergonomía de un test unitario: sin despliegue, sin puertos y con los fallos en el depurador del propio test.

> Si vienes del frontend, es la misma idea que jsdom en un test de React: un entorno real *simulado dentro del proceso de test*, sin levantar la pieza pesada (el navegador, aquí el servidor web).

## ¿Cuándo y para qué se usa?

En una tienda online, `POST /api/pedidos` valida el cuerpo, comprueba la autenticación, guarda el pedido y responde `201` con una cabecera `Location`. Cada una de esas piezas puede estar bien por separado y el endpoint fallar por cómo están conectadas: una ruta mal declarada, un servicio sin registrar, un enum que se serializa como número. `WebApplicationFactory` cubre ese nivel, el de los [tests de API](Tipos-de-tests.md): el contrato HTTP de la aplicación con sus colaboradores externos sustituidos.

Sirve para:

- Comprobar códigos de estado, cabeceras y cuerpo JSON de cada endpoint, incluidas las respuestas de error (`400`, `401`, `404`, `402`).
- Detectar composiciones de DI rotas: si el host no arranca, el test falla antes de enviar nada.
- Verificar que la autorización protege lo que debe, sin pasar por un proveedor de identidad.
- Ejercitar flujos de varias peticiones (crear un pedido, consultarlo, pagarlo) contra una base de datos temporal.

## Puesta en marcha

### Paquete y versión

`Microsoft.AspNetCore.Mvc.Testing` se versiona con el runtime: para una aplicación `net10.0` corresponde la línea 10.0.x. Comprobado el 2026-11-10, la última es la 10.0.14, la misma que `Microsoft.EntityFrameworkCore.Sqlite` y `Microsoft.EntityFrameworkCore.SqlServer`. El proyecto de pruebas es un proyecto xUnit normal (`dotnet new xunit`) con una referencia al proyecto web:

```bash
dotnet new web   -n Tienda.Api   -o src/Tienda.Api
dotnet new xunit -n Tienda.Tests -o tests/Tienda.Tests
dotnet add tests/Tienda.Tests reference src/Tienda.Api
dotnet add tests/Tienda.Tests package Microsoft.AspNetCore.Mvc.Testing
dotnet add tests/Tienda.Tests package Microsoft.EntityFrameworkCore.Sqlite   # se usa en «La base de datos»
```

La referencia al proyecto web (`ProjectReference`) importa: el paquete genera, al compilar el proyecto de pruebas, un fichero `MvcTestingAppManifest.json` que indica dónde está la carpeta de contenido de la aplicación (`appsettings*.json`, `wwwroot`). Con la API referenciada como DLL suelta, ese fichero no se genera (ver «Errores frecuentes»).

### La API bajo prueba

El dominio es el de la tienda ([xUnit](xUnit.md) lo presenta): `Pedido`, `LineaPedido`, `EstadoPedido`. `Tienda.Api` expone cuatro endpoints bajo `/api/pedidos`. Versión abreviada de `Program.cs` (se omiten los endpoints `GET` y el de pago, que siguen el mismo patrón):

```csharp
var builder = WebApplication.CreateBuilder(args);

var maximoLineas = builder.Configuration.GetValue<int>("Pedidos:MaximoLineas");

builder.Services.AddDbContext<TiendaDb>(o =>
    o.UseSqlServer(builder.Configuration.GetConnectionString("Default")));
builder.Services.AddSingleton<IRelojDelSistema, RelojReal>();
builder.Services.AddScoped<IPasarelaDePago, PasarelaReal>();
builder.Services.AddHostedService<RecordatorioDePagos>();
builder.Services.AddAuthentication("ApiKey").AddScheme<AuthenticationSchemeOptions, ApiKeyHandler>("ApiKey", null);
builder.Services.AddAuthorization();
builder.Services.ConfigureHttpJsonOptions(o => o.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));

var app = builder.Build();
app.UseAuthentication();
app.UseAuthorization();

var pedidos = app.MapGroup("/api/pedidos");

pedidos.MapPost("/", async (NuevoPedido nuevo, TiendaDb db, IRelojDelSistema reloj) =>
{
    if (nuevo.Lineas is not { Count: > 0 })
        return Results.ValidationProblem(new Dictionary<string, string[]>
            { ["lineas"] = ["Un pedido sin líneas no se puede confirmar."] });
    if (nuevo.Lineas.Count > maximoLineas)
        return Results.ValidationProblem(new Dictionary<string, string[]>
            { ["lineas"] = [$"Un pedido admite como máximo {maximoLineas} líneas."] });

    var pedido = new Pedido(nuevo.Numero);
    foreach (var l in nuevo.Lineas) pedido.AgregarLinea(l.Sku, l.Cantidad, l.PrecioUnitario);
    pedido.Confirmar();
    db.Pedidos.Add(pedido);
    await db.SaveChangesAsync();
    return Results.Created($"/api/pedidos/{pedido.Numero}", PedidoDto.De(pedido, reloj.Ahora));
}).RequireAuthorization();

app.Run();
```

Los colaboradores son interfaces pequeñas, para poder sustituirlas:

```csharp
public interface IRelojDelSistema { DateTimeOffset Ahora { get; } }

public record ResultadoPago(bool Aprobado, string? Motivo = null);
public interface IPasarelaDePago
{
    Task<ResultadoPago> CobrarAsync(int numeroPedido, decimal importe);
}
```

`GET /api/pedidos` y `GET /api/pedidos/{numero}` son públicos; `POST /api/pedidos` y `POST /api/pedidos/{numero}/pago` exigen estar autenticado. La base real es SQL Server; la pasarela real llamaría a un proveedor externo; el esquema de autenticación real lee una cabecera `X-Api-Key`.

### La clase `Program` tiene que ser visible

`WebApplicationFactory<TEntryPoint>` necesita un tipo del ensamblado de la aplicación que contenga el punto de entrada; por convención, `Program`. Con sentencias de nivel superior (`Program.cs` sin clase explícita), el compilador genera esa clase, y por defecto es `internal`: el proyecto de pruebas no la vería.

Con `Microsoft.NET.Sdk.Web` o con una referencia al framework `Microsoft.AspNetCore.App`, el SDK de .NET 10 evita el problema: el ensamblado `Microsoft.AspNetCore.App.SourceGenerators` incluye un generador (`PublicProgramSourceGenerator`) que declara la clase como pública. Comprobado el 2026-11-10 con los SDK 10.0.301 y 10.0.401: en un proyecto de consola con sentencias de nivel superior, `typeof(Program).IsPublic` es `False`; en un proyecto web equivalente, `True`, sin escribir nada más. Por eso el ejemplo no declara `public partial class Program`.

La línea `public partial class Program;` al final de `Program.cs` sigue siendo necesaria cuando el proyecto **no** recibe ese generador o la clase `Program` está declarada a mano y no es pública. Reproducción con una clase explícita:

```csharp
internal class Program
{
    public static void Main(string[] args) { /* ... */ }
}
```

```text
T.cs(2,38): error CS0122: 'Program' is inaccessible due to its protection level
```

Las dos salidas comprobadas: declararla `public class Program` (el test pasa) o escribir `public partial class Program;` junto a las sentencias de nivel superior (también pasa). Con `<InternalsVisibleTo Include="Tienda.Tests" />` en el `.csproj` de la API, la clase de test deja de dar `CS0122`, pero pasa a dar `CS0051: Inconsistent accessibility: parameter type 'WebApplicationFactory<Program>' is less accessible than method`: la clase de test también debe ser `internal`.

## Primeros tests: `GET` y `POST` contra `/api/pedidos`

### Un test, una factory

`WebApplicationFactory<Program>` se puede usar tal cual como fixture de xUnit. El ejemplo mínimo comprueba que un pedido inexistente da `404`:

```csharp
public class PedidosMinimoTests(WebApplicationFactory<Program> factory)
    : IClassFixture<WebApplicationFactory<Program>>
{
    [Fact]
    public async Task Get_PedidoInexistente_Devuelve404()
    {
        var cliente = factory.CreateClient();

        var respuesta = await cliente.GetAsync("/api/pedidos/999999");

        Assert.Equal(HttpStatusCode.NotFound, respuesta.StatusCode);
    }
}
```

Con la factory sin personalizar, la aplicación arranca con su configuración real: busca SQL Server en `localhost` y las llamadas que lo tocan fallan. Una petición a `GET /api/pedidos` en ese estado, con el entorno por defecto, devolvió `500` tras unos 8 segundos de espera de conexión:

```text
Failed Tienda.Tests.PrimerTest.Get_Pedidos_Responde [8 s]
  Assert.Equal() Failure: Values differ
Expected: OK
Actual:   InternalServerError
```

De ahí la necesidad de una factory propia.

### Qué ocurre al pedir un cliente

`IClassFixture<T>` hace que xUnit cree **una** factory por clase de test y la comparta entre todos sus tests (el ciclo de vida de los fixtures se explica en [Fixtures y ciclo de vida](Fixtures-y-ciclo-de-vida.md)). La factory construye el host la primera vez que se pide un cliente o se accede a `Services`: ese primer test de cada clase paga el arranque (de 1 a 8 segundos en la ejecución citada abajo) y el resto solo el coste de la petición.

`CreateClient()` devuelve un `HttpClient` conectado al `TestServer` del host. La petición no pasa por la red: `HttpClient` entrega el mensaje al pipeline en memoria y recibe la respuesta. Cada llamada a `CreateClient()` devuelve un cliente nuevo; las cabeceras por defecto de uno no afectan a otro.

### Factory propia

`TiendaApiFactory` reúne todo lo que los tests necesitan cambiar. El resto de las secciones explica cada bloque; el conjunto, con los `using` omitidos:

```csharp
public class TiendaApiFactory : WebApplicationFactory<Program>
{
    // La base en memoria vive mientras la conexión esté abierta.
    private readonly SqliteConnection _conexion = new("DataSource=:memory:");

    public RelojFijo Reloj { get; } = new(new DateTimeOffset(2026, 11, 10, 9, 0, 0, TimeSpan.Zero));
    public PasarelaFalsa Pasarela { get; } = new();

    public TiendaApiFactory() => _conexion.Open();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");

        builder.ConfigureTestServices(services =>
        {
            // Base de datos: SQL Server de la aplicación -> SQLite en memoria
            services.RemoveAll<DbContextOptions<TiendaDb>>();
            services.RemoveAll<IDbContextOptionsConfiguration<TiendaDb>>();
            services.AddDbContext<TiendaDb>(o => o.UseSqlite(_conexion));

            // Dobles de los colaboradores externos
            services.RemoveAll<IRelojDelSistema>();
            services.AddSingleton<IRelojDelSistema>(Reloj);
            services.RemoveAll<IPasarelaDePago>();
            services.AddSingleton<IPasarelaDePago>(Pasarela);

            // Autenticación: esquema de prueba como esquema por defecto
            services.AddAuthentication(TestAuthHandler.Esquema)
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuthHandler.Esquema, null);

            // Servicios en segundo plano: fuera
            services.Remove(services.Single(d =>
                d.ServiceType == typeof(IHostedService) && d.ImplementationType == typeof(RecordatorioDePagos)));
        });
    }

    protected override IHost CreateHost(IHostBuilder builder)
    {
        var host = base.CreateHost(builder);
        using var scope = host.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<TiendaDb>().Database.EnsureCreated();
        return host;
    }

    // Devuelve la factory al estado inicial: tablas vacías y dobles sin rastro del test anterior.
    public void Reiniciar()
    {
        using var scope = Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<TiendaDb>().Pedidos.ExecuteDelete();
        Pasarela.Respuesta = new ResultadoPago(true);
        Pasarela.Cobros.Clear();
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing) _conexion.Dispose();
    }
}
```

`ConfigureWebHost` es el punto de extensión principal: recibe el `IWebHostBuilder` de la aplicación antes de que se construya. `CreateHost` permite actuar sobre el host ya construido y antes de que reciba peticiones; aquí crea el esquema de la base de datos.

### `POST` y `GET`: estado y JSON

Con la factory propia, el patrón de un test de API es el de [Arrange-Act-Assert](Arrange-Act-Assert.md): preparar el cliente y el cuerpo, enviar la petición, comprobar la respuesta. `PostAsJsonAsync` y `ReadFromJsonAsync` (de `System.Net.Http.Json`) serializan y deserializan sin código manual:

```csharp
public class PedidosApiTests(TiendaApiFactory factory) : IClassFixture<TiendaApiFactory>
{
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter() }
    };

    private HttpClient ClienteAutenticado()
    {
        var cliente = factory.CreateClient();
        cliente.DefaultRequestHeaders.Add("X-Usuario-Test", "ana");
        return cliente;
    }

    private static NuevoPedido PedidoConUnaLinea(int numero) =>
        new(numero, [new LineaNueva("CAM-001", 2, 19.99m)]);

    [Fact]
    public async Task Post_PedidoValido_Devuelve201ConLocationYCuerpo()
    {
        var cliente = ClienteAutenticado();

        var respuesta = await cliente.PostAsJsonAsync("/api/pedidos", PedidoConUnaLinea(4711));

        Assert.Equal(HttpStatusCode.Created, respuesta.StatusCode);
        Assert.Equal("/api/pedidos/4711", respuesta.Headers.Location?.OriginalString);
        var pedido = await respuesta.Content.ReadFromJsonAsync<PedidoDto>(Json);
        Assert.Equal(new PedidoDto(4711, EstadoPedido.Confirmado, 39.98m, factory.Reloj.Ahora), pedido);
    }

    [Fact]
    public async Task Get_PedidoExistente_DevuelveElPedido()
    {
        var cliente = ClienteAutenticado();
        await cliente.PostAsJsonAsync("/api/pedidos", PedidoConUnaLinea(4714));

        var pedido = await cliente.GetFromJsonAsync<PedidoDto>("/api/pedidos/4714", Json);

        Assert.Equal(4714, pedido!.Numero);
        Assert.Equal(39.98m, pedido.Total);
    }
}
```

El primer test comprueba tres cosas con una sola petición: el código (`201`), la cabecera `Location` y el cuerpo. Como `PedidoDto` es un `record`, `Assert.Equal` compara todas sus propiedades de una vez. El campo `CreadoEn` coincide con `factory.Reloj.Ahora` porque el reloj de la factory es un doble: ver «Sustituir servicios».

Las respuestas de error también se prueban con su cuerpo. Una validación fallida devuelve un `ValidationProblem` (cuerpo estándar de ASP.NET Core, `HttpValidationProblemDetails`):

```csharp
[Fact]
public async Task Post_SinLineas_Devuelve400ConElMensajeDeValidacion()
{
    var cliente = ClienteAutenticado();

    var respuesta = await cliente.PostAsJsonAsync("/api/pedidos", new NuevoPedido(4713, []));

    Assert.Equal(HttpStatusCode.BadRequest, respuesta.StatusCode);
    var problema = await respuesta.Content.ReadFromJsonAsync<HttpValidationProblemDetails>();
    Assert.Equal(["Un pedido sin líneas no se puede confirmar."], problema!.Errors["lineas"]);
}
```

Salida de `dotnet test --logger "console;verbosity=normal"` con los tests de `PedidosApiTests` (más los de las secciones siguientes), tomada de una ejecución completa:

```text
  Passed Tienda.Tests.PedidosApiTests.Post_SinAutenticar_Devuelve401 [25 ms]
  Passed Tienda.Tests.PedidosApiTests.Get_Estado_SeSerializaComoTexto [61 ms]
  Passed Tienda.Tests.PedidosApiTests.Post_SinLineas_Devuelve400ConElMensajeDeValidacion [46 ms]
  Passed Tienda.Tests.PedidosApiTests.Pago_Rechazado_Devuelve402ConElMotivo [19 ms]
  Passed Tienda.Tests.PedidosApiTests.Post_PedidoValido_Devuelve201ConLocationYCuerpo [16 ms]
  Passed Tienda.Tests.PedidosApiTests.Pago_Aprobado_MarcaElPedidoComoPagado [36 ms]
  Passed Tienda.Tests.PedidosApiTests.Get_PedidoInexistente_Devuelve404 [5 ms]
```

Cada test tarda decenas de milisegundos: la aplicación entera ya está arrancada y la petición no sale del proceso.

Las salidas citadas provienen de `dotnet test` ejecutado el 2026-11-10 con el SDK 10.0.401, xUnit 2.9.3, `Microsoft.AspNetCore.Mvc.Testing` 10.0.14 y EF Core 10.0.14, con `VSLANG=1033` y `DOTNET_CLI_UI_LANGUAGE=en`, y rutas acortadas. Los decimales salen con coma porque la salida usa la cultura del sistema (español).

### El contrato JSON, no solo el DTO

Deserializar al DTO y comparar propiedades no detecta que un enum se serialice como número en lugar de texto: un cliente que espera `"Confirmado"` recibiría `1` y el test seguiría en verde. El contrato se comprueba sobre el JSON crudo:

```csharp
[Fact]
public async Task Get_Estado_SeSerializaComoTexto()
{
    var cliente = ClienteAutenticado();
    await cliente.PostAsJsonAsync("/api/pedidos", PedidoConUnaLinea(4715));

    var json = await cliente.GetStringAsync("/api/pedidos/4715");

    Assert.Contains("\"estado\":\"Confirmado\"", json);
}
```

En el sentido contrario, `ReadFromJsonAsync` y `GetFromJsonAsync` sin opciones usan los valores por defecto de la web (nombres en `camelCase`, enums como número). Si la API usa `JsonStringEnumConverter`, el cliente de prueba debe usarlo también:

```text
System.Text.Json.JsonException : The JSON value could not be converted to PedidoDto. Path: $.estado | LineNumber: 0 | BytePositionInLine: 36.
```

Las opciones estáticas `Json` del ejemplo reflejan las de `Program.cs`. Si cambian en un sitio y no en el otro, el test falla (o miente); extraerlas a un lugar compartido evita la desincronización.

## Sustituir servicios

`ConfigureTestServices` (en `Microsoft.AspNetCore.TestHost`) registra servicios **después** de todos los de `Program.cs`, y el contenedor de DI resuelve el último registro de cada tipo. Así un fake gana sin tocar la aplicación. Dos dobles escritos a mano, sin librería de mocks:

```csharp
public class RelojFijo(DateTimeOffset ahora) : IRelojDelSistema
{
    public DateTimeOffset Ahora { get; set; } = ahora;
}

public class PasarelaFalsa : IPasarelaDePago
{
    public ResultadoPago Respuesta { get; set; } = new(true);
    public List<(int Numero, decimal Importe)> Cobros { get; } = [];

    public Task<ResultadoPago> CobrarAsync(int numeroPedido, decimal importe)
    {
        Cobros.Add((numeroPedido, importe));
        return Task.FromResult(Respuesta);
    }
}
```

La factory los registra con `AddSingleton<I...>(instancia)` y los expone como propiedades; el test configura la respuesta y comprueba lo que recibió la pasarela:

```csharp
[Fact]
public async Task Pago_Rechazado_Devuelve402ConElMotivo()
{
    var cliente = ClienteAutenticado();
    await cliente.PostAsJsonAsync("/api/pedidos", PedidoConUnaLinea(4717));
    factory.Pasarela.Respuesta = new ResultadoPago(false, "Tarjeta sin fondos");

    var respuesta = await cliente.PostAsync("/api/pedidos/4717/pago", content: null);

    Assert.Equal(HttpStatusCode.PaymentRequired, respuesta.StatusCode);
    var problema = await respuesta.Content.ReadFromJsonAsync<ProblemDetails>();
    Assert.Equal("Tarjeta sin fondos", problema!.Detail);
}
```

El camino feliz usa `Respuesta = new ResultadoPago(true)` (el valor por defecto) y comprueba además que la pasarela recibió el cobro correcto: `Assert.Contains((4716, 39.98m), factory.Pasarela.Cobros)`. Si el test no sustituyera la pasarela, el servicio real se ejecutaría y la excepción llegaría al test:

```text
System.Net.Http.HttpRequestException : No se pudo conectar con pagos.ejemplo.com
   at Tienda.Api.PasarelaReal.CobrarAsync(Int32 numeroPedido, Decimal importe)
```

Para dobles generados con librería (comprobar llamadas, devolver valores según los argumentos), [NSubstitute](NSubstitute.md) encaja igual: se registra el sustituto con `services.AddSingleton(sustituto)`.

### Una variante por test: `WithWebHostBuilder`

`factory.WithWebHostBuilder(...)` devuelve una factory derivada que aplica la configuración de la original más lo que se le añade. Sirve para variar un servicio en un único test sin crear otra clase de factory:

```csharp
[Fact]
public async Task Post_ConOtroReloj_DevuelveLaFechaDeEseReloj()
{
    var nochebuena = new RelojFijo(new DateTimeOffset(2026, 12, 24, 23, 59, 0, TimeSpan.Zero));
    var cliente = factory
        .WithWebHostBuilder(b => b.ConfigureTestServices(s => s.AddSingleton<IRelojDelSistema>(nochebuena)))
        .CreateClient();
    cliente.DefaultRequestHeaders.Add("X-Usuario-Test", "ana");

    var respuesta = await cliente.PostAsJsonAsync("/api/pedidos", PedidoConUnaLinea(4718));

    var pedido = await respuesta.Content.ReadFromJsonAsync<PedidoDto>(Json);
    Assert.Equal(nochebuena.Ahora, pedido!.CreadoEn);
}
```

Cada `WithWebHostBuilder` arranca **otro host**, con su coste de arranque. La factory derivada reutiliza `ConfigureWebHost` de la original, así que comparte la misma conexión SQLite: ve los datos de los demás tests de la clase.

## Configuración y entorno

### Tres mecanismos, resultados distintos

La aplicación lee `Pedidos:MaximoLineas` directamente de `builder.Configuration` al principio de `Program.cs`. `appsettings.json` lo fija en 100 y `appsettings.Testing.json` (un fichero de la API que solo se carga con el entorno `Testing`) en 5. Se probaron tres formas de cambiarlo desde el test, enviando un pedido de 3 líneas con el valor 2 y otro de 6 líneas sin sobrescribir nada:

| Mecanismo | Código | Resultado observado |
|---|---|---|
| Entorno `Testing` | `builder.UseEnvironment("Testing")` | Carga `appsettings.Testing.json`: un pedido de 6 líneas da `400 Un pedido admite como máximo 5 líneas.` |
| `UseSetting` | `b.UseSetting("Pedidos:MaximoLineas", "2")` | Se aplica: el de 3 líneas da `400 ... como máximo 2 líneas.` |
| `ConfigureAppConfiguration` | `cfg.AddInMemoryCollection(new Dictionary<string, string?> { ["Pedidos:MaximoLineas"] = "2" })` | **No se aplica**: el pedido de 3 líneas se acepta (`201`) |

`ConfigureAppConfiguration` añade el origen de configuración al host, pero `Program.cs` ya había leído `builder.Configuration` antes de que ese origen existiera. Los valores que el código lee durante la construcción (como `maximoLineas` o la cadena de conexión que se pasa a `UseSqlServer`) se sobrescriben con `UseSetting`, que fija el valor antes de que `Program.cs` empiece. Un valor que se lee más tarde (por ejemplo, a través de `IOptions<T>` en el momento de la petición) no tiene este problema; la prueba citada solo cubre la lectura directa durante la construcción.

```csharp
[Fact]
public async Task Post_ConElMaximoSobrescritoEnElTest_RespetaElNuevoValor()
{
    var cliente = factory
        .WithWebHostBuilder(b => b.UseSetting("Pedidos:MaximoLineas", "2"))
        .CreateClient();
    cliente.DefaultRequestHeaders.Add("X-Usuario-Test", "ana");
    var lineas = Enumerable.Range(1, 3).Select(i => new LineaNueva($"SKU-{i}", 1, 1m)).ToList();

    var respuesta = await cliente.PostAsJsonAsync("/api/pedidos", new NuevoPedido(4720, lineas));

    var problema = await respuesta.Content.ReadFromJsonAsync<HttpValidationProblemDetails>();
    Assert.Equal(["Un pedido admite como máximo 2 líneas."], problema!.Errors["lineas"]);
}
```

### Qué cambia el entorno

El entorno por defecto de `WebApplicationFactory` es `Development`. Eso tiene efectos que un test no suele querer: carga `appsettings.Development.json` y activa la página de excepciones del desarrollador, de modo que una excepción en un endpoint llega como respuesta `500` en lugar de propagarse. Con `UseEnvironment("Testing")` la excepción de la pasarela real, citada arriba, llegó al test como excepción y no como `500`: el fallo se lee en la pila, en el sitio donde ocurre. Un entorno propio (`Testing`) también permite un `appsettings.Testing.json` con valores específicos de pruebas, sin ensuciar `appsettings.Development.json`.

## Autenticación falsa

Para probar los endpoints protegidos sin un proveedor de identidad, la factory sustituye el esquema de autenticación por uno de prueba: un `AuthenticationHandler` que autentica si la petición lleva una cabecera concreta y, si no, no devuelve resultado (lo que produce el `401`):

```csharp
public class TestAuthHandler(IOptionsMonitor<AuthenticationSchemeOptions> o, ILoggerFactory l, UrlEncoder e)
    : AuthenticationHandler<AuthenticationSchemeOptions>(o, l, e)
{
    public const string Esquema = "Test";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue("X-Usuario-Test", out var usuario))
            return Task.FromResult(AuthenticateResult.NoResult());

        var identidad = new ClaimsIdentity([new Claim(ClaimTypes.Name, usuario.ToString())], Esquema);
        return Task.FromResult(AuthenticateResult.Success(
            new AuthenticationTicket(new ClaimsPrincipal(identidad), Esquema)));
    }
}
```

Se registra como esquema por defecto en `ConfigureTestServices` (en la factory, arriba): `AddAuthentication("Test").AddScheme<..., TestAuthHandler>("Test", null)`. El diseño con cabecera permite que **una** factory sirva a los dos casos: el cliente anónimo y el autenticado. La alternativa, un handler que autentica siempre, obliga a una factory aparte para probar el `401`.

Dos tests que fijan el comportamiento:

```csharp
[Fact]
public async Task Post_SinAutenticar_Devuelve401()
{
    var cliente = factory.CreateClient();   // sin cabecera X-Usuario-Test

    var respuesta = await cliente.PostAsJsonAsync("/api/pedidos", PedidoConUnaLinea(4712));

    Assert.Equal(HttpStatusCode.Unauthorized, respuesta.StatusCode);
}
```

El otro es cualquiera de los anteriores con `ClienteAutenticado()`. El test del `401` es la alarma contra quien retire por accidente el `RequireAuthorization()`.

Este enfoque prueba que la **autorización** de la API funciona (el endpoint exige un usuario), no que el esquema **real** valide bien las credenciales. Para el flujo de autenticación en sí (la comprobación de la clave `X-Api-Key`, el JWT) se escriben tests aparte contra el esquema real, sin sustituirlo.

## La base de datos: SQLite en memoria

### Cambiar el proveedor de EF Core

`WebApplicationFactory` no aporta base de datos: o se sustituye por otra ligera, o se apunta a una real (ver [Testcontainers](Testcontainers.md) y la [guía de Testcontainers de Docker](../../devops/docker/Testcontainers.md)). SQLite en memoria es la opción rápida: un solo paquete, sin Docker. El `DbContext` de la aplicación se registró con `UseSqlServer`; la factory lo vuelve a registrar con `UseSqlite`:

```csharp
services.RemoveAll<DbContextOptions<TiendaDb>>();
services.RemoveAll<IDbContextOptionsConfiguration<TiendaDb>>();
services.AddDbContext<TiendaDb>(o => o.UseSqlite(_conexion));
```

Desde EF Core 9, `AddDbContext` registra además un `IDbContextOptionsConfiguration<TiendaDb>` con la configuración del proveedor. Quitar solo `DbContextOptions<TiendaDb>` (lo que bastaba antes) deja esa configuración viva, y el resultado son dos proveedores en el mismo contexto:

```text
System.InvalidOperationException : Services for database providers 'Microsoft.EntityFrameworkCore.SqlServer', 'Microsoft.EntityFrameworkCore.Sqlite' have been registered in the service provider. Only a single database provider can be registered in a service provider. If possible, ensure that Entity Framework is managing its service provider by removing the call to 'UseInternalServiceProvider'. Otherwise, consider conditionally registering the database provider, or maintaining one service provider per database provider.
```

### La conexión se mantiene abierta

Una base `:memory:` de SQLite existe mientras vive **la conexión** que la creó; cuando EF cierra una conexión propia, la base desaparece. Por eso la factory abre una `SqliteConnection` en su constructor, la pasa a `UseSqlite(_conexion)` y la elimina en `Dispose`. El esquema se crea una vez en `CreateHost` con `EnsureCreated()`, que genera las tablas desde el modelo (sin migraciones). Sin conexión compartida, con `UseSqlite("DataSource=:memory:")`, cada `DbContext` obtiene una base vacía distinta:

```text
Microsoft.EntityFrameworkCore.DbUpdateException : An error occurred while saving the entity changes. See the inner exception for details.
---- Microsoft.Data.Sqlite.SqliteException : SQLite Error 1: 'no such table: Pedidos'.
```

Más sobre EF Core y sobre el cambio de proveedor en [Entity Framework Core](../../bases-de-datos/acceso-a-datos-dotnet/Entity-Framework-Core.md).

SQLite no es SQL Server: los tipos, las colaciones, el manejo de `decimal` y el SQL que genera EF son distintos. Un test verde sobre SQLite no garantiza el mismo resultado sobre el motor de producción; para consultas con comportamiento específico del motor o migraciones, [Testcontainers](Testcontainers.md) levanta el motor real. No se contrastaron aquí las diferencias concretas entre ambos motores.

## Aislar el estado entre tests

### La fuga

Una factory compartida es **una** aplicación y **una** base de datos para todos los tests de la clase. Lo que un test escribe, el siguiente lo ve. Dos tests de una clase con `IClassFixture<TiendaApiFactory>`: uno crea el pedido 4711 y comprueba que la lista tiene un pedido; el otro comprueba que, sin crear nada, la lista está vacía:

```csharp
[Fact]
public async Task Crear_Pedido4711_ListaTieneUnPedido() { /* POST 4711, GET lista, Assert.Single(lista) */ }

[Fact]
public async Task SinPedidos_ListaVacia() { /* GET lista, Assert.Empty(lista) */ }
```

Ejecutada tres veces (la clase se llamaba `FugaDeEstadoTests`), la salida fue idéntica: el test que crea el pedido corrió antes en las tres, y el otro falló:

```text
  Passed Tienda.Tests.FugaDeEstadoTests.Crear_Pedido4711_ListaTieneUnPedido [2 s]
  Failed Tienda.Tests.FugaDeEstadoTests.SinPedidos_ListaVacia [20 ms]
   Assert.Empty() Failure: Collection was not empty
Collection: [PedidoDto { Numero = 4711, Estado = Confirmado, Total = 10,0, CreadoEn =  }]
```

xUnit no garantiza el orden de los tests de una clase (ver [xUnit](xUnit.md)); con el orden contrario, el test de la lista vacía pasaría. Un fallo que depende del orden es el síntoma de estado compartido.

### Tres estrategias

| Estrategia | Cómo | Cuándo |
|---|---|---|
| Datos propios por test | Cada test usa números de pedido distintos (4711, 4712...) y consulta solo lo suyo, sin asumir tablas vacías | Suites pequeñas; lo más barato |
| Reiniciar antes de cada test | El constructor de la clase de test llama a `factory.Reiniciar()` (vaciar tablas, resetear dobles) | Tests que necesitan una base vacía o contar filas |
| Una factory por test | `using var factory = new TiendaApiFactory();` dentro del test | Cuando el reinicio es difícil; cada test paga el arranque del host |

`PedidosApiTests` usa la primera estrategia (números 4711 a 4720). La segunda, con el método `Reiniciar()` de la factory, deja el par anterior en verde con cualquier orden:

```csharp
public class ListadoDePedidosTests : IClassFixture<TiendaApiFactory>
{
    private readonly TiendaApiFactory factory;

    public ListadoDePedidosTests(TiendaApiFactory factory)
    {
        this.factory = factory;
        factory.Reiniciar();   // xUnit crea una instancia por test: se ejecuta antes de cada uno
    }

    // los mismos dos tests, ahora sin fuga
}
```

```text
Passed!  - Failed:     0, Passed:     2, Skipped:     0, Total:     2, Duration: 2 s - Tienda.Tests.dll (net10.0)
```

Los tests de una misma clase se ejecutan en serie, así que `Reiniciar()` no pisa a un test en curso. Las clases distintas se ejecutan en paralelo, pero cada clase tiene su propia factory y, con ella, su propia base en memoria. Si varias clases compartieran una factory (con una colección de xUnit, ver [Fixtures y ciclo de vida](Fixtures-y-ciclo-de-vida.md)), el reinicio dejaría de ser seguro y habría que serializar esas clases.

## Servicios en segundo plano

Un `IHostedService` o `BackgroundService` arranca con el host. En producción envía recordatorios de pago; en un test, el servicio de ejemplo (`RecordatorioDePagos`, que registra una línea de log al arrancar) se ejecuta como parte del arranque de la factory. Sin quitarlo, la salida del test lo muestra:

```text
info: Tienda.Api.RecordatorioDePagos[0]
      RecordatorioDePagos: enviando recordatorios a clientes
```

Un servicio real haría trabajo real (correos, llamadas, escrituras en la base) al arrancar cada factory, con efectos que el test no ha pedido y dependencias de tiempo. La factory lo elimina buscando el descriptor concreto:

```csharp
services.Remove(services.Single(d =>
    d.ServiceType == typeof(IHostedService) && d.ImplementationType == typeof(RecordatorioDePagos)));
```

`services.RemoveAll<IHostedService>()` también funciona, pero elimina todos los servicios en segundo plano, incluidos los que registren librerías y la aplicación necesite para funcionar. Con la eliminación selectiva, la salida del test deja de mostrar la línea de log. Si el comportamiento del servicio es lo que se quiere probar, se prueba la clase directamente o se invoca su método con un doble del reloj, no a través del arranque de la factory.

## Errores frecuentes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `error CS0122: 'Program' is inaccessible due to its protection level` | La clase `Program` es `internal` (clase declarada a mano, o proyecto sin el generador de `Program` público) | `public partial class Program;` al final de `Program.cs` o `public class Program` (con `InternalsVisibleTo`, la clase de test también debe ser `internal`) |
| `InvalidOperationException : The provided Type 'Pedido' does not belong to an assembly with an entry point. A common cause for this error is providing a Type from a class library.` | `WebApplicationFactory<T>` con un `T` de una biblioteca de clases (aquí `Tienda.Dominio`) | Usar `Program` de la API como `T` |
| `DirectoryNotFoundException : ...\Tienda.Api\` al crear el cliente | No se encuentra la carpeta de contenido: falta `MvcTestingAppManifest.json` en la salida (se borró para reproducirlo; ocurre si la API no se referencia con `ProjectReference`) | Referenciar el proyecto web con `ProjectReference` (o declarar el atributo `WebApplicationFactoryContentRoot` del ensamblado, alternativa documentada que no se probó aquí) |
| `Services for database providers 'Microsoft.EntityFrameworkCore.SqlServer', 'Microsoft.EntityFrameworkCore.Sqlite' have been registered` | Solo se quitó `DbContextOptions<T>`; EF Core 9 y posteriores dejan `IDbContextOptionsConfiguration<T>` | Quitar también `IDbContextOptionsConfiguration<TiendaDb>` |
| `SQLite Error 1: 'no such table: Pedidos'` | Base `:memory:` sin conexión compartida, o sin `EnsureCreated` | Una `SqliteConnection` abierta que viva lo que la factory; crear el esquema en `CreateHost` |
| Un test pasa solo o en un orden y falla en otro | Estado compartido en la factory del fixture | Datos propios por test, `Reiniciar()` o factory por test |
| `The JSON value could not be converted to PedidoDto. Path: $.estado` | La API serializa el enum como texto y el cliente de prueba lo espera como número | Pasar a `ReadFromJsonAsync` las mismas opciones (con `JsonStringEnumConverter`) |
| Un valor de configuración sobrescrito no tiene efecto | Se usó `ConfigureAppConfiguration` y `Program.cs` lo lee durante la construcción | Usar `UseSetting` |
| Aparece actividad inesperada en la salida del test (logs, llamadas, correos) | Un `IHostedService` arranca con la factory | Quitar su descriptor en `ConfigureTestServices` |
| `500` en lugar de la excepción real | Entorno `Development` por defecto: la página de excepciones lo convierte en respuesta | `UseEnvironment("Testing")` para que la excepción llegue al test |

## Qué no prueba

`WebApplicationFactory` prueba el **pipeline de la aplicación**: rutas, middleware, filtros, binding, serialización, autorización, DI. No prueba lo que ocurre antes de que la petición llegue a ese pipeline:

- **Red, proxy inverso y TLS.** El `HttpClient` habla con un `TestServer` en memoria, no con Kestrel. Certificados, redirección HTTP a HTTPS por el proxy, cabeceras `X-Forwarded-*` y límites del servidor quedan fuera.
- **Despliegue.** La imagen de Docker, las variables de entorno del entorno real, los puertos y las comprobaciones de salud del orquestador no se ejercitan.
- **La base de datos de producción.** Con SQLite en memoria se prueba el código de acceso a datos, no el motor.
- **Navegador y frontend.** No ejecuta JavaScript ni abre páginas; para eso, pruebas de extremo a extremo con un navegador.

Un pequeño conjunto de tests contra el sistema desplegado (humo) cubre esos huecos, en el nivel que explica [Tipos de tests](Tipos-de-tests.md).

## Cuándo usarlo y cuándo probar el handler directamente

| Qué se quiere comprobar | Herramienta | Por qué |
|---|---|---|
| Una regla del dominio (`Pedido.Confirmar` sin líneas lanza) | Test unitario del dominio | No necesita HTTP ni DI; milisegundos |
| La lógica de un endpoint que se puede aislar en una clase o función | Test unitario de esa clase, con dobles | Rápido y localizado; no depende de rutas ni de binding |
| Ruta, método HTTP, código de estado, cabeceras, cuerpo JSON, formato de errores | `WebApplicationFactory` | Solo el pipeline completo muestra el contrato real |
| Que la autorización protege el endpoint (`401`/`403`) | `WebApplicationFactory` | Depende de la configuración del pipeline, no de la lógica |
| Que el host arranca con la DI completa | `WebApplicationFactory` (un `GET` de humo) | Detecta servicios sin registrar |
| Consultas y migraciones sobre el motor real | Integración con [Testcontainers](Testcontainers.md) | SQLite no sustituye al motor de producción |
| Red, TLS, proxy, despliegue | Smoke test contra el entorno desplegado | Fuera del alcance del host en memoria |

La regla práctica: una regla de negocio no necesita HTTP para probarse; el **contrato HTTP** (lo que un cliente ve) sí. Los tests de API con `WebApplicationFactory` son más lentos que los unitarios (arrancar el host cuesta segundos; cada petición, decenas de milisegundos, frente a los milisegundos de un test unitario), y por eso se reservan para lo que solo ellos pueden detectar.

## Buenas prácticas avanzadas

- **Comprueba el contrato sobre el JSON crudo y el comportamiento sobre el DTO.** Un test que deserializa y compara propiedades no ve que un enum cambie de texto a número. Una aserción sobre el texto (`"\"estado\":\"Confirmado\""`) para el formato, y el DTO para el resto, cubre las dos cosas.
- **Un test del `401` en cada API.** Sin autenticación, un endpoint protegido responde `401`. Ese test avisa si alguien quita `RequireAuthorization()` o relaja la política por defecto; es la alarma de «seguro por defecto».
- **Sustituye lo que cruza el límite del proceso, no lo que hay dentro.** Base de datos, pasarela de pago, correo, reloj y generadores de identificadores se reemplazan; los servicios propios de la aplicación, no. Un test que reemplaza la mitad de la DI ya no prueba la composición real.
- **Usa un reloj y un generador de identificadores falsos.** Sin ellos, las aserciones sobre fechas y GUID se vuelven aproximadas (`Assert.InRange`). Con un `RelojFijo`, la fecha del cuerpo se compara por igualdad.
- **Vigila el coste de los hosts.** Cada factory y cada `WithWebHostBuilder` arrancan una aplicación (segundos). Muchas variantes de configuración multiplican el tiempo de la suite: agrupa los tests que comparten configuración en la misma clase y prefiere cambiar el comportamiento con un doble mutable (`factory.Pasarela.Respuesta = ...`) antes que con una factory derivada por test.
- **Los hosts de prueba conviven con el paralelismo de xUnit.** Cada clase tiene su factory y su base en memoria, y las clases se ejecutan en paralelo. Un recurso global que la API toque (un fichero, un puerto fijo, una variable estática) se comparte entre factories y rompe el aislamiento; la API de la tienda no debe usarlos.

## Documentación oficial

- [Pruebas de integración en ASP.NET Core (Microsoft Learn)](https://learn.microsoft.com/aspnet/core/test/integration-tests) — la guía de referencia: `WebApplicationFactory`, personalización con `ConfigureTestServices`, autenticación simulada y el requisito de la clase `Program` pública; punto de partida para cualquier duda de configuración.
- [Código de `Microsoft.AspNetCore.Mvc.Testing` en el repositorio de ASP.NET Core](https://github.com/dotnet/aspnetcore/tree/main/src/Mvc/Mvc.Testing) — el código de `WebApplicationFactory` y de las tareas de MSBuild que generan el manifiesto de la carpeta de contenido; útil para entender errores de `contentRoot`.
- [Proveedor SQLite de EF Core (Microsoft Learn)](https://learn.microsoft.com/ef/core/providers/sqlite/) — las limitaciones del proveedor frente a SQL Server, para saber qué se puede probar sobre SQLite en memoria.

## Recursos didácticos

- [http.cat](https://http.cat/) — cada código de estado con su gato; útil para el `402`, el `401` y el `404` de los ejemplos.

---

*En resumen: `WebApplicationFactory` arranca tu API real dentro del test, sustituye lo que cruza el límite del proceso (base de datos, pasarela, reloj, autenticación) y la ataca por HTTP en memoria; protege el contrato de la API, pero no sustituye a los tests unitarios ni a un smoke test del despliegue.*
