# WebSockets

## ¿Qué es?

**WebSockets** (RFC 6455) es un protocolo que abre una **conexión TCP persistente y bidireccional** entre cliente y servidor. Empieza como una petición HTTP normal, se "asciende" (*upgrade*) y, a partir de ahí, ambos lados se envían mensajes cuando quieren, sin pedirlos ni esperar respuesta.

## ¿Por qué existe?

HTTP es petición-respuesta: el cliente pregunta y el servidor contesta. El servidor **no puede** iniciar la conversación. Para ver en vivo el estado del pedido 4711 en un panel de soporte, la única salida con HTTP puro es el *sondeo* (*polling*): `GET /orders/4711` cada segundo. Es caro (cada petición lleva cabeceras, autenticación y una consulta a base de datos, aunque nada haya cambiado) y llega tarde (el cambio se ve, de media, medio segundo después de ocurrir, y hasta un segundo entero en el peor caso). Con 500 agentes mirando pedidos son 500 peticiones por segundo para enterarse, casi siempre, de que no hay novedades.

WebSockets invierte el modelo: una sola conexión que queda abierta. El servidor empuja el cambio en el instante en que ocurre, y el agente de soporte puede enviar un mensaje al cliente por la misma conexión.

> REST es como enviar cartas: escribes, esperas respuesta y solo recibes cuando tú has escrito antes. WebSockets es una llamada de teléfono abierta: los dos habláis cuando queréis, sin colgar y volver a marcar.

## ¿Cuándo y para qué se usa?

Cuando hay datos en tiempo real que fluyen **en ambas direcciones** y con frecuencia:

- El **panel de soporte** de la tienda: ve el estado del pedido 4711 cambiar de `paid` a `shipped` y escribe mensajes al cliente.
- Un **chat**, un **juego** multijugador, una **pizarra colaborativa**.
- Un panel de métricas o cotizaciones con acciones de vuelta (suscribirse a un valor, pausar).

Si los datos solo bajan del servidor al cliente, [Server-Sent Events](Server-Sent-Events.md) suele bastar con menos piezas. Si el cambio es raro y se tolera algo de retraso, [Long Polling](Long-Polling.md) o un sondeo espaciado son más sencillos.

## El apretón de manos (*handshake*)

La conexión nace como una petición HTTP `GET` que pide cambiar de protocolo. Este es el intercambio real capturado con `curl --include --no-buffer` contra el servidor de más abajo (.NET 10, Kestrel):

```http
GET /ws?ticket=15476132dce37147bbf7ee10f85de2ef HTTP/1.1
Host: 127.0.0.1:5437
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Version: 13
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
```

```http
HTTP/1.1 101 Switching Protocols
Connection: Upgrade
Upgrade: websocket
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

- `Upgrade: websocket` + `Connection: Upgrade`: la petición de cambio de protocolo.
- `Sec-WebSocket-Version: 13`: la versión de la RFC 6455, la única en uso.
- `Sec-WebSocket-Key`: un valor aleatorio en base64 que genera el cliente.
- `101 Switching Protocols`: el servidor acepta. Desde el final de esas cabeceras, el mismo socket TCP deja de hablar HTTP y habla tramas WebSocket.

`Sec-WebSocket-Accept` no es un secreto ni autentica a nadie: demuestra que el servidor entiende WebSocket y evita que un servidor HTTP ajeno (o una caché) responda por error como si lo hiciera. Se calcula concatenando la clave del cliente con un GUID fijo de la RFC, aplicando SHA-1 y codificando en base64:

```csharp
using System.Security.Cryptography;
using System.Text;

var key = "dGhlIHNhbXBsZSBub25jZQ==";                         // Sec-WebSocket-Key
var guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";           // constante de la RFC 6455
var accept = Convert.ToBase64String(SHA1.HashData(Encoding.ASCII.GetBytes(key + guid)));
Console.WriteLine(accept);   // s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

El resultado coincide con la cabecera que devolvió el servidor y con el ejemplo de la propia RFC (sección 1.3). En la práctica nadie lo calcula a mano: lo hacen el navegador y `AcceptWebSocketAsync`.

La URL usa `ws://` (sin cifrar) o `wss://` (sobre TLS, la única opción razonable fuera de local): `wss://api.tienda.ejemplo.com/ws`.

