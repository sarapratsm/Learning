# Strategy

## ¿Qué es?

Strategy es un patrón de diseño clásico (GoF) que saca una familia de algoritmos intercambiables a piezas separadas que comparten un mismo contrato (una interfaz o un delegado), de modo que el código que los usa recibe «un algoritmo» sin saber cuál es y puede cambiar de uno a otro sin modificarse.

## ¿Por qué existe?

Cuando hay varias formas de hacer lo mismo (calcular el envío, aplicar un descuento, ordenar un listado), la solución directa es un `switch` o una cadena de `if` que decide según el caso. Funciona con dos variantes. Con cinco, el método mezcla las reglas de todas, cada variante nueva obliga a editar y volver a probar el método entero, y las variantes dejan de tener nombre: son ramas anónimas de un bloque cada vez más largo.

Strategy da a cada variante su propia pieza y su nombre. Añadir una variante es añadir una clase; las que ya funcionaban no se tocan.

La analogía es la de un navegador GPS con modos de ruta. El destino y el mapa son los mismos; «más rápida», «más corta» o «evitar peajes» son tres formas intercambiables de calcular el camino. El GPS no contiene un `if` gigante con todos los criterios: recibe el modo elegido y le pide la ruta.

## ¿Cuándo y para qué se usa?

Siempre que el «cómo» varía y el «qué se necesita» es fijo: gastos de envío según el tipo de envío, descuentos según la promoción, criterios de ordenación, cálculo de impuestos por país, formato de exportación (CSV, JSON), política de reintentos. La señal en el código es un `switch` sobre un tipo o un enum cuyas ramas calculan lo mismo de maneras distintas, y que crece con cada requisito.

## El problema: un `switch` que crece

En la tienda online, el pedido #4711 (2 unidades a 19,99 EUR, total 39,98 EUR) se envía de tres formas: estándar (5,99 EUR, gratis desde 50 EUR), exprés (14,99 EUR) y recogida en tienda (gratis). Todo en un método:

```csharp
// ❌ Un método que sabe calcular todos los envíos
public static class CalculoConSwitch
{
    public static Dinero CalcularEnvio(Pedido pedido, TipoEnvio tipo)
    {
        var total = pedido.Total("EUR");
        switch (tipo)
        {
            case TipoEnvio.Estandar:
                return total.Importe >= 50 ? Dinero.Cero("EUR") : Dinero.De(5.99m, "EUR");
            case TipoEnvio.Expres:
                return Dinero.De(14.99m, "EUR");
            case TipoEnvio.Recogida:
                return Dinero.Cero("EUR");
            default:
                throw new ArgumentOutOfRangeException(nameof(tipo));
        }
    }
}
```

El día que negocio pide «envío internacional» (24,99 EUR más un 10 % del total), hay que editar este método: añadir un `case`, tocar el enum, y volver a probar los cuatro envíos, porque un error de llave o un `return` mal puesto en la rama nueva puede romper las anteriores. Con el tiempo aparecen condiciones cruzadas (internacional y exprés, internacional y pedido grande) y el método pasa a ser el lugar donde nadie se atreve a tocar.

Con Strategy, cada variante es una clase detrás de la misma interfaz:

```csharp
// ✅ Una clase por variante
public interface ICalculoDeEnvio
{
    TipoEnvio Tipo { get; }              // a qué tipo de envío corresponde
    Dinero Calcular(Pedido pedido);      // el algoritmo
}
```

Añadir el envío internacional es crear `EnvioInternacional` y registrarlo. Ni `EnvioEstandar`, ni `EnvioExpres`, ni `RecogidaEnTienda` se editan, y por tanto sus pruebas no necesitan repetirse.

## La forma completa

Tres piezas: la **interfaz** (el contrato), las **estrategias** (una implementación por variante) y el **contexto** (el código que usa una estrategia sin saber cuál es).

### La interfaz y las estrategias

