# Domain Events

## ¿Qué es?

Un evento de dominio es un objeto inmutable que describe **algo que ya ha ocurrido** en el negocio y que puede interesar a otras partes del sistema: `PedidoConfirmado`, `StockAgotado`, `ClienteRegistrado`. Se nombra en pasado porque es un hecho consumado, no una orden.

## ¿Por qué existe?

Confirmar el pedido #4711 implica avisar al cliente, descontar stock y emitir la factura. La tentación es meter las tres llamadas dentro de `ConfirmarPedido`. Cada nuevo interesado (auditoría, puntos de fidelidad, un aviso al almacén) obliga a abrir ese caso de uso, y «confirmar un pedido» acaba conociendo cómo se envía un correo, cómo se factura y cómo se mueve el stock.

> Es la diferencia entre quien grita «¡pedido listo!» en una cocina y quien va avisando mesa por mesa. Quien grita no sabe quién escucha ni cuántos son; si mañana se suma otra persona al equipo, el grito no cambia.

Un evento invierte la relación: el agregado anuncia el hecho y cada interesado reacciona por su cuenta. Quien genera el evento no sabe quién escucha.

## ¿Cuándo y para qué se usa?

Cuando un hecho de negocio interesa a más de una parte y el resto de efectos no son el motivo de la operación: un pedido confirmado dispara correo, stock y factura; un cliente registrado dispara bienvenida y configuración por defecto. Dentro de un solo proceso es un evento de dominio; si el hecho tiene que salir hacia otro módulo o servicio, se habla de evento de integración (ver la siguiente sección).

## Evento, comando y evento de integración

| | Evento de dominio | Comando | Evento de integración |
|---|---|---|---|
| Qué expresa | Un hecho que ya ocurrió | Una intención | Un hecho, publicado para otros procesos o módulos |
| Tiempo verbal | Pasado: `PedidoConfirmado` | Imperativo: `ConfirmarPedido` | Pasado: `PedidoConfirmado` |
| ¿Puede rechazarse? | No: ya ocurrió | Sí: puede incumplir una regla | No |
| Destinatarios | Cero, uno o varios; el emisor no los conoce | Uno, el que lo ejecuta | Otros módulos o servicios |
| Alcance | Dentro del proceso | Dentro del proceso | Cruza fronteras: se serializa y se versiona como contrato |
| Ejemplo | `PedidoConfirmado` con tipos del dominio (`IdPedido`) | `ConfirmarPedido(IdPedido)` | `PedidoConfirmado` con tipos primitivos (`int PedidoId`) |

Con frecuencia el evento de integración es el de dominio traducido a un contrato estable. Cómo se publica entre módulos de una misma aplicación está en [Módulos frente a Shared](../clean-architecture/Modulos-vs-Shared.md).

## Del acoplamiento al evento

Sin eventos, el caso de uso conoce a todos los interesados:

```csharp
// ❌ ConfirmarPedido conoce cada efecto secundario
public class ConfirmarPedido(IRepositorioPedidos repositorio, INotificador notificador,
                             IServicioStock stock, IServicioFacturacion facturacion)
{
    public async Task Ejecutar(IdPedido id, CancellationToken ct)
    {
        var pedido = (await repositorio.ObtenerPorId(id, ct))!;
        pedido.Confirmar(DateTimeOffset.UtcNow);
        await repositorio.Guardar(pedido, ct);

        await notificador.Enviar(pedido.ClienteId, $"Tu pedido #{id.Valor} está confirmado.");
        await stock.Descontar(pedido);
        await facturacion.Emitir(pedido);        // un efecto más = una dependencia más aquí
    }
}
```

Con eventos, el caso de uso solo orquesta lo suyo:

```csharp
// ✅ ConfirmarPedido no sabe quién reacciona
public class ConfirmarPedido(IRepositorioPedidos repositorio, IPublicadorEventos publicador, TimeProvider reloj)
{
    public async Task Ejecutar(IdPedido id, CancellationToken ct)
    {
        var pedido = (await repositorio.ObtenerPorId(id, ct))!;
        pedido.Confirmar(reloj.GetUtcNow());
        await repositorio.Guardar(pedido, ct);
        // ...despacha los eventos del pedido (se completa en la sección siguiente)
    }
}
```

Los tres efectos pasan a ser manejadores independientes de `PedidoConfirmado`. Añadir el cuarto es añadir una clase; `ConfirmarPedido` no cambia.

## El recorrido completo

Cuatro piezas: el evento, el agregado que lo registra, quien lo despacha y los manejadores.

**El evento** es un `record`: inmutable, con igualdad por valor y nombre en pasado. Los contratos `IManejadorEvento<TEvento>` e `IPublicadorEventos` son los mismos de [Módulos frente a Shared](../clean-architecture/Modulos-vs-Shared.md).

```csharp
namespace Tienda.Dominio;

public interface IEventoDominio;

public record PedidoConfirmado(IdPedido PedidoId, IdCliente ClienteId, DateTimeOffset ConfirmadoEn)
    : IEventoDominio;
```

**El agregado registra, no publica.** La raíz acumula en una lista interna los eventos que van ocurriendo; el dominio no depende de ningún bus, contenedor ni infraestructura:

```csharp
public abstract class RaizDeAgregado
{
    private readonly List<IEventoDominio> _eventos = [];
    public IReadOnlyList<IEventoDominio> EventosDominio => _eventos.AsReadOnly();
    protected void Registrar(IEventoDominio evento) => _eventos.Add(evento);
    public void LimpiarEventos() => _eventos.Clear();
}

public sealed class Pedido : RaizDeAgregado
{
    // ...identidad, líneas y resto del agregado: ver Capa de Dominio

    public void Confirmar(DateTimeOffset ahora)
    {
        if (Estado != EstadoPedido.Borrador)
            throw new ReglaDeDominioException($"Un pedido {Estado} no se puede confirmar.");
        if (_lineas.Count == 0)
            throw new ReglaDeDominioException("Un pedido sin líneas no se puede confirmar.");
        Estado = EstadoPedido.Confirmado;
        ConfirmadoEn = ahora;
        Registrar(new PedidoConfirmado(Id, ClienteId, ahora));   // se anota; nadie lo ha visto aún
    }
}
```

El resto de `Pedido` (fábrica `Pedido.Crear`, `AñadirLinea`, colección encapsulada) es el de [Capa de Dominio](../clean-architecture/Capa-de-Dominio.md); el diseño del agregado se desarrolla en [Entidades y Agregados](Entidades-y-Agregados.md). Si la regla falla, la excepción sale antes de `Registrar`: un pedido que no se confirma no deja evento.

**El caso de uso despacha después de guardar.** Los eventos salen de la raíz una vez persistido el cambio:

```csharp
public class ConfirmarPedido(IRepositorioPedidos repositorio, IPublicadorEventos publicador, TimeProvider reloj)
{
    public async Task Ejecutar(IdPedido id, CancellationToken ct)
    {
        var pedido = await repositorio.ObtenerPorId(id, ct)
            ?? throw new InvalidOperationException($"No existe el pedido {id.Valor}.");

        pedido.Confirmar(reloj.GetUtcNow());
        await repositorio.Guardar(pedido, ct);                 // 1. se persiste el hecho

        var eventos = pedido.EventosDominio.ToList();
        pedido.LimpiarEventos();
        foreach (var evento in eventos)                        // 2. se avisa después
            await publicador.Publicar((dynamic)evento, ct);
    }
}
```

