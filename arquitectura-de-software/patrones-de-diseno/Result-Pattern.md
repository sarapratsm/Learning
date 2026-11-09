# Result Pattern

## ¿Qué es?

El Result Pattern consiste en devolver el éxito o el fallo de una operación como parte del valor de retorno, en lugar de lanzar una excepción para los fallos que la aplicación ya espera. Las librerías lo llaman `Result`; en esta colección el tipo se llama `Resultado`.

## ¿Por qué existe?

Una excepción está pensada para lo **excepcional**: perder la conexión a la base de datos, un bug. Usarla también para fallos de negocio habituales (un pedido sin líneas, sin stock, con el pago rechazado) tiene dos costes: el rendimiento y, sobre todo, un contrato oculto.

```csharp
// ❌ La firma promete un Confirmacion; los fallos esperados viajan por un canal que no se ve
public Confirmacion ConfirmarPedido(Pedido pedido)
{
    if (pedido.Lineas.Count == 0) throw new PedidoVacioException();
    if (!HayStock(pedido))        throw new StockInsuficienteException();
    return Cobrar(pedido);        // puede lanzar PagoRechazadoException
}

// ✅ La firma dice que puede fallar y el compilador obliga a mirar
public Resultado<Confirmacion> ConfirmarPedido(Pedido pedido) { /* ... */ }
```

Con la primera firma, quien llama no tiene forma de saber, sin leer el cuerpo, qué excepciones pueden salir; olvidar un `catch` compila igual. Con la segunda, el valor solo se obtiene pasando por el resultado.

El coste de rendimiento es medible. Mismo fallo (convertir `"x"` en número) 100 000 veces: una versión lanza y captura `FormatException`, la otra devuelve un `Resultado<int>` fallido:

```text
Excepción: 176,7 ms (1,77 µs/fallo); Resultado: 5,1 ms (0,051 µs/fallo); ratio x35
```

Medido con `Stopwatch`, compilación `Release`, .NET 10.0.12, 16 CPU, tras 2000 repeticiones de calentamiento; tres ejecuciones dieron entre x35 y x37. Las cifras dependen de la máquina y del modo (en `Debug` salen distintas), y el lanzamiento es más caro cuanto más profunda es la pila que la excepción atraviesa: la medida usa un solo nivel. Un solo fallo cuesta microsegundos y no importa; importa cuando el fallo esperado es el camino frecuente (validar miles de filas de un fichero importado, buscar por clave que casi nunca existe).

> Si conoces los códigos de estado HTTP: un `404 Not Found` es el Result Pattern aplicado a una API. La petición no lanza una excepción al cliente; le devuelve un valor (el código) que debe mirar antes de interpretar la respuesta.

## ¿Cuándo y para qué se usa?

Cuando un método puede fallar de una forma que **forma parte del flujo normal** y quien lo llama puede reaccionar: una validación que no pasa, una regla de negocio incumplida, un recurso que no existe, un conflicto de estado. Los fallos que nadie puede tratar (un bug, una dependencia caída sin alternativa, una invariante rota) siguen siendo excepciones.

Dónde vive cada tipo de resultado según la capa de Clean Architecture, y cómo se traduce a HTTP, está en [Códigos de Resultado por Capa](../clean-architecture/Codigos-de-Resultado-por-Capa.md). La orquestación de pasos de `ConfirmarPedido` está en [Casos de Uso](../clean-architecture/Casos-de-Uso.md), y el criterio entre invariante y fallo esperable, en [Capa de Dominio](../clean-architecture/Capa-de-Dominio.md).

## El Result mínimo

Un `Resultado` sabe si fue bien, lleva el valor si lo hubo y los errores si no. Constructores privados y fábricas estáticas impiden construir estados incoherentes (éxito con error, fallo sin error):

