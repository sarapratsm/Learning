# Valores por defecto

## ¿Qué es?

Un valor por defecto es el dato que Odoo precarga en un campo cuando se **crea** un registro y nadie lo ha informado. Hay cuatro vías para definirlo, con prioridad distinta:

| Vía | Dónde vive | Ejemplo |
|---|---|---|
| `default=` en el campo | Código del módulo | `fields.Date(default=fields.Date.context_today)` |
| `default_get` sobrescrito | Código del módulo | un método que añade claves al diccionario de defaults |
| `default_<campo>` en el contexto | Acción, vista o llamada | `context="{'default_partner_id': 7}"` |
| `ir.default` (valores por defecto definidos por el usuario) | Base de datos | un administrador fija `note` para todos los pedidos |

Una quinta pieza, `search_default_*`, parece de la familia pero precarga **filtros de búsqueda**, no campos de un registro (ver el apartado 5).

Versión de referencia: Odoo 19.0 (`odoo/release.py` de la rama `19.0` declara `version_info = (19, 0, 0, FINAL, 0, '')`). El código se leyó en `odoo/orm/models.py`, `odoo/orm/fields.py`, `odoo/orm/fields_temporal.py` y `odoo/addons/base/models/ir_default.py` de esa rama. No se ejecutó ninguna instancia de Odoo: los comportamientos descritos salen de la lectura del código fuente.

## ¿Por qué existe?

Rellenar siempre los mismos campos a mano es lento y genera registros incompletos. Si todo pedido de venta nace con la fecha de hoy, o si al crear un pedido desde la ficha de «Cafés del Valle» el cliente ya debe venir puesto, es mejor que Odoo lo precargue.

> Es el equivalente al valor por defecto de un parámetro de función o a `DEFAULT` en una columna SQL, con una diferencia: aquí hay varias capas que pueden pisarse entre sí, y conviene saber cuál gana.

## ¿Cuándo y para qué se usa?

- Valor fijo o calculado que decide el desarrollo: `default=`.
- Lógica de varios campos relacionados entre sí al crear: `default_get`.
- El valor depende de desde dónde se abre el formulario (un botón en la ficha de un cliente que crea un pedido): contexto `default_<campo>`.
- El valor lo decide quien administra la instancia, sin desplegar código, quizá distinto por usuario o compañía: `ir.default`.

## 1. `default=` en la definición del campo

Para una constante se pasa el valor; para uno dinámico, un callable que recibe el modelo (`self`).

```python
class SaleOrder(models.Model):
    _inherit = "sale.order"

    prioridad = fields.Integer(default=1)                                   # constante
    fecha_entrega = fields.Date(default=fields.Date.context_today)          # callable
    responsable_id = fields.Many2one("res.users", default=lambda self: self.env.user)
```

Qué ocurre: en `odoo/orm/fields.py` (rama 19.0), `setup` convierte cualquier constante en un callable (`self.default = lambda model: value`), de modo que todos los defaults se evalúan igual al crear (`field.default(self)`).

### La trampa: callable frente a valor evaluado al arrancar

```python
# ❌ Se evalúa UNA vez, al importar el módulo: toda creación posterior
#    recibe la fecha del día en que arrancó el servidor.
fecha = fields.Date(default=fields.Date.today())

# ✅ Se pasa la función: se llama en cada creación.
fecha = fields.Date(default=fields.Date.today)
```

Explicación: con paréntesis, Python ejecuta `today()` al definir la clase y `default` recibe una fecha concreta, que pasa a ser una constante. Sin paréntesis, `default` recibe la función y Odoo la invoca con el modelo cada vez. `fields.Date.today` acepta argumentos sobrantes (`def today(*args)` en `fields_temporal.py`), por eso se puede pasar tal cual. Para la fecha en la zona horaria del usuario existe `fields.Date.context_today` (recibe el recordset). Lo mismo vale para `lambda self: ...`: el cuerpo se ejecuta al crear, no al definir.

## 2. `default_get` sobrescrito

`default_get(fields)` es el método del ORM que reúne los valores por defecto de los campos pedidos. Sobrescribirlo sirve cuando el valor de un campo depende de otros defaults:

```python
@api.model
def default_get(self, fields_list):
    res = super().default_get(fields_list)
    if "fecha_entrega" in fields_list and not res.get("fecha_entrega"):
        res["fecha_entrega"] = fields.Date.context_today(self)
    return res
```

