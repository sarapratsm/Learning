# Factory

## ¿Qué es?

Factory (fábrica) es un patrón que **centraliza la creación de objetos** en un método o una clase dedicada, en lugar de repartir `new` por todo el código. Tiene dos usos habituales: crear un objeto que debe nacer válido, y elegir qué implementación concreta de una interfaz entregar según un dato.

## ¿Por qué existe?

Crear un objeto a veces no es un simple `new`: hay que validar datos, fijar un estado inicial, decidir entre varias implementaciones o ensamblar piezas. Si esa lógica se repite en cada sitio donde se necesita el objeto, un cambio en las reglas obliga a tocar muchos puntos, y alguno se queda con la versión antigua. Peor aún: si el constructor es público y sin reglas, cualquiera puede construir un objeto a medias.

La analogía es la de una cocina frente a una mesa. Quien pide un plato no sabe qué ingredientes lleva ni en qué orden se mezclan; pide «el menú del día» y recibe algo completo y comestible. Si cada comensal entrara a cocinar, unos sacarían platos crudos y otros olvidarían la sal. La fábrica es la cocina: un único sitio que sabe cómo se hace y que no entrega nada a medio hacer.

## ¿Cuándo y para qué se usa?

- Crear una entidad u objeto de valor con **invariantes** (reglas que siempre deben cumplirse): el objeto no puede existir en un estado inválido.
- Elegir **una implementación entre varias** según un dato que solo se conoce en ejecución: el país del cliente decide qué `IPasarelaPago` cobra.
- Crear objetos que necesitan **dependencias** (reloj, generador de ids) que el código llamador no debería conocer.
- Distinguir **crear** un objeto nuevo de **reconstruir** uno ya existente que viene de la base de datos.

Los ejemplos usan la tienda online: `Pedido`, `Dinero`, `Email`, `IPasarelaPago`. El modelado completo del `Pedido` está en [Capa de Dominio](../clean-architecture/Capa-de-Dominio.md).

## Crear un objeto válido: la fábrica estática

Un **método de fábrica estático** es un método `static` de la propia clase que construye y devuelve una instancia, mientras el constructor se hace privado. El contraste con un constructor público sin reglas:

```csharp
// ❌ El objeto nace inválido y cada llamador debe acordarse de completarlo
var pedido = new Pedido();            // sin id, sin cliente, sin fecha
pedido.Estado = "Borrador";           // ¿y si alguien escribe "Borradorr"?
pedido.ClienteId = 0;                 // ¿un cliente 0 existe?
```

```csharp
// ✅ La fábrica exige lo imprescindible y devuelve siempre un objeto válido
var pedido = Pedido.Crear(new IdPedido(4711), new IdCliente(1), ahora);
```

La firma es la de la entidad en la capa de dominio:

```csharp
public sealed class Pedido
{
    private Pedido(IdPedido id, IdCliente clienteId, DateTimeOffset creadoEn) { /* ... */ }

    public static Pedido Crear(IdPedido id, IdCliente clienteId, DateTimeOffset ahora) =>
        new(id, clienteId, ahora);
}
```

Con el constructor privado, `new Pedido()` ya no compila fuera de la clase, y no existe forma de obtener un `Pedido` que no haya pasado por `Crear`. Si mañana un pedido exige un dato más, se añade un parámetro a `Crear` y el compilador señala a todos los llamadores. Salida de `Pedido.Crear(new IdPedido(4711), new IdCliente(1), ahora)`:

```text
4711 Borrador líneas=0
```

### Constructores con nombre

Una fábrica estática puede tener un nombre que explique la intención, cosa que un constructor no permite. Sirve sobre todo en objetos de valor:

```csharp
Dinero.Euros(10)               // 10,00 EUR: más legible que new Dinero(10, "EUR")
Email.Crear("ana@tienda.com")  // normaliza y valida; "sin-arroba" lanza ReglaDeDominioException
```

