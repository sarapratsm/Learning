# Aprovisionamiento y Migraciones

## ¿Qué es?

El **aprovisionamiento** (*provisioning*) es todo lo que ocurre cuando nace un tenant nuevo: registrarlo, crear su espacio de datos, sembrar lo mínimo para que funcione y dejarlo listo para usarse. Las **migraciones** son los cambios de estructura de la base de datos (tablas, columnas, índices) que hay que llevar a *todos* los tenants a medida que el producto evoluciona.

## ¿Por qué existe?

En una aplicación de un solo cliente, la base de datos se monta una vez y se migra una vez. En una aplicación multi-tenant esas dos tareas se multiplican por el número de tenants: cada cliente nuevo necesita su rincón preparado, y cada cambio del modelo hay que llevarlo a cientos o miles de tenants sin que ninguno se quede atrás ni se rompa a medias.

> Piensa en una cadena de tiendas. Abrir una tienda nueva (aprovisionar) implica montar estanterías, caja y catálogo inicial, y la tienda no abre hasta que todo está listo. Cuando la central decide cambiar el sistema de cajas (migrar), hay que reformar **todas** las tiendas, no solo una, sin cerrar el negocio y sabiendo que durante unos días habrá tiendas con la caja vieja y otras con la nueva.

Cuanto más aislada es la estrategia (base por tenant), más trabajo de alta y de migración por cliente; cuanto más compartida, más sencillo. Es la otra cara del equilibrio descrito en [Estrategias de Aislamiento](Estrategias-de-Aislamiento.md).

## ¿Cuándo y para qué se usa?

El aprovisionamiento se dispara al dar de alta un cliente: un registro autoservicio, o una persona de la plataforma desde el panel de administración. Las migraciones se aplican en cada despliegue en el que cambie el esquema. Con más de un puñado de tenants, ambos tienen que ser procesos automatizados, repetibles y con estado consultable, no comandos manuales.

## Qué significa «dar de alta» y «migrar» según la estrategia

| Estrategia | Dar de alta un tenant | Migrar el esquema | Qué crece con el número de tenants |
|---|---|---|---|
| Base compartida (columna `TenantId`) | Insertar una fila en `Tenants` y sembrar filas | Una sola migración sobre una sola base | Casi nada |
| Esquema por tenant (PostgreSQL, SQL Server) | Crear el esquema y sus tablas | Una vez por esquema | Número de esquemas a recorrer |
| Base por tenant | Crear una base (o un fichero) y sus tablas | Una vez por base | Bases a recorrer, conexiones, tiempo total |

Las ventajas e inconvenientes de cada estrategia en el resto de aspectos están en [Estrategias de Aislamiento](Estrategias-de-Aislamiento.md).

Los ejemplos ejecutados usan **base por tenant con SQLite** (un fichero `<subdominio>.db` por tenant, más un fichero `catalog.db` con el catálogo de tenants) y EF Core 10 sobre .NET 10. Se ejecutaron el 2026-11-09. Hay dos contextos: `CatalogDbContext` (tabla `Tenants` con `Subdomain` y `Status`, y la tabla `TenantMigrationLog`) y `TenantDbContext` (`Users`, `Orders`), con dos migraciones: `Initial` (versión 1 del esquema) y `AddOrderStatus` (versión 2, añade `Orders.Status`). Los nombres de versión que aparecen en las salidas son los de la tabla `__EFMigrationsHistory` de cada base. El tenant lleva un `Status` (`Provisioning`, `Active`, `Failed`) en lugar de un simple `IsActive`.

## El alta de un tenant, de principio a fin

Un `TenantProvisioner` recibe el nombre y el subdominio y ejecuta cuatro pasos en orden:

1. **Registrar** el tenant en el catálogo con estado `Provisioning`.
2. **Preparar su espacio**: crear la base y aplicar todas las migraciones con `Database.MigrateAsync()`. En base compartida este paso no existe.
3. **Sembrar** los datos iniciales: un usuario administrador y unos pedidos de ejemplo.
4. **Marcar** el tenant como `Active`. Solo entonces la aplicación le deja entrar.

