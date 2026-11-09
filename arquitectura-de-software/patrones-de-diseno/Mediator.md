# Mediator

## ¿Qué es?

Mediator es un patrón de diseño (GoF) en el que un objeto central, el *mediador*, concentra la comunicación entre otros objetos para que estos no se conozcan entre sí. En las aplicaciones actuales suele aparecer como **despachador de mensajes**: quien pide algo entrega un mensaje al mediador y este lo hace llegar a quien sabe tratarlo.

## ¿Por qué existe?

La forma directa de coordinar piezas es que una llame a las otras. En la tienda online, confirmar el pedido #4711 implica reservar stock, emitir la factura y avisar al cliente, y el caso de uso lo resuelve conociendo a cada colaborador:

```csharp
// ❌ El caso de uso conoce a todos los que intervienen
public class ConfirmarPedido(
    IRepositorioPedidos pedidos,
    IPasarelaPago pasarela,
    IServicioStock stock,
    IServicioFacturacion facturacion,
    INotificador notificador,
    IServicioEstadisticas estadisticas)
{
    public async Task Ejecutar(int pedidoId)
    {
        // ... cobrar, guardar ...
        await stock.Reservar(pedidoId);
        await facturacion.Emitir(pedidoId);
        await notificador.PedidoConfirmado(pedidoId);
        await estadisticas.Registrar(pedidoId);
    }
}
```

Cada requisito nuevo («al confirmar, avisar también al almacén») añade una dependencia al constructor y una línea al método, y cada colaborador nuevo que quiera reaccionar obliga a editar el caso de uso. Con el mediador, quien pide solo conoce el mensaje y al mediador:

```csharp
// ✅ Quien pide no sabe quién ejecuta ni cuántos reaccionan
await mediador.Publicar(new PedidoConfirmado(pedidoId));
```

> Piensa en una torre de control aérea: los aviones no se coordinan entre ellos por radio directa para no chocar; todos hablan con la torre, y es la torre quien decide el orden de aterrizaje. Ningún avión necesita conocer la posición de los demás, solo escuchar a la torre.

## ¿Cuándo y para qué se usa?

Cuando varios objetos se llaman entre sí en una maraña (cada uno referencia a varios otros) y conviene centralizar la coordinación en un solo sitio. Y, en aplicaciones, cuando un punto de entrada debe disparar una acción sin acoplarse a la clase que la ejecuta, o cuando una misma noticia interesa a varios manejadores independientes dentro del mismo proceso.

El mediador siempre vive **dentro de un proceso**: no es una cola ni un bus entre servicios. Si el mensaje debe sobrevivir a un reinicio o salir a otro servicio, hace falta un broker (ver [Mensajería Asíncrona](../../devops/mensajeria-asincrona/Mensajeria-Asincrona.md)).

## El mediador clásico (GoF)

En la versión del libro hay **colegas** (los objetos que colaboran) y un **mediador** que los conoce a todos. Los colegas no se referencian entre sí: cuando les ocurre algo, se lo comunican al mediador, y este decide a quién avisar y en qué orden. Ejemplo mínimo con los participantes de la confirmación del pedido:

```csharp
public interface IMediadorPedido { void Notificar(object emisor, string suceso, int pedidoId); }

public class Stock
{
    public IMediadorPedido? Mediador { get; set; }
    public void Reservar(int pedidoId)
    {
        Console.WriteLine($"Stock: reservadas las unidades del pedido #{pedidoId}");
        Mediador!.Notificar(this, "StockReservado", pedidoId);
    }
}

public class Facturacion
{
    public IMediadorPedido? Mediador { get; set; }
    public void Emitir(int pedidoId)
    {
        Console.WriteLine($"Facturación: factura emitida para el pedido #{pedidoId}");
        Mediador!.Notificar(this, "FacturaEmitida", pedidoId);
    }
}

public class Notificaciones
{
    public void AvisarCliente(int pedidoId) =>
        Console.WriteLine($"Notificaciones: correo enviado por el pedido #{pedidoId}");
}

// El mediador es el único que conoce a los tres colegas y decide el orden.
public class ProcesoConfirmacion : IMediadorPedido
{
    public Stock Stock { get; } = new();
    private readonly Facturacion _facturacion = new();
    private readonly Notificaciones _notificaciones = new();

    public ProcesoConfirmacion()
    {
        Stock.Mediador = this;
        _facturacion.Mediador = this;
    }

    public void Notificar(object emisor, string suceso, int pedidoId)
    {
        switch (suceso)
        {
            case "StockReservado": _facturacion.Emitir(pedidoId); break;
            case "FacturaEmitida": _notificaciones.AvisarCliente(pedidoId); break;
        }
    }
}
```

