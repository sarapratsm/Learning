# Capa de Dominio

## ¿Qué es?

La capa de dominio es el **centro** de Clean Architecture: contiene las entidades, los objetos de valor y las reglas de negocio de la aplicación. Describe *qué es* el negocio (un pedido, un cliente, un producto) y *qué reglas se cumplen siempre*, sin saber nada de bases de datos, HTTP ni frameworks.

## ¿Por qué existe?

Las reglas de negocio son lo más valioso y lo más estable de una aplicación: «un pedido sin líneas no se puede confirmar», «un pedido pagado no se puede cancelar», «el stock no puede ser negativo». Cambiar de base de datos, de ORM o de framework web no debería tocarlas. Si están desperdigadas entre controladores, consultas y servicios, cada cambio técnico las pone en riesgo y nadie sabe en qué sitio está la versión buena de la regla.

La capa de dominio las **aísla** en un lugar sin dependencias externas: solo objetos y lógica. Eso la hace fácil de entender, de probar sin infraestructura y de proteger.

La analogía es la de una tabla frente a una entidad. La tabla `Pedidos` de una base de datos es *cómo se guarda* un pedido: columnas, tipos, claves. Cualquiera con acceso puede escribir `Estado = 'Pagado'` en una fila sin que nadie vigile nada. La entidad `Pedido` es *qué significa* un pedido y *qué puede hacerse con él*: no ofrece escribir el estado, ofrece operaciones (`Confirmar`, `Cancelar`) que solo avanzan si la regla lo permite. La tabla guarda datos; la entidad garantiza que esos datos tengan sentido.

## ¿Cuándo y para qué se usa?

Es la primera capa que se diseña al modelar un negocio y la que más cambia por motivos de negocio (y casi nunca por motivos técnicos). En una tienda online, aquí viven `Pedido`, `Cliente`, `Producto` y las reglas que los gobiernan. El resto (casos de uso, persistencia, API) se construye alrededor y depende de ella; el dominio no depende de nadie (ver [Regla de Dependencia](Regla-de-Dependencia.md)).

## La entidad: identidad, comportamiento y estado válido

Una **entidad** es un objeto que se distingue por su **identidad**, no por sus datos: el pedido #4711 sigue siendo el mismo aunque cambien sus líneas o su estado. Además de identidad, una entidad tiene **comportamiento** (operaciones con nombre de negocio) y garantiza un **estado válido**: ningún código externo puede dejarla en una situación que las reglas prohíben. A esas reglas que siempre deben cumplirse se las llama **invariantes**.

### Modelo anémico frente a entidad rica

El *modelo anémico* es una clase que solo tiene propiedades públicas, con la lógica en un «servicio» aparte:

```csharp
// ❌ Modelo anémico: cualquiera puede dejarlo en un estado inválido
public class Pedido
{
    public int Id { get; set; }
    public string Estado { get; set; } = "Borrador";
    public List<LineaPedido> Lineas { get; set; } = new();
}

public class PedidoService
{
    public void Confirmar(Pedido pedido)
    {
        if (pedido.Lineas.Count == 0) throw new Exception("Pedido vacío");
        pedido.Estado = "Confirmado";
    }
}
```

La regla existe, pero es opcional: otro código puede escribir `pedido.Estado = "Confirmado"` sin pasar por `PedidoService`, o `pedido.Lineas.Clear()` después de confirmar, o `pedido.Estado = "Pagadoo"` con una errata. La regla vive en un sitio y los datos en otro, y el compilador no obliga a juntarlos.

En la *entidad rica* los datos y las reglas viajan juntos, y la única forma de cambiar el estado es una operación que valida:

```csharp
// ✅ Entidad rica: el estado solo cambia por operaciones que validan
var pedido = Pedido.Crear(new IdPedido(4711), new IdCliente(1), ahora);
pedido.Confirmar(ahora);   // lanza ReglaDeDominioException: no hay líneas
```

Aquí `Estado` no tiene `set` público, `Lineas` es de solo lectura hacia fuera y no existe `new Pedido()` vacío. El estado inválido no es «algo que hay que acordarse de validar»: es **imposible de construir**.

### El `Pedido` completo

