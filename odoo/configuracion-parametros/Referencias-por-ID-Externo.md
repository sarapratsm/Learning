# Referencias por ID externo (XML ID)

> Procedencia: código de la rama `19.0` de github.com/odoo/odoo (`odoo/addons/base/models/ir_model.py`, `odoo/orm/environments.py`, `odoo/orm/models.py`, `odoo/tools/convert.py`, `odoo/modules/loading.py`) y documentación 19.0 (referencia de ficheros de datos, referencia del manifiesto, importación y exportación). Leído el 2026-11-10. No se ejecutó ninguna instancia de Odoo: el código no está ejecutado y las únicas «salidas» son textos literales del código fuente. La rama `20.0` existe (su `release.py` indica `20.0 FINAL`); no se contrastó este contenido contra ella.

## ¿Qué es?

Un **ID externo** (o *XML ID*) es un nombre estable de la forma `módulo.nombre` que Odoo asocia a un registro concreto de la base de datos: por ejemplo `base.group_user` para el grupo de usuarios internos. Cada pareja «nombre → registro» es una fila del modelo `ir.model.data`, cuyos campos relevantes son (en `ir_model.py`, 19.0):

| Campo | Significado |
|---|---|
| `module` | Prefijo: normalmente el módulo que declaró el registro |
| `name` | Nombre dentro del módulo (sin espacios; hay una restricción SQL) |
| `model` | Nombre técnico del modelo del registro (`res.partner`, `sale.order`...) |
| `res_id` | `id` numérico del registro en su tabla |
| `noupdate` | Si es verdadero, una actualización del módulo no sobrescribe el registro |

Hay un índice único sobre `(module, name)`: un ID externo apunta a un solo registro, aunque un mismo registro puede tener varios IDs externos.

## ¿Por qué existe?

El `id` numérico de una fila no es el mismo entre bases de datos: el grupo o la etiqueta que en una base es el `id` 12 puede ser el 87 en otra. Código como `if partner.category_id.id == 12` funciona en una base y falla en silencio en otra. El ID externo es el mismo allí donde esté instalado el módulo, y Odoo lo traduce al número local.

> Es la diferencia entre identificar a una persona por su número de socio (distinto en cada club) o por su correo corporativo (el mismo en todas partes). `base.group_user` significa lo mismo en cualquier base; `12`, no.

Además, el ID externo permite que una actualización del módulo (`-u`) **encuentre** el registro que instaló antes y lo actualice en vez de crear otro.

## ¿Cuándo y para qué se usa?

- Código o vistas que deben apuntar a **un registro concreto que actúa como configuración**: un grupo de seguridad, una etiqueta, una etapa, una plantilla de correo, un diario.
- Datos que un módulo entrega (ficheros XML/CSV) y que luego debe poder actualizar.
- Importar y exportar datos entre sistemas, relacionando registros sin depender de los `id` locales.

Un valor suelto (un plazo en días, una URL, un interruptor) no es un registro al que apuntar: eso vive en los [parámetros del sistema](Parametros-del-Sistema.md). Otras vías de configuración, que no son IDs externos: [el fichero `odoo.conf`](El-Fichero-odoo-conf.md), [los ajustes](Ajustes.md), [la configuración por compañía](Configuracion-por-Compania.md) y [los valores por defecto](Valores-por-Defecto.md).

## Resolver un ID externo desde Python

`env.ref` busca `(módulo, nombre)` en `ir.model.data` y devuelve el recordset del registro (firma en `odoo/orm/environments.py`, 19.0):

```python
grupo = self.env.ref("base.group_user")
etiqueta = self.env.ref("mi_modulo.categoria_cafeterias")

if etiqueta in partner.category_id:
    ...
```

Comportamiento, leído en el código:

- **Solo busca, no crea.** El docstring lo dice: lanza `ValueError` si el registro no se encuentra y `raise_if_not_found` es `True` (valor por defecto).
- **Dos mensajes distintos.** Si la fila de `ir.model.data` no existe, el mensaje es `External ID not found in the system: <xmlid>` (en `_xmlid_lookup`). Si la fila existe pero el registro al que apunta fue borrado, el mensaje es `No record found for unique ID <xmlid>. It may have been deleted.`
- **Con `raise_if_not_found=False`** devuelve `None` en ambos casos (el tipo de retorno anotado es `BaseModel | None`).
- El ID debe llevar el módulo: `_xmlid_lookup` hace `xmlid.split('.', 1)`, así que un nombre sin punto falla.

```python
etiqueta = self.env.ref("otro_modulo.categoria_opcional", raise_if_not_found=False)
if etiqueta:
    ...
```

Para saber a qué modelo y `id` apunta un ID externo sin traer el registro, existe `self.env["ir.model.data"]._xmlid_to_res_model_res_id("mod.nombre")`; devuelve `(modelo, res_id)` o `(False, False)` (método con prefijo `_`, de uso interno).

### El camino inverso: de un registro a su ID externo

`get_external_id()` (en `odoo/orm/models.py`, 19.0) devuelve un diccionario `{id: 'módulo.nombre'}`, con cadena vacía si el registro no tiene ID externo. Si tiene varios, devuelve solo uno de ellos (el docstring dice «randomly»). `_get_external_ids()` devuelve la lista completa por registro.

```python
partner.get_external_id()
# forma documentada en el docstring: {id: 'module.ext_id'}, o {id: ''} si no hay
```

## Declarar registros en ficheros XML

Un ID externo lo declara alguien. La vía habitual es un fichero de datos listado en la clave `data` del `__manifest__.py`, con un `<record>` por registro. El atributo `id` es el ID externo; `model` el modelo:

```xml
<odoo>
    <data noupdate="1">
        <record id="categoria_cafeterias" model="res.partner.category">
            <field name="name">Cafeterías</field>
        </record>
    </data>
</odoo>
```

Si `id` no lleva punto, `make_xml_id` (en `convert.py`) le antepone el módulo actual: este registro queda como `mi_modulo.categoria_cafeterias`. Si lleva punto, el ID debe tener **un solo punto** (`módulo.id`) y, si el módulo es otro, ese módulo debe estar instalado (`_test_xml_id` falla con *«refers to an uninstalled module»*).

La documentación (referencia de ficheros de datos, 19.0) añade: los ficheros se ejecutan en orden y una operación solo puede referirse al resultado de operaciones anteriores; y se recomienda encarecidamente dar `id` a todo `<record>`.

### Referirse a un registro dentro de otro XML

Con el atributo `ref` de un `<field>`, o con la función `ref()` dentro de `eval` (ambos aparecen en la referencia de datos):

```xml
<record id="partner_cafes_del_valle" model="res.partner">
    <field name="name">Cafés del Valle</field>
    <field name="category_id" eval="[(4, ref('mi_modulo.categoria_cafeterias'))]"/>
</record>
```

Qué hace: crea el contacto y le añade (comando `4`, enlazar) la etiqueta cuyo ID externo es `mi_modulo.categoria_cafeterias`. Para un campo Many2one basta `<field name="parent_id" ref="mod.id"/>`.

## `noupdate`: qué recarga `-u` y qué no

La referencia de datos (19.0) lo describe así: lo que está en `<data noupdate="1">` solo se carga al instalar el módulo (`-i`); lo demás se recarga en instalación **y** en actualización (`-i`/`-u`).

Lo que hace el código (`convert.py`, `_tag_record`, 19.0): en modo actualización, si el nodo está marcado `noupdate` y el ID ya existe, el registro **no se actualiza** (solo se guarda su `id` para poder referenciarlo después). Si no existe, se crea con normalidad salvo que lleve `forcecreate="0"`. Además, `models.py` (`_load_records`) vuelve a comprobar el campo `noupdate` de la fila de `ir.model.data` (`if not (update and d_noupdate)`), de modo que el indicador persiste en la base y no solo en el XML.

