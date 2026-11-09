# SOAP

## ¿Qué es?

**SOAP** es un protocolo de mensajería en el que cada petición y cada respuesta es un documento XML con una estructura fija (el *sobre*), y en el que el contrato del servicio se publica en un fichero **WSDL** del que las herramientas generan el cliente. Es el estilo que se encuentra al integrarse con sistemas heredados: banca, seguros, administraciones públicas y software empresarial con décadas de servicio.

## ¿Por qué existe?

SOAP se publicó a finales de los años noventa y se estandarizó en el W3C en los primeros 2000, cuando no existía JSON ni había una convención extendida para hacer APIs sobre HTTP. Había que conectar sistemas escritos en lenguajes y plataformas distintos (Java, COBOL, C++, Visual Basic) y hacía falta un acuerdo que no dependiera de ninguno: un formato de mensaje común (XML), una descripción formal de qué operaciones ofrece cada servicio (WSDL) y herramientas que generaran el código de ambos lados a partir de esa descripción.

> La analogía actual es un esquema OpenAPI más un generador de clientes, pero con el formato de mensaje también fijado por el estándar: no hay decisiones de diseño sobre rutas, verbos o forma del JSON. Solo hay operaciones, mensajes tipados y un sobre que los envuelve.

Dos ideas lo distinguen de REST. SOAP modela **operaciones** (`GetOrder`, `CancelOrder`) en vez de recursos con verbos HTTP; es la rama «acciones» que desarrolla [RPC](RPC.md). Y define la mensajería en sí (cabeceras de mensaje, errores, extensiones de seguridad), de modo que no depende de HTTP: HTTP es el transporte habitual, no el protocolo.

## ¿Cuándo y para qué se usa?

Casi nunca se elige para un proyecto nuevo; se consume porque el otro sistema ya lo expone. Los casos reales son pasarelas de pago y bancos, servicios de aseguradoras, facturación electrónica y trámites con organismos públicos, ERP y software empresarial anterior a REST. El trabajo habitual es **saber leerlo** (un sobre y un WSDL), **consumirlo** (generar un cliente) y, a veces, **exponerlo** porque un socio lo exige.

## El sobre: Envelope, Header, Body y Fault

Todo mensaje SOAP, de ida o de vuelta, tiene la misma estructura:

| Elemento | Obligatorio | Contiene |
|---|---|---|
| `Envelope` | Sí | El documento entero. Su espacio de nombres identifica la versión de SOAP (1.1 o 1.2). |
| `Header` | No | Metadatos del mensaje que no son datos de negocio: credenciales, identificador de transacción, firma. |
| `Body` | Sí | La carga: la operación pedida y sus parámetros, la respuesta, o un `Fault`. |
| `Fault` | Solo en errores | Dentro del `Body` de la respuesta: código, motivo legible y detalle estructurado opcional. |

El sobre separa «de qué trata el mensaje» (`Body`) de «cómo hay que tratarlo» (`Header`). Los nodos intermedios (un gateway, un servicio de auditoría) pueden leer y modificar la cabecera sin entender el cuerpo. Una cabecera puede marcarse como obligatoria de entender (`mustUnderstand`): quien no la reconozca debe rechazar el mensaje en vez de ignorarla.

Como el protocolo define sus propios errores, un fallo de negocio no se comunica con un código HTTP, sino con un `Fault` en el `Body`. HTTP solo transporta: la especificación de SOAP 1.1 pide que el servidor responda con `500` cuando hay un `Fault`.

## Un mensaje real: `GetOrder(4711)` frente a `GET /orders/4711`

La misma consulta («dame el pedido 4711») en SOAP 1.1. Petición:

```http
POST /soap11 HTTP/1.1
Host: localhost:5080
Content-Type: text/xml; charset=utf-8
SOAPAction: "http://tienda.ejemplo.com/orders/IOrderService/GetOrder"
Content-Length: 258

<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <GetOrder xmlns="http://tienda.ejemplo.com/orders">
      <orderId>4711</orderId>
    </GetOrder>
  </soap:Body>
</soap:Envelope>
```

Respuesta (salida real del servicio de la sección siguiente, con el XML tal como sale, en una línea):

