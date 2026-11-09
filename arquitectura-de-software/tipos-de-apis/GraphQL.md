# GraphQL

## ¿Qué es?

**GraphQL** es un lenguaje de consulta para APIs, junto con un entorno de ejecución en el servidor, en el que el **cliente** describe la forma exacta de los datos que quiere y el servidor devuelve esa forma, en una sola petición. Lo que se puede pedir lo define un **esquema** con tipos, y normalmente todo entra por un único endpoint (`POST /graphql`).

## ¿Por qué existe?

En una API REST cada endpoint devuelve una forma fija. Eso produce dos molestias:

- **Over-fetching**: se recibe el recurso entero cuando solo hacen falta dos campos.
- **Under-fetching**: una pantalla necesita datos de varios recursos y hay que encadenar llamadas, porque la respuesta de una trae el identificador que necesita la siguiente.

Caso real en la tienda online (`https://api.tienda.ejemplo.com`): pintar «el pedido 4711 con su cliente y los nombres de sus productos». El pedido solo trae el `customerId` y los `productId` de sus líneas, así que en REST hacen falta cuatro llamadas, tres de ellas dependientes de la primera:

```text
❌ REST
GET /orders/4711      → 512 bytes   (direcciones, importes, fechas, notas... y customerId: 2, productId: 2 y 3)
GET /customers/2      → 298 bytes   (teléfono, fecha de nacimiento, puntos de fidelidad...)
GET /products/2       → 337 bytes   (descripción larga, stock, peso, imágenes...)
GET /products/3       → 337 bytes
                        ─────────
                        1.484 bytes en 4 viajes, de los que la pantalla usa 5 datos
```

Las respuestas anteriores se midieron con un servidor de prueba que devuelve esos recursos con los campos habituales de una tienda. Con GraphQL, la pantalla pide justo lo que pinta:

```graphql
# ✅ GraphQL: una petición
{
  order(id: 4711) {
    id
    status
    customer { name }
    lines { quantity product { name } }
  }
}
```

```json
{"data":{"order":{"id":4711,"status":"PAID","customer":{"name":"Cliente 2"},"lines":[{"quantity":2,"product":{"name":"Producto 2"}},{"quantity":1,"product":{"name":"Producto 3"}}]}}}
```

Son 185 bytes de respuesta en un solo viaje. El navegador de móvil puede pedir menos campos y el de escritorio más, contra la misma API.

> Es la diferencia entre un menú cerrado y un bufé. En REST sirven el plato del día completo, te sobre o te falte algo; en GraphQL te sirves exactamente lo que vas a comer. A cambio, el bufé necesita a alguien vigilando que nadie se lleve la cocina entera (ver «Coste y seguridad»).

## ¿Cuándo y para qué se usa?

Encaja cuando una pantalla agrega datos de muchos recursos relacionados, cuando varios clientes (web, móvil, terceros) necesitan piezas distintas de lo mismo y cuando el equipo de frontend quiere evolucionar sus pantallas sin esperar a que backend cree un endpoint nuevo por cada variante. Es habitual en paneles de control, catálogos ricos y productos con datos muy interconectados. Para una API CRUD pequeña con un único cliente, REST suele ser más simple (ver «¿GraphQL o REST?»).

## El esquema

El esquema se escribe en **SDL** (*Schema Definition Language*) y es a la vez contrato y documentación. Este es el esquema de la tienda, tal como lo publica el servidor de prueba (recortado a lo esencial):

```graphql
type Query {
  order(id: Int!): Order
  orders: [Order!]!
  products: [Product!]!
}

type Mutation {
  shipOrder(orderId: Int!): ShipOrderPayload!
}

type Order {
  id: Int!
  status: OrderStatus!
  customer: Customer
  lines: [Line!]!
  trackingCode: String
}

type Customer {
  id: Int!
  name: String!
  email: String!
}

type Line {
  quantity: Int!
  unitPrice: Decimal!
  product: Product
}

type Product {
  id: Int!
  name: String!
  price: Decimal!
}

enum OrderStatus {
  PENDING
  PAID
  SHIPPED
}
```

Piezas:

- **Tipos de objeto** (`Order`, `Customer`, `Product`): conjuntos de campos; cada campo tiene un tipo y puede devolver otro objeto, lo que forma el grafo.
- **Escalares**: `Int`, `Float`, `String`, `Boolean` e `ID` vienen de serie; hay escalares propios como `Decimal` o `DateTime`.
- **`!` (no nulo)**: `id: Int!` promete que nunca será `null`; sin `!`, el campo puede serlo.
- **Listas**: `[Line!]!` es una lista no nula cuyos elementos tampoco son nulos; `[Line]` permitiría `null` en la lista y en cada elemento.
- **`enum`**: conjunto cerrado de valores; el cliente no puede enviar `"ENVIADO"` si el esquema solo admite `SHIPPED`.
- **Argumentos**: `order(id: Int!)` recibe parámetros tipados; el servidor rechaza una petición con el tipo equivocado antes de ejecutar nada.

### Los tres tipos de operación

- **`query`**: lee datos; no debe tener efectos secundarios y sus campos pueden ejecutarse en paralelo.
- **`mutation`**: cambia datos; los campos de primer nivel se ejecutan en orden, uno detrás de otro.
- **`subscription`**: el servidor empuja eventos al cliente cuando ocurre algo; suele montarse sobre [WebSockets](WebSockets.md) y no se desarrolla aquí.

## Hacer consultas

### Alias, variables y fragmentos

Para comparar dos pedidos con la misma forma, la consulta usa los tres mecanismos del lenguaje:

```graphql
query Comparar($a: Int!, $b: Int!) {
  primero: order(id: $a) { ...Resumen }
  segundo: order(id: $b) { ...Resumen }
}

fragment Resumen on Order {
  id
  status
  customer { name }
}
```

- **Alias** (`primero:`, `segundo:`): sin ellos los dos campos se llamarían `order` y chocarían en la respuesta.
- **Variables** (`$a`, `$b`): los valores viajan aparte del texto de la consulta, tipados. Así el texto es constante (cacheable, registrable) y no hay que construir cadenas con datos del usuario.
- **Fragmentos** (`fragment Resumen on Order`): un trozo de selección con nombre que se reutiliza.

### El intercambio HTTP

Una operación es un `POST` al endpoint único con un cuerpo JSON de tres claves: `query`, `variables` y, si el documento tiene varias operaciones, `operationName`:

```bash
curl -si -X POST http://localhost:5055/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query":"query Comparar($a: Int!, $b: Int!) { primero: order(id: $a) { ...Resumen } segundo: order(id: $b) { ...Resumen } } fragment Resumen on Order { id status customer { name } }","variables":{"a":4711,"b":4712},"operationName":"Comparar"}'
```

```http
HTTP/1.1 200 OK
Content-Type: application/graphql-response+json; charset=utf-8

{"data":{"primero":{"id":4711,"status":"PAID","customer":{"name":"Cliente 2"}},"segundo":{"id":4712,"status":"SHIPPED","customer":{"name":"Cliente 3"}}}}
```

La respuesta siempre es un objeto JSON con `data` (el resultado, con la misma forma que la consulta) y, si algo falló, `errors`.

## Un servidor de verdad con HotChocolate

Las salidas provienen de un servidor mínimo con **HotChocolate** (paquete `HotChocolate.AspNetCore`), un servidor GraphQL para .NET. Se probó el 2026-11-09 con la versión 16.7.3 sobre .NET SDK 10.0.401 (`net10.0`).

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup>
  <ItemGroup><PackageReference Include="HotChocolate.AspNetCore" Version="16.7.3" /></ItemGroup>
</Project>
```

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSingleton<Repositorio>();   // datos en memoria, con contadores de llamadas

builder.Services.AddGraphQLServer()
    .AddQueryType<Query>()
    .AddMutationType<Mutation>()
    .AddTypeExtension<OrderResolvers>();         // resolvers de Order.customer, etc.

var app = builder.Build();
app.MapGraphQL();                                // POST /graphql
app.Run("http://localhost:5055");

public enum OrderStatus { PENDING, PAID, SHIPPED }
public record Customer(int Id, string Name, string Email);
public record Order(int Id, int CustomerId, OrderStatus Status, List<Line> Lines);

public class Query
{
    public Order? GetOrder(int id, Repositorio repo) => repo.ObtenerPedido(id);
    public List<Order> GetOrders(Repositorio repo) => repo.ObtenerPedidos();
}
```

HotChocolate deduce el esquema de las clases C#: `GetOrder` se convierte en el campo `order`, y los tipos no anulables (`int`, `string`) en `Int!`, `String!`. Un **resolver** es la función que produce el valor de un campo; por defecto lee la propiedad con el mismo nombre, y cuando el dato no está en el objeto (el cliente del pedido solo está como `CustomerId`) se escribe uno a mano:

```csharp
[ExtendObjectType<Order>]
public class OrderResolvers
{
    public Customer? GetCustomer([Parent] Order pedido, Repositorio repo)
        => repo.ObtenerCliente(pedido.CustomerId);
}
```

### Errores

GraphQL distingue dos situaciones. Pedir un campo que no existe es un fallo de **validación** contra el esquema, y no se ejecuta nada:

```bash
curl -si -X POST http://localhost:5055/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ order(id: 4711) { id total } }"}'
```

```http
HTTP/1.1 400 Bad Request
Content-Type: application/graphql-response+json; charset=utf-8

{"errors":[{"message":"The field `total` does not exist on the type `Order`.","locations":[{"line":1,"column":24}],"extensions":{"type":"Order","field":"total","responseName":"total","specifiedBy":"https://spec.graphql.org/September2025/#sec-Field-Selections"}}]}
```

No hay clave `data`, y este servidor responde `400`: con el tipo de contenido `application/graphql-response+json` (el de la [especificación GraphQL sobre HTTP](https://graphql.github.io/graphql-over-http/)) un documento inválido es un error de cliente. Con `application/json` algunos servidores devuelven `200` también aquí, de modo que el código de estado no basta para saber si hubo errores.

En cambio, un fallo al **ejecutar** un campo es parcial. Si el resolver de `trackingCode` lanza una excepción para el pedido 4712 (el servicio de transporte no responde), el resto de la consulta se resuelve:

```bash
curl -si -X POST http://localhost:5055/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ orders { id trackingCode } }"}'
```

```http
HTTP/1.1 200 OK

{"errors":[{"message":"Unexpected Execution Error","path":["orders",1,"trackingCode"]}],"data":{"orders":[{"id":4711,"trackingCode":null},{"id":4712,"trackingCode":null},{"id":4713,"trackingCode":null}, ...
```

HTTP `200`, con `data` **y** `errors` a la vez: `path` indica qué campo falló (`orders`, posición 1, `trackingCode`) y ese campo vale `null`; los otros 19 pedidos llegan completos. Por eso el cliente debe mirar siempre `errors`, no solo el código HTTP. Esto funciona porque `trackingCode` es **nullable** en el esquema (`String`, sin `!`). Si fuera `String!`, el `null` no cabría en el campo y GraphQL lo propagaría al objeto padre: `orders[1]` pasaría a `null` y, si la lista no admite elementos nulos, subiría hasta el `data` entero.

Los mensajes de excepciones internas se enmascaran a propósito (`Unexpected Execution Error`) para no filtrar detalles al cliente.

### Mutaciones y errores de negocio

Una mutación se escribe como una consulta con la palabra `mutation`. Marcar un pedido como enviado solo es posible si está pagado, y ese rechazo es un resultado esperado, no una avería: se modela dentro del esquema devolviendo un *payload* con el pedido o una lista de errores tipados.

```graphql
type ShipOrderPayload {
  order: Order
  errors: [UserError!]
}

type UserError {
  code: String!
  message: String!
}
```

```bash
curl -s -X POST http://localhost:5055/graphql -H 'Content-Type: application/json' \
  -d '{"query":"mutation { shipOrder(orderId: 4712) { order { id } errors { code message } } }"}'
```

```json
{"data":{"shipOrder":{"order":null,"errors":[{"code":"ORDER_NOT_PAID","message":"Solo se puede enviar un pedido pagado"}]}}}
```

Con `orderId: 4711` (pagado) devuelve `{"data":{"shipOrder":{"order":{"id":4711,"status":"SHIPPED"},"errors":null}}}`. El cliente distingue por `code` sin analizar texto y el esquema documenta qué puede salir mal. El campo `errors` de la respuesta GraphQL queda para fallos del sistema.

## El problema de las N+1 consultas

El resolver de `Order.customer` de arriba se ejecuta **una vez por cada pedido**. Para listar pedidos con el nombre del cliente:

```graphql
{ orders { id customer { name } } }
```

el servidor de prueba cuenta las llamadas al repositorio (equivalentes a consultas a la base de datos) con 20 pedidos:

```bash
curl -s -X POST localhost:5055/stats/reset
curl -s -X POST localhost:5055/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ orders { id customer { name } } }"}' -o /dev/null
curl -s localhost:5055/stats
```

```json
{"llamadasPedidos":1,"llamadasClientes":20,"llamadasClientesLote":0}
```

**21 llamadas**: 1 para la lista de pedidos y 20 para los clientes, una por pedido (el patrón se llama «N+1»: 1 consulta inicial más N, una por elemento). Con 2.000 pedidos serían 2.001. La razón es estructural: cada resolver solo ve su objeto padre y no sabe qué hacen los demás, así que no puede agrupar.

La solución estándar es un **DataLoader**: un objeto que, durante la ejecución de una petición, recoge todas las claves que se piden («el cliente 2», «el 3»...) y las resuelve en un único lote. En HotChocolate se define con `BatchDataLoader`:

```csharp
public class CustomerByIdDataLoader(Repositorio repo, IBatchScheduler scheduler, DataLoaderOptions options)
    : BatchDataLoader<int, Customer>(scheduler, options)
{
    protected override Task<IReadOnlyDictionary<int, Customer>> LoadBatchAsync(
        IReadOnlyList<int> keys, CancellationToken ct)
        => Task.FromResult(repo.ObtenerClientes(keys));   // SELECT ... WHERE id IN (...)
}

[ExtendObjectType<Order>]
public class OrderResolvers
{
    public Task<Customer?> GetCustomer([Parent] Order pedido, CustomerByIdDataLoader loader, CancellationToken ct)
        => loader.LoadAsync(pedido.CustomerId, ct)!;
}
```

Misma consulta, mismo contador:

```json
{"llamadasPedidos":1,"llamadasClientes":0,"llamadasClientesLote":1}
```

**2 llamadas** (1 de pedidos y 1 por lote para los cinco clientes distintos). El DataLoader además deduplica: los 20 pedidos solo tienen 5 clientes, y el lote pide cada uno una vez. Sin esto, GraphQL puede ser más lento que el REST al que sustituye. En un servidor con acceso a datos por EF Core hay que aplicar lo mismo a cualquier campo que dependa de otra tabla.

## Coste y seguridad

Como el cliente decide la forma de la consulta, también puede decidir pedir una consulta que tumbe el servidor. Un servidor sin límites ejecuta todo lo que sea válido contra el esquema. Los límites se configuran por servidor; estas pruebas usan HotChocolate con profundidad máxima 5, coste máximo 200 e introspección desactivada.

```csharp
builder.Services.AddGraphQLServer()
    // ... tipos ...
    .AddMaxExecutionDepthRule(5)
    .ModifyCostOptions(o => { o.EnforceCostLimits = true; o.MaxFieldCost = 200; })
    .DisableIntrospection();   // en producción pública, si no hay consumidores de terceros
```

### Profundidad

Si el esquema tiene un ciclo (`Customer.orders` devuelve pedidos y cada `Order.customer` devuelve un cliente), la consulta puede anidarse sin fin:

```graphql
{ order(id: 4711) { customer { orders { customer { orders { customer { orders { id } } } } } } } }
```

```http
HTTP/1.1 400 Bad Request

{"errors":[{"message":"The GraphQL document has an execution depth of 8 which exceeds the max allowed execution depth of 5.", ... "extensions":{"allowedExecutionDepth":5,"detectedExecutionDepth":8}}]}
```

El servidor la rechaza antes de ejecutarla. Sin el límite, cada nivel multiplica el trabajo.

### Complejidad y alias repetidos

Una consulta poco profunda puede ser carísima si repite el mismo campo muchas veces con alias. Treinta alias de `order { customer { name } }` son una sola petición HTTP y treinta ejecuciones:

```graphql
{ a0: order(id: 4711) { customer { name } }  a1: order(id: 4711) { customer { name } }  ...  a29: order(id: 4711) { customer { name } } }
```

```http
HTTP/1.1 400 Bad Request

{"errors":[{"message":"The maximum allowed field cost was exceeded.","extensions":{"code":"HC0047","fieldCost":330,"maxFieldCost":200}}]}
```

Esto esquiva los límites por petición HTTP (un limitador de peticiones por minuto ve una sola), de ahí que el coste se calcule sobre el contenido de la consulta: cada campo suma un peso (los que consultan otra fuente, más) y los campos que devuelven listas lo multiplican por el tamaño esperado. Una consulta `orders` de 20 pedidos con `customer` por cada uno se contabiliza como lo que es, no como «una petición». Las listas sin argumento de paginación son el otro vector: `orders { ... }` devuelve todo.

### Introspección

La **introspección** es la capacidad de preguntar al servidor por su propio esquema (`__schema`, `__type`); gracias a ella funcionan los editores con autocompletado y la documentación generada. En producción expone al público todos los tipos y campos, incluidos los que el frontend oficial nunca usa. Con la introspección desactivada:

```bash
curl -s -X POST localhost:5055/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ __schema { types { name } } }"}'
```

```json
{"errors":[{"message":"Introspection is not allowed for the current request.","locations":[{"line":1,"column":3}],"extensions":{"code":"HC0046","field":"__schema"}}]}
```

Desactivarla no sustituye a la autorización (un campo oculto sigue siendo consultable por quien lo adivine), pero quita el mapa. Una API pública pensada para terceros la necesita activada.

## Caché

REST aprovecha la caché HTTP: `GET /products/42` tiene una URL que identifica el recurso, y navegadores, proxies y CDN lo guardan según `Cache-Control` y `ETag`. GraphQL por `POST /graphql` rompe ese esquema: todas las peticiones tienen la misma URL, el `POST` no se cachea por defecto y el recurso es la forma de la consulta, que cambia con cada cliente. Lo que se hace:

- **Consultas persistidas** (*persisted queries*): el cliente registra con antelación cada consulta con un identificador (un *hash*) y después envía solo `{"id":"abc123","variables":{...}}`, a veces por `GET /graphql?id=abc123&variables=...`. Esa URL sí se puede cachear en CDN, el cuerpo es minúsculo y, si el servidor solo acepta consultas registradas, desaparecen los abusos de la sección anterior.
- **Caché en el cliente**: librerías como Apollo Client o Relay guardan los objetos normalizados por tipo e `id` (`Order:4711`), de modo que una consulta nueva reutiliza lo que ya llegó por otra.
- **Caché en el servidor**: de resultados de campos costosos o del DataLoader por petición (el DataLoader ya cachea dentro de una misma petición).

## Evolución del esquema en lugar de versiones

En REST es habitual publicar `/v1/` y `/v2/` cuando se rompe el contrato. En GraphQL, como el cliente pide campo a campo, añadir campos y tipos nuevos no rompe a nadie, y lo que se retira se marca antes con `@deprecated`:

```graphql
type Order {
  id: Int!
  status: OrderStatus!
  state: String @deprecated(reason: "Usar status, que es un enum")
}
```

Las herramientas (editores, introspección) muestran el aviso y el servidor puede medir qué clientes usan todavía el campo antes de borrarlo. Lo que sí rompe: eliminar o renombrar campos, cambiar un tipo, pasar un campo de nullable a `!` en los argumentos o de `!` a nullable en el resultado. Para versionar el contrato OpenAPI de una API REST, ver [Versionado-de-Contratos.md](../contratos-de-api/Versionado-de-Contratos.md).

## ¿GraphQL o REST?

| Situación | Mejor opción | Motivo |
|---|---|---|
| Varios clientes (web, móvil, terceros) con necesidades de datos distintas | GraphQL | Cada uno pide su forma sin endpoints a medida |
| Pantallas que agregan muchos recursos relacionados | GraphQL | Un viaje en lugar de una cascada de llamadas |
| Equipo frontend que evoluciona sin esperar a backend | GraphQL | Nuevos campos disponibles sin nuevos endpoints |
| API simple, CRUD, un único cliente | REST | Menos piezas; el sobrecoste de GraphQL no se amortiza |
| Subida de ficheros | REST | GraphQL no define subida; existe una extensión no oficial de *multipart*, pero un endpoint `POST` aparte es lo más simple |
| Cachear con CDN y caché HTTP «gratis» | REST | URL por recurso; en GraphQL exige consultas persistidas |
| Equipo pequeño sin experiencia con GraphQL | REST | Hay que dominar DataLoader, límites de coste y manejo de errores parciales |
| API pública para integradores que esperan convenciones conocidas | REST | Herramientas y expectativas más extendidas |

Pueden convivir: muchas empresas ofrecen REST para integraciones y GraphQL para sus propias aplicaciones. La comparativa con el resto de estilos está en [Qué es una API](Que-es-una-API.md) y [REST](REST.md).

## Cuándo NO usar GraphQL

- **El dato es plano y los clientes piden siempre lo mismo.** No hay over-fetching que resolver, solo complejidad añadida.
- **Operaciones orientadas a acción** (`POST /orders/4711/cancel`, `/reports/generate`): encajan mejor en [RPC](RPC.md) o en endpoints REST que en un grafo.
- **Descarga o subida de binarios grandes**: no hay un mecanismo estándar; usa HTTP directo.
- **Servicio a servicio con rendimiento crítico**: un formato binario con contrato estricto, como [gRPC](gRPC.md), es más adecuado.
- **Sin capacidad de operar los límites**: sin límite de profundidad y coste, un único cliente puede saturar el servidor.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| El esquema tiene un tipo por tabla y los mismos nombres de columna; cada cambio en la base de datos rompe a los clientes | Esquema como espejo de la base de datos: se publicó el modelo de almacenamiento en lugar del modelo que necesitan los clientes |
| `createOrder`, `updateOrder`, `deleteOrder` como único vocabulario; el cliente no sabe qué reglas se aplican | Mutations con verbo CRUD genérico: conviene nombrarlas por la intención (`shipOrder`, `cancelOrder`, `applyCoupon`) |
| Un fallo pequeño anula una pantalla entera | Demasiados `!`: el `null` de un campo no nulo sube al objeto padre; usar `!` solo en lo que nunca falta |
| Todos los campos son nullable y el cliente comprueba `null` en todas partes | El extremo contrario: se perdió la garantía del contrato; marcar `!` en lo que de verdad nunca falta |
| El panel va lento con listas largas y la base de datos recibe cientos de consultas iguales | Resolvers que consultan la BD uno a uno: falta un DataLoader (ver «El problema de las N+1 consultas») |
| El cliente parsea mensajes de texto para saber que el cupón caducó | Errores de negocio devueltos como excepciones sin tipar en `errors`: modelarlos como parte del *payload* de la mutación |
| Una sola petición satura el servidor | Sin límites de profundidad, coste ni paginación obligatoria |
| `orders: [Order!]!` devuelve miles de elementos | Lista sin paginación; añadirla después rompe consultas existentes |

## Buenas prácticas avanzadas

- **Resuelve las N+1 en el diseño, no cuando duele.** Todo campo que consulte otra tabla o servicio debería pasar por un DataLoader; es mucho más barato hacerlo al crear el resolver que descubrirlo con 2.000 pedidos.
- **Usa `!` con criterio.** Un campo no nulo que falla anula en cascada al padre hasta encontrar algo nullable. Reserva `!` para lo que jamás puede faltar; deja nullable lo que dependa de otro servicio que pueda caerse (como `trackingCode`).
- **Pon límites de profundidad, coste y paginación antes de publicar.** Y si los clientes son los tuyos, acepta solo consultas persistidas: elimina los abusos de raíz.
- **Tipa los errores de negocio dentro del esquema.** Un *payload* con el resultado o una lista de `UserError { code, message }` permite al cliente tratarlos con tipos; `errors` queda para lo inesperado. Para el patrón equivalente en C#, ver [Result-Pattern.md](../patrones-de-diseno/Result-Pattern.md).
- **Pagina con *connections* (cursores) desde el principio.** La convención es `orders(first: 20, after: $cursor)` devolviendo `edges` y `pageInfo`. Cambiar después un campo-lista simple a *connection* rompe todas las consultas existentes.
- **Diseña el esquema alrededor de lo que necesitan los clientes**, no de las tablas, y nombra las mutaciones por intención.
- **Federación**: cuando varios equipos tienen cada uno su propia API GraphQL y se quiere exponer un único grafo, se compone un esquema unificado con una puerta de enlace (*federation*). Es un tema aparte.

## Documentación oficial

- [graphql.org/learn](https://graphql.org/learn/): la introducción oficial; merece la pena para las secciones de esquemas y tipos, consultas y *best practices* cuando se quiere el vocabulario exacto.
- [Especificación de GraphQL](https://spec.graphql.org/September2025/): la referencia canónica; útil para saber qué es un error de validación y qué de ejecución, y cómo se propaga el `null`.
- [GraphQL sobre HTTP](https://graphql.github.io/graphql-over-http/): qué códigos de estado y tipos de contenido deben devolver los servidores; consultarla al implementar o depurar un cliente.
- [Documentación de HotChocolate](https://chillicream.com/docs/hotchocolate/v16): para DataLoader, límites de coste y configuración del servidor de .NET usado aquí.

---

*En resumen: GraphQL permite que cada cliente pida exactamente la forma de datos que necesita, y a cambio traslada al servidor el trabajo de evitar N+1 consultas y de poner límites a lo que se puede pedir.*
