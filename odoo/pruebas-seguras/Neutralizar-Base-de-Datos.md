# Neutralizar la base de datos

## ¿Qué es?

**Neutralizar** una base de datos de Odoo es ejecutar sobre una copia un conjunto de sentencias SQL que desactivan todo lo que puede comunicarse con el exterior: servidores de correo, tareas programadas (*crons*), pasarelas de pago en modo real, transportistas, tokens de servicios de terceros, webhooks. La copia sigue funcionando por dentro con los datos de siempre, pero deja de poder enviar correos, cobrar o sincronizar con sistemas externos.

El mecanismo es el mismo en toda la versión vigente: cada módulo puede aportar un fichero `data/neutralize.sql`, y el comando `neutralize` lee los ficheros de los módulos instalados y los ejecuta. No es una acción de la interfaz web ni un parámetro mágico: es SQL aplicado directamente a las tablas.

Referencias: rama estable `20.0` de `github.com/odoo/odoo` y documentación 20.0, leídas el 2026-11-10. La [página de versiones soportadas](https://www.odoo.com/documentation/20.0/administration/standard_extended_support.html) lista la 20.0 (septiembre de 2026), la 19.0 y la 18.0 con soporte estándar. No se ejecutó ninguna instancia de Odoo ni ningún comando: todo procede de ficheros de código y páginas de documentación leídos, citados en cada punto. Los comandos se presentan como **no ejecutados**.

## ¿Por qué existe?

Una copia de producción hereda la configuración real. Si «Cafés del Valle» copia `cafes_prod` a `cafes_staging` y arranca Odoo sobre la copia, esa copia tiene los mismos servidores de correo con credenciales válidas, los mismos *crons* (recordatorios, facturación recurrente, sincronizaciones), las mismas claves de pasarela de pago y las mismas conexiones con agencias de transporte. Funcionaría como producción con datos reales: podría escribir a Ana Ruiz y a los clientes, repetir un cobro del pedido S00042 o generar una etiqueta de envío, todo desde el servidor de pruebas `staging.ejemplo.com`.

La neutralización corta esos hilos con un único paso, repetible y que no depende de la memoria de quien prepara el entorno.

> Piensa en el **modo avión** del móvil: el aparato sigue encendido y las aplicaciones funcionan, pero no transmite nada hacia fuera. Una base neutralizada está viva por dentro e incomunicada hacia el exterior. Como en el móvil, no borra tu información: solo corta las antenas.

## ¿Cuándo y para qué se usa?

- Al montar un entorno de pruebas o *staging* a partir de una copia de producción (ver [Entornos de desarrollo, staging y producción](Entornos-dev-staging-produccion.md)).
- Al duplicar una base (ver [Duplicar la base de datos](Duplicar-Base-de-Datos.md)).
- Al restaurar un backup de producción en cualquier sitio que no sea producción (ver [Backups y restauración](Backups-y-Restauracion.md)).
- Antes de formaciones, demos o pruebas con datos realistas (ver [Pruebas seguras en producción](Pruebas-Seguras-en-Produccion.md)).

| Situación | ¿Neutralizar? |
|---|---|
| Copia para staging, formación o demo | Sí, siempre |
| Restaurar un backup en un portátil para investigar un error | Sí |
| Restauración de emergencia que sustituye a la propia producción | No: dejaría producción sin correo ni cobros |
| Base creada desde cero sin datos reales | No hace falta |

## Cómo se invoca

Hay tres vías, todas leídas en el código de la rama 20.0.

**1. Comando `neutralize` sobre una base ya existente.** La [referencia de la línea de comandos](https://www.odoo.com/documentation/20.0/developer/reference/cli.html) documenta la sintaxis y las opciones `-d/--database` y `--stdout`:

```bash
# NO EJECUTADO. Neutraliza la base indicada (solo admite una base)
odoo-bin --addons-path <RUTAS> neutralize -d cafes_staging

# NO EJECUTADO. Imprime el SQL que se aplicaría, sin aplicarlo
odoo-bin --addons-path <RUTAS> neutralize -d cafes_staging --stdout
```

`odoo/cli/neutralize.py` exige una única base: sin `-d` registra un error y sale con código 1, y con varias bases sale con el mensaje «please provide a single one». Si algo falla durante la ejecución, registra a nivel crítico `An error occurred during the neutralization. THE DATABASE IS NOT NEUTRALIZED!` y sale con código 1. Con `--stdout` imprime `BEGIN;`, las consultas de cada módulo instalado y `COMMIT;`, lo que permite revisar el SQL antes de aplicarlo.

El `--addons-path` importa: el comando busca `<módulo>/data/neutralize.sql` por la ruta de addons, así que un módulo propio solo se neutraliza si su carpeta está en esa ruta.

**2. Opción `-n/--neutralize` de los subcomandos `db`.** En `odoo/cli/db.py` existen `db restore` y `db duplicate` con la opción `-n, --neutralize`, descrita como «neutralize the database after restore» y «neutralize the target database after duplicate». La referencia de la CLI la documenta igual:

```bash
# NO EJECUTADO
odoo-bin db restore cafes_staging cafes_prod.zip --neutralize
odoo-bin db duplicate cafes_prod cafes_staging --neutralize
```

**3. Casilla del gestor de bases de datos.** `addons/web/controllers/database.py` acepta el parámetro `neutralize_database` en las rutas de duplicar (`duplicate`) y de restaurar (`restore`) del gestor de bases de datos web.

Las dos últimas vías llaman a `odoo/modules/db.py`, que ejecuta la neutralización **antes de que la base sea visible para los workers de crons**: el comentario del código dice «Neutralize the database before it becomes visible to the cron workers». Es la vía más segura porque la ventana de riesgo desaparece. Con la vía 1 el orden lo pones tú.

### Qué hace el comando por dentro

`odoo/modules/neutralize.py` hace tres cosas:

1. Consulta `ir_module_module` y toma los módulos en estado `installed`, `to upgrade` o `to remove`.
2. Los ordena topológicamente: cada módulo va **después** de los módulos de los que depende, de modo que su SQL puede refinar el de sus dependencias. El test `odoo/addons/test_base/tests/test_modules/test_neutralize.py` comprueba que `base` es el primero y que cada dependencia precede a su dependiente.
3. Por cada módulo intenta abrir `<módulo>/data/neutralize.sql`; si el fichero no existe, lo ignora (`suppress(FileNotFoundError)`). Ejecuta cada fichero con `cursor.execute`.

Consecuencia: **solo se neutraliza lo de módulos instalados**, y un módulo sin `neutralize.sql` simplemente no se toca.

## Qué desactiva, módulo a módulo

Contenido literal de los `data/neutralize.sql` de la rama 20.0 (el prefijo de ruta es `github.com/odoo/odoo/blob/20.0/`).

| Módulo (ruta del fichero) | Qué hace |
|---|---|
| `base` (`odoo/addons/base/data/neutralize.sql`) | Desactiva todos los servidores de correo saliente (`ir_mail_server`) y borra `smtp_user` y `smtp_pass`; inserta un servidor ficticio «neutralization - disable emails» (host `invalid`, puerto 1025) para que no se use un servidor de reserva indicado por línea de comandos; desactiva todos los crons excepto `autovacuum_job` de `base`; escribe `database.is_neutralized = 'True'` en `ir_config_parameter`; cambia el `webhook_url` de las acciones de servidor de tipo webhook por «neutralization - disable webhook» |
| `mail` (`addons/mail/data/neutralize.sql`) | Quita el servidor de correo asignado a las plantillas (`mail_template.mail_server_id`); desactiva los servidores de correo entrante (`fetchmail_server`); borra las claves VAPID/JWT de notificaciones push web y `mail.sfu_server_key`; vacía `mail_push` y `mail_push_device` |
| `web` (`addons/web/data/neutralize.sql`) | Activa la vista `web.neutralize_banner`: el banner rojo |
| `website` (`addons/website/data/neutralize.sql`) | Anula el dominio de los sitios web, activa la cinta `website.neutralize_ribbon`, desactiva el CDN y sustituye `robots.txt` por `User-agent: *` / `Disallow: /` |
| `payment` (`addons/payment/data/neutralize.sql`) | Pone `is_live = False` en todos los proveedores de pago |
| `payment_stripe`, `payment_paypal`, `payment_adyen`... (`addons/payment_<proveedor>/data/neutralize.sql`) | Cada proveedor limpia sus credenciales o claves; por ejemplo, Stripe pone a `NULL` `stripe_secret_key`, `stripe_publishable_key` y `stripe_webhook_secret` |
| `delivery` (`addons/delivery/data/neutralize.sql`) | Pone `prod_environment = false` en todos los métodos de envío y desactiva los de transportistas externos (`delivery_type` distinto de `fixed` y `base_on_rule`) |
| `iap` (`addons/iap/data/neutralize.sql`) | Añade el sufijo `+disabled` al token de las cuentas IAP (*In-App Purchase*, servicios de pago por uso de Odoo) |
| `auth_oauth` (`addons/auth_oauth/data/neutralize.sql`) | Desactiva los proveedores OAuth (`enabled = false`) |
| `google_calendar`, `microsoft_calendar` | Borran los tokens de sincronización y marcan la sincronización como detenida |
| `l10n_es_edi_sii` (`addons/l10n_es_edi_sii/data/neutralize.sql`) | Pone la empresa en entorno de pruebas del SII (`l10n_es_sii_test_env = true`) |
| `account_peppol` (`addons/account_peppol/data/neutralize.sql`) | Fija el parámetro `account_peppol.edi.mode` en `demo` |
| `sms_twilio` (`addons/sms_twilio/data/neutralize.sql`) | Sustituye `sms_twilio_auth_token` por `dummytoken` |

El árbol de ficheros de la rama 20.0 incluye además `neutralize.sql` en módulos como `account_edi_proxy_client`, `cloud_storage*`, `google_recaptcha`, `google_address_autocomplete`, `website_cf_turnstile`, decenas de módulos `l10n_*_edi` y varios `pos_*` (terminales de pago). No se leyó cada uno: la lista completa se obtiene con `neutralize -d <base> --stdout` en la propia instalación.

Dos ausencias verificadas en la rama 20.0: `addons/base_automation` y `addons/sms` **no** tienen `data/neutralize.sql`. Las reglas de automatización basadas en tiempo dependen de crons, y los crons ya quedan desactivados por `base`; pero una regla que dispare una acción de servidor de tipo correo o webhook ante un evento de registro (por ejemplo, al confirmar un pedido) actúa en cuanto alguien confirme un pedido en la copia. El correo lo frena el servidor ficticio de `base`; las acciones de otro tipo (Python que llame a una API) no las toca nadie.

La documentación oficial de [base de datos neutralizada](https://www.odoo.com/documentation/20.0/administration/neutralized_database.html) lo resume como «lista no exhaustiva»: acciones planificadas, correo saliente, sincronización bancaria, proveedores de pago, métodos de entrega, tokens IAP y visibilidad del sitio web, con un banner rojo en la parte superior.

## Qué NO neutraliza

- **Módulos sin `neutralize.sql`**: los módulos de terceros, o de la comunidad, que no lo incluyen se quedan como estaban. Una conexión a una API externa programada por ti o por un tercero sigue activa.
- **Los datos personales**: la neutralización no anonimiza. Nombres, correos, teléfonos, importes y facturas siguen en la copia. A efectos de privacidad, un *staging* neutralizado es tan sensible como producción: restringe quién entra y no lo publiques abierto.
- **Credenciales fuera de las tablas que tocan los ficheros**: claves guardadas en parámetros del sistema (`ir_config_parameter`) por módulos propios, o URLs de servicios externas en campos de configuración, no se tocan salvo que lo haga un `neutralize.sql`.
- **Los ficheros del servidor**: `odoo.conf` (servidor SMTP por línea de comandos, claves), certificados y el *filestore* (adjuntos) son externos a la base.
- **Lo que no pasa por Odoo**: reglas de cortafuegos, otros sistemas que lean la base directamente, un proxy inverso.

## Añadir la neutralización a un módulo propio

Si un módulo propio llama a un servicio externo, debe llevar su `data/neutralize.sql`. La estructura es la que usan los módulos oficiales: un fichero SQL de texto plano, que `neutralize.py` localiza por la ruta `<módulo>/data/neutralize.sql` (no se comprobó si los módulos oficiales lo declaran en el manifest; la lectura del código indica que no hace falta).

Ejemplo inventado para un módulo `cafes_envios` con un modelo `cafes_envios_config` que guarda la URL y la clave de una API de reparto (la tabla y los campos son del ejemplo, no de Odoo):

```text
cafes_envios/
├── __manifest__.py
├── data/
│   └── neutralize.sql
└── models/
```

```sql
-- data/neutralize.sql (no ejecutado; modelo de ejemplo)
-- desactiva la integración y retira la clave: un dump con la clave sigue siendo un dump con la clave
UPDATE cafes_envios_config
   SET active = false,
       api_key = NULL;
```

Reglas que se deducen del código leído:

- Pon el módulo en la ruta de addons que se pasa a `neutralize`; si no, el fichero no se leerá.
- Una sentencia que falla aborta la neutralización entera con el mensaje «THE DATABASE IS NOT NEUTRALIZED!»: prueba el SQL contra una copia antes de depender de él.
- El orden es de dependencias: si tu módulo depende de `payment`, tu fichero se ejecuta después del de `payment`.
- Odoo prueba los suyos con un test que ejecuta todos los `neutralize.sql` de los módulos instalados (`test_neutralize.py`); conviene hacer lo mismo con los propios.

## Cómo comprobar que la copia está neutralizada

1. **El parámetro `database.is_neutralized`.** `base/data/neutralize.sql` lo escribe con valor `True`. Es una consulta de solo lectura:

   ```sql
   -- NO EJECUTADO
   SELECT value FROM ir_config_parameter WHERE key = 'database.is_neutralized';
   ```

   El código lo usa: `ir.cron.toggle` en `odoo/addons/base/models/ir_cron.py` devuelve sin hacer nada si el parámetro es verdadero, «para evitar que los crons desactivados se reactiven por efectos secundarios en bases neutralizadas».

2. **El banner.** `web.neutralize_banner` (`addons/web/views/neutralize_views.xml`) es una vista inactiva por defecto que el SQL de `web` activa; muestra el texto «Database neutralized for testing: no emails sent, etc.» sobre fondo rojo y añade `noindex, nofollow`. En sitios web aparece además la cinta «Neutralized» (`website.neutralize_ribbon`).

3. **Los servidores de correo.** En el modo desarrollador, *Ajustes ▸ Técnico ▸ Servidores de correo saliente* debe mostrar solo «neutralization - disable emails». Los nombres de menú pueden variar entre versiones; no se verificaron en interfaz.

4. **Los crons.** *Ajustes ▸ Técnico ▸ Acciones planificadas*: todas desactivadas salvo la de autolimpieza de `base`.

5. **Pasarelas y transportistas.** Los proveedores de pago con credenciales vacías o en modo de pruebas y los métodos de envío externos archivados.

El parámetro y el banner demuestran que el comando se ejecutó, no que tu integración propia quedó apagada: eso solo lo prueba una comprobación específica.

## Orden correcto

```text
restaurar/copiar la base  →  neutralizar  →  arrancar con workers y crons
```

Con `db restore -n`, `db duplicate -n` o la casilla del gestor, el código neutraliza antes de que la base sea visible para los crons. Con `odoo-bin neutralize -d` el orden es responsabilidad tuya: no arranques el servidor sobre la copia, ni siquiera «un momento para ver que abre», hasta haberlo ejecutado.

Lista de comprobación:

- [ ] La base de destino es la copia y no producción (se confirma el nombre antes de ejecutar).
- [ ] El servidor de pruebas no tiene arrancado Odoo sobre esa base.
- [ ] `neutralize` termina sin el mensaje «THE DATABASE IS NOT NEUTRALIZED!».
- [ ] `database.is_neutralized` vale `True` y se ve el banner.
- [ ] Las integraciones propias tienen su `neutralize.sql` o se han desactivado a mano.
- [ ] El acceso al entorno está restringido: los datos siguen siendo reales.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Clientes reciben correos de pruebas desde `staging.ejemplo.com` | Se arrancó el servidor sobre la copia antes de neutralizar, o el correo sale por un servicio no gestionado por `ir_mail_server` |
| El comando termina en segundos y no se ve el banner | Se ejecutó sobre otra base, o falta el módulo `web` en la ruta de addons |
| `THE DATABASE IS NOT NEUTRALIZED!` en el registro y código de salida 1 | Una sentencia SQL falló; el error original aparece justo antes en el registro |
| Un módulo propio sigue llamando a su API | Falta su `neutralize.sql` o su carpeta no está en `--addons-path` |
| Tras refrescar la copia con datos nuevos, vuelven los correos | Se restauró encima de una base ya neutralizada: la neutralización viene en la base, no en el servidor, y se pierde con la restauración |
| Un cobro de prueba llega a la pasarela real | Un módulo de pago de terceros sin `neutralize.sql`, o claves guardadas fuera de `payment_provider` |
| El comando falla por falta de nombre de base | No se pasó `-d`, o se pasaron varias |

## Buenas prácticas avanzadas

- **Neutraliza en el mismo paso que restauras o duplicas** (`-n`, casilla del gestor): el código lo hace antes de que los workers de crons vean la base, algo que con dos pasos manuales no puedes garantizar.
- **Revisa el SQL con `--stdout` en copias nuevas**: es la forma de saber qué se aplicará con tus módulos instalados y de detectar un módulo propio que falte.
- **Borra credenciales, no solo desactives**: los ficheros oficiales anulan `smtp_pass`, claves de Stripe y tokens porque un volcado de la copia archivada seguiría llevando credenciales válidas.
- **Prueba el comando tras cada actualización de versión mayor**: los ficheros cambian entre versiones, y el árbol de 20.0 ya incluye módulos que antes no existían.
- **Trata la neutralización como una capa, no como la defensa completa**: combínala con un cortafuegos de salida en el servidor de pruebas y con acceso restringido.

## Documentación oficial

- [Neutralized database](https://www.odoo.com/documentation/20.0/administration/neutralized_database.html): lista no exhaustiva de lo que se desactiva y el banner rojo.
- [Command-line interface: neutralize y db](https://www.odoo.com/documentation/20.0/developer/reference/cli.html): opciones `-d`, `--stdout`, y `-n/--neutralize` de `db restore` y `db duplicate`.
- [`odoo/modules/neutralize.py`](https://github.com/odoo/odoo/blob/20.0/odoo/modules/neutralize.py): el algoritmo completo en menos de 50 líneas.

---

*En resumen: neutralizar es aplicar los `data/neutralize.sql` de los módulos instalados para dejar una copia viva por dentro e incomunicada hacia fuera; se hace antes de que arranquen los crons, no anonimiza datos y no cubre módulos sin su propio `neutralize.sql`.*
