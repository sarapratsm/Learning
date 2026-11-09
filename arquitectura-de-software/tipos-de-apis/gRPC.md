# gRPC

## ¿Qué es?

**gRPC** es un framework de [RPC](RPC.md) creado por Google en el que el contrato se escribe en un fichero `.proto`, de él se genera el código de cliente y servidor, y los mensajes viajan en un formato binario (**Protocol Buffers**, o *protobuf*) sobre HTTP/2.

## ¿Por qué existe?

Entre dos servicios de la tienda, «dame el pedido 4711» con JSON sobre HTTP/1.1 tiene tres costes:

- **Sin contrato fuerte.** El JSON no declara tipos: si el servicio de pedidos renombra `unitPrice` a `unitPriceCents`, el cliente lo descubre en ejecución.
- **Texto verboso.** Cada mensaje repite los nombres de los campos y escribe los números como dígitos; cada extremo debe analizar ese texto.
- **Sin streaming nativo.** «Avisar cuando el pedido cambie de estado» obliga a sondear o a montar otro canal ([WebSockets](WebSockets.md), [SSE](Server-Sent-Events.md)).

gRPC resuelve los tres: el contrato `.proto` genera clases tipadas, protobuf codifica cada campo con un número en lugar de un nombre, y HTTP/2 permite que una misma conexión lleve flujos de mensajes en ambos sentidos.

> Es como pasar de enviar cartas manuscritas con el nombre de cada campo («Cliente: 17, Estado: pagado…») a rellenar un formulario con casillas numeradas que las dos partes ya tienen impreso: cabe mucho más en cada envío, pero sin el formulario el contenido no se entiende.

## ¿Cuándo y para qué se usa?

Su terreno es la comunicación **interna entre servicios**: el servicio de pedidos que consulta al de inventario o al de pagos cientos de veces por segundo, con un contrato que ambos equipos comparten y compilan. También encaja donde hay flujos continuos (seguimiento de estado, telemetría). No es la opción para una API pública consumida desde navegadores o por terceros que no controlas (véase la tabla de decisión más abajo).

## El contrato en `.proto`

El contrato de la tienda: un servicio `OrderService` con operaciones y los mensajes que intercambian.

```proto
syntax = "proto3";

import "google/protobuf/timestamp.proto";

option csharp_namespace = "Tienda.Grpc";

package tienda.orders.v1;

service OrderService {
  rpc GetOrder (GetOrderRequest) returns (Order);
  rpc WatchOrderStatus (GetOrderRequest) returns (stream OrderStatusUpdate);
}

message GetOrderRequest {
  int32 order_id = 1;
}

message Order {
  int32 id = 1;
  int32 customer_id = 2;
  OrderStatus status = 3;
  repeated OrderLine lines = 4;
  google.protobuf.Timestamp created_at = 5;
}

message OrderLine {
  int32 product_id = 1;
  int32 quantity = 2;
  int64 unit_price_cents = 3;
}

message OrderStatusUpdate {
  int32 order_id = 1;
  OrderStatus status = 2;
}

enum OrderStatus {
  ORDER_STATUS_UNSPECIFIED = 0;
  ORDER_STATUS_PENDING = 1;
  ORDER_STATUS_PAID = 2;
  ORDER_STATUS_SHIPPED = 3;
}
```

Lo que conviene saber de cada pieza:

- **Tipos escalares**: `int32`, `int64`, `string`, `bool`, `double`, `bytes`... Los importes van en céntimos (`int64`) porque `double` no representa bien el dinero.
- **`repeated`**: una lista (`lines` es una lista de `OrderLine`). Una lista vacía y una ausente son lo mismo.
- **`enum`**: el primer valor debe ser `0` y es el que se asume cuando el campo falta; por convención se llama `..._UNSPECIFIED`.
- **`google.protobuf.Timestamp`**: tipo estándar para instantes (segundos y nanosegundos desde 1970 en UTC); en C# se convierte con `ToDateTime()` y `Timestamp.FromDateTime(...)`.
- **`package`**: espacio de nombres del contrato. Con `v1` incluido, una futura versión incompatible convive como `v2` (el versionado de contratos se trata en [Versionado de contratos](../contratos-de-api/Versionado-de-Contratos.md)).
- **Los números de campo** (`= 1`, `= 2`…) son lo que viaja por la red; los nombres no se envían nunca. Por eso son la identidad real del campo y no se pueden cambiar ni reutilizar (véase «Evolucionar el contrato sin romper a nadie»). Los números del 1 al 15 ocupan un solo byte en la etiqueta del campo: se reservan para los más frecuentes.