| Situación | ¿`-u` pisa los cambios hechos a mano? |
|---|---|
| `<record>` fuera de `noupdate` | Sí: vuelve a escribir los campos del XML |
| `<record>` en `<data noupdate="1">`, ya instalado | No |
| `<record>` en `noupdate`, y el registro fue borrado a mano | Se vuelve a crear en la actualización (sale del código: «else create it normally») |

Un registro de configuración que el negocio personalizará (etiquetas, etapas, plantillas) va en `noupdate`; uno que debe mantenerse idéntico al del módulo, no.

## Por qué no clavar IDs numéricos

❌ Depende de la base:

```python
if partner.category_id.id == 12:   # en otra base el 12 es otra cosa o no existe
    ...
```

✅ Depende de un nombre acordado:

```python
if self.env.ref("mi_modulo.categoria_cafeterias") in partner.category_id:
    ...
```

Tampoco conviene buscar por nombre visible (`search([("name", "=", "Cafeterías")])`): el nombre puede traducirse o renombrarse.

## IDs externos en exportación e importación

La documentación de importación y exportación (19.0) explica que:

- En la exportación, el campo `ID` (o `XXX/ID` para una relación) lleva el ID externo, y distingue «ID de base de datos» de «ID externo».
- En la importación, la columna `ID` fija el ID externo del registro importado y las columnas de relaciones se escriben `XXX/ID` (por ejemplo `Country/External ID`, con valores como `base.be`). Se desaconseja quitar la columna `ID` de un fichero exportado.
- Dos registros con el mismo ID externo provocan conflicto.

En el código, si se exporta un registro sin ID externo, `__ensure_xml_id` (`models.py`) **crea uno** con el módulo `__export__`. Por eso un registro exportado puede adquirir un ID externo `__export__.xxx` sin que nadie lo declare en un módulo.

## Adoptar un registro creado a mano sin duplicarlo

Caso: la etiqueta «Cafeterías» la creó alguien desde la interfaz, antes de que existiera el módulo. No tiene fila en `ir.model.data`. Si el módulo añade el `<record id="categoria_cafeterias" ...>` anterior, el cargador busca `(mi_modulo, categoria_cafeterias)`, no lo encuentra y **crea otra etiqueta**.

El código de `_load_records` consulta las filas existentes (`_lookup_xmlids`) y, si hay una para ese ID, actualiza el registro al que apunta (`res_id`). De ahí el patrón: crear de antemano la fila de `ir.model.data` apuntando al registro existente. Los campos son los de la tabla de arriba:

```python
def _adoptar_categoria(env):
    imd = env["ir.model.data"]
    if imd.search_count([("module", "=", "mi_modulo"), ("name", "=", "categoria_cafeterias")]):
        return  # ya adoptada
    categoria = env["res.partner.category"].search([("name", "=", "Cafeterías")], limit=1)
    if categoria:
        imd.create({
            "module": "mi_modulo",
            "name": "categoria_cafeterias",
            "model": "res.partner.category",
            "res_id": categoria.id,
            "noupdate": True,
        })
```

No ejecutado. El patrón es una deducción a partir de la lectura de `_load_records` y de los campos de `ir.model.data`; la documentación oficial leída no describe este procedimiento. Dos precauciones: buscar por nombre solo es aceptable aquí, en un paso puntual; y buscar `env.ref(...)` para decidir si hay que crear la etiqueta es un error, porque ese ID aún no existe y se crearía un duplicado.

### Cuándo se ejecuta ese código

Leído en `odoo/modules/loading.py` (19.0) y en la referencia del manifiesto:

| Mecanismo | Cuándo corre |
|---|---|
| `pre_init_hook` (clave del manifiesto) | Solo en **instalación**, antes de cargar el módulo y sus datos; recibe `env` |
| `post_init_hook` | Solo en instalación, después de cargar el módulo; recibe `env` |
| `uninstall_hook` | En la desinstalación; recibe `env` |
| `migrations/<versión>/pre-*`, `post-*`, `end-*` | En una **actualización** (`migrate_module(package, 'pre'/'post'/'end')`), no en la instalación inicial |

La referencia del manifiesto indica que los hooks solo se deben usar cuando la preparación o limpieza sea muy difícil o imposible por la API normal. Para un módulo ya instalado en producción, el código de adopción debe ir en un script de migración; para una instalación nueva, en `pre_init_hook`. No se leyó la firma exacta de los scripts de migración (`migrate(cr, version)` es el uso habitual, no verificado aquí).

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `ValueError: External ID not found in the system: mod.nombre` | La fila no existe: módulo no instalado, nombre mal escrito, o el registro nunca se declaró |
| `ValueError: No record found for unique ID ... It may have been deleted.` | La fila existe pero el registro fue borrado |
| Tras instalar el módulo aparece un registro duplicado | El registro ya existía a mano y no tenía fila en `ir.model.data` (ver adopción) |
| Un `-u` no devuelve un registro a sus valores originales | El registro está en `noupdate` o su fila tiene `noupdate` verdadero |
| `The ID "x.y" refers to an uninstalled module` al cargar el XML | El ID referencia un módulo que no está instalado ni es dependencia |
| `The ID reference ... must contain maximum one dot` | El `id` del XML lleva más de un punto |
| Un ID externo deja de existir tras desinstalar un módulo | `_module_data_uninstall` borra los registros referenciados por las filas del módulo, siempre que ninguna otra fila de otro módulo los referencie |

## Buenas prácticas avanzadas

- **El ciclo de vida de un registro adoptado queda atado al módulo.** `_module_data_uninstall` elimina los registros cuyas filas de `ir.model.data` pertenecen al módulo (salvo los que otra fila mantiene vivos). Al adoptar un registro anterior al módulo, valora si desinstalarlo debería borrarlo.
- **`noupdate` protege de `-u`, no de la desinstalación ni del código.** Un registro `noupdate` se borra igualmente al desinstalar su módulo.
- **Cuando un módulo consume un ID de otro, decláralo en `depends`**, o usa `raise_if_not_found=False`: `_test_xml_id` rechaza referencias en XML a módulos no instalados.
- **No dependas de un ID `__export__`.** Se genera al exportar un registro sin ID; no pertenece a ningún módulo ni es estable entre bases.
- **Nombra con sentido y sin duplicar prefijos.** `mi_modulo.categoria_cafeterias` se lee solo; un nombre genérico invita a colisiones y a no saber quién es el dueño.
- **`get_external_id()` no es determinista si hay varios IDs.** Si necesitas todos, usa `_get_external_ids()` (método interno).

## Documentación oficial

- [Ficheros de datos](https://www.odoo.com/documentation/19.0/developer/reference/backend/data.html) — `<record>`, `ref`, `eval`, `noupdate` y `forcecreate`.
- [Manifiesto del módulo](https://www.odoo.com/documentation/19.0/developer/reference/backend/module.html) — `pre_init_hook`, `post_init_hook` y `uninstall_hook`.
- [Exportar e importar datos](https://www.odoo.com/documentation/19.0/applications/essentials/export_import_data.html) — ID de base de datos frente a ID externo, columnas `ID` y `XXX/ID`.

---

*En resumen: un ID externo es la fila de `ir.model.data` que da a un registro un nombre `módulo.nombre` estable entre bases; se declara con `<record id="...">`, se resuelve con `env.ref(...)` en vez de IDs numéricos, `noupdate` decide si `-u` lo vuelve a escribir, y un registro creado a mano se adopta creando su fila de `ir.model.data` antes de que el módulo lo declare.*
