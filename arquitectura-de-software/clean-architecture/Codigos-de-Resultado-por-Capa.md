# Códigos de Resultado por Capa

## ¿Qué es?

Un **código de resultado** es un valor, casi siempre un `enum`, que nombra **cómo terminó** una operación de la aplicación: `Confirmado`, `PedidoVacio`, `StockInsuficiente`, `PagoRechazado`. La pregunta de diseño es en qué capa de Clean Architecture vive ese enum; la respuesta es la capa de Aplicación.

## ¿Por qué existe?

Cuando un caso de uso devuelve el motivo del fallo como enum en lugar de como texto suelto, aparece la pregunta de dónde declararlo. Hay dos respuestas intuitivas, y las dos suelen estar mal:

- *«Donde nace el error»*: en Infraestructura, que es quien ve el `402` o el `429` de la pasarela de pago.
- *«Con los demás enums del negocio»*: en Dominio, junto a `EstadoPedido`.

La analogía es la de un servicio de mensajería. Las etiquetas del parte de reparto («entregado», «ausente», «dirección errónea») las define quien organiza el reparto. No las define el camión, que solo sabe que la puerta no se abrió, ni el almacén, que solo sabe qué paquetes existen. El código de resultado es el vocabulario con el que un caso de uso cuenta su desenlace a quien lo invocó; por eso pertenece a Aplicación, la capa de los [casos de uso](Casos-de-Uso.md).

> Si conoces los códigos de estado HTTP: el enum de resultado cumple el mismo papel, pero en el lenguaje del negocio y no en el del protocolo. `StockInsuficiente` dice qué pasó; `409` es cómo lo cuenta HTTP.

## ¿Cuándo y para qué se usa?

Cuando un caso de uso devuelve un desenlace tipado en lugar de lanzar excepciones para los fallos que el negocio ya prevé. `ConfirmarPedido` puede terminar en `Confirmado`, `PedidoVacio`, `StockInsuficiente` o `PagoRechazado`; cada llamador (una API HTTP, un consumidor de cola, un comando de consola) decide qué hacer con cada valor.

El patrón de devolver el resultado en el valor de retorno se explica en [Result Pattern](../patrones-de-diseno/Result-Pattern.md). La cuestión pendiente es de qué capa es el enum, quién lo produce y quién lo traduce.

## Dos respuestas intuitivas que no funcionan

La solución de ejemplo tiene cuatro proyectos: `Tienda.Dominio`, `Tienda.Aplicacion`, `Tienda.Infraestructura` y `Tienda.Api`. Cada referencia entre proyectos apunta hacia dentro, según la [Regla de Dependencia](Regla-de-Dependencia.md): Infraestructura referencia a Aplicación porque implementa sus puertos (`IPasarelaPago`, `IRepositorioPedidos`).

### En Infraestructura, «donde nace el error»

Con `ConfirmarPedidoResultado` declarado en `Tienda.Infraestructura`, el caso de uso `ConfirmarPedido` (en Aplicación) necesita nombrar el enum en su firma. Para eso Aplicación tendría que referenciar a Infraestructura, y Infraestructura ya referencia a Aplicación:

```text
Tienda.Aplicacion ──► Tienda.Infraestructura
        ▲                      │
        └──────────────────────┘
```

`dotnet build` lo rechaza antes de compilar nada (salida real, SDK en español):

```text
NuGet.targets(1298,5): error MSB4006: Existe una dependencia circular en el gráfico de
dependencias de destino en la que está involucrado el destino "_GenerateRestoreProjectPathWalk".
```

El mensaje habla de «destino» de MSBuild y no de proyectos, pero el origen es siempre el mismo: dos `ProjectReference` que se apuntan entre sí. No hay arreglo que conserve el diseño; el enum no puede estar en un proyecto que depende del que lo usa.

### En Dominio, «con los demás enums»

Con el enum en `Tienda.Dominio` todo compila, y ese es el problema: el error no es de compilador sino de significado. `Pedido` no sabe qué es una pasarela de pago ni que existe una API, pero el enum nombraría `PagoRechazado` y `ProveedorNoDisponible`: vocabulario de colaboradores externos dentro del núcleo. Además, cada desenlace nuevo de un caso de uso (por ejemplo, `LimiteDiarioSuperado`) obligaría a modificar y versionar el Dominio, que debería cambiar solo cuando cambian las reglas del negocio.

## Enum de dominio frente a enum de resultado

La confusión viene de que los dos son `enum`. La pregunta que los separa es si el valor describe a una entidad o a una operación:

| | Enum de dominio | Enum de resultado |
|---|---|---|
| Representa | *Qué es* algo: un concepto intrínseco del negocio | *Cómo terminó* una operación |
| Ejemplo | `EstadoPedido { Borrador, Confirmado, Pagado, Cancelado }` | `ConfirmarPedidoResultado { Confirmado, PedidoVacio, StockInsuficiente, ... }` |
| Capa | Dominio | Aplicación |
| Quién lo usa | Las entidades (`Pedido.Estado`) y cualquier capa externa que las lea | El caso de uso que lo produce y quien lo invoca |
| Persiste | Sí: forma parte del estado de la entidad | No: existe mientras dura la llamada |
| Pregunta de control | «¿Lo guardaría en la base de datos?» → sí | «¿Lo guardaría en la base de datos?» → no |

`Confirmado` aparece en ambos enums con significados distintos: en `EstadoPedido` es un estado en el que el pedido *está*; en `ConfirmarPedidoResultado` es un desenlace que *ocurrió* en esta llamada. Son tipos distintos a propósito: acoplarlos haría que añadir `PagoRechazado` a uno obligara a decidir qué significa en el otro.

## El recorrido completo en tres capas

El enum de resultado se traduce dos veces: los errores crudos del exterior se traducen **hacia** él en Infraestructura, y él se traduce **desde** él al protocolo en la capa web. Esta doble traducción es lo que mantiene al caso de uso ignorante de HTTP y de la pasarela concreta.

```text
Tienda.Infraestructura ──► Tienda.Aplicacion (enum) ◄── Tienda.Api
   traduce HACIA el enum          ▲                    traduce DESDE el enum
   (HttpRequestException → …)     │                    (enum → 200/409/402 …)
                           Tienda.Dominio
```

### Aplicación: el enum y el caso de uso

Un `Resultado<TValor, TDesenlace>` mínimo, propio, sin paquetes:

```csharp
// Tienda.Aplicacion
public readonly record struct Resultado<TValor, TDesenlace>(TValor? Valor, TDesenlace Desenlace)
    where TDesenlace : struct, Enum
{
    public static Resultado<TValor, TDesenlace> Ok(TValor valor, TDesenlace ok) => new(valor, ok);
    public static Resultado<TValor, TDesenlace> Fallo(TDesenlace motivo) => new(default, motivo);
}
```

El enum, el puerto de cobro y el caso de uso viven en el mismo proyecto:

```csharp
// Tienda.Aplicacion
public enum ConfirmarPedidoResultado
{
    Confirmado, NoEncontrado, PedidoVacio, StockInsuficiente, PagoRechazado, ProveedorNoDisponible
}

public enum ResultadoCobro { Cobrado, Rechazado, ProveedorNoDisponible }

public interface IPasarelaPago
{
    Task<ResultadoCobro> Cobrar(int pedidoId, decimal importe);
}

public class ConfirmarPedido(IRepositorioPedidos repositorio, IPasarelaPago pasarela)
{
    public async Task<Resultado<Pedido, ConfirmarPedidoResultado>> Ejecutar(int pedidoId)
    {
        var pedido = await repositorio.ObtenerPorId(pedidoId);
        if (pedido is null) return Fallo(ConfirmarPedidoResultado.NoEncontrado);
        if (pedido.EstaVacio) return Fallo(ConfirmarPedidoResultado.PedidoVacio);
        if (!await repositorio.ReservarStock(pedido)) return Fallo(ConfirmarPedidoResultado.StockInsuficiente);

        var cobro = await pasarela.Cobrar(pedido.Id, pedido.Total);
        if (cobro != ResultadoCobro.Cobrado)
            return Fallo(cobro == ResultadoCobro.Rechazado
                ? ConfirmarPedidoResultado.PagoRechazado
                : ConfirmarPedidoResultado.ProveedorNoDisponible);

        pedido.MarcarPagado();
        await repositorio.Guardar(pedido);
        return Resultado<Pedido, ConfirmarPedidoResultado>.Ok(pedido, ConfirmarPedidoResultado.Confirmado);
    }

    private static Resultado<Pedido, ConfirmarPedidoResultado> Fallo(ConfirmarPedidoResultado motivo)
        => Resultado<Pedido, ConfirmarPedidoResultado>.Fallo(motivo);
}
```

