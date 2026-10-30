# Docker en CI/CD

## ¿Qué es?

En un pipeline de CI/CD, Docker cumple dos papeles: **entorno de ejecución** (los jobs corren dentro de una imagen con las versiones exactas de las herramientas) y **producto final** (el pipeline construye una imagen de la aplicación, la publica en un registro y el servidor la descarga y la arranca).

## ¿Por qué existe?

El clásico «en mi máquina funcionaba» ocurre porque cada equipo tiene versiones distintas de las herramientas, y el runner de CI es otro equipo más. Una imagen lleva dentro su propia versión exacta de todo, así que lo que se prueba en el pipeline es lo que se ejecuta en producción.

> Si nunca lo has usado: una imagen es una fiambrera que lleva la comida, los cubiertos y el plato. No depende de lo que haya en la cocina de destino.

Para qué es Docker en sí (imágenes, contenedores, `Dockerfile`) está en la guía de [Docker](../docker/Docker.md); aquí se trata solo de cómo encaja en un pipeline.

## ¿Cuándo y para qué se usa?

Con la tienda online de ejemplo, cada servicio (`pedidos`, `pagos`, `inventario`, `emails`) tiene su `Dockerfile`. En cada fusión a `main`, el pipeline:

1. Ejecuta los tests.
2. Construye la imagen `ghcr.io/tienda/pedidos` y la etiqueta con el SHA del commit.
3. La sube a un registro.
4. Ordena al VPS (`203.0.113.10`, usuario `deployer`) descargarla y reiniciar el servicio.

El mismo `Dockerfile` sirve en local, en CI y en producción; esa es la reproducibilidad que se busca.

## Docker como entorno de ejecución del job

La forma más simple: el job corre dentro de un contenedor con la imagen que se elija.

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    container: node:20.11     # todos los steps corren dentro de esta imagen
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm test
```

En GitLab CI es `image: node:20.11` a nivel de job. Qué hace: en vez de depender de lo que traiga el runner, los pasos usan la versión exacta de Node de la imagen.

Para tests de integración que necesitan una base de datos, los **service containers** levantan contenedores auxiliares junto al job:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: ci-only
        options: >-
          --health-cmd pg_isready --health-interval 5s --health-retries 10
        ports:
          - 5432:5432
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm test
        env:
          DATABASE_URL: postgres://postgres:ci-only@localhost:5432/postgres
```

El `health-cmd` hace que los steps no arranquen hasta que Postgres responde. Para entornos completos por rama, ver [Entornos efímeros en CI](Entornos-Efimeros-en-CI.md).

## Construir y publicar la imagen

El `Dockerfile` del servicio `pedidos`:

```dockerfile
FROM node:20.11 AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20.11-slim
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
CMD ["node", "dist/main.js"]
```

Y el job que la construye y publica en GitHub Container Registry:

```yaml
  publish:
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write           # necesario para subir a ghcr.io
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ghcr.io/tienda/pedidos:${{ github.sha }}
            ghcr.io/tienda/pedidos:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

Qué hace: inicia sesión en el registro con el token que GitHub genera para cada ejecución (no hay que crear secretos), construye la imagen y la sube con dos etiquetas. `cache-from`/`cache-to` guardan las capas en la caché de Actions para que el siguiente build las reutilice. Más sobre el registro en [GitHub Container Registry](../docker/GitHub-Container-Registry.md) y, para registros propios, [Registros de imágenes privados](../despliegue-en-vps/Registros-de-Imagenes-Privados.md).

## Desplegar: el servidor descarga la imagen

Con la imagen ya en el registro, el despliegue deja de instalar nada en el servidor:

```bash
ssh deployer@203.0.113.10 \
  "cd /srv/tienda && IMAGE_TAG=<sha> docker compose pull pedidos && docker compose up -d pedidos"
