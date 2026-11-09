# Atributos personalizados

## ¿Qué es?

Un atributo personalizado es una etiqueta de metadatos que define el propio código en lugar de usar una de las que traen el lenguaje o un framework: una clase que hereda de `System.Attribute` y que se coloca sobre tipos, métodos o propiedades con corchetes, igual que `[Obsolete]` o `[Authorize]`. Por sí solo no hace nada; da sentido a la etiqueta el código que la lee.

## ¿Por qué existe?

Los atributos integrados cubren lo habitual, pero a menudo hace falta marcar el código con información propia y que otra parte del programa la use: «este caso de uso hay que auditarlo», «este endpoint exige el rol Administrador». Sin atributos, esa intención acaba en listas de nombres mantenidas a mano o en `if` repetidos. Un atributo propio expresa la intención una vez, junto al código al que se refiere, y un único lector la aplica en todos los sitios.

> Es como una pegatina de «frágil» en un paquete: la pegatina no protege nada, pero quien manipula los paquetes la lee y actúa distinto. Crear el atributo es poner la pegatina; el *procesador* es quien la lee.

Cómo se aplican y leen los atributos que ya existen lo desarrolla [Atributos](Atributos.md); aquí se trata de crear los propios.

## ¿Cuándo y para qué se usa?

Cuando ninguna etiqueta existente expresa lo que se quiere marcar y la información es **fija, conocida al compilar** y se aplica a muchos elementos. En la tienda online (solución `Tienda.sln`):

- `[Auditable(Evento = "PedidoConfirmado")]` sobre los casos de uso cuya ejecución hay que registrar, como `ConfirmarPedido`.
- `[RequiereRol("Administrador")]` sobre las operaciones que solo puede lanzar ese rol.
- Un `[ColumnaCsv("Precio")]` sobre las propiedades de `Producto` que van a una exportación.

Cuando el dato se conoce solo en ejecución, o cuando basta una interfaz o una línea de configuración, un atributo es la herramienta equivocada (ver «Cuándo no crear un atributo»).

## Un atributo mínimo

La clase hereda de `Attribute`, por convención termina en `Attribute`, y al aplicarla se omite ese sufijo:

```csharp
public sealed class AuditableAttribute : Attribute { }

[Auditable]                       // el compilador busca AuditableAttribute
public sealed class ConfirmarPedido : ICasoDeUso { /* ... */ }
```

`[Auditable]` y `[AuditableAttribute]` son equivalentes. Si existieran las dos clases, `Auditable` y `AuditableAttribute`, la forma corta resolvería a la primera; por eso conviene no tener nombres así.

### Argumentos posicionales y con nombre

Los parámetros del **constructor** son posicionales y obligatorios; las **propiedades públicas** con `set` o `init` se asignan por nombre y son opcionales:

```csharp
public sealed class RequiereRolAttribute(string rol) : Attribute
{
    public string Rol { get; } = rol;
}

public sealed class AuditableAttribute : Attribute
{
    public string? Evento { get; init; }
}

[RequiereRol("Administrador")]                    // posicional
[Auditable(Evento = "PedidoConfirmado")]          // con nombre
public sealed class ConfirmarPedido : ICasoDeUso { /* ... */ }
```

Lo imprescindible va en el constructor, de modo que no se pueda usar la etiqueta a medias; los ajustes con valor por defecto razonable van en propiedades. En un mismo uso, los posicionales van primero y los con nombre después, separados por comas: `[RequiereRol("Administrador", Nivel = 3)]`.

## `[AttributeUsage]`: dónde y cuántas veces se aplica

Se coloca sobre la clase del atributo y el compilador hace cumplir sus reglas. Sin él, el atributo es aplicable a cualquier elemento (`AttributeTargets.All`), una sola vez por elemento y heredable. Tiene tres parámetros:

| Parámetro | Qué controla | Por defecto |
|---|---|---|
| `AttributeTargets` (posicional) | Dónde es válido: `Class`, `Method`, `Property`, `Parameter`, `Interface`... combinables con `\|` | `All` |
| `AllowMultiple` | Si se puede repetir sobre el mismo elemento | `false` |
| `Inherited` | Si las clases derivadas (y los métodos que sobrescriben) lo «heredan» al leerlo por reflexión | `true` |

Los ejemplos siguientes se compilaron con .NET SDK 10.0.401. El SDK estaba en español, por lo que los mensajes del compilador se citan en ese idioma.

### Destino no permitido

```csharp
[AttributeUsage(AttributeTargets.Method)]
public sealed class AuditableAttribute : Attribute { }

[Auditable]                         // ❌ está sobre una clase
public class ConfirmarPedido { }
```

```text
error CS0592: El atributo 'Auditable' no es válido en este tipo de declaración. Solo es válido en declaraciones 'método'.
```

Declarar los destinos convierte «lo puse donde nadie lo lee» en un error de compilación.

### Repetición sin `AllowMultiple`

```csharp
public class ConfirmarPedido
{
    [Auditable]
    [Auditable]                     // ❌ repetido
    public void Ejecutar() { }
}
```

```text
error CS0579: Atributo 'Auditable' duplicado
```

Con `AllowMultiple = true` se admite repetir, y el lector debe usar `GetCustomAttributes<T>()` (plural) para obtenerlos todos; `GetCustomAttribute<T>()` lanza `AmbiguousMatchException` si encuentra más de uno.

### `Inherited`: la diferencia con una clase base y una derivada

```csharp
[AttributeUsage(AttributeTargets.Class, Inherited = true)]
public sealed class MarcaAttribute : Attribute { }

[AttributeUsage(AttributeTargets.Class, Inherited = false)]
public sealed class NoHeredaAttribute : Attribute { }

[Marca, NoHereda] public class PedidoBase { }
public class PedidoOnline : PedidoBase { }

// Lectura sobre cada tipo:
//   t.GetCustomAttribute<MarcaAttribute>(inherit: true)  y  (inherit: false)
//   t.GetCustomAttribute<NoHeredaAttribute>(inherit: true)
```

```text
PedidoBase:   Marca(inherit:true)=True, Marca(inherit:false)=True,  NoHereda(inherit:true)=True
PedidoOnline: Marca(inherit:true)=True, Marca(inherit:false)=False, NoHereda(inherit:true)=False
```

El atributo nunca se copia a la clase derivada: sigue grabado solo en `PedidoBase`. Lo que cambia es que la búsqueda con `inherit: true` sube por la cadena de herencia y lo encuentra allí, salvo que el atributo declare `Inherited = false`. Con `inherit: false`, la derivada no lo ve en ningún caso.

Esto cuenta como trampa cuando un atributo con efectos (`[RequiereRol]`, `[Auditable]`) está en una clase base y se hereda sin querer a derivados que no deberían tenerlo (ver «Errores frecuentes»).

### Interfaces: la herencia no aplica

`Inherited` no se propaga de una interfaz a las clases que la implementan. Se ejecutó con `[Marca] public interface IPasarela { }` y `public class PasarelaFalsa : IPasarela { }`:

```text
Interfaz IPasarela tiene Marca: True
PasarelaFalsa (implementa IPasarela) tiene Marca: False
```

Para encontrar atributos puestos en interfaces hay que recorrer `tipo.GetInterfaces()` y consultar cada una.

## Por qué los argumentos son constantes de compilación

Un atributo no se ejecuta al escribirlo: el compilador lo graba en los metadatos del ensamblado. Por eso los argumentos deben poder calcularse y codificarse al compilar.

### Qué se puede pasar