`ResultadoCobro` es el vocabulario del puerto `IPasarelaPago`: dice cómo terminó *cobrar*, y el caso de uso lo convierte en su propio desenlace. Tener un enum por puerto evita que el adaptador tenga que conocer los desenlaces de un caso de uso concreto. Las reglas de negocio (`EstaVacio`, `MarcarPagado`) están en `Pedido`; ver [Capa de Dominio](Capa-de-Dominio.md).

### Infraestructura: traducir hacia el enum

El adaptador de la pasarela es el único que ve los códigos del proveedor. Su trabajo es convertirlos al vocabulario del puerto antes de que crucen la frontera:

```csharp
// Tienda.Infraestructura
public class PasarelaPagoHttp(HttpClient http) : IPasarelaPago
{
    public async Task<ResultadoCobro> Cobrar(int pedidoId, decimal importe)
    {
        try
        {
            var respuesta = await http.PostAsJsonAsync("cobros", new { pedidoId, importe });
            respuesta.EnsureSuccessStatusCode();
            return ResultadoCobro.Cobrado;
        }
        catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.PaymentRequired)
        {
            return ResultadoCobro.Rechazado;                   // 402: el banco dijo que no
        }
        catch (HttpRequestException ex) when (
            ex.StatusCode is HttpStatusCode.TooManyRequests or >= HttpStatusCode.InternalServerError or null)
        {
            return ResultadoCobro.ProveedorNoDisponible;       // 429, 5xx o sin respuesta
        }
        catch (TaskCanceledException)                          // tiempo de espera agotado
        {
            return ResultadoCobro.ProveedorNoDisponible;
        }
    }
}
```

El `402` es un rechazo del negocio: el pago no se hizo y reintentar no ayuda. El `429`, los `5xx` y el timeout dicen que *no se sabe* si el cobro se haría: son indisponibilidad del proveedor, y por eso el `429` no se traduce a `Rechazado`. Cualquier otro 4xx (un `400` por un cuerpo mal formado, un `401` por una clave caducada) no está cubierto: es un bug de integración y se propaga como excepción. Los detalles de esta traducción están en [Capa de Infraestructura](Capa-de-Infraestructura.md).

### Api: traducir desde el enum

