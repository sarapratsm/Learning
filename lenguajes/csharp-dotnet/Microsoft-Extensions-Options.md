# Microsoft.Extensions.Options

## ¿Qué es?

`Microsoft.Extensions.Options` es la librería de .NET que implementa el **patrón Options**: tomar una sección de la configuración (`appsettings.json`, variables de entorno...) y exponerla como un objeto C# tipado, inyectable por DI, en lugar de leer claves sueltas por su nombre.

## ¿Por qué existe?

La configuración de una aplicación .NET vive en `IConfiguration`: un diccionario plano de claves y valores de texto (`"Pagos:ApiKey"`). Se puede leer directamente, pero cada lectura es una cadena mágica sin tipo, sin autocompletado y sin comprobación alguna. Una tienda online que configura su pasarela de pago así acaba con esto repartido por el código:

```csharp
// ❌ Cadenas dispersas: un tecleo no falla al compilar, falla en ejecución
var apiKey = configuration["Pagos:ApyKey"];                      // null, sin aviso
var espera = int.Parse(configuration["Pagos:TiempoEspera"]!);    // revienta al llegar aquí
```

Ejecutado con una configuración que sí tiene `Pagos:ApiKey`:

```text
apiKey = null
Unhandled exception. System.ArgumentNullException: Value cannot be null. (Parameter 's')
   at System.Int32.Parse(String s)
```

Con Options se declara una clase con lo que el componente espera, se asocia una vez a su sección y se pide ya montada:

```csharp
// ✅ Un único punto de enlace, tipado y validable
public class PasarelaPagoOptions
{
    public string ApiKey { get; set; } = "";
    public int TiempoEsperaSegundos { get; set; } = 30;
}

builder.Services.AddOptions<PasarelaPagoOptions>().BindConfiguration("Pagos");

public class PasarelaStripe(IOptions<PasarelaPagoOptions> opciones) : IPasarelaPago
{
    private readonly PasarelaPagoOptions _opciones = opciones.Value;
}
```

> Equivale a `@ConfigurationProperties` de Spring: una sección del fichero de configuración mapeada a un bean tipado.

## ¿Cuándo y para qué se usa?

Cuando un componente necesita parámetros externos que no deben ir fijos en el código: la URL y la clave de la pasarela de pago, el servidor y el puerto del correo que notifica el pedido #4711, el tamaño de página de un listado de productos, los *feature flags*. El mismo binario funciona en local, en pruebas y en producción cambiando solo el origen de la configuración.

Las dos clases de la tienda que se usan a lo largo de la guía:

```csharp
public class PasarelaPagoOptions
{
    public const string Seccion = "Pagos";

    public string ApiKey { get; set; } = "";
    public string Url { get; set; } = "";
    public int TiempoEsperaSegundos { get; set; } = 30;
}

public class CorreoOptions
{
    public string Servidor { get; set; } = "";
    public int Puerto { get; set; } = 25;
    public string[] Destinatarios { get; set; } = [];
}
```

Con el paquete `Microsoft.Extensions.Hosting` ya se dispone de `IOptions<T>`, `Configure`, `PostConfigure`, `BindConfiguration` y `ValidateOnStart`. Las salidas de la guía provienen de ejecuciones con .NET SDK 10.0.401 y paquetes `10.0.14` (2026-11-09). Para añadir paquetes, véase [NuGet](fundamentos/NuGet.md).

## De dónde sale la configuración

Options no lee ficheros: toma lo que `IConfiguration` ya cargó. `Host.CreateApplicationBuilder` (y `WebApplication.CreateBuilder`) la rellena con varias fuentes. Cuando dos fuentes definen la misma clave, **gana la que se registró después**:

| Prioridad | Fuente | Ejemplo para `Pagos:ApiKey` |
| --- | --- | --- |
| 1 (menor) | `appsettings.json` | `{ "Pagos": { "ApiKey": "..." } }` |
| 2 | `appsettings.{Environment}.json` | `appsettings.Development.json` con la misma estructura |
| 3 | Variables de entorno | `Pagos__ApiKey=...` |
| 4 (mayor) | Argumentos de línea de comandos | `--Pagos:ApiKey=...` |

En variables de entorno el separador de niveles es el **doble guion bajo** (`__`), porque `:` no es válido en el nombre de una variable en todos los sistemas. El entorno (`Development`, `Production`...) sale de `DOTNET_ENVIRONMENT` (o `ASPNETCORE_ENVIRONMENT` en una aplicación web).

