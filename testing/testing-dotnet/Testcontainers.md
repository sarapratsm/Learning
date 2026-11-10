# Testcontainers

## ¿Qué es?

Testcontainers es una librería que arranca **contenedores Docker efímeros desde el propio test**: un PostgreSQL real que nace antes de los tests y se destruye al terminar. En .NET se instala por módulos; `Testcontainers.PostgreSql` trae la base de datos ya configurada (imagen, usuario, contraseña y comprobación de que acepta conexiones).

## ¿Por qué existe?

Los tests que necesitan una base de datos tenían dos malas salidas. Una era un sustituto en memoria (el proveedor `InMemory` de EF Core o SQLite): rápido, pero no es PostgreSQL, así que lo que pasa en verde puede fallar en producción. La otra era un PostgreSQL instalado en la máquina o compartido: real, pero los tests de dos personas se pisan y «en mi máquina funciona». Testcontainers da la tercera vía: **un PostgreSQL real, de la versión de producción, privado y desechable**, creado por la propia suite en un puerto aleatorio.

> Es el `docker run postgres` que harías a mano para probar algo, pero automatizado, con puerto libre elegido por la librería y con limpieza garantizada al terminar.

La parte de Docker (cómo funciona por dentro, CI, otros módulos como Redis o RabbitMQ) está en [Testcontainers en Docker](../../devops/docker/Testcontainers.md). Desde xUnit y EF Core, lo que hace falta es una fixture, las migraciones aplicadas, aislamiento entre tests y control de los tiempos.

## ¿Cuándo y para qué se usa?

| Qué se prueba | ¿Testcontainers? |
|---|---|
| Reglas de dominio puras (un pedido sin líneas no se confirma) | No: test unitario, sin infraestructura |
| Consultas y escrituras de EF Core o Dapper contra PostgreSQL | Sí: es el caso central |
| Restricciones del esquema (índices únicos, claves foráneas, `NOT NULL`) | Sí: viven en la base de datos, un mock no las prueba |
| Que las migraciones se aplican sobre una base vacía | Sí |
| Un endpoint completo (HTTP, EF Core, fila en disco) | Sí, junto a `WebApplicationFactory` |
| Mapeo sencillo sin SQL específico del motor | Opcional: SQLite en memoria basta y arranca antes |

Requisito único: un Docker en marcha en la máquina de desarrollo y en el runner de CI. Dónde encaja cada capa de test, en [Tipos de tests](Tipos-de-tests.md).

## Lo que un sustituto en memoria no detecta

La razón práctica de usar un PostgreSQL real es que los sustitutos se comportan distinto. Un ejemplo ejecutado: buscar pedidos por el texto del cliente con `EF.Functions.Like`. En PostgreSQL, `LIKE` distingue mayúsculas; en SQLite, no (para letras ASCII). Con un pedido #4711 del cliente `ACME S.L.`, el mismo test:

```csharp
var encontrados = await contexto.Pedidos
    .Where(p => EF.Functions.Like(p.Cliente, "%acme%"))
    .CountAsync();

Assert.Equal(0, encontrados);   // PostgreSQL: «acme» no es «ACME»
```

Contra PostgreSQL (contenedor) pasa; contra SQLite en memoria falla, porque devuelve 1 fila:

```text
  Failed Tienda.Tests.PedidoSqliteTests.Buscar_ConLikeEnMinusculas_ContraSqlite [1 s]
  Error Message:
   Assert.Equal() Failure: Values differ
Expected: 0
Actual:   1
```

Un test verde contra SQLite habría dejado pasar una búsqueda que en producción no encuentra nada. Dos matices comprobados con el mismo pedido:

- `Contains("acme")` de LINQ **no** reproduce la diferencia: ejecutado contra SQLite también devolvió 0 (el proveedor de SQLite de EF Core lo traduce de forma que distingue mayúsculas; no se inspeccionó el SQL generado). La divergencia aparece con `EF.Functions.Like` o con SQL escrito a mano.
- Un índice único **parcial** (`WHERE "Estado" = 'Borrador'`) sí lo detecta SQLite: lanza `SQLite Error 19: 'UNIQUE constraint failed: Pedidos.Cliente'`. La excepción es otra (`SqliteException` frente a `PostgresException`), y solo la de PostgreSQL permite comprobar el código `SqlState`. Los tipos propios de PostgreSQL (`jsonb`, arrays, extensiones) no existen en SQLite; no se ejecutó ninguna prueba con ellos.

