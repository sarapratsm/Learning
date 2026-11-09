# APIs Dirigidas por Eventos

## ¿Qué es?

Una **API dirigida por eventos** (*event-driven API*) es un estilo de API en el que un sistema no pide cosas a otros, sino que **publica hechos ya ocurridos** («el pedido 4711 se ha enviado») y los sistemas interesados reaccionan por su cuenta. Lo que se diseña y se versiona es el **evento**: su nombre, su contenido y su forma, igual que en REST se diseña el recurso.

## ¿Por qué existe?

En la tienda online, cuando un pedido se envía, tres sistemas tienen algo que hacer: `inventory` descuenta el stock, `emails` avisa al cliente y, más adelante, `analytics` querrá contar envíos. Con llamadas síncronas, `orders` los invoca uno tras otro:

```csharp
// ❌ orders conoce a todos sus interesados y espera a cada uno
await inventory.DiscountStockAsync(order);
await emails.SendShippedEmailAsync(order);   // si SMTP cae, falla el envío del pedido entero
// mañana: await analytics.RegisterShipmentAsync(order);  → hay que tocar y redesplegar orders
```

Hay dos problemas. El primero es el **acoplamiento en el tiempo**: si `emails` está caído o lento, la petición que marca el pedido como enviado falla o tarda, aunque el envío en sí haya ido bien. El segundo es el **acoplamiento por conocimiento**: cada interesado nuevo obliga a modificar al emisor, que acaba sabiendo quién reacciona a qué.

Con eventos, `orders` publica `OrderShipped` y termina. `inventory`, `emails` y `analytics` se suscriben; añadir un cuarto no toca a `orders`, y que uno falle no afecta a los demás.

> Un tablón de anuncios de la comunidad. Quien tiene una novedad la cuelga y sigue con lo suyo; los vecinos interesados la leen cuando pasan. Nadie va puerta por puerta, y quien quiera enterarse no necesita que el autor lo sepa. Lo que sí necesita es que el anuncio esté bien escrito: es lo único que comparten.

## ¿Cuándo y para qué se usa?

Cuando un mismo hecho desencadena varias reacciones independientes (pedido enviado, pago recibido, producto agotado), cuando los sistemas deben seguir funcionando aunque otro esté caído, o cuando se quiere que terceros puedan reaccionar a lo que ocurre sin pedir cambios al emisor. La infraestructura que reparte los eventos (colas, *topics*, *brokers*) se explica en [Mensajería asíncrona](../../devops/mensajeria-asincrona/Mensajeria-Asincrona.md) y [RabbitMQ](../../devops/mensajeria-asincrona/RabbitMQ.md); aquí se trata el diseño de los eventos como API.

## Evento, comando y consulta

Tres tipos de mensaje que se confunden con facilidad y que se diseñan distinto:

| | Evento | Comando | Consulta |
|---|---|---|---|
| Significa | «Ha ocurrido X» | «Haz X» | «Dame X» |
| Nombre | Pasado: `OrderShipped` | Imperativo: `ShipOrder` | Pregunta: `GetOrder` |
| Quién decide | Quien lo emite ya decidió y lo hizo; el receptor no puede vetarlo | El receptor decide si lo cumple | El receptor responde |
| Receptores | Cero, uno o muchos, desconocidos para el emisor | Uno, conocido | Uno, conocido |
| Respuesta | Ninguna | Aceptado o rechazado | Los datos |

Un evento es **parte de la API pública** aunque nadie lo llame: los consumidores dependen de su nombre y de sus campos, y no hay forma de saber cuántos son. Cambiarlo a la ligera rompe a quien ni sabías que existía.

La prueba del nombre: si al escribirlo en imperativo el mensaje pide algo a alguien concreto (`SendShippedEmail`), es un comando disfrazado de evento.

## El sobre del evento

