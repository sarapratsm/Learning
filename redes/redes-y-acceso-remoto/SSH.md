# SSH

## ¿Qué es?

**SSH** (*Secure Shell*) es un protocolo para conectarse a otro equipo a través de la red y darle órdenes por **línea de comandos**, con toda la comunicación cifrada. Además de la terminal remota, el mismo canal cifrado sirve para copiar ficheros (`scp`, `sftp`) y para llevar *dentro* otras conexiones (los **túneles**).

El estándar de facto es **OpenSSH**: el cliente `ssh` viene con Windows 10/11, macOS y casi cualquier Linux, y el servidor `sshd` es el que escucha en prácticamente todos los servidores Linux.

## ¿Por qué existe?

Antes de SSH se usaban **Telnet** (terminal remota) y `rsh`/`ftp`, que enviaban todo en texto plano: el usuario, la contraseña y cada comando viajaban tal cual por cada router intermedio, y cualquiera que pudiera ver el tráfico (una wifi compartida, un equipo comprometido en el camino) lo leía. SSH nació en 1995 para hacer lo mismo con tres garantías que Telnet no daba:

- **Confidencialidad**: el tráfico va cifrado.
- **Integridad**: si alguien modifica un paquete por el camino, se detecta.
- **Autenticación en los dos sentidos**: el servidor demuestra quién es (para que no te conectes a un impostor) y tú demuestras quién eres (con contraseña o, mejor, con una clave).

