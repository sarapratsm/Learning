# Server-Sent Events (SSE)

## ¿Qué es?

Server-Sent Events (SSE) es una forma de que el servidor envíe al cliente un flujo continuo de mensajes de texto a través de una única respuesta HTTP que no termina, en una sola dirección (servidor → cliente). Está estandarizado en la especificación de HTML y los navegadores lo exponen con la API `EventSource`.

## ¿Por qué existe?

Una petición HTTP normal es «pregunto y me contestan». Si la persona que compró el pedido 4711 está mirando la pantalla de seguimiento, el estado cambia en el servidor (`pending` → `paid` → `shipped`) sin que el navegador pregunte nada. Las salidas clásicas son preguntar cada pocos segundos (*polling*, que gasta peticiones y llega tarde) o montar [WebSockets](WebSockets.md), un protocolo bidireccional aparte que hay que hospedar, autenticar y escalar, cuando aquí el cliente no tiene nada que decir de vuelta.

SSE resuelve exactamente ese caso: el navegador hace un `GET`, el servidor responde con `Content-Type: text/event-stream` y no cierra la respuesta; cada vez que hay una novedad escribe un bloque de texto en ella. Es HTTP corriente, con el reintento automático y la reanudación incluidos en el estándar.

> Si WebSockets es una llamada de teléfono (los dos hablan), SSE es la megafonía de una estación: el servidor anuncia y los viajeros escuchan. Para «avisarme de que el pedido se ha enviado» no hace falta que el viajero conteste por el mismo canal.

## ¿Cuándo y para qué se usa?

Cuando los datos fluyen sobre todo del servidor al cliente y el cliente, si necesita hablar, puede hacerlo con una petición HTTP aparte: seguimiento de un pedido, notificaciones, el progreso de una tarea larga (importar un fichero, generar un informe), un panel con cifras que se refrescan, el texto de una respuesta que llega por trozos (como los asistentes de IA). Si hace falta enviar del cliente al servidor con baja latencia o mover binario, mira la tabla de decisión más abajo.

## El formato del flujo de eventos

El flujo es texto UTF-8 formado por líneas `campo: valor`. Un evento termina con una línea en blanco (dos saltos de línea seguidos). Así se ve el flujo real que devuelve un servidor de prueba para el pedido 4711, capturado con `curl -N` (que desactiva el búfer de curl para ver los bloques según llegan):

```bash
curl -N -i http://localhost:5537/raw
```

```http
HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache
Transfer-Encoding: chunked
X-Accel-Buffering: no

retry: 3000

: latido

id: 1
event: estado
data: {"orderId":4711,"status":"pending"}

data: Pedido 4711
data: pagado a las 10:32

```

Cada campo tiene un papel:

| Campo | Qué hace |
|---|---|
| `data:` | El contenido del evento. Si el evento tiene varias líneas `data:`, el cliente las une con `\n` (el último bloque de arriba llega como `Pedido 4711\npagado a las 10:32`). |
| `event:` | Nombre del evento. Sin él, el evento es de tipo `message`. |
| `id:` | Identificador del evento. El navegador recuerda el último y lo reenvía al reconectar (véase más abajo). |
| `retry:` | Milisegundos que el navegador debe esperar antes de reconectar. |
| `: texto` | Línea que empieza por `:`: comentario. El cliente la ignora; sirve de latido para que nada dé la conexión por muerta. |

Una línea en blanco es lo que hace que el evento se entregue: sin ella, el navegador sigue acumulando campos y no dispara nada. Las líneas con campos desconocidos se ignoran.

## Un servidor mínimo en ASP.NET Core

.NET 10 trae soporte directo: `TypedResults.ServerSentEvents` recibe un `IAsyncEnumerable<SseItem<T>>` (tipo de `System.Net.ServerSentEvents`) y escribe el flujo con las cabeceras correctas. Este servidor emite el historial del pedido 4711 y después deja la conexión abierta esperando más cambios. Los ejemplos se ejecutaron con .NET SDK 10.0.401.

