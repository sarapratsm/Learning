# Git hooks

## ¿Qué es?

Un *hook* de Git es un script que Git ejecuta automáticamente en un momento concreto del flujo de trabajo local: antes de crear un commit, al escribir su mensaje, antes de subir cambios. Si el script termina con un código de salida distinto de cero, Git aborta la operación. El más usado es `pre-commit`, que corre justo antes de cada commit.

## ¿Por qué existe?

El CI valida el código en un servidor, pero tiene dos costes: los **minutos de ejecución** (que se pagan) y el **tiempo de espera**. Se sube el commit, se espera al robot, se descubre que fallaba un lint trivial o un test unitario, y vuelta a empezar. Muchos de esos fallos se habrían detectado en la máquina local en segundos.

Un hook mueve esa primera validación a local: si el lint o los tests rápidos fallan, **el commit ni siquiera se crea**. El error aparece en el momento más barato posible.

> Es el corrector ortográfico del editor frente a esperar a que la imprenta devuelva el libro impreso: mismo error, detectado mucho antes.

## ¿Cuándo y para qué se usa?

- **Formato y lint antes de cada commit**, para que no lleguen a una pull request discusiones sobre comillas o espacios.
- **Compilación y tests unitarios rápidos** del servicio tocado: en la tienda online de ejemplo (servicios `pedidos`, `pagos`, `inventario` y `emails` en un mismo repositorio), un cambio en `pagos` no necesita compilar `emails`.
- **Convenciones de mensaje de commit**, por ejemplo exigir que empiece por `pedidos:` o `pagos:` según el servicio.
- **Evitar subir secretos** con un escáner que revise lo que se va a commitear.

Un hook no reemplaza al CI; lo complementa. La sección «`--no-verify` y por qué el CI sigue siendo la barrera» explica por qué.

---

## Qué hooks hay y cuáles se usan

Git admite unos veinte hooks; para el trabajo diario bastan cuatro.

| Hook | Cuándo corre | Recibe | Úsalo para |
|---|---|---|---|
| `pre-commit` | Antes de crear el commit, antes de pedir el mensaje | Nada | Lint, formato, compilación rápida, tests unitarios |
| `prepare-commit-msg` | Al preparar el mensaje, antes de abrir el editor | Fichero del mensaje | Rellenar una plantilla (prefijo según rama) |
| `commit-msg` | Tras escribir el mensaje | Ruta al fichero del mensaje | Validar el formato del mensaje |
| `pre-push` | Al hacer `git push`, antes de enviar nada | Remoto y URL; las referencias por entrada estándar | Validaciones más caras: suite de tests completa |

Un código de salida distinto de cero en `pre-commit`, `commit-msg` o `pre-push` aborta la operación. `pre-push` aborta el envío sin subir nada.

## Primer hook: un `pre-commit` que funciona

Los hooks viven por defecto en `.git/hooks/`, una carpeta que **no se versiona**. Eso significa que no viajan con `git clone`. Para compartirlos hay que guardarlos en el repositorio y decirle a Git dónde están.

Primero, el script en una carpeta del repositorio:

```sh
#!/bin/sh
# .githooks/pre-commit — si termina con código != 0, el commit se aborta
set -e

echo "pre-commit: comprobando formato y compilación..."
dotnet format --verify-no-changes pagos/
dotnet build pagos/ --nologo -v q
```

Después, se le da permiso de ejecución y se le indica a Git la carpeta, **una sola vez por clon**:

```bash
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
```

`core.hooksPath` sustituye la carpeta `.git/hooks/` por la ruta indicada (relativa a la raíz del repositorio o absoluta). Un hook sin permiso de ejecución se ignora **sin avisar**.

Al hacer `git commit`, si `dotnet format` encuentra cambios pendientes, el commit se aborta:

```text
$ git commit -m "pagos: reintento de cobro"
pre-commit: comprobando formato y compilación...
Formatting code files in workspace 'pagos/'...
pagos/CobroService.cs(42,5): error WHITESPACE: Fix whitespace formatting.
$ git log --oneline -1     # el commit no existe
```