> Si ya usas HTTPS, piensa en SSH como "TLS para una terminal": un canal cifrado y autenticado sobre TCP, con la diferencia de que aquí no hay autoridades certificadoras: el cliente guarda la huella de cada servidor la primera vez que lo ve (se explica en [known_hosts](#known_hosts-y-la-huella-del-servidor)).

A diferencia del [Escritorio Remoto](Escritorio-Remoto.md) o [VNC](VNC.md), SSH no muestra una pantalla con ventanas: da una **consola de texto**. Es mucho más ligero y funciona en servidores sin interfaz gráfica.

## ¿Cuándo y para qué se usa?

Ejemplo conductor: una tienda online en un VPS `203.0.113.10` (dominio `tienda.ejemplo.com`), con usuario `deployer`, y una red de oficina `192.168.1.0/24` con un equipo en `192.168.1.20` y un NAS en `192.168.1.50`. Las direcciones públicas son de documentación (RFC 5737) y las locales, privadas (RFC 1918); no son las de ninguna máquina real.

- **Administrar el VPS**: actualizar paquetes, reiniciar un servicio, leer logs.
- **Desplegar**: un pipeline de CI/CD entra por SSH para actualizar los contenedores.
- **Copiar ficheros** de y hacia un servidor (copias de seguridad, informes).
- **Alcanzar servicios que no están expuestos**: la base de datos del VPS que solo escucha en `127.0.0.1`, el panel web del NAS.
- **Saltar a redes internas** pasando por un único equipo de entrada (*bastión*).

## Cómo es una conexión

Al ejecutar `ssh deployer@203.0.113.10` ocurren, en orden, estas fases:

1. **Negociación**: cliente y servidor se anuncian los algoritmos que soportan y eligen uno de cada tipo (intercambio de claves, cifrado, firma). Es lo que permite que versiones distintas se entiendan.
2. **Intercambio de claves**: acuerdan una clave de sesión efímera que solo conocen ellos. Desde ese momento todo va cifrado.
3. **Autenticación del servidor**: el servidor firma con su **clave de host** y el cliente comprueba que es la que recuerda (`known_hosts`).
4. **Autenticación del usuario**: contraseña o clave pública.
5. **Sesión**: una terminal, un comando suelto, un túnel o una transferencia de ficheros, todos multiplexados dentro del mismo canal.

Patrones de uso diario (no ejecutados contra una máquina real; los comandos se corresponden con la man page de `ssh`):

```bash
ssh deployer@203.0.113.10                 # sesión interactiva
ssh -p 2222 deployer@203.0.113.10         # servidor en un puerto distinto de 22
ssh deployer@203.0.113.10 "df -h"         # ejecutar un comando y volver (sin terminal)
ssh -i ~/.ssh/tienda_vps deployer@203.0.113.10   # indicar qué clave privada usar
```

El comando remoto de la tercera línea devuelve su salida por la terminal local y el código de salida del comando se convierte en el de `ssh`, así que sirve en scripts.

### Versión y algoritmos

Un equipo Windows con Git Bash puede tener dos clientes distintos (observado el 2026-11-10):

```text
$ ssh -V                                  # el de Git Bash
OpenSSH_10.3p1, OpenSSL 3.5.6 7 Apr 2026

$ C:\Windows\System32\OpenSSH\ssh.exe -V  # el que trae Windows
OpenSSH_for_Windows_9.5p2, LibreSSL 3.8.2
```

Conviene saber cuál se ejecuta (`where ssh` en PowerShell, `which ssh` en Git Bash), porque cada uno lee su propia configuración de algoritmos y gestiona el agente de forma distinta (ver [ssh-agent](#ssh-agent-y-forwardagent)).

Recomendaciones de algoritmos, según las notas de versión de OpenSSH (leídas el 2026-11-10 en `openssh.com/txt/release-10.0` y `release-10.1`):

| Aspecto | Recomendación | Fuente |
|---|---|---|
| Clave de usuario | **Ed25519**. RSA solo por compatibilidad y con 3072 bits o más (4096 es habitual) | — |
| Intercambio de claves | El predeterminado desde OpenSSH 10.0 es el híbrido post-cuántico `mlkem768x25519-sha256`; no lo cambies salvo necesidad | notas 10.0 |
| DSA | **Eliminado** en OpenSSH 10.0; si una clave es `ssh-dss`, hay que sustituirla | notas 10.0 |
| Avisos | Desde 10.1, `ssh` avisa si la conexión negocia un intercambio de claves no post-cuántico (opción `WarnWeakCrypto`) | notas 10.1 |
| SHA-1 | `ssh-rsa` (firma RSA con SHA-1) está desactivado por defecto desde hace años; usa `rsa-sha2-256/512` | — |

Un cliente puede listar lo que soporta con `ssh -Q kex` o `ssh -Q key`; el `ssh` 10.3 de Git Bash incluye entre otros `curve25519-sha256`, `sntrup761x25519-sha512` y `mlkem768x25519-sha256`. Si un servidor antiguo solo ofrece algoritmos débiles, la mejor respuesta es actualizar el servidor, no reactivar algoritmos en el cliente.

## Autenticación por clave

Con contraseña, quien consiga adivinarla entra. Con **clave pública** hay un par de ficheros: la **privada** se queda en tu equipo y nunca viaja; la **pública** se copia al servidor y no es secreta. Al conectar, el servidor lanza un reto que solo se resuelve con la privada.

> Es un candado (la pública, que puede estar en mil servidores) y su única llave (la privada, que solo tienes tú).

### Generar un par Ed25519

Se genera siempre en tu máquina, con ruta explícita (`-f`) para no sobrescribir `~/.ssh/id_ed25519`:

```bash
ssh-keygen -t ed25519 -C "portatil-de-trabajo" -f ~/.ssh/tienda_vps
```

Salida real de la generación (con `-N ""` para no pedir passphrase en la prueba; en uso real pon una):

```text
Your identification has been saved in keys/tienda_vps
Your public key has been saved in keys/tienda_vps.pub
The key fingerprint is:
SHA256:eZG5bxIPPTAWI9r2SxW+6Y/4orN1L8h8K5nrMHMTnxM portatil-de-trabajo
```

La pública es **una sola línea** (tipo, clave en base64, comentario) y pesa 101 bytes; una RSA de 4096 bits pesa 727:

```text
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILvANXVU9TrQkWA556EAa6ZA+u08+lwEZ7z62iQ/4eVu portatil-de-trabajo
```

### La huella (fingerprint)

La **huella** es un resumen hash de la clave pública; sirve para comparar claves sin leerlas enteras. Se muestra con `ssh-keygen -l`:

```text
$ ssh-keygen -l -f keys/tienda_vps.pub
256 SHA256:eZG5bxIPPTAWI9r2SxW+6Y/4orN1L8h8K5nrMHMTnxM portatil-de-trabajo (ED25519)

$ ssh-keygen -l -E md5 -f keys/tienda_vps.pub     # formato antiguo, aún visto en algunos paneles
256 MD5:a5:31:59:df:7d:6a:33:3f:b1:81:c3:2e:5c:be:9f:0b portatil-de-trabajo (ED25519)
```

El primer número es el tamaño (256 bits en Ed25519) y la huella `SHA256:` es la que muestra el cliente la primera vez que se conecta a un servidor. Con `-v` añade el dibujo *randomart*, una representación visual de la huella que facilita compararlas a ojo.

Instalar la pública en el servidor (`ssh-copy-id`, permisos de `authorized_keys`) y, sobre todo, **desactivar después las contraseñas** está en [Acceso SSH seguro](../../devops/despliegue-en-vps/Acceso-SSH-Seguro.md); aquí solo se necesita saber que la línea `.pub` acaba en `~/.ssh/authorized_keys` del usuario destino.

## known_hosts y la huella del servidor

Cuando el servidor se presenta, el cliente comprueba su clave de host contra `~/.ssh/known_hosts`. La primera vez no la conoce y pregunta (el texto exacto está en `sshconnect.c` del código de OpenSSH):

```text
The authenticity of host '203.0.113.10 (203.0.113.10)' can't be established.
ED25519 key fingerprint is SHA256:...
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Esa pregunta es **la única defensa frente a un impostor interpuesto** (*man-in-the-middle*) en la primera conexión. La respuesta correcta no es `yes` por reflejo, sino comparar la huella con la real, que se obtiene en el propio servidor (por la consola web del proveedor, por ejemplo):

```bash
ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub
```

Con `yes`, el cliente guarda la clave en `known_hosts` y no vuelve a preguntar. El fichero es una línea por servidor. Se puede consultar y mantener con `ssh-keygen` (probado sobre un `known_hosts` de prueba con una clave de host generada para la ocasión):

```text
$ ssh-keygen -F tienda.ejemplo.com -f kh2          # ¿qué sé de este servidor?
# Host tienda.ejemplo.com found: line 1
tienda.ejemplo.com,203.0.113.10 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIJz1Acp...

$ ssh-keygen -R tienda.ejemplo.com -f kh2          # olvidar la entrada
# Host tienda.ejemplo.com found: line 1
kh2 updated.
Original contents retained as kh2.old
```

`ssh-keygen -H` (o la opción `HashKnownHosts yes`) sustituye los nombres por un hash (`|1|MQu6pq...|PbZ3dP... ssh-ed25519 AAAA...`), de modo que quien robe el fichero no obtenga la lista de servidores a los que te conectas.

### La advertencia de huella cambiada

Si la clave que presenta el servidor **no coincide** con la guardada, OpenSSH se niega a conectar con este mensaje (texto tomado de `sshconnect.c` en el repositorio oficial de OpenSSH, leído el 2026-11-10; no se provocó contra ninguna máquina):

```text
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
Someone could be eavesdropping on you right now (man-in-the-middle attack)!
It is also possible that a host key has just been changed.
The fingerprint for the ED25519 key sent by the remote host is
SHA256:...
Please contact your system administrator.
Add correct host key in /home/usuario/.ssh/known_hosts to get rid of this message.
Offending ED25519 key in /home/usuario/.ssh/known_hosts:7
Host key for 203.0.113.10 has changed and you have requested strict checking.
Host key verification failed.
```

Las causas legítimas son una **reinstalación** del servidor, un cambio de IP o dominio que ahora apunta a otra máquina, o un servidor nuevo tras recrear un VPS. La ilegítima es alguien interponiéndose. La línea `Offending ED25519 key in ...:7` dice qué línea de `known_hosts` choca.

Qué hacer: **averiguar antes** (preguntar a quien administra el servidor, o comparar la huella nueva con la que se ve en su consola) y solo entonces `ssh-keygen -R 203.0.113.10`. Borrar la línea por reflejo anula la protección.

`StrictHostKeyChecking` regula esta conducta: `ask` (predeterminado) pregunta en hosts nuevos y bloquea los cambiados; `accept-new` acepta hosts nuevos sin preguntar pero sigue bloqueando los cambiados; `no` lo acepta todo y desactiva la protección.

## El fichero `~/.ssh/config`

Teclear usuario, puerto y clave en cada conexión es incómodo. `~/.ssh/config` guarda **alias** con sus parámetros. Con un fichero de prueba (en uso real vive en `~/.ssh/config`; en Windows, `C:\Users\<usuario>\.ssh\config`):

```text
Host tienda
    HostName 203.0.113.10
    User deployer
    IdentityFile keys/tienda_vps
    IdentitiesOnly yes

Host nas
    HostName 192.168.1.50
    User admin
    Port 2222

Host db-interna
    HostName 10.0.0.5
    User deployer
    ProxyJump tienda

Host *
    ServerAliveInterval 60
```

Reglas de lectura: cada `Host` es un patrón; el cliente aplica **todos los bloques que casan** y, para cada opción, **gana el primer valor encontrado** (por eso lo específico va arriba y `Host *` abajo). `HostName` es la dirección real; `Host` es solo el nombre que tecleas.

Para ver qué configuración **efectiva** resultará, sin conectar, se usa `ssh -G` (con `-F` para leer un fichero concreto en vez del de la usuaria):

```text
$ ssh -F config -G tienda
user deployer
hostname 203.0.113.10
port 22
identitiesonly yes
serveraliveinterval 60
identityfile keys/tienda_vps
forwardagent no

$ ssh -F config -G nas
user admin
hostname 192.168.1.50
port 2222
identitiesonly no
serveraliveinterval 60
identityfile ~/.ssh/id_rsa
identityfile ~/.ssh/id_ecdsa
identityfile ~/.ssh/id_ecdsa_sk
identityfile ~/.ssh/id_ed25519
identityfile ~/.ssh/id_ed25519_sk
forwardagent no

$ ssh -F config -G db-interna
user deployer
hostname 10.0.0.5
port 22
identitiesonly no
serveraliveinterval 60
identityfile ~/.ssh/id_rsa
...
proxyjump tienda
```

(La salida real incluye más líneas; aquí solo se muestran las relevantes.) Tres cosas que enseña:

- Lo no declarado toma el **valor por defecto**: `port 22`, `forwardagent no`.
- `Host *` se mezcla en todos: `serveraliveinterval 60` aparece en los tres.
- Sin `IdentityFile`, `ssh` prueba las **cinco claves por defecto**, y con `IdentitiesOnly no` ofrecerá también las del agente. Si tienes muchas claves, el servidor puede cortar con `Too many authentication failures`: fija `IdentityFile` e `IdentitiesOnly yes` en cada host.

`ssh -G` es la primera herramienta cuando "no usa la clave que esperaba" o "va a un puerto equivocado".

## Copiar ficheros: `scp` y `sftp`

Ambos reutilizan la conexión SSH, el `config` y las claves. *No ejecutados* (requieren servidor); sintaxis según las man pages de `scp` y `sftp`:

```bash
scp informe.pdf tienda:/srv/backups/            # subir
scp tienda:/var/log/tienda/app.log .            # bajar
scp -r ./dist tienda:/srv/tienda/               # directorio entero
sftp tienda                                      # sesión interactiva: ls, get, put, cd...
```

`scp` copia de A a B de una vez; `sftp` abre una sesión para explorar y transferir varias veces. Nota: desde OpenSSH 9.0, `scp` usa por dentro el **protocolo SFTP** en lugar del antiguo protocolo `rcp`, más frágil con nombres con caracteres especiales. Para sincronizar directorios (solo copia lo cambiado), `rsync -av -e ssh` es mejor que `scp`. Qué es SFTP frente a FTP y FTPS: [FTP y SFTP](FTP-y-SFTP.md).

## ssh-agent y ForwardAgent

Una clave privada con *passphrase* te la pide en cada conexión. El **agente** (`ssh-agent`) la guarda descifrada **en memoria** y responde a las peticiones de firma, de modo que la tecleas una vez (`ssh-add`). La clave privada nunca sale del agente; solo se le piden firmas.

```bash
ssh-add ~/.ssh/tienda_vps     # pide la passphrase una vez
ssh-add -l                    # lista las huellas cargadas
```

En Windows el agente es un servicio. En el Windows 11 de la prueba, `Get-Service ssh-agent` devuelve `Status: Stopped`, `StartType: Disabled` (valor de fábrica); para usarlo hay que cambiar el servicio a manual o automático, y lo gestiona el `ssh.exe` de Windows, no el de Git Bash, que usa su propio `ssh-agent`.

### `ForwardAgent`: cómodo y peligroso

Con `ForwardAgent yes` (o `ssh -A`), el servidor al que entras recibe un **canal hacia tu agente local**. Así, desde allí puedes hacer `ssh` a un tercer servidor sin copiar claves. El riesgo, según la man page de `ssh_config` («the connection to the agent is automatically forwarded to the remote side»): mientras la sesión esté abierta, **cualquiera con privilegios de administrador en el servidor intermedio puede pedir firmas a tu agente** y suplantarte en todos los sitios donde esa clave tenga acceso. La clave no se copia, pero se usa.

❌ Global y para todos:

```text
Host *
    ForwardAgent yes
```

✅ Mejor, usar `ProxyJump` para saltos (siguiente apartado). Y si de verdad hace falta reenviar el agente, solo hacia un host de máxima confianza y con confirmación por uso (`ssh-add -c`).

## ProxyJump: saltar a través de un bastión

Imagina que la base de datos `10.0.0.5` solo es alcanzable desde el VPS. Con `ProxyJump` el cliente abre primero la conexión al VPS y, **a través de ella**, abre la segunda hacia la base de datos:

```bash
ssh -J deployer@203.0.113.10 deployer@10.0.0.5     # en línea
ssh db-interna                                      # con el config de arriba (ProxyJump tienda)
```

```text
tu equipo ══ SSH ══> VPS 203.0.113.10 ── TCP ──> 10.0.0.5:22
          └──────────── SSH de extremo a extremo ────────────┘
```

La diferencia con `ForwardAgent`: la sesión SSH hacia `10.0.0.5` se cifra **de extremo a extremo desde tu equipo**; el bastión solo reenvía bytes cifrados y **no ve** ni tus comandos ni tu agente. Funciona también con `scp -J` y `sftp -J`. Cadenas de saltos: `-J salto1,salto2`.

## Túneles: `-L`, `-R` y `-D`

Un **túnel** (o *port forwarding*) hace que un puerto TCP lleve su tráfico **dentro** de la conexión SSH, que ya está cifrada y autenticada. Resuelve el problema de alcanzar un servicio que no se quiere (o no se puede) abrir a internet.

> **No ejecutado.** La máquina de pruebas no tiene servidor `sshd` y no se ha instalado ninguno. Lo que sigue se explica a partir de la man page de `ssh` (`man.openbsd.org/ssh`, opciones `-L`, `-R` y `-D`, leída el 2026-11-10). Sí se ha comprobado en local que sin servidor el cliente responde `ssh: connect to host 127.0.0.1 port 6810: Connection refused`.

### `-L`: puerto local hacia un destino visible desde el servidor

Según la man page, `-L` indica que las conexiones al puerto local indicado se reenvían por el canal seguro hacia un host y puerto del lado remoto. Caso: la base de datos PostgreSQL del VPS solo escucha en `127.0.0.1:5432` y quieres abrirla desde tu cliente gráfico.

```bash
ssh -L 5433:127.0.0.1:5432 deployer@203.0.113.10
```

```text
 TU EQUIPO                         VPS 203.0.113.10
┌──────────────────┐              ┌──────────────────────────┐
│ cliente SQL      │              │                          │
│   │ conecta a    │   túnel SSH  │  sshd ──> 127.0.0.1:5432 │
│   ▼              │ ═══════════> │           (PostgreSQL)   │
│ 127.0.0.1:5433 ──┼──────────────┘                          │
└──────────────────┘              └──────────────────────────┘
```

Se lee `-L puerto_local:destino:puerto_destino`. El **destino se resuelve desde el servidor**: aquí `127.0.0.1` significa "el propio VPS", no tu equipo. Mientras la sesión esté abierta, conectar a `127.0.0.1:5433` en tu máquina llega a PostgreSQL. Por defecto el puerto local solo escucha en el bucle local; no lo abras a la red con `0.0.0.0` sin necesidad.

Opciones útiles: `-N` (no abrir terminal, solo túnel) y `-f` (segundo plano).

### `-R`: puerto remoto hacia un destino visible desde tu equipo

`-R` es el inverso: según la man page, las conexiones al puerto del **servidor** se reenvían hacia tu lado. Caso: enseñar a un compañero, a través del VPS, el servidor de desarrollo que corre en tu portátil en el 3000.

```bash
ssh -R 8080:127.0.0.1:3000 deployer@203.0.113.10
```

```text
 TU EQUIPO                          VPS 203.0.113.10
┌──────────────────┐               ┌──────────────────────────┐
│ app dev          │   túnel SSH   │  127.0.0.1:8080          │
│ 127.0.0.1:3000 <─┼═══════════════┼── (quien conecte aquí    │
└──────────────────┘               │   llega a tu portátil)   │
                                   └──────────────────────────┘
```

Por defecto el puerto remoto escucha solo en el bucle local del servidor; para que escuche en todas las interfaces el servidor debe tener `GatewayPorts` activado, y eso **abre tu portátil a internet** a través del VPS. Es un riesgo: úsalo con intención.

### `-D`: proxy SOCKS dinámico

Con `-D` el cliente abre un **proxy SOCKS** en un puerto local: cada aplicación que lo use decide su destino y SSH lo reenvía por el túnel, saliendo desde el servidor.

```bash
ssh -D 1080 -N deployer@203.0.113.10
# navegador o curl con proxy SOCKS5 en 127.0.0.1:1080
```

```text
navegador ──> 127.0.0.1:1080 ══ túnel SSH ══> VPS ──> cualquier destino que la app pida
```

Sirve para navegar como si estuvieras en la red del servidor. Frente a una [VPN](VPN.md) es más modesto: solo afecta a las aplicaciones configuradas para usar el proxy y no es una interfaz de red.

### Cuándo un túnel basta y cuándo no

| Necesidad | Herramienta |
|---|---|
| Un puerto concreto, uso puntual (base de datos, panel interno) | Túnel `-L` |
| Compartir temporalmente algo de tu equipo | `-R` (con cuidado) |
| Navegar con la salida del servidor | `-D` |
| Acceso permanente a **toda** una red interna, varias personas | [VPN](VPN.md) |

Los túneles también pueden desactivarse en el servidor (`AllowTcpForwarding no`) y por clave (`restrict`, ver [Acceso SSH seguro](../../devops/despliegue-en-vps/Acceso-SSH-Seguro.md)).

## Cuándo NO exponer el puerto 22 a internet

Un servidor con el 22 abierto recibe intentos de fuerza bruta de bots a los pocos minutos de existir. Con contraseñas desactivadas no entran, pero siguen llenando los logs y consumiendo recursos, y un fallo futuro del propio `sshd` sería explotable desde cualquier sitio.

| Situación | ¿Exponer el 22 a internet? |
|---|---|
| VPS público de producción, sin otra vía | Sí, pero con solo claves, `PermitRootLogin no`, [UFW](../../devops/despliegue-en-vps/UFW.md) y [Fail2ban](../../devops/despliegue-en-vps/Fail2ban.md) |
| VPS al que puedes entrar por una [VPN](VPN.md) | **No**: abre el 22 solo desde la red de la VPN (ver [WireGuard](../../devops/despliegue-en-vps/WireGuard.md)) |
| Equipo de oficina (`192.168.1.20`) o NAS (`192.168.1.50`) tras el router | **No**: no hagas [redirección de puertos](Redireccion-de-Puertos.md) del 22 hacia dentro; entra por VPN |
| Servidor interno alcanzable desde un bastión | **No**: usa `ProxyJump` |

Cambiar el puerto (por ejemplo al 2222) reduce el ruido de los escáneres automáticos, pero no frena a quien escanee a propósito: es higiene, no seguridad. Lo que cierra la puerta es dejar de aceptar contraseñas y limitar desde dónde se puede llegar.

## Errores frecuentes

| Síntoma | Causa habitual | Cómo comprobarlo |
|---|---|---|
| `Permission denied (publickey)` | La pública no está en `authorized_keys` del usuario correcto, se ofrece otra clave, o permisos del lado servidor demasiado abiertos | `ssh -v`: busca `Offering public key:` y `Authentications that can continue:` |
| `Host key verification failed.` | La clave de host no coincide con `known_hosts` (ver el aviso completo arriba), o en un script no hay `known_hosts` y no se puede preguntar | `ssh-keygen -F host`; comparar huellas antes de `ssh-keygen -R` |
| `Connection refused` | La máquina **responde** pero **nada escucha** en ese puerto: `sshd` parado, puerto equivocado, o el firewall rechaza activamente | Se ve al instante. Salida real: `ssh: connect to host 127.0.0.1 port 6810: Connection refused` |
| `Connection timed out` | **Nadie responde**: IP equivocada, equipo apagado, firewall que descarta paquetes (`DROP`) o falta de ruta | Tarda decenas de segundos; `-o ConnectTimeout=5` lo acorta. Mensaje: `ssh: connect to host ... port 22: Connection timed out` (no ejecutado contra una máquina real) |
| `Too many authentication failures` | El agente o los ficheros por defecto ofrecen demasiadas claves antes de la buena | `IdentityFile` + `IdentitiesOnly yes` en el `config` |
| `WARNING: UNPROTECTED PRIVATE KEY FILE!` | La clave privada es legible por otras cuentas | Ver siguiente apartado |
| `REMOTE HOST IDENTIFICATION HAS CHANGED!` | Servidor reinstalado o suplantación | Averiguar antes de borrar la línea |
| Sigue pidiendo contraseña tras instalar la clave | Permisos de `~/.ssh` (700) o `authorized_keys` (600) en el servidor | `journalctl -u ssh` en el servidor: `bad ownership or modes` |

La diferencia entre *refused* y *timed out* es la mejor pista de red: *refused* significa que el paquete llegó y alguien contestó "aquí no"; *timed out* significa que se perdió o se descartó sin respuesta (típico de un firewall con política de descarte, o de apuntar a una IP que no existe).

### Permisos de la clave en Windows

OpenSSH rechaza una clave privada que puedan leer otras cuentas. En Linux se resuelve con `chmod 600`; en Windows el equivalente son las **ACL**. Reproducido con una copia de la clave de prueba a la que se concedió lectura al grupo local `Usuarios` (observado con `ssh-keygen.exe` de Windows el 2026-11-10):

```text
Bad permissions. Try removing permissions for user: BUILTIN\\Usuarios (S-1-5-32-545) on file C:/.../keys/mala.
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@         WARNING: UNPROTECTED PRIVATE KEY FILE!          @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Permissions for 'keys/mala' are too open.
It is required that your private key files are NOT accessible by others.
This private key will be ignored.
Load key "keys/mala": bad permissions
```

El mensaje dice qué hacer: quitar el permiso sobrante. Con `icacls` (sobre la clave de prueba; `*S-1-5-32-545` es el identificador del grupo Usuarios, válido en cualquier idioma de Windows):

```powershell
icacls $clave /inheritance:r                    # dejar de heredar permisos de la carpeta
icacls $clave /remove "*S-1-5-32-545"           # quitar al grupo Usuarios
icacls $clave /grant:r "${env:USERNAME}:(R)"    # solo tu cuenta, solo lectura
```

Tras ese ajuste, `ssh-keygen -y -f` sobre la misma clave vuelve a leerla sin quejarse. Los permisos de `chmod` en Git Bash (`-rw-r--r--` en `ls -l`) no reflejan las ACL reales de Windows: la referencia es `icacls`. Si la clave está en una carpeta heredada de otra (por ejemplo, copiada a `C:\Users\Public`), el problema es el mismo.

## Buenas prácticas avanzadas

- **Una clave por persona y por dispositivo, con passphrase, cargada en el agente.** Revocar a quien se va o a un portátil perdido es borrar una línea de `authorized_keys`. Con una clave compartida habría que rotarla para todos.
- **Prefiere `ProxyJump` a `ForwardAgent`.** El salto con `-J` no expone tu agente al bastión; el reenvío sí. Si ya tienes `ForwardAgent yes` en un `Host *`, quítalo y compruébalo con `ssh -G <host> | grep forwardagent`.
- **Fija `IdentityFile` + `IdentitiesOnly yes` por host.** Evita el `Too many authentication failures` y, además, evita **filtrar a un servidor ajeno** cuáles son tus claves públicas (cada clave ofrecida le revela una huella tuya).
- **Verifica la huella en la primera conexión y automatiza con criterio.** En scripts, `StrictHostKeyChecking no` equivale a no tener autenticación del servidor. Usa `accept-new` o, mejor, carga un `known_hosts` verificado (con `ssh-keyscan` y comparación de huella).
- **Limita lo que puede hacer cada clave en el servidor.** Las opciones de `authorized_keys` (`restrict`, `command=`, `from=`) acotan una clave de despliegue a un único comando y a un origen concreto; una clave de CI robada deja de ser una shell.
- **Revisa los algoritmos con una auditoría externa.** [SSH Audit](https://www.sshaudit.com/) valida el servidor desde fuera y te dice qué líneas de `sshd_config` quitar; hazlo tras cada actualización importante.

## Documentación oficial

- [OpenSSH: manual de `ssh`](https://man.openbsd.org/ssh) — referencia de opciones del cliente; las secciones de `-L`, `-R`, `-D` y `-J` son las que más se consultan.
- [OpenSSH: manual de `ssh_config`](https://man.openbsd.org/ssh_config) — todas las directivas del fichero `config`, incluidas `ProxyJump`, `IdentitiesOnly` y `StrictHostKeyChecking`.
- [OpenSSH: manual de `ssh-keygen`](https://man.openbsd.org/ssh-keygen) — generación, huellas (`-l`), `known_hosts` (`-F`, `-R`, `-H`).
- [RFC 4253, SSH Transport Layer Protocol](https://www.rfc-editor.org/rfc/rfc4253) — la fuente normativa, para saber qué hace de verdad la negociación y el intercambio de claves.

## Recursos didácticos

- [SSH Audit](https://www.sshaudit.com/) — audita desde fuera la configuración de un servidor y propone las líneas exactas a corregir.
- [Explainshell](https://explainshell.com/) — pega un comando `ssh -L ...` y lo desmenuza opción por opción.

---

*En resumen: SSH es la terminal remota cifrada que sustituyó a Telnet y, con claves, `known_hosts` y un buen `config`, permite administrar y saltar entre servidores y abrir túneles sin exponer más puertos de los necesarios.*
