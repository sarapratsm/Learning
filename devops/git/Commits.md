# Commits

## ¿Qué es?

Un commit es una instantánea del proyecto guardada en el historial de Git: el estado de todos los archivos rastreados en ese momento, más quién lo hizo, cuándo, y un mensaje que explica **por qué**. Cada commit apunta al anterior, y esa cadena de commits es el historial.

## ¿Por qué existe?

Sin commits, el único historial de un proyecto son copias de carpetas (`tienda-final`, `tienda-final-2`) o un fichero que alguien guardó a las tres de la tarde. Un commit convierte cada cambio con sentido en un punto del que se puede volver, que se puede revisar y que se puede combinar con el trabajo de otras personas.

> Si ya conoces el botón «Guardar» de cualquier programa, un commit es como guardar sin sobrescribir lo anterior: cada commit se suma a la línea de tiempo y todos los anteriores siguen ahí.

Un commit no almacena «las diferencias»: almacena el estado completo, y Git calcula la diferencia al compararlo con el anterior. Por eso `git show` o `git log -p` pueden enseñar el cambio de cualquier commit sin que nadie lo haya guardado aparte.

## ¿Cuándo y para qué se usa?

Cada vez que termina un cambio con sentido propio: arreglar un error en `pagos`, añadir la plantilla de confirmación en `emails`, renombrar una función. La regla práctica es un commit por idea: pequeños, frecuentes y con un mensaje que se entienda sin abrir el código. Antes de cada commit conviene decidir qué entra en él con el [área de preparación](Area-de-preparacion.md); este documento arranca desde ahí.

---

## Confirmar lo preparado: `git commit`

Ejemplo guiado en el repositorio `tienda`. Se ha corregido `pagos/pagos.py` y, además, hay un fichero de notas sin relación:

```bash
git status -s
```

```
 M pagos/pagos.py
?? notas.txt
```

Se prepara solo el arreglo y se confirma con un mensaje de una línea (`-m`):

```bash
git add pagos/pagos.py
git commit -m "Corrige el cálculo del IVA en el pago del pedido #4711"
```

```
[main 2d5733f] Corrige el cálculo del IVA en el pago del pedido #4711
 1 file changed, 1 insertion(+)
```

La salida dice la rama (`main`), el identificador abreviado del commit (`2d5733f`) y el resumen del cambio. `notas.txt` sigue sin rastrear: el commit contiene únicamente lo que había en el área de preparación.

Variantes de uso frecuente:

| Comando | Qué hace |
|---|---|
| `git commit` | Abre el editor para escribir el mensaje completo (asunto y cuerpo). |
| `git commit -m "Asunto" -m "Cuerpo"` | Cada `-m` es un párrafo; el segundo forma el cuerpo. |
| `git commit -am "Asunto"` | Prepara los archivos **ya rastreados** modificados y confirma. No incluye archivos nuevos. |
| `git commit -v` | Abre el editor con el diff completo bajo el mensaje, como última revisión. |
| `git commit --allow-empty -m "..."` | Crea un commit sin cambios (por ejemplo, para relanzar un pipeline de CI). |

`-a` es cómodo y también el camino más corto para meter en un commit algo que no se quería. Con cambios mezclados, mejor `git add` selectivo.

### Cuando no hay nada que confirmar

Si se intenta confirmar sin nada preparado, Git no crea un commit vacío y explica el motivo:

```
On branch main
Untracked files:
  (use "git add <file>..." to include in what will be committed)
	notas.txt

nothing added to commit but untracked files present (use "git add" to track)
```

Con el árbol limpio, el mensaje es `nothing to commit, working tree clean`.

## Anatomía de un buen mensaje

Un mensaje tiene un **asunto**, una línea en blanco y un **cuerpo** opcional:

```
Corrige el cálculo del IVA en el pago del pedido #4711

El IVA se aplicaba dos veces cuando el pedido llevaba envío:
una al sumar las líneas y otra al sumar el transporte. Se aplica
ahora solo sobre el total de líneas más envío.
```

- **Asunto**: unos 50 caracteres, en imperativo («Corrige», «Añade»), sin punto final. Describe qué hace el commit al aplicarlo.
- **Línea en blanco**: separa asunto y cuerpo. Herramientas como `git log --oneline` o los pull requests leen solo el asunto, y esa separación es lo que se lo permite.
- **Cuerpo**: el *porqué*: qué problema había, qué alternativas se descartaron, qué caso raro cubre. El *qué* ya lo cuenta el diff.

