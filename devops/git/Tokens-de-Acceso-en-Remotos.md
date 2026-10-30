# Tokens de acceso en remotos

## ¿Qué es?

Un token de acceso personal (*personal access token*, PAT) es una credencial generada por la plataforma que aloja el repositorio (GitHub, GitLab, Bitbucket...) para autenticar `clone`, `fetch`, `pull` y `push` por HTTPS en lugar de la contraseña de la cuenta. Se usa en el campo de contraseña y tiene permisos y caducidad propios.

## ¿Por qué existe?

Las plataformas dejaron de aceptar la contraseña de la cuenta para operaciones de Git. Un `push` con contraseña fracasa hoy con un mensaje como este (el texto exacto varía según la plataforma y la fecha):

```
remote: Support for password authentication was removed on August 13, 2021.
fatal: Authentication failed for 'https://github.com/tienda-org/tienda.git/'
```

La razón es de seguridad. Una contraseña de cuenta da acceso a todo y no se puede recortar. Un token se limita a unos repositorios y a unos permisos concretos (solo lectura, o lectura y escritura de contenido), caduca, y se revoca sin tocar la contraseña ni cerrar las demás sesiones.

> Una contraseña es la llave maestra de la casa. Un token es una llave de una sola habitación, con fecha de caducidad, que se puede tirar sin cambiar la cerradura.

## ¿Cuándo y para qué se usa?

- Trabajar con un remoto por **HTTPS** desde un portátil o un servidor (`https://github.com/tienda-org/tienda.git`).
- Dar a una **automatización** (un script de despliegue, un servidor de CI) acceso a un repositorio concreto sin usar la cuenta de una persona.
- Cuando SSH no es una opción: redes que bloquean el puerto 22, o herramientas que solo hablan HTTPS.