## Tramas y códigos de cierre

Tras el `101`, los datos viajan en **tramas** (*frames*). Un **mensaje** es una o varias tramas; cada trama indica su tipo (*opcode*) y si es la última del mensaje:

| Tipo | Opcode | Para qué |
|---|---|---|
| Texto | `0x1` | Mensaje UTF-8 (lo habitual: JSON) |
| Binario | `0x2` | Bytes arbitrarios |
| Continuación | `0x0` | Trama siguiente de un mensaje fragmentado |
| Close | `0x8` | Cierre ordenado, con código y motivo opcional |
| Ping | `0x9` | "¿Sigues ahí?" |
| Pong | `0xA` | Respuesta a un ping |

Los controles (close, ping, pong) llevan como máximo 125 bytes de carga útil. Las tramas del cliente al servidor van **enmascaradas** (lo exige la RFC para que los intermediarios no interpreten el contenido como HTTP); las del servidor, no. Los clientes de las librerías lo hacen solos.

El primer mensaje que llega al panel al conectar, visto en crudo con curl, empieza por la cabecera de trama `0x81 0x44`: `0x81` = última trama + texto, `0x44` = 68 bytes de carga, que son:

```json
{"type":"order.snapshot","payload":{"orderId":4711,"status":"paid"}}
```

Códigos de cierre más habituales (RFC 6455, sección 7.4.1):

| Código | Significado | Quién lo usa |
|---|---|---|
| `1000` | Cierre normal: se cumplió el propósito | Cualquiera, al terminar |
| `1001` | "Me voy": el servidor se apaga o el usuario sale de la página | Cualquiera |
| `1002` | Error de protocolo | Quien detecta la violación |
| `1003` | Tipo de dato no aceptado (p. ej. binario donde solo se admite texto) | Quien recibe |
| `1005` | Cierre sin código | Reservado: nunca viaja en la red |
| `1006` | Conexión cerrada de forma anormal, sin trama close | Reservado: lo informa la librería local, nunca viaja |
| `1007` | Datos incoherentes con el tipo (texto que no es UTF-8) | Quien recibe |
| `1008` | Mensaje que viola la política (código genérico; sirve para "no autorizado") | Servidor |
| `1009` | Mensaje demasiado grande | Quien recibe |
| `1011` | Error interno del servidor | Servidor |

`1005`, `1006` y `1015` son valores que la RFC reserva para que las librerías informen de situaciones locales: si una aplicación ve `1006`, significa que la conexión se perdió (red, proxy, proceso muerto) sin que el otro lado enviara un close. Las aplicaciones pueden definir sus propios códigos en el rango `4000-4999`.

## Un servidor mínimo en ASP.NET Core

Servidor del panel: acepta conexiones en `/ws`, envía al conectar el estado actual del pedido 4711, difunde los cambios de estado a todos los conectados y confirma (`ack`) los mensajes del agente.

```csharp
using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.UseWebSockets();   // habilita el middleware

var clients = new ConcurrentDictionary<Guid, Client>();
var status = "paid";

app.MapPost("/orders/4711/status/{s}", async (string s) =>
{
    status = s;
    await Broadcast(new { type = "order.status", payload = new { orderId = 4711, status = s } });
    return Results.NoContent();
});

app.Map("/ws", async (HttpContext ctx) =>
{
    if (!ctx.WebSockets.IsWebSocketRequest) { ctx.Response.StatusCode = 400; return; }

    using var ws = await ctx.WebSockets.AcceptWebSocketAsync();   // responde el 101
    var id = Guid.NewGuid();
    var client = new Client(ws);
    clients[id] = client;
    try
    {
        await client.SendAsync(new { type = "order.snapshot", payload = new { orderId = 4711, status } });
        await ReceiveLoop(ws, client, ctx.RequestAborted);
    }
    finally { clients.TryRemove(id, out _); }       // siempre, aunque la conexión caiga
});

async Task Broadcast(object msg)
{
    foreach (var c in clients.Values)
        try { await c.SendAsync(msg); } catch { /* un cliente roto no debe parar al resto */ }
}

app.Run();

// Un envío a la vez por socket
class Client(WebSocket ws)
{
    readonly SemaphoreSlim gate = new(1, 1);
    public async Task SendAsync(object msg)
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(msg);
        await gate.WaitAsync();
        try
        {
            if (ws.State == WebSocketState.Open)
                await ws.SendAsync(bytes, WebSocketMessageType.Text, true, CancellationToken.None);
        }
        finally { gate.Release(); }
    }
}
```

