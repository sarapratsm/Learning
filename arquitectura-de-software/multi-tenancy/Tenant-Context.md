# Tenant Context

## ¿Qué es?

El *tenant context* es el objeto que guarda «el tenant de la petición actual» (o de la unidad de trabajo en curso) y lo deja disponible para todas las capas del código sin pasarlo a mano por cada método. Lo rellena un único punto de entrada, normalmente el middleware que resuelve el tenant, y lo leen muchos.

## ¿Por qué existe?

En una aplicación SaaS de gestión de pedidos con las empresas clientes `acme` y `globex` (los *tenants*), casi todo el código necesita saber de quién son los datos: el repositorio que consulta pedidos, el servicio que aplica el plan contratado, el generador de facturas. El middleware averigua el tenant una vez al empezar la petición ([cómo se resuelve está en Identificacion-del-Tenant.md](Identificacion-del-Tenant.md)); el contexto es dónde queda guardado el resultado.

La alternativa es pasar `tenantId` como parámetro por todas las llamadas, y ahí aparece el peligro: basta con que un método olvide recibirlo, o que una consulta olvide usarlo, para que devuelva datos de todos los tenants.

```csharp
// ❌ El tenant viaja a mano: cada método y cada consulta deben acordarse
public class OrderService(IOrderRepository repo)
{
    public List<Order> ListOrders(string tenantId) => repo.GetAll(tenantId);
    public Order? GetOrder(int id) => repo.GetById(id);          // se olvidó tenantId: devuelve el pedido 3 a quien pregunte
}

// ✅ El tenant se lee del contexto: ningún método de negocio lo recibe ni puede omitirlo
public class OrderService(IOrderRepository repo)
{
    public List<Order> ListOrders() => repo.GetAll();
    public Order? GetOrder(int id) => repo.GetById(id);          // el repositorio filtra con el tenant del contexto
}
```

El contexto no elimina el riesgo de fuga (un repositorio puede seguir sin filtrar, y de eso se ocupa [Aislamiento-por-Fila.md](Aislamiento-por-Fila.md)), pero quita de las firmas un parámetro que todo el mundo debe acordarse de pasar y de usar.

> Si conoces la inyección de dependencias, piensa en el contexto como un servicio con vida «por petición» (*scoped*): cada petición recibe su propia instancia, que cualquier clase puede pedir en su constructor.

## ¿Cuándo y para qué se usa?

Lo consulta cualquier código que dependa del tenant: repositorios que filtran por `TenantId`, la fábrica que elige la cadena de conexión de la base del tenant, la lógica que aplica límites según su plan, el logger que añade el tenant a cada línea. Lo escribe un único sitio por unidad de trabajo: el middleware en una petición HTTP, o el código que arranca un trabajo en segundo plano. La tabla de decisión de más abajo compara esta opción con las otras dos que existen (`AsyncLocal` y parámetro explícito).

## El contrato mínimo

El contrato que ven las capas es de lectura:

```csharp
public interface ITenantContext
{
    string TenantId { get; }   // lanza TenantNotResolvedException si no hay tenant
}
```

Con un `string` basta para el ejemplo (aquí, el subdominio); una aplicación real suele exponer un identificador estable y, si lo necesita, el objeto `Tenant` entero.

### Qué pasa cuando no hay tenant

Si el contexto no se ha rellenado, `TenantId` **lanza una excepción**; no devuelve `null`, ni una cadena vacía, ni un tenant por defecto:

```csharp
public sealed class TenantNotResolvedException()
    : InvalidOperationException("No hay tenant en el contexto actual. ¿Falta el middleware o el scope de la unidad de trabajo?");
```

La razón es lo que ocurre con las alternativas. Un `null` o un `""` se propagan hasta una consulta que filtra por `TenantId == ""` (cero resultados y un bug difícil de explicar) o, si el filtro se compone mal, hasta una consulta que no filtra. Un tenant «por defecto» es peor: los datos de una petición sin identificar acaban mezclados con los de un cliente real. La excepción apunta al punto exacto donde falta el contexto y convierte un fallo de aislamiento (silencioso, grave) en un error 500 (ruidoso, corregible).

