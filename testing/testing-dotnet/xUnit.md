# xUnit

## ¿Qué es?

xUnit es el framework de pruebas más usado en .NET: define cómo se escriben los tests (`[Fact]`, `[Theory]`), cómo se comprueban los resultados (`Assert`) y cómo se ejecutan (`dotnet test`). Cada test es un método que termina en verde (no lanzó nada) o en rojo (una aserción falló o saltó una excepción).

## ¿Por qué existe?

Sin un framework, «probar» es ejecutar la aplicación a mano y mirar si algo se rompe. Un framework de pruebas convierte cada comprobación en un método que se descubre, se ejecuta de forma aislada y devuelve un veredicto binario, de modo que una suite de miles de tests se lanza con un comando y se puede automatizar en integración continua.

xUnit se distingue de sus alternativas por una decisión de diseño: **crea una instancia nueva de la clase de test para cada test**. Un campo de instancia nunca se comparte entre dos tests, y no existen `[SetUp]` ni `[TearDown]`: la preparación es el constructor y la limpieza es `IDisposable.Dispose`. El aislamiento deja de ser una disciplina y pasa a ser el comportamiento por defecto.

> Si vienes del frontend, xUnit es a .NET lo que Vitest o Jest son a TypeScript: [Vitest](../../desarrollo-web/frontend-react/Vitest.md) cumple el mismo papel de runner, aserciones y convenciones.

## ¿Cuándo y para qué se usa?

Es la base de cualquier proyecto de pruebas en .NET: los tests unitarios de dominio, los de integración y los de API se escriben con xUnit, aunque cambien las herramientas de apoyo (`WebApplicationFactory`, Testcontainers, NSubstitute). En una tienda online, las reglas del dominio («un pedido sin líneas no se puede confirmar», «un cupón no puede superar el 50 %») son tests unitarios; un proyecto de pruebas separado (`Tienda.Tests`) referencia al proyecto bajo prueba y se ejecuta con `dotnet test` en local y en CI. Qué tipo de test conviene en cada capa se explica en [Tipos de tests](Tipos-de-tests.md); el ciclo de escribir primero el test, en [TDD](../tdd-bdd-sdd/TDD.md).

## Dos versiones: v2 y v3

xUnit convive hoy en dos líneas con paquetes distintos. Comprobado el 2026-11-09 con el SDK de .NET 10.0.401:

| | v2 | v3 |
|---|---|---|
| Paquete principal | `xunit` (última 2.9.3) | `xunit.v3` (última 4.0.3) |
| Proyecto de test | biblioteca (`.dll`) que carga un runner | ejecutable (`OutputType` `Exe`): se puede lanzar con `dotnet run` |
| Plantilla | `dotnet new xunit` (viene con el SDK) | `dotnet new xunit3` (requiere `dotnet new install xunit.v3.templates`) |
| `ITestOutputHelper` | `using Xunit.Abstractions;` | namespace `Xunit`, sin `xunit.abstractions` |
| `async void` | funciona, con aviso del analizador `xUnit1048` | error de compilación `xUnit1049` y fallo en ejecución |
| Omitir en ejecución | solo `[Fact(Skip = "...")]`, estático | además `Assert.Skip`, `Assert.SkipUnless`, `Assert.SkipWhen` y `SkipUnless`/`SkipWhen` en `[Fact]` |
| Contexto del test | no existe | `TestContext.Current` (token de cancelación, test actual) |
| Runner de `dotnet test` | VSTest (`Microsoft.NET.Test.Sdk` + `xunit.runner.visualstudio`) | Microsoft Testing Platform |

Qué instala la plantilla con el SDK 10.0.401 instalado (`dotnet new xunit`): un proyecto `net10.0` de v2.

```xml
<PackageReference Include="coverlet.collector" Version="6.0.4" />
<PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.14.1" />
<PackageReference Include="xunit" Version="2.9.3" />
<PackageReference Include="xunit.runner.visualstudio" Version="3.1.4" />
```

Más un `<Using Include="Xunit" />` que evita repetir `using Xunit;` en cada fichero. Esa es la versión de todos los ejemplos siguientes, salvo donde se indique v3. Para v3 se probó un proyecto con `xunit.v3` 4.0.3, `<OutputType>Exe</OutputType>` y la misma referencia al dominio.

Con el SDK 10, `dotnet test` sobre un proyecto v3 falla mientras no se elija el runner nuevo:

```text
error : Testing with VSTest target is no longer supported by Microsoft.Testing.Platform on .NET 10 SDK and later.
If you use dotnet test, you should opt-in to the new dotnet test experience.
```

Se resuelve con un `global.json` en la raíz de la solución y con la sintaxis nueva de `dotnet test`, que recibe el proyecto con `--project`:

```json
{
  "test": {
    "runner": "Microsoft.Testing.Platform"
  }
}
```

La documentación de xunit.net indica que la plantilla `xunit3` genera ese fichero. Los paquetes `xunit.v3` de la línea 4.x usan Microsoft Testing Platform v2 por defecto y envían telemetría anónima a Microsoft; la variable de entorno `TESTINGPLATFORM_TELEMETRY_OPTOUT=1` la desactiva (según la documentación oficial; no se comprobó el envío).

