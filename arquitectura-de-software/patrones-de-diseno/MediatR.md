# MediatR

## ¿Qué es?

MediatR es una librería de .NET que implementa el patrón [Mediator](Mediator.md) dentro de un proceso: se define un *mensaje* (un objeto con los datos de lo que se quiere hacer), se envía a un mediador y este lo entrega al *handler* (manejador) que sabe procesarlo. Añade además un *pipeline* de *behaviors*, piezas que envuelven a todos los mensajes para aplicar lógica transversal.

## ¿Por qué existe?

Cuando un endpoint necesita ejecutar un caso de uso, lo natural es inyectar la clase concreta y llamarla. Con diez casos de uso, el constructor del controlador arrastra diez dependencias; y cada necesidad transversal (registrar la duración, validar, abrir una transacción) se repite en cada caso de uso o exige un decorador por cada uno. MediatR cambia la relación: el endpoint solo conoce el mensaje y el mediador, el mediador localiza al handler por el tipo del mensaje, y lo transversal se escribe una vez en el pipeline.

> Piensa en la recepcionista de una oficina grande: no buscas despacho por despacho a quien resuelve tu gestión; entregas la solicitud en recepción y ella sabe a qué departamento enviarla. Los *behaviors* son los controles por los que pasa toda solicitud antes de llegar al departamento (registro de entrada, comprobación de documentos), sin que cada departamento tenga que repetirlos.

El patrón en sí (qué problema resuelve, cuándo conviene y cómo sería un mediador mínimo escrito a mano) se desarrolla en [Mediator](Mediator.md). Aquí se trata la herramienta: instalación, tipos de mensaje, pipeline, errores y pruebas.

## ¿Cuándo y para qué se usa?

- **Endpoints delgados**: cada endpoint hace `Send` de un mensaje y traduce el resultado a HTTP, sin conocer clases de aplicación.
- **Lo transversal en un único sitio**: logging, validación y transacción para todos los comandos sin tocar ningún handler.
- **Varias reacciones a un hecho**: una notificación (`Publish`) con N handlers dentro del mismo proceso.
- **CQRS en proceso**: separar el tipo de mensaje que cambia estado del que solo lee.

No es un bus de mensajería: todo ocurre en memoria, en el mismo proceso. El mensaje no cruza la red, no se persiste y, si el proceso muere a mitad, se pierde. Para colas duraderas o comunicación entre servicios, ver [Mensajería Asíncrona](../../devops/mensajeria-asincrona/Mensajeria-Asincrona.md). Tampoco mejora el rendimiento: añade una indirección.

## Licencia y versión

Consultado el 2026-11-09 en NuGet (metadatos de los paquetes), en el repositorio de GitHub y en el `LICENSE.md` incluido en el paquete:

| Versiones | Licencia según la fuente |
|---|---|
| 12.0.0, 12.4.1, 12.5.0 (las comprobadas hasta la 12.x) | `Apache-2.0` en el campo `license` del paquete NuGet |
| 13.0.0 y posteriores (la última en NuGet al consultarlo: 14.3.0) | `LICENSE.md`: licencia *Reciprocal Public License 1.5* (RPL-1.5), o bien el *License Agreement* comercial de Lucky Penny Software |

Qué se pudo confirmar y qué no:

- El repositorio ya no está en `jbogard/MediatR`: esa URL redirige (301) a `LuckyPennySoftware/MediatR`.
- El `README` de las versiones actuales documenta una clave de licencia (`cfg.LicenseKey`, o las variables de entorno `MEDIATR_LICENSE_KEY` y `LUCKYPENNY_LICENSE_KEY`). Sin clave, con la 14.3.0 la aplicación arranca y escribe este aviso en el log (salida real):

```text
warn: LuckyPennySoftware.MediatR.License[0] You do not have a valid license key for the Lucky Penny software MediatR. This is allowed for development and testing scenarios. If you are running in production you are required to have a licensed version. Please visit https://luckypennysoftware.com to obtain a valid license.
```

- **No se pudo confirmar**: las condiciones del *License Agreement* (precios, si existe gratuidad para algún tipo de organización) porque el documento enlazado en `luckypennysoftware.com/license` es un PDF que no se pudo leer. Tampoco se evaluó qué implica RPL-1.5 para un producto concreto: es una licencia con obligación de publicar el código de lo que se construya sobre ella. Antes de adoptar la 13 o posterior en un proyecto de empresa, leer el texto de ambas licencias y consultarlo con quien corresponda.