```csharp
public sealed record Error(string Codigo, string Mensaje);

public class Resultado
{
    public IReadOnlyList<Error> Errores { get; }
    public bool EsExito => Errores.Count == 0;

    protected Resultado(IReadOnlyList<Error> errores) => Errores = errores;

    public static Resultado Ok() => new([]);
    public static Resultado Fallo(Error error) => new([error]);
    public static Resultado Fallo(IEnumerable<Error> errores) => new(AlMenosUno(errores));

    protected static Error[] AlMenosUno(IEnumerable<Error> errores)
    {
        var lista = errores.ToArray();
        if (lista.Length == 0)
            throw new ArgumentException("Un fallo necesita al menos un error.", nameof(errores));
        return lista;
    }
}

public sealed class Resultado<TValor> : Resultado
{
    private readonly TValor? _valor;

    public TValor Valor => EsExito
        ? _valor!
        : throw new InvalidOperationException(
            $"El resultado es un fallo ({Errores[0].Codigo}); no tiene valor.");

    private Resultado(TValor valor) : base([]) => _valor = valor;
    private Resultado(IReadOnlyList<Error> errores) : base(errores) { }

    public static Resultado<TValor> Ok(TValor valor) => new(valor);
    public static new Resultado<TValor> Fallo(Error error) => new([error]);
    public static new Resultado<TValor> Fallo(IEnumerable<Error> errores) => new(AlMenosUno(errores));
}
```

Un fallo se define por tener errores: `EsExito` es `Errores.Count == 0`, y la fábrica rechaza una lista vacía (`ArgumentException: Un fallo necesita al menos un error.`). `Resultado` (sin tipo) es la versión para operaciones sin valor de retorno, como cancelar o guardar; `Resultado<TValor>` añade el valor. Uso:

```csharp
Resultado<Pedido> Validar(Pedido p) => p.Lineas.Count == 0
    ? Resultado<Pedido>.Fallo(new Error("pedido.vacio", "El pedido no tiene líneas."))
    : Resultado<Pedido>.Ok(p);

var r = Validar(pedido);
if (!r.EsExito) return Problema(r.Errores[0]);
Usar(r.Valor);
```

En las llamadas a `Fallo` hay que escribir `new Error(...)` y no `new(...)`: con dos sobrecargas (un error o una lista) el compilador declara la llamada ambigua (CS0121).

Las librerías públicas (ver más abajo) llaman `Result` a este tipo; el nombre en español es el que usan las demás fichas de la colección.

## El error como dato

Tres formas de representar *por qué* falló, de menos a más estructurada:

| Forma | Ejemplo | Sirve para | Límite |
|---|---|---|---|
| Texto | `Fallo("Sin stock")` | Mostrarlo tal cual a una persona | Quien llama no puede decidir sin comparar cadenas; cambiar la redacción rompe a los llamadores |
| Tipo `Error` (código + mensaje) | `new Error("stock.insuficiente", "Sin stock de taza.")` | Decidir por el código y mostrar el mensaje; logs; varios errores | El código es una cadena: un error tipográfico compila y el `switch` no es exhaustivo |
| Enum de desenlace | `ConfirmarPedidoResultado.StockInsuficiente` | Cuando el conjunto de fallos de una operación es cerrado y conocido | Un valor nuevo exige tocar el enum; no lleva datos propios (cuál es el producto sin stock) |

Criterio práctico: si quien llama solo decide *qué hacer* ante cada fallo y los fallos son un conjunto cerrado, un enum, con `Resultado<TValor, TDesenlace>` tal como lo define [Códigos de Resultado por Capa](../clean-architecture/Codigos-de-Resultado-por-Capa.md), y un `switch` que el compilador comprueba. Si hace falta transportar datos (qué campo falló, qué producto) o acumular varios fallos, un tipo `Error`. El texto solo es defendible en un prototipo.

### Varios errores a la vez

Una validación de formulario no debe parar en el primer fallo: devuelve todos los que encuentra. Por eso `Resultado` guarda una lista:

```csharp
var errores = new List<Error>();
if (string.IsNullOrWhiteSpace(nombre)) errores.Add(new Error("nombre.vacio", "El nombre es obligatorio."));
if (!email.Contains('@'))              errores.Add(new Error("email.invalido", "El email no es válido."));

var r = errores.Count == 0 ? Resultado.Ok() : Resultado.Fallo(errores);
// r.Errores → nombre.vacio | email.invalido
```

Con un enum de desenlace los errores múltiples no caben bien: un valor del enum es un único desenlace. Una validación con varios mensajes devuelve un `Resultado` con lista de `Error`; la operación posterior puede seguir usando un enum.

## Encadenar pasos que pueden fallar

`ConfirmarPedido` tiene tres pasos, cada uno puede fallar y cada uno necesita la salida del anterior: validar el pedido, reservar el stock, cobrar. Con comprobaciones manuales sale una pirámide de `if`:

```csharp
// ❌ Cada paso repite la misma comprobación
public static string ConfirmarPiramide(Pedido p)
{
    var v = Validar(p);
    if (!v.EsExito) return $"ERROR {v.Errores[0].Codigo}";
    var r = ReservarStock(v.Valor);
    if (!r.EsExito) return $"ERROR {r.Errores[0].Codigo}";
    var c = Cobrar(r.Valor);
    if (!c.EsExito) return $"ERROR {c.Errores[0].Codigo}";
    return $"OK pedido {c.Valor.PedidoId}, cobrado {c.Valor.Cobrado}";
}
```

Tres operaciones convierten esa repetición en un método del propio tipo. `Bind` encadena un paso que a su vez puede fallar: si el resultado es un fallo lo propaga sin ejecutar el paso; si es éxito, pasa el valor al paso. `Map` transforma el valor de un éxito con una función que no puede fallar. `Match` sale del `Resultado`: recibe qué hacer con el éxito y qué hacer con el fallo, y devuelve un único valor.

```csharp
// dentro de Resultado<TValor>
public Resultado<TSalida> Map<TSalida>(Func<TValor, TSalida> f)
    => EsExito ? Resultado<TSalida>.Ok(f(_valor!)) : Resultado<TSalida>.Fallo(Errores);

public Resultado<TSalida> Bind<TSalida>(Func<TValor, Resultado<TSalida>> f)
    => EsExito ? f(_valor!) : Resultado<TSalida>.Fallo(Errores);

public TSalida Match<TSalida>(Func<TValor, TSalida> ok, Func<IReadOnlyList<Error>, TSalida> fallo)
    => EsExito ? ok(_valor!) : fallo(Errores);
```

```csharp
// ✅ Los tres pasos en línea; el primer fallo corta la cadena
public static string ConfirmarCadena(Pedido p) =>
    Validar(p).Bind(ReservarStock).Bind(Cobrar)
        .Match(c => $"OK pedido {c.PedidoId}, cobrado {c.Cobrado}",
               e => $"ERROR {e[0].Codigo}");
```

Los pasos son `Validar(Pedido) → Resultado<Pedido>`, `ReservarStock(Pedido) → Resultado<Reserva>` y `Cobrar(Reserva) → Resultado<Confirmacion>`. Ejecutada la pirámide y la cadena con cuatro pedidos (salida real):

```text
#4711 piramide: OK pedido 4711, cobrado 40               cadena: OK pedido 4711, cobrado 40
#4712 piramide: ERROR pedido.vacio                       cadena: ERROR pedido.vacio
#4713 piramide: ERROR stock.insuficiente                 cadena: ERROR stock.insuficiente
#4714 piramide: ERROR pago.rechazado                     cadena: ERROR pago.rechazado
```

Las dos formas dan lo mismo. `ReservarStock` no se ejecuta si `Validar` falló, y `Cobrar` no se ejecuta si falló la reserva: es lo que impide cobrar un pedido sin stock.

