# VPN

## ¿Qué es?

Una **VPN** (*Virtual Private Network*, «red privada virtual») es un **túnel cifrado** entre dos puntos a través de una red que no controlas, normalmente internet. Los paquetes de tu equipo viajan dentro del túnel hasta el otro extremo, donde salen a la red de destino: desde el punto de vista de las aplicaciones, es como estar enchufado a esa red.

## ¿Por qué existe?

Carpetas compartidas, escritorio remoto, un NAS o un panel de administración están pensados para usarse **dentro de una red local**, donde los equipos son de confianza. Abrirlos a internet con [redirección de puertos](Redireccion-de-Puertos.md) los expone a escaneos y ataques de fuerza bruta las 24 horas. Pero quien teletrabaja, viaja o administra un servidor necesita alcanzarlos desde fuera.

La VPN cambia el planteamiento: en lugar de abrir cada servicio, se abre **una sola puerta**, autenticada y cifrada, y tras ella los servicios siguen siendo internos. Esa puerta es un único puerto (en WireGuard, un puerto UDP) en vez de uno por servicio.

> Es la diferencia entre colocar una ventanilla en cada despacho de la oficina para que cualquiera llame desde la calle y poner una sola puerta con portero: quien pasa, y solo quien pasa, circula por dentro como un empleado más.

## ¿Cuándo y para qué se usa?

Ejemplo conductor: una tienda online con un VPS (`203.0.113.10`, dominio `tienda.ejemplo.com`) y una oficina con red `192.168.1.0/24`, un equipo de trabajo en `192.168.1.20` y un NAS en `192.168.1.50`.

- **Teletrabajo**: desde casa, alcanzar `192.168.1.50` (el NAS) y `192.168.1.20` (escritorio remoto) sin exponerlos a internet.
- **Administración de servidores**: llegar por SSH al VPS sin tener el puerto 22 abierto al mundo. El montaje sobre un VPS está en [WireGuard](../../devops/despliegue-en-vps/WireGuard.md) (dentro de la guía de despliegue en VPS); aquí se explica el modelo.
- **Unir sedes**: que la oficina y el almacén se vean como una sola red.
- **Antesala de otros accesos**: primero se entra por VPN y luego se usa [Escritorio Remoto](Escritorio-Remoto.md), [SSH](SSH.md) o una [carpeta compartida](Carpeta-Compartida.md).

### Qué es una VPN y qué no

| Una VPN sí | Una VPN no |
|---|---|
| Cifra el tráfico entre tu equipo y el otro extremo del túnel | No cifra lo que ocurre **después** del otro extremo (si sales a una web por HTTP, ese tramo va en claro) |
| Te hace aparecer con una IP de la red remota | No te hace anónimo: quien opera el otro extremo ve tu tráfico y sabe quién eres |
| Reduce lo que se expone a internet a un solo puerto | No sustituye a las contraseñas ni a los permisos de cada servicio interno |
| Protege en una wifi pública el tramo hasta el servidor VPN | No protege de un equipo ya comprometido: ese equipo entra por el túnel |
| | No acelera la conexión: cifrar y dar un rodeo añade latencia |

### Tres usos con el mismo nombre

«VPN» designa tres situaciones distintas, y elegir mal es el origen de la mayoría de malentendidos.

| | Acceso remoto (*road warrior*) | Sitio a sitio (*site-to-site*) | VPN comercial |
|---|---|---|---|
| Qué conecta | Un equipo suelto con una red | Dos redes entre sí | Un equipo con un proveedor externo |
| Quién la monta | Quien administra la red de destino | Quien administra ambas sedes | Una empresa que vende el servicio |
| Se instala en | Cada portátil o móvil (cliente) | Los routers/firewalls de cada sede | El cliente del proveedor |
| Para qué sirve | Entrar a la oficina desde casa | Que `192.168.1.0/24` vea a la red del almacén sin que cada equipo haga nada | Cambiar la IP de salida o cifrar el tramo hasta el proveedor |
| Qué **no** da | Salida anónima | Acceso individual de personas | Acceso a tu red interna |

Tabla de decisión:

| Necesidad | Solución |
|---|---|
| Entrar a mi red o a mi servidor desde fuera | VPN de acceso remoto propia |
| Que dos sedes se comuniquen de forma permanente | VPN sitio a sitio |
| Un servicio que solo usan desde fuera dos o tres personas, con una sola aplicación | Valorar antes [SSH con túnel](SSH.md) o publicar ese servicio con HTTPS y autenticación |
| Cambiar de país o evitar que mi proveedor de internet vea el destino de mis conexiones | VPN comercial (el proveedor pasa a ver ese tráfico) |
| Anonimato frente a quien sirve la web | Ninguna VPN lo garantiza |

