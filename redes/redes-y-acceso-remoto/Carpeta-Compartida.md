# Carpeta Compartida (SMB)

## ¿Qué es?

Una **carpeta compartida** es una carpeta de un equipo que se ofrece al resto de la red para abrir, leer y guardar archivos en ella como si fuera local. El protocolo que lo hace posible en Windows (y en la mayoría de NAS, impresoras multifunción y servidores Samba) es **SMB** (*Server Message Block*), que escucha en el puerto **445/TCP**.

## ¿Por qué existe?

Mover archivos con pendrives o adjuntos de correo genera copias sueltas: nadie sabe cuál es la versión buena. SMB resuelve esto dejando el archivo en un único sitio y haciendo que cada equipo lo abra por la red, con control de quién puede leer y quién puede escribir.

> Si ya conoces los volúmenes de Docker, piensa en SMB como un volumen compartido a través de la red: el contenido vive en un sitio y varios clientes lo montan. La diferencia es que aquí cada cliente se identifica con un usuario y la autorización se evalúa archivo a archivo.

SMB también se conoce como **CIFS** (*Common Internet File System*), el nombre de una variante antigua del protocolo (SMB 1). Hoy se usa «SMB» para todo, y en Linux la herramienta de montaje sigue llamándose `mount.cifs`.

## ¿Cuándo y para qué se usa?

Ejemplo conductor: una tienda online pequeña tiene una oficina con la red `192.168.1.0/24`, un equipo de trabajo en `192.168.1.20` y un [NAS](NAS.md) en `192.168.1.50`.

- **Documentos comunes** de la oficina: facturas, plantillas, fotos de producto. El NAS expone `\\192.168.1.50\datos` y todos los equipos lo ven como un disco más.
- **Destino de copias de seguridad** de los equipos de la oficina.
- **Intercambio puntual** entre dos equipos Windows sin montar ningún servidor.

Fuera de la red local, SMB no es la herramienta: la tabla de decisión del final indica cuándo usar [SFTP](FTP-y-SFTP.md), [WebDAV](WebDAV.md) o una [VPN](VPN.md) por delante.

## Cómo se direcciona: la ruta UNC

Un recurso compartido se nombra con una ruta **UNC** (*Universal Naming Convention*): dos barras invertidas, el servidor y el nombre del recurso.

```text
\\192.168.1.50\datos
\\192.168.1.50\datos\facturas\2026
```

| Parte | Significado |
|---|---|
| `\\` | Prefijo que indica «recurso de red», no una ruta local |
| `192.168.1.50` | Servidor: IP o nombre de equipo (`\\nas-oficina\datos`) |
| `datos` | **Nombre del recurso compartido**, no la carpeta del disco: puede llamarse distinto de la carpeta real (`D:\Empresa\Docs`) |
| `\facturas\2026` | Ruta normal dentro del recurso |

Se escribe en la barra de direcciones del Explorador, en *Ejecutar* (`Win + R`) o en cualquier programa que abra archivos. En macOS y Linux se usa el esquema `smb://192.168.1.50/datos`.

Un nombre que termina en `$` (`\\servidor\backups$`) es un recurso **oculto**: no aparece al explorar el servidor, pero entra quien conozca la ruta. Windows crea además recursos administrativos ocultos (`C$`, `ADMIN$`) para cada disco; solo son accesibles para administradores.

## Compartir una carpeta en Windows

> No ejecutado: compartir una carpeta modifica la configuración del equipo. Lo que sigue procede de la documentación de Microsoft (enlazada al final).

Dos vías equivalentes:

- **Gráfica**: clic derecho sobre la carpeta → *Propiedades* → pestaña *Compartir* → *Uso compartido avanzado* → marcar *Compartir esta carpeta*, dar nombre al recurso y pulsar *Permisos*.
- **PowerShell** (consola elevada):

```powershell
New-SmbShare -Name datos -Path D:\Empresa\Docs -FullAccess "Usuarios autenticados"
```

Crea el recurso `datos` apuntando a `D:\Empresa\Docs` y da control total de **recurso compartido** a *Usuarios autenticados*. Lo que cada persona puede hacer de verdad lo decide además el sistema de archivos, como se explica a continuación.

## Dos capas de permisos: gana la más restrictiva

Una carpeta compartida en Windows pasa por **dos** comprobaciones:

1. Los **permisos del recurso compartido** (*share permissions*): solo se aplican a quien entra por la red y tienen tres niveles: Lectura, Cambiar y Control total.
2. Los **permisos NTFS**: son los del sistema de archivos, se aplican a todo el mundo (local o remoto) y son mucho más finos.

Microsoft lo documenta así: los dos conjuntos son independientes y se aplican los permisos más restrictivos (*the more restrictive permissions are then applied*). Es decir, el acceso efectivo de una persona que entra por la red es la **intersección** de ambas capas.

| Permiso del recurso compartido | Permiso NTFS | Acceso efectivo por red |
|---|---|---|
| Control total | Lectura | Lectura |
| Lectura | Modificar | Lectura |
| Cambiar | Modificar | Modificar |
| Cambiar | Sin permiso (no aparece) | Ninguno: acceso denegado |
| Control total | Control total | Control total |

Dos consecuencias prácticas:

- Los permisos del recurso compartido **no protegen** frente a quien se sienta delante del equipo ni frente a una sesión de Escritorio Remoto: solo afectan a la red. NTFS protege en ambos casos.
- Si una persona «llega» a la carpeta pero no puede guardar, la causa casi siempre es una de las dos capas, no la conexión.

Microsoft documenta, como opción que prefieren muchos administradores con experiencia, dar control total a *Todos* en el recurso compartido y gestionar el acceso real solo con NTFS. Así los permisos viven en un único sitio.

```text
❌ Recurso compartido: Lectura para Usuarios  +  NTFS: Modificar para Usuarios
   → quien escribe recibe «Acceso denegado» y nadie sabe en qué capa mirar

✅ Recurso compartido: Control total para Usuarios autenticados
   NTFS: Modificar para el grupo «Facturacion», nada para el resto
   → toda la política está en NTFS
```

## Acceder desde otros sistemas

### Windows

Escribir la ruta UNC en el Explorador, o mapearla como unidad (siguiente sección). La primera vez pide usuario y contraseña de una cuenta que exista **en el servidor**.

### macOS

Finder → *Ir* → *Conectarse al servidor* (`Cmd + K`) y escribir `smb://192.168.1.50/datos`. No ejecutado: procedimiento estándar del sistema.

### Linux

El cliente es `mount.cifs` (paquete `cifs-utils`). Según la documentación del proyecto Samba, la sintaxis básica es `mount -t cifs //<servidor>/<recurso> <punto-de-montaje>` con las opciones tras `-o`:

```bash
sudo mkdir -p /mnt/datos
sudo mount -t cifs //192.168.1.50/datos /mnt/datos -o credentials=/home/deployer/.smbcred,uid=1000
```

Se monta el recurso en `/mnt/datos`. La opción `credentials=` apunta a un fichero con dos líneas, `username=...` y `password=...`; Samba lo prefiere a escribir la contraseña en claro en la línea de comandos o en `/etc/fstab`. El fichero debe ser legible solo por su dueño:

```bash
chmod 600 /home/deployer/.smbcred
```

No ejecutado: requiere root y un servidor real. Para ver los recursos que ofrece un servidor Samba, `smbclient -L //192.168.1.50 -U usuario` los lista.

## Mapear una unidad de red

> No ejecutado: mapear una unidad modifica el estado del equipo. El comando es el de la documentación de Microsoft.

```bash
net use Z: \\192.168.1.50\datos /user:oficina\sara /persistent:yes
```

| Parte | Qué hace |
|---|---|
| `net use` | Gestiona conexiones de red |
| `Z:` | Letra de unidad que se asigna (con `*` Windows elige una libre) |
| `\\192.168.1.50\datos` | Recurso al que se conecta |
| `/user:oficina\sara` | Cuenta con la que se autentica, en formato `dominio-o-equipo\usuario`. Sin esta opción usa la sesión actual |
| `/persistent:yes` | Recuerda la unidad tras reiniciar |

Sin contraseña en la línea de comandos, Windows la pide por consola. Evita escribirla con `/user:... contraseña` porque queda en el historial.

Otras dos formas de ver y quitar:

```bash
net use                 # lista las conexiones abiertas
net use Z: /delete      # desmapea la unidad Z:
```

La salida de `net use` en un equipo sin unidades mapeadas (2026-11-10) se limitó a «Se registrarán las nuevas conexiones» con una tabla vacía: no había ninguna unidad de red mapeada.

Para exigir cifrado al mapear existe `/requireprivacy` (véase más abajo).

## Versiones del protocolo: por qué SMB 1 debe estar apagado

