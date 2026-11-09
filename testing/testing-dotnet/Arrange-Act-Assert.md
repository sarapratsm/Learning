# Arrange-Act-Assert

## ¿Qué es?

Un patrón para estructurar un test en tres bloques ordenados: **Arrange** (preparar el escenario), **Act** (ejecutar la acción que se prueba) y **Assert** (comprobar el resultado). Casi cualquier test bien escrito, en cualquier lenguaje, tiene esta forma, se marque o no con comentarios.

## ¿Por qué existe?

Un test sin estructura mezcla preparación, llamadas y comprobaciones, y al fallar no se sabe qué parte del escenario era la importante ni qué se estaba probando. AAA obliga a responder tres preguntas en orden: ¿de qué situación parto?, ¿qué acción pruebo?, ¿qué esperaba que pasara?

Es una historia en tres actos: **planteamiento** (se coloca a los personajes), **nudo** (ocurre una cosa) y **desenlace** (se ve qué cambió). Si en el nudo ocurren dos cosas, hay dos historias contadas como una, y cuando el final no cuadra no se sabe cuál de las dos se torció.

> El mismo patrón aparece en BDD con otros nombres: *Given-When-Then* (dado, cuando, entonces). Ver [BDD](../tdd-bdd-sdd/BDD.md).

## ¿Cuándo y para qué se usa?

En todos los tests, de unidad o de integración. Aquí los ejemplos son los de una tienda online: un `Pedido` con líneas, que se confirma, admite un cupón de descuento (máximo 50 %) y no se puede cancelar una vez pagado. Las salidas citadas provienen de un proyecto xUnit 2.9.3 sobre .NET 10 (Shouldly 4.3.0 solo donde se indica), ejecutado con `dotnet test` el 2026-11-09; el runner estaba en español y las rutas de fichero de los mensajes se abrevian.

El problema se ve comparando dos formas de probar lo mismo.

## El contraste: un test que prueba tres cosas y uno AAA

Un test que va haciendo cosas y comprobándolas sobre la marcha:

```csharp
// ❌ Preparación, acciones y aserciones entremezcladas
[Fact]
public void Pedido_funciona()
{
    var pedido = new Pedido(4711);
    pedido.Agregar(new Producto(1, "Camiseta", 20m), 2);
    pedido.Confirmar();
    Assert.Equal(EstadoPedido.Confirmado, pedido.Estado);
    pedido.AplicarCupon(10);
    Assert.Equal(36m, pedido.Total);
    pedido.Cancelar();
    Assert.Equal(EstadoPedido.Cancelado, pedido.Estado);
}
```

Prueba tres comportamientos (confirmar, aplicar un cupón, cancelar) y el nombre no dice ninguno. Para comprobar qué ocurre cuando `Confirmar()` olvida cambiar el estado se compiló el código de producción con ese fallo introducido a propósito. Salida:

```text
Con error PedidoTestsMal.Pedido_funciona [10 ms]
  Mensaje de error:
   Assert.Equal() Failure: Values differ
Expected: Confirmado
Actual:   Borrador
     at PedidoTestsMal.Pedido_funciona() in ...\Mal.cs:line 12
```

El mensaje no dice qué se estaba probando: hay que abrir el test y contar líneas. Y como el primer `Assert` que falla corta el test, **las demás comprobaciones no se ejecutan**: un segundo fallo en el cálculo del cupón (el mismo código con el cupón ignorado) queda oculto hasta arreglar el primero.

Los mismos comportamientos, un test por acción:

```csharp
// ✅ Una acción por test, nombre que dice qué se espera
[Fact]
public void Confirmar_con_lineas_pasa_a_Confirmado()
{
    // Arrange
    var pedido = new Pedido(4711);
    pedido.Agregar(new Producto(1, "Camiseta", 20m), 2);

    // Act
    pedido.Confirmar();

    // Assert
    Assert.Equal(EstadoPedido.Confirmado, pedido.Estado);
}

[Fact]
public void AplicarCupon_del_10_por_ciento_descuenta_el_total()
{
    var pedido = new Pedido(4711);
    pedido.Agregar(new Producto(1, "Camiseta", 20m), 2);

    pedido.AplicarCupon(10);

    Assert.Equal(36m, pedido.Total);
}

[Fact]
public void Cancelar_un_pedido_en_borrador_lo_cancela()
{
    var pedido = new Pedido(4711);

    pedido.Cancelar();

    Assert.Equal(EstadoPedido.Cancelado, pedido.Estado);
}
```

