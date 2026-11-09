# Multi-Tenancy

## ¿Qué es?

La **multi-tenancy** (o multi-inquilino) es un modelo de arquitectura en el que una misma aplicación, desplegada una sola vez, da servicio a muchos clientes —llamados *tenants*— manteniendo los datos de cada uno separados e invisibles para los demás. Un *tenant* es una empresa u organización cliente, no una persona: dentro de un tenant hay muchos usuarios.

## ¿Por qué existe?

Una herramienta de gestión de pedidos se vende a 500 empresas. Hay dos formas de entregarla:

- **Single-tenant:** una instalación independiente por cliente (su servidor, su base de datos, su despliegue). Hay 500 cosas que actualizar, monitorizar y copiar a seguro.
- **Multi-tenant:** una sola aplicación atiende a las 500 empresas a la vez y separa sus datos por dentro. Un fallo se corrige una vez y queda corregido para todos.

> Es el alojamiento compartido (*shared hosting*): muchos sitios web en un mismo servidor, cada uno con su carpeta y sus permisos. El servidor, el sistema operativo y el mantenimiento se comparten; el contenido no. Y como en el alojamiento compartido, todo depende de que los permisos estén bien puestos: si uno falla, un sitio ve los ficheros de otro.

Compartir infraestructura es la ventaja y el riesgo a la vez. Con una instalación por cliente, la separación la da el propio despliegue: no hay forma de leer datos ajenos porque están en otra máquina. Con una instalación compartida, la separación es **código**, y un descuido en una consulta basta para romperla (ver más abajo).

## ¿Cuándo y para qué se usa?

En cualquier producto **SaaS** (*Software as a Service*) cuyos clientes son organizaciones: un CRM, un programa de facturación, una herramienta de gestión de proyectos, una plataforma de pedidos. Alguien da de alta su empresa, invita a sus compañeros y a partir de ahí todos ven únicamente los datos de su organización.

A lo largo de la colección se usa un ejemplo común: una aplicación de gestión de pedidos en `miapp.ejemplo.com` con dos clientes, `acme` (Acme S.L., en `acme.miapp.ejemplo.com`) y `globex` (Globex S.A., en `globex.miapp.ejemplo.com`), y un panel de administración de la plataforma en `admin.miapp.ejemplo.com`. El pedido (`Order`) de Acme no debe ser visible jamás para Globex.

## Vocabulario básico

| Término | Significado |
|---|---|
| **Tenant** | El cliente de la aplicación: una empresa u organización. Es la unidad de aislamiento. |
| **Tenant ID** | El identificador del tenant (un `Guid`, un número o un texto como `acme`). Es lo que marca a quién pertenece cada dato. |
| **Tenant resolution** | Averiguar, en cada petición, a qué tenant pertenece (por el subdominio, una cabecera, un claim del token...). |
| **Aislamiento** | Garantizar que un tenant no puede leer ni modificar datos de otro. Puede lograrse a distintos niveles: base de datos, esquema o fila. |

## Multi-tenant frente a single-tenant

No es una decisión de «lo moderno frente a lo antiguo»: cada modelo gana en cosas distintas.

| Criterio | Single-tenant (una instalación por cliente) | Multi-tenant (una instalación compartida) |
|---|---|---|
| Coste por cliente | Alto: infraestructura propia para cada uno, aunque la use poco | Bajo: los recursos se reparten y se aprovechan mejor |
| Operación | Cada instalación hay que monitorizarla, respaldarla y vigilarla | Una sola instalación (más grande y más crítica) |
| Actualizaciones | Hay que desplegar en cada instalación; las versiones tienden a divergir | Un único despliegue para todos |
| Personalización por cliente | Fácil: cada cliente puede tener su propia versión | Limitada a lo configurable; código distinto por cliente rompe el modelo |
| Aislamiento | Fuerte por construcción (máquinas o bases de datos separadas) | Depende del diseño y del código; hay que demostrarlo con pruebas |
| Cumplimiento normativo | Fácil de justificar cuando un cliente exige infraestructura dedicada | Puede no ser aceptable si el contrato o la norma exigen separación física |
| Tiempo de alta | Lento: hay que crear el entorno | Rápido: crear una fila `Tenant` y, según el modelo, poco más |

