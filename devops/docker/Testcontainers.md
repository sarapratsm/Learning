# Testcontainers

## ¿Qué es?

Una librería que permite a tus tests arrancar contenedores [Docker](Docker.md) reales —una base de datos, una cola, un caché— desde el propio código de test, y destruirlos al terminar. Existe para .NET, Java, Node, Go, Python y Rust; aquí se usa la versión .NET con [xUnit](../../testing/testing-dotnet/xUnit.md).

## ¿Por qué existe?

Imagina una API de tienda online con un `RepositorioPedidos` que guarda y recupera entidades `Pedido` en PostgreSQL. Quieres probarlo. Tienes dos caminos clásicos y los dos mienten.

**El mock.** Sustituyes `IRepositorioPedidos` por un doble con [NSubstitute](../../testing/testing-dotnet/NSubstitute.md) y le dices que devuelva el pedido #4711 cuando le pidan el 4711. El test pasa. Pero acabas de verificar que tu mock hace lo que le mandaste: nadie ha comprobado que el SQL sea válido, que la columna `total` exista, que el `JOIN` con líneas de pedido no duplique filas, ni que la foreign key impida guardar un pedido de un cliente inexistente. El mock reemplaza justo la pieza que querías probar.

**La base de datos en memoria.** El proveedor `InMemory` de EF Core no es una base de datos, es un diccionario con LINQ encima. No aplica restricciones `UNIQUE` ni `NOT NULL`, no tiene transacciones reales (`BeginTransaction` es un no-op), no entiende SQL y no comparte dialecto con PostgreSQL: `ILIKE`, los tipos `jsonb` y `array`, los índices parciales o la ordenación sensible a *collation* no existen. Un test verde contra `InMemory` y un error en producción son perfectamente compatibles.

Testcontainers ofrece la tercera vía: **un PostgreSQL de verdad, en la versión de producción, vacío, arrancado por el propio test y destruido al acabar**. Sin instalar nada, sin una base compartida donde los tests de dos personas se pisan.

> Un mock es un decorado de cartón con la fachada de una cocina pintada; la base de datos en memoria es una cocina de juguete. Testcontainers monta una cocina real de acero, la usas y la desmontas al salir. Si el plato sale mal, sale mal aquí y no delante del cliente.

## ¿Cuándo y para qué se usa?

| Escenario | ¿Testcontainers? |
|---|---|
| Lógica de dominio pura (cálculo del total de un `Pedido`) | No. Test unitario, sin infraestructura. |
| Consultas y comandos de `RepositorioPedidos` | Sí. Es el caso central. |
| Verificar que las migraciones de esquema se aplican limpias | Sí. Base vacía, migración, comprobación. |
| Endpoint completo de la API (HTTP → repositorio → BD) | Sí, combinado con `WebApplicationFactory`. |
| Un consumidor que lee de RabbitMQ o escribe en Redis | Sí, hay módulo para cada uno. |
| Validaciones de un DTO | No. |

La regla es simple: si el código que pruebas **habla con infraestructura**, esa infraestructura debe ser real. Si no, un test unitario es más rápido y suficiente. Ver [Tipos de tests](../../testing/testing-dotnet/Tipos-de-tests.md) para situar cada capa.

## Cómo funciona por dentro

Cuando un test pide un contenedor, Testcontainers habla con el demonio de Docker local y hace tres cosas: **descarga la imagen** si no está en caché y arranca un contenedor desechable con nombre generado; **publica el puerto interno en un puerto aleatorio libre del host** (PostgreSQL sigue escuchando en su 5432, pero desde fuera se llega por, digamos, el 54327, para que dos suites en paralelo no colisionen — por eso **nunca escribes la cadena de conexión a mano**, se la pides al contenedor); y **lo registra ante Ryuk**, el recolector de basura que se explica más abajo. Al terminar, contenedor y volumen anónimo desaparecen.

## El primer test completo

Instala el módulo de PostgreSQL (`dotnet add package Testcontainers.PostgreSql`), que ya trae imagen, usuario, contraseña y estrategia de espera preconfigurados. Y este es el test entero, ejecutable tal cual:

```csharp
using Testcontainers.PostgreSql;
using Xunit;

public class RepositorioPedidosTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres =
        new PostgreSqlBuilder().WithImage("postgres:16-alpine").Build();

    private RepositorioPedidos _repositorio = null!;

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();                    // descarga, arranca y espera
        _repositorio = new RepositorioPedidos(_postgres.GetConnectionString());
        await _repositorio.AplicarEsquemaAsync();        // la BD nace vacía: hay que crear tablas
    }

    public Task DisposeAsync() => _postgres.DisposeAsync().AsTask();

    [Fact]
    public async Task Guardar_PersisteElPedidoYLoRecupera()
    {
        await _repositorio.GuardarAsync(new Pedido { Id = 4711, Cliente = "ACME", Total = 129.90m });
        var recuperado = await _repositorio.ObtenerPorIdAsync(4711);

        Assert.Equal(129.90m, recuperado!.Total);
    }
}
```

Qué hace cada pieza:

- `IAsyncLifetime` es la interfaz de xUnit para *setup* y *teardown* asíncronos: `InitializeAsync` corre antes de los tests de la clase, `DisposeAsync` después, pase lo que pase (incluso si un test falla). Detalle en [Fixtures y ciclo de vida](../../testing/testing-dotnet/Fixtures-y-ciclo-de-vida.md).
- `StartAsync()` bloquea hasta que PostgreSQL **acepta conexiones**, no solo hasta que el contenedor existe.
- `GetConnectionString()` devuelve algo como `Host=localhost;Port=54327;Database=postgres;Username=postgres;Password=postgres`, con el puerto real de esta ejecución.
- El esquema es cosa tuya: la base nace vacía. Aplica tus [migraciones](../../bases-de-datos/migraciones-de-esquema/EF-Core-Migrations.md) o un script DDL.

Ejecuta y verás el coste:

```
Passed!  - Failed: 0, Passed: 1, Skipped: 0, Total: 1, Duration: 4 s
```

Cuatro segundos para un `Assert.Equal`. Ahí está el problema siguiente.

## El coste: un contenedor por clase es inviable

Con el código anterior, **cada clase de tests arranca su propio PostgreSQL**. Veinte clases son veinte arranques:

| Estrategia | 20 clases × 5 tests | Aislamiento |
|---|---|---|
| Un contenedor por test | ~7 min | Perfecto y carísimo |
| Un contenedor por clase | ~90 s | Bueno, aún caro |
| Un contenedor compartido | ~10 s | Hay que limpiar entre tests |

El patrón correcto en xUnit es **`ICollectionFixture`**: una instancia compartida por todas las clases de una colección. Dos piezas.

**1. El fixture, que posee el contenedor, más la clase vacía que da nombre a la colección:**

```csharp
public class PostgresFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres =
        new PostgreSqlBuilder().WithImage("postgres:16-alpine").Build();

    public string CadenaConexion => _postgres.GetConnectionString();

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();
        await new RepositorioPedidos(CadenaConexion).AplicarEsquemaAsync();
    }

    public Task DisposeAsync() => _postgres.DisposeAsync().AsTask();
}

[CollectionDefinition("postgres")]
public class PostgresCollection : ICollectionFixture<PostgresFixture> { }
```

**2. Cada clase de tests se apunta a la colección y recibe el fixture por constructor:**

```csharp
[Collection("postgres")]
public class RepositorioPedidosTests(PostgresFixture fixture)
{
    private readonly RepositorioPedidos _repositorio = new(fixture.CadenaConexion);

    [Fact]
    public async Task Guardar_PersisteElPedido()
    {
        await _repositorio.GuardarAsync(new Pedido { Id = 4711, Total = 129.90m });
        Assert.Equal(129.90m, (await _repositorio.ObtenerPorIdAsync(4711))!.Total);
    }
}
```

xUnit crea `PostgresFixture` una sola vez, lo pasa a todas las clases marcadas con `[Collection("postgres")]` y lo destruye al final. Como efecto secundario, xUnit **ejecuta en serie** las clases de una misma colección, lo que evita que dos tests escriban a la vez en la misma tabla.

