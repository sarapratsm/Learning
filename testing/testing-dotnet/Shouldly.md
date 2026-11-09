# Shouldly

## ¿Qué es?

Shouldly es una biblioteca de aserciones para .NET que se escriben como frases sobre el valor comprobado (`pedido.Total.ShouldBe(55m)`) y que, al fallar, citan en el mensaje el código de esa expresión. No ejecuta tests —eso lo hace el framework, por ejemplo [xUnit](xUnit.md)—: solo sustituye a `Assert`.

## ¿Por qué existe?

Una aserción clásica dice qué valores difieren, pero no *de qué* eran esos valores. El mismo test fallido, con las dos bibliotecas (pedido #4711 con dos unidades a 25 €, que suman 50):

```csharp
// ❌ Assert de xUnit
var pedido = Nuevo();
Assert.Equal(55m, pedido.Total);

// ✅ Shouldly
var pedido = Nuevo();
pedido.Total.ShouldBe(55m);
```

```text
Assert.Equal() Failure: Values differ
Expected: 55
Actual:   50
```

```text
Shouldly.ShouldAssertException : pedido.Total
    should be
55m
    but was
50m
```

El primer mensaje obliga a abrir el test para saber que 50 era el total del pedido. El segundo nombra la expresión (`pedido.Total`), y en un fallo de integración continua suele bastar para saber qué se rompió sin abrir el código.

> Es como un parte de avería: «error: 50 ≠ 55» obliga a buscar la máquina; «la caldera del sótano marca 50 y debería marcar 55» ya señala dónde mirar.

Las salidas provienen de un proyecto `Tienda.Tests` real (xUnit 2.9.3, Shouldly 4.3.0, .NET SDK 10.0.401), ejecutado con `dotnet test` el 2026-11-09. El runner estaba en un sistema con configuración regional española: los decimales de los mensajes de Shouldly salen con coma (`0,3d`).

## ¿Cuándo y para qué se usa?

En cualquier proyecto de tests .NET donde se quiera que el fallo se explique solo: tests unitarios de dominio y de casos de uso, y tests de integración donde se comparan resultados de consultas o respuestas. Es independiente del framework de tests: lanza su propia excepción (`ShouldAssertException`), que xUnit registra como fallo como cualquier otra (con NUnit y MSTest no se probó; la documentación oficial usa NUnit en su guía de inicio).

## Instalación y licencia

```bash
dotnet add package Shouldly
```

```csharp
using Shouldly;
```

En NuGet, la última versión estable consultada el 2026-11-09 es **4.3.0**; existen además `5.0.0-preview.1` y `5.0.0-preview.2`. El paquete 4.3.0 compila para `net8.0`, `net9.0` y `netstandard2.0`, y funcionó sin problemas con xUnit 2.9.3 sobre `net10.0`. No se probó con xUnit v3 ni con NUnit ni MSTest.

Licencia, leída en el `.nuspec` del paquete 4.3.0 el 2026-11-09: `<license type="expression">BSD-3-Clause</license>`, es decir, una licencia permisiva que permite uso comercial. Como contraste verificable: el `.nuspec` de FluentAssertions 7.2.0 declara `Apache-2.0`, y el de FluentAssertions 8.0.0 (y también el de 8.11.0, la última versión consultada) declara `type="file"` con un fichero `LICENSE`; el `LICENSE` de la rama principal del repositorio es un «Community License Agreement» de Xceed Software para uso no comercial, y cualquier otro uso exige una licencia comercial de pago. Antes de adoptar o actualizar una biblioteca de aserciones conviene leer el `.nuspec`, no suponer.

## Aserciones esenciales

Todas son métodos de extensión sobre el valor, con la forma `actual.ShouldXxx(expected)`. Los ejemplos usan una `Pedido` reducida: `Numero`, `Estado`, `Cupon` (puede ser `null`), `Lineas` y `Total` (suma de cantidad por precio).

### Igualdad, nulos y booleanos

```csharp
var pedido = Nuevo();                       // pedido #4711, una línea: 2 × 25 €
pedido.Numero.ShouldBe("PED-4711");
pedido.Estado.ShouldNotBe(EstadoPedido.Cancelado);
pedido.ShouldNotBeNull();
pedido.Cupon.ShouldBeNull();
pedido.Lineas.Any().ShouldBeTrue();
```

### Números

```csharp
pedido.Total.ShouldBeGreaterThan(0m);
pedido.Total.ShouldBeInRange(10m, 100m);
(0.1 + 0.2).ShouldBe(0.3, 0.0001);          // double con tolerancia
(10m / 3).ShouldBe(3.33m, 0.01m);           // decimal con tolerancia
```

La sobrecarga con segundo parámetro numérico es una **tolerancia**: sin ella, `(0.1 + 0.2).ShouldBe(0.3)` falla con `d should be 0,3d but was 0,30000000000000004d`.

### Cadenas

```csharp
pedido.Numero.ShouldContain("4711");
pedido.Numero.ShouldStartWith("PED");
pedido.Numero.ShouldEndWith("11");
pedido.Numero.ShouldMatch(@"^PED-\d+$");                              // expresión regular
pedido.Numero.ShouldBe("ped-4711", StringCompareShould.IgnoreCase);
```

`ShouldBe` de cadenas distingue mayúsculas por defecto. `StringCompareShould.IgnoreCase` es la opción para cadenas; el enum `Case` (`Case.Insensitive`) solo existe para colecciones y para `ShouldContain` de cadenas: `"x".ShouldBe("X", Case.Insensitive)` no compila. Al fallar, el mensaje incluye una tabla de diferencia carácter a carácter:

```text
"PED-4711"
    should be with options: Ignoring case
"ped-4712"
    but was
"PED-4711"
    difference
Difference     |                                     |
               |                                    \|/
Index          | 0    1    2    3    4    5    6    7
Expected Value | p    e    d    -    4    7    1    2
Actual Value   | P    E    D    -    4    7    1    1
```

### Colecciones

```csharp
var skus = new List<string> { "CAM-01", "PAN-02", "GOR-03" };
skus.ShouldContain("PAN-02");
skus.ShouldContain(s => s.StartsWith("GOR"));           // con predicado
skus.ShouldNotContain("XXX");
skus.ShouldNotBeEmpty();
skus.ShouldBe(["CAM-01", "PAN-02", "GOR-03"]);          // mismo orden
skus.ShouldBe(["GOR-03", "CAM-01", "PAN-02"], ignoreOrder: true);
skus.ShouldAllBe(s => s.Contains('-'));
skus.ShouldBeUnique();
var unico = new[] { "CAM-01" }.ShouldHaveSingleItem();  // devuelve el elemento
```

Los fallos listan el contenido y marcan lo distinto:

```text
new[]{1,2,3}
    should be
[3, 2, 1]
    but was
[1, 2, 3]
    difference
[*1*, 2, *3*]
```

```text
new[]{"A-1","B","A-2"}
    should satisfy the condition
s.Contains(-)
    but
["B"]
    do not
```

`ShouldAllBe` señala qué elementos incumplen, no solo que alguno lo hace.

### Tipos

```csharp
object resultado = new PedidoDto(1, "Ana", new());
resultado.ShouldBeOfType<PedidoDto>();                  // tipo exacto
resultado.ShouldBeAssignableTo<IEquatable<PedidoDto>>(); // el tipo o un derivado/interfaz
```

### Objetos: igualdad y equivalencia estructural

`ShouldBe` usa `Equals`. Un `record` compara sus propiedades por valor, pero una propiedad de tipo lista se compara **por referencia**, así que dos DTO con las mismas listas de contenido idéntico no son iguales:

```csharp
var a = new PedidoDto(1, "Ana", new() { "A", "B" });
var b = new PedidoDto(1, "Ana", new() { "A", "B" });
a.ShouldBe(b);                    // ❌ falla
a.ShouldBeEquivalentTo(b);        // ✅ compara propiedad a propiedad, y dentro de las listas
```

```text
Shouldly.ShouldAssertException : a
    should be
PedidoDto { Id = 1, Cliente = Ana, Skus = System.Collections.Generic.List`1[System.String] }
    but was