Cuando los pasos son asíncronos, `Bind` necesita una sobrecarga sobre `Task<Resultado<T>>`; sin ella hay que hacer `await` en cada eslabón:

```csharp
public static class ResultadoAsync
{
    public static async Task<Resultado<TSalida>> Bind<TValor, TSalida>(
        this Task<Resultado<TValor>> tarea, Func<TValor, Task<Resultado<TSalida>>> f)
    {
        var r = await tarea;
        return r.EsExito ? await f(r.Valor) : Resultado<TSalida>.Fallo(r.Errores);
    }
}

// ValidarA(p).Bind(ReservarA).Bind(CobrarA)   → para #4714: EsExito=False, pago.rechazado
```

## Consumir el resultado de forma exhaustiva

`Match` obliga a escribir las dos ramas: no hay forma de usar el valor sin decidir qué pasa si falló. Con un enum de desenlace, el `switch` expression sin rama `_` hace lo mismo para cada fallo, y el compilador avisa de un valor sin tratar (cómo elevar ese aviso a error y el mapeo a estados HTTP están en [Códigos de Resultado por Capa](../clean-architecture/Codigos-de-Resultado-por-Capa.md)):

```csharp
var texto = desenlace switch
{
    ConfirmarPedidoResultado.Confirmado        => "Pedido confirmado",
    ConfirmarPedidoResultado.PedidoVacio       => "El pedido no tiene líneas",
    ConfirmarPedidoResultado.StockInsuficiente => "No hay stock suficiente",
    ConfirmarPedidoResultado.PagoRechazado     => "Pago rechazado",
    // ... un valor sin tratar es un aviso de compilación (CS8509)
};
```

Con `Error` de código-cadena el `switch` no puede ser exhaustivo (las cadenas son infinitas) y siempre necesita un descarte: razón de más para preferir enum cuando el conjunto es cerrado.

## Excepciones y Result sin mezclarse

El patrón no elimina las excepciones; reparte el terreno. El criterio es si quien llama puede y debe reaccionar de forma distinta:

| Situación | Forma | Motivo |
|---|---|---|
| Pedido sin líneas, sin stock, pago rechazado | `Resultado` fallido | Fallo esperado: ocurre cada día con datos legítimos |
| Búsqueda de un pedido que no existe | `Resultado` fallido (`pedido.no-encontrado`) | Ocurre con entrada de usuario; no es un bug |
| `NullReferenceException`, índice fuera de rango | Excepción | Bug: nadie debe tratarlo, debe verse y corregirse |
| Base de datos caída sin alternativa | Excepción | Ningún llamador puede hacer nada distinto; sube al manejador global |
| Invariante del dominio rota (cantidad negativa) | Excepción | Quien llama no debía llegar ahí |
| Argumento inválido de programación (`null` donde no cabe) | Excepción (`ArgumentNullException`) | Error de uso del método, no del negocio |

La regla de convivencia: **un mismo fallo se comunica de una sola forma**. Un método que a veces devuelve `Fallo` y a veces lanza para el mismo problema obliga a protegerse con `try/catch` y con `if` a la vez. Y un método cuya firma devuelve `Resultado` no debe lanzar por fallos esperados: lo que hace es romper la promesa que la firma acaba de hacer.

## La trampa de ignorar el resultado

Un `Resultado` descartado no falla ni avisa:

```csharp
Cancelar(pedido);                            // devuelve Resultado.Fallo("pedido.pagado")
Console.WriteLine("seguimos como si nada");  // salida real: seguimos como si nada
```

El fallo pasa tan en silencio como un `catch` vacío, y es peor que la excepción, que al menos interrumpe. Qué existe para mitigarlo (comprobado con .NET SDK 10):