Con el código correcto, los tres pasan:

```text
Correctas! - Con error:     0, Superado:     3, Omitido:     0, Total:     3, Duración: 27 ms - Tienda.Tests.dll (net10.0)
```

Con los dos fallos introducidos (estado sin cambiar y cupón ignorado) se ven **los dos a la vez**, cada uno con su nombre:

```text
[xUnit.net 00:00:00.49]     PedidoTestsAaa.AplicarCupon_del_10_por_ciento_descuenta_el_total [FAIL]
[xUnit.net 00:00:00.49]     PedidoTestsAaa.Confirmar_con_lineas_pasa_a_Confirmado [FAIL]
  Con error PedidoTestsAaa.AplicarCupon_del_10_por_ciento_descuenta_el_total [3 ms]
   Assert.Equal() Failure: Values differ
Expected: 36
Actual:   40
```

El nombre del test que falla ya localiza el fallo; el mensaje solo aporta los valores.

## Los tres bloques y los comentarios

El ejemplo con comentarios `// Arrange`, `// Act` y `// Assert` y el mismo sin ellos:

```csharp
// Con comentarios: el bloque Arrange de Confirmar_con_lineas_pasa_a_Confirmado
// Arrange
var pedido = new Pedido(4711);
pedido.Agregar(new Producto(1, "Camiseta", 20m), 2);

// Act
pedido.Confirmar();

// Assert
Assert.Equal(EstadoPedido.Confirmado, pedido.Estado);
```

```csharp
// Sin comentarios: tres bloques separados por una línea en blanco
var pedido = new Pedido(4711);
pedido.Agregar(new Producto(1, "Camiseta", 20m), 2);

pedido.Confirmar();

Assert.Equal(EstadoPedido.Confirmado, pedido.Estado);
```

| Situación | Comentarios `// Arrange`… | Línea en blanco |
|---|---|---|
| Test de 3-4 líneas como el anterior | Ruido: la estructura se ve sola | Suficiente |
| Test con Arrange de varias líneas o de integración | Ayudan a localizar el Act de un vistazo | Insuficiente |
| Equipo que está aprendiendo el patrón | Útiles como andamio | — |
| Comentario que explica **por qué** (`// Arrange: cupón en el límite permitido`) | Aporta contexto | — |

Lo que sí es ruido siempre es el comentario que repite el código (`// Arrange: creamos el pedido`).

## Una sola acción por test

El bloque Act es **una sola llamada** al comportamiento probado. Dos llamadas son dos acciones, y dos acciones son casi siempre dos tests: el nombre del test solo puede describir una.

Hay dos casos habituales con apariencia de dos Act:

- **La segunda llamada es preparación.** Para probar que un pedido pagado no se cancela hace falta pagarlo antes; `Pagar()` es Arrange, y el Act es `Cancelar()`. La distinción es qué comportamiento se está probando.
- **La segunda llamada es otro comportamiento.** En el test `Pedido_funciona` de arriba, `Confirmar()`, `AplicarCupon()` y `Cancelar()` son tres comportamientos. El refactor es partirlo, como en el contraste ✅. Lo que antes era el Arrange compartido pasa a un constructor, a una función auxiliar o a un builder (siguiente sección).

Una excepción legítima: un test de flujo completo (confirmar, pagar, enviar) donde el recorrido entero es el escenario. Es el caso de un test de integración o de extremo a extremo, no de unidad.

## Una razón para fallar: varias aserciones

«Una sola aserción por test» es una regla demasiado estricta. El criterio útil es **una comprobación lógica**: varias aserciones sobre el mismo resultado forman un solo Assert.

