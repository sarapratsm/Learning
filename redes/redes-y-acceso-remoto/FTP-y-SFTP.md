# FTP y SFTP

## ¿Qué es?

**FTP** (*File Transfer Protocol*, RFC 959) es un protocolo de 1971-1985 pensado para una sola cosa: subir y bajar ficheros entre un cliente y un servidor. **SFTP** (*SSH File Transfer Protocol*) hace lo mismo, pero es un protocolo distinto que viaja dentro de una conexión [SSH](SSH.md), con todo cifrado y autenticación por clave.

Los nombres engañan: **SFTP no es «FTP sobre SSH»**. No comparte comandos, puertos ni mensajes con FTP. Es otro protocolo que solo ha heredado las siglas.

## ¿Por qué existe?

Antes de que existiera la web, ya hacía falta una forma estándar de mover ficheros entre máquinas. FTP la dio, y sigue vivo en hostings compartidos, sistemas industriales y proveedores que envían catálogos o facturas por lotes. Pero se diseñó cuando las redes eran de confianza y tiene dos defectos graves hoy:

- **Todo viaja en texto plano**: usuario, contraseña, nombres de fichero y contenido. Quien esté en medio del camino (una wifi pública, un router comprometido, un proveedor intermedio) lo lee tal cual.
- **Usa dos conexiones**, y eso lo hace incompatible con la forma en que funcionan hoy los cortafuegos y el NAT (se explica más abajo).

SFTP resuelve ambos: una sola conexión, un solo puerto (el 22) y cifrado de extremo a extremo.

> Si conoces HTTP, FTP es como un HTTP de los años 70 con una peculiaridad rara: el servidor abre una segunda conexión aparte para cada transferencia. SFTP, en cambio, es como un servicio de ficheros que corre «dentro» de la sesión SSH, igual que un túnel dentro de otro.

## ¿Cuándo y para qué se usa?

En la tienda online de ejemplo (VPS `203.0.113.10`, dominio `tienda.ejemplo.com`, usuario `deployer`):

- **Un proveedor sube cada noche su catálogo** (`catalogo.csv`) a una carpeta del VPS, sin tener acceso a nada más del servidor.
- **Descargar una copia de seguridad** de la base de datos desde el VPS al equipo de oficina (`192.168.1.20`) para guardarla en el NAS (`192.168.1.50`).
- **Subir un sitio estático o ficheros grandes** a un servidor donde no se quiere montar una [carpeta compartida](Carpeta-Compartida.md) ni un [WebDAV](WebDAV.md).
- **Integrarse con un sistema antiguo** (un ERP, un TPV, un hosting barato) que solo habla FTP.

No es una herramienta para *trabajar* sobre un fichero remoto (abrirlo, editarlo y guardarlo en vivo): transfiere copias. Tampoco sincroniza solo; para mantener dos carpetas iguales existe `rsync`.

## Cuál usar: tabla de decisión

Cinco formas de mover ficheros que se confunden con facilidad:

| Opción | Qué es | Puerto | Cifrado | Úsala cuando |
|---|---|---|---|---|
| **FTP** | Protocolo original | 21 + datos | No | Nunca por internet. Solo en una red local de confianza y porque un equipo antiguo no admite otra cosa |
| **FTPS** | FTP con TLS por encima | 21 (explícito) o 990 (implícito) | Sí | El otro extremo solo ofrece FTP y exige o admite TLS |
| **SFTP** | Protocolo de ficheros sobre SSH | 22 | Sí | Opción por defecto para subir/bajar ficheros contra un servidor Linux |
| **SCP** | Copia de un fichero o carpeta por SSH | 22 | Sí | Copia puntual de una orden, sin sesión interactiva |
| **rsync** | Sincronización incremental, normalmente sobre SSH | 22 | Sí (por SSH) | Copias repetidas de directorios grandes: solo envía lo que cambió |

Reglas prácticas:

- **FTP en claro nunca cruza internet.** Quien lo expone abre una puerta con la contraseña a la vista de cualquiera.
- Si puedes elegir, **SFTP o `rsync` sobre SSH**. Reutilizan el servidor SSH que ya tienes, su cortafuegos y sus claves.
- Si el único camino a un servidor es FTP, mejor FTPS; y si solo es FTP plano, que la conexión pase por una [VPN](VPN.md) en vez de por internet abierto.

