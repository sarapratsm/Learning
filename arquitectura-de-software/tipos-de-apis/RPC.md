# RPC

## ¿Qué es?

**RPC** (*Remote Procedure Call*, llamada a procedimiento remoto) es un estilo de API en el que el cliente invoca una **función con nombre** que se ejecuta en otra máquina, pasándole argumentos y recibiendo un resultado. El contrato es la lista de funciones disponibles, no un conjunto de recursos con URL.

## ¿Por qué existe?

Algunas operaciones son verbos del negocio, no datos: cancelar un pedido, capturar un cobro, reiniciar un servidor, calcular un envío. Un programador sabe llamar a una función (`order.Cancel("reason")`); RPC propone lo mismo con la función en otra máquina: el cliente llama, el servidor ejecuta y devuelve el resultado.

La analogía es el teléfono de una tienda: no se pide «el recurso pedido 4711 con el estado cancelado», se dice «cancelen el pedido 4711, por duplicado». Quien atiende ejecuta la orden y confirma.

Es el estilo más antiguo de comunicación entre sistemas. [SOAP](SOAP.md) y [gRPC](gRPC.md) son RPC con reglas, formatos y herramientas propios; aquí se trata la idea general que comparten y el protocolo más pequeño que la ilustra, JSON-RPC 2.0.

## ¿Cuándo y para qué se usa?

Encaja cuando la API es un conjunto de **acciones**: pasarelas de pago (`capture`, `refund`), comunicación entre microservicios propios, herramientas internas, protocolos de editor (el *Language Server Protocol* usa JSON-RPC) y cualquier sitio donde «llamo a esta función con estos argumentos» sea el modelo mental natural. Encaja peor en APIs públicas de datos con jerarquía (clientes, pedidos, líneas), donde [REST](REST.md) aprovecha mejor HTTP.

## El problema: cancelar un pedido en REST puro

En la tienda online, el pedido `4711` está pagado y la persona quiere cancelarlo. Con recursos y verbos HTTP hay que decidir cómo se representa un verbo:

```http
# ❌ Opción A: cambiar el estado con PATCH
PATCH /orders/4711
{ "status": "cancelled" }
```

El cliente puede intentar cualquier transición (`shipped` → `pending`) y el servidor tiene que adivinar que lo que se pidió era «cancelar», con sus efectos: reembolso, reponer stock, avisar. El motivo no tiene dónde ir, porque no es un campo del pedido.

```http
# ❌ Opción B: DELETE
DELETE /orders/4711
```

`DELETE` promete que el recurso deja de existir, pero un pedido cancelado debe conservarse (contabilidad, atención al cliente). Se acaba devolviendo `200` con el pedido «borrado» que sigue ahí.

```http
# ✅ Opción C: la cancelación como sub-recurso (REST válido)
POST /orders/4711/cancellation
{ "reason": "Duplicado" }

# ✅ Opción D: acción explícita sobre el recurso (estilo RPC sobre HTTP)
POST /orders/4711:cancel
{ "reason": "Duplicado" }

# ✅ Opción E: método RPC con parámetros
POST /rpc
{ "jsonrpc": "2.0", "method": "CancelOrder",
  "params": { "orderId": 4711, "reason": "Duplicado" }, "id": 1 }
```

Las tres últimas dicen lo que pasa y dejan sitio al motivo. La opción C sigue siendo REST (inventa un recurso, la cancelación); D y E asumen que la operación es un verbo y lo nombran sin rodeos. Cuando una buena parte de la API son verbos, RPC evita el esfuerzo de modelarlos como sustantivos.

## La ilusión peligrosa: una llamada remota no es una llamada local

Muchas librerías RPC generan código para que `await orderService.CancelOrderAsync(4711, "Duplicado")` parezca una función normal. Es cómodo y es la trampa fundacional del estilo: entre el cliente y la función hay red, y la red falla de formas que una llamada local no conoce.

Las «falacias de la computación distribuida» (formuladas en Sun Microsystems en los años 90) son suposiciones falsas que se hacen al tratar lo remoto como local. Las que más pesan en RPC:

| Falacia | Realidad | Consecuencia en el cliente |
|---|---|---|
| La red es fiable | Los paquetes se pierden, las conexiones se cortan | La llamada puede no llegar o no volver |
| La latencia es cero | Una llamada local tarda nanosegundos; una remota, milisegundos o segundos | Un bucle con una llamada por iteración es lento sin parecerlo |
| El ancho de banda es infinito | Resultados grandes saturan el enlace | Devolver objetos enormes «porque es cómodo» cuesta |
| La red es segura | Cualquiera en medio puede mirar o alterar | Cifrar (TLS) y autenticar cada llamada |
| La topología no cambia | Servidores se mueven, caen y se reemplazan | No fijar direcciones; tolerar reconexiones |