Llamar a `super()` primero conserva el orden de prioridad del apartado siguiente; lo que se añada después se aplica **por encima** de contexto, `ir.default` y `default=` si se sobrescribe la clave, así que conviene añadir solo claves ausentes.

## 3. Precedencia real: contexto, `ir.default`, `default=`

En `default_get` de `odoo/orm/models.py` (rama 19.0), para cada campo pedido el orden es este (los comentarios numerados son los del código):

1. **Contexto**: si existe la clave `default_<campo>` en `self.env.context`, se usa y se pasa al siguiente campo.
2. **`ir.default`** para campos que no son `company_dependent`.
3. **`field.default`** (el `default=` del campo).
4. **`ir.default`** para campos `company_dependent` (actúa como valor de reserva).
5. Si el campo viene de un modelo heredado por `_inherits`, se delega en el modelo padre.

Consecuencia práctica: **un `ir.default` gana a `default=`**, y el contexto gana a ambos. Por eso un administrador puede cambiar un default del código sin desplegar, y por eso un botón puede forzar otro valor al abrir el formulario.

Ejemplo de contexto en una acción de ventana (XML):

```xml
<field name="context">{'default_partner_id': active_id}</field>
```

Al abrir el formulario, `partner_id` llega rellenado con el contacto de origen, aunque el campo tenga `default=` o un `ir.default`.

## 4. `ir.default`: valores definidos por el usuario o el administrador

`ir.default` guarda en base de datos un valor (en JSON, campo `json_value`) para un campo, con alcance opcional por usuario (`user_id`), compañía (`company_id`) y una `condition` (cadena opaca, normalmente `clave=valor`). El modelo se describe como «User-defined Defaults»: tiene una entrada de menú con ese nombre en el menú técnico (la ruta exacta del menú no se verificó). Es una vista de lista/formulario sobre `ir.default`, visible con el modo desarrollador.

```python
self.env["ir.default"].set("sale.order", "note", "Gracias por su compra")        # todos
self.env["ir.default"].set("sale.order", "note", "Pago a 30 días",
                           user_id=True, company_id=False)                     # usuario actual
valor = self.env["ir.default"]._get("sale.order", "note", user_id=True)
```

Comportamiento, según `ir_default.py` (rama 19.0):

- `set(model_name, field_name, value, user_id=False, company_id=False, condition=False)` valida que el campo existe y que el valor es convertible; si ya hay una entrada con el mismo alcance (campo, usuario, compañía, condición) la **reemplaza**, y si no, la crea. `user_id=True` significa «usuario actual» y `company_id=True`, «compañía actual».
- `_get(...)` devuelve el valor **solo de esa combinación exacta**, o `None`. No resuelve prioridades.
- La resolución para un usuario la hace `_get_model_defaults`, usada por `default_get`: toma las entradas de usuario nulo o actual y compañía nula o actual, ordenadas por `user_id, company_id, id`, y se queda con la primera por campo. Con la ordenación habitual de PostgreSQL (los nulos van al final en orden ascendente) una entrada específica de usuario o compañía prevalece sobre la general; esta lectura del orden no se ejecutó.
- Crear, modificar o borrar un `ir.default` invalida cachés (`registry.clear_cache()`); `_get_model_defaults` está cacheado por usuario, compañía, modelo y condición.
- Al crear o editar, se comprueba que quien lo hace puede crear en el modelo y escribir en el campo (`_check_accessible_field_id`).
- El valor debe ser JSON válido y de tipo compatible con el campo, o salta `ValidationError`.

Los ajustes globales de módulo se tratan en [Ajustes](Ajustes.md).

## 5. `search_default_*` (solo mención)

La clave `search_default_<filtro>` en el contexto de una acción activa un filtro o agrupación de la vista de búsqueda al abrir la lista. No rellena campos de un registro nuevo. Se explica en [Vista de búsqueda](../busqueda-y-filtros/Vista-de-Busqueda.md).

## Tabla de decisión

