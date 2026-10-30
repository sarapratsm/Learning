# Monorepo y path filters

## ¿Qué es?

Un *monorepo* es un único repositorio Git que contiene varias partes de un producto, cada una en su carpeta. Los *path filters* son la técnica de CI que hace que cada pipeline se ejecute **solo cuando cambian los archivos que le importan**. En GitHub Actions se declaran con las claves `paths` y `paths-ignore` del disparador.

## ¿Por qué existe?

En un monorepo, cualquier push toca «el repositorio». Sin más información, el CI reacciona ejecutándolo todo: compila el servicio `pagos` porque alguien corrigió una errata en la documentación de `emails`, o pasa la suite completa de `inventario` porque se tocó un README. Eso desperdicia minutos de runner (que se facturan en repositorios privados) y alarga el tiempo de espera de cada PR.

> Piensa en un edificio de cuatro pisos con un solo timbre: sin filtros, cada visita despierta a todos los vecinos. Los path filters ponen a cada piso su propio timbre.

## ¿Cuándo y para qué se usa?

Cuando un repositorio contiene más de una unidad compilable o desplegable por separado. El caso de esta guía es una tienda online con cuatro servicios en un mismo repositorio:

```
tienda/
├── pedidos/        # API de pedidos (el pedido #4711 nace aquí)
├── pagos/
├── inventario/
├── emails/
├── shared/         # contratos y librerías comunes
└── .github/workflows/
    ├── pedidos-ci.yml
    ├── pagos-ci.yml
    ├── inventario-ci.yml
    └── emails-ci.yml
```

Cada servicio tiene su workflow, y cada workflow declara qué rutas le afectan. Para una sola unidad en un repositorio, no hace falta nada de esto.

## Filtrar con `paths` y `paths-ignore`

Se añaden bajo el evento (`push` o `pull_request`). Con `paths`, el workflow se ejecuta si **al menos un** archivo cambiado coincide con algún patrón.

```yaml
# .github/workflows/pedidos-ci.yml
name: pedidos-ci
on:
  pull_request:
    branches: [main]
    paths:
      - 'pedidos/**'
      - 'shared/**'
      - '.github/workflows/pedidos-ci.yml'

jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: pedidos   # los comandos corren dentro de pedidos/
    steps:
      - uses: actions/checkout@v4
      - run: ./run-tests.sh
```

Una PR que solo modifique `emails/plantillas/bienvenida.html` no lanza este workflow. Una que toque `pedidos/` o `shared/` sí. Los patrones usan `*` (un segmento de ruta) y `**` (cualquier profundidad).

`paths-ignore` hace lo inverso: el workflow se salta **solo si todos** los archivos cambiados coinciden con los patrones ignorados. Sirve para «ejecuta siempre salvo que solo cambien documentos»:

```yaml
on:
  push:
    branches: [main]
    paths-ignore:
      - '**.md'
      - 'docs/**'
```

| Necesitas | Usa |
|---|---|
| Ejecutar solo cuando cambia un área concreta | `paths` |
| Ejecutar siempre salvo cambios triviales (docs, README) | `paths-ignore` |
| Incluir una carpeta pero excluir una subcarpeta | `paths` con un patrón negativo `!` después del positivo |

Reglas que conviene tener presentes, según la documentación de GitHub:

- No se pueden usar `paths` y `paths-ignore` en el mismo evento. Para mezclar inclusión y exclusión, se usa `paths` con patrones `!`; debe haber al menos un patrón positivo y el orden importa (un `!` posterior a un positivo lo excluye).
- Si el evento declara también `branches`, el workflow solo se ejecuta cuando se cumplen **ambos** filtros.
- Los filtros de ruta **no se evalúan en pushes de tags**. Un `on: push: tags` ignora `paths`.
- En una PR la comparación se hace contra el punto donde la rama se separó de la base (diff de tres puntos), no contra la punta actual de `main`.