### Quién escribe

La escritura va en una interfaz aparte, que solo conoce el punto de entrada:

```csharp
public interface ITenantContextSetter
{
    void Set(string tenantId);
}
```

La implementación guarda el valor y rechaza un segundo `Set`:

```csharp
public sealed class TenantContext : ITenantContext, ITenantContextSetter
{
    private string? _tenantId;

    public string TenantId => _tenantId ?? throw new TenantNotResolvedException();

    public void Set(string tenantId)
    {
        if (_tenantId is not null)
            throw new InvalidOperationException($"El contexto ya tiene tenant ('{_tenantId}').");
        _tenantId = tenantId;
    }
}
```

## Contexto `Scoped` en ASP.NET Core

### Registro y middleware

Las tres interfaces deben resolver **la misma instancia dentro de cada scope**; por eso las dos interfaces se registran delegando en el tipo concreto:

```csharp
builder.Services.AddScoped<TenantContext>();
builder.Services.AddScoped<ITenantContext>(sp => sp.GetRequiredService<TenantContext>());
builder.Services.AddScoped<ITenantContextSetter>(sp => sp.GetRequiredService<TenantContext>());
builder.Services.AddScoped<IOrderRepository, OrderRepository>();
builder.Services.AddScoped<OrderService>();
```

Si se registraran con `AddScoped<ITenantContext, TenantContext>()` y `AddScoped<ITenantContextSetter, TenantContext>()` por separado, el contenedor crearía dos objetos distintos: el middleware escribiría en uno y el repositorio leería de otro, que siempre estaría vacío.

El middleware rellena el contexto con el resultado de la resolución. Aquí se simplifica a «primer segmento del `Host`»; la resolución real (validar que el tenant existe y está activo, rechazar el resto) es asunto de [Identificacion-del-Tenant.md](Identificacion-del-Tenant.md):

```csharp
app.Use(async (ctx, next) =>
{
    var subdomain = ctx.Request.Host.Host.Split('.')[0];            // acme.miapp.ejemplo.com -> acme
    ctx.RequestServices.GetRequiredService<ITenantContextSetter>().Set(subdomain);
    await next();
});
```

`ctx.RequestServices` es el scope de la petición: lo que se escribe ahí es lo que verán el servicio y el repositorio de esa misma petición. Cómo se encadenan los middlewares está en [Routing-y-Middleware.md](../../desarrollo-web/de-wpf-a-web/Routing-y-Middleware.md).

### Quien lee no lo pasa

El servicio de aplicación y el repositorio piden `ITenantContext` por constructor y nadie les pasa el tenant:

```csharp
public record Order(int Id, string TenantId, decimal Total);

public class OrderRepository(ITenantContext tenant) : IOrderRepository
{
    private static readonly List<Order> Data =
    [
        new(1, "acme", 120m), new(2, "acme", 80m),
        new(3, "globex", 500m),
    ];

    // Datos en memoria para el ejemplo; con EF Core el filtro lo aplicaría un query filter
    public List<Order> GetAll() => Data.Where(o => o.TenantId == tenant.TenantId).ToList();
}

public class OrderService(IOrderRepository repo, ITenantContext tenant)
{
    public object ListOrders() => new { serviceSees = tenant.TenantId, orders = repo.GetAll() };
}

app.MapGet("/orders", (OrderService s) => s.ListOrders());
```

Con el servidor en marcha, dos peticiones con distinto `Host` (se ejecutó con .NET SDK 10.0.401):

```bash
curl -s -H "Host: acme.miapp.ejemplo.com"   localhost:6431/orders
curl -s -H "Host: globex.miapp.ejemplo.com" localhost:6431/orders
```

```json
{"serviceSees":"acme","orders":[{"id":1,"tenantId":"acme","total":120},{"id":2,"tenantId":"acme","total":80}]}
{"serviceSees":"globex","orders":[{"id":3,"tenantId":"globex","total":500}]}
```

Servicio y repositorio leen el mismo tenant (`serviceSees` lo confirma) y ningún método recibió un `tenantId`.

