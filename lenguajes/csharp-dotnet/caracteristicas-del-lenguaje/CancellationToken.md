# CancellationToken

## ¿Qué es?

`CancellationToken` es el mecanismo de .NET para avisar a una operación en marcha de que ya nadie espera su resultado. Funciona por **cooperación**: quien quiere cancelar activa una señal y cada método que la recibe decide, comprobándola o pasándosela a otra llamada, cuándo parar.

## ¿Por qué existe?

En la tienda, el cliente pulsa «Confirmar pedido», el servidor empieza `ConfirmarPedido` (leer el pedido #4711, llamar a la pasarela de pago, notificar, guardar) y a los dos segundos el cliente cierra la pestaña. Sin mecanismo de cancelación, el servidor ejecuta el resto de la operación para nadie: consume conexiones de base de datos, hilos y llamadas a la pasarela mientras la respuesta se descarta.

El contraste, con un servidor mínimo de ASP.NET Core y `curl -m 1` (el cliente abandona al segundo):

```csharp
// ❌ Sin token: el endpoint no sabe que el cliente se fue
app.MapGet("/sin-token", async () =>
{
    for (var paso = 1; paso <= 5; paso++)
    {
        await Task.Delay(500);
        Log.Marca("sin-token", $"paso {paso}/5 completado");
    }
    return Results.Ok("confirmado");
});

// ✅ Con token: ASP.NET Core rellena el parámetro
app.MapGet("/con-token", async (CancellationToken ct) =>
{
    for (var paso = 1; paso <= 5; paso++)
    {
        await Task.Delay(500, ct);
        Log.Marca("con-token", $"paso {paso}/5 completado");
    }
    return Results.Ok("confirmado");
});
```

```text
10:59:01.260 [sin-token   ] paso 1/5 completado
10:59:01.782 [sin-token   ] paso 2/5 completado
10:59:02.292 [sin-token   ] paso 3/5 completado      ← el cliente se fue hace más de un segundo
10:59:02.807 [sin-token   ] paso 4/5 completado
10:59:03.307 [sin-token   ] paso 5/5 completado
10:59:03.331 [middleware  ] /sin-token termina: status=200, RequestAborted=True

10:59:06.228 [con-token   ] paso 1/5 completado
10:59:06.728 [con-token   ] paso 2/5 completado
10:59:06.729 [middleware  ] /con-token termina: status=200, RequestAborted=True
```

Sin token, la petición abandonada completa los cinco pasos. Con token, el `Task.Delay` pendiente lanza una excepción en cuanto el cliente se va y el resto del trabajo no empieza. Las salidas provienen de un servidor de prueba con .NET 10 (`dotnet 10.0.401`), ejecutado el 2026-11-09.

> Piensa en el testigo de una carrera de relevos: cada método `async` recibe el `CancellationToken` como quien recibe el testigo y se lo pasa al siguiente corredor. Si alguien se queda el testigo y no lo pasa, el aviso de «parad» no llega más allá de ese punto.

## ¿Cuándo y para qué se usa?

En cualquier método `async` que haga E/S y pueda tardar: una consulta a base de datos, una llamada HTTP, la lectura de un fichero grande, el bucle de un proceso por lotes. También para imponer tiempos límite propios y para parar de forma ordenada los servicios en segundo plano cuando la aplicación se apaga.

## Los tres tipos

La cancelación reparte tres papeles en tres tipos distintos:

| Tipo | Papel | Qué hace |
|---|---|---|
| `CancellationTokenSource` | Quien cancela | Crea el token y expone `Cancel()` y `CancelAfter(...)`. Es `IDisposable`. |
| `CancellationToken` | Quien escucha | `struct` que se pasa de método en método. Solo se puede leer: `IsCancellationRequested`, `ThrowIfCancellationRequested()`, `Register(...)`. |
| `OperationCanceledException` | El resultado | Lo que lanza una operación que se detiene por cancelación. |

```csharp
using var cts = new CancellationTokenSource();
cts.Cancel();
cts.Token.ThrowIfCancellationRequested();   // lanza OperationCanceledException: The operation was canceled.
```

Como `CancellationToken` es un `struct`, copiarlo es barato y todas las copias comparten el mismo origen: cancelar el `CancellationTokenSource` cancela todas. Un token que no viene de ningún origen (`default` o `CancellationToken.None`) nunca se cancela: `CanBeCanceled` es `false` y `default(CancellationToken) == CancellationToken.None` es `true` (comprobado el 2026-11-09).

## La cancelación es cooperativa

Nada detiene un hilo a la fuerza. Cancelar el origen solo cambia el valor de `IsCancellationRequested`; el trabajo para si alguien lo comprueba. Dos bucles idénticos sobre seis lotes de 200 ms con el token cancelado a los 500 ms, uno sin comprobar y otro comprobando al inicio de cada vuelta:

```csharp
static void Trabajo(string nombre, int lotes, CancellationToken ct, bool comprueba)
{
    for (var i = 1; i <= lotes; i++)
    {
        if (comprueba) ct.ThrowIfCancellationRequested();
        Thread.Sleep(200);
        Console.WriteLine($"  [{nombre}] lote {i} procesado");
    }
}
```

```text
--- sin comprobación
  [sin comprobación] lote 1 procesado
  ...                                     (los seis lotes)
  [sin comprobación] lote 6 procesado
  terminó normalmente en 1234 ms
--- con comprobación
  [con comprobación] lote 1 procesado
  [con comprobación] lote 2 procesado
  [con comprobación] lote 3 procesado
  OperationCanceledException tras 611 ms
```

Las APIs asíncronas de .NET (`Task.Delay`, `HttpClient`, EF Core, `Stream`...) ya comprueban el token por dentro. El código propio de CPU o síncrono necesita `ct.ThrowIfCancellationRequested()` en los puntos donde sea seguro parar, normalmente al inicio de cada iteración.

## De extremo a extremo: el token recorre la cadena

El token solo sirve si llega a la operación que espera. En ASP.NET Core nace en la petición y baja por cada capa:

```csharp
// Tienda.Api: el parámetro CancellationToken se enlaza con HttpContext.RequestAborted
app.MapPost("/pedidos/{id:int}/confirmar", async (int id, ConfirmarPedido caso, CancellationToken ct) =>
{
    await caso.EjecutarAsync(id, ct);
    return Results.Ok($"pedido #{id} confirmado");
});
```

Un controlador con `[ApiController]` recibe el token igual, como parámetro de la acción; en cualquier punto con `HttpContext` está disponible como `HttpContext.RequestAborted`. Dentro de un endpoint mínimo se comprobó que ambos son el mismo token (`ct == ctx.RequestAborted` devuelve `True`).

El caso de uso lo recibe y lo pasa a cada eslabón (en la prueba, EF Core con SQLite, un `HttpClient` hacia una pasarela simulada y un `Task.Delay` que representa la notificación):

```csharp
// Tienda.Aplicacion (abreviado: db, http y los logs son los de la prueba)
public async Task EjecutarAsync(int id, CancellationToken ct)
{
    Log.Marca("caso-de-uso", $"inicio confirmación #{id}");

    var pedidos = await db.Pedidos.Where(p => p.Id == id).ToListAsync(ct);
    Log.Marca("repositorio", $"pedido leído ({pedidos.Count})");

    await http.CreateClient("pasarela").PostAsync("/pasarela/lenta?ms=3000", null, ct);
    Log.Marca("http", "pasarela respondió");

    await Task.Delay(500, ct);
    Log.Marca("notificador", "cliente notificado");

    pedidos[0].Estado = "Confirmado";
    await db.SaveChangesAsync(ct);
    Log.Marca("repositorio", "pedido guardado");
}
```

Con la pasarela tardando 3 s y el cliente abandonando a 1 s (`curl -m 1 -X POST .../pedidos/4711/confirmar`):

```text
10:59:08.823 [caso-de-uso ] inicio confirmación #4711
10:59:09.202 [repositorio ] pedido leído (1)
10:59:09.820 [pasarela    ] petición lenta cancelada
10:59:09.820 [middleware  ] /pasarela/lenta termina: status=200, RequestAborted=True
10:59:09.835 [middleware  ] /pedidos/4711/confirmar termina: status=200, RequestAborted=True
```

La cadena se corta en la llamada HTTP: nunca aparecen «cliente notificado» ni «pedido guardado». Además, el `HttpClient` cancelado cerró su conexión y la pasarela (que sí recibe el token en su endpoint) también abortó su trabajo. Si un solo eslabón no recibiera el token, el resto de la cadena seguiría trabajando, como en el contraste inicial.

Con el cliente esperando hasta el final, la misma cadena termina en «pedido guardado» a los ~3,6 s.

## Pasar siempre el token

La regla: si un método asíncrono puede recibir un `CancellationToken`, recíbelo y pásalo. En las firmas, como último parámetro:

```csharp
public Task<Pedido?> ObtenerAsync(int id, CancellationToken ct = default);
```

`= default` evita obligar a quien llama a inventar un token y equivale a `CancellationToken.None`: «no se puede cancelar». Conviene limitarlo a las firmas públicas de librerías y a los puntos de entrada (un `Main`, una prueba). En las capas internas de la aplicación, que se llaman siempre desde un endpoint con token, un parámetro obligatorio hace que olvidarse de pasarlo sea un error de compilación y no un fallo silencioso en producción. El caso de uso que recibe el token se describe en [Casos de uso](../../../arquitectura-de-software/clean-architecture/Casos-de-Uso.md).

## OperationCanceledException frente a TaskCanceledException

`TaskCanceledException` hereda de `OperationCanceledException` (comprobado: `typeof(OperationCanceledException).IsAssignableFrom(typeof(TaskCanceledException))` es `true`). Qué se lanza depende de quién cancele:

| Operación (token ya cancelado o que vence) | Excepción observada |
|---|---|
| `await Task.Delay(1000, ct)` | `TaskCanceledException` |
| `ct.ThrowIfCancellationRequested()` | `OperationCanceledException` |
| `await Task.Run(() => 1, ct)` con el token cancelado antes de empezar | `TaskCanceledException` |
| `await Task.Run(() => ct.ThrowIfCancellationRequested())` | `OperationCanceledException` |
| `HttpClient.GetAsync(url, ct)` con el token cancelado o vencido | `TaskCanceledException` |
| `HttpClient` con `Timeout` vencido | `TaskCanceledException` con `InnerException` de tipo `TimeoutException` |
| `task.Wait()` / `task.Result` sobre una tarea cancelada | `AggregateException` que contiene la anterior |

Moraleja: captura siempre `OperationCanceledException` y nunca dependas de cuál de las dos llega. Para distinguir «venció el `Timeout` del `HttpClient`» de «canceló quien llama», mira `InnerException is TimeoutException` o, mejor, usa tu propio token con tiempo límite (véase la sección siguiente).

### Cómo manejarla

La cancelación del cliente no es un fallo del sistema. Un `catch (Exception)` genérico la registra como error:

```csharp
// ❌ cada pestaña cerrada genera un error en el log
try { await caso.EjecutarAsync(id, ct); return Results.Ok(); }
catch (Exception ex) { log.LogError(ex, "Fallo al confirmar el pedido {Id}", id); return Results.Problem("error"); }
```

```text
fail: Program[0]
      Fallo al confirmar el pedido 4711
      System.Threading.Tasks.TaskCanceledException: The operation was canceled.
       ---> System.IO.IOException: Unable to read data from the transport connection: ...
      ...
10:59:15.590 [middleware  ] /pedidos/4711/confirmar-catch-exception termina: status=500, RequestAborted=True
```

Un error con traza completa por cada cliente impaciente dispara alertas falsas. El filtro `when (ct.IsCancellationRequested)` deja pasar solo las cancelaciones de la petición y no atrapa otras `OperationCanceledException` con origen distinto (un tiempo límite propio, por ejemplo):

```csharp
// ✅
try { await caso.EjecutarAsync(id, ct); return Results.Ok(); }
catch (OperationCanceledException) when (ct.IsCancellationRequested)
{
    log.LogInformation("Confirmación del pedido {Id} cancelada por el cliente", id);
    return Results.Empty;
}
```

```text
info: Program[0]
      Confirmación del pedido 4711 cancelada por el cliente
```

Tampoco hace falta capturarla para nada más: si se deja propagar, ASP.NET Core la trata sin registrar un error (con el nivel de log por defecto de la plantilla no aparece nada).

### Qué respuesta devolver cuando el cliente ya se fue

Ninguna: no hay a quién entregarla. ASP.NET Core lo registra por sí mismo. Con `Logging:LogLevel:Microsoft.AspNetCore` en `Debug` el servidor de prueba escribió:

```text
      The request was aborted by the client.
      Request finished HTTP/1.1 GET http://localhost:7381/con-token - 499 - - 993.0648ms
```

El 499 aparece solo en ese log de la petición. Dentro de un middleware propio, `HttpContext.Response.StatusCode` seguía valiendo 200 al terminar. La documentación de `StatusCodes.Status499ClientClosedRequest` lo describe como un código no oficial definido originalmente por Nginx y habitual en logs cuando el cliente se desconecta. Devolver explícitamente 499 o cualquier otro código desde el endpoint no tiene destinatario.

## Tiempos límite y varios orígenes

`new CancellationTokenSource(TimeSpan)` crea un origen que se cancela solo al vencer el plazo, y `CancelAfter(...)` programa lo mismo sobre uno existente (llamadas posteriores reinician la cuenta si todavía no se canceló). Para que una llamada se detenga cuando se va el cliente **o** cuando vence un plazo propio hace falta combinarlos con `CreateLinkedTokenSource`:

```csharp
app.MapPost("/pedidos/{id:int}/cobrar-con-limite", async (int id, IHttpClientFactory f, CancellationToken requestAborted) =>
{
    using var timeoutCts = new CancellationTokenSource(TimeSpan.FromSeconds(2));
    using var linked = CancellationTokenSource.CreateLinkedTokenSource(requestAborted, timeoutCts.Token);
    try
    {
        await f.CreateClient("pasarela").PostAsync("/pasarela/lenta?ms=5000", null, linked.Token);
        return Results.Ok("cobrado");
    }
    catch (OperationCanceledException) when (timeoutCts.IsCancellationRequested)
    {
        return Results.Problem("La pasarela tardó demasiado", statusCode: 504);
    }
    catch (OperationCanceledException) when (requestAborted.IsCancellationRequested)
    {
        return Results.Empty;   // el cliente se fue
    }
});
```

La pasarela simulada tarda 5 s. Con `curl -m 4` vence el plazo de 2 s; con `curl -m 1` se va el cliente antes:

```text
10:59:22.754 [limite      ] venció el tiempo de 2 s: la pasarela no respondió
10:59:22.754 [middleware  ] /pedidos/4711/cobrar-con-limite termina: status=504, RequestAborted=False

10:59:19.679 [limite      ] el cliente cerró la conexión
10:59:19.679 [middleware  ] /pedidos/4711/cobrar-con-limite termina: status=200, RequestAborted=True
```

Los filtros se evalúan en orden: `timeoutCts.IsCancellationRequested` solo es verdadero si venció el plazo, así que el 504 se reserva para ese caso y la desconexión del cliente no se confunde con él.

## Liberar el CancellationTokenSource

`CancellationTokenSource` es `IDisposable`; la documentación de cancelación administrada indica llamar a `Dispose` cuando se termina de usar para liberar los recursos que contiene. La razón práctica se midió con 200 000 orígenes creados y descartados sin liberar (memoria retenida tras `GC.Collect()`, .NET 10, 2026-11-09):

| Caso | Memoria retenida |
|---|---|
| `CreateLinkedTokenSource(padre.Token)` sin `Dispose` | +28 128 KB |
| El mismo con `using` | +0 KB |
| `new CancellationTokenSource(TimeSpan.FromMinutes(10))` sin `Dispose` | +28 131 KB |
| El mismo con `using` | +0 KB |

Lo más probable (explicación inferida de la medida, no leída en la documentación) es que el padre mantenga una referencia al origen enlazado y que el temporizador mantenga viva la fuente con plazo hasta que vence. Si el padre es el token de apagado de la aplicación o el plazo es largo, cada petición que olvide el `using` deja una fuente más en memoria. Tras `Dispose`, usar el origen lanza `ObjectDisposedException` (comprobado con `.Token`, `Cancel()` y `CancelAfter(...)`). Por eso el patrón es siempre `using var cts = ...`.

## Ejecutar algo al cancelar: Register

`token.Register(accion)` ejecuta una acción en el momento de la cancelación, útil para cerrar un recurso que no acepta token:

```csharp
using var cts = new CancellationTokenSource();
using var registro = cts.Token.Register(() => conexion.Cerrar());   // devuelve CancellationTokenRegistration
cts.CancelAfter(300);
await conexion.LeerAsync(cts.Token);
```

```text
  callback: cerrando conexión
  conexión cerrada
  lectura cancelada
```

`Register` devuelve un `CancellationTokenRegistration`, que es `IDisposable`: liberarlo antes de cancelar anula el registro (en la prueba el callback no se ejecutó), y conviene hacerlo en cuanto el recurso ya no importa. Registrar sobre un token que ya está cancelado ejecuta la acción en el acto, de forma síncrona.

## Servicios en segundo plano y apagado

Un `BackgroundService` recibe en `ExecuteAsync` un `stoppingToken` que se cancela cuando el host empieza a parar (Ctrl+C, `SIGTERM`, `StopApplication()`):

```csharp
public class NotificadorPedidos(ILogger<NotificadorPedidos> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var pedido = 4711;
        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                log.LogInformation("Notificando pedido #{Id}", pedido++);
                await Task.Delay(1000, stoppingToken);
            }
        }
        catch (OperationCanceledException)
        {
            log.LogInformation("Parada solicitada: se detiene el bucle");
        }
        await Task.Delay(300);   // limpieza breve que no se cancela
        log.LogInformation("Limpieza terminada");
    }
}
```

Salida real tras pulsar Ctrl+C (enviado a un proceso `Worker.exe` en consola de Windows):

```text
info: NotificadorPedidos[0]
      Notificando pedido #4716
info: Microsoft.Hosting.Lifetime[0]
      Application is shutting down...
info: NotificadorPedidos[0]
      Parada solicitada: se detiene el bucle
info: NotificadorPedidos[0]
      Limpieza terminada
```

El host espera a que los servicios terminen hasta `HostOptions.ShutdownTimeout`, cuyo valor por defecto resultó ser `00:00:30` (se imprimió `host.Services.GetRequiredService<IOptions<HostOptions>>().Value.ShutdownTimeout` con .NET 10). La documentación indica que ese plazo incluye también los servicios que implementen `StoppingAsync` y `StoppedAsync`. Un worker que ignora el `stoppingToken` retrasa el apagado hasta agotarlo; el host y su configuración se explican en [Hosts y builders](../../../desarrollo-web/de-wpf-a-web/Hosts-y-Builders.md).

## Qué no se puede deshacer

Cancelar significa «dejar de esperar y no empezar más trabajo»; no significa «deshacer». Si el cobro ya salió hacia la pasarela, cancelar el `await` no lo anula. Con una pasarela simulada que procesa el cobro durante 2 s sin mirar el token y el cliente abandonando a 1 s:

```text
10:59:23.844 [caso-de-uso ] enviando cobro del pedido #4711
10:59:23.846 [pasarela    ] cobro #4711 recibido, procesando 2 s
10:59:24.844 [caso-de-uso ] await cancelado: no sabemos si se cobró
10:59:24.844 [middleware  ] /pedidos/4711/cobrar termina: status=200, RequestAborted=True
10:59:25.859 [pasarela    ] COBRO #4711 REGISTRADO
```

El caso de uso salió con «cancelado» un segundo antes de que la pasarela registrara el cobro. Tras una cancelación en pleno envío, el sistema no sabe en qué estado quedó la operación remota. Las salidas habituales son hacer que la operación sea idempotente (una clave de idempotencia permite reintentar o consultar el resultado sin cobrar dos veces, como se explica en [REST](../../../arquitectura-de-software/tipos-de-apis/REST.md)) y compensar si es necesario (reembolsar). Por eso un paso con efectos externos irreversibles suele recibir `CancellationToken.None` o un plazo propio, y la decisión de cancelar se toma antes de empezar, no en medio.

## CancellationToken.None y sus olores

`CancellationToken.None` es la forma explícita de decir «esta operación no se cancela»: tiene sentido en un punto de entrada que no tiene ningún origen (un `Main`, una prueba) o en un paso que no debe interrumpirse (el ejemplo del cobro). Es un olor cuando aparece en medio de una cadena que sí recibe un token: rompe la propagación desde ese punto. Con un token cancelado a los 300 ms y un eslabón intermedio que usa `None`:

```csharp
async Task Eslabon(CancellationToken ct) { await Task.Delay(2000, CancellationToken.None); }
await Eslabon(cts.Token);
```

```text
Con None en medio: terminó normal tras 2010 ms (token cancelado a los 300)
```

## Código síncrono, Parallel.ForEachAsync y IAsyncEnumerable

**Código síncrono.** Se comprueba a mano (`ThrowIfCancellationRequested()`), como en el bucle de la sección sobre la cancelación cooperativa. `Task.Run(trabajo, ct)` solo evita arrancar el trabajo si el token ya está cancelado; una vez arrancado, `trabajo` tiene que comprobar el token por sí mismo. En la prueba, `Task.Run` con token cancelado a los 500 ms y un trabajo que no lo comprueba terminó normalmente a los 1270 ms con `IsCancellationRequested` en `True`.

**`Parallel.ForEachAsync`.** El token va en `ParallelOptions` y el cuerpo recibe además su propio token:

```csharp
await Parallel.ForEachAsync(pedidos,
    new ParallelOptions { CancellationToken = cts.Token, MaxDegreeOfParallelism = 2 },
    async (id, ct) => { await Task.Delay(300, ct); Console.WriteLine($"  notificado pedido #{id}"); });
```

Con 20 pedidos y cancelación a los 700 ms: se notificaron 4 (#4700 a #4703) y la llamada lanzó `TaskCanceledException`. Se atrapa con `OperationCanceledException`.

**`IAsyncEnumerable`.** En el método iterador, el parámetro lleva `[EnumeratorCancellation]`, y quien consume pasa el token con `WithCancellation`:

```csharp
static async IAsyncEnumerable<int> Pedidos([EnumeratorCancellation] CancellationToken ct = default)
{
    for (var id = 4711; ; id++) { await Task.Delay(200, ct); yield return id; }
}

await foreach (var id in Pedidos().WithCancellation(cts.Token))
    Console.WriteLine($"  leído pedido #{id}");
```

Con 700 ms de plazo se leyeron #4711, #4712 y #4713 y lanzó `TaskCanceledException`. Sin el atributo, el compilador avisa (`CS8425`: el parámetro no incluye `EnumeratorCancellation`) y el token de `WithCancellation` no llega al método: en una prueba equivalente el bucle siguió leyendo pedidos pasado el plazo.

## Cuándo no hace falta

- **Operaciones muy cortas y no cancelables:** una validación, un mapeo, una suma. Añadir el parámetro a cada método puro es ruido.
- **Código puramente en memoria:** sin E/S ni esperas, cancelar solo tiene sentido en bucles largos.
- **Trabajo que debe sobrevivir a la petición:** enviar un correo o generar un informe tras responder. Atarlo al token de la petición lo cancela en cuanto el cliente cierra la conexión; ese trabajo necesita su propio origen o un `BackgroundService`.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| El cliente se va y el servidor sigue trabajando; la base de datos o la pasarela siguen recibiendo peticiones. | Algún eslabón de la cadena no recibe o no pasa el token (el log de las capas inferiores no se detiene). |
| Cada pestaña cerrada deja un error con traza (`TaskCanceledException`) en el log. | `catch (Exception)` que trata la cancelación como fallo; usa `catch (OperationCanceledException) when (ct.IsCancellationRequested)`. |
| La aplicación se bloquea al cancelar o se envuelve la excepción en `AggregateException`. | `.Result` o `.Wait()` sobre una tarea; usa `await`. |
| Memoria que crece con el tiempo en un servicio con plazos o orígenes enlazados. | `CancellationTokenSource` sin `Dispose` (véase la tabla de memoria). |
| `Task.Run(trabajo, ct)` y el trabajo termina entero a pesar de cancelar. | El token solo evita el arranque; `trabajo` no lo comprueba. |
| Se cancela y la operación remota se completa igualmente (cobro registrado). | Se canceló tras iniciar una operación no cancelable: cancelar el `await` no deshace lo ya enviado. |
| Se cancela y el paso intermedio termina entero. | `CancellationToken.None` en medio de la cadena. |
| `CS8425` y el bucle `await foreach` no se detiene. | Falta `[EnumeratorCancellation]` en el iterador asíncrono. |

## Buenas prácticas avanzadas

- **Distingue quién canceló.** Con orígenes enlazados, `timeoutCts.IsCancellationRequested` frente a `requestAborted.IsCancellationRequested` decide si se responde 504 o no se responde nada.
- **Un filtro, no un `catch` ciego.** `when (ct.IsCancellationRequested)` evita tragarse cancelaciones de otro origen (por ejemplo, un `HttpClient.Timeout` interno).
- **Todo `CancellationTokenSource` con `using`,** y todo `Register` con su `Dispose` cuando el recurso deje de importar.
- **No encadenes el trabajo diferido al token de la petición.** Pasa el trabajo a una cola o a un `BackgroundService` con su propio ciclo de vida.
- **Cancelar antes de empezar, no en medio, los pasos con efectos externos.** Comprueba `ct.ThrowIfCancellationRequested()` antes de enviar el cobro y no después; en el resto, idempotencia y compensación.
- **En servicios en segundo plano, comprueba el `stoppingToken` en cada espera** y mantén la limpieza dentro del `ShutdownTimeout`.

## Documentación oficial

- [Cancelación en subprocesos administrados](https://learn.microsoft.com/dotnet/standard/threading/cancellation-in-managed-threads): el modelo cooperativo, los tres tipos y el patrón general. Para ver cómo se reparten los papeles y qué se pide que se libere con `Dispose`.
- [Cancelación de tareas](https://learn.microsoft.com/dotnet/standard/parallel-programming/task-cancellation): cancelación con `Task` y sus excepciones. Para el caso de código basado en tareas.
- [`StatusCodes.Status499ClientClosedRequest`](https://learn.microsoft.com/dotnet/api/microsoft.aspnetcore.http.statuscodes.status499clientclosedrequest): origen y uso del 499, para quien quiera confirmar que no es un código estándar.
- [Servicios en segundo plano con `BackgroundService`](https://learn.microsoft.com/dotnet/core/extensions/workers): el `stoppingToken` y el ciclo de vida de un worker.

---
*En resumen: cancelar es avisar con un testigo que cada eslabón debe recibir, comprobar y pasar; significa «dejar de esperar y no empezar más», nunca «deshacer lo hecho».*