- Literales y constantes `const` de los tipos primitivos: `bool`, `byte`, `char`, `short`, `int`, `long`, `float`, `double`, sus equivalentes sin signo y `string`.
- `typeof(X)` (un `System.Type`).
- Valores de un `enum`.
- Arrays unidimensionales de todo lo anterior (`new[] { "Soporte", "Gerencia" }` o, desde C# 12, `["Soporte", "Gerencia"]`).
- `object` como tipo del parámetro, siempre que el valor pasado sea una de las constantes anteriores.

### Qué da error, con el mensaje real

Un valor que se calcula en ejecución:

```csharp
public sealed class RequiereRolAttribute(string rol) : Attribute { public string Rol { get; } = rol; }

[RequiereRol(Environment.MachineName)]      // ❌ propiedad de ejecución
public class A { }

public class D
{
    static string rol = "Administrador";    // ❌ un campo no const
    [RequiereRol(rol)]
    public void M() { }
}
```

```text
error CS0182: Un argumento de atributo debe ser una expresión constante, una expresión typeof o una expresión de creación de matrices de un tipo de parámetro de atributo
```

Con `const string Rol = "Administrador";` el mismo uso compila.

Un parámetro del constructor de un tipo no admitido, como `DateTime`, `decimal` o `List<string>`, se declara sin queja, pero falla al **usarlo**:

```csharp
public sealed class VigenteDesdeAttribute(DateTime desde) : Attribute { }
public sealed class RolesAttribute(List<string> roles) : Attribute { }

[VigenteDesde(default)] public class A { }
[Roles(null)]           public class B { }
```

```text
error CS0181: El parámetro del constructor de atributo 'desde' tiene el tipo 'DateTime', que no es un tipo de parámetro de atributo válido
error CS0181: El parámetro del constructor de atributo 'roles' tiene el tipo 'List<string>', que no es un tipo de parámetro de atributo válido
```

Si el tipo no válido es el de una **propiedad** con nombre, el error es otro:

```csharp
public sealed class RequiereRolAttribute(string rol) : Attribute
{
    public DateTime Desde { get; init; }
    public List<string>? Extra { get; init; }
}

[RequiereRol("Administrador", Desde = DateTime.Now)]                     // ❌
[RequiereRol("Administrador", Extra = new List<string> { "x" })]         // ❌
```

```text
error CS0655: 'Desde' no es un argumento de atributo con nombre válido porque no es un tipo de parámetro de atributo válido
error CS0655: 'Extra' no es un argumento de atributo con nombre válido porque no es un tipo de parámetro de atributo válido
```

| Código | Causa |
|---|---|
| CS0182 | El valor del argumento no es constante |
| CS0181 | El tipo de un parámetro del **constructor** no es admisible |
| CS0655 | El tipo de una **propiedad** con nombre no es admisible |

### Cómo se graba en los metadatos

El compilador no guarda la instancia del atributo, sino su descripción: la referencia al constructor que se invoca y un blob binario en la tabla `CustomAttribute` de los metadatos del ensamblado con los argumentos serializados. La instancia se construye más tarde, cuando alguien la lee por reflexión: el runtime llama al constructor con esos valores y asigna las propiedades.

Se puede ver el blob real. Con `[RequiereRol("Administrador", Nivel = 3)]` sobre una clase, leyendo el `.dll` con `System.Reflection.Metadata`:

```csharp
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;

using var pe = new PEReader(File.OpenRead(typeof(CancelarPedido).Assembly.Location));
var md = pe.GetMetadataReader();
foreach (var h in md.CustomAttributes)
{
    var ca = md.GetCustomAttribute(h);
    if (ca.Parent.Kind != HandleKind.TypeDefinition) continue;
    var td = md.GetTypeDefinition((TypeDefinitionHandle)ca.Parent);
    if (md.GetString(td.Name) != "CancelarPedido") continue;
    Console.WriteLine(Convert.ToHexString(md.GetBlobBytes(ca.Value)));
}
```

```text
30 bytes: 01000D41646D696E6973747261646F7201005408054E6976656C03000000
```

Se descompone así:

| Bytes | Significado |
|---|---|
| `0100` | Prólogo fijo |
| `0D 41646D696E6973747261646F72` | Argumento posicional: cadena de 13 bytes, «Administrador» en UTF-8 |
| `0100` | Un argumento con nombre |
| `54` | Es una propiedad |
| `08` | De tipo `int` (4 bytes) |
| `05 4E6976656C` | Nombre de 5 bytes: «Nivel» |
| `03000000` | El valor, 3, como entero de 32 bits |

Solo existen codificaciones para los tipos del apartado anterior; un `DateTime` o un `List<string>` no tienen forma de serializarse en ese blob. Es la razón de los tres errores.

Sin ejecutar nada, `GetCustomAttributesData()` expone esa descripción (con `[RequiereRol("Administrador", Roles = ["Soporte", "Gerencia"], Politica = typeof(string), Nivel = 3)]` sobre `CancelarPedido`):

```csharp
foreach (var d in typeof(CancelarPedido).GetCustomAttributesData())
{
    Console.WriteLine(d.Constructor);
    foreach (var a in d.ConstructorArguments) Console.WriteLine($"posicional: {a.ArgumentType.Name} = {a.Value}");
    foreach (var n in d.NamedArguments) Console.WriteLine($"con nombre: {n.MemberName} = {n.TypedValue.Value}");
}
```

```text
Void .ctor(System.String)
posicional: String = Administrador
con nombre: Roles = System.Collections.ObjectModel.ReadOnlyCollection`1[System.Reflection.CustomAttributeTypedArgument]
con nombre: Politica = System.String
con nombre: Nivel = 3
```

Con un contador estático incrementado en el constructor del atributo, enumerar `GetCustomAttributesData()` dejó el contador en 0; `GetCustomAttribute<RequiereRolAttribute>()` lo subió a 1. Los datos se leen sin ejecutar código del atributo.

### Consecuencia: lo dinámico no cabe en el atributo

Si la regla depende de algo que solo se conoce en ejecución (la hora, un valor de base de datos, el importe de un pedido), el atributo no llega. El patrón es repartir el trabajo: el atributo lleva un nombre o clave fija y el procesador resuelve el valor en ejecución. En ASP.NET Core eso son las *policies*: `[Authorize(Policy = "...")]` lleva solo el nombre (ver [`[Authorize]`](../../../desarrollo-web/asp-net-core/Authorize.md) y [RBAC y Claims](../../../seguridad/autenticacion-y-autorizacion/RBAC-y-Claims.md)).

## El patrón marcador + procesador

Un atributo es metadato inerte: sin un lector que lo consulte, no ocurre nada. Todo atributo propio útil son dos piezas: el marcador (el atributo) y el procesador (código que lo descubre y actúa). El procesador puede ser un decorador, un filtro de ASP.NET Core o un escáner que recorre el ensamblado.

Ejemplo de la tienda: dos casos de uso, `ConfirmarPedido` marcado con `[Auditable]` y `ListarProductos` sin marcar, y un decorador que registra una línea solo si el caso de uso lleva la marca:

```csharp
public interface ICasoDeUso { void Ejecutar(int id); }

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Interface)]
public sealed class AuditableAttribute : Attribute
{
    public string? Evento { get; init; }
}