Reglas del ejemplo: un pedido sin líneas no se confirma, un pedido pagado no se cancela, la cantidad de cada línea es mayor que cero. El constructor es privado y la única entrada es la fábrica estática `Pedido.Crear`, de modo que cada objeto nace válido:

```csharp
namespace Tienda.Dominio;

public class ReglaDeDominioException(string message) : Exception(message);

public enum EstadoPedido { Borrador, Confirmado, Pagado, Cancelado }

public sealed class LineaPedido
{
    public IdProducto ProductoId { get; }
    public int Cantidad { get; }
    public Dinero PrecioUnitario { get; }
    public Dinero Subtotal => PrecioUnitario.Multiplicar(Cantidad);

    internal LineaPedido(IdProducto productoId, int cantidad, Dinero precioUnitario)
    {
        if (cantidad <= 0)
            throw new ReglaDeDominioException("La cantidad debe ser mayor que cero.");
        ProductoId = productoId;
        Cantidad = cantidad;
        PrecioUnitario = precioUnitario;
    }
}

public sealed class Pedido
{
    private readonly List<LineaPedido> _lineas = [];

    public IdPedido Id { get; }
    public IdCliente ClienteId { get; }
    public EstadoPedido Estado { get; private set; }
    public DateTimeOffset CreadoEn { get; }
    public DateTimeOffset? ConfirmadoEn { get; private set; }
    public IReadOnlyList<LineaPedido> Lineas => _lineas.AsReadOnly();

    private Pedido(IdPedido id, IdCliente clienteId, DateTimeOffset creadoEn)
    {
        Id = id;
        ClienteId = clienteId;
        CreadoEn = creadoEn;
        Estado = EstadoPedido.Borrador;
    }

    public static Pedido Crear(IdPedido id, IdCliente clienteId, DateTimeOffset ahora) =>
        new(id, clienteId, ahora);

    public Dinero Total(string moneda) =>
        _lineas.Aggregate(Dinero.Cero(moneda), (acum, l) => acum.Sumar(l.Subtotal));

    public void AñadirLinea(IdProducto productoId, int cantidad, Dinero precioUnitario)
    {
        if (Estado != EstadoPedido.Borrador)
            throw new ReglaDeDominioException("Solo se pueden añadir líneas a un pedido en borrador.");
        _lineas.Add(new LineaPedido(productoId, cantidad, precioUnitario));
    }

    public void Confirmar(DateTimeOffset ahora)
    {
        if (Estado != EstadoPedido.Borrador)
            throw new ReglaDeDominioException($"Un pedido {Estado} no se puede confirmar.");
        if (_lineas.Count == 0)
            throw new ReglaDeDominioException("Un pedido sin líneas no se puede confirmar.");
        Estado = EstadoPedido.Confirmado;
        ConfirmadoEn = ahora;
    }

    public void MarcarPagado()
    {
        if (Estado != EstadoPedido.Confirmado)
            throw new ReglaDeDominioException("Solo un pedido confirmado puede pagarse.");
        Estado = EstadoPedido.Pagado;
    }

    public void Cancelar()
    {
        if (Estado == EstadoPedido.Pagado)
            throw new ReglaDeDominioException("Un pedido pagado no se puede cancelar.");
        if (Estado == EstadoPedido.Cancelado)
            throw new ReglaDeDominioException("El pedido ya está cancelado.");
        Estado = EstadoPedido.Cancelado;
    }
}
```

Detalles que sostienen las invariantes:

- **Constructor privado + `Crear`**: quien necesite un `Pedido` pasa por la fábrica, que es el único sitio donde se decide qué es un pedido recién nacido. Si mañana crear exige más datos, el compilador señala todos los llamadores.
- **Colección encapsulada**: `_lineas` es privada y hacia fuera se expone `AsReadOnly()`. Exponer `IReadOnlyList<LineaPedido> Lineas => _lineas` a secas parece equivalente, pero cualquiera puede hacer `(List<LineaPedido>)pedido.Lineas` y saltarse las reglas; la envoltura de solo lectura lo impide.
- **`LineaPedido` con constructor `internal`**: solo el `Pedido` puede crear líneas, así que la regla de cantidad > 0 no tiene atajo.
- **Los verbos son del negocio** (`Confirmar`, `MarcarPagado`, `Cancelar`), no `SetEstado`.