Si se prefiere no gestionar tokens, [SSH](#alternativa-ssh) evita el problema.

## Crear un token en GitHub

La ruta, según la documentación de GitHub: foto de perfil → **Settings** → **Developer settings** → **Personal access tokens**, y ahí dos tipos.

| | Fine-grained tokens | Tokens (classic) |
|---|---|---|
| Alcance | Un solo *Resource owner* (cuenta u organización) y los repositorios que se elijan | Todos los repositorios a los que accede la cuenta |
| Permisos | Por permiso concreto (p. ej. **Contents**: lectura o escritura) | Por *scopes* amplios; para Git por línea de comandos, **repo** |
| Caducidad | **Expiration** a elegir; GitHub la recomienda | **Expiration**: valores predefinidos o **Custom** |
| Organizaciones | Pueden requerir aprobación de un administrador | Dependen de la política de la organización |
| Recomendación de GitHub | Preferirlos siempre que se pueda | Solo para lo que los otros aún no cubren |

Para un token de granularidad fina (el recomendado): **Generate new token** → **Token name** y **Expiration** → **Resource owner** → en **Repository access**, **Only select repositories** y elegir `tienda` → en **Permissions**, **Contents** con lectura y escritura → **Generate token**.

Para un token clásico: **Generate new token (classic)** → nombre en **Note** → **Expiration** → marcar el scope **repo** → **Generate token**.

Un token con **Contents** de solo lectura sirve para clonar y para que un servidor de despliegue (por ejemplo, el usuario `deployer` de la tienda) descargue el código sin poder modificarlo. Si el propietario es una organización con aprobación obligatoria, el token queda pendiente hasta que un administrador lo apruebe, y mientras tanto solo lee recursos públicos.

La documentación de GitHub no detalla qué pasa en pantalla al generar el token. Pendiente de verificar: si el valor se muestra una sola vez al generarlo (es lo que suele ocurrir en las plataformas, pero esa página no lo confirma); por si acaso, conviene copiarlo en ese momento.

## Usar el token

La primera operación contra el remoto pide credenciales; Git muestra la solicitud en terminal o en una ventana de la plataforma:

```bash
git clone https://github.com/tienda-org/tienda.git
```

```
Username for 'https://github.com': <usuario>
Password for 'https://<usuario>@github.com': <pegar el token>
```

El nombre de usuario es el de la cuenta; en el campo de contraseña se pega el token. Pegar el token en cada operación es incómodo, y para eso existen los **credential helpers**: programas que Git invoca para guardar y recuperar credenciales (se explican en la documentación `gitcredentials`).

### Dónde se guarda en cada sistema

GitHub recomienda dos formas: **Git Credential Manager** (GCM) y **GitHub CLI**.

| Sistema | Qué lo guarda | Cómo |
|---|---|---|
| Windows | Windows Credential Manager | Git for Windows incluye GCM desde la versión 2.29; no hay nada que instalar |
| macOS | Llavero (*keychain*) | `brew install git` y `brew install --cask git-credential-manager`; no hace falta configurar nada más |
| Linux | Depende del almacén que se configure para GCM | Instalar GCM siguiendo las instrucciones de su repositorio y configurar el almacén que indique su documentación |
| Cualquiera | GitHub CLI | `gh auth login`, elegir `HTTPS` y responder `Y` a la pregunta de autenticar Git con las credenciales de GitHub |

Para ver qué helper usa una máquina: `git config --show-origin --get-all credential.helper`.

Dos helpers integrados de Git conviene conocer por sus riesgos: `store` guarda el token **en texto plano** en un archivo del disco, y `cache` lo guarda en memoria durante un tiempo (`git config --global credential.helper cache`). Ninguno de los dos es lo ideal en un portátil: el almacén del sistema cifra la credencial.

### Lo que no hay que hacer: el token en la URL

Existe la costumbre de incrustarlo en el remoto:

```bash
git remote set-url origin https://<usuario>:<TOKEN>@github.com/tienda-org/tienda.git
```

Funciona, pero el token queda en texto plano en `.git/config`, aparece en `git remote -v` (y en cualquier captura de pantalla o registro de CI que lo imprima) y se copia con el repositorio. Con un credential helper el remoto sigue siendo `https://github.com/tienda-org/tienda.git` y el secreto vive fuera.

## Cuando caduca o se revoca

Síntoma: operaciones que funcionaban dejan de funcionar con

```
remote: Invalid username or password.
fatal: Authentication failed for 'https://github.com/tienda-org/tienda.git/'
```

o con un `403` / `Permission to tienda-org/tienda.git denied`. El primero apunta a una credencial inválida (caducada, revocada o mal pegada); el segundo, a que la credencial es válida pero no tiene permiso para esa acción (por ejemplo, un token de solo lectura intentando un `push`, o un token de granularidad fina que no incluye ese repositorio).

Para recuperarse:

1. Generar un token nuevo en **Settings** → **Developer settings** → **Personal access tokens** con los mismos permisos.
2. Borrar la credencial vieja del almacén, o Git seguirá enviándola sin pedir la nueva. Con cualquier helper:

   ```bash
   printf "protocol=https\nhost=github.com\n\n" | git credential reject
   ```

   (En Windows también se puede borrar desde el administrador de credenciales del sistema; en macOS, desde el llavero.)
3. Repetir una operación segura (`git fetch`) y pegar el token nuevo cuando lo pida.

GitHub elimina automáticamente los tokens clásicos que lleven un año sin usarse, así que un token olvidado en un servidor de poco uso puede dejar de funcionar sin que nadie lo haya revocado.

## Alternativa: SSH

SSH autentica con un par de claves en lugar de un token: la privada se queda en la máquina y la pública se registra en la cuenta. No hay nada que caduque ni que pegar.

```bash
ssh-keygen -t ed25519 -C "ana@tienda.example"
```

El comando recomendado por GitHub es ese (con `-t rsa -b 4096` como alternativa si el sistema no soporta Ed25519). Después, en GitHub: **Settings** → **SSH and GPG keys** → **New SSH key** → **Title**, tipo de clave y pegar el contenido del `.pub` en **Key**. La comprobación:

```bash
ssh -T git@github.com
```

```
Hi ana! You've successfully authenticated, but GitHub does not provide shell access.
```

(El mensaje oficial incluye el nombre de usuario; el comando termina con código de salida 1 y es lo esperado.) Y el remoto se cambia al formato SSH:

```bash
git remote set-url origin git@github.com:tienda-org/tienda.git
```

| Criterio | HTTPS + token | SSH |
|---|---|---|
| Caduca | Sí (según la expiración elegida) | No, salvo que se retire la clave |
| Funciona detrás de proxies restrictivos | Casi siempre | A veces bloqueado |
| Permisos finos por repositorio | Sí (fine-grained) | La clave da acceso a lo que la cuenta ve; las *deploy keys* son por repositorio |
| Protección extra | Almacén del sistema | *Passphrase* + ssh-agent, o clave de hardware |

## Si se filtra un token

Un token en un chat, un ticket, un `README`, un log de CI o un commit debe darse por comprometido.

1. **Revocarlo ya**: en **Settings** → **Developer settings** → **Personal access tokens**, elegir **Fine-grained tokens** o **Tokens (classic)** y pulsar **Delete** junto al token.
2. Crear uno nuevo y actualizar todos los sitios que lo usaban.
3. Revisar qué se hizo con él: GitHub ofrece un registro de seguridad de la cuenta con las acciones de los últimos 90 días (*security log*).
4. Si estaba en un commit, **reescribir el historial no sustituye a revocar**: el secreto ya se copió. La documentación de GitHub sobre *secret scanning* indica que, una vez revocada la credencial, reescribir el historial suele ser innecesario y costoso.

GitHub activa *secret scanning* gratis en repositorios públicos; para ciertos tipos de secretos avisa al proveedor, pero su documentación no promete una revocación automática de los tokens personales, así que la revocación manual es lo único seguro.

## Buenas prácticas avanzadas

- **Caducidad corta y un token por uso.** Uno para el portátil, otro para el servidor de despliegue, otro para la CI. Si hay que revocar el del portátil perdido, lo demás sigue funcionando.
- **Preferir granularidad fina y solo lo necesario.** Un servidor que solo descarga código necesita **Contents** de lectura sobre un repositorio, no el scope **repo** clásico, que da escritura en todo lo que la cuenta alcanza.
- **Para automatizar, no usar el token de una persona.** Si esa persona se va o cambia de permisos, la automatización se rompe, y los cambios aparecen firmados a su nombre. Existen cuentas de servicio y *deploy keys* por repositorio para eso.
- **No guardar tokens en archivos del repositorio, ni siquiera en uno ignorado.** Un `.env` ignorado con [gitignore](gitignore.md) evita el commit accidental, pero no protege de que se copie la carpeta. Los secretos de CI van en el almacén de secretos de la plataforma, como cuentan los *secrets* de [GitHub Actions](GitHub-Actions.md).
- **Distinguir `Authentication failed` de `403`.** El primero es «no sé quién eres»; el segundo, «sé quién eres y no puedes». Es la diferencia entre regenerar el token y ampliar sus permisos.

## Documentación oficial

- [Managing your personal access tokens (GitHub Docs)](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) — creación de tokens clásicos y de granularidad fina, aprobación en organizaciones y revocación; la tabla de arriba sale de aquí.
- [Caching your GitHub credentials in Git](https://docs.github.com/en/get-started/getting-started-with-git/caching-your-github-credentials-in-git) — instalación de GCM y de GitHub CLI por sistema operativo.
- [Connecting to GitHub with SSH](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/about-ssh) — punto de entrada a generar la clave, añadirla a la cuenta y probar la conexión.
- [gitcredentials](https://git-scm.com/docs/gitcredentials) — cómo Git pide y guarda credenciales, y qué hacen `cache`, `store` y los helpers de plataforma.

---

*En resumen: un token es una llave recortable y caducable para Git por HTTPS; guárdalo en el almacén del sistema, nunca en la URL, y si se filtra, revócalo antes que nada.*