| Versión | Llegó con | Estado |
|---|---|---|
| SMB 1 (CIFS) | Años 90 | Obsoleto y con vulnerabilidades graves; no se instala por defecto |
| SMB 2.x | Windows Vista / Server 2008 | Correcto; reduce mucho las conversaciones del protocolo |
| SMB 3.x | Windows 8 / Server 2012 | La actual: cifrado, multicanal, firma mejorada |

Según la documentación de Microsoft (*Detect, enable, and disable SMBv1, SMBv2, and SMBv3*, actualizada en 2026): SMB 1 «has significant security vulnerabilities» y no está instalado por defecto en ninguna edición de Windows 11 ni en Windows Server 2019 o posterior.

Se comprueba sin privilegios elevados con una consulta de solo lectura. Salida obtenida el 2026-11-10 en un equipo con Windows 11, filtrada a las propiedades relevantes:

```powershell
Get-SmbServerConfiguration | Format-List EnableSMB1Protocol, EnableSMB2Protocol, RequireSecuritySignature, EnableSecuritySignature, EncryptData, RejectUnencryptedAccess
```

```text
EnableSMB1Protocol       : False
EnableSMB2Protocol       : True
RequireSecuritySignature : True
EnableSecuritySignature  : False
EncryptData              : False
RejectUnencryptedAccess  : True
```

- `EnableSMB1Protocol : False` — SMB 1 apagado.
- `EnableSMB2Protocol : True` — habilita SMB 2 **y** SMB 3 (comparten pila).
- `RequireSecuritySignature : True` — la firma es obligatoria.
- `EncryptData : False` — el cifrado no se exige a nivel de servidor (se puede exigir por recurso).

### NetBIOS (137-139): historia

Antes de SMB 2, SMB viajaba sobre **NetBIOS** (puertos 137/UDP, 138/UDP y 139/TCP), que servía además para descubrir equipos por nombre. Desde Windows 2000, SMB puede ir directamente sobre TCP en el **445**, y es lo que se usa hoy. Los puertos 137-139 solo importan en equipos muy antiguos o para bloquearlos en un cortafuegos de frontera.

## Firma y cifrado

Dos mecanismos distintos de SMB 2/3 que a veces se confunden:

- **Firma** (*signing*): cada mensaje lleva una marca criptográfica que demuestra que no lo ha alterado nadie por el camino. Protege la **integridad**, no la confidencialidad: un tercero podría leer el tráfico, pero no modificarlo. Según Microsoft, en Windows 11 24H2 y Windows Server 2025 la firma es **obligatoria por defecto**, lo que puede impedir conectar con equipos de grupo de trabajo, recursos con acceso invitado o servidores de terceros que no la soportan. La solución es activar la firma en el servidor remoto o sustituir el dispositivo, no desactivarla en el cliente.
- **Cifrado** (*SMB Encryption*, solo SMB 3): protege la **confidencialidad** de extremo a extremo con AES. SMB 3.1.1 negocia AES-128-GCM por defecto; Windows 11 y Server 2022 añaden AES-256-GCM/CCM. Se puede exigir por recurso, por servidor o al mapear:

```powershell
Set-SmbShare -Name datos -EncryptData $true      # por recurso (no ejecutado)
```

```bash
net use Z: \\192.168.1.50\datos /requireprivacy  # al mapear (no ejecutado)
```

Con el cifrado exigido y `RejectUnencryptedAccess` en `True` (valor por defecto), los clientes sin SMB 3 reciben «Acceso denegado». Tiene un coste de rendimiento, y no sustituye al cifrado en reposo (BitLocker).

La protección de integridad de la negociación de SMB 3.1.1 evita degradar la conexión a SMB 2, pero no a SMB 1: otra razón para tenerlo desinstalado.

## Por qué nunca exponer el 445 a internet

SMB está diseñado para redes de confianza: autentica con credenciales de Windows, tiene décadas de vulnerabilidades y su superficie es enorme. Si el 445 es alcanzable desde internet:

- Cualquiera puede **probar contraseñas** indefinidamente contra las cuentas del equipo.
- Cualquier vulnerabilidad de SMB sin parchear es explotable **sin credenciales**.

El caso histórico es **WannaCry** (mayo de 2017). La alerta de CISA lo describe: el gusano se propagaba por la vulnerabilidad MS17-010 (*EternalBlue*) de **SMBv1**, comprobaba los puertos TCP 139 y 445 y, si el 445 respondía, lanzaba el exploit. Cifraba los archivos y pedía rescate. Microsoft había publicado el parche el 14 de marzo de 2017. Las mitigaciones que recomendaba CISA: aplicar el parche, desactivar SMBv1 y **bloquear SMB en el borde de la red** (TCP 445, TCP 139, UDP 137-138).

