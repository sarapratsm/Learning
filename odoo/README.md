# Odoo — Guía de tecnología

Colección introductoria sobre **Odoo** (el ERP de código abierto), organizada en diez subcolecciones: los **fundamentos** para entender qué es y cómo está montado (incluida la estructura de datos del ORM, el recordset), las **pruebas seguras** para tocar un sistema en producción sin romperlo, el **desarrollo de búsquedas y filtros** que ve el usuario, las **maneras de configurar parámetros** para no dejar valores clavados en el código, los **mecanismos de notificación** con los que el sistema avisa a las personas, los **botones de acción** con los que una vista dispara código propio sobre un registro concreto, el **systray** con el que se añade un icono propio a la barra de navegación, el **bus de eventos de OWL** con el que dos partes de la interfaz que no se conocen se avisan de un cambio, cómo **contribuir un fix a Odoo o a la OCA** cuando el bug no está en código propio, y los **hitos de proyecto** con los que se marcan las entregas y se factura por ellas. Está escrita para perfiles junior, sin dar por supuesta experiencia previa con Odoo ni con sistemas de gestión.

Cada subcolección tiene su propio índice con orden de lectura. Si empiezas de cero, recórrelas en el orden de abajo.

---

## Subcolecciones

### 1. [Fundamentos](fundamentos/README.md)

Qué es Odoo y cómo está montado por dentro. Necesario para que todo lo demás tenga sentido.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Odoo](fundamentos/Odoo.md) | El punto de partida: qué es, para qué sirve y cómo encaja Python + PostgreSQL. |
| 2 | [Módulos y Apps](fundamentos/Modulos-y-Apps.md) | Cómo se añade funcionalidad; por qué instalar un módulo es un cambio serio. |
| 3 | [Partner, Usuario y Empleado](fundamentos/Partner-Usuario-y-Empleado.md) | Los tres modelos de "persona" de Odoo y por qué no son lo mismo: contacto vs. login vs. ficha laboral. |
| 4 | [Modo desarrollador](fundamentos/Modo-Desarrollador.md) | El interruptor que revela la capa técnica y por qué hay que usarlo con cuidado. |
| 5 | [Recordsets](fundamentos/Recordsets.md) | La estructura de datos que devuelve cualquier consulta del ORM, y la trampa de compararla contra un id plano. |

### 2. [Pruebas seguras](pruebas-seguras/README.md)

El corazón de la guía: dónde probar, cómo aislar los datos reales y cómo tener siempre marcha atrás.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 6 | [Entornos: desarrollo, staging y producción](pruebas-seguras/Entornos-dev-staging-produccion.md) | La idea base: separar entornos para tener un sitio donde equivocarte. |
| 7 | [Duplicar la base de datos](pruebas-seguras/Duplicar-Base-de-Datos.md) | El primer paso: una copia realista de producción para probar sobre datos de verdad. |
| 8 | [Neutralizar la base de datos](pruebas-seguras/Neutralizar-Base-de-Datos.md) | El paso imprescindible: apagar en la copia todo lo que puede escaparse al mundo real. |
| 9 | [Backups y restauración](pruebas-seguras/Backups-y-Restauracion.md) | Tu red de seguridad: cómo volver atrás cuando algo sale mal. |
| 10 | [Pruebas seguras sobre un Odoo en producción](pruebas-seguras/Pruebas-Seguras-en-Produccion.md) | La síntesis: el checklist de buenas prácticas que reúne todo lo anterior. |

### 3. [Búsqueda y filtros](busqueda-y-filtros/README.md)

Ya en clave de desarrollo, cómo se construyen las herramientas de búsqueda y filtrado de un listado.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 11 | [Dominios](busqueda-y-filtros/Dominios.md) | El cimiento: el lenguaje con el que Odoo expresa cualquier filtro. |
| 12 | [Vista de búsqueda](busqueda-y-filtros/Vista-de-Busqueda.md) | Dónde se declaran los filtros, agrupaciones y campos buscables de un listado. |
| 13 | [Search Panel](busqueda-y-filtros/Search-Panel.md) | El panel lateral de filtrado por facetas: el tema estrella y el más visual. |
| 14 | [Dominios dinámicos](busqueda-y-filtros/Dominios-Dinamicos.md) | Filtros que se calculan según el contexto: otro campo, el usuario o una lógica en Python. |

### 4. [Configuración de parámetros](configuracion-parametros/README.md)

Las distintas maneras de guardar un valor configurable en Odoo, para no dejarlo clavado en el código.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 15 | [El fichero odoo.conf](configuracion-parametros/El-Fichero-odoo-conf.md) | La capa de infraestructura: lo que el servidor necesita para arrancar. |
| 16 | [Parámetros del sistema (ir.config_parameter)](configuracion-parametros/Parametros-del-Sistema.md) | El almacén global clave-valor de la base de datos, editable en caliente. |
| 17 | [Ajustes (res.config.settings)](configuracion-parametros/Ajustes.md) | La pantalla amable que expone esos parámetros al usuario de negocio. |
| 18 | [Configuración por compañía](configuracion-parametros/Configuracion-por-Compania.md) | El mismo parámetro con un valor distinto en cada empresa. |
| 19 | [Valores por defecto](configuracion-parametros/Valores-por-Defecto.md) | Qué se precarga en un campo al crear un registro, y desde dónde definirlo. |
| 20 | [Referencias por ID externo (XML ID)](configuracion-parametros/Referencias-por-ID-Externo.md) | Apuntar a un registro concreto sin clavar su ID numérico, y cómo adoptar sin duplicar uno que ya existía a mano. |

