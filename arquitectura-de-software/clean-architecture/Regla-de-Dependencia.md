# Regla de Dependencia

## ¿Qué es?

La regla de dependencia es el principio central de Clean Architecture: **las dependencias del código fuente solo pueden apuntar hacia dentro**, hacia las capas más cercanas a las reglas de negocio. Una capa exterior puede conocer a una interior, nunca al revés.

## ¿Por qué existe?

Sin una dirección fija, las dependencias acaban en espaguetis: la lógica de negocio importa la librería de la base de datos, que llama a un helper de la capa web, que necesita un tipo del negocio. Cambiar de ORM, de proveedor de pagos o de framework web obliga entonces a tocar las reglas de negocio, y probar una regla exige levantar media aplicación.

La regla impone una **única dirección**: lo de fuera conoce a lo de dentro, y lo de dentro no sabe que lo de fuera existe. Piensa en las dependencias como calles de sentido único que van todas hacia el centro: se puede ir de la periferia al núcleo, pero no hay ninguna calle de vuelta. Lo que el núcleo necesita del exterior (guardar un pedido, cobrar, avisar al cliente) lo pide a través de una interfaz que él mismo define; cómo se hace se decide fuera.

> Si conoces el concepto de «capas» en una aplicación, la diferencia es que aquí no basta con que las capas existan: importa en qué sentido se referencian.

## ¿Cuándo y para qué se usa?

Se aplica en cualquier solución que siga Clean Architecture, arquitectura hexagonal u otra organización en capas con un núcleo de negocio. Se decide en cada `using` y en cada `ProjectReference`: antes de que una clase dependa de otra, la pregunta es si esa dependencia apunta hacia dentro.

En una tienda online, el cálculo del total de un pedido (negocio, capa interna) no debe conocer la tabla SQL donde se guarda ni el controlador que lo expone (capas externas). Si lo conoce, cualquier cambio en la base de datos o en la API puede romper una regla de negocio, y la regla ya no se puede probar sin ellas.

## La regla con precisión

Las capas de la solución de ejemplo, de dentro hacia fuera:

```text
Tienda.Dominio  ◄──  Tienda.Aplicacion  ◄──  Tienda.Infraestructura
                              ▲                        ▲
                              └──────  Tienda.Api  ───┘
```

- `Tienda.Dominio`: entidades y reglas de negocio (`Pedido`, `LineaPedido`, `Cliente`, `Producto`). No referencia a ninguna otra capa.
- `Tienda.Aplicacion`: casos de uso (`ConfirmarPedido`, `CancelarPedido`) y las interfaces que necesitan (`IRepositorioPedidos`, `IPasarelaPago`, `INotificador`). Referencia solo al dominio.
- `Tienda.Infraestructura`: implementaciones concretas de esas interfaces (EF Core, cliente HTTP de la pasarela, envío de correo). Referencia a Aplicación y Dominio.
- `Tienda.Api`: el punto de entrada. Referencia a Aplicación y a Infraestructura, porque es donde se enganchan las implementaciones con las interfaces (ver [Inversión de Dependencias](Inversion-de-Dependencias.md)).

La regla habla de **dependencias de código**: qué proyectos y tipos se mencionan entre sí al compilar. No habla de quién ejecuta a quién.

### Compilación frente a ejecución

En ejecución, el flujo de control va hacia fuera y vuelve. Esto es lo que pasa cuando llega la petición de confirmar el pedido #4711:

```text
Ejecución (flujo de control)                      Compilación (quién referencia a quién)

Tienda.Api  POST /pedidos/4711/confirmar          Tienda.Api  ──►  Tienda.Aplicacion
   │                                              Tienda.Api  ──►  Tienda.Infraestructura
   ▼                                              Tienda.Infraestructura ──► Tienda.Aplicacion
ConfirmarPedido (Aplicacion)                      Tienda.Aplicacion ──► Tienda.Dominio
   │  pedido.Confirmar()  → Tienda.Dominio        Tienda.Infraestructura ──► Tienda.Dominio
   │  repositorio.Guardar(pedido)
   ▼                                              (ningún proyecto interno referencia
IRepositorioPedidos  (interfaz en Aplicacion)      a un proyecto externo)
   │
   ▼
RepositorioPedidos   (Infraestructura) → UPDATE pedidos ... en la base de datos
```

