# Escritorio Remoto (RDP)

## ¿Qué es?

El **Escritorio Remoto** permite ver y controlar la pantalla de otro ordenador desde el propio, con su mismo escritorio, programas, ratón y teclado. En Windows lo hace posible **RDP** (*Remote Desktop Protocol*), un protocolo que escucha por el puerto **3389** (TCP y también UDP) y que no envía una captura de pantalla, sino instrucciones de dibujo y los eventos de teclado y ratón.

## ¿Por qué existe?

A menudo hace falta usar una máquina que no está delante: el equipo de oficina desde casa, un servidor Windows sin monitor, o el portátil de una persona a la que se ayuda. RDP resuelve eso a través de la red y, como transmite instrucciones de dibujo en lugar de imágenes completas, aguanta conexiones lentas mejor que otras soluciones de pantalla compartida.

> Si ya has usado SSH para trabajar en un servidor Linux, RDP es el equivalente con interfaz gráfica para Windows: te autenticas con una cuenta del equipo remoto y obtienes **tu propia sesión** de usuario, no un espejo de lo que ve otra persona.

Ejemplo conductor: la tienda online tiene un equipo de oficina en `192.168.1.20` (Windows 11 Pro, red local `192.168.1.0/24`) y la persona que lo usa, `ana`, quiere trabajar con él desde casa.

## ¿Cuándo y para qué se usa?

- **Teletrabajo**: usar el equipo de la oficina con sus programas y archivos.
- **Administrar servidores Windows**: la gestión diaria de un Windows Server sin pantalla.
- **Software pesado o con licencia ligada a una máquina**: ejecutarlo en el equipo potente y verlo desde un portátil modesto.
- **Soporte técnico**: entrar en un equipo con las credenciales de quien lo administra.

**Cuándo no**: para controlar un Linux o un macOS, [VNC](VNC.md) o [SSH](SSH.md) encajan mejor; para ayudar a alguien que no puede configurar nada en su red, las [herramientas de control remoto](Herramientas-de-Control-Remoto.md) atraviesan routers sin abrir puertos.

## Qué equipos pueden recibir conexiones

Un equipo que **recibe** conexiones se llama anfitrión (*host*); el que se conecta es el cliente. La documentación vigente de Microsoft (*Enable Remote Desktop on your PC*, consultada el 2026-11-10) dice que las ediciones **Professional, Enterprise y Education**, y las ediciones de **Windows Server**, pueden ser anfitrión. Las ediciones **Home no pueden**, aunque sí actuar como cliente.

| Edición | ¿Anfitrión? | ¿Cliente (`mstsc`)? |
|---|---|---|
| Windows 10/11 Pro, Enterprise, Education | Sí | Sí |
| Windows 10/11 Home | **No** | Sí |
| Windows Server | Sí | Sí |

Comprobado el 2026-11-10 en un equipo con Windows 11 Home: el cliente existe (`where mstsc` encuentra `mstsc.exe` en `System32`), pero el servicio de anfitrión está parado y sin nada escuchando en el 3389:

```text
> sc query TermService
NOMBRE_DE_SERVICIO: TermService
        TIPO                         : 20  WIN32_SHARE_PROCESS
        ESTADO                       : 1  STOPPED

> netstat -ano | findstr ":3389 "
(sin resultados)
```

`sc query` y `netstat` solo consultan. `TermService` es el servicio *Servicios de Escritorio remoto*, el que atiende las conexiones entrantes; que esté en `STOPPED` es lo esperable en una edición Home.

Además del tipo de edición, la documentación lista los requisitos para conectarse: el equipo anfitrión encendido y en red, Escritorio remoto activado en él, acceso de red hasta él, una cuenta con permiso y el firewall del anfitrión dejando pasar el tráfico.

## Habilitar el anfitrión

*No ejecutado: el equipo es Home y no se modificó su configuración. Pasos tomados de la documentación de Microsoft citada arriba.*