Con la entrada `Email.Crear("sin-arroba")` la salida es `'sin-arroba' no es un email válido.` Varias fábricas con nombres distintos (`Dinero.Euros`, `Dinero.Cero`, `Dinero.De(importe, moneda)`) cubren casos que con constructores obligarían a sobrecargas confusas del mismo nombre.

### Cuando la creación puede fallar de forma esperable

Si crear el objeto puede fallar por razones que forman parte del funcionamiento normal (un cupón ya caducado, un código vacío que viene de un formulario), lanzar una excepción convierte el flujo habitual en `try/catch`. La fábrica devuelve entonces un resultado (patrón desarrollado en [Result Pattern](Result-Pattern.md)); la excepción se reserva para las invariantes que indican un bug:

```csharp
public enum CrearCuponResultado { Creado, CodigoVacio, YaCaducado }

public sealed class Cupon
{
    public string Codigo { get; }
    public DateTimeOffset CaducaEn { get; }
    private Cupon(string codigo, DateTimeOffset caducaEn) { Codigo = codigo; CaducaEn = caducaEn; }

    public static Resultado<Cupon, CrearCuponResultado> Crear(
        string codigo, DateTimeOffset caducaEn, DateTimeOffset ahora)
    {
        if (string.IsNullOrWhiteSpace(codigo))
            return Resultado<Cupon, CrearCuponResultado>.Fallo(CrearCuponResultado.CodigoVacio);
        if (caducaEn <= ahora)
            return Resultado<Cupon, CrearCuponResultado>.Fallo(CrearCuponResultado.YaCaducado);
        return Resultado<Cupon, CrearCuponResultado>.Ok(
            new Cupon(codigo.Trim().ToUpperInvariant(), caducaEn), CrearCuponResultado.Creado);
    }
}
```

`Resultado<TValor, TDesenlace>` es el tipo mínimo de [Códigos de Resultado por Capa](../clean-architecture/Codigos-de-Resultado-por-Capa.md). Con `ahora` = 9/11/2026, salida real:

```text
'' -> CodigoVacio 
'NAVIDAD' -> YaCaducado 
' navidad ' -> Creado NAVIDAD
```

Quien llama decide con el desenlace; nadie recibe un `Cupon` a medias ni un `null`.

## Elegir una implementación según un dato

El segundo uso no crea un objeto con reglas, sino que **decide qué clase concreta entregar** detrás de una interfaz. El código que cobra depende de `IPasarelaPago`; qué pasarela concreta se usa depende del país del pedido.

### Con un `switch` expression

```csharp
public static class FabricaDePasarelas
{
    public static IPasarelaPago Para(string pais) => pais switch
    {
        "ES" or "FR" or "DE" => new PasarelaSepa(),
        "US" or "CA"         => new PasarelaStripe(),
        _ => throw new ArgumentException($"Sin pasarela para el país '{pais}'.", nameof(pais))
    };
}
```

```text
SEPA cobra 45,48 EUR            // FabricaDePasarelas.Para("ES").Cobrar(Dinero.Euros(45.48m))
Tarjeta cobra 45,48 EUR         // Para("US")
Sin pasarela para el país 'JP'. (Parameter 'pais')
```

Es la versión más simple y basta mientras las implementaciones no tengan dependencias propias y sean pocas. El caso no cubierto falla con un mensaje claro en vez de devolver `null`.

### Con el contenedor de DI

Cuando las pasarelas sí tienen dependencias (un `HttpClient`, configuración, logs), crearlas con `new` dentro del `switch` obliga a la fábrica a conocerlas todas. En .NET 8 el contenedor admite **servicios con clave** (*keyed services*): se registran varias implementaciones de la misma interfaz bajo una clave y se resuelven por ella.