Una VPN comercial no sirve para entrar a la red de la oficina: apunta a servidores del proveedor, no a los tuyos.

---

## Túnel y encapsulado

Un túnel funciona **encapsulando**: el paquete original (con sus direcciones internas) se cifra y se mete como carga de otro paquete, que viaja por internet con las direcciones públicas de los dos extremos.

```text
Paquete original (dentro del túnel)
  origen 10.10.0.2  ->  destino 192.168.1.50      (IP privadas)
        |
        |  se cifra y se mete en un paquete UDP
        v
Paquete que ve internet
  origen 198.51.100.25:54219  ->  destino 203.0.113.10:51820   (IP públicas)
```

Quien observa la red entre los dos extremos solo ve un flujo UDP entre dos direcciones públicas. No ve a qué equipo interno se dirige el tráfico ni qué contiene.

En el extremo receptor se descifra y el paquete original sigue su camino hacia `192.168.1.50`. Para el sistema operativo, el túnel es una **interfaz de red más**, con su propia IP, igual que la wifi o el cable. Que el tráfico vaya por el túnel o por la conexión normal lo decide la tabla de rutas (sección «Split tunnel y full tunnel»).

El encapsulado tiene un coste: cada paquete lleva cabeceras añadidas y eso reduce el espacio útil (sección «MTU»).

## Protocolos: WireGuard, OpenVPN e IPsec

Los tres sirven para lo mismo y difieren en diseño y en dónde están disponibles.

| | WireGuard | OpenVPN | IPsec (IKEv2) y L2TP/IPsec |
|---|---|---|---|
| Diseño | Pocas líneas de código, un único conjunto de algoritmos modernos, sin negociación | Basado en TLS, muy configurable | Familia de estándares, negociación compleja |
| Transporte | UDP | UDP o TCP (típicamente el 1194, o el 443 para atravesar firewalls restrictivos) | UDP 500 y 4500, y el protocolo ESP (número 50) |
| Configuración | Un fichero corto con claves | Fichero `.ovpn` con certificados o usuario/contraseña | Depende del equipo; claves compartidas o certificados |
| Autenticación | Par de claves por dispositivo | Certificados, usuario/contraseña | Certificados, claves precompartidas |
| Soporte | Núcleo de Linux, clientes para Windows, macOS, iOS, Android | Cliente a instalar en todos | Integrado en Windows, iOS, Android, macOS |
| Cuándo | Montaje nuevo propio | Red que solo deja pasar TCP 443; infraestructura ya existente | Se exige que sea nativo (sin instalar nada) o interoperar con un firewall o router corporativo |

- **WireGuard** es la opción por defecto para un montaje nuevo: la configuración es corta y el servidor **no responde a paquetes que no estén firmados por una clave autorizada**, de modo que un escáner de puertos UDP no detecta que hay una VPN escuchando.
- **OpenVPN** es el recurso cuando la red desde la que se conecta solo deja salir TCP 443: puede disfrazarse de tráfico HTTPS. Es más lento y de configuración más extensa.
- **IPsec** es el estándar de interoperabilidad entre equipos de distintos fabricantes y es lo habitual en las VPN sitio a sitio entre routers. **L2TP/IPsec** es una combinación antigua (L2TP monta el túnel e IPsec lo cifra); sigue apareciendo en equipos viejos. **PPTP**, del mismo entorno, está roto criptográficamente y no debe usarse.

---

## El modelo de WireGuard

WireGuard no distingue entre «cliente» y «servidor» en su diseño: cada extremo es un **par** (*peer*). Quien tiene IP pública fija actúa de punto de encuentro, pero conceptualmente son iguales. Cuatro conceptos bastan para entender cualquier configuración.

### Par de claves

Cada par tiene una **clave privada** (secreta, nunca sale del dispositivo) y una **clave pública** derivada de ella, que se entrega al otro extremo. Es el mismo modelo que las claves SSH: se intercambian las públicas y a partir de ahí cada extremo reconoce al otro.

Generación del par, sin crear ni activar ninguna interfaz:

```bash
umask 077
wg genkey > privada.key
wg pubkey < privada.key > publica.key
cat publica.key
```