Reglas concretas:

```text
❌ Router: reenvío  TCP 445 → 192.168.1.50:445   (SMB expuesto a internet)
✅ Router: sin reenvío del 445; acceso externo por VPN o por SFTP
```

Para el reenvío de puertos y sus riesgos, véase [Redirección de Puertos](Redireccion-de-Puertos.md).

## SMB sobre VPN

La forma segura de llegar a una carpeta compartida desde fuera es entrar primero en la red local con una [VPN](VPN.md) (por ejemplo [WireGuard](../../devops/despliegue-en-vps/WireGuard.md)) y usar después la ruta UNC normal: `\\192.168.1.50\datos` funciona igual porque, a efectos de red, el equipo remoto ya está dentro. El 445 solo se abre en la interfaz del túnel, nunca en la pública.

Dos matices:

- La resolución de nombres (`\\nas-oficina`) puede fallar a través del túnel si el DNS de la oficina no llega al cliente; usar la IP lo evita.
- SMB es sensible a la latencia: abrir una carpeta con miles de archivos por una VPN lenta resulta mucho peor que en la LAN.

Existe además **SMB sobre QUIC** (Windows Server 2022 Datacenter: Azure Edition, Windows Server 2025 y clientes Windows 11): envuelve SMB en un túnel TLS 1.3 sobre **UDP 443** en lugar del TCP 445, lo que Microsoft llama una «VPN de SMB». La documentación indica expresamente no permitir el TCP/445 de entrada en el servidor. No ejecutado: requiere servidor y certificados.

## Credenciales y acceso anónimo

- **Credenciales**: SMB autentica con una cuenta (local del servidor o de dominio). Windows ofrece guardarlas en el Administrador de credenciales, y las reutiliza al reconectar.
- **Invitado / anónimo**: un recurso accesible sin usuario. Es cómodo y peligroso: cualquiera en la red lee (o escribe) en él. Además, con la firma obligatoria de Windows 11 24H2, los recursos con acceso de invitado dejan de funcionar con el comportamiento por defecto. Si un NAS tiene el acceso de invitado activado «por comodidad», conviene crear usuarios reales.
- **Una sola identidad por servidor**: Windows no admite dos sesiones con usuarios distintos contra el mismo servidor (ver el error 1219 más abajo).

## Errores frecuentes

Los textos de error son los que devuelve `net helpmsg <código>` en Windows en español (2026-11-10).

- **Error de sistema 1219** — «Las conexiones múltiples para un servidor o recurso compartido compatible por el mismo usuario, usando más de un nombre de usuario, no están permitidas. Desconecte todas las conexiones anteriores al servidor o recursos compartido e inténtelo de nuevo.» Causa: ya hay una sesión abierta contra ese servidor con otra cuenta. Solución: `net use \\192.168.1.50 /delete` (o `net use * /delete` para cerrarlas todas) y volver a conectar; o acceder por el nombre en un caso y por la IP en el otro, porque Windows los trata como servidores distintos.
- **Error de sistema 5** — «Acceso denegado.» La conexión se estableció, pero una de las dos capas de permisos (recurso compartido o NTFS) no te autoriza, o el servidor exige cifrado y el cliente no lo soporta. Revisa las dos capas antes de tocar nada más.
- **Error de sistema 1326** — «El nombre de usuario o la contraseña no son correctos.» La cuenta no existe en el servidor o la contraseña es otra. Con dos equipos de grupo de trabajo, hace falta una cuenta con ese nombre y contraseña en el servidor.
- **Error de sistema 53** — «No se ha encontrado la ruta de acceso de la red.» El servidor no responde por el 445: equipo apagado, IP errónea, otra subred, cortafuegos de Windows con el perfil de red en *Pública* o recurso compartido inexistente.
- **Error de sistema 67** — «No se encuentra el nombre de red especificado.» El servidor responde, pero el nombre del **recurso** (la parte `\datos`) no existe: recuerda que es el nombre del recurso compartido, no el de la carpeta.
- **Credenciales antiguas en caché** — tras cambiar la contraseña, Windows sigue ofreciendo la guardada y falla. Se borra desde el Administrador de credenciales (*Credenciales de Windows*) o con `net use \\192.168.1.50 /delete`.
- **No conecta a un NAS o equipo antiguo tras actualizar a Windows 11 24H2** — la firma obligatoria. Activa la firma en el dispositivo; no la desactives en el cliente.

