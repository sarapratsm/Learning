# Git Flow

## ¿Qué es?

Git Flow es un **modelo de ramas**: un conjunto de reglas sobre qué ramas existen, para qué sirve cada una y cómo fluye el trabajo entre ellas. No es un comando de Git, sino una convención que un equipo decide seguir. Lo describió Vincent Driessen en 2010 en el artículo *A successful Git branching model*.

## ¿Por qué existe?

Git deja crear ramas libremente, pero esa libertad en equipo puede volverse un caos: ¿dónde va el trabajo en curso?, ¿dónde lo que ya es estable?, ¿cómo entra un arreglo urgente sin arrastrar lo que está a medias? Git Flow responde con una estructura fija de ramas con roles claros, para que todo el equipo trabaje igual y sin sorpresas.

> Es como las normas de circulación: Git ofrece las calles (las ramas), pero Git Flow define los carriles y las señales para que nadie choque.

## ¿Cuándo y para qué se usa?

Encaja con **versiones publicadas de forma periódica y varias personas trabajando a la vez**: una aplicación de escritorio o móvil que saca versión cada pocas semanas, un producto que mantiene varias versiones en paralelo, o un equipo que necesita una fase de estabilización antes de cada publicación. En la tienda online (repositorio `tienda`, servicios `pedidos`, `pagos`, `inventario` y `emails`), tendría sentido si cada versión se entrega empaquetada a clientes que la instalan en su servidor. Para una web que se despliega varias veces al día, suele ser demasiada ceremonia; la sección [Git Flow, GitHub Flow o trunk-based](#git-flow-github-flow-o-trunk-based) compara las opciones.

## Las ramas

Dos ramas **permanentes** y tres tipos de ramas **temporales**.

| Rama | Sale de | Vuelve a | Para qué |
|---|---|---|---|
| `main` | — | — | Permanente. Solo contiene versiones publicadas; cada commit de `main` es una versión y lleva su etiqueta |
| `develop` | — | — | Permanente. Rama de integración: el trabajo terminado de la próxima versión |
| `feature/*` | `develop` | `develop` | Desarrollar una función nueva |
| `release/*` | `develop` | `main` y `develop` | Congelar y pulir una versión antes de publicarla |
| `hotfix/*` | `main` | `main` y `develop` | Arreglar un error urgente en producción |

Los nombres con barra (`feature/cancelar-pedido`) son una convención: Git los admite como cualquier otro, y muchos clientes los agrupan en carpetas. Detalles de cómo crear, listar y borrar ramas: [Ramas](Ramas.md) y [Switch](Switch.md).

## El flujo, paso a paso

Un ciclo completo con las ramas de `tienda`. Los comandos usan `merge --no-ff`, que **siempre crea un commit de fusión**, aunque Git pudiera simplemente avanzar la rama. Así queda registrado en el historial que existió una rama de función, y se puede deshacer una función entera revirtiendo un solo commit (ver [Fusión y conflictos](Fusion-y-conflictos.md)).

### 1. Una función: `feature/*`

```bash
git switch -c feature/pedidos-cancelar develop
# ...trabajo y commits...
git switch develop
git merge --no-ff feature/pedidos-cancelar
git branch -d feature/pedidos-cancelar
```

```
Switched to a new branch 'feature/pedidos-cancelar'
Switched to branch 'develop'
Merge made by the 'ort' strategy.
 b | 1 +
 1 file changed, 1 insertion(+)
 create mode 100644 b
Deleted branch feature/pedidos-cancelar (was 1ca8682).
```

La función nace de `develop` y vuelve a `develop`; `main` no se entera. Si se trabaja con [pull requests](Pull-requests.md), el `merge` lo hace el botón de la plataforma en lugar de la línea de comandos.

### 2. Una versión: `release/*`

Cuando `develop` contiene lo que debe salir en la próxima versión, se abre una rama de release. En ella solo entran correcciones y el cambio del número de versión.

```bash
git switch -c release/1.1.0 develop
# ...subir la versión, corregir lo que salga en las pruebas...
git switch main
git merge --no-ff release/1.1.0
git tag -a v1.1.0 -m "Versión 1.1.0"
git switch develop
git merge --no-ff release/1.1.0          # back-merge
git branch -d release/1.1.0
```

La fusión a `main` es la publicación; la etiqueta (ver [Tags y versiones](Tags-y-versiones.md)) marca el commit exacto. El **back-merge** a `develop` devuelve a la rama de integración las correcciones que se hicieron durante la release.

### 3. Un arreglo urgente: `hotfix/*`

Un error en producción no puede esperar a la siguiente versión ni arrastrar lo que `develop` tenga a medias. Por eso el hotfix sale de `main`, no de `develop`:

```bash
git switch -c hotfix/1.1.1 main
# ...el arreglo...
git switch main
git merge --no-ff hotfix/1.1.1
git tag -a v1.1.1 -m "Versión 1.1.1"
git switch develop
git merge --no-ff hotfix/1.1.1           # back-merge
git branch -d hotfix/1.1.1
```

Resultado en el historial tras los tres ciclos (`git log --oneline --graph --all`, abreviado):

```
*   c1e0b01 Back-merge hotfix 1.1.1
|\
*   48872a5 Back-merge release 1.1.0
...
| | | *   6cea93e Hotfix 1.1.1
...
| | *   b814627 Release 1.1.0
...
* |   420b918 Fusiona feature/pedidos-cancelar
```

Si hay una release abierta cuando llega el hotfix, el back-merge del hotfix va a la rama `release/*` en lugar de a `develop` (que la recibirá al cerrar la release).

### La extensión `git flow`

Existe una extensión externa (`git flow init`, `git flow feature start`, `git flow release finish`...) que automatiza estos pasos: crea las ramas, fusiona con `--no-ff`, etiqueta y borra. No viene incluida con Git y no es imprescindible: el modelo se sigue igual con `switch`, `merge` y `tag`.

## Git Flow, GitHub Flow o trunk-based

Git Flow no es la única forma de organizar las ramas. Las otras dos más extendidas son:

- **GitHub Flow**: una única rama permanente (`main`, siempre desplegable). Cada cambio nace en una rama corta, se revisa en un pull request y, al fusionarse, se despliega.
- **Trunk-based development**: todo el equipo integra en una sola rama (el *trunk*, normalmente `main`) varias veces al día, con ramas de vida muy corta (horas) o directamente sobre el tronco. Lo incompleto se esconde detrás de *feature flags* en lugar de en ramas.

| | Git Flow | GitHub Flow | Trunk-based |
|---|---|---|---|
| Ramas permanentes | `main` y `develop` | `main` | `main` (el tronco) |
| Vida de las ramas de trabajo | Días o semanas (`feature`) | Horas o pocos días | Horas; a veces ninguna |
| Frecuencia de publicación | Por versiones planificadas | Cada fusión puede desplegarse | Continua |
| Varias versiones en producción a la vez | Sí (mantenimiento con `hotfix` y ramas `release`) | No | No (salvo ramas de release puntuales) |
| Revisión de código | Posible, no obligatoria por el modelo | Núcleo del modelo (pull request) | Revisión rápida o programación en pareja |
| Disciplina que exige | Respetar el flujo y no olvidar el back-merge | Buenos tests y despliegue automatizado | Tests muy fiables y *feature flags* |
| Encaja con | Software empaquetado, versiones con soporte | Aplicaciones web y servicios | Equipos con CI/CD maduro |

Regla práctica de elección:

| Situación | Modelo |
|---|---|
| Se publican versiones numeradas y se mantienen varias a la vez (SDK, aplicación instalable) | Git Flow |
| Servicio web con despliegue frecuente y un solo entorno de producción | GitHub Flow |
| Despliegue continuo con tests automáticos sólidos y equipo con experiencia | Trunk-based |
| Equipo pequeño que empieza | GitHub Flow: es el más simple de explicar |

Las críticas más repetidas a Git Flow:

- **Ceremonia**: dos ramas permanentes, tres tipos de rama y dos merges por release añaden pasos que, con despliegue continuo, no aportan nada.
- **Integración tardía**: una `feature` que vive semanas se aleja de `develop` y la fusión final trae conflictos grandes.
- **`develop` y `main` divergen**: cualquier cambio que se cuele en una y no en la otra tarda en notarse.
- **El propio autor lo matizó**: en una nota añadida en 2020 al artículo original, Vincent Driessen indica que el modelo se pensó hace más de una década y que, si el equipo hace entrega continua, conviene un flujo mucho más simple.

## Errores frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| Un bug arreglado en producción reaparece en la siguiente versión | Se hizo el merge del hotfix a `main` pero no el back-merge a `develop` | Fusionar el hotfix en `develop` y adoptar la comprobación de abajo |
| `git branch -d feature/x` responde `error: The branch 'feature/x' is not fully merged.` | La rama tiene commits que no están en la rama actual | Comprobar que se fusionó en `develop`; si es así, estar en `develop` al borrar; si de verdad se descarta, `git branch -D` |
| Conflictos enormes al cerrar una `feature` | Estuvo semanas sin actualizarse desde `develop` | Traer `develop` a la rama cada pocos días (`git merge develop`, o [`rebase`](Rebase.md) si aún no se ha publicado) |
| La release no se acaba nunca | Siguen entrando funciones nuevas en `release/*` | Solo correcciones; lo nuevo espera en `develop` |
| `main` contiene una versión sin etiqueta | Se olvidó `git tag` tras el merge | `git tag -a v1.1.0 <commit-de-la-release>` y `git push --tags` |

## Buenas prácticas avanzadas

- **El *back-merge* a `develop` es el paso que todo el mundo olvida.** Cada `hotfix/*` y cada `release/*` se fusiona en `main` **y** en `develop`. Si se omite el segundo, el arreglo vive solo en producción y la siguiente release lo pisa. Una comprobación barata, ejecutable en CI, es `git log develop..main --no-merges --oneline`: si imprime algo, hay commits en `main` que `develop` no tiene (sin `--no-merges` siempre listaría los commits de fusión, que no se replican).
- **Una etiqueta por cada merge a `main`.** En Git Flow, `main` solo recibe releases y hotfixes, así que cada fusión merece su `v2.1.0` o `v2.1.1`. Sin ellas se pierde lo que justifica el modelo: responder «¿qué hay exactamente en producción?» y volver a cualquier versión publicada. Los despliegues pueden dispararse por etiqueta (ver [Release por tag](../ci-cd/Release-por-Tag.md)).
- **En `release/*` solo entran correcciones.** El propósito de la rama es congelar el contenido de la versión mientras se pule. Colar «una funcioncita más» invalida las pruebas hechas y alarga la release. Si algo no puede esperar a la siguiente versión, el problema es de planificación, no de Git.
- **Protege `main` y `develop`.** Con protección de rama, solo se entra por pull request con los checks en verde, así que ni un hotfix urgente llega a producción sin pasar por la CI (ver [Pull requests](Pull-requests.md)).
- **Mantén las `feature` cortas, aunque el modelo permita lo contrario.** Dividir el trabajo para fusionar cada pocos días reduce los conflictos y acerca a Git Flow al ritmo de integración de los otros modelos; lo que no esté listo se esconde tras un *feature flag* en lugar de en una rama larga.

## Documentación oficial

- [A successful Git branching model](https://nvie.com/posts/a-successful-git-branching-model/) — el artículo original de 2010 con los diagramas de cada rama; leer también la nota de reflexión de 2020 al inicio.
- [GitHub flow](https://docs.github.com/en/get-started/using-github/github-flow) — descripción oficial del flujo alternativo basado en `main` y pull requests.
- [Trunk Based Development](https://trunkbaseddevelopment.com/) — sitio de referencia del modelo de tronco único, con técnicas como los *feature flags* y las ramas de vida corta.

---

*En resumen: Git Flow reparte el trabajo en `main`, `develop`, `feature`, `release` y `hotfix` para gestionar versiones publicadas con varias personas — vale la pena cuando hay versiones que mantener, y sobra cuando se despliega de forma continua.*
