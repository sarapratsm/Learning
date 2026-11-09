# .NET

## ¿Qué es?

.NET es la plataforma de Microsoft para ejecutar aplicaciones escritas en C# (y en F# o Visual Basic): un **runtime** que ejecuta el programa y gestiona su memoria, una **biblioteca de clases base** (*BCL*: colecciones, ficheros, red, JSON, hilos, fechas...) y un **SDK** con las herramientas para compilar, probar y publicar, todo bajo el comando `dotnet`.

## ¿Por qué existe?

Un programa C# no se compila directamente a instrucciones de un procesador concreto: se compila a un lenguaje intermedio que el runtime traduce en el momento de ejecutarlo. Eso es lo que permite que el mismo `.dll` corra en Windows, Linux o macOS, y que la memoria y la seguridad de tipos las gestione la plataforma y no cada aplicación.

> Si vienes de Java, el paralelismo es directo: el SDK es el JDK, el runtime es la JVM más la biblioteca estándar, y el IL (*Intermediate Language*) es el *bytecode*.

La historia, solo lo que evita confusiones:

| Nombre | Qué es hoy |
|---|---|
| **.NET Framework** (1.0 a 4.8) | La plataforma original, solo Windows, instalada con el sistema operativo. La 4.8 es la última: recibe parches, no funcionalidad nueva. |
| **.NET Core** (1.0 a 3.1) | La reescritura multiplataforma y de código abierto. |
| **.NET** (5 en adelante) | La unificación: se quitó el «Core» del nombre y se saltó el 4 para no chocar con .NET Framework 4.x. Es la única línea que evoluciona. |

Quien llega de aplicaciones de escritorio con «.NET Framework 4.8» debe tener presente que **«.NET 10» no es una versión posterior de lo mismo en el sentido de actualización directa**: es otra plataforma, con la misma familia de lenguajes pero otro runtime, otro SDK y otro formato de proyecto. Migrar una aplicación es una tarea de proyecto, no un cambio de número.

## ¿Cuándo y para qué se usa?

Es la base de cualquier aplicación C#: la API HTTP de una tienda online (`Tienda.Api`), un servicio en segundo plano que envía notificaciones, una herramienta de línea de comandos o una biblioteca compartida (`Tienda.Dominio`). El servidor web, la serialización, la inyección de dependencias o el acceso a datos que se usan encima ([ASP.NET Core](../../../desarrollo-web/de-wpf-a-web/ASP-NET-Core.md), Entity Framework Core) son bibliotecas que se apoyan en esta plataforma; no forman parte del runtime en sí.

## SDK, runtime y runtime de ASP.NET Core

Son tres piezas distintas y se instalan según lo que haga falta:

| Pieza | Para qué sirve | Dónde se instala |
|---|---|---|
| **SDK** | Compilar, restaurar paquetes, probar, publicar. Incluye también un runtime. | Máquina de desarrollo y agente de CI. |
| **Runtime de .NET** (`Microsoft.NETCore.App`) | Ejecutar aplicaciones de consola, servicios y bibliotecas. | Servidor de producción. |
| **Runtime de ASP.NET Core** (`Microsoft.AspNetCore.App`) | Bibliotecas adicionales para ejecutar aplicaciones web; se instala junto al runtime de .NET. | Servidor de producción, si es una API. |

(`Microsoft.WindowsDesktop.App` es el runtime de WPF y Windows Forms; solo existe en Windows.)

En un servidor de producción **solo hace falta el runtime**, no el SDK: la compilación se hace en desarrollo o en integración continua. Esta es la salida real de la máquina en la que se probó (consulta del 2026-11-09):

```bash
dotnet --list-sdks
```

```text
10.0.301 [C:\Program Files\dotnet\sdk]
10.0.401 [C:\Program Files\dotnet\sdk]
```

```bash
dotnet --list-runtimes
```

