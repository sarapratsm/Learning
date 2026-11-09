# Aislamiento por Fila

## ¿Qué es?

Es la técnica que garantiza que, en una base de datos **compartida** entre *tenants* (las empresas clientes de una aplicación SaaS), cada consulta solo vea las filas de su propio tenant. Se consigue marcando cada fila con una columna `TenantId` y aplicando el filtro por ella de forma automática, en dos capas: los *global query filters* de EF Core y *Row-Level Security* (RLS) del motor de base de datos.

## ¿Por qué existe?

En la estrategia de base compartida, todos los tenants conviven en las mismas tablas y el aislamiento es solo lógico: depende de que **toda** consulta incluya `WHERE TenantId = @actual`. El fallo es humano: tarde o temprano alguien escribe una consulta nueva y olvida el filtro, y esa única consulta devuelve datos de otro cliente.

> Es como una oficina compartida donde cada documento lleva el nombre de su empresa. Si se confía en que cada empleado lea la etiqueta antes de coger un papel, un despiste basta para filtrar. Mejor poner un guardia automático que tape los documentos que no son de quien pregunta, y un segundo guardia en la puerta del archivo por si el primero falla.

El aislamiento por fila existe para que el filtro no dependa de recordarlo: el ORM lo añade solo y la base de datos lo vuelve a comprobar.

## ¿Cuándo y para qué se usa?

Siempre que varios tenants compartan las mismas tablas (la tercera opción de [Estrategias de Aislamiento](Estrategias-de-Aislamiento.md)). Es la pieza de seguridad central de esa estrategia. Con base de datos o esquema por tenant, la separación la hace la propia estructura y esta técnica deja de ser necesaria, aunque el filtro sigue siendo una barrera barata dentro de cada base.

Todos los ejemplos usan una aplicación de gestión de pedidos con dos tenants, `acme` y `globex`, EF Core 10 y SQLite. El tenant llega en la cabecera `X-Tenant` solo por simplicidad: cómo se identifica de verdad está en [Identificación del Tenant](Identificacion-del-Tenant.md) y dónde vive durante la petición, en [Tenant Context](Tenant-Context.md). Aquí basta una interfaz mínima:

```csharp
public interface ITenantContext { Guid? TenantId { get; } }
```

## El problema: el `Where` que se olvida

Filtrar a mano parece razonable. Este servidor tiene dos endpoints sobre la misma tabla `Orders`; el primero filtra por tenant y el segundo, escrito seis meses después, no:

```csharp
// ❌ El aislamiento depende de que cada autor del endpoint recuerde el Where
app.MapGet("/orders", async (ManualDb db, ITenantContext t) =>
{
    var tenantId = t.TenantId!.Value;
    return await db.Orders.Where(o => o.TenantId == tenantId)
        .Select(o => new { o.Id, o.TenantId, o.Total }).ToListAsync();
});

app.MapGet("/orders/{id:guid}", async (Guid id, ManualDb db) =>
    await db.Orders.Where(o => o.Id == id)          // ← falta el TenantId
        .Select(o => new { o.Id, o.TenantId, o.Total }).FirstOrDefaultAsync());
```

Con dos pedidos sembrados (uno de `acme` y otro de `globex` con id `bbbbbbbb-0000-0000-0000-000000000001`), `acme` pide su listado y después el pedido de `globex` por id:

```bash
curl -H "X-Tenant: acme" localhost:6743/orders
curl -H "X-Tenant: acme" localhost:6743/orders/bbbbbbbb-0000-0000-0000-000000000001
```

```text
[{"id":"aaaaaaaa-0000-0000-0000-000000000001","tenantId":"11111111-1111-1111-1111-111111111111","total":120.0}]
{"id":"bbbbbbbb-0000-0000-0000-000000000001","tenantId":"22222222-2222-2222-2222-222222222222","total":9999.0}
```

El listado está bien y el segundo endpoint entrega el pedido de otra empresa (el tenant `22222222…` es `globex`). Ninguna prueba que solo use el listado lo detecta. La versión con filtro global, con el mismo código en los dos endpoints y **sin ningún `Where` de tenant**:

```csharp
// ✅ El filtro se añade solo, en cada consulta sobre Order
app.MapGet("/orders/{id:guid}", async (Guid id, AppDb db) =>
    await db.Orders.Where(o => o.Id == id)
        .Select(o => new { o.Id, o.TenantId, o.Total }).FirstOrDefaultAsync() is { } o
        ? Results.Ok(o) : Results.NotFound());
```

```bash
curl -s -w ' [%{http_code}]' -H "X-Tenant: acme" localhost:6419/orders/bbbbbbbb-0000-0000-0000-000000000001
curl -s -H "X-Tenant: acme" localhost:6419/orders/aaaaaaaa-0000-0000-0000-000000000001
```

```text
 [404]
{"id":"aaaaaaaa-0000-0000-0000-000000000001","tenantId":"11111111-1111-1111-1111-111111111111","total":120.0}
```

El pedido de `globex` no existe para `acme` (404) y el propio sí se encuentra.

## La columna `TenantId`

Cada entidad de negocio lleva `TenantId` e implementa una interfaz marcadora. La interfaz permite aplicar el filtro y la asignación automática a todas las entidades con un solo bucle:

```csharp
public interface ITenantEntity { Guid TenantId { get; set; } }

public class Order : ITenantEntity
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid TenantId { get; set; }
    public Guid CustomerId { get; set; }
    public decimal Total { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public List<OrderLine> Lines { get; set; } = [];
}
```

Qué tablas **no** llevan `TenantId`:

| Tabla | Motivo |
|---|---|
| `Tenants` | Es la lista de tenants: no pertenece a ninguno. |
| Catálogos globales (países, monedas, tipos de IVA) | Son los mismos para todos y de solo lectura para los tenants. |
| Tablas de plataforma (planes, registros de migración) | Las gestiona la plataforma, no el tenant. |

Las tablas hijas (por ejemplo `OrderLine`, líneas de un pedido) **sí** llevan `TenantId`, aunque se alcancen a través del padre: más abajo se ve qué fuga si no lo hacen. Una decisión por tabla, consciente: lo global es la excepción y debe estar en una lista explícita (el test de aislamiento la usa).

## El filtro global de EF Core

Un *global query filter* es una condición `Where` que EF Core añade a toda consulta LINQ sobre una entidad. Se declara una vez en `OnModelCreating`.

### Un filtro para todas las entidades

El filtro debe leer el tenant **actual**, que cambia en cada petición, mientras que el modelo se construye una vez y se cachea. Por eso lee una **propiedad del propio `DbContext`**, no un valor copiado al construir el modelo:

```csharp
public class AppDb(DbContextOptions<AppDb> options, ITenantContext tenant) : DbContext(options)
{
    public DbSet<Order> Orders => Set<Order>();
    // ... resto de DbSet

    // El filtro lee ESTA propiedad en cada consulta.
    // Sin tenant: Guid.Empty, que no coincide con ninguna fila (falla cerrado).
    public Guid CurrentTenantId => tenant.TenantId ?? Guid.Empty;

    protected override void OnModelCreating(ModelBuilder mb)
    {
        foreach (var entityType in mb.Model.GetEntityTypes())
        {
            if (typeof(ITenantEntity).IsAssignableFrom(entityType.ClrType))
                typeof(AppDb).GetMethod(nameof(ApplyTenantFilter), BindingFlags.NonPublic | BindingFlags.Instance)!
                    .MakeGenericMethod(entityType.ClrType).Invoke(this, [mb]);
        }
    }

    private void ApplyTenantFilter<T>(ModelBuilder mb) where T : class, ITenantEntity
        => mb.Entity<T>().HasQueryFilter(e => e.TenantId == CurrentTenantId);
}
```

El bucle recorre las entidades registradas y, por reflexión, llama al método genérico para cada una que implemente `ITenantEntity`; así el lambda queda tipado y una entidad nueva con la interfaz recibe el filtro sin tocar nada más. Con `Orders.Select(o => new { o.Id, o.TenantId, o.Total })` y el tenant `acme`, EF genera (obtenido con `ToQueryString()`):

```text
.param set @ef_filter__CurrentTenantId '11111111-1111-1111-1111-111111111111'

SELECT "o"."Id", "o"."TenantId", "o"."Total"
FROM "Orders" AS "o"
WHERE "o"."TenantId" = @ef_filter__CurrentTenantId
```

El tenant aparece como **parámetro** (`@ef_filter__CurrentTenantId`) que EF rellena con el valor de la propiedad en cada ejecución: esa es la señal de que el filtro está bien construido.

Si se prefiere construir el filtro sin método genérico, también funciona (comprobado) con árboles de expresión: `Expression.Property(Expression.Constant(this), nameof(CurrentTenantId))` como lado derecho de la igualdad y `mb.Entity(clrType).HasQueryFilter(lambda)` con el `LambdaExpression` resultante.

### El error clásico: el tenant capturado en el modelo

Esta variante parece equivalente y no lo es:

```csharp
protected override void OnModelCreating(ModelBuilder mb)
{
    var tenantId = tenant.TenantId;                       // ❌ se lee UNA vez, al construir el modelo
    mb.Entity<Order>().HasQueryFilter(o => o.TenantId == tenantId);
}
```

EF construye el modelo en la primera petición y lo reutiliza para todas las siguientes; el valor de la variable local queda fijado en ese momento. Con el servidor arrancado, `acme` hace la primera petición y después `globex` pide sus pedidos:

```bash
curl -H "X-Tenant: acme"   localhost:6418/orders
curl -H "X-Tenant: globex" localhost:6418/orders
```

```text
[{"id":"aaaaaaaa-0000-0000-0000-000000000001","tenantId":"11111111-1111-1111-1111-111111111111","total":120.0}]
[{"id":"aaaaaaaa-0000-0000-0000-000000000001","tenantId":"11111111-1111-1111-1111-111111111111","total":120.0}]
```

`globex` recibe el pedido de `acme`. No hay error ni excepción: la aplicación devuelve filas de otro cliente con aspecto de normalidad. Y el síntoma depende del orden: el tenant que llegue primero tras cada arranque es el que "gana". En la versión correcta, con la propiedad del contexto, los dos `curl` devuelven cada uno su pedido (`11111111…` para `acme`, `22222222…` para `globex`, salida real de las pruebas).

