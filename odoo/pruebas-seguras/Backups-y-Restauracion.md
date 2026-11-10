# Backups y restauración

## ¿Qué es?

Un backup de Odoo es el conjunto de datos necesario para reconstruir una instancia: la **base de datos PostgreSQL**, el **filestore** (la carpeta del servidor donde Odoo guarda los ficheros adjuntos, que no viven en la base) y la **configuración** del servidor (`odoo.conf`). Restaurar es volver a cargar ese conjunto en un servidor y una base de datos nueva.

Fuentes: código de `odoo/service/db.py` y `addons/web/controllers/database.py` en la rama `19.0` de `github.com/odoo/odoo` (leídos el 2026-11-10; en la rama `20.0`, vigente en esa fecha, la ruta `odoo/service/db.py` ya no existe y no se localizó su nuevo sitio: lo descrito se contrastó con `19.0`), documentación de despliegue de Odoo 19.0 y documentación de PostgreSQL 18. No se ejecutó ninguna instancia de Odoo ni ningún comando: los comandos están **sin ejecutar**, tomados de la documentación citada en cada caso.

## ¿Por qué existe?

Una prueba que sale mal, un módulo que corrompe datos o un borrado por error son inevitables a la larga. Sin una copia con historia, los datos de «Cafés del Valle» (clientes, pedidos como el S00042, empleadas como Ana Ruiz) no tienen vuelta atrás. Además, un backup de `cafes_prod` es la materia prima de cualquier entorno de pruebas como `cafes_staging`.

> Es el punto de guardado de un videojuego: sirve solo si el archivo de guardado carga. Un guardado que nunca se ha cargado es una suposición.

## ¿Cuándo y para qué se usa?

- Antes de instalar o actualizar un módulo, o de cualquier cambio grave en producción.
- De forma periódica y automática, sin depender de que alguien se acuerde.
- Para crear un entorno de pruebas (véase [Entornos dev, staging y producción](Entornos-dev-staging-produccion.md) y [Duplicar una base de datos](Duplicar-Base-de-Datos.md)).
- Para migrar a otro servidor.

## Qué hay que respaldar

| Pieza | Dónde vive | Si falta |
|---|---|---|
| Base de datos | PostgreSQL (por ejemplo `cafes_prod`) | No hay datos |
| Filestore | Carpeta de datos de Odoo (`data_dir`), una subcarpeta por base | Los registros existen, pero imágenes, PDFs y adjuntos dan error al abrirse |
| Configuración | `odoo.conf` (claves de base de datos, `admin_passwd`, rutas de `addons_path`) | Hay que reconstruirla a mano |
| Módulos propios y de terceros | Carpetas de `addons_path`, normalmente en Git | La base no carga los módulos instalados |

El código oficial de Odoo no hace falta copiarlo: se reinstala de la versión correspondiente. Lo que sí hay que anotar es **qué versión** de Odoo y de PostgreSQL producía la copia (el ZIP del gestor la incluye, véase más abajo).

