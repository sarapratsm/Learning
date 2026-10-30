# git bisect

## ¿Qué es?

`git bisect` es el comando que encuentra el commit que introdujo un error mediante una **búsqueda binaria** por el historial: prueba el commit de la mitad, se le dice si está bien o mal, y descarta la mitad del rango en cada paso.

## ¿Por qué existe?

Algo funcionaba la semana pasada y hoy está roto, pero entre medias hay 200 commits de varias personas. Revisarlos uno a uno, o leer los diffs buscando al sospechoso, es lento y poco fiable. `git bisect` aplica el truco de «adivina el número»: cada respuesta elimina la mitad de los candidatos.

> Es como buscar una palabra en un diccionario: no se empieza por la primera página, se abre por la mitad y según la letra se salta a una mitad u otra. En 10 saltos se cubren 1.000 páginas.

La cifra que lo hace tangible: **n commits se resuelven en unos log₂(n) pasos**. 200 commits son 8 pruebas; 1.000 son 10; 10.000 son 14.

## ¿Cuándo y para qué se usa?

Cuando se sabe que algo se rompió entre una versión que funcionaba y otra que no, pero no en cuál. En la tienda online (repositorio `tienda`, servicios `pedidos`, `pagos`, `inventario` y `emails`): el total del pedido #4711 salía bien en la versión `v1.0.0` y hoy sale mal, y desde entonces hay decenas de commits en los cuatro servicios.

Requiere dos cosas: un commit **donde el problema existe** (normalmente el actual) y otro **donde no existía**, y una forma fiable de comprobarlo en cada commit, a mano o con un script.

## Bisect manual

El escenario de los ejemplos: el repositorio contiene un `total.sh` que calcula el total de un pedido de 2 unidades a 10 € cada una. El resultado correcto es 20; hoy da 24. La etiqueta `v1.0.0` marca la versión que funcionaba y hay diez commits desde entonces.

### 1. Delimitar el rango

```bash
git bisect start
git bisect bad                 # el commit actual tiene el error
git bisect good v1.0.0         # esta versión funcionaba
```

```
status: waiting for both good and bad commits
status: waiting for good commit(s), bad commit known
Bisecting: 4 revisions left to test after this (roughly 2 steps)
[17c79c2144386f195a61d322a293b8f5076cdce0] Cambio 5 en notas
```

Git dice cuántos pasos quedan y deja el directorio de trabajo en el commit de la mitad (en [detached HEAD](Ramas.md): no está en ninguna rama). `bad` y `good` aceptan cualquier referencia: un hash, una etiqueta o una rama. Existe el atajo `git bisect start <malo> <bueno>`.

### 2. Probar y responder

En cada parada se ejecuta la prueba y se responde `good` o `bad` según el resultado:

```bash
sh total.sh                    # imprime 20: este commit está bien
git bisect good
```

```
Bisecting: 2 revisions left to test after this (roughly 1 step)
[9c639629269cdda3af4c397188de5250faac867a] Aplica recargo al total
```

```bash
sh total.sh                    # imprime 24: este ya falla
git bisect bad
```

```
Bisecting: 0 revisions left to test after this (roughly 0 steps)
[b934f5fd9dee6903296dc2d73c6ce5f91b97bcfb] Cambio 6 en notas
```

```bash
sh total.sh                    # imprime 20: este está bien
git bisect good
```

```
9c639629269cdda3af4c397188de5250faac867a is the first bad commit
commit 9c639629269cdda3af4c397188de5250faac867a
Author: Ana <a@x.com>
Date:   Fri Oct 30 08:30:15 2026 +0100

    Aplica recargo al total

 total.sh | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
```

Tres pruebas bastaron para señalar el commit culpable entre diez.

### 3. Volver a la normalidad

```bash
git bisect reset
```

```
Previous HEAD position was b934f5f Cambio 6 en notas
Switched to branch 'main'
```

`reset` devuelve el repositorio a la rama original. Hay que hacerlo siempre al terminar, o se queda el repositorio en detached HEAD en mitad de una búsqueda. Para ver el historial de respuestas dadas: `git bisect log`.

## Bisect automático con `git bisect run`

Si la comprobación se puede expresar como un comando, no hace falta responder a mano. `git bisect run` ejecuta el comando en cada paso y interpreta su **código de salida**.

El script de prueba, `test.sh`:

```bash
#!/bin/sh
# Sale con 0 si el total del pedido de ejemplo es correcto, con 1 si no
[ "$(sh total.sh)" = "20" ]
```

La búsqueda completa, sin intervención:

```bash
git bisect start HEAD v1.0.0
git bisect run sh test.sh
```

```
Bisecting: 4 revisions left to test after this (roughly 2 steps)
[17c79c2144386f195a61d322a293b8f5076cdce0] Cambio 5 en notas
running 'sh' 'test.sh'
Bisecting: 2 revisions left to test after this (roughly 1 step)
[9c639629269cdda3af4c397188de5250faac867a] Aplica recargo al total
running 'sh' 'test.sh'
Bisecting: 0 revisions left to test after this (roughly 0 steps)
[b934f5fd9dee6903296dc2d73c6ce5f91b97bcfb] Cambio 6 en notas
running 'sh' 'test.sh'
9c639629269cdda3af4c397188de5250faac867a is the first bad commit
...
bisect found first bad commit
```

Mismo resultado que a mano. En un proyecto real el comando suele ser el de la suite de tests, o un test único que reproduce el error: `git bisect run dotnet test --filter Total_pedido_4711`, o `git bisect run npm test`.

| Código de salida | Significado |
|---|---|
| `0` | `good`: este commit está bien |
| `1` a `124`, `126` y `127` | `bad`: este commit tiene el error |
| `125` | `skip`: este commit no se puede probar |
| `128` o más | Aborta la búsqueda entera |