`ReceiveLoop` se desarrolla en la sección siguiente. Se ha compilado y ejecutado en .NET 10 (SDK 10.0.401).

Cliente en C# con `ClientWebSocket`, que hace de panel de soporte: lee el estado, envía un mensaje al cliente y recibe el cambio de estado que provoca un `POST /orders/4711/status/shipped`:

```csharp
var ws = new ClientWebSocket();
await ws.ConnectAsync(new Uri("ws://127.0.0.1:5437/ws"), CancellationToken.None);

await Send(ws, new { id = "m-1", type = "support.message",
                     payload = new { orderId = 4711, text = "Su pedido sale hoy" } });
// Receive(...) es el bucle de recepción de la sección siguiente
```

Salida real de ejecutar ese flujo (cada línea es un mensaje recibido):

```text
recibido: {"type":"order.snapshot","payload":{"orderId":4711,"status":"paid"}}
recibido: {"type":"ack","payload":{"ackId":"m-1"}}
recibido: {"type":"order.status","payload":{"orderId":4711,"status":"shipped"}}
```

En el navegador, la API es la de [MDN (`WebSocket`)](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket), basada en eventos:

```js
const ws = new WebSocket("wss://api.tienda.ejemplo.com/ws?ticket=" + ticket);

ws.onmessage = (e) => {
  const msg = JSON.parse(e.data);                 // e.data ya llega como mensaje completo
  if (msg.type === "order.status") pintarEstado(msg.payload.status);
};
ws.onclose = (e) => console.log("cerrada", e.code, e.reason);   // 1000, 1006...

ws.send(JSON.stringify({ id: "m-2", type: "support.message",
                         payload: { orderId: 4711, text: "Gracias por esperar" } }));
```

El navegador entrega mensajes completos: el fragmentado en tramas lo resuelve él. En .NET, no.

## El bucle de recepción

`ReceiveAsync` rellena un búfer y devuelve cuántos bytes ha puesto y si ese trozo **cierra el mensaje** (`EndOfMessage`). Un mensaje puede llegar partido en varias lecturas, por tamaño del búfer o por fragmentación de tramas. El error clásico es asumir una lectura = un mensaje.

❌ Con un búfer de 16 bytes (exagerado para que se vea; con 4 KB pasa igual con mensajes más grandes), la primera lectura del mensaje de 68 bytes devuelve:

```text
leído: {"type":"order.s  EndOfMessage=False
JsonReaderException: Expected end of string, but instead reached end of data. LineNumber: 0 | BytePositionInLine: 16.
```

✅ El bucle correcto acumula hasta `EndOfMessage` y trata el cierre:

```csharp
static async Task ReceiveLoop(WebSocket ws, Client client, CancellationToken ct)
{
    var buffer = new byte[4096];
    while (ws.State == WebSocketState.Open)
    {
        using var ms = new MemoryStream();
        WebSocketReceiveResult r;
        do
        {
            r = await ws.ReceiveAsync(buffer, ct);
            if (r.MessageType == WebSocketMessageType.Close)
            {
                await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "bye", CancellationToken.None);
                return;
            }
            ms.Write(buffer, 0, r.Count);
            if (ms.Length > 64 * 1024)   // límite de tamaño de mensaje
            {
                await ws.CloseAsync(WebSocketCloseStatus.MessageTooBig, "demasiado grande", CancellationToken.None);
                return;
            }
        } while (!r.EndOfMessage);

        await Handle(ms.ToArray(), client);   // aquí ya hay un mensaje completo
    }
}
```

Dos detalles: sin el límite de tamaño, un cliente puede agotar la memoria enviando un mensaje que nunca termina; y al recibir `Close` hay que responder con `CloseAsync` para completar el cierre ordenado.