Qué elegir: v3 es la línea con desarrollo activo y la que documenta xunit.net como destino; v2 sigue siendo lo que crea `dotnet new xunit` y lo que hay en la mayoría de proyectos existentes. La sintaxis de `[Fact]`, `[Theory]` y de las aserciones es prácticamente la misma, así que lo mismo sirve en las dos; las diferencias de la tabla son lo que cambia al migrar.

## Un primer proyecto de principio a fin

Una solución con el dominio y el proyecto de pruebas, creados con la CLI:

```bash
dotnet new sln -n Tienda                                   # crea Tienda.slnx
dotnet new classlib -n Tienda.Dominio -o src/Tienda.Dominio
dotnet new xunit -n Tienda.Tests -o tests/Tienda.Tests
dotnet sln add src/Tienda.Dominio tests/Tienda.Tests
dotnet add tests/Tienda.Tests reference src/Tienda.Dominio
```

Con el SDK 10, `dotnet new sln` genera el formato `.slnx` en lugar del `.sln` clásico. El árbol resultante, tras borrar `Class1.cs` y `UnitTest1.cs` que crean las plantillas y añadir el código de dominio y un fichero de tests:

```text
Tienda/
├── Tienda.slnx
├── src/
│   └── Tienda.Dominio/
│       ├── Tienda.Dominio.csproj
│       ├── Pedido.cs
│       └── Cupon.cs
└── tests/
    └── Tienda.Tests/
        ├── Tienda.Tests.csproj
        └── PedidoTests.cs
```

El dominio mínimo que necesitan los ejemplos (versión reducida de la entidad `Pedido`: sin identificadores tipados ni `Dinero`):

```csharp
namespace Tienda.Dominio;

public enum EstadoPedido { Borrador, Confirmado, Pagado, Cancelado }

public record LineaPedido(string Sku, int Cantidad, decimal PrecioUnitario)
{
    public decimal Subtotal => Cantidad * PrecioUnitario;
}

public class Pedido
{
    private readonly List<LineaPedido> _lineas = [];

    public Pedido(int numero) => Numero = numero;

    public int Numero { get; }
    public EstadoPedido Estado { get; private set; } = EstadoPedido.Borrador;
    public IReadOnlyList<LineaPedido> Lineas => _lineas;

    public void AgregarLinea(string sku, int cantidad, decimal precioUnitario) =>
        _lineas.Add(new LineaPedido(sku, cantidad, precioUnitario));

    public void Confirmar()
    {
        if (_lineas.Count == 0)
            throw new InvalidOperationException("Un pedido sin líneas no se puede confirmar.");
        Estado = EstadoPedido.Confirmado;
    }
}

public record Cupon
{
    public Cupon(string codigo, int porcentaje)
    {
        if (porcentaje is < 0 or > 50)
            throw new ArgumentOutOfRangeException(nameof(porcentaje), "Un cupón no puede superar el 50 %.");
        Codigo = codigo;
        Porcentaje = porcentaje;
    }

    public string Codigo { get; }
    public int Porcentaje { get; }

    public decimal Aplicar(decimal importe) => importe - importe * Porcentaje / 100m;
}
```

Y un primer fichero de pruebas, `tests/Tienda.Tests/PedidoTests.cs`:

```csharp
using Tienda.Dominio;

namespace Tienda.Tests;

public class PedidoTests
{
    [Fact]
    public void Confirmar_SinLineas_LanzaInvalidOperationException()
    {
        var pedido = new Pedido(4711);

        var ex = Assert.Throws<InvalidOperationException>(() => pedido.Confirmar());

        Assert.Equal("Un pedido sin líneas no se puede confirmar.", ex.Message);
    }

    [Fact]
    public void Confirmar_ConUnaLinea_CambiaElEstadoAConfirmado()
    {
        var pedido = new Pedido(4711);
        pedido.AgregarLinea("CAM-001", 2, 19.99m);

        pedido.Confirmar();

        Assert.Equal(EstadoPedido.Confirmado, pedido.Estado);
    }
}
```

Desde la raíz de la solución, `dotnet test` compila todo y ejecuta los tests:

```text
$ dotnet test
Passed!  - Failed:     0, Passed:     2, Skipped:     0, Total:     2, Duration: 49 ms - Tienda.Tests.dll (net10.0)
```

Para ver el rojo se elimina la regla de dominio (se cambia `if (_lineas.Count == 0)` por `if (false)`) y se vuelve a ejecutar:

```text
[xUnit.net 00:00:00.22]     Tienda.Tests.PedidoTests.Confirmar_SinLineas_LanzaInvalidOperationException [FAIL]
  Failed Tienda.Tests.PedidoTests.Confirmar_SinLineas_LanzaInvalidOperationException [2 ms]
  Error Message:
   Assert.Throws() Failure: No exception was thrown
Expected: typeof(System.InvalidOperationException)
  Stack Trace:
     at Tienda.Tests.PedidoTests.Confirmar_SinLineas_LanzaInvalidOperationException() in ...\PedidoTests.cs:line 12
Failed!  - Failed:     1, Passed:     1, Skipped:     0, Total:     2, Duration: 49 ms - Tienda.Tests.dll (net10.0)
```

