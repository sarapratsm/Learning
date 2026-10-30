# Secrets y variables de entorno

## ¿Qué es?

Los *secrets* y las *variables* son los valores que una plataforma de CI/CD guarda fuera del repositorio y entrega al pipeline cuando lo necesita. Una **variable** guarda un dato de configuración que puede verse (una URL pública, el nombre de un entorno); un **secret** guarda un dato confidencial (contraseña, token, clave privada) que la plataforma almacena cifrado y oculta en los logs.

## ¿Por qué existe?

Un pipeline necesita datos para trabajar: la dirección del servidor, la clave SSH del usuario de despliegue, el token del registro de imágenes. Escribirlos en el fichero del pipeline es un error grave, porque ese fichero vive en Git: lo ve todo el equipo, se copia en cada clon y queda en el historial aunque se borre después.

> Es la diferencia entre dejar la llave de casa pegada con celo en la puerta y guardarla en una caja fuerte que solo se abre cuando hace falta.

La plataforma resuelve esto con un almacén aparte: el valor se define en los ajustes del repositorio, se cifra, y el pipeline lo recibe en tiempo de ejecución por su nombre. El fichero del pipeline solo dice *qué* secret usa, nunca *cuál es su valor*.

## ¿Cuándo y para qué se usa?

Siempre que el pipeline necesite algo que no debe estar en el repositorio. En la tienda online de ejemplo (servicios `pedidos`, `pagos`, `inventario` y `emails`, desplegada en un VPS `203.0.113.10` bajo `tienda.ejemplo.com`):

- La clave SSH con la que el usuario `deployer` entra al VPS para desplegar.
- El token con el que el pipeline publica las imágenes de `pagos` en el registro.
- La clave de la pasarela de pagos que `pagos` usa en las pruebas contra el entorno de sandbox.
- El nombre del dominio de cada entorno (`tienda.ejemplo.com`, `staging.tienda.ejemplo.com`), que no es secreto pero sí cambia según el entorno.

---

## Secret o variable: dónde va cada dato

El criterio es una pregunta: **¿pasaría algo grave si lo leyera cualquier persona con acceso de lectura al repositorio?** Si la respuesta es sí, es un secret.

| Dato | ¿Qué es? | Motivo |
|---|---|---|
| `DEPLOY_HOST` = `203.0.113.10` | Variable | Una IP de servidor no concede acceso por sí sola |
| `APP_URL` = `https://tienda.ejemplo.com` | Variable | Es pública por definición |
| `DEPLOY_SSH_KEY` | Secret | Quien la tenga entra al VPS como `deployer` |
| `REGISTRY_TOKEN` | Secret | Permite publicar imágenes con el nombre de la tienda |
| `PAYMENTS_API_KEY` | Secret | Permite operar contra la pasarela |
| `DB_CONNECTION_STRING` | Secret | Incluye la contraseña de la base de datos |
| `LOG_LEVEL` = `info` | Variable | Configuración sin riesgo |

Poner un dato público como secret no es peligroso, pero tiene un coste: los secrets se enmascaran en los logs y no se pueden consultar después en la interfaz. Si `DEPLOY_HOST` fuera un secret, cada log mostraría `***` donde debería verse el servidor y el diagnóstico de un despliegue fallido sería más difícil.

## Definirlos y leerlos en GitHub Actions

Se definen en *Settings → Secrets and variables → Actions* del repositorio, o desde la terminal con la CLI de GitHub:

```bash
gh secret set DEPLOY_SSH_KEY < ~/.ssh/deployer_ed25519
gh variable set DEPLOY_HOST --body "203.0.113.10"
```

Dentro del workflow, los secrets se leen con el contexto `secrets` y las variables con `vars`:

```yaml
name: deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Desplegar en el VPS
        env:
          DEPLOY_HOST: ${{ vars.DEPLOY_HOST }}
          DEPLOY_SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
        run: |
          install -m 600 /dev/null key
          printf '%s\n' "$DEPLOY_SSH_KEY" > key
          ssh -i key -o StrictHostKeyChecking=accept-new "deployer@$DEPLOY_HOST" \
            'cd /srv/tienda && docker compose pull && docker compose up -d'
```

