# Fusión y conflictos (merge)

## ¿Qué es?

Fusionar (*merge*) es incorporar a la rama actual los commits de otra rama. Un **conflicto** aparece cuando las dos ramas modificaron las mismas líneas de un archivo de forma distinta y Git no puede decidir cuál versión es la buena.

## ¿Por qué existe?

Las [ramas](Ramas.md) permiten trabajar en paralelo, pero el trabajo paralelo tiene que volver a juntarse en algún momento. `git merge` hace esa unión: compara las dos puntas con su último ancestro común y combina las diferencias de cada lado.

La mayoría de las veces la combinación es automática. Si una rama toca `pagos/` y otra toca `emails/`, no hay nada que decidir. Si ambas reescriben la misma línea, Git se detiene y deja la elección a la persona, porque cualquier criterio automático acabaría tirando trabajo.

> Dos personas editan el mismo documento compartido. Si tocan párrafos distintos, los cambios se mezclan solos. Si reescriben la misma frase, alguien tiene que elegir con qué versión quedarse.

## ¿Cuándo y para qué se usa?

En la tienda online, el repositorio `tienda` tiene los servicios `pedidos`, `pagos`, `inventario` y `emails`. Cuando `feature/envio-gratis` está terminada, se va a `main` y se fusiona la rama dentro. También se fusiona `main` hacia la rama de trabajo para traer lo que el resto del equipo ha publicado mientras tanto. Siempre se fusiona **hacia la rama en la que estás**: la rama que recibe es la que está activa.

## Fusionar una rama

La fusión se hace desde la rama que recibe los cambios. Con la rama `feature/emails` terminada:

```bash
git switch main
git merge feature/emails
```

Si `main` no había avanzado desde que se creó la rama, Git no necesita crear nada nuevo: mueve el puntero de `main` hacia delante.

```
Updating ee87d31..523a633
Fast-forward
 emails.py | 1 +
 1 file changed, 1 insertion(+)
 create mode 100644 emails.py
```

Eso es un *fast-forward*: no hay commit de fusión y el historial queda en línea recta. Cuando las dos ramas avanzaron por su lado, Git crea un **commit de fusión** con dos padres:

```
Merge made by the 'ort' strategy.
 inventario.py | 1 +
 1 file changed, 1 insertion(+)
 create mode 100644 inventario.py
```

(`ort` es el algoritmo de fusión por defecto; no hay que elegirlo.) `git switch` se explica en [Switch](Switch.md).

## Fast-forward, merge commit y squash

La forma de fusionar decide qué aspecto tiene el historial después:

| Comando | Qué deja en el historial | Cuándo usarlo |
|---|---|---|
| `git merge rama` | Fast-forward si es posible; si no, commit de fusión | Por defecto, cuando da igual |
| `git merge --no-ff rama` | Siempre un commit de fusión, aunque pudiera deslizarse | Se quiere que quede visible dónde entró una función completa |
| `git merge --squash rama` | Ningún commit de fusión: deja los cambios preparados para que se haga un único commit | La rama tiene commits de trabajo (`wip`, `arreglo`) que no merece la pena conservar |
| `git merge --ff-only rama` | Fast-forward o error, nunca un commit de fusión | Se quiere garantizar un historial lineal |

Con `--no-ff` el historial conserva la costura de la rama:

```bash
git merge --no-ff -m "Fusiona feature/inventario" feature/inventario
git log --oneline --graph
```

```
*   2d01667 Fusiona feature/inventario
|\
| * 09ef53e Servicio inventario: stock minimo
|/
* 523a633 Plantilla de email del pedido 4711
```

Ese commit de fusión permite luego revertir la función entera de una vez (ver [Deshacer cambios](Deshacer-cambios.md)). Con `--squash` no se crea commit al fusionar; los cambios quedan en el área de preparación y el commit lo escribe quien fusiona:

```bash
git merge --squash feature/reembolsos
```

```
Squash commit -- not updating HEAD
 pagos/r1.py | 1 +
 pagos/r2.py | 1 +
 2 files changed, 2 insertions(+)
```

```bash
git commit -m "Añade reembolsos en pagos"
```

La rama original no queda referenciada como fusionada: Git no sabe que sus commits ya entraron, así que `git branch -d` se negará a borrarla y hará falta `git branch -D`. Cada equipo suele fijar una de estas formas (el flujo de [Pull requests](Pull-requests.md) ofrece las tres como botón); lo importante es no mezclarlas al azar.

