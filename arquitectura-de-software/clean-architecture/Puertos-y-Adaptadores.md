# Puertos y Adaptadores

## ¿Qué es?

Puertos y adaptadores es un vocabulario para las fronteras de una aplicación: un **puerto** es una interfaz con la forma que fija el centro de la aplicación, y un **adaptador** es la pieza que conecta ese puerto con una tecnología concreta (un framework web, una base de datos, un proveedor de pagos). Es el nombre que la arquitectura hexagonal da a la misma idea que persigue Clean Architecture.

## ¿Por qué existe?

Una aplicación tiene reglas de negocio y, a su alrededor, muchas formas de entrar y de salir: peticiones HTTP, mensajes de una cola, comandos de consola, una base de datos, una pasarela de pago, el correo. Si cada regla conoce directamente la tecnología con la que habla, cada cambio externo (otro proveedor, otro transporte, otra base de datos) obliga a tocar el negocio, y cada test necesita esa tecnología funcionando.

Alistair Cockburn formuló la solución en 2005 con la arquitectura hexagonal: el centro define unas **entradas y salidas con forma fija** y todo lo demás se acopla a ellas mediante piezas intercambiables. La imagen es la de un ordenador con puertos USB. El ordenador no sabe si le conectan un ratón, un teclado o una memoria: define la forma del puerto, y cada dispositivo trae el adaptador que encaja. Cambiar de dispositivo no obliga a abrir la carcasa.

Esto separa dos preguntas: *qué* ofrece o necesita la aplicación (el puerto, estable y escrito en el idioma del negocio) y *cómo* se consigue con tecnología concreta (el adaptador, reemplazable).

> Si conoces el patrón *Adapter* de GoF, es la misma idea aplicada a escala de aplicación: un adaptador convierte la interfaz de una tecnología en la interfaz que espera el cliente, aquí el centro.

## ¿Cuándo y para qué se usa?

Aparece en cada punto donde la aplicación se comunica con el exterior. En una tienda online: el pedido #4711 llega por HTTP desde la web o por un mensaje de otro sistema (entradas distintas, mismo caso de uso `ConfirmarPedido`); para confirmarlo hay que leer y guardar el pedido, cobrar y avisar al cliente (salidas que el caso de uso necesita sin querer saber con qué tecnología se hacen).

Sirve para tres cosas concretas: poder probar el negocio sin infraestructura real, poder añadir una entrada o cambiar una salida sin tocar el centro, y tener un nombre compartido para decir «esto es una frontera» en una revisión de código.

## Equivalencia con Clean Architecture

Hexagonal y Clean Architecture comparten objetivo (aislar el negocio de la tecnología) y regla (las dependencias de código apuntan hacia el centro, ver [Regla de Dependencia](Regla-de-Dependencia.md)). Cambia el vocabulario y el dibujo: círculos concéntricos frente a un hexágono con puertos en el borde.

| Hexagonal | Clean Architecture | En la solución de la tienda |
|---|---|---|
| Interior del hexágono | Entidades + casos de uso | `Tienda.Dominio` y `Tienda.Aplicacion` |
| Puerto de entrada (*driving*) | Frontera de entrada del caso de uso (*input boundary*) | `ConfirmarPedido` (el caso de uso en sí) |
| Puerto de salida (*driven*) | Interfaces de acceso a lo externo (*gateways*), frontera de salida | `IRepositorioPedidos`, `IPasarelaPago`, `INotificador` |
| Adaptador de entrada (primario) | Controladores en la capa de adaptadores de interfaz | `PedidosController`, consumidor de mensajes |
| Adaptador de salida (secundario) | Implementaciones de los *gateways* en infraestructura | repositorio SQL, cliente de Stripe, notificador por email |

La diferencia práctica es de énfasis: hexagonal habla de *lados* (quien llama a la aplicación frente a quien la aplicación llama) y Clean habla de *capas* (qué está más cerca del negocio). Una solución puede describirse con ambos vocabularios a la vez sin contradicción. La ficha [Clean Architecture](Clean-Architecture.md) recorre las capas; esta se centra en las fronteras.