Al ejecutar `new ProcesoConfirmacion().Stock.Reservar(4711)`:

```text
Stock: reservadas las unidades del pedido #4711
Facturación: factura emitida para el pedido #4711
Notificaciones: correo enviado por el pedido #4711
```

`Stock` no sabe que existe `Facturacion`: solo dice «ya reservé». El orden de la cadena vive en un único `switch`, y cambiarlo no toca a ningún colega.

### Cuando el mediador se convierte en el objeto dios

El peligro del diseño clásico es que toda la lógica de coordinación se acumula en el mediador. Con cada colega y cada suceso nuevo crece el `switch`, y acaba conociendo reglas de negocio (cuándo facturar, a quién avisar según el importe). Se ha movido el acoplamiento de «todos con todos» a «todos con el mediador», y el mediador es ahora la clase que nadie se atreve a tocar. Dos defensas: que el mediador solo **encamine** (la regla vive en el dominio o en el colega) y partir los mediadores por proceso, no tener uno para toda la aplicación.

## El mediador como despachador de mensajes

La variante moderna cambia el `switch` por un mapa de tipos: cada mensaje es una clase, cada manejador declara qué mensaje trata, y el mediador busca el manejador en el contenedor de dependencias. Hay dos clases de mensaje:

- **Petición**: espera una respuesta y tiene **exactamente un** manejador.
- **Notificación**: informa de algo ya ocurrido y tiene **cero, uno o varios** manejadores.

Implementación mínima, con inyección de dependencias de `Microsoft.Extensions.DependencyInjection`:

```csharp
using Microsoft.Extensions.DependencyInjection;

public interface IPeticion<TRespuesta>;
public interface IManejador<TPeticion, TRespuesta> where TPeticion : IPeticion<TRespuesta>
{
    Task<TRespuesta> Manejar(TPeticion peticion);
}
public interface INotificacion;
public interface IManejadorNotificacion<TNotificacion> where TNotificacion : INotificacion
{
    Task Manejar(TNotificacion notificacion);
}

public interface IMediador
{
    Task<TRespuesta> Enviar<TRespuesta>(IPeticion<TRespuesta> peticion);
    Task Publicar(INotificacion notificacion);
}

public class Mediador(IServiceProvider servicios) : IMediador
{
    public Task<TRespuesta> Enviar<TRespuesta>(IPeticion<TRespuesta> peticion)
    {
        var tipo = typeof(IManejador<,>).MakeGenericType(peticion.GetType(), typeof(TRespuesta));
        dynamic manejador = servicios.GetRequiredService(tipo); // exactamente uno, o falla
        return manejador.Manejar((dynamic)peticion);
    }

    public async Task Publicar(INotificacion notificacion)
    {
        var tipo = typeof(IManejadorNotificacion<>).MakeGenericType(notificacion.GetType());
        foreach (var servicio in servicios.GetServices(tipo)) // cero, uno o varios
        {
            dynamic manejador = servicio!;
            await manejador.Manejar((dynamic)notificacion);
        }
    }
}
```

`dynamic` evita escribir a mano la reflexión que invoca el método genérico; es suficiente para entender el patrón, y las librerías reales cachean y compilan ese paso.