Prueba real del cierre ordenado: tras `CloseAsync(NormalClosure, "fin")` desde el cliente, el servidor que respondió con "bye" deja en el cliente `estado=Closed cierre=NormalClosure desc=bye`. Con `ws.Abort()` en el cliente (sin trama close) el servidor ve la conexión como rota: el mismo `ReceiveAsync` lanza una excepción en lugar de devolver un `Close`. En el servidor de la prueba, pasar `ctx.RequestAborted` al `ReceiveAsync` la convierte en `OperationCanceledException`; sin él, sería `WebSocketException` (el `1006` de la tabla).

## Mantener viva la conexión

Una conexión puede morir sin que nadie lo note: se desenchufa el cable, el móvil cambia de red, el proceso se cuelga. TCP no avisa hasta que intenta escribir y falla. Además, proxies y balanceadores cierran las conexiones **inactivas**: es el caso típico de la conexión que "se cae sola a los 60 segundos" (muchas configuraciones por defecto rondan ese valor; consulta la de la tuya).

La solución son **latidos** (*heartbeats*): tráfico periódico que mantiene la conexión activa y detecta las muertas.

- **Ping/pong del protocolo.** ASP.NET Core envía pings automáticamente cada `KeepAliveInterval` (por defecto, 2 minutos según la documentación consultada el 2026-11-09), y el navegador responde pong sin código. Dos minutos es más que muchos timeouts de proxy: reduce el valor (p. ej. 30 s). Con `KeepAliveTimeout` (desactivado por defecto) el servidor aborta la conexión si no llega el pong.
- **Latidos propios en JSON** (`{"type":"ping"}`/`{"type":"pong"}`): el navegador no expone ping/pong de protocolo a JavaScript, así que para que el cliente web detecte una conexión muerta necesita un latido de aplicación: si pasan, por ejemplo, 2 intervalos sin recibir nada, cierra y reconecta.

```csharp
app.UseWebSockets(new WebSocketOptions
{
    KeepAliveInterval = TimeSpan.FromSeconds(30),
    KeepAliveTimeout = TimeSpan.FromSeconds(15),
});
```

### Reconexión con espera exponencial y *jitter*

Cuando la conexión cae, el cliente reintenta. Si 10 000 clientes reintentan a la vez cada segundo, la recuperación del servidor se convierte en un ataque contra sí mismo. Se espacia con **espera exponencial** (1, 2, 4, 8... hasta un tope) y se le añade **jitter**, una parte aleatoria para que los clientes no vuelvan en la misma oleada. Esta variante ("*full jitter*") espera un tiempo aleatorio entre 0 y el tope de cada intento:

```csharp
var attempt = 0;
while (!ct.IsCancellationRequested)
{
    try
    {
        using var ws = new ClientWebSocket();
        var ticket = await getTicket();                 // ticket nuevo en cada intento
        await ws.ConnectAsync(new Uri($"wss://api.tienda.ejemplo.com/ws?ticket={ticket}"), ct);
        attempt = 0;                                    // conectado: la espera vuelve a empezar
        await ReceiveUntilClosed(ws, ct);               // bucle de recepción de la sección anterior
    }
    catch (Exception e) when (e is WebSocketException or HttpRequestException) { }

    var cap = Math.Min(30.0, Math.Pow(2, attempt++));   // 1, 2, 4, 8, 16, 30, 30...
    await Task.Delay(TimeSpan.FromSeconds(Random.Shared.NextDouble() * cap), ct);
}
```

Esperas generadas en una ejecución (aleatorias, por eso no coinciden con el tope):

```text
intento 0: espera aleatoria entre 0 y 1s -> 0,28s
intento 1: espera aleatoria entre 0 y 2s -> 0,45s
intento 2: espera aleatoria entre 0 y 4s -> 0,60s
intento 3: espera aleatoria entre 0 y 8s -> 1,73s
intento 4: espera aleatoria entre 0 y 16s -> 1,76s
intento 5: espera aleatoria entre 0 y 30s -> 10,48s
```

Reconectar no basta: durante la caída se perdieron mensajes. Al volver, el cliente pide el estado actual (en el panel, el servidor ya envía un `order.snapshot` al conectar) o los mensajes posteriores al último `id` que recibió.

## El protocolo sobre el socket

