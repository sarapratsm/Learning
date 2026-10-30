# GitLab CI/CD

## ¿Qué es?

GitLab CI/CD es el motor de integración y despliegue continuo integrado en GitLab. Todo el pipeline se describe en un fichero, `.gitlab-ci.yml`, en la raíz del repositorio, y lo ejecutan *runners*: procesos que recogen los trabajos pendientes y los corren, normalmente dentro de contenedores Docker.

## ¿Por qué existe?

GitLab nació como plataforma única: repositorio, *merge requests*, registro de imágenes, gestor de incidencias y CI en el mismo sitio, con el mismo sistema de permisos. Un pipeline no necesita credenciales para leer el código, ni un registro externo donde publicar la imagen, ni un webhook que avise de los cambios: todo eso ya existe en el proyecto y llega al job en variables predefinidas (`CI_REGISTRY_IMAGE`, `CI_COMMIT_SHA`...).

La otra decisión de diseño es que el trabajo corre **dentro de una imagen Docker elegida por el job**: en vez de instalar el SDK de .NET en la máquina de CI, se declara `image: mcr.microsoft.com/dotnet/sdk:10.0` y el job arranca con él.

> Si conoces GitHub Actions: es el mismo concepto con un solo fichero y otro vocabulario: *pipeline* en vez de *workflow*, *stage* para agrupar jobs en fases, *merge request* en vez de *pull request*. Si conoces Jenkins: `.gitlab-ci.yml` es un `Jenkinsfile` declarativo, sin Groovy.

## ¿Cuándo y para qué se usa?

En proyectos alojados en GitLab (en gitlab.com o en una instalación propia) que quieran automatizar pruebas y despliegues. En la tienda online de ejemplo (`pedidos`, `pagos`, `inventario`, `emails`):

- Compilar y probar en cada *merge request* antes de aceptarla.
- Al fusionar en la rama principal, construir la imagen de `pedidos`, publicarla en el registro del propio proyecto y desplegarla en el VPS `203.0.113.10`.
- Poner el despliegue a producción detrás de un botón manual.
- Ejecutar tareas programadas (*pipeline schedules*) como un test de humo nocturno.

