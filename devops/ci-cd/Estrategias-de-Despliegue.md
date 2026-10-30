# Estrategias de despliegue

## ¿Qué es?

Una estrategia de despliegue es la forma concreta de sustituir la versión que corre en producción por una nueva: en qué orden se apagan unas instancias y se arrancan otras, cuánto tráfico recibe cada versión y cómo se vuelve atrás si algo falla. Las principales son *recreate*, *rolling*, *blue-green* y *canary*, y se complementan con *feature flags* y con migraciones de base de datos compatibles entre versiones.

## ¿Por qué existe?

La forma más simple de desplegar es apagar la aplicación, copiar la versión nueva y volver a encenderla. Durante ese rato la tienda no atiende pedidos, y si la versión nueva tiene un fallo, lo sufren todos los clientes a la vez. Las estrategias existen para dos cosas: **desplegar sin cortes** y **poder echarse atrás rápido**.

> Es cambiar las ruedas de un coche: lo ingenuo es pararlo en mitad de la carretera; lo bueno es cambiarlas sin que los pasajeros noten nada.

Ninguna estrategia es gratis. Cada una intercambia algo (infraestructura duplicada, complejidad, versiones conviviendo) por reducir el riesgo, y la elección depende de cuánto cuesta un fallo en ese servicio concreto.

## ¿Cuándo y para qué se usa?

Cada vez que se publica una versión nueva de un servicio. La tienda online de ejemplo (servicios `pedidos`, `pagos`, `inventario` y `emails`, en el VPS `203.0.113.10` bajo `tienda.ejemplo.com`) no necesita lo mismo en todos sus servicios: `emails` puede permitirse un reinicio de dos segundos porque los envíos se reintentan, mientras que un fallo de `pagos` en plena campaña cuesta ventas reales y justifica una estrategia más cuidadosa.

El paso de despliegue es una fase más del [pipeline](Pipeline.md), y [Release-por-Tag.md](Release-por-Tag.md) trata cómo se dispara con una etiqueta de versión. Esta ficha trata de lo que sucede en el servidor una vez disparado.

---

## Cómo elegir

| Estrategia | Corte de servicio | Versiones conviviendo | Infraestructura extra | Vuelta atrás | Úsala cuando |
|---|---|---|---|---|---|
| Recreate | Sí, breve | No | Ninguna | Redesplegar la anterior | Entorno interno, `emails`, ventana de mantenimiento aceptada |
| Rolling | No | Sí, un rato | Poca (una instancia extra) | Otro rolling hacia atrás | Varias réplicas y cambios compatibles; el caso por defecto |
| Blue-green | No | No (cada una por separado) | El doble de capacidad | Inmediata (cambio de enrutado) | Cambios arriesgados que se quieren probar antes de exponerlos |
| Canary | No | Sí, controlado por porcentaje | Poca, pero exige enrutado por peso y métricas | Retirar el canario | Servicio crítico con tráfico suficiente para medir |

Las **feature flags** no sustituyen a ninguna de estas filas: desacoplan *desplegar* (poner el código en producción) de *activar* (que los usuarios lo vean), y se combinan con cualquiera.

## Recreate: apagar y encender

Se detiene la versión vieja y se arranca la nueva. Es el comportamiento por defecto de Docker Compose cuando cambia la imagen:

```bash
cd /srv/tienda
IMAGE_TAG=1.5.0 docker compose pull emails
IMAGE_TAG=1.5.0 docker compose up -d emails
```

`docker compose up -d` detecta que la definición del servicio cambió, para el contenedor viejo y crea uno nuevo. Mientras tanto no hay nadie atendiendo. Kubernetes tiene el equivalente explícito:

```yaml
spec:
  strategy:
    type: Recreate   # termina todos los Pods antes de crear los nuevos
```