### Filtros con nombre (EF Core 10)

`HasQueryFilter` con una sola lambda **sustituye** cualquier filtro anterior de esa entidad. Con EF Core 10 se pueden declarar varios filtros por entidad si cada uno tiene nombre, y desactivarlos por separado. La documentación (consultada el 2026-11-09) lo describe y su texto lo presenta como novedad de EF Core 10; se ejecutó con 10.0.14:

```csharp
mb.Entity<Note>()
    .HasQueryFilter("Tenant", n => n.TenantId == CurrentTenantId)
    .HasQueryFilter("SoftDelete", n => !n.IsDeleted);

db.Notes.Count();                                      // 1  (de acme y no borrada)
db.Notes.IgnoreQueryFilters(["SoftDelete"]).Count();   // 2  (también las borradas de acme; el filtro de tenant sigue)
db.Notes.IgnoreQueryFilters().Count();                 // 3  (todo, también de globex)
```

Es útil cuando el filtro de tenant convive con el de borrado lógico: una consulta de papelera desactiva solo `SoftDelete` y **no** pierde el aislamiento. Antes de EF Core 10 había que combinar ambas condiciones con `&&` en un único filtro, lo que obliga a saltarse las dos a la vez.

## Escritura: asignar y validar el `TenantId`

El filtro solo actúa al **leer**. Al insertar, nada impide guardar una fila sin tenant o con el de otro. Un `SaveChangesInterceptor` lo resuelve para todas las entidades `ITenantEntity` en un solo punto:

```csharp
public class TenantStampInterceptor(ITenantContext tenant) : SaveChangesInterceptor
{
    public override InterceptionResult<int> SavingChanges(DbContextEventData e, InterceptionResult<int> r)
    { Stamp(e.Context!); return r; }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData e, InterceptionResult<int> r, CancellationToken ct = default)
    { Stamp(e.Context!); return ValueTask.FromResult(r); }

    private void Stamp(DbContext db)
    {
        var current = tenant.TenantId ?? throw new InvalidOperationException("No hay tenant en la petición actual.");
        foreach (var entry in db.ChangeTracker.Entries<ITenantEntity>())
        {
            if (entry.State == EntityState.Added)
            {
                if (entry.Entity.TenantId == Guid.Empty) entry.Entity.TenantId = current;
                else if (entry.Entity.TenantId != current)
                    throw new InvalidOperationException(
                        $"Intento de escribir en el tenant {entry.Entity.TenantId} desde el tenant {current}.");
            }
            else if (entry.State is EntityState.Modified or EntityState.Deleted && entry.Entity.TenantId != current)
                throw new InvalidOperationException(
                    $"Intento de modificar una fila del tenant {entry.Entity.TenantId} desde el tenant {current}.");
        }
    }
}
```

Se registra con `AddDbContext<AppDb>((sp, o) => o.UseSqlite(cs).AddInterceptors(sp.GetRequiredService<TenantStampInterceptor>()))` y el interceptor se registra `Scoped`, porque depende del tenant de la petición. Sobrescribir `SaveChanges` y `SaveChangesAsync` en el contexto da el mismo resultado; el interceptor evita tener que sobrescribir ambos y es reutilizable. Un `Order` creado sin `TenantId` y otro con el de `globex`, guardados desde el tenant `acme`:

```text
antes de guardar: TenantId = 00000000-0000-0000-0000-000000000000
después de guardar: TenantId = 11111111-1111-1111-1111-111111111111 (acme = 11111111-1111-1111-1111-111111111111)

InvalidOperationException: Intento de escribir en el tenant 22222222-2222-2222-2222-222222222222 desde el tenant 11111111-1111-1111-1111-111111111111.
```

La asignación es automática y el intento de escribir en otro tenant se rechaza antes de llegar a la base. Esto también cubre el caso de un `TenantId` que llega en el cuerpo de la petición y se mapea sin mirar: el valor del cliente nunca debería usarse, y si se usa, se rechaza.

### Modificar o borrar filas de otro tenant

Con el filtro activo, `acme` no puede alcanzar el pedido de `globex` por ninguna vía que pase por LINQ, incluidas las operaciones masivas (salida real):

```text
FindAsync:          null
FirstOrDefault:     null
ExecuteUpdate:      0 filas afectadas
ExecuteDelete:      0 filas afectadas
pedido de globex intacto: total = 9999,0
```

`Find`, `FirstOrDefault`, `ExecuteUpdate` y `ExecuteDelete` aplican el filtro: el patrón seguro es **cargar por la consulta filtrada y modificar la entidad cargada**.

El hueco está en las entidades **desconectadas**: construidas con el `Id` de otra fila y entregadas a `Update` o `Attach`, EF genera `UPDATE ... WHERE Id = @id` sin pasar por el filtro. Con el tenant `acme`:

```csharp
db.Orders.Update(new Order { Id = Seed.GlobexOrder, TenantId = Seed.Acme, Total = 1m });
await db.SaveChangesAsync();   // filas guardadas: 1
```

```text
filas guardadas: 1
pedido de globex tras el intento: ya no lo ve globex
pedidos que ve acme: 2
```