El paso expone el secret al script como variable de entorno (`env:`) y no escribiendo `${{ secrets.X }}` dentro del `run:`. La diferencia importa: con `${{ ... }}` dentro de `run:`, GitHub sustituye el valor en el texto del script antes de ejecutarlo, y un valor con comillas o saltos de línea puede romper el script o inyectar comandos. Como variable de entorno, el shell lo trata como dato.

Un secret sin definir se evalúa como cadena vacía, sin error: si `secrets.DEPLOY_SSH_KEY` tiene un nombre mal escrito, el paso falla más adelante con un error de autenticación y no con «secret no encontrado».

En GitLab CI el mecanismo es equivalente: la variable se define en *Settings → CI/CD → Variables* con la opción *Masked* (y *Protected* para limitarla a ramas protegidas) y el script la lee como `$DEPLOY_SSH_KEY`. La ficha [GitLab-CI.md](GitLab-CI.md) cubre su sintaxis.

## Ámbitos: repositorio, entorno y organización

GitHub ofrece tres niveles donde definir un secret o una variable. Cuanto más estrecho el ámbito, menos gente y menos workflows pueden llegar al valor.

| Ámbito | Quién lo ve | Quién puede crearlo | Úsalo para |
|---|---|---|---|
| Repositorio | Todos los workflows del repo | Quien tenga permiso de escritura en repos de organización | Datos que no cambian entre entornos (token del registro) |
| Entorno (*environment*) | Solo los jobs que declaran ese entorno | Quien tenga permiso de administración en repos de organización | Credenciales de producción frente a las de staging |
| Organización | Los repos que la política de acceso permita | Propietarios de la organización | Un token compartido por muchos repos |

Un entorno permite además exigir una **aprobación manual** antes de que el job arranque y restringir a qué ramas puede desplegar. Así, `DEPLOY_SSH_KEY` de producción solo existe para el job que lo declara:

```yaml
jobs:
  deploy-production:
    runs-on: ubuntu-latest
    environment: production        # secrets de ese entorno + aprobación
    steps:
      - run: echo "Desplegando pedido #4711 en producción"
```

Si el repositorio y el entorno definen un secret con el mismo nombre, gana el del entorno. Es la forma habitual de tener `DEPLOY_SSH_KEY` en `staging` y en `production` con valores distintos sin cambiar una línea del workflow.

Los secrets de organización tienen una restricción en el plan gratuito: no son accesibles desde repositorios privados.

## Qué enmascarado hay en los logs, y qué no

GitHub sustituye por `***` cualquier aparición literal del valor de un secret en los logs. Eso protege de un `echo` descuidado, pero tiene límites que conviene conocer:

| Situación | ¿Se oculta? |
|---|---|
| `echo "$DEPLOY_SSH_KEY"` | Sí: aparece `***` |
| `echo "$DEPLOY_SSH_KEY" \| base64` | No: el valor transformado ya no coincide literalmente |
| El valor troceado (`${KEY:0:10}`) | No |
| Un valor que no se guardó como secret (por ejemplo, uno que devuelve una API en mitad del job) | No, salvo que se declare con `::add-mask::` |
| Un secret con varias líneas (una clave PEM) | Comportamiento no verificado en esta ficha: conviene probarlo con un valor de prueba antes de fiarse |

Para valores calculados durante el job, el comando `::add-mask::` los marca para enmascarado desde ese punto:

```yaml
- name: Obtener token temporal
  run: |
    TOKEN=$(curl -s https://api.ejemplo.com/token)
    echo "::add-mask::$TOKEN"
    echo "TOKEN=$TOKEN" >> "$GITHUB_ENV"
```

Otros límites de la plataforma:

- Los secrets no se envían a workflows que arrancan desde un fork, salvo `GITHUB_TOKEN`. Una pull request externa no puede leerlos, y por eso sus pruebas a veces no tienen acceso a servicios externos.
- Los secrets no pasan solos a un workflow reutilizable: hay que declararlos en la llamada (`secrets: inherit` o uno por uno).
- No se pueden usar directamente en una condición `if:`; hay que exponerlos antes como variable de entorno del job.
- Un secret de más de 48 KB no cabe; la alternativa documentada es cifrar el fichero con `gpg`, subirlo al repositorio y guardar solo la contraseña de cifrado como secret.

## OIDC: credenciales que caducan solas

