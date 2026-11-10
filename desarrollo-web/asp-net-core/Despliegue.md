# Despliegue de una app ASP.NET Core

## ¿Qué es?

Desplegar es llevar la aplicación del «funciona en mi máquina» a un servidor donde atiende peticiones reales de forma permanente. En ASP.NET Core son dos gestos: **publicar** (`dotnet publish`, que genera la carpeta con el artefacto compilado) y **ejecutar ese artefacto** en el destino, ya sea una máquina con un supervisor, un contenedor o un servicio en la nube. El lado de la aplicación abarca qué se publica, cómo se configura y qué tiene que hacer el código para convivir con un proxy, un orquestador y un apagado. Montar el servidor está en [Despliegue en un VPS](../../devops/despliegue-en-vps/README.md) y las imágenes en [Docker](../../devops/docker/Docker.md).

## ¿Por qué existe?

`dotnet run`, el comando con el que se desarrolla, está pensado para el equipo de quien programa: compila al vuelo, necesita el SDK completo, usa el perfil de `launchSettings.json` (que fuerza `Development`) y sirve en `localhost`. Nada de eso vale en producción, donde hace falta un artefacto ya compilado, sin herramientas de desarrollo, con la configuración del entorno real y accesible desde fuera.

> Si vienes de Node, `dotnet publish` es el `npm run build` de producción: no ejecuta la aplicación, prepara lo que se copiará al servidor. La diferencia es que el resultado trae su propio punto de entrada (`Tienda.Api.dll`) y, opcionalmente, el runtime entero.

## ¿Cuándo y para qué se usa?

Cada vez que alguien más tiene que usar la aplicación: la API de una tienda online que consume su app móvil, el backend de un blog metido en un contenedor, un panel de administración en la red interna de una empresa. El mismo artefacto se lleva a `Staging` y a `Production`; lo único que cambia entre entornos es la configuración que recibe.

## El proyecto de prueba

Todo lo que sigue se ejecutó contra `Tienda.Api`, un proyecto `dotnet new web` sobre .NET SDK 10.0.401 con estos elementos (abreviado; los fragmentos relevantes se muestran en cada sección):

