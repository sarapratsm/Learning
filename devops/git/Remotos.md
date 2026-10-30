# Remotos (remote, fetch, pull, push)

## ¿Qué es?

Un *remoto* es otra copia del mismo repositorio, alojada en otro sitio (un servidor de GitHub o GitLab, o incluso otra carpeta de disco). Se le da un nombre corto y, con `fetch`, `pull` y `push`, se intercambian commits con él.

## ¿Por qué existe?

Git es distribuido: cada persona tiene el historial completo en su máquina y puede trabajar sin conexión. Eso no resuelve cómo ponerse de acuerdo. Hace falta un punto común al que todas las copias suban y del que todas bajen, y un mecanismo para saber qué tiene cada lado que el otro no tiene.

Los remotos son ese mecanismo. Git no guarda «la» versión oficial en ningún sitio especial: el remoto es otro repositorio más, al que el equipo ha decidido tratar como referencia.

> Piensa en una carpeta compartida en la nube con tu proyecto. Cada persona trabaja en su copia local y, de vez en cuando, sube lo suyo y baja lo de las demás. La diferencia con una carpeta compartida es que Git sabe exactamente qué commits faltan en cada lado.

## ¿Cuándo y para qué se usa?

- **Colaborar**: en el repositorio `tienda`, quien trabaja en `pagos` publica sus commits y quien trabaja en `inventario` los recibe.
- **Copia de seguridad**: el historial vive fuera de un portátil que se puede perder.
- **Disparar automatizaciones**: un `push` a la rama principal suele lanzar la CI y el despliegue, como cuenta [GitHub Actions](GitHub-Actions.md).
- **Revisar el trabajo antes de integrarlo**: las ramas se publican y se discuten en [Pull requests](Pull-requests.md).

## Los remotos de un repositorio

Un repositorio puede tener varios remotos. Se listan con `-v`:

```bash
git remote -v
```

```
origin	https://github.com/tienda-org/tienda.git (fetch)
origin	https://github.com/tienda-org/tienda.git (push)
```

Al hacer `git clone` el remoto se llama `origin` automáticamente. Si el repositorio se creó con `git init` (ver [Repositorio](Repositorio.md)), se conecta a mano:

```bash
git remote add origin https://github.com/tienda-org/tienda.git
```

Añadir un nombre que ya existe da `error: remote origin already exists.`; para cambiar la dirección de uno existente se usa `git remote set-url origin <url>`. Otros subcomandos útiles: `git remote rename origin casa`, `git remote remove origin` y `git remote show origin`, que explica cómo está configurado:

```
* remote origin
  Fetch URL: ../servidor.git
  Push  URL: ../servidor.git
  HEAD branch: main
  Remote branch:
    main tracked
  Local branch configured for 'git pull':
    main merges with remote main
  Local ref configured for 'git push':
    main pushes to main (up to date)
```

### `origin` y `upstream`

`origin` es solo un nombre por convención: el remoto del que se clonó. Cuando se trabaja con un *fork* (copia personal de un repositorio ajeno), suelen coexistir dos:

| Nombre | Apunta a | Para qué |
|---|---|---|
| `origin` | Tu fork | Donde publicas tus ramas |
| `upstream` | El repositorio original | De donde traes lo que el resto va publicando |

```bash
git remote add upstream https://github.com/tienda-org/tienda.git
git fetch upstream
git merge upstream/main
```

No confundir con la *rama upstream* (la rama remota que sigue una rama local), que se explica a continuación.

## Ramas de seguimiento: lo que Git recuerda del remoto

Tras un `fetch`, Git guarda en local una copia de cada rama remota con nombre `origin/main`, `origin/feature/emails`, etc. Son las **ramas de seguimiento remoto** (*remote-tracking branches*): marcadores de solo lectura que dicen «la última vez que pregunté, `main` estaba aquí». No se mueven solas; solo se actualizan al hablar con el remoto.

Una rama local puede además estar **vinculada** a una rama remota (su *upstream*). Con ese vínculo, `git pull`, `git push` y `git status` saben con qué comparar sin que se les diga. Se ve con `-vv`:

```bash
git branch -vv
```

```
* main fbb381c [origin/main] Servicio pedidos
```

El vínculo se crea con `-u` (`--set-upstream`) la primera vez que se publica una rama:

```bash
git push -u origin main
```

```
To ../servidor.git
 * [new branch]      main -> main
branch 'main' set up to track 'origin/main'.
```

Una rama nueva sin vínculo no se puede publicar con un `git push` pelado:

```
fatal: The current branch feature/cupones has no upstream branch.
To push the current branch and set the remote as upstream, use

    git push --set-upstream origin feature/cupones
```

Para no repetir esto en cada rama: `git config --global push.autoSetupRemote true`. (Git lo sugiere en el propio mensaje.)

## Fetch, pull y push

| Comando | Qué hace | Toca tu rama |
|---|---|---|
| `git fetch` | Descarga commits nuevos y actualiza `origin/*` | No |
| `git pull` | `fetch` + integrar en la rama actual (fusión, o rebase con `--rebase`) | Sí |
| `git push` | Envía tus commits al remoto | No (cambia el remoto) |

### `fetch`: mirar antes de tocar

```bash
git fetch origin
git status -sb
```

```
From ../servidor
   fbb381c..1364241  main       -> origin/main
## main...origin/main [ahead 1, behind 1]
```

`ahead 1, behind 1` quiere decir que hay un commit local sin publicar y otro remoto sin traer: las dos copias **divergen**. Para ver cuáles son:

```bash
git log --oneline main..origin/main    # lo que falta en tu rama
git log --oneline origin/main..main    # lo que falta en el remoto
```

### `pull`: traer e integrar

`git pull` equivale a `git fetch` seguido de una fusión (ver [Fusión y conflictos](Fusion-y-conflictos.md)) de `origin/main` en la rama actual. Con divergencia, crea un commit de fusión `Merge branch 'main' of ...`. Con `--rebase`, en cambio, los commits locales se recolocan encima de los que llegaron (ver [Rebase](Rebase.md)):

```bash
git pull --rebase
```

```
Rebasing (1/1)
Successfully rebased and updated refs/heads/main.
```

Desde Git 2.27 `git pull` avisa mientras no se haya fijado qué hacer ante una divergencia; se resuelve con `git config --global pull.rebase true` (rebase) o `false` (fusión). Con `git pull --ff-only` solo se acepta avanzar en línea recta, y falla si hay divergencia: es la opción más prudente para un `pull` automático.

### `push`: publicar

```bash
git push
```

Solo viajan **commits**. Los cambios sin confirmar, y lo que está en el área de preparación sin commit, no se envían. Los commits se tratan en [Commits](Commits.md).

## Push rechazado

El error más común con remotos:

```
To ../servidor.git
 ! [rejected]        main -> main (non-fast-forward)
error: failed to push some refs to '../servidor.git'
hint: Updates were rejected because the tip of your current branch is behind
hint: its remote counterpart. If you want to integrate the remote changes,
hint: use 'git pull' before pushing again.
```

Significa que el remoto tiene commits que tu copia no tiene: aceptar tu `push` los pisaría. El remedio es integrar y volver a publicar:

```bash
git pull --rebase
git push
```

```
   1364241..08a66de  main -> main
```

| Mensaje | Causa | Qué hacer |
|---|---|---|
| `! [rejected] main -> main (non-fast-forward)` | El remoto avanzó; tu rama diverge | `git pull --rebase` (o `git pull`) y `git push` |
| `! [rejected] main -> main (fetch first)` | El remoto tiene commits que ni siquiera has descargado | `git fetch`, integrar, `git push` |
| `fatal: The current branch X has no upstream branch.` | Rama sin vincular | `git push -u origin X` |
| `error: remote origin already exists.` | Se repite `remote add` | `git remote set-url origin <url>` |
| `remote: Permission to ... denied` / `fatal: Authentication failed` | Credenciales o permisos | Ver [Tokens de acceso en remotos](Tokens-de-Acceso-en-Remotos.md) |