### El caso que lo hace tangible: timeout con cobro hecho

Un cliente llama a `ChargeOrder`, el servidor tarda 3 segundos y el cliente tiene un timeout de 1. Se probó contra el servidor de la siguiente sección, con `curl --max-time 1`:

```bash
curl -s --max-time 1 -X POST http://localhost:5871/rpc \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"ChargeOrder","params":{"orderId":4713,"delayMs":3000},"id":20}'
echo "curl exit=$?"
```

```text
curl exit=28
```

Salida del servidor, instantes después:

```text
[servidor] COBRO #1 del pedido 4713
```

El cliente ve un error (código 28, timeout) y el servidor sí cobró. Un `catch` que trate el timeout como «no pasó nada» y reintente cobra dos veces. El timeout no significa «falló»: significa «no sé qué pasó».

## JSON-RPC 2.0: el RPC más pequeño que existe

JSON-RPC 2.0 es una especificación de una página ([jsonrpc.org/specification](https://www.jsonrpc.org/specification)) que define solo el formato de los mensajes, no el transporte: puede ir sobre HTTP, WebSockets o un socket. Define cuatro piezas:

| Pieza | Campos | Significado |
|---|---|---|
| Petición | `jsonrpc: "2.0"`, `method`, `params` (opcional, objeto o array), `id` | Llama al método `method` |
| Respuesta correcta | `jsonrpc`, `result`, `id` | El `id` coincide con el de la petición |
| Respuesta de error | `jsonrpc`, `error: { code, message, data? }`, `id` | `code` es un entero |
| Notificación | Petición **sin** `id` | El servidor no responde |

Los códigos de error reservados por la especificación:

| Código | Significado |
|---|---|
| `-32700` | Parse error: el JSON recibido no es válido |
| `-32600` | Invalid Request: no es una petición válida |
| `-32601` | Method not found |
| `-32602` | Invalid params |
| `-32603` | Internal error |
| `-32000` a `-32099` | Reservados para errores del servidor definidos por la implementación |

La especificación reserva el rango de `-32768` a `-32000` para sus propios errores. Los errores de negocio pueden usar la banda de `-32000` a `-32099` (como `-32001` y `-32002` en los ejemplos) o códigos fuera de ese rango.

### El servidor de la tienda

Un servidor mínimo de ASP.NET Core (.NET 10) con tres métodos: `GetOrderStatus`, `CancelOrder` y `ChargeOrder` (este último para la sección de idempotencia). Un único endpoint `POST /rpc` que acepta una petición o un array de ellas (lote):

```csharp
using System.Text.Json;
using System.Text.Json.Nodes;

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls("http://localhost:5871");
var app = builder.Build();

var orders = new Dictionary<int, string> { [4711] = "paid", [4712] = "pending", [4713] = "shipped" };

app.MapPost("/rpc", async (HttpRequest http) =>
{
    JsonNode? body;
    try { body = await JsonNode.ParseAsync(http.Body); }
    catch (JsonException) { return Results.Json(Error(null, -32700, "Parse error")); }

    if (body is JsonArray batch)
    {
        if (batch.Count == 0) return Results.Json(Error(null, -32600, "Invalid Request"));
        var replies = batch.Select(Handle).Where(r => r is not null).ToArray();
        return replies.Length == 0 ? Results.StatusCode(204) : Results.Json(new JsonArray(replies));
    }
    var reply = Handle(body);
    return reply is null ? Results.StatusCode(204) : Results.Json(reply);
});

app.Run();

JsonNode? Handle(JsonNode? req)
{
    if (req is not JsonObject o || o["jsonrpc"]?.ToString() != "2.0"
        || o["method"] is not JsonValue m || m.GetValueKind() != JsonValueKind.String)
        return Error(null, -32600, "Invalid Request");

    var hasId = o.ContainsKey("id");               // sin id = notificación
    var id = hasId ? o["id"]?.DeepClone() : null;
    var p = o["params"] as JsonObject;
    JsonNode? reply;

    switch (m.GetValue<string>())
    {
        case "GetOrderStatus":
            if (p?["orderId"] is not JsonValue ov || !ov.TryGetValue<int>(out var oid))
            { reply = Error(id, -32602, "Invalid params"); break; }
            reply = orders.TryGetValue(oid, out var st)
                ? Ok(id, new JsonObject { ["orderId"] = oid, ["status"] = st })
                : Error(id, -32001, "Pedido no encontrado", new JsonObject { ["orderId"] = oid });
            break;

        case "CancelOrder":
            if (p?["orderId"] is not JsonValue cv || !cv.TryGetValue<int>(out var cid))
            { reply = Error(id, -32602, "Invalid params"); break; }
            if (!orders.TryGetValue(cid, out var current) || current == "shipped")
            { reply = Error(id, -32002, "El pedido ya no se puede cancelar", new JsonObject { ["orderId"] = cid }); break; }
            orders[cid] = "cancelled";
            reply = Ok(id, new JsonObject { ["orderId"] = cid, ["status"] = "cancelled", ["refund"] = current == "paid" });
            break;

        default:
            reply = Error(id, -32601, "Method not found");
            break;
    }
    return hasId ? reply : null;                   // una notificación no recibe respuesta
}

JsonNode Ok(JsonNode? id, JsonNode? result) =>
    new JsonObject { ["jsonrpc"] = "2.0", ["result"] = result, ["id"] = id };

JsonNode Error(JsonNode? id, int code, string msg, JsonNode? data = null)
{
    var e = new JsonObject { ["code"] = code, ["message"] = msg };
    if (data is not null) e["data"] = data;
    return new JsonObject { ["jsonrpc"] = "2.0", ["error"] = e, ["id"] = id };
}
```

El estado de la tienda al arrancar: `4711` pagado, `4712` pendiente, `4713` enviado. Todos los intercambios siguientes son salidas reales de este servidor con `curl`.

### Llamada correcta

```bash
curl -s -X POST http://localhost:5871/rpc -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"CancelOrder","params":{"orderId":4711,"reason":"Cambio de opinion"},"id":2}'
```

```json
{"jsonrpc":"2.0","result":{"orderId":4711,"status":"cancelled","refund":true},"id":2}
```

HTTP responde `200`; el `id` de la respuesta es el de la petición, que es lo que permite emparejarlas cuando viajan varias por la misma conexión. `refund: true` indica que el pedido estaba pagado.

### Método inexistente: `-32601`

```bash
curl -s -X POST http://localhost:5871/rpc -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"RefundOrder","params":{"orderId":4711},"id":3}'
```

```json
{"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"},"id":3}
```

El estado HTTP también es `200`: JSON-RPC no usa los códigos de HTTP para el resultado de la llamada, el error va en el cuerpo. Es una de las diferencias más importantes con REST.

### Error de negocio con datos

`CancelOrder` sobre el pedido enviado `4713` devuelve un código propio dentro de la banda reservada a la implementación, con `data` para el detalle:

```json
{"jsonrpc":"2.0","error":{"code":-32002,"message":"El pedido ya no se puede cancelar","data":{"orderId":4713}},"id":5}
```

### Notificación: sin `id`, sin respuesta

```bash
curl -s -i -X POST http://localhost:5871/rpc -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"CancelOrder","params":{"orderId":4712,"reason":"Duplicado"}}'
```

```text
HTTP/1.1 204 No Content
```

El servidor ejecutó la cancelación (se ve en su salida: `[servidor] CANCEL pedido=4712 motivo='Duplicado'`), pero el cliente no recibe ni el resultado ni los errores. Sirve para avisos que no importan si se pierden; para una cancelación real es una mala idea, porque el cliente no sabe si funcionó.

### Lote (batch): varias llamadas en una petición

```bash
curl -s -X POST http://localhost:5871/rpc -H 'Content-Type: application/json' -d '[
  {"jsonrpc":"2.0","method":"GetOrderStatus","params":{"orderId":4712},"id":"a"},
  {"jsonrpc":"2.0","method":"GetOrderStatus","params":{"orderId":4713},"id":"b"},
  {"jsonrpc":"2.0","method":"Nope","id":"c"},
  {"jsonrpc":"2.0","method":"CancelOrder","params":{"orderId":4712,"reason":"x"}}
]'
```

```json
[{"jsonrpc":"2.0","result":{"orderId":4712,"status":"pending"},"id":"a"},
 {"jsonrpc":"2.0","result":{"orderId":4713,"status":"shipped"},"id":"b"},
 {"jsonrpc":"2.0","error":{"code":-32601,"message":"Method not found"},"id":"c"}]
```

Tres respuestas para cuatro peticiones: la notificación no genera ninguna. El orden de las respuestas no está garantizado por la especificación (se emparejan por `id`) y cada elemento tiene su propio éxito o error. Un lote ahorra viajes de red cuando se hacen varias llamadas independientes.

### Peticiones mal formadas

| Entrada | Respuesta |
|---|---|
| JSON truncado | `{"jsonrpc":"2.0","error":{"code":-32700,"message":"Parse error"},"id":null}` |
| Array vacío `[]` | `{"jsonrpc":"2.0","error":{"code":-32600,"message":"Invalid Request"},"id":null}` |
| `orderId` con una cadena | `{"jsonrpc":"2.0","error":{"code":-32602,"message":"Invalid params"},"id":7}` |

Cuando el servidor no pudo leer la petición, no sabe el `id`, por eso la respuesta lleva `"id": null`. La especificación fija estos casos y sus códigos; los ejemplos de la propia especificación (`rpc call with an empty Array`, `rpc call with invalid JSON`) coinciden con lo anterior.

## RPC sobre HTTP «a mano»: acciones como URL

No hace falta JSON-RPC para tener un estilo orientado a acciones. Muchas APIs conservan los recursos en la URL y añaden la acción con un sufijo o un sub-recurso:

```http
POST /orders/4711:cancel
Idempotency-Key: 9c1f6a52
Content-Type: application/json

{ "reason": "Duplicado" }
```

La respuesta a un pedido enviado usa el estado HTTP, algo que JSON-RPC no hace (probado con el mismo servidor):

```http
HTTP/1.1 409 Conflict
Content-Type: application/json

{"error":"order_not_cancellable","message":"No se puede cancelar un pedido enviado."}
```

Es un híbrido: URLs con recurso y estados HTTP con significado, pero las operaciones son verbos explícitos. Es lo que hacen Google (guía de diseño de APIs, «custom methods») y varias pasarelas de pago. Gana legibilidad y control de acceso por ruta; pierde el principio de que el verbo HTTP dice qué se hace.

## Qué se gana y qué se pierde frente a REST

| Criterio | RPC | REST |
|---|---|---|
| Modelo mental | Funciones: verbos del negocio (`cancel`, `capture`) | Recursos: sustantivos con CRUD (`orders`) |
| Operaciones que no son CRUD | Naturales | Hay que inventar un sustantivo o un sub-recurso |
| Caché HTTP | Casi nunca: todo es `POST` a una única URL | `GET` cacheable con `ETag`/`Cache-Control` |
| Estados HTTP | JSON-RPC los ignora (200 con error en el cuerpo); el RPC «a mano» sí los usa | Parte del contrato |
| Descubribilidad | Hay que conocer la lista de métodos (documentación, esquema) | URLs navegables y vocabulario HTTP conocido |
| Acoplamiento cliente-servidor | Alto: el cliente conoce nombres y firmas; cambiar una firma lo rompe | Menor: el recurso cambia con más margen, pero también hay contrato |
| Herramientas genéricas (proxies, gateways, métricas por ruta) | Ven una sola URL | Ven rutas y verbos distintos |
| Rendimiento y simplicidad interna | Sin ceremonia de recursos; fácil de generar con código | Más diseño inicial |

Regla práctica: si la mayoría de las operaciones son lectura y escritura de datos, REST. Si la mayoría son acciones con efectos, o los clientes son servicios propios que se despliegan junto al servidor, RPC.

## Idempotencia y reintentos

Una operación es **idempotente** si ejecutarla varias veces deja el mismo estado que ejecutarla una (el resultado de `GetOrderStatus` o de «fijar el estado a `cancelled`» no cambia al repetirse). `ChargeOrder` no lo es: cada llamada cobra.

Como en un timeout no se sabe si la operación se ejecutó, el cliente solo puede reintentar sin riesgo las idempotentes. Para las demás se añade una **clave de idempotencia**: un identificador que el cliente genera por intención de cobro (no por intento) y el servidor recuerda. Si llega de nuevo, devuelve el resultado guardado sin repetir el efecto.

```csharp
case "ChargeOrder":
    var key = p?["idempotencyKey"]?.ToString() ?? "";
    lock (gate)
    {
        if (key != "" && done.TryGetValue(key, out var previous))
        { reply = Ok(id, previous.DeepClone()); break; }   // misma clave: mismo resultado
        charges++;                                          // efecto real: un cobro
        var result = new JsonObject { ["chargeId"] = "ch_" + charges, ["amount"] = 39.98 };
        if (key != "") done[key] = result.DeepClone();
        reply = Ok(id, result);
    }
    break;
```

Sin clave, dos llamadas seguidas cobran dos veces:

```json
{"jsonrpc":"2.0","result":{"chargeId":"ch_1","amount":39.98},"id":8}
{"jsonrpc":"2.0","result":{"chargeId":"ch_2","amount":39.98},"id":9}
```

Con la misma clave `k-1`, la segunda llamada devuelve el cobro de la primera:

```json
{"jsonrpc":"2.0","result":{"chargeId":"ch_3","amount":39.98},"id":10}
{"jsonrpc":"2.0","result":{"chargeId":"ch_3","amount":39.98},"id":11}
```

Y en el escenario del timeout: dos intentos, ambos con `curl exit=28`, con la clave `pay-4713-1`. El servidor registró un único cobro y una tercera consulta con la misma clave devolvió el mismo `chargeId`. En HTTP, una cabecera `Idempotency-Key` hace de clave; existe un [borrador del IETF](https://datatracker.ietf.org/doc/html/draft-ietf-httpapi-idempotency-key-header) para estandarizarla. La semántica de qué métodos HTTP son idempotentes (`GET`, `PUT`, `DELETE`; `POST` no) está en [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html#name-idempotent-methods), y por eso `POST /orders/4711:cancel` necesita una clave si el reembolso no debe repetirse.

## Evolucionar las firmas sin romper al cliente

En RPC el cliente conoce la firma de cada método: cambiarla de cualquier manera rompe a quien no se haya actualizado.

| Cambio | Compatible | Motivo |
|---|---|---|
| Añadir un parámetro **opcional** con valor por defecto | Sí | Los clientes antiguos no lo envían y el servidor asume el valor por defecto |
| Añadir un campo al resultado | Sí, si el cliente ignora lo que no conoce | Un cliente estricto puede fallar |
| Quitar o renombrar un parámetro | No | El cliente sigue enviando el antiguo |
| Cambiar el orden de parámetros posicionales | No | Se interpreta cada valor como otro parámetro |
| Cambiar el tipo de un parámetro o de un resultado | No | Mismo valor, otro significado |
| Hacer obligatorio un parámetro antes opcional | No | Los clientes antiguos dejan de funcionar |

Por eso JSON-RPC aconseja `params` por nombre (objeto) frente a por posición (array) siempre que haya más de uno o dos: un objeto admite campos nuevos, un array fija el orden para siempre. Cuando el cambio es incompatible, se publica un método nuevo (`CancelOrderV2`) o un prefijo de versión (`/rpc/v2`) y se mantiene el antiguo hasta que los clientes migren. El versionado del contrato en sí, con ejemplos para OpenAPI, está en [Versionado de contratos](../contratos-de-api/Versionado-de-Contratos.md).

## De dónde viene: la línea de descendencia

| Época | Tecnología | Idea |
|---|---|---|
| Años 80 | RPC originales (Sun RPC; el artículo «Implementing Remote Procedure Calls» de Birrell y Nelson, 1984) | Llamar a procedimientos de otra máquina de forma transparente |
| Años 90 | CORBA, Java RMI | Objetos remotos con interfaces tipadas; fuerte acoplamiento a un lenguaje o a un bus de objetos |
| 1998-2000 | XML-RPC → [SOAP](SOAP.md) | RPC con XML sobre HTTP; SOAP añade sobres, esquemas y extensiones |
| 2005-2010 | JSON-RPC (la versión 2.0, de 2010) | La misma idea con JSON y un formato mínimo |
| 2015 en adelante | [gRPC](gRPC.md) | RPC con contrato binario (`.proto`), código generado y HTTP/2 |

[tRPC](https://trpc.io) es un caso aparte: una librería de TypeScript que comparte los tipos del servidor con el cliente sin generar código, lo que solo es posible si ambos están en el mismo ecosistema TypeScript. Apache Thrift ([thrift.apache.org](https://thrift.apache.org)) es un marco de RPC con su propio lenguaje de definición de interfaces y generación de código para muchos lenguajes, de la familia de gRPC. Las fechas de la tabla son aproximadas; solo la de JSON-RPC 2.0 está comprobada contra su especificación (origen 2010-03-26, consulta del 2026-11-09).

## Cuándo NO usar RPC

| Situación | Por qué no RPC | Alternativa |
|---|---|---|
| API pública para terceros, sin SDK | Cada integrador tiene que aprender métodos y firmas sin convención común, y cualquier cambio rompe a quien no pueda actualizar | [REST](REST.md) con contrato, o RPC acompañado de un [SDK](SDK.md) |
| Datos con jerarquía natural (clientes → pedidos → líneas) | Hay que reinventar a mano rutas, paginación y filtros | [REST](REST.md) o [GraphQL](GraphQL.md) |
| Lecturas muy repetidas que deben cachearse | Un `POST` a una única URL no se cachea en navegadores ni CDN | `GET` con `Cache-Control` y `ETag` |
| Cliente que debe enterarse de algo cuando ocurre | Preguntar con llamadas repetidas es sondeo | [Webhooks](Webhooks.md), [WebSockets](WebSockets.md) o [eventos](APIs-Dirigidas-por-Eventos.md) |
| Operación larga (minutos) | Una llamada que espera ata una conexión y un timeout | Devolver un identificador y consultar el estado, o mensajería ([Mensajería asíncrona](../../devops/mensajeria-asincrona/Mensajeria-Asincrona.md)) |

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| La API tiene 200 métodos y nadie sabe cuáles se usan | Un RPC por cada método interno del servicio: la superficie pública refleja el código y no las necesidades del cliente |
| Una pantalla tarda 3 segundos en cargar | Llamadas encadenadas: `GetOrder` → `GetCustomer` → `GetProduct` por cada línea. Cada una suma su latencia. Un método que devuelva lo necesario, o un lote de llamadas independientes, la reduce |
| Cobros o pedidos duplicados tras una caída de red | El cliente trata el timeout como fallo local y reintenta una operación no idempotente sin clave |
| Un fallo del servidor tumba al cliente entero | Los fallos de red se tratan como excepciones locales: sin timeout, sin reintento acotado, sin distinguir error de transporte de error de negocio |
| Al desplegar el servidor, los clientes antiguos dejan de funcionar | Cambio de firma sin compatibilidad ni versión (ver la tabla de evolución) |
| El panel de métricas muestra todo bajo `POST /rpc` | Un único endpoint oculta el método; hay que registrar `method` como etiqueta o usar rutas por método |
| Un método `execute(action, params)` recibe todo | RPC genérico: se pierde el contrato, la documentación y la evolución independiente de cada operación |

## Buenas prácticas avanzadas

- **Pon un timeout explícito en cada llamada y decide qué hacer al vencer.** El valor por defecto de muchas librerías es «sin límite» o minutos. El cliente debe saber, antes de llamar, si ante un timeout va a reintentar, preguntar el estado o avisar a la persona.
- **Reintenta solo lo idempotente, con retroceso exponencial y un máximo de intentos.** Las operaciones con efectos (cobros, envíos) exigen una clave de idempotencia que el servidor recuerde; sin ella, el reintento es una apuesta.
- **Separa los errores de transporte de los de negocio.** «No contacté con el servidor» puede reintentarse; «el pedido ya está enviado» no. Usa los códigos reservados de JSON-RPC (`-32xxx`) para el protocolo y códigos propios documentados para el negocio, y devuelve un `data` útil.
- **Diseña los métodos alrededor de lo que necesita el cliente, no de lo que tiene el servidor.** Un método `GetOrderSummary` que devuelve pedido, cliente y total evita tres viajes; exponer cada método de repositorio interno multiplica la latencia y fija el diseño interno como contrato.
- **Nombra con el vocabulario del negocio y con un verbo concreto.** `CancelOrder`, `CapturePayment`, `ReserveStock`: cada uno hace una cosa. Un `UpdateOrder` que sirve para todo es un `PATCH` disfrazado.
- **Usa `params` por nombre y deja que el servidor ignore campos desconocidos al leer.** Es lo que hace compatible añadir parámetros opcionales y campos de respuesta.

## Documentación oficial

- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification): la especificación completa en una página. Merece la pena para el formato exacto de petición, respuesta, notificación, lote y la tabla de códigos de error; las secciones de ejemplos recorren todos los casos límite.
- [RFC 9110, semántica de HTTP: métodos idempotentes](https://www.rfc-editor.org/rfc/rfc9110.html#name-idempotent-methods): qué métodos HTTP se pueden repetir sin cambiar el resultado, base para decidir qué reintentar.

---

*En resumen: RPC es llamar a una función de otra máquina por su nombre, y funciona bien mientras no se olvide que hay red de por medio: timeouts explícitos, reintentos con clave de idempotencia y firmas que solo crecen.*