El mensaje dice qué se esperaba y qué ocurrió, y la pila apunta a la línea del test. Las salidas citadas provienen de ejecuciones reales con `VSLANG=1033` y `DOTNET_CLI_UI_LANGUAGE=en` (el runner respeta el idioma del sistema; sin esas variables el resumen sale en el idioma del sistema operativo), con las rutas acortadas.

## Escribir tests: `[Fact]` y `[Theory]`

### `[Fact]`: un caso, sin parámetros

Un método `public` con `[Fact]` es un test. Una convención extendida de nombres es `Metodo_Escenario_ResultadoEsperado`: `Confirmar_SinLineas_LanzaInvalidOperationException` dice qué se probó y qué se esperaba, de modo que un rojo en CI se entiende sin abrir el fichero. Cada test sigue la estructura de [Arrange-Act-Assert](Arrange-Act-Assert.md): preparar, ejecutar, comprobar.

### `[Theory]`: la misma regla con varios datos

Cuando la regla es una y los casos son varios, `[Theory]` recibe los datos por parámetros y el runner ejecuta y reporta cada caso por separado. Regla de la tienda: un cupón no puede superar el 50 %.

```csharp
public class CuponTests
{
    [Theory]
    [InlineData(0)]
    [InlineData(10)]
    [InlineData(50)]
    public void Crear_ConPorcentajeValido_ConservaElPorcentaje(int porcentaje)
    {
        var cupon = new Cupon("PROMO", porcentaje);

        Assert.Equal(porcentaje, cupon.Porcentaje);
    }

    [Theory]
    [InlineData(51)]
    [InlineData(80)]
    [InlineData(-1)]
    public void Crear_ConPorcentajeFueraDeRango_Lanza(int porcentaje)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new Cupon("PROMO", porcentaje));
    }
}
```

La salida con `dotnet test --logger "console;verbosity=normal"` lista seis tests, no dos:

```text
  Passed Tienda.Tests.CuponTests.Crear_ConPorcentajeFueraDeRango_Lanza(porcentaje: 80) [4 ms]
  Passed Tienda.Tests.CuponTests.Crear_ConPorcentajeFueraDeRango_Lanza(porcentaje: 51) [< 1 ms]
  Passed Tienda.Tests.CuponTests.Crear_ConPorcentajeFueraDeRango_Lanza(porcentaje: -1) [< 1 ms]
  Passed Tienda.Tests.CuponTests.Crear_ConPorcentajeValido_ConservaElPorcentaje(porcentaje: 10) [1 ms]
  Passed Tienda.Tests.CuponTests.Crear_ConPorcentajeValido_ConservaElPorcentaje(porcentaje: 0) [< 1 ms]
  Passed Tienda.Tests.CuponTests.Crear_ConPorcentajeValido_ConservaElPorcentaje(porcentaje: 50) [< 1 ms]
```

Si el caso `51` fallara, los otros cinco seguirían ejecutándose y apareciendo en verde. Con un `foreach` dentro de un `[Fact]`, el primer fallo cortaría el bucle y ocultaría el resto.

### Tres fuentes de datos

`[InlineData]` solo admite **constantes de compilación** (números, cadenas, `typeof`, enums, arrays de eso). Un objeto no cabe en un atributo:

```csharp
[InlineData(new Cupon("MITAD", 50), 100)]   // ❌
// error CS0182: An attribute argument must be a constant expression, typeof expression
//               or array creation expression of an attribute parameter type
```

Para objetos hay dos salidas más:

| Fuente | Dónde viven los datos | Cuándo |
|---|---|---|
| `[InlineData(...)]` | En el atributo, constantes | Pocos casos con valores simples |
| `[MemberData(nameof(X))]` | Una propiedad o método `static` de la clase de test (o de otra con `MemberType`) | Objetos, datos calculados, datos compartidos entre varios tests |
| `[ClassData(typeof(X))]` | Una clase que implementa `IEnumerable<object[]>` o hereda de `TheoryData<...>` | Conjuntos grandes o reutilizados en varias clases de test |

```csharp
public static IEnumerable<object[]> CuponesYTotales =>
[
    [new Cupon("MITAD", 50), 100m, 50m],
    [new Cupon("DIEZ", 10), 200m, 180m],
    [new Cupon("NADA", 0), 99.99m, 99.99m],
];

[Theory]
[MemberData(nameof(CuponesYTotales))]
public void Aplicar_ConCupon_DevuelveElImporteConDescuento(Cupon cupon, decimal importe, decimal esperado)
{
    Assert.Equal(esperado, cupon.Aplicar(importe));
}
```

```text
  Passed Tienda.Tests.CuponTests.Aplicar_ConCupon_DevuelveElImporteConDescuento(cupon: Cupon { Codigo = MITAD, Porcentaje = 50 }, importe: 100, esperado: 50) [2 ms]
  Passed Tienda.Tests.CuponTests.Aplicar_ConCupon_DevuelveElImporteConDescuento(cupon: Cupon { Codigo = DIEZ, Porcentaje = 10 }, importe: 200, esperado: 180) [< 1 ms]
  Passed Tienda.Tests.CuponTests.Aplicar_ConCupon_DevuelveElImporteConDescuento(cupon: Cupon { Codigo = NADA, Porcentaje = 0 }, importe: 99,99, esperado: 99,99) [< 1 ms]
```