`Publicar<TEvento>` resuelve `TEvento` en tiempo de compilación. Con la lista como `IEventoDominio`, buscaría manejadores de `IManejadorEvento<IEventoDominio>` y no encontraría ninguno: no falla, simplemente no avisa a nadie (comprobado: el publicador en proceso no invoca ningún manejador). `(dynamic)evento` hace que `TEvento` sea el tipo real, `PedidoConfirmado`. Una alternativa sin `dynamic` es que el publicador tenga un método no genérico que resuelva el tipo con reflexión.

**Los manejadores** reaccionan cada uno a lo suyo y no se conocen entre sí:

```csharp
public class NotificarCliente(INotificador notificador) : IManejadorEvento<PedidoConfirmado>
{
    public Task Manejar(PedidoConfirmado e, CancellationToken ct) =>
        notificador.Enviar(e.ClienteId, $"Tu pedido #{e.PedidoId.Valor} está confirmado.");
}

public class DescontarStock : IManejadorEvento<PedidoConfirmado> { /* ... */ }
public class EmitirFactura : IManejadorEvento<PedidoConfirmado> { /* ... */ }
```

Con `PublicadorEnProceso` (el de [Módulos frente a Shared](../clean-architecture/Modulos-vs-Shared.md)) y los tres manejadores registrados, confirmar el pedido #4711 produce:

```text
Correo a cliente 1: Tu pedido #4711 está confirmado.
Stock descontado para el pedido #4711
Factura emitida para el pedido #4711
```

## Cuándo se despachan los eventos

Es la decisión de diseño con más consecuencias. Hay tres momentos posibles:

| Momento | Qué garantiza | Qué puede salir mal |
|---|---|---|
| **Antes de guardar** | Nada: el hecho aún no es firme | Se reacciona a algo que luego no se persiste |
| **Dentro de la transacción**, justo antes del commit | Los manejadores que escriben en la misma base de datos se confirman o se revierten junto al agregado: consistencia inmediata | Un manejador que falla revierte la confirmación; los efectos externos (correo, llamada HTTP) no se pueden deshacer con el rollback; transacciones más largas |
| **Después del commit** | Solo se reacciona a hechos firmes | El proceso puede caer entre el commit y el despacho: el evento se pierde (se trata en la sección siguiente); la consistencia es eventual |

La regla práctica: los efectos que modifican **el mismo almacén** y deben ser atómicos con el cambio (p. ej. descontar stock en la misma base) pueden ir dentro de la transacción; los efectos hacia fuera (correos, otros servicios) van después del commit.

El fallo de despachar **antes** de guardar, con una versión del caso de uso que publica y luego guarda, y una base de datos que falla al guardar:

```text
Correo a cliente 1: Tu pedido #4711 está confirmado.
Stock descontado para el pedido #4711
Factura emitida para el pedido #4711
ERROR: Se perdió la conexión con la base de datos.
```

El cliente tiene un correo de confirmación y una factura de un pedido que en la base de datos sigue en borrador. Con el despacho después del guardado, el mismo fallo termina en `ERROR: Se perdió la conexión con la base de datos.` y nada más: ningún manejador llega a ejecutarse.

## Manejadores síncronos y asíncronos

`PublicadorEnProceso` invoca los manejadores dentro de la misma petición y espera a cada uno. Es simple, pero deja una brecha: el commit ya se hizo y el proceso puede morir antes de despachar, o un manejador puede fallar. «Guardé pero no pude publicar» deja el hecho guardado y a los interesados sin enterarse.

Cuando eso no es aceptable se usa el patrón *outbox* (bandeja de salida): en la misma transacción que guarda el pedido se inserta el evento en una tabla de la misma base de datos, y un proceso aparte lee esa tabla, publica y marca lo publicado.

```text
Pedidos                          MensajesSalida
-------                          --------------
Id            4711               Id           (auto)
Estado        Confirmado         Tipo         'PedidoConfirmado'
...                              Carga        '{"pedidoId":4711,"clienteId":1,...}'
                                 CreadoEn     2026-11-09 10:05
                                 ProcesadoEn  NULL   <- el proceso lo rellena al publicar
```

