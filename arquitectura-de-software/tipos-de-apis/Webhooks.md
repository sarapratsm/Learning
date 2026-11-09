# Webhooks

## ¿Qué es?

Un **webhook** es una llamada HTTP que un sistema hace a otro cuando ocurre un evento: en lugar de que el cliente pregunte periódicamente si ha pasado algo, el servicio hace un `POST` a una URL que el cliente registró de antemano. Es una «API al revés»: quien consume el servicio expone un endpoint y quien lo ofrece lo invoca.

## ¿Por qué existe?

Un socio de logística recoge los paquetes de la tienda online y necesita saber en qué momento el pedido `4711` pasa a `shipped` para enviar el transportista. Con una API REST, la única forma es **sondear** (*polling*): llamar a `GET /orders?status=shipped` cada pocos segundos. Casi todas las respuestas serán «nada nuevo»: se gasta tráfico en ambos lados y, aun así, el aviso llega con el retraso del intervalo elegido.

El webhook invierte la iniciativa. El socio registra una URL (`https://logistica.ejemplo.net/webhooks/orders`) y la tienda le hace `POST` en el instante en que el pedido cambia de estado. Sin llamadas vacías y sin retraso.

> El polling es llamar al restaurante cada cinco minutos para preguntar si el pedido está listo. El webhook es dejar el número de teléfono para que llamen ellos. La contrapartida es que ahora el restaurante necesita el número bien apuntado, que tú tengas el teléfono encendido y que puedas comprobar que quien llama es el restaurante y no otra persona.

Esa contrapartida es el tema real de los webhooks: el emisor llama a un servidor que no controla y el receptor expone una URL pública que cualquiera puede invocar. Casi todo lo que sigue (firmas, reintentos, idempotencia, SSRF) existe por esas dos razones.

## ¿Cuándo y para qué se usa?

Cuando un tercero necesita enterarse de algo que pasa en tu sistema (o al revés) sin estar preguntando: una pasarela de pago que avisa de un cobro, un repositorio que notifica un `push`, una plataforma de envíos que informa de un cambio de estado, un formulario externo que manda cada respuesta. Requisitos: ambos lados son **servidores** con URL alcanzable y los eventos son puntuales, no un flujo continuo.

## Los dos lados

La guía usa dos papeles:

- **Emisor**: la tienda. Guarda las suscripciones (URL, eventos de interés, secreto) y hace el `POST` cuando ocurre el evento.
- **Receptor**: el socio de logística. Expone un endpoint, comprueba que el aviso viene de la tienda y lo procesa.

Registrar la suscripción es una llamada normal a la API del emisor:

```http
POST /webhook-endpoints HTTP/1.1
Host: api.tienda.ejemplo.com
Content-Type: application/json

{ "url": "https://logistica.ejemplo.net/webhooks/orders", "events": ["order.shipped"] }
```

```http
HTTP/1.1 201 Created
Content-Type: application/json

{ "id": "we_81", "url": "https://logistica.ejemplo.net/webhooks/orders", "events": ["order.shipped"], "secret": "whsec_..." }
```

El `secret` se muestra una sola vez y es lo que permite al receptor verificar las firmas. Cada suscripción tiene el suyo.

## El cuerpo de un evento

Un evento es un sobre (*envelope*) con metadatos fijos y el contenido en `data`:

```json
{
  "id": "evt_a1b2c3",
  "type": "order.shipped",
  "created": "2026-11-09T09:28:45Z",
  "data": { "orderId": 4711, "status": "shipped", "customer": "Núria Peña" }
}
```

| Campo | Para qué sirve |
|---|---|
| `id` | Identifica el evento. Es el mismo en todos los reintentos: el receptor lo usa para detectar duplicados. |
| `type` | Qué ocurrió y, por tanto, qué forma tiene `data`. Jerárquico con puntos (`order.paid`, `order.shipped`). |
| `created` | Cuándo ocurrió el evento (no cuándo se entregó). Sirve para ordenar. |
| `data` | El contenido del evento. |

