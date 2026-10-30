# Release por tag

## ¿Qué es?

Una estrategia de publicación en la que **subir código a una rama no publica nada**: el despliegue a producción (o la publicación de una imagen) se dispara únicamente cuando alguien crea un *tag* de versión (`v1.2.0`) sobre un commit de la rama principal. El tag es el botón de publicar.

## ¿Por qué existe?

La alternativa habitual es desplegar «cuando algo llega a `main`». El problema: un merge puede hacerse por muchos motivos (consolidar trabajo, preparar terreno, resolver un conflicto) y no todos significan «quiero esto en producción ya». Cuando el merge y el release son la misma cosa, publicar deja de ser una decisión y pasa a ser un efecto secundario.

Separarlos convierte el release en un **acto deliberado**: alguien mira el estado de la rama, decide que ese commit exacto es la versión 1.2.0 y lo etiqueta.

> Es la diferencia entre guardar el borrador de un artículo (merge) y pulsar «Publicar» (tag). Puedes guardar cien veces; publicas cuando decides.

## ¿Cuándo y para qué se usa?

- Cuando el equipo quiere **control humano** sobre el momento exacto de publicar (por ejemplo, no desplegar un viernes por la tarde).
- Cuando hace falta un **historial de versiones legible**: `git tag` lista todas las releases, y cada despliegue corresponde a una versión con nombre.
- Cuando conviene poder **volver atrás con precisión**: recuperar la versión anterior es apuntar al tag anterior, sin buscar commits a mano.

Ejemplo de la tienda online: el servicio `pedidos` está en `v1.4.2`. Tras fusionar una corrección del cálculo de IVA, alguien etiqueta `v1.4.3` y el pipeline publica la imagen `tienda-pedidos:1.4.3` y la despliega en el VPS `203.0.113.10`, donde el pedido #4711 se procesará ya con el cálculo correcto. Qué es un tag en Git se explica en [Tags y versiones](../git/Tags-y-versiones.md); aquí se trata lo que el CI hace con él.

## Numerar con SemVer

Los tags de versión suelen seguir *versionado semántico* (SemVer): `MAYOR.MENOR.PARCHE`, normalmente precedido de `v` en el tag (`v1.4.3`).

| Sube... | Cuándo | Ejemplo |
|---|---|---|
| **MAYOR** | Cambio incompatible con lo anterior | `v1.4.3` → `v2.0.0` (la API de `pedidos` cambia el formato de respuesta) |
| **MENOR** | Funcionalidad nueva compatible | `v1.4.3` → `v1.5.0` (nuevo endpoint de seguimiento) |
| **PARCHE** | Corrección compatible | `v1.4.2` → `v1.4.3` (arreglo del IVA) |

Al subir una cifra, las de su derecha vuelven a cero. Otras reglas de la especificación:

- Una *pre-release* se marca con guion: `v1.5.0-rc.1`, `v2.0.0-beta.2`. Tiene menor precedencia que la versión final (`1.5.0-rc.1` < `1.5.0`) y avisa de que puede ser inestable.
- Los metadatos de compilación van tras un `+` (`1.5.0+20261030`) y no cuentan para la precedencia.
- `0.y.z` significa desarrollo inicial: nada es estable. La versión `1.0.0` declara la API pública.
- Una versión publicada **no se modifica**: cualquier cambio es una versión nueva.

Decidir si algo es `1.5.0` o `2.0.0` («¿rompe compatibilidad?») sigue siendo criterio humano; hay herramientas de *semantic release* que lo derivan de los mensajes de commit, pero quedan fuera de esta guía.

## Crear el tag y disparar el workflow

El workflow se dispara con el push del tag, no con la rama.

```yaml
# .github/workflows/release.yml
name: release
on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'        # v1.4.3; no coincide con v1.4.3-rc.1
```

Los patrones de `tags` usan la sintaxis de globs de GitHub (`*`, `**`, `+`, `?`, `!`), no expresiones regulares. `v[0-9]+.[0-9]+.[0-9]+` encaja con `v1.4.3` pero no con `v1.4.3-rc.1`, de modo que las pre-releases no desencadenan el despliegue a producción. Si se declaran solo filtros de tags, el workflow no se ejecuta con pushes de ramas.

Crear la release es crear un tag anotado y subirlo:

```bash
git switch main
git pull
git tag -a v1.4.3 -m "Corrige el cálculo del IVA en pedidos"
git push origin v1.4.3          # esto, y solo esto, lanza el workflow
```

Qué hace: `git tag -a` crea un tag anotado (objeto con autor, fecha y mensaje) sobre el commit actual; `git push origin v1.4.3` sube **ese** tag. Se evita `git push --tags`, que sube todos los tags locales, incluidos los que no pensabas publicar.

## Publicar la imagen con el tag

El workflow construye una imagen cuyo nombre ligado a la versión permite saber qué corre en producción. `docker/metadata-action` genera las etiquetas a partir del tag de Git.

```yaml
jobs:
  imagen:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - id: meta
        uses: docker/metadata-action@v6
        with:
          images: ghcr.io/mi-org/tienda-pedidos
          tags: |
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/build-push-action@v6
        with:
          context: ./pedidos
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

Para el tag `v1.4.3`, la acción genera `1.4.3`, `1.4`, `sha-<7 caracteres del commit>` y, por defecto, `latest`. Con una pre-release como `v2.0.0-beta.1`, el patrón `{{version}}` produce `2.0.0-beta.1` y no se marca como `latest` según los ejemplos de su README. Si no quieres `latest` nunca, se desactiva con `flavor: latest=false`. Las etiquetas de imagen se tratan en [GitHub Container Registry](../docker/GitHub-Container-Registry.md) y en [Docker en CI/CD](Docker-en-CI-CD.md).

## Generar las release notes

Una *release* de GitHub es la página pública asociada a un tag, con notas de cambios y artefactos adjuntos. GitHub puede generar las notas a partir de las PRs fusionadas desde el tag anterior.

```yaml
  release:
    needs: imagen
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - name: Crear la release en GitHub
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: gh release create "$GITHUB_REF_NAME" --verify-tag --generate-notes
```

Qué hace: `gh release create` con el nombre del tag (`GITHUB_REF_NAME` vale `v1.4.3`), `--verify-tag` aborta si el tag no existe en el remoto y `--generate-notes` pide a GitHub el título y las notas. Con `--prerelease` se marca como pre-release y con `--draft` queda sin publicar a la espera de revisión.

La estructura de las notas se controla con `.github/release.yml`, que agrupa las PRs por etiqueta:

```yaml
# .github/release.yml
changelog:
  exclude:
    labels: [ignore-for-release]
    authors: [dependabot]
  categories:
    - title: Cambios incompatibles
      labels: [breaking-change]
    - title: Novedades
      labels: [enhancement]
    - title: Otros cambios
      labels: ['*']
```

El resultado depende de que las PRs lleven etiquetas: sin ellas, todo cae en la categoría comodín.

## Proteger los tags

El tag es el botón de producción: quien pueda crear un tag `v*` puede desplegar. En GitHub se protege con un *ruleset* de tipo tag:

1. En *Settings → Rules → Rulesets*, crear un **New tag ruleset**.
2. En *Target tags*, añadir el patrón `v*` (patrón `fnmatch`).
3. En las reglas, restringir quién puede crear, actualizar y borrar esos tags, y añadir a la lista de excepciones solo los roles de release.
4. Activar la aplicación (*Active*).

Con las protecciones activas, un `git push --tags` accidental de quien no tiene permiso es rechazado. Que no se pueda borrar ni mover un tag publicado es tan importante como que no se pueda crear.

## Rollback por tag

Volver atrás es **desplegar de nuevo una versión anterior**, no reescribir la actual. El workflow admite un lanzamiento manual con el tag a desplegar:

```yaml
on:
  push:
    tags: ['v[0-9]+.[0-9]+.[0-9]+']
  workflow_dispatch:
    inputs:
      tag:
        description: 'Tag a desplegar (p. ej. v1.4.2)'
        required: true

jobs:
  desplegar:
    runs-on: ubuntu-latest
    env:
      VERSION: ${{ inputs.tag || github.ref_name }}
    steps:
      - name: Desplegar la imagen de esa versión
        run: |
          ssh deployer@203.0.113.10 \
            "cd /srv/tienda && VERSION=${VERSION#v} docker compose up -d pedidos"