## Primer contenedor

El paquete se instala en el proyecto de pruebas:

```bash
dotnet add tests/Tienda.Tests package Testcontainers.PostgreSql
```

La versión actual es la 4.16.0 (publicada el 2026-10-09, comprobada en NuGet y en las versiones del repositorio de GitHub el 2026-11-10). El patrón básico es un `PostgreSqlBuilder` con la imagen fijada y el ciclo de vida asíncrono de xUnit, `IAsyncLifetime`: `InitializeAsync` se ejecuta antes de los tests de la clase y `DisposeAsync` después, aunque un test falle (detalle en [Fixtures y ciclo de vida](Fixtures-y-ciclo-de-vida.md)):

```csharp
public class PrimerContenedorTests(ITestOutputHelper salida) : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres =
        new PostgreSqlBuilder("postgres:16-alpine").Build();

    public Task InitializeAsync() => _postgres.StartAsync();      // arranca y espera a que acepte conexiones
    public Task DisposeAsync() => _postgres.DisposeAsync().AsTask();

    [Fact]
    public async Task PostgreSql_ResponderALaConsulta()
    {
        salida.WriteLine(_postgres.GetConnectionString());
        await using var conexion = new NpgsqlConnection(_postgres.GetConnectionString());
        await conexion.OpenAsync();
        await using var comando = new NpgsqlCommand("SELECT version()", conexion);

        var version = (string?)await comando.ExecuteScalarAsync();

        salida.WriteLine(version);
        Assert.StartsWith("PostgreSQL 16", version);
    }
}
```

`StartAsync` descarga la imagen si falta, arranca el contenedor y espera hasta que PostgreSQL acepta conexiones (comprueba con `pg_isready`). `GetConnectionString()` devuelve la cadena con el puerto aleatorio de esa ejecución; con `dotnet test --logger "console;verbosity=detailed"` la salida fue:

```text
Host=127.0.0.1;Port=58931;Database=postgres;Username=postgres;Password=postgres
PostgreSQL 16.14 on x86_64-pc-linux-musl, compiled by gcc (Alpine 15.2.0) 15.2.0, 64-bit
```

El puerto cambia en cada ejecución: la cadena de conexión no se escribe a mano, se pide siempre al contenedor. La etiqueta de la imagen (`16-alpine`) debe coincidir con la versión de producción: probar contra «la última» es probar otro motor.

Con el nivel de registro `normal`, Testcontainers imprime su propio recorrido; el arranque de la primera ejecución incluye dos contenedores, el primero es el de Ryuk (explicado más abajo) y el segundo el de PostgreSQL:

```text
[testcontainers.org 00:00:00.34] Connected to Docker:
  Host: npipe://./pipe/docker_engine
  Server Version: 29.5.3
...
[testcontainers.org 00:00:00.75] Docker container b2b2a80cb1c3 created
[testcontainers.org 00:00:02.38] Docker container b2b2a80cb1c3 ready
[testcontainers.org 00:00:02.60] Docker container 30479897cd04 created
[testcontainers.org 00:00:02.98] Execute "pg_isready --host localhost --dbname postgres --username postgres" at Docker container 30479897cd04
[testcontainers.org 00:00:05.36] Docker container 30479897cd04 ready
[testcontainers.org 00:00:08.29] Delete Docker container 30479897cd04
```

## El modelo de ejemplo: EF Core, migraciones y un índice parcial

Los ejemplos siguientes comparten un esquema pequeño de la tienda. La entidad `Pedido` (la de [xUnit](xUnit.md), con un campo más, `Cliente`) se mapea con EF Core 10 y Npgsql (`Npgsql.EntityFrameworkCore.PostgreSQL` 10.0.3 en la comprobación). Una regla vive solo en el esquema: **un cliente solo puede tener un pedido en borrador a la vez**, expresada como un índice único parcial.