Un secret como `AWS_SECRET_ACCESS_KEY` es una credencial de **larga duración**: sirve hasta que alguien la revoque, y cualquiera que la copie la usa desde cualquier sitio. OIDC (*OpenID Connect*) elimina esa pieza. En lugar de guardar la clave en GitHub, el proveedor de nube confía en GitHub: cada job pide a GitHub un token firmado (un JWT) que dice quién es (repositorio, rama, entorno), lo presenta al proveedor y recibe a cambio credenciales que caducan al terminar el job.

```text
job de GitHub Actions ──(1) pide JWT──> GitHub OIDC
        │
        └──(2) presenta JWT + rol a asumir──> Proveedor de nube
                 comprueba firma y condiciones (repo, rama, entorno)
        ┌──(3) credenciales temporales──┘
        ▼
   usa la nube con credenciales que caducan al acabar el job
```

Dos piezas hacen falta. En el workflow, el permiso `id-token: write`, sin el cual el job no puede pedir el JWT:

```yaml
permissions:
  id-token: write   # necesario para solicitar el JWT
  contents: read    # necesario para actions/checkout

jobs:
  publish:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/tienda-publica-imagenes
          aws-region: eu-west-1
```

Y en el proveedor, una relación de confianza que limita **qué ejecuciones** pueden asumir el rol. La clave es el campo `sub` del token, que GitHub construye con el contexto del job, por ejemplo:

| Contexto del job | Valor de `sub` |
|---|---|
| Job con `environment: Production` | `repo:octo-org/octo-repo:environment:Production` |
| Push a una rama | `repo:octo-org/octo-repo:ref:refs/heads/main` |
| Pull request | `repo:octo-org/octo-repo:pull_request` |
| Push de una etiqueta | `repo:octo-org/octo-repo:ref:refs/tags/v1.0` |

Con una condición que exija `...:environment:Production`, un job lanzado desde una pull request o desde otra rama no obtiene el rol, aunque el workflow sea idéntico. Esa es la ventaja frente al secret: la credencial deja de ser un objeto que se copia y pasa a ser una decisión que el proveedor toma en cada ejecución.

> Los repositorios creados después del 15 de julio de 2026, y los que lo activen, usan un formato de `sub` inmutable que incluye los identificadores numéricos del propietario y del repositorio (`repo:octo-org@123456/octo-repo@456789:ref:refs/heads/main`). La condición de confianza debe escribirse con el formato que emita el repositorio concreto.

OIDC solo sirve contra proveedores que lo soporten (AWS, Azure, Google Cloud, HashiCorp Vault y otros). No aplica a la entrada por SSH al VPS de la tienda: ahí la clave de `deployer` sigue siendo un secret, y la defensa es acotarla (usuario sin privilegios, clave dedicada, limitada con `command=` en `authorized_keys`; ver [Acceso-SSH-Seguro.md](../despliegue-en-vps/Acceso-SSH-Seguro.md)).

## Rotación

Rotar es cambiar el valor de una credencial y revocar el anterior. Hacerlo con calendario (cada 90 días, por ejemplo) limita la vida útil de cualquier fuga que nadie haya detectado. Se hace sin cortes en tres pasos:

1. Crear la credencial nueva en el servicio de origen, sin revocar todavía la vieja.
2. Actualizar el secret en la plataforma (`gh secret set REGISTRY_TOKEN`). El siguiente pipeline ya usa el valor nuevo.
3. Comprobar que un despliegue real funciona y entonces revocar la credencial antigua.

Rotar es sencillo cuando cada secret tiene un solo dueño y un uso claro. Es un susto cuando una clave maestra se reutiliza en cinco sitios: nadie sabe qué se rompe al cambiarla. Por eso conviene una credencial por servicio y por entorno.

## Si se filtra un secret

Un secret que ha aparecido en un commit, en un log público o en un mensaje de chat debe tratarse como **comprometido**, aunque se borre en el acto: Git conserva el historial, los clones y los forks conservan copias, y existen bots que rastrean repositorios públicos y prueban las claves que encuentran en cuestión de minutos.

Orden de actuación:

1. **Revocar** la credencial en el servicio de origen. Es lo único que cierra la puerta.
2. **Generar una nueva** y actualizar el secret en la plataforma.
3. **Revisar el uso**: mirar en el servicio si la credencial se usó entre la fuga y la revocación (accesos desde IP desconocidas, recursos creados).
4. **Limpiar el historial** solo después, y como higiene, no como remedio. Reescribir la historia con `git filter-repo` y forzar el push no recupera nada de lo ya copiado.
5. **Cerrar la causa**: ¿por qué llegó ahí? Un `.env` sin ignorar, un `echo` de depuración, una URL con la clave dentro.