## Por qué `Scoped`, y no `Singleton` ni estático

Un servicio `Singleton` tiene una única instancia para toda la aplicación; uno `Scoped`, una por scope (en ASP.NET Core, una por petición). El contexto describe algo que cambia en cada petición, así que solo encaja con `Scoped`. La explicación general de los tiempos de vida está en [Inversion-de-Dependencias.md](../clean-architecture/Inversion-de-Dependencias.md).

### El error clásico: un contexto `Singleton`

Un contexto registrado como `Singleton` que «aprovecha» el primer valor (una caché mal pensada, o un `??=`) sirve ese tenant a todas las peticiones siguientes:

```csharp
public sealed class LeakyTenantContext : ITenantContext, ITenantContextSetter
{
    private string? _tenantId;
    public string TenantId => _tenantId ?? throw new TenantNotResolvedException();
    public void Set(string tenantId) => _tenantId ??= tenantId;      // solo conserva el primero
}

builder.Services.AddSingleton<LeakyTenantContext>();
// ... ITenantContext e ITenantContextSetter delegan en ese singleton
```

Dos `curl` seguidos, `acme` primero:

```bash
curl -s -H "Host: acme.miapp.ejemplo.com"   localhost:6418/orders
curl -s -H "Host: globex.miapp.ejemplo.com" localhost:6418/orders
```

```json
{"serviceSees":"acme","orders":[{"id":1,"tenantId":"acme","total":120},{"id":2,"tenantId":"acme","total":80}]}
{"serviceSees":"acme","orders":[{"id":1,"tenantId":"acme","total":120},{"id":2,"tenantId":"acme","total":80}]}
```

La petición de `globex` recibe los pedidos de `acme`. No hay excepción, ni error en el log: es la fuga entre tenants en su forma más limpia. Un contexto mutable compartido entre peticiones simultáneas es además una condición de carrera: dos peticiones pisándose el valor en paralelo.

### La *captive dependency*

El otro camino al mismo error es que un `Singleton` legítimo (una caché, un cliente configurado) reciba el contexto por constructor. El `Singleton` vive para siempre y captura la instancia `Scoped` con la que se creó, que ya no cambia:

```csharp
public class ReportCache(ITenantContext tenant)      // Singleton que consume un Scoped
{
    public string Owner => tenant.TenantId;
}

builder.Services.AddSingleton<ReportCache>();
```

En el entorno `Development`, `WebApplication.CreateBuilder` activa la validación de scopes y de dependencias al construir el contenedor, y la aplicación ni arranca:

```text
Unhandled exception. System.AggregateException: Some services are not able to be constructed
 (Error while validating the service descriptor 'ServiceType: Demo.ReportCache Lifetime: Singleton
  ImplementationType: Demo.ReportCache': Cannot consume scoped service 'Demo.ITenantContext'
  from singleton 'Demo.ReportCache'.)
```

En `Production` esa validación no está activa. Se ejecutó el mismo código con `ASPNETCORE_ENVIRONMENT=Production` y la petición `/report` devolvió `500` con `TenantNotResolvedException`: el singleton había recibido una instancia del scope raíz, donde nadie escribió nunca el tenant. Gracias a que el contexto lanza excepción, el fallo es visible; un contexto que devolviera un tenant por defecto lo habría servido en silencio.

Arreglo: el `Singleton` no recibe el contexto; recibe `IServiceScopeFactory` y resuelve el contexto dentro de un scope en cada uso, o se registra con la vida adecuada (`Scoped`).

### Por qué no una variable estática

Una variable `static` (o `[ThreadStatic]`) es el singleton con otro nombre: una sola copia por proceso, o por hilo. En ASP.NET Core una petición asíncrona puede continuar en un hilo distinto tras cada `await`, de modo que `[ThreadStatic]` pierde el valor, y `static` lo comparte entre todas las peticiones. Ninguna de las dos sirve.

## Fuera de la petición: jobs, consumidores y tareas programadas