```csharp
using System.Net.ServerSentEvents;
using System.Runtime.CompilerServices;

var app = WebApplication.CreateBuilder(args).Build();

// Búfer de eventos del pedido 4711: (id, tipo, datos JSON)
var historial = new List<(int Id, string Tipo, string Json)>
{
    (1, "estado", """{"orderId":4711,"status":"pending"}"""),
    (2, "estado", """{"orderId":4711,"status":"paid"}"""),
    (3, "estado", """{"orderId":4711,"status":"shipped"}"""),
};

app.MapGet("/orders/{id:int}/events", (int id, HttpRequest request, CancellationToken ct) =>
{
    // Last-Event-ID: la cabecera que el navegador reenvía al reconectar
    int ultimo = int.TryParse(request.Headers["Last-Event-ID"], out var n) ? n : 0;
    return TypedResults.ServerSentEvents(Emitir(ultimo, app.Logger, ct));
});

async IAsyncEnumerable<SseItem<string>> Emitir(
    int desde, ILogger log, [EnumeratorCancellation] CancellationToken ct)
{
    try
    {
        foreach (var e in historial.Where(e => e.Id > desde))
        {
            yield return new SseItem<string>(e.Json, e.Tipo)
            {
                EventId = e.Id.ToString(),
                ReconnectionInterval = TimeSpan.FromSeconds(3)
            };
            await Task.Delay(1000, ct);
        }
        await Task.Delay(Timeout.Infinite, ct); // a la espera de más cambios
    }
    finally { log.LogInformation("Cliente desconectado (cancelado={C})", ct.IsCancellationRequested); }
}

app.Run("http://localhost:5537");
```

Salida de `curl -N http://localhost:5537/orders/4711/events`, un evento por segundo:

```text
event: estado
data: {"orderId":4711,"status":"pending"}
id: 1
retry: 3000

event: estado
data: {"orderId":4711,"status":"paid"}
id: 2
retry: 3000

event: estado
data: {"orderId":4711,"status":"shipped"}
id: 3
retry: 3000

```

Dos detalles de la API, comprobados al compilar:

- `new SseItem<string>(datos, tipoDeEvento)` con `EventId` y `ReconnectionInterval` produce los campos `event`, `id` y `retry`. Si `T` es `string`, `data` lleva el texto tal cual; con otro `T` se serializa a JSON.
- La sobrecarga `TypedResults.ServerSentEvents<T>(IAsyncEnumerable<T>, string? eventType)` también existe, y el compilador la elige antes que la de `SseItem<T>` si se le pasa `eventType`: el resultado fue un `SseItem` entero serializado como JSON dentro de `data`. Para fijar `id` o `retry` hay que pasar un `IAsyncEnumerable<SseItem<T>>` sin el parámetro `eventType` y poner el tipo en cada `SseItem`.

`SseItem` no tiene campo para comentarios, así que los latidos (`: latido`) no salen de `TypedResults`. Si hacen falta, la alternativa es escribir el flujo a mano con `Response.WriteAsync` y `FlushAsync`, como hace la ruta `/raw` que produjo la captura de la sección anterior:

```csharp
app.MapGet("/raw", async (HttpContext ctx) =>
{
    ctx.Response.Headers.ContentType = "text/event-stream";
    ctx.Response.Headers.CacheControl = "no-cache";
    ctx.Response.Headers["X-Accel-Buffering"] = "no";
    var ct = ctx.RequestAborted;
    await ctx.Response.WriteAsync("retry: 3000\n\n", ct);
    await ctx.Response.WriteAsync(": latido\n\n", ct);
    await ctx.Response.WriteAsync("id: 1\nevent: estado\ndata: {\"orderId\":4711,\"status\":\"pending\"}\n\n", ct);
    await ctx.Response.Body.FlushAsync(ct);   // sin flush, el evento puede quedarse en el búfer
});
```

## El cliente

### En el navegador: `EventSource`

```js
const source = new EventSource("https://api.tienda.ejemplo.com/orders/4711/events");

// eventos sin nombre (tipo "message")
source.onmessage = (e) => console.log("sin nombre:", e.data);

// eventos con nombre: addEventListener con el valor de "event:"
source.addEventListener("estado", (e) => {
  const { status } = JSON.parse(e.data);
  console.log(`Pedido 4711: ${status} (id ${e.lastEventId})`);
});

source.onerror = () => {
  // readyState: 0 CONNECTING (reconectando), 1 OPEN, 2 CLOSED (no reconectará)
  console.log("readyState =", source.readyState);
};

// para dejar de escuchar (pantalla cerrada):
source.close();
```

Un detalle que desorienta: `onmessage` solo recibe los eventos sin `event:`. Los que llevan `event: estado` solo llegan a un `addEventListener("estado", ...)`. `onerror` se dispara tanto en un corte (el navegador reintenta solo, `readyState` pasa a 0) como en un fallo definitivo (`readyState` es 2 y ya no hay reintentos).