Los ejemplos se probaron con **MediatR 12.5.0** (.NET 10): es la última versión con licencia `Apache-2.0` y no pide clave. El mismo código compila y supera las mismas pruebas con 14.3.0 (comprobado el 2026-11-09); solo cambia el aviso de licencia al arrancar.

Para quedarse en la 12 sin saltar de versión por accidente en un `dotnet restore`:

```xml
<PackageReference Include="MediatR" Version="[12.5.0]" />
```

## Instalación y registro

```text
dotnet add Tienda.Aplicacion package MediatR --version 12.5.0
```

El paquete va en el proyecto que contiene los mensajes y los handlers (`Tienda.Aplicacion`). El registro se hace una vez, indicando qué ensamblados escanear para descubrir los handlers:

```csharp
// Tienda.Aplicacion
public static IServiceCollection AñadirAplicacion(this IServiceCollection servicios)
{
    servicios.AddMediatR(cfg =>
        cfg.RegisterServicesFromAssembly(typeof(Registro).Assembly));
    return servicios;
}
```

Con la 13 o posterior y una licencia comercial, la clave se pasa en la misma llamada (en la documentación oficial también se explica cómo leerla de un almacén de secretos o de una variable de entorno):

```csharp
servicios.AddMediatR(cfg =>
{
    cfg.LicenseKey = configuracion["MediatR:LicenseKey"];
    cfg.RegisterServicesFromAssembly(typeof(Registro).Assembly);
});
```

`AddMediatR` registra `IMediator`, `ISender` e `IPublisher` (los tres, *transient*) y todos los handlers que encuentre en el ensamblado. Conviene inyectar la interfaz más estrecha: `ISender` si solo se hace `Send`, `IPublisher` si solo se hace `Publish`.

## Una petición de principio a fin

El ejemplo es confirmar el pedido #4711 de una tienda. El mensaje es un `record` que declara qué devuelve; usa el enum de resultado de la capa de Aplicación ([Códigos de Resultado por Capa](../clean-architecture/Codigos-de-Resultado-por-Capa.md)):

```csharp
// Tienda.Aplicacion
public enum ConfirmarPedidoResultado { Confirmado, NoEncontrado, PedidoVacio, PagoRechazado }

public record ConfirmarPedidoComando(int PedidoId) : IRequest<ConfirmarPedidoResultado>;
```

El handler recibe sus dependencias por constructor, como cualquier servicio. Hay exactamente un handler por petición:

```csharp
public class ConfirmarPedidoManejador(
    IRepositorioPedidos repositorio, IPasarelaPago pasarela, IPublisher publicador, TimeProvider reloj)
    : IRequestHandler<ConfirmarPedidoComando, ConfirmarPedidoResultado>
{
    public async Task<ConfirmarPedidoResultado> Handle(ConfirmarPedidoComando comando, CancellationToken ct)
    {
        var pedido = await repositorio.ObtenerPorId(new IdPedido(comando.PedidoId), ct);
        if (pedido is null) return ConfirmarPedidoResultado.NoEncontrado;
        if (pedido.Lineas.Count == 0) return ConfirmarPedidoResultado.PedidoVacio;

        var cobro = await pasarela.Cobrar(pedido.Id, pedido.Total("EUR"), ct);
        if (cobro != ResultadoCobro.Cobrado) return ConfirmarPedidoResultado.PagoRechazado;

        pedido.Confirmar(reloj.GetUtcNow());
        await repositorio.Guardar(pedido, ct);
        await publicador.Publish(new PedidoConfirmado(pedido.Id.Valor, pedido.ClienteId.Valor), ct);
        return ConfirmarPedidoResultado.Confirmado;
    }
}
```

El endpoint de `Tienda.Api` envía el mensaje y traduce el desenlace a HTTP; no conoce el handler, el repositorio ni la pasarela:

```csharp
// Tienda.Api
app.MapPost("/pedidos/{id:int}/confirmar", async (int id, ISender sender) =>
{
    var resultado = await sender.Send(new ConfirmarPedidoComando(id));
    return resultado switch
    {
        ConfirmarPedidoResultado.Confirmado => Results.Ok(new { estado = "Confirmado" }),
        ConfirmarPedidoResultado.NoEncontrado => Results.NotFound(),
        ConfirmarPedidoResultado.PedidoVacio => Results.Problem("El pedido no tiene líneas.", statusCode: 409),
        ConfirmarPedidoResultado.PagoRechazado => Results.Problem("Pago rechazado.", statusCode: 402),
        _ => Results.StatusCode(500)
    };
});
```

