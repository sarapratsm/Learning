# Stash

## ¿Qué es?

`git stash` aparta los cambios sin confirmar en una pila local (la «estantería») y deja el directorio de trabajo igual que el último commit, para recuperarlos más tarde.

## ¿Por qué existe?

Surge una urgencia a mitad de una tarea: hay que cambiar de rama para arreglar un fallo, pero Git se niega porque hay cambios sin guardar que se perderían, y todavía no merecen un commit. Con el *stash* se aparta lo que hay, se atiende lo urgente y se devuelve.

```
error: Your local changes to the following files would be overwritten by checkout:
	pagos/api.py
Please commit your changes or stash them before you switch branches.
Aborting
```

> Es como dejar el trabajo a medias en un cajón para despejar la mesa, atender otra cosa y luego sacarlo y seguir donde lo dejaste.

## ¿Cuándo y para qué se usa?

- **Cambiar de contexto** (de rama, de tarea) con trabajo a medias en el repositorio `tienda`: se está en el servicio `pagos` y aparece un fallo en el pedido #4711.
- **Actualizar la rama** con `git pull --rebase` o `git rebase` (ver [Rebase.md](Rebase.md)) cuando Git protesta por cambios sin confirmar.
- **Probar algo con el árbol limpio** sin perder lo que había.

Para guardar trabajo de verdad (que sobreviva a una avería o llegue al remoto), se hace commit en una rama; el stash es local y temporal.

## Guardar: `push`, `-u` y `-m`

Estado de partida: un fichero modificado, otro modificado y uno nuevo sin rastrear.

```bash
git status -s
```

```
 M pagos/api.py
 M pedidos/api.py
?? pagos/reembolso.py
```

`git stash` a secas aparta solo los ficheros que Git ya conoce:

```bash
git stash
```

```
Saved working directory and index state WIP on main: 8d37dc7 Aplica IVA en pagos
```

```
?? pagos/reembolso.py
```

Los modificados volvieron al último commit, pero `reembolso.py` sigue ahí: **los ficheros nuevos no se guardan por defecto**. Para incluirlos se usa `-u` (`--include-untracked`), y `-m` pone un nombre que se entiende semanas después:

```bash
git stash push -u -m "Reembolsos a medias"
```

```
Saved working directory and index state On main: Reembolsos a medias
```

| Opción | Efecto |
|---|---|
| `-u` / `--include-untracked` | Incluye ficheros nuevos sin rastrear |
| `-a` / `--all` | Incluye además los ignorados por `.gitignore` (ver [gitignore.md](gitignore.md)); casi nunca conviene |
| `-m "texto"` | Nombre de la entrada; sin él sale `WIP on <rama>: <hash> <mensaje>` |
| `--keep-index` | Aparta todo pero deja en el área de preparación lo ya añadido con `git add` (ver [Area-de-preparacion.md](Area-de-preparacion.md)) |

## Ver el contenido

```bash
git stash list
```

```
stash@{0}: On main: Reembolsos a medias
stash@{1}: WIP on main: 8d37dc7 Aplica IVA en pagos
```

Es una pila: `stash@{0}` es el más reciente. Para ver qué cambia una entrada:

```bash
git stash show              # resumen del más reciente
git stash show -p stash@{1} # el diff completo de otra entrada
```

```
 pagos/api.py | 3 +--
 1 file changed, 1 insertion(+), 2 deletions(-)
```

## Recuperar: `pop` o `apply`

| Orden | Aplica los cambios | Borra la entrada |
|---|---|---|
| `git stash pop` | Sí | Sí, si se aplicó sin conflictos |
| `git stash apply` | Sí | No |

```bash
git stash pop
```

```
On branch main
Changes not staged for commit:
	modified:   pagos/api.py
	modified:   pedidos/api.py
Dropped refs/stash@{0} (8c131d33ca43713e7ec99d2015260c1d8e034fa3)
```

`pop` es lo habitual. `apply` es útil para llevar los mismos cambios a varias ramas, o cuando se quiere conservar la copia hasta comprobar que todo ha ido bien. Para una entrada concreta: `git stash pop stash@{1}` o `git stash apply stash@{1}`. Una entrada que sobra se elimina con `git stash drop stash@{1}`, y todas con `git stash clear` (sin confirmación).

## Apartar solo algunos ficheros

Con `--` y rutas se aparta solo lo indicado, y el resto sigue en el directorio de trabajo:

```bash
git stash push -m "solo pagos" -- pagos/api.py
```

```
Saved working directory and index state On main: solo pagos
```

```
 M pedidos/api.py
```

Es la forma de aislar un cambio sin tocar el resto de lo que se está haciendo. Para elegir por trozos de fichero existe `git stash push -p`, que pregunta hunk a hunk.