```yaml
paths:
  - 'pedidos/**'
  - '!pedidos/docs/**'    # dentro de pedidos/, ignora su documentación
```

## Los dos huecos del filtro: el propio workflow y lo compartido

Un filtro `paths: ['pedidos/**']` deja dos agujeros:

- Cambiar `.github/workflows/pedidos-ci.yml` no dispara el pipeline que acabas de modificar, así que el cambio llega a `main` sin haberse ejecutado nunca.
- Tocar `shared/` (contratos, librerías, configuración raíz) no dispara ningún servicio, aunque los cuatro dependan de ello.

Por eso el ejemplo anterior incluye `shared/**` y el propio fichero del workflow. El CI que valida todo *excepto* los cambios más peligrosos da una falsa sensación de seguridad.

## El problema de los checks requeridos

Es la trampa que más tiempo hace perder. Las reglas de protección de rama (o los *rulesets*) permiten exigir que ciertos checks pasen antes de fusionar. Si `pedidos-ci` es un check requerido y la PR solo toca `emails/`, el workflow **no se ejecuta**, el check nunca se reporta y la PR queda así, sin poder fusionarse:

```
Expected — Waiting for status to be reported
```

La documentación de GitHub lo describe: cuando un workflow se omite por filtrado de rutas, sus checks quedan *pending* y bloquean el merge. En cambio, un **job** omitido por una condición (`if:`) sí reporta *Success*. Y la recomendación oficial es evitar exigir workflows que pueden omitirse.

La salida es mover el filtrado **dentro** del workflow: el workflow se dispara siempre, y los jobs se activan o no según lo que cambió. Un job final agregador es el único check requerido.

```yaml
# .github/workflows/ci.yml
name: ci
on:
  pull_request:
    branches: [main]

jobs:
  changes:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: read
    outputs:
      pedidos: ${{ steps.filter.outputs.pedidos }}
      pagos: ${{ steps.filter.outputs.pagos }}
    steps:
      - uses: dorny/paths-filter@v4
        id: filter
        with:
          filters: |
            pedidos:
              - 'pedidos/**'
              - 'shared/**'
            pagos:
              - 'pagos/**'
              - 'shared/**'

  pedidos:
    needs: changes
    if: needs.changes.outputs.pedidos == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./pedidos/run-tests.sh

  pagos:
    needs: changes
    if: needs.changes.outputs.pagos == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./pagos/run-tests.sh

  ci-ok:                       # el único check que se marca como requerido
    if: always()
    needs: [pedidos, pagos]
    runs-on: ubuntu-latest
    steps:
      - run: |
          if [ "${{ contains(needs.*.result, 'failure') }}" = "true" ] || \
             [ "${{ contains(needs.*.result, 'cancelled') }}" = "true" ]; then
            exit 1
          fi
```

Qué hace: el job `changes` calcula qué áreas cambiaron; `pedidos` y `pagos` se ejecutan solo si les toca y, si no, quedan *skipped*. `ci-ok` corre siempre (`if: always()`) y falla únicamente si algún job necesario falló o se canceló; con jobs *skipped* termina en verde. En la regla de protección se exige solo `ci-ok`.