Un programa que lo ejercita, con la salida real:

```csharp
var ahora = new DateTimeOffset(2026, 11, 9, 10, 0, 0, TimeSpan.Zero);
var pedido = Pedido.Crear(new IdPedido(4711), new IdCliente(1), ahora);

Intentar("Confirmar vacío", () => pedido.Confirmar(ahora));
pedido.AñadirLinea(new IdProducto(7), 2, Dinero.De(19.99m, "EUR"));
pedido.AñadirLinea(new IdProducto(9), 1, Dinero.De(5.50m, "EUR"));
Console.WriteLine($"Total: {pedido.Total("EUR")}");
Intentar("Cantidad 0", () => pedido.AñadirLinea(new IdProducto(7), 0, Dinero.De(1, "EUR")));
pedido.Confirmar(ahora.AddMinutes(5));
pedido.MarcarPagado();
Intentar("Cancelar pagado", () => pedido.Cancelar());
Console.WriteLine($"Estado: {pedido.Estado}");

static void Intentar(string nombre, Action accion)
{
    try { accion(); Console.WriteLine($"{nombre}: OK"); }
    catch (ReglaDeDominioException e) { Console.WriteLine($"{nombre}: {e.Message}"); }
}
```

```text
Confirmar vacío: Un pedido sin líneas no se puede confirmar.
Total: 45,48 EUR
Cantidad 0: La cantidad debe ser mayor que cero.
Cancelar pagado: Un pedido pagado no se puede cancelar.
Estado: Pagado
```

Cada regla se prueba sin base de datos, sin servidor y sin simulacros (*mocks*): es código C# puro. (El `45,48` usa la coma decimal porque la salida se obtuvo con cultura `es-ES`.) Quién llama a estas operaciones, en qué orden y con qué transacción alrededor es trabajo de los [Casos de Uso](Casos-de-Uso.md). Cómo se guarda un `Pedido` con constructor privado y colección encapsulada es asunto de la [Capa de Infraestructura](Capa-de-Infraestructura.md). Para el concepto de agregado (qué entidades se tratan como unidad y quién es su raíz) ver [Entidades y Agregados](../patrones-de-diseno/Entidades-y-Agregados.md).

## Objetos de valor e ids tipados

Un **objeto de valor** modela un concepto sin identidad propia: un importe, un email, una dirección. Dos objetos con los mismos datos son intercambiables, así que se comparan **por valor** y son inmutables. Un `record` de C# da esa igualdad gratis. Con un constructor privado y una fábrica, además validan al nacer:

```csharp
public sealed record Dinero
{
    public decimal Importe { get; }
    public string Moneda { get; }

    private Dinero(decimal importe, string moneda) => (Importe, Moneda) = (importe, moneda);

    public static Dinero De(decimal importe, string moneda)
    {
        if (importe < 0)
            throw new ReglaDeDominioException("El dinero no puede ser negativo.");
        if (string.IsNullOrWhiteSpace(moneda) || moneda.Length != 3)
            throw new ReglaDeDominioException("La moneda debe ser un código de 3 letras.");
        return new Dinero(Math.Round(importe, 2), moneda.ToUpperInvariant());
    }

    public static Dinero Cero(string moneda) => De(0, moneda);

    public Dinero Sumar(Dinero otro)
    {
        if (Moneda != otro.Moneda)
            throw new ReglaDeDominioException($"No se pueden sumar {Moneda} y {otro.Moneda}.");
        return new Dinero(Importe + otro.Importe, Moneda);
    }

    public Dinero Multiplicar(decimal factor) => De(Importe * factor, Moneda);

    public override string ToString() => $"{Importe:0.00} {Moneda}";
}

public sealed record Email
{
    public string Valor { get; }
    private Email(string valor) => Valor = valor;

    public static Email Crear(string texto)
    {
        var limpio = texto?.Trim().ToLowerInvariant() ?? "";
        if (!limpio.Contains('@') || limpio.StartsWith('@') || limpio.EndsWith('@'))
            throw new ReglaDeDominioException($"'{texto}' no es un email válido.");
        return new Email(limpio);
    }
}
```

