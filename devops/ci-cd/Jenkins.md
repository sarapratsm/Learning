# Jenkins

## ¿Qué es?

Jenkins es un servidor de automatización de código abierto que se instala y se administra en una máquina propia. Ejecuta pipelines descritos en un fichero `Jenkinsfile` (con una sintaxis propia basada en Groovy), reparte el trabajo entre máquinas llamadas *agentes* y se amplía con un catálogo de miles de *plugins*.

## ¿Por qué existe?

Jenkins es anterior a las plataformas con CI integrado. Nació cuando el código vivía en repositorios muy dispares y hacía falta algo independiente que los vigilara, compilara y desplegara. Por eso toma el enfoque contrario a GitHub Actions o GitLab CI: no pertenece a ninguna plataforma, se conecta a cualquier repositorio y corre donde se quiera, a cambio de que alguien lo instale, lo actualice y lo proteja.

Ese control es lo que lo mantiene vivo: ejecución dentro de una red privada sin salida a internet, hardware especial, integración con herramientas muy antiguas o muy específicas (hay un plugin para casi todo), o simplemente una empresa que ya lo tiene funcionando desde hace años.

> Si conoces GitHub Actions: Jenkins es "el CI/CD que no depende de ninguna plataforma: pones el servidor y decides todo, pero también lo mantienes". Un `Jenkinsfile` hace el papel de un workflow; un *agente*, el de un runner; un *plugin*, el de una action.

## ¿Cuándo y para qué se usa?

En organizaciones que necesitan ejecutar CI/CD en infraestructura propia, por seguridad, normativa o porque ya la tienen. En la tienda online de ejemplo (`pedidos`, `pagos`, `inventario`, `emails`):

- Construir en servidores internos y desplegar en el VPS `203.0.113.10` sin que el código salga a una nube pública.
- Un pipeline que mezcla compilación en Windows y en Linux con herramientas que solo existen en una de las dos.
- Mantener pipelines ya existentes que nadie quiere migrar.

