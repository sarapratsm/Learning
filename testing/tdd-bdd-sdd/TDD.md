# TDD (Test-Driven Development)

## ¿Qué es?

TDD, *Test-Driven Development* o desarrollo guiado por pruebas, es una forma de programar en la que **el test se escribe antes que el código que lo hace pasar**, en ciclos de minutos: un test que falla (rojo), el código mínimo para que pase (verde) y una limpieza del diseño con la red de seguridad de los tests (refactor).

## ¿Por qué existe?

Escribir el código primero y los tests después tiene tres problemas conocidos. Los tests que nacen después de la implementación se adaptan a lo que el código ya hace, no a lo que debería hacer. Salen difíciles de escribir porque el código no se pensó para ser probado (constructores que abren conexiones, `DateTime.Now` enterrado en medio de un método). Y, con la presión de la entrega, se quedan sin escribir.

TDD invierte el orden y con él los incentivos: el test es la primera «persona» que usa el código, así que el diseño nace usable y comprobable. Cada comportamiento queda protegido desde el minuto uno, y el refactor se hace sin miedo porque hay una alarma que salta si algo se rompe.

> Si ya haces control de calidad con listas de comprobación, piensa en TDD como escribir la lista de comprobación **antes** de construir la pieza y construirla hasta que todas las casillas pasan.

Qué **no** es TDD:

- **No es «escribir muchos tests».** Se pueden escribir mil tests después del código y no hacer TDD; el ritmo (test primero, paso pequeño, refactor) es lo que define la práctica.
- **No es una técnica de testing, sino de diseño.** Los tests que quedan son un subproducto valioso; el beneficio principal es que el código se descompone en piezas pequeñas, desacopladas y con dependencias explícitas.
- **No es incompatible con pensar de antemano.** Se piensa en la lista de comportamientos y en la forma de la API; lo que no se hace es implementar un diseño completo de golpe.
- **No es lo mismo que BDD ni que SDD.** [BDD](BDD.md) describe el comportamiento en el lenguaje del negocio y [SDD](SDD.md) parte de especificaciones; TDD trabaja en el nivel del código, entre programadores.

## ¿Cuándo y para qué se usa?

Cuando la lógica tiene reglas con casos y bordes, y el coste de equivocarse es mayor que el de escribir el test: reglas de precios y descuentos, cálculos de impuestos, máquinas de estados de un pedido, validaciones, algoritmos de reparto.

El ejemplo conductor es una tienda online en C# con xUnit. El dominio tiene un `Cart` (carrito) con líneas `CartItem` de un `Product`, y la regla **cupón de descuento**: el código `SAVE10` da un 10 % sobre el subtotal, **no es acumulable**, **caduca** y exige un **importe mínimo** de 50 €. Un pedido de referencia, el **#4711**, lleva tres cables de 19,99 €.

Los tests usan [xUnit](../testing-dotnet/xUnit.md), [Shouldly](../testing-dotnet/Shouldly.md) y [NSubstitute](../testing-dotnet/NSubstitute.md); la estructura de cada test sigue [Arrange-Act-Assert](../testing-dotnet/Arrange-Act-Assert.md). Todo el código de esta ficha se compiló y ejecutó con .NET 10, xUnit 2.9.3, Shouldly 4.3.0, NSubstitute 6.2.0 y Microsoft.Extensions.TimeProvider.Testing (excepto los fragmentos marcados como ilustrativos o sin ejecutar).

## El ciclo rojo-verde-refactor

| Fase | Qué se hace | Regla |
|---|---|---|
| 🔴 Rojo | Escribir **un** test que falle, y verlo fallar por la razón esperada | Sin test rojo no se toca código de producción |
| 🟢 Verde | Escribir el código **mínimo** que lo hace pasar, aunque sea feo o falso | Pasar el test, no resolver el mundo |
| 🔵 Refactor | Mejorar el diseño (nombres, duplicación, estructura) sin cambiar comportamiento | Solo con todos los tests en verde; se corren tras cada cambio |

Las *Tres Leyes del TDD* de Robert C. Martin fijan el ritmo en segundos: no escribir código de producción salvo para pasar un test que falla; no escribir más de un test del necesario para fallar (y no compilar cuenta como fallar); no escribir más código de producción del necesario para pasar el test que falla actual.

Ver el rojo es parte del ciclo, no un trámite. Un test que nunca ha fallado no demuestra nada: puede estar comprobando algo que siempre es verdad. El rojo prueba que el test **puede** fallar y que falla por el motivo correcto.

## Sesión guiada: el cupón SAVE10, ronda a ronda

El código resultante crece test a test. Las salidas de `dotnet test` son reales (observadas el 2026-10-30, rutas recortadas con `...`).

### Lista de tests inicial

Antes del primer test se anotan, sin implementar, los comportamientos que faltan por cubrir. Esa lista cambia durante la sesión (ver la sección de lista de tests más abajo):

