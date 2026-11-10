# Odoo

## ¿Qué es?

Odoo es un **ERP** (*Enterprise Resource Planning*, sistema de gestión empresarial) modular: una única plataforma con aplicaciones de ventas, facturación, inventario, contabilidad, RRHH, CRM, proyectos, punto de venta, web y muchas más. El servidor está escrito en Python, guarda los datos en PostgreSQL y se usa desde el navegador. Existe en dos ediciones: **Community**, de código abierto bajo LGPL v3, y **Enterprise**, con módulos adicionales bajo una licencia propietaria.

## ¿Por qué existe?

Una empresa necesita muchas herramientas: una para vender, otra para facturar, otra para el almacén, otra para las nóminas. Si cada una es un programa aparte, los datos no se hablan entre sí y alguien acaba copiándolos a mano de un sitio a otro.

Odoo pone **todas esas aplicaciones sobre la misma base de datos**. Un pedido de venta confirmado puede generar la entrega de almacén y la factura sin reintroducir datos, porque ventas, inventario y contabilidad leen y escriben las mismas tablas.

> Si ya conoces el mundo web, piensa en Odoo como un WordPress de la gestión empresarial: un núcleo al que se le enchufan módulos para añadir funciones. La diferencia es que aquí los módulos comparten un modelo de datos relacional común (clientes, productos, empresas), no solo un sistema de plugins.

## ¿Cuándo y para qué se usa?

Aparece cuando una organización quiere centralizar su operativa. El ejemplo es una pequeña empresa de cafés que vende productos a clientes: un cliente («Cafés del Valle»), un pedido de venta (`S00042`) y una empleada («Ana Ruiz») que lo gestiona. Todos los datos de ejemplo son inventados.

- Una **tienda online** que gestiona catálogo, pedidos, stock y facturas desde un mismo lugar.
- Una **empresa de servicios** que lleva proyectos, partes de horas y facturación.
- Un **taller o fábrica** que controla órdenes de fabricación, materiales y compras.

## Ediciones y licencia

La documentación oficial (página *Licenses*, versión 20.0) fija dos licencias:

| | Community | Enterprise |
|---|---|---|
| Licencia | LGPL v3 | *Odoo Enterprise Edition License v1.0* (propietaria) |
| Uso | Libre: se puede ejecutar, modificar y redistribuir según la LGPL | Solo con una suscripción Enterprise válida para el número correcto de usuarios; prohibido publicar, distribuir o vender copias |
| Código | Público en [github.com/odoo/odoo](https://github.com/odoo/odoo) | Fuentes compartidas con quien tiene suscripción |
| Módulos propios | Los que se desarrollen pueden distribuirse bajo la licencia que se elija, si es compatible | Igual: licencia compatible con la de Enterprise (LGPL, MIT o propietaria similar) |

Dos matices comprobados en las fuentes:

- La página de licencias, en la documentación 20.0, está redactada para «Odoo 19» y dice que las licencias de las versiones 9 a 18 son las mismas. Para la 20.0, el fichero `LICENSE` de la rama `20.0` de `odoo/odoo` sigue declarando LGPL v3, y el `__manifest__.py` de módulos como `sale` o `account` lleva `'license': 'LGPL-3'`.
- Odoo 8 usaba AGPL v3; desde la 9 es LGPL. Una guía antigua que hable de AGPL describe una versión que ya no tiene soporte.

**Qué diferencia técnicamente a las ediciones.** El tutorial oficial de arquitectura lo resume así: Enterprise ofrece funcionalidades extra que, técnicamente, son **módulos nuevos instalados encima de los de Community**. La documentación de migración lo confirma: pasar de Community a Enterprise consiste en añadir el módulo `web_enterprise` (más el resto de módulos Enterprise en el `addons-path`), actualizar la base con `-i web_enterprise` e introducir el código de suscripción. No se migran los datos: es la misma base de datos.

El repositorio público de la rama `20.0` contiene `account`, `sale`, `stock`, `mrp`, `crm`, `project`, `hr`, `point_of_sale` o `website`, y **no** contiene `web_enterprise`, `account_accountant`, `web_studio`, `sign`, `helpdesk` ni `documents` (comprobado en el listado del directorio `addons/` el 2026-11-10). La lista completa de lo que incluye cada edición vive en la web comercial de Odoo y no se ha contrastado aquí.

## Arquitectura

La documentación oficial describe Odoo como una **arquitectura multicapa de tres niveles**:

| Capa | Tecnología | Qué hace |
|---|---|---|
| Presentación | HTML5, JavaScript, CSS; cliente web con el framework **OWL** | Pinta vistas, envía las acciones del usuario |
| Lógica | Python (la rama 20.0 exige Python 3.12 a 3.14: `MIN_PY_VERSION`/`MAX_PY_VERSION` en `odoo/release.py`) | Modelos, reglas de negocio, seguridad, controladores HTTP |
| Datos | PostgreSQL (la documentación de instalación de la 20.0 pide 16 o superior) | Persistencia; es el único motor soportado |

OWL es el framework de componentes propio de Odoo; el tutorial oficial indica que desde la 15.0 el cliente transiciona hacia él. Sus detalles están en [frontend-js](../frontend-js/README.md).

### Modelo, vista y controlador en Odoo

Dentro de la capa de lógica, un módulo de Odoo reparte el trabajo como en un MVC clásico. La documentación habla de «tres niveles» y no de MVC; este reparto es una lectura didáctica de los elementos que, según la misma documentación, componen un módulo:

| Pieza MVC | En Odoo | Dónde vive |
|---|---|---|
| Modelo | Clase Python con campos; el ORM mapea los campos a columnas | `models/*.py` |
| Vista | Definiciones XML de formularios, listas, kanban, búsquedas; plantillas QWeb | `views/*.xml` |
| Controlador | Controlador web que atiende rutas HTTP | `controllers/*.py` |

Cuidado con el término: en Odoo el «controlador» es el que atiende rutas HTTP (por ejemplo las de la web pública o las llamadas JSON). La lógica de negocio **no** se escribe ahí: se escribe en métodos del modelo, que el cliente invoca de forma genérica. Un botón «Confirmar» de un pedido es una acción de vista que llama a un método del modelo `sale.order`, no a un controlador.

### Las piezas que sostienen a un modelo

Sobre cada modelo se apoyan cuatro piezas más, todas declaradas por los módulos como datos:

- **ORM** (*Object-Relational Mapping*): la capa que traduce clases Python a tablas y operaciones de base de datos. Se usa a través de *recordsets*: [Recordsets](Recordsets.md).
- **Vistas XML**: registros del modelo `ir.ui.view`. Por ejemplo, el formulario del pedido de venta es el registro `view_order_form` de `addons/sale/views/sale_order_views.xml`:

  ```xml
  <record id="view_order_form" model="ir.ui.view">
      <field name="name">sale.order.form</field>
      <field name="model">sale.order</field>
      <field name="arch" type="xml">
          <form string="Sales Order" class="o_sale_order" js_class="sale_order_form">
  ```

- **Acciones**: registros que dicen qué abrir. Una acción de ventana (`ir.actions.act_window`) enlaza un modelo con sus tipos de vista. Fragmento literal de la misma ficha de la rama 20.0:

  ```xml
  <record id="action_orders" model="ir.actions.act_window">
      <field name="name">Sales Orders</field>
      <field name="res_model">sale.order</field>
      <field name="view_mode">list,kanban,form,calendar,pivot,graph,activity</field>
  ```

- **Menús**: registros `ir.ui.menu` que cuelgan una acción de la barra de navegación. En `addons/sale/views/sale_menus.xml`, el menú «Orders» apunta a `action_orders` y solo lo ven los miembros del grupo `sales_team.group_sale_salesman`.

La cadena completa es: **menú → acción → vistas → modelo**. Un módulo la declara entera en ficheros XML y CSV listados en su `__manifest__.py` (clave `data`). Cómo se empaquetan, instalan y actualizan los módulos: [Módulos y Apps](Modulos-y-Apps.md).

### Seguridad: grupos, permisos y reglas de registro

La seguridad se declara con datos, no con código. Los usuarios pertenecen a **grupos** (`res.groups`; un grupo puede implicar a otros) y los permisos se asignan a grupos. La referencia oficial *Security in Odoo* distingue dos preguntas:

1. **¿Puede este grupo hacer esta operación (crear, leer, modificar, borrar) sobre este modelo?** Es el *permiso de acceso*. Si ninguno de los grupos del usuario lo concede, no hay acceso. Los permisos se suman: la unión de todos los grupos.
2. **¿Sobre qué registros concretos?** Es la *regla de registro*: un dominio que filtra los registros permitidos (por ejemplo, un comercial solo ve sus pedidos o los de su empresa).

La forma de declararlo **cambió en la 20.0**:

| Rama | Permisos | Reglas de registro |
|---|---|---|
| 18.0 y 19.0 | Modelo `ir.model.access`, fichero `security/ir.model.access.csv` | Modelo `ir.rule`, fichero `security/ir_rules.xml` |
| 20.0 | Modelo `ir.access`, fichero `security/ir.access.csv` (columnas `operation` con valores como `cru` y `domain`) | Mismo modelo `ir.access`: una fila sin grupo es una restricción global |

Se comprobó listando `addons/sale/security/` en las ramas 18.0, 19.0 y 20.0, y leyendo `odoo/addons/base/models/ir_access.py` de la 20.0; no se leyó el contenido de la 18.0 más allá de la presencia de esos ficheros. Fila de ejemplo literal de `addons/sale/security/ir.access.csv` (20.0): `access_account_analytic_account_salesman,account_analytic_account salesman,account.analytic.account,sales_team.group_sale_salesman,cru,` (grupo de comerciales, operaciones crear/leer/modificar, sin dominio).

Cuando alguien sin permiso intenta algo, el ORM lanza un error de acceso (`AccessError`). El detalle de cómo se evalúan permisos y reglas, incluido el significado de las reglas globales y de grupo, está en la referencia oficial citada al final.

## El ciclo de una petición

Cuando se pulsa un botón o se abre una lista, el navegador no pide páginas HTML nuevas: el cliente OWL llama al servidor con JSON-RPC y repinta con la respuesta. A nivel conceptual:

```
Navegador (cliente OWL)
   │  POST /web/dataset/call_kw/<modelo>/<método>    (JSON-RPC 2.0)
   ▼
Servidor Odoo (Python, proceso HTTP)
   │  controlador `call_kw` (auth="user")   ← valida sesión
   │  call_kw(request.env[modelo], método, args, kwargs)
   ▼
ORM (métodos del modelo)
   │  comprueba permisos y reglas de registro (grupos del usuario)
   │  ejecuta la lógica de negocio del método
   ▼
PostgreSQL  ←  SELECT / INSERT / UPDATE generados por el ORM
   │
   └─ resultado ─► ORM ─► controlador ─► respuesta JSON ─► navegador
```

Cada flecha corresponde a código leído en la rama 20.0:

- `addons/web/static/src/core/orm_plugin.js` construye la URL `/web/dataset/call_kw/${model}/${method}`, y `addons/web/static/src/core/network/rpc.js` envía el sobre `{id, jsonrpc: "2.0", method: "call", params}` por `XMLHttpRequest`.
- `addons/web/controllers/dataset.py` declara `@http.route(['/web/dataset/call_kw', '/web/dataset/call_kw/<path:path>'], type='jsonrpc', auth="user", ...)` y ejecuta `call_kw(request.env[model], method, args, kwargs)`.
- `odoo/service/model.py`, función `call_kw`: invoca el método del modelo solicitado; **los métodos privados no se pueden llamar** por esta vía, solo los que devuelve `get_public_method`.
- El tipo de ruta `jsonrpc` es el que en la 18.0 y anteriores se llamaba `type='json'` (así lo indica el aviso de la documentación *External RPC API*).

Una consecuencia práctica: cualquier método público de un modelo es, en principio, invocable por un cliente. La documentación de seguridad lo advierte: los permisos solo se comprueban en las operaciones CRUD, no al entrar al método. Por eso la lógica sensible debe comprobar permisos ella misma, y los métodos internos deben empezar por `_`.

`odoo/service/server.py` define tres tipos de servidor: `ThreadedServer` (hilos), `PreforkServer` (procesos *worker*) y `GeventServer` (conexiones largas, puerto `--gevent-port`, por defecto 8072). La opción `--workers` vale 0 por defecto y, según su texto de ayuda en `odoo/tools/config.py`, 0 desactiva el modo prefork.

## Estructura de una base de datos Odoo

Una base de datos de Odoo es un esquema relacional corriente, y la regla de nombres es mecánica. En `odoo/orm/model_classes.py` (rama 20.0): `model_cls._table = model_cls._name.replace('.', '_')`. El nombre de tabla es el `_name` del modelo con los puntos convertidos en guiones bajos, salvo que el modelo defina `_table` a mano.

| Modelo (`_name`) | Tabla | Qué guarda | Verificado en |
|---|---|---|---|
| `res.partner` | `res_partner` | Contactos: personas y empresas (clientes, proveedores) | `odoo/addons/base/models/res_partner.py` |
| `res.users` | `res_users` | Usuarios que inician sesión; hereda de `res.partner` con `_inherits` | `odoo/addons/base/models/res_users.py` |
| `res.groups` | `res_groups` | Grupos de seguridad | `res_groups.py` |
| `sale.order` | `sale_order` | Cabecera de pedido de venta | `addons/sale/models/sale_order.py` |
| `sale.order.line` | `sale_order_line` | Líneas del pedido | `sale_order_line.py` |
| `hr.employee` | `hr_employee` | Empleados | `addons/hr/models/hr_employee.py` |
| `ir.model` | `ir_model` | Catálogo de modelos instalados | `ir_model.py` |
| `ir.model.data` | `ir_model_data` | IDs externos (identificador textual de cada registro creado por un módulo) | `ir_model.py` |
| `ir.ui.view` | `ir_ui_view` | Vistas XML | `ir_ui_view.py` |
| `ir.ui.menu` | `ir_ui_menu` | Menús | `ir_ui_menu.py` |
| `ir.actions.act_window` | `ir_act_window` | Acciones de ventana (`_table` fijado a mano) | `ir_actions.py` |
| `ir.access` (20.0) | `ir_access` | Permisos y reglas de registro | `ir_access.py` |

Los prefijos delatan el origen: `res_*` son recursos base (empresas, usuarios, monedas), `ir_*` son la maquinaria interna de Odoo (modelos, vistas, acciones, menús, cron), y el resto lleva el nombre del módulo que los define (`sale_`, `hr_`, `account_`).

Las relaciones son claves foráneas habituales. Los campos del modelo `sale.order` de la rama 20.0 que importan aquí:

```python
partner_id = fields.Many2one(comodel_name="res.partner", string="Customer", required=True, ...)
order_line = fields.One2many(comodel_name="sale.order.line", inverse_name="order_id", ...)
state = fields.Selection(selection=SALE_ORDER_STATE, ..., default="draft")
```

```python
SALE_ORDER_STATE = [("draft", "Quotation"), ("sent", "Quotation Sent"),
                    ("sale", "Sales Order"), ("cancel", "Cancelled")]
```

Traducido al esquema, para el pedido `S00042` de «Cafés del Valle»: `sale_order` tiene una columna `partner_id` que apunta a la fila de «Cafés del Valle» en `res_partner`; `sale_order_line` apunta a `sale_order` mediante `order_id`; y la columna `state` guarda uno de los cuatro valores técnicos (`draft`, `sent`, `sale`, `cancel`) de los que la interfaz muestra la etiqueta («Quotation», «Sales Order»…). Un `Many2many` crea una tabla intermedia con sufijo `_rel` (por ejemplo, `sale_order_transaction_rel` en el mismo modelo).

Una consulta de **solo lectura** para inspeccionar ese esquema desde `psql` sería:

```sql
SELECT o.name, o.state, p.name AS cliente
FROM sale_order o
JOIN res_partner p ON p.id = o.partner_id;
```

No hay salida real que mostrar: los nombres de tabla y de columna proceden de leer el código fuente de la rama 20.0 (el 2026-11-10), no de ejecutar una instancia. Para modificar datos, nunca `UPDATE` directo: el ORM mantiene campos calculados, caché, historial (*chatter*) y permisos que un `UPDATE` salta.

### Modelos y personas

`res.partner` no es solo «el cliente»: es el contacto genérico que usan clientes, proveedores y también el usuario y, indirectamente, el empleado. Cuándo usar cada uno: [Partner, Usuario y Empleado](Partner-Usuario-y-Empleado.md).

## Versiones y ciclo de soporte

Cada año sale una versión mayor (`18.0`, `19.0`, `20.0`) y, entre ellas, versiones intermedias *SaaS* solo para Odoo Online. Según la página oficial *Standard and extended support* (consultada el 2026-11-10):

- **Soporte estándar**: los tres primeros años desde el lanzamiento, en Online, Odoo.sh y on-premise. Las **actualizaciones de seguridad** solo se entregan en esta fase.
- **Soporte extendido**: empieza al terminar el estándar, cuesta aparte, solo está en Odoo.sh (para un número limitado de versiones) y en on-premise, y las correcciones se dan «donde sea técnicamente posible».
- Se puede actualizar desde cualquier versión a cualquier versión mayor con soporte estándar, o que lo perdiera hace menos de seis meses.

Estado el 2026-11-10 (los colores de la leyenda de la tabla original se leyeron en el HTML de la página):

| Versión | Lanzamiento | Fin del soporte estándar | Situación hoy |
|---|---|---|---|
| 20.0 | septiembre 2026 | septiembre 2029 (previsto) | Estándar en Online, Odoo.sh y on-premise |
| 19.0 | septiembre 2025 | septiembre 2028 (previsto) | Estándar en las tres plataformas |
| 18.0 | octubre 2024 | septiembre 2027 (previsto) | Estándar en las tres plataformas |
| 17.0 | noviembre 2023 | septiembre 2026 | Estándar terminado; extendido en Odoo.sh y on-premise; sin soporte en Online |
| 16.0 | octubre 2022 | septiembre 2025 | Solo extendido (Odoo.sh y on-premise) |
| 15.0 | octubre 2021 | octubre 2024 | Solo extendido (Odoo.sh y on-premise) |
| Anteriores a 15.0 | antes de 2021 | antes de 2024 | Sin soporte en Online ni Odoo.sh; solo extendido on-premise |

Las versiones intermedias *SaaS* (19.1 a 19.4 en la tabla) solo existen en Odoo Online, no tienen soporte extendido y ni Odoo.sh ni on-premise pueden usarlas.

Para elegir versión de partida, la rama mayor más reciente con soporte estándar es la 20.0. 

## Formas de alojarse

| Opción | Qué es | Código propio | Elegirla cuando |
|---|---|---|---|
| **Odoo Online** | Bases privadas alojadas y gestionadas por Odoo, accesibles desde el navegador | **No**: incompatible con módulos propios y con los de la tienda Odoo Apps | Se usa lo estándar y se quiere cero administración |
| **Odoo.sh** | Plataforma cloud oficial de Odoo: ramas, *builds*, integración continua, shell web y acceso SSH | Sí | Hay módulos propios y se quiere que Odoo opere la infraestructura |
| **On-premise** | Se instala y opera por cuenta propia (servidor propio o VPS) con el paquete oficial o desde el código fuente | Sí, con control total | Se necesita control del servidor, del `odoo.conf`, de las copias o de los datos |

Datos comprobados en la documentación 20.0 que condicionan la elección:

- Una base on-premise con Enterprise se registra con el código de suscripción, **una base por suscripción**; para pruebas se duplica (con la opción de neutralizar, que ejecuta los `neutralize.sql` de cada módulo). Ver [Entornos dev, staging y producción](../pruebas-seguras/Entornos-dev-staging-produccion.md).
- Mover una base de on-premise a Online exige desinstalar antes todos los módulos no estándar.
- El **acceso externo a datos por API** solo está disponible en los planes *Custom* de Odoo Online; los planes *One App Free* y *Standard* no lo incluyen (documentación *External JSON-2 API*).
- Los precios y las condiciones de cada plan no están en la documentación técnica y no se han contrastado.

## Integración externa: la API vigente

La API externa para leer y escribir datos desde fuera cambió. En la documentación 20.0:

- **JSON-2** (nueva en la 19.0): `POST /json/2/<modelo>/<método>`, con cabecera `Authorization: bearer <API key>` y cuerpo JSON.
- Los servicios **XML-RPC** (`/xmlrpc`, `/xmlrpc/2`) y **JSON-RPC** (`/jsonrpc`) están **obsoletos**: el servicio `db` se eliminó en la 20.0 y `common` y `object` se eliminarán en la 22 (otoño de 2028). Las rutas propias de módulos con `type='jsonrpc'` no están afectadas.

Ejemplo (tomado de la propia documentación, con un nombre de empresa y host inventados):

```http
POST /json/2/res.partner/search_read HTTP/1.1
Host: mycompany.example.com
X-Odoo-Database: mycompany
Authorization: bearer <API key>
Content-Type: application/json; charset=utf-8

{"domain": [["name", "ilike", "%valle%"], ["is_company", "=", true]], "fields": ["name"]}
```

La respuesta correcta es un `200` con el valor devuelto por el método serializado como JSON (una lista de diccionarios con `id` y `name` para este caso). Pedir siempre `fields` evita traer todos los campos del modelo.

## Cuándo NO usar Odoo

Criterio propio, apoyado en los hechos de las secciones anteriores:

| Situación | Por qué encaja mal |
|---|---|
| Un único proceso muy simple (una hoja de cálculo basta, un formulario y un correo) | Se asume el coste de operar un ERP, con su base de datos y sus actualizaciones anuales, para usar una fracción mínima |
| Se necesita otro motor de base de datos o un cambio de pila (Java, .NET) | Los datos son solo PostgreSQL y la lógica solo Python; no se sustituyen |
| Un producto cuyo núcleo es otra cosa (un videojuego, una app de streaming, un sistema de tiempo real) | Odoo es un framework para aplicaciones de gestión con formularios, listas y flujos de documentos |
| Se quiere usar la edición **Online** con módulos propios | Es incompatible; hace falta Odoo.sh u on-premise |
| Se espera «instalar y olvidarse» | Hay una versión mayor al año y el soporte estándar dura tres; los módulos de terceros pueden no existir para la versión nueva |
| Procesos muy específicos que obligarían a reescribir la mayoría de los modelos | Se acaba manteniendo un fork del ERP en lugar de usar el ERP |

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Un registro «ha desaparecido» de las listas | Está archivado: casi todos los modelos tienen un campo `active`, y la búsqueda oculta los inactivos. Se ve añadiendo el filtro *Archivado* |
| Una guía antigua usa XML-RPC y el endpoint no existe en la 20.0 | `common` y `object` están obsoletos y el servicio `db` ya se eliminó. Usar `/json/2` |
| Un módulo antiguo no instala en la versión nueva | Es un módulo de una rama anterior; los módulos se portan por versión (`17.0`, `18.0`, `19.0`, `20.0`) |
| La documentación de una versión dice que existe `ir.model.access`/`ir.rule` y la base 20.0 no | En la 20.0 se unificaron en `ir.access` |
| Un `UPDATE` por SQL «funciona» pero la interfaz muestra datos viejos o inconsistentes | El ORM mantiene cachés y campos calculados que el SQL directo no actualiza |
| Todos los usuarios quedan bloqueados mientras una petición tarda | Con `--workers` en 0 (el valor por defecto) no hay procesos *worker*; una operación lenta puede degradar al resto |
| Una llamada externa a Odoo Online devuelve error de acceso a la API | El plan contratado no incluye API externa (solo *Custom*) |

## Buenas prácticas avanzadas

- **Archivar antes que borrar**: casi todos los modelos tienen `active`. Archivar oculta el registro de búsquedas y vistas sin romper lo que lo referencia (pedidos antiguos, apuntes contables). Quien domina Odoo sabe que un registro «perdido» suele estar archivado.
- **Resolver los registros por ID externo, no por `id` numérico**: el `id` de base de datos cambia entre bases (producción, staging, copias). El ID externo (`modulo.nombre`, tabla `ir_model_data`) es estable. Referencias: [Referencias por ID externo](../configuracion-parametros/Referencias-por-ID-Externo.md). También hace repetibles las importaciones: reimportar un fichero con una columna `id` externa estable actualiza en vez de duplicar.
- **Tratar `odoo.conf` de desarrollo como no apto para producción**: el valor por defecto de `workers` es 0 (modo hilos); en producción se configuran `workers`, `proxy_mode` detrás del proxy inverso (por defecto `False`) y los límites `limit_time_cpu` (60 por defecto) y `limit_time_real` (120). Ver [El fichero odoo.conf](../configuracion-parametros/El-Fichero-odoo-conf.md).
- **No confiar en el permiso de CRUD para proteger un método público**: los permisos y reglas se comprueban al leer o escribir, no al entrar en el método. Un método público es invocable desde `/web/dataset/call_kw`. Lo que no debe llamarse desde fuera lleva prefijo `_`.
- **Elegir la versión como decisión de ciclo de vida**: el soporte estándar es de tres años y las actualizaciones de seguridad solo llegan en esa fase. Si se parte de una versión a mitad de vida, el margen de uso real es menor. Antes de depender de un módulo de terceros, comprobar que existe para la rama exacta (20.0, 19.0…).
- **Activar el modo desarrollador solo cuando hace falta**: revela menús y opciones técnicas (modelos, campos, vistas). Ver [Modo desarrollador](Modo-Desarrollador.md).

## Documentación oficial

- [Chapter 1: Architecture Overview](https://www.odoo.com/documentation/20.0/developer/tutorials/server_framework_101/01_architecture.html) — la explicación oficial de las tres capas, de qué se compone un módulo y de cómo se relacionan Community y Enterprise.
- [Standard and extended support](https://www.odoo.com/documentation/master/administration/standard_extended_support.html) — la tabla de versiones y plataformas; es la que hay que consultar antes de elegir versión o plataforma.
- [Licenses](https://www.odoo.com/documentation/20.0/legal/licenses.html) — los textos de las licencias LGPL v3 de Community y Enterprise v1.0, y la de las Odoo Apps.
- [Security in Odoo](https://www.odoo.com/documentation/20.0/developer/reference/backend/security.html) — grupos, permisos, reglas globales y de grupo, y los errores de seguridad típicos.

---

*En resumen: Odoo es un conjunto de aplicaciones de gestión que comparten una sola base de datos PostgreSQL, un servidor Python y un cliente web OWL; Community (LGPL v3) y Enterprise (propietaria) comparten el mismo núcleo y la segunda añade módulos, y en la 20.0 las tres versiones con soporte estándar son 18.0, 19.0 y 20.0.*
