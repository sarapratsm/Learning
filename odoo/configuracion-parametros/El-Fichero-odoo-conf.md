# El fichero odoo.conf

## ¿Qué es?

`odoo.conf` es el fichero de configuración del **servidor** de Odoo: un archivo de texto en formato `ini` con una sección `[options]` y pares `clave = valor`. Declara lo que el proceso necesita saber antes de arrancar: a qué PostgreSQL conectarse, en qué carpetas buscar módulos, en qué puerto escuchar, cuántos procesos levantar, cuánta memoria puede gastar cada uno y dónde escribir los logs. Odoo lo lee **una sola vez, al iniciarse**.

Referencias: `odoo/tools/config.py` y la documentación de la rama estable `20.0` de `github.com/odoo/odoo` (leídos el 2026-11-10). La [página de versiones soportadas](https://www.odoo.com/documentation/20.0/administration/standard_extended_support.html) lista como mayores con soporte estándar la 20.0, la 19.0 y la 18.0. No se ejecutó ninguna instancia de Odoo: los valores por defecto y el orden de precedencia salen de la lectura de `config.py`, citada en cada punto.

## ¿Por qué existe?

Hay datos que Odoo necesita antes de poder funcionar y que dependen de la máquina, no del negocio: la contraseña de PostgreSQL de este servidor, la ruta de los addons en este disco, cuántos workers aguanta esta CPU. Meterlos en el código sería absurdo, porque cambian de un servidor a otro. `odoo.conf` separa esa configuración de infraestructura del programa.

> Si vienes de .NET, es el equivalente a `appsettings.json` (y a las variables de entorno del servicio): parámetros de entorno que se leen al arrancar, sin lógica de negocio.

## ¿Cuándo y para qué se usa?

- **Montar un servidor**: primera instalación, apuntar a PostgreSQL, fijar puertos y proxy.
- **Añadir una carpeta de módulos**: cuando un módulo propio no aparece en Aplicaciones, casi siempre falta su carpeta en `addons_path`.
- **Ajustar rendimiento**: número de workers y límites de memoria y tiempo.
- **Endurecer producción**: contraseña maestra, ocultar el gestor de bases de datos, filtrar qué base ve cada dominio.
- Quien desarrolla módulos lo toca poco; quien administra el despliegue, a menudo.

## Formato y ejemplo

Es un `ini` con una única sección relevante, `[options]`. Las claves son el nombre de la opción de línea de comandos con guiones bajos (`--http-port` es `http_port`, `--db-filter` es `dbfilter`). A continuación, un **ejemplo inventado** para el servidor de la pequeña empresa «Cafés del Valle» (no ejecutado):

```ini
[options]
; Contraseña maestra del gestor de bases de datos (valor de ejemplo)
admin_passwd = cambia-esto-por-una-frase-larga

; PostgreSQL
db_host = 127.0.0.1
db_port = 5432
db_user = odoo
db_password = contraseña-de-ejemplo
db_maxconn = 64

; Módulos: carpetas separadas por comas
addons_path = /opt/odoo/addons,/opt/odoo-extra/cafes_del_valle

; Red
http_interface = 127.0.0.1
http_port = 8069
proxy_mode = True

; Una sola base visible, la del dominio
dbfilter = ^%d$
list_db = False

; Procesos y límites (cifras de ejemplo, no recomendaciones)
workers = 5
limit_memory_soft = 2147483648
limit_memory_hard = 2684354560
limit_time_cpu = 60
limit_time_real = 120

; Datos y logs
data_dir = /var/lib/odoo
logfile = /var/log/odoo/odoo.log
```

Qué se ve: al arrancar con `odoo -c /etc/odoo/odoo.conf`, Odoo toma esos valores. Los nombres de las opciones corresponden a los `dest` definidos en `config.py` (20.0).

## Dónde busca Odoo el fichero

La opción `-c` / `--config` indica la ruta; también se puede dar por la variable de entorno `ODOO_RC` (`config.py`, definición de la opción `config`). Si no se indica, `_load_default_options` elige, por este orden:

1. `odoo.conf` en el directorio de configuración del usuario (calculado con `appdirs`), si existe.
2. En Windows: `odoo.conf` junto al ejecutable lanzado.
3. En otros sistemas: `~/.odoorc` si existe y, si no, `~/.openerp_serverrc` (con aviso de obsolescencia).
4. Si ninguno existe, la ruta de la primera opción, que no se crea salvo con `--save`.

Si se pasa `-c` con un fichero que no existe o no se puede leer y no se usa `--save`, Odoo se detiene con un error de parámetros (`_parse_config`).

## Precedencia: qué gana cuando un valor aparece en varios sitios

En `config.py` (20.0) las opciones viven en un `ChainMap` con este orden, de mayor a menor prioridad:

| Prioridad | Origen | Ejemplo |
|---|---|---|
| 1 | Valores de ejecución (el propio código) | no aplica al administrador |
| 2 | Argumentos de línea de comandos | `--http-port=8070` |
| 3 | Variables de entorno | `ODOO_HTTP_PORT`, `PGHOST` |
| 4 | Fichero `odoo.conf` | `http_port = 8069` |
| 5 | Valores por defecto del código | `8069` |

Consecuencias prácticas:

- Un argumento de línea de comandos **pisa** al fichero: sirve para levantar un entorno de pruebas con un puerto distinto sin tocar el fichero.
- Una variable de entorno también pisa al fichero. Si un valor «no hace caso» a `odoo.conf`, conviene comprobar el entorno del servicio y la línea de arranque.
- Hay opciones **solo de fichero** (`FileOnlyOption`, por ejemplo `admin_passwd`, `reportgz`, `csv_internal_sep`) que no existen como argumento de línea de comandos, y opciones **solo de línea de comandos** (`file_loadable=False`, por ejemplo `-i`, `-u`, `--save`).

## Variables de entorno

Sí: `config.py` genera un nombre `ODOO_<OPCIÓN_EN_MAYÚSCULAS>` para las opciones que se pueden cargar desde fichero (`ODOO_HTTP_PORT`, `ODOO_WORKERS`…) y define explícitamente otras, entre ellas las de PostgreSQL:

| Opción | Variable de entorno |
|---|---|
| `config` (ruta del fichero) | `ODOO_RC` |
| `db_host` | `PGHOST` |
| `db_port` | `PGPORT` |
| `db_user` | `PGUSER` |
| `db_password` | `PGPASSWORD` |
| `db_name` | `PGDATABASE` |
| `dev_mode` | `ODOO_DEV` |

Las variables de entorno son útiles en contenedores, donde evitan dejar la contraseña en un fichero. Esa generación automática de `ODOO_*` figura en la rama 20.0; en ramas anteriores no se verificó.

## Guardar la configuración con `--save`

`odoo -c /ruta/odoo.conf -d cafes --save --stop-after-init` escribe en el fichero los valores efectivos de esa ejecución (`save()` en `config.py`): crea la sección `[options]` y vuelca las opciones exportables. Si el fichero no existía, lo crea (junto con su directorio). Sin `-c`, `--save` escribe en la ruta por defecto (`~/.odoorc` en Linux/macOS). El resultado incluye lo que venía de la línea de comandos y del entorno, no solo del fichero: conviene revisarlo antes de dejarlo en un servidor, porque podría arrastrar valores temporales.

## Opciones que más se tocan

Valores por defecto leídos de `config.py` (20.0):

| Opción | Por defecto | Qué hace |
|---|---|---|
| `addons_path` | vacío (lista) | Carpetas con módulos, separadas por comas. |
| `http_interface` | `127.0.0.1` | Interfaz de red donde escucha. |
| `http_port` | `8069` | Puerto HTTP. |
| `gevent_port` | `8072` | Puerto del servicio de larga conexión (websocket) en modo multiproceso. |
| `proxy_mode` | `False` | Interpreta las cabeceras de un proxy inverso. Solo detrás de un proxy de confianza. |
| `db_host` / `db_port` / `db_user` / `db_password` | vacío / sin valor / vacío / vacío | Conexión a PostgreSQL. |
| `db_maxconn` | `64` | Máximo de conexiones físicas a PostgreSQL por proceso. |
| `dbfilter` | vacío | Expresión regular que filtra las bases visibles; admite `%d` (dominio) y `%h` (host). |
| `list_db` | `True` | Si es `False`, se desactiva el listado de bases y el gestor de bases de datos. |
| `admin_passwd` | `admin` | Contraseña maestra del gestor de bases de datos. |
| `data_dir` | directorio de datos del usuario (`appdirs`) | Dónde guarda Odoo adjuntos y sesiones. |
| `logfile` | vacío (salida estándar) | Fichero de log. |

La documentación de `list_db` indica que, al desactivarlo, conviene fijar antes `--database`: sin base indicada, no habría forma de elegir una.

## Rendimiento: workers y límites

Por defecto `workers = 0`: Odoo corre en un solo proceso con hilos, sin los límites de abajo (`config.py`: «Specify the number of workers, 0 disable prefork mode»). Con `workers > 0` arranca el modo multiproceso, que es el de producción. Los límites actúan **por worker**:

| Opción | Por defecto | Significado |
|---|---|---|
| `workers` | `0` | Procesos que atienden peticiones. |
| `max_cron_threads` | `2` | Hilos de tareas programadas. |
| `limit_memory_soft` | 2048 MiB (2 147 483 648 bytes) | Pasado este umbral, el worker se reinicia tras terminar la petición en curso. |
| `limit_memory_hard` | 2560 MiB (2 684 354 560 bytes) | Pasado este umbral, la reserva de memoria falla. |
| `limit_time_cpu` | `60` s | Tiempo de CPU máximo por petición. |
| `limit_time_real` | `120` s | Tiempo real máximo por petición. |
| `limit_request` | `65536` | Peticiones atendidas antes de reciclar el worker. |

Un ajuste de memoria demasiado bajo mata peticiones legítimas (informes grandes, importaciones); uno demasiado alto permite que un worker agote el servidor. Cuántos workers usar depende de las CPU y la RAM: la documentación de [despliegue](https://www.odoo.com/documentation/20.0/administration/on_premise/deploy.html) explica cómo estimarlo; no se reproduce aquí una fórmula que no se haya contrastado.

## Seguridad y secretos

- `admin_passwd` tiene por defecto `admin`: **cámbiala siempre**. Protege crear, duplicar y borrar bases desde el navegador.
- En producción, `list_db = False` y un `dbfilter` estricto.
- `proxy_mode = True` solo si hay un proxy inverso que reescribe las cabeceras; sin él, un cliente podría falsificarlas.
- El fichero contiene `admin_passwd` y `db_password`: **no se versiona** con valores reales. En el repositorio, como mucho, una plantilla con los secretos en blanco. En Linux, propietario el usuario del servicio y permisos `600` o `640` (práctica general del sistema operativo, no de Odoo).

## `odoo.conf` frente a `ir.config_parameter`

| Dato | Dónde va | Por qué |
|---|---|---|
| Contraseña de PostgreSQL, puerto, workers, `addons_path` | `odoo.conf` | Lo necesita el proceso antes de tener base de datos; depende de la máquina. |
| URL base del sitio, plazo de un proceso de negocio, interruptor de una función | Parámetros del sistema (`ir.config_parameter`) | Vive en la base de datos, se edita sin reiniciar y viaja con la base. Ver [Parametros-del-Sistema.md](Parametros-del-Sistema.md). |
| Opción que el usuario administrador cambia desde la interfaz | Ajustes | Ver [Ajustes.md](Ajustes.md). |
| Valor distinto por compañía | Configuración por compañía | Ver [Configuracion-por-Compania.md](Configuracion-por-Compania.md). |

Regla práctica: si Odoo lo necesita **antes** de conectar con la base, o cambia entre servidores, va a `odoo.conf`; si forma parte de los datos de la empresa, va a la base de datos. Fichas relacionadas: [Valores-por-Defecto.md](Valores-por-Defecto.md) y [Referencias-por-ID-Externo.md](Referencias-por-ID-Externo.md).

Leer el fichero desde código es posible (solo lectura):

```python
from odoo.tools import config

data_dir = config["data_dir"]
```

## Errores frecuentes

- **Cambié el fichero y no pasa nada** → se lee al arrancar: hay que reiniciar el servicio. Si aun así no cambia, un argumento de línea de comandos o una variable de entorno lo está pisando.
- **Un módulo propio no aparece en Aplicaciones** → su carpeta no está en `addons_path`, o falta actualizar la lista de aplicaciones.
- **Odoo no arranca con `-c` y un fichero inexistente** → `_parse_config` aborta con «the config file ... selected with -c/--config doesn't exist or is not readable, use --save if you want to generate it».
- **Una opción del fichero se ignora** → nombre mal escrito: Odoo registra un aviso «unknown option ... in the config file» y guarda el valor sin interpretarlo.
- **`list_db = False` y no puedo entrar** → no hay base definida; hay que fijar `db_name` o un `dbfilter` que resuelva una sola.
- **Peticiones largas que mueren** → superan `limit_time_cpu` o `limit_time_real`; revisar el trabajo antes de subir los límites a ciegas.

## Buenas prácticas avanzadas

- **Una plantilla versionada y el fichero real fuera del repositorio**, con secretos inyectados por el despliegue o por variables de entorno (`PGPASSWORD`, `ODOO_RC`).
- **Documenta qué pisa qué en cada servidor**: un servicio con `Environment=` en la unidad de systemd y otro valor en `odoo.conf` es una fuente clásica de «no hace caso».
- **`--save` para generar, no para mantener**: úsalo una vez para obtener una plantilla completa y edita después a mano.
- **Los límites de memoria van en bytes**: un cero de más o de menos cambia el límite en un orden de magnitud.
- **`dbfilter` con ancla (`^%d$`)** para que un dominio no coincida con varias bases por prefijo.

## Documentación oficial

- [Despliegue en servidor propio (20.0)](https://www.odoo.com/documentation/20.0/administration/on_premise/deploy.html): workers, proxy inverso, `dbfilter` y seguridad de la base de datos.
- [Instalación con paquetes (20.0)](https://www.odoo.com/documentation/20.0/administration/on_premise/packages.html): dónde deja el fichero cada paquete.
- [Interfaz de línea de comandos (20.0)](https://www.odoo.com/documentation/20.0/developer/reference/cli.html): lista de las opciones de arranque.
- [`odoo/tools/config.py` en la rama 20.0](https://github.com/odoo/odoo/blob/20.0/odoo/tools/config.py): la fuente de verdad de nombres, valores por defecto y precedencia.

---

*En resumen: `odoo.conf` es la configuración de infraestructura que el servidor lee al arrancar; un argumento o una variable de entorno la pisan, los secretos no se versionan, y lo que pertenece a los datos de la empresa va a la base de datos.*
