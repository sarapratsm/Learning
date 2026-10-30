# GitHub Actions

## ¿Qué es?

GitHub Actions es el motor de CI/CD integrado en GitHub. Los pipelines (aquí llamados *workflows*) son ficheros YAML dentro del repositorio que GitHub ejecuta en máquinas virtuales efímeras cuando ocurre un evento: un `push`, una pull request, una hora fijada, un botón pulsado a mano.

## ¿Por qué existe?

Conectar un servidor de CI externo al repositorio exige cuentas aparte, tokens de acceso en ambos sentidos, webhooks y alguien que mantenga el servidor. GitHub Actions elimina todo eso poniendo la automatización donde ya está el código: se crea un fichero en `.github/workflows/` y, en el siguiente `push`, funciona. No hay nada que instalar ni que enchufar.

Además de ejecutar comandos, tiene un *marketplace* de pasos ya escritos (las *actions*), de modo que descargar el código, instalar un SDK o hacer `docker login` es una línea y no un script propio.

> Si vienes de Jenkins: un workflow es un `Jenkinsfile` que vive en GitHub y cuyo "servidor" administra GitHub. Si vienes de GitLab CI: es el mismo concepto, pero con varios ficheros y con pasos reutilizables publicados por terceros.

## ¿Cuándo y para qué se usa?

En cualquier proyecto alojado en GitHub que quiera automatizar algo ante un evento del repositorio. En la tienda online que sirve de ejemplo (servicios `pedidos`, `pagos`, `inventario` y `emails`):

- Compilar y pasar los tests en cada pull request, para no fusionar código roto.
- Al fusionar en `main`, construir la imagen Docker de `pedidos` y desplegarla en el VPS `203.0.113.10`.
- Lanzar un despliegue manual a producción desde la pestaña *Actions*.
- Tareas que no son despliegue: un test de humo nocturno, etiquetar issues, publicar un paquete.