| Necesidad | Vía | Quién puede cambiarlo |
|---|---|---|
| Valor fijo o calculado, parte del diseño del módulo | `default=` | Quien programa (requiere actualizar el módulo) |
| Varios defaults interdependientes | `default_get` | Quien programa |
| El valor depende del origen (desde qué cliente o pedido se crea) | `default_<campo>` en el contexto | Quien define la acción o el botón |
| El valor lo elige la persona administradora, por usuario o compañía | `ir.default` | Quien tenga acceso al modelo `ir.default` (en la práctica, administración) |
| Filtro inicial de una lista | `search_default_*` | Quien define la acción |

Para valores que la lógica **consulta después de crear** (no precargas), véanse [Parámetros del sistema](Parametros-del-Sistema.md), [Ajustes](Ajustes.md) y [Configuración por compañía](Configuracion-por-Compania.md); el fichero [odoo.conf](El-Fichero-odoo-conf.md) es configuración del servidor, no de registros. Para referirse a registros concretos en un default sin fijar ids, véase [Referencias por ID externo](Referencias-por-ID-Externo.md).

## Defaults y la API de creación

`create` aplica los defaults solo a los campos que **no** vienen en `vals`. En `_add_missing_default_values` (`models.py`, 19.0) el código calcula los campos ausentes, llama a `default_get` con ellos y termina con `defaults.update(values)`, comentado como «override defaults with the provided values, never allow the other way around».

```python
# Con context {'default_partner_id': cafes_del_valle.id}:
env["sale.order"].with_context(default_partner_id=cafes_del_valle.id).create({
    "partner_id": otro_cliente.id,   # gana este valor; el contexto no lo pisa
})
```

Además, `create` comprueba permisos de escritura sobre los campos dados y también sobre los de claves `default_*` del contexto que correspondan a campos del modelo; una clave `default_x` con un campo inexistente se ignora en esa comprobación.

## Errores frecuentes

- **Todos los registros nuevos salen con la misma fecha vieja** → se escribió `default=fields.Date.today()`: se evaluó al arrancar. Pasar `fields.Date.today` sin paréntesis.
- **Cambié `default=` en el código y no se ve efecto** → existe un `ir.default` para ese campo, que tiene prioridad sobre `default=`. Revisar la entrada en «User-defined Defaults».
- **El `ir.default` no se aplica a un campo `company_dependent`** → en esos campos `ir.default` actúa solo si no hay `default=`, tras él (paso 4 del orden).
- **`default_x` en el contexto no hace nada al llamar a `create`** → el valor ya venía en `vals`, o el nombre del campo no existe en el modelo.
- **`ValidationError` al fijar un `ir.default`** → el JSON no es válido o su tipo no encaja con el campo.
- **Un default de Many2one apunta a un registro borrado** → `ir.default.discard_records` existe para limpiar esas entradas; no se verificó cuándo se invoca.
- **Un usuario sin permisos no puede crear defaults** → `ir.default` exige acceso de creación al modelo y de escritura al campo.

## Buenas prácticas avanzadas

- Prefiere `default=` con callable o `lambda self:` y reserva `default_get` para dependencias entre campos: evita sobrescribir más métodos del ORM de los necesarios.
- Recuerda que `ir.default` está por encima de `default=`: un default del código no es una garantía, y los defaults del usuario deben documentarse en el módulo que los espera.
- Para campos `company_dependent`, el orden cambia: el `default=` del código gana al `ir.default`. Mezclarlos produce comportamientos distintos entre campos del mismo modelo.
- Usa el contexto `default_<campo>` en botones y acciones que crean registros relacionados; es explícito, local y no depende de configuración.
- Al probar, crea con y sin `default_*` en el contexto y con `vals` explícitos: son tres caminos distintos del mismo método.

## Documentación oficial

- [ORM API, valores por defecto de campos](https://www.odoo.com/documentation/19.0/developer/reference/backend/orm.html) — parámetro `default` de los campos y `default_get`.
- [Acciones](https://www.odoo.com/documentation/19.0/developer/reference/backend/actions.html) — el contexto de `ir.actions.act_window`.
- [`ir_default.py`](https://github.com/odoo/odoo/blob/19.0/odoo/addons/base/models/ir_default.py) — lectura recomendada: `set`, `_get` y `_get_model_defaults`.

---

*En resumen: un default precarga un campo solo al crear y solo si no se ha informado; el orden real en `default_get` es contexto `default_<campo>`, luego `ir.default`, luego `default=` (con la excepción de los campos por compañía), y los callables se pasan sin paréntesis para evaluarse en cada creación.*
