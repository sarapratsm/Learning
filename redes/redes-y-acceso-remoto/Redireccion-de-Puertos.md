# Redirección de Puertos (Port Forwarding)

## ¿Qué es?

La **redirección de puertos** es una regla del router que dice: «lo que llegue desde internet al puerto X de mi IP pública, mándalo al puerto Y del equipo Z de la red local». Es la forma de hacer visible desde fuera un servicio que vive dentro, ya sea un servidor, una cámara o un [NAS](NAS.md).

## ¿Por qué existe?

Los equipos de una red local usan direcciones privadas (`192.168.1.0/24`, ver [Red local e IP](Red-local-e-IP.md)) que no se enrutan por internet. Todos salen al exterior compartiendo la única IP pública del router, gracias a **NAT** (*Network Address Translation*): el router reescribe cada paquete saliente con su IP pública y apunta en una tabla qué equipo lo originó, para devolverle la respuesta.

Ese mecanismo funciona solo en un sentido. Cuando alguien de fuera envía un paquete a la IP pública, el router no tiene ninguna entrada en su tabla (nadie de dentro había iniciado esa conversación) y lo descarta. De ahí que un equipo de la LAN no sea alcanzable desde internet, y de ahí también que NAT, sin pretenderlo, actúe como un cortafuegos básico.

La redirección de puertos añade a mano esa entrada que falta, de forma permanente.

> Imagina un edificio con una sola dirección postal (la IP pública) y muchos apartamentos (los equipos). El conserje (el router) reparte lo que los vecinos piden por correo, pero un paquete que nadie ha pedido lo devuelve. La redirección de puertos es una nota fija en la conserjería: «los paquetes del buzón 8080 son para el apartamento 192.168.1.20».

## ¿Cuándo y para qué se usa?

- **Publicar un servicio propio**: el panel interno de pedidos de una tienda online, alojado en el equipo de oficina `192.168.1.20`, accesible para quien trabaja desde casa.
- **Acceder a la red de la oficina desde fuera**: llegar a un NAS o a una cámara cuando no se está.
- **Servicios que necesitan conexiones entrantes**: servidores de juegos, o aplicaciones que no pueden pasar por un intermediario como las [herramientas de control remoto](Herramientas-de-Control-Remoto.md).

Es también la opción que más riesgo introduce de las que resuelven este problema. La sección de alternativas explica cuándo es mejor no usarla.

---

## La regla: qué se configura

El ejemplo que seguirá toda la guía: la oficina de la tienda tiene un router con IP pública `198.51.100.7` (dirección de documentación) y un equipo interno, `192.168.1.20`, que sirve un panel web en el puerto 80. Se quiere llegar a él desde fuera.

La regla, tal como aparece en el panel de casi cualquier router (el nombre varía: *Port Forwarding*, *Virtual Server*, *NAT*, *Redirección de puertos*):

| Protocolo | Puerto externo | IP interna | Puerto interno |
|---|---|---|---|
| TCP | 8080 | 192.168.1.20 | 80 |

Lectura: «lo que llegue por TCP a `198.51.100.7:8080` se entrega a `192.168.1.20:80`».

- **Protocolo**: TCP, UDP o ambos. Un servicio web usa TCP; WireGuard, UDP. Abrir el protocolo equivocado es una causa clásica de «la regla está bien y no funciona».
- **Puerto externo**: el que ve internet. No tiene por qué coincidir con el interno: aquí el 8080 oculta que el servicio real escucha en el 80.
- **IP interna**: el equipo destino. Debe ser una IP que no cambie (siguiente sección).
- **Puerto interno**: donde escucha de verdad el servicio en ese equipo.

Quien quiera llegar al panel desde fuera usa la IP pública y el puerto externo:

```bash
curl http://198.51.100.7:8080/
```

El router recibe el paquete, aplica la regla, reescribe el destino a `192.168.1.20:80` y lo reenvía. La respuesta vuelve por el mismo camino con el origen reescrito.

## El destino necesita una IP que no cambie

La regla apunta a una IP, no a un equipo. Si el router vuelve a repartir las direcciones por DHCP y el equipo recibe otra (`192.168.1.23`, por ejemplo), la regla sigue apuntando a `192.168.1.20`, que ahora es otro dispositivo o ninguno. El servicio deja de responder sin ningún error visible.

Hay dos formas de evitarlo:

| Opción | Cómo se hace | Cuándo conviene |
|---|---|---|
| **Reserva DHCP** | En el router, se asocia la MAC del equipo a una IP concreta; el equipo sigue pidiendo IP por DHCP y siempre recibe la misma | Casi siempre: se gestiona en un solo sitio y no se puede producir un conflicto |
| **IP estática en el equipo** | En la configuración de red del propio equipo se escribe la IP a mano | Equipos sin DHCP o servidores con configuración declarativa; hay que elegir una IP fuera del rango que reparte el router para que no choque |

Con la reserva DHCP, la regla y la IP viven en el mismo panel, y es más difícil que se desincronicen.

## Qué se expone realmente

Abrir el puerto 8080 no expone «el equipo»: expone **un servicio concreto, a todo internet**. Desde ese momento, cualquiera puede intentar conectar, y los escáneres automáticos recorren continuamente el rango completo de IPs públicas buscando puertos abiertos. Un servicio recién publicado recibe sondeos en cuestión de minutos.

Lo que protege el servicio es **solo el propio servicio**: su autenticación, su cifrado, sus actualizaciones. La redirección no añade nada de eso.

Los contrastes más habituales:

```text
❌ Regla                                     Por qué es mala idea
TCP 3389 → 192.168.1.20:3389                 Escritorio Remoto expuesto: objetivo constante de fuerza bruta
TCP 445  → 192.168.1.50:445                  SMB (carpetas compartidas) expuesto a internet
TCP 80   → 192.168.1.50:5000                 Panel de administración del NAS sin HTTPS

✅ Regla                                     Por qué es razonable
UDP 51820 → 192.168.1.20:51820               Puerto de una VPN, diseñado para estar en la frontera
TCP 443  → 192.168.1.20:443                  Web con HTTPS, actualizada y con autenticación
```

Reducir lo que se expone, de mayor a menor efecto:

1. **Exponer solo un servicio diseñado para estar en internet**, y preferiblemente solo una [VPN](VPN.md). Ver la sección de alternativas.
2. **Limitar el origen** cuando se conoce: algunos routers permiten restringir la regla a una IP o rango de origen. Si quien se conecta tiene IP fija (una oficina), la regla puede aceptar solo esa. Con IP dinámica no es viable.
3. **Aplicar también el firewall del destino**: el equipo interno debería aceptar el puerto solo desde donde corresponda. En un servidor Linux, [UFW](../../devops/despliegue-en-vps/UFW.md) lo permite por origen.
4. **Vigilar los intentos fallidos**: una herramienta como [Fail2ban](../../devops/despliegue-en-vps/Fail2ban.md) lee los registros del servicio y bloquea temporalmente las IPs que fallan la autenticación varias veces. Conceptualmente, convierte un ataque de fuerza bruta en uno inviable.
5. **Mantener el servicio actualizado**: un servicio expuesto es el primero en sufrir cuando se publica una vulnerabilidad.

Cambiar el puerto por uno no estándar (el 22222 en vez del 22, por ejemplo) **no es una medida de seguridad**. Los escáneres recorren los 65 535 puertos, no solo los conocidos, y detectan el servicio por su respuesta. Sí reduce el ruido en los registros, y por eso a veces se hace, pero no debe sustituir a ninguna de las medidas anteriores.

## Cuándo no usarla: alternativas más seguras

La redirección de puertos publica un servicio **hacia dentro**: el router espera conexiones entrantes de desconocidos. Las alternativas invierten ese planteamiento.

| Alternativa | Cómo funciona | Cuándo elegirla |
|---|---|---|
| **VPN** ([VPN](VPN.md), [WireGuard](../../devops/despliegue-en-vps/WireGuard.md)) | Se abre un único puerto UDP, y solo quien tenga clave puede entrar; dentro del túnel se accede a todo como si se estuviera en la LAN | Acceso personal o de equipo a varios servicios internos. Es la opción recomendada |
| **Túnel inverso** (SSH `-R`, o servicios como Cloudflare Tunnel y ngrok) | El equipo interno inicia una conexión **saliente** hacia un intermediario; el intermediario recibe las peticiones de internet y las devuelve por ese túnel ya abierto | Cuando no se puede abrir puertos: CGNAT, router ajeno, red corporativa. No requiere regla en el router |
| **Servicio de control remoto** ([TeamViewer, AnyDesk...](Herramientas-de-Control-Remoto.md)) | El intermediario hace de punto de encuentro | Soporte puntual sobre una pantalla, no un servicio permanente |
| **Alojar el servicio en un VPS** | El servicio vive en un servidor con IP pública propia, ya preparado para estar expuesto | Si la finalidad es publicar para clientes y no para uso interno |

