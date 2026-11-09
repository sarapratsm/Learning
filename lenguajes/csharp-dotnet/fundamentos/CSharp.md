# C#

## ¿Qué es?

C# es un lenguaje de programación de tipado estático, compilado a un lenguaje intermedio (IL) que el runtime de .NET ejecuta, y orientado a objetos con rasgos funcionales (expresiones lambda, LINQ, *pattern matching*, tipos inmutables). Es el lenguaje de referencia de .NET y el habitual en un backend: la plataforma, el runtime y el SDK se explican en [.NET](DotNET.md).

## ¿Por qué existe?

Un backend necesita un lenguaje con la productividad de uno de alto nivel (recolección de basura, genéricos, `async`/`await`, una biblioteca estándar amplia) y el rendimiento de uno compilado. C# lo ofrece y evoluciona cada año con la plataforma: gran parte de las novedades recientes (constructores primarios, `record`, tipos de referencia que no admiten `null`) quitan código repetitivo y convierten errores de ejecución en avisos de compilación.

> Analogía: el compilador de C# es un revisor que lee el código antes de que se ejecute. Con las características modernas activadas, rechaza o avisa de lo que antes explotaba en producción, como una referencia nula sin comprobar o una propiedad que nadie inicializó.

## ¿Cuándo y para qué se usa?

Para escribir toda la lógica de una aplicación .NET: en una tienda online, las entidades (`Pedido`, `Producto`, `Cliente`), los casos de uso (`ConfirmarPedido`), los servicios (`IPasarelaPago`, `INotificador`) y los endpoints de `Tienda.Api`. C# solo es el lenguaje: no define rutas HTTP, serialización JSON ni acceso a datos, que aportan ASP.NET Core y otras bibliotecas; tampoco se ejecuta en el navegador. Esta guía cubre lo que distingue al C# actual y lo que más aparece en código de backend, no la sintaxis completa.

## Versión del lenguaje

Cada versión de .NET trae una versión de C#, y el SDK elige la del lenguaje a partir del `TargetFramework` del proyecto. La propiedad `LangVersion` del `.csproj` la fija a mano (`<LangVersion>13</LangVersion>`, `latest`, `preview`). La versión efectiva se consulta con MSBuild; las salidas provienen de un proyecto de consola creado con el SDK 10.0.401 (`dotnet --version`):

```bash
dotnet msbuild -getProperty:LangVersion
dotnet msbuild -getProperty:LangVersion -p:TargetFramework=net8.0
```

```text
14.0
12.0
```

Resultado completo, consultado el 2026-11-09:

| `TargetFramework` | C# por defecto |
|---|---|
| `net8.0` | 12.0 |
| `net9.0` | 13.0 |
| `net10.0` | 14.0 |