El script se ejecuta desde la raíz del repositorio. Si falla, se arregla el problema, se vuelve a hacer `git add` y se repite el commit.

## Solo lo que toca el commit

En un repositorio con varios servicios, compilar todo en cada commit es lento y la gente acaba saltándose el hook. La solución es revisar qué ficheros están preparados (*staged*) y validar solo esa área:

```sh
#!/bin/sh
# .githooks/pre-commit — valida solo los servicios que toca el commit
set -e

changed=$(git diff --cached --name-only)

for service in pedidos pagos inventario emails; do
  if printf '%s\n' "$changed" | grep -q "^$service/"; then
    echo "pre-commit: validando $service..."
    ( cd "$service" && dotnet build --nologo -v q && dotnet test --filter "Category=Unit" --nologo -v q )
  fi
done
```

`git diff --cached --name-only` lista los ficheros del área de preparación. Si el commit solo toca `pedidos/`, solo se compila y prueba `pedidos`. La ficha [Monorepo-y-Path-Filters.md](Monorepo-y-Path-Filters.md) aplica la misma idea al CI.

Hay una trampa importante: el hook corre sobre los ficheros **tal como están en disco**, no sobre lo que se va a commitear. Si hay cambios sin preparar en el árbol de trabajo, el test los ve y puede pasar por algo que el commit no incluye. El commit resultante puede estar roto aunque «pasó el hook».

```bash
# ❌ El test pasa en local porque ve el cambio no preparado de PagoValidator.cs,
#    pero el commit solo lleva CobroService.cs
git add pagos/CobroService.cs
git commit -m "pagos: reintento de cobro"
```

Las herramientas que operan solo sobre lo preparado (lint-staged, y las funciones equivalentes de pre-commit y lefthook) cierran ese hueco. Un script casero puede aislar el área de preparación con `git stash push --keep-index` antes de validar y restaurar con `git stash pop` después, aunque es frágil con ficheros sin seguimiento.

## Validar el mensaje del commit

`commit-msg` recibe la ruta del fichero con el mensaje. Este ejemplo exige un prefijo con el nombre del servicio:

```sh
#!/bin/sh
# .githooks/commit-msg
msg_file="$1"
if ! grep -Eq '^(pedidos|pagos|inventario|emails|infra): ' "$msg_file"; then
  echo "commit-msg: el mensaje debe empezar por 'servicio: ' (pedidos, pagos, inventario, emails, infra)"
  exit 1
fi
```

Un mensaje como `arreglo del cobro` se rechaza; `pagos: arreglo del cobro` pasa. Para las convenciones de mensaje en general, ver [Commits.md](../git/Commits.md).

## Herramientas que gestionan los hooks

Configurar `core.hooksPath` a mano funciona, pero deja a cada persona la tarea de activarlo, y no resuelve la ejecución solo sobre ficheros preparados. Tres herramientas cubren ese hueco (verificadas en sus sitios oficiales a 2026-10-30):

| Herramienta | Ecosistema | Configuración | Cómo se activa |
|---|---|---|---|
| Husky | Node (npm) | Scripts en `.husky/` | El script `prepare` de `package.json` lo instala en `npm install` |
| pre-commit | Python, agnóstica del lenguaje de los hooks | `.pre-commit-config.yaml` | `pre-commit install` en cada clon |
| lefthook | Binario único (Go), disponible por npm, gem, winget, etc. | `lefthook.yml` | `lefthook install` |

**Husky** se apoya en `core.hooksPath` y en el script `prepare`, de modo que quien ejecuta `npm install` queda con los hooks activos:

```bash
npm install --save-dev husky
npx husky init            # crea .husky/pre-commit y añade el script "prepare"
```

```sh
# .husky/pre-commit
npx lint-staged
```

```json
{
  "lint-staged": {
    "*.{js,ts}": ["eslint --fix", "prettier --write"]
  }
}
```

