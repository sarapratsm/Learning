# Capa de Infraestructura

## ¿Qué es?

La capa de infraestructura es el proyecto que contiene las implementaciones concretas de los contratos que el centro de la aplicación declara: repositorios sobre una base de datos, clientes de APIs externas, envío de correo, reloj, ficheros. Es el único sitio donde aparecen EF Core, `HttpClient`, SQL o claves de un proveedor, y no contiene reglas de negocio.

## ¿Por qué existe?

Cuando la tienda confirma el pedido #4711, el caso de uso `ConfirmarPedido` necesita guardar el pedido, cobrarlo y avisar al cliente. Esos tres «necesito» están declarados como interfaces en el centro (`IRepositorioPedidos`, `IPasarelaPago`, `INotificador`), pero alguien tiene que cumplirlos con SQL Server, con la API de un proveedor de pagos y con un servidor de correo. Ese alguien es `Tienda.Infraestructura`.

Sin una capa que concentre ese trabajo, los detalles se esparcen: una cadena de conexión en un caso de uso, un `catch (SqlException)` en un controlador, un `[Table]` sobre una entidad. Cada detalle técnico que se cuela en el centro lo ata a una tecnología concreta y obliga a probarlo con ella.

> Si la aplicación es una cocina, el dominio es la receta y la infraestructura son los electrodomésticos: la receta dice «hornear 20 minutos» y no sabe si el horno es de gas o eléctrico. Cambiar de horno no obliga a reescribir la receta, pero sí a que el nuevo horno entienda la orden. Y un electrodoméstico no decide qué se cocina.

## ¿Cuándo y para qué se usa?

Todo lo que cruza la frontera de la aplicación hacia fuera vive aquí:

| Contrato (en el centro) | Adaptador (en `Tienda.Infraestructura`) | Tecnología |
|---|---|---|
| `IRepositorioPedidos` | `RepositorioPedidos` | EF Core + SQL Server |
| `IPasarelaPago` | `PasarelaPagoStripe` | `HttpClient` tipado |
| `INotificador` | `NotificadorSmtp` | Servidor de correo |
| `TimeProvider` | El del sistema | Reloj |
| `IAlmacenFacturas` | `AlmacenFacturasEnDisco` | Sistema de ficheros |

Es la capa que más cambia cuando cambia la tecnología y la que menos debería saber del negocio: su trabajo es **traducir** en ambas direcciones (de entidades a filas, de excepciones del proveedor a errores del contrato) y **tolerar los fallos de lo remoto** (reintentos, timeouts). Cómo se llama cada pieza en el vocabulario hexagonal está en [Puertos y Adaptadores](Puertos-y-Adaptadores.md).

## Qué contiene y qué no

Una prueba rápida para decidir si algo pertenece aquí: si al cambiar de proveedor (de SQL Server a PostgreSQL, de Stripe a otra pasarela) ese código tiene que cambiar, es infraestructura. Si tiene que cambiar cuando cambia una regla del negocio, es dominio o caso de uso.

| Pertenece a la infraestructura | No pertenece |
|---|---|
| `DbContext`, configuración del mapeo, migraciones | «Un pedido sin líneas no se confirma» |
| SQL, consultas, índices | «Un pedido pagado no se cancela» |
| Cliente HTTP, serialización, cabeceras de autenticación | Elegir qué hacer cuando el pago falla |
| Reintentos, timeouts, *circuit breaker* | Calcular el total o aplicar un descuento |
| Traducir excepciones del proveedor | Decidir si un stock negativo es válido (el dominio lo prohíbe) |

La dependencia va en un solo sentido: `Tienda.Infraestructura` referencia a `Tienda.Aplicacion` (para ver las interfaces) y a `Tienda.Dominio` (para construir las entidades), nunca al revés. Por qué y cómo se vigila está en [Regla de Dependencia](Regla-de-Dependencia.md).

## Un repositorio completo con EF Core

### El contrato

Lo declara el centro, con el vocabulario del negocio y sin tipos de EF Core:

```csharp
// Tienda.Aplicacion
public interface IRepositorioPedidos
{
    Task<Pedido?> ObtenerPorId(int id, CancellationToken ct);
    Task Guardar(Pedido pedido, CancellationToken ct);
}
```

