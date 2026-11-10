# Partner, Usuario y Empleado en Odoo

## ¿Qué es?

Odoo representa a una persona real con hasta tres registros de modelos distintos, cada uno con una
responsabilidad propia:

- `res.partner` (contacto): una ficha con nombre, dirección, email y datos fiscales. Puede ser una
  empresa o una persona. Es la base de clientes y proveedores.
- `res.users` (usuario): una cuenta con `login`, contraseña y permisos. Cada usuario cuelga de un
  contacto.
- `hr.employee` (empleado): la ficha laboral de quien trabaja en la empresa (departamento, puesto,
  jornada...). Es una pieza del módulo de Recursos Humanos (`hr`).

Los tres suelen describir a la misma persona, pero no son lo mismo y no siempre existen a la vez.

> Las citas de código proceden de la rama `20.0` de
> [github.com/odoo/odoo](https://github.com/odoo/odoo), la versión mayor más reciente según la
> página oficial de
> [soporte estándar y extendido](https://www.odoo.com/documentation/20.0/administration/standard_extended_support.html)
> (consultada el 2026-11-10: Odoo 20.0, lanzada en septiembre de 2026; también figuran en soporte
> 19.0, 18.0 y 17.0). Se leyeron los ficheros fuente; no se ejecutó ninguna instancia de Odoo, de
> modo que no hay salidas de consola ni capturas, y el código de ejemplo no se ha probado en
> ejecución.

## ¿Por qué existe?

Un ERP necesita hablar de personas en contextos muy distintos: a quién se le vende, quién puede
entrar al sistema, quién cobra una nómina. Meter todo en una sola tabla obligaría a que cada cliente
tuviera campos de contraseña y de departamento, y a que cada empleado fuera automáticamente un
cliente potencial. Odoo reparte esas responsabilidades: el contacto guarda los datos de identidad
y comunicación, el usuario añade el acceso, el empleado añade lo laboral.

> Si vienes de SQL o de un ORM clásico, piensa en tres tablas con claves foráneas entre ellas:
> `partner` es la tabla base de identidad; `users` y `employee` son extensiones que apuntan a
> ella, igual que una tabla `Account` y una tabla `Staff` apuntarían a una tabla `Person`.

## ¿Cuándo y para qué se usa?

El ejemplo conductor es una pequeña empresa que vende productos. Tiene un cliente, «Cafés del
Valle»; un pedido de venta, S00042; y una empleada, Ana Ruiz, que prepara pedidos y entra a Odoo
para confirmarlos. Preguntas de cada día:

- ¿A quién va dirigido el pedido S00042? A un contacto: el campo `partner_id` de `sale.order`
  es un `Many2one` a `res.partner` (`addons/sale/models/sale_order.py`, rama 20.0).
- ¿Quién es el comercial de ese pedido? A un usuario: `user_id` de `sale.order` es un `Many2one`
  a `res.users`, con la etiqueta «Salesperson».
- ¿En qué departamento trabaja Ana Ruiz? A un empleado: `department_id` vive en `hr.version`, el
  registro de datos laborales que `hr.employee` incorpora por delegación (ver más abajo).

## Los tres modelos, uno a uno

### `res.partner`: el contacto

Un contacto es una entidad con nombre que Odoo necesita conocer: una empresa («Cafés del Valle»),
una persona de contacto dentro de ella, o una dirección de entrega o de factura. No implica poder
entrar a Odoo ni trabajar en la empresa. Definiciones leídas en
`odoo/addons/base/models/res_partner.py` (rama 20.0):

```python
class ResPartner(models.Model):
    _name = 'res.partner'
    _description = 'Contact'
    _explanation = "Foundational model for all people and companies (customers, vendors, employees, etc.). Used for identifying individuals or organizations."
```

```python
parent_id: ResPartner = fields.Many2one('res.partner', string='Related Company', index=True)
child_ids: ResPartner = fields.One2many('res.partner', 'parent_id', string='Related Contacts', domain=[('active', '=', True)], context={'active_test': False})
is_company = fields.Boolean(string='Is a Company', default=False, compute="_compute_is_company", store=True,
    help="Check if the contact is a company, otherwise it is a person")
type = fields.Selection(
    [('contact', 'Contact'),
     ('invoice', 'Invoice'),
     ('delivery', 'Delivery'),
     ('other', 'Other'),
    ], string='Address Type',
    default='contact')
```

Qué dicen estos fragmentos:

- Un contacto puede colgar de otro mediante `parent_id` (la persona «Marta Gil» cuelga de la
  empresa «Cafés del Valle»). `child_ids` es el lado inverso.
- `type` distingue un contacto normal de una dirección de factura o de entrega, que también son
  filas de `res.partner` colgando de la empresa.
- En la rama 20.0, `is_company` es un campo calculado y almacenado: su método de cómputo lo deja a
  `True` cuando el contacto es su propia entidad comercial y tiene NIF (`has_vat`). El campo
  `company_id` del contacto (`fields.Many2one('res.company', 'Company', index=True)`) es opcional:
  vacío significa que el contacto es compartido entre todas las compañías.

Otros campos de identidad que aparecen en el mismo fichero: `email`, `phone`, `vat` («Tax ID»),
`ref`, `street`, `city`, `country_id`, `active`. Los módulos de ventas y contabilidad añaden más;
por ejemplo, `addons/account/models/partner.py` define `customer_rank` y `supplier_rank`
(enteros) que sirven para saber si un contacto actúa como cliente o proveedor: no existe un
modelo «cliente» aparte.

### `res.users`: la cuenta de acceso

Un usuario es quien puede autenticarse. El fichero `odoo/addons/base/models/res_users.py`
(rama 20.0) lo declara así:

```python
class ResUsers(models.Model):
    _name = 'res.users'
    _description = 'User'
    _explanation = "Represents a person who has access to the system. Users have login credentials, assigned groups for security permissions, and are linked to a partner record for contact information."
    _inherits = {'res.partner': 'partner_id'}
```

```python
partner_id = fields.Many2one('res.partner', required=True, ondelete='restrict', bypass_search_access=True, index=True,
    string='Related Partner', help='Partner-related data of the user')
login = fields.Char(required=True, help="Used to log into the system")
active = fields.Boolean(default=True)
share = fields.Boolean(compute='_compute_share', compute_sudo=True, string='Share User', store=True,
     help="External user with limited access, created only for the purpose of sharing data.")
company_id = fields.Many2one('res.company', string='Company', required=True, ...
    help='The default company for this user.', context={'user_preference': True})
company_ids = fields.Many2many('res.company', 'res_company_users_rel', 'user_id', 'cid',
    string='Companies', default=lambda self: self.env.company.ids)
group_ids = fields.Many2many('res.groups', 'res_groups_users_rel', 'uid', 'gid', string='Groups', ...
    help="Groups explicitly assigned to the user")
```

Los puntos que importan:

- `partner_id` es obligatorio (`required=True`): no hay usuario sin contacto. `ondelete='restrict'`
  impide borrar el contacto mientras exista el usuario.
- `login` es único: el fichero declara `_login_key = models.Constraint("UNIQUE (login)", 'You can
  not have two users with the same login!')`.
- Los permisos vienen de los grupos (`group_ids`). En la rama 18.0 este campo se llama `groups_id`
  y en 19.0 y 20.0 `group_ids`: el código escrito contra una versión puede no funcionar en otra.
- `company_id` es la compañía por defecto del usuario; `company_ids`, el conjunto de compañías a
  las que puede acceder.

#### La herencia por delegación (`_inherits`)

`_inherits = {'res.partner': 'partner_id'}` significa «herencia por delegación»: `res.users` no
copia las columnas de `res.partner` en su propia tabla; guarda una clave foránea (`partner_id`) y
expone los campos del contacto como si fueran suyos. Es lo contrario de la herencia de clase
habitual (`_inherit`), que añade campos al mismo modelo y a la misma tabla.

Evidencia en el propio fichero: bajo el comentario «overridden inherited fields to bypass access
rights, in case you have access to the user but not its corresponding partner», se redefinen así:

```python
name = fields.Char(related='partner_id.name', inherited=True, readonly=False, copy=True, user_writeable=True)
email = fields.Char(related='partner_id.email', inherited=True, readonly=False, user_writeable=True)
phone = fields.Char(related='partner_id.phone', inherited=True, readonly=False, user_writeable=True)
```

Es decir, `user.name` es un campo relacionado (`related='partner_id.name'`) que lee y escribe en el
contacto. Consecuencias:

```python
user = env["res.users"].browse(7)     # un usuario cualquiera (id inventado)
user.name                              # el mismo valor que user.partner_id.name
user.partner_id.email = "ana@example.com"   # equivale a user.email = "ana@example.com"
```

- Cambiar el nombre desde el usuario cambia el contacto, y viceversa: hay un solo dato, en
  `res_partner`.
- Todos los campos de `res.partner` son accesibles desde el usuario (`user.city`, `user.street`),
  aunque `res.users` no los declare.
- Lo contrario no es cierto: `partner.login` no existe. Para llegar del contacto al usuario se usa
  `user_ids` (ver más abajo).

### `hr.employee`: la ficha laboral

Un empleado es el registro de Recursos Humanos. Está en el módulo `hr`, que hay que instalar
(consulta [Módulos y Apps](Modulos-y-Apps.md)); sin él, `hr.employee` no existe. Definiciones de
`addons/hr/models/hr_employee.py` (rama 20.0):

```python
class HrEmployee(models.Model):
    _name = 'hr.employee'
    _description = "Employee"
    _inherits = {'hr.version': 'version_id'}
```

```python
user_id = fields.Many2one(
    'res.users', 'User',
    related='resource_id.user_id',
    store=True,
    readonly=False,
    check_company=True,
    ...
    ondelete='restrict',
    copy=False
)
company_id = fields.Many2one('res.company', required=True, tracking=True)
work_contact_id = fields.Many2one('res.partner', 'Work Contact', copy=False, index='btree_not_null')
```

```python
_user_uniq = models.Constraint(
    'unique (user_id, company_id)',
    'A user cannot be linked to multiple employees in the same company.',
)
```

Qué dicen:

- `user_id` es opcional (no hay `required=True`): un empleado puede no tener usuario. Se guarda a
  través de `resource_id` (el recurso planificable que el módulo `resource` asocia a cada
  empleado), pero se lee y se escribe como un campo normal del empleado.
- `work_contact_id` apunta al contacto de trabajo (`res.partner`); también es opcional en el
  esquema, pero el `create` garantiza que exista (ver «Qué se crea automáticamente»).
- `company_id` es obligatorio: un empleado pertenece a una compañía concreta.
- La restricción `_user_uniq` permite que un mismo usuario tenga un empleado por compañía, pero no
  dos en la misma.
- En 20.0, `hr.employee` delega los datos contractuales y de puesto en `hr.version`
  (`_inherits = {'hr.version': 'version_id'}`), el mismo mecanismo que `res.users` usa con el
  contacto. Por eso `department_id` y `job_id` están definidos en `addons/hr/models/hr_version.py`
  y no en `hr_employee.py`. En versiones anteriores a 20.0 no se verificó esta estructura.

## Cómo se relacionan

Quién apunta a quién, con las cardinalidades que dicta el código leído:

```
                      res.partner  (contacto)
                       ▲   ▲   ▲
        partner_id     │   │   │  work_contact_id
        (obligatorio,  │   │   │  (varios empleados pueden
        N usuarios     │   │   │   apuntar al mismo contacto)
        por contacto)  │   │   │
                       │   │   │
              res.users    │   hr.employee
        (login, grupos)    │   (ficha laboral)
                  ▲        │        │
                  └────────┼────────┘
                  user_id  │  (opcional; único por compañía)
                           └── partner.user_ids / partner.employee_ids
                               son los lados inversos (One2many)
```

En forma de tabla:

| Enlace | Campo | Obligatorio | Cardinalidad |
|---|---|---|---|
| usuario → contacto | `res.users.partner_id` | sí | muchos usuarios pueden apuntar al mismo contacto (el inverso `res.partner.user_ids` es `One2many`) |
| empleado → usuario | `hr.employee.user_id` | no | un usuario, como mucho un empleado por compañía (`_user_uniq`) |
| empleado → contacto | `hr.employee.work_contact_id` | no en el esquema; se crea al crear el empleado | el inverso `res.partner.employee_ids` es `One2many` |
| contacto → contacto | `res.partner.parent_id` | no | una empresa con varios contactos y direcciones hijos |

El campo inverso `employee_ids` de `res.partner` lo añade el módulo `hr`
(`addons/hr/models/res_partner.py`) y está restringido al grupo `hr.group_hr_user`; el comentario
de su `help` dice «Related employees based on their private address», que no coincide con el
nombre del campo que enlaza (`work_contact_id`): el código manda.

### Qué se crea automáticamente

Al crear un usuario:

- Se crea (o se reutiliza) un contacto. Como `res.users` hereda por delegación de `res.partner`, un
  `create` sin `partner_id` crea el contacto con los campos del contacto que se pasen (nombre,
  email...). Este comportamiento es el estándar del ORM para `_inherits`; el `create` de `res.users`
  que se leyó no lo reimplementa, solo ajusta lo siguiente: copia `company_id` al contacto si este
  tenía una compañía, sincroniza `active` y genera un avatar con iniciales para usuarios internos
  sin imagen.
- Si el usuario es interno, se crea su ajuste personal (`res.users.settings`).
- Con el módulo `hr`: no se crea empleado salvo que se pida. El `create` de `hr/models/res_users.py`
  solo crea el empleado si los valores traen `create_employee=True` (crea uno en la compañía actual)
  o `create_employee_id` (enlaza uno ya existente).

Al crear un empleado:

- Se crea un contacto de trabajo si no se indicó `work_contact_id`: el método
  `_create_work_contacts` de `hr_employee.py` crea un `res.partner` con el nombre, el email y el
  teléfono de trabajo, la imagen y la compañía del empleado.
- Si se indica `user_id`, el método `_sync_user` hace que el contacto de trabajo sea el contacto
  del usuario (`work_contact_id=user.partner_id.id`) y copia su imagen y zona horaria. Es decir,
  Ana Ruiz con usuario tiene un solo contacto: el mismo para su cuenta y para su ficha laboral.
- Se crea además la primera `hr.version` (los datos laborales) y el recurso asociado.
- El campo `employee` de `res.partner` (booleano) se recalcula y queda a `True` para los contactos
  que son contacto de trabajo de algún empleado.

Un usuario que se crea después para un empleado ya existente (o un empleado que se vincula a un
usuario existente) se enlaza con `user_id`; si antes era el contacto de trabajo de otro empleado
de la misma compañía sin usuario, `_remove_work_contact_id` se lo quita a ese otro.

## No es una relación 1:1

Cada combinación es posible. Con el ejemplo conductor:

| Persona | Contacto | Usuario | Empleado |
|---|:---:|:---:|:---:|
| «Cafés del Valle» (cliente) | sí | no | no |
| Un asesor externo que entra a Odoo como usuario | sí | sí | no |
| Un repartidor que ficha horas pero no entra al sistema | sí | no | sí |
| Ana Ruiz, empleada que también entra a Odoo | sí | sí | sí |

Dos matices que se deducen del código:

- Todo empleado tiene contacto (`work_contact_id` se rellena al crearlo) y todo usuario tiene
  contacto (`partner_id` es obligatorio), pero el enlace `hr.employee.user_id` puede estar vacío.
- Un contacto puede tener varios usuarios: la relación inversa es `user_ids` (`One2many`) y existe
  un campo `main_user_id` cuyo `help` dice «There can be several users related to the same
  partner. When a single user is needed, this field attempts to find the most appropriate one.»

## Usuarios internos, portal y públicos

No todos los usuarios son personal de la empresa. El tipo de usuario lo determinan grupos
exclusivos, definidos en `odoo/addons/base/security/base_groups.xml` (rama 20.0):

| Tipo | Grupo | Comentario del fichero | `share` |
|---|---|---|---|
| Interno | `base.group_user` («Role / User») | «Access to the home menu with limited access» | `False` |
| Portal | `base.group_portal` («Role / Portal») | «Portal members have specific access rights (such as record rules and restricted menus)» | `True` |
| Público | `base.group_public` («Role / Public») | «Public users have specific access rights...» | `True` |

El campo `share` se calcula así (`res_users.py`, rama 20.0):

```python
@api.depends('group_ids')
def _compute_share(self):
    user_group_id = self.env['ir.model.data']._xmlid_to_res_id('base.group_user')
    internal_users = self.filtered_domain([('all_group_ids', 'in', [user_group_id])])
    internal_users.share = False
    (self - internal_users).share = True
```

Un usuario es «compartido» (`share=True`) cuando no pertenece, directa o por implicación, a
`base.group_user`. Esa es la definición operativa de «no interno». Para distinguir portal de
público, el código dispone de `_is_portal()` y `_is_public()`, que comprueban
`has_group('base.group_portal')` y `has_group('base.group_public')`. Una restricción
(`_check_disjoint_groups`) impide que un usuario sea a la vez interno y portal, o interno y
público: «User %(user)s cannot be at the same time in exclusive groups».

Además, en 20.0 el campo `role` de `res.users` es un `Selection` con tres valores:
`('light_user', 'Light')`, `('regular_user', 'User')` y `('group_system', 'Administrator')` (en
19.0 solo tenía `group_user` y `group_system`), calculado a partir de los grupos. Es una clasificación entre usuarios internos; portal y público
no tienen valor de `role` (el cómputo devuelve `False`). Qué diferencia práctica tiene un usuario
«Light» (por ejemplo, en licencias) no se verificó.

En el contacto, `partner_share` resume lo mismo: «Either customer (not a user), either shared
user». Su cálculo es `not partner.user_ids or not any(not user.share for user in partner.user_ids)`:
es `True` si el contacto no tiene usuarios, o si todos sus usuarios son compartidos. O sea, un
cliente sin cuenta y un cliente con acceso al portal comparten `partner_share=True`.

## Consecuencias prácticas

### Un contacto no es un usuario

Dar de alta a «Cafés del Valle» crea un `res.partner`; no crea login ni permisos. Para que su
persona de contacto vea sus pedidos en el portal hay que crear un usuario portal vinculado a ese
contacto (según la documentación oficial de
[usuarios y portal](https://www.odoo.com/documentation/20.0/applications/general/users/portal.html);
el flujo de invitación no se ha leído en detalle).

### Archivar: contacto, usuario y empleado

Los tres modelos tienen un campo `active` y se archivan por separado, con reglas que el código
impone:

- No se puede archivar un contacto con un usuario activo. El `write` de `res.partner` busca los
  usuarios activos del contacto y lanza «You cannot archive contacts linked to an active user. You
  first need to archive their associated user.» Hay que archivar primero el usuario.
- Al reactivar un usuario, el `write` de `res.users` desarchiva antes su contacto
  (`self.partner_id.action_unarchive()`).
- No se puede archivar al usuario con el que se está conectado («You cannot deactivate the user
  you're currently logged in as.») ni activar el superusuario.
- Archivar un empleado (`action_archive` de `hr.employee`) archiva su recurso, porque `active` del
  empleado es un campo relacionado con `resource_id.active`, y vacía los enlaces que otros
  empleados tenían a él (responsable, coach...). El código leído no archiva el usuario ni el
  contacto: dar de baja a Ana Ruiz como empleada no le quita el login. Hay que desactivar el
  usuario aparte.
- El usuario `admin` no se puede borrar («Instead, archive it»), ni los usuarios plantilla de portal
  y público.

### Compañías múltiples y `company_id`

Odoo permite varias compañías en una misma base de datos. El `company_id` significa algo distinto
en cada modelo:

| Modelo | `company_id` | Significado |
|---|---|---|
| `res.partner` | opcional | Vacío: contacto compartido por todas las compañías. Con valor: solo esa compañía. |
| `res.users` | obligatorio, más `company_ids` | `company_id` es la compañía por defecto; `company_ids` son las accesibles. |
| `hr.employee` | obligatorio | Un empleado pertenece a una compañía; el mismo usuario puede tener un empleado distinto en cada una. |

Reglas del código: si un contacto tiene usuarios, su `company_id` debe ser la compañía de todos
esos usuarios, o quedar vacío («The selected company is not compatible with the companies of the
related user(s)»). En un `res.users.create`, si el contacto tenía compañía, pasa a ser la del
usuario. Y el campo `employee_id` del usuario (con `hr`) es el empleado de la compañía activa
(`env.company`); `employee_ids` filtra por las compañías activas y `all_employee_ids` las
devuelve todas. Cambiar de compañía a un empleado existente muestra un aviso: conviene crear otro
empleado en la nueva compañía para no perder acceso a contratos y ausencias anteriores.

## Qué modelo usar para cada pregunta

| Pregunta de negocio | Modelo | Por qué |
|---|---|---|
| ¿A quién facturamos o enviamos el pedido S00042? | `res.partner` | `sale.order.partner_id` es un contacto; las direcciones de factura y entrega son contactos hijos. |
| ¿Quién puede entrar a Odoo y con qué permisos? | `res.users` | Solo el usuario tiene `login` y `group_ids`. |
| ¿A quién se le asigna el seguimiento o el pedido como responsable? | `res.users` | `sale.order.user_id` es un `Many2one` a `res.users`. |
| ¿Cuántos clientes tenemos? | `res.partner` | Filtrar por `customer_rank > 0` (campo del módulo `account`), no «todos los contactos». |
| ¿Quién trabaja en la empresa, en qué departamento y puesto? | `hr.employee` | Los datos laborales viven en el empleado y su `hr.version`. |
| ¿Quién es empleado y además tiene acceso a Odoo? | `hr.employee` con `user_id` no vacío | El enlace es opcional. |
| ¿Qué usuarios son personal interno? | `res.users` con `share = False` | `share` distingue interno de portal y público. |
| ¿Qué personas pueden recibir un email desde un documento? | `res.partner` | El email vive en el contacto; el del usuario y el del empleado se derivan de él. |

Ejemplos de búsqueda (código no ejecutado; los modelos y campos son los citados arriba):

```python
# Usuarios internos activos (no portal, no público)
internos = env["res.users"].search([("share", "=", False)])

# Empleados de la compañía actual que tienen cuenta en Odoo
con_login = env["hr.employee"].search([("user_id", "!=", False)])

# Clientes: contactos con rango de cliente (campo del módulo account)
clientes = env["res.partner"].search([("customer_rank", ">", 0)])
```

Cada uno devuelve un [recordset](Recordsets.md) del modelo consultado: vacío si no hay
coincidencias.

## Errores frecuentes

- **Síntoma:** buscar «Ana Ruiz» en `res.partner` devuelve un contacto, pero no hay forma de ver su
  departamento ni su puesto.
  **Causa:** en `res.partner` está su contacto, no su ficha laboral. El campo `employee` del contacto
  (booleano) solo indica que es contacto de trabajo de un empleado; para los datos laborales hay que
  ir a `hr.employee`, enlazando por `work_contact_id` o por `user_id`.
- **Síntoma:** un script que recorre `res.partner` para enviar invitaciones asume que cada contacto
  puede iniciar sesión y falla o notifica a quien no existe en el sistema.
  **Causa:** el login vive en `res.users`. Un contacto puede tener cero, uno o varios usuarios
  (`user_ids`); filtra por `user_ids` o usa `main_user_id` si necesitas un usuario concreto.
- **Síntoma:** «You cannot archive contacts linked to an active user».
  **Causa:** el contacto tiene un usuario activo. Se archiva primero el usuario; el contacto se
  archiva después o queda como está.
- **Síntoma:** una persona dada de baja como empleada sigue pudiendo entrar a Odoo.
  **Causa:** archivar el empleado no archiva el usuario (ver «Archivar»). Son dos acciones.
- **Síntoma:** cada cliente aparece dos veces en los listados («Cafés del Valle» y «Cafes del
  Valle»), con pedidos repartidos entre ambos.
  **Causa:** contactos duplicados, a menudo por escribir el nombre de una empresa a mano en cada
  pedido en lugar de seleccionar el contacto existente. `res.partner` tiene `vat` (NIF) y un campo
  calculado `same_vat_partner_id` («Partner with same Tax ID») para detectar coincidencias por
  identificación fiscal; el código leído no impide por sí solo duplicados con nombre parecido ni
  sin NIF. Odoo trae una función de fusión de contactos, pero no se ha leído su código.
- **Síntoma:** `A user cannot be linked to multiple employees in the same company.`
  **Causa:** se intentó enlazar el mismo usuario a un segundo empleado de la misma compañía
  (`_user_uniq`). Si la persona trabaja en dos compañías, crea un empleado en cada una.
- **Síntoma:** `user.employee_id` está vacío aunque el empleado existe.
  **Causa:** `employee_id` es el empleado de la compañía activa (`env.company`); si el empleado es
  de otra compañía, aparece en `employee_ids`/`all_employee_ids` pero no en `employee_id`.
- **Síntoma:** `partner.login` o `partner.groups` lanzan `AttributeError`.
  **Causa:** la delegación solo funciona en un sentido (usuario → contacto). Desde el contacto se
  entra con `partner.user_ids`.

## Buenas prácticas avanzadas

- **Enlaza personas por el modelo que corresponde a la pregunta, no por el más cómodo.** Un campo
  de «responsable» a `res.partner` permitiría elegir a un cliente como responsable de una tarea;
  uno a `res.users` lo limita a quien puede actuar en el sistema, y uno a `hr.employee` lo ata a la
  estructura laboral (y a la compañía). Es una decisión de diseño con consecuencias en permisos,
  informes y migraciones.
- **Cruza modelos por el enlace documentado, nunca por nombre o email.** De empleado a usuario,
  `user_id`; de empleado a contacto, `work_contact_id`; de usuario a contacto, `partner_id`. Hacer
  coincidir por nombre falla con homónimos, cambios de nombre y personas con más de un correo.
- **Trata `user_id` de `hr.employee` como opcional en todo código que cruce los dos modelos.**
  Filtra con `("user_id", "!=", False)` antes de acceder a `employee.user_id.partner_id` o a
  campos del usuario, y recuerda que con varias compañías el usuario puede tener varios empleados.
- **Distingue «Salesperson» de «Users» en `res.partner`.** El campo `user_id` de `res.partner` es el
  comercial asignado al contacto (su comentario en el código avisa: «user_id is a Salesperson, not
  the inverse of partner_id in res.users»); la relación inversa real es `user_ids`.
- **Respeta los permisos de lectura de la ficha laboral.** Muchos campos de `hr.employee` están
  restringidos al grupo `hr.group_hr_user` (por ejemplo `private_phone` y `private_email`); para
  quien no tiene ese grupo existe el modelo `hr.employee.public`, una vista (`_auto = False`) con
  los campos de lectura general. Al construir pantallas o integraciones para usuarios sin permisos
  de RRHH, consulta el modelo público.
- **No cambies la compañía de un empleado existente.** Odoo avisa de que conviene crear otro
  empleado en la nueva compañía. Si el mismo contacto trabaja en dos, `work_contact_id` puede
  repetirse entre sus empleados, y por eso el código sincroniza teléfono y email del contacto solo
  si apunta a un único empleado.

## Documentación oficial

- [Código de `res.users`](https://github.com/odoo/odoo/blob/20.0/odoo/addons/base/models/res_users.py),
  [`res.partner`](https://github.com/odoo/odoo/blob/20.0/odoo/addons/base/models/res_partner.py) y
  [`hr.employee`](https://github.com/odoo/odoo/blob/20.0/addons/hr/models/hr_employee.py): las
  definiciones de campos y la lógica de `create`/`write` citadas arriba.
- [Gestión de usuarios](https://www.odoo.com/documentation/20.0/applications/general/users/manage_users.html):
  cómo se crean, invitan y gestionan usuarios desde la interfaz.
- [Acceso del portal](https://www.odoo.com/documentation/20.0/applications/general/users/portal.html):
  cómo dar acceso externo a clientes y proveedores.
- [Nuevo empleado](https://www.odoo.com/documentation/20.0/applications/hr/employees/new_employee.html):
  el alta de empleados y su enlace con usuarios desde la interfaz.

Para el contexto: [qué es Odoo](Odoo.md), [cómo se instala el módulo `hr`](Modulos-y-Apps.md), [el
modo desarrollador](Modo-Desarrollador.md), que muestra los nombres técnicos de modelos y campos en
la interfaz, y [los recordsets](Recordsets.md), el tipo que devuelve cualquier consulta.

---

*En resumen: el contacto (`res.partner`) es la identidad, el usuario (`res.users`) es ese contacto
más login y permisos —delegado por `_inherits` con `partner_id` obligatorio—, y el empleado
(`hr.employee`) es la ficha laboral, enlazada al usuario por un `user_id` opcional y al contacto
por `work_contact_id`. No son una relación 1:1, se archivan por separado y conviene filtrar siempre
por el modelo que responde a la pregunta de negocio.*