El identificador y la marca de tiempo del **intento** de entrega viajan en cabeceras, no en el cuerpo, porque cambian en cada reintento. Se sigue la convención de [Standard Webhooks](https://www.standardwebhooks.com/): `webhook-id`, `webhook-timestamp` (segundos Unix) y `webhook-signature`.

## Un intercambio de extremo a extremo

Para probar, un receptor mínimo en ASP.NET Core que solo registra lo que llega:

```csharp
app.MapPost("/webhooks/orders", async (HttpRequest req) =>
{
    using var ms = new MemoryStream();
    await req.Body.CopyToAsync(ms);                       // cuerpo crudo, tal como llegó
    Console.WriteLine($"{req.Headers["webhook-id"]}: {Encoding.UTF8.GetString(ms.ToArray())}");
    return Results.Accepted();
});
```

Y la petición que haría el emisor, con las cabeceras de la convención (la firma se calcula en la sección siguiente):

```bash
curl -i -X POST http://127.0.0.1:5731/webhooks/orders \
  -H "Content-Type: application/json" \
  -H "webhook-id: evt_a1b2c3" \
  -H "webhook-timestamp: 1794043725" \
  -H "webhook-signature: v1,<firma>" \
  --data-binary @body.json
```

El receptor completo de las secciones siguientes responde así a una petición correcta (salida real, 2026-11-09):

```http
HTTP/1.1 202 Accepted
Content-Type: application/json; charset=utf-8

{"status":"queued"}
```

## Firma del mensaje con HMAC-SHA256

La URL del receptor es pública. Sin más, cualquiera puede mandarle un `{"type":"order.shipped",...}` falso y hacer que genere una etiqueta de envío. La defensa habitual es una **firma HMAC**: emisor y receptor comparten un secreto; el emisor calcula una huella del mensaje con ese secreto y la envía en una cabecera; el receptor recalcula la huella y la compara. Quien no conoce el secreto no puede producir una huella válida y cualquier cambio en el mensaje la invalida.

**Qué se firma.** El cuerpo no basta: si solo se firma el cuerpo, una captura válida sirve para siempre. Se firma la concatenación `id.timestamp.cuerpo`, de modo que la marca de tiempo y el id quedan protegidos:

```text
evt_a1b2c3.1794043725.{"id":"evt_a1b2c3","type":"order.shipped",...}
```

**Cómo firma el emisor** (sobre los *bytes* exactos que va a enviar):

```csharp
public static string Sign(string secret, string id, long timestamp, byte[] rawBody)
{
    var prefix = Encoding.UTF8.GetBytes($"{id}.{timestamp}.");
    var signed = new byte[prefix.Length + rawBody.Length];
    prefix.CopyTo(signed, 0);
    rawBody.CopyTo(signed, prefix.Length);

    using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
    return "v1," + Convert.ToBase64String(hmac.ComputeHash(signed));
}
```

En el ejemplo el secreto se usa como texto UTF-8 para simplificar. La especificación Standard Webhooks (v1.0.0, consultada el 2026-11-09) define el secreto como una cadena en base64 con el prefijo `whsec_`, que hay que decodificar antes de usarlo como clave del HMAC: con una librería compatible con esa especificación, el emisor y el receptor deben usar la misma codificación.

**Cómo verifica el receptor**: recalcula la firma con el cuerpo crudo, comprueba la ventana de tiempo y compara en tiempo constante:

```csharp
public enum VerifyResult { Ok, MissingHeaders, TimestampOutOfWindow, BadSignature }

public static VerifyResult Verify(
    string[] secrets, string? id, string? timestampHeader, string? signatureHeader,
    byte[] rawBody, DateTimeOffset now, TimeSpan tolerance)
{
    if (string.IsNullOrEmpty(id) || string.IsNullOrEmpty(signatureHeader)
        || !long.TryParse(timestampHeader, out var timestamp))
        return VerifyResult.MissingHeaders;

    var age = now - DateTimeOffset.FromUnixTimeSeconds(timestamp);
    if (age.Duration() > tolerance)                       // demasiado antigua o del futuro
        return VerifyResult.TimestampOutOfWindow;

    // La cabecera puede traer varias firmas separadas por espacios (rotación del secreto).
    var received = signatureHeader.Split(' ', StringSplitOptions.RemoveEmptyEntries);
    foreach (var secret in secrets)
    {
        var expected = Encoding.UTF8.GetBytes(Sign(secret, id, timestamp, rawBody));
        foreach (var candidate in received)
            if (CryptographicOperations.FixedTimeEquals(expected, Encoding.UTF8.GetBytes(candidate)))
                return VerifyResult.Ok;
    }
    return VerifyResult.BadSignature;
}
```

`FixedTimeEquals` tarda lo mismo acierte en el primer byte o en el último. Con `==`, la comparación termina en el primer byte distinto y quien mide tiempos de respuesta puede reconstruir la firma byte a byte.

El endpoint solo orquesta: lee el cuerpo crudo, verifica y, si falla, responde `401` con un mensaje genérico (el motivo exacto va al log, no a quien llama):

```csharp
app.MapPost("/webhooks/orders", async (HttpRequest req) =>
{
    using var ms = new MemoryStream();
    await req.Body.CopyToAsync(ms);
    var body = ms.ToArray();

    var result = WebhookSigner.Verify(secrets, req.Headers["webhook-id"], req.Headers["webhook-timestamp"],
        req.Headers["webhook-signature"], body, DateTimeOffset.UtcNow, TimeSpan.FromMinutes(5));
    if (result != VerifyResult.Ok)
    {
        Console.WriteLine($"[receptor] rechazado: {result}");
        return Results.Json(new { error = "Firma no válida." }, statusCode: 401);
    }
    // ... idempotencia y cola (secciones siguientes)
});
```

La firma a mano con `openssl` reproduce lo mismo que el emisor en C# (`$BODY` es el contenido exacto de `body.json`):

```bash
SIG=$(printf '%s.%s.%s' "$ID" "$TS" "$BODY" | openssl dgst -sha256 -hmac "$SECRET" -binary | base64)
curl -i -X POST http://127.0.0.1:5731/webhooks/orders -H "webhook-id: $ID" \
  -H "webhook-timestamp: $TS" -H "webhook-signature: v1,$SIG" --data-binary @body.json
```

Resultados reales contra el receptor (2026-11-09):

| Petición | Respuesta |
|---|---|
| Firma correcta | `HTTP/1.1 202 Accepted` · `{"status":"queued"}` |
| Firma calculada con otro secreto | `HTTP/1.1 401 Unauthorized` · `{"error":"Firma no válida."}` |
| Firma correcta, pero se cambió `Núria` por `Nuria` en el cuerpo después de firmar | `HTTP/1.1 401 Unauthorized` · `{"error":"Firma no válida."}` |

En el log del receptor, las dos últimas aparecen como `rechazado: BadSignature`.

### El error clásico: verificar sobre el JSON re-serializado

Los frameworks deserializan el cuerpo antes de que el código lo vea. Si el handler recibe un objeto y para verificar lo vuelve a serializar, los bytes ya no son los mismos: cambia el orden de propiedades, los espacios o el escape de caracteres. Una petición **legítima y bien firmada** se rechaza:

```csharp
// ❌ Se firma sobre lo que sale de re-serializar, no sobre lo que llegó
var reserialized = Encoding.UTF8.GetBytes(JsonNode.Parse(body)!.ToJsonString());
var result = WebhookSigner.Verify(secrets, id, ts, sig, reserialized, now, tolerance);
```

Con el mismo cuerpo y la misma firma que el receptor correcto acepta con `202`, el receptor que re-serializa responde (salida real):

```http
HTTP/1.1 401 Unauthorized

{"error":"Firma no válida."}
```

La causa aquí es el escape: el emisor envió `"Núria Peña"` tal cual y `ToJsonString()` lo vuelve a escribir como `"Núria Peña"`. El mismo fallo aparece con un espacio de más, con otro orden de propiedades o con un número `1.0` que pasa a `1`. La regla es leer el cuerpo como bytes, verificar y solo después deserializar. En ASP.NET Core eso significa no usar el *model binding* en el parámetro del endpoint que verifica.

## Protección frente a repetición

Una firma válida no caduca por sí sola. Quien capture una petición legítima (un proxy intermedio, un log mal protegido) puede reenviarla idéntica semanas después y la firma seguirá cuadrando. Por eso `webhook-timestamp` entra en el contenido firmado y el receptor rechaza las que están fuera de una **ventana de tolerancia** (cinco minutos en el código anterior, hacia el pasado y hacia el futuro, para absorber desajuste de relojes).

Cambiar la marca de tiempo para colarse en la ventana invalida la firma, porque el timestamp forma parte de lo firmado. Una petición con firma válida pero con diez minutos de antigüedad (salida real):

```http
HTTP/1.1 401 Unauthorized

{"error":"Firma no válida."}
```

```text
[receptor] rechazado: TimestampOutOfWindow
```

La ventana no sustituye a la idempotencia: dentro de los cinco minutos la misma petición sigue siendo repetible. Eso lo cubre el `id` del evento (más adelante).

## Responder rápido y procesar después

El emisor espera la respuesta con un *timeout* corto (Standard Webhooks recomienda entre 15 y 30 segundos). Si el receptor hace el trabajo dentro de la petición, un trabajo lento equivale a un fallo.

```csharp
// ❌ Trabajo dentro de la petición
app.MapPost("/webhooks/slow", async (HttpRequest req, OrderProjection p) =>
{
    // ... verificación ...
    await Task.Delay(3000);                    // generar la etiqueta de envío
    Interlocked.Increment(ref p.Labels);
    return Results.Ok();
});
```

Un emisor con *timeout* de 1 segundo contra ese endpoint (salida real; se omiten los intentos 3 a 7, todos iguales):

```text
intento 1: evt_d0f2a383 -> timeout en 1010 ms
  siguiente intento en 00:00:05
intento 2: evt_d0f2a383 -> timeout en 1000 ms
  siguiente intento en 00:00:25
...
intento 8: evt_d0f2a383 -> timeout en 1005 ms
decisión: agotados los intentos
```

```bash
$ curl -s localhost:5731/stats
{"labels":8}
```

Para el emisor, los ocho intentos fallaron. Para el receptor, **los ocho se completaron**: el mismo pedido generó ocho etiquetas de envío. El timeout del emisor no cancela el trabajo del receptor.

La alternativa es validar, encolar y devolver `2xx` de inmediato. El trabajo ocurre en un proceso en segundo plano:

```csharp
// ✅ Verificar, registrar el id, encolar y responder
await queue.Writer.WriteAsync(ev);
return Results.Json(new { status = "queued" }, statusCode: 202);
```

Con ese receptor, la misma entrega tarda 47 ms (`intento 1: evt_e1b3d639 -> 202 en 47 ms`). La cola del ejemplo es un `Channel<T>` en memoria; en producción conviene una cola persistente (una tabla, o un broker como el de [Mensajería asíncrona](../../devops/mensajeria-asincrona/Mensajeria-Asincrona.md)), porque lo que está en memoria se pierde si el proceso se reinicia después de haber respondido `202`.

## Reintentos del emisor

El emisor no sabe si el receptor está caído un minuto o un día. Un emisor fiable reintenta con espera exponencial y se rinde en algún momento.

**Qué se reintenta.** Según el resultado del intento:

| Resultado | Decisión |
|---|---|
| `2xx` | Entregado. |
| `410 Gone` | El receptor pide no recibir más: se desactiva el endpoint. |
| `3xx` | Fallo. No se siguen redirecciones; se debe actualizar la URL registrada. |
| Timeout, conexión rechazada, error de DNS | Reintento. |
| `408`, `429` (respetar `Retry-After`), `5xx` y el resto de `4xx` | Reintento. Un `401` o un `404` suelen ser un despliegue a medias en el receptor, no un fallo definitivo. |

```csharp
public static Decision Classify(int? status) => status switch
{
    null => Decision.Retry,                       // timeout, conexión rechazada, DNS
    >= 200 and < 300 => Decision.Success,
    410 => Decision.DisableEndpoint,
    >= 300 and < 400 => Decision.Fail,
    _ => Decision.Retry
};
```

**La agenda.** Espera antes del intento *n*: `5 s · 5^(n-2)`, con tope de 24 h y 8 intentos como máximo:

```csharp
public static TimeSpan DelayBefore(int attempt, double jitter = 0, Random? rng = null)
{
    var seconds = Math.Min(5 * Math.Pow(5, attempt - 2), TimeSpan.FromHours(24).TotalSeconds);
    if (jitter > 0) seconds *= 1 + (rng!.NextDouble() * 2 - 1) * jitter;   // ±jitter
    return TimeSpan.FromSeconds(seconds);
}
```

Salida real de la agenda (sin *jitter*):

```text
intento  espera       acumulado
      1  00:00:00     00:00:00
      2  00:00:05     00:00:05
      3  00:00:25     00:00:30
      4  00:02:05     00:02:35
      5  00:10:25     00:13:00
      6  00:52:05     01:05:05
      7  04:20:25     05:25:30
      8  21:42:05     27:07:35
```

Los fallos breves (un reinicio, un despliegue) se resuelven en los primeros intentos; una caída larga se cubre durante algo más de un día. El *jitter* (un ±20 % aleatorio) evita que cien eventos fallidos a la vez vuelvan a golpear al receptor en el mismo segundo, justo cuando se recupera.

Cada intento lleva una `webhook-timestamp` nueva, con su firma recalculada (si no, la ventana anti-repetición rechazaría los reintentos tardíos), y el **mismo** `webhook-id`. Contra un receptor que responde `503` dos veces y luego `200`:

```text
intento 1: evt_4de86563 -> 503 en 42 ms
  siguiente intento en 00:00:05 (en la demo se espera 1 s)
intento 2: evt_4de86563 -> 503 en 1 ms
  siguiente intento en 00:00:25 (en la demo se espera 1 s)
intento 3: evt_4de86563 -> 200 en 1 ms
decisión: Success
```

**Cuándo se desactiva un endpoint.** Si se agota la agenda completa para varios eventos seguidos (por ejemplo, cinco), o si responde `410`, el emisor marca la suscripción como desactivada, deja de enviarle eventos y avisa al propietario por otro canal (correo, panel). Seguir golpeando una URL muerta durante meses desperdicia recursos y puede generar una avalancha cuando vuelva. Desactivar es distinto de borrar: un endpoint reactivado puede recibir de nuevo los eventos pendientes.

## Duplicados y orden

### Al menos una vez: idempotencia por `id`

Un emisor que no recibe respuesta no sabe si el receptor procesó el evento (el `2xx` se perdió por el camino) o no. Para no perder eventos reenvía, así que la entrega es **al menos una vez**: los duplicados son parte del contrato, no un fallo. El receptor debe ser **idempotente**: procesar dos veces el mismo evento tiene el mismo efecto que procesarlo una.

La forma habitual es una tabla de eventos procesados con el `id` como clave primaria y registrar el `id` **antes** de encolar:

```sql
CREATE TABLE processed_events (
    event_id     varchar(64)  PRIMARY KEY,
    received_at  timestamptz  NOT NULL DEFAULT now()
);
-- INSERT ... ON CONFLICT DO NOTHING; si no inserta ninguna fila, es un duplicado
```

```csharp
if (!inbox.TryRegister(ev.Id))                       // en el ejemplo, un ConcurrentDictionary
    return Results.Json(new { status = "duplicate" });  // 200: el evento ya se tiene
```

La clave primaria resuelve también la carrera entre dos entregas simultáneas del mismo evento. Enviando dos veces `evt_a1b2c3` (salida real):

```http
HTTP/1.1 202 Accepted
{"status":"queued"}
```

```http
HTTP/1.1 200 OK
{"status":"duplicate"}
```

```text
[receptor] evt_a1b2c3 encolado
[receptor] evt_a1b2c3 duplicado, se ignora
```

El duplicado se responde con `2xx` (aquí `200`): si se respondiera con error, el emisor seguiría reintentando algo que ya se tiene. La tabla puede purgarse pasado el periodo máximo de reintentos del emisor (en esta agenda, algo más de un día).

### No confiar en el orden

Con reintentos y entregas en paralelo, `order.shipped` puede llegar antes que `order.paid`. Un receptor que aplica los eventos en orden de llegada deja el pedido en `paid` cuando ya está enviado. Dos formas de resolverlo:

- **Comparar la marca del recurso**: cada evento lleva `created` (o una versión del recurso); el receptor guarda la marca del último evento aplicado por pedido e ignora los más antiguos.
- **Consultar el estado actual**: tratar el evento como un aviso y pedir a la API el estado real (siguiente sección).

Con la primera, mandando `shipped` (creado a las 10:00:10) y después `paid` (creado a las 10:00:00), el log del receptor muestra (salida real):

```text
[worker] evt_o1 order.shipped: pedido 4711 -> shipped
[worker] evt_o2 order.paid: ignorado (obsoleto): el pedido ya está en 'shipped' desde 10:00:10
```

```csharp
if (current.Status is not null && current.At >= at)
    return $"ignorado (obsoleto): ...";
state[orderId] = (status, at);
```

## Evento ligero o evento gordo

El evento **ligero** solo avisa y lleva identificadores; el receptor llama después a `GET /orders/4711` con sus credenciales. El evento **gordo** lleva el pedido completo.

```json
{ "id": "evt_a1b2c3", "type": "order.shipped", "created": "2026-11-09T09:28:45Z", "data": { "orderId": 4711 } }
```

| Criterio | Ligero (aviso + consulta) | Gordo (datos completos) |
|---|---|---|
| Seguridad | Los datos no viajan por la URL del receptor; se piden con autenticación y se puede auditar quién los lee. | Los datos personales (nombre, dirección) llegan a cualquier endpoint registrado y quedan en sus logs. |
| Tamaño | Cientos de bytes. | Crece con el recurso; se recomienda mantenerlo por debajo de unos 20 kB. |
| Obsolescencia | El receptor lee el estado actual: nunca ve datos viejos. | Refleja el estado en el momento del evento; si llega tarde o desordenado, puede estar desfasado. |
| Carga | Cada evento provoca una llamada extra a la API del emisor. | El receptor puede procesar sin llamar a nadie. |
| Evolución | Se puede ampliar `data` más adelante sin ruptura. | Quitar campos del recurso rompe a los receptores. |

La solución intermedia es habitual: avisar con un identificador y los pocos campos que casi todos necesitan (`status`), y dejar el resto a la consulta. El ligero con consulta resuelve de paso el orden: lo que se lee es siempre el estado actual.

## Seguridad del receptor

- **HTTPS siempre.** La firma garantiza autenticidad e integridad, pero no cifra: sin TLS, los datos del pedido viajan en claro.
- **Un secreto por suscripción**, generado aleatoriamente (entre 24 y 64 bytes, según Standard Webhooks), mostrado una sola vez y guardado como cualquier credencial. Si un secreto se filtra, solo afecta a esa suscripción.
- **Rotación sin corte.** Durante la rotación el emisor firma con el secreto nuevo y con el viejo y manda ambas firmas en `webhook-signature`, separadas por espacios. El receptor acepta la petición si coincide cualquiera (el bucle de `Verify` ya lo hace con su lista de secretos). Pasado el periodo de gracia se retira el viejo.
- **No fiarse de la IP de origen.** Las IP de los emisores cambian, se comparten con otros clientes y son falsificables en redes internas. La firma es el único control que prueba quién envía; una lista de IP permitidas es, como mucho, un filtro adicional.
- **Errores sin detalles.** Un `401` genérico (`Firma no válida.`) para cualquier fallo de verificación; el motivo exacto (`TimestampOutOfWindow`, `BadSignature`) solo en el log. Distinguirlos en la respuesta ayuda a quien intenta falsificar.
- **Limitar el tamaño del cuerpo** antes de leerlo entero y verificar la firma **antes** de hacer nada costoso con el contenido.

El secreto no se versiona: va en un gestor de secretos o variables de entorno (ver [Gestión de secretos en desarrollo](../../seguridad/gestion-de-secretos-en-desarrollo/README.md)).

## Seguridad del emisor

### SSRF: la URL la elige el cliente

Quien registra la suscripción decide a qué URL hará el servidor del emisor una petición. Eso es una invitación al **SSRF** (*server-side request forgery*): un cliente malicioso registra `http://169.254.169.254/latest/meta-data/` (el servicio de metadatos de muchas nubes, que devuelve credenciales) o `http://localhost:5432/` y el emisor, desde dentro de su red, hace la petición y puede devolver o filtrar la respuesta.

La defensa es validar la URL **resuelta**, no el texto. Un nombre como `localtest.me` parece público y resuelve a `127.0.0.1`; `https://2130706433/` es `127.0.0.1` escrito como entero. Comprobación al registrar:

```csharp
public static async Task<string?> CheckAsync(string url)
{
    if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return "URL no válida";
    if (uri.Scheme != Uri.UriSchemeHttps) return "solo se admite https";
    if (!string.IsNullOrEmpty(uri.UserInfo)) return "no se admiten credenciales en la URL";
    if (uri.Port != 443) return "solo se admite el puerto 443";

    var ips = await Dns.GetHostAddressesAsync(uri.DnsSafeHost);
    var blocked = ips.FirstOrDefault(ip => !IsPublic(ip));
    return blocked is null ? null : $"resuelve a una dirección no pública ({blocked})";
}
```

`IsPublic` rechaza loopback, `0.0.0.0/8`, `10.0.0.0/8`, `100.64.0.0/10`, `169.254.0.0/16`, `172.16.0.0/12`, `192.168.0.0/16`, multicast, y en IPv6 `::1`, `fe80::/10` y `fc00::/7` (incluidas las direcciones IPv4 mapeadas en IPv6). Resultados reales (2026-11-09):

```text
https://example.com/hook             -> permitida
http://example.com/hook              -> solo se admite https
https://169.254.169.254/latest/meta-data/ -> resuelve a una dirección no pública (169.254.169.254)
https://localhost/hook               -> resuelve a una dirección no pública (::1)
https://10.0.0.5/hook                -> resuelve a una dirección no pública (10.0.0.5)
https://[::1]/hook                   -> resuelve a una dirección no pública (::1)
https://2130706433/hook              -> resuelve a una dirección no pública (127.0.0.1)
https://localtest.me/hook            -> resuelve a una dirección no pública (127.0.0.1)
https://user:pw@example.com/hook     -> no se admiten credenciales en la URL
https://example.com:8443/hook        -> solo se admite el puerto 443
```

Validar al registrar no basta: el DNS del atacante puede devolver una IP pública al registrar y una interna al enviar (*DNS rebinding*). Por eso la entrega vuelve a comprobar la IP **en el momento de conectar**, y no sigue redirecciones (una `302` a `http://169.254...` saltaría la validación):

```csharp
new SocketsHttpHandler
{
    AllowAutoRedirect = false,
    ConnectCallback = async (ctx, ct) =>
    {
        var ips = await Dns.GetHostAddressesAsync(ctx.DnsEndPoint.Host, ct);
        var ip = ips.FirstOrDefault(UrlGuard.IsPublic)
            ?? throw new HttpRequestException("destino no público bloqueado");
        var socket = new Socket(ip.AddressFamily, SocketType.Stream, ProtocolType.Tcp);
        await socket.ConnectAsync(new IPEndPoint(ip, ctx.DnsEndPoint.Port), ct);
        return new NetworkStream(socket, ownsSocket: true);
    }
}
```

Lo ideal, además, es que los trabajadores que envían webhooks vivan en una red sin acceso a servicios internos: la validación en código es la segunda línea de defensa.

### Timeouts y límites

- **Timeout de conexión y de respuesta** cortos (de 5 a 30 s). Un receptor que acepta la conexión y no responde nunca no debe bloquear un hilo del emisor indefinidamente.
- **Límite de lectura de la respuesta**: el emisor solo necesita el código de estado; descartar o truncar el cuerpo (unos pocos kB) para el registro de intentos.
- **Tamaño del evento acotado** (unos 20 kB) y concurrencia por endpoint limitada, para que un receptor lento no acapare todos los trabajadores.

## Registrar y reenviar las entregas

Cada intento se guarda. Es lo que permite al propietario de la suscripción (y al soporte del emisor) ver por qué falla algo y reenviar a mano:

```sql
CREATE TABLE deliveries (
    id            bigint       PRIMARY KEY,
    endpoint_id   varchar(32)  NOT NULL,           -- we_81
    event_id      varchar(64)  NOT NULL,           -- evt_a1b2c3
    attempt       int          NOT NULL,
    status        varchar(16)  NOT NULL,           -- pending | succeeded | failed | disabled
    http_status   int          NULL,
    response_ms   int          NULL,
    error         varchar(200) NULL,               -- 'timeout', 'destino no público bloqueado'
    next_attempt  timestamptz  NULL,
    attempted_at  timestamptz  NOT NULL
);
```

Un reenvío manual crea un intento nuevo con el **mismo** `event_id`: gracias a la idempotencia del receptor, repetirlo es seguro. Una API de gestión (listar endpoints, ver entregas fallidas, reenviar) convierte la depuración en autoservicio en lugar de tickets de soporte.

## Probar webhooks en desarrollo

- **Receptor local + túnel**: un servicio de túneles expone temporalmente `localhost` a internet para que un emisor real pueda alcanzarlo (no hace falta instalar nada para entender el patrón).
- **`curl` firmado a mano**, como en las secciones anteriores: permite reproducir una firma válida, una incorrecta o un cuerpo alterado, sin emisor.
- **Guardar cuerpos reales** recibidos (con los datos sensibles enmascarados) y usarlos como casos de test del endpoint: los cuerpos reales nunca coinciden del todo con la documentación (campos extra, nulos, formatos de fecha).

## ¿Webhook, polling o tiempo real?

| | Webhook | Polling / long polling | SSE / WebSockets |
|---|---|---|---|
| Quién inicia | El emisor (servidor a servidor) | El cliente | El cliente abre la conexión; el servidor empuja |
| El receptor necesita URL pública | Sí | No | No |
| Latencia | Inmediata | Del intervalo (polling) o casi inmediata (long polling) | Inmediata |
| Volumen adecuado | Eventos puntuales | Cualquiera, con coste por llamada | Flujo continuo |
| Quién es el receptor | Otro servidor | Navegador, app o servidor | Navegador, app o servidor |

Con el socio de logística, un webhook. Para un panel de soporte con el estado del pedido en vivo en el navegador, [Server-Sent Events](Server-Sent-Events.md) o [WebSockets](WebSockets.md): un navegador no expone una URL a la que el servidor pueda llamar. Si el receptor no puede ser alcanzable desde internet (detrás de un cortafuegos corporativo), [Long-Polling](Long-Polling.md) o un sondeo periódico es la salida.

## Relación con eventos y con el outbox

Un webhook es la entrega de un evento a un tercero por HTTP. Cuando los eventos circulan **dentro** de una organización entre varios servicios, el transporte habitual es un broker, descrito en [APIs dirigidas por eventos](APIs-Dirigidas-por-Eventos.md); un servicio puede, además, consumir esos eventos y reenviarlos a los socios como webhooks.

Queda un problema del lado del emisor: guardar el cambio (`order.status = shipped`) y avisar son dos operaciones, y puede ocurrir que el cambio se guarde y el proceso muera antes de emitir el evento. El socio nunca se entera. El patrón [Outbox](../../devops/mensajeria-asincrona/Outbox-Pattern.md) lo resuelve guardando el evento en la misma transacción que el cambio y entregándolo después desde esa tabla.

## Cuándo NO usar webhooks

- El receptor **no puede exponer una URL** accesible desde el emisor (app móvil, navegador, red cerrada): usa SSE, WebSockets o polling.
- El flujo es **continuo y de alta frecuencia** (cotizaciones, telemetría): un `POST` por evento es mucho más caro que una conexión abierta.
- Se necesita **entrega ordenada y garantizada** sin lógica adicional en el receptor: un broker con colas ofrece esas garantías; un webhook no.
- El receptor **no puede asumir** idempotencia, verificación y reconciliación: sin esas piezas, un webhook es una fuente de datos duplicados o falsos.
- Hay **pocos eventos y mucha tolerancia a retraso**: un sondeo cada cinco minutos es más simple de operar.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| Peticiones legítimas rechazadas con `401` solo a veces (con tildes, emojis, números decimales) | Se verifica la firma sobre el JSON deserializado y re-serializado, no sobre el cuerpo crudo. |
| La verificación pasa en local y falla tras un proxy o un middleware | Algo entre emisor y endpoint modifica el cuerpo (compresión, reescritura, normalización de saltos de línea) antes de leerlo. |
| Se pueden adivinar firmas midiendo tiempos de respuesta | Comparación con `==` o `string.Equals` en lugar de `CryptographicOperations.FixedTimeEquals`. |
| El emisor reintenta sin parar y el receptor «ya lo hizo» | Procesamiento en la misma petición que supera el timeout del emisor. |
| Un pedido genera dos etiquetas, dos correos o dos cobros | Falta idempotencia por `id` del evento. |
| Un pedido enviado figura como pagado | Se aplican los eventos en orden de llegada, sin comprobar la marca del recurso. |
| Se aceptan peticiones capturadas días después | La firma no incluye la marca de tiempo o no se comprueba la ventana. |
| El emisor accede a servicios internos | Falta validación de la URL resuelta (SSRF), o se siguen redirecciones. |
| Un secreto aparece en el historial de Git | Secreto en el repositorio. Rótalo y guárdalo en un gestor de secretos (ver [Gestión de secretos en desarrollo](../../seguridad/gestion-de-secretos-en-desarrollo/README.md)). |
| Eventos «perdidos» tras una caída del receptor | Se agotó la agenda de reintentos y no hay reconciliación ni reenvío manual. |

## Buenas prácticas avanzadas

- **Verifica la marca de tiempo además de la firma, y dentro de lo firmado.** Una firma válida no basta: una captura reenviada días después sigue cuadrando. Firma `id.timestamp.cuerpo` y rechaza lo que quede fuera de unos pocos minutos.
- **Trata el webhook como un timbre, no como la verdad.** Los reintentos y el paralelismo desordenan los eventos. Ante cualquier decisión que dependa del estado, consulta el estado actual a la API del emisor o compara la marca del recurso.
- **Reconcilia periódicamente.** Algún webhook se perderá (una caída del receptor que coincide con el último reintento, un despliegue en mal momento). Un proceso que compare el estado local con el del emisor («pedidos que sigo teniendo como `paid` desde hace más de una hora») convierte una pérdida silenciosa en un retraso de minutos.
- **Registra el `id` antes de encolar y con restricción única.** Es la única forma de que dos entregas simultáneas del mismo evento no se cuelen ambas.
- **Un secreto por suscripción y rotación con firmas múltiples.** Compartir un secreto entre clientes hace que la filtración de uno comprometa a todos; rotar con doble firma evita cortes.
- **Desactiva endpoints muertos y avisa por otro canal.** El emisor que reintenta eternamente contra una URL abandonada gasta recursos y, si la URL cambia de dueño, envía datos a un tercero.

## Documentación oficial

- [Standard Webhooks](https://www.standardwebhooks.com/): especificación abierta (versión 1.0.0, consultada el 2026-11-09) con el formato del sobre, las cabeceras `webhook-id`/`webhook-timestamp`/`webhook-signature`, el esquema de firma con HMAC-SHA256 y la rotación con firmas múltiples, una agenda de reintentos de ejemplo, el tratamiento de códigos de estado, el SSRF y los eventos ligeros frente a gordos. Es la referencia para diseñar un emisor y un receptor desde cero.
- [GitHub: validar las entregas de webhooks](https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries): ejemplo real de firma HMAC-SHA256 (cabecera `X-Hub-Signature-256`) con la advertencia de usar una comparación en tiempo constante. Útil para ver el mismo patrón en un proveedor que se integra a diario.

---

*En resumen: un webhook es una API al revés, y por eso el receptor debe comprobar la firma sobre el cuerpo crudo, aceptar duplicados sin repetir el efecto y responder rápido, mientras que el emisor reintenta con espera exponencial y nunca llama a una URL sin validar adónde apunta.*