El pedido de `globex` pasó a ser de `acme`: el interceptor no lo detecta porque el `TenantId` de la entidad ya es el del tenant actual. Con `Attach` y un solo campo modificado también se escribe en la fila ajena (se comprobó: 1 fila guardada, total cambiado). No se encontró en la prueba una opción de EF que lo cierre (marcar `TenantId` como inmutable con `SetAfterSaveBehavior(Throw)` no impidió el `Update`); la defensa es no actualizar nunca a partir de un `Id` del cliente sin cargar antes la fila con la consulta filtrada, y la política de RLS con predicado de bloqueo, descrita más abajo.

## Huecos del filtro de EF Core

El filtro solo existe en las consultas LINQ de EF. Cada camino que no pase por ahí queda sin protección:

| Camino | ¿Aplica el filtro? | Comprobado |
|---|---|---|
| LINQ sobre un `DbSet` (`Where`, `Find`, `ExecuteUpdate`...) | Sí | Sí |
| `IgnoreQueryFilters()` | No, por diseño | Sí |
| `FromSqlRaw` sobre un `DbSet` | **Sí**: EF envuelve el SQL como subconsulta | Sí |
| `Database.SqlQueryRaw<T>`, `ExecuteSqlRaw` | No | `SqlQueryRaw` sí; `ExecuteSqlRaw` no |
| Dapper, ADO.NET, conexión directa | No | ADO.NET sí; Dapper no (usa la misma conexión) |
| Entidad hija sin `TenantId` | No | Sí |
| `Update`/`Attach` de entidad desconectada | No | Sí |
| Vistas, procedimientos, herramientas externas (`psql`, BI) | No: no pasan por EF | No (se deduce del diseño) |

### `IgnoreQueryFilters`

Es la puerta oficial para saltarse el filtro, necesaria en tareas de plataforma (un informe global, una migración de datos). Con `acme` activo:

```text
con filtro:         1 pedidos
IgnoreQueryFilters: 2 pedidos
```

Devuelve los pedidos de todos los tenants. Para restringir su uso, un test recorre el código fuente y falla si aparece fuera de una carpeta autorizada:

```csharp
public class NoBypassTests
{
    private const string AllowedFolder = "Platform";   // único módulo que puede saltarse el filtro

    [Fact]
    public void IgnoreQueryFilters_solo_aparece_en_el_modulo_de_plataforma()
    {
        var root = new DirectoryInfo(AppContext.BaseDirectory);
        while (root is not null && !File.Exists(Path.Combine(root.FullName, "Demo", "Demo.csproj"))) root = root.Parent;
        Assert.NotNull(root);

        var offenders = Directory.EnumerateFiles(Path.Combine(root.FullName, "Demo"), "*.cs", SearchOption.AllDirectories)
            .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}"))
            .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}{AllowedFolder}{Path.DirectorySeparatorChar}"))
            .Where(f => File.ReadAllText(f).Contains("IgnoreQueryFilters"))
            .ToList();

        Assert.Empty(offenders);
    }
}
```

Se comprobó que pasa sin apariciones y que falla al añadir un fichero con el texto fuera de la carpeta autorizada. Un analizador de Roslyn que prohíba el método da el mismo resultado con mejor mensaje en el editor, pero no se probó aquí.

### SQL crudo

`FromSqlRaw` sobre un `DbSet` **sí** respeta el filtro, porque EF trata el SQL como la raíz de la consulta y compone el `Where` por encima (comprobado, `ToQueryString()`):

```text
.param set @ef_filter__CurrentTenantId '11111111-1111-1111-1111-111111111111'

SELECT "d"."Id", "d"."CreatedAt", "d"."CustomerId", "d"."TenantId", "d"."Total"
FROM (
    SELECT * FROM Orders
) AS "d"
WHERE "d"."TenantId" = @ef_filter__CurrentTenantId
```

Lo que **no** pasa por el filtro es todo SQL que no devuelva una entidad con filtro: `Database.SqlQueryRaw<T>`, `ExecuteSqlRaw` y la conexión subyacente. Con `acme` activo y dos pedidos en la tabla:

```text
Database.SqlQueryRaw<decimal>: 2 totales: 120,0, 9999,0
Conexión directa (ADO.NET/Dapper): 2 pedidos
```

Los totales de `globex` (`9999,0`) llegan a `acme`. Dapper no se ejecutó, pero trabaja sobre la misma conexión ADO.NET y se comporta igual. Regla: en SQL escrito a mano, el `WHERE tenant_id = @tenant` va siempre, y RLS es la red de seguridad.

### Entidades hijas sin filtro

Si la entidad hija no tiene `TenantId` ni filtro, alcanzarla directamente devuelve filas de todos. En el modelo de prueba, `Invoice` tiene filtro y `InvoiceItem` (sus líneas) no:

```text
Invoices:                         1
InvoiceItems (hija sin filtro):   2 -> Factura de globex, Factura de acme
InvoiceItems.Include(Invoice):    1
```

`db.InvoiceItems` devuelve las líneas de las dos facturas. Con `Include(i => i.Invoice)`, en cambio, aparece solo una: la relación es obligatoria, EF usa un `INNER JOIN` con la tabla `Invoices` filtrada y descarta las líneas cuyo padre está oculto. Por eso el resultado cambia según la forma de la consulta, y EF avisa al construir el modelo (texto real, evento `PossibleIncorrectRequiredNavigationWithQueryFilterInteractionWarning`):

