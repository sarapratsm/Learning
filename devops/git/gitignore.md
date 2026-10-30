# gitignore

## ¿Qué es?

`.gitignore` es un archivo de texto donde se listan, con patrones, los archivos y carpetas que Git debe **ignorar**: no los muestra como pendientes en `git status`, no los prepara con `git add .` y no entran en el historial.

## ¿Por qué existe?

No todo lo que hay en la carpeta de un proyecto debe versionarse. Hay archivos que se regeneran solos (dependencias descargadas, resultados de compilación), archivos propios del entorno de cada persona (carpetas del editor, ficheros del sistema operativo) y archivos que nunca deben salir de una máquina (contraseñas, claves de API). Sin una lista de exclusión, `git add .` los recogería todos y `git status` mostraría cientos de líneas de ruido que esconden los cambios reales.

> Es la lista de «no molestar» de Git: los archivos que coinciden con un patrón se tratan como si no existieran.

## ¿Cuándo y para qué se usa?

Se crea al empezar el proyecto, normalmente a partir de una plantilla del lenguaje o framework, y se ajusta cuando aparece algo nuevo que no debe versionarse. En la tienda online `tienda`, con los servicios `pedidos`, `pagos`, `inventario` y `emails`, las exclusiones típicas son el directorio de compilación de cada servicio, el fichero `.env` con las credenciales de la base de datos y los registros (`*.log`) que generan los contenedores.

---

## Escribir un `.gitignore`

El archivo se llama `.gitignore` y vive en la raíz del repositorio (también puede haber otros en subcarpetas, que aplican solo a su ámbito). Cada línea es un patrón; las líneas que empiezan por `#` son comentarios y las vacías se ignoran.

```gitignore
# Dependencias y compilación
node_modules/
bin/
obj/

# Configuración local con credenciales
.env

# Registros
*.log

# Ficheros del sistema operativo
.DS_Store
Thumbs.db
```

Se versiona como cualquier otro archivo (`git add .gitignore` y commit), para que todo el equipo ignore lo mismo.

### Sintaxis de patrones

| Patrón | Qué ignora |
|---|---|
| `*.log` | Cualquier archivo que acabe en `.log`, en cualquier carpeta. |
| `debug.log` | Archivos llamados `debug.log`, en cualquier carpeta. |
| `/debug.log` | Solo el de la raíz del repositorio; la `/` inicial ancla el patrón. |
| `build/` | Cualquier **carpeta** llamada `build` y todo su contenido; la `/` final limita el patrón a carpetas. |
| `docs/*.pdf` | Los PDF directamente dentro de `docs/`, no en sus subcarpetas. |
| `docs/**/*.pdf` | Los PDF en `docs/` y en cualquier nivel de subcarpetas. |
| `report?.txt` | `?` equivale a un carácter: `report1.txt`, `reportA.txt`. |
| `*.py[co]` | Un carácter de la lista: `.pyc` y `.pyo`. |
| `!importante.log` | Negación: vuelve a incluir lo que un patrón anterior ignoraba. |

El orden importa: cuando varios patrones coinciden, **gana el último**. Por eso la negación siempre va después del patrón que corrige.

### La negación `!` y su trampa

Si se ignora una carpeta entera, Git ni siquiera entra en ella, así que no puede rescatar un archivo de dentro:

```gitignore
# ❌ No funciona: logs/ queda excluida y Git no mira dentro
logs/
!logs/importante.log
```

```bash
git check-ignore -v logs/importante.log
```

```
.gitignore:1:logs/	logs/importante.log
```

La salida confirma que el patrón de la línea 1 sigue ganando. La solución es ignorar el **contenido** de la carpeta, no la carpeta:

```gitignore
# ✅ Funciona: se ignora el contenido y se rescata un archivo
logs/*
!logs/importante.log
```

## Averiguar por qué se ignora algo: `git check-ignore -v`

Cuando un archivo «no aparece» o no se deja añadir, `check-ignore -v` dice qué archivo de ignore y qué línea son responsables:

```bash
git check-ignore -v debug.log .env pedidos/app.py
```

```
.gitignore:2:*.log	debug.log
.gitignore:1:.env	.env
```

Cada línea tiene el formato `origen:línea:patrón <tab> ruta`. Los archivos que no se ignoran (como `pedidos/app.py`) no aparecen en la salida, y el código de salida es 1 si ninguno coincide. Los archivos **ya rastreados** tampoco se reportan, aunque un patrón los cubra; con `--no-index` se comprueba el patrón sin tener en cuenta el seguimiento. El origen puede ser también el ignore global o `.git/info/exclude`.

Si se intenta añadir un archivo ignorado, Git avisa en lugar de callar:

```bash
git add a.log
```

```
The following paths are ignored by one of your .gitignore files:
a.log
hint: Use -f if you really want to add them.
```

`git add -f a.log` lo fuerza. Para ver los archivos ignorados presentes en disco: `git status --ignored`.

## Ignorar lo que ya está rastreado

`.gitignore` solo afecta a archivos que Git **aún no rastrea**. Si `.env` se confirmó antes de añadirlo a la lista, Git sigue vigilándolo y mostrando sus cambios. Hay que dejar de rastrearlo sin borrarlo del disco:

```bash
echo ".env" >> .gitignore
git rm --cached .env
git status -s
```

```
rm '.env'
D  .env
?? .gitignore
```

