# Repositorios

## ¿Qué es?

Un repositorio es la abstracción que permite cargar y guardar [agregados](Entidades-y-Agregados.md) como si fueran una colección en memoria: se pide un `Pedido`, se modifica y se devuelve, sin que quien lo hace sepa si por debajo hay SQL, un fichero o un diccionario. Su contrato se escribe con el vocabulario del negocio, no con el de la base de datos.

## ¿Por qué existe?

Un caso de uso como `ConfirmarPedido` necesita recuperar el pedido #4711 con todas sus líneas, aplicarle una regla y dejarlo guardado. Si para eso escribe consultas, `Include` y `SaveChanges`, el caso de uso queda atado al ORM, no se puede probar sin base de datos y cada consulta repetida en un sitio distinto es una versión más de «qué significa pendiente de envío».

El repositorio concentra ese acceso detrás de una interfaz pequeña con nombres de negocio. Para el caso de uso, el almacén es una colección: `ObtenerPorId`, cambiar, `Guardar`.

> Es el mostrador de una biblioteca: se pide «el libro con este código» y se entrega, sin saber en qué estantería está ni cómo está catalogado por dentro. Tampoco se pide «dame acceso al almacén para que busque yo»: se pregunta al bibliotecario, que conoce el catálogo.

## ¿Cuándo y para qué se usa?

Siempre que un caso de uso necesita recuperar o guardar un agregado completo: el `Pedido` con sus líneas, el `Producto` tras descontar stock. Es la mitad de escritura del acceso a datos: carga el agregado entero para que su raíz haga cumplir las reglas y lo persiste entero.

En esta colección el contrato `IRepositorioPedidos` vive en `Tienda.Aplicacion` y su implementación en `Tienda.Infraestructura`. En el DDD clásico la interfaz se sitúa en el dominio; es equivalente, porque ambos proyectos forman el centro de la aplicación y lo que importa es que la interfaz esté en el lado interior de la dependencia y la implementación en el exterior. El vocabulario de puerto y adaptador está en [Puertos y Adaptadores](../clean-architecture/Puertos-y-Adaptadores.md): un repositorio es un puerto de salida. La implementación completa con EF Core (mapeo, concurrencia, excepciones) está en [Capa de Infraestructura](../clean-architecture/Capa-de-Infraestructura.md) y no se repite aquí.

## El contrato de un repositorio

El contrato de un repositorio de pedidos recoge lo que el negocio pregunta sobre pedidos:

```csharp
// Tienda.Aplicacion
public interface IRepositorioPedidos
{
    Task<Pedido?> ObtenerPorId(IdPedido id, CancellationToken ct);
    Task<IReadOnlyList<Pedido>> ObtenerPendientesDeEnvio(CancellationToken ct);
    Task Guardar(Pedido pedido, CancellationToken ct);
}
```

- `ObtenerPorId` devuelve el `Pedido` completo, con sus líneas, o `null`.
- `ObtenerPendientesDeEnvio` es una pregunta del negocio con nombre propio: «pagados y sin enviar» se define en un único sitio.
- `Guardar` persiste el agregado, nuevo o modificado.

### Genérico con `IQueryable`: la tentación

Parece más económico un contrato único para todas las entidades:

```csharp
// ❌ Repositorio genérico que deja componer la consulta desde fuera
public interface IRepositorio<T> where T : class
{
    IQueryable<T> Consultar();
    IEnumerable<T> Find(Expression<Func<T, bool>> filtro);
}
```

El peligro se ve con una tabla de 5000 pedidos, 50 de ellos pagados y sin enviar, y una regla del dominio escrita como método (`Pedido.PendienteDeEnvio()`). Un llamador reutiliza esa regla componiendo la consulta:

```csharp
repo.Consultar().Where(p => p.PendienteDeEnvio()).ToList();
```

EF Core no sabe traducir a SQL un método C# arbitrario y lanza:

```
InvalidOperationException: The LINQ expression 'DbSet<Pedido>()
    .Where(p => p.PendienteDeEnvio())' could not be translated.
```

El arreglo «que funciona» es insertar `AsEnumerable()` antes del `Where`: la consulta se ejecuta, devuelve los 50 pedidos correctos y **la base de datos recibe `SELECT ... FROM "Pedidos"` sin ningún `WHERE`**, es decir, las 5000 filas viajan a memoria para quedarse con 50. Con cien mil pedidos nadie lo nota hasta producción. Nada de esto es culpa del llamador: el contrato le permitió escribir una consulta que solo el adaptador sabe ejecutar bien.

Con el contrato específico, la consulta vive en el adaptador, donde se conoce el motor:

```csharp
// ✅ Tienda.Infraestructura: la consulta la escribe quien conoce el SQL
public async Task<IReadOnlyList<Pedido>> ObtenerPendientesDeEnvio(CancellationToken ct) =>
    await db.Pedidos
        .Include(p => p.Lineas)
        .Where(p => p.Estado == EstadoPedido.Pagado && p.EnviadoEn == null)
        .ToListAsync(ct);
```

Comprobado con SQLite en memoria y EF Core 10, el SQL enviado es:

```
SELECT "p"."Id", "p"."EnviadoEn", "p"."Estado"
FROM "Pedidos" AS "p"
WHERE "p"."Estado" = 'Pagado' AND "p"."EnviadoEn" IS NULL
```

(El ejemplo de prueba omitía las líneas para simplificar; con `Include` la consulta añade el `JOIN` correspondiente.) Hay un segundo beneficio: el contrato ya no depende de EF. Un diccionario en memoria puede implementar `ObtenerPendientesDeEnvio`; no puede implementar `IQueryable` con la misma semántica, porque `Expression` y `IQueryable` significan «el proveedor que haya detrás traduce esto», y cada proveedor traduce un subconjunto distinto.

Lo que se escribe a mano al no ser genérico es un método más por cada pregunta de negocio. Es un coste buscado: cada método es una pregunta que el negocio hace, con nombre, y que se puede probar.

## Un repositorio por raíz de agregado

El repositorio se corresponde con el agregado, no con la tabla. `LineaPedido` tiene su propia tabla, pero no es una raíz: solo existe dentro de un `Pedido` y se modifica a través de él (`pedido.AñadirLinea(...)`). Por eso no hay `IRepositorioLineasPedido`.

| Concepto | ¿Tiene repositorio? | Motivo |
|---|---|---|
| `Pedido` (con `LineaPedido`) | Sí: `IRepositorioPedidos` | Raíz del agregado; las líneas viajan con él |
| `LineaPedido` | No | Parte interna del agregado: sin raíz, nadie garantiza «un pedido pagado no se modifica» |
| `Producto` | Sí: `IRepositorioProductos` | Raíz propia: el stock tiene su regla («no puede ser negativo») y su ciclo de vida |
| `Cliente` | Sí: `IRepositorioClientes` | Raíz propia; el pedido solo guarda su `IdCliente` |
| Tabla de países, estados de pedido | No | Datos de referencia sin reglas: una consulta de lectura basta |

Un `Pedido` guarda el `IdCliente`, no un `Cliente`. Un repositorio que cargara el cliente «de propina» con cada pedido mezclaría dos agregados en una carga y, por extensión, en una transacción. Qué es un agregado y cómo se dibuja su límite está en [Entidades y Agregados](Entidades-y-Agregados.md).

## Qué métodos tiene y cuáles no

El repertorio mínimo imita el de una colección:

| Método | Cuándo |
|---|---|
| `ObtenerPorId` | Siempre: es la carga del agregado para modificarlo |
| `Guardar` (o `Añadir` si se separan inserción y actualización) | Siempre |
| `Eliminar` | Solo si el negocio borra de verdad; muchos agregados se «cancelan» (estado) en lugar de borrarse |
| `ObtenerXxx` con nombre de negocio (`ObtenerPendientesDeEnvio`) | Cuando el negocio necesita encontrar agregados por una condición que no es la identidad |

