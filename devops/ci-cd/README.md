# CI/CD — Guía de tecnologías

Guía de **CI/CD** (integración y despliegue continuos): qué problema resuelve, cómo se describe un pipeline, qué plataformas lo ejecutan y qué técnicas aparecen al montar el de un proyecto real. Todos los ejemplos comparten escenario: una tienda online con los servicios `pedidos`, `pagos`, `inventario` y `emails`, desplegada en un VPS.

Cada ficha parte de una introducción accesible y desarrolla el tema con ejemplos de código guiados, tablas de decisión y errores frecuentes. Requiere nociones de programación y de Git, pero no experiencia previa en automatización.

---

## Orden de lectura recomendado

Cada concepto se apoya en el anterior.

### 1. Conceptos fundamentales

Empieza por entender la idea antes de mirar herramientas concretas.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [CI/CD](CI-CD.md) | La idea central. Qué significan las siglas y qué problema resuelven. Imprescindible antes de todo lo demás. |
| 2 | [Pipeline](Pipeline.md) | Cómo se describe el proceso paso a paso. Es el vocabulario común a todas las herramientas. |

### 2. Herramientas de CI/CD

Las plataformas concretas que ejecutan los pipelines. Lee al menos la primera; las demás según lo que uses.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 3 | [GitHub Actions](GitHub-Actions.md) | La opción más extendida si tu código está en GitHub. Buen punto de partida práctico. |
| 4 | [GitLab CI/CD](GitLab-CI.md) | El equivalente para repositorios en GitLab. Mismos conceptos, vocabulario propio. |
| 5 | [Jenkins](Jenkins.md) | El veterano autoalojado. Útil para entender el enfoque "servidor propio". |

### 3. Piezas que aparecen en casi cualquier pipeline

Conceptos transversales que usarás sea cual sea la herramienta.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 6 | [Docker en CI/CD](Docker-en-CI-CD.md) | Cómo se consigue un entorno reproducible y cómo se empaqueta la app para desplegarla. |
| 7 | [Secrets y variables de entorno](Secrets-y-Variables.md) | Cómo manejar contraseñas y tokens sin meterlos en el repositorio. Seguridad básica imprescindible. |
| 8 | [Estrategias de despliegue](Estrategias-de-Despliegue.md) | Las distintas formas de poner una versión en producción sin cortes y con vuelta atrás. |

### 4. Técnicas que verás en pipelines reales

Patrones concretos que aparecen al montar el CI/CD de un proyecto de verdad. Requieren los bloques anteriores.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 9 | [Git hooks (validación local)](Git-Hooks.md) | La primera línea de defensa: validar en tu máquina antes de gastar un minuto de CI. |
| 10 | [Monorepo y path-filters](Monorepo-y-Path-Filters.md) | Cómo evitar que un repo con varias áreas lo recompile todo en cada cambio. |
| 11 | [Entornos efímeros en CI](Entornos-Efimeros-en-CI.md) | Probar la aplicación completa sin mantener un servidor de pruebas permanente. |
| 12 | [Release por tag](Release-por-Tag.md) | Separar "integrar código" de "publicar producto": el deploy como decisión explícita. |

---

## Qué ficha consultar según la duda

| Duda | Ficha |
|---|---|
| ¿Qué diferencia hay entre integración, entrega y despliegue continuos? | [CI/CD](CI-CD.md) |
| ¿Cómo se estructura un pipeline en etapas y trabajos? | [Pipeline](Pipeline.md) |
| ¿Cómo monto mi primer workflow en GitHub? | [GitHub Actions](GitHub-Actions.md) |
| ¿Cómo guardo una contraseña o un token sin subirlo al repo? | [Secrets y variables](Secrets-y-Variables.md) |
| ¿Cómo publico una versión sin cortar el servicio? | [Estrategias de despliegue](Estrategias-de-Despliegue.md) |
| ¿Por qué mi workflow no arranca al tocar un solo servicio? | [Monorepo y path-filters](Monorepo-y-Path-Filters.md) |
| ¿Cómo publico una versión solo cuando yo lo decida? | [Release por tag](Release-por-Tag.md) |

---

> ¿Quieres ver cómo encaja esto con el resto del stack? Echa un vistazo a las guías de [Docker](../docker/README.md) y de [React y su ecosistema](../../desarrollo-web/frontend-react/README.md) de esta misma colección de aprendizaje.
