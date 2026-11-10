# NAS

## ¿Qué es?

Un **NAS** (*Network Attached Storage*, «almacenamiento conectado a la red») es un pequeño ordenador dedicado a una sola tarea: guardar archivos en uno o varios discos y servirlos por la red a los demás equipos. Lleva su propio sistema operativo, su propia tarjeta de red y un panel web de administración, y está pensado para estar encendido siempre.

## ¿Por qué existe?

Guardar los archivos importantes de una oficina en el disco de un portátil es frágil: si el portátil se rompe, se pierde o lo roban, los archivos se van con él. Compartir una carpeta desde el PC de alguien resuelve la parte de «verlos todos», pero obliga a que ese PC esté encendido, y además mezcla el trabajo diario de esa persona con el papel de servidor. Un disco USB enchufado a un equipo tiene el mismo problema: depende de ese equipo.

El NAS separa el almacenamiento de los equipos de trabajo. Es un aparato aparte, con varios discos para sobrevivir a averías, que entiende de usuarios y permisos, y al que se llega por red desde cualquier dispositivo autorizado.

> Piensa en el NAS como «tu propia nube»: lo que Dropbox o Google Drive ofrecen como servicio, pero con el aparato en tu oficina y los datos bajo tu control (y tu responsabilidad).

## ¿Cuándo y para qué se usa?

Ejemplo conductor: la tienda online tiene una pequeña oficina con red `192.168.1.0/24`. El equipo de oficina es `192.168.1.20` y el NAS es `192.168.1.50`.

- **Almacén central de archivos** del equipo: catálogos, fotos de producto, facturas escaneadas. Todos guardan en un sitio.
- **Destino de copias de seguridad** de los equipos de la oficina (y, con cuidado, de las bases de datos del servidor; ver [Copias de seguridad](../../devops/despliegue-en-vps/Copias-de-Seguridad.md)).
- **Servidor multimedia** o de fotos, con aplicaciones que el fabricante instala sobre el NAS.
- **Acceso remoto controlado** a esos archivos desde fuera de la oficina, por [VPN](VPN.md).

---

## NAS frente a otras formas de guardar archivos

La diferencia está en **quién habla con el disco** y **a qué nivel**. En un NAS, el equipo cliente pide *archivos* («dame `facturas/2026/F-001.pdf`») y el NAS decide cómo y dónde están en el disco. En un SAN o en un disco directo, el equipo cliente ve un *disco en bruto* y pone su propio sistema de archivos encima.

| Opción | Qué es | Se comparte por | Depende de un PC encendido | RAID y permisos propios | Uso típico |
|---|---|---|---|---|---|
| Disco USB | Un disco enchufado a un equipo | No se comparte (salvo que ese equipo lo comparta) | Sí | No | Copia puntual, transportar datos |
| Carpeta compartida de un PC | Una carpeta de Windows expuesta por [SMB](Carpeta-Compartida.md) | Red local | **Sí** | Solo permisos de Windows | Pasar archivos en un equipo pequeño |
| **NAS** | Aparato dedicado con discos, sistema operativo y servicios de red | SMB, NFS, SFTP, WebDAV... (archivos) | **No** | Sí: RAID, usuarios, instantáneas | Almacén común y destino de copias |
| DAS (*Direct Attached Storage*) | Cabina de discos conectada directamente a un servidor (USB, SAS, eSATA) | No: la ve un solo servidor | Sí (el servidor) | A veces RAID | Ampliar el disco de un servidor |
| SAN (*Storage Area Network*) | Red dedicada que entrega *discos en bruto* (bloques) a servidores, normalmente por iSCSI o Fibre Channel | Bloques, no archivos | No | Sí, a escala empresarial | Virtualización y bases de datos en centros de datos |

Un NAS doméstico o de oficina también puede ofrecer **iSCSI** (el protocolo típico de un SAN): entrega un volumen en bruto a un servidor, que lo formatea como si fuera un disco local. Es una función avanzada; para guardar archivos de oficina basta con las carpetas compartidas.