Devuelve `Pedido` completo (con sus líneas) o `null`, y `Guardar` persiste los cambios del agregado. Quien lo llama no sabe si detrás hay SQL, un fichero o un diccionario. Qué es un repositorio y por qué se organiza por agregado se explica en [Repositorios](../patrones-de-diseno/Repositorios.md).

### El dominio, sin atributos

`Pedido` tiene un constructor privado, estado que solo cambia mediante métodos y una colección de líneas que no se puede modificar desde fuera:

```csharp
// Tienda.Dominio
public class Pedido
{
    private readonly List<LineaPedido> _lineas = [];

    private Pedido() { }                       // lo usa EF Core al materializar
    public Pedido(int id, int clienteId) { Id = id; ClienteId = clienteId; }

    public int Id { get; private set; }
    public int ClienteId { get; private set; }
    public EstadoPedido Estado { get; private set; }
    public IReadOnlyCollection<LineaPedido> Lineas => _lineas;
    public decimal Total => _lineas.Sum(l => l.Cantidad * l.Precio);

    public void AnadirLinea(int productoId, int cantidad, decimal precio) =>
        _lineas.Add(new LineaPedido(productoId, cantidad, precio));

    public void Confirmar()
    {
        if (_lineas.Count == 0)
            throw new InvalidOperationException("Un pedido sin líneas no se puede confirmar.");
        Estado = EstadoPedido.Confirmado;
    }
}
```

No hay `[Table]`, `[Key]` ni `using Microsoft.EntityFrameworkCore`. Las reglas siguen en el dominio (ver [Capa de Dominio](Capa-de-Dominio.md)).

### La configuración del mapeo

El mapeo se escribe en `Tienda.Infraestructura` con la API fluida de EF Core, una clase por entidad:

```csharp
// Tienda.Infraestructura
public class PedidoConfiguration : IEntityTypeConfiguration<Pedido>
{
    public void Configure(EntityTypeBuilder<Pedido> b)
    {
        b.ToTable("Pedidos");
        b.HasKey(p => p.Id);
        b.Property(p => p.Id).ValueGeneratedNever();            // el id lo asigna el dominio
        b.Property(p => p.Estado).HasConversion<string>().HasMaxLength(20);
        b.Property<int>("Version").IsConcurrencyToken();         // propiedad sombra: no existe en la clase
        b.Ignore(p => p.Total);                                  // se calcula, no se guarda

        b.HasMany(p => p.Lineas).WithOne().HasForeignKey("PedidoId").OnDelete(DeleteBehavior.Cascade);
        b.Navigation(p => p.Lineas).UsePropertyAccessMode(PropertyAccessMode.Field);
    }
}

public class TiendaDbContext(DbContextOptions<TiendaDbContext> opciones) : DbContext(opciones)
{
    public DbSet<Pedido> Pedidos => Set<Pedido>();

    protected override void OnModelCreating(ModelBuilder mb) =>
        mb.ApplyConfigurationsFromAssembly(typeof(TiendaDbContext).Assembly);
}
```

Tres detalles hacen que funcione con un dominio encapsulado:

- **Constructor privado.** EF Core necesita un constructor sin parámetros (o con parámetros que coincidan con propiedades) y no exige que sea público. Crea la instancia con él y rellena las propiedades con *setters* privados.
- **Colección encapsulada.** `Lineas` es de solo lectura y no tiene *setter*. EF encuentra el campo `_lineas` por convención (nombre de la propiedad en minúscula con guion bajo) y con `UsePropertyAccessMode(Field)` lee y escribe ese campo directamente, sin pasar por la propiedad.
- **Propiedad sombra `Version`.** Es una columna que existe en la tabla y en el modelo de EF, pero no en la clase `Pedido`: el dominio no sabe que la persistencia necesita detectar escrituras simultáneas.

Comprobado con SQLite en memoria y EF Core 10: se guarda el pedido #4711 con dos líneas, se lee desde un `DbContext` nuevo y devuelve el agregado entero:

```
Leído: #4711 Confirmado líneas=2 total=60,0
```

Las líneas llegan por el campo `_lineas` y `Total` se recalcula en el dominio. Si se omite el `Include` en la consulta, EF no carga la colección y el mismo pedido sale con `líneas=0`: un agregado incompleto, sin error.

### La implementación