Lo que **no** es un repositorio:

- **No es la unidad de trabajo.** `Guardar` registra el cambio del agregado, pero el commit de la transacción que cubre varios cambios (guardar el pedido y descontar stock, por ejemplo) lo decide el caso de uso. Si cada `Guardar` hace su propio commit, un fallo a mitad de operación deja datos a medias. Quién abre y cierra la transacción se explica en [Casos de Uso](../clean-architecture/Casos-de-Uso.md). Con EF Core esto se resuelve de forma natural: el `DbContext` es la unidad de trabajo, y un único `SaveChanges` al final del caso de uso persiste todo lo que han tocado los repositorios que comparten ese contexto.
- **No es un servicio de listados.** No sirve filas para pantallas (ver siguiente sección).
- **No contiene reglas de negocio.** Decidir si un pedido se puede cancelar es de `Pedido`; el repositorio solo lo carga y lo guarda.

## Lectura y escritura por separado

El repositorio carga el agregado completo porque va a ejecutar sus reglas. Para pintar un listado esa carga es un desperdicio: se materializan líneas, objetos de valor e invariantes que nadie va a usar. Los listados y las pantallas de consulta se resuelven con una **consulta de solo lectura** que devuelve un DTO ya con la forma de lo que se muestra, sin pasar por el repositorio.

```csharp
public record ResumenPedido(int Id, string Estado, int NumeroLineas, decimal Total);
```

Con EF Core, proyectando en la propia consulta para que el SQL solo pida esas columnas:

```csharp
public async Task<IReadOnlyList<ResumenPedido>> ListarResumenes(int clienteId, CancellationToken ct) =>
    await db.Pedidos
        .AsNoTracking()
        .Where(p => p.ClienteId == new IdCliente(clienteId))
        .Select(p => new ResumenPedido(
            p.Id.Valor, p.Estado.ToString(), p.Lineas.Count, p.Lineas.Sum(l => l.Cantidad * l.PrecioUnitario.Importe)))
        .ToListAsync(ct);
```

O con SQL directo, si el listado es complejo o crítico en rendimiento:

```csharp
const string sql = """
    SELECT p.Id, p.Estado, COUNT(l.Id) AS NumeroLineas, SUM(l.Cantidad * l.PrecioUnitario) AS Total
    FROM Pedidos p LEFT JOIN LineasPedido l ON l.PedidoId = p.Id
    WHERE p.ClienteId = @clienteId
    GROUP BY p.Id, p.Estado
    """;
var resumenes = (await conexion.QueryAsync<ResumenPedido>(sql, new { clienteId })).ToList();
```

La consulta de lectura se declara como su propia interfaz en `Tienda.Aplicacion` (por ejemplo, `IConsultasPedidos`), separada de `IRepositorioPedidos`: una no puede usarse para saltarse las reglas de la otra. Los detalles de cada herramienta están en [Entity Framework Core](../../bases-de-datos/acceso-a-datos-dotnet/Entity-Framework-Core.md) y [Dapper](../../bases-de-datos/acceso-a-datos-dotnet/Dapper.md). Esta separación es la versión más ligera de lo que se conoce como CQRS (separar el modelo con el que se escribe del modelo con el que se lee), sin necesidad de bases de datos distintas ni de mensajería.

## Una versión en memoria para las pruebas

Al ser el contrato una colección, una implementación con un diccionario basta para probar los casos de uso sin base de datos:

```csharp
// Tienda.Aplicacion.Tests
public class RepositorioPedidosEnMemoria : IRepositorioPedidos
{
    private readonly Dictionary<IdPedido, Pedido> _pedidos = [];

    public Task<Pedido?> ObtenerPorId(IdPedido id, CancellationToken ct) =>
        Task.FromResult(_pedidos.GetValueOrDefault(id));

    public Task<IReadOnlyList<Pedido>> ObtenerPendientesDeEnvio(CancellationToken ct) =>
        Task.FromResult<IReadOnlyList<Pedido>>(
            _pedidos.Values.Where(p => p.Estado == EstadoPedido.Pagado && p.EnviadoEn is null).ToList());

    public Task Guardar(Pedido pedido, CancellationToken ct)
    {
        _pedidos[pedido.Id] = pedido;
        return Task.CompletedTask;
    }
}
```

Comprobado con un programa de prueba: guardar un pedido pagado y sin enviar y llamar a `ObtenerPendientesDeEnvio` lo devuelve, igual que el adaptador SQL.

Un fake solo sirve si se comporta como el adaptador real en lo que el caso de uso observa. Aquí hay un riesgo concreto: este fake guarda la referencia del objeto, mientras que una base de datos devuelve siempre una copia. Un test que modifica el pedido sin llamar a `Guardar` pasaría con el fake y fallaría en producción. La defensa es una suite de pruebas escrita contra la interfaz y ejecutada contra ambos adaptadores (*contract tests*), con un ejemplo completo en [Puertos y Adaptadores](../clean-architecture/Puertos-y-Adaptadores.md). El adaptador real se prueba contra un motor real, no con un `DbContext` simulado, como se detalla en [Capa de Infraestructura](../clean-architecture/Capa-de-Infraestructura.md).

## ¿Repositorio o `DbContext` directo?

EF Core ya implementa por dentro dos patrones: `DbSet<T>` hace de repositorio y `DbContext` de unidad de trabajo. Poner un repositorio encima no siempre aporta algo.

| Situación | Decisión |
|---|---|
| Dominio rico, con agregados y reglas que se rompen con facilidad; casos de uso que se quieren probar sin base de datos | Repositorio por agregado: el caso de uso depende de una interfaz del centro |
| El mismo agregado se persiste en más de un almacén o puede cambiar de motor | Repositorio: es el punto de sustitución |
| Consultas con nombre de negocio que se reutilizan en varios casos de uso | Repositorio: la definición vive en un único sitio |
| Aplicación de CRUD sin reglas entre campos | `DbContext` directo en el endpoint o en un servicio: un repositorio solo reenvía llamadas |
| Listados y pantallas de consulta | Consulta de lectura (EF con proyección o Dapper), sin repositorio |
| Un único proyecto, sin capas, con pruebas contra una base de datos real | `DbContext` directo es suficiente; el repositorio solo añade código |
| «Para poder cambiar de ORM algún día» sin motivo concreto | No justifica el repositorio por sí solo; ese cambio casi nunca ocurre y, cuando ocurre, el contrato rara vez sobrevive intacto |

Un repositorio que solo envuelve `db.Set<T>().Find(id)`, `Add` y `SaveChanges` es una capa sin valor: añade indirección, no abstrae nada y duplica lo que EF ya ofrece. Gana su sitio cuando expresa preguntas del negocio, protege la frontera del agregado o permite sustituir el almacén.

## Especificaciones

