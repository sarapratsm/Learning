# Tags y versiones

## ¿Qué es?

Una *tag* (etiqueta) es un nombre fijo que apunta a un commit concreto para marcarlo como importante, típicamente una versión publicada como `v1.4.0`.

## ¿Por qué existe?

Los commits se identifican por hashes poco memorables (`8d37dc7`). Al publicar la versión 1.4 de la tienda online hay que poder volver exactamente a ese punto con un nombre claro, saber qué código corre en producción y poder comparar dos versiones. Las ramas se mueven con cada commit; una tag no.

> Si las ramas son líneas de trabajo en movimiento, una tag es una chincheta clavada en un punto exacto del historial que ya no se mueve.

## ¿Cuándo y para qué se usa?

- **Marcar versiones publicadas** (*releases*) del repositorio `tienda`: `v1.4.0`, `v1.4.1`.
- **Referencia para despliegues y CI**: un pipeline puede dispararse al subir una tag (ver [Release-por-Tag.md](../ci-cd/Release-por-Tag.md)).
- **Comparar versiones**: `git log v1.3.0..v1.4.0` lista lo que entró entre ambas.
- **Fijar un punto de partida** para una rama de corrección: `git switch -c release/1.4 v1.4.0`.

## Ligeras y anotadas

Git tiene dos tipos de tags:

```bash
git tag v1.4.0                                # ligera
git tag -a v1.4.1 -m "Corrige redondeo en pagos"   # anotada
```

| | Ligera | Anotada |
|---|---|---|
| Qué es | Un nombre que apunta a un commit | Un objeto propio con autor, fecha y mensaje |
| Se crea con | `git tag <nombre>` | `git tag -a <nombre> -m "..."` |
| `git cat-file -t` | `commit` | `tag` |
| Para releases | No recomendada | Sí |
| `git describe` la ve | Solo con `--tags` | Sí |
| La sube `--follow-tags` | No | Sí |

```bash
git cat-file -t v1.4.0
git cat-file -t v1.4.1
```

```
commit
tag
```

`git show` de una anotada enseña quién y cuándo la creó antes del commit:

```
tag v1.4.1
Tagger: Sara <s@x.com>
Date:   Fri Oct 30 08:31:55 2026 +0100

Corrige redondeo en pagos

commit 8d37dc72a95c4166329478888dffbc5f50c1ebf9
```

Las ligeras sirven como marcadores locales temporales; todo lo que se publica va anotado.

## Crear y listar

La tag se pone en el commit actual o en uno indicado:

```bash
git tag -a v1.3.0 f35bea1 -m "Versión 1.3.0 de la tienda"
git tag
```

```
v1.3.0
v1.4.0
v1.4.1
```

```bash
git tag -l "v1.4.*" -n1      # filtrar por patrón y mostrar la primera línea del mensaje
```

```
v1.4.0          Aplica IVA en pagos
v1.4.1          Corrige redondeo en pagos
```

Las tags aparecen en `git log --oneline --decorate`:

```
8d37dc7 (HEAD -> main, tag: v1.4.1, tag: v1.4.0, origin/main) Aplica IVA en pagos
```

Repetir un nombre existente se rechaza:

```
fatal: tag 'v1.4.0' already exists
```

## Compartir con el remoto

Un `git push` normal **no** sube tags. Hay que enviarlas aparte:

```bash
git push origin v1.4.1        # una concreta
git push origin --tags        # todas las locales, anotadas y ligeras
git push --follow-tags        # solo las anotadas que apuntan a commits que se suben
```

```
 * [new tag]         v1.4.1 -> v1.4.1
```

`--tags` envía también las ligeras de prueba que nunca debieron salir (en el ejemplo, la ligera `v1.4.0`). `--follow-tags` es casi siempre lo que se quiere, y se puede hacer permanente con `git config --global push.followTags true`. Las tags del remoto se bajan con `git fetch --tags` (ver [Remotos.md](Remotos.md)).

## Borrar

```bash
git tag -d v1.4.0                       # local
git push origin --delete v1.4.0         # remoto
```

```
Deleted tag 'v1.4.0' (was 8d37dc7)
 - [deleted]         v1.4.0
```

Es válido para una tag creada por error y aún sin usar. Borrar no avisa a quien ya la haya descargado: su copia local sigue existiendo.

