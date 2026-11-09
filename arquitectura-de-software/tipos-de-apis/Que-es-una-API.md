# Qué es una API

## ¿Qué es?

Una **API** (*Application Programming Interface*, interfaz de programación de aplicaciones) es el contrato mediante el cual un programa pide cosas a otro: qué se puede pedir, cómo se pide y qué se recibe a cambio, sin necesidad de conocer el funcionamiento interno del otro lado.

## ¿Por qué existe?

El software no vive aislado: una app de móvil necesita datos de un servidor, una tienda necesita cobrar a través de un banco, un programa necesita usar funciones de otro. Sin un contrato, cada conexión dependería de los detalles internos del otro programa, y cualquier cambio interno rompería a todos los que lo usan.

La analogía es el camarero de un restaurante. Quien pide (un programa) no entra en la cocina (otro programa): le dice al camarero lo que quiere de una carta, él lo lleva a cocina y trae el plato. La **carta** es el contrato (lo que se puede pedir), el **camarero** es la API (el intermediario) y la **cocina** es la implementación, que se puede reformar entera mientras la carta y el plato sigan siendo los mismos.

> «API» nombra tres cosas distintas según el contexto (tabla siguiente). En esta colección casi siempre significa la tercera fila: la **API web**, la que viaja por la red.

## ¿Cuándo y para qué se usa?

Aparece donde dos piezas de software se comunican: la app de móvil con su servidor, la tienda con la pasarela de pago, el frontend con el backend, un sistema interno con el de un proveedor, un cliente que automatiza sus pedidos.

### Tres significados de «API»

| Tipo | Quién llama a quién | Cómo viaja la llamada | Ejemplo |
|---|---|---|---|
| API de librería | Tu código a un paquete | Llamada a un método dentro del mismo proceso | `JsonSerializer.Serialize(order)`: la superficie pública de `System.Text.Json` |
| API del sistema operativo | Un programa al sistema | Llamada a una función del sistema | `File.ReadAllText` termina pidiendo al sistema operativo que lea un fichero |
| API web | Un programa a otro, en otra máquina | Mensajes por la red (normalmente HTTP) | `GET https://api.tienda.ejemplo.com/orders/4711` |

Las tres comparten la idea: una superficie pública estable delante de una implementación oculta. Lo que cambia es el coste de cruzarla. Una llamada a una librería es de nanosegundos, no puede perderse y falla con una excepción. Una llamada web tarda milisegundos, puede perderse, llegar dos veces o no recibir respuesta, y el otro lado lo mantiene alguien que no controlas. Por eso las APIs web necesitan contrato explícito, errores estructurados, versionado y límites, que se tratan a continuación.

## El ciclo petición-respuesta

El intercambio básico de una API web: el **cliente** (quien pide) envía una **petición** y el **servidor** (quien responde) devuelve una **respuesta**. En la tienda online, pedir el pedido 4711:

```http
GET /orders/4711 HTTP/1.1
Host: api.tienda.ejemplo.com
Accept: application/json
Authorization: Bearer token-de-ana
```

La respuesta, tal como la devuelve un servidor ASP.NET Core mínimo y `curl -i` (salida real, ejecutada el 2026-11-09 con .NET 10):

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
Date: Mon, 09 Nov 2026 09:16:28 GMT
Server: Kestrel
ETag: "v3"
Transfer-Encoding: chunked

