# Coverlet

## ¿Qué es?

Coverlet es el motor de **cobertura de código** de referencia en .NET: instrumenta los ensamblados mientras se ejecutan los tests y registra qué líneas, ramas y métodos del código de producción se ejecutaron. Se distribuye en varios paquetes NuGet (`coverlet.collector`, `coverlet.msbuild`, `coverlet.mtp`) que escriben un informe en formatos estándar (Cobertura, OpenCover, lcov, JSON).

## ¿Por qué existe?

Una suite en verde dice que nada de lo comprobado falló; no dice cuánto código se comprobó. Sin medición, la respuesta a «¿qué parte del dominio pisan los tests?» es una intuición, y las zonas sin probar (el `catch` que nunca se ejecuta, la regla de validación que nadie llama) se descubren en producción.

> Es el control de asistencia de una clase: apunta quién estuvo en el aula, no quién atendió. Una persona presente y dormida cuenta como asistencia; una línea ejecutada y sin aserción, como cobertura.

Esa analogía es también el límite de la herramienta: la cobertura detecta con fiabilidad el código que **ningún test ejecuta**, y es incapaz de detectar el código que un test ejecuta sin comprobar nada.

## ¿Cuándo y para qué se usa?

En una tienda online, el dominio (`Pedido`, `Cupon`) concentra reglas de negocio: un pedido sin líneas no se confirma, un cupón no supera el 50 %. Coverlet responde a dos preguntas distintas:

- **En local**, para encontrar huecos: abrir el informe tras añadir una regla y ver en rojo la rama que ningún test recorre.
- **En CI**, para vigilar la tendencia: que un cambio grande no entre con su lógica sin ejecutar, o que el porcentaje no caiga por debajo de un mínimo acordado.

Los tests que producen la cobertura son los de [xUnit](xUnit.md); qué tipo de test conviene en cada capa está en [Tipos de tests](Tipos-de-tests.md).

## Qué mide la cobertura

Coverlet mide tres cosas, que el informe da por separado:

| Métrica | Qué cuenta | Cuándo cuenta como cubierta |
|---|---|---|
| **Línea** (*line*) | Líneas de código con instrucciones ejecutables | La línea se ejecutó al menos una vez |
| **Rama** (*branch*) | Cada salida posible de una decisión (`if`, `?:`, `&&`, `switch`, `is < 0 or > 50`) | Cada salida se tomó al menos una vez |
| **Método** (*method*) | Métodos y propiedades | El método se ejecutó al menos una vez |

El dominio que usan todos los ejemplos es una versión reducida de `Tienda.Dominio`, con el cupón máximo del 50 %. `LineaPedido` y `Cupon` están en `src/Tienda.Dominio/Pedido.cs`:

```csharp
namespace Tienda.Dominio;

public enum EstadoPedido { Borrador, Confirmado, Pagado, Cancelado }

public record LineaPedido(string Sku, int Cantidad, decimal PrecioUnitario)
{
    public decimal Subtotal => Cantidad * PrecioUnitario;
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
}

public class Pedido
{
    private readonly List<LineaPedido> _lineas = [];

    public Pedido(int numero) => Numero = numero;

    public int Numero { get; }
    public EstadoPedido Estado { get; private set; } = EstadoPedido.Borrador;
    public Cupon? Cupon { get; private set; }
    public IReadOnlyList<LineaPedido> Lineas => _lineas;

    public void AgregarLinea(string sku, int cantidad, decimal precioUnitario) =>
        _lineas.Add(new LineaPedido(sku, cantidad, precioUnitario));

    public void AplicarCupon(Cupon cupon)
    {
        if (Estado != EstadoPedido.Borrador)
            throw new InvalidOperationException("Solo se puede aplicar un cupón a un pedido en borrador.");
        Cupon = cupon;
    }

    public decimal Total()
    {
        var bruto = _lineas.Sum(l => l.Subtotal);
        return Cupon is null ? bruto : bruto - bruto * Cupon.Porcentaje / 100m;
    }

    public void Confirmar()
    {
        if (_lineas.Count == 0)
            throw new InvalidOperationException("Un pedido sin líneas no se puede confirmar.");
        Estado = EstadoPedido.Confirmado;
    }
}
```

