# Dominios

Referencias de código y documentación: rama estable `20.0` de `github.com/odoo/odoo` (HEAD `4611da65a7`, leído el 2026-11-10) y documentación 20.0. La [página de versiones soportadas](https://www.odoo.com/documentation/20.0/administration/standard_extended_support.html) lista como versiones mayores con soporte estándar la 20.0, la 19.0 y la 18.0. No se ejecutó ninguna instancia de Odoo: los comportamientos descritos proceden de ficheros y páginas leídos, citados en cada punto. Los ejemplos usan datos inventados (cliente «Cafés del Valle», pedido S00042).

## ¿Qué es?

Un dominio es la forma que tiene Odoo de expresar un filtro sobre registros: una lista de condiciones `(campo, operador, valor)`, combinables con los operadores lógicos `&` (y), `|` (o) y `!` (no), que decide qué filas de un modelo se seleccionan. Es el `WHERE` de SQL escrito como estructura de datos de Python.

## ¿Por qué existe?

Casi todo lo que filtra registros en Odoo —una lista que muestra solo los pedidos del mes, un desplegable que solo ofrece empresas, una regla de seguridad que limita a cada persona a sus propios documentos— necesita decir «quédate con los que cumplan esto». Escribir SQL en cada sitio ataría cada filtro al esquema de la base de datos, y no podría viajar entre el servidor, las vistas XML y el navegador. El dominio es un lenguaje único que los tres entienden: el ORM lo traduce a SQL, y el cliente web lo manipula como datos (por ejemplo, para que un editor visual lo construya con clics).

> Si vienes de SQL, `WHERE state = 'sale' AND amount_total > 100` se escribe como `[('state', '=', 'sale'), ('amount_total', '>', 100)]`. Si vienes de LINQ o de los *predicates* de un ORM, un dominio es el predicado, pero serializable: una lista, no una lambda.

## ¿Cuándo y para qué se usa?

Aparece siempre que haya que acotar registros: los pedidos de venta confirmados de un cliente, el desplegable de «Cliente» que solo debe ofrecer empresas, el filtro «Mis pedidos», la regla de acceso «cada comercial ve sus pedidos». Los ejemplos usan el modelo `sale.order` (pedido de venta) y `res.partner` (contacto). Una búsqueda con dominio devuelve un [recordset](../fundamentos/Recordsets.md).

## La condición y la lista

Una condición es una tupla de tres elementos: el campo, el operador y el valor.

```python
[('state', '=', 'sale')]   # pedidos confirmados
```

Una lista con varias condiciones las combina con **AND**:

```python
# state = 'sale' AND amount_total > 100
[('state', '=', 'sale'), ('amount_total', '>', 100)]
```

La lista vacía `[]` no filtra nada: devuelve todos los registros. El código de `Domain` la trata como el dominio «verdadero» (`arg == []` devuelve `_TRUE_DOMAIN` en `odoo/orm/domains.py`, rama 20.0).

El primer elemento de la condición se llama, en el código, *field expression*: normalmente es un nombre de campo, pero puede ser una ruta (ver más abajo). Para lanzar la búsqueda desde Python:

```python
pedidos = env['sale.order'].search([('state', '=', 'sale')])
```

`search` acepta además `offset`, `limit` y `order`; el dominio solo decide **qué** registros entran, no su orden ni su agrupación (`search` en `odoo/orm/models.py`, rama 20.0).

### Los registros archivados no entran por defecto

Si el modelo tiene campo `active`, `search` añade por su cuenta la condición `active = True`, salvo que el dominio ya mencione ese campo o el contexto lleve `active_test=False`. Se lee en `_search` (`odoo/orm/models.py`, rama 20.0): la condición se antepone solo si ninguna condición del dominio usa el campo de activo. Por eso `[('active', '=', False)]` devuelve archivados, y por eso un dominio sin `active` no los devuelve aunque cumplan el resto.

## Operadores

La documentación oficial de la ORM API 20.0 ([Search domains](https://www.odoo.com/documentation/20.0/developer/reference/backend/orm.html)) lista estos operadores válidos:

| Operador | Significado | Ejemplo |
|---|---|---|
| `=`, `!=` | igual, distinto | `('state', '!=', 'cancel')` |
| `<`, `<=`, `>`, `>=` | comparación | `('amount_total', '>=', 500)` |
| `=?` | «sin valor o igual»: si el valor es `None`/`False` la condición se cumple siempre; si no, se comporta como `=` | `('partner_id', '=?', partner_id)` |
| `in`, `not in` | pertenece a una colección de valores | `('state', 'in', ['draft', 'sent'])` |
| `like`, `not like` | coincide con `%valor%` | `('name', 'like', 'S004')` |
| `ilike`, `not ilike` | como `like`, sin distinguir mayúsculas | `('name', 'ilike', 'cafés')` |
| `=like`, `not =like` | coincide con el patrón tal cual (`_` = un carácter, `%` = cualquier cadena) | `('name', '=like', 'S004%')` |
| `=ilike`, `not =ilike` | como `=like`, sin distinguir mayúsculas | `('name', '=ilike', 's004%')` |
| `child_of`, `parent_of` | descendiente / ascendiente de un registro, siguiendo `_parent_name` | `('category_id', 'child_of', cat_id)` |
| `any`, `not any` | alguno de los registros de la relación cumple un subdominio | `('order_line', 'any', [('product_uom_qty', '>', 10)])` |
| `any!`, `not any!` | como `any`, saltándose los controles de acceso | (de uso interno) |

La diferencia entre `like` y `=like` es el comodín: `like` añade `%` a ambos lados del valor y `=like` usa el patrón exactamente como se escribe, de modo que `'S004%'` solo encuentra nombres que *empiezan* por `S004`.

Dos precisiones que se leen en el código (`odoo/orm/domains.py`, rama 20.0):

- Las condiciones con `in` y `not in` sobre una colección vacía no son errores: `in []` se reescribe como dominio falso y `not in []` como verdadero (`_optimize_in_set`). Si un dominio se construye a partir de una lista que puede quedar vacía, `('id', 'in', ids)` con `ids == []` devuelve cero registros.
- `=` y `!=` con una colección como valor funcionan, pero el código registra el aviso *«should use the 'in' or 'not in' operator»*: el operador correcto para listas es `in`.

### `child_of` y `parent_of`: jerarquías

Los modelos con jerarquía (etiquetas de contacto con padre, categorías de producto) declaran una relación padre; `child_of` trae el registro y toda su descendencia sin recorrer el árbol a mano:

```python
# contactos con la etiqueta «Hostelería» o cualquiera de sus subetiquetas
env['res.partner'].search([('category_id', 'child_of', etiqueta.id)])
```

El valor puede ser un id, una lista de ids o un texto (en cuyo caso el código busca por `display_name` con `ilike`). Si el modelo declara `_parent_store = True`, el código resuelve la descendencia con una condición `parent_path =like '<ruta>%'`; si no, recorre la relación nivel a nivel (`_operator_child_of_domain`, rama 20.0). La documentación de `_parent_store` indica que `parent_path` debe declararse con `index=True` para que funcione bien. Aplicado a un campo que no es relacional (ni `id`), el código lanza un error con el texto *«Cannot execute child_of for <campo>, works only for relational fields»* (con `parent_of` en su caso).

## Combinar con OR y NOT: notación polaca

Los operadores lógicos van en **notación prefija** (polaca): primero el operador, después los operandos a los que afecta. `&` y `|` toman **exactamente dos** operandos; `!` toma uno.

```python
# state = 'sale' OR state = 'sent'
['|', ('state', '=', 'sale'), ('state', '=', 'sent')]

# NOT (state = 'cancel')
['!', ('state', '=', 'cancel')]
```

El docstring de `odoo/orm/domains.py` da un ejemplo con anidación: `['&', '!', <cond>, '|', <cond2>, <cond3>]` equivale a `(not <cond1>) and (<cond2> or <cond3>)`.

### El AND implícito

Cuando dos expresiones van seguidas sin operador entre ellas, Odoo las une con AND. La lista `[A, B]` es lo mismo que `['&', A, B]`. La documentación 20.0 lo muestra al serializar un dominio: `list(Domain([('name', '=', 'abc'), ('phone', 'like', '7620')]))` da `['&', ('name', '=', 'abc'), ('phone', 'like', '7620')]`.

Ese AND implícito es la fuente del error más frecuente: un `|` solo captura las dos expresiones que le siguen, y lo que venga después queda unido con AND.

```python
A = ('state', '=', 'sale')
B = ('state', '=', 'sent')
C = ('amount_total', '>', 100)

# ❌ se lee «A o B o C», pero significa (A o B) y C
['|', A, B, C]

# ✅ dos «o» para tres operandos
['|', '|', A, B, C]
```

Para `N` operandos unidos con OR hacen falta `N - 1` signos `|`, escritos **antes** de todos. El código de `Domain.__new__` procesa la lista de derecha a izquierda con una pila: `|` toma las dos expresiones siguientes, y las que sobran se unen con `Domain.AND` (`return Domain.AND(reversed(stack))`). Con `['|', A, B, C]` la pila acaba con `C` y `(A | B)`, que se unen con AND.

Un operador al que le faltan operandos produce `ValueError: Domain() malformed domain [...]` (el `IndexError` de la pila se convierte en ese mensaje).

Lo mismo con `!`: afecta solo a la expresión siguiente.

```python
# ❌ NOT solo afecta a A: es (NOT A) AND B
['!', A, B]

# ✅ NOT (A AND B)
['!', '&', A, B]
```

### Demostración: normalizar el AND implícito

La función siguiente es una demostración de lógica pura en Python estándar, no código de Odoo: convierte un dominio con AND implícitos en uno con todos los `&` explícitos, para ver cómo se agrupa de verdad. Se ejecutó con Python normal, sin instancia de Odoo; su salida no es la de `list(Domain(...))`, aunque coincide con el ejemplo de dos condiciones de la documentación.

```python
def _parse(items, pos):
    """Lee una expresión que empieza en items[pos]; devuelve (árbol, siguiente_pos)."""
    if pos >= len(items):
        raise ValueError("dominio mal formado: faltan operandos")
    item = items[pos]
    if item == "!":
        arg, pos = _parse(items, pos + 1)
        return ("!", arg), pos
    if item in ("&", "|"):
        left, pos = _parse(items, pos + 1)
        right, pos = _parse(items, pos)
        return (item, left, right), pos
    if isinstance(item, (tuple, list)) and len(item) == 3:
        return tuple(item), pos + 1
    raise ValueError(f"elemento no válido: {item!r}")


def _emit(node):
    if node[0] in ("&", "|"):
        return [node[0], *_emit(node[1]), *_emit(node[2])]
    if node[0] == "!":
        return ["!", *_emit(node[1])]
    return [node]


def normalizar(dominio):
    """Devuelve el dominio con todos los AND implícitos escritos como '&'."""
    if not dominio:
        return []
    pos, nodos = 0, []
    while pos < len(dominio):
        nodo, pos = _parse(dominio, pos)
        nodos.append(nodo)
    arbol = nodos[0]
    for siguiente in nodos[1:]:
        arbol = ("&", arbol, siguiente)
    return _emit(arbol)
```

Salida literal de ejecutarla con las `A`, `B` y `C` de arriba (se abrevian las tuplas como `A`, `B`, `C`):

```text
[A, C]               ->  ['&', A, C]
['|', A, B, C]       ->  ['&', '|', A, B, C]
['|', '|', A, B, C]  ->  ['|', '|', A, B, C]
['!', A, C]          ->  ['&', '!', A, C]
['|', A]             ->  ValueError: dominio mal formado: faltan operandos
```

La segunda línea muestra el error: el dominio que parecía «de tres OR» queda como `&` de un `|` y un tercer operando. Es una forma de comprobar un dominio dudoso sin abrir Odoo.

## Campos con ruta

El campo de una condición puede ser una ruta con puntos que atraviesa relaciones. La documentación 20.0 la describe como un recorrido por un `Many2one` con notación de punto (`'partner_id.country'`), y el docstring de `odoo/orm/domains.py` aclara que recorrer relaciones equivale a usar el operador `any`.

```python
# pedidos de clientes cuyo país tiene el código «ES»
[('partner_id.country_id.code', '=', 'ES')]

# equivalente con any, útil cuando la relación es One2many o Many2many
[('partner_id', 'any', [('country_id.code', '=', 'ES')])]
```

Para un `One2many` o un `Many2many` (como `order_line`), el operador `any` es la forma explícita y documentada: *«pedidos que tienen al menos una línea de más de 10 unidades»* se escribe `('order_line', 'any', [('product_uom_qty', '>', 10)])`. La documentación incluye un ejemplo equivalente (`Domain('order_line', 'any', Domain('product_id.qty_available', '<=', 0))`). El subdominio de `any` es otro dominio completo, con su propio `&` y `|`.

En campos de fecha, la ruta admite una granularidad: `('birthday.month_number', '=', 2)` selecciona cumpleaños de febrero. Las granularidades soportadas son `year_number`, `quarter_number`, `month_number`, `iso_week_number`, `day_of_week`, `day_of_month`, `day_of_year`, `hour_number`, `minute_number` y `second_number`, y todas comparan con un entero.

## Valores especiales

### `False` es «sin valor»

Para «campo vacío» el valor es `False`, tanto en campos relacionales como en texto, fecha o número:

```python
[('partner_id', '=', False)]    # pedidos sin cliente
[('partner_id', '!=', False)]   # pedidos con cliente
```

El código convierte `None` en `False` al construir la condición (`if value is None: value = False` en `DomainCondition.checked`), así que ambos valen. En fechas, una comparación de orden contra `False` (`<`, `>`…) da un dominio falso, no un error (`_optimize_type_date`).

La documentación define `=?` como «sin valor o igual». Es útil para filtros opcionales: `('partner_id', '=?', partner_id)` no filtra si `partner_id` es `False`.

### Registros como valores

Un registro no debe viajar dentro de un dominio: hay que pasar su `.id`. El código registra el aviso *«should not have a value which is a model»* y lo sustituye por `value.ids`, y un `NewId` (registro aún sin guardar) lo convierte en una lista vacía con otro aviso. Que el ORM compense el descuido no significa que convenga apoyarse en él; ver [Recordsets](../fundamentos/Recordsets.md) para el caso de comparar un recordset con un id.

### Fechas

Sobre campos `Date` se compara con objetos `date` o con cadenas ISO `'2026-11-01'`; sobre `Datetime`, con `datetime` sin zona horaria. Si se pasa solo una fecha a un campo `Datetime`, el código la interpreta como medianoche en la zona horaria del usuario y la convierte a UTC (`_value_to_datetime`). Un `datetime` con zona horaria emite el aviso *«Use naive datetimes in domains»*.

La documentación 20.0 añade un lenguaje de **valores temporales relativos** como cadenas, evaluados en la zona horaria del usuario:

```python
Domain('some_date', '<', 'today')        # hoy a medianoche
Domain('some_date', '<', '-3d +1H')      # ahora - 3 días + 1 hora
Domain('some_date', '>=', '=monday -1w') # lunes de la semana anterior
```

Cada término empieza por `+` (sumar), `-` (restar) o `=` (fijar), seguido de un entero y una unidad (`d`, `w`, `m`, `y`, `H`, `M`, `S`) o de un día de la semana en minúsculas. Esta sintaxis está en la documentación 20.0 y no se localizó en el código de la rama 19.0 (`odoo/orm/domains.py`); no se verificó en versiones anteriores.

## Dónde se escribe un dominio

El mismo dominio aparece en cinco sitios, con diferencias en **quién lo evalúa** y **con qué variables**:

| Sitio | Ejemplo | Quién lo evalúa |
|---|---|---|
| Código Python | `self.env['sale.order'].search(dominio)`, `search_read(dominio, fields)` | El servidor; el dominio ya es una lista |
| Recordsets en memoria | `pedidos.filtered_domain(dominio)` | El servidor, sin consultar la base de datos |
| Atributo `domain` de un campo en una vista XML, o de un `Many2one` en Python | `domain="[('is_company', '=', True)]"` | El navegador, con los valores del formulario |
| Acciones de ventana (`domain` de la acción) | `[('state', '=', 'sale')]` | El navegador, al abrir la acción |
| Reglas de acceso por registro | `[('user_id', '=', user.id)]` | El servidor, en cada consulta |

`filtered_domain` aplica el dominio a un recordset ya cargado y conserva el orden: devuelve `self` si el recordset o el dominio están vacíos y, si no, evalúa el dominio como predicado sobre cada registro (`odoo/orm/models.py`, rama 20.0). El comentario de `Domain.contains` en el cliente web (`core/domain.js`) avisa de que la versión JavaScript no maneja bien operadores como `any` o `child_of`; la del servidor sí los resuelve.

Los dominios de los filtros de las vistas de búsqueda y del panel lateral se declaran en XML; se tratan en [Vista de búsqueda](Vista-de-Busqueda.md) y [Search Panel](Search-Panel.md), y los que cambian según el contexto, en [Dominios dinámicos](Dominios-Dinamicos.md).

### Un dominio como cadena en XML

En un fichero XML el dominio es texto con sintaxis de Python, y **el navegador lo evalúa**, no el servidor. Por eso, a diferencia de un dominio en Python, puede contener expresiones:

```xml
<field name="partner_id" domain="[('is_company', '=', True)]"/>
```

Variables disponibles según el código del cliente web (`addons/web/static/src/`, rama 20.0):

- **En un campo de un formulario**: los valores de los campos del registro (por nombre), `parent` (el registro padre, dentro de líneas), `context`, `uid`, `allowed_company_ids` y `current_company_id` (`getBasicEvalContext` y `Record._setEvalContext`, en `model/relational_model/`).
- **En el dominio de una acción**: el contexto del usuario más el contexto de la acción, con `uid` incluido (`_preprocessAction` en `webclient/actions/action_plugin.js`).
- **En ambos**, además, los nombres del intérprete de Python del cliente (`core/py_js/py_builtin.js`): `time` (con `strftime`), `context_today()`, `today` y `current_date` (este último marcado como obsoleto en el código), `now`, `datetime` (con `datetime`, `date`, `time` y `timedelta`) y `relativedelta`, además de `true` y `false`. Todo lo demás de Python no existe: el cliente trae su propio intérprete, no ejecuta Python.

Con esas variables, «pedidos de los últimos 30 días» se expresa así (la expresión se compuso a partir de los nombres anteriores; no se ejecutó):

```xml
domain="[('date_order', '>=', (context_today() - relativedelta(days=30)).strftime('%Y-%m-%d'))]"
```

Dos consecuencias prácticas: en XML, `<` debe escribirse `&lt;` dentro del atributo (es XML); y los campos que el dominio usa tienen que estar presentes en la vista, porque el evaluador solo conoce los campos cargados.

### Reglas de acceso por registro

Las reglas que limitan qué registros ve cada grupo también son dominios, pero los evalúa el servidor con otras variables. En 20.0 la documentación de seguridad ([Security](https://www.odoo.com/documentation/20.0/developer/reference/backend/security.html)) describe el campo `domain` de `ir.access` como una expresión de Python que puede usar `time`, `user` (el usuario actual como recordset de un registro), `company_id` (id de la compañía seleccionada, no un recordset) y `company_ids` (lista de ids de compañías accesibles). Ejemplo: `[('user_id', '=', user.id)]`. Cuando el campo `domain` está vacío, la regla equivale a `[]`: se aplica a todos los registros del modelo.

## `Domain` como API de composición

En la rama 20.0, `odoo/orm/domains.py` define una clase `Domain` que representa el dominio como un árbol de expresiones, y la documentación 20.0 la presenta como constructor de dominios. La clase ya existe en 19.0 (`class Domain` en `odoo/orm/domains.py`); en 18.0 el fichero no existe y la lógica vive en `odoo/osv/expression.py`.

```python
from odoo.fields import Domain

d1 = Domain('state', '=', 'sale')
d2 = Domain('amount_total', '>', 100)

d1 & d2          # AND
d1 | d2          # OR
~d1              # NOT
Domain.AND([d1, d2, Domain('partner_id', '!=', False)])
Domain.OR([d1, d2])
Domain.TRUE      # el dominio que siempre se cumple
Domain.FALSE
```

La importación `from odoo.fields import Domain` es la que usa `addons/sale/models/sale_order.py` en la rama 20.0 (`from odoo.fields import Command, Domain`). `search` y `filtered_domain` aceptan indistintamente una lista o un `Domain`: `Domain(domain)` normaliza ambos (`filtered_domain`, `_search`).

Propiedades útiles de la clase, según el código:

- **Inmutable**: modificar un atributo lanza `TypeError("Domain objects are immutable")`.
- **No hashable**: `hash(domain)` lanza `NotImplementedError("Domains are not hashable")`.
- **Se convierte en lista**: `list(domain)` devuelve la lista en notación polaca, con los `&` explícitos (así lo documenta el ejemplo de `['&', ('name', '=', 'abc'), ...]`).
- `bool(domain)` es `False` solo para el dominio verdadero (`[]`): una trampa conocida de la clase, marcada como pendiente de deprecación en el código (usar `is_true()` / `is_false()`).
- `Domain + lista` concatena como listas, «por compatibilidad hacia atrás»; el comentario del código lo señala como candidato a deprecación. La forma recomendada es `&`/`|` o `Domain.AND`/`Domain.OR`.

Componer con `&`/`Domain.AND` evita el error del OR y el NOT de la sección anterior: el operador une dominios completos, no hay que contar operandos. Cuando hay que combinar un dominio que llega de fuera con otro propio, `Domain.AND([externo, propio])` acepta listas, tuplas y dominios mezclados.

## Rendimiento

El dominio se traduce a una consulta SQL, así que lo que importa es si PostgreSQL puede apoyarse en un índice. Lo siguiente es razonamiento sobre la traducción y sobre lo que dice la documentación de los campos; no se midió en ninguna base de datos.

- **Un campo sin índice** se filtra recorriendo la tabla. La documentación de `index` en la ORM API distingue `"btree"` (índice estándar), `"btree_not_null"` (sin valores nulos; útil cuando la mayoría son nulos o no se busca por nulo) y `"trigram"` (índice GIN con trigramas, pensado para búsquedas de texto). Sin esas declaraciones, `('state', '=', 'sale')` solo es rápido si el campo tiene índice: `state` de `sale.order` lo declara (`index=True` en `addons/sale/models/sale_order.py`, rama 20.0).
- **`=`, `in` y comparaciones** sobre un campo con índice btree son las condiciones que un índice puede resolver. `=like` con un patrón que empieza por texto fijo (`'S004%'`) es el candidato de un índice de prefijo en PostgreSQL; con `%` al principio no lo es.
- **`like` e `ilike`** envuelven el valor en `%…%`, es decir, el patrón empieza por comodín: un índice btree no ayuda y la tabla se recorre, salvo que el campo tenga índice `trigram`. En `ilike` y `=ilike` el código usa además `unaccent` (comentario de `STANDARD_CONDITION_OPERATORS`).
- **Las rutas con punto** (`partner_id.country_id.code`) equivalen a `any` según el docstring del código: el filtro final recae sobre el modelo relacionado, así que el coste depende de los índices de ese modelo, y cada nivel de la ruta añade uno. Por ejemplo, `country_id` de `res.partner` declara `index='btree_not_null'` (`odoo/addons/base/models/res_partner.py`, rama 20.0).
- **`child_of`** sobre un modelo con `_parent_store` se resuelve con `parent_path =like 'ruta%'`, que aprovecha un índice sobre `parent_path` (la documentación exige `index=True` ahí); sin `_parent_store`, el código recorre el árbol nivel a nivel con una consulta por nivel.
- **Los dominios negativos** (`!=`, `not in`, `not like`) rara vez se apoyan bien en un índice; si el modelo tiene pocos valores posibles, es más claro y más rápido listar los que sí interesan con `in`.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| El filtro devuelve registros que no deberían entrar (o muestra más de lo esperado) | `['|', A, B, C]` es `(A o B) y C`; faltaba un segundo `|` |
| Un `!` no niega lo que se esperaba | `!` solo afecta a la expresión siguiente; usar `['!', '&', A, B]` para negar un conjunto |
| `ValueError: Domain() malformed domain [...]` | Un operador sin operandos suficientes (`['|', A]`) o un `&`/`|` colgado al final |
| `ValueError: Domain() invalid item in domain: ...` | Un elemento que no es tupla/lista de tres, ni `&`, `|`, `!` |
| `ValueError: Invalid operator in condition (...)` | El operador no está en la lista de operadores (`CONDITION_OPERATORS`), p. ej. un error de escritura. El mensaje termina con la condición completa |
| `ValueError: Invalid field <modelo>.<campo> in condition (...)` | El campo no existe en el modelo; suele ser un nombre mal escrito o un campo de otro módulo no instalado |
| `UserError: Unsupported operator on <campo> <modelo> in <dominio>` | El operador no es válido para ese campo (por ejemplo, un campo calculado sin método de búsqueda para ese operador) |
| La búsqueda ignora los registros archivados | `search` añade `active = True` si el dominio no menciona `active`; usar `('active', 'in', [True, False])` o `with_context(active_test=False)` |
| Un filtro por lista no devuelve nada | `('id', 'in', [])` con lista vacía se reescribe como dominio falso |
| Error al evaluar un dominio en el navegador, o un campo del dominio «no existe» | El dominio XML usa un campo que la vista no carga; añadir el campo (puede ir con `invisible="1"`) |
| Aviso en el log: *should not have a value which is a model* | Se pasó un recordset en lugar de `.id` / `.ids` |

Sobre la versión: el mensaje `Invalid leaf %s`, que aparece en búsquedas sobre Odoo 18.0, está en `odoo/osv/expression.py` (rama 18.0, `raise ValueError("Invalid leaf %s" % str(element))`). No existe en `odoo/orm/domains.py` de la rama 20.0, donde los equivalentes son los mensajes de la tabla anterior (`Invalid operator`, `Invalid field`, `malformed domain`).

## Buenas prácticas avanzadas

- **Compón con `Domain`, no con listas concatenadas.** `Domain.AND([externo, propio])` o `d1 & d2` unen árboles completos; unir con `['|'] + d1 + d2` solo funciona mientras `d1` sea una única condición: con dos condiciones, el `|` se queda con la primera y la segunda se une por AND. El propio código marca `Domain + lista` como pendiente de deprecación.
- **No uses `bool(domain)` para saber si hay filtro.** En un `Domain` solo el dominio verdadero es falso, y el código lo señala como uso por compatibilidad; usa `is_true()` o `is_false()`.
- **Normaliza antes de depurar.** Si un OR no hace lo que parece, escribe los `&` implícitos (la demostración de arriba, o `list(Domain(dominio))` en 19.0/20.0) y lee el resultado: el error de agrupación se ve a la primera.
- **Pasa ids, no recordsets.** Un registro dentro de un dominio funciona por una conversión con aviso en el log (`value.ids`); usar `.id`/`.ids` desde el principio evita el aviso y evita que un `NewId` se convierta silenciosamente en una lista vacía.
- **Ten en cuenta `active_test` en cada búsqueda.** `search` añade `active = True` si el dominio no menciona `active`; en `child_of` sobre un `Many2one`, el código busca con `active_test=False` en el modelo relacionado (`_operator_hierarchy`), de modo que un padre archivado cuenta en la jerarquía aunque no en un listado, y la documentación de `any` indica lo mismo para un subdominio sobre un `Many2one`.
- **Prefiere `any` explícito en `One2many`/`Many2many`.** Dice qué se comprueba (alguna línea, no todas) y el subdominio puede llevar sus propios `&` y `|`.

## Documentación oficial

- [ORM API — Search domains](https://www.odoo.com/documentation/20.0/developer/reference/backend/orm.html) — la referencia de operadores, de la clase `Domain` y del lenguaje de fechas relativas. Buscar la sección «Search domains» en la página.
- [Security in Odoo](https://www.odoo.com/documentation/20.0/developer/reference/backend/security.html) — describe el dominio de los permisos por registro y las variables que ve (`time`, `user`, `company_id`, `company_ids`).
- [`odoo/orm/domains.py`, rama 20.0](https://github.com/odoo/odoo/blob/20.0/odoo/orm/domains.py) — el código fuente de `Domain` y de la lista de operadores; el docstring inicial explica la notación polaca y la lista de optimizaciones es la fuente de verdad de lo que hace cada operador.

## Recursos didácticos

El editor de dominios del cliente web muestra, en modo desarrollador, un cuadro «Code editor» con el dominio como texto (`domain_selector_dialog.xml`, rama 20.0): una forma cómoda de comprobar cómo se escribe un filtro armado con clics. Cómo activar el modo desarrollador: [Modo desarrollador](../fundamentos/Modo-Desarrollador.md).

---

*En resumen: un dominio es el `WHERE` de Odoo escrito como lista de condiciones `(campo, operador, valor)` unidas con AND de forma implícita; lo que no se ve es que `|` y `!` solo afectan a las expresiones inmediatas, y la forma segura de combinarlos es `Domain` o escribir los `&` a la vista.*