```csharp
// Tienda.Infraestructura
public class RepositorioPedidos(TiendaDbContext db) : IRepositorioPedidos
{
    public Task<Pedido?> ObtenerPorId(int id, CancellationToken ct) =>
        db.Pedidos.Include(p => p.Lineas).SingleOrDefaultAsync(p => p.Id == id, ct);

    public async Task Guardar(Pedido pedido, CancellationToken ct)
    {
        if (!db.Pedidos.Local.Contains(pedido)) db.Pedidos.Add(pedido);
        else db.Entry(pedido).Property<int>("Version").CurrentValue++;

        await db.SaveChangesAsync(ct);   // la traducción de excepciones va aquí; ver siguiente sección
    }
}
```

`ObtenerPorId` carga el agregado completo con una sola consulta. `Guardar` inserta si el pedido es nuevo y, si ya lo seguía el contexto, incrementa el token de versión para que `UPDATE ... WHERE Version = <la leída>` falle si otra petición lo modificó antes. En SQL Server se suele usar `IsRowVersion()` (columna `rowversion` que la base de datos incrementa sola) en lugar de un entero manual. El detalle de EF Core (seguimiento de cambios, consultas, migraciones) está en [Entity Framework Core](../../bases-de-datos/acceso-a-datos-dotnet/Entity-Framework-Core.md).

### ¿Mapear la entidad o separar un modelo de persistencia?

Lo habitual es mapear la entidad de dominio directamente, como arriba. Hace falta una clase de persistencia aparte (con su propio mapeo a `Pedido` en el repositorio) solo cuando el ORM no puede representar el dominio:

| Situación | Decisión |
|---|---|
| Constructor privado, *setters* privados, colecciones encapsuladas, enums, propiedades sombra | Mapear la entidad con Fluent API: EF lo soporta |
| Objetos de valor (`Dinero`, `Direccion`) | Mapear la entidad: `OwnsOne` o `HasConversion` |
| Tabla heredada cuyas columnas no se parecen al dominio (nombres crípticos, una fila con datos de dos conceptos) | Clase de persistencia + mapeo manual |
| El dominio usa tipos que el ORM no sabe guardar (jerarquías inmutables complejas, colecciones de colecciones) | Clase de persistencia + mapeo manual |
| El mismo agregado se guarda en dos almacenes distintos (SQL y un índice de búsqueda) | Un modelo de persistencia por almacén |
| Se quiere «proteger» el dominio de EF sin motivo concreto | Mapear la entidad: el modelo doble cuesta una clase por entidad y un mapeo que mantener |

El modelo de persistencia separado tiene un coste real: cada cambio de campo se escribe dos veces y el mapeo puede perder datos sin que ningún compilador avise. Compensa cuando la forma de la tabla y la del dominio divergen de verdad.

## Traducir las excepciones en la frontera

Las excepciones de un proveedor son detalles técnicos. Si cruzan la frontera, el caso de uso acaba conociendo la tecnología:

```csharp
// ❌ Tienda.Aplicacion: el caso de uso conoce SQL Server
public async Task Ejecutar(int pedidoId, CancellationToken ct)
{
    var pedido = await repositorio.ObtenerPorId(pedidoId, ct);
    pedido!.Confirmar();
    try { await repositorio.Guardar(pedido, ct); }
    catch (SqlException) { /* ¿y si mañana es PostgreSQL? */ }
    catch (DbUpdateConcurrencyException) { /* referencia a EF Core en la capa de aplicación */ }
}
```

`Tienda.Aplicacion` tendría que referenciar `Microsoft.EntityFrameworkCore` y `Microsoft.Data.SqlClient`, y cambiar de base de datos rompería el caso de uso. La alternativa es que el contrato declare sus propios errores y el adaptador traduzca:

```csharp
// ✅ Tienda.Aplicacion: errores neutros, del vocabulario del contrato
public class ConflictoDeConcurrenciaException(Exception inner)
    : Exception("El pedido fue modificado por otra operación.", inner);

public class AlmacenNoDisponibleException(Exception inner)
    : Exception("El almacén de pedidos no responde.", inner);

// Tienda.Infraestructura
public async Task Guardar(Pedido pedido, CancellationToken ct)
{
    // ... Add o incremento de versión
    try { await db.SaveChangesAsync(ct); }
    catch (DbUpdateConcurrencyException ex) { throw new ConflictoDeConcurrenciaException(ex); }
    catch (DbUpdateException ex) when (ex.InnerException is SqlException) { throw new AlmacenNoDisponibleException(ex); }
}
```