La documentación de despliegue de Odoo lo resume así: configurar copias diarias de las bases y del filestore y copiarlas a un servidor remoto de archivo al que el propio servidor no pueda acceder ([despliegue, sección de seguridad](https://www.odoo.com/documentation/19.0/administration/on_premise/deploy.html), leída el 2026-11-10).

## Backup desde el gestor de bases de datos

El gestor de bases (`/web/database/manager`) protege sus operaciones con la **contraseña maestra** (`admin_passwd` en `odoo.conf`). El formulario de *Backup* pide la contraseña maestra, la base y un formato.

El controlador `backup` (`addons/web/controllers/database.py`, rama 19.0) acepta `backup_format='zip'` por defecto y `filestore=True`, comprueba la contraseña con `check_super`, y nombra el fichero `<base>_<fecha-hora UTC>.<formato>`.

### Formato ZIP

Con `zip`, `dump_db` (`odoo/service/db.py`, 19.0) crea un directorio temporal y mete en él:

| Entrada del ZIP | Contenido | Origen en el código |
|---|---|---|
| `dump.sql` | SQL en texto plano generado con `pg_dump --no-owner <base>` | `cmd = [find_pg_tool('pg_dump'), '--no-owner', db_name]` y `--file=.../dump.sql` |
| `filestore/` | Copia de la carpeta de adjuntos de esa base (solo si `with_filestore` y existe) | `shutil.copytree(filestore, .../'filestore')` |
| `manifest.json` | Metadatos del backup | `dump_db_manifest(cr)` |

El manifiesto lo construye `dump_db_manifest` con estas claves, literales del código: `odoo_dump` (`'1'`), `db_name`, `version`, `version_info`, `major_version`, `pg_version` y `modules` (diccionario nombre → versión de cada módulo con `state = 'installed'`). Es lo que permite saber, sin restaurar, de qué versión mayor de Odoo viene la copia.

### Formato `dump` (custom de PostgreSQL)

Con un formato distinto de `zip`, `dump_db` ejecuta `pg_dump --no-owner --format=c <base>` y devuelve la salida tal cual: **sin filestore ni manifiesto**. Es una copia solo de la base.

### Límites del gestor

La documentación de Odoo es tajante: el gestor de bases es una herramienta de desarrollo y demostración, no está diseñada para producción, no maneja bien bases grandes («may trigger memory limits») y debería desactivarse en sistemas expuestos a internet; en producción, las operaciones sobre bases y las copias automáticas las hace la administración del sistema ([despliegue, «Database Manager Security»](https://www.odoo.com/documentation/19.0/administration/on_premise/deploy.html)). En el código, además, `backup` escribe el ZIP completo en un fichero temporal del servidor antes de devolverlo.

Dos opciones de configuración controlan el acceso, según esa misma página:

- `admin_passwd`: contraseña maestra. Debe cambiarse del valor por defecto y ser aleatoria.
- `list_db = False` (o `--no-database-list`): oculta la lista de bases y bloquea las pantallas del gestor. En el código, `list_dbs` lanza `AccessDenied` si `list_db` es falso.

## Backup por línea de comandos con `pg_dump`

PostgreSQL documenta que `pg_dump` «hace exportaciones consistentes aunque la base se esté usando» sin bloquear a lectores ni escritores, y que los formatos *custom* (`-Fc`) y *directory* (`-Fd`) permiten seleccionar elementos al restaurar, admiten restauración en paralelo y están comprimidos por defecto ([`pg_dump`, PostgreSQL 18](https://www.postgresql.org/docs/18/app-pgdump.html)). La misma página advierte de que, salvo casos simples, `pg_dump` no es generalmente la opción para las copias periódicas de producción de grandes volúmenes y remite al capítulo de copias de PostgreSQL.

Comando **no ejecutado** (forma estándar de la documentación de `pg_dump`):

```bash
pg_dump -Fc cafes_prod -f cafes_prod_2026-11-10.dump
```

Y el filestore, aparte, con una copia de carpeta (por ejemplo `tar` o `rsync`) de la subcarpeta de la base dentro del `data_dir`. La ruta exacta depende de la instalación; el código la obtiene con `odoo.tools.config.filestore(db_name)`.

| | ZIP del gestor | `pg_dump -Fc` + copia del filestore |
|---|---|---|
| Filestore incluido | Sí (opcional) | Manual |
| Manifiesto de versión | Sí (`manifest.json`) | No |
| Restaurable desde la interfaz | Sí | Solo la parte de base (véase más abajo) |
| Apto para bases grandes | No recomendado por la documentación | Sí |
| Restauración en paralelo y selectiva | No (SQL plano) | Sí, con `pg_restore -j` |
| Automatizable en cron | Incómodo (HTTP con contraseña maestra) | Sí |

### Consistencia entre base y filestore

`pg_dump` es consistente consigo mismo, pero la base y el filestore se copian en momentos distintos. Si entre ambas copias se crean o borran adjuntos, quedarán referencias a ficheros que no existen (o ficheros huérfanos). Para minimizarlo, copiar el filestore justo después del volcado y restaurar ambos juntos.

## Restaurar

### Desde el gestor («Restore»)

`restore_db` (`odoo/service/db.py`, 19.0) hace, en este orden:

1. **Rechaza** si la base de destino ya existe: lanza «Database already exists». No sobrescribe.
2. Crea una base vacía (`_create_empty_database`).
3. Si el fichero es un ZIP: extrae solo `dump.sql` y las entradas que empiezan por `filestore/`, y carga el SQL con `psql`. Si no es un ZIP, lo trata como volcado binario de `pg_dump` y lo carga con `pg_restore --no-owner` (el código lo comenta como formato «<= 7.0», pero el resultado es que un `-Fc` pasa por esa rama; en ella no hay filestore). Si `psql`/`pg_restore` devuelve error, lanza «Couldn't restore database».
4. Si `neutralize_database` es verdadero, neutraliza la base **antes** de que los crons la vean ([Neutralizar una base de datos](Neutralizar-Base-de-Datos.md)).
5. Carga el registro de Odoo. Si `copy` es verdadero («esta base es una copia»), fuerza un nuevo `database.uuid` con `ir.config_parameter.init(force=True)`. Después mueve el filestore extraído a la carpeta de adjuntos de la base nueva.

El controlador `restore` expone justo esos dos interruptores: `copy` y `neutralize_database`, ambos falsos por defecto.

| Situación | `copy` | Neutralizar |
|---|---|---|
| Recuperar producción tras un desastre (la base original ya no existe) | No (es «movida») | No |
| Crear `cafes_staging` a partir de un backup de `cafes_prod` | Sí | Sí, siempre |
| Restaurar en un servidor de pruebas para verificar el backup | Sí | Sí |

El `database.uuid` identifica la base ante Odoo; una copia que lo conserva puede confundirse con la original en servicios externos. Qué efectos exactos tiene no se contrastó en esta lectura.

### Con `pg_restore`

La documentación de `pg_restore` indica que `--clean` ejecuta `DROP` de los objetos antes de restaurarlos «útil para sobrescribir una base existente», y que `--if-exists` evita los errores de objetos inexistentes (solo válido con `--clean`); `--create` crea la base antes de restaurar ([`pg_restore`, PostgreSQL 18](https://www.postgresql.org/docs/18/app-pgrestore.html)).

Comandos **no ejecutados**, a una base nueva (sin `--clean`, el caso seguro):

```bash
createdb cafes_staging
pg_restore --no-owner -d cafes_staging cafes_prod_2026-11-10.dump
```

`--clean --if-exists` sobre una base existente destruye su contenido: solo cuando esa base es desechable.

Después, el filestore: copiar la carpeta de adjuntos a la subcarpeta con el **nombre de la base nueva** dentro del `data_dir` (el código del gestor lo coloca con `env['ir.attachment']._filestore()`). Y arrancar Odoo con `--database=cafes_staging` y con la neutralización pendiente (véase abajo).

## Copias automáticas

Una copia diaria programada con cron, con retención y envío fuera del servidor, la desarrolla `devops/despliegue-en-vps/Copias-de-Seguridad.md`: [Copias de seguridad en un VPS](../../devops/despliegue-en-vps/Copias-de-Seguridad.md) (regla 3-2-1, `set -euo pipefail`, retención en el proveedor, restauración periódica) y [Tareas programadas con cron](../../devops/despliegue-en-vps/Tareas-Programadas-con-Cron.md). Aplicado a Odoo, el script de esa ficha cambia en tres cosas:

- Se vuelca la base con `pg_dump -Fc` (o el equivalente con `docker exec`, si la base va en contenedor).
- Se añade la copia del filestore de la base, tomada justo después del volcado.
- Se incluye `odoo.conf`, **cifrado**: contiene `admin_passwd` y credenciales de la base.

Regla 3-2-1: tres copias, en dos soportes distintos, una de ellas fuera del sitio. La documentación de Odoo exige que el destino remoto no sea accesible desde el propio servidor, para que un compromiso del servidor no pueda borrar las copias.

## Probar la restauración

Un backup no probado no es un backup. Procedimiento en un servidor o máquina distinto de producción, todo con comandos **no ejecutados** a partir de la documentación citada:

1. Restaurar el backup en una base con otro nombre (`cafes_restauracion`), nunca sobre producción.
2. **Neutralizar** antes de arrancar con cron activo ([Neutralizar una base de datos](Neutralizar-Base-de-Datos.md)).
3. Arrancar una instancia de la **misma versión mayor** que dice el `manifest.json` (o la versión de la que procedía el `.dump`).
4. Comprobar: entrar con un usuario; abrir el pedido S00042 con sus líneas; abrir un adjunto o una imagen de producto (prueba del filestore); contar registros clave contra la copia de origen.
5. Anotar la fecha, el tamaño del backup, el tiempo de restauración y quién lo hizo.
6. Repetirlo con un calendario (por ejemplo, trimestral), no solo cuando hace falta.

Una comprobación barata del ZIP sin restaurarlo: que contenga `dump.sql`, `manifest.json` y `filestore/`, y que `manifest.json` tenga la versión esperada.

## Restaurar en otro servidor o versión

- **Versión mayor igual**: la restauración funciona entre servidores. Hay que instalar los mismos módulos propios y de terceros, y usar una versión de PostgreSQL que pueda leer el volcado (los volcados se cargan en la misma versión de PostgreSQL o en otra posterior; no se contrastó en esta lectura la compatibilidad concreta).
- **Versión anterior**: no soportado. La documentación de actualización lista entre lo que una migración *no* cubre el «downgrading to a previous version of Odoo» ([actualización, 19.0](https://www.odoo.com/documentation/19.0/administration/upgrade.html)). Una base de una versión más nueva no debe cargarse en un Odoo más antiguo.
- **Versión posterior**: restaurar y migrar son dos pasos distintos. Una base de otra versión mayor no se usa directamente; la propia documentación pide probar la actualización en una base de pruebas antes y avisa de que las bases con módulos propios no se pueden actualizar hasta que exista una versión de esos módulos para la versión de destino. El código de `list_db_incompatible` marca como incompatible una base cuyo `base.latest_version` no coincide con la versión mayor del servidor.
- Versiones soportadas el 2026-11-10: 20.0, 19.0 y 18.0 ([versiones soportadas](https://www.odoo.com/documentation/20.0/administration/standard_extended_support.html)).

## Restaurar es peligroso si no se neutraliza

Una base restaurada es una **copia viva de producción**: conserva servidores de correo saliente, claves de pasarelas de pago, acciones programadas (crons) y webhooks. Si se arranca sin neutralizar, puede enviar correos a clientes reales, cobrar o disparar integraciones desde el servidor de pruebas.

Reglas:

- Restaurar con la opción de neutralizar (`neutralize_database` del gestor) o ejecutar la neutralización antes de arrancar con crons activos. Qué neutraliza exactamente cada módulo: [Neutralizar una base de datos](Neutralizar-Base-de-Datos.md).
- La neutralización no cubre integraciones que viven fuera de la base. Para el resto: [Pruebas seguras en producción](Pruebas-Seguras-en-Produccion.md).

## Cifrado y almacenamiento

Un backup contiene todos los datos de clientes, hashes de contraseñas de usuarios y secretos guardados en parámetros del sistema; robarlo equivale a robar la empresa. Criterios (conceptuales; no se verificó ninguna herramienta concreta):

- Cifrar el backup antes de sacarlo del servidor, y custodiar la clave **fuera** del servidor y de los propios backups.
- Una copia **fuera de la ubicación** principal (regla 3-2-1), con credenciales de subida que no puedan borrar.
- Restringir quién puede leer, y no dejarlos en carpetas compartidas ni en el servidor de pruebas más tiempo del necesario.
- Borrar la copia restaurada de pruebas cuando termine la verificación.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Tras restaurar, las imágenes y adjuntos no se ven o dan error | Se restauró solo la base (`-Fc` o ZIP sin filestore): falta el filestore, o está bajo el nombre de otra base |
| «Database already exists» al restaurar | `restore_db` no sobrescribe: elegir otro nombre o borrar antes la base de destino |
| «Couldn't restore database» | `psql`/`pg_restore` falló (versión de PostgreSQL, extensión ausente, volcado truncado); el código descarta la salida del comando, así que hay que repetirlo a mano con `pg_restore` o `psql` para ver el error |
| La instancia de pruebas envió correos reales | Se restauró sin neutralizar |
| El gestor da *timeout* o error de memoria al hacer backup | Base grande: la documentación desaconseja el gestor; usar `pg_dump` |
| El pedido existe pero su adjunto no | Base y filestore tomados en momentos distintos, o filestore de otra copia |
| La base no carga en el servidor nuevo | Versión de Odoo distinta de la del `manifest.json`, o faltan módulos propios en `addons_path` |
| Nadie recuerda la contraseña del gestor | `admin_passwd` está en `odoo.conf`; la documentación de despliegue explica cómo restablecerla |

## Buenas prácticas avanzadas

- **Guardar el `manifest.json` y la versión de PostgreSQL junto a cualquier copia** que no sea ZIP: sin ellos, saber con qué versión de Odoo se produjo el `.dump` es adivinar.
- **Restaurar siempre a una base nueva** y renombrar después si hace falta. Como `restore_db` rechaza bases existentes, el hábito coincide con el comportamiento por defecto y evita `--clean` sobre datos valiosos.
- **Medir el tiempo de restauración** durante las pruebas: es el dato que determina cuánto tarda una recuperación real y si compensa `pg_restore -j`.
- **Desactivar el gestor de bases en producción** (`list_db = False`, bloqueo de `/web/database` en el proxy) y hacer las copias desde el sistema, no desde la web.
- **Alertar por ausencia**, no por error: un servicio externo que espera una señal diaria detecta el backup que dejó de ejecutarse (véase la ficha de devops enlazada).
- **Comparar tamaño con la copia anterior**: una caída brusca indica un volcado incompleto aunque el script devuelva éxito.

## Documentación oficial

- [Despliegue de Odoo (19.0)](https://www.odoo.com/documentation/19.0/administration/on_premise/deploy.html): seguridad del gestor de bases, `admin_passwd`, `list_db` y la recomendación de copias diarias remotas.
- [Actualización de Odoo (19.0)](https://www.odoo.com/documentation/19.0/administration/upgrade.html): qué cubre una migración y qué no (no se puede volver a una versión anterior).
- [`pg_dump` (PostgreSQL 18)](https://www.postgresql.org/docs/18/app-pgdump.html): formatos, consistencia y restauración en paralelo.
- [`pg_restore` (PostgreSQL 18)](https://www.postgresql.org/docs/18/app-pgrestore.html): `--clean`, `--if-exists`, `--create`, `-j`.

---

*En resumen: un backup de Odoo son base, filestore y configuración; el ZIP del gestor sirve para bases pequeñas y `pg_dump -Fc` para el resto; se restaura siempre a una base nueva, se neutraliza antes de arrancar con crons activos y no cuenta hasta que se ha probado a restaurar.*