`ConfirmarPedido` pasa a ser una petición con su manejador, y `PedidoConfirmado` una notificación con dos manejadores:

```csharp
public enum ConfirmarPedidoResultado { Confirmado, NoEncontrado }
public record ConfirmarPedidoComando(int PedidoId) : IPeticion<ConfirmarPedidoResultado>;
public record PedidoConfirmado(int PedidoId) : INotificacion;

public class ConfirmarPedido(IMediador mediador) : IManejador<ConfirmarPedidoComando, ConfirmarPedidoResultado>
{
    public async Task<ConfirmarPedidoResultado> Manejar(ConfirmarPedidoComando c)
    {
        if (c.PedidoId != 4711) return ConfirmarPedidoResultado.NoEncontrado;
        Console.WriteLine($"ConfirmarPedido: pedido #{c.PedidoId} confirmado");
        await mediador.Publicar(new PedidoConfirmado(c.PedidoId));
        return ConfirmarPedidoResultado.Confirmado;
    }
}
public class ReservarStock : IManejadorNotificacion<PedidoConfirmado> { /* escribe «Stock: reservado para #…» */ }
public class AvisarAlCliente : IManejadorNotificacion<PedidoConfirmado> { /* escribe «Notificador: correo por #…» */ }

public record CancelarPedidoComando(int PedidoId) : IPeticion<bool>; // sin manejador registrado
```

El registro y el uso:

```csharp
var servicios = new ServiceCollection()
    .AddSingleton<IMediador, Mediador>()
    .AddTransient<IManejador<ConfirmarPedidoComando, ConfirmarPedidoResultado>, ConfirmarPedido>()
    .AddTransient<IManejadorNotificacion<PedidoConfirmado>, ReservarStock>()
    .AddTransient<IManejadorNotificacion<PedidoConfirmado>, AvisarAlCliente>()
    .BuildServiceProvider();

var mediador = servicios.GetRequiredService<IMediador>();
Console.WriteLine(await mediador.Enviar(new ConfirmarPedidoComando(4711)));
Console.WriteLine(await mediador.Enviar(new ConfirmarPedidoComando(1)));
await mediador.Enviar(new CancelarPedidoComando(4711));
```

Salida real (.NET 10):