```csharp
// ✅ Una comprobación lógica: la línea resultante
var linea = pedido.Lineas.Single();
Assert.Equal("Camiseta", linea.Producto.Nombre);
Assert.Equal(2, linea.Cantidad);
```

```csharp
// ❌ Dos razones para fallar: el estado y el total, que no tienen que ver
pedido.Confirmar();
Assert.Equal(EstadoPedido.Confirmado, pedido.Estado);
Assert.Equal(36m, pedido.Total);
```

La prueba práctica es preguntarse: ¿podría fallar una aserción sin que la otra tenga nada que decir? Si es así, son dos tests.

Cuando las aserciones sí describen el mismo resultado y se quiere ver **todos** los fallos en una pasada (la primera que falla corta el test), hay dos formas verificadas con el paquete instalado:

```csharp
// xUnit 2.9.3: Assert.Multiple existe
Assert.Multiple(
    () => Assert.Equal(EstadoPedido.Borrador, pedido.Estado),
    () => Assert.Equal(1, pedido.Lineas.Count),
    () => Assert.Equal(15m, pedido.Total));
```

```csharp
// Shouldly 4.3.0: ShouldSatisfyAllConditions
pedido.ShouldSatisfyAllConditions(
    () => pedido.Estado.ShouldBe(EstadoPedido.Borrador),
    () => pedido.Lineas.Count.ShouldBe(1),
    () => pedido.Total.ShouldBe(15m));
```

Con dos aserciones erróneas, `Assert.Multiple` agrupa los dos fallos en un solo mensaje:

```text
Assert.Multiple() Failure: Multiple failures were encountered
---- Assert.Equal() Failure: Values differ
Expected: Borrador
Actual:   Confirmado
---- Assert.Equal() Failure: Values differ
Expected: 15
Actual:   20
```

Shouldly lista los errores bajo `should satisfy all the conditions specified, but does not` (el ejemplo ejecutado tenía un solo error: `pedido.Total should be 15m but was 20m`). Para el paquete Shouldly, ver [Shouldly](Shouldly.md); para xUnit, [xUnit](xUnit.md).

## Preparar el escenario sin repetirlo

### Builders y *object mothers*

El Arrange largo oculta la intención: de las diez líneas de preparación, solo una explica por qué el test existe.

```csharp
// ❌ ¿Qué importa aquí? Hay que leer todo para descubrirlo: el cupón
var pedido = new Pedido(4711);
pedido.Agregar(new Producto(1, "Camiseta", 20m), 2);
pedido.Agregar(new Producto(2, "Gorra", 10m), 1);
pedido.AplicarCupon(10);
// ...

var total = pedido.Total;
```

Un **builder** (clase que construye el objeto con valores por defecto válidos y métodos para cambiar solo lo que importa al test) deja visible lo único relevante:

```csharp
public class PedidoBuilder
{
    private int _id = 4711;
    private readonly List<(Producto, int)> _lineas = [(new Producto(1, "Camiseta", 20m), 1)];
    private int? _cupon;
    private bool _confirmado;

    public PedidoBuilder SinLineas() { _lineas.Clear(); return this; }
    public PedidoBuilder ConLinea(decimal precio, int cantidad)
    { _lineas.Add((new Producto(99, "Otro", precio), cantidad)); return this; }
    public PedidoBuilder ConCupon(int porcentaje) { _cupon = porcentaje; return this; }
    public PedidoBuilder Confirmado() { _confirmado = true; return this; }

    public Pedido Construir()
    {
        var pedido = new Pedido(_id);
        foreach (var (producto, cantidad) in _lineas) pedido.Agregar(producto, cantidad);
        if (_cupon is { } cupon) pedido.AplicarCupon(cupon);
        if (_confirmado) pedido.Confirmar();
        return pedido;
    }
}
```

```csharp
// ✅ Se ve qué importa: el cupón del 10 % sobre 40 de líneas
var pedido = new PedidoBuilder().SinLineas().ConLinea(20m, 2).ConCupon(10).Construir();
```