Se necesita una cuenta de administrador en el equipo anfitrión. En la interfaz:

1. *Inicio → Configuración → Sistema → Escritorio remoto*.
2. Activar **Habilitar Escritorio remoto** y confirmar el cuadro.
3. Para añadir cuentas, abrir **Usuarios de Escritorio remoto** (en versiones anteriores: *Seleccionar los usuarios que pueden acceder de forma remota a este equipo*), pulsar *Agregar* y escribir el nombre.

Al activarlo, Windows abre el puerto del equipo a la red y, por defecto, queda marcada la casilla de hacerlo detectable en redes privadas. La propia documentación recomienda activarlo solo en redes de confianza, como la doméstica o la de la oficina.

En un conjunto de equipos gestionados, la misma opción se fija con una directiva de grupo (*Configuración del equipo → Plantillas administrativas → Componentes de Windows → Servicios de Escritorio remoto → Host de sesión de Escritorio remoto → Conexiones*, directiva *Permitir que los usuarios se conecten de forma remota mediante Servicios de Escritorio remoto*). No ejecutado; nombre de la directiva no contrastado con la documentación en esta lectura.

### Quién puede entrar

Con Escritorio remoto activado pueden conectarse los miembros del grupo **Administradores** y los del grupo local **Usuarios de Escritorio remoto** (*Remote Desktop Users*). Dar acceso a `ana` sin hacerla administradora consiste en añadirla a ese grupo, ya sea desde el cuadro anterior o con:

```powershell
# No ejecutado
net localgroup "Remote Desktop Users" ana /add
```

Los grupos locales en un equipo en español pueden mostrarse traducidos (*Usuarios de escritorio remoto*); el comando usa el nombre en el idioma del sistema.

Toda cuenta con acceso remoto debe tener contraseña fuerte y única: la documentación de Microsoft lo exige expresamente, y una débil es lo primero que prueban los ataques automáticos.

## NLA: autenticarse antes de crear la sesión

**NLA** (*Network Level Authentication*) obliga a que quien se conecta demuestre quién es **antes** de que el servidor construya la sesión gráfica. Sin NLA, cualquier cliente que llegue al puerto recibe una pantalla de inicio de sesión remota: el anfitrión gasta memoria y CPU por cada intento y expone más código sin autenticar. Con NLA, un intento sin credenciales válidas se corta en el primer paso.

La documentación de Microsoft lo recomienda para la mayoría de entornos y solo admite desactivarlo, y de forma temporal, para clientes antiguos que no lo soportan. En la interfaz está en *Configuración → Sistema → Escritorio remoto → Configuración avanzada → Requerir que los dispositivos usen autenticación a nivel de red*. En un `.rdp` lo gobierna `enablecredsspsupport` (CredSSP es el proveedor de seguridad que implementa NLA).

Efecto práctico: como las credenciales se validan antes de abrir la sesión, el cliente necesita poder verificarlas contra el equipo. Eso explica varios errores de la sección final cuando el equipo remoto es de dominio y el cliente no.

## Conectar con `mstsc`

`mstsc.exe` es el cliente integrado de Windows (*Conexión a Escritorio remoto*). Sin argumentos abre el cuadro de conexión; con argumentos conecta directamente.

```text
mstsc /v:192.168.1.20 /f
```

`/v` indica el equipo (admite `host:puerto` si el puerto no es el 3389) y `/f` abre en pantalla completa. Pide usuario y contraseña si no hay credenciales guardadas, y devuelve la sesión del equipo remoto en una ventana o a pantalla completa. No ejecutado: no había ningún anfitrión al que conectarse.

Las opciones útiles según la documentación de `mstsc` (*mstsc*, Microsoft Learn, consultada el 2026-11-10):