Programa de consola que muestra el valor ganador (con `appsettings.json` y `appsettings.Development.json` presentes, ambos con `Pagos:ApiKey`):

```csharp
var builder = Host.CreateApplicationBuilder(args);
Console.WriteLine($"Entorno: {builder.Environment.EnvironmentName}");
Console.WriteLine($"Pagos:ApiKey = {builder.Configuration["Pagos:ApiKey"]}");
```

```bash
dotnet run                                    # DOTNET_ENVIRONMENT=Production
dotnet run                                    # DOTNET_ENVIRONMENT=Development
Pagos__ApiKey=desde-variable-de-entorno dotnet run
Pagos__ApiKey=desde-variable-de-entorno dotnet run -- --Pagos:ApiKey=desde-linea-de-comandos
```

```text
Entorno: Production    Pagos:ApiKey = desde-appsettings.json
Entorno: Development   Pagos:ApiKey = desde-appsettings.Development.json
Entorno: Development   Pagos:ApiKey = desde-variable-de-entorno
Entorno: Development   Pagos:ApiKey = desde-linea-de-comandos
```

Cada ejecución sobrescribe a la anterior, en el orden de la tabla. En desarrollo existe además la fuente de *user secrets*, que se trata en la sección de secretos.

## Enlazar y registrar

Hay dos formas habituales de asociar la clase con su sección:

```csharp
// Con OptionsBuilder: permite encadenar validación
builder.Services.AddOptions<PasarelaPagoOptions>()
    .BindConfiguration(PasarelaPagoOptions.Seccion);

// Con Configure<T>: más corto, sin validación encadenada
builder.Services.Configure<CorreoOptions>(
    builder.Configuration.GetSection("Correo"));
```

Ambas se ejecutaron en .NET 10 con el mismo resultado: la clase queda enlazada y disponible por DI. `AddOptions<T>().BindConfiguration("...")` es la forma que combina con `ValidateDataAnnotations()` y `ValidateOnStart()`, así que es la que conviene por defecto. El `Bind(IConfiguration)` explícito también existe y equivale a ella cuando ya se tiene la sección a mano.

## Consumir: `IOptions`, `IOptionsSnapshot` e `IOptionsMonitor`

| Interfaz | Tiempo de vida | Cuándo calcula el valor | Qué ve si el fichero cambia en ejecución | Úsala cuando |
| --- | --- | --- | --- | --- |
| `IOptions<T>` | Singleton | Una vez, la primera vez que se pide | Nada: el valor queda fijo hasta reiniciar | La configuración no cambia mientras corre la aplicación (el caso mayoritario) |
| `IOptionsSnapshot<T>` | Scoped | Una vez por ámbito (en web, por petición) | El valor nuevo, pero solo en ámbitos creados después del cambio | Un servicio scoped debe ver cambios de una petición a otra |
| `IOptionsMonitor<T>` | Singleton | En cada lectura de `CurrentValue` | El valor nuevo, en cuanto el proveedor detecta el cambio | Un singleton debe ver cambios en caliente, o reaccionar con `OnChange` |

### Qué ve cada una cuando se edita el fichero

Un servicio singleton lee el mismo valor por `IOptions` y por `IOptionsMonitor`; uno scoped, por `IOptionsSnapshot`. El programa escribe `appsettings.json` con `clave-v1`, arranca, imprime, reescribe el fichero con `clave-v2` y vuelve a imprimir. La recarga en caliente la hace el proveedor JSON de `Host.CreateApplicationBuilder`, que se registra con `reloadOnChange: true`:

```csharp
builder.Services.AddOptions<PasarelaPagoOptions>().BindConfiguration("Pagos");
builder.Services.AddSingleton<ServicioSingleton>();   // recibe IOptions<T> e IOptionsMonitor<T>
builder.Services.AddScoped<ServicioScoped>();         // recibe IOptionsSnapshot<T>
```

```text
[antes de editar el fichero]
  IOptions         (Singleton): clave-v1
  IOptionsMonitor  (Singleton): clave-v1
  IOptionsSnapshot (Scoped, mismo ámbito): clave-v1
  IOptionsSnapshot (Scoped, ámbito nuevo): clave-v1
[después de editar el fichero]
  IOptions         (Singleton): clave-v1
  IOptionsMonitor  (Singleton): clave-v2
  IOptionsSnapshot (Scoped, mismo ámbito): clave-v1
  IOptionsSnapshot (Scoped, ámbito nuevo): clave-v2
```

