# Deshacer cambios

## ¿Qué es?

Un conjunto de comandos de Git para corregir errores según el punto en el que estén: descartar modificaciones sin guardar, sacar archivos del área de preparación, anular o rehacer commits, y recuperar lo que parecía perdido.

## ¿Por qué existe?

Equivocarse es parte de programar: se modifica un archivo que no tocaba, se prepara un archivo de más, se confirma con el mensaje equivocado o se publica un commit que rompe `pagos`. Git guarda el historial precisamente para que esos errores no sean permanentes, pero no hay un único «deshacer»: hay una herramienta por cada **zona** de Git donde puede estar el cambio, y elegir mal la herramienta es lo que convierte un fallo menor en una pérdida real.

> Es el Ctrl+Z de cualquier programa, pero con niveles: uno para lo que aún no guardaste, otro para lo que ya preparaste y otro para lo que ya confirmaste. Y con una diferencia importante: lo publicado ya lo tienen otras personas, y no se deshace igual que lo local.

## ¿Cuándo y para qué se usa?

Siempre se empieza por la misma pregunta: **¿dónde está el cambio que quiero deshacer?** Hay tres zonas (explicadas en [Área de preparación](Area-de-preparacion.md)): el directorio de trabajo, el área de preparación (*staging*) y el historial de commits. Y, para el historial, una cuarta cuestión: si ya se hizo `push` (ver [Remotos](Remotos.md)).

## Tabla de decisión

| Qué quiero deshacer | En qué punto está | Comando |
|---|---|---|
| Cambios en un archivo | Modificado, sin preparar | `git restore archivo` |
| Haber preparado un archivo | En el área de preparación | `git restore --staged archivo` |
| Un archivo nuevo sin seguimiento | Sin añadir a Git | `git clean -n` y `git clean -f` (o borrarlo a mano) |
| Una versión antigua de un archivo | En el historial | `git restore --source=<commit> archivo` |
| El mensaje o el contenido del último commit | Commit local, sin publicar | `git commit --amend` |
| Los últimos commits, conservando los cambios | Commits locales, sin publicar | `git reset --soft HEAD~N` o `git reset HEAD~N` |
| Los últimos commits y los cambios | Commits locales, sin publicar | `git reset --hard HEAD~N` |
| Un commit concreto, sin tocar el resto | Ya publicado (o compartido) | `git revert <commit>` |
| Una fusión ya publicada | Commit de fusión en `main` | `git revert -m 1 <commit-de-fusión>` |
| Un `reset --hard` o una rama borrada | Ya confirmado alguna vez | `git reflog` y volver a ese punto |
| Cambios que nunca se guardaron ni se confirmaron | Solo en el directorio de trabajo | No hay vuelta atrás: Git no los conoce |

## Descartar cambios sin guardar: `restore`

Estado de partida: se añadió `DEBUG = True` al archivo `config.py` del servicio `pagos` y no se quiere.

```bash
git status -s
git restore config.py
git status -s
```

```
 M config.py
```

La primera orden muestra ` M config.py` (modificado, sin preparar) y la segunda no muestra nada: el archivo vuelve a ser idéntico al del último commit. **No hay papelera**: lo descartado no se recupera, porque Git nunca lo guardó.

Para sacar del área de preparación sin perder el cambio:

```bash
git add config.py
git restore --staged config.py
git status -s
```

```
 M config.py
```

Pasó de `M ` (preparado) a ` M` (modificado sin preparar): el contenido sigue ahí, solo se quitó de «la caja del próximo commit».

`restore` también trae versiones antiguas. Para recuperar `config.py` tal como estaba dos commits atrás, sin tocar el resto:

```bash
git restore --source=HEAD~2 config.py
```

El archivo queda modificado en el directorio de trabajo, listo para revisarlo y confirmarlo (o descartarlo con otro `git restore config.py`). Para archivos nuevos sin seguimiento, `restore` no sirve: `git clean -n` muestra qué borraría (`Would remove tmp.txt`) y `git clean -f` lo borra.