Un pedido válido por defecto (`new PedidoBuilder().Construir()`) sirve para todos los tests que no dependen de su contenido. Un *object mother* es la variante más simple: métodos estáticos con nombre de escenario (`Pedidos.Confirmado()`, `Pedidos.SinLineas()`); basta mientras haya pocos escenarios y poca variación, y se queda corto en cuanto cada test necesita un detalle distinto.

Si el Arrange sigue largo con un builder, el problema suele estar en el diseño: la clase bajo prueba tiene demasiadas dependencias o hace demasiado.

### Datos mágicos y fixtures

Los valores que explican el resultado se nombran, no se dejan sueltos:

```csharp
const decimal PrecioCamiseta = 20m;
const int CuponDelDiezPorCiento = 10;
const decimal TotalConCupon = 36m;   // 2 camisetas * 20 - 10 %
```

Un `Assert.Equal(36m, total)` obliga a deducir de dónde sale el 36; con la constante o un comentario el test se lee sin cuentas. Pero no hay que nombrar todo: `4711` como id o `"Camiseta"` como nombre no influyen en el resultado y se quedan como están.

Lo que es caro de preparar (un servidor, una base de datos, una API en memoria) no va en el Arrange de cada test sino en una *fixture* compartida. Ver [Fixtures y ciclo de vida](Fixtures-y-ciclo-de-vida.md).

## El nombre del test es documentación

El nombre es lo primero que lee quien mira el informe del runner cuando algo falla. Tres convenciones, con lo que se vio en una ejecución con tres tests fallidos, cada uno con una convención distinta:

```text
Con error Nombres.Confirmar_sin_lineas_lanza_ReglaDeDominioException
Con error Nombres.Dado_pedido_sin_lineas_Cuando_se_confirma_Entonces_lanza_excepcion
Con error Un pedido sin líneas no se puede confirmar
```

| Convención | Ejemplo | Lectura en el informe | Cuándo conviene |
|---|---|---|---|
| `Metodo_Escenario_Resultado` | `Confirmar_sin_lineas_lanza_ReglaDeDominioException` | Sale el nombre de la clase y el del método tal cual | Tests de unidad centrados en un método; la más habitual en .NET |
| `Dado_Cuando_Entonces` | `Dado_pedido_sin_lineas_Cuando_se_confirma_Entonces_lanza_excepcion` | El nombre más largo de los tres | Equipos que ya hablan en términos de BDD |
| Frase con `[Fact(DisplayName = "...")]` | `Un pedido sin líneas no se puede confirmar` | Sale la frase sin el nombre de la clase (observado así) | Reglas de negocio que debe entender alguien que no programa |

Cualquiera sirve si el nombre dice el escenario y el resultado esperado, no el método. Un nombre como `Pedido_funciona` o `Test1` obliga a abrir el código. Con `[Theory]`, xUnit añade los argumentos al nombre (`Total_con_cupon(cupon: 50, esperado: 25)`).

## Excepciones, asincronía y dobles

### Excepciones

Cuando el resultado es una excepción, la acción y la comprobación son inseparables: `Assert.Throws` envuelve el Act. El patrón se mantiene si el Arrange queda **fuera** de la lambda y la lambda contiene una sola llamada:

```csharp
// ✅ Arrange fuera; el Act está dentro de Throws y es una sola llamada
[Fact]
public void Confirmar_sin_lineas_lanza_ReglaDeDominioException()
{
    var pedido = new PedidoBuilder().SinLineas().Construir();

    var ex = Assert.Throws<ReglaDeDominioException>(() => pedido.Confirmar());

    Assert.Equal("Un pedido sin líneas no se puede confirmar.", ex.Message);
}
```

La forma que parece AAA y no lo es:

```csharp
// ❌ Arrange y Act dentro de la lambda: pasa por la razón equivocada
Assert.Throws<ReglaDeDominioException>(() =>
{
    var pedido = new Pedido(4711);
    pedido.Agregar(new Producto(1, "Camiseta", 20m), 1);
    pedido.AplicarCupon(60);   // lanza aquí: cupón por encima del 50 %
    pedido.Confirmar();        // nunca se ejecuta
});
```