PedidoDto { Id = 1, Cliente = Ana, Skus = System.Collections.Generic.List`1[System.String] }
```

El mensaje de `ShouldBe` muestra dos textos idénticos: `ToString()` del `record` no despliega la lista. Es el síntoma típico de un `record` con colecciones.

En la 4.3.0, `ShouldBeEquivalentTo` solo acepta `(expected, customMessage)`: no tiene opciones y **sí distingue el orden de las listas**. Con `Skus` en orden `A, B` frente a `B, A` falla:

```text
Comparing object equivalence, at path:
a [Tienda.PedidoDto]
    Skus [System.Collections.Generic.List`1[...]]
        Element [0] [System.String]
    Expected value to be
"B"
    but was
"A"
```

También exige el mismo tipo: comparar un `PedidoDto` con un objeto anónimo de las mismas propiedades falla con `Expected value to be <>f__AnonymousType0...` / `but was Tienda.PedidoDto`.

### Excepciones y tiempos

```csharp
var ex = Should.Throw<PedidoNoConfirmableException>(() => new Pedido(1).Confirmar());
ex.Message.ShouldContain("sin líneas");

var exAsync = await Should.ThrowAsync<PedidoNoConfirmableException>(
    () => new Pedido(1).ConfirmarAsync());

Should.NotThrow(() => Nuevo().Confirmar());
await Should.NotThrowAsync(() => Nuevo().ConfirmarAsync());