| Opción | Qué hace |
|---|---|
| `/v:<equipo>[:<puerto>]` | Equipo y, opcionalmente, puerto de destino. |
| `/f` o `/fullscreen` | Pantalla completa. |
| `/w:<ancho> /h:<alto>` | Tamaño de la ventana, p. ej. `/w:1920 /h:1080`. |
| `/multimon` | La sesión replica la disposición de monitores del cliente. |
| `/span` | Extiende un único escritorio por varios monitores iguales y alineados en horizontal. |
| `/l` | Lista los monitores locales y sus identificadores (sirven para `selectedmonitors`). |
| `/g:<pasarela>` | Servidor de Puerta de enlace de Escritorio remoto (RD Gateway); solo se lee junto a `/v`. |
| `/admin` | Sesión de administración del servidor. |
| `/prompt` | Pide las credenciales al conectar en lugar de usar las guardadas. |
| `/public` | Modo público: no guarda contraseñas ni mapas de bits en caché. |
| `/restrictedAdmin` | No envía las credenciales al equipo remoto; implica `/admin`. |
| `/remoteGuard` | Tampoco las envía y además redirige al cliente las peticiones de autenticación salientes. |
| `/edit <fichero.rdp>` | Abre un `.rdp` para editarlo en el cuadro gráfico. |
| `<fichero.rdp>` | Conecta usando un fichero guardado. |

`mstsc /?` no imprime texto por consola: abre un cuadro gráfico con el uso, así que no se capturó su salida y la tabla sale de la documentación, no de ese cuadro.

## Ficheros `.rdp`

Un `.rdp` es un fichero de texto con una línea por ajuste, en el formato `clave:tipo:valor`, donde el tipo es `s` (texto) o `i` (entero). Guarda una conexión para repetirla sin escribir nada. Windows guarda por defecto los de usuario en *Documentos* y mantiene un `Default.rdp` oculto con los últimos ajustes.

Ejemplo del equipo de oficina:

```text
full address:s:192.168.1.20
username:s:ana
screen mode id:i:2
session bpp:i:32
redirectclipboard:i:1
drivestoredirect:s:
authentication level:i:2
enablecredsspsupport:i:1
```

Se usa con `mstsc oficina.rdp`. Claves, según la referencia de propiedades RDP de Microsoft (*Supported RDP properties*, consultada el 2026-11-10):

| Clave | Valores | Efecto |
|---|---|---|
| `full address` | `s:<host>[:<puerto>]` | Equipo de destino (propiedad básica del cliente; la referencia consultada no la desarrolla aparte). |
| `username` | `s:<usuario>` | Cuenta con la que iniciar sesión. Para dominio, `DOMINIO\usuario`. |
| `screen mode id` | `1` ventana, `2` pantalla completa | Cómo se abre la sesión. Valor por defecto: `2`. |
| `session bpp` | `i:<bits de color>` | Profundidad de color (p. ej. 16 o 32). Propiedad básica; no aparece en la referencia consultada. |
| `redirectclipboard` | `0` no, `1` sí | Comparte el portapapeles con el equipo remoto. Por defecto: `0`. |
| `drivestoredirect` | vacío = ninguna; `*` = todas; `C:\;E:\;` = las indicadas | Unidades locales que aparecen en la sesión remota. Por defecto: vacío. |
| `authentication level` | `0` conecta sin avisar si falla la autenticación del servidor; `1` no conecta; `2` avisa y deja elegir; `3` sin requisito | Qué hacer si no se puede verificar la identidad del equipo. Por defecto: `3`. |
| `enablecredsspsupport` | `0` / `1` | Usa CredSSP (la base de NLA) si el sistema lo soporta. Por defecto: `1`. |
| `desktopwidth`, `desktopheight` | 200 a 8192 | Resolución en píxeles; por defecto, la del dispositivo local. |
| `dynamic resolution` | `0` / `1` | La resolución sigue al redimensionar la ventana. Por defecto: `1`. |
| `use multimon` | `0` / `1` | Una o varias pantallas. |
| `audiomode` | `0` local, `1` remoto, `2` sin sonido | Dónde suena el audio. |
| `redirectprinters` | `0` / `1` | Impresoras locales en la sesión remota. Por defecto: `0`. |
| `networkautodetect`, `bandwidthautodetect` | `0` / `1` | Detección automática del tipo de red y del ancho de banda. Por defecto: `1`. |