La mayoría de los SaaS acaba siendo multi-tenant porque la mayoría de sus clientes son pequeños y parecidos entre sí: el coste de operar una instalación por cliente supera pronto lo que ese cliente paga. Suele quedar, además, una minoría de clientes grandes o regulados a los que se les ofrece un despliegue dedicado como producto aparte; no hace falta elegir un único modelo para todos.

## El peligro: una fuga entre tenants

El fallo típico no es sofisticado. Un endpoint busca un pedido por su identificador y devuelve lo que encuentra, sin preguntar de quién es. Es el clásico **IDOR** (*Insecure Direct Object Reference*: acceder a un objeto con solo conocer o adivinar su id) aplicado entre tenants.

Aplicación mínima con ASP.NET Core y EF Core sobre SQLite, con dos pedidos: el `1` de `acme` y el `2` de `globex`. El tenant se toma del subdominio de la petición:

```csharp
// Los dos pedidos de partida
db.Orders.AddRange(
    new Order { TenantId = "acme",   Total = 120.50m },   // Id = 1
    new Order { TenantId = "globex", Total = 9800m });    // Id = 2

static string TenantOf(HttpContext ctx) => ctx.Request.Host.Host.Split('.')[0];

// ❌ Busca por id y no comprueba el tenant
app.MapGet("/unsafe/orders/{id:int}", async (int id, AppDb db) =>
    await db.Orders.FindAsync(id) is { } o ? Results.Ok(o) : Results.NotFound());

// ✅ El tenant forma parte de la consulta
app.MapGet("/orders/{id:int}", async (int id, HttpContext ctx, AppDb db) =>
{
    var tenant = TenantOf(ctx);
    var order = await db.Orders.SingleOrDefaultAsync(o => o.Id == id && o.TenantId == tenant);
    return order is null ? Results.NotFound() : Results.Ok(order);
});

class Order { public int Id { get; set; } public string TenantId { get; set; } = ""; public decimal Total { get; set; } }
class AppDb(DbContextOptions<AppDb> o) : DbContext(o) { public DbSet<Order> Orders => Set<Order>(); }
```

Una persona de Acme pide el pedido `2` al endpoint sin filtro (en local, `curl` indica el subdominio con la cabecera `Host`):

```bash
curl -i -H "Host: acme.miapp.ejemplo.com" http://localhost:6481/unsafe/orders/2
```

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

{"id":2,"tenantId":"globex","total":9800.0}
```

Acme ha leído un pedido de Globex. No ha hecho falta ningún ataque: el endpoint obedece a quien pregunta. Con el filtro, la misma petición:

```bash
curl -i -H "Host: acme.miapp.ejemplo.com" http://localhost:6481/orders/2
```

```http
HTTP/1.1 404 Not Found
Content-Length: 0
```

Para Acme, ese pedido no existe, y la respuesta no distingue «no existe» de «es de otro»: un `403` confirmaría que el id está en uso. Sus propios pedidos siguen funcionando (`/orders/1` devuelve `200` con `{"id":1,"tenantId":"acme","total":120.5}`), y `globex` sí obtiene el pedido `2`.

Las salidas provienen de una ejecución con .NET 10 y `Microsoft.EntityFrameworkCore.Sqlite` 10.0.0. Conviene guardar este contraste como prueba automatizada con dos tenants: con uno solo, el endpoint sin filtro parece correcto.

## Una vista de conjunto

Construir una aplicación multi-tenant consiste en responder a tres preguntas, cada una con su ficha:

| Pregunta | Qué se decide | Ficha |
|---|---|---|
| ¿Dónde viven los datos de cada tenant? | Una base de datos por tenant, un esquema por tenant o una base compartida con columna `TenantId` | [Estrategias de Aislamiento](Estrategias-de-Aislamiento.md) |
| ¿De quién es esta petición? | Cómo se averigua el tenant y dónde se guarda mientras dura la petición | [Identificación del Tenant](Identificacion-del-Tenant.md) y [Tenant Context](Tenant-Context.md) |
| ¿Cómo se garantiza que nadie vea lo de otro? | Filtrado automático por fila en la aplicación y en el motor | [Aislamiento por Fila](Aislamiento-por-Fila.md) |

Dos asuntos más aparecen al operar el producto: dar de alta tenants y migrar el esquema para todos ([Aprovisionamiento y Migraciones](Aprovisionamiento-y-Migraciones.md)), y la convivencia entre tenants —vecino ruidoso, configuración propia, cachés— ([Retos Avanzados](Retos-Avanzados.md)).

El recorrido de una petición, de forma esquemática:

```text
GET https://acme.miapp.ejemplo.com/orders/1
        │
        ▼
 1. Resolver el tenant        subdominio "acme" → tenant Acme S.L.
        │
        ▼
 2. Guardar el contexto       el tenant actual queda disponible para toda la petición
        │
        ▼
 3. Consulta filtrada         SELECT ... FROM Orders WHERE Id = 1 AND TenantId = 'acme'
        │
        ▼
 Respuesta solo con datos de Acme