Lo que consigue frente a un `decimal` y un `string` sueltos:

```csharp
Console.WriteLine(Dinero.De(10, "eur") == Dinero.De(10.00m, "EUR"));        // True: igualdad por valor
Console.WriteLine(Email.Crear(" Ana@Tienda.com ") == Email.Crear("ana@tienda.com")); // True: normalizado
Dinero.De(1, "EUR").Sumar(Dinero.De(1, "USD"));  // ReglaDeDominioException: No se pueden sumar EUR y USD.
```

Con `decimal` el compilador sumaría euros y dólares sin protestar; con `Dinero`, la mezcla de monedas es una regla del tipo. Los propios `Pedido` y `LineaPedido` usan `Dinero` y por eso nunca tienen importes negativos.

Los **ids tipados** son objetos de valor mínimos que evitan la obsesión por los primitivos: con `int pedidoId, int clienteId` el compilador acepta intercambiarlos; con tipos distintos, es un error de compilación.

```csharp
public readonly record struct IdPedido(int Valor);
public readonly record struct IdCliente(int Valor);
public readonly record struct IdProducto(int Valor);

// Pedido.Crear(new IdCliente(1), new IdPedido(4711), ahora);  // ❌ no compila: argumentos cruzados
```

`readonly record struct` evita reservar memoria en cada id y conserva la igualdad por valor. Para profundizar (colecciones de objetos de valor, cuándo un concepto merece serlo) ver [Value Objects](../patrones-de-diseno/Value-Objects.md).

## Regla incumplida: excepción o resultado

No toda regla rota es lo mismo. La pregunta es si quien llama **podía haberlo evitado** y si el fallo es parte del funcionamiento normal del negocio:

| Situación | Ejemplo | Cómo se comunica |
|---|---|---|
| **Invariante violada**: quien llama no debía llegar aquí; si ocurre, hay un bug | Cantidad ≤ 0, importe negativo, cancelar un pedido pagado desde un flujo que ya comprobó el estado | Excepción de dominio (`ReglaDeDominioException`) |
| **Fallo esperable**: depende de datos que cambian y es un desenlace normal | Stock insuficiente al reservar, cupón caducado | Resultado explícito en el valor devuelto |

Un pedido sin stock suficiente no es un error de programación: ocurrirá cada día y la capa superior debe reaccionar con normalidad (ofrecer menos unidades, avisar). Lanzar una excepción por cada caso así convierte el flujo normal en `try/catch` en cascada y oculta en la firma del método que puede fallar. Una invariante, en cambio, es un contrato: si salta, algo del código que llama está mal y conviene que falle ruidosamente.

```csharp
public enum ResultadoReserva { Reservado, StockInsuficiente }

public sealed class Producto
{
    public int Stock { get; private set; }

    public Producto(IdProducto id, string nombre, int stock)
    {
        if (stock < 0)
            throw new ReglaDeDominioException("El stock no puede ser negativo."); // invariante
        Id = id; Nombre = nombre; Stock = stock;
    }

    public IdProducto Id { get; }
    public string Nombre { get; }

    public ResultadoReserva Reservar(int cantidad)
    {
        if (cantidad <= 0)
            throw new ReglaDeDominioException("La cantidad debe ser mayor que cero."); // invariante
        if (cantidad > Stock)
            return ResultadoReserva.StockInsuficiente;                                 // fallo esperable
        Stock -= cantidad;
        return ResultadoReserva.Reservado;
    }
}
```

Con `Stock = 3`: `Reservar(5)` devuelve `StockInsuficiente` y el stock sigue en 3; `Reservar(3)` devuelve `Reservado` y deja `Stock = 0`. En ningún caso el stock queda negativo. El enum es la versión mínima de un resultado explícito; cuando hay que llevar además un mensaje o un valor, el patrón se desarrolla en [Result Pattern](../patrones-de-diseno/Result-Pattern.md), y en qué capa vive cada código de resultado en [Códigos de Resultado por Capa](Codigos-de-Resultado-por-Capa.md).