Cuándo elegir otra herramienta: ver [Cuándo no usarla](#cuándo-no-usarla).

## Vocabulario

| Término | Qué es |
|---|---|
| *Controller* | El servidor Jenkins: interfaz web, configuración, planificación. Antes se llamaba *master*. |
| *Agent* / *node* | Máquina (o contenedor) que ejecuta el trabajo. Se conecta al controller. |
| *Executor* | "Ranura" de ejecución de un nodo: un nodo con 2 executors corre 2 builds a la vez. |
| *Pipeline* | La definición del proceso, en un `Jenkinsfile`. Existen la sintaxis *declarativa* (`pipeline { }`, la recomendada) y la *scripted* (Groovy libre). |
| *Stage* | Fase con nombre dentro del pipeline; se muestra como columna en la vista de ejecución. |
| *Step* | Una instrucción dentro de un stage (`sh`, `echo`, `archiveArtifacts`...). |
| *Plugin* | Extensión instalable que añade steps, tipos de credencial, integraciones. |
| *Credentials* | Almacén de secretos del controller, referenciados por un identificador. |
| *Multibranch pipeline* | Tipo de job que busca ramas (y PRs) con `Jenkinsfile` y crea un pipeline por cada una. |
| *Workspace* | Directorio del agente donde se descarga el código y se trabaja. |

## Puesta en marcha

Jenkins necesita Java (las versiones actuales exigen Java 21 o superior, según el registro de cambios de la LTS comprobado el 2026-10-30). La forma más rápida de tener uno para probar es el contenedor oficial:

```bash
docker run -d -v jenkins_home:/var/jenkins_home -p 8080:8080 -p 50000:50000 \
  --restart=on-failure jenkins/jenkins:lts-jdk21
docker exec <contenedor> cat /var/jenkins_home/secrets/initialAdminPassword
```

- El puerto `8080` es la interfaz web; el `50000`, el canal por el que se conectan los agentes remotos.
- El volumen `jenkins_home` guarda toda la configuración, los jobs y las credenciales: perderlo es perder Jenkins.
- La segunda orden muestra la contraseña inicial que pide el asistente de `http://localhost:8080`. El asistente ofrece instalar los *plugins sugeridos* (incluye los de Git y Pipeline).

Para este pipeline hacen falta además los plugins **Docker Pipeline** y **SSH Agent** (o usar `withCredentials`, que viene con *Credentials Binding*), instalables en *Manage Jenkins → Plugins*. En producción conviene fijar la etiqueta a una versión concreta, en lugar de `lts-jdk21`, para que un reinicio no actualice sin avisar.

## Primer pipeline completo: de `push` a producción

Un `Jenkinsfile` en la raíz del repositorio con cuatro fases: compilar y probar, construir la imagen, aprobar y desplegar.

### 1. Compilar y probar

```groovy
pipeline {
    agent none

    options {
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    stages {
        stage('Build y test') {
            agent {
                docker { image 'mcr.microsoft.com/dotnet/sdk:10.0' }
            }
            environment {
                HOME = "${WORKSPACE}"          // dotnet necesita un HOME escribible
                NUGET_PACKAGES = "${WORKSPACE}/.nuget"
            }
            steps {
                sh 'dotnet build --configuration Release'
                sh 'dotnet test --configuration Release --no-build --logger trx --results-directory TestResults'
            }
            post {
                always {
                    archiveArtifacts artifacts: 'TestResults/**', allowEmptyArchive: true
                }
            }
        }
    }
}
```

- `agent none` a nivel superior indica que cada stage elige su propio agente.
- `agent { docker { image ... } }` arranca un contenedor con el SDK en un agente que tenga Docker y ejecuta el stage dentro (requiere el plugin Docker Pipeline).
- `options` fija un límite de tiempo, impide dos builds simultáneos del mismo job y conserva solo los últimos 20.
- `post { always { ... } }` se ejecuta al terminar el stage, pase lo que pase: aquí guarda los informes de tests.
- Si un `sh` devuelve un código distinto de 0, el stage falla y el pipeline se detiene.

### 2. Construir y publicar la imagen

```groovy
        stage('Imagen') {
            agent { label 'docker' }
            when { branch 'main' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'registro-imagenes',
                                                  usernameVariable: 'REG_USR',
                                                  passwordVariable: 'REG_PSW')]) {
                    sh '''
                        echo "$REG_PSW" | docker login registry.ejemplo.com -u "$REG_USR" --password-stdin
                        docker build -t registry.ejemplo.com/tienda/pedidos:$GIT_COMMIT ./pedidos
                        docker push registry.ejemplo.com/tienda/pedidos:$GIT_COMMIT
                    '''
                }
            }
        }
```

- `agent { label 'docker' }` elige un agente etiquetado como `docker`, es decir, uno que tiene Docker instalado y permiso para usarlo.
- `when { branch 'main' }` omite el stage en el resto de ramas (solo funciona en un *multibranch pipeline*, que es lo recomendable).
- `withCredentials` carga el usuario y la contraseña del almacén de credenciales (identificador `registro-imagenes`) en variables que solo existen dentro del bloque y se enmascaran en el log.
- Las comillas son **simples** (`'''`): el shell sustituye las variables. Con comillas dobles las sustituye Groovy y el secreto acaba en el log. Es la regla que más se rompe con Jenkins.
- `GIT_COMMIT` la define Jenkins al hacer el checkout.

Para las alternativas de construcción y el almacenamiento en caché de capas, véase [Docker en CI/CD](Docker-en-CI-CD.md).

### 3. Aprobar y desplegar

```groovy
        stage('Aprobación') {
            agent none
            when { branch 'main' }
            steps {
                input message: '¿Desplegar pedidos en producción?', ok: 'Desplegar'
            }
        }
        stage('Producción') {
            agent { label 'docker' }
            when { branch 'main' }
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'deployer-ssh',
                                                   keyFileVariable: 'SSH_KEY')]) {
                    sh '''
                        ssh -i "$SSH_KEY" deployer@203.0.113.10 \
                          "cd /srv/tienda && docker compose pull pedidos && docker compose up -d pedidos"
                    '''
                }
            }
        }
    }
}
```

- `input` pausa el pipeline hasta que alguien con permiso pulse *Desplegar* en la interfaz (el equivalente de un `environment` con aprobación en Actions o de `when: manual` en GitLab). Está en un stage con `agent none` para no ocupar un executor mientras alguien decide.
- `sshUserPrivateKey` guarda la clave en un fichero temporal y pone su ruta en `SSH_KEY`.
- La huella del servidor debe estar en el `known_hosts` del usuario del agente; si no, `ssh` se niega a continuar (ver errores frecuentes).
- El servidor ha de haber hecho `docker login` previamente con un token de solo lectura.

Para saber cómo guardar los secretos y rotarlos: [Secrets y variables](Secrets-y-Variables.md). Para qué hacer cuando el despliegue sale mal o se quiere desplegar sin cortes: [Estrategias de despliegue](Estrategias-de-Despliegue.md).

### 4. Conectar el repositorio

El pipeline no se ejecuta solo al subir el fichero. Se crea un job **Multibranch Pipeline** en Jenkins apuntando al repositorio; Jenkins busca ramas con `Jenkinsfile` y crea un pipeline para cada una. Para que arranque al hacer `push` hay dos caminos:

- **Webhook**: el repositorio avisa a Jenkins (con el plugin de la plataforma: *GitHub Branch Source* o *GitLab Branch Source*). Es inmediato y no consume sondeos.
- **Sondeo**: Jenkins pregunta cada cierto tiempo (`triggers { pollSCM('H/5 * * * *') }` en un pipeline sencillo, o *Periodically if not otherwise run* en el multibranch). Funciona sin exponer Jenkins a internet, pero con retraso.

Dentro del pipeline, `env.BRANCH_NAME` contiene la rama y `env.CHANGE_ID` el número de la PR (solo definida en builds de PR).

## Disparadores

```groovy
triggers {
    cron('H 3 * * *')           // cada día, a una hora cualquiera entre las 03:00 y las 03:59
    pollSCM('H/5 * * * *')      // consulta cambios cada ~5 minutos
}
```

`H` reparte la carga: Jenkins elige un minuto estable pero distinto para cada job, en lugar de lanzar todos a la vez a las 03:00. Los *upstream triggers* encadenan un job a otro, y los webhooks son el mecanismo habitual para el `push`. Disparar solo cuando cambia una carpeta (monorepo): [Monorepo y path filters](Monorepo-y-Path-Filters.md). Publicar al crear un tag: [Release por tag](Release-por-Tag.md).

## Stages, paralelismo y artefactos

Dentro de un stage se pueden ejecutar ramas en paralelo:

```groovy
stage('Pruebas') {
    parallel {
        stage('Unitarias') { steps { sh 'dotnet test pedidos.Tests' } }
        stage('Integración') { steps { sh 'dotnet test pedidos.IntegrationTests' } }
    }
}
```

Para pasar ficheros entre stages que corren en agentes distintos se usan `stash`/`unstash` (temporal, dentro del mismo build) o `archiveArtifacts` (permanente, descargable desde la web):

```groovy
stash name: 'publish', includes: 'publish/**'
// ... en otro stage, otro agente:
unstash 'publish'
```

El espacio de trabajo **no se comparte** entre agentes: lo que un agente deja en disco no está en el otro. Dentro de un mismo agente, los stages comparten el workspace.

## Cachés

Jenkins no trae un mecanismo de caché declarativo. Las opciones reales:

- **Workspace persistente en un agente fijo**: la carpeta `.nuget` o `node_modules` sobrevive entre builds. Es lo más rápido, pero ata el build a esa máquina y arrastra residuos.
- **Volumen Docker montado** en el contenedor del agente: `docker { image '...'; args '-v nuget-cache:/root/.nuget' }`.
- **Plugin de caché** (*Job Cacher*): guarda y restaura rutas con una clave, parecido a `actions/cache`. Es otro plugin que mantener.

## Matrices

El bloque `matrix` (con `axes` y `excludes`) repite un stage con las combinaciones de valores:

```groovy
stage('Imágenes') {
    matrix {
        axes {
            axis { name 'SERVICIO'; values 'pedidos', 'pagos', 'inventario', 'emails' }
        }
        stages {
            stage('Construir') {
                steps { sh 'docker build -t tienda-$SERVICIO ./$SERVICIO' }
            }
        }
    }
}
```

Genera cuatro ejecuciones en paralelo, con `SERVICIO` como variable de entorno en cada una.

## Agentes

El controller coordina; los agentes trabajan. Un agente se conecta al controller por SSH (el controller entra) o por JNLP/WebSocket (el agente llama), y se identifica con *labels* que los stages piden con `agent { label 'docker && linux' }`.

| Tipo de agente | Cuándo |
|---|---|
| Permanente (una VM o servidor) | Pocos builds, herramientas ya instaladas |
| Contenedor efímero (`agent { docker { ... } }`) | Una imagen por stage; entorno limpio y reproducible |
| Agentes dinámicos (plugin de Kubernetes o de nube) | Muchos builds en pico; se crean y destruyen bajo demanda |

El controller tiene que estar configurado con 0 *executors*: si ejecuta builds, cualquier pipeline lee los ficheros y credenciales del propio Jenkins.

## Condiciones

`when` decide si un stage corre. Varias condiciones al mismo nivel se combinan con AND; `anyOf` y `not` cubren el resto:

```groovy
when {
    allOf {
        branch 'main'
        not { changeRequest() }
    }
}
```

| Condición | Se cumple si |
|---|---|
| `branch 'main'` | La rama del build es `main` (multibranch) |
| `buildingTag()` | El build es de un tag |
| `tag 'v*'` | El tag coincide con el patrón |
| `changeRequest()` | El build es de una PR |
| `changeset 'pedidos/**'` | Cambió algún fichero de esa ruta |
| `expression { env.DEPLOY == 'true' }` | Una expresión Groovy es verdadera |
| `environment name: 'X', value: 'Y'` | Una variable tiene ese valor |

## Reutilización

- **Shared libraries**: código Groovy versionado en un repositorio propio que varios `Jenkinsfile` importan con `@Library('ci-comun') _`. Permite definir steps propios (`desplegarServicio(nombre: 'pedidos')`) y es el equivalente a los *reusable workflows* de Actions y a los `include` de GitLab.
- *Configuration as Code*: sirve para repetir la configuración del **servidor**, no la del pipeline.

## Credenciales

El almacén (*Manage Jenkins → Credentials*) guarda secretos con un identificador y un ámbito. Los tipos habituales: *Secret text*, *Username with password*, *SSH Username with private key*, *Secret file*. En el `Jenkinsfile` se usan por su identificador:

```groovy
environment {
    API_TOKEN = credentials('token-avisos')       // Secret text
}
```

Con `credentials()` en `environment`, un secret de texto queda en la variable y uno de usuario y contraseña genera además `VAR_USR` y `VAR_PSW`. Siempre con comillas simples en `sh`: así el valor lo resuelve el shell del agente y no se interpola en Groovy.

## Errores frecuentes

| Síntoma (mensaje real) | Causa | Solución |
|---|---|---|
| `permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock` | El usuario del agente no está en el grupo `docker` | Añadirlo al grupo y reiniciar el agente |
| `WorkflowScript: 5: Expected a step @ line 5, column 9.` | Una instrucción Groovy suelta en bloque declarativo | Meterla en `script { ... }` o usar un step |
| `org.jenkinsci.plugins.workflow.steps.MissingContextVariableException: Required context class hudson.FilePath is missing` | `sh` usado en un stage sin agente (con `agent none` global) | Poner `agent` en ese stage |
| `groovy.lang.MissingPropertyException: No such property: REG_PSW for class: groovy.lang.Binding` | Se usa la variable fuera del bloque `withCredentials` | Mover el uso dentro del bloque |
| `Host key verification failed.` al desplegar | El `known_hosts` del usuario del agente no tiene el servidor | Añadir la huella verificada en la máquina del agente |
| `ERROR: Couldn't find any revision to build. Verify the repository and branch configuration for this job.` | La rama no existe en el repositorio o el job apunta a otra | Corregir la rama o usar multibranch |
| `Scripts not permitted to use method ...` | El pipeline (Groovy en *sandbox*) llama a un método no aprobado | Aprobarlo en *Manage Jenkins → In-process Script Approval* tras revisarlo, o evitarlo |
| El pipeline queda en `Still waiting to schedule task` | Ningún agente tiene la etiqueta pedida o no hay executors libres | Revisar `label` y el estado de los nodos |
| El build tumba la interfaz web | Los builds corren en el controller | Poner sus executors a 0 y usar agentes |

## Cuándo no usarla

- El código está en GitHub o GitLab y no hay una razón para ejecutar en infraestructura propia: [GitHub Actions](GitHub-Actions.md) o [GitLab CI](GitLab-CI.md) evitan mantener un servidor.
- Nadie del equipo puede dedicarle tiempo a actualizar Jenkins y sus plugins: un Jenkins abandonado acumula vulnerabilidades, y está muy expuesto por tener credenciales de despliegue.
- Se quiere una configuración 100 % declarativa sin código: el Groovy del `Jenkinsfile` y las shared libraries invitan a lógica difícil de probar.

## Tabla de decisión

| Situación | Elección |
|---|---|
| Un pipeline para todo el repositorio | Declarativo con `Jenkinsfile` |
| Lógica compleja imposible de expresar declarativamente | Bloque `script { }` (con moderación) o shared library |
| Un pipeline por rama y por PR | *Multibranch pipeline* |
| Entorno de build limpio y reproducible | `agent { docker { ... } }` |
| Builds que requieren Windows | Agente con label `windows` |
| Muchos builds en pico | Agentes dinámicos (Kubernetes / nube) |
| Pasar ficheros entre agentes | `stash` / `unstash` |
| Aprobación manual | `input` |
| Reproducir el servidor tras un desastre | *Configuration as Code* |

## Equivalencia de vocabulario

| Jenkins | GitHub Actions | GitLab CI |
|---|---|---|
| Pipeline (`Jenkinsfile`) | Workflow (`.github/workflows/*.yml`) | Pipeline (`.gitlab-ci.yml`) |
| `triggers { }`, webhooks | `on:` | `rules:` / `workflow:` |
| Stage con `steps` | Job | Job |
| `sh '...'` | `run:` | `script:` |
| Agente (*agent*, *node*) | Runner | Runner |
| `agent { docker { image '...' } }` | `container:` | `image:` |
| `archiveArtifacts` / `stash` | `upload-artifact` | `artifacts:` |
| `matrix { axes { } }` | `strategy.matrix` | `parallel: matrix` |
| Shared library | *Reusable workflow* / action | `include` / `extends` |
| Credencial (*Credentials*) | Secret | Variable *masked* / *protected* |
| `input` | `environment` con aprobación | `when: manual` |
| Plugin | Action | Imagen o `include` |

Sus fichas hermanas: [GitHub Actions](GitHub-Actions.md) y [GitLab CI](GitLab-CI.md).

## Buenas prácticas avanzadas

- **Nada configurado a golpe de clic.** Un Jenkins montado desde la interfaz es irreproducible: si el servidor muere, nadie recuerda qué casillas estaban marcadas. Define los pipelines solo en el `Jenkinsfile` y la configuración del servidor con *Configuration as Code* (plugin JCasC), de modo que todo Jenkins se pueda reconstruir desde ficheros versionados.
- **El controller no ejecuta builds.** Sus *executors* a 0 y todo el trabajo en agentes. Si los builds corren en el controller, cualquier pipeline puede leer credenciales y ficheros del propio servidor, y un build pesado puede tumbar la interfaz para todo el equipo.
- **Cada plugin es una deuda, no un regalo.** Los plugins se actualizan a ritmos distintos y una actualización puede romper otro plugin o el propio servidor. Instala los mínimos imprescindibles, prueba las actualizaciones en una instancia de ensayo y suscríbete a los avisos de seguridad de Jenkins: la mayoría de incidentes vienen de plugins sin actualizar.
- **Comillas simples con secretos.** `sh "curl -H 'Authorization: $TOKEN' ..."` interpola en Groovy y el secreto viaja en claro por el log y por la línea de comandos del proceso; `sh 'curl -H "Authorization: $TOKEN" ...'` deja que lo resuelva el shell del agente. Jenkins avisa con `Warning: A secret was passed to "sh" using Groovy String interpolation, which is insecure`.
- **Fija versiones: imágenes, plugins y la propia LTS.** Seguir la línea LTS (no la semanal) y fijar los plugins en un `plugins.txt` hace que el servidor sea el mismo tras un reinicio o una reconstrucción. Con `jenkins/jenkins:lts` sin versión, un `docker pull` puede cambiar la versión mayor de Java o de la interfaz.
- **Usa `input` fuera de un agente.** Un `input` dentro de un `agent` mantiene el executor ocupado mientras alguien decide (horas, si es de noche); declara `agent none` en ese stage y reserva el agente después, como hace el pipeline de ejemplo.

## Documentación oficial

- [Pipeline (manual de Jenkins)](https://www.jenkins.io/doc/book/pipeline/) — la guía de referencia; empieza por *Using a Jenkinsfile* y *Pipeline Syntax*.
- [Sintaxis declarativa](https://www.jenkins.io/doc/book/pipeline/syntax/) — referencia de `agent`, `options`, `when`, `matrix`, `post`, `input` y `triggers`.
- [Multibranch pipelines](https://www.jenkins.io/doc/book/pipeline/multibranch/) — cómo se descubren ramas y PRs y qué variables define cada build.

---

*En resumen: Jenkins es el veterano del CI/CD: un servidor propio y extensible con plugins, cuyo `Jenkinsfile` describe stages que corren en agentes, y que da control total a cambio de que alguien lo instale, lo actualice y lo proteja.*