```csharp
namespace Tienda.Aplicacion.Envios;

public enum TipoEnvio { Estandar, Expres, Recogida, Internacional }

public interface ICalculoDeEnvio
{
    TipoEnvio Tipo { get; }
    Dinero Calcular(Pedido pedido);
}

public sealed class EnvioEstandar : ICalculoDeEnvio
{
    public TipoEnvio Tipo => TipoEnvio.Estandar;
    public Dinero Calcular(Pedido pedido) =>
        pedido.Total("EUR").Importe >= 50 ? Dinero.Cero("EUR") : Dinero.De(5.99m, "EUR");
}

public sealed class EnvioExpres : ICalculoDeEnvio
{
    public TipoEnvio Tipo => TipoEnvio.Expres;
    public Dinero Calcular(Pedido pedido) => Dinero.De(14.99m, "EUR");
}

public sealed class RecogidaEnTienda : ICalculoDeEnvio
{
    public TipoEnvio Tipo => TipoEnvio.Recogida;
    public Dinero Calcular(Pedido pedido) => Dinero.Cero("EUR");
}
```

`Pedido` y `Dinero` son los de la [Capa de Dominio](../clean-architecture/Capa-de-Dominio.md). Cada clase es pequeña, se lee de una vez y su nombre dice qué regla de negocio contiene. La interfaz expone solo lo que el contexto necesita: la operación (`Calcular`) y, para poder elegir entre ellas, a qué variante corresponde (`Tipo`).

### El contexto

El contexto es quien necesita el resultado. Recibe la estrategia de dos maneras, según cuándo se decide cuál usar.

**Por constructor**, cuando la estrategia es la misma durante toda la vida del objeto:

```csharp
public sealed class ResumenDeCobro(ICalculoDeEnvio envio)
{
    public Dinero TotalConEnvio(Pedido pedido) =>
        pedido.Total("EUR").Sumar(envio.Calcular(pedido));
}
```

**Por parámetro**, cuando cada llamada puede usar una distinta (el caso habitual: cada pedido elige su tipo de envío):

```csharp
public sealed class CalculadoraDeTotal
{
    public Dinero TotalConEnvio(Pedido pedido, ICalculoDeEnvio envio) =>
        pedido.Total("EUR").Sumar(envio.Calcular(pedido));
}
```

Para el pedido #4711, con envío exprés y con envío estándar, el resultado es:

```text
54,97 EUR     // 39,98 + 14,99  (ResumenDeCobro con EnvioExpres)
45,97 EUR     // 39,98 + 5,99   (CalculadoraDeTotal con EnvioEstandar)
```

(Salida de un programa ejecutado con cultura `es-ES`, de ahí la coma decimal.) El contexto no contiene ningún `if` sobre el tipo de envío ni conoce las clases concretas: solo conoce `ICalculoDeEnvio`.

## Cómo se elige la estrategia

Strategy es el comportamiento intercambiable; **elegir** cuál se usa es otro problema. Alguien tiene que traducir «el cliente ha marcado envío exprés» (un dato) en «esta instancia de `EnvioExpres`» (un objeto). Si esa traducción es un `switch` repetido en cada sitio que necesita la estrategia, el problema original solo se ha movido. La regla es que la elección vive en **un único lugar**. Quién decide y cómo se construye lo elegido es el terreno de [Factory](Factory.md); aquí aparecen las tres formas habituales en .NET.

### Registro con todas las estrategias inyectadas

El contenedor inyecta todas las implementaciones de la interfaz como `IEnumerable<ICalculoDeEnvio>`, y un selector las indexa por su `Tipo`:

```csharp
public sealed class SelectorDeEnvio(IEnumerable<ICalculoDeEnvio> estrategias)
{
    private readonly Dictionary<TipoEnvio, ICalculoDeEnvio> _porTipo =
        estrategias.ToDictionary(e => e.Tipo);

    public ICalculoDeEnvio Para(TipoEnvio tipo) =>
        _porTipo.TryGetValue(tipo, out var e)
            ? e
            : throw new NotSupportedException($"No hay cálculo de envío para {tipo}.");
}

// Registro
services.AddSingleton<ICalculoDeEnvio, EnvioEstandar>();
services.AddSingleton<ICalculoDeEnvio, EnvioExpres>();
services.AddSingleton<ICalculoDeEnvio, RecogidaEnTienda>();
services.AddSingleton<SelectorDeEnvio>();
```

