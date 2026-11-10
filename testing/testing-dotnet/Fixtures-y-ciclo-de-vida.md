# Fixtures y ciclo de vida en xUnit

## ¿Qué es?

El ciclo de vida de xUnit define qué se ejecuta antes y después de cada test, de cada clase de test y de cada grupo de clases (*colección*). Una *fixture* es un objeto que xUnit crea una sola vez para uno de esos ámbitos y entrega por constructor a los tests que lo piden, de modo que compartan un recurso caro (una base de datos, un host web, un contenedor) sin recrearlo en cada test.

## ¿Por qué existe?

xUnit crea una **instancia nueva de la clase de test para cada test** (ver [xUnit](xUnit.md)). El aislamiento es total, pero todo lo que se prepare en el constructor se repite por test. Arrancar una API en memoria tarda segundos y levantar un contenedor con PostgreSQL, más: repetirlo en cada test convierte una suite de dos segundos en una de diez minutos. Las fixtures resuelven el dilema: el recurso caro se crea **una vez** y la clase de test sigue recreándose por test.

> Si conoces la inyección de dependencias de ASP.NET Core, los *lifetimes* son una buena analogía: la clase de test es *transient* (una instancia por test) y la fixture es *singleton* dentro de su ámbito (la clase o la colección).

El precio de compartir es que lo compartido ya no está aislado: lo que un test deja en la fixture lo ve el siguiente. Los apartados siguientes tratan de ese precio y de cómo pagarlo.

## ¿Cuándo y para qué se usa?

