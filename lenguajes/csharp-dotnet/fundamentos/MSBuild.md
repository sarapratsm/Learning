# MSBuild

## ¿Qué es?

MSBuild (Microsoft Build Engine) es el sistema de build de .NET: lee los ficheros de proyecto (`.csproj`), que son XML declarativo, y ejecuta los pasos necesarios para convertir el código fuente en ensamblados (`.dll` o `.exe`). Es de código abierto y lo usan por debajo `dotnet build`, Visual Studio y Rider.

## ¿Por qué existe?

Compilar un proyecto no es solo invocar al compilador: hay que resolver qué ficheros entran, descargar los paquetes, construir antes los proyectos de los que depende, decidir dónde se escribe el resultado y repetir todo eso igual en el portátil de cada persona y en el servidor de integración continua. MSBuild convierte ese proceso en una descripción declarativa y reproducible, en lugar de un script a mano.

Es el motor invisible de .NET: quien ejecuta `dotnet build` ya lo está usando. `dotnet build` hace, en orden, tres cosas: **restaurar** (descargar los paquetes NuGet y calcular el grafo de dependencias), **compilar** (invocar el compilador de C#, Roslyn) y **dejar el resultado** en `bin/`.

> Si ya conoces Maven o Gradle en Java, o `package.json` + los scripts de npm en JavaScript, piensa en el `.csproj` como el `pom.xml`: describe el proyecto y MSBuild es quien lo ejecuta. La diferencia es que en .NET casi todo el trabajo viene predefinido por el SDK y el `.csproj` solo cuenta lo que se sale de lo habitual.

## ¿Cuándo y para qué se usa?

En cualquier solución con varios proyectos. Los ejemplos usan una tienda online: la solución `Tienda.sln` con cuatro proyectos (`Tienda.Dominio`, `Tienda.Aplicacion`, `Tienda.Infraestructura` y `Tienda.Api`) que se referencian entre sí. MSBuild decide el orden de construcción, compila solo lo necesario y aplica a todos las mismas reglas. Se toca el `.csproj` para añadir referencias, cambiar el *target framework*, fijar reglas de calidad (avisos como errores) o enganchar un paso propio al build.

Las salidas citadas se obtuvieron con el SDK 10.0.401 (2026-11-09), con los mensajes en inglés (`DOTNET_CLI_UI_LANGUAGE=en`) y las rutas absolutas abreviadas a relativas.

## El `.csproj` de estilo SDK

El proyecto mínimo de una biblioteca de clases es esto (`Tienda.Dominio.csproj`):

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>

</Project>
```

| Línea | Qué significa |
|---|---|
| `<Project Sdk="Microsoft.NET.Sdk">` | Importa el SDK: un conjunto de ficheros `.props` y `.targets` con todo el comportamiento por defecto (compilar los `.cs`, restaurar, copiar a `bin/`...). Para una aplicación web es `Microsoft.NET.Sdk.Web`. |
| `TargetFramework` | Contra qué versión de .NET se compila (`net10.0`, `net8.0`...). Determina qué API de la plataforma se puede usar. |
| `OutputType` | Qué se genera: `Library` (la opción por defecto, un `.dll`), `Exe` (ejecutable de consola) o `WinExe`. No aparece en el ejemplo porque `Microsoft.NET.Sdk` asume `Library`; con `Microsoft.NET.Sdk.Web` el SDK lo fija a `Exe`. |
| `Nullable` | Activa el análisis de nulabilidad: el compilador avisa cuando una referencia no anulable puede quedar a `null`. |
| `ImplicitUsings` | Añade automáticamente `using` habituales (`System`, `System.Linq`, `System.Collections.Generic`...) a todos los ficheros. |

No hay lista de ficheros `.cs`: el SDK incluye por convención todo `**/*.cs` bajo la carpeta del proyecto. Tampoco hay `AssemblyName` ni `RootNamespace`: por defecto valen el nombre del fichero del proyecto.

La estructura de la solución de la tienda:

```text
Tienda.sln
Directory.Build.props
global.json
src/
├── Tienda.Dominio/            Tienda.Dominio.csproj
├── Tienda.Aplicacion/         Tienda.Aplicacion.csproj
├── Tienda.Infraestructura/    Tienda.Infraestructura.csproj
└── Tienda.Api/                Tienda.Api.csproj
```

### Qué hay detrás de `Sdk=`

El `.csproj` mínimo tiene seis líneas, pero MSBuild ve miles. `dotnet msbuild -preprocess` escribe el proyecto «expandido»: el `.csproj` con todos los ficheros importados insertados en su sitio.

```bash
dotnet msbuild src/Tienda.Dominio -preprocess:expandido.xml
```

Para `Tienda.Dominio` genera 17 304 líneas (SDK 10.0.401), cada import precedido de un comentario con el fichero de origen. Un fragmento real, el de los valores por defecto que dependen de la configuración:

```xml
<!-- User-facing configuration-specific defaults -->
<PropertyGroup Condition=" '$(Configuration)' == 'Debug' ">
  <DebugSymbols Condition=" '$(DebugSymbols)' == '' ">true</DebugSymbols>
  <Optimize Condition=" '$(Optimize)' == '' ">false</Optimize>
</PropertyGroup>
<PropertyGroup Condition=" '$(Configuration)' == 'Release' ">
  <Optimize Condition=" '$(Optimize)' == '' ">true</Optimize>
</PropertyGroup>
```

Y la regla que explica por qué no hay lista de ficheros:

```xml
<Compile Include="**/*$(DefaultLanguageSourceExtension)" Exclude="$(DefaultItemExcludes);$(DefaultExcludesInProjectFolder)" Condition=" '$(EnableDefaultCompileItems)' == 'true' " />
```

En medio del fichero aparece el contenido literal del `.csproj` (`TargetFramework`, `Nullable`, `ImplicitUsings`) entre los dos imports implícitos, `Sdk.props` antes y `Sdk.targets` después.

Para ver el resultado final de unas propiedades sin leer 17 000 líneas, `-getProperty` las evalúa (con `-getItem` se hace lo mismo con los *items*):

```bash
dotnet msbuild src/Tienda.Dominio -getProperty:TargetFramework,Nullable,LangVersion,OutputType,AssemblyName
```

```json
{
  "Properties": {
    "TargetFramework": "net10.0",
    "Nullable": "enable",
    "LangVersion": "14.0",
    "OutputType": "Library",
    "AssemblyName": "Tienda.Dominio"
  }
}
```

`LangVersion` vale `14.0` sin que el proyecto lo diga: el SDK lo deduce del `TargetFramework`.

## Referencias entre proyectos y paquetes

Hay dos tipos de referencia, y los dos son `<ItemGroup>` dentro del `.csproj`:

- `PackageReference`: un paquete NuGet (`<PackageReference Include="Dapper" Version="2.1.66" />`). Cómo se eligen, versionan y fijan está en [NuGet](NuGet.md).
- `ProjectReference`: otro proyecto de la misma solución. MSBuild lo construye antes y referencia su ensamblado.

La solución de la tienda sigue la [regla de dependencia](../../../arquitectura-de-software/clean-architecture/Regla-de-Dependencia.md): las dependencias apuntan hacia dentro. `Tienda.Dominio` no referencia a nadie; `Tienda.Aplicacion` referencia a `Tienda.Dominio`; `Tienda.Infraestructura` referencia a `Tienda.Aplicacion`; `Tienda.Api` referencia a `Tienda.Infraestructura` y a `Tienda.Aplicacion`. Se crea así:

```bash
dotnet new sln -n Tienda --format sln
dotnet new classlib -n Tienda.Dominio -o src/Tienda.Dominio -f net10.0
dotnet new classlib -n Tienda.Aplicacion -o src/Tienda.Aplicacion -f net10.0
dotnet new classlib -n Tienda.Infraestructura -o src/Tienda.Infraestructura -f net10.0
dotnet new web -n Tienda.Api -o src/Tienda.Api -f net10.0
dotnet sln add src/Tienda.Dominio src/Tienda.Aplicacion src/Tienda.Infraestructura src/Tienda.Api
dotnet add src/Tienda.Aplicacion reference src/Tienda.Dominio
dotnet add src/Tienda.Infraestructura reference src/Tienda.Aplicacion
dotnet add src/Tienda.Api reference src/Tienda.Infraestructura src/Tienda.Aplicacion
```

Con el SDK 10, `dotnet new sln` crea por defecto una solución en formato `.slnx` (XML); `--format sln` fuerza el formato clásico `Tienda.sln`. Los cuatro proyectos resultantes:

```xml
<!-- src/Tienda.Dominio/Tienda.Dominio.csproj -->
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>

</Project>
```

```xml
<!-- src/Tienda.Aplicacion/Tienda.Aplicacion.csproj -->
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\Tienda.Dominio\Tienda.Dominio.csproj" />
  </ItemGroup>

</Project>
```

```xml
<!-- src/Tienda.Infraestructura/Tienda.Infraestructura.csproj -->
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\Tienda.Aplicacion\Tienda.Aplicacion.csproj" />
  </ItemGroup>

</Project>
```

```xml
<!-- src/Tienda.Api/Tienda.Api.csproj -->
<Project Sdk="Microsoft.NET.Sdk.Web">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\Tienda.Infraestructura\Tienda.Infraestructura.csproj" />
    <ProjectReference Include="..\Tienda.Aplicacion\Tienda.Aplicacion.csproj" />
  </ItemGroup>

</Project>
```

Cada proyecto contiene una clase mínima (`Pedido` en el dominio, `ConfirmarPedido` en la aplicación, un notificador por consola en la infraestructura) y `Tienda.Api` las usa en su `Program.cs` para confirmar el pedido #4711.

Las referencias son **transitivas**: `Tienda.Api` no referencia a `Tienda.Dominio`, pero lo ve igualmente a través de `Tienda.Aplicacion`. Por eso los `.dll` de los proyectos referenciados se copian también a la carpeta `bin/` de cada proyecto que los usa.

## Compilar: la solución o un solo proyecto

`dotnet build` sobre la solución construye los cuatro proyectos, y los construye en el orden que dictan las referencias:

```bash
dotnet build Tienda.sln
```

```text
  Determining projects to restore...
  Restored src\Tienda.Api\Tienda.Api.csproj (in 97 ms).
  Restored src\Tienda.Dominio\Tienda.Dominio.csproj (in 85 ms).
  Restored src\Tienda.Aplicacion\Tienda.Aplicacion.csproj (in 97 ms).
  Restored src\Tienda.Infraestructura\Tienda.Infraestructura.csproj (in 97 ms).
  Tienda.Dominio -> src\Tienda.Dominio\bin\Debug\net10.0\Tienda.Dominio.dll
  Tienda.Aplicacion -> src\Tienda.Aplicacion\bin\Debug\net10.0\Tienda.Aplicacion.dll
  Tienda.Infraestructura -> src\Tienda.Infraestructura\bin\Debug\net10.0\Tienda.Infraestructura.dll
  Tienda.Api -> src\Tienda.Api\bin\Debug\net10.0\Tienda.Api.dll

Build succeeded.
    0 Warning(s)
    0 Error(s)
```

Las líneas `Restored` son la fase de restauración y las flechas `->` indican cada ensamblado generado. El orden `Dominio → Aplicacion → Infraestructura → Api` es el de las dependencias: nadie se construye antes que lo que referencia. (Con proyectos independientes entre sí MSBuild puede construirlos en paralelo y el orden de las líneas varía.)

Con un solo proyecto, MSBuild construye también lo que ese proyecto referencia, y solo eso:

```bash
dotnet build src/Tienda.Aplicacion
```

```text
  Tienda.Dominio -> src\Tienda.Dominio\bin\Debug\net10.0\Tienda.Dominio.dll
  Tienda.Aplicacion -> src\Tienda.Aplicacion\bin\Debug\net10.0\Tienda.Aplicacion.dll
```

Compilar `src/Tienda.Dominio` genera solo `Tienda.Dominio`; compilar `src/Tienda.Api` arrastra a los otros tres, porque dependen unos de otros. Con la ruta de una carpeta basta si contiene un único proyecto; en una carpeta con varios `.csproj` o `.sln` hay que indicar cuál.

## Configuraciones: Debug y Release

Una *configuración* es un conjunto de valores por defecto para el build. Hay dos predefinidas: `Debug` (la que se usa si no se dice nada) y `Release`, que se elige con `-c`:

```bash
dotnet build Tienda.sln -c Release
```

Las diferencias reales, leídas del propio proyecto con `-getProperty` (la propiedad se llama `Configuration`, y se fija con `-p:Configuration=Release`):

```bash
dotnet msbuild src/Tienda.Dominio -p:Configuration=Release -getProperty:Optimize,DebugType,DefineConstants,OutputPath
```

| Propiedad | `Debug` | `Release` |
|---|---|---|
| `Optimize` | `false` | `true` |
| `DefineConstants` | `TRACE;DEBUG` | `TRACE;RELEASE` |
| `DebugType` | `portable` | `portable` |
| `OutputPath` | `bin\Debug\net10.0\` | `bin\Release\net10.0\` |

`Optimize` activa las optimizaciones del compilador. `DefineConstants` define símbolos para la compilación condicional: con `Debug` existe `DEBUG`, con `Release` existe `RELEASE`. Los símbolos de depuración (`DebugType`) se generan en las dos configuraciones: el `.pdb` existe también en `Release`, lo que permite depurar un binario de producción.

La compilación condicional se ve con un `Program.cs` que lo usa:

```csharp
#if DEBUG
Console.WriteLine("Compilado en Debug");
#else
Console.WriteLine("Compilado en Release");
#endif
```

```bash
dotnet run --project src/Tienda.Api
dotnet run --project src/Tienda.Api -c Release
```

```text
Pedido #4711: Confirmado
Compilado en Debug

Pedido #4711: Confirmado
Compilado en Release
```

El bloque que no cumple la condición no llega a compilarse: no queda en el ensamblado.

### `bin/` y `obj/`

MSBuild escribe en dos carpetas dentro de cada proyecto. Estado tras compilar `Tienda.Aplicacion` en `Debug`:

```text
src/Tienda.Aplicacion/
├── bin/Debug/net10.0/
│   ├── Tienda.Aplicacion.dll       el ensamblado del proyecto
│   ├── Tienda.Aplicacion.pdb       símbolos de depuración
│   ├── Tienda.Aplicacion.deps.json descripción de dependencias para el runtime
│   └── Tienda.Dominio.dll          el proyecto referenciado, copiado
└── obj/
    ├── project.assets.json         resultado de la restauración (paquetes y grafo)
    ├── Tienda.Aplicacion.csproj.nuget.g.props / .g.targets
    └── Debug/net10.0/              ficheros intermedios: Tienda.Aplicacion.dll sin copiar,
                                    GlobalUsings.g.cs, AssemblyInfo.cs, cachés...
```

`bin/` contiene lo que se ejecuta o se distribuye; `obj/` contiene intermedios y el resultado de la restauración. Los dos son **generados y reproducibles**: se pueden borrar siempre y el siguiente `dotnet build` los recrea. Por eso no se comitean: ensucian los diffs, pesan y provocan conflictos. `dotnet new gitignore` crea un `.gitignore` estándar para .NET que ya incluye `[Bb]in/` y `[Oo]bj/`; con él, un `git status` sobre la solución compilada no lista ningún fichero de `bin/` ni `obj/`.

Cada configuración escribe en su propia subcarpeta (`bin/Debug`, `bin/Release`), así que las dos conviven sin pisarse.

## Propiedades y condiciones

Dentro de un `.csproj`, una *propiedad* es una variable de texto (`<Nullable>enable</Nullable>`) que se lee con `$(Nombre)`. Un *item* es una lista de ficheros o referencias (`<Compile>`, `<ProjectReference>`). Un `Condition` hace que un `PropertyGroup`, un `ItemGroup` o una propiedad suelta solo cuenten si se cumple una expresión:

```xml
<PropertyGroup Condition="'$(Configuration)' == 'Release'">
  <DebugType>none</DebugType>
</PropertyGroup>
```

Evaluado en cada configuración:

```bash
dotnet msbuild src/Tienda.Infraestructura -p:Configuration=Debug -getProperty:DebugType
dotnet msbuild src/Tienda.Infraestructura -p:Configuration=Release -getProperty:DebugType
```

```text
portable
none
```

Con `DebugType` a `none`, la carpeta `bin/Release/net10.0` de ese proyecto no contiene `Tienda.Infraestructura.pdb`. (Se muestra para ilustrar las condiciones; renunciar al `.pdb` en producción dificulta diagnosticar excepciones.)

Reglas de evaluación que explican la mayoría de sorpresas: MSBuild lee el proyecto de arriba abajo y **la última definición de una propiedad gana** (la documentación de personalización del build lo describe así: el orden de importación importa). Una propiedad pasada por línea de comandos con `-p:` tiene prioridad sobre las del fichero. Y las comillas simples y los espacios de `'$(Configuration)' == 'Release'` son la sintaxis habitual de las condiciones.

## Configuración compartida por toda la solución

Cuando cuatro proyectos repiten las mismas líneas, MSBuild ofrece ficheros que se aplican a todos por su sola ubicación. MSBuild busca hacia arriba desde la carpeta de cada proyecto el primer fichero con el nombre exacto y lo importa automáticamente.

### `Directory.Build.props`

En la raíz de la solución, junto a `Tienda.sln`:

```xml
<Project>

  <PropertyGroup>
    <Nullable>enable</Nullable>
    <LangVersion>latest</LangVersion>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  </PropertyGroup>

</Project>
```

Con él, `Nullable` se retira de los cuatro `.csproj` (el de `Tienda.Dominio` queda con `TargetFramework` e `ImplicitUsings`). Que lo heredan lo demuestra `-getProperty` sobre proyectos que ya no lo declaran:

```bash
dotnet msbuild src/Tienda.Dominio -getProperty:Nullable,LangVersion,TreatWarningsAsErrors
dotnet msbuild src/Tienda.Api -getProperty:Nullable,LangVersion,TreatWarningsAsErrors
```

```json
{
  "Properties": {
    "Nullable": "enable",
    "LangVersion": "latest",
    "TreatWarningsAsErrors": "true"
  }
}
```

La salida es idéntica para los dos proyectos. `dotnet new buildprops` crea una plantilla de este fichero. Hay un `Directory.Build.targets` análogo para lo que debe evaluarse después del SDK (targets y ajustes que dependen de propiedades ya calculadas).

### `Directory.Packages.props`

Fija las versiones de los paquetes NuGet en un único sitio (gestión central de versiones); los `.csproj` declaran `<PackageReference Include="Dapper" />` sin `Version`. Su funcionamiento completo está en [NuGet](NuGet.md). Si un proyecto sigue poniendo `Version` bajo gestión central, la restauración falla con `NU1008`.

```xml
<Project>

  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>

  <ItemGroup>
    <PackageVersion Include="Dapper" Version="2.1.66" />
  </ItemGroup>

</Project>
```

### `global.json`

No es un fichero de MSBuild sino del `dotnet` CLI: fija con qué versión del SDK se compila la carpeta y sus subcarpetas.

```json
{
  "sdk": {
    "version": "10.0.401",
    "rollForward": "latestFeature"
  }
}
```

`rollForward` indica cuánta libertad se deja a una versión posterior instalada: `latestFeature` acepta parches y bandas de características más nuevas de la misma versión mayor y menor. `dotnet new globaljson --sdk-version 10.0.401 --roll-forward latestFeature` lo genera. Con una versión que no está instalada y `rollForward` en `disable`, cualquier comando de `dotnet` falla:

```text
The command could not be loaded, possibly because:
  * You intended to execute a .NET application:
      The application 'build' does not exist or is not a managed .dll or .exe.
  * You intended to execute a .NET SDK command:
      A compatible .NET SDK was not found.

Requested SDK version: 10.0.999
global.json file: <ruta>\global.json
```

## Avisos y errores de análisis

El compilador emite *avisos* (`warning CSxxxx`) que no detienen el build. Una clase `Cliente` con una propiedad no anulable sin inicializar, con `Nullable` activo, produce:

```csharp
public class Cliente
{
    public string Nombre { get; set; }
}
```

```text
src\Tienda.Dominio\Pedido.cs(13,19): warning CS8618: Non-nullable property 'Nombre' must contain a non-null value when exiting constructor. Consider adding the 'required' modifier or declaring the property as nullable. [src\Tienda.Dominio\Tienda.Dominio.csproj]
    1 Warning(s)
    0 Error(s)
```

Con `TreatWarningsAsErrors` a `true` (en el `Directory.Build.props` de arriba, o por línea de comandos con `-p:TreatWarningsAsErrors=true`), el mismo código rompe el build, y la solución entera falla:

```text
src\Tienda.Dominio\Pedido.cs(13,19): error CS8618: Non-nullable property 'Nombre' must contain a non-null value when exiting constructor. Consider adding the 'required' modifier or declaring the property as nullable. [src\Tienda.Dominio\Tienda.Dominio.csproj]
Build FAILED.
    0 Warning(s)
    1 Error(s)
```

La corrección es el propio mensaje: `public required string Nombre { get; set; }`.

| Mecanismo | Efecto |
|---|---|
| `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` | Todos los avisos son errores. |
| `<WarningsAsErrors>CS8618;CS8602</WarningsAsErrors>` | Solo esos códigos son errores (con `-p:WarningsAsErrors=CS8618` también rompe el mismo caso). |
| `<WarningsNotAsErrors>CS0618</WarningsNotAsErrors>` | Con `TreatWarningsAsErrors`, esos códigos siguen siendo avisos. |
| `<NoWarn>CS1591</NoWarn>` | Silencia el aviso por completo. |
| `<Nullable>disable</Nullable>` | Desactiva el análisis de nulabilidad (el aviso de arriba desaparece). |

`dotnet build -warnaserror` es el equivalente de `TreatWarningsAsErrors` solo para esa ejecución. Un proyecto existente con cientos de avisos no se pasa a `TreatWarningsAsErrors` de golpe: se activa `WarningsAsErrors` solo para los códigos ya limpios y se amplía poco a poco.

## Targets y tareas propias

Un *target* es un paso con nombre; una *task* es una acción dentro del target (copiar ficheros, ejecutar un programa, escribir un mensaje). El SDK define cientos (`Restore`, `CoreCompile`, `Build`...). Uno propio se engancha a otro con `AfterTargets` o `BeforeTargets`:

```xml
<Target Name="MensajeFinal" AfterTargets="Build">
  <Message Importance="high" Text="Tienda.Api compilada en $(Configuration): $(TargetPath)" />
</Target>
```

Dentro de `Tienda.Api.csproj`, al compilar:

```text
  Tienda.Infraestructura -> src\Tienda.Infraestructura\bin\Debug\net10.0\Tienda.Infraestructura.dll
  Tienda.Api -> src\Tienda.Api\bin\Debug\net10.0\Tienda.Api.dll
  Tienda.Api compilada en Debug: src\Tienda.Api\bin\Debug\net10.0\Tienda.Api.dll
```

`Importance="high"` hace que el mensaje salga con la verbosidad por defecto. `dotnet build -target:MensajeFinal` ejecuta solo ese target.

En una aplicación típica casi nunca se justifica: copiar ficheros a la salida se hace con `<Content CopyToOutputDirectory="PreserveNewest" />`, la generación de código tiene *source generators* y los pasos de empaquetado o despliegue viven mejor en el pipeline de integración continua que en el `.csproj`. Un target propio tiene sentido para un paso de build que debe ocurrir igual en cualquier máquina y no tiene equivalente en el SDK.

## Multi-targeting

`TargetFrameworks` (en plural, separado por `;`) compila el mismo proyecto contra varios .NET a la vez, útil en una biblioteca consumida por aplicaciones con versiones distintas:

```xml
<TargetFrameworks>net10.0;net8.0</TargetFrameworks>
```

```text
  Tienda.Dominio -> src\Tienda.Dominio\bin\Debug\net10.0\Tienda.Dominio.dll
  Tienda.Dominio -> src\Tienda.Dominio\bin\Debug\net8.0\Tienda.Dominio.dll
```

Genera una subcarpeta por framework en `bin/Debug/`. El SDK 10.0.401 compiló el `net8.0` sin instalar nada; para frameworks cuyo paquete de referencia no está en la máquina, la restauración lo descarga de NuGet (la restauración de un proyecto con `net6.0` tardó 2,2 s en la primera ejecución frente a unos 0,1 s de las siguientes). El código tiene que compilar con la API de **todos** los frameworks: con `net6.0` en la lista, una propiedad `required` en `Tienda.Dominio` falla con `error CS0656: Missing compiler required member 'System.Runtime.CompilerServices.RequiredMemberAttribute..ctor'`, porque ese tipo no existe en .NET 6.

Un objetivo fuera de soporte avisa. En un proyecto de consola con `net6.0` (observado el 2026-11-09):

```text
warning NETSDK1138: The target framework 'net6.0' is out of support and will not receive security updates in the future. Please refer to https://aka.ms/dotnet-core-support for more information about the support policy.
```

El aviso apareció en una aplicación de consola; en una biblioteca de clases con `net6.0` y `net7.0` no apareció. La política de soporte a la que remite el aviso está en https://aka.ms/dotnet-core-support (no se consultó). El runtime y sus versiones se explican en [DotNET](DotNET.md).

## Builds reproducibles e integración continua

En un servidor, el build debe hacer exactamente lo mismo cada vez. La receta mínima separa la restauración de la compilación:

```bash
dotnet restore Tienda.sln
dotnet build Tienda.sln --no-restore -c Release -p:ContinuousIntegrationBuild=true -v:minimal
```

| Opción | Para qué |
|---|---|
| `dotnet restore` aparte | Los fallos de red o de paquetes salen en su propio paso, y se puede cachear. |
| `--no-restore` | `build` no repite la restauración. |
| `-c Release` | Compila con optimizaciones y sin `DEBUG`. |
| `-p:ContinuousIntegrationBuild=true` | Activa `DeterministicSourcePaths` (vacía sin esta opción, `true` con ella, comprobado con `-getProperty`): las rutas locales de la máquina dejan de incrustarse en los símbolos, de modo que el mismo código produce el mismo binario en máquinas distintas. |
| `-v:minimal` | Controla cuánto se escribe en el registro (`quiet`, `minimal`, `normal`, `detailed`, `diagnostic`). |
| `global.json` + `Directory.Packages.props` | Fijan la versión del SDK y de los paquetes. |

La orquestación de la integración continua se desarrolla en [`devops/ci-cd`](../../../devops/ci-cd/README.md).

### El *binlog* para diagnosticar

Cuando el build falla o se comporta de forma rara, el registro de texto no basta. El **registro binario** (`-bl`) guarda cada propiedad, import, target y mensaje de la ejecución:

```bash
dotnet build Tienda.sln --no-restore -bl
```

Escribe `msbuild.binlog` en la carpeta actual (613 KB en la solución de la tienda), y `-bl:ruta.binlog` elige el nombre. Es un fichero binario que no se lee con un editor: se abre con el [MSBuild Structured Log Viewer](https://msbuildlog.com/) (según su página, doble clic sobre el `.binlog` con el visor instalado, o un visor en línea) y en un pipeline suele subirse como artefacto del build fallido. El visor no se probó aquí: la descripción procede de la página del proyecto.

## Errores frecuentes

| Síntoma (mensaje real) | Causa y solución |
|---|---|
| `MSBUILD : error MSB1003: Specify a project or solution file. The current working directory does not contain a project or solution file.` | Se ejecutó `dotnet build` en una carpeta sin `.csproj` ni `.sln`. Entrar en la carpeta correcta o pasar la ruta. |
| `error NETSDK1004: Assets file '...\obj\project.assets.json' not found. Run a NuGet package restore to generate this file.` | Se usó `--no-restore` (o `dotnet build` sin restauración previa, p. ej. tras borrar `obj/`) sin que el proyecto estuviera restaurado. Ejecutar `dotnet restore`. |
| `error MSB3202: The project file "...\src\Tienda.Dominio\Tienda.Dominio.csproj" was not found.` | La solución lista un proyecto cuya carpeta se movió o se borró. `dotnet sln remove` o corregir la ruta. |
| `error CS0234: The type or namespace name 'Dominio' does not exist in the namespace 'Tienda' (are you missing an assembly reference?)` y `error CS0246: The type or namespace name 'Pedido' could not be found` | Falta el `ProjectReference` (o `PackageReference`) del proyecto que define el tipo. Se reproduce quitando la referencia de `Tienda.Aplicacion` a `Tienda.Dominio`. |
| `error MSB4006: There is a circular dependency in the target dependency graph involving target "_GenerateRestoreProjectPathWalk".` | Referencia circular entre proyectos (aquí, `Tienda.Dominio` referenciando a `Tienda.Api`, que depende de él a través de las demás). Los proyectos no pueden depender entre sí en círculo: la dependencia se invierte con una interfaz en la capa interna. |
| `error NU1008: The following PackageReference items cannot define a value for Version: Dapper.` | Con gestión central de versiones el `Version` va solo en `Directory.Packages.props`. |
| `A compatible .NET SDK was not found. Requested SDK version: 10.0.999` | El `global.json` pide un SDK que no está instalado. Instalarlo o relajar `rollForward`. |

## Cuándo no tocar el `.csproj` a mano

Para las operaciones habituales conviene la herramienta de línea de comandos: `dotnet add package`, `dotnet add reference`, `dotnet sln add` escriben XML correcto y evitan errores de rutas. Se edita a mano para lo que la CLI no cubre: condiciones, `Directory.Build.props`, targets propios. Dos advertencias:

- No se editan los ficheros de `obj/` ni los del SDK (el aviso de `Sdk.props` es explícito: no modificar). Todo ajuste va en el `.csproj` o en un `Directory.Build.props`.
- No se arrastra el `.csproj` entero a un proyecto nuevo copiando y pegando: el SDK ya aporta casi todo, y un proyecto largo suele ser señal de configuración que sobra o que debería vivir en `Directory.Build.props`.

## Buenas prácticas avanzadas

- **Un `.csproj` corto es un `.csproj` sano.** El estilo SDK incluye por convención ficheros, referencias implícitas y valores por defecto. Líneas como `<Compile Include="**/*.cs" />` o un `<Reference>` a una DLL del framework son restos de formatos antiguos y duplican lo que el SDK ya hace; al compararlo con `dotnet msbuild -preprocess` se ve qué ya estaba definido.
- **Las reglas de calidad van en `Directory.Build.props`, no repetidas en cada proyecto.** Un proyecto que olvida `Nullable` o `TreatWarningsAsErrors` es un hueco silencioso. Con `-getProperty` se comprueba que todos los proyectos heredan lo esperado.
- **`TreatWarningsAsErrors` global en proyectos nuevos; `WarningsAsErrors` selectivo en los heredados.** Activar el global en una base con cientos de avisos bloquea el trabajo y acaba revertido; con la lista selectiva se endurece por códigos.
- **Separa `restore` de `build` en integración continua y pasa `-p:ContinuousIntegrationBuild=true`.** Es lo que hace reproducible el binario y hace que el fallo de red se distinga del fallo de compilación. Sin `--no-restore`, `build` restaura por su cuenta.
- **Ante un build incomprensible, genera un `-bl` en lugar de subir la verbosidad.** El registro binario es navegable (qué propiedad valía qué, qué fichero importó a qué). `-v:diagnostic` produce un texto enorme y difícil de leer.
- **Fija el SDK con `global.json`.** Sin él, cada máquina usa el SDK más reciente que tenga instalado; con él, el build de un portátil y el del servidor coinciden, y los cambios de comportamiento entre SDK llegan cuando se decide actualizar.

## Documentación oficial

- [MSBuild](https://learn.microsoft.com/visualstudio/msbuild/msbuild): punto de entrada de la documentación del motor. Merece la pena para conceptos (propiedades, items, targets, tasks) cuando se escribe algo más que un `.csproj` mínimo.
- [Visión general del SDK de proyectos de .NET](https://learn.microsoft.com/dotnet/core/project-sdk/overview): qué importan implícitamente los SDK (`Microsoft.NET.Sdk`, `.Web`...), los `using` implícitos, las referencias implícitas y cómo crear un `Directory.Build.props`. Es la primera lectura cuando una propiedad «aparece de la nada».
- [Personalizar el build](https://learn.microsoft.com/visualstudio/msbuild/customize-your-build): `Directory.Build.props` y `.targets`, el orden de importación y qué fichero aplicar a cada caso. Para soluciones con varios proyectos.

## Recursos didácticos

- [MSBuild Structured Log Viewer](https://msbuildlog.com/): el visor del registro binario `-bl`, imprescindible para diagnosticar builds que no se entienden a simple vista.

---

*En resumen: MSBuild es el motor invisible tras `dotnet build`; el `.csproj` de estilo SDK solo cuenta lo que se sale de lo habitual, y lo común a toda la solución vive en `Directory.Build.props`.*
