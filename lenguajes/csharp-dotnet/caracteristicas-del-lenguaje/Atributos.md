# Atributos

## ¿Qué es?

Un atributo (*attribute*) es una etiqueta declarativa entre corchetes que se coloca sobre un elemento del código —un tipo, un método, una propiedad, un parámetro, un ensamblado— y queda grabada como metadato en el ensamblado compilado: `[Obsolete]`, `[HttpGet]`, `[Required]`. No ejecuta nada por sí mismo: lo lee el compilador, el runtime o un framework (casi siempre por reflexión, la capacidad de .NET de examinar tipos en ejecución) y decide qué hacer con él.

## ¿Por qué existe?

Evita repetir en el código una decisión que es una propiedad del elemento y no de su lógica. Sin atributos, cada componente que necesita saber algo de una clase lo averigua con código imperativo disperso:

```csharp
// ❌ La regla "el total no puede ser negativo" vive lejos del dato y hay que acordarse de llamarla
public class ConfirmarPedido
{
    public void Ejecutar(Pedido pedido)
    {
        if (pedido.Total < 0) throw new ArgumentException("Total negativo");
        if (string.IsNullOrEmpty(pedido.Cliente)) throw new ArgumentException("Falta el cliente");
        // ...y lo mismo en cada caso de uso que reciba un Pedido
    }
}
```

```csharp
// ✅ La regla se declara una vez, junto al dato; un validador genérico la lee
public class NuevaLinea
{
    [Required] public string? Producto { get; set; }
    [Range(1, 100)] public int Cantidad { get; set; }
}
```

Es la misma idea que una restricción `NOT NULL` o `CHECK` de una tabla SQL: se declara en la columna y el motor la aplica en cada `INSERT`, sin un `if` por consulta. El atributo es la declaración; el motor —aquí, el validador de ASP.NET Core— es quien la hace cumplir. En Java se llaman *annotations* (`@Override`); en TypeScript, los *decorators* son un mecanismo parecido.

## ¿Cuándo y para qué se usa?

- Hablar con el compilador: marcar código obsoleto, quitar llamadas en Release, anotar la nulabilidad.
- Configurar un framework: rutas y verbos en ASP.NET Core, validación con DataAnnotations, nombres JSON, mapeo de EF Core, pruebas con xunit.
- Dejar metadatos para herramientas propias (auditoría, documentación) que algún código leerá.

El **uso** de atributos ya existentes se explica a continuación; la creación de los propios está en [Atributos personalizados](Atributos-Personalizados.md).

## Sintaxis y destinos

### Las formas de escribir un atributo

Un atributo es una clase que hereda de `System.Attribute`; los corchetes invocan a su constructor. Hace falta el `using` de su espacio de nombres (`System` para `[Obsolete]`, `Microsoft.AspNetCore.Mvc` para `[HttpGet]`).

```csharp
[Obsolete]                                    // sin argumentos
[Obsolete("Usa CalculadorNuevo.Total")]       // argumento posicional (parámetro del constructor)
[Obsolete("Usa CalculadorNuevo.Total", error: true)]  // posicional con nombre
[Range(1, 100, ErrorMessage = "Entre 1 y 100")]       // propiedad con nombre: Propiedad = valor
[Serializable, Auditable]                     // varios atributos en los mismos corchetes
[Serializable]
[Auditable]                                   // o apilados, equivalente
```

El nombre real de la clase termina en `Attribute` (`ObsoleteAttribute`); C# permite omitir el sufijo. Los argumentos tienen que ser constantes de compilación: literales, `const`, `typeof(...)`, enums y arrays de esos. Por eso no existe `[Authorize(Roles = miVariable)]`.

### El destino: `[assembly: ...]`, `[return: ...]`, `[field: ...]`

Normalmente el compilador deduce a qué elemento se aplica el atributo por su posición. Cuando hay ambigüedad, o se quiere otro destino, se antepone un prefijo:

| Escritura | Destino | Ejemplo |
|---|---|---|
| `[Algo]` sobre un tipo | El tipo | `[Serializable] class Pedido { }` |
| `[Algo]` sobre un método | El método | `[Obsolete("...")] static decimal Total(...)` |
| `[Algo]` sobre una propiedad | La propiedad | `[Auditable("t")] public decimal Total { get; set; }` |
| `[Algo]` sobre un parámetro | El parámetro | `Calcular([Auditable] decimal x)` |
| `[param: Algo]` | El parámetro del constructor de un `record` o clase con constructor primario (sin ejecutar) | `record PedidoDto([param: Auditable] int Id)` |
| `[property: Algo]` | La propiedad generada de un `record` posicional | `[property: JsonPropertyName("pedido_id")] int PedidoId` |
| `[field: Algo]` | El campo de respaldo de una propiedad automática | `[field: NonSerialized] public int Cantidad { get; set; }` |
| `[return: Algo]` | El valor de retorno | `[return: Auditable("devuelve")] decimal Calcular(...)` |
| `[assembly: Algo]` | El ensamblado completo | `[assembly: Auditable("ensamblado")]` |

Se comprobó con reflexión que el atributo cae donde dice el prefijo. `[NonSerialized]` solo admite campos; sobre una propiedad automática hace falta `[field: NonSerialized]` para que llegue al campo de respaldo:

```text
field: CompilerGeneratedAttribute,DebuggerBrowsableAttribute,NonSerializedAttribute
return: AuditableAttribute
assembly: ensamblado
```

Los atributos de ensamblado tienen que ir antes de cualquier declaración del fichero, salvo los `using`; de lo contrario:

```text
error CS1730: Los atributos de módulo y ensamblado deben ir delante de los demás elementos definidos en un archivo, excepto las cláusulas using y las declaraciones de alias externos
```

### Atributos genéricos (C# 11)