## Aislamiento entre tests que comparten contenedor

Compartir contenedor reintroduce el problema que Testcontainers venía a resolver: el pedido #4711 que insertó un test sigue ahí cuando corre el siguiente. Tres formas de limpiar, de menos a más aislamiento:

**Truncado entre tests.** Vaciar las tablas antes de cada test. A mano es frágil (el orden importa por las foreign keys), así que se usa **Respawn**, que inspecciona el esquema y genera el `TRUNCATE ... CASCADE` correcto:

```csharp
var conexion = new NpgsqlConnection(_fixture.CadenaConexion);
await conexion.OpenAsync();
var respawner = await Respawner.CreateAsync(conexion,
    new RespawnerOptions { DbAdapter = DbAdapter.Postgres });
await respawner.ResetAsync(conexion);   // ~5 ms, borra filas y deja el esquema intacto
```

Rápido y sencillo. Borra también los datos de referencia, así que hay que resembrarlos (Respawn admite `TablesToIgnore`).

**Transacción con rollback.** Abrir una transacción al empezar el test y deshacerla al terminar:

```csharp
await using var tx = await conexion.BeginTransactionAsync();
await _repositorio.GuardarAsync(new Pedido { Id = 4711 });
// sin Commit: al salir del using todo desaparece
```

Lo más rápido de todo (no toca disco), pero **el código bajo prueba tiene que usar esa misma conexión y transacción**. Si `RepositorioPedidos` abre la suya, no ve nada, y no sirve para probar código que hace `COMMIT` explícito.

**Una base de datos por test.** `CREATE DATABASE pedidos_test_4711` dentro del mismo contenedor. Aislamiento total y paralelismo real, a cambio de unos cientos de milisegundos por test más aplicar el esquema.

| Opción | Coste | Aislamiento | Permite paralelizar |
|---|---|---|---|
| Respawn (truncate) | ~5 ms | Alto | No dentro de la colección |
| Transacción + rollback | ~1 ms | Alto | Sí |
| BD por test | ~200 ms | Total | Sí |

Para la mayoría de suites, **Respawn es el equilibrio correcto**: barato, no impone nada al código de producción y sobrevive a cualquier cosa que haga el repositorio.

## Esperar a que el servicio esté listo

Que Docker diga `running` no significa que el servicio dentro acepte peticiones: PostgreSQL tarda uno o dos segundos más en abrir el socket. Si conectas antes, obtienes `connection refused` de forma intermitente — la causa número uno de tests que fallan uno de cada diez.

Los módulos oficiales (`PostgreSqlBuilder`, `RedisBuilder`...) ya traen la espera correcta. El problema aparece al usar `ContainerBuilder` genérico con una imagen propia, donde Testcontainers solo espera al arranque del proceso. Declara la condición real:

```csharp
var pasarelaPagos = new ContainerBuilder()
    .WithImage("mi-pasarela-pagos:1.2")
    .WithPortBinding(8080, assignRandomHostPort: true)
    .WithWaitStrategy(Wait.ForUnixContainer()
        .UntilHttpRequestIsSucceeded(r => r.ForPath("/health").ForPort(8080)))
    .Build();
```

`UntilHttpRequestIsSucceeded` reintenta contra `/health` hasta recibir un 2xx. Las otras estrategias habituales son `UntilMessageIsLogged("ready to accept connections")`, que espera a una línea concreta en los logs, y `UntilPortIsAvailable(5432)`, la más débil (el puerto puede estar abierto antes de que el servicio responda).

## Más allá de PostgreSQL

El catálogo tiene un módulo por tecnología, todos con la misma forma: `XBuilder` → `StartAsync` → un método que da la cadena de conexión.

| Paquete | Clase | Cómo se conecta |
|---|---|---|
| `Testcontainers.PostgreSql` | `PostgreSqlContainer` | `GetConnectionString()` |
| `Testcontainers.Redis` | `RedisContainer` | `GetConnectionString()` |
| `Testcontainers.RabbitMq` | `RabbitMqContainer` | `GetConnectionString()` (URI `amqp://`) |
| `Testcontainers.MongoDb` | `MongoDbContainer` | `GetConnectionString()` |
| `Testcontainers.Azurite` | `AzuriteContainer` | `GetConnectionString()` (Azure Storage emulado) |