```text
OS7/1ehZTFSpSMisQeMz9KJdfH8bdhzXeZhlWDwJO00=
```

`wg genkey` escribe en la salida estándar una clave privada aleatoria; `wg pubkey` lee una privada por la entrada estándar y escribe la pública correspondiente. Ambas son 32 bytes en base64 (44 caracteres, acabados en `=`). El `umask 077` hace que el fichero de la privada solo lo lea su propietario; sin él, `wg` avisa con `Warning: writing to world accessible file`. Esa advertencia es lo que apareció al ejecutarlo sin `umask` el 2026-11-10.

La clave pública de arriba es **de prueba**: se generó para este ejemplo, no se usa en ningún túnel y su privada se descartó. En los ejemplos de configuración siguientes las claves aparecen sustituidas por marcadores (`<CLAVE_PRIVADA_DEL_SERVIDOR>`, etc.) y no deben copiarse tal cual.

### Dirección del túnel (`Address`)

Cada extremo tiene una IP **dentro de la red virtual del túnel**, una subred privada que se elige y que no existe en ninguna otra parte (en los ejemplos, `10.10.0.0/24`). No la reparte ningún DHCP: se escribe a mano en cada fichero.

### `Endpoint`: dónde está el otro extremo

`Endpoint = IP_pública:puerto` indica a dónde enviar los paquetes cifrados. Lo normal es que solo lo lleve quien inicia la conexión (el portátil apunta al VPS, no al revés). WireGuard aprende solo el endpoint de un par cuando recibe un paquete válido de él: si el portátil cambia de wifi y su IP pública cambia, el servidor actualiza su dirección al recibir el siguiente paquete autenticado.

### `AllowedIPs`: la lista de destinos y de orígenes

Es la opción que más confunde, porque significa dos cosas a la vez (descripción de `wg(8)`: direcciones «desde las que se permite tráfico entrante» para ese par y «hacia las que se dirige el tráfico saliente»):

- **Al enviar**: funciona como tabla de enrutado. Si un paquete va a una IP incluida en el `AllowedIPs` de un par, se cifra con la clave de ese par y se envía a su `Endpoint`.
- **Al recibir**: funciona como filtro. Un paquete descifrado correctamente que venga de una IP no incluida en el `AllowedIPs` de ese par se descarta.

Con varios pares, esa tabla decide a cuál va cada paquete, por lo que no puede haber rangos repetidos entre pares.

### `PersistentKeepalive`

WireGuard no envía nada si no hay tráfico. Un cliente detrás de un router con NAT necesita que la asociación de puertos del router siga viva para que el servidor le pueda enviar paquetes; sin tráfico, el router la olvida al cabo de un minuto o menos. `PersistentKeepalive = 25` envía un paquete vacío autenticado cada 25 segundos para evitarlo. Se pone en el lado que está detrás de NAT y necesita ser alcanzable; en el lado con IP pública no hace falta.

## Configuración de ejemplo