[Auditable(Evento = "PedidoConfirmado")]
public sealed class ConfirmarPedido : ICasoDeUso
{
    public void Ejecutar(int id) => Console.WriteLine($"Pedido #{id} confirmado");
}

public sealed class ListarProductos : ICasoDeUso
{
    public void Ejecutar(int id) => Console.WriteLine("Catálogo listado");
}

public sealed class Auditor { public void Registrar(string linea) => Console.WriteLine($"[AUDITORIA] {linea}"); }

public sealed class DecoradorAuditable<T>(T interior, Auditor auditor) : ICasoDeUso where T : ICasoDeUso
{
    // Se lee una sola vez por cada T cerrado
    private static readonly AuditableAttribute? Marca = typeof(T).GetCustomAttribute<AuditableAttribute>();

    public void Ejecutar(int id)
    {
        interior.Ejecutar(id);
        if (Marca is not null) auditor.Registrar($"{Marca.Evento} caso={typeof(T).Name} id={id}");
    }
}
```

```csharp
var auditor = new Auditor();
new DecoradorAuditable<ConfirmarPedido>(new ConfirmarPedido(), auditor).Ejecutar(4711);
new DecoradorAuditable<ListarProductos>(new ListarProductos(), auditor).Ejecutar(0);
```

```text
Pedido #4711 confirmado
[AUDITORIA] PedidoConfirmado caso=ConfirmarPedido id=4711
Catálogo listado
```

Quitar el atributo de `ConfirmarPedido` no toca el decorador, y añadírselo a un caso de uso nuevo basta para que se audite. Un campo `static readonly` en una clase genérica se inicializa una vez por cada tipo cerrado, lo que da la caché por tipo sin diccionario.

El otro modo de procesar es **descubrir** los marcados recorriendo el ensamblado, útil para registrarlos en el contenedor de dependencias al arrancar:

```csharp
var auditables = typeof(Auditor).Assembly.GetTypes()
    .Where(t => typeof(ICasoDeUso).IsAssignableFrom(t) && !t.IsAbstract)
    .Select(t => (Tipo: t, Marca: t.GetCustomAttribute<AuditableAttribute>()))
    .Where(x => x.Marca is not null);