Tres lecturas distintas del mismo cambio: `IOptions` no se entera, el *monitor* lo ve ya, y el *snapshot* lo ve solo al abrir un ámbito nuevo (dentro de la petición en curso el valor es estable, que es justo su utilidad).

### Error clásico: `IOptionsSnapshot` dentro de un Singleton

`IOptionsSnapshot<T>` es scoped. Si un singleton (por ejemplo un `Notificador` registrado con `AddSingleton`) lo recibe, queda una dependencia cautiva: el singleton retendría para siempre un servicio pensado para vivir una petición. La detección depende del entorno. Con el mismo código:

```csharp
builder.Services.AddSingleton<Notificador>();   // constructor: IOptionsSnapshot<PasarelaPagoOptions>
using var host = builder.Build();
```

```text
# DOTNET_ENVIRONMENT=Development (la validación de ámbitos está activa)
Unhandled exception. System.AggregateException: Some services are not able to be constructed (Error while validating the service descriptor 'ServiceType: Notificador Lifetime: Singleton ImplementationType: Notificador': Cannot consume scoped service 'Microsoft.Extensions.Options.IOptionsSnapshot`1[PasarelaPagoOptions]' from singleton 'Notificador'.)
   ---> System.InvalidOperationException: Cannot consume scoped service '...' from singleton 'Notificador'.

# DOTNET_ENVIRONMENT=Production
(sin salida: no hay error)
```

En desarrollo el contenedor lo rechaza al construir el host; en producción la validación está desactivada y el singleton se construye sin queja, con un *snapshot* que ya no refrescará. La solución es `IOptionsMonitor<T>` en el singleton (con `CurrentValue`). El motivo de fondo es el de las dependencias cautivas, que se explica en [Inversión de dependencias](../../arquitectura-de-software/clean-architecture/Inversion-de-Dependencias.md).

### Reaccionar al cambio: `OnChange`

`IOptionsMonitor<T>.OnChange` registra un callback que se invoca cuando cambia la configuración, y devuelve un `IDisposable` con el que darse de baja:

```csharp
var monitor = host.Services.GetRequiredService<IOptionsMonitor<PasarelaPagoOptions>>();
int llamadas = 0;
using var suscripcion = monitor.OnChange((opciones, nombre) =>
    Console.WriteLine($"OnChange #{++llamadas}: ApiKey = {opciones.ApiKey}, nombre = '{nombre}'"));

File.WriteAllText(rutaJson, """{ "Pagos": { "ApiKey": "clave-v2" } }""");   // una sola edición
await Task.Delay(2000);
```

```text
OnChange #1: ApiKey = clave-v2, nombre = ''
OnChange #2: ApiKey = clave-v2, nombre = ''
Total de llamadas al callback: 2
```

Una única escritura disparó el callback dos veces (observado en Windows con `File.WriteAllText`, que trunca y luego escribe; repetido en tres ejecuciones). El callback debe ser **idempotente**: reconstruir un cliente HTTP o reiniciar una conexión por cada llamada, sin comprobar si el valor realmente cambió, repite el trabajo. Comparar con el valor anterior antes de actuar evita el efecto.

## Validar la configuración

Sin validación, una sección incompleta se enlaza igualmente y el fallo aparece más tarde, lejos de la causa. El `OptionsBuilder` ofrece cuatro piezas que se combinan:

```csharp
builder.Services.AddOptions<PasarelaPagoOptions>()
    .BindConfiguration(PasarelaPagoOptions.Seccion)
    .ValidateDataAnnotations()                       // [Required], [Range], [Url]...
    .Validate(o => !o.Url.Contains("sandbox") || o.ApiKey.StartsWith("test_"),
              "Una URL de sandbox exige una ApiKey que empiece por 'test_'.")
    .ValidateOnStart();                              // falla al arrancar

builder.Services.AddSingleton<IValidateOptions<PasarelaPagoOptions>, ValidaReintentos>();
```

```csharp
public class PasarelaPagoOptions
{
    public const string Seccion = "Pagos";

    [Required] public string ApiKey { get; set; } = "";
    [Required, Url] public string Url { get; set; } = "";
    [Range(1, 60)] public int TiempoEsperaSegundos { get; set; } = 30;
    public int Reintentos { get; set; } = 3;
}