El estado sustituye al booleano `IsActive`, que basta cuando el alta no puede fallar: un alta que puede quedarse a medias necesita tres estados (`Provisioning`, `Active`, `Failed`), y un tenant en `Provisioning` o `Failed` se trata como no disponible, igual que uno con `IsActive` a `false`.

```csharp
public async Task<ProvisionResult> ProvisionAsync(string name, string subdomain)
{
    if (!ValidSubdomain().IsMatch(subdomain)) return new(ProvisionOutcome.Invalid, null);   // ^[a-z0-9-]{3,30}$

    await using var catalog = dbs.Catalog();
    var tenant = await catalog.Tenants.SingleOrDefaultAsync(t => t.Subdomain == subdomain);
    if (tenant is { Status: TenantStatus.Active }) return new(ProvisionOutcome.AlreadyActive, tenant);

    if (tenant is null)
    {
        tenant = new Tenant { Name = name, Subdomain = subdomain, Status = TenantStatus.Provisioning };
        catalog.Tenants.Add(tenant);
    }
    else { tenant.Status = TenantStatus.Provisioning; tenant.LastError = null; }   // reintento
    await catalog.SaveChangesAsync();

    try
    {
        await using var db = dbs.Tenant(subdomain);          // su propio fichero SQLite
        await db.Database.MigrateAsync();                    // crea la base y aplica todas las migraciones
        if (!await db.Users.AnyAsync(u => u.Email == $"admin@{subdomain}.ejemplo.com"))
            db.Users.Add(new AppUser { Email = $"admin@{subdomain}.ejemplo.com", Role = "Administrador" });
        if (!await db.Orders.AnyAsync())
            db.Orders.AddRange(new Order { Number = "EJ-1", Total = 10m }, new Order { Number = "EJ-2", Total = 25m });
        await db.SaveChangesAsync();

        tenant.Status = TenantStatus.Active;
        await catalog.SaveChangesAsync();
        return new(ProvisionOutcome.Created, tenant);
    }
    catch (Exception ex)
    {
        tenant.Status = TenantStatus.Failed;
        tenant.LastError = ex.Message;
        await catalog.SaveChangesAsync();
        return new(ProvisionOutcome.Failed, tenant);
    }
}
```

`dbs.Tenant(subdomain)` construye un `TenantDbContext` con la cadena `Data Source=<subdominio>.db`. Como el subdominio forma parte de un nombre de fichero (en otras estrategias, de un nombre de esquema o de base), se valida con una lista blanca antes de usarlo: con `../evil` el servidor responde `400`.

Un servidor mínimo expone `POST /admin/tenants` (el panel de administración) y `GET /orders`, que resuelve el tenant por el primer segmento del `Host`. El alta de `initech` y la consulta posterior, ejecutadas con `curl`:

```bash
curl -si -X POST localhost:6482/admin/tenants -H 'Content-Type: application/json' \
  -H 'Host: admin.miapp.ejemplo.com' -d '{"name":"Initech","subdomain":"initech"}'
```

```text
HTTP/1.1 201 Created
{"subdomain":"initech","status":"Active"}
```

```bash
curl -si localhost:6482/orders -H 'Host: initech.miapp.ejemplo.com'
```

```text
HTTP/1.1 200 OK
[{"id":1,"number":"EJ-1","total":10.0,"status":"new"},{"id":2,"number":"EJ-2","total":25.0,"status":"new"}]
```

El mismo `POST` repetido responde `409 Conflict` con `{"error":"El tenant 'initech' ya existe"}`: el alta de un tenant activo no se repite ni se pisa.

En el disco, `data1/` pasó a contener `catalog.db` e `initech.db`. En base compartida el paso 2 desaparece y el paso 3 inserta filas con `TenantId = <id del tenant>`; el resto del flujo es idéntico.

## Cuando el alta falla a mitad