{"id":4711,"status":"paid","customerId":17,"lines":[{"productId":42,"quantity":2,"price":19.99}],"total":39.98}
```

Línea por línea:

| Parte | Qué dice |
|---|---|
| `GET` | **Método**: la intención. `GET` lee sin modificar nada; `POST` crea, `PUT`/`PATCH` modifican, `DELETE` borra |
| `/orders/4711` | **Ruta**: qué recurso (el pedido 4711). Junto con `Host`, forma la URL completa |
| `Accept: application/json` | El cliente declara en qué formato quiere la respuesta |
| `Authorization: Bearer …` | Quién pide: la credencial (sección de autenticación más abajo) |
| `200 OK` | **Código de estado**: resultado resumido en un número (`2xx` éxito, `4xx` error del cliente, `5xx` error del servidor) |
| `Content-Type: application/json` | El formato del cuerpo que viene detrás: así el cliente sabe cómo interpretarlo |
| `ETag: "v3"` | Versión del recurso; sirve para cachear y para detectar cambios concurrentes |
| Línea en blanco + JSON | **Cuerpo**: los datos. Las cabeceras terminan en la primera línea en blanco |

Todo lo anterior es texto plano sobre HTTP; el detalle del protocolo está en [HTTP](../../desarrollo-web/de-wpf-a-web/HTTP.md). Desde C# la misma llamada es una línea:

```csharp
var order = await httpClient.GetFromJsonAsync<Order>("orders/4711");
```

## Qué debe ofrecer una API además de datos

Devolver un JSON es la parte fácil. Lo que separa una API usable de una frágil son seis cosas.

### Contrato

El **contrato** dice qué rutas existen, qué recibe cada una y qué devuelve (campos, tipos, códigos de estado). Se describe en un documento legible por máquinas (típicamente OpenAPI) y es lo que el cliente usa para programar sin leer el código del servidor. Cómo escribirlo antes que el código está en [Contrato primero](../contratos-de-api/Contrato-Primero.md).

### Autenticación

La API necesita saber **quién llama** antes de decidir qué puede hacer. Sin credencial válida, la respuesta correcta es un `401`:

```http
HTTP/1.1 401 Unauthorized
Content-Type: application/problem+json
WWW-Authenticate: Bearer

{"type":"about:blank","title":"No autenticado","status":401,"detail":"Falta un token válido."}
```

`401` significa «no sé quién eres»; `403` significa «sé quién eres y no tienes permiso». Las dos preguntas son independientes, y están desarrolladas en [Autenticación frente a autorización](../../seguridad/autenticacion-y-autorizacion/Autenticacion-vs-Autorizacion.md). Cuando la API actúa en nombre de un usuario ante terceros, el estándar es [OAuth 2.0](../../seguridad/autenticacion-y-autorizacion/OAuth2.md).

### Errores

Un error es parte del contrato: mismo formato en todas las rutas, un código de estado correcto y un mensaje que el cliente pueda tratar sin analizar texto libre. Pedir un pedido inexistente:

```http
HTTP/1.1 404 Not Found
Content-Type: application/problem+json

{"title":"Pedido no encontrado","status":404,"detail":"No existe el pedido 9999."}
```

El formato `application/problem+json` es el estándar [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457). Cómo modelarlos con rigor: [Modelado de errores](../contratos-de-api/Modelado-de-Errores.md).

### Versionado

Cuando el contrato tiene que cambiar de forma incompatible, los clientes existentes siguen funcionando si la versión antigua se mantiene (`/v1/orders`, `/v2/orders`, o una cabecera). Ver la sección de acoplamiento más abajo y [Versionado de contratos](../contratos-de-api/Versionado-de-Contratos.md).

### Límites de uso

Una API compartida se protege de clientes que piden demasiado. Al superar el límite responde `429` e indica cuándo reintentar con `Retry-After` (aquí, tras 3 peticiones, salida real):

```http
HTTP/1.1 429 Too Many Requests
Content-Type: application/problem+json
Retry-After: 30