public class ValidaReintentos : IValidateOptions<PasarelaPagoOptions>
{
    public ValidateOptionsResult Validate(string? nombre, PasarelaPagoOptions o) =>
        o.Reintentos is >= 0 and <= 5
            ? ValidateOptionsResult.Success
            : ValidateOptionsResult.Fail("Reintentos debe estar entre 0 y 5.");
}
```

- `ValidateDataAnnotations()` vive en el paquete `Microsoft.Extensions.Options.DataAnnotations`, **no incluido** en `Microsoft.Extensions.Hosting`: sin él, el compilador emite `error CS1061: "OptionsBuilder<PasarelaPagoOptions>" no contiene una definición para "ValidateDataAnnotations"`. Los atributos son los de `System.ComponentModel.DataAnnotations` (véase [Atributos](caracteristicas-del-lenguaje/Atributos.md)).
- `Validate(función, mensaje)` sirve para reglas de una línea, también entre propiedades.
- `IValidateOptions<T>` es la opción para reglas con lógica o dependencias inyectadas: se registra en DI y puede devolver varios fallos.

### Sin `ValidateOnStart`, el error llega en el primer uso

La diferencia que más importa: sin `ValidateOnStart()`, la validación se ejecuta la primera vez que alguien lee `.Value`, es decir, cuando un cliente ya está confirmando un pedido. Misma configuración inválida (`Url` mal formada, `TiempoEsperaSegundos: 500`, sin `ApiKey`), dos ejecuciones:

```text
# sin ValidateOnStart
Construyendo el host...
Host construido. Arrancando...
Aplicación en marcha. Un cliente confirma el pedido #4711...
OptionsValidationException (PasarelaPagoOptions, nombre ''):
  - DataAnnotation validation failed for 'PasarelaPagoOptions' members: 'ApiKey' with the error: 'The ApiKey field is required.'.
  - DataAnnotation validation failed for 'PasarelaPagoOptions' members: 'Url' with the error: 'The Url field is not a valid fully-qualified http, https, or ftp URL.'.
  - DataAnnotation validation failed for 'PasarelaPagoOptions' members: 'TiempoEsperaSegundos' with the error: 'The field TiempoEsperaSegundos must be between 1 and 60.'.

# con ValidateOnStart
Construyendo el host...
Host construido. Arrancando...
fail: Microsoft.Extensions.Hosting.Internal.Host[11]
      Microsoft.Extensions.Options.OptionsValidationException: DataAnnotation validation failed for 'PasarelaPagoOptions' members: 'ApiKey' ...
OptionsValidationException (PasarelaPagoOptions, nombre ''):
  - (los mismos tres fallos)
```

Con `ValidateOnStart()` la línea «Aplicación en marcha» no llega a imprimirse: el host falla en `StartAsync` con la misma `OptionsValidationException`, que expone `Failures` (la lista de mensajes), `OptionsType` y `OptionsName`. En un despliegue eso significa un arranque fallido visible, en lugar de un error en producción horas después.

Las otras dos piezas, con una configuración con URL de sandbox, `ApiKey: "live_abc"` y `Reintentos: 9`:

```text
OptionsValidationException (PasarelaPagoOptions, nombre ''):
  - Una URL de sandbox exige una ApiKey que empiece por 'test_'.
  - Reintentos debe estar entre 0 y 5.
```

### La sección que no existe

Si `Pagos` falta por completo en la configuración (un `appsettings.json` vacío, `{ }`), el enlace no falla: produce un objeto con los valores por defecto de la clase. Con `[Required]` y `ValidateOnStart()` esa omisión se convierte en un fallo de arranque:

```text
OptionsValidationException (PasarelaPagoOptions, nombre ''):
  - DataAnnotation validation failed for 'PasarelaPagoOptions' members: 'ApiKey' with the error: 'The ApiKey field is required.'.
  - DataAnnotation validation failed for 'PasarelaPagoOptions' members: 'Url' with the error: 'The Url field is required.'.
```

`[Required]` solo detecta ausencias en propiedades sin valor por defecto útil: una propiedad con `= 30` nunca estará «vacía». Los parámetros obligatorios (clave, URL) se declaran sin valor por defecto significativo, y los opcionales con él.

### Validación generada en compilación

.NET incluye un generador de código, `[OptionsValidator]`, que produce el validador a partir de los atributos sin reflexión (útil con AOT y recorte):

```csharp
[OptionsValidator]
public partial class PasarelaPagoOptionsValidator : IValidateOptions<PasarelaPagoOptions> { }