Un caché de pedidos contra Redis real, por ejemplo:

```csharp
private readonly RedisContainer _redis = new RedisBuilder().WithImage("redis:7-alpine").Build();

[Fact]
public async Task Cache_DevuelveElPedidoGuardado()
{
    var cache = ConnectionMultiplexer.Connect(_redis.GetConnectionString()).GetDatabase();
    await cache.StringSetAsync("pedido:4711", "129.90", TimeSpan.FromMinutes(5));

    Assert.Equal("129.90", await cache.StringGetAsync("pedido:4711"));  // TTL real, no un diccionario
}
```

## La API completa: junto a `WebApplicationFactory`

Hasta ahora se ha probado el repositorio aislado. Para probar el endpoint `GET /pedidos/4711` de punta a punta hace falta levantar la aplicación y **sustituir su cadena de conexión por la del contenedor**. Eso lo hace [`WebApplicationFactory`](../../testing/testing-dotnet/WebApplicationFactory.md):

```csharp
public class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres =
        new PostgreSqlBuilder().WithImage("postgres:16-alpine").Build();

    protected override void ConfigureWebHost(IWebHostBuilder builder) =>
        builder.UseSetting("ConnectionStrings:Pedidos", _postgres.GetConnectionString());

    public async Task InitializeAsync() => await _postgres.StartAsync();
    public new Task DisposeAsync() => _postgres.DisposeAsync().AsTask();
}

[Collection("api")]
public class PedidosEndpointTests(ApiFactory factory)
{
    [Fact]
    public async Task Get_DevuelveElPedido()
    {
        var respuesta = await factory.CreateClient().GetAsync("/pedidos/4711");
        Assert.Equal(HttpStatusCode.OK, respuesta.StatusCode);   // 200 OK, contra PostgreSQL real
    }
}
```

El test pide por HTTP sin saber que hay un contenedor debajo. Ojo con el orden: `ConfigureWebHost` se ejecuta cuando se crea el primer `HttpClient`, que es **después** de `InitializeAsync`. Si inviertes ese orden, `GetConnectionString()` lanza porque el contenedor aún no tiene puerto asignado.

## Ejecutar en CI

**1. Docker tiene que estar disponible en el runner.** Los runners `ubuntu-latest` de GitHub Actions lo traen instalado y arrancado, así que un job normal con `actions/setup-dotnet` y `dotnet test` funciona sin configuración extra. En runners autoalojados o en agentes que ya corren dentro de un contenedor, hay que montar el socket (`/var/run/docker.sock`) o usar Docker-in-Docker. Ver [CI/CD](../ci-cd/README.md) y [Docker en CI/CD](../ci-cd/Docker-en-CI-CD.md).

**2. Caché de imágenes.** Cada job descarga `postgres:16-alpine` desde cero. Fijar una versión concreta y republicar la imagen en tu propio [registro](GitHub-Container-Registry.md) evita depender del límite de descargas de Docker Hub.

**Ryuk, el basurero.** Al arrancar el primer contenedor, Testcontainers levanta también `testcontainers/ryuk`, que monta el socket de Docker y vigila la sesión de tests. Si el proceso muere sin llamar a `DisposeAsync` —un `Ctrl+C`, un runner cancelado, un fallo del proceso—, Ryuk detecta que la sesión ha desaparecido y elimina los contenedores, redes y volúmenes huérfanos. Es lo que impide que un CI acumule PostgreSQLs zombis hasta llenar el disco. Se desactiva con `TESTCONTAINERS_RYUK_DISABLED=true`, y hacerlo casi nunca es buena idea: solo en entornos donde montar el socket está prohibido, y asumiendo la limpieza tú.

## Errores frecuentes