```text
warn: ... CoreEventId.PossibleIncorrectRequiredNavigationWithQueryFilterInteractionWarning[10622]
      Entity 'Invoice' has a global query filter defined and is the required end of a relationship
      with the entity 'InvoiceItem'. This may lead to unexpected results when the required entity
      is filtered out. Either configure the navigation as optional, or define matching query
      filters for both entities in the navigation.
```

La documentación de EF Core propone dos salidas: hacer la navegación opcional (`LEFT JOIN`) o definir filtros coherentes en ambas entidades. En multi-tenancy la segunda es la correcta, y la forma más simple es que la hija **también** lleve `TenantId` e implemente `ITenantEntity`, de modo que el bucle le ponga el filtro. Hacer la navegación opcional resolvería la advertencia pero dejaría la hija sin proteger. Tratar esa advertencia como error en el arranque es una buena regla.

### Vistas, procedimientos y herramientas externas

Una vista, un procedimiento almacenado o una herramienta de BI que lea las tablas no pasa por EF Core, y por tanto por ningún filtro. Esos caminos solo los cubre RLS, o su propio `WHERE`. No se ejecutó ninguno: se deduce de que el filtro vive en la aplicación.

## Row-Level Security como segunda barrera

*Row-Level Security* es una función del motor que filtra las filas **dentro de la base de datos**, según una condición asociada a la tabla, para toda consulta que llegue por esa conexión, venga de EF, de Dapper o de una persona con `psql`. Es la defensa cuando falla el filtro de la aplicación.

> Los ejemplos de esta sección **no se ejecutaron en esta máquina**: no hay PostgreSQL ni SQL Server disponibles. Están escritos a partir de la documentación oficial citada, que sí se leyó; lo que no figura en esas páginas se marca como no verificado.

### PostgreSQL

La documentación (sección *5.9. Row Security Policies*, consultada el 2026-11-09) describe lo siguiente: con `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`, todo acceso normal a la tabla debe estar permitido por una política, y sin políticas rige un *default-deny* (ninguna fila visible ni modificable). Las políticas se crean con `CREATE POLICY`; `USING` define las filas visibles y `WITH CHECK` las que se pueden escribir (si se omite, toma la misma expresión que `USING`). **Los superusuarios y los roles con `BYPASSRLS` siempre se saltan la seguridad de filas, y el propietario de la tabla normalmente también**, salvo que se ejecute `ALTER TABLE ... FORCE ROW LEVEL SECURITY`.

```sql
-- NO ejecutado en esta máquina
CREATE ROLE app_user LOGIN NOBYPASSRLS;           -- rol con el que se conecta la aplicación
GRANT SELECT, INSERT, UPDATE, DELETE ON orders TO app_user;

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;      -- también se aplica al propietario

CREATE POLICY tenant_isolation ON orders
    USING      (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);
```

`current_setting('app.tenant_id', true)` lee una variable de configuración personalizada de la sesión; con el segundo argumento a `true` devuelve `NULL` si no existe en lugar de lanzar un error (así lo describe la documentación de las funciones de administración de PostgreSQL, consultada el 2026-11-09). Con `NULL` la comparación no es verdadera y no se ve ninguna fila: falla cerrado. El `NULLIF(..., '')` cubre una variable que exista con valor vacío; ese caso concreto no se probó. Que `app.tenant_id` pueda usarse como nombre de variable personalizada sin declararla es comportamiento de PostgreSQL que no figura en la página de RLS y no se verificó aquí.

La aplicación debe conectarse con un rol que **no** sea propietario de las tablas ni tenga `BYPASSRLS`: las migraciones se ejecutan con otro rol. Si la aplicación se conecta como propietario sin `FORCE`, la política existe y no se aplica.

### SQL Server

Su documentación (*Row-Level Security*, consultada el 2026-11-09) distingue dos tipos de predicado: los de **filtro** ocultan filas en lecturas, `UPDATE` y `DELETE` sin avisar, y los de **bloqueo** hacen fallar con error las escrituras que violen el predicado. Un predicado es una función con valores de tabla en línea, que una `SECURITY POLICY` asocia a la tabla. A diferencia de PostgreSQL, los usuarios `dbo` y los miembros de `db_owner` **sí** quedan sujetos a la política; si necesitan ver todo, el predicado debe permitirlo.

```sql
-- NO ejecutado en esta máquina
CREATE SCHEMA Security;
GO
CREATE FUNCTION Security.fn_tenant_predicate(@TenantId uniqueidentifier)
    RETURNS TABLE
    WITH SCHEMABINDING
AS
    RETURN SELECT 1 AS allowed
    WHERE @TenantId = TRY_CAST(CAST(SESSION_CONTEXT(N'TenantId') AS nvarchar(36)) AS uniqueidentifier);
GO
CREATE SECURITY POLICY Security.TenantPolicy
    ADD FILTER PREDICATE Security.fn_tenant_predicate(TenantId) ON dbo.Orders,
    ADD BLOCK  PREDICATE Security.fn_tenant_predicate(TenantId) ON dbo.Orders AFTER INSERT,
    ADD BLOCK  PREDICATE Security.fn_tenant_predicate(TenantId) ON dbo.Orders AFTER UPDATE
    WITH (STATE = ON);
```