Un script con compilación debe distinguir «no compila» de «falla el test»: si el fallo de compilación saliera como `bad`, se señalaría un commit inocente. El patrón habitual:

```bash
#!/bin/sh
dotnet build || exit 125          # si no compila, no se puede juzgar: se salta
dotnet test --filter Total_pedido_4711
```

Si el script vive dentro del repositorio, **cambia con cada commit** que Git recorre: puede incluso no existir en commits antiguos. Se guarda fuera del repositorio (`~/bin/test.sh`) o se copia a una ruta ajena antes de empezar.

## Saltar commits: `skip`

En cualquier historial largo hay commits que no compilan o no arrancan por motivos ajenos al error buscado. Marcarlos como `bad` o `good` falsearía la búsqueda. Se salta con:

```bash
git bisect skip
```

Git prueba otro commit cercano. También se pueden saltar rangos: `git bisect skip v1.1..v1.2`. Si hay muchos commits saltados alrededor del culpable, el resultado final puede ser un rango de candidatos en lugar de un único commit (Git lo indica con *There are only 'skip'ped commits left to test*).

## Buscar algo que no es un error

`good` y `bad` son solo nombres. Si se busca el commit donde algo *cambió* (cuándo mejoró el rendimiento, cuándo creció el bundle), los términos `old` y `new` leen mejor, o incluso términos propios:

```bash
git bisect start --term-old=lento --term-new=rapido
```

Después, `git bisect lento` y `git bisect rapido` sustituyen a `bad` y `good`. No se pueden mezclar los dos juegos de términos en una misma búsqueda.

## Errores frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| El culpable señalado es un commit inocente (por ejemplo `Cambio 6 en notas`, que solo toca un fichero de notas) | Se respondió mal en algún paso: la prueba salía bien y se marcó `bad` (o al revés) | `git bisect log > respuestas.txt`, corregir la línea equivocada y reproducir con `git bisect replay respuestas.txt` |
| `Some good revs are not ancestors of the bad rev. git bisect cannot work properly in this case.` | El commit «bueno» no está en el historial del «malo» (ramas distintas) | Elegir un bueno que sea ancestro del malo; `git merge-base <bueno> <malo>` ayuda |
| `error: Your local changes to the following files would be overwritten by checkout:` | Hay cambios sin commitear que chocan al saltar de commit | Commitearlos o guardarlos con [`git stash`](Stash.md) antes de empezar |
| `You need to start by "git bisect start"` | Se usó `good` o `bad` sin sesión iniciada | `git bisect start` primero |
| `error: bisect run failed: exit code 130 from 'sh' 'x130.sh' is < 0 or >= 128` | El script salió con un código de 128 o más (en la práctica, una señal o un fallo del propio intérprete), que aborta la búsqueda | Hacer que el script termine con 0, 1 o 125 |
| Tras terminar el repositorio está en detached HEAD | Se olvidó `git bisect reset` | `git bisect reset` |

## Cuándo no usarlo

- **No hay un commit bueno conocido**: sin él no hay rango que acotar. Primero hay que probar versiones antiguas hasta encontrar una que funcione.
- **El fallo es intermitente**: una prueba que falla a veces responde `good` por azar y la búsqueda se desvía. Se necesita una prueba determinista, o repetirla varias veces dentro del script y dar `bad` si falla alguna.
- **El error nace de la combinación de varios commits**: bisect señala un commit, no una interacción. En ese caso el culpable señalado es solo la última pieza.
- **El historial tiene commits grandes mezclados** (un commit de 3.000 líneas que toca todo): bisect lo señala, pero no ayuda a acotar más. Ahí compensa que los [commits](Commits.md) sean pequeños y enfocados.
- **Se sabe qué fichero falla**: `git log -p -- ruta/del/fichero` o `git blame` suelen ser más rápidos que una búsqueda.

## Buenas prácticas avanzadas

- **Escribe primero la prueba y luego bisecta.** Si el test que reproduce el error se escribe *después* del bug, hay que aplicarlo sobre cada commit: se mantiene fuera del árbol (script externo) o se copia en cada paso, porque los commits antiguos no lo tienen.
- **Devuelve `125` ante todo lo que no sea el fallo buscado.** Compilación rota, dependencia que no se restaura, base de datos que no arranca: cualquier cosa que impida juzgar el commit debe ser `skip`, no `bad`. Un solo falso `bad` desvía toda la búsqueda sin avisar.
- **Los commits pequeños y atómicos son lo que hace útil a bisect.** Si cada commit compila y pasa los tests, el culpable es una línea concreta y no hay que saltar nada. Los [merges](Fusion-y-conflictos.md) y los commits de arreglo encadenados (`fix`, `fix2`, `fix3`) ensucian la búsqueda; ver también [`rebase`](Rebase.md) para ordenarlos.
- **`--first-parent` limita la búsqueda a la rama principal.** `git bisect start --first-parent` trata cada merge como un único paso, útil cuando cada rama de función era sólida por separado y se rompió al integrarse.
- **`git bisect visualize` muestra el rango que queda.** Abre `gitk` o, con `git bisect visualize --oneline`, imprime los candidatos pendientes; es la forma de decidir a mano qué commit probar a continuación si el elegido por Git no se puede construir.

## Documentación oficial

- [git-bisect](https://git-scm.com/docs/git-bisect) — referencia de comandos; la sección *Bisect run* describe los códigos de salida (incluido el `125`) y *Alternate terms* describe `--term-old` y `--term-new`.

---

*En resumen: `git bisect` es la búsqueda binaria aplicada al historial, y con `bisect run` y un script que devuelva 0, 1 o 125 encuentra el commit que rompió algo en un puñado de pasos, por largo que sea el historial.*
