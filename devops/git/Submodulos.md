# Submódulos

## ¿Qué es?

Un submódulo es un repositorio de Git **dentro de otro repositorio**. El proyecto principal (el *superproyecto*) no copia el código del otro: solo guarda la dirección del repositorio externo y **el hash de un commit concreto** de él.

## ¿Por qué existe?

A veces el proyecto necesita usar otro proyecto que también está en Git y que evoluciona por su cuenta: una biblioteca de plantillas de correo compartida entre varias aplicaciones, por ejemplo. Copiar y pegar su código haría perder el historial y obligaría a repetir el trabajo cada vez que la biblioteca cambia. Los submódulos permiten **incluir ese repositorio tal cual**, fijado a una versión exacta, sin mezclar los dos historiales.

> Imagina un libro que cita otro libro. En lugar de copiar capítulos enteros, pone una nota: «ver *Tal libro*, edición de 2024». El submódulo es esa referencia precisa a una versión exacta de otro proyecto.

## ¿Cuándo y para qué se usa?

En la tienda online (repositorio `tienda`, servicios `pedidos`, `pagos`, `inventario` y `emails`), las plantillas HTML de los correos viven en su propio repositorio, `emails-plantillas`, porque las usan también otras aplicaciones. Cada aplicación las incorpora como submódulo en `libs/plantillas`.

- **Reutilizar una biblioteca propia** en varios proyectos manteniéndola como repositorio independiente.
- **Fijar una dependencia** a un commit exacto, bajo control propio y sin pasar por un gestor de paquetes.
- **Incluir un componente con ciclo de vida distinto**: el repositorio externo lo mantiene otro equipo y se actualiza cuando se decide.