```http
HTTP/1.1 200 OK
Content-Length: 423
Content-Type: text/xml; charset=utf-8

<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><GetOrderResponse xmlns="http://tienda.ejemplo.com/orders"><GetOrderResult xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><Id>4711</Id><CustomerId>17</CustomerId><Status>paid</Status><Lines><OrderLine><ProductId>42</ProductId><Quantity>2</Quantity><Price>19.90</Price></OrderLine></Lines></GetOrderResult></GetOrderResponse></s:Body></s:Envelope>
```

El equivalente REST:

```http
GET /orders/4711 HTTP/1.1
Host: api.tienda.ejemplo.com
Accept: application/json
```

```json
{"id":4711,"customerId":17,"status":"paid","lines":[{"productId":42,"quantity":2,"price":19.90}]}
```

| | SOAP 1.1 | REST |
|---|---|---|
| Método HTTP | `POST` siempre | `GET`: la operación está en el verbo |
| Qué dice cuál es la operación | El elemento `GetOrder` del cuerpo y la cabecera `SOAPAction` | La ruta `/orders/4711` y el verbo |
| Cuerpo de la petición | 258 bytes de XML | Ninguno |
| Cuerpo de la respuesta | 423 bytes | 97 bytes (JSON escrito a mano con los mismos datos, no servido) |
| Qué aporta el sobre | `Envelope` y `Body` con su espacio de nombres, el nombre de la operación y su espacio de nombres, y la marca `xmlns:i` de tipos | Nada: el JSON es solo el dato |
| Error | `500` y un `Fault` en el cuerpo | `404` y un cuerpo de error propio (p. ej. [Modelado de errores](../contratos-de-api/Modelado-de-Errores.md)) |
| ¿Cacheable? | No: es `POST` | Sí: `GET` con `ETag` o `Cache-Control` |

La respuesta SOAP pesa unas cuatro veces la REST con los mismos datos, y la diferencia crece con los nombres de espacio largos. A cambio, cada elemento pertenece a un espacio de nombres y a un tipo declarado en el WSDL: el cliente no tiene que adivinar nada.

Los espacios de nombres (`xmlns`) son la parte que más cuesta. `http://tienda.ejemplo.com/orders` no es una URL que se visite: es un identificador único que evita colisiones entre vocabularios. El elemento `<GetOrder>` solo es la operación correcta si está en ese espacio de nombres; el mismo texto en otro espacio es otra cosa para el servidor.

## Un servicio SOAP real en .NET con CoreWCF

Para ver todo esto sin depender de un servicio ajeno, el servidor de la tienda en .NET 10 con CoreWCF, la reimplementación de WCF (*Windows Communication Foundation*) para .NET moderno. Paquetes consultados en NuGet el 2026-11-09: `CoreWCF.Primitives`, `CoreWCF.Http` y `CoreWCF.ConfigurationManager`, versión `1.9.1` los tres.

```xml
<ItemGroup>
  <PackageReference Include="CoreWCF.Primitives" Version="1.9.1" />
  <PackageReference Include="CoreWCF.Http" Version="1.9.1" />
  <PackageReference Include="CoreWCF.ConfigurationManager" Version="1.9.1" />
</ItemGroup>
```

El contrato es una interfaz con atributos. `ServiceContract` define el espacio de nombres del servicio, `OperationContract` marca la operación y `FaultContract` declara qué error tipado puede devolver:

```csharp
using CoreWCF;
using CoreWCF.Channels;
using CoreWCF.Configuration;
using CoreWCF.Description;
using System.Runtime.Serialization;

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls("http://localhost:5080");
builder.Services.AddServiceModelServices().AddServiceModelMetadata();
builder.Services.AddSingleton<IServiceBehavior, UseRequestHeadersForMetadataAddressBehavior>();

var app = builder.Build();

// SOAP 1.2: codificador de texto con MessageVersion.Soap12 sobre transporte HTTP
var soap12 = new CustomBinding(
    new TextMessageEncodingBindingElement(MessageVersion.Soap12, System.Text.Encoding.UTF8),
    new HttpTransportBindingElement());

app.UseServiceModel(sm =>
{
    sm.AddService<OrderService>();
    sm.AddServiceEndpoint<OrderService, IOrderService>(new BasicHttpBinding(), "/soap11"); // SOAP 1.1
    sm.AddServiceEndpoint<OrderService, IOrderService>(soap12, "/soap12");                 // SOAP 1.2
    app.Services.GetRequiredService<ServiceMetadataBehavior>().HttpGetEnabled = true;      // publica ?wsdl
});
app.Run();

[ServiceContract(Namespace = "http://tienda.ejemplo.com/orders")]
public interface IOrderService
{
    [OperationContract]
    [FaultContract(typeof(OrderNotFound))]
    Order GetOrder(int orderId);
}

[ServiceBehavior(Namespace = "http://tienda.ejemplo.com/orders")]
public class OrderService : IOrderService
{
    public Order GetOrder(int orderId)
    {
        if (orderId != 4711)
            throw new FaultException<OrderNotFound>(
                new OrderNotFound { OrderId = orderId, Message = "El pedido no existe" },
                new FaultReason($"El pedido {orderId} no existe"));
        return new Order { Id = 4711, CustomerId = 17, Status = "paid",
            Lines = { new OrderLine { ProductId = 42, Quantity = 2, Price = 19.90m } } };
    }
}
```

Los tipos `Order`, `OrderLine` y `OrderNotFound` son clases con `[DataContract(Namespace = "http://tienda.ejemplo.com/orders")]` y `[DataMember(Order = n)]` en cada propiedad (el `Order` fija el orden de los elementos en el XML; sin él salen por orden alfabético). El código compila y se ejecuta con `dotnet run` en .NET SDK 10.0.401; las salidas citadas se obtuvieron contra él. Un mismo servicio publica dos puntos de acceso (*endpoints*), uno por versión de SOAP.

## El WSDL: el contrato del servicio

El WSDL (*Web Services Description Language*) es un XML que describe, en capas, todo lo que el cliente necesita para llamar al servicio:

| Parte del WSDL | Qué describe |
|---|---|
| `types` | Los tipos de datos, en XML Schema (XSD): qué campos tiene un `Order`, de qué tipo es cada uno. |
| `message` | Los mensajes que viajan: el de entrada de `GetOrder`, el de salida y el de error. Cada uno apunta a un elemento de `types`. |
| `portType` | Las operaciones abstractas: `GetOrder` recibe tal mensaje, devuelve tal otro y puede fallar con tal error. |
| `binding` | Cómo se concreta cada operación en un protocolo: SOAP 1.1 o 1.2, estilo `document`, el valor de `soapAction`. |
| `service` / `port` | La dirección donde vive cada binding: la URL del endpoint. |

Se obtiene añadiendo `?wsdl` a la URL del servicio. Con el servidor anterior:

```bash
curl "http://localhost:5080/soap11?wsdl"
```

CoreWCF reparte el documento entre varios ficheros enlazados por `import` (`?wsdl=wsdl0`, `?xsd=xsd0`). Fragmento del `binding` y del `service`:

```xml
<wsdl:binding name="BasicHttpBinding_IOrderService" type="i0:IOrderService">
  <soap:binding transport="http://schemas.xmlsoap.org/soap/http"/>
  <wsdl:operation name="GetOrder">
    <soap:operation soapAction="http://tienda.ejemplo.com/orders/IOrderService/GetOrder" style="document"/>
    <wsdl:input><soap:body use="literal"/></wsdl:input>
    <wsdl:output><soap:body use="literal"/></wsdl:output>
    <wsdl:fault name="OrderNotFoundFault"><soap:fault name="OrderNotFoundFault" use="literal"/></wsdl:fault>
  </wsdl:operation>
</wsdl:binding>
<wsdl:service name="OrderService">
  <wsdl:port name="BasicHttpBinding_IOrderService" binding="tns:BasicHttpBinding_IOrderService">
    <soap:address location="http://localhost:5080/soap11"/>
  </wsdl:port>
</wsdl:service>
```

Y del esquema de tipos (`?xsd=xsd0`):

```xml
<xs:complexType name="OrderLine">
  <xs:sequence>
    <xs:element minOccurs="0" name="ProductId" type="xs:int"/>
    <xs:element minOccurs="0" name="Quantity" type="xs:int"/>
    <xs:element minOccurs="0" name="Price" type="xs:decimal"/>
  </xs:sequence>
</xs:complexType>
```

