# Parámetros del Sistema (ir.config_parameter)

## ¿Qué es?

Los parámetros del sistema son un almacén de **clave-valor** guardado en la base de datos, en el modelo `ir.config_parameter` (descripción interna: «System Parameter»). Cada parámetro es una pareja de textos —`key` → `value`— que el código puede leer y escribir en tiempo de ejecución, sin tocar el servidor ni reiniciarlo. Hay una sola tabla por base de datos: el valor es global a esa base, no depende del usuario ni de la compañía.

Procedencia (2026-11-10): el comportamiento descrito sale de la lectura de el código fuente de la rama `19.0` de Odoo (`odoo/addons/base/models/ir_config_parameter.py`, `odoo/addons/base/models/res_config.py`, `odoo/addons/base/views/ir_config_parameter_views.xml`, `odoo/addons/base/views/base_menus.xml` y `odoo/addons/base/security/ir.model.access.csv`; la documentación oficial lista Odoo 19.0 como versión actual el 2026-11-10). No se ejecutó ninguna instancia de Odoo: no hay salidas de consola, y lo que se cita como resultado sale literalmente del código.

## ¿Por qué existe?

Hay valores que no son código ni infraestructura, pero tampoco deberían estar clavados en un `.py`: la URL base de la instancia, un límite configurable, un interruptor para activar una funcionalidad. Si viven en el código, cambiarlos obliga a modificar y redesplegar. Si viven en `odoo.conf`, cambiarlos obliga a reiniciar el servidor y tener acceso al sistema de ficheros. `ir.config_parameter` ofrece un sitio intermedio: un valor que se cambia en caliente, desde la interfaz o desde código, y que cada base de datos tiene por separado.

> Piensa en un diccionario global y persistente, con las claves como texto, que sobrevive a los reinicios y que es distinto en cada base de datos (la de producción y una copia de pruebas tienen cada una el suyo).

## ¿Cuándo y para qué se usa?