Este test pasa (se ejecutó en verde) pero la excepción sale de `AplicarCupon(60)`, una regla distinta, y `Confirmar()` no llega a probarse. Cualquier excepción del mismo tipo en cualquier punto de la preparación lo mantiene en verde.

### Tests asíncronos y dobles de prueba

Con `async`, el Act lleva `await` y el patrón no cambia. Un **doble de prueba** (objeto que sustituye a una dependencia real: un *fake* con comportamiento simple, un *mock* que registra llamadas) se configura en el Arrange, y verificar sus llamadas es parte del Assert:

```csharp
[Fact]
public async Task Confirma_guarda_y_notifica_el_pedido()
{
    // Arrange: fakes escritos a mano y un pedido válido ya guardado
    var repositorio = new RepositorioFake();
    repositorio.Pedidos[4711] = new PedidoBuilder().Construir();
    var notificador = new NotificadorFake(repositorio.Llamadas);
    var casoDeUso = new ConfirmarPedido(repositorio, notificador);

    // Act
    await casoDeUso.EjecutarAsync(4711, CancellationToken.None);

    // Assert: el estado guardado y la notificación enviada
    Assert.Equal(EstadoPedido.Confirmado, repositorio.Pedidos[4711].Estado);
    Assert.Equal([4711], notificador.Notificados);
}
```

El test pasa. Con una librería de dobles el Arrange configura el doble y el Assert comprueba las llamadas recibidas; ver [NSubstitute](NSubstitute.md).

### Tests parametrizados

En un `[Theory]` el Arrange viene de los datos de la prueba: cada fila es un escenario y el cuerpo sigue siendo AAA.

```csharp
[Theory]
[InlineData(10, 36)]
[InlineData(50, 20)]
[InlineData(0, 40)]
public void Total_con_cupon(int cupon, decimal esperado)
{
    var pedido = new PedidoBuilder().SinLineas().ConLinea(20m, 2).ConCupon(cupon).Construir();

    var total = pedido.Total;

    Assert.Equal(esperado, total);
}
```

Con las tres filas correctas pasan las tres. Con una fila errónea el informe nombra la fila, no solo el método: `Varios.Total_con_cupon(cupon: 50, esperado: 25)` seguida de `Expected: 25 / Actual: 20`.

## Tests de integración

En un test de integración (varias capas reales, una base de datos o la API en memoria) el Arrange es caro y puede ser largo: crear datos, arrancar el host. Se mueve a una *fixture* o a un constructor y el cuerpo del test conserva solo el Arrange específico del caso. El Act sigue siendo una sola llamada (una petición HTTP, un caso de uso) y el Assert comprueba lo observable: la respuesta, la fila escrita. Ver [Tipos de tests](Tipos-de-tests.md) y [Fixtures y ciclo de vida](Fixtures-y-ciclo-de-vida.md).

## Señales de mal AAA

| Síntoma en el test | Qué cambiar |
|---|---|
| `if`, `for` o `switch` en el cuerpo | El test calcula en lugar de comprobar: sustituir por datos fijos o por un `[Theory]` |
| El Assert repite la lógica de producción (`Assert.Equal(precio * cantidad * 0.9m, total)`) | Usar un valor literal calculado a mano; si no, el test comparte el error del código |
| El test es más largo que el código que prueba | El Arrange arrastra demasiado: builder, o revisar el diseño |
| No hay Act (solo construcción y aserciones sobre el resultado) | Falta la acción o el test comprueba el constructor; nombrarlo como tal |
| Varios bloques Act / Assert alternados | Partir en un test por acción |
| El Arrange no se relaciona con el Assert | Quitar lo que no influye en el resultado |

## Cuándo no forzar AAA