```

Cada etapa tiene su ficha. Aquí basta con la idea: el tenant se decide **antes** de tocar los datos y acompaña a la petición hasta la consulta.

## Tenant, usuario y organización

Un usuario es una persona con credenciales; un tenant es la organización a la que pertenece. Muchas personas de Acme forman un único tenant. Azure Architecture Center lo expresa igual: los tenants son distintos de los usuarios y varios usuarios de una misma organización forman un único tenant.

La relación se complica cuando una persona pertenece a más de un tenant: un consultor que trabaja para Acme y para Globex con el mismo email. Si el usuario se modela con un único `TenantId`, ese caso no cabe. Lo habitual es una tabla de pertenencia (usuario, tenant y rol dentro de ese tenant) y tratar la identidad como global y el acceso como por tenant:

```text
User (consultor@ejemplo.com)
 ├── Membership → Tenant acme    (rol: Admin)
 └── Membership → Tenant globex  (rol: Lector)
```

Implica dos cosas: al iniciar sesión (o al cambiar de organización) hay que saber **en qué tenant** actúa la persona en ese momento, y los permisos son los de esa pertenencia, no los de la persona en abstracto. Cómo se refleja en el token y en la sesión se trata en [JWT](../../seguridad/autenticacion-y-autorizacion/JWT.md) y [RBAC y Claims](../../seguridad/autenticacion-y-autorizacion/RBAC-y-Claims.md).

Algunos productos usan «cuenta» u «organización» donde aquí se dice *tenant*; es el mismo concepto con otro nombre de cara al público. En la documentación de Azure aparece además otro uso: los *Microsoft Entra tenants* son directorios de identidad, un concepto distinto que la propia documentación nombra con el término completo para evitar la confusión.

## El tenant como concepto de negocio

El tenant no es solo una columna que filtra: es una entidad de negocio con ciclo de vida propio. Cuánto paga, si puede entrar y qué límites tiene se cuelgan de él.

```csharp
public class Tenant
{
    public Guid Id { get; set; }
    public string Name { get; set; } = "";        // "Acme S.L."
    public string Subdomain { get; set; } = "";   // "acme" → acme.miapp.ejemplo.com
    public bool IsActive { get; set; }            // false = suspendido
}
```

Con ella, la aplicación rechaza a un tenant suspendido antes de ejecutar nada:

```csharp
var tenant = await db.Tenants.SingleOrDefaultAsync(t => t.Subdomain == subdomain);