## Las dos direcciones

Un puerto se clasifica por quién inicia la conversación.

| | Puertos de entrada (*driving*) | Puertos de salida (*driven*) |
|---|---|---|
| Quién llama a quién | El exterior llama a la aplicación | La aplicación llama al exterior |
| Qué expresan | Lo que la aplicación **ofrece** | Lo que la aplicación **necesita** |
| Quién escribe la interfaz | La aplicación (es su API interna) | La aplicación, según su necesidad |
| Quién implementa el puerto | El propio caso de uso | El adaptador, en infraestructura |
| Quién lo usa | El adaptador de entrada | El caso de uso |
| Ejemplos | `ConfirmarPedido`, `CancelarPedido` | `IRepositorioPedidos`, `IPasarelaPago`, `INotificador` |
| Adaptadores típicos | Controlador REST, consumidor de cola, comando de consola, pantalla | Repositorio SQL, cliente de Stripe, notificador por email, fake de test |

En .NET es habitual que el puerto de entrada sea simplemente la **clase del caso de uso**, sin interfaz propia: el adaptador de entrada la recibe por constructor y llama a su método. Una interfaz `IConfirmarPedido` solo se justifica si hay motivo para sustituir el caso de uso entero (por ejemplo, para probar un controlador sin ejecutar la lógica); la interfaz de los puertos de salida, en cambio, es imprescindible, porque ahí la dependencia sí hay que invertir (ver [Inversión de Dependencias](Inversion-de-Dependencias.md)).

El mapa completo de la aplicación de ejemplo:

```text
   ENTRADAS (driving)                                        SALIDAS (driven)

 ┌───────────────────┐                                    ┌──────────────────────┐
 │ PedidosController │─┐                               ┌─►│ RepositorioSqlServer │
 │ (HTTP)            │ │     ┌─────────────────────┐   │  └──────────────────────┘
 └───────────────────┘ │     │                     │   │    IRepositorioPedidos
                       ├────►│   ConfirmarPedido   │───┤
 ┌───────────────────┐ │     │  (puerto de entrada)│   │  ┌──────────────────────┐
 │ Consumidor de     │─┘     │                     │   ├─►│ PasarelaStripe       │
 │ mensajes (cola)   │       │ Pedido, LineaPedido │   │  └──────────────────────┘
 └───────────────────┘       │ (reglas de negocio) │   │    IPasarelaPago
   adaptadores               └─────────────────────┘   │
   de entrada                                          │  ┌──────────────────────┐
                                                       └─►│ NotificadorEmail     │
                                                          │ NotificadorFalso     │
                                                          └──────────────────────┘
                                                            INotificador
                                                            adaptadores de salida
```

Las flechas indican quién llama a quién en ejecución. En el código, las referencias entre proyectos van todas hacia el centro: los adaptadores conocen al caso de uso y a las interfaces, nunca al revés.

## Un caso de uso, dos entradas y dos salidas

El caso de uso `ConfirmarPedido` y sus puertos de salida, en `Tienda.Aplicacion`:

```csharp
public interface IRepositorioPedidos
{
    Task<Pedido?> ObtenerPorId(int id);
    Task Guardar(Pedido pedido);
}

public interface IPasarelaPago
{
    Task<bool> Cobrar(decimal importe, string tarjeta);
}

public interface INotificador
{
    Task PedidoConfirmado(Pedido pedido);
}

public record ConfirmarPedidoComando(int PedidoId);

public enum ConfirmarPedidoResultado { Confirmado, PedidoNoEncontrado, PedidoSinLineas, PagoRechazado }

public class ConfirmarPedido(
    IRepositorioPedidos pedidos, IPasarelaPago pasarela, INotificador notificador)
{
    public async Task<ConfirmarPedidoResultado> Ejecutar(ConfirmarPedidoComando comando)
    {
        var pedido = await pedidos.ObtenerPorId(comando.PedidoId);
        if (pedido is null) return ConfirmarPedidoResultado.PedidoNoEncontrado;
        if (pedido.Lineas.Count == 0) return ConfirmarPedidoResultado.PedidoSinLineas;

        if (!await pasarela.Cobrar(pedido.Total, pedido.Tarjeta))
            return ConfirmarPedidoResultado.PagoRechazado;

        pedido.MarcarPagado();
        await pedidos.Guardar(pedido);
        await notificador.PedidoConfirmado(pedido);
        return ConfirmarPedidoResultado.Confirmado;
    }
}
```