El WSDL generado es WSDL 1.1, la versión que usa prácticamente todo el ecosistema SOAP (la 2.0 existe como recomendación del W3C, con poca adopción en la práctica). Es el equivalente del contrato OpenAPI de REST: de él se genera el cliente, y quien lo publica se compromete a no romperlo (más sobre el mantenimiento de contratos en [Versionado de contratos](../contratos-de-api/Versionado-de-Contratos.md)).

## Consumirlo desde C#

La vía habitual es generar el cliente tipado desde el WSDL con `dotnet-svcutil`, la herramienta de Microsoft para .NET. La versión `8.0.0` es la última estable en NuGet (consulta del 2026-11-09). Se instala como herramienta local del proyecto y se apunta al WSDL:

```bash
dotnet new tool-manifest
dotnet tool install dotnet-svcutil
dotnet dotnet-svcutil "http://localhost:5080/soap11?wsdl" -n "*,Tienda.Soap" -d Generated -o OrderServiceClient.cs
```

En la máquina de la prueba, con el SDK 10 instalado, la herramienta no arrancó hasta definir `DOTNET_ROLL_FORWARD=Major` (pide un runtime que no encuentra). Con eso respondió `Generando archivos...` y produjo `Generated/OrderServiceClient.cs`, con las clases `Order`, `OrderLine` y `OrderNotFound`, la interfaz `IOrderService` y un `OrderServiceClient` con un constructor por cada endpoint del WSDL. Añade también al `.csproj` los paquetes `System.ServiceModel.*` `4.10.*` (uno de sus transitivos, `System.Security.Cryptography.Pkcs` 6.0.1, dispara un aviso `NU1903` de vulnerabilidad conocida al restaurar).

```csharp
using System.ServiceModel;
using Tienda.Soap;

var client = new OrderServiceClient(OrderServiceClient.EndpointConfiguration.BasicHttpBinding_IOrderService);

var order = await client.GetOrderAsync(4711);
Console.WriteLine($"Pedido {order.Id}: cliente {order.CustomerId}, estado {order.Status}");
foreach (var line in order.Lines)
    Console.WriteLine($"  producto {line.ProductId} x{line.Quantity} a {line.Price}");

try
{
    await client.GetOrderAsync(9999);
}
catch (FaultException<OrderNotFound> ex)
{
    Console.WriteLine($"Fault tipado: {ex.Reason} (OrderId={ex.Detail.OrderId}, Code={ex.Code.Name})");
}
```

Salida real:

```text
Pedido 4711: cliente 17, estado paid
  producto 42 x2 a 19,90
Fault tipado: El pedido 9999 no existe (OrderId=9999, Code=Client)
```

El `Fault` declarado en el contrato llega como excepción `FaultException<OrderNotFound>` con el detalle ya deserializado: se captura por tipo, sin leer texto. (El `19,90` lo escribe `Console.WriteLine` con la cultura de la máquina; por el cable viaja `19.90`.)

## Probarlo a mano con curl

Para depurar o para integrarse sin cliente generado basta un fichero con el sobre y `curl`. Con el sobre guardado como `req11.xml`:

```bash
curl -si -X POST http://localhost:5080/soap11 \
  -H 'Content-Type: text/xml; charset=utf-8' \
  -H 'SOAPAction: "http://tienda.ejemplo.com/orders/IOrderService/GetOrder"' \
  --data-binary @req11.xml
```

Con un pedido que no existe (`<orderId>9999</orderId>`) el servidor responde con un `Fault`:

```http
HTTP/1.1 500 Internal Server Error
Content-Type: text/xml; charset=utf-8

<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring xml:lang="es-ES">El pedido 9999 no existe</faultstring><detail><OrderNotFound xmlns="http://tienda.ejemplo.com/orders" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><Message>El pedido no existe</Message><OrderId>9999</OrderId></OrderNotFound></detail></s:Fault></s:Body></s:Envelope>
```

