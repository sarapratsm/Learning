# Red local e IP

## ¿Qué es?

Una **red local** (LAN) es el conjunto de equipos conectados entre sí en un mismo sitio —una oficina, una casa— que se hablan directamente. Una **dirección IP** es el identificador de cada equipo en la red, y un **puerto** es el número que dice a qué servicio de ese equipo va dirigido el tráfico.

## ¿Por qué existe?

Para que dos equipos intercambien datos, cada uno necesita una forma de localizar al otro y de saber qué programa debe recibir lo que llega. La IP resuelve lo primero y el puerto lo segundo. Casi todo lo que se explica en esta colección (escritorio remoto, carpetas compartidas, SSH, VPN) se reduce a la misma frase: «conéctate al equipo que está en **esta IP**, por **este puerto**».

> Si ya conoces las URL, la IP es el host y el puerto es el `:8080` del final. `http://192.168.1.50:8080/` significa «el equipo `192.168.1.50`, el servicio que escucha en el puerto 8080». El nombre de dominio (`tienda.ejemplo.com`) es solo una forma legible de escribir una IP.

La analogía clásica sigue valiendo: la IP es la dirección de un edificio y el puerto es el número de apartamento. La IP lleva al equipo correcto; el puerto, al servicio correcto dentro de él.

## ¿Cuándo y para qué se usa?

Aparece siempre que dos máquinas se conectan: entrar por SSH a un servidor, abrir el escritorio de un equipo de la oficina, montar una carpeta del NAS, o decidir qué puertos deja abiertos un firewall. En todos esos casos lo primero es saber qué IP tiene el destino, si está en tu misma red o en otra, y qué puerto usa el servicio.

Los ejemplos usan un escenario común: una tienda online con un servidor en un VPS (`203.0.113.10`, dominio `tienda.ejemplo.com`) y una oficina con red local `192.168.1.0/24`, un equipo de trabajo (`192.168.1.20`), un NAS (`192.168.1.50`) y un router (`192.168.1.1`). Las direcciones son de documentación: las públicas pertenecen a los bloques reservados para ejemplos y las locales a rangos privados. Las salidas de comandos son de Windows 11, observadas el 2026-11-10; las direcciones reales de la máquina de pruebas se han sustituido por las del escenario.

---

## Direcciones IP: privadas y públicas

Una dirección IPv4 son 32 bits que se escriben como cuatro números de 0 a 255 separados por puntos (`192.168.1.20`). Cada número son 8 bits, un **octeto**.

No todas las direcciones son alcanzables desde internet. Hay rangos reservados para uso interno, definidos en el RFC 1918, que cualquier red puede reutilizar porque los routers de internet no los enrutan:

| Rango privado (RFC 1918) | Notación CIDR | Direcciones | Uso típico |
|---|---|---|---|
| `10.0.0.0` – `10.255.255.255` | `10.0.0.0/8` | 16 777 216 | Redes corporativas grandes, VPN |
| `172.16.0.0` – `172.31.255.255` | `172.16.0.0/12` | 1 048 576 | Redes medianas, Docker |
| `192.168.0.0` – `192.168.255.255` | `192.168.0.0/16` | 65 536 | Casa y oficina pequeña |

Dos detalles que hacen tropezar: el rango de `172` es privado solo entre `172.16` y `172.31` (`172.32.0.1` es una IP pública, comprobado con `ipaddress.is_private` de Python), y no es el único rango reservado. Otros que conviene reconocer:

| Rango | Qué es |
|---|---|
| `127.0.0.0/8` | Loopback: el propio equipo (véase más abajo) |
| `169.254.0.0/16` | Autoasignada (*link-local*): el equipo no encontró servidor DHCP y se puso una IP a sí mismo. Si la ves, algo falla |
| `100.64.0.0/10` | Espacio de operador (RFC 6598), usado cuando el proveedor comparte una IP pública entre muchos clientes |

Una **IP pública** es la que se ve desde internet y la asigna el proveedor. Un servidor como el VPS de la tienda tiene una IP pública propia; una oficina suele tener una sola IP pública, la del router, compartida por todos sus equipos (se explica en la sección de NAT).

### Direcciones de documentación (RFC 5737)

Para escribir ejemplos sin señalar a nadie, el RFC 5737 reserva tres bloques públicos que nunca se asignan a nadie:

| Bloque | Uso en esta colección |
|---|---|
| `192.0.2.0/24` | Reserva para ejemplos sueltos |
| `198.51.100.0/24` | IP pública de la oficina (`198.51.100.25`) |
| `203.0.113.0/24` | Servidor VPS (`203.0.113.10`) |

Si en una documentación aparece una IP que no pertenece a estos bloques ni a los privados, probablemente sea real.

## Máscara de subred y notación CIDR

Una IP sola no dice qué equipos están en tu misma red. Eso lo dice la **máscara de subred**: marca qué parte de la dirección identifica la red y qué parte identifica al equipo dentro de ella.

La **notación CIDR** (RFC 4632) escribe la máscara como un número tras una barra: `/24` significa «los primeros 24 bits son la parte de red». La máscara equivalente se escribe con 24 unos seguidos de 8 ceros:

```text
/24 = 11111111.11111111.11111111.00000000 = 255.255.255.0
```

Una **subred** es el grupo de direcciones que comparten la misma parte de red. Dos equipos están en la misma subred si, al aplicar la máscara, obtienen la misma dirección de red; solo entonces se hablan directamente, sin pasar por un router.

### Cálculo a mano de una /24

Con `192.168.1.20/24`:

1. Quedan 32 − 24 = 8 bits para equipos: 2⁸ = 256 direcciones.
2. La **dirección de red** es la primera, con todos los bits de equipo a 0: `192.168.1.0`.
3. La **dirección de difusión** (*broadcast*) es la última, con todos a 1: `192.168.1.255`. Llega a todos los equipos de la subred.
4. Ambas están reservadas, así que los equipos usables son 256 − 2 = **254**, de `192.168.1.1` a `192.168.1.254`.

### Cálculo a mano de una /28

Una /28 es una subred pequeña: 32 − 28 = 4 bits de equipo, 2⁴ = 16 direcciones, 14 usables. La máscara tiene 28 unos: los tres primeros octetos son `255` y el cuarto lleva 4 unos y 4 ceros, `11110000` = 128 + 64 + 32 + 16 = 240. Es decir, `255.255.255.240`.

Como cada subred ocupa 16 direcciones, el último octeto se parte en bloques de 16: `0–15`, `16–31`, `32–47`, `48–63`... Para `192.168.1.50/28`, se busca el bloque que contiene el 50 (el múltiplo de 16 más cercano por debajo es 48):

| Dato | Valor |
|---|---|
| Dirección de red | `192.168.1.48` |
| Primer equipo usable | `192.168.1.49` |
| Último equipo usable | `192.168.1.62` |
| Difusión | `192.168.1.63` |
| Máscara | `255.255.255.240` |

Los cálculos de los dos apartados coinciden con los que devuelve el módulo `ipaddress` de Python, ejecutado el 2026-11-10 como comprobación.

### Por qué importa: la misma red con dos máscaras

Con `/24`, el equipo de la oficina (`192.168.1.20`) y el NAS (`192.168.1.50`) están en la misma subred `192.168.1.0/24` y se ven directamente. Si una de las dos máquinas tuviera por error máscara `/28`, el equipo `192.168.1.20` caería en el bloque `192.168.1.16/28` (usables `.17`–`.30`) y el NAS `192.168.1.50` en el `192.168.1.48/28`. Para el equipo con `/28`, el NAS ya no está en su red: intentará llegar a él a través de la puerta de enlace y, normalmente, no lo conseguirá. Es una de las averías más desconcertantes, porque ambos equipos tienen IPs «parecidas» y pueden hacer ping a otros.

| Dirección | Con /24 | Con /28 |
|---|---|---|
| `192.168.1.20` | red `192.168.1.0` | red `192.168.1.16` |
| `192.168.1.50` | red `192.168.1.0` | red `192.168.1.48` |
| ¿Misma red? | Sí | No |

## Puerta de enlace y tabla de rutas

La **puerta de enlace** (*gateway*) es el equipo de tu subred que sabe sacar el tráfico hacia otras redes; en una oficina, el router (`192.168.1.1`). Cuando un equipo quiere hablar con una IP, decide con la máscara:

- Si el destino está en su misma subred, envía directamente.
- Si no, entrega el paquete a la puerta de enlace y esta se ocupa del resto.

Esa decisión vive en la **tabla de rutas**: una lista de «para este destino, sal por aquí». La ruta `0.0.0.0/0` se llama **ruta por defecto** y significa «cualquier otro destino».

## Mirar tu configuración: IP y rutas

Los comandos de lectura no cambian nada. En Windows, para ver la IP, la máscara y la puerta de enlace:

```bash
ipconfig
```

```text
Adaptador de Ethernet Ethernet:

   Dirección IPv4. . . . . . . . . . . . . . : 192.168.1.20
   Máscara de subred . . . . . . . . . . . . : 255.255.255.0
   Puerta de enlace predeterminada . . . . . : 192.168.1.1
```

Salida abreviada y con las direcciones sustituidas por las del escenario. El equivalente en Linux es `ip addr` (direcciones) e `ip route` (rutas); no se ha ejecutado en esta ocasión.

Para ver la tabla de rutas IPv4:

```bash
route print -4
```

```text
IPv4 Tabla de enrutamiento
===========================================================================
Rutas activas:
Destino de red        Máscara de red   Puerta de enlace   Interfaz  Métrica
          0.0.0.0          0.0.0.0      192.168.1.1     192.168.1.20    291
        127.0.0.0        255.0.0.0      En vínculo         127.0.0.1    331
      192.168.1.0    255.255.255.0      En vínculo      192.168.1.20    291
     192.168.1.20  255.255.255.255      En vínculo      192.168.1.20    291
    192.168.1.255  255.255.255.255      En vínculo      192.168.1.20    291
        224.0.0.0        240.0.0.0      En vínculo         127.0.0.1    331
```

Salida abreviada (se han quitado las rutas de las interfaces virtuales) y con direcciones sustituidas. Se lee así:

- `0.0.0.0` con máscara `0.0.0.0`: la ruta por defecto. Todo lo que no case con otra fila sale por `192.168.1.1`.
- `192.168.1.0/24` «En vínculo» (*on-link*): esa subred está directamente conectada; no hace falta puerta de enlace.
- `192.168.1.255/32`: la dirección de difusión de la subred.
- `127.0.0.0/8`: el loopback.
- La **métrica** desempata: entre dos rutas que casan, gana la de métrica menor.

Para ver los equipos con los que se ha hablado hace poco en la subred y su dirección física (MAC):

```bash
arp -a
```

```text
Interfaz: 192.168.1.20 --- 0x5
  Dirección de Internet          Dirección física      Tipo
  192.168.1.1           00-00-5e-00-53-01     dinámico
  192.168.1.50          00-00-5e-00-53-32     dinámico
```

Salida ilustrativa, no capturada: las direcciones son las del ejemplo y las físicas, del rango de documentación de MAC (el formato es el que imprime `arp -a` en Windows). La tabla ARP asocia cada IP de tu subred con la MAC que responde por ella; solo contiene vecinos de tu misma subred, nunca equipos remotos.

## DHCP o IP fija

Un equipo obtiene su IP de dos maneras:

- **DHCP** (*Dynamic Host Configuration Protocol*, RFC 2131): al conectarse, el equipo pide configuración a un servidor DHCP —normalmente el router— y recibe IP, máscara, puerta de enlace y servidor DNS, con una **concesión** (*lease*) de duración limitada. Cuando caduca, se renueva y puede cambiar la IP.
- **IP fija (estática)**: la configuras a mano en el equipo, que la usa siempre.

En `ipconfig /all` el campo `DHCP habilitado` dice cuál de las dos usa cada adaptador (en la máquina de pruebas aparecían ambos casos según el adaptador).

| Situación | Qué conviene |
|---|---|
| Portátiles, móviles, equipos de invitados | DHCP |
| NAS, impresora, servidor interno que otros buscan por IP | IP fija o reserva DHCP |
| Equipo al que apunta una redirección de puertos | IP fija o reserva DHCP: si cambia, la redirección apunta a otro equipo |

La opción más sensata para equipos que necesitan IP estable es la **reserva DHCP**: en el router se asocia la MAC del equipo a una IP concreta, y el equipo sigue usando DHCP pero siempre recibe la misma. La asignación vive en un único sitio. Si en lugar de eso configuras la IP a mano en el equipo, el servidor DHCP no se entera y puede ofrecer esa misma dirección a otro.

## NAT: cómo comparte internet toda una red

Las IPs privadas no son alcanzables desde internet, pero los equipos de la oficina navegan igualmente. Lo permite el **NAT** (*Network Address Translation*, RFC 3022), que hace el router: sustituye la IP privada de origen por su propia IP pública y recuerda la correspondencia para devolver la respuesta al equipo correcto.

Un ejemplo con la oficina de la tienda (router con IP pública `198.51.100.25`) conectando por SSH al VPS:

```text
Salida del equipo:         192.168.1.20:51514  →  203.0.113.10:22
El router traduce a:       198.51.100.25:40001 →  203.0.113.10:22
Respuesta del VPS:         203.0.113.10:22     →  198.51.100.25:40001
El router devuelve a:      203.0.113.10:22     →  192.168.1.20:51514
```

Esta traducción de puertos (a veces llamada PAT) es lo que permite que decenas de equipos compartan una IP pública: el router distingue cada conversación por el puerto de origen.

La consecuencia importante es que NAT solo permite que la conexión **empiece desde dentro**. Para el VPS, la oficina es simplemente `198.51.100.25`; no sabe que existe `192.168.1.20`. Si alguien en internet intenta conectar con `198.51.100.25:3389`, el router no tiene ninguna entrada de traducción y descarta el tráfico. Eso es un efecto lateral útil (los equipos internos no son alcanzables desde fuera), pero **no es un firewall**: no lo diseñaron para proteger.

Para que algo desde fuera llegue a un equipo interno hace falta una regla explícita en el router (véase [Redirección de puertos](Redireccion-de-Puertos.md)) o una VPN (véase [VPN](VPN.md)).

## Puertos y sockets

Un equipo con una sola IP ofrece muchos servicios a la vez. El **puerto** es un número de 16 bits (0 a 65 535) que identifica a cuál va dirigido el tráfico. Cada conexión usa además un protocolo de transporte: **TCP** (orientado a conexión, con entrega garantizada: SSH, HTTP) o **UDP** (sin conexión, más ligero: DNS, WireGuard). El puerto 53 de TCP y el 53 de UDP son cosas distintas.

Los puertos asignados a servicios conocidos los mantiene la IANA, y los más habituales en esta colección son:

| Puerto | Protocolo | Servicio |
|---|---|---|
| 22 | TCP | SSH y SFTP |
| 21 | TCP | FTP |
| 53 | UDP y TCP | DNS |
| 80 | TCP | HTTP |
| 443 | TCP | HTTPS |
| 445 | TCP | Carpetas compartidas (SMB) |
| 3389 | TCP | Escritorio Remoto (RDP) |
| 51820 | UDP | WireGuard (el valor por defecto en su documentación, configurable) |

Un servicio **escucha** (*listen*) en un puerto; quien se conecta es el cliente, que usa un puerto de origen aleatorio (`51514` en el ejemplo de NAT). Un **socket** es cada extremo de una conexión: la combinación de protocolo, IP y puerto. Una conexión se identifica por el par de sockets: `192.168.1.20:51514 ↔ 203.0.113.10:22`.

### Un servicio escuchando, visto en `netstat`

Para ver un puerto en escucha sin tocar nada del sistema, un script de Python abre un socket en `127.0.0.1`, puerto `6801`, y se queda esperando (`nc -l` hace lo mismo donde esté instalado; en la máquina de pruebas no lo estaba, y por eso se usó Python):

```python
import socket, time

s = socket.socket()
s.bind(("127.0.0.1", 6801))   # IP y puerto en los que escuchar
s.listen()
print("escuchando", flush=True)
time.sleep(120)
```

Con el script en marcha, `netstat -ano` lista los sockets del equipo con el **PID** del proceso (`-a` todos, `-n` números en lugar de nombres, `-o` PID):

```bash
netstat -ano -p TCP
```

```text
  Proto  Dirección local          Dirección remota        Estado           PID
  TCP    127.0.0.1:6801         0.0.0.0:0              LISTENING       19544
```

Se leen cuatro datos: el protocolo, la dirección local (`127.0.0.1:6801`: IP y puerto en los que escucha), el estado `LISTENING` y el PID del proceso que lo tiene abierto. Para identificar el programa: `tasklist /FI "PID eq 19544"` en Windows, o `ss -tulpn` en Linux (no ejecutado).

Un cliente puede comprobar que el puerto responde sin escribir código. En PowerShell:

```powershell
Test-NetConnection 127.0.0.1 -Port 6801
```

```text
ComputerName     : 127.0.0.1
RemotePort       : 6801
TcpTestSucceeded : True
```

Contra un puerto en el que nadie escucha (`6809`), `TcpTestSucceeded` vale `False` y `curl http://127.0.0.1:6809` termina con el código de salida 7 (*Failed to connect*). Esta comprobación contra el puerto es más fiable que `ping`: muchos firewalls descartan el ping pero dejan pasar los servicios.

### A qué IP se ata un servicio