Cada caso aparece con sus argumentos; para un `record` el nombre muestra sus propiedades. Los decimales salen con coma porque la salida usa la cultura del sistema (español).

### `TheoryData<T>`: datos con tipos comprobados

`IEnumerable<object[]>` pierde los tipos: un `string` donde va un `int` solo falla al ejecutar. `TheoryData<...>` declara los tipos de cada columna y el compilador (y el analizador de xUnit, según la documentación) los comprueba:

```csharp
public static TheoryData<int, decimal> Descuentos => new()
{
    { 10, 90m },
    { 25, 75m },
};

[Theory]
[MemberData(nameof(Descuentos))]
public void Aplicar_SobreCien_DevuelveElTotalEsperado(int porcentaje, decimal esperado) =>
    Assert.Equal(esperado, new Cupon("X", porcentaje).Aplicar(100m));
```

Con `[ClassData]` se hereda de `TheoryData<...>` y se llama a `Add` en el constructor:

```csharp
public class CuponDatos : TheoryData<Cupon, decimal, decimal>
{
    public CuponDatos()
    {
        Add(new Cupon("MITAD", 50), 100m, 50m);
        Add(new Cupon("DIEZ", 10), 200m, 180m);
    }
}

[Theory]
[ClassData(typeof(CuponDatos))]
public void Aplicar_ConClassData_DevuelveElImporteEsperado(Cupon cupon, decimal importe, decimal esperado) =>
    Assert.Equal(esperado, cupon.Aplicar(importe));
```

En v3 existen además `TheoryDataRow<...>` (para marcar una fila como omitida o con tiempo máximo) y `MatrixTheoryData` (producto cartesiano de conjuntos), según la documentación de novedades de v3.

## Las aserciones esenciales

`Assert` es la clase estática con la que un test declara el resultado esperado. Lo que se usa a diario:

| Necesidad | Aserción |
|---|---|
| Igualdad (estructural para colecciones y `record`) | `Assert.Equal(esperado, real)` |
| Condición | `Assert.True(...)`, `Assert.False(...)` |
| Nulos | `Assert.Null(x)`, `Assert.NotNull(x)` |
| Contenido | `Assert.Contains(item, coleccion)`, `Assert.Empty(coleccion)` |
| Elemento a elemento | `Assert.Collection(coleccion, e => ..., e => ...)` |
| Excepciones | `Assert.Throws<T>(...)`, `Assert.ThrowsAsync<T>(...)`, `Assert.ThrowsAny<T>(...)` |

El orden de los argumentos importa: primero el valor **esperado**, luego el real. Con la inversión el test pasa o falla igual, pero el mensaje de fallo confunde. Los mensajes reales de los fallos más habituales:

```text
Assert.Equal(3, new[] { 1, 2 }.Length);
  Assert.Equal() Failure: Values differ
  Expected: 3
  Actual:   2

Assert.Equal("Confirmado", "Confirmada");
  Assert.Equal() Failure: Strings differ
                      ↓ (pos 9)
  Expected: "Confirmado"
  Actual:   "Confirmada"
                      ↑ (pos 9)

Assert.Equal(new[] { 1, 2, 3 }, new[] { 1, 2, 4 });
  Assert.Equal() Failure: Collections differ
                 ↓ (pos 2)
  Expected: [1, 2, 3]
  Actual:   [1, 2, 4]
                 ↑ (pos 2)

Assert.Contains("CAM-009", new[] { "CAM-001", "CAM-002" });
  Assert.Contains() Failure: Item not found in collection
  Collection: ["CAM-001", "CAM-002"]
  Not found:  "CAM-009"
```

### Excepciones

`Assert.Throws<T>` exige el tipo **exacto**; devuelve la excepción para comprobar su mensaje o sus propiedades. `Assert.ThrowsAny<T>` acepta también tipos derivados. Un `ArgumentOutOfRangeException` no satisface `Throws<ArgumentException>`:

```text
Assert.Throws<ArgumentException>(() => new Cupon("X", 80));
  Assert.Throws() Failure: Exception type was not an exact match
  Expected: typeof(System.ArgumentException)
  Actual:   typeof(System.ArgumentOutOfRangeException)
  ---- System.ArgumentOutOfRangeException : Un cupón no puede superar el 50 %. (Parameter 'porcentaje')
```

Para código asíncrono, `await Assert.ThrowsAsync<T>(() => ...)`. Sin el `await` la aserción no se espera; el analizador lo rechaza en compilación con el error `xUnit2021` (comprobado en v2 2.9.3).

### Decimales y coma flotante

Un `double` no representa `0.1 + 0.2` como `0.3`:

```text
Assert.Equal(0.3, 0.1 + 0.2);
  Assert.Equal() Failure: Values differ
  Expected: 0,29999999999999999
  Actual:   0,30000000000000004
```

`Assert.Equal(0.3, 0.1 + 0.2, precision: 5)` compara con cinco decimales y pasa. Para `decimal` existe la misma sobrecarga: `Assert.Equal(10.00m, 10.004m, 2)` pasa, y con `10.04m` falla con `Expected: 10,00 (rounded from 10,00)` / `Actual:   10,04 (rounded from 10,04)`. Para importes de dinero, lo habitual es comparar `decimal` exactos; la tolerancia es para resultados que pasan por divisiones o conversiones.