```csharp
public class TiendaDbContext(DbContextOptions<TiendaDbContext> options) : DbContext(options)
{
    public DbSet<Pedido> Pedidos => Set<Pedido>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Pedido>(pedido =>
        {
            pedido.HasKey(p => p.Numero);
            pedido.Property(p => p.Numero).ValueGeneratedNever();
            pedido.Property(p => p.Estado).HasConversion<string>();
            pedido.OwnsMany(p => p.Lineas, linea =>
            {
                linea.WithOwner().HasForeignKey("PedidoNumero");
                linea.Property<int>("Id");
                linea.HasKey("Id");
                linea.Ignore(l => l.Subtotal);
            });

            pedido.HasIndex(p => p.Cliente)
                .IsUnique()
                .HasFilter("\"Estado\" = 'Borrador'");   // solo cuenta entre los borradores
        });
    }
}
```

Las migraciones se generan como siempre (`dotnet ef migrations add Inicial`); el proyecto de datos necesita `Microsoft.EntityFrameworkCore.Design`. El funcionamiento de las migraciones se explica en [Entity Framework Core](../../bases-de-datos/acceso-a-datos-dotnet/Entity-Framework-Core.md).

## La fixture: un contenedor para todos los tests

Arrancar un contenedor cuesta segundos (mediciones más abajo), así que se crea una vez y se comparte. La fixture es una clase que posee el contenedor, aplica las migraciones y expone la cadena de conexión:

```csharp
public class PostgresFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres =
        new PostgreSqlBuilder("postgres:16-alpine").Build();

    private Respawner _respawner = null!;

    public string CadenaConexion => _postgres.GetConnectionString();

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();

        await using var contexto = CrearContexto();
        await contexto.Database.MigrateAsync();          // el esquema real, aplicado por las migraciones

        await using var conexion = new NpgsqlConnection(CadenaConexion);
        await conexion.OpenAsync();
        _respawner = await Respawner.CreateAsync(conexion, new RespawnerOptions
        {
            DbAdapter = DbAdapter.Postgres,
            SchemasToInclude = ["public"],
            TablesToIgnore = [new Table("__EFMigrationsHistory")],
        });
    }

    public TiendaDbContext CrearContexto() =>
        new(new DbContextOptionsBuilder<TiendaDbContext>().UseNpgsql(CadenaConexion).Options);

    public async Task ReiniciarDatosAsync()
    {
        await using var conexion = new NpgsqlConnection(CadenaConexion);
        await conexion.OpenAsync();
        await _respawner.ResetAsync(conexion);
    }

    public Task DisposeAsync() => _postgres.DisposeAsync().AsTask();
}

[CollectionDefinition("postgres")]
public class PostgresCollection : ICollectionFixture<PostgresFixture>;
```

`Respawner` (se explica en la sección siguiente) se incluye aquí porque se crea una vez, justo después de las migraciones. `ICollectionFixture<PostgresFixture>` hace que xUnit cree **una sola instancia** de la fixture para todas las clases de la colección `postgres`, y la destruya cuando acabe la última. Cada clase de tests se apunta con `[Collection("postgres")]` y recibe la fixture por constructor. Con una clase única bastaría `IClassFixture<PostgresFixture>`; la colección sirve para repartir el contenedor entre varias clases. Una consecuencia: xUnit ejecuta **en serie** las clases de una misma colección, que es justo lo que se quiere cuando todas comparten tablas.

Aplicar las migraciones en la fixture (y no en cada test) tiene un efecto adicional: si una migración falla, falla una vez y con su propio mensaje, no en cincuenta tests rojos idénticos.

## Un test de integración contra el esquema real

Con la fixture, un test de la regla del índice parcial, de principio a fin:

```csharp
[Collection("postgres")]
public class PedidoPostgresTests(PostgresFixture fixture) : IAsyncLifetime
{
    public Task InitializeAsync() => fixture.ReiniciarDatosAsync();   // antes de cada test
    public Task DisposeAsync() => Task.CompletedTask;

    [Fact]
    public async Task DosBorradoresDelMismoCliente_ViolanElIndiceUnicoParcial()
    {
        await using var contexto = fixture.CrearContexto();
        contexto.Pedidos.Add(new Pedido(4711, "ACME S.L."));
        contexto.Pedidos.Add(new Pedido(4712, "ACME S.L."));

        var ex = await Assert.ThrowsAsync<DbUpdateException>(() => contexto.SaveChangesAsync());

        var pg = Assert.IsType<PostgresException>(ex.InnerException);
        Assert.Equal("23505", pg.SqlState);   // unique_violation
        Assert.Equal("IX_Pedidos_Cliente", pg.ConstraintName);
    }

    [Fact]
    public async Task UnBorradorYUnConfirmadoDelMismoCliente_ConviviSinProblema()
    {
        await using var contexto = fixture.CrearContexto();
        var confirmado = new Pedido(4710, "ACME S.L.");
        confirmado.AgregarLinea("CAM-001", 1, 10m);
        confirmado.Confirmar();
        contexto.Pedidos.AddRange(confirmado, new Pedido(4711, "ACME S.L."));

        await contexto.SaveChangesAsync();

        Assert.Equal(2, await contexto.Pedidos.CountAsync());
    }
}
```