## FTP clásico: cómo funciona y por qué se rompe

### Dos conexiones: control y datos

FTP separa las órdenes de los datos:

- **Conexión de control**: el cliente se conecta al puerto **21** del servidor. Por ahí viajan los comandos (`USER`, `PASS`, `LIST`, `RETR`, `STOR`) y las respuestas numéricas (`220`, `331`, `230`, `550`...). Dura toda la sesión.
- **Conexión de datos**: se abre una nueva conexión *por cada* listado o transferencia, y se cierra al terminar. Quién la abre depende del modo.

### Modo activo

En el modo **activo**, el cliente dice en qué puerto escucha y el servidor se conecta *de vuelta* hacia él:

```text
   CLIENTE (192.168.1.20)                      SERVIDOR (203.0.113.10)
   ──────────────────────                      ───────────────────────
   puerto 50000 ─────── control ─────────────► puerto 21
   "PORT 192,168,1,20,195,80"  (= escucho en el 50001)
   puerto 50001 ◄────── datos ───────────────  puerto 20
                      (el servidor abre la conexión)
```

El problema: la conexión entrante hacia el cliente la tumba su cortafuegos, y además el cliente anuncia su IP *privada* (`192.168.1.20`) dentro del comando `PORT`, una dirección que el servidor no puede alcanzar desde internet. El [NAT del router](Redireccion-de-Puertos.md) solo reescribe cabeceras de paquetes, no el texto dentro de la conexión de control, salvo que tenga un ayudante específico para FTP.

### Modo pasivo

En el modo **pasivo** se invierte la iniciativa: el servidor dice en qué puerto escucha y es el cliente quien abre ambas conexiones, las dos hacia fuera:

```text
   CLIENTE (192.168.1.20)                      SERVIDOR (203.0.113.10)
   ──────────────────────                      ───────────────────────
   puerto 50000 ─────── control ─────────────► puerto 21
   "PASV"  →  "227 Entering Passive Mode (203,0,113,10,200,10)"  (= puerto 51210)
   puerto 50001 ─────── datos ───────────────► puerto 51210
```

El cliente solo sale hacia fuera, que es lo que los cortafuegos de cliente permiten. Por eso **el pasivo es el modo por defecto de casi todos los clientes**. El coste se traslada al servidor: debe tener un **rango de puertos pasivos** abierto en su cortafuegos y, si está detrás de NAT, anunciar su IP pública en el `227`. Si no lo hace, el cliente intenta conectar a una IP privada y la sesión se queda colgada.

### Por qué FTP rompe con NAT y cortafuegos

Un cortafuegos normal abre un puerto concreto (el 21) y listo. FTP exige además puertos de datos que cambian en cada transferencia y cuyo número viaja *dentro* del texto de la conexión de control. Para que funcione, el cortafuegos tiene que leer esa conexión y abrir el puerto correcto al vuelo (un módulo *conntrack* de FTP), y eso no es posible si el tráfico va cifrado con FTPS: el cortafuegos ya no puede leer los comandos. Resultado habitual: el login funciona y el listado (`LIST`) se queda colgado.

### Texto plano: las credenciales se ven

FTP no cifra nada. Para comprobarlo se ejecutó una demostración local, **no un servidor FTP real**: un script de Python (librería estándar, sin instalar nada) abre un servidor falso de unas 15 líneas en `127.0.0.1:6890` que solo responde `220`, `331` y `230`, y se conecta a él con `ftplib`. El servidor imprime lo que recibe por el cable:

```python
# DEMOSTRACIÓN: servidor FTP FALSO, solo escucha en 127.0.0.1. No es un servidor real.
import socket, threading, ftplib
captured = []

def serve(srv):
    c, _ = srv.accept()
    f = c.makefile("rwb", buffering=0)
    say = lambda s: f.write((s + "\r\n").encode())
    say("220 Servidor FTP de demostracion")
    while True:
        line = f.readline().decode().rstrip("\r\n")
        if not line: break
        captured.append(line)
        cmd = line.split(" ")[0].upper()
        if cmd == "USER": say("331 Password required")
        elif cmd == "PASS": say("230 Login successful")
        elif cmd == "QUIT": say("221 Bye"); break
        else: say("502 Not implemented")
    c.close()

srv = socket.socket(); srv.bind(("127.0.0.1", 6890)); srv.listen(1)
t = threading.Thread(target=serve, args=(srv,)); t.start()
ftp = ftplib.FTP(); ftp.connect("127.0.0.1", 6890)
ftp.login("deployer", "Contrasena-De-Ejemplo-1"); ftp.quit()
t.join()
print(*captured, sep="\n")
```

