# Git

## ¿Qué es?

Git es un **sistema de control de versiones distribuido**: una herramienta que guarda el historial de cambios de un proyecto, permite volver a cualquier punto anterior, trabajar en varias cosas en paralelo y combinar el trabajo de varias personas sin pisarse.

## ¿Por qué existe?

Sin control de versiones, guardar el progreso acaba siendo copiar carpetas con nombres como `tienda_final`, `tienda_final_v2`, `tienda_final_BUENO_ahora_si`. Se pierde el rastro de qué cambió, cuándo y por qué, y juntar el trabajo de dos personas se convierte en un copiar y pegar a mano.

Git registra cada conjunto de cambios como una «foto» completa del proyecto (un *commit*) con su autor, fecha y descripción, y permite moverse por esa línea de tiempo en cualquier momento.

> Piensa en el historial de versiones de un documento en la nube, pero para todo un proyecto y con mucho más control: se ve qué línea exacta cambió en cada versión, quién la escribió y por qué.

## ¿Cuándo y para qué se usa?

En casi cualquier proyecto de software, desde un script personal hasta una aplicación con cientos de personas trabajando a la vez. En esta colección el hilo conductor es una **tienda online** con un repositorio llamado `tienda` y cuatro servicios: `pedidos`, `pagos`, `inventario` y `emails`. Git responde ahí a preguntas como:

- ¿Cuándo dejó de funcionar el cobro del pedido #4711? (se busca en el historial).
- ¿Quién cambió el cálculo del IVA en `pagos` y por qué? (cada commit lleva autor y mensaje).
- ¿Cómo desarrollar el servicio `emails` sin romper lo que ya funciona en `pedidos`? (en una rama aparte).

## Modelo mental: fotos, no diferencias

Muchos sistemas antiguos guardaban, por cada archivo, la lista de diferencias respecto a la versión anterior. Git guarda **una instantánea completa del proyecto en cada commit**; si un archivo no cambió, la foto nueva reutiliza el contenido ya guardado en vez de duplicarlo. Los *diffs* que se ven en pantalla los calcula Git al vuelo, comparando dos fotos.

Con este modelo, `merge`, `rebase` o `cherry-pick` dejan de ser magia: todos consisten en crear, combinar o recolocar instantáneas.

### Qué hay dentro: objetos

Git es, en el fondo, una base de datos de **objetos** identificados por un hash (un identificador de 40 caracteres hexadecimales calculado a partir del contenido). Hay cuatro tipos; tres bastan para entender el día a día:

| Objeto | Qué guarda | Equivale a |
|---|---|---|
| *blob* | El contenido de un archivo | El archivo, sin nombre |
| *tree* | Una lista de nombres que apuntan a blobs y a otros trees | Una carpeta |
| *commit* | Un tree (la foto), el commit anterior, autor y mensaje | Un punto de la línea de tiempo |

(El cuarto, el *tag anotado*, se trata en [Tags y versiones](Tags-y-versiones.md).) Se pueden inspeccionar con `git cat-file`:

```bash
git cat-file -p HEAD
```

```
tree 65f405f6406a68f04825b2309af92435cc500c32
parent 70a901d8b00643c6f89f175e2c0cea9a02a92e40
author Sara <s@e.com> 1793345393 +0100
committer Sara <s@e.com> 1793345393 +0100

Pagos
```

Un commit apunta a su *tree* y a su **padre** (el commit anterior). Esa cadena de padres es el historial. Al pedir el contenido del tree se ve la «carpeta» de la foto:

```bash
git cat-file -p 'HEAD^{tree}'
```

```
100644 blob c2bfa40bca06379d5f5e24b47085baa1b6565d97	README.md
040000 tree 7000066a89293615df55c2cc8a5b074b224823e6	pagos
040000 tree 3f90c763c571bb74540bae450d9e1c04e4c0b228	pedidos
```

Como el hash depende del contenido, **cambiar un solo byte del pasado cambia todos los hashes posteriores**: el historial no se puede alterar sin que se note. Es lo que hace fiable al repositorio.

### Dónde vive: la carpeta `.git`

Todos esos objetos, junto con las ramas y la configuración local, viven en la subcarpeta oculta `.git` de la raíz del proyecto. Esa carpeta *es* el repositorio; el resto de archivos son solo la copia de trabajo. El detalle de su contenido está en [Repositorio](Repositorio.md).

### Las tres áreas

Los archivos del proyecto pasan por tres lugares:

| Área | Qué contiene | Se actualiza con |
|---|---|---|
| Directorio de trabajo | Los archivos tal como están en disco, los que se editan | El editor |
| Área de preparación (*index*) | La foto que se va a guardar en el próximo commit | `git add` ([Área de preparación](Area-de-preparacion.md)) |
| Repositorio (`.git`) | Las fotos ya guardadas | `git commit` ([Commits](Commits.md)) |

De ahí salen los tres estados de un archivo: **modificado** (cambiado en disco, sin preparar), **preparado** (*staged*, incluido en la próxima foto) y **confirmado** (*committed*, ya guardado).

### Ramas: etiquetas que se mueven

Una **rama** no es una copia del proyecto: es un archivo con 41 bytes que contiene el hash de un commit. Cuando se hace un commit nuevo, la rama actual avanza para apuntar a él. `HEAD` es otro puntero que indica en qué rama se está trabajando.

```bash
cat .git/refs/heads/master
cat .git/HEAD
```

```
46812cc7114bb29dadbc6da40a36085d57d7255b
ref: refs/heads/master
```

Por eso crear una rama es instantáneo y barato en un repositorio de cualquier tamaño. Se desarrollan en [Ramas](Ramas.md) y [Switch](Switch.md).