La IP con la que se hace `bind` decide quién puede conectar:

| Escucha en | Quién llega |
|---|---|
| `127.0.0.1` | Solo el propio equipo |
| `192.168.1.20` | Equipos que alcancen esa IP concreta (la red local) |
| `0.0.0.0` | Todas las interfaces del equipo, incluida cualquier IP pública que tenga |

Es la diferencia entre una base de datos accesible solo por la aplicación de la misma máquina y otra visible para toda la red. En un servidor con IP pública, `0.0.0.0` más un firewall abierto significa «expuesto a internet»; véase [UFW](../../devops/despliegue-en-vps/UFW.md). El caso `0.0.0.0` no se ha ejecutado: abrirlo en la máquina de pruebas habría expuesto un puerto a la red.

## Loopback: hablar con uno mismo

La dirección `127.0.0.1` (y todo el bloque `127.0.0.0/8`) es el **loopback**: tráfico que no sale del equipo, ni siquiera llega a la tarjeta de red. El nombre `localhost` apunta a ella. Es el destino para probar un servicio local («¿arranca mi API en el puerto 6801?») y la dirección segura para servicios que solo debe usar la propia máquina. En la tabla de rutas aparece como `127.0.0.0 255.0.0.0 En vínculo`.

## DNS: de nombres a direcciones

Las personas recordamos nombres; las redes necesitan IPs. El **DNS** (*Domain Name System*, RFC 1034) es el sistema que traduce `tienda.ejemplo.com` en `203.0.113.10`. Funciona como una agenda distribuida: tu equipo pregunta a un **servidor DNS** (el que le dio el DHCP, normalmente el router, que a su vez pregunta a otro) y recibe la IP asociada a ese nombre. La respuesta se guarda en caché durante un tiempo (el TTL) para no repetir la consulta.

`nslookup` consulta el DNS directamente. Contra el dominio que la IANA reserva para documentación, `example.com`:

```bash
nslookup example.com
```

```text
Respuesta no autoritativa:
Servidor:  UnKnown
Address:  192.168.1.1

Nombre:  example.com
Addresses:  2606:4700:10::ac42:93f3
	  2606:4700:10::6814:179a
	  172.66.147.243
	  104.20.23.154
```

Observado el 2026-11-10; la dirección del servidor DNS se ha sustituido por la del router del escenario. Se lee así:

- `Servidor: UnKnown`: `nslookup` intentó resolver el nombre de su propio servidor DNS y no existe registro inverso para él. Es habitual y no indica un fallo.
- `Respuesta no autoritativa`: la respuesta viene de una caché, no del servidor que es dueño del dominio.
- Hay varias direcciones: las dos primeras son IPv6 (registros `AAAA`) y las dos últimas IPv4 (registros `A`). Un nombre puede apuntar a varias IPs; las de `example.com` pertenecen a un proveedor de CDN y pueden cambiar con el tiempo.

Para pedir solo IPv4: `nslookup -type=A example.com`. Para el mismo nombre contra otro servidor DNS (útil cuando sospechas del que usas): `nslookup example.com 192.168.1.1`, donde el último argumento es el servidor a consultar.

La resolución de nombres tiene otra capa local, el fichero `hosts` (`C:\Windows\System32\drivers\etc\hosts` en Windows, `/etc/hosts` en Linux), que se consulta antes que el DNS. Para nombres de equipos internos (`nas-oficina` en lugar de `192.168.1.50`) hay también DNS interno, tratado en [DNS interno con dnsmasq](../../devops/despliegue-en-vps/DNS-Interno-con-dnsmasq.md).

## Errores frecuentes

### Puerto en uso al abrir un segundo listener

Dos procesos no pueden escuchar en la misma IP y puerto a la vez. Con el script anterior ya en marcha, lanzar una segunda copia en el mismo puerto falla:

```text
OSError(10048, 'Solo se permite un uso de cada dirección de socket (protocolo/dirección de red/puerto)', None, 10048, None)
```

Código `10048` en Windows (`WSAEADDRINUSE`); en Linux el equivalente es `OSError: [Errno 98] Address already in use` (no ejecutado). En frameworks web suele verse como `EADDRINUSE` o «address already in use». La solución es localizar quién lo ocupa con `netstat -ano | findstr :6801` (o `ss -tulpn`), y decidir si se cierra ese proceso o se cambia de puerto. Con el script cerrado, el puerto queda libre.

### IP duplicada