Es una herramienta potente con fama de incómoda. La sección [Cuándo no usarlos](#cuándo-no-usarlos) compara las alternativas.

## Cómo se guarda un submódulo

Un submódulo son dos piezas dentro del superproyecto:

- Un fichero `.gitmodules` en la raíz, versionado, que dice dónde está el repositorio externo y en qué carpeta se monta.
- Una entrada especial en el árbol de Git (modo `160000`) que guarda el hash del commit al que apunta. No hay ficheros del submódulo en el historial del superproyecto: solo ese hash.

Cada clon del superproyecto lee ambas cosas y sabe qué repositorio traer y en qué versión. Cambiar de versión el submódulo es, por tanto, **un cambio del superproyecto** que hay que commitear.

## Añadir un submódulo

```bash
git submodule add https://github.com/acme/emails-plantillas.git libs/plantillas
```

Clona el repositorio en `libs/plantillas`, crea `.gitmodules` y deja ambos cambios preparados:

```
Cloning into 'libs/plantillas'...
done.
```

```bash
git status --short
```

```
A  .gitmodules
A  libs/plantillas
```

```bash
cat .gitmodules
```

```
[submodule "libs/plantillas"]
	path = libs/plantillas
	url = https://github.com/acme/emails-plantillas.git
```

Como el cambio solo está preparado, falta commitearlo; la entrada guarda el hash exacto:

```bash
git commit -m "Añade plantillas de emails como submódulo"
git ls-tree HEAD libs/
```

```
160000 commit d67c46e885dfa39a74e9001cc303a8840db046b8	libs/plantillas
```

Para ver en cualquier momento a qué versión apunta cada submódulo:

```bash
git submodule status
```

```
 d67c46e885dfa39a74e9001cc303a8840db046b8 libs/plantillas (heads/main)
```

Un `-` delante del hash indica submódulo sin inicializar; un `+`, que la carpeta está en un commit distinto al registrado; una `U`, conflicto.

## Clonar un proyecto que tiene submódulos

Un `git clone` normal trae el superproyecto pero deja **vacías** las carpetas de los submódulos:

```bash
git clone https://github.com/acme/tienda.git
ls tienda/libs/plantillas        # no muestra nada
git submodule status
```

```
-d67c46e885dfa39a74e9001cc303a8840db046b8 libs/plantillas
```

El `-` indica que el submódulo está registrado pero no inicializado. Hay dos formas de resolverlo:

```bash
# Desde el principio
git clone --recurse-submodules https://github.com/acme/tienda.git

# Si ya se clonó sin la opción
git submodule update --init --recursive
```

`--init` registra los submódulos que `.gitmodules` declara y `--recursive` incluye los submódulos de los submódulos. Al terminar, cada carpeta queda en el commit exacto que registra el superproyecto:

```
Submodule path 'libs/plantillas': checked out 'd67c46e885dfa39a74e9001cc303a8840db046b8'
```

Después de un `git pull` del superproyecto que cambie el puntero, el submódulo **no se mueve solo** y `git status` lo muestra como modificado. Se alinea con `git submodule update --init --recursive`, o activando una vez `git config submodule.recurse true`, que hace que `pull`, `switch` y compañía lo actualicen automáticamente.

## Actualizar un submódulo

El superproyecto apunta a un commit fijo, así que actualizar es una decisión explícita. Cuando `emails-plantillas` publica cambios, desde `tienda`:

```bash
git submodule update --remote libs/plantillas
```

```
From https://github.com/acme/emails-plantillas
   d67c46e..3f028dd  main       -> origin/main
Submodule path 'libs/plantillas': checked out '3f028dd75781e2a5ff96de292d59d9be15c88f0d'
```

`--remote` hace un `fetch` del submódulo y lo mueve al último commit de su rama remota (la rama `main`, salvo que `.gitmodules` indique otra con `branch = ...`). Sin `--remote`, `update` devuelve el submódulo al commit registrado.

El superproyecto ve ahora el submódulo modificado. Antes de commitear conviene mirar qué entra:

```bash
git status --short
git diff --submodule=log
```

```
 M libs/plantillas
Submodule libs/plantillas d67c46e..3f028dd:
  > Pie nuevo
```

Cada línea con `>` es un commit del submódulo que entra. Un `git diff` normal solo mostraría dos hashes. Para que `log` sea el formato por defecto: `git config --global diff.submodule log`.

Para fijar la nueva versión, se commitea el cambio de puntero:

```bash
git add libs/plantillas
git commit -m "Actualiza plantillas de emails: pie nuevo"
```

Quien clone o actualice el superproyecto después recibirá exactamente esa versión.

### Fijar una versión concreta

Para quedarse en una versión estable (una etiqueta, no la punta de `main`), se entra en el submódulo, se cambia al commit deseado y se commitea el puntero en el superproyecto:

```bash
cd libs/plantillas
git fetch --tags
git switch --detach v2.3.0
cd ../..
git add libs/plantillas
git commit -m "Fija plantillas de emails en v2.3.0"
```

## Trabajar dentro de un submódulo

Al inicializarse, un submódulo queda en **detached HEAD**: apunta a un commit, no a una rama.

```bash
cd libs/plantillas
git status
```

```
HEAD detached at d67c46e
nothing to commit, working tree clean
```

Para modificarlo hay que subirse a una rama **antes** de commitear; los commits hechos en detached HEAD no pertenecen a ninguna rama y se pierden al mover el submódulo (ver [Switch](Switch.md) y [Ramas](Ramas.md)). El orden correcto, con dos pushes:

```bash
cd libs/plantillas
git switch main
# ...cambios...
git commit -am "Corrige el asunto del correo de pedido"
git push                        # 1.º: el submódulo
cd ../..
git add libs/plantillas
git commit -m "Actualiza plantillas"
git push                        # 2.º: el superproyecto
```

El orden importa: si se sube primero el superproyecto, queda apuntando a un commit que no existe en el remoto del submódulo.

## Errores frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| La carpeta `libs/plantillas` existe pero está vacía | Clon sin `--recurse-submodules` | `git submodule update --init --recursive` |
| `git status` muestra `modified: libs/plantillas (new commits)` sin haber tocado nada | Se hizo `pull` o `switch` en el superproyecto y el submódulo se quedó en el commit anterior | `git submodule update --init --recursive`, o `git config submodule.recurse true` |
| `Fetched in submodule path 'libs/plantillas', but it did not contain 3f028dd.... Direct fetching of that commit failed.` | El superproyecto se subió apuntando a un commit que nunca se subió en el submódulo | Quien lo hizo debe entrar en el submódulo y hacer `git push`; para evitarlo, ver [Buenas prácticas avanzadas](#buenas-prácticas-avanzadas) |
| `fatal: 'libs/plantillas' already exists in the index` | La carpeta ya estaba versionada como ficheros normales | `git rm -r --cached libs/plantillas`, y repetir `git submodule add` |
| Los commits hechos dentro del submódulo «desaparecen» tras `git submodule update` | Se commiteó en detached HEAD | Recuperar el hash con `git reflog` dentro del submódulo y crear una rama: `git branch rescate <hash>` |
| `Please make sure you have the correct access rights` al clonar el submódulo | La URL de `.gitmodules` es privada o está en un formato (SSH/HTTPS) que no corresponde a las credenciales | Ver [Remotos](Remotos.md) y [Tokens de acceso en remotos](Tokens-de-Acceso-en-Remotos.md); corregir la `url` y ejecutar `git submodule sync` |

Para quitar un submódulo hacen falta tres pasos, porque deja rastro en tres sitios:

```bash
git submodule deinit -f libs/plantillas
git rm -f libs/plantillas
rm -rf .git/modules/libs/plantillas
```

## Cuándo no usarlos

Un submódulo añade pasos a cada clon, a cada `pull` y a cada actualización. Antes de adoptarlo, comparar:

| Necesidad | Mejor opción |
|---|---|
| La dependencia se publica como paquete (npm, NuGet, PyPI) | **Gestor de paquetes**: versiones semánticas, resolución automática y sin pasos extra al clonar |
| Se quiere el código del otro repositorio dentro del propio, sin que nadie tenga que saber que viene de fuera | **`git subtree`**: copia el contenido y su historial en el repositorio; se clona sin pasos extra, a cambio de un historial más pesado y de comandos de sincronización más enrevesados |
| Código compartido entre servicios del mismo equipo que se cambia a la vez | **Monorepo**: un solo repositorio y un solo commit para cambiar ambos lados |
| Un componente de terceros que se actualiza raramente | **Copia vendida** (carpeta `vendor/`) con una nota de procedencia |
| Dos repositorios que deben seguir siendo independientes, con versión fijada y control exacto de cuándo se actualiza | **Submódulo** |

## Buenas prácticas avanzadas

- **Evita el push a medias con `--recurse-submodules`.** Si se commitea dentro del submódulo y se sube solo el superproyecto, el resto del equipo apunta a un commit inexistente en el remoto. Con `git push --recurse-submodules=check`, Git aborta si detecta el problema; con `=on-demand`, sube primero los submódulos pendientes. Se puede dejar fijo con `git config push.recurseSubmodules check`.
- **`git config submodule.recurse true` elimina la mayor fuente de confusión.** Con él, `pull`, `switch`, `checkout` y `fetch` actualizan los submódulos solos y desaparecen los «modificados» fantasma tras cambiar de rama.
- **En CI, clona con los submódulos explícitamente.** Un `checkout` por defecto deja la carpeta vacía y el build falla con ficheros que no existen. En GitHub Actions, `actions/checkout` admite `submodules: recursive` (ver [GitHub Actions](../ci-cd/GitHub-Actions.md)), y para submódulos privados hace falta un token con acceso a ese repositorio.
- **Usa URLs relativas en `.gitmodules` si ambos repositorios viven en el mismo servidor.** `url = ../emails-plantillas.git` funciona igual con HTTPS que con SSH y se adapta al servidor desde el que se clonó el superproyecto.
- **`git submodule foreach` ejecuta un comando en todos los submódulos.** `git submodule foreach 'git fetch --tags'` evita entrar uno a uno cuando hay varios.

## Documentación oficial

- [git-submodule](https://git-scm.com/docs/git-submodule) — referencia de cada subcomando; consultar `update` (opciones `--remote`, `--init`) y `foreach`.
- [Pro Git: Submódulos](https://git-scm.com/book/en/v2/Git-Tools-Submodules) — capítulo con flujos de trabajo completos, problemas típicos y cómo trabajar con submódulos en equipo.

---

*En resumen: un submódulo es una referencia precisa a un commit de otro repositorio dentro del tuyo; reutilizas código ajeno fijado a una versión exacta, a cambio de recordar clonarlo con `--recurse-submodules`, subir primero el submódulo y commitear cada cambio de puntero.*