El primer test comprueba la restricción por el `SqlState` `23505` y el nombre del índice; el segundo comprueba el lado contrario (que la regla no sea más estricta de lo debido, porque el filtro del índice solo afecta a los borradores). Los dos pasan:

```text
  Passed Tienda.Tests.PedidoPostgresTests.DosBorradoresDelMismoCliente_ViolanElIndiceUnicoParcial [39 ms]
  Passed Tienda.Tests.PedidoPostgresTests.UnBorradorYUnConfirmadoDelMismoCliente_ConviviSinProblema [27 ms]
```

Los códigos `SqlState` son estables entre versiones y entre idiomas del servidor; los mensajes de error, no. Se aserta sobre el código y la restricción, no sobre el texto.

## Aislamiento entre tests

El contenedor es el mismo para todos los tests de la colección, así que lo que un test inserta lo ve el siguiente. Un ejemplo real: dos tests que insertan el pedido #4711 sin limpieza entre medias. El segundo falla:

```text
  Microsoft.EntityFrameworkCore.DbUpdateException : An error occurred while saving the entity changes. See the inner exception for details.
  ---- Npgsql.PostgresException : 23505: duplicate key value violates unique constraint "PK_Pedidos"
```

Es el fallo típico de «pasa solo, falla en la suite». Hay cuatro formas de evitarlo.

### Respawn: borrar las filas antes de cada test