```

Cómo está montado Compose en el VPS se explica en [Docker en un VPS](../despliegue-en-vps/Docker-en-un-VPS.md); las variantes sin corte, en [Estrategias de despliegue](Estrategias-de-Despliegue.md).

## Cómo etiquetar las imágenes

| Etiqueta | Cuándo | Riesgo |
|---|---|---|
| SHA del commit (`:3f9a1c2`) | Siempre, es la identidad real | Ninguno: inmutable y trazable |
| Versión (`:1.4.0`) | En releases por etiqueta (ver [Release por tag](Release-por-Tag.md)) | Si se sobrescribe, deja de ser inmutable |
| Rama (`:main`) | Para el entorno de pruebas | Cambia con cada merge |
| `:latest` | Solo como comodidad | No indica qué versión corre ni permite volver atrás |

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `denied: permission_denied: write_package` al hacer push | Falta `permissions: packages: write` en el job, o el paquete pertenece a otra cuenta |
| `Error: Cannot perform an interactive login from a non TTY device` | `docker login` sin contraseña por stdin (usar `docker/login-action`) |
| `manifest unknown: manifest unknown` al hacer `pull` en el VPS | La etiqueta no existe en el registro: el push falló o se usa otra etiqueta |
| `Cannot connect to the Docker daemon at unix:///var/run/docker.sock` | El job corre dentro de un contenedor sin acceso al daemon, o el servicio no está arrancado |
| `toomanyrequests: You have reached your pull rate limit` | Límite de descargas anónimas de Docker Hub; autenticarse o usar un registro espejo |
| La build tarda 6 minutos aunque solo cambió una línea | `COPY . .` antes de instalar dependencias: la caché de capas se invalida siempre |
| `failed to solve: process "/bin/sh -c npm ci" did not complete successfully: exit code: 1` | El error real está unas líneas más arriba, en la salida de `npm` |

## Cuándo no usar Docker en el pipeline

- Proyecto sin despliegue en contenedores y con una sola versión de herramienta: el runner nativo basta y arranca antes.
- Tareas muy cortas (un linter de 5 segundos): descargar una imagen de cientos de MB cuesta más que la tarea.
- Orquestar muchos contenedores en producción no es trabajo de Docker ni del pipeline, sino de una herramienta como Kubernetes.

## Buenas prácticas avanzadas

- **Copia el lockfile antes que el código.** Docker cachea cada instrucción por capas, y un `COPY . .` temprano invalida la caché con cualquier cambio, reinstalando todo en cada build. Primero el manifiesto, luego la instalación, luego el resto: `COPY package*.json ./` → `RUN npm ci` → `COPY . .`.
- **Multi-stage: que el SDK no viaje a producción.** Se compila en una etapa con todas las herramientas y se copia solo el resultado a una imagen final mínima (`node:20.11-slim`). La imagen pesa una fracción y no lleva compiladores que amplíen la superficie de ataque.
- **`latest` no es una versión.** Publicar cada imagen con un tag inmutable (SHA o versión) permite saber qué corre y volver atrás con precisión. Para imágenes base críticas, anclar por *digest* (`node:20.11@sha256:...`) es lo único que garantiza bytes idénticos.
- **Compila la imagen una vez y promociónala.** La imagen que pasó las pruebas es la que se despliega en producción; se le cambia la etiqueta, no se reconstruye.
- **Minimiza permisos del token del job.** Declara `permissions:` explícito: `packages: write` solo en el job que publica, no en todos.

## Documentación oficial

- [Docker Build GitHub Actions](https://docs.docker.com/build/ci/github-actions/) — las acciones oficiales (`setup-buildx`, `login`, `build-push`) y un workflow de partida; ir ahí para etiquetas automáticas, multi-plataforma y caché.
- [Docker Build Cache](https://docs.docker.com/build/cache/) — cómo funciona la invalidación de capas y los backends de caché; imprescindible si las builds son lentas.

---

*En resumen: Docker da al pipeline un entorno idéntico de principio a fin — el job corre en una imagen conocida y el producto sale como otra imagen que se publica una vez y se despliega tal cual.*