`ConfirmarPedido` acaba provocando una escritura en base de datos, es decir, en ejecución el flujo sale hacia la infraestructura. Pero en el código, `Tienda.Aplicacion` solo conoce `IRepositorioPedidos`, una interfaz suya. La clase que escribe en la base de datos referencia a la interfaz, no al revés. La regla no prohíbe llamar a la base de datos: prohíbe que el núcleo la **conozca**.

## Cómo se ve en una solución .NET

La regla se materializa en las referencias entre proyectos. Un `Tienda.Aplicacion.csproj` correcto:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <!-- ✅ Apunta hacia dentro -->
    <ProjectReference Include="..\Tienda.Dominio\Tienda.Dominio.csproj" />

    <!-- ❌ Prohibida: el centro no puede conocer a la periferia
    <ProjectReference Include="..\Tienda.Infraestructura\Tienda.Infraestructura.csproj" />
    -->
  </ItemGroup>
</Project>
```

Con el `ProjectReference` prohibido ausente, el compilador defiende la regla. Si alguien escribe en `Tienda.Dominio` la línea `using Tienda.Infraestructura;`, la compilación falla con este error (salida real de `dotnet build`, con el SDK en español):

```text
Pedido.cs(1,14): error CS0234: El tipo o el nombre del espacio de nombres 'Infraestructura'
no existe en el espacio de nombres 'Tienda' (¿falta alguna referencia de ensamblado?)
```

En inglés es `CS0234: The type or namespace name 'Infraestructura' does not exist in the namespace 'Tienda' (are you missing an assembly reference?)`. Cuando el espacio de nombres raíz tampoco existe, el código es `CS0246`. Quien recibe este error tiene dos salidas: arreglar el diseño o, tentación habitual, añadir la referencia al `.csproj`. La segunda anula la protección, y por eso las referencias entre proyectos conviene revisarlas en las pull requests como si fueran código.

Dos precisiones:

- Si dominio e infraestructura son carpetas de un mismo proyecto, no existe este error: cualquier `using` prohibido compila. Separar en proyectos es la defensa más barata.
- `ProjectReference` es transitiva por defecto. Si `Tienda.Infraestructura` referencia a EF Core, `Tienda.Api` lo ve, pero `Tienda.Dominio` no, porque no referencia a ninguno de los dos. Un `PackageReference` a EF Core dentro de `Tienda.Dominio.csproj` es la misma violación que una `ProjectReference` a infraestructura.

## Cómo se rompe

### La violación obvia

```csharp
using Microsoft.EntityFrameworkCore;   // ❌ el dominio importa el ORM
using System.ComponentModel.DataAnnotations.Schema;