{"title":"Demasiadas peticiones","status":429,"detail":"Límite de 3 peticiones. Reintenta en 30 segundos."}
```

Un cliente educado espera esos 30 segundos; uno que reintenta en bucle sin pausa empeora la situación.

### Documentación

El contrato dice *qué*; la documentación dice *cómo empezar*: un ejemplo que funcione al copiarlo, cómo obtener credenciales, los límites, qué significa cada error. Una API sin documentación de arranque se usa a base de prueba y error y de preguntas al equipo que la mantiene.

## Estilos de API: los ejes que los distinguen

«API web» no es una sola tecnología. Los estilos se distinguen en tres ejes:

| Eje | Opciones | Qué cambia |
|---|---|---|
| Patrón de comunicación | Petición-respuesta; tiempo real (canal abierto, el servidor envía datos cuando los hay); eventos (alguien publica un hecho y quien esté interesado lo recibe) | Si el cliente pregunta cuando le interesa o el servidor avisa |
| Formato | Texto (JSON, XML) frente a binario (Protocol Buffers) | Legibilidad y depuración frente a tamaño y velocidad |
| Quién inicia | El cliente siempre; el servidor, a través de un canal ya abierto; el servidor, llamando a una URL del cliente | Si el cliente necesita ser accesible desde fuera |

Cada estilo ocupa una posición en esos ejes y resuelve mejor unas necesidades que otras. Las tres necesidades de la tienda —«dame el pedido 4711», «avísame cuando se envíe», «actualiza el estado en la pantalla de soporte sin recargar»— caen en estilos distintos.

### Qué estilo para qué necesidad

| Necesito… | Estilo | Ficha |
|---|---|---|
| Exponer recursos (`products`, `orders`, `customers`) con operaciones uniformes sobre HTTP | REST | [REST](REST.md) |
| Que cada cliente pida exactamente los campos que necesita, en una sola petición | GraphQL | [GraphQL](GraphQL.md) |
| Exponer acciones («cancelar pedido», «calcular envío») en vez de recursos | RPC | [RPC](RPC.md) |
| Comunicación rápida y tipada entre servicios internos, con formato binario | gRPC | [gRPC](gRPC.md) |
| Integrarse con un sistema empresarial que exige XML, contrato formal y estándares de seguridad | SOAP | [SOAP](SOAP.md) |
| Un canal abierto en los dos sentidos (chat, panel de soporte interactivo) | WebSockets | [WebSockets](WebSockets.md) |
| Que el servidor empuje datos al navegador en una sola dirección (progreso, notificaciones) | Server-Sent Events | [Server-Sent Events](Server-Sent-Events.md) |
| Recibir novedades sin canal permanente y con la infraestructura HTTP más simple posible | Long polling | [Long polling](Long-Polling.md) |
| Que otro sistema me llame a una URL mía cuando ocurra algo («pedido enviado») | Webhooks | [Webhooks](Webhooks.md) |
| Desacoplar productores y consumidores: publicar hechos y que cada interesado reaccione a su ritmo | APIs dirigidas por eventos | [APIs dirigidas por eventos](APIs-Dirigidas-por-Eventos.md) |
| Decidir qué se expone a quién: privada, de socios o pública | Clasificación por audiencia | [APIs por audiencia](APIs-por-Audiencia.md) |
| Que quien integra no escriba las llamadas HTTP a mano: una librería sobre la API | SDK | [SDK](SDK.md) |

Las dos últimas filas no son estilos de comunicación, sino formas de clasificar y de empaquetar una API; se combinan con cualquiera de las anteriores. Varios estilos suelen convivir en un mismo producto: la tienda puede ofrecer REST a sus clientes, gRPC entre sus servicios internos y webhooks para avisar de pedidos enviados.

## Acoplamiento y evolución

Publicar una API crea una dependencia: cada cliente que la usa queda acoplado a todo lo que puede observar de ella, no solo a lo documentado. Renombrar `customerId` a `clientId` es un cambio de una línea en el servidor y una rotura en cada cliente. Y los clientes no se actualizan a la vez: una app móvil con una versión antigua sigue llamando meses después.

Por eso cambiar una API pública es caro y la regla práctica es:

- **Añadir** (un campo, una ruta, un parámetro opcional) es compatible: los clientes bien escritos ignoran lo que no conocen.
- **Quitar, renombrar o cambiar el significado** es una rotura: exige una versión nueva y un periodo en el que conviven las dos.
- Cuanto más lejos está el cliente (otra empresa, el público), más cara es la rotura; con una API interna que controlas puedes coordinar el cambio.

Qué cuenta como rotura y cómo gestionarla está en [Versionado de contratos](../contratos-de-api/Versionado-de-Contratos.md).

## Cuándo no hace falta una API

Una API web añade red, serialización, autenticación, versionado y un servicio más que operar. Si los dos lados comparten proceso, no compensa:

- **Una librería en proceso.** Si el código reutilizable se consume desde aplicaciones .NET, un paquete con una API pública pequeña (interfaces y tipos) basta; no hay red ni versionado HTTP, solo versiones del paquete.
- **Un módulo del mismo monolito.** Dos módulos de una misma aplicación se hablan con una interfaz y una llamada directa, no con HTTP contra sí mismos. El límite se mantiene con la estructura del código, como explica [Módulos frente a Shared](../clean-architecture/Modulos-vs-Shared.md).
- **Un único consumidor, que es el propio frontend del mismo equipo y despliegue**: puede bastar con endpoints pensados para esa pantalla, sin tratarlos como producto público.

Una API web se justifica cuando los lados se despliegan por separado, los escriben equipos distintos, están en lenguajes o máquinas distintas, o hay terceros.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| «Hacemos una API, o sea, REST» y se discute REST contra GraphQL como si fueran lo mismo que «API» | «API» es el concepto; REST, GraphQL o gRPC son estilos de construirla. Un endpoint HTTP que devuelve JSON no es REST por el mero hecho de existir |
| Cada cambio en una tabla de la base de datos rompe a los clientes | El contrato es el modelo de base de datos serializado tal cual. El contrato debe hablar el idioma de quien consume, no el del esquema interno |
| Al renombrar un campo, las apps instaladas dejan de funcionar | La API no tiene versión ni política de compatibilidad: no hay forma de cambiar sin romper a todos a la vez |
| El cliente cree que un pago salió bien y no fue así | La API devuelve `200 OK` con `{"error":"Tarjeta rechazada"}` en el cuerpo. Los clientes, proxies y herramientas de monitorización miran el código de estado; un error debe llevar `4xx` o `5xx` |
| Los clientes hacen `if (mensaje.Contains("not found"))` | Errores como texto libre sin estructura estable ni código propio |
| Un cliente tumba el servicio sin querer | No hay límite de uso (`429`), o el cliente reintenta en bucle sin respetar `Retry-After` |
| La integración se rompe cuando el proveedor añade un campo | El cliente deserializa con validación estricta y rechaza campos que no conoce |

## Buenas prácticas avanzadas

- **Trata cada campo publicado como una promesa duradera.** En cuanto una API se usa, alguien depende de todo lo observable: campos, formatos, incluso el orden de una lista o el texto exacto de un error. Renombrar un campo «que nadie usa» rompe clientes en producción. Se añade sin quitar y se versiona antes de romper.
- **Diseña el contrato de fuera hacia dentro.** El contrato describe lo que necesita quien consume (un `order` con sus `lines` y un `total`), no cómo se guardan los datos. Así un cambio en la base de datos no se convierte en un cambio de API.
- **Los errores también son contrato.** Mismo formato en todas las rutas, código de estado correcto, un identificador de error estable que el cliente pueda comparar y un mensaje para humanos que pueda cambiar.
- **Sé un lector tolerante al consumir.** Ignora los campos que no reconozcas y no valides más estructura de la que usas. El proveedor puede añadir campos legítimamente; una validación estricta convierte esa mejora en una caída.
- **Asume que la red falla.** Toda llamada remota lleva un *timeout* explícito (los valores por defecto suelen ser enormes), reintentos solo para operaciones seguras de repetir (`GET`; un `POST` que cobra, no) y un plan para cuando la otra API no responde. Esa es la diferencia con una llamada a una librería.

## Documentación oficial

- [RFC 9110: HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110): la definición de métodos, códigos de estado y cabeceras. Merece la pena para consultar qué significa exactamente cada código o cabecera.
- [RFC 9457: Problem Details for HTTP APIs](https://www.rfc-editor.org/rfc/rfc9457): el formato estándar de errores (`application/problem+json`). Cuando se diseñe cómo responde una API ante un fallo.
- [RFC 6585: Additional HTTP Status Codes](https://www.rfc-editor.org/rfc/rfc6585): define `429 Too Many Requests`. Al implementar o consumir límites de uso.
- [Minimal APIs en ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis): cómo construir en C# el servidor de los ejemplos.

---

*En resumen: una API es el camarero entre dos programas: un contrato estable que dice qué se puede pedir y qué se recibe, sin entrar en la cocina; en la web, además, hay que decidir el estilo, y cambiarla cuesta tanto como clientes tenga.*