## Por qué «distribuido»

En un sistema centralizado hay un servidor con el historial y cada persona tiene solo la versión en la que trabaja. En Git, **cada clon contiene el historial completo**:

| | Centralizado | Distribuido (Git) |
|---|---|---|
| Ver el historial, comparar versiones | Requiere servidor | Local, sin red |
| Hacer commits | Requiere servidor | Local; se sube después |
| Si el servidor desaparece | Se pierde el historial | Cualquier clon lo restaura |
| Trabajar en un tren o avión | No | Sí |

Los commits, las ramas y los diffs son operaciones locales y por tanto instantáneas. Compartir el trabajo es un paso aparte: se sube o se descarga contra otros repositorios llamados remotos ([Remotos](Remotos.md)).

## Git no es GitHub

Git es el programa que se ejecuta en el ordenador. GitHub, GitLab o Bitbucket son servicios en línea que alojan repositorios Git y añaden extras (permisos, revisión de código, automatización). Se puede usar Git sin ninguno de ellos.

| Quiero… | Lo da… |
|---|---|
| Guardar historial, ramas, fusiones | Git |
| Alojar el repositorio para el equipo | GitHub, GitLab, un servidor propio |
| Revisar cambios antes de integrarlos | El servicio ([Pull requests](Pull-requests.md)) |
| Ejecutar pruebas automáticas al subir código | El servicio ([GitHub Actions](GitHub-Actions.md)) |

## Un primer recorrido

El flujo mínimo, con el servicio `pedidos` de la tienda:

```bash
git init                         # crea el repositorio
git add pedidos/app.py           # prepara el archivo
git commit -m "Crea el servicio de pedidos"
git log --oneline
```

`init` crea `.git`, `add` copia el archivo al área de preparación, `commit` guarda la foto y `log --oneline` lista el historial en una línea por commit. Cada paso tiene su ficha: [Repositorio](Repositorio.md), [Área de preparación](Area-de-preparacion.md) y [Commits](Commits.md). Antes de nada, Git necesita saber quién es el autor: [Instalación y configuración](Instalacion-y-configuracion.md).

## Qué no hace Git

- **No es una copia de seguridad en la nube.** Guarda historial en local; subirlo a otro sitio es un paso explícito.
- **No resuelve los conflictos por ti.** Si dos personas cambian la misma línea, avisa y decide quien fusiona ([Fusión y conflictos](Fusion-y-conflictos.md)).
- **No es adecuado para binarios grandes que cambian a menudo.** Cada versión de un vídeo o un dataset se guarda entera y el repositorio crece sin freno; para eso existen extensiones como Git LFS.
- **No guarda carpetas vacías.** Solo versiona archivos; una carpeta vacía necesita un archivo dentro (por convención, `.gitkeep`).

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `fatal: not a git repository (or any of the parent directories): .git` | El comando se ejecuta fuera de un repositorio; falta `git init` o hay que entrar en la carpeta correcta |
| Los commits no aparecen en GitHub | Commit y subida son pasos distintos; falta `git push` ([Remotos](Remotos.md)) |
| Se «perdió» un commit tras un error | Casi siempre sigue en la base de datos; ver [Deshacer cambios](Deshacer-cambios.md) |
| Se subió un archivo con una contraseña | Borrarlo en un commit posterior no lo quita del historial; hay que tratar la credencial como comprometida |

## Buenas prácticas avanzadas

- **Interroga al historial con el *pickaxe*.** `git log -S "calcularIva"` encuentra los commits donde ese texto apareció o desapareció, y `git log -p -- pagos/app.py` muestra la evolución de un archivo cambio a cambio. Es la forma experta de responder «¿cuándo y por qué se tocó esto?» sin leer commits al azar.
- **Git casi nunca borra de verdad.** Los commits «perdidos» siguen en la base de datos durante semanas hasta que el recolector de basura los limpia, y `git reflog` los localiza. Quien domina Git trabaja sin miedo porque casi todo se recupera.
- **Una rama es un puntero: si dudas, crea otra.** Antes de una operación arriesgada, `git branch copia-seguridad` cuesta un archivo de 41 bytes y deja un punto de retorno exacto.
- **Un hash identifica un contenido, no un momento.** Dos commits con el mismo árbol pero distinto padre o fecha tienen hashes distintos; por eso reescribir historia (rebase, amend) produce commits nuevos y los antiguos no se «modifican».
- **Crea alias para lo que se escribe veinte veces al día.** `git config --global alias.lg "log --oneline --graph --all"` da una vista del árbol de ramas que cambia cómo se entiende el repositorio ([Instalación y configuración](Instalacion-y-configuracion.md)).

## Documentación oficial

- [Pro Git, capítulo «Inicio - Sobre el Control de Versiones»](https://git-scm.com/book/es/v2/Inicio---Sobre-el-Control-de-Versiones-Fundamentos-de-Git) — la explicación canónica de instantáneas, las tres áreas y los tres estados; léela primero para afianzar el modelo mental.
- [Pro Git, índice del libro](https://git-scm.com/book/es/v2) — el libro completo en español; el capítulo «Fundamentos de Git» cubre el uso diario y el de «Git Internals» detalla los objetos.
- [Glosario de Git](https://git-scm.com/docs/gitglossary) — definición oficial de cada término (*index*, *ref*, *HEAD*, *tree-ish*…); útil cuando un mensaje de error usa una palabra que no se reconoce.

---

*En resumen: Git es una base de datos de fotos del proyecto enlazadas entre sí, que cada persona lleva completa en su ordenador — de ahí que casi todo sea local, rápido y recuperable.*