[Table("pedidos")]                     // ❌ y lo configura desde la entidad
public class Pedido
{
    public int Id { get; set; }
    public DbSet<LineaPedido> Lineas { get; set; } = null!;   // ❌
}
```

Se ve en el primer `using`. Con proyectos separados ni siquiera compila.

### Las violaciones sutiles

Las peligrosas no llevan `using` de base de datos, sino **tipos del exterior en las firmas y en los flujos del centro**. Cada una compila si el tipo llega por algún paquete que el proyecto ya referencia:

| Síntoma | Qué se ha filtrado | Arreglo |
|---|---|---|
| `IRepositorioPedidos` devuelve `IQueryable<Pedido>` | El ORM: quien consume la consulta la termina de construir y su traducción a SQL depende de EF Core | Devolver `Pedido?` o `IReadOnlyList<Pedido>`, y un método por consulta que el negocio necesite (`ObtenerPendientesDeCliente(clienteId)`) |
| Un caso de uso hace `catch (SqlException)` o `catch (DbUpdateException)` | El motor de base de datos y su tecnología | La infraestructura traduce la excepción a un error propio de la aplicación (excepción de aplicación o [resultado](../patrones-de-diseno/Result-Pattern.md)); ver [Capa de Infraestructura](Capa-de-Infraestructura.md) |
| Atributos `[Table]`, `[Column]`, `[JsonPropertyName]`, `[JsonIgnore]` sobre `Pedido` | Persistencia y formato de transporte | Mapeo con la configuración fluida del ORM en Infraestructura y DTO de salida en la API con sus atributos |
| `ConfirmarPedido` recibe `TiendaDbContext` por constructor | La infraestructura entera, no solo una interfaz | Inyectar `IRepositorioPedidos`; el `DbContext` se queda dentro de la implementación |
| Un caso de uso recibe `HttpContext`, `IFormFile` o `ClaimsPrincipal` | El protocolo de entrada (HTTP) | La API extrae lo necesario (identificador de usuario, bytes del fichero, `Stream`) y llama al caso de uso con valores simples |
| `Tienda.Dominio` referencia el paquete de EF Core «solo para una anotación» | El ORM, por la puerta de atrás | Quitar el paquete: si el dominio no lo necesita para compilar, nada del ORM debería poder usarse allí |

El ejemplo más tangible es el `IQueryable`. Con este contrato:

```csharp
// ❌ Tienda.Aplicacion
public interface IRepositorioPedidos
{
    IQueryable<Pedido> Pedidos { get; }
}
```

el caso de uso escribe `repositorio.Pedidos.Where(p => p.Lineas.Any()).Include(...)`. El código compila, el dominio sigue limpio, y aun así la capa de aplicación depende del comportamiento de EF Core: qué expresiones se traducen a SQL, cuándo se ejecuta la consulta, qué pasa fuera de una sesión abierta. Un doble de pruebas en memoria acepta consultas que el proveedor real rechaza en ejecución. La regla se ha roto aunque `Tienda.Aplicacion` no tenga ninguna referencia nueva.

## Cómo se hace cumplir

| Mecanismo | Qué detecta | Coste |
|---|---|---|
| Proyectos separados y referencias mínimas | Un `using` hacia una capa a la que no se referencia | Ninguno; es la base |
| Test de arquitectura (NetArchTest) | Dependencias de tipos hacia espacios de nombres concretos, incluidas las que llegan por paquetes | Un test, ejecutado en la integración continua |
| Revisión de firmas y excepciones | Violaciones sutiles que ninguna herramienta distingue de un uso legítimo | Atención en la revisión de código |

### Tests de arquitectura con NetArchTest

[NetArchTest](https://github.com/BenMorris/NetArchTest) (paquete NuGet `NetArchTest.Rules`) inspecciona los ensamblados compilados y permite escribir la regla como un test. Se puede ejecutar con xUnit, NUnit o MSTest. Este proyecto de tests referencia a todos los proyectos de la solución:

```csharp
using System.Reflection;
using NetArchTest.Rules;
using Tienda.Aplicacion;
using Tienda.Dominio;
using Xunit;

public class ReglaDeDependenciaTests
{
    private static readonly Assembly Dominio = typeof(Pedido).Assembly;
    private static readonly Assembly Aplicacion = typeof(ConfirmarPedido).Assembly;

    [Fact]
    public void Dominio_no_depende_de_capas_externas()
    {
        var resultado = Types.InAssembly(Dominio)
            .ShouldNot().HaveDependencyOnAny(
                "Tienda.Aplicacion", "Tienda.Infraestructura", "Tienda.Api")
            .GetResult();

        Assert.True(resultado.IsSuccessful,
            "Violan la regla: " + string.Join(", ", resultado.FailingTypeNames ?? []));
    }

