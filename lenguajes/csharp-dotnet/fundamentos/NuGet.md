# NuGet

## ¿Qué es?

NuGet es el gestor de paquetes de .NET: descarga, versiona y referencia librerías (de terceros o propias) para que un proyecto las use sin copiar código a mano. Un paquete es un fichero `.nupkg` (un zip) con ensamblados compilados y metadatos; el registro público es [nuget.org](https://www.nuget.org/).

## ¿Por qué existe?

Una aplicación depende de mucho código que no escribió el equipo: acceso a datos, logging, serialización, testing. Sin gestor, cada dependencia se descarga y se copia a mano, y cuando dos librerías necesitan versiones distintas de una tercera hay que arbitrar a pulso. NuGet centraliza la distribución (nuget.org o un feed privado) y resuelve las versiones de forma determinista cada vez que se compila.

> Si conoces npm: nuget.org es el registro, el `.csproj` ocupa el lugar del `package.json` y `packages.lock.json` el del `package-lock.json`. La diferencia que importa: NuGet no instala una copia de cada paquete dentro del proyecto (no hay `node_modules`), sino una única copia por versión en una carpeta global del usuario.

## ¿Cuándo y para qué se usa?

Cada vez que un proyecto de la tienda necesita código ajeno: `Tienda.Infraestructura` referencia un micro-ORM y una librería de logging, `Tienda.Api` el framework web, los proyectos de pruebas un framework de testing. También cuando `Tienda.Dominio` se quiere compartir entre soluciones como paquete interno.

Las salidas provienen de ejecutar el SDK 10.0.401 (NuGet 7.0.0) el 2026-11-09, en una máquina con configuración regional española: los mensajes de la CLI aparecen en español y se citan tal cual, con las rutas largas abreviadas con `…`.

## Añadir un paquete y restaurarlo

Añadir una dependencia es una línea de CLI que edita el `.csproj`:

```bash
dotnet add Tienda.Infraestructura package Dapper
```

```text
info :   GET https://api.nuget.org/v3-flatcontainer/dapper/2.1.89/dapper.2.1.89.nupkg
info :   OK https://api.nuget.org/v3-flatcontainer/dapper/2.1.89/dapper.2.1.89.nupkg 47 ms
info : Se ha instalado Dapper 2.1.89 de https://api.nuget.org/v3/index.json a C:\Users\MaccionUser\.nuget\packages\dapper\2.1.89 con el hash de contenido 1VjFE664…
info : Se agregó PackageReference para la versión "2.1.89" del paquete "Dapper" al archivo "…\Tienda.Infraestructura\Tienda.Infraestructura.csproj".
```

Sin `--version`, se elige la última versión estable que haya en el feed en ese momento. El cambio en el `.csproj` es un `PackageReference`:

```xml
<ItemGroup>
  <PackageReference Include="Dapper" Version="2.1.89" />
</ItemGroup>
```

`dotnet add package` ya incluye una **restauración** (*restore*): leer los `PackageReference`, resolver el grafo completo de versiones, descargar lo que falte y escribir el resultado. `dotnet build` y `dotnet run` la repiten si hace falta; `dotnet restore` la lanza sin compilar. Deja rastro en dos sitios:

| Lugar | Qué es | En el repositorio |
|---|---|---|
| `C:\Users\MaccionUser\.nuget\packages\` (`~/.nuget/packages` en Linux y macOS) | Carpeta global de paquetes: una carpeta por paquete y versión (`dapper\2.1.89\`) con el `.nupkg`, su `.nuspec` y los ensamblados en `lib\<target framework>\`. Compartida por todos los proyectos del usuario | No |
| `<proyecto>\obj\project.assets.json` | Resultado de la restauración de ese proyecto: grafo de paquetes resuelto, qué carpeta `lib\` se usa para cada *target framework* y orígenes consultados. MSBuild lo lee para saber qué ensamblados pasar al compilador | No (`obj/` se ignora) |

Dentro de `project.assets.json`, `libraries` lista `Dapper/2.1.89` con su ruta relativa a la carpeta global (`dapper/2.1.89`) y sus ficheros, entre ellos `lib/net10.0/Dapper.dll`, `lib/net8.0/Dapper.dll` y `lib/netstandard2.0/Dapper.dll`; NuGet elige la carpeta más adecuada al *target framework* del proyecto. Junto a él, `obj/` contiene `*.nuget.g.props` y `*.nuget.g.targets`, ficheros de MSBuild generados que enganchan esos paquetes al build (el funcionamiento de MSBuild está en [MSBuild](MSBuild.md)).

Consecuencia práctica: como la carpeta global actúa de caché, restaurar un paquete ya descargado no toca la red. Los paquetes descargados desde nuget.org llevan además una firma (`.signature.p7s`) que NuGet verifica al instalarlos.

## Versiones: rangos, resolución y conflictos

### Notación de versiones

Los paquetes siguen versionado semántico (SemVer): `MAYOR.MENOR.PARCHE`, donde subir el mayor puede romper compatibilidad. Es una convención del autor, no una garantía. Un sufijo tras un guion marca una versión **preliminar** (*prerelease*): `3.0.0-beta.2`. Una preliminar es anterior a su versión estable y `dotnet add package` solo la elige con `--prerelease`.

En `Version="…"` se escribe una **notación de intervalo**:

| Notación | Significa | Resuelve (si existen 2.1.35 … 2.1.89) |
|---|---|---|
| `2.1.35` | Mínimo 2.1.35 | 2.1.35, la más baja que cumple, no la última |
| `[2.1.35]` | Exactamente 2.1.35 | 2.1.35 |
| `[2.1.35,3.0.0)` | De 2.1.35 incluida a 3.0.0 excluida | 2.1.35 (de nuevo la más baja) |
| `2.1.*` | Flotante: la última 2.1.x | 2.1.89 |
| `*` | Flotante: la última versión estable | la última publicada |

Lo contraintuitivo es la primera fila: `Version="2.1.35"` **no fija** la versión, la declara como mínimo. En la práctica el resultado es 2.1.35 porque NuGet restaura la versión más baja que cumple (ver más abajo), pero otro paquete del grafo que exija 2.1.50 la subiría a 2.1.50. Las versiones flotantes solo se admiten en el proyecto, no como dependencia de un paquete, y se resuelven con lo que haya; la documentación recomienda combinarlas con *lock file* para repetibilidad.

### Qué versión gana: tres reglas

NuGet resuelve un grafo plano por proyecto con estas reglas (documentación de *dependency resolution*):

- **Versión más baja aplicable.** Se restaura la versión más baja que satisfaga todos los mínimos. Si el mínimo pedido no existe en el feed, se toma la siguiente que sí exista.
- **La dependencia directa gana.** Si un paquete aparece en el grafo como dependencia transitiva y también como `PackageReference` del propio proyecto, vale la versión del proyecto.
- **Dependencias primas.** Si dos ramas distintas piden versiones distintas y ninguna es directa, gana la más baja que cumple todos los requisitos.

El ejemplo real: `Serilog.Sinks.File 5.0.0` declara una dependencia de `Serilog (>= 2.10.0)`. Con solo ese paquete en `Tienda.Infraestructura`:

```bash
dotnet list package --include-transitive
```

```text
   Paquete de nivel superior      Solicitado   Resuelto
   > Dapper                       2.1.89       2.1.89
   > Serilog.Sinks.File           5.0.0        5.0.0

   Paquete transitivo      Resuelto
   > Serilog               2.10.0
```

Serilog 2.10.0 es la versión **más baja aplicable**, aunque existen versiones mucho más recientes. Sin `--include-transitive`, el comando solo muestra los paquetes de nivel superior.

Ahora, el conflicto. Si el proyecto declara directamente una versión **inferior** a la que exige el paquete:

```bash
dotnet add package Serilog --version 2.9.0
```

```text
error: NU1605: Advertencia como error: Degradación del paquete detectada: Serilog de 2.10.0 a 2.9.0. Haga referencia al paquete directamente desde el proyecto para seleccionar una versión diferente.
error:  Tienda.Infraestructura -> Serilog.Sinks.File 5.0.0 -> Serilog (>= 2.10.0)
error:  Tienda.Infraestructura -> Serilog (>= 2.9.0)
```

Ganaría la directa (2.9.0), pero eso incumple el mínimo de `Serilog.Sinks.File`: NuGet lo declara error (`NU1605`, degradación). La salida correcta es subir la directa, por ejemplo a `Serilog 3.1.1`, que sí gana a la transitiva y deja la resolución sin avisos. Una directa **superior** a la que exige el paquete no da problemas de resolución; que funcione en ejecución solo lo dicen las pruebas.

Otro aviso, `NU1603`, indica que un paquete pide un mínimo que no existe en el feed y NuGet toma el siguiente. Se reprodujo con un feed local que contiene `Tienda.Aplicacion 1.0.0` (dependiente de `Tienda.Dominio >= 1.1.0`) y solo `Tienda.Dominio 1.2.0`:

```text
warning NU1603: Tienda.Aplicacion 1.0.0 depende de Tienda.Dominio (>= 1.1.0), pero no se encontró Tienda.Dominio 1.1.0. Tienda.Dominio 1.2.0 se resolvió en su lugar.
```

## Consultar el estado: desactualizados y vulnerables

Tres comandos de solo lectura describen las dependencias de un proyecto o de una solución:

| Comando | Responde | Salida real |
|---|---|---|
| `dotnet list package --include-transitive` | Qué hay resuelto, directo y transitivo | Tablas como la anterior |
| `dotnet list package --outdated` | Qué tiene versión más nueva en el feed | `> Serilog.Sinks.File  5.0.0  5.0.0  7.0.0` (columnas Solicitado, Resuelto, Más reciente) |
| `dotnet list package --vulnerable [--include-transitive]` | Qué versiones tienen vulnerabilidades conocidas | Ver abajo |

`--outdated` compara con el feed; el 2026-11-09 la última de `Serilog.Sinks.File` era 7.0.0. Solo es una pista de cuánto se ha quedado atrás un paquete: no dice si la subida es segura. Existen `--deprecated` para paquetes que su autor marcó como obsoletos.

Los avisos de seguridad salen de datos que publica la propia fuente de paquetes (nuget.org); cada restauración consulta su índice de vulnerabilidades (`https://api.nuget.org/v3/vulnerabilities/index.json`). Para provocar uno se usó `Newtonsoft.Json 12.0.3`, afectada por el aviso GHSA-5crp-9r3c-p9vr (CVE-2024-21907: denegación de servicio por anidamiento muy profundo, corregida en 13.0.1; verificado en la API de GitHub Advisories el 2026-11-09):

```bash
dotnet add package Newtonsoft.Json --version 12.0.3
```

```text
warn : NU1903: El paquete "Newtonsoft.Json" 12.0.3 tiene una vulnerabilidad de gravedad alta conocida, https://github.com/advisories/GHSA-5crp-9r3c-p9vr
```

```bash
dotnet list package --vulnerable --include-transitive
```

```text
   Paquete de nivel superior      Solicitado   Resuelto   Gravedad   Dirección URL de asesoría
   > Newtonsoft.Json              12.0.3       12.0.3     High       https://github.com/advisories/GHSA-5crp-9r3c-p9vr
```

El aviso no necesita ejecutar `dotnet list`: la **auditoría de NuGet** (*NuGet Audit*) corre en cada restauración y lanza un aviso por gravedad: `NU1901` baja, `NU1902` moderada, `NU1903` alta y `NU1904` crítica (aquí se vio `NU1903`, la alta; el resto, igual de documentado, no se reprodujo). Además, `NU1900` indica que no se pudo consultar la fuente de avisos y `NU1905` que una fuente de auditoría no devuelve información. En proyectos que apuntan a `net10.0` o superior, `NuGetAuditMode` vale `all` (también audita transitivas); en versiones anteriores, `direct`.

Para que una vulnerabilidad rompa el build en lugar de quedarse en aviso:

```xml
<PropertyGroup>
  <WarningsAsErrors>$(WarningsAsErrors);NU1903;NU1904</WarningsAsErrors>
</PropertyGroup>
```

## Fijar versiones: lock files y gestión central

### Lock file

Un *lock file* guarda las versiones exactas resueltas y su hash. Se activa con una propiedad:

```xml
<PropertyGroup>
  <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
</PropertyGroup>
```

La siguiente restauración crea `packages.lock.json` junto al `.csproj`, que sí se versiona:

```json
{
  "version": 1,
  "dependencies": {
    "net10.0": {
      "Dapper": {
        "type": "Direct",
        "requested": "[2.1.35, )",
        "resolved": "2.1.35",
        "contentHash": "YKRwjVfr…"
      }
    }
  }
}
```

`requested` muestra cómo NuGet interpretó `Version="2.1.35"`: el intervalo `[2.1.35, )`, un mínimo sin tope. El hash garantiza que el contenido descargado es el mismo; los paquetes transitivos aparecen con `"type": "Transitive"`.

Con el *modo bloqueado* la restauración falla si el lock file y el `.csproj` ya no coinciden, que es lo deseable en integración continua. Cambiando `Version="2.1.35"` a `2.1.89` sin regenerar el lock:

```bash
dotnet restore --locked-mode
```

```text
error NU1004: La versión Dapper de la referencia del paquete ha cambiado de [2.1.35, ) a [2.1.89, ).El archivo de bloqueo de paquetes no es coherente con las dependencias del proyecto, por lo que la restauración no se puede ejecutar en modo bloqueado. Deshabilite la propiedad MSBuild de RestoreLockedMode o pase una opción explícita -force-evaluate para ejecutar la restauración a fin de actualizar el archivo de bloqueo.
```

`dotnet restore --force-evaluate` regenera el lock (`requested` pasa a `[2.1.89, )`). El flujo habitual: los desarrolladores actualizan versiones y suben el lock regenerado; el CI restaura con `--locked-mode` (o `RestoreLockedMode=true`) y falla si alguien cambió una versión sin actualizar el lock. Más sobre integración continua en [CI/CD](../../../devops/ci-cd/README.md).

### Gestión central de versiones

Con varios proyectos, repetir la misma versión en cada `.csproj` provoca divergencias. La **gestión central de paquetes** (*Central Package Management*) mueve las versiones a un único fichero, `Directory.Packages.props`, en la carpeta de la solución. Estructura probada, una solución con `Tienda.Dominio` y `Tienda.Infraestructura`:

```xml
<!-- Directory.Packages.props -->
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <PackageVersion Include="Dapper" Version="2.1.89" />
    <PackageVersion Include="Serilog" Version="3.1.1" />
  </ItemGroup>
</Project>
```

Los proyectos solo dicen qué paquetes usan, sin `Version`:

```xml
<!-- Tienda.Infraestructura.csproj -->
<ItemGroup>
  <PackageReference Include="Dapper" />
</ItemGroup>
<!-- Tienda.Dominio.csproj -->
<ItemGroup>
  <PackageReference Include="Serilog" />
</ItemGroup>
```

`dotnet build` compila ambos con las versiones del fichero central (`Compilación correcta`, 0 avisos). Con `ManagePackageVersionsCentrally` activo, `dotnet add package` escribe la referencia sin versión (usa la de `PackageVersion`). Si un `.csproj` reintroduce la `Version`:

```text
error NU1008: Los siguientes elementos PackageReference no pueden definir un valor para la versión: Dapper. Los proyectos que usan la Administración central de paquetes deben definir un valor de versión en un elemento PackageVersion. …
```

Para una excepción puntual en un proyecto existe el atributo `VersionOverride="2.1.35"` en el `PackageReference`: el build lo acepta, y por eso conviene revisarlos en las revisiones de código. `Directory.Packages.props` lo descubre MSBuild subiendo por las carpetas, como otros ficheros `Directory.*` ([MSBuild](MSBuild.md)). En la solución de la tienda (`Tienda.Dominio`, `Tienda.Aplicacion`, `Tienda.Infraestructura`, `Tienda.Api`) es un solo fichero junto a la solución. Nota: `dotnet new sln` con el SDK 10 crea `Tienda.slnx`, el formato de solución nuevo basado en XML, y no `Tienda.sln`.

## Fuentes de paquetes y seguridad de la cadena de suministro

Las fuentes se definen en `nuget.config`. NuGet combina el `nuget.config` de la carpeta de la solución (o del proyecto, si se restaura un `.csproj` suelto), los de las carpetas superiores y el del usuario (`%AppData%\NuGet\NuGet.Config`); lo que está más cerca de la solución tiene prioridad. `dotnet nuget list source` muestra el resultado:

```text
Orígenes registrados:
  1.  nuget.org [Habilitado]
      https://api.nuget.org/v3/index.json
  2.  <otra fuente local> [Habilitado]
  3.  <otra fuente local> [Habilitado]
```

(Las fuentes 2 y 3 son carpetas locales del usuario de la máquina de pruebas.) Los feeds privados (por ejemplo Azure Artifacts o GitHub Packages) se añaden como una fuente más con su URL; sirven para paquetes internos.

El riesgo de tener varias fuentes es la **confusión de dependencias** (*dependency confusion*): si un paquete interno se llama `Tienda.Contratos` y alguien publica en nuget.org un paquete con ese mismo nombre y una versión más alta, una restauración que consulte ambas fuentes puede descargar el ajeno. El remedio es el **mapeo de fuentes** (`packageSourceMapping`): decidir qué fuente es válida para cada patrón de identificador.

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="interno" value="../pack/paquetes" />
  </packageSources>
  <packageSourceMapping>
    <packageSource key="nuget.org">
      <package pattern="*" />
    </packageSource>
    <packageSource key="interno">
      <package pattern="Tienda.*" />
    </packageSource>
  </packageSourceMapping>
</configuration>
```

Con este fichero, `Tienda.Dominio` solo se busca en `interno` y todo lo demás en `nuget.org`. La prueba, referenciando un `Tienda.Inexistente` y un `Dapperr` (errata):

```text
error NU1101: No se encuentra el paquete Tienda.Inexistente. No existe ningún paquete con este id. en los orígenes: interno. PackageSourceMapping está habilitado. No se tuvieron en cuenta los siguientes orígenes: nuget.org.
error NU1101: No se encuentra el paquete Dapperr. No existe ningún paquete con este id. en los orígenes: nuget.org. PackageSourceMapping está habilitado. No se tuvieron en cuenta los siguientes orígenes: interno.
```

Cada id consulta solo su fuente: un `Tienda.*` publicado en nuget.org nunca se tendría en cuenta. Al activar el mapeo hay que mapear **todos** los paquetes que se usen (el `*` de nuget.org cubre el resto), o la restauración falla con `NU1101`.

Las credenciales de un feed privado no van en el `nuget.config` versionado: ni tokens ni contraseñas. Se inyectan desde el entorno del desarrollador o del CI; el razonamiento y las alternativas están en [gestión de secretos en desarrollo](../../../seguridad/gestion-de-secretos-en-desarrollo/README.md).

## Crear un paquete propio

Una librería se empaqueta con `dotnet pack`; los metadatos viven en el `.csproj`:

```xml
<PropertyGroup>
  <TargetFramework>net10.0</TargetFramework>
  <PackageId>Tienda.Dominio</PackageId>
  <Version>1.0.0</Version>
  <Description>Entidades del dominio de la tienda: Pedido, Producto y Cliente.</Description>
  <Authors>Equipo Tienda</Authors>
</PropertyGroup>
```

```bash
dotnet pack -c Release -o ../paquetes
```

```text
  Al paquete Tienda.Dominio.1.0.0 le falta un Léame. Visite https://aka.ms/nuget/authoring-best-practices/readme …
  Paquete creado correctamente '…\paquetes\Tienda.Dominio.1.0.0.nupkg'.
```

El `.nupkg` (4696 bytes) es un zip. Su contenido, leído con `System.IO.Compression` sin instalar nada:

```text
   481  _rels/.rels
   467  Tienda.Dominio.nuspec
  6144  lib/net10.0/Tienda.Dominio.dll
   465  [Content_Types].xml
   667  package/services/metadata/core-properties/nuget.psmdcp
```

`lib/net10.0/` es la carpeta que NuGet elige según el *target framework* del proyecto consumidor; `Tienda.Dominio.nuspec` es el manifiesto generado a partir del `.csproj`:

```xml
<metadata>
  <id>Tienda.Dominio</id>
  <version>1.0.0</version>
  <authors>Equipo Tienda</authors>
  <description>Entidades del dominio de la tienda: Pedido, Producto y Cliente.</description>
  <dependencies>
    <group targetFramework="net10.0" />
  </dependencies>
</metadata>
```

Las `PackageReference` del proyecto pasan a ser el bloque `<dependencies>`, y el aviso de la salida pide un fichero `README` empaquetado. Publicar el paquete (`dotnet nuget push` con una clave de API) no se ejecutó. Un directorio con `.nupkg` ya sirve como feed local, como en el ejemplo del mapeo de fuentes.

## Caché y limpieza

`dotnet nuget locals all --list` muestra las cuatro carpetas de caché de NuGet:

```text
http-cache: C:\Users\MaccionUser\AppData\Local\NuGet\v3-cache
global-packages: C:\Users\MaccionUser\.nuget\packages\
temp: C:\Users\MaccionUser\AppData\Local\Temp\NuGetScratch
plugins-cache: C:\Users\MaccionUser\AppData\Local\NuGet\plugins-cache
```

`dotnet nuget locals all --clear` (o `http-cache`, `global-packages`, `temp`, `plugins-cache` en lugar de `all`) las vacía. No se ejecutó: borraría la carpeta global del usuario y todos sus proyectos tendrían que volver a descargar todo. Es la última opción cuando una restauración falla por una caché corrupta o por un paquete que cambió de contenido bajo la misma versión; `http-cache` es la que conviene limpiar si el feed publicó algo y la máquina sigue sin verlo.

## Elegir un paquete

Añadir un paquete es adquirir código de otra persona dentro de la aplicación, con sus dependencias y sus futuros cambios.

| Criterio | Qué mirar | Señal de alarma |
|---|---|---|
| Mantenimiento | Fecha de la última versión, incidencias abiertas y respuesta del equipo | Sin versiones desde hace años y vulnerabilidades pendientes |
| Descargas | Total y tendencia en nuget.org | Pocas descargas no descartan nada; solo condicionan la confianza |
| Licencia | El elemento `license` del `.nuspec` y su texto | Cambio de licencia entre versiones mayores |
| Dependencias | Cuántas arrastra y de qué versiones (`--include-transitive`) | Dependencias que chocan con las del proyecto |
| Compatibilidad | Carpetas `lib/` del paquete y su *target framework* | Ninguna que sirva a `net10.0` (`NU1202`) |
| Firma y procedencia | Paquete firmado, propietario verificado, repositorio enlazado | Nombre parecido a otro conocido (*typosquatting*) |
| Alternativa | Si la biblioteca estándar ya lo cubre | Una dependencia para una sola función |

Un caso real de licencia: el `.nuspec` de `MediatR 12.5.0` declara `<license type="expression">Apache-2.0` y el de `MediatR 13.0.0`, `<license type="file">LICENSE.md`; lo mismo ocurre entre `FluentAssertions 7.2.0` y `8.0.0` (consultado en nuget.org el 2026-11-09). El tipo `file` significa una licencia propia empaquetada: hay que leerla antes de subir de versión mayor.

## Errores frecuentes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `NU1101: No se encuentra el paquete X. No existe ningún paquete con este id. en los orígenes: …` | Nombre mal escrito, o el paquete no está en ninguna fuente activa; con `packageSourceMapping`, la fuente que lo tiene no está mapeada para ese id | Revisar el id, `dotnet nuget list source` y el mapeo |
| `NU1102: No se encuentra el paquete Dapper con la versión (>= 2.1.9999)` seguido de `Versiones encontradas en nuget.org: 95 [ versión más cercana: 2.1.89 ]` | La versión pedida no existe | Usar la versión que sugiere el mensaje |
| `NU1202: El paquete Tienda.Dominio 1.0.0 no es compatible con net8.0 … admite: net10.0` | El paquete no tiene ensamblados para el *target framework* del proyecto | Subir el *target framework* o usar una versión del paquete que lo soporte |
| `NU1603: … depende de … (>= 1.1.0), pero no se encontró … 1.1.0. … 1.2.0 se resolvió en su lugar` | Falta en el feed la versión mínima exigida | Usarlo si es compatible; si no, publicarla o fijar otra |
| `NU1605: Degradación del paquete detectada` (error) | Una versión directa inferior a la que exige una dependencia | Subir la directa o quitar la referencia |
| `NU1004` al restaurar con `--locked-mode` | `packages.lock.json` no coincide con el `.csproj` | `dotnet restore --force-evaluate` y subir el lock |
| `NU1008` al compilar | `Version` en un `PackageReference` con gestión central activa | Mover la versión a `Directory.Packages.props` |
| La restauración falla tras cambiar `nuget.config` | Fuente inalcanzable o sin credenciales, o versiones en `~/.nuget/packages` que aún se usan | `dotnet restore -v n` para ver qué fuente falla; `dotnet nuget locals http-cache --clear` si hace falta |
| `MSB3277` (aviso de MSBuild: conflicto entre versiones distintas de un mismo ensamblado) | Dos dependencias referencian versiones distintas de un ensamblado y MSBuild elige una | Referenciar directamente la versión más alta; no se reprodujo, el diagnóstico se describe de forma general |

## Buenas prácticas avanzadas

- **Una versión sin corchetes es un mínimo, no una fijación.** `Version="2.1.35"` acepta lo que otro paquete del grafo empuje hacia arriba. Para fijar de verdad hay dos vías: `[2.1.35]` (exacta, el grafo falla si otro paquete pide más) o `packages.lock.json` con `--locked-mode` en el CI, que además fija las transitivas y verifica el hash del contenido.
- **Declara directamente los paquetes transitivos que importan.** Con la regla «la directa gana», una referencia propia a `Serilog` te protege de que un cambio en otro paquete mueva la versión que usa tu código, y es el único sitio donde un parche de seguridad de una transitiva se aplica sin esperar al paquete intermedio.
- **Trata `NU1903` y `NU1904` como errores en integración continua**, con `WarningsAsErrors`. Un aviso de vulnerabilidad que nadie lee equivale a no tener auditoría, y `NuGetAuditMode=all` ya incluye las transitivas en `net10.0`.
- **Revisa la licencia antes de subir una versión mayor**, no solo el registro de cambios: algunos paquetes muy usados han cambiado de licencia entre versiones mayores (metadatos citados en «Elegir un paquete»). Fijar la versión evita subir sin darse cuenta, a costa de dejar de recibir parches: decide con antelación si pagar, quedarse o migrar, y vigila lo fijado con `--vulnerable` y `--deprecated`.
- **Activa `packageSourceMapping` en cuanto haya una fuente privada**, porque la confusión de dependencias se produce en la restauración y el mapeo es la defensa que no depende de que alguien se acuerde de reservar el nombre en nuget.org.
- **Usa gestión central y revisa los `VersionOverride`.** Evita la divergencia silenciosa entre `Tienda.Aplicacion` y `Tienda.Infraestructura`, y deja el historial de subidas en un único fichero de diff pequeño.

## Documentación oficial

- [Resolución de dependencias](https://learn.microsoft.com/en-us/nuget/concepts/dependency-resolution) — las reglas de versión más baja aplicable, directa gana y primas; consultar ante un `NU1605` o un `NU1603` incomprensible.
- [Gestión central de paquetes](https://learn.microsoft.com/en-us/nuget/consume-packages/central-package-management) — `Directory.Packages.props`, `VersionOverride` y migración desde versiones por proyecto.
- [Mapeo de fuentes de paquetes](https://learn.microsoft.com/en-us/nuget/consume-packages/package-source-mapping) — formato de `packageSourceMapping` y el ataque que previene.
- [Auditoría de paquetes](https://learn.microsoft.com/en-us/nuget/concepts/auditing-packages) — `NuGetAudit`, `NuGetAuditMode`, los códigos `NU1900`-`NU1905` y cómo suprimir avisos.

---

*En resumen: NuGet restaura la versión más baja que cumple todos los mínimos del grafo, así que fijar versiones de verdad (lock file o gestión central), auditar vulnerabilidades y mapear las fuentes es lo que convierte una restauración en algo reproducible y de confianza.*
