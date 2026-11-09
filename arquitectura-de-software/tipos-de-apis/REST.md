# REST

## ¿Qué es?

**REST** (*Representational State Transfer*) es un estilo de diseño de APIs web que organiza todo en torno a **recursos** (productos, pedidos, clientes) identificados por una URL, sobre los que se actúa con los verbos estándar de HTTP (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`) y cuyo resultado se comunica con los códigos de estado de HTTP. Es, con diferencia, el estilo más extendido.

## ¿Por qué existe?

Antes de REST, cada API inventaba sus propias operaciones (`/getUser`, `/createOrderNow`, `/deleteThing`), y aprender una no servía para la siguiente. REST propone un convenio que aprovecha lo que la web ya tenía: las URLs para nombrar cosas y los verbos HTTP para decir qué hacer con ellas. El estilo lo describió Roy Fielding en su tesis doctoral (2000) a partir de las propiedades que hicieron escalar a la web: cliente y servidor separados, peticiones **sin estado** (*stateless*: cada una lleva todo lo necesario, incluida la credencial), respuestas cacheables y una interfaz uniforme.

> Piensa en una biblioteca bien ordenada: cada libro tiene su ubicación fija (la URL) y las acciones son siempre las mismas —consultar, añadir, reemplazar, retirar— independientemente del libro. Una vez aprendido el sistema, sabes moverte por cualquier sección. Y como el bibliotecario no necesita recordar quién eras ayer (cada vez enseñas el carné), cualquiera de los bibliotecarios puede atenderte.

El resultado son APIs predecibles: quien sabe usar una API REST sabe usar casi cualquier otra, y las herramientas genéricas (navegadores, proxies, cachés, `curl`) ya entienden el protocolo.

## ¿Cuándo y para qué se usa?

Es la opción por defecto para la mayoría de APIs web públicas e internas: la API de una tienda online, la de una app de tareas, la de un blog. Funciona especialmente bien cuando los datos encajan en colecciones de cosas (productos, pedidos, clientes) y las operaciones son crear, leer, actualizar y borrar (**CRUD**). Los ejemplos usan una tienda con `products`, `orders` y `customers`, base `https://api.tienda.ejemplo.com`.

## Recursos y URLs

La URL identifica la *cosa*, no la acción. Los nombres van en plural y en minúsculas; el verbo dice qué hacer.

```text
/products              la colección de productos
/products/42           el producto 42
/orders/4711           el pedido 4711
/orders/4711/lines     las líneas del pedido 4711
```

El **anidamiento** se usa cuando el hijo no tiene sentido sin el padre (una línea no existe fuera de su pedido). Cuando el hijo tiene vida propia o se consulta de forma transversal, es mejor una colección propia con filtro:

| Forma | Cuándo encaja |
|---|---|
| `/orders/4711/lines` | Las líneas solo se leen y escriben a través de su pedido |
| `/order-lines?order=4711` | Las líneas se consultan también sin pedido (p. ej. «todas las líneas del producto 42») |
| `/customers/7/orders` | Atajo de lectura para «los pedidos de este cliente»; el pedido sigue viviendo en `/orders/4711` |

Dos niveles de anidamiento son el techo razonable: `/customers/7/orders/4711/lines/2` obliga al cliente a conocer toda la cadena para llegar a una línea. Los verbos nunca van en la URL: `/getOrder`, `/createOrder` o `/orders/delete/4711` repiten lo que ya dice el método HTTP.

## Verbos y su semántica real

Dos propiedades definidas en [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) deciden cómo puede tratar la red cada método:

- **Seguro**: no cambia el estado del servidor (solo lectura). Un rastreador o un precargador pueden llamarlo sin pedir permiso.
- **Idempotente**: repetir la misma petición N veces deja el servidor en el mismo estado que enviarla una sola vez. Los clientes, proxies y librerías HTTP pueden **reintentar** automáticamente ante un corte de red.

| Verbo | Uso | Seguro | Idempotente | Si se repite |
|---|---|---|---|---|
| `GET` | Leer | Sí | Sí | Misma lectura |
| `POST` | Crear, o ejecutar una acción | No | No | Se ejecuta otra vez: dos pedidos |
| `PUT` | Reemplazar el recurso entero (o crearlo en una URL que elige el cliente) | No | Sí | Mismo estado final |
| `PATCH` | Modificar parte del recurso | No | No garantizado | Depende de la operación: «poner `status` a `paid`» es repetible; «sumar 1 a la cantidad» no |
| `DELETE` | Borrar | No | Sí | El estado final es el mismo (no existe), aunque la 2.ª respuesta sea `404` |

La diferencia entre `PUT` y `POST` se ve repitiendo la petición contra el servidor de ejemplo:

```bash
# PUT dos veces al mismo producto: mismo estado final
curl -si -X PUT http://localhost:5099/products/42 -H "Content-Type: application/json" \
     -d '{"name":"Teclado","price":54.90}'
```

```text
HTTP/1.1 200 OK
{"id":42,"name":"Teclado","price":54.90}
HTTP/1.1 200 OK
{"id":42,"name":"Teclado","price":54.90}
```

```bash
# POST dos veces a /orders: dos pedidos distintos
curl -si -X POST http://localhost:5099/orders -H "Content-Type: application/json" \
     -d '{"customerId":7,"lines":[{"productId":42,"quantity":1}]}'
```

```text
HTTP/1.1 201 Created
Location: /orders/4713
HTTP/1.1 201 Created
Location: /orders/4714
```

Por eso un cliente puede reintentar un `PUT` sin miedo, pero un `POST` reintentado tras un *timeout* puede duplicar el pedido (ver «Idempotencia en operaciones no idempotentes»). `PUT` exige enviar el recurso completo: los campos omitidos se pierden. Para cambiar solo el estado, `PATCH`.

## Códigos de estado que importan

El código de estado cuenta qué pasó sin abrir el cuerpo.

| Código | Cuándo | Nota |
|---|---|---|
| `200 OK` | Lectura o actualización correcta con cuerpo | |
| `201 Created` | Un `POST` (o `PUT`) creó el recurso | Con cabecera `Location` con la URL del nuevo recurso |
| `204 No Content` | Éxito sin cuerpo | Típico en `DELETE` |
| `304 Not Modified` | El recurso no cambió respecto a la copia del cliente | Ver «Condicionales y caché» |
| `400 Bad Request` | La petición está mal formada (JSON roto, tipo incorrecto) | |
| `401 Unauthorized` | Falta credencial válida (el nombre es engañoso: significa «no autenticado») | |
| `403 Forbidden` | Hay credencial, pero no permiso | |
| `404 Not Found` | El recurso no existe (o no quieres revelar que existe) | |
| `409 Conflict` | La petición es válida pero choca con el estado actual | P. ej. enviar un pedido que aún no está pagado |
| `412 Precondition Failed` | Falló un `If-Match` | Ver «Condicionales y caché» |
| `422 Unprocessable Content` | Sintaxis correcta, pero reglas de validación incumplidas (cantidad negativa) | Algunas APIs usan `400` para esto; lo importante es elegir una convención y mantenerla |
| `429 Too Many Requests` | Límite de uso superado | Con cabecera `Retry-After` |
| `500` / `503` | Fallo del servidor / no disponible | Nunca para errores del cliente |

El error más dañino de la tabla es el que no aparece: devolver **`200` con el error en el cuerpo**.

```http
❌ HTTP/1.1 200 OK
   {"success": false, "error": "Pedido no encontrado"}

✅ HTTP/1.1 404 Not Found
   Content-Type: application/problem+json
```

Con el `200`, las cachés guardan el error como si fuera una respuesta buena, las métricas y alertas no ven fallos, y cada cliente tiene que inventar su propio parseo. El formato del cuerpo de error (`application/problem+json`, [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457)) se desarrolla en [Modelado de errores](../contratos-de-api/Modelado-de-Errores.md).

## Un servidor mínimo y el intercambio real

El servidor de ejemplo es una API mínima de ASP.NET Core (.NET 10) con datos en memoria. Fragmento de las rutas de pedidos:

```csharp
app.MapPost("/orders", (OrderInput body) =>
{
    var o = new Order(nextOrder++, body.CustomerId, "pending",
        body.Lines.Select(l => new Line(l.ProductId, l.Quantity,
            products.First(p => p.Id == l.ProductId).Price)).ToList());
    orders[o.Id] = o;
    return Results.Created($"/orders/{o.Id}", o);   // 201 + Location
});

app.MapDelete("/orders/{id:int}", (int id) =>
{
    if (!orders.TryGetValue(id, out var o)) return Results.NotFound();
    if (o.Status == "shipped") return Results.Conflict();   // 409
    orders.Remove(id);
    return Results.NoContent();                              // 204
});
```

El precio de cada línea lo fija el servidor, no el cliente. Salidas reales contra él, recorriendo la vida de un pedido.

**Crear** (`POST` a la colección; el servidor asigna el id y lo comunica en `Location`):

```bash
curl -i -X POST http://localhost:5099/orders -H "Content-Type: application/json" \
     -d '{"customerId":7,"lines":[{"productId":42,"quantity":2}]}'
```

```http
HTTP/1.1 201 Created
Content-Type: application/json; charset=utf-8
Location: /orders/4713

{"id":4713,"customerId":7,"status":"pending","lines":[{"productId":42,"quantity":2,"unitPrice":59.90}]}
```

**Leer** (`GET /orders/4713`) devuelve `200` con ese mismo cuerpo. **Actualizar** el estado con `PATCH` y un cuerpo parcial:

```bash
curl -i -X PATCH http://localhost:5099/orders/4713 -H "Content-Type: application/json" \
     -d '{"status":"paid"}'
```

```http
HTTP/1.1 200 OK
{"id":4713,"customerId":7,"status":"paid","lines":[{"productId":42,"quantity":2,"unitPrice":59.90}]}
```

**Un `409`**: el pedido `4714` está en `pending` y la regla de negocio exige pasar por `paid` antes de `shipped`. La petición es válida; choca con el estado.

```http
HTTP/1.1 409 Conflict
Content-Type: application/problem+json

{"type":"about:blank","title":"Transición de estado no permitida","status":409,"detail":"Un pedido en estado 'pending' no puede pasar a 'shipped'."}
```

El mismo `409` aparece al borrar un pedido ya enviado (`DELETE /orders/4712`). **Borrar** uno pendiente devuelve `204 No Content` sin cuerpo, y leerlo después da el `404`:

```http
HTTP/1.1 204 No Content

HTTP/1.1 404 Not Found
Content-Length: 0
```

## Paginación, filtrado y ordenación

Una colección sin límite funciona con 20 filas en desarrollo y tumba producción con dos millones. La paginación se define desde el primer día, porque añadirla después cambia el contrato de las respuestas.

| | `offset`/`limit` | Cursor (`after`) |
|---|---|---|
| Petición | `/products?offset=3&limit=3` | `/products?after=42&limit=3` |
| Saltar a la página N | Sí | No (solo «siguiente») |
| Total de elementos | Fácil (`total`) | Costoso o no disponible |
| Coste en tablas grandes | Crece con el offset (la base de datos recorre y descarta filas) | Constante (usa un índice) |
| Datos que cambian mientras se lee | **Salta o repite elementos** | Estable |
| Encaja en | Listados de administración, tablas con «ir a la página 5» | *Feeds*, exportaciones, scroll infinito, tablas grandes |

El problema de las páginas que cambian, con el servidor de ejemplo (productos 40 a 45, páginas de 3):

```text
GET /products?offset=0&limit=3   → ids 40 41 42        (página 1)
DELETE /products/41              → 204                 (alguien borra uno mientras se lee)
GET /products?offset=3&limit=3   → ids 44 45           (página 2)
```

El producto **43 no aparece nunca**: al borrar el 41, todo se desplazó una posición y el `offset=3` empezó después de él. Con una inserción pasa lo contrario y un elemento se repite. Con cursor, la segunda página pide «lo que viene después del 42» y recibe `43 44 45`:

```text
GET /products?after=42&limit=3   → ids 43 44 45
```

En el cursor, el valor de `after` es opaco para el cliente: es la última clave de ordenación vista (aquí el id; en una ordenación por fecha, el par fecha+id, para desempatar). El **formato de la lista** incluye el enlace a la página siguiente, que el cliente sigue sin construir URLs:

```json
{
  "items": [{ "id": 43, "name": "Monitor", "price": 189.00 }],
  "next": "/products?after=45&limit=3"
}
```

Cuando `next` es `null`, no hay más páginas. Para el **filtrado**, parámetros de consulta con el nombre del campo (`/orders?status=paid&customer=7`); para la **ordenación**, un parámetro explícito (`/products?sort=-price,name`, con `-` para descendente). Conviene fijar un `limit` máximo en el servidor (`Math.Clamp` en el ejemplo) y una ordenación por defecto estable: sin ella, ni offset ni cursor son fiables.

## Condicionales y caché HTTP

La caché es la ventaja más desaprovechada de REST. El servidor devuelve un **`ETag`** (huella de la versión actual del recurso); el cliente lo reenvía en `If-None-Match`, y si nada cambió recibe `304` sin cuerpo.

```bash
curl -i http://localhost:5099/orders/4713
```

```http
HTTP/1.1 200 OK
Cache-Control: private, max-age=0, must-revalidate
ETag: "35f23d80400e"

{"id":4713,"customerId":7,"status":"pending", ...}
```

```bash
curl -i http://localhost:5099/orders/4713 -H 'If-None-Match: "35f23d80400e"'
```

```http
HTTP/1.1 304 Not Modified
ETag: "35f23d80400e"
```

La respuesta no lleva cuerpo: ahorra ancho de banda y, si el servidor compara la huella antes de armar el cuerpo (por ejemplo con una columna de versión), también trabajo de base de datos.

El mismo mecanismo, con **`If-Match`** en las escrituras, evita que dos personas editando a la vez se pisen (*optimistic locking*). La petición solo se aplica si el recurso sigue en la versión que el cliente leyó:

```bash
# La persona A leyó la versión "35f23d80400e" y la actualiza: OK, y el ETag cambia
curl -i -X PATCH http://localhost:5099/orders/4713 -H "Content-Type: application/json" \
     -H 'If-Match: "35f23d80400e"' -d '{"status":"paid"}'
# → 200 OK, ETag: "f32bde44f697"

# La persona B, con la versión vieja, intenta lo suyo:
curl -i -X PATCH http://localhost:5099/orders/4713 -H "Content-Type: application/json" \
     -H 'If-Match: "35f23d80400e"' -d '{"status":"shipped"}'
```

```http
HTTP/1.1 412 Precondition Failed
```

B recibe el `412`, vuelve a leer el pedido y decide con los datos actuales. Sin `If-Match`, su cambio habría pisado el de A en silencio. Exigir la cabecera con `428 Precondition Required` cuando falta es una opción para recursos donde el pisado es costoso.

## Idempotencia en operaciones no idempotentes

Un cobro es un `POST` (crea un pago) y no es idempotente. Si el cliente envía el cobro, el servidor lo procesa y la respuesta se pierde por la red, el cliente no sabe si cobró y reintentar puede cobrar dos veces. La solución es que el **cliente genere una clave única por intención de operación** y la envíe en la cabecera `Idempotency-Key`; el servidor recuerda la clave y, si llega repetida, devuelve el resultado ya calculado en vez de ejecutar de nuevo. (La cabecera es un borrador activo del IETF, no un RFC; es la convención de hecho en las APIs de pagos. Consulta: 2026-11-09.)

```csharp
app.MapPost("/payments", (PaymentInput body, HttpContext ctx) =>
{
    var key = ctx.Request.Headers["Idempotency-Key"].ToString();
    if (key == "") return Results.Problem(statusCode: 400, title: "Falta la cabecera Idempotency-Key");

    var hash = JsonSerializer.Serialize(body);
    if (payments.TryGetValue(key, out var prev))
    {
        if (prev.Hash != hash) return Results.Problem(statusCode: 422, title: "Clave ya usada con otro cuerpo");
        ctx.Response.Headers["Idempotent-Replayed"] = "true";
        return Results.Ok(prev.Result);                       // mismo pago, sin cobrar de nuevo
    }
    var pay = new Payment($"pay_{++paymentCount:D4}", body.OrderId, body.Amount, "succeeded");
    payments[key] = (hash, pay);
    return Results.Created($"/payments/{pay.Id}", pay);
});
```

Enviando dos veces el mismo cobro con la misma clave:

```bash
curl -si -X POST http://localhost:5099/payments -H "Content-Type: application/json" \
     -H "Idempotency-Key: 7c9e-4711" -d '{"orderId":4711,"amount":59.90}'
```

```http
HTTP/1.1 201 Created
{"id":"pay_0001","orderId":4711,"amount":59.90,"status":"succeeded"}

HTTP/1.1 200 OK
Idempotent-Replayed: true
{"id":"pay_0001","orderId":4711,"amount":59.90,"status":"succeeded"}
```

El contador de cobros del servidor marca **1**. Con la misma clave y otro importe responde `422` (la clave se reutilizó con una petición distinta, que casi siempre es un fallo del cliente), y sin clave, `400`. En producción el almacén de claves es una tabla o caché compartida entre instancias, con caducidad (24 horas es habitual), y la reserva de la clave debe ser atómica para que dos reintentos simultáneos no se crucen. El ejemplo, en memoria y sin concurrencia, no cubre ese caso.

## HATEOAS y el modelo de madurez de Richardson

El **modelo de madurez de Richardson** ordena las APIs «HTTP» por cuánto aprovechan el estilo:

| Nivel | Qué añade | Ejemplo |
|---|---|---|
| 0 | Un solo endpoint, HTTP como túnel | `POST /api` con la operación en el cuerpo |
| 1 | Recursos con URL propia | `/orders/4711` |
| 2 | Verbos y códigos de estado con su significado | `DELETE /orders/4711` → `204` |
| 3 | **HATEOAS**: la respuesta incluye los enlaces de lo que se puede hacer a continuación | `"links": {"pay": "/orders/4711/payment"}` |

En la práctica, casi todas las APIs que se llaman REST están en el **nivel 2**, y funcionan bien. El nivel 3 (HATEOAS, *hypermedia as the engine of application state*) es el que Fielding considera imprescindible para llamar REST a una API, pero rara vez se implementa de forma completa: los clientes suelen programarse contra el contrato OpenAPI y no descubren las URLs en tiempo de ejecución. Lo que sí se usa de verdad es una parte pequeña: enlaces de paginación (`next`), la cabecera `Location` tras crear y, en algunos casos, enlaces a acciones disponibles según el estado (un pedido pagado ya no ofrece `pay`).

## Versionado

| Opción | Ejemplo | Ventaja | Inconveniente |
|---|---|---|---|
| Ruta | `/v2/orders/4711` | Visible, fácil de probar y de enrutar | La URL de un recurso cambia entre versiones |
| Cabecera propia | `Api-Version: 2` | URLs estables | Invisible en el navegador, más fácil de olvidar en las cachés (`Vary`) |
| Media type | `Accept: application/vnd.tienda.v2+json` | Es la opción más fiel a REST | Tooling menos cómodo |

La ruta es la más usada por simplicidad. Qué cambios exigen versión nueva y cómo gestionarla se explica en [Versionado de contratos](../contratos-de-api/Versionado-de-Contratos.md).

## REST frente a otros estilos

| Necesidad | Estilo | Ficha |
|---|---|---|
| CRUD sobre recursos, API pública, caché HTTP | **REST** | esta |
| Cada pantalla pide un subconjunto distinto de datos (evitar *over/under-fetching*) | GraphQL | [GraphQL](GraphQL.md) |
| Llamadas internas entre servicios, bajo coste y contrato estricto | gRPC | [gRPC](gRPC.md) |
| Operaciones tipo acción («calcular», «enviar», «reindexar») sin recurso claro | RPC | [RPC](RPC.md) |
| Datos en vivo hacia el cliente | WebSockets o SSE | [WebSockets](WebSockets.md), [Server-Sent Events](Server-Sent-Events.md) |

## Cuándo NO usar REST

**Operaciones tipo acción.** «Cancelar el pedido 4711» no es CRUD. Dos formas de modelarlo sin romper el estilo:

- **Sub-recurso**: `POST /orders/4711/cancellation` crea una cancelación, que luego se puede consultar (`GET`) con su estado y fecha. Vale cuando la acción deja un rastro que interesa.
- **`POST` a una acción**: `POST /orders/4711/cancel`, pragmático y legible. Vale cuando la acción es puntual y no hay nada que consultar después.

```http
HTTP/1.1 201 Created
Location: /orders/4711/cancellation

{"orderId":4711,"status":"cancelled"}
```

Cuando casi toda la API son acciones (`/recalculate`, `/reindex`, `/send-invoice`) y los recursos son un disfraz, un estilo [RPC](RPC.md) es más honesto.

**Tiempo real.** REST es petición-respuesta: el servidor no puede avisar. Preguntar cada segundo (*polling*) gasta recursos; para avisos usa [Server-Sent Events](Server-Sent-Events.md), [WebSockets](WebSockets.md) o [Webhooks](Webhooks.md).

**Lecturas muy variables por pantalla.** Si una pantalla necesita el pedido con cliente y productos y otra solo el estado, un endpoint fijo devuelve de más o obliga a encadenar llamadas (`/orders/4711`, luego `/customers/7`, luego cada `/products/42`). Se mitiga con `?expand=customer` o endpoints de resumen; si la variedad es estructural, [GraphQL](GraphQL.md) la resuelve mejor.

## Errores frecuentes

| Síntoma | Causa | Arreglo |
|---|---|---|
| URLs como `/getOrder` o `/orders/delete/4711` | El verbo está en la ruta, duplicando el método HTTP | Sustantivo en la ruta, verbo en el método |
| Un buscador o precargador borra o modifica datos | Un `GET` cambia estado (por ejemplo, `GET /orders/4711/cancel`) | Todo lo que modifica va con `POST`/`PUT`/`PATCH`/`DELETE` |
| Todo es `POST` y el cuerpo dice qué hacer | HTTP usado como túnel (nivel 0) | Verbos con su semántica: se ganan reintentos y caché |
| Clientes que parsean texto para saber si falló | Siempre `200`, o un genérico `500` ante un dato inválido | `4xx` para fallos del cliente, `5xx` solo para los del servidor |
| Pedidos duplicados tras un corte de red | `POST` reintentado sin clave de idempotencia | Cabecera `Idempotency-Key` |
| Dos usuarios editando y uno pierde cambios sin enterarse | Escritura sin `If-Match` | `ETag` + `If-Match`, y `412` |
| Alguien lee pedidos ajenos cambiando `/orders/4711` por `/orders/4712` | Ids autoincrementales y comprobar solo que la persona está autenticada, no que el recurso sea suyo (**BOLA**, *Broken Object Level Authorization*) | Autorización por recurso en cada endpoint; ids no secuenciales como defensa adicional, nunca como la única. Ver [Seguridad en el contrato](../contratos-de-api/Seguridad-en-el-Contrato.md) |

## Buenas prácticas avanzadas

- **Apóyate en la idempotencia de cada verbo.** `PUT` y `DELETE` deben poder repetirse sin cambiar el resultado, porque proxies y librerías reintentan solos. Un `PUT` que «suma 1» en lugar de «fija el valor» duplica efectos en cuanto hay un reintento.
- **Pagina desde el primer día, con cursor si los datos cambian.** Un `limit` máximo en el servidor y una ordenación por defecto estable evitan los dos desastres: respuestas gigantes y elementos que se saltan o repiten.
- **Deja que el servidor decida los datos que no debe decidir el cliente.** Precios, totales y estado inicial salen del servidor (el ejemplo ignora cualquier precio enviado en una línea). El cliente envía intención; el servidor, hechos.
- **Distingue `400`, `404`, `409` y `422` con intención.** `409` para estado incompatible, `422` para reglas de validación y `400` para mensajes mal formados permiten a los clientes reaccionar sin leer el texto.
- **Devuelve `Location` y el recurso al crear.** Tras un `POST`, el cliente suele necesitar el id y el estado inicial; devolver ambos le evita un `GET` más.
- **Ante un recurso inexistente que no debe revelarse, `404` mejor que `403`.** Si el pedido 4712 es de otra persona, un `403` confirma que existe; un `404` no dice nada.

## Documentación oficial

- [RFC 9110: HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110): la definición de métodos, seguridad e idempotencia, códigos de estado y peticiones condicionales. Consúltalo para zanjar qué significa cada código o método.
- [Tesis de Fielding, cap. 5: Representational State Transfer (REST)](https://ics.uci.edu/~fielding/pubs/dissertation/rest_arch_style.htm): el origen del estilo y sus restricciones. Interesa para entender por qué HATEOAS y la interfaz uniforme son parte de la definición.
- [RFC 9457: Problem Details for HTTP APIs](https://www.rfc-editor.org/rfc/rfc9457): formato estándar de los cuerpos de error.

---

*En resumen: REST trata la API como una biblioteca de recursos con URL fija, manejados con los verbos de HTTP; su valor está en usar bien la semántica (verbos, códigos, caché, condicionales) que la web ya trae, no en cumplir un dogma.*