foreach (var (tipo, marca) in auditables) Console.WriteLine($"{tipo.Name} -> evento {marca!.Evento}");
```

```text
ConfirmarPedido -> evento PedidoConfirmado
```

Los casos de uso como tales los trata [Casos de Uso](../../../arquitectura-de-software/clean-architecture/Casos-de-Uso.md).

## Leer atributos por reflexión

| Método | Devuelve | Ejecuta el constructor | Cuándo usarlo |
|---|---|---|---|
| `IsDefined(typeof(X), inherit)` | `bool` | No | Solo importa si la marca está; no hace falta su contenido |
| `GetCustomAttribute<T>(inherit)` | Una instancia o `null` | Sí | Un atributo `T` con `AllowMultiple = false` |
| `GetCustomAttributes<T>(inherit)` | Todas las instancias | Sí | Atributos con `AllowMultiple = true` |
| `GetCustomAttributesData()` | Descripciones (`CustomAttributeData`) | No | Inspeccionar sin ejecutar código del atributo, o con ensamblados cargados solo para reflexión |

Estos métodos son extensiones de `System.Reflection.CustomAttributeExtensions`, con `using System.Reflection;`. Con `inherit` omitido, la búsqueda es `true` para tipos y métodos.

### Cuánto cuesta leer en cada llamada

Leer un atributo es reflexión: cada `GetCustomAttribute` parsea el blob, localiza el constructor y crea una instancia nueva. Medición con un `Stopwatch` simple: un millón de lecturas del atributo de `ConfirmarPedido` (tras 1000 de calentamiento):

```csharp
for (int i = 0; i < N; i++) suma += tipo.GetCustomAttribute<AuditableAttribute>()?.Evento?.Length ?? 0;
for (int i = 0; i < N; i++) suma += tipo.IsDefined(typeof(AuditableAttribute), false) ? 1 : 0;
for (int i = 0; i < N; i++) suma += cache.GetOrAdd(tipo, t => t.GetCustomAttribute<AuditableAttribute>()?.Evento)?.Length ?? 0;
```

```text
1.000.000 lecturas:
  GetCustomAttribute cada vez :   1335,1 ms (1335 ns/lectura)
  IsDefined cada vez          :    213,8 ms (214 ns/lectura)
  ConcurrentDictionary        :     13,5 ms (13 ns/lectura)
```

Se ejecutó con `dotnet run -c Release` en .NET 10. Los números dependen de la máquina, del modo (Debug da otros) y de la carga; un `Stopwatch` sin BenchmarkDotNet no es un benchmark riguroso. Lo que sí se mantiene es el orden de magnitud: cachear es en torno a cien veces más barato que leer cada vez, y cada lectura además asigna un objeto nuevo.

### Cachear el resultado

El atributo es inmutable en la práctica: no puede cambiar tras compilar. Se lee una vez por tipo y se guarda:

```csharp
public static class CatalogoDeAuditoria
{
    private static readonly ConcurrentDictionary<Type, AuditableAttribute?> Cache = new();