Como `Pedidos` y `MensajesSalida` se escriben en una única transacción, o están las dos filas o ninguna: no puede haber pedido confirmado sin evento pendiente ni evento de un pedido que no se guardó. El coste es que la entrega pasa a ser **al menos una vez**: si el proceso publica y cae antes de marcar `ProcesadoEn`, al reintentar publicará de nuevo. Por eso los manejadores deben ser idempotentes (sección siguiente). Esta guía no implementa el *outbox* completo (sondeo, reintentos, limpieza, concurrencia entre varias instancias); es una pieza con entidad propia.

## Idempotencia de los manejadores

Con entrega al menos una vez, o simplemente con un reintento tras un fallo parcial, un manejador puede recibir el mismo evento dos veces. Un manejador ingenuo, con el evento entregado dos veces:

```text
Correo a cliente 1: Tu pedido #4711 está confirmado.
Correo a cliente 1: Tu pedido #4711 está confirmado.
```

El cliente recibe dos correos. Un manejador idempotente comprueba si ya hizo su trabajo para ese hecho, con una clave natural (aquí, el pedido y el tipo de envío) que se registra de forma atómica:

```csharp
public class NotificarClienteIdempotente(INotificador notificador, IRegistroEnvios registro)
    : IManejadorEvento<PedidoConfirmado>
{
    public async Task Manejar(PedidoConfirmado e, CancellationToken ct)
    {
        if (!registro.IntentarRegistrar(e.PedidoId, "correo-confirmacion")) return;   // ya enviado
        await notificador.Enviar(e.ClienteId, $"Tu pedido #{e.PedidoId.Valor} está confirmado.");
    }
}
```

Con el mismo evento entregado dos veces, sale un solo correo. En producción `IntentarRegistrar` es un `INSERT` contra una restricción única (la base de datos es quien impide el duplicado, no un `if` en memoria). Un matiz: registrar antes de enviar evita el duplicado pero, si el envío falla justo después, el correo no se reintentará; registrar después reintenta pero puede duplicar si el proceso cae entre el envío y el registro. Se elige según qué sea peor: perder un correo o mandarlo dos veces.

Los eventos que pueden repetirse legítimamente para la misma entidad (p. ej. `DireccionCambiada`) necesitan un identificador propio del evento, no la clave natural.

## Qué lleva el evento

- **Nombre en pasado y del negocio**: `PedidoConfirmado`, no `PedidoActualizado` ni `ConfirmarPedido`.
- **Los datos que los manejadores necesitan, y quién y cuándo**: `PedidoId`, `ClienteId`, `ConfirmadoEn`. Con esto el manejador de correos sabe a quién escribir sin tocar la base de datos.
- **No el agregado entero**: un manejador que recibe el `Pedido` puede mutarlo y acopla a todos los consumidores a su forma interna.
- **No solo un id si obliga a todos a releer**: si cada manejador empieza con `repositorio.ObtenerPorId(e.PedidoId)` para conseguir lo que el agregado ya sabía al confirmar, se multiplican las lecturas y se lee el estado actual, no el del momento del hecho (el pedido pudo cambiar entre medias).
- **Inmutable** (un `record`) y **sin comportamiento**: es un dato, no un objeto con lógica.

## Eventos y MediatR

En .NET, [MediatR](MediatR.md) ofrece una infraestructura lista para esto: el evento implementa `INotification`, los manejadores implementan `INotificationHandler<T>` y se publican con `Publish`. La forma de las piezas es la misma que aquí.

## Probar el agregado

Que `Confirmar()` registre el evento es comportamiento del dominio y se prueba sin infraestructura, con xUnit:

```csharp
using Tienda.Dominio;

namespace Pruebas;

public class PedidoEventosTests
{
    private static readonly DateTimeOffset Ahora = new(2026, 11, 9, 10, 0, 0, TimeSpan.Zero);

    private static Pedido PedidoConUnaLinea()
    {
        var pedido = Pedido.Crear(new IdPedido(4711), new IdCliente(1), Ahora);
        pedido.AñadirLinea(new IdProducto(7), 2, Dinero.De(19.99m, "EUR"));
        return pedido;
    }

    [Fact]
    public void Confirmar_registra_PedidoConfirmado_con_los_datos_del_pedido()
    {
        var pedido = PedidoConUnaLinea();

        pedido.Confirmar(Ahora.AddMinutes(5));

        var evento = Assert.IsType<PedidoConfirmado>(Assert.Single(pedido.EventosDominio));
        Assert.Equal(new IdPedido(4711), evento.PedidoId);
        Assert.Equal(new IdCliente(1), evento.ClienteId);
        Assert.Equal(Ahora.AddMinutes(5), evento.ConfirmadoEn);
    }

    [Fact]
    public void Un_pedido_sin_lineas_no_se_confirma_y_no_registra_evento()
    {
        var pedido = Pedido.Crear(new IdPedido(4711), new IdCliente(1), Ahora);

        Assert.Throws<ReglaDeDominioException>(() => pedido.Confirmar(Ahora));

        Assert.Empty(pedido.EventosDominio);
    }

    [Fact]
    public void Confirmar_dos_veces_no_duplica_el_evento()
    {
        var pedido = PedidoConUnaLinea();
        pedido.Confirmar(Ahora);

        Assert.Throws<ReglaDeDominioException>(() => pedido.Confirmar(Ahora));

        Assert.Single(pedido.EventosDominio);
    }
}
```

```text
  Correctas Pruebas.PedidoEventosTests.Confirmar_dos_veces_no_duplica_el_evento [15 ms]
  Correctas Pruebas.PedidoEventosTests.Un_pedido_sin_lineas_no_se_confirma_y_no_registra_evento [2 ms]
  Correctas Pruebas.PedidoEventosTests.Confirmar_registra_PedidoConfirmado_con_los_datos_del_pedido [10 ms]

Correctas! - Con error:     0, Superado:     3, Omitido:     0, Total:     3
```

(La salida está en español porque el SDK usó la cultura de la máquina.) Para la prueba del despacho y de los manejadores basta un publicador y un repositorio en memoria. Sobre el ciclo de escribir primero la prueba, ver [TDD](../../testing/tdd-bdd-sdd/TDD.md).

## Cuándo no usar eventos

| Situación | Por qué un evento no encaja | Alternativa |
|---|---|---|
| Un único efecto secundario, obvio y que siempre irá junto | Un evento con un solo manejador fijo añade indirección sin desacoplar nada | Llamar directamente al puerto desde el caso de uso |
| El flujo necesita el **resultado** del otro lado (¿hay stock? ¿se aprobó el pago?) | Los eventos no devuelven nada: el emisor no espera ni recibe respuesta | Llamada síncrona (un contrato de consulta o un puerto) |
| El **orden** entre efectos es estricto (cobrar, y solo si cobra, facturar) | Los manejadores de un evento son independientes y no deben depender del orden | Un caso de uso que orquesta los pasos en secuencia |
| El efecto debe fallar la operación entera si falla | Con eventos tolerantes a fallo, el emisor sigue adelante | Dentro del caso de uso, en la misma transacción |

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Un fallo del servicio de facturación hace fallar la confirmación, aunque el pedido ya estaba guardado | Un manejador lanza y el publicador en proceso propaga la excepción al caso de uso; además, los manejadores posteriores no se ejecutan |
| El correo sale pero el stock no se descuenta (o al revés), según el orden de registro | Los manejadores dependen del orden o de que otro haya terminado antes |
| Para entender qué pasa al confirmar hay que abrir doce clases sin un orden visible | Reglas de negocio escondidas en manejadores; el flujo es imposible de seguir |
| Hay un evento llamado `ConfirmarPedido` que «ordena» a alguien hacer algo | Un comando disfrazado de evento: no describe un hecho, espera ser obedecido |
| Los clientes reciben correos de pedidos que no existen | El evento se despachó antes de guardar |
| Se confirma el pedido y nunca se avisa a nadie | Despacho con el tipo estático equivocado (`IEventoDominio` en lugar del tipo real) o proceso caído entre el commit y el despacho |