El alta toca dos sitios, el catálogo y el espacio del tenant, y no hay transacción que abarque los dos. Si el proceso se interrumpe tras crear la base pero antes de sembrar, el catálogo dice que el tenant existe y su base está a medias: un tenant zombi que no funciona y que, si el alta no sabe reintentarse, tampoco se puede volver a crear.

Tres piezas lo resuelven:

- **Estado explícito.** `Provisioning` mientras se está montando, `Active` cuando termina, `Failed` cuando se rinde con el error guardado en `LastError`. La aplicación solo atiende a tenants `Active`.
- **Idempotencia.** Cada paso se puede repetir sin duplicar nada: `MigrateAsync()` solo aplica lo pendiente, y la semilla comprueba si el administrador o los pedidos ya existen antes de insertar.
- **Reintento o compensación.** Un alta fallida se relanza con la misma llamada, o se descarta del todo.

Se forzó un fallo en el paso de sembrar (`FailAt=seed` en el servidor) para `hooli`:

```text
HTTP/1.1 500 Internal Server Error
{"subdomain":"hooli","status":"Failed","error":"fallo simulado al sembrar"}
```

```text
GET /orders  (Host: hooli.miapp.ejemplo.com)
HTTP/1.1 503 Service Unavailable
{"error":"Tenant en estado Failed"}
```

```json
[{"subdomain":"hooli","status":"Failed","lastError":"fallo simulado al sembrar"},{"subdomain":"initech","status":"Active","lastError":null}]
```

Tras reiniciar el servidor sin el fallo, la **misma petición** de alta dio `201 Created` con `"status":"Active"`, el `GET /orders` devolvió los dos pedidos de ejemplo (sin duplicados) y una tercera repetición dio `409`. La base `hooli.db` ya existía y `MigrateAsync()` no tuvo nada que aplicar.

La **compensación** es el camino contrario: en lugar de reintentar, deshacer. `DELETE /admin/tenants/{sub}/failed` borra el fichero de la base y la fila del catálogo, pero solo si el tenant está en `Failed`:

```text
alta fallida: 500
antes:   catalog.db hooli.db initech.db piedpiper.db piedpiper2.db pipersoft.db
compensar: 204
despues: catalog.db hooli.db initech.db piedpiper.db pipersoft.db
```

La condición `Status == Failed` evita que una llamada equivocada borre un tenant activo.

### Síncrono frente a asíncrono

| | Alta síncrona (dentro de la petición HTTP) | Alta asíncrona (trabajo en segundo plano) |
|---|---|---|
| Quien se registra | Espera con el navegador abierto hasta que termina | Recibe `202 Accepted` y una URL para consultar el estado |
| Crear una base real (PostgreSQL, SQL Server) | Cabe en la petición solo si el motor responde en pocos segundos; el tiempo depende del motor, de su configuración y de la plantilla usada, y conviene medirlo en el entorno propio | No importa cuánto tarde: el trabajo tiene su propio plazo |
| Fallo a mitad | La petición devuelve error y quien se registra decide si reintenta | El trabajo reintenta solo y deja `Failed` con el error si se agota |
| Estado consultable | Poco necesario | Imprescindible: `Provisioning` → `Active`/`Failed` en `GET /tenants/{id}` |
| Complejidad | Mínima | Cola o trabajo en segundo plano, reintentos, idempotencia |

Con SQLite el alta tarda lo que tarda crear un fichero, y la forma síncrona basta. Con una base real y pasos adicionales (DNS, correo de bienvenida, facturación) la forma asíncrona es la habitual. El estado `Provisioning` ya está en el modelo, así que pasar de una a otra no cambia el catálogo: solo cambia quién ejecuta el `ProvisionAsync` y qué recibe quien llamó.

## Migrar todos los tenants

Con base por tenant, el despliegue de una versión que cambia el esquema deja una **flota** de bases con la versión anterior. Un runner recorre el catálogo, abre el contexto de cada tenant activo y aplica `MigrateAsync()`:

```csharp
await Parallel.ForEachAsync(tenants, new ParallelOptions { MaxDegreeOfParallelism = maxParallel }, async (t, ct) =>
{
    var sw = Stopwatch.StartNew();
    string from = "?", to = "?", outcome = "OK"; string? error = null;
    try
    {
        await using var db = dbs.Tenant(t.Subdomain);
        from = (await db.Database.GetAppliedMigrationsAsync(ct)).LastOrDefault() ?? "(vacía)";
        await db.Database.MigrateAsync(ct);
        to = (await db.Database.GetAppliedMigrationsAsync(ct)).LastOrDefault() ?? "(vacía)";
    }
    catch (Exception ex) { outcome = "FALLO"; error = ex.GetBaseException().Message; }

    await using var catalog = dbs.Catalog();   // un contexto por tenant: DbContext no es seguro entre hilos
    catalog.MigrationLog.Add(new TenantMigrationLog { Subdomain = t.Subdomain, FromVersion = from, ToVersion = to,
        Outcome = outcome, Error = error, StartedAt = DateTime.UtcNow, Millis = sw.ElapsedMilliseconds });
    await catalog.SaveChangesAsync(ct);
});
```

La lista de tenants sale del catálogo (solo los `Active`), no de una lista escrita a mano: un tenant nuevo entra en el siguiente recorrido sin tocar el código. Además, un tenant dado de alta después del despliegue ya nace con todas las migraciones, porque el aprovisionamiento ejecuta `MigrateAsync()`.

Con tres tenants (`acme`, `globex` e `initech`, dados de alta con la versión 1) y una modificación a mano en la base de `globex` (alguien ya había añadido a mano la columna `Status`), la salida real fue:

```text
acme       20261101000000_Initial -> 20261108000000_AddOrderStatus  OK
globex     20261101000000_Initial -> ?  FALLO  SQLite Error 1: 'duplicate column name: Status'.
initech    20261101000000_Initial -> 20261108000000_AddOrderStatus  OK
Total 665 ms, 1 fallos
```

Un fallo en un tenant no deshizo el resto. El catálogo quedó con una flota repartida entre dos versiones:

```text
acme       Active       20261108000000_AddOrderStatus
globex     Active       20261101000000_Initial
initech    Active       20261108000000_AddOrderStatus
```

Una segunda pasada dio `OK` para `acme` e `initech` con la misma versión de origen y de destino (nada que aplicar) y volvió a fallar `globex`: el recorrido es repetible, que es lo que permite relanzarlo tras corregir el problema. Que el fallo de `globex` sea una columna ya existente ilustra otro riesgo: una migración que asume el estado de la base en lugar de comprobarlo no se puede reintentar sobre una base tocada a mano.

### Qué pasa con la aplicación mientras la flota está repartida

Con el código de la versión 2 (que lee `Orders.Status`) y la base de `acme` todavía en la versión 1, la petición falla:

```text
GET /orders  (Host: acme.miapp.ejemplo.com)
HTTP/1.1 500 Internal Server Error
(registro del servidor) SQLite Error 1: 'no such column: o.Status'.
```

Mientras dure la migración, y mientras haya tenants fallidos, el código tiene que funcionar con las dos versiones del esquema. El patrón habitual es *expand/contract*: la versión N+1 del código se despliega primero con una migración aditiva (columna con valor por defecto, tolerada por el código viejo), y la limpieza destructiva se deja para una versión posterior, cuando toda la flota está en N+1. Las técnicas para ello (columnas nuevas, renombrados en varios pasos, despliegues sin parada) están en [Estrategias Zero-Downtime](../../bases-de-datos/migraciones-de-esquema/Estrategias-Zero-Downtime.md); los comandos y el funcionamiento de las migraciones de EF Core, en [EF Core Migrations](../../bases-de-datos/migraciones-de-esquema/EF-Core-Migrations.md).

### Continuar o parar cuando un tenant falla

| Decisión | Cuándo conviene | Riesgo |
|---|---|---|
| **Continuar** con los demás y registrar el fallo | La migración es aditiva y el código tolera ambas versiones; cada tenant es independiente | Flota repartida entre versiones hasta resolver los fallidos; hay que alertar y reintentar |
| **Parar** al primer fallo | La migración es destructiva o el código nuevo no tolera el esquema viejo; un fallo indica un defecto general de la migración | Despliegue detenido con una parte de la flota migrada y otra no |
| **Parar tras un umbral** (por ejemplo, un porcentaje de fallos) | Muchos tenants, fallos puntuales esperables | Hay que elegir y revisar el umbral |

