# GitHub Actions

## ¿Qué es?

GitHub Actions es el motor de automatización (CI/CD) de GitHub: ejecuta ficheros YAML del repositorio, llamados *workflows*, cuando ocurre un evento, y muchos de esos eventos son operaciones de Git (un `push`, un pull request, una etiqueta). Esta ficha cubre **el vínculo entre Git y Actions**; la sintaxis completa, los runners, las cachés y las matrices están en la ficha de referencia [GitHub Actions en CI/CD](../ci-cd/GitHub-Actions.md).

## ¿Por qué existe?

Hay tareas que deberían pasar siempre que alguien toca el repositorio y que es fácil olvidar: compilar, pasar los tests, revisar el estilo. Hacerlas a mano es lento y poco fiable. Actions las engancha a las propias operaciones de Git: se define una vez «cuando llegue un pull request, ejecuta los tests» y el resultado aparece en el propio PR.

> Imagina un asistente en la puerta de `main` que, cada vez que alguien entrega trabajo, comprueba que no rompe nada antes de dejarlo pasar. Actions es ese asistente, y las reglas de la rama deciden si su veredicto es vinculante.

## ¿Cuándo y para qué se usa?

En la tienda online (repositorio `tienda`, servicios `pedidos`, `pagos`, `inventario` y `emails`), el vínculo con Git cubre tres necesidades:

- **Probar cada propuesta**: en cada pull request, compilar y ejecutar los tests antes de fusionar.
- **Reaccionar a lo que llega a `main`**: construir y desplegar al fusionar.
- **Publicar versiones**: al empujar una etiqueta como `v1.4.0`, generar la release.

## Qué evento de Git dispara qué

Cada operación de Git que llega al remoto puede lanzar un workflow:

| Acción en Git | Evento | Se declara con |
|---|---|---|
| `git push` de commits a una rama | `push` | `on: push: branches: [main]` |
| `git push --tags` (o `git push origin v1.4.0`) | `push` con etiqueta | `on: push: tags: ['v*']` |
| Abrir, actualizar o reabrir un PR | `pull_request` | `on: pull_request:` |
| Crear o borrar una rama o etiqueta | `create` / `delete` | `on: create:` |
| Publicar una release en GitHub | `release` | `on: release: types: [published]` |
| Enviar una revisión de un PR | `pull_request_review` | `on: pull_request_review:` |
| Pulsar el botón de la web o llamar a la API | `workflow_dispatch` | `on: workflow_dispatch:` |

Tres detalles que causan la mayoría de las sorpresas:

- **`pull_request` prueba el código fusionado.** Por defecto se dispara con los tipos `opened`, `synchronize` (commits nuevos) y `reopened`. El workflow no ejecuta el último commit de la rama, sino la **fusión provisional con la rama destino** (`refs/pull/<número>/merge`). Así comprueba lo que quedaría en `main`; para obtener el commit exacto de la rama de origen se usa `github.event.pull_request.head.sha`.
- **Un PR con conflictos no ejecuta sus workflows.** No hay fusión provisional que probar, hasta que se resuelven los conflictos (ver [Fusión y conflictos](Fusion-y-conflictos.md)).
- **Los pushes hechos por un workflow no disparan otros workflows.** Un commit o una etiqueta creados con el `GITHUB_TOKEN` automático no lanzan nuevos `push`, para evitar bucles (las excepciones son `workflow_dispatch` y `repository_dispatch`). Si un workflow debe encadenar a otro, se usa `workflow_call` o un token distinto.

Los filtros de rama, etiqueta y ruta (`branches`, `tags`, `paths`) se combinan dentro del mismo evento; los de ruta están desarrollados en [Monorepo y path filters](../ci-cd/Monorepo-y-Path-Filters.md), y el disparo por etiqueta, en [Release por tag](../ci-cd/Release-por-Tag.md) y [Tags y versiones](Tags-y-versiones.md).

## Primer workflow mínimo