Los túneles inversos no abren puertos en el router, pero **siguen publicando el servicio**: Cloudflare Tunnel o ngrok dan una URL pública que cualquiera puede visitar, salvo que se añada autenticación en el intermediario. Evitan el problema de la IP, no el de la exposición. Su configuración concreta depende del servicio elegido y no se ejecutó; la documentación oficial está en el apartado final.

Regla práctica: si quien accede es **una persona o un equipo conocido**, VPN. Si el destinatario es **el público**, el servicio no debería estar en un router doméstico o de oficina.

## Comprobar si un puerto está abierto

Una regla puesta no equivale a un puerto alcanzable. Para distinguir qué falla hay que entender las **tres respuestas posibles** de un puerto TCP:

| Estado | Qué ha pasado | Qué se ve |
|---|---|---|
| **Abierto** | Hay un proceso escuchando y la conexión se completa | La conexión se establece |
| **Cerrado** (rechazado) | La máquina responde, pero no hay nadie escuchando en ese puerto: devuelve un rechazo inmediato (paquete RST) | Error rápido: *Connection refused* |
| **Filtrado** | Un firewall descarta el paquete sin responder | Silencio: la conexión se queda esperando hasta agotar el tiempo |

La diferencia entre cerrado y filtrado es la que más orienta al diagnosticar: un rechazo inmediato significa que el paquete **llegó** a una máquina que dijo «aquí no hay nada»; un silencio significa que algo **por el camino** se lo tragó.

### Demostración en local

La prueba se hace sin tocar ningún router ni firewall: un listener propio en `127.0.0.1` (la interfaz de bucle local, accesible solo desde la propia máquina), en el puerto 6830. Salidas obtenidas el 2026-11-10 en Windows 11 con Python 3.12 y curl 8.19.

Primero, el listener. Acepta una conexión, lee la petición y responde un HTTP mínimo:

```python
import socket

s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 6830))   # solo la propia máquina puede conectar
s.listen()
print("escuchando en 127.0.0.1:6830", flush=True)
while True:
    c, _ = s.accept()
    c.recv(1024)
    c.sendall(b"HTTP/1.0 200 OK\r\nContent-Length: 3\r\n\r\nhi\n")
    c.close()
```

Con el listener en marcha, `netstat -ano` lo lista en estado `LISTENING`. La columna de dirección local indica **en qué interfaz** escucha:

```text
  TCP    127.0.0.1:6830         0.0.0.0:0              LISTENING       27244
```

`127.0.0.1:6830` significa que solo acepta conexiones desde la misma máquina. Un servicio que mostrara `0.0.0.0:6830` escucharía en todas las interfaces, y quedaría al alcance de la red (y de internet, si hay una regla que lo reenvíe). Esta columna es lo primero que conviene mirar en el equipo destino de una redirección.

**Caso abierto.** `curl -v` muestra el establecimiento de la conexión y la respuesta:

```text
$ curl -sv http://127.0.0.1:6830/
*   Trying 127.0.0.1:6830...
* Established connection to 127.0.0.1 (127.0.0.1 port 6830) from 127.0.0.1 port 64500
> GET / HTTP/1.1
> Host: 127.0.0.1:6830
...
< HTTP/1.0 200 OK
< Content-Length: 3
```

**Caso cerrado.** El puerto 6831 no tiene ningún proceso. El rechazo es inmediato:

```text
$ curl -sv --max-time 5 http://127.0.0.1:6831/
*   Trying 127.0.0.1:6831...
* connect to 127.0.0.1 port 6831 from 0.0.0.0 port 64501 failed: Connection refused
* Failed to connect to 127.0.0.1 port 6831 after 2028 ms: Could not connect to server
```

curl termina con código de salida 7 (*no se pudo conectar*). En Windows, `Test-NetConnection` hace la misma prueba de forma más compacta, y su campo `TcpTestSucceeded` resume el resultado:

```powershell
Test-NetConnection 127.0.0.1 -Port 6830    # TcpTestSucceeded : True
Test-NetConnection 127.0.0.1 -Port 6831    # TcpTestSucceeded : False
                                           # ADVERTENCIA: TCP connect to (127.0.0.1 : 6831) failed
```

**Caso filtrado.** No se reprodujo: provocarlo exige una regla de firewall que descarte paquetes en lugar de rechazarlos, y modificar el firewall no estaba permitido. Lo que cabe esperar, según la documentación de nmap sobre estados de puerto (apartado final), es que `curl` no devuelva un rechazo, sino que espere hasta agotar `--max-time` y termine con el código 28 (*timeout*), y que `Test-NetConnection` tarde varios segundos antes de dar `False`.

### Probar una redirección real

