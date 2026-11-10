# Search Panel

## ¿Qué es?

El *search panel* es un panel lateral que Odoo muestra a la izquierda de las vistas de varios registros (lista y kanban por defecto) y que permite filtrar por los valores de uno o varios campos con un clic, sin escribir nada. Se declara con la etiqueta `<searchpanel>` dentro de la [vista de búsqueda](Vista-de-Busqueda.md) del modelo. Cada campo del panel es una *sección*: de tipo **categoría** (una sola selección, como navegar por carpetas) o de tipo **filtro** (varias casillas combinables).

Referencias de código y documentación: rama estable `20.0` de `github.com/odoo/odoo` (HEAD `4611da65a7`, leído el 2026-11-10) y documentación 20.0. La [página de versiones soportadas](https://www.odoo.com/documentation/20.0/administration/standard_extended_support.html) lista la 20.0, la 19.0 y la 18.0 con soporte estándar. No se ejecutó ninguna instancia de Odoo: el comportamiento descrito procede del código y la documentación leídos, citados en cada punto, y las afirmaciones sobre rendimiento son razonamientos a partir del código, sin medir.

## ¿Por qué existe?

La barra de búsqueda exige saber qué escribir. Cuando un listado se recorre siempre por una dimensión conocida —el estado de un pedido, el equipo comercial, el departamento de una empleada como Ana Ruiz— conviene ver todas las opciones a la vez y pinchar en una. El search panel convierte un campo `Many2one` o `Selection` en esa navegación lateral y, de paso, enseña cuántos registros hay en cada valor.

> Si has usado el filtro lateral de una tienda online (marca, talla, color), el search panel es lo mismo: un filtro por facetas. Cada faceta es una consulta `GROUP BY` sobre el campo, con el recuento al lado.

## ¿Cuándo y para qué se usa?

- **Recorrer un listado por una dimensión de baja cardinalidad**: pedidos de venta de Cafés del Valle por estado (`Quotation`, `Sales Order`...) o por equipo comercial.
- **Ver de un vistazo cuántos registros hay en cada valor**, con `enable_counters`.
- **Navegar jerarquías**: departamentos, categorías de producto o cualquier modelo con campo padre.
- **No** sirve en formularios (muestran un solo registro) ni como sustituto de la búsqueda por texto: convive con la barra de búsqueda.

## Un primer panel: dónde se declara

El panel vive dentro de `<search>` y solo admite hijos `<field>` ([vista de referencia, `searchpanel`](https://www.odoo.com/documentation/20.0/developer/reference/user_interface/view_architectures.html); el esquema `odoo/addons/base/rng/search_view.rng` lo define con los atributos opcionales `view_types` y `class` y cero o más `field`). Un ejemplo real de la rama 20.0, en `addons/hr/views/hr_employee_views.xml` (vista de búsqueda de empleados):

```xml
<search string="Employees">
    <field name="name" string="Employee"
        filter_domain="['|', ('work_email', 'ilike', self), ('name', 'ilike', self)]"/>
    <searchpanel view_types="kanban,list,graph,pivot,hierarchy">
        <field name="company_id" groups="base.group_multi_company" icon="business" enable_counters="1"/>
        <field name="department_id" icon="group" icon_class="oi-filled" enable_counters="1"/>
    </searchpanel>
    <!-- ... más campos y filtros ... -->
</search>
```

Qué se ve: a la izquierda de la lista de empleados, dos secciones —compañía (solo para quien pertenece al grupo multicompañía) y departamento— con un contador junto a cada valor y la opción «All» (el literal que añade el parser, `ALL` en `search_arch_parser.js`) para quitar la selección. Los campos que no son `<field>` dentro del panel se ignoran: el parser recorre los hijos y salta cualquier nodo que no sea `field` (`visitSearchPanel`, `search_arch_parser.js`).

### En qué vistas aparece

El atributo `view_types` del `<searchpanel>` es una lista separada por comas de tipos de vista. Si no se indica, el parser usa `["kanban", "list"]` (`DEFAULT_VIEWS_WITH_SEARCH_PANEL`). El panel solo se muestra si hay secciones y el tipo de la vista activa figura en esa lista (`_getDisplay` en `search_model.js`). Con el ejemplo anterior el panel también aparece en `graph`, `pivot` y `hierarchy`; sin `view_types`, solo en lista y kanban, y nunca en un formulario.

## Categoría frente a filtro: `select="one"` y `select="multi"`

El atributo `select` decide el tipo de sección. En el parser, `select="multi"` crea un filtro; cualquier otro valor, incluida la ausencia del atributo, crea una categoría.

| | Categoría (`select="one"`, por defecto) | Filtro (`select="multi"`) |
|---|---|---|
| Selección | como máximo un valor (o «All») | varias casillas |
| Tipos de campo | `many2one`, `selection` (y `many2many` aceptado por el servidor) | `many2one`, `many2many`, `selection` |
| Dominio que genera | `campo = valor`, o `campo child_of valor` si el modelo relacionado es jerárquico | `campo in [valores marcados]` |
| Icono por defecto | `folder` | `filter_alt` |
| Atributos propios | `hierarchize`, `depth` | `domain`, `groupby` |

La tabla sale del parser (`search_arch_parser.js`), de `_getCategoryDomain` y `_getFilterDomain` (`search_model.js`) y de `search_panel_select_range` y `search_panel_select_multi_range` (`addons/web/models/models.py`). La documentación 20.0 menciona `many2one` y `selection` para `one`; el código del servidor acepta además `many2many` en categorías (`supported_types = ['many2one', 'selection', 'many2many']`). Lo documentado es lo seguro.

Cómo se combinan: las condiciones de las categorías y las de los filtros se unen con **Y**. Dentro de un mismo filtro, los valores marcados forman un `in` (equivale a **O** entre ellos). Dos filtros distintos se unen con **Y** (`_getSearchPanelDomain` junta `_getCategoryDomain` y `_getFilterDomain`).

## Un ejemplo completo sobre `sale.order`

El repositorio oficial no incluye un panel sobre `sale.order` en la rama 20.0 (comprobado en `addons/sale/views/sale_order_views.xml`: no contiene `<searchpanel>`). Lo que sigue es un ejemplo **adaptado**, no copiado: extiende la vista de búsqueda `sale.view_sales_order_filter` (definida en ese mismo fichero, y de la que heredan las vistas de búsqueda de presupuestos y pedidos) y usa campos que existen en `addons/sale/models/sale_order.py`: `state` (`Selection`, con valores `draft`, `sent`, `sale`, `cancel`), `team_id` (`Many2one` a `crm.team`, etiqueta «Sales Team», almacenado) y `company_id`.

```xml
<odoo>
    <record id="view_sales_order_filter_searchpanel" model="ir.ui.view">
        <field name="name">sale.order.search.searchpanel</field>
        <field name="model">sale.order</field>
        <field name="inherit_id" ref="sale.view_sales_order_filter"/>
        <field name="arch" type="xml">
            <xpath expr="//search" position="inside">
                <searchpanel>
                    <field name="team_id" icon="group" enable_counters="1"/>
                    <field name="state" select="multi" enable_counters="1"/>
                </searchpanel>
            </xpath>
        </field>
    </record>
</odoo>
```

El fichero se declara en la clave `data` del `__manifest__.py` de un módulo propio que dependa de `sale` (véase [Módulos y Apps](../fundamentos/Modulos-y-Apps.md)).

Qué se ve, deducido del código (no se ejecutó): una sección «Sales Team» con una entrada «All» y un equipo por cada valor presente en los pedidos visibles, cada uno con su contador; debajo, una sección «Status» con una casilla por estado presente (`Quotation`, `Sales Order`...) y su contador. Marcar «Sales Order» y elegir un equipo deja los pedidos confirmados de ese equipo.

La sección `state` no declara `icon`: se usa `filter_alt`. El `string` de cada sección, si falta, es el `string` del campo del modelo (`attrs.string || this.fields[attrs.name].string` en el parser).

## Atributos de `<field>` dentro del panel

Fuentes: el esquema `odoo/addons/base/rng/common.rng` (atributos que admite un `field`), el parser `search_arch_parser.js` (los que lee el cliente) y la documentación 20.0.

| Atributo | Efecto | Observaciones |
|---|---|---|
| `name` | campo del modelo sobre el que filtrar | obligatorio |
| `string` | etiqueta de la sección | por defecto, el `string` del campo |
| `select` | `one` (categoría, por defecto) o `multi` (filtro) | ver la sección anterior |
| `icon` | icono de la sección | el cliente lo pinta como `data-icon` de un elemento `oi`; los ejemplos de la rama usan nombres como `group` o `filter_alt` |
| `icon_class` | clase CSS del icono | p. ej. `oi-filled`; el parser lo lee y el esquema lo admite |
| `color` | color CSS del icono | se aplica como `style="color: ..."` |
| `enable_counters` | muestra el recuento de registros por valor | el parser lo lee en ambos tipos; por defecto desactivado |
| `expand` | muestra también los valores sin registros | por defecto desactivado |
| `limit` | máximo de valores a traer | por defecto `200`; `0` o `false` desactiva el límite |
| `hierarchize` | (categoría) anida los hijos bajo su padre | por defecto activado |
| `depth` | (categoría) niveles de la jerarquía que se despliegan al abrir | por defecto `0` |
| `domain` | (filtro) condición que deben cumplir los valores ofrecidos | por defecto `[]`; puede usar el valor de las categorías activas |
| `groupby` | (filtro) campo del modelo relacionado por el que agrupar las casillas | lo lee el parser y lo usa el cliente; la documentación 20.0 no lo lista |
| `groups` | grupos de usuarios a quienes se muestra la sección | documentado; el ejemplo de empleados lo usa |
| `invisible` | con `1` o `True`, el parser descarta la sección | `visitSearchPanel` |

Otros hechos verificados en el código:

- **`domain` solo se envía en filtros.** El cliente evalúa el `domain` de cada filtro con el valor activo de cada categoría como contexto (`_fetchFilters` construye `evalContext` con `category.activeValueId`). La documentación 20.0 lo ilustra con `department_id` como categoría y un filtro sobre `manager_id` cuyo dominio usa `department_id`. Para categorías, el cliente no envía `comodel_domain`.
- **`groupby` agrupa las casillas de un filtro.** El servidor devuelve para cada valor `group_id` y `group_name`, leyendo ese campo del modelo relacionado (`search_panel_select_multi_range`, parámetro `group_by`), y el cliente los pinta como grupos (`_createFilterTree`). Solo se lee en la rama de filtro del parser: en una categoría no tiene efecto.
- **`limit="false"` quita el límite.** Ejemplo real en `addons/account/views/account_move_views.xml` (rama 20.0): `<field name="account_root_id" icon="filter_alt" icon_class="oi-filled" groupby="account_id" limit="false"/>`. Esa línea no lleva `select`, por lo que el parser la trata como categoría y su `groupby` no se aplica (no verificado si otro código lo aprovecha).
- **`hierarchize` solo actúa si el modelo relacionado tiene campo padre.** El servidor comprueba `Comodel._parent_name in Comodel._fields`; si no, desactiva la jerarquía (`search_panel_select_range`).
- **Un campo `many2one` jerárquico filtra con `child_of`**: al elegir un departamento padre, entran también los registros de sus hijos (`_getCategoryDomain`).

## De dónde salen los datos: dos métodos del modelo

El cliente no consulta tablas directamente: llama por RPC a dos métodos de `models` definidos en `addons/web/models/models.py` (clase `Base`, que hace `_inherit = 'base'`, de modo que existen en todos los modelos):

- `search_panel_select_range(field_name, **kwargs)` para categorías. Devuelve `{'parent_field': ..., 'values': [...]}`.
- `search_panel_select_multi_range(field_name, **kwargs)` para filtros. Devuelve `{'values': [...]}`.

Cada valor es un diccionario con `id`, `display_name` y, si hay contadores, `__count`. Los parámetros que envía el cliente (`_fetchCategories` y `_fetchFilters` en `search_model.js`): `search_domain` (la búsqueda actual sin el panel), `category_domain`, `filter_domain`, `enable_counters`, `expand`, `limit`, y según el tipo `hierarchize`, `comodel_domain`, `group_by` y `group_domain`.

El comportamiento del servidor, del código:

1. **Valores ofrecidos.** Sin `expand`, solo los que aparecen en algún registro del `search_domain`: una consulta de agrupación (`formatted_read_group`) sobre el campo, ignorando registros con el campo vacío (`_search_panel_domain_image`). Con `expand`, todos los valores del modelo relacionado (o de la selección).
2. **Contadores.** Se calculan sobre el `search_domain` más las selecciones del resto de secciones (`category_domain` y `filter_domain`). Cuando esas selecciones no están vacías, el servidor ejecuta dos agrupaciones: una para los valores y otra para los contadores (`_search_panel_field_image`).
3. **Jerarquía.** Si `hierarchize` aplica, se completan los ancestros de los valores presentes con `parent_of` y los contadores de un padre incluyen los de sus hijos (`_search_panel_global_counters`).
4. **Selection.** Para campos `Selection`, la lista sale de `fields_get`; con `expand` aparecen todas las opciones, y sin él solo las presentes en los datos (`_search_panel_selection_range`).

## Cómo se combina con la barra de búsqueda y con el dominio de la acción

La consulta de cada sección usa como `search_domain` el resultado de `_getDomain({ withSearchPanel: false })`: el dominio global (el de la acción), más los filtros, agrupaciones y búsquedas de texto activos en la barra, y sin las selecciones del propio panel. Consecuencias:

- **Los valores ofrecidos respetan la acción y la búsqueda.** Si la acción ya restringe a pedidos confirmados, el panel no ofrece `Cancelled`, salvo que se use `expand`.
- **Las selecciones del panel se suman con Y al dominio final** (`_getDomain` añade `_getSearchPanelDomain` cuando el panel está visible): barra de búsqueda, acción y panel se intersectan. Lo que ofrece el panel no se ve afectado por sus propias selecciones, solo por los contadores.
- **Cuándo se recargan las secciones** (`_reloadSections`): cuando cambia el dominio de búsqueda, se recargan las secciones sin `expand`; las secciones con `enable_counters` se recargan siempre. Si el panel no está visible, la recarga queda pendiente hasta que lo esté.
- **Contadores y filtros con `domain` son incompatibles.** Si hay una categoría con contadores y algún filtro con `domain` distinto de `[]`, el parser desactiva los contadores de todas las categorías y escribe un aviso en consola (`"Warning: categories with counters are incompatible with filters having a domain attribute."`, `search_arch_parser.js`).

Los dominios de la acción y de las vistas se explican en [Dominios](Dominios.md); los que se calculan en tiempo de ejecución, en [Dominios dinámicos](Dominios-Dinamicos.md). La barra de búsqueda y sus filtros, en [Vista de búsqueda](Vista-de-Busqueda.md).

### Valores por defecto

El contexto de la acción admite `searchpanel_default_<campo>` para preseleccionar una categoría (`_extractSearchDefaultsFromGlobalContext` en `search_model.js` separa las claves con ese prefijo; en categorías el valor pasa a ser `activeValueId`, y en filtros el valor es una lista de ids que se marcan al cargar). Ejemplo adaptado, sin verificar en ejecución:

```xml
<field name="context">{'searchpanel_default_team_id': 1, 'searchpanel_default_state': ['sale']}</field>
```

Aquí `team_id` sería una categoría y `state` un filtro con valor inicial `sale`; el segundo no se verificó para campos `Selection` en filtros.

## Rendimiento y límites

Razonamiento a partir del código; no se midió nada.

- **Cada sección es, como mínimo, una consulta de agrupación** sobre el modelo, y se vuelve a lanzar cuando cambia la búsqueda. Con varias secciones, son varias consultas en cada recarga (`_fetchCategories` y `_fetchFilters` lanzan una llamada RPC por sección, en paralelo dentro de su grupo).
- **Un contador en una categoría `many2one` no añade consulta propia** cuando no hay otras selecciones; si las hay, añade una segunda agrupación (ver más arriba).
- **El filtro `many2many` con contadores es el caso caro.** El servidor ejecuta un `search_count` por cada valor del modelo relacionado (`search_panel_select_multi_range`, rama `many2many` con `enable_counters`). Con los 200 valores por defecto del límite, hasta 200 consultas por recarga.
- **La jerarquía añade una lectura del modelo relacionado** (`search_read`), porque hay que completar los ancestros.
- **`expand`** obliga a leer todo el modelo relacionado, no solo los valores presentes.
- **El límite protege la interfaz.** Con `limit` (200 por defecto), si el número de valores alcanza el límite, el servidor responde `{'error_msg': 'Too many items to display.'}` (constante `SEARCH_PANEL_ERROR_MESSAGE`) y el cliente muestra la sección vacía con ese mensaje en un aviso (`search_panel.xml`, `t-if="section.errorMsg"`). La documentación 20.0 dice lo mismo y añade que `0` quita el límite.
- La documentación 20.0 recomienda, como alternativa a `enable_counters` para problemas de rendimiento, sobrescribir `search_panel_select_range` y `search_panel_select_multi_range`.

Tipos que no admite: el servidor lanza `UserError` si el campo no es `many2one`, `selection` o `many2many` (en el código, el mensaje parametrizado es `Only types %(supported_types)s are supported for category (found type %(field_type)s)`; para filtros, el equivalente con `filter`). Además, el panel agrupa por la base de datos: un campo no almacenado (calculado sin `store=True`) no puede agruparse; no se comprobó qué error exacto devuelve en ese caso.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| El panel no aparece | El tipo de vista activa no está en `view_types` (por defecto solo `kanban` y `list`); el panel no se escribió dentro de la vista de búsqueda que usa la acción (comprobar el `search_view_id` de la acción); el `<searchpanel>` vive en una vista heredada que no se aplica; o todas las secciones tienen `invisible="1"` o `groups` que excluyen a quien mira |
| El panel aparece pero una sección está vacía con «Too many items to display.» | El campo alcanza `limit` valores (200 por defecto); subir `limit`, ponerlo a `0` o elegir otra dimensión |
| Una categoría no despliega los hijos | El modelo relacionado no tiene campo padre (`_parent_name`), o `hierarchize="0"` |
| Los contadores de las categorías desaparecen | Hay un filtro del mismo panel con `domain` distinto de `[]`: el parser los desactiva y avisa en consola |
| `UserError` sobre tipos admitidos | El campo no es `many2one`, `selection` ni `many2many` (p. ej. un `Char` o un `Integer`) |
| Falta un valor que sí existe en el modelo relacionado | Sin `expand`, solo salen los valores presentes en los registros que cumplen la búsqueda y la acción actuales |
| `groupby` no agrupa | Se puso en un campo de tipo categoría (sin `select="multi"`) |

## Buenas prácticas avanzadas

- **Reserva el panel para campos de baja cardinalidad.** El límite de 200 existe porque el panel pinta todos los valores; un campo con casi un valor por registro (cliente, referencia) agota el límite y llena la pantalla.
- **Piensa en el coste de cada contador antes de activarlo.** Una categoría `many2one` o un `selection` con contadores es una agrupación; un filtro `many2many` con contadores es una consulta por valor. Activa `enable_counters` solo donde el número cambia decisiones.
- **Ajusta `expand` según lo que se quiera enseñar.** Sin `expand`, las secciones solo ofrecen valores con datos y se recargan al cambiar la búsqueda; con `expand`, la lista de valores es estable pero obliga a leer todo el modelo relacionado.
- **Usa `domain` en filtros para que dependan de una categoría**, como en el ejemplo de la documentación (gestores de un departamento): pero recuerda que invalida los contadores de las categorías del mismo panel.
- **Fíjate en `view_types`.** Quien añade el panel a un modelo con vistas `graph` o `pivot` lo ve solo en lista y kanban si no lo declara; el módulo de empleados lo extiende explícitamente.
- **Prefiere heredar la vista de búsqueda con `xpath`** (como en el ejemplo `sale.order`) en lugar de duplicarla: así el panel acompaña a las vistas que hereden de ella.

## Documentación oficial

- [Vista de referencia: `searchpanel`](https://www.odoo.com/documentation/20.0/developer/reference/user_interface/view_architectures.html) — atributos oficiales de `<searchpanel>` y de sus `<field>`, con tipos admitidos y valores por defecto.
- [`addons/web/models/models.py`, rama 20.0](https://github.com/odoo/odoo/blob/20.0/addons/web/models/models.py) — `search_panel_select_range` y `search_panel_select_multi_range`: la respuesta definitiva sobre qué consultas se lanzan.
- [`addons/web/static/src/search/search_arch_parser.js`, rama 20.0](https://github.com/odoo/odoo/blob/20.0/addons/web/static/src/search/search_arch_parser.js) — qué atributos lee el cliente (`visitSearchPanel`), incluidos los que la documentación no lista.

---

*En resumen: un `<searchpanel>` dentro de la vista de búsqueda convierte campos `Many2one`, `Many2many` o `Selection` en navegación lateral —categorías de selección única o filtros de casillas—; los valores salen de dos métodos del modelo que agrupan en base de datos, así que conviene usarlo con campos de baja cardinalidad y activar los contadores solo donde compensen.*
