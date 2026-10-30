# Rebase

## ¿Qué es?

*Rebase* vuelve a aplicar los commits de una rama sobre otro punto de partida, normalmente la punta más reciente de otra rama. Cada commit se copia como uno nuevo (con otro hash), y la rama queda como una línea recta que arranca desde ese punto.

## ¿Por qué existe?

Mientras se trabaja en una rama, la rama principal sigue avanzando. Para ponerse al día hay dos caminos: fusionar (`merge`, ver [Fusion-y-conflictos.md](Fusion-y-conflictos.md)) o rebasar.

- **Merge** junta las dos líneas con un commit de fusión extra. El historial conserva la verdad de que hubo dos ramas paralelas, pero se enreda.
- **Rebase** finge que el trabajo empezó *hoy* sobre el último estado de `main`. El historial queda recto y se lee de arriba abajo.

> Imagina que escribiste tu capítulo partiendo de la edición 3 de un libro y ya va por la edición 5. Hacer rebase es reescribir tu capítulo como si hubiera nacido de la edición 5.

Un ejemplo con el repositorio `tienda`. La rama `feature/pedido-4711` (validación y cálculo del total del pedido #4711, en el servicio `pedidos`) salió de `main`, y mientras tanto `main` recibió el commit «Aplica IVA en pagos»:

```
* 235ba77 Arregla typo
* 6a8350f Calcula total del pedido
* 4a9813f WIP
* b6a3e39 Valida el pedido
| * 6328bda Aplica IVA en pagos        <- main
|/
* 20a544b Añade README
```

```bash
git switch feature/pedido-4711
git rebase main
```

```
Rebasing (1/4)Rebasing (2/4)Rebasing (3/4)Rebasing (4/4)Successfully rebased and updated refs/heads/feature/pedido-4711.
```

```
* d38d5bd Arregla typo
* 11bc6b4 Calcula total del pedido
* 43b9ff2 WIP
* ec51d6f Valida el pedido
* 6328bda Aplica IVA en pagos
* 20a544b Añade README
```

Los cuatro commits ahora cuelgan de «Aplica IVA en pagos». Sus hashes han cambiado (`b6a3e39` pasó a `ec51d6f`): son copias, no los mismos commits. De ahí salen todas las precauciones de esta ficha.

## ¿Cuándo y para qué se usa?

- **Actualizar una rama de trabajo** con lo último de `main` antes de abrir o mientras está abierta una *pull request* (ver [Pull-requests.md](Pull-requests.md)).
- **Limpiar commits propios** antes de compartirlos: unir los de «WIP», quitar los de depuración, reescribir mensajes (rebase interactivo).
- **Trasplantar una rama** que nació encima de otra equivocada (`--onto`).

## Rebase o merge

| Situación | Mejor opción | Por qué |
|---|---|---|
| Rama de función propia, aún sin subir, que quiere ponerse al día con `main` | `rebase main` | Historial lineal, sin commits de fusión |
| Rama ya subida y usada por otras personas | `merge` | Rebase reescribiría commits que otras personas ya tienen |
| Integrar la rama terminada en `main` | `merge` (o *squash merge* en la plataforma) | Deja constancia de la integración |
| Quitar `WIP` y typos antes de la revisión | `rebase -i` | Es la única herramienta que edita commits ya hechos |
| Rama apoyada en otra rama de función equivocada | `rebase --onto` | Mueve solo los commits propios |
| Rama compartida de larga vida (`main`, `release/*`) | Nunca rebase | Todo el equipo depende de esos hashes |

## Rebase interactivo: limpiar los commits propios

`git rebase -i` abre un editor con la lista de commits que se van a reaplicar y una orden por línea. Antes de la limpieza, la rama `feature/pedido-4711` tiene un commit `WIP` suelto y un typo que pertenece a «Valida el pedido»:

```bash
git rebase -i main
```

El editor muestra (el primero es el más antiguo, al revés que `git log`):

```
pick ec51d6f # Valida el pedido
pick 43b9ff2 # WIP
pick 11bc6b4 # Calcula total del pedido
pick d38d5bd # Arregla typo

# Commands:
# p, pick <commit> = use commit
# r, reword <commit> = use commit, but edit the commit message
# e, edit <commit> = use commit, but stop for amending
# s, squash <commit> = use commit, but meld into previous commit
# f, fixup [-C | -c] <commit> = like "squash" but keep only the previous
#                    commit's log message, unless -C is used, ...
# d, drop <commit> = remove commit
```

Las órdenes que se usan a diario:

| Orden | Qué hace |
|---|---|
| `pick` | Conserva el commit tal cual |
| `reword` | Conserva el cambio y abre el editor para cambiar el mensaje |
| `squash` | Funde el commit con el anterior y junta ambos mensajes en el editor |
| `fixup` | Igual que `squash`, pero descarta el mensaje del commit fundido |
| `drop` | Elimina el commit (borrar la línea hace lo mismo, pero `drop` es explícito) |
| `edit` | Detiene el rebase en ese commit para modificarlo; se sigue con `--continue` |

Para quedarse sin `WIP` y con el typo absorbido por el commit al que pertenece, se reordena y se cambian las órdenes:

```
pick ec51d6f # Valida el pedido
fixup d38d5bd # Arregla typo
drop 43b9ff2 # WIP
pick 11bc6b4 # Calcula total del pedido
```

Al guardar y cerrar el editor, Git ejecuta las líneas de arriba abajo:

```
Successfully rebased and updated refs/heads/feature/pedido-4711.
```

```
452a715 Calcula total del pedido
15601c7 Valida el pedido
8d37dc7 Aplica IVA en pagos
```

Cuatro commits quedaron en dos, con mensajes que cuentan qué se hizo y no cómo se llegó ahí. Si al soltar un commit con `drop` o al reordenar otros dos tocan las mismas líneas, Git se detiene con un conflicto (siguiente sección).

## Conflictos, `--continue` y `--abort`

Como el rebase reaplica los commits uno a uno, un conflicto puede aparecer en cualquiera de ellos. Aquí `main` fijó el IVA en 21 % y una rama propia lo fijó en 10 % sobre el mismo fichero:

```
Auto-merging pagos/iva.py
CONFLICT (add/add): Merge conflict in pagos/iva.py
error: could not apply 0bd96d4... IVA reducido 10%
hint: Resolve all conflicts manually, mark them as resolved with
hint: "git add/rm <conflicted_files>", then run "git rebase --continue".
hint: You can instead skip this commit: run "git rebase --skip".
hint: To abort and get back to the state before "git rebase", run "git rebase --abort".
```

El fichero queda con los marcadores habituales:

```
<<<<<<< HEAD
iva=21
=======
iva=10
>>>>>>> 0bd96d4 (IVA reducido 10%)
```

Un detalle que desconcierta: durante un rebase, `HEAD` (la parte de arriba) es **`main`**, el trabajo ya reaplicado, y la parte de abajo es **el commit propio** que se está reaplicando. Es lo contrario de lo que ocurre en un `merge`. Se edita el fichero, se marca como resuelto y se sigue:

```bash
git add pagos/iva.py
git rebase --continue
```

| Orden | Cuándo |
|---|---|
| `git rebase --continue` | Conflicto resuelto y añadido con `git add` |
| `git rebase --skip` | Ese commit ya no hace falta (por ejemplo, `main` ya contiene lo mismo) |
| `git rebase --abort` | Algo va mal: devuelve la rama exactamente al estado anterior al rebase |

`--abort` es seguro en cualquier momento mientras el rebase esté en curso; lo que se hizo en commits anteriores del mismo rebase se descarta junto con él.

## Mover una rama con `--onto`

`git rebase --onto <destino> <origen-antiguo> <rama>` toma los commits de `<rama>` que no están en `<origen-antiguo>` y los replanta sobre `<destino>`. Sirve cuando una rama nació encima de otra rama de función en lugar de `main`: `feature/emails-pedido` (el email de confirmación del pedido #4711, servicio `emails`) se creó sobre `feature/emails-base`, que no debía ser su base:

```
* 82aa92e Email de confirmación del pedido 4711     <- feature/emails-pedido
* ac8cbe0 Base de plantillas de emails              <- feature/emails-base
* 4ec6a9e IVA 21%                                   <- main
```

```bash
git rebase --onto main feature/emails-base
```

La rama actual (`feature/emails-pedido`) se queda solo con los commits que `feature/emails-base` no tiene, y se planta sobre `main`:

```
Rebasing (1/1)Successfully rebased and updated refs/heads/feature/emails-pedido.
```

```
* d56ab1a Email de confirmación del pedido 4711
* 4ec6a9e IVA 21%
```

«Base de plantillas de emails» ya no forma parte de la rama: solo viajó el commit propio.

## Correcciones que se colocan solas: `--fixup` y `--autosquash`

Cuando la revisión pide retocar un commit antiguo de la rama, en lugar de reordenar a mano se crea un commit marcado como corrección de aquel:

```bash
git commit --fixup 15601c7
```

```
a183c9c fixup! Valida el pedido
b52eb08 Calcula total del pedido
15601c7 Valida el pedido
```

Antes de integrar, `--autosquash` coloca cada `fixup!` justo debajo de su commit original y lo marca como `fixup`:

```bash
git rebase -i --autosquash main
```

```
pick 15601c7 # Valida el pedido
fixup a183c9c # fixup! Valida el pedido
pick b52eb08 # Calcula total del pedido
```

Con `git config --global rebase.autoSquash true` se activa siempre.

## La regla: no reescribir historia publicada

Rebase no modifica commits: crea copias con otro hash y abandona los originales. Si otra persona ya tiene los originales, su historial y el tuyo divergen. Tras rebasar una rama que ya estaba en el remoto, el `push` normal se rechaza:

```
 ! [rejected]        feature/pedido-4711 -> feature/pedido-4711 (non-fast-forward)
error: failed to push some refs to '...'
hint: Updates were rejected because the tip of your current branch is behind
hint: its remote counterpart.
```

Es lo esperado: el remoto tiene los commits viejos y se les ha dado otro hash. Solo se fuerza en una rama que nadie más use (la propia rama de una *pull request*, por ejemplo), y con `--force-with-lease`, no con `--force`:

```bash
git push --force-with-lease
```

`--force-with-lease` solo sobrescribe si el remoto sigue como se vio la última vez. Si una compañera subió un commit entre medias:

```
 ! [rejected]        feature/pedido-4711 -> feature/pedido-4711 (stale info)
```

Se aborta en lugar de borrar su trabajo. Con `--force` a secas, ese commit habría desaparecido sin aviso.

Para recuperar un estado anterior al rebase, `git reflog` guarda las posiciones previas (la rama sigue accesible como `ORIG_HEAD` justo después del rebase):

```bash
git reset --hard ORIG_HEAD
```

## Errores frecuentes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `error: cannot rebase: You have unstaged changes.` / `error: Please commit or stash them.` | Hay cambios sin confirmar | Hacer commit o `git stash` (ver [Stash.md](Stash.md)) |
| `! [rejected] ... (non-fast-forward)` al hacer push tras rebasar | Los commits tienen otro hash que en el remoto | `git push --force-with-lease` solo si la rama es de uso propio |
| `! [rejected] ... (stale info)` | El remoto tiene commits que no se han visto | `git fetch`, revisar qué hay de nuevo y volver a rebasar |
| El conflicto se repite en cada commit | Cada commit propio toca las mismas líneas | `git rebase --abort`, unir antes los commits con `squash` y rebasar de nuevo |
| Commits duplicados tras rebasar una rama compartida | Alguien más tenía los originales | Rehacer la rama a partir de `origin/<rama>` (ver [Remotos.md](Remotos.md)) |

Un matiz de `--force-with-lease`: si se ejecuta `git fetch` antes del push, el remoto ya está «visto» y la comprobación pasa aunque haya commits ajenos sin mirar. Hay que revisar `git log origin/<rama>` tras el fetch.

## Cuándo no usarlo

- En ramas compartidas de larga vida: `main`, `develop`, `release/*`.
- Cuando bastaría un `merge` y nadie exige historial lineal: rebase añade riesgo sin que haya ganancia que justifique.
- Para deshacer un cambio ya publicado: eso es un `revert` (ver [Deshacer-cambios.md](Deshacer-cambios.md)).
- Con commits de fusión en medio, si no se entiende `--rebase-merges`: por defecto, rebase los aplana.

## Buenas prácticas avanzadas

- **`git commit --fixup` + `--autosquash` + `rebase.autoSquash`** — durante la revisión se corrigen commits antiguos sin interrumpir el trabajo y se entrega un historial limpio con un solo rebase.
- **`--update-refs` para ramas apiladas** — si la rama B está construida sobre la A, `git rebase --update-refs main` desde B mueve también el puntero de A, que de otro modo quedaría apuntando a los commits viejos.
- **Rebasar antes de abrir la PR, no después de la revisión** — reescribir historia con comentarios ya anclados a commits viejos los deja huérfanos. Una vez abierta, se añaden commits `fixup!` y se limpia al final.
- **Hacer una rama de respaldo antes de un rebase largo** — `git branch respaldo` cuesta nada y evita depender del reflog (que caduca; por defecto 90 días para commits alcanzables y 30 para los que no).
- **`git pull --rebase` para actualizar una rama propia** — equivale a `fetch` + `rebase` sobre su remota y evita los commits «Merge branch 'x' of ...» que ensucian el historial.

## Documentación oficial

- [git-rebase](https://git-scm.com/docs/git-rebase) — manual de referencia. Lo más útil: la sección «Transplanting a topic branch with --onto» y «Recovering from upstream rebase».
- [Pro Git: Rebasing](https://git-scm.com/book/en/v2/Git-Branching-Rebasing) — explicación con diagramas, incluida «The Perils of Rebasing».

---

*En resumen: rebase copia tus commits sobre un punto nuevo para dejar el historial recto; úsalo para ordenar lo tuyo y nunca sobre lo que otras personas ya tienen.*
