# Entornos efímeros en CI

## ¿Qué es?

Un *entorno efímero* es una copia completa de la aplicación (servicios, base de datos, todo lo necesario para probarla) que el pipeline **levanta desde cero, usa y destruye al terminar**. Normalmente vive en contenedores Docker dentro del propio runner de CI. No existe antes de la prueba ni después.

## ¿Por qué existe?

La forma clásica de probar «la aplicación entera» es mantener un servidor de TEST siempre encendido, donde se despliega antes que a producción. Tiene costes ocultos: hay que mantenerlo y pagarlo, y con el tiempo se convierte en un blanco móvil con datos viejos, versiones a medias y una configuración que ya no coincide con producción. Los tests fallan por culpa del entorno, no del código.

El entorno efímero elimina el problema de raíz: si cada ejecución construye su propio mundo limpio, no hay nada que se desactualice ni estado de una ejecución que contamine la siguiente.

> Es la diferencia entre ensayar en un teatro compartido (donde el decorado queda como lo dejó el último grupo) y montar un decorado nuevo cada vez, idéntico al del estreno.

## ¿Cuándo y para qué se usa?

Tres escenarios, de menor a mayor tamaño:

- **Tests de integración con una base de datos real.** En lugar de un servidor de BD compartido, el job arranca un PostgreSQL de usar y tirar contra el que prueba la API de `pedidos`.
- **Tests E2E sin entorno desplegado.** El pipeline levanta los cuatro servicios de la tienda (`pedidos`, `pagos`, `inventario`, `emails`) con Docker Compose en el runner y lanza una suite que crea el pedido #4711 de punta a punta.
- **Entornos de preview por PR.** Cada PR obtiene una URL propia para revisarla a mano, y desaparece al cerrarse.

Cada uno resuelve un nivel distinto; las secciones siguientes los recorren en ese orden.

## Service containers: la base de datos del job

Un *service container* es un contenedor que GitHub Actions arranca junto al job, antes de que empiece, y destruye al acabar. Se declara con `services:` y cubre el caso más habitual: un PostgreSQL, un Redis o un RabbitMQ para los tests de integración.

```yaml
jobs:
  integracion:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16.3          # la misma versión que producción
        env:
          POSTGRES_PASSWORD: test
          POSTGRES_DB: pedidos
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U postgres"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 10
    steps:
      - uses: actions/checkout@v4
      - run: ./run-integration-tests.sh
        env:
          DB_HOST: localhost
          DB_PORT: 5432
          DB_PASSWORD: test
```

Qué hace: antes del primer paso, Actions arranca `postgres:16.3` y espera a que su *health check* pase; los pasos ven la base de datos en `localhost:5432`. Al terminar el job, el contenedor desaparece con todos sus datos.

La dirección de conexión depende de dónde corre el job:

| El job corre... | Se conecta a... | `ports:` |
|---|---|---|
| Directamente en el runner (lo habitual) | `localhost` y el puerto mapeado | Necesario |
| Dentro de un contenedor (`container:`) | El nombre del servicio (`postgres`) | No hace falta |

Sin `options` de health check, el primer paso puede ejecutarse mientras PostgreSQL aún arranca, y los tests fallan de forma intermitente. Para una base efímera lanzada desde el propio código de test, en lugar de desde el YAML, está [Testcontainers](../docker/Testcontainers.md).

## Docker Compose en CI: la aplicación completa

Cuando hay que probar varios servicios hablando entre sí, el mismo `compose.yml` que usa el equipo en local se levanta en el runner.

```yaml
jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Levantar la tienda
        run: docker compose -f compose.yml -f compose.ci.yml up -d --build --wait --wait-timeout 120
      - name: Ejecutar E2E
        run: npx playwright test
        env:
          BASE_URL: http://localhost:8080
      - name: Logs si algo falló
        if: failure()
        run: docker compose logs --timestamps
      - name: Destruir
        if: always()
        run: docker compose down -v
```

Qué hace cada pieza:

- `--wait` hace que `up` espere a que los servicios estén *running* o *healthy* (y fuerza el modo detached). Evita el `wait-on` manual, siempre que los servicios definan `healthcheck` en el compose.
- `--wait-timeout 120` aborta tras 120 segundos si no llegan a estar sanos, en vez de colgarse hasta el límite del job.
- Un segundo fichero (`compose.ci.yml`) sobrescribe lo propio de CI: puertos, imágenes de dependencias externas sustituidas por *mocks*, variables de prueba.
- El paso de logs lleva `if: failure()` y va **antes** del `down`; el de `down -v` lleva `if: always()` para que el entorno se destruya aunque fallen los tests.