Un `BackgroundService`, un consumidor de mensajes o un trabajo programado no nacen de una petición HTTP: no hay middleware que haya rellenado nada, ni scope de petición. El contexto `Scoped` solo existe dentro de un scope, así que el código que arranca la unidad de trabajo debe **crear el scope y rellenar el contexto de forma explícita**, una vez por unidad de trabajo (un mensaje, un pedido, una ejecución):

```csharp
public class Worker(IServiceScopeFactory scopes, ILogger<Worker> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        var jobs = new[] { ("acme", 1), ("globex", 3), ("acme", 2) };   // (tenant, pedido)
        foreach (var (tenantId, orderId) in jobs)
        {
            using var scope = scopes.CreateScope();                       // un scope por trabajo
            scope.ServiceProvider.GetRequiredService<ITenantContextSetter>().Set(tenantId);

            var repo = scope.ServiceProvider.GetRequiredService<IOrderRepository>();
            log.LogInformation("Trabajo del tenant {Tenant}: el repositorio ve {Orders}",
                tenantId, string.Join(",", repo.GetAll().Select(o => $"{o.TenantId}#{o.Id}")));
            await Task.Delay(50, ct);
        }
    }
}
```

Salida del servidor (se ejecutó con `AddHostedService<Worker>()`):

```text
Trabajo del tenant acme: el repositorio ve acme#1,acme#2
Trabajo del tenant globex: el repositorio ve globex#3
Trabajo del tenant acme: el repositorio ve acme#1,acme#2
```

Cada iteración recibe un contexto propio, nuevo y vacío, y el tercer trabajo no hereda nada del segundo. El `using` descarta el scope al terminar la iteración.

### El error de olvidar el scope

Si el job pide el repositorio sin haber rellenado el contexto, el diseño falla de forma ruidosa:

```csharp
using var forgotten = scopes.CreateScope();       // scope sin Set(...)
forgotten.ServiceProvider.GetRequiredService<IOrderRepository>().GetAll();
```

```text
TenantNotResolvedException: No hay tenant en el contexto actual. ¿Falta el middleware o el scope de la unidad de trabajo?
```

El caso peor es inyectar `IOrderRepository` directamente en el constructor del `BackgroundService` (que es `Singleton`): con la validación de scopes de `Development` ni arranca, y sin ella el repositorio queda ligado al scope raíz para siempre.

## `AsyncLocal<T>`: cuando no se puede inyectar

`AsyncLocal<T>` guarda un valor ligado al flujo asíncrono de ejecución: lo heredan las tareas que se lanzan desde ese flujo, pero cada flujo tiene su copia. Se usa cuando el código que necesita el tenant **no puede recibir el servicio por DI**: un método estático, un *interceptor* o un callback de una librería que instancia sus propias clases. En el resto de casos, el servicio inyectado es más explícito y más fácil de probar.

```csharp
public static class AmbientTenant
{
    private static readonly AsyncLocal<string?> _current = new();
    public static string? Current => _current.Value;

    public static IDisposable Use(string tenantId)       // se asigna y se devuelve la limpieza
    {
        var previous = _current.Value;
        _current.Value = tenantId;
        return new Restore(previous);
    }

    private sealed class Restore(string? previous) : IDisposable
    {
        public void Dispose() => _current.Value = previous;
    }
}

using (AmbientTenant.Use("acme"))
{
    await ProcessAsync();          // todo lo que se llame desde aquí ve "acme"
}                                  // al salir, se restaura el valor anterior
```

### La trampa: lo que fluye, y lo que no

Un experimento breve (consola, .NET 10.0.401) con un `AsyncLocal<string?>` muestra qué hace de verdad:

```text
1. Task.Run hereda: acme
2. Tras await SetInside(): acme
3. quien lo lanzó ahora ve: globex
3. bucle de fondo, iteración 0: acme
3. bucle de fondo, iteración 1: acme
3. bucle de fondo, iteración 2: acme
4. job sin establecer tenant, ve: acme
4. job sin establecer tenant, ve: (ninguno)
5. lectores en el mismo hilo que asignó: 158; con valor filtrado: 0
```

Lectura de cada línea:

- **1**: una tarea hija hereda el valor del flujo que la lanzó.
- **2**: un método `async` que asigna `"globex"` lo hace sobre **su copia**; al volver, el llamador sigue viendo `acme`. Asignar dentro de un método `async` auxiliar no cambia el tenant de quien lo llama.
- **3**: una tarea de larga vida lanzada con el valor `acme` sigue viéndolo aunque quien la lanzó cambie después a `globex`. Un bucle de fondo arrancado desde una petición hereda el tenant de **esa** petición para siempre.
- **4**: si nadie lo limpia, el valor sigue ahí para el siguiente trabajo del mismo flujo: un job que olvida asignar el tenant no falla, usa el último.
- **5**: el valor **no** se queda en el hilo del *thread pool*: de 2000 tareas, 158 cayeron en el mismo hilo que había asignado el valor y ninguna lo vio, porque el pool restaura el contexto de ejecución entre elementos de trabajo. El riesgo está en el flujo lógico (líneas 3 y 4), no en el hilo físico.

Por eso el patrón `Use(...)` con `IDisposable` que restaura el valor anterior, y por eso un `AsyncLocal` que lee un valor sin asignar debe fallar (lanzar excepción), no devolver `null` en silencio.

### Tabla de decisión

| Situación | Opción | Motivo |
|---|---|---|
| Código de la aplicación (servicios, repositorios, casos de uso) en una petición | `ITenantContext` `Scoped` | Explícito en el constructor, sustituible en pruebas, falla si falta |
| Job o consumidor propio | `Scoped` con scope creado por unidad de trabajo | Un contexto limpio por mensaje |
| Código que no se construye por DI (estático, callback de librería, interceptor) | `AsyncLocal<T>` con asignación y restauración acotadas | Fluye sin inyección; exige disciplina |
| Función pura o utilidad que solo necesita el dato una vez | Parámetro explícito | Sin magia; solo aceptable en la frontera, no repetido en cada capa |
| Operación que cambia de tenant a propósito | Scope explícito por tenant | Ver siguiente sección |

Un patrón frecuente combina las dos primeras: el `ITenantContext` `Scoped` es la fuente de verdad y, si hace falta, un adaptador copia su valor al `AsyncLocal` solo para el código que no puede inyectarlo.

## Quién puede escribir el contexto

Las capas de negocio reciben `ITenantContext` (solo lectura). `ITenantContextSetter` solo lo conocen el middleware y los puntos de entrada de los jobs, y conviene declararlo en un proyecto que el resto no referencie:

```csharp
public class ConfirmOrder(ITenantContext tenant)
{
    public void Execute()
    {
        var id = tenant.TenantId;      // lectura: lo único que ofrece la interfaz
        // tenant.Set("globex");       // no compila: ITenantContext no tiene Set
    }
}
```

Si la interfaz expusiera `Set` (o `Current` tuviera un `set` público), cualquier caso de uso podría cambiar de tenant a mitad de petición con un descuido, por ejemplo al reutilizar un contexto con el tenant equivocado. Con la interfaz de solo lectura, el compilador lo impide; y como la implementación rechaza un segundo `Set`, el tenant de una petición se fija una sola vez, incluso para quien tenga acceso al setter. Una prueba de arquitectura que prohíba referenciar `ITenantContextSetter` fuera del punto de entrada cubre el resto.

## Cambiar de tenant a propósito

Las operaciones de plataforma (migrar todos los tenants, recalcular una métrica global, «impersonar» a un cliente para dar soporte desde `admin.miapp.ejemplo.com`) necesitan actuar sobre un tenant que no es el de la petición. El patrón es el mismo que el del job: un scope explícito por tenant, con una línea de auditoría que diga quién y a quién:

```csharp
foreach (var tenantId in tenantIds)
{
    using var scope = scopes.CreateScope();
    scope.ServiceProvider.GetRequiredService<ITenantContextSetter>().Set(tenantId);
    log.LogWarning("Operación de plataforma {Operation} por {Admin} sobre el tenant {Tenant}",
        "RecalculateTotals", adminUserId, tenantId);
    await scope.ServiceProvider.GetRequiredService<RecalculateTotals>().ExecuteAsync(ct);
}
```