Un fallo en el primer tenant de una migración que nunca se ha probado suele indicar un defecto de la propia migración, no del tenant: por eso el consejo de aplicar primero a unos pocos tenants canario y seguir solo si salen bien.

### Registro del resultado por tenant

La tabla `TenantMigrationLog` del catálogo guarda una fila por intento:

```text
1 acme     OK     20261101000000_Initial -> 20261108000000_AddOrderStatus 176 ms
2 globex   FALLO  20261101000000_Initial -> ? 23 ms SQLite Error 1: 'duplicate column name: Status'.
3 initech  OK     20261101000000_Initial -> 20261108000000_AddOrderStatus 57 ms
```

Con ella, «¿por dónde iba?» tras una caída es una consulta, y la lista de tenants pendientes (`Active` sin la última versión) sale directamente de comparar versiones. Qué versión tiene cada tenant sale de `__EFMigrationsHistory` en su propia base; el log es la bitácora de intentos, no sustituye a esa tabla.

### En paralelo, con límite

El recorrido en serie tarda lo que suma cada migración. `Parallel.ForEachAsync` con `MaxDegreeOfParallelism` reparte el trabajo y limita cuántas migraciones corren a la vez. Medición con 200 tenants SQLite creados en la versión 1 y migrados a la 2, con tres ejecuciones por valor sobre copias idénticas de las bases:

| `MaxDegreeOfParallelism` | Tiempo total (3 ejecuciones) |
|---|---|
| 1 | 2274, 2272 y 2394 ms |
| 4 | 1801, 1912 y 1995 ms |
| 16 | 3624, 3310 y 3374 ms |

En esta máquina, con ficheros locales, 4 mejora algo y 16 empeora: SQLite admite una sola escritura a la vez, y los 16 hilos compiten por el fichero del catálogo donde se escribe el log. Con PostgreSQL o SQL Server las bases de los tenants sí son independientes entre sí y el paralelismo rinde más, pero el límite sigue importando porque todas las conexiones llegan al mismo servidor (o al mismo *pool* de recursos): una migración con `ALTER TABLE` sobre tablas grandes ocupa disco, memoria y bloqueos. El valor correcto se determina midiendo contra el servidor real, no copiando un número.

## Migrar al arrancar la aplicación o en un paso aparte

Llamar a `Database.MigrateAsync()` al arrancar es cómodo con una sola base. La documentación de EF Core indica que, desde EF Core 9, `Migrate` y `MigrateAsync` toman un bloqueo de base de datos para que varias instancias de la aplicación no migren a la vez, y que un paso de despliegue separado sigue siendo preferible cuando importan la revisión, las credenciales de privilegios mínimos, el despliegue coordinado o la alta disponibilidad.

Con muchos tenants, hay una razón más: el arranque pasa a costar **N × t**, con N tenants y t el tiempo medio de una migración. La medición anterior dio unos 11-12 ms por tenant en serie con SQLite local (2272 ms entre 200 tenants). Eso extrapolado a 1000 tenants es del orden de 12 s; pero una migración sobre una base real con tablas grandes no tarda milisegundos. Con un tiempo **supuesto** de 30 s por migración (valor ilustrativo, no medido), 500 tenants en serie son 15 000 s, unas 4 h 10 min: durante ese tiempo la aplicación no está lista, el orquestador ve que no responde a las sondas de salud y la reinicia, el reinicio relanza la migración, y todas las instancias nuevas hacen lo mismo. Un fallo en el tenant 300 deja la aplicación sin arrancar por un problema de un solo cliente.