## El reloj y otras fuentes de no determinismo

Una regla es **determinista** si, con las mismas entradas, da siempre la misma salida. `DateTime.Now`, `Guid.NewGuid()` o `Random` dentro de una entidad rompen eso: la regla «un borrador caduca a las 24 horas» no se puede probar sin esperar un día, o sin tocar el reloj del sistema. El reloj es una dependencia más, y el dominio no debería leer el mundo exterior ni para saber la hora.

Hay dos salidas. La primera, la más simple: **la fecha entra por parámetro**. Es lo que hace `Pedido.Confirmar(ahora)`, y la regla de caducidad se escribe igual:

```csharp
// dentro de Pedido
private static readonly TimeSpan VigenciaDelBorrador = TimeSpan.FromHours(24);

public bool HaCaducado(DateTimeOffset ahora) =>
    Estado == EstadoPedido.Borrador && ahora - CreadoEn > VigenciaDelBorrador;
```

La segunda: quien orquesta (el caso de uso) abstrae el reloj con `TimeProvider`, disponible desde .NET 8, y le pide la hora para pasarla al dominio:

```csharp
// en el caso de uso (ver Casos de Uso): el dominio solo recibe la fecha
pedido.Confirmar(tiempo.GetUtcNow());
```

El test, con un reloj fijo que hereda de `TimeProvider`:

```csharp
class RelojFijo(DateTimeOffset ahora) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => ahora;
}

var inicio = new DateTimeOffset(2026, 11, 9, 10, 0, 0, TimeSpan.Zero);
var borrador = Pedido.Crear(new IdPedido(4712), new IdCliente(1), inicio);

Console.WriteLine(borrador.HaCaducado(inicio.AddHours(23).AddMinutes(59)));  // False
Console.WriteLine(borrador.HaCaducado(inicio.AddHours(24).AddMinutes(1)));   // True
Console.WriteLine(borrador.HaCaducado(new RelojFijo(inicio.AddHours(25)).GetUtcNow())); // True
```

Los dos extremos (23 h 59 min y 24 h 1 min) se comprueban al instante y siempre dan lo mismo. Con `DateTime.UtcNow` dentro de `HaCaducado`, el test solo podría comprobar «ahora mismo no ha caducado». El paquete `Microsoft.Extensions.TimeProvider.Testing` ofrece un `FakeTimeProvider` que avanza el tiempo a voluntad, por si el reloj fijo se queda corto. El mismo criterio vale para los identificadores aleatorios: se generan fuera y entran por parámetro.

## Servicios de dominio y lo que no va en el dominio

### Servicios de dominio

Cuando una regla de negocio involucra a varias entidades y no pertenece naturalmente a ninguna, se modela como **servicio de dominio**: una clase sin estado, con lógica pura y sin acceso a recursos externos. Ejemplo: «un cliente premium tiene un 10 % de descuento en pedidos de 100 EUR o más». Depende de `Cliente` y de `Pedido`; meterla en `Pedido` le obligaría a conocer qué es un cliente premium.

```csharp
public sealed class Cliente(IdCliente id, Email email, bool esPremium)
{
    public IdCliente Id { get; } = id;
    public Email Email { get; } = email;
    public bool EsPremium { get; } = esPremium;
}

public static class PoliticaDeDescuento
{
    public static Dinero Calcular(Cliente cliente, Pedido pedido, string moneda)
    {
        var total = pedido.Total(moneda);
        return cliente.EsPremium && total.Importe >= 100
            ? total.Multiplicar(0.10m)
            : Dinero.Cero(moneda);
    }
}
```

Para un cliente premium con un pedido de 5 unidades a 30 EUR (total 150 EUR), `Calcular` devuelve `15,00 EUR`. Ojo con el nombre «servicio»: un servicio de dominio recibe objetos de dominio ya cargados y decide; no consulta repositorios ni coordina pasos (eso es un [caso de uso](Casos-de-Uso.md)). Si la regla cabe en una entidad, va en la entidad: crear servicios de más es la vía de vuelta al modelo anémico.

### Qué no va en el dominio