Un `.rdp` con `username` guardado y sin contraseña es inocuo; uno que lleve credenciales guardadas debe tratarse como un secreto.

## Redirecciones: portapapeles y unidades

Las **redirecciones** son canales extra dentro de la sesión que conectan el equipo local con el remoto: portapapeles, unidades de disco, impresoras, tarjetas inteligentes. Son cómodas (copiar un fichero de un equipo a otro con copiar y pegar) y dobles filos: un canal que sirve para llevar un fichero a la oficina sirve también para traerse algo desde un equipo comprometido.

```text
❌  drivestoredirect:s:*        (todas las unidades, incluso las que se conecten después, hacia un equipo ajeno)
✅  drivestoredirect:s:         (ninguna)
✅  drivestoredirect:s:E:\;     (solo la unidad de intercambio que haga falta)
```

En el cuadro gráfico están en *Mostrar opciones → Recursos locales*. Regla práctica: activar lo mínimo, y nada con equipos que no se controlan.

## Sesiones: una por usuario y qué pasa al desconectar

Una **sesión** es el entorno de un usuario en el equipo: escritorio, programas abiertos y procesos. En una edición de cliente (Windows 10/11 Pro) solo puede haber **una sesión interactiva a la vez**: al conectar por RDP, la sesión de quien estuviera delante pasa a la pantalla remota y la pantalla física queda bloqueada, y si otra persona entra con otra cuenta, se le pide desconectar a la actual. Es un relevo, no una pantalla compartida. En **Windows Server** pueden coexistir varias sesiones de distintos usuarios; la documentación de Microsoft trata este punto en la parte de licencias de Servicios de Escritorio remoto (CAL), no verificado con documentación de Microsoft.

Cerrar la ventana de `mstsc` **desconecta**, pero no cierra la sesión: los programas siguen ejecutándose y se recupera todo al volver a conectar. Es útil para tareas largas y un riesgo si es una sesión de administrador olvidada. Para ver y cerrar sesiones:

```text
query user
logoff <id>
```

No ejecutado: `query user` consulta el servicio de sesiones, y sobre una edición Home sin anfitrión no aporta datos de interés.

## Rendimiento

Con una conexión lenta, el cuello de botella es el volumen de píxeles que cambian. Los ajustes que más pesan, desde el cuadro *Experiencia* de `mstsc` o desde el `.rdp`:

- **Menos colores**: `session bpp:i:16` en vez de 32 reduce el tráfico de forma notable, a costa de degradados menos suaves.
- **Resolución menor**: `desktopwidth` y `desktopheight` pequeños, o `desktop size id`.
- **Quitar adornos** (fondo, animaciones, temas) en la pestaña *Experiencia*.
- Dejar en `1` `networkautodetect` y `bandwidthautodetect` (valor por defecto) para que el cliente adapte la calidad al ancho de banda disponible.
- Desactivar `audiomode` (`2`) y las redirecciones que no se usen.

La parte de **UDP** del puerto 3389 sirve para el transporte más fluido en redes con pérdidas; si el firewall solo permite TCP, la sesión funciona igual, algo más lenta. No ejecutado: sin un anfitrión, no se midió el efecto de cada ajuste.

## No abrir el 3389 a internet

La forma tentadora de usar el equipo de la oficina desde casa es [redirigir el puerto](Redireccion-de-Puertos.md) `TCP 3389` del router hacia `192.168.1.20`. La documentación de Microsoft sobre acceso desde fuera de la red ofrece exactamente dos vías, la redirección y la VPN, y avisa de la primera: *abre el PC a internet, lo cual no se recomienda; si no hay otro remedio, usar una contraseña fuerte, y es preferible una VPN*.