- **Tests de una línea**, como `Assert.Equal(EstadoPedido.Borrador, new Pedido(4711).Estado)`: tres bloques serían más texto que prueba.
- **Tests de propiedades** (*property-based*), donde el framework genera los casos y el Arrange es el generador.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| El test falla y el mensaje no dice qué se estaba probando | Varias acciones en un test; partirlo |
| Un fallo posterior no aparece hasta arreglar el primero | La primera aserción que falla corta el test; separar tests o agrupar con `Assert.Multiple` |
| Un `Assert` dentro de un `foreach` pasa con una lista vacía | El bucle no itera y no se comprueba nada; fijar el número de elementos esperados antes del bucle |
| Test en verde que nunca ejercita el Act | Excepción esperada lanzada por la preparación (ver la forma ❌ de `Assert.Throws`) |
| Comentario `// Arrange` sobre código que ya ejecuta la acción | El comentario miente; mover la línea o quitar el comentario |
| Test que se rompe al refactorizar sin cambiar el comportamiento | Prueba la implementación, no el contrato |

El último síntoma se demuestra. Un test que invoca por reflexión el método privado `ExigirLineas` de `Pedido`:

```csharp
var metodo = typeof(Pedido).GetMethod("ExigirLineas", BindingFlags.NonPublic | BindingFlags.Instance);
var ex = Assert.Throws<TargetInvocationException>(() => metodo!.Invoke(pedido, null));
Assert.IsType<ReglaDeDominioException>(ex.InnerException);
```

Pasa mientras el método se llame así. Al renombrarlo a `ComprobarLineas` (el comportamiento de `Confirmar()` no cambia) el test falla:

```text
Con error FragilTests.Acoplado_a_la_implementacion [5 ms]
   Assert.Throws() Failure: Exception type was not an exact match
Expected: typeof(System.Reflection.TargetInvocationException)
Actual:   typeof(System.NullReferenceException)
```

Con el contrato público (`Assert.Throws<ReglaDeDominioException>(() => pedido.Confirmar())`) el mismo refactor no afecta al test. Lo mismo ocurre con un doble que verifica el orden de las llamadas internas cuando ese orden no es un requisito.

## Buenas prácticas avanzadas

- **Escribe el Assert primero.** Preguntarse «si funcionara, ¿cómo lo notaría?» define el resultado antes de la preparación, y deja fuera del Arrange todo lo que el Assert no necesita. Es la técnica que describe el artículo de Bill Wake.
- **Un builder con valores por defecto válidos, y que cada test cambie solo lo que le importa.** El test que dice `.ConCupon(10)` está diciendo que el cupón es lo relevante; si el builder obliga a especificar todo, esa señal se pierde.
- **Comenta el porqué del Arrange, nunca el qué.** `// Arrange: cupón en el límite permitido` aporta lo que el código no dice; `// Arrange: creamos el pedido` es ruido.
- **Pon `Assert.Throws` sobre una sola llamada y deja el Arrange fuera de la lambda.** Es la única forma de saber qué línea lanzó la excepción.
- **Comprueba el contrato observable, no la implementación.** Estado resultante, valor devuelto, mensaje enviado: un test acoplado a métodos privados o al orden de llamadas internas se rompe con cada refactor y acaba ignorado.
- **Un Arrange de veinte líneas es una señal sobre el diseño.** Muchas dependencias que construir indican una clase que hace demasiado; el builder lo alivia, no lo arregla.

## Documentación oficial

- [Prácticas recomendadas de pruebas unitarias (Microsoft Learn)](https://learn.microsoft.com/dotnet/core/testing/unit-testing-best-practices) — las secciones «Arrange your tests», «Avoid multiple Act tasks», «Avoid magic strings» y «Avoid coding logic in unit tests» (títulos leídos el 2026-11-09). Para contrastar las reglas de este patrón con las de la documentación de .NET.
- [3A: Arrange, Act, Assert (Bill Wake, xp123.com)](https://xp123.com/3a-arrange-act-assert/) — artículo de 2011 que describe el patrón, su variante «Assert First» y un FAQ sobre cuándo se admite una secuencia de acciones. Para la motivación original (tests «como una frase interminable»).

---

*En resumen: cada test cuenta una historia en tres actos con una sola acción en el segundo; si el final no cuadra, el nombre del test ya dice qué acto se torció.*