Una estrategia nueva se añade con una línea de registro; el selector no cambia. Si dos estrategias declaran el mismo `Tipo`, `ToDictionary` lanza una excepción al construir el selector, es decir, el error aparece al arrancar y no en producción con un pedido concreto. Si la regla de selección no es «un tipo, una estrategia» (por ejemplo, «exprés solo si el destino es nacional»), la interfaz puede exponer un método `bool Aplica(Pedido pedido)` en lugar de `Tipo` y el selector escoge la primera que aplique.

### Servicios con clave (.NET 8)

Desde .NET 8 el contenedor permite registrar una implementación bajo una clave y pedirla por esa clave, sin selector propio:

```csharp
services.AddKeyedSingleton<ICalculoDeEnvio, EnvioExpres>(TipoEnvio.Expres);
services.AddKeyedSingleton<ICalculoDeEnvio, EnvioEstandar>(TipoEnvio.Estandar);

// Resolución: por clave en tiempo de ejecución...
var envio = provider.GetRequiredKeyedService<ICalculoDeEnvio>(TipoEnvio.Expres);

// ...o fija en un constructor
public sealed class ResumenExpres([FromKeyedServices(TipoEnvio.Expres)] ICalculoDeEnvio envio) { /* ... */ }
```

Pedir una clave sin registrar falla con `InvalidOperationException: No keyed service for type 'Tienda.Aplicacion.Envios.ICalculoDeEnvio' using key type 'Tienda.Aplicacion.Envios.TipoEnvio' has been registered.` Encaja cuando la clave es conocida al escribir el código o llega por una sola vía. Cuando la clave viene del dato del pedido en cada petición, pedir el servicio al contenedor desde el código de negocio equivale a usar un localizador de servicios; es preferible el selector de arriba, que es un objeto con nombre y se prueba sin contenedor.

### Qué usar

| Situación | Forma |
|---|---|
| El tipo llega como dato del pedido, varias estrategias, más a futuro | Selector con `IEnumerable<ICalculoDeEnvio>` y propiedad `Tipo` |
| La elección depende de una condición más rica que la igualdad | `IEnumerable<ICalculoDeEnvio>` con `Aplica(...)` |
| Cada servicio usa siempre la misma estrategia, fijada al componer | Servicios con clave y `[FromKeyedServices]` |
| Dos o tres variantes fijas y sin contenedor | Un `Dictionary` construido a mano |

Con el pedido #4711, el selector devuelve `5,99 EUR` (estándar), `14,99 EUR` (exprés), `0,00 EUR` (recogida) y, con el cálculo internacional registrado, `28,99 EUR`; las resoluciones por clave devuelven el mismo importe que el selector.

## Estrategias con dependencias

Una estrategia es una clase como las demás: puede recibir dependencias por constructor. El envío internacional no tiene tarifa fija; la consulta a un servicio del transportista a través de un puerto:

```csharp
public interface ITarifasDeTransportista
{
    Dinero TarifaBase(TipoEnvio tipo);
}

public sealed class EnvioInternacional(ITarifasDeTransportista tarifas) : ICalculoDeEnvio
{
    public TipoEnvio Tipo => TipoEnvio.Internacional;

    public Dinero Calcular(Pedido pedido) =>
        tarifas.TarifaBase(Tipo).Sumar(pedido.Total("EUR").Multiplicar(0.10m));
}
```

Con una tarifa base de 24,99 EUR y el pedido #4711 (39,98 EUR), el cálculo da 24,99 + 4,00 = `28,99 EUR`. La estrategia depende de la abstracción `ITarifasDeTransportista`, no del cliente HTTP del transportista; la implementación concreta vive en infraestructura y el contenedor la inyecta. El porqué de esa dirección de dependencias está en [Inversión de Dependencias](../clean-architecture/Inversion-de-Dependencias.md). El efecto práctico para Strategy es que la estrategia con dependencias se prueba con una implementación falsa del puerto.

## Strategy con delegados

Cuando el contrato tiene un único método, la interfaz es opcional: un delegado `Func<Pedido, Dinero>` cumple el mismo papel y la «clase por estrategia» se reduce a una lambda:

```csharp
public static readonly IReadOnlyDictionary<TipoEnvio, Func<Pedido, Dinero>> Tabla =
    new Dictionary<TipoEnvio, Func<Pedido, Dinero>>
    {
        [TipoEnvio.Estandar] = p => p.Total("EUR").Importe >= 50 ? Dinero.Cero("EUR") : Dinero.De(5.99m, "EUR"),
        [TipoEnvio.Expres]   = _ => Dinero.De(14.99m, "EUR"),
        [TipoEnvio.Recogida] = _ => Dinero.Cero("EUR"),
    };

var envio = Tabla[TipoEnvio.Estandar](pedido);   // 5,99 EUR
```

El segundo ejemplo de la tienda, los descuentos, muestra bien el caso en que el delegado basta: cada descuento es una función del total y no necesita nada más.

```csharp
public static class Descuentos
{
    public static readonly Func<Dinero, Dinero> PorVolumen =
        t => t.Importe >= 100 ? t.Multiplicar(0.10m) : Dinero.Cero(t.Moneda);

    public static Func<Dinero, Dinero> CuponFijo(decimal euros) =>
        t => Dinero.De(Math.Min(euros, t.Importe), t.Moneda);   // nunca más que el total
}

// Con el total del pedido #4711 (39,98 EUR):
Descuentos.PorVolumen(total);        // 0,00 EUR (no llega a 100)
Descuentos.CuponFijo(5)(total);      // 5,00 EUR
```

`CuponFijo(5)` devuelve una función que «recuerda» el 5: la lambda captura el parámetro, que es el estado más sencillo que puede tener una estrategia.

| Criterio | Delegado (`Func<…>`) | Interfaz y clase |
|---|---|---|
| Lógica de una o dos líneas, sin dependencias | Basta y sobra | Ceremonia |
| Necesita dependencias inyectadas (tarifa externa, repositorio) | Posible con una clase auxiliar, pero se vuelve opaco | Natural: constructor |
| Tiene estado propio o varios métodos (`Calcular`, `Describir`) | No encaja: un delegado es una sola operación | Natural |
| La variante es un concepto del negocio con nombre (`EnvioExpres`) | Se pierde el nombre en el diccionario | El nombre del tipo documenta la regla |
| Se registra y resuelve con el contenedor, por tipo o por clave | Incómodo: hay que registrar delegados | Natural |
| Pruebas | Se prueba la lambda por el diccionario | Se prueba la clase directamente, con su nombre en el informe de pruebas |

Regla práctica: empieza por un delegado si la variante cabe en una expresión y nadie le pondría un nombre de negocio; pasa a clase en cuanto aparezca la primera dependencia, el primer estado o la necesidad de mostrar la regla en un informe.

## Probar cada estrategia por separado

La ventaja que más se nota en el día a día: cada regla tiene su prueba, pequeña y sin preparación de las demás.

```csharp
public class EnvioTests
{
    private static Pedido PedidoDe(decimal precio, int cantidad = 1)
    {
        var p = Pedido.Crear(new IdPedido(4711), new IdCliente(1), DateTimeOffset.UtcNow);
        p.AñadirLinea(new IdProducto(7), cantidad, Dinero.De(precio, "EUR"));
        return p;
    }

    [Fact]
    public void Estandar_cobra_5_99_por_debajo_de_50()
    {
        var envio = new EnvioEstandar().Calcular(PedidoDe(49.99m));
        Assert.Equal(Dinero.De(5.99m, "EUR"), envio);
    }

    [Fact]
    public void Estandar_es_gratis_desde_50()
    {
        var envio = new EnvioEstandar().Calcular(PedidoDe(50m));
        Assert.Equal(Dinero.Cero("EUR"), envio);
    }

    private sealed class TarifaFalsa(decimal importe) : ITarifasDeTransportista
    {
        public Dinero TarifaBase(TipoEnvio tipo) => Dinero.De(importe, "EUR");
    }

    [Fact]
    public void Internacional_suma_tarifa_externa_y_10_por_ciento()
    {
        var envio = new EnvioInternacional(new TarifaFalsa(20m)).Calcular(PedidoDe(100m));
        Assert.Equal(Dinero.De(30m, "EUR"), envio);
    }
}
```