builder.Services.AddSingleton<IValidateOptions<PasarelaPagoOptions>, PasarelaPagoOptionsValidator>();
```

Compiló sin avisos en .NET 10 con solo `Microsoft.Extensions.Hosting` y, con `ApiKey` vacía y `TiempoEsperaSegundos: 500`, produjo:

```text
ApiKey: The PasarelaPagoOptions.ApiKey field is required.
TiempoEsperaSegundos: The field PasarelaPagoOptions.TiempoEsperaSegundos must be between 1 and 60.
```

Los mensajes difieren en formato de los de `ValidateDataAnnotations()`.

## Opciones con nombre y post-configuración

Con dos pasarelas (Stripe y PayPal) la clase es la misma y cambian los valores. Se registran con nombre y se piden por nombre; el nombre vacío es el de las opciones «sin nombre» de siempre:

```json
{
  "Stripe": { "ApiKey": "clave-stripe", "Url": "https://api.stripe.example" },
  "PayPal": { "ApiKey": "clave-paypal", "Url": "https://api.paypal.example" }
}
```

```csharp
builder.Services.Configure<PasarelaPagoOptions>("Stripe", builder.Configuration.GetSection("Stripe"));
builder.Services.Configure<PasarelaPagoOptions>("PayPal", builder.Configuration.GetSection("PayPal"));