```text
Microsoft.AspNetCore.App 8.0.31 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App]
Microsoft.AspNetCore.App 10.0.9 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App]
Microsoft.AspNetCore.App 10.0.12 [C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App]
Microsoft.NETCore.App 8.0.31 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
Microsoft.NETCore.App 10.0.9 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
Microsoft.NETCore.App 10.0.12 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]
Microsoft.WindowsDesktop.App 8.0.31 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
Microsoft.WindowsDesktop.App 10.0.9 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
Microsoft.WindowsDesktop.App 10.0.12 [C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App]
```

Se observa que conviven varios SDK y varios runtimes: la instalación es lado a lado y cada aplicación declara en su `.runtimeconfig.json` qué runtime necesita. Un SDK reciente puede compilar para destinos anteriores (ver la sección de *target framework*).

## Versiones y soporte

Cada año, en noviembre, sale una versión mayor de .NET. Las pares son **LTS** (*Long Term Support*, tres años de parches) y las impares **STS** (*Standard Term Support*, hasta 12 meses después de la versión siguiente, en la práctica dos años). La calidad es la misma; solo cambia el plazo de soporte. Para soporte hay que tener instalado el último parche de la versión.

Fechas leídas en la [política de soporte](https://dotnet.microsoft.com/platform/support/policy/dotnet-core) el 2026-11-09:

| Versión | Tipo | Lanzamiento | Fin de soporte | Fase (según la página) |
|---|---|---|---|---|
| .NET 10 | LTS | 11 nov 2025 | 14 nov 2028 | Active |
| .NET 9 | STS | 12 nov 2024 | 10 nov 2026 | Maintenance |
| .NET 8 | LTS | 14 nov 2023 | 10 nov 2026 | Maintenance |

En esa misma consulta la página listaba .NET 11 solo como *release candidate* (RC3). La versión vigente en una máquina concreta se comprueba con `dotnet --version`: en la máquina de las pruebas devolvió `10.0.401`, mientras que la página indicaba `10.0.14` como último parche del runtime 10, frente al `10.0.12` instalado (los parches de runtime y SDK se numeran por separado). Con estos plazos, un proyecto nuevo elige la LTS vigente, y una aplicación en producción sobre una versión sin soporte deja de recibir parches de seguridad.

## Cómo se ejecuta un programa

El camino del código al procesador tiene dos traducciones:

1. **C# → IL.** El compilador (Roslyn) genera un **ensamblado**: un `.dll` o `.exe` con el IL, los metadatos de tipos y el manifiesto. No contiene instrucciones de procesador.
2. **IL → código nativo.** En el arranque, el runtime traduce con el compilador **JIT** (*Just-In-Time*) cada método la primera vez que se llama, y reutiliza el resultado.

Se comprueba con un programa mínimo (`dotnet new console`) al que se añade:

```csharp
using System.Reflection;
using System.Runtime.InteropServices;

Console.WriteLine(RuntimeInformation.FrameworkDescription);
Console.WriteLine(typeof(object).Assembly.Location);
Console.WriteLine(Assembly.GetExecutingAssembly().GetName());
Console.WriteLine(System.Runtime.CompilerServices.RuntimeFeature.IsDynamicCodeCompiled);
```

```bash
dotnet run
```

```text
.NET 10.0.12
C:\Program Files\dotnet\shared\Microsoft.NETCore.App\10.0.12\System.Private.CoreLib.dll
Hola, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null
True
```

`System.Private.CoreLib.dll` es el ensamblado que contiene `object`, `string` y el núcleo de la BCL: pertenece al runtime, no a la aplicación. `IsDynamicCodeCompiled` en `True` indica que hay JIT activo.

Tras `dotnet build`, la carpeta `bin/Debug/net10.0/` contiene:

```text
  406 Hola.deps.json
 4608 Hola.dll
162304 Hola.exe
10956 Hola.pdb
  270 Hola.runtimeconfig.json
```

`Hola.dll` (4,5 KB) es el programa en IL; no se puede ejecutar sin runtime y por eso `dotnet bin/Debug/net10.0/Hola.dll` lo arranca con el host `dotnet`. `Hola.exe` es un **apphost**: un pequeño ejecutable nativo de Windows (cabecera `MZ`, 159 KB) que localiza el runtime y carga `Hola.dll`; no contiene el programa. `Hola.runtimeconfig.json` declara qué runtime pide (`"name": "Microsoft.NETCore.App"`, `"version": "10.0.0"`) y `Hola.deps.json` las dependencias. El `.pdb` son los símbolos de depuración.

### Tiered compilation, ReadyToRun y Native AOT

El JIT tiene un coste de arranque, y .NET ofrece tres estrategias:

- **Tiered compilation** (activa por defecto): los métodos se compilan primero rápido y poco optimizados, y los que se llaman mucho se recompilan con optimización completa mientras el programa corre.
- **ReadyToRun** (`PublishReadyToRun`): el `.dll` incluye ya código nativo precompilado junto al IL, de modo que el arranque apenas necesita JIT; el IL sigue ahí y el JIT puede recompilar.
- **Native AOT** (`PublishAot`): se compila todo a un ejecutable nativo sin IL ni JIT, sin runtime instalado.

| | JIT con tiered (por defecto) | ReadyToRun | Native AOT |
|---|---|---|---|
| Arranque | El más lento | Mejor | El mejor |
| Tamaño | El más pequeño | Mayor (el `.dll` incluye nativo) | Un único ejecutable; sin runtime aparte |
| Reflexión y código dinámico | Completos | Completos | Limitados: lo que se resuelve en ejecución puede no estar compilado |
| Necesita runtime en destino | Sí | Sí | No |
| Herramientas adicionales | Ninguna | Ninguna (se descargan como paquetes NuGet) | Enlazador nativo de C++ |

Mediciones de esta máquina con el programa mínimo: `Hola.dll` de 5120 bytes en `Release` pasa a **20480 bytes** con `-p:PublishReadyToRun=true -r win-x64`. El arranque no se midió.

**Native AOT no se pudo probar**: `dotnet publish -c Release -r win-x64 -p:PublishAot=true` descargó el paquete del compilador y falló al enlazar:

```text
error : Platform linker not found. Ensure you have all the required prerequisites documented at https://aka.ms/nativeaot-prerequisites, in particular the Desktop Development for C++ workload in Visual Studio.
```

Hace falta instalar las herramientas de C++; las cifras de tamaño y arranque de AOT quedan sin medir. Además, `Microsoft.DotNet.ILCompiler` 10.0.12 produjo el aviso `NU1903` (vulnerabilidad de gravedad alta conocida): conviene actualizar al último parche antes de usarlo.

## El recolector de basura

La memoria de los objetos creados con `new` la libera el **recolector de basura** (GC) cuando ya nada los referencia, sin `free` ni conteo manual. Es **generacional**: los objetos nuevos viven en la generación 0, se revisan a menudo y casi todos mueren ahí; los que sobreviven pasan a la 1 y luego a la 2, que se revisa pocas veces. Así la mayoría de recolecciones son baratas.

El GC solo conoce memoria administrada. **No libera recursos no administrados** (conexiones, ficheros, *sockets*, manejadores del sistema) ni decide cuándo hacerlo: para eso existe `IDisposable` y la instrucción `using`, que llama a `Dispose` al salir del ámbito. Ejemplo mínimo:

```csharp
using var conexion = new Recurso("conexión a la base de datos");
using var archivo = new Recurso("fichero de factura");
Console.WriteLine("Pedido #4711 confirmado");

var huerfano = new Recurso("recurso sin using");
huerfano = null;
GC.Collect();
GC.WaitForPendingFinalizers();
Console.WriteLine($"Generación del objeto vivo: {GC.GetGeneration(conexion)}");
GC.Collect();
Console.WriteLine($"Generación tras otra recolección: {GC.GetGeneration(conexion)}");
Console.WriteLine("Fin de Main");

sealed class Recurso(string nombre) : IDisposable
{
    public void Dispose() => Console.WriteLine($"Dispose: {nombre}");
}
```

```text
Pedido #4711 confirmado
Generación del objeto vivo: 1
Generación tras otra recolección: 2
Fin de Main
Dispose: fichero de factura
Dispose: conexión a la base de datos
```

Tres lecciones de la salida: los `using` se liberan **al final del ámbito y en orden inverso** al de declaración (la factura antes que la conexión); el objeto `huerfano` fue recolectado como memoria pero **nunca imprimió `Dispose`**, porque el GC no lo llama; y el objeto vivo fue ascendiendo de generación (1, luego 2) con cada recolección que sobrevivió. Las llamadas a `GC.Collect` son solo para la demostración: en una aplicación real no se fuerzan.

## La CLI `dotnet`

| Comando | Qué hace |
|---|---|
| `dotnet new <plantilla>` | Crea un proyecto, solución o fichero (`console`, `classlib`, `webapi`, `xunit`, `sln`). |
| `dotnet build` | Restaura paquetes y compila. Deja el resultado en `bin/<Configuración>/<tfm>/`. |
| `dotnet run` | Compila si hace falta y ejecuta el proyecto. |
| `dotnet test` | Compila y ejecuta las pruebas. |
| `dotnet publish` | Produce la carpeta lista para desplegar. |
| `dotnet sln add` / `dotnet add reference` | Añade proyectos a la solución y referencias entre proyectos. |

### Recorrido: la solución de la tienda

Se crea la solución con tres de sus proyectos (la capa de infraestructura se omite por brevedad) y las referencias en el sentido de la arquitectura: la API depende de Aplicación, y esta de Dominio.

```bash
dotnet new sln -n Tienda
dotnet new classlib -n Tienda.Dominio
dotnet new classlib -n Tienda.Aplicacion
dotnet new webapi -n Tienda.Api
dotnet sln add Tienda.Dominio Tienda.Aplicacion Tienda.Api
dotnet add Tienda.Aplicacion reference Tienda.Dominio
dotnet add Tienda.Api reference Tienda.Aplicacion
```

```text
Se ha agregado el proyecto "Tienda.Dominio\Tienda.Dominio.csproj" a la solución.
Se ha agregado el proyecto "Tienda.Aplicacion\Tienda.Aplicacion.csproj" a la solución.
Se ha agregado el proyecto "Tienda.Api\Tienda.Api.csproj" a la solución.
Se ha agregado la referencia "..\Tienda.Dominio\Tienda.Dominio.csproj" al proyecto.
Se ha agregado la referencia "..\Tienda.Aplicacion\Tienda.Aplicacion.csproj" al proyecto.
```

Con el SDK 10.0.401, `dotnet new sln` creó **`Tienda.slnx`**, el formato XML nuevo, y no el `.sln` clásico (los dos se admiten):

```text
Tienda.slnx
Tienda.Api/            Program.cs, Tienda.Api.csproj, Tienda.Api.http, appsettings.json,
                       appsettings.Development.json, Properties/launchSettings.json
Tienda.Aplicacion/     Class1.cs, Tienda.Aplicacion.csproj
Tienda.Dominio/        Class1.cs, Tienda.Dominio.csproj
```

```xml
<Solution>
  <Project Path="Tienda.Api/Tienda.Api.csproj" />
  <Project Path="Tienda.Aplicacion/Tienda.Aplicacion.csproj" />
  <Project Path="Tienda.Dominio/Tienda.Dominio.csproj" />
</Solution>
```

`dotnet build` en la raíz compila los tres proyectos (`Compilación correcta. 0 Advertencia(s) 0 Errores`), y `dotnet run --project Tienda.Api --urls http://localhost:7431` arrancó la API:

```text
info: Microsoft.Hosting.Lifetime[14]
      Now listening on: http://localhost:7431
info: Microsoft.Hosting.Lifetime[0]
      Application started. Press Ctrl+C to shut down.
```

(La plantilla incluye un endpoint de ejemplo, `/weatherforecast`, que respondió con un JSON.) Qué contiene cada `.csproj` se explica en [MSBuild](MSBuild.md); los paquetes, en [NuGet](NuGet.md).

## Publicar para desplegar

`dotnet publish -c Release` genera la carpeta que se copia al servidor. Hay dos modos de empaquetar el runtime:

- **Dependiente del framework** (por defecto): la carpeta solo trae la aplicación; el servidor debe tener el runtime instalado.
- **Autocontenido** (`--self-contained`, necesita `-r <RID>`, por ejemplo `-r win-x64` o `linux-x64`): la carpeta incluye el runtime y la BCL.

| | Dependiente del framework | Autocontenido |
|---|---|---|
| Tamaño | Mínimo | Decenas de MB |
| Requisito en el servidor | Runtime de la versión adecuada | Ninguno |
| Parches de seguridad del runtime | Los aplica quien administra el servidor, sin recompilar | Hay que republicar la aplicación |
| Varias aplicaciones en un servidor | Comparten un único runtime | Cada una lleva su copia |
| Cuándo | Servidores propios, contenedores con imagen base de .NET | Entornos donde no se puede instalar nada, o versiones distintas de runtime por aplicación |

Medido en esta máquina con el programa mínimo (`Release`, `win-x64`, SDK 10.0.401):

| Comando | Resultado |
|---|---|
| `dotnet publish -c Release` | 0,2 MB, 5 ficheros (`Hola.dll` de 5120 bytes + apphost de 162304 bytes) |
| `dotnet publish -c Release -r win-x64 --self-contained` | 76,8 MB, 192 ficheros |
| El anterior con `-p:PublishSingleFile=true` | 70,1 MB, 2 ficheros (`Hola.exe` de 73 524 915 bytes y el `.pdb`) |

El autocontenido arranca sin runtime instalado: `./pub-sc/Hola.exe` imprimió `.NET 10.0.12` y cargó `System.Private.CoreLib.dll` desde su propia carpeta. El *single-file* empaqueta todo en un único `.exe`, lo que cambia `Assembly.Location` (devuelve cadena vacía; el compilador avisa con `IL3000`).

## Fijar la versión del SDK con `global.json`

Un `global.json` en la raíz de la solución fija qué SDK usa `dotnet` en esa carpeta y sus subcarpetas, para que todo el equipo y la integración continua compilen igual:

```json
{
  "sdk": {
    "version": "10.0.301",
    "rollForward": "disable"
  }
}
```

`rollForward` decide cuánta flexibilidad se admite: `disable` exige exactamente esa versión; `latestFeature` (con `"version": "10.0.100"`) admitió el `10.0.401` instalado. Con una versión que la máquina no tiene (`9.0.100` y `disable`):

```text
The command could not be loaded, possibly because:
  * You intended to execute a .NET application:
      The application '--version' does not exist or is not a managed .dll or .exe.
  * You intended to execute a .NET SDK command:
      A compatible .NET SDK was not found.

Requested SDK version: 9.0.100
global.json file: ...\tienda\global.json

Installed SDKs:

Install the [9.0.100] .NET SDK or update [...\tienda\global.json] to match an installed SDK.
```

El mensaje sale aunque se ejecute `dotnet build` o `dotnet --version`, porque la resolución del SDK ocurre antes. Referencia de todas las opciones en [global.json](https://learn.microsoft.com/dotnet/core/tools/global-json).

## Target framework y compatibilidad

El `.csproj` declara para qué plataforma se compila con el *target framework moniker*: `net10.0` (.NET 10), `net8.0`, o `netstandard2.0`, un contrato antiguo de API que permite a una biblioteca usarse desde .NET Framework y desde .NET moderno. Una aplicación ejecutable apunta a `net10.0`; una biblioteca que debe consumir también código antiguo apunta a `netstandard2.0` o a varios destinos. El detalle de la propiedad está en [MSBuild](MSBuild.md).

El SDK nuevo compila para destinos antiguos (sin verificar en esta máquina), pero un SDK antiguo no puede compilar para un destino más nuevo (`NETSDK1045`, ver errores). En ejecución, cada aplicación pide un runtime de su versión mayor; el runtime avanza por sí solo a parches nuevos, pero no cambia de versión mayor salvo configuración explícita (*roll forward*, sin verificar aquí).

## Cuándo no .NET

.NET encaja bien en backends tipados, servicios de larga duración y aplicaciones de escritorio de Windows; no es la mejor opción en todos los casos. Un guion de administración de pocas líneas se escribe antes en Python o Bash; un frontend de navegador es JavaScript o TypeScript (Blazor existe, pero es otro compromiso); una función serverless con arranque en frío crítico exige medir JIT frente a Native AOT antes de decidir; y un equipo con toda su experiencia y su infraestructura en otro ecosistema (JVM, Node) paga un coste real de adopción que debe compensar algo concreto.

## Errores frecuentes

| Síntoma | Causa y solución |
|---|---|
| `You must install or update .NET to run this application.` ... `Framework: 'Microsoft.NETCore.App', version '99.0.0' (x64)`, código de salida 150 | El runtime que pide el `.runtimeconfig.json` no está instalado (se reprodujo cambiando `"version"` a `99.0.0`). El mensaje lista los runtimes encontrados y un enlace de descarga. Instalar el runtime de esa versión, o publicar autocontenido. |
| `error NETSDK1045: El SDK de .NET actual no admite el destino .NET 11.0` | El `TargetFramework` del proyecto (aquí `net11.0`) es más nuevo que el SDK instalado (10.0.401). Instalar un SDK de esa versión o bajar el `TargetFramework`. |
| `A compatible .NET SDK was not found. Requested SDK version: 9.0.100` | El `global.json` pide un SDK que la máquina no tiene. Instalarlo o ajustar el fichero. |
| `Platform linker not found` al publicar con `PublishAot=true` | Falta el enlazador de C++ (en Windows, la carga de trabajo *Desktop Development for C++*). |
| La aplicación funciona en el equipo del desarrollo y no en el servidor | El servidor tiene un runtime distinto o ninguno: comparar `dotnet --list-runtimes` en ambos. |

## Buenas prácticas avanzadas

- **Una LTS para producción, y fecha de fin de soporte en el calendario.** Elegir versión por su fecha de fin de soporte, no por su novedad; planificar la migración antes de que expire.
- **Fijar el SDK con `global.json` y actualizarlo a propósito.** Evita que un SDK nuevo cambie el comportamiento del build en una máquina sí y en otra no.
- **Desplegar dependiente del framework mientras se pueda y mantener el runtime al día.** Los parches de seguridad llegan al runtime sin recompilar; con autocontenido, cada parche exige republicar.
- **Liberar con `using` todo `IDisposable`, sin esperar al GC.** El recolector nunca llama a `Dispose` por ti en el momento oportuno.
- **No usar `GC.Collect()` en producción.** Fuerza una recolección completa y suele empeorar la latencia; el GC se ajusta mejor solo.
- **Medir antes de pasar a Native AOT o ReadyToRun.** Ambos tienen restricciones (reflexión, enlazador) y su ganancia depende del programa.

## Documentación oficial

- [¿Qué es .NET?](https://learn.microsoft.com/dotnet/core/introduction): punto de entrada de la documentación de la plataforma; sirve para la visión de conjunto y para navegar a cada tema.
- [Política de soporte de .NET](https://dotnet.microsoft.com/platform/support/policy/dotnet-core): tabla de versiones, tipo (LTS/STS) y fechas de fin de soporte; consultarla antes de elegir o migrar de versión.
- [Native AOT](https://learn.microsoft.com/dotnet/core/deploying/native-aot): requisitos previos y limitaciones de la compilación nativa.
- [ReadyToRun](https://learn.microsoft.com/dotnet/core/deploying/ready-to-run): compilación previa de ensamblados.
- [Fundamentos del recolector de basura](https://learn.microsoft.com/dotnet/standard/garbage-collection/fundamentals): generaciones y funcionamiento del GC.

---
*En resumen: .NET es el runtime que traduce IL a código nativo, la biblioteca que lo acompaña y la CLI `dotnet`; en producción basta el runtime, la versión se fija con `global.json` y el GC libera memoria, no recursos.*
