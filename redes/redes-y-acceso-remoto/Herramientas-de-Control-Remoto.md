# Herramientas de Control Remoto (TeamViewer, AnyDesk, RustDesk...)

## ¿Qué es?

Programas como **TeamViewer**, **AnyDesk**, **RustDesk**, **Chrome Remote Desktop** o **Quick Assist** de Windows que permiten ver y controlar la pantalla de otro equipo por internet **sin tocar el router ni abrir puertos**. Hacen lo mismo que [RDP](Escritorio-Remoto.md) o [VNC](VNC.md), pero en lugar de exigir que un equipo sea alcanzable desde fuera, los dos extremos se conectan a un servidor intermedio que los pone en contacto.

## ¿Por qué existe?

RDP y VNC suponen que el equipo al que quieres entrar es **alcanzable**: tiene una IP y un puerto (3389 o 5900) al que se puede llegar. Dentro de la red local es cierto; desde internet casi nunca lo es. El equipo está detrás del router de la oficina o de la casa, que hace NAT (traduce las direcciones privadas a una sola pública) y descarta todo lo que entra sin que nadie lo haya pedido. Para llegar hay que configurar una [redirección de puertos](Redireccion-de-Puertos.md) —con el riesgo de dejar RDP expuesto— o montar una [VPN](VPN.md). Eso exige acceso al router, a veces imposible (el router es del proveedor, la oficina del cliente tiene IT propio) y casi siempre fuera del alcance de quien solo necesita «ver qué le pasa al ordenador».

Estas herramientas invierten la dirección de la conexión. Un router deja salir todo lo que el equipo inicia, así que ambos extremos **llaman hacia fuera** a un servidor público, y ese servidor los empareja:

```text
RDP / VNC clásicos:  tú ──────────────► [router: ¿puerto abierto?] ──► equipo

Control remoto con intermediario:
   equipo ──(saliente, 443 o similar)──► servidor de la empresa ◄──(saliente)── tú
```

> Si RDP/VNC son «llamar directamente al número de teléfono de un equipo», estas herramientas son «una centralita a la que llaman los dos y que los pone en contacto, sin que ninguno conozca el número del otro».

## ¿Cuándo y para qué se usa?

Escenarios con la tienda online del ejemplo (servidor en el VPS `203.0.113.10`, dominio `tienda.ejemplo.com`, oficina en `192.168.1.0/24`):

- **Soporte puntual**: la persona de administración llama porque el ordenador `192.168.1.20` no imprime; quien da soporte entra, mira y arregla en diez minutos.
- **Acceder a tu propio equipo de oficina** desde casa, cuando no hay VPN ni nadie con acceso al router.
- **Formación y demostraciones**: compartir pantalla con un control limitado que se cierra al acabar.
- **Mantenimiento de equipos de usuario** repartidos por varias sedes sin red común.

Para administrar servidores, la herramienta adecuada es otra ([SSH](SSH.md) y, si hace falta, [VPN](VPN.md)); más abajo se detalla por qué.

## Cómo funciona la conexión

### Las piezas

| Pieza | Qué hace |
|---|---|
| **Cliente** (en cada equipo) | Captura la pantalla, envía teclado y ratón, mantiene una conexión saliente con el servidor. |
| **Servidor de registro / rendezvous** | Sabe qué ID está conectado y desde qué dirección pública; presenta a los dos extremos. |
| **Relay** (retransmisor) | Reenvía el tráfico entre ambos cuando no pueden hablar directamente. |

### Primero directo, luego relay

1. El equipo controlado arranca y **registra su ID** en el servidor de la empresa con una conexión saliente. La mantiene viva.
2. Quien controla introduce ese ID. El servidor avisa al equipo controlado y da a cada lado la dirección pública del otro.
3. Los dos intentan una conexión directa mediante *hole punching* («agujerear» el NAT): cada lado envía paquetes al otro a la vez, de modo que cada router cree que la respuesta es de una conexión que él mismo inició y deja pasar el tráfico.
4. Si el NAT es demasiado estricto (típico en redes corporativas, CG-NAT de operadores móviles) y el agujero falla, todo el tráfico **pasa por el relay**.