- `GET /api/productos` y `GET /api/pedidos/{id}` (devuelve el pedido #4711; el parámetro `demoraMs` simula un pedido lento).
- `GET /diagnostico/peticion`: devuelve `Request.Scheme` y la IP remota que ve la aplicación.
- `GET /diagnostico/config`: devuelve el entorno y tres claves de configuración.
- `GET /health`, `/health/live` y `/health/ready`.
- `appsettings.json` con `Tienda:Nombre` = `Tienda (base)` y `Tienda:MaxLineasPorPedido` = 50, y `appsettings.Production.json` que solo sustituye `Tienda:Nombre` por `Tienda (Production)`.

Las salidas citadas provienen de ese proyecto ejecutado el 2026-11-10 en Windows 11 (`win-x64`) con el runtime 10.0.12. Lo que no se pudo ejecutar en esa máquina (Linux, systemd, nginx y la construcción de la imagen Docker) se marca como no ejecutado donde aparece.

## Publicar: qué se genera

```bash
dotnet publish -c Release -o ./publish
```

`-c Release` compila con optimizaciones y `-o` fija la carpeta de salida. Contenido de la carpeta de `Tienda.Api`:

```
Tienda.Api.deps.json
Tienda.Api.dll                       ← la aplicación (22 KB)
Tienda.Api.exe                       ← lanzador nativo (solo en Windows; en Linux no hay .exe)
Tienda.Api.pdb                       ← símbolos de depuración
Tienda.Api.runtimeconfig.json
Tienda.Api.staticwebassets.endpoints.json
appsettings.json
appsettings.Development.json
appsettings.Production.json
web.config                           ← solo lo usa IIS
```

Total: 219 KB. No hay ni una dependencia: el framework no viaja con la aplicación. Tres ficheros merecen una mirada:

- **`Tienda.Api.runtimeconfig.json`** declara qué runtime pide la aplicación: `Microsoft.NETCore.App` y `Microsoft.AspNetCore.App`, ambos en versión `10.0.0`. Es lo que el arranque compara con lo instalado en la máquina.
- **`appsettings*.json`** se copian **todos**, incluido `appsettings.Development.json`. Publicar no filtra por entorno: el que se carga lo decide la variable `ASPNETCORE_ENVIRONMENT` al ejecutar.
- **`.pdb`**: `-c Release` no elimina los símbolos de depuración de la carpeta publicada. Si no se quieren en producción, se borran o se publica con `-p:DebugType=None` (opción no probada).

Ejecutar el artefacto es lanzar el `.dll` con el *host* `dotnet`, sin SDK y sin recompilar:

```bash
cd publish
dotnet Tienda.Api.dll --urls http://localhost:6780
```

```
info: Microsoft.Hosting.Lifetime[14]
      Now listening on: http://localhost:6780
info: Microsoft.Hosting.Lifetime[0]
      Application started. Press Ctrl+C to shut down.
info: Microsoft.Hosting.Lifetime[0]
      Hosting environment: Production
info: Microsoft.Hosting.Lifetime[0]
      Content root path: C:\...\publish
```

Dos datos del log importan más adelante. Sin variable de entorno, el entorno es `Production` (no hay perfil de lanzamiento que lo cambie). Y el **content root** es el directorio desde el que se lanzó el proceso, no el de la carpeta donde vive el `.dll`; de eso depende que se encuentren los `appsettings` (véase «Errores frecuentes»).

## Dependiente del framework o autocontenido

Por defecto la publicación es **framework-dependent**: el artefacto es diminuto, pero la máquina destino necesita el runtime instalado (ASP.NET Core Runtime, no el SDK). La alternativa **self-contained** copia el runtime dentro de la carpeta y funciona en una máquina sin .NET:

```bash
dotnet publish -c Release -r win-x64 --self-contained -o ./publish-sc
```

Medido con `Tienda.Api` en `win-x64` (la columna de ficheros cuenta las entradas de la carpeta de salida):

| Variante | Opciones | Tamaño | Ficheros |
|---|---|---|---|
| Dependiente del framework | (por defecto) | 219 KB | 10 |
| Dependiente + *single-file* | `-p:PublishSingleFile=true` | 217 KB | 7 |
| Dependiente + ReadyToRun | `-p:PublishReadyToRun=true` | 247 KB | 10 |
| Autocontenida | `--self-contained -r win-x64` | 106 MB | 340 |
| Autocontenida + ReadyToRun | además `-p:PublishReadyToRun=true` | 106 MB | 340 |
| Autocontenida + *single-file* | además `-p:PublishSingleFile=true` | 99 MB | 8 |
| Autocontenida + *single-file* comprimido | además `-p:EnableCompressionInSingleFile=true` | 48 MB | 8 |

Qué es cada opción:

- **Single-file** empaqueta todos los `.dll` en un único ejecutable. En una publicación dependiente del framework apenas cambia nada porque no hay nada que empaquetar; en una autocontenida reduce 340 ficheros a 8.
- **ReadyToRun** (R2R) compila el código a nativo por adelantado para acortar el arranque, a costa de tamaño. En `Tienda.Api` el efecto sobre el tamaño es casi nulo porque el runtime ya viene precompilado y la aplicación es pequeña (+28 KB en la variante dependiente). La mejora de arranque no se midió.
- **Trimming** (`-p:PublishTrimmed=true`) elimina del paquete el código que el análisis estático no ve alcanzable. Es la única opción que recorta de verdad el tamaño autocontenido, y la que más cuesta en ASP.NET Core, como se ve a continuación.

### El trimming y las Minimal APIs

Medido con una variante reducida de la tienda (solo `GET /api/productos` y `GET /api/pedidos/{id}`, con *records* en lugar de tipos anónimos):

| Variante autocontenida | Tamaño | Ficheros |
|---|---|---|
| Sin trimming | 106 MB | 340 |
| `PublishTrimmed` | 26 MB | 132 |
| `PublishTrimmed` + single-file | 19 MB | 8 |
| `PublishTrimmed` + ReadyToRun | 41 MB | 132 |

El tamaño es atractivo y la compilación lo advierte. Con el proyecto completo, `PublishTrimmed=true` ni siquiera compila: los tipos anónimos de los endpoints hacen que el generador del delegado de petición produzca código inválido (`error CS0119: 'int' es tipo, que no es válida en el contexto indicado`), y cada `MapGet` emite el aviso `IL2026: ... has 'RequiresUnreferencedCodeAttribute' can break functionality when trimming application code`. Con la variante de *records* compila, arranca y escucha, pero **la primera petición que serializa JSON falla**:

```
fail: Microsoft.AspNetCore.Server.Kestrel[13]
      An unhandled exception was thrown by the application.
      System.NotSupportedException: JsonTypeInfo metadata for type 'ProductoResponse[]' was not
      provided by TypeInfoResolver of type '[]'. If using source generation, ensure that all
      root types passed to the serializer have been annotated with 'JsonSerializableAttribute'...
```

Con trimming, la serialización por reflexión queda desactivada y cada tipo que se devuelve hay que declararlo en un contexto de *source generation*:

```csharp
builder.Services.ConfigureHttpJsonOptions(o =>
    o.SerializerOptions.TypeInfoResolverChain.Insert(0, TiendaJsonContext.Default));

[JsonSerializable(typeof(ProductoResponse[]))]
[JsonSerializable(typeof(PedidoResponse))]
partial class TiendaJsonContext : JsonSerializerContext;
```

Con eso la variante `PublishTrimmed` + single-file (19 MB) respondió `[{"id":1,"nombre":"Teclado","precio":49.90}]` y `{"id":4711,"estado":"Pagado"}`, sin avisos de trimming. El coste real del trimming es ese: cada controlador, DTO y librería con reflexión (MVC, Entity Framework Core, la mayoría de serializadores) tiene que ser compatible, y el fallo aparece en ejecución, no al compilar.

### Cuál elegir

| Situación | Variante |
|---|---|
| Servidor o contenedor con el runtime instalado o la imagen `aspnet` | Dependiente del framework. Es la opción por defecto y la que usa el `Dockerfile` de más abajo |
| Máquina sin .NET que no se puede preparar, o versión de runtime fijada por aplicación | Autocontenida |
| Distribuir un único fichero a quien no es del equipo | Autocontenida + single-file |
| Reducir tamaño de forma drástica | Trimming, solo tras probar cada endpoint y con *source generation* |
| Reducir el tiempo de arranque (funciones, contenedores que escalan a cero) | ReadyToRun, midiendo antes |

## Dónde escucha la aplicación

Kestrel necesita saber en qué dirección y puerto escuchar. Tres mecanismos, comprobados:

```bash
# 1. Argumento de línea de comandos
dotnet Tienda.Api.dll --urls http://localhost:6780

# 2. Variable de entorno con URLs completas
ASPNETCORE_URLS=http://localhost:6781 dotnet Tienda.Api.dll

# 3. Variable de entorno solo con puertos
ASPNETCORE_HTTP_PORTS=6783 dotnet Tienda.Api.dll
```

La tercera, con `ASPNETCORE_HTTP_PORTS=6783`, produjo `Now listening on: http://[::]:6783`: escucha en **todas las interfaces**, no solo en `localhost`. Es lo que se quiere dentro de un contenedor y lo que conviene vigilar en un servidor con IP pública. Si hay un proxy en la misma máquina, `http://127.0.0.1:5000` en `ASPNETCORE_URLS` deja a Kestrel inaccesible desde fuera. Sin ningún mecanismo, la documentación fija el puerto por defecto en 5000 (no se ejecutó para no salir del rango de puertos de prueba).

## Configuración por entorno

El orden de los proveedores (`appsettings.json`, `appsettings.{Entorno}.json`, *user secrets*, variables de entorno y argumentos) y el de prioridad están explicados en [De .NET Core a ASP.NET Core](De-NET-Core-a-ASP-NET-Core.md). Lo que cambia al desplegar es quién aporta cada valor. Con `GET /diagnostico/config` sobre el mismo artefacto:

```bash
dotnet Tienda.Api.dll                                    # entorno por defecto
ASPNETCORE_ENVIRONMENT=Development dotnet Tienda.Api.dll
```

```json
{"entorno":"Production","tienda":{"nombre":"Tienda (Production)","maxLineasPorPedido":"50","cadenaConexion":null}}
{"entorno":"Development","tienda":{"nombre":"Tienda (base)","maxLineasPorPedido":"50","cadenaConexion":null}}
```

(La salida se abrevió quitando el campo `urls`.) En `Production` el nombre sale de `appsettings.Production.json` y el resto del `appsettings.json` base; en `Development` no hay sobrescritura y queda el valor base.

### Variables de entorno: `__` en lugar de `:`

La clave jerárquica `Tienda:Nombre` no es un nombre de variable de entorno válido en todos los shells, así que se escribe con **doble guion bajo**: `Tienda__Nombre`.

```bash
Tienda__Nombre="Tienda (variable de entorno)" \
Tienda__MaxLineasPorPedido=10 \
ConnectionStrings__Tienda="Host=db;Password=secreto" \
dotnet Tienda.Api.dll
```

```json
{"entorno":"Production","tienda":{"nombre":"Tienda (variable de entorno)","maxLineasPorPedido":"10","cadenaConexion":"Host=db;Password=secreto"}}
```

Las tres claves se resolvieron desde el entorno y ganaron a los JSON. Un argumento de línea de comandos gana a todo lo anterior: `--Tienda:Nombre="desde linea de comandos"` produjo `"nombre":"desde linea de comandos"` con el resto de valores intactos. Los elementos de una lista se numeran: `Proxy__KnownProxies__0=127.0.0.1`.

### Secretos fuera del repositorio

`appsettings.json` y `appsettings.Production.json` van al repositorio, así que no llevan contraseñas, claves de API ni cadenas de conexión reales. Esos valores se inyectan en el destino: variables de entorno del contenedor, un fichero de entorno con permisos restringidos, o el almacén de secretos de la nube. En el equipo de desarrollo se usan los *user secrets* (`dotnet user-secrets set "ConnectionStrings:Tienda" "..."`), que viven fuera de la carpeta del proyecto. Comprobado con el mismo artefacto publicado:

```
== Development   →  "cadenaConexion":"Host=localhost;Database=tienda;Password=solo-en-mi-maquina"
== Production    →  "cadenaConexion":null
```

Los *user secrets* solo se cargan en `Development`: son una comodidad local, no un mecanismo de producción. El detalle está en [User secrets en .NET](../../seguridad/gestion-de-secretos-en-desarrollo/User-Secrets-En-Dotnet.md) y el porqué en [Por qué los secretos no van a Git](../../seguridad/gestion-de-secretos-en-desarrollo/Por-Que-Los-Secretos-No-Van-A-Git.md).

## Detrás de un reverse proxy

En producción Kestrel rara vez da la cara a internet. Delante hay un *reverse proxy* (nginx, un balanceador de la nube, el [nginx-proxy](../../devops/despliegue-en-vps/Reverse-Proxy-con-nginx-proxy.md) del VPS) que termina el TLS y reenvía la petición a Kestrel por HTTP plano. Desde la aplicación, esa petición parece local y sin cifrar: `Request.Scheme` es `http` y la IP remota es la del proxy. El proxy informa de los datos reales con las cabeceras `X-Forwarded-Proto` y `X-Forwarded-For`; la configuración de nginx que las envía está en [Redes Docker y exposición de servicios](../../devops/despliegue-en-vps/Redes-Docker-y-Exposicion-de-Servicios.md). Que la aplicación les haga caso es cosa del middleware **ForwardedHeaders**.

```csharp
builder.Services.Configure<ForwardedHeadersOptions>(o =>
{
    o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    o.KnownProxies.Clear();
    o.KnownIPNetworks.Clear();
    o.KnownProxies.Add(IPAddress.Parse("127.0.0.1"));   // la IP del proxy
});

var app = builder.Build();
app.UseForwardedHeaders();          // antes de cualquier middleware que lea el esquema o la IP
```

(En el proyecto de prueba este bloque está detrás de un interruptor de configuración para comparar con y sin middleware; las instrucciones son las mismas. `KnownIPNetworks` es el nombre en .NET 10; `KnownNetworks` sigue existiendo pero compila con el aviso `ASPDEPR005`.)

Se simula el proxy enviando las cabeceras a mano con `curl`, a un endpoint que devuelve lo que la aplicación ve:

```bash
curl -s -H "X-Forwarded-Proto: https" -H "X-Forwarded-For: 203.0.113.7" http://127.0.0.1:6780/diagnostico/peticion
```

| Configuración | Respuesta |
|---|---|
| Sin `UseForwardedHeaders` | `{"scheme":"http","ipRemota":"127.0.0.1","host":"127.0.0.1:6780"}` |
| Con el middleware y `KnownProxies` = `127.0.0.1` | `{"scheme":"https","ipRemota":"203.0.113.7","host":"127.0.0.1:6780"}` |
| Con el middleware y `KnownProxies` = `10.0.0.5` (no coincide) | `{"scheme":"http","ipRemota":"127.0.0.1","host":"127.0.0.1:6780"}` |
| Con el middleware y `KnownProxies` = `127.0.0.1`, **sin** cabeceras | `{"scheme":"http","ipRemota":"127.0.0.1","host":"127.0.0.1:6780"}` |

La tercera fila es la importante. El middleware solo acepta las cabeceras de un remitente de la lista de proxies de confianza; si no coincide, las ignora sin avisar. Es lo que impide que cualquier cliente de internet que hable directamente con Kestrel se atribuya la IP o el esquema que quiera. Sin el middleware (primera fila) la aplicación ignora las cabeceras siempre, con la consecuencia habitual en producción: `app.UseHttpsRedirection()` redirige en bucle porque ve siempre `http`, los enlaces absolutos generados salen con `http://` y los logs registran la IP del proxy.

También existe un atajo: la variable `ASPNETCORE_FORWARDEDHEADERS_ENABLED=true` activa el middleware sin escribir código. Con ella, la misma petición desde `127.0.0.1` devolvió `{"scheme":"https","ipRemota":"203.0.113.7",...}`: **confía en cualquier remitente**, sin lista de proxies. Solo es razonable si la aplicación es inalcanzable salvo a través del proxy (una red privada de contenedores, un servicio de la nube).

Dentro de Docker la IP del proxy no es fija. Lo habitual entonces es confiar en la subred de la red de Docker con `KnownIPNetworks.Add(...)`, en lugar de en una IP concreta (no se ejecutó, no había proxy real en la máquina de pruebas).

## Health checks

Un balanceador o un orquestador necesita preguntarle a la instancia si está viva y si puede recibir tráfico. ASP.NET Core lo trae incorporado:

```csharp
builder.Services.AddHealthChecks()
    .AddCheck("catalogo", () => HealthCheckResult.Healthy("catálogo cargado"), tags: ["ready"])
    .AddCheck("base-de-datos", () => /* consulta real a la base de datos */ HealthCheckResult.Healthy(), tags: ["ready"]);

app.MapHealthChecks("/health/live", new() { Predicate = _ => false });                      // sin comprobaciones: solo «el proceso responde»
app.MapHealthChecks("/health/ready", new() { Predicate = c => c.Tags.Contains("ready") });  // las comprobaciones etiquetadas
app.MapHealthChecks("/health");                                                             // todas
```

(En el proyecto de prueba el segundo `AddCheck` devolvía `Unhealthy` cuando la variable `Salud__BdCaida` valía `true`, para simular una base de datos caída.) Con todo en orden, `curl -i http://127.0.0.1:6780/health` devolvió:

```
HTTP/1.1 200 OK
Content-Type: text/plain
Cache-Control: no-store, no-cache

Healthy
```

Con la base de datos simulada como caída:

```
$ curl -i /health         →  HTTP/1.1 503 Service Unavailable   (cuerpo: Unhealthy)
$ curl -i /health/live    →  HTTP/1.1 200 OK                    (cuerpo: Healthy)
$ curl -i /health/ready   →  HTTP/1.1 503 Service Unavailable   (cuerpo: Unhealthy)
```

El cuerpo es solo la palabra del estado (`Healthy`, `Degraded` o `Unhealthy`), y el código HTTP es lo que consume el orquestador: 503 para `Unhealthy` (comprobado) y 200 en los demás estados (`Degraded` incluido, según la documentación; no se ejecutó). Cómo se encadenan con un despliegue sin cortes está en [Estrategias de despliegue](../../devops/ci-cd/Estrategias-de-Despliegue.md). Los dos endpoints tienen significados distintos: **liveness** (`/health/live`) dice «el proceso responde», y su fallo suele significar reiniciarlo; **readiness** (`/health/ready`) dice «puede atender tráfico ahora», y su fallo significa dejar de enviarle peticiones sin reiniciarlo.

## Apagado ordenado

Un despliegue nuevo, un reinicio del supervisor o `docker stop` piden al proceso que termine con una señal (`SIGTERM` en Linux; `Ctrl+C` es `SIGINT` y sigue el mismo camino). El host de ASP.NET Core la intercepta, deja de aceptar conexiones nuevas, **espera a que terminen las peticiones en curso** y solo entonces sale. El código puede engancharse con `IHostApplicationLifetime`:

```csharp
app.Lifetime.ApplicationStopping.Register(() =>
    app.Logger.LogInformation("ApplicationStopping: dejo de aceptar peticiones nuevas"));
app.Lifetime.ApplicationStopped.Register(() =>
    app.Logger.LogInformation("ApplicationStopped: apagado completo"));
```

Prueba: se lanza una petición lenta (`GET /api/pedidos/4711?demoraMs=6000`) y, un segundo después, se envía `Ctrl+C` al proceso:

```
curl:    {"id":4711,"estado":"Pagado"} (HTTP 200, 6.196568s)
log:     Application is shutting down...
         ApplicationStopping: dejo de aceptar peticiones nuevas
         ApplicationStopped: apagado completo
proceso: terminó con código de salida 0, 5,5 s después de la señal
```

La petición en vuelo no se cortó: terminó con su 200 y el proceso salió después, con código 0. La prueba se hizo en Windows con `Ctrl+C`; el mismo camino lo recorre `SIGTERM` en Linux, pero no se ejecutó allí. El tiempo máximo de espera (`HostOptions.ShutdownTimeout`) es por defecto de 30 segundos, valor documentado que no se midió.

## Empaquetar en un contenedor

El `Dockerfile` multi-stage para .NET 10 compila con la imagen del SDK y copia el resultado a la del runtime de ASP.NET Core. El porqué de cada instrucción, el orden para aprovechar la caché y el `.dockerignore` están en [Docker](../../devops/docker/Docker.md); aquí solo cambian los nombres y la versión de la imagen.

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Tienda.Api.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish Tienda.Api.csproj -c Release -o /app/publish --no-restore -p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
USER app
ENTRYPOINT ["dotnet", "Tienda.Api.dll"]
```

`-p:UseAppHost=false` omite el lanzador nativo, que el contenedor no usa, y `USER app` ejecuta el proceso como el usuario sin privilegios que traen las imágenes de .NET 8 y posteriores.

**Este `Dockerfile` no se construyó.** La máquina de pruebas tenía Docker, pero `docker images` no mostraba `mcr.microsoft.com/dotnet/aspnet:10.0` ni `sdk:10.0`, y descargarlas quedaba fuera del alcance. No hay tamaños de imagen ni salida de `docker build` medidos para .NET 10.

### Sin contenedor: un servicio de systemd

En un servidor Linux sin Docker, el supervisor es una unidad de systemd (no ejecutada: la máquina de pruebas es Windows):

```ini
[Unit]
Description=Tienda.Api
After=network.target

[Service]
WorkingDirectory=/srv/tienda-api
ExecStart=/usr/bin/dotnet /srv/tienda-api/Tienda.Api.dll
Restart=always
User=tienda
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=ASPNETCORE_URLS=http://127.0.0.1:5000
EnvironmentFile=/etc/tienda-api.env
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
```

`WorkingDirectory` no es un detalle: fija el *content root* de la aplicación (véase la primera fila de «Errores frecuentes»). `Restart=always` es el supervisor que reinicia la aplicación si cae o si el servidor se reinicia, y `EnvironmentFile` es un lugar para los secretos, con permisos `600`. `systemctl stop` envía `SIGTERM`, el apagado ordenado de la sección anterior.

## Errores frecuentes

Cada mensaje es el que se obtuvo al reproducir el fallo.

| Síntoma | Causa | Qué hacer |
|---|---|---|
| La aplicación arranca, responde, pero la configuración llega vacía (`"nombre":null`) y no hay ningún error | Se lanzó con otro directorio de trabajo: `dotnet publish/Tienda.Api.dll` desde la carpeta superior. El log muestra `Content root path: ...\despliegue` en lugar de la carpeta publicada, y los `appsettings*.json` no se encontraron. Los ficheros de configuración son opcionales, así que su ausencia no avisa | Ejecutar con el directorio de la publicación como actual, fijar `WorkingDirectory` en el supervisor, o pasar `--contentRoot` (no se probó esta última) |
| `Failed to bind to address http://127.0.0.1:6780: address already in use.` seguido de `SocketException (10048)` / `AddressInUseException` | Otro proceso (a veces la instancia anterior que no terminó) ya escucha ese puerto | Averiguar quién lo usa (`ss -ltnp` en Linux, `netstat -ano` en Windows) o cambiar el puerto. El mensaje de la `SocketException` va en el idioma del sistema; la primera línea, no |
| `You must install or update .NET to run this application.` con `Framework: 'Microsoft.NETCore.App', version '99.0.0' (x64)` y una lista de `The following frameworks were found` | El runtime que pide `runtimeconfig.json` no está instalado. Se reprodujo cambiando a mano la versión en una copia del fichero; con un runtime de ASP.NET Core ausente, la línea `Framework:` nombra `Microsoft.AspNetCore.App` | Instalar el runtime de esa versión mayor, o publicar autocontenido |
| `HTTP 503` en `/health/ready` con `Unhealthy`, pero `/health/live` responde `200` | Una dependencia (base de datos) no está disponible; el proceso está vivo | Revisar la dependencia. Reiniciar el proceso no la arregla |
| Redirecciones HTTPS en bucle, enlaces absolutos con `http://` o la IP del proxy en todos los logs | Falta `UseForwardedHeaders`, o el proxy no está en `KnownProxies` | Véase «Detrás de un reverse proxy» |
| `System.NotSupportedException: JsonTypeInfo metadata for type 'ProductoResponse[]' was not provided by TypeInfoResolver` | Publicación con `PublishTrimmed` sin contexto de *source generation* | Véase «El trimming y las Minimal APIs» |

## Buenas prácticas avanzadas

- **Separa *liveness* de *readiness* y no metas dependencias externas en la primera.** Si `/health/live` consulta la base de datos y esta cae, el orquestador reinicia todas las instancias a la vez, que siguen sin base de datos y entran en bucle de reinicios. Con la sonda de *liveness* con `Predicate = _ => false` y las dependencias solo en *readiness*, la instancia sale del balanceador y vuelve sola cuando la dependencia se recupera.
- **Confía solo en el proxy, no en toda la red.** Una lista `KnownProxies` o `KnownIPNetworks` ajustada es lo que impide falsificar `X-Forwarded-For`: se comprobó que una IP que no coincide hace que las cabeceras se ignoren. `ASPNETCORE_FORWARDEDHEADERS_ENABLED=true` confía en cualquiera, y es una puerta abierta si Kestrel es alcanzable sin pasar por el proxy.
- **Alinea el tiempo de apagado de la aplicación con el del orquestador.** El host espera hasta 30 segundos a las peticiones en curso (por defecto), pero `docker stop` mata el contenedor a los 10 segundos si no se le indica otro plazo con `--time`, y Kubernetes usa su propio `terminationGracePeriodSeconds`. Si el plazo del orquestador es menor, el apagado ordenado no llega a completarse y se cortan peticiones. Fija los dos a propósito.
- **No actives el trimming «por el tamaño» sin probar cada ruta.** El proyecto de prueba compiló con avisos, arrancó, escuchó y falló en la primera respuesta JSON. La publicación con trimming exige serialización con *source generation* y librerías compatibles, y los errores aparecen en ejecución. Para una API en contenedor, la imagen `aspnet` con publicación dependiente del framework suele ser más barata de mantener.
- **Las migraciones de base de datos van en un paso aparte del despliegue, no en el arranque.** Con varias instancias arrancando a la vez (`Database.Migrate()` en `Program.cs`) todas intentan migrar en paralelo, sin control ni vuelta atrás. Ejecútalas como paso del pipeline antes de arrancar la versión nueva (no se ejecutó, es práctica de despliegue).
- **Fija el entorno explícitamente en el destino.** Sin variable, el entorno es `Production`, lo que es seguro; pero un `ASPNETCORE_ENVIRONMENT=Development` heredado por error expone la página de excepciones y carga los *user secrets*. Pon el entorno en la unidad de systemd o en el manifiesto del contenedor, y no dependas del valor por defecto.

## Documentación oficial

- [Host and deploy ASP.NET Core](https://learn.microsoft.com/aspnet/core/host-and-deploy/) — el índice por destino (Linux con nginx, IIS, Docker, Azure). Empieza por «Host ASP.NET Core on Linux with Nginx» si despliegas en un VPS.
- [Configure ASP.NET Core to work with proxy servers and load balancers](https://learn.microsoft.com/aspnet/core/host-and-deploy/proxy-load-balancer) — referencia de `ForwardedHeadersOptions`, `KnownProxies`, `KnownIPNetworks` y la variable `ASPNETCORE_FORWARDEDHEADERS_ENABLED`.
- [Health checks in ASP.NET Core](https://learn.microsoft.com/aspnet/core/host-and-deploy/health-checks) — filtros por etiqueta, respuestas personalizadas y comprobaciones de bases de datos.
- [.NET application publishing overview](https://learn.microsoft.com/dotnet/core/deploying/) — framework-dependent, self-contained, single-file, ReadyToRun y trimming, con las limitaciones de cada uno.

---

*En resumen: publicar produce una carpeta que se ejecuta con `dotnet Tienda.Api.dll`; lo que la hace desplegable es lo que le rodea: configuración por variables de entorno (`__`) y no por el repositorio, `UseForwardedHeaders` con la lista exacta de proxies de confianza, sondas de salud que distinguen «vivo» de «listo», un apagado que deja terminar las peticiones en curso y un supervisor o contenedor que la mantenga en marcha.*