public class SelectorPasarela(IOptionsMonitor<PasarelaPagoOptions> opciones)
{
    public PasarelaPagoOptions Para(string pasarela) => opciones.Get(pasarela);
}
```

Salida (`Get("Stripe")`, `Get("PayPal")` y `IOptionsSnapshot<T>.Get("PayPal")` desde un ámbito):

```text
Stripe: clave-stripe https://api.stripe.example/v1
PayPal: clave-paypal https://api.paypal.example
Snapshot.Get("PayPal"): clave-paypal
```

`IOptions<T>` no admite nombres: solo ve las opciones sin nombre. La URL de Stripe lleva `/v1` porque se añadió con `PostConfigure`, que se ejecuta después de todas las `Configure` y sirve para ajustes finales (normalizar un valor, aplicar un valor por defecto calculado):

```csharp
builder.Services.PostConfigure<PasarelaPagoOptions>("Stripe", o => o.Url = o.Url.TrimEnd('/') + "/v1");
```

## Secretos: la clave de la pasarela no va en el repositorio

`appsettings.json` se versiona. Una `ApiKey` real en él termina en el historial de git para siempre. El patrón es dejar en el fichero versionado solo valores no sensibles, y proporcionar la clave por otra fuente: *user secrets* en desarrollo y variables de entorno (o un gestor de secretos) en producción. La gestión de secretos en profundidad está en [Gestión de secretos en desarrollo](../../seguridad/gestion-de-secretos-en-desarrollo/README.md).

La herramienta `dotnet user-secrets` viene con el SDK. Se ejecutó en la carpeta del proyecto de consola de la sección de fuentes de configuración:

```bash
dotnet user-secrets init
dotnet user-secrets set "Pagos:ApiKey" "clave-secreta-local"
dotnet user-secrets list
```

```text
Set UserSecretsId to '642a23d5-f075-4b8b-af23-4830cbaa81e2' for MSBuild project '...\prio.csproj'.
Successfully saved Pagos:ApiKey to the secret store.
Pagos:ApiKey = clave-secreta-local
```

`init` añade un `UserSecretsId` al `.csproj`; el valor se guarda fuera del repositorio, en el perfil de la persona usuaria. Con `DOTNET_ENVIRONMENT=Development`, la ejecución del programa anterior imprimió `Pagos:ApiKey = clave-secreta-local`: el secreto sustituyó al valor de `appsettings.Development.json`. No se comprobó el comportamiento en `Production`.

## `IConfiguration` directa o Options

| Situación | Elección | Por qué |
| --- | --- | --- |
| Un servicio con varios parámetros relacionados (pasarela, correo) | Options | Tipado, validación y un único punto de enlace |
| Un valor que se lee una vez en `Program.cs` para decidir el arranque | `GetValue<T>` o `Get<T>()` | Registrar y validar una clase para eso es más ceremonia que beneficio |
| Configuración que debe fallar al arrancar si falta | Options con `ValidateOnStart` | `IConfiguration` nunca avisa de lo que falta |
| Lectura dinámica de claves cuyo nombre se conoce en ejecución | `IConfiguration` | Options exige una forma fija conocida en compilación |

Para el arranque, ejecutados contra el mismo `appsettings.json`:

```csharp
cfg.GetValue<int>("Pagos:TiempoEsperaSegundos");     // 10
cfg.GetValue("Pagos:Reintentos", 3);                 // 3 (clave ausente: devuelve el valor por defecto dado)
cfg.GetSection("Pagos").Get<PasarelaPagoOptions>();  // objeto enlazado
cfg.GetSection("NoExiste").Get<PasarelaPagoOptions>(); // null
cfg.GetSection("NoExiste").Exists();                 // False
```

A diferencia de `AddOptions<T>().BindConfiguration`, `Get<T>()` devuelve `null` si la sección no existe (con Options se obtiene un objeto vacío).

## Cómo diseñar la clase de opciones

El *binder* (el componente que copia los valores de la configuración a la clase) crea la instancia sin argumentos y asigna propiedades. Se ejecutaron ocho formas de clase contra `Pagos: { ApiKey: "clave", TiempoEsperaSegundos: 10 }`:

| Forma de la clase | Resultado |
| --- | --- |
| Propiedad `{ get; set; }` con valor por defecto | Enlaza (`TiempoEsperaSegundos = 10`) |
| Propiedad `{ get; init; }` | Enlaza (`10`) |
| Propiedad `required` con `set` | Enlaza (`ApiKey = clave`) |
| Propiedad solo `{ get; }` (`= 30`) | **No enlaza**: queda `30`, sin error |
| Propiedad con `{ get; private set; }` | **No enlaza**: queda `30`, sin error |
| Campo público | **No enlaza**: queda `30`, sin error |
| `record RecordPosicional(string ApiKey, int TiempoEsperaSegundos = 30)` | `MissingMethodException: Cannot dynamically create an instance of type 'RecordPosicional'. Reason: No parameterless constructor defined.` |
| Clase con constructor que exige parámetros | La misma `MissingMethodException` |

Con `IOptions<T>` hace falta, pues, una clase con constructor sin parámetros y propiedades con `set` o `init`. Un `record` sirve si se escribe con propiedades (`record PasarelaPagoOptions { public string ApiKey { get; init; } = ""; }`), no con constructor primario. Los valores por defecto (`= 30`) permiten que una clave ausente no deje la propiedad en `0` o `null`.


## Colecciones y secciones anidadas

Una lista en JSON se enlaza a un array o `List<T>`:

```json
{ "Correo": { "Servidor": "smtp.tienda.example", "Puerto": 2525,
              "Destinatarios": [ "ventas@tienda.example", "soporte@tienda.example" ] } }