Funciona sin abrir puertos porque **nunca hay una conexión entrante no solicitada**: todas las conexiones nacen de dentro hacia fuera. La documentación de RustDesk describe este mismo esquema (el cliente avisa constantemente a `hbbs` de su IP y puerto; para conectar se intenta *hole punching* y, si falla, el tráfico va por `hbbr`). TeamViewer y AnyDesk documentan conexiones intermediadas por sus servidores con el mismo principio general; el detalle de cuándo usan directo o relay es propio de cada producto y no está desarrollado aquí.

Consecuencia práctica: ambos extremos necesitan **salida a internet**. Si el servicio de la empresa cae, o un proxy corporativo bloquea sus servidores, no hay sesión.

## Cómo se identifica cada equipo

En RDP/VNC la dirección es una IP. Aquí es un **ID** que asigna la herramienta, independiente de la IP y estable aunque el equipo cambie de red. Para que alguien entre hace falta, además del ID, una **autorización**. Hay tres modelos:

| Modelo | Cómo se autoriza | Ejemplos |
|---|---|---|
| **Código de un solo uso** | La persona que recibe ayuda genera un código y se lo da a quien ayuda; deja de valer al usarse o al caducar. | Quick Assist (6 dígitos), Chrome Remote Desktop (código de «Compartir pantalla», un solo uso) |
| **ID + contraseña** | El equipo muestra su ID y una contraseña (temporal o fija); el controlador necesita ambos. | TeamViewer, AnyDesk, RustDesk |
| **Cuenta + aprobación** | Ambas personas inician sesión con una cuenta (de la organización); el acceso lo gobierna la cuenta y, en su caso, políticas administrativas. | Remote Help de Microsoft (cuentas de Entra ID de la misma organización), Chrome Remote Desktop con PIN en tus propios equipos |

Detalles verificados en la documentación vigente (2026-11-10):

- **Quick Assist**: quien ayuda elige «Help someone» y comparte un código de 6 dígitos; quien recibe ayuda lo introduce. Quien ayuda ve la pantalla cuando se le permite y puede **pedir control** (`Request control`) que quien recibe acepta o no, y cancelar cuando quiera. La página de soporte de Microsoft no indica cuánto dura el código.
- **Chrome Remote Desktop**: en `remotedesktop.google.com/support` se genera un código de un solo uso. Al conectarse, quien comparte ve el correo de quien entra y debe pulsar «Compartir»; la ayuda advierte de que esa persona tendrá acceso completo a aplicaciones, archivos, correos, documentos e historial, y pide confirmar **cada 30 minutos** que se sigue compartiendo. Para el acceso a tus propios equipos se usa un PIN.
- **Remote Help de Microsoft**: es una función de Intune. Quien ayuda y quien recibe ayuda deben iniciar sesión con cuentas de Entra ID **de la misma organización** (no hay ayuda entre organizaciones distintas), la función debe activarse en el tenant (viene desactivada) y requiere licencia para ambos lados.

## Asistido frente a desatendido

Es la distinción que más condiciona el riesgo.

- **Asistido**: hay una persona delante del equipo, que inicia la sesión y puede cortarla. El acceso dura lo que dura la ayuda.
- **Desatendido**: el equipo está instalado como servicio, con una contraseña fija o vinculado a una cuenta, y se puede entrar **sin nadie delante**. Cómodo, pero convierte el equipo en un objetivo permanente.

| Situación | Modo | Por qué |
|---|---|---|
| Un familiar o un usuario te llama con un problema | Asistido (código/ID de un solo uso) | Hay alguien que ve lo que haces y puede cortar. |
| Entrar al PC de la oficina desde casa | Desatendido, con 2FA en la cuenta y lista de IDs permitidos | No hay nadie delante; la protección ha de venir de la autenticación. Si hay VPN disponible, mejor [VPN + RDP](Escritorio-Remoto.md). |
| Mantener equipos de la flota por sedes | Desatendido gestionado (cuenta de empresa, directivas, registro de conexiones) | Requiere control central y auditoría. |
| Cliente desconocido pide «que entres a mirar» | Asistido, solo si has sido tú quien le ha dado el código o el enlace | Evita el patrón de estafa descrito abajo. |
| Servidor en producción (el VPS `203.0.113.10`) | **Ninguno de estos** | SSH con clave y, si procede, VPN; ver «Cuándo no usarlas». |

## Seguridad

### Cifrado y lo que ve el intermediario

El servidor intermedio es un tercero que ve que «el ID A conectó con el ID B», cuándo y desde qué IP. Lo que importa es si además puede ver el contenido de la sesión. Cada fabricante lo cuenta de forma distinta y la ficha solo afirma lo que ha leído en su documentación (2026-11-10):

