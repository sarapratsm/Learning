# Ramas (branches)

## ¿Qué es?

Una rama es una línea de trabajo independiente dentro del repositorio: un nombre que apunta a un commit y que avanza con cada commit nuevo que se hace estando en ella. Permite desarrollar cambios sin tocar la versión principal hasta que estén listos para combinarse.

## ¿Por qué existe?

En la tienda online `tienda`, imagina que hay que añadir un nuevo método de pago al servicio `pagos` mientras otra persona corrige un error urgente en `pedidos`. Si las dos trabajaran sobre la misma línea de commits, cada cambio a medias rompería el trabajo de la otra. Con ramas, cada tarea avanza en su propia línea y la rama principal sigue siendo una versión que funciona. Si la idea sale bien se combina; si no, se descarta y la rama principal nunca se enteró.

> Piensa en un videojuego: una rama es una partida guardada aparte donde pruebas una estrategia arriesgada. Si funciona, sigues desde ahí; si no, vuelves a tu partida principal intacta.

## ¿Cuándo y para qué se usa?

- Desarrollar una **función nueva** sin desestabilizar lo que ya funciona.
- **Arreglar un error urgente** mientras otra persona sigue con su trabajo.
- **Probar ideas** que quizá se descarten.
- Preparar un **pull request**: la propuesta de cambio se hace desde una rama ([Pull requests](Pull-requests.md)).

La rama principal suele llamarse `main` (o `master` en repositorios antiguos). El resto son ramas temporales que se crean, se combinan y se borran.

---

## Una rama es un puntero

Una rama no es una copia de la carpeta ni una lista de commits: es un fichero diminuto con el identificador de un único commit. Se puede comprobar en un repositorio recién creado:

```bash
cat .git/refs/heads/main
```

```
178b03834de513cc311ce6e138944ecf06c4bbdd
```

Esos 40 caracteres hexadecimales (más el salto de línea, 41 bytes) son toda la rama `main`. Por eso crear una rama es instantáneo y barato: Git escribe un fichero de 41 bytes, sin copiar nada. Cada commit nuevo mueve el puntero de la rama actual un paso adelante.

### `HEAD`: dónde estás

`HEAD` es otro puntero, que dice **qué rama tienes activa**:

```bash
cat .git/HEAD
```

```
ref: refs/heads/main
```

Al hacer un commit, Git lo cuelga del commit al que apunta la rama que señala `HEAD`, y mueve esa rama. Cambiar de rama es, en esencia, cambiar a dónde apunta `HEAD` y actualizar los archivos de la carpeta para que reflejen ese commit (el comando para hacerlo, [`git switch`](Switch.md), tiene su propia ficha).

## Crear y listar ramas

```bash
git branch feat/inventario
git branch
```

```
  feat/inventario
* main
```

`git branch <nombre>` crea la rama apuntando al commit actual, **pero no cambia a ella**; sigues en `main`. El asterisco marca la rama activa. Para crearla y moverse en un paso, `git switch -c <nombre>` (véase [Switch](Switch.md)).

Para ver desde qué commit sale cada una:

```bash
git branch -vv
```

```
  feat/inventario 178b038 Primer commit
* fix/pagos-iva   178b038 Primer commit
  main            178b038 Primer commit
```

Las tres apuntan al mismo commit `178b038`: de momento las ramas no se distinguen. Divergen en cuanto cada una recibe commits propios. Crear una rama desde un punto distinto de la posición actual se indica con un segundo argumento:

```bash
git branch fix/pagos-iva main
git switch -c fix/pagos-iva main
```

Ambos arrancan la rama desde `main` estés donde estés.

## Convenciones de nombres

Git acepta casi cualquier nombre (sin espacios, sin `..`, sin empezar por `-`). La barra `/` permite agrupar por categorías, y eso es lo que usan casi todos los equipos:

| Prefijo | Para qué | Ejemplo |
|---|---|---|
| `feat/` o `feature/` | Función nueva | `feat/inventario-reservas` |
| `fix/` | Corrección de error | `fix/iva-pagos` |
| `hotfix/` | Corrección urgente sobre producción | `hotfix/pedido-4711-duplicado` |
| `chore/`, `docs/`, `refactor/` | Mantenimiento, documentación, reestructuración | `docs/readme-emails` |
| `release/` | Preparación de una versión | `release/2.4` |

Reglas útiles: minúsculas y guiones; que el nombre diga **qué** hace la rama (no `cambios` ni `pruebas2`); y, si el equipo usa un gestor de tareas, incluir su identificador (`feat/TIENDA-231-reservas`). Los flujos de trabajo completos que dan significado a `main`, `develop`, `release/` y `hotfix/` están en [Git Flow](Git-Flow.md).

## Renombrar y borrar

```bash
git branch -m fix/pagos-iva fix/iva-pagos
```

`-m` (*move*) renombra una rama. Para borrar:

```bash
git branch -d fix/iva-pagos
```

`-d` solo borra si la rama ya está combinada. Si tiene commits que no están en ninguna otra rama, Git se niega:

```
error: the branch 'fix/iva-pagos' is not fully merged
hint: If you are sure you want to delete it, run 'git branch -D fix/iva-pagos'
```