WebSocket solo transporta mensajes (texto o bytes). **No define qué significan**: ni formato, ni versionado, ni confirmaciones. Sin disciplina, el código se llena de `socket.send("algo")`. El diseño mínimo es un **sobre** (*envelope*) JSON con un `type` que enruta y un `payload` con los datos:

```json
{ "v": 1, "id": "m-1", "type": "support.message",
  "payload": { "orderId": 4711, "text": "Su pedido sale hoy" } }
```

```json
{ "v": 1, "type": "ack", "payload": { "ackId": "m-1" } }
```

- **`type`**: enruta al manejador (`order.status`, `order.snapshot`, `support.message`). Un `type` desconocido se ignora o se responde con un error, no tumba la conexión.
- **`v`** (versión): permite cambiar el formato sin romper a los clientes antiguos que siguen conectados, igual que el versionado de un contrato OpenAPI.
- **`id` y `ack`**: WebSocket garantiza que los bytes llegan en orden por una conexión viva, pero no que la **aplicación** los procesara. Si se cae la conexión, un mensaje en vuelo se pierde sin aviso. El emisor numera sus mensajes, el receptor responde con un `ack` que cita el `id`, y el emisor reenvía los que no se confirmaron al reconectar (con `id` estable para que el receptor descarte los duplicados). Salida real del servidor de prueba: al enviar el cliente `m-1`, el servidor registra `mensaje m-1: {"orderId":4711,"text":"Su pedido sale hoy"}` y responde con el `ack` que se vio arriba.

## Autenticación y origen

El navegador **no permite** poner cabeceras personalizadas como `Authorization` en `new WebSocket(url)`: solo la URL y los subprotocolos. Opciones:

| Opción | Cómo | Pega |
|---|---|---|
| **Ticket de un solo uso en la URL** | La web autenticada pide `POST /ws-tickets`, recibe un ticket aleatorio de vida corta y abre `wss://…/ws?ticket=…`. El servidor lo canjea y lo borra | Requiere el endpoint de tickets; es la opción recomendada |
| **Cookie de sesión** | El navegador la envía en el `GET` del handshake | Hay que validar `Origin` (ver abajo); solo mismo sitio o dominios compatibles |
| **Primer mensaje** | Se conecta sin credenciales y el primer mensaje es `{"type":"auth",...}` | El servidor mantiene una conexión sin autenticar abierta: poner un plazo corto y descartar todo lo demás |

El servidor de prueba valida el ticket en el handshake y lo borra al canjearlo. Sin ticket, el handshake se rechaza antes del `101`:

```http
HTTP/1.1 401 Unauthorized
Content-Length: 0
```

**No pongas un token largo (JWT, token de sesión) en la query string.** Las URLs acaban en registros de acceso del servidor y de los proxys, en el historial del navegador y en herramientas de monitorización, y viven tanto como el token. Un ticket de un solo uso, aleatorio y con caducidad de segundos no sirve de nada a quien lo encuentre después en un log. Sobre cookies y tokens en general: [Sesiones vs Tokens](../../seguridad/autenticacion-y-autorizacion/Sesiones-vs-Tokens.md).

### Comprobar el `Origin` (CSWSH)

Los WebSockets **no están sujetos a la política de mismo origen** del navegador: cualquier página puede abrir `new WebSocket("wss://api.tienda.ejemplo.com/ws")`. Si la autenticación es una cookie, el navegador la adjunta al handshake. Así funciona el ataque *Cross-Site WebSocket Hijacking* (CSWSH): una agente de soporte con sesión abierta visita `https://malo.example`, cuya página abre el WebSocket de la tienda **con la cookie de la agente**, y desde ahí lee los pedidos en vivo o envía mensajes en su nombre.

El navegador envía siempre la cabecera `Origin` con la página que abre el socket, y esa no se puede falsificar desde JavaScript. El servidor debe compararla con una lista de orígenes permitidos. Prueba real contra el servidor de ejemplo:

```bash
curl -i -H "Origin: https://malo.example" -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  "http://127.0.0.1:5437/ws?ticket=…"
```

```http
HTTP/1.1 403 Forbidden
```