```

En variables de entorno el índice va como un nivel más: `Correo__Destinatarios__0`. Los elementos se **fusionan por índice** con los del fichero, no sustituyen la lista:

```bash
Correo__Destinatarios__0=gerencia@tienda.example dotnet run
Correo__Destinatarios__0=a@t.example Correo__Destinatarios__1=b@t.example Correo__Destinatarios__2=c@t.example dotnet run
```

```text
Correo: smtp.tienda.example:2525 -> gerencia@tienda.example, soporte@tienda.example
Correo: smtp.tienda.example:2525 -> a@t.example, b@t.example, c@t.example
```

Con un solo índice, el elemento 0 se reemplaza y el 1 del fichero se conserva; con tres índices se obtiene la lista de la variable. Para sustituir una lista entera de forma fiable hay que dar todos sus índices (y, si la lista nueva es más corta que la del fichero, los sobrantes del fichero sobreviven).

## Cuándo NO usar Options

- **Un valor que se lee una sola vez en `Program.cs`**, para decidir cómo construir el host: `GetValue<T>` basta.
- **Configuración que cambia por petición o por cliente** (por ejemplo, la pasarela que corresponde a cada inquilino de una tienda multiempresa): las opciones son globales a la aplicación y a su ámbito; lo que varía por inquilino se resuelve con un contexto de inquilino, como se plantea en [Retos avanzados de multi-tenancy](../../arquitectura-de-software/multi-tenancy/Retos-Avanzados.md).
- **Datos, no configuración**: una lista de precios o el catálogo de productos van a una base de datos, no a `appsettings.json`.

## Errores frecuentes

| Síntoma | Causa | Qué hacer |
| --- | --- | --- |
| La propiedad queda con su valor por defecto y no hay ningún error | El nombre de sección no coincide (`"Pagoss"` en vez de `"Pagos"`), o la sección no existe | `[Required]` en lo obligatorio más `ValidateOnStart()`; usar una constante para el nombre de la sección |
| `OptionsValidationException: DataAnnotation validation failed for 'PasarelaPagoOptions' members: 'ApiKey' ...` | La configuración incumple una regla | Corregir la fuente; con `ValidateOnStart()` aparece al arrancar y no en el primer uso |
| `InvalidOperationException: Cannot consume scoped service '...IOptionsSnapshot`1[...]' from singleton '...'` | Un singleton recibe `IOptionsSnapshot<T>` | Usar `IOptionsMonitor<T>` en el singleton; solo se detecta en `Development` |
| El valor del fichero cambia pero el servicio sigue viendo el antiguo | Se usa `IOptions<T>` (se calcula una vez), o el proveedor no tiene `reloadOnChange` | `IOptionsMonitor<T>` en singletons, `IOptionsSnapshot<T>` en scoped |
| `MissingMethodException: Cannot dynamically create an instance of type '...'. Reason: No parameterless constructor defined.` | Clase de opciones con constructor primario o con parámetros | Propiedades con `set`/`init` y constructor sin parámetros |
| Una propiedad no recibe el valor y no hay error | Es solo `get`, tiene `private set` o es un campo | Propiedad pública con `set` o `init` |
| `error CS1061: ... no contiene una definición para "ValidateDataAnnotations"` | Falta el paquete `Microsoft.Extensions.Options.DataAnnotations` | Añadir el paquete |
| `OnChange` se ejecuta dos veces por una edición | El editor o `File.WriteAllText` generan dos eventos de fichero | Callback idempotente que compare con el valor anterior |

## Buenas prácticas avanzadas

- **Poner `ValidateOnStart()` en toda clase cuyo valor sea imprescindible.** Sin él el fallo llega a la primera persona que toca el endpoint afectado. Con él, el despliegue falla antes de recibir tráfico.
- **Elegir la interfaz por el tiempo de vida del consumidor.** `IOptions<T>` por defecto, `IOptionsSnapshot<T>` solo en servicios scoped que necesiten ver cambios entre peticiones, `IOptionsMonitor<T>` en singletons que los necesiten. Meter `IOptionsMonitor<T>` «por si acaso» añade complejidad sin beneficio.
- **Una clase de opciones por área, con la constante del nombre de sección dentro** (`PasarelaPagoOptions.Seccion`). Cada servicio inyecta solo lo que usa, y el nombre de la sección existe una vez, no duplicado entre el JSON, `Program.cs` y las pruebas.
- **Tratar el valor como inmutable.** `IOptions<T>.Value` es un objeto compartido por toda la aplicación: modificarlo en un servicio lo cambia para todos. `init` evita el error.
- **Dejar la clave de la pasarela fuera de los ficheros versionados** y comprobar que la validación exige su presencia: un entorno al que le falte `Pagos__ApiKey` debe fallar al arrancar, no cobrar sin credenciales.
- **No hacer trabajo pesado dentro de `OnChange`** sin proteger la reentrada; el callback puede llegar más de una vez por un solo cambio.

## Documentación oficial

- [Options pattern in .NET](https://learn.microsoft.com/dotnet/core/extensions/options): la referencia del patrón; incluye los apartados de interfaces, `IOptionsSnapshot`, `IOptionsMonitor`, opciones con nombre, validación y post-configuración. Es el sitio al que ir para el detalle de `OptionsBuilder`.
- [Configuration in .NET](https://learn.microsoft.com/dotnet/core/extensions/configuration): los proveedores de configuración y el enlace de jerarquías (*binding*); es el punto de partida para entender las fuentes y su orden.
- [Options pattern in ASP.NET Core](https://learn.microsoft.com/aspnet/core/fundamentals/configuration/options): el patrón visto desde una aplicación web; útil al usar `IOptionsSnapshot` con peticiones.

---

*En resumen: Options convierte una sección de configuración en una clase tipada y validable, y `ValidateOnStart` hace que una configuración mala impida arrancar en lugar de romper en producción.*
