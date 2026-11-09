# Casos de Uso

## ¿Qué es?

Un caso de uso es una clase de la capa de aplicación que representa **una acción concreta que la aplicación sabe hacer** («confirmar un pedido», «cancelar un pedido») y que **orquesta** sus pasos: cargar datos, invocar las reglas del dominio, hablar con el exterior a través de interfaces, guardar y devolver un desenlace. Una acción, una clase, un método `Ejecutar`.

## ¿Por qué existe?

En una tienda online, confirmar el pedido #4711 no es una sola cosa: hay que leerlo, comprobar que se puede confirmar, cobrar, guardarlo como pagado y avisar al cliente. Las reglas («un pedido sin líneas no se confirma») viven en el dominio, pero alguien tiene que decidir **el orden y la coordinación** de esos pasos. Sin un lugar propio para ello, esa coordinación acaba en uno de dos sitios malos:

```csharp
// ❌ Controlador gordo: la acción está atrapada en el framework
[HttpPost("pedidos/{id}/confirmar")]
public async Task<IActionResult> Confirmar(int id, [FromBody] DatosPago datos)
{
    var pedido = await _db.Pedidos.Include(p => p.Lineas).FirstOrDefaultAsync(p => p.Id == id);
    if (pedido is null) return NotFound();
    if (pedido.Lineas.Count == 0) return BadRequest("Pedido vacío");   // regla de negocio en el controlador
    await _stripe.CrearCargo(pedido.Total, datos.Token);               // tecnología concreta
    pedido.Estado = "Pagado";
    await _db.SaveChangesAsync();
    return Ok();
}
```

Para probar esa acción hace falta levantar HTTP, base de datos y Stripe; para lanzarla desde otro sitio (un proceso por lotes, un mensaje de una cola) hay que copiarla. El otro mal sitio es el **servicio de aplicación gigante**: un `ServicioPedidos` con `Confirmar`, `Cancelar`, `AñadirLinea`, `AplicarDescuento`... que crece sin límite, acumula quince dependencias en el constructor y obliga a que cada test las simule todas.

```csharp
// ✅ Caso de uso: una acción, dependencias solo de lo que esa acción necesita
public class ConfirmarPedido(IRepositorioPedidos pedidos, IPasarelaPago pasarela /* ... */)
{
    public Task<ConfirmarPedidoResultado> Ejecutar(ConfirmarPedidoComando comando) { /* ... */ }
}
```

> Un caso de uso es el patrón «servicio de aplicación» acotado a **una sola acción**: en lugar de un mostrador donde se atiende todo, una ventanilla por trámite. Cada ventanilla sabe qué papeles pedir y en qué orden, pero las normas (qué trámites son válidos) las dicta el reglamento, es decir, el dominio.

## ¿Cuándo y para qué se usa?

Hay un caso de uso por cada cosa que un usuario o el sistema puede pedir a la aplicación y que **cambia estado o coordina varios colaboradores**: `ConfirmarPedido`, `CancelarPedido`. Es el punto de entrada a la lógica: la capa web recibe la petición HTTP, la traduce a un comando, llama a `Ejecutar` y traduce el resultado de vuelta. El caso de uso no sabe que vino de la web; el mismo sirve a un endpoint, a un consumidor de mensajes o a un test.

Dónde encaja respecto a las demás piezas: el dominio ([Capa de Dominio](Capa-de-Dominio.md)) está dentro y no conoce a los casos de uso; los casos de uso están justo alrededor y solo conocen al dominio y a las interfaces; las implementaciones de esas interfaces ([Capa de Infraestructura](Capa-de-Infraestructura.md)) están fuera.

## Anatomía de un caso de uso completo

`ConfirmarPedido` en `Tienda.Aplicacion`, con las interfaces que necesita (los puertos, definidos en el centro; el motivo se explica en [Inversión de Dependencias](Inversion-de-Dependencias.md)):