```
[ ] SAVE10 descuenta el 10 % del subtotal
[ ] funciona con cualquier subtotal, no solo uno
[ ] un código desconocido se rechaza
[ ] subtotal por debajo de 50 € se rechaza
[ ] un segundo cupón no se acumula
[ ] el cupón caduca
```

### Ronda 1: primer test, implementación falsa

El primer test cuenta cómo se quiere usar el carrito:

```csharp
public class CartCouponTests
{
    [Fact]
    public void SAVE10_descuenta_el_10_por_ciento_del_subtotal()
    {
        var cart = new Cart();
        cart.Add(new Product(1, "Teclado", 100m), 1);

        cart.ApplyCoupon("SAVE10");

        cart.Total.ShouldBe(90m);
    }
}
```

🔴 `Cart` y `Product` no existen. En .NET, no compilar es la primera forma de rojo:

```
CartCouponTests.cs(10,24): error CS0246: El nombre del tipo o del espacio de nombres 'Cart' no se encontró
CartCouponTests.cs(11,22): error CS0246: El nombre del tipo o del espacio de nombres 'Product' no se encontró
```

Se crea el esqueleto que compila, con lo que el test ya puede ejecutarse. Para ver un rojo **útil**, el esqueleto calcula el subtotal y deja el cupón sin hacer nada:

```csharp
public record Product(int Id, string Name, decimal Price);

public class Cart
{
    private readonly List<(Product Product, int Quantity)> _items = [];

    public void Add(Product product, int quantity) => _items.Add((product, quantity));
    public decimal Subtotal => _items.Sum(i => i.Product.Price * i.Quantity);
    public void ApplyCoupon(string code) { }
    public decimal Total => Subtotal;
}
```

```
  Con error Tienda.Tests.CartCouponTests.SAVE10_descuenta_el_10_por_ciento_del_subtotal [36 ms]
  Mensaje de error:
   Shouldly.ShouldAssertException : cart.Total
    should be
90m
    but was
100m

Con error! - Con error: 1, Superado: 0, Omitido: 0, Total: 1
```

El rojo es el esperado: el total debería ser 90 y es 100. (Con el esqueleto lanzando `NotImplementedException` el test también fallaba, pero por una razón que no dice nada del cupón.)

🟢 El código mínimo para pasar a verde es, literalmente, devolver la constante:

```csharp
public decimal Total => 90m;
```

```
Correctas! - Con error: 0, Superado: 1, Omitido: 0, Total: 1
```

Parece una trampa y es una técnica con nombre (*implementación falsa*, descrita más abajo). Lo importante es que el test está verde y con una única constante que ahora hay que obligar a desaparecer.

🔵 Refactor: no hay nada que limpiar todavía.

### Ronda 2: triangulación

Un segundo test con otro subtotal hace imposible la constante:

```csharp
[Fact]
public void SAVE10_descuenta_el_10_por_ciento_con_otro_subtotal()
{
    var cart = new Cart();
    cart.Add(new Product(2, "Ratón", 59.90m), 1);

    cart.ApplyCoupon("SAVE10");

    cart.Total.ShouldBe(53.91m);
}
```

🔴 Falla porque `Total` sigue siendo `90m`:

```
Shouldly.ShouldAssertException : cart.Total
    should be
53.91m
    but was
90m
```

🟢 Ya sobra la constante; se generaliza con lo que dicen los dos ejemplos:

```csharp
private decimal _discount;

public void ApplyCoupon(string code)
{
    if (code == "SAVE10") _discount = Subtotal * 0.10m;
}

public decimal Total => Subtotal - _discount;
```

Los dos tests pasan. 🔵 Todavía no hay duplicación que justifique tocar nada.

### Ronda 3: código desconocido (cambia la firma)

El test necesita saber si el cupón se aceptó, así que `ApplyCoupon` pasa a devolver un resultado. El test de la ronda 1 y el de la 2 no leen el valor devuelto y siguen compilando:

```csharp
[Fact]
public void Un_codigo_desconocido_se_rechaza_y_no_cambia_el_total()
{
    var cart = new Cart();
    cart.Add(new Product(1, "Teclado", 100m), 1);

    var result = cart.ApplyCoupon("NOPE");

    result.ShouldBe(CouponResult.Unknown);
    cart.Total.ShouldBe(100m);
}
```

🔴 Primero no compila (`CouponResult` no existe). Con el `enum` creado y `ApplyCoupon` devolviendo siempre `Applied`:

```
Shouldly.ShouldAssertException : result
    should be
CouponResult.Unknown
    but was
CouponResult.Applied
```

🟢

```csharp
public enum CouponResult { Applied, Unknown, BelowMinimum, AlreadyApplied }

public CouponResult ApplyCoupon(string code)
{
    if (code != "SAVE10") return CouponResult.Unknown;
    _discount = Subtotal * 0.10m;
    return CouponResult.Applied;
}
```

El `enum` ya contiene los otros dos valores porque la lista de tests los anuncia; el código **de producción** que los usa no existe hasta que un test lo exija.

### Ronda 4: importe mínimo

