# Inversión de Dependencias

## ¿Qué es?

La inversión de dependencias es el principio por el que el código de negocio no depende de la tecnología que necesita (base de datos, pasarela de pago, correo), sino de una **interfaz que él mismo define**; la tecnología se adapta a esa interfaz. Es el mecanismo que hace posible, en la práctica, que las dependencias apunten hacia el centro de la aplicación.

## ¿Por qué existe?

Una tienda online confirma el pedido #4711: tiene que cobrar. Lo natural es que el caso de uso `ConfirmarPedido` llame directamente a Stripe. Funciona, pero deja dos problemas:

- **No se puede probar sin cobrar de verdad.** Cualquier test de `ConfirmarPedido` ejecuta el cobro real (o falla por falta de red y credenciales).
- **Cambiar de proveedor obliga a tocar el negocio.** La regla «un pedido sin líneas no se confirma» acaba mezclada con el SDK de un tercero.

La solución es dar la vuelta a la relación. El negocio no dice «uso Stripe»; dice «necesito *algo* que sepa cobrar» y lo describe con una interfaz. Quién cumple ese contrato (Stripe, PayPal, un objeto falso de test) se decide fuera.

> Es como el enchufe y la toma de corriente: la casa define la forma de la toma (la interfaz) y cualquier aparato con el enchufe adecuado funciona, sin que la instalación eléctrica sepa si es una lámpara o una tostadora. Lo que no se hace es soldar la lámpara a la pared.

## ¿Cuándo y para qué se usa?

Cada vez que el centro de la aplicación necesita algo que vive en el borde: persistir pedidos, cobrar, enviar un correo, consultar una API externa, leer el reloj del sistema. En todos esos casos la interfaz se define en el centro (`IRepositorioPedidos`, `IPasarelaPago`, `INotificador`) y la implementación vive en `Tienda.Infraestructura`.

Los tres nombres que suelen mezclarse son cosas distintas:

| Concepto | Qué es | Dónde se ve |
|---|---|---|
| **Inversión de dependencias** (DIP) | Principio de diseño: el código de alto nivel y el de bajo nivel dependen de abstracciones, y la abstracción pertenece al alto nivel | En quién declara la interfaz y en qué dirección apuntan las referencias entre proyectos |
| **Inyección de dependencias** (DI) | Técnica: una clase recibe sus dependencias desde fuera (normalmente por constructor) en lugar de crearlas con `new` | En el constructor de `ConfirmarPedido` |
| **Contenedor de DI** | Herramienta que automatiza la técnica: sabe qué implementación corresponde a cada interfaz y construye los objetos | En `Program.cs`, con `AddScoped`, `AddSingleton`... |

Se puede aplicar el principio sin contenedor (pasando las implementaciones a mano) y se puede usar un contenedor violando el principio (registrando clases concretas y pidiéndolas por constructor).

## El recorrido completo: de `new` a un test sin red

### Sin inversión

```csharp
// Tienda.Aplicacion
public class ConfirmarPedido
{
    public async Task Ejecutar(Pedido pedido)
    {
        var pasarela = new PasarelaStripe();               // ❌ el caso de uso conoce a Stripe
        await pasarela.Cobrar(pedido.Total, pedido.Tarjeta);
        pedido.MarcarPagado();
    }
}
```

`Tienda.Aplicacion` tiene que referenciar el SDK de Stripe (o `Tienda.Infraestructura`), y un test de esta clase cobra de verdad. ❌

### La interfaz la define el centro

```csharp
// Tienda.Aplicacion (o Tienda.Dominio): habla el idioma del negocio
public interface IPasarelaPago
{
    Task<bool> Cobrar(decimal importe, string tarjeta);
}

public class ConfirmarPedido(IPasarelaPago pasarela)
{
    public async Task<ConfirmarPedidoResultado> Ejecutar(Pedido pedido)
    {
        if (!await pasarela.Cobrar(pedido.Total, pedido.Tarjeta))
            return ConfirmarPedidoResultado.PagoRechazado;

        pedido.MarcarPagado();
        return ConfirmarPedidoResultado.Confirmado;
    }
}
```

`ConfirmarPedido` pide un `IPasarelaPago` por constructor y no sabe qué hay detrás. Las reglas de negocio de verdad (pedido sin líneas, pedido ya pagado) viven en `Pedido`; aquí solo importa quién cobra.

### La implementación vive en la infraestructura