### 5. [Notificaciones](notificaciones/README.md)

Cómo avisa Odoo a las personas: el aviso flotante, el diálogo que bloquea, el historial del *chatter*, el correo con plantilla y la tarea con fecha límite. **Colección en curso**: seis fichas escritas y tres pendientes (bus en tiempo real, push del navegador y automatización sin código), detalladas en su propio índice.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 21 | [Tipos de notificación](notificaciones/Tipos-de-Notificacion.md) | El mapa: los diez mecanismos, los cuatro ejes que los separan y la tabla de decisión. |
| 22 | [Notificaciones de interfaz](notificaciones/Notificaciones-de-Interfaz.md) | El aviso flotante: `display_notification` desde Python y el servicio `notification` desde JavaScript. |
| 23 | [Errores y avisos bloqueantes](notificaciones/Errores-y-Avisos.md) | Las excepciones que el cliente sabe presentar, y por qué un `raise` deshace la transacción entera. |
| 24 | [Chatter, mensajes y seguidores](notificaciones/Chatter-y-Seguidores.md) | El historial del registro: `message_post`, subtipos, seguidores y rastreo de campos. |
| 25 | [Plantillas de correo](notificaciones/Plantillas-de-Correo.md) | `mail.template`: renderizado, cola de envío, adjuntos e idioma del destinatario. |
| 26 | [Actividades](notificaciones/Actividades.md) | El aviso que además es trabajo: `activity_schedule`, tipos, cierre y cadenas. |

### 6. [Botones de acción](botones-de-accion/README.md)

De vuelta a las vistas: cómo se añade un botón que ejecuta código propio sobre un registro, y cómo se hereda la vista que lo aloja.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 27 | [Botones de acción en Kanban](botones-de-accion/Botones-de-Accion-en-Kanban.md) | `type="object"`, herencia de vistas con `xpath`, y qué hace Odoo con lo que el método devuelve. |

### 7. [Systray](systray/README.md)

Ya en clave de cliente web: cómo se añade un icono propio a la barra de navegación superior, con su propio componente Owl.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 28 | [Systray](systray/Systray.md) | El registro `systray`, el componente Owl, de dónde salen los datos y cómo se declara en el manifest. |

### 8. [Bus de eventos de OWL](bus-de-eventos-owl/README.md)

Cómo dos componentes que no se conocen entre sí —por ejemplo, un botón de una vista y un icono del systray— se avisan de un cambio dentro de la misma pestaña del navegador.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 29 | [El bus de eventos de OWL (env.bus)](bus-de-eventos-owl/Bus-de-Eventos-OWL.md) | `trigger`, `useBus`, `patch()` y `record.load()`, con ejemplo guiado de principio a fin. |

### 9. [Contribuir un fix a Odoo y a la OCA](contribucion-a-odoo-y-oca/README.md)

Qué hacer cuando el bug no está en código propio: cómo se propone y se acepta una corrección en el núcleo de Odoo o en un módulo de la comunidad (OCA), y qué hacer mientras esa corrección todavía no ha llegado a una instalación real.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 30 | [Contribuir un fix al núcleo de Odoo](contribucion-a-odoo-y-oca/Contribuir-un-Fix-al-Nucleo-de-Odoo.md) | El caso más estricto: el fabricante revisa cada cambio y exige firmar un acuerdo de contribución. |
| 31 | [Contribuir un fix a un módulo de la OCA](contribucion-a-odoo-y-oca/Contribuir-un-Fix-a-un-Modulo-OCA.md) | El caso más abierto: revisión por mantenedores de la comunidad, con linters automáticos más exigentes que compensan la ausencia de un único fabricante. |

### 10. [Hitos de proyecto](hitos-de-proyecto/README.md)

Cómo se marcan los puntos de entrega de un proyecto y, si el pedido de venta lo pide, cómo alcanzar un hito equivale a entregar —y poder facturar— una parte del pedido.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 32 | [Hitos de proyecto](hitos-de-proyecto/Hitos-de-Proyecto.md) | El concepto, la activación global y por proyecto, la herencia a subtareas y el campo que se vacía sin avisar. |
| 33 | [Facturación por hitos](hitos-de-proyecto/Facturacion-por-Hitos.md) | La cadena producto → línea de pedido → hito, los porcentajes y los errores que dan una factura equivocada. |

---

> ¿Te interesa cómo un sistema separa los datos de varios clientes en una misma instalación? Échale un ojo a la guía de [multi-tenancy](../arquitectura-de-software/multi-tenancy/README.md).