> **No ejecutado.** Los ficheros siguientes no se activaron en ninguna máquina: están escritos a partir de la documentación oficial (`wg(8)`, `wg-quick(8)` y el [quickstart](https://www.wireguard.com/quickstart/)). Las claves son marcadores y las direcciones son las del ejemplo conductor.

Servidor, el VPS (`203.0.113.10`), con el fichero `wg0.conf`:

```ini
[Interface]
# IP del servidor dentro del túnel. Subred inventada que no existe en ninguna otra red.
Address    = 10.10.0.1/24
# Puerto UDP en el que escucha: debe estar abierto en el firewall.
ListenPort = 51820
PrivateKey = <CLAVE_PRIVADA_DEL_SERVIDOR>

[Peer]
# Portátil de trabajo
PublicKey  = <CLAVE_PUBLICA_DEL_PORTATIL>
# Solo acepta de este par paquetes con origen 10.10.0.2 (y solo le enruta esa IP).
AllowedIPs = 10.10.0.2/32
```

Cliente, el portátil de quien teletrabaja:

```ini
[Interface]
Address    = 10.10.0.2/32
PrivateKey = <CLAVE_PRIVADA_DEL_PORTATIL>

[Peer]
# El servidor
PublicKey           = <CLAVE_PUBLICA_DEL_SERVIDOR>
Endpoint            = 203.0.113.10:51820
# Qué se envía por el túnel: ver la sección «Split tunnel y full tunnel».
AllowedIPs          = 10.10.0.0/24, 192.168.1.0/24
PersistentKeepalive = 25
```

Lo que dice este par de ficheros:

- Las dos claves privadas **no se comparten**. Cada fichero lleva su privada y la pública del otro.
- El servidor no tiene `Endpoint` del portátil: no lo conoce hasta recibir su primer paquete.
- `AllowedIPs = 10.10.0.2/32` en el servidor y `10.10.0.0/24, 192.168.1.0/24` en el cliente no son contradictorios: cada uno describe qué tráfico se asocia a **ese par** desde su propio lado.
- Para que el portátil llegue a `192.168.1.50`, el extremo remoto tiene que **reenviar** paquetes hacia la red `192.168.1.0/24` (en Linux, `net.ipv4.ip_forward=1` más permitirlo en el firewall) y el destino tiene que saber devolver la respuesta. El procedimiento completo está en [WireGuard](../../devops/despliegue-en-vps/WireGuard.md).

Cómo leer `wg show` (último apretón de manos, bytes transferidos) está en la ficha de despliegue enlazada arriba.

## Split tunnel y full tunnel

`AllowedIPs` en el cliente decide **qué tráfico entra al túnel**, y con ello si el túnel es parcial o total.

| | Split tunnel (túnel dividido) | Full tunnel (túnel completo) |
|---|---|---|
| `AllowedIPs` en el cliente | `192.168.1.0/24` (o `10.10.0.0/24`) | `0.0.0.0/0` (y `::/0` para IPv6) |
| Qué pasa por el túnel | Solo lo destinado a esas redes | Todo el tráfico de internet |
| Navegar por internet | Sale por la conexión normal de quien teletrabaja | Sale por el servidor VPN: se ve la IP del servidor |
| Ventajas | Más rápido, sin cargar el servidor | Protege en wifi pública; el tráfico queda bajo el control corporativo |
| Inconvenientes | El resto del tráfico no va protegido por el túnel | Más latencia, y el servidor necesita salida y enmascarado (NAT) a internet |

Mismo cliente, dos valores de la línea:

```ini
# Split tunnel: solo la oficina por el túnel
AllowedIPs = 192.168.1.0/24

# Full tunnel: todo por el túnel
AllowedIPs = 0.0.0.0/0
```

### Qué cambia en la tabla de rutas

El sistema operativo mantiene una tabla que decide por qué interfaz sale cada paquete, eligiendo la ruta más específica. Con un túnel de acceso remoto activo y `AllowedIPs` dividido, `route print -4` en Windows muestra algo como (salida real del 2026-11-10 en una máquina con un túnel dividido activo, abreviada y con las direcciones sustituidas por las del ejemplo conductor):

```text
IPv4 Tabla de enrutamiento
===========================================================================
Rutas activas:
Destino de red        Máscara de red   Puerta de enlace   Interfaz  Métrica
          0.0.0.0          0.0.0.0      192.168.1.1      192.168.1.20    291
        10.10.0.0    255.255.255.0      En vínculo         10.10.0.2      5
        10.10.0.2  255.255.255.255      En vínculo         10.10.0.2    261
      192.168.1.0    255.255.255.0      En vínculo         192.168.1.20  291
```

Cómo leerlo:

- `0.0.0.0/0` por `192.168.1.1` es la **ruta por defecto**: todo lo que no tenga una ruta más específica sale por el router de la red local. Aquí sigue activa, por eso internet funciona con normalidad.
- `10.10.0.0/24` «En vínculo» (*on-link*) por la interfaz `10.10.0.2` es la ruta que añade el túnel: lo destinado a la red del túnel sale por la interfaz virtual, sin puerta de enlace porque el otro extremo está directamente «conectado».
- Con `AllowedIPs = 10.10.0.0/24, 192.168.1.0/24` se añadiría también una ruta a la red de la oficina por la interfaz del túnel. Es entonces cuando se produce el solapamiento descrito más abajo si la red local de quien teletrabaja es la misma.

Con `AllowedIPs = 0.0.0.0/0`, el cliente tiene que desviar **todo** el tráfico, incluido el que iría a la ruta por defecto. No se ejecutó (activar un túnel completo cambia la conectividad de la máquina), así que lo siguiente procede de la documentación de `wg-quick(8)`: en Linux no se sustituye la ruta por defecto, sino que se usa una marca de paquete (`fwmark`) y una tabla de rutas aparte para que los paquetes **cifrados** del propio túnel hacia el `Endpoint` salgan por la conexión real y no vuelvan a entrar al túnel; los paquetes de usuario van a la interfaz `wg0`. Un detalle que conviene tener presente: el `Endpoint` (`203.0.113.10`) debe seguir alcanzable por la conexión normal, o el túnel se corta a sí mismo.

## Solapamiento de subredes

El error clásico del acceso remoto: la red de la oficina es `192.168.1.0/24` y la red de casa también (es el rango por defecto de muchos routers).

```text
Casa:     192.168.1.0/24   (router 192.168.1.1, impresora 192.168.1.50)
Oficina:  192.168.1.0/24   (NAS 192.168.1.50)
```

Al conectar la VPN y pedir `192.168.1.50`, el sistema ve dos rutas iguales: la de la interfaz de casa y la del túnel. Con rutas idénticas decide la métrica, y la de la red local suele ganar, de modo que `192.168.1.50` es la impresora de casa y no el NAS. Los síntomas son confusos: unas veces se conecta a otro equipo, otras da «tiempo de espera agotado».

Soluciones, de mejor a peor:

1. **Usar rangos poco habituales en las redes que se van a unir.** Evitar `192.168.0.0/24`, `192.168.1.0/24` y `10.0.0.0/24`; son los de fábrica en la mayoría de routers. Es la solución definitiva, pero obliga a renumerar la red de la oficina. Lo mismo vale para la subred del túnel (`10.10.0.0/24` en los ejemplos) y para las redes de Docker (`172.17.0.0/16` y siguientes).
2. **Acceder por nombre y no por IP**, con DNS interno que resuelva a direcciones del túnel, cuando es posible reasignar.
3. **NAT entre las redes** en el extremo remoto, para que desde casa el NAS aparezca con otra IP (por ejemplo `10.20.0.50`). Funciona, pero añade complejidad que hay que mantener.

El solapamiento no se arregla con la VPN: es un problema de direccionamiento anterior a ella. Verificar las redes de todos los puntos antes de elegir la subred del túnel evita el problema.

## MTU

La **MTU** (*Maximum Transmission Unit*) es el tamaño máximo de paquete que admite una interfaz; en Ethernet y wifi suele ser 1500 bytes. El encapsulado añade cabeceras (WireGuard añade un mínimo de 60 bytes sobre IPv4 y 80 sobre IPv6), así que la interfaz del túnel debe tener una MTU menor para que el paquete ya encapsulado quepa en los 1500 de la red real.

Salida real del 2026-11-10 de `netsh interface ipv4 show subinterfaces` (abreviada, con el nombre de la interfaz sustituido por `wg0`):

```text
       MTU  MediaSenseState      Bytes de entrada     Bytes de salida Interfaz
----------  ---------------  ------------  ------------  -------------
      1420                1       2309483        976159  wg0
      1500                1    6155057963     824151187  Ethernet
```

La interfaz del túnel tiene MTU 1420 (1500 menos 80, el cálculo prudente que cubre IPv6) frente a los 1500 del cable. `wg-quick` la calcula sola a partir de la ruta hacia el `Endpoint` si no se indica una (`MTU =` en `[Interface]`), y casi siempre es válida.

Cuando falla, el síntoma es característico: el túnel funciona, `ping` responde y SSH entra, pero las **transferencias grandes se quedan colgadas** o las páginas cargan a medias. Pasa porque los paquetes pequeños caben y los grandes se pierden. Se diagnostica con ping sin fragmentación, a partir de 1420 y bajando hasta que pase:

```bash
ping -f -l 1392 10.10.0.1      # Windows: -f no fragmentar, -l tamaño de datos
ping -M do -s 1392 10.10.0.1   # Linux
```

La carga útil del `ping` suma 28 bytes de cabeceras (20 de IP y 8 de ICMP) al tamaño indicado. Si `1392` pasa y valores mayores no, la MTU efectiva del camino es 1420. No ejecutado aquí (requiere un túnel real); el procedimiento procede del [quickstart](https://www.wireguard.com/quickstart/) y de `wg-quick(8)`. Si hace falta bajarla, se fija en `[Interface]` con `MTU = 1380` o un valor similar.

---

## Errores frecuentes

No ejecutado en ningún túnel real; el diagnóstico se basa en el comportamiento descrito en la documentación oficial.

| Síntoma | Causa probable |
|---|---|
| `wg show` en el servidor no muestra línea `latest handshake` para el par | El paquete de inicio no llega. Puerto UDP bloqueado en el firewall del servidor (`ufw allow 51820/udp`), en el del proveedor del VPS, o en la red desde la que conecta el cliente |
| Sigue sin llegar con el firewall abierto | `Endpoint` con IP o puerto equivocados; o las claves públicas están cruzadas (la del servidor en el cliente debe ser la del **servidor**, y viceversa) |
| Hay handshake pero no pasa tráfico | `AllowedIPs` mal: la IP de destino no está en el `AllowedIPs` del cliente (el paquete ni entra al túnel), o la IP de origen no está en el `AllowedIPs` de ese par en el servidor (se descarta) |
| Se alcanza `10.10.0.1` pero no la red `192.168.1.0/24` | Falta reenviar paquetes en el servidor (`ip_forward`), falta permitirlo en el firewall, o los equipos de la oficina no tienen ruta de vuelta hacia `10.10.0.0/24` |
| Funciona un rato y luego el servidor no puede alcanzar al cliente | Cliente tras NAT sin `PersistentKeepalive` |
| `192.168.1.50` responde otro equipo, o a veces nada | Solapamiento de subredes |
| `ping` y SSH van, pero las transferencias grandes se quedan colgadas | MTU demasiado alta |
| Dos dispositivos con la misma clave se desconectan alternativamente | Cada dispositivo necesita su propio par de claves |
| Con `AllowedIPs = 0.0.0.0/0` se pierde internet | El servidor no hace reenvío ni NAT hacia internet, o el `Endpoint` quedó enrutado dentro del propio túnel |

El diagnóstico se hace en este orden: primero comprobar que el paquete UDP llega y hay handshake; solo después buscar fallos de rutas y `AllowedIPs`.

## Buenas prácticas avanzadas

- **Un par de claves por dispositivo, generado en el dispositivo.** La clave privada no debería viajar nunca por correo ni chat. Y dos equipos con la misma clave se pisan, además de que revocar uno obliga a rehacer los demás.
- **`AllowedIPs` mínimos en el servidor, no el `/24` entero.** Dar a cada par su `/32` es un filtro de origen: un portátil comprometido no puede suplantar la IP de otro par. Para limitar a qué recursos llega cada par, hacen falta además reglas de firewall en el servidor sobre la interfaz del túnel: la VPN te mete en la red, pero no debería darte toda la red.
- **Elige una subred poco común antes de montar nada.** Comprueba las redes de casa y oficina, las de Docker y las de las redes que alguien pueda usar de visita. Cambiar la subred de una VPN ya repartida a diez dispositivos es mucho más caro que acertar a la primera.
- **El DNS forma parte del túnel.** Con `DNS =` en el cliente se usan resolutores internos; si no se configura, los nombres internos no resuelven aunque el túnel funcione. Y al revés: con túnel completo, un resolutor del proveedor local puede filtrar las consultas fuera del túnel.
- **Fíjate en `latest handshake`, no en el estado del servicio.** WireGuard no mantiene «sesiones»; el servicio activo solo indica que la interfaz existe. Un handshake de hace más de unos minutos significa que ese par no está conectado.
- **No cierres la vía de administración pública sin tener otra.** Si la VPN es la única puerta al servidor y falla tras una actualización, hace falta una consola del proveedor probada de antemano.

## Documentación oficial

- [WireGuard — quickstart](https://www.wireguard.com/quickstart/) — el modelo de pares, claves y `AllowedIPs` explicado de forma corta; primera lectura.
- [WireGuard — protocolo y criptografía](https://www.wireguard.com/protocol/) — qué algoritmos usa y cómo es el apretón de manos, para entender por qué no responde a quien no está autorizado.
- [wg(8)](https://man7.org/linux/man-pages/man8/wg.8.html) y [wg-quick(8)](https://man7.org/linux/man-pages/man8/wg-quick.8.html) — referencia de cada opción (`AllowedIPs`, `PersistentKeepalive`, `MTU`, `Table`, `DNS`).
- [RFC 1918](https://datatracker.ietf.org/doc/html/rfc1918) — los rangos de direcciones privadas, para elegir una subred que no choque.

---

*En resumen: una VPN encapsula el tráfico en un túnel cifrado para entrar a una red por una sola puerta, no para ser anónimo, y casi todos sus fallos se reducen a tres cosas: un puerto UDP bloqueado, un `AllowedIPs` mal escrito o dos redes con el mismo rango.*