```csharp
// Tienda.Infraestructura: aquí sí aparece la tecnología
public class PasarelaStripe(StripeClient cliente) : IPasarelaPago
{
    public async Task<bool> Cobrar(decimal importe, string tarjeta)
    {
        // Traduce del idioma del negocio al del proveedor
        var cargo = await cliente.CrearCargo(importe, "eur", tarjeta);
        return cargo.Estado == "succeeded";
    }
}
```

`Tienda.Infraestructura` referencia a `Tienda.Aplicacion` (para ver `IPasarelaPago`), nunca al revés. `StripeClient` representa aquí el SDK del proveedor; el que use `CrearCargo` es un detalle de esta clase.

### El registro en `Program.cs`

```csharp
// Tienda.Api: la capa más externa conoce todas las demás
builder.Services.AddScoped<IPasarelaPago, PasarelaStripe>();
builder.Services.AddScoped<ConfirmarPedido>();
```

Cuando un endpoint pide `ConfirmarPedido`, el contenedor ve que necesita un `IPasarelaPago`, construye una `PasarelaStripe` y se la entrega. Pasar a PayPal es cambiar el segundo tipo de la primera línea.

Sin contenedor, el equivalente («*pure DI*») es construir el grafo a mano en el punto de arranque:

```csharp
// Raíz de composición escrita a mano
var pasarela = new PasarelaStripe(clienteStripe);
var confirmarPedido = new ConfirmarPedido(pasarela);
```

Es el mismo diseño, con las mismas dependencias; el contenedor solo ahorra escribir esas líneas cuando el grafo crece. Al sitio donde se ensamblan las piezas (aquí `Program.cs`) se le llama **raíz de composición**, y es el único lugar donde se permite conocer clases concretas de todas las capas.

### El test con un fake escrito a mano

Un *fake* es una implementación sencilla de la interfaz, hecha para el test. Este devuelve el resultado que se le pide y apunta cada llamada:

```csharp
public class PasarelaPagoFalsa(bool resultado) : IPasarelaPago
{
    public List<(decimal Importe, string Tarjeta)> Cobros { get; } = [];

    public Task<bool> Cobrar(decimal importe, string tarjeta)
    {
        Cobros.Add((importe, tarjeta));
        return Task.FromResult(resultado);
    }
}

public class ConfirmarPedidoTests
{
    [Fact]
    public async Task Pago_rechazado_no_marca_el_pedido_como_pagado()
    {
        var pasarela = new PasarelaPagoFalsa(resultado: false);
        var caso = new ConfirmarPedido(pasarela);
        var pedido = new Pedido { Id = 4711, Tarjeta = "tok_visa" };
        pedido.Lineas.Add(new LineaPedido { Precio = 25m, Cantidad = 2 });

        var resultado = await caso.Ejecutar(pedido);

        Assert.Equal(ConfirmarPedidoResultado.PagoRechazado, resultado);
        Assert.False(pedido.Pagado);
        Assert.Single(pasarela.Cobros);
        Assert.Equal(50m, pasarela.Cobros[0].Importe);
    }
}
```

El test no toca la red, no necesita credenciales y tarda milisegundos (verificado con xunit en .NET 10). Comprueba tres cosas: el resultado devuelto, que el pedido no queda pagado y que se intentó cobrar exactamente una vez, por 50 (2 × 25). Cambiando `resultado: true` se prueba el camino feliz con el mismo fake. Para este tipo de comprobaciones, un fake de diez líneas suele ser más legible que una librería de *mocking* con su configuración.

## Quién es dueño de la interfaz

Lo que de verdad invierte la flecha no es que exista una interfaz, sino **dónde se declara**. Si `IPasarelaPago` viviera en `Tienda.Infraestructura`, junto a Stripe, el caso de uso seguiría dependiendo de la infraestructura; la interfaz sería solo una capa de pintura.

```
SIN INVERSIÓN                          CON INVERSIÓN

Tienda.Aplicacion                      Tienda.Aplicacion
 (ConfirmarPedido)                      (ConfirmarPedido + IPasarelaPago)
        |                                      ^
        | referencia                           | referencia
        v                                      |
Tienda.Infraestructura                 Tienda.Infraestructura
 (PasarelaStripe)                       (PasarelaStripe : IPasarelaPago)
```