El caso de uso recibe un comando con datos propios (`ConfirmarPedidoComando`) y devuelve un desenlace del negocio. No aparece HTTP, ni JSON, ni SMTP.

### Primera entrada: el controlador HTTP

```csharp
[ApiController]
[Route("pedidos")]
public class PedidosController(ConfirmarPedido confirmarPedido) : ControllerBase
{
    [HttpPost("{id:int}/confirmar")]
    public async Task<IActionResult> Confirmar(int id)
    {
        var resultado = await confirmarPedido.Ejecutar(new ConfirmarPedidoComando(id));

        return resultado switch
        {
            ConfirmarPedidoResultado.Confirmado => NoContent(),
            ConfirmarPedidoResultado.PedidoNoEncontrado => NotFound(),
            ConfirmarPedidoResultado.PedidoSinLineas => UnprocessableEntity(),
            ConfirmarPedidoResultado.PagoRechazado => StatusCode(402),
            _ => StatusCode(500)
        };
    }
}
```

`POST /pedidos/4711/confirmar` se convierte en un comando y el desenlace vuelve como código HTTP. Cómo se decide esa tabla de traducción por capas está en [Códigos de Resultado por Capa](Codigos-de-Resultado-por-Capa.md).

### Segunda entrada: un consumidor de mensajes

El mismo caso de uso atiende ahora mensajes de una cola (por ejemplo, un sistema de almacén que avisa de que el pedido está listo):

```csharp
public record MensajePedidoListo(int PedidoId);

public enum Acuse { Procesado, Descartado }

public class ConsumidorPedidosListos(ConfirmarPedido confirmarPedido)
{
    public async Task<Acuse> Procesar(string cuerpoJson)
    {
        var mensaje = JsonSerializer.Deserialize<MensajePedidoListo>(cuerpoJson);
        if (mensaje is null) return Acuse.Descartado;

        var resultado = await confirmarPedido.Ejecutar(new ConfirmarPedidoComando(mensaje.PedidoId));

        return resultado == ConfirmarPedidoResultado.Confirmado ? Acuse.Procesado : Acuse.Descartado;
    }
}
```

Este adaptador traduce otro idioma: el cuerpo `{"PedidoId":4711}` pasa a ser el mismo `ConfirmarPedidoComando(4711)`, y el desenlace se convierte en la respuesta que entiende una cola (acuse de recibo o descarte del mensaje, en lugar de un código HTTP). `Procesar` recibe el cuerpo como texto para que el adaptador sea independiente del cliente de mensajería concreto; el código que lee de la cola y llama a `Procesar` es el borde exterior del adaptador.

### Dos salidas para `INotificador`

En producción, el adaptador envía un correo:

```csharp
public class NotificadorEmail(SmtpClient smtp) : INotificador
{
    public Task PedidoConfirmado(Pedido pedido)
    {
        var correo = new MailMessage("tienda@ejemplo.com", pedido.Cliente.Email)
        {
            Subject = $"Pedido #{pedido.Id} confirmado",
            Body = $"Hola {pedido.Cliente.Nombre}, hemos cobrado {pedido.Total:0.00} EUR."
        };
        return smtp.SendMailAsync(correo);
    }
}
```

En los tests, otro adaptador del mismo puerto apunta lo que recibe:

```csharp
public class NotificadorFalso : INotificador
{
    public List<int> PedidosNotificados { get; } = [];

    public Task PedidoConfirmado(Pedido pedido)
    {
        PedidosNotificados.Add(pedido.Id);
        return Task.CompletedTask;
    }
}
```

