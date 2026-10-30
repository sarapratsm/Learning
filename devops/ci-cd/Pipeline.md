# Pipeline

## ¿Qué es?

Un *pipeline* (tubería) es la **secuencia de pasos automáticos** que recorre el código desde que cambia hasta que llega a producción, descrita normalmente en un fichero de texto (YAML) que vive junto al código. Es la receta concreta que ejecuta una herramienta de CI/CD.

## ¿Por qué existe?

Automatizar exige describir qué pasos se ejecutan, en qué orden, bajo qué condiciones y qué pasa si uno falla. El pipeline es esa descripción.

> Si ya conoces las recetas de cocina: el pipeline es la receta escrita paso a paso; la herramienta de CI/CD es el cocinero que la sigue al pie de la letra cada vez.

Tenerlo como fichero (*pipeline as code*) tiene una ventaja enorme: el proceso de despliegue queda versionado en Git igual que el código. Se ve quién lo cambió, se revierte si se rompe y se revisa en una *pull request*. La alternativa, configurarlo con clics en el panel de una herramienta, no deja rastro ni se puede revisar.

## ¿Cuándo y para qué se usa?

Cada vez que se configura CI/CD se define un pipeline. Los pasos cambian con el proyecto:

- Servicio en Node.js (`pedidos`): instalar dependencias → linter → tests → build → imagen → desplegar.
- Servicio en .NET (`pagos`): restaurar paquetes → compilar → tests → imagen → publicar.
- Sitio estático: generar → subir al hosting.

Este documento explica el vocabulario común (jobs, steps, stages, artefactos, caché) con GitHub Actions como herramienta de ejemplo; la sintaxis completa de cada plataforma está en [GitHub Actions](GitHub-Actions.md), [GitLab CI](GitLab-CI.md) y [Jenkins](Jenkins.md). El marco general —qué es CI y qué es CD— está en [CI/CD](CI-CD.md).

## Anatomía: disparador, jobs y steps

Un pipeline tiene tres niveles:

- **Disparador** (*trigger*): el evento que lo arranca (`push`, *pull request*, etiqueta, hora programada, botón manual).
- **Job**: un grupo de pasos que se ejecuta en una misma máquina limpia (*runner*). Cada job parte de cero: no ve los ficheros ni las instalaciones del job anterior.
- **Step**: una orden concreta dentro de un job (un comando o una acción reutilizable).

```yaml
name: ci
on:
  push:
    branches: [main]

jobs:
  test:                              # job
    runs-on: ubuntu-latest
    steps:                           # pasos, en orden
      - uses: actions/checkout@v4    # descargar el código
      - run: npm ci                  # instalar dependencias
      - run: npm test                # tests
```

Qué hace: ante cada `push` a `main`, arranca una máquina Ubuntu, descarga el código y ejecuta los tres pasos en orden. Si `npm test` devuelve un código de salida distinto de 0, el job se marca como fallido y se detiene.

Que cada job parta de una máquina limpia es lo que más desconcierta al principio, y la razón de que existan los artefactos (más abajo).

## Orden y paralelismo

Los jobs, por defecto, corren **en paralelo**. Para encadenarlos se declara la dependencia:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm test

  build:
    needs: test                      # espera a que test termine bien
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm run build

  deploy:
    needs: build
    if: github.ref == 'refs/heads/main'    # solo desde main
    runs-on: ubuntu-latest
    steps:
      - run: echo "desplegar tienda.ejemplo.com"
```

Qué hace: `test` arranca primero; `build` solo si `test` fue bien; `deploy` solo si `build` fue bien y la rama es `main`. Si `test` falla, los otros dos se marcan como omitidos y no se despliega código roto.

GitLab CI llama *stages* (fases) a estos niveles: los jobs de una fase corren en paralelo y la fase siguiente espera a que termine toda la anterior. GitHub Actions no tiene fases, tiene `needs`; el efecto es el mismo.

Para repetir un job con varias combinaciones (Node 20 y 22, Linux y Windows) se usa una **matriz**, que lanza una copia en paralelo por combinación:

```yaml
strategy:
  matrix:
    node: [20, 22]
steps:
  - uses: actions/setup-node@v4
    with:
      node-version: ${{ matrix.node }}
```

## Pasar resultados entre jobs: artefactos

Como cada job parte de cero, lo que produce uno (la app compilada, un informe de tests) se guarda como **artefacto** y lo recoge el siguiente:

```yaml
  build:
    steps:
      - run: npm ci && npm run build
      - uses: actions/upload-artifact@v4
        with:
          name: dist
          path: dist/

  deploy:
    needs: build
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: dist
```

Así el `deploy` publica exactamente lo que `build` generó, sin recompilar. Cuando el artefacto es una imagen de contenedor, el «almacén» es un registro de imágenes; ver [Docker en CI/CD](Docker-en-CI-CD.md).

## Caché: no descargar lo mismo en cada ejecución

La caché evita reinstalar dependencias que no han cambiado. Se distingue del artefacto en que la caché es una optimización (si falta, el pipeline funciona, solo tarda más) y el artefacto es un resultado del que depende el job siguiente.

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 20
    cache: npm          # clave basada en package-lock.json
- run: npm ci
```

