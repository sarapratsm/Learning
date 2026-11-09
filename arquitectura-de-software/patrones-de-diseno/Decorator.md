# Decorator

## ¿Qué es?

Decorator es un patrón de diseño clásico (GoF) que añade comportamiento a un objeto envolviéndolo con otro que implementa **la misma interfaz**: el decorador añade su parte, delega el resto en el objeto envuelto y quien lo usa no nota la diferencia. No modifica la clase original ni recurre a la herencia.

## ¿Por qué existe?

Una tienda online guarda y lee pedidos a través de un puerto, `IRepositorioPedidos`, que implementa `RepositorioPedidosSql`. Con el tiempo hacen falta tres capacidades alrededor de ese acceso: **caché** (leer el pedido #4711 diez veces no debería lanzar diez `SELECT`), **registro** de las llamadas y **reintentos** ante fallos transitorios. Hay dos formas ingenuas de añadirlas.

```csharp
// ❌ La lógica transversal dentro de la implementación real
public sealed class RepositorioPedidosSql(TiendaDbContext db, IMemoryCache cache, ILogger<RepositorioPedidosSql> log)
    : IRepositorioPedidos
{
    public async Task<Pedido?> ObtenerPorId(int id, CancellationToken ct)
    {
        log.LogInformation("ObtenerPorId({Id})", id);
        if (cache.TryGetValue(id, out Pedido? enCache)) return enCache;
        // ...reintentos, SELECT, rellenar la caché...
    }
    // La clase mezcla acceso a datos, caché, registro y reintentos: cuatro motivos para cambiar.
}

// ❌ Una subclase por combinación
public class RepositorioPedidosSqlConCache : RepositorioPedidosSql { /* ... */ }
public class RepositorioPedidosSqlConLog : RepositorioPedidosSql { /* ... */ }
public class RepositorioPedidosSqlConCacheYLog : RepositorioPedidosSql { /* ... */ }
```

La primera mezcla responsabilidades y obliga a probar la caché con una base de datos. La segunda no escala: con **3 capacidades** hay 7 combinaciones no vacías (3 individuales, 3 parejas y 1 trío), es decir, 7 subclases; y si el orden de aplicación importa (ver más abajo), son 15 (3 + 6 + 6). Una cuarta capacidad lleva a 15 combinaciones o 64 órdenes.

```csharp
// ✅ Cada capacidad es una clase; se combinan sin tocar ninguna
IRepositorioPedidos repo =
    new RepositorioPedidosConLog(
        new RepositorioPedidosConCache(
            new RepositorioPedidosSql(...)));
```

> Analogía: una carta que se mete en un sobre, y el sobre en otro con acuse de recibo. El contenido no cambia; cada envoltorio añade un servicio y quien recibe el paquete exterior puede tratarlo igual que la carta.

## ¿Cuándo y para qué se usa?

Siempre que haya que sumar una capacidad transversal a una pieza ya existente sin modificarla ni heredar de ella: caché de un repositorio, registro y medición de las llamadas a una pasarela de pago, reintentos sobre un cliente remoto, validación o transacción alrededor de un caso de uso. Su terreno natural son los **puertos** de [Puertos y Adaptadores](../clean-architecture/Puertos-y-Adaptadores.md): como el consumidor depende de la interfaz, se puede envolver la implementación sin que lo sepa.

## La forma completa

Cuatro piezas: la interfaz, la implementación real, y los decoradores, que reciben **otra** `IRepositorioPedidos` por constructor. (`Pedido` se reduce aquí a lo mínimo para que el ejemplo compile por sí solo; en la tienda es la entidad del dominio.)

```csharp
public sealed record Pedido(int Id, string Estado);

public interface IRepositorioPedidos
{
    Task<Pedido?> ObtenerPorId(int id, CancellationToken ct);
    Task Guardar(Pedido pedido, CancellationToken ct);
}

public sealed class RepositorioPedidosSql : IRepositorioPedidos
{
    private readonly Dictionary<int, string> _filas = new() { [4711] = "Borrador" };

    public Task<Pedido?> ObtenerPorId(int id, CancellationToken ct)
    {
        Console.WriteLine($"   [SQL] SELECT pedido {id}");
        return Task.FromResult(_filas.TryGetValue(id, out var e) ? new Pedido(id, e) : null);
    }

    public Task Guardar(Pedido pedido, CancellationToken ct)
    {
        Console.WriteLine($"   [SQL] UPDATE pedido {pedido.Id} -> {pedido.Estado}");
        _filas[pedido.Id] = pedido.Estado;
        return Task.CompletedTask;
    }
}

public sealed class RepositorioPedidosConLog(IRepositorioPedidos interno, ILogger<RepositorioPedidosConLog> log)
    : IRepositorioPedidos
{
    public async Task<Pedido?> ObtenerPorId(int id, CancellationToken ct)
    {
        log.LogInformation("ObtenerPorId({Id})", id);
        var pedido = await interno.ObtenerPorId(id, ct);
        log.LogInformation("ObtenerPorId({Id}) -> {Estado}", id, pedido?.Estado ?? "no existe");
        return pedido;
    }

    public async Task Guardar(Pedido pedido, CancellationToken ct)
    {
        log.LogInformation("Guardar({Id}, {Estado})", pedido.Id, pedido.Estado);
        await interno.Guardar(pedido, ct);
    }
}

public sealed class RepositorioPedidosConCache(IRepositorioPedidos interno, IMemoryCache cache)
    : IRepositorioPedidos
{
    public async Task<Pedido?> ObtenerPorId(int id, CancellationToken ct)
    {
        if (cache.TryGetValue(id, out Pedido? enCache))
            return enCache;

        var pedido = await interno.ObtenerPorId(id, ct);
        if (pedido is not null)
            cache.Set(id, pedido, TimeSpan.FromMinutes(5));
        return pedido;
    }

    public async Task Guardar(Pedido pedido, CancellationToken ct)
    {
        await interno.Guardar(pedido, ct);
        cache.Remove(pedido.Id);   // ver «La trampa de la caché»
    }
}
```

Cada decorador solo conoce la interfaz, no qué hay debajo: puede envolver a `RepositorioPedidosSql`, a otro decorador o a un doble de pruebas. Se apilan a mano, de dentro hacia fuera:

```csharp
IRepositorioPedidos repo =
    new RepositorioPedidosConLog(
        new RepositorioPedidosConCache(
            new RepositorioPedidosSql(), cache),
        logger);

await repo.ObtenerPorId(4711, ct);   // 1.ª lectura
await repo.ObtenerPorId(4711, ct);   // 2.ª lectura
```

Salida real (compilado y ejecutado con .NET 10):

```
info: RepositorioPedidosConLog[0] ObtenerPorId(4711)
   [SQL] SELECT pedido 4711
info: RepositorioPedidosConLog[0] ObtenerPorId(4711) -> Borrador
info: RepositorioPedidosConLog[0] ObtenerPorId(4711)
info: RepositorioPedidosConLog[0] ObtenerPorId(4711) -> Borrador
```

La llamada atraviesa las capas de fuera adentro: el registro (la capa más externa) ve ambas lecturas, la caché responde la segunda y solo la primera llega a SQL. En `new A(new B(new C()))`, `A` se ejecuta primero.

## El orden importa

Si la caché envuelve al registro en lugar de al revés, el mismo código se comporta distinto:

```csharp
new RepositorioPedidosConCache(
    new RepositorioPedidosConLog(new RepositorioPedidosSql(), logger), cache);
```

```
   [SQL] SELECT pedido 4711
info: RepositorioPedidosConLog[0] ObtenerPorId(4711)
info: RepositorioPedidosConLog[0] ObtenerPorId(4711) -> Borrador
```

| Cadena (de fuera adentro) | Qué registra | Para qué sirve |
|---|---|---|
| Registro → Caché → SQL | Las 2 lecturas, incluida la que la caché responde sola | Auditar todo lo que pide el consumidor |
| Caché → Registro → SQL | Solo la lectura que llega a la base de datos | Medir cuánto trabajo real se hace; el registro no ve los aciertos de caché |

No hay un orden correcto en abstracto: depende de qué debe ver cada capa. Con los reintentos pasa igual: un reintento por fuera de la medición cuenta el tiempo total; por dentro, cada intento por separado. El orden se decide y se documenta en el punto donde se compone la cadena.

## Registro en inyección de dependencias

**A mano, con una lambda.** Es la opción sin dependencias: se registra la interfaz con una fábrica que construye la cadena.

```csharp
services.AddSingleton<RepositorioPedidosSql>();
services.AddSingleton<IRepositorioPedidos>(sp =>
    new RepositorioPedidosConLog(
        new RepositorioPedidosConCache(
            sp.GetRequiredService<RepositorioPedidosSql>(),
            sp.GetRequiredService<IMemoryCache>()),
        sp.GetRequiredService<ILogger<RepositorioPedidosConLog>>()));
```

**Con [Scrutor](https://github.com/khellang/Scrutor)** (paquete NuGet `Scrutor`, versión 7.0.0 al probarlo). `Decorate<TService, TDecorator>` sustituye el registro existente de `TService` por un decorador que recibe el anterior en su constructor; el contenedor resuelve el resto de parámetros. **La última llamada a `Decorate` es la capa más externa.**

```csharp
services.AddSingleton<IRepositorioPedidos, RepositorioPedidosSql>();
services.Decorate<IRepositorioPedidos, RepositorioPedidosConCache>();   // envuelve al SQL
services.Decorate<IRepositorioPedidos, RepositorioPedidosConLog>();     // envuelve a la caché
```

Resolver `IRepositorioPedidos` devuelve un `RepositorioPedidosConLog`, y las dos lecturas producen exactamente la salida de la cadena Registro → Caché → SQL de arriba (comprobado).

**Sin librería, con `ActivatorUtilities`.** `ActivatorUtilities.CreateInstance<T>(sp, args)` construye `T` resolviendo del contenedor los parámetros del constructor y usando los `args` para los que se pasan a mano (aquí, el objeto envuelto):

```csharp
services.AddSingleton<RepositorioPedidosSql>();
services.AddSingleton<IRepositorioPedidos>(sp =>
{
    IRepositorioPedidos r = sp.GetRequiredService<RepositorioPedidosSql>();
    r = ActivatorUtilities.CreateInstance<RepositorioPedidosConCache>(sp, r);
    return ActivatorUtilities.CreateInstance<RepositorioPedidosConLog>(sp, r);
});
```

Evita escribir cada `GetRequiredService` y sigue sin dependencias externas. Con muchos servicios conviene Scrutor, que además conserva el ciclo de vida del registro original.

## Decorar un puerto de salida o un caso de uso

El mismo patrón sirve en dos sitios con propósito distinto.

| | Puerto de salida (`IRepositorioPedidos`, `IPasarelaPago`) | Caso de uso (`ConfirmarPedido`) |
|---|---|---|
| Qué se envuelve | La salida hacia el exterior | La entrada a la aplicación |
| Capacidades típicas | Caché, medición, reintentos, registro de llamadas | Registro, transacción, validación del comando |
| Dónde vive el decorador | `Tienda.Infraestructura` (conoce tecnología) | `Tienda.Aplicacion` (no debe conocerla) |

Un decorador de medición sobre la pasarela:

```csharp
public interface IPasarelaPago
{
    Task<bool> Cobrar(decimal importe, string tokenTarjeta, string claveIdempotencia);
}

public sealed class PasarelaPagoMedida(IPasarelaPago interna) : IPasarelaPago
{
    public async Task<bool> Cobrar(decimal importe, string tokenTarjeta, string claveIdempotencia)
    {
        var reloj = Stopwatch.StartNew();
        try
        {
            return await interna.Cobrar(importe, tokenTarjeta, claveIdempotencia);
        }
        finally
        {
            Console.WriteLine($"Cobrar({importe}, clave={claveIdempotencia}) tardó {reloj.ElapsedMilliseconds} ms");
        }
    }
}
```

Los decoradores transversales de casos de uso (registro, transacción, validación) se tratan en [Casos de Uso](../clean-architecture/Casos-de-Uso.md); con MediatR los hace el *pipeline* de *behaviors* sin escribir un decorador por caso de uso, ver [MediatR](MediatR.md).

### Reintentos

Un decorador de reintentos es técnicamente trivial (un bucle alrededor de `interna.Cobrar`), pero para llamadas HTTP casi nunca hace falta escribirlo: la resiliencia de `HttpClient` ya aporta reintentos, tiempo límite y *circuit breaker*, y vive en la infraestructura. Esa política está en [Capa de Infraestructura](../clean-architecture/Capa-de-Infraestructura.md). Allí también se explica el riesgo principal: **reintentar una operación no idempotente** (un cobro) puede ejecutarla dos veces. Cualquier decorador de reintentos debe aplicarse solo a operaciones idempotentes o propagar una clave de idempotencia estable.

## Decorator frente a Proxy, Adapter y herencia

Los tres envuelven un objeto; la diferencia está en la intención.

| | Interfaz que expone | Intención | Ejemplo en la tienda |
|---|---|---|---|
| **Decorator** | La misma que el objeto envuelto | Añadir comportamiento, apilable | `RepositorioPedidosConCache` |
| **Proxy** | La misma | Controlar el acceso al objeto (carga perezosa, permisos, acceso remoto) | Un repositorio que decide si crea el real |
| **Adapter** | **Distinta** de la del objeto envuelto | Traducir una interfaz a otra | `PasarelaPagoHttp` que adapta la API del proveedor a `IPasarelaPago` |
| **Herencia** | La de la clase base | Especializar en tiempo de compilación | `RepositorioPedidosSqlConCache` |

Decorator y Proxy son estructuralmente casi idénticos; se distinguen por el propósito. A diferencia de la herencia, el decorador se elige y se combina en tiempo de ejecución, y funciona aunque la clase original sea `sealed`.

## La trampa de la caché

Una caché que no se invalida sirve datos viejos. Este decorador solo guarda en `ObtenerPorId` y delega `Guardar` sin más:

```csharp
public sealed class RepositorioPedidosConCacheSinInvalidar(IRepositorioPedidos interno, IMemoryCache cache)
    : IRepositorioPedidos
{
    public async Task<Pedido?> ObtenerPorId(int id, CancellationToken ct)
    {
        if (cache.TryGetValue(id, out Pedido? enCache)) return enCache;
        var pedido = await interno.ObtenerPorId(id, ct);
        if (pedido is not null) cache.Set(id, pedido, TimeSpan.FromMinutes(5));
        return pedido;
    }

    public Task Guardar(Pedido pedido, CancellationToken ct) => interno.Guardar(pedido, ct);   // ❌
}
```

Se lee el pedido #4711, se confirma y se vuelve a leer:

```
   [SQL] SELECT pedido 4711
Borrador
   [SQL] UPDATE pedido 4711 -> Confirmado
Borrador          <- ❌ pedido obsoleto: la base de datos dice Confirmado
```

Con `cache.Remove(pedido.Id)` tras `Guardar` (como en `RepositorioPedidosConCache` de arriba) la segunda lectura vuelve a SQL y devuelve `Confirmado`:

```
   [SQL] SELECT pedido 4711
Borrador
   [SQL] UPDATE pedido 4711 -> Confirmado
   [SQL] SELECT pedido 4711
Confirmado
```

Es la regla general: **toda operación de escritura que afecte a lo cacheado debe invalidarlo**, y el decorador tiene que conocer qué claves afecta cada escritura. Si algo ajeno al decorador modifica la tabla (otro servicio, un script), la caché local no se entera. Estrategias de expiración, invalidación y caché distribuida están en [Caching](../../bases-de-datos/caching/README.md).

## Decoradores genéricos

Con muchas interfaces (veinte repositorios, treinta casos de uso) escribir un decorador por cada una es repetitivo. Si todas comparten una forma (por ejemplo `IManejador<TComando>`), un único decorador genérico `RegistroDe<TComando>` las cubre. Para interfaces heterogéneas existen los interceptores o proxies dinámicos (programación orientada a aspectos, AOP), que generan el decorador en ejecución; ganan en reutilización y pierden en claridad (la cadena ya no se lee en el código) y en depuración. Hasta que la repetición duela, los decoradores escritos a mano son más fáciles de seguir.

## Cuándo no usar Decorator

- **Una sola capacidad que nunca se combina.** Si solo hay un registro y no habrá más, una clase con la capacidad dentro (o la inyección directa de `ILogger`) es más simple que un decorador.
- **Hace falta acceder a miembros que no están en la interfaz.** Un decorador solo ve el contrato. Si el consumidor necesita un método extra de `RepositorioPedidosSql`, lo que hay detrás de la interfaz ya no es sustituible: la interfaz es demasiado pobre o el consumidor depende de la implementación.
- **La capacidad ya la ofrece el framework.** Para HTTP, el *middleware* de ASP.NET y la resiliencia de `HttpClient`; para casos de uso con MediatR, los *behaviors*.
- **La preocupación cambia el significado de la operación.** Si lo que se añade altera el resultado (no solo lo observa o lo acelera), el decorador engaña al consumidor; ver el primer error de la tabla siguiente.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| El consumidor recibe resultados distintos con y sin decorador | El decorador cambia la semántica del contrato: traga excepciones, devuelve `null` en lugar de lanzar, o recorta datos. Un decorador puede añadir, no reinterpretar |
| El registro no ve las lecturas que responde la caché, o la medición incluye aciertos de caché | Orden de la cadena equivocado: la capa se compuso por dentro o por fuera de lo que debía observar |
| Datos obsoletos tras guardar | La caché no se invalida en las escrituras |
| Valores de un usuario aparecen en la respuesta de otro | Decorador registrado como *singleton* con estado compartido por petición (campos con el usuario, el pedido o la transacción actuales). Un decorador singleton no debe guardar estado de una llamada |
| Una operación nueva de la interfaz no pasa por el decorador | Al añadir un miembro a la interfaz, el decorador no lo reenvía: normalmente no compila, salvo que el miembro tenga implementación por defecto o el decorador herede de una base con métodos virtuales, y entonces la nueva operación se salta la caché o el registro en silencio |

## Buenas prácticas avanzadas

- **Un decorador, una responsabilidad.** Un `RepositorioPedidosConCacheYLog` reproduce la explosión de clases dentro de una sola. Si hacen falta las dos, son dos decoradores.
- **Registra la cadena en un único sitio del contenedor** (una extensión como `AddRepositorioPedidos()`), no la construyas a mano en cada consumidor: quién envuelve a quién no debe estar disperso.
- **Documenta el orden en el punto de registro.** No se deduce leyendo cada decorador por separado, y cambiarlo cambia lo que se registra, se mide y se reintenta.
- **Decora el puerto, no la clase concreta.** Si el consumidor depende de `RepositorioPedidosSql`, ningún decorador podrá entrar. Depende de la interfaz.
- **Prueba cada decorador aislado con un doble de la interfaz** (que cuente llamadas), sin base de datos, y prueba la cadena completa una vez para fijar el orden.
- **Cuida los métodos que añades a la interfaz.** Cada miembro nuevo implica revisar todos los decoradores: ninguno debe quedarse sin reenviarlo ni, si es una escritura, sin invalidar lo que corresponda.

## Documentación oficial

- [Decorator (Refactoring.Guru)](https://refactoring.guru/design-patterns/decorator): descripción del patrón con diagramas y variantes; para ver la estructura general antes de implementarlo.
- [Scrutor](https://github.com/khellang/Scrutor): README con `Decorate` y el escaneo de ensamblados; para registrar cadenas de decoradores en el contenedor de DI.
- [`ActivatorUtilities` (Microsoft Learn)](https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.dependencyinjection.activatorutilities): referencia de `CreateInstance`, útil para componer decoradores sin librerías.
- [Inyección de dependencias en .NET (Microsoft Learn)](https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection): ciclos de vida (*singleton*, *scoped*, *transient*) que condicionan qué estado puede tener un decorador.

## Recursos didácticos

- *Design Patterns: Elements of Reusable Object-Oriented Software* (Gamma, Helm, Johnson, Vlissides, 1994): el catálogo GoF donde se define Decorator; sin enlace verificado.

---
*En resumen: Decorator añade capacidades envolviendo una pieza con otras que comparten su interfaz, de modo que caché, registro y reintentos se combinan en cualquier orden sin tocar la implementación ni multiplicar subclases; el orden y la invalidación de la caché son lo que hay que vigilar.*
