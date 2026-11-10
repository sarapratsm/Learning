# Pruebas seguras sobre un Odoo en producción

## ¿Qué es?

El procedimiento para comprobar un cambio en un Odoo que la empresa usa cada día sin dañar sus datos ni interrumpir el trabajo. Combina tres ideas: probar primero en una copia, tocar producción solo con red de seguridad (copia de seguridad probada, ventana de cambio, plan de marcha atrás) y saber qué acciones de Odoo **no se pueden deshacer** aunque se restaure algo.

Referencias de código y documentación: rama estable `20.0` de `github.com/odoo/odoo` y documentación 20.0, leídas el 2026-11-10. No se ejecutó ninguna instancia de Odoo: los comandos se presentan como **no ejecutados** y los comportamientos citados proceden de los ficheros indicados en cada punto. Lo que no se pudo contrastar está marcado como «no verificado».

Ejemplo conductor: la empresa «Cafés del Valle» (base de producción `cafes_prod`, copia `cafes_staging` en `staging.ejemplo.com`; datos inventados) que vende productos y gestiona pedidos como el S00042 y contactos como Ana Ruiz.

## ¿Por qué existe?

Producción es el único entorno con datos reales: clientes, facturas, stock. Un fallo ahí no es un error de programación cualquiera: puede enviar un correo a un cliente real, consumir números de factura o dejar a toda la plantilla sin poder trabajar. Y Odoo hace efectos laterales fuera de la base de datos (envío de correo, llamadas a servicios externos) que ninguna restauración recupera.

> Es la diferencia entre ensayar una operación en un maniquí, con el equipo y un plan de emergencia, y improvisar sobre el paciente.

## ¿Cuándo y para qué se usa?

Siempre que un cambio vaya a llegar a la base que usa la empresa: instalar o actualizar un módulo, cambiar la configuración de una App, importar datos en masa, ensayar una migración de versión o diagnosticar un error que solo ocurre con datos reales.

## Qué se puede tocar en producción y qué no

La regla: lo que se pueda ensayar en una copia se ensaya en la copia, y la decisión depende de lo que el cambio escribe y de si se puede deshacer.