```text
❌  Internet → router (3389 abierto) → 192.168.1.20
✅  Internet → VPN (un solo puerto UDP) → red local → 192.168.1.20:3389
✅  Internet → RD Gateway (HTTPS, 443) → 192.168.1.20:3389
```

Por qué es un riesgo, a nivel documental:

- **Fuerza bruta**: un puerto 3389 abierto se descubre en horas con escaneos masivos y recibe un goteo constante de intentos de usuario y contraseña. Una contraseña débil acaba cayendo; una buena reduce el riesgo pero no el ruido.
- **Vulnerabilidades en el propio servicio**: **BlueKeep** (CVE-2019-0708) permitía ejecutar código en el anfitrión **sin autenticación**, y tuvo carácter de gusano. Se corrigió en 2019 y afectaba a versiones antiguas de Windows (no verificado en esta lectura el listado exacto; el catálogo de Microsoft lo detalla). NLA fue una mitigación porque obliga a autenticar antes de llegar al código vulnerable.
- **Cambiar de puerto** reduce los intentos automáticos de los bots menos sofisticados, pero no protege: los escáneres detectan RDP en cualquier puerto.

Las dos alternativas:

- **VPN**: se abre un solo puerto, el del servicio de VPN, que ignora todo lo que no venga con una clave válida; después el 3389 se alcanza por la red interna. [VPN](VPN.md) lo explica y [WireGuard](../../devops/despliegue-en-vps/WireGuard.md) es la implementación del ejemplo.
- **Puerta de enlace de Escritorio remoto (RD Gateway)**: un rol de Windows Server que acepta RDP encapsulado en HTTPS y lo reenvía a los equipos internos, con su propia directiva de quién puede llegar a qué equipo. Se usa con `mstsc /g:<pasarela> /v:<equipo>`. No ejecutado; su despliegue no se cubre aquí.

Si el 3389 tiene que seguir en el firewall del propio equipo, limítalo por origen a la red local. En Windows, eso equivale a acotar el ámbito de la regla de entrada *Escritorio remoto* a `192.168.1.0/24` (no ejecutado).

## Errores frecuentes

Los mensajes son los habituales del cliente; ninguno se reprodujo (el equipo de prueba no es anfitrión), y el texto exacto depende del idioma y de la versión.

| Síntoma | Causa probable |
|---|---|
| «Su credencial no funcionó» / «Your credentials did not work» | Usuario o contraseña incorrectos, o formato equivocado: para cuenta local se usa `EQUIPO\usuario`, para dominio `DOMINIO\usuario`.  |
| «El usuario no tiene permiso para conectarse» / «The connection was denied because the user account is not authorized for remote login» | La cuenta no es administradora ni pertenece al grupo *Usuarios de Escritorio remoto* del anfitrión. |
| «Se ha producido un error interno» / «An internal error has occurred» | Mensaje genérico que cubre varias causas: servicio de Escritorio remoto parado en el anfitrión, certificado del equipo inválido, o cliente y servidor sin parámetros de seguridad compatibles. Primera comprobación: que el servicio `TermService` esté en marcha en el anfitrión. |
| «Para conectarse a este equipo se requiere autenticación a nivel de red» / «The function requested is not supported» | El anfitrión exige NLA y el cliente no puede cumplirla (cliente antiguo, equipo sin acceso al dominio). Actualiza el cliente; desactivar NLA es un último recurso y temporal. |
| La autenticación falla solo con equipos de dominio, o «No se puede contactar con la autoridad de seguridad» | El cliente no alcanza el controlador de dominio (fuera de la red corporativa sin VPN) o la hora de ambos equipos difiere demasiado. Se resuelve conectando primero por VPN. |
| «No se puede conectar con el equipo remoto» / «Remote Desktop can't connect to the remote computer» | Equipo apagado, suspendido o inalcanzable; Escritorio remoto desactivado; firewall del anfitrión o de la ruta bloqueando el 3389; IP o nombre erróneos. Se comprueba el acceso a la red antes que las credenciales. |
| Advertencia de certificado («No se puede comprobar la identidad del equipo remoto») | El anfitrión usa un certificado autofirmado, normal en equipos sueltos. En redes corporativas se evita con certificados de una autoridad interna. |
| «Otro usuario está conectado: ¿desconectarlo?» | En clientes de Windows solo cabe una sesión interactiva; entrar con otra cuenta cierra la de la persona que esté usando el equipo. |

