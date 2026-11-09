# Long Polling

## ¿Qué es?

Una técnica para recibir avisos del servidor usando solo peticiones HTTP corrientes: el cliente pregunta «¿hay algo nuevo?» y el servidor **retiene la petición sin responder** hasta que haya una novedad o venza un tiempo límite. En cuanto el cliente recibe respuesta, vuelve a preguntar de inmediato.

## ¿Por qué existe?

HTTP está pensado para que el cliente pregunte y el servidor conteste; el servidor no puede escribirle al cliente por iniciativa propia. Si una pantalla de la tienda online tiene que enterarse de que el pedido `4711` ha pasado de `paid` a `shipped`, la solución ingenua es el **polling corto**: preguntar cada segundo. Casi todas las respuestas son «sigue igual», así que se paga el coste de una petición completa (cabeceras, autenticación, consulta a base de datos) para no enterarse de nada. Y aun así el aviso llega tarde: hasta un segundo después del cambio.

Long polling cambia quién espera. En vez de contestar «no hay nada» al momento, el servidor deja la petición abierta y contesta cuando ocurre algo. Se consigue casi tiempo real sin protocolos nuevos, y por eso funciona donde [WebSockets](WebSockets.md) o [Server-Sent Events](Server-Sent-Events.md) no están disponibles.

> Polling corto es llamar al timbre cada minuto por si ha llegado el paquete. Long polling es llamar una vez y que el portero no cuelgue hasta que el paquete llegue o se canse de esperar.

## ¿Cuándo y para qué se usa?

- **Infraestructura que solo deja pasar HTTP clásico**: proxys corporativos que cortan WebSockets o que almacenan en búfer las respuestas de SSE.
- **Clientes antiguos o limitados**: dispositivos, navegadores o librerías sin soporte de las alternativas.
- **Avisos poco frecuentes**: un cambio de estado de pedido cada pocos minutos no justifica mantener un canal bidireccional.
- **Respaldo**: bibliotecas de tiempo real intentan WebSockets y, si fallan, caen a long polling.

Para un proyecto nuevo sin esas restricciones, lo habitual es empezar por SSE o WebSockets (ver la tabla de decisión más abajo).

## El intercambio, paso a paso

El cliente pide los eventos del pedido posteriores al último que conoce. `since` es ese cursor; el significado completo se explica en la sección de eventos perdidos. Un servidor mínimo (el de más abajo) devuelve `204` si no pasa nada durante el tiempo de espera. Salida real con `curl`, con una espera de 3 segundos:

```bash
curl -i "localhost:5637/orders/4711/events?since=16&timeout=3"
```

```http
HTTP/1.1 204 No Content
Date: Mon, 09 Nov 2026 09:23:23 GMT
Server: Kestrel
```

`curl` tardó 3,1 s en recibir esa respuesta vacía: la petición estuvo retenida todo ese tiempo. Si mientras tanto alguien cambia el pedido (`POST /orders/4711/status` con `{"status":"paid"}`), la misma petición termina antes con `200`. En este caso, el cambio se hizo a los 2 s y `curl` tardó 2,06 s:

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