El camino habitual es un **paso aparte**: un trabajo de despliegue (el runner anterior, o un *bundle* de migraciones) que se ejecuta antes o después de la aplicación, con su propio registro y sus reintentos. La documentación de EF Core recomienda para el despliegue automatizado un *migration bundle* o un script SQL en lugar de `dotnet ef database update` en producción. Sobre los modos de aplicar migraciones y sus compromisos, véase [Migraciones de Esquema](../../bases-de-datos/migraciones-de-esquema/Migraciones-de-Esquema.md).

## Migraciones en base compartida y en esquema por tenant

**Base compartida.** La migración es una sola, con el comando de siempre (`dotnet ef database update`, o el *bundle*). No hay flota ni versiones repartidas, pero el riesgo se concentra: una migración defectuosa o que bloquea una tabla grande afecta a **todos los tenants a la vez**, y no hay un tenant canario al que probarla primero. Por eso pesan más las técnicas de [Estrategias Zero-Downtime](../../bases-de-datos/migraciones-de-esquema/Estrategias-Zero-Downtime.md) y probar la migración con una copia de datos del tamaño real.

**Esquema por tenant en PostgreSQL o SQL Server.** El runner es el mismo, pero cada tenant se abre contra su esquema (`tenant_acme`, `tenant_globex`...) en la misma base, y cada tenant necesita su propia tabla de historial de migraciones para llevar su propia versión. En EF Core eso pasa por configurar el esquema por tenant (por ejemplo, con `HasDefaultSchema` y `MigrationsHistoryTable`); esos nombres de API están escritos de memoria y no se han comprobado.

> **No ejecutado en esta máquina.** No hay PostgreSQL ni SQL Server instalados, así que el comando de aplicar migraciones por esquema no se ha ejecutado. Lo anterior se basa en la documentación leída de EF Core y en el modelo de datos de esas bases; antes de adoptarlo, hay que probarlo contra el motor real, incluida la tabla de historial por esquema.

## Baja y eliminación de un tenant

| Opción | Qué hace | Cuándo |
|---|---|---|
| **Desactivar** (suspender) | Cambia el estado; los datos siguen; se puede reactivar | Impago, pausa temporal, periodo de gracia |
| **Exportar y archivar** | Entrega los datos al cliente (o los guarda fuera) antes de borrar | Obligación contractual o legal de portabilidad |
| **Borrar** | Elimina los datos de forma definitiva | Pasado el plazo de retención, o petición de supresión |

Primero se desactiva; el borrado definitivo se hace pasado el plazo de retención que fijen el contrato y la normativa aplicable, y siempre después de una exportación si el cliente tiene derecho a recibirla. Los plazos concretos dependen de cada caso y no se fijan aquí.

El borrado depende de la estrategia. Con base o esquema por tenant es eliminar la base o el esquema (en el ejemplo, borrar el fichero `.db`, como hace la compensación del alta fallida). Con base compartida es un `DELETE` por `TenantId`, y ahí el filtro global que protege las consultas normales ([Aislamiento por Fila](Aislamiento-por-Fila.md)) estorba, porque filtra por el tenant de la petición actual, que en una tarea de administración no es el tenant a borrar. Se ignora a propósito con `IgnoreQueryFilters()`, y por eso es peligroso: se ejecutó con cuatro pedidos de tres tenants (`acme` dos, `globex` uno, `initech` uno):

```csharp
var q = db.Orders.IgnoreQueryFilters();
q = q.Where(o => o.TenantId == "initech");     // ✅ la condición explícita
var n = await q.ExecuteDeleteAsync();
```

```text
con Where: borradas 1 filas; quedan: acme=2, globex=1
sin Where (olvidado): borradas 4 filas; quedan: ninguna
```

Con `IgnoreQueryFilters()` no queda ninguna red: olvidar el `Where` (o calcular mal el identificador, o recibir uno vacío) borra los pedidos de todos los tenants. Por eso el borrado se hace con el identificador validado contra el catálogo, con un recuento previo, dentro de una transacción y con el tenant ya desactivado.

## Copias de seguridad y restauración por tenant