| Herramienta | Qué afirma la documentación consultada |
|---|---|
| TeamViewer | Su Trust Center describe cifrado de extremo a extremo con RSA y AES 256, conexiones intermediadas por servidores, doble factor y lista de permitidos. |
| AnyDesk | Su página de seguridad describe TLS 1.2 con intercambio de claves RSA 2048 y cifrado de transporte AES-256, según resúmenes de buscador (la página respondió 403 a la lectura automática; verificar en `anydesk.com/en/security`). |
| Chrome Remote Desktop | La ayuda de Google afirma que «todas las sesiones de escritorio remoto están totalmente cifradas». No detalla si es de extremo a extremo. |
| Quick Assist | La página de soporte de Microsoft consultada no menciona el cifrado. |
| RustDesk | La documentación de autoalojamiento consultada no describe el cifrado del protocolo (solo WSS para el cliente web). Fuentes secundarias hablan de cifrado de extremo a extremo con NaCl; **no verificado** en documentación oficial. |

«Cifrado de transporte» (TLS entre cada cliente y el servidor) y «cifrado de extremo a extremo» (el servidor no puede descifrar) son cosas distintas. Si la política de la empresa exige lo segundo, pídelo por escrito al fabricante o autoaloja la infraestructura (sección siguiente).

### Incidentes públicos