En el esquema de la izquierda, el flujo de ejecución (el caso de uso llama a Stripe) y la dependencia de código apuntan en el mismo sentido. A la derecha la ejecución sigue yendo del caso de uso a Stripe, pero la referencia entre proyectos va en sentido contrario: eso es lo que se ha invertido. La regla es que **el consumidor es dueño del contrato**: la interfaz se escribe según lo que el consumidor necesita, no según lo que el proveedor ofrece.

Por qué las dependencias deben apuntar hacia dentro y cómo se vigila con tests de arquitectura se desarrolla en [Regla de Dependencia](Regla-de-Dependencia.md). Cómo se llama cada pieza en el vocabulario hexagonal está en [Puertos y Adaptadores](Puertos-y-Adaptadores.md).

## Lifetimes del contenedor

Al registrar un servicio hay que decidir cuánto vive cada instancia:

| Lifetime | Instancias | Uso típico |
|---|---|---|
| `Transient` | Una nueva cada vez que se pide | Clases sin estado y baratas |
| `Scoped` | Una por ámbito (en ASP.NET Core, una por petición HTTP) | Repositorios, `DbContext`, casos de uso |
| `Singleton` | Una para toda la vida de la aplicación | Cachés, clientes HTTP configurados, estado compartido y seguro entre hilos |

El error clásico es la ***captive dependency***: un servicio de vida larga que recibe uno de vida corta. La instancia de vida corta queda «cautiva» y vive tanto como su captor.

```csharp
builder.Services.AddScoped<IPasarelaPago, PasarelaStripe>();
builder.Services.AddSingleton<ConfirmarPedido>();   // ❌ Singleton que consume un Scoped
```

`ConfirmarPedido` se crea una sola vez, con la primera `PasarelaStripe` que se construya, y la conserva para siempre. Si esa dependencia arrastra algo de la petición (el `DbContext`, el usuario autenticado), todas las peticiones siguientes compartirán datos con la primera, y un `DbContext` no es seguro entre hilos. En la demo funciona; en producción mezcla usuarios.

En entorno `Development`, ASP.NET Core activa por defecto la validación de ámbitos (`ValidateScopes`) y la aplicación ni arranca. Mensaje real obtenido con .NET 10:

```
System.AggregateException: Some services are not able to be constructed (Error while validating
the service descriptor 'ServiceType: ConfirmarPedido Lifetime: Singleton ImplementationType:
ConfirmarPedido': Cannot consume scoped service 'IPasarelaPago' from singleton 'ConfirmarPedido'.)
```

En producción esa validación no está activa por defecto, así que el error se manifiesta como datos cruzados, no como excepción. La regla práctica: un servicio solo puede depender de otros con su mismo lifetime o más largo (`Transient` y `Scoped` pueden consumir `Singleton`, nunca al revés). Quien necesite un `Scoped` desde un `Singleton` (un servicio en segundo plano, por ejemplo) debe abrir un ámbito propio con `IServiceScopeFactory` en cada ejecución.

## ¿Interfaz o clase concreta?

No todo merece una interfaz. Se crea cuando hay algo que aislar, no por costumbre:

| Situación | ¿Interfaz? | Por qué |
|---|---|---|
| Frontera entre capas (el caso de uso necesita guardar pedidos) | Sí | Es la inversión en sí: `IRepositorioPedidos` la define el centro |
| Entrada/salida y red: pasarela de pago, correo, API externa, disco | Sí | Lentos, con coste o impredecibles; los tests necesitan un sustituto |
| El reloj (`DateTime.UtcNow`) | Sí (`TimeProvider` ya viene en .NET) | Sin él, no se puede probar «un pedido pendiente más de 24 h se cancela» |
| Aleatoriedad, generadores de identificadores | Sí | Un test no puede depender de un valor distinto en cada ejecución |
| Clase interna pura (calcular el total, aplicar un descuento) | No | Es determinista y rápida; se prueba tal cual |
| Entidades y objetos de valor (`Pedido`, `Cliente`) | No | Son el negocio; no se sustituyen |
| Clase con una sola implementación que nadie más consumirá | No (por ahora) | Extraer la interfaz cuando aparezca la segunda necesidad cuesta poco |

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Cada clase tiene su `IAlgo` con los mismos métodos y una única implementación | **Interfaz espejo 1:1**: se ha extraído la interfaz de la clase, no de una necesidad del consumidor. No abstrae nada: duplica el código y obliga a editar dos ficheros por cambio |
| `IPasarelaPago` devuelve `StripeCharge` o lanza `StripeException`, y cambiar de proveedor rompe a los consumidores | **Interfaz que filtra tipos del proveedor**: el contrato se diseñó mirando al SDK. Debe devolver tipos del negocio y traducir fallos en la implementación (ver [Capa de Infraestructura](Capa-de-Infraestructura.md)) |
| Un caso de uso pide `IServiceProvider` y hace `GetRequiredService<IPasarelaPago>()` | ***Service locator* escondido**: las dependencias reales ya no se ven en el constructor, los tests no saben qué preparar y los errores de registro saltan en ejecución, no al arrancar |
| El constructor de un caso de uso recibe 8 dependencias | **Caso de uso demasiado grande**: hace varias cosas. La solución es dividirlo (`ConfirmarPedido`, `CancelarPedido`), no agrupar dependencias en un `IServiciosVarios` (ver [Casos de Uso](Casos-de-Uso.md)) |
| Todo funciona en local y en producción los usuarios ven datos de otros | *Captive dependency*: un `Singleton` conserva una dependencia `Scoped`; con `ValidateScopes` desactivado no hay excepción |
| `InvalidOperationException: Unable to resolve service for type 'IPasarelaPago'` al ejecutar | La interfaz está declarada pero falta el `Add...` en `Program.cs`, o se registró en otro contenedor |