```text
ConfirmarPedido: pedido #4711 confirmado
Stock: reservado para #4711
Notificador: correo por #4711
Confirmado
NoEncontrado
No service for type 'IManejador`2[CancelarPedidoComando,System.Boolean]' has been registered.
```

Los dos manejadores de `PedidoConfirmado` se ejecutan sin que `ConfirmarPedido` los nombre; añadir un tercero es registrar una clase. Y la última línea muestra el fallo típico: una petición sin manejador solo se descubre **al ejecutarla**, no al compilar.

La implementación completa en .NET, con comportamientos comunes (*pipeline behaviors*), registro por escaneo de ensamblados y el resto de su API, está en [MediatR](MediatR.md).

## Qué se gana y qué se paga

| Se gana | Se paga |
|---|---|
| Quien pide no conoce la clase que ejecuta | «Ir a la definición» desde `Enviar` no lleva al manejador: hay que buscarlo por tipo |
| Un punto común donde enganchar logging, validación o medición | Las dependencias reales quedan ocultas: el constructor del controlador ya no dice qué hace |
| Añadir un reaccionario a una notificación sin tocar al emisor | Quién reacciona a un mensaje solo se ve buscando todos sus manejadores |
| Los manejadores se prueban de forma aislada | Depurar exige seguir el rastro por el contenedor; las pilas de llamadas son más largas |
| Un controlador delgado | Una capa de indirección (mensaje + manejador + registro) por cada operación |

## Cuándo sí y cuándo no

| Situación | ¿Mediador? | Alternativa |
|---|---|---|
| Un caso de uso al que solo llama un controlador | No | Inyectar el caso de uso y llamar a `Ejecutar` |
| La misma acción se invoca desde varios puntos de entrada (API, consumidor de cola, tarea programada) | Puede compensar | Si todos pueden inyectar el caso de uso, sigue bastando la llamada directa |
| Comportamiento común a todas las operaciones (log, validación, transacción) | Sí | Decoradores sobre cada caso de uso |
| Un hecho interesa a varios reaccionarios independientes | Sí, como notificación | [Eventos de dominio](Domain-Events.md) si el hecho nace en el dominio |
| Una clase llama a otra de su mismo módulo | No | Llamada directa |
| Dos módulos que no deben referenciarse como proyectos | Sí, con cuidado | Ver [Módulos vs Shared](../clean-architecture/Modulos-vs-Shared.md) |
| Necesitas entrega fiable entre procesos | No | Cola o broker |

Frente a las alternativas cercanas:

- **Llamada directa al caso de uso**: la más simple y navegable; es la opción por defecto (ver [Casos de Uso](../clean-architecture/Casos-de-Uso.md)).
- **Eventos de dominio**: el dominio anuncia un hecho ya ocurrido y otros reaccionan; el mediador es el mecanismo que puede transportarlos, pero el diseño del evento es otro tema.
- **Observer**: el emisor mantiene su propia lista de suscriptores y los avisa; el mediador, en cambio, es un tercero que ni emisor ni receptor necesitan conocer.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| El mediador tiene `if` sobre importes, estados o tipos de cliente | Reglas de negocio dentro del mediador: deben vivir en el dominio o en el manejador |
| Un servicio envía mensajes a sí mismo para llamar a sus propios métodos | Mediador usado para llamar métodos de la misma clase: basta una llamada directa |
| Confirmar un pedido dispara una petición que dispara otra que dispara otra | Cadenas de peticiones: el flujo real queda repartido en seis clases; agrupa el flujo en un único caso de uso |
| Al publicar una notificación ocurren cosas que nadie esperaba (cobros, correos) | Manejadores con efectos secundarios ocultos: quien publica no ve qué más se ejecuta |
| Un manejador llama a `Enviar` con otra petición y las transacciones, errores y logs se mezclan | `Enviar` dentro del manejador de otra petición: extrae la lógica común a una clase y que ambos manejadores la llamen |
| `No service for type ...` en producción | Petición sin manejador registrado: se detecta al ejecutar, así que cada petición necesita un test que la envíe |

## Buenas prácticas avanzadas

- **Una petición, un manejador, y comprobado**: añade un test que recorra todas las peticiones del ensamblado y compruebe que cada una tiene exactamente un manejador registrado; convierte el fallo de ejecución en un fallo de la batería de pruebas.
- **Las notificaciones se publican cuando el estado ya está guardado**: un manejador que reacciona a `PedidoConfirmado` no debe ver un pedido que luego se revierte.
- **Decide qué pasa si un manejador de notificación falla**: ejecutarlos en secuencia (como en el ejemplo) hace que un fallo corte a los siguientes; documenta si es lo deseado o aísla cada manejador.
- **Nombra los mensajes por intención**: `ConfirmarPedidoComando` para una orden (imperativo, un destinatario), `PedidoConfirmado` para un hecho (participio, varios oyentes). La diferencia de tiempo verbal distingue petición de notificación.
- **Resérvalo para las fronteras**: usarlo entre dos clases del mismo módulo suma indirección sin desacoplar nada que no se desacoplase ya con una interfaz.
- **Prueba los manejadores directamente**: son clases normales; instánciala y llama a `Manejar`, sin montar el mediador.

## Documentación oficial

- [Mediator, Refactoring.Guru](https://refactoring.guru/design-patterns/mediator): explicación visual del patrón con estructura, aplicabilidad y comparación con Observer y Facade; el punto de entrada para quien no tiene el libro *Design Patterns* (Gamma, Helm, Johnson, Vlissides) que lo catalogó.

---

*En resumen: el mediador convierte «todos hablan con todos» en «todos hablan con uno», pero esa comodidad se paga en trazabilidad, así que úsalo donde de verdad desacople y no donde una llamada directa ya bastaba.*