Con el fake, cualquiera de las dos entradas se prueba sin red y sin servidor de correo:

```csharp
[Fact]
public async Task El_consumidor_de_mensajes_confirma_el_mismo_pedido()
{
    var (caso, notificador) = await Preparar();   // repositorio en memoria + pasarela falsa + NotificadorFalso

    var acuse = await new ConsumidorPedidosListos(caso).Procesar("""{"PedidoId":4711}""");

    Assert.Equal(Acuse.Procesado, acuse);
    Assert.Equal([4711], notificador.PedidosNotificados);
}
```

El test equivalente con `new PedidosController(caso).Confirmar(4711)` comprueba `NoContentResult` y la misma lista de notificados. Ambos tests pasan (verificado con xunit en .NET 10).

### Qué cambia y qué no

| Cambia al añadir una entrada o una salida | No cambia |
|---|---|
| Un adaptador nuevo (clase y su registro en `Program.cs`) | `ConfirmarPedido` |
| La traducción de entrada (ruta + JSON, o cuerpo de mensaje) a `ConfirmarPedidoComando` | El comando y el enum de desenlaces |
| La traducción del desenlace (código HTTP, acuse de cola) | Las reglas de `Pedido` (sin líneas no se confirma; un pedido pagado no se cancela) |
| El adaptador de salida elegido al arrancar (`NotificadorEmail` o `NotificadorFalso`) | La interfaz `INotificador` y sus consumidores |

Si añadir la segunda entrada obliga a editar el caso de uso, la lógica estaba en el adaptador de la primera.

## Cómo nombrar un puerto

El puerto se nombra por la **necesidad del negocio**, no por la tecnología que hoy la satisface. El nombre es lo primero que delata si la frontera está cortada en el sitio correcto.

| Nombre | Por qué |
|---|---|
| ✅ `INotificador` | Dice qué necesita el negocio (avisar al cliente). Sirve igual para email, SMS o push |
| ❌ `IEmailSender` | Fija el canal. Si mañana el aviso es una notificación móvil, el nombre miente o hay que renombrar a todos los consumidores |
| ✅ `IPasarelaPago` | Habla de cobrar, no de un proveedor |
| ❌ `IStripeService` | Es Stripe con un prefijo `I`; el centro conoce al proveedor |
| ✅ `IRepositorioPedidos` | Colección de pedidos del negocio |
| ❌ `IPedidosSqlRepository` | Revela el almacenamiento |

El nombre del **método** sigue la misma regla: `PedidoConfirmado(pedido)` y no `EnviarCorreo(destinatario, asunto, cuerpo)`. El segundo obliga a que el caso de uso redacte asuntos y cuerpos de correo, es decir, que haga el trabajo del adaptador. La prueba: si el nombre del puerto o de sus métodos cambia al sustituir la tecnología, está nombrado por la tecnología.

## El adaptador solo traduce

Un adaptador convierte entre el idioma de una tecnología y el idioma del negocio, y delega. Lo que traduce depende de la dirección:

| Dirección | Entra en el centro | Sale del centro |
|---|---|---|
| Adaptador de entrada | Ruta, cuerpo JSON, cabeceras, cuerpo de mensaje → `ConfirmarPedidoComando` | Desenlace del caso de uso → código HTTP, acuse de cola, código de salida de consola |
| Adaptador de salida | Valor del dominio (`pedido.Total`, `pedido.Tarjeta`) → llamada al SDK o consulta SQL | Respuesta o excepción del proveedor → valor o desenlace del negocio (`StripeException` con código `card_declined` → `false` en `Cobrar`) |

Ejemplo de la traducción de salida en un adaptador de pago:

```csharp
public class PasarelaStripe(StripeClient cliente) : IPasarelaPago
{
    public async Task<bool> Cobrar(decimal importe, string tarjeta)
    {
        try
        {
            var cargo = await cliente.CrearCargo(importe, "eur", tarjeta);
            return cargo.Estado == "succeeded";
        }
        catch (StripeException ex) when (ex.Codigo == "card_declined")
        {
            return false;   // rechazo de la tarjeta: desenlace del negocio, no fallo técnico
        }
    }
}
```

