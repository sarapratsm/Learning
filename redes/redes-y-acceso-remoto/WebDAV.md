# WebDAV

## ¿Qué es?

**WebDAV** (*Web Distributed Authoring and Versioning*) es una extensión del protocolo HTTP, definida en el [RFC 4918](https://datatracker.ietf.org/doc/html/rfc4918), que añade métodos para **listar, crear, copiar, mover y bloquear archivos y carpetas en un servidor web**. Con él, una URL deja de ser solo algo que se descarga y pasa a ser una carpeta que se puede leer y escribir.

## ¿Por qué existe?

HTTP nació para leer documentos: `GET` descarga y poco más. Existe `PUT` para subir y `DELETE` para borrar, pero no hay forma estándar de preguntar «¿qué hay en esta carpeta?», de crear un directorio o de impedir que dos personas pisen el mismo fichero a la vez. WebDAV añade esas operaciones como métodos HTTP nuevos y define un formato XML para describir carpetas y propiedades.

El resultado es una carpeta remota que viaja por el mismo canal que cualquier web, en el puerto 80 o 443. Eso resuelve dos problemas de las alternativas:

- [SMB](Carpeta-Compartida.md) está pensado para la red local y su puerto 445 no debe exponerse a internet.
- [FTP y SFTP](FTP-y-SFTP.md) transfieren ficheros, pero no se montan como una unidad más ni tienen bloqueos.

Como es HTTP, atraviesa casi cualquier firewall corporativo (que ya deja pasar 80 y 443), se cifra con TLS igual que una web y se puede poner detrás de un *reverse proxy*.

> Si ya conoces una API REST, piensa en WebDAV como una API REST estándar para ficheros: las URL son recursos, `PUT` crea o reemplaza, `DELETE` borra, y `PROPFIND` es el «listar» que HTTP no tenía. La diferencia es que está estandarizada, así que Windows, macOS, Linux y decenas de clientes ya saben hablarla.

## ¿Cuándo y para qué se usa?

Ejemplo conductor: la tienda online guarda en un servidor las facturas en PDF y las imágenes de producto, y el equipo de oficina (`192.168.1.20`) necesita abrirlas y guardarlas desde fuera de la oficina.

- **Nube propia.** Nextcloud y ownCloud exponen todos los ficheros de cada usuario por WebDAV, y muchos [NAS](NAS.md) incluyen un servidor WebDAV.
- **Unidad de red a través de internet** sin montar una [VPN](VPN.md) cuando solo hace falta acceso a ficheros.
- **Copias y sincronización con `rclone`**, que usa WebDAV como uno más de sus destinos.
- **Calendarios y contactos.** CalDAV (calendarios) y CardDAV (contactos) son extensiones de WebDAV: usan los mismos métodos y el mismo XML, y por eso un servidor Nextcloud sirve ficheros, agenda y libreta de direcciones por la misma URL base.

## Los métodos que añade

WebDAV mantiene los métodos de HTTP y suma los suyos:

| Método | Qué hace | Equivalente en un explorador de archivos |
|---|---|---|
| `GET` / `PUT` / `DELETE` | Descargar, subir (crear o reemplazar) y borrar un fichero. Ya existían en HTTP. | Copiar, pegar, borrar |
| `PROPFIND` | Devuelve propiedades (tipo, tamaño, fecha) de un recurso y, según la cabecera `Depth`, de su contenido. | Abrir una carpeta y ver la lista |
| `PROPPATCH` | Modifica propiedades de un recurso. | Cambiar atributos |
| `MKCOL` | Crea una carpeta (una *colección*, en términos de WebDAV). | Nueva carpeta |
| `COPY` / `MOVE` | Copia o mueve un recurso a otra URL, indicada en la cabecera `Destination`. | Copiar y mover |
| `LOCK` / `UNLOCK` | Bloquea un recurso para que nadie más lo modifique mientras se edita. | El aviso «el archivo está en uso» |

`OPTIONS` sirve para descubrir qué soporta el servidor: la cabecera `DAV: 1` (o `1, 2` si admite bloqueos) en la respuesta indica que habla WebDAV.

## Probarlo: un servidor mínimo y `curl`

Para ver el protocolo sin instalar nada se usa un manejador de demostración de unas 120 líneas escrito con `http.server` de Python. **Es una demostración del protocolo, no un servidor real**: no implementa `LOCK`, `COPY`, `MOVE` ni `PROPPATCH`, no tiene permisos por usuario ni TLS, y la contraseña está escrita en el código. Escucha solo en `127.0.0.1:6900`, con un único usuario `deployer` (contraseña `secreto`) y un límite de subida de 1 KiB que sirve para provocar un 413 más adelante. Salidas obtenidas el 2026-11-10 con Python 3.12 y curl 8.19.

La carpeta servida se queda vacía. Primero se pregunta qué soporta:

```bash
curl -si -X OPTIONS http://127.0.0.1:6900/
```

```text
HTTP/1.0 200 OK
Server: DemoDAV/0.1 Python/3.12.10
Content-Length: 0
DAV: 1
Allow: OPTIONS, GET, PUT, DELETE, MKCOL, PROPFIND
```

`DAV: 1` confirma que habla WebDAV y `Allow` lista los métodos habilitados. Esa lista es la que decide si luego aparece un 405.

### Crear una carpeta y subir un fichero

`MKCOL` crea la carpeta y `curl -T` (que hace un `PUT`) sube el fichero:

```bash
curl -si -u deployer:secreto -X MKCOL http://127.0.0.1:6900/pedidos/
curl -si -u deployer:secreto -T pedido-001.txt http://127.0.0.1:6900/pedidos/pedido-001.txt
curl -si -u deployer:secreto -T pedido-001.txt http://127.0.0.1:6900/pedidos/pedido-001.txt
```

```text
HTTP/1.0 201 Created
HTTP/1.0 201 Created
HTTP/1.0 204 No Content
```

`201 Created` indica que el recurso es nuevo; repetir el `PUT` sobre el mismo fichero devuelve `204 No Content` porque lo reemplaza. Subir a una carpeta que no existe (`/nada/x.txt`) devuelve `409 Conflict`: WebDAV no crea carpetas intermedias por su cuenta, hay que hacer `MKCOL` primero.

### Listar con `PROPFIND`: la respuesta 207 Multi-Status

La cabecera `Depth` controla hasta dónde se pregunta: `0` es solo el recurso, `1` el recurso y sus hijos directos.

```bash
curl -si -u deployer:secreto -X PROPFIND -H "Depth: 1" http://127.0.0.1:6900/pedidos/
```

```text
HTTP/1.0 207 Multi-Status
Content-Type: application/xml; charset="utf-8"

<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/pedidos/</D:href>
    <D:propstat><D:prop>
      <D:resourcetype><D:collection/></D:resourcetype>
      <D:getlastmodified>Tue, 10 Nov 2026 10:27:57 GMT</D:getlastmodified>
    </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
  </D:response>
  <D:response>
    <D:href>/pedidos/pedido-001.txt</D:href>
    <D:propstat><D:prop>
      <D:resourcetype></D:resourcetype>
      <D:getcontentlength>12</D:getcontentlength>
      <D:getlastmodified>Tue, 10 Nov 2026 10:27:57 GMT</D:getlastmodified>
    </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
  </D:response>
</D:multistatus>
```

(La respuesta real sale en una sola línea; aquí se ha indentado para leerla.) Cómo leerla:

- **`207 Multi-Status`** significa que el cuerpo contiene un resultado por cada recurso. Un `PROPFIND` sobre una carpeta devuelve varios recursos, y cada uno puede haber tenido un resultado distinto, por eso el código HTTP global no basta y cada `<D:response>` lleva su propio `<D:status>`.
- **`<D:resourcetype><D:collection/>`** marca una carpeta; vacío, un fichero.
- **`getcontentlength`** es el tamaño en bytes (12 = `hola tienda\n`).
- Sin cuerpo en la petición, el servidor devuelve un conjunto de propiedades por defecto. Los clientes reales envían un XML `<D:propfind>` pidiendo propiedades concretas.

### Descargar, borrar y los métodos no habilitados

```bash
curl -si -u deployer:secreto http://127.0.0.1:6900/pedidos/pedido-001.txt   # 200 OK, cuerpo "hola tienda"
curl -si -u deployer:secreto -X DELETE http://127.0.0.1:6900/pedidos/pedido-001.txt   # 204 No Content
curl -si -u deployer:secreto -X LOCK http://127.0.0.1:6900/pedidos/pedido-001.txt     # ver abajo
```

```text
HTTP/1.0 405 Method Not Allowed
Allow: OPTIONS, GET, PUT, DELETE, MKCOL, PROPFIND
```

El servidor de demostración no implementa `LOCK`, y así se ve un 405 real: la cabecera `Allow` dice qué métodos sí acepta ese recurso. Repetir un `MKCOL` sobre una carpeta que ya existe también devuelve `405`.

## Seguridad: HTTPS obligatorio

WebDAV hereda la seguridad de HTTP, y la autenticación más común (*Basic*) no cifra nada. El mismo servidor de demostración, visto con `curl -v`, envía esta cabecera:

```text
> Authorization: Basic ZGVwbG95ZXI6c2VjcmV0bw==
```

Eso es solo Base64, no cifrado:

```bash
echo ZGVwbG95ZXI6c2VjcmV0bw== | base64 -d
```

```text
deployer:secreto
```

Cualquiera que vea el tráfico (una wifi compartida, un equipo intermedio) lee usuario y contraseña. Por eso:

```text
❌ http://dav.tienda.ejemplo.com/       Basic en claro: credenciales y ficheros visibles en la red
✅ https://dav.tienda.ejemplo.com/      TLS: credenciales y contenido cifrados
```

Con TLS el servidor necesita un certificado válido (ver [HTTPS con Let's Encrypt](../../devops/despliegue-en-vps/HTTPS-con-Lets-Encrypt.md)). Además, un servidor WebDAV expuesto a internet debe tratarse como cualquier servicio público: contraseñas fuertes o tokens de aplicación, límite de intentos ([Fail2ban](../../devops/despliegue-en-vps/Fail2ban.md)) y, si solo lo usa el equipo, [VPN](VPN.md) en lugar de abrirlo al mundo.

## Montarlo en cada sistema

Esta sección no se ha ejecutado: son comandos tomados de la documentación oficial y no se han probado contra un servidor real. La URL `https://dav.tienda.ejemplo.com/` es la del ejemplo conductor y el usuario es `deployer`.

### Windows

Se puede hacer desde el Explorador (*Este equipo > Conectar a unidad de red*, con la URL `https://dav.tienda.ejemplo.com/`) o con `net use`:

```bat
net use Z: https://dav.tienda.ejemplo.com/ /user:deployer *
```

`*` hace que Windows pida la contraseña sin escribirla en el historial. Windows no habla WebDAV por sí mismo: lo hace el servicio **WebClient** (el «redirector» WebDAV). Según la [documentación de Microsoft](https://learn.microsoft.com/en-us/iis/publish/using-webdav/using-the-webdav-redirector), su comportamiento se ajusta en `HKLM\SYSTEM\CurrentControlSet\Services\WebClient\Parameters`, y los límites que más molestan son:

| Valor | Efecto | Por defecto |
|---|---|---|
| `FileSizeLimitInBytes` | Tamaño máximo de fichero que el cliente transfiere. | 50 000 000 bytes (50 MB) |
| `BasicAuthLevel` | `0`: Basic desactivado; `1`: solo sobre HTTPS; `2`: también sobre HTTP. | `1` |
| `SendReceiveTimeoutInSec` | Espera tras enviar una petición como `GET` o `PUT`. | 60 s |

Tras cambiar un valor hay que reiniciar el servicio WebClient o el equipo. Otro matiz documentado: la página de [funciones obsoletas de Windows](https://learn.microsoft.com/en-us/windows/whats-new/deprecated-features) marca el servicio WebClient (WebDAV) como obsoleto desde noviembre de 2023 y dice que **no se inicia por defecto**; un `net use` que falla puede deberse simplemente a que el servicio está parado. La misma documentación de Microsoft avisa de un riesgo con servidores Linux: Windows no distingue mayúsculas de minúsculas y un servidor Linux sí, de modo que dos ficheros que solo difieren en mayúsculas pueden pisarse.

### macOS

En Finder: *Ir > Conectarse al servidor* (`Cmd+K`) y la URL `https://dav.tienda.ejemplo.com/`. Es compatible de serie; no ejecutado.

### Linux

- **GVFS** (escritorio GNOME): *Otras ubicaciones > Conectarse al servidor* con `davs://dav.tienda.ejemplo.com/`, o `gio mount davs://dav.tienda.ejemplo.com/` por terminal (`davs` es WebDAV sobre TLS).
- **davfs2**: monta la URL como un sistema de ficheros con `mount -t davfs`, p. ej. `sudo mount -t davfs https://dav.tienda.ejemplo.com/ /mnt/tienda`. Mantiene una caché local y sube los cambios con retraso; no ejecutado.

### Clientes de línea de comandos y gráficos

- **`rclone`**: configurado con `rclone config` (tipo `webdav`, con `vendor` de `nextcloud`, `owncloud` u otro si procede) permite `rclone ls tienda:`, `rclone copy`, `rclone sync` y `rclone mount`. Es la opción más robusta para tareas automáticas; ver [su documentación de WebDAV](https://rclone.org/webdav/).
- **`cadaver`**: cliente interactivo tipo `ftp` (`cadaver https://dav.tienda.ejemplo.com/`, con `ls`, `put`, `mkcol`), útil para depurar un servidor.
- **Cyberduck** (y similares con interfaz gráfica): conectan por WebDAV (HTTPS) con perfil guardado.

## Servidores

| Servidor | Cómo ofrece WebDAV | Notas |
|---|---|---|
| **Nextcloud / ownCloud** | Viene activado. La URL de ficheros de cada usuario cuelga de `/remote.php/dav/files/<usuario>/`. | Incluye también CalDAV y CardDAV. Con doble factor, el cliente WebDAV necesita una contraseña de aplicación. |
| **Apache** | Módulos `mod_dav` y `mod_dav_fs`; la directiva `Dav On` en un `<Directory>` o `<Location>`. | Solución completa, con `LOCK` (`DAVLockDB`). Ver [mod_dav](https://httpd.apache.org/docs/2.4/mod/mod_dav.html). |
| **nginx** | Módulo `ngx_http_dav_module`, que **no está compilado por defecto** (requiere `--with-http_dav_module`). | Solo implementa `PUT`, `DELETE`, `MKCOL`, `COPY` y `MOVE`: sin `PROPFIND` ni `LOCK`, los clientes de escritorio no listan carpetas. Para eso hace falta el módulo externo `nginx-dav-ext-module`. Ver [documentación](https://nginx.org/en/docs/http/ngx_http_dav_module.html). |
| **NAS** | Interruptor en el panel del fabricante. | Comprueba que el servicio se publica por HTTPS y no solo por HTTP. |

Configuración de Apache (no ejecutada), con TLS, autenticación y escritura solo para usuarios válidos:

```apache
DavLockDB /var/lib/apache2/davlock
<Location "/ficheros">
    Dav On
    AuthType Basic
    AuthName "Ficheros de la tienda"
    AuthUserFile /etc/apache2/webdav.passwd
    Require valid-user
</Location>
```

Esa configuración solo es segura dentro de un `VirtualHost *:443` con certificado; en el 80 enviaría la contraseña en claro.

## Errores frecuentes

| Síntoma | Causa y arreglo |
|---|---|
| `405 Method Not Allowed` (observado con `LOCK` y `MKCOL` repetido) | El método no está habilitado en ese servidor o recurso. La cabecera `Allow` de la respuesta lista los admitidos. En nginx típico faltan `PROPFIND` y `LOCK` (módulo `dav_ext`); en Apache, falta `Dav On`. Con `MKCOL`, también aparece si la carpeta ya existe. |
| `401 Unauthorized` con `WWW-Authenticate: Basic` (observado) | Faltan credenciales o son incorrectas. Si el cliente se niega a enviarlas, comprueba que la URL es `https://`: Windows no manda Basic por HTTP con la configuración por defecto (`BasicAuthLevel = 1`). |
| `409 Conflict` al subir (observado) | La carpeta destino no existe. WebDAV no crea intermedias; usar `MKCOL` primero. |
| `413 Request Entity Too Large` (observado con el límite de 1 KiB del servidor de demostración) | El servidor o un proxy delante limita el cuerpo. En nginx, `client_max_body_size`; en Apache, `LimitRequestBody`; en Nextcloud, también los límites de PHP. Distinto del 50 MB del cliente Windows, que falla en el cliente, sin llegar a pedir nada. |
| Windows: error `0x800700DF` («el tamaño del archivo supera el límite permitido») | Límite `FileSizeLimitInBytes` del cliente WebClient (50 MB por defecto, según la documentación de Microsoft). Se sube el valor en el registro y se reinicia el servicio WebClient. Para ficheros grandes, mejor un cliente como `rclone`. |
| Windows: `Error de sistema 67. No se encuentra el nombre de red` o «carpeta no accesible» | Documentado por Microsoft: servicio WebClient parado, WebDAV no activado en el servidor, o Basic sobre HTTP. Comprobar `sc query WebClient`, la URL en HTTPS y que el servidor responde a `PROPFIND`. |
| Windows: `Error de sistema 224` | El sitio no está en la lista de sitios de confianza de Windows (Opciones de Internet). Se añade ahí. |
| El Explorador carga la carpeta pero no lista nada o va muy lento | El servidor no implementa `PROPFIND` correctamente o con `Depth: 1`; es frecuente con nginx sin `dav_ext`. Probar con `curl -X PROPFIND` como arriba. |

## Cuándo usar WebDAV, SMB, SFTP o un NAS

| Necesidad | Mejor opción | Por qué |
|---|---|---|
| Compartir carpetas en la red local de la oficina | [SMB](Carpeta-Compartida.md) | Más rápido, integrado en Windows, con permisos por usuario. |
| Disco compartido central con copias y RAID | [NAS](NAS.md) | El hardware dedicado; el NAS puede ofrecer SMB y WebDAV a la vez. |
| Subir y bajar ficheros a un servidor, scripts, despliegues | [SFTP](FTP-y-SFTP.md) | Un solo puerto cifrado, claves SSH y ningún servicio web que mantener. |
| Acceso a ficheros por internet desde cualquier equipo, atravesando firewalls y proxys | **WebDAV sobre HTTPS** | Usa 443 y TLS, y se monta como unidad. |
| Calendarios y contactos sincronizados | CalDAV / CardDAV (Nextcloud) | Son estándares hermanos de WebDAV. |
| Acceso total a la red interna (impresoras, bases de datos, SMB) | [VPN](VPN.md) | Un túnel para todo, en lugar de un servicio expuesto por aplicación. |

WebDAV no es buena opción para un directorio con miles de ficheros pequeños (cada fichero es una petición HTTP), ni para editar a la vez el mismo fichero varias personas sin soporte de `LOCK`, ni como sustituto de una sincronización: monta el remoto, no mantiene una copia local al día. Los clientes de Nextcloud y `rclone sync` cubren esa necesidad.

## Buenas prácticas avanzadas

- **Cierra HTTP del todo, no solo recomiendes HTTPS.** Redirigir el 80 al 443 no basta si un cliente ya envió la primera petición con `Authorization: Basic` por HTTP: la contraseña ya viajó. Para un servidor solo WebDAV, rechaza el puerto 80 o activa HSTS y no publiques nunca enlaces `http://`.
- **Usa contraseñas de aplicación o tokens por cliente.** Basic exige enviar la contraseña en cada petición; si cada dispositivo tiene la suya (Nextcloud las genera), una portátil perdida se revoca sin cambiar la contraseña principal ni cortar al resto.
- **Limita el alcance del usuario WebDAV.** Una cuenta que solo escribe en `/ficheros/facturas/` y no puede salir de ahí; en Apache o nginx, que la carpeta servida no incluya claves, `.env` ni copias de seguridad de la base de datos.
- **No dejes `PROPFIND` con `Depth: infinity` abierto.** En un árbol grande, un cliente (o un atacante) obliga al servidor a recorrer y describir todo el árbol de una vez. Apache lo controla con `DavDepthInfinity` (desactivado por defecto) y varios servidores lo devuelven como 403.
- **Eleva los límites en toda la cadena, no solo en un punto.** Un fichero grande atraviesa cliente (50 MB en Windows), proxy inverso, servidor web y aplicación (PHP en Nextcloud), y el 413 lo puede dar cualquiera. Cuando falla, `curl -T` contra el servidor directo y luego a través del proxy localiza el eslabón.
- **Ten claro que el cliente de Windows es el eslabón débil.** Está marcado como obsoleto por Microsoft y depende de un servicio que no arranca por defecto. Para automatizar o mover ficheros grandes, `rclone` evita todas esas trampas.

## Documentación oficial

- [RFC 4918: HTTP Extensions for Web Distributed Authoring and Versioning](https://datatracker.ietf.org/doc/html/rfc4918) — la especificación; la sección de `PROPFIND` y la de códigos 207 y 423 responden las dudas de formato.
- [Using the WebDAV Redirector (Microsoft)](https://learn.microsoft.com/en-us/iis/publish/using-webdav/using-the-webdav-redirector) — cómo monta Windows una unidad WebDAV, errores de sistema y tabla completa de valores de registro de WebClient.
- [mod_dav (Apache)](https://httpd.apache.org/docs/2.4/mod/mod_dav.html) y [ngx_http_dav_module (nginx)](https://nginx.org/en/docs/http/ngx_http_dav_module.html) — directivas de cada servidor y los métodos que implementan.
- [Acceso por WebDAV en Nextcloud](https://docs.nextcloud.com/server/latest/user_manual/en/files/access_webdav.html) — URL de cada usuario, clientes y límites.

## Recursos didácticos

- [rclone: WebDAV](https://rclone.org/webdav/) — cómo configurar un remoto WebDAV y las opciones por proveedor (Nextcloud, ownCloud, SharePoint...).
- [http.cat/405](https://http.cat/405) — el error 405, con gato.

---

*En resumen: WebDAV es HTTP con métodos extra (`PROPFIND`, `MKCOL`, `MOVE`...) para tratar una URL como una carpeta; funciona por el 443 y se monta como una unidad de red, pero solo es seguro con HTTPS y el cliente de Windows tiene límites que conviene conocer.*
