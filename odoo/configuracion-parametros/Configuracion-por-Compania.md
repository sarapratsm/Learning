# Configuración por compañía

## ¿Qué es?

Una *compañía* (`res.company`) es una de las empresas que conviven en una misma base de datos de Odoo. La configuración por compañía es cualquier mecanismo que haga que un mismo ajuste tenga un **valor distinto en cada compañía** sin separar los datos en bases distintas.

Los ejemplos usan una pequeña empresa ficticia que vende cafés: «Cafés del Valle» (cliente), pedido de venta S00042, y una segunda compañía del mismo grupo, «Cafés del Valle Portugal». No se ejecutó ninguna instancia de Odoo: todo lo que sigue procede de la lectura del código de la rama `19.0` de `github.com/odoo/odoo` (ficheros `odoo/orm/environments.py`, `odoo/orm/fields.py` y `odoo/orm/models.py`) y de la documentación oficial 19.0.

## ¿Por qué existe?

Con varias compañías, muchos ajustes no pueden ser globales: cada una tiene su plazo de pago por defecto, su cuenta de ingresos, su pie legal. Un [parámetro del sistema](Parametros-del-Sistema.md) es único para toda la base de datos, y el [fichero de configuración del servidor](El-Fichero-odoo-conf.md) vale para todo el proceso. Hace falta guardar «un valor por compañía».

> Analogía: una cadena de franquicias con el mismo manual de operaciones, pero cada local tiene su propio cartel de horarios. El manual es el campo; el cartel es el valor de cada compañía.

## ¿Cuándo y para qué se usa?

Siempre que la instalación tenga más de una compañía y un dato deba variar entre ellas: la cuenta contable de un producto, el margen objetivo, un texto legal. Con una sola compañía suele bastar un campo normal, pero elegir el mecanismo correcto desde el principio evita migrar cuando aparezca la segunda.

## La compañía activa y las compañías permitidas

El usuario puede tener acceso a varias compañías (campo `company_ids`) y una compañía principal (`company_id`). En la interfaz marca cuáles están activas; esa selección viaja en el contexto como `allowed_company_ids`, una lista de ids donde **la primera es la compañía activa**.

En el código, el entorno expone dos atajos (`odoo/orm/environments.py`, rama 19.0):

| Atributo | Qué devuelve |
|---|---|
| `self.env.company` | La compañía activa: la primera de `allowed_company_ids` del contexto; si el contexto no la trae, la compañía principal del usuario (`user.company_id`). |
| `self.env.companies` | Las compañías habilitadas: `allowed_company_ids` del contexto o, si falta, `user.company_ids`. |

Si el contexto incluye una compañía a la que el usuario no tiene acceso, ambos atributos lanzan `AccessError` («Access to unauthorized or invalid companies.»), salvo en modo `sudo`, donde no se hace esa comprobación.

## Tres mecanismos para un valor distinto por compañía

### 1. Un campo en `res.company`

La compañía es un registro más; se le añade un campo y cada compañía guarda el suyo en su propia fila.

```python
class ResCompany(models.Model):
    _inherit = "res.company"

    plazo_entrega_dias = fields.Integer(string="Plazo de entrega (días)", default=3)
```

Para editarlo desde la pantalla de [Ajustes](Ajustes.md), el modelo `res.config.settings` declara un campo `related` hacia la compañía (el detalle de ese mecanismo está en la ficha de Ajustes):

```python
class ResConfigSettings(models.TransientModel):
    _inherit = "res.config.settings"

    plazo_entrega_dias = fields.Integer(related="company_id.plazo_entrega_dias", readonly=False)
```

Cuándo encaja: el valor es un atributo **de la compañía** y se lee desde muchos sitios.

### 2. `company_dependent=True` en cualquier modelo

Marca el campo de un modelo ajeno a la compañía (por ejemplo, el producto) y Odoo guarda un valor por compañía.

```python
class ProductTemplate(models.Model):
    _inherit = "product.template"

    margen_objetivo = fields.Float(company_dependent=True)
```

El mismo producto mostrará, por ejemplo, 20 bajo «Cafés del Valle» y 15 bajo «Cafés del Valle Portugal».

Cómo se guarda, según el docstring de `fields.py` en 19.0: «The value is stored on the model table as jsonb dict with the company id as the key», y los valores por defecto guardados en `ir.default` actúan como valor de respaldo para las compañías sin valor propio. Es decir, en 19.0 es una columna `jsonb` en la propia tabla del modelo, no el modelo `ir.property` (que era el almacenamiento de versiones anteriores; la ficha antigua lo daba por vigente y no lo es en 19.0).

Restricciones leídas en el código (`fields.py`, 19.0): los tipos permitidos son `char`, `float`, `boolean`, `integer`, `text`, `many2one`, `date`, `datetime`, `selection` y `html`; el campo no puede ser `required` ni traducible (Odoo emite una advertencia).

### 3. Reglas de registro por compañía

Las reglas de registro (`ir.rule`) pueden filtrar por `company_id` o `company_ids` para que cada usuario solo vea los registros de sus compañías. Eso no da un *valor* distinto por compañía: decide **qué registros** ve cada una. Se menciona aquí para no confundirlo con los dos mecanismos anteriores; su sintaxis no se cubre en esta guía.

## `check_company`: que no se mezclen compañías