    public static AuditableAttribute? De(Type tipo) =>
        Cache.GetOrAdd(tipo, t => t.GetCustomAttribute<AuditableAttribute>());
}
```

Alternativas sin diccionario: un campo `static readonly` (como en el decorador genérico de arriba) o leerlos todos al arrancar y guardar el resultado en un servicio singleton.

## Atributos en ASP.NET Core

En un endpoint, el enrutado construye una lista de **metadatos** del endpoint: ahí van los atributos que están sobre el controlador, la acción o la lambda, y los añadidos con `.WithMetadata(...)`. Quien se ejecuta después del enrutado los lee con `HttpContext.GetEndpoint()?.Metadata.GetMetadata<T>()`, sin reflexión propia ni caché: ASP.NET Core ya la hizo al construir el endpoint.

Servidor mínimo de la tienda, con un middleware que lee el atributo y un `IEndpointFilter` en un grupo:

```csharp
var app = WebApplication.CreateBuilder(args).Build();

app.Use(async (contexto, siguiente) =>
{
    var auditable = contexto.GetEndpoint()?.Metadata.GetMetadata<AuditableAttribute>();
    await siguiente();
    if (auditable is not null)
        Console.WriteLine($"[AUDITORIA] {auditable.Evento} {contexto.Request.Method} {contexto.Request.Path} -> {contexto.Response.StatusCode}");
});

// Atributo sobre la lambda
app.MapPost("/pedidos/{id:int}/confirmar",
    [Auditable(Evento = "PedidoConfirmado")] (int id) => Results.Ok($"Pedido #{id} confirmado"));

// Sin atributo
app.MapGet("/productos", () => Results.Ok("Catálogo"));

// Metadato con la API fluida, sin atributo en el código del endpoint
app.MapPost("/pedidos/{id:int}/cancelar", (int id) => Results.Ok($"Pedido #{id} cancelado"))
   .WithMetadata(new AuditableAttribute { Evento = "PedidoCancelado" });

// Filtro de endpoint que lee el mismo metadato
var admin = app.MapGroup("/admin").AddEndpointFilter(async (ctx, siguiente) =>
{
    var a = ctx.HttpContext.GetEndpoint()?.Metadata.GetMetadata<AuditableAttribute>();
    Console.WriteLine($"[FILTRO] metadato Auditable = {a?.Evento ?? "(ninguno)"}");
    return await siguiente(ctx);
});
admin.MapPost("/reembolsos/{id:int}", (int id) => $"Reembolso del pedido #{id}")
     .WithMetadata(new AuditableAttribute { Evento = "ReembolsoEmitido" });
admin.MapGet("/informe", () => "Informe");

app.Run("http://localhost:7431");

[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class)]
public sealed class AuditableAttribute : Attribute { public string? Evento { get; init; } }
```

```bash
curl -X POST http://localhost:7431/pedidos/4711/confirmar
curl http://localhost:7431/productos
curl -X POST http://localhost:7431/pedidos/4711/cancelar
curl -X POST http://localhost:7431/admin/reembolsos/4711
curl http://localhost:7431/admin/informe
```

Respuestas (200 en todas) y salida del servidor:

```text
"Pedido #4711 confirmado"
"Catálogo"
"Pedido #4711 cancelado"
Reembolso del pedido #4711
Informe