La prueba de una regla debe hacerse **desde fuera de la red**, por ejemplo desde un móvil con los datos activados y la wifi apagada:

```bash
curl -v --max-time 10 http://198.51.100.7:8080/
```

Lectura del resultado, con los tres estados:

- **Respuesta HTTP**: la cadena completa funciona.
- **Connection refused**: el paquete llegó a una máquina que no tiene nada escuchando. O la regla apunta a un puerto interno equivocado, o el servicio está parado.
- **Timeout**: algo descarta el paquete antes de llegar: el firewall del equipo destino, el router, el proveedor o un NAT adicional (ver errores frecuentes).

## IP pública dinámica: DNS dinámico

La IP pública de un acceso doméstico o de pequeña oficina suele cambiar cada cierto tiempo. Una regla correcta deja de ser útil cuando quien se conecta tiene apuntada la IP antigua.

El **DNS dinámico** (DDNS) resuelve esto con un nombre estable. Un cliente (en el router o en un equipo de la red) avisa periódicamente al proveedor DDNS de la IP actual, y el proveedor actualiza el registro DNS de un nombre como `oficina.tienda.ejemplo.com`. Quien se conecta usa el nombre:

```bash
curl http://oficina.tienda.ejemplo.com:8080/
```

Muchos routers incluyen un cliente DDNS integrado y soportan varios proveedores; los nombres pueden salir gratis de servicios como DuckDNS o No-IP, o de un dominio propio con API de DNS. Tiene un límite: entre que la IP cambia y el cliente avisa, el nombre apunta a la dirección vieja durante unos minutos, que es lo que dura el TTL.

## CGNAT: cuando el router no tiene IP pública

Algunos proveedores no dan una IP pública a cada cliente: comparten una entre muchos, con un NAT adicional en su red (CGNAT, *Carrier-Grade NAT*). En ese caso la «IP pública» del router es en realidad una dirección interna del proveedor, y ninguna regla del router puede hacer llegar tráfico desde internet, porque el NAT que decide está fuera de su control.

**Cómo detectarlo.** Se comparan dos direcciones:

1. La **IP WAN** que el propio router muestra en su panel de estado (la de su interfaz hacia el proveedor).
2. La IP con la que un servicio externo ve la conexión: cualquier web o API del tipo «cuál es mi IP» devuelve la dirección de origen que le llega.