{"events":[{"id":17,"orderId":4711,"status":"paid"}]}
```

Ciclo completo del cliente:

1. Pide `GET /orders/4711/events?since=16`.
2. El servidor retiene la petición.
3. Ocurre un evento (`200` con el cuerpo) o vence el tiempo (`204` sin cuerpo).
4. El cliente procesa lo recibido y vuelve al paso 1, ahora con `since=17` si recibió el evento 17, o con el mismo cursor si fue un `204`.

Los textos que ve una persona (por ejemplo «Tu pedido ha sido enviado») los compone la interfaz a partir de `status`; el cuerpo solo lleva datos.

## Cuánto cuesta frente al polling corto

Una medición con el mismo escenario para ambos: la pantalla observa el pedido `4711` durante 60 segundos y el pedido cambia **una sola vez**, a los 30 s. Se midió con `curl` contra el servidor mínimo de la sección siguiente, en una sola máquina y sin TLS (consulta: 2026-11-09). Los bytes son los de la petición y la respuesta HTTP (`size_request` + `size_header` + `size_download` de `curl`), sin contar TCP ni TLS.

| | Polling corto (cada 1 s) | Long polling (espera de 25 s) |
|---|---|---|
| Peticiones en 60 s | 60 | 4 (tres `204` y un `200`) |
| Bytes intercambiados | 20 244 | 908 |
| Retraso entre el cambio y el aviso | entre 0 y 1 s (según el momento) | 0,10 s en la medición |

Son cifras de este escenario, no una constante: dependen de la frecuencia de los cambios, del tamaño de las cabeceras (con cookies o un JWT en cada petición el polling corto pesa mucho más) y de lo que devuelva cada respuesta. En el polling corto de la prueba cada respuesta devolvía el pedido completo (102 bytes); con `ETag` y `304 Not Modified` pesaría menos, aunque seguiría siendo una petición por segundo. Cuantos más cambios haya por minuto, más se acercan ambas técnicas: con un evento por segundo, long polling hace tantas peticiones como el polling corto.

## Servidor mínimo en ASP.NET Core

La clave es esperar **sin ocupar un hilo**: la petición `await`ea una tarea que se completa cuando llega un evento, y un `CancellationToken` con tiempo límite corta la espera. Hay tres piezas:

- Un registro de eventos con id creciente. Aquí vive en memoria; en producción sería la base de datos o un almacén de eventos (ver las buenas prácticas).
- Un `TaskCompletionSource` que se completa en cada `Append` para despertar a todas las peticiones retenidas.
- Un endpoint que primero mira si ya hay eventos posteriores al cursor y, si no, espera.

```csharp
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();
var log = new OrderEventLog(firstId: 17);

app.MapPost("/orders/4711/status", (StatusChange change) => Results.Json(log.Append(change.Status)));

app.MapGet("/orders/4711/events", async (long since, int? timeout, HttpContext ctx) =>
{
    var pending = log.After(since);
    if (pending.Count > 0) return Results.Json(new { events = pending });   // hay algo: respuesta inmediata

    using var cts = CancellationTokenSource.CreateLinkedTokenSource(ctx.RequestAborted);
    cts.CancelAfter(TimeSpan.FromSeconds(timeout ?? 25));                    // tiempo máximo de retención
    try
    {
        return Results.Json(new { events = await log.WaitForAfterAsync(since, cts.Token) });
    }
    catch (OperationCanceledException) when (!ctx.RequestAborted.IsCancellationRequested)
    {
        return Results.NoContent();                                          // venció el tiempo: 204
    }
});

app.Run();

record StatusChange(string Status);
record OrderEvent(long Id, int OrderId, string Status);

class OrderEventLog(long firstId)
{
    private readonly object _gate = new();
    private readonly List<OrderEvent> _events = new();
    private long _next = firstId;
    private TaskCompletionSource _signal = NewSignal();

    static TaskCompletionSource NewSignal() => new(TaskCreationOptions.RunContinuationsAsynchronously);

    public OrderEvent Append(string status)
    {
        TaskCompletionSource old; OrderEvent ev;
        lock (_gate)
        {
            ev = new OrderEvent(_next++, 4711, status);
            _events.Add(ev);
            old = _signal;
            _signal = NewSignal();      // las próximas peticiones esperarán a esta nueva señal
        }
        old.SetResult();                // despierta a todas las peticiones retenidas
        return ev;
    }

    public List<OrderEvent> After(long since) { lock (_gate) return _events.Where(e => e.Id > since).ToList(); }