Should.CompleteIn(() => Thread.Sleep(10), TimeSpan.FromSeconds(1));
```

`Should.Throw<T>` devuelve la excepción para seguir comprobándola. Los mensajes de fallo nombran la expresión y las dos excepciones:

```text
`pedido.Confirmar()`
    should throw
System.ArgumentException
    but threw
Tienda.PedidoNoConfirmableException
---- Tienda.PedidoNoConfirmableException : Un pedido sin líneas no se puede confirmar.
```

```text
`pedido.Confirmar()`
    should not throw but threw
Tienda.PedidoNoConfirmableException
    with message
"Un pedido sin líneas no se puede confirmar."
```

```text
Shouldly.ShouldCompleteInException :
Delegate
    should complete in
00:00:00.1000000
    but did not
```

`Should.CompleteIn` aborta la espera pasado el tiempo, pero no es un benchmark: sirve para detectar bloqueos, no para medir rendimiento.

### Mensaje personalizado

El último parámetro opcional de casi todas las aserciones es un texto que se añade al fallo:

```csharp
pedido.Total.ShouldBe(55m, "el total debe incluir el envío");
```

```text
pedido.Total
    should be
55m
    but was
50m
Additional Info:
    el total debe incluir el envío
```

## Varias comprobaciones a la vez

Con aserciones sucesivas, la primera que falla detiene el test y las demás quedan sin comprobar. Un pedido con tres datos erróneos exige tres ciclos de ejecutar, corregir y volver a ejecutar:

```csharp
pedido.Numero.ShouldBe("PED-4712");        // falla aquí; las otras dos ni se ejecutan
pedido.Estado.ShouldBe(EstadoPedido.Pagado);
pedido.Lineas.Count.ShouldBe(3);
```

`ShouldSatisfyAllConditions` ejecuta todas y recoge los fallos en un solo mensaje:

```csharp
pedido.ShouldSatisfyAllConditions(
    () => pedido.Numero.ShouldBe("PED-4712"),
    () => pedido.Estado.ShouldBe(EstadoPedido.Pagado),
    () => pedido.Lineas.Count.ShouldBe(3));
```

```text
pedido
    should satisfy all the conditions specified, but does not.
The following errors were found ...
--------------- Error 1 ---------------
    pedido.Numero
        should be
    "PED-4712"
        but was
    "PED-4711"
--------------- Error 2 ---------------
    pedido.Estado
        should be
    EstadoPedido.Pagado
        but was
    EstadoPedido.Borrador
--------------- Error 3 ---------------
    pedido.Lineas.Count
        should be
    3
        but was
    1