### En C#: `SseParser` y `HttpClient`

Para consumir un flujo desde un servicio .NET (otro backend, una herramienta), `System.Net.ServerSentEvents` ofrece `SseParser`. La clave es `HttpCompletionOption.ResponseHeadersRead`: sin ella, `HttpClient` espera a tener el cuerpo entero, y el cuerpo nunca termina.

```csharp
using System.Net.ServerSentEvents;
using System.Text.Json;

using var http = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));

using var req = new HttpRequestMessage(HttpMethod.Get, "http://localhost:5537/orders/4711/events");
req.Headers.Accept.ParseAdd("text/event-stream");

using var resp = await http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, cts.Token);
resp.EnsureSuccessStatusCode();
await using var stream = await resp.Content.ReadAsStreamAsync(cts.Token);

try
{
    await foreach (SseItem<string> e in SseParser.Create(stream).EnumerateAsync(cts.Token))
    {
        var estado = JsonDocument.Parse(e.Data).RootElement.GetProperty("status").GetString();
        Console.WriteLine($"[{e.EventType}] id={e.EventId} estado={estado}");
    }
}
catch (OperationCanceledException) { Console.WriteLine("Cancelado."); }
```

```text
[estado] id=1 estado=pending
[estado] id=2 estado=paid
[estado] id=3 estado=shipped
Cancelado.
```

Se desactiva el `Timeout` de `HttpClient` (por defecto 100 s mataría el flujo) y la vida de la conexión se controla con el `CancellationToken`. `SseParser` solo interpreta el formato: la reconexión y el reenvío de `Last-Event-ID` no vienen incluidos, quien llama debe implementarlos guardando `e.EventId`.

## Reconexión automática y `Last-Event-ID`

Si la conexión se corta, `EventSource` reconecta solo tras esperar el tiempo de `retry` (si el servidor no lo ha fijado, el navegador elige uno, del orden de unos pocos segundos). En la nueva petición añade la cabecera `Last-Event-ID` con el último `id:` que recibió. Si el servidor guarda los eventos recientes en un búfer, puede reanudar justo donde se quedó el cliente. Con `curl` se simula la reconexión de quien vio hasta el `id` 2:

```bash
curl -N -H "Last-Event-ID: 2" http://localhost:5537/orders/4711/events
```

```text
event: estado
data: {"orderId":4711,"status":"shipped"}
id: 3
retry: 3000

```

Solo llega el evento 3. El código del servidor lo consigue con `historial.Where(e => e.Id > desde)`. En producción ese búfer es un almacén con límite (los últimos N eventos o minutos, o la propia tabla de eventos del pedido consultada por `id`), y si el `Last-Event-ID` es más antiguo que lo que se conserva, lo honesto es enviar el estado completo actual en vez de un hueco.

El campo `retry:` da el control del ritmo: el servidor puede subirlo (`retry: 30000`) cuando está saturado para que los clientes reconecten menos. Tres reglas del estándar sobre el estado de la conexión:

- Respuesta `HTTP 204 No Content` a una reconexión: el navegador deja de reintentar. Es la forma de decir «ya no hay nada más que enviar» (pedido entregado, por ejemplo).
- Respuesta con un `Content-Type` distinto de `text/event-stream` (o un estado de error distinto de red): el navegador falla la conexión y no reintenta.
- Que el servidor cierre la respuesta con normalidad no es un final: el navegador lo trata como un corte y reconecta.

## Cancelación y limpieza

Cuando la persona cierra la pestaña, el servidor se entera porque `HttpContext.RequestAborted` se cancela. En un `MapGet` el parámetro `CancellationToken` es ese mismo token. Todo lo que el servidor mantenga por conexión (suscripciones, temporizadores, entradas en un diccionario de clientes conectados) debe liberarse al cancelarse. Log real del servidor de arriba tras ejecutar `curl -m 5` (que corta a los 5 segundos) y el cliente C# (que cancela por su cuenta):

```text
      Cliente desconectado (cancelado=True)
      Cliente desconectado (cancelado=True)
```

El `finally` del iterador asíncrono se ejecuta en ambos casos. Con escritura manual en `Response`, `WriteAsync(texto, ct)` lanza `OperationCanceledException` al irse el cliente: hay que capturarla y salir limpiamente en lugar de dejar que se registre como error.

## Límites y trampas reales

### Conexiones por dominio en HTTP/1.1