El 2 de febrero de 2024 AnyDesk comunicó que una auditoría había encontrado indicios de **sistemas de producción comprometidos**. Según su comunicado, contrató a CrowdStrike, revocó todos los certificados relacionados con seguridad, invalidó las contraseñas del portal web de clientes y afirmó no tener pruebas de que se hubieran visto afectados sistemas de usuarios finales. La prensa especializada informó además del robo de código fuente y de claves privadas de firma de código (dato de prensa, no del comunicado). Fuente: [TechCrunch](https://techcrunch.com/2024/02/05/remote-access-giant-anydesk-resets-passwords-and-revokes-certificates-after-hack).

La lección es de diseño, no de marca: todas estas herramientas concentran en el proveedor la confianza sobre el intermediario y sobre los binarios que se instalan.

### Fraude de «soporte técnico»

Las herramientas de control remoto son el instrumento favorito de las estafas de soporte falso: alguien llama o muestra una ventana emergente («su equipo está infectado», «hemos detectado un cargo en su cuenta»), pide instalar la herramienta y leer el ID y el código. Con eso el estafador tiene el mismo acceso que si estuviera sentado delante: archivos, correo, banca online.

Reglas sin excepciones:

- **No des nunca el ID, el código ni la contraseña a quien te ha llamado o escrito primero.** Ni el soporte de Microsoft ni el de un banco te llaman para pedir acceso remoto. La propia ayuda de Quick Assist indica que solo se permita conectar a quien se ha contactado por iniciativa propia.
- Un código de un solo uso protege solo si lo generas **tú, para alguien que tú has buscado**.
- Si ya diste acceso: corta la sesión, desconecta el equipo de la red, cambia contraseñas desde otro dispositivo y avisa al banco si hubo datos financieros.

## Licencias y uso comercial

| Herramienta | Licencia / condiciones |
|---|---|
| TeamViewer | Gratuito solo para **uso personal**. Su base de conocimiento define como comercial cualquier uso pagado directa o indirectamente: soporte a clientes, **teletrabajo** (aunque sea para mirar el correo del trabajo), conexiones entrantes en entorno comercial, monitorización de servidores. Cuando sospecha uso comercial, bloquea el ID o la cuenta; el desbloqueo exige solicitar un reinicio, que revisan en 72 horas. |
| AnyDesk | No verificado: las condiciones de uso gratuito y las de empresa deben consultarse en su página de precios y en su EULA antes de usarlo en una empresa. |
| RustDesk | Cliente y servidor OSS con licencia **AGPL-3.0** (el fichero `LICENCE` del repositorio es el texto de la GNU Affero GPL v3). Hay una edición Server Pro de pago con consola web, usuarios y auditoría. |
| Chrome Remote Desktop | Gratuito con cuenta de Google; las organizaciones pueden administrarlo desde su cuenta gestionada. |
| Quick Assist | Incluido en Windows 10/11 (se instala desde Microsoft Store). |
| Remote Help | Requiere Intune y licencias para quien ayuda y quien recibe ayuda. |

La AGPL permite el uso comercial, pero si modificas RustDesk y lo ofreces como servicio en red, debes publicar tus cambios. Usarlo sin modificar no lo activa.

## Autoalojamiento con RustDesk

RustDesk permite montar **tu propio** servidor de intermediación, de modo que ni el registro de IDs ni el relay pasan por terceros. Son dos procesos:

- **`hbbs`**: servidor de IDs (rendezvous). Registra equipos y organiza el *hole punching*.
- **`hbbr`**: servidor de relay. Retransmite el tráfico cuando la conexión directa falla.

Puertos según la documentación de autoalojamiento (leída el 2026-11-10; **no ejecutado**):

| Puerto | Protocolo | Proceso | Para qué |
|---|---|---|---|
| 21115 | TCP | hbbs | Prueba de tipo de NAT |
| 21116 | TCP y UDP | hbbs | Registro de equipos y *hole punching* |
| 21117 | TCP | hbbr | Relay |
| 21118 | TCP | hbbs | WebSocket (cliente web) |
| 21119 | TCP | hbbr | WebSocket (cliente web) |
| 21114 | TCP | hbbs | API HTTP (solo Server Pro) |

La documentación indica que **21115-21117 son el mínimo imprescindible**, y que 21118 y 21119 solo hacen falta para el cliente web (con un reverse proxy como nginx delante, normalmente no se exponen).

Despliegue conceptual sobre el VPS del ejemplo (no ejecutado):

1. Se arranca `hbbs` y `hbbr` con Docker; la documentación propone descargar un `compose.yml` oficial y lanzar `docker compose up -d` (ver [Docker en un VPS](../../devops/despliegue-en-vps/Docker-en-un-VPS.md)).
2. Se abren en [UFW](../../devops/despliegue-en-vps/UFW.md) solo los puertos necesarios (21115-21117, y 21116/udp), no los demás.
3. En cada cliente, `Ajustes > Red > Servidor ID/Relay`: se introduce la dirección del servidor (`tienda.ejemplo.com`) y la **clave pública** que muestra la instalación. El resto de campos se deja vacío.

Esto no elimina el trabajo: el VPS pasa a tener puertos abiertos a internet que hay que mantener actualizados, y se hereda la responsabilidad de seguridad que antes llevaba el proveedor. Compensa cuando la política de privacidad prohíbe intermediarios ajenos o cuando hay muchos equipos y la licencia comercial resulta cara.

## Cuándo NO usarlas

- **Servidores en producción.** El VPS `203.0.113.10` se administra con [SSH](SSH.md) con clave y, si hace falta alcanzar servicios internos, con [WireGuard](../../devops/despliegue-en-vps/WireGuard.md). Instalar en un servidor una herramienta de escritorio remoto añade un agente de terceros con control total, que casi nunca está justificado: un servidor Linux no tiene escritorio y uno Windows se administra con RDP tras VPN.
- **Equipos con datos sensibles o regulados** (datos de clientes, sanitarios, financieros) cuando la política de la empresa exige que el tráfico no salga a terceros. Aquí encaja el autoalojamiento o VPN + RDP.
- **Cuando la empresa tiene una herramienta aprobada.** Instalar una por libre abre una vía de acceso que el área de seguridad no conoce. En entornos gestionados con Microsoft, Remote Help y Quick Assist suelen ser las permitidas.
- **Acceso desatendido sin segundo factor.** Si la única barrera es una contraseña, el equipo es tan seguro como esa contraseña.

## Errores frecuentes

**Pantalla negra o sin control al aparecer un aviso de administrador (UAC).** Síntoma: la sesión funciona, pero al saltar una petición de elevación de privilegios (UAC) el controlador ve la pantalla negra o no puede pulsar «Sí». Causa: el aviso UAC se muestra en un escritorio protegido (*secure desktop*) al que solo accede un proceso con privilegios de sistema. Una herramienta ejecutada solo con el usuario no lo ve. Solución: instalar la herramienta como **servicio** (modo instalado, no «ejecutar sin instalar») o, en Quick Assist, que quien recibe la ayuda pulse el aviso. Comportamiento descrito de forma general; **no reproducido** aquí.

**«Conexión fallida» o «sin conexión al servicio» en una red de empresa.** Síntoma: la aplicación se queda en «conectando». Causa habitual: un proxy corporativo o un firewall de salida bloquea los servidores del fabricante o los puertos que usa. Solución: pedir a IT que permita los dominios y puertos que el fabricante publica, o usar la edición con relay autoalojado. No uses una herramienta distinta para saltarte el bloqueo: es justo lo que la política quiere evitar.

**Comprobar que Quick Assist está instalado.** Quick Assist ya no viene como ejecutable de sistema: es una app de Microsoft Store. En la máquina de pruebas (2026-11-10):

```powershell
where quickassist
```

```text
INFORMACIÓN: no se pudo encontrar ningún archivo para los patrones dados.
```

`where` no lo encuentra porque la app no está en el `PATH`, aunque sí instalada (`Get-AppxPackage -Name *QuickAssist*` devolvió el paquete `MicrosoftCorporationII.QuickAssist`, versión 2.0.35.0). Se abre desde el menú Inicio; el lanzamiento desde terminal no se ha probado.

**TeamViewer dice «uso comercial detectado» o limita las sesiones.** Causa: el uso se ha clasificado como comercial (ver «Licencias»). Solución: licencia de empresa, o solicitar el reinicio del ID si es un uso personal real; no se debe cambiar de ID para esquivar la restricción.

**Sesión que no se corta al acabar.** El acceso desatendido sigue activo tras una ayuda puntual. Revisa la lista de equipos autorizados y las sesiones abiertas de la cuenta tras cada soporte, y desinstala la herramienta si no se va a volver a usar.

## Buenas prácticas avanzadas

- **La cuenta del servicio es la llave maestra: protégela con doble factor.** Si tienes acceso desatendido a varios equipos asociados a la cuenta, quien entre en la cuenta entra en todos. Activa 2FA, usa una contraseña de acceso distinta por equipo y revoca los equipos que ya no uses.
- **Restringe con lista de permitidos.** TeamViewer documenta lista de permitidos y doble factor; AnyDesk ofrece lista blanca de ID. Con ella, aunque alguien consiga la contraseña, su ID no está autorizado. Revisa de vez en cuando el registro de conexiones entrantes.
- **Pon el equipo desatendido detrás de otra barrera.** Para un equipo que debe ser accesible siempre, es preferible dejarlo accesible por [VPN](VPN.md) y usar RDP dentro, y reservar la herramienta de intermediario para soporte asistido. Así no hay un servicio de terceros con acceso permanente.
- **Descarga solo desde el sitio oficial y verifica la firma.** Un instalador «portable» enviado por correo o por un anuncio es el vector más habitual de troyanos disfrazados de herramienta de soporte. Tras el incidente de 2024 en el que se robaron claves de firma, comprueba también que se descarga la versión vigente.
- **Define qué se permite y quién.** En una empresa, fija una única herramienta aprobada, bloquea a nivel de red las demás y registra quién tiene acceso desatendido a qué. Una herramienta «no oficial» instalada por un empleado es acceso remoto no auditado.
- **Cierra las sesiones y revoca el acceso al terminar el soporte.** En un código de un solo uso se cierra solo; en el acceso desatendido, no.

## Documentación oficial

- [Quick Assist (Microsoft Support)](https://support.microsoft.com/en-us/windows/solve-pc-problems-over-a-remote-connection-b077e31a-16f4-2529-1a47-21f6a9040bf3) — cómo funciona el código de 6 dígitos, el control solicitado y los requisitos; incluye el aviso contra el fraude de soporte técnico.
- [Remote Help con Intune (Microsoft Learn)](https://learn.microsoft.com/en-us/intune/remote-help/) — requisitos de cuenta, licencia y *Conditional Access*; para entornos de empresa.
- [Autoalojamiento de RustDesk](https://rustdesk.com/docs/en/self-host/) — puertos de `hbbs` y `hbbr` y esquema de conexión; el primer sitio al montar tu propio servidor.
- [Trust Center de TeamViewer](https://www.teamviewer.com/en/trust-center/security/) — modelo de seguridad y certificaciones declarados por el fabricante.

---

*En resumen: las herramientas de control remoto funcionan sin abrir puertos porque ambos equipos llaman hacia un servidor intermedio, a cambio de depender de un tercero y de exponer un acceso que solo es tan seguro como su segundo factor; sirven para soporte asistido, no para administrar servidores, y nunca se da el ID a quien te ha llamado primero.*