```csharp
// Tienda.Aplicacion
public interface IRepositorioPedidos { Task<Pedido?> ObtenerPorId(int id); Task Guardar(Pedido pedido); }
public interface IPasarelaPago { Task<bool> Cobrar(decimal importe, string tokenTarjeta, string claveIdempotencia); }
public interface INotificador { Task PedidoConfirmado(int pedidoId); }
public interface IUnidadDeTrabajo { Task Confirmar(); }

// Entrada: un record inmutable, sin tipos de ASP.NET
public record ConfirmarPedidoComando(int PedidoId, string TokenTarjeta);

// Salida: un desenlace explícito, no una excepción ni un código HTTP
public enum ConfirmarPedidoResultado { Confirmado, YaConfirmado, NoEncontrado, NoConfirmable, PagoRechazado }

public class ConfirmarPedido(
    IRepositorioPedidos pedidos,
    IPasarelaPago pasarela,
    INotificador notificador,
    IUnidadDeTrabajo unidad)
{
    public async Task<ConfirmarPedidoResultado> Ejecutar(ConfirmarPedidoComando comando)
    {
        // 1. Cargar el agregado
        var pedido = await pedidos.ObtenerPorId(comando.PedidoId);
        if (pedido is null) return ConfirmarPedidoResultado.NoEncontrado;

        // 2. Detectar la repetición (ver «Idempotencia»)
        if (pedido.Estado == EstadoPedido.Pagado) return ConfirmarPedidoResultado.YaConfirmado;

        // 3. Preguntar al dominio si la regla lo permite
        if (!pedido.PuedeConfirmarse) return ConfirmarPedidoResultado.NoConfirmable;

        // 4. Cobrar a través del puerto
        var cobrado = await pasarela.Cobrar(pedido.Total, comando.TokenTarjeta, $"pedido-{pedido.Id}");
        if (!cobrado) return ConfirmarPedidoResultado.PagoRechazado;

        // 5. Aplicar el cambio de estado (la entidad vuelve a validar la regla) y guardar
        pedido.MarcarPagado();
        await pedidos.Guardar(pedido);
        await unidad.Confirmar();

        // 6. Avisar, ya con el pedido guardado
        await notificador.PedidoConfirmado(pedido.Id);
        return ConfirmarPedidoResultado.Confirmado;
    }
}
```

La entidad que el caso de uso consulta, reducida a lo que importa aquí (cómo se protegen sus invariantes se desarrolla en [Capa de Dominio](Capa-de-Dominio.md)):

```csharp
// Tienda.Dominio
public class Pedido
{
    public int Id { get; init; }
    public List<LineaPedido> Lineas { get; } = [];
    public EstadoPedido Estado { get; private set; } = EstadoPedido.Pendiente;
    public decimal Total => Lineas.Sum(l => l.Precio * l.Cantidad);

    // La regla vive aquí: un pedido sin líneas, o ya pagado o cancelado, no se confirma
    public bool PuedeConfirmarse => Estado == EstadoPedido.Pendiente && Lineas.Count > 0;

    public void MarcarPagado()
    {
        if (!PuedeConfirmarse) throw new InvalidOperationException("El pedido no se puede confirmar.");
        Estado = EstadoPedido.Pagado;
    }
}
```

El método devuelve uno de cinco desenlaces y recorre siempre el mismo camino: cargar, descartar lo que no procede (inexistente, repetido, no confirmable), cobrar, guardar y avisar. Las salidas tempranas van **antes** del cobro: es lo que impide cobrar un pedido que luego no se puede confirmar.

El caso de uso no usa `if (pedido.Lineas.Count == 0)` por su cuenta: pregunta a `PuedeConfirmarse`. Si mañana la regla cambia (por ejemplo, un importe mínimo), cambia en `Pedido` y todos los casos de uso que la consultan se enteran.

## Qué va en el caso de uso y qué en el dominio

| Pregunta | Dónde vive | Ejemplo |
|---|---|---|
| ¿El formato de la entrada es válido? (campo vacío, longitud, tipo) | Borde: validación del comando o de la capa web, antes de `Ejecutar` | `TokenTarjeta` no es una cadena vacía |
| ¿Se permite esta operación según el negocio? | **Dominio** (la entidad) | Pedido sin líneas no se confirma; stock no negativo |
| ¿En qué orden se hacen los pasos y con qué colaboradores? | **Caso de uso** | Comprobar → cobrar → guardar → avisar |
| ¿Qué pasa si falla un colaborador? | **Caso de uso** (decide el desenlace) | `PagoRechazado` si la pasarela dice que no |
| ¿Qué código HTTP corresponde? | Capa web (adaptador) | `NoEncontrado` → 404, `PagoRechazado` → 402 |

Prueba rápida: si una regla se puede enunciar sin mencionar bases de datos, pasarelas ni notificaciones («un pedido pagado no se puede cancelar»), pertenece al dominio. Si hace falta hablar de «primero esto, luego aquello», es orquestación y pertenece al caso de uso. El mapeo del resultado a HTTP se trata en [Códigos de Resultado por Capa](Codigos-de-Resultado-por-Capa.md).