## Los protocolos con los que habla

Un NAS no inventa ningún protocolo: reutiliza los de siempre. Por eso se usa igual que cualquier otro servidor de archivos. Los puertos de la tabla son los habituales de un NAS Synology (documentación de Synology, «What network ports are used by Synology services», consultada el 2026-11-10); otras marcas usan otros puertos de administración.

| Protocolo | Para qué | Puerto | Ficha |
|---|---|---|---|
| SMB | Carpetas compartidas con Windows y macOS: el acceso diario de la oficina | 445/tcp | [Carpeta compartida](Carpeta-Compartida.md) |
| NFS | Carpetas compartidas con Linux y servidores | 2049 | (mención) |
| SFTP | Subir y bajar archivos con cifrado, sobre SSH | 22/tcp | [FTP y SFTP](FTP-y-SFTP.md) |
| WebDAV | Montar carpetas remotas sobre HTTP(S) | 5005 / 5006 (Synology) | [WebDAV](WebDAV.md) |
| iSCSI | Entregar un volumen en bruto a un servidor | 3260/tcp | (mención) |
| HTTP / HTTPS del panel | Administrar el NAS desde el navegador | 5000 / 5001 (Synology) | (panel del NAS) |

Conviene activar solo los servicios que se usan: cada servicio activo es una puerta más.

El panel de administración se abre escribiendo la dirección del NAS en el navegador y es la zona más delicada: desde ahí se crean usuarios, se borran volúmenes y se instalan aplicaciones.

```text
https://192.168.1.50:5001      panel de administración (HTTPS)
\\192.168.1.50\facturas        carpeta compartida por SMB desde Windows
```

---

## RAID: tolerar averías de disco

**RAID** (*Redundant Array of Independent Disks*) combina varios discos en un único volumen. Según cómo los combine («nivel»), reparte los datos para ir más rápido, o guarda copias o información de paridad para que el volumen siga funcionando cuando un disco falla.

- **Paridad**: información calculada a partir de los datos de los demás discos que permite reconstruir el contenido de un disco perdido.
- **Volumen degradado**: el RAID sigue funcionando con un disco menos, sin redundancia hasta que se reconstruya.
- **Reconstrucción** (*rebuild*): al sustituir el disco averiado, el NAS lee los discos supervivientes enteros para regenerar el contenido del nuevo.

### Los niveles habituales, con cuatro discos de 4 TB

El script usa 4 discos de 4 TB (16 TB brutos) y aplica la fórmula de capacidad de cada nivel:

```python
n, tb = 4, 4
niveles = {
 "RAID 0":  (n*tb,       "0 discos"),
 "RAID 1":  (tb,         f"{n-1} discos (espejo de {n} copias)"),
 "RAID 5":  ((n-1)*tb,   "1 disco"),
 "RAID 6":  ((n-2)*tb,   "2 discos"),
 "RAID 10": ((n//2)*tb,  "1 por espejo (2 si son de pares distintos)"),
}
total = n*tb
print(f"{n} discos de {tb} TB = {total} TB brutos")
for k,(u,t) in niveles.items():
    print(f"{k:8} util={u:2d} TB ({u/total:4.0%})  tolera: {t}")
```

Salida obtenida el 2026-11-10 con Python 3.12:

```text
4 discos de 4 TB = 16 TB brutos
RAID 0   util=16 TB (100%)  tolera: 0 discos
RAID 1   util= 4 TB ( 25%)  tolera: 3 discos (espejo de 4 copias)
RAID 5   util=12 TB ( 75%)  tolera: 1 disco
RAID 6   util= 8 TB ( 50%)  tolera: 2 discos
RAID 10  util= 8 TB ( 50%)  tolera: 1 por espejo (2 si son de pares distintos)
```