## SMB, NAS, SFTP o WebDAV: cuándo usar cada uno

| Necesidad | Usa | Por qué |
|---|---|---|
| Carpeta de oficina entre equipos Windows, en la LAN | **SMB** | Integrado en el sistema; la unidad aparece como un disco más |
| Un disco compartido dedicado, siempre encendido, con usuarios y copias | [**NAS**](NAS.md) | Es un servidor SMB (y más) listo para usar |
| Subir/bajar archivos a un servidor remoto o a un VPS | [**SFTP**](FTP-y-SFTP.md) | Cifrado, un único puerto (22) y claves SSH; seguro por internet |
| Carpeta remota a través de internet, montada como unidad, en puerto web | [**WebDAV**](WebDAV.md) sobre HTTPS | Atraviesa cortafuegos que dejan pasar 443 |
| Acceso a la carpeta de la oficina desde casa o de viaje | **SMB sobre [VPN](VPN.md)** | El 445 queda dentro del túnel |
| Gestionar un servidor Linux por terminal y mover archivos | [**SSH**](SSH.md) / SFTP | SMB no es necesario |
| Publicar archivos a clientes externos | Enlace de descarga o SFTP, **nunca SMB** | El 445 no debe estar en internet |

## Buenas prácticas avanzadas

- **Gestiona los permisos solo en NTFS y deja el recurso compartido abierto a *Usuarios autenticados*.** Dos capas de permisos que se pisan son la causa más típica de «Acceso denegado» inexplicable. Con una sola capa estricta, la política se audita en un único sitio, y se asigna a **grupos** (`Facturacion`), no a personas.
- **Audita el uso de SMB 1 antes de apagarlo en un entorno antiguo.** `Set-SmbServerConfiguration -AuditSmb1Access $true` registra el ID de evento 3000 en `Microsoft-Windows-SMBServer\Audit` cada vez que un cliente lo intenta: se ve qué impresora o escáner depende de él antes de romperlo.
- **Exige cifrado en los recursos con datos sensibles y desinstala SMB 1 a la vez.** La documentación de Microsoft advierte que la protección contra degradación del protocolo cubre SMB 2, pero no SMB 1. Cifrar con SMB 1 todavía instalado deja la puerta abierta.
- **Comprueba qué escucha de verdad en el 445 con `netstat -ano`.** En un portátil conviene que el cortafuegos trate las redes desconocidas como *Pública* y bloquee la entrada de SMB. Una exploración desde fuera (por ejemplo, la prueba de puertos comunes de [Shields Up!](https://www.grc.com/shieldsup)) confirma que el 445 está cerrado.
- **Vigila los recursos administrativos y ocultos.** `Get-SmbShare` lista todos los recursos, incluidos los terminados en `$`. Un recurso oculto no es un recurso protegido: solo evita que aparezca al explorar.
- **Copias aparte del recurso compartido.** SMB no versiona: si el ransomware cifra la unidad mapeada, cifra también todo lo que ve. Una copia desconectada o con versiones inmutables en el NAS es lo que permite recuperar.

## Documentación oficial

- [Detect, enable, and disable SMBv1, SMBv2, and SMBv3 in Windows](https://learn.microsoft.com/en-us/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3) — estado de SMB 1 por defecto, comandos de detección y la firma obligatoria de Windows 11 24H2.
- [SMB Security Enhancements](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-security) — cifrado, algoritmos de firma y protección frente a degradación.
- [SMB over QUIC](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-over-quic) — acceso a SMB por internet sin abrir el 445.
- [Mounting samba shares from a unix client](https://wiki.samba.org/index.php/Mounting_samba_shares_from_a_unix_client) — `mount.cifs` y el fichero de credenciales.

## Recursos didácticos

- [Indicators associated with WannaCry ransomware (CISA)](https://www.cisa.gov/news-events/alerts/2017/05/12/indicators-associated-wannacry-ransomware) — cómo un SMB 1 expuesto y sin parchear se convirtió en un incidente mundial.

---

*En resumen: SMB comparte carpetas por el 445 dentro de la red local, con permisos en dos capas donde gana la más restrictiva, SMB 1 apagado y el puerto jamás expuesto a internet: desde fuera se entra por VPN.*
