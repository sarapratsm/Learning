# Vista de búsqueda

## ¿Qué es?

La vista de búsqueda es un registro del modelo `ir.ui.view` (el modelo donde Odoo guarda todas las vistas) cuyo XML tiene como raíz `<search>`. Declara la barra de búsqueda que aparece sobre una lista, un kanban, una tabla pivote o un gráfico: qué campos se pueden buscar escribiendo, qué filtros se ofrecen con un clic, por qué campos se puede agrupar y cuáles de esas opciones vienen activadas al abrir la pantalla. Es una vista que no muestra datos: acota lo que muestran las demás ([referencia de vistas, apartado Search](https://www.odoo.com/documentation/20.0/developer/reference/user_interface/view_architectures.html)).

Referencias de código y documentación: rama estable `20.0` de `github.com/odoo/odoo` (HEAD `4611da65a7`, leído el 2026-11-10) y documentación 20.0. La [página de versiones soportadas](https://www.odoo.com/documentation/20.0/administration/standard_extended_support.html) lista como versiones mayores con soporte estándar la 20.0, la 19.0 y la 18.0. No se ejecutó ninguna instancia de Odoo: el XML de los ejemplos procede de ficheros leídos, citados en cada caso, y las únicas «salidas» son las de la validación contra el esquema RNG que se indica en su sitio.

## ¿Por qué existe?

Una lista de pedidos de venta de una pequeña empresa como «Cafés del Valle» crece sin parar; sin una forma de acotarla, encontrar el pedido S00042 de un cliente o los presupuestos pendientes de confirmar es inviable. Odoo separa los datos (el modelo) de cómo se buscan en ellos (la vista de búsqueda), y esa búsqueda se declara en XML: se nombran los campos buscables y se escriben los filtros como dominios (la lista de condiciones de Odoo; véase [Dominios](Dominios.md)), y el cliente web construye la interfaz.

> Si ya conoces SQL, piensa en la vista de búsqueda como el menú de `WHERE` y `GROUP BY` permitidos para un modelo: cada `<field>` es una condición con un hueco que rellena quien escribe, cada `<filter>` es una condición ya escrita con un nombre amable y cada filtro con `group_by` es un `GROUP BY` ya escrito.

## ¿Cuándo y para qué se usa?

- **Añadir un filtro «Presupuestos» o «Por facturar»** a la lista de pedidos de venta para que el equipo comercial no escriba condiciones a mano.
- **Hacer que escribir «Cafés del Valle» busque** en el cliente, en la referencia del cliente y en los contactos hijos de esa empresa, no solo en el nombre del pedido.
- **Abrir una acción con un filtro ya activado**, por ejemplo «Mis presupuestos».
- **Extender la búsqueda de otro módulo** (añadir un campo o un filtro) sin copiar su vista.

## Anatomía de una vista de búsqueda

La raíz `<search>` admite como hijos `field`, `filter`, `separator`, `group` y `searchpanel` ([referencia de vistas](https://www.odoo.com/documentation/20.0/developer/reference/user_interface/view_architectures.html)). El panel de búsqueda lateral, `<searchpanel>`, tiene su propia ficha: [Search-Panel](Search-Panel.md).

### Ejemplo completo sobre `sale.order`

La vista de búsqueda de los pedidos de venta está en `addons/sale/views/sale_order_views.xml` (rama 20.0), registro `sale.view_sales_order_filter`. La versión que sigue es una adaptación reducida: conserva los atributos de la original y omite los campos de actividades y los filtros ocultos.

```xml
<record id="view_sales_order_filter" model="ir.ui.view">
    <field name="name">sale.order.list.select</field>
    <field name="model">sale.order</field>
    <field name="priority" eval="15"/>
    <field name="arch" type="xml">
        <search string="Search Sales Order">
            <field name="name" string="Order"
                   filter_domain="['|', '|', ('name', 'ilike', self),
                                   ('client_order_ref', 'ilike', self),
                                   ('partner_id', 'child_of', self)]"/>
            <field name="partner_id"/>
            <field name="user_id"/>
            <filter name="my_sale_orders_filter" string="My Orders"
                    domain="[('user_id', '=', uid)]"/>
            <group>
                <filter name="salesperson" string="Salesperson"
                        context="{'group_by': 'user_id'}"/>
                <filter name="customer" string="Customer"
                        context="{'group_by': 'partner_id'}"/>
                <filter name="order_month" string="Order Date"
                        context="{'group_by': 'date_order'}"/>
                <filter name="currency" string="Currency"
                        context="{'group_by': 'currency_id'}"
                        groups="base.group_multi_currency"/>
            </group>
        </search>
    </field>
</record>
```

Qué produce, según el código del cliente web (`addons/web/static/src/search/search_arch_parser.js`, rama 20.0):

- Cada `<field>` es un elemento de búsqueda por texto: al escribir «Cafés», la barra ofrece buscar ese texto en cada uno de los campos declarados, y cada opción elegida añade una condición.
- Cada `<filter>` con `domain` es una opción del menú de filtros: «My Orders» añade `[('user_id', '=', uid)]` (`uid` es el id del usuario que busca).
- Cada `<filter>` con `context="{'group_by': ...}"` aparece en el menú de agrupaciones. El parser decide que un filtro es una agrupación al ver un `group_by` en su `context` sobre un campo existente; si el campo es de fecha o fecha-hora, lo trata como agrupación por fecha, con un intervalo por defecto.
- `groups="base.group_multi_currency"` oculta la agrupación por moneda a quien no pertenezca a ese grupo de usuarios. Esto muestra u oculta la opción: no restringe qué registros se ven (para eso están las reglas de registro).

### Atributos de cada elemento

Los atributos admitidos por cada elemento se verificaron en el esquema RNG de la rama 20.0 (`odoo/addons/base/rng/search_view.rng` y `common.rng`, mismo directorio) y en la [referencia de vistas](https://www.odoo.com/documentation/20.0/developer/reference/user_interface/view_architectures.html).

| Elemento | Atributo | Función |
|---|---|---|
| `<search>` | `string` | Único atributo admitido; cualquier otro, p. ej. `foo="1"`, no valida contra el RNG. |
| `<field>` | `name` (obligatorio) | Campo del modelo por el que se busca. |
| | `string` | Etiqueta; por defecto, la etiqueta del campo. |
| | `filter_domain` | Dominio propio, con la variable `self` que contiene el texto escrito. Tiene prioridad sobre `operator`. |
| | `operator` | Cambia el operador del dominio generado (`=`, `ilike`, `child_of`...). |
| | `domain` | Restringe las sugerencias del autocompletado (campos `Many2one`). |
| | `context` | Contexto que se fusiona con el de la vista destino; puede usar `self`. |
| | `invisible`, `groups` | Ocultar el elemento; `groups` acepta una lista de grupos y el prefijo `!`. |
| `<filter>` | `name` | Identidad estable: se usa para activarlo por defecto y como ancla de herencia. La referencia lo da como obligatorio. |
| | `string` | Etiqueta visible. |
| | `domain` | Condición que se añade al dominio de búsqueda. |
| | `context` | Con `{'group_by': 'campo'}`, el filtro es una agrupación. |
| | `help` | Tooltip. |
| | `date`, `end_date`, `default_period` | Filtro de fechas: ver más abajo. |
| | `invisible`, `groups` | Ocultar el elemento. |
| `<separator/>` | | Corta el grupo de filtros en curso (ver «Cómo se combinan»). |
| `<group>` | | Agrupa elementos; en el RNG no admite `string` ni `expand`. |

**Filtros de fecha con `date`.** Un `<filter>` con `date="campo"` genera un submenú con meses, trimestres y años, en lugar de un dominio fijo. La referencia lo describe como filtros dependientes del tiempo que se evalúan al crear el panel de control. Ejemplo literal de la referencia:

```xml
<filter string="Creation Date" name="filter_create_date" date="create_date"/>
```

`default_period` indica qué periodo queda activo cuando el filtro se activa por defecto (valores como `month`, `month-1`, `year`, `this_week`...; lista completa en la referencia), y `end_date` permite filtrar por un rango entre dos campos de fecha. El filtro `Order Date` de `sale` es de este tipo: `<filter string="Order Date" name="order_date" date="date_order"/>` (`sale_order_views.xml`, 20.0).

### Cómo se combinan los elementos

La referencia indica que los dominios de los `<field>` se unen entre sí y con los filtros mediante AND. Dentro de los filtros, la regla viene del cliente: el parser cierra un grupo de elementos con cada `<separator/>`, cada `<group>` y cuando cambia el tipo de elemento (campo, filtro, agrupación), y `search_model.js` combina con OR (`Domain.or`) los filtros activos de un mismo grupo y con AND (`Domain.and`) los grupos entre sí.

```xml
<filter name="draft" string="Quotations" domain="[('state', 'in', ('draft', 'sent'))]"/>
<filter name="sales" string="Sales Orders" domain="[('state', '=', 'sale')]"/>
<separator/>
<filter name="to_invoice" string="To Invoice" domain="[('invoice_status', '=', 'to invoice')]"/>
```

Con «Quotations» y «Sales Orders» (adaptados de esa vista) activos a la vez, se muestran pedidos de cualquiera de los dos estados (OR). Si además se activa «To Invoice», el resultado exige estar en uno de los dos estados **y** estar por facturar (AND), porque `<separator/>` abre un grupo nuevo. Los filtros proceden de `sale_order_view_search_inherit_quotation` (`sale_order_views.xml`, 20.0), con la disposición de separadores simplificada.

### Un campo con varios campos detrás: `filter_domain`

Por defecto, un `<field>` genera un dominio sobre su propio campo. Con `filter_domain`, escribir una vez busca en varios sitios a la vez; la referencia lo describe como la vía para «buscar en varios campos a la vez». La variable `self` es el texto escrito y `raw_value` el valor sin transformar (`search_model.js`, `_getFieldDomain`).

```xml
<field name="name" string="Order"
       filter_domain="['|', '|',
                       ('name', 'ilike', self),
                       ('client_order_ref', 'ilike', self),
                       ('partner_id', 'child_of', self)]"/>
```

Al escribir «Cafés del Valle» y elegir la opción del campo `Order`, se buscan los pedidos cuyo número, referencia de cliente o contacto (incluidos sus contactos hijos, por `child_of`) coincidan. Si se elige el mismo campo varias veces con valores distintos, los dominios resultantes se combinan con OR. Sobre la sintaxis de los dominios, véase [Dominios](Dominios.md).

## Asociar la vista de búsqueda a una acción

Una acción de ventana (`ir.actions.act_window`) apunta a su vista de búsqueda con el campo `search_view_id` (Many2one a `ir.ui.view`, `odoo/addons/base/models/ir_actions.py`, 20.0). La referencia de acciones indica que, si falta, se carga la vista de búsqueda por defecto del modelo. Ejemplo de `sale_order_views.xml` (20.0), la acción de pedidos de venta:

```xml
<record id="action_orders" model="ir.actions.act_window">
    <field name="name">Sales Orders</field>
    <field name="res_model">sale.order</field>
    <field name="view_mode">list,kanban,form,calendar,pivot,graph,activity</field>
    <field name="search_view_id" ref="sale_order_view_search_inherit_sale"/>
    <field name="context">{'search_default_sales' : 1}</field>
</record>
```

Cada vista de la acción (lista, kanban, pivote...) comparte esa barra de búsqueda. Al abrir la acción, el filtro `sales` aparece activado (ver la sección siguiente) y la lista muestra solo los pedidos en estado `sale`.

### Qué pasa si no hay vista de búsqueda

`ir.ui.view._get_view` (`odoo/addons/base/models/ir_ui_view.py`, 20.0) resuelve la vista en este orden:

1. `search_view_ref` en el contexto, si existe (el patrón es `<tipo>_view_ref`, aquí `search_view_ref`).
2. La vista **primaria** del modelo de ese tipo con la prioridad más baja (`default_view`: «primary view with the lowest priority»).
3. Si no existe ninguna vista, el método `_get_default_search_view`, que genera una vista con **un solo campo**, el nombre del registro, y como título la descripción del modelo:

```python
def _get_default_search_view(self):
    element = E.field(name=self._rec_name_fallback())
    return E.search(element, string=self._description)
```

Consecuencia práctica: sin vista de búsqueda solo se puede buscar por el nombre del registro, sin filtros ni agrupaciones predefinidos. Y como el paso 2 elige la primaria de menor prioridad del modelo, una acción sin `search_view_id` hereda la vista de búsqueda por defecto que haya, que puede no ser la que se esperaba si hay varias.

## Filtros por defecto con `search_default_<nombre>`

El prefijo `search_default_` en el `context` de la acción activa un filtro o rellena un campo al abrir la pantalla. La referencia lo explica así: para un campo, el valor es el que se asigna al campo; para un filtro, un booleano o un número. El cliente web extrae esas claves del contexto y las borra de él (`_extractSearchDefaultsFromGlobalContext` en `search_model.js`, 20.0), de modo que no viajan al servidor como contexto.

```xml
<field name="context">{
    'search_default_my_quotation': 1,
    'search_default_partner_id': 7
}</field>
```

El filtro cuyo `name` es `my_quotation` queda activo, y el campo `partner_id` se rellena con el contacto de id 7. Dos detalles verificados en la referencia y en `search_arch_parser.js`:

- **Orden de las agrupaciones.** Para filtros de agrupación, un número entre 1 y 99 fija el orden: `{'search_default_foo': 2, 'search_default_bar': 1}` activa primero `bar` y después `foo`.
- **Filtros con carga perezosa** (los `<filter>` con un `<field>` hijo) no pueden usarse como valor por defecto, porque sus opciones se descargan solo al desplegarlos.

Para dominios que no se escriben a mano con valores fijos como el id 7, véase [Dominios dinámicos](Dominios-Dinamicos.md).

## Heredar una vista de búsqueda

Para añadir un filtro a la búsqueda de otro módulo se hereda su vista con `inherit_id` y se localiza el punto de inserción por el nombre del elemento. La búsqueda de pedidos de venta la extienden otros módulos oficiales; este ejemplo es el de `sale_project` (`addons/sale_project/views/sale_order_views.xml`, 20.0) que añade un campo:

```xml
<record id="view_sales_order_filter_inherit_sale_project" model="ir.ui.view">
    <field name="name">sale.order.list.select.inherit.sale_project</field>
    <field name="model">sale.order</field>
    <field name="inherit_id" ref="sale.view_sales_order_filter"/>
    <field name="arch" type="xml">
        <field name="order_line" position="after">
            <field name="project_id" groups="project.group_project_user"/>
        </field>
    </field>
</record>
```

Y este es el de `sale_stock` (`addons/sale_stock/views/sale_order_views.xml`, 20.0), que añade un filtro tras el filtro `order_date`:

```xml
<filter name="order_date" position="after">
    <filter string="Late Availability" name="late_availability"
            domain="[('late_availability', '=', True)]"/>
</filter>
```

Los dos ejemplos usan la forma abreviada `<elemento name="..." position="...">`, la que usan los módulos oficiales leídos; la forma general es `<xpath expr="..." position="...">`. `position` admite `before`, `after`, `inside`, `replace` y `attributes` (`common.rng`, definición `overload`). Un ejemplo con `xpath` explícito sobre el filtro de «Mis pedidos» (sintaxis estándar; no es una copia literal de un módulo):

```xml
<xpath expr="//filter[@name='my_sale_orders_filter']" position="after">
    <filter name="to_invoice" string="To Invoice"
            domain="[('invoice_status', '=', 'to invoice')]"/>
</xpath>
```

Dos matices de las vistas de `sale` de esta rama: `sale.sale_order_view_search_inherit_quotation` y `sale.sale_order_view_search_inherit_sale` declaran `<field name="mode">primary</field>` junto a `inherit_id`, es decir, son vistas **derivadas** que sirven de vista de búsqueda propia de una acción (`search_view_id`), no una extensión que se funde en la base. Esa elección es la que permite que dos acciones sobre `sale.order` (presupuestos y pedidos) tengan filtros distintos.

## Filtros de vista y filtros favoritos

Dos mecanismos distintos hacen que un filtro aparezca en el menú, con dueños diferentes:

| Necesidad | Dónde se define | Quién lo crea |
|---|---|---|
| Filtro disponible para todo el mundo y versionado con el módulo | `<filter>` en la vista de búsqueda (XML) | Quien desarrolla |
| Filtro activado al abrir una acción concreta | `search_default_<nombre>` en el `context` de la acción | Quien desarrolla |
| Filtro personal o de un equipo, sin tocar código | Favorito (registro de `ir.filters`) | Cada usuario desde el menú de filtros |
| Favorito que se aplica solo al abrir | Favorito marcado como `is_default` (campo de `ir.filters`) | Cada usuario |
| Filtro cuya condición depende del usuario que busca | `<filter>` con `domain` que use `uid` (como `My Orders`) | Quien desarrolla |

Un favorito es un registro de `ir.filters` (`odoo/addons/base/models/ir_filters.py`, 20.0) con los campos `name`, `model_id`, `domain` (texto, por defecto `'[]'`), `context`, `sort`, `is_default`, `action_id` y `user_ids`; el texto de ayuda de `user_ids` dice que si está vacío, el filtro se comparte con todos los usuarios. Se guarda en la base de datos, no en el XML de la vista: no se actualiza al actualizar el módulo ni se versiona.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Error `Element '<filter name="...">' cannot be located in parent view` al actualizar el módulo | El elemento ancla de la herencia no existe en la vista padre (otro módulo lo renombró, o aún no se cargó). El mensaje procede de `odoo/tools/template_inheritance.py` (20.0), que lo emite con el elemento localizado entre comillas, y entre `<` y `>` con sus atributos. |
| Error `Invalid view <nombre> definition in <fichero>` o `Error while validating view` al actualizar | El XML no cumple el esquema RNG. Mensajes literales de `ir_ui_view.py` (20.0): `Invalid view %(name)s definition in %(file)s` y `Error while validating view near:`. |
| `<group expand="0" string="Group By">` no valida | El `group` del RNG de 20.0 no tiene los atributos `expand` ni `string`. Comprobado con lxml contra `search_view.rng` (ver nota debajo). La vista de `sale` usa `<group>` sin atributos. |
| Un `<filter>` con `date` pero sin `name` no valida | El RNG exige `name` en el filtro estándar; solo con `string` se admite si el filtro tiene como hijo un `<field>` o filtros anidados (filtro «padre»). |
| `search_default_mi_filtro` no activa nada | El nombre no coincide con el `name` de ningún `<filter>` o `<field>` de la vista de búsqueda que usa la acción. Con `search_view_id` apuntando a otra vista, el filtro no existe en ella. |
| Un filtro de agrupación se comporta como filtro normal (o a la inversa) | La agrupación se declara con `context="{'group_by': 'campo'}"`, no con `domain`. Si el campo del `group_by` no existe en el modelo, el parser lo trata como filtro con contexto. |
| La búsqueda por un campo no encuentra lo esperado | El operador por defecto depende del tipo de campo: `=` para float, `ilike` para char y `child_of` para many2one (referencia de vistas). Para otra cosa, `operator` o `filter_domain`. |
| Una acción nueva solo permite buscar por nombre | La acción no tiene `search_view_id` y el modelo no tiene vista de búsqueda propia: se genera la vista de un solo campo. |

Nota sobre la validación: se descargó `search_view.rng` y `common.rng` de la rama 20.0 y se validaron ocho fragmentos con `lxml.etree.RelaxNG` (Python local, sin instancia de Odoo). Resultados: `<search><group>...` sin atributos valida; `<group expand="0" string="Group By">` falla con `RELAXNG_ERR_EXTRACONTENT: Element search has extra content: group`; `<filter domain="[]"/>` sin `name` ni `string` falla; `<filter string="..." date="..."/>` sin `name` falla; `<filter name="f" string="..." date="..."/>` valida; `<search foo="1">` falla con `RELAXNG_ERR_INVALIDATTR: Invalid attribute foo for element search`. La validación completa de Odoo (`valid_view` y comprobaciones adicionales) no se ejecutó.

## Buenas prácticas avanzadas

- **Pon un `name` a cada `<filter>` y trátalo como una API pública.** Es el ancla de la herencia (`<filter name="order_date" position="after">`), la clave de `search_default_<name>` y el id interno del cliente. Si lo renombras, rompes a quien herede de tu vista y a las acciones que lo activen por defecto.
- **Decide si una vista derivada o una herencia.** Una herencia normal modifica la vista base para todas las acciones; una vista con `mode="primary"` e `inherit_id` crea una vista de búsqueda propia para una acción concreta (como hace `sale` con presupuestos y pedidos). Usa la primera para añadir algo a todo el mundo y la segunda para que una acción tenga su propio menú de filtros.
- **No pongas una agrupación en `domain`.** La agrupación va siempre en `context="{'group_by': ...}"`; el parser clasifica el filtro por su `context`, no por su etiqueta. Para agrupar por un campo de fecha con otro intervalo, el mismo `context` admite `campo:intervalo` (el parser parte la cadena por `:`; los intervalos concretos no se verificaron).
- **`separator` define lógica, no solo estética.** Dos filtros contiguos se combinan con OR y separados por `<separator/>` o `<group>`, con AND. Meter un `<separator/>` de más en una vista heredada cambia el resultado de las combinaciones, no solo el aspecto del menú.
- **`groups` oculta la opción, no los datos.** Un `<filter groups="...">` esconde el filtro de quien no está en el grupo; no impide que esa persona vea esos registros por otra vía. Lo que un usuario no debe ver se restringe con reglas de registro, nunca con la vista de búsqueda.
- **Prefiere `date=` a dominios con fechas escritas.** Los filtros con `date` se recalculan al abrir el panel de control, con la fecha de ese momento; `default_period` y `end_date` cubren los casos habituales (mes anterior, rango entre dos campos) sin código.

## Documentación oficial

- [Vistas: referencia de arquitecturas, apartado Search](https://www.odoo.com/documentation/20.0/developer/reference/user_interface/view_architectures.html) — todos los atributos de `field`, `filter` y `group`, los filtros de fecha, y la sección «Search defaults»; el sitio al que ir primero.
- [Acciones: `ir.actions.act_window`](https://www.odoo.com/documentation/20.0/developer/reference/backend/actions.html) — `search_view_id`, `context` y el comportamiento por defecto de una acción sin vista de búsqueda.
- [Vista de búsqueda de `sale.order` en la rama 20.0](https://github.com/odoo/odoo/blob/20.0/addons/sale/views/sale_order_views.xml) — la implementación real: filtros, agrupaciones, herencia y acciones con `search_default_*`.

---

*En resumen: la vista de búsqueda es el XML `<search>` que declara qué campos, filtros y agrupaciones ofrece una pantalla; se asocia a una acción con `search_view_id`, se activa por defecto con `search_default_<nombre>`, se extiende con herencia anclada al `name` del filtro, y sin ella solo se busca por el nombre del registro.*
