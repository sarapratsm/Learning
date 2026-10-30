# Repositorio

## ¿Qué es?

Un repositorio (o *repo*) es una carpeta que Git vigila. Contiene los archivos del proyecto y, dentro de una subcarpeta oculta llamada `.git`, todo el historial de cambios.

## ¿Por qué existe?

Git no vigila todo el disco: necesita saber qué carpeta debe seguir. Convertir una carpeta en repositorio es declarar «a partir de aquí, se registra el historial de estos archivos». Toda la información (commits, ramas, configuración local) vive en `.git`; si se borra, se pierde el historial pero se conservan los archivos actuales.

> Si ya conoces las bases de datos, piensa en `.git` como una pequeña base de datos que guarda cada versión del proyecto, y en el resto de archivos como la versión que está «abierta» en este momento.

## ¿Cuándo y para qué se usa?

| Situación | Comando |
|---|---|
| Empiezo un proyecto desde cero, o quiero versionar una carpeta que ya existe | `git init` |
| Quiero trabajar sobre un proyecto que ya existe en un servidor | `git clone` |
| Quiero saber en qué estado está mi copia de trabajo | `git status` |

En la tienda online de esta colección, la primera persona crea el repositorio `tienda` con `init` y sube el código a un servidor; todas las demás lo obtienen con `clone`.

## Crear un repositorio: `git init`

Se crea la carpeta, se entra en ella y se inicializa:

```bash
mkdir tienda
cd tienda
git init -b main
```

```
Initialized empty Git repository in C:/Users/ana/tienda/.git/
```

`init` crea la carpeta `.git` con la estructura mínima; a partir de ese momento la carpeta tiene historial (vacío). `-b main` fija el nombre de la rama inicial; sin él, se usa `init.defaultBranch` o, si no está configurado, `master` ([Instalación y configuración](Instalacion-y-configuracion.md)).

Si la carpeta ya contiene archivos, `git init` no los toca ni los guarda: quedan como *no rastreados* hasta que se preparen y se confirmen.

```bash
git status
```

```
On branch master

No commits yet

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	README.md
	pagos/
	pedidos/

nothing added to commit but untracked files present (use "git add" to track)
```

`git init` no sube nada a internet y no guarda nada por sí solo: crea el lugar donde se guardará. Preparar archivos es el siguiente paso ([Área de preparación](Area-de-preparacion.md)) y confirmarlos, el posterior ([Commits](Commits.md)).

## Obtener un repositorio existente: `git clone`

```bash
git clone https://github.com/usuario/tienda.git
```

```
Cloning into 'tienda'...
done.
```

`clone` crea la carpeta `tienda`, descarga **todo el historial**, deja desplegada la rama por defecto y registra el origen con el nombre `origin`. Es una copia completa e independiente: a partir de ahí se puede trabajar sin conexión ([Remotos](Remotos.md) explica cómo volver a sincronizar).

Para elegir el nombre de la carpeta destino se añade como último argumento:

```bash
git clone https://github.com/usuario/tienda.git tienda-pruebas
```

### Variantes de `clone`

| Variante | Qué hace | Cuándo |
|---|---|---|
| `--branch rel` | Deja desplegada esa rama o tag en vez de la rama por defecto | Se necesita otra rama desde el principio |
| `--single-branch` | Descarga solo el historial de una rama | Ahorrar descarga; combinable con `--branch` |
| `--depth 1` | Historial truncado: solo el último commit (clon *superficial*) | CI, o leer código sin importar el historial |
| `--filter=blob:none` | Descarga el contenido de los archivos solo cuando se necesita | Repositorios enormes con historial que sí interesa |

Efecto de `--depth 1` en un repositorio con cinco commits:

```bash
git clone --depth 1 file:///ruta/tienda sup
cd sup
git log --oneline
```

```
49ecf29 c3
```

Solo hay un commit, y el hash del anterior se anota en `.git/shallow`. Con `--branch` y `--single-branch`, solo existe esa rama en la copia:

```bash
git clone --branch rel --single-branch /ruta/tienda b
cd b
git branch -a
```

```
* rel
  remotes/origin/rel
```

Un clon superficial no sirve para todo: no se puede buscar en el historial antiguo, y algunas operaciones de fusión o `git bisect` fallan. Para recuperar el historial: `git fetch --unshallow`.

## Qué hay dentro de `.git`

```bash
ls .git
```

```
COMMIT_EDITMSG  HEAD  config  description  hooks  index  info  logs  objects  refs
```