El `Fault` de SOAP 1.1 tiene tres partes: `faultcode` (quién tiene la culpa: `Client` o `Server`), `faultstring` (texto para personas) y `detail` (datos estructurados definidos en el WSDL). El cuerpo se lee con las dos primeras; el programa debe reaccionar al `detail`. Una gestión correcta mira el código HTTP solo como señal de que hay un `Fault`, no como diagnóstico.

## SOAP 1.1 y SOAP 1.2

SOAP 1.1 es una nota del W3C de 2000 y SOAP 1.2 una recomendación posterior que cerró ambigüedades. Los servicios heredados hablan sobre todo 1.1; los dos coexisten. Las diferencias, comprobadas con los dos endpoints del servicio:

| | SOAP 1.1 | SOAP 1.2 |
|---|---|---|
| Espacio de nombres del `Envelope` | `http://schemas.xmlsoap.org/soap/envelope/` | `http://www.w3.org/2003/05/soap-envelope` |
| `Content-Type` | `text/xml; charset=utf-8` | `application/soap+xml; charset=utf-8` |
| Acción de la operación | Cabecera HTTP `SOAPAction: "…"` | Parámetro `action="…"` dentro de `Content-Type`; la cabecera `SOAPAction` desaparece |
| Estructura del `Fault` | `faultcode`, `faultstring`, `detail` | `Code/Value`, `Reason/Text`, `Detail` |
| Códigos de fallo | `Client`, `Server` (y otros) | `Sender`, `Receiver` (y otros) |
| Enviar `text/xml` al endpoint 1.2 | — | `415` sin cuerpo |
| Respuesta con `Fault` en HTTP | `500` | `500` en este servidor |

Petición y `Fault` equivalentes en SOAP 1.2:

```bash
curl -si -X POST http://localhost:5080/soap12 \
  -H 'Content-Type: application/soap+xml; charset=utf-8; action="http://tienda.ejemplo.com/orders/IOrderService/GetOrder"' \
  --data-binary @req12-404.xml
```

```http
HTTP/1.1 500 Internal Server Error
Content-Type: application/soap+xml; charset=utf-8

<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><s:Fault><s:Code><s:Value>s:Sender</s:Value></s:Code><s:Reason><s:Text xml:lang="es-ES">El pedido 9999 no existe</s:Text></s:Reason><s:Detail><OrderNotFound xmlns="http://tienda.ejemplo.com/orders" xmlns:i="http://www.w3.org/2001/XMLSchema-instance"><OrderId>9999</OrderId><Message>El pedido no existe</Message></OrderNotFound></s:Detail></s:Fault></s:Body></s:Envelope>
```

El endpoint de cada versión solo entiende su versión: enviar el sobre 1.1 al endpoint 1.2 devolvió `400` sin cuerpo. El cliente debe elegir la versión que el WSDL anuncia en su `binding`.

## WS-*: lo que SOAP añade y REST no trae de serie

Al ser un protocolo de mensajería con cabeceras extensibles, SOAP admite una familia de especificaciones (conocidas como **WS-\***) que se apoyan en el `Header`. Conviene saber qué problema resuelve cada una; en REST se cubren con otras piezas.

| Especificación | Qué aporta | Equivalente en REST |
|---|---|---|
| WS-Security | Firma y cifrado del mensaje y credenciales en la cabecera: la protección viaja con el mensaje, sobreviva o no el canal. | TLS protege el canal (punto a punto); tokens como [JWT](../../seguridad/autenticacion-y-autorizacion/JWT.md) autentican; no hay firma de mensaje estándar. |
| WS-ReliableMessaging | Entrega garantizada, sin duplicados y en orden, entre dos extremos, con acuses de recibo. | Reintentos con claves de idempotencia, o una cola de mensajes ([Mensajería asíncrona](../../devops/mensajeria-asincrona/Mensajeria-Asincrona.md)). |
| WS-AtomicTransaction | Una transacción distribuida que abarca varios servicios con confirmación en dos fases. | Nada estándar; se evita con sagas y consistencia eventual. |