### `Assert.Collection`

Comprueba el número de elementos y una aserción por elemento, en orden:

```csharp
Assert.Collection(pedido.Lineas,
    linea => Assert.Equal("CAM-001", linea.Sku),
    linea => Assert.Equal(7, linea.Cantidad));
```

```text
Assert.Collection() Failure: Item comparison failure
                                           ↓ (pos 1)
Collection: [LineaPedido { Sku = CAM-001, Cantidad = 2, ... }, LineaPedido { Sku = TAZ-002, Cantidad = 1, ... }]
Error:      Assert.Equal() Failure: Values differ
            Expected: 7
            Actual:   1
```

Con un número de elementos distinto: `Assert.Collection() Failure: Mismatched item count` con `Expected count: 2` y `Actual count: 1`.

El `Assert` de xUnit es deliberadamente austero. Para aserciones con lectura de frase (`resultado.ShouldBe(...)`) existe [Shouldly](Shouldly.md), que se usa dentro de los mismos tests de xUnit.

### Tests asíncronos

Un test asíncrono devuelve `Task` (o `ValueTask`) y xUnit lo espera:

```csharp
[Fact]
public async Task Confirmar_ConPasarelaCaida_LanzaExcepcion()
{
    await Assert.ThrowsAsync<InvalidOperationException>(async () =>
    {
        await Task.Delay(1);
        new Pedido(1).Confirmar();
    });
}
```

`async void` no. Con `async void` el framework no tiene una tarea que esperar y no puede asociar el resultado al test. xUnit v2 2.9.3 lo tolera (instala un contexto de sincronización) y avisa en compilación:

```text
warning xUnit1048: Support for 'async void' unit tests is being removed from xUnit.net v3.
To simplify upgrading, convert the test to 'async Task' instead.
```

En v3 es un error de compilación (`xUnit1049: Support for 'async void' unit tests has been removed from xUnit.net v3`) y, si se silencia el analizador, el test falla en ejecución sin llegar a ejecutarse:

```text
failed Tienda.Tests.Err1.AsyncVoidFalla (0ms)
  Xunit.MicrosoftTestingPlatform.XunitException: Tests marked as 'async void' are no longer supported.
  Please convert to 'async Task' or 'async ValueTask'.
```

En v3, un `async` que recibe un `CancellationToken` debería usar el de `TestContext.Current.CancellationToken`; el analizador `xUnit1051` lo avisa.

## El modelo de ejecución

### Una instancia por test

El constructor se ejecuta antes de cada test y `Dispose` (si la clase implementa `IDisposable`) después. Tres tests con un campo de instancia:

```csharp
public class InstanciaTests
{
    private int _contador;

    public InstanciaTests() => Console.Error.WriteLine("ctor");

    [Fact] public void A() { _contador++; Assert.Equal(1, _contador); }
    [Fact] public void B() { _contador++; Assert.Equal(1, _contador); }
    [Fact] public void C() { _contador++; Assert.Equal(1, _contador); }
}
```

```text
ctor
ctor
ctor
  Passed Tienda.Tests.InstanciaTests.B [6 ms]
  Passed Tienda.Tests.InstanciaTests.C [< 1 ms]
  Passed Tienda.Tests.InstanciaTests.A [< 1 ms]
```

Tres construcciones y tres contadores a 1: cada test tiene su propio `_contador`. Si se quiere compartir algo costoso entre tests (un host, una base de datos), la herramienta son los *fixtures*, que se explican en [Fixtures y ciclo de vida](Fixtures-y-ciclo-de-vida.md). El ciclo en una línea: constructor, test, `Dispose`; para preparación o limpieza asíncronas, `IAsyncLifetime`.

El campo `static` es la excepción que rompe el aislamiento: es de la clase, no de la instancia, y sobrevive a todos los tests.

### Orden de ejecución

El orden en que se ejecutan los tests de una clase no está garantizado. Un test que depende de otro:

```csharp
public class OrdenTests
{
    private static int _paso;

    [Fact] public void Primero()  { Assert.Equal(0, _paso); _paso = 1; }
    [Fact] public void Segundo()  { Assert.Equal(1, _paso); _paso = 2; }
    [Fact] public void Tercero()  { Assert.Equal(2, _paso); }
}
```

```text
  Failed Tienda.Tests.OrdenTests.Segundo [6 ms]
  Error Message:
   Assert.Equal() Failure: Values differ
Expected: 1
Actual:   0
  Passed Tienda.Tests.OrdenTests.Primero [< 1 ms]
  Failed Tienda.Tests.OrdenTests.Tercero [< 1 ms]
  Error Message:
   Assert.Equal() Failure: Values differ
Expected: 2
Actual:   1
```

En esta ejecución `Segundo` corrió antes que `Primero`. Un test que solo funciona después de otro es un test mal diseñado: cada uno debe preparar su propio estado. Existe un mecanismo para fijar el orden (`[TestCaseOrderer]`), pero tapa el problema en lugar de resolverlo.

### Paralelismo