-----------------------------------------
```

(Se omite la tabla de diferencia de la primera cadena.) Es la herramienta adecuada para comprobar varias propiedades de un mismo resultado; no sustituye a separar en tests distintos cosas que no tienen relación.

### Shouldly 5 (versión preliminar)

La documentación de docs.shouldly.org describe la versión 5 y avisa de que `ShouldSatisfyAllConditions` queda obsoleto en ella (aún funciona, con `[Obsolete]`) a favor de `ShouldSatisfy` sobre un sujeto y `Should.Satisfy` para aserciones sin sujeto común, y de que `ShouldBeEquivalentTo` admite `new EquivalencyOptions { IgnoreOrder = true }`. Con `5.0.0-preview.2` se comprobó en un proyecto aparte, el 2026-11-09, que `a.ShouldSatisfy([p => p.Id.ShouldBe(2), p => p.Skus.Count.ShouldBe(3)])` agrupa los dos fallos igual que arriba y que `ShouldBeEquivalentTo(b, new EquivalencyOptions { IgnoreOrder = true })` pasa con listas en distinto orden. `Should.Satisfy` no se probó. La 4.3.0, la estable, no tiene `ShouldSatisfy` ni opciones de equivalencia.

## Cómo construye el mensaje

Shouldly lee de la expresión del código fuente lo que hay delante del `ShouldXxx`. En la 4.3.0 lo hace localizando en el fichero de símbolos de depuración (`.pdb`) la línea de la llamada; las versiones 5 usan `[CallerArgumentExpression]`, que el compilador resuelve en tiempo de compilación (según la documentación de migración 4 a 5). Consecuencias comprobadas con la 4.3.0:

- **Expresiones que no son un identificador**: se cita el texto completo, sea una llamada, un indexador o una suma (`Nuevo().Lineas.Sum(l => l.Cantidad)`, `pedido.Lineas[0].Cantidad`, `pedido.Total + 1`).
- **Varias sentencias en una línea**: se cita la línea entera. Un test escrito como `[Fact] public void X() { var pedido = Nuevo(); pedido.Total.ShouldBe(55m); }` produce `[Fact] public void X() { var pedido = Nuevo(); pedido.Total should be…`. Una aserción por línea evita el ruido. Lo mismo ocurre con una función local de una línea: cita `static void Comprobar(int valor) => valor`.
- **Release**: con la configuración por defecto (`dotnet test -c Release`) el mensaje es idéntico, porque el `.pdb` portable se sigue generando. Si el proyecto se compila sin símbolos (`-p:DebugType=none`) Shouldly pierde la expresión y el mensaje queda en `50m should be 55m but was not`.

## Migrar de `Assert` a Shouldly

| xUnit `Assert` | Shouldly |
|---|---|
| `Assert.Equal(55m, x)` | `x.ShouldBe(55m)` |
| `Assert.NotEqual(1, x)` | `x.ShouldNotBe(1)` |
| `Assert.True(x)` | `x.ShouldBeTrue()` |
| `Assert.Null(x)` / `Assert.NotNull(x)` | `x.ShouldBeNull()` / `x.ShouldNotBeNull()` |
| `Assert.Contains("PED", cadena)` | `cadena.ShouldContain("PED")` |
| `Assert.Contains(item, coleccion)` | `coleccion.ShouldContain(item)` |
| `Assert.Empty(coleccion)` | `coleccion.ShouldBeEmpty()` |
| `Assert.Single(coleccion)` | `coleccion.ShouldHaveSingleItem()` |
| `Assert.All(coleccion, comprobacion)` | `coleccion.ShouldAllBe(predicado)` |
| `Assert.InRange(x, 1, 10)` | `x.ShouldBeInRange(1, 10)` |
| `Assert.IsType<T>(x)` | `x.ShouldBeOfType<T>()` |
| `Assert.Throws<T>(() => ...)` | `Should.Throw<T>(() => ...)` |

El orden de los argumentos se invierte respecto a `Assert`: el valor real va delante y el esperado entre paréntesis. La migración puede hacerse test a test: ambas bibliotecas conviven sin problema en el mismo proyecto.

### Cuándo no compensa

- **El equipo ya usa otra biblioteca** (por ejemplo FluentAssertions en versiones anteriores a la 8, o `Assert` con tests ya escritos): mezclar estilos en un mismo código base resta más que aporta. Migrar solo tiene sentido si los mensajes del actual duelen de verdad.
- **Una dependencia más**: cada paquete exige vigilar versiones y licencia; `Assert` ya viene con xUnit.
- **El comportamiento de los mensajes depende de los símbolos** (ver arriba): un entorno de compilación que los quite pierde la mitad del beneficio.
- **La licencia del paquete cambió en el pasado en otras bibliotecas del mismo nicho**: conviene fijar la versión y revisar el `.nuspec` al actualizar.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `error CS1929: 'int' does not contain a definition for 'ShouldBe'... requires a receiver of type 'long'` al hacer `int i; i.ShouldBe(3L)` | `ShouldBe<T>` exige el mismo tipo en ambos lados; con `decimal` frente a `double` el error de compilación es igual. Se corrige igualando los tipos, no con un cast al azar. |
| `o.ShouldBe(3)` con `o` de tipo `object` que contiene `3L` pasa; con `object o = 3` contra la cadena `"3"` falla (`should be "3" but was 3`) | Con `object` como receptor no hay comprobación de tipos en compilación; entre numéricos (`3L` y `3`) la comparación pasó, entre número y cadena no. |
| `a.ShouldBe(b)` falla con dos textos idénticos en el mensaje | Un `record` con una lista compara la lista por referencia; usar `ShouldBeEquivalentTo` |
| `ShouldBeEquivalentTo` falla con las mismas listas en otro orden | En la 4.3.0 respeta el orden y no tiene opciones. Para ignorarlo: `ShouldBe(otra, ignoreOrder: true)` sobre la propia colección, o la opción `IgnoreOrder` de la versión 5 |
| `skus.ShouldContain("CAM")` falla con `skus should contain "CAM" but was actually ["CAM-01", "PAN-02"]` | Sobre una colección, `ShouldContain` busca un elemento igual; sobre una cadena (`"CAM-01".ShouldContain("CAM")`), una subcadena |
| Un test que debería fallar pasa en verde | `Should.ThrowAsync` sin `await`: la aserción no llega a esperarse. Ver abajo |
| El mensaje dice `50m should be 55m but was not` | El proyecto se compiló sin símbolos de depuración |

El caso de `ThrowAsync` sin `await` es el más traicionero. Con un pedido que **sí tiene líneas** (confirmarlo no lanza nada), el mismo test escrito de las dos formas:

```csharp
[Fact]
public async Task Sin_await()
{
    var pedido = Nuevo();
    Should.ThrowAsync<PedidoNoConfirmableException>(() => pedido.ConfirmarAsync()); // sin await
    await Task.CompletedTask;
}

[Fact]
public async Task Con_await()
{
    var pedido = Nuevo();
    await Should.ThrowAsync<PedidoNoConfirmableException>(() => pedido.ConfirmarAsync());
}
```

`Sin_await` queda **verde** aunque la aserción sea falsa (el compilador solo avisa con `CS4014: Because this call is not awaited, execution of the current method continues...`). `Con_await` falla como debe:

```text
Task `pedido.ConfirmarAsync()`
    should throw
Tienda.PedidoNoConfirmableException
    but did not
```

Tratar `CS4014` como error (`<WarningsAsErrors>CS4014</WarningsAsErrors>`) lo evita.

## Buenas prácticas avanzadas

- **Una aserción por línea.** El mensaje cita la línea del fichero; varias sentencias juntas ensucian el texto o apuntan a otra cosa.
- **Agrupar con `ShouldSatisfyAllConditions` (o `ShouldSatisfy` en la 5) las propiedades de un mismo resultado**, para ver todos los fallos de una vez, pero no mezclar escenarios distintos en un test.
- **Tolerancia explícita para `double` y `decimal` calculados**, nunca igualdad exacta. En importes monetarios con `decimal` suele bastar la igualdad exacta; si hay divisiones, una tolerancia de medio céntimo.
- **`ShouldBeEquivalentTo` para DTO con listas, `ShouldBe` para valores.** Y si el orden de la lista no importa, decidirlo en el test (`ignoreOrder: true`) en lugar de ordenar a mano.
- **Fallar con mensaje propio solo cuando el código no lo diga.** Un `"razón"` que repite la expresión es ruido; uno que explica la regla de negocio (`"un cupón no puede superar el 50 %"`) ahorra una búsqueda.
- **Tratar `CS4014` como error en el proyecto de tests** para que ninguna aserción asíncrona se quede sin `await`.
- **Fijar la versión del paquete y leer el `.nuspec` al actualizar.** La 5 aún es preliminar y la documentación pública ya la describe a ella.

## Documentación oficial

- [docs.shouldly.org](https://docs.shouldly.org/) — documentación general. Las páginas de aserciones (igualdad, colecciones, cadenas, excepciones) tienen ejemplos con el mensaje de fallo, y se puede leer cualquiera en Markdown añadiendo `.md` a la URL. Léase sabiendo que los ejemplos nuevos apuntan a la versión 5.
- [Migrating from FluentAssertions](https://docs.shouldly.org/documentation/migrating-from-fluentassertions) — tabla de equivalencias y diferencias de comportamiento si se viene de FluentAssertions; también apunta a la versión 5.
- [Upgrade 4 to 5](https://docs.shouldly.org/documentation/4to5) — qué cambia al pasar a la 5 (por ejemplo `ShouldSatisfyAllConditions` obsoleto); consultar antes de actualizar.
- [Repositorio shouldly/shouldly](https://github.com/shouldly/shouldly) — código, versiones y licencia.

---
*En resumen: Shouldly convierte un «esperaba 55 y fue 50» anónimo en «`pedido.Total` debería ser 55 y fue 50»: un fallo que dice dónde mirar.*