if (tenant is null)      return Results.NotFound();        // el subdominio no existe
if (!tenant.IsActive)    return Results.StatusCode(403);   // impago o baja: cuenta suspendida
```

Un tenant desconocido da `404` y uno suspendido, `403`: son situaciones distintas y a veces conviene que lo sean para el cliente. Sobre esta base se añaden cuando hacen falta el plan contratado (`Plan`: gratuito, profesional...), límites (usuarios, almacenamiento, peticiones por minuto) y ajustes propios. La convivencia entre tenants se aborda en [Retos Avanzados](Retos-Avanzados.md).

## Cuándo no conviene multi-tenancy

- **Cada cliente exige su propia infraestructura aislada**, por contrato o por normativa (sector sanitario, financiero, administración pública, residencia de datos en una región concreta). Compartir tablas con un filtro puede no ser aceptable por muy bien hecho que esté. Cabe una base de datos dedicada por tenant dentro del mismo producto, o directamente un despliegue aparte.
- **Cada cliente necesita código distinto.** Si cada alta implica una rama o una excepción en el código, se pierde la ventaja principal (un único despliegue para todos) y se conservan los riesgos.
- **Hay un único cliente grande.** Sin varios tenants, la separación no aporta nada y añade complejidad. Aun así, merece la pena que el modelo prevea el `TenantId` si hay una posibilidad real de un segundo cliente.

## Errores frecuentes

| Síntoma | Causa habitual |
|---|---|
| Una persona ve en un listado una fila de otra empresa | Una sola consulta sin filtro de tenant: cualquier `Where`, `SqlQueryRaw` o informe escrito a mano que se salta el mecanismo común |
| Cambiando el id en la URL se leen o se editan datos ajenos | El endpoint busca por id (`FindAsync`, `Single(o => o.Id == id)`) sin comprobar el tenant |
| Un tenant accede a datos de otro cambiando un parámetro (`?tenantId=...`) | El tenant se toma de un dato que el cliente controla (query, cuerpo, cabecera sin verificar) en lugar del resuelto y validado en el servidor |
| Un proceso nocturno mezcla datos o falla con «tenant no resuelto» | Una tarea en segundo plano se ejecuta sin petición HTTP y por tanto sin tenant: nadie le dijo para quién trabaja |
| Una persona ve datos recién guardados por otra empresa | Una caché con claves sin el tenant (`order:1` en lugar de `acme:order:1`) |
| Los logs de un tenant contienen datos de otros, o un equipo de soporte los ve todos | Logs sin etiqueta de tenant ni control de acceso por tenant |

## Buenas prácticas avanzadas

- **Modela el tenant desde el primer día, aunque solo haya un cliente.** Convertir en multi-tenant una aplicación que nació sin ello implica tocar cada tabla, cada consulta y cada caché. Con un solo tenant, incluir `TenantId` casi no cuesta y evita la reescritura.
- **El aislamiento va mucho más allá de la base de datos.** Ficheros subidos, colas de mensajes, índices de búsqueda, correo saliente, cachés y logs contienen datos de tenants. Para cada almacén conviene preguntarse qué impide en él que un tenant vea lo de otro: las fugas reales suelen aparecer por estos canales secundarios.
- **Nunca autorices con un `TenantId` que envía el cliente.** El tenant válido es el que el servidor resuelve (subdominio contrastado, token firmado); cualquier identificador de tenant que llegue en el cuerpo o la query se compara con él, jamás se usa directamente.
- **Prueba siempre con dos tenants como mínimo.** Una suite con un único tenant no detecta fugas, porque todo lo que devuelve es «correcto» por definición. En los tests de integración se crean datos de Acme y de Globex y se comprueba que acceder por id a un recurso ajeno responde `404`.
- **Decide pronto la relación entre usuario y tenant.** Un `TenantId` único en el usuario es el error de diseño más común: tarde o temprano alguien necesitará pertenecer a varias organizaciones con el mismo email. Cambiarlo después arrastra la autenticación entera.
- **Devuelve `404`, no `403`, para recursos de otro tenant.** Un `403` confirma que el recurso existe y permite enumerar ids ajenos.

## Documentación oficial

- [Architect multitenant solutions on Azure (Azure Architecture Center)](https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/overview): la introducción de la serie. Define qué es una solución multitenant y distingue tenants de usuarios; remite a las consideraciones de arquitectura, a los enfoques por tipo de recurso y a la guía específica por servicio de Azure. Merece la pena al empezar a diseñar, o al elegir cómo aislar un recurso concreto (cómputo, almacenamiento, datos, mensajería, identidad).

## Recursos didácticos

- [Entity Framework Core](../../bases-de-datos/acceso-a-datos-dotnet/Entity-Framework-Core.md): base para entender las consultas del ejemplo, antes de ver los *query filters* en [Aislamiento por Fila](Aislamiento-por-Fila.md).
- [APIs por Audiencia](../tipos-de-apis/APIs-por-Audiencia.md): el panel de administración de la plataforma y las APIs de los tenants tienen audiencias distintas.

---

*En resumen: multi-tenancy es servir a muchas organizaciones desde una sola aplicación, y su seguridad depende de que cada consulta sepa de qué tenant es.*