Por defecto, **las clases de test distintas se ejecutan en paralelo y los tests dentro de una clase se ejecutan en serie**. Para verlo, dos clases con tests de 500 ms que registran la hora de inicio y fin:

```csharp
public static class Reloj { public static readonly Stopwatch Sw = Stopwatch.StartNew(); }

public class LentaA   // LentaB es igual, con un solo test T1
{
    private readonly ITestOutputHelper _o;
    public LentaA(ITestOutputHelper o) => _o = o;

    [Fact] public void T1() { _o.WriteLine($"A.T1 inicio {Reloj.Sw.ElapsedMilliseconds} ms"); Thread.Sleep(500); _o.WriteLine($"A.T1 fin {Reloj.Sw.ElapsedMilliseconds} ms"); }
    [Fact] public void T2() { /* igual, con la etiqueta A.T2 */ }
}
```

```text
 B.T1 inicio 0 ms        <- LentaB y LentaA empiezan a la vez (clases distintas)
 B.T1 fin 503 ms
 A.T2 inicio 0 ms
 A.T2 fin 503 ms
 A.T1 inicio 509 ms      <- dentro de LentaA, en serie
 A.T1 fin 1018 ms
 Total time: 1,6912 Seconds
```

`B.T1` y `A.T2` solapan; `A.T1` espera a `A.T2`. Los tres tests suman 1,5 s de espera y la ejecución completa tarda 1,7 s; serializada del todo (ver más abajo) tarda 2,2 s. Cada clase de test forma por defecto su propia **colección**: el grupo de tests que xUnit nunca ejecuta a la vez, mientras que las colecciones distintas sí se ejecutan en paralelo.

Para serializar solo algunas clases, se agrupan en la misma colección con nombre:

```csharp
[Collection("Base de datos")]
public class LentaA { /* ... */ }

[Collection("Base de datos")]
public class LentaB { /* ... */ }
```

Con ese atributo en las dos clases, el mismo experimento da `A.T2` a 510 ms y `A.T1` a 1015 ms, detrás de `B.T1`: nada solapa y el total sube a 2,2 s. Para apagar el paralelismo en todo el ensamblado hay dos vías (ambas comprobadas en v2):

```csharp
[assembly: CollectionBehavior(DisableTestParallelization = true)]
```

```json
{
  "$schema": "https://xunit.net/schema/current/xunit.runner.schema.json",
  "parallelizeTestCollections": false
}
```

El segundo es `xunit.runner.json`, que debe copiarse al directorio de salida: `<Content Include="xunit.runner.json" CopyToOutputDirectory="PreserveNewest" />` en el `.csproj`. La plantilla v3 ya lo incluye; la de v2 no. El esquema oficial de ese fichero incluye, entre otras, las claves `maxParallelThreads`, `parallelAlgorithm`, `parallelMode`, `methodDisplay`, `culture`, `stopOnFail` y `diagnosticMessages` (consultado el 2026-11-09); el detalle de cada una está en la documentación de configuración. El runner de v3 admite además `-parallelMode none` en línea de comandos.

El paralelismo es una razón más para que cada test no dependa de estado externo compartido: dos clases que escriben en la misma base de datos o en el mismo fichero fallan de forma intermitente cuando se solapan. Se agrupan en una colección (o se da a cada una su propia base), no se apaga el paralelismo de toda la suite.

## Salida, omisión y filtrado

### Salida de un test

`Console.WriteLine` no es el canal de xUnit v2: el framework inyecta un `ITestOutputHelper` en el constructor.

```csharp
using Xunit.Abstractions;   // solo en v2

public class SalidaTests
{
    private readonly ITestOutputHelper _salida;
    public SalidaTests(ITestOutputHelper salida) => _salida = salida;

    [Fact]
    public void Muestra_Salida()
    {
        _salida.WriteLine("Pedido #{0} con {1} líneas", 4711, 3);
        Assert.Equal(1, 2);
    }
}
```

```text
  Failed Tienda.Tests.SalidaTests.Muestra_Salida [6 ms]
  Error Message:
   Assert.Equal() Failure: Values differ
...
  Standard Output Messages:
 Pedido #4711 con 3 líneas
```

Con el logger `console;verbosity=detailed`, la salida de un test aparece en los fallos y en los verdes. En v3, `ITestOutputHelper` vive en el namespace `Xunit` (sin `using Xunit.Abstractions;`, que ya no existe), y el informe de un fallo la agrupa bajo `Standard output`:

```text
failed Tienda.Tests.V3Tests.Salida (22ms)
  Assert.Equal() Failure: Values differ
  Expected: 1
  Actual:   2
  Standard output
    Pedido #4711
```

Además, v3 permite capturar `Console`, `Debug` y `Trace` con `[assembly: CaptureConsole]` (según la documentación de captura de salida), y `TestContext.Current` da acceso al test en curso.

### Omitir tests

En las dos versiones, `[Fact(Skip = "motivo")]` omite el test de forma estática: aparece como *Skipped* con el motivo.

```csharp
[Fact(Skip = "Pendiente de la pasarela de pago")]
public void Confirmar_ConPagoRechazado_NoCambiaElEstado() { }
```

```text
  Skipped Tienda.Tests.VariosTests.Omitido [1 ms]
```