## Reescribir lo publicado: `--force-with-lease`

Tras reescribir commits ya publicados (un `commit --amend`, un rebase), el `push` normal se rechaza porque el historial ya no es una continuación del remoto. La salida es forzar, y hay dos formas muy distintas:

| Opción | Qué hace |
|---|---|
| `git push --force` | Sobrescribe la rama remota **pase lo que pase**, aunque alguien haya publicado commits que tú no has visto |
| `git push --force-with-lease` | Sobrescribe **solo si** la rama remota sigue donde la viste en tu último `fetch` |

Ejemplo. Tras un `commit --amend` en un commit ya publicado, mientras una persona del equipo añadió un commit al remoto que aún no has descargado:

```bash
git push --force-with-lease
```

```
To ../servidor.git
 ! [rejected]        main -> main (stale info)
error: failed to push some refs to '../servidor.git'
```

`stale info` es el éxito de la opción: ha detectado que el remoto cambió y se ha negado a borrar ese commit ajeno. Un `--force` lo habría destruido en silencio. Tras `git fetch` la misma orden pasaría:

```
 + 2f2f165...4c412a2 main -> main (forced update)
```

Atención a esto: **el lease se renueva con cada `fetch`**. Si se hace `fetch` y no se mira lo que llegó, `--force-with-lease` ya considera que lo has visto y lo sobrescribe. Es una red de seguridad contra el descuido, no contra la prisa. Regla general: no reescribir ramas que otras personas usan (`main`), y sí las propias de trabajo, con `--force-with-lease`.

## Limpiar y mantener

Cuando alguien borra una rama en el remoto (por ejemplo, al fusionar un pull request), tu copia `origin/esa-rama` sigue existiendo. Se elimina con:

```bash
git fetch --prune
```

```
From ../servidor
 - [deleted]         (none)     -> origin/tmp
```

Para borrar una rama en el remoto: `git push origin --delete tmp`. Y para que cada `fetch` limpie solo: `git config --global fetch.prune true`.

## Buenas prácticas avanzadas

- **`origin/main` es un recuerdo, no el servidor.** `git status` puede decir `Your branch is up to date with 'origin/main'` con el remoto veinte commits por delante, porque compara con la última copia descargada. Haz `git fetch` antes de fiarte de cualquier comparación.
- **Fija `pull.rebase` o `pull.ff` una vez.** Sin ello, un `git pull` distraído crea commits `Merge branch 'main' of ...` sin contenido propio y ensucia el historial. `git config --global pull.ff only` obliga a decidir explícitamente (fusión o rebase) cuando hay divergencia.
- **Nunca `--force` sobre una rama compartida; con `--force-with-lease` ya basta.** Y, cuando se reescribe una rama propia, avisar a quien la tenga descargada: su copia local ya no es continuación de la remota.
- **Usa `--force-with-lease=<rama>:<commit>` para fijar el lease explícito.** Indicas el commit que esperas encontrar en el remoto; así ni un `fetch` intermedio hace que el lease sobrescriba lo que no has revisado.
- **Un remoto no tiene por qué ser un servidor.** Una ruta (`../servidor.git`) o una unidad de red valen como remoto; un repositorio *bare* (sin archivos de trabajo, creado con `git init --bare`) es lo que se usa como punto de intercambio. Sirve para probar esta guía sin cuenta en ninguna plataforma.

## Documentación oficial

- [Pro Git: Working with Remotes](https://git-scm.com/book/en/v2/Git-Basics-Working-with-Remotes) — el recorrido completo de `remote`, `fetch`, `pull`, `push`, renombrar y borrar remotos; el sitio donde empezar.
- [git-push](https://git-scm.com/docs/git-push) — referencia de `-u`, `--force-with-lease` (y su forma `=<rama>:<commit>`) y `--delete`.

---

*En resumen: un remoto es otra copia del repositorio; `fetch` mira, `pull` integra, `push` publica, y `--force-with-lease` es la única forma sensata de forzar.*