    public async Task<List<OrderEvent>> WaitForAfterAsync(long since, CancellationToken ct)
    {
        while (true)
        {
            Task signal;
            lock (_gate)
            {
                var pending = _events.Where(e => e.Id > since).ToList();
                if (pending.Count > 0) return pending;
                signal = _signal.Task;  // se captura bajo el cerrojo: no se pierde un Append intermedio
            }
            await signal.WaitAsync(ct);
        }
    }
}
```

Tres detalles importan:

- **Comprobar y capturar la señal bajo el mismo cerrojo.** Si se mirase la lista, se soltase el cerrojo y luego se tomase la señal, un `Append` en medio dejaría la petición esperando una señal que ya nadie va a completar.
- **`RunContinuationsAsynchronously`.** Sin él, `SetResult` ejecutaría las continuaciones de las peticiones retenidas dentro del hilo de quien llama a `Append`.
- **Distinguir el timeout propio del aborto del cliente.** El `when (!ctx.RequestAborted.IsCancellationRequested)` evita responder `204` a un cliente que ya se fue.

Para una cola con un solo consumidor, un `Channel<T>` encaja igual de bien; el `TaskCompletionSource` es preferible aquí porque muchas peticiones esperan **el mismo** evento (difusión) y un `Channel` entrega cada elemento a un solo lector.

## El cliente: bucle de reintento

El cliente repite la pregunta mientras la aplicación esté abierta. Lo que lo diferencia de un `while (true)` ingenuo es lo que hace cuando algo falla: un servidor caído que responde error al instante convertiría el bucle en un martilleo de miles de peticiones por segundo, por eso se espera antes de reintentar, con tiempos crecientes.

```csharp
var http = new HttpClient
{
    BaseAddress = new Uri("https://api.tienda.ejemplo.com"),
    Timeout = TimeSpan.FromSeconds(40)    // mayor que los 25 s de espera del servidor
};

long since = 16;
var failures = 0;
while (true)
{
    try
    {
        using var res = await http.GetAsync($"/orders/4711/events?since={since}");
        if (res.StatusCode == HttpStatusCode.NoContent) { failures = 0; continue; }   // sin novedades: preguntar de nuevo
        res.EnsureSuccessStatusCode();

        var body = await res.Content.ReadFromJsonAsync<EventsResponse>();
        foreach (var e in body!.Events)
        {
            Console.WriteLine($"evento {e.Id}: pedido {e.OrderId} -> {e.Status}");
            since = e.Id;                 // el cursor avanza solo después de procesar el evento
        }
        failures = 0;
    }
    catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
    {
        failures++;
        var delay = TimeSpan.FromSeconds(Math.Min(30, Math.Pow(2, failures - 1)))
                  + TimeSpan.FromMilliseconds(Random.Shared.Next(0, 1000));           // espera creciente con jitter
        await Task.Delay(delay);
    }
}

record OrderEvent(long Id, int OrderId, string Status);
record EventsResponse(List<OrderEvent> Events);
```

Ejecutado contra el servidor (con una espera de 5 s para ver el ciclo), con un cambio a los 7 s y el servidor detenido a los 13 s:

```text
[  5.2s] 204 sin novedades, vuelvo a preguntar
[  7.0s] evento 17: pedido 4711 -> paid
[ 12.1s] 204 sin novedades, vuelvo a preguntar
[ 13.9s] fallo (HttpRequestException), reintento en 1.1s
[ 19.0s] fallo (HttpRequestException), reintento en 2.5s
```

El evento llega en el instante del cambio (7,0 s), el `204` no se trata como error, y con el servidor caído las esperas crecen en lugar de repetirse sin pausa.

## Eventos perdidos entre dos peticiones

Entre que el servidor responde y el cliente vuelve a preguntar hay un hueco, de milisegundos o de segundos si el cliente está procesando. Lo que ocurra en ese hueco se pierde si el servidor solo entrega «lo que llegue a partir de ahora». Es el fallo característico de long polling.

Secuencia real contra una variante del servidor que no usa cursor (cada petición espera «el siguiente evento»). El cliente recibe el cambio a `paid`, tarda 2 s en procesarlo, y a los 0,5 s de ese procesado el pedido pasa a `shipped`:

```text
# ❌ Sin cursor
peticion 1:           200  {"id":17,"orderId":4711,"status":"paid"}
(el cliente procesa 2 s)
servidor, a los 0.5 s: evento 18 -> shipped          # nadie estaba escuchando
peticion 2:           204                             # el evento 18 no llega nunca
```

El cliente se queda con `paid` aunque el pedido está enviado, y no hay error ni registro de que algo falló. La solución es que el cliente diga hasta dónde ha leído y el servidor devuelva todo lo posterior, esté o no el cliente escuchando en ese momento:

```text
# ✅ Con cursor (?since=<último id procesado>)
GET /orders/4711/events?since=16  ->  200  {"events":[{"id":17,"orderId":4711,"status":"paid"}]}
(el cliente procesa 2 s)
servidor, a los 0.5 s: evento 18 -> shipped
GET /orders/4711/events?since=17  ->  200  {"events":[{"id":18,"orderId":4711,"status":"shipped"}]}   # inmediato
```

Dos consecuencias de usar cursor:

- **Los reintentos no duplican el proceso.** Si la respuesta se pierde en la red y el cliente repite la pregunta con el cursor anterior, recibe otra vez el mismo evento con el mismo `id`; el cliente puede descartar los ids que ya procesó. Sin ids, el reintento del cliente procesaría dos veces el mismo cambio (dos correos de «tu pedido ha sido enviado»).
- **El cursor debe sobrevivir al servidor.** En una prueba, el servidor de ejemplo (registro en memoria) se reinició y empezó otra vez en el id 17 mientras el cliente ya tenía `since=17`: el primer evento nuevo quedó oculto. Los ids tienen que salir de un almacén duradero (una secuencia de la base de datos, la tabla de eventos o un [outbox](../../devops/mensajeria-asincrona/Outbox-Pattern.md)). Si el cursor del cliente es posterior al último id del servidor, lo razonable es que el cliente recargue el estado completo con `GET /orders/4711`.

Esto es el equivalente de `Last-Event-ID` en [Server-Sent Events](Server-Sent-Events.md), que lo incorpora al estándar; en long polling hay que construirlo a mano.

## Reparto de timeouts

Hay tres cronómetros en juego: el del servidor (cuánto retiene la petición), el del cliente (cuánto espera antes de rendirse) y el de cada proxy, balanceador o cortafuegos intermedio (cuánto tolera una conexión sin tráfico). La regla es que **el servidor responda siempre antes que los demás**:

```text
timeout del servidor  <  timeout de proxys y balanceadores  y  <  timeout del cliente
        25 s                         60 s (ejemplo)                   40 s