Con `-D` se borra igualmente, y Git informa de cuál era el último commit (`Deleted branch fix/iva-pagos (was 757a34e).`). Con ese hash se puede recrear la rama durante un tiempo, si fue un error (`git branch fix/iva-pagos 757a34e`). No se puede borrar la rama en la que estás: hay que cambiar antes a otra.

Para decidir qué borrar sin ir de memoria:

```bash
git branch --merged main
git branch --no-merged main
```

```
  feat/inventario
* main
```

`--merged` lista las ramas cuyo contenido ya está en `main` (se pueden borrar sin pérdida). `--no-merged` lista las que aún tienen trabajo propio; en el ejemplo de arriba no hay ninguna. La combinación de ramas está en [Fusión y conflictos](Fusion-y-conflictos.md).

## Ramas de seguimiento (tracking) y remotas

Cuando un repositorio tiene un remoto (normalmente `origin`), una rama local puede **seguir** a una rama del remoto: Git sabe con cuál comparar y de cuál tirar. `git branch -vv` lo muestra entre corchetes:

```
* feat/pagos 086912a [origin/feat/pagos: ahead 1] Local
  main       2a28e9c [origin/main] Inicio
```

`ahead 1` significa un commit local sin subir; `behind 2` sería dos commits del remoto sin bajar. Las referencias `origin/...` son copias locales del estado del remoto, que se actualizan con `git fetch`. Lo explican con detalle [Remotos](Remotos.md).

Dos formas de crear el seguimiento:

```bash
git push -u origin feat/pagos
git switch feat/pagos
```

```
branch 'feat/pagos' set up to track 'origin/feat/pagos'.
```

La primera sube la rama y fija el seguimiento (`-u`). La segunda funciona cuando la rama existe en `origin` pero no en local: Git la crea y la conecta sola.

Para borrar una rama del remoto (por ejemplo, tras combinar un pull request):

```bash
git push origin --delete feat/pagos
git fetch -p
```

`fetch -p` (*prune*) elimina las referencias locales a ramas que ya no existen en el remoto. Si no se hace, una rama local cuya remota ha desaparecido queda así:

```
* feat/pagos 086912a [origin/feat/pagos: gone] Local
```

y `git status` avisa `Your branch is based on 'origin/feat/pagos', but the upstream is gone.` La rama local puede borrarse o reconectarse con `git branch --unset-upstream`.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `fatal: a branch named 'feat/inventario' already exists` | Ya hay una rama con ese nombre; usar otro o cambiar a ella con `git switch`. |
| `error: the branch 'x' is not fully merged` | Tiene commits sin combinar; revisar con `git log main..x` antes de forzar con `-D`. |
| Una rama nueva «arrastra» commits ajenos | Se creó desde la posición actual, que era otra rama a medias, en lugar de desde `main`. |
| `HEAD detached at ...` | `HEAD` apunta a un commit y no a una rama; véase [Switch](Switch.md). |
| Se borró una rama con trabajo | Los commits siguen en Git un tiempo: `git reflog` muestra su hash y `git branch <nombre> <hash>` la recrea. |

## Cuándo no usar una rama

- Para **un cambio trivial** (una errata) en un repositorio personal: una rama más es burocracia sin beneficio.
- Para **guardar trabajo a medias unos minutos** mientras se atiende otra cosa: [Stash](Stash.md) lo resuelve sin crear nombres.
- Para **mantener durante meses** una rama paralela de una función enorme: cuanto más tiempo vive, más difícil es combinarla. Mejor ramas cortas y combinar a menudo.

## Buenas prácticas avanzadas

- **Di siempre desde dónde nace la rama** — `git switch -c fix/iva-pagos main` evita crear una rama encima de otra a medias; sin el último argumento, la nueva hereda los commits de la posición actual y el pull request sale contaminado.
- **Ramas cortas, combinadas a menudo** — una rama de dos días se combina sin dolor; una de dos meses acumula conflictos. Si una función es grande, se divide en ramas sucesivas pequeñas.
- **Limpia con `--merged` y `fetch -p`** — tras cada combinación, borra la rama local y la remota; el listado de `git branch` sigue siendo útil solo si contiene ramas vivas.
- **`git branch -vv` antes de empezar el día** — detecta ramas con `behind` acumulado antes de que la fusión se complique.
- **Proteger `main` en el remoto** — las plataformas permiten prohibir pushes directos a `main` y exigir pull request; es la red de seguridad que sustituye a la disciplina individual ([Pull requests](Pull-requests.md)).

## Documentación oficial

- [git-branch](https://git-scm.com/docs/git-branch) — todas las opciones de `branch`; las secciones de `--merged`, `-m` y seguimiento de ramas son las más útiles.
- [Pro Git: Branches in a Nutshell](https://git-scm.com/book/en/v2/Git-Branching-Branches-in-a-Nutshell) — explicación con diagramas de qué es una rama como puntero y qué hace `HEAD`.

---

*En resumen: una rama es un puntero de 41 bytes a un commit, y `HEAD` indica cuál tienes activa; por ser tan baratas conviene crear una por tarea, nombrarla por lo que hace y borrarla en cuanto se combine.*