## Corregir el último commit: `--amend`

Si el error está en el último commit y aún no se ha publicado:

```bash
git commit --amend -m "Pedido 4711: corrección de estado"
```

Cambia el mensaje o, si antes se preparan más archivos con `git add`, también el contenido. Git sustituye el commit por otro nuevo (con otro identificador). Eso es reescribir historial: solo es seguro si nadie más tiene ese commit (ver [Commits](Commits.md)).

## Mover la rama hacia atrás: `reset`

`reset` mueve la rama actual a otro commit. La diferencia entre sus tres modos es **cuánto más arrastra**:

| Modo | Mueve la rama | Vacía el área de preparación | Toca los archivos de trabajo |
|---|---|---|---|
| `--soft` | Sí | No (los cambios quedan preparados) | No |
| `--mixed` (por defecto) | Sí | Sí (quedan modificados) | No |
| `--hard` | Sí | Sí | **Sí: los sobrescribe** |

Con dos commits locales del pedido 4711:

```
cffb6c2 Pedido 4711: estado
aee1ef4 Pedido 4711: alta
8518455 v2
```

**`--soft`**: deshace el commit y deja el cambio listo para recommitear (útil para reescribir el mensaje o juntar commits).

```bash
git reset --soft HEAD~1
git status -s
```

```
M  pedidos.py
```

**`--mixed`** (sin opción): deshace el commit y además lo saca de la preparación.

```bash
git reset HEAD~1
```

```
Unstaged changes after reset:
M	pedidos.py
```

**`--hard`**: deshace el commit **y descarta el cambio** del archivo.

```bash
git reset --hard HEAD~1
```

```
HEAD is now at aee1ef4 Pedido 4711: alta
```

Es el único destructivo: `git reset --hard` a secas, sin commit, descarta todo lo modificado sin preguntar (`HEAD is now at ...` es toda la confirmación). Como reescribe historial, **no se usa sobre commits ya publicados en una rama compartida**.

## Deshacer lo ya publicado: `revert`

Cuando el commit ya está en el remoto y otras personas han podido descargarlo, no se borra: se añade un commit nuevo que hace lo contrario.

```bash
git revert cffb6c2
```

```
[main 796745a] Revert "Pedido 4711: estado"
 1 file changed, 1 deletion(-)
```

El historial pasa a ser `796745a Revert "Pedido 4711: estado"` encima de `cffb6c2 Pedido 4711: estado`: el original sigue ahí, y el repositorio queda como estaba antes. Se publica con un `push` normal, sin forzar. Sirve para cualquier commit del pasado, no solo el último; si el revert choca con cambios posteriores, hay conflicto y se resuelve como en [Fusión y conflictos](Fusion-y-conflictos.md).

### Revertir una fusión

Un commit de fusión tiene dos padres y Git no sabe cuál es la línea que se debe conservar:

```
error: commit c009111e16ea1f6f491219be2112be1d0fe8722d is a merge but no -m option was given.
fatal: revert failed
```

```bash
git revert -m 1 <commit-de-fusión>
```

`-m 1` indica que el padre 1 (normalmente `main`, la rama en la que se fusionó) es el que se conserva. Después de revertir una fusión, volver a fusionar la **misma rama** no trae nada, porque Git considera que esos commits ya entraron: hay que revertir el revert, o rehacer los commits de la rama en commits nuevos.

## Recuperar lo perdido: `reflog`

Git apunta cada vez que `HEAD` se mueve en un registro local, el *reflog*. Tras un `reset --hard` equivocado:

```bash
git reflog
```

```
aee1ef4 HEAD@{0}: reset: moving to HEAD~1
cffb6c2 HEAD@{1}: commit: Pedido 4711: estado
aee1ef4 HEAD@{2}: reset: moving to HEAD~1
```

