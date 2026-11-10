# Conexiones — Guía de tecnologías

Guía sobre las formas más habituales de **conectar equipos entre sí y compartir archivos** a través de la red: escritorio remoto, control remoto comercial, SSH, carpetas compartidas, NAS, transferencia de ficheros, VPN y redirección de puertos. Parte de cómo se localizan los equipos (IP, puertos, NAT) y termina en cómo acceder desde fuera sin abrir más de lo necesario.

El criterio de seguridad recorre todas las fichas: qué queda expuesto a internet con cada tecnología y qué alternativa lo evita. Los ejemplos comparten un escenario: una oficina de la tienda online con red local `192.168.1.0/24`, un equipo de trabajo en `192.168.1.20`, un NAS en `192.168.1.50` y un VPS en `203.0.113.10`. Las direcciones públicas son de los rangos reservados para documentación (RFC 5737).

---

## Orden de lectura recomendado

### 1. Fundamentos

Antes de conectar nada, cómo se localizan los equipos en la red.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Red local e IP](Red-local-e-IP.md) | La base de todo: IP, máscara, puertos, NAT y DNS. El resto de las fichas se apoya en estos términos. |

### 2. Controlar otro equipo

Conectarse a una máquina para usarla como si se estuviera delante.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 2 | [Escritorio Remoto (RDP)](Escritorio-Remoto.md) | Ver y manejar la pantalla de otro equipo Windows, y por qué el puerto 3389 no se abre a internet. |
| 3 | [VNC](VNC.md) | La alternativa multiplataforma: comparte la pantalla en vez de abrir una sesión propia, con una autenticación que obliga a protegerla con un túnel. |
| 4 | [Herramientas de Control Remoto](Herramientas-de-Control-Remoto.md) | TeamViewer, AnyDesk, RustDesk y Quick Assist: conexión saliente a un intermediario, sin tocar el router. |
| 5 | [SSH](SSH.md) | Terminal remota cifrada, claves, túneles y el fichero `config`. Imprescindible para servidores. |

### 3. Compartir archivos

Poner ficheros en común entre varios equipos.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 6 | [Carpeta Compartida (SMB)](Carpeta-Compartida.md) | La forma clásica de compartir una carpeta en la red local, y por qué el puerto 445 nunca sale a internet. |
| 7 | [NAS](NAS.md) | Un disco compartido dedicado para toda la red, y la diferencia entre RAID y copia de seguridad. |
| 8 | [FTP y SFTP](FTP-y-SFTP.md) | Subir y bajar ficheros contra un servidor: por qué FTP plano no se usa y qué lo sustituye. |
| 9 | [WebDAV](WebDAV.md) | Carpetas remotas sobre HTTP(S), montadas como una unidad más. |

### 4. Acceso seguro desde fuera

Cómo usar todo lo anterior desde fuera de la red local sin abrir agujeros.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 10 | [VPN](VPN.md) | Una sola puerta cifrada hacia la red remota. La opción recomendada para acceder desde fuera. |
| 11 | [Redirección de Puertos](Redireccion-de-Puertos.md) | La alternativa para exponer un servicio concreto a internet, con sus riesgos; incluye CGNAT y las alternativas más seguras. |

---

## Qué tecnología elegir

| Si hace falta… | Opción | Qué se expone a internet |
|---|---|---|
| Ver la pantalla de un equipo Windows de la oficina desde casa | [RDP](Escritorio-Remoto.md) detrás de una [VPN](VPN.md) | Solo el puerto UDP de la VPN |
| Ayudar puntualmente a alguien sin tocar su router | [Herramienta de control remoto](Herramientas-de-Control-Remoto.md) | Nada: la conexión es saliente |
| Administrar un servidor Linux | [SSH](SSH.md) con clave | El puerto 22, con endurecimiento (ver [Acceso SSH seguro](../../devops/despliegue-en-vps/Acceso-SSH-Seguro.md)) |
| Compartir una carpeta entre equipos de la oficina | [SMB](Carpeta-Compartida.md) o un [NAS](NAS.md) | Nada |
| Subir ficheros a un servidor | [SFTP](FTP-y-SFTP.md) | El mismo puerto 22 de SSH |
| Montar una carpeta remota a través de proxys corporativos | [WebDAV](WebDAV.md) sobre HTTPS | El puerto 443 |
| Entrar a toda la red de la oficina | [VPN](VPN.md) | Solo el puerto de la VPN |
| Publicar un servicio web | [Redirección de puertos](Redireccion-de-Puertos.md) o un VPS | Solo ese servicio |

---

> Los mismos conceptos aplicados a un servidor real están en [Despliegue en un VPS](../../devops/despliegue-en-vps/README.md): endurecimiento de SSH, cortafuegos, [WireGuard](../../devops/despliegue-en-vps/WireGuard.md) y DNS interno. Para el trabajo en equipo sobre el código una vez conectado, la guía de [Git](../../devops/git/README.md).
