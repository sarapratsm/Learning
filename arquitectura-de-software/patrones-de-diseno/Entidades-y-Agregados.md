# Entidades y Agregados

## ¿Qué es?

Una **entidad** es un objeto del dominio que se distingue por su **identidad** (un id), no por sus atributos: aunque cambien sus datos, sigue siendo «la misma». Un **agregado** es un grupo de entidades y objetos de valor que se tratan como una sola unidad de consistencia, con una entidad concreta, la **raíz del agregado**, como única puerta de entrada desde fuera.

## ¿Por qué existe?

Muchas reglas de negocio no dependen de un solo objeto, sino de **varios a la vez**: «el total de un pedido no supera el límite de crédito», «un pedido no tiene más de 10 líneas». Esas reglas se llaman **invariantes** (condiciones que deben cumplirse siempre) y, cuando abarcan varios objetos, ninguno de ellos puede vigilarlas por sí solo. Si `LineaPedido` se puede modificar desde cualquier sitio, nada garantiza que la regla conjunta se cumpla.

El agregado marca una frontera: fuera de ella, nadie toca una línea suelta. Todo pasa por la raíz (`Pedido`), que es la única responsable de que el conjunto esté siempre en un estado válido.

> Piensa en un contrato con varios anexos. No se puede firmar ni modificar un anexo por separado sin pasar por el contrato principal: el contrato es la puerta de entrada y garantiza que el conjunto (contrato más anexos) sea siempre coherente.

## ¿Cuándo y para qué se usa?

Cada vez que un conjunto de objetos debe cambiar **junto** y de forma consistente: un `Pedido` con sus `LineaPedido`, un `Carrito` con sus `ItemCarrito`, una `Reserva` con sus `Ocupante`. Es una pieza central del diseño dirigido por el dominio (ver [Domain-Driven Design](Domain-Driven-Design.md)). Si el concepto es solo CRUD sin reglas entre sus partes, un agregado es ceremonia sobrante.

## Entidad frente a objeto de valor

Una **entidad** se compara por su id: el pedido #4711 sigue siendo el mismo aunque cambien sus líneas o su estado. Un [objeto de valor](Value-Objects.md) (`Dinero`, `Email`) se compara por contenido y no tiene vida propia: dos billetes de 10 EUR son intercambiables, dos pedidos con las mismas líneas no.

```csharp
public sealed class Cliente(IdCliente id, string nombre)
{
    public IdCliente Id { get; } = id;
    public string Nombre { get; private set; } = nombre;

    public override bool Equals(object? o) => o is Cliente otro && otro.Id == Id;
    public override int GetHashCode() => Id.GetHashCode();
}
```

Dos instancias de `Cliente` con el mismo `Id` son «el mismo cliente» aunque el `Nombre` difiera en el tiempo. Los ids tipados (`IdPedido`, `IdCliente`) son `record struct`, definidos en la [Capa de Dominio](../clean-architecture/Capa-de-Dominio.md).

## La raíz y las reglas de límite

Sin agregado, el `Pedido` es una bolsa de datos y cualquier código puede tocar sus partes:

```csharp
// ❌ Sin agregado: la línea es modificable desde fuera
class LineaAnemica { public int Cantidad { get; set; } public decimal PrecioUnitario { get; set; } }
class PedidoAnemico { public List<LineaAnemica> Lineas { get; set; } = new(); }

var pedido = new PedidoAnemico();
pedido.Lineas.Add(new LineaAnemica { Cantidad = 2, PrecioUnitario = 400m });
pedido.Lineas[0].Cantidad = 500;                       // nadie vigila el límite de crédito
for (var i = 0; i < 15; i++)
    pedido.Lineas.Add(new LineaAnemica { Cantidad = 1, PrecioUnitario = 1m });  // ni el máximo de líneas
```

```text
Total: 200000 EUR (limite 1000)
Lineas: 16
```

Cada regla se podría comprobar en el sitio donde se añade una línea, pero hay infinitas rutas para cambiar una cantidad o añadir otra línea, y basta una que olvide la comprobación. Con agregado, la regla vive en un único lugar, la raíz, y las demás rutas no existen. Este es el `Pedido` de la [Capa de Dominio](../clean-architecture/Capa-de-Dominio.md) (constructor privado, fábrica `Pedido.Crear`, colección encapsulada, `LineaPedido` con constructor `internal`) con las dos reglas de límite añadidas a `AñadirLinea`:

```csharp
public sealed class Pedido
{
    public const int MaximoDeLineas = 10;
    public static readonly Dinero LimiteDeCredito = Dinero.De(1000, "EUR");

    private readonly List<LineaPedido> _lineas = [];
    public IReadOnlyList<LineaPedido> Lineas => _lineas.AsReadOnly();
    // Id, ClienteId, Estado, Crear, Total, Confirmar, MarcarPagado y Cancelar, como en la Capa de Dominio

    public void AñadirLinea(IdProducto productoId, int cantidad, Dinero precioUnitario)
    {
        if (Estado != EstadoPedido.Borrador)
            throw new ReglaDeDominioException("Solo se pueden añadir líneas a un pedido en borrador.");
        if (_lineas.Count >= MaximoDeLineas)
            throw new ReglaDeDominioException($"Un pedido no puede tener más de {MaximoDeLineas} líneas.");

        var linea = new LineaPedido(productoId, cantidad, precioUnitario);
        if (Total("EUR").Sumar(linea.Subtotal).Importe > LimiteDeCredito.Importe)
            throw new ReglaDeDominioException($"El total no puede superar {LimiteDeCredito}.");

        _lineas.Add(linea);
    }
}
```

El límite de crédito fijo en 1000 EUR simplifica el ejemplo; en un caso real vendría del cliente y se pasaría como parámetro. Su ejecución:

```csharp
var pedido = Pedido.Crear(new IdPedido(4711), new IdCliente(1), ahora);
pedido.AñadirLinea(new IdProducto(7), 2, Dinero.De(400, "EUR"));   // OK
pedido.AñadirLinea(new IdProducto(8), 1, Dinero.De(300, "EUR"));   // total 1100
// 9 líneas más de 1 EUR: OK hasta la 10.ª; la 11.ª falla
```

```text
Total: 800,00 EUR
1 x 300 (total 1100): El total no puede superar 1000,00 EUR.
linea 10: OK
linea 11: Un pedido no puede tener más de 10 líneas.
Lineas: 10, total 809,00 EUR
```

La regla del total depende de **todas** las líneas a la vez: por eso la comprueba la raíz y no `LineaPedido`. Fuera del agregado, `pedido.Lineas.Add(...)` no compila (la vista es de solo lectura y no se puede convertir a `List<LineaPedido>`: probado, `pedido.Lineas as List<LineaPedido>` da `null`), y `new LineaPedido(...)` tampoco, porque su constructor es `internal`. La única puerta es `AñadirLinea`. Se dice que el agregado tiene **invariantes de límite**: reglas cuyo ámbito acaba en la frontera del agregado y que se garantizan en cada operación, no «al final».

## Referencias entre agregados: por id, no por objeto

Un `Pedido` guarda `IdCliente`, no un `Cliente`:

```csharp
// ❌ Navega al otro agregado
public sealed class Pedido { public Cliente Cliente { get; } }

// ✅ Referencia por id
public sealed class Pedido { public IdCliente ClienteId { get; } }
```

Las consecuencias del objeto completo:

| Aspecto | `Cliente Cliente` (por objeto) | `IdCliente ClienteId` (por id) |
|---|---|---|
| Carga | Cargar un pedido arrastra el cliente, y con él sus direcciones, y con ellas lo que cuelgue | Una fila de pedido y sus líneas |
| Transacción | Nada impide hacer `pedido.Cliente.CambiarNombre(...)` y guardar dos agregados a la vez | Para tocar al cliente hay que cargarlo por su cuenta: es otra operación |
| Memoria | El grafo vivo crece con cada navegación y se mantiene mientras viva el pedido | Un entero por referencia |
| Reglas | Es tentador saltarse la raíz del cliente y modificar sus partes desde el pedido | El pedido solo conoce la identidad |

Cuando el pedido necesita un dato del cliente para decidir (p. ej. su límite de crédito), el caso de uso carga ambos agregados y pasa el dato como parámetro, o una consulta de lectura lo proyecta; el agregado no sale a buscarlo.

## Frontera transaccional y consistencia entre agregados

