# APIs por Audiencia

## ¿Qué es?

Una clasificación de las APIs por **quién las consume** y no por su tecnología: públicas (cualquier desarrollador, sin relación previa), de socios (organizaciones concretas con las que hay un acuerdo) e internas (el propio equipo y sus servicios). La misma API REST puede ser de cualquiera de los tres tipos; lo que cambia es cuánto control hay sobre los clientes y, por tanto, cuánto cuesta equivocarse.

## ¿Por qué existe?

Una API nace casi siempre para el front de la propia tienda. Un día el equipo de logística externo pide acceso a los pedidos, y otro día un comparador de precios quiere leer el catálogo. Lo más fácil es darles la misma API con una clave. Es también lo más caro, por dos razones:

- **Se expone lo interno al mundo.** La respuesta pensada para el front incluye costes, notas del equipo o identificadores secuenciales. Un tercero que la recibe puede guardarla, y no hay forma de retirársela.
- **Se da la misma estabilidad a quien no se controla.** Renombrar un campo en una API interna se resuelve cambiando el front en el mismo despliegue. Hacerlo con un comparador de precios que no conoces rompe su producto un viernes y no sabrás quién ha sido hasta el lunes.

> Piensa en un edificio: la recepción atiende a cualquiera con horario y normas públicas; la zona de proveedores se abre con cita y credencial nominal; los despachos internos se abren con tarjeta de empleado. Es el mismo edificio, pero cada puerta tiene reglas, vigilancia y consecuencias distintas.

## ¿Cuándo y para qué se usa?

La clasificación se usa para decidir, antes de escribir código, cuánta ceremonia necesita cada puerta de entrada: qué datos se devuelven, cómo se autentica, qué límites se aplican, cuánto aviso se da antes de un cambio y qué documentación hace falta. En la tienda hay tres puertas:

- **API pública**: un comparador de precios construye sobre ella y lee `products`. Nadie en la tienda sabe quién lo hace, ni cuándo.
- **API de socios**: el socio de logística consulta `orders` para preparar envíos y actualiza su estado. Hay contrato firmado y una persona de contacto.
- **API interna**: el front de la tienda y los servicios propios. El mismo equipo (o una empresa vecina del organigrama) controla ambos lados.

## Las tres audiencias, lado a lado

| Dimensión | Pública | De socios | Interna |
|---|---|---|---|
| Quién la consume | Cualquier desarrollador que se registre | Organizaciones con acuerdo | Front y servicios propios |
| Control sobre los clientes | Ninguno: no se conoce a todos ni se puede obligar a migrar | Parcial: se conoce a cada socio y se puede pactar | Total: se despliega junto con los clientes |
| Estabilidad exigida | Máxima: cambios que rompen, solo con versión nueva | Alta: igual, con plazos pactados | Baja: puede cambiar con contratos coordinados |
| Política de cambios | Versiones, aviso público y fecha de retirada larga | Aviso directo al socio y plazo en el acuerdo | Cambio y migración de clientes en el mismo ciclo |
| Autenticación habitual | Clave de API o OAuth 2.0 con tokens de usuario | OAuth 2.0 *client credentials* o mTLS, credencial por socio | Identidad de servicio, mTLS o token del usuario propagado |
| Límites de uso | Estrictos, por plan y por segundo | Acordados por socio, más holgados | Normalmente protección contra descontrol, no cuota comercial |
| Documentación | Portal con guía de inicio, ejemplos y entorno de pruebas | Documentación compartida y soporte directo | Repositorio y catálogo internos |
| Soporte y SLA | Mejor esfuerzo o por plan | Pactado en el contrato | El del propio equipo |
| Coste de un cambio que rompe | Muy alto: clientes desconocidos y reputación | Alto: incidencia con un cliente identificable | Bajo: se corrige en el siguiente despliegue |

La fila decisiva es la de control sobre los clientes. Casi todas las demás (versionado, avisos, límites, soporte) son consecuencias de cuánta capacidad hay de obligar a un cliente a cambiar.

### La API «de plataforma»