[AUDITORIA] PedidoConfirmado POST /pedidos/4711/confirmar -> 200
[AUDITORIA] PedidoCancelado POST /pedidos/4711/cancelar -> 200
[FILTRO] metadato Auditable = ReembolsoEmitido
[AUDITORIA] ReembolsoEmitido POST /admin/reembolsos/4711 -> 200
[FILTRO] metadato Auditable = (ninguno)
```

`/productos` no dejó línea porque no lleva marca. Un atributo propio funciona como metadato de endpoint tanto puesto sobre la lambda como pasado a `WithMetadata`; en controladores se pone sobre la acción o el controlador y se lee desde un `IActionFilter` con `context.ActionDescriptor.EndpointMetadata`. El detalle del enrutado y el pipeline está en [Routing y Middleware](../../../desarrollo-web/de-wpf-a-web/Routing-y-Middleware.md) y en la [colección de ASP.NET Core](../../../desarrollo-web/asp-net-core/README.md). La forma con `GetEndpoint()` y `Metadata.GetMetadata<T>()` se ejecutó en .NET 10; la variante de controladores con `EndpointMetadata` no se ejecutó.

## Atributos genéricos

Desde C# 11 un atributo puede ser genérico, lo que evita pasar `typeof(X)` como argumento y comprueba el tipo en compilación:

```csharp
[AttributeUsage(AttributeTargets.Class)]
public sealed class ValidadorAttribute<T> : Attribute where T : class { }

public class PedidoValidador { }

[Validador<PedidoValidador>]
public class PedidoConValidador { }

var a = typeof(PedidoConValidador).GetCustomAttribute(typeof(ValidadorAttribute<PedidoValidador>));
Console.WriteLine($"{a!.GetType().Name} -> {a.GetType().GetGenericArguments()[0].Name}");
```

```text
ValidadorAttribute`1 -> PedidoValidador
```

El argumento de tipo debe ser un tipo concreto: no puede ser un parámetro de tipo del método o clase donde se aplica (regla del lenguaje, no probada aquí). Se lee con la sobrecarga no genérica `GetCustomAttribute(Type)`, porque no se puede escribir el tipo abierto como argumento de `GetCustomAttribute<T>`.

## Cuándo no crear un atributo

| Necesidad | Atributo | Interfaz de marcado | Configuración en el registro de servicios | *Fluent API* |
|---|---|---|---|---|
| Etiqueta fija, declarada junto al código | Encaja | Encaja | Desplaza la información lejos del código | Desplaza la información lejos del código |
| Valor conocido solo en ejecución | No vale (constantes) | No lleva datos | Encaja | Encaja |
| Comprobación en compilación de la marca | Con `AttributeUsage` | Con restricciones genéricas | No | No |
| Marcar miembros o parámetros | Encaja | No (solo tipos) | No | Depende |
| Dato que no debe grabarse en el binario | No: queda en los metadatos | Queda el tipo | Encaja | Encaja |
| Ya hay un mecanismo del framework (`[Authorize]`, *policies*) | Usar el existente | | | |

Ejemplo del límite. Se quiere que `ConfirmarPedido` solo se ejecute fuera del cierre contable, y el cierre se lee de base de datos:

```csharp
[SoloFueraDeCierre(Hasta = DateTime.Now)]      // ❌ CS0655: no es una constante
```

La solución no es forzar un atributo: o el atributo lleva un nombre (`[Politica("CierreContable")]`) y un procesador resuelve la fecha real, o la regla se configura en el registro de servicios o en el propio caso de uso. Si la información es de **comportamiento**, una interfaz o un servicio inyectado la expresan mejor que una etiqueta.

## Errores frecuentes