| Entrada | Contenido |
|---|---|
| `objects/` | Todos los commits, trees y blobs (la «base de datos») |
| `refs/` | Los punteros de ramas (`refs/heads/`) y tags (`refs/tags/`) |
| `HEAD` | Qué rama o commit está desplegado ahora: `ref: refs/heads/master` |
| `index` | El área de preparación ([Área de preparación](Area-de-preparacion.md)) |
| `config` | La configuración local de ese repositorio |
| `hooks/` | Scripts que Git ejecuta en ciertos momentos (antes de un commit, antes de un push) |
| `logs/` | El historial de movimientos de `HEAD` y de las ramas (alimenta `git reflog`) |

La carpeta no se toca a mano: se usan los comandos de Git. Sí es útil mirarla para entender qué ocurre.

Dos consecuencias prácticas: el repositorio es **autocontenido y portable** (copiar la carpeta a otro disco da un repositorio idéntico), y lo que está solo en `.git/config` o en `hooks/` **no viaja con `push`**: el resto del equipo no lo ve.

## Comprobar el estado: `git status`

Es el comando más usado: dice en qué rama se está, qué cambios hay preparados, cuáles no y qué archivos son nuevos.

```bash
git status
```

```
On branch master
Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
	modified:   pedidos/app.py

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
	modified:   pagos/app.py
```

Y su versión corta, con `-sb` (*short* + *branch*), que muestra dos columnas de letras: la primera es el área de preparación, la segunda el directorio de trabajo.

```
## master
M  pedidos/app.py
 M pagos/app.py
?? notas.txt
```

| Código | Significado |
|---|---|
| `??` | Archivo no rastreado (Git no lo conoce) |
| `A ` | Nuevo, preparado |
| `M ` | Modificado y preparado |
| ` M` | Modificado, sin preparar |
| `MM` | Modificado, preparado y vuelto a modificar |

Fuera de un repositorio, `status` falla (ver errores frecuentes). Para saber en qué carpeta está la raíz del repositorio actual: `git rev-parse --show-toplevel`.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `fatal: not a git repository (or any of the parent directories): .git` | Se está fuera de un repositorio: falta `git init` o hay que hacer `cd` a la carpeta correcta |
| `fatal: destination path 'tienda' already exists and is not an empty directory.` | `clone` no sobrescribe una carpeta con contenido; borrarla, vaciarla o indicar otro destino |
| `warning: re-init: ignored --initial-branch=main` | Se ejecutó `git init -b` en una carpeta que ya era un repositorio: no cambia la rama existente |
| Dos repositorios anidados: la carpeta interior aparece en `status` como una sola entrada | Un repositorio dentro de otro se trata como unidad aparte; para componerlos a propósito, ver [Submódulos](Submodulos.md) |
| Se hizo `git init` en la carpeta personal o en `C:\` | Git escanea todo lo que hay debajo; borrar la carpeta `.git` creada por error |
| Nada se guardó tras `git init` | `init` solo crea el repositorio; hacen falta `add` y `commit` |

## Buenas prácticas avanzadas

- **Varias carpetas de trabajo sobre un mismo repositorio con `git worktree`.** `git worktree add ../tienda-hotfix hotfix-precios` crea una segunda carpeta con esa rama desplegada, compartiendo el mismo `.git`. Permite tener una función a medias en una carpeta y un arreglo urgente en otra, sin stash ni clones duplicados.
- **Clona ligero en CI y pesado en local.** `--depth 1` basta para compilar y probar; para trabajar de verdad se necesita el historial. `--filter=blob:none` conserva el historial completo y descarga los contenidos bajo demanda, una opción intermedia en repositorios con años de archivos grandes.
- **Mira `.git/config` para entender un comportamiento raro.** Los remotos, las ramas que siguen a otras y los ajustes locales viven ahí; una URL de remoto equivocada o una opción olvidada se ven al instante, y es el único sitio donde ese estado existe.
- **Un repositorio *bare* es un repositorio sin copia de trabajo.** `git init --bare tienda.git` crea solo lo que normalmente está dentro de `.git`; es el formato de los servidores que reciben `push`, porque no hay archivos desplegados que se puedan pisar.

## Documentación oficial

- [git init](https://git-scm.com/docs/git-init) — opciones como `--bare`, `-b` y `--separate-git-dir`; útil para configurar servidores o plantillas.
- [git clone](https://git-scm.com/docs/git-clone) — referencia de `--depth`, `--filter`, `--branch` y `--single-branch`, con sus limitaciones.
- [Disposición de un repositorio](https://git-scm.com/docs/gitrepository-layout) — qué es cada archivo de `.git`, para quien quiere entender o depurar el almacenamiento.
- [Pro Git: Obteniendo un repositorio Git](https://git-scm.com/book/es/v2/Fundamentos-de-Git-Obteniendo-un-repositorio-Git) — `init` y `clone` explicados con el flujo inicial completo.

---

*En resumen: un repositorio es una carpeta con memoria — `init` la crea, `clone` la copia de otro sitio y `status` dice siempre cómo está.*