La excepción original viaja como `InnerException`, así que el diagnóstico no se pierde, pero el caso de uso solo ve tipos que él conoce. Comprobado con dos `DbContext` que leen el pedido #4711 y guardan uno tras otro: el segundo `Guardar` lanza `ConflictoDeConcurrenciaException`, con `DbUpdateConcurrencyException` como causa.

Lo mismo vale para `PasarelaPagoStripe` con `HttpRequestException` o `TaskCanceledException` por timeout. Si se prefiere no usar excepciones para fallos esperables, el contrato puede devolver un resultado (ver [Result Pattern](../patrones-de-diseno/Result-Pattern.md)); lo importante es que el tipo del fallo pertenezca al centro. Cómo se convierte luego ese desenlace en un código HTTP se trata en [Códigos de Resultado por Capa](Codigos-de-Resultado-por-Capa.md).

## Adaptador de una API externa con reintentos

### Cliente tipado

La pasarela de pago se implementa con un `HttpClient` tipado: `IHttpClientFactory` crea y recicla los manejadores internos (evita agotar sockets y respeta los cambios de DNS) y entrega el cliente ya configurado a la clase.

```csharp
// Tienda.Infraestructura
public class PasarelaPagoStripe(HttpClient http) : IPasarelaPago
{
    public async Task<bool> Cobrar(int pedidoId, decimal importe, string tarjeta, CancellationToken ct)
    {
        using var peticion = new HttpRequestMessage(HttpMethod.Post, "v1/payment_intents")
        {
            Content = JsonContent.Create(new { amount = (long)(importe * 100), currency = "eur", source = tarjeta })
        };
        peticion.Headers.Add("Idempotency-Key", $"pedido-{pedidoId}-cobro");

        using var respuesta = await http.SendAsync(peticion, ct);
        return respuesta.IsSuccessStatusCode;
    }
}
```

Traduce del idioma del negocio (`Cobrar(pedidoId, importe, tarjeta)`, devuelve sí o no) al del proveedor (céntimos, moneda, cabecera). El contrato `IPasarelaPago` no menciona Stripe.

### Reintentos y timeouts

La resiliencia se añade al registrar el cliente, con el paquete `Microsoft.Extensions.Http.Resilience` (construido sobre Polly v8):

```csharp
services.AddHttpClient<IPasarelaPago, PasarelaPagoStripe>(c => c.BaseAddress = new Uri(opciones.UrlBase))
        .AddStandardResilienceHandler();
```

`AddStandardResilienceHandler` encadena un límite de tiempo total, reintentos con espera exponencial, un *circuit breaker* y un timeout por intento, con valores por defecto razonables (tres reintentos). Se ajustan por opciones (`o.Retry.MaxRetryAttempts`, `o.AttemptTimeout`...).

Esta política vive en la infraestructura y no en `ConfirmarPedido`: cuántas veces se reintenta, con qué espera y tras cuántos fallos se «abre» el circuito son detalles de hablar con un servicio remoto. El caso de uso solo ve que `Cobrar` devolvió un resultado o falló definitivamente.

Comprobado con un manejador falso que responde 503, 503 y 200: el cliente hace tres intentos y `Cobrar` devuelve `true`.

### Reintentar un cobro exige idempotencia

Reintentar una lectura es inocuo; reintentar un `POST` que cobra no. Si la primera petición llegó al proveedor, el cobro se hizo y la respuesta se perdió por el camino, el reintento cobra dos veces al cliente del pedido #4711. La defensa es una **clave de idempotencia**: un identificador que se envía en cada intento y con el que el proveedor reconoce la repetición y devuelve el resultado del primero en lugar de cobrar otra vez.

En el ejemplo, la clave `pedido-4711-cobro` se deriva del pedido, no se genera por intento: los tres intentos del test anterior llevaron la misma (`claves=pedido-4711-cobro`). Una clave aleatoria generada dentro del reintento anularía la protección. Si el proveedor no ofrece idempotencia, hay que desactivar los reintentos para ese método (`DisableForUnsafeHttpMethods()` en las opciones de reintento) o consultar el estado del cobro antes de repetir.