    [Fact]
    public void Aplicacion_no_depende_de_infraestructura()
    {
        var resultado = Types.InAssembly(Aplicacion)
            .ShouldNot().HaveDependencyOnAny(
                "Tienda.Infraestructura", "Tienda.Api", "Microsoft.EntityFrameworkCore")
            .GetResult();

        Assert.True(resultado.IsSuccessful,
            "Violan la regla: " + string.Join(", ", resultado.FailingTypeNames ?? []));
    }
}
```

Cada test devuelve un `TestResult`; si algún tipo viola la regla, `IsSuccessful` es `false` y `FailingTypeNames` lista los culpables, de modo que el mensaje del test dice qué clase arreglar. La segunda regla incluye `Microsoft.EntityFrameworkCore` porque una dependencia al ORM no pasa por ninguna `ProjectReference` interna y solo se ve así. Los nombres son prefijos de espacio de nombres: `"Tienda.Infraestructura"` cubre todos los espacios de nombres que cuelgan de él.

NetArchTest mira lo que el código **usa** una vez compilado: un `using` sin ningún uso real no deja rastro en el ensamblado y no lo detecta. Un `IQueryable` en una firma tampoco lo detecta, porque es un tipo de `System.Linq`; esa violación se vigila con la revisión de firmas (o con `BannedSymbols.txt`, ver más abajo).

### Analizadores

Existen analizadores de Roslyn que prohíben `using` o símbolos concretos por proyecto; el paquete `Microsoft.CodeAnalysis.BannedApiAnalyzers` permite declarar en un fichero `BannedSymbols.txt` los tipos que un proyecto no puede usar. Funciona bien para cosas finas (`T:Microsoft.AspNetCore.Http.HttpContext` prohibido en `Tienda.Aplicacion`) y da el error en el editor, antes de compilar. Se complementa con los tests de arquitectura, no los sustituye.

## Cómo cruzan los datos la frontera

Una capa exterior habla con la interior con los tipos de la interior, y cada capa tiene sus propios modelos para lo que recibe y devuelve:

```csharp
// Tienda.Api — modelo de la petición HTTP, con sus atributos y su forma pública
public record ConfirmarPedidoRequest(int ClienteId, string? CodigoDescuento);

// Tienda.Aplicacion — comando del caso de uso, sin nada de HTTP
public record ConfirmarPedidoComando(int PedidoId, string? CodigoDescuento);