Cada vez que un módulo necesita un valor **global a la base de datos** que pueda cambiar sin redesplegar. El ejemplo conductor es una pequeña empresa de cafés («Cafés del Valle» es un cliente; S00042, un pedido de venta): un módulo propio quiere un parámetro `mi_modulo.dias_aviso_pedido` con el número de días tras los que avisar de un pedido sin confirmar. También lo usa el propio Odoo para sus necesidades internas (véase [Parámetros estándar](#parámetros-estándar-que-crea-odoo)).

## Leer un parámetro

`get_param(key, default=False)` devuelve el valor como texto, o `default` si el parámetro no existe (y `False` si tampoco se indica `default`).

```python
ICP = self.env["ir.config_parameter"].sudo()
dias = ICP.get_param("mi_modulo.dias_aviso_pedido", default="7")
```

Detalles del código (`19.0`, `ir_config_parameter.py`):

- `get_param` empieza con `self.browse().check_access('read')`: comprueba el permiso de lectura sobre el modelo antes de leer.
- Devuelve `self._get_param(key) or default`. Como se usa `or`, **un valor vacío (`""`) cuenta como ausente** y devuelve `default`.
- `_get_param` está decorado con `@ormcache('key', cache='stable')`: el resultado se guarda en una caché del registro, no en la base de datos. Hace un `SELECT value FROM ir_config_parameter WHERE key = %s` directo (se salta el ORM a propósito, porque `get_param` se usa en `depends` de campos y debe funcionar aunque el ORM no esté listo).
- `create`, `write` y `unlink` limpian esa caché (`registry.clear_cache('stable')`), así que leer después de escribir devuelve el valor nuevo.

## Escribir un parámetro

`set_param(key, value)` crea, actualiza o borra, y devuelve el valor anterior (o `False` si no existía).

```python
ICP.set_param("mi_modulo.dias_aviso_pedido", "10")   # crea o actualiza
ICP.set_param("mi_modulo.dias_aviso_pedido", False)  # borra el parámetro
```

Según el código:

| Situación | Resultado |
|---|---|
| La clave existe y `value` es distinto (`str(value) != old`) | Escribe el valor nuevo |
| La clave existe y `value` es `False` o `None` | **Borra** el registro (`unlink`) |
| La clave no existe y `value` es `False` o `None` | No hace nada |
| La clave no existe y hay valor | Crea el registro |

Consecuencia importante: poner un parámetro a `False` no lo guarda como «falso»: lo elimina, y la siguiente lectura devolverá el `default`. Un `0` (entero) sí se guarda, como el texto `"0"`.

## Verlos y editarlos en la interfaz

La lista está en **Ajustes → Técnico → Parámetros → Parámetros del sistema**. El menú «Técnico» solo aparece con el [modo desarrollador](../fundamentos/Modo-Desarrollador.md) activo: en `base_menus.xml` lleva `groups="base.group_no_one"`, el grupo que representa el modo desarrollador. La acción (`ir_config_list_action`) muestra la lista con búsqueda por `key` y por `value`, y permite crear, editar y borrar.

El permiso sobre el modelo (`ir.model.access.csv`) lo tiene solo `base.group_system` (administradores de ajustes), con lectura, escritura, creación y borrado. Un usuario normal que ejecute código que lea un parámetro necesita `sudo()` (ver Errores frecuentes).

## Definir un valor inicial por XML

Un módulo puede crear parámetros al instalarse con un fichero de datos. El propio Odoo lo hace en `odoo/addons/base/data/ir_config_parameter_data.xml`:

```xml
<odoo>
    <data noupdate="1">
        <record id="default_max_email_size" model="ir.config_parameter">
            <field name="key">base.default_max_email_size</field>
            <field name="value">10</field>
        </record>
    </data>
</odoo>
```

Con `noupdate="1"` el registro se crea al instalar, pero **no se vuelve a sobrescribir** al actualizar el módulo: si un administrador cambia el valor después, la actualización no lo revierte. Sin `noupdate`, cada actualización del módulo restablecería el valor del XML. El `id` del registro (aquí `default_max_email_size`) es su [referencia por ID externo](Referencias-por-ID-Externo.md).

Este mecanismo sirve para valores que el módulo da por supuestos. Los que no pueden faltar nunca desde que existe la base (`web.base.url`, `database.uuid`…) no se crean por XML, sino por código (siguiente sección).

## Parámetros estándar que crea Odoo

En `ir_config_parameter.py` (`19.0`) hay un diccionario `_default_parameters` que el método `init` recorre al crear la base de datos; solo crea las claves que faltan:

| Clave | Valor inicial (según el código) |
|---|---|
| `database.secret` | un `uuid4` aleatorio |
| `database.uuid` | un `uuid1` |
| `database.create_date` | la fecha y hora de creación |
| `web.base.url` | `http://localhost:<http_port>` |
| `base.login_cooldown_after` | `10` |
| `base.login_cooldown_duration` | `60` |

Además, `base.default_max_email_size` (valor `10`) viene del XML anterior.

Protecciones del código: un `write` que **renombre** una de las claves de `_default_parameters` lanza `ValidationError` («You cannot rename config parameters…»), y borrarla también (`unlink_default_parameters`: «You cannot delete the %s record.»; la comprobación está marcada `at_uninstall=False`, es decir, no se aplica al desinstalar el módulo).

`database.is_neutralized` no está entre los parámetros por defecto de esta rama: lo escribe el `neutralize.sql` del módulo `base` al [neutralizar la base](../pruebas-seguras/Neutralizar-Base-de-Datos.md) (leído en la rama `20.0`, no en `19.0`). No se verificó `mail.catchall.domain` (en la `19.0` el correo de captura vive en el modelo `mail.alias.domain`, fichero `addons/mail/models/mail_alias_domain.py`, no en un parámetro). No los uses como referencia sin contrastarlos en tu versión.

## Parámetro, odoo.conf o campo de Ajustes

La decisión depende de quién cambia el valor y cuándo.

| Necesidad | Mejor opción |
|---|---|
| Valor de infraestructura del servidor (puerto, ruta de datos, conexión a la base, claves maestras) | [`odoo.conf`](El-Fichero-odoo-conf.md) |
| Valor global a la base, que un administrador cambia en caliente | `ir.config_parameter` |
| Valor global que además debe tener pantalla amable para usuarios de negocio | Campo de `res.config.settings` ([Ajustes](Ajustes.md)) con `config_parameter='...'`, que guarda en un `ir.config_parameter` |
| Valor distinto por compañía | Campo en la compañía ([Configuración por compañía](Configuracion-por-Compania.md)) |
| Valor sugerido al crear un registro | [Valor por defecto](Valores-por-Defecto.md) |

La relación con Ajustes se ve en `res_config.py`: un campo con `config_parameter='mi.clave'` se lee con `IrConfigParameter.get_param(icp, ...)` al abrir la pantalla y se guarda con `set_param` al pulsar «Guardar». Al guardar, un campo `char` se recorta de espacios y vacío pasa a `False` (lo que **borra** el parámetro); `integer` y `float` se guardan con `repr(value)`; un `many2one` guarda su `id`.

## Convertir tipos

El valor es texto (`fields.Text`), así que la conversión es manual:

```python
dias = int(ICP.get_param("mi_modulo.dias_aviso_pedido", "7"))
activo = ICP.get_param("mi_modulo.aviso_activo", "False") == "True"
```

Los booleanos son otra trampa: como `set_param(key, False)` borra, no se puede guardar «falso» como valor `False`; usa el texto `"False"`/`"0"` o `"1"`/`"True"` y compáralo explícitamente. Odoo mismo evalúa algunos parámetros con `literal_eval` (por ejemplo `base.template_portal_user_id` en `res_config.py`, leído con `get_param(..., 'False')`).

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `AccessError` al leer el parámetro desde un usuario normal | Falta `sudo()`; solo `base.group_system` tiene permiso sobre el modelo |
| `TypeError` o comparaciones que nunca se cumplen con un número | El valor llega como texto (`"5"`), no como `int` |
| `set_param(key, False)` y luego el parámetro «desaparece» | `False` y `None` borran el parámetro |
| Un valor vacío devuelve el `default` | `get_param` usa `or default`: `""` cuenta como ausente |
| El valor del XML vuelve a su estado inicial tras actualizar el módulo | Falta `noupdate="1"` |
| Dos módulos se pisan el mismo parámetro | Clave sin prefijo de módulo; el almacén es global |
| `ValidationError` al renombrar o borrar una clave | Es una de las de `_default_parameters` (`web.base.url`, `database.uuid`…) |
| El valor leído no es el que acabas de cambiar en otra base | Cada base de datos tiene su tabla; el valor no se comparte entre bases |

## Buenas prácticas avanzadas

- **Prefija la clave con el nombre técnico del módulo**: `mi_modulo.dias_aviso_pedido`, como hacen las claves del propio Odoo (`web.`, `base.`, `database.`).
- **Lee una vez, no dentro de un bucle de miles de registros**: `get_param` está en caché del registro, pero conviene leer fuera del bucle y reutilizar la variable.
- **Usa un valor por defecto en texto y conviértelo después**: `int(ICP.get_param(clave, "7"))` evita `int(False)`.
- **Evita guardar secretos en claro**: el valor se guarda sin cifrar, lo leen quienes accedan a la tabla o a un volcado de la base (y la lista del modo desarrollador). Para claves sensibles, valora [`odoo.conf`](El-Fichero-odoo-conf.md) o variables de entorno, y no las incluyas en copias que vayan a salir de producción.
- **No dependas de las claves internas de Odoo entre versiones**: la lista de `_default_parameters` y dónde vive la configuración del correo han cambiado entre versiones; contrasta en la rama que uses.
- **Para exponer un parámetro a usuarios de negocio, usa un campo de Ajustes** con `config_parameter=`, en lugar de pedirles que editen la lista técnica.

## Documentación oficial

- [Código de `ir_config_parameter.py`, rama 19.0](https://github.com/odoo/odoo/blob/19.0/odoo/addons/base/models/ir_config_parameter.py): implementación completa de `get_param`, `set_param`, la caché y los parámetros por defecto.
- [Código de `res_config.py`, rama 19.0](https://github.com/odoo/odoo/blob/19.0/odoo/addons/base/models/res_config.py): cómo los campos de Ajustes con `config_parameter` leen y escriben parámetros.
- [Referencia del ORM, versión 19.0](https://www.odoo.com/documentation/19.0/developer/reference/backend/orm.html): contexto del entorno y del `sudo()`.

---

*En resumen: `ir.config_parameter` es el diccionario de texto global a cada base de datos que se cambia en caliente; léelo con `get_param` (el vacío cuenta como ausente) y escríbelo con `set_param` (`False` lo borra), prefija las claves, usa `sudo()`, convierte los tipos a mano y no guardes secretos en claro.*