| Mecanismo | Qué hace | Límite |
|---|---|---|
| Regla IDE0058 (*Remove unnecessary expression value*), activada con `dotnet_diagnostic.IDE0058.severity = warning` en `.editorconfig` y `<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>` en el `.csproj` | Avisa en `dotnet build` de cada llamada cuyo valor de retorno se descarta (verificado: marcó `Cancelar(pedido);`) | Marca **todas** las expresiones descartadas, no solo las de `Resultado`; es ruidosa. Desactivada por defecto |
| `[MustUseReturnValue]` de `JetBrains.Annotations` | Marca un método o tipo para el analizador de Rider/ReSharper | Es un paquete de terceros y lo aplica el IDE de JetBrains, no el compilador. No verificado en esta máquina |
| Descartar a propósito: `_ = Cancelar(pedido);` | Deja constancia de que se ignora conscientemente | No evita el olvido; lo hace visible en la revisión de código |

.NET no incluye un atributo equivalente a `[MustUseReturnValue]` que el compilador haga cumplir para tipos propios. Lo que sí es robusto es el diseño: que el método devuelva `Resultado<TValor>` y no `Resultado` cuando hay un valor que usar (sin el valor no se avanza), y revisar en el code review las llamadas a métodos que devuelven `Resultado` sin variable.

## Valor nulo y `.Valor` en un fallo

`Valor` en un fallo lanza `InvalidOperationException`; no devuelve `default`. Una excepción aquí es correcta: leer el valor sin comprobar es un bug de programación, no un fallo del negocio, y devolver `null` o `0` en silencio reproduciría el problema que el patrón quiere evitar. Salida real:

```text
InvalidOperationException: El resultado es un fallo (numero.invalido); no tiene valor.
```

El mensaje incluye el código del primer error para localizar el origen. Quien no quiera comprobar a mano usa `Match` o `Bind`, que acceden al valor solo en el éxito.

Un éxito puede llevar `null` (`Resultado<string?>.Ok(null)` da `EsExito = True` y `Valor is null`), pero conviene evitarlo: «no encontrado» es un fallo (`pedido.no-encontrado`), no un éxito con valor nulo. Así quien llama no necesita comprobar dos veces, primero `EsExito` y luego `Valor is null`.

## Librerías existentes

Existen paquetes que ya traen `Bind`, `Map`, listas de errores y otras combinaciones. Comprobados en NuGet y GitHub el 2026-11-09:

| Paquete | Autoría | Licencia | Enfoque |
|---|---|---|---|
| `FluentResults` (4.0.0) | Michael Altmann | MIT | `Result` y `Result<T>` con lista de errores y éxitos con metadatos |
| `CSharpFunctionalExtensions` (3.7.0) | Vladimir Khorikov | MIT | `Result`, `Maybe`, combinadores (`Bind`, `Map`, `Ensure`) y variantes asíncronas |
| `ErrorOr` (2.1.1) | Amichai Mantinband | MIT (según el repositorio) | Unión «un valor o una lista de errores» ligera |
| `OneOf` (3.0.271) | Harry McIntyre | MIT (según el repositorio) | Uniones discriminadas genéricas, no solo resultado/error |

Recomendación: empezar con un `Resultado` casero como el de arriba, que son unas 60 líneas y no añade dependencia; pasar a una librería cuando se echen en falta combinadores (`Ensure`, `Combine`, versiones asíncronas completas) y no antes. Las cuatro llaman `Result` (u otro nombre propio) al tipo; migrar es cambiar los nombres, no el diseño.

## Cuándo no usar el patrón

- **Un solo llamador que no puede reaccionar.** Si todos los fallos acaban igual (propagarse hasta un manejador global que responde `500`), la excepción es más corta y el `Resultado` solo añade comprobaciones.
- **Código de infraestructura donde la excepción ya encaja.** Un repositorio que pierde la conexión debe lanzar; envolverlo en un `Resultado` obliga a todas las capas a reenviar un fallo que nadie sabe tratar.
- **Métodos privados internos.** Un método auxiliar privado cuyo único llamador está dos líneas más arriba no necesita contrato explícito; el patrón se justifica en las fronteras (casos de uso, servicios públicos).
- **Fallos de programación.** Un argumento `null` o una invariante rota son bugs; devolverlos como `Resultado` los esconde.

