# Hitos de proyecto

## ¿Qué es?

Un hito (*milestone*, modelo `project.milestone`) es un punto de control con nombre y fecha dentro de un proyecto de Odoo: "Beta cerrada", "Lanzamiento", "Migración de datos". Las tareas del proyecto se enlazan a él, y el hito se marca como alcanzado cuando el trabajo que representa está terminado.

## ¿Por qué existe?

Un proyecto con cien tareas dice poco sobre si va bien o mal: están en etapas distintas, tienen fechas distintas y ninguna cuenta la historia completa. Lo que quien gestiona o quien paga necesita saber es otra cosa: *¿hemos llegado ya a la beta?, ¿cuándo toca el lanzamiento?, ¿vamos tarde?*

El hito responde a eso. Agrupa tareas bajo un objetivo con fecha y le da un estado de dos valores: alcanzado o no.

> Si ya conoces las *releases* o los *milestones* de GitHub, es la misma idea: una etiqueta con fecha límite a la que se asocian incidencias y que tiene una barra de progreso. En Odoo, además, puede servir como momento de facturación (ver [Facturación por hitos](Facturacion-por-Hitos.md)).

## ¿Cuándo y para qué se usa?

- Un proyecto con **entregas parciales al cliente**: una tienda online que sale primero con catálogo y carrito y, semanas después, con el panel de administración.
- Ver de un vistazo qué hitos **se están retrasando** sin abrir tarea por tarea.
- Dar al cliente (por el portal del proyecto) una visión de alto nivel, sin enseñarle el detalle de cada tarea interna.

No sirve para planificar tandas de trabajo de pocas semanas (para eso están los sprints, o simplemente las etapas del tablero) ni para clasificar tareas por tema (para eso están las etiquetas).

---

## Un hito pertenece a un solo proyecto

Este es el dato de diseño que condiciona todo lo demás. Un hito tiene un campo `project_id` obligatorio, y una tarea solo puede apuntar a hitos de **su propio proyecto**.

| | Hito | Etiqueta | Etapa |
|---|---|---|---|
| Alcance | Un proyecto | Toda la instalación | Un proyecto (o varios) |
| Tiene fecha | Sí | No | No |
| Tiene estado propio | Sí (alcanzado o no) | No | Es el estado de la tarea |
| Una tarea puede tener | Uno | Varias | Una |

Consecuencia práctica: **un hito no puede abarcar tareas de dos proyectos**. Si un lanzamiento reparte trabajo entre el proyecto "Web" y el proyecto "App móvil", hay un hito en cada uno y la relación entre ellos la mantienes tú (por ejemplo, con el mismo nombre).

## Activar los hitos

Los hitos vienen apagados en una instalación nueva. Se activan en dos niveles:

1. **En toda la instalación**: *Ajustes → Proyecto → Gestión de tareas → Hitos* (*Milestones*), y *Guardar*. Esto habilita la función para los usuarios y hace aparecer los campos relacionados.
2. **En cada proyecto**: en la configuración del proyecto, la casilla **Hitos**. Un proyecto nuevo la trae marcada si la función está activa en los ajustes generales; en uno que ya existía, puede que haya que marcarla a mano.

Si activas el ajuste global y no ves nada en un proyecto, casi siempre es porque falta la casilla del proyecto. Y a la inversa: desactivar el ajuste global apaga la función en todos los proyectos.

Estas dos casillas son `group_project_milestone` (ajuste global) y `allow_milestones` (por proyecto). Conviene conocer los nombres si necesitas buscar el ajuste en modo desarrollador o escribir un dominio.

## Crear un hito y asignarle tareas

Hay tres sitios desde donde crear un hito, y todos acaban en el mismo modelo:

- Desde el **panel del proyecto** (el resumen que se abre desde la tarjeta del proyecto), con *Añadir hito* dentro de la sección de hitos.
- Desde el menú del proyecto, en la lista de hitos, que es **editable en línea**: escribes nombre y fecha directamente en la fila.
- Desde el propio campo *Hito* de una tarea, escribiendo un nombre nuevo y eligiendo *Crear*.

Una tarea se enlaza con el campo **Hito** de su formulario, que solo ofrece los del proyecto de esa tarea. El mismo campo se puede añadir como columna a la vista de lista y usar para **filtrar y agrupar** (*Agrupar por → Hito*), lo que permite mover muchas tareas de golpe editando varias filas a la vez.

El mismo resultado, escrito desde el shell de Odoo (útil para entender qué hay detrás de la pantalla):

```python
project = env['project.project'].search([('name', '=', 'Tienda online')], limit=1)

beta = env['project.milestone'].create({
    'name': 'Beta cerrada',
    'project_id': project.id,
    'deadline': '2026-12-15',
})

tareas = env['project.task'].search([
    ('project_id', '=', project.id),
    ('name', 'ilike', 'carrito'),
])
tareas.write({'milestone_id': beta.id})
```

El hito se crea ligado al proyecto con su fecha límite, y las tareas cuyo nombre contiene "carrito" se enlazan a él. Después, `beta.task_count` da cuántas tareas tiene y `beta.done_task_count` cuántas están cerradas.

## Subtareas: el hito se hereda

Odoo propaga el hito por la jerarquía de subtareas, con reglas que conviene conocer porque a veces "se mueven solas":