Un fichero `.github/workflows/ci.yml` que compila y prueba cada pull request y cada push a `main`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - run: dotnet test --configuration Release
```

- `on:` enlaza el workflow con dos operaciones de Git: llegar a `main` y abrir o actualizar un PR.
- `jobs.test` es **el nombre del check** que aparecerá en el PR y al que se refieren las reglas de la rama.
- `actions/checkout` descarga el código; sin él, la máquina está vacía.
- Si un `run:` devuelve un código distinto de 0, el paso falla y el job se marca en rojo.

Al hacer `git push` de este fichero, la ejecución aparece en la pestaña *Actions* del repositorio. Qué es un job, un step o un runner, y todo lo que se puede añadir (caché, artefactos, matrices), se explica en la [ficha de referencia](../ci-cd/GitHub-Actions.md).

## Checks de PR y protección de ramas

Cuando un workflow se dispara por un PR, cada job aparece en el PR como un **check** con su estado:

```
✓ CI / test (pull_request)
✗ CI / lint (pull_request)
```

Sin más, el check es informativo: se puede fusionar en rojo. Para que sea vinculante hay que activar en *Settings → Branches* (o *Rulesets*) la regla de **exigir checks de estado** sobre `main` y marcar `test` como requerido. A partir de ahí, el botón de fusionar se bloquea mientras el check no esté en verde, y el `push` directo a `main` se rechaza. Todas las reglas disponibles y la forma de elegir la estrategia de fusión están en [Pull requests](Pull-requests.md).

Cuidado con los workflows que no se ejecutan siempre: si un workflow se omite por filtros de ruta (`paths`), de rama o por un mensaje de commit, el check requerido queda **Pending** y bloquea la fusión para siempre. La documentación de GitHub aconseja no exigir workflows que puedan omitirse; una solución habitual es exigir un job final que dependa de los demás y se ejecute siempre.

## Errores frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| El workflow no aparece tras el `push` | El fichero no está en `.github/workflows/` o no está en la rama que lo dispara | Comprobar la ruta y que `on:` incluye esa rama |
| El PR muestra `Expected — Waiting for status to be reported` y nunca avanza | El check es requerido, pero el workflow se omitió por un filtro o por conflictos | Resolver conflictos o revisar los filtros `paths` / `branches` |
| `Required status check "test" is expected` | El nombre del job no coincide con el check requerido | Usar el nombre exacto del job en la regla de rama |
| El workflow de la etiqueta no se lanza al empujarla | Se empujaron más de tres etiquetas a la vez, o la etiqueta no encaja con `tags: ['v*']` | Empujar las etiquetas de una en una y revisar el patrón |
| Los tests del PR pasan en local pero fallan en el check | El check prueba la fusión con `main`, no la rama sola | Traer `main` a la rama y repetir en local |
| `Resource not accessible by integration` | El `GITHUB_TOKEN` no tiene el permiso declarado en `permissions:` | Añadir el permiso concreto en el job |

## Cuándo no usarla

- **El repositorio no está en GitHub**: Actions está atado a sus repositorios. En GitLab, el equivalente es [GitLab CI](../ci-cd/GitLab-CI.md).
- **Las comprobaciones deben ocurrir antes de commitear, en local**: para eso están los [Git Hooks](../ci-cd/Git-Hooks.md), que se ejecutan en la máquina de quien commitea y dan respuesta inmediata.
- **El mismo flujo debe ejecutarse sin depender de la plataforma**: conviene que el workflow solo llame a un script versionado (`./build.sh test`), de modo que el mismo comando se pueda lanzar en local o en otro CI.

## Buenas prácticas avanzadas

- **Haz que el workflow llame a un script del repositorio.** Un `run: ./build.sh test` se prueba en local, se depura sin hacer `push` a cada intento y no ata la lógica a GitHub.
- **`pull_request_target` no sustituye a `pull_request`.** Corre en el contexto de la rama destino y con acceso a los secrets, lo que lo hace peligroso si hace `checkout` del código del fork. Solo se usa para tareas que no ejecutan código del PR (etiquetar, comentar).
- **Pon `concurrency` por rama en los workflows de PR.** Con `group: ci-${{ github.ref }}` y `cancel-in-progress: true`, cada commit nuevo cancela la ejecución anterior del mismo PR, y los checks reflejan siempre el último commit.
- **Fija la identidad del check.** Dar a cada job un `name:` estable evita que renombrar un job deje a la regla de la rama esperando un check que ya no existe.
- **Declara `permissions` mínimos.** Con `contents: read` en el workflow se limita el daño si algún paso, un test o una acción de terceros se comprometen.

## Documentación oficial

- [Eventos que disparan workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows) — la tabla de cada evento (`push`, `pull_request`, `release`...) con sus tipos de actividad y el valor de `GITHUB_SHA` y `GITHUB_REF` en cada caso.
- [Acerca de las ramas protegidas](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) — cómo exigir checks y aprobaciones antes de fusionar.

---

*En resumen: GitHub Actions engancha automatizaciones a las operaciones de Git (push, etiqueta, pull request); con las reglas de la rama protegida, el veredicto de sus checks pasa de aviso a barrera.*