El ejemplo de la documentación sobre una aplicación de capa intermedia con un usuario SQL compartido usa la misma idea: guarda el identificador en `SESSION_CONTEXT` con `sp_set_session_context` y un predicado de filtro y otro de bloqueo `AFTER INSERT`. La forma exacta de la conversión del valor (`CAST` a `nvarchar` y después `TRY_CAST`) no está en esa página, que convierte a `int`; no se verificó. Si `SESSION_CONTEXT` no está definido devuelve `NULL` y no coincide ninguna fila. El predicado `AFTER UPDATE` impide además mover una fila a otro tenant.

### Pasar el tenant a la sesión desde .NET

Ambos motores necesitan saber el tenant de la petición **en la conexión** que usa EF. Un `DbConnectionInterceptor` lo establece cada vez que EF abre la conexión:

```csharp
// NO ejecutado en esta máquina (PostgreSQL con Npgsql)
public class TenantConnectionInterceptor(ITenantContext tenant) : DbConnectionInterceptor
{
    public override async Task ConnectionOpenedAsync(
        DbConnection connection, ConnectionEndEventData e, CancellationToken ct = default)
    {
        await using var cmd = connection.CreateCommand();
        cmd.CommandText = "SELECT set_config('app.tenant_id', @tenant, false)";
        var p = cmd.CreateParameter();
        p.ParameterName = "tenant";
        p.Value = tenant.TenantId?.ToString() ?? "";   // sin tenant: valor vacío, no el del anterior
        cmd.Parameters.Add(p);
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
```

`set_config(nombre, valor, is_local)` es una función de PostgreSQL (documentación consultada el 2026-11-09): con `is_local = true` el valor solo vale durante la transacción actual y con `false`, durante el resto de la sesión. En SQL Server la sentencia equivalente es `EXEC sp_set_session_context @key = N'TenantId', @value = @tenant;`, y la documentación indica que `@read_only = 1` impide cambiar el valor hasta que la conexión se cierra (se devuelve al *pool*). El interceptor también necesita su versión síncrona (`ConnectionOpened`) si se usan consultas síncronas, y se registra junto al de `SaveChanges` con `AddInterceptors`.

**La trampa del *pool*.** Las conexiones se reutilizan: una conexión que sirvió a `globex` vuelve al *pool* y la siguiente petición, de `acme`, puede recibirla. Si el valor de sesión no se establece **en cada apertura**, o si hay un camino (un `HttpClient` de otro servicio, Dapper con otra fábrica de conexiones, un job) que abre conexiones sin pasar por el interceptor, la sesión conserva el tenant de la petición anterior y RLS aísla con el tenant equivocado. Dos medidas: establecer siempre el valor, incluso vacío (el ejemplo lo hace), y, en PostgreSQL, usar `is_local = true` dentro de una transacción para que el valor muera con ella. Si el *pool* restablece el estado de sesión al devolver la conexión depende del proveedor y de su configuración; no se leyó en la documentación ni se probó, y no debe darse por hecho.

## Defensa en profundidad

Ninguna capa cubre todo. La tabla dice qué cubre cada una y qué deja pasar:

| Capa | Cubre | NO cubre |
|---|---|---|
| Filtro global de EF Core | Toda consulta LINQ sobre entidades con filtro; `ExecuteUpdate`/`ExecuteDelete` | `IgnoreQueryFilters`, `SqlQueryRaw`, Dapper, hijas sin filtro, `Update` de entidades desconectadas |
| Interceptor de escritura | `TenantId` automático; rechaza `Add` con otro tenant | Lecturas; `Update`/`Attach` con el `TenantId` propio y el `Id` ajeno |
| RLS (política con `USING`/`WITH CHECK` o predicados de filtro y bloqueo) | Cualquier consulta de la conexión: EF, SQL crudo, Dapper, herramientas con ese rol | Conexiones con rol propietario o `BYPASSRLS` (PostgreSQL), sesión con el tenant equivocado, tablas sin política |
| Test de aislamiento | Entidad nueva sin filtro; regresiones del filtro; usos de `IgnoreQueryFilters` | Lo que no pasa por el modelo (SQL crudo, vistas) |

El filtro evita casi todos los errores del día a día, RLS cubre los caminos que lo esquivan y los tests detectan que alguien dejó una de las dos sin poner.

## Test de aislamiento automatizado

El test recorre el **modelo de EF**, no una lista escrita a mano, para que una entidad nueva sin filtro haga fallar la integración continua. Las entidades globales se declaran explícitamente. Paquetes: `xunit` 2.9.3, `Microsoft.EntityFrameworkCore.Sqlite` 10.0.14.

