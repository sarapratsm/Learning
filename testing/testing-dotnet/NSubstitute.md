# NSubstitute

## ¿Qué es?

NSubstitute es una librería de *mocking* para .NET: crea en una línea implementaciones falsas de interfaces (y de clases con miembros virtuales) para que un test unitario aísle la clase bajo prueba de sus dependencias reales, decida qué devuelven esas dependencias y compruebe después qué llamadas recibieron.

## ¿Por qué existe?

Para probar un caso de uso que cobra con una pasarela de pago, guarda en una base de datos y avisa por correo, el test no puede llamar a la pasarela real, ni cobrar de verdad, ni depender de que el servidor de correo responda. Sin librería, la salida es escribir a mano una clase falsa por cada dependencia, con listas y contadores para saber qué se llamó, y repetir ese trabajo para cada escenario distinto (pasarela que acepta, que rechaza, que no responde).

NSubstitute genera esas clases falsas sobre la marcha con `Substitute.For<T>()`, y se configura y se verifica con métodos de extensión que se leen casi como una frase: `pasarela.Cobrar(...).Returns(true)`, `notificador.Received(1).PedidoConfirmado(...)`.

> Si conoces Vitest o Jest, `Substitute.For<T>()` es su `vi.fn()` / `jest.fn()`, pero tipado: el sustituto cumple la interfaz completa y el compilador vigila los nombres y los tipos.

## ¿Cuándo y para qué se usa?