| Nivel | Cómo reparte | Capacidad útil (4 × 4 TB) | Fallos que tolera | Para qué |
|---|---|---|---|---|
| RAID 0 | Reparte los datos a rayas, sin redundancia | 16 TB | **Ninguno**: si falla un disco, se pierde todo | Velocidad con datos desechables |
| RAID 1 | Espejo: cada disco guarda lo mismo | 4 TB | Todos menos uno | Pocos discos (dos es lo habitual) y datos críticos pequeños |
| RAID 5 | Rayas con una paridad repartida | 12 TB | 1 disco | Compromiso capacidad/seguridad con discos pequeños |
| RAID 6 | Rayas con dos paridades | 8 TB | 2 discos | Discos grandes o datos que importan |
| RAID 10 | Espejos de pares, repartidos en rayas | 8 TB | 1 con certeza; 2 si no son del mismo par | Rendimiento y reconstrucción rápida |

La regla general: RAID 5 pierde un disco de capacidad, RAID 6 pierde dos; RAID 1 y RAID 10 pierden la mitad. Las implementaciones de ZFS llaman a esos niveles `mirror`, `raidz1` (una paridad), `raidz2` (dos) y `raidz3` (tres): la documentación de OpenZFS describe que un grupo con N discos de tamaño X y P de paridad guarda aproximadamente (N−P)·X.

Algunos fabricantes ofrecen niveles propios que funcionan como RAID 5 o 6 con discos de tamaños distintos (en Synology, SHR y SHR-2). Conviene mirar la ficha del fabricante antes de elegir.

### RAID 5 con discos grandes: el riesgo de la reconstrucción

Reconstruir un RAID 5 obliga a **leer completos todos los discos que quedan**. En el ejemplo son 3 discos × 4 TB = 12 TB. Si durante esa lectura un sector de uno de los discos supervivientes no se puede leer (un error de lectura irrecuperable o *URE*), la reconstrucción falla: ya no hay una segunda paridad que lo supla.

Las hojas de especificaciones indican una tasa de URE de 1 error por cada 10^14 bits leídos en discos de consumo y de 1 por 10^15 en muchos discos para NAS. Con esas tasas, el cálculo de probabilidad de leer 12 TB sin ningún error (modelo simplificado de Poisson):

```text
URE 1 por 1e+14 bits: lee 12 TB, errores esperados 0.96, P(sin error) 38%
URE 1 por 1e+15 bits: lee 12 TB, errores esperados 0.10, P(sin error) 91%
```

Salida del mismo script (obtenida el 2026-11-10). Es una cota pesimista basada en la cifra de catálogo, no una medición: en la práctica los discos suelen comportarse mejor que su hoja de especificaciones. Pero explica por qué el criterio extendido (en las guías y foros de fabricantes; la capacidad a partir de la cual se recomienda cambiar varía según la fuente) es usar **RAID 6 o equivalente (SHR-2)** con discos grandes o con datos que importan, y no confiar en un RAID 5 sin copia aparte.

### Un RAID bien montado se vigila

El RAID solo ayuda si se detecta el primer disco averiado antes de que falle el segundo. Esto se hace con avisos por correo del NAS y con pruebas periódicas:

- **S.M.A.R.T.**: los discos reportan su propio estado (sectores reasignados, temperatura). Los paneles de los NAS programan pruebas periódicas.
- **Scrubbing** (verificación de datos): lectura completa del volumen para detectar sectores dañados y repararlos mientras aún hay redundancia. En Btrfs, el *scrub* repara automáticamente solo si hay una réplica buena; en un volumen sin redundancia solo informa.

En un NAS Linux con `mdadm`, el estado del RAID se lee sin modificar nada. No se ejecutó (no había ningún NAS disponible):

```bash
# no ejecutado: lectura del estado del RAID por software de Linux
cat /proc/mdstat
```

---

## RAID no es una copia de seguridad

El RAID protege de **una cosa**: que un disco físico muera. Todo lo demás lo replica al instante en todos los discos.