Cada campo ausente toma su valor por defecto (`0`, cadena vacía, lista vacía); proto3 no distingue «ausente» de «cero» salvo que el campo se declare `optional`.

## Un servicio y un cliente completos

Dos proyectos de .NET 10 que comparten `orders.proto`. El proyecto del servidor referencia `Grpc.AspNetCore` y el del cliente `Grpc.Net.Client`, `Google.Protobuf` y `Grpc.Tools` (que genera el código C# al compilar). Versiones usadas, consultadas en NuGet el 2026-11-09: `Grpc.AspNetCore` 2.85.0, `Grpc.Net.Client` 2.85.0, `Grpc.Tools` 2.85.0, `Google.Protobuf` 3.36.2.

El fichero del servidor indica al compilador qué generar:

```xml
<ItemGroup>
  <PackageReference Include="Grpc.AspNetCore" Version="2.85.0" />
  <Protobuf Include="../Protos/orders.proto" GrpcServices="Server" />
</ItemGroup>
```

La implementación hereda de la clase base generada (`OrderService.OrderServiceBase`) y sobrescribe cada operación:

```csharp
using Google.Protobuf.WellKnownTypes;
using Grpc.Core;
using Tienda.Grpc;

public class OrderServiceImpl : OrderService.OrderServiceBase
{
    private static readonly Order Order4711 = new()
    {
        Id = 4711,
        CustomerId = 17,
        Status = OrderStatus.Paid,
        CreatedAt = Timestamp.FromDateTime(new DateTime(2026, 11, 9, 10, 30, 0, DateTimeKind.Utc)),
        Lines =
        {
            new OrderLine { ProductId = 42, Quantity = 2, UnitPriceCents = 1999 },
            new OrderLine { ProductId = 77, Quantity = 1, UnitPriceCents = 4950 }
        }
    };

    public override Task<Order> GetOrder(GetOrderRequest request, ServerCallContext context)
    {
        if (request.OrderId <= 0)
            throw new RpcException(new Status(StatusCode.InvalidArgument, "order_id debe ser positivo"));
        if (request.OrderId != 4711)
            throw new RpcException(new Status(StatusCode.NotFound, $"El pedido {request.OrderId} no existe"));
        return Task.FromResult(Order4711);
    }
}
```

`Program.cs` del servidor:

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddGrpc();

var app = builder.Build();
app.MapGrpcService<OrderServiceImpl>();
app.Run();
```

El cliente crea un canal, construye el cliente generado y llama como si fuera un método local:

```csharp
using Grpc.Core;
using Grpc.Net.Client;
using Tienda.Grpc;

using var channel = GrpcChannel.ForAddress("http://localhost:5100");
var client = new OrderService.OrderServiceClient(channel);

var order = await client.GetOrderAsync(new GetOrderRequest { OrderId = 4711 });
var total = order.Lines.Sum(l => l.Quantity * l.UnitPriceCents);
Console.WriteLine($"Pedido {order.Id} del cliente {order.CustomerId}: {order.Status}, creado {order.CreatedAt.ToDateTime():u}");
foreach (var l in order.Lines)
    Console.WriteLine($"  producto {l.ProductId} x{l.Quantity} a {l.UnitPriceCents / 100m:F2} EUR");
Console.WriteLine($"  total: {total / 100m:F2} EUR");
```

Salida real (ejecutado el 2026-11-09 con .NET 10.0.401; la coma decimal es de la configuración regional de la máquina):

```text
Pedido 4711 del cliente 17: Paid, creado 2026-11-09 10:30:00Z
  producto 42 x2 a 19,99 EUR
  producto 77 x1 a 49,50 EUR
  total: 89,48 EUR
```

Para desarrollo local sin certificado, el ejemplo usa `http://` con el puerto fijado en `launchSettings.json` (`http://localhost:5100`) y el endpoint en HTTP/2 sin TLS (`"Kestrel": { "EndpointDefaults": { "Protocols": "Http2" } }` en `appsettings.json`). En producción se usa `https://`.

La autenticación de las llamadas (tokens en metadatos, certificados de cliente) no se trata aquí; véase [Autenticación y autorización](../../seguridad/autenticacion-y-autorizacion/README.md).

## Los cuatro tipos de llamada

El contrato declara el tipo con la palabra `stream` en la petición, en la respuesta o en ambas.

| Tipo | Declaración en `.proto` | Caso en la tienda |
| --- | --- | --- |
| Unaria | `rpc GetOrder (Req) returns (Order)` | Consultar el pedido 4711 |
| Streaming de servidor | `rpc WatchOrderStatus (Req) returns (stream Update)` | Seguir el estado del pedido hasta que se envíe |
| Streaming de cliente | `rpc UploadLines (stream OrderLine) returns (Summary)` | Enviar cientos de líneas de un pedido masivo y recibir un resumen al final |
| Bidireccional | `rpc Chat (stream Msg) returns (stream Msg)` | Una conversación de soporte en vivo, con mensajes en ambos sentidos a la vez |

El streaming de servidor, ejecutado. En el servidor, el método escribe en un `IServerStreamWriter` cada vez que hay novedad (aquí, con una espera de 500 ms entre estados para simular el avance del pedido):

```csharp
public override async Task WatchOrderStatus(GetOrderRequest request,
    IServerStreamWriter<OrderStatusUpdate> responseStream, ServerCallContext context)
{
    foreach (var status in new[] { OrderStatus.Pending, OrderStatus.Paid, OrderStatus.Shipped })
    {
        await Task.Delay(500, context.CancellationToken);
        await responseStream.WriteAsync(new OrderStatusUpdate { OrderId = request.OrderId, Status = status });
    }
}
```

El cliente lee el flujo con `ReadAllAsync()` hasta que el servidor lo cierra:

```csharp
using var call = client.WatchOrderStatus(new GetOrderRequest { OrderId = 4711 });
var t0 = DateTime.UtcNow;
await foreach (var u in call.ResponseStream.ReadAllAsync())
    Console.WriteLine($"  +{(DateTime.UtcNow - t0).TotalMilliseconds,5:F0} ms  {u.Status}");
```

```text
  +  513 ms  Pending
  + 1017 ms  Paid
  + 1523 ms  Shipped
```

Cada línea llega en cuanto el servidor la escribe, por la misma llamada, sin que el cliente vuelva a preguntar. Los tipos de streaming de cliente y bidireccional no se ejecutan aquí: siguen el mismo patrón con `IAsyncStreamReader<T>` en el servidor y `RequestStream.WriteAsync` en el cliente.

## HTTP/2 y lo que implica

gRPC usa HTTP/2 por tres razones técnicas: **multiplexación** (muchas llamadas simultáneas, cada una un *stream* independiente, por una sola conexión TCP), **streaming** bidireccional dentro de cada llamada y **cabeceras comprimidas** (HPACK). Las consecuencias prácticas están en la infraestructura que rodea al servicio:

- **HTTP/2 es obligatorio.** Un cliente gRPC contra un endpoint que solo habla HTTP/1.1 falla. Con un servidor Kestrel configurado solo para HTTP/1 (`Protocols: Http1`), el cliente del ejemplo termina con:

  ```text
  Grpc.Core.RpcException: Status(StatusCode="Internal", Detail="Error starting gRPC call. HttpRequestException: The HTTP/2 server closed the connection. HTTP/2 error code 'HTTP_1_1_REQUIRED' (0xd). (HttpProtocolError) ...
  ```

  Y a la inversa, con `curl --http1.1` contra un endpoint solo HTTP/2: `400 Bad Request` y el texto `An HTTP/1.x request was sent to an HTTP/2 only endpoint.`
- **Balanceadores y proxys.** Como la conexión es única y larga, un balanceador de capa 4 (por conexión) manda todas las llamadas de un cliente a la misma instancia y deja las demás ociosas (lo confirma la documentación de Microsoft sobre balanceo de carga, consultada el 2026-11-09). Hace falta un proxy de capa 7 que entienda HTTP/2 y reparta por llamada, o balanceo del lado del cliente. Antes de poner un proxy delante, conviene comprobar que soporta HTTP/2 de extremo a extremo y los *trailers* (donde gRPC envía el código de estado).
- **Navegadores.** Un navegador no puede llamar directamente a un servicio gRPC: ninguno da el control sobre las peticiones HTTP/2 que el protocolo necesita (lo dice la documentación de Microsoft, consultada el 2026-11-09). La alternativa es **gRPC-Web**, una variante del protocolo que sí cabe en las APIs del navegador, con un middleware en el servidor o un proxy que traduce; soporta llamadas unarias y de streaming de servidor, pero no el streaming de cliente ni el bidireccional.

## Cómo se ve en la red frente a REST

Mismo pedido 4711 (dos líneas, cliente 17, estado pagado, fecha), serializado con `System.Text.Json` y con protobuf (`ToByteArray()`).

JSON (192 bytes):

```json
{"id":4711,"customerId":17,"status":"paid","createdAt":"2026-11-09T10:30:00Z","lines":[{"productId":42,"quantity":2,"unitPriceCents":1999},{"productId":77,"quantity":1,"unitPriceCents":4950}]}
```

Protobuf (33 bytes, en hexadecimal):

```text
08E724101118022207082A100218CF0F2207084D100118D6262A0608A8C1C6D706
```

| Mensaje | JSON | Protobuf | Relación |
| --- | --- | --- | --- |
| Pedido 4711 (2 líneas) | 192 bytes | 33 bytes | 17 % |
| Pedido de 1000 líneas | 58 085 bytes | 12 014 bytes | 21 % |

Medido el 2026-11-09. El resultado depende de los datos: protobuf gana más cuanto más pesan los nombres de campo y los números pequeños (un `int32` pequeño ocupa 1 o 2 bytes; uno grande, hasta 5), y menos cuando el mensaje es sobre todo texto largo (un `string` ocupa lo mismo en ambos formatos). Con compresión gzip sobre HTTP el JSON se acerca, aunque sigue habiendo coste de análisis. Los números anteriores son del cuerpo; las cabeceras HTTP/2 y el marco de gRPC (5 bytes por mensaje) se suman aparte.

La ganancia real de red suele ser menor que la de CPU y latencia que se nota en volumen; con pocas llamadas por segundo, la diferencia rara vez justifica por sí sola cambiar de REST a gRPC.

## Errores: códigos de estado y `RpcException`

gRPC no usa los códigos HTTP (la respuesta HTTP es casi siempre `200`): el resultado va en un **código de estado propio** más un mensaje, enviados en los *trailers* de la respuesta. Los más habituales y su equivalente HTTP aproximado:

| Código gRPC | Significado | HTTP aproximado | ¿Reintentable? |
| --- | --- | --- | --- |
| `InvalidArgument` | Petición mal formada o con valores no válidos | 400 | No |
| `NotFound` | El recurso no existe | 404 | No |
| `AlreadyExists` | Se intenta crear lo que ya existe | 409 | No |
| `PermissionDenied` | Identificado, pero sin permiso | 403 | No |
| `Unauthenticated` | Faltan credenciales válidas | 401 | No |
| `FailedPrecondition` | El estado actual no permite la operación (pedido ya enviado) | 400 / 409 | No |
| `DeadlineExceeded` | Venció el plazo de la llamada | 504 | Según el caso |
| `Unavailable` | Servicio caído o red cortada | 503 | Sí |
| `Internal` / `Unknown` | Error del servidor sin traducir | 500 | No |

La correspondencia es orientativa; la tabla oficial está en la documentación de gRPC. El servidor lanza un `RpcException`, como en el servicio de arriba; el cliente la captura y lee el código y el detalle:

```csharp
foreach (var id in new[] { 9999, 0 })
{
    try { await client.GetOrderAsync(new GetOrderRequest { OrderId = id }); }
    catch (RpcException ex)
    {
        Console.WriteLine($"Error con order_id={id}: {ex.StatusCode} - {ex.Status.Detail}");
    }
}
```

```text
Error con order_id=9999: NotFound - El pedido 9999 no existe
Error con order_id=0: InvalidArgument - order_id debe ser positivo
```

Una excepción que escapa sin traducir llega al cliente como `Unknown` o `Internal`. Para errores con estructura (un campo concreto inválido, un identificador de reintento), gRPC define el **error rico** `google.rpc.Status`, que adjunta mensajes tipados al código; en .NET se usa con el paquete `Grpc.StatusProto` (no probado aquí). El formato de errores para REST se trata en [Modelado de errores](../contratos-de-api/Modelado-de-Errores.md).

## Plazos y cancelación

Una llamada sin plazo espera indefinidamente. El cliente fija un **deadline** (instante absoluto) y gRPC lo envía al servidor, que lo ve en `context.Deadline` y recibe la cancelación en `context.CancellationToken` cuando vence.

Un método lento en el servidor, que simula trabajo de 5 segundos y lo abandona al cancelarse:

```csharp
public override async Task<Order> GetOrderSlow(GetOrderRequest request, ServerCallContext context)
{
    Console.WriteLine($"[servidor] plazo recibido: {context.Deadline:HH:mm:ss.fff} UTC (quedan {(context.Deadline - DateTime.UtcNow).TotalMilliseconds:F0} ms)");
    try { await Task.Delay(5000, context.CancellationToken); }
    catch (OperationCanceledException)
    {
        Console.WriteLine("[servidor] llamada cancelada: el plazo ha vencido, dejo de trabajar");
        throw;
    }
    return Order4711;
}
```

El cliente da 1 segundo:

```csharp
try
{
    await client.GetOrderSlowAsync(new GetOrderRequest { OrderId = 4711 },
        deadline: DateTime.UtcNow.AddSeconds(1));
}
catch (RpcException ex)
{
    Console.WriteLine($"Plazo: {ex.StatusCode} - {ex.Status.Detail}");
}
```

Salida real. Cliente:

```text
Plazo: DeadlineExceeded - 
```

Servidor:

```text
[servidor] plazo recibido: 09:19:40.792 UTC (quedan 986 ms)
[servidor] llamada cancelada: el plazo ha vencido, dejo de trabajar
```

El cliente recibe `DeadlineExceeded` (con el detalle vacío) al cumplirse el segundo, y el servidor deja de gastar recursos en una respuesta que nadie espera. Cuando un servicio llama a otro, el plazo restante se propaga al registrar el cliente con `AddGrpcClient<T>().EnableCallContextPropagation()` (no probado aquí).

## Evolucionar el contrato sin romper a nadie

Como en la red solo viajan números de campo y tipos, lo compatible y lo incompatible se decide ahí.

| Cambio | ¿Compatible? |
| --- | --- |
| Añadir un campo con número nuevo | Sí: los clientes antiguos lo ignoran y los nuevos reciben el valor por defecto si el servidor antiguo no lo envía |
| Añadir un valor a un `enum` | Con cuidado: un cliente antiguo recibe un número que no conoce |
| Renombrar un campo | Sí en el cable (el nombre no viaja); rompe el código fuente de quien lo use y el JSON si se transcodifica |
| Cambiar el tipo de un número de campo | No |
| Reutilizar el número de un campo eliminado | No, y sin error visible |
| Eliminar un campo | Sí, si se reserva su número y su nombre |

La ruptura silenciosa, medida el 2026-11-09. La versión 1 del pedido tenía `int32 discount_percent = 3` (un 10 % de descuento). Alguien lo elimina y, para un campo nuevo de gastos de envío en céntimos, reutiliza el número 3:

```proto
message OrderV1 { int32 id = 1; int32 discount_percent = 3; }
message OrderV2 { int32 id = 1; int32 shipping_cents = 3; }
```

Un servidor ya actualizado envía el pedido con 500 céntimos de envío; un cliente que sigue con la versión 1 lo interpreta con el mismo tipo `int32` y el mismo número:

```text
V1 bytes: 08E724180A  V2 bytes: 08E72418F403
Cliente antiguo lee descuento: 500%
```

Ningún error: el cliente aplica un descuento del 500 %. La forma correcta es dejar el número fuera de uso con `reserved` y asignar uno nuevo:

```proto
message OrderV3 {
  reserved 3;
  reserved "discount_percent";
  int32 id = 1;
  int32 shipping_cents = 4;
}
```

El compilador rechaza ahora cualquier campo que use el número 3 o el nombre `discount_percent`, y el cliente antiguo lee un descuento de `0` (campo ausente) en lugar de un dato corrupto. Para cambios que sí rompen, se publica una versión nueva del paquete (`tienda.orders.v2`) y las dos conviven mientras migran los clientes; la estrategia general está en [Versionado de contratos](../contratos-de-api/Versionado-de-Contratos.md).

## Probar y explorar un servicio

Como el cuerpo es binario, `curl` no sirve para llamar a gRPC. La herramienta equivalente es **grpcurl** (proyecto `fullstorydev/grpcurl`), que existe en winget con el identificador `fullstorydev.grpcurl` (versión 1.9.3 en la consulta del 2026-11-09; no instalado ni ejecutado al preparar el ejemplo, así que no se muestra salida suya).

Para que grpcurl descubra los servicios sin tener el `.proto` a mano, el servidor puede activar la **reflexión** con el paquete `Grpc.AspNetCore.Server.Reflection`:

```csharp
builder.Services.AddGrpcReflection();
// ...
app.MapGrpcReflectionService();
```

Con la reflexión activa, estas son las órdenes habituales (el flag `-plaintext` indica HTTP/2 sin TLS, propio del desarrollo local):

```bash
grpcurl -plaintext localhost:5100 list
grpcurl -plaintext localhost:5100 describe tienda.orders.v1.OrderService
grpcurl -plaintext -d '{"order_id": 4711}' localhost:5100 tienda.orders.v1.OrderService/GetOrder
```

La reflexión expone todo el contrato a quien llegue al puerto: se activa en desarrollo y se desactiva (o se protege) en producción.

## gRPC, REST o GraphQL

| Criterio | gRPC | REST | GraphQL |
| --- | --- | --- | --- |
| Entre servicios internos | Muy buena | Buena | Poco habitual |
| Contrato estricto y código generado | Nativo (`.proto`) | Opcional (OpenAPI) | Nativo (esquema) |
| Streaming | Nativo, en ambos sentidos | No (hace falta SSE o WebSockets) | Suscripciones, con otro canal |
| API pública para terceros | Poco adecuada | La más adecuada | Adecuada |
| Navegador | Solo con gRPC-Web | Directo | Directo |
| Depuración a mano | Difícil (binario; `grpcurl`) | Fácil (`curl`, navegador) | Media |
| Cachés HTTP y CDN | No | Sí | Difícil |
| Tamaño y velocidad del mensaje | Mejor | Mayor | Mayor |

Los estilos se detallan en [REST](REST.md) y [GraphQL](GraphQL.md).

**Cuándo NO usar gRPC:**

- Una API pública o de terceros que deben poder probar con `curl`, el navegador o una herramienta cualquiera.
- Una aplicación web que llama directamente desde el navegador y no puede asumir un proxy o middleware de gRPC-Web.
- Infraestructura (proxys, balanceadores, cortafuegos) que no habla HTTP/2 completo.
- Volumen bajo y equipo pequeño: el ahorro no compensa el coste de herramientas, depuración y aprendizaje.
- Respuestas que se benefician de la caché de HTTP o de una CDN.

## Errores frecuentes

| Síntoma | Causa |
| --- | --- |
| El cliente falla con `Internal` y `HTTP_1_1_REQUIRED` o con un error de protocolo al conectar | El endpoint del servidor solo habla HTTP/1.1; hay que habilitar HTTP/2 en Kestrel (o en el proxy que está delante) |
| En desarrollo, el cliente no conecta a `http://` aunque el servidor funciona | Kestrel sin TLS necesita configurar `Http2` explícitamente en ese endpoint (negociar HTTP/2 por ALPN exige TLS); con `https://` y certificado de desarrollo (`dotnet dev-certs https --trust`) funciona sin ese ajuste |
| `ResourceExhausted`: «Received message exceeds the maximum configured message size» | Se superó el límite de recepción por defecto, 4 MB (en el servidor y en el cliente). Se sube con `MaxReceiveMessageSize` en `AddGrpc` o en las opciones del canal, pero conviene antes partir el mensaje o usar streaming |
| Datos con valores absurdos tras desplegar una versión nueva del contrato | Se reutilizó un número de campo eliminado (véase la ruptura silenciosa) |
| Cada llamada tarda decenas de milisegundos más de lo esperado y se agotan los puertos | Se crea un `GrpcChannel` nuevo por llamada |
| Una instancia del servicio al 100 % y las demás ociosas | Balanceador de capa 4 con conexiones largas de HTTP/2 |
| Llamadas colgadas que nunca terminan | Sin `deadline`: el valor por defecto es sin límite |

**Por qué el `GrpcChannel` se reutiliza.** El canal es la conexión HTTP/2 (con su TCP y, en producción, su TLS) más la gestión de las llamadas. Crearlo cuesta un *handshake* completo, y descartarlo cierra la conexión. Como HTTP/2 multiplexa, un solo canal admite muchas llamadas concurrentes (el cliente generado es ligero y seguro entre hilos). La pauta es un canal por destino, compartido durante toda la vida de la aplicación, normalmente registrado en la inyección de dependencias con `AddGrpcClient<T>()`.

## Buenas prácticas avanzadas

- **Nunca reutilices ni cambies el tipo de un número de campo.** Al eliminar un campo, `reserved` con número y nombre; el compilador impide el accidente.
- **Reutiliza el canal.** Un `GrpcChannel` por servicio destino, durante toda la vida del proceso; con inyección de dependencias, `AddGrpcClient<T>()`.
- **Fija siempre un deadline en el cliente y respeta `context.CancellationToken` en el servidor.** Sin él, una cadena de servicios puede quedar esperándose entre sí; con él, el trabajo inútil se aborta en cadena.
- **Elige el código de estado con precisión.** Los reintentos automáticos y las métricas dependen de él: `Unavailable` se reintenta, `InvalidArgument` no. Devolver `Unknown` para todo, que es lo que pasa con una excepción sin traducir, lo estropea.
- **Reparte la carga por llamada, no por conexión.** Proxy de capa 7 con HTTP/2 o balanceo en el cliente; un balanceador de capa 4 concentra todo en una instancia.
- **Valores de enum con `UNSPECIFIED = 0` y paquete con versión (`v1`).** El cero es lo que ve un cliente cuando el campo falta, y el sufijo de versión deja sitio para una ruptura futura sin tocar a los clientes existentes.

## Documentación oficial

- [grpc.io: conceptos básicos](https://grpc.io/docs/what-is-grpc/core-concepts/) — los cuatro tipos de llamada, deadlines y estados; la referencia neutral al lenguaje.
- [grpc.io: códigos de estado](https://grpc.io/docs/guides/status-codes/) — la tabla completa y cuándo usar cada código; útil al diseñar el manejo de errores.
- [gRPC en ASP.NET Core (Microsoft Learn)](https://learn.microsoft.com/en-us/aspnet/core/grpc/) — creación del servicio y del cliente, configuración, balanceo de carga, gRPC-Web y plazos en .NET.
- [grpcurl](https://github.com/fullstorydev/grpcurl) — instalación y uso de la herramienta de línea de órdenes.

---

*En resumen: gRPC cambia la legibilidad del JSON por un contrato tipado, mensajes compactos y streaming sobre HTTP/2, y es la opción para hablar entre servicios que controlas, no para abrir una API al mundo.*