El coste es el corte; el beneficio es que nunca hay dos versiones a la vez. Esa segunda propiedad es la que hace a *recreate* la opción correcta cuando dos versiones no pueden coexistir (una migración destructiva, un worker que debe ser único).

## Rolling: de una en una

Con varias réplicas se actualiza una cada vez: se arranca una nueva, se espera a que esté lista, se retira una vieja, y se repite. Siempre hay réplicas atendiendo. Es la estrategia por defecto de un `Deployment` de Kubernetes:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pedidos
spec:
  replicas: 4
  minReadySeconds: 10
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1          # como mucho 1 Pod por encima de las 4 réplicas
      maxUnavailable: 0    # nunca menos de 4 Pods disponibles
  selector:
    matchLabels: { app: pedidos }
  template:
    metadata:
      labels: { app: pedidos }
    spec:
      containers:
        - name: pedidos
          image: ghcr.io/tienda/pedidos:1.5.0
          readinessProbe:
            httpGet: { path: /health, port: 8080 }
            periodSeconds: 5
```

- `maxSurge` es cuántos Pods puede haber por encima de `replicas` durante la actualización; `maxUnavailable`, cuántos pueden faltar. Por defecto valen un 25 % cada uno, y no pueden ser ambos cero.
- `readinessProbe` es lo que decide cuándo un Pod nuevo recibe tráfico. Sin ella, Kubernetes da por lista la réplica en cuanto arranca el proceso, aunque la aplicación aún no haya conectado con la base de datos, y el rolling reemplaza réplicas sanas por otras que fallan.
- `minReadySeconds` exige que el Pod lleve ese tiempo listo antes de contarlo como disponible, lo que atrapa a las que arrancan y se caen a los pocos segundos.

El seguimiento y la vuelta atrás se hacen con:

```bash
kubectl set image deployment/pedidos pedidos=ghcr.io/tienda/pedidos:1.5.0
kubectl rollout status deployment/pedidos   # termina con código != 0 si falla
kubectl rollout undo deployment/pedidos     # vuelve a la revisión anterior
```

Docker Compose en un VPS con una sola máquina **no ofrece rolling real**: `docker compose up -d` sigue la lógica de *recreate*. Existe el bloque `deploy.update_config` (`parallelism`, `delay`, `order: start-first`, `failure_action`) en la especificación de Compose, pensado para Docker Swarm; la documentación de la especificación no aclara si `docker compose up` lo respeta, así que conviene no apoyarse en él sin probarlo en la versión instalada. En un VPS, lo realista es blue-green con el proxy delante.

El coste del rolling es que **durante unos minutos conviven dos versiones** contra la misma base de datos, lo que obliga a los cambios compatibles hacia atrás (ver más abajo «Migraciones»).

## Blue-green: dos entornos y un interruptor

Se mantienen dos copias completas: la **azul** sirve a los clientes y la **verde** recibe la versión nueva. La verde se prueba con calma, sin tráfico real; cuando está lista, el proxy envía todo el tráfico a ella. La azul queda arrancada de reserva: volver atrás es mover el interruptor otra vez.

```text
antes:   clientes ──> proxy ──> [azul  1.4.2]    [verde 1.5.0 en pruebas]
después: clientes ──> proxy ──> [verde 1.5.0]    [azul  1.4.2 de reserva]
```

En un VPS con Docker Compose se implementa con dos servicios y un nginx que apunta a uno de ellos:

```yaml
# compose.yaml
services:
  proxy:
    image: nginx:1.27
    ports: ["80:80", "443:443"]
    volumes:
      - ./nginx/active-upstream.conf:/etc/nginx/conf.d/active-upstream.conf:ro
      - ./nginx/site.conf:/etc/nginx/conf.d/site.conf:ro

  pedidos-blue:
    image: ghcr.io/tienda/pedidos:${BLUE_TAG}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 5s
      retries: 5

  pedidos-green:
    image: ghcr.io/tienda/pedidos:${GREEN_TAG}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 5s
      retries: 5