Un evento lleva el dato del negocio (`data`) dentro de un **sobre** con metadatos que permiten identificarlo, enrutarlo y deduplicarlo sin abrir el contenido. [CloudEvents](https://cloudevents.io/) es la especificación que estandariza ese sobre. Según la versión 1.0 de la especificación (consultada el 2026-11-09), los atributos obligatorios son cuatro:

| Atributo | Qué es |
|---|---|
| `id` | Identifica el evento. `source` + `id` debe ser único para cada evento distinto; un reenvío del mismo evento puede conservar el `id`, y los consumidores pueden tratar `source` + `id` repetidos como duplicados |
| `source` | Contexto donde ocurrió (referencia URI; se recomienda absoluta) |
| `specversion` | Versión de CloudEvents; con la 1.0 vale `"1.0"` |
| `type` | Tipo de evento; se recomienda prefijarlo con un nombre DNS inverso |

`time` (cuándo ocurrió), `subject`, `datacontenttype` y `dataschema` son opcionales; `data` es el contenido. Un `OrderShipped` de la tienda en formato estructurado JSON:

```json
{
  "specversion": "1.0",
  "id": "evt-9f2c1a",
  "source": "https://api.tienda.ejemplo.com/orders",
  "type": "com.tienda.order.shipped.v1",
  "subject": "orders/4711",
  "time": "2026-11-09T10:15:00Z",
  "datacontenttype": "application/json",
  "data": {
    "orderId": 4711,
    "customerId": 12,
    "carrier": "Correos",
    "trackingNumber": "CO123456789ES",
    "shippedAt": "2026-11-09T10:15:00Z"
  }
}
```

El sobre responde a las preguntas de infraestructura (¿es un duplicado?, ¿a quién enruto?, ¿de qué versión es?) y `data` a las del negocio. Usar CloudEvents no es obligatorio; es útil porque herramientas y proveedores ya entienden esos atributos, y porque obliga a no olvidarse del `id` y del `type`.

## Evento ligero o evento con estado

Qué lleva `data` es la decisión de diseño más discutida. Un evento **ligero** (*notification*) solo dice qué ha pasado y dónde está el dato; uno **con estado** (*event-carried state transfer*) lleva los datos que el consumidor necesita.

```json
{ "type": "com.tienda.order.shipped.v1", "data": { "orderId": 4711 } }
```

```json
{ "type": "com.tienda.order.shipped.v1",
  "data": { "orderId": 4711, "customerId": 12, "carrier": "Correos",
            "trackingNumber": "CO123456789ES", "lines": [{ "productId": 42, "quantity": 2 }] } }
```

| | Ligero | Con estado |
|---|---|---|
| Consumidor necesita más datos | Llama a `GET /orders/4711` | Ya los tiene |
| Acoplamiento | Por consulta de vuelta: `orders` debe estar disponible y los consumidores lo saturan en un pico | Por esquema: cada campo es contrato |
| Obsolescencia | Lee el estado actual (puede haber cambiado desde el evento) | Lee el estado del momento del evento (puede estar desactualizado al procesarlo) |
| Tamaño | Mínimo | Mayor, y crece con cada consumidor que pide «un campo más» |
| Encaja cuando | El dato cambia a menudo o es sensible | El consumidor necesita el estado **en ese instante** o no debe depender de `orders` |

Regla práctica: incluir lo que casi todos los consumidores necesitan y que no cambia después del hecho (`trackingNumber` en un envío ya hecho), y dejar fuera lo voluminoso o mutable. Si cada consumidor acaba llamando de vuelta a la API de `orders`, el evento no ha desacoplado nada.

## El contrato asíncrono: AsyncAPI

OpenAPI describe qué rutas ofrece una API HTTP. Para eventos no hay rutas que llamar, y [AsyncAPI](https://www.asyncapi.com/) cumple ese papel: un documento YAML o JSON que describe los **canales** (por dónde viajan los mensajes), los **mensajes** (qué evento circula y con qué esquema) y las **operaciones** (si la aplicación envía o recibe en ese canal). La versión vigente consultada el 2026-11-09 es la 3.1.0. Un fragmento mínimo para `OrderShipped`:

```yaml
asyncapi: 3.1.0
info:
  title: Eventos de pedidos de la tienda
  version: 1.0.0
channels:
  orderShipped:
    address: orders.shipped
    messages:
      orderShipped:
        $ref: '#/components/messages/OrderShipped'
operations:
  publishOrderShipped:
    action: send
    channel:
      $ref: '#/channels/orderShipped'
components:
  messages:
    OrderShipped:
      name: OrderShipped
      contentType: application/json
      payload:
        type: object
        required: [orderId, carrier]
        properties:
          orderId:        { type: integer, examples: [4711] }
          carrier:        { type: string,  examples: [Correos] }
          trackingNumber: { type: string }
```

`action: send` indica que este servicio **publica** en el canal; el servicio que consume declara la misma estructura con `action: receive`. Con ese documento se puede generar documentación, validar mensajes y generar código, igual que con OpenAPI. El criterio de trabajar primero el contrato y después el código es el mismo que en [Contrato primero](../contratos-de-api/Contrato-Primero.md).

## Evolucionar los eventos sin romper consumidores

Los consumidores se despliegan en otro momento y el emisor no los controla, así que los cambios se clasifican por si rompen o no:

| Cambio | ¿Compatible? | Por qué |
|---|---|---|
| Añadir un campo opcional | Sí | Quien no lo conoce lo ignora (si su deserializador tolera campos desconocidos) |
| Renombrar un campo | No | El consumidor busca el nombre antiguo |
| Quitar un campo | No | Los que lo leían dejan de recibirlo |
| Cambiar su significado o su unidad (`total` pasa de euros a céntimos) | No, y es el peor: no da error, da datos falsos | El nombre y el tipo no cambian |

Cuando hace falta un cambio incompatible se publica un **tipo nuevo**: la versión va en el `type` (`com.tienda.order.shipped.v2`) o en el esquema referenciado por `dataschema`. Durante un tiempo el emisor publica las dos versiones y se retira la antigua cuando nadie la consume. Cómo se versionan y gobiernan los contratos en general está en [Versionado de contratos](../contratos-de-api/Versionado-de-Contratos.md).

## Entrega, orden y duplicados

Un broker típico entrega **al menos una vez**: no pierde el evento, pero puede entregarlo dos veces (el detalle está en [Mensajería asíncrona](../../devops/mensajeria-asincrona/Mensajeria-Asincrona.md)). Tres consecuencias de diseño para la API de eventos:

**Duplicados: el consumidor es idempotente.** El `id` del sobre sirve de clave. Una tabla de eventos procesados lo registra en la misma transacción que el trabajo:

```sql
CREATE TABLE processed_events (
    consumer   VARCHAR(50)  NOT NULL,
    event_id   VARCHAR(100) NOT NULL,
    processed_at TIMESTAMP  NOT NULL,
    PRIMARY KEY (consumer, event_id)
);
-- Un INSERT que viola la clave primaria significa «ya procesado»: se ignora el evento.
```

**Orden: solo dentro de una partición o clave.** Los brokers garantizan orden, como mucho, entre los mensajes de un mismo grupo (una partición, una sesión), y a costa de paralelismo. Si todos los eventos del pedido 4711 usan `4711` como clave, llegarán en orden; entre pedidos distintos no hay orden. Aun así un consumidor sensato no asume orden. Si `OrderShipped` llega antes que `OrderPaid`, caben tres respuestas: guardar el evento y reintentarlo con espera hasta que se cumpla la precondición, incluir en el evento un número de secuencia por pedido para detectar huecos y descartar los obsoletos, o diseñar el consumidor para que el resultado final no dependa del orden (guardar «enviado» y «pagado» como hechos independientes).

**Eventos perdidos: se evitan al emitir.** Guardar el pedido y publicar el evento son dos escrituras en sistemas distintos; si el proceso muere entre ambas, el pedido existe y nadie se enteró. La emisión fiable se resuelve con el patrón *outbox*: el evento se guarda en la misma transacción que el dato y un proceso aparte lo publica. Está desarrollado en [Outbox Pattern](../../devops/mensajeria-asincrona/Outbox-Pattern.md), y los mensajes que no se consiguen procesar van a una [Dead Letter Queue](../../devops/mensajeria-asincrona/Dead-Letter-Queues.md).

## Un broker en memoria para verlo

El siguiente programa es una **simulación didáctica**: un broker de juguete hecho con `System.Threading.Channels`, sin red ni persistencia ni confirmaciones. No sustituye a un broker real; sirve para ver el desacoplamiento. Cada suscripción recibe su propia copia de cada evento.

```csharp
using System.Threading.Channels;

var broker = new InMemoryBroker();
var inventario = broker.Subscribe();
var emails = broker.Subscribe();

var tareas = new List<Task>
{
    Consumir(inventario, "inventory", e => Console.WriteLine($"[inventory] descuenta stock del pedido {e.Data.OrderId}")),
    Consumir(emails, "emails", e => throw new InvalidOperationException("servidor SMTP caído")),
};

var emisor = new OrderShippedPublisher(broker);
await emisor.PublishAsync("4711");

// Un tercer interesado se suscribe: el emisor no cambia
var estadisticas = broker.Subscribe();
tareas.Add(Consumir(estadisticas, "analytics", e => Console.WriteLine($"[analytics] registra envío del pedido {e.Data.OrderId}")));
await emisor.PublishAsync("4712");
await emisor.PublishAsync("4712"); // reenvío del mismo evento (mismo id)

broker.Complete();
await Task.WhenAll(tareas);

async Task Consumir(ChannelReader<OrderShipped> cola, string nombre, Action<OrderShipped> manejar)
{
    var procesados = new HashSet<string>(); // tabla de eventos procesados, en memoria
    await foreach (var e in cola.ReadAllAsync())
    {
        if (!procesados.Add(e.Id)) { Console.WriteLine($"[{nombre}] duplicado {e.Id}, se ignora"); continue; }
        try { manejar(e); }
        catch (Exception ex) { Console.WriteLine($"[{nombre}] ERROR con {e.Id}: {ex.Message}"); procesados.Remove(e.Id); }
    }
}

record ShippedData(string OrderId, string Carrier, string TrackingNumber);
record OrderShipped(string Id, string Type, string Source, string Time, string Specversion, ShippedData Data);

class InMemoryBroker
{
    private readonly List<Channel<OrderShipped>> _subs = new();
    public ChannelReader<OrderShipped> Subscribe()
    { var c = Channel.CreateUnbounded<OrderShipped>(); _subs.Add(c); return c.Reader; }
    public void Publish(OrderShipped e) { foreach (var c in _subs) c.Writer.TryWrite(e); }
    public void Complete() { foreach (var c in _subs) c.Writer.Complete(); }
}

class OrderShippedPublisher(InMemoryBroker broker)
{
    public Task PublishAsync(string orderId)
    {
        var e = new OrderShipped($"evt-{orderId}", "com.tienda.order.shipped.v1", "/orders",
            "2026-11-09T10:15:00Z", "1.0", new ShippedData(orderId, "Correos", "CO123456789ES"));
        Console.WriteLine($"[orders] publica {e.Type} {e.Id}");
        broker.Publish(e);
        return Task.CompletedTask;
    }
}
```

Salida real (.NET 10; las líneas de consumidores distintos se intercalan en orden variable porque corren en paralelo):

```text
[orders] publica com.tienda.order.shipped.v1 evt-4711
[orders] publica com.tienda.order.shipped.v1 evt-4712
[orders] publica com.tienda.order.shipped.v1 evt-4712
[inventory] descuenta stock del pedido 4711
[analytics] registra envío del pedido 4712
[inventory] descuenta stock del pedido 4712
[analytics] duplicado evt-4712, se ignora
[emails] ERROR con evt-4711: servidor SMTP caído
[inventory] duplicado evt-4712, se ignora
[emails] ERROR con evt-4712: servidor SMTP caído
[emails] ERROR con evt-4712: servidor SMTP caído
```

Qué demuestra: `emails` falla en todos los eventos y `inventory` y `analytics` procesan los suyos sin enterarse; `analytics` se añade después sin que `OrderShippedPublisher` cambie una línea; y el reenvío de `evt-4712` se descarta en cada consumidor gracias al `id`. Lo que no reproduce: persistencia (si el proceso muere, se pierde todo), reentrega de los eventos fallidos ni *dead-lettering*; con un broker real, el evento de `emails` esperaría en su cola hasta que el consumidor se recuperase.

## Coreografía u orquestación

Cuando varios pasos deben ocurrir tras un hecho hay dos formas de organizarlos. En la **coreografía** cada servicio reacciona a eventos y emite los suyos, sin director. En la **orquestación** un componente central ordena cada paso (suele usar comandos).

Confirmación del pedido 4711: reservar stock, cobrar, preparar el envío, avisar al cliente.

| | Coreografía | Orquestación |
|---|---|---|
| Flujo | `OrderPlaced` → inventory emite `StockReserved` → payments emite `PaymentCaptured` → shipping emite `OrderShipped` | Un orquestador pide `ReserveStock`, espera, pide `CapturePayment`, etc. |
| Acoplamiento | Bajo: nadie conoce el flujo entero | Los servicios son simples, pero el orquestador conoce a todos |
| Ver el flujo | Repartido: hay que reconstruirlo siguiendo eventos de cinco servicios | Está en un solo sitio |
| Compensar un fallo (devolver el cobro si no hay envío) | Cada servicio reacciona a eventos de fallo; fácil dejar huecos | Lo decide el orquestador |
| Encaja cuando | Pocos pasos y reacciones independientes | Muchos pasos con dependencias y compensaciones |

El riesgo de la coreografía es que el flujo de negocio exista solo en la suma de suscripciones: nadie puede decir qué pasa cuando se confirma un pedido sin leer el código de cinco servicios. Si el proceso tiene más de tres o cuatro pasos dependientes, documentar el flujo (o pasar a un orquestador) es parte del diseño.

No conviene confundir el evento de integración con el *evento de dominio*: este último ocurre **dentro de un proceso**, entre objetos de una misma aplicación; el de integración cruza sistemas y es contrato público. La distinción y cuándo uno origina el otro están en [Domain Events](../patrones-de-diseno/Domain-Events.md).

## Observabilidad

Un fallo en un consumidor ocurre en otro proceso, minutos después, sin pila de llamadas que lo una al origen. El evento debe llevar con qué reconstruir el recorrido: un identificador de correlación (el `id` del evento que originó la cadena, copiado a los eventos derivados) y el contexto de traza. CloudEvents define una extensión de trazado distribuido que añade el atributo `traceparent` con el formato de W3C Trace Context:

```text
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
```

Con él, la herramienta de trazas une la petición que originó `OrderShipped` con cada consumidor que lo procesó.

## Cuándo no usar APIs dirigidas por eventos

- **Se necesita la respuesta para continuar.** Comprobar si hay stock antes de aceptar el pedido es una consulta; con eventos solo se añade latencia. Usa [REST](REST.md) o [RPC](RPC.md).
- **Flujo transaccional estricto.** O se hacen los tres pasos o ninguno, y el usuario espera verlo al instante, la consistencia eventual de los eventos no sirve; hace falta una transacción o un orquestador con compensaciones.
- **Equipo pequeño y un monolito.** Un broker es una pieza más que operar y vigilar. Dentro de un mismo proceso basta con eventos de dominio en memoria.
- **El destinatario es un tercero que debe recibir un aviso HTTP.** Para notificar hacia fuera, [Webhooks](Webhooks.md) (llamada HTTP al cliente) o [Server-Sent Events](Server-Sent-Events.md) (flujo hacia un navegador) son más simples que exponer un broker.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| Un consumidor «solo funciona» si otro servicio hace algo concreto | El evento es un comando disfrazado (`SendShippedEmail`): el emisor espera una acción, no anuncia un hecho |
| Los consumidores tienen un `switch` sobre qué campo ha cambiado | Evento CRUD genérico (`OrderUpdated`): no dice qué ocurrió; usar eventos con significado de negocio (`OrderShipped`, `OrderCancelled`) |
| Estados incoherentes de forma intermitente | Consumidores que asumen orden: `OrderShipped` procesado antes que `OrderPaid` |
| Cambiar un evento obliga a desplegar a todos a la vez | Un paquete de esquema compartido entre emisor y consumidores los acopla en compilación; compartir el contrato (AsyncAPI), no una librería de clases |
| Eventos que nadie recibió, sin error en ningún sitio | Se publicó antes del *commit* y la transacción falló, o el proceso murió entre guardar y publicar: usar outbox |
| Facturas o emails duplicados | Entrega al menos una vez con consumidor no idempotente |
| El sistema se satura sin que nadie lo haya pedido | Ciclo de eventos: A reacciona a un evento de B y B a uno de A; todo evento derivado debería tener una causa que no sea su propia consecuencia |

## Buenas prácticas avanzadas

- **Nombra el evento por el hecho de negocio, en pasado, y con una sola razón para existir.** `OrderShipped` y `OrderCancelled` tienen cada uno consumidores con intereses distintos; `OrderStatusChanged` los obliga a filtrar.
- **Trata `type` y el esquema como una API pública desde el primer día.** Publica el documento AsyncAPI en el mismo repositorio que el emisor y valida los eventos contra él en las pruebas del emisor.
- **Que el consumidor ignore lo que no conoce.** Configura el deserializador para tolerar campos desconocidos y valores nuevos de enumeraciones; es lo que permite al emisor añadir sin coordinar.
- **Pon a cada consumidor su propia cola o suscripción.** Compartirla reparte los eventos entre consumidores distintos en vez de duplicarlos para cada uno, y un consumidor lento retrasaría a los demás.
- **Mide la antigüedad del evento más viejo pendiente por consumidor**, no solo los errores: un consumidor atascado no lanza excepciones.
- **Decide quién es el dueño del evento.** El servicio donde ocurre el hecho (`orders` para `OrderShipped`) define el contrato; los consumidores lo aceptan o piden cambios, no lo redefinen.

## Documentación oficial

- [CloudEvents](https://cloudevents.io/) — la página del proyecto; la especificación está en [github.com/cloudevents/spec](https://github.com/cloudevents/spec). Ir al documento `spec.md` para la lista de atributos obligatorios y opcionales, y a las extensiones (trazado distribuido) cuando haga falta propagar el contexto.
- [AsyncAPI](https://www.asyncapi.com/docs) — documentación del estándar; la [especificación 3.1.0](https://www.asyncapi.com/docs/reference/specification/v3.1.0) es la referencia al escribir canales, operaciones y mensajes.

---
*En resumen: en una API dirigida por eventos lo que se publica es un hecho ya ocurrido, y ese evento es un contrato público que hay que nombrar, describir y evolucionar con el mismo cuidado que un endpoint.*