Salida (ejecutado el 2026-11-10):

```text
USER deployer
PASS Contrasena-De-Ejemplo-1
QUIT
```

La contraseña aparece íntegra, sin ninguna ofuscación. Con `ftp.set_debuglevel(1)` el cliente la enmascara en *su* pantalla (`PASS ***********`), pero eso es solo cosmética del cliente: por el cable sigue yendo en claro. Cualquiera que capture ese tráfico (por ejemplo con Wireshark en una red compartida) ve exactamente las tres líneas de arriba.

## FTPS: FTP con TLS

**FTPS** es FTP al que se le añade TLS (el mismo cifrado de HTTPS). Cifra las credenciales y los datos, pero **conserva el diseño de dos conexiones**, con todos sus problemas de cortafuegos. Tiene dos variantes:

| Variante | Puerto | Cómo empieza | Estado |
|---|---|---|---|
| **Explícito** (`AUTH TLS`, RFC 4217) | 21 | Conexión en claro y el cliente pide pasar a TLS con `AUTH TLS` antes de enviar credenciales | La variante recomendada |
| **Implícito** | 990 | TLS desde el primer byte | Heredada: no está estandarizada y se mantiene por compatibilidad |

En el explícito hay que comprobar que el cliente *exige* TLS: si solo lo «intenta» y el servidor no lo ofrece, algunos clientes caen a FTP plano sin avisar. Con `curl`, `--ssl-reqd` impone el cifrado y falla si no se puede:

```bash
curl --ssl-reqd --user deployer ftp://203.0.113.10/descargas/   # no ejecutado: requiere un servidor FTPS real
```

## SFTP: un protocolo distinto sobre SSH

SFTP corre como un **subsistema de SSH**: al conectar, el cliente `sftp` abre una sesión SSH normal (puerto **22**) y pide al servidor que arranque el programa `sftp-server`. A partir de ahí, ambos hablan un protocolo binario propio de operaciones sobre ficheros (abrir, leer, escribir, listar). Consecuencias prácticas:

- **Un solo puerto**: el que ya tienes abierto para [SSH](SSH.md). Sin rangos pasivos ni ayudantes de NAT.
- **Mismas claves y mismo `known_hosts`**: la autenticación es la de SSH.
- **No hay modo activo/pasivo**: el problema de las dos conexiones deja de existir.
- **No necesita instalar nada en el servidor** si ya hay `sshd`: el subsistema viene incluido.

En un `sshd_config` típico aparece como una línea:

```text
Subsystem sftp /usr/lib/ssh/sftp-server
```

(La ruta varía según la distribución; en Debian/Ubuntu es `/usr/lib/openssh/sftp-server`.)

## Clientes

| Cliente | Plataforma | Habla | Notas |
|---|---|---|---|
| **`sftp`** (OpenSSH) | Windows 10/11, Linux, macOS | SFTP | Interactivo o por lotes. Incluido con el cliente de OpenSSH |
| **`scp`** (OpenSSH) | ídem | SCP (por SFTP desde OpenSSH 9.0) | Copia directa, sin sesión |
| **WinSCP** | Windows | SFTP, SCP, FTP, FTPS, WebDAV | Software libre, **GPL v3 o posterior** (comprobado en su página de licencia el 2026-11-10). Interfaz gráfica y `winscp.com` para scripts |
| **FileZilla** | Windows, Linux, macOS | FTP, FTPS, SFTP | Cliente gratuito de código abierto (GPL; la versión exacta, 2 o 3, no se pudo confirmar en la página oficial, que carga el contenido cifrado con JavaScript). Existe una edición de pago, **FileZilla Pro**, con más protocolos |
| **`curl`** | Todas | FTP, FTPS, SFTP, SCP, HTTP... | Para scripts y pruebas puntuales |