La documentación de Microsoft sobre la configuración de la versión del lenguaje indica que el compilador solo acepta la sintaxis incluida en la versión elegida. Una característica de una versión posterior falla con un error concreto. Con `-p:LangVersion=13`, la palabra clave `field` (C# 14) produce:

```text
error CS9260: Feature 'field keyword' is not available in C# 13.0. Please use language version 14.0 or greater.
```

Fijar `LangVersion` por debajo del valor por defecto casi nunca compensa: lo habitual es subir el `TargetFramework`. Dónde vive esa propiedad en el build se explica en [MSBuild](MSBuild.md).

## Tipos: valor, referencia y registros

### Valor frente a referencia

Una `struct` es un tipo de valor: asignarla copia los datos. Una `class` es un tipo de referencia: asignarla copia la referencia, y ambas variables apuntan al mismo objeto.

```csharp
var sA = new PuntoS(1, 2); var sB = sA; sB.X = 99;
var cA = new PuntoC(1, 2); var cB = cA; cB.X = 99;
Console.WriteLine($"struct: original={sA.X}, copia={sB.X}");
Console.WriteLine($"class:  original={cA.X}, copia={cB.X}");

struct PuntoS(int x, int y) { public int X = x; public int Y = y; }
class PuntoC(int x, int y) { public int X = x; public int Y = y; }
```

```text
struct: original=1, copia=99
class:  original=99, copia=99
```

La misma regla afecta a los argumentos de un método: una `struct` se pasa por copia y una `class`, por referencia a su objeto.

### `record` y `record struct`

Un `record` es una clase pensada para datos: el compilador genera igualdad por valor, `ToString()` legible y la expresión `with` para crear una copia modificada. Un `record struct` hace lo mismo sobre una `struct`.

```csharp
var l1 = new LineaPedido(4711, "Teclado", 2);
var l2 = new LineaPedido(4711, "Teclado", 2);
Console.WriteLine($"record == : {l1 == l2}; ReferenceEquals: {ReferenceEquals(l1, l2)}");
Console.WriteLine(l1 with { Cantidad = 5 });
var c1 = new PuntoC(1, 2); var c2 = new PuntoC(1, 2);
Console.WriteLine($"class == : {c1 == c2}");

record LineaPedido(int PedidoId, string Producto, int Cantidad);
record struct Dinero(decimal Importe, string Moneda);
```

```text
record == : True; ReferenceEquals: False
LineaPedido { PedidoId = 4711, Producto = Teclado, Cantidad = 5 }
class == : False
```

Los parámetros de un `record` posicional se convierten en propiedades `init` (solo asignables al crear el objeto): el registro es inmutable salvo que se declare lo contrario. Es la forma habitual de escribir un DTO.

### `enum`, tuplas y `string`

- `enum`: conjunto de constantes con nombre sobre un entero (`enum EstadoPedido { Nuevo, Pagado, Enviado }`). Conviene no persistir ni exponer el número, sino el nombre o un valor explícito, porque insertar un miembro en medio cambia los números siguientes.
- Tuplas: agrupan valores sin declarar un tipo, con nombres opcionales. Sirven para devolver dos valores desde un método privado; para algo que cruza capas, un `record`.

  ```csharp
  (int Min, int Max) rango = (1, 9);   // rango.Min, rango.Max
  var (min, max) = rango;              // deconstrucción
  ```

- `string`: es un tipo de referencia **inmutable**. Métodos como `ToUpper()` devuelven una cadena nueva y no modifican la original (`"hola"` sigue siendo `hola` tras `s.ToUpper()`). La interpolación `$"Pedido #{pedido.Id}: {pedido.Total:N2}"` admite formato tras los dos puntos, que depende de la cultura del proceso. Para concatenar en un bucle grande se usa `StringBuilder`.

## Nulabilidad

Con los *nullable reference types* activados, un tipo de referencia **no admite** `null` salvo que se declare con `?`: `string` es «nunca nulo» y `string?` es «puede ser nulo». Es una comprobación del compilador, no del runtime: no cambia cómo se ejecuta el programa, solo emite avisos. Se activa con `<Nullable>enable</Nullable>` en el `.csproj` (las plantillas actuales ya lo incluyen) o por fichero con `#nullable enable`.

Este código genera los avisos de la derecha:

```csharp
string? buscar(int id) => id == 1 ? "Ana" : null;
string a = buscar(2);                    // CS8600
Console.WriteLine(buscar(2).Length);     // CS8602
M(buscar(2));                            // CS8604
static void M(string s) => Console.WriteLine(s);
class Cliente { public string Nombre { get; set; } }   // CS8618
```

```text
(2,12): warning CS8600: Converting null literal or possible null value to non-nullable type.
(3,19): warning CS8602: Dereference of a possibly null reference.
(4,3): warning CS8604: Possible null reference argument for parameter 's' in 'void M(string s)'.
(8,31): warning CS8618: Non-nullable property 'Nombre' must contain a non-null value when exiting constructor. Consider adding the 'required' modifier or declaring the property as nullable.
```

Los operadores para manejarlo:

| Operador | Qué hace | Ejemplo |
|---|---|---|
| `?.` | Accede solo si no es nulo; si lo es, el resultado es nulo | `cliente?.Correo?.Length` |
| `??` | Valor alternativo si es nulo | `cliente?.Correo ?? "sin correo"` |
| `??=` | Asigna solo si es nulo | `cache ??= CargarCatalogo();` |
| `!` | Afirma al compilador «no es nulo» y silencia el aviso | `buscar(1)!.Length` |

El operador `!` no comprueba nada: si el valor resulta ser nulo, la excepción llega igual (`NullReferenceException: Object reference not set to an instance of an object`). Es legítimo cuando se sabe algo que el compilador no puede inferir, por ejemplo en una prueba. No lo es para acallar un aviso: lo correcto es comprobar (`if (x is null) return ...;`), cambiar el tipo a `string?` o garantizar la inicialización con `required`.

## Lo moderno que más se ve en código real

Cada característica sustituye una forma antigua más larga. Salvo que se indique otra versión, se compila con C# 12 o anterior; todos los ejemplos se ejecutaron con el SDK 10.

### Constructores primarios (C# 12)

Los parámetros de la clase se declaran junto al nombre y están disponibles en todo el cuerpo.

```csharp
// ❌ Forma antigua
class ConfirmarPedido
{
    private readonly IPasarelaPago _pasarela;
    public ConfirmarPedido(IPasarelaPago pasarela) { _pasarela = pasarela; }
}

// ✅ Constructor primario
class ConfirmarPedido(IPasarelaPago pasarela)
{
    public Task Ejecutar(int pedidoId) => pasarela.Cobrar(pedidoId);
}
```

Para un `class` o `struct` el parámetro es una variable capturada, no una propiedad ni un campo público (en un `record` sí se convierte en propiedad). Los parámetros capturados no son `readonly`: pueden reasignarse dentro de la clase.

### Expresiones de colección (C# 12)

```csharp
int[] nums = [1, 2, 3];
List<int> lst = [..nums, 4];     // spread: copia los elementos de nums
Console.WriteLine(string.Join(",", lst));
```

```text
1,2,3,4
```

Antes: `new List<int>(nums) { 4 }` o `nums.Append(4).ToList()`. El tipo de destino decide qué colección se crea.

### *Pattern matching*

`switch` como expresión con patrones de propiedades y relacionales:

```csharp
static string Describir(Pedido? p) => p switch
{
    null => "sin pedido",
    { Estado: "Pagado", Total: > 100m } => $"pedido #{p.Id} pagado, importe alto",
    { Estado: "Pagado" } => $"pedido #{p.Id} pagado",
    _ => "otro"
};
```

```text
pedido #4711 pagado, importe alto
pedido #1 pagado
sin pedido
```

Los casos se evalúan en orden, de modo que el más específico va primero. El compilador avisa si un caso queda oculto por uno anterior y de que el `switch` no cubre todos los casos posibles. Para comprobaciones sueltas, `is not null` (`if (pedido is not null)`) reemplaza a `pedido != null` y no se ve afectado por un operador `!=` sobrecargado.

### `init` y `required`

`init` permite asignar una propiedad solo al crear el objeto; `required` obliga a hacerlo.

```csharp
class Cliente { public required string Nombre { get; init; } }

var c = new Cliente();                  // CS9035
var d = new Cliente { Nombre = "a" };
d.Nombre = "b";                         // CS8852
```

```text
error CS9035: Required member 'Cliente.Nombre' must be set in the object initializer or attribute constructor.
error CS8852: Init-only property or indexer 'Cliente.Nombre' can only be assigned in an object initializer, or on 'this' or 'base' in an instance constructor or an 'init' accessor.
```

Es la combinación para clases de configuración o de entrada sin constructor largo y sin el aviso CS8618.

### `using` declaraciones

```csharp
// ❌ Forma antigua: un bloque con llaves
using (var f = new Recurso("fichero"))
{
    // ...
}

// ✅ Declaración: se libera al terminar el ámbito que la contiene
using var f = new Recurso("fichero");
Console.WriteLine("fin de Main");
```

```text
fin de Main
liberado fichero
```

### *Top-level statements*, `var`, tipo de destino y *namespaces* de fichero

```csharp
// Program.cs: sin class Program ni Main
Dictionary<string, int> stock = new() { ["teclado"] = 12 };   // new() de destino
var pedido = new Pedido { Id = 4711, Estado = "Nuevo" };       // var: el tipo se infiere

// En otros ficheros: un namespace para todo el fichero, sin llaves ni nivel extra de sangría
namespace Tienda.Dominio;
public record Producto(int Id, string Nombre);
```

`var` no es tipado dinámico: el tipo se fija en compilación a partir de la expresión de la derecha. Se usa cuando el tipo es evidente (`var pedido = new Pedido()`) y se evita cuando no lo es (`var x = Calcular();`).

### Novedades de C# 13 y C# 14

La documentación de «What's new» de C# 14 lista, entre otras, *extension members*, asignación condicional nula y propiedades con `field`. Las dos que siguen se compilaron con el SDK 10 (C# 14); la lista completa de C# 13 y 14 está en las páginas de novedades.

La palabra clave `field` es el campo de respaldo que genera el compilador para una propiedad con lógica en el `set`:

```csharp
class Perfil { public string Nombre { get; set => field = value.Trim(); } = ""; }
// new Perfil { Nombre = "  Ana " }.Nombre  →  "Ana"
```

Antes obligaba a declarar un campo privado aparte. La asignación condicional nula permite `p?.Nombre = "x";`, que asigna solo si `p` no es nulo. Ambas fallan en un proyecto con `net9.0` o inferior: son C# 14.

## `async` y `await`

Un método `async` devuelve `Task` o `Task<T>` (la promesa de un resultado futuro). `await` cede el hilo mientras la operación espera y continúa al terminar. En un servidor, eso permite atender otras peticiones con el mismo hilo durante una llamada a la base de datos o a `IPasarelaPago`.

```csharp
static async Task<int> Falla() { await Task.Delay(10); throw new InvalidOperationException("pasarela caída"); }

try { await Falla(); }
catch (Exception e) { Console.WriteLine($"await: {e.GetType().Name}: {e.Message}"); }

try { var r = Falla().Result; }
catch (Exception e) { Console.WriteLine($".Result: {e.GetType().Name}: {e.Message} | interna: {e.InnerException!.GetType().Name}"); }
```

```text
await: InvalidOperationException: pasarela caída
.Result: AggregateException: One or more errors occurred. (pasarela caída) | interna: InvalidOperationException
```

`.Result` (y `.Wait()`) **bloquea** el hilo hasta que termina la tarea y además envuelve la excepción en una `AggregateException`; `await` no bloquea y relanza la excepción original. Bloquear dentro de código asíncrono puede dejar la aplicación colgada (interbloqueo) cuando existe un contexto de sincronización, como en una interfaz gráfica; ASP.NET Core no lo tiene, pero seguiría ocupando un hilo del servidor. El interbloqueo no se reprodujo en la consola de estas pruebas.

Reglas prácticas: `async` hasta el final de la cadena de llamadas, nombres con sufijo `Async` en métodos que devuelven `Task`, y un `CancellationToken` como último parámetro; su propagación se explica en [CancellationToken](../caracteristicas-del-lenguaje/CancellationToken.md).

## LINQ

LINQ (*Language Integrated Query*) consulta cualquier secuencia (`IEnumerable<T>`) con métodos encadenados (`Where`, `Select`, `Sum`, `OrderBy`...) o con una sintaxis parecida a SQL. En código real domina la sintaxis de métodos:

```csharp
// Sintaxis de métodos
var total = pedidos.Where(p => p.Estado == "Pagado").Sum(p => p.Total);

// Sintaxis de consulta, equivalente
var pagados = from p in pedidos where p.Estado == "Pagado" select p;
```

Las consultas tienen **ejecución diferida**: definir la consulta no la ejecuta; se ejecuta cada vez que se enumera (`foreach`, `Count()`, `ToList()`...).

```csharp
int llamadas = 0;
var q = ped.Where(p => { llamadas++; return p.Total > 60m; });
Console.WriteLine($"definida: llamadas={llamadas}");
Console.WriteLine($"1a vez: {q.Count()} llamadas={llamadas}");
Console.WriteLine($"2a vez: {q.Count()} llamadas={llamadas}");
var lst = q.ToList();
Console.WriteLine($"ToList llamadas={llamadas}; luego Count {lst.Count} llamadas={llamadas}");
```

```text
definida: llamadas=0
1a vez: 1 llamadas=2
2a vez: 1 llamadas=4
ToList llamadas=6; luego Count 1 llamadas=6
```

Con dos pedidos, el filtro se ejecutó 2 veces por cada enumeración. Si la consulta es cara (acceso a base de datos con EF Core, cálculos) y se necesita varias veces, se materializa una vez con `ToList()` o `ToArray()`. El detalle de cómo EF Core traduce LINQ a SQL queda en [Entity Framework Core](../../../bases-de-datos/acceso-a-datos-dotnet/Entity-Framework-Core.md).

## Genéricos, delegados, excepciones y atributos

- **Genéricos**: tipos y métodos con parámetros de tipo (`List<Pedido>`, `Task<int>`, `IRepositorio<T>`). A diferencia del borrado de tipos de otros entornos, en .NET el tipo genérico existe en ejecución. `where T : class, new()` restringe qué tipos se aceptan.
- **Delegados**: tipos que representan un método. `Func<T, TResult>` (devuelve valor), `Action<T>` (no devuelve) y las lambdas (`p => p.Total > 60m`) cubren casi todos los usos; los `event` se construyen sobre delegados.
- **Excepciones frente a resultados**: una excepción sirve para fallos inesperados; un resultado explícito, para los esperados del negocio (por ejemplo, un pedido sin stock). Ver [Result Pattern](../../../arquitectura-de-software/patrones-de-diseno/Result-Pattern.md).
- **Atributos**: metadatos declarativos entre corchetes (`[HttpGet]`) que frameworks y herramientas leen por reflection. Ver [Atributos](../caracteristicas-del-lenguaje/Atributos.md).

## Elegir `class`, `record`, `struct` o `record struct`

| Tipo | Semántica | Igualdad | Cuándo | Ejemplo de la tienda |
|---|---|---|---|---|
| `class` | Referencia, mutable por defecto | Por referencia | Objetos con identidad y ciclo de vida, servicios | `Pedido` (entidad), `ConfirmarPedido` |
| `record` | Referencia, inmutable por defecto | Por valor | DTO, mensajes, comandos, resultados | `ProductoDto`, `ConfirmarPedidoCommand` |
| `struct` | Valor, copia al asignar | Por defecto, por campos (lenta sin sobrescribir) | Valores pequeños (unos 16 bytes) y muy numerosos | Coordenada de un almacén |
| `record struct` | Valor, igualdad por valor generada | Por valor | Objeto de valor pequeño y sin identidad | `Dinero(decimal Importe, string Moneda)` |

Una entidad con identidad (`Pedido #4711`) no debe ser `record`: dos pedidos con los mismos datos siguen siendo pedidos distintos. Una `struct` grande o mutable genera copias costosas y errores sutiles (modificar una copia creyendo que se modifica el original).

## Diferencias que sorprenden al llegar de otros lenguajes

| Tema | Comportamiento en C# |
|---|---|
| `==` en `string` | Compara el contenido, no la referencia: `==` está sobrecargado. Con la variable tipada como `object`, `==` compara referencias: en la prueba, `(string)o1 == (string)o2` dio `True`, `o1 == o2` dio `False` y `o1.Equals(o2)` dio `True` |
| `==` frente a `Equals` | En `class` sin sobrecarga, ambos comparan referencia; en `record`, valores. `Equals` es virtual; `==` se resuelve por el tipo estático |
| Propiedades frente a campos | Una propiedad (`public string Nombre { get; set; }`) tiene acceso controlado y se puede cambiar su implementación sin romper a quien la usa; un campo público no. Los frameworks (serialización, EF Core) trabajan con propiedades |
| `IEnumerable<T>` | Es una secuencia perezosa, no una colección: puede evaluarse varias veces. Para tamaño o acceso por índice, `List<T>`/`IReadOnlyList<T>` |
| `static` | Estado compartido por todo el proceso y por todas las peticiones concurrentes: sin sincronización es una condición de carrera y complica las pruebas. Para estado compartido se usa un servicio registrado como *singleton* |
| `null` | Con nullable activado, un tipo no marcado con `?` nunca debería ser nulo; el aviso es del compilador, no impide pasar un `null` desde código que no lo use |

## Errores frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `NullReferenceException: Object reference not set to an instance of an object` | Se desreferenció un nulo; a menudo tras un `!` o ignorando un CS8602 | Tratar los avisos de nulabilidad como errores y comprobar con `is not null` o `?.` |
| `warning CS8618: Non-nullable property 'Nombre' must contain a non-null value when exiting constructor` | Propiedad no nula sin inicializar | `required`, inicializarla en el constructor, o declararla `string?` |
| `InvalidOperationException: Collection was modified; enumeration operation may not execute.` | Se añadió o quitó un elemento de una colección dentro de un `foreach` sobre ella | Iterar sobre una copia (`.ToList()`) o usar `RemoveAll(predicado)` |
| Las lambdas de un `for` imprimen todas `3 3 3` | Una lambda captura la **variable** del bucle, no su valor, y al ejecutarse ya vale 3 | Copiar a una variable local dentro del bucle o usar `foreach`, que declara una variable nueva por iteración (en la prueba imprimió `0 1 2`) |
| El proceso termina con `Unhandled exception. System.InvalidOperationException: boom async void` | Excepción en un método `async void`: nadie puede esperarla ni capturarla y cae al hilo del pool | Devolver `Task`; `async void` solo en manejadores de eventos |
| Aplicación que se cuelga al usar `.Result` o `.Wait()` | Bloqueo sobre una tarea que necesita el mismo hilo para continuar | `await` en toda la cadena |

## Buenas prácticas avanzadas

- **Tratar los avisos de nulabilidad como errores.** En el `.csproj`, `<WarningsAsErrors>nullable</WarningsAsErrors>`: los CS86xx dejan de pasar desapercibidos y el `!` pierde su atractivo como atajo.
- **Inmutabilidad por defecto.** DTO como `record`, propiedades `init`/`required`, colecciones expuestas como `IReadOnlyList<T>`; la mutación se concentra en las entidades.
- **Devolver tipos `IEnumerable<T>` solo si el llamador puede asumir pereza.** Materializar con `ToList()` antes de salir de un repositorio evita consultas que se ejecutan después de cerrar la conexión o varias veces.
- **No capturar en `catch (Exception)` para seguir como si nada.** Capturar el tipo concreto y relanzar con `throw;` (no `throw e;`, que reinicia la traza de la pila).
- **`var` con criterio y tipos de destino (`new()`, `[]`) cuando el tipo ya aparece en la declaración**, para quitar repetición sin perder legibilidad.
- **Fijar el SDK con `global.json` y dejar `LangVersion` sin tocar**, de modo que el equipo y la integración continua compilen con el mismo C#.

## Documentación oficial

- [Guía de C#](https://learn.microsoft.com/dotnet/csharp/): punto de entrada de Microsoft Learn con fundamentos, tour del lenguaje y referencia; para buscar una característica concreta.
- [Novedades de C#](https://learn.microsoft.com/dotnet/csharp/whats-new/): una página por versión (entre ellas [C# 13](https://learn.microsoft.com/dotnet/csharp/whats-new/csharp-13) y [C# 14](https://learn.microsoft.com/dotnet/csharp/whats-new/csharp-14)); útil al subir de `TargetFramework`.
- [Configurar la versión del lenguaje](https://learn.microsoft.com/dotnet/csharp/language-reference/configure-language-version): qué versión usa cada `TargetFramework` y cómo cambiarla con `LangVersion`.
- [Especificación del lenguaje](https://learn.microsoft.com/dotnet/csharp/language-reference/language-specification/introduction): definición formal; para dudas de semántica que la guía no resuelve.

## Recursos didácticos

- [Tipos de referencia que aceptan valores NULL](https://learn.microsoft.com/dotnet/csharp/nullable-references): la explicación de Microsoft sobre cómo funciona la nulabilidad y cómo migrar un proyecto existente.
- [Programación asíncrona](https://learn.microsoft.com/dotnet/csharp/asynchronous-programming/): modelo `async`/`await` con ejemplos.

---

*En resumen: C# moderno mueve al compilador los errores que antes llegaban en producción, así que conviene dejarle avisar y no silenciarlo con `!`.*
