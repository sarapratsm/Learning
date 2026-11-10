# Duplicar la base de datos

## ¿Qué es?

Duplicar una base de datos de Odoo es crear una segunda base, con otro nombre, que contiene los mismos datos que la original en el momento de la copia. Una instalación de Odoo guarda su estado en dos sitios: las **tablas de PostgreSQL** y el **filestore**, una carpeta en disco con los ficheros adjuntos (facturas en PDF, imágenes de producto, documentos subidos). Un duplicado completo copia las dos piezas.

Referencias: rama `20.0` de `github.com/odoo/odoo` (leída el 2026-11-10) y documentación 20.0 de Odoo y vigente de PostgreSQL. La [página de versiones soportadas](https://www.odoo.com/documentation/20.0/administration/standard_extended_support.html) lista la 20.0, la 19.0 y la 18.0 con soporte estándar. No se ejecutó ninguna instancia de Odoo ni ninguna base de datos: lo que sigue procede de ficheros y páginas leídos, citados en cada punto, y los comandos se presentan como no ejecutados.

Ejemplo conductor: la empresa «Cafés del Valle» tiene la base `cafes_prod` en producción y quiere `cafes_staging` en el servidor de pruebas `staging.ejemplo.com` (nombres inventados).

## ¿Por qué existe?

Muchos fallos solo aparecen con los datos y la configuración reales: miles de pedidos como el S00042, un cliente con reglas de precio propias, un módulo instalado hace años. Una copia permite ensayar una actualización de módulo o reproducir un error sin tocar la base que usa la empresa cada día.

> Es el simulador de vuelo: primero una réplica fiel del avión (duplicar) y después cortarle la conexión con el mundo real (neutralizar). Una réplica sin lo segundo conserva todo lo que la une al exterior.

Una copia recién hecha hereda las credenciales de correo, las pasarelas de pago y las tareas programadas de producción. Por eso duplicar es la mitad del trabajo; la otra mitad es [neutralizar la copia](Neutralizar-Base-de-Datos.md), y el contexto de los entornos está en [Entornos dev, staging y producción](Entornos-dev-staging-produccion.md).

## ¿Cuándo y para qué se usa?

- Ensayar la instalación o actualización de un módulo con datos reales.
- Ensayar una migración a otra versión mayor.
- Reproducir un error que solo ocurre con los datos de producción.
- Formar o hacer demos con información realista.
- Probar una restauración: una copia de seguridad que no se ha restaurado nunca no se sabe si funciona ([Backups y restauración](Backups-y-Restauracion.md)).

## Las formas de duplicar

| Forma | Copia base | Copia filestore | Cuándo |
|---|---|---|---|
| Gestor de bases de datos → *Duplicate* | Sí | Sí | Servidor propio con el gestor habilitado |
| `createdb -T` / `CREATE DATABASE ... TEMPLATE` | Sí | No | Copia rápida en el mismo servidor PostgreSQL; el filestore se copia aparte |
| `pg_dump` + `pg_restore` | Sí | No | Entre servidores o cuando hay conexiones activas que no se pueden cortar |
| Backup ZIP del gestor + *Restore* | Sí | Sí | Entre servidores, con el backup en un fichero |
| Odoo.sh (rama *staging*) | Sí | Sí | Plataforma gestionada |

### Gestor de bases de datos

El gestor está en `/web/database/manager`. El botón de duplicar envía un `POST` a `/web/database/duplicate` con la contraseña maestra, el nombre de origen, el nombre nuevo y la casilla de neutralizar (`addons/web/controllers/database.py`, rama 20.0). El controlador valida el nombre, comprueba la contraseña maestra y llama a `odoo.modules.db.duplicate`.

Esa función (`odoo/modules/db.py`, rama 20.0; en las ramas 18.0 y 19.0 vive como `exp_duplicate_database` en `odoo/service/db.py`, con los mismos pasos: `CREATE DATABASE ... TEMPLATE`, neutralización opcional, `init(force=True)` y `copytree`) hace, por este orden:

1. Cierra las conexiones propias a la base de origen y **termina las demás conexiones** a ella con `pg_terminate_backend` (`_drop_conn`).
2. Ejecuta `CREATE DATABASE <nueva> ENCODING 'unicode' TEMPLATE <origen>`.
3. Si se pidió neutralizar, ejecuta `neutralize_database` sobre la copia **antes** de cargar su registro, «before it becomes visible to the cron workers» (comentario literal del código).
4. Abre la copia y ejecuta `env['ir.config_parameter'].init(force=True)`: regenera el UUID de la base (comentario: «force generation of a new dbuuid»).
5. Copia el filestore con `shutil.copytree`, solo si existe la carpeta de origen y **no** existe la de destino.

La consecuencia práctica del paso 1 es que duplicar desde el gestor **expulsa a quien esté trabajando en la base de origen**. En producción, eso significa cortar la sesión de todo el equipo.

### `CREATE DATABASE ... TEMPLATE` con `createdb -T`

PostgreSQL permite copiar cualquier base nombrándola como plantilla. Comando de ejemplo, no ejecutado:

```bash
createdb -T cafes_prod cafes_staging
```

La documentación de PostgreSQL ([plantillas](https://www.postgresql.org/docs/current/manage-ag-templatedbs.html)) advierte de que esto no es una facilidad general de «copiar base de datos»: «no other sessions can be connected to the source database while it is being copied. CREATE DATABASE will fail if any other connection exists when it starts». Con Odoo corriendo contra `cafes_prod`, el comando falla. El gestor de Odoo lo resuelve terminando las conexiones; por línea de comandos hay que parar Odoo o aceptar el fallo. Además, `createdb -T` copia solo la base: el filestore se copia aparte (siguiente sección).

### `pg_dump` + `pg_restore`

No requiere parar a nadie, porque `pg_dump` lee con una instantánea consistente ([documentación de `pg_dump`](https://www.postgresql.org/docs/current/app-pgdump.html)). Comandos de ejemplo, no ejecutados:

```bash
pg_dump -Fc -f cafes_prod.dump cafes_prod
createdb cafes_staging
pg_restore -d cafes_staging cafes_prod.dump
```

`-Fc` produce el formato personalizado que lee `pg_restore`. El resultado es solo la base; faltan el filestore y el cambio de UUID (secciones siguientes). Otra diferencia: el *Restore* del gestor de Odoo no usa `pg_restore`; extrae del ZIP `dump.sql` y la carpeta `filestore/` y ejecuta `dump.sql` con `psql` (`odoo/modules/db.py`, función `restore`, rama 20.0).

### Odoo.sh

En la plataforma gestionada, una rama *staging* «crea duplicados neutralizados de la base de datos de producción» ([documentación de ramas de Odoo.sh](https://www.odoo.com/documentation/20.0/administration/odoo_sh/getting_started/branches.html)); la propia documentación enumera lo que se neutraliza (acciones programadas, correos salientes, servicios IAP, proveedores de pago y conectores de envío). El detalle por módulo en Odoo Community está en [Neutralizar la base de datos](Neutralizar-Base-de-Datos.md). Odoo.sh es un producto de pago de Odoo; el resto de la ficha sirve para instalaciones propias.

## Qué copia el duplicado: base y filestore

El filestore vive en `<data_dir>/filestore/<nombre_de_la_base>`. Lo establece `config.filestore(dbname)` (`odoo/tools/config.py`, rama 20.0): `os.path.join(self['data_dir'], 'filestore', dbname)`. El adjunto de la base lo resuelve `ir.attachment._filestore()` con el nombre de la base conectada.

Por eso la **ruta lleva el nombre de la base**. Si se copia solo la base con `createdb -T` o `pg_restore`, `cafes_staging` tendrá filas de `ir.attachment` que apuntan a ficheros que no existen en `<data_dir>/filestore/cafes_staging`. La base arranca, pero los adjuntos, las imágenes de producto y los informes guardados dan error o aparecen vacíos. (La estructura interna de subcarpetas del filestore no se verificó en esta lectura.)

Copia manual del filestore, no ejecutada, tras crear la base por línea de comandos:

```bash
cp -a /var/lib/odoo/filestore/cafes_prod /var/lib/odoo/filestore/cafes_staging
```

La ruta de ejemplo es la habitual de un servidor Linux; la real depende de `data_dir`.

> No enlaces ni compartas la carpeta del filestore entre dos bases. La función `_gc_file_store` (`odoo/addons/base/models/ir_attachment.py`) es un `@api.autovacuum` que borra ficheros del filestore sin fila de adjunto en la base que la ejecuta. Si dos bases comparten carpeta, la limpieza de una puede borrar ficheros que la otra necesita. Con un enlace a la carpeta de producción, la copia puede dañar producción.

## Identidad de la copia: UUID y parámetros

Odoo guarda en `ir.config_parameter` unos valores de arranque. El diccionario `_default_parameters` (`odoo/addons/base/models/ir_config_parameter.py`, rama 20.0) contiene `database.secret`, `database.uuid`, `database.create_date`, `web.base.url` (por defecto `http://localhost:<http_port>`) y dos parámetros de enfriamiento de inicio de sesión. `init(force=True)` los **reescribe todos**.

Efectos que se desprenden del código:

- Duplicar desde el gestor, o restaurar con la casilla de copia (`copy=True` en `restore`), regenera `database.uuid` y también `database.secret` y `web.base.url`. La copia **no** conserva el dominio de producción en `web.base.url`: queda en `http://localhost:<puerto>`.
- Restaurar sin marcar «copia» o hacer `pg_restore`/`createdb -T` a mano **no** ejecuta `init(force=True)`: la copia comparte UUID y `web.base.url` con producción. Para el comportamiento de licencias y avisos que dependa del UUID en Enterprise no hay fuente leída: no verificado.
- `web.base.url` condiciona los enlaces de los correos y portales. Tras la copia hay que fijarlo al dominio de pruebas (por ejemplo `https://staging.ejemplo.com`) en *Ajustes técnicos ▸ Parámetros del sistema* (con el [modo desarrollador](../fundamentos/Modo-Desarrollador.md) activo).

### La opción «¿Es una copia?» y el flag de neutralización

El controlador de restauración (`/web/database/restore`) acepta el parámetro `copy`; el texto exacto que muestra el formulario del gestor no se leyó. En el código, el parámetro `copy` de `restore` hace exactamente una cosa: si es verdadero, regenera UUID y demás con `init(force=True)`. Si se **mueve** la base (la original ya no se usa), conviene conservar la identidad; si se **copia** (conviven las dos), hay que regenerarla. Duplicar desde el gestor equivale siempre a una copia.

La neutralización guarda en `ir.config_parameter` la clave `database.is_neutralized` con valor `True` (`odoo/addons/base/data/neutralize.sql`, rama 20.0). Qué ofrece la interfaz con ese flag (por ejemplo, un aviso visible) no se pudo localizar en el código leído: no verificado. Lo que sí es verificable es que la casilla `neutralize_database` del gestor ejecuta la neutralización sobre la copia antes de que los *workers* de cron la vean.

## Riesgos: la copia que se comporta como producción

Una copia no neutralizada conserva las filas de `ir_mail_server` con su usuario y contraseña, las tareas de `ir_cron` activas y la configuración de proveedores de pago. Si Odoo arranca contra ella con acceso a Internet, puede enviar correos a clientes reales, ejecutar procesos programados y contactar con servicios externos. Por eso el orden seguro es duplicar, neutralizar y solo entonces arrancar para uso normal. La casilla del gestor y el comando `odoo-bin neutralize` se describen en [Neutralizar la base de datos](Neutralizar-Base-de-Datos.md); [Pruebas seguras en producción](Pruebas-Seguras-en-Produccion.md) trata las alternativas cuando no existe copia.

| Situación | Riesgo | Medida |
|---|---|---|
| Copia por `pg_restore` arrancada tal cual | Correos y cobros reales | Neutralizar antes del primer arranque |
| Misma `database.uuid` en dos bases | Identidad duplicada | Regenerar (gestor o casilla de copia) |
| Filestore compartido | Borrado cruzado por `_gc_file_store` | Carpeta propia por base |
| `web.base.url` de producción | Enlaces de la copia llevan a producción | Fijarlo al dominio de pruebas |

## Tamaños y tiempos

Razonamiento, sin medición:

- La copia con `CREATE DATABASE ... TEMPLATE` copia ficheros de la base a nivel de bloques, sin pasar por SQL; suele ser más rápida que volcar y restaurar. El volcado/restauración reconstruye índices y vuelve a insertar filas.
- El filestore suele pesar más que la base en instalaciones con muchos adjuntos, y `shutil.copytree` lo copia entero, sin compresión.
- El tiempo crece con el volumen de datos y adjuntos, no con el número de módulos. Hay que medirlo una vez con los datos propios para conocer la ventana necesaria.
- El espacio necesario es, como mínimo, el de la base y el filestore de origen otra vez.

La documentación de Odoo avisa de que el gestor «is not designed to handle large databases, and may trigger memory limits» ([despliegue, seguridad del gestor](https://www.odoo.com/documentation/20.0/administration/on_premise/deploy.html)): en bases grandes se prefieren `pg_dump` y copia de ficheros desde el sistema.

## Contraseña maestra y gestor en producción

Todas las operaciones del gestor exigen la **contraseña maestra** `admin_passwd`, que solo se configura en el fichero de configuración (`FileOnlyOption` en `odoo/tools/config.py`) y se guarda con hash. El controlador la comprueba con `verify_access` en cada llamada. Detalles verificados en el código de la rama 20.0:

- Si `admin_passwd` conserva el valor por defecto `admin`, el primer uso del gestor con otra contraseña **la establece como contraseña maestra y la guarda en el fichero** (`verify_access`).
- Con `list_db = False` (opción `--no-database-list`), `verify_db_management_enabled` devuelve el error «Database management functions blocked, admin disabled database listing.» y el gestor y el selector quedan inaccesibles.

La documentación oficial recomienda desactivar el gestor «for any internet-facing system» porque es «a development/demo tool» y en producción las operaciones sobre bases las hace quien administra el sistema. En producción: `list_db = False`, `admin_passwd` aleatoria y duplicar por línea de comandos desde el servidor o, en la plataforma, con sus herramientas.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `CREATE DATABASE` falla por haber otras conexiones a la base de origen | PostgreSQL exige que no haya otras sesiones en la plantilla (documentación de PostgreSQL). Parar Odoo y las conexiones externas, o usar el gestor, que las termina |
| Adjuntos, logos o imágenes rotos en la copia | Falta la carpeta `<data_dir>/filestore/<base_copia>`: la ruta lleva el nombre de la base |
| «Database management functions blocked, admin disabled database listing.» | `list_db = False` en la configuración |
| «Database management function blocked, bad admin password.» | La contraseña maestra no coincide con `admin_passwd` (literal de `verify_admin_password`) |
| `Database 'cafes_staging' already exists!` o `already exists` | Existe una base con ese nombre; el código no sobrescribe, hay que borrar o elegir otro nombre (literales de `_create_empty_database` y `restore`) |
| Enlaces de correo o del portal de la copia llevan a otro dominio | `web.base.url` sin fijar al dominio de pruebas |
| La copia envía correos reales | Se arrancó sin neutralizar |
| Un usuario de producción se queda sin sesión al duplicar | El gestor termina las conexiones de la base de origen |

## Buenas prácticas avanzadas

- Duplicar con el gestor en producción interrumpe a todo el mundo. Para hacerlo en horario de trabajo, usa `pg_dump` (instantánea consistente sin cortar conexiones) y restaura en el servidor de pruebas.
- Pon nombre distinto de base **y** de carpeta de filestore, y comprueba que existe antes del primer arranque; una base copiada sin su filestore no avisa al abrir, falla al usar el primer adjunto.
- Neutraliza antes de que ningún proceso de Odoo con *crons* active la copia. La casilla del gestor lo hace en el orden correcto, antes de cargar el registro; si restauras a mano, ejecuta la neutralización antes de arrancar el servicio.
- Tras duplicar, revisa `web.base.url` y la configuración de correo, y comprueba en el registro del servidor que no hay envíos.
- Registra la fecha de la copia: los datos de producción posteriores no aparecen y la copia envejece. Rehacerla es más barato que depurar diferencias de datos.
- Protege la copia como a producción: contiene los datos personales reales de clientes y empleados, y neutralizar no los anonimiza (la neutralización leída desactiva efectos externos, no borra datos).

## Documentación oficial

- [Despliegue en servidor propio](https://www.odoo.com/documentation/20.0/administration/on_premise/deploy.html): la contraseña maestra, `list_db` y por qué desactivar el gestor de bases de datos en producción.
- [Ramas de Odoo.sh](https://www.odoo.com/documentation/20.0/administration/odoo_sh/getting_started/branches.html): qué neutraliza una rama de staging.
- [PostgreSQL: bases de datos plantilla](https://www.postgresql.org/docs/current/manage-ag-templatedbs.html): la limitación de conexiones activas de `CREATE DATABASE ... TEMPLATE`.
- [PostgreSQL: `pg_dump`](https://www.postgresql.org/docs/current/app-pgdump.html): formatos de volcado y consistencia de la instantánea.

---

*En resumen: duplicar una base de Odoo es copiar tablas y filestore con un nombre nuevo, regenerar su identidad y neutralizarla antes del primer arranque; el gestor lo hace en ese orden, pero expulsa a los usuarios de la base de origen, y las copias manuales con `createdb -T` o `pg_restore` olvidan el filestore y el UUID.*