Cuando una empresa abre sus capacidades a terceros para que construyan productos sobre ellas, suele ofrecer una API compuesta por varias capas con audiencias distintas. Los nombres varían de una empresa a otra; aquí se describen por lo que hacen:

- **Partner abierto**: cualquier organización puede darse de alta, aceptar unas condiciones y obtener credenciales sin intervención humana. Se parece a la pública, pero con una relación identificada (hay una cuenta, y se puede suspender).
- **Partner restringido**: el acceso lo concede una persona de la empresa tras un acuerdo. Da acceso a operaciones y datos que no se ofrecen a todos, como actualizar el estado de un pedido.
- **Interna expuesta fuera**: una API que nació para uso propio y se abre a un socio. Es el caso más peligroso: se hereda el modelo interno, sus nombres y sus datos. Lo sensato es exponerla a través de una capa que adapte y filtre, no abriéndola tal cual (ver más abajo).

## Una misma operación, tres vistas

El recurso es el mismo en las tres: `GET /orders/4711`. Cambia la credencial, y con ella el alcance (*scope*): una cadena como `orders:read:partner` que indica qué puede hacer la credencial. El servidor elige la vista según el alcance más alto que la credencial lleve. Es un servidor mínimo de ASP.NET Core con tres claves de prueba (los nombres de alcance son de este ejemplo, no un estándar).

```csharp
app.MapGet("/orders/{id:int}", (int id, HttpContext ctx) =>
{
    var c = Credenciales.Resolver(ctx);   // lee X-Api-Key y devuelve cliente y alcances
    if (c is null) return Results.Json(new { error = "no_autenticado" }, statusCode: 401);
    if (id != 4711) return Results.Json(new { error = "no_encontrado" }, statusCode: 404);

    if (c.Scopes.Contains("orders:read:internal")) return Results.Ok(Pedido.Interna);
    if (c.Scopes.Contains("orders:read:partner"))  return Results.Ok(Pedido.Socio);
    if (c.Scopes.Contains("orders:read:public"))   return Results.Ok(Pedido.Publica);
    return Results.Json(new { error = "alcance_insuficiente" }, statusCode: 403);
});
```

**Vista pública.** Para un tercero que llega con el consentimiento de quien hizo el pedido (por ejemplo, una app de seguimiento): sin datos personales, con identificadores opacos que no permiten deducir cuántos pedidos tiene la tienda.

```json
{
  "id": "ord_8Kq2mZ",
  "status": "paid",
  "lines": [
    { "product": "prd_Xf3a91", "quantity": 2 },
    { "product": "prd_Lm7c04", "quantity": 1 }
  ]
}
```

**Vista de socio.** Con lo que la logística necesita para entregar: dirección y estado logístico. No incluye precios ni notas, porque no les hacen falta.

```json
{
  "id": 4711,
  "status": "paid",
  "logistics": { "stage": "ready_to_ship", "carrier": "TransExpress", "parcels": 1, "weightKg": 2.4 },
  "shippingAddress": {
    "name": "Marta Ruiz", "street": "Calle Mayor 12", "city": "Valencia",
    "postalCode": "46001", "country": "ES", "phone": "+34 600 000 000"
  },
  "lines": [
    { "sku": "BK-042", "quantity": 2 },
    { "sku": "MG-007", "quantity": 1 }
  ]
}
```

**Vista interna.** El modelo completo, con costes, márgenes, referencias de pago y notas.

```json
{
  "id": 4711,
  "status": "paid",
  "customerId": 311,
  "lines": [
    { "productId": 42, "sku": "BK-042", "quantity": 2, "unitPrice": 19.99, "unitCost": 11.20 },
    { "productId": 57, "sku": "MG-007", "quantity": 1, "unitPrice": 8.50, "unitCost": 3.10 }
  ],
  "totals": { "revenue": 48.48, "cost": 25.50, "margin": 22.98 },
  "paymentRef": "pi_3Qx9fA",
  "internalNotes": "Cliente con incidencia previa de entrega; revisar antes de enviar.",
  "fraudScore": 0.07
}
```