```csharp
foreach (var pais in new[] { "ES", "FR", "DE" })
    services.AddKeyedSingleton<IPasarelaPago, PasarelaSepa>(pais);
services.AddKeyedSingleton<IPasarelaPago, PasarelaStripe>("US");

public sealed class FabricaPasarelasDi(IServiceProvider sp)
{
    public IPasarelaPago Para(string pais) => sp.GetRequiredKeyedService<IPasarelaPago>(pais);
}
```

Compilado y ejecutado con `Microsoft.Extensions.DependencyInjection` 8.0.1:

```text
SEPA cobra 10,00 EUR            // Para("FR")
Tarjeta cobra 10,00 EUR         // Para("US")
No service for type 'IPasarelaPago' has been registered.   // Para("JP") con GetRequiredKeyedService
True                            // GetKeyedService("JP") is null: devuelve null en vez de lanzar
```

`GetRequiredKeyedService` lanza si la clave no existe; `GetKeyedService` devuelve `null`. Alternativa sin pasar `IServiceProvider` por todas partes: registrar un delegado y que quien lo necesite pida `Func<string, IPasarelaPago>`:

```csharp
services.AddSingleton<Func<string, IPasarelaPago>>(sp =>
    pais => sp.GetRequiredKeyedService<IPasarelaPago>(pais));
```

También probado: `GetRequiredService<Func<string, IPasarelaPago>>()("US")` devuelve la pasarela de tarjeta. Cómo funciona el contenedor y por qué las dependencias apuntan a interfaces está en [Inversión de Dependencias](../clean-architecture/Inversion-de-Dependencias.md).

### Fábrica frente a Strategy

Se confunden porque ambas hablan de «varias implementaciones de una interfaz»:

| | Fábrica | Strategy |
|---|---|---|
| Responde a | ¿**Cuál** implementación entrego? | ¿**Cómo** se intercambia el comportamiento? |
| Se centra en | La decisión y la construcción | La interfaz común y las variantes del algoritmo |
| En el ejemplo | `Para("ES")` devuelve `PasarelaSepa` | `IPasarelaPago` y sus implementaciones intercambiables |

Suelen aparecer juntas: Strategy define el contrato y las variantes, y la fábrica elige cuál se entrega en cada petición. Strategy se desarrolla en [Strategy](Strategy.md).

## Simple Factory, Factory Method y Abstract Factory

El catálogo clásico del libro *Design Patterns* distingue tres formas, con nombres que se mezclan a menudo:

| Variante | Qué es | Ejemplo en la tienda |
|---|---|---|
| **Simple Factory** (no es un patrón GoF) | Un método o clase con un `switch` que devuelve implementaciones | `FabricaDePasarelas.Para(pais)` |
| **Factory Method** | Un método que crea el objeto; en la versión GoF, las subclases deciden qué crear | `Pedido.Crear(...)`, `Dinero.Euros(...)` |
| **Abstract Factory** | Una interfaz que crea una **familia** de objetos que deben ser coherentes entre sí | `IFamiliaDeEnvio` que entrega a la vez el cálculo de tarifa y la etiqueta del mismo transportista |

En C# moderno, casi siempre basta un **método estático** o una `Func<>`: la herencia que pide el Factory Method de GoF rara vez aporta algo. Abstract Factory aparece cuando hay que garantizar que dos piezas vienen del mismo «proveedor» (que el envío nacional no combine su tarifa con la etiqueta de aduanas del internacional):

```csharp
public interface IFamiliaDeEnvio { string Calculo(); string Etiqueta(); }
public sealed class EnvioNacional : IFamiliaDeEnvio { /* tarifa plana + etiqueta A6 */ }
public sealed class EnvioInternacional : IFamiliaDeEnvio { /* tarifa por peso + etiqueta con aduanas */ }
```

Con la familia nacional, `Calculo()` devuelve `tarifa plana 4,90` y `Etiqueta()` devuelve `etiqueta A6 nacional`. Si el código solo necesita una pieza, una fábrica simple es suficiente.

## Fábrica como servicio inyectable