El endpoint de `Tienda.Api` convierte el desenlace en un estado HTTP y en un cuerpo de error. `Results.Problem` produce un *problem details* ([RFC 9457](https://www.rfc-editor.org/rfc/rfc9457.html)), el formato estándar de cuerpo de error en HTTP:

```csharp
// Tienda.Api
app.MapPost("/pedidos/{id:int}/confirmar", async (int id, ConfirmarPedido confirmar) =>
{
    var r = await confirmar.Ejecutar(id);
    return r.Desenlace switch
    {
        ConfirmarPedidoResultado.Confirmado            => Results.Ok(new { r.Valor!.Id, Estado = r.Valor.Estado.ToString() }),
        ConfirmarPedidoResultado.NoEncontrado          => Problema(404, "El pedido no existe"),
        ConfirmarPedidoResultado.PedidoVacio           => Problema(422, "El pedido no tiene líneas"),
        ConfirmarPedidoResultado.StockInsuficiente     => Problema(409, "No hay stock suficiente"),
        ConfirmarPedidoResultado.PagoRechazado         => Problema(402, "La pasarela rechazó el pago"),
        ConfirmarPedidoResultado.ProveedorNoDisponible => Problema(503, "La pasarela de pago no está disponible"),
    };
});

static IResult Problema(int estado, string titulo) => Results.Problem(statusCode: estado, title: titulo);
```

Un controlador con `[ApiController]` hace lo mismo con `StatusCode(...)` o `Problem(...)`; el `switch` es idéntico. Esta es la única capa que conoce los números.

### Salida real

Comprobado con un test de integración (`WebApplicationFactory`, con la pasarela sustituida por un manejador HTTP falso que responde `402` para #4714 y no responde para #4715):

| Llamada `POST /pedidos/{id}/confirmar` | Situación | Respuesta |
|---|---|---|
| `/pedidos/4711/confirmar` | Pedido válido, con stock, cobro correcto | `200` `{"id":4711,"estado":"Pagado"}` |
| `/pedidos/4712/confirmar` | Pedido sin líneas | `422` `"El pedido no tiene líneas"` |
| `/pedidos/4713/confirmar` | Una línea sin stock | `409` `"No hay stock suficiente"` |
| `/pedidos/4714/confirmar` | La pasarela responde `402` | `402` `"La pasarela rechazó el pago"` |
| `/pedidos/4715/confirmar` | La pasarela no responde | `503` `"La pasarela de pago no está disponible"` |
| `/pedidos/9999/confirmar` | El pedido no existe | `404` `"El pedido no existe"` |

Cuerpo de un fallo (el caso del stock), tal como lo emite ASP.NET Core:

```json
{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.10","title":"No hay stock suficiente","status":409,"traceId":"00-fdc8f3a8..."}
```

## Excepción o desenlace tipado

No todo fallo es un desenlace. El criterio es si quien llama puede y debe reaccionar de forma distinta ante él:

| Situación | Forma | Motivo |
|---|---|---|
| Pedido vacío, stock insuficiente, pago rechazado | Desenlace tipado | Fallo esperado del negocio: el llamador lo trata como parte del flujo |
| Pedido que no existe | Desenlace tipado (`NoEncontrado`) | Ocurre con datos de usuario; no es un bug |
| Pasarela caída o con timeout | Desenlace tipado (`ProveedorNoDisponible`) si el llamador puede reaccionar | Reintentar, encolar o avisar a quien compra son decisiones del caso de uso o de quien lo invoca |
| Pasarela caída y nadie puede hacer nada distinto | Excepción | Sube hasta el manejador global y acaba en `500` |
| `NullReferenceException`, 401 de la clave de la pasarela | Excepción | Bug o configuración rota: no hay reacción de negocio posible |
| Violación de un invariante del dominio | Excepción (`ReglaDeNegocioException` u otra) | Nunca debería ocurrir si el caso de uso comprueba antes |

La ficha [Clean Architecture](Clean-Architecture.md) muestra `ConfirmarPedido` señalando los fallos con una `ReglaDeNegocioException`; la ficha [Casos de Uso](Casos-de-Uso.md) lo muestra devolviendo un `ConfirmarPedidoResultado`. Ambas opciones son válidas y se elige por proyecto, no por capa:

- **Excepción de negocio**: el caso de uso es más corto y la API la captura en un único manejador. Encaja cuando cada fallo se traduce igual (siempre `409`, siempre `422`) y hay un solo llamador.
- **Desenlace tipado**: el compilador obliga a decidir qué hacer con cada fallo, y el caso de uso se reutiliza desde una API, una cola o un comando sin que cada uno capture excepciones. Encaja cuando hay varios llamadores o fallos con tratamientos distintos.

Lo que no conviene es mezclar ambas para el mismo fallo: quien llama tendría que protegerse con `try/catch` y con un `switch` a la vez.

## Diseñar el enum

**Granularidad.** Un enum por caso de uso (`ConfirmarPedidoResultado`, `CancelarPedidoResultado`), no un `ErrorCode` global. Quien invoca `CancelarPedido` solo debe ver los desenlaces de cancelar: `PedidoYaPagado` no tiene sentido al confirmar, y un enum compartido obligaría a cada `switch` a decidir qué hacer con valores imposibles.

**Nombre por motivo de negocio, no por protocolo.** `NoEncontrado`, no `NotFound404`; `PagoRechazado`, no `Error402`. Un valor que lleva el número de HTTP ata Aplicación a la web, y el día que el mismo caso de uso se invoque desde una cola, `404` no significa nada.

**Valores sin números.** No declares `NoEncontrado = 404`. Aunque compile, invita a hacer `(int)resultado.Desenlace` para responder y reintroduce HTTP por la puerta de atrás.

**Enum compartido entre módulos.** Si dos módulos de la aplicación necesitan el mismo desenlace, la tentación es subirlo a un proyecto común. Primero comprueba que el desenlace es de verdad el mismo concepto; si no, cada módulo conserva el suyo. Si lo es, va a un proyecto compartido de Aplicación, nunca al Dominio compartido. El criterio de qué se comparte y qué no está en [Módulos frente a Shared](Modulos-vs-Shared.md).

## Errores frecuentes

| Síntoma | Causa | Arreglo |
|---|---|---|
| Un `switch` sobre `HttpStatusCode` o un `StatusCode(409)` dentro de `ConfirmarPedido` | La traducción a protocolo se coló en Aplicación | Devolver el desenlace; el `switch` va en `Tienda.Api` |
| Un `ErrorCode` de 80 valores en un proyecto común y cada `switch` ignora la mitad | Enum global en lugar de uno por caso de uso | Un enum por caso de uso, solo con sus desenlaces |
| `enum Resultado { NotFound = 404, Conflict = 409 }` | HTTP dentro del vocabulario de negocio | Nombres de negocio; los números se asignan en el borde |
| `HttpRequestException` o `SqlException` llegan al endpoint y salen como `500` | El adaptador deja escapar la excepción cruda | Capturarla en el adaptador y devolver el desenlace del puerto |
| Se añade `PedidoYaPagado` al enum y el endpoint responde `500` sin avisar | Un `_ => StatusCode(500)` oculta el valor nuevo sin mapear | `switch` sin descarte (`_`) y CS8509 como error |
| Error `MSB4006` de dependencia circular al compilar | El enum se declaró en un proyecto exterior (Infraestructura) | Moverlo a Aplicación |

### Hacer que el compilador avise de un desenlace nuevo

Un `switch` expression sin rama `_` es exhaustivo sobre el enum. Con CS8509 elevado a error, añadir un valor al enum rompe la compilación de cada `switch` que no lo trate:

```xml
<!-- Tienda.Api.csproj -->
<PropertyGroup>
  <WarningsAsErrors>CS8509</WarningsAsErrors>
</PropertyGroup>
```

Al añadir `PedidoYaPagado` a `ConfirmarPedidoResultado` sin tocar el endpoint, `dotnet build` falla (salida real):

```text
Program.cs(15,24): error CS8509: La expresión switch no controla todos los valores posibles de su
tipo de entrada (no es exhaustivo). Por ejemplo, el patrón
"Tienda.Aplicacion.ConfirmarPedidoResultado.PedidoYaPagado" no está incluido.
```

Sin esa configuración CS8509 es solo un aviso. CS8524 (valores sin nombre del enum, como `(ConfirmarPedidoResultado)6`) aparece también como aviso, pero no se eleva a error: no tiene arreglo razonable sin una rama `_`. El descarte `_ => 500` quita ambos avisos y por eso es el error frecuente de la tabla anterior.

## Buenas prácticas avanzadas

- **Una frase de negocio por valor.** Si un valor no se puede explicar sin nombrar un código HTTP, una tabla de la base de datos o un proveedor, está en el nivel equivocado. `PagoRechazado` se explica solo; `Error402DeLaPasarela` no.
- **Un desenlace nuevo se mapea en el mismo cambio que lo introduce.** Con CS8509 como error no hay otra opción, y evita el estado intermedio en el que producción responde `500` porque nadie recordó actualizar el endpoint.
- **Traduce en la frontera y en una sola dirección por adaptador.** El adaptador de salida (`PasarelaPagoHttp`) solo traduce *hacia* el vocabulario de Aplicación; el de entrada (el endpoint) solo traduce *desde* él. Si el mismo adaptador hace las dos, está haciendo de caso de uso.
- **Los desenlaces tipados solo cubren lo que el llamador puede tratar.** Un 401 de la pasarela por clave caducada no es un desenlace de `ConfirmarPedido`: es una configuración rota que debe verse como excepción y alertar.
- **Un test por valor del enum en el endpoint.** La tabla de salida real de arriba es ese test: confirma que cada desenlace llega al cliente con el estado esperado y no se pierde en un `500`.

## Documentación oficial

- [RFC 9457: Problem Details for HTTP APIs](https://www.rfc-editor.org/rfc/rfc9457.html): formato estándar del cuerpo de error. Consúltalo al definir `type`, `title` y `status` en las respuestas de fallo.
- [Controlar errores en minimal APIs (Microsoft Learn)](https://learn.microsoft.com/es-es/aspnet/core/fundamentals/minimal-apis/handle-errors): `AddProblemDetails`, `Results.Problem` y el manejador global de excepciones. Útil al decidir qué ocurre con lo que *no* es un desenlace.
- [Pruebas de integración en ASP.NET Core (Microsoft Learn)](https://learn.microsoft.com/es-es/aspnet/core/test/integration-tests): `WebApplicationFactory` y cómo sustituir servicios por falsos. Ve a él para reproducir la tabla de salida real.
- [Advertencias de coincidencia de patrones, CS8509 y CS8524 (Microsoft Learn)](https://learn.microsoft.com/es-es/dotnet/csharp/language-reference/compiler-messages/pattern-matching-warnings): significado exacto de cada aviso de exhaustividad.

## Recursos didácticos

- [http.cat](https://http.cat/): cada código de estado HTTP ilustrado con un gato. Útil para fijar a qué estado se traduce cada desenlace (`404`, `409`, `422`, `402`) al escribir el `switch` de la capa web.

---

*En resumen: el enum que nombra cómo terminó una operación es vocabulario del caso de uso y vive en Aplicación; Infraestructura traduce hacia él, la web traduce desde él, y un `switch` sin descarte hace que el compilador avise cuando aparece un desenlace sin mapear.*