`--cached` quita el archivo del índice pero lo deja en el disco (`D  .env` significa «eliminado del seguimiento, preparado»). Se confirma el borrado junto al `.gitignore`:

```bash
git add .gitignore
git commit -m "Deja de rastrear .env"
```

Para carpetas, `git rm -r --cached <carpeta>`. Esto saca el archivo del **futuro** del proyecto; sigue existiendo en todos los commits anteriores.

### Si el archivo era un secreto

Quitar un secreto con `git rm --cached` no lo elimina del historial: cualquiera con acceso al repositorio puede recuperarlo de un commit antiguo. Lo que hay que hacer, por este orden:

1. **Revocar y regenerar el secreto** (contraseña, token, clave). Es lo único que lo invalida de verdad.
2. Dejar de rastrear el archivo (el paso anterior) y reconfigurar el proyecto para leerlo de fuera del repositorio.
3. Solo después, y si es necesario, reescribir el historial para borrarlo; es una operación invasiva que obliga a todo el equipo a volver a clonar.

El razonamiento completo y las alternativas para gestionar secretos están en [Por qué los secretos no van a Git](../../seguridad/gestion-de-secretos-en-desarrollo/Por-Que-Los-Secretos-No-Van-A-Git.md).

## Tres lugares donde ignorar, tres alcances

| Lugar | Se versiona | Para qué |
|---|---|---|
| `.gitignore` del repositorio | Sí, lo comparte el equipo | Lo que ignora **todo el proyecto**: compilación, dependencias, `.env`. |
| `.git/info/exclude` | No, es local de ese clon | Exclusiones personales de un solo repositorio, sin tocar nada compartido. |
| Ignore global (`core.excludesFile`) | No, es de tu usuario | Manías del entorno que valen para todos tus repositorios. |

Configurar el ignore global una vez:

```bash
git config --global core.excludesFile ~/.gitignore_global
```

Y listar en ese archivo lo propio del entorno (`.idea/`, `.vscode/`, `.DS_Store`, `*.swp`). Así el `.gitignore` del proyecto no se llena de las preferencias de cada persona. Para una exclusión puntual en un solo clon:

```bash
echo "notas-personales.md" >> .git/info/exclude
```

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Se añadió el patrón y el archivo sigue apareciendo en `git status` | El archivo ya estaba rastreado. Hace falta `git rm --cached`. |
| `!archivo` no hace nada | Una carpeta padre está ignorada con `carpeta/`. Cambiar a `carpeta/*`. |
| `git add` responde `The following paths are ignored by one of your .gitignore files` | El patrón ignora ese archivo. Averiguar cuál con `git check-ignore -v`; `-f` solo si es deliberado. |
| Un patrón ignora más de lo esperado (`build` oculta también un archivo `build`) | Sin la `/` final el patrón afecta a archivos y carpetas. Usar `build/`. |
| El patrón no funciona en una línea con comentario al final (`*.log # registros`) | No hay comentarios en línea: el `#` forma parte del patrón. Poner el comentario en su propia línea. |
| Un archivo con espacios al final del patrón no coincide | Los espacios finales se ignoran salvo escapados con `\`. |

## Cuándo no usarlo

- **Para proteger secretos ya subidos**: no sirve, como se ha visto arriba.
- **Para variaciones locales de un archivo que debe estar versionado** (una `appsettings.json` con otros valores en tu máquina): ignorarlo no es posible porque ya se rastrea. Se versiona una plantilla (`appsettings.example.json`) y el archivo real se ignora.
- **Para dejar una carpeta vacía en el repositorio**: Git no versiona carpetas vacías; la convención es un archivo `.gitkeep` dentro.

## Buenas prácticas avanzadas

- **Parte de una plantilla y ajusta** — el repositorio `github/gitignore` reúne plantillas por lenguaje y framework; es más fiable que reconstruir la lista a mano y evita olvidos clásicos.
- **Versiona una plantilla del archivo ignorado** — un `.env.example` con las claves y sin valores documenta qué configuración necesita `tienda` sin exponer ninguna.
- **`git status --ignored` antes de un `git clean -fdx`** — `-x` borra también lo ignorado (incluido tu `.env` local); la lista de `--ignored` indica qué se perdería.
- **Una carpeta ignorada no se explora, y eso es rendimiento** — ignorar `node_modules/` por carpeta (no por `node_modules/*`) evita que Git recorra decenas de miles de archivos en cada `git status`.
- **Los patrones se evalúan relativos al archivo `.gitignore` que los contiene** — un `.gitignore` en `pagos/` con `/bin/` ignora solo `pagos/bin/`; útil en monorepos con una convención distinta por servicio.

## Documentación oficial

- [gitignore](https://git-scm.com/docs/gitignore) — la sintaxis exacta de los patrones y la precedencia entre ficheros de ignore; la sección «Pattern format» resuelve la mayoría de dudas.
- [Pro Git: Guardando cambios en el repositorio](https://git-scm.com/book/es/v2/Fundamentos-de-Git-Guardando-cambios-en-el-Repositorio) — incluye una sección sobre ignorar archivos con ejemplos.

## Recursos didácticos

- [github/gitignore](https://github.com/github/gitignore) — colección de plantillas `.gitignore` por lenguaje, framework y editor.

---

*En resumen: `.gitignore` decide qué nunca entra en el historial, pero solo vale antes de que algo se rastree: lo ya confirmado exige `git rm --cached`, y un secreto ya subido exige además revocarlo.*