| Tipo de cambio | ¿Directo en producción? | Condiciones |
|---|---|---|
| Ajuste de datos puntual (corregir un contacto, un precio de lista) | Sí, por la interfaz | Copia de seguridad reciente; un cambio cada vez; nunca con `UPDATE` en SQL. |
| Ajuste de datos masivo (importación, acción en lote) | No sin ensayo | Ensayar antes en `cafes_staging` y medir qué se escribe; ventana de cambio. |
| Vista o configuración (campos de una vista, parámetros) | Con cuidado | Una vista rota bloquea la pantalla para todos; ensayar antes en la copia y tener el cambio anotado para revertirlo. |
| Módulo nuevo (instalar) | No | Instalar crea tablas y columnas y puede cargar datos; ensayar en la copia neutralizada; plan de marcha atrás = restaurar la copia de seguridad. |
| Actualización de módulo (`-u`) | No | Ensayar en la copia con los datos reales; ventana de cambio; parada de crons (ver más abajo). |
| Migración de versión mayor | Nunca directamente | Ensayar sobre una copia tantas veces como haga falta; la documentación de actualización de Odoo trabaja siempre con una copia de la base ([Actualizaciones](https://www.odoo.com/documentation/20.0/administration/upgrade.html)). |
| Diagnóstico (solo mirar) | Sí | Solo lectura (ver más abajo). |

## Checklist

Las fichas hermanas contienen el cómo; aquí solo el orden y los puntos de control.

### Antes

1. **Entorno de pruebas**: confirmar que existe una copia y qué la distingue de producción ([Entornos de desarrollo, staging y producción](Entornos-dev-staging-produccion.md)).
2. **Copia de seguridad**: hacer una completa (base de datos y filestore) y **probar la restauración** en otra base; solo cuenta como copia la que se ha restaurado con éxito ([Backups y restauración](Backups-y-Restauracion.md)). Anotar cuánto tarda: ese tiempo es la duración real de la marcha atrás.
3. **Copia para ensayar**: duplicar la base ([Duplicar la base de datos](Duplicar-Base-de-Datos.md)) y **neutralizarla antes de arrancarla** ([Neutralizar la base de datos](Neutralizar-Base-de-Datos.md)), para que no envíe correo ni dispare integraciones reales.
4. **Ensayo completo** en la copia: el mismo cambio, con el mismo procedimiento, y validado con un usuario que tenga los permisos reales de quien lo usará, no solo con administración (el administrador se salta la mayoría de reglas de acceso y oculta fallos de grupos).
5. **Ventana de cambio**: fuera del horario laboral, con fecha y hora de inicio y de fin límite para decidir si se vuelve atrás.
6. **Plan de marcha atrás** escrito: qué copia de seguridad restaurar, en qué orden, quién lo ejecuta y cuánto tarda.
7. **Comunicación**: avisar a las personas que usan el sistema de cuándo no estará disponible y qué hacer si algo falla.

### Durante

- Aplicar los cambios de uno en uno y comprobar tras cada uno.
- Parar o revisar las acciones planificadas (crons) delicadas durante la ventana: una facturación recurrente que se dispara a mitad de una actualización trabaja sobre datos a medio migrar. Desde los ajustes técnicos se pueden desactivar temporalmente y reactivar al final.
- No tocar PostgreSQL a mano: un `UPDATE`/`DELETE` directo se salta la lógica de Odoo (cálculos, restricciones, trazabilidad) y deja datos incoherentes.

### Después

- Revisar el registro del servidor (errores y avisos) y la cola de correo saliente.
- Recorrer el flujo principal con un usuario normal: crear un presupuesto, confirmarlo, consultar un contacto.
- Reactivar los crons y confirmar que se ejecutan.
- Mantener la copia de seguridad previa hasta que haya pasado el tiempo suficiente para detectar problemas diferidos (un cierre de mes, una facturación recurrente).

## Qué se puede probar con riesgo bajo en producción

Ninguna de estas técnicas es riesgo cero; cada una tiene un límite concreto.

| Técnica | Qué permite | Límite |
|---|---|---|
| Consultas de solo lectura | Diagnosticar con datos reales sin escribir. Conectarse a PostgreSQL con un rol que solo tenga `SELECT` (no verificado cómo se crea en cada despliegue). | Las consultas pesadas pueden ralentizar el servidor en plena jornada. |
| Usuario con permisos de solo lectura | Mirar sin poder modificar. | Odoo no trae un grupo genérico «solo lectura» para todo: hay que montarlo con grupos y reglas de acceso; comprobar que de verdad no puede escribir. |
| [Modo desarrollador](../fundamentos/Modo-Desarrollador.md) | Ver nombres técnicos de campos, vistas y acciones. | **No restringe nada**: quien lo activa conserva sus permisos de escritura. Es una ayuda para mirar, no un modo seguro. |
| Usuario de pruebas | Ensayar permisos de un perfil sin usar la cuenta de otra persona. | Los datos que cree siguen siendo datos de producción y las secuencias que consuma no se recuperan. |
| Compañía de pruebas dentro de la misma base | Aislar los registros de ensayo de los reales (Odoo filtra por compañía). | Comparte la base, los usuarios, los crons y la configuración de correo saliente; un fallo de módulo afecta igualmente a todas las compañías. Las secuencias de cada compañía se separan solo si así están definidas (no verificado para todas las Apps). |
| Pedidos con clientes de prueba (p. ej. un contacto «ZZ Cliente de pruebas») | Ensayar el flujo de ventas completo. | Confirmar un pedido envía correos si hay plantilla automática, consume el número de pedido y puede mover stock o generar asientos; los registros se pueden cancelar, pero los efectos de la sección siguiente permanecen. |

## Lo que no se puede deshacer

Restaurar una copia de seguridad devuelve la base de datos a un instante anterior; lo que sigue **no** se arregla con deshacer dentro de Odoo, o escapa de la base de datos.

| Efecto | Por qué no se revierte | Fuente |
|---|---|---|
| Números de secuencia consumidos | La implementación `standard` de `ir.sequence` usa secuencias nativas de PostgreSQL (`SELECT nextval(...)`), que no se revierten con la transacción; la implementación `no_gap` sí evita huecos con una actualización de fila. | `odoo/addons/base/models/ir_sequence.py`, funciones `_select_nextval` y `_next_do`, rama 20.0; [PostgreSQL, funciones de secuencia](https://www.postgresql.org/docs/current/functions-sequence.html) |
| Correos enviados | `mail.mail` confirma (`commit`) el estado tras cada envío cuando trabaja con `auto_commit`; una vez entregado al servidor SMTP, el correo no vuelve. Además, un reinicio no lo recupera. | `addons/mail/models/mail_mail.py`, método `send` y `_send`, rama 20.0 |
| Asientos contables publicados | Un asiento publicado vuelve a borrador solo si el diario no lo protege con hash y no está bloqueado por fecha de cierre; con hash, Odoo prohíbe editar sus campos y exige solicitar una cancelación. Con asientos ya declarados (impuestos, bloqueo fiscal) no se debe tocar. | `addons/account/models/account_move.py`, `button_draft`, `_compute_show_reset_to_draft_button`, `_check_fiscal_lock_dates`, rama 20.0 |
| Movimientos de stock validados | Un movimiento en estado `done` ya ha cambiado existencias y valoración; en Odoo se corrige con un movimiento inverso (devolución), no desmarcándolo. | `addons/stock/models/stock_move.py`, `_action_done`; la devolución no se leyó: no verificado |
| Pagos | Si el cobro se hizo en una pasarela externa, el dinero se ha movido fuera de Odoo; anular el pago en Odoo no lo devuelve. | Razonamiento general; el código de las pasarelas no se leyó: no verificado |
| Llamadas a servicios externos (webhooks, integraciones) | Salen de la base de datos; ninguna restauración las recupera. | Razonamiento general |

Consecuencia práctica: las pruebas con efectos externos se hacen solo en una copia neutralizada, nunca en producción.

## Actualizar módulos en producción (`-u`)

Actualizar un módulo con `odoo-bin -u <módulo>` (no ejecutado) recarga su código, aplica los cambios de esquema y reescribe los datos XML que el módulo declara. Cómo se carga un módulo y qué hace `-u` se explica en [Módulos y Apps](../fundamentos/Modulos-y-Apps.md). Lo relevante para producción:

- Puede modificar vistas y datos ya personalizados: lo que se hubiera cambiado a mano en un registro de datos de `noupdate="0"` se sobrescribe.
- Si falla a mitad, el código nuevo ya está en disco y el estado de la base no se ha comprobado aquí (no verificado): se asume que hay que volver a la copia de seguridad y al código anterior.
- Actualizar un módulo actualiza también los que dependen de él.
- Desinstalar **no** es el opuesto de instalar: borra las tablas y columnas del módulo con sus datos. El plan de marcha atrás de una instalación fallida es restaurar la copia de seguridad, no pulsar *Desinstalar*.

## Monitorización y reversión

Tras el cambio, durante al menos un ciclo de uso (una jornada; más si hay cierres periódicos):

1. Vigilar el registro del servidor por trazas con `ERROR` y `CRITICAL`.
2. Revisar que los crons programados se ejecutan.
3. Revisar la cola de correo saliente (que no haya un envío masivo inesperado ni acumulación de fallos).
4. Preguntar a las personas usuarias por comportamientos raros.

Se vuelve atrás si se cruza el límite de la ventana sin validar el cambio. La reversión es **restaurar la copia de seguridad previa** (con el tiempo ya medido) y asumir la pérdida del trabajo hecho desde la copia; por eso la ventana debe ser de poco uso. Si ya salieron correos o hubo pagos, se avisa al equipo que corresponda.

## Errores frecuentes

- **Aparecen correos de una copia en los clientes reales** → se restauró una base de producción en staging y se arrancó sin neutralizar. Se neutraliza antes del primer arranque ([Neutralizar la base de datos](Neutralizar-Base-de-Datos.md)).
- **Faltan números de factura o de pedido tras las pruebas en producción** → las secuencias `standard` consumidas no se revierten; los huecos son visibles en la numeración legal.
- **«A mí me funciona» pero Ana Ruiz no puede abrir el pedido S00042** → se validó solo con administración; el fallo está en grupos o reglas de acceso.
- **La restauración tarda tres horas y la ventana era de una** → nunca se midió la restauración en una copia.
- **La copia de seguridad no restaura** → nunca se probó; el fichero estaba incompleto (faltaba el filestore) o corrupto.
- **Una vista rota deja una pantalla inutilizable** → se cambió directamente en producción sin ensayo ni anotación del cambio anterior.
- **Se desinstaló un módulo para «deshacer» y desaparecieron datos** → desinstalar borra tablas y columnas del módulo.
- **Un cron disparó una facturación a mitad de la actualización** → no se pararon las acciones planificadas durante la ventana.

## Buenas prácticas avanzadas

- **Cronometra la restauración**: el tiempo de volver atrás es parte de la ventana; si no cabe, hay que reducir el alcance o ampliar la ventana.
- **Prefiere una copia reciente neutralizada sobre un entorno de pruebas heredado**: un staging viejo oculta problemas que dependen del volumen y de la forma de los datos de hoy.
- **Escribe el cambio como pasos repetibles** (comandos y clics anotados) y ejecuta exactamente eso en staging y en producción; las diferencias manuales entre ambos son la fuente de los fallos «solo en producción».
- **Cambia una sola cosa por ventana** cuando el riesgo es alto: si algo falla, solo hay una causa posible.
- **Congela las escrituras si la restauración es la salida**: pon el sistema en mantenimiento para que nadie cree datos que se perderían al volver atrás.
- **Registra qué se hizo** (hora de inicio, comandos, resultados, hora de fin) para poder decidir y diagnosticar con datos si hay que volver atrás.

## Documentación oficial

- [Actualizaciones (documentación 20.0)](https://www.odoo.com/documentation/20.0/administration/upgrade.html): cómo plantea Odoo ensayar una migración sobre una copia antes de pasar a producción.
- [Ramas y entornos de Odoo.sh](https://www.odoo.com/documentation/20.0/administration/odoo_sh/getting_started/branches.html): el modelo de producción, staging y desarrollo de la plataforma de alojamiento de Odoo.
- [PostgreSQL: funciones de secuencia](https://www.postgresql.org/docs/current/functions-sequence.html): por qué `nextval` no se revierte con la transacción.

---

*En resumen: ensaya en una copia neutralizada, no toques producción sin una copia de seguridad ya restaurada con éxito, ventana de cambio y plan de vuelta; y recuerda que números de secuencia, correos, pagos y llamadas externas no se deshacen restaurando.*
