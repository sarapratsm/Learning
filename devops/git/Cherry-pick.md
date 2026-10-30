# Cherry-pick

## ¿Qué es?

`git cherry-pick` copia uno o varios commits concretos de cualquier rama y los aplica como commits nuevos sobre la rama actual, sin traer el resto del trabajo de la rama de origen.

## ¿Por qué existe?

A veces hace falta *un* cambio de otra rama, no todo su trabajo. En el repositorio `tienda`, alguien corrige en `main` el redondeo del total en el servicio `pagos`, pero la versión en producción es la rama `release/1.4` y necesita ese arreglo ya, sin las funciones a medias que `main` ha acumulado desde entonces. Fusionar `main` traería todo; cherry-pick toma justo el commit.

> Como indica el nombre (*recoger cerezas*), se elige un commit concreto del árbol y se lleva a otro sitio, dejando el resto.

## ¿Cuándo y para qué se usa?

- **Hotfix y backport**: llevar un arreglo de `main` a una rama de versión que sigue en producción (`release/1.4`).
- **Commit en la rama equivocada**: pasarlo a la correcta (y luego quitarlo de la primera, ver [Deshacer-cambios.md](Deshacer-cambios.md)).
- **Rescatar un commit** de una rama que se descarta.

Para integrar una rama entera se usa `merge` (ver [Fusion-y-conflictos.md](Fusion-y-conflictos.md)) o `rebase` (ver [Rebase.md](Rebase.md)).

## Copiar un commit

Se localiza el commit en la rama de origen y se aplica en la de destino. En `main`:

```bash
git log --oneline main -3
```

```
15055d3 Añade pagos en cuotas
7e7ed9b Corrige redondeo del total en pagos
b0eba77 Refactor de pagos
```

El arreglo es `7e7ed9b`. En `release/1.4`:

```bash
git switch release/1.4
git cherry-pick 7e7ed9b
```

```
[release/1.4 9b529a7] Corrige redondeo del total en pagos
 Date: Fri Oct 30 08:31:30 2026 +0100
 1 file changed, 1 insertion(+)
 create mode 100644 pagos/total_fix.py
```

Se ha creado un commit nuevo (`9b529a7`) con el mismo cambio, mensaje y autoría, pero otro hash. El original sigue en `main`: es una copia, no un movimiento.

## Dejar rastro con `-x`

```bash
git cherry-pick -x 7e7ed9b
```

Añade al mensaje del commit nuevo una línea con el origen:

```
Corrige redondeo del total en pagos

(cherry picked from commit 7e7ed9bbef737236885912128b87b5df61635712)
```

Es la única pista de que `release/1.4` y `main` contienen el mismo arreglo, porque Git no relaciona copias por hash. En un backport conviene usarlo siempre; `-x` solo tiene sentido cuando el commit de origen es público.

## Varios commits y rangos

```bash
git cherry-pick -x b0eba77 7e7ed9b          # dos commits sueltos, en ese orden
git cherry-pick -x b0eba77^..7e7ed9b        # el rango, incluido el primero
```

```
[release/1.4 c4820eb] Refactor de pagos
[release/1.4 4b7f034] Corrige redondeo del total en pagos
```

La sintaxis `A..B` **excluye** `A`; para incluirlo se escribe `A^..B`. Los commits se aplican en el orden de la historia.

## Aplicar sin commitear: `-n`

```bash
git cherry-pick -n b0eba77 7e7ed9b
```

```
A  pagos/redondeo.py
A  pagos/total_fix.py
```

Los cambios quedan en el área de preparación (ver [Area-de-preparacion.md](Area-de-preparacion.md)) sin commits. Sirve para juntar varios commits en uno solo con un mensaje propio, o para revisar el resultado antes de confirmar.

## Conflictos

El commit se aplica sobre una rama que no tiene su contexto; si el código ha divergido, hay conflicto. En `release/1.4` se hizo un hotfix sobre `pagos/conflicto.py`, y en `main` se cambió después esa misma línea:

```bash
git cherry-pick -x main
```