Cuándo elegir otra herramienta: ver [Cuándo no usarla](#cuándo-no-usarla).

## Vocabulario

| Término | Qué es |
|---|---|
| *Pipeline* | Una ejecución completa de `.gitlab-ci.yml` para un commit o evento. |
| *Stage* | Fase con nombre. Los jobs de un mismo stage corren en paralelo; el stage siguiente no empieza hasta que el anterior termina bien (salvo que se use `needs`). |
| *Job* | Unidad de trabajo: una lista de comandos (`script:`) asignada a un stage. |
| *Runner* | Agente que ejecuta jobs. *Shared* (de GitLab o de la instancia) o *specific* (propio del proyecto o grupo). |
| *Executor* | Cómo ejecuta el runner cada job: `docker` (contenedor nuevo, el habitual), `shell`, `kubernetes`... |
| *Artifacts* | Ficheros que un job conserva y que reciben los jobs de stages posteriores. |
| *Cache* | Ficheros que se reutilizan entre pipelines para acelerar (dependencias). Sin garantías. |
| *Variables* | Valores de entorno: predefinidos (`CI_*`), declarados en el YAML o configurados en la web. |
| *Environment* | Destino de despliegue con nombre (`staging`, `production`), con historial y botón de *rollback*. |

Cada job corre en un contenedor **limpio**: lo que un job escribe en disco solo llega al siguiente por artefactos o caché.

## Primer pipeline completo: de `push` a producción

Un único fichero, `.gitlab-ci.yml`, con cuatro stages: compilar, probar, empaquetar la imagen y desplegar.

### 1. Compilar y probar

```yaml
stages: [build, test, package, deploy]

default:
  image: mcr.microsoft.com/dotnet/sdk:10.0

variables:
  NUGET_PACKAGES: $CI_PROJECT_DIR/.nuget

build:
  stage: build
  script:
    - dotnet build --configuration Release
  artifacts:
    paths:
      - "**/bin/Release/"
      - "**/obj/"
    expire_in: 1 day
  cache:
    key:
      files: [packages.lock.json]
    paths: [.nuget/]

test:
  stage: test
  script:
    - dotnet test --configuration Release --no-build --logger trx --results-directory TestResults
  artifacts:
    when: always
    paths: [TestResults/]
    expire_in: 1 week
```

- `stages` fija el orden. Un job sin `stage:` va a `test`.
- `default:` aplica una imagen (y otras claves) a todos los jobs.
- `NUGET_PACKAGES` redirige la caché de NuGet a una carpeta **dentro del proyecto**, porque GitLab solo cachea rutas bajo `$CI_PROJECT_DIR`.
- `artifacts` pasa el resultado compilado al job `test`, que lo recibe automáticamente por ser de un stage posterior; con `--no-build` no se recompila.
- `artifacts: when: always` conserva los informes aunque los tests fallen.
- `cache: key: files:` calcula la clave a partir del hash del fichero indicado: la caché solo se renueva cuando cambian las dependencias.

Si cualquier comando de `script` termina con código distinto de 0, el job falla, los stages siguientes no se ejecutan y la merge request muestra el pipeline en rojo.

### 2. Construir la imagen y publicarla en el registro del proyecto

```yaml
package:
  stage: package
  image: docker:29-cli
  services:
    - docker:29-dind
  variables:
    DOCKER_TLS_CERTDIR: "/certs"
  before_script:
    - echo "$CI_REGISTRY_PASSWORD" | docker login -u "$CI_REGISTRY_USER" --password-stdin "$CI_REGISTRY"
  script:
    - docker build -t "$CI_REGISTRY_IMAGE/pedidos:$CI_COMMIT_SHORT_SHA" ./pedidos
    - docker push "$CI_REGISTRY_IMAGE/pedidos:$CI_COMMIT_SHORT_SHA"
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

- `services: docker:29-dind` arranca un demonio Docker auxiliar (*Docker-in-Docker*) junto al job; el cliente `docker:29-cli` habla con él. Para que funcione, el runner debe estar registrado con `privileged = true` (los runners compartidos de gitlab.com ya lo están).
- `CI_REGISTRY`, `CI_REGISTRY_USER`, `CI_REGISTRY_PASSWORD` y `CI_REGISTRY_IMAGE` los inyecta GitLab; el usuario y la contraseña son un token válido solo durante el job.
- `rules` limita el job a la rama por defecto: en las merge requests se prueba pero no se publica.

Alternativas a Docker-in-Docker (montar el socket del host, Kaniko, BuildKit sin privilegios) y su compromiso entre seguridad y velocidad: [Docker en CI/CD](Docker-en-CI-CD.md).

### 3. Desplegar en el VPS

```yaml
deploy:
  stage: deploy
  image: alpine:3
  environment:
    name: production
    url: https://tienda.ejemplo.com
  resource_group: production
  before_script:
    - apk add --no-cache openssh-client
    - chmod 600 "$DEPLOY_SSH_KEY"
    - mkdir -p ~/.ssh && cp "$DEPLOY_KNOWN_HOSTS" ~/.ssh/known_hosts
  script:
    - >
      ssh -i "$DEPLOY_SSH_KEY" deployer@203.0.113.10
      "cd /srv/tienda && docker compose pull pedidos && docker compose up -d pedidos"
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      when: manual
```

- `rules: when: manual` crea el job con un botón *Run*: el pipeline llega a `package` solo y el despliegue lo lanza una persona.
- `environment` registra el despliegue en *Operate → Environments*, con enlace al sitio.
- `resource_group` garantiza que no corran dos despliegues a la vez, aunque vengan de pipelines distintos.
- `DEPLOY_SSH_KEY` y `DEPLOY_KNOWN_HOSTS` son variables de tipo **File** configuradas en *Settings → CI/CD → Variables*: GitLab escribe el contenido en un fichero temporal y la variable contiene su ruta. Cómo guardarlas, protegerlas y rotarlas: [Secrets y variables](Secrets-y-Variables.md).
- El servidor debe haber hecho `docker login` una vez contra el registro con un *deploy token* de solo lectura.

La estrategia usada aquí es la más simple (reemplazar el contenedor). Las alternativas están en [Estrategias de despliegue](Estrategias-de-Despliegue.md).

## Disparadores: `rules` y `workflow`

Un pipeline se crea por un evento (push, merge request, schedule, tag, API, botón) y `rules:` decide qué jobs entran. Cada regla es una condición; gana la primera que coincide:

```yaml
deploy:
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      when: manual
    - when: never
```

| Variable | Contiene |
|---|---|
| `CI_COMMIT_BRANCH` | La rama (vacía en pipelines de merge request y de tag) |
| `CI_COMMIT_TAG` | El tag, si el pipeline es de un tag |
| `CI_PIPELINE_SOURCE` | `push`, `merge_request_event`, `schedule`, `web`, `api`... |
| `CI_DEFAULT_BRANCH` | Nombre de la rama por defecto |
| `CI_MERGE_REQUEST_ID` | Identificador, solo en pipelines de merge request |

`rules:changes` ejecuta el job solo si cambian ciertas rutas (base de los monorepos: [Monorepo y path filters](Monorepo-y-Path-Filters.md)). A nivel de fichero, `workflow: rules:` decide si el pipeline existe; sirve para evitar el pipeline duplicado que aparece cuando un `push` y una merge request lanzan uno cada uno:

```yaml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS
      when: never
    - if: $CI_COMMIT_BRANCH
```

Los tags de versión como disparador del despliegue: [Release por tag](Release-por-Tag.md). `only:` y `except:` son sintaxis heredada: GitLab remite a `rules:` y no se combinan con ella en el mismo job.

## Stages y `needs`

Por defecto, ningún job de un stage empieza hasta que **todos** los del anterior terminan. Con `needs:` se declara qué necesita cada job realmente y GitLab construye un grafo:

```yaml
test-pedidos:
  stage: test
  needs: [build-pedidos]
  script: dotnet test pedidos

package-pedidos:
  stage: package
  needs: [test-pedidos]
  script: ./empaquetar.sh pedidos
```

`package-pedidos` arranca en cuanto termina `test-pedidos`, sin esperar a los tests de `pagos` o `inventario`. `needs: []` hace que un job arranque inmediatamente. Con `needs`, el job solo recibe los artefactos de los jobs listados; `needs: [{ job: build, artifacts: false }]` evita descargarlos.

## Artefactos y caché

| | `artifacts` | `cache` |
|---|---|---|
| Para qué | Pasar resultados de un job a los siguientes y conservarlos | Reutilizar dependencias entre pipelines |
| Garantía | Existe mientras no caduque (`expire_in`) | Puede faltar (es local al runner o a un almacén compartido) |
| Se descarga | Automáticamente en los jobs posteriores | Según `key` y `policy` |
| Visible en la web | Sí, se pueden descargar | No |

Ficheros de un job accesibles para siempre desde la web: `artifacts: paths` + `expire_in`. Para una caché de solo lectura en los jobs que no la modifican (más rápida), `cache: policy: pull`; el job que la construye usa `pull-push` (el valor por defecto).

## Matrices

`parallel: matrix` repite un job una vez por cada combinación de variables, y cada combinación se ejecuta en paralelo:

```yaml
imagen:
  stage: package
  parallel:
    matrix:
      - SERVICIO: [pedidos, pagos, inventario, emails]
  script:
    - docker build -t "$CI_REGISTRY_IMAGE/$SERVICIO:$CI_COMMIT_SHORT_SHA" "./$SERVICIO"
```

Genera cuatro jobs (`imagen: [pedidos]`, `imagen: [pagos]`...). Con dos variables se obtiene el producto de las combinaciones; el máximo son 200 jobs por matriz.

## Runners

- **Runners compartidos (*SaaS*)** de gitlab.com: Linux x86-64 por defecto, con la etiqueta `saas-linux-small-amd64` (2 vCPU, 8 GB; comprobado el 2026-10-30). Los jobs sin `tags:` caen ahí. El plan gratuito tiene una cuota mensual de minutos de cómputo (consultar la cifra vigente en la documentación, que cambia por plan).
- **Runners propios**: se instala `gitlab-runner` en una máquina y se registra con un token del proyecto, grupo o instancia. Se asignan jobs con `tags:`: `tags: [vps-privado]`. Sirven para redes internas, hardware especial o más control sobre la caché.

Los runners propios con executor `docker` y `privileged = true` permiten Docker-in-Docker, pero un job con ese privilegio puede escapar del contenedor: no se comparten con proyectos de terceros.

## Reutilización

- **`extends`** hereda configuración de un job plantilla (los que empiezan por punto no se ejecutan):

  ```yaml
  .base-dotnet:
    image: mcr.microsoft.com/dotnet/sdk:10.0
    cache:
      key: { files: [packages.lock.json] }
      paths: [.nuget/]

  test:
    extends: .base-dotnet
    script: dotnet test
  ```

- **`include`** trae YAML de otro fichero, de otro proyecto o de una URL: `include: [{ project: plataforma/ci-comun, file: /dotnet.yml, ref: v2 }]`. Es el equivalente a un *reusable workflow* de Actions.
- **`default:`** fija valores globales (imagen, `before_script`, `retry`).
- **Anclas YAML** (`&` y `*`) y `!reference [.job, script]` para fragmentos sueltos.

## Variables y secretos

Las variables se definen en `variables:` (visibles en el repositorio) o en *Settings → CI/CD → Variables* (privadas). Opciones que importan en las segundas:

| Opción | Efecto |
|---|---|
| *Masked* | El valor aparece como `[MASKED]` en los logs (requiere formato compatible) |
| *Protected* | Solo existe en ramas y tags protegidos |
| Tipo *File* | La variable contiene la ruta de un fichero con el valor |
| *Environment scope* | Limita la variable a un environment (`production`) |

Para elegir cuál usar en cada caso y cómo rotarlas: [Secrets y variables](Secrets-y-Variables.md).

## Errores frecuentes

| Síntoma (mensaje real) | Causa | Solución |
|---|---|---|
| `test job: chosen stage does not exist; available stages are .pre, build, test, deploy, .post` | El `stage:` del job no está en la lista `stages:` | Añadir el stage o corregir el nombre |
| `Cannot connect to the Docker daemon at tcp://docker:2375. Is the docker daemon running?` | Falta el servicio `docker:dind`, el runner no es privilegiado, o `DOCKER_TLS_CERTDIR` no coincide con el puerto usado | Declarar `services`, usar un runner privilegiado, no mezclar TLS (`2376`) y sin TLS (`2375`) |
| La variable `$DEPLOY_SSH_KEY` está vacía en el job | Es *protected* y la rama no lo es | Proteger la rama o quitar *protected* si es un entorno de pruebas |
| `Permission denied (publickey).` al desplegar | Clave privada que no corresponde a la autorizada para `deployer`, o permisos distintos de `600` | `chmod 600`; regenerar el par |
| `Host key verification failed.` | `known_hosts` vacío o con otra huella | Cargar la salida de `ssh-keyscan` verificada |
| `This job is stuck because the project doesn't have any runners online assigned to it` | Ningún runner coincide con los `tags:` del job | Quitar el tag o registrar un runner con él |
| Falta un fichero en el job siguiente a veces sí y a veces no | Se pasa por `cache` y no por `artifacts` | Pasar resultados con `artifacts` |
| `ERROR: Job failed: exit code 1` | Es el resumen; el fallo real está en las líneas anteriores | Leer el log del job hacia arriba |
| Dos pipelines por cada push a una rama con merge request abierta | Falta `workflow: rules` | Añadir el bloque `workflow:` de la sección de disparadores |

## Cuándo no usarla

- El código está en GitHub o en otro alojamiento: aunque GitLab puede lanzar pipelines desde repositorios externos, pierde la integración que es su ventaja.
- Se necesita una red completamente aislada y no hay GitLab propio ni runners propios: [Jenkins](Jenkins.md) o un GitLab autoalojado.
- Se espera lógica compleja de programación dentro del pipeline (bucles, condiciones sobre estructuras de datos): el YAML se queda corto y conviene mover esa lógica a scripts.

## Tabla de decisión

| Situación | Elección |
|---|---|
| Decidir si un job existe según rama, tag o ruta | `rules:` |
| Un job necesita solo parte del stage anterior | `needs:` |
| Pasar el resultado de un build al job siguiente | `artifacts` |
| No descargar dependencias en cada pipeline | `cache` con `key: files` |
| Repetir un job para varios servicios | `parallel: matrix` |
| Compartir configuración dentro del fichero | `extends` o anclas |
| Compartir configuración entre proyectos | `include: project` |
| Despliegue con botón | `rules: when: manual` + `environment` |
| Que no se pisen dos despliegues | `resource_group` |

## Equivalencia de vocabulario

| GitLab CI | GitHub Actions | Jenkins |
|---|---|---|
| Pipeline (`.gitlab-ci.yml`) | Workflow (`.github/workflows/*.yml`) | Pipeline (`Jenkinsfile`) |
| `rules:` / `workflow:` | `on:` y `if:` | `triggers { }` y `when { }` |
| Stage | Orden por `needs` (no hay stages) | `stage('...')` |
| Job | Job | Stage con `steps` |
| `script:` | `run:` | `sh '...'` |
| `image:` | `container:` o imagen del runner | `agent { docker { image '...' } }` |
| Runner | Runner | Agente (*agent*, *node*) |
| `artifacts:` | `upload-artifact` / `download-artifact` | `archiveArtifacts` / `stash` |
| `cache:` | `actions/cache` | Caché del agente o volumen |
| `parallel: matrix` | `strategy.matrix` | `matrix { axes { } }` |
| `include` / `extends` | *Reusable workflow* / composite action | *Shared library* |
| Variable *masked* / *protected* | Secret / `vars` | Credencial |
| `environment` | `environment` | `input` + credenciales por entorno |

Sus fichas hermanas: [GitHub Actions](GitHub-Actions.md) y [Jenkins](Jenkins.md).

## Buenas prácticas avanzadas

- **Usa `rules:` en lugar de `only`/`except`.** `only`/`except` es sintaxis heredada y no admite condiciones complejas. `rules:` decide por rama, por archivos cambiados o por variables, y cambia el comportamiento (`when: manual`, `allow_failure`) según la condición. Un detalle: en una regla con `when: manual`, `allow_failure` vale `false` por defecto, así que el job bloquea el pipeline hasta que alguien lo ejecute; añade `allow_failure: true` si el pipeline debe poder darse por terminado sin él.
- **Rompe la rigidez de los stages con `needs:`.** En pipelines con varios servicios, el ahorro de tiempo suele ser grande: cada rama del grafo avanza a su ritmo y un test lento de `emails` no retrasa el despliegue de `pedidos`.
- **No confundas `cache` con `artifacts`.** Si el pipeline "a veces falla porque falta un fichero", casi seguro se está pasando un resultado por `cache`, que es un acelerador sin garantías.
- **Marca las variables sensibles como *protected* y *masked*, y alinea las ramas.** *Protected* evita que una rama cualquiera exfiltre el token de producción, y es también la razón de que "la variable no llega" desde una rama sin proteger. Con *environment scope* se limita además cada variable a su entorno.
- **Fija las imágenes por versión o digest.** `image: docker:latest` hace que un pipeline que ayer funcionaba falle hoy sin que haya cambiado el repositorio. Usa etiquetas de versión (`docker:29-cli`) y, para máxima reproducibilidad, el *digest* (`image: docker@sha256:...`).
- **Valida el YAML antes de subirlo.** La pestaña *Build → Pipeline editor* del proyecto incluye un validador y muestra el YAML ya expandido tras `include` y `extends`, que es el que de verdad se ejecuta.

## Documentación oficial

- [Referencia de la sintaxis de `.gitlab-ci.yml`](https://docs.gitlab.com/ci/yaml/) — todas las claves; consultar primero `rules`, `needs`, `cache` y `artifacts`.
- [Docker-in-Docker en GitLab CI](https://docs.gitlab.com/ci/docker/docker_in_docker/) — configuración del runner y del job para construir imágenes, incluido TLS.

---

*En resumen: GitLab CI/CD es el motor de pipelines nativo de GitLab: un único `.gitlab-ci.yml` describe stages y jobs que corren en contenedores, y `rules`, `needs` y `artifacts` son las tres piezas que más se tocan.*