GitHub ofrece *secret scanning*, que busca credenciales conocidas en todo el historial del repositorio y abre una alerta cuando encuentra una; la respuesta recomendada es rotar de inmediato. La ficha [Por-Que-Los-Secretos-No-Van-A-Git.md](../../seguridad/gestion-de-secretos-en-desarrollo/Por-Que-Los-Secretos-No-Van-A-Git.md) explica el problema de fondo.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| `Permission denied (publickey)` en el paso de despliegue | El secret está vacío (nombre mal escrito) o la clave se pegó sin el salto de línea final |
| El job de una pull request de un fork falla pidiendo credenciales | Los secrets no se entregan a workflows desde forks; el comportamiento es intencionado |
| `Error: Credentials could not be loaded` con OIDC | Falta `permissions: id-token: write` en el job o en el workflow |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | La condición de confianza no coincide con el `sub` real: rama, entorno o formato del identificador distinto |
| El valor aparece en claro en el log | Se transformó antes de imprimirlo (base64, troceado) o no era un secret registrado |
| Un workflow reutilizable no ve el secret | Los secrets no se heredan: hay que pasarlos en la llamada |
| El secret de producción llega a una rama de pruebas | Está definido a nivel de repositorio y no de entorno |

## Cuándo no basta con los secrets de la plataforma

Los secrets de la plataforma resuelven el pipeline, no la aplicación en ejecución. Si `pagos` necesita su clave de la pasarela cuando corre en el VPS, esa clave tiene que llegar allí por otra vía (fichero `.env` con permisos restrictivos, `docker secret`, un gestor como Vault). Y con decenas de repos, rotación auditada o credenciales por usuario, un gestor dedicado compensa más que repartir secrets por ajustes.

## Buenas prácticas avanzadas

- **Prefiere OIDC a cualquier clave estática de nube.** Una clave que no existe no se filtra: el token de OIDC caduca con el job y su condición de confianza (rama, entorno) impide que otro workflow lo obtenga.
- **Fija `permissions` al mínimo en cada workflow.** El `GITHUB_TOKEN` es un secret que GitHub crea en cada ejecución; con `permissions: contents: read` por defecto y ampliación solo en el job que lo necesita, un paso comprometido tiene el mínimo alcance.
- **Trata los secrets como entrada de un script que puede ser malicioso.** Una acción de terceros o una dependencia que se ejecuta en el job lee el entorno completo. Fija las acciones por commit y no expongas un secret a pasos que no lo necesitan: declara `env:` en el paso, no en el job.
- **Protege el entorno de producción con aprobación y restricción de ramas.** Un secret de entorno con reglas de despliegue es la diferencia entre «solo `main` tras revisión» y «cualquier rama que modifique el workflow».
- **No uses secrets para lo que la aplicación debería resolver sola.** Una clave de producción que viaja por el pipeline hasta el VPS pasa por más manos que una que el servidor lee de su propio almacén.
- **Pasa los secrets por entorno o por fichero, nunca por argumento.** Un argumento de línea de comandos es visible en la lista de procesos y puede aparecer en mensajes de error.

## Documentación oficial

- [Usar secrets en GitHub Actions](https://docs.github.com/en/actions/how-tos/security-for-github-actions/security-guides/using-secrets-in-github-actions) — ámbitos, límites de tamaño y comportamiento con forks; la sección sobre cómo pasarlos a acciones y a workflows reutilizables.
- [OpenID Connect en GitHub Actions](https://docs.github.com/en/actions/concepts/security/openid-connect) — el modelo conceptual de OIDC y la relación de confianza con el proveedor.
- [Referencia de OIDC](https://docs.github.com/en/actions/reference/security/oidc) — permisos `id-token`, formatos del `sub` y claves para las condiciones de confianza.
- [Acerca del secret scanning](https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning) — qué detecta y qué hacer al recibir una alerta.

---

*En resumen: el valor sensible vive en la plataforma y no en el repositorio, se limita al entorno que lo necesita, se sustituye por OIDC cuando la nube lo permite, y cuando se filtra se revoca primero y se limpia después.*
