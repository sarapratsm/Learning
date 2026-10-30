# Área de preparación (staging)

## ¿Qué es?

El área de preparación (*staging area* o *index*) es una zona intermedia donde se colocan los cambios que van a entrar en el próximo commit, antes de confirmarlos definitivamente.

## ¿Por qué existe?

Casi nunca se quiere guardar *todo* lo que se ha tocado de golpe. Quizá se ha arreglado un error en el servicio `pedidos` y, de paso, se han dejado notas a medias en otro archivo. El área de preparación permite elegir **qué cambios entran en cada commit**, para que el historial cuente una historia limpia en vez de mezclar cosas sin relación.

> Imagina una caja para enviar por correo: el área de preparación es la caja. Se mete solo lo que va en este envío; lo demás espera al siguiente.

Técnicamente es un archivo (`.git/index`) que contiene la foto que se guardará con el próximo `git commit`. `git add` actualiza esa foto; `git commit` la convierte en un commit.

## ¿Cuándo y para qué se usa?

Cada vez que se va a hacer un commit. Se prepara (`add`) lo que corresponde y se confirma ([Commits](Commits.md)). Es especialmente útil cuando se han tocado varias cosas y conviene separarlas: un commit para el arreglo del cobro de `pagos`, otro para el nuevo servicio `emails`.

## Cómo se ve cada área

Un cambio puede estar en tres sitios a la vez. Con un archivo `pedidos/app.py` modificado y uno de `pagos/app.py` sin preparar:

| Área | Comando para verla | Qué muestra |
|---|---|---|
| Directorio de trabajo vs. área de preparación | `git diff` | Lo **no** preparado |
| Área de preparación vs. último commit | `git diff --staged` | Lo que **entrará** en el commit |
| Resumen de ambas | `git status` | Qué está preparado, qué no y qué es nuevo |

`git diff --staged` y `git diff --cached` son sinónimos.

## Preparar: `git add`

### Archivos o carpetas concretos

```bash
git add pedidos/app.py
git add pedidos/
```

El primero prepara un archivo; el segundo, todo lo modificado y nuevo bajo `pedidos/`. Si el archivo no existe, Git lo dice:

```
fatal: pathspec 'nada.py' did not match any files
```

### Todo de una vez

| Comando | Prepara |
|---|---|
| `git add .` | Todo lo modificado, nuevo o borrado desde la carpeta actual hacia abajo |
| `git add -A` | Igual, pero desde la raíz del repositorio |
| `git add -u` | Solo lo que Git ya conocía (modificado o borrado); ignora archivos nuevos |

Es cómodo y peligroso: arrastra cualquier cosa que haya en la carpeta (un archivo de configuración con contraseñas, un volcado de datos). Conviene mirar `git status` antes, o dejar fuera lo que no pertenece al repositorio con [gitignore](gitignore.md).

### Ejemplo: dos cambios, un commit

Hay modificados `pedidos/app.py` y `pagos/app.py`. Se prepara solo el primero:

```bash
git add pedidos/app.py
git status -sb
```

```
## main
M  pedidos/app.py
 M pagos/app.py
```

La primera columna (`M `) es el área de preparación; la segunda (` M`) es el directorio de trabajo. `pedidos/app.py` está preparado; `pagos/app.py`, modificado a secas. Un `git commit` guardaría solo el primero.

## Ver qué se va a confirmar: `diff` frente a `diff --staged`

```bash
git add pedidos/app.py
git diff
```

```
diff --git a/pagos/app.py b/pagos/app.py
--- a/pagos/app.py
+++ b/pagos/app.py
@@ -1 +1 @@
-def cobrar(): pass
+def cobrar(): return 4711
```

`git diff` a secas enseña **lo que falta por preparar** (aquí `pagos`), no lo que va a entrar. Para ver el contenido del commit que viene:

```bash
git diff --staged
```

```
diff --git a/pedidos/app.py b/pedidos/app.py
--- a/pedidos/app.py
+++ b/pedidos/app.py
@@ -1 +1 @@
-def crear_pedido(): pass
+def crear_pedido(id): print(id)
```

Confundir ambos es la causa más habitual de commits con sorpresas dentro. Hábito útil: `git diff --staged` justo antes de `git commit`.

## Preparar por trozos: `git add -p`

A veces el mismo archivo contiene dos cambios que no deben ir juntos: un arreglo y una nota a medias. `git add -p` (*patch*) divide el archivo en bloques (*hunks*) y pregunta por cada uno:

```bash
git add -p pedidos.py
```

```
@@ -1,5 +1,5 @@
 1
-2
+CAMBIO arreglo
 3
 4
 5
(1/2) Stage this hunk [y,n,q,a,d,k,K,j,J,g,/,e,p,P,?]?
```

Se responde `y` al primero y `n` al segundo. El resultado es un archivo a la vez preparado y modificado (`MM`), con solo el arreglo en la foto:

```
## main
MM pedidos.py
```

```bash
git diff --staged | grep '^[+-]'
```

```
-2
+CAMBIO arreglo
```

Respuestas más útiles:

| Tecla | Efecto |
|---|---|
| `y` / `n` | Preparar / no preparar este bloque |
| `s` | Dividir el bloque en otros más pequeños (aparece si hay líneas sin cambios entre medias) |
| `e` | Editar el bloque a mano, línea a línea |
| `a` / `d` | Preparar / saltar este y todos los siguientes del archivo |
| `q` | Salir; lo ya decidido se conserva |
| `?` | Ayuda con todas las opciones |

## Sacar algo del área de preparación: `git restore --staged`

```bash
git restore --staged pedidos/app.py
git status -sb
```

```
## main
 M pagos/app.py
 M pedidos/app.py
```

El archivo vuelve a estar modificado sin preparar: el cambio **no se pierde**, solo sale de la caja. Sin argumentos, el comando falla con `fatal: you must specify path(s) to restore`; para vaciar todo el área: `git restore --staged .`.

`restore --staged` no toca el contenido de los archivos. Descartar los cambios del disco es otra operación, destructiva, que se trata en [Deshacer cambios](Deshacer-cambios.md).

## Archivos nuevos

Un archivo que Git nunca ha visto no entra en ningún commit hasta que se prepara con `git add`. Mientras tanto no aparece en `git diff`:

```bash
git status -sb
```

```
## main
MM pedidos.py
?? emails.py
```

Tampoco aparece en `git add -p`. Con `git add -N emails.py` (*intent to add*) Git lo registra vacío y su contenido pasa a verse como un cambio más:

```
## main
 A emails.py
MM pedidos.py
```

Así `git diff` y `git add -p` ya lo muestran y permiten prepararlo por trozos.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| El archivo sale a la vez en «Changes to be committed» y «Changes not staged for commit» (`MM`) | Se editó **después** de `git add`: lo preparado es la versión de aquel momento; hay que volver a hacer `git add` |
| `git diff` no muestra nada pero `git status` dice que hay cambios | Esos cambios ya están preparados: `git diff --staged` |
| `nothing added to commit but untracked files present (use "git add" to track)` | Hay archivos nuevos y ninguno preparado; `commit` no los incluye solos |
| `fatal: pathspec 'nada.py' did not match any files` | La ruta no existe o está mal escrita; se ejecuta desde otra carpeta |
| `no changes added to commit (use "git add" and/or "git commit -a")` | Hay cambios sin preparar y se ha lanzado `git commit` |
| Se preparó algo que no debía (un archivo de configuración con credenciales) | `git restore --staged <archivo>` antes del commit; si ya se hizo, ver [Deshacer cambios](Deshacer-cambios.md) |

## Cuándo no usarlo

Para un cambio pequeño que se confirma entero, el área de preparación es un paso de ceremonia. `git commit -a -m "mensaje"` prepara y confirma de golpe todos los archivos **ya rastreados** que cambiaron; no incluye archivos nuevos. Si la intención es un commit por tema, `git add -p` es la herramienta, no `commit -a`.

## Buenas prácticas avanzadas

- **Prepara trozos, no archivos.** Quien domina Git construye commits atómicos con `git add -p`: cada commit responde a una sola idea (el arreglo del cobro, no «cambios varios»), lo que facilita revisarlos, revertirlos con [Rebase](Rebase.md) o con [Cherry-pick](Cherry-pick.md) y encontrar errores con [git bisect](git-bisect.md).
- **Revisa siempre `git diff --staged` antes de confirmar.** Es la última barrera para detectar una traza de depuración, una credencial o un archivo ajeno. Un alias como `git config --global alias.ds "diff --staged"` lo deja a dos letras ([Instalación y configuración](Instalacion-y-configuracion.md)).
- **`git add` congela el contenido en ese instante.** Si el editor guarda de nuevo, la foto del área de preparación queda desfasada: el commit contiene la versión antigua y no hay ningún aviso salvo el `MM` de `git status`.
- **Prepara con intención con `git add -p` también para archivos nuevos.** `git add -N` los hace visibles a `diff` y a `add -p`, y es la única forma de dividir en commits distintos un archivo nuevo ya grande.
- **El área de preparación es un punto de guardado temporal.** Preparar una versión que funciona y seguir experimentando permite volver a ella con `git restore <archivo>` (que restaura desde el área de preparación) si el experimento sale mal.

## Documentación oficial

- [git add](https://git-scm.com/docs/git-add) — opciones de selección (`-p`, `-u`, `-A`, `-N`) y el modo interactivo; la lista completa de teclas de `-p`.
- [git restore](https://git-scm.com/docs/git-restore) — `--staged`, `--worktree` y `--source`; los ejemplos del final cubren los usos habituales.
- [git diff](https://git-scm.com/docs/git-diff) — qué compara cada forma de `git diff` y las opciones de formato (`--stat`, `--word-diff`).
- [Pro Git: Guardando cambios en el repositorio](https://git-scm.com/book/es/v2/Fundamentos-de-Git-Guardando-cambios-en-el-Repositorio) — el ciclo `status`, `add`, `diff`, `commit` explicado paso a paso.

---

*En resumen: el área de preparación es la caja donde se elige, cambio a cambio, qué entra en el próximo commit — `git diff --staged` enseña su contenido y `git add -p` permite llenarla por trozos.*