Salida real (la API con un repositorio en memoria, el pedido #4711 con dos líneas y el #4712 sin líneas):

```text
POST /pedidos/4711/confirmar  ->  200  {"estado":"Confirmado"}
POST /pedidos/4712/confirmar  ->  409  {"title":"Conflict","status":409,"detail":"El pedido no tiene líneas."}
POST /pedidos/999/confirmar   ->  404
```

La regla de negocio vive en `Pedido.Confirmar` ([Capa de Dominio](../clean-architecture/Capa-de-Dominio.md)) y el handler solo orquesta, igual que un [caso de uso](../clean-architecture/Casos-de-Uso.md): MediatR no cambia dónde va cada responsabilidad, solo cómo se llega al caso de uso.

## Peticiones y notificaciones

| | Petición (`IRequest<T>`) | Notificación (`INotification`) |
|---|---|---|
| Se envía con | `Send` | `Publish` |
| Handlers | Exactamente uno | Cero, uno o varios |
| Devuelve | Un valor de tipo `T` | Nada |
| Significa | «Haz esto» (imperativo) | «Esto ocurrió» (hecho) |
| Si el emisor necesita el resultado | Sí | No |

`PedidoConfirmado` es una notificación: el handler de la petición la publica y varios handlers reaccionan sin que el emisor sepa cuántos son.

```csharp
public record PedidoConfirmado(int PedidoId, int ClienteId) : INotification;

public class ReservarEnvioManejador(ILogger<ReservarEnvioManejador> log) : INotificationHandler<PedidoConfirmado>
{
    public Task Handle(PedidoConfirmado n, CancellationToken ct)
    { log.LogInformation("Envío reservado para el pedido #{Id}", n.PedidoId); return Task.CompletedTask; }
}

public class EnviarCorreoManejador(ILogger<EnviarCorreoManejador> log) : INotificationHandler<PedidoConfirmado>
{
    public Task Handle(PedidoConfirmado n, CancellationToken ct)
    { log.LogInformation("Correo enviado al cliente {Cliente}", n.ClienteId); return Task.CompletedTask; }
}
```

Al confirmar el #4711 el log muestra los dos handlers ejecutados:

```text
info: Tienda.Aplicacion.ReservarEnvioManejador[0] Envío reservado para el pedido #4711
info: Tienda.Aplicacion.EnviarCorreoManejador[0] Correo enviado al cliente 7
```

Qué es un evento de dominio y cómo se diseña (nombre en pasado, qué datos lleva, quién lo publica) está en [Domain Events](Domain-Events.md). MediatR es una forma de entregarlos dentro del proceso; la colección también muestra un publicador propio en [Módulos vs Shared](../clean-architecture/Modulos-vs-Shared.md).

### Qué pasa si un handler de notificación lanza

Con tres handlers (A, B y C) registrados para la misma notificación, y B lanzando una excepción, `Publish` se comporta así con el publicador por defecto (salida real de MediatR 12.5.0):

```text
A: ejecutado
B: lanzando
Publish lanzó InvalidOperationException: fallo en B
```

El publicador por defecto (`ForeachAwaitPublisher`) ejecuta los handlers **uno detrás de otro, en orden de registro**, y la primera excepción corta la cadena: C no llega a ejecutarse y la excepción sube a quien llamó a `Publish`. En esta prueba el orden observado fue el de declaración de las clases, pero MediatR no lo garantiza como contrato: no se debe depender de él.

Cambiando el publicador, todos los handlers arrancan, aunque alguno falle:

```csharp
cfg.NotificationPublisherType = typeof(TaskWhenAllPublisher); // using MediatR.NotificationPublishers;
```

```text
A: ejecutado
B: lanzando
C: ejecutado
Publish lanzó InvalidOperationException: fallo en B
```

`TaskWhenAllPublisher` los lanza en paralelo; la excepción sigue llegando al emisor. En la prueba, B fallaba tras un `await`; un handler que lanza de forma síncrona antes de devolver su `Task` corta el arranque de los siguientes también con este publicador. Consecuencia práctica en ambos modos: **un handler de notificación que falla hace fallar al `Publish` y, por tanto, al handler de la petición que publicó**. Si un correo caído no debe deshacer la confirmación de un pedido, el handler del correo captura sus propias excepciones, o el aviso se saca del proceso con una cola y un *outbox* ([Outbox Pattern](../../devops/mensajeria-asincrona/Outbox-Pattern.md)).

## Consultas y comandos

CQRS en proceso consiste en distinguir dos clases de mensaje: los comandos cambian estado y las consultas solo leen. Con MediatR son dos `IRequest<T>` con convenciones distintas:

```csharp
public record PedidoDto(int Id, string Estado, int Lineas, string Total);
public record ObtenerPedidoConsulta(int PedidoId) : IRequest<PedidoDto?>;

public class ObtenerPedidoManejador(IRepositorioPedidos repositorio)
    : IRequestHandler<ObtenerPedidoConsulta, PedidoDto?>
{
    public async Task<PedidoDto?> Handle(ObtenerPedidoConsulta consulta, CancellationToken ct)
    {
        var p = await repositorio.ObtenerPorId(new IdPedido(consulta.PedidoId), ct);
        return p is null ? null : new PedidoDto(p.Id.Valor, p.Estado.ToString(), p.Lineas.Count, p.Total("EUR").ToString());
    }
}
```

`GET /pedidos/4711` tras confirmarlo devuelve `{"id":4711,"estado":"Confirmado","lineas":2,"total":"44,90 EUR"}`.

| | `ConfirmarPedidoComando` | `ObtenerPedidoConsulta` |
|---|---|---|
| Cambia estado | Sí | No |
| Devuelve | Un desenlace (`ConfirmarPedidoResultado`) | Un DTO de lectura |
| Transacción | Sí (behavior solo para comandos) | No hace falta |
| Puede publicar notificaciones | Sí | No |
| Se puede repetir sin efectos | No | Sí |
| Nombre | Verbo en imperativo | `Obtener…`, `Listar…` |

Lo que **no** cambia por separarlos: no implica bases de datos separadas, ni un modelo de lectura distinto, ni consistencia eventual. Ambos handlers pueden leer del mismo repositorio y de la misma base de datos, como arriba. La separación es de intención y de política (la transacción solo envuelve a los comandos); dividir además el almacenamiento es una decisión independiente que solo compensa con cargas de lectura y escritura muy distintas.

## Pipeline behaviors

Un *behavior* implementa `IPipelineBehavior<TRequest, TResponse>` y envuelve la ejecución del handler: recibe la petición y un delegado `next` que invoca al siguiente eslabón (otro behavior o, al final, el handler). Lo que ocurre antes de `next()` es la ida; lo que ocurre después es la vuelta. Es la forma de aplicar a todos los mensajes lo que [Decorator](Decorator.md) resuelve con un decorador por interfaz.

Tres behaviors, cada uno una preocupación distinta.

**Registro con duración.** Se aplica a todas las peticiones:

```csharp
public class RegistroBehavior<TRequest, TResponse>(ILogger<RegistroBehavior<TRequest, TResponse>> log)
    : IPipelineBehavior<TRequest, TResponse> where TRequest : notnull
{
    public async Task<TResponse> Handle(TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken ct)
    {
        var nombre = typeof(TRequest).Name;
        log.LogInformation("[Registro] -> {Peticion}", nombre);
        var reloj = Stopwatch.StartNew();
        try { return await next(); }
        finally { log.LogInformation("[Registro] <- {Peticion} en {Ms} ms", nombre, reloj.ElapsedMilliseconds); }
    }
}
```

El `finally` registra la duración también cuando algo lanza.

**Validación con FluentValidation** ([FluentValidation](../../desarrollo-web/de-wpf-a-web/FluentValidation.md)). El behavior recibe todos los `IValidator<TRequest>` registrados para esa petición (cero, uno o varios) y lanza si alguno falla:

```csharp
public class ConfirmarPedidoValidador : AbstractValidator<ConfirmarPedidoComando>
{
    public ConfirmarPedidoValidador() =>
        RuleFor(c => c.PedidoId).GreaterThan(0).WithMessage("PedidoId debe ser mayor que cero.");
}

public class ValidacionBehavior<TRequest, TResponse>(
    IEnumerable<IValidator<TRequest>> validadores, ILogger<ValidacionBehavior<TRequest, TResponse>> log)
    : IPipelineBehavior<TRequest, TResponse> where TRequest : notnull
{
    public async Task<TResponse> Handle(TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken ct)
    {
        log.LogInformation("[Validacion] {Peticion}: {N} validador(es)", typeof(TRequest).Name, validadores.Count());
        var contexto = new ValidationContext<TRequest>(request);
        var fallos = (await Task.WhenAll(validadores.Select(v => v.ValidateAsync(contexto, ct))))
            .SelectMany(r => r.Errors).Where(e => e != null).ToList();
        if (fallos.Count != 0) throw new ValidationException(fallos);
        return await next();
    }
}
```

Los validadores se registran con `servicios.AddValidatorsFromAssembly(...)` (paquete `FluentValidation.DependencyInjectionExtensions`). La `ValidationException` se traduce a `400` en un middleware de la API. `POST /pedidos/0/confirmar` devuelve `400 {"errores":["PedidoId debe ser mayor que cero."]}` sin llegar al handler.

**Transacción.** Abre una unidad de trabajo, la confirma si todo va bien y la revierte si algo lanza. Solo tiene sentido para comandos, así que lleva una restricción de tipo sobre una interfaz marcadora:

```csharp
public interface IComando { }
public record ConfirmarPedidoComando(int PedidoId) : IComando, IRequest<ConfirmarPedidoResultado>;

public class TransaccionBehavior<TRequest, TResponse>(IUnidadDeTrabajo uow, ILogger<TransaccionBehavior<TRequest, TResponse>> log)
    : IPipelineBehavior<TRequest, TResponse> where TRequest : IComando
{
    public async Task<TResponse> Handle(TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken ct)
    {
        await uow.Iniciar(ct);
        log.LogInformation("[Transaccion] iniciada");
        try
        {
            var respuesta = await next();
            await uow.Confirmar(ct);
            log.LogInformation("[Transaccion] confirmada");
            return respuesta;
        }
        catch
        {
            await uow.Revertir(ct);
            log.LogInformation("[Transaccion] revertida");
            throw;
        }
    }
}
```

`IUnidadDeTrabajo` (con `Iniciar`, `Confirmar` y `Revertir`) es un puerto de `Tienda.Aplicacion`. La transacción debe cubrir el cambio de estado y la publicación de notificaciones, pero no llamadas externas no reversibles; ese límite se explica en [Casos de Uso](../clean-architecture/Casos-de-Uso.md).

### Registro, orden de registro y orden de ejecución

Los behaviors abiertos (con parámetros de tipo sin cerrar) se registran con `AddOpenBehavior`:

```csharp
servicios.AddMediatR(cfg =>
{
    cfg.RegisterServicesFromAssembly(typeof(Registro).Assembly);
    cfg.AddOpenBehavior(typeof(RegistroBehavior<,>));      // el primero registrado es el más externo
    cfg.AddOpenBehavior(typeof(ValidacionBehavior<,>));
    cfg.AddOpenBehavior(typeof(TransaccionBehavior<,>));   // solo para IComando
});
```

**El primero registrado es el más externo**: su parte «antes» se ejecuta primero y su parte «después», la última. Esta es la salida real de `POST /pedidos/4711/confirmar` seguido de un `GET /pedidos/4711`:

```text
[Registro] -> ConfirmarPedidoComando
[Validacion] ConfirmarPedidoComando: 1 validador(es)
[Transaccion] iniciada
    (handler: Envío reservado..., Correo enviado...)
[Transaccion] confirmada
[Registro] <- ConfirmarPedidoComando en 39 ms
[Registro] -> ObtenerPedidoConsulta
[Validacion] ObtenerPedidoConsulta: 0 validador(es)
[Registro] <- ObtenerPedidoConsulta en 5 ms
```

La restricción `where TRequest : IComando` funciona sin código adicional: para `ObtenerPedidoConsulta`, que no implementa `IComando`, MediatR no aplica el behavior de transacción (no aparece `[Transaccion]`). La primera llamada tarda más (39 ms frente a 5 ms) porque es la primera ejecución del proceso.

El orden importa. Registrar la validación antes que el registro con una petición inválida (`PedidoId = 0`) da:

```text
-- orden: Registro, Validacion              -- orden: Validacion, Registro
[Registro] -> ConfirmarPedidoComando        [Validacion] ConfirmarPedidoComando: 1 validador(es)
[Validacion] ...: 1 validador(es)           Llegó al llamador: ValidationException
[Registro] <- ConfirmarPedidoComando en 16 ms
Llegó al llamador: ValidationException
```

Con el segundo orden las peticiones rechazadas **no dejan rastro en el registro ni en la duración**. Con el primero se registran todas, también las inválidas. Ninguno es universalmente correcto; lo importante es decidirlo. Una guía razonable, de fuera a dentro: registro, validación, transacción. La validación va antes que la transacción para no abrir una transacción por una petición que se va a rechazar.

Dos límites de la transacción de la salida anterior: solo ve excepciones, así que un fallo de negocio devuelto como valor (`PedidoVacio`) acaba en `Confirmar` (el comando termina «bien» desde su punto de vista). Y como las notificaciones se publican dentro del handler, también quedan dentro de la transacción.

## Excepciones

Una excepción lanzada por un handler atraviesa los behaviors en sentido inverso y llega intacta a quien llamó a `Send`: MediatR no la envuelve ni la captura. Con un repositorio cuyo `Guardar` lanza `TimeoutException` (salida real):

```text
[Registro] -> ConfirmarPedidoComando
[Transaccion] iniciada
[Transaccion] revertida
[Registro] <- ConfirmarPedidoComando en 10 ms
Llegó al llamador: TimeoutException: la base de datos no responde
```

El `try/finally` del registro y el `catch` de la transacción actúan al pasar. Un behavior de captura traduce excepciones en un único sitio, por ejemplo convertir las del dominio en el desenlace de la petición. Debe ser el más externo (el primero registrado) para ver las de todos los demás:

```csharp
public class CapturaReglasBehavior<TRequest, TResponse>(ILogger<CapturaReglasBehavior<TRequest, TResponse>> log)
    : IPipelineBehavior<TRequest, TResponse> where TRequest : notnull
{
    public async Task<TResponse> Handle(TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken ct)
    {
        try { return await next(); }
        catch (ReglaDeDominioException ex)
        {
            log.LogWarning("Regla de dominio incumplida en {Peticion}: {Mensaje}", typeof(TRequest).Name, ex.Message);
            throw;   // o traducir a una respuesta, si TResponse lo permite
        }
    }
}
```

Capturar y devolver un valor solo es posible si `TResponse` puede representar el fallo (un tipo resultado, como el de [Result Pattern](Result-Pattern.md)); con un `TResponse` arbitrario, lo único seguro es registrar y relanzar. Este behavior no se ejecutó en las pruebas: el ejemplo compila, pero su comportamiento no se midió.

MediatR incluye además *exception handlers* y *exception actions* (`IRequestExceptionHandler`); se describen en su `README`.

## Probar handlers y behaviors

Un handler es una clase normal: se instancia con dobles de sus dependencias y se llama a `Handle`. No hace falta MediatR, ni contenedor, ni pipeline. Prueba completa de `ConfirmarPedidoManejador` con dobles escritos a mano (xunit):

```csharp
public class ConfirmarPedidoManejadorPruebas
{
    private static readonly DateTimeOffset Ahora = new(2026, 11, 9, 10, 0, 0, TimeSpan.Zero);

    private static Pedido PedidoConLineas()
    {
        var p = Pedido.Crear(new IdPedido(4711), new IdCliente(7), Ahora);
        p.AñadirLinea(new IdProducto(1), 2, Dinero.De(19.95m, "EUR"));
        return p;
    }

    [Fact]
    public async Task Confirma_cobra_guarda_y_publica()
    {
        var repo = new RepoFalso(PedidoConLineas());
        var pasarela = new PasarelaFalsa(ResultadoCobro.Cobrado);
        var publicador = new PublicadorFalso();
        var manejador = new ConfirmarPedidoManejador(repo, pasarela, publicador, new RelojFijo(Ahora));

        var resultado = await manejador.Handle(new ConfirmarPedidoComando(4711), CancellationToken.None);

        Assert.Equal(ConfirmarPedidoResultado.Confirmado, resultado);
        Assert.Equal(EstadoPedido.Confirmado, repo.Guardado!.Estado);
        Assert.Equal(Dinero.De(39.90m, "EUR"), pasarela.ImporteCobrado);
        Assert.Equal(new PedidoConfirmado(4711, 7), Assert.Single(publicador.Publicadas));
    }

    [Fact]
    public async Task Pedido_vacio_no_cobra_ni_publica()
    {
        var vacio = Pedido.Crear(new IdPedido(4712), new IdCliente(7), Ahora);
        var pasarela = new PasarelaFalsa(ResultadoCobro.Cobrado);
        var publicador = new PublicadorFalso();
        var manejador = new ConfirmarPedidoManejador(new RepoFalso(vacio), pasarela, publicador, new RelojFijo(Ahora));

        var resultado = await manejador.Handle(new ConfirmarPedidoComando(4712), CancellationToken.None);

        Assert.Equal(ConfirmarPedidoResultado.PedidoVacio, resultado);
        Assert.Null(pasarela.ImporteCobrado);
        Assert.Empty(publicador.Publicadas);
    }
}
```

El publicador falso implementa `IPublisher` y guarda lo publicado; `RelojFijo` es un `TimeProvider` con la hora fija. La tercera prueba (no reproducida arriba) comprueba que con `ResultadoCobro.Rechazado` el resultado es `PagoRechazado` y no se guarda nada.

Un behavior se prueba igual: se instancia y se le pasa un `next` escrito como lambda. En la 12.5.0 el delegado `RequestHandlerDelegate<TResponse>` recibe un `CancellationToken`, por eso el parámetro `_`:

```csharp
private record OrdenDePrueba : IComando, IRequest<string>;

[Fact]
public async Task Revierte_y_relanza_si_el_siguiente_eslabon_lanza()
{
    var uow = new UowFalsa();
    var behavior = new TransaccionBehavior<OrdenDePrueba, string>(
        uow, NullLogger<TransaccionBehavior<OrdenDePrueba, string>>.Instance);

    var ex = await Assert.ThrowsAsync<TimeoutException>(() =>
        behavior.Handle(new OrdenDePrueba(), _ => throw new TimeoutException("bd caída"), CancellationToken.None));

    Assert.Equal("bd caída", ex.Message);
    Assert.Equal(["Iniciar", "Revertir"], uow.Llamadas);
}
```

Resultado real de `dotnet test` con las tres pruebas del handler (confirmar, pedido vacío, pago rechazado) y las dos del behavior (confirma si todo va bien; revierte y relanza si falla):

```text
Correctas! - Con error: 0, Superado: 5, Omitido: 0, Total: 5
```

Estas pruebas no recorren el pipeline: para comprobar que los behaviors están registrados en el orden previsto hace falta una prueba de integración que construya el contenedor con `AñadirAplicacion()` y haga un `Send` (no probada aquí). Metodología de pruebas en [TDD](../../testing/tdd-bdd-sdd/TDD.md).

## MediatR frente a llamar directamente al caso de uso

La alternativa es inyectar el caso de uso (`ConfirmarPedido`) en el endpoint y llamarlo. Es la opción por defecto de [Casos de Uso](../clean-architecture/Casos-de-Uso.md); lo transversal se logra con decoradores, ver [Decorator](Decorator.md).

| Situación | Llamada directa | MediatR |
|---|---|---|
| Pocos casos de uso (menos de unos diez) | Mejor: sin indirección ni dependencia | Sobra |
| Navegación del código | «Ir a definición» llega a la clase | Del `Send` al handler hay que buscar el tipo del mensaje |
| Lo transversal (registro, validación, transacción) | Un decorador por interfaz, o un decorador genérico | Un behavior para todos |
| Varias reacciones a un hecho | Publicador propio | `Publish` ya incluido |
| Constructor del endpoint | Una dependencia por caso de uso que use | `ISender` y nada más |
| Dependencia de terceros y licencia | Ninguna | Sí; licencia RPL-1.5 o comercial desde la 13 |
| Un caso de uso llama a otro | Inyección directa, explícita | `Send` dentro de un handler: ver errores |
| Cambiar de herramienta después | Casi nada que cambiar | Mensajes y handlers atados a `IRequest`/`IRequestHandler` |

Regla práctica: con pocos casos de uso y lo transversal resuelto, la llamada directa; MediatR gana cuando hay decenas de casos de uso y se quiere un único pipeline.

### Alternativas

- **Mediador propio mínimo**: `Send`, `Publish` y handlers resueltos por el contenedor, sin paquete externo ni licencia; se describe en [Mediator](Mediator.md).
- **Librerías con la misma forma de uso** (verificado el 2026-11-09 en NuGet y GitHub; no se probaron):
  - `Mediator.SourceGenerator` (repositorio `martinothamar/Mediator`, licencia MIT en el `LICENSE` del repositorio): generador de código fuente con una API de mediador similar.
  - `WolverineFx` (repositorio `jasperfx/wolverine`, licencia `MIT` en el paquete NuGet 6.63.0): es un marco de mensajería y de manejo de comandos más amplio, no un sustituto directo.

## Errores frecuentes

| Síntoma | Causa y solución |
|---|---|
| `InvalidOperationException: No service for type 'MediatR.IRequestHandler`2[Tienda.Aplicacion.ConfirmarPedidoComando,Tienda.Aplicacion.ConfirmarPedidoResultado]' has been registered.` al hacer `Send` | El ensamblado donde viven los handlers no se pasó a `RegisterServicesFromAssembly`, o se pasó otro. Es el mensaje real que produce registrar `typeof(Program).Assembly` cuando los handlers están en `Tienda.Aplicacion`. Registrar el ensamblado correcto |
| Se ejecuta un handler distinto del esperado, sin error | Dos handlers para la misma petición. MediatR no avisa; con dos `IRequestHandler<Saludo, string>` ganó el primero registrado (`SaludoUno`) en la prueba. Debe haber exactamente uno por petición |
| Un handler de notificación no se ejecuta | Un handler anterior lanzó y, con el publicador por defecto, corta la cadena. Ver «Qué pasa si un handler de notificación lanza» |
| `Send` dentro de un handler para encadenar casos de uso | Cada `Send` interno **vuelve a recorrer todo el pipeline** (registro, validación, transacción). En la prueba con un handler que envía otra petición, el registro mostró `-> Externa`, `-> Interna`, `<- Interna`, `<- Externa`: con `TransaccionBehavior` serían dos transacciones anidadas. Para encadenar, inyectar el caso de uso o una clase de aplicación compartida, o publicar una notificación si el segundo paso es una reacción |
| La validación corre después del registro (o de otro behavior) y los rechazos no aparecen en el log, o aparecen cuando no se quería | El orden de `AddOpenBehavior` es el orden de ejecución, de fuera a dentro. Ver «Registro, orden de registro y orden de ejecución» |
| Un behavior se aplica a todo, incluidas las consultas | No tiene restricción de tipo. Añadir `where TRequest : IComando` y marcar los comandos con la interfaz |
| Una petición devuelve la entidad `Pedido` y el endpoint la serializa | Se filtran el modelo de dominio y su estado interno al exterior, y cualquier cambio de la entidad rompe el contrato de la API. Devolver un DTO (`PedidoDto`) o el enum de desenlace |
| Tras actualizar a la 13, el log avisa de falta de licencia, o la empresa no puede usar la librería | Cambio de licencia. Ver «Licencia y versión» |

## Buenas prácticas avanzadas

- **Fija la versión de forma consciente**: la licencia cambia entre la 12 y la 13. Un rango abierto en el `.csproj` puede subir de versión en un `dotnet restore`; fija la versión exacta (`[12.5.0]`) o decide a propósito pasar a la 13 o posterior.
- **Una petición, un handler, un caso de uso**: si un handler orquesta media aplicación, probablemente son varios mensajes. Un handler que llama a `Send` está pidiendo una clase de aplicación compartida.
- **El behavior de transacción solo para comandos**: usa una interfaz marcadora (`IComando`) o una restricción de tipo; abrir una transacción para una lectura es coste sin beneficio.
- **El behavior de validación va antes que el de transacción**: no se abre una transacción para una petición que se va a rechazar. Y decide con intención si los rechazos deben quedar en el registro.
- **Las notificaciones se ejecutan dentro del comando**: un handler de notificación que lanza deshace la transacción y devuelve error al llamador aunque el cobro ya se hiciera. Capturar sus excepciones o sacar el aviso del proceso.
- **Sé explícito con los ensamblados a escanear**: `RegisterServicesFromAssembly` usa reflexión al arrancar; pasa solo los ensamblados que contienen handlers.
- **Inyecta la interfaz más estrecha**: `ISender` en los endpoints, `IPublisher` en quien solo publica; `IMediator` ofrece las dos.

## Documentación oficial

- [github.com/LuckyPennySoftware/MediatR](https://github.com/LuckyPennySoftware/MediatR): el `README` contiene la instalación, qué registra `AddMediatR`, el registro de behaviors y la clave de licencia; empezar aquí.
- [github.com/LuckyPennySoftware/MediatR/wiki](https://github.com/LuckyPennySoftware/MediatR/wiki): ejemplos de peticiones, notificaciones, behaviors, publicadores personalizados y manejo de excepciones.
- [mediatr.io](https://mediatr.io): página del producto, desde donde se obtiene la clave de licencia de las versiones 13 y posteriores.

---

*En resumen: MediatR convierte cada caso de uso en un mensaje con su handler y deja lo transversal en un pipeline de behaviors, a cambio de una indirección y, desde la versión 13, de una licencia que hay que leer antes de adoptarla.*