## Composición y configuración

### Un solo punto de registro

Todos los adaptadores se registran en un método de extensión de la propia infraestructura, que la capa más externa invoca:

```csharp
// Tienda.Infraestructura
public static class DependencyInjection
{
    public static IServiceCollection AddInfraestructura(this IServiceCollection services, IConfiguration config)
    {
        services.AddOptions<PasarelaPagoOpciones>()
                .Bind(config.GetSection("PasarelaPago"))
                .ValidateDataAnnotations().ValidateOnStart();

        services.AddDbContext<TiendaDbContext>(o =>
            o.UseSqlServer(config.GetConnectionString("Tienda")));

        services.AddScoped<IRepositorioPedidos, RepositorioPedidos>();
        services.AddScoped<INotificador, NotificadorSmtp>();
        services.AddSingleton(TimeProvider.System);

        services.AddHttpClient<IPasarelaPago, PasarelaPagoStripe>((sp, c) =>
                c.BaseAddress = new Uri(sp.GetRequiredService<IOptions<PasarelaPagoOpciones>>().Value.UrlBase))
                .AddStandardResilienceHandler();

        return services;
    }
}

// Tienda.Api (Program.cs)
builder.Services.AddInfraestructura(builder.Configuration);
```

`Tienda.Api` conoce el método, no las clases. Los lifetimes de cada registro (por qué el repositorio y el `DbContext` son `Scoped`) y la raíz de composición se explican en [Inversión de Dependencias](Inversion-de-Dependencias.md).

### Configuración y secretos fuera del código

Nada de URLs, claves ni cadenas de conexión en C#. Se leen de la configuración (ficheros `appsettings`, variables de entorno, gestor de secretos) y se exponen como **opciones tipadas**:

```csharp
public class PasarelaPagoOpciones
{
    [Required, Url] public string UrlBase { get; init; } = "";
    [Required]      public string ClaveApi { get; init; } = "";
}
```

`ValidateOnStart()` hace que una clave ausente rompa el arranque con un mensaje claro, no el primer cobro en producción. Las claves reales no van al repositorio: en desarrollo, a *user secrets*; en producción, a variables de entorno o a un almacén de secretos. Las opciones están en la [guía de gestión de secretos en desarrollo](../../seguridad/gestion-de-secretos-en-desarrollo/README.md).

## Probar la capa contra tecnología real

Un repositorio con el `DbContext` mockeado solo demuestra que se llamó a un método del mock. Lo que falla en producción (un mapeo mal configurado, un tipo de columna, una restricción única, la concurrencia, el `Include` olvidado) no existe en un doble. Esta capa se prueba contra la tecnología de verdad:

| Opción | Cuándo sirve | Limitación |
|---|---|---|
| Base de datos real en contenedor (Testcontainers) | Valida mapeo, SQL, restricciones y concurrencia del motor que se usa en producción | Necesita Docker y tarda segundos por clase de tests |
| SQLite en memoria | Rápida; sirve para el mapeo y la forma del agregado | Otro motor: no reproduce `rowversion`, tipos ni el SQL específico de SQL Server |
| `UseInMemoryDatabase` de EF Core | Casi nunca | No es relacional: no aplica restricciones ni transacciones ni claves foráneas |
| Mock de `DbContext` o `DbSet` | No | No prueba el comportamiento real |

