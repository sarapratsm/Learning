# SDK

## ¿Qué es?

Un **SDK** (*Software Development Kit*) para consumir una API es una biblioteca cliente, escrita para un lenguaje concreto, que envuelve las llamadas de la API en métodos y tipos de ese lenguaje: en lugar de montar una petición HTTP, se llama a `tienda.Orders.GetAsync(4711)`. **No es un tipo de API**: no añade capacidades al servicio, solo cambia la forma de usarlo. Por debajo sigue habiendo [REST](REST.md), [gRPC](gRPC.md) o lo que sea.

## ¿Por qué existe?

Una API web es un contrato «crudo»: URLs, JSON, cabeceras, códigos de estado. Usarla a mano obliga a cada consumidor a resolver los mismos problemas: construir la URL, serializar y deserializar, poner la autenticación, interpretar los errores, recorrer las páginas, decidir qué hacer con un `429`. Cada equipo lo resuelve a su manera y casi todos se equivocan en algún detalle.

El SDK resuelve esos problemas una vez, en el lado de quien publica la API, y todos los consumidores heredan la solución.

> Si la API es el motor de un coche, el SDK es el coche con volante y pedales: el motor es el mismo, pero conducirlo ya no requiere saber de inyección.

## ¿Cuándo y para qué se usa?

Cuando una API se consume desde muchos sitios y por equipos que no conocen su interior: una pasarela de pago, un servicio de almacenamiento, la API pública de la tienda online que usan integradores externos. También dentro de una empresa, si varios servicios consumen la misma API y todos repiten el mismo código de acceso. Quien publica la API decide qué SDK ofrece (ver [APIs por audiencia](APIs-por-Audiencia.md)); quien la consume decide si usa el oficial, genera uno o llama a mano.

## Llamar a mano frente a usar el SDK

El caso: leer el pedido 4711 de la API de la tienda (`https://api.tienda.ejemplo.com`), con autenticación, un error posible y un límite de peticiones que el servidor responde con `429`.

```csharp
// ❌ A mano: cada consumidor reescribe esto
using var http = new HttpClient();
http.DefaultRequestHeaders.Authorization = new("Bearer", apiKey);

for (var intento = 0; intento < 3; intento++)
{
    var response = await http.GetAsync($"https://api.tienda.ejemplo.com/orders/{id}");

    if (response.StatusCode == HttpStatusCode.TooManyRequests)
    {
        var espera = response.Headers.RetryAfter?.Delta ?? TimeSpan.FromSeconds(1);
        await Task.Delay(espera);
        continue;
    }
    if (response.StatusCode == HttpStatusCode.NotFound)
        throw new Exception("El pedido no existe");        // ¿y el código y el cuerpo del error?
    response.EnsureSuccessStatusCode();

    var json = await response.Content.ReadAsStringAsync();
    return JsonSerializer.Deserialize<Order>(json);        // ¿mayúsculas? ¿campos nuevos?
}
throw new Exception("Demasiados intentos");
```

```csharp
// ✅ Con el SDK
var order = await tienda.Orders.GetAsync(4711);
```

El segundo fragmento no es magia: la lógica del primero vive dentro del SDK, escrita y probada una vez. El ejemplo a mano ya contiene tres defectos típicos: un `new HttpClient()` por llamada (ver «Errores frecuentes»), una `Exception` genérica que pierde el código y el cuerpo del error, y un reintento que ningún otro consumidor repetirá igual.

## Qué debería hacer un buen SDK

Envolver las rutas es lo fácil. Lo que separa un SDK útil de uno que estorba:

| Responsabilidad | Qué se espera |
|---|---|
| Autenticación | La clave o el token se configuran una vez; el SDK los pone en cada petición y renueva los tokens que caducan. |
| Serialización y tipos | Clases del lenguaje (`Order`, `OrderLine`), con nulabilidad fiel al contrato; tolerante con campos desconocidos. |
| Errores tipados | Una excepción propia con el código HTTP, el código de error de la API y el cuerpo, no una `Exception` genérica. |
| Paginación transparente | `ListAsync` devuelve un flujo (`IAsyncEnumerable<Order>`) que pide páginas a medida que se consume. |
| Reintentos con espera | Reintenta lo que es seguro reintentar, respeta `Retry-After` y se rinde tras un máximo. |
| Tiempos de espera | Un *timeout* explícito y configurable. |
| Idempotencia | Envía una clave de idempotencia en las operaciones que crean algo, para que reintentar no duplique. |
| Cancelación | Cada método acepta un `CancellationToken`. |
| Registro | Se puede ver qué petición salió y qué respuesta volvió, sin exponer secretos. |
| Versionado | Cada versión del SDK declara contra qué versión de la API se ha probado. |