El primer síntoma, reproducido: un manejador de facturación roto registrado después del de correo.

```text
Correo a cliente 1: Tu pedido #4711 está confirmado.
ERROR en el caso de uso: El servicio de facturación no responde.
```

El pedido está guardado, el stock no se descontó y el que llama ve un error. Un publicador que aísla los fallos de cada manejador y los registra, sin detener a los demás, lo evita:

```csharp
public class PublicadorAislado(IServiceProvider servicios, ILogger<PublicadorAislado> log) : IPublicadorEventos
{
    public async Task Publicar<TEvento>(TEvento evento, CancellationToken ct)
    {
        foreach (var manejador in servicios.GetServices<IManejadorEvento<TEvento>>())
        {
            try { await manejador.Manejar(evento, ct); }
            catch (Exception ex)
            {
                log.LogError(ex, "Falló {Manejador} al manejar {Evento}", manejador.GetType().Name, typeof(TEvento).Name);
            }
        }
    }
}
```

```text
Correo a cliente 1: Tu pedido #4711 está confirmado.
Falló ManejadorRoto: El servicio de facturación no responde.
Stock descontado para el pedido #4711
Factura emitida para el pedido #4711
```

(La prueba usó una lista de textos en lugar de `ILogger`; el resto es idéntico.) Tragarse la excepción implica que alguien debe enterarse y que el efecto fallido se reintente de alguna forma: con un *outbox* y reintentos, o con una cola.

## Buenas prácticas avanzadas

- **Despacha después de confirmar la transacción** los efectos que salen del proceso. Un correo o una llamada HTTP no se deshacen con un *rollback*.
- **Trata los manejadores como un efecto aparte del camino principal.** Que falle «enviar el correo» normalmente no debe deshacer la confirmación del pedido; aísla cada fallo y reintenta.
- **Diseña cada manejador para recibir el evento dos veces.** La idempotencia no es un extra: con entrega al menos una vez, es el contrato.
- **Vigila las cascadas.** Un manejador que publica otro evento, que dispara otro manejador, reproduce el encadenamiento de casos de uso, pero sin una llamada explícita que seguir en el código. Si hace falta ver el flujo, es señal de que debería ser un caso de uso que orquesta ([Casos de Uso](../clean-architecture/Casos-de-Uso.md)).
- **Versiona los eventos que salen del proceso.** En memoria se puede renombrar cualquier campo; en cuanto el evento se serializa (bus, log, *outbox*), añadir un campo es seguro y renombrar o quitar uno rompe a quien ya lo lee.
- **Pon un solo hecho en cada evento.** `PedidoConfirmado` y `PedidoPagado` son dos hechos aunque ocurran seguidos; un `PedidoConfirmadoYPagado` obliga a quien solo quiere uno de los dos a filtrar.

## Documentación oficial

- [Domain Event, Martin Fowler](https://martinfowler.com/eaaDev/DomainEvent.html): la descripción canónica del patrón; leer cuando haga falta el origen de la idea.
- [Domain events: design and implementation, Microsoft](https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/domain-events-design-implementation): diseño e implementación de eventos de dominio en .NET; útil para contrastar el momento del despacho.
- [Transactional outbox, microservices.io](https://microservices.io/patterns/data/transactional-outbox.html): el patrón *outbox* descrito con detalle; consultar antes de implementarlo.

---

*En resumen: un evento de dominio anuncia un hecho ya ocurrido para que otros reaccionen por su cuenta; el agregado lo registra, se despacha después de guardar y cada manejador debe tolerar recibirlo dos veces.*