```

```nginx
# nginx/active-upstream.conf  — apunta al color que sirve en producción
upstream pedidos_backend { server pedidos-blue:8080; }
```

```nginx
# nginx/site.conf
server {
  listen 80;
  server_name tienda.ejemplo.com;
  location /api/pedidos/ { proxy_pass http://pedidos_backend; }
}
```

El despliegue arranca el color inactivo, espera a que su `healthcheck` pase, comprueba que responde y cambia el enrutado:

```bash
GREEN_TAG=1.5.0 docker compose up -d --wait pedidos-green     # --wait: espera a "healthy"
docker compose exec proxy curl -fs http://pedidos-green:8080/health

echo 'upstream pedidos_backend { server pedidos-green:8080; }' > nginx/active-upstream.conf
docker compose exec proxy nginx -t && docker compose exec proxy nginx -s reload
```

`nginx -s reload` aplica la configuración nueva sin cortar las conexiones en curso: los workers viejos terminan sus peticiones mientras los nuevos ya apuntan al verde. Para volver atrás se deja `server pedidos-blue:8080;` y se recarga.

El coste es **duplicar la capacidad** y, sobre todo, que **la base de datos es una sola**: el azul y el verde comparten esquema. Blue-green protege contra un fallo del *código*; no protege contra una migración que rompa el esquema del que depende la versión vieja.

El proxy y la red entre contenedores se explican en [Reverse-Proxy-con-nginx-proxy.md](../despliegue-en-vps/Reverse-Proxy-con-nginx-proxy.md) y [Docker-en-un-VPS.md](../despliegue-en-vps/Docker-en-un-VPS.md).

## Canary: un porcentaje de tráfico

La versión nueva atiende solo a una fracción de los clientes (un 5 %, por ejemplo). Si las métricas se mantienen, se sube a 25 %, 50 % y 100 %; si empeoran, se retira y solo una minoría la ha sufrido.

> Viene de los canarios que los mineros bajaban a la mina: si el aire era malo, el pájaro lo notaba antes que las personas.

La implementación mínima es repartir por peso. Con nginx, un 10 % del tráfico va al canario:

```nginx
upstream pedidos_backend {
  server pedidos-stable:8080 weight=9;
  server pedidos-canary:8080 weight=1;
}
```

En Kubernetes, sin herramientas adicionales, se consigue con dos `Deployment` que comparten la etiqueta que selecciona el `Service`: el reparto sigue la proporción de réplicas. Con 9 réplicas estables y 1 canario, aproximadamente un 10 % de las peticiones llega al canario:

```yaml
# Service: selecciona por la etiqueta común
selector:
  app: pedidos        # la llevan pedidos-stable (9 réplicas) y pedidos-canary (1)
```

Ese reparto es por *petición*, no por usuario: la misma persona puede ver una versión y luego la otra. Si eso importa, hace falta afinidad por cookie o por cabecera, que ofrecen los *ingress controllers* y las mallas de servicios.

Un canario solo tiene sentido si **algo compara** sus errores y su latencia con los de la versión estable y decide si seguir. Hace falta tráfico suficiente para que la comparación sea estadísticamente útil: con pocas peticiones por minuto, un 5 % son demasiado pocas muestras.

## Feature flags: desplegar no es activar

Una *feature flag* es una condición en el código que enciende o apaga una funcionalidad sin desplegar. El código nuevo llega a producción **apagado**, y se activa después para un grupo, un porcentaje o todos.

```csharp
if (flags.IsEnabled("nuevo-calculo-de-envio", user))
    return nuevoCalculo.Calcular(pedido);   // pedido #4711 con el cálculo nuevo
return calculoActual.Calcular(pedido);
```

Esto separa dos decisiones que sin flags van juntas: *poner el código en producción* (riesgo técnico) y *exponerlo a los clientes* (riesgo de negocio). Si el cálculo nuevo falla, se apaga la flag en segundos, sin redesplegar ni hacer rollback.

El coste es la deuda: cada flag es una rama más del código que hay que probar. Una flag que ya está al 100 % durante meses debe borrarse junto con el camino viejo; de lo contrario el código acumula condiciones muertas que nadie se atreve a quitar. El almacén de flags puede ser desde una variable de entorno hasta un servicio dedicado; para empezar basta con lo primero.

## Migraciones de base de datos: expand / contract

El rolling, el canary y hasta el blue-green (mientras la versión vieja está de reserva) tienen en común que **dos versiones del código usan a la vez la misma base de datos**. Un cambio de esquema que rompe a la versión vieja tumba producción aunque la estrategia sea «sin cortes».

El patrón *expand / contract* (también llamado *parallel change*) divide el cambio en pasos que se despliegan por separado. Ejemplo: `pagos` guarda el estado del pago en la columna `estado` y se quiere renombrarla a `estado_pago`.

| Paso | Despliegue | Esquema | Código |
|---|---|---|---|
| 1. Expand | Migración | Añade `estado_pago` sin quitar `estado` | Escribe en ambas, lee de `estado` |
| 2. Migrate | Datos | Copia los valores antiguos a `estado_pago` | Escribe en ambas, lee de `estado_pago` |
| 3. Contract | Migración, más tarde | Elimina `estado` | Solo usa `estado_pago` |

```sql
-- Paso 1 (expand): compatible con la versión vieja
ALTER TABLE pagos ADD COLUMN estado_pago text;

-- Paso 2 (migrate): se hace por lotes si la tabla es grande
UPDATE pagos SET estado_pago = estado WHERE estado_pago IS NULL;

-- Paso 3 (contract): solo cuando ninguna versión desplegada lee `estado`
ALTER TABLE pagos DROP COLUMN estado;
```

Cada paso es seguro con la versión anterior y con la siguiente, por lo que cada despliegue admite rollback. Un `ALTER TABLE ... RENAME COLUMN` en el mismo despliegue que el código nuevo es la forma clásica de provocar un incidente con una estrategia «sin cortes». Los detalles (bloqueos de tabla, índices concurrentes, migraciones por lotes) están en [Estrategias-Zero-Downtime.md](../../bases-de-datos/migraciones-de-esquema/Estrategias-Zero-Downtime.md).

## Rollback: la vuelta atrás

El rollback es volver a la versión anterior. Es **parte** de la estrategia y no un extra, y su coste depende de cómo se despliega:

| Estrategia | Cómo se vuelve atrás |
|---|---|
| Recreate | Redesplegar la etiqueta anterior (hay corte otra vez) |
| Rolling en Kubernetes | `kubectl rollout undo deployment/pedidos` |
| Blue-green | Cambiar el upstream al color anterior y recargar |
| Canary | Poner el peso del canario a cero o escalarlo a cero réplicas |
| Feature flag | Apagar la flag |

Para que el rollback sea posible, la versión anterior debe seguir disponible: imágenes con **etiquetas inmutables** (`1.4.2`, nunca solo `latest`) y la etiqueta en una variable. En un VPS con Compose:

```bash
# Despliegue
IMAGE_TAG=1.5.0 docker compose up -d pedidos

# Rollback: la misma orden con la etiqueta anterior
IMAGE_TAG=1.4.2 docker compose up -d pedidos
```

El rollback de **código** es fácil; el de **datos** no. Una migración que borró una columna no se deshace volviendo a la imagen anterior. Por eso el paso *contract* se retrasa hasta estar seguro de que no habrá vuelta atrás.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| Errores 502 durante unos segundos en cada despliegue | `recreate` sin `healthcheck` ni proxy que reintente; o rolling sin `readinessProbe` |
| El rolling termina «bien» pero la aplicación falla | Los Pods nuevos pasan por listos antes de conectar con la base de datos; falta `readinessProbe` o su comprobación es demasiado laxa |
| Tras desplegar, la versión vieja lanza `column "estado" does not exist` | Se eliminó o renombró una columna en el mismo despliegue que el código nuevo |
| `kubectl rollout status` se queda esperando y acaba con `exceeded its progress deadline` | Los Pods nuevos no llegan a estar listos; `progressDeadlineSeconds` (600 s por defecto) marca el fallo, pero **no** deshace el despliegue |
| El rollback levanta una versión que no arranca | Una variable o un secret nuevo faltan en la configuración, o la imagen anterior se sobrescribió con `latest` |
| El canario «sale bien» pero producción falla al llegar al 100 % | Con 1-5 % del tráfico no se ejerció el caso que falla; la muestra era demasiado pequeña |
| Blue-green: el interruptor funciona pero los clientes ven la versión vieja | El proxy no recargó la configuración, o hay caché delante (CDN, navegador) |

## Cuándo no usar cada una

- **Blue-green** cuando la infraestructura duplicada no cabe: en un VPS pequeño, dos copias de `pedidos` más de la base de datos pueden agotar la memoria.
- **Canary** con poco tráfico o sin métricas: sin datos para comparar, es un rolling lento con mejor nombre.
- **Rolling** cuando las dos versiones no pueden convivir: una migración incompatible o un servicio que debe tener una única instancia.
- **Recreate** en un servicio por el que pasan pagos en directo.

## Buenas prácticas avanzadas

- **Diseña cada cambio para que dos versiones convivan.** Antes de elegir estrategia, la pregunta es qué ocurre si la versión N y la N+1 atienden a la vez contra la misma base de datos y la misma cola de mensajes. Los contratos de mensajes entre `pedidos` y `emails` se versionan igual que las columnas.
- **Ensaya el rollback antes de necesitarlo.** Casi todos los equipos tienen rollback «en teoría» y descubren durante un incidente que la imagen anterior ya no arranca. Probar la vuelta atrás en staging con cada cambio de configuración lo detecta a tiempo.
- **Que el despliegue falle por sí solo.** `kubectl rollout status` con código de salida distinto de cero, o `docker compose up -d --wait` que espera a `healthy`, permiten que el pipeline detecte el fallo y dispare el rollback en lugar de dar el despliegue por bueno al terminar el comando.
- **Separa el cambio de esquema del cambio de código.** Dos despliegues pequeños (migración compatible, luego código) son más fáciles de revertir que uno grande.
- **Retira las flags viejas.** Una flag al 100 % durante meses es deuda; ponerle fecha de caducidad al crearla evita el cementerio de condiciones.
- **Pon etiquetas inmutables a las imágenes.** Si `latest` cambia entre el despliegue y el rollback, «volver a la anterior» ya no significa nada.

## Documentación oficial

- [Kubernetes: Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) — estrategias `RollingUpdate` y `Recreate`, `maxSurge`, `maxUnavailable`, `kubectl rollout`; leer las secciones de estrategia y de vuelta atrás.
- [Compose: `deploy`](https://docs.docker.com/reference/compose-file/deploy/) — campos `update_config` y `rollback_config`; útil para saber qué existe y comprobar su soporte en la versión instalada.
- [Martin Fowler: Blue-Green Deployment](https://martinfowler.com/bliki/BlueGreenDeployment.html) — el artículo breve que describe el patrón y sus límites con la base de datos.
- [Martin Fowler: Parallel Change](https://martinfowler.com/bliki/ParallelChange.html) — el patrón *expand / migrate / contract* en el que se basa la sección de migraciones.

---

*En resumen: desplegar sin cortes consiste en que dos versiones convivan durante un rato, de modo que la elección de estrategia es decidir cuánta infraestructura y complejidad se paga a cambio de poder equivocarse sin que se note, con la base de datos compatible en ambas direcciones.*