## Mover una tag: casi nunca

`git tag -f v1.4.1 <commit>` mueve la tag en local, pero el remoto la rechaza:

```
 ! [rejected]        v1.4.1 -> v1.4.1 (already exists)
hint: Updates were rejected because the tag already exists in the remote.
```

Forzar el envío es posible, pero las personas que ya tenían la tag antigua no la actualizan con un `pull` normal, y quedan dos `v1.4.1` distintas según la máquina. La corrección es publicar `v1.4.2`.

## Ir a una versión

```bash
git switch --detach v1.3.0
```

```
HEAD is now at f35bea1 Timeout en cobro
```

Se queda en *detached HEAD*: se puede mirar y compilar esa versión, pero los commits nuevos no pertenecen a ninguna rama. Para trabajar sobre ella, `git switch -c release/1.3 v1.3.0` (ver [Switch.md](Switch.md) y [Ramas.md](Ramas.md)).

## Versionado semántico

La convención habitual para el nombre es `vMAYOR.MENOR.PARCHE`:

| Sube | Cuándo | Ejemplo |
|---|---|---|
| MAYOR | Cambios que rompen compatibilidad | `v2.0.0` |
| MENOR | Funciones nuevas compatibles | `v1.5.0` |
| PARCHE | Correcciones compatibles | `v1.4.2` |

Las reglas de pre-releases (`v1.5.0-rc.1`) y de metadatos de compilación están en [Release-por-Tag.md](../ci-cd/Release-por-Tag.md). Git no valida el formato: la tag `version-final` es legal. El número lo decide el equipo, no la herramienta.

## Conectar un build con su versión

```bash
git describe --tags
```

```
v1.4.1                # sobre la tag exacta
v1.4.1-1-g4c18295     # un commit después de v1.4.1
```

El formato es `<tag>-<commits desde la tag>-g<hash>`. Inyectado en el build (en un endpoint `/version` del servicio `pedidos`, por ejemplo), dice qué código corre en producción.

## Errores frecuentes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `fatal: tag 'v1.4.0' already exists` | El nombre está en uso | Otro nombre, o borrar la tag si nunca se publicó |
| `! [rejected] ... (already exists)` al subir | Se movió una tag ya publicada | Publicar una versión nueva |
| La tag no aparece en el remoto | `git push` no sube tags | `git push origin <tag>` o `--follow-tags` |
| El pipeline no se dispara | Se creó una tag ligera y el flujo solo sube anotadas, o no se subió | Anotar y subir la tag |
| `git describe` no encuentra tags | Solo hay ligeras | `git describe --tags` |

## Cuándo no usarlo

- Para marcar trabajo en curso: eso es una rama (ver [Ramas.md](Ramas.md)).
- Para identificar despliegues temporales o pruebas: llenan el repositorio de tags que nadie borra.
- Como sustituto del versionado de dependencias: la tag nombra un commit, no garantiza compatibilidad.

## Buenas prácticas avanzadas

- **Tratar toda tag subida como inmutable** — mover una tag publicada deja versiones distintas con el mismo nombre en cachés de CI y clones.
- **Anotar siempre las tags de release** — dan autor, fecha, mensaje y funcionan con `describe` y `--follow-tags`.
- **`--follow-tags` como valor por defecto** — `push.followTags true` evita subir tags ligeras de prueba.
- **Etiquetar sobre el commit probado** — crear la tag sobre `main` tras pasar el CI, no sobre una rama de trabajo que aún puede cambiar.
- **Firmar tags de release** — `git tag -s` añade una firma GPG o SSH verificable con `git tag -v`, si el repositorio necesita acreditar el origen.

## Documentación oficial

- [git-tag](https://git-scm.com/docs/git-tag) — referencia; la sección «On Re-tagging» explica por qué evitar mover tags publicadas.
- [Pro Git: Etiquetado](https://git-scm.com/book/es/v2/Fundamentos-de-Git-Etiquetado) — recorrido en español por listar, crear, compartir y recuperar tags.
- [Versionado Semántico 2.0.0](https://semver.org/lang/es/) — la especificación de MAYOR.MENOR.PARCHE.

---

*En resumen: una tag es la chincheta que marca un commit concreto, casi siempre una versión publicada; se anota, se sube aparte y, una vez publicada, no se mueve.*