La cobertura de **línea** es la más tosca: una línea con varias decisiones cuenta como cubierta en cuanto una de ellas se ejecuta. La de **rama** es más exigente y se ve en [su propia sección](#la-línea-cubierta-con-una-rama-sin-probar). La de **método** es la más gruesa, útil para detectar métodos que nadie llama.

## Lo que la cobertura no garantiza

Dos suites sobre el mismo dominio, ambas con el 100 % de líneas, ramas y métodos.

La primera ejecuta todo y no comprueba nada (`PedidoSinAserciones.cs`):

```csharp
public class PedidoSinAserciones
{
    [Fact]
    public void Recorre_el_dominio()
    {
        var sinCupon = new Pedido(4711);
        sinCupon.AgregarLinea("CAM-001", 2, 19.99m);
        sinCupon.Total();

        var conCupon = new Pedido(4712);
        conCupon.AgregarLinea("CAM-001", 2, 19.99m);
        conCupon.AplicarCupon(new Cupon("PROMO", 50));
        conCupon.Total();
        conCupon.Confirmar();
        _ = (conCupon.Numero, conCupon.Estado, conCupon.Cupon!.Codigo, conCupon.Lineas);

        try { conCupon.AplicarCupon(new Cupon("TARDE", 10)); } catch (InvalidOperationException) { }
        try { new Pedido(4713).Confirmar(); } catch (InvalidOperationException) { }
        try { _ = new Cupon("ABUSO", 80); } catch (ArgumentOutOfRangeException) { }
    }
}
```

La segunda tiene ocho tests con aserciones (`PedidoConAserciones.cs`, abreviada a cuatro de los ocho; los otros cuatro siguen el mismo patrón):

```csharp
public class PedidoConAserciones
{
    [Fact]
    public void Total_ConCuponDel50_DescuentaLaMitad()
    {
        var pedido = new Pedido(4711);
        pedido.AgregarLinea("CAM-001", 2, 50m);
        pedido.AplicarCupon(new Cupon("PROMO", 50));

        Assert.Equal(50m, pedido.Total());
    }

    [Fact]
    public void Confirmar_SinLineas_Lanza()
    {
        var ex = Assert.Throws<InvalidOperationException>(() => new Pedido(4711).Confirmar());

        Assert.Equal("Un pedido sin líneas no se puede confirmar.", ex.Message);
    }

    [Theory]
    [InlineData(51)]
    [InlineData(-1)]
    public void Cupon_FueraDeRango_Lanza(int porcentaje)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => new Cupon("ABUSO", porcentaje));
    }

    // ... Total_SinCupon_EsLaSumaDeLasLineas, AplicarCupon_SobrePedidoConfirmado_Lanza,
    //     Confirmar_ConLineas_PasaAConfirmado, AplicarCupon_EnBorrador_GuardaElCuponEnElPedido
}
```

Ejecutadas por separado con `--filter` (el [filtrado](xUnit.md#trait-y-filtrado) es el de xUnit), la medición es la misma:

| | `PedidoSinAserciones` (1 test) | `PedidoConAserciones` (8 tests) |
|---|---|---|
| Línea | 100 % (32 de 32) | 100 % (32 de 32) |
| Rama | 100 % (12 de 12) | 100 % (12 de 12) |
| Método | 100 % (14 de 14) | 100 % (14 de 14) |

Para ver la diferencia se **rompe el dominio a propósito** (una mutación manual) y se vuelve a ejecutar cada suite.

**Mutación 1**: el descuento divide entre 1000 en lugar de entre 100 (`bruto * Cupon.Porcentaje / 1000m`), de modo que un cupón del 50 % descuenta el 5 %:

```text
# PedidoSinAserciones
Passed!  - Failed:     0, Passed:     1, Skipped:     0, Total:     1, Duration: 196 ms - Tienda.Tests.dll (net10.0)
# PedidoConAserciones
  Failed Tienda.Tests.PedidoConAserciones.Total_ConCuponDel50_DescuentaLaMitad [11 ms]
   Assert.Equal() Failure: Values differ
Expected: 50
Actual:   95
Failed!  - Failed:     1, Passed:     7, Skipped:     0, Total:     8, Duration: 168 ms - Tienda.Tests.dll (net10.0)
```

**Mutación 2**: el límite del cupón sube del 50 % al 90 % (`porcentaje is < 0 or > 90`). La suite sin aserciones sigue en verde con `Passed: 1`; la otra falla en `Cupon_FueraDeRango_Lanza(porcentaje: 51)`.

Las dos suites miden lo mismo y valen cosas distintas: la primera es incapaz de fallar mientras el código no lance una excepción inesperada. Un informe de cobertura al 100 % es compatible con una suite que no protege nada, y por eso el porcentaje no se usa como medida de calidad de los tests. La herramienta que sí mide si los tests detectan cambios es la **prueba de mutación** (aquí se hizo a mano, dos mutantes); existen herramientas que la automatizan, como Stryker.NET, que no se ejecutó (no se comprobó su estado con .NET 10).

## Medir con `coverlet.collector`

### Primera medición

Las salidas citadas provienen de ejecuciones reales con el SDK de .NET 10.0.401, xUnit 2.9.3 (y `xunit.v3` 4.0.3 donde se indica) y ReportGenerator 5.5.12, ejecutadas el 2026-11-10, con las rutas abreviadas.

El paquete `coverlet.collector` es un *data collector* de VSTest, el runner que usa `dotnet test` con xUnit v2. La plantilla `dotnet new xunit` lo incluye (con el SDK 10.0.401, la versión `6.0.4`; la última estable de la línea actual es la `10.1.0`, comprobada el 2026-11-10 en NuGet; las dos funcionan igual con `net10.0`). Para actualizarlo:

```bash
dotnet add tests/Tienda.Tests package coverlet.collector
```

Se activa con un flag de `dotnet test`:

```bash
dotnet test --collect:"XPlat Code Coverage"
```

```text
Passed!  - Failed:     0, Passed:     9, Skipped:     0, Total:     9, Duration: 189 ms - Tienda.Tests.dll (net10.0)

Attachments:
  ...\tests\Tienda.Tests\TestResults\54e352a7-7b6c-4e89-8d4c-b198e78f144c\coverage.cobertura.xml
```

`dotnet test` no imprime ninguna tabla de porcentajes: solo deja el fichero en `TestResults/<GUID>/coverage.cobertura.xml`. El GUID cambia en cada ejecución, de modo que la ruta no es estable y todos los scripts localizan el fichero con un comodín (`**/coverage.cobertura.xml`). `--results-directory ./cov` mueve la carpeta, pero el GUID se mantiene.

### Configurar con un `.runsettings`

Las opciones del collector van en un fichero `.runsettings` que se pasa con `--settings`. El fichero `coverlet.runsettings`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<RunSettings>
  <DataCollectionRunSettings>
    <DataCollectors>
      <DataCollector friendlyName="XPlat Code Coverage">
        <Configuration>
          <Format>cobertura,opencover,lcov,json</Format>
        </Configuration>
      </DataCollector>
    </DataCollectors>
  </DataCollectionRunSettings>
</RunSettings>
```

```bash
dotnet test --settings coverlet.runsettings --collect:"XPlat Code Coverage"
```

Las opciones que se tocan de verdad: `Format`, `Include`, `Exclude`, `ExcludeByFile`, `ExcludeByAttribute`, `IncludeTestAssembly`, `SingleHit`, `SkipAutoProps`. La lista completa está en la [documentación de integración con VSTest](https://github.com/coverlet-coverage/coverlet/blob/master/Documentation/VSTestIntegration.md).

## Tres formas de usar Coverlet en .NET 10

| | `coverlet.collector` | `coverlet.msbuild` | `coverlet.mtp` (Microsoft Testing Platform) |
|---|---|---|---|
| Runner | VSTest | VSTest (se engancha al build de MSBuild) | Microsoft Testing Platform |
| Se activa con | `--collect:"XPlat Code Coverage"` | `-p:CollectCoverage=true` | `--coverlet` |
| Opciones en | `.runsettings` | propiedades MSBuild (`-p:` o `.csproj`) | flags `--coverlet-*` o `testconfig.json` |
| Tabla de porcentajes en consola | No | Sí | No |
| Umbral que rompe el build | No | Sí (`Threshold`) | Sí (`--coverlet-threshold`) |
| Encaja con | xUnit v2 y plantilla `dotnet new xunit` | xUnit v2 cuando se quiere el umbral en un solo comando | xUnit v3 |

Las tres producen el mismo tipo de informe. En el proyecto de ejemplo, con tres configuraciones (el mismo código y los mismos 9 tests):

| Herramienta | Líneas cubiertas / válidas | Ramas cubiertas / válidas |
|---|---|---|
| `coverlet.collector` 10.1.0 (xUnit v2) | 32 de 34 | 12 de 12 |
| `coverlet.mtp` 10.1.0 (xUnit v3) | 26 de 28 | 12 de 12 |
| `Microsoft.Testing.Extensions.CodeCoverage` 18.12.0 (xUnit v3) | 29 de 32 | 14 de 16 |

Los totales difieren entre herramientas aunque el código es el mismo (cada una decide qué cuenta como línea o rama instrumentable); **un porcentaje solo se compara con otro de la misma herramienta y la misma configuración**. No se investigó la causa exacta de cada diferencia.

### `coverlet.msbuild`

Con el paquete `coverlet.msbuild` en el proyecto de tests (sin `coverlet.collector`), la cobertura la activa MSBuild y `dotnet test` imprime la tabla al terminar:

```bash
dotnet add tests/Tienda.Tests package coverlet.msbuild
dotnet test -p:CollectCoverage=true
```

```text
Passed!  - Failed:     0, Passed:     9, Skipped:     0, Total:     9, Duration: 333 ms - Tienda.Tests.dll (net10.0)
  Generating report '...\tests\Tienda.Tests\coverage.json'

+----------------+--------+--------+--------+
| Module         | Line   | Branch | Method |
+----------------+--------+--------+--------+
| Tienda.Dominio | 94.11% | 100%   | 87.5%  |
+----------------+--------+--------+--------+

+---------+--------+--------+--------+
|         | Line   | Branch | Method |
+---------+--------+--------+--------+
| Total   | 94.11% | 100%   | 87.5%  |
+---------+--------+--------+--------+
| Average | 94.11% | 100%   | 87.5%  |
+---------+--------+--------+--------+
```

Sin más opciones escribe `coverage.json` en la carpeta del proyecto de tests. Las propiedades `CoverletOutputFormat` y `CoverletOutput` eligen formato y ruta: `-p:CoverletOutputFormat=cobertura -p:CoverletOutput=../../cov/` deja `cov/coverage.cobertura.xml` en una ruta fija, sin GUID.

> En Git Bash de Windows, escribe `-p:` en lugar de `/p:`: la shell convierte `/p:CollectCoverage=true` en una ruta y `dotnet test` responde `MSBUILD : error MSB1009: Project file does not exist. Switch: p:CollectCoverage=true`.

### Microsoft Testing Platform (xUnit v3)

Un proyecto xUnit v3 es un ejecutable que corre sobre Microsoft Testing Platform (MTP); con el SDK 10 se elige ese runner en `global.json` y `dotnet test` recibe el proyecto con `--project` (detalle en [xUnit](xUnit.md#dos-versiones-v2-y-v3)). `--collect` y `coverlet.collector` son de VSTest, y `coverlet.mtp` es, según su documentación, la implementación de la funcionalidad del collector para MTP. Hay dos extensiones de cobertura, y ambas se comprobaron con un proyecto `xunit.v3` 4.0.3:

**`coverlet.mtp`** (la versión de Coverlet para MTP, licencia MIT, 10.1.0):

```bash
dotnet add tests/Tienda.Tests.V3 package coverlet.mtp
dotnet test --project tests/Tienda.Tests.V3 --coverlet
```

Escribe en `TestResults/` dos ficheros por defecto, `coverage.<marca de tiempo>.json` y `coverage.cobertura.<marca de tiempo>.xml`. Sus opciones (`--coverlet-output-format`, `--coverlet-exclude-by-file`, `--coverlet-threshold`...) son equivalentes a las del collector y se ven con `--help`.

**`Microsoft.Testing.Extensions.CodeCoverage`** (la extensión de Microsoft, 18.12.0; el paquete pide aceptar una licencia propia de Microsoft, sin licencia de código abierto):

```bash
dotnet add tests/Tienda.Tests.V3 package Microsoft.Testing.Extensions.CodeCoverage
dotnet test --project tests/Tienda.Tests.V3 --coverage --coverage-output-format cobertura --coverage-output tienda.cobertura.xml
```

Sin la extensión instalada, `--coverage` no genera ningún informe: la ejecución observada terminó con `total: 0` y `Test run completed with non-success exit code: 5` (no se investigó la causa). Con ella, el formato por defecto es un fichero binario `.coverage` (propio de Microsoft, se abre con Visual Studio); `--coverage-output-format cobertura` genera el XML estándar.

La elección sigue la del runner: xUnit v2 con VSTest, `coverlet.collector` (o `coverlet.msbuild` si se quiere el umbral integrado); xUnit v3 con MTP, `coverlet.mtp` o la extensión de Microsoft. No se probó combinar dos extensiones en el mismo proyecto.

## Formatos de salida y cómo leerlos

Los cuatro formatos se pidieron a la vez con `<Format>cobertura,opencover,lcov,json</Format>`. Salen cuatro ficheros en la misma carpeta con GUID:

```text
coverage.cobertura.xml   9569 bytes
coverage.opencover.xml  20346 bytes
coverage.info            2634 bytes      <- lcov
coverage.json            5568 bytes
```

| Formato | Para qué se usa | Cómo se lee a mano |
|---|---|---|
| **Cobertura** (`coverage.cobertura.xml`) | Es el estándar: lo entienden ReportGenerator, GitHub Actions, Azure DevOps, SonarQube | Un `<coverage line-rate=... branch-rate=...>` por ensamblado y un `<line number hits>` por línea |
| **OpenCover** (`coverage.opencover.xml`) | Herramientas que esperan ese esquema (por ejemplo, SonarQube con su propio importador) | `<SequencePoint vc=... sl=...>` (visitas y línea) y `<BranchPoint>` |
| **lcov** (`coverage.info`) | Ecosistema de Linux y editores que pintan cobertura en el margen | Texto plano: `DA:` por línea, `BRDA:` por rama |
| **JSON** (`coverage.json`) | Formato propio de Coverlet; el único que permite **fusionar** varias ejecuciones | Ensamblado → fichero → clase → método → `Lines` y `Branches` |

La misma línea (`bruto - ... : bruto`, la línea 48 de `Pedido.cs`) en Cobertura y en lcov:

```xml
<line number="48" hits="4" branch="True" condition-coverage="100% (2/2)">
```

```text
FN:45,System.Decimal Tienda.Dominio.Pedido::Total()
FNDA:4,System.Decimal Tienda.Dominio.Pedido::Total()
BRDA:48,50,0,2
BRDA:48,50,1,2
```

En Cobertura, `hits` son las veces que se ejecutó la línea y `condition-coverage` la proporción de ramas tomadas. En lcov, `FNDA:4` es el número de llamadas a `Total()` y cada `BRDA:línea,bloque,rama,veces` es una rama con sus visitas (aquí, 2 y 2: las dos salidas del operador `?:` se tomaron). Las rutas del XML son absolutas, por eso conviene generar el informe en la máquina que ejecutó los tests o usar `-sourcedirs` de ReportGenerator.

El formato JSON de Coverlet permite acumular varias ejecuciones (de proyectos de test distintos, por ejemplo) en un único resultado; el flag y el detalle están en la documentación de cada integración.

## ReportGenerator: del XML al informe legible

Un XML de cobertura no se lee. **ReportGenerator** (herramienta .NET aparte, Apache 2.0, versión 5.5.12 en la comprobación del 2026-11-10) lo convierte en un informe HTML navegable, en un resumen de texto o en una tabla Markdown:

```bash
dotnet tool install -g dotnet-reportgenerator-globaltool
reportgenerator -reports:"tests/**/coverage.cobertura.xml" -targetdir:coveragereport -reporttypes:"Html;TextSummary;MarkdownSummaryGithub"
```

`-reports` acepta comodines, de modo que da igual el GUID. `coveragereport/index.html` muestra cada fichero con las líneas cubiertas en verde y las no cubiertas en rojo, y `Summary.txt` (`TextSummary`) resume el total y la tabla por clase:

```text
Summary
  Classes: 5
  Files: 3
  Line coverage: 94.1%
  Covered lines: 32
  Uncovered lines: 2
  Coverable lines: 34
  Branch coverage: 100% (12 of 12)
  Method coverage: 87.5% (14 of 16)

Tienda.Dominio                           94.1%
  Tienda.Dominio.Cupon                    100%
  Tienda.Dominio.Generado.PedidoMapper      0%
  Tienda.Dominio.Informes                   0%
  Tienda.Dominio.LineaPedido              100%
  Tienda.Dominio.Pedido                   100%
```

La tabla con ramas sale en `SummaryGithub.md` (`MarkdownSummaryGithub`), pensada para pegarla en el resumen de un *job* de GitHub Actions:

```text
|**Name**|**Line**|**Branch**|
|:---|---:|---:|
|**Tienda.Dominio**|**94.1%**|**100%**|
|Tienda.Dominio.Cupon|100%|100%|
|Tienda.Dominio.Generado.PedidoMapper|0%||
|Tienda.Dominio.Informes|0%||
|Tienda.Dominio.LineaPedido|100%||
|Tienda.Dominio.Pedido|100%|100%|
```

Las clases sin decisiones (`LineaPedido`, `Informes`) dejan la columna de rama vacía. En esa versión, el Markdown muestra `Method coverage: [Feature is only available for sponsors]` y la cobertura de método solo aparece completa en `TextSummary` y en el HTML. Para fusionar los resultados de varios proyectos de test, `-reports` acepta varios ficheros separados por `;`.

## La línea cubierta con una rama sin probar

El operador `?:` de `Total()` ocupa una línea con dos salidas: sin cupón (`bruto`) y con cupón (el descuento). Si el único test que se ejecuta usa cupón:

```bash
dotnet test --collect:"XPlat Code Coverage" --filter "FullyQualifiedName~Total_ConCuponDel50"
```

el informe Cobertura dice, para el método `Total`:

```xml
<method name="Total" signature="()" line-rate="1" branch-rate="0.5" complexity="2">
  <lines>
    <line number="46" hits="1" branch="False" />
    <line number="47" hits="2" branch="False" />
    <line number="48" hits="1" branch="True" condition-coverage="50% (1/2)">
```

`line-rate="1"`: todas las líneas del método se ejecutaron. `branch-rate="0.5"` y `condition-coverage="50% (1/2)"`: de las dos salidas de la línea 48, solo se tomó una. Ningún test comprueba un pedido **sin** cupón y la cobertura de línea no lo delata. Un fallo en `bruto` pasaría inadvertido.

La cobertura de rama es la métrica que merece mirarse en las reglas de negocio con condiciones (`if`, `?:`, `&&`, `is < 0 or > 50`), y la de línea sirve como suelo. Lo mismo ocurre con el `is < 0 or > 50` del constructor de `Cupon`: ese predicado genera seis ramas (`condition-coverage="100% (6/6)"` en los informes citados).

## Excluir código de la medición

Hay código que no merece test: el generado, el de arranque, el de diagnóstico. Se excluye **de la medición**, no del proyecto. Al dominio se añaden tres ficheros para verlo: `Informes.cs` (con lógica real y sin test), `Generado/PedidoMapper.g.cs` (código generado) y `Diagnostico.cs` marcado con `[ExcludeFromCodeCoverage]`:

```csharp
using System.Diagnostics.CodeAnalysis;

namespace Tienda.Dominio;

[ExcludeFromCodeCoverage]
public static class Diagnostico
{
    public static string Resumen(Pedido pedido) =>
        $"Pedido #{pedido.Numero}: {pedido.Lineas.Count} líneas, estado {pedido.Estado}";
}
```

El atributo `[ExcludeFromCodeCoverage]` se respeta **por defecto**, sin configurar nada: en el informe de la sección anterior, `Diagnostico` no aparece. Para excluir por fichero o con otros atributos hay que configurarlo:

```xml
<Configuration>
  <Format>cobertura</Format>
  <ExcludeByFile>**/Generado/*.cs</ExcludeByFile>
  <ExcludeByAttribute>ExcludeFromCodeCoverage,GeneratedCode</ExcludeByAttribute>
</Configuration>
```

Con ese `.runsettings` el informe pasa de 94,1 % a 96,9 % y `PedidoMapper` desaparece; `Informes` sigue en 0 %, porque no está excluida y es código real sin probar:

```text
Tienda.Dominio                 96.9%
  Tienda.Dominio.Cupon          100%
  Tienda.Dominio.Informes         0%
  Tienda.Dominio.LineaPedido    100%
  Tienda.Dominio.Pedido         100%
```

| Opción | Qué excluye | Ejemplo |
|---|---|---|
| `ExcludeByAttribute` | Clases y métodos con el atributo | `ExcludeFromCodeCoverage,GeneratedCode` |
| `ExcludeByFile` | Ficheros por *glob* | `**/Generado/*.cs`, `**/Migrations/*.cs` |
| `Exclude` | Ensamblados o tipos con filtro `[Ensamblado]Tipo` | `[Tienda.Dominio]Tienda.Dominio.Informes` |
| `Include` | Lo contrario: solo mide lo que coincide | `[Tienda.Dominio]*` |

Con `coverlet.msbuild` son las mismas opciones como propiedades (`"-p:ExcludeByFile=**/Generado/*.cs"`, `"-p:Exclude=[Tienda.Dominio]Tienda.Dominio.Informes"`) y, con las dos exclusiones del ejemplo, el módulo pasa al 100 % en línea, rama y método. `[ExcludeFromCodeCoverage]` admite desde .NET 5 la propiedad `Justification`, que es el sitio para escribir el motivo de la exclusión.

## Umbrales: que el build falle por debajo de un mínimo

Un umbral convierte el porcentaje en una regla: si baja, el paso de CI se pone en rojo aunque todos los tests pasen.

### Con `coverlet.msbuild`

```bash
dotnet test -p:CollectCoverage=true -p:Threshold=95 -p:ThresholdType=line
```

```text
Passed!  - Failed:     0, Passed:     9, Skipped:     0, Total:     9, Duration: 217 ms - Tienda.Tests.dll (net10.0)
...coverlet.msbuild.targets(73,5): error : The minimum line coverage is below the specified 95
```

Los 9 tests pasan, y el comando termina con código de salida 1 por el umbral (94,11 % frente a 95 %). Con `-p:Threshold=94` pasa y el código de salida es 0.

- `ThresholdType`: `line`, `branch` o `method`. Se pueden combinar (`line,branch,method`); en un shell que trate la coma como separador, se escribe como `line%2Cbranch%2Cmethod`: con `-p:ThresholdType="line,branch,method"` sin escapar, MSBuild respondió `MSBUILD : error MSB1006: Property is not valid.`
- `ThresholdStat`: `minimum` (cada ensamblado debe cumplirlo, el valor por defecto), `total` (la cobertura combinada de todos) o `average`. Con `-p:ThresholdStat=total` y umbral 95 el mensaje cambia a `The total line coverage is below the specified 95`.
- `Threshold` también acepta una lista, uno por tipo: `Threshold="80,100,70"` con `ThresholdType="line,branch,method"` (según la documentación; solo se ejecutó el umbral único).

### Con `coverlet.collector`: no existe

El collector **no tiene umbral**. Se comprobó: con `--collect:"XPlat Code Coverage" -p:Threshold=99`, la ejecución termina con `Passed!` y código de salida 0, porque `Threshold` es una propiedad que solo lee `coverlet.msbuild`. Lo mismo ocurre con `-p:CollectCoverage=true`: el collector la ignora sin avisar y no imprime ninguna tabla. Con el collector, el umbral se comprueba fuera de Coverlet: un paso del pipeline que lea `line-rate` del Cobertura o una herramienta que lo compare (SonarQube, Codecov, la acción que se use para el informe).

### Con `coverlet.mtp`

```bash
dotnet test --project tests/Tienda.Tests.V3 --coverlet --coverlet-threshold 99 --coverlet-threshold-type line,branch
```

```text
Exit code: 14
Test run summary: Failed!
  error: 1
  total: 9
  succeeded: 9
```

Los 9 tests pasan, el resumen sale con `Failed!` y un `error: 1`, y el código de salida es 14 (los códigos de salida de MTP se listan en [aka.ms/testingplatform/exitcodes](https://aka.ms/testingplatform/exitcodes)). Tiene los mismos `--coverlet-threshold-type` y `--coverlet-threshold-stat` (`total`, `average`, `minimum`).

## En CI

Un paso de GitHub Actions que mide con el collector, genera el informe con ReportGenerator, lo publica en el resumen del *job* y sube el HTML como artefacto (YAML **no ejecutado**: los comandos `dotnet test` y `reportgenerator` sí se ejecutaron en local, con `--results-directory ./cov` y el informe en `cov/report`):

```yaml
- name: Tests con cobertura
  run: dotnet test --no-restore --collect:"XPlat Code Coverage" --results-directory ./cov

- name: Informe de cobertura
  run: |
    dotnet tool install -g dotnet-reportgenerator-globaltool
    reportgenerator "-reports:cov/**/coverage.cobertura.xml" -targetdir:cov/report -reporttypes:"Html;MarkdownSummaryGithub"
    cat cov/report/SummaryGithub.md >> "$GITHUB_STEP_SUMMARY"

- uses: actions/upload-artifact@v4
  with:
    name: cobertura-html
    path: cov/report
```

El *job* completo (restauración, caché de paquetes, matriz de sistemas operativos) está en [GitHub Actions](../../devops/ci-cd/GitHub-Actions.md); el concepto general de *pipeline*, en [CI/CD](../../devops/ci-cd/CI-CD.md).

## El porcentaje no es el objetivo

Cuando una medida se convierte en objetivo deja de ser una buena medida (ley de Goodhart). Con un «mínimo del 80 %» obligatorio, la vía más barata para subir el número es la suite `PedidoSinAserciones`: tests que recorren el código sin comprobar nada. Esa suite pasó los umbrales de línea, rama y método y no detectó ninguno de los dos mutantes.

La cobertura es útil en sentido inverso: **lo que está en rojo es información, lo que está en verde no garantiza nada**. Preguntas útiles son «¿qué regla de negocio está en rojo?» y «¿qué rama del `Cupon` ningún test recorre?»; una pregunta inútil es «¿cuánto tenemos?».

| Decisión | Recomendación | Motivo |
|---|---|---|
| ¿Umbral global en CI? | Sí, **justo por debajo del valor real** y sin subirlo por decreto | Evita regresiones (un trinquete); un umbral muy por encima de la realidad se desactiva con la primera urgencia |
| ¿Qué tipo de umbral? | Rama (`branch`) o línea y rama a la vez, no solo línea | La línea no ve la rama que falta |
| ¿Un 100 % obligatorio? | No | Empuja a tests sin aserciones y a excluir código para llegar |
| ¿Umbral por proyecto? | Solo en el dominio y la lógica de negocio, donde hay reglas | En el arranque (`Program.cs`), los DTO y las migraciones, el número no informa de nada |
| ¿Un umbral sobre el código **nuevo** de una PR? | Sí, si la herramienta de revisión lo permite (SonarQube, Codecov) | Mide lo que se acaba de escribir, sin cargar con la historia |
| ¿Cómo se sabe si los tests detectan fallos? | Prueba de mutación (manual o con Stryker.NET) en las reglas críticas | Es lo único que mide si un test falla cuando el código se rompe |

Por último, la cobertura no distingue el tipo de test. Una clase al 100 % cubierta solo por tests de integración lentos y una cubierta por tests unitarios rápidos puntúan igual; el reparto por tipo está en [Tipos de tests](Tipos-de-tests.md).

## Errores frecuentes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `dotnet test --collect:"XPlat Code Coverage"` pasa en verde y no hay `coverage.cobertura.xml`; en la salida: `Data collection : Unable to find a datacollector with friendly name 'XPlat Code Coverage'.` y `Data collection : Could not find data collector 'XPlat Code Coverage'` | El proyecto de tests no tiene `coverlet.collector` | `dotnet add package coverlet.collector`. El código de salida es 0: solo la ausencia del fichero delata el problema |
| No se encuentra el fichero: `TestResults/54e352a7-7b6c-4e89-8d4c-b198e78f144c/coverage.cobertura.xml` | El collector crea una carpeta con GUID por ejecución | Usar un comodín (`**/coverage.cobertura.xml`) o `coverlet.msbuild` con `CoverletOutput` para una ruta fija |
| Ningún ensamblado en el informe; ReportGenerator imprime `No assemblies have been covered.` | Un filtro `Include` que no coincide (con `[Tienda.Domino]*` en lugar de `[Tienda.Dominio]*`, el XML sale con `<packages />` vacío y `lines-valid="0"`) | Revisar el nombre exacto del ensamblado en `Include`/`Exclude`; el informe vacío no es un error de Coverlet |
| La cobertura **sube** porque falta un proyecto entero | Coverlet solo mide los ensamblados que están en la salida del proyecto de tests. Un `Tienda.Infra` que el proyecto de tests no referencia **no aparece** en el informe, ni con 0 % | Referenciar el proyecto desde los tests (`dotnet add reference`). Con la referencia y sin que nadie lo use, aparece con `line-rate="0"`: ese 0 % es el dato correcto |
| La cobertura de un proyecto de API es 0 % aunque los tests lo ejercitan | Los tests llaman a la API **en otro proceso** (un contenedor, un `dotnet run` lanzado aparte): la instrumentación está en el proceso de los tests | Usar el host en proceso (`WebApplicationFactory`, ver [WebApplicationFactory](WebApplicationFactory.md)). Esta fila describe cómo funciona la instrumentación y no se reprodujo con un proyecto de API |
| `-p:Threshold=80` no rompe el build | Se usa `coverlet.collector`, que no tiene umbral | Cambiar a `coverlet.msbuild` o `coverlet.mtp`, o comprobar el XML en el pipeline |
| `MSBUILD : error MSB1009: Project file does not exist. Switch: p:CollectCoverage=true` | Git Bash convierte `/p:` en una ruta | Escribir `-p:` |
| `--coverage` termina con `Test run completed with non-success exit code: 5` y `total: 0` | Proyecto MTP (xUnit v3) sin la extensión de cobertura | Añadir `coverlet.mtp` (y `--coverlet`) o `Microsoft.Testing.Extensions.CodeCoverage` (y `--coverage`) |
| `--collect:"XPlat Code Coverage"` en un proyecto xUnit v3 con MTP no genera cobertura (no se ejecutó este caso) | El collector es de VSTest y el runner es otro | Usar `coverlet.mtp` |

## Buenas prácticas avanzadas

- **Mira la rama, no la línea.** Una línea con `?:`, `&&` o `is < 0 or > 50` cuenta como cubierta con una sola salida; el `condition-coverage="50% (1/2)"` del Cobertura es el aviso. Empieza por las reglas del dominio.
- **Comprueba la herramienta, no solo el número.** `coverlet.collector`, `coverlet.mtp` y la extensión de Microsoft dieron tres totales distintos con el mismo código y los mismos tests. Fija una sola herramienta y configuración por solución, y compara tendencias (el delta de una PR), no valores absolutos entre equipos.
- **Excluye con motivo y a la vista.** `[ExcludeFromCodeCoverage]` se lee en la revisión del código; un `ExcludeByFile` en un `.runsettings` pasa desapercibido. Si una exclusión no tiene motivo escrito, desvirtúa el número.
- **Rompe el dominio para validar la suite.** Cambia a mano una regla crítica (el 50 % del cupón, la condición de `Confirmar`) y ejecuta los tests: si siguen en verde, el hueco está en las aserciones, no en la cobertura. Es la prueba de mutación en pequeño.
- **Un umbral como trinquete.** Fíjalo en el valor real redondeado hacia abajo y súbelo cuando suba la cobertura; con un valor aspiracional, el equipo lo desactiva el primer viernes con prisas y no vuelve.
- **Guarda el Cobertura y regenera el HTML.** El XML es el artefacto de verdad (se puede comparar entre ejecuciones y cargar en SonarQube); el HTML se reconstruye en segundos con `reportgenerator`.

## Documentación oficial

- [Coverlet: documentación de la integración con VSTest](https://github.com/coverlet-coverage/coverlet/blob/master/Documentation/VSTestIntegration.md) — todas las opciones del `.runsettings` (filtros, exclusiones, formatos). Primera parada para `coverlet.collector`.
- [Coverlet: integración con MSBuild](https://github.com/coverlet-coverage/coverlet/blob/master/Documentation/MSBuildIntegration.md) — las propiedades `Threshold`, `ThresholdType`, `ThresholdStat` y las de salida de `coverlet.msbuild`.
- [Coverlet: integración con Microsoft Testing Platform](https://github.com/coverlet-coverage/coverlet/blob/master/Documentation/Coverlet.MTP.Integration.md) — los flags `--coverlet-*` y el `testconfig.json` de `coverlet.mtp`, para proyectos xUnit v3.
- [Microsoft Learn: cobertura de código en .NET](https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-code-coverage) — la guía de Microsoft con Coverlet y ReportGenerator; para quien prefiere el recorrido de Microsoft.

## Recursos didácticos

- [ReportGenerator](https://reportgenerator.io) — la documentación de todos los tipos de informe (`-reporttypes`), incluidas las insignias y los resúmenes para integrar en un README.

---

*En resumen: Coverlet mide qué código ejecutan los tests, no qué comprueban; úsalo para ver lo que está en rojo, mira la rama antes que la línea y no conviertas el porcentaje en el objetivo.*