`lint-staged` ejecuta cada comando solo sobre los ficheros preparados que casan con el patrón, y vuelve a prepararlos si el comando los reformatea.

**pre-commit** descarga y versiona los hooks como repositorios externos, lo que sirve para equipos con varios lenguajes:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-added-large-files
```

```bash
pip install pre-commit
pre-commit install            # instala el hook en .git/hooks
pre-commit run --all-files    # al añadir hooks nuevos: revisa todo el repositorio
```

La documentación recomienda fijar cada `rev` a una referencia inmutable; `pre-commit autoupdate --freeze` reescribe el `rev` con el hash completo del commit. Los números de versión del ejemplo son ilustrativos: usar el resultado de `autoupdate`.

**lefthook** es un binario sin dependencias de runtime, con ejecución en paralelo y filtros por patrón de ficheros:

```yaml
# lefthook.yml
pre-commit:
  jobs:
    - run: npx eslint --fix {staged_files}
      glob: "*.{js,ts}"
      stage_fixed: true
```

```bash
lefthook install
```

`{staged_files}` se sustituye por la lista de ficheros preparados, y `stage_fixed: true` vuelve a prepararlos tras la corrección automática.

## Cuál elegir

| Situación | Opción |
|---|---|
| Proyecto Node y poco que configurar | Husky + lint-staged |
| Repositorio con varios lenguajes o equipo con Python | pre-commit |
| Monorepo poliglota, hooks lentos que conviene paralelizar | lefthook |
| Un solo script de pocas líneas y repositorio pequeño | `core.hooksPath` a mano |

La diferencia práctica entre ellas es el ecosistema de instalación: Husky y lefthook se sirven con el gestor de paquetes que el proyecto ya usa, y pre-commit exige Python en cada máquina.

## `--no-verify` y por qué el CI sigue siendo la barrera

Cualquier commit se puede crear sin pasar por `pre-commit` ni `commit-msg`:

```bash
git commit --no-verify -m "pagos: arreglo urgente"
```

Y un hook que nadie ha activado (por ejemplo, tras un clon nuevo sin ejecutar `npm install`) simplemente no corre. Por eso **un hook local no garantiza nada**: ayuda a quien quiere ayudarse, pero no impide un commit defectuoso, accidental o deliberado.

La barrera real está en el servidor. El CI debe ejecutar **las mismas comprobaciones** que el hook, y la plataforma debe exigir que pasen antes de fusionar. En GitHub, eso se configura con una regla de protección de rama que requiere que determinadas comprobaciones de estado pasen:

```yaml
# .github/workflows/ci.yml
name: ci
on:
  pull_request:

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: dotnet format --verify-no-changes
      - run: dotnet build --nologo -v q
      - run: dotnet test --filter "Category=Unit" --nologo -v q
```

Con esta regla, un commit hecho con `--no-verify` falla en la pull request y no entra en `main`. El hook sigue siendo útil porque ahorra la espera, pero la garantía es la del CI. La ficha [GitHub-Actions.md](GitHub-Actions.md) explica la sintaxis del workflow, y [CI-CD.md](CI-CD.md) el papel de la integración continua como puerta de entrada.

`--no-verify` tiene usos legítimos: un commit de trabajo en progreso en una rama personal, un arreglo de emergencia con el hook roto, un commit de merge que el hook rechaza por error. Se vuelve un problema cuando es el hábito, y eso suele indicar que el hook es demasiado lento o demasiado ruidoso.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| El hook no se ejecuta nunca | `core.hooksPath` no configurado en ese clon, o el fichero no tiene permiso de ejecución (Git lo ignora sin avisar) |
| `/usr/bin/env: 'sh\r': No such file or directory` | El script se guardó con finales de línea CRLF (típico en Windows); convertirlo a LF y fijarlo con `.gitattributes` (`*.sh text eol=lf`, y lo mismo para los hooks) |
| `hint: The '.githooks/pre-commit' hook was ignored because it's not set as executable.` | Falta `chmod +x`; en Windows, `git update-index --chmod=+x .githooks/pre-commit` |
| El hook pasa en local y el CI falla | El hook valida ficheros del árbol de trabajo (incluidos los no preparados) y el CI valida el commit; o las versiones de las herramientas difieren |
| `npx: command not found` o `dotnet: command not found` al commitear desde un cliente gráfico | El cliente gráfico no hereda el `PATH` del terminal; invocar con ruta completa o configurar el entorno del cliente |
| Los commits tardan medio minuto | Tests lentos en `pre-commit`; pasarlos a `pre-push` o al CI |
| Con Husky, los hooks desaparecen tras clonar | No se ejecutó `npm install`, y el script `prepare` es el que instala los hooks |
| El hook modifica ficheros y el commit sale sin esos cambios | El formateador cambió ficheros que no se volvieron a preparar; usar `lint-staged` o `stage_fixed` |

