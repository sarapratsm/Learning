# git switch

## ¿Qué es?

`git switch` es el comando para **cambiar de rama** y, opcionalmente, crear una nueva en el mismo paso. Mueve `HEAD` a otra rama y actualiza los archivos de la carpeta para reflejar su contenido.

## ¿Por qué existe?

Durante años, una sola orden (`git checkout`) hacía cosas muy distintas: cambiar de rama, crear ramas, situarse en un commit antiguo y también **descartar cambios de archivos**. El mismo comando servía para moverse y para destruir trabajo, y un despiste (`git checkout pagos` donde `pagos` era un archivo y no una rama) podía costar horas de cambios.

Git 2.23 (2019) lo dividió en dos comandos con una sola responsabilidad: `git switch` para moverse entre ramas y `git restore` para tocar archivos. `git checkout` sigue funcionando y seguirá, pero lo habitual hoy es usar los nuevos.

> Si vienes de `git checkout`, `git switch` es la «mitad de ramas» de aquel comando: lo mismo, pero sin riesgo de descartar archivos por error.

| Antes | Ahora |
|---|---|
| `git checkout main` | `git switch main` |
| `git checkout -b feat/emails` | `git switch -c feat/emails` |
| `git checkout -` | `git switch -` |
| `git checkout a1b2c3d` | `git switch --detach a1b2c3d` |
| `git checkout -- pagos/pagos.py` | `git restore pagos/pagos.py` |

## ¿Cuándo y para qué se usa?

- **Moverse a otra rama** para seguir trabajando allí: pasar de `main` a la rama del servicio `emails`.
- **Crear una rama nueva** y situarse en ella al empezar una tarea.
- **Alternar entre dos tareas** sin escribir los nombres.
- **Mirar un commit antiguo** sin tocar ninguna rama.

---

## Cambiar de rama y crearla

Ejemplo guiado en el repositorio `tienda`. Se empieza en `main` y se abre una rama para el envío de correos:

```bash
git switch -c feat/emails
```

```
Switched to a new branch 'feat/emails'
```

`-c` (*create*) crea la rama a partir del commit actual y se cambia a ella; equivale a `git branch feat/emails` seguido de `git switch feat/emails` (véase [Ramas](Ramas.md)). Para ramificar desde otro punto, se añade el origen:

```bash
git switch -c fix/pedido-4711 main
```

Volver a una rama existente:

```bash
git switch main
```

```
Switched to branch 'main'
```

Si el nombre no existe, Git lo dice y no hace nada:

```
fatal: invalid reference: nope
```

Y si se intenta crear una rama con un nombre ya usado:

```
fatal: a branch named 'feat/inventario' already exists
```

### Volver a la rama anterior: `git switch -`

```bash
git switch -
```

El guion significa «la rama en la que estabas antes», como el botón «atrás» de un navegador. Ejecutarlo dos veces seguidas devuelve al punto de partida: cómodo para alternar entre una rama de trabajo y `main`.

### Empezar a trabajar sobre una rama del remoto

Si una compañera ha subido `feat/pagos` y tú no la tienes en local:

```bash
git fetch
git switch feat/pagos
```

```
branch 'feat/pagos' set up to track 'origin/feat/pagos'.
Switched to a new branch 'feat/pagos'
```

Git detecta que existe `origin/feat/pagos`, crea la rama local y la conecta con ella. Sin `-c` y sin configurar nada. Cómo funcionan los remotos está en [Remotos](Remotos.md).

## Qué pasa con los cambios sin confirmar

Cambiar de rama sustituye los archivos de la carpeta por los de la otra rama, así que la pregunta es qué ocurre con lo que se haya modificado sin hacer commit. Hay dos casos.

**Los archivos modificados no difieren entre las dos ramas: Git deja pasar los cambios.** Se llevan puestos a la nueva rama:

```bash
echo "cambio" >> pedidos/app.py
git switch feat/inventario
```

```
Switched to branch 'feat/inventario'
M	pedidos/app.py
```

La `M` indica que `pedidos/app.py` sigue modificado, ahora en `feat/inventario`. Es útil para el caso «empecé a trabajar en `main` y debía hacerlo en una rama»: `git switch -c <nombre>` traslada los cambios sin más. Y explica por qué a veces «aparecen» cambios en otra rama: no han aparecido, han viajado.

**Los archivos modificados sí difieren entre las dos ramas: Git se niega.** Cambiar obligaría a sobrescribir el trabajo sin confirmar:

```
error: Your local changes to the following files would be overwritten by checkout:
	pedidos/app.py
Please commit your changes or stash them before you switch branches.
Aborting
```

(El texto dice `checkout` porque `switch` comparte el mecanismo con el comando antiguo.) Las salidas son:

| Quieres... | Haz |
|---|---|
| Conservar el trabajo en la rama actual | `git add` y `git commit` antes de cambiar. |
| Guardarlo a un lado para recuperarlo después | `git stash` ([Stash](Stash.md)), cambiar, y `git stash pop` al volver. |
| Llevarlo contigo e intentar mezclarlo con la rama destino | `git switch -m <rama>` (puede dejar conflictos que resolver, véase [Fusión y conflictos](Fusion-y-conflictos.md)). |
| Tirarlo a la basura | `git switch --discard-changes <rama>` (o `-f`): irreversible. |

## Mirar un commit antiguo: `--detach`

```bash
git switch --detach 178b038
```

```
HEAD is now at 178b038 Primer commit
```

`HEAD` queda apuntando a un commit y no a una rama: es el estado de `HEAD` desacoplado (*detached HEAD*). Sirve para inspeccionar el proyecto como estaba entonces, compilar una versión antigua o reproducir un error. `git branch` lo señala:

```
* (HEAD detached at 178b038)
  feat/inventario
  main
```

Si se hacen commits en este estado, no los sigue ninguna rama y se pierden al cambiar. Para conservarlos, se crea una rama en ese punto antes de irse:

```bash
git switch -c fix/rescate
```

Sin cambios que guardar, `git switch main` vuelve a una rama normal.

## `git restore`, la otra mitad

`git restore` actúa sobre **archivos**, no sobre ramas, y por eso es el que destruye cambios (con intención):

```bash
git restore pagos/pagos.py
```

Descarta las modificaciones sin preparar de ese archivo y lo devuelve al último commit, sin mensaje de salida. Con `--staged` hace lo contrario, ocuparse solo de la preparación:

```bash
git restore --staged pagos/pagos.py
```

Saca el archivo del [área de preparación](Area-de-preparacion.md) pero conserva los cambios en el disco. Todo el abanico de formas de deshacer (incluido `restore --source`) está en [Deshacer cambios](Deshacer-cambios.md).

## Errores frecuentes

| Síntoma | Causa y solución |
|---|---|
| `error: Your local changes to the following files would be overwritten by checkout` | Cambios sin confirmar que chocan con la rama destino: commit, stash o `-m`. |
| `fatal: invalid reference: nope` | La rama no existe en local; revisar el nombre con `git branch -a` o hacer `git fetch` si debería venir del remoto. |
| `fatal: a branch named '...' already exists` | `-c` sobre un nombre ya usado; cambiar a ella sin `-c` o elegir otro nombre. |
| Tras `git switch --detach`, los commits «desaparecen» | Se hicieron sin rama. `git reflog` muestra sus hashes y `git switch -c <nombre> <hash>` los rescata. |
| `git switch archivo.txt` falla | `switch` solo mueve entre ramas; para archivos es `git restore`. |

## Cuándo no usarlo

- **Para deshacer cambios en un archivo**: es trabajo de `git restore`.
- **Para trabajar en dos ramas a la vez** (compilar una mientras editas otra): cambiar de rama sin parar es incómodo y tira de cachés; `git worktree` crea una segunda carpeta enlazada al mismo repositorio.
- **Con una carpeta de trabajo sucia sin saber qué hay**: antes de cambiar, `git status` evita arrastrar sin querer cambios a la rama equivocada.

## Buenas prácticas avanzadas

- **`git status` antes de `switch`** — como los cambios sin confirmar viajan, la costumbre de mirar el estado evita sorpresas y commits en la rama equivocada.
- **`switch -c` para rescatar un commit hecho en `main` por error** — si ya se confirmó en `main` lo que iba en una rama, `git switch -c feat/emails` crea la rama en ese punto con el commit incluido; después se devuelve `main` a su sitio ([Deshacer cambios](Deshacer-cambios.md)).
- **`--discard-changes` no se escribe de memoria** — es el único caso en que `switch` es tan destructivo como el viejo `checkout`; que sea una decisión explícita.
- **`git switch -` como atajo de ritmo** — con una rama de trabajo y `main`, alternar con `-` es más rápido que escribir los nombres y no se equivoca de rama.
- **Mueve el seguimiento al cambiar de rama remota** — si dos remotos tienen una rama con el mismo nombre, `git switch` no sabe cuál elegir y hay que indicarlo (`git switch -c feat/pagos --track origin/feat/pagos`).

## Documentación oficial

- [git-switch](https://git-scm.com/docs/git-switch) — todas las opciones (`-c`, `-C`, `-m`, `--detach`, `--track`); las secciones de ejemplos y de `--guess` son las más claras.

---

*En resumen: `git switch` solo mueve entre ramas y las crea con `-c`; los cambios sin confirmar viajan contigo salvo que choquen, y para tocar archivos existe `git restore`.*