En **tests unitarios**, para las dependencias que no son el objetivo del test. En la tienda online, el caso de uso `ConfirmarPedido` (confirmar el pedido #4711: leerlo, cobrar, guardarlo como pagado, avisar al cliente) se prueba de verdad; el repositorio, la pasarela de pago, el notificador y el reloj son sustitutos. Encaja especialmente bien con arquitecturas de puertos y adaptadores, donde esas dependencias ya son interfaces definidas por la aplicación (ver [Casos de uso](../../arquitectura-de-software/clean-architecture/Casos-de-Uso.md)).

No se usa en tests de integración ni de API, donde el punto es precisamente usar las piezas reales (ver [Tipos de tests](Tipos-de-tests.md)); y tampoco para sustituir el dominio: los `Pedido` y `Cupon` se construyen de verdad.

## Estado del proyecto y versiones

Comprobado el 2026-11-10 con el SDK de .NET 10.0.401:

| Paquete | Última versión en NuGet | Notas |
|---|---|---|
| `NSubstitute` | 6.2.0 (publicada el 2026-08-11) | Depende de `Castle.Core` 5.1.1, que genera los proxies en tiempo de ejecución |
| `NSubstitute.Analyzers.CSharp` | 1.0.17 | Analizador de Roslyn: avisa en compilación de usos incorrectos (códigos `NS1000`, `NS4000`...) |

La licencia es BSD-3-Clause (declarada en el paquete NuGet) y el repositorio `nsubstitute/NSubstitute` no está archivado: su último *push* es del 2026-10-26.

```bash
dotnet add tests/Tienda.Tests package NSubstitute
dotnet add tests/Tienda.Tests package NSubstitute.Analyzers.CSharp
```

El segundo paquete se añade con `PrivateAssets=all` (el comando lo hace solo): se aplica en compilación y no viaja a quien referencie el proyecto de pruebas. Es recomendable desde el primer día, porque varios de los errores de más abajo los detecta antes de ejecutar nada.

## Vocabulario: dobles de prueba

Un **doble de prueba** es cualquier objeto que ocupa el lugar de una dependencia real durante un test. El vocabulario habitual (Gerard Meszaros, popularizado por Martin Fowler) distingue cinco tipos:

| Doble | Qué hace | Ejemplo en la tienda | Se comprueba |
|---|---|---|---|
| **Dummy** | Rellena un parámetro que nunca se usa | Un `INotificador` que se pasa al constructor en un test donde no se llega a avisar | Nada |
| **Stub** | Devuelve respuestas fijas a las preguntas del código bajo prueba | `IReloj` que siempre dice que son las 9:30; repositorio que devuelve el pedido #4711 | El resultado del código bajo prueba |
| **Spy** | Funciona como stub y además registra cómo se le llamó | Pasarela que devuelve `true` y apunta cada cobro recibido | Las llamadas, después de ejecutar |
| **Mock** | Se programa con las llamadas que *debe* recibir y falla si no ocurren | Notificador que espera exactamente un `PedidoConfirmado(4711, ...)` | Las llamadas |
| **Fake** | Implementación real pero simplificada, con lógica propia | Repositorio en memoria con un `Dictionary` | El estado final |

La diferencia práctica es **qué se comprueba**: con un stub se comprueba el resultado; con un spy o un mock, las interacciones; con un fake, el estado que queda. NSubstitute no distingue entre stub, spy y mock: el mismo `Substitute.For<T>()` sirve para los tres, y es el test el que decide si solo lo configura (`Returns`) o también verifica (`Received`). Los *fakes* con lógica se escriben a mano (ver «Mock o fake» más abajo).

## Un primer test de principio a fin

El caso de uso `ConfirmarPedido` de los ejemplos es una versión reducida, con las interfaces (puertos) que necesita; en el proyecto de pruebas ejecutado, dominio y aplicación están juntos en un solo proyecto de clases. Los puertos son los de [Casos de uso](../../arquitectura-de-software/clean-architecture/Casos-de-Uso.md), sin la unidad de trabajo y con dos añadidos: un `IReloj` y la fecha en el aviso.

```csharp
namespace Tienda.Aplicacion;

public interface IRepositorioPedidos
{
    Task<Pedido?> ObtenerPorId(int id);
    Task Guardar(Pedido pedido);
}

public interface IPasarelaPago
{
    Task<bool> Cobrar(decimal importe, string tokenTarjeta, string claveIdempotencia);
}

public interface INotificador
{
    Task PedidoConfirmado(int pedidoId, DateTimeOffset confirmadoEl);
}

public interface IReloj
{
    DateTimeOffset Ahora { get; }
}

public record ConfirmarPedidoComando(int PedidoId, string TokenTarjeta);

public enum ConfirmarPedidoResultado { Confirmado, YaConfirmado, NoEncontrado, NoConfirmable, PagoRechazado }

public class ConfirmarPedido(
    IRepositorioPedidos pedidos,
    IPasarelaPago pasarela,
    INotificador notificador,
    IReloj reloj)
{
    public async Task<ConfirmarPedidoResultado> Ejecutar(ConfirmarPedidoComando comando)
    {
        var pedido = await pedidos.ObtenerPorId(comando.PedidoId);
        if (pedido is null) return ConfirmarPedidoResultado.NoEncontrado;
        if (pedido.Estado == EstadoPedido.Pagado) return ConfirmarPedidoResultado.YaConfirmado;
        if (!pedido.PuedeConfirmarse) return ConfirmarPedidoResultado.NoConfirmable;

        var cobrado = await pasarela.Cobrar(pedido.Total, comando.TokenTarjeta, $"pedido-{pedido.Id}");
        if (!cobrado) return ConfirmarPedidoResultado.PagoRechazado;

        pedido.MarcarPagado();
        await pedidos.Guardar(pedido);
        await notificador.PedidoConfirmado(pedido.Id, reloj.Ahora);
        return ConfirmarPedidoResultado.Confirmado;
    }
}
```

`Pedido` es la entidad de ese mismo capítulo: `Id`, `Lineas`, `Estado` (`Pendiente`, `Pagado`, `Cancelado`), `Total`, `PuedeConfirmarse` y `MarcarPagado()`. El test tiene tres movimientos: crear los sustitutos, configurar lo que devuelven y, tras ejecutar, verificar los efectos que importan.

```csharp
using NSubstitute;
using Tienda.Aplicacion;

namespace Tienda.Tests;

public class ConfirmarPedidoTests
{
    private readonly IRepositorioPedidos _pedidos = Substitute.For<IRepositorioPedidos>();
    private readonly IPasarelaPago _pasarela = Substitute.For<IPasarelaPago>();
    private readonly INotificador _notificador = Substitute.For<INotificador>();
    private readonly IReloj _reloj = Substitute.For<IReloj>();
    private readonly ConfirmarPedido _caso;

    public ConfirmarPedidoTests() => _caso = new(_pedidos, _pasarela, _notificador, _reloj);

    private static Pedido PedidoConLineas()
    {
        var pedido = new Pedido { Id = 4711 };
        pedido.Lineas.Add(new LineaPedido { ProductoId = 10, Precio = 25m, Cantidad = 2 });
        return pedido;
    }

    [Fact]
    public async Task Confirma_cobra_guarda_y_avisa()
    {
        var pedido = PedidoConLineas();
        var instante = new DateTimeOffset(2026, 11, 10, 9, 30, 0, TimeSpan.Zero);
        _pedidos.ObtenerPorId(4711).Returns(pedido);
        _pasarela.Cobrar(50m, "tok_visa", "pedido-4711").Returns(true);
        _reloj.Ahora.Returns(instante);

        var resultado = await _caso.Ejecutar(new(4711, "tok_visa"));

        Assert.Equal(ConfirmarPedidoResultado.Confirmado, resultado);
        Assert.Equal(EstadoPedido.Pagado, pedido.Estado);
        await _pedidos.Received(1).Guardar(pedido);
        await _notificador.Received(1).PedidoConfirmado(4711, instante);
    }
}
```

`Substitute.For<T>()` devuelve un objeto que implementa `T`. xUnit crea una instancia nueva de la clase por cada test (ver [xUnit](xUnit.md)), así que los sustitutos de los campos son nuevos en cada test y no arrastran llamadas del anterior. Las tres líneas `Returns` son el *Arrange* de [Arrange-Act-Assert](Arrange-Act-Assert.md); las dos `Received` son el *Assert* sobre los dos efectos hacia fuera. `pedido.Estado` se comprueba en el objeto real, porque `Pedido` no es un doble.

## Configurar respuestas

### Valores por defecto: un sustituto sin configurar no falla, devuelve «vacío»

Un miembro sin configurar devuelve un valor por defecto en lugar de lanzar. Lo que se observó con los sustitutos de arriba:

| Miembro sin configurar | Devuelve |
|---|---|
| `Task<Pedido?> ObtenerPorId(int)` | Una `Task` ya completada con `null` |
| `Task<bool> Cobrar(...)` | Una `Task` ya completada con `false` |
| `int Stock(string)` | `0` |
| Propiedad `string Nombre` | Cadena vacía (no `null`) |

Un `await` sobre un método sin configurar no se queda colgado ni lanza. Lo cómodo tiene su cara: un test puede pasar por el camino equivocado sin avisar. Este test, sin configurar la pasarela, pasa:

```csharp
_pedidos.ObtenerPorId(4711).Returns(PedidoConLineas());

var resultado = await _caso.Ejecutar(new(4711, "tok_visa"));

Assert.Equal(ConfirmarPedidoResultado.PagoRechazado, resultado);   // la pasarela devolvió false por defecto
```

### `Returns`

`Returns` se encadena sobre la llamada que se quiere configurar y fija qué devuelve. Con argumentos literales, solo responde a esos argumentos:

```csharp
_pedidos.ObtenerPorId(4711).Returns(pedido);
_pasarela.Cobrar(50m, "tok_visa", "pedido-4711").Returns(true);
_reloj.Ahora.Returns(instante);              // las propiedades se configuran igual
```

Con el repositorio configurado solo para el pedido #4711, `ObtenerPorId(999)` devuelve el valor por defecto (`null`). Si se configura la misma llamada dos veces, **gana la última**.

### Valor en función de los argumentos: `Returns` con lambda

Cuando la respuesta depende de lo que se pida, `Returns` acepta una función que recibe un `CallInfo`, con acceso a los argumentos por tipo (`ci.Arg<string>()`) o por posición (`ci.ArgAt<decimal>(0)`):

```csharp
_pasarela.Cobrar(Arg.Any<decimal>(), Arg.Any<string>(), Arg.Any<string>())
         .Returns(ci => ci.ArgAt<decimal>(0) <= 100m);   // rechaza los cobros de más de 100

alm.Stock(Arg.Any<string>()).Returns(ci => ci.Arg<string>() == "CAM-001" ? 5 : 0);
```

Con esa pasarela, un cobro de 50 devuelve `true` y uno de 500 devuelve `false`. Con el almacén, `Stock("CAM-001")` devuelve 5 y `Stock("OTRO")` devuelve 0.

### Una secuencia de valores

Varios valores en un solo `Returns` se devuelven uno por llamada, y el último se repite:

```csharp
_pasarela.Cobrar(Arg.Any<decimal>(), Arg.Any<string>(), Arg.Any<string>()).Returns(true, false, true);
// cuatro llamadas seguidas devuelven: True False True True
```

### `ReturnsForAnyArgs`

`ReturnsForAnyArgs` configura la respuesta para cualquier valor de los argumentos, sin escribir un `Arg.Any` por parámetro. Los valores que se pasan en la llamada de configuración se ignoran:

```csharp
_pasarela.Cobrar(default, default!, default!).ReturnsForAnyArgs(false);
```

Es la forma corta de `Cobrar(Arg.Any<decimal>(), Arg.Any<string>(), Arg.Any<string>()).Returns(false)`. Existe el equivalente `DidNotReceiveWithAnyArgs()` para verificar, que se usa más abajo.

### Métodos asíncronos

En un método que devuelve `Task<T>`, `Returns` acepta el valor `T` directamente, sin envolverlo:

```csharp
_pasarela.Cobrar(50m, "tok_visa", "pedido-4711").Returns(true);                   // ✅ lo habitual
_pasarela.Cobrar(50m, "tok_visa", "pedido-4711").Returns(Task.FromResult(true));  // ✅ equivale al anterior
```

NSubstitute no tiene `ReturnsAsync` (es de Moq): llamarlo da `error CS1061: 'Task<bool>' does not contain a definition for 'ReturnsAsync'`. Para devolver `null` en un `Task<Pedido?>`, `Returns(Task.FromResult<Pedido?>(null))`; y como un sustituto sin configurar ya devuelve una `Task` con `null`, normalmente no hace falta configurar nada.

## Verificar llamadas

### `Received`, `DidNotReceive` y `Received(n)`

Tras ejecutar, `Received` comprueba que la llamada ocurrió; `Received(n)`, que ocurrió exactamente `n` veces; `DidNotReceive`, que no ocurrió:

```csharp
await _pedidos.Received(1).Guardar(pedido);                                  // exactamente una vez
await _notificador.Received().PedidoConfirmado(4711, Arg.Any<DateTimeOffset>()); // al menos una
await _pedidos.DidNotReceive().Guardar(Arg.Any<Pedido>());                   // ninguna
await _notificador.DidNotReceiveWithAnyArgs().PedidoConfirmado(default, default); // ninguna, con cualquier argumento
```

La verificación se ejecuta en el momento de la llamada, así que no hace falta ningún `Verify()` final. Si falla, lanza `ReceivedCallsException` con un mensaje que dice qué se esperaba y qué llegó de verdad. Los mensajes reales para un repositorio que recibió dos `Guardar` y una pasarela que recibió un `Cobrar(50, "tok_visa", "pedido-4711")`:

```text
Expected to receive exactly 3 calls matching:
	Guardar(any Pedido)
Actually received 2 matching calls:
	Guardar(Pedido)
	Guardar(Pedido)
```

```text
Expected to receive no calls matching:
	Guardar(any Pedido)
Actually received 2 matching calls:
	Guardar(Pedido)
	Guardar(Pedido)
```

```text
Expected to receive exactly 1 call matching:
	Cobrar(60, "tok_visa", "pedido-4711")
Actually received no matching calls.
Received 1 non-matching call (non-matching arguments indicated with '*' characters):
	Cobrar(*50*, "tok_visa", "pedido-4711")
```

El tercero es el más útil: marca con asteriscos el argumento que no coincidió.

### El orden: `Received.InOrder`

Cuando el orden de las llamadas **es** el contrato (cobrar antes de avisar), `Received.InOrder` lo comprueba entre sustitutos distintos:

```csharp
Received.InOrder(() =>
{
    _pasarela.Cobrar(50m, "tok_visa", "pedido-4711");
    _notificador.PedidoConfirmado(4711, Arg.Any<DateTimeOffset>());
});
```

Si el código avisara antes de cobrar, el fallo lista ambas secuencias:

```text
NSubstitute.Exceptions.CallSequenceNotFoundException
Expected to receive these calls in order:

    INotificador.PedidoConfirmado(1, 01/01/0001 0:00:00 +00:00)
    IPasarelaPago.Cobrar(1, "a", "b")

Actually received matching calls in this order:

    IPasarelaPago.Cobrar(1, "a", "b")
    INotificador.PedidoConfirmado(1, 01/01/0001 0:00:00 +00:00)

*** Note: calls to property getters are not considered part of the query. ***
```

(Mensaje real de una prueba con los argumentos `1`, `"a"` y `"b"`.) Las lecturas de propiedades, como `reloj.Ahora`, no cuentan para el orden.

## Argument matchers

Un **argument matcher** es una condición sobre un argumento en lugar de un valor literal. Se usan en la misma posición del argumento, tanto al configurar (`Returns`) como al verificar (`Received`):

| Matcher | Casa con | Ejemplo |
|---|---|---|
| Literal | El valor igual (`Equals`) | `Cobrar(50m, "tok_visa", ...)` |
| `Arg.Any<T>()` | Cualquier valor de tipo `T` | `Guardar(Arg.Any<Pedido>())` |
| `Arg.Is<T>(valor)` | El valor igual | `Arg.Is("tok_visa")` |
| `Arg.Is<T>(predicado)` | Los valores para los que el predicado da `true` | `Guardar(Arg.Is<Pedido>(p => p.Id == 4711))` |
| `Arg.Do<T>(accion)` | Cualquier valor, y ejecuta la acción con él | `Cobrar(Arg.Any<decimal>(), Arg.Any<string>(), Arg.Do<string>(c => clave = c))` |

`Arg.Is` con predicado es la herramienta para objetos que no se pueden construir idénticos al de dentro del código bajo prueba. `Arg.Do` captura el argumento para comprobarlo con calma en el *Assert*:

```csharp
[Fact]
public async Task La_clave_de_idempotencia_se_deriva_del_pedido()
{
    string? clave = null;
    _pedidos.ObtenerPorId(4711).Returns(PedidoConLineas());
    _pasarela.Cobrar(Arg.Any<decimal>(), Arg.Any<string>(), Arg.Do<string>(c => clave = c)).Returns(true);

    await _caso.Ejecutar(new(4711, "tok_visa"));

    Assert.Equal("pedido-4711", clave);
}
```

`Arg.Do` no captura al configurar sino **cada vez que el sustituto recibe la llamada**: en una prueba, `capturado` seguía en `null` justo después de configurar y valía 4711 tras la llamada.

Se pueden mezclar literales y matchers en una misma llamada (`Cobrar(50m, Arg.Any<string>(), "pedido-4711")`), con una restricción que se explica en «Errores frecuentes».

`Arg.Compat` (`Arg.Compat.Any<T>()`, `Arg.Compat.Is<T>(...)`) existe para usar matchers dentro de árboles de expresión (`Expression<...>`), donde `Arg.Any<T>()` no compila. Está marcado como obsoleto en 6.2.0 (`warning CS0618: 'Arg.Compat' is obsolete: 'This api is deprecated and will be removed in future versions of product.'`): evítalo en código nuevo.

## Excepciones y callbacks

### Simular un fallo de la dependencia

`Throws` configura que la llamada lance una excepción; `ThrowsAsync` es la versión para métodos que devuelven `Task` o `Task<T>`, y la excepción sale al hacer `await`, no al llamar. Ambos vienen del espacio de nombres `NSubstitute.ExceptionExtensions`:

```csharp
using NSubstitute.ExceptionExtensions;

[Fact]
public async Task Pasarela_caida_propaga_la_excepcion_y_no_guarda()
{
    _pedidos.ObtenerPorId(4711).Returns(PedidoConLineas());
    _pasarela.Cobrar(Arg.Any<decimal>(), Arg.Any<string>(), Arg.Any<string>())
             .ThrowsAsync(new TimeoutException("La pasarela no responde"));

    await Assert.ThrowsAsync<TimeoutException>(() => _caso.Ejecutar(new(4711, "tok_visa")));

    await _pedidos.DidNotReceive().Guardar(Arg.Any<Pedido>());
}
```

`ThrowsAsync` devuelve una `Task` ya fallida (`IsFaulted` es `true` al llamar, sin excepción): el `await` lanza `TimeoutException`. Con un miembro síncrono (`int Stock(string)`), `Throws(new InvalidOperationException("sin conexion"))` lanza al llamar. Con una lambda, `Returns<bool>(x => throw new TimeoutException("al llamar"))` sobre un método que devuelve `Task<bool>` lanza **de forma síncrona al llamar**, sin llegar a devolver una tarea; para simular un fallo que aparezca al `await`, usa `ThrowsAsync`.

### Ejecutar código cuando se llama: `When ... Do`

`When(...).Do(...)` registra una acción que se ejecuta cuando se recibe una llamada, sea cual sea su valor de retorno. Sirve para métodos que no devuelven nada que configurar, o para anotar datos:

```csharp
var avisos = new List<int>();
_notificador
    .When(n => n.PedidoConfirmado(Arg.Any<int>(), Arg.Any<DateTimeOffset>()))
    .Do(ci => avisos.Add(ci.Arg<int>()));

await _notificador.PedidoConfirmado(4711, default);   // avisos == [4711]
```

Con `Do(ci => throw ...)` se hace fallar un método `void`, para el que `Throws` no existe. Es el último recurso: antes de usar `When..Do` con estado compartido, valora si un *fake* hecho a mano expresa lo mismo con menos ruido.

## Propiedades y eventos

Una propiedad de lectura y escritura de un sustituto **recuerda** lo que se le asigna, como una propiedad normal; `Returns` fija un valor y una asignación posterior lo vuelve a sobrescribir:

```csharp
alm.Nombre = "Central";
var a = alm.Nombre;             // "Central"
alm.Nombre.Returns("Fijo");
alm.Nombre = "Otro";
var b = alm.Nombre;             // "Otro": la asignación posterior gana
```

Una propiedad de solo lectura (`IReloj.Ahora`) se configura con `Returns`, como en el primer ejemplo.

Para los eventos, `Raise.Event` los dispara; se suscribe el código bajo prueba (o el test) y luego se emite el evento desde el sustituto:

```csharp
public interface IAlmacen { event EventHandler<int> StockBajo; /* ... */ }

int bajo = -1;
alm.StockBajo += (sender, unidades) => bajo = unidades;

alm.StockBajo += Raise.Event<EventHandler<int>>(alm, 3);   // bajo == 3
```

## Sustituir clases, y sus límites

`Substitute.For<T>()` también acepta clases, pero **solo puede interceptar miembros `virtual` o `abstract`** (por debajo, Castle.Core genera una subclase). Lo que no es virtual se ejecuta de verdad, y eso produce sorpresas:

```csharp
public class CalculadoraEnvio
{
    public virtual decimal Coste(decimal peso) => peso * 2m;
    public decimal CosteConIva(decimal peso) => Coste(peso) * 1.21m;   // no virtual
}

var c = Substitute.For<CalculadoraEnvio>();
c.Coste(10m);          // 0   (virtual: interceptado, valor por defecto)
c.CosteConIva(10m);    // 0,00 (no virtual: se ejecuta el código real, que llama al Coste interceptado)
c.Coste(10m).Returns(100m);
c.CosteConIva(10m);    // 121,00
```

`Substitute.ForPartsOf<T>()` crea un sustituto *parcial*: los miembros virtuales sin configurar ejecutan el código real, y los configurados se reemplazan. Con `ForPartsOf<CalculadoraEnvio>()`, `Coste(10m)` devuelve 20 y, tras `Returns(1m)`, devuelve 1.

El límite peligroso es intentar configurar un miembro no virtual. NSubstitute no puede interceptarlo, así que ejecuta el código real; el `Returns` se aplica entonces **a la última llamada que sí interceptó**, y falla en silencio:

```csharp
c.CosteConIva(10m).Returns(5m);   // warning NS1000: Member CosteConIva can not be intercepted.
// c.Coste(10m) devuelve ahora 5 y c.CosteConIva(10m) devuelve 6,05: se reconfiguró el miembro equivocado
```

Si necesitas sustituir una clase, el diseño más sólido es una interfaz en la costura (`ICalculadoraEnvio`) y la clase como implementación. Un tipo `sealed` no se puede sustituir: `Substitute.For<Cerrada>()` lanza `TypeLoadException: Could not load type 'Castle.Proxies.CerradaProxy' ... because the parent type is sealed.`

## El sobre-mocking: tests atados a la implementación

El **sobre-mocking** es verificar cada llamada interna con `Received` en lugar del resultado observable. Esos tests no se rompen cuando el comportamiento falla, sino cuando el código se reorganiza sin cambiar su comportamiento. Una refactorización plausible de `ConfirmarPedido`: volver a leer el pedido del repositorio después del cobro, para tener la versión más reciente (llamado `ConfirmarPedidoConRelectura` en las pruebas; el resto del método es idéntico). La conducta observable no cambia: sigue cobrando 50 una vez, guardando el pedido como pagado y avisando.

```csharp
// ❌ Verifica la coreografía interna: cada llamada, cuántas veces, con qué argumentos
[Fact]
public async Task Acoplado_a_la_implementacion()
{
    var pedido = PedidoConLineas();
    _pedidos.ObtenerPorId(4711).Returns(pedido);
    _pasarela.Cobrar(50m, "tok_visa", "pedido-4711").Returns(true);

    await _caso.Ejecutar(new(4711, "tok_visa"));

    await _pedidos.Received(1).ObtenerPorId(4711);
    await _pasarela.Received(1).Cobrar(50m, "tok_visa", "pedido-4711");
    await _pedidos.Received(1).Guardar(pedido);
    await _notificador.Received(1).PedidoConfirmado(4711, Arg.Any<DateTimeOffset>());
    _ = _reloj.Received(1).Ahora;
}
```

Con la relectura, ese test falla aunque nada se haya roto:

```text
NSubstitute.Exceptions.ReceivedCallsException : Expected to receive exactly 1 call matching:
	ObtenerPorId(4711)
Actually received 2 matching calls:
	ObtenerPorId(4711)
	ObtenerPorId(4711)
```

```csharp
// ✅ Comprueba lo que el negocio observa: el desenlace, el estado y los efectos hacia fuera
[Fact]
public async Task Centrado_en_el_resultado()
{
    var pedido = PedidoConLineas();
    _pedidos.ObtenerPorId(4711).Returns(pedido);
    _pasarela.Cobrar(50m, "tok_visa", "pedido-4711").Returns(true);

    var resultado = await _caso.Ejecutar(new(4711, "tok_visa"));

    Assert.Equal(ConfirmarPedidoResultado.Confirmado, resultado);
    Assert.Equal(EstadoPedido.Pagado, pedido.Estado);
    await _pedidos.Received().Guardar(pedido);
    await _notificador.Received(1).PedidoConfirmado(4711, Arg.Any<DateTimeOffset>());
}
```

El segundo test pasa antes y después de la relectura. Sigue verificando interacciones (`Guardar`, `PedidoConfirmado`), pero solo las que son el contrato: el efecto de guardar y el de avisar al cliente. La regla:

| Qué comprobar | ¿`Received`? |
|---|---|
| El valor que devuelve el código bajo prueba | No: `Assert` sobre el resultado |
| El estado de un objeto real (`pedido.Estado`) | No: `Assert` sobre el objeto |
| Un efecto saliente que nadie más observa (cobrar una vez, enviar un aviso, publicar un evento) | Sí, con los argumentos que importan |
| Que **no** se produjo un efecto peligroso (no cobrar un pedido inexistente) | Sí, `DidNotReceive` |
| Una llamada de consulta (`ObtenerPorId`) | No: es un detalle de cómo se obtiene el dato |
| Las llamadas a colaboradores intermedios, el número exacto de lecturas, el orden sin importancia | No |

## ¿Mock o fake? Cuándo cada doble

Un *fake* hecho a mano (un repositorio con un `Dictionary`) tiene lógica propia: lo que se guarda, luego se lee. Un sustituto de NSubstitute no tiene memoria: devuelve lo que se le configuró. Cuál usar depende de la dependencia y de qué se quiere comprobar:

| Situación | Doble recomendado | Por qué |
|---|---|---|
| Una consulta que alimenta al código con datos (`ObtenerPorId`, `IReloj.Ahora`) | **Stub** con `Returns` | Una línea; el test no se interesa por cómo se pidió |
| Un efecto saliente que es el contrato (cobrar, avisar, publicar un evento) | **Mock** (`Received`) | La interacción es lo único observable |
| Fallos de la dependencia (timeout, rechazo, excepción) | **Stub** con `Throws` / `ThrowsAsync` | Un fake con un modo «falla» acaba siendo código propio por mantener |
| Un repositorio que varios pasos del mismo test leen y escriben | **Fake** en memoria | Guardar y leer coherentes sin configurar cada llamada |
| La misma dependencia con el mismo comportamiento en muchos tests | **Fake** compartido | Una clase de diez líneas, en lugar de repetir `Returns` en cada test |
| Hay que comprobar el estado final de lo guardado | **Fake** | `repositorio.Datos[4711].Estado`, sin ensamblar el argumento de `Guardar` |
| El comportamiento real de la dependencia es lo que se quiere probar (SQL, mapeo, serialización) | Ninguno: **integración** | Un doble hace pasar el test aunque el SQL falle (ver [Testcontainers](Testcontainers.md)) |
| Un tipo concreto, `sealed` o con métodos no virtuales | Ninguno directo: introduce un puerto o usa el real | `Substitute.For` no lo intercepta (ver arriba) |

Un test con el repositorio *fake* y la pasarela como sustituto:

```csharp
public class RepositorioEnMemoria : IRepositorioPedidos
{
    public Dictionary<int, Pedido> Datos { get; } = [];
    public Task<Pedido?> ObtenerPorId(int id) => Task.FromResult(Datos.GetValueOrDefault(id));
    public Task Guardar(Pedido pedido) { Datos[pedido.Id] = pedido; return Task.CompletedTask; }
}

[Fact]
public async Task Confirma_y_deja_el_pedido_pagado_en_el_repositorio()
{
    var repositorio = new RepositorioEnMemoria();
    var pedido = new Pedido { Id = 4711 };
    pedido.Lineas.Add(new LineaPedido { ProductoId = 10, Precio = 25m, Cantidad = 2 });
    repositorio.Datos[4711] = pedido;

    var pasarela = Substitute.For<IPasarelaPago>();
    pasarela.Cobrar(Arg.Any<decimal>(), Arg.Any<string>(), Arg.Any<string>()).Returns(true);
    var caso = new ConfirmarPedido(repositorio, pasarela, Substitute.For<INotificador>(), Substitute.For<IReloj>());

    var resultado = await caso.Ejecutar(new(4711, "tok_visa"));

    Assert.Equal(ConfirmarPedidoResultado.Confirmado, resultado);
    Assert.Equal(EstadoPedido.Pagado, repositorio.Datos[4711].Estado);
}
```

Mezclar es lo normal: fakes para lo que tiene estado, sustitutos para lo que solo devuelve o solo recibe. Dos `Substitute.For` sin configuración (`INotificador`, `IReloj`) cumplen aquí el papel de *dummy*.

Para el tiempo, además de un `IReloj` propio, .NET trae la clase abstracta `TimeProvider`, y el paquete `Microsoft.Extensions.TimeProvider.Testing` ofrece `FakeTimeProvider`; este mecanismo no se probó aquí.

## Errores frecuentes

| Síntoma / mensaje | Causa | Qué hacer |
|---|---|---|
| `CouldNotSetReturnDueToNoLastCallException`: «Could not find a call to return from.» | Un `Returns` que recibe como argumento una llamada que a su vez configura otro sustituto (`repo.ObtenerPorId(4711).Returns(PedidoConPasarelaPreparada(pasarela))`, y la función hace `pasarela...Returns(true)`): el `Returns` interior consume la «última llamada» | Construir el valor antes (`var pedido = Preparar(...);`) y pasarlo ya listo, o usar `Returns(ci => Preparar(...))`. El analizador avisa: `NS4000: Returns() is set with a method that itself calls Returns` |
| `CouldNotSetReturnDueToTypeMismatchException`: «Can not return value of type Task`1 for IReloj.get_Ahora (expected type DateTimeOffset).» | El argumento de `Returns` hace otra llamada a un sustituto (aquí, leer `reloj.Ahora`) y esa pasa a ser la «última llamada», de otro tipo | Mismo remedio: no llamar a sustitutos dentro de los argumentos de `Returns` |
| `Returns` sin error pero el valor no aparece (`alm.Stock("A").Returns(otro.Stock("B"))` deja `alm.Stock("A")` en 0) | Misma causa cuando los tipos coinciden: el valor se aplica a la llamada del otro sustituto y no hay excepción | Leer el valor a una variable local antes de configurar. `NS4000` también avisa aquí (`Returns() is set with a method that itself calls Stock`) |
| `AmbiguousArgumentsException`: «Cannot determine argument specifications to use. Please use specifications for all arguments of the same type.» | Un matcher mezclado con un literal `null` del mismo tipo (aquí `Cobrar(50m, Arg.Any<string>(), null!)`: con dos `string` y un `null`, no se sabe a cuál va el matcher; con el literal `""` en su lugar no hubo excepción) | Usar un matcher en **todos** los argumentos del mismo tipo, como pide el propio mensaje |
| `UnexpectedArgumentMatcherException`: «Argument matchers (Arg.Is, Arg.Any) should only be used in place of member arguments. Do not use in a Returns() statement...» | `alm.Stock("X").Returns(Arg.Any<int>())`: un matcher como valor devuelto | `Returns` recibe un valor concreto, no un matcher |
| `RedundantArgumentMatcherException`: «Some argument specifications (e.g. Arg.Is, Arg.Any) were left over after the last call.» | Un matcher en una llamada que NSubstitute no gestiona (un objeto real, un miembro no virtual): `repo.Guardar(new Pedido { Id = Arg.Any<int>() })`. El matcher queda «huérfano» y puede romper el test siguiente | Usar matchers solo como argumentos directos de llamadas a un sustituto. El analizador avisa: `NS1004: Argument matcher used with a non-virtual member of a class` |
| `NotASubstituteException`: «NSubstitute extension methods like .Received() can only be called on objects created using Substitute.For<T>() and related methods.» | `Received()` o `Returns` sobre un objeto real (`new CalculadoraEnvio()`) | Crear el objeto con `Substitute.For<T>()` o `ForPartsOf<T>()` |
| `ReceivedCallsException`: «Expected to receive exactly 1 call matching...» | La llamada no ocurrió, ocurrió otro número de veces, o con otros argumentos | Leer las líneas `Received 1 non-matching call`: marcan con `*` el argumento que difiere |
| Un test pasa por el camino equivocado (`PagoRechazado` sin haber configurado la pasarela) | Un sustituto sin configurar devuelve `false` / `null` / `0` en lugar de fallar | Configurar explícitamente todo lo que el flujo bajo prueba toque, y asertar el resultado esperado |
| `c.CosteConIva(10m).Returns(5m)` «funciona» pero cambia otro miembro | Miembro no virtual de una clase | `warning NS1000: Member CosteConIva can not be intercepted...`: pasar a una interfaz o hacer el miembro `virtual` |

Las salidas citadas provienen de NSubstitute 6.2.0 y xUnit 2.9.3 con el SDK de .NET 10.0.401 en Windows, ejecutados el 2026-11-10 con `VSLANG=1033` y `DOTNET_CLI_UI_LANGUAGE=en`; los números decimales de las salidas siguen la cultura del sistema (coma decimal).

## Buenas prácticas avanzadas

- **Configura con `Arg.Any`, verifica con valores concretos.** Un stub permisivo (`Cobrar(Arg.Any<decimal>(), ...)`) no ata el test a un importe concreto cuando el importe no es lo que se prueba; el `Received` que sí importa (`Cobrar(50m, "tok_visa", "pedido-4711")`) lleva los argumentos exactos, y si falla, el mensaje marca con `*` cuál difiere.
- **Nunca llames a un sustituto dentro de los argumentos de `Returns`.** El valor se calcula antes de que `Returns` se ejecute y esa llamada interior se convierte en la «última llamada» a la que se aplica la configuración. Calcula el valor en una variable antes, o pasa una lambda (`Returns(ci => ...)`), que se evalúa más tarde. Con el analizador instalado, `NS4000` lo detecta en compilación cuando el método llama a `Returns` o a un miembro de otro sustituto; no avisó en la prueba que leía una propiedad (`reloj.Ahora`) dentro del argumento.
- **Eleva a error los avisos del analizador que apuntan a errores silenciosos.** `NS1000` (configurar un miembro no virtual) y `NS4000` dejan el test pasando en verde con una configuración equivocada: en el `.csproj` del proyecto de pruebas, `<WarningsAsErrors>$(WarningsAsErrors);NS1000;NS1004;NS4000</WarningsAsErrors>`.
- **Usa `Arg.Do` o `Arg.Is` según lo que falle.** Para comprobar una propiedad de un argumento complejo, capturarlo con `Arg.Do` y aplicar `Assert` sobre lo capturado da un mensaje de fallo específico; un `Received(...).Guardar(Arg.Is<Pedido>(p => ...))` solo dice «no hubo llamada que coincida». Recuerda que `Arg.Do` actúa en cada llamada, no al configurar.
- **No sustituyas lo que no es tuyo.** `HttpClient`, `DbContext` o `SmtpClient` no son interfaces propias y sus miembros importantes no siempre son virtuales: un doble de ellos prueba tu suposición sobre el tipo, no el tipo. Envuélvelos en un puerto pequeño que definas tú (`IPasarelaPago`) y sustituye el puerto; el adaptador real se prueba con integración.
- **Si el Arrange necesita más de tres o cuatro sustitutos, mira la clase, no el test.** Un constructor con muchas dependencias es el síntoma de una clase con demasiadas responsabilidades; un `ConfirmarPedido` con cuatro puertos ya está en el límite razonable.

## Documentación oficial

- [NSubstitute: documentación](https://nsubstitute.github.io/) — el índice de la ayuda oficial; las páginas *Getting started*, *Creating a substitute*, *Setting a return value* y *Checking received calls* cubren lo esencial con ejemplos cortos.
- [NSubstitute: argument matchers](https://nsubstitute.github.io/help/argument-matchers/) — el detalle de `Arg.Any`, `Arg.Is` y `Arg.Do`, y las reglas de mezcla con literales.
- [NSubstitute.Analyzers](https://github.com/nsubstitute/NSubstitute.Analyzers) — la lista de reglas `NS1000`, `NS4000`... con su explicación; útil cuando el analizador avisa y no se entiende por qué.
- [NSubstitute en GitHub](https://github.com/nsubstitute/NSubstitute) — código, historial de versiones y *issues*; el sitio donde mirar si una conducta rara es un fallo conocido.

## Recursos didácticos

- [Mocks Aren't Stubs (Martin Fowler)](https://martinfowler.com/articles/mocksArentStubs.html) — el artículo que separa la verificación de estado de la de comportamiento; explica el debate entre fakes y mocks que la tabla de decisión resume.
- [Test Double (Martin Fowler)](https://martinfowler.com/bliki/TestDouble.html) — la definición breve de dummy, stub, spy, mock y fake, para consultar el vocabulario.

---

*En resumen: NSubstitute fabrica las dependencias falsas para que el test unitario pruebe solo tu lógica; configura con `Returns` lo que el código necesita, verifica con `Received` solo los efectos que son el contrato, y prefiere un fake o el objeto real cuando la dependencia tiene estado o cuando comprobar cada llamada interna ataría el test a la implementación.*