La tarjeta rechazada es una respuesta esperada del negocio y llega al caso de uso como `false`; un fallo de red u otra excepción inesperada no se disfraza y se propaga. Qué excepciones traducir, cuáles dejar subir y cómo reintentar se desarrolla en [Capa de Infraestructura](Capa-de-Infraestructura.md).

Lo que **no** hace un adaptador: decidir si un pedido se puede confirmar, calcular el total, aplicar un descuento. Eso es negocio y vive en `Pedido` o en el caso de uso. Una regla en un adaptador existe una sola vez *por adaptador*: con dos entradas, habría que duplicarla (y las dos copias terminarían diferenciándose).

## Contract tests: el fake y el real cumplen el mismo contrato

Los casos de uso se prueban con fakes. Esos tests solo valen si el fake se comporta como el adaptador real en lo que el caso de uso observa: qué devuelve para un pedido inexistente, qué pasa al guardar dos veces el mismo pedido. Un *contract test* es una **suite escrita contra el puerto** que se ejecuta contra cada adaptador. Si el fake y el real la pasan, son intercambiables; si divergen, el test lo dice.

En xunit, la suite es una clase abstracta con un método que crea el adaptador, y una clase derivada por adaptador:

```csharp
public abstract class RepositorioPedidosContrato
{
    protected abstract IRepositorioPedidos CrearRepositorio();

    private static Pedido PedidoEjemplo()
    {
        var pedido = new Pedido(4711, new Cliente(1, "Ana", "ana@ejemplo.com"), "tok_visa");
        pedido.AñadirLinea(productoId: 10, precio: 25m, cantidad: 2);
        pedido.AñadirLinea(productoId: 11, precio: 9.99m, cantidad: 1);
        return pedido;
    }

    [Fact]
    public async Task Un_pedido_inexistente_devuelve_null()
    {
        var repositorio = CrearRepositorio();

        Assert.Null(await repositorio.ObtenerPorId(999));
    }

    [Fact]
    public async Task Un_pedido_guardado_se_recupera_con_sus_lineas()
    {
        var repositorio = CrearRepositorio();
        await repositorio.Guardar(PedidoEjemplo());

        var leido = await repositorio.ObtenerPorId(4711);

        Assert.NotNull(leido);
        Assert.Equal(2, leido.Lineas.Count);
        Assert.Equal(59.99m, leido.Total);
        Assert.Equal("ana@ejemplo.com", leido.Cliente.Email);
    }

    [Fact]
    public async Task Guardar_dos_veces_el_mismo_pedido_actualiza_sin_duplicar()
    {
        var repositorio = CrearRepositorio();
        var pedido = PedidoEjemplo();
        await repositorio.Guardar(pedido);
        pedido.MarcarPagado();
        await repositorio.Guardar(pedido);

        var leido = await repositorio.ObtenerPorId(4711);

        Assert.True(leido!.Pagado);
        Assert.Equal(2, leido.Lineas.Count);
    }

    [Fact]
    public async Task Modificar_el_pedido_sin_guardar_no_cambia_lo_persistido()
    {
        var repositorio = CrearRepositorio();
        var pedido = PedidoEjemplo();
        await repositorio.Guardar(pedido);

        pedido.MarcarPagado();

        Assert.False((await repositorio.ObtenerPorId(4711))!.Pagado);
    }
}

public class RepositorioEnMemoriaTests : RepositorioPedidosContrato
{
    protected override IRepositorioPedidos CrearRepositorio() => new RepositorioPedidosEnMemoria();
}

public class RepositorioSqliteTests : RepositorioPedidosContrato
{
    protected override IRepositorioPedidos CrearRepositorio() => new RepositorioPedidosSqlite();
}
```

Cada `[Fact]` de la clase base se ejecuta una vez por clase derivada: cuatro comprobaciones por adaptador, ocho tests en total. Salida real con ambos adaptadores correctos:

```text
Correctas RepositorioEnMemoriaTests.Un_pedido_inexistente_devuelve_null
Correctas RepositorioEnMemoriaTests.Un_pedido_guardado_se_recupera_con_sus_lineas
Correctas RepositorioEnMemoriaTests.Guardar_dos_veces_el_mismo_pedido_actualiza_sin_duplicar
Correctas RepositorioEnMemoriaTests.Modificar_el_pedido_sin_guardar_no_cambia_lo_persistido
Correctas RepositorioSqliteTests.Un_pedido_inexistente_devuelve_null
...
Correctas RepositorioSqliteTests.Modificar_el_pedido_sin_guardar_no_cambia_lo_persistido
```

El valor se ve cuando un adaptador falla. Un fake escrito deprisa guarda la referencia del objeto en el diccionario (`_pedidos[pedido.Id] = pedido;`) en lugar de una copia. La base de datos real devuelve siempre un objeto nuevo; el fake devuelve el mismo, y cualquier cambio sobre el pedido sin llamar a `Guardar` aparece como «persistido». El contrato lo detecta:

```text
Con error RepositorioEnMemoriaTests.Modificar_el_pedido_sin_guardar_no_cambia_lo_persistido
  Assert.False() Failure
  Expected: False
  Actual:   True
```

Sin esa suite, los tests del caso de uso pasarían con el fake mientras un olvido de `Guardar` en producción dejaría el pedido sin pagar. En la práctica, el adaptador real del contrato se ejecuta contra una base de datos desechable (SQLite en memoria como aquí, o un contenedor con [Testcontainers](../../devops/docker/Testcontainers.md) cuando el motor real importa). El patrón de repositorio como tal se explica en [Repositorios](../patrones-de-diseno/Repositorios.md).

## Cuándo NO merece un puerto

Un puerto cuesta una interfaz, un adaptador y un registro. Se paga cuando hay algo que aislar y se desperdicia cuando no.

| Dependencia | ¿Puerto? | Motivo |
|---|---|---|
| Base de datos, ficheros, disco | Sí | I/O lento, con estado, difícil de reproducir en un test |
| Servicios externos (pagos, correo, APIs de terceros) | Sí | Tienen coste, latencia y fallan por su cuenta |
| El reloj (`DateTime.UtcNow`) | Sí (`TimeProvider`) | Sin él no se prueba «un pedido pendiente más de 24 h se cancela» |
| Aleatoriedad e identificadores generados | Sí | El test no puede depender de un valor distinto en cada ejecución |
| Cálculo del total, aplicar un descuento | No | Función pura y determinista: se prueba tal cual |
| Entidades y objetos de valor (`Pedido`, `Cliente`) | No | Son el negocio, no una frontera |
| Clase interna con una sola implementación que nadie más usa | No | Si aparece la segunda necesidad, extraer la interfaz cuesta poco |
| Una librería de utilidades pura (formateo, serialización simple) | No, salvo que el formato sea una decisión del negocio | No hay I/O ni efectos que aislar |

Criterio resumido: un puerto existe donde la aplicación toca algo que **no controla** (red, disco, tiempo, azar, sistemas de otros) o donde hay más de un adaptador plausible.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `ConfirmarPedido` recibe `HttpRequest`, `IFormFile` o `ClaimsPrincipal`; no se puede invocar desde el consumidor de mensajes | **Tipos del framework web cruzando al centro**: el adaptador de entrada no ha traducido. El caso de uso debe recibir un comando con datos propios (`ConfirmarPedidoComando`) |
| Añadir la entrada de mensajes obliga a copiar una comprobación del controlador | **Lógica de negocio en el adaptador**: la regla pertenece a `Pedido` o al caso de uso, donde la comparten todas las entradas |
| Cambiar de Stripe a otro proveedor obliga a tocar el caso de uso o a los consumidores del puerto | **Puerto que calca la API del proveedor**: devuelve `StripeCharge`, lanza `StripeException` o expone «intentos de pago» que solo existen en Stripe. El puerto debería hablar de cobrar |
| Hay `IPedido`, `ILineaPedido`, `ICliente`, cada una con una única implementación | **Un puerto por clase**: se ha extraído interfaz por costumbre, sin frontera real. Las entidades no son puertos |
| Los tests del caso de uso pasan y en producción falla algo que el fake «hacía bien» | **Fake sin contract tests**: el fake y el adaptador real divergen en un caso borde (inexistente, duplicado, copia frente a referencia) |
| El adaptador SQL devuelve `IQueryable<Pedido>` y el caso de uso encadena `.Where(...)` | **Detalle de la tecnología filtrado por el puerto**: el consumidor queda atado al proveedor de LINQ. Un `Dictionary` en memoria no podría implementar el puerto con esa firma |
| El controlador lanza una excepción con 404 o 402 dentro del caso de uso | **Traducción hecha en el lado equivocado**: el caso de uso debe devolver un desenlace; cada adaptador decide qué significa en su lenguaje |