```csharp
[Fact]
public void SAVE10_se_rechaza_si_el_subtotal_no_llega_al_minimo()
{
    var cart = new Cart();
    cart.Add(new Product(3, "Alfombrilla", 49.99m), 1);

    var result = cart.ApplyCoupon("SAVE10");

    result.ShouldBe(CouponResult.BelowMinimum);
    cart.Total.ShouldBe(49.99m);
}
```

🔴 `but was CouponResult.Applied`. 🟢 Una línea:

```csharp
if (code != "SAVE10") return CouponResult.Unknown;
if (Subtotal < 50m) return CouponResult.BelowMinimum;
```

El valor 49,99 es deliberado: un céntimo por debajo del borde. Los errores viven en los bordes, y el borde hay que elegirlo a propósito.

### Ronda 5: no acumulable

```csharp
[Fact]
public void Un_segundo_cupon_no_se_acumula()
{
    var cart = new Cart();
    cart.Add(new Product(1, "Teclado", 100m), 1);
    cart.ApplyCoupon("SAVE10");

    var result = cart.ApplyCoupon("SAVE10");

    result.ShouldBe(CouponResult.AlreadyApplied);
    cart.Total.ShouldBe(90m);
}
```

🔴 `but was CouponResult.Applied`. 🟢 Un indicador de «ya hay cupón»:

```csharp
private bool _couponApplied;

public CouponResult ApplyCoupon(string code)
{
    if (code != "SAVE10") return CouponResult.Unknown;
    if (_couponApplied) return CouponResult.AlreadyApplied;
    if (Subtotal < 50m) return CouponResult.BelowMinimum;
    _discount = Subtotal * 0.10m;
    _couponApplied = true;
    return CouponResult.Applied;
}
```

🔵 Refactor: el método mezcla tres cosas (qué cupón es, si procede y cuánto descuenta) y los números 0.10 y 50 son datos del cupón, no del carrito. Es la señal para extraer un concepto, pero todavía no: hay un test de la lista sin hacer que va a tocar esa misma línea.

### Ronda 6: redondeo (el pedido #4711)

```csharp
[Fact]
public void El_descuento_se_redondea_a_dos_decimales()
{
    var cart = new Cart();
    cart.Add(new Product(4, "Cable", 19.99m), 3);   // 59,97 €: el pedido #4711

    cart.ApplyCoupon("SAVE10");

    cart.Total.ShouldBe(53.97m);
}
```

🔴 Este rojo enseña algo que ningún test anterior habría detectado: 59,97 × 0,10 = 5,997, y el total sale con cuatro decimales.

```
Shouldly.ShouldAssertException : cart.Total
    should be
53.97m
    but was
53.9730m
```

🟢 `_discount = Math.Round(Subtotal * 0.10m, 2, MidpointRounding.AwayFromZero);` y los seis tests pasan.

### Refactor con la red puesta

Con seis tests en verde, el concepto que pedían las rondas 4 a 6 se extrae: el cupón es un dato (código, porcentaje, mínimo) con su propia lógica de importe.

```csharp
public record Coupon(string Code, decimal Rate, decimal MinSubtotal, DateTimeOffset ExpiresAt)
{
    public bool AppliesTo(decimal subtotal) => subtotal >= MinSubtotal;

    public decimal DiscountFor(decimal subtotal) =>
        Math.Round(subtotal * Rate, 2, MidpointRounding.AwayFromZero);
}

public class Cart : ICart
{
    private readonly List<(Product Product, int Quantity)> _items = [];
    private Coupon? _coupon;

    public void Add(Product product, int quantity) => _items.Add((product, quantity));
    public decimal Subtotal => _items.Sum(i => i.Product.Price * i.Quantity);
    public decimal Total => Subtotal - (_coupon?.DiscountFor(Subtotal) ?? 0m);

    public CouponResult Apply(Coupon coupon)
    {
        if (_coupon is not null) return CouponResult.AlreadyApplied;
        if (!coupon.AppliesTo(Subtotal)) return CouponResult.BelowMinimum;
        _coupon = coupon;
        return CouponResult.Applied;
    }
}
```

Desaparecen el `_discount` mutable, los números mágicos y el indicador. La búsqueda del cupón por código (y la caducidad, el último test de la lista) no cabe aquí: el carrito no sabe qué hora es ni dónde viven los cupones. Eso se resuelve en la sección sobre diseño, y es precisamente el test de la caducidad el que lo exige.

El refactor tocó la firma (`ApplyCoupon(string)` pasó a `Apply(Coupon)`), así que los tests del carrito cambian su *arrange* (reciben un `Coupon` en lugar de un código) pero **no sus asserts**: siguen exigiendo el mismo total y el mismo resultado. Cuando un refactor obliga a reescribir los asserts, el test estaba acoplado a la implementación.

## Las tres estrategias para pasar a verde

Kent Beck describe tres formas de llegar al verde. La elección depende de la confianza que se tenga en la solución.