Especificaciones, en OASIS: [WS-Security (SOAP Message Security 1.1.1)](https://docs.oasis-open.org/wss-m/wss/v1.1.1/os/wss-SOAPMessageSecurity-v1.1.1-os.html), [WS-ReliableMessaging 1.2](https://docs.oasis-open.org/ws-rx/wsrm/v1.2/wsrm.html) y [WS-AtomicTransaction](https://docs.oasis-open.org/ws-tx/wsat/2006/06). La que más aparece en la práctica es WS-Security, sobre todo en entornos financieros y gubernamentales; las otras dos se ven poco. Su coste es alto: aumentan el tamaño del mensaje, la complejidad de configuración y los problemas de interoperabilidad entre pilas.

## SOAP o REST

| Situación | Elección |
|---|---|
| El sistema con el que hay que hablar ya expone SOAP | SOAP: se consume tal cual; no se pide una API REST «por gusto». |
| Un socio, un banco o un organismo impone un contrato formal en WSDL | SOAP. |
| Se exige seguridad a nivel de mensaje (firma o cifrado que sobreviva a intermediarios) | SOAP con WS-Security. |
| Entorno regulado donde el contrato y la trazabilidad del mensaje son requisito de auditoría | SOAP es defendible; confirmar qué exige realmente la norma. |
| API nueva para equipos propios, web o móvil | REST (o [GraphQL](GraphQL.md) o [gRPC](gRPC.md) según el caso). |
| Los clientes son navegadores o terceros que quieren probar con `curl` o con el navegador | REST: SOAP no se puede llamar con un enlace ni cachear. |
| Se necesita caché HTTP o recursos con identidad estable | REST: SOAP usa `POST` para todo. |
| Ancho de banda o latencia ajustados | REST con JSON, o gRPC. |

La regla práctica: SOAP se elige cuando lo impone el otro lado, no por sus virtudes.

## Convivir con un SOAP heredado en un sistema nuevo

Cuando un sistema nuevo debe usar un servicio SOAP antiguo, la tentación es dejar que las clases generadas (`Order` del WSDL, con sus nombres, sus tipos y sus `Fault`) se extiendan por todo el código. Así el modelo del proveedor dicta el del sistema, y cualquier cambio del WSDL se propaga a todas partes.

Una **capa anticorrupción** lo evita: un adaptador que es el único que conoce el cliente generado y traduce entre el SOAP y un modelo propio. El resto del código depende de una interfaz suya (`IOrderGateway`) y de sus tipos de dominio.

```csharp
// El dominio habla en su idioma; no sabe que detrás hay SOAP.
public interface IOrderGateway
{
    Task<Result<Order>> GetAsync(int orderId, CancellationToken ct);
}

public class SoapOrderGateway(OrderServiceClient client) : IOrderGateway
{
    public async Task<Result<Order>> GetAsync(int orderId, CancellationToken ct)
    {
        try
        {
            var dto = await client.GetOrderAsync(orderId);
            return Result.Ok(new Order(dto.Id, dto.CustomerId, ParseStatus(dto.Status),
                dto.Lines.Select(l => new Line(l.ProductId, l.Quantity, l.Price)).ToList()));
        }
        catch (FaultException<OrderNotFound>)
        {
            return Result.NotFound();
        }
    }
}
```

El adaptador traduce los tipos generados al modelo propio, convierte el `Fault` tipado en un resultado del dominio y es el único sitio donde cambiar cuando el WSDL cambie. La estructura de interfaz propia más adaptador es la de [Puertos y adaptadores](../clean-architecture/Puertos-y-Adaptadores.md).

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `Fault` `ActionNotSupported` con `Action ''` (observado en CoreWCF) | Falta la cabecera `SOAPAction` en SOAP 1.1: este servidor decide la operación por ella. Algunos servicios despachan por el elemento del cuerpo y no la exigen; el WSDL dice cuál es el valor correcto. |
| `Fault` `ActionNotSupported` con `Action 'urn:otra'` | `SOAPAction` con un valor que no corresponde a ninguna operación. Debe ser exactamente el de `soap:operation soapAction` del WSDL, comillas incluidas. |
| El elemento «está ahí» pero el servidor no lo encuentra, o responde con un fallo interno genérico | Espacio de nombres mal declarado: `http://tienda.ejemplo.com/order` en vez de `…/orders` hizo que el servidor de la prueba devolviera `InternalServiceFault` (HTTP 500). Un elemento sin `xmlns` o con otro prefijo pertenece a otro espacio y no coincide. |
| `DeserializationFailed` con `The value 'abc' cannot be parsed as the type 'Int32'` | Un valor que no cumple el tipo del XSD (`orderId` es `xs:int`). El `Fault` es del cliente. |
| El cliente deja de compilar o falla en producción tras una actualización del proveedor | El WSDL cambió (campo nuevo obligatorio, tipo distinto, operación renombrada) y el cliente generado ya no coincide. |
| Una excepción genérica que se trata como un fallo de red | Se ha capturado el `500` HTTP en vez de leer el `Fault`: el código de negocio está dentro del cuerpo. |
| Importes o fechas distintos a los esperados | Las fechas viajan en `xs:dateTime` (ISO 8601, con o sin zona horaria) y los decimales con punto (`19.90`). Un sistema heredado puede enviar fechas sin zona o decimales con coma, y el cliente los interpreta con la cultura de la máquina si no se fija. |

## Buenas prácticas avanzadas

- **Congela el WSDL en tu repositorio, no lo consumas en remoto.** Generar el cliente apuntando a la URL viva significa que tu compilación depende de un servidor ajeno y que un cambio silencioso del proveedor te rompe el build (o peor: te cambia el contrato sin enterarte). Descarga el WSDL y sus XSD importados, versiónalos junto a tu código y regenera el cliente solo de forma deliberada, comparando diferencias.
- **Los bugs más desquiciantes son de espacios de nombres.** Dos sobres idénticos a ojo pueden ser distintos para el servidor si un elemento está en el espacio de nombres equivocado, o sin él. Al depurar, compara siempre los prefijos y los `xmlns` contra un ejemplo que funcione, no solo los nombres de las etiquetas.
- **Captura el XML crudo que viaja, no solo los objetos.** Cuando una integración falla, el proveedor pide «el sobre exacto que enviaste», y los objetos tipados no lo dan. Activa la traza del mensaje en bruto (petición y respuesta) desde el primer día, con los datos sensibles enmascarados.
- **Trata los `Fault` como errores tipados.** El `detail` declarado en el WSDL llega como excepción tipada (`FaultException<T>`): captúrala por tipo en vez de buscar palabras en el `faultstring`, que cambia de redacción e idioma entre versiones del servicio.
- **Pon un tiempo máximo y un reintento acotado.** Los servicios heredados tienen latencias altas e irregulares; sin tiempo máximo, una llamada colgada acaba con los hilos del sistema nuevo. Reintenta solo operaciones que sean idempotentes: una consulta como `GetOrder` sí, una creación de pedido no sin una clave que evite duplicados.
- **Si tienes que exponer SOAP, genera el WSDL desde el contrato y fija los espacios de nombres.** Dejar los valores por defecto (en WCF, `tempuri.org`) publica un contrato con un identificador que nadie eligió y que luego no se puede cambiar sin romper a los clientes.

## Documentación oficial

- [SOAP Version 1.2 Part 1: Messaging Framework](https://www.w3.org/TR/soap12-part1/): la recomendación del W3C. Merece la pena para el modelo de procesamiento del `Envelope`, el `Header` con `mustUnderstand` y la estructura del `Fault`.
- [SOAP 1.1 (nota del W3C)](https://www.w3.org/TR/soap11/): la versión que usan casi todos los servicios heredados. Ir aquí cuando el servicio responda con `faultcode`/`faultstring` y `SOAPAction`.
- [WSDL 1.1 (nota del W3C)](https://www.w3.org/TR/2001/NOTE-wsdl-20010315) y [WSDL 2.0 Parte 1](https://www.w3.org/TR/wsdl20/): descripción formal de `types`, `message`, `portType`, `binding` y `service`. La 1.1 es la que genera CoreWCF y la que encontrarás en la mayoría de servicios.
- [CoreWCF](https://corewcf.github.io/): documentación y ejemplos del servidor SOAP para .NET moderno; ir cuando haya que exponer un servicio o configurar bindings.

---

*En resumen: SOAP es un contrato formal en XML que se elige casi siempre porque lo impone el otro lado; aprende a leer su sobre, su WSDL y su `Fault`, y aíslalo detrás de un adaptador para que no contamine el resto del sistema.*
