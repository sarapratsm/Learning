# Value Objects

## ¿Qué es?

Un objeto de valor (*value object*) es un objeto que se define **por sus datos, no por una identidad**: dos objetos de valor con los mismos datos son iguales e intercambiables, y una vez creados no cambian. Una entidad, en cambio, sigue siendo «la misma» aunque cambien sus datos.

## ¿Por qué existe?

Es habitual modelar los conceptos del negocio con tipos primitivos: un importe como `decimal`, una moneda como `string`, un email como `string`. Esa práctica se llama **obsesión por los primitivos** (*primitive obsession*) y tiene un coste: un `decimal` no sabe si son euros o dólares, un `string` acepta cualquier texto, y el compilador permite pasar un descuento donde se esperaba un precio. La validación y el significado del dato se reparten por cada sitio donde se usa, y basta olvidarlos en uno para que el dato inválido entre al sistema.

Un objeto de valor envuelve esos primitivos en un tipo con nombre propio que valida sus reglas al nacer, lleva consigo las operaciones que tienen sentido y no se puede modificar después.

> Piensa en dos billetes de 10 €: da igual cuál de los dos tengas en la mano, valen lo mismo y se pueden cambiar uno por otro. Nadie pregunta «¿cuál es la identidad de este billete?», solo importa su valor. Y un billete no se «edita»: si necesitas 15 €, no escribes encima del billete, entregas otros. Eso es un objeto de valor: igualdad por contenido, intercambiable e inmutable.

## ¿Cuándo y para qué se usa?

En cualquier concepto del dominio que se defina solo por sus datos: un importe con su moneda, un email, una dirección postal, un rango de fechas, unas coordenadas, un identificador. En la tienda online de ejemplo, el total de un pedido, el email de un cliente, la dirección de envío y los identificadores `IdPedido` e `IdCliente` son objetos de valor; el `Pedido` #4711 y el `Cliente` son entidades, porque importa *cuál* es cada uno.

La [Capa de Dominio](../clean-architecture/Capa-de-Dominio.md) muestra dónde encajan estos tipos dentro del `Pedido`; aquí se desarrolla el patrón en sí.

## Del primitivo suelto al tipo con significado

Un total de pedido con `decimal` y `string` sueltos compila con cualquier mezcla:

```csharp
// ❌ Primitivos sueltos: el compilador no ve nada raro
decimal totalA = 10m;  string monedaA = "EUR";
decimal totalB = 20m;  string monedaB = "USD";

decimal suma = totalA + totalB;   // 30: euros más dólares, sin error ni aviso
```

Nada obliga a mirar la moneda antes de sumar, y el resultado `30` ya no dice en qué moneda está. Con un tipo propio, la regla pasa a vivir en un solo sitio:

```csharp
// ✅ Dinero: la mezcla de monedas es una regla del tipo
var a = Dinero.De(10, "EUR");
var b = Dinero.De(20, "USD");

a.Sumar(b);   // ReglaDeDominioException: No se pueden sumar EUR y USD.
```

El `Dinero` completo se desarrolla en la sección siguiente; antes, cómo consigue C# la igualdad por valor.

## Igualdad por valor en C#

C# ofrece tres formas de definir un objeto de valor, y la diferencia está en cómo comparan:

```csharp
public record DineroRecord(decimal Importe, string Moneda);              // igualdad por valor gratis
public class DineroClase(decimal importe, string moneda)                 // igualdad por referencia
{
    public decimal Importe { get; } = importe;
    public string Moneda { get; } = moneda;
}
public readonly record struct DineroStruct(decimal Importe, string Moneda); // por valor, tipo valor
```

```csharp
Console.WriteLine(new DineroRecord(10, "EUR") == new DineroRecord(10, "EUR"));  // True
Console.WriteLine(new DineroClase(10, "EUR") == new DineroClase(10, "EUR"));    // False
Console.WriteLine(new DineroStruct(10, "EUR") == new DineroStruct(10, "EUR"));  // True
```

```text
True
False
True
```

