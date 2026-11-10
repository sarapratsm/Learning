# Ajustes (res.config.settings)

## ¿Qué es?

`res.config.settings` es el modelo que hay detrás de la pantalla **Ajustes** (*Settings*) de Odoo. Es un modelo **transitorio** (`TransientModel`: sus registros son temporales y Odoo los purga solo) cuya misión es mostrar un formulario de configuración y, al pulsar *Guardar*, repartir lo que se ha rellenado entre los sitios donde esos valores viven de verdad: un [parámetro del sistema](Parametros-del-Sistema.md), un campo de la compañía, un grupo de seguridad, un valor por defecto o un módulo por instalar.

Referencias de código y documentación: rama estable `20.0` de `github.com/odoo/odoo`, leída el 2026-11-10 (la [página de versiones soportadas](https://www.odoo.com/documentation/20.0/administration/standard_extended_support.html) lista 20.0, 19.0 y 18.0 con soporte estándar). No se ejecutó ninguna instancia de Odoo: el comportamiento descrito sale de los ficheros citados, sobre todo [`odoo/addons/base/models/res_config.py`](https://github.com/odoo/odoo/blob/20.0/odoo/addons/base/models/res_config.py).

## ¿Por qué existe?

Una lista técnica de clave-valor no es sitio para quien gestiona el negocio: no valida, no agrupa y está en el menú técnico. Además, lo que una persona entiende como «un ajuste» se guarda en cinco sitios distintos según el caso. `res.config.settings` ofrece una sola pantalla con casillas, etiquetas y ayudas, y un mecanismo por convención de nombres que decide dónde guardar cada campo.

> Analogía: es la ventanilla de un ayuntamiento. La persona rellena un único impreso; detrás, el personal lo reparte entre registro, hacienda y urbanismo. El impreso no archiva nada: se tira al terminar.

## ¿Cuándo y para qué se usa?

Cuando un módulo tiene opciones que el cliente debe poder cambiar sin un desarrollador: activar una funcionalidad opcional, fijar un plazo, elegir una plantilla por defecto, instalar un módulo complementario. El ejemplo conductor es la pequeña empresa de cafés (cliente «Cafés del Valle», pedido S00042) que quiere configurar su flujo de pedidos de venta.

## Cómo se declara un ajuste: la convención de nombres

`execute` y `default_get` clasifican cada campo del modelo según su **prefijo** o sus atributos (`_get_classified_fields` en `res_config.py`, rama 20.0):

| Campo | Qué ocurre al guardar | Dónde queda el valor |
|---|---|---|
| `config_parameter='clave'` (tipos `boolean`, `integer`, `float`, `char`, `selection`, `many2one`, `datetime`) | Escribe el parámetro | `ir.config_parameter` ([Parámetros del sistema](Parametros-del-Sistema.md)) |
| `related='company_id.campo'` + `readonly=False` | Escribe en el campo de la compañía | `res.company` ([Configuración por compañía](Configuracion-por-Compania.md)) |
| `group_xxx` (boolean o selection) con `implied_group='modulo.grupo'` | Añade o quita el grupo implicado | grupos de seguridad (`group` por defecto: `base.group_user`, Empleado) |
| `module_xxx` (boolean o selection) | Instala (o desinstala) el módulo `xxx` | `ir.module.module` |
| `default_xxx` con `default_model='modelo'` | Fija el valor por defecto del campo `xxx` de ese modelo | `ir.default` ([Valores por defecto](Valores-por-Defecto.md)) |
| Cualquier otro | Nada automático: lo gestiona `set_values` si lo sobrescribes | donde tu código decida |

Fuente de la tabla: docstring de la clase y `_get_classified_fields`, `res_config.py`, rama 20.0. Un `group_`, `module_` o `default_` mal declarado (sin `implied_group`, sin `default_model`, o de tipo no permitido) lanza una excepción al clasificar los campos.

### Ajuste global con `config_parameter`

Se introduce con un campo que enlaza con un parámetro; el ejemplo está adaptado de `addons/sale/wizard/res_config_settings.py` (rama 20.0), que declara `sale_order_mandatory_product = fields.Boolean(string="Mandatory Product", config_parameter="sale.mandatory_product")`:

```python
from odoo import fields, models

class ResConfigSettings(models.TransientModel):
    _inherit = "res.config.settings"

    pedido_requiere_producto = fields.Boolean(
        string="Exigir producto en cada línea",
        config_parameter="cafes_pedidos.requiere_producto",
    )
```

Al abrir Ajustes, `default_get` lee el parámetro y rellena la casilla; al guardar, `set_values` lo escribe. En la rama 20.0 un `boolean` se guarda con `set_bool`, un `integer` con `set_int`, un `char` se recorta de espacios (`strip`) y un `many2one` guarda el id.

### Ajuste por compañía con `related`

Cuando el valor debe diferir entre compañías, el campo apunta a un campo de `res.company`. Ejemplo literal de `sale`:

```python
quotation_validity_days = fields.Integer(
    related="company_id.quotation_validity_days", readonly=False
)
```

Sin `readonly=False`, un campo `related` es de solo lectura: se ve pero no se edita. El campo de `res.company` tiene que existir (en `sale` lo define el propio módulo; la ficha de [Configuración por compañía](Configuracion-por-Compania.md) lo trata).

### Ajuste que activa un grupo o instala un módulo

Dos ejemplos de `sale` (rama 20.0):

```python
group_discount_per_so_line = fields.Boolean(
    string="Discounts", implied_group="sale.group_discount_per_so_line"
)
module_delivery = fields.Boolean("Delivery Methods")
```

El primero concede el grupo «descuentos por línea» a los grupos de `group` (por defecto, Empleado); el segundo instala el módulo `delivery` al marcarlo.

## La vista: `<app>`, `<block>`, `<setting>`

Los campos se colocan heredando `base.res_config_settings_view_form`. Extracto de `addons/sale/wizard/res_config_settings_views.xml` (rama 20.0), abreviado:

```xml
<record id="res_config_settings_view_form" model="ir.ui.view">
    <field name="name">res.config.settings.view.form.inherit.sale</field>
    <field name="model">res.config.settings</field>
    <field name="inherit_id" ref="base.res_config_settings_view_form"/>
    <field name="arch" type="xml">
        <xpath expr="//form" position="inside">
            <app notApp="1" string="Sales" name="sale_management"
                 groups="sales_team.group_sale_manager">
                <block title="Quotations &amp; Orders" name="quotation_order_setting_container">
                    <setting id="sale_order_mandatory_product"
                             help="Prevent selling without a linked product">
                        <field name="sale_order_mandatory_product"/>
                    </setting>
                </block>
            </app>
        </xpath>
    </field>
</record>
```

- `<app>`: la sección de una aplicación en la barra lateral de Ajustes.
- `<block title="...">`: un grupo con título dentro de la aplicación.
- `<setting help="...">`: una opción, con su campo, su texto de ayuda y, opcionalmente, contenido que aparece al marcarla (`invisible="not group_uom"` en el fichero real).

El atributo `company_dependent="1"` en un `<setting>` del fichero real marca los ajustes que son por compañía.

## Qué ocurre al pulsar «Guardar»

Secuencia de `execute` (rama 20.0, `res_config.py`):

1. Comprueba que quien guarda es administrador; si no, lanza `AccessError` («Only administrators can change the settings»).
2. Llama a `set_values()`: guarda los campos `default_`, aplica o retira los `group_`, y escribe los `config_parameter`. Solo actúa donde el valor cambió respecto al actual.
3. Calcula los módulos a instalar (`module_xxx` marcado y no instalado) y a desinstalar (desmarcado e instalado).
4. Si hay módulos que desinstalar, devuelve un asistente de confirmación («Uninstall modules») y **no instala nada** todavía.
5. Si no, instala los pendientes con `button_immediate_install()`.
6. Devuelve una acción de recarga del cliente web (`ir.actions.client`, `tag: reload`), salvo que `res.config.next()` devuelva otra acción.

El docstring avisa de que `execute` **no debe sobrescribirse** y de que la parte de instalar o desinstalar módulos debe quedar al final de la transacción para evitar desincronizar el registro y la base de datos. Lo que se sobrescribe es `set_values`.

## Ajuste propio en la pantalla existente

Ejemplo adaptado y rotulado como tal (no ejecutado): añadir a Ajustes un plazo en días con su casilla, dentro del bloque de ventas.

```python
class ResConfigSettings(models.TransientModel):
    _inherit = "res.config.settings"

    dias_aviso_pedido = fields.Integer(
        string="Días de aviso de pedido",
        config_parameter="cafes_pedidos.dias_aviso",
        default=3,
    )
```

```xml
<record id="res_config_settings_view_form_cafes" model="ir.ui.view">
    <field name="name">res.config.settings.view.form.inherit.cafes</field>
    <field name="model">res.config.settings</field>
    <field name="inherit_id" ref="sale.res_config_settings_view_form"/>
    <field name="arch" type="xml">
        <xpath expr="//block[@name='quotation_order_setting_container']" position="inside">
            <setting id="dias_aviso_pedido" help="Días antes de avisar de un pedido sin confirmar">
                <field name="dias_aviso_pedido"/>
            </setting>
        </xpath>
    </field>
</record>
```

El `name` del bloque (`quotation_order_setting_container`) es el que aparece en el fichero de `sale` citado. En `default_get`, si el parámetro no existe, se usa el `default` del campo. Qué verá la usuaria: un nuevo ajuste bajo «Quotations & Orders» con el valor 3 hasta que lo cambie.

## Campos que no persisten por sí solos

Un campo sin prefijo ni `config_parameter` ni `related` editable cae en la categoría `other`: se muestra, pero `execute` no lo guarda. Hay dos salidas: darle `config_parameter` (si es un tipo admitido) o implementar `get_values` (rellenar al abrir) y `set_values` (escribir al guardar), llamando a `super()` en este último.

```python
@api.model
def get_values(self):
    res = super().get_values()
    res["mi_campo"] = self.env["ir.config_parameter"].sudo().get_str("cafes_pedidos.mi_campo", False)
    return res
```

Los métodos `get_values` y `set_values` existen en la rama 20.0 (`get_values` devuelve `{}` por defecto); el cuerpo del ejemplo es ilustrativo, no extraído del código.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| El campo aparece en Ajustes, se cambia, guarda y al recargar vuelve al valor anterior | No es `config_parameter` ni `related` editable ni `group_`/`module_`/`default_`: cae en `other` y nadie lo escribe |
| El campo aparece pero no se puede editar | Es `related` sin `readonly=False` |
| Todas las compañías comparten el mismo valor | Se usó `config_parameter` (global a la base de datos) donde correspondía `related` a la compañía |
| Se instala un módulo al guardar sin que nadie lo pidiera | Hay una casilla `module_xxx` marcada en pantalla: guardar la instala |
| Al guardar aparece un asistente de desinstalación | Se desmarcó un `module_xxx` de un módulo instalado |
| Excepción «Field ... without attribute 'implied_group'» (o `default_model`) | Un campo `group_` o `default_` mal declarado |
| «Only administrators can change the settings» | `execute` exige administrador |
| El valor numérico o de texto guarda espacios o formato inesperado | Los parámetros se guardan como texto: los `char` se recortan; los demás tipos se convierten |

## Buenas prácticas avanzadas

- **Elige el respaldo según el alcance:** `config_parameter` para lo global a la base de datos, `related` a `res.company` para lo que cambia por empresa; los `group_` para lo que se enciende por permisos.
- **Prefiere sobrescribir `set_values` a `execute`:** el docstring lo pide expresamente porque la instalación de módulos debe ir al final de la transacción.
- **Nombra los parámetros con prefijo de módulo** (`cafes_pedidos.dias_aviso`): el espacio de claves de `ir.config_parameter` es común a todos los módulos.
- **Recuerda que guardar sin cambios tampoco es gratis:** `create` descarta los campos `related` editables cuyo valor no ha cambiado para no disparar recálculos en cadena (comentario de optimización en `create`, `res_config.py`).
- **Usa `module_` con cuidado:** una casilla de módulo hace una instalación real al guardar; ponle una ayuda que lo diga.

## Documentación oficial

- [`res_config.py` (rama 20.0)](https://github.com/odoo/odoo/blob/20.0/odoo/addons/base/models/res_config.py): `get_values`, `set_values`, `execute` y el docstring con la convención de nombres.
- [`addons/sale/wizard/res_config_settings_views.xml`](https://github.com/odoo/odoo/blob/20.0/addons/sale/wizard/res_config_settings_views.xml): ejemplo real de `<app>`, `<block>` y `<setting>`.
- [Referencia del ORM, 20.0](https://www.odoo.com/documentation/20.0/developer/reference/backend/orm.html): modelos transitorios y campos relacionados.

Fichas relacionadas: [Parámetros del sistema](Parametros-del-Sistema.md), [Configuración por compañía](Configuracion-por-Compania.md), [Valores por defecto](Valores-por-Defecto.md), [Referencias por ID externo](Referencias-por-ID-Externo.md) (para el `ref="..."` de las vistas), [El fichero odoo.conf](El-Fichero-odoo-conf.md) (infraestructura, fuera de Ajustes).

---

*En resumen: `res.config.settings` es un formulario transitorio que reparte, por convención de nombres, cada ajuste hacia un parámetro, un campo de compañía, un grupo, un valor por defecto o un módulo; lo que no encaja en ninguna convención no se guarda salvo que implementes `set_values`.*
