# Modo desarrollador

## ¿Qué es?

El modo desarrollador (*developer mode* o *debug mode*) es un estado de la sesión de Odoo que revela la capa técnica de la interfaz: el menú **Técnico** en Ajustes, un icono de insecto con herramientas de diagnóstico, los nombres internos de los campos y el acceso directo a los registros que definen vistas, acciones y filtros. No cambia datos ni configuración por sí mismo: cambia lo que se muestra y lo que se ofrece hacer.

Procedencia (2026-11-10): lo descrito se ha contrastado leyendo el código de la rama `20.0` de [github.com/odoo/odoo](https://github.com/odoo/odoo) (commit `4611da6`, 3 de noviembre de 2026) y la documentación de usuario de Odoo 20.0. No se ha ejecutado ninguna instancia de Odoo: no hay capturas ni salidas reales, y las únicas «salidas» que aparecen son literales del código (etiquetas de menú, mensajes) o el resultado de una réplica rotulada en Python.

Versiones vigentes según la documentación oficial («Standard and extended support», consultada el 2026-11-10): Odoo 20.0 (septiembre de 2026), 19.0 y 18.0 con soporte estándar; 17.0 terminó en septiembre de 2026. Donde una función cambia entre versiones, se indica.

## ¿Por qué existe?

La interfaz normal de Odoo está pensada para personas de negocio: oculta los nombres técnicos y las pantallas de configuración interna para no abrumar ni provocar accidentes. Quien administra o desarrolla necesita justo lo contrario: saber cómo se llama el campo que ve en pantalla, qué vista lo dibuja, qué acción abre la pantalla y con qué dominio. Sin un interruptor para eso, habría que leer el código de los módulos o consultar la base de datos a mano.

> Si ya conoces las herramientas de desarrollo del navegador (F12), el modo desarrollador es lo mismo para Odoo: siempre disponible, invisible hasta que se activa, y con capacidad de editar lo que inspeccionas.

## ¿Cuándo y para qué se usa?

Escenarios con la pequeña empresa de ejemplo, que vende productos y gestiona pedidos de venta (el pedido `S00042` del cliente «Cafés del Valle»):

- Una exportación o una automatización pide el **nombre técnico** del campo «Cliente» del pedido, no su etiqueta.
- Un botón no hace lo esperado y hay que ver **qué acción** abre la pantalla, sobre qué modelo y con qué dominio.
- Un campo no aparece en el formulario y hay que localizar **la vista** (y la vista heredada) que lo añade o lo oculta.
- Hay que saber **cuándo y quién** creó un registro, o si su identificador externo está marcado como `noupdate`.
- Un error de interfaz exige JavaScript legible en el navegador: modo con *assets*.

Fichas relacionadas: [Odoo](Odoo.md), [Módulos y Apps](Modulos-y-Apps.md), [Partner, Usuario y Empleado](Partner-Usuario-y-Empleado.md) y [Recordsets](Recordsets.md).

## Cómo se activa y se desactiva

### Desde Ajustes

En la aplicación **Ajustes**, al final de la página, la sección **Developer Tools** (Herramientas de desarrollador) ofrece enlaces con estas etiquetas, literales del código (`res_config_dev_tool.xml`, 20.0):

| Enlace | Qué activa |
|---|---|
| Activate the developer mode | `debug=1` |
| Activate the developer mode (with assets) | `debug=assets` |
| Activate the developer mode (with tests assets) | `debug=assets,tests` |
| Deactivate the developer mode | `debug=0` |

Cada enlace solo se muestra si procede: si el modo ya está activo, no aparece «Activate…». Todos llaman a `router.pushState({ debug: valor }, { reload: true })`: añaden `debug` a la URL y recargan el cliente web.

### Desde la URL

El parámetro `debug` funciona en cualquier pantalla. La documentación de usuario de 20.0 lo describe así:

```
https://miempresa.odoo.com/odoo?debug=1        # activar
https://miempresa.odoo.com/odoo?debug=assets   # activar, con assets sin minificar
https://miempresa.odoo.com/odoo?debug=tests    # activar, con assets de pruebas
https://miempresa.odoo.com/odoo?debug=0        # desactivar
```

El dominio es inventado; la ruta `/odoo` es la que usa la documentación de 20.0.

### Paleta de comandos y extensión

La documentación de 20.0 añade dos atajos: la paleta de comandos (`Ctrl + K` o `Cmd + K`) permite escribir `debug` para activar el modo con assets o desactivarlo (el código de `debug_providers.js` ofrece «Activate debug mode» y «Activate debug mode (with assets)»), y existe la extensión de navegador *Odoo Debug*, con un icono para alternar el modo.

### Qué ocurre en el servidor

El modo vive en la **sesión del servidor**, no en la URL. La clase `ir.http` (`addons/web/models/ir_http.py`, 20.0) lee el parámetro `debug` en cada petición y, si viene, lo guarda en `request.session.debug`:

```python
@classmethod
def _handle_debug(cls):
    debug = request.httprequest.args.get('debug')
    if debug is not None:
        request.session.debug = ','.join(
                 mode if mode in request.env['ir.http']._get_debug_modes()
            else '1' if str2bool(mode, mode)
            else ''
            for mode in (debug or '').split(',')
        )
```

`_get_debug_modes()` devuelve `{'', '1', 'assets', 'tests'}`. Una petición sin parámetro `debug` no toca la sesión, así que el modo persiste entre pantallas hasta que alguna petición lo cambie. En la rama 19.0 hay una prueba que lo comprueba (`odoo/addons/test_http/tests/test_session.py`, `test_session00_debug_mode`): sin parámetro la sesión sigue en `''`; con `?debug=1` pasa a `'1'`; una petición posterior sin parámetro la deja en `'1'`; con `?debug=` vuelve a `''`.

Para ver cómo se normaliza el valor, esta réplica en Python de esa lógica (con `str2bool` de `odoo/tools/misc.py` reducida a su lógica) se ejecutó en local; es una demostración de la lógica, no la salida de Odoo:

```python
for v in ['1', '0', '', 'assets', 'tests', 'assets,tests', 'on', 'off', 'true', 'assets, tests']:
    print(repr(v), '->', repr(handle_debug(v)))
```

```
'1' -> '1'
'0' -> ''
'' -> ''
'assets' -> 'assets'
'tests' -> 'tests'
'assets,tests' -> 'assets,tests'
'on' -> '1'
'off' -> ''
'true' -> '1'
'assets, tests' -> 'assets,1'
```

Tres consecuencias que se derivan de ese código:

- Cualquier valor «verdadero» (`1`, `on`, `true`, cualquier texto desconocido) equivale al modo simple (`'1'`); cualquier valor «falso» (`0`, `off`, vacío) lo desactiva.
- Los modos se combinan separándolos por comas **sin espacios**: la cadena `assets, tests` (con espacio, como aparece en el comentario del propio código) se interpreta como `assets,1`, porque `' tests'` no está en la lista permitida.
- `?debug=tests` por sí solo guarda `'tests'` en la sesión: es un valor no vacío, por lo que el modo está activo, pero sin `assets`. Lo habitual es `assets,tests`, que es lo que activan el enlace de Ajustes y la opción «Activate Test Mode» del menú de debug.

En el cliente, el valor llega a la página como `odoo.debug` (la plantilla `web.layout` de `addons/web/views/webclient_templates.xml` escribe `debug: "<t t-out="debug"/>"`) y el cliente lo consulta con `odoo.debug` o con el plugin `DebugModePlugin` (`isActive()`, `isActive('assets')`).

## Qué revela

### El icono del insecto

Con el modo activo, la barra superior muestra un icono de insecto (en 20.0 se dibuja con el icono `bug_report`, `aria-label="Open developer tools"`; en 19.0 era `fa-bug`). Abre un menú cuyo contenido **depende de la pantalla** (la documentación lo dice así: «las opciones disponibles dependen de dónde se accede al menú»). Las opciones se agrupan en secciones con estas etiquetas literales: *Record*, *Records*, *User Interface*, *Security*, *Tours & Testing* y *Tools*.

Las opciones que hay en el código de 20.0 (`views/debug_items.js`, `webclient/actions/debug_items.js`, `core/debug/debug_menu_items.js`):

| Opción del menú | Qué ofrece |
|---|---|
| **Metadata** (en un formulario con registro guardado) | Diálogo «View Metadata»: id, identificador externo (*XML ID*), si está marcado `noupdate`, quién lo creó y lo modificó por última vez y cuándo. Permite alternar `noupdate` y crear un identificador externo. |
| **Data** | Los valores crudos del registro (sin campos binarios), en un diálogo. |
| **View: Form** (o List, Kanban…) | Abre el registro `ir.ui.view` de la vista actual para editarlo. Solo aparece si el usuario tiene permiso de escritura sobre `ir.ui.view`. |
| **SearchView** | Lo mismo para la vista de búsqueda. |
| **Computed Arch** | Muestra la arquitectura XML resultante de aplicar todas las vistas heredadas (en el código, `rawArch` del entorno de la vista). |
| **Action** | Abre el registro de la acción de ventana que muestra la pantalla; ahí se ven su dominio, contexto y vistas. |
| **Fields** | Lista los registros `ir.model.fields` del modelo de la acción. |
| **Model: …** | Abre el registro `ir.model` del modelo. |
| **Filters** | Gestiona los filtros guardados (`ir.filters`) de ese modelo. |
| **Access Rights** / **Record Rules** | Atajos a los permisos de acceso y reglas de registro del modelo (requieren permiso de lectura sobre ellos). |
| **Set Default Values**, **Attachments** | Valores por defecto de campos y adjuntos del registro. |
| **Regenerate Assets** | Borra los *bundles* de assets generados (`ir.attachment.regenerate_assets_bundles`) y recarga. |
| **Become Superuser** | Solo para administradores; abre `/web/become`. |
| **Disable RPC Cache** / **Enable RPC Cache** | Desactiva o activa la caché de llamadas RPC del cliente (presente en 20.0; en 19.0 no existe). |
| **Activate Test Mode** | Recarga con `debug=assets,tests`. |
| **Leave Debug Mode** | Recarga con `debug=0`. |

Las etiquetas son las del código en inglés; en una instalación con otro idioma se traducen. La disponibilidad exacta de cada opción en cada vista concreta no se ha comprobado ejecutándola.

### El nombre técnico de un campo

Con el modo activo, el *tooltip* de un campo (al pasar el ratón sobre su etiqueta) añade una lista técnica. La plantilla `field_tooltip.xml` de 20.0 incluye, entre otras, las líneas **Label:** (la etiqueta visible) y **Field:** (el nombre técnico del campo). La misma plantilla incluye, según el campo, **Model:**, **Type:**, **Widget:**, **Domain:**, **Context:**, **Required:**, **Readonly:**, **Relation:** y **Selection:**, entre otras. Sin el modo activo, `debug` es falso y esa lista no se pinta.

### El menú Técnico

En Ajustes aparece el menú **Technical** («Técnico»; es `base.menu_custom` en `odoo/addons/base/views/base_menus.xml`), con submenús como *Email*, *Actions*, *User Interface* o *Database Structure*. Desde ahí se llega a las mismas piezas que el icono del insecto, pero navegando por listas: todas las vistas (`ir.ui.view`), todas las acciones, todos los filtros guardados, los identificadores externos (`ir.model.data`) y la estructura de modelos y campos. Es la vía para tocar una vista **heredada** concreta, ya que «View: Form» abre la vista principal de la pantalla, mientras que las que la extienden se encuentran en la lista de vistas.

### Assets sin minificar

Un *asset* es un fichero JavaScript o CSS que el cliente web carga; Odoo los agrupa en *bundles* (conjuntos de ficheros) que sirve concatenados y minificados. Con `debug=assets`:

- La plantilla de QWeb recibe el valor de la sesión (`values.get("debug")`) y `_get_asset_links` (`ir_qweb.py`, 20.0) comprueba `debug and 'assets' in debug`: si es así, genera los *bundles* en modo depuración (`debug_assets=True`).
- En `AssetsBundle` ese modo se traduce en URLs con el identificador `debug` en lugar del hash de versión y en extensión `js`/`css` en lugar de `min.js`/`min.css` (`assetsbundle.py`, líneas 146-147 en 20.0).
- Los ficheros estáticos se sirven con `max_age=0` si `'assets' in request.session.debug` (`odoo/http/router.py`, 20.0), es decir, sin caché del navegador.
- La documentación de `_get_asset_nodes` dice que, con `debug=assets`, los *bundles* se regeneran cuando cambia un fichero que los compone.

Resultado práctico: en las herramientas del navegador, los errores y los puntos de ruptura apuntan a ficheros legibles en lugar de a un *bundle* comprimido. Es el modo que se usa para depurar JavaScript.

### Assets de pruebas

Con `tests` en la sesión, la plantilla `web.conditional_assets_tests` (`webclient_templates.xml`) carga el *bundle* `web.assets_tests`, el que contiene los *tours* (recorridos guiados automatizados de la interfaz usados como prueba). Solo es relevante para quien escribe o ejecuta pruebas de interfaz; el resto de personas no necesita este modo.

## Qué NO hace, y riesgos

- **No es un entorno de pruebas.** Sigues sobre la misma base de datos; todo lo que guardes es real. La preparación de entornos desechables está en [Pruebas seguras](../pruebas-seguras/README.md).
- **No bloquea nada ni protege.** Solo hace visibles más opciones, y la mayoría de ellas editan registros del sistema (vistas, acciones, filtros, identificadores externos).
- **No versiona los cambios.** Una vista editada desde el menú queda guardada en la base de datos, no en el código de ningún módulo. No hay historial en git, no pasa por revisión y no viaja a otros entornos.
- **Puede perderlos al actualizar el módulo.** La documentación de desarrollo de 20.0 (`developer/reference/backend/data.html`) explica que los ficheros de datos se cargan en instalación y se **recargan en cada actualización** (`-u`), salvo la parte marcada `noupdate`. Una vista definida en el XML de un módulo es un registro de datos de ese tipo; por tanto, su edición manual se expone a ser sobrescrita cuando el módulo se actualice. La marca `noupdate` de un registro se ve y se alterna en el diálogo **Metadata**. (Que una vista concreta se sobrescriba depende de cómo la declare su módulo; no se ha comprobado con una actualización real.)
- **No arregla el origen.** Si un campo falta o una vista está mal, el arreglo correcto vive en el módulo (una vista heredada en código), no en una edición manual en producción.

## Flujo de trabajo útil

Tabla de decisión según el problema:

| Problema | Herramienta del modo desarrollador |
|---|---|
| ¿Cómo se llama técnicamente este campo? | Tooltip del campo: línea **Field:** |
| ¿De qué modelo es esta pantalla? | Menú del insecto → **Model: …**; o **Action** y leer `res_model` |
| ¿Qué dominio y contexto tiene esta pantalla? | Menú del insecto → **Action** |
| ¿Qué campos tiene este modelo? | Menú del insecto → **Fields** |
| ¿Por qué este campo no se ve / está duplicado? | **Computed Arch** (XML final) y luego **Settings → Technical → User Interface** para localizar la vista heredada |
| ¿Cuál es el identificador externo de este registro? | **Metadata** → *XML ID* |
| ¿Quién creó este registro y cuándo? | **Metadata** → creador y fecha |
| ¿Qué filtros guardados existen para este modelo? | **Filters** |
| ¿Es un bug o un problema de permisos? | **Become Superuser** (solo diagnóstico) y repetir la acción |
| Error de JavaScript ilegible | `?debug=assets` y repetir |
| Los cambios de JavaScript/CSS no se reflejan | **Regenerate Assets** |

### Encontrar el nombre técnico de un campo

En un pedido de venta (por ejemplo `S00042`), con el modo activo se pasa el ratón sobre la etiqueta del campo «Cliente». El *tooltip* muestra la línea **Field:** con el nombre técnico (lo que aparezca ahí es lo que se usa en dominios, informes o código; en el sistema de la empresa de ejemplo se esperaría un campo `partner_id`, pero es lo que muestre cada instalación lo que vale). El mismo *tooltip* trae la línea **Type:** y, para un campo relacional, **Relation:**.

### Ver la vista que define un campo

1. En el formulario, menú del insecto → **Computed Arch**: muestra el XML resultante tras aplicar todas las vistas heredadas. Sirve para confirmar si el campo está en la vista final.
2. Si falta o sobra algo, hay que saber qué vista lo provoca: **Settings → Technical → User Interface**, la lista de vistas, filtrando por el modelo; las vistas heredadas dicen de cuál heredan.
3. Antes de editar, **Metadata** del registro de la vista dice si viene de un módulo (tiene *XML ID*) o fue creada a mano. Si viene de un módulo, el cambio duradero se hace en el módulo.

### Comprobar el dominio de una acción

Menú del insecto → **Action**: se abre el registro de la acción de ventana de esa pantalla (`action.type` y `action.id`, que son los que pasa el código a `editModelDebug`). Ahí se leen el modelo (`res_model`), el dominio, el contexto y las vistas. El dominio sigue el formato de listas de tuplas de Odoo y es el punto de partida para entender por qué un registro «no aparece» en una lista.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| No aparece el menú **Technical** en Ajustes | El modo no está activo en esta sesión: el menú tiene `groups="base.group_no_one"` (`base_menus.xml`) y `has_group('base.group_no_one')` solo devuelve verdadero si la sesión está en modo debug (`res_users.py`: `result and bool(request and request.session.debug)`). Revisar que la URL o Ajustes lo hayan activado. |
| Con el modo activo, sigue sin aparecer el menú **Technical** | Falta acceso a **Ajustes**: el menú raíz exige `base.group_erp_manager` o `base.group_system` en 20.0 (`menu_administration`). Además, en 20.0 `ir.ui.menu._visible_menu_ids` descarta `base.group_no_one` para quien no es un usuario «regular» (un usuario ligero, *light*, no tiene menú técnico). |
| El icono del insecto no aparece | El modo no está activo (el menú solo se monta si `debugMode.isActive()` es verdadero en `webclient.js`, 20.0) o la página no se recargó tras activarlo: el cambio exige recarga (`reload: true`). |
| Tras activarlo con `?debug=assets, tests` (con espacio) no hay assets sin minificar | El valor se normaliza a `assets,1` (ver réplica arriba): ` tests` con el espacio inicial no es un modo válido. Usar `assets,tests` sin espacios. |
| La opción **View: Form** no aparece en el menú | El usuario no tiene permiso de escritura sobre `ir.ui.view` (`canEditView` en `debug_context.js`). |
| Una vista editada vuelve a su estado anterior tras actualizar un módulo | El registro de la vista pertenece a datos del módulo que se recargan en la actualización (ver «Qué NO hace»). |
| El modo sigue activo en pantallas sin `?debug` en la URL | Es lo esperado: vive en la sesión. Se apaga con `?debug=0`, con «Deactivate the developer mode» o con «Leave Debug Mode». |
| El menú del insecto muestra opciones distintas según la pantalla | Es lo esperado: las opciones dependen de la vista y de la acción actuales. |

## Buenas prácticas avanzadas

- **Activa el modo en la sesión y apágalo al acabar.** El modo se guarda en la sesión del servidor, de modo que un `?debug=1` compartido en un enlace, o una extensión de navegador que lo mantenga siempre encendido, convierte el trabajo diario en producción en un trabajo con las vistas editables. `?debug=0` lo cierra.
- **`Computed Arch` antes que la vista individual.** El XML de una sola vista no dice qué ve finalmente la persona: la vista final resulta de aplicar en orden todas las heredadas. Diagnosticar desde la arquitectura calculada evita editar la vista equivocada.
- **Mira `noupdate` en Metadata antes de tocar un registro de módulo.** Dice si el registro vuelve a escribirse en cada actualización. Los cambios que deben perdurar pertenecen al código del módulo.
- **Usa `Become Superuser` solo como prueba de diagnóstico.** Si una acción funciona como superusuario y falla con la cuenta normal, el problema son los permisos, no un bug. Todo lo editado así se salta las reglas de acceso; vuelve a tu usuario al terminar.
- **`Regenerate Assets` cuando cambias JavaScript o CSS y no se refleja.** Borra los *bundles* generados (`ir.attachment`) y recarga. Con `debug=assets` los *bundles* se regeneran por sí solos cuando cambia un fichero, así que el síntoma indica normalmente que estás en modo `1` sin `assets`.
- **Combina modos sin espacios.** `assets,tests` es válido; `assets, tests` no, por la normalización que hace `_handle_debug`.

## Documentación oficial

- [Developer mode (debug mode) — Odoo 20.0](https://www.odoo.com/documentation/20.0/applications/general/developer_mode.html) — activación (Ajustes, URL, paleta de comandos, extensión) y panorama del menú de herramientas.
- [`addons/web/models/ir_http.py` en la rama 20.0](https://github.com/odoo/odoo/blob/20.0/addons/web/models/ir_http.py) — dónde se lee `?debug=` y qué valores acepta; lectura corta y es la fuente exacta.
- [`addons/web/static/src/views/debug_items.js` en la rama 20.0](https://github.com/odoo/odoo/blob/20.0/addons/web/static/src/views/debug_items.js) — lo que ofrece el menú del insecto en vistas (Metadata, edición de vistas, arquitectura calculada).
- [Data files — Odoo 20.0](https://www.odoo.com/documentation/20.0/developer/reference/backend/data.html) — la explicación de `noupdate` y de qué se recarga al actualizar un módulo.

---

*En resumen: el modo desarrollador es un estado de la sesión (`?debug=1`, `assets` o `tests`) que muestra la capa técnica de Odoo y ofrece editarla; sirve para encontrar el nombre de un campo, la vista o el dominio, pero lo que se edita con él no queda versionado y puede perderse al actualizar el módulo, por lo que se activa para diagnosticar y se apaga al terminar.*