Un `compose.ci.yml` típico sustituye lo que no tiene sentido levantar en CI:

```yaml
# compose.ci.yml
services:
  pagos:
    environment:
      PASARELA_URL: http://pasarela-mock:9000   # nunca la pasarela real
  pasarela-mock:
    image: mockserver/mockserver:5.15.0
  emails:
    environment:
      SMTP_HOST: mailpit
  mailpit:
    image: axllent/mailpit:v1.20
```

El servicio `pagos` habla con una pasarela simulada y `emails` envía a un buzón de captura; ningún test cobra una tarjeta ni escribe a un cliente real.

## Datos de prueba: partir siempre de estado cero

El entorno nace vacío, así que cada ejecución **siembra sus propios datos** antes de probar: aplica las migraciones y luego crea lo que necesita. Un test que dependa de que «ya existe el cliente 42» de una ejecución anterior es un test roto en un entorno efímero.

```yaml
- run: docker compose exec -T pedidos ./migrar-bd.sh
- run: docker compose exec -T pedidos ./sembrar-datos.sh --perfil e2e
```

Reglas prácticas para los datos:

- Siembra con un conjunto **pequeño y determinista** (un catálogo de diez productos, un cliente, el pedido #4711 de ejemplo) y no con un volcado de producción: es más rápido, repetible y no arrastra datos personales.
- Cada test crea lo que necesita con identificadores propios; no asume el orden de ejecución.
- Si necesitas volumen para probar rendimiento, genéralo con un script, no copies producción.

## Entornos de preview por PR

Un *preview environment* despliega la PR en una infraestructura real y le da una URL propia (`pr-123.tienda.ejemplo.com`) para que quien revisa la pruebe en el navegador. A diferencia de lo anterior, **no vive dentro del runner**: sobrevive al job y hay que limpiarlo explícitamente.

Un esquema posible sobre el VPS de la tienda (`203.0.113.10`), con un proyecto Compose por PR:

```yaml
name: preview
on:
  pull_request:
    types: [opened, synchronize, reopened, closed]

concurrency:
  group: preview-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  desplegar:
    if: github.event.action != 'closed'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Desplegar preview
        run: |
          ssh deployer@203.0.113.10 \
            "PR=${{ github.event.pull_request.number }} ./preview-up.sh"

  limpiar:
    if: github.event.action == 'closed'
    runs-on: ubuntu-latest
    steps:
      - name: Destruir preview
        run: |
          ssh deployer@203.0.113.10 \
            "PR=${{ github.event.pull_request.number }} ./preview-down.sh"
```

Qué hace: por defecto un workflow de `pull_request` solo reacciona a `opened`, `synchronize` y `reopened`; añadir `closed` es lo que permite limpiar al cerrar o fusionar la PR. `concurrency` con grupo por número de PR cancela el despliegue anterior si llega un push nuevo mientras sigue en marcha. El script `preview-down.sh` hace `docker compose -p pr-123 down -v` y borra el registro DNS o la regla del proxy. La configuración de acceso por SSH y secretos queda en [Secrets y variables](Secrets-y-Variables.md); el modelo de despliegue al VPS, en [Docker en un VPS](../despliegue-en-vps/Docker-en-un-VPS.md).

Si solo se quiere ejecutar la limpieza tras una fusión (no al cerrar sin fusionar), se añade al job `if: github.event.pull_request.merged == true`.

Los previews tienen una limitación de seguridad: los workflows de PRs desde *forks* no reciben secrets. Un preview para colaboradores externos exige otro diseño (o aprobación manual) y no debe resolverse relajando esa protección.

## Costes y tiempos

Un entorno efímero cuesta minutos de runner en cada ejecución; en repositorios privados se facturan, y en públicos los runners estándar de GitHub son gratuitos. Las palancas para controlarlo:

| Palanca | Efecto |
|---|---|
| Ejecutar E2E solo en PR hacia `main`, no en cada push de rama | Menos ejecuciones |
| [Path filters](Monorepo-y-Path-Filters.md) | No levantar la tienda entera para un cambio en documentación |
| `concurrency` con `cancel-in-progress` | Un push nuevo cancela el run obsoleto |
| Caché de capas de imagen | Menos tiempo de `--build` |
| Previews con caducidad o limpieza programada | Evita que se acumulen entornos olvidados |
| Un set pequeño de datos y servicios | Arranque más rápido |

El coste más peligroso no es el de los minutos, sino el de los previews que nadie destruye: contenedores y volúmenes que se acumulan en el VPS hasta llenar el disco. Una tarea programada que borre proyectos `pr-*` con más de unos días de antigüedad es el cinturón de seguridad.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `connection refused` a `localhost:5432` en la primera prueba | El service container aún arranca; faltan las `options` de health check |
| `could not translate host name "postgres" to address` | El job corre en el runner, no en un contenedor: usar `localhost`, no el nombre del servicio |
| `bind: address already in use` al hacer `up` | Un puerto fijo choca con otro servicio del runner o con el propio service container |
| El E2E falla en CI pero pasa en local, con `latest` en las imágenes | La imagen `latest` cambió de versión mayor; fijar la misma versión que producción |
| `docker compose up --wait` termina con `container ... is unhealthy` | Falta o es demasiado estricto el `healthcheck` del servicio; revisar los logs con `docker compose logs` |
| El E2E rojo no deja pistas | El entorno se destruyó sin guardar logs; añadir un paso `if: failure()` previo al `down` |
| Los previews no desaparecen al cerrar la PR | El workflow no incluye `closed` en `types` |
| El disco del VPS se llena | Previews huérfanos (workflow fallido, cierre sin limpieza) |

## Cuándo no usar entornos efímeros

- Para probar la infraestructura real (nginx, DNS, certificados, límites del VPS): solo la cubre un *smoke test* tras el despliegue real. Véase [Estrategias de despliegue](Estrategias-de-Despliegue.md).
- Para probar migraciones sobre volúmenes reales de producción: los datos sembrados no reproducen el tamaño ni las rarezas reales.
- Si la suite completa tarda tanto que el equipo deja de esperarla: dividir en un conjunto rápido por PR y uno completo nocturno antes de seguir levantando más entornos.

## Buenas prácticas avanzadas

- **Fija las versiones a las de producción, hasta el parche.** Si producción corre `postgres:16.3`, el contenedor de test es `postgres:16.3`. Con `latest`, el día que la imagen salta de versión mayor se valida una base de datos que no es la tuya, y el fallo aparece «sin que nadie haya cambiado nada».
- **Vuelca los logs antes de destruir, no después.** El error real de un E2E suele estar en los logs de la API o de la BD, que desaparecen con el entorno. Un paso `if: failure()` con `docker compose logs --timestamps` (o la subida como artefacto) va siempre antes del `down`.
- **Usa `if: always()` en el `down`.** Sin esa condición, un test que falla salta el paso de limpieza; en un runner de GitHub no importa (la máquina se descarta), pero en un VPS o un runner propio el entorno queda vivo.
- **Trae la caché de fuera.** El runner nace vacío y `up --build` reconstruye todas las capas. Apunta la caché al registro (`--cache-from`) o a la caché de la plataforma para reconstruir solo lo que cambió.
- **Nunca apuntes un entorno efímero a servicios externos reales.** Una pasarela de pago, un proveedor de emails o una cola compartida deben estar simulados: el día que un test de CI envíe correos reales a clientes, el entorno efímero deja de ser inocuo.

## Documentación oficial

- [Servicios en contenedores de GitHub Actions](https://docs.github.com/en/actions/using-containerized-services/creating-postgresql-service-containers) — el ejemplo oficial de PostgreSQL con health check y la explicación de `localhost` frente al nombre del servicio.
- [`docker compose up`](https://docs.docker.com/reference/cli/docker/compose/up/) — referencia de `--wait`, `--wait-timeout` y `--build`.
- [Eventos que disparan workflows](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows) — la sección de `pull_request` con los tipos de actividad por defecto y el uso de `closed` para limpieza.
- [Uso de concurrencia](https://docs.github.com/en/actions/using-jobs/using-concurrency) — grupos y `cancel-in-progress` para no acumular ejecuciones obsoletas.

---

*En resumen: un entorno efímero cambia «mantener un servidor de pruebas siempre a medio morir» por «construir un mundo limpio, probarlo y tirarlo»; la reproducibilidad se consigue sin dejar nada vivo entre ejecuciones, y los previews exigen además limpiar explícitamente lo que crean.*