## Errores frecuentes

| Síntoma | Causa | Arreglo |
|---|---|---|
| Un `Resultado.Fallo(ex.Message)` por cada `catch (Exception)` y no se sabe qué falló | Se envuelven todas las excepciones sin distinguir tipo | Capturar solo las que son fallo de negocio (`catch (PagoRechazadoException)`); el resto, que suba |
| `Resultado<bool>` cuyo `true` significa «hecho», «ya estaba hecho» y «no hacía falta» | El valor carga tres significados | Un enum de desenlace o `Resultado` sin valor más un tipo con nombre |
| Un `if (r.Error.Contains("stock"))` o un `switch` sobre el texto del mensaje | El mensaje se usa como contrato | Código estable (`Error.Codigo` o enum); el mensaje es solo para personas |
| `Resultado<Resultado<Pedido>>` | `Map` con una función que ya devuelve `Resultado` | Usar `Bind` en vez de `Map` |
| Un método que devuelve `Resultado` y dentro hace `throw new PedidoVacioException()` | Se mezclan las dos formas para un fallo esperado | Devolver `Fallo`; reservar el `throw` para bugs |
| El fallo desaparece y nadie reacciona | Resultado descartado | Ver «La trampa de ignorar el resultado» |
| `InvalidOperationException` al leer `.Valor` | Se leyó el valor sin comprobar `EsExito` | Usar `Match`/`Bind`, o comprobar antes |

## Buenas prácticas avanzadas

- **El código del error es el contrato; el mensaje, no.** Los llamadores deciden por `Codigo` (o por el enum); el texto puede cambiar de redacción o de idioma sin romper a nadie.
- **Un fallo siempre lleva al menos un error.** Hacer imposible el estado «fallo sin error» en la fábrica evita llamadores que lean `Errores[0]` y revienten con un índice fuera de rango.
- **Traduce excepciones de dependencias en el borde, no en el medio.** El adaptador que habla con la pasarela convierte `HttpRequestException` en el desenlace del puerto; el resto del código ya no ve excepciones de HTTP (patrón completo en [Capa de Infraestructura](../clean-architecture/Capa-de-Infraestructura.md)).
- **`Bind` para pasos que pueden fallar, `Map` para los que no.** Si un `Map` devuelve un `Resultado`, el tipo se anida; el compilador lo muestra como `Resultado<Resultado<T>>` y es la señal de que tocaba `Bind`.
- **Mide antes de justificar por rendimiento.** El x35 medido arriba sale de un micro-benchmark con un nivel de pila; el argumento sólido para el patrón es el contrato visible en la firma. El rendimiento solo decide cuando el fallo es el camino frecuente.

## Documentación oficial

- [Prácticas recomendadas para las excepciones (Microsoft Learn)](https://learn.microsoft.com/es-es/dotnet/standard/exceptions/best-practices-for-exceptions): las secciones «Manejar condiciones comunes para evitar excepciones» y «Diseñar clases para que se puedan evitar excepciones» recomiendan comprobar las condiciones que ocurren de forma rutinaria en lugar de provocar la excepción. Ve a ella para decidir qué sigue siendo excepción.
- [Railway Oriented Programming (Scott Wlaschin)](https://fsharpforfunandprofit.com/rop/): la serie de artículos y charlas que presenta el encadenado de pasos que pueden fallar como dos vías (éxito y fallo), en F#. Ve a ella si quieres entender por qué la cadena propaga el primer fallo.

---

*En resumen: el Result Pattern convierte un fallo esperado en un dato que viaja en el tipo de retorno, para que la firma avise de que puede fallar y el compilador obligue a mirar; las excepciones se quedan para lo que nadie puede tratar.*