**Sobre el instalador de FileZilla.** Según la búsqueda web del 2026-11-10, la página de descarga oficial avisa de que su instalador estándar puede incluir **ofertas de terceros** (software adicional patrocinado) y que la lista completa de descargas (`https://filezilla-project.org/download.php?show_all=1`) ofrece builds sin ellas. No se pudo comprobar en la propia página, porque su contenido se descifra con JavaScript, y no se descargó ni se instaló nada. Si se usa FileZilla: descargar solo desde el sitio oficial, elegir la variante sin ofertas y leer cada pantalla del instalador. WinSCP es una alternativa en Windows sin ese problema conocido (no ejecutado: tampoco se instaló).

Ni `curl` ni `sftp` se pueden usar para FTPS/SFTP contra un servidor real en este entorno (no hay ninguno), pero sí se verificó que el `curl` instalado (8.19.0, libssh2 1.11.1) soporta `ftp`, `ftps`, `sftp` y `scp` (`curl -V`).

## `sftp` paso a paso

### Conectar

```bash
sftp deployer@203.0.113.10          # no ejecutado: requiere un servidor SSH real
sftp -P 2222 deployer@203.0.113.10  # otro puerto
sftp -i ~/.ssh/tienda_vps deployer@203.0.113.10   # una clave concreta
```

Pide la huella del servidor la primera vez (como `ssh`) y deja un prompt `sftp>`. Los alias de `~/.ssh/config` valen también aquí: `sftp tienda`. Ver [Acceso SSH seguro](../../devops/despliegue-en-vps/Acceso-SSH-Seguro.md) para generar la clave y el alias.

### Comandos esenciales

No había sshd disponible ni se instaló ninguno, así que los comandos siguientes se ejecutaron contra el binario `sftp-server` de Git for Windows lanzado localmente con `sftp -D <ruta>` (el cliente habla con un `sftp-server` local por tuberías, sin red ni SSH). Sirve para ver el comportamiento real de los comandos, no el cifrado ni la autenticación. Las rutas del equipo se han sustituido por `/srv/tienda`.

La regla mental: los comandos normales actúan en **el servidor** (`cd`, `ls`, `pwd`, `mkdir`, `rm`), y los que empiezan por `l` actúan en **tu máquina** (`lcd`, `lls`, `lpwd`, `lmkdir`).

```text
sftp> pwd
Remote working directory: /srv/tienda
sftp> lpwd
Local working directory: /home/oficina/trabajo
sftp> lcd local
sftp> cd backups
sftp> mkdir nuevos
sftp> put informe.txt
sftp> put backup.bin
sftp> ls -l
-rw-r--r--    ? oficina users    3000000 Nov 10 11:26 backup.bin
-rw-r--r--    ? oficina users         12 Nov 10 11:26 informe.txt
-rw-r--r--    ? oficina users          6 Nov 10 11:26 leeme.txt
drwxr-xr-x    ? oficina users          0 Nov 10 11:26 nuevos
sftp> get leeme.txt
sftp> lls
backup.bin
informe.txt
leeme.txt
```

| Comando | Qué hace |
|---|---|
| `put fichero [destino]` | Sube un fichero (`put -r carpeta` sube una carpeta entera) |
| `get remoto [local]` | Descarga un fichero (`get -r` para carpetas) |
| `ls [-l]` / `cd` / `pwd` / `mkdir` / `rm` / `rmdir` / `rename` | Operan en el servidor |
| `lls` / `lcd` / `lpwd` / `lmkdir` | Operan en tu máquina |
| `chmod modo ruta` | Cambia permisos en el servidor |
| `reget` / `reput` | Reanudan una descarga o subida interrumpida |
| `!comando` | Ejecuta un comando en tu máquina local |
| `help` / `bye` | Ayuda y salir |

### Reanudar una descarga interrumpida

Con ficheros grandes (un volcado de base de datos de varios GB) y una conexión inestable, repetir desde cero es un desperdicio. `reget` continúa desde donde quedó el fichero local. Prueba real: se dejó un `backup.bin` local truncado a 1 000 000 bytes (de 3 000 000) y se reanudó:

```text
sftp> lcd dl
sftp> cd backups
sftp> reget backup.bin
sftp> lls -l
-rw-r--r-- 1 oficina users 3000000 Nov 10 11:26 backup.bin
```