```text
Correctas EnvioTests.Estandar_es_gratis_desde_50
Correctas EnvioTests.Internacional_suma_tarifa_externa_y_10_por_ciento
Correctas EnvioTests.Estandar_cobra_5_99_por_debajo_de_50
Correctas! - Con error: 0, Superado: 3, Omitido: 0, Total: 3
```

Cada prueba instancia una sola clase, ni tabla, ni contenedor, ni enum. La del envío internacional sustituye el puerto con una clase de cuatro líneas. Con el `switch`, para probar el umbral de 50 EUR del envío estándar hay que pasar por el método que contiene también las ramas exprés, recogida e internacional: las pruebas pasan por la misma función, el fallo en una rama puede dejar a oscuras a las demás, y cada edición del método (por ejemplo, la rama nueva) obliga a repetir la batería completa para tener garantía. Con Strategy, tocar `EnvioInternacional` solo invalida las pruebas de `EnvioInternacional`.

## Strategy frente a patrones parecidos

| Patrón | Qué hace | Diferencia con Strategy |
|---|---|---|
| **State** | El comportamiento del objeto cambia según su estado interno, y las transiciones las provoca el propio objeto | En Strategy quien usa el objeto elige la variante desde fuera, y la estrategia no cambia por sí sola |
| **Template Method** | Fija el esqueleto de un algoritmo y deja que las subclases varíen algunos pasos | Strategy sustituye el algoritmo entero y por composición; Template Method varía pasos y por herencia |
| **Decorator** | Envuelve un objeto para añadir capacidades, apilándolas (ver [Decorator](Decorator.md)) | Decorator conserva el algoritmo y le añade algo alrededor; Strategy reemplaza el algoritmo |
| **Factory** | Crea objetos | Strategy es lo que se ejecuta; Factory puede ser quien entrega la estrategia adecuada (ver [Factory](Factory.md)) |

Lo que distingue a Strategy de State es **quién decide el cambio**: un pedido que pasa de `Confirmado` a `Pagado` por sus propias reglas es State; un pedido al que se le pasa el cálculo de envío que corresponde a lo que ha elegido el cliente es Strategy.

## Cuándo no usar Strategy

Strategy cambia un `switch` por una interfaz, varias clases y un mecanismo de selección. Ese coste solo compensa cuando la variación existe de verdad.

- **Dos variantes estables.** Si el envío fuera siempre «a domicilio o recogida» y nadie espera un tercer caso, un `if` de dos líneas es más claro que una interfaz con dos clases y un selector.
- **Variantes que no comparten contrato.** Si cada rama necesita datos distintos de entrada o devuelve cosas distintas, forzarlas bajo una interfaz común produce parámetros opcionales y valores sin sentido para algunas ramas.
- **Lógica que no va a cambiar de forma independiente.** Si todas las ramas se modifican siempre a la vez, no hay ventaja en separarlas.

Regla práctica: con una variante, no hay patrón; con dos, un `if`; la **tercera variante**, o la primera regla que cambia con frecuencia por su cuenta, es el momento de extraer estrategias. Aplicar Strategy antes es el «astronauta de la arquitectura»: abstracciones para variaciones que nadie ha pedido.

## Errores frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| La estrategia recibe el contexto entero (`Calcular(ServicioDePedidos contexto)`) y lee propiedades privadas de él | La estrategia se acopla al contexto: no se puede probar ni reutilizar sin él | Pasar solo los datos que necesita (`Pedido`, o un valor concreto como el total) |
| Los resultados cambian de una ejecución a otra bajo carga; el mismo pedido da importes distintos | Estrategia registrada como singleton con un campo mutable compartido entre peticiones | Estrategias sin estado, o con ciclo de vida acorde (`Scoped`/`Transient`); guardar el estado en variables locales |
| La interfaz acumula métodos (`CalcularEnvio`, `CalcularImpuesto`, `Describir`, `EsGratis`) y las implementaciones lanzan `NotSupportedException` | Se ha convertido en una interfaz «por cada caso de uso» en lugar de un único algoritmo | Una interfaz por algoritmo; si hay dos operaciones que varían juntas, valorar si son una sola estrategia |
| El selector tiene un `switch` sobre el tipo que hay que ampliar con cada estrategia | El `switch` reaparece en el registro y no se ha ganado nada | Indexar por la propiedad `Tipo` de cada estrategia, o resolver por clave |
| Una estrategia nueva se añade y el pedido sigue usando la anterior sin error | La estrategia no está registrada, o el selector resuelve la primera que aplica y otra la tapa | Excepción explícita cuando no hay estrategia para un tipo y pruebas del selector que enumeren todos los valores del enum |