## Un SDK mínimo funcional

Un `TiendaClient` con `HttpClient` inyectable, `Orders.GetAsync`, `Orders.ListAsync`, una excepción tipada y un reintento ante `429`. Los tipos de datos y la excepción:

```csharp
public sealed record OrderLine(int ProductId, int Quantity, decimal Price);
public sealed record Order(int Id, int CustomerId, string Status, IReadOnlyList<OrderLine> Lines);

public sealed class TiendaApiException : Exception
{
    public HttpStatusCode StatusCode { get; }
    public string? Code { get; }       // el "code" del cuerpo de error de la API
    public string Body { get; }        // el cuerpo completo, para diagnosticar

    public TiendaApiException(HttpStatusCode status, string? code, string message, string body)
        : base($"{(int)status} {code}: {message}")
    { StatusCode = status; Code = code; Body = body; }
}
```

El cliente recibe el `HttpClient` desde fuera (quien lo usa decide el *timeout*, el *handler* y la reutilización) y centraliza el envío con el reintento:

```csharp
public sealed class TiendaClient
{
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private readonly HttpClient _http;
    private readonly int _maxRetries;
    public OrdersApi Orders { get; }

    public TiendaClient(HttpClient http, string apiKey, int maxRetries = 2)
    {
        _http = http;
        _maxRetries = maxRetries;
        _http.BaseAddress ??= new Uri("https://api.tienda.ejemplo.com");
        _http.DefaultRequestHeaders.Authorization = new("Bearer", apiKey);
        Orders = new OrdersApi(this);
    }

    internal async Task<T> GetAsync<T>(string path, CancellationToken ct)
    {
        for (var attempt = 0; ; attempt++)
        {
            using var response = await _http.GetAsync(path, ct);
            if (response.IsSuccessStatusCode)
                return (await response.Content.ReadFromJsonAsync<T>(Json, ct))!;

            if (response.StatusCode == HttpStatusCode.TooManyRequests && attempt < _maxRetries)
            {
                var wait = response.Headers.RetryAfter?.Delta ?? TimeSpan.FromSeconds(Math.Pow(2, attempt));
                await Task.Delay(wait, ct);
                continue;
            }
            throw await ToException(response, ct);   // lee "code" y "message" del cuerpo si los hay
        }
    }
    // ToException: lee el cuerpo y construye TiendaApiException (omitido: son 12 líneas de JsonDocument)
}
```

Y los métodos de pedidos. `ListAsync` es un iterador asíncrono: cada vuelta del `while` es una petición, y solo se hace cuando quien consume pide más elementos:

```csharp
public sealed class OrdersApi
{
    private sealed record Page(List<Order> Items, int? NextPage);
    private readonly TiendaClient _c;
    internal OrdersApi(TiendaClient c) => _c = c;

    public Task<Order> GetAsync(int id, CancellationToken ct = default)
        => _c.GetAsync<Order>($"/orders/{id}", ct);

    public async IAsyncEnumerable<Order> ListAsync([EnumeratorCancellation] CancellationToken ct = default)
    {
        int? page = 1;
        while (page is not null)
        {
            var p = await _c.GetAsync<Page>($"/orders?page={page}&pageSize=3", ct);
            foreach (var o in p.Items) yield return o;
            page = p.NextPage;
        }
    }
}
```

Se ha probado contra un servidor mínimo de ASP.NET Core (.NET 10) con siete pedidos, `4711` a `4717`. Un pedido suelto:

```csharp
var tienda = new TiendaClient(new HttpClient { BaseAddress = new Uri("http://localhost:5937"), Timeout = TimeSpan.FromSeconds(10) }, "sk_test_123");
var o = await tienda.Orders.GetAsync(4711);
Console.WriteLine($"{o.Id} {o.Status} {o.Lines.Count} línea(s)");
```

```text
4711 shipped 1 línea(s)
```

### Paginación transparente

```csharp
await foreach (var x in tienda.Orders.ListAsync()) Console.WriteLine($"{x.Id} {x.Status}");
```

```text
4711 shipped
4712 paid
4713 pending
4714 shipped
4715 paid
4716 pending
4717 shipped
```

Quien llama ve un solo bucle. El registro del servidor muestra las tres peticiones que hizo el SDK por debajo:

```text
[server] GET /orders?page=1&pageSize=3 -> 200
[server] GET /orders?page=2&pageSize=3 -> 200
[server] GET /orders?page=3&pageSize=3 -> 200
```

### Un `429` que se reintenta

El servidor responde `429` con `Retry-After: 1` la primera vez que se pide el pedido 5000:

```text
[sdk] 429, reintento 1 tras 1 s
Order { Id = 5000, CustomerId = 7, Status = paid, ... }
```

El SDK esperó un segundo, el que dictaba el servidor, y la segunda petición devolvió `200`. Quien llamó a `GetAsync(5000)` no se enteró.

### Un `404` convertido en excepción tipada

```csharp
try { await tienda.Orders.GetAsync(9999); }
catch (TiendaApiException e)
{ Console.WriteLine($"{e.GetType().Name}: {e.Message}\nStatusCode={e.StatusCode} Code={e.Code}\nBody={e.Body}"); }
```

```text
TiendaApiException: 404 order_not_found: El pedido 9999 no existe
StatusCode=NotFound Code=order_not_found
Body={"code":"order_not_found","message":"El pedido 9999 no existe"}
```

El código puede decidir con `e.Code == "order_not_found"` sin analizar texto. El formato del cuerpo de error lo define el contrato de la API (ver [Modelado de errores](../contratos-de-api/Modelado-de-Errores.md)); el SDK solo lo traduce a un tipo.

## SDK escrito a mano frente a SDK generado

El mismo contrato OpenAPI que describe la API puede alimentar un generador que produce el cliente de forma mecánica. Es la disyuntiva real al planificar un SDK:

| | A mano | Generado desde OpenAPI |
|---|---|---|
| Ergonomía | La que se diseñe: `tienda.Orders.ListAsync()` con paginación propia | La que dicta el generador: rutas como cadena de objetos, paginación sin resolver |
| Control | Total (reintentos, registro, nombres) | Limitado a lo que el generador permite configurar |
| Mantenimiento | Cada endpoint nuevo es trabajo manual y puede olvidarse | Se regenera con el contrato; la cobertura es completa |
| Consistencia entre lenguajes | Cada lenguaje diverge con el tiempo | Mismo comportamiento y nombres en todos |
| Fidelidad al contrato | La del cuidado de quien escribe | Mecánica: si el contrato cambia, el tipo cambia |
| Cuándo encaja | Pocos endpoints o un lenguaje principal con mucha exigencia de ergonomía | Muchos endpoints, varios lenguajes, contrato bien cuidado |

Es frecuente combinar: un núcleo generado con una capa fina escrita a mano encima (paginación, reintentos, nombres) y regeneración del núcleo en cada versión del contrato.

### Generar un cliente con Kiota