- Una **subtarea nueva** hereda el hito de su tarea padre si ambas están en el mismo proyecto.
- Al **cambiar el hito de una tarea padre**, se actualizan sus subtareas que no tengan hito o que tuvieran el mismo que el padre. Las subtareas con un hito propio distinto se quedan como están.
- Las subtareas **cerradas** (hechas o canceladas) no se tocan: conservan el hito con el que se cerraron.

```python
# El padre pasa de "Beta cerrada" a "Lanzamiento"
padre.write({'milestone_id': lanzamiento.id})
# Sus subtareas abiertas que seguían a "Beta cerrada" pasan también a "Lanzamiento".
# Las que ya estaban cerradas siguen en "Beta cerrada".
```

## Marcar un hito como alcanzado

El hito tiene una casilla **Alcanzado** (`is_reached`). Se marca **a mano**: Odoo no la marca solo cuando se cierran las tareas.

Lo que sí hace Odoo es avisarte con el color en la lista de hitos:

| Color | Significado |
|---|---|
| Verde | Se puede marcar: el hito tiene al menos una tarea cerrada y ninguna abierta. |
| Rojo | La fecha límite ha pasado y no se puede marcar aún. |
| Gris | Ya está alcanzado. |

Al marcar la casilla se guarda la **fecha en la que se alcanzó** (`reached_date`, hoy), distinta de la fecha límite. Comparar las dos es la forma de saber si el hito se cumplió a tiempo.

Un hito sin ninguna tarea nunca se pone verde, aunque no tenga nada pendiente: Odoo exige al menos una tarea cerrada. Si usas hitos "vacíos" como simples hitos de calendario, los marcarás siempre a mano.

## Dónde se ve el avance

- **Panel del proyecto**: lista de hitos con una casilla para marcarlos y colores por fecha.
- **Lista de proyectos**: el próximo hito pendiente y un porcentaje de hitos alcanzados sobre el total (`milestone_progress`).
- **Filtro *Hitos retrasados*** en la lista de proyectos (los que tienen algún hito vencido sin alcanzar). En las tareas, el campo `has_late_and_unreached_milestone` permite filtrar las que cuelgan de un hito en esa situación:

```python
# Tareas abiertas cuyo hito ya venció sin alcanzarse
env['project.task'].search([
    ('has_late_and_unreached_milestone', '=', True),
    ('state', 'not in', ['1_done', '1_canceled']),
])
```

- **Portal del cliente**: si el proyecto se comparte, las tareas muestran su hito y se pueden agrupar por él.

## Errores frecuentes

**Asignar un hito de otro proyecto.** Si escribes en una tarea un `milestone_id` que pertenece a un proyecto distinto, Odoo no lanza ningún error: **vacía el campo** de esa tarea. Pasa también al mover una tarea a otro proyecto (el hito se pierde y solo se conserva si la tarea hereda del padre uno del proyecto nuevo). Si tras una operación masiva las tareas se quedan sin hito, es lo primero que hay que comprobar.

**No ver el campo *Hito* en la tarea.** El campo solo aparece si la función está activa en los ajustes generales **y** en el proyecto de la tarea, y solo para quien tenga el permiso asociado. Una tarea sin proyecto tampoco lo muestra.

**Esperar que la fecha del hito mueva las tareas.** No lo hace: la fecha límite del hito y las de las tareas son independientes. Cambiar una no cambia la otra.

## Buenas prácticas avanzadas

- **Define el hito por lo que el cliente puede comprobar, no por lo que el equipo termina.** "Catálogo navegable en el entorno de pruebas" es un hito; "Terminar el backend" no lo es. Un hito que nadie fuera del equipo puede verificar no sirve para negociar una entrega ni para facturar, y se acaba marcando por costumbre.
- **Marca el hito como alcanzado solo cuando haya algo que lo demuestre.** Como la casilla es manual, es fácil marcarla "casi hecho". Si el hito está ligado a una factura (ver [Facturación por hitos](Facturacion-por-Hitos.md)), marcarla de más tiene consecuencias económicas.
- **Pocos hitos y con nombre propio.** Entre tres y ocho por proyecto. Con más, la lista pierde la función de resumen y se convierte en una segunda lista de tareas, y la barra de progreso (que cuenta hitos, no tareas) deja de significar nada.
- **No muevas tareas entre hitos con el proyecto a medias sin revisar las subtareas.** La propagación al padre actualiza solo las subtareas abiertas que seguían a su padre; el resultado es una mezcla de hitos que se explica por la regla, pero sorprende a quien mira la lista sin conocerla.
- **Documenta los cambios de fecha en el propio hito.** El hito usa el chatter (`mail.thread`) y registra los cambios de fecha límite: aprovéchalo para dejar un comentario con el motivo cuando se retrase, porque ese historial es lo que luego se enseña al cliente.

## Documentación oficial

- [Panel del proyecto (Odoo 18)](https://www.odoo.com/documentation/18.0/applications/services/project/project_management/project_dashboard.html) — la parte de hitos explica cómo se añaden, se editan y se marcan desde el panel, y qué significan los colores.
- [Código del modelo `project.milestone`](https://github.com/odoo/odoo/blob/18.0/addons/project/models/project_milestone.py) — corto y legible; responde cualquier duda sobre qué cuenta como "se puede marcar" o cómo se calcula el progreso.

---

*En resumen: un hito es una fecha con nombre que pertenece a un proyecto, a la que se enlazan tareas y que alguien marca como alcanzada a mano; sirve para enseñar el avance sin enseñar las tareas.*