| Estrategia | Qué hace | Cuándo usarla | Ejemplo en la sesión |
|---|---|---|---|
| **Implementación falsa** | Devolver una constante y generalizar después | Terreno incierto; se quiere ver el verde ya | `Total => 90m` (ronda 1) |
| **Triangulación** | Añadir un 2.º ejemplo que obligue a generalizar | No está clara la forma de la abstracción | `59,90 → 53,91` (ronda 2) |
| **Implementación obvia** | Escribir directamente la solución real | La solución es evidente y cabe en pocas líneas | `if (Subtotal < 50m) return BelowMinimum;` (ronda 4) |

Reglas prácticas:

- Se empieza por la obvia cuando se sabe. Si el test sale rojo (la «obvia» no lo era), se retrocede a falsa o triangulación.
- La triangulación **solo** se usa cuando la generalización no es evidente. Triangular lo evidente añade tests redundantes, no confianza.
- Un test que se pasa con una constante no es una falta de seriedad: es una afirmación verificable («al menos este caso funciona») que se estrecha con el siguiente test.

## La lista de tests y la elección del siguiente paso

La lista de tests es un apunte de comportamientos pendientes, escrito al empezar y vivo durante toda la sesión: se tacha lo hecho, se añaden los casos que aparecen por el camino y se descartan los que dejan de tener sentido. Al terminar la ronda 5 la lista tenía una entrada nueva que no estaba al inicio (el redondeo) y no se escribió antes porque nadie lo había pensado hasta ver `59,97`.

Cómo elegir el siguiente test:

- **El más simple que fuerce código nuevo.** No el más interesante.
- **El que te enseñe algo del diseño.** Si dos candidatos son igual de simples, el que obliga a decidir una firma o un tipo.
- **Los casos degenerados primero** (vacío, cero, nulo, desconocido) cuando son baratos; los bordes (49,99 y 50,00) después de que el caso feliz funcione.
- **Evitar saltos de abstracción.** Si el siguiente test exige tres cambios a la vez, falta un test intermedio.

### Tamaño del paso

El paso se ajusta a la confianza, no a una medida fija:

| Señal | Qué hacer |
|---|---|
| Los últimos tres tests han pasado a la primera | Agrandar el paso: implementación obvia, menos triangulación |
| Un test rojo lleva más de ~10 minutos sin pasar | Encoger: volver a verde (descartar o aplazar el test) y buscar un test intermedio |
| Se necesita depurar con el depurador para entender el fallo | Encoger: el paso fue demasiado grande |
| Un test «nace verde» sin tocar código | Revisar: o estaba cubierto por otro test, o no comprueba nada |

Un test que nace verde no siempre es un error. En la sesión, un test «sin cupón, el total es el subtotal» habría pasado ya desde la ronda 1; se aceptaría como documentación y con la certeza de que *se puede romper* (se verifica estropeando el código a mano y viendo el rojo).

## El test guía el diseño

El último test de la lista, **el cupón caduca**, no se puede escribir contra el carrito de la sesión sin que el diseño proteste:

```csharp
// ❌ Imposible de probar sin esperar al calendario
public CouponResult ApplyCoupon(string code)
{
    if (DateTime.UtcNow >= _expiresAt) return CouponResult.Expired;   // ¿qué fecha pone el test?
    ...
}
```

Para probarlo habría que tocar el reloj del sistema, o crear cupones cuya caducidad sea «mañana» y esperar al día siguiente. **El dolor de escribir el test es la señal de diseño**: el carrito tiene tres responsabilidades (líneas, buscar cupones, comprobar la hora). La respuesta es separar y **inyectar las dependencias** que el comportamiento necesita:

```csharp
public interface ICouponRepository
{
    Coupon? FindByCode(string code);
}

public interface ICart
{
    CouponResult Apply(Coupon coupon);
}

public class CouponService(ICouponRepository repository, TimeProvider clock)
{
    public CouponResult Apply(ICart cart, string code)
    {
        var coupon = repository.FindByCode(code);
        if (coupon is null) return CouponResult.Unknown;
        if (coupon.ExpiresAt <= clock.GetUtcNow()) return CouponResult.Expired;
        return cart.Apply(coupon);
    }
}
```

`TimeProvider` es la abstracción del reloj que incluye .NET desde la versión 8; en tests se sustituye por `FakeTimeProvider`, del paquete `Microsoft.Extensions.TimeProvider.Testing`, que permite fijar la hora y avanzarla a voluntad. Con las dependencias a la vista, el test es corto y determinista:

```csharp
private static readonly DateTimeOffset Today = new(2026, 10, 30, 12, 0, 0, TimeSpan.Zero);

[Fact]
public void El_dia_exacto_de_caducidad_ya_no_vale()
{
    var repository = new InMemoryCouponRepository(Save10(expiresAt: Today));
    var service = new CouponService(repository, new FakeTimeProvider(Today));

    service.Apply(new Cart(), "SAVE10").ShouldBe(CouponResult.Expired);
}
```

La decisión «el día exacto de caducidad ya no vale» (`<=` y no `<`) quedó escrita como test y no como suposición en la cabeza de alguien.