| Qué pasa | ¿Lo cubre el RAID? | Por qué |
|---|---|---|
| Un disco se avería | **Sí** | Es para lo que sirve |
| Alguien borra `facturas/2026` por error | **No** | El borrado se aplica en todos los discos a la vez |
| Ransomware cifra la carpeta compartida | **No** | Los archivos cifrados son ahora «los datos válidos» en todos los discos |
| El controlador o la placa del NAS fallan y corrompen datos | **No** | Escribe basura de forma consistente en todos los discos |
| Corte de luz a mitad de escritura | **Parcialmente** | Puede dejar el volumen inconsistente; un SAI lo evita |
| Incendio, robo o inundación de la oficina | **No** | Todos los discos están en el mismo sitio |
| Dos discos fallan a la vez (o uno durante la reconstrucción) | **No** (en RAID 5) | Supera la redundancia |

### La regla 3-2-1

La guía de la CISA para pequeñas empresas («Back Up Business Data», consultada el 2026-11-10) resume la copia de seguridad como una regla:

- **3** copias de los archivos importantes (el original y dos más).
- **2** tipos de soporte distintos (por ejemplo, el NAS y un disco externo, o el NAS y la nube).
- **1** copia fuera del sitio, lejos de la oficina.

El mismo documento recomienda proteger las copias con acceso físico restringido, cifrado y **copias sin conexión**, y probar las restauraciones periódicamente. Sin la prueba de restauración, la copia es una suposición.

Aplicado a la tienda: los archivos de trabajo (copia 1) están en el NAS, que ya no es «el único sitio»; el NAS copia por la noche a un disco USB que se desconecta y se guarda fuera de la oficina (copia 2, otro soporte); y otra copia cifrada sale a un servicio en la nube (copia 3, fuera del sitio).

### Instantáneas (*snapshots*)

Una **instantánea** es una fotografía de solo lectura del estado de una carpeta o volumen en un momento dado. Es instantánea y ocupa poco, porque solo guarda lo que cambia después (dependen de los sistemas de archivos de copia en escritura que se describen abajo).

Sirven para deshacer: el viernes se borra una carpeta por error y se recupera la versión del jueves a las 23:00. Frente al ransomware ayudan porque las instantáneas no son carpetas a las que el equipo infectado pueda escribir. Pero **viven en el mismo NAS**: no sustituyen a la copia fuera del sitio, y si alguien con la cuenta de administrador las borra, desaparecen. Las instantáneas inmutables (que ni el administrador puede borrar durante un plazo) existen en algunos fabricantes; hay que comprobar el modelo.

---

## Sistemas de archivos del NAS

El **sistema de archivos** es la forma en que el NAS organiza los datos dentro del volumen. La diferencia práctica entre los habituales está en dos capacidades: detectar datos corruptos (*checksums*) y hacer instantáneas.

| Sistema | Origen | Qué aporta | Qué le falta o qué vigilar |
|---|---|---|---|
| **ext4** | Linux | Muy maduro y estable; diario (*journaling*) que protege los metadatos ante cortes de luz. | Sin instantáneas propias; no verifica el contenido de los datos. |
| **Btrfs** | Linux | Copia en escritura, instantáneas, sumas de verificación de datos y metadatos, *scrub*. | RAID 5/6 propio de Btrfs marcado como inestable (ver abajo). |
| **ZFS** | OpenZFS (Linux, FreeBSD) | Sumas de verificación, instantáneas, gestión de discos y RAID integrados (`mirror`, `raidz1/2/3`). | Necesita memoria y planificación; mayor curva de aprendizaje. |
| **ReFS** | Microsoft | Sumas de verificación y reparación automática cuando se combina con Storage Spaces con espejo o paridad. | Pensado para Windows Server; no es el sistema de un NAS comercial típico. |

- **Copia en escritura** (*copy-on-write*): en lugar de sobreescribir un bloque, se escribe el nuevo en otro sitio y se actualiza la referencia. Es lo que hace baratas las instantáneas y evita estados a medias tras un corte de luz.
- **Checksum**: cada bloque lleva una huella; al leerlo se comprueba. Si no coincide y hay una copia buena (espejo o paridad), el sistema repara en caliente. Sin esto, un disco que devuelve datos erróneos *sin avisar* (corrupción silenciosa) pasa inadvertido.