[Kiota](https://learn.microsoft.com/openapi/kiota/) es el generador de clientes de Microsoft; produce C#, Go, Java, PHP, Python, Ruby y TypeScript. Se instala como herramienta de .NET. Con un contrato mínimo de la tienda (`openapi.yaml`, solo `GET /orders/{id}`):

```yaml
openapi: 3.0.3
info:
  title: API de la tienda
  version: 1.0.0
servers:
  - url: http://localhost:5937
paths:
  /orders/{id}:
    get:
      operationId: getOrder
      parameters:
        - name: id
          in: path
          required: true
          schema: { type: integer }
      responses:
        '200':
          description: El pedido
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Order' }
        '404':
          description: El pedido no existe
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Error' }
components:
  schemas:
    Order:
      type: object
      required: [id, customerId, status]
      properties:
        id: { type: integer }
        customerId: { type: integer }
        status: { type: string, enum: [pending, paid, shipped] }
        lines:
          type: array
          items: { $ref: '#/components/schemas/OrderLine' }
    OrderLine:
      type: object
      properties:
        productId: { type: integer }
        quantity: { type: integer }
        price: { type: number }
    Error:
      type: object
      properties:
        code: { type: string }
        message: { type: string }
```

```bash
dotnet tool install Microsoft.OpenApi.Kiota --tool-path ./tools
./tools/kiota --version
./tools/kiota generate -l CSharp -c TiendaApiClient -n Tienda.Kiota -d openapi.yaml -o ./Generated
```

```text
1.38.0+560032020b92acc37ee0fbbe5bddb6527fce9ec5
Generation completed successfully
Client base url set to http://localhost:5937
```

Versión consultada el 2026-11-09. La carpeta `Generated` contiene `TiendaApiClient.cs`, los modelos (`Order.cs`, `OrderLine.cs`, `Order_status.cs`, `Error.cs`), un constructor de peticiones por ruta (`OrdersRequestBuilder.cs`, `OrdersItemRequestBuilder.cs`) y `kiota-lock.json`, que recuerda con qué opciones se generó. El proyecto que lo usa necesita el paquete `Microsoft.Kiota.Bundle` (se probó la 2.1.6). Contra el mismo servidor de antes:

```csharp
var adapter = new HttpClientRequestAdapter(new AnonymousAuthenticationProvider());
var client = new TiendaApiClient(adapter);

var order = await client.Orders[4711].GetAsync();
Console.WriteLine($"{order!.Id} {order.Status} {order.Lines!.Count} línea(s)");

try { await client.Orders[9999].GetAsync(); }
catch (Tienda.Kiota.Models.Error e)
{ Console.WriteLine($"{e.GetType().FullName}: {e.Message} | Code={e.Code} | HTTP {e.ResponseStatusCode}"); }
```

```text
4711 Shipped 1 línea(s)
Tienda.Kiota.Models.Error: El pedido 9999 no existe | Code=order_not_found | HTTP 404
```

Dos observaciones: el `404` declarado en el contrato se convierte en una excepción tipada (`Error`) sin escribir código, y todas las propiedades del modelo generado son anulables (`int? Id`, `Status?`), incluso las marcadas como `required` en el contrato; por eso el ejemplo usa `!`. Además, el modelo trae un `AdditionalData` donde caen los campos que el contrato no declara, de modo que un campo nuevo del servidor no rompe la deserialización (opción `includeAdditionalData: true` del `kiota-lock.json` generado). Cómo se ve cada decisión del esquema (obligatorio, anulable, `enum`, campos desconocidos) desde el cliente generado lo explica [additionalProperties y clientes generados](../contratos-de-api/Additional-Properties-y-Clientes-Generados.md). Y [Contrato primero](../contratos-de-api/Contrato-Primero.md) explica por qué conviene que el contrato exista antes que el código, que es lo que hace posible generar.

El cliente de Kiota no incluye por sí solo paginación transparente ni reglas de reintento propias de la tienda: para eso está la capa fina a mano.

## El SDK como parte del producto

En una API pública, el SDK es parte de lo que se vende: es lo primero que toca quien integra, y sus errores se atribuyen a la API.

### Versionado del SDK frente a versionado de la API

El SDK se versiona con [versionado semántico](https://semver.org/lang/es/) (`MAJOR.MINOR.PATCH`). Su versión es independiente de la de la API: un SDK `2.4.1` puede hablar con la API `v1`. Qué cambio de la API obliga a qué cambio del SDK:

| Cambio en la API | Efecto en el SDK | Versión del SDK |
|---|---|---|
| Endpoint nuevo | Método nuevo; no rompe a nadie | Menor |
| Campo nuevo opcional en una respuesta | Propiedad nueva en el tipo | Menor |
| Campo nuevo opcional en una petición | Parámetro opcional nuevo | Menor |
| Valor nuevo en un `enum` de respuesta | Valor nuevo en el `enum`; un `switch` exhaustivo del consumidor puede romperse | Menor (con nota en el *changelog*) o mayor si se cierra el `enum` |
| Campo de petición pasa a ser obligatorio | Firma del método cambia | Mayor |
| Campo o endpoint eliminado | Método o propiedad desaparece | Mayor |
| Cambio de tipo de un campo | El tipo de la propiedad cambia | Mayor |
| Nueva versión mayor de la API (`/v2`) | El SDK mayor nuevo apunta a `v2`; el anterior sigue apuntando a `v1` | Mayor |
| Corrección interna (mensaje de error, cabecera) | Sin cambio en la firma | Parche |

### Compatibilidad y deprecación

Dentro de una misma versión mayor, el SDK no quita nada: lo que se queda anticuado se marca con `[Obsolete]` y el mensaje dice qué usar y cuándo desaparece.

```csharp
[Obsolete("Usa ListAsync(). Se eliminará en la versión 3.0.")]
public Task<List<Order>> ListAllAsync() { /* ... */ }
```

```text
warning CS0618: 'OrdersApi.ListAllAsync()' está obsoleto: 'Usa ListAsync(). Se eliminará en la versión 3.0.'
```

El compilador avisa a quien llama en cada compilación; el método sigue funcionando hasta el siguiente cambio mayor. Pasar `error: true` a `[Obsolete]` convierte el aviso en error, para la versión intermedia en la que ya no debería usarse.

### Distribución

En .NET, el SDK es un paquete NuGet con su versión semántica; en otros lenguajes, un paquete npm, PyPI, Maven, etc. Hay **un paquete por lenguaje**, y cada uno es producto aparte con su *changelog*. Un SDK para consumo público necesita, además del paquete, documentación y ejemplos ejecutables por método: sin ellos, quien integra acaba leyendo el código del SDK o llamando a la API a mano.

## Lo que un SDK oculta de más

La comodidad del SDK es también su riesgo: esconde decisiones que el consumidor no sabe que existen. Tres trampas, cada una con su resultado.

### El reintento ciego de operaciones no idempotentes

Una operación es **idempotente** si repetirla produce el mismo resultado que hacerla una vez (`GET`, `PUT`, `DELETE`). Un `POST` que crea un pedido no lo es. El servidor de pruebas registra el pedido pero responde `503` la primera vez, de modo que el cliente no sabe si se creó. Un SDK que reintenta sin pensar:

```text
intento 1: 503
intento 2: 201
ciego:       {"created":2,"postAttempts":2,"listRequests":0}
```

Dos pedidos creados para una sola orden del cliente. Con una clave de idempotencia (cabecera `Idempotency-Key`, que el servidor reconoce y devuelve el pedido ya creado en lugar de crear otro), el mismo flujo:

```csharp
// El SDK genera una clave por operación y la repite en cada reintento
var key = Guid.NewGuid().ToString();
var id = await tienda.Orders.CreateAsync(key);
```

```text
intento 1: 503 unavailable: Servicio no disponible
intento 2: pedido 9001
idempotente: {"created":1,"postAttempts":2,"listRequests":0}
```

Dos intentos, un pedido. La regla: el SDK reintenta solo lo idempotente, o lo que lleva clave de idempotencia. Esa cabecera no es un estándar cerrado: es una convención que el servidor debe implementar, así que el SDK la usa solo si la API la documenta.

### La paginación que carga todo en memoria

Un `ListAsync` que devuelve `Task<List<Order>>` obliga a recorrer todas las páginas antes de entregar nada. Con `IAsyncEnumerable<Order>`, quien consume puede parar cuando tiene bastante:

```csharp
await foreach (var x in tienda.Orders.ListAsync()) { Console.WriteLine(x.Id); if (x.Id == 4712) break; }
```

```text
4711
4712
{"created":0,"postAttempts":0,"listRequests":1}
```

Dos pedidos, una sola petición al servidor (`listRequests: 1`). Una lista completa habría hecho las tres peticiones y retenido los siete pedidos; con un catálogo de cientos de miles, esa diferencia es memoria y tiempo reales.

### Los errores genéricos

Un SDK que lanza `Exception("Error en la llamada")` obliga a quien lo usa a analizar el texto del mensaje para saber si fue un `404`, un `429` o un fallo de red. La excepción tipada del apartado anterior (`TiendaApiException` con `StatusCode`, `Code` y `Body`) permite `catch (TiendaApiException e) when (e.Code == "order_not_found")`.

## Seguridad

La clave de la API es un secreto, y dónde corre el SDK decide si se puede guardar.

| SDK de... | Corre en | ¿Puede llevar la clave secreta? |
|---|---|---|
| Servidor | Un backend que controla quien lo usa | Sí, en configuración o en un gestor de secretos, nunca en el repositorio |
| Cliente (móvil, navegador, escritorio) | El dispositivo de la persona usuaria | No: cualquiera puede extraerla del paquete o del tráfico |

Una aplicación móvil que incluye `sk_test_123` en el código distribuye esa clave a todos los dispositivos donde se instale. Un SDK pensado para clientes públicos usa credenciales de alcance limitado (claves públicas con permisos de solo lectura, o tokens de corta duración que emite el propio backend). Cómo se describe la seguridad en el contrato está en [Seguridad en el contrato](../contratos-de-api/Seguridad-en-el-Contrato.md).

## Cuándo NO hace falta un SDK

- **Pocos endpoints.** Con tres rutas, un `HttpClient` bien configurado y un par de clases cuesta menos que mantener un paquete.
- **API interna con un único consumidor.** Quien la consume y quien la publica son el mismo equipo; el SDK sería una capa más sin beneficiario.
- **El contrato generado basta.** Si el cliente que sale de OpenAPI ya cubre lo que se necesita, no hay motivo para envolverlo.
- **Cuando se puede garantizar el mantenimiento.** Un SDK abandonado que se queda atrás de la API es peor que no tenerlo: sus tipos mienten.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Tras muchas llamadas seguidas fallan con errores de conexión o de puertos agotados, y el servidor está bien | Se crea un `HttpClient` nuevo por llamada (o el SDK crea uno por operación) |
| `catch (Exception)` para distinguir un `404` de un fallo de red | El SDK lanza `Exception` genérica en lugar de un tipo propio |
| El SDK no compila o falla al cargarse en un proyecto antiguo | Apunta solo a la última versión de .NET en lugar de a `netstandard2.0` o a varios *target frameworks* |
| La aplicación deja de leer pedidos el día que el servidor añade un campo | Deserialización estricta: el SDK rechaza propiedades que no conoce |
| Una petición se queda colgada minutos | No hay *timeout* configurado y el valor por defecto es muy largo |
| Aparecen pedidos duplicados tras un fallo de red | El SDK reintenta `POST` sin clave de idempotencia |

### Un `HttpClient` nuevo por llamada

Con el servidor local, 500 peticiones seguidas creando y desechando un `HttpClient` cada vez, y contando las conexiones que quedan en el sistema operativo:

```bash
dotnet run -- sockets 500 new
netstat -an | grep ":5937" | awk '{print $NF}' | sort | uniq -c
```

```text
hecho 500 new
      4 CLOSED
      1 FIN_WAIT_1
    491 TIME_WAIT
```

Cada `HttpClient` abre su propia conexión, la cierra al desecharse, y el sistema operativo retiene el puerto en `TIME_WAIT` durante un tiempo. Medido en Windows el 2026-11-09, con un servidor local; la cantidad exacta y el tiempo de retención dependen del sistema operativo. Con un único `HttpClient` compartido, 500 peticiones más no añadieron conexiones nuevas (el recuento no creció). La documentación de Microsoft lo explica así: *«If the rate of requests is high, the operating system limit of available ports might be exhausted. To avoid port exhaustion problems, reuse `HttpClient` instances for as many HTTP requests as possible.»* La solución: un `HttpClient` de larga vida con `PooledConnectionLifetime` configurado, o clientes de vida corta creados por `IHttpClientFactory`.

### Sin *timeout* por defecto

```csharp
Console.WriteLine("HttpClient.Timeout por defecto: " + new HttpClient().Timeout);
```

```text
HttpClient.Timeout por defecto: 00:01:40
```

Cien segundos. Un SDK que no fija el suyo hace que la aplicación espere casi dos minutos por un servidor caído. El SDK debe exponer un *timeout* propio con un valor más corto, y permitir cancelar con `CancellationToken`.

### Deserialización estricta

Si el servidor añade un campo `carrier` a la respuesta y el SDK deserializa con `UnmappedMemberHandling = Disallow`:

```text
{"id":4711,"customerId":7,"status":"shipped","lines":[...],"carrier":"Correos"}
JsonException: The JSON property 'carrier' could not be mapped to any .NET member contained in type 'Tienda.Order'.
```

Con la configuración por defecto de `System.Text.Json`, el mismo cuerpo se deserializa y `carrier` se ignora. Un cambio aditivo del servidor no debería romper a un SDK ya publicado. El contrato conviene decidirlo a propósito, como explica [additionalProperties y clientes generados](../contratos-de-api/Additional-Properties-y-Clientes-Generados.md).

## Buenas prácticas avanzadas

- **Envuelve el SDK de terceros tras una interfaz propia.** Si `PaymentClient` y sus clases aparecen por toda la aplicación, cambiar de proveedor o probar sin llamar a la API real obliga a reescribir. Una interfaz con *tus* tipos (`IPaymentGateway`) y un adaptador que es lo único que conoce al proveedor (patrón *adapter*) cuesta poco y se paga solo.
- **Inyecta el `HttpClient`, no lo construyas dentro.** Quien integra decide el *timeout*, el *handler*, el proxy y las pruebas con un `HttpMessageHandler` falso. Un SDK que hace `new HttpClient()` por dentro quita todas esas opciones y reproduce el problema de los sockets.
- **Reintenta solo lo seguro y con espera.** `GET`, `PUT` y `DELETE` por defecto; `POST` solo con clave de idempotencia. Respeta `Retry-After` (ver [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html)) cuando existe y usa una espera creciente con un máximo de intentos cuando no. El reintento sin límite convierte un fallo transitorio en una avalancha contra un servidor ya sobrecargado.
- **Ancla la versión del SDK y lee el *changelog* antes de actualizar.** Los SDK cambian comportamientos sutiles (reintentos por defecto, formato de fechas, nombres) sin que el código deje de compilar. Fijar la versión exacta y tratar cada actualización como un cambio funcional evita sorpresas.
- **Tolera lo que no conoce.** Campos desconocidos, valores de `enum` nuevos y cabeceras adicionales no deberían romper al SDK; una rama `default` («estado desconocido») y deserialización permisiva dejan evolucionar a la API sin versionar el SDK cada vez.
- **Activa el registro de peticiones cuando algo falle.** Un error opaco del SDK casi siempre se explica comparando la petición HTTP que construyó con la documentación de la API. Registrar método, URL, estado y *request id*, sin cabeceras de autenticación ni cuerpos con datos personales, es lo que permite diagnosticar sin exponer secretos.

## Documentación oficial

- [Directrices de uso de `HttpClient` (Microsoft Learn)](https://learn.microsoft.com/dotnet/fundamentals/networking/http/httpclient-guidelines) — la sección sobre la vida del cliente explica el agotamiento de puertos, `PooledConnectionLifetime` y cuándo preferir `IHttpClientFactory`. Para quien escribe o evalúa un SDK en .NET.
- [`IHttpClientFactory` (Microsoft Learn)](https://learn.microsoft.com/dotnet/core/extensions/httpclient-factory) — cómo registrar clientes con nombre o tipados e inyectarlos; el camino habitual cuando el SDK se usa dentro de una aplicación ASP.NET Core.
- [Kiota (Microsoft Learn)](https://learn.microsoft.com/openapi/kiota/) — qué es el generador, los lenguajes que soporta y la guía de uso de la herramienta; punto de partida para generar el cliente desde un contrato OpenAPI.
- [`HttpClient.Timeout` (Microsoft Learn)](https://learn.microsoft.com/dotnet/api/system.net.http.httpclient.timeout) — el valor por defecto (100 segundos).

---

*En resumen: un SDK no es un tipo de API sino la biblioteca que la envuelve; vale lo que valgan sus decisiones ocultas (reintentos, paginación, errores y timeouts), y por eso un buen SDK es el que no esconde nada que quien lo usa necesite saber.*
