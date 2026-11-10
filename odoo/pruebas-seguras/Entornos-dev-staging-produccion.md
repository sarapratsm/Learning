# Entornos: desarrollo, staging y producción

## ¿Qué es?

Un **entorno** es una instalación completa y aislada de Odoo: su propio servidor, su propia base de datos PostgreSQL, su propio fichero de configuración y su propia dirección. Lo habitual es mantener tres:

- **Producción**: el que usan las personas reales cada día. Tiene los datos de verdad.
- **Staging** (también *preproducción*): una copia casi idéntica de producción, con los datos copiados y neutralizados, donde se ensaya un cambio antes de aplicarlo de verdad.
- **Desarrollo**: donde se programa y se rompe sin miedo, normalmente con datos de prueba o de demostración.

Referencias: rama estable `20.0` de `github.com/odoo/odoo` (`odoo/release.py` declara `version_info = (20, 0, 0, FINAL, 0, '')`) y documentación 20.0, leídas el 2026-11-10. La [página de versiones soportadas](https://www.odoo.com/documentation/20.0/administration/standard_extended_support.html) lista como mayores con soporte estándar la 20.0, la 19.0 y la 18.0. No se ejecutó ninguna instancia de Odoo: cada afirmación procede de un fichero o una página leídos y citados en el punto donde aparece. Lo que no se pudo contrastar figura como «no verificado».

## ¿Por qué existe?

Una pequeña empresa como «Cafés del Valle» —vende productos, gestiona pedidos de venta como el S00042, tiene contactos y empleadas como Ana Ruiz— guarda en su base `cafes_prod` la facturación real. Si cada prueba (instalar un módulo, cambiar una configuración, importar clientes) se hiciera ahí, un error podría facturar mal, enviar correos a clientes reales o dejar el sistema caído mientras el equipo trabaja.

Con entornos separados, el error ocurre en un sitio donde no importa, se corrige, y solo entonces se lleva a producción.

> Es la misma idea que ensayar una obra de teatro antes del estreno: nadie prueba la función por primera vez delante del público que ha pagado la entrada.

## ¿Cuándo y para qué se usa?

- Antes de **actualizar Odoo** a otra versión mayor: se prueba en staging para ver qué se rompe.
- Antes de **instalar o actualizar un módulo**: se comprueba en una copia que todo sigue funcionando.
- Para **desarrollar** funcionalidad a medida sin que los datos de prueba contaminen la contabilidad real.
- Para **formar** a personas nuevas o hacer demostraciones sin tocar datos reales.

## Qué es cada entorno y qué datos tiene

| Entorno | Base de datos (ejemplo) | Dirección (ejemplo) | Datos | Para qué |
|---|---|---|---|---|
| Producción | `cafes_prod` | `erp.ejemplo.com` | Reales, en uso | Operar la empresa |
| Staging | `cafes_staging` | `staging.ejemplo.com` | Copia de producción, neutralizada | Ensayar cambios con datos realistas |
| Desarrollo | `cafes_dev` | `localhost:8069` | De demostración o mínimos inventados | Programar y experimentar |

Los nombres son inventados. Lo que importa es que cada entorno tenga base, dirección y credenciales propias: si dos entornos comparten algo (la base, una clave de API, un servidor de correo), dejan de estar aislados.

Dos consecuencias sobre los datos:

- **Desarrollo no necesita datos reales.** Una base con datos de demostración basta para programar. Cuanto menos dato real circule por los portátiles, menos hay que proteger.
- **Staging sí los necesita**, porque el objetivo es ensayar sobre la realidad. Por eso nace de una copia de producción (ver [Duplicar la base de datos](Duplicar-Base-de-Datos.md)) y se neutraliza (ver [Neutralizar la base de datos](Neutralizar-Base-de-Datos.md)).

## El flujo de cambios

Hay dos corrientes que van en sentidos opuestos:

```
Código:   rama de trabajo ──► desarrollo ──► staging ──► producción
Datos:    producción ──────────────────────► staging (copia neutralizada)
```

1. **Rama.** El cambio (un módulo propio, una modificación de vistas) se escribe en una rama del repositorio de control de versiones.
2. **Desarrollo.** Se prueba en local o en el servidor de desarrollo, con datos de prueba.
3. **Staging.** Se despliega el código en una copia fresca de producción. Se prueba con datos reales neutralizados y se anota cada paso.
4. **Producción.** Se repiten, en el mismo orden, los pasos que funcionaron en staging.

El código sube; los datos solo bajan (de producción a staging) y siempre neutralizados. Lo que se configura a mano en staging (un ajuste, un campo creado desde la interfaz) no viaja a producción: hay que repetirlo o, mejor, escribirlo en un módulo que se despliegue.

## Paridad entre entornos

Un ensayo solo vale si el entorno de ensayo se comporta como producción. Debe coincidir:

- **Versión de Odoo**: misma rama y misma revisión del código.
- **Versiones de Python y PostgreSQL**: una diferencia en PostgreSQL puede cambiar el plan de una consulta o el comportamiento de una migración.
- **Módulos y su versión**: los mismos módulos instalados, tanto los de Odoo como los de terceros y propios. Una ruta `addons_path` distinta cambia qué se carga.
- **Parámetros de arranque relevantes**: por ejemplo `workers`, que activa el servidor multiproceso (ver la sección siguiente).

Lo que sí debe diferir: los datos sensibles (neutralizados), la dirección, las credenciales de servicios externos y el correo.

## Qué hace distinto a staging

| Aspecto | Producción | Staging |
|---|---|---|
| Datos | Reales | Copiados de producción |
| Correo saliente | Servidores SMTP reales | Neutralizado; con la neutralización de Odoo no sale ningún correo |
| Acciones planificadas (crons) | Activas | Desactivadas |
| Pasarelas de pago, métodos de envío | Reales | En pruebas o desactivadas |
| Webhooks | Reales | Desactivados |
| Dirección | `erp.ejemplo.com` | `staging.ejemplo.com` |

Qué hace exactamente la neutralización se verificó en `odoo/addons/base/data/neutralize.sql` (rama 20.0). Ese fichero:

- desactiva los servidores de correo saliente (`ir_mail_server`) y borra su usuario y contraseña SMTP;
- inserta un servidor ficticio llamado `neutralization - disable emails`, con host `invalid`, para que no se use ningún servidor de reserva indicado por línea de comandos;
- desactiva todas las acciones planificadas (`ir_cron`), salvo el trabajo `autovacuum_job` de `base`;
- escribe el parámetro del sistema `database.is_neutralized` con el valor `True`;
- sustituye la URL de las acciones de servidor de tipo webhook por el texto `neutralization - disable webhook`.

Otros módulos añaden su propio `neutralize.sql` (pagos, envíos, sitio web). La [documentación de bases neutralizadas](https://www.odoo.com/documentation/20.0/administration/neutralized_database.html) lista, como relación no exhaustiva, las acciones planificadas, el correo saliente, la sincronización bancaria, los proveedores de pago, los métodos de entrega, los tokens IAP y la visibilidad del sitio web. El detalle por módulo está en la ficha de neutralización.

Dos cosas que la neutralización no cubre solas:

- **El dominio.** `web.base.url` y los enlaces de los correos dependen de la configuración de cada instancia; en una copia siguen valiendo lo que valía en producción hasta que se cambian. No se verificó en el código si la neutralización los modifica; trátalo como pendiente de revisar tras cada copia.
- **Lo que vive fuera de la base.** Si staging apunta al mismo servicio externo con la misma clave que producción, una prueba puede tocar datos reales aunque la base sea una copia.

## Configuración por entorno: `odoo.conf`

Cada entorno arranca con su propio fichero de configuración (más sobre el formato en [El fichero odoo.conf](../configuracion-parametros/El-Fichero-odoo-conf.md)). Estas son las opciones que más suelen variar, contrastadas con `odoo/tools/config.py` (rama 20.0) y con la [guía de despliegue](https://www.odoo.com/documentation/20.0/administration/on_premise/deploy.html):

| Opción | Qué hace según el código/la documentación | Valor típico por entorno |
|---|---|---|
| `db_name` | Base(s) de datos con las que trabaja el servidor (en línea de comandos, `-d`/`--database`; acepta lista separada por comas; por defecto vacío). | Producción: `cafes_prod`. Staging: `cafes_staging`. |
| `dbfilter` | Expresión regular que filtra qué bases se ofrecen en la interfaz web; admite los marcadores `%d` (dominio) y `%h` (host). Por defecto vacío. | Producción: `^cafes_prod$`. Staging: `^cafes_staging$`. |
| `list_db` | Por defecto `True`. Con `False` se oculta la lista de bases y se desactivan el gestor y el selector de bases (opción `--no-database-list`; el código avisa de fijar antes `--database`). | `False` en producción y staging; puede ser `True` en desarrollo local. |
| `admin_passwd` | Contraseña maestra de las pantallas de gestión de bases. Se lee solo desde el fichero (`FileOnlyOption`); su valor por defecto en el código es `admin`. | Distinta y secreta en cada entorno; nunca el valor por defecto. |
| `workers` | Número de procesos de trabajo; por defecto 0, que desactiva el modo multiproceso. La guía de despliegue lo describe como la forma de aprovechar varios núcleos y fija que, con él, se lanzan también procesos para las tareas planificadas. | Producción: según CPU. Desarrollo: 0. |
| `proxy_mode` | Opción `--proxy-mode`, por defecto `False`; la guía de despliegue la usa cuando Odoo va detrás de un proxy inverso. | Activa donde haya proxy inverso. |

Ejemplo de dos ficheros con valores inventados (no ejecutado: formado según las opciones de la tabla):

```ini
; /etc/odoo/odoo.conf  (producción)
[options]
db_name = cafes_prod
dbfilter = ^cafes_prod$
list_db = False
admin_passwd = <hash o secreto propio de producción>
workers = 4
proxy_mode = True
```

```ini
; /etc/odoo/odoo.conf  (staging)
[options]
db_name = cafes_staging
dbfilter = ^cafes_staging$
list_db = False
admin_passwd = <secreto propio de staging, distinto del de producción>
workers = 4
proxy_mode = True
```

La guía de despliegue indica que, cuando una instalación sirve varias bases, `dbfilter` debe fijarse, y que con una sola base por nombre de host conviene poner `list_db = False` para no exponer la lista. Que el valor exacto de `workers` deba ser igual en staging que en producción es una recomendación de buena práctica, no una regla de Odoo: se propone para que el ensayo de rendimiento se parezca al real.

## Identificar visualmente el entorno

Equivocarse de pestaña es el error humano más caro: ejecutar «prueba» en producción creyendo que es staging. Medidas, de menos a más fiable:

1. **Banner de la base neutralizada.** La documentación oficial indica: «A red banner at the top of the screen is displayed on the neutralized database so that it can be seen immediately». Es decir, quien abre una copia neutralizada ve un banner rojo en la parte superior. En el código de la rama 20.0 lo pinta la vista `web.neutralize_banner` (`addons/web/views/neutralize_views.xml`), inactiva por defecto y activada por el `neutralize.sql` del módulo `web`; el detalle está en [Neutralizar la base de datos](Neutralizar-Base-de-Datos.md).
2. **El parámetro del sistema.** `database.is_neutralized = True` queda escrito por `neutralize.sql`; se puede consultar en el modo desarrollador (ver [Modo desarrollador](../fundamentos/Modo-Desarrollador.md)). Una base sin esa clave no pasó por la neutralización.
3. **Dirección distinta y reconocible.** `staging.ejemplo.com` frente a `erp.ejemplo.com`. Un certificado y un título de pestaña distintos ayudan.
4. **Nombre de empresa o de base distinto**, visible para quien trabaja: por ejemplo, anteponer «STAGING» al nombre de la compañía en la copia. Si lo hace una persona a mano, debe ser parte del procedimiento de refresco.

## Odoo.sh como alternativa gestionada

Odoo.sh es la plataforma alojada de Odoo que organiza el flujo anterior alrededor de ramas de Git. Según la [página de ramas (documentación 20.0)](https://www.odoo.com/documentation/20.0/administration/odoo_sh/getting_started/branches.html), cada rama tiene una de tres etapas:

| Etapa | Qué hace la documentación | Datos |
|---|---|---|
| **Producción** | Contiene el código que ejecuta la base de producción; solo puede haber una. Un commit nuevo actualiza el servidor de producción. Se hacen copias automáticas (siete diarias, cuatro semanales y tres mensuales, según la página). | Reales; no carga datos de demostración. |
| **Staging** | Prueba funciones nuevas con datos de producción. Crea duplicados neutralizados de la base de producción. Desactiva acciones planificadas, correo saliente (se intercepta con un capturador de correo), servicios IAP y pasarelas y conectores de envío (los pone en modo de prueba). | Copia de producción. Se borra automáticamente al mes; no hay copias automáticas. |
| **Desarrollo** | Crea bases nuevas con datos de demostración y ejecuta las pruebas unitarias. | Demo. Pensada para durar unos tres días; sin copias. |

Una rama se mueve entre etapas arrastrándola; la página advierte que una rama de staging no puede pasar directamente a producción (hay que hacer una fusión) y que solo puede haber una de producción. En desarrollo y staging, el correo no sale: se intercepta.

Si no se usa Odoo.sh (instalación propia, *on-premise*), esas garantías no vienen de serie: hay que montar el servidor de staging, duplicar y neutralizar la base y gestionar los backups.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Clientes reales reciben correos de «staging» | La copia no se neutralizó, o se restauró sin pasar por la neutralización; el servidor SMTP de producción seguía activo. |
| Un cron de staging factura o sincroniza contra producción | Acciones planificadas activas en la copia; o una integración externa con las credenciales de producción. |
| Una pasarela de pago cobra desde staging | Proveedor de pago no puesto en modo de prueba y con la clave real. |
| «Me funcionó en staging y falló en producción» | Falta de paridad: otra versión de Odoo, de PostgreSQL, otro conjunto de módulos o datos de un staging antiguo. |
| Se ejecuta una prueba en producción | Pestañas idénticas, sin banner ni nombre distinto; se confundió el entorno. |
| El ajuste hecho a mano en staging no aparece en producción | Los entornos no se sincronizan; el ajuste debía estar en un módulo desplegable o repetido en producción. |
| La lista de bases es visible desde internet | `list_db` a `True` (valor por defecto) en un servidor expuesto. |
| Dos entornos con la misma `admin_passwd` | Se copió el `odoo.conf` sin cambiar los secretos; una brecha en uno compromete al otro. |
| Staging expuesto sin autenticación | Se olvidó que contiene datos personales reales (ver Buenas prácticas). |

## Buenas prácticas avanzadas

- **Re-clona staging justo antes de un ensayo serio.** Un staging de hace meses ha divergido de producción en datos y configuración. El ensayo que cuenta se hace sobre una copia fresca, y la copia se neutraliza antes de arrancarla por primera vez (ver [Duplicar la base de datos](Duplicar-Base-de-Datos.md) y [Neutralizar la base de datos](Neutralizar-Base-de-Datos.md)).
- **Convierte el ensayo en un guion.** Anota cada paso, su orden y su duración mientras ensayas. El día del cambio real no se improvisa: se repite lo ensayado, y de paso se sabe cuánto tiempo estará parado producción.
- **Credenciales propias por entorno.** Staging debe usar claves de sandbox de cada servicio externo, no las de producción. La neutralización cubre lo que Odoo conoce; no cubre un script externo que lea la misma clave.
- **Trata staging como producción para la privacidad.** La copia neutralizada no envía correos, pero contiene nombres, correos y facturas de personas reales. Restringe el acceso, no la expongas sin autenticación y aplica la misma política de retención que a producción.
- **Los backups no son un entorno.** Staging sirve para ensayar, no para recuperar datos perdidos: eso depende de [las copias de seguridad y su restauración](Backups-y-Restauracion.md), y de que se hayan probado.
- **Cuando hay que probar sobre producción, no sobre staging**, lo que se pueda hacer sin riesgo se describe en [Pruebas seguras en producción](Pruebas-Seguras-en-Produccion.md).

## Documentación oficial

- [Neutralized database](https://www.odoo.com/documentation/20.0/administration/neutralized_database.html): qué desactiva la neutralización y el aviso del banner rojo.
- [Deploying Odoo (on-premise)](https://www.odoo.com/documentation/20.0/administration/on_premise/deploy.html): `dbfilter`, `list_db`, `admin_passwd`, `workers` y `proxy_mode` en un despliegue real.
- [Odoo.sh: Branches](https://www.odoo.com/documentation/20.0/administration/odoo_sh/getting_started/branches.html): etapas de desarrollo, staging y producción y qué hace cada una.

---

*En resumen: producción tiene los datos reales, staging los copia ya neutralizados para ensayar con realismo y desarrollo trabaja con datos de prueba; el código sube de rama en rama, los datos solo bajan, y cada entorno necesita base, dirección, credenciales y configuración (`db_name`, `dbfilter`, `list_db`, `admin_passwd`, `workers`) propias y una señal visible que lo distinga.*