## Cuándo no usar hooks

- **Pruebas de integración o E2E**: son lentas y necesitan servicios externos; van al CI.
- **Validaciones que dependen de la red** (`npm install`, llamadas a APIs): fallan sin conexión y entrenan al equipo a saltarse el hook.
- **Como control de seguridad o de cumplimiento**: nada que deba cumplirse obligatoriamente puede depender de un script que cada persona puede omitir.
- **Cuando el equipo ya no los respeta**: un hook al que casi todo el mundo pasa `--no-verify` es peor que no tenerlo, porque da una falsa sensación de control.

## Buenas prácticas avanzadas

- **Reparte el coste: `pre-commit` para lo instantáneo, `pre-push` para lo caro.** Lint y formato aguantan en cada commit; una suite de 40 segundos no. En el segundo caso, la gente acaba usando `--no-verify` por sistema y el hook muere. `pre-push` corre solo al subir, así que tolera validaciones más pesadas.
- **Que el hook trabaje sobre lo preparado, no sobre el disco.** Los cambios sin preparar contaminan el resultado. `lint-staged`, `stage_fixed` o un `git stash --keep-index` garantizan que lo validado es lo que se commitea.
- **Que el hook funcione sin red y sin instalar nada.** Un hook que ejecuta `npm install` o llama a un servicio falla por causas ajenas al código. Todo lo que ejecute debe estar ya en la máquina y ser determinista.
- **Que el hook y el CI ejecuten la misma orden.** Si el hook llama a `npm run lint` y el CI a otra cosa, los resultados divergen. Que ambos usen el mismo script (`make lint`, `npm run lint`) elimina la causa más habitual de «pasa en local y falla en CI».
- **Activar los hooks sin intervención humana.** Si el paso de activación es manual, la mitad del equipo no lo hace. El script `prepare` de Husky, o una línea en el `README` de arranque o en el script de instalación del entorno, lo dejan listo.
- **Invertir en la velocidad del hook.** Por debajo de un par de segundos nadie lo desactiva; por encima de diez, casi todos. Medirlo (`time .githooks/pre-commit`) tiene más impacto que añadir más comprobaciones.

## Documentación oficial

- [githooks (Git)](https://git-scm.com/docs/githooks) — referencia de todos los hooks, sus parámetros y cuándo se ejecutan; consultar al escribir un hook que no sea `pre-commit`.
- [Husky](https://typicode.github.io/husky/) — instalación con `husky init` y ejemplos de hooks; la página *Get Started* es la que enseña el flujo completo.
- [pre-commit](https://pre-commit.com/) — configuración de `.pre-commit-config.yaml`, catálogo de hooks y `autoupdate`.
- [lefthook](https://lefthook.dev/) — instalación en cada gestor de paquetes y referencia de `lefthook.yml` (filtros, paralelismo, `stage_fixed`).

---

*En resumen: un hook es el primer filtro, rápido y barato, que ahorra esperar al servidor, pero cualquiera puede saltárselo con `--no-verify`, y por eso la comprobación que de verdad manda es la del CI en la pull request.*