Con HTTP/1.1 los navegadores limitan las conexiones simultáneas por dominio y cada `EventSource` ocupa una durante todo su tiempo de vida. MDN lo describe así (página consultada el 2026-11-09, última modificación el 2026-09-03): sin HTTP/2 el límite es de 6 conexiones por navegador y dominio, compartido entre todas las pestañas, y los navegadores lo han marcado como «Won't fix». Con HTTP/2 el máximo de flujos simultáneos se negocia entre cliente y servidor (por defecto, 100). La solución práctica es servir por HTTP/2 y no abrir un `EventSource` por componente de pantalla, sino uno por página que reparta los eventos.

### Proxys, compresión y búfer

Los eventos pueden llegar «a golpes» o todos al final porque algo entre el servidor y el navegador acumula la respuesta antes de reenviarla. Los sospechosos y sus remedios:

- Proxy inverso con búfer (nginx lo hace por defecto): responder con `X-Accel-Buffering: no` o desactivar `proxy_buffering` en esa ruta.
- Cachés y proxys intermedios: `Cache-Control: no-cache`.
- Compresión de respuesta (gzip, Brotli): comprime por bloques y espera a llenarlos; excluir `text/event-stream` de la compresión.
- Servidor de aplicaciones: escribir y hacer `FlushAsync` tras cada evento. Kestrel envió cada evento en el momento de escribirlo (la ruta `/lento` de prueba, con un `FlushAsync` y un segundo de pausa entre eventos, entregó los tres a intervalos de ~1 s medidos con marcas de tiempo en `curl -N`).

No se ha podido comprobar el efecto real de nginx, de un balanceador o de la compresión sobre el flujo: las cabeceras y remedios anteriores son los habituales, pero no se han probado aquí.

### Inactividad

Balanceadores y proxys cierran las conexiones que pasan un rato sin tráfico. La especificación recomienda un comentario (`: ...`) cada 15 segundos aproximadamente para mantener viva la conexión; cada cuánto cierra tu infraestructura depende de ella, y el latido debe ir por debajo de ese tiempo.

### Autenticación

`EventSource` no permite poner cabeceras propias, así que no se puede mandar `Authorization: Bearer ...`. Las opciones:

| Opción | Cómo | Pega |
|---|---|---|
| Cookie de sesión | El navegador la envía sola (`new EventSource(url, { withCredentials: true })` entre orígenes distintos) | Requiere configurar CORS con credenciales y proteger frente a CSRF (es un `GET`, que no debe cambiar estado) |
| `fetch` leyendo el flujo | `fetch(url, { headers })` y leer `response.body` con un lector de flujo | Se pierde la reconexión automática y `Last-Event-ID`: hay que reimplementarlos |
| Ticket de un solo uso | Un `POST` autenticado devuelve un ticket de vida corta; se conecta con `?ticket=...` | El ticket viaja en la URL: debe caducar en segundos y valer una sola vez |

Nunca pongas el token de acceso largo en la URL: acaba en registros de servidores y de proxys. Qué es una sesión, qué es un token y cuándo conviene cada uno está en [Sesiones vs Tokens](../../seguridad/autenticacion-y-autorizacion/Sesiones-vs-Tokens.md).

### Escalado

Cada cliente mantiene una conexión abierta, así que el coste es de conexiones simultáneas y memoria por cliente, no de peticiones por segundo. Con varias instancias, un cambio de estado del pedido ocurre en una y el cliente puede estar conectado a otra: hay que difundir los eventos entre instancias con un intermediario de mensajes (véase [Mensajería asíncrona](../../devops/mensajeria-asincrona/Mensajeria-Asincrona.md)).

## ¿SSE, WebSockets, long polling o polling?

| | SSE | [WebSockets](WebSockets.md) | [Long polling](Long-Polling.md) | Polling |
|---|---|---|---|---|
| Dirección | Servidor → cliente | Ambas | Servidor → cliente (una petición por novedad) | Servidor → cliente (el cliente pregunta) |
| Formato | Texto UTF-8 | Texto o binario | El que quieras (HTTP) | El que quieras (HTTP) |
| Reconexión | Automática, con `Last-Event-ID` | Hay que implementarla | Se vuelve a pedir tras cada respuesta | No aplica |
| Atraviesa proxys | Bien, salvo los que acumulan la respuesta | Algunos proxys bloquean el *upgrade* | Muy bien | Muy bien |
| Latencia | Inmediata | Inmediata | Casi inmediata, más una petición por evento | Hasta el intervalo de consulta |
| Complejidad | Baja | Media-alta | Media | Muy baja |

