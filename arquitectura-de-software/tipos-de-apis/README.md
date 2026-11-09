# Tipos de APIs — Guía de tecnologías

Guías sobre los distintos tipos de APIs: qué es una API y, sobre todo, los estilos para construir una (REST, GraphQL, RPC, gRPC, SOAP, WebSockets, Server-Sent Events, long polling, webhooks y eventos). Cada estilo resuelve un problema distinto y tiene un coste distinto; las guías explican cómo funciona cada uno con un intercambio real y cuándo conviene elegirlo. Están pensadas para perfiles backend junior-medio que conocen HTTP y una API REST básica.

Todas comparten el mismo ejemplo: una **tienda online** con productos (`/products/42`), pedidos (`/orders/4711`) y clientes (`/customers/...`) en `https://api.tienda.ejemplo.com`, el mismo escenario que usa la colección [Contratos de API](../contratos-de-api/README.md). Así se puede comparar cómo se pide «el pedido 4711 con su cliente» o «avisarme cuando el pedido se envíe» en cada estilo. Los ejemplos de código son C#/ASP.NET Core y JSON, y las ideas valen para cualquier lenguaje.

---

## Orden de lectura recomendado

### 1. Fundamentos

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Qué es una API](Que-es-una-API.md) | El concepto base, el ciclo petición-respuesta y el mapa para elegir estilo. |

### 2. Estilos de petición-respuesta

El cliente pide y el servidor responde.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 2 | [REST](REST.md) | El estándar de facto: recursos, verbos, códigos de estado, caché y paginación. Casi todo lo demás se compara con REST. |
| 3 | [GraphQL](GraphQL.md) | El cliente pide exactamente los datos que necesita, en una sola llamada. |
| 4 | [RPC](RPC.md) | Pensar en acciones (funciones remotas) en vez de en recursos. La raíz de gRPC y SOAP. |
| 5 | [gRPC](gRPC.md) | RPC moderno, binario y con contrato, para que los servicios se hablen entre sí. |
| 6 | [SOAP](SOAP.md) | El veterano formal basado en XML, todavía presente en banca, seguros y sistemas heredados. |

### 3. Tiempo real

El servidor necesita enviar datos sin que se los pidan.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 7 | [WebSockets](WebSockets.md) | Canal permanente y bidireccional. |
| 8 | [Server-Sent Events](Server-Sent-Events.md) | Flujo en una sola dirección (servidor → cliente), más simple que WebSockets. |
| 9 | [Long Polling](Long-Polling.md) | Simular tiempo real con HTTP normal; útil como respaldo. |

### 4. Comunicación asíncrona y por eventos

Otro sistema avisa cuando ocurre algo, sin que nadie esté preguntando.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 10 | [Webhooks](Webhooks.md) | Una «API al revés»: el servicio llama a una URL propia cuando pasa un evento. |
| 11 | [APIs Dirigidas por Eventos](APIs-Dirigidas-por-Eventos.md) | Sistemas que publican eventos y otros reaccionan, desacoplados por un *broker*. |

### 5. Clasificar y consumir APIs

Dos conceptos que no dependen del estilo técnico.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 12 | [APIs por Audiencia](APIs-por-Audiencia.md) | Públicas, privadas y de socios: una clasificación por *quién* las usa y lo que eso exige. |
| 13 | [SDK](SDK.md) | La biblioteca que envuelve una API para quien la consume; no es un tipo de API. |

---

## Qué estilo elegir

| Necesidad | Estilo |
|---|---|
| Exponer recursos (productos, pedidos) a clientes muy variados, con caché HTTP | [REST](REST.md) |
| Pantallas que combinan muchos recursos y cada cliente necesita campos distintos | [GraphQL](GraphQL.md) |
| Operaciones que son verbos del negocio («cancelar pedido») | [RPC](RPC.md) |
| Comunicación interna entre servicios con contrato estricto y poca latencia | [gRPC](gRPC.md) |
| Integrarse con un sistema heredado que ya habla XML y WS-* | [SOAP](SOAP.md) |
| Datos en vivo en las dos direcciones (chat, edición colaborativa) | [WebSockets](WebSockets.md) |
| Datos en vivo solo del servidor al cliente (progreso, notificaciones) | [Server-Sent Events](Server-Sent-Events.md) |
| Tiempo real donde solo hay HTTP clásico disponible | [Long Polling](Long-Polling.md) |
| Que un tercero reciba un aviso en su servidor cuando algo ocurre en el tuyo | [Webhooks](Webhooks.md) |
| Varios sistemas que reaccionan a lo que ocurre sin conocerse entre sí | [APIs Dirigidas por Eventos](APIs-Dirigidas-por-Eventos.md) |

## Comparativa

| Estilo | Transporte habitual | Formato | Quién inicia la comunicación | Caché HTTP estándar |
|---|---|---|---|---|
| REST | HTTP | JSON | Cliente | Sí |
| GraphQL | HTTP (`POST` a un solo endpoint) | JSON | Cliente | Difícil |
| RPC (JSON-RPC) | HTTP | JSON | Cliente | No |
| gRPC | HTTP/2 | Binario (Protocol Buffers) | Cliente (con *streaming* en ambos sentidos) | No |
| SOAP | HTTP | XML | Cliente | No |
| WebSockets | Conexión propia sobre TCP | Libre (texto o binario) | Ambos | No |
| Server-Sent Events | HTTP | Texto (flujo de eventos) | Servidor | No |
| Long polling | HTTP | Libre | Cliente (el servidor retrasa la respuesta) | No |
| Webhooks | HTTP (`POST` al receptor) | JSON | Servidor | No |
| Eventos con *broker* | Protocolo del *broker* | Libre | Productor | No |

---

> Antes o después de esta colección: [Contratos de API](../contratos-de-api/README.md) explica cómo escribir y mantener el contrato de una API REST, y [Clean Architecture](../clean-architecture/README.md) cómo organizar el backend que las sirve. Si se viene de escritorio, la guía de [transición de WPF a web](../../desarrollo-web/de-wpf-a-web/README.md) cubre la base.