El fichero acabó con los 3 000 000 de bytes completos. `reput` hace lo mismo para subidas. En OpenSSH reciente también existe `get -a` / `put -a` (*append*: reanudar si ya existe un fichero parcial), disponible en el `help` del cliente instalado (OpenSSH 10.3).

### Modo por lotes (sin interacción)

Para ejecutar una lista de comandos sin teclear, `-b` lee un fichero de órdenes. Los comandos de arriba se ejecutaron exactamente así (`sftp -b cmds.txt ...`). En un servidor real sería:

```bash
sftp -b cmds.txt -i ~/.ssh/tienda_vps deployer@203.0.113.10   # no ejecutado: requiere servidor real
```

Con `-b` el cliente no puede preguntar nada: exige autenticación por clave (sin contraseña) y que la huella del servidor ya esté en `known_hosts`. Si un comando falla, el lote se aborta.

## SCP y rsync

**`scp`** copia una orden concreta: origen y destino, uno de ellos remoto con la sintaxis `usuario@host:ruta`.

```bash
scp copia.sql deployer@203.0.113.10:/srv/backups/        # subir un fichero   (no ejecutado)
scp -r deployer@203.0.113.10:/srv/backups/ ./copias/     # bajar una carpeta   (no ejecutado)
```

Detalle de seguridad: desde **OpenSSH 9.0**, `scp` usa por debajo el protocolo SFTP en lugar del antiguo protocolo SCP/RCP, que tenía debilidades de diseño. Si un servidor muy antiguo no lo soporta, `scp -O` fuerza el protocolo clásico (el `scp` instalado lo lista entre sus opciones).

**`rsync`** compara origen y destino y transfiere **solo las diferencias**, lo que lo hace ideal para copias repetidas de directorios grandes. Normalmente corre por SSH:

```bash
rsync -avz --partial --progress /srv/docker/ deployer@203.0.113.10:/srv/docker/   # no ejecutado
```

`rsync` no se probó (Git for Windows no lo incluye). Su comportamiento está descrito en `man rsync`. Una trampa clásica: con `/` final en el origen (`/srv/docker/`) copia el *contenido*; sin él (`/srv/docker`), copia la carpeta y su contenido dentro del destino.

Para elegir entre las dos: `scp` para copiar un fichero suelto una vez; `sftp` si quieres navegar y elegir; `rsync` si la copia se repite o los ficheros son grandes.

## Restringir lo que puede hacer cada usuario

Por defecto, un usuario con SFTP ve **todo lo que sus permisos de sistema le dejan ver**. Esto se comprobó con el `sftp-server` local sin restricciones: un `cd /etc` seguido de `ls` listó sin problema ficheros fuera de la carpeta de trabajo (`profile`, `protocols`, `services`...). Dar acceso a un tercero así es dar un paseo por el servidor.