```csharp
var allowed = new HashSet<string> { "https://soporte.tienda.ejemplo.com" };
var origin = ctx.Request.Headers.Origin.ToString();
if (origin != "" && !allowed.Contains(origin)) { ctx.Response.StatusCode = 403; return; }
```

`curl` o un cliente de servidor no envían `Origin` (por eso el ejemplo acepta el vacío: la protección es contra navegadores). ASP.NET Core ofrece también `WebSocketOptions.AllowedOrigins`, que por defecto admite todos los orígenes. El ticket de un solo uso, además, es inmune a CSWSH porque la página maliciosa no puede obtenerlo.

## Escalar

Una conexión WebSocket vive atada a **un** proceso y consume un socket y memoria durante toda su vida. Eso rompe la suposición de REST, donde cualquier instancia atiende cualquier petición.

- **Difundir entre instancias.** Si la agente A está conectada a la instancia 1 y la B a la 2, el cambio de estado que llega a la 1 no llega a B. Hace falta un canal entre instancias (*backplane*): un pub/sub como Redis al que cada instancia se suscribe y desde el que reenvía a sus propios clientes. [SignalR](../../desarrollo-web/de-wpf-a-web/SignalR.md) trae backplanes ya hechos; con WebSocket puro lo escribes tú.
- **Afinidad de sesión (*sticky sessions*).** Una vez abierta, la conexión no cambia de instancia, así que el balanceador no necesita afinidad para WebSocket puro. Sí la necesita cualquier protocolo que repita varias peticiones HTTP para una sesión (fallback de SignalR, por ejemplo).
- **Límites.** Cada conexión ocupa un descriptor de socket, búferes y el estado de aplicación, y los balanceadores y proxys tienen un máximo de conexiones y un timeout de inactividad. No hay una cifra universal de "conexiones por servidor": depende del tamaño de los búferes, del estado que guardes por cliente y de la frecuencia de mensajes. Se mide con una prueba de carga propia, abriendo conexiones hasta ver la memoria y la CPU del proceso.
- **Reinicios.** Cada despliegue corta todas las conexiones: el cliente tiene que reconectar y resincronizar (sección anterior), y conviene cerrar con `1001` o un código propio para distinguirlo de un fallo.

## WebSockets, SSE, long polling o polling

| | **WebSockets** | **Server-Sent Events** | **Long polling** | **Polling** |
|---|---|---|---|---|
| Dirección | Bidireccional | Servidor → cliente | Servidor → cliente (la petición espera) | Cliente pregunta |
| Transporte | Conexión TCP propia tras `Upgrade` | Respuesta HTTP que no termina | Peticiones HTTP encadenadas | Peticiones HTTP periódicas |
| Reconexión automática | No: la escribes tú | Sí, en el navegador | La escribes tú (es el bucle) | No hace falta |
| Proxys y balanceadores | Algunos cierran por inactividad o no soportan el `Upgrade` | Funciona como HTTP, aunque algunos proxys acumulan la respuesta | Funciona como HTTP | Funciona como HTTP |
| Cabeceras de autenticación | Solo en clientes que no son navegador | Con `fetch` sí; con `EventSource` no | Sí | Sí |
| Complejidad | Alta | Baja | Media | Mínima |

Más detalle de cada alternativa en [Server-Sent Events](Server-Sent-Events.md) y [Long Polling](Long-Polling.md). Para el panel de soporte: si solo tuviera que **ver** el estado, bastaría SSE; como también **envía** mensajes y se quiere un único canal, WebSockets es razonable (aunque el envío podría ser un `POST` normal junto a SSE).

### WebSockets frente a SignalR

WebSocket es el transporte; [SignalR](../../desarrollo-web/de-wpf-a-web/SignalR.md) es un framework de ASP.NET Core encima, con un protocolo de mensajes ya definido, llamadas a métodos, grupos de usuarios, reconexión y *fallback* a otros transportes. Si el servidor es .NET y el cliente es navegador o .NET, SignalR resuelve gran parte de lo anterior. WebSocket puro conviene cuando hay que hablar con clientes de otro ecosistema que ya usan el protocolo estándar, o se quiere el mínimo de piezas y control del formato.

## Cuándo NO usar WebSockets