- **Base compartida**: la copia es de toda la base; restaurar un solo tenant exige extraer sus filas de una copia restaurada aparte y reinsertarlas.
- **Esquema por tenant**: se puede copiar y restaurar un esquema suelto, con las herramientas de volcado del motor, sin tocar los demás.
- **Base por tenant**: cada base tiene su copia y se restaura de forma independiente, que es una de las razones para elegirla.

## Cuándo no hace falta nada de esto

Con una base compartida y pocos tenants, el alta es insertar una fila en `Tenants` (más la semilla) y la migración es la de cualquier aplicación de una sola base. El runner, los estados `Provisioning`/`Failed`, el log por tenant y el alta asíncrona aparecen cuando el alta toca recursos externos a la base compartida o cuando hay una base o esquema por tenant.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| La aplicación no arranca tras desplegar, o se reinicia en bucle | `MigrateAsync()` al arrancar sobre cientos de tenants: el arranque dura N × t y las sondas de salud lo matan |
| Un tenant existe en el catálogo pero da error al entrar | Alta fallida a mitad sin estado `Failed` ni reintento: catálogo y base desincronizados |
| El reintento de una migración falla con «ya existe» | Migración no idempotente aplicada sobre una base modificada a mano o a medias |
| Errores `no such column` (o equivalente) solo en algunos tenants | La flota tiene versiones distintas y el código asume la última |
| Un tenant recién dado de alta se queda en la versión antigua | El runner usa una lista fija de tenants en lugar del catálogo, o el alta no aplica las migraciones |
| Desaparecen los datos de varios tenants tras dar de baja uno | `DELETE` con `IgnoreQueryFilters()` sin comprobar el `TenantId` |

## Buenas prácticas avanzadas

- **Alta idempotente y con estado explícito.** Cada paso se puede repetir sin duplicar nada (semillas con comprobación previa, creación de base «si no existe») y el estado `Provisioning`/`Active`/`Failed` decide si el tenant puede entrar. Un alta fallida se reintenta con la misma llamada.
- **Migraciones aditivas primero (*expand/contract*).** Durante una migración conviven código y esquema de versiones distintas. Añade lo nuevo de forma tolerada por el código anterior, despliega, rellena datos y solo al final elimina lo antiguo. Renombrar una columna de golpe funciona en local y rompe en una flota.
- **Canarios antes de la flota.** Aplica la migración a tenants internos o de demostración, luego a un porcentaje pequeño de clientes reales y después al resto. Una migración defectuosa en tres canarios es un susto; en todos a la vez es el peor día de un SaaS.
- **Paralelismo con techo y registro por tenant.** Un grado de paralelismo fijo, ajustado midiendo contra el servidor real, y una fila de log por tenant e intento. Así los reintentos y los informes salen de una consulta.
- **Valida lo que se convierte en nombre de base, esquema o fichero.** El subdominio llega de fuera y acaba en una ruta o en un identificador SQL: una lista blanca de caracteres antes de usarlo.
- **Migración como paso de despliegue, no como efecto del arranque.** Con credenciales distintas a las de la aplicación (las de la aplicación no necesitan permiso para alterar el esquema) y con un resultado que alguien pueda consultar.

## Documentación oficial

- [Applying Migrations (EF Core)](https://learn.microsoft.com/ef/core/managing-schemas/migrations/applying): la comparativa entre aplicar migraciones con *bundle*, script SQL idempotente o desde la aplicación, incluido el bloqueo de EF Core 9 y posteriores. Léela antes de decidir cómo se despliega la migración en producción. Consultada el 2026-11-09.
- [Despliegue y configuración de soluciones multi-tenant (Azure Architecture Center)](https://learn.microsoft.com/azure/architecture/guide/multitenant/approaches/deployment-configuration): qué incluye un proceso de incorporación de tenants (pasos documentados, automatización, impacto sobre otros tenants). Útil al diseñar el alta. Consultada el 2026-11-09.

---

*En resumen: aprovisionar es montar la tienda de cada cliente nuevo con un estado que diga si está lista, y migrar es reformar todas las tiendas a la vez con un registro de cuál va por dónde, sabiendo que durante la obra algunas tendrán la caja vieja y otras la nueva.*
