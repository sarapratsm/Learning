# Instalación y configuración de Git

## ¿Qué es?

El primer paso antes de usar Git: instalarlo y decirle quién eres y cómo quieres que se comporte. La configuración se guarda en archivos de texto y se maneja con el comando `git config`.

## ¿Por qué existe?

Git adjunta a cada commit un nombre y un correo de autor, y necesita decisiones que varían de un equipo a otro: qué editor abrir, cómo tratar los finales de línea, cómo se llama la rama inicial. Sin identidad, Git se niega a crear commits:

```
Author identity unknown

*** Please tell me who you are.

Run

  git config --global user.email "you@example.com"
  git config --global user.name "Your Name"

to set your account's default identity.
Omit --global to set the identity only in this repository.
```

La configuración se hace una vez por ordenador y rara vez se vuelve a tocar.

## ¿Cuándo y para qué se usa?

Justo después de instalar Git en un equipo nuevo, antes del primer commit. Después, cuando cambia algo: otro correo para un cliente, un alias nuevo, una credencial caducada. En la tienda online de esta colección, cada persona del equipo configura una vez su identidad y sus preferencias, y el repositorio `tienda` hereda esos valores.

## Instalar Git

Se comprueba si ya está:

```bash
git --version
```

```
git version 2.54.0.windows.1
```