[`dorny/paths-filter`](https://github.com/dorny/paths-filter) es una action de terceros. En PR consulta la API de GitHub (necesita `pull-requests: read`); en pushes usa git y exige que el repositorio esté ya descargado con `actions/checkout`.

Alternativa sin dependencias de terceros: dos workflows con **el mismo nombre de job**, uno con `paths` y otro con `paths-ignore` de las mismas rutas, cuyo job se limita a un `run: echo "sin cambios"`. Funciona, pero hay que mantener ambas listas sincronizadas.

## `fetch-depth` y detectar cambios dentro de un job

Si en vez de la action calculas los cambios con git (`git diff --name-only origin/main...HEAD`), el checkout por defecto no sirve: `actions/checkout` descarga **un solo commit** (`fetch-depth: 1`) y no existe el punto de comparación.

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0       # historial completo de todas las ramas y tags
- run: git diff --name-only origin/main...HEAD
```

`fetch-depth: 0` en un repositorio con años de historia tarda; si solo necesitas el ancestro común de una PR, un valor acotado (por ejemplo 50) suele bastar, a riesgo de que una rama muy antigua no lo encuentre.

## Workflows reutilizables: un workflow por área sin copiar YAML

Con cuatro servicios, los cuatro workflows acaban siendo casi idénticos. Un *workflow reutilizable* (con el disparador `workflow_call`) concentra la receta y cada servicio lo llama con sus parámetros.

```yaml
# .github/workflows/_servicio.yml
name: servicio reutilizable
on:
  workflow_call:
    inputs:
      carpeta:
        type: string
        required: true

jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ${{ inputs.carpeta }}
    steps:
      - uses: actions/checkout@v4
      - run: ./run-tests.sh
```

```yaml
# .github/workflows/pedidos-ci.yml
name: pedidos-ci
on:
  pull_request:
    paths: ['pedidos/**', 'shared/**', '.github/workflows/pedidos-ci.yml', '.github/workflows/_servicio.yml']

jobs:
  ci:
    uses: ./.github/workflows/_servicio.yml
    with:
      carpeta: pedidos
```

Los filtros `paths` van en el workflow llamador, que es el que tiene el evento. Incluye también el fichero del reutilizable en la lista: si cambia, hay que revalidar a todos sus llamadores. La llamada se hace con `uses` a nivel de job (no dentro de `steps`) y los secrets se pasan por nombre o con `secrets: inherit` dentro de la misma organización.

## Jobs que dependen de otros

Dentro de un workflow, `needs` encadena jobs. Si un job necesario se omite (por una condición o un filtro), el job dependiente se omite también salvo que declare una condición propia. Es la razón de que `ci-ok` use `if: always()`: sin ella, quedaría *skipped* en cuanto cualquiera de sus necesidades lo estuviera, y un check requerido omitido bloquea el merge.

Para un despliegue que depende de varios servicios, la condición habitual es:

```yaml
deploy:
  needs: [pedidos, pagos]
  if: ${{ !failure() && !cancelled() }}   # corre aunque alguno se haya omitido
```

Sin ella, `deploy` no se ejecutaría cuando solo cambió uno de los dos servicios.

## Construir y desplegar solo lo que cambió

El mismo criterio se aplica a las imágenes: el contexto de `docker/build-push-action` apunta a la carpeta del servicio y el tag lleva su nombre.

```yaml
- uses: docker/build-push-action@v6
  with:
    context: ./pagos
    push: true
    tags: ghcr.io/mi-org/tienda-pagos:sha-${{ github.sha }}
```

Cómo publicar imágenes y qué etiquetas poner se explica en [Docker en CI/CD](Docker-en-CI-CD.md) y en [GitHub Container Registry](../docker/GitHub-Container-Registry.md). Para publicar versiones por servicio en un monorepo, el patrón de tags (`pagos-v1.2.0`) se trata en [Release por tag](Release-por-Tag.md).

## Herramientas del ecosistema

Los path filters son una solución manual: tú declaras qué rutas importan a cada pipeline. Existen herramientas que calculan el grafo de dependencias entre paquetes y ejecutan solo lo *afectado*:

- **Nx** — `nx affected` compara un commit `base` con uno `head` y ejecuta solo las tareas cuyas entradas cambiaron.
- **Turborepo** — `turbo run build --affected` ejecuta tareas solo en los paquetes con cambios, detectando por sí mismo la base y la cabeza de una PR en GitHub Actions.

Quedan fuera de esta guía; son la respuesta cuando el mantenimiento de las listas de `paths` se vuelve inmanejable porque las dependencias entre paquetes son muchas.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| La PR se queda en `Expected — Waiting for status to be reported` | El check es requerido pero su workflow se omitió por `paths`. Mover el filtro dentro del workflow y exigir un job agregador |
| Cambio en `shared/` sin ningún pipeline ejecutado | `shared/**` no está en los `paths` de los servicios que dependen de él |
| Editas el workflow y no se ejecuta en la PR | El propio fichero `.github/workflows/...yml` no está en `paths` |
| `git diff origin/main...HEAD` falla con `unknown revision or path not in the working tree` | `fetch-depth: 1` por defecto; la referencia no existe en el clon superficial |
| El job `deploy` queda `skipped` aunque los tests pasaron | Un `needs` previo se omitió y `deploy` no declara `if: ${{ !failure() && !cancelled() }}` |
| `paths` no filtra y el workflow corre con un tag | Los filtros de ruta no se evalúan en pushes de tags |
| Workflow que siempre se ejecuta pese a los filtros | Pushes de más de 1000 commits, diff que agota el tiempo o más de 3000 archivos cambiados: GitHub documenta que en esos casos puede ejecutarse (o no) sin respetar el filtro |

## Cuándo no usar path filters

- Repositorio de una sola unidad desplegable: añaden complejidad sin ahorro.
- Cuando las áreas se acoplan tanto que casi todo cambio afecta a casi todo: las listas de rutas se vuelven mentira y es mejor ejecutar todo con caché.
- Para decidir qué desplegar a producción en un monorepo con dependencias cruzadas: un filtro de rutas no entiende contratos entre servicios; una herramienta de grafo sí.

## Buenas prácticas avanzadas

- **Exige un único check agregador, no los jobs individuales.** Marcar `ci-ok` como requerido desacopla la regla de protección de la lista de servicios: añadir `emails` al pipeline no obliga a tocar la configuración del repositorio, y ningún filtro puede dejar la PR esperando.
- **Pasa la lista de archivos por `env:`, nunca interpolada en `run:`.** Los nombres de archivo de una PR de terceros son entrada no confiable; `${{ steps.filter.outputs.pedidos_files }}` pegado en un script es una inyección de comandos. Asígnalo a una variable de entorno y úsala como `"$FILES"`.
- **Cuenta con el modo de fallo silencioso del filtro.** Si el diff supera 3000 archivos o agota el tiempo, el comportamiento deja de ser el esperado. Para una migración masiva o un renombrado de carpetas, lanza el workflow a mano (`workflow_dispatch`) y no te fíes de la ausencia de ejecución.
- **Versiona el cambio del filtro junto al código que protege.** Cuando muevas una carpeta, actualiza `paths` en la misma PR: un servicio renombrado cuyo filtro sigue apuntando a la ruta antigua deja de validarse sin ningún error visible.

## Documentación oficial

- [Sintaxis de workflows de GitHub Actions](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions) — las secciones sobre `on.<push|pull_request>.paths` y `branches` detallan los patrones, la regla de «ambos filtros» y los límites del diff.
- [Reutilizar workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows) — `workflow_call`, parámetros y paso de secrets.
- [Solución de problemas de checks requeridos](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks) — la tabla que explica por qué un workflow omitido por rutas bloquea el merge y uno omitido por condición no.
- [dorny/paths-filter](https://github.com/dorny/paths-filter) — la action de terceros para filtrar a nivel de job; incluye ejemplos de salidas y de `fetch-depth`.

## Recursos didácticos

- [Nx: tareas afectadas](https://nx.dev/ci/features/affected) y [Turborepo: CI](https://turborepo.dev/docs/crafting-your-repository/constructing-ci) — cómo las herramientas de grafo resuelven lo que los path filters hacen a mano.

---

*En resumen: en un monorepo, los path filters dan a cada carpeta su propio timbre; la trampa es que un workflow omitido por rutas bloquea los checks requeridos, así que filtra dentro del workflow y exige un único job agregador.*