Estado a 2026-11-10 según la documentación oficial leída:

- **Btrfs**: la página de estado lo marca como OK para subvolúmenes, instantáneas, *scrub*, RAID1 y RAID10, y **inestable para RAID56**, con la advertencia de que las funciones inestables deben usarse solo para pruebas (problemas graves conocidos y partes del núcleo sin implementar). Por eso los NAS que usan Btrfs lo combinan con el RAID de Linux por debajo en lugar de usar el RAID 5/6 propio de Btrfs.
- **ZFS**: sigue activo como OpenZFS (la documentación publica la versión 2.4 y la rama `master`) en Linux y FreeBSD.
- **ReFS**: Microsoft lo documenta como orientado a Windows Server, con corrección de corrupción en caliente solo con Storage Spaces; para uso general mantiene NTFS.

---

## Acceso remoto seguro al NAS

El NAS contiene los datos de la empresa y un panel que puede borrarlos. Es un objetivo muy buscado por campañas automatizadas que prueban contraseñas por defecto y fallos conocidos del panel y de los servicios de archivos.

| Exposición | ¿Aceptable? | Motivo |
|---|---|---|
| Acceso por VPN a la red local | **Sí, la forma recomendada** | Desde fuera, el equipo entra a la red y usa el NAS como en la oficina. No se publica nada del NAS |
| Redirigir el 445 (SMB) del router al NAS | **Nunca** | SMB está pensado para redes de confianza, no para internet |
| Redirigir 5000/5001 (panel) | **No** | Expone la administración a todo internet |
| Servicio en la nube del fabricante (QuickConnect y similares) | Con reservas | Ver más abajo |
| WebDAV/SFTP expuestos con HTTPS, usuarios dedicados y bloqueo de intentos | Solo si hay motivo de peso | Es una superficie más |

```text
❌ Router: TCP 445   → 192.168.1.50:445     (SMB abierto a internet)
❌ Router: TCP 5000  → 192.168.1.50:5000    (panel sin HTTPS, accesible desde fuera)
✅ Router: UDP 51820 → servidor VPN         (solo el puerto de la VPN; el NAS se alcanza por dentro)
```

La alternativa correcta es la [VPN](VPN.md): una vez conectada, la persona remota usa la misma dirección `192.168.1.50` que en la oficina. Cómo montarla en un servidor propio está en [WireGuard](../../devops/despliegue-en-vps/WireGuard.md), y por qué las redirecciones son una exposición real, en [Redirección de puertos](Redireccion-de-Puertos.md). Quien necesite abrir una sesión de terminal en el NAS puede hacerlo por [SSH](SSH.md), también por dentro de la VPN.

### Los servicios en la nube del fabricante

Servicios como **QuickConnect** (Synology) o equivalentes de otras marcas permiten acceder al NAS desde fuera sin abrir puertos en el router. El NAS abre una conexión *saliente* hacia los servidores del fabricante y el cliente llega por ahí. Según el *white paper* de QuickConnect (resumen obtenido por búsqueda; el cuerpo del documento no se pudo leer directamente), el cliente intenta primero LAN y WAN, luego perforación de NAT (*hole punching*) y, solo si fallan, un **servidor de relé** del fabricante por el que pasa el tráfico.

Qué implica:

- **Ventaja**: funciona detrás de CGNAT y sin tocar el router; es cómodo.
- **Riesgo 1**: el tráfico puede pasar por infraestructura de un tercero. Habría que confiar en el fabricante y en su cifrado.
- **Riesgo 2**: el acceso depende de que la cuenta del fabricante y su servicio sigan funcionando, y de una contraseña más que proteger (con verificación en dos pasos).
- **Riesgo 3**: es una puerta de entrada más, protegida solo por las credenciales de ese servicio.