Dos equipos con la misma IP provocan fallos intermitentes: conexiones que se cortan, sesiones que «saltan» a otro equipo, o aviso de «conflicto de direcciones IP» en Windows. El causante típico es una IP fija configurada a mano dentro del rango que reparte el DHCP, de modo que el router la entrega a otro equipo. Se arregla sacando la IP fija del rango DHCP, o mejor, sustituyéndola por una reserva DHCP.

### Subred distinta

Dos equipos físicamente en la misma red no se ven porque sus máscaras o rangos no coinciden: uno en `192.168.1.0/24` y otro en `192.168.0.0/24`, o la máscara `/28` del ejemplo anterior. El síntoma es que el equipo ve internet pero no sus vecinos (o al revés). Se diagnostica con `ipconfig` en ambos lados: comparar IP, máscara y puerta de enlace, y aplicar el cálculo de red a mano.

### Todo parece bien pero no hay conexión

| Síntoma | Causa probable | Qué comprobar |
|---|---|---|
| `ping` a la IP funciona, pero el nombre no resuelve | DNS | `nslookup nombre`; probar con otro servidor DNS |
| `ping` al router funciona, a una IP de internet no | Puerta de enlace o ruta por defecto | `route print`, buscar `0.0.0.0` |
| `ping` falla, pero el servicio responde | El equipo descarta el ping (firewall) | `Test-NetConnection IP -Port N` |
| IP `169.254.x.x` | No hay respuesta de DHCP | Cable, router, servidor DHCP |
| `Test-NetConnection` falla solo en un puerto | Servicio parado o firewall en ese puerto | `netstat -ano` en el destino |

## Buenas prácticas avanzadas

- **Reserva las IPs en el router, no a mano en el equipo.** Una reserva DHCP asocia la MAC a una IP y la asignación vive en un único sitio. Con IPs fijas puestas a mano, el DHCP no sabe que existen y el conflicto es cuestión de tiempo.
- **Planifica el rango de red antes de que haya que unirlo con otro.** Una VPN entre la oficina `192.168.1.0/24` y casa falla si casa también usa `192.168.1.0/24`: las rutas se solapan y no hay forma de distinguir los destinos. Usar rangos menos comunes (`10.x.x.x` o `192.168.x.x` con `x` inusual) evita rehacer la red cuando llegue la VPN.
- **Comprueba el puerto, no el ping.** Un `ping` sin respuesta no prueba que el equipo esté caído, y uno con respuesta no prueba que el servicio funcione. `Test-NetConnection IP -Port N` (o `nc -zv IP N` en Linux) prueba exactamente lo que importa: que alguien escucha ahí.
- **Distingue «escucha» de «es alcanzable».** `netstat -ano` muestra qué puertos tiene abiertos un equipo; no dice si el firewall los deja pasar. Y a la inversa: un firewall abierto sobre un puerto en el que nadie escucha no expone nada. Revisa ambas listas.
- **Átate a `127.0.0.1` todo lo que no necesite red.** Bases de datos, paneles de administración y servicios de desarrollo que solo usa la propia máquina deben escuchar en loopback; `0.0.0.0` es la excepción que se justifica, no el valor por defecto que se acepta sin mirar.
- **No tomes NAT por un firewall.** Que un equipo no sea alcanzable desde fuera por estar tras NAT es un efecto de cómo se traduce el tráfico, no una política de seguridad. Un puerto redirigido en el router queda expuesto a todo internet tal cual, y un dispositivo comprometido dentro de la red puede iniciar conexiones hacia fuera sin que NAT lo impida.

## Documentación oficial

- [RFC 1918 — Address Allocation for Private Internets](https://www.rfc-editor.org/rfc/rfc1918) — la definición de los tres rangos privados; cuando dudes de si una IP es privada.
- [RFC 5737 — IPv4 Address Blocks Reserved for Documentation](https://www.rfc-editor.org/rfc/rfc5737) — los tres bloques de documentación que se usan en todos los ejemplos.
- [Registro de puertos de la IANA](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml) — la lista oficial de qué servicio corresponde a cada puerto.
- [Referencia de `netstat` en Microsoft Learn](https://learn.microsoft.com/es-es/windows-server/administration/windows-commands/netstat) — todas las opciones del comando en Windows, incluidos los estados de conexión.

---

*En resumen: la IP localiza al equipo, la máscara dice quién está en tu red, el puerto elige el servicio y el DNS pone nombre a todo ello; NAT es lo que oculta una red entera tras una sola IP pública.*
