# Estrategias de Aislamiento de Datos

## ¿Qué es?

Son las formas de **separar los datos de cada tenant** (cada empresa cliente de una aplicación SaaS) en la capa de persistencia. Hay tres clásicas: una base de datos por tenant, un esquema por tenant dentro de una misma base, o una base compartida en la que cada fila lleva una columna `TenantId`. Se pueden combinar tenant a tenant (modelo híbrido).

## ¿Por qué existe?

Una aplicación de gestión de pedidos da servicio a Acme S.L. y a Globex S.A. El pedido de `acme` no debe verse jamás desde `globex`, y la pregunta de diseño es *dónde se guarda cada pedido para que eso se cumpla*. No hay una respuesta única, porque tres fuerzas tiran en direcciones opuestas:

- **Aislamiento** (qué pasa si hay un bug, un fallo humano o una auditoría).
- **Coste y escala** (cuánto cuesta atender a 10 tenants y cuánto a 10.000).
- **Complejidad operativa** (cuánto duele migrar, copiar, restaurar y vigilar).

> Piensa en vivienda. La base por tenant es un **chalet** por familia: máxima privacidad, máximo coste, y cada chalet tiene su propio mantenimiento. El esquema por tenant es un **piso** por familia en el mismo bloque: paredes propias, portal y tuberías comunes. La base compartida es un **albergue con taquillas**: lo más barato, y la privacidad depende de que cada cual abra solo su taquilla.

## ¿Cuándo y para qué se usa?

La estrategia se elige al diseñar el producto, según los clientes que se esperan:

- SaaS para pocos clientes grandes con exigencias contractuales o legales (bancos, sanidad): base por tenant.
- Producto masivo para miles de pequeñas cuentas: base compartida.
- Catálogo mixto (plan básico y plan *enterprise*): híbrido, con la mayoría de tenants en base compartida y los grandes en base propia.

Cómo se averigua el tenant de cada petición está en [Identificación del Tenant](Identificacion-del-Tenant.md); aquí se da por resuelto y los ejemplos usan una cabecera `X-Tenant` solo por simplicidad.

## Las tres estrategias comparadas

| Criterio | Base por tenant (chalet) | Esquema por tenant (piso) | Base compartida + `TenantId` (albergue) |
|---|---|---|---|
| **Aislamiento** | Físico: otra base, otras credenciales posibles | Intermedio: mismo motor y base, objetos separados y permisos por esquema | Lógico: depende de que toda consulta filtre |
| **Coste de infraestructura por tenant** | Alto: una base por cliente (en servidores compartidos o *pools* elásticos baja, pero no desaparece) | Medio: una sola base, pero cada tenant añade un juego de tablas | Mínimo: un tenant nuevo son filas nuevas |
| **Nº de tenants razonable** (criterio, no medición) | Decenas o cientos | Decenas o pocos cientos: cada tenant multiplica tablas e índices en el catálogo del motor | Miles o más |
| **Complejidad operativa** | Alta: N bases que vigilar, parchear y monitorizar | Alta: poca herramienta lo soporta de serie (ver más abajo) | Baja: una base |
| **Migraciones de esquema** | Hay que aplicarlas N veces, y puede haber tenants a medias | También N veces, dentro de la misma base | Una sola vez para todos |
| **Copia y restauración de un solo tenant** | Directa: se restaura su base | Posible a mano (p. ej. `pg_dump --schema`), sin soporte de las herramientas de copia a nivel de base | Difícil: hay que restaurar la base entera en otro sitio y extraer sus filas |
| **Rendimiento y vecino ruidoso** | Mejor aislado: cada base tiene sus recursos, o el servidor los reparte | Compartido: mismo motor, mismo almacenamiento | Peor: un tenant grande compite con todos en tablas e índices comunes |
| **Cumplimiento y residencia de datos** | La mejor opción: una base puede vivir en la región o con las claves que exija el cliente | Limitada: todos los esquemas viven en la misma base y región | Solo con aislamiento lógico; no se pueden mapear tenants a regiones |
| **Consultas entre tenants (informes de la plataforma)** | Incómodas: hay que recorrer N bases o volcarlas a un almacén de informes | Posibles dentro de la misma base (`UNION` entre esquemas) | Triviales: una consulta sin filtro |

