# BDD (Behavior-Driven Development)

## ¿Qué es?

BDD, **desarrollo guiado por comportamiento**, es una práctica de equipo en la que negocio, desarrollo y pruebas se ponen de acuerdo sobre qué debe hacer el software mediante **ejemplos concretos escritos en un lenguaje común**. Esos ejemplos se convierten después en especificación legible, en pruebas automáticas y en documentación que no caduca.

Tiene tres actividades que se repiten por cada funcionalidad: **descubrimiento** (conversar con ejemplos), **formulación** (escribirlos en un formato estructurado, normalmente Gherkin) y **automatización** (convertirlos en pruebas que fallan hasta que el comportamiento existe).

## ¿Por qué existe?

El problema no es técnico: es que quien pide el software y quien lo escribe entienden cosas distintas con las mismas palabras. Una historia de usuario como esta parece clara:

> Como cliente, quiero usar un cupón de descuento para pagar menos.

Y dos semanas después aparecen las preguntas que nadie hizo: ¿el 10 % se calcula antes o después del envío?, ¿se puede usar con otro cupón?, ¿qué pasa el último día de validez?, ¿y si el carrito no llega al importe mínimo? Cada pregunta sin responder se convierte en una suposición del desarrollo, y cada suposición equivocada es un defecto que se descubre tarde y cuesta caro.