### El estado compartido, medido

Una estrategia que guarda el total en un campo y lo lee después de otro paso funciona en una prueba secuencial y falla en producción:

```csharp
class EnvioConEstado
{
    private decimal _total;                         // estado mutable compartido

    public decimal CalcularPara(decimal total)
    {
        _total = total;
        Thread.SpinWait(50);                        // trabajo intermedio
        return _total * 0.10m;
    }
}

var envio = new EnvioConEstado();                   // una instancia, como un singleton
var errores = 0;
Parallel.For(0, 10_000, i =>
{
    var total = i % 2 == 0 ? 10m : 100m;
    if (envio.CalcularPara(total) != total * 0.10m) Interlocked.Increment(ref errores);
});
Console.WriteLine($"Cálculos incorrectos: {errores} de 10000");
```

```text
Cálculos incorrectos: 4900 de 10000
```

En dos ejecuciones se obtuvieron 4900 y 4408 errores: el número cambia, que es lo que hace estos fallos tan difíciles de reproducir. Con `_total` como variable local, el resultado es siempre correcto.

## Buenas prácticas avanzadas

- **Haz las estrategias sin estado y `sealed`** — una estrategia sin campos mutables es segura como singleton y trivialmente intercambiable. Si necesita datos, que lleguen por parámetro de `Calcular` o por constructor y sean inmutables.
- **Pasa a la estrategia solo lo que necesita** — un `Pedido` o un `Dinero`, no el servicio que la invoca. Una estrategia que recibe el contexto completo ya no es intercambiable: depende de quién la llama.
- **Falla al arrancar, no en la petición** — construye el selector con `ToDictionary` (que rechaza claves duplicadas) y comprueba en una prueba que hay una estrategia para cada valor de `TipoEnvio`. Añadir un valor al enum sin su estrategia debe romper una prueba, no un pedido.
- **Mantén la selección fuera de las estrategias y del contexto** — ninguna de las dos debería conocer el enum ni a sus hermanas. La única que sabe qué estrategia corresponde a cada dato es el selector o la configuración del contenedor.
- **Distingue «tipo» de «regla»** — si «exprés» tiene condiciones que dependen de más datos (destino, peso), la estrategia es la regla completa y el selector solo la elige por tipo; no repartas la regla entre la estrategia y quien la elige.
- **Nombra la estrategia por lo que hace en el negocio** — `EnvioExpres`, no `Estrategia2` ni `CalculadorB`. El informe de pruebas y los registros del contenedor se leen mejor.

## Documentación oficial

- [Strategy en Refactoring.Guru](https://refactoring.guru/es/design-patterns/strategy) — descripción del patrón del catálogo GoF (*Design Patterns*, Gamma, Helm, Johnson y Vlissides, 1994) con estructura y relaciones con otros patrones; consultar para la formulación canónica.
- [Inyección de dependencias en .NET: servicios con clave](https://learn.microsoft.com/es-es/dotnet/core/extensions/dependency-injection#keyed-services) — `AddKeyedSingleton`, `[FromKeyedServices]` y `GetRequiredKeyedService`; consultar al elegir estrategias por clave.

---

*En resumen: Strategy convierte un `switch` de comportamientos en piezas intercambiables detrás de un mismo contrato, para añadir variantes sin tocar las que ya funcionan; la elección de cuál usar sigue siendo necesaria y debe vivir en un solo lugar.*