## Un conflicto, paso a paso

Situación: `main` aplicó el IVA en `pedidos/calculo.py` y, en paralelo, `feature/envio-gratis` cambió la misma función para añadir el envío. Al fusionar:

```bash
git switch main
git merge feature/envio-gratis
```

```
Auto-merging pedidos/calculo.py
CONFLICT (content): Merge conflict in pedidos/calculo.py
Automatic merge failed; fix conflicts and then commit the result.
```

Git ha dejado la fusión a medias. `git status` dice en qué punto está y qué hacer:

```
On branch main
You have unmerged paths.
  (fix conflicts and run "git commit")
  (use "git merge --abort" to abort the merge)

Unmerged paths:
  (use "git add <file>..." to mark resolution)
	both modified:   pedidos/calculo.py
```

### Anatomía de los marcadores

Git escribe ambas versiones dentro del archivo:

```
def total(items):
<<<<<<< HEAD
    return round(sum(items) * 1.21, 2)
=======
    envio = 0 if sum(items) > 50 else 4.99
    return sum(items) + envio
>>>>>>> feature/envio-gratis
```

- Entre `<<<<<<< HEAD` y `=======` está **tu lado**: lo que hay en la rama actual (`main`).
- Entre `=======` y `>>>>>>> feature/envio-gratis` está **el otro lado**: lo que trae la rama que se fusiona.
- Todo lo que queda fuera de los marcadores se combinó sin problema.

En este caso ninguna de las dos versiones es la correcta: lo que se necesita es **las dos cosas a la vez**, el envío y el IVA. Por eso no existe un «quedarse con la mía» automático; hay que escribir el resultado.

### Resolver

1. Editar el archivo hasta que quede como debe y **borrar las tres líneas de marcadores**:

   ```python
   def total(items):
       envio = 0 if sum(items) > 50 else 4.99
       return round((sum(items) + envio) * 1.21, 2)
   ```

2. Marcar el archivo como resuelto con `git add` (el área de preparación se explica en [Área de preparación](Area-de-preparacion.md)):

   ```bash
   git add pedidos/calculo.py
   ```

3. Cerrar la fusión con un commit. Sin `-m`, Git abre el editor con un mensaje ya preparado (`Merge branch 'feature/envio-gratis'`); aceptarlo es lo normal:

   ```bash
   git commit
   ```

```
*   ee87d31 Merge branch 'feature/envio-gratis'
|\
| * dec18c7 Envio gratis a partir de 50 euros
* | 0d683a9 Aplica IVA en el total del pedido
|/
* b631506 Estructura inicial de pedidos y pagos
```

Antes de hacer `git add` conviene comprobar que no quedan marcadores olvidados: `git diff --check` los detecta, y sin ellos un `<<<<<<<` acaba en producción. Para ver solo los archivos pendientes: `git diff --name-only --diff-filter=U`.

### Cuando se quiere una versión entera

Si en un archivo concreto basta con quedarse con un lado completo (típico en un archivo generado o un fichero de dependencias bloqueado):

```bash
git checkout --ours archivo     # el de la rama actual
git checkout --theirs archivo   # el de la rama que se fusiona
git add archivo
```

Durante una fusión, `ours` es la rama en la que estás y `theirs` la que traes. En un [rebase](Rebase.md) los papeles se invierten, y es una confusión clásica.

## Cancelar una fusión

Mientras la fusión no está confirmada, nada es definitivo:

```bash
git merge --abort
```

Devuelve el repositorio exactamente al estado previo a `git merge`, incluidos los archivos modificados. Después de la anulación, `git status -sb` vuelve a mostrar solo `## main`. Si ya se hizo el commit de fusión y se descubre el error, `merge --abort` ya no sirve: se usa `reset` o `revert` según se haya publicado o no.

## Herramientas de fusión

Editar marcadores a mano funciona, pero con muchos conflictos una vista de tres paneles (base, tu versión, la otra, y el resultado) es más cómoda. Git lanza la herramienta configurada con:

```bash
git config --global merge.tool vscode
git mergetool
```