```csharp
public class TenantIsolationTests : IDisposable
{
    private static readonly HashSet<Type> Global = [typeof(Tenant), typeof(Country)];   // sin tenant
    private readonly SqliteConnection _conn = new("Data Source=:memory:");

    public TenantIsolationTests()
    {
        _conn.Open();
        using var schema = Open(Guid.Empty); schema.Database.EnsureCreated();
        using var raw = new ManualDb(new DbContextOptionsBuilder<ManualDb>().UseSqlite(_conn).Options);
        Seed.Fill(raw); raw.SaveChanges();   // filas de acme y de globex en cada tabla
    }

    private AppDb Open(Guid tenant) =>
        new(new DbContextOptionsBuilder<AppDb>().UseSqlite(_conn).Options, new TenantContext { TenantId = tenant });

    public static IEnumerable<object[]> EntityTypes()
    {
        using var db = new AppDb(new DbContextOptionsBuilder<AppDb>().UseSqlite("Data Source=:memory:").Options, new TenantContext());
        return db.Model.GetEntityTypes().Select(t => new object[] { t.ClrType.Name }).ToList();
    }

    [Theory, MemberData(nameof(EntityTypes))]
    public void Cada_entidad_es_global_o_tiene_filtro_de_tenant(string name)
    {
        using var db = Open(Seed.Acme);
        var type = db.Model.GetEntityTypes().Single(t => t.ClrType.Name == name);
        if (Global.Contains(type.ClrType)) return;

        Assert.True(typeof(ITenantEntity).IsAssignableFrom(type.ClrType),
            $"{name} no implementa ITenantEntity: añade TenantId o inclúyela en la lista de entidades globales.");
        Assert.NotEmpty(type.GetDeclaredQueryFilters());
    }

    [Theory, MemberData(nameof(EntityTypes))]
    public void Acme_no_ve_filas_de_globex(string name)
    {
        using var db = Open(Seed.Acme);
        var type = db.Model.GetEntityTypes().Single(t => t.ClrType.Name == name).ClrType;
        if (!typeof(ITenantEntity).IsAssignableFrom(type)) return;

        var list = ((IEnumerable<ITenantEntity>)typeof(TenantIsolationTests)
            .GetMethod(nameof(Load), BindingFlags.NonPublic | BindingFlags.Static)!
            .MakeGenericMethod(type).Invoke(null, [db])!).ToList();

        Assert.NotEmpty(list);                                   // el seed tiene filas de acme en cada entidad
        Assert.All(list, r => Assert.Equal(Seed.Acme, r.TenantId));
    }

    private static List<ITenantEntity> Load<T>(AppDb db) where T : class, ITenantEntity =>
        db.Set<T>().AsEnumerable().Cast<ITenantEntity>().ToList();

    public void Dispose() => _conn.Dispose();
}
```

Con las cinco entidades del modelo (`Tenant`, `Country`, `Customer`, `Order`, `OrderLine`) y el test de `IgnoreQueryFilters` de arriba, `dotnet test`:

```text
Correctas! - Con error:     0, Superado:    11, Omitido:     0, Total:    11
```

Y al quitar `: ITenantEntity` de `OrderLine` (la hija que alguien olvida marcar):

```text
Con error TenantIsolationTests.Cada_entidad_es_global_o_tiene_filtro_de_tenant(name: "OrderLine") [4 ms]
   OrderLine no implementa ITenantEntity: añade TenantId o inclúyela en la lista de entidades globales.
Con error! - Con error:     1, Superado:   10, Omitido:     0, Total:    11
```

El test falla antes de que la entidad llegue a producción. Con el filtro puesto, el segundo test comprueba además que los datos de `acme` son los únicos visibles (pasa en cada entidad).

## Rendimiento

El filtro añade `WHERE TenantId = @tenant` a **todas** las consultas, así que `TenantId` debe ser la **primera** columna de los índices que usen las consultas habituales. Un índice `(TenantId, CreatedAt)` sirve para "los pedidos de este tenant, ordenados por fecha":

```csharp
mb.Entity<Order>().HasIndex(o => new { o.TenantId, o.CreatedAt });
```

`EXPLAIN QUERY PLAN` de SQLite sobre `SELECT * FROM Orders WHERE TenantId = 'x' ORDER BY CreatedAt`, sin y con ese índice:

```text
sin índice con TenantId: SCAN Orders
sin índice con TenantId: USE TEMP B-TREE FOR ORDER BY
con (TenantId, CreatedAt): SEARCH Orders USING INDEX IX_Orders_TenantId_CreatedAt (TenantId=?)
```

Sin índice, el motor recorre toda la tabla (de todos los tenants) y ordena aparte; con él, busca directamente las filas del tenant y ya salen ordenadas, sin paso de ordenación. Es el plan de SQLite: otros motores muestran planes distintos con la misma idea. No se midieron tiempos. En PostgreSQL, además, RLS añade la política como condición a cada consulta; si su expresión llama a funciones, conviene mantenerla simple (la documentación de PostgreSQL recomienda que la política consulte solo valores de la propia fila, el caso más simple y de mejor rendimiento).

## Cuándo NO basta el aislamiento por fila