Otras señales de dolor al escribir el test y qué indican:

| Dolor al escribir el test | Qué suele indicar | Respuesta |
|---|---|---|
| El *arrange* ocupa 30 líneas | Demasiadas dependencias o una clase con demasiadas responsabilidades | Partir la clase; un *builder* solo si el dominio lo justifica |
| Hay que usar reflexión o `InternalsVisibleTo` para llegar a algo | La lógica importante está escondida en un detalle privado | Extraer a una clase pública pequeña |
| Hay que sustituir cinco colaboradores | La clase coordina demasiado | Revisar el límite del módulo |
| El test depende de la hora, del azar o del disco | Dependencia no inyectada | `TimeProvider`, una abstracción del azar, un puerto de ficheros |
| Un cambio de nombre privado rompe diez tests | El test conoce la implementación | Probar por la API pública (ver errores frecuentes) |

## Escuela clásica y escuela mockista

Hay dos estilos de TDD que se diferencian en **qué se sustituye** y **qué se comprueba**. Martin Fowler los describe en «Mocks Aren't Stubs».

| | Clásica (Chicago, de estado) | Mockista (London, de interacción) |
|---|---|---|
| Colaboradores | Reales siempre que sea práctico; dobles solo para lo lento o no determinista | Sustituidos todos los que tengan comportamiento |
| Qué se comprueba | El **estado** resultante (valores devueltos, propiedades) | Las **llamadas** que hace el objeto a sus colaboradores |
| Dirección del diseño | De dentro hacia fuera: se empieza por el dominio | De fuera hacia dentro: se empieza por el borde y se descubren las dependencias |
| Resistencia al refactor | Alta: cambiar cómo colaboran las clases no rompe tests | Baja: cambiar la conversación entre clases rompe tests |
| Aislamiento | Un fallo puede romper varios tests (comparten código real) | Un fallo señala a una sola clase |
| Riesgo típico | Tests más grandes; arranques con mucho *setup* real | Tests que reflejan el código y pasan con un sistema roto |
| Encaja bien con | Lógica de dominio, cálculos, reglas | Orquestación, límites con sistemas externos |

El mismo comportamiento («un cupón caducado no se aplica») escrito de las dos formas, tal como se compilaron y ejecutaron:

```csharp
// Clásica: repositorio en memoria, Cart real, se comprueba el estado
[Fact]
public void Chicago_un_cupon_caducado_no_cambia_el_total()
{
    var repository = new InMemoryCouponRepository(Save10(Today.AddDays(-1)));
    var service = new CouponService(repository, new FakeTimeProvider(Today));
    var cart = new Cart();
    cart.Add(new Product(1, "Teclado", 100m), 1);

    var result = service.Apply(cart, "SAVE10");

    result.ShouldBe(CouponResult.Expired);
    cart.Total.ShouldBe(100m);
}

// Mockista: todo sustituido, se comprueba la interacción
[Fact]
public void London_un_cupon_caducado_no_llega_al_carrito()
{
    var repository = Substitute.For<ICouponRepository>();
    repository.FindByCode("SAVE10").Returns(Save10(Today.AddDays(-1)));
    var cart = Substitute.For<ICart>();
    var service = new CouponService(repository, new FakeTimeProvider(Today));

    var result = service.Apply(cart, "SAVE10");

    result.ShouldBe(CouponResult.Expired);
    cart.DidNotReceive().Apply(Arg.Any<Coupon>());
}
```

La versión clásica sobrevive a que mañana `CouponService` deje de llamar a `cart.Apply` y use otro método del carrito; la mockista deja de compilar o falla. En cambio, la mockista dice explícitamente «el carrito no se toca», algo que el test de estado solo deduce.

Criterio de uso:

- **Por defecto, clásica** para lógica de dominio: el `Cart` y el `Coupon` se prueban con objetos reales.
- **Mockista (o dobles)** para las **fronteras**: repositorios, relojes, pasarelas de pago, correo. Se sustituye lo que cruza el límite del proceso o es no determinista.
- **Mezclar es normal.** En el ejemplo, el repositorio es siempre un doble y el carrito se sustituye solo cuando se quiere afirmar que no se llama.
- Verificar con `Received()` una llamada que es detalle de implementación (un `Log`, un orden interno) crea el acoplamiento que se quiere evitar. Se verifica la interacción cuando **es** el comportamiento: «no se cobra», «se envía un único correo».

## TDD en la práctica

### Bugs: el test que reproduce, primero

Un bug es un comportamiento que ningún test pidió. El procedimiento es siempre el mismo:

1. Escribir el test que **reproduce** el fallo con los datos del informe y ver cómo falla (mismo mensaje que en producción).
2. Arreglar el código con el cambio mínimo.
3. Ver el verde y dejar el test: es el test de regresión más barato que existe.

Fragmento ilustrativo (sin ejecutar): informe «tras quitar productos, el cupón sigue aplicado aunque el carrito baje de 50 €».