```

Qué hace: `workflow_dispatch` permite lanzar a mano el workflow indicando `v1.4.2`; para un push de tag, `github.ref_name` aporta el tag. El despliegue usa la imagen ya publicada `tienda-pedidos:1.4.2`, que existe en el registro: no hay que recompilar nada, y por eso el rollback tarda segundos. Sobre el SSH al VPS véase [Secrets y variables](Secrets-y-Variables.md); sobre políticas de transición entre versiones, [Estrategias de despliegue](Estrategias-de-Despliegue.md).

El rollback de la aplicación no deshace los cambios de esquema de base de datos: una migración que ya borró una columna no se revierte al re-desplegar la imagen anterior.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Hice `git push` y no se ha lanzado la release | Se subió la rama, no el tag; hace falta `git push origin v1.4.3` |
| El workflow no arranca con el tag | El patrón de `tags` no coincide (por ejemplo `v*` frente a `1.4.3` sin `v`), o el workflow no existe aún en el commit etiquetado |
| Se lanzó con un tag de pre-release | Patrón `v*` demasiado amplio; usar `v[0-9]+.[0-9]+.[0-9]+` |
| `gh release create` falla con `tag ... not found` | Se usó `--verify-tag` y el tag no está en el remoto; empujarlo primero |
| `latest` apunta a una versión vieja | Se etiquetó a mano `latest` en otra ejecución; derivarlo siempre del tag |
| Dos imágenes dicen ser `1.4.3` | Se movió el tag con `git tag -f` y se volvió a empujar |
| `403` al subir la imagen a ghcr.io | Falta `permissions: packages: write` en el job |
| El tag existe, pero el commit etiquetado no pasó CI | El tag no valida nada; el workflow de release debe comprobarlo |

## Cuándo no usar release por tag

- Servicios con despliegue continuo por diseño (cada merge a `main` va a producción, con *feature flags* y revertir rápido): el paso del tag es fricción sin valor.
- Equipos de una sola persona que ya controlan el momento de fusión: la separación aporta poco.
- Entornos de desarrollo y staging: allí lo normal es desplegar con cada merge; el tag es para producción.

## Buenas prácticas avanzadas

- **Un tag publicado no se mueve jamás.** Borrar `v1.4.3` y recrearlo sobre otro commit deja dos artefactos distintos que dicen ser la misma versión: la imagen que alguien ya descargó y la nueva. Si el release salió mal, publica `v1.4.4`.
- **Que el workflow del tag verifique, no confíe.** Como el tag no valida nada, un buen pipeline de release comprueba antes de desplegar que el commit etiquetado pasó los checks de CI en `main` (o relanza la suite). Cuesta unos minutos y elimina el accidente «etiqueté la rama equivocada».
- **Usa tags anotados.** `git tag v1.4.3` crea un tag ligero, un simple puntero sin autor, fecha ni mensaje; `git tag -a` crea un objeto completo, y herramientas como `git describe` ignoran por defecto los ligeros.
- **Etiqueta la imagen también con el SHA.** La versión es para humanos; `sha-8f4b7f8` responde sin ambigüedad a «¿qué código exacto corre en producción?», incluso si alguien movió un tag.
- **Con `fetch-depth` limitado, las notas salen mal.** Si el workflow calcula cambios con git (en lugar de usar `--generate-notes`), `actions/checkout` descarga un solo commit por defecto; usa `fetch-depth: 0` para tener el historial y los tags.

## Documentación oficial

- [Sintaxis de workflows: filtros `tags`](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions) — la sección de `on.push.tags` con la sintaxis de patrones y su combinación con `branches`.
- [Notas de release generadas automáticamente](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes) — configuración de `.github/release.yml` con categorías y exclusiones.
- [`gh release create`](https://cli.github.com/manual/gh_release_create) — referencia de `--generate-notes`, `--verify-tag`, `--prerelease` y `--draft`.
- [Versionado semántico 2.0.0](https://semver.org/lang/es/) — la especificación completa, incluidas pre-releases y metadatos.

## Recursos didácticos

- [docker/metadata-action](https://github.com/docker/metadata-action) — tabla con los tags de imagen que genera cada tipo de tag de Git.
- [Reglas de tags con rulesets](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/configuring-tag-protection-rules) — el paso a paso para proteger `v*`.

---

*En resumen: release por tag separa «integrar código» de «publicar producto»; el tag es la decisión, la imagen queda ligada a su versión, y volver atrás es desplegar el tag anterior, nunca mover el actual.*