| No va aquí | Por qué | Dónde va |
|---|---|---|
| SQL, `DbContext`, atributos del ORM | Ata las reglas a una tecnología de persistencia | [Capa de Infraestructura](Capa-de-Infraestructura.md) |
| HTTP, `HttpContext`, códigos de estado | El dominio no sabe quién lo invoca | Capa de API |
| DTO de entrada y salida | Su forma depende del contrato con el cliente, no del negocio | Capa de aplicación o API |
| Transacciones y orquestación de varios pasos | Coordinar «confirmar, cobrar, guardar» no es una regla de una entidad | [Casos de Uso](Casos-de-Uso.md) |
| Envío de correo, llamadas a la pasarela de pago | Efectos con el mundo exterior | Adaptadores de infraestructura |
| Validación de formato de la entrada (JSON mal formado, campo obligatorio ausente) | Es un asunto del contrato de la API, con respuestas 400 amigables | Capa de API |

La última fila suele confundirse con las invariantes. `Email.Crear` rechaza un texto sin `@` porque un `Email` inválido no puede existir en el negocio; la API valida además el formato de la petición para devolver un mensaje claro al cliente antes de llegar al dominio. Son dos filtros con propósitos distintos, y el segundo no sustituye al primero.

### Cuándo un dominio rico no merece la pena

Si la aplicación solo crea, lista, edita y borra filas sin reglas entre campos (un catálogo de países, un panel de administración de tablas auxiliares), un dominio rico es ceremonia: entidades con constructor privado y fábrica que solo reenvían datos. Basta con CRUD directo sobre el acceso a datos. El dominio rico se paga solo cuando hay reglas que se rompen con facilidad, estados con transiciones o conceptos con comportamiento (como el `Pedido` de arriba).

## Buenas prácticas avanzadas

- **Haz imposible el estado inválido desde el constructor** — validar en los métodos no basta si se puede hacer `new Pedido()` vacío y rellenarlo a medias: la invariante nació rota. Constructor privado y fábrica estática que exija todo lo imprescindible. Para el ORM, un constructor privado sin parámetros y sin lógica solo si el ORM lo exige.
- **No expongas la colección interna, ni siquiera como `IReadOnlyList` sin envolver** — `IReadOnlyList<T> Lineas => _lineas` se puede convertir de vuelta a `List<T>` con un *cast*. `_lineas.AsReadOnly()` devuelve una vista que no se puede convertir.
- **Una excepción de dominio propia, no `Exception` ni `InvalidOperationException` a secas** — una `ReglaDeDominioException` permite que la capa superior la capture y la traduzca a una respuesta de negocio, sin tragarse por accidente fallos de infraestructura que también son `InvalidOperationException`.
- **Nombra las operaciones con el lenguaje del negocio** — `Confirmar`, `Cancelar`, `MarcarPagado`, no `SetEstado(EstadoPedido.Confirmado)`. Un setter público de estado reabre la puerta a todas las transiciones inválidas y obliga a repetir la validación en cada llamador.
- **Los fallos esperables no se lanzan, se devuelven** — si un desenlace ocurre a diario (stock insuficiente), una excepción cuesta rendimiento y esconde el camino normal. Reserva las excepciones para invariantes cuyo incumplimiento indica un bug.
- **El reloj, los ids aleatorios y las cadenas de cultura entran por parámetro o por una abstracción** — `DateTime.Now`, `Guid.NewGuid()` y `ToString()` sin cultura hacen que el mismo test pase en tu máquina y falle en la de otra persona o en integración continua.

## Documentación oficial

- [Fundamentos de C# sobre `record`](https://learn.microsoft.com/es-es/dotnet/csharp/language-reference/builtin-types/record) — la igualdad por valor, `with` y las diferencias entre `record` y `record struct`; consultar al modelar objetos de valor.
- [`TimeProvider`](https://learn.microsoft.com/es-es/dotnet/api/system.timeprovider) — la abstracción del reloj de .NET 8; consultar para sustituir el tiempo en pruebas.

---

*En resumen: el dominio es el centro limpio donde las reglas del negocio se protegen a sí mismas: el estado inválido no se puede construir, el tiempo entra por parámetro y la tecnología queda fuera.*
