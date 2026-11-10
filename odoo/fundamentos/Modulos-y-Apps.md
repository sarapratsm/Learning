# Módulos y Apps

## ¿Qué es?

Un **módulo** de Odoo es una carpeta de código Python y XML que contiene un fichero `__manifest__.py`; es la unidad mínima en la que se instala, actualiza y desinstala funcionalidad. Una **App** (*Aplicación* en la interfaz en español) es un módulo cuyo manifest declara `'application': True`: el que se presenta como producto completo en el menú de aplicaciones, frente a los módulos técnicos que solo amplían a otro.

Referencias de código y documentación: rama estable `20.0` de `github.com/odoo/odoo` (HEAD `4611da65a7`, leído el 2026-11-10) y documentación 20.0. La [página de versiones soportadas](https://www.odoo.com/documentation/20.0/administration/standard_extended_support.html) lista como versiones mayores con soporte estándar la 20.0 (septiembre de 2026), la 19.0 y la 18.0. No se ejecutó ninguna instancia de Odoo: todo lo que sigue procede de ficheros y páginas leídos, citados en cada punto.

## ¿Por qué existe?

Una pequeña empresa como «Cafés del Valle» —vende productos, gestiona pedidos de venta y contactos, tiene empleadas como Ana Ruiz— no necesita fabricación ni punto de venta. Odoo ([qué es y cómo encajan Python y PostgreSQL](Odoo.md)) parte de un núcleo mínimo y deja que cada capacidad sea un módulo que se instala solo si hace falta. Además, cada módulo declara de qué otros depende, de modo que el servidor sabe en qué orden cargarlos y qué instalar por añadidura.

> Si ya conoces `apt`, `npm` o `pip`, piensa en un módulo como un paquete con dependencias declaradas. La documentación oficial hace la misma comparación con los gestores de paquetes de Linux ([capítulo 2 del tutorial de servidor](https://www.odoo.com/documentation/20.0/developer/tutorials/server_framework_101/02_newapp.html)). La diferencia es que instalar un módulo no copia ficheros: **modifica la base de datos** (tablas, columnas, vistas, datos).

## ¿Cuándo y para qué se usa?

- **Activar una capacidad estándar**: instalar la App de ventas para tener presupuestos y pedidos como el S00042 de Cafés del Valle.
- **Añadir un campo, una vista o una regla propia** sin tocar el código oficial: un módulo propio que depende del módulo que quiere extender.
- **Integrar un servicio externo** o incorporar un módulo de la comunidad.
- **Entender un error de carga**: casi todos los fallos al arrancar tras un cambio (módulo que no aparece, dependencia ausente, vista rota) se resuelven sabiendo cómo se carga un módulo.

## Anatomía de un módulo

Un módulo debe contener al menos `__manifest__.py` e `__init__.py`; el único campo obligatorio del manifest es `name` ([tutorial, capítulo 2](https://www.odoo.com/documentation/20.0/developer/tutorials/server_framework_101/02_newapp.html), [referencia del manifest](https://www.odoo.com/documentation/20.0/developer/reference/backend/module.html)). El resto de carpetas es convención.

El ejemplo real es `hr_fleet`, un módulo pequeño de `addons/` de la rama 20.0 que añade el historial de vehículos conducidos por cada empleado. Sus ficheros, sin `i18n/` ni `tests/`:

```
addons/hr_fleet/
├── __init__.py
├── __manifest__.py
├── data/hr_fleet_demo.xml
├── models/                         (hr_employee.py, fleet_vehicle.py, ...)
├── security/ir.access.csv
├── static/src/views/hr_fleet_kanban/
└── views/                          (hr_employee_views.xml, fleet_vehicle_views.xml, ...)
```

Fuente: [`addons/hr_fleet` en la rama 20.0](https://github.com/odoo/odoo/tree/20.0/addons/hr_fleet). Su manifest completo:

```python
# Part of Odoo. See LICENSE file for full copyright and licensing details.
{
    'name': 'Fleet History',
    'category': 'Human Resources',
    'summary': 'Get history of driven cars by employees',
    'depends': ['hr', 'fleet'],
    'data': [
        'views/hr_employee_views.xml',
        'views/fleet_vehicle_views.xml',
        'views/fleet_vehicle_cost_views.xml',
        'security/ir.access.csv',
    ],
    'demo': [
        'data/hr_fleet_demo.xml',
    ],
    'assets': {
        'web.assets_backend': [
            'hr_fleet/static/src/views/**/*',
        ],
    },
    'auto_install': True,
    'author': 'Odoo S.A.',
    'license': 'LGPL-3',
}
```

Qué hace cada pieza, con las claves tal como las define la [referencia del manifest](https://www.odoo.com/documentation/20.0/developer/reference/backend/module.html):

| Pieza | Papel | En `hr_fleet` |
|---|---|---|
| `__manifest__.py` | Diccionario Python que declara el paquete como módulo y sus metadatos. | Arriba. |
| `__init__.py` | Importa los subpaquetes de Python. | Contiene `from . import models`. |
| `models/` | Clases Python que definen o extienden modelos. | `hr_employee.py` empieza con `class HrEmployee(models.Model): _inherit = 'hr.employee'`: extiende un modelo ajeno en lugar de crear uno. |
| `views/` | XML con vistas, acciones y menús. | `hr_employee_views.xml` declara un registro `ir.ui.view` con `inherit_id` apuntando a `hr.view_employee_form`: una vista heredada. |
| `security/` | Permisos de acceso a los modelos. | `ir.access.csv` (véase el aparte siguiente). |
| `data/` y `demo` | Datos cargados al instalar; los de `demo` solo con datos de demostración. | `data/hr_fleet_demo.xml`, solo en `demo`. |
| `static/` y `assets` | Ficheros de cliente (JS, XML de OWL, SCSS) y el paquete (*bundle*) donde se cargan. | `static/src/views/**/*` en `web.assets_backend`. |
| `depends` | Módulos que deben cargarse antes. | `hr` y `fleet`. |
| `auto_install` | Se instala solo cuando todas sus dependencias están instaladas. | `True`: «módulo puente» entre `hr` y `fleet`. |

**Orden de los ficheros de `data`.** Se cargan en el orden de la lista: si un dato A referencia a otro B, B debe ir antes ([tutorial, capítulo 4](https://www.odoo.com/documentation/20.0/developer/tutorials/server_framework_101/04_securityintro.html)).

**Aparte: el fichero de permisos cambió de nombre.** Leído en el código el 2026-11-10:

| Rama | Fichero en `security/` | Cabecera de columnas |
|---|---|---|
| 20.0 | `ir.access.csv` | `id,name,model_id,group_id/id,operation,domain` (p. ej. `crud`, `r`) |
| 19.0 (leído en `addons/sale`) | `ir.model.access.csv` | `id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink` |

En 20.0 el modelo es `ir.access` ([referencia de seguridad](https://www.odoo.com/documentation/20.0/developer/reference/backend/security.html)) y un modelo sin ningún permiso definido queda inaccesible para todos los usuarios ([tutorial, capítulo 4](https://www.odoo.com/documentation/20.0/developer/tutorials/server_framework_101/04_securityintro.html)). La rama 18.0 de `hr_fleet` y `sale` también tiene `ir.model.access.csv` (nombre del fichero verificado; contenido no leído). Las versiones anteriores a 18.0 no se comprobaron. Un módulo de terceros escrito para 19.0 o anterior que declare `ir.model.access.csv` no es portable sin cambios a 20.0: no se verificó cómo reacciona 20.0 a ese fichero.

### Módulo técnico frente a App: dos manifests reales

En 20.0 el menú de ventas procede de dos módulos, leídos en sus manifests:

- `sale` («Sales», resumen «Sales internal machinery»): sin clave `application`, es decir, `False` por defecto. Contiene la maquinaria común.
- `sale_management` («Sales», resumen «From quotations to invoices»): `"depends": ["sale", "digest"]` y `"application": True`. Es el que aparece como App.

La referencia define `application` como el criterio para considerar al módulo una aplicación completa (`True`) o un módulo técnico que da funciones extra a una aplicación ([referencia del manifest](https://www.odoo.com/documentation/20.0/developer/reference/backend/module.html)). En la base de datos es un campo booleano de `ir.module.module`, el modelo que representa a cada módulo.

## Dependencias y orden de carga

`depends` lista los módulos que deben cargarse antes. Al instalar un módulo se instalan primero todas sus dependencias, y las dependencias se cargan antes que él ([referencia del manifest](https://www.odoo.com/documentation/20.0/developer/reference/backend/module.html)).

Tres consecuencias que se leen en el código (`odoo/addons/base/models/ir_module.py` y `odoo/modules/module_graph.py`, rama 20.0):

- **Instalar arrastra.** `button_install` marca para instalar el módulo y sus dependencias, y después busca los módulos con `auto_install` cuyas dependencias estén todas instaladas o por instalar. Por eso al instalar `hr` y `fleet` aparece también `hr_fleet` sin pedirlo.
- **Actualizar arrastra hacia abajo.** `button_upgrade` añade a la lista a todos los módulos instalados que dependen del actualizado.
- **Desinstalar arrastra hacia abajo.** `button_uninstall` pone en estado `to remove` el módulo y todos los que dependen de él (`downstream_dependencies`).

Los módulos tienen un estado en `ir.module.module`: `uninstallable`, `uninstalled`, `installed`, `to upgrade`, `to remove` y `to install`. Los tres últimos son transitorios: significan «pendiente de aplicar al recargar el registro».

### `base`, `web` y `mail`

- **`base`** es «el núcleo de Odoo, necesario para toda instalación» (descripción de su manifest). El cargador lo trata como forzado (`_FORCED_MODULES = ('base',)` en `odoo/modules/loading.py`), y `button_uninstall` rechaza desinstalar los módulos forzados y los de `server_wide_modules`. Define lo que todo lo demás da por supuesto: idiomas, monedas, países, compañías, usuarios y partners, y los modelos del propio sistema de módulos (`ir.module.module`, `ir.ui.view`, `ir.model.data`...). Para los modelos de persona véase [Partner, Usuario y Empleado](Partner-Usuario-y-Empleado.md).
- **`web`** es «el núcleo del cliente web»: `'depends': ['base']` y `'auto_install': True`.
- **`mail`** se llama «Discuss» (chat, pasarela de correo, canales). Su manifest declara `depends` en `base`, `base_setup`, `bus`, `web_tour` y `html_editor`, y `'application': True`. Su descripción incluye el *chatter*, el hilo de mensajes de cada documento.

La referencia pide listar `base` en `depends` aunque siempre esté instalado, para que el módulo se actualice cuando se actualice `base`.

## Instalar, actualizar, desinstalar

Tres operaciones, cada una con una vía de interfaz y una de línea de comandos. La CLI del servidor es `odoo-bin` (en un paquete de distribución, el ejecutable se llama `odoo`) y sus opciones se documentan en la [referencia de la CLI](https://www.odoo.com/documentation/20.0/developer/reference/cli.html). Lo que sigue se verificó leyendo esa página y el código del cargador.

| Operación | Interfaz (Aplicaciones) | Línea de comandos |
|---|---|---|
| Instalar | Botón *Activar* en la tarjeta de la App | `odoo-bin -d <base> -i <módulos>` |
| Actualizar | Menú de tres puntos → *Actualizar* | `odoo-bin -d <base> -u <módulos>` (o `-u all`) |
| Desinstalar | Menú de tres puntos → *Desinstalar* | Sin opción de CLI propia (la CLI documentada no la incluye) |

`-i` y `-u` aceptan listas separadas por comas y requieren `-d`. Con `--stop-after-init` el servidor aplica el cambio y termina en lugar de quedarse sirviendo. Un ejemplo con el módulo propio que se desarrolla en la sección siguiente (no se ejecutó):

```bash
odoo-bin -d cafes_del_valle_pruebas -i sale_nota_entrega --stop-after-init
```

### Qué ocurre al instalar (`-i`)

En `load_module_graph` (`odoo/modules/loading.py`), para cada módulo en estado `to install` y en orden de dependencias:

1. Se ejecuta el `pre_init_hook`, si existe.
2. Se registran los modelos del módulo y se inicializan en la base de datos: se crean las tablas y columnas que falten.
3. Se cargan los ficheros de `data` en modo `init`, en el orden del manifest. Las vistas, acciones, menús y registros de seguridad son datos: se insertan aquí.
4. Se cargan los de `demo`, solo si la base tiene datos de demostración (según la CLI, `--without-demo` es el valor por defecto).
5. Se actualizan las traducciones de los idiomas instalados.
6. Se ejecuta el `post_init_hook`, y el módulo pasa a `installed` con su versión.

`-i` solo actúa sobre módulos en estado `uninstalled`: el cargador filtra por ese estado. Pedir `-i` de un módulo ya instalado no lo reinstala. Un nombre inexistente no da error: el cargador registra la advertencia `invalid module names, ignored: <nombres>` y continúa.

### Qué recarga y qué no recarga `-u`

`-u` repite el paso 3 anterior con el modo `update` y actualiza la información del módulo desde el manifest. La referencia de datos explica la diferencia clave ([datos XML](https://www.odoo.com/documentation/20.0/developer/reference/backend/data.html)):

| Se recarga con `-u` | No se recarga con `-u` |
|---|---|
| Los ficheros de `data` fuera de `noupdate`. | Los registros marcados `noupdate="1"`: «se crean si no existían, pero no se actualizan al actualizar el módulo». |
| El esquema de los modelos del módulo y de los que extiende. | Los `demo`, salvo que la base tenga la marca de demo activa. |
| Las vistas del módulo, que se validan al final (`_validate_module_views`). | Los registros creados a mano en la base que no vengan de un fichero del módulo. |
| Los módulos que dependen del actualizado. | Un módulo que no esté en estado `installed`: el cargador solo actualiza los instalados. |

El cambio de código Python tiene efecto al arrancar el proceso, que es lo que hace la CLI; qué ocurre exactamente con el botón *Actualizar* de la interfaz sobre un código Python ya importado **no se verificó**. Dos excepciones, ambas desaconsejadas en producción: la documentación de datos indica que `-i` ignora `noupdate` y carga siempre los datos, y `--reinit` recarga también los registros `noupdate` pero la CLI lo reserva a depuración y desarrollo («no lo uses con una base de producción»).

### Qué ocurre al desinstalar

`button_uninstall` marca el módulo y sus dependientes como `to remove`; al recargar el registro, el cargador ejecuta el `uninstall_hook` y llama a `module_uninstall`, que invoca `ir.model.data._module_data_uninstall` (`odoo/addons/base/models/ir_model.py`, rama 20.0). Ese método:

- elimina los registros que tienen un ID externo del módulo (vistas, menús, acciones, reglas, datos);
- elimina los campos que el módulo añadió, incluidos los añadidos a modelos de otros módulos, y las tablas de los modelos que el módulo definió, con los registros que contuvieran;
- **no** elimina un registro que tenga otro ID externo perteneciente a otro módulo;
- si un registro no se puede eliminar, lo deja: registra una advertencia y la lista de IDs que no pudo borrar (`ir.model.data could not be deleted`).

Por eso desinstalar no siempre devuelve la base a su estado anterior: lo que borra es lo que el módulo declaró (modelos, campos, datos con ID externo); lo que el módulo hizo por otras vías (por ejemplo, el código de un `post_init_hook` que escriba datos sin ID externo) no figura en ninguna lista del módulo y la desinstalación no lo busca. En sentido contrario, la documentación avisa de que desinstalar «borra también sus registros de la base de datos» y recomienda probar antes en una copia ([Aplicaciones y módulos](https://www.odoo.com/documentation/20.0/applications/general/apps_modules.html)). El asistente de desinstalación (`base.module.uninstall`) calcula y muestra los módulos impactados, y los modelos que se perderían: los que tienen todos sus IDs externos dentro de los módulos afectados. En la interfaz, esas listas se presentan como *Apps to Uninstall* y *Documents to Delete* (documentación en inglés).

## Un módulo propio mínimo

Para un caso del día a día: Cafés del Valle quiere una nota de entrega en cada pedido de venta. Un módulo propio que depende del módulo técnico `sale`, añade un campo con `_inherit` y lo muestra con una vista heredada. Ejemplo ilustrativo; no se ejecutó una instancia.

```
sale_nota_entrega/
├── __init__.py
├── __manifest__.py
├── models/
│   ├── __init__.py
│   └── sale_order.py
└── views/
    └── sale_order_views.xml
```

```python
# __manifest__.py
{
    "name": "Nota de entrega en pedidos",
    "version": "1.0",
    "category": "Sales/Sales",
    "depends": ["sale"],
    "data": ["views/sale_order_views.xml"],
    "license": "LGPL-3",
}
```

```python
# models/sale_order.py
from odoo import fields, models


class SaleOrder(models.Model):
    _inherit = "sale.order"

    delivery_note = fields.Text(string="Nota de entrega")
```

```xml
<!-- views/sale_order_views.xml -->
<odoo>
    <record id="view_order_form_delivery_note" model="ir.ui.view">
        <field name="name">sale.order.form.delivery.note</field>
        <field name="model">sale.order</field>
        <field name="inherit_id" ref="sale.view_order_form"/>
        <field name="arch" type="xml">
            <field name="client_order_ref" position="after">
                <field name="delivery_note"/>
            </field>
        </field>
    </record>
</odoo>
```

`sale.view_order_form` y el campo `client_order_ref` existen en `addons/sale/views/sale_order_views.xml` de la rama 20.0 (comprobado en el fichero). Al instalarlo (`-i sale_nota_entrega`), el cargador añade la columna `delivery_note` a la tabla de `sale.order` y registra la vista heredada. Un campo de modelo existente no requiere fichero de permisos: los accesos del modelo ya los define quien lo creó. El módulo no tiene `application`: es un módulo técnico, no aparecerá en el filtro por defecto de Aplicaciones.

Para generar el esqueleto base existe `odoo-bin scaffold <nombre> <destino>` ([referencia de la CLI](https://www.odoo.com/documentation/20.0/developer/reference/cli.html)).

Para recorrer los registros de un modelo en el código del módulo véase [Recordsets](Recordsets.md).

## Instalar un módulo en producción es un cambio serio

El código lo explica: instalar escribe en el esquema y en los datos, y el servidor toma bloqueos exclusivos para hacerlo. Tabla de riesgos, con la causa leída en el código o la documentación:

| Riesgo | Qué ocurre | Cómo se reduce |
|---|---|---|
| Cambios de esquema | Se crean tablas y columnas; desinstalar las borra con sus datos. | Probar en una copia, con un backup previo restaurable ([Backups y restauración](../pruebas-seguras/Backups-y-Restauracion.md)). |
| Efectos colaterales por dependencias | Instalar un módulo instala sus dependencias y los `auto_install` que quedan completos; la documentación advierte de que puede alterar los costes de la suscripción. | Duplicar la base y comparar la lista de módulos instalados antes y después ([Duplicar la base de datos](../pruebas-seguras/Duplicar-Base-de-Datos.md)). |
| Bloqueos y concurrencia | La operación desde la interfaz bloquea la tabla de módulos y `ir_cron`; si hay otra operación o una tarea programada ejecutándose, falla con «Odoo is currently processing another module operation» o «...a scheduled action». Después recarga el registro de modelos. | Hacerlo en una ventana de mantenimiento, no en hora punta. |
| Desinstalar arrastra datos | Se pierden los modelos, campos y registros del módulo y de sus dependientes. | Ensayar también la desinstalación en la copia y leer el asistente. |
| Operación sin vuelta atrás limpia | Revertir una instalación es una desinstalación, y esta no es simétrica (véase la sección anterior). | Tener un backup; la vuelta atrás fiable es restaurarlo. |
| Solo administradores | Los métodos de instalación, actualización y desinstalación se rechazan (`AccessDenied`) a quien no sea administrador, y cada llamada se registra en el log. | — |
| Código externo | Un módulo ajeno ejecuta su código con los permisos del servidor. | Revisar el origen; véase la siguiente sección. |

El entorno recomendado para ensayar es uno que no comparta conexiones con producción: [Entornos dev, staging y producción](../pruebas-seguras/Entornos-dev-staging-produccion.md).

## Community, Enterprise y módulos de terceros

| Origen | Licencia | Dónde se obtiene | Qué hay que saber |
|---|---|---|---|
| **Community** (oficial) | LGPL v3 | Repositorio público `odoo/odoo`, carpetas `odoo/addons/` y `addons/`. | La licencia está en cada manifest (`'license': 'LGPL-3'` en `sale`, `hr_fleet`...) y en la [página de licencias](https://www.odoo.com/documentation/20.0/legal/licenses.html). |
| **Enterprise** (oficial) | Odoo Enterprise Edition License v1.0 (`OEEL-1`) | Descarga con la cuenta de la suscripción (la guía de actualización lo indica así). | De pago. El paso de Community a Enterprise consiste, entre otros, en instalar el módulo `web_enterprise` y escribir el código de suscripción ([guía](https://www.odoo.com/documentation/20.0/administration/on_premise/community_to_enterprise.html)). |
| **Odoo Apps** de Odoo S.A. | Odoo Proprietary License v1.0 (`OPL-1`), salvo indicación | Odoo Apps (la licencia se compra, típicamente ahí, según la página de licencias). | Requiere licencia comprada. |
| **OCA** | La que declare cada módulo; p. ej. `auditlog` (rama 18.0 de `OCA/server-tools`) declara AGPL-3 | Repositorios `github.com/OCA`, una rama por versión de Odoo. | Ver abajo. |
| **Terceros / a medida** | La que elija el autor (la lista de valores válidos está en la referencia del manifest). | Tiendas, repositorios, desarrollo interno. | Sin garantía de mantenimiento. |

Nota sobre la página de licencias: la versión de la rama 20.0 enuncia las licencias de «Odoo 19» en sus títulos; los manifests de 20.0 leídos siguen en `LGPL-3`.

**OCA** son las siglas de *Odoo Community Association*: según su [página «About»](https://www.odoo-community.org/about) (leída el 2026-11-10), «una organización sin ánimo de lucro con sede en Suiza» que forma una comunidad en torno a Odoo y aporta «miles de módulos Odoo con licencias de código abierto». La dirección `oca.odoo-community.org` indicada para consultarla no se pudo resolver el 2026-11-10; el sitio responde en `www.odoo-community.org`. Para el flujo de aportar correcciones a módulos OCA, véase [Contribución a Odoo y a la OCA](../contribucion-a-odoo-y-oca/README.md).

Un módulo OCA no es parte de Odoo: es un paquete de terceros con proceso de revisión propio. Cada módulo se publica por rama de versión (el manifest de `auditlog` en 18.0 declara la versión `18.0.2.0.9`), de modo que al migrar de Odoo hay que esperar a que exista la rama correspondiente.

## La lista de módulos y el menú Aplicaciones

El servidor no busca módulos en disco cada vez que se abre la pantalla de Aplicaciones: guarda una lista en la tabla `ir_module_module`. Esa lista se sincroniza con el disco en dos momentos: al arrancar con `-i` o `-u` (el cargador llama a `update_list`) y al pulsar **Actualizar lista de aplicaciones**.

`update_list` recorre los módulos que hay en `addons_path`, crea los nuevos en estado `uninstalled` (o `uninstallable` si el manifest tiene `installable: False`), actualiza los metadatos de los conocidos y refresca sus dependencias y categoría. No instala nada.

Para ver el botón hay que tener el [modo desarrollador](Modo-Desarrollador.md) activo. Según la [documentación 20.0](https://www.odoo.com/documentation/20.0/applications/general/apps_modules.html), si un módulo no aparece: activar el modo desarrollador, ir a Aplicaciones → *Update Apps List* y pulsar *Update*. Las etiquetas en español, leídas en `odoo/addons/base/i18n/es.po` de 20.0: *Aplicaciones*, *Actualizar lista de aplicaciones*, *Activar*, *Desinstalar*, y tanto *Update* como *Upgrade* se traducen como *Actualizar*.

Por defecto, Aplicaciones aplica el filtro *Apps* (los módulos con `application: True`). Para ver también los técnicos como `sale` o `hr_fleet` hay que elegir el filtro **Extra** en el desplegable de filtros. El orden de las tarjetas lo da el campo `sequence` del manifest (por defecto 100; menor va antes) y las categorías, `category`.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| El módulo no aparece en Aplicaciones | La carpeta no está bajo ningún directorio de `addons_path` (véase [El fichero odoo.conf](../configuracion-parametros/El-Fichero-odoo-conf.md)); o no se actualizó la lista de aplicaciones; o el filtro *Apps* oculta un módulo sin `application: True` (el tutorial oficial lo recuerda: «quita el filtro por defecto»). |
| El módulo aparece pero no se puede instalar | `'installable': False` en el manifest: queda en estado `uninstallable` (`update_list`; el cargador registra `module <nombre>: not installable, skipped`). |
| `module <nombre>: some depends are not loaded (<lista>), skipped` en el log | Una de las dependencias del manifest no está en el grafo de módulos: falta en `addons_path`, tiene el nombre mal escrito o no es instalable (`odoo/modules/module_graph.py`). |
| En la interfaz: `You try to install module "<A>" that depends on module "<B>". But the latter module is not available in your system.` | `B` no existe en el disco del servidor (`ir_module.py`, `_state_update`): se copió `A` sin copiar sus dependencias. |
| `Unable to install module "<A>" because an external dependency is not met: <paquete>` | El manifest declara `external_dependencies` (biblioteca Python o binario) que el servidor no tiene. Hay que instalarla en el entorno de Python. |
| `-i` o `-u` no hace nada, y el log dice `invalid module names, ignored: <nombre>` | El nombre no coincide con ningún módulo conocido: error tipográfico, o falta `addons_path` / actualizar la lista. |
| La actualización falla con `Error while validating view (...)` o `Element ... cannot be located in parent view` | Una vista heredada usa un selector que ya no existe en la vista padre, normalmente porque el módulo base cambió de versión. Se corrige en la vista heredada (`ir_ui_view.py` y `template_inheritance.py`, rama 20.0). |
| Cambié un fichero de datos o una vista y `-u` no lo refleja | El registro está en `noupdate` o en un fichero ajeno al `data` del manifest. |
| `Modules "<A>" and "<B>" are incompatible.` | Uno de los módulos declara el otro en `excludes`. |
| `Odoo is currently processing another module operation.` | Otra instalación, actualización o desinstalación ya está en curso en esa base: esperar y reintentar. |

Los mensajes anteriores están citados de los ficheros indicados, de la rama 20.0 leída el 2026-11-10; pueden variar entre versiones y los de la interfaz se traducen al idioma de la persona usuaria.

## Buenas prácticas avanzadas

- **Extiende, no edites.** Cambiar un módulo oficial u OCA en su sitio se pierde en la siguiente actualización del código. El patrón es un módulo propio que depende de él y usa `_inherit` y vistas heredadas, como `hr_fleet` hace con `hr.employee`. Si un cambio se necesita en el origen, el camino es [aportarlo](../contribucion-a-odoo-y-oca/README.md).
- **Un módulo «puente» lleva `auto_install`.** Cuando la funcionalidad solo tiene sentido si dos módulos independientes coexisten, un tercer módulo que dependa de ambos y declare `auto_install` evita que ninguno de los dos conozca al otro (el ejemplo de la referencia es `sale_crm`; en el repositorio, `hr_fleet`). Con una lista en lugar de `True`, la instalación se dispara con un subconjunto de dependencias, y las demás se instalan con él.
- **Ordena `data` por dependencia entre ficheros.** Una vista que referencia una acción, o una regla que referencia un grupo, falla en la instalación si el fichero referenciado va después. La causa es el orden de la lista, no un error del XML.
- **Distingue `noupdate` de la actualización.** Los datos que el usuario final puede editar suelen ir en `noupdate="1"` para que `-u` no pise sus cambios; la contrapartida es que una corrección en el XML no llega a las bases ya instaladas. Si hace falta corregirlos, hay que hacerlo con un script de migración o a mano, no con `--reinit` en producción.
- **Prueba desinstalar, no solo instalar.** Un `uninstall_hook` limpia lo que el manifest no puede declarar (datos creados por `post_init_hook`). La referencia advierte de que los hooks son solo para cuando la preparación o limpieza es «extremadamente difícil o imposible» con la API.
- **Usa `--skip-auto-install` en el entorno de desarrollo** para comprobar que tus módulos no dependen sin saberlo de uno que se instala solo (la CLI documenta esa utilidad).

## Documentación oficial

- [Aplicaciones y módulos](https://www.odoo.com/documentation/20.0/applications/general/apps_modules.html) — instalar, actualizar y desinstalar desde la interfaz, el filtro *Extra* y el aviso de borrado de registros.
- [Manifest de módulos](https://www.odoo.com/documentation/20.0/developer/reference/backend/module.html) — todas las claves de `__manifest__.py` (`depends`, `auto_install`, `application`, hooks, `assets`).
- [Interfaz de línea de comandos](https://www.odoo.com/documentation/20.0/developer/reference/cli.html) — `-i`, `-u`, `--addons-path`, `--stop-after-init`, `scaffold`.
- [Código de `hr_fleet`](https://github.com/odoo/odoo/tree/20.0/addons/hr_fleet) y de `odoo/modules/loading.py` — lo que de verdad ocurre al cargar un módulo.

## Recursos didácticos

- [Tutorial de arquitectura del servidor, capítulo 2: una aplicación nueva](https://www.odoo.com/documentation/20.0/developer/tutorials/server_framework_101/02_newapp.html) — crea un módulo vacío, hace que aparezca en Aplicaciones y lo convierte en App.

---

*En resumen: un módulo es una carpeta con manifest que modifica la base de datos al instalarse, una App es el módulo marcado `application: True`, el orden de carga lo da `depends`, y como desinstalar no deshace limpiamente lo que instalar hizo, todo cambio de módulos se ensaya antes en una copia.*