Cuándo elegir otra herramienta: ver [Cuándo no usarla](#cuándo-no-usarla).

## Vocabulario

| Término | Qué es |
|---|---|
| *Workflow* | Un fichero `.yml` en `.github/workflows/`. Un repositorio puede tener varios. |
| *Event* / *trigger* | Lo que lo dispara, declarado en `on:`. |
| *Job* | Conjunto de pasos que se ejecuta en un mismo *runner*. Los jobs corren **en paralelo** salvo que se encadenen con `needs`. |
| *Step* | Una unidad dentro de un job: un comando (`run:`) o una action (`uses:`). |
| *Action* | Paso empaquetado y reutilizable (`actions/checkout`). |
| *Runner* | La máquina que ejecuta un job. *GitHub-hosted* (la pone GitHub) o *self-hosted* (la pones tú). |
| *Artifact* | Fichero que un job guarda para que lo descarguen otro job o una persona. |
| *Secret* / *variable* | Valores configurados en la web del repositorio y leídos con `secrets.X` y `vars.X`. |
| *Context* | Objetos con información disponibles en expresiones `${{ ... }}`: `github`, `env`, `secrets`, `needs`, `matrix`... |

Cada job arranca en una máquina **limpia**: lo que un job deja en disco no existe para el siguiente. Esa es la causa de casi todo lo que sorprende al empezar, y la razón de que existan los artefactos y las cachés.

## Primer workflow completo: de `push` a producción

Un workflow que compila, prueba, construye la imagen de `pedidos` y la despliega, en tres bloques.

### 1. Compilar y probar

Fichero `.github/workflows/ci.yml`:

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
      - uses: actions/setup-dotnet@v6
        with:
          dotnet-version: 10.0.x
      - run: dotnet build --configuration Release
      - run: dotnet test --configuration Release --no-build --logger trx --results-directory TestResults
```

- `on:` dispara el workflow con los `push` a `main` y con cualquier pull request.
- `permissions: contents: read` recorta el token automático al mínimo (ver [Buenas prácticas avanzadas](#buenas-prácticas-avanzadas)).
- `ubuntu-latest` apunta hoy a Ubuntu 24.04 (comprobado el 2026-10-30 en la documentación de GitHub).
- `actions/checkout` descarga el código: sin él, el runner está vacío.
- `setup-dotnet` instala el SDK; `10.0.x` toma el último parche de .NET 10.

Al subir el fichero, la pestaña *Actions* del repositorio muestra la ejecución. Si un `run:` devuelve un código distinto de 0, el paso falla, los siguientes se saltan y el job se marca en rojo.

### 2. Construir la imagen y publicarla

Se añade un segundo job que depende del primero y publica la imagen en el registro de GitHub (`ghcr.io`):

```yaml
  imagen:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v7
      - uses: docker/setup-buildx-action@v4
      - uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v7
        with:
          context: ./pedidos
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/tienda-pedidos:${{ github.sha }}
            ghcr.io/${{ github.repository_owner }}/tienda-pedidos:latest
```

- `needs: test` hace que el job espere a `test` y no arranque si este falla.
- `if:` limita el job a `main`: en las pull requests se prueba pero no se publica.
- `permissions` dentro del job **sustituye** al del workflow: aquí hace falta `packages: write` para empujar al registro, y nada más.
- `GITHUB_TOKEN` es un secret que GitHub crea solo en cada ejecución; no hay que configurarlo.
- La etiqueta con `github.sha` identifica la imagen de forma inmutable; `latest` se mueve. Para qué etiqueta desplegar, ver [Estrategias de despliegue](Estrategias-de-Despliegue.md).

Los detalles de construcción de imágenes en CI (cachés de capas, multi-plataforma, escaneo) están en [Docker en CI/CD](Docker-en-CI-CD.md).

### 3. Desplegar en el VPS

```yaml
  desplegar:
    needs: imagen
    runs-on: ubuntu-latest
    environment: production
    concurrency: deploy-production
    steps:
      - name: Preparar SSH
        run: |
          install -m 700 -d ~/.ssh
          echo "${{ secrets.DEPLOY_SSH_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          echo "${{ secrets.DEPLOY_KNOWN_HOSTS }}" > ~/.ssh/known_hosts
      - name: Actualizar el servicio
        run: |
          ssh deployer@203.0.113.10 \
            "cd /srv/tienda && docker compose pull pedidos && docker compose up -d pedidos"
```

- `environment: production` enlaza el job con un *environment* configurado en *Settings → Environments*, donde se pueden exigir aprobaciones manuales y guardar secrets que solo ese job ve.
- `concurrency` evita que dos despliegues se pisen: el segundo espera al primero.
- `DEPLOY_SSH_KEY` y `DEPLOY_KNOWN_HOSTS` (la huella del servidor, obtenida con `ssh-keyscan 203.0.113.10` y revisada una vez a mano) son secrets del repositorio o del environment. Cómo guardarlos y rotarlos: [Secrets y variables](Secrets-y-Variables.md).
- El servidor debe hacer `docker login ghcr.io` una vez con un token de solo lectura de paquetes.

El fichero completo es la unión de los tres bloques bajo un único `jobs:`. El orden resultante es `test` → `imagen` → `desplegar`. Estrategias más cuidadosas que reemplazar el contenedor (azul/verde, canario, *rollback*): [Estrategias de despliegue](Estrategias-de-Despliegue.md).

## Disparadores (`on`)

Un workflow puede escuchar varios eventos a la vez. Los habituales:

```yaml
on:
  push:
    branches: [main]
    tags: ['v*']              # también etiquetas tipo v1.4.0
    paths: ['pedidos/**']     # solo si cambia algo de esa carpeta
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 3 * * *'       # cada día a las 03:00 UTC
  workflow_dispatch:          # botón "Run workflow" en la web
    inputs:
      entorno:
        type: choice
        options: [staging, production]
        default: staging
```

| Evento | Cuándo se ejecuta | Nota |
|---|---|---|
| `push` | Al empujar commits o tags | Con `branches`, `tags` y `paths` se filtra |
| `pull_request` | Al abrir, actualizar o reabrir una PR | Ejecuta el código **fusionado** con la rama destino |
| `schedule` | Según cron | Siempre UTC; intervalo mínimo de 5 minutos |
| `workflow_dispatch` | A mano o por API | Admite `inputs`; leídos con `${{ inputs.entorno }}` |
| `workflow_call` | Lo invoca otro workflow | Base de los *reusable workflows* |

Los filtros `paths` son la base de los monorepos: ver [Monorepo y path filters](Monorepo-y-Path-Filters.md). El disparo por etiqueta para publicar versiones está en [Release por tag](Release-por-Tag.md).

## Jobs, dependencias y datos entre ellos

Sin `needs`, todos los jobs arrancan a la vez, cada uno en su máquina. Con `needs` forman un grafo:

```yaml
jobs:
  compilar: { ... }
  test:    { needs: compilar, ... }
  lint:    { needs: compilar, ... }
  desplegar: { needs: [test, lint], ... }
```

`test` y `lint` corren en paralelo y `desplegar` espera a ambos.

Para pasar un valor corto de un job a otro se usan *outputs*:

```yaml
jobs:
  version:
    runs-on: ubuntu-latest
    outputs:
      tag: ${{ steps.calc.outputs.tag }}
    steps:
      - id: calc
        run: echo "tag=$(date +%Y%m%d)-${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"
  imagen:
    needs: version
    runs-on: ubuntu-latest
    steps:
      - run: echo "Construyendo ${{ needs.version.outputs.tag }}"
```

Para pasar ficheros se usan artefactos (siguiente sección).

## Artefactos y cachés

Los dos guardan ficheros entre ejecuciones o jobs, pero con garantías distintas:

| | Artefacto | Caché |
|---|---|---|
| Para qué | Resultado que se **necesita** después (binarios, informes) | Acelerador de dependencias descargables |
| Garantía | Existe mientras no caduque (90 días por defecto) | Puede no existir; si falta, se reconstruye |
| Quién lo ve | Otros jobs y las personas, desde la web | Solo los workflows del repositorio |
| Acciones | `actions/upload-artifact` y `download-artifact` | `actions/cache` |

Artefacto: guardar el informe de tests aunque fallen, y reutilizar el resultado de la compilación en otro job:

```yaml
      - run: dotnet publish pedidos -c Release -o publish
      - uses: actions/upload-artifact@v7
        with:
          name: pedidos-publish
          path: publish/
          retention-days: 7
      - uses: actions/upload-artifact@v7
        if: always()                 # también cuando los tests han fallado
        with:
          name: informe-tests
          path: TestResults/
```

```yaml
  otro-job:
    needs: compilar
    steps:
      - uses: actions/download-artifact@v8
        with:
          name: pedidos-publish
          path: publish/
```

Caché: los paquetes NuGet se descargan en cada ejecución salvo que se cacheen. La clave se calcula a partir de los ficheros que los definen, de modo que cambia solo cuando cambian las dependencias:

```yaml
      - uses: actions/cache@v6
        with:
          path: ~/.nuget/packages
          key: nuget-${{ runner.os }}-${{ hashFiles('**/*.csproj', '**/packages.lock.json') }}
          restore-keys: |
            nuget-${{ runner.os }}-
```

Si no hay coincidencia exacta con `key`, se prueba con `restore-keys` y se restaura la caché más parecida; al terminar el job se guarda la nueva. Las acciones `setup-*` (`setup-dotnet`, `setup-node`...) traen una opción `cache:` que hace esto sin escribirlo.

## Matrices

Una *matrix* repite un job con combinaciones de valores. Útil para probar en varios sistemas o para repetir el mismo paso en los cuatro servicios de la tienda:

```yaml
jobs:
  imagen:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        servicio: [pedidos, pagos, inventario, emails]
    steps:
      - uses: actions/checkout@v7
      - run: docker build -t tienda-${{ matrix.servicio }} ./${{ matrix.servicio }}
```

Genera cuatro jobs en paralelo. `fail-fast: false` evita que, al fallar uno, GitHub cancele los demás (el valor por defecto es `true`). Con dos ejes (`servicio` y `os`) se generan todas las combinaciones; `include:` añade combinaciones sueltas y `exclude:` quita las que no interesan.

## Runners

- **GitHub-hosted**: `ubuntu-latest`, `windows-latest`, `macos-latest`. Se crean limpios para cada job y se destruyen. Los repositorios públicos no consumen cuota; en los privados, el plan gratuito incluye un crédito mensual (12 USD de uso, unos 2.000 minutos de Linux de 2 núcleos según la documentación consultada el 2026-10-30), y los minutos de Windows y macOS cuestan más.
- **Self-hosted**: un agente (`actions/runner`) instalado en una máquina propia, seleccionado con `runs-on: [self-hosted, linux]`. Sirve para acceder a redes internas, hardware especial o evitar la cuota. A cambio, el runner **no está limpio** entre jobs (hay que limpiar) y, en repositorios públicos, ejecuta código de desconocidos: no se usa nunca con repos públicos.

## Condiciones

`if:` decide si se ejecuta un paso o un job. La expresión no necesita `${{ }}` en esa clave:

```yaml
- run: ./notificar.sh
  if: failure() && github.ref == 'refs/heads/main'
```

| Función o contexto | Para qué |
|---|---|
| `success()` | Valor por defecto: solo si todo lo anterior fue bien |
| `failure()` | Si algún paso anterior falló |
| `always()` | Siempre, incluso tras un fallo o una cancelación |
| `github.ref`, `github.event_name` | Rama o tag y tipo de evento |
| `contains(github.event.head_commit.message, '[skip deploy]')` | Búsqueda en texto |

## Reutilización

- **Actions de composición** (`runs: using: composite`): empaquetan una secuencia de pasos en un `action.yml` dentro del repositorio.
- **Reusable workflows** (`on: workflow_call`): un workflow completo que otros invocan como si fuera un job.

```yaml
# .github/workflows/desplegar.yml (el reutilizable)
on:
  workflow_call:
    inputs:
      servicio: { type: string, required: true }
    secrets:
      DEPLOY_SSH_KEY: { required: true }
```

```yaml
# .github/workflows/ci.yml (quien lo llama)
jobs:
  desplegar-pedidos:
    uses: ./.github/workflows/desplegar.yml
    with:
      servicio: pedidos
    secrets: inherit
```

Para compartir entre repositorios, `uses: organizacion/repo-comun/.github/workflows/desplegar.yml@main` (mejor fijado a un tag o commit).

## Secrets y variables

Los secrets se definen en *Settings → Secrets and variables → Actions* (a nivel de repositorio, de organización o de *environment*) y se leen con `${{ secrets.NOMBRE }}`. GitHub los reemplaza por `***` en los logs. Las variables no sensibles (`vars.NOMBRE`) se definen en el mismo sitio y sí se ven.

```yaml
- run: ./notificar.sh
  env:
    URL_AVISOS: ${{ secrets.URL_AVISOS }}
```

Pasarlos por `env:` y no interpolarlos dentro del script evita que un valor con comillas rompa la sintaxis. Un secret **no existe** en los workflows de pull requests procedentes de un fork. Qué guardar como secret, cómo rotarlos y cuándo usar OIDC en lugar de claves largas: [Secrets y variables](Secrets-y-Variables.md).

## Errores frecuentes

| Síntoma (mensaje real) | Causa | Solución |
|---|---|---|
| `Invalid workflow file: .github/workflows/ci.yml#L12 ... You have an error in your yaml syntax on line 12` | Indentación o dos puntos mal puestos | Validar el YAML; en el editor de GitHub, el aviso apunta a la línea |
| `Error: Unable to resolve action actions/checkout@v9, unable to find version v9` | La versión no existe | Comprobar los tags en el repositorio de la action |
| `Resource not accessible by integration` | El `GITHUB_TOKEN` no tiene el permiso (escribir paquetes, comentar PRs) | Añadir el permiso concreto en `permissions:` del job |
| `Permission denied (publickey).` al desplegar | La clave privada no coincide con la autorizada para `deployer`, o llegó con formato roto | Regenerar el par; pegar el secret con el salto de línea final |
| `Host key verification failed.` | `known_hosts` vacío o con otra huella | Cargar `ssh-keyscan` del servidor en `DEPLOY_KNOWN_HOSTS` |
| `denied: permission_denied: write_package` al hacer push a `ghcr.io` | Falta `packages: write` | Añadirlo en el job que publica |
| El secret llega vacío y el despliegue falla sin pistas | La ejecución viene de un fork, o el secret está en un *environment* que el job no declara | Declarar `environment:` o definir el secret en el repositorio |
| El job de despliegue arranca aunque los tests fallaron | Falta `needs:` | Declarar la dependencia |
| Error `Process completed with exit code 1.` | Es solo el resumen: el fallo real está en las líneas anteriores del log | Abrir el paso en rojo y leer hacia arriba |

## Cuándo no usarla

- El código no está en GitHub: está atada a sus repositorios.
- Hay que ejecutar todo en una red aislada sin salida a internet y sin posibilidad de runners propios: Jenkins encaja mejor (ver [Jenkins](Jenkins.md)).
- Se necesita una orquestación muy compleja con aprobaciones, ventanas y múltiples entornos como producto de gestión de releases: Actions cubre lo básico con *environments*, pero no es una herramienta de gestión de releases.
- Las pruebas son muy largas y consumen minutos de pago: runners propios o una máquina dedicada salen más baratos.

## Tabla de decisión

| Situación | Elección |
|---|---|
| Un paso que ya existe (checkout, login, setup de SDK) | `uses:` con una action |
| Una operación de dos líneas que solo usa el proyecto | `run:` directamente |
| El mismo flujo en varios repositorios | *Reusable workflow* con `workflow_call` |
| La misma secuencia de pasos dentro de un repositorio | Action de composición |
| Un resultado que otro job necesita | Artefacto |
| Dependencias que se descargan siempre | Caché |
| Repetir un job con valores distintos | `matrix` |
| Entorno con aprobación manual | `environment` con *required reviewers* |
| Acceso a una red interna | Runner self-hosted |

## Equivalencia de vocabulario

| GitHub Actions | GitLab CI | Jenkins |
|---|---|---|
| Workflow (`.github/workflows/*.yml`) | Pipeline (`.gitlab-ci.yml`) | Pipeline (`Jenkinsfile`) |
| `on:` | `rules:` / `workflow:` | `triggers { }` / webhooks |
| Job | Job | Stage (con sus `steps`) |
| Step (`run:` / `uses:`) | Línea de `script:` | `steps { sh '...' }` |
| Action | `include:` o imagen con herramientas | Plugin o *shared library* |
| Runner | Runner | Agente (*agent*, *node*) |
| `needs:` | `needs:` (y `stages:` por orden) | Orden de `stage` y `parallel` |
| Artefacto | `artifacts:` | `archiveArtifacts` / `stash` |
| Caché | `cache:` | Caché del agente o volumen |
| `matrix` | `parallel: matrix` | `matrix { axes { } }` |
| Secret | Variable *masked* / *protected* | Credencial (*Credentials*) |
| `environment` | `environment` | `input` + credenciales por entorno |

Sus fichas hermanas: [GitLab CI](GitLab-CI.md) y [Jenkins](Jenkins.md).

## Buenas prácticas avanzadas

- **Ancla las actions de terceros a un commit SHA, no a un tag.** `docker/login-action@v4` parece fijo, pero un tag de Git se puede mover: si comprometen la cuenta del autor, `v4` puede pasar a apuntar a código malicioso que corre con acceso a los secrets. Anclar al hash completo (`uses: docker/login-action@<40 caracteres>  # v4.7.0`) hace el paso inmutable; Dependabot actualiza esos hashes. Las actions del propio GitHub (`actions/*`) conllevan menos riesgo, pero la regla vale igual para el resto.
- **Recorta los permisos del `GITHUB_TOKEN`.** Según la configuración del repositorio, el token automático puede tener escritura sobre casi todo. Declara arriba `permissions: { contents: read }` y amplía solo en el job que lo necesite (`packages: write`, `pull-requests: write`): si un paso comprometido roba el token, el daño queda acotado. Al indicar un permiso, todos los demás pasan a `none`.
- **Cancela ejecuciones obsoletas con `concurrency`.** Sin ello, cada push a una pull request encola un workflow nuevo mientras los anteriores siguen corriendo. Para CI se cancela; para despliegues **no** (cancelar a mitad deja el servidor en estado indefinido):

  ```yaml
  concurrency:
    group: ci-${{ github.ref }}
    cancel-in-progress: true
  ```
- **Trata `pull_request_target` con cuidado extremo.** A diferencia de `pull_request`, se ejecuta en el contexto de la rama destino y **con acceso a los secrets**, sobre eventos que puede provocar cualquiera desde un fork. Si además se hace checkout del código del fork, un desconocido puede exfiltrar los secrets abriendo una PR. Solo se usa para tareas que no ejecutan código del fork (etiquetar, comentar).
- **No interpoles texto controlable por terceros dentro de `run:`.** `run: echo "${{ github.event.pull_request.title }}"` inserta el título de la PR en el script antes de ejecutarlo: un título con `"; curl ... | sh #` ejecuta código. Pasa el valor por una variable de entorno (`env: TITULO: ${{ ... }}`) y úsala como `"$TITULO"`.
- **Fija `timeout-minutes` en los jobs.** El valor por defecto es de 360 minutos: un test colgado consume seis horas de cuota antes de abortarse.

## Documentación oficial

- [Documentación de GitHub Actions](https://docs.github.com/en/actions) — punto de entrada; las secciones *Learn GitHub Actions* y *Security for GitHub Actions* son las que más rentabilizan la lectura.
- [Sintaxis de workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax) — referencia completa de claves (`on`, `permissions`, `concurrency`, `strategy`); consultarla cuando una clave no se comporta como se espera.

---

*En resumen: GitHub Actions es CI/CD que ya vive dentro del repositorio: un YAML por workflow, jobs en máquinas limpias encadenados con `needs`, y todo lo demás (caché, artefactos, matrices, reutilización) existe para no empezar de cero en cada ejecución.*