| Resultado | Significado |
|---|---|
| Las dos coinciden y es una IP pública | Hay IP pública propia: la redirección es viable |
| Son distintas | Hay un NAT por encima del router (CGNAT, o un doble NAT propio) |
| La IP WAN está en `100.64.0.0/10` | CGNAT casi seguro: ese rango está reservado para esa finalidad ([RFC 6598](https://datatracker.ietf.org/doc/html/rfc6598)) |
| La IP WAN es `10.x`, `172.16-31.x` o `192.168.x` | El router está detrás de otro router o del equipo del proveedor |

La comprobación se hace en el panel del router y en un navegador, y no se ejecutó contra ningún servicio real.

**Qué hacer si hay CGNAT.** Pedir al proveedor una IP pública (algunos la ofrecen gratis o con un coste pequeño), o usar un túnel inverso (Cloudflare Tunnel, ngrok, SSH `-R` contra un VPS), que solo necesita conexiones salientes, o montar la VPN en un VPS con IP pública y conectar ambos extremos a él.

## Hairpin NAT: probar desde dentro

Quien intenta usar `http://198.51.100.7:8080/` **desde un equipo de la propia LAN** a veces no consigue conectar, aunque la regla esté perfecta y desde fuera funcione. El motivo es el *hairpin NAT* (o *NAT loopback*): el paquete sale del equipo hacia la IP pública del router, y el router tendría que devolverlo hacia dentro, reescribiendo origen y destino. Muchos routers no implementan ese giro en horquilla, o lo hacen mal.

Soluciones, de mejor a peor:

- **Usar un nombre que dentro resuelva a la IP interna** (*split DNS*): fuera, `oficina.tienda.ejemplo.com` apunta a la IP pública; dentro, un servidor DNS de la LAN lo resuelve a `192.168.1.20`. Ver [DNS interno con dnsmasq](../../devops/despliegue-en-vps/DNS-Interno-con-dnsmasq.md).
- **Usar directamente la IP interna** desde la LAN.
- **Activar el NAT loopback** del router, si lo ofrece.

Por esta razón la prueba de una regla debe hacerse siempre desde fuera: un fallo desde dentro no demuestra que la regla esté mal, y un acierto desde dentro no demuestra que funcione desde internet.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| Desde fuera, *timeout*; desde dentro con la IP interna funciona | **El firewall del equipo destino bloquea el puerto.** La regla del router es correcta, pero el paquete llega a `192.168.1.20` y el firewall de ese equipo (Windows Defender Firewall, UFW...) lo descarta. Hay que permitir el puerto también ahí |
| La regla es correcta y desde fuera nunca funciona | **Doble NAT o CGNAT.** Hay otro router o un NAT del proveedor por encima; la IP WAN del panel no es la que ve internet. Ver la sección de CGNAT |
| Funcionaba y un día deja de responder | **La IP interna cambió por DHCP.** El equipo recibió otra dirección y la regla apunta al vacío. Reserva DHCP o IP estática |
| Funciona desde el móvil, no desde un equipo de la LAN | **Hairpin NAT** no soportado. Ver la sección correspondiente |
| `Connection refused` desde fuera | La regla llega al equipo, pero ningún proceso escucha en el puerto interno: servicio parado, puerto interno equivocado, o el servicio escucha solo en `127.0.0.1` en lugar de en la IP de la LAN |
| `Connection refused` al probar el puerto del propio router | La regla no existe o está desactivada, o el propio router tiene un servicio de administración remota en ese puerto |
| Funciona solo para UDP o solo para TCP | El campo protocolo de la regla no coincide con el del servicio |

Un servicio que escucha solo en `127.0.0.1` es inalcanzable desde otros equipos aunque la regla y el firewall estén bien. `netstat -ano` en el equipo destino (ver la demostración local) muestra a qué dirección está ligado el puerto.

## Buenas prácticas avanzadas

- **Desactiva UPnP en el router** — permite que cualquier programa de la red abra puertos por su cuenta, sin que nadie lo vea, y un dispositivo comprometido puede publicarse solo en internet. Apágalo y revisa de vez en cuando la tabla de reglas: debe contener únicamente lo que se puso a mano.
- **Una sola puerta, y que sea una VPN** — antes de reenviar RDP, SMB y el panel del NAS, plantéate abrir únicamente el puerto de [WireGuard](../../devops/despliegue-en-vps/WireGuard.md) y llegar al resto a través del túnel. Un servicio diseñado para vivir en la frontera, y que ignora en silencio todo paquete sin clave válida, es mucho más difícil de atacar que cinco servicios pensados para una red de confianza.
- **Combina defensas en capas** — limitar el origen en el router, filtrar en el firewall del destino, y bloquear reintentos con [Fail2ban](../../devops/despliegue-en-vps/Fail2ban.md): cada capa cubre el fallo de la anterior. Una regla del router sin firewall en el destino depende de un único punto.
- **Prueba siempre desde fuera y distingue los tres estados** — *refused* y *timeout* señalan sitios distintos de la cadena, y con esa diferencia se descubre en minutos qué falla en vez de cambiar reglas al azar.
- **Revisa qué escucha en el destino antes de publicar** — `netstat -ano` (o `ss -tlnp` en Linux): si el servicio escucha en `0.0.0.0` sin necesitarlo, o hay puertos que ni sabías que estaban abiertos, la redirección multiplica el problema.
- **No reenvíes nunca un puerto sin autenticación** — una base de datos, un panel de administración o una cámara con la contraseña de fábrica quedan comprometidos en horas. Si el servicio no se puede proteger por sí mismo, va detrás de una VPN.

## Documentación oficial

- [RFC 4787: requisitos de comportamiento de NAT para UDP](https://datatracker.ietf.org/doc/html/rfc4787) — la norma que define el comportamiento esperado de un NAT, incluido el *hairpinning*.
- [RFC 6598: espacio de direcciones compartido (100.64.0.0/10)](https://datatracker.ietf.org/doc/html/rfc6598) — el rango reservado para CGNAT, útil para reconocerlo.
- [Documentación de Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) — cómo funciona un túnel inverso y cómo se protege con autenticación.
- [nmap: fundamentos del escaneo de puertos](https://nmap.org/book/man-port-scanning-basics.html) — define los estados abierto, cerrado y filtrado tal como los distingue un escáner.

## Recursos didácticos

- [ngrok: documentación](https://ngrok.com/docs/) — la forma más rápida de probar un túnel inverso con un servicio local, para entender la idea sin tocar el router.

---

*En resumen: la redirección de puertos es la nota que le dejas al router para que entregue al equipo correcto lo que llega de internet; funciona solo con IP pública, con destino de IP estable y con el firewall del equipo de acuerdo, y como cada puerto abierto es una puerta a todo internet, lo prudente es abrir como mucho la de una VPN.*