Una fábrica estática no puede tener dependencias propias. Cuando crear el objeto exige un reloj o un generador de ids, esas dependencias deben llegar desde fuera, y entonces la fábrica pasa a ser una **clase inyectable**, es decir, un servicio:

```csharp
public interface IFabricaDePedidos { Pedido NuevoBorrador(IdCliente cliente); }

public sealed class FabricaDePedidos(TimeProvider reloj, IGeneradorDeIds ids) : IFabricaDePedidos
{
    public Pedido NuevoBorrador(IdCliente cliente) =>
        Pedido.Crear(ids.Siguiente(), cliente, reloj.GetUtcNow());
}
```

El dominio sigue sin leer el reloj: `Pedido.Crear` recibe la fecha por parámetro (ver [Capa de Dominio](../clean-architecture/Capa-de-Dominio.md)) y la fábrica de aplicación es quien la pide a `TimeProvider`. En una prueba, con `FakeTimeProvider` del paquete `Microsoft.Extensions.TimeProvider.Testing`:

```csharp
var reloj = new FakeTimeProvider(ahora);                       // 10:00
var fabrica = new FabricaDePedidos(reloj, new GeneradorSecuencial(4711));
var a = fabrica.NuevoBorrador(new IdCliente(1));
reloj.Advance(TimeSpan.FromMinutes(5));
var b = fabrica.NuevoBorrador(new IdCliente(1));
```

```text
4711 10:00  4712 10:05
```

Ids consecutivos y fechas controladas, sin esperar ni tocar el reloj del sistema. La diferencia con la fábrica estática: aquí la clase se registra en el contenedor, se sustituye en pruebas y puede crecer con más dependencias.

## Crear no es reconstruir

Un `Pedido` guardado hace tres días, ya pagado, se carga de la base de datos. **Reconstituir** es devolver el objeto exactamente como estaba; **crear** es dar de alta uno nuevo, con las reglas de «alta» (nace en `Borrador`, con la fecha de ahora). Mezclarlas rompe el dato:

```csharp
// ❌ Cargar reutilizando el alta: se reejecutan reglas y se pisan fechas
var pedido = Pedido.Crear(id, clienteId, ahora);
foreach (var l in lineasGuardadas) pedido.AñadirLinea(l.ProductoId, l.Cantidad, l.PrecioUnitario);
pedido.Confirmar(ahora);
pedido.MarcarPagado();
```

```csharp
// ✅ Una vía de reconstitución que no ejecuta las reglas de alta
var pedido = Pedido.Reconstituir(id, clienteId, EstadoPedido.Pagado, creadoEn, confirmadoEn, lineas);
```

Salida real con un pedido guardado el 6/11 y cargado el 9/11:

```text
✅ Pagado creado=06/11 confirmado=06/11
❌ Pagado creado=09/11 confirmado=09/11
```

El camino ❌ da el mismo estado, pero ha reescrito las fechas de creación y confirmación con las de la carga. Además, cualquier regla que se endurezca después (por ejemplo, cantidad mínima mayor que cero) haría fallar la carga de datos antiguos válidos en su momento; la reconstitución no valida el pasado. `Reconstituir` es `internal` en el ejemplo, para que solo la infraestructura la use; los ORM como EF Core suelen cargar la entidad por un constructor privado sin lógica y asignar las propiedades, sin pasar por `Crear` (ver [Capa de Infraestructura](../clean-architecture/Capa-de-Infraestructura.md)).

## ¿Constructor, método de fábrica, clase fábrica o DI?

| Situación | Elección |
|---|---|
| Objeto sin reglas de creación (un DTO, una configuración simple) | Constructor público |
| Entidad u objeto de valor con invariantes | Constructor privado + método de fábrica estático |
| La creación puede fallar de forma esperable | Método de fábrica que devuelve un resultado |
| Varias formas de construir lo mismo, con intención distinta | Constructores con nombre (`Dinero.Euros`, `Dinero.Cero`) |
| Elegir implementación por un dato, pocas variantes, sin dependencias | Método estático con `switch` |
| Elegir implementación con dependencias o que crece | Servicios con clave del contenedor de DI, o `Func<string, T>` |
| La creación necesita reloj, ids u otras dependencias | Clase fábrica inyectable (`IFabricaDePedidos`) |
| Cargar desde persistencia | Reconstitución, nunca la fábrica de alta |