El agregado es la unidad que se guarda completa: o el pedido con todas sus líneas queda persistido, o no queda nada. La regla práctica es **una transacción, un agregado**. Las invariantes de dentro del agregado se garantizan al instante; lo que cruza agregados se resuelve con **consistencia eventual**: el sistema converge, pero durante un intervalo los dos agregados pueden estar desfasados.

Ejemplo con dos contextos delimitados, `Pedidos` y `Catalogo`: confirmar el pedido #4711 debe descontar stock del `Producto` 7. Son dos agregados, de dos contextos distintos.

```text
Transacción 1 (Pedidos):  pedido.Confirmar()  ->  guardar Pedido  ->  PedidoConfirmado
Transacción 2 (Catalogo): reaccionar al hecho ->  producto.Reservar(2) -> guardar Producto
```

Entre la primera y la segunda transacción el pedido ya está confirmado y el stock todavía no ha bajado: es la ventana de inconsistencia, normalmente de milisegundos. Si el stock resulta insuficiente (fallo esperable, no bug), `Pedidos` reacciona con una compensación, como cancelar el pedido o avisar a la persona. Ampliar el agregado para que una sola transacción abarque pedido y producto elimina la ventana, pero obliga a bloquear catálogo entero por cada pedido. Cómo se publica y se maneja el hecho `PedidoConfirmado` se explica en [Domain Events](Domain-Events.md).

## Tamaño del agregado

Los agregados deben ser **pequeños**: solo lo que necesita estar consistente en cada operación. El peligro típico es agrupar por «pertenencia» en vez de por invariante:

```csharp
// ❌ Agregado Cliente con todos sus pedidos dentro
public sealed class Cliente
{
    public IdCliente Id { get; }
    private readonly List<Pedido> _pedidos = [];
}
```

Cálculo para un cliente con 500 pedidos de 6 líneas de media (cifras de ejemplo): cada operación carga 1 cliente + 500 pedidos + 3.000 líneas, también cuando solo se quiere confirmar el pedido #4711. Y el coste crece con la antigüedad del cliente. Con concurrencia optimista, la versión es una por agregado: si una persona confirma el pedido #4711 y otra cancela el #4712 al mismo tiempo (no comparten ninguna regla), una de las dos recibe un conflicto de versión y debe reintentar. Un cliente fiel colisiona más, no menos.

La salida es partir por invariantes: ¿qué regla exige que el pedido #4711 y el #4712 cambien juntos? Ninguna. Se quedan como agregados separados, con `Pedido` guardando `IdCliente`, y el cliente conserva solo sus datos. Si hace falta una regla sobre el conjunto (p. ej. «crédito pendiente total del cliente»), se mantiene como dato derivado actualizado con consistencia eventual, o se consulta con una proyección de lectura.

## ¿Agregado propio, entidad interna u objeto de valor?

| Pregunta | Sí | Ejemplo de la tienda |
|---|---|---|
| ¿Tiene identidad propia y se consulta o referencia por sí sola desde fuera? | Agregado propio (su propia raíz) | `Pedido`, `Cliente`, `Producto` |
| ¿Tiene identidad y ciclo de vida, pero solo tiene sentido dentro de otro y sus reglas dependen de él? | Entidad interna | `LineaPedido` (dentro de `Pedido`) |
| ¿Se define por sus datos, es inmutable e intercambiable? | Objeto de valor | `Dinero`, `Email`, dirección de envío |
| ¿Su regla debe cumplirse en la misma transacción que la de otro? | Mismo agregado | Líneas y total del `Pedido` |
| ¿Basta con que sea coherente «más tarde»? | Agregados distintos | `Pedido` y stock del `Producto` |

Ante la duda entre entidad interna y agregado propio, se elige agregado propio: unir después es más barato que partir un agregado en producción.

## Concurrencia optimista a nivel de agregado

Dos personas pueden cargar el mismo agregado, modificarlo y guardarlo: sin control, la última sobrescribe en silencio a la primera. La **concurrencia optimista** añade a la raíz un **token de versión** que cambia en cada guardado; el guardado hace `UPDATE ... WHERE Id = @id AND Version = @versionLeida` y, si no afecta ninguna fila, alguien se adelantó.

EF Core lo implementa con un token de concurrencia (ver [Entity Framework Core](../../bases-de-datos/acceso-a-datos-dotnet/Entity-Framework-Core.md)). Probado con SQLite en memoria, con una clase de persistencia mínima:

```csharp
class PedidoFila
{
    public int Id { get; set; }
    public string Estado { get; private set; } = "Borrador";
    [ConcurrencyCheck] public int Version { get; private set; }
    public void Confirmar() { Estado = "Confirmado"; Version++; }
    public void Cancelar()  { Estado = "Cancelado";  Version++; }
}

// dos contextos cargan el mismo pedido
pa.Confirmar(); a.SaveChanges();          // OK
pb.Cancelar();  b.SaveChanges();          // lanza DbUpdateConcurrencyException
```

```text
A guarda: Estado=Confirmado, Version=1
B: DbUpdateConcurrencyException - The database operation was expected to affect 1 row(s), but actually affected 0 row(s); ...
```

Aquí la versión se incrementa a mano en cada operación de la raíz; con SQL Server, una columna `rowversion` marcada con `[Timestamp]` la gestiona el motor. Quien captura la excepción decide: reintentar (recargar y reaplicar) o devolver el conflicto a quien llama.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Cargar un pedido tarda segundos y trae medio modelo | El agregado navega a otros agregados por objeto en lugar de por id |
| Una regla del pedido se cumple en la API pero no en un proceso por lotes | Setters públicos en la raíz (o en la línea): la regla se repite en cada llamador en vez de vivir en la raíz |
| Aparecen líneas que no pasaron por `AñadirLinea` | La colección se expone como `List<T>` o como `IReadOnlyList<T>` sin envolver, y se convierte con un *cast* |
| Conflictos de concurrencia frecuentes en operaciones sin relación | Agregado demasiado grande: la versión es una para todo el conjunto |
| Dos agregados que «siempre deben guardarse juntos» | O el límite está mal puesto (son uno), o falta aceptar consistencia eventual con un evento |
| Una clase de agregado por tabla, con todas las tablas relacionadas apuntándose | El agregado se ha diseñado desde el esquema de base de datos y no desde las invariantes |

## Buenas prácticas avanzadas

- **Diseña el agregado desde sus invariantes, no desde las tablas** — pregunta qué reglas deben cumplirse al instante y agrupa solo lo que participa en ellas. Un agregado puede mapearse a varias tablas (`Pedidos` y `LineasPedido`) y una tabla puede no corresponder a ningún agregado.
- **Una transacción modifica un único agregado** — si un caso de uso parece necesitar dos, o el límite está mal puesto, o debe aceptarse consistencia eventual con un [evento de dominio](Domain-Events.md); ampliar el agregado para abarcarlos es la salida cara.
- **Expón la colección interna con `AsReadOnly()`** — `IReadOnlyList<T> Lineas => _lineas` a secas se puede convertir de vuelta a `List<T>`; la vista de solo lectura no.
- **Haz internos los constructores de las entidades internas** — `LineaPedido` con constructor `internal` impide crear líneas sin pasar por la raíz.
- **Deja el token de versión solo en la raíz** — una versión por agregado, no por entidad interna: el agregado entero es la unidad de conflicto.
- **Carga el agregado entero o no lo cargues para modificarlo** — modificar un agregado cargado a medias (líneas sin traer) puede dejar una invariante evaluada sobre datos incompletos; las consultas parciales son para lectura y van por proyecciones.

## Documentación oficial

- [Martin Fowler, «DDD_Aggregate»](https://martinfowler.com/bliki/DDD_Aggregate.html) — la definición breve del patrón y la idea de la raíz como único punto de acceso; para repasar el concepto en dos minutos.
- [Vaughn Vernon, «Effective Aggregate Design»](https://www.dddcommunity.org/library/vernon_2011/) — tres artículos sobre cómo dimensionar agregados, referenciar por identidad y aceptar consistencia eventual; consultar al decidir dónde poner el límite.
- [Concurrencia optimista en EF Core](https://learn.microsoft.com/es-es/ef/core/saving/concurrency) — tokens de concurrencia, `rowversion` y cómo resolver un `DbUpdateConcurrencyException`.

---

*En resumen: una entidad se reconoce por su identidad; un agregado es la frontera pequeña dentro de la cual las reglas siempre se cumplen y cuya raíz es la única puerta de entrada, y entre agregados se referencia por id y se acepta consistencia eventual.*