## Buenas prácticas avanzadas

- **Deja NLA activo y trata como señal de alarma cualquier consejo de quitarlo.** Quien lo desactiva para «arreglar» una conexión suele estar tapando un problema de dominio, de hora o de cliente antiguo; el arreglo real es otro, y desactivarlo vuelve a exponer la pantalla de inicio de sesión a cualquier cliente que llegue al puerto.
- **Mantén `authentication level` en `2` o `1` y no ignores la advertencia del certificado.** Con `0` el cliente conecta sin avisar aunque no pueda verificar el equipo, lo que permite que un intermediario se haga pasar por él y capture las credenciales. Si el aviso salta con un equipo que siempre funcionó, es una señal, no una molestia.
- **Protege las credenciales cuando el destino no es de confianza.** Con `/restrictedAdmin` o `/remoteGuard`, el equipo remoto no se queda con credenciales reutilizables del cliente; es la diferencia entre perder una máquina comprometida y perder también la cuenta con la que se entró en ella. Con restricted admin algunas operaciones de red desde la sesión pueden no autenticarse.
- **Aplica el principio del mínimo: un grupo, no administradores.** Quien solo necesita conectarse pertenece a *Usuarios de Escritorio remoto*; hacerlo administrador amplía lo que puede hacer en el equipo y lo que pierde la organización si su contraseña cae.
- **Cierra la sesión (`logoff`) cuando termines, no solo la ventana.** Una sesión desconectada de un administrador sigue viva con sus programas, y se revisa con `query user`. Limitar el tiempo máximo de sesiones desconectadas con la directiva de grupo correspondiente evita el olvido.
- **Mantén el anfitrión al día y limita el 3389 por origen.** Los fallos graves de RDP se parchean en las actualizaciones de seguridad; un servicio expuesto solo a la red local o al túnel de VPN reduce a casi nada la superficie sobre la que puede actuar un fallo nuevo.

## Documentación oficial

- [Habilitar Escritorio remoto en el equipo](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remotepc/remote-desktop-allow-access) — qué ediciones pueden ser anfitrión, pasos para activarlo, usuarios permitidos y por qué NLA.
- [Acceso desde fuera de la red](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remotepc/remote-desktop-allow-outside-access) — la redirección de puertos frente a la VPN y el aviso de Microsoft sobre abrir el equipo a internet.
- [Referencia de `mstsc`](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/mstsc) — todas las opciones de línea de comandos del cliente.
- [Propiedades RDP admitidas](https://learn.microsoft.com/en-us/azure/virtual-desktop/rdp-properties) — cada clave posible de un fichero `.rdp`, con valores y por defecto.

## Recursos didácticos

- [Entrada de BlueKeep (CVE-2019-0708) en el catálogo de Microsoft](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2019-0708) — qué sistemas afectó y qué parche lo corrige; buen ejemplo de por qué un servicio de acceso remoto no se expone sin necesidad.

---

*En resumen: RDP te da tu propia sesión en otro Windows a través del puerto 3389, y es cómodo y seguro mientras se use con NLA, cuentas acotadas y dentro de una VPN, no con el puerto abierto a internet.*