## Cuándo NO usar una fábrica

- **Un constructor sin reglas basta.** Un `new Direccion(calle, ciudad)` que solo asigna campos no gana nada con `Direccion.Crear(...)`.
- **Una fábrica por clase por costumbre** (`FabricaDeProductos`, `FabricaDeClientes`) que solo reenvía al constructor añade una clase y un nivel de indirección sin proteger nada.
- **Si el dato que decide la implementación se conoce al arrancar**, la elección es un registro del contenedor de DI, no una fábrica.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| La fábrica tiene `if`s de negocio que se repiten en la entidad, o la entidad queda anémica | La lógica de negocio debía estar en la entidad; la fábrica solo construye y garantiza el estado inicial |
| Una prueba de la fábrica solo funciona a ciertas horas, o los ids cambian en cada ejecución | La fábrica estática usa `DateTime.Now` o `Guid.NewGuid()` dentro; el reloj y el generador deben entrar por parámetro o inyectarse |
| El `switch` de la fábrica gana una rama por cada pasarela nueva y todos los despliegues tocan el mismo fichero | La variación debería ser un registro del contenedor de DI (servicios con clave), no código |
| `NullReferenceException` lejos de la fábrica | La fábrica devuelve `null` para el caso no soportado; debe lanzar con mensaje o devolver un resultado |
| Se pueden crear objetos inválidos aunque exista la fábrica | El constructor sigue siendo público |
| Pedidos cargados con fechas de hoy o error al cargar datos antiguos | La carga desde base de datos pasa por la fábrica de alta en lugar de reconstituir |

## Buenas prácticas avanzadas

- **Haz privado el constructor que la fábrica protege** — con `Crear` y un constructor público, cualquiera se salta las validaciones. Si el ORM necesita un constructor, que sea privado y sin lógica.
- **Usa una fábrica cuando el dato que decide el tipo solo se conoce en ejecución** — si la pasarela es fija al arrancar, la resuelve el contenedor de DI; si depende del país de cada pedido, hace falta una fábrica invocada en ese momento.
- **La fábrica garantiza el estado inicial; la entidad guarda las reglas** — una fábrica que decide si un pedido puede confirmarse está haciendo el trabajo de `Pedido.Confirmar`.
- **Los fallos esperables se devuelven, las invariantes se lanzan** — `Cupon.Crear` devuelve un desenlace; `Dinero.De(-1, "EUR")` lanza porque alguien se equivocó.
- **Falla ruidosamente en el caso no cubierto** — un `switch` con rama `_` que lance o un `GetRequiredKeyedService` es preferible a un `null` que explote más tarde.
- **Mantén la reconstitución fuera del alcance de la capa de aplicación** — `internal` o accesible solo a infraestructura, para que ningún caso de uso «cargue» un pedido saltándose las reglas.

## Documentación oficial

- [Factory Method (Refactoring Guru)](https://refactoring.guru/es/design-patterns/factory-method) — la forma clásica del patrón con diagramas; consultar para ver la relación con Abstract Factory y con la herencia.
- [Inyección de dependencias en .NET](https://learn.microsoft.com/es-es/dotnet/core/extensions/dependency-injection#keyed-services) — la sección de servicios con clave; consultar al elegir una implementación por un dato.
- [`TimeProvider`](https://learn.microsoft.com/es-es/dotnet/api/system.timeprovider) — la abstracción del reloj de .NET 8; consultar para sustituir el tiempo en pruebas.

---

*En resumen: una fábrica es el único camino para obtener un objeto bien formado o la implementación correcta, y deja de ser estática en cuanto necesita dependencias.*