Dan North formuló BDD en 2006 («Introducing BDD», ver [Documentación oficial](#documentación-oficial)) a partir de un problema de enseñanza de TDD: quien empezaba con TDD no sabía qué probar, por dónde empezar ni cómo llamar a las pruebas. Su propuesta fue pensar en **comportamiento** en vez de en *tests*, nombrar cada comportamiento con una frase en el vocabulario del negocio (el *ubiquitous language* de Domain-Driven Design) y estructurar los criterios de aceptación como contexto → acción → resultado: **Given-When-Then**.

> Si ya conoces los tests de aceptación con [Arrange-Act-Assert](../testing-dotnet/Arrange-Act-Assert.md), piensa en BDD como la misma estructura elevada de nivel: el *Given-When-Then* no lo escribe solo quien programa, sino todo el equipo, antes de programar, y está redactado en palabras del negocio en vez de en llamadas a métodos.

### Qué NO es BDD

| Idea habitual | Por qué es un malentendido |
|---|---|
| «BDD es TDD con Gherkin» | TDD guía el **diseño del código** con tests unitarios escritos por quien programa. BDD guía la **comprensión del problema** con ejemplos acordados por todo el equipo. Se combinan (ver [BDD y TDD juntos](#bdd-y-tdd-juntos)), pero resuelven problemas distintos. Más sobre TDD en [TDD](TDD.md). |
| «BDD es una herramienta (Cucumber, Reqnroll)» | La herramienta automatiza lo que ya se acordó. Sin la conversación, es una forma lenta y verbosa de escribir tests de integración. |
| «BDD son tests de UI con frases bonitas» | Un escenario que dice «hago clic en #btn-apply» describe la pantalla, no el comportamiento. La UI es un detalle de implementación. |
| «Lo escribe QA después de que el código esté hecho» | Entonces es documentación de lo que ya existe, no una forma de descubrir qué construir. El valor está en el **antes**. |
| «Todo el proyecto debe hacerse con BDD» | BDD compensa donde hay reglas de negocio ambiguas o varias disciplinas implicadas; en código de infraestructura o utilidades es sobrecoste (ver [Cuándo aporta y cuándo sobra](#cuándo-aporta-y-cuándo-sobra)). |

## ¿Cuándo y para qué se usa?

Aparece donde las reglas de negocio importan y cambian: precios y descuentos, impuestos, flujos de aprobación, elegibilidad, reglas de envío, prestaciones. Cualquier sitio donde la frase «depende» salga en la primera conversación.

El **ejemplo conductor** de esta ficha, compartida con las fichas hermanas [TDD](TDD.md) y [SDD](SDD.md), es una tienda online en C#/.NET con carrito (`Cart`), productos y una regla de **cupón de descuento**:

- El cupón `SAVE10` descuenta un **10 % sobre el subtotal**.
- Exige un **importe mínimo** de subtotal de 50,00.
- **Caduca**: es válido hasta el 2026-11-30.
- **No es acumulable**: un pedido admite un solo cupón.

El pedido que se sigue como caso real es el **#4711**. Los pasos se automatizan con **Reqnroll** (el sucesor de SpecFlow para .NET) sobre [xUnit](../testing-dotnet/xUnit.md).

## Las tres prácticas

### 1. Descubrimiento: conversar con ejemplos

Se hace con la **reunión de los tres amigos** (*Three Amigos*): una persona de negocio (qué problema se resuelve y qué regla aplica), una de desarrollo (qué es viable y cómo encaja) y una de pruebas (qué puede salir mal). Duran entre 15 y 30 minutos por historia y ocurren **antes** de que la historia entre en desarrollo. El objetivo no es producir un documento: es que las tres personas salgan con la misma imagen y con las dudas a la vista.

La técnica más usada para estructurarla es el **Example Mapping**, que usa cuatro colores de tarjeta:

| Tarjeta | Color | Contenido |
|---|---|---|
| Historia | Amarilla | La funcionalidad que se discute, arriba del todo. |
| Regla | Azul | Un criterio de aceptación, debajo de la historia. |
| Ejemplo | Verde | Un caso concreto que ilustra una regla, debajo de ella. |
| Pregunta | Roja | Algo que nadie en la sala sabe responder, o una suposición. |

**Sesión de ejemplo sobre el cupón.** La historia amarilla es «Usar un cupón de descuento». La sesión produce este mapa:

```
[ HISTORIA: Usar un cupón de descuento ]

[ REGLA: SAVE10 descuenta el 10 % del subtotal ]
    (ejemplo) Carrito de 85,00 → descuento 8,50 → total 76,50

[ REGLA: Exige un subtotal mínimo de 50,00 ]
    (ejemplo) Subtotal 25,00 → cupón rechazado
    (ejemplo) Subtotal 50,00 exactos → cupón aceptado   ← la frontera
    (ejemplo) Subtotal 75,00 → cupón aceptado

[ REGLA: Un pedido admite un solo cupón ]
    (ejemplo) Con SAVE10 ya aplicado, aplicarlo otra vez → rechazado

[ REGLA: El cupón caduca ]
    (ejemplo) Válido hasta 2026-11-30; el 2026-12-01 → rechazado
    (ejemplo) El mismo 2026-11-30 → aceptado   ← la otra frontera

[ PREGUNTA: ¿El subtotal incluye el envío? ]
[ PREGUNTA: ¿Se descuenta también sobre productos ya rebajados? ]
[ PREGUNTA: ¿«save10» en minúsculas es el mismo cupón? ]
```

Esto es lo que el Example Mapping hace bien:

- **Los ejemplos de frontera aparecen solos.** Nadie habría escrito «50,00 exactos» en una especificación en prosa; al pedir ejemplos, la persona de pruebas pregunta «¿y con 50?» y la de negocio responde «aceptado» en diez segundos.
- **Las tarjetas rojas son trabajo detectado, no fallos.** Se asignan a quien pueda responderlas. Si hay demasiadas, la historia no está lista para desarrollo.
- **Se mide la historia.** Una historia con diez reglas es varias historias; una con una única tarjeta roja gigante necesita investigación antes de estimarse.

Las tarjetas verdes son la materia prima de la siguiente práctica.

### 2. Formulación: escribir los ejemplos en Gherkin

Los ejemplos acordados se escriben en **Gherkin**, un lenguaje con pocas palabras clave, pensado para que lo lean personas de negocio y lo procese una herramienta. Se guarda en ficheros `.feature` dentro del repositorio, versionados junto al código. La siguiente sección lo describe a fondo.

### 3. Automatización: convertir los ejemplos en pruebas

Cada escenario se enlaza con código mediante **definiciones de pasos** (*step definitions*): métodos que ejecutan lo que dice cada frase. El escenario falla hasta que el comportamiento existe. Se desarrolla en [Automatización con Reqnroll](#automatización-con-reqnroll).

El orden importa: descubrimiento primero, automatización después. Si solo se hace la tercera práctica se obtiene una suite de tests con sintaxis extraña, sin ninguno de los beneficios.

## Gherkin a fondo

Gherkin es un formato de texto con indentación opcional; cada línea empieza por una palabra clave. Este es el `.feature` completo del cupón, que se usará durante el resto de la ficha:

```gherkin
@coupons
Feature: Discount coupons
  Shoppers can lower the price of an order with a coupon code.

  Background:
    Given the catalog has these products
      | sku   | name     | price |
      | KB-01 | Keyboard | 60.00 |
      | MS-02 | Mouse    | 25.00 |

  Rule: SAVE10 takes 10% off the subtotal

    Scenario: A valid coupon discounts the subtotal
      Given a cart with these items
        | sku   | quantity |
        | KB-01 | 1        |
        | MS-02 | 1        |
      When the shopper applies coupon "SAVE10"
      Then the discount is 8.50
      And the total is 76.50

  Rule: The coupon requires a minimum subtotal of 50.00

    Scenario Outline: Minimum subtotal
      Given a cart with <quantity> units of "MS-02"
      When the shopper applies coupon "SAVE10"
      Then the coupon is <outcome>
      And the total is <total>

      Examples:
        | quantity | outcome  | total |
        | 1        | rejected | 25.00 |
        | 2        | accepted | 45.00 |
        | 3        | accepted | 67.50 |

  Rule: An order accepts only one coupon

    Scenario: Applying the same coupon twice
      Given a cart with 3 units of "MS-02"
      And the shopper has applied coupon "SAVE10"
      When the shopper applies coupon "SAVE10"
      Then the coupon is rejected
      And the discount is 7.50

  Rule: The coupon expires

    @expiry
    Scenario: Used after the expiry date
      Given today is 2026-12-01
      And a cart with 3 units of "MS-02"
      When the shopper applies coupon "SAVE10"
      Then the coupon is rejected

    @expiry
    Scenario: Used on the last valid day
      Given today is 2026-11-30
      And a cart with 3 units of "MS-02"
      When the shopper applies coupon "SAVE10"
      Then the coupon is accepted
```

### Las palabras clave

| Palabra clave | Función |
|---|---|
| `Feature` | Primera palabra del fichero y única por fichero. Nombre de la funcionalidad más una descripción libre de unas líneas. |
| `Rule` | Agrupa los escenarios que ilustran **una regla de negocio**. Equivale a una tarjeta azul del Example Mapping. Disponible desde Gherkin 6. |
| `Scenario` (o `Example`) | Un ejemplo concreto: una secuencia de pasos con un único comportamiento. Equivale a una tarjeta verde. |
| `Given` | **Contexto**: el estado del mundo antes de la acción. No ejecuta nada de lo que se prueba. |
| `When` | **Acción**: lo que ocurre y se prueba. Idealmente una sola por escenario. |
| `Then` | **Resultado observable**: lo que debe ser cierto después. |
| `And`, `But` | Continúan el tipo del paso anterior para que la lectura sea natural. Para la herramienta, `And` tras un `Given` es otro `Given`. |
| `Background` | Pasos que se ejecutan antes de **cada** escenario de la `Feature` o de la `Rule`. Solo uno por ámbito. |
| `Scenario Outline` + `Examples` | Una plantilla con marcadores `<columna>` que se ejecuta una vez por fila de la tabla. |
| `@etiqueta` | Metadatos encima de `Feature`, `Rule` o `Scenario`; se heredan hacia abajo. |
| `\| tabla \|` | Datos tabulares como argumento de un paso. |
| `"""` | **Doc string**: texto multilínea como argumento de un paso. |
| `#` | Comentario; solo al principio de línea. |

Gherkin admite escribir las palabras clave en otros idiomas con una primera línea tipo `# language: es`, con lo que `Given` pasa a `Dado`, etc. El código sigue usando los atributos `[Given]`/`[When]`/`[Then]`.

### Qué lleva cada tipo de paso

La separación `Given`/`When`/`Then` es una disciplina de lectura:

- `Given` describe **estado**, en pasado o en presente: «a cart with 3 units of "MS-02"». No contiene acciones del usuario.
- `When` describe **un evento**: «the shopper applies coupon "SAVE10"». Si hay dos `When`, probablemente son dos escenarios.
- `Then` describe **algo que se pueda observar** desde fuera: un importe, un mensaje, un correo enviado. No «la base de datos contiene una fila», salvo que la base de datos sea el producto.

### Tablas, doc strings y Outline

Una **tabla de datos** se pasa al paso como una estructura de filas (en Reqnroll, `DataTable`). Sirve cuando el contexto es un conjunto de objetos, como el catálogo de productos del `Background`.

Un **doc string** sirve para contenido que no es tabular: un cuerpo JSON, el texto de un correo.

```gherkin
Then the confirmation email for order 4711 reads
  """
  Thanks for your order. Coupon SAVE10 saved you 8.50.
  """
```

`Scenario Outline` evita copiar y pegar escenarios idénticos que solo difieren en los datos. Reqnroll sustituye `<quantity>` por el valor de cada fila **antes** de buscar la definición de paso, de modo que el paso `a cart with 2 units of "MS-02"` es una frase normal. Cada fila se ejecuta como un test independiente. Los encabezados de `Examples` deben ser únicos.

Un `Outline` sirve para **la misma regla con distintos valores** (el mínimo con 1, 2 y 3 unidades), no para escenarios que solo se parecen. Con más de cinco o seis columnas, el escenario se ha vuelto una tabla de verdad ilegible y conviene partirlo.

### Escribir buenos escenarios

**Declarativo, no imperativo.** El escenario describe *qué* hace el sistema, no *cómo* se maneja:

```gherkin
# ❌ imperativo: describe la pantalla
Scenario: Apply coupon
  Given I open "https://shop.example/cart"
  And I type "KB-01" in the field "#search"
  And I click the button "#add-to-cart"
  And I click the link "Have a coupon?"
  And I type "SAVE10" in the field "#coupon-code"
  And I click the button "#apply-coupon"
  Then the element ".discount-line" contains "-8.50"

# ✅ declarativo: describe el comportamiento
Scenario: A valid coupon discounts the subtotal
  Given a cart with 1 unit of "KB-01" and 1 unit of "MS-02"
  When the shopper applies coupon "SAVE10"
  Then the discount is 8.50
```

La prueba de calidad que propone Cucumber: **si el tipo de interfaz cambia, ¿hay que reescribir el escenario?** Si sí, hay detalle de implementación. El primer escenario cambia con cada rediseño de la web; el segundo solo cambia si cambia la regla.

Más criterios:

- **Un comportamiento por escenario.** Un escenario que comprueba el descuento, el correo y el stock fallará por tres motivos distintos y no dirá cuál.
- **Lenguaje del dominio.** «The shopper applies coupon» y no «POST /coupons con payload». Si negocio no diría la frase, sobra.
- **Datos relevantes visibles, irrelevantes ocultos.** El escenario muestra los 3 `MS-02` que determinan el importe mínimo; no muestra el nombre del cliente ni su dirección. Lo irrelevante vive en la definición del paso.
- **Cortos.** Entre tres y siete pasos. Si pasan de diez, se está escribiendo un script.
- **Cada escenario es independiente.** Se puede ejecutar solo y en cualquier orden.
- **Ejemplos reales y con frontera.** Importes y fechas concretos, incluidos los valores en el borde (50,00 exactos; el último día de validez).

## Automatización con Reqnroll

**Reqnroll** es el proyecto de código abierto, sucesor de SpecFlow, que enlaza ficheros `.feature` con código .NET. Al compilar, genera por cada `.feature` una clase de test del framework elegido (aquí xUnit); cada escenario se convierte en un test, y cada fila de un `Examples` en un test distinto. Se ejecutan con `dotnet test` como cualquier otro.

### Crear el proyecto

```bash
dotnet new xunit -n Shop.Specs
cd Shop.Specs
dotnet add package Reqnroll.xUnit
dotnet add package Shouldly
dotnet add reference ../Shop.Domain/Shop.Domain.csproj
```

`Reqnroll.xUnit` es el paquete del adaptador para xUnit. Las plantillas oficiales (`dotnet new install Reqnroll.Templates.DotNet`, luego `dotnet new reqnroll-project` y `dotnet new reqnroll-feature -n Coupons`) crean el proyecto y los ficheros `.feature`; con `dotnet new reqnroll-project --help` se ve qué valores admite el framework de pruebas. Los `.feature` se guardan en una carpeta `Features/` y las definiciones de pasos en `StepDefinitions/`. [Shouldly](../testing-dotnet/Shouldly.md) se usa para las aserciones.

El dominio que se va a probar es el siguiente. El código de la tienda vive en `Shop.Domain`, y los escenarios no saben nada más de él:

```csharp
public sealed record Product(string Sku, string Name, decimal Price);

public sealed record Coupon(string Code, decimal Percent, DateOnly ExpiresOn, decimal MinimumSubtotal);

public enum CouponRejection { None, UnknownCoupon, BelowMinimum, Expired, AlreadyApplied }

public sealed record CouponResult(bool Accepted, CouponRejection Reason);

public sealed class Cart
{
    private readonly List<(Product Product, int Quantity)> _lines = [];

    public Coupon? AppliedCoupon { get; private set; }
    public decimal Subtotal => _lines.Sum(l => l.Product.Price * l.Quantity);
    public decimal Discount => AppliedCoupon is null
        ? 0m
        : Math.Round(Subtotal * AppliedCoupon.Percent / 100m, 2, MidpointRounding.AwayFromZero);
    public decimal Total => Subtotal - Discount;

    public void Add(Product product, int quantity) => _lines.Add((product, quantity));

    public CouponResult ApplyCoupon(Coupon coupon, DateOnly today)
    {
        // lo implementa el ciclo de TDD: ver «BDD y TDD juntos»
        throw new NotImplementedException();
    }
}
```

### La salida roja: pasos sin definir

Con el `.feature` ya escrito y **ninguna** definición de pasos, el proyecto compila y los tests no pasan. Reqnroll genera, para cada paso sin enlazar, un fragmento de código listo para pegar:

```bash
dotnet test
```

```
No matching step definition found for one or more steps.
using Reqnroll;

namespace Shop.Specs.StepDefinitions
{
    [Binding]
    public class StepDefinitions
    {
        [Given("the catalog has these products")]
        public void GivenTheCatalogHasTheseProducts(DataTable dataTable)
        {
            throw new PendingStepException();
        }

        [When("the shopper applies coupon {string}")]
        public void WhenTheShopperAppliesCoupon(string p0)
        {
            throw new PendingStepException();
        }
        ...
```

Lo verificado en la documentación oficial es la forma del fragmento: una clase `[Binding]` con atributos que usan **Cucumber expressions** (`{string}`, `{int}`, `{float}`) y cuerpos que lanzan `PendingStepException`. El texto literal del mensaje y los nombres de los parámetros (`p0`) varían entre versiones; el bloque de arriba es ilustrativo, no una copia de una ejecución. Cómo cuenta xUnit un paso pendiente (fallo, omitido) depende de la configuración de Reqnroll y de la versión: pendiente de confirmar para la combinación concreta del proyecto.

Esta salida es el equivalente al «rojo» de TDD: la especificación existe, nada la cumple.

### Escribir las definiciones de pasos

Una definición de pasos es un método con un atributo cuya expresión coincide con la frase del escenario. Las llaves `{string}`, `{int}`, `{float}` capturan valores y los pasan como parámetros. Antes hace falta decidir dónde vive el estado que comparten los pasos.

### Compartir estado entre pasos: context injection

Un escenario son varios pasos, cada uno un método distinto, y necesitan compartir el carrito y el resultado de aplicar el cupón. Reqnroll lo resuelve con **inyección de contexto**: se declara una clase normal (un POCO), se pide en el constructor de la clase `[Binding]` y Reqnroll crea **una instancia por escenario** y la entrega a todas las clases que la pidan. La vida del objeto se limita al escenario y, si implementa `IDisposable`, se libera al terminar.

```csharp
public sealed class ShoppingContext
{
    public Dictionary<string, Product> Catalog { get; } = new();
    public Cart Cart { get; } = new();
    public DateOnly Today { get; set; } = new(2026, 10, 30);
    public CouponResult? LastResult { get; set; }

    public Coupon Save10 { get; } =
        new("SAVE10", Percent: 10m, ExpiresOn: new DateOnly(2026, 11, 30), MinimumSubtotal: 50m);
}
```

```csharp
using Reqnroll;
using Shouldly;

[Binding]
public sealed class CouponSteps(ShoppingContext ctx)
{
    [Given("the catalog has these products")]
    public void GivenTheCatalogHasTheseProducts(DataTable table)
    {
        foreach (var row in table.Rows)
            ctx.Catalog[row["sku"]] = new Product(row["sku"], row["name"], decimal.Parse(row["price"], CultureInfo.InvariantCulture));
    }

    [Given("a cart with these items")]
    public void GivenACartWithTheseItems(DataTable table)
    {
        foreach (var row in table.Rows)
            ctx.Cart.Add(ctx.Catalog[row["sku"]], int.Parse(row["quantity"]));
    }

    [Given("a cart with {int} units of {string}")]
    public void GivenACartWithUnitsOf(int quantity, string sku)
        => ctx.Cart.Add(ctx.Catalog[sku], quantity);

    [Given("today is {word}")]
    public void GivenTodayIs(string date)
        => ctx.Today = DateOnly.Parse(date, CultureInfo.InvariantCulture);

    [Given("the shopper has applied coupon {string}")]
    [When("the shopper applies coupon {string}")]
    public void WhenTheShopperAppliesCoupon(string code)
        => ctx.LastResult = ctx.Cart.ApplyCoupon(FindCoupon(code), ctx.Today);

    [Then("the coupon is {word}")]
    public void ThenTheCouponIs(string outcome)
        => ctx.LastResult!.Accepted.ShouldBe(outcome == "accepted");

    [Then("the discount is {float}")]
    public void ThenTheDiscountIs(decimal expected) => ctx.Cart.Discount.ShouldBe(expected);

    [Then("the total is {float}")]
    public void ThenTheTotalIs(decimal expected) => ctx.Cart.Total.ShouldBe(expected);

    private Coupon FindCoupon(string code) =>
        code == ctx.Save10.Code ? ctx.Save10 : new Coupon(code, 0m, DateOnly.MinValue, 0m);
}
```

Qué hace el código:

- El constructor primario pide `ShoppingContext`; Reqnroll lo entrega ya creado. Si otra clase `[Binding]` (por ejemplo, la de los hooks) también lo pide en su constructor, **recibe la misma instancia** dentro del escenario.
- Un método puede llevar **varios atributos**. Aquí `the shopper has applied coupon "SAVE10"` (un `Given`) y `the shopper applies coupon "SAVE10"` (un `When`) comparten implementación, y la frase se puede decir en cualquier de los dos tipos de paso.
- Los argumentos de un `DataTable` llegan como filas con acceso por nombre de columna.
- `{float}` entrega el número ya convertido; si el parámetro del método es `decimal`, Reqnroll lo convierte. Gherkin escribe los decimales con punto.
- `{word}` captura una sola palabra sin espacios, útil para valores como `accepted`/`rejected` que parametrizan un `Scenario Outline`.

Reqnroll también ofrece `ScenarioContext`, un diccionario por escenario con indexador (`_scenarioContext["Number1"] = number;`) al que se llega pidiéndolo en el constructor. Es más rápido de escribir y no tiene tipos: la clave `"cart"` mal escrita falla en ejecución. Para estado propio del dominio, una clase de contexto tipada.

### Reutilizar pasos

Los pasos se enlazan **por texto, globalmente**: el paso `the shopper applies coupon {string}` sirve a cualquier `.feature` del proyecto, esté en la clase que esté. Eso se aprovecha, pero con límites:

- **Un paso, una definición.** Si dos definiciones casan con la misma frase, Reqnroll lanza una excepción por ambigüedad (*ambiguous step definitions*), y el escenario falla.
- **Reutilizar el lenguaje, no el código.** Los pasos de dominio («the shopper applies coupon») se reutilizan entre features; los pasos específicos de una funcionalidad viven en su propia clase `[Binding]`.
- **Un paso no debe llamar a otro paso.** Si hay lógica común, va a un método auxiliar o a un *driver* (ver [Capas de automatización](#capas-de-automatización)).

### Hooks y etiquetas

Los **hooks** son métodos que Reqnroll ejecuta en momentos concretos del ciclo de vida.

| Hook | Cuándo corre | ¿`static`? |
|---|---|---|
| `[BeforeTestRun]` / `[AfterTestRun]` | Una vez por ejecución de la suite | Sí |
| `[BeforeFeature]` / `[AfterFeature]` | Por fichero `.feature` | Sí |
| `[BeforeScenario]` / `[AfterScenario]` | Por escenario (y por fila de un `Outline`) | No |
| `[BeforeStep]` / `[AfterStep]` | Por paso | No |

Todos salvo el de ejecución completa admiten un **filtro por etiqueta**: `[BeforeScenario("@expiry")]` solo corre para escenarios (o features o reglas) con esa etiqueta. Con varias etiquetas, basta que coincida una. El orden entre hooks del mismo tipo se fija con `Order` (menor, primero; por defecto 10000):

```csharp
[Binding]
public sealed class CouponHooks(ShoppingContext ctx)
{
    [BeforeScenario(Order = 0)]
    public void ResetClock() => ctx.Today = new DateOnly(2026, 10, 30);

    [AfterScenario("@debug")]
    public void DumpState()
        => Console.WriteLine($"Subtotal={ctx.Cart.Subtotal} Discount={ctx.Cart.Discount} Total={ctx.Cart.Total}");
}
```

Las etiquetas también sirven para **filtrar la ejecución**: Reqnroll las convierte en categorías del framework de pruebas (en xUnit, *traits* de categoría) y `dotnet test` filtra por ellas.

```bash
dotnet test --filter "Category=coupons"
dotnet test --filter "Category!=slow"
```

La etiqueta especial `@ignore` hace que Reqnroll genere el escenario como test ignorado. En un binding se pueden leer las etiquetas del escenario con `ScenarioInfo.Tags`, o con `CombinedTags` para incluir las de la `Rule` y la `Feature`.

### Resultado en verde

Con el dominio implementado (ver la sección siguiente), la suite pasa:

```bash
dotnet test
```

```
Passed!  - Failed: 0, Passed: 7, Skipped: 0, Total: 7
```

Siete tests: el escenario del descuento, tres filas del `Outline`, el cupón repetido y las dos fechas de caducidad. Es la salida abreviada que ofrece `dotnet test`; los nombres de los escenarios aparecen en el informe detallado.

## Capas de automatización

Un mismo escenario puede ejecutarse contra tres capas distintas. El `.feature` no cambia; cambia lo que hacen las definiciones de pasos.

| Capa | Qué ejecuta | Velocidad | Fidelidad | Fragilidad |
|---|---|---|---|---|
| **Dominio directo** | Llama a `Cart.ApplyCoupon(...)` en memoria | Milisegundos | Solo la lógica | Baja |
| **API HTTP** | Peticiones contra la API con [WebApplicationFactory](../testing-dotnet/WebApplicationFactory.md) | Decenas de ms | Lógica + serialización + validación + persistencia | Media |
| **UI** | Un navegador automatizado | Segundos por escenario | Experiencia completa | Alta |

El ejemplo anterior usa la primera capa. La misma definición de paso contra la segunda:

```csharp
[When("the shopper applies coupon {string}")]
public async Task WhenTheShopperAppliesCoupon(string code)
{
    var response = await ctx.Client.PostAsJsonAsync("/api/carts/4711/coupon", new { code });
    ctx.LastResponse = response;
}

[Then("the total is {float}")]
public async Task ThenTheTotalIs(decimal expected)
{
    var cart = await ctx.LastResponse!.Content.ReadFromJsonAsync<CartDto>();
    cart!.Total.ShouldBe(expected);
}
```

`ctx.Client` sale de una `WebApplicationFactory<Program>` creada en un hook `[BeforeScenario]` y registrada en el contexto. El escenario sigue hablando de cupones; el paso hace la traducción a HTTP.

Cuál elegir:

| Situación | Capa recomendada |
|---|---|
| Reglas de negocio con muchas variantes (descuentos, impuestos) | **Dominio directo**: son los escenarios más numerosos, rápidos y estables |
| Flujo de extremo a extremo de un servicio sin interfaz propia | **API HTTP** |
| Un puñado de recorridos críticos del usuario | **UI**, en poquísimos escenarios |
| Duda | La capa **más baja** que siga ejercitando la regla |

El criterio es el mismo que en la pirámide de tests ([Tipos de tests](../testing-dotnet/Tipos-de-tests.md)): muchos escenarios baratos, pocos caros. Un `.feature` puede incluso ejecutarse en varias capas cambiando solo el *binding* con una etiqueta, si se quiere comprobar que la regla se comporta igual en el dominio y en la API.

## BDD y TDD juntos

BDD y TDD no compiten: se anidan en un **doble bucle**.

```
        BUCLE EXTERNO (BDD, por comportamiento)
   escenario de aceptación ──► ROJO  ───────────────────────┐
        ▲                                                    │
        │         BUCLE INTERNO (TDD, por unidad de código) │
        │     test unitario ROJO → código mínimo → VERDE →   │
        │     refactor → siguiente test unitario ...         │
        │                                                    ▼
   refactor ◄── escenario de aceptación VERDE ◄──── (tantas vueltas internas como haga falta)
```

El escenario de aceptación define **cuándo se ha terminado**. Los tests unitarios guían **cómo se construye**. Aplicado al cupón:

1. **Escenario en rojo.** `A valid coupon discounts the subtotal` está definido y falla:

   ```
   Shouldly.ShouldAssertException : ctx.Cart.Discount
       should be
   8.50m
       but was
   0m
   ```

   En realidad, falla antes: `ApplyCoupon` lanza `NotImplementedException`. Da igual cuál de los dos; lo importante es que está rojo.

2. **Primer test unitario** (xUnit, estilo [Arrange-Act-Assert](../testing-dotnet/Arrange-Act-Assert.md)). Se escribe lo mínimo que lo haga pasar:

   ```csharp
   [Fact]
   public void Applying_SAVE10_discounts_ten_percent_of_the_subtotal()
   {
       var cart = new Cart();
       cart.Add(new Product("KB-01", "Keyboard", 60m), 1);
       cart.Add(new Product("MS-02", "Mouse", 25m), 1);

       var result = cart.ApplyCoupon(Save10, today: new DateOnly(2026, 10, 30));

       result.Accepted.ShouldBeTrue();
       cart.Discount.ShouldBe(8.50m);
   }
   ```

   ```csharp
   public CouponResult ApplyCoupon(Coupon coupon, DateOnly today)
   {
       AppliedCoupon = coupon;
       return new CouponResult(true, CouponRejection.None);
   }
   ```

3. **Bucle interno repetido.** Cada regla de la lista de ejemplos genera tests unitarios más finos, con casos que el escenario no muestra por legibilidad:

   ```csharp
   [Fact]
   public void Rejects_a_second_coupon()
   {
       var cart = new Cart();
       cart.Add(new Product("MS-02", "Mouse", 25m), 3);
       cart.ApplyCoupon(Save10, Today);

       var second = cart.ApplyCoupon(Save10, Today);

       second.Reason.ShouldBe(CouponRejection.AlreadyApplied);
   }
   ```

   Hasta llegar a la implementación completa:

   ```csharp
   public CouponResult ApplyCoupon(Coupon coupon, DateOnly today)
   {
       if (AppliedCoupon is not null) return new(false, CouponRejection.AlreadyApplied);
       if (today > coupon.ExpiresOn)   return new(false, CouponRejection.Expired);
       if (Subtotal < coupon.MinimumSubtotal) return new(false, CouponRejection.BelowMinimum);

       AppliedCoupon = coupon;
       return new(true, CouponRejection.None);
   }
   ```

4. **Escenario en verde.** Vuelve a ejecutarse `dotnet test` y los siete escenarios pasan. Se refactoriza con los dos niveles de red de seguridad.

Qué aporta cada nivel:

| Aspecto | BDD (escenarios) | TDD (tests unitarios) |
|---|---|---|
| Pregunta que responde | ¿Estamos construyendo lo que se pidió? | ¿Está bien construido y diseñado el código? |
| Quién lo escribe | Todo el equipo, en conversación; automatiza quien programa | Quien programa |
| Lenguaje | Dominio de negocio | Código |
| Granularidad | Un comportamiento visible de la funcionalidad | Una unidad: clase o método |
| Cuántos | Pocos, representativos | Muchos, incluidos casos de borde técnicos |
| Si falla, indica | Una regla de negocio incumplida | Una unidad concreta rota |
| Cambia cuando | Cambia la regla de negocio | Cambia la implementación |
| Ficha | Esta | [TDD](TDD.md) |

## Documentación viva

Los `.feature` son la única especificación que **no puede quedar desactualizada sin que alguien se entere**: si el código deja de cumplirla, la suite falla. Esa propiedad convierte los ficheros en *documentación viva* (*living documentation*): una descripción del comportamiento del sistema que se verifica en cada ejecución.

Reqnroll (desde la versión 3.0) incluye **formatters** que generan informes a partir de la ejecución. Se activan en `reqnroll.json`:

```json
{
  "$schema": "https://schemas.reqnroll.net/reqnroll-config-latest.json",
  "formatters": {
    "html":    { "outputFilePath": "reqnroll_report.html" },
    "message": { "outputFilePath": "report/cucumber_messages.ndjson" }
  }
}
```

- `html` genera un único fichero HTML con los `.feature` ejecutados y su resultado; por defecto se escribe en la carpeta de salida del proyecto (`bin/Debug/net…/`). Es lo que se publica como artefacto del pipeline de integración continua.
- `message` genera un fichero en el formato **Cucumber Messages** (NDJSON), el estándar con el que se alimentan herramientas externas de informes.

También se pueden activar con una variable de entorno, útil en un pipeline: `REQNROLL_FORMATTERS_HTML='outputFilePath=reqnroll_report.html'`.

Sirve de documentación viva solo si se cumplen tres condiciones:

1. **Los escenarios están escritos para negocio**, no para quien programa. Un informe de 400 pasos imperativos no lo lee nadie.
2. **Las `Rule` y los nombres de escenario cuentan la historia.** El informe es el índice de reglas del producto.
3. **Se publica donde negocio lo vea** (una página interna, el artefacto de la integración continua), no se queda en `bin/`.

Reqnroll también ofrece integración con *loggers* de VSTest para producir informes de resultados. Para otras opciones de informes, consultar la [documentación de Reqnroll](https://docs.reqnroll.net/latest/) en la versión que se use.

## Cuándo aporta y cuándo sobra

BDD tiene un coste fijo: reuniones, mantenimiento de los `.feature` y una capa más de código. Se amortiza solo cuando esa capa compra algo.

| Situación | ¿BDD? | Motivo |
|---|---|---|
| Reglas de negocio con ambigüedad (descuentos, impuestos, elegibilidad) | **Sí** | El descubrimiento aflora las preguntas pronto |
| Equipo con producto, desarrollo y pruebas que no comparten vocabulario | **Sí** | El lenguaje común es el principal beneficio |
| Regulación o auditoría que exige trazar requisito → prueba | **Sí** | Los `.feature` actúan de evidencia |
| Negocio disponible para colaborar | **Sí** | Sin su participación, no hay descubrimiento |
| Una persona desarrolla, es su propio producto y no hay negocio | **No** | Los tests unitarios dan lo mismo sin la capa de texto |
| Código técnico: parsers, utilidades, infraestructura, algoritmos | **No** | No hay lenguaje de negocio que compartir; basta [xUnit](../testing-dotnet/xUnit.md) |
| Prototipo o experimento con requisitos que cambian a diario | **No** | El mantenimiento de escenarios supera el valor |
| Negocio dice «escribid vosotros los escenarios» y no participa | **Cuidado** | Se obtiene el coste de BDD sin su beneficio |
| Validar un diseño visual o la ergonomía de una pantalla | **No** | Un escenario no mide si una pantalla es agradable |

Regla práctica: si **ninguna persona de negocio ha leído nunca un `.feature`**, la capa de Gherkin es un coste sin retorno, y los mismos tests están mejor escritos directamente en C#.

## Errores frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| Escenarios de 20 pasos que nadie lee | Escritos de forma **imperativa**, con cada clic y cada campo. Mezclan el qué con el cómo. | Reescribirlos declarativos; los detalles pasan a la definición del paso (ver [Escribir buenos escenarios](#escribir-buenos-escenarios)). |
| Los `.feature` los escribe solo QA o solo desarrollo, y negocio nunca los ha visto | Se saltó el descubrimiento: la automatización es la única práctica que se hace | Reservar la reunión de tres amigos antes de la historia; si no hay negocio, replantearse usar BDD |
| Escenarios que parecen código: `Given I set variable x to 5`, `When I call method Apply` | **Gherkin como lenguaje de scripting**: la sintaxis sin la intención | Cada paso debe ser una frase que negocio diría |
| Un único paso `Given the data is set up` o `When I do the thing` con docenas de usos | Pasos demasiado **genéricos**: el escenario no cuenta nada | Pasos con parámetros específicos de dominio y los datos relevantes visibles |
| Un paso con 15 parámetros opcionales en una expresión regular | Intento de reutilizar a toda costa | Pasos pequeños y claros; duplicar un poco es menos malo que un paso ilegible |
| El escenario B falla cuando se ejecuta solo, o la suite falla según el orden | Escenarios **acoplados**: B depende del estado que dejó A (base de datos, singleton estático) | Cada escenario crea su estado en `Given`; limpiar en un `[AfterScenario]`; el contexto inyectado no se comparte |
| Error de «ambiguous step definitions» (pasos ambiguos) al ejecutar un escenario; el texto exacto depende de la versión | Dos métodos con atributos que casan con la misma frase | Quitar o ajustar uno; mantener las expresiones suficientemente distintas |
| El paso termina en `PendingStepException` | El paso existe en el `.feature` y no está enlazado, o la expresión no coincide con el texto (comillas, mayúsculas) | Ejecutar y copiar el fragmento sugerido; los literales de la expresión deben ser idénticos |
| Una suite que tarda 40 minutos y todos evitan ejecutar | **Demasiados escenarios de UI**, cada uno con arranque de navegador y datos | Bajar la capa de automatización; solo recorridos críticos en UI; paralelizar las features |
| Los `Scenario Outline` con 12 columnas | La tabla se ha vuelto una tabla de verdad | Partir en varios `Outline` por regla |
| Hay `.feature` que ya no describen el producto, pero «pasan» | Los pasos asertan poco o nada (`Then the result is processed`) | Cada `Then` debe poder fallar; revisar los escenarios con mutaciones deliberadas |
| Cada cambio de interfaz rompe 200 escenarios | Los pasos están acoplados a selectores de UI, no a un *driver* intermedio | Una capa de objetos de página o de *drivers*; los escenarios no los conocen |
| Negocio se queja de que los escenarios «parecen tests» | Redactados en términos de campos y pantallas, no de decisiones | Rehacer los ejemplos con negocio presente, con sus palabras |

Un ejemplo concreto de «pasos demasiado genéricos»:

```gherkin
# ❌ el paso no dice nada sobre el negocio
Given the system is in state "A"
When I perform action "coupon"
Then I see result "OK"

# ✅ los datos que importan están a la vista
Given a cart with 3 units of "MS-02"
When the shopper applies coupon "SAVE10"
Then the total is 67.50
```

## Alternativas y ecosistema

Gherkin es un formato y Cucumber su implementación de referencia. El ecosistema es amplio; todas estas herramientas leen `.feature`:

| Herramienta | Plataforma |
|---|---|
| **Reqnroll** | .NET (sucesor de SpecFlow) |
| **Cucumber** (cucumber-jvm, cucumber-js) | Java y otros lenguajes de la JVM; JavaScript/TypeScript |
| **Behave** / **pytest-bdd** | Python |
| **Gauge** | Multi-lenguaje; usa especificaciones en Markdown en vez de Gherkin |

Quien aprende BDD con una herramienta puede moverse a otra: los conceptos son los mismos, cambian los atributos o decoradores.

## Buenas prácticas avanzadas

- **Etiquetar por propósito, no por tipo de test.** Etiquetas como `@smoke`, `@slow`, `@wip` o `@requires-db` permiten ejecutar subconjuntos en cada etapa del pipeline (`dotnet test --filter "Category=smoke"` en cada commit, la suite completa por la noche). Una etiqueta `@ui` o `@api` por escenario es más útil que mil etiquetas de funcionalidad.
- **Un driver entre los pasos y el sistema.** Las definiciones de pasos llaman a una clase *driver* con un API de dominio (`shopper.AppliesCoupon("SAVE10")`); el driver sabe si habla con el dominio, la API o la UI. Así el mismo `.feature` se ejecuta en varias capas y un cambio de interfaz toca un único sitio, no cientos de pasos.
- **Escenarios que pueden fallar de verdad.** Un `Then` que no puede fallar es documentación falsa. Comprobar cada escenario nuevo rompiendo a propósito el código para ver que se pone rojo, y aserciones sobre el resultado observable, no sobre «no hubo excepción».
- **Datos controlados por el escenario.** El tiempo (`today is 2026-12-01`), los identificadores y los generadores aleatorios entran por contexto o por hooks, nunca por el reloj del sistema. Un escenario de caducidad que depende de `DateTime.Now` empezará a fallar sin tocar el código.
- **Paralelizar de forma segura.** xUnit ejecuta cada clase de test (cada `.feature`) en paralelo con las demás, y el contexto inyectado es por escenario, así que el único estado compartido es el que se cree en recursos globales (base de datos, ficheros, puertos). Un `[BeforeFeature]` con una base de datos compartida y escenarios que la modifican rompe el paralelismo; aislar por escenario o por esquema.
- **Revisar los `.feature` como se revisa código.** Una revisión de pull request debería incluir a quien conoce el negocio; un cambio de regla empieza editando el escenario, no el código. Si en la revisión nadie lee el `.feature`, la capa ha dejado de cumplir su función.

## Documentación oficial

- [Cucumber: referencia de Gherkin](https://cucumber.io/docs/gherkin/reference/) — la definición canónica de cada palabra clave (`Rule`, `Background`, `Scenario Outline`, etiquetas, tablas, doc strings). Consultarla cuando haya dudas sobre qué admite el lenguaje.
- [Cucumber: Example Mapping](https://cucumber.io/docs/bdd/example-mapping/) — las cuatro tarjetas, cómo conducir la sesión y qué hacer con las preguntas pendientes.
- [Documentación de Reqnroll](https://docs.reqnroll.net/latest/) — instalación, definiciones de pasos, inyección de contexto, *hooks* y formatters; empezar por *Step Definitions* y *Context Injection*.
- [Dan North: Introducing BDD](https://dannorth.net/blog/introducing-bdd/) — el artículo original de 2006 que acuñó el término.

## Recursos didácticos

- [Cucumber: Writing better Gherkin](https://cucumber.io/docs/bdd/better-gherkin/) — consejos sobre declarativo frente a imperativo, con ejemplos contrastados.
- [Cucumber: BDD](https://cucumber.io/docs/bdd/) — visión general de las tres prácticas de descubrimiento, formulación y automatización.

---

*En resumen: BDD es ponerse de acuerdo, con ejemplos concretos y en el lenguaje del negocio, sobre qué debe hacer el software antes de escribirlo; Gherkin y Reqnroll solo convierten ese acuerdo en una prueba que falla hasta que es verdad.*