| Síntoma | Causa probable | Solución |
|---|---|---|
| `Docker is either not running or misconfigured` | El demonio no está arrancado, o el usuario no está en el grupo `docker` | Arrancar Docker Desktop; en Linux, `usermod -aG docker $USER` y reabrir sesión |
| `connection refused` en uno de cada N tests | Falta *wait strategy*: se conecta antes de que el servicio esté listo | `WithWaitStrategy(...)` con una condición real (`/health`, log, `pg_isready`) |
| `port is already allocated` | Se fijó un puerto de host con `WithPortBinding(5432, 5432)` | Dejar que Testcontainers asigne puerto aleatorio y usar `GetConnectionString()` |
| La suite tarda minutos | Un contenedor por clase de test | `ICollectionFixture` + limpieza con Respawn |
| Contenedores vivos tras `Ctrl+C` | Ryuk desactivado o el proceso murió sin él | Reactivar Ryuk; limpiar con `docker ps -a --filter label=org.testcontainers=true` |
| El test ve datos de otro test | Contenedor compartido sin limpieza entre tests | Respawn, transacción con rollback o BD por test |
| `relation "pedidos" does not exist` | La BD nace vacía y no se aplicó el esquema | Ejecutar migraciones en `InitializeAsync` del fixture |

## Buenas prácticas avanzadas

- **Fija la versión de la imagen y que sea la de producción.** `WithImage("postgres:16-alpine")`, nunca `postgres:latest`. Toda la propuesta de valor de Testcontainers es probar contra el motor real; si el test corre sobre la 17 y producción va por la 15, has cambiado un doble por otro. Cuando actualices producción, el cambio de esa línea es el que te dice si algo se rompe.
- **Activa `WithReuse(true)` solo en local.** Con `new PostgreSqlBuilder().WithReuse(true)`, el contenedor sobrevive al final de la suite y la siguiente ejecución lo reaprovecha: en el ciclo "toco código, lanzo tests" ahorra segundos cada vez. Es una función experimental: desactiva Ryuk para ese recurso y deja el contenedor parado, no borrado, al terminar. La propiedad `testcontainers.reuse.enable=true` en `~/.testcontainers.properties` no hizo falta con la 4.16.0 (comprobado el 2026-11-10, sin ese fichero). En CI no aporta nada (el runner es efímero) y arrastra estado entre ejecuciones, que es justo lo que no quieres al validar un *pull request*.
- **Aplica el esquema una vez, en el fixture, no en cada test.** Correr las migraciones por test convierte 5 ms de truncado en 500 ms de DDL. El fixture crea el esquema al arrancar; cada test solo limpia filas. Y si la migración falla, falla una vez y con un mensaje claro, en lugar de ensuciar el informe con cincuenta tests rojos idénticos.
- **No pongas todos los tests en la misma colección por defecto.** xUnit serializa las clases de una colección, así que una única colección gigante mata el paralelismo de toda la suite. Agrupa por recurso compartido: una colección para los tests de PostgreSQL, otra para los de Redis; correrán en paralelo entre sí.
- **Etiqueta los contenedores con el commit o el nombre del job en CI.** `WithLabel("ci-run", Environment.GetEnvironmentVariable("GITHUB_RUN_ID"))` no cambia nada en el test, pero cuando un runner se quede sin disco te permite ver de qué ejecución venían los contenedores colgados en lugar de mirar una lista de identificadores anónimos.

## Recursos didácticos

- [Documentación oficial de Testcontainers for .NET](https://dotnet.testcontainers.org/) — la referencia de la API: builders, *wait strategies*, redes y variables de entorno, con las firmas exactas de la versión que tengas instalada.
- [Catálogo de módulos](https://testcontainers.com/modules/) — busca la tecnología que necesitas (Kafka, Elasticsearch, LocalStack, Keycloak...) y te da el paquete y el fragmento de arranque. Evita escribir a mano un `ContainerBuilder` genérico cuando ya existe módulo.
- [Respawn](https://github.com/jbogard/Respawn) — el complemento natural: el README explica cómo detecta el grafo de foreign keys y qué opciones hay para preservar tablas de datos maestros entre tests.

---

*En resumen: Testcontainers cambia "para probar el repositorio necesito una base de datos" por tres líneas de código; lo que separa una suite útil de una suite lenta es compartir un contenedor por colección y limpiar los datos entre tests en lugar de arrancar uno nuevo cada vez.*