| Síntoma | Causa | Arreglo |
|---|---|---|
| `CS0182` al aplicar el atributo | El argumento no es constante (variable, `static readonly`, llamada) | Usar `const`, un literal o `enum`; si el valor es dinámico, el atributo lleva una clave y el procesador lo resuelve |
| `CS0181` o `CS0655` | Tipo de parámetro o de propiedad no admisible (`DateTime`, `decimal`, `List<T>`) | Usar `string`, `long`, un `enum` o un array de esos; convertir en el procesador |
| El atributo se aplica donde no tiene efecto y nadie avisa | Falta `[AttributeUsage]`, o `AttributeTargets.All` por defecto | Declarar `[AttributeUsage]` con los destinos reales; el compilador da `CS0592` en los demás |
| Se añade el atributo y no pasa nada | Ningún procesador lo lee | Escribir y registrar el lector (decorador, filtro, escáner); un atributo solo es metadato |
| La API de la tienda va más lenta tras añadir un filtro de atributos | Se llama a `GetCustomAttribute` en cada petición | Cachear por tipo (`ConcurrentDictionary`, `static readonly`) o leer `Metadata` del endpoint |
| Una clase derivada se audita o exige un rol sin que se pusiera | El atributo está en la base con `Inherited = true` (valor por defecto) y se lee con `inherit: true` | `Inherited = false`, o leer con `inherit: false` |
| `AmbiguousMatchException` | `GetCustomAttribute<T>` sobre un atributo con `AllowMultiple = true` repetido | Usar `GetCustomAttributes<T>()` |
| El atributo de una interfaz no llega a las implementaciones | `Inherited` no cruza las interfaces | Recorrer `tipo.GetInterfaces()` |

## Buenas prácticas avanzadas

- **Sella el atributo y declara siempre `[AttributeUsage]`.** Un `sealed` evita jerarquías de atributos, que casi nunca aportan y complican la lectura; `[AttributeUsage]` con los destinos exactos convierte los usos erróneos en errores de compilación.
- **Constructor para lo obligatorio, propiedades `init` para lo opcional.** Quien lo aplica no puede olvidar el dato imprescindible, y los ajustes con valor por defecto no ensucian el uso.
- **El atributo declara el qué; el procesador implementa el cómo.** Un `[SoloEnHorarioLaboral]` no debería conocer la hora: solo marca. Mantener la lógica fuera es lo que permite reglas dinámicas pese a la restricción de constantes.
- **Lee una vez y cachea.** Un `static readonly` en un decorador genérico, un `ConcurrentDictionary<Type, ...>` o leer los metadatos de endpoint de ASP.NET Core evitan reflexión en la ruta caliente.
- **Decide `Inherited` conscientemente.** Para atributos con efectos (seguridad, auditoría), `Inherited = false` evita que un derivado quede afectado sin que nadie lo haya marcado.
- **Que el compilador avise del mal uso.** `[AttributeUsage]` cubre destino y repetición; reglas más finas (por ejemplo, «solo en clases que implementan `ICasoDeUso`») requieren un analizador de Roslyn, que es lo que permite emitir un aviso propio al compilar. No se desarrolla aquí ni se probó.
- **Los atributos de generadores de código** (por ejemplo `[GeneratedRegex]`) son atributos que lee un generador al compilar en lugar de la reflexión en ejecución; se tratan en [Atributos](Atributos.md).

## Documentación oficial

- [Create custom attributes](https://learn.microsoft.com/dotnet/standard/attributes/writing-custom-attributes): declaración de la clase, constructor y propiedades, y los tres parámetros de `AttributeUsage`; ir aquí al diseñar un atributo propio.
- [AttributeUsageAttribute](https://learn.microsoft.com/dotnet/api/system.attributeusageattribute): referencia de `AttributeTargets`, `AllowMultiple` e `Inherited`; ir aquí para consultar valores y combinaciones.
- [Reflexión y atributos en C#](https://learn.microsoft.com/dotnet/csharp/advanced-topics/reflection-and-attributes/): visión general de los atributos y de su lectura con reflexión.
- [Filtros en Minimal APIs](https://learn.microsoft.com/aspnet/core/fundamentals/minimal-apis/min-api-filters): `IEndpointFilter` y filtros de grupo; ir aquí para procesar metadatos de endpoint.

## Recursos didácticos

[SharpLab](https://sharplab.io): se pega una clase con un atributo y se ve el IL y los metadatos que genera el compilador; es la forma más directa de comprobar que los argumentos quedan grabados en el binario.

---

*En resumen: un atributo propio es una etiqueta inerte, con argumentos constantes grabados en los metadatos al compilar, y solo hace algo cuando un procesador la lee: decláralo con `[AttributeUsage]`, léelo una vez y cachéalo, y déjale a ese procesador lo que se decide en ejecución.*