## Buenas prácticas avanzadas

- **Diseña la interfaz desde la necesidad del negocio, no calcando al proveedor.** Si `IPasarelaPago` tiene un método `CrearIntentoDePago` y devuelve los objetos del SDK, no has invertido nada: le has puesto un disfraz a Stripe. El contrato dice `Cobrar(importe, tarjeta)`; traducirlo a lo que pida el proveedor es trabajo de la implementación.
- **Prueba del algodón: ¿se podría implementar con un diccionario en memoria sin cambiar la firma?** Una interfaz que expone `DbConnection`, `HttpResponseMessage` o excepciones del proveedor arrastra la tecnología al centro. `IRepositorioPedidos` pasa la prueba (un `Dictionary<int, Pedido>` lo implementa); uno que devuelve `IQueryable<Pedido>` no la pasa, porque el consumidor queda atado al proveedor de LINQ.
- **Interfaces pequeñas por rol, no espejos de la clase.** Si un consumidor solo lee pedidos, no necesita ver `Guardar`. Cortar por lo que cada consumidor necesita hace los fakes triviales y los cambios, locales; una interfaz de quince métodos obliga a escribir quince métodos en cada fake.
- **Activa `ValidateScopes` y `ValidateOnBuild` también en los tests de integración y en el arranque de CI.** Por defecto solo `ValidateScopes` está activo en `Development`; con `builder.Host.UseDefaultServiceProvider(o => { o.ValidateScopes = true; o.ValidateOnBuild = true; })` se detectan en el arranque tanto las *captive dependencies* como las interfaces sin registrar, en lugar de descubrirlas en la primera petición que las use.
- **Una sola raíz de composición.** Los `new` de clases con dependencias se concentran en `Program.cs` (o en métodos de extensión como `AddInfraestructura()` que él invoca). Un `new PasarelaStripe()` en mitad de un caso de uso, o un `static` que guarda el contenedor, reintroducen la dependencia que se había eliminado.
- **El fake sustituye en el test lo que está en la frontera, no lo que hay dentro.** Sustituir `IPasarelaPago` es sano; sustituir también `Pedido` o el cálculo del total hace que el test compruebe el fake, no el comportamiento. Para comprobar que la implementación real cumple el contrato, usa tests de contrato contra ella (ver [Puertos y Adaptadores](Puertos-y-Adaptadores.md)).

## Documentación oficial

- [Dependency injection en .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection) — la referencia del contenedor: lifetimes, registro y validación de ámbitos. Empieza por la sección de lifetimes de servicio.
- [Directrices de inyección de dependencias](https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection-guidelines) — captive dependencies, *service locator* y cuándo resolver manualmente. Útil cuando un servicio en segundo plano necesita un `Scoped`.
- [Dependency injection en ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/dependency-injection) — cómo se integra el contenedor con controladores, endpoints mínimos y la validación en `Development`.

---

*En resumen: el centro define la interfaz que necesita, la infraestructura la cumple y `Program.cs` las une; así la flecha apunta hacia dentro y el negocio se prueba sin cobrar a nadie.*