- Operaciones normales de petición-respuesta: `POST /orders` es REST, no necesita canal abierto.
- Datos que cambian cada pocos minutos: un sondeo espaciado es más simple y barato.
- Solo servidor → cliente: SSE, con reconexión incluida, es más simple.
- Cuando hay que aprovechar caché HTTP, CDN o la telemetría habitual de peticiones: una conexión persistente propia no se beneficia de ninguna.
- Entornos con proxys corporativos que bloquean el `Upgrade`, si no puedes controlar la red del cliente.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| La conexión se cae sola cada ~60 s sin errores en la aplicación | Un proxy o balanceador cierra las conexiones inactivas. Sin latidos no hay tráfico: añade ping/pong o latidos propios con intervalo inferior al timeout |
| El `JSON.parse` o `JsonDocument.Parse` falla con mensajes largos, de forma intermitente | Se asume una lectura = un mensaje. Acumula hasta `EndOfMessage` (ver el bucle de recepción) |
| `Send` desde varias tareas sobre el mismo socket | No hay garantía de que sea seguro enviar a la vez por el mismo socket: serializa con un `SemaphoreSlim` por conexión (ver `Client`). En la prueba con .NET 10 (200 envíos concurrentes de 1000 bytes) no apareció una excepción, pero eso no es una garantía de comportamiento |
| Cada vez hay más conexiones "conectadas" que usuarios reales | No se limpia al cerrar: quitar el cliente de la colección en un `finally`, también cuando `ReceiveAsync` lanza |
| Un cliente lento o muerto congela las actualizaciones de todos | Difundir bajo un `lock` o esperando cada `SendAsync` en serie: un `await` lento bloquea a los demás. Envía en paralelo con timeout y descarta a quien no avance |
| Tras caerse la red, el panel muestra datos antiguos | Se reconecta sin resincronizar: pide el estado actual o los mensajes posteriores al último `id` |
| Todos los clientes reconectan a la vez tras un reinicio y el servidor vuelve a caer | Reconexión sin espera exponencial ni jitter |

## Buenas prácticas avanzadas

- **Reconectar no basta: hay que resincronizar.** Tras una caída, el cliente se ha perdido mensajes. Numera los mensajes (o sella el último recibido) y, al reconectar, pide lo pendiente o un *snapshot* completo del estado.
- **Latidos propios, porque TCP no avisa.** Una conexión puede quedar "zombi" (cable desenchufado, móvil que cambia de red) sin error en ningún lado. Envía pings periódicos y da por muerta la conexión si no llega el pong; si no, el servidor acumula conexiones fantasma y el cliente cree estar conectado sin recibir nada.
- **Define el protocolo de mensajes desde el principio.** Sobre con `type`, `payload`, `v`, `id` y `ack`, y enruta por `type`. Es la diferencia entre un canal mantenible y un cajón de cadenas mágicas.
- **Limita el tamaño del mensaje y el número de conexiones por usuario.** Sin límites, un cliente puede agotar la memoria del proceso.
- **Valida cada mensaje como una petición HTTP más.** La autorización se comprueba en el handshake, pero cada mensaje (`support.message` sobre el pedido 4711) debe volver a comprobar que esa persona puede actuar sobre ese pedido.
- **Envía sin bloquear.** Una cola por conexión (o `Channel<T>`) con un tope: si un cliente no consume, se le cierra con `1008` en lugar de que retrase a todos.

## Documentación oficial

- [RFC 6455: The WebSocket Protocol](https://www.rfc-editor.org/rfc/rfc6455): la sección 1.3 (apretón de manos), la 5 (tramas) y la 7.4 (códigos de cierre) cuando haya que entender qué viaja por la red.
- [WebSockets en ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/websockets): `UseWebSockets`, `WebSocketOptions` (`KeepAliveInterval`, `KeepAliveTimeout`, `AllowedOrigins`) y la gestión de desconexiones.
- [WebSocket API en MDN](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket): eventos, `readyState`, `CloseEvent` y límites del cliente del navegador; y la [introducción a la API de WebSockets](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API) para el uso básico.

---

*En resumen: WebSockets es una línea abierta entre cliente y servidor donde cada lado habla cuando quiere, pero a cambio la conexión, los latidos, la reconexión, el formato y la seguridad son cosa tuya.*