[Respawn](https://github.com/jbogard/Respawn) inspecciona el esquema, calcula el orden correcto de borrado según las claves foráneas y genera el SQL de vaciado. Se configura una vez (en la fixture de arriba) y se llama antes de cada test, que es lo que hace `InitializeAsync` de `PedidoPostgresTests`. Comprobado el 2026-11-10: la versión actual es la 7.0.0, con licencia Apache-2.0, el repositorio no está archivado y su último *push* es del 2026-01-19.

**Hay que excluir la tabla del historial de migraciones.** Con el adaptador de PostgreSQL y sin `TablesToIgnore`, Respawn también vacía `__EFMigrationsHistory`. Un test que lo comprueba (inserta un pedido, reinicia y consulta las migraciones aplicadas) falla así:

```text
  Failed Tienda.Tests.AislamientoTests.Respawn_VaciaLasTablasPeroConservaElHistorialDeMigraciones
  Error Message:
   Assert.Single() Failure: The collection was empty
```

Con `TablesToIgnore = [new Table("__EFMigrationsHistory")]` (la configuración mostrada en la fixture) el test pasa. Sin esa exclusión, EF Core creería que la base de datos no tiene migraciones aplicadas.

### Transacción sin confirmar

El test abre una transacción, hace lo que necesita y no llama a `Commit`: al cerrar la conexión, PostgreSQL deshace todo.

```csharp
[Fact]
public async Task TransaccionSinCommit_NoDejaRastro()
{
    await using (var contexto = fixture.CrearContexto())
    {
        await using var tx = await contexto.Database.BeginTransactionAsync();
        contexto.Pedidos.Add(new Pedido(4711, "ACME S.L."));
        await contexto.SaveChangesAsync();
        Assert.Equal(1, await contexto.Pedidos.CountAsync());   // dentro de la transacción se ve
    }                                                           // sin Commit: rollback al salir

    await using var lectura = fixture.CrearContexto();
    Assert.Equal(0, await lectura.Pedidos.CountAsync());
}
```

Es la opción más barata, pero el código bajo prueba tiene que usar **esa misma conexión y transacción**. Un repositorio que abre su propio `DbContext` no ve nada de lo insertado, y no sirve para probar código que hace `COMMIT` por su cuenta o que depende del comportamiento de transacciones concurrentes.

### Qué elegir

| Estrategia | Cuándo encaja | Coste medido o esperado |
|---|---|---|
| Respawn antes de cada test | Caso general: el código bajo prueba abre sus propias conexiones | 6 a 13 ms por test en la medición (incluye reinicio, escritura y lectura) |
| Truncar tablas a mano (`TRUNCATE ... CASCADE`) | Pocas tablas y sin ganas de otra dependencia | No medido; el orden de las claves foráneas lo mantienes tú |
| Transacción sin `Commit` | Código que recibe la conexión o el `DbContext` y no hace `COMMIT` | No medido por separado; se hace sin sentencias de borrado |
| Base de datos por test (`CREATE DATABASE` dentro del mismo contenedor) | Tests en paralelo sin colección compartida | No medido; cada base exige aplicar el esquema |
| Contenedor por test | Aislamiento total, pocas pruebas | Medido: unos 3 s por test (siguiente sección) |

Respawn es el equilibrio habitual: no exige nada al código de producción ni a cómo abre las conexiones.

## Tiempos medidos

Medido en una máquina con Windows 11, Docker Desktop 29.5.3 y la imagen `postgres:16-alpine` ya descargada, ejecutado el 2026-11-10 con `dotnet test --logger "console;verbosity=detailed"`. No se midió la descarga de la imagen (con la imagen ausente el primer arranque paga la descarga).

| Medida | Resultado |
|---|---|
| `StartAsync` del primer contenedor del proceso (incluye conectar con Docker y arrancar Ryuk) | 6,7 s |
| `StartAsync` de los contenedores siguientes en el mismo proceso | 2,8 a 3,0 s |
| Aplicar la migración inicial (primer contexto del proceso, con calentamiento de EF Core) | 1,9 s |
| Aplicar la migración inicial (siguientes contenedores) | 0,1 s |
| 10 tests, un contenedor nuevo con migraciones por test | 42,3 s en total |
| 10 tests, un contenedor compartido (fixture) y Respawn antes de cada test | 12,7 s en total |
| Cada test con el contenedor compartido (reinicio, escritura y lectura) | 6 a 13 ms |

Los totales incluyen el arranque del proceso de pruebas y el del propio contenedor; con más tests, el contenedor compartido sigue pagando un único arranque y cada test añade unos milisegundos, mientras el contenedor por test añade unos 3 s por cada uno. Con 10 tests la diferencia ya es de 30 s; con 200, la de un contenedor por test sería de unos 10 minutos (extrapolación, no medida).

La ejecución completa de la suite del ejemplo (29 tests en esa ejecución, entre ellos los 10 con contenedor por test) tardó 1,15 minutos.

### Reutilizar el contenedor entre ejecuciones

`WithReuse(true)` hace que Testcontainers etiquete el contenedor con un hash de su configuración y, en la ejecución siguiente, reutilice el existente en lugar de crear otro. Según la documentación del propio método es una función **experimental** y **desactiva el recolector Ryuk para ese recurso**: el contenedor no se limpia al terminar. Comprobado con Testcontainers 4.16.0: dos ejecuciones seguidas con `new PostgreSqlBuilder("postgres:16-alpine").WithReuse(true)` usaron el mismo contenedor (mismo identificador) y el arranque bajó de 3,8 s a 1,9 s; entre ejecuciones el contenedor queda parado (`Exited`) y **no se elimina**, hay que borrarlo a mano (`docker rm -f <id>`). En esa máquina no existía ningún `~/.testcontainers.properties` y la reutilización funcionó igualmente. Sirve para el ciclo de desarrollo local; en CI no aporta nada y arrastra estado entre ejecuciones.

## Combinarlo con `WebApplicationFactory`

Para probar un endpoint completo, la API se arranca apuntando al contenedor. La factory recibe la fixture y pasa su cadena de conexión como configuración, que [WebApplicationFactory](WebApplicationFactory.md) describe con detalle:

```csharp
public class TiendaApiFactory(PostgresFixture fixture) : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder) =>
        builder.UseSetting("ConnectionStrings:Tienda", fixture.CadenaConexion);
}

[Collection("postgres")]
public class ApiConPostgresTests(PostgresFixture fixture) : IAsyncLifetime
{
    public Task InitializeAsync() => fixture.ReiniciarDatosAsync();
    public Task DisposeAsync() => Task.CompletedTask;

    [Fact]
    public async Task GetPedido_Existente_Devuelve200ConElPedido()
    {
        await using (var contexto = fixture.CrearContexto())
        {
            var pedido = new Pedido(4711, "ACME S.L.");
            pedido.AgregarLinea("CAM-001", 2, 19.99m);
            contexto.Pedidos.Add(pedido);
            await contexto.SaveChangesAsync();
        }
        await using var factory = new TiendaApiFactory(fixture);
        using var cliente = factory.CreateClient();

        var respuesta = await cliente.GetAsync("/pedidos/4711");

        Assert.Equal(HttpStatusCode.OK, respuesta.StatusCode);
        Assert.Equal("""{"numero":4711,"cliente":"ACME S.L.","estado":"Borrador","lineas":1}""",
            await respuesta.Content.ReadAsStringAsync());
    }
}
```

La API del ejemplo (`Tienda.Api`) es una API mínima con `GET /pedidos/{numero}` que lee `TiendaDbContext` con `ConnectionStrings:Tienda`. El test siembra el pedido directamente en la base de datos y lo pide por HTTP. Este test y otro para el 404 de un pedido inexistente pasaron (`GetPedido_Existente_Devuelve200ConElPedido [272 ms]`; la clase usa `Microsoft.AspNetCore.Mvc.Testing`). La factory se crea dentro de cada test por simplicidad; reutilizar una entre tests es cuestión de [WebApplicationFactory](WebApplicationFactory.md).

## Qué es Ryuk y qué pasa si Docker no está

**Ryuk** (Moby Ryuk, imagen `testcontainers/ryuk`) es un contenedor auxiliar que Testcontainers arranca antes del primero que se pide. Cada recurso que crea la librería se etiqueta con el identificador de su sesión; cuando la sesión desaparece, Ryuk elimina los contenedores, redes y volúmenes que quedaron. Si el proceso de tests muere sin ejecutar `DisposeAsync` (un `Ctrl+C`, un runner cancelado), Ryuk es lo que evita los contenedores huérfanos. Según la documentación de Testcontainers para .NET, solo admite contenedores Linux y no conviene desactivarlo salvo que el entorno ya limpie los recursos Docker por su cuenta (nodos efímeros de CI); en el paquete aparecen las variables `TESTCONTAINERS_RYUK_DISABLED`, `TESTCONTAINERS_RYUK_CONTAINER_IMAGE` y `TESTCONTAINERS_RYUK_CONTAINER_PRIVILEGED`. Durante las ejecuciones de este ejemplo se vieron contenedores `testcontainers-ryuk-<guid>` con la imagen `testcontainers/ryuk:0.14.0` mientras duraba la sesión. La limpieza tras matar el proceso **no se reprodujo**: provocarla exigía matar procesos de prueba en una máquina compartida con otras ejecuciones, y se descartó. El comportamiento descrito es el de la documentación.

**Con Docker parado.** No se reprodujo (no se detuvo Docker Desktop). Un intento con `DOCKER_HOST` apuntando a un puerto inexistente tampoco falló: Testcontainers probó otras estrategias de conexión y se conectó al `npipe://./pipe/docker_engine` habitual. El texto del error está en el paquete `Testcontainers` 4.16.0, tal como se lee en su ensamblado:

```text
Docker is either not running or misconfigured. Please ensure that Docker is running and that the endpoint is properly configured.
```

No se comprobó en qué momento exacto se lanza (si en `StartAsync` del primer contenedor o antes) ni con qué tipo de excepción.

## Errores frecuentes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `Docker is either not running or misconfigured. Please ensure that Docker is running and that the endpoint is properly configured.` (texto leído en el paquete; no reproducido) | Docker no está arrancado o su punto de conexión no es accesible | Arrancar Docker Desktop o el servicio; en CI usar un runner con Docker |
| `23505: duplicate key value violates unique constraint "PK_Pedidos"` en el segundo test | Contenedor compartido sin limpieza: el test anterior dejó su fila | Respawn antes de cada test (o transacción sin `Commit`) |
| Tras reiniciar con Respawn, EF Core intenta aplicar de nuevo las migraciones, o `GetAppliedMigrationsAsync()` devuelve una lista vacía | Respawn vació `__EFMigrationsHistory` | `TablesToIgnore = [new Table("__EFMigrationsHistory")]` |
| `Assert.Equal() Failure` con `Expected: 0 / Actual: 1` solo contra SQLite | El sustituto en memoria se comporta distinto (aquí, `LIKE` insensible a mayúsculas) | Hacer el test contra PostgreSQL real |
| `error CS1705: Assembly 'Tienda.Datos' ... uses 'Microsoft.EntityFrameworkCore, Version=10.0.14.0' ... which has a higher version than referenced assembly ... Version=10.0.4.0` al añadir un proyecto web | Versiones distintas de EF Core resueltas por rutas diferentes (Npgsql arrastra una menor) | Fijar `Microsoft.EntityFrameworkCore` y `Microsoft.EntityFrameworkCore.Relational` a la misma versión en el proyecto de datos |
| La suite tarda minutos | Un contenedor por clase o por test | Fixture de colección más Respawn |
| El contenedor reutilizado no desaparece | `WithReuse(true)` desactiva Ryuk para ese recurso | `docker rm -f <id>`; usarlo solo en local |
| Los tests de una misma colección no corren en paralelo | xUnit serializa las clases de una colección | Es lo esperado: agrupa solo lo que comparte el contenedor |

## Buenas prácticas avanzadas

- **Reinicia el estado al empezar el test, no al terminar.** Si el reinicio va en `InitializeAsync`, un test que se interrumpió o falló no contamina al siguiente, y la base de datos queda con el estado del último test para depurarlo. Un reinicio en `DisposeAsync` no se ejecuta si el proceso muere.
- **Excluye de Respawn lo que no son datos del test.** `__EFMigrationsHistory` y las tablas de referencia que el esquema siembra (países, estados) se declaran en `TablesToIgnore`; si no, cada reinicio las borra y los tests dependen de resembrarlas.
- **Asierta sobre `SqlState` y `ConstraintName`, no sobre el mensaje.** El mensaje de PostgreSQL cambia entre versiones y entre idiomas del servidor; `23505` (unique_violation), `23503` (foreign_key_violation) y el nombre de la restricción son estables. Guarda los códigos como constantes con nombre.
- **Una fixture por motor y una colección por recurso compartido.** Todos los tests que usan PostgreSQL en una colección `postgres`; los de otro recurso (otro contenedor) en otra, para que sigan en paralelo entre sí. Una colección única para toda la suite apaga el paralelismo de xUnit entero.
- **Declara en la fixture el esquema que el test valida.** Aplicar `MigrateAsync()` prueba también las migraciones. Si en producción el esquema se aplica con un script o con otra herramienta, la fixture debe aplicar ese mismo mecanismo, no el que sea cómodo para el test.
- **Fija la imagen y mantenla igual que producción.** `postgres:16-alpine` en el test y `postgres:15` en producción es probar otro motor. Cuando se actualiza producción, el cambio de esa línea es el que revela qué se rompe.

## Documentación oficial

- [Testcontainers for .NET](https://dotnet.testcontainers.org/) — la referencia de la librería: builders, estrategias de espera, redes y configuración por variables de entorno. Punto de partida para opciones que la guía no cubre.
- [Módulo de PostgreSQL](https://dotnet.testcontainers.org/modules/postgres/) — qué configura `PostgreSqlBuilder` y cómo añadir scripts de inicio.
- [Resource Reaper](https://dotnet.testcontainers.org/api/resource_reaper/) — qué hace Ryuk y cuándo conviene o no desactivarlo.
- [Respawn](https://github.com/jbogard/Respawn) — opciones de `RespawnerOptions` (tablas y esquemas incluidos o ignorados, adaptadores por motor).

---

*En resumen: un `PostgreSqlBuilder` con la imagen fijada, una fixture de colección que arranca el contenedor y aplica las migraciones una vez, y Respawn (sin vaciar el historial de migraciones) antes de cada test dan un PostgreSQL real, aislado y desechable por unos 10 ms por test, en lugar de los 3 s de un contenedor nuevo para cada uno.*