El commit `cffb6c2` sigue existiendo aunque ninguna rama apunte a él. Para volver:

```bash
git reset --hard HEAD@{1}
```

```
HEAD is now at cffb6c2 Pedido 4711: estado
```

También sirve para una rama borrada por error (`git branch -D rama` imprime `Deleted branch rama (was 8498c82)`, y ese identificador permite recrearla con `git branch rama 8498c82`). Límites: el reflog es **local** (no viaja con `push`), y las entradas caducan: por defecto 90 días las alcanzables y 30 las inalcanzables. Y solo recupera lo que alguna vez se confirmó: lo que nunca pasó por un commit no está.

## Errores frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `error: pathspec 'config.py' did not match any file(s) known to git` | Archivo nuevo sin seguimiento, o nombre mal escrito | `git status`; los archivos sin seguimiento se borran, no se restauran |
| `! [rejected] main -> main (non-fast-forward)` tras un `reset` o `amend` | Se reescribió un commit ya publicado | Si nadie lo tiene, `git push --force-with-lease` (ver [Remotos](Remotos.md)); si es rama compartida, usar `revert` |
| `error: commit ... is a merge but no -m option was given.` | Se intenta revertir un commit de fusión | `git revert -m 1 <commit>` |
| `git reset --hard` descartó trabajo sin commit | Los archivos no confirmados no están en el reflog | Sin solución en Git; revisar la papelera del editor o copias locales |
| `fatal: ambiguous argument 'HEAD~1': unknown revision` | No hay commit anterior (primer commit del repositorio) | No hay a dónde retroceder |

## Buenas prácticas avanzadas

- **Haz `git status` y `git diff` antes de `restore` o `reset --hard`.** Son las únicas órdenes de esta guía que destruyen trabajo sin recuperación posible; mirar qué se pierde cuesta dos segundos.
- **Crea una rama de rescate antes de reescribir.** `git branch respaldo` antes de un `reset` o rebase arriesgado deja un puntero al estado anterior, sin depender de acordarse del reflog. Se borra después con `git branch -D respaldo`.
- **`reset` mixto es seguro; `--hard` es la excepción.** `git reset HEAD~1` solo descommitea: el trabajo sigue en los archivos. Usarlo sin miedo para recolocar commits es señal de dominio, y reservar `--hard` para cuando de verdad se quiere perder el cambio.
- **Elige `revert` por defecto en ramas compartidas.** Su coste (un commit extra) es nada frente al coste de reescribir un historial que ya tienen otras personas. Si la corrección se puede hacer con un commit nuevo, no se reescribe nada.
- **Los commits «perdidos» sobreviven semanas.** Antes de dar nada por perdido, `git reflog` y `git log --all`; entre los dos aparecen casi todos los commits que ya se hicieron alguna vez. Y para cambios a medias que no se quieren confirmar todavía, la red de seguridad es [Stash](Stash.md), no `restore`.

## Documentación oficial

- [git-restore](https://git-scm.com/docs/git-restore) — `--staged`, `--source` y `--patch`; los ejemplos del final cubren los casos habituales.
- [git-reset](https://git-scm.com/docs/git-reset) — la tabla de qué cambia cada modo (`--soft`, `--mixed`, `--hard`) para cada estado del archivo.
- [Pro Git: Reset Demystified](https://git-scm.com/book/en/v2/Git-Tools-Reset-Demystified) — el modelo de las tres zonas (HEAD, índice, directorio de trabajo) que hace evidente qué toca cada modo de `reset`.
- [git-revert](https://git-scm.com/docs/git-revert) y [git-reflog](https://git-scm.com/docs/git-reflog) — `-m` para fusiones y los plazos de caducidad del reflog.

---

*En resumen: antes de deshacer, pregunta dónde está el cambio: `restore` para lo no confirmado, `reset` para lo local, `revert` para lo publicado y `reflog` cuando creas que lo perdiste.*