Si se usa, conviene limitarlo a los servicios necesarios, activar la verificación en dos pasos y mantener el firmware al día. Si la VPN es viable, es la opción preferible.

---

## Usuarios y permisos

Un NAS distingue usuarios igual que un servidor. El esquema que funciona:

1. **Una cuenta por persona**, con su contraseña. Nada de una cuenta compartida «oficina».
2. **Permisos por grupo**: `contabilidad` ve `facturas`; `tienda` ve `catalogo`. Se asigna a las personas a los grupos.
3. **Lectura/escritura solo donde hace falta**: quien consulta, no escribe.
4. **Cuentas de servicio separadas** para las copias y los programas, con acceso solo a su carpeta.
5. **Administrador**: una cuenta propia con otro nombre, no la `admin` de fábrica (que se desactiva), usada solo para administrar.

Un detalle de seguridad: el permiso de escritura en una carpeta es exactamente lo que un ransomware hereda cuando infecta un equipo. Cuanto más estrecho es el permiso, menos daño puede hacer.

## Qué usar según la situación

| Situación | Opción razonable | Por qué |
|---|---|---|
| Una persona, pocos archivos, copia de seguridad ocasional | Disco USB o nube | Un NAS es más de lo que hace falta |
| Equipo pequeño que comparte documentos, sin criticidad | Carpeta compartida de un PC o nube con sincronización | Sin coste y sin mantenimiento |
| Oficina que necesita un almacén común siempre disponible, con permisos y copias | **NAS** (con copia externa) | Es el caso para el que existe |
| Acceso desde muchos sitios, sin nadie que mantenga la infraestructura | Nube (Drive, OneDrive, Dropbox...) | El proveedor se encarga de la disponibilidad y de los fallos de hardware |
| Aplicaciones, bases de datos, contenedores | Servidor casero o VPS | Un NAS está optimizado para archivos, no para cómputo |
| Datos críticos de la empresa | NAS **más** copia fuera del sitio | El NAS solo no cumple 3-2-1 |

El NAS cuesta tiempo además de dinero: alguien debe actualizar el firmware, vigilar los discos y probar las restauraciones. Si nadie va a hacer eso, la nube suele ser más segura que un NAS abandonado.

---

## Errores frecuentes

### «No veo el NAS desde mi equipo»

Síntoma: `\\192.168.1.50` no abre, o el navegador no carga el panel.

Causa habitual: el equipo y el NAS están en **subredes distintas** (por ejemplo, el equipo en `192.168.2.x` por un segundo router o un punto de acceso en modo router, o conectado a la red de invitados). Se comprueba la dirección y la máscara del equipo con una orden de solo lectura. La orden se ejecutó el 2026-11-10 y su salida real tiene este formato; las direcciones están sustituidas por las del ejemplo conductor:

```text
C:\> ipconfig
   Dirección IPv4. . . . . . . . . . . . . . : 192.168.1.20
   Máscara de subred . . . . . . . . . . . . : 255.255.255.0
   Puerta de enlace predeterminada . . . . . : 192.168.1.1
```

Si la IPv4 del equipo no empieza por `192.168.1.`, no está en la misma red que el NAS: hay que moverlo a la red correcta o usar la [VPN](VPN.md) / una ruta entre redes. El fundamento (máscara, subred, puerta de enlace) está en [Red local e IP](Red-local-e-IP.md).

### «Falló la reconstrucción del RAID»

Síntoma: se sustituye el disco averiado de un RAID 5, la reconstrucción arranca y el NAS informa de que el volumen se ha caído o está en estado de error.

Causa: un **segundo disco** tenía un sector ilegible, o falló bajo el esfuerzo de leerse entero (ver el cálculo de arriba). Con RAID 5 no hay paridad extra que lo cubra. Prevención: RAID 6 o equivalente con discos grandes, *scrubbing* periódico para detectar sectores malos antes de necesitarlos, discos de lotes o edades distintas y, sobre todo, una copia fuera del NAS. **Recuperación**: restaurar desde la copia de seguridad; no se debe reintentar a ciegas, porque cada intento estresa más los discos.

