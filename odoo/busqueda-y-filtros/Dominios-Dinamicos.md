# Dominios dinámicos

## ¿Qué es?

Un **dominio dinámico** es un filtro que no está fijado de antemano, sino que se calcula en el momento de usarlo a partir de algo que cambia: el valor de otro campo del formulario, el usuario conectado, la fecha de hoy o un valor del contexto. En vez de «ofrece siempre estos registros», dice «ofrece los que correspondan ahora».

Un **dominio** (la lista de condiciones `[('campo', 'operador', valor)]` con la que Odoo filtra registros) se explica en [Dominios](Dominios.md). Aquí interesa la parte que se recalcula.

Referencias de código y documentación: rama estable `20.0` de `github.com/odoo/odoo` (HEAD `4611da65a7`, leído el 2026-11-10) y documentación 20.0; las versiones 19.0 y 18.0 siguen con soporte estándar según la [página de versiones soportadas](https://www.odoo.com/documentation/20.0/administration/standard_extended_support.html). No se ejecutó ninguna instancia de Odoo: cada afirmación procede de un fichero o página leídos y citados. Lo que no se pudo contrastar se marca como «no verificado».

## ¿Por qué existe?

Una pequeña empresa como «Cafés del Valle» registra pedidos de venta (el S00042, por ejemplo) y guarda varios contactos por cliente. En un pedido, el campo «contacto de entrega» debería ofrecer solo los contactos del cliente elegido arriba, no los de los demás clientes. Qué contactos son válidos depende de un valor que solo se conoce mientras se rellena el formulario, y un filtro fijo no puede expresarlo.

> Si ya conoces los desplegables encadenados «país → provincia → ciudad», es lo mismo: cada selector se recalcula en función del anterior.

## ¿Cuándo y para qué se usa?

- **Selectores dependientes**: contactos del cliente del pedido, responsables del equipo elegido, productos de la categoría seleccionada.
- **Filtros por usuario o empresa**: ofrecer solo registros de las empresas activas del usuario.
- **Filtros por fecha relativa**: «pedidos de los últimos 30 días», que mañana significa otro intervalo.
- **Filtrar por un campo calculado sin columna** en la base de datos: eso se resuelve con un método `search` en el campo, no con un dominio dinámico, y se trata en «Qué no es un dominio dinámico».

## Cómo funciona: el dominio viaja como texto y lo evalúa el navegador

En el cliente web, un dominio dinámico es una **expresión en sintaxis Python que el navegador evalúa** cada vez que el campo necesita los candidatos. El servidor no la ejecuta: el intérprete es JavaScript (`addons/web/static/src/core/py_js/`, rama 20.0), una implementación reducida de Python. Admite lo habitual (listas, tuplas, comparaciones, `and`/`or`, la expresión condicional `a if c else b`), pero no es Python completo: no se puede llamar a métodos del ORM ni a funciones propias.

Las variables disponibles dentro de la expresión son las del navegador, no las del servidor:

| Variable | Qué contiene | Fuente |
|---|---|---|
| Nombre de cualquier campo presente en la vista | El valor actual en el formulario, aunque no esté guardado. Un `Many2one` llega como su id (o `False` si está vacío); un `One2many`/`Many2many`, como lista de ids; una fecha, como cadena `YYYY-MM-DD` | `record.js`, `_computeDataContext` |
| `id` | El id del registro (`False` si es nuevo) | `record.js`, `_computeDataContext` |
| `parent` | El registro que contiene la línea; solo dentro de subvistas de campos relacionales | Documentación, «Python expression» de las arquitecturas de vista |
| `uid` | Id del usuario actual | `utils.js`, `getBasicEvalContext` |
| `context` | El contexto (diccionario) de la vista | `utils.js`, `getBasicEvalContext` |
| `allowed_company_ids`, `current_company_id` | Ids de las empresas activas y la empresa activa | `utils.js`, `getBasicEvalContext` |
| `context_today()`, `today`, `now`, `time`, `datetime`, `relativedelta` | La fecha y hora locales, y utilidades de fechas | `py_builtin.js`, `BUILTINS` |

Dos detalles de esa tabla importan en la práctica. Primero, `context_today()` devuelve un objeto fecha, mientras que `today` es la cadena `'2026-11-10'`; para comparar con un campo de fecha hace falta una cadena (`today`, o `context_today().strftime('%Y-%m-%d')`). `current_date` también existe, pero el propio código lo marca como obsoleto en favor de `today`. Segundo, solo están los campos **presentes en la vista**: si el dominio usa `partner_id`, ese campo debe estar en el formulario, aunque sea oculto.

## Vía 1: atributo `domain` del campo en la vista XML

Es la vía más común. Una frase que la introduce: el atributo `domain` de `<field>` contiene una expresión que se evalúa contra el registro que se está editando.

```xml
<field name="partner_id"/>
<field name="delivery_contact_id"
       domain="[('parent_id', '=', partner_id)]"/>
```

Qué hace: al abrir el selector de «Contacto de entrega», el navegador sustituye `partner_id` por el id del cliente elegido (por ejemplo, el de Cafés del Valle) y busca solo contactos cuyo `parent_id` sea ese. Si se cambia el cliente, el selector muestra otros candidatos la siguiente vez que se abre. El código lo confirma: el dominio se envuelve en una función que se llama en cada búsqueda del selector (`getFieldDomain` en `utils.js` y `domain()` en `field.js`), por lo que no queda fijado al cargar el formulario.

Sin variables del registro, el mismo atributo sirve para filtros por usuario, empresa o fecha:

```xml
<!-- Empleados de las empresas activas del usuario -->
<field name="responsible_id"
       domain="[('company_id', 'in', allowed_company_ids)]"/>

<!-- Pedidos de los últimos 30 días -->
<field name="origin_order_id"
       domain="[('date_order', '>=', (context_today() - relativedelta(days=30)).strftime('%Y-%m-%d'))]"/>
```

Dentro de las líneas de un pedido (subvista de un `One2many`), `parent` da acceso a los campos del pedido:

```xml
<field name="order_line">
    <list editable="bottom">
        <field name="product_id"
               domain="[('company_id', 'in', [parent.company_id, False])]"/>
    </list>
</field>
```

La documentación de las vistas ([arquitecturas de vista, sección «Python expression» y atributo `domain`](https://www.odoo.com/documentation/20.0/developer/reference/user_interface/view_architectures.html)) da el ejemplo `domain="[('fname_a', '=', parent.fname_b)]"` y describe el `domain` como «los filtros a aplicar al mostrar registros existentes para su selección».

## Vía 2: `domain` en la definición Python del campo

Si el filtro debe valer en todas las vistas donde aparezca el campo, se declara una vez en el modelo. El parámetro `domain` acepta una lista, una cadena o una función; la documentación lo describe como «un dominio para los valores candidatos en el lado cliente (dominio o expresión Python que se evaluará para dar un dominio)» (ORM, campos relacionales, 20.0).

**Como cadena**: es la misma expresión que en la vía 1, evaluada por el navegador.

```python
delivery_contact_id = fields.Many2one(
    'res.partner',
    domain="[('parent_id', '=', partner_id)]")
```

El servidor no la interpreta. En `get_comodel_domain` (`odoo/orm/fields_relational.py`, rama 20.0) una cadena se trata como dominio vacío en el servidor, con el comentario «domain=str is used only for the client-side». La cadena se envía tal cual al cliente (`_internal_description_domain_raw`).

**Como función**: se evalúa en el servidor, recibe el modelo del campo y devuelve una lista, un `Domain` o una cadena.

```python
responsible_id = fields.Many2one(
    'hr.employee',
    domain=lambda self: [('company_id', 'in', self.env.companies.ids)])
```

Qué hace: cuando el servidor describe el campo al cliente (`_description_domain`), llama a la función y envía la lista resultante. El valor sirve para lo que depende del **usuario o de la configuración**, no de otros campos del formulario: la función recibe el modelo, no el registro en edición. No se verificó con qué frecuencia el cliente vuelve a pedir esa descripción, por lo que no conviene confiar en que se reevalúe en cada apertura del selector.

Si el campo declara `check_company=True`, Odoo antepone automáticamente un dominio de empresa (`_description_domain`, mismo fichero): no hace falta escribirlo.

## Vía 3: dominios devueltos desde `@api.onchange`: ya no existe

Hasta la 16.0, un método `@api.onchange` podía devolver `{'domain': {'campo': [...]}}` para cambiar el dominio de otro campo. En 16.0 el código ya lo avisaba: registraba «onchange method … returned a domain, this is deprecated» (`odoo/models.py`, rama 16.0, `process` dentro de `onchange`).

En la rama 20.0 se ha dejado de procesar. El método que aplica los resultados de los `@onchange` (`_apply_onchange_methods`, `odoo/orm/models.py`) solo lee las claves `value` y `warning`; el resultado final que el servidor devuelve al cliente (`onchange` en `addons/web/models/models.py`) contiene `value` y `warning`; la documentación del decorador (`odoo/orm/decorators.py`) solo muestra `warning`. En la 17.0 el bloque correspondiente ya no recogía `domain` (leído en `odoo/models.py` de 17.0, que solo procesa `warning`; no se contrastó la nota de versión que lo eliminó).

```python
# ❌ En 20.0 la clave 'domain' se ignora sin error: el selector no se filtra
@api.onchange('partner_id')
def _onchange_partner_id(self):
    return {'domain': {'delivery_contact_id': [('parent_id', '=', self.partner_id.id)]}}
```

```xml
<!-- ✅ El equivalente: el dominio va en la vista y se reevalúa solo -->
<field name="delivery_contact_id" domain="[('parent_id', '=', partner_id)]"/>
```

Un `@api.onchange` sí sigue vigente para lo que le queda: asignar valores (por ejemplo, **vaciar** el contacto cuando cambia el cliente) y mostrar avisos. Esa limpieza es el complemento natural de la vía 1:

```python
@api.onchange('partner_id')
def _onchange_partner_id(self):
    if self.delivery_contact_id.parent_id != self.partner_id:
        self.delivery_contact_id = False
```

Otra forma de rellenar valores según otros campos es un campo calculado editable (`compute` + `store=True` + `readonly=False`); tampoco devuelve dominios.

## Dominios por usuario con reglas de registro

Para limitar qué registros **puede ver o modificar** cada usuario no se usa un dominio de campo, sino una regla de registro (`ir.rule`), cuyo dominio sí se evalúa en el servidor con las variables `user`, `company_id`, `company_ids` y `time` (documentación de [seguridad, «Record rules»](https://www.odoo.com/documentation/20.0/developer/reference/backend/security.html), 20.0). Por ejemplo, `[('company_id', 'in', company_ids)]`. La diferencia clave: una regla se aplica siempre, y el `domain` de un campo no.

## Qué vía elegir

| Necesidad | Vía | Motivo |
|---|---|---|
| El selector depende de otro campo del formulario | `domain` en la vista, o cadena en el campo | El navegador lo reevalúa al abrir el selector |
| Depende de un campo del pedido y estás en sus líneas | `domain` con `parent.campo` en la subvista | `parent` solo existe en subvistas |
| Depende del usuario o de las empresas activas, sin campos del formulario | `uid`/`allowed_company_ids` en la cadena, o función en el campo | Ambas valen; la cadena evita una descripción del campo con valores ya fijados |
| Debe aplicarse igual en todas las vistas | Cadena o función en la definición Python | Se declara una vez |
| Depende de la fecha de hoy | `context_today()`/`today` en la cadena | Se evalúa al abrir el selector |
| Un campo debe cambiar de valor al cambiar otro | `@api.onchange` (solo asigna valores) | No devuelve dominios |
| Hay que impedir el acceso a ciertos registros | `ir.rule`, no un dominio de campo | Es seguridad, no interfaz |
| El valor guardado debe cumplir el dominio | `@api.constrains` además del dominio | El dominio de campo no valida (ver «Errores frecuentes») |

## Qué no es un dominio dinámico

Filtrar por un campo calculado sin `store=True` no se resuelve con un dominio, sino dando al campo un método `search`, que traduce la condición a otras sobre campos almacenados:

```python
is_late = fields.Boolean(compute='_compute_is_late', search='_search_is_late')

def _search_is_late(self, operator, value):
    # Debe contemplar los operadores y valores recibidos, no solo ('=', True)
    ...
```

La documentación del ORM (20.0, «Field», apartado de `search`) indica que el método recibe el operador y el valor y devuelve un dominio que sustituye a la condición `(campo, operador, valor)`. Un campo calculado sin `search` ni almacenamiento no puede usarse en un dominio. El ejemplo de la documentación devuelve `Domain('partner_id.ref', operator, value)`.

## Errores frecuentes

**El selector sigue mostrando los candidatos de antes al cambiar el campo del que depende.**
Causa probable: el dominio es una función en Python (vía 2) y no una cadena. La función se evalúa en el servidor y no ve el formulario. Si el filtro depende de otro campo, tiene que ser una cadena o ir en la vista.

**El dominio no se aplica o falla al evaluarse.**
Causa: el campo del que depende no está en la vista (el mensaje exacto de error no se verificó). El cliente solo evalúa con los campos **presentes** en ella; añade el campo, aunque sea con `invisible="1"`.

**Se guardó un valor que no cumple el dominio.**
Causa: el `domain` de un `Many2one` filtra únicamente lo que ofrece el selector. En el código de `Many2one` (`fields_relational.py`, 20.0) ni `convert_to_column` ni `write` consultan el dominio, y la documentación lo define como un dominio «del lado cliente» para los candidatos. Escribir por código, importar un fichero o cambiar el cliente tras elegir el contacto deja un valor inválido sin error. Si se cambia el cliente después de elegir el contacto, el contacto antiguo sigue guardado. Dos medidas combinadas: vaciar el campo en un `@api.onchange` y validar con una restricción.

```python
@api.constrains('partner_id', 'delivery_contact_id')
def _check_delivery_contact(self):
    for order in self:
        contact = order.delivery_contact_id
        if contact and contact.parent_id != order.partner_id:
            raise ValidationError(
                "El contacto de entrega debe pertenecer al cliente del pedido.")
```

Excepción verificada: en un `One2many`, el dominio de campo en forma de lista sí se comprueba en el servidor al vincular líneas (`write` de los campos multivalor: lanza `ValueError("Cannot link inaccessible records …")`). Una cadena nunca se comprueba. El detalle de cuándo se alcanza este camino no se verificó.

**El dominio se vuelve «ofrece solo registros sin valor» cuando el campo está vacío.**
Causa: un `Many2one` vacío llega a la expresión como `False`, y `[('parent_id', '=', partner_id)]` pasa a ser `[('parent_id', '=', False)]`: contactos **sin** empresa padre, no «sin filtro» ni «ninguno». Hay que decidir qué significa el caso vacío y escribirlo:

```xml
<!-- ❌ Sin cliente elegido, ofrece los contactos sin empresa padre -->
<field name="delivery_contact_id" domain="[('parent_id', '=', partner_id)]"/>

<!-- ✅ Sin cliente elegido, no ofrece ninguno -->
<field name="delivery_contact_id"
       domain="[('parent_id', '=', partner_id)] if partner_id else [('id', '=', False)]"/>

<!-- ✅ Sin cliente elegido, sin restricción -->
<field name="delivery_contact_id"
       domain="[('parent_id', '=', partner_id)] if partner_id else []"/>
```

Ese `[]` y el `False` no son equivalentes. Un dominio vacío `[]` significa «todos»; la condición con `False` como valor compara con «sin valor». En el código de Python, `get_comodel_domain` trata un `domain` vacío o falso como `Domain.TRUE`, es decir, sin restricción.

**El filtro por fecha queda desfasado o falla al comparar.**
Causa: se compara un campo de fecha con el objeto `context_today()` en lugar de con una cadena. Usa `today` o `.strftime('%Y-%m-%d')`.

## Buenas prácticas avanzadas

- **Define qué significa el campo vacío en cada dominio que dependa de un `Many2one`.** `False` entra en la expresión como valor, no como ausencia de filtro. Escribe la rama `if campo else ...` explícitamente; el caso vacío es el más frecuente al crear un registro nuevo.
- **Un dominio de campo ayuda al usuario; la integridad la garantiza una restricción.** Si un valor fuera del dominio rompe algo (una entrega al contacto de otro cliente), añade `@api.constrains` y vacía el campo dependiente en un `@api.onchange`. El dominio solo no protege de la API, de las importaciones ni de cambios posteriores del campo del que depende.
- **No pongas un `@api.onchange` que devuelva `{'domain': ...}` en código nuevo ni lo conserves al migrar.** En 20.0 se ignora sin avisar. Al migrar un módulo desde la 16.0, busca esos retornos y sustitúyelos por `domain` en la vista.
- **Prefiere la cadena a la función cuando el dominio depende del registro.** La función se evalúa en el servidor con el modelo, no con el formulario; el valor solo se refresca cuando el cliente vuelve a pedir la descripción del campo.
- **No lleves lógica al dominio que el intérprete del navegador no sepa evaluar.** Es una implementación reducida de Python: nada de métodos del ORM ni de funciones propias. Si el cálculo es complejo, mételo en un campo calculado (por ejemplo, un `Boolean` o un `Many2many` auxiliar) y filtra por él.
- **Mantén el dominio dinámico y la regla de acceso como dos cosas distintas.** Una regla de registro (`ir.rule`) es la que impide ver o escribir; el `domain` de un campo solo guía la elección.

## Documentación oficial

- [Arquitecturas de vista](https://www.odoo.com/documentation/20.0/developer/reference/user_interface/view_architectures.html) — secciones «Python expression» (variables disponibles al evaluar) y el atributo `domain` de `<field>`.
- [API del ORM](https://www.odoo.com/documentation/20.0/developer/reference/backend/orm.html) — parámetro `domain` de los campos relacionales y método `search` de los campos calculados.
- [Seguridad en Odoo](https://www.odoo.com/documentation/20.0/developer/reference/backend/security.html) — reglas de registro y las variables de su dominio.
- [Código del evaluador en el cliente](https://github.com/odoo/odoo/tree/20.0/addons/web/static/src/core/py_js) — `py_builtin.js` muestra qué funciones y variables existen al evaluar un dominio.

Lecturas relacionadas de la colección: [Dominios](Dominios.md) (la sintaxis de las condiciones), [Vista de búsqueda](Vista-de-Busqueda.md) y [Search Panel](Search-Panel.md), donde también se aplican dominios; y [Recordsets](../fundamentos/Recordsets.md), para el tipo de lo que devuelven esas búsquedas.

---

*En resumen: un dominio dinámico es una expresión que el navegador reevalúa al abrir el selector, con los valores del formulario, el usuario y la fecha; no valida lo ya guardado, así que conviene una restricción además, y `@api.onchange` ya no sirve para cambiar dominios.*