// Tienda.Infraestructura — fila de la tabla, con la forma de la base de datos
public class PedidoFila
{
    public int Id { get; set; }
    public string Estado { get; set; } = "";
    public DateTime CreadoEnUtc { get; set; }
}
```

El controlador traduce `ConfirmarPedidoRequest` a `ConfirmarPedidoComando` y el repositorio traduce `PedidoFila` a `Pedido` y viceversa. Son tres clases con campos parecidos y esa duplicación es el precio de la independencia: la API puede añadir un campo sin tocar el negocio, y una migración de la tabla no cambia el contrato público.

Compartir un único modelo entre capas (la entidad `Pedido` serializada tal cual en la respuesta, o `PedidoFila` usada como argumento del caso de uso) hace que un cambio en una capa se propague a todas, y reintroduce por el tipo la dependencia que la regla había eliminado. La entidad de dominio tampoco debe salir por la API: expone invariantes y colecciones mutables que el consumidor no debe tocar. Dónde viven los resultados y errores que cruzan la frontera se trata en [Códigos de Resultado por Capa](Codigos-de-Resultado-por-Capa.md).

## Cuándo la regla se relaja

La regla protege el negocio de lo que **cambia o se puede sustituir**: base de datos, framework web, proveedor externo, formato de transporte. No protege de la plataforma sobre la que todo se ejecuta, y aplicarla con ese celo produce capas llenas de envoltorios inútiles.

| Dependencia | ¿Permitida en Dominio/Aplicación? | Criterio |
|---|---|---|
| `System.*` (colecciones, `DateTime`, `Guid`, `Task`, LINQ sobre objetos en memoria) | Sí | Es el lenguaje, no una tecnología sustituible |
| `Microsoft.Extensions.Logging.Abstractions` (`ILogger<T>`) | Sí, en Aplicación | Es una abstracción estable y sin implementación; evita inventar `ILogger` propio. En Dominio, mejor evitarlo: las entidades no registran logs |
| `Microsoft.Extensions.DependencyInjection.Abstractions` | Solo en el proyecto que registra servicios, no en clases de negocio | Una entidad o un caso de uso no deberían pedirle servicios a un contenedor (`IServiceProvider`) |
| `TimeProvider` (.NET 8) | Sí | Abstracción de la plataforma para controlar la hora en las pruebas |
| MediatR, FluentValidation u otra librería de terceros | Decisión del equipo, explícita y única | Si la aplicación se escribe en torno a ella (`IRequest<T>`), cambiarla cuesta tanto como cambiar el ORM; ver [MediatR](../patrones-de-diseno/MediatR.md) |
| Un SDK de proveedor (cliente de la pasarela de pago, `DbContext`, ASP.NET Core) | No | Es exactamente lo que la regla aísla |

El criterio práctico: ¿qué costaría sustituirla, y es plausible que ocurra? Cambiar de `ILogger` casi nunca ocurre y su coste es bajo; cambiar de pasarela de pago ocurre y arrastra todo el código que conozca su SDK. Cuando se relaje la regla, que sea por un tipo concreto, anotado en el test de arquitectura (las excepciones permitidas son una lista visible), no por un paquete entero.

## Buenas prácticas avanzadas

- **Revisa los `.csproj` como código** — una `ProjectReference` o `PackageReference` nueva en `Tienda.Dominio` o `Tienda.Aplicacion` es la forma más silenciosa de romper la regla y casi nunca se mira en una pull request. Un test que lea el grafo de referencias o una norma de revisión para esos dos ficheros cuesta poco.
- **Prohíbe paquetes concretos en el test de arquitectura, no solo capas propias** — `HaveDependencyOn("Tienda.Infraestructura")` no detecta que `Tienda.Aplicacion` use `Microsoft.EntityFrameworkCore` a través de un paquete transitivo. Añade a la lista los espacios de nombres del ORM, de ASP.NET Core y del serializador.
- **Un `Include` o una paginación en el caso de uso delatan un contrato de repositorio demasiado genérico** — si la capa de aplicación necesita saber cómo se cargan los datos, el ORM se ha filtrado por la firma. El repositorio debe ofrecer métodos con nombre de negocio y decidir internamente qué cargar.
- **Un `internal` en la infraestructura evita que se use desde fuera de sitio** — marca `RepositorioPedidos` como `internal` y expón solo un método de registro (`AddInfraestructura()`). La API enlaza las piezas sin poder instanciar el adaptador directamente, y ninguna capa tiene la tentación de usar la clase concreta en lugar de la interfaz.
- **Añade una regla por cada dirección prohibida al crecer la solución** — si aparece un proyecto nuevo (otro punto de entrada, una librería de utilidades), el test debe prohibir explícitamente que `Tienda.Dominio` y `Tienda.Aplicacion` lo referencien. Una regla que no menciona al proyecto nuevo no lo protege.
- **Ejecuta el test de arquitectura en la integración continua con un fallo claro** — que el mensaje liste los tipos culpables (`FailingTypeNames`). Un test que falla con «False» invita a comentarlo; uno que dice qué clase arreglar se corrige en minutos.

## Documentación oficial

- [The Clean Architecture (Robert C. Martin)](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html) — el artículo donde se enuncia la regla; la sección «The Dependency Rule» y el apartado sobre cómo cruzan los datos los límites son lo que merece la pena.
- [Principios arquitectónicos de Microsoft (Dependency Inversion y Separation of Concerns)](https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/architectural-principles) — la lectura de referencia para ver cómo se traduce la regla a proyectos .NET.
- [NetArchTest en GitHub](https://github.com/BenMorris/NetArchTest) — el README lista los predicados disponibles (`ResideInNamespace`, `HaveDependencyOn`, `ImplementInterface`) para reglas más finas que las del ejemplo.

---

*En resumen: las flechas del código apuntan hacia dentro aunque el flujo de ejecución salga hacia fuera, y esa dirección solo se mantiene si el compilador y un test de arquitectura la vigilan.*