La solución es doble: que el usuario **solo pueda usar SFTP** (sin shell) y que quede **enjaulado** en su carpeta (*chroot*). Ambas cosas se configuran en el servidor, en `/etc/ssh/sshd_config`. Lo siguiente **no se ejecutó** (no se instaló sshd); se explica a partir del manual de `sshd_config` ([man.openbsd.org/sshd_config](https://man.openbsd.org/sshd_config)).

### Un usuario solo SFTP, enjaulado

Caso: el proveedor `proveedor` debe subir `catalogo.csv` a una carpeta y nada más.

```bash
# En el servidor (no ejecutado)
sudo groupadd sftpusers
sudo useradd -g sftpusers -s /usr/sbin/nologin -d /subidas proveedor
sudo mkdir -p /srv/sftp/proveedor/subidas
sudo chown root:root /srv/sftp/proveedor          # la jaula debe ser de root
sudo chmod 755 /srv/sftp/proveedor
sudo chown proveedor:sftpusers /srv/sftp/proveedor/subidas
sudo chmod 750 /srv/sftp/proveedor/subidas
```

```text
# /etc/ssh/sshd_config
Subsystem sftp internal-sftp

Match Group sftpusers
    ChrootDirectory /srv/sftp/%u
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PasswordAuthentication no
```

Qué hace cada pieza:

- `Subsystem sftp internal-sftp` usa el servidor SFTP **integrado en `sshd`**, que no necesita ficheros ni librerías dentro de la jaula (con `/usr/lib/.../sftp-server` externo habría que replicarlos).
- `Match Group sftpusers` aplica el bloque solo a ese grupo; el resto de usuarios (`deployer`) no cambia.
- `ChrootDirectory /srv/sftp/%u` encierra al usuario: ve `/srv/sftp/proveedor` como si fuera la raíz `/`. `%u` es su nombre de usuario.
- `ForceCommand internal-sftp` ignora lo que pida el cliente: aunque ejecute `ssh proveedor@... bash`, solo obtiene SFTP.
- `AllowTcpForwarding no` y `X11Forwarding no` evitan que use la sesión como túnel.

**Requisito estricto**: la carpeta de la jaula y todas sus carpetas padre deben ser propiedad de `root` y **no escribibles por nadie más**. Si no, `sshd` rechaza la conexión (ver *Errores frecuentes*). Por eso el usuario sube a una subcarpeta (`subidas/`) donde sí tiene permiso de escritura, no a la raíz de la jaula.

Antes de reiniciar, validar con `sudo sshd -t`, y no cerrar la sesión de administración hasta probar desde otra terminal. Las reglas de seguridad generales de `sshd_config` (claves, sin contraseñas, sin `root`) están en [Acceso SSH seguro](../../devops/despliegue-en-vps/Acceso-SSH-Seguro.md).

## Permisos y umask

Un fichero subido por SFTP nace con los permisos que decida el servidor, no el cliente: el programa `sftp-server` aplica la **umask** del proceso, la máscara que *resta* permisos a los nuevos ficheros. Con la umask habitual `022`, un fichero nuevo queda `644` (`rw-r--r--`: legible por todos), como se vio en el `ls -l` de arriba (`-rw-r--r--`).

Para un servidor SFTP con ficheros delicados (facturas, volcados) conviene una umask más cerrada, `027` (`640`, sin acceso para «otros») o `077` (solo el propietario). Con `internal-sftp` se fija con la opción `-u`:

```text
ForceCommand internal-sftp -u 027      # no ejecutado: requiere sshd real
```

Y desde el cliente se puede corregir un fichero concreto con `chmod`:

```text
sftp> chmod 640 catalogo.csv
```

Para escritura en equipo (varios usuarios subiendo a la misma carpeta) se usa un grupo común con el bit *setgid* en la carpeta (`chmod g+s`), de modo que los ficheros nuevos hereden el grupo de la carpeta. Los volúmenes de Docker tienen su propia versión de este problema; ver [Volúmenes y permisos](../../devops/despliegue-en-vps/Volumenes-y-Permisos.md).

## Integridad: comprobar que el fichero llegó entero

Que `put` termine sin error no garantiza que el fichero sea idéntico, sobre todo tras una reanudación o con un proceso que cortó a medias. La comprobación fiable es comparar una **huella SHA-256** del origen y del destino ([qué es un hash criptográfico](../../seguridad/algoritmos-de-hash/Hash-Criptografico.md)):

```bash
sha256sum backup.bin                      # en el equipo de oficina
ssh tienda sha256sum /srv/backups/backup.bin   # en el servidor (no ejecutado)
```

Si las dos líneas muestran el mismo hash, el contenido es idéntico bit a bit. Comprobado tras la reanudación con `reget` de arriba:

```text
dc9faa0a0fd84373e7529b203cdbfd828e21b408fe771f93aef9141668de84ce  remote/backups/backup.bin
dc9faa0a0fd84373e7529b203cdbfd828e21b408fe771f93aef9141668de84ce  dl/backup.bin
```

Para verificar contra una lista guardada, `sha256sum -c`:

```bash
sha256sum backup.bin > backup.bin.sha256     # origen: guarda la huella
sha256sum -c backup.bin.sha256               # destino: compara
```

```text
backup.bin: OK
```

Si la huella cambia, el mensaje es `backup.bin: FAILED`. En Windows sin Git Bash, el equivalente es `Get-FileHash -Algorithm SHA256 backup.bin` en PowerShell.

## Automatización: con claves, nunca con contraseña en el script

Un script que sube cada noche el volcado de la base de datos no puede teclear nada. La solución correcta es una **clave SSH dedicada**, no una contraseña escrita en el script.

❌ **Mal**: contraseña dentro del script (queda en el historial, en el repositorio, en los logs y a la vista de quien lea el fichero):

```text
open sftp://deployer:MiContrasena@203.0.113.10/
```

✅ **Bien**: autenticación por clave privada, sin contraseña en el comando.

Con `sftp` de OpenSSH:

```bash
sftp -b subir.txt -i ~/.ssh/tienda_backup \
     -o BatchMode=yes -o IdentitiesOnly=yes deployer@203.0.113.10   # no ejecutado
```

`BatchMode=yes` impide cualquier pregunta interactiva: si la clave falla, el comando termina con error en vez de quedarse esperando una contraseña. `ssh -G` confirma la configuración efectiva sin conectar (ejecutado; `203.0.113.10` es dirección de documentación):

```text
$ ssh -G -F /dev/null deployer@203.0.113.10 | grep -iE '^(port|user) '
user deployer
port 22
```

Con **WinSCP**, el script (`winscp.com`) usa `-privatekey` en `open`; WinSCP usa claves en formato `.ppk` (PuTTY), que convierte desde las de OpenSSH con PuTTYgen o con el propio WinSCP. Según la documentación del comando `open` (verificada el 2026-11-10; no ejecutado):

```text
open sftp://deployer@203.0.113.10/ -privatekey="C:\claves\tienda_backup.ppk" -hostkey="ssh-ed25519 256 SHA256:..."
put C:\copias\tienda.sql /srv/backups/
exit
```

`-hostkey` fija la huella esperada del servidor: si cambia (servidor suplantado o reinstalado), la conexión falla en vez de aceptar a ciegas. La documentación de WinSCP muestra en sus ejemplos `usuario:contraseña@`; es el patrón que **no** hay que copiar.

Para que la clave del script haga solo eso, se aplica el mismo principio de [Acceso SSH seguro](../../devops/despliegue-en-vps/Acceso-SSH-Seguro.md): una clave por función, restringida con `restrict` y `command=` o con un usuario SFTP enjaulado como el de la sección anterior.

## Errores frecuentes

| Síntoma | Causa habitual |
|---|---|
| `550 Permission denied` (FTP) o `Permission denied` / `remote open("...") : Permission denied` (SFTP) | El usuario no tiene permiso de escritura en esa carpeta (propietario o `umask`), o intenta escribir en la raíz de una jaula chroot, que debe ser de `root` |
| `530 Login incorrect` (FTP) | Usuario o contraseña erróneos, o el servidor no admite login para ese usuario (lista de usuarios denegados, cuenta sin shell válida en FTP clásico) |
| Login correcto en FTP, pero `LIST` se queda colgado o termina en `Connection timed out` | Modo activo bloqueado por NAT o cortafuegos; o modo pasivo donde el servidor anuncia una IP privada o su rango de puertos pasivos no está abierto. Probar el otro modo; en el servidor, abrir el rango pasivo y configurar la IP pública anunciada |
| `Received message too long 1752132705` (SFTP) | Algo escribe texto en la sesión antes del protocolo: típicamente un `echo` o un banner en `~/.bashrc`/`.profile` del usuario remoto. El número es el texto ASCII leído como longitud (`1752132705` = `hola`). Reproducido el 2026-11-10 lanzando `sftp -D "echo hola"` |
| `Received unexpected end-of-file from SFTP server` | El servidor cerró la conexión sin responder al protocolo: usuario con shell `nologin` sin `ForceCommand internal-sftp`, jaula con permisos incorrectos (`bad ownership or modes for chroot directory`), o `Subsystem sftp` ausente o con una ruta que no existe. No se reprodujo (no hay sshd); la causa se ve en el log del servidor |
| `subsystem request failed on channel 0` / `Connection closed` | `sshd_config` sin `Subsystem sftp` válido |
| `Connection refused` | Nada escucha en el puerto: servicio parado o puerto/IP equivocados. Reproducido contra un puerto local cerrado: `curl: (7) Failed to connect to 127.0.0.1 port 6891 ...: Could not connect to server` |
| `Permission denied (publickey)` | La clave no está autorizada para ese usuario; ver [Acceso SSH seguro](../../devops/despliegue-en-vps/Acceso-SSH-Seguro.md) |
| `File "..." not found.` (al hacer `get`) | Ruta remota mal escrita; reproducido con `get nada.txt` |

El diagnóstico del lado SFTP pasa siempre por el log de `sshd`:

```bash
sudo journalctl -u ssh -n 50 --no-pager     # no ejecutado: requiere servidor real
```

Y por el modo verboso del cliente, `sftp -vvv ...`, que muestra la negociación SSH completa.

## Buenas prácticas avanzadas

- **FTP plano no sale nunca de la red local, y si hay que usarlo, entra por una VPN.** La contraseña viaja a la vista (la demostración de arriba la muestra en tres líneas). Si un tercero solo ofrece FTP, preferir FTPS explícito exigido (`--ssl-reqd` en `curl`, «requerir FTP sobre TLS explícito» en FileZilla/WinSCP) en lugar de un cliente que «intenta» TLS y vuelve a texto plano sin avisar.
- **Cada tercero, su usuario SFTP enjaulado y sin shell.** Con `Match Group`, `ChrootDirectory`, `ForceCommand internal-sftp` y `AllowTcpForwarding no`, un proveedor que sube ficheros no puede ejecutar nada ni ver nada más. Un usuario con shell normal que solo «se usa para SFTP» no está restringido: lo está solo por costumbre.
- **Un usuario enjaulado necesita una jaula propiedad de `root` y una subcarpeta propia donde escribir.** El fallo clásico es dar permisos de escritura al propietario de la raíz de la jaula: `sshd` lo rechaza con `bad ownership or modes for chroot directory component`, y desde el cliente solo se ve el críptico `Connection closed`. Todos los componentes de la ruta, desde `/`, deben ser de `root` y no escribibles por otros.
- **Verifica los ficheros críticos con SHA-256 y, en scripts, falla en voz alta.** Subir una copia de seguridad corrupta y enterarse al restaurar es el peor momento para descubrirlo. Guardar el `.sha256` junto al fichero y comprobarlo tras cada transferencia (o tras cada `reget`/`rsync --partial`) lo evita.
- **En automatización, una clave por tarea, `BatchMode=yes` y huella del servidor fijada.** Sin `BatchMode`, un fallo de autenticación deja el script colgado esperando una contraseña; sin huella fijada (`-hostkey` en WinSCP, `known_hosts` en OpenSSH), el script acepta a cualquier servidor que responda.
- **Cierra lo que no se usa en el cortafuegos.** El puerto 21 y el rango pasivo no deben estar abiertos si el servicio FTP no existe. Para SFTP basta el 22, que ya debe estar protegido: ver [UFW](../../devops/despliegue-en-vps/UFW.md) y [Fail2ban](../../devops/despliegue-en-vps/Fail2ban.md).

## Documentación oficial

- [man sftp (OpenBSD)](https://man.openbsd.org/sftp) — referencia del cliente `sftp`: todos los comandos interactivos (`reget`, `reput`, `-b`, `-D`) y sus opciones.
- [man sshd_config (OpenBSD)](https://man.openbsd.org/sshd_config) — para `ChrootDirectory`, `ForceCommand`, `Match` y `Subsystem`; leer `ChrootDirectory` para los requisitos exactos de permisos.
- [RFC 959: FTP](https://www.rfc-editor.org/rfc/rfc959) — la especificación original: modos activo y pasivo, códigos de respuesta.
- [RFC 4217: Securing FTP with TLS](https://www.rfc-editor.org/rfc/rfc4217) — cómo funciona `AUTH TLS` en FTPS explícito.

## Recursos didácticos

- [Documentación de scripting de WinSCP](https://winscp.net/eng/docs/scripting) — cómo automatizar subidas con `winscp.com`, `-hostkey` y `synchronize`; útil para ver el patrón completo de un script con clave.
- [Manual de curl](https://curl.se/docs/manpage.html) — las opciones `--ftp-pasv`, `--ssl-reqd`, `--disable-epsv` y `--ftp-create-dirs` sirven para probar un servidor FTP/FTPS desde la línea de comandos.

---

*En resumen: FTP clásico viaja en claro y con dos conexiones que rompen NAT y cortafuegos, así que SFTP —un protocolo distinto dentro de SSH, con un solo puerto y claves— es la opción por defecto, enjaulando a cada tercero en su carpeta.*