Un campo relacional puede declararse con `check_company=True`; el modelo con `_check_company_auto = True` (mencionado en `models.py` 19.0 como activador de la consistencia sobre campos `check_company=True`) valida al escribir que el registro enlazado pertenezca a la misma compañía o a ninguna. `_check_company` lanza un `UserError` cuyo texto, en 19.0, incluye «…belongs to company … while … belongs to another company.» y termina con «To avoid a mess, no company crossover is allowed!».

Ejemplo: el pedido S00042 es de «Cafés del Valle»; si se le asigna un contacto exclusivo de «Cafés del Valle Portugal», la validación lo rechaza. El texto «Incompatible companies on records» no aparece en `models.py` 19.0, por lo que no se cita como mensaje vigente.

## Tabla de decisión

| Necesitas… | Usa |
|---|---|
| Un atributo propio de la compañía (plazo, logo, texto legal) | Campo en `res.company` (+ `related` en Ajustes) |
| Un valor por compañía en un registro compartido (producto, categoría) | `company_dependent=True` |
| Que cada compañía vea solo sus registros | `company_id` + regla de registro |
| Impedir enlaces entre compañías | `check_company=True` |
| Un valor único para toda la base | [Parámetro del sistema](Parametros-del-Sistema.md) |
| Un valor inicial al crear registros | [Valor por defecto](Valores-por-Defecto.md) |

## Leer el valor de la compañía correcta

Un campo `company_dependent` devuelve el valor de **la compañía activa del entorno** (`env.company`). Para leer el de otra, se cambia el entorno con `with_company`, que en 19.0 devuelve un recordset con `env.company = company` (y la añade a `env.companies`):

```python
producto = self.env["product.template"].browse(7)
margen_portugal = producto.with_company(portugal).margen_objetivo
```

`with_company` con un valor vacío (`False`, `None`, recordset vacío) mantiene el entorno actual. Usar una compañía no autorizada para el usuario puede provocar `AccessError` al acceder a ella, salvo en `sudo`.

Para campos de `res.company`, basta leer el registro: `portugal.plazo_entrega_dias`.

### La trampa: leer bajo la compañía equivocada

❌ Un cron o una acción de servidor corre con la compañía principal del usuario y lee sin fijar compañía:

```python
for producto in productos:          # env.company = compañía principal
    informe.append(producto.margen_objetivo)   # siempre el valor de esa compañía
```

✅ Se fija la compañía para la que se calcula:

```python
for compania in self.env["res.company"].search([]):
    for producto in productos.with_company(compania):
        informe.append((compania.name, producto.margen_objetivo))
```

La consulta también depende del entorno: en `fields.py` 19.0, ordenar o agrupar por un campo `company_dependent` usa `model.env.company.id` como clave dentro del `jsonb`. Un dominio sobre ese campo se evalúa, por tanto, para la compañía activa.

## Errores frecuentes

- **«A veces sale un valor y a veces otro»** → el código se ejecuta con distinta compañía activa (cron, usuario con varias compañías); fijar la compañía con `with_company`.
- **El valor de una compañía nueva aparece vacío o con un valor que nadie puso** → una compañía sin valor propio usa el valor de respaldo de `ir.default` (docstring de `fields.py` 19.0); definir el valor para la nueva compañía.
- **`AccessError` «Access to unauthorized or invalid companies.»** → el contexto trae un `allowed_company_ids` con una compañía fuera de las del usuario.
- **`UserError` «…no company crossover is allowed!»** → se enlazó un registro de otra compañía en un campo con `check_company=True`.
- **Se declaró `company_dependent` en un campo `required` o de un tipo no permitido** → el código emite una advertencia; revisar la lista de tipos permitidos.

## Buenas prácticas avanzadas

- **Elige el mecanismo por el dueño del dato.** Si pertenece a la compañía, campo en `res.company`; si pertenece a un registro compartido y solo el valor varía, `company_dependent`.
- **Fija siempre la compañía en código sin usuario** (cron, importaciones, tareas en cola) con `with_company`; no dependas de la compañía principal del usuario que lo lanza.
- **Ten en cuenta el respaldo de `ir.default`.** Un valor por defecto cambia el comportamiento de todas las compañías sin valor propio (ver [Valores por defecto](Valores-por-Defecto.md)).
- **Expón el ajuste en [Ajustes](Ajustes.md)** con la compañía visible, no editando datos técnicos.
- **Referencia registros concretos por [ID externo](Referencias-por-ID-Externo.md)**, no por nombre, cuando cada compañía tenga registros homónimos.

## Documentación oficial

- [ORM API, Odoo 19.0](https://www.odoo.com/documentation/19.0/developer/reference/backend/orm.html): campos, `company_dependent` y entorno.
- [Multi-company guidelines, 19.0](https://www.odoo.com/documentation/19.0/developer/howtos/company.html): `check_company`, `with_company` y reglas por compañía.

No verificado: el comportamiento exacto de las reglas `ir.rule` por compañía y el contenido de esas páginas más allá de que responden 200.

---

*En resumen: un valor distinto por compañía se logra con un campo en `res.company`, con `company_dependent=True` (un `jsonb` por compañía en 19.0) o filtrando registros con reglas; al leerlo, la compañía activa (`env.company`) decide el valor, y `with_company` es la forma de pedir el de otra.*