Cada iteración tiene su contexto y deja rastro. (Mismo mecanismo que el `Worker` ejecutado arriba; este fragmento concreto no se ejecutó.) Lo contrario, un administrador que necesita ver varios tenants a la vez en una sola consulta, se resuelve en la capa de datos con `IgnoreQueryFilters`, restringido a código y a usuarios de plataforma: eso se desarrolla en [Aislamiento-por-Fila.md](Aislamiento-por-Fila.md).

## Probar el contexto

### Con un contexto falso

Como las clases piden `ITenantContext` y no un middleware, una prueba lo sustituye por una implementación mínima:

```csharp
public class FakeTenantContext(string tenantId) : ITenantContext
{
    public string TenantId => tenantId;
}

[Theory]
[InlineData("acme", 2)]
[InlineData("globex", 1)]
public void Repository_returns_only_orders_of_the_context_tenant(string tenant, int expected)
{
    var repo = new OrderRepository(new FakeTenantContext(tenant));

    var orders = repo.GetAll();

    Assert.Equal(expected, orders.Count);
    Assert.All(orders, o => Assert.Equal(tenant, o.TenantId));
}
```

### Probar que un tenant no ve lo del otro

El valor de un contexto `Scoped` está en que dos peticiones simultáneas no se mezclan. La prueba monta el contenedor real con `validateScopes: true`, lanza 200 «peticiones» concurrentes alternando `acme` y `globex`, cede el hilo en mitad de cada una y comprueba que cada resultado pertenece al tenant de su petición:

```csharp
[Fact]
public async Task Concurrent_scopes_never_see_each_others_tenant()
{
    var services = new ServiceCollection();
    services.AddScoped<TenantContext>();
    services.AddScoped<ITenantContext>(sp => sp.GetRequiredService<TenantContext>());
    services.AddScoped<ITenantContextSetter>(sp => sp.GetRequiredService<TenantContext>());
    services.AddScoped<IOrderRepository, OrderRepository>();
    using var provider = services.BuildServiceProvider(validateScopes: true);

    async Task<List<Order>> Request(string tenant)
    {
        using var scope = provider.CreateScope();
        scope.ServiceProvider.GetRequiredService<ITenantContextSetter>().Set(tenant);
        await Task.Delay(Random.Shared.Next(1, 20));   // cede el hilo: otras peticiones avanzan
        return scope.ServiceProvider.GetRequiredService<IOrderRepository>().GetAll();
    }

    var results = await Task.WhenAll(Enumerable.Range(0, 200)
        .Select(i => Request(i % 2 == 0 ? "acme" : "globex")));

    for (var i = 0; i < results.Length; i++)
        Assert.All(results[i], o => Assert.Equal(i % 2 == 0 ? "acme" : "globex", o.TenantId));
}
```

Más dos pruebas del contrato (`Context_without_tenant_fails_loudly` comprueba que `TenantId` lanza `TenantNotResolvedException`; `Context_cannot_change_tenant_once_set`, que un segundo `Set` falla). Resultado de `dotnet test --logger "console;verbosity=normal"` (xunit, .NET 10.0.401):

```text
Correctas Tests.TenantIsolationTests.Repository_returns_only_orders_of_the_context_tenant(tenant: "acme", expected: 2) [7 ms]
Correctas Tests.TenantIsolationTests.Repository_returns_only_orders_of_the_context_tenant(tenant: "globex", expected: 1) [< 1 ms]
Correctas Tests.TenantIsolationTests.Concurrent_scopes_never_see_each_others_tenant [58 ms]
Correctas Tests.TenantIsolationTests.Context_without_tenant_fails_loudly [< 1 ms]
Correctas Tests.TenantIsolationTests.Context_cannot_change_tenant_once_set [< 1 ms]

Correctas! - Con error: 0, Superado: 5, Omitido: 0, Total: 5
```

La prueba concurrente no se ejecutó contra la variante `Singleton` para ver el fallo; el fallo del contexto compartido sí se observa en la salida de los dos `curl` de arriba.