## Transacción: el caso de uso es el dueño

«Leer, confirmar, guardar» debe ser todo o nada, y quien sabe dónde empieza y acaba la acción es el caso de uso. Por eso la unidad de trabajo (`IUnidadDeTrabajo`: agrupa los cambios pendientes y los confirma de una vez) se invoca desde él, no desde dentro de cada repositorio.

El fallo que se evita, si cada repositorio hace commit por su cuenta, con un caso de uso que además descuenta stock:

```
repositorioPedidos.Guardar(pedido)      -> commit  (pedido #4711: Pagado)   OK
repositorioProductos.Guardar(producto)  -> commit  (stock: 0 -> -1)         FALLA: el stock no puede ser negativo
```

El pedido queda marcado como pagado y el stock sin descontar. Con una sola unidad de trabajo, ambos `Guardar` solo anotan los cambios y el `Confirmar()` final los persiste juntos o no persiste ninguno. Cómo implementa la infraestructura esa unidad (en EF Core, el propio `DbContext`) se cuenta en [Capa de Infraestructura](Capa-de-Infraestructura.md) y en [Repositorios](../patrones-de-diseno/Repositorios.md).

### El cobro queda fuera de la transacción

La transacción cubre la base de datos; la pasarela de pago es otro sistema y no participa en ella. De ahí un dilema sin solución perfecta:

| Orden | Si falla el segundo paso | Consecuencia |
|---|---|---|
| Cobrar y luego guardar (el del ejemplo) | El commit falla tras cobrar | Cliente cobrado y pedido sin registrar como pagado |
| Guardar y luego cobrar | El cobro falla tras guardar | Pedido «pagado» sin dinero; hay que deshacerlo |

El ejemplo elige cobrar primero porque el segundo fallo es el más raro (un commit a una base de datos sana) y el más fácil de reparar: el pedido sigue `Pendiente`, así que **reintentar es seguro** si el cobro lleva una *clave de idempotencia* (`pedido-4711`): la pasarela reconoce la clave, no vuelve a cobrar y devuelve el resultado del primer intento. Para los casos que aun así se escapen, hace falta una conciliación periódica entre cobros de la pasarela y pedidos pagados. Los patrones que evitan esa ventana por completo (estado intermedio `PagoPendiente`, *outbox*) son un tema aparte.

## Idempotencia: ejecutar dos veces no cobra dos veces

Todo caso de uso que llega por red acabará ejecutándose dos veces: doble clic, reintento tras un *timeout*, mensaje de cola entregado dos veces. El paso 2 del ejemplo es la defensa: si el pedido ya está `Pagado`, responde `YaConfirmado` sin tocar la pasarela. La respuesta distingue «lo acabo de hacer» de «ya estaba hecho», y la capa web puede tratar ambos como éxito.

Lo demuestra este test (más abajo se ve completo): confirmar dos veces el pedido #4711 produce un solo cobro y un solo commit.

```
Primera ejecución : Confirmado     (cobros: 1, commits: 1)
Segunda ejecución : YaConfirmado   (cobros: 1, commits: 1)
```

La comprobación de estado cubre las repeticiones secuenciales. Dos peticiones **simultáneas** pueden pasar ambas el paso 2 antes de que ninguna guarde: contra eso protege la clave de idempotencia de la pasarela y una restricción de concurrencia en la base de datos (versión de fila o índice único), no el `if`.

## Cómo se devuelve el desenlace

El caso de uso devuelve un valor explícito (`ConfirmarPedidoResultado`) en lugar de lanzar excepciones para lo esperable: que un pago sea rechazado o que el pedido no exista no es un error del programa, es un desenlace del negocio. Las excepciones se reservan para lo inesperado (la base de datos no responde). Si se necesita acompañar el desenlace con datos (el motivo, el importe), el patrón se generaliza en [Result Pattern](../patrones-de-diseno/Result-Pattern.md); en qué capa debe vivir cada enum de resultado y quién lo traduce a HTTP se explica en [Códigos de Resultado por Capa](Codigos-de-Resultado-por-Capa.md).

## Probar un caso de uso con fakes escritos a mano

Como `ConfirmarPedido` solo depende de interfaces, el test no necesita HTTP, base de datos ni red. Un *fake* es una implementación mínima de la interfaz hecha para el test, que apunta lo que recibe:

```csharp
public class RepositorioEnMemoria : IRepositorioPedidos
{
    public Dictionary<int, Pedido> Datos { get; } = [];
    public Task<Pedido?> ObtenerPorId(int id) => Task.FromResult(Datos.GetValueOrDefault(id));
    public Task Guardar(Pedido p) { Datos[p.Id] = p; return Task.CompletedTask; }
}

public class PasarelaFalsa(bool acepta = true) : IPasarelaPago
{
    public List<(decimal Importe, string Clave)> Cobros { get; } = [];
    public Task<bool> Cobrar(decimal importe, string token, string clave)
    { Cobros.Add((importe, clave)); return Task.FromResult(acepta); }
}

public class NotificadorFalso : INotificador
{
    public List<int> Avisos { get; } = [];
    public Task PedidoConfirmado(int id) { Avisos.Add(id); return Task.CompletedTask; }
}

public class UnidadDeTrabajoFalsa : IUnidadDeTrabajo
{
    public int Commits { get; private set; }
    public Task Confirmar() { Commits++; return Task.CompletedTask; }
}

public class ConfirmarPedidoTests
{
    readonly RepositorioEnMemoria repo = new();
    readonly PasarelaFalsa pasarela = new();
    readonly NotificadorFalso notificador = new();
    readonly UnidadDeTrabajoFalsa unidad = new();
    ConfirmarPedido Caso() => new(repo, pasarela, notificador, unidad);

    Pedido PedidoConLineas()
    {
        var pedido = new Pedido { Id = 4711 };
        pedido.Lineas.Add(new LineaPedido { ProductoId = 10, Precio = 25m, Cantidad = 2 });
        repo.Datos[pedido.Id] = pedido;
        return pedido;
    }

    [Fact]
    public async Task Confirma_cobra_guarda_y_avisa()
    {
        var pedido = PedidoConLineas();

        var resultado = await Caso().Ejecutar(new(4711, "tok_visa"));

        Assert.Equal(ConfirmarPedidoResultado.Confirmado, resultado);
        Assert.Equal(EstadoPedido.Pagado, pedido.Estado);
        Assert.Equal(50m, Assert.Single(pasarela.Cobros).Importe);   // 2 x 25
        Assert.Equal(1, unidad.Commits);
        Assert.Equal([4711], notificador.Avisos);
    }

    [Fact]
    public async Task Pedido_sin_lineas_no_cobra()
    {
        repo.Datos[4711] = new Pedido { Id = 4711 };

        var resultado = await Caso().Ejecutar(new(4711, "tok_visa"));

        Assert.Equal(ConfirmarPedidoResultado.NoConfirmable, resultado);
        Assert.Empty(pasarela.Cobros);
        Assert.Equal(0, unidad.Commits);
    }

    [Fact]
    public async Task Segunda_ejecucion_no_cobra_de_nuevo()
    {
        PedidoConLineas();
        var caso = Caso();

        var primera = await caso.Ejecutar(new(4711, "tok_visa"));
        var segunda = await caso.Ejecutar(new(4711, "tok_visa"));

        Assert.Equal(ConfirmarPedidoResultado.Confirmado, primera);
        Assert.Equal(ConfirmarPedidoResultado.YaConfirmado, segunda);
        Assert.Single(pasarela.Cobros);
        Assert.Equal(1, unidad.Commits);
    }
}
```

Los tres tests pasan (verificados con xunit en .NET 10) y tardan milisegundos. Lo que se comprueba no es la regla interna de `Pedido` (eso se prueba en sus propios tests), sino la **orquestación**: que no se cobra cuando no procede, que se guarda una sola vez y que la repetición no tiene efectos. Un fake de diez líneas suele ser más legible que una librería de *mocking* con su configuración.

## Casos de uso que se llaman entre sí

Cuando `ConfirmarPedido` llama a `EnviarConfirmacion` (otro caso de uso), nace un grafo de orquestadores que se llaman unos a otros y que nadie puede seguir: ¿qué transacción vale?, ¿qué pasa si el segundo falla?, ¿quién devuelve el resultado? Hay dos salidas según el motivo:

| Situación | Qué hacer |
|---|---|
| Dos casos de uso comparten pasos o una regla (calcular el total con descuentos) | Extraer ese cálculo a un **servicio de dominio** o a la entidad, y que ambos lo usen |
| Un caso de uso debe «enterarse» de lo que hizo otro (enviar el correo al confirmar) | Que la entidad registre un **evento de dominio** (`PedidoConfirmado`) y un manejador reaccione; ver [Domain Events](../patrones-de-diseno/Domain-Events.md) |

Llamar a un puerto (`INotificador`) desde un caso de uso es normal; llamar a otro caso de uso, no.

## Lo transversal: decoradores y pipeline

Logging, validación del comando, transacción y métricas copiados a mano en cada caso de uso acaban desincronizados. Como todos tienen la misma forma (una clase, un método `Ejecutar`), se pueden envolver con un [decorador](../patrones-de-diseno/Decorator.md) que añada la preocupación y delegue en el caso de uso real. Con MediatR, los *behaviors* de su pipeline hacen exactamente eso sin escribir cada decorador (ver [MediatR](../patrones-de-diseno/MediatR.md)). Es una comodidad, no un requisito: un caso de uso es una clase normal con o sin MediatR.

## Cuándo NO merece un caso de uso

- **Lecturas y consultas simples** («dame el pedido #4711 para mostrarlo»): no hay regla que aplicar ni estado que cambiar ni transacción que proteger. Un caso de uso que solo hace `return repositorio.ObtenerPorId(id)` es una capa de ceremonia; una consulta directa a un lector de solo lectura (que devuelva el DTO ya montado) es más simple y más rápida.
- **Operaciones CRUD sin lógica** (un catálogo de categorías que solo se edita): lo que haría el caso de uso es copiar campos de un lado a otro.
- **Cuando aparezca lógica**, sí: una consulta que empieza a filtrar según permisos o a combinar fuentes es candidata a pasar a caso de uso o a un objeto de consulta propio.

Síntoma de que falta el caso de uso: la misma secuencia de pasos aparece en dos controladores. Síntoma de que sobra: un método `Ejecutar` de una línea que reenvía a otro.

## Buenas prácticas avanzadas

- **Haz que el cobro lleve clave de idempotencia derivada del negocio**, no aleatoria: `pedido-4711` es estable entre reintentos, un GUID nuevo en cada intento anula la protección. Es lo que convierte un reintento tras un fallo de commit en una operación segura.
- **Pon las salidas tempranas antes de cualquier efecto externo.** El orden «comprobar, cobrar, guardar, avisar» no es estético: todo lo que puede rechazar la operación va antes del cobro, y todo lo que no debe ocurrir si el guardado falla (el aviso) va después del commit.
- **Notifica después del commit, no antes.** Un correo de «pedido confirmado» enviado antes de confirmar la transacción se queda enviado aunque el guardado falle. Si el aviso no puede perderse, no lo envíes en línea: guarda un evento y envíalo desde un proceso aparte.
- **Un comando por caso de uso, inmutable y sin tipos de framework.** Un `record` como `ConfirmarPedidoComando` no arrastra `HttpContext`, ni atributos de binding, ni entidades; así el mismo caso de uso se llama igual desde un endpoint, un consumidor de mensajes o un test.
- **Vigila el constructor.** Más de cuatro o cinco dependencias suele indicar que el caso de uso hace dos cosas (o que una regla de negocio se ha quedado fuera del dominio y obliga a coordinar demasiado). Es el servicio gigante reapareciendo en pequeño.
- **Devuelve desenlaces del negocio, no excepciones para lo esperable.** Un pago rechazado es un resultado; un pedido inexistente, también. Una excepción debe significar «algo se ha roto», y así los registros de errores no se llenan de rechazos normales.

## Documentación oficial

- [The Clean Architecture (Robert C. Martin)](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html) — el artículo original; interesa el apartado *Use Cases*, que define su papel entre las entidades y los adaptadores.
- [Idempotent requests (Stripe)](https://docs.stripe.com/api/idempotent_requests) — cómo una pasarela real implementa las claves de idempotencia; léelo antes de diseñar el paso de cobro.

## Recursos didácticos

- [Wiki de MediatR](https://github.com/jbogard/MediatR/wiki) — ejemplos de *behaviors* de pipeline para transacción, validación y logging si decides centralizar lo transversal.

---

*En resumen: un caso de uso es la ventanilla de una sola acción: comprueba, cobra, guarda y avisa en el orden correcto, es dueño de la transacción y aguanta que le pidan lo mismo dos veces; las reglas las pone el dominio.*