- **Exigencia contractual de aislamiento físico.** Si el cliente o la normativa piden que sus datos estén en una base propia, el aislamiento por fila no lo cumple por mucho que las dos capas funcionen: las filas siguen en las mismas tablas. [Estrategias de Aislamiento](Estrategias-de-Aislamiento.md) compara las alternativas.
- **Un tenant que consume mucho.** El filtro aísla datos, no recursos: una consulta pesada de un tenant afecta a los demás en la misma base. Es el *vecino ruidoso*, tratado en [Retos Avanzados](Retos-Avanzados.md).
- **Copias de seguridad y restauración por tenant.** Restaurar solo los datos de un tenant desde una copia compartida es manual y delicado; con base propia es una restauración normal.
- **Equipos con acceso directo a la base de datos.** Quien entra con una cuenta propietaria o con `BYPASSRLS` ve todos los tenants, y ninguna de las dos capas lo evita.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| Todas las peticiones ven los datos del primer tenant tras arrancar | El tenant se capturó al construir el modelo (variable local en `OnModelCreating`) en vez de leerse de una propiedad del contexto |
| Un informe o un job muestra datos de todos los tenants | `IgnoreQueryFilters()` usado sin restricción o sin la lógica de tenant propia |
| Una consulta con `SqlQueryRaw`/Dapper devuelve filas ajenas | SQL escrito a mano sin `WHERE tenant_id`; ni el filtro ni nada lo añaden |
| Se ven filas de otro tenant al consultar la entidad hija directamente | La hija no tiene `TenantId` ni filtro; solo se protegía al pasar por el padre |
| RLS está activa y no filtra nada | La aplicación se conecta como propietario de la tabla (sin `FORCE ROW LEVEL SECURITY`) o con un rol con `BYPASSRLS` |
| Una petición ve, de forma intermitente, datos del tenant anterior | La conexión del *pool* conserva el valor de sesión de la petición anterior |
| Un pedido de otro tenant cambia de dueño o se sobrescribe | `Update`/`Attach` con un `Id` del cliente sin cargar antes la fila por la consulta filtrada |
| Se guardan filas con un `TenantId` elegido por quien llama | El `TenantId` se acepta del cuerpo de la petición en vez de asignarse desde el contexto |

## Buenas prácticas avanzadas

- **Que el filtro falle cerrado.** Si no hay tenant (un job, un test mal montado), el filtro no puede degradarse a "sin filtro": con `Guid.Empty` no coincide ninguna fila (comprobado: 0 pedidos visibles sin tenant) y el interceptor lanza excepción al escribir. Un `tenant?.Id` que evalúa a `null` y deja pasar todo es la fuga más silenciosa.
- **Claves foráneas compuestas para impedir referencias cruzadas.** El filtro evita *leer* filas ajenas, pero no impide que un pedido de `acme` apunte a un cliente de `globex` por `CustomerId`. Si la clave foránea incluye el tenant, la propia base lo hace imposible:

  ```sql
  ALTER TABLE Orders ADD CONSTRAINT FK_Orders_Customers
      FOREIGN KEY (TenantId, CustomerId) REFERENCES Customers (TenantId, Id);
  ```

  Requiere una clave única `(TenantId, Id)` en `Customers`. No se ejecutó en esta máquina.
- **Con RLS, bloquea también la escritura.** En SQL Server, un predicado de filtro solo oculta filas al leer; sin predicado de bloqueo, una consulta con un fallo puede insertar o actualizar filas con el tenant de otro. En PostgreSQL, `WITH CHECK` cumple ese papel (y toma el valor de `USING` si se omite).
- **Trata `IgnoreQueryFilters` como excepción vigilada.** Concentra su uso en un módulo de plataforma y deja un test que falle ante cualquier aparición fuera de él; con filtros con nombre, desactiva solo el que haga falta.
- **Convierte en error la advertencia 10622.** Una relación obligatoria con un padre filtrado y una hija sin filtro es una fuga latente; configurar `ConfigureWarnings(w => w.Throw(CoreEventId.PossibleIncorrectRequiredNavigationWithQueryFilterInteractionWarning))` hace que el arranque falle. (No se probó esa configuración concreta.)
- **`TenantId` el primero en los índices.** Es el motivo habitual de que la aplicación fuera bien con 10 tenants y se arrastre con 500.

## Documentación oficial

- [Global Query Filters (EF Core)](https://learn.microsoft.com/ef/core/querying/filters): lo útil es el ejemplo de multi-tenancy con el contexto, los filtros con nombre de EF Core 10, `IgnoreQueryFilters` y la sección de navegaciones obligatorias; ir cuando se dude de cómo se compone un filtro con `Include`.
- [PostgreSQL: Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html): qué se aplica a quién (propietarios, `BYPASSRLS`, `FORCE`), `USING` frente a `WITH CHECK` y políticas permisivas y restrictivas; ir antes de escribir la primera política.
- [SQL Server: Row-Level Security](https://learn.microsoft.com/sql/relational-databases/security/row-level-security): predicados de filtro y de bloqueo, `SESSION_CONTEXT` con una aplicación de capa intermedia y las limitaciones y fugas conocidas; ir al diseñar el predicado.
- [Entity Framework Core](../../bases-de-datos/acceso-a-datos-dotnet/Entity-Framework-Core.md) y [PostgreSQL](../../bases-de-datos/postgresql/PostgreSQL.md) en este repositorio: contexto general de EF Core y del motor.

---

*En resumen: aislar por fila es poner a cada dato su dueño y dos guardias automáticos —el filtro del ORM y la política del motor— más un test que avise si falta uno, para que el aislamiento no dependa de recordar un `WHERE`.*