## Cuándo NO hace falta un contexto propio

- **Aplicación pequeña con un único punto que necesita el tenant.** Si solo un lugar lo usa (por ejemplo, un endpoint que lee el claim del token con `User.FindFirst("tenant_id")`), una abstracción con interfaz, setter y registro es más maquinaria que el problema.
- **El tenant ya viaja en una sola abstracción existente.** Si el `DbContext` recibe el tenant al construirse y todo pasa por él, el contexto es el propio `DbContext`.
- **Una instancia de aplicación por tenant.** Si cada tenant tiene su propio despliegue, el tenant es configuración del proceso, no estado de la petición.

Cuando una segunda o tercera clase empieza a leer el claim directamente, es el momento de extraer el contexto.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| Un tenant ve datos de otro, sin error ni log | El contexto es `Singleton` (o está en un campo `static`) y conserva el tenant de la primera petición |
| `Cannot consume scoped service 'ITenantContext' from singleton '…'` al arrancar | Un `Singleton` (caché, `BackgroundService`, cliente) recibe el contexto por constructor; resolver dentro de un scope con `IServiceScopeFactory` |
| `TenantNotResolvedException` solo en jobs o consumidores | El job no crea scope ni rellena el contexto por unidad de trabajo |
| El middleware escribe el tenant pero el repositorio ve «no hay tenant» | `ITenantContext` y `ITenantContextSetter` se registraron como dos `AddScoped` separados: son dos instancias |
| Un job de fondo usa el tenant de otra petición | `AsyncLocal` sin restaurar, o un bucle lanzado dentro de una petición que hereda su valor |
| Un tenant cambia a mitad de petición | El contexto expone un `set` público y algún servicio lo usa |
| El dominio o la capa de aplicación tienen `using Microsoft.AspNetCore.Http` para leer el tenant | Se accede a `HttpContext` desde una capa interna: el contexto existe para que solo el borde conozca HTTP |

## Buenas prácticas avanzadas

- **El contexto falla, no devuelve vacío** — `TenantId` lanza excepción si no hay tenant, y el `Set` rechaza un segundo valor. Un tenant `null`, `""` o «por defecto» convierte un error de cableado en una fuga silenciosa.
- **Registra la interfaz de lectura y la de escritura con la misma instancia** — dos `AddScoped<I…, TenantContext>()` independientes crean dos objetos; delega ambas interfaces en el tipo concreto, como en el registro de arriba.
- **Una unidad de trabajo, un scope, un `Set`** — en jobs y consumidores, el scope se crea dentro del bucle (no antes), y el contexto se rellena antes de resolver cualquier otro servicio del scope. Un servicio resuelto antes del `Set` puede haberse construido con el contexto vacío.
- **Activa `ValidateScopes` y `ValidateOnBuild` también fuera de `Development`** si la aplicación tiene singletons que podrían tocar el contexto: `builder.Host.UseDefaultServiceProvider(o => { o.ValidateScopes = true; o.ValidateOnBuild = true; })`. Sin ello, la captive dependency solo se descubre en producción.
- **Si usas `AsyncLocal`, asigna con un `using` que restaure** y no lances bucles de larga vida desde dentro de una petición sin comprobar qué tenant heredan.
- **Etiqueta logs y trazas con el tenant desde el contexto** — es la forma más barata de depurar una fuga cuando ocurre.

## Documentación oficial

- [Inyección de dependencias en .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/dependency-injection) — la sección de tiempos de vida (`Singleton`, `Scoped`, `Transient`) y la de validación de scopes (*Scope validation*), que define cuándo salta el error de la captive dependency.
- [`AsyncLocal<T>`](https://learn.microsoft.com/en-us/dotnet/api/system.threading.asynclocal-1) — referencia de la clase: cuándo usarla y cómo fluyen sus valores entre llamadas asíncronas.

---

*En resumen: el tenant actual vive en un servicio `Scoped` que escribe un solo punto de entrada, lo leen todas las capas y falla a gritos cuando falta; cualquier cosa más global que una petición (o una unidad de trabajo) es una fuga esperando a ocurrir.*