Diferencias que no son solo «campos de menos»: el identificador pasa de opaco (`ord_8Kq2mZ`) a secuencial (`4711`), las líneas se identifican por `product` opaco, por `sku` o por `productId` según quién mira, y solo la interna contiene datos cuya filtración tiene consecuencias comerciales o legales (`unitCost`, `fraudScore`, `internalNotes`).

La escritura también depende del alcance. El socio de logística actualiza el estado; el comparador no puede:

```bash
curl -s -X PATCH -H 'X-Api-Key: pk_logistica_demo' -H 'Content-Type: application/json' \
     -d '{"status":"shipped"}' http://localhost:5847/orders/4711/status
# {"id":4711,"status":"shipped"}

curl -si -X PATCH -H 'X-Api-Key: pk_comparador_demo' -H 'Content-Type: application/json' \
     -d '{"status":"shipped"}' http://localhost:5847/orders/4711/status
# HTTP/1.1 403 Forbidden
# {"error":"alcance_insuficiente","mensaje":"Se necesita el alcance orders:write:status.","requerido":"orders:write:status"}
```

Un `401` significa «no sé quién eres» (falta la credencial o no es válida); un `403`, «sé quién eres y no puedes hacer esto».

## Autenticación y autorización según la audiencia

La autenticación responde a *quién* llama; la autorización (aquí, los alcances) a *qué puede hacer*. Una **clave de API identifica a una aplicación, no a una persona**: quien la tenga es «el comparador de precios», pero la clave no dice qué usuario hay detrás. Sirve para atribuir tráfico, aplicar límites y revocar a un cliente; no sirve para decidir qué datos de qué persona puede ver una petición.

| Mecanismo | Identifica a | Cuándo encaja | Cuidado |
|---|---|---|---|
| Clave de API | Una aplicación | Pública de solo lectura; primer paso sencillo para terceros | Se filtra con facilidad (repositorios, el navegador); sin caducidad, hay que rotarla a mano |
| OAuth 2.0, *client credentials* | Una aplicación, con alcances y token de vida corta | Socios y servicios entre sí: máquina a máquina | Hay que operar un servidor de autorización |
| OAuth 2.0 con usuario (código de autorización) | Una aplicación actuando en nombre de una persona | Terceros que acceden a datos de la persona usuaria, con su consentimiento | Pedir solo los alcances necesarios |
| mTLS | El cliente, mediante un certificado | Socios con requisitos altos; servicios internos | Emitir, rotar y revocar certificados |
| Token de usuario (JWT u opaco) | La persona usuaria | El front de la tienda hacia su API | Es el caso de la API interna que llega al navegador |

Cómo funcionan los flujos de OAuth 2.0 y los tokens se explica en [OAuth2](../../seguridad/autenticacion-y-autorizacion/OAuth2.md) y [JWT](../../seguridad/autenticacion-y-autorizacion/JWT.md); aquí solo importa qué elegir según la audiencia.

Reglas que valen para las tres: una credencial **por cliente** (nunca una clave compartida), con los **alcances mínimos** de su caso de uso y revocable de forma individual.

## Límites de uso diferenciados

Un límite protege la API y, en la pública, es también el producto: los planes se diferencian por cuota. Hay dos clases que se combinan:

- **Cuota por plan**: peticiones por día o por mes (la parte comercial).
- **Límite por segundo (o ráfaga)**: protege el servidor de un cliente que se descontrola.

Un limitador con política por audiencia en ASP.NET Core usa `AddRateLimiter` con un `GlobalLimiter` particionado: para cada petición devuelve una partición (con su algoritmo) según quién llama. Aquí la pública tiene una ventana fija de 3 peticiones cada 10 segundos por clave, el socio un *token bucket* (cubo de fichas que se rellena a ritmo constante) y la interna ninguno. Los valores son de demostración:

```csharp
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(ctx =>
    {
        var cliente = Credenciales.Resolver(ctx);
        return cliente?.Audiencia switch
        {
            "publica" => RateLimitPartition.GetFixedWindowLimiter($"pub:{cliente.Nombre}",
                _ => new FixedWindowRateLimiterOptions
                    { PermitLimit = 3, Window = TimeSpan.FromSeconds(10), QueueLimit = 0 }),
            "socio" => RateLimitPartition.GetTokenBucketLimiter($"soc:{cliente.Nombre}",
                _ => new TokenBucketRateLimiterOptions
                {
                    TokenLimit = 10, TokensPerPeriod = 5,
                    ReplenishmentPeriod = TimeSpan.FromSeconds(1), QueueLimit = 0
                }),
            "interna" => RateLimitPartition.GetNoLimiter("int"),
            _ => RateLimitPartition.GetFixedWindowLimiter($"anon:{ctx.Connection.RemoteIpAddress}",
                _ => new FixedWindowRateLimiterOptions
                    { PermitLimit = 2, Window = TimeSpan.FromSeconds(10), QueueLimit = 0 })
        };
    });
    options.OnRejected = async (ctx, ct) =>
    {
        if (ctx.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter))
            ctx.HttpContext.Response.Headers.RetryAfter =
                ((int)Math.Ceiling(retryAfter.TotalSeconds)).ToString();
        ctx.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
        await ctx.HttpContext.Response.WriteAsJsonAsync(
            new { error = "limite_de_uso", mensaje = "Has superado el límite de peticiones de tu plan." }, ct);
    };
});

app.UseRateLimiter();
```

Salida real (.NET 10) con cinco peticiones seguidas de la clave pública, y la cuarta con cabeceras:

```text
200
200
200
429
429

HTTP/1.1 429 Too Many Requests
Content-Type: application/json; charset=utf-8
Retry-After: 10

{"error":"limite_de_uso","mensaje":"Has superado el límite de peticiones de tu plan."}
```

El socio, con una ráfaga de 14 peticiones seguidas, obtuvo `200` once veces (las 10 fichas del cubo y una repuesta mientras corría la ráfaga), después `429` dos veces y de nuevo `200` cuando se repuso otra. La clave interna hizo 30 peticiones seguidas y recibió 30 respuestas `200`.

`Retry-After` indica cuántos segundos esperar. Con `GetFixedWindowLimiter`, el valor que da el limitador es el tamaño de la ventana (10), no el tiempo restante, así que un cliente bien escrito espera como máximo ese tiempo. Una petición sin credencial en la demo cae en un cubo por IP muy estrecho; al estar la autenticación en el propio *endpoint*, las dos primeras reciben `401` y la tercera `429`.

El código `429` viene del RFC 6585 y la cabecera `Retry-After` del RFC 9110; el limitador de ASP.NET Core es solo una de las formas de aplicarlos.

## Estabilidad y política de cambios

Cuántos cambios admite una API depende de cuántos clientes ve romperse sin poder arreglarlos:

| Cambio | Interna | Socios | Pública |
|---|---|---|---|
| Añadir un campo opcional | Libre | Libre, avisando | Libre, documentando |
| Renombrar o eliminar un campo | Se cambia API y clientes a la vez | Versión nueva y plazo pactado | Versión nueva y plazo público largo |
| Retirar una versión | Cuando ya no la use nadie | Fecha acordada por contrato | Aviso con meses de antelación |

En la pública y en la de socios, el cliente tiene que enterarse del cambio sin leer un correo. Dos cabeceras de respuesta lo señalan en la propia API:

```http
HTTP/1.1 200 OK
Deprecation: @1767225600
Sunset: Thu, 31 Dec 2026 23:59:59 GMT
Link: <https://developers.tienda.ejemplo.com/migracion-v2>; rel="deprecation"
```

- `Deprecation` indica que el recurso está o estará obsoleto; el valor es una fecha en segundos Unix precedida de `@`. Está definida en el RFC 9745 (marzo de 2025, categoría *Standards Track*).
- `Sunset` indica el momento a partir del cual el recurso puede dejar de responder. Está definida en el RFC 8594 (mayo de 2019, categoría *Informational*, es decir, no es un estándar de seguimiento).
- El `Link` con `rel="deprecation"` apunta a la documentación de la migración (también del RFC 9745).

