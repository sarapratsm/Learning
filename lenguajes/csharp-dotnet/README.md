# C# y .NET — Guía de tecnologías

Guías sobre el lenguaje C# y la plataforma .NET para quien ya programa en otro lenguaje y quiere entender las piezas base sobre las que se construye cualquier aplicación .NET, antes de entrar en frameworks concretos como ASP.NET Core o Entity Framework Core.

Se organizan en tres planos: los **fundamentos** (la plataforma, el lenguaje, el build y los paquetes), las **características del lenguaje** (funcionalidades e idiomas de C#/.NET que aparecen una vez superada la sintaxis básica) y la **configuración** (cómo una aplicación lee sus ajustes externos y los expone al código de forma tipada). Los ejemplos usan una tienda online, la solución `Tienda` con los proyectos `Tienda.Dominio`, `Tienda.Aplicacion`, `Tienda.Infraestructura` y `Tienda.Api`, la misma de las colecciones de [arquitectura de software](../../arquitectura-de-software/README.md).

---

## Orden de lectura recomendado

### 1. Fundamentos

La plataforma, el lenguaje y las herramientas que convierten el código en un programa que se ejecuta.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [.NET](fundamentos/DotNET.md) | El runtime y la plataforma de ejecución: SDK, runtime, versiones y soporte, y cómo pasa un programa de C# a ejecutarse. |
| 2 | [C#](fundamentos/CSharp.md) | El lenguaje moderno: tipos, nulabilidad, `record`, *pattern matching*, `async` y LINQ. |
| 3 | [MSBuild](fundamentos/MSBuild.md) | El sistema de build: el `.csproj`, las referencias entre proyectos y los ficheros compartidos de la solución. |
| 4 | [NuGet](fundamentos/NuGet.md) | El gestor de paquetes: versiones, dependencias transitivas, bloqueo de versiones y seguridad de la cadena de suministro. |

### 2. Características del lenguaje

Funcionalidades e idiomas de .NET que se encuentran al escribir código real, más allá de la sintaxis básica.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 5 | [CancellationToken](caracteristicas-del-lenguaje/CancellationToken.md) | Cómo se propaga de extremo a extremo la petición de cancelar una operación asíncrona. |
| 6 | [Atributos](caracteristicas-del-lenguaje/Atributos.md) | Metadatos declarativos (`[Algo]`) que el framework lee por reflexión para decidir cómo tratar el código. |
| 7 | [Atributos personalizados](caracteristicas-del-lenguaje/Atributos-Personalizados.md) | Crear atributos propios y por qué sus argumentos son constantes de compilación. |

### 3. Configuración de la aplicación

Cómo una aplicación .NET (de consola, *worker* o web) lee sus ajustes externos. No es exclusivo de ningún framework: vive en el *host* de cualquier aplicación .NET.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 8 | [Microsoft.Extensions.Options](Microsoft-Extensions-Options.md) | El patrón Options: asociar una sección de configuración a una clase, consumirla con `IOptions`, `IOptionsSnapshot` o `IOptionsMonitor` y validarla al arrancar. |

---

## Comandos de `dotnet` de todos los días

| Comando | Qué hace | Ficha |
|---|---|---|
| `dotnet new` | Crea un proyecto o una solución a partir de una plantilla | [.NET](fundamentos/DotNET.md) |
| `dotnet restore` | Descarga los paquetes NuGet que declaran los proyectos | [NuGet](fundamentos/NuGet.md) |
| `dotnet build` | Restaura, compila y genera el ensamblado | [MSBuild](fundamentos/MSBuild.md) |
| `dotnet run` | Compila y ejecuta un proyecto | [.NET](fundamentos/DotNET.md) |
| `dotnet add package` | Añade una dependencia al `.csproj` | [NuGet](fundamentos/NuGet.md) |
| `dotnet publish` | Genera la carpeta lista para desplegar | [.NET](fundamentos/DotNET.md) |
| `dotnet list package --outdated` | Lista las dependencias con versiones nuevas | [NuGet](fundamentos/NuGet.md) |

## Qué fichero configura qué

| Fichero | Qué configura | Ficha |
|---|---|---|
| `*.csproj` | Un proyecto: framework de destino, referencias y paquetes | [MSBuild](fundamentos/MSBuild.md) |
| `Directory.Build.props` | Propiedades comunes a todos los proyectos de la solución | [MSBuild](fundamentos/MSBuild.md) |
| `Directory.Packages.props` | Versiones centralizadas de los paquetes NuGet | [NuGet](fundamentos/NuGet.md) |
| `global.json` | La versión del SDK de .NET que usa la solución | [.NET](fundamentos/DotNET.md) |
| `nuget.config` | Las fuentes de paquetes y su asignación | [NuGet](fundamentos/NuGet.md) |
| `appsettings.json` | Los ajustes de la aplicación en ejecución | [Microsoft.Extensions.Options](Microsoft-Extensions-Options.md) |

---

> Para ver estas piezas en un backend web: [Primeros pasos con ASP.NET Core](../../desarrollo-web/asp-net-core/README.md). Para quien viene de escritorio: [De C# WPF a C# para web](../../desarrollo-web/de-wpf-a-web/README.md).