### «Se borró una carpeta y el RAID no la tiene»

Síntoma: alguien borró `facturas` y se piensa en el disco de repuesto. Causa: el RAID replicó el borrado (ver tabla anterior). Solución: restaurar desde la instantánea o la copia; para que haya algo que restaurar hay que haberlas activado antes.

### «El NAS aparece en el escáner de puertos de internet»

Síntoma: un servicio de escaneo muestra abiertos el 445 o el 5000/5001 de la IP pública de la oficina. Causa: una redirección de puertos (creada a mano o por UPnP, el mecanismo con el que los dispositivos piden abrir puertos al router sin intervención humana). Hay que eliminar la redirección, desactivar UPnP en el router y pasar al acceso por VPN.

### «El NAS se apaga o se corrompe tras un corte de luz»

Causa: no hay SAI. Un corte mientras escribe puede dejar el sistema de archivos o el RAID inconsistentes. Casi todos los NAS se apagan de forma ordenada si un SAI les avisa por USB.

---

## Buenas prácticas avanzadas

- **Trata la instantánea como un seguro contra el error, no contra el desastre.** Vive en el mismo aparato, en las mismas cuentas de administrador y en el mismo edificio. Programa instantáneas frecuentes con retención larga (por ejemplo, cada hora durante dos días y cada día durante un mes), y añade siempre una copia que salga del NAS.
- **Haz que la copia externa la *tire* el destino, no que la *empuje* el NAS.** Si el NAS tiene credenciales con acceso de escritura al destino, un atacante que entre en el NAS puede borrar o cifrar también la copia. Una copia que el destino descarga por su cuenta, o con instantáneas inmutables en el destino, sobrevive a ese caso.
- **Prueba la restauración de verdad, con fecha en el calendario.** Elige un archivo al azar, restáuralo en otro equipo y ábrelo. Una copia que nunca se ha restaurado no se sabe si funciona.
- **Retira la cuenta `admin` de fábrica y no publiques el panel en ningún sitio.** Crea un administrador con otro nombre, activa la verificación en dos pasos, desactiva UPnP en el router y los servicios (FTP, Telnet, SMB1) que no uses.
- **Mezcla discos para repartir el riesgo de fallos por lote.** Discos de la misma marca, modelo y fecha fallan a menudo con semanas de diferencia. Comprarlos en lotes distintos reduce la probabilidad de que el segundo falle durante la reconstrucción del primero.
- **Mantén el firmware al día y lee los avisos de seguridad del fabricante.** Los NAS exponen servicios de archivos y un panel web; las vulnerabilidades críticas se corrigen en el firmware, y la actualización rara vez es automática por defecto.

## Documentación oficial

- [CISA: Back Up Business Data](https://www.cisa.gov/audiences/small-and-medium-businesses/secure-your-business/back-up-business-data) — la regla 3-2-1 explicada por una agencia oficial, con las recomendaciones de copias sin conexión y pruebas de restauración.
- [Btrfs: estado de las funciones](https://btrfs.readthedocs.io/en/latest/Status.html) — qué partes de Btrfs se consideran estables (instantáneas, RAID1/10) y cuáles no (RAID56).
- [OpenZFS: conceptos de `zpool`](https://openzfs.github.io/openzfs-docs/man/master/7/zpoolconcepts.7.html) — `mirror`, `raidz1/2/3` y cuántos fallos tolera cada uno.
- [Synology: puertos que usan los servicios](https://kb.synology.com/en-global/DSM/tutorial/What_network_ports_are_used_by_Synology_services) — lista de puertos de un NAS real (SMB, NFS, WebDAV, panel) para decidir qué se cierra y qué se abre.

---

*En resumen: un NAS es un disco de red siempre encendido que sirve archivos con usuarios y permisos; el RAID aguanta que un disco muera, pero solo una copia 3-2-1 aguanta el resto, y desde fuera de la oficina se llega por VPN, no abriendo puertos.*