La `class` normal compara **referencias**: son dos objetos distintos en memoria, aunque contengan lo mismo. El `record` genera `Equals`, `GetHashCode`, `==` y `ToString` comparando todas las propiedades. También se nota en las colecciones: un `HashSet<DineroRecord>` que contiene `10 EUR` responde `True` a `Contains(new DineroRecord(10, "EUR"))`, y el equivalente con `DineroClase` responde `False`.

| Forma | Igualdad | Cuándo elegirla |
|---|---|---|
| `record` (clase) | Por valor, generada | Valor por defecto para objetos de valor con varios campos (`Dinero`, `Direccion`). |
| `readonly record struct` | Por valor, generada; vive en la pila o dentro del objeto que lo contiene | Valores pequeños de uno o dos campos que se crean a miles, como los ids tipados. |
| `class` con `Equals`/`GetHashCode` a mano | La que programes | Solo si hace falta una igualdad que el `record` no da (ver la sección de errores, caso de las colecciones). |

Escribir la igualdad a mano obliga a mantener coherentes cuatro piezas (`Equals(T)`, `Equals(object)`, `GetHashCode` y los operadores `==`/`!=`); si dos objetos son iguales y sus `GetHashCode` difieren, los diccionarios y conjuntos fallan sin avisar:

```csharp
public sealed class DineroManual(decimal importe, string moneda) : IEquatable<DineroManual>
{
    public decimal Importe { get; } = importe;
    public string Moneda { get; } = moneda;

    public bool Equals(DineroManual? otro) =>
        otro is not null && Importe == otro.Importe && Moneda == otro.Moneda;
    public override bool Equals(object? obj) => Equals(obj as DineroManual);
    public override int GetHashCode() => HashCode.Combine(Importe, Moneda);
    public static bool operator ==(DineroManual? a, DineroManual? b) => a is null ? b is null : a.Equals(b);
    public static bool operator !=(DineroManual? a, DineroManual? b) => !(a == b);
}
```

Con ese código `new DineroManual(10, "EUR") == new DineroManual(10, "EUR")` devuelve `True`: es lo que el `record` genera en una línea.

Un detalle de `decimal`: `10m` y `10.00m` son iguales para el `record` (`new DineroRecord(10m, "EUR") == new DineroRecord(10.00m, "EUR")` es `True`), aunque se impriman distinto (`10` y `10.00`).

### La limitación honesta del `record`: `with` salta las invariantes

Un `record` permite crear una copia modificada con `with`. Si las propiedades son `init` y la validación solo está en el constructor, `with` la esquiva, porque asigna las propiedades directamente sin pasar por el constructor:

```csharp
public record DineroRecordValida
{
    public decimal Importe { get; init; }
    public string Moneda { get; init; }

    public DineroRecordValida(decimal importe, string moneda)
    {
        if (importe < 0) throw new ArgumentException("negativo");
        Importe = importe;
        Moneda = moneda;
    }
}

new DineroRecordValida(-1, "EUR");                              // ArgumentException: negativo
var roto = new DineroRecordValida(10, "EUR") with { Importe = -5 };
Console.WriteLine(roto);   // DineroRecordValida { Importe = -5, Moneda = EUR }
```

El constructor rechaza `-1`, pero `with { Importe = -5 }` produce un objeto que viola la regla. Lo mismo ocurre con un `record` posicional (`record Dinero(decimal Importe, string Moneda)`): el constructor primario no tiene cuerpo donde validar, y cualquier validación redeclarando la propiedad se salta igual con `with`.

Hay dos salidas. La más sencilla es que **las propiedades no tengan `init`** y solo se pueda construir por un constructor privado y una fábrica: así `with { Importe = … }` ni compila.

```csharp
var d = Dinero.De(1, "EUR");
var x = d with { Importe = -5 };
// error CS0200: No se puede asignar a la propiedad o el indizador 'Dinero.Importe' porque es de solo lectura
```