Siempre que varios tests necesiten el mismo recurso costoso o con inicialización **asíncrona** (algo que un constructor de C# no puede hacer con `await`). En una tienda online: una base de datos con el esquema de `Pedido` creado una vez, el host de la API (ver [WebApplicationFactory](WebApplicationFactory.md)), un contenedor de PostgreSQL con las migraciones aplicadas (ver [Testcontainers](Testcontainers.md)). Para un objeto barato (un `Pedido` en memoria) no hace falta fixture: basta el constructor del test.

Los ejemplos usan el dominio de la tienda (`Pedido` con su `Numero`, `EstadoPedido`) y una base de datos SQLite en memoria como recurso compartido. Las salidas citadas provienen de un proyecto xUnit 2.9.3 (SDK 10.0.401, `net10.0`, `Microsoft.Data.Sqlite` 10.0.14) ejecutado con `dotnet test` el 2026-11-10; el runner estaba en inglés, las rutas de fichero se abrevian y, donde se indica, se omiten las marcas de hora.

## El ciclo de vida de un test

Con una clase de test que implementa todos los puntos de enganche a la vez, más una fixture de clase (se explica en la siguiente sección), cada paso escribe una línea en un registro:

```csharp
public class RelojFixture : IAsyncLifetime
{
    public RelojFixture() => Registro.Escribir("  fixture   ctor");
    public Task InitializeAsync() { Registro.Escribir("  fixture   InitializeAsync"); return Task.CompletedTask; }
    public Task DisposeAsync()    { Registro.Escribir("  fixture   DisposeAsync");    return Task.CompletedTask; }
}

public class CicloTests : IClassFixture<RelojFixture>, IAsyncLifetime, IDisposable
{
    public CicloTests(RelojFixture fixture) => Registro.Escribir("test      ctor");
    public Task InitializeAsync() { Registro.Escribir("test      InitializeAsync"); return Task.CompletedTask; }
    public Task DisposeAsync()    { Registro.Escribir("test      DisposeAsync");    return Task.CompletedTask; }
    public void Dispose()         => Registro.Escribir("test      Dispose");

    [Fact] public void A() => Registro.Escribir("test      >>> cuerpo de A");
    [Fact] public void B() => Registro.Escribir("test      >>> cuerpo de B");
}
```

`Registro.Escribir` añade una línea a un fichero (con un candado, porque los tests pueden ejecutarse a la vez); es un asistente mínimo escrito para observar el orden, no forma parte de xUnit. Contenido del registro tras `dotnet test`, sin marcas de hora:

```text
  fixture   ctor
  fixture   InitializeAsync
test      ctor
test      InitializeAsync
test      >>> cuerpo de A
test      DisposeAsync
test      Dispose
test      ctor
test      InitializeAsync
test      >>> cuerpo de B
test      DisposeAsync
test      Dispose
  fixture   DisposeAsync
```

Lo que enseña el registro:

- **La fixture se crea una vez** (antes del primer test de la clase) y se destruye una vez (después del último). El test se construye y destruye **dos veces**, una por test.
- **Orden dentro de un test:** constructor → `InitializeAsync` → cuerpo → `DisposeAsync` → `Dispose`. El `DisposeAsync` va antes que el `Dispose`.
- **Constructor y `Dispose` son síncronos.** Para `await` (arrancar un contenedor, aplicar migraciones) la clase implementa `IAsyncLifetime`, que añade `InitializeAsync` y `DisposeAsync`. Sirve tanto en clases de test como en fixtures.

En xUnit 2.9.3 `InitializeAsync` y `DisposeAsync` devuelven `Task`. En xUnit v3 la interfaz devuelve `ValueTask` (según la documentación de migración; no se ejecutó v3).

Regla práctica: lo que se pueda hacer en el constructor, va en el constructor; `IAsyncLifetime` solo cuando hace falta `await`.

## `IClassFixture<T>`: compartir dentro de una clase

`IClassFixture<T>` pide a xUnit que cree un `T` para la clase, lo inyecte por constructor en cada test y lo destruya al acabar la clase. `T` necesita un constructor público sin parámetros (y puede implementar `IDisposable` o `IAsyncLifetime` para limpiar). La fixture de la base de datos en memoria de la tienda:

```csharp
public sealed class TiendaDb : IDisposable
{
    public SqliteConnection Conexion { get; }

    public TiendaDb()
    {
        Conexion = new SqliteConnection("Data Source=:memory:");
        Conexion.Open();   // la base vive mientras la conexión esté abierta
        Ejecutar("CREATE TABLE pedidos (numero INTEGER PRIMARY KEY, estado TEXT NOT NULL)");
    }

    public void Guardar(Pedido pedido) =>
        Ejecutar("INSERT INTO pedidos (numero, estado) VALUES ($n, $e)",
            ("$n", pedido.Numero), ("$e", pedido.Estado.ToString()));

    public long Contar() { /* SELECT COUNT(*) FROM pedidos (abreviado) */ }
    public void Vaciar() => Ejecutar("DELETE FROM pedidos");

    public void Dispose() => Conexion.Dispose();
    // Ejecutar(sql, parámetros): crea un SqliteCommand y lo ejecuta (abreviado)
}
```

Una base SQLite `:memory:` desaparece al cerrar su conexión; por eso la fixture mantiene la conexión abierta durante toda su vida (ver la [documentación de bases en memoria de Microsoft.Data.Sqlite](https://learn.microsoft.com/dotnet/standard/data/sqlite/in-memory-databases)). Una clase de test la recibe por constructor:

```csharp
public class PedidoRepositorioTests : IClassFixture<TiendaDb>
{
    private readonly TiendaDb _db;
    public PedidoRepositorioTests(TiendaDb db) => _db = db;   // la misma instancia en todos los tests

    [Fact]
    public void Guardar_UnPedido_DejaUnaFila() { /* usa _db */ }
}
```

Una clase puede declarar varias fixtures (`IClassFixture<A>, IClassFixture<B>`) y recibir todas en el constructor.

## `ICollectionFixture<T>` y `[Collection]`: compartir entre clases

Una *colección* es un grupo de clases de test que xUnit nunca ejecuta a la vez y que comparten fixtures. `IClassFixture` solo comparte dentro de una clase; para que varias clases usen **la misma** instancia hay que declarar una colección con nombre (una clase vacía con `[CollectionDefinition]`) y marcar cada clase de test con ese nombre:

```csharp
[CollectionDefinition("Base de datos")]
public class BaseDatosCollection : ICollectionFixture<BaseDatosFixture> { }   // sin código: solo declara

[Collection("Base de datos")]
public class PedidoRepositorioTests
{
    public PedidoRepositorioTests(BaseDatosFixture f) { /* ... */ }
    [Fact] public void Guarda() { /* ... */ }
}

[Collection("Base de datos")]
public class CuponRepositorioTests
{
    public CuponRepositorioTests(BaseDatosFixture f) { /* ... */ }
    [Fact] public void Guarda() { /* ... */ }
}
```

Con registro en la fixture (que implementa `IAsyncLifetime`) y en los constructores:

```text
fixture de colección ctor
fixture de colección InitializeAsync
  CuponRepositorioTests ctor
  CuponRepositorioTests.Guarda
  PedidoRepositorioTests ctor
  PedidoRepositorioTests.Guarda
fixture de colección DisposeAsync
```

Una sola fixture para las dos clases, creada antes de la primera y destruida después de la última. La clase `[CollectionDefinition]` no se instancia nunca: es solo el sitio donde se declara la fixture. Dos consecuencias de la colección:

- Las clases de una misma colección **se ejecutan en serie**, nunca a la vez. Es la garantía que permite compartir una base de datos sin que dos clases se pisen en paralelo.
- Una clase sin `[Collection]` forma su propia colección (de una sola clase), así que `IClassFixture` es el caso particular de colección con un solo miembro.

## Compartir tiene un precio: contaminación entre tests

La fixture comparte el recurso **tal cual**: lo que un test escribe, el siguiente lo encuentra. Dos tests que, cada uno por su lado, esperan encontrar la base vacía:

```csharp
public class ContaminadoTests : IClassFixture<TiendaDb>
{
    private readonly TiendaDb _db;
    public ContaminadoTests(TiendaDb db) => _db = db;

    [Fact]
    public void Guardar_UnPedido_DejaUnaFila()
    {
        _db.Guardar(new Pedido(4711));

        Assert.Equal(1, _db.Contar());
    }

    [Fact]
    public void Guardar_OtroPedido_DejaUnaFila()
    {
        _db.Guardar(new Pedido(4712));

        Assert.Equal(1, _db.Contar());
    }
}
```

Ejecutando solo uno de los dos tests (`--filter "FullyQualifiedName~ContaminadoTests&DisplayName~UnPedido"`, y lo mismo con `OtroPedido`), pasan los dos. Ejecutando la clase entera:

```text
  Passed Tienda.Tests.Datos.ContaminadoTests.Guardar_OtroPedido_DejaUnaFila [33 ms]
  Failed Tienda.Tests.Datos.ContaminadoTests.Guardar_UnPedido_DejaUnaFila [5 ms]
  Error Message:
   Assert.Equal() Failure: Values differ
Expected: 1
Actual:   2
```

Es el síntoma clásico: **el test pasa solo y falla en la suite.** El que corre segundo encuentra la fila del primero. El mensaje no menciona la contaminación (solo dice `Expected: 1 / Actual: 2`), y qué test falla depende del orden de ejecución, que no está garantizado (ver más abajo). La variante con clave primaria da un error de la base de datos en lugar de una aserción: dos tests que insertan el pedido `4711`:

```text
  Failed Tienda.Tests.Datos.PkTests.Confirmar_Guarda4711 [5 ms]
  Error Message:
   Microsoft.Data.Sqlite.SqliteException : SQLite Error 19: 'UNIQUE constraint failed: pedidos.numero'.
```

Con una `[Collection]` la contaminación cruza clases. Una clase da de alta el pedido `4711` y otra comprueba que el informe está vacío; las dos comparten `TiendaDb`:

```csharp
[Collection("Tienda DB")]
public class InformeAntesTests   // declarada antes en el fichero
{
    [Fact] public void SinPedidos_ElInformeEstaVacio() => Assert.Equal(0, _db.Contar());   // _db: la fixture (abreviado)
}

[Collection("Tienda DB")]
public class AltaDespuesTests    // declarada después en el fichero
{
    [Fact] public void Alta_DejaUnPedido() { _db.Guardar(new Pedido(4711)); Assert.Equal(1, _db.Contar()); }
}
```

```text
  Passed Tienda.Tests.Datos.AltaDespuesTests.Alta_DejaUnPedido [37 ms]
  Failed Tienda.Tests.Datos.InformeAntesTests.SinPedidos_ElInformeEstaVacio [6 ms]
Expected: 0
Actual:   1
```

En este experimento el alta corrió primero en las tres ejecuciones; con las clases declaradas en el orden inverso, el mismo par pasaba siempre. Es decir, el resultado depende de un detalle (el orden de declaración) que nadie vigila, y reordenar un fichero o añadir una clase puede romper la suite sin tocar ningún test.

## Reiniciar el estado entre tests

La solución es que cada test **parta de un estado conocido**, y hay tres formas, de menos a más aislamiento.

**1. Vaciar al principio de cada test.** El constructor de la clase de test (que se ejecuta por test) deja la base como se espera:

```csharp
public class LimpioTests : IClassFixture<TiendaDb>
{
    private readonly TiendaDb _db;

    public LimpioTests(TiendaDb db)
    {
        _db = db;
        _db.Vaciar();   // estado conocido antes de CADA test
    }
    // ... los mismos dos tests de ContaminadoTests
}
```

```text
  Passed Tienda.Tests.Datos.LimpioTests.Guardar_OtroPedido_DejaUnaFila [14 ms]
  Passed Tienda.Tests.Datos.LimpioTests.Guardar_UnPedido_DejaUnaFila [< 1 ms]
```

Limpiar **al empezar** y no solo al terminar es lo robusto: si un test anterior falló a mitad y se saltó su limpieza final, el siguiente sigue partiendo de cero.

**2. Una transacción por test que nunca se confirma.** El constructor abre una transacción y `Dispose` la revierte; lo que el test escriba desaparece solo. Es la técnica habitual con una base real, porque no depende de recordar qué tablas vaciar:

```csharp
public class TransaccionTests : IClassFixture<TiendaDb>, IDisposable
{
    private readonly TiendaDb _db;
    private readonly SqliteTransaction _tx;

    public TransaccionTests(TiendaDb db)
    {
        _db = db;
        _tx = db.Conexion.BeginTransaction();
    }

    public void Dispose() => _tx.Rollback();

    [Fact] public void A() { _db.Guardar(new Pedido(4711)); Assert.Equal(1, _db.Contar()); }
    [Fact] public void B() { _db.Guardar(new Pedido(4711)); Assert.Equal(1, _db.Contar()); }   // mismo número: no choca
}
```

Los dos tests insertan el pedido `4711` y pasan, algo que con `PkTests` fallaba. Dos límites: el código bajo prueba debe usar **la misma conexión** (con otra, no ve la transacción) y no puede hacer `COMMIT` por su cuenta. Con Entity Framework Core hay equivalentes (ver [Entity Framework Core](../../bases-de-datos/acceso-a-datos-dotnet/Entity-Framework-Core.md)).

**3. Un recurso nuevo por test.** Si el recurso es barato, no se comparte: se crea en el constructor y se destruye en `Dispose`. En esta máquina, 200 bases SQLite en memoria creadas con su tabla y una fila tardaron 38 ms (0,2 ms cada una), frente a 3 ms de 200 inserciones con vaciado. Con SQLite en memoria no merece la pena una fixture; con un contenedor de PostgreSQL, que tarda segundos, sí, y se combina con la opción 1 o la 2.

## Orden de ejecución y paralelismo

### Orden: no lo garantiza xUnit

Con seis clases de test de tres tests cada una, ejecutadas con el paralelismo desactivado (para que el registro no se entremezcle), el orden **de clases** cambió en cada ejecución:

```text
clases: Delta Alfa Gamma Epsilon Zeta Beta
clases: Epsilon Gamma Zeta Delta Alfa Beta
clases: Beta Gamma Delta Alfa Zeta Epsilon
clases: Delta Gamma Epsilon Alfa Zeta Beta
```

En ocho ejecuciones no se repitió ninguna secuencia. En cambio, el orden **de los métodos dentro de una clase** fue el mismo en las ocho ejecuciones (los tres métodos `T1`, `T2` y `T3` de `AlfaTests` salieron siempre `T1 T3 T2`) y no coincide con el orden del fichero ni el alfabético: es estable para unos nombres dados, pero arbitrario. Seis clases dentro de una misma `[Collection]` salieron siempre en el mismo orden en cinco ejecuciones, y en el orden inverso al de declaración en el fichero.

Resumen de lo observado en 2.9.3:

| Nivel | Observado | Se puede confiar en ello |
|---|---|---|
| Orden entre colecciones/clases sueltas | Cambia entre ejecuciones | No |
| Orden de las clases dentro de una colección | Estable entre ejecuciones; inverso al de declaración | No: es un detalle de implementación |
| Orden de los métodos dentro de una clase | Estable entre ejecuciones; no coincide con el del fichero | No: cambia al renombrar tests |

Un test que solo pasa en un orden concreto está mal diseñado: parte de estado que otro dejó. Existen `[TestCaseOrderer]` y `[TestCollectionOrderer]` para fijar el orden, pero tapan el problema en lugar de resolverlo.

### Paralelismo: por colecciones

Por defecto, **las colecciones distintas se ejecutan en paralelo** y los tests de una misma colección, en serie. Dos clases, cada una con su propia fixture de clase cuyo `InitializeAsync` espera 300 ms, y marcas de tiempo desde el inicio de la ejecución:

```text
fixture lenta inicio    0 ms          # por defecto
fixture lenta inicio    0 ms
  Envios.Pasa           340 ms
  Pagos.Pasa            340 ms
fixture lenta fin     347 ms
fixture lenta fin     347 ms
```

Las dos fixtures se inicializan a la vez. Con el paralelismo apagado:

```text
fixture lenta inicio    0 ms          # sin paralelismo
  Envios.Pasa           352 ms
fixture lenta fin     374 ms
fixture lenta inicio  383 ms
  Pagos.Pasa            691 ms
fixture lenta fin     692 ms
```

Las fixtures y los tests de una clase terminan antes de que empiece la siguiente: el tiempo se duplica. Tres formas de desactivarlo (las dos primeras, con más detalle, en [xUnit](xUnit.md)):

```csharp
[assembly: CollectionBehavior(DisableTestParallelization = true)]   // en cualquier fichero del proyecto
```

```json
{ "parallelizeTestCollections": false }
```

El segundo va en `xunit.runner.json`, que debe copiarse al directorio de salida. La tercera es una opción de ejecución que no requiere recompilar:

```bash
dotnet test -- xUnit.ParallelizeTestCollections=false
```

(La capitalización importa: con `xunit.parallelizeTestCollections=false` el comando no tuvo efecto en la prueba y los tests siguieron entremezclados.)

Apagar el paralelismo en toda la suite por culpa de una clase que comparte base de datos es matar moscas a cañonazos. Lo proporcionado es meter **solo** las clases que comparten recurso en una `[Collection]`: se serializan entre sí y el resto sigue en paralelo.

## Cuando la fixture falla

Un fixture con el constructor roto, uno con `InitializeAsync` roto, y los mismos fallos en una clase de test:

```csharp
public class FixtureRota : IDisposable
{
    public FixtureRota() => throw new InvalidOperationException("No hay conexión a la base de datos.");
    public void Dispose() { /* nunca se llama */ }
}

public class ConFixtureRotaTests : IClassFixture<FixtureRota>
{
    public ConFixtureRotaTests(FixtureRota f) { }   // nunca se ejecuta
    [Fact] public void A() { }
    [Fact] public void B() { }
}
```

```text
  Failed Tienda.Tests.Falla.ConFixtureRotaTests.A [1 ms]
  Error Message:
   Class fixture type 'Tienda.Tests.Falla.FixtureRota' threw in its constructor
---- System.InvalidOperationException : No hay conexión a la base de datos.
  Failed Tienda.Tests.Falla.ConFixtureRotaTests.B [1 ms]
  Error Message:
   Class fixture type 'Tienda.Tests.Falla.FixtureRota' threw in its constructor
---- System.InvalidOperationException : No hay conexión a la base de datos.
```

Observado en 2.9.3:

| Qué falla | Qué ocurre |
|---|---|
| El constructor de una fixture | **Todos** los tests de la clase fallan con `Class fixture type '…' threw in its constructor` y la excepción interna; ni el constructor del test ni su cuerpo se ejecutan. La fixture se construyó una sola vez; el `Dispose` no se llama (el objeto no llegó a existir). |
| `InitializeAsync` de una fixture | El test falla con la excepción original, sin el prefijo anterior; el constructor del test no se ejecuta; **sí se llama a `DisposeAsync`** de la fixture. |
| El constructor de una clase de test | El test falla; **no se llama a `Dispose`**. |
| `InitializeAsync` de una clase de test | El test falla; el constructor ya se ejecutó y **no se llama a `DisposeAsync`**. |

Los dos últimos casos importan para la limpieza: lo que un constructor abrió antes de lanzar una excepción, o lo que `InitializeAsync` dejó a medias en una clase de test, no se libera por el camino habitual. Un recurso que se abre dentro de una clase de test debe protegerse con `try/catch` en el propio constructor o moverse a una fixture. El fallo de una fixture afecta solo a las clases que la usan: en la misma ejecución, una clase sin fixture rota (`SanaTests`) pasó.

## Qué mecanismo elegir

| Necesidad | Mecanismo | Ámbito de vida | Cuándo NO |
|---|---|---|---|
| Preparar un objeto barato para cada test | Constructor (y `IDisposable`) | Un test | — |
| Preparación que necesita `await` y es específica del test | `IAsyncLifetime` en la clase de test | Un test | Si es cara: se repite por test |
| Recurso caro que usan los tests de **una** clase | `IClassFixture<T>` | Una clase | Si otra clase necesita **la misma** instancia |
| Recurso caro que usan **varias** clases | `ICollectionFixture<T>` + `[Collection]` | Una colección | Si las clases podrían ir en paralelo y no comparten nada: serializarlas cuesta tiempo |
| Un recurso por test (si es barato) | Crear en el constructor, `Dispose` | Un test | Si crear el recurso tarda segundos |
| Estado en `static` | Ninguno | Todo el proceso | Siempre: rompe el aislamiento |

Dos decisiones aparte: **cómo reiniciar** el estado de lo compartido (vaciar al principio del test, transacción revertida, recurso nuevo) y **cómo evitar el paralelismo** (colección, no desactivarlo todo). Un recurso compartido caro de verdad (un host web o un contenedor) tiene su propia guía: [WebApplicationFactory](WebApplicationFactory.md) y [Testcontainers](Testcontainers.md) (y la parte de Docker, en [Testcontainers en Docker](../../devops/docker/Testcontainers.md)).

## Errores frecuentes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| El test pasa solo y falla en la suite (`Expected: 1 / Actual: 2`) | El recurso de una fixture conserva lo que escribió otro test | Reiniciar el estado al empezar cada test (vaciar o transacción) |
| `SQLite Error 19: 'UNIQUE constraint failed: pedidos.numero'` en un test que antes pasaba | Otro test ya insertó la misma clave en la fixture compartida | Transacción revertida por test, o claves distintas por test |
| La suite pasa unas veces y otras no, sin cambios de código | Orden de clases no determinista, o clases en paralelo sobre el mismo recurso | Reiniciar el estado; meter en una `[Collection]` las clases que comparten recurso |
| `Class fixture type '…' threw in its constructor` en todos los tests de una clase | El constructor de la fixture lanza | Arreglar la causa interna (leer la línea `----`); mover lo asíncrono a `InitializeAsync` |
| Los recursos de un test no se liberan tras un fallo en el constructor | `Dispose` no se llama si el constructor lanza | Capturar y liberar dentro del constructor, o usar una fixture |
| `The following constructor parameters did not have matching fixture data: TiendaDb db` | El constructor pide una fixture que la clase no declara | Añadir `IClassFixture<TiendaDb>` a la clase, o `[Collection]` si la fixture es de colección |
| Las fixtures de dos clases se crean dos veces en vez de una | Se usó `IClassFixture<T>` en cada clase | `ICollectionFixture<T>` y `[Collection]` en ambas |
| `static` mutable «para compartir» y fallos que cambian con el orden | Campo `static` fuera de cualquier fixture | Moverlo a una fixture con reinicio por test |

## Buenas prácticas avanzadas

- **Reinicia al empezar, no solo al terminar.** `Dispose` no se ejecuta si el constructor falla, y un test que se rompe a mitad puede saltarse su propia limpieza. El constructor del test, que corre siempre antes del cuerpo, es el sitio que garantiza partir de un estado conocido.
- **Prefiere la transacción revertida a vaciar tablas cuando el recurso es una base de datos real.** Vaciar obliga a mantener la lista de tablas y su orden por las claves foráneas; el `Rollback` borra todo lo que el test hizo sin saber qué fue. Comprueba que el código bajo prueba usa la misma conexión y no confirma por su cuenta.
- **Serializa lo que comparte, no la suite.** Una `[Collection]` por recurso compartido (no una colección global): dos colecciones distintas siguen corriendo en paralelo entre sí. Una colección que lo abarca todo es la forma lenta de apagar el paralelismo.
- **Haz la fixture inmutable de cara a los tests.** Que exponga operaciones (`Guardar`, `Contar`) y no el recurso crudo; el día que se cambie SQLite por PostgreSQL, el test no cambia. Si un test necesita datos propios, que los cree él y no confíe en los de la fixture.
- **Detecta la contaminación ejecutando cada test solo.** Un test que pasa con `--filter` y falla en la suite depende de estado que otro deja; la ejecución en solitario de cada test de una clase (con `--filter "FullyQualifiedName~Clase.Metodo"`) lo delata. Es el diagnóstico más barato.
- **No dependas de que la fixture falle de forma limpia.** Un fallo en el constructor de una fixture marca en rojo todos los tests que la usan, con el mismo mensaje: en CI parece una avalancha de fallos con una sola causa. Lee siempre la primera excepción interna.

## Documentación oficial

- [xUnit.net: shared context](https://xunit.net/docs/shared-context) — la página que describe constructor/`Dispose`, `IClassFixture`, `ICollectionFixture` e `IAsyncLifetime`; para contrastar el ciclo de vida y las reglas de las colecciones.
- [xUnit.net: running tests in parallel](https://xunit.net/docs/running-tests-in-parallel) — cómo decide xUnit qué ejecuta en paralelo y las opciones para limitarlo; para diagnosticar fallos intermitentes.
- [Microsoft Learn: bases de datos en memoria de Microsoft.Data.Sqlite](https://learn.microsoft.com/dotnet/standard/data/sqlite/in-memory-databases) — por qué la base desaparece al cerrar la conexión y cómo compartirla entre conexiones; para el recurso de los ejemplos.

---

*En resumen: el test se crea de nuevo cada vez y la fixture se crea una vez; lo que se comparte no está aislado, así que cada test debe reiniciar lo que toca y las clases que comparten recurso, agruparse en una colección en lugar de apagar el paralelismo.*
