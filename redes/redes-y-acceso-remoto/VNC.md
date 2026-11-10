# VNC

## ¿Qué es?

**VNC** (*Virtual Network Computing*) es una tecnología para ver y controlar el escritorio de otro equipo a través de la red. Se apoya en un protocolo abierto, **RFB** (*Remote Framebuffer*), descrito en el [RFC 6143](https://www.rfc-editor.org/rfc/rfc6143), y existen servidores y visores para Windows, Linux y macOS que se entienden entre sí.

## ¿Por qué existe?

El servidor de Escritorio Remoto de Windows ([RDP](Escritorio-Remoto.md)) solo existe en Windows. VNC nació para resolver lo mismo sin atarse a un sistema operativo: controlar un Linux desde un Windows o un Mac desde un Linux.

Su diseño es deliberadamente simple. El servidor trata la pantalla como una imagen rectangular (el *framebuffer*), envía al visor los rectángulos que han cambiado y recibe de vuelta movimientos de ratón y pulsaciones de tecla. No sabe qué hay dibujado (ventanas, botones, texto): solo píxeles. Por eso funciona con cualquier sistema, y por eso es más pesado que RDP.

> Si ya conoces RDP, piensa en VNC como un "retransmitir el monitor": quien está en el equipo remoto y tú veis lo mismo a la vez. RDP, en cambio, es "abrir una sesión nueva a distancia".

## ¿Cuándo y para qué se usa?

Tomando el ejemplo de una tienda online con una oficina (red `192.168.1.0/24`) y un VPS en `203.0.113.10`:

- **Asistir a una persona** del equipo de oficina (`192.168.1.20`) viendo exactamente lo que ve en su pantalla, sin cerrarle la sesión.
- **Controlar equipos Linux o macOS** donde RDP no encaja bien.
- **Gestionar dispositivos sin monitor** (mini-PC, placas tipo Raspberry Pi) que necesitan escritorio gráfico puntual.
- **Entornos de laboratorio o formación**, con escritorios Linux accesibles desde el navegador (véase «VNC en el navegador»).

Para administrar un servidor como el VPS **no** es la herramienta: ahí se usa [SSH](SSH.md) por terminal.

## El protocolo RFB: puertos y displays

Según el RFC 6143 (sección 2), un cliente RFB contacta con el servidor por TCP en el puerto **5900**, y en sistemas con varios servidores, el servidor N escucha en **5900+N**. Ese N es el número de *display*, un concepto heredado de X Window (que usa 6000+N):

| Display | Puerto TCP | Se escribe en el visor |
|---|---|---|
| `:0` | 5900 | `192.168.1.20:0` o `192.168.1.20::5900` |
| `:1` | 5901 | `192.168.1.20:1` |
| `:2` | 5902 | `192.168.1.20:2` |

Muchos visores aceptan `host:N` (número de display) y `host::puerto` (puerto TCP literal). La confusión entre ambas notaciones es un clásico: `host:5901` suele interpretarse como display 5901, es decir, el puerto 11801 (se detalla en «Errores frecuentes»).

El RFC aclara que el único puerto asignado por IANA para RFB es el 5900; el resto son convención.

### El inicio de la conversación

Al conectar, lo primero que ocurre es un intercambio de versión: el servidor envía 12 bytes en texto ASCII, `RFB 003.008\n`, y el cliente responde con la versión que elige. A partir de ahí se negocia el tipo de seguridad, se autentica y se envía la pantalla.

Demostración con un servidor falso en `127.0.0.1` (solo envía el mensaje de versión; no es un VNC real ni dibuja nada):

```python
import socket, threading
srv = socket.socket(); srv.bind(("127.0.0.1", 6850)); srv.listen(1)
def servidor():
    c, _ = srv.accept()
    c.sendall(b"RFB 003.008\n")          # mensaje de versión del servidor (12 bytes)
    print("servidor: cliente responde", c.recv(12))
    c.close()
t = threading.Thread(target=servidor); t.start()
cli = socket.create_connection(("127.0.0.1", 6850))
v = cli.recv(12)
print("cliente: version recibida", v, len(v), "bytes")
cli.sendall(b"RFB 003.008\n")            # el cliente elige la versión
t.join(); cli.close(); srv.close()
```

Salida real (ejecutado el 2026-11-10 en una máquina de pruebas):

```text
cliente: version recibida b'RFB 003.008\n' 12 bytes
servidor: cliente responde b'RFB 003.008\n'
```

Los 12 bytes coinciden con el formato del RFC (`52 46 42 20 30 30 33 2e 30 30 38 0a`). El resto del protocolo (seguridad, `ServerInit`, rectángulos) no se ha ejecutado aquí.

## VNC frente a RDP y a las herramientas comerciales

La diferencia de fondo: **qué se comparte**.

- **RDP** crea (o reanuda) una sesión de usuario propia en el servidor y envía instrucciones de dibujo, no imágenes completas. En Windows de escritorio, conectarse suele bloquear la sesión local: quien está delante ve la pantalla de bloqueo.
- **VNC** comparte la pantalla de una sesión que ya existe (la física, en Windows y macOS; o una virtual, en Linux con Xvnc) y envía píxeles. Ambas partes ven y manejan lo mismo a la vez.
- **Herramientas comerciales** (TeamViewer, AnyDesk; ver [Herramientas de Control Remoto](Herramientas-de-Control-Remoto.md)) añaden una intermediación en la nube: no hace falta abrir puertos ni conocer la IP.

| Criterio | RDP | VNC | Herramienta comercial |
|---|---|---|---|
| Sesión | Propia, independiente de la pantalla física | La pantalla existente (o una virtual en Linux) | La pantalla existente |
| Servidor disponible en | Windows (ediciones Pro y superiores) | Windows, Linux, macOS | Windows, Linux, macOS, móviles |
| Cifrado | Sí, de serie | No en RFB clásico; depende de la implementación | Sí, gestionado por el proveedor |
| Atraviesa NAT sin abrir puertos | No | No | Sí |
| Rendimiento en redes lentas | Bueno | Aceptable con compresión | Bueno |
| Mejor para | Administrar equipos Windows | Equipos no Windows y soporte a quien está delante | Soporte puntual a terceros sin conocimientos de red |

Criterio de decisión rápido:

1. ¿Equipo Windows y necesitas una sesión propia? RDP, por [VPN](VPN.md).
2. ¿Linux o macOS, o necesitas ver lo mismo que la otra persona? VNC, siempre dentro de un túnel.
3. ¿Soporte a alguien fuera de tu red, sin infraestructura? Herramienta comercial.
4. ¿Solo hace falta terminal? SSH, sin escritorio.

## Servidores y clientes habituales

Hay un solo protocolo y muchas implementaciones. Estado verificado el 2026-11-10 contra sus páginas y repositorios cuando se indica; lo demás queda marcado.

| Implementación | Qué es | Licencia / estado |
|---|---|---|
| **TigerVNC** | Servidor y visor multiplataforma; en Linux incluye `Xvnc` (servidor con pantalla virtual) y `x0vncserver` (comparte la pantalla X física) | GPL v2 (fichero `LICENCE.TXT` del repositorio). Última versión publicada: v1.16.2 (2026-03-26, API de GitHub). El README actual menciona también `w0vncserver`, para compositores Wayland |
| **x11vnc** | Comparte una sesión X11 ya existente | GPL v2 (`COPYING` del repositorio). Solo X11 |
| **UltraVNC** | Servidor y visor para Windows, con transferencia de archivos y chat | Se presenta como VNC de código abierto (uvnc.com); licencia exacta no verificada |
| **TightVNC** | Servidor y visor, origen de la codificación Tight | Sitio no accesible desde la máquina de pruebas (sin respuesta HTTP); licencia y estado no verificados |
| **RealVNC** (Connect) | Producto comercial de los autores originales de VNC; añade cifrado y acceso por la nube | Comercial; la página de precios devolvió 403 a `curl`, planes y condiciones no verificados |
| **macOS Screen Sharing** | Compartir pantalla integrado en macOS | Incluido en el sistema. Según Apple, la opción «VNC viewers may control screen with password» permite visores VNC estándar, y Apple declara compatibilidad con VNC |

Los visores más comunes (TigerVNC Viewer, RealVNC Viewer, el visor de UltraVNC, Remmina en Linux) hablan RFB y se conectan a cualquiera de los servidores anteriores. Los servidores propietarios añaden extensiones (cifrado propio, credenciales de sistema), y quien los quiera usar con visores de terceros debe comprobar qué tipo de seguridad aceptan.

## Seguridad: por qué no abrir el 5900 a internet

El RFB clásico incluye un tipo de seguridad llamado *VNC Authentication*. El RFC 6143 (sección 7.2.2) lo describe así: el servidor envía un reto aleatorio de 16 bytes y el cliente lo cifra con DES, usando como clave la contraseña truncada a **ocho caracteres**. El propio RFC lo califica de «criptográficamente débil» y dice que no está pensado para redes no confiables. Además, tras autenticarse, el tráfico (pantalla, teclas, portapapeles) viaja **sin cifrar** salvo que el servidor use una extensión de seguridad (el RFC menciona VeNCrypt entre los tipos asignados históricamente) o se proteja desde fuera. El RFC recomienda IPsec o SSH.

Consecuencias:

- Quien capture el tráfico lee la pantalla completa y lo que se teclea (incluidas contraseñas).
- La contraseña de ocho caracteres admite ataques de fuerza bruta contra el reto.
- Un 5900 abierto a internet se escanea y ataca de forma rutinaria.

❌ MAL — puerto VNC expuesto en el router mediante [redirección de puertos](Redireccion-de-Puertos.md):

```text
Router: 5900/tcp externo  →  192.168.1.20:5900
```

✅ BIEN — el servidor solo atiende en `localhost` (o en la red local, tras firewall) y se entra por [SSH](SSH.md) o por [VPN](VPN.md). El puerto 5900 no aparece en el router.

### Túnel SSH

Un túnel SSH hace que el puerto 5900 del servidor aparezca en tu máquina, con todo el tráfico cifrado dentro de la conexión SSH. Para un equipo con VNC y SSH accesible (aquí, el VPS de la tienda como ejemplo; no ejecutado contra ninguna máquina real):

```bash
ssh -L 5901:localhost:5900 deployer@203.0.113.10
```

Y en el visor, a continuación, se abre `localhost:5901` (o, según el visor, `localhost::5901`).

Qué hace cada parte:

| Parte | Significado |
|---|---|
| `ssh` | Cliente OpenSSH. |
| `-L` | Reenvío local (*local forward*): abre un puerto de escucha **en tu máquina**. |
| `5901` | Puerto local de escucha. Se elige 5901 y no 5900 para no chocar con un servidor VNC propio en la máquina local. |
| `localhost:5900` | Destino, **visto desde el servidor**: «`localhost`» significa el propio servidor, no tu máquina. Ahí escucha VNC. |
| `deployer@203.0.113.10` | Usuario y dirección del servidor SSH al que se conecta el túnel. |

Lo que sí se ha comprobado, solo de lectura (`ssh -G`, OpenSSH 10.3p1, 2026-11-10, sin abrir ninguna conexión), es cómo interpreta el cliente el comando:

```text
user deployer
hostname 203.0.113.10
port 22
localforward 5901 [localhost]:5900
```

Variante: si el servidor SSH es un equipo intermedio (un salto) y VNC está en otra máquina de su red, se cambia el destino: `-L 5901:192.168.1.20:5900`. El tramo entre el salto y `192.168.1.20` va sin cifrar por la red local de oficina, por lo que solo es aceptable si esa red es de confianza.

Para que el 5900 tampoco quede accesible desde la red local, se configura el servidor VNC para escuchar solo en el interfaz de bucle local. La mayoría de implementaciones ofrecen una opción para ello (en TigerVNC, `-localhost`); no verificada contra su manual ni ejecutada aquí.

### Alternativa: VPN

Con una VPN ([VPN](VPN.md), por ejemplo [WireGuard](../../devops/despliegue-en-vps/WireGuard.md)), el equipo remoto se alcanza por su dirección privada y VNC viaja dentro del túnel cifrado. Es preferible al túnel SSH cuando se accede a varios servicios o equipos a la vez.

## VNC en el navegador: noVNC

**noVNC** es un visor VNC escrito en JavaScript que funciona dentro del navegador, sin instalar nada. Un navegador no puede abrir un socket TCP crudo, así que hace falta un traductor: **websockify** convierte WebSocket a TCP y reenvía hacia el servidor VNC (noVNC y websockify son proyectos hermanos, según el README de noVNC). La cadena resultante:

```text
Navegador (noVNC) —WebSocket→ websockify —TCP→ servidor VNC (5900+N)
```

Se usa en paneles de máquinas virtuales y laboratorios de formación. El riesgo es el mismo que con VNC clásico, trasladado a la web: si websockify queda expuesto sin TLS ni autenticación sólida, el escritorio queda abierto. La versión estable actual es la 1.7.0 (2026-04-28, API de GitHub); licencia MPL 2.0 en el núcleo, según su `LICENSE.txt`. Esta sección es conceptual: no se ha ejecutado noVNC.

## Rendimiento: codificaciones

El visor y el servidor negocian cómo se codifican los rectángulos (RFC 6143, sección 7.7):

- **Raw**: píxeles sin comprimir; siempre disponible, muy pesado.
- **Hextile, RRE, CopyRect**: simples; el RFC marca Hextile y RRE como obsoletas.
- **ZRLE** y **TRLE**: el RFC indica que los servidores actuales usan sobre todo ZRLE, TRLE y Tight. ZRLE comprime con zlib.
- **Tight**: nacida en TightVNC y listada en el RFC como asignación histórica; es la que muchos visores ofrecen para enlaces lentos (comportamiento no verificado aquí).

Opciones que se tocan en la práctica: bajar la **profundidad de color** (16 bits en vez de 24), reducir la **calidad JPEG**, desactivar el fondo de escritorio y las animaciones en el equipo remoto, y reducir la resolución. Las implementaciones exponen estos ajustes con nombres distintos; se consultan en su manual.

## VNC en Linux

En Linux existen dos modelos distintos y conviene no confundirlos:

- **Compartir la pantalla física** (`x0vncserver`, `x11vnc`): quien está en el equipo y quien conecta ven lo mismo. Sirve para soporte.
- **Pantalla virtual** (`Xvnc`): el servidor crea un escritorio gráfico propio, sin monitor, en el display `:1` (puerto 5901). Es el modelo de servidores sin pantalla: cada usuario tiene su sesión, parecida a RDP. TigerVNC distribuye `Xvnc`, el servicio `vncserver@.service` (para levantar una sesión de usuario con Xvnc) y el servidor para compositores Wayland `w0vncserver`, según su README.

El arranque automático de estas sesiones y su relación con el gestor de sesiones (*display manager*, como GDM o LightDM) varía según la distribución y no se cubre aquí. Todo lo de esta sección es documental, no ejecutado.

## Errores frecuentes

| Síntoma | Causa y solución |
|---|---|
| Pantalla negra o gris tras conectar a un equipo Linux | Sesión Wayland: los servidores clásicos (`x11vnc`, `x0vncserver`) capturan una pantalla X11 y en Wayland no ven nada. Usar una sesión X11, un servidor con soporte Wayland (como `w0vncserver`) o el mecanismo de escritorio remoto del entorno. Es el síntoma habitual; no reproducido aquí |
| `connection refused` (o «No se puede establecer la conexión») en el 5900 | El servidor no está arrancado, no escucha en ese display (puede ser el 5901, 5902...) o el firewall lo bloquea. Comprobar con `netstat -ano` o `ss -ltn` en el servidor qué puerto escucha realmente |
| Funciona en la red local pero no desde fuera | Es lo esperado: el 5900 no debe estar expuesto. Entrar por VPN o túnel SSH |
| `bind [127.0.0.1]:5901: Address already in use` al abrir el túnel | El puerto local de escucha ya está en uso (otro túnel o un servidor VNC local). Elegir otro, p. ej. `5902` |
| Con el túnel abierto, el visor «se queda cargando» | El destino del `-L` (`localhost:5900`) es erróneo para ese servidor: probar con el puerto de su display real (5901, 5902...) |
| Resolución distinta o escala rara | La resolución de VNC es la del framebuffer del servidor, que puede diferir del tamaño de tu ventana. Activar «escalar a la ventana» en el visor, o cambiar la resolución en el servidor (con `Xvnc`, con la opción de geometría) |
| `host:5901` no conecta | Muchos visores interpretan el número tras `:` como display, es decir, puerto 5900+5901. Escribir `host::5901` o `host:1` |
| Contraseña rechazada con más de ocho caracteres | El RFB clásico trunca a ocho: solo cuentan los ocho primeros |

## Buenas prácticas avanzadas

- **Servidor en `localhost` y entrada por túnel** — el modo más seguro es que el servidor VNC escuche solo en el bucle local y se acceda por SSH o VPN. No expone ni siquiera en la red local un servicio con autenticación de ocho caracteres.
- **La contraseña VNC no es seguridad, es un pestillo** — ocho caracteres con DES se rompen por fuerza bruta. Usa una larga igualmente, pero considera la protección real el cifrado del túnel y el acceso a este.
- **Distingue «display» de «puerto»** — `:1` es el 5901. Aplica a visor, túnel y firewall: un túnel con `-L 5901:localhost:5900` apunta al display `:0`, no al `:1`.
- **Prefiere la sesión virtual para administración y la física solo para soporte** — compartir la pantalla física es cómodo, pero quien tiene el control puede ver todo lo que haya abierto la otra persona (correos, contraseñas). Con `Xvnc` cada uso queda aislado.
- **Cierra el servidor cuando no se use** — un servidor VNC en reposo permanente es superficie de ataque; arráncalo bajo demanda para soporte puntual y para en cuanto termine la sesión.
- **Limita el origen en el firewall** — si hay que abrir el puerto en la red local, limítalo en el firewall a las IP que lo necesiten (p. ej. solo `192.168.1.20`) en lugar de a toda la red.

## Documentación oficial

- [RFC 6143: The Remote Framebuffer Protocol](https://www.rfc-editor.org/rfc/rfc6143) — la especificación normativa de RFB: puertos (sección 2), tipos de seguridad (7.2), codificaciones (7.7).
- [TigerVNC](https://tigervnc.org/) — implementación libre de referencia en Linux; consultar el apartado de documentación para el manual de `Xvnc` y las opciones de seguridad.
- [noVNC](https://github.com/novnc/noVNC) — el visor en navegador, con instrucciones para websockify y para integrarlo en otras aplicaciones.
- [Compartir pantalla en Mac (Apple)](https://support.apple.com/guide/mac-help/turn-screen-sharing-on-or-off-mh11848/mac) — cómo activar el uso compartido de pantalla y el acceso de visores VNC con contraseña.

---

*En resumen: VNC retransmite la pantalla de un equipo a cualquier sistema operativo, pero su protección clásica es de juguete: el puerto 5900 no se expone nunca, y se entra siempre por un túnel SSH o una VPN.*