La decisión en tiempo de ejecución (omitir según sistema operativo, variable de entorno, servicio disponible) existe solo en v3. En v2 2.9.3, `Assert.Skip` no compila (el compilador se queja de un método `Skip` de otro tipo, `AsyncEnumerable.Skip`, porque la clase `Assert` no lo tiene). En v3:

```csharp
[Fact]
public void Pagos_ConTarjetaReal() => Assert.Skip("solo en Linux");

public static bool EsLinux => OperatingSystem.IsLinux();

[Fact(SkipUnless = nameof(EsLinux), Skip = "solo en Linux")]
public void Pagos_ConSocketUnix() { }
```

```text
skipped Tienda.Tests.V3Tests.Salta_Dinamico
  solo en Linux
skipped Tienda.Tests.V3Tests.Salta_Declarativo
  solo en Linux
```

Las dos formas dan el mismo resultado en Windows: omitido con el motivo. `SkipUnless`/`SkipWhen` apuntan a una propiedad `static bool` pública; `Assert.SkipUnless(condicion, motivo)` y `Assert.SkipWhen` son las versiones en línea. En v2, la alternativa es un paquete de terceros (por ejemplo `Xunit.SkippableFact`), que no se comprobó aquí.

Un test omitido es deuda visible en el informe; uno comentado desaparece. Omitir sin motivo escrito es el camino al test que nadie reactiva.

### `[Trait]` y filtrado

`[Trait("Clave", "valor")]` etiqueta un test; `--filter` ejecuta solo los que coinciden. Con dos tests etiquetados `Category=Unit` y `Category=Integration`:

```csharp
[Fact, Trait("Category", "Unit")]
public void Unitario() { }

[Fact, Trait("Category", "Integration")]
public void Integracion() { }
```

```text
$ dotnet test --filter "Category=Unit"
Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1, Duration: 8 ms - Tienda.Tests.dll (net10.0)

$ dotnet test --filter "Category!=Integration&FullyQualifiedName~Varios" --logger "console;verbosity=normal"
  Failed Tienda.Tests.VariosTests.ConFail [2 ms]
  Skipped Tienda.Tests.VariosTests.Omitido [1 ms]
  Passed Tienda.Tests.VariosTests.Unitario [< 1 ms]
```

Sin filtro se ejecutan los cuatro tests de esa clase. La sintaxis del filtro (VSTest, en v2) admite `=`, `!=`, `~` (contiene), `&` y `|` sobre `Category`, `FullyQualifiedName`, `DisplayName` y las claves de `[Trait]`. En v3 sobre Microsoft Testing Platform existen opciones propias, como `--filter-trait "Category=Unit"`, `--filter-class`, `--filter-method` y `--filter-display-name`, y `--filter` con la sintaxis de VSTest sigue disponible; con `dotnet run -- -trait "Category=Unit"` se filtra desde el ejecutable.

## Ejecutar desde la línea de comandos y en CI

```bash
dotnet test                                                  # toda la solución
dotnet test --filter "FullyQualifiedName~PedidoTests"        # solo una clase
dotnet test --logger "console;verbosity=detailed"            # un resultado por test, con su salida
dotnet test --logger "trx;LogFileName=resultados.trx"        # informe XML (TRX)
dotnet test --no-build                                       # reutiliza la compilación anterior
```

Con el logger `trx`, `dotnet test` imprime la ruta (`tests/Tienda.Tests/TestResults/resultados.trx`) y termina con el código de salida distinto de cero si algún test falla, que es lo que hace fallar el paso de un *pipeline*. En v3 con Microsoft Testing Platform, `dotnet test --project X` recibe las opciones del propio test (no acepta `--nologo`), y el ejecutable genera informes con `dotnet run -- -xml out.xml -trx out.trx`. La configuración del pipeline (dónde ejecutar, cómo publicar el informe TRX) está en [CI/CD](../../devops/ci-cd/README.md). La plantilla v2 incluye `coverlet.collector` para medir cobertura, que se explica en [Coverlet](Coverlet.md).

## xUnit frente a NUnit y MSTest

Los tres frameworks cubren lo esencial y todos tienen plantilla en `dotnet new` (`xunit`, `nunit`, `mstest`). Las diferencias reales son de filosofía:

| Criterio | xUnit | NUnit | MSTest |
|---|---|---|---|
| Aislamiento entre tests | Instancia nueva por test; sin `[SetUp]` | Una instancia por clase por defecto; `[SetUp]`/`[TearDown]` | Instancia nueva por test; `[TestInitialize]`/`[TestCleanup]` |
| Paralelismo | Activo por defecto entre clases | Opt-in (`[Parallelizable]`) | Opt-in (atributo de ensamblado) |
| Datos | `[Theory]` + `InlineData`/`MemberData`/`ClassData` | `[TestCase]`, `[TestCaseSource]` | `[DataRow]`, `[DynamicData]` |
| Aserciones | Métodos `Assert.*` simples | `Assert.That` con restricciones | `Assert.*` clásicos |
| Cuándo encaja | Proyectos nuevos y equipos que valoran el aislamiento forzado | Proyectos existentes con NUnit; quien prefiere `SetUp` explícito | Equipos muy atados al ecosistema Microsoft y Visual Studio |