En la API interna basta con coordinar contratos: se cambia el contrato y los clientes en la misma iteración, y la integración continua rechaza lo que rompa a un cliente conocido. Cómo se versionan los contratos y cómo se gobiernan los cambios se explica en [Versionado de contratos](../contratos-de-api/Versionado-de-Contratos.md) y [Gobierno de cambios en contratos](../contratos-de-api/Gobierno-de-Cambios-en-Contratos.md).

## Exponer una API interna sin abrir el puerto

Una API interna no se vuelve de socios ni pública abriendo su puerto al exterior: se heredan su modelo, sus datos de más y su ausencia de límites. Lo habitual es poner delante una **puerta de enlace** (*API gateway*): una capa que recibe el tráfico de fuera y decide qué entra y en qué forma.

```text
  Comparador          Socio de logística          Front de la tienda
  (pública)           (socios)                    (interna)
      │                     │                           │
      ▼                     ▼                           │
┌───────────────────────────────────────┐               │
│          Puerta de enlace             │               │
│  autentica · aplica alcances          │               │
│  límites por cliente · registra       │               │
│  adapta: oculta campos, opacifica ids │               │
└───────────────┬───────────────────────┘               │
                │ solo rutas y campos expuestos         │
                ▼                                       ▼
        ┌───────────────────────────────────────────────────┐
        │     Servicios internos (orders, products, ...)     │
        │     red privada, sin acceso directo desde fuera    │
        └───────────────────────────────────────────────────┘
```

La capa hace cuatro cosas que la API interna no debe hacer ella misma: validar la credencial y sus alcances, aplicar límites por cliente, filtrar la respuesta a la vista de la audiencia y registrar quién llamó. Qué debe declarar el contrato público en materia de seguridad se trata en [Seguridad en el contrato](../contratos-de-api/Seguridad-en-el-Contrato.md).

El front de la tienda llega al navegador, y todo lo que llega al navegador es visible para cualquiera que abra las herramientas de desarrollador. Esa API es «interna» por organigrama, no por exposición, y se protege (autenticación, validación, límites) como una pública.

## Documentación y experiencia de quien desarrolla

| Aspecto | Pública | De socios | Interna |
|---|---|---|---|
| Entrada | Portal con registro y guía de inicio (la primera llamada en minutos) | Documentación compartida tras el acuerdo y alta manual | Repositorio, catálogo o contrato en el código |
| Ejemplos | Imprescindibles, por lenguaje, con respuestas reales | Casos de uso del socio (el flujo de envío, no cada *endpoint*) | Los que ayuden al equipo |
| Pruebas | Entorno de pruebas (*sandbox*) con datos ficticios y claves de prueba | Entorno de integración compartido | Entornos de desarrollo |
| Cambios | Registro de cambios público y calendario de retiradas | Aviso directo y reunión | Aviso en el canal del equipo |
| Soporte | Foro, correo o plan de pago | Persona de contacto y SLA | El equipo propietario |

Una API pública sin *sandbox* obliga a probar con datos reales o a no probar; una de socios sin persona de contacto convierte cada incidencia en una cadena de correos.

## ¿Pública, de socios o interna?

Las preguntas, en este orden:

| Pregunta | Si la respuesta es sí | Si es no |
|---|---|---|
| ¿Puedo obligar a los clientes a migrar cuando cambio algo? | Interna | Socios o pública |
| ¿Conozco a quien la usa y tengo un acuerdo con cada uno? | De socios | Pública |
| ¿Puede alguien darse de alta sin intervención humana? | Pública (o partner abierto) | De socios o interna |
| ¿Llega la respuesta a un navegador o dispositivo que no controlo? | Tratar como pública en protección | Puede ser interna de verdad |
| ¿Hay datos que no deben salir de la empresa (costes, notas, puntuaciones)? | Vista adaptada o no exponerlos | Revisar de todos modos campo a campo |

La evolución habitual es **interna → socios → pública**, y cada salto tiene un coste:

| Salto | Qué hay que añadir | Coste principal |
|---|---|---|
| Interna → socios | Credencial por socio y alcances; vista adaptada con los campos necesarios; versionado y aviso de cambios; límites; contacto de soporte | Dejar de poder cambiar el contrato libremente |
| Socios → pública | Registro autoservicio; límites y planes; portal y *sandbox*; moderación de abusos; plazos de retirada largos | Soporte a clientes desconocidos y estabilidad prolongada |

Dar el salto desde un diseño interno «rápido y sucio» (sin versiones, con datos de más) obliga a rehacerlo. La disciplina del contrato no depende de la audiencia; los controles de acceso, sí.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| Un socio recibe `customerId`, `unitCost` o notas internas | Se expuso el modelo interno como respuesta pública; falta una vista por audiencia |
| Un tercero lee pedidos que no son suyos | Una sola clave con todos los permisos y sin comprobar a quién pertenece cada recurso |
| El tráfico de un cliente tumba la API para todos | La pública sin límites de uso, o límites globales en lugar de por cliente |
| El socio de logística deja de poder actualizar pedidos tras un despliegue | Se trató su API como interna: se cambió un campo sin versión ni aviso |
| Hay que cambiar una clave y se rompen tres integraciones | Una misma clave compartida entre varios clientes |
| Una respuesta de error revela rutas, consultas SQL o nombres de servidores | Los errores internos se devuelven tal cual al exterior; falta una capa que los traduzca |
| Alguien enumera `orders/1`, `orders/2`... | Identificadores secuenciales expuestos en la API pública |

## Buenas prácticas avanzadas

- **Una vista por audiencia, construida desde una lista de campos permitidos.** Partir del modelo interno y «quitar lo sensible» falla cuando alguien añade un campo nuevo: sale al exterior sin que nadie lo decida. Es más seguro que cada audiencia tenga un tipo de respuesta propio que solo incluya lo que se ha elegido exponer.
- **Alcances por operación, no por rol de empresa.** `orders:read:partner` y `orders:write:status` permiten dar al socio solo lo que hace; un único `partner:all` convierte cualquier credencial robada en acceso total.
- **Aplica el límite de uso por credencial, y devuelve `Retry-After`.** Un límite global lo agota el cliente más ruidoso; con `Retry-After`, los clientes bien escritos esperan en lugar de reintentar a ciegas.
- **Anuncia la retirada en la respuesta antes de retirar.** Pon `Deprecation` y `Sunset` en las rutas afectadas durante todo el plazo, y mide qué credenciales siguen llamando a la versión vieja para avisar a cada una antes de la fecha.
- **Los errores también pertenecen a la audiencia.** El `500` de la API pública no debe incluir trazas, consultas ni nombres de servicios; el detalle va al registro interno con un identificador de correlación que el cliente pueda citar al pedir soporte.
- **Identificadores opacos fuera, secuenciales dentro.** Un `id` secuencial público filtra el volumen de negocio y facilita enumerar recursos; la traducción se hace en la capa de exposición.

## Documentación oficial

- [Diseño de API web (Microsoft Azure Architecture Center)](https://learn.microsoft.com/en-us/azure/architecture/best-practices/api-design) — buenas prácticas de diseño de APIs REST; la sección de versionado resulta útil al fijar la política de cambios de la pública y de socios.
- [Limitación de velocidad en ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/performance/rate-limit) — los algoritmos de `AddRateLimiter` (ventana fija, ventana deslizante, cubo de fichas, concurrencia) y las particiones; consúltala al diseñar los límites por audiencia.
- [RFC 9745: The Deprecation HTTP Response Header Field](https://www.rfc-editor.org/rfc/rfc9745) — formato exacto de `Deprecation` y de la relación de enlace `deprecation`.
- [RFC 8594: The Sunset HTTP Header Field](https://www.rfc-editor.org/rfc/rfc8594) — formato de `Sunset`; categoría informativa.

---

*En resumen: la audiencia decide cuánto control tienes sobre los clientes, y de ese control dependen el modelo que expones, la credencial que pides, los límites que aplicas y el aviso que debes dar antes de cambiar nada.*