La otra, válida si se quiere conservar `init`, es validar dentro del propio descriptor de acceso (la palabra clave `field` requiere C# 14, .NET 10):

```csharp
public decimal Importe
{
    get;
    init
    {
        if (value < 0) throw new ArgumentException("negativo");
        field = value;
    }
}
```

Con esa versión, `with { Importe = -5 }` lanza `ArgumentException: negativo`. La primera opción es la que se usa en los ejemplos siguientes.

## Los objetos de valor de la tienda

### `Dinero`: moneda y operaciones

El patrón completo: constructor privado, fábrica que valida y normaliza, y operaciones que devuelven un `Dinero` nuevo. Las firmas (`De`, `Cero`, `Sumar`, `Multiplicar`) son las mismas que usa el `Pedido` de la [Capa de Dominio](../clean-architecture/Capa-de-Dominio.md):

```csharp
namespace Tienda.Dominio;

public sealed record Dinero
{
    public decimal Importe { get; }
    public string Moneda { get; }

    private Dinero(decimal importe, string moneda) => (Importe, Moneda) = (importe, moneda);

    public static Dinero De(decimal importe, string moneda)
    {
        if (importe < 0)
            throw new ReglaDeDominioException("El dinero no puede ser negativo.");
        if (string.IsNullOrWhiteSpace(moneda) || moneda.Length != 3)
            throw new ReglaDeDominioException("La moneda debe ser un código de 3 letras.");
        return new Dinero(Math.Round(importe, 2, MidpointRounding.AwayFromZero), moneda.ToUpperInvariant());
    }

    public static Dinero Cero(string moneda) => De(0, moneda);

    public Dinero Sumar(Dinero otro)
    {
        if (Moneda != otro.Moneda)
            throw new ReglaDeDominioException($"No se pueden sumar {Moneda} y {otro.Moneda}.");
        return new Dinero(Importe + otro.Importe, Moneda);
    }

    public Dinero Multiplicar(decimal factor) => De(Importe * factor, Moneda);

    public override string ToString() => $"{Importe:0.00} {Moneda}";
}
```

```csharp
var precio = Dinero.De(19.99m, "eur");
Console.WriteLine(precio);                                // 19.99 EUR  (moneda normalizada)
Console.WriteLine(precio.Multiplicar(3));                 // 59.97 EUR
Console.WriteLine(precio.Sumar(Dinero.De(5.5m, "EUR")));  // 25.49 EUR
Console.WriteLine(Dinero.De(10, "EUR") == Dinero.De(10.00m, "EUR"));  // True
Dinero.De(-1, "EUR");                                     // ReglaDeDominioException: El dinero no puede ser negativo.
```

Dos decisiones del código: el redondeo se fija al crear (se explica en la sección de aritmética) y la operación con monedas distintas **lanza** en lugar de convertir en silencio. Si convertir divisas es un requisito, es una operación nueva con su tipo de cambio como parámetro, no un comportamiento escondido de `Sumar`. La excepción es de dominio porque sumar monedas distintas es un error de programación; si el desenlace fuese normal (por ejemplo, un carrito con productos de varios vendedores), convendría devolver un resultado, como se explica en [Result Pattern](Result-Pattern.md).

### `Email` y `Direccion`

`Email` normaliza al crearse, de modo que dos escrituras del mismo correo son el mismo valor:

```csharp
public sealed record Email
{
    public string Valor { get; }
    private Email(string valor) => Valor = valor;

    public static Email Crear(string texto)
    {
        var limpio = texto?.Trim().ToLowerInvariant() ?? "";
        if (!limpio.Contains('@') || limpio.StartsWith('@') || limpio.EndsWith('@'))
            throw new ReglaDeDominioException($"'{texto}' no es un email válido.");
        return new Email(limpio);
    }
}

Console.WriteLine(Email.Crear(" Ana@Tienda.com ") == Email.Crear("ana@tienda.com"));  // True
Email.Crear("ana");   // ReglaDeDominioException: 'ana' no es un email válido.
```

`Direccion` es un objeto de valor **compuesto**: agrupa varios campos que solo tienen sentido juntos y valida cada uno. La igualdad compara los tres campos:

```csharp
public sealed record Direccion
{
    public string Calle { get; }
    public string Ciudad { get; }
    public string CodigoPostal { get; }

    private Direccion(string calle, string ciudad, string codigoPostal) =>
        (Calle, Ciudad, CodigoPostal) = (calle, ciudad, codigoPostal);

    public static Direccion Crear(string calle, string ciudad, string codigoPostal)
    {
        if (string.IsNullOrWhiteSpace(calle) || string.IsNullOrWhiteSpace(ciudad))
            throw new ReglaDeDominioException("La dirección necesita calle y ciudad.");
        if (codigoPostal is not { Length: 5 } || !codigoPostal.All(char.IsDigit))
            throw new ReglaDeDominioException("El código postal debe tener 5 dígitos.");
        return new Direccion(calle.Trim(), ciudad.Trim(), codigoPostal);
    }
}
```

La regla del código postal (cinco dígitos) es la española; una tienda que envíe a varios países necesitaría una regla por país, y entonces `Direccion` pasaría a recibir el país.

### Ids tipados

Un id tipado es el objeto de valor mínimo: un solo campo, sin reglas, solo para que el compilador distinga un id de pedido de uno de cliente. Se declaran como `readonly record struct`, igual que en la [Capa de Dominio](../clean-architecture/Capa-de-Dominio.md), que explica el motivo y el error de compilación que evitan:

```csharp
public readonly record struct IdPedido(int Valor);
public readonly record struct IdCliente(int Valor);
```

Un `record struct` es un tipo valor: no reserva un objeto en el montón por cada id y su igualdad compara el campo (`new IdPedido(4711) == new IdPedido(4711)` es `True`).

## Aritmética de dinero: `decimal`, no `double`

`double` representa los números en binario, y fracciones decimales tan corrientes como 0,1 no tienen representación exacta. El error es pequeño y se acumula:

```csharp
Console.WriteLine(0.1 + 0.2);          // 0.30000000000000004
Console.WriteLine(0.1 + 0.2 == 0.3);   // False
Console.WriteLine(0.1m + 0.2m);        // 0.3
Console.WriteLine(0.1m + 0.2m == 0.3m); // True

double suma = 0;  for (int i = 0; i < 10; i++) suma += 0.1;
Console.WriteLine(suma == 1.0);        // False: diez veces 0,1 no son 1

decimal sumaD = 0; for (int i = 0; i < 10; i++) sumaD += 0.1m;
Console.WriteLine(sumaD == 1.0m);      // True
```

`decimal` guarda los dígitos en base 10, así que 0,1 es exactamente 0,1. Por eso `Dinero` usa `decimal` para el importe y los literales llevan el sufijo `m` (`19.99m`); un literal sin sufijo es `double`, y el compilador no deja mezclarlos sin conversión explícita.

### Redondeo

Una operación como `Multiplicar` produce más decimales de los que admite la moneda (el porcentaje de un descuento, un impuesto), y hay que decidir cómo se redondea. `Math.Round` sobre `decimal` usa por defecto `MidpointRounding.ToEven` (redondeo bancario): el valor exactamente intermedio va al par más cercano.

```csharp
Console.WriteLine(Math.Round(2.5m));                                        // 2
Console.WriteLine(Math.Round(2.5m, MidpointRounding.AwayFromZero));         // 3
Console.WriteLine(Math.Round(2.345m, 2));                                   // 2.34
Console.WriteLine(Math.Round(2.345m, 2, MidpointRounding.AwayFromZero));    // 2.35
Console.WriteLine(Math.Round(0.125m, 2));                                   // 0.12
Console.WriteLine(Math.Round(0.125m, 2, MidpointRounding.AwayFromZero));    // 0.13
```

`ToEven` compensa los errores a lo largo de muchas operaciones; `AwayFromZero` es lo que la mayoría de la gente espera de una factura («el medio sube»). Ninguno es el correcto en abstracto: lo importante es **elegirlo explícitamente en un único sitio** (la fábrica `Dinero.De`) para que dos partes del sistema no redondeen distinto y descuadren un céntimo. Si la normativa fiscal aplicable exige una regla concreta, manda ella.

## Persistir objetos de valor con EF Core

Un objeto de valor no tiene tabla propia: se guarda como columnas de la tabla de la entidad que lo contiene. EF Core ofrece dos APIs, `ComplexProperty` (tipos complejos, desde EF Core 8) y `OwnsOne` (tipos poseídos, la API clásica). Con la entidad reducida a lo que importa para la persistencia:

```csharp
public class Pedido
{
    public IdPedido Id { get; private set; }
    public IdCliente ClienteId { get; private set; }
    public Dinero Total { get; private set; } = null!;
    public Direccion Envio { get; private set; } = null!;
    private Pedido() { }
    // ... fábrica Crear y operaciones, ver Capa de Dominio
}

protected override void OnModelCreating(ModelBuilder b) =>
    b.Entity<Pedido>(e =>
    {
        e.ToTable("Pedidos");
        e.Property(x => x.Id).HasConversion(v => v.Valor, v => new IdPedido(v));
        e.HasKey(x => x.Id);
        e.Property(x => x.ClienteId).HasConversion(v => v.Valor, v => new IdCliente(v));
        e.ComplexProperty(x => x.Total, t =>
        {
            t.Property(d => d.Importe).HasPrecision(18, 2);
            t.Property(d => d.Moneda).HasMaxLength(3);
        });
        e.ComplexProperty(x => x.Envio);
    });
```

El esquema que genera con SQLite (`Database.GenerateCreateScript()`, EF Core 10.0.14):

```sql
CREATE TABLE "Pedidos" (
    "Id" INTEGER NOT NULL CONSTRAINT "PK_Pedidos" PRIMARY KEY,
    "ClienteId" INTEGER NOT NULL,
    "Envio_Calle" TEXT NOT NULL,
    "Envio_Ciudad" TEXT NOT NULL,
    "Envio_CodigoPostal" TEXT NOT NULL,
    "Total_Importe" TEXT NOT NULL,
    "Total_Moneda" TEXT NOT NULL
);
```

Cada objeto de valor se aplana en columnas con el prefijo del nombre de la propiedad (`Total_Importe`, `Envio_Ciudad`), y se puede filtrar por ellas: `Where(x => x.Total.Moneda == "EUR" && x.Envio.Ciudad == "Madrid")` se traduce a `WHERE "p"."Total_Moneda" = 'EUR' AND "p"."Envio_Ciudad" = 'Madrid'`. Al leer, el pedido 4711 vuelve con `Total` y `Envio` reconstruidos. Cambiar `ComplexProperty` por `OwnsOne` produce las mismas columnas y los mismos datos (comprobado con el mismo modelo).

Dos tropiezos reales al mapear estos tipos, con propiedades de solo lectura y constructor privado:

- EF Core no mapea por convención las propiedades sin `set`. Sin las líneas `t.Property(d => d.Importe)` y `t.Property(d => d.Moneda)` el arranque falla con `No suitable constructor was found for the type '<Entidad>.Total#Dinero'… Cannot bind 'importe', 'moneda'`. Declararlas explícitamente (como arriba) basta; no hace falta un `set` público.
- Los ids tipados no son tipos complejos: se mapean con `HasConversion` a su primitivo, como se ve en `Id` y `ClienteId`.

Cuándo usar cada API: `ComplexProperty` es el modelo natural para un valor sin identidad (la semántica de objeto de valor es la suya: se compara y se copia por valor); `OwnsOne` es la alternativa cuando el objeto de valor necesita algo que los tipos complejos de la versión en uso no ofrecen (por ejemplo, mapearse a una tabla aparte). Las diferencias finas entre ambas (nulabilidad, colecciones, JSON, versiones) cambian de una versión de EF Core a otra: consultar la documentación de la versión en uso. El mapeo del repositorio y su ciclo de vida se tratan en la [Capa de Infraestructura](../clean-architecture/Capa-de-Infraestructura.md) y en [Entity Framework Core](../../bases-de-datos/acceso-a-datos-dotnet/Entity-Framework-Core.md).

## En la API: un DTO, no el objeto de valor

Un objeto de valor con constructor privado y fábrica no se deserializa de forma natural desde JSON, y exponerlo tal cual ata el contrato público de la API a la forma interna del dominio; la respuesta debe ser un DTO propio (`record PedidoResponse(int Id, decimal Total, string Moneda)`) que la capa de aplicación o la API rellena a partir del objeto de valor.

## ¿Objeto de valor, entidad o primitivo?

Dos preguntas distintas, con una tabla cada una.

**¿Objeto de valor o entidad?**

| Pregunta | Objeto de valor | Entidad |
|---|---|---|
| ¿Importa *cuál* es, o solo *qué* contiene? | Solo qué contiene | Cuál (el pedido #4711) |
| ¿Dos instancias con los mismos datos son lo mismo? | Sí, son intercambiables | No, siguen siendo distintas |
| ¿Se rastrea a lo largo del tiempo (historial, estado)? | No | Sí |
| ¿Cambia «en el sitio»? | No: se sustituye por otro valor | Sí: sigue siendo ella con otros datos |
| Ejemplos | `Dinero`, `Email`, `Direccion`, `IdPedido` | `Pedido`, `Cliente`, `Producto` |

El mismo concepto puede ser una cosa u otra según el negocio: una `Direccion` es un objeto de valor en el envío de un pedido, pero en un sistema de logística que gestiona direcciones como registros con su propio historial sería una entidad.

**¿Objeto de valor o primitivo?**

| Situación | Primitivo basta | Objeto de valor |
|---|---|---|
| Tiene reglas de formato o rango | No | Sí (`Email`, `CodigoPostal`) |
| Sus datos viajan en pareja (importe + moneda) | No | Sí (`Dinero`) |
| Hay operaciones propias (sumar, comparar, normalizar) | No | Sí |
| Se confunde con otro del mismo tipo (dos `int` de ids) | No | Sí (ids tipados) |
| Es un dato opaco que solo se almacena y se muestra | Sí (un comentario libre, un nombre de producto sin reglas) | Sobra |
| Se crea una vez y se pasa a una sola función | Sí | Sobra |

La señal para crearlo es que **el mismo dato se valida o se interpreta en más de un sitio**. Si no hay regla, no hay operación y no hay riesgo de confusión, un `string` basta y envolverlo solo añade ceremonia.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| Un `Dinero` válido pasa a tener importe negativo tras un `with` | Propiedades `init` con la validación solo en el constructor. Constructor privado y propiedades de solo lectura, o validación en el `init` |
| `Dinero.Importe` se modifica desde fuera y se corrompen otros objetos que lo comparten | Setters públicos o `set` en un objeto de valor. Una vez creado, no se muta: se crea otro |
| Dos objetos de valor «iguales» dan `False` con `==` | Es una `class` normal sin `Equals`/`GetHashCode`, o contiene una colección (ver las dos filas siguientes) |
| `new EtiquetasList(["a","b"]) == new EtiquetasList(["a","b"])` da `False` | Un `record` compara los campos con su igualdad por defecto, y `List<T>` compara referencias |
| `ImmutableArray<string>` dentro de un `record` tampoco da `True` | `ImmutableArray<T>` compara la identidad del array interno, no los elementos. Hay que sobrescribir `Equals`/`GetHashCode` comparando con `SequenceEqual` |
| El objeto de valor cambia después de crearlo | Recibe una `List<T>` mutable y guarda la referencia: quien la creó puede seguir modificándola. Copiar a una colección inmutable en el constructor |
| `new PrecioDouble(0.1 + 0.2) == new PrecioDouble(0.3)` da `False` | Importes en `double`: la igualdad exacta falla por la representación binaria. Usar `decimal` |
| Totales que no cuadran por un céntimo entre dos sitios | Se redondea con reglas distintas (`ToEven` en uno, `AwayFromZero` en otro). Redondear en un único punto |
| El arranque de EF Core falla con `Cannot bind` en el objeto de valor | Propiedades de solo lectura sin mapear explícitamente (ver la sección de persistencia) |

Las filas de las colecciones se han comprobado con este código:

```csharp
public record EtiquetasList(List<string> Valores);
public record EtiquetasArr(ImmutableArray<string> Valores);

Console.WriteLine(new EtiquetasList(["a", "b"]) == new EtiquetasList(["a", "b"]));   // False
Console.WriteLine(new EtiquetasArr([.. new[] { "a", "b" }]) == new EtiquetasArr([.. new[] { "a", "b" }])); // False

var lista = new List<string> { "a" };
var etiquetas = new EtiquetasList(lista);
lista.Add("z");
Console.WriteLine(string.Join(",", etiquetas.Valores));   // a,z  (el «inmutable» cambió)
```

La salida es `False`, `False` y `a,z`. La solución es un tipo que copie la colección y compare por secuencia:

```csharp
public record EtiquetasOk
{
    public ImmutableArray<string> Valores { get; }
    public EtiquetasOk(IEnumerable<string> valores) => Valores = [.. valores];

    public virtual bool Equals(EtiquetasOk? otro) =>
        otro is not null && Valores.SequenceEqual(otro.Valores);
    public override int GetHashCode() =>
        Valores.Aggregate(0, (hash, s) => HashCode.Combine(hash, s));
}
// new EtiquetasOk(["a","b"]) == new EtiquetasOk(["a","b"])   → True
```

## Buenas prácticas avanzadas

- **Da comportamiento al tipo, no lo dejes como bolsa de datos con nombre** — un `Dinero` que solo expone `Importe` y `Moneda` desaprovecha el patrón: `Sumar`, `Multiplicar` o `EstaEnRango` dentro del tipo evitan que la lógica vuelva a dispersarse y que cada llamador compruebe la moneda a su manera.
- **Valida y normaliza en un único punto de entrada** — constructor privado y fábrica (`Dinero.De`, `Email.Crear`). Normalizar al crear (minúsculas, recorte de espacios, redondeo) hace que la igualdad por valor funcione: si `Ana@Tienda.com` y `ana@tienda.com` pudieran coexistir, los dos «mismos» emails no serían iguales.
- **Elige explícitamente `MidpointRounding` y hazlo en un solo sitio** — el valor por defecto de `Math.Round` es `ToEven`, que sorprende a quien espera que 2,345 sea 2,35. Dos redondeos distintos en el sistema producen diferencias de céntimo difíciles de rastrear.
- **No confíes en la igualdad automática del `record` cuando hay colecciones** — compara cada campo con su propio `Equals`: `List<T>` y `ImmutableArray<T>` comparan por referencia. Sobrescribe `Equals` y `GetHashCode` con `SequenceEqual`, y copia la colección en el constructor.
- **Un `record struct` no es siempre mejor** — evita reservar memoria para valores de un campo, pero una estructura grande se copia entera en cada paso y su valor por defecto (`default`) existe sin pasar por la validación: `default(IdPedido)` es el id 0 aunque ninguna fábrica lo permita. Para ids tipados compensa; para `Dinero` con validación, una `class` sellada garantiza que no existe un valor sin validar.
- **Si necesita historial o ciclo de vida, ya no es un objeto de valor** — un `Dinero` al que empiezas a añadir «fecha de última modificación» o «quién lo cambió» está pidiendo ser una entidad (ver [Entidades y Agregados](Entidades-y-Agregados.md)).

## Documentación oficial

- [Tipos `record` en C#](https://learn.microsoft.com/es-es/dotnet/csharp/language-reference/builtin-types/record) — la igualdad por valor generada, `with` y las diferencias entre `record` y `record struct`; ir aquí para ver exactamente qué genera el compilador.
- [Tipos complejos en EF Core](https://learn.microsoft.com/es-es/ef/core/modeling/complex-types) — el mapeo de objetos de valor como columnas de la tabla dueña, con sus limitaciones por versión; consultar antes de elegir entre `ComplexProperty` y `OwnsOne`.
- [Tipos de entidad propiedad (`OwnsOne`)](https://learn.microsoft.com/es-es/ef/core/modeling/owned-entities) — la API clásica de EF Core; consultarla si el objeto de valor debe guardarse en otra tabla.
- [Martin Fowler: *Value Object*](https://martinfowler.com/bliki/ValueObject.html) — la definición canónica del patrón y su contraste con la entidad.

## Recursos didácticos

- [`Math.Round` y `MidpointRounding`](https://learn.microsoft.com/es-es/dotnet/api/system.math.round) — tabla de modos de redondeo con ejemplos; útil para decidir cuál aplicar a los importes.

---

*En resumen: un objeto de valor es un dato inmutable definido por su contenido, no por quién es: valida al nacer, se compara por valor y, si lo necesitas distinto, se sustituye en lugar de modificarse.*
