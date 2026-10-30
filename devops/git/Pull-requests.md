# Pull requests

## ¿Qué es?

Un *pull request* (PR) —*merge request* en GitLab— es una propuesta de fusión: se pide que los cambios de una rama se revisen y se incorporen a otra (normalmente `main`). Es una función de plataformas como GitHub o GitLab, no de Git en sí: Git solo conoce ramas y fusiones.

## ¿Por qué existe?

En un equipo no conviene que cualquiera meta cambios directamente en la rama principal sin que nadie los mire. El pull request crea un espacio para **revisar el código antes de fusionarlo**: quien revisa comenta línea a línea, sugiere mejoras y aprueba o pide cambios. Además, es el momento en que se ejecutan las comprobaciones automáticas (tests, linters), cuando un fallo aún no ha contaminado la rama común.

> Si una rama es el borrador y la fusión es publicarlo, el pull request es el momento de «pasarlo a revisión» antes de que entre en la versión oficial.

## ¿Cuándo y para qué se usa?

En la tienda online (repositorio `tienda`, servicios `pedidos`, `pagos`, `inventario` y `emails`), cualquier cambio entra en `main` por un PR:

- **Proponer** que un trabajo (una función, un arreglo en `pagos`) entre en `main`.
- **Revisar** el código y dejar comentarios antes de que llegue a producción.
- **Ejecutar comprobaciones automáticas** sobre el cambio (ver [GitHub Actions](GitHub-Actions.md)).
- **Dejar constancia**: la discusión y las decisiones quedan asociadas al cambio y se pueden consultar después.

## Ciclo de vida de un PR

Un PR pasa por estas etapas:

| Etapa | Qué ocurre |
|---|---|
| 1. Rama | Se crea una rama y se hacen commits |
| 2. Subida | La rama se sube al remoto |
| 3. Apertura | Se abre el PR desde la web o con `gh pr create` |
| 4. Checks y revisión | Corren los workflows de CI; quien revisa comenta, aprueba o pide cambios |
| 5. Ajustes | Se hacen más commits en la misma rama; el PR se actualiza solo y los checks se relanzan |
| 6. Fusión | Con aprobación y checks en verde, se fusiona con una de las [tres estrategias](#estrategias-de-fusión) |
| 7. Limpieza | Se borra la rama |

### Abrir un PR

```bash
git switch -c fix/total-pedido
# ...cambios y commits...
git push -u origin fix/total-pedido
```

El `push` imprime un enlace para abrir el PR; en GitHub también aparece un aviso «Compare & pull request» en la página del repositorio. Con la CLI de GitHub (`gh`):

```bash
gh pr create --base main --title "Corrige el redondeo del total del pedido #4711" \
  --body "Cierra #212. El total se redondeaba antes de aplicar el IVA."
```

Escribir `Closes #212` (o `Fixes`, `Resolves`) en la descripción hace que, al fusionar el PR, la plataforma cierre automáticamente la incidencia 212.

Los detalles de crear, subir y gestionar ramas están en [Ramas](Ramas.md) y [Remotos](Remotos.md); si hace falta autenticar `git push` o `gh`, ver [Tokens de acceso en remotos](Tokens-de-Acceso-en-Remotos.md).

### Responder a la revisión

Quien revisa deja comentarios o una de tres decisiones: *Comment*, *Approve* o *Request changes*. Responder consiste en **hacer más commits en la misma rama**:

```bash
git commit -am "Redondea después de aplicar el IVA"
git push
```

No se abre otro PR: el mismo se actualiza y se relanzan los checks. Los comentarios resueltos se marcan como *resolved* para que quien revisa vea qué falta.

Si la rama principal avanzó y el PR muestra *This branch has conflicts that must be resolved*, hay que traer los cambios y resolver los conflictos en local:

```bash
git fetch origin
git merge origin/main        # o: git rebase origin/main
# resolver conflictos, commitear
git push                     # tras un rebase: git push --force-with-lease
```

Ver [Fusión y conflictos](Fusion-y-conflictos.md) y [Rebase](Rebase.md) para ambos caminos.

## Qué hace bueno a un PR

Un PR se revisa mejor, y más deprisa, cuando cumple cuatro condiciones:

| Aspecto | Bien | Mal |
|---|---|---|
| **Tamaño** | Un cambio con un propósito, de decenas a pocos cientos de líneas | Miles de líneas que mezclan una función, un renombrado y un arreglo |
| **Título** | «Corrige el redondeo del total del pedido #4711» | «Cambios», «fix» |
| **Descripción** | Qué cambia, por qué, cómo probarlo y qué queda fuera | Vacía o «ver commits» |
| **Commits** | Cada uno con sentido propio (ver [Commits](Commits.md)) | `wip`, `wip2`, `arreglo`, `arreglo definitivo` |

La razón del tamaño es sencilla: es más fácil revisar 50 líneas con atención que 5.000, y una revisión de 5.000 líneas suele acabar en un «parece bien» sin lectura real. Si el trabajo es grande, se divide en varios PR encadenados o se abre uno en borrador.

Una descripción útil tiene esta forma:

```markdown
## Qué cambia
El total del pedido se redondeaba antes de aplicar el IVA, con diferencias de un céntimo.

## Por qué
Cierra #212. Los pagos con importe de 1 céntimo de diferencia fallaban en `pagos`.

## Cómo probarlo
`dotnet test --filter Total_pedido_4711`

## Fuera de alcance
El redondeo de los descuentos se trata en otro PR.
```

Muchos repositorios fijan esta plantilla en `.github/pull_request_template.md`, y se muestra precargada al abrir cada PR.

## Estrategias de fusión

El botón de fusionar ofrece tres modos. No es un detalle estético: define cómo se leerá el historial de `main` para siempre.

| | Merge commit | Squash and merge | Rebase and merge |
|---|---|---|---|
| Qué hace | Añade todos los commits del PR más un commit de fusión | Aplasta todo el PR en **un** commit | Recoloca los commits del PR uno a uno, sin commit de fusión |
| Historial de `main` | Con ramas visibles | Lineal; un commit por PR | Lineal; todos los commits |
| Conserva los commits originales | Sí | No | Sí, pero con **hashes nuevos** |
| Deshacer el PR entero | Revertir el commit de fusión | Revertir un commit | Revertir varios commits |
| Encaja cuando | Se valora el historial completo y cada commit tiene sentido | El PR es un solo cambio lógico, o tiene muchos commits de arreglo | Los commits están bien curados y se quiere historial lineal |

Regla de elección:

| Situación | Estrategia |
|---|---|
| Ramas con commits del tipo `wip`, `arreglos de revisión` | Squash |
| Cada commit del PR es limpio y autónomo | Rebase o merge commit |
| Ramas largas con varias personas aportando | Merge commit |
| Se quiere `main` fácil de leer, de revertir y de usar con [`bisect`](git-bisect.md) | Squash |
| Duda y equipo pequeño | Squash: es el más simple de entender |

El equipo debe elegir uno y fijarlo en *Settings → General → Pull Requests* del repositorio, donde se puede desactivar el resto. GitHub rehace los commits en *rebase and merge* (nuevos hashes y datos de commiter), igual que haría un [`rebase`](Rebase.md) local.

Tras un *squash and merge*, la rama original **no se reutiliza**: el commit de `main` es nuevo y Git no lo relaciona con los commits de la rama. Seguir trabajando sobre ella y abrir otro PR vuelve a traer los cambios ya fusionados y provoca conflictos absurdos. La rama fusionada con squash se borra y lo siguiente arranca de `main` actualizado:

```bash
git switch main
git pull
git branch -D fix/total-pedido      # -D: Git no ve la rama como fusionada, y es normal
```

## Protección de ramas y checks requeridos

Por defecto los checks son **informativos**: alguien con prisa puede fusionar en rojo o saltarse el PR y hacer `push` directo a `main`. La protección de rama (*Settings → Branches*, o *Rulesets*, en GitHub) convierte la disciplina en una regla que el servidor hace cumplir. Las opciones que se tocan de verdad:

| Regla | Efecto |
|---|---|
| Exigir pull request antes de fusionar | Se prohíbe el `push` directo a la rama |
| Exigir N aprobaciones | El PR necesita N revisiones favorables |
| Descartar aprobaciones al subir commits nuevos | Un cambio posterior a la aprobación obliga a aprobar de nuevo |
| Exigir checks de estado | Los workflows indicados deben terminar en verde (o *skipped*, o *neutral*) |
| Exigir que la rama esté al día con la base | El PR debe incluir los últimos cambios de `main` antes de fusionarse |
| Exigir revisión de *code owners* | Los ficheros definidos en `CODEOWNERS` necesitan la aprobación de su responsable |
| Exigir historial lineal | Prohíbe los merge commits |
| Incluir a administradores | Las reglas también valen para quien administra el repositorio |

Con la regla activa, un `push` directo se rechaza así:

```
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote: error: Changes must be made through a pull request.
 ! [remote rejected] main -> main (protected branch hook declined)
```

Y un PR con revisión pendiente de resolver no se puede fusionar, con un mensaje equivalente (`Changes have been requested.`, según la documentación de GitHub).

Cada check requerido se identifica por **el nombre del job** del workflow. Conviene darle nombres únicos entre todos los workflows del repositorio: si dos jobs se llaman `test`, el resultado se vuelve ambiguo y el PR puede quedar bloqueado. Cómo se definen los workflows que producen esos checks: [GitHub Actions en esta colección](GitHub-Actions.md) y la ficha de referencia [GitHub Actions en CI/CD](../ci-cd/GitHub-Actions.md).

## PRs en borrador

Un *draft PR* se abre con `gh pr create --draft` o con la opción *Create draft pull request*. Indica «esto no está listo, pero quiero opinión sobre el enfoque»:

- No se puede fusionar mientras siga en borrador.
- No solicita revisión formal automáticamente (los *code owners* no reciben aviso).
- Los checks sí se ejecutan, así que sirve también para probar la CI.

Cuando está listo, se pulsa *Ready for review* o `gh pr ready`.

## Errores frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `GH006: Protected branch update failed for refs/heads/main. Changes must be made through a pull request.` | Se hizo `push` directo a una rama protegida | Subir a una rama propia y abrir un PR |
| El botón de fusionar aparece deshabilitado con `Required status check "test" is expected` | Falta el check requerido: no ha terminado, no se ha lanzado o el nombre no coincide | Esperar a que termine; si nunca llega, comprobar que el workflow se dispara con `pull_request` y que no tiene filtros de rutas que lo excluyan |
| `This branch has conflicts that must be resolved` | `main` cambió las mismas líneas | Traer `main` a la rama y resolver (ver arriba) |
| Un PR nuevo desde una rama ya fusionada con squash muestra cambios antiguos | La rama se reutilizó tras el squash | Crear una rama nueva desde `main` y pasar los commits pendientes con [`cherry-pick`](Cherry-pick.md) |
| Los checks no aparecen en el PR y no hay rastro en la pestaña *Actions* | El PR tiene conflictos: los workflows de `pull_request` no se ejecutan mientras los haya | Resolver los conflictos; los checks arrancan al subir el commit |
| Los checks de un PR de un fork esperan o fallan por falta de secrets | En PRs de forks, un primer contribuyente puede necesitar que quien mantiene apruebe la ejecución; además no reciben secrets y el `GITHUB_TOKEN` es de solo lectura | Aprobar la ejecución en el PR; no depender de secrets en los checks de PR |
| Tras un `rebase` local, `git push` responde `! [rejected] ... (non-fast-forward)` | El rebase reescribió commits ya publicados | `git push --force-with-lease` solo en la rama propia del PR |

## Cuándo no usarlos

- **Repositorio personal sin revisión**: un PR para uno mismo aporta poco, salvo que se quiera la CI previa a la fusión (que se puede conseguir igualmente con una regla de rama).
- **Cambios triviales con un flujo muy rápido** (trunk-based, programación en pareja): la revisión ocurre en tiempo real y el PR añade espera. Ver la comparación de modelos en [Git Flow](Git-Flow.md).
- **Cambios que no se pueden revisar** (ficheros generados, volcados enormes): se fusionan, pero la revisión real está en lo que los genera.

## Buenas prácticas avanzadas

- **Revisa tu propio PR antes de pedir revisión.** Recorre el diff en la interfaz del PR, tal como lo verá quien revise: salen ficheros colados, código de depuración y renombrados que despistan. Donde algo necesite contexto, déjalo como comentario propio en la línea exacta. Un PR auto-revisado se revisa en la mitad de tiempo.
- **Abre en borrador para conversar antes de pulir.** Recibir un «por ahí no» con el 20 % del trabajo hecho es barato; recibirlo con el 100 % es una semana a la basura.
- **Exige los checks por nombre estable y no por existencia.** Si un workflow se omite por filtros de rutas (`paths`), el check requerido nunca se publica y el PR queda bloqueado sin explicación. Un job final que dependa de los demás (`needs`) y sea el único requerido evita el problema.
- **Activa la fusión automática (*auto-merge*) en lugar de esperar los checks.** `gh pr merge --auto --squash` deja el PR programado para fusionarse en cuanto se cumplan las reglas.
- **Pon `CODEOWNERS` en las zonas sensibles.** Un fichero `.github/CODEOWNERS` con `/pagos/ @equipo-pagos` pide revisión automática a quien responde de cada servicio y, con la regla correspondiente, la hace obligatoria.
- **Los PR apilados evitan los PR gigantes.** Un PR cuya base es la rama de otro PR (`--base fix/total-pedido`) permite dividir un cambio grande en pasos revisables; al fusionar el primero, el segundo se reorienta a `main`.

## Documentación oficial

- [Pull requests en GitHub Docs](https://docs.github.com/en/pull-requests) — punto de entrada; las secciones sobre revisión y sobre fusión son las más útiles.
- [Acerca de la fusión de pull requests](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/about-pull-request-merges) — detalle de las tres estrategias y de lo que pasa al reutilizar una rama tras un squash.
- [Acerca de las ramas protegidas](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) — cada regla de protección, incluidos los checks requeridos y las aprobaciones.

---

*En resumen: un pull request es el punto de control donde el trabajo se revisa, se prueba automáticamente y se discute antes de entrar en la rama principal; con una estrategia de fusión elegida y la rama protegida, esa disciplina deja de depender de la buena voluntad.*