Para el seguimiento del pedido, SSE: un solo sentido, texto, reconexión gratis. Un panel de chat con soporte pide WebSockets. Si la infraestructura no tolera conexiones largas, el long polling, y si basta con refrescar cada minuto, el polling.

## Cuándo NO usar SSE

- Hace falta enviar del cliente al servidor con baja latencia (chat, juego, edición colaborativa): el cliente puede enviar con `fetch`, pero una petición por mensaje es lo que WebSockets evita.
- El contenido es binario: SSE es texto; habría que codificar a Base64 y pagar un tercio más.
- Muchos eventos por segundo por cliente: el formato textual y el procesamiento por evento en el navegador son un coste; para cotizaciones o telemetría densa conviene WebSockets o agrupar eventos.
- La infraestructura no permite respuestas largas ni desactivar el búfer.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| Los eventos llegan todos de golpe al final | Un proxy, la compresión o el propio servidor acumulan la respuesta: falta `FlushAsync`, `X-Accel-Buffering: no` o excluir el stream de la compresión |
| El navegador no dispara el evento aunque el servidor lo escribe | Falta la línea en blanco final: el evento termina con `\n\n`, no con un solo `\n` |
| `EventSource` reconecta en bucle cada pocos segundos | El servidor cerró la respuesta (por ejemplo, un `200` con el flujo vacío): para el navegador es un corte y reintenta. Para terminar de verdad, responder `204` a la reconexión |
| Se pierden o se repiten eventos tras un corte | Falta `id:` en los eventos o el servidor ignora `Last-Event-ID` |
| `onmessage` no recibe nada | El servidor envía `event: estado`: hay que usar `addEventListener("estado", ...)` |
| El evento llega cortado o `JSON.parse` falla | Un JSON con saltos de línea escrito dentro de un solo `data:`: el salto de línea termina el campo y la línea siguiente se interpreta como otro campo. Serializar en una sola línea (`JsonSerializer.Serialize` sin indentar) o repetir `data:` en cada línea |
| Error en consola y no reconecta | Content-Type distinto de `text/event-stream` o estado HTTP de error: la conexión falla definitivamente |
| Una pestaña nueva se queda sin conexión | Se alcanzó el límite de ~6 conexiones por dominio en HTTP/1.1 |

No se ha comprobado en un navegador real el bucle de reconexión tras un `200` con el flujo cerrado: es lo que dice el estándar y lo habitual, no una captura.

## Buenas prácticas avanzadas

- Pon `id:` en cada evento y guarda un búfer acotado para reanudar con `Last-Event-ID`: sin él, cada microcorte deja un hueco silencioso. Si el id pedido ya no está en el búfer, envía el estado completo actual como primer evento.
- Manda un latido (`: ping`) por debajo del timeout de inactividad más corto de tu infraestructura, y comprueba que atraviesa el proxy con `curl -N` contra el dominio público, no solo contra `localhost`.
- Libera los recursos por conexión al cancelarse `RequestAborted`; una suscripción que no se retira es una fuga que crece con cada pestaña cerrada.
- Envía eventos que el cliente pueda aplicar solo (el estado nuevo, no «recarga»), con `event:` para tipos distintos y JSON en una sola línea en `data:`.
- Usa `retry:` para repartir la carga en una reconexión masiva (tras reiniciar el servidor, todos los clientes vuelven a la vez): un valor con algo de variación evita la avalancha.

## Documentación oficial

- [Especificación HTML (WHATWG): Server-sent events](https://html.spec.whatwg.org/multipage/server-sent-events.html): el formato del flujo y el algoritmo de reconexión. Ir cuando haya dudas sobre un caso límite (campos desconocidos, `204`, `Last-Event-ID`).
- [MDN: Usar server-sent events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events): guía práctica con ejemplos de cliente y servidor y el límite de conexiones.
- [MDN: EventSource](https://developer.mozilla.org/en-US/docs/Web/API/EventSource): propiedades, eventos y `readyState`.
- [Microsoft Learn: SseParser](https://learn.microsoft.com/en-us/dotnet/api/system.net.serversentevents.sseparser): la API de .NET para leer flujos SSE desde C#.

---
*En resumen: SSE es una respuesta HTTP que no termina y por la que el servidor empuja texto: un solo sentido, reconexión y reanudación incluidas, y la herramienta justa para avisar de que el pedido ha cambiado de estado.*