```

Qué pasa si no se cumple, con los 25 s del servidor como referencia:

| Reparto | Qué se corta primero | Síntoma |
|---|---|---|
| Cliente con 20 s, servidor con 25 s | El cliente se rinde antes | `TaskCanceledException` (o `curl` con código de salida 28) cada 20 s; si el bucle lo trata como fallo, entra en espera creciente y los avisos se retrasan |
| Servidor con 90 s, proxy con 60 s | El proxy corta a los 60 s | `504 Gateway Timeout` o conexión cerrada cada 60 s; el cliente lo ve como un fallo de verdad y la gráfica de errores no distingue «sin novedades» de «roto» |
| Servidor con 60 s, proxy con 60 s | Empate: gana el que se dispare primero | Errores intermitentes e imposibles de reproducir a voluntad |
| Servidor con 25 s, proxy con 60 s, cliente con 40 s | Nada: gana el servidor | `204` limpio cada 25 s |

La primera fila se reprodujo: `curl -m 5` contra una espera de 25 s termina a los 5 s sin respuesta y con salida 28. El resto de filas son el comportamiento esperado de un proxy genérico y no se midió con un proxy real.

Los valores por defecto de cada producto (nginx, Azure, AWS, Cloudflare…) cambian con las versiones y no se han comprobado aquí: antes de elegir los segundos del servidor, mira el timeout de inactividad configurado en cada intermediario de la ruta y deja margen. La RFC 6202 (sección «Timeouts») recomienda como valor seguro unos 30 segundos y cita experimentos con éxito hasta 120 s.

## Coste en el servidor: una conexión, no un hilo

Cada petición retenida ocupa una conexión abierta y algo de memoria, pero **con `async`/`await` no ocupa ningún hilo**: mientras espera, el hilo vuelve al pool. Se comprobó con un cliente de prueba en C# que abre 1000 peticiones simultáneas y, a los 10 s, mide el servidor y lo que tarda otra petición cualquiera (.NET 10, una sola máquina con Windows, cliente y servidor en la misma máquina, una ejecución; las cifras ilustran la diferencia, no son un benchmark):

| 1000 peticiones retenidas | Espera con `await` | Espera con `Thread.Sleep` |
|---|---|---|
| Hilos del proceso del servidor | 31 en reposo → 45 | (pool agotado) |
| Memoria (working set) | 49 → 66 MB | — |
| `GET /orders/4711` mientras tanto | 12 ms | sin respuesta tras 30 s |
| Entrega de un evento a las 1000 | 48 ms, las 1000 con `200` | 50 s, ninguna llegó dentro del timeout de 40 s del cliente |

El endpoint bloqueante hacía `while (...) { Thread.Sleep(100); }`. Con 1000 peticiones, el pool de hilos (que crece despacio) se queda sin hilos libres y **toda la aplicación** deja de responder, no solo ese endpoint. Con la espera asíncrona, las 1000 conexiones conviven con un servidor que sigue atendiendo en milisegundos.

Los límites reales pasan a ser los de las conexiones: descriptores de archivo o puertos del sistema operativo, el máximo de conexiones del servidor web o del balanceador, y la memoria por conexión. Con decenas de miles de clientes simultáneos conviene medirlo en el entorno de destino.

## La estampida tras un despliegue

Si el servidor se reinicia, **todos** los clientes pierden su petición retenida a la vez y reconectan a la vez. El servidor que acaba de arrancar, con los cachés vacíos, recibe de golpe miles de peticiones: es el efecto *thundering herd* (estampida), y puede tumbarlo otra vez, lo que provoca otra oleada.

La mitigación es el **jitter**: un componente aleatorio en la espera antes de reconectar, para que los clientes se repartan en el tiempo. El bucle de cliente de arriba ya lo lleva (`Random.Shared.Next(0, 1000)` milisegundos sumados a la espera creciente). Si el despliegue sincroniza también los timeouts normales (todos los clientes arrancaron a la vez), conviene que el servidor varíe unos segundos el tiempo de retención de cada petición, por ejemplo entre 20 y 30 s en lugar de 25 fijos. La estampida no se midió.

## Límites de conexiones por navegador

Cada petición retenida usa una conexión durante todo su tiempo de espera. Con HTTP/1.1, los navegadores limitan las conexiones simultáneas por dominio. La RFC 6202 (2011) cita límites de 6 u 8 en los navegadores de entonces; el valor actual por navegador no se ha verificado aquí. El efecto práctico es el mismo: si una pestaña mantiene dos long polls abiertos y el límite es 6, solo quedan 4 conexiones para el resto de peticiones de esa pestaña y de todas las demás pestañas abiertas hacia el mismo dominio. Con muchas pestañas abiertas, la tienda deja de cargar imágenes y datos porque todas las conexiones están ocupadas esperando.

Mitigaciones: un único long poll por pantalla que reciba todos los tipos de evento (en vez de uno por recurso), un dominio aparte para los avisos, o HTTP/2 (que multiplexa muchas peticiones sobre una conexión; el límite de flujos concurrentes depende del servidor y no se comprobó).

## ¿Long polling, SSE, WebSockets o polling?

| Situación | Elección | Motivo |
|---|---|---|
| Cambios frecuentes, solo servidor → cliente (estado de pedidos, notificaciones) | [Server-Sent Events](Server-Sent-Events.md) | Una conexión, reconexión automática y `Last-Event-ID` incluidos en el estándar |
| Comunicación en ambos sentidos con baja latencia (chat, edición colaborativa) | [WebSockets](WebSockets.md) | Canal bidireccional persistente |
| Avisos poco frecuentes, o solo HTTP clásico disponible (proxys que cortan SSE/WebSockets, clientes antiguos) | Long polling | Funciona en cualquier sitio donde funcione una petición `GET` |
| Respaldo cuando fallan las anteriores | Long polling | Es la opción de último recurso |
| Hay que consultar un estado de vez en cuando, sin urgencia (panel que se actualiza cada minuto) | Polling corto | Es lo más simple, no mantiene conexiones, se cachea; basta con espaciar las peticiones |
| Un sistema externo avisa a tu servidor | [Webhooks](Webhooks.md) | Servidor a servidor, sin cliente esperando |

Solo [WebSockets](WebSockets.md) y [SSE](Server-Sent-Events.md) mantienen una conexión que el servidor puede usar en cualquier momento; en long polling, entre una respuesta y la siguiente petición no hay canal.

[SignalR](../../desarrollo-web/de-wpf-a-web/SignalR.md) lo usa como último recurso: intenta WebSockets, después SSE y, si ninguno funciona, long polling.

## Cuándo no usarlo

- Si ya hay WebSockets o SSE disponibles y funcionan en toda la ruta, es más simple y eficiente usarlos.
- Si los avisos son tan frecuentes que cada petición devuelve algo, el coste por cambio (una petición completa con cabeceras) se parece al del polling corto.
- Si el cliente tiene que enviar mucho al servidor: el long polling es solo del servidor al cliente; lo demás son peticiones aparte.
- Si hay miles de clientes por servidor y el entorno no admite conexiones largas, el coste de conexiones abiertas manda sobre la sencillez del protocolo.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| El servidor se satura y la CPU sube cuando cae una dependencia o el servidor | Bucle de reconexión sin espera: cada fallo inmediato provoca otra petición al instante |
| Toda la aplicación se queda sin responder con pocos cientos de clientes en espera | Hilos bloqueados en la espera (`Thread.Sleep`, `.Result`, `.Wait()`) en lugar de `await` |
| Errores `504` o cortes secos exactamente cada 60 s (o la cifra del proxy) | El timeout del servidor coincide o supera el del proxy o balanceador |
| `TaskCanceledException` periódicas en el cliente, sin que el servidor falle | `HttpClient.Timeout` menor que la espera del servidor |
| El cliente se queda con un estado antiguo sin ningún error | Sin cursor: un evento ocurrido entre dos peticiones se perdió |
| Un correo o un cargo se ejecuta dos veces | Reintentos sin id de evento: el cliente procesa de nuevo lo que ya había procesado |
| Tras reiniciar el servidor, los clientes dejan de recibir avisos durante un rato | Ids de evento en memoria que empiezan de nuevo, o cursores más altos que los del servidor |
| Las demás peticiones de la página tardan o se quedan en pendiente | Se agotaron las conexiones por dominio del navegador con long polls abiertos |

## Buenas prácticas avanzadas

- **Avanza el cursor solo después de procesar el evento.** Si se actualiza al recibir la respuesta y la aplicación falla a mitad de proceso, el evento no se vuelve a pedir; si se actualiza después, el peor caso es recibirlo dos veces, que el id permite descartar.
- **Devuelve un lote, no un solo evento.** Si el cliente tardó y hay tres eventos pendientes, entrégalos en una respuesta (`events: [...]`): evita tres idas y vueltas y, con ellas, tres huecos donde perder eventos.
- **Haz que el `204` sea una respuesta normal, no un error.** Tampoco lo registres como fallo en métricas ni alertas: cada 25 s por cliente es lo esperado. Mide en cambio el tiempo de retención y la cantidad de peticiones retenidas.
- **Propaga la cancelación.** Al enlazar el `CancellationToken` de la petición, cuando el cliente se va el servidor deja de esperar y libera la entrada; sin él, cada cliente que cierra la pestaña deja una espera zombi hasta que venza su timeout.
- **Pon un tope a la espera aunque no haya proxys.** Un servidor sin límite acumula peticiones de clientes que se fueron sin cerrar bien la conexión; el tope garantiza que todo se libera.
- **Valida el cursor.** Un `since` mayor que el último id o negativo es un cliente con estado inválido; responde un error claro (por ejemplo `409`) para que recargue el estado completo en vez de esperar eternamente.

## Documentación oficial

- [RFC 6202: Known Issues and Best Practices for the Use of Long Polling and Streaming in Bidirectional HTTP](https://www.rfc-editor.org/rfc/rfc6202) — la sección 2 describe long polling y sus problemas (latencia máxima, recursos, timeouts); la sección 5 recoge las prácticas HTTP (límite de conexiones y timeouts) y es la que conviene leer antes de fijar tiempos.

---

*En resumen: long polling es preguntar y que el servidor no conteste hasta tener algo —con un cursor para no perder eventos entre dos preguntas, un timeout de servidor menor que el de todo lo demás y una espera asíncrona que no cueste hilos.*