| ❌ Mensaje | ✅ Mensaje |
|---|---|
| `cambios` | `Corrige el cálculo del IVA en el carrito` |
| `arreglo` | `Evita duplicar el email de confirmación al reintentar el pago` |
| `WIP` | `Añade el esqueleto del servicio inventario` |
| `Cambios en pagos, emails e inventario` | Tres commits, uno por servicio |

La última fila es la más reveladora: si no cabe en una frase sin «y», el commit mezcla ideas y conviene partirlo.

## Conventional Commits: una convención para el asunto

[Conventional Commits](https://www.conventionalcommits.org/es/v1.0.0/) es una convención de formato para el asunto: `tipo(ámbito opcional): descripción`.

```
feat(emails): envía confirmación del pedido
fix(pagos): evita aplicar el IVA dos veces
docs: explica cómo arrancar la tienda en local
refactor(inventario): extrae el cálculo de stock reservado
feat(pedidos)!: elimina el campo `estado_legacy`
```

| Tipo | Se usa para |
|---|---|
| `feat` | Una funcionalidad nueva. |
| `fix` | Una corrección de error. |
| `docs` | Solo documentación. |
| `refactor` | Cambio de código sin cambio de comportamiento. |
| `test` | Añadir o corregir tests. |
| `chore` | Tareas de mantenimiento (dependencias, configuración). |
| `ci`, `build`, `perf`, `style` | Pipeline, construcción, rendimiento, formato. |

El `!` tras el tipo (o un pie `BREAKING CHANGE:` en el cuerpo) marca un cambio incompatible. La convención no es obligatoria en Git; compensa cuando se quiere filtrar el historial (`git log --grep "^fix"`) o automatizar changelogs y números de versión (véase [Tags y versiones](Tags-y-versiones.md)).

## Leer el historial: `git log`

`git log` sin opciones es verboso; casi siempre se usa con un formato.

```bash
git log --oneline
```

```
0831630 Corrige el cálculo del IVA en el pago del pedido #4711
355f5bf Añade servicios pedidos y pagos
```

Para ver la forma de las ramas junto a los commits:

```bash
git log --oneline --graph --all --decorate
```

```
* 45a5b62 (feat/emails) feat(emails): envía confirmación del pedido
* 0831630 (HEAD -> main) Corrige el cálculo del IVA en el pago del pedido #4711
* 355f5bf Añade servicios pedidos y pagos
```

`(HEAD -> main)` indica dónde estás; `(feat/emails)` es otra rama, un commit por delante. Un formato propio con `--pretty=format:`:

```bash
git log --pretty=format:'%h %an %ad %s' --date=short
```

```
0831630 Sara Prats 2026-10-30 Corrige el cálculo del IVA en el pago del pedido #4711
355f5bf Sara Prats 2026-10-30 Añade servicios pedidos y pagos
```

(`%h` hash corto, `%an` autoría, `%ad` fecha, `%s` asunto.) Filtros que se usan de verdad:

| Comando | Responde a |
|---|---|
| `git log --stat -1` | ¿Qué archivos tocó el último commit? |
| `git log -p -- pagos/pagos.py` | ¿Qué cambios ha tenido este archivo? |
| `git log --author="Sara" --since="2 weeks ago"` | ¿Qué hizo esta persona últimamente? |
| `git log --grep="IVA"` | ¿Qué commits mencionan el IVA en el mensaje? |
| `git log -S"calcular_iva"` | ¿Qué commits añadieron o quitaron esa cadena en el código? |
| `git log main..feat/emails` | ¿Qué tiene `feat/emails` que no tenga `main`? |

## Inspeccionar un commit: `git show`

```bash
git show --stat HEAD
```

```
commit 0831630b56aab0000608db84fe868a5acdc56e24
Author: Sara Prats <s@example.com>
Date:   Fri Oct 30 08:29:56 2026 +0100

    Corrige el cálculo del IVA en el pago del pedido #4711

    El IVA se aplicaba dos veces cuando el pedido llevaba envío.

 notas.txt      | 1 +
 pagos/pagos.py | 1 +
 2 files changed, 2 insertions(+)
```

Sin `--stat`, `git show` añade el diff completo. `HEAD` es el último commit de la rama actual (véase [Ramas](Ramas.md)); también valen `HEAD~1` (el anterior) o un hash. Con `-s --format=...` se extraen datos sueltos, útil en scripts.

## Corregir el último commit: `--amend`

Si justo después de confirmar se ve una errata o un archivo olvidado:

```bash
git add notas.txt
git commit --amend --no-edit
```

```
[main 0831630] Corrige el cálculo del IVA en el pago del pedido #4711
 Date: Fri Oct 30 08:29:56 2026 +0100
 2 files changed, 2 insertions(+)
 create mode 100644 notas.txt
```

`--amend` no edita el commit: **lo sustituye por uno nuevo**. En el ejemplo el hash pasó de `2d5733f` a `0831630`. `--no-edit` conserva el mensaje; sin esa opción se abre el editor para cambiarlo.

| Situación | ¿`--amend`? |
|---|---|
| El último commit es local y aún no se ha subido | ✅ Sí. |
| Falta un archivo o hay una errata en el mensaje | ✅ Sí. |
| El commit ya está en el remoto y otras personas pueden tenerlo | ❌ No: obliga a reescribir historia compartida; mejor un commit nuevo. |
| Hay que corregir un commit que no es el último | ❌ No: es un caso de [rebase](Rebase.md). |

Otras formas de deshacer commits (`revert`, `reset`) están en [Deshacer cambios](Deshacer-cambios.md).

## Errores frecuentes

| Síntoma | Causa y solución |
|---|---|
| `nothing added to commit but untracked files present` | Los archivos nuevos no se preparan con `-a`. Hacer `git add <archivo>`. |
| `Author identity unknown` / `*** Please tell me who you are.` | Falta `user.name` y `user.email`; véase [Instalación y configuración](Instalacion-y-configuracion.md). |
| Se coló un archivo en el commit | Si no se ha subido: `git reset --soft HEAD~1`, corregir la preparación y repetir (véase [Deshacer cambios](Deshacer-cambios.md)). |
| `git commit` abre un editor desconocido (vim) | Es el editor por defecto: `:wq` guarda, `:q!` aborta. Cambiable con `git config --global core.editor`. |
| El commit «no aparece» en el remoto | Un commit es local; falta `git push` ([Remotos](Remotos.md)). |

## Buenas prácticas avanzadas

- **Commits atómicos con `git add -p`** — prepara por trozos (*hunks*) cuando un archivo mezcla dos ideas. Un commit que se puede revertir o cherry-pickear solo porque contiene una única idea vale mucho más que uno grande.
- **Cada commit debe dejar el proyecto funcionando** — así `git bisect` ([git-bisect](git-bisect.md)) puede localizar un error saltando entre commits sin tropezar con estados rotos.
- **`git commit --fixup` y `git rebase --autosquash`** — para corregir un commit anterior (no el último) sin perder el hilo: se crea un commit marcado y el rebase lo pliega en su sitio antes de subir ([Rebase](Rebase.md)).
- **El mensaje referencia, el código explica** — enlaza el ticket o el pedido en el cuerpo (`Refs #4711`) y deja en el cuerpo el motivo; un comentario en el código envejece, el mensaje queda fijado a su cambio y se recupera con `git blame` y `git log -S`.
- **No amendes lo ya publicado** — si ya se hizo `git push`, un `--amend` obliga a un push forzado que desincroniza a quien haya bajado el commit.

## Documentación oficial

- [git-commit](https://git-scm.com/docs/git-commit) — referencia de todas las opciones; útil para `--amend`, `--fixup` y la sección de plantillas de mensaje.
- [Conventional Commits 1.0.0](https://www.conventionalcommits.org/es/v1.0.0/) — la especificación completa de la convención, breve y en español.
- [Pro Git: Guardando cambios en el repositorio](https://git-scm.com/book/es/v2/Fundamentos-de-Git-Guardando-cambios-en-el-Repositorio) — el recorrido clásico de `status`, `add`, `commit` y `log`.

---

*En resumen: un commit es una foto etiquetada del proyecto; confirma una sola idea cada vez, escribe el porqué en el mensaje y usa `--amend` solo mientras el commit siga siendo solo tuyo.*