Un atributo puede ser genérico: `[Etiqueta<int>(7)]`. Se probó con una clase `EtiquetaAttribute<T>` propia en un proyecto `net10.0` (C# 14) y el lector `GetCustomAttribute<EtiquetaAttribute<int>>()` devolvió `7`. El argumento de tipo debe ser un tipo concreto, no un parámetro de tipo del elemento decorado. Cómo declararlos está en [Atributos personalizados](Atributos-Personalizados.md).

## Los atributos del compilador de uso diario

Salidas obtenidas con `dotnet build` y `dotnet run` en un proyecto `net10.0`; los mensajes del compilador salen en el idioma del sistema (aquí, español).

### `[Obsolete]`: avisar y luego bloquear

```csharp
static class CalculadorAntiguo
{
    [Obsolete("Usa CalculadorNuevo.Total, que incluye IVA.")]
    public static decimal Total(decimal x) => x;
}
```

Llamar a `CalculadorAntiguo.Total(10)` compila, pero avisa:

```text
warning CS0618: 'CalculadorAntiguo.Total(decimal)' está obsoleto: 'Usa CalculadorNuevo.Total, que incluye IVA.'
```

Con `error: true` el aviso se convierte en error y el código deja de compilar, que es el segundo paso de una retirada gradual:

```csharp
[Obsolete("Usa Nuevo.Total", error: true)]
public static int Total(int x) => x;
```

```text
error CS0619: 'Viejo.Total(int)' está obsoleto: 'Usa Nuevo.Total'
```

El texto del atributo es lo único que ve quien llama: debe nombrar la alternativa.

### `[Conditional("DEBUG")]`: una llamada que desaparece

```csharp
static class Trazas
{
    [Conditional("DEBUG")]
    public static void Escribir(string m) => Console.WriteLine("TRAZA: " + m);
}

Trazas.Escribir("llamada que solo existe en Debug");
```

Con `dotnet run` (configuración Debug) se imprime `TRAZA: llamada que solo existe en Debug`; con `dotnet run -c Release` no se imprime nada, porque el compilador elimina la llamada, incluida la evaluación de sus argumentos. El método sigue existiendo; lo que desaparece es la llamada. Solo sirve en métodos `void`.

### `[CallerMemberName]`, `[CallerFilePath]` y `[CallerLineNumber]`

El compilador rellena un parámetro opcional con datos del sitio de la llamada:

```csharp
static class Registro
{
    public static void Log(string msg,
        [CallerMemberName] string miembro = "",
        [CallerFilePath] string fichero = "",
        [CallerLineNumber] int linea = 0)
        => Console.WriteLine($"[{miembro}] {Path.GetFileName(fichero)}:{linea} {msg}");
}

Registro.Log("pedido confirmado");
```

```text
[<Main>$] Program.cs:16 pedido confirmado
```

Se llamó desde instrucciones de nivel superior, de ahí `<Main>$`; dentro de un método sería su nombre. El valor se inserta en compilación, no se consulta con una traza de pila.

### `[Flags]` en un `enum`

```csharp
enum Dias { Lunes = 1, Martes = 2 }
[Flags] enum Dias2 { Lunes = 1, Martes = 2 }

Console.WriteLine(Dias.Lunes | Dias.Martes);    // 3
Console.WriteLine(Dias2.Lunes | Dias2.Martes);  // Lunes, Martes
```

El atributo no cambia las operaciones de bits (funcionan igual); lo lee `Enum.ToString()` para descomponer el valor en nombres. Los valores deben ser potencias de dos para que la descomposición sea inequívoca.

### `[MethodImpl]` y `[Serializable]`

- `[MethodImpl(MethodImplOptions.AggressiveInlining)]` sugiere al compilador JIT que inserte el cuerpo del método en el sitio de la llamada; es una pista, no una orden, y solo merece la pena tras medir.
- `[Serializable]` marca un tipo como serializable para los mecanismos antiguos de serialización binaria de .NET; para JSON no interviene.

### Nulabilidad: `[NotNull]`, `[MaybeNull]`, `[NotNullWhen]`

En el espacio de nombres `System.Diagnostics.CodeAnalysis`, los atributos explican al análisis de nulabilidad lo que la firma no puede expresar. Un método `Try...` devuelve un `bool` y rellena un `out`; el compilador no sabe que, si el `bool` es `true`, el `out` no es nulo:

```csharp
public static bool Buscar(string c, out string? nombre) { /* ... */ }

if (Catalogo.Buscar("A1", out var n))
    Console.WriteLine(n.Length);
```

```text
warning CS8602: Desreferencia de una referencia posiblemente NULL.
```

Con `[NotNullWhen(true)]` en el parámetro, el aviso desaparece dentro del `if`:

```csharp
public static bool Buscar2(string c, [NotNullWhen(true)] out string? nombre) { /* ... */ }
```

`[NotNull]` indica que, al volver el método, el valor nunca es nulo aunque su tipo admita nulos; `[MaybeNull]`, que un valor puede ser nulo aunque su tipo no lo diga (típico en genéricos como `T`). Las dos clases existen en `System.Diagnostics.CodeAnalysis`; solo se ejecutó `[NotNullWhen]`.

### `[SetsRequiredMembers]`

Un constructor marcado con él promete inicializar todos los miembros `required`, de modo que quien lo use no tiene que repetirlos en el inicializador de objeto:

```csharp
class Linea
{
    public required string Codigo { get; init; }
    public Linea() { }
    [SetsRequiredMembers] public Linea(string c) { Codigo = c; }
}
```

El compilador se fía de la promesa: no comprueba que el constructor la cumpla.

## Atributos de frameworks

| Atributo | Lo lee | Para qué |
|---|---|---|
| `[ApiController]`, `[Route]`, `[HttpGet]`, `[FromQuery]` | ASP.NET Core (MVC y enlace de parámetros) | Enrutado, comportamiento de API y origen de cada parámetro |
| `[Authorize]`, `[AllowAnonymous]` | Middleware de autorización de ASP.NET Core | Exigir o eximir de autenticación |
| `[Required]`, `[Range]` | Validación de DataAnnotations (ASP.NET Core al enlazar el modelo) | Reglas de validación de un modelo |
| `[JsonPropertyName]`, `[JsonIgnore]` | `System.Text.Json` | Nombre y presencia de una propiedad en el JSON |
| `[Key]`, `[Column]` | EF Core al construir el modelo | Clave primaria y nombre de columna |
| `[Fact]`, `[Theory]` | El ejecutor de xunit | Descubrir qué métodos son pruebas |

Con un endpoint mínimo y un controlador de ejemplo, ejecutados en `net10.0` y consultados con `curl`:

```csharp
app.MapGet("/pedidos", ([FromQuery] int pagina = 1) => new PedidoDto(4711, 59.90m, pagina));

public record PedidoDto([property: JsonPropertyName("pedido_id")] int PedidoId, decimal Total, int Pagina);
```

```bash
curl "127.0.0.1:7658/pedidos?pagina=2"
```

```json
{"pedido_id":4711,"total":59.90,"pagina":2}
```

`[FromQuery]` ordena leer `pagina` de la cadena de consulta; `[JsonPropertyName]` renombra la propiedad solo en el JSON (el resto usa el nombre por defecto en `camelCase`).

Con un modelo con DataAnnotations y un `[ApiController]`, una petición inválida recibe un `400` sin una línea de código de validación:

```csharp
public class NuevaLinea
{
    [Required] public string? Producto { get; set; }
    [Range(1, 100)] public int Cantidad { get; set; }
}

[ApiController]
[Route("lineas")]
public class LineasController : ControllerBase
{
    [HttpPost]
    public IActionResult Crear(NuevaLinea linea) => Ok(linea);
}
```

```bash
curl -i -X POST 127.0.0.1:7658/lineas -H "Content-Type: application/json" -d '{"cantidad":0}'
```

```text
HTTP/1.1 400 Bad Request
{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"Cantidad":["The field Cantidad must be between 1 and 100."],"Producto":["The Producto field is required."]},"traceId":"..."}
```

Con `{"producto":"Teclado","cantidad":2}` la respuesta es `200` y el mismo JSON. El detalle de estos atributos está en [Validación con DataAnnotations](../../../desarrollo-web/asp-net-core/Validacion-con-DataAnnotations.md), [ApiController](../../../desarrollo-web/asp-net-core/ApiController.md) y [Authorize](../../../desarrollo-web/asp-net-core/Authorize.md); el de `[Key]` y `[Column]`, en [Entity Framework Core](../../../bases-de-datos/acceso-a-datos-dotnet/Entity-Framework-Core.md). No se ejecutaron `[Authorize]`, `[Key]`, `[Column]` ni `[Fact]`.

## Un atributo no hace nada por sí solo

Un atributo es metadato inerte hasta que alguien lo lee. Con un atributo propio mínimo `Auditable` (su creación está en [Atributos personalizados](Atributos-Personalizados.md)), dos clases decoradas de la misma forma:

```csharp
[Auditable("cambia el total")] class PedidoSinLector { }
[Auditable("cambia el total")] class PedidoEtiquetado { }
```

Ejecutar el programa sin ningún código que consulte `PedidoSinLector` no produce ningún efecto: ni error, ni aviso, ni registro. El compilador comprueba que el atributo existe y que sus argumentos son válidos; no comprueba que alguien lo use. Con un lector se obtiene el comportamiento:

```csharp
var t = typeof(PedidoEtiquetado);
Console.WriteLine($"Atributos: {string.Join(", ", t.GetCustomAttributes().Select(a => a.GetType().Name))}");
Console.WriteLine($"Lector: {t.GetCustomAttribute<AuditableAttribute>()?.Motivo}");
```

```text
Atributos: AuditableAttribute
Lector: cambia el total
```

## Leer atributos por reflexión

Dos métodos cubren casi todo:

- `Type.GetCustomAttributes()` (y `GetCustomAttributes(typeof(T), inherit)`) devuelve todos los atributos de un tipo o miembro.
- `GetCustomAttribute<T>()` (extensión de `System.Reflection.CustomAttributeExtensions`, disponible sobre `Type`, `MemberInfo`, `ParameterInfo` y `Assembly`) devuelve uno o `null`.

```csharp
typeof(Pedido2).GetProperty("Total")!.GetCustomAttribute<AuditableAttribute>();
typeof(Pedido2).Assembly.GetCustomAttributes<AuditableAttribute>();
```

Lo que se ve en una consola recorriendo `typeof(Pedido2).GetCustomAttributes()` es la lista de nombres de atributo guardados en los metadatos; para `[Serializable, Auditable]` y `[Etiqueta<int>(7)]`:

```text
SerializableAttribute
AuditableAttribute
EtiquetaAttribute`1
```

El `` `1 `` es la aridad del genérico en los metadatos. `GetCustomAttribute` instancia el atributo llamando a su constructor cada vez; eso y la propia reflexión cuestan, así que un lector que se ejecute en cada petición debe cachear el resultado.

### Herencia

`GetCustomAttribute<T>()` sigue la cadena de herencia solo si el atributo se declaró con `Inherited = true` en su `[AttributeUsage]` (el valor por defecto). En la prueba, `PedidoHijo : PedidoEtiquetado` devolvió el `AuditableAttribute` de su base (`True`). Cómo configurarlo está en [Atributos personalizados](Atributos-Personalizados.md).

## Source generators: leer atributos en compilación

Hay atributos que no se leen en ejecución: los lee un *source generator*, un componente del compilador que genera código C# al compilar. El atributo marca qué generar y el resultado es código normal, sin reflexión en ejecución. Con `[GeneratedRegex]`:

```csharp
static partial class Patrones
{
    [GeneratedRegex(@"^PED-\d+$")] public static partial Regex Referencia();
}

Console.WriteLine(Patrones.Referencia().IsMatch("PED-4711"));   // True
```

Con `<EmitCompilerGeneratedFiles>true</EmitCompilerGeneratedFiles>` en el `.csproj`, el código generado queda visible en `obj/`. En este proyecto apareció en `obj/Debug/net10.0/generated/System.Text.RegularExpressions.Generator/System.Text.RegularExpressions.Generator.RegexGenerator/RegexGenerator.g.cs` (160 líneas), con un método `Referencia()` que devuelve una instancia de una clase `Referencia_0 : Regex` generada. Otros atributos que funcionan así son `[JsonSerializable]` y `[LoggerMessage]`; no se ejecutaron aquí.

## Cuándo usar un atributo y cuándo no

| Necesidad | Atributo | Interfaz | Configuración fluida | Código |
|---|---|---|---|---|
| Etiquetar un elemento para un lector genérico (ruta, validación, nombre JSON) | ✅ Natural | Excesivo | Posible | Disperso |
| Comportamiento que el tipo debe implementar (`IDisposable`, `INotificador`) | ❌ No impone nada | ✅ El compilador exige la implementación | No aplica | Lo mismo que la interfaz |
| Mantener el dominio libre de dependencias de un framework (mapeo a tablas) | ❌ Acopla el dominio al ORM | No aplica | ✅ API fluida de EF Core en la capa de infraestructura | Posible |
| Valor que se conoce solo en ejecución (roles leídos de base de datos) | ❌ Solo constantes | Posible | ✅ Políticas, `Options` | ✅ |
| Lógica con ramas y dependencias | ❌ | ✅ | Posible | ✅ |

Un atributo `[Key]` o `[Column]` sobre `Pedido` obliga a que `Tienda.Dominio` referencie el paquete de EF Core, que pertenece a la infraestructura; la configuración fluida mantiene el mapeo en `Tienda.Infraestructura`. El razonamiento está en [Capa de dominio](../../../arquitectura-de-software/clean-architecture/Capa-de-Dominio.md) y [Capa de infraestructura](../../../arquitectura-de-software/clean-architecture/Capa-de-Infraestructura.md). Un atributo de la librería base (`[Obsolete]`, `[Flags]`) no tiene ese coste.

## Errores frecuentes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| El atributo está puesto y no ocurre nada | Nadie lo lee: ni el framework ni código propio ni un generador | Comprobar quién lo lee y que está registrado (p. ej. `AddControllers()` para los atributos de MVC) |
| `error CS0592: El atributo 'Flags' no es válido en este tipo de declaración. Solo es válido en declaraciones 'enumeración'.` | Destino equivocado (`[Flags]` sobre un método) | Moverlo al destino que admite su `[AttributeUsage]`; el mensaje lo dice |
| `error CS0578: El atributo Conditional no es válido en 'Mal.Devuelve()' porque su tipo de valor devuelto no es void` | `[Conditional]` sobre un método que devuelve valor | Devolver `void`; si hace falta un valor, usar `#if` |
| `error CS0619` en código que antes compilaba | Se subió `[Obsolete]` a `error: true` | Migrar a la alternativa; por eso el mensaje debe nombrarla |
| `[Obsolete]` sin texto: la persona que ve el aviso no sabe qué usar | Atributo sin mensaje de alternativa | `[Obsolete("Usa X")]` |
| `warning CS8602` pese a haber comprobado el `bool` de un `Try...` | El compilador no relaciona el `bool` con el `out` | `[NotNullWhen(true)]` en el parámetro |
| Una regla `[Authorize]` o un filtro se aplica «en otro orden» | Varios atributos del mismo tipo: la reflexión no garantiza el orden de declaración | Fijarlo con la propiedad `Order` del filtro cuando existe (no verificado en ejecución) |

## Buenas prácticas avanzadas

- **Los argumentos son constantes de compilación**: una regla dinámica no cabe en un atributo; resuélvela en ejecución con políticas o filtros.
- **Cachea las lecturas de reflexión que estén en caliente**: `GetCustomAttribute` en cada petición es un coste silencioso; los frameworks leen una vez al arrancar y reutilizan.
- **Prefiere el generador a la reflexión cuando el atributo es estático**: `[GeneratedRegex]` o `[LoggerMessage]` mueven el trabajo a la compilación y dejan código inspeccionable en `obj/`.
- **Escribe siempre el mensaje de `[Obsolete]`** con la alternativa y, cuando la migración termine, pasa a `error: true` antes de borrar.
- **No acoples el dominio con atributos de infraestructura**: el mapeo, la serialización y la validación de transporte van en las capas exteriores.
- **Cada atributo propio, con `[AttributeUsage]`**: restringe dónde puede ir y avisa en compilación del destino equivocado.

## Documentación oficial

- [Atributos y reflexión](https://learn.microsoft.com/dotnet/csharp/advanced-topics/reflection-and-attributes/): visión general de cómo se aplican, de dónde salen y cómo se leen; el punto de partida.
- [Atributos interpretados por el compilador](https://learn.microsoft.com/dotnet/csharp/language-reference/attributes/general): referencia de los atributos que el compilador entiende (`[Obsolete]`, `[Conditional]`, `[Caller...]`); para consultar sus parámetros exactos. Las páginas hermanas `global` y `nullable-analysis` del mismo directorio tratan los atributos de ensamblado y los de nulabilidad.

## Recursos didácticos

- [Catálogo de la clase `System.Attribute`](https://learn.microsoft.com/dotnet/api/system.attribute): enlaza los atributos integrados de .NET, útil para descubrir cuáles existen más allá de los habituales.

---

*En resumen: un atributo es solo metadato declarado una vez sobre el código; el efecto lo pone quien lo lee, así que lo primero que hay que saber de cada uno es quién lo lee.*
