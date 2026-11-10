# ASP.NET Core — Guía de tecnologías

Guía de **ASP.NET Core**, el framework web de .NET, para quien ya programa en C#/.NET (consola, librerías, backend) pero no ha construido todavía una API web. Parte de lo que ya conoce la plataforma, explica qué añade el framework encima, recorre los atributos y las piezas que aparecen en cualquier API de controladores (enrutado, binding, validación, autorización, respuestas), compara los estilos de programación web que ofrece y termina con la publicación de la aplicación.

Los ejemplos comparten un escenario: la API de una tienda online (`Tienda.Api`, rutas `/api/productos` y `/api/pedidos`, pedido #4711), con las respuestas reales de `curl` sobre .NET 10.

---

## Orden de lectura recomendado

### 1. El salto desde .NET Core

De un programa que hace algo y termina a un servidor que atiende peticiones sin parar.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [De .NET Core a ASP.NET Core](De-NET-Core-a-ASP-NET-Core.md) | Qué añade ASP.NET sobre el .NET que ya se conoce: servidor, inyección de dependencias, configuración, middleware y entornos. |

### 2. Las piezas de una API de controladores

Los atributos son la forma en que ASP.NET Core recibe instrucciones declarativas. Estas fichas siguen el camino de una petición: cómo llega a la acción, cómo se leen y validan sus datos, quién puede ejecutarla y qué se responde. Quien no conozca el mecanismo de los atributos puede empezar por [Atributos](../../lenguajes/csharp-dotnet/caracteristicas-del-lenguaje/Atributos.md) en la guía del lenguaje.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 2 | [[ApiController]](ApiController.md) | Lo que activa el atributo: validación automática, inferencia de orígenes y respuestas `ProblemDetails`. El punto de entrada. |
| 3 | [Enrutado y verbos HTTP](Enrutado-y-Verbos.md) | `[Route]`, `[HttpGet]`, `[HttpPost]`…: cómo se asocia cada método a una URL y un verbo, y qué ocurre cuando dos rutas coinciden. |
| 4 | [Model binding ([From...])](Model-Binding.md) | `[FromBody]`, `[FromQuery]`, `[FromRoute]`…: de dónde sale el valor de cada parámetro y qué pasa cuando no encaja. |
| 5 | [Validación con Data Annotations](Validacion-con-DataAnnotations.md) | `[Required]`, `[Range]`, `[EmailAddress]`…: las reglas de los datos de entrada y la respuesta 400 que producen. |
| 6 | [[Authorize] y [AllowAnonymous]](Authorize.md) | Quién puede acceder a cada endpoint: autenticación, roles, políticas y autorización por recurso. |
| 7 | [Tipos de retorno de una acción](Tipos-de-Retorno-de-una-Accion.md) | `IActionResult`, `ActionResult<T>`, `TypedResults` y `ProblemDetails`: cómo lo que se devuelve se traduce en código de estado, cuerpo y documento OpenAPI. |

### 3. El panorama completo

La vista de pájaro: qué otros estilos ofrece el framework y cuándo conviene cada uno.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 8 | [Modelos de programación web](Modelos-de-programacion-web.md) | MVC, Razor Pages, controladores de API, Minimal APIs y Blazor comparados con el mismo caso, y cómo encajan como capa de presentación de una Clean Architecture. |

### 4. Llevarlo a producción

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 9 | [Despliegue](Despliegue.md) | `dotnet publish`, configuración por entorno, Kestrel tras un proxy inverso, health checks y contenedores. |

---

## Qué ficha consultar según el síntoma

| Si la respuesta es… | Ficha |
|---|---|
| 404 en una ruta que debería existir, o 405 con `Allow` | [Enrutado y verbos HTTP](Enrutado-y-Verbos.md) |
| Un parámetro llega vacío o a su valor por defecto | [Model binding](Model-Binding.md) |
| 400 con `errors` por campo | [Validación con Data Annotations](Validacion-con-DataAnnotations.md) y [[ApiController]](ApiController.md) |
| 401 o 403 | [[Authorize] y [AllowAnonymous]](Authorize.md) |
| 200 con un cuerpo de error, o un `Location` equivocado | [Tipos de retorno de una acción](Tipos-de-Retorno-de-una-Accion.md) |
| Un servicio inyectado falla al arrancar | [De .NET Core a ASP.NET Core](De-NET-Core-a-ASP-NET-Core.md) |
| `Request.Scheme` es `http` detrás de un proxy | [Despliegue](Despliegue.md) |

---

> Los atributos como mecanismo del lenguaje (crear los propios, `[AttributeUsage]`, reflection) están en [Atributos](../../lenguajes/csharp-dotnet/caracteristicas-del-lenguaje/Atributos.md), dentro de la guía de [C# y .NET](../../lenguajes/csharp-dotnet/README.md). Los estilos de API (REST, GraphQL, gRPC…) se comparan en [Tipos de APIs](../../arquitectura-de-software/tipos-de-apis/README.md), y las pruebas de una API completa en memoria, en [WebApplicationFactory](../../testing/testing-dotnet/WebApplicationFactory.md). Quien viene de escritorio tiene en [De C# WPF a C# para web](../de-wpf-a-web/README.md) el mismo salto desde WPF.