## Conflictos al aplicar

Si el código cambió mientras tanto, el stash puede chocar con lo nuevo. Se apartó un cambio en `pagos/api.py`; después, un commit tocó la misma línea:

```bash
git stash pop
```

```
Auto-merging pagos/api.py
CONFLICT (content): Merge conflict in pagos/api.py
...
The stash entry is kept in case you need it again.
```

Git deja marcadores de conflicto en el fichero (resolución explicada en [Fusion-y-conflictos.md](Fusion-y-conflictos.md)) y **conserva la entrada**. Una vez resuelto el fichero se elimina a mano:

```bash
git add pagos/api.py
git restore --staged pagos/api.py   # opcional: dejar los cambios sin preparar
git stash drop
```

Si el stash es antiguo y el código ha cambiado mucho, `git stash branch <nombre>` crea una rama en el commit donde se hizo el stash, aplica ahí los cambios y borra la entrada. En esa rama encajan sin conflicto y se integran después como cualquier otra rama:

```bash
git stash branch rama-rescate
```

```
Switched to a new branch 'rama-rescate'
On branch rama-rescate
Changes to be committed:
```

## Recuperar un stash borrado

Un `drop` (o un `pop` ya aplicado) no destruye el contenido: la entrada deja de estar en la lista, pero el commit sigue en la base de datos de Git hasta que el recolector de basura lo limpia. `git stash drop` y `pop` imprimen el hash en la línea `Dropped refs/stash@{0} (ce6f055...)`; si se conserva, basta aplicarlo:

```bash
git stash apply ce6f055
```

Si no, se buscan los commits huérfanos que son stashes (son commits de fusión):

```bash
git fsck --no-reflog --unreachable | awk '/commit/{print $3}' | xargs git log --merges --no-walk --format='%h %ad %s' --date=short
```

```
771399d 2026-10-30 WIP on main: f35bea1 Timeout en cobro
ce6f055 2026-10-30 On main: reintentos de cobro
8c131d3 2026-10-30 On main: solo pagos
```

Se identifica la entrada por su mensaje, se aplica con `git stash apply <hash>` y, si se quiere de vuelta en la lista, `git stash store -m "recuperado" <hash>`.

## Errores frecuentes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `Your local changes ... would be overwritten by checkout` | Hay cambios que chocan con la rama de destino | `git stash push -u`, cambiar de rama, `git stash pop` |
| Tras `git stash`, un fichero nuevo sigue en el árbol | `stash` sin `-u` ignora ficheros sin rastrear | `git stash push -u` |
| `CONFLICT` al hacer `pop` | La base cambió | Resolver y `git stash drop`, o `git stash branch` |
| Aparece el mismo cambio dos veces semanas después | El `pop` con conflicto no borró la entrada y se volvió a aplicar | `git stash list` periódico y `drop` de lo que sobra |
| `No local changes to save` | No hay nada que guardar, o solo hay ficheros nuevos sin `-u` | Revisar `git status` |
| `error: Your local changes to the following files would be overwritten by merge` al hacer `pop` | Ya hay cambios locales en los mismos ficheros | Confirmarlos o apartarlos antes |

## Cuándo no usarlo

- Para conservar trabajo más de unos días: un commit en una rama de trabajo (ver [Ramas.md](Ramas.md)) se ve, se sube y se nombra.
- Para deshacer cambios que no se quieren: es una operación de [Deshacer-cambios.md](Deshacer-cambios.md).
- Como mecanismo de traspaso entre máquinas: el stash no viaja con `git push`.

## Buenas prácticas avanzadas

- **Poner siempre `-m`** — `WIP on main: 8d37dc7 Aplica IVA en pagos` describe el commit de partida, no el contenido. Con tres entradas ya no se sabe cuál es cuál.
- **`-u` como costumbre** — sin él, un fichero nuevo se queda fuera y el árbol «limpio» no lo está; luego se cree que la entrada lo contiene.
- **Un stash con conflicto no se borra solo** — tras resolver, `git stash drop`; si no, la entrada sigue ahí y se reaplica por error.
- **`git stash branch` para entradas viejas** — evita conflictos al partir del commit original.
- **El stash es recuperable, pero no eternamente** — los commits huérfanos los elimina `git gc` pasado el tiempo de gracia (por defecto, 2 semanas para objetos no alcanzables); si se borró algo valioso, conviene recuperarlo cuanto antes con `fsck`.

## Documentación oficial

- [git-stash](https://git-scm.com/docs/git-stash) — referencia completa; las secciones de `push` y `branch` explican las opciones que aquí solo se citan.

---

*En resumen: `git stash` es el cajón donde se aparta el trabajo a medias para cambiar de contexto; se nombra, se incluyen los ficheros nuevos con `-u` y no sustituye a un commit.*