Qué hace: restaura `~/.npm` si el `package-lock.json` no cambió, y la guarda al final si cambió. Una instalación de 90 segundos puede bajar a 10.

## Fallos, reintentos y condiciones

- Por defecto, un step fallido detiene el job y los jobs que dependen de él no se ejecutan.
- `if: always()` ejecuta un step aunque falle uno anterior (útil para subir el informe de tests).
- `continue-on-error: true` deja pasar el fallo de un step. Úsalo con cuidado: un check que nunca para nada es decoración.
- `timeout-minutes` limita la duración del job; el valor por defecto de GitHub Actions es 360 minutos.

```yaml
- run: npm test
- if: always()
  uses: actions/upload-artifact@v4
  with:
    name: informe-tests
    path: coverage/
```

## Cuándo usar cada pieza

| Necesidad | Pieza |
|---|---|
| Que dos tareas corran a la vez | Jobs sin `needs` entre sí |
| Que una tarea espere a otra | `needs` (o *stages* en GitLab) |
| Probar varias versiones o sistemas | Matriz |
| Llevar un resultado a otro job | Artefacto |
| Acelerar la descarga de dependencias | Caché |
| Ejecutar solo en ciertas ramas o ficheros | `if`, filtros de rama y ruta (ver [Monorepo y path-filters](Monorepo-y-Path-Filters.md)) |
| Una contraseña o token | *Secret*, nunca en el YAML (ver [Secrets y variables](Secrets-y-Variables.md)) |

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `Error: ENOENT: no such file or directory, open 'package.json'` | Falta el `actions/checkout`: el runner está vacío |
| `Error: Unable to resolve action actions/checkout@v99` | Versión de la acción inexistente |
| `Error: Input required and not supplied: path` | Falta un parámetro obligatorio en `with:` |
| `Error: Unable to download artifact(s): Artifact not found for name: dist` | El job que lo sube falló, se llama distinto, o no está en `needs` |
| `Invalid workflow file: .github/workflows/ci.yml#L12 ... mapping values are not allowed here` | Sangría incorrecta en el YAML |
| El job de despliegue se queda en «Skipped» | Un job del que depende falló, o la condición `if` no se cumple |
| Las dependencias se descargan en cada ejecución | Caché sin configurar, o clave que cambia siempre |

## Cuándo un pipeline no es la herramienta

- Tareas que deben ocurrir **en tu máquina antes de subir** (formato, mensajes de commit): mejor un [hook de Git](Git-Hooks.md); el pipeline llega tarde y cuesta minutos de runner.
- Lógica compleja incrustada en YAML: si hay bucles, condiciones anidadas y manejo de errores, es un script y debe vivir como tal (ver buenas prácticas).

## Buenas prácticas avanzadas

- **El YAML orquesta; los scripts hacen.** Si la lógica de build vive incrustada en el YAML, solo se puede probar subiendo commits y esperando al robot. Los equipos expertos ponen la lógica en scripts del repositorio (`./scripts/build.sh`, un Makefile, scripts de npm) y el pipeline se limita a llamarlos: así cada paso se depura en local y se puede cambiar de herramienta sin reescribirlo todo.
- **Fija versiones de todo lo que ejecuta el pipeline.** `node:20.11`, acciones ancladas a versión (o mejor, a SHA de commit), herramientas con número exacto. Un pipeline con `latest` falla un día sin que nadie haya tocado nada, porque cambió medio entorno.
- **Compila una vez y pasa el artefacto entre fases.** Que cada job compile lo que necesita hace que lo desplegado no sea lo probado, y se paga la compilación varias veces.
- **Cachea con una clave que dependa del lockfile.** La clave es el hash de `package-lock.json` (o equivalente): sin cambios restaura, con cambios reconstruye. Una caché con clave fija sirve dependencias viejas y produce verdes que mienten.
- **Pon timeout explícito a cada job.** Un test colgado puede mantener el job vivo horas, consumiendo minutos de pago y bloqueando la cola. El doble de lo que tarda normalmente convierte un cuelgue silencioso en un fallo visible.

## Documentación oficial

- [Workflow syntax for GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax) — la referencia completa de la sintaxis usada aquí: `on`, `jobs`, `needs`, `strategy.matrix`, `if`, `timeout-minutes`. Se consulta buscando la clave concreta.
- [Understanding GitHub Actions](https://docs.github.com/en/actions/get-started/understand-github-actions) — el modelo mental de workflows, jobs, steps y runners, antes de entrar en la sintaxis.

---

*En resumen: el pipeline es la receta paso a paso de CI/CD — un fichero versionado que describe cómo el código pasa de un commit a producción, con jobs, orden, artefactos y caché.*