`git mergetool --tool-help` lista las herramientas que Git reconoce (en la versión 2.54 de Git para Windows aparecen entre otras `vimdiff`, `vscode`, `araxis`). Cuando se cierra el panel y se guarda, Git marca el archivo como resuelto; el commit final sigue siendo manual. Por defecto la herramienta deja copias `*.orig` junto a cada archivo; se evitan con `git config --global mergetool.keepBackup false`. Muchos IDE integran lo mismo con botones de «aceptar este lado» sobre los marcadores.

## Errores frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `error: Your local changes to the following files would be overwritten by merge:` | Hay cambios sin confirmar en archivos que la fusión también toca | Hacer commit, o guardar los cambios con [Stash](Stash.md), y volver a fusionar |
| `fatal: You have not concluded your merge (MERGE_HEAD exists).` al intentar `commit`, `pull` u otra fusión | Hay una fusión a medias | Resolver y `git commit`, o `git merge --abort` |
| `error: Committing is not possible because you have unmerged files.` | Se intentó `commit` sin hacer `git add` de los archivos resueltos | `git add` de los archivos en conflicto y volver a `git commit` |
| `merge: feature/envios - not something we can merge` | El nombre de la rama no existe (error tipográfico, o solo existe en el remoto sin traer) | `git branch -a` para ver el nombre exacto; `git fetch` si viene del remoto |
| `Already up to date.` | La rama ya está contenida en la actual; no hay nada que fusionar | Comprobar que se fusiona la rama correcta y que se hizo `fetch` |
| Quedan `<<<<<<<` en el código tras «resolver» | Se hizo `git add` sin editar el archivo | `git diff --check` antes del commit |

## Buenas prácticas avanzadas

- **Activa `zdiff3` para ver la versión original.** Los marcadores estándar muestran los dos lados pero no cómo era la línea antes de que ambos la tocaran, y es el dato que permite decidir. Con `git config --global merge.conflictStyle zdiff3` el mismo conflicto se ve así, con la sección `base`:

  ```
  <<<<<<< ours
      return round(sum(items) * 1.21, 2)
  ||||||| base
      return sum(items)
  =======
      envio = 0 if sum(items) > 50 else 4.99
      return sum(items) + envio
  >>>>>>> theirs
  ```

  Con la base delante, se ve que un lado añadió el IVA y el otro el envío: hay que sumarlos, no elegir.
- **Fusiona `main` hacia tu rama a menudo.** Un conflicto pequeño cada día cuesta minutos; una rama de tres semanas fusionada de golpe convierte la fusión en una tarde de trabajo y en riesgo de errores. Las ramas cortas casi no producen conflictos.
- **Activa `rerere` en ramas largas.** Con `git config --global rerere.enabled true`, Git memoriza cómo se resolvió cada conflicto y lo reaplica si reaparece (algo habitual al rehacer una fusión de prueba o al rebasar varias veces). El archivo se escribe resuelto pero **no** se añade al área de preparación: hay que revisarlo y hacer `git add`. Si una resolución grabada era mala, `git rerere forget <archivo>` la descarta.
- **Un conflicto resuelto sin entenderlo es un bug futuro.** Que compile no significa que esté bien: los conflictos «semánticos» no generan marcadores (una función renombrada en una rama y usada en la otra se fusiona limpia y rompe). Tras fusionar, ejecuta las pruebas antes de publicar.
- **Revertir una fusión tiene una trampa.** `git revert` de un commit de fusión exige `-m 1`, y después Git considera que esa rama ya entró: volver a fusionarla no trae nada. Los detalles están en [Deshacer cambios](Deshacer-cambios.md).

## Documentación oficial

- [git-merge](https://git-scm.com/docs/git-merge) — referencia de `--no-ff`, `--squash`, `--abort` y de `merge.conflictStyle`; la sección de cómo se presentan los conflictos explica los marcadores en detalle.
- [Pro Git: Advanced Merging](https://git-scm.com/book/en/v2/Git-Tools-Advanced-Merging) — conflictos con `diff3`, deshacer fusiones y estrategias; útil cuando los casos del día a día se quedan cortos.
- [git-rerere](https://git-scm.com/docs/git-rerere) — cómo funciona la reutilización de resoluciones y sus subcomandos (`forget`, `status`, `gc`).

---

*En resumen: fusionar es reunir ramas, y un conflicto es Git pidiendo que decidas cuando dos cambios chocan; mientras no confirmes, `git merge --abort` te devuelve al principio.*