No hay un ganador técnico: lo que importa es la coherencia dentro de la solución. Una sola herramienta por solución evita mezclar dos sintaxis de aserciones y dos ciclos de vida. Esta comparación se apoya en el conocimiento general de los tres frameworks y no se contrastó con sus documentaciones; quien migre debe revisar el comportamiento por defecto de la instancia y del paralelismo.

## Errores frecuentes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| Error de compilación `xUnit1001: Fact methods cannot have parameters` | Un `[Fact]` con parámetros | Convertirlo en `[Theory]` con datos. Si se silencia el analizador, falla en ejecución: `[Fact] methods are not allowed to have parameters. Did you mean to use [Theory]?` |
| Los tests de una clase no aparecen en `dotnet test` (ni en `--list-tests`) | La clase es `internal` (o no `public`): el analizador lo avisa como `xUnit1000: Test classes must be public` | Declarar la clase `public`. Un método de test no `public` sí se descubre y se ejecuta (comprobado en v2 2.9.3 y en v3 4.0.3) |
| Un método sin atributo no se ejecuta aunque parezca un test | Falta `[Fact]` o `[Theory]` | Añadir el atributo |
| `error CS0182: An attribute argument must be a constant expression` | Un objeto en `[InlineData]` | Pasar a `[MemberData]`, `[ClassData]` o `TheoryData<...>` |
| `Assert.Throws() Failure: Exception type was not an exact match` | El tipo lanzado es un derivado | Usar el tipo concreto o `Assert.ThrowsAny<T>` |
| `xUnit1048` / `xUnit1049` / `Tests marked as 'async void' are no longer supported` | `async void` en un test | Devolver `Task` |
| Un test pasa solo si se ejecuta tras otro; falla al ejecutarlo suelto o en CI | Estado en un campo `static` o dependencia del orden | Estado por test en el constructor; sin campos `static` mutables |
| Fallos intermitentes que desaparecen al relanzar | Clases en paralelo que comparten base de datos, fichero o puerto | Misma `[Collection]` para serializarlas o recurso propio por clase |
| `dotnet test` en un proyecto v3 falla con `Testing with VSTest target is no longer supported` | SDK 10 sin `global.json` que elija Microsoft Testing Platform | Añadir `"test": { "runner": "Microsoft.Testing.Platform" }` |

## Buenas prácticas avanzadas

- **Construcción y limpieza van en el constructor y en `Dispose`, no en campos `static`.** Una instancia por test hace que el constructor sea el `[SetUp]`. Compartir con `static` rompe el aislamiento y produce los fallos que dependen del orden; para compartir un recurso caro se declara un fixture explícito.
- **Un `[Theory]` por regla, un `[Fact]` por caso distinto.** Si el cuerpo es idéntico y cambian los datos, es una `[Theory]`; si hay ramas `if` según el dato dentro del test, son dos tests.
- **Prefiere `TheoryData<...>` a `IEnumerable<object[]>`.** Los tipos de las columnas se comprueban al compilar; con `object[]` un dato mal tipado explota al ejecutar, con un mensaje poco claro.
- **Pasa a la `[Theory]` valores que se lean en el informe.** El runner muestra cada caso con sus argumentos (`porcentaje: 51`); con un `record` grande el nombre se vuelve ilegible. Pasar el dato mínimo (el porcentaje, no el `Cupon`) y construir el objeto dentro del test mantiene el informe claro.
- **No desactives el paralelismo de toda la suite por un test conflictivo.** Se agrupa solo lo que comparte recurso en una `[Collection]`; el resto sigue en paralelo y la suite no se vuelve lenta por una clase.
- **Convierte los avisos del analizador en errores.** `xUnit1048`, `xUnit1051` y `xUnit1026` (parámetro de `[Theory]` sin usar) anticipan errores reales. Con `<TreatWarningsAsErrors>` en el proyecto de pruebas, la migración a v3 se detecta en compilación.

## Documentación oficial

- [xUnit.net: Getting started (v3)](https://xunit.net/docs/getting-started/v3/getting-started) — la creación de un proyecto con la plantilla `xunit3`, el significado de cada línea del `.csproj` y `dotnet run` sobre un test; punto de entrada para proyectos nuevos.
- [xUnit.net: migración de v2 a v3](https://xunit.net/docs/getting-started/v3/migration) — la tabla de paquetes antiguos y nuevos, los cambios de namespaces y de `async void`; para pasar un proyecto v2 a v3.
- [xUnit.net: ejecución de tests en paralelo](https://xunit.net/docs/running-tests-in-parallel) — los modos, los algoritmos y el uso de colecciones; para diagnosticar fallos intermitentes.
- [Microsoft Learn: pruebas unitarias en C# con xUnit y `dotnet test`](https://learn.microsoft.com/dotnet/core/testing/unit-testing-with-dotnet-test) — la guía de Microsoft con una solución de ejemplo; útil como recorrido por el flujo `dotnet new` / `dotnet test`.

---

*En resumen: xUnit crea una instancia nueva de la clase por cada test, ejecuta las clases en paralelo y deja el orden sin garantía; escribe cada test para que no necesite ni compartir estado ni saber quién corrió antes.*