## Buenas prácticas avanzadas

- **Haz que el caso de uso reciba comandos y devuelva desenlaces propios, nunca tipos del transporte.** Si el método `Ejecutar` se puede llamar desde una prueba, un controlador, un consumidor y una consola sin cambiar nada, la frontera está bien. Si la firma contiene `HttpContext`, `IFormFile`, `IActionResult` o un DTO anotado con atributos del framework, el centro depende ya del web.
- **Diseña el puerto desde el consumidor, y la prueba del algodón es un diccionario.** Si cualquier puerto de salida se puede implementar con un `Dictionary` en memoria (o con una lista) sin cambiar la firma, no filtra tecnología. Si exige `DbConnection`, `IQueryable` o excepciones del proveedor, hay que rediseñarlo.
- **Un puerto por necesidad y por rol, no por tecnología ni por clase.** `INotificador` con un único método `PedidoConfirmado` es mejor que `INotificador` con doce métodos de notificación que solo usa otro caso de uso: se parte por quien lo consume. Los fakes quedan de pocas líneas y el contrato, pequeño.
- **Escribe el contrato antes que el fake.** El orden habitual (fake rápido y, quizá, un test después) produce fakes que se parecen a lo que el programador *creía* que hacía la base de datos. Con la suite abstracta primero, el fake nace obligado a respetar las mismas reglas que el adaptador real, incluidos los casos borde como el duplicado o la copia frente a la referencia.
- **Mantén los adaptadores finos y reconocibles.** Cuando un adaptador pasa de unas decenas de líneas, suele haber negocio dentro. Señal rápida: si para probar el adaptador hay que preparar datos de dominio complejos, esa lógica debería estar en el dominio o en el caso de uso.
- **Registra los adaptadores en un solo sitio.** La elección «email o fake», «SQL Server o SQLite» se hace únicamente en la raíz de composición (`Program.cs` o un método de extensión que este invoque). Si un caso de uso decide con un `if (entorno == "Test")` qué adaptador usar, el puerto ya no aísla nada.

## Documentación oficial

- [Hexagonal architecture (Alistair Cockburn)](https://alistair.cockburn.us/hexagonal-architecture/) — el artículo original que acuñó «puertos y adaptadores». Merece la pena para ver la motivación inicial (probar la aplicación sin interfaz de usuario ni base de datos) y la distinción entre lado que conduce y lado conducido.
- [The Clean Architecture (Robert C. Martin)](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html) — el artículo que sitúa hexagonal y otras variantes bajo la misma regla de dependencia. Útil para contrastar el vocabulario de círculos con el de puertos.
- [Common web application architectures (Microsoft)](https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/common-web-application-architectures) — la guía de .NET que presenta la arquitectura limpia con su estructura de proyectos. Consúltala para ver cómo se reparten núcleo, infraestructura e interfaz de usuario en una solución .NET.

---

*En resumen: el centro dicta la forma de sus puertos, cada tecnología trae su adaptador y el adaptador solo traduce; mientras eso se cumpla, entradas y salidas se añaden o se cambian sin tocar el negocio.*