Cuando las consultas son muchas y combinables (filtrar por estado, por cliente, por rango de fechas, en cualquier mezcla), el patrón *Specification* encapsula cada condición en un objeto que el repositorio sabe ejecutar (`repositorio.Buscar(new PedidosPagadosSinEnviar())`). Permite consultas componibles sin exponer `IQueryable` al centro; a cambio, añade un tipo por condición y un intérprete en el adaptador, así que solo compensa cuando la combinatoria de filtros es real.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Los llamadores encadenan `.Where` y `.Include` sobre lo que devuelve el repositorio; aparecen errores «no se puede traducir» o consultas sin `WHERE` | **Repositorio genérico que expone `IQueryable` o `Find(Expression)`**: la consulta se compone fuera del adaptador. Un método por pregunta de negocio |
| El repositorio devuelve `ResumenPedido` o un DTO con columnas de pantalla, y cada cambio de la pantalla obliga a tocarlo | **Métodos que devuelven DTO de pantalla**: mezcla lectura y escritura. El repositorio devuelve agregados; los listados, consultas de lectura aparte |
| Un fallo a mitad de una operación deja el pedido guardado pero el stock sin descontar | **`Guardar` que hace commit**: cada llamada confirma su propia transacción. Un único commit al final del caso de uso |
| Cargar un pedido lanza consultas de más sobre `Cliente` o histórico de pedidos | **Carga perezosa que cruza agregados**: el ORM navega de un agregado a otro. Guardar solo el `IdCliente` en el pedido y cargar explícitamente lo que el agregado necesita |
| El repositorio tiene `ObtenerPorEstado`, `ObtenerPorClienteYEstado`, `ObtenerPorFechaYCliente`... | **Un método por cada filtro posible**: se reintroduce el filtro libre con más pasos. Se dejan los métodos que el negocio usa; si la combinatoria es real, una especificación |
| Existe `IRepositorioLineasPedido` y las líneas se modifican sin pasar por el pedido | **Repositorio por tabla**: se saltan las invariantes de la raíz. Un repositorio por raíz de agregado |
| Los tests del caso de uso pasan con el fake y en producción falta un guardado | **Fake sin contrato**: devuelve la misma referencia en lugar de una copia. Suite de contrato contra ambas implementaciones |

## Buenas prácticas avanzadas

- **Evita `IRepositorio<T>` y su `IQueryable`.** Un contrato por agregado con métodos de negocio (`ObtenerPendientesDeEnvio`) protege la frontera aunque haya que escribir más código. Si se quiere reutilizar código de infraestructura, una clase base interna del adaptador (no del contrato) comparte la mecánica sin filtrarla al centro.
- **El repositorio participa en la transacción, no la dirige.** `Guardar` marca los cambios; el caso de uso decide cuándo confirmar, y con EF Core lo normal es un único `SaveChanges` al final. Un `Guardar` que confirma por su cuenta rompe la atomicidad de operaciones que tocan varios agregados.
- **Carga el agregado entero o no lo cargues.** `ObtenerPorId` devuelve el `Pedido` con todas sus líneas, no una versión parcial con las invariantes sin comprobar. Para mostrar datos, consulta de lectura.
- **Prueba cada pregunta con casos que deben quedar fuera.** Un test de `ObtenerPendientesDeEnvio` guarda un pedido pagado, otro sin pagar y otro ya enviado, y comprueba que vuelve solo el primero. Esa prueba debe pasar con el fake y con el adaptador real.
- **Pasa `CancellationToken` hasta la base de datos.** Si la petición se cancela, no hay motivo para seguir leyendo ni escribiendo.
- **Devuelve `null` para «no existe», no una excepción.** Que un pedido no exista es un desenlace normal; el caso de uso lo traduce a `ConfirmarPedidoResultado.PedidoNoEncontrado`, no a un `catch`.

## Documentación oficial

- [Repository (Martin Fowler, Patterns of Enterprise Application Architecture)](https://martinfowler.com/eaaCatalog/repository.html) — la definición canónica del patrón: la colección en memoria sobre una capa de mapeo. Ir para ver el origen de la analogía.
- [Diseñar la capa de persistencia de infraestructura (Microsoft)](https://learn.microsoft.com/es-es/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/infrastructure-persistence-layer-design) — repositorio por agregado en .NET, y por qué no uno por tabla. Ir al decidir el contrato.
- [Specification pattern (Martin Fowler)](https://martinfowler.com/apsupp/spec.pdf) — el artículo original de Evans y Fowler sobre las especificaciones. Ir solo si las consultas combinables se vuelven un problema real.

---

*En resumen: el repositorio es una colección de agregados con preguntas de negocio, uno por raíz y sin `IQueryable`; carga y guarda, pero ni decide la transacción ni sirve las pantallas.*