```csharp
[Fact]
public void Quitar_un_producto_que_baja_del_minimo_retira_el_cupon()
{
    var cart = new Cart();
    cart.Add(new Product(1, "Teclado", 40m), 1);
    cart.Add(new Product(2, "Ratón", 20m), 1);
    cart.Apply(Save10);                       // subtotal 60 → vale
    cart.Remove(productId: 1);                // subtotal 20 → ya no cumple el mínimo

    cart.Total.ShouldBe(20m);                 // rojo: calcula 18
}
```

Un test que reproduce el bug y que **no** falla significa que no se ha entendido el bug: el siguiente paso es volver a leer el informe, no arreglar a ciegas.

### Código legado: tests de caracterización y costuras

El código heredado sin tests no permite el ciclo habitual porque no se sabe qué debe hacer. Se invierte el orden: primero se **fija lo que hace** y después se cambia.

- **Test de caracterización:** se llama al código con una entrada, se anota la salida real (aunque parezca un error) y se escribe un test que afirma esa salida. No dice que sea correcta; dice que no ha cambiado.
- **Costura (*seam*):** un punto donde se puede cambiar el comportamiento sin editar el código que se prueba. En C#, la más barata es el constructor: sustituir la llamada directa a `DateTime.Now` o a un `new SqlConnection(...)` por una dependencia inyectada, manteniendo un constructor sin parámetros que usa los valores reales para no romper a quien ya llama.

```csharp
// Antes: no se puede fijar la hora
public class LegacyPricing
{
    public decimal Price(Product p) => IsSaleSeason(DateTime.Now) ? p.Price * 0.8m : p.Price;
}

// Después: costura mínima, comportamiento idéntico para el código existente
public class LegacyPricing(TimeProvider clock)
{
    public LegacyPricing() : this(TimeProvider.System) { }
    public decimal Price(Product p) => IsSaleSeason(clock.GetLocalNow().DateTime) ? p.Price * 0.8m : p.Price;
}
```

Fragmento ilustrativo (sin ejecutar). Con la costura puesta, el flujo es: test de caracterización → refactor → nuevo comportamiento con el ciclo normal.

### HTTP y acceso a datos: por qué ahí se pasa a integración

TDD funciona bien en lo que es lógica pura. En los bordes, el valor de un test está en comprobar que la **tecnología** hace lo que se cree, y un doble no puede comprobarlo:

| Capa | Qué se puede hacer con TDD puro | Dónde falla un doble | Qué se hace |
|---|---|---|---|
| Endpoint HTTP (`POST /api/cart/4711/coupon`) | La lógica del servicio de cupones | No prueba enrutado, serialización, códigos de estado, validación del modelo | Test de integración con [WebApplicationFactory](../testing-dotnet/WebApplicationFactory.md) |
| Repositorio / SQL | La interfaz `ICouponRepository` y los tests del servicio que la usa | No prueba que el SQL sea válido ni las restricciones de la base | Test de integración con [Testcontainers](../testing-dotnet/Testcontainers.md) y una base real |
| Cliente de pasarela de pago | El contrato propio (qué se pide, qué se hace con cada respuesta) | No prueba el contrato real con el tercero | Test de contrato o de integración contra un sandbox |

Un método válido es TDD en dos niveles: un test de integración grueso que describe el caso de extremo a extremo (rojo durante un rato) y, dentro, ciclos rojo-verde-refactor sobre las piezas. Para la clasificación de los niveles, véase [Tipos de tests](../testing-dotnet/Tipos-de-tests.md).

### Kata de calentamiento

El *String Calculator* es el kata clásico de TDD: un método `Add(string)` que suma números separados por comas y crece con cada requisito (cadena vacía, cualquier cantidad, saltos de línea, delimitadores propios, negativos que lanzan excepción, números mayores de 1000 ignorados). Se practica con una regla: **un test por vez, solo el código mínimo**. Conviene repetirlo varias veces, de forma deliberadamente más lenta, para interiorizar el ritmo, y comparar las soluciones: la forma final suele cambiar entre intentos.

## Cuándo no usar TDD

TDD cuesta tiempo al principio de cada comportamiento y devuelve valor cuando ese comportamiento hay que mantenerlo. Si no hay nada que mantener, o si no se sabe todavía qué construir, el coste no se recupera.

| Situación | ¿TDD? | Por qué |
|---|---|---|
| Reglas de negocio (descuentos, impuestos, estados) | ✅ Sí | Casos, bordes y mucho coste si fallan |
| Algoritmos con entradas y salidas claras | ✅ Sí | El test es la especificación |
| Corrección de bugs | ✅ Sí | El test de reproducción es el entregable |
| Refactor de código legado | ✅ Con caracterización | Hay que fijar lo que hace antes de moverlo |
| Spike o prototipo para aprender (¿esta API sirve?) | ❌ No | Se tira el código; los tests también se tirarían |
| UI visual (disposición, estilos, animaciones) | ❌ Poco rentable | Se juzga mirando; la lógica de presentación sí se puede extraer y probar |
| Script desechable de una sola ejecución | ❌ No | No hay segunda ejecución que proteger |
| Código de pegamento (configuración, `Program.cs`, registro de DI) | ❌ Poco rentable | Lo cubre un test de integración o el arranque de la aplicación |
| Requisitos que cambian cada hora | ⚠️ Con cuidado | Mejor descubrir primero; fijar con tests cuando se estabilice |