| Sistema | Instalación habitual |
|---|---|
| Windows | `winget install --id Git.Git -e`, o el instalador de [git-scm.com](https://git-scm.com/install/windows). Incluye *Git Bash* y *Git Credential Manager* |
| macOS | `brew install git`, o `xcode-select --install` (versión de las herramientas de Apple, más antigua) |
| Debian/Ubuntu | `sudo apt install git` |
| Fedora | `sudo dnf install git` |

En Windows, el instalador hace preguntas; los valores por defecto sirven. Tres merecen atención: el editor por defecto (si no se conoce Vim, elegir otro), el nombre de la rama inicial (se puede fijar después con `init.defaultBranch`) y el tratamiento de finales de línea (se explica más abajo).

## Los tres ámbitos de configuración

`git config` lee y escribe en tres archivos. Cuando una misma clave aparece en varios, **gana el ámbito más específico**:

| Ámbito | Flag | Archivo | Aplica a |
|---|---|---|---|
| Sistema | `--system` | `etc/gitconfig` dentro de la instalación | Todas las personas del equipo |
| Global (usuario) | `--global` | `~/.gitconfig` | Todos tus repositorios |
| Local | `--local` (por defecto) | `.git/config` del repositorio | Solo ese repositorio |

Sin flag, `git config clave valor` escribe en el ámbito local, por lo que **debe ejecutarse dentro de un repositorio**. Para ver qué valor está vigente y de dónde sale:

```bash
git config --list --show-origin --show-scope
git config --show-origin user.email
```

```
global	user.name=Sara
global	user.email=s@e.com
global	alias.st=status -sb
local	core.repositoryformatversion=0
```

El archivo global es de texto y se puede editar a mano; es el resultado de los comandos:

```gitconfig
[user]
	name = Sara
	email = s@e.com
[alias]
	st = status -sb
[init]
	defaultBranch = main
```

## Identidad

Es lo único obligatorio:

```bash
git config --global user.name "Ana García"
git config --global user.email "ana@tienda.example"
```

Se aplica a todos los commits nuevos de todos los repositorios. Quien necesita otra identidad en un proyecto concreto ejecuta los mismos comandos sin `--global` dentro de ese repositorio. Los commits ya hechos no cambian de autor.

La identidad no es una autenticación: cualquiera puede escribir cualquier nombre. Quien demuestra la identidad ante un servidor son las credenciales (más abajo) y, opcionalmente, la firma de commits.

## Ajustes que conviene fijar al empezar

### Rama inicial: `init.defaultBranch`

```bash
git config --global init.defaultBranch main
```

Sin él, `git init` crea la rama `master` (la salida de `git status` en un repositorio nuevo sin configurar es `On branch master`). Con él, los repositorios nuevos empiezan en `main`, el nombre que usan por defecto GitHub y GitLab. Afecta solo a los repositorios que se creen después.

### Finales de línea: `core.autocrlf`

Windows termina las líneas con dos caracteres (CRLF) y Linux y macOS con uno (LF). Si cada persona del equipo usa un sistema, aparecen diffs en los que «cambia todo el archivo» sin que nadie lo haya tocado. Un síntoma típico en Windows es este aviso al hacer `git add`:

```
warning: in the working copy of 'README.md', LF will be replaced by CRLF the next time Git touches it
```

| Valor | Efecto | Para |
|---|---|---|
| `true` | Convierte a LF al confirmar y a CRLF al extraer | Windows |
| `input` | Convierte a LF al confirmar, no toca al extraer | macOS y Linux |
| `false` | No convierte nada | Equipos que lo resuelven con otra herramienta |

```bash
git config --global core.autocrlf true     # Windows
git config --global core.autocrlf input    # macOS / Linux
```

La solución más robusta es declararlo en el propio repositorio, para que no dependa de la configuración de cada persona: un archivo `.gitattributes` en la raíz con `* text=auto`.

### Estrategia de `git pull`: `pull.rebase`

`git pull` descarga y luego integra. Sin configurar, Git avisa de que no sabe cómo y pide elegir:

```
hint: You have divergent branches and need to specify how to reconcile them.
```

```bash
git config --global pull.rebase false   # integra con un commit de fusión (comportamiento clásico)
git config --global pull.rebase true    # recoloca tus commits encima de los descargados
git config --global pull.ff only        # solo avanza si no hay divergencia; si la hay, falla
```

Cuál elegir depende del flujo del equipo: [Fusión y conflictos](Fusion-y-conflictos.md) explica la fusión, [Rebase](Rebase.md) la alternativa y [Remotos](Remotos.md) el comportamiento de `pull`.

### Editor: `core.editor`

Git abre un editor para los mensajes de commit largos. Si el de por defecto incomoda:

```bash
git config --global core.editor "code --wait"
```

El `--wait` hace que Git espere a que se cierre la pestaña antes de continuar.

## Alias

Un alias convierte un comando largo en uno corto. Se guardan en la sección `[alias]`:

```bash
git config --global alias.st "status -sb"
git config --global alias.lg "log --oneline --graph --all"
```

```bash
git st
```

```
## master
 M pagos/app.py
 M pedidos/app.py
```

Los alias que empiezan por `!` ejecutan un comando de shell: `alias.hoy "!git log --since=midnight --oneline"`.

## Identidades distintas por carpeta

Con correo de trabajo y correo personal, depender de recordar la configuración repo a repo termina en commits personales con el correo de la empresa. `includeIf` carga otro archivo según la ubicación del repositorio:

```gitconfig
[includeIf "gitdir:~/trabajo/"]
    path = ~/trabajo/.gitconfig
```

Y en `~/trabajo/.gitconfig`:

```gitconfig
[user]
    email = ana@empresa.example
```

Todo repositorio bajo `~/trabajo/` (la barra final es necesaria) usa ese correo automáticamente.

## Credenciales

Para hablar con un remoto, Git necesita demostrar quién eres. Hay dos caminos:

| Protocolo | Cómo se autentica | Detalle |
|---|---|---|
| HTTPS | Usuario y token de acceso (no la contraseña de la cuenta) | [Tokens de acceso en remotos](Tokens-de-Acceso-en-Remotos.md) |
| SSH | Par de claves; la pública se registra en el servicio | [Remotos](Remotos.md) |

Para HTTPS, un *credential helper* guarda el token para no teclearlo cada vez. En Windows viene incluido *Git Credential Manager*; en macOS, el llavero del sistema:

```bash
git config --global credential.helper manager         # Windows (Git Credential Manager)
git config --global credential.helper osxkeychain     # macOS
git config --global credential.helper 'cache --timeout=3600'   # Linux: en memoria 1 hora
```

Evita `credential.helper store`: guarda el token en texto plano en `~/.git-credentials`.

## Firma de commits

Git permite firmar criptográficamente cada commit para que el servicio muestre una insignia «verificado». Se activa con `commit.gpgsign true` y una clave configurada en `user.signingkey` (GPG, o una clave SSH con `gpg.format ssh`). Es opcional y su configuración excede esta ficha: la referencia está en la documentación de `git config`.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `Author identity unknown` / `fatal: unable to auto-detect email address` | Faltan `user.name` y `user.email` |
| El correo de un commit no coincide con la cuenta de GitHub | El correo configurado no está asociado a esa cuenta: los commits no se vinculan a tu perfil |
| `git config clave valor` no cambia nada «global» | Se ejecutó sin `--global`: se escribió solo en el `.git/config` de ese repositorio |
| Cambió `init.defaultBranch` pero un repositorio sigue en `master` | El ajuste solo afecta a repositorios creados después |
| `warning: ... LF will be replaced by CRLF` | `core.autocrlf` activo en Windows; es un aviso informativo, no un error |
| Pide usuario y contraseña en cada `push` por HTTPS | No hay credential helper, o se está usando la contraseña de la cuenta en vez de un token |

## Buenas prácticas avanzadas

- **Fija los finales de línea en el repositorio, no en cada máquina.** `core.autocrlf` es una preferencia personal; `.gitattributes` con `* text=auto` viaja con el repositorio y da el mismo resultado a todo el equipo. Así un equipo mixto Windows/Linux no depende de que cada persona configure bien su equipo.
- **`push.autoSetupRemote` elimina el error más repetido de Git.** Con `git config --global push.autoSetupRemote true`, el primer `git push` de una rama nueva crea y vincula la rama remota, y no hay que copiar el comando que Git sugiere tras `fatal: The current branch ... has no upstream branch`.
- **`git config --show-origin` resuelve los «¿de dónde sale este valor?».** Cuando un ajuste no se comporta como se espera, casi siempre hay otra definición en un ámbito de mayor prioridad o en un archivo incluido por `includeIf`; el origen lo delata en una línea.
- **Evita `git config --system` salvo administración de equipos.** Se pierde al reinstalar, no viaja con la persona y es el primer sitio que nadie mira cuando algo se comporta distinto en dos ordenadores.
- **Revisa `git config --global --list` al entrar en un equipo prestado o de CI.** Un `user.email` ajeno o un `credential.helper store` heredado son la causa típica de commits con autor equivocado y de tokens guardados en claro.

## Documentación oficial

- [git config](https://git-scm.com/docs/git-config) — referencia completa de claves y de `includeIf`; se consulta con búsqueda de texto para una clave concreta, no se lee entera.
- [Pro Git: Configurando Git por primera vez](https://git-scm.com/book/es/v2/Inicio---Sobre-el-Control-de-Versiones-Configurando-Git-por-primera-vez) — los tres niveles, identidad y editor, explicados paso a paso.
- [Descargas de Git](https://git-scm.com/install/) — instaladores y comandos para Windows, macOS y Linux.

---

*En resumen: instala Git, preséntate una vez con `user.name` y `user.email`, fija tres o cuatro ajustes globales y sabe preguntar a `git config --show-origin` de dónde sale cada valor.*