Los calificativos («alto», «medio») son criterio de diseño, no mediciones: los umbrales reales dependen del motor, del tamaño de cada tenant y de la herramienta de operación. La guía de arquitectura de Microsoft (ver «Documentación oficial») recoge las mismas consideraciones y añade una: cuando los tenants necesitan sus propias claves de cifrado, políticas de copia propias o ubicaciones geográficas distintas, hay que aislarlos o agruparlos con quien tenga las mismas políticas.

## Base de datos por tenant

Cada tenant tiene su propia base. La aplicación elige la cadena de conexión en cada petición. En EF Core la forma directa es construir las opciones del `DbContext` con la cadena del tenant actual; la [documentación de EF Core](https://learn.microsoft.com/en-us/ef/core/miscellaneous/multitenancy) indica que, con una base por tenant, cambiar a la base correcta se reduce a proporcionar la cadena de conexión correcta.

El ejemplo guiado usa SQLite, con un fichero por tenant (`acme.db`, `globex.db`), un catálogo de tenants con la ubicación de cada uno y un servidor mínimo de ASP.NET Core. Primero las entidades y el catálogo:

```csharp
public enum Isolation { Shared, Dedicated }

public class Tenant
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string Subdomain { get; set; } = "";
    public bool IsActive { get; set; }
    public Isolation Isolation { get; set; }        // dónde viven sus datos
    public string ConnectionString { get; set; } = ""; // solo si es Dedicated
}

public class Order
{
    public int Id { get; set; }
    public int TenantId { get; set; }
    public decimal Total { get; set; }
}

public class TenantContext { public Tenant? Current { get; set; } }

public class AppDbContext(DbContextOptions<AppDbContext> o) : DbContext(o)
{
    public DbSet<Order> Orders => Set<Order>();
}
```

Y el registro: el `AppDbContext` de cada petición se construye con la cadena del tenant, vía un selector que mira el catálogo y no está cableado en el código de negocio:

```csharp
builder.Services.AddScoped<TenantContext>();
builder.Services.AddScoped<AppDbContext>(sp =>
{
    var tenant = sp.GetRequiredService<TenantContext>().Current
        ?? throw new InvalidOperationException("No hay tenant en la petición.");
    var options = new DbContextOptionsBuilder<AppDbContext>()
        .UseSqlite(ConnectionStringFor(tenant))
        .Options;
    return new AppDbContext(options);
});

// El selector de estrategia
static string ConnectionStringFor(Tenant t) =>
    t.Isolation == Isolation.Dedicated ? t.ConnectionString : "Data Source=shared.db";

// Un endpoint de lectura (filtra por TenantId; su sentido se explica más abajo)
app.MapGet("/orders", async (AppDbContext db, TenantContext tc) =>
    await db.Orders.Where(o => o.TenantId == tc.Current!.Id)
        .Select(o => new { o.Id, o.TenantId, o.Total }).ToListAsync());
```

Con `acme` y `globex` ambos como `Dedicated` (cada uno con su fichero, `Data Source=acme.db` y `Data Source=globex.db`), cada uno con sus pedidos, y arrancado el servidor, se consulta con `curl`:

```bash
curl -s -H "X-Tenant: acme" localhost:6482/orders
curl -s -H "X-Tenant: globex" localhost:6482/orders
curl -si -H "X-Tenant: initech" localhost:6482/orders
```

```text
[{"id":1,"tenantId":1,"total":120.5},{"id":2,"tenantId":1,"total":80.0}]
[{"id":1,"tenantId":2,"total":999.99}]
HTTP/1.1 404 Not Found
Tenant desconocido
```

La misma consulta devuelve dos pedidos de Acme y uno de Globex porque son bases distintas (el `id: 1` aparece en ambas: cada base numera por su cuenta). Un tenant inexistente no recibe ninguna conexión. Las salidas provienen de una ejecución real con .NET 10 y `Microsoft.EntityFrameworkCore.Sqlite` 10.0.0; en producción la cadena apuntaría a un servidor de base de datos y el catálogo viviría en una base propia de la plataforma.

Una ventaja de esta estrategia: un olvido de filtro no filtra datos ajenos. Si un endpoint se escribe sin el `Where` por `TenantId`, solo ve lo que hay en la base del tenant actual.

## Esquema por tenant

Una sola base, y cada tenant tiene un *schema* (un espacio de nombres de tablas): `acme.Orders`, `globex.Orders`. Estas tablas tienen el mismo nombre en esquemas distintos, y el motor resuelve cuál es la que se quiere.

**Esta sección no se ha ejecutado en esta máquina**: SQLite no tiene esquemas y no había ni PostgreSQL ni SQL Server disponibles. Lo que sigue se apoya en la documentación de cada motor y de EF Core, consultada el 2026-11-09.

En PostgreSQL, las consultas con nombre sin cualificar buscan en el *search path*, una lista de esquemas; el primero que contiene la tabla gana ([documentación de PostgreSQL sobre esquemas](https://www.postgresql.org/docs/current/ddl-schemas.html)). Alta de un tenant y selección en la sesión:

```sql
CREATE SCHEMA acme;
CREATE TABLE acme."Orders" (...);   -- el mismo DDL por cada esquema

SET search_path TO acme;
SELECT * FROM "Orders";             -- lee acme."Orders"
```

En SQL Server el equivalente es `CREATE SCHEMA acme;` y tablas cualificadas (`acme.Orders`); [`CREATE SCHEMA`](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-schema-transact-sql) se documenta en Microsoft Learn. No hay un `search_path` por sesión equivalente: se cualifica el nombre en cada consulta o se usa el esquema por defecto del usuario de base de datos (dato de memoria, sin verificar).

En EF Core, el esquema de las tablas se fija con `HasDefaultSchema` (existe en el modelo, como muestra la [documentación de tipos de entidad](https://learn.microsoft.com/en-us/ef/core/modeling/entity-types)). Con un tenant por petición, el nombre se leería del tenant actual:

```csharp
public class AppDbContext(DbContextOptions<AppDbContext> o, TenantContext tenant) : DbContext(o)
{
    private readonly string _schema = tenant.Current!.Subdomain;

    protected override void OnModelCreating(ModelBuilder b) =>
        b.HasDefaultSchema(_schema);   // ¡trampa! ver más abajo
}
```

La documentación de EF Core avisa de que el escenario de varios esquemas no está soportado directamente y no es una solución recomendada, y su ejemplo solo cubre el caso en que las migraciones de EF Core no se usan para actualizar la base.

### La trampa del caché de modelo

EF Core construye el modelo y ejecuta `OnModelCreating` **una sola vez por tipo de contexto**, y guarda el resultado. Según [la documentación de modelos dinámicos](https://learn.microsoft.com/en-us/ef/core/modeling/dynamic-model), la clave de caché por defecto contiene solo el tipo del contexto: se asume que, para un tipo dado, el modelo es siempre el mismo. Así que el primer tenant que llegue fija el esquema (o el nombre de tabla) para todos los demás. Para que el modelo cambie hay que sustituir `IModelCacheKeyFactory` por una implementación que incluya el esquema en la clave.

Esta trampa sí se ha ejecutado, con un equivalente en SQLite: en vez de un esquema, el nombre de la tabla depende del tenant (`ToTable("Orders_" + tenant)`), que es el mismo mecanismo (el modelo depende de un dato de la petición). Con datos distintos en `Orders_acme` (`120.50`) y `Orders_globex` (`999.99`) y sin tocar el caché:

```text
acme: 120.50
globex: 120.50      ← globex lee la tabla de acme, sin ningún error
```

Con una clave de caché que incluye el tenant:

```csharp
public class TenantKey : IModelCacheKeyFactory
{
    public object Create(DbContext c, bool designTime) =>
        c is TenantDb t ? (c.GetType(), t.Tenant, designTime) : (c.GetType(), designTime);
}
// y en OnConfiguring: optionsBuilder.ReplaceService<IModelCacheKeyFactory, TenantKey>();
```

```text
acme: 120.50
globex: 999.99
```

El fallo es silencioso: no lanza excepción, devuelve los datos del tenant equivocado. Con un esquema el efecto sería el mismo.

## Base compartida con `TenantId`

Todos los tenants comparten tablas y cada fila lleva la columna que indica de quién es. Es la estrategia más barata y la más común en productos masivos:

```csharp
public class Order
{
    public int Id { get; set; }
    public int TenantId { get; set; }   // a qué tenant pertenece la fila
    public decimal Total { get; set; }
}
```

Con el mismo servidor de la sección anterior, pero con `acme` y `globex` como `Shared` (ambos en `shared.db`), cada petición devuelve lo suyo gracias al filtro explícito:

```text
$ curl -s -H "X-Tenant: acme" localhost:6482/orders
[{"id":1,"tenantId":1,"total":120.5},{"id":2,"tenantId":1,"total":80.0}]
$ curl -s -H "X-Tenant: globex" localhost:6482/orders
[{"id":3,"tenantId":2,"total":999.99}]
```

Los identificadores son únicos (`id: 3`) porque la tabla es una sola. El peligro es olvidar el filtro. Una variante del endpoint sin el `Where` por `TenantId`:

```csharp
app.MapGet("/orders-sin-filtro", async (AppDbContext db) =>
    await db.Orders.Select(o => new { o.Id, o.TenantId, o.Total }).ToListAsync());
```

```text
$ curl -s -H "X-Tenant: globex" localhost:6482/orders-sin-filtro
[{"id":1,"tenantId":1,"total":120.5},{"id":2,"tenantId":1,"total":80.0},{"id":3,"tenantId":2,"total":999.99}]
```

Globex ve los pedidos de Acme. Es el albergue sin candados: nada falla, solo se enseña lo que no toca. Por eso el filtro no se escribe a mano en cada consulta: se automatiza con *query filters* de EF Core y, como segunda barrera, con *Row-Level Security* del motor, algo que se explica en [Aislamiento por Fila](Aislamiento-por-Fila.md).

## Elegir estrategia

| Pregunta | Si la respuesta es… | Tiende hacia |
|---|---|---|
| ¿Cuántos tenants habrá? | Miles o más | Base compartida |
| | Decenas | Cualquiera; manda el resto |
| ¿Algún cliente exige aislamiento por contrato (región, claves propias, auditoría de «su» base)? | Sí | Base propia para ese cliente |
| ¿Los tamaños son muy desiguales? | Sí, unos pocos tenants enormes y muchos pequeños | Híbrido |
| ¿Hay equipo de operaciones capaz de gestionar N bases y su tooling? | No | Base compartida |
| | Sí | Más margen para base por tenant |
| ¿Hace falta informar sobre toda la plataforma (facturación, métricas)? | Sí, a menudo | Base compartida, o un almacén de informes que reciba datos de las bases propias |

La recomendación honesta para la mayoría de productos es **empezar con base compartida y poder mover a un tenant grande a una base propia**. Es lo más barato al principio y deja una salida cuando llegue el primer cliente con exigencias o un tenant que degrade a los demás. Esa salida es el **modelo híbrido**: acme en `shared.db` y globex como tenant «premium» en su base propia, decidido tenant a tenant.

Lo que hace posible el cambio no es una promesa, es un diseño: la ubicación de los datos de cada tenant vive en un **catálogo** (la tabla `Tenant` con `Isolation` y `ConnectionString`) y el código solo ve un **selector** (`ConnectionStringFor`) que, dado un tenant, devuelve dónde conectarse. Ningún caso de uso sabe en qué base vive el tenant. Con acme como `Shared` y globex como `Dedicated`, las mismas rutas dan:

```text
$ curl -s -H "X-Tenant: acme" localhost:6482/orders
[{"id":1,"tenantId":1,"total":120.5},{"id":2,"tenantId":1,"total":80.0}]
$ curl -s -H "X-Tenant: globex" localhost:6482/orders
[{"id":1,"tenantId":2,"total":999.99}]
$ curl -s -H "X-Tenant: globex" localhost:6482/orders-sin-filtro
[{"id":1,"tenantId":2,"total":999.99}]
```

El filtro por `TenantId` sigue en el código aunque la base sea propia: el endpoint sin filtro ya no filtra datos ajenos para Globex, pero conviene que el código sea idéntico en ambas estrategias.

## El coste real día a día

- **Conexiones y pools.** Los proveedores de ADO.NET mantienen un *pool* de conexiones físicas **por cadena de conexión distinta**. En Microsoft.Data.SqlClient la clave del pool incluye la cadena tal cual: según [su documentación](https://learn.microsoft.com/en-us/sql/connect/ado-net/sql-server-connection-pooling), el texto debe coincidir exactamente y un cambio en el orden de las palabras clave crea otro pool. `Max Pool Size` vale 100 por defecto. Npgsql tiene el mismo valor por defecto de 100 ([parámetros de cadena de conexión](https://www.npgsql.org/doc/connection-string-parameters.html)). Con base compartida hay un pool; con 500 tenants en bases propias hay hasta 500 pools, cada uno con su máximo, y la suma de conexiones abiertas puede superar el límite del servidor sin que ninguna consulta concreta sea culpable.
- **Miles de pools.** Con miles de tenants activos en bases propias el reparto deja de ser viable: o se baja `Max Pool Size` por pool a valores pequeños, o se pone un *pooler* externo delante del servidor (PgBouncer en PostgreSQL), o se agrupan tenants en menos bases. Tampoco conviene dejar las conexiones abiertas entre peticiones: se abren tarde y se liberan pronto, y el pool decide cuándo cierra la física.
- **Esquema por tenant.** No multiplica pools (hay una sola base y una sola cadena), pero multiplica los objetos del catálogo del motor, y cada migración se ejecuta N veces.
- **Operación.** En base por tenant, copias de seguridad, parches y monitorización se multiplican por N. En compartida es una sola, pero la restauración de un tenant concreto exige restaurar la base entera en un lugar aparte y extraer sus filas.

## Seguridad de la cadena de conexión por tenant

La cadena de conexión de una base propia incluye credenciales: no debe vivir en el código ni en un fichero versionado. En el ejemplo, el campo `Tenant.ConnectionString` del catálogo contiene solo `Data Source=acme.db` porque SQLite no tiene credenciales; en un motor real, guardar la cadena completa en una tabla en claro replica el problema. Opciones habituales: guardar en el catálogo solo una referencia (el nombre de un secreto) y leer la cadena de un gestor de secretos, o cifrar la columna. Las bases de por qué los secretos no van al control de versiones y cómo manejarlos en desarrollo están en [Gestión de secretos en desarrollo](../../seguridad/gestion-de-secretos-en-desarrollo/README.md). Una credencial distinta por tenant limita además el daño de una fuga: la de Acme no abre la base de Globex.

## Cambiar de estrategia más tarde

Pasar un tenant de base compartida a base propia es un proyecto, no un cambio de configuración. Pasos, sin desarrollarlos:

1. Crear la base nueva con el mismo esquema que la compartida.
2. Copiar las filas del tenant (las de sus tablas y las que cuelgan de ellas).
3. Mantener la copia sincronizada o poner al tenant en solo lectura mientras dura.
4. Cambiar `Isolation` y `ConnectionString` del catálogo, que es el momento del corte.
5. Borrar las filas del tenant en la base compartida, tras comprobar la copia.

Los riesgos concretos: identificadores generados que ya existen fuera (referencias de otras tablas o de otros sistemas), la ventana entre la copia y el corte, y la migración posterior de esa base dedicada, que a partir de ahora hay que aplicar también a ella. Cómo se crea y se migra cada base está en [Aprovisionamiento y Migraciones](Aprovisionamiento-y-Migraciones.md).

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Un tenant ve las tablas o el esquema de otro, sin errores, después del primer tenant atendido | Esquema o nombre de tabla dinámico con el caché de modelo de EF Core por defecto: el modelo se construyó una vez, con el primer tenant (se ejecutó la variante con tabla; ver «Esquema por tenant») |
| Errores `Timeout expired` o `too many connections` con muchos tenants activos, sin una consulta lenta | Un pool de conexiones por cadena distinta: la suma de pools supera el límite del servidor |
| Un tenant ve filas de otro, o un informe suma todos los tenants | En base compartida, una consulta sin filtro por `TenantId` |
| Todos los tenants se vuelven lentos cuando uno hace una carga masiva | Un tenant enorme en la base o tabla compartida: sin base propia, sin cuotas por tenant |
| Un cliente pide recuperar los datos de ayer y solo hay una copia de la base completa | Copias de seguridad de una base compartida: restaurar un solo tenant exige restaurar todo en otro lugar |
| La cadena de conexión de un cliente aparece en un repositorio o en un log | Cadena guardada en el código o en un fichero versionado, o volcada al registrar la configuración |

## Buenas prácticas avanzadas

- **Diseña para el híbrido aunque empieces con una sola estrategia.** Esconde la decisión detrás de un catálogo y un selector (`Tenant.Isolation`, `Tenant.ConnectionString`). Si la estrategia está cableada por todo el código, el día que un cliente *enterprise* exija base propia habrá una reescritura; si está abstraída, es un cambio por tenant.
- **En base compartida, `TenantId` va el primero en los índices.** Como toda consulta filtra por tenant, un índice `(TenantId, CreatedAt)` deja al motor ir directo a las filas del tenant; uno que empiece por `CreatedAt` le obliga a rastrear filas de todos los clientes. Revisa los planes de ejecución con datos de *muchos* tenants: con pocos, cualquier índice parece funcionar.
- **Con base por tenant, limita los pools antes de necesitarlo.** Baja `Max Pool Size`, considera un *pooler* externo y vigila las conexiones totales del servidor, no solo las de cada aplicación.
- **El coste oculto del esquema por tenant es el tooling.** Migraciones, ORMs y herramientas de BI asumen un esquema fijo, y EF Core no lo soporta directamente. Suele ser la opción más cara de operar pese a parecer la intermedia; elígela solo si el equipo puede mantener el tooling a medida.
- **La elección también es legal y comercial.** Hay clientes que exigen su dato en una región (*data residency*), claves propias o auditar «su» base. Solo el aislamiento físico lo permite. Pregunta a negocio qué contratos se esperan antes de elegir; es más barato que descubrirlo con el primer cliente grande.
- **Prueba la restauración de un solo tenant antes de necesitarla.** En compartida es el escenario que más sorprende; ensáyalo con datos reales de un tenant y mide cuánto tarda.

## Documentación oficial

- [Approaches to storage and data in multitenant solutions (Azure Architecture Center)](https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/approaches/storage-data): las consideraciones de escala, aislamiento, vecino ruidoso, copia y restauración y operación comparadas entre enfoques. Merece la pena para argumentar la decisión ante negocio.
- [Multi-tenancy (EF Core)](https://learn.microsoft.com/en-us/ef/core/miscellaneous/multitenancy): ejemplos de una base con *query filter* y de varias bases con cadena por tenant, la advertencia sobre esquemas y el ciclo de vida del `DbContext` al cambiar de tenant. Última actualización indicada en la página: 2022-05-11; el propio texto advierte que son «prácticas que funcionan», no «mejores prácticas».
- [Dynamic model: IModelCacheKeyFactory (EF Core)](https://learn.microsoft.com/en-us/ef/core/modeling/dynamic-model): imprescindible si el modelo (esquema, nombre de tabla) depende del tenant.
- [Esquemas en PostgreSQL](https://www.postgresql.org/docs/current/ddl-schemas.html): `search_path` y permisos por esquema, para el esquema por tenant en ese motor.

---

*En resumen: aislar tenants es elegir dónde poner la pared (entre bases, entre esquemas o entre filas) sabiendo que más aislamiento cuesta más, y guardar la ubicación de cada tenant en un catálogo para poder moverla cuando haga falta.*