```
Auto-merging pagos/conflicto.py
CONFLICT (content): Merge conflict in pagos/conflicto.py
error: could not apply cb8efac... Cobro con timeout (v3)
hint: After resolving the conflicts, mark them with
hint: "git add/rm <pathspec>", then run
hint: "git cherry-pick --continue".
hint: You can instead skip this commit with "git cherry-pick --skip".
hint: To abort and get back to the state before "git cherry-pick",
hint: run "git cherry-pick --abort".
```

Se resuelve el fichero (ver [Fusion-y-conflictos.md](Fusion-y-conflictos.md)), se añade y se continúa:

```bash
git add pagos/conflicto.py
git cherry-pick --continue
```

| Orden | Efecto |
|---|---|
| `--continue` | Termina el commit con el conflicto resuelto |
| `--skip` | Salta este commit y sigue con el siguiente del rango |
| `--abort` | Devuelve la rama al estado anterior al cherry-pick |

La causa habitual de un conflicto es que el commit **depende de otros previos** que no están en la rama de destino (aquí, un refactor anterior). Cherry-pick copia solo el cambio de ese commit, no sus dependencias.

## Duplicación de commits

La copia y el original no son «el mismo commit»: tienen hashes distintos. Si más tarde se fusiona la rama de origen completa, Git ve dos commits con el mismo efecto. Si el cambio coincide exactamente, lo absorbe sin conflicto, pero ambos aparecen en la historia:

```
*   03e4905 Merge feature/x
|\
| * 610b5b9 Más trabajo
| * 713ef8f Corrige redondeo
* | fc58119 Corrige redondeo
|/
* 3203cb0 Base
```

El mismo «Corrige redondeo» figura dos veces. Si entre medias el código tocó esas líneas, el resultado es un conflicto difícil de entender. Por eso cherry-pick se reserva para direcciones que **no se vuelven a fusionar** (de `main` hacia una rama de versión) y se evita entre ramas que acabarán encontrándose: ahí lo correcto es `merge` o `rebase`.

`git cherry -v <destino> <origen>` lista los commits del origen que aún no tienen equivalente en el destino (marcados con `+`), comparando por contenido del cambio, no por hash.

## Errores frecuentes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `error: commit 790d457... is a merge but no -m option was given.` | Se intenta copiar un commit de fusión (dos padres) | `git cherry-pick -m 1 <commit>`: calcula el cambio respecto al primer padre |
| `CONFLICT (content)` | Falta contexto de commits previos | Resolver, o traer también los commits de los que depende |
| `The previous cherry-pick is now empty, possibly due to conflict resolution.` | Tras resolver, no queda ningún cambio (ya estaba en la rama) | `git cherry-pick --skip`, o `git commit --allow-empty` si se quiere conservar |
| `fatal: bad revision` | Hash incorrecto o commit no disponible en el repositorio local | `git fetch` y revisar el hash |
| El mismo cambio duplicado tras un merge | Se copió con cherry-pick y luego se fusionó la rama de origen | Evitar la combinación; ver apartado «Duplicación de commits» |

## Cuándo no usarlo

- Para llevar de una rama a otra *todo* el trabajo: `merge` o `rebase`.
- Entre dos ramas que acabarán fusionándose.
- Como flujo habitual de integración: cada copia es un commit nuevo que luego hay que reconciliar.
- Cuando el commit depende de una cadena larga de cambios previos.

## Buenas prácticas avanzadas

- **`-x` en todo backport** — es la única trazabilidad entre la copia y el original.
- **Copiar en una dirección única** — de `main` hacia las ramas `release/*`, nunca de vuelta; así el historial no se cruza.
- **`-m 1` para commits de fusión** — Git necesita saber respecto a qué padre calcular el cambio; el primero es la rama que recibió la fusión.
- **Cherry-pick de un rango con `-n` para un único commit limpio** — varios commits de un arreglo se reducen a uno antes de comitear en la rama de versión.
- **Comprobar con `git cherry`** antes de dar por hecho que un arreglo ya está en ambas ramas.

## Documentación oficial

- [git-cherry-pick](https://git-scm.com/docs/git-cherry-pick) — referencia con las opciones `-x`, `-n`, `-m` y la sintaxis de rangos; la sección de ejemplos cubre los casos habituales.

---

*En resumen: cherry-pick es las pinzas para llevar un commit suelto a otra rama; úsalo para hotfixes y backports con `-x`, y no entre ramas que acabarán fusionándose.*