El test típico guarda un `Pedido` con dos líneas, lo lee con un contexto nuevo y comprueba que el agregado vuelve completo; otro provoca el conflicto de versión y espera `ConflictoDeConcurrenciaException`. Cómo levantar la base de datos efímera por test está en [Testcontainers](../../devops/docker/Testcontainers.md). Para el adaptador HTTP basta un `HttpMessageHandler` falso que simule 503 y timeouts; la verificación de que cualquier implementación cumple el contrato está en [Puertos y Adaptadores](Puertos-y-Adaptadores.md).

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Para confirmar un pedido hay que cambiar el repositorio; un `if (pedido.Estado == Pagado)` aparece dentro de `Guardar` | **Lógica de negocio en el adaptador**: la regla «un pedido pagado no se cancela» pertenece a `Pedido`. Un segundo adaptador (otro motor) tendría que duplicarla |
| El caso de uso hace `.Where(...)` sobre lo que devuelve el repositorio y falla con «no se puede traducir a SQL» | **`IQueryable` filtrado al centro**: la consulta se ejecuta cuando alguien la enumera, fuera del adaptador; el contrato queda atado a EF. Devolver `Pedido` o `List<Pedido>` y poner cada consulta como método con nombre (`ObtenerPendientesDeCobro`) |
| `InvalidOperationException: A second operation was started on this context instance` o datos cruzados entre usuarios | **`DbContext` registrado como `Singleton`**: no es seguro entre hilos y acumula el seguimiento de todas las entidades. Debe ser `Scoped` (`AddDbContext` ya lo registra así) |
| Cargar una lista de 100 pedidos lanza 101 consultas | **Consulta N+1**: se carga la lista y se accede a las `Lineas` de cada uno una a una (carga diferida). Cargar con `Include` (o proyectar lo necesario) en la consulta del repositorio |
| El pedido se lee con `Lineas.Count == 0` aunque tiene líneas guardadas | Falta el `Include` en la consulta: EF no carga colecciones por sí solo |
| El caso de uso tiene un `catch (SqlException)` | Excepción del proveedor sin traducir en la frontera |
| Al cobrar tras un timeout, el cliente recibe dos cargos | Reintento de un `POST` sin clave de idempotencia estable |
| El primer cobro en producción falla con «Value cannot be null» sobre la clave de API | Opciones sin validar al arrancar: falta `ValidateOnStart()` |

## Buenas prácticas avanzadas

- **Un repositorio por agregado, con métodos que dicen qué buscan.** `ObtenerPorId` y `ObtenerPendientesDeCobro` son contratos del negocio; un `Consultar(Expression<Func<Pedido,bool>>)` genérico traslada LINQ y EF al centro y hace imposible cambiar de almacén.
- **Carga el agregado entero o no lo cargues.** `ObtenerPorId` devuelve el `Pedido` con todas sus líneas; para listados, devuelve proyecciones de solo lectura (`ResumenPedido`) en lugar de entidades parciales que el dominio no puede validar.
- **Pasa el `CancellationToken` hasta el `SaveChangesAsync` y hasta el `HttpClient`.** Si el cliente cierra la petición, no hay motivo para seguir cobrando o escribiendo; y el timeout por intento de la política de resiliencia lo necesita para cancelar de verdad.
- **Configura el timeout total por debajo del de quien te llama.** Si el endpoint de `ConfirmarPedido` tiene 15 segundos y la política de reintentos puede durar 30, el cliente recibe el error antes de que el adaptador termine y el cobro puede completarse sin que nadie lo sepa. Ajusta `TotalRequestTimeout` y los reintentos para que quepan.
- **Una excepción traducida conserva la causa.** Pasa siempre la original como `InnerException`: el contrato queda neutro y los registros siguen mostrando el código de error de SQL Server o el estado HTTP real.
- **Registra los adaptadores en un único método de extensión por proyecto.** `AddInfraestructura` hace que `Program.cs` no conozca ninguna clase concreta y que añadir un adaptador no obligue a tocar la capa de API.

## Documentación oficial

- [Resiliencia de HTTP en .NET](https://learn.microsoft.com/en-us/dotnet/core/resilience/http-resilience) — `AddStandardResilienceHandler`, valores por defecto y cómo ajustarlos. Ir al configurar reintentos y timeouts de un cliente externo.
- [IHttpClientFactory en .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/httpclient-factory) — clientes tipados y ciclo de vida de los manejadores. Útil al montar el adaptador de una API externa.
- [Campos de respaldo (*backing fields*) en EF Core](https://learn.microsoft.com/en-us/ef/core/modeling/backing-field) — cómo EF accede a colecciones encapsuladas. Ir cuando el dominio no expone *setters*.
- [Claves de idempotencia de Stripe](https://docs.stripe.com/api/idempotent_requests) — cómo un proveedor real reconoce un reintento y qué garantías da. Ir antes de reintentar cualquier cobro.

---

*En resumen: la infraestructura son los electrodomésticos de la aplicación: cumplen las órdenes del centro con tecnología real, traducen sus fallos a un idioma neutro y no deciden nada del menú.*