Una práctica habitual con los *spikes*: explorar sin tests, **tirar el código** y rehacerlo con TDD con lo aprendido. Conservar el spike «y añadirle tests después» recupera los problemas de siempre.

## Errores frecuentes

| Síntoma | Causa | Remedio |
|---|---|---|
| Cambiar el nombre de un método privado rompe 15 tests | Tests acoplados a la implementación: acceden a lo privado (reflexión, `InternalsVisibleTo` abusivo) o verifican llamadas internas | Probar por la API pública y por el efecto observable, no por cómo se consigue |
| Se refactoriza y hay que reescribir los asserts | Los asserts describen la estructura (`Received(1)` a un colaborador interno) en vez del resultado | Aserciones sobre estado o sobre interacciones que sean contrato real |
| Hay tests de `Cart.Items` que comprueban que el *getter* devuelve lo que el *setter* guardó | Test sin comportamiento: cubre una línea, no una regla | Borrarlo; si hay una regla detrás (p. ej. no admitir cantidad negativa), testear esa regla |
| Un test pasa aunque se rompa el código | Nunca fue rojo, o no tiene aserción (`cart.Apply(c);` sin `ShouldBe`) | Ver siempre el rojo; estropear el código a mano y confirmar que el test salta |
| La suite pasa y producción falla con cupones caducados | El reloj se lee con `DateTime.UtcNow` en medio del código y el test solo cubre cupones vigentes | Inyectar `TimeProvider` y cubrir los dos lados del borde |
| Se escribe medio módulo y luego «se añaden los tests» | Se ha perdido el ritmo: TDD se ha convertido en test-después | Volver al paso pequeño; un test por vez |
| Refactor con la suite en rojo | Se mezcla cambiar comportamiento y cambiar estructura | Volver a verde (deshacer si hace falta); refactorizar solo en verde |
| Tests que pasan solos y fallan en conjunto, o viceversa | Estado compartido entre tests (campos estáticos, base de datos) | Cada test crea lo que usa; véase [Fixtures y ciclo de vida](../testing-dotnet/Fixtures-y-ciclo-de-vida.md) |
| Un test necesita 40 líneas de `Substitute.For` | Mocks en exceso: la clase tiene demasiados colaboradores o se simula lo que se debería usar real | Usar el objeto real si es rápido y determinista (`Cart`, `Coupon`); revisar responsabilidades |
| La suite tarda 6 minutos y nadie la ejecuta | Tests lentos: acceso a base de datos o `Thread.Sleep` en tests de unidad | Los de lógica, en memoria y en milisegundos; los de base de datos, en un proyecto aparte |
| El mismo caso está repetido en seis tests | Tests redundantes tras triangular lo evidente | Fusionar con `[Theory]` o borrar los que no añaden información |
| Un test comprueba cinco comportamientos | Test «de escenario» con un solo `Fact` | Un comportamiento por test: cuando falla, el nombre dice qué se rompió |

La referencia de tiempo de feedback: un ciclo de TDD es cómodo con una suite de unidad que corre en **menos de 10 segundos**. Con 2 000 tests de 150 ms cada uno (por ejemplo, porque tocan una base de datos), son 5 minutos por ejecución: a ese precio nadie la lanza tras cada cambio y el ciclo se rompe.

## Métricas y señales honestas

**La cobertura no es el objetivo.** Mide qué líneas se ejecutaron, no si alguien comprobó algo. Este test deja la clase `Cart` al 100 % de cobertura de líneas en el método `Apply` y no protege nada:

```csharp
[Fact]
public void Apply_no_lanza()
{
    var cart = new Cart();
    cart.Add(new Product(1, "Teclado", 100m), 1);
    cart.Apply(Save10);          // sin aserción: cubre, pero no comprueba
}
```

La cobertura con [Coverlet](../testing-dotnet/Coverlet.md) sirve en negativo: una zona con 0 % es una zona que ningún test toca. Un 90 % no dice que esté bien probada.

**Mutation testing** responde a la pregunta que la cobertura no responde: *¿los tests fallarían si el código estuviera mal?* La herramienta introduce pequeños cambios (mutantes) en el código, como `>=` por `>`, y ejecuta los tests: si siguen pasando, el mutante **sobrevive** y señala un hueco. En .NET lo hace Stryker.NET:

```bash
dotnet tool install -g dotnet-stryker
cd tests/Tienda.Tests
dotnet stryker
```

Ejemplo razonado (sin ejecutar): en `Coupon.AppliesTo`, cambiar `subtotal >= MinSubtotal` por `subtotal > MinSubtotal` hace que un carrito de exactamente 50,00 € se rechace. Los tests de la sesión usan 100 y 49,99 y **ninguno usa 50,00**: el mutante sobrevive pese a tener el método cubierto al 100 %. La acción es añadir el test del borde `50,00 → Applied`, y el mutante muere.

Señales útiles, en orden de valor:

| Señal | Qué dice | Cómo leerla |
|---|---|---|
| Tiempo de feedback (de guardar a ver el resultado) | Si el ciclo es viable | Segundos: bien. Minutos: se acaba el TDD |
| Mutantes supervivientes | Huecos reales en los tests | Revisar los de lógica de dominio; ignorar los de logs o mensajes |
| Frecuencia de tests rojos por causa ajena al cambio | Tests frágiles o dependientes de estado | Cada fallo espurio resta confianza en la suite |
| Bugs que llegan a producción sin test que los reprodujese | Si se está haciendo el test del bug | Cada bug debe dejar su test |
| Cobertura por zonas | Dónde no hay nada | Útil en negativo; un número global no sirve |

Medir y exigir un porcentaje de cobertura como objetivo del equipo lo convierte en objeto de optimización: aparecen los tests sin aserciones para subir el número.

## Buenas prácticas avanzadas

- **Nombra el test con el comportamiento y la regla, no con el método.** `SAVE10_se_rechaza_si_el_subtotal_no_llega_al_minimo` documenta una regla del negocio y, cuando falla, indica qué se rompió sin abrir el código; `ApplyCoupon_Test3` no dice nada. Cuando un test es difícil de nombrar, suele probar dos cosas.
- **Un único motivo de fallo por test, y asserts sobre el resultado, no sobre el camino.** Dos asserts sobre el mismo resultado (`result` y `Total`) son un comportamiento; tres sobre cosas distintas son tres tests. Verificar el camino (`Received`) solo cuando es contrato.
- **Usa el rojo como instrumento.** Si el mensaje del rojo no te permite saber qué pasó sin abrir el test, mejora el test (nombre, valores con significado, mensaje de Shouldly). Un rojo claro hace que el verde cueste menos.
- **Haz el refactor también en los tests.** El código de test se duplica más que el de producción. Extrae constructores de datos de prueba (`Save10(expiresAt)`, `Today`) para que cada test cuente solo lo que le importa, sin esconder ahí los valores que explican el caso.
- **Congela las fuentes de no-determinismo en la frontera**: reloj (`TimeProvider`), azar (una interfaz con semilla), `Guid`, zona horaria, cultura (`1.234,50` y `1,234.50` dan tests distintos según la máquina). La suite debe dar el mismo resultado en la máquina de cada persona y en el servidor de integración continua.
- **Reserva los dobles para las costuras que aporten valor y deja los tests de dominio sin dobles.** Cuando cada test de una clase sustituye al repositorio, al reloj y a dos servicios, la lógica real ya no se está ejecutando en ninguna parte; el equilibrio es pocas fronteras sustituidas y mucho dominio real.

## Documentación oficial

- [Martin Fowler — Test Driven Development](https://martinfowler.com/bliki/TestDrivenDevelopment.html) — definición breve y de referencia del ciclo y de sus malentendidos; la página enlaza el resto de su obra sobre pruebas.
- [xUnit.net](https://xunit.net/) — documentación del marco con el que se escriben los tests de esta ficha; la sección *Getting started* para empezar, y *Comparisons* si se viene de NUnit o MSTest.
- [Stryker.NET — Introduction](https://stryker-mutator.io/docs/stryker-net/introduction/) — mutation testing para .NET: instalación, ejecución, opciones y cómo leer el informe de mutantes.

## Recursos didácticos

- [Martin Fowler — Mocks Aren't Stubs](https://martinfowler.com/articles/mocksArentStubs.html) — el artículo que distingue la escuela clásica de la mockista, con las diferencias entre dobles (*dummy*, *fake*, *stub*, *spy*, *mock*).
- [Robert C. Martin — The Cycles of TDD](https://blog.cleancoder.com/uncle-bob/2014/12/17/TheCyclesOfTDD.html) — las Tres Leyes y el ciclo rojo-verde-refactor vistos como ciclos anidados de segundos a horas.
- [Kata-Log — String Calculator](https://kata-log.rocks/string-calculator-kata) — enunciado paso a paso del kata de calentamiento; el sitio recoge más katas (*Fizz Buzz*, entre ellos) con etiqueta de TDD.
- *Test-Driven Development: By Example*, de Kent Beck (Addison-Wesley, 2002) — el libro que formalizó la práctica, con las estrategias de implementación falsa, triangulación e implementación obvia. No se enlaza ninguna página porque no se ha podido verificar una fuente pública fiable.

---

*En resumen: TDD es escribir primero un test que falle, hacerlo pasar con el código mínimo y limpiar el diseño con la red puesta, de modo que cada paso sea pequeño, cada comportamiento quede protegido y la dificultad de testear avise de un mal diseño antes de que sea caro.*
