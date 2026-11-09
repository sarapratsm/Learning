# Tipos de tests

## ¿Qué es?

Una clasificación de los tests automatizados según *cuántas piezas reales* ejercitan: desde una sola clase aislada (test unitario) hasta la API completa con una base de datos real detrás (integración y extremo a extremo). Cada tipo responde a una pregunta distinta y detecta fallos que los otros no ven.

## ¿Por qué existe?

Una suite con un solo tipo de test falla de una de dos maneras. Si todo son tests de extremo a extremo, la suite tarda minutos, se rompe por motivos ajenos al código (un puerto ocupado, un dato compartido) y, cuando falla, el mensaje no dice dónde está el defecto. Si todo son tests unitarios con dobles de prueba (objetos falsos que sustituyen a las dependencias), la suite es rápida y estable, pero pasa en verde mientras la consulta real a la base de datos no se puede ejecutar o el endpoint devuelve el código de estado equivocado: nadie ha probado nunca que las piezas encajen.

La solución son **capas con propósito distinto**: muchos tests baratos que fijan las reglas de negocio, menos tests que comprueban que cada pieza habla bien con su recurso real (base de datos, HTTP) y muy pocos que recorren el sistema entero.

> Piensa en una revisión de un coche. Probar cada pieza en el banco (el freno, el motor) es rápido y dice exactamente qué pieza falla, pero no demuestra que el coche frene al ir montado. Una vuelta a la pista lo demuestra, pero tarda, y si falla hay que desmontar para saber por qué. Las revisiones sensatas hacen las dos cosas, y muchas más del banco que de la pista.

## ¿Cuándo y para qué se usa?

Desde el primer día de un proyecto: la pregunta no es si hacer tests unitarios o de integración, sino en qué nivel colocar cada regla. El mapa de tipos sirve para decidirlo y para organizar la solución en proyectos de prueba separados por tipo.

Todos los ejemplos proceden de la misma tienda online, con la regla *un pedido sin líneas no se puede confirmar* probada en tres niveles. Se ejecutaron el 2026-11-09 con .NET SDK 10.0.401, xUnit 2.9.3, `Microsoft.NET.Test.Sdk` 17.14.1, `Microsoft.EntityFrameworkCore.Sqlite` 10.0.14 y `Microsoft.AspNetCore.Mvc.Testing` 10.0.14. El `Pedido` es una versión reducida: id entero, líneas con producto, cantidad y precio, y las operaciones `AgregarLinea`, `Total` y `Confirmar`.

## Un test unitario: la regla sola

Un **test unitario** ejercita una unidad de lógica (una clase, un método) sin base de datos, sin red y sin disco, y no necesita nada que no sea código propio. Aquí interviene **una sola pieza real**: `Pedido`.

```csharp
[Trait("Tipo", "Unitario")]
public class PedidoTests
{
    [Fact]
    public void Confirmar_SinLineas_LanzaReglaDeDominio()
    {
        var pedido = Pedido.Crear(4711);

        var ex = Assert.Throws<ReglaDeDominioException>(() => pedido.Confirmar());

        Assert.Equal("Un pedido sin líneas no se puede confirmar.", ex.Message);
    }
}
```

El test construye el pedido, intenta confirmarlo y comprueba que el dominio lanza su excepción con el mensaje esperado. Si alguien quita la comprobación de `Confirmar()`, este test falla en milisegundos y el fallo señala la línea exacta.

```text
Correctas! - Con error:     0, Superado:     2, Omitido:     0, Total:     2, Duración: 22 ms - Tienda.Dominio.Tests.dll (net10.0)
```

El proyecto tiene dos tests; tres ejecuciones seguidas dieron 22, 23 y 28 ms. El `[Trait]` es una etiqueta de xUnit que más abajo permite ejecutar solo un tipo.

## Un test de integración: la pieza con su recurso real

Un **test de integración** comprueba que una pieza funciona con el recurso real al que habla: la base de datos, el sistema de ficheros, un servicio HTTP. Aquí el repositorio `RepositorioPedidos` guarda un pedido y lo lee con EF Core sobre SQLite en memoria, una base de datos real aunque ligera. Intervienen **cinco piezas reales**: `Pedido`, `RepositorioPedidos`, `TiendaDbContext`, EF Core y el motor SQLite.

```csharp
[Trait("Tipo", "Integracion")]
public sealed class RepositorioPedidosTests : IDisposable
{
    private readonly SqliteConnection _conexion = new("Data Source=:memory:");
    private readonly DbContextOptions<TiendaDbContext> _opciones;

    public RepositorioPedidosTests()
    {
        _conexion.Open(); // la base en memoria vive mientras la conexión esté abierta
        _opciones = new DbContextOptionsBuilder<TiendaDbContext>().UseSqlite(_conexion).Options;
        using var db = new TiendaDbContext(_opciones);
        db.Database.EnsureCreated();
    }

    public void Dispose() => _conexion.Dispose();

    [Fact]
    public async Task Guardar_PedidoConfirmado_SeRecuperaConSusLineas()
    {
        var pedido = Pedido.Crear(4711);
        pedido.AgregarLinea(productoId: 1, cantidad: 2, precioUnitario: 10m);
        pedido.Confirmar();
        await new RepositorioPedidos(new TiendaDbContext(_opciones)).GuardarAsync(pedido);

        // contexto nuevo: lee de la base, no de la caché del contexto anterior
        var leido = await new RepositorioPedidos(new TiendaDbContext(_opciones)).ObtenerAsync(4711);

        Assert.NotNull(leido);
        Assert.Equal(EstadoPedido.Confirmado, leido.Estado);
        Assert.Single(leido.Lineas);
    }
}
```

Cada test crea su propia conexión y su propia base, así que no comparte datos con ningún otro. La lectura usa un contexto distinto del de la escritura: con el mismo contexto, EF devolvería el objeto que ya tiene en memoria y el test no tocaría la base. Aquí la regla de negocio ya no se comprueba; se comprueba que el estado `Confirmado` y las líneas sobreviven a un viaje de ida y vuelta por el esquema real.

```text
Correctas! - Con error:     0, Superado:     2, Omitido:     0, Total:     2, Duración: 1 s - Tienda.Infraestructura.Tests.dll (net10.0)
```

Tres ejecuciones dieron 1 s (el runner no muestra decimales por encima del segundo). La diferencia con el unitario es de uno o dos órdenes de magnitud; no se midió en qué fase se va el tiempo. SQLite sirve para comprobar el mapeo y las consultas; una restricción o una función propia de PostgreSQL o SQL Server exige un motor real, que [Testcontainers](Testcontainers.md) levanta en un contenedor efímero.

## Un test de API: la petición HTTP contra la aplicación real en memoria

Un **test de API** (o de extremo a extremo parcial) envía una petición HTTP a la aplicación arrancada en el propio proceso, sin abrir puertos. `WebApplicationFactory<Program>` (del paquete `Microsoft.AspNetCore.Mvc.Testing`) levanta la API real: enrutado, inyección de dependencias, serialización, el caso de uso `ConfirmarPedido`, el repositorio y SQLite. Su funcionamiento completo está en [WebApplicationFactory](WebApplicationFactory.md). Intervienen **unas diez piezas reales**: las cinco anteriores más el host de ASP.NET Core, el enrutado del endpoint, el contenedor de inyección de dependencias, el caso de uso y la serialización de la respuesta.

```csharp
[Trait("Tipo", "Api")]
public class ConfirmarEndpointTests(WebApplicationFactory<Program> factory)
    : IClassFixture<WebApplicationFactory<Program>>
{
    private async Task Sembrar(Pedido pedido)
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<TiendaDbContext>();
        db.Pedidos.Add(pedido);
        await db.SaveChangesAsync();
    }

    [Fact]
    public async Task Confirm_PedidoSinLineas_Devuelve409()
    {
        await Sembrar(Pedido.Crear(4711));
        var client = factory.CreateClient();

        var respuesta = await client.PostAsync("/orders/4711/confirm", content: null);

        Assert.Equal(HttpStatusCode.Conflict, respuesta.StatusCode);
        Assert.Contains("sin líneas", await respuesta.Content.ReadAsStringAsync());
    }
}
```

El test deja el pedido #4711 sin líneas en la base, hace `POST /orders/4711/confirm` y comprueba el contrato HTTP: la regla de negocio llega al cliente como un `409 Conflict` con el mensaje. Ese `409` lo decide el endpoint (captura la excepción de dominio y la traduce); ni el test unitario ni el de integración pueden saber si esa traducción existe.

```text
Correctas! - Con error:     0, Superado:     2, Omitido:     0, Total:     2, Duración: 1 s - Tienda.Api.Tests.dll (net10.0)
```

Tres ejecuciones dieron 1 s. Las diez piezas son un recuento orientativo; el número exacto depende de cómo se cuenten el middleware y los servicios del framework.

A nivel de navegador, un test de extremo a extremo real maneja la interfaz con un navegador de verdad; está en [Playwright](../e2e/Playwright.md).

Los tiempos y recuentos dependen de la máquina y de si la compilación está caliente; las tres ejecuciones se hicieron con `--no-build` en un Windows 11 de uso normal. Cuenta el orden de magnitud (milisegundos, un segundo, un segundo o más), no la cifra.

## Cuánto cuesta cada tipo

Valoración cualitativa, no medida:

| | Velocidad | Fragilidad | Diagnóstico cuando falla |
|---|---|---|---|
| **Unitario** | Milisegundos | Baja: solo se rompe si cambia la regla | Exacto: señala la unidad y la línea |
| **Integración** | Cientos de ms a segundos | Media: depende del esquema, del motor y del orden de datos | Bueno: acota a una pieza y su recurso |
| **API (parcial)** | Segundos | Media-alta: cualquier capa puede romperlo | Más difuso: hay que mirar qué capa falló |
| **Extremo a extremo (navegador)** | Segundos a minutos | Alta: red, tiempos, datos, interfaz | Pobre: «algo falló en el flujo» |

## La pirámide y sus variantes

La **pirámide** (muchos unitarios, menos integración, pocos de extremo a extremo) es una heurística sobre dónde conviene gastar el esfuerzo. Existen otras formas, y ninguna es una ley: la forma correcta es la que pone los tests donde vive el riesgo de *esa* aplicación.

| Forma | Reparto | Encaja cuando |
|---|---|---|
| **Pirámide** | Base ancha de unitarios | Hay mucha lógica de negocio propia: reglas, cálculos, máquinas de estados |
| **Trofeo** | Pocos unitarios, mucha integración | La aplicación es sobre todo orquestación (CRUD, API que coordina servicios) y la lógica pura es escasa |
| **Panal** | Casi todo integración sobre servicios pequeños | Microservicios cuya lógica interna es mínima y el riesgo está en los contratos entre servicios |

Es criterio, no norma: una API CRUD con poca lógica gana más con tests de integración contra la base real que con cientos de unitarios triviales, y un motor de precios gana más con una pirámide clásica.

## Dobles de prueba frente a recursos reales, por nivel

Un **doble de prueba** (*fake*, *stub*, *mock*) sustituye a una dependencia para aislar la unidad. Lo que se sustituye marca el tipo de test:

| Nivel | Se sustituye | Se usa real |
|---|---|---|
| **Unitario** | Casi todas las dependencias: repositorio, pasarela de pago, notificador | La unidad bajo prueba y su dominio puro |
| **Integración** | Lo que queda fuera de la frontera probada (la pasarela de pago externa) | El recurso que la pieza usa: la base de datos, el sistema de ficheros |
| **API** | Solo servicios externos fuera de tu control (pasarela, correo) | Todo el código propio, el enrutado, la inyección de dependencias y la base |

La regla práctica: se sustituye lo que no controlas o lo que haría el test lento o no determinista; no se sustituye aquello cuyo comportamiento real es justamente lo que se quiere comprobar. [NSubstitute](NSubstitute.md) desarrolla cómo crear los dobles.

## Lo que un tipo de test no ve

Cada capa tiene un punto ciego. El más frecuente: un test unitario con un *fake* que pasa mientras la consulta real no se puede ejecutar. El caso de uso necesita una consulta de pedidos confirmados ordenados por total. Con un repositorio falso basado en una lista, que ejecuta la expresión como código C# normal, el test unitario pasa:

```csharp
// En Tienda.Aplicacion.Tests: el fake evalúa la expresión con LINQ to Objects
public Task<IReadOnlyList<Pedido>> ConfirmadosPorTotalAsync(CancellationToken ct = default) =>
    Task.FromResult<IReadOnlyList<Pedido>>(Pedidos
        .Where(p => p.Estado == EstadoPedido.Confirmado)
        .OrderByDescending(p => p.Total())   // método de C# propio de Pedido
        .ToList());
```

```text
Correctas! - Con error:     0, Superado:     2, Omitido:     0, Total:     2, Duración: 32 ms - Tienda.Aplicacion.Tests.dll (net10.0)
```

La implementación real del repositorio usa la misma expresión sobre `DbSet<Pedido>`, y un test de integración contra SQLite que pide esa misma consulta falla:

```text
Con error Tienda.Infraestructura.Tests.RepositorioPedidosTests.ConfirmadosPorTotal_OrdenaDeMayorAMenor [23 ms]
  Mensaje de error:
   System.InvalidOperationException : The LINQ expression 'DbSet<Pedido>()
    .Where(p => (int)p.Estado == 1)
    .OrderByDescending(p => p.Total())' could not be translated. Either rewrite the query in a form that can be translated, or switch to client evaluation explicitly by inserting a call to 'AsEnumerable', 'AsAsyncEnumerable', 'ToList', or 'ToListAsync'.
```

EF Core traduce la consulta a SQL y no sabe traducir `Total()`, que es un método de C#. El fake nunca traduce nada, por eso no puede ver este fallo. La corrección es escribir la expresión en una forma traducible (`p.Lineas.Sum(l => l.PrecioUnitario * l.Cantidad)`); con ella, el test de integración pasa. El fallo lo produce EF Core al traducir la consulta; no se probó contra otros motores.

Resumen de puntos ciegos:

| Tipo | No ve |
|---|---|
| **Unitario** | Que las piezas encajen: mapeo, SQL, serialización, configuración de la inyección de dependencias |
| **Integración** | Que el contrato HTTP y el orden del *pipeline* sean los esperados; diferencias entre SQLite y el motor de producción |
| **API** | Que la interfaz de usuario funcione; qué capa falla exactamente |
| **Extremo a extremo** | Casi nada, pero tarda y diagnostica mal: no es sitio para probar cada regla |

## Contrato y humo en una línea

- **Test de contrato**: comprueba que dos lados de una frontera (un puerto y su adaptador, una API y sus clientes) cumplen el mismo acuerdo; típico para que un *fake* y la implementación real se comporten igual (ver [Puertos y Adaptadores](../../arquitectura-de-software/clean-architecture/Puertos-y-Adaptadores.md)).
- **Test de humo** (*smoke test*): comprueba lo mínimo para saber que el sistema arranca, por ejemplo `GET /healthz` devuelve 200; con la API en memoria detecta servicios sin registrar en la inyección de dependencias, middleware mal ordenado o configuración ausente, y es de los de mejor relación coste/valor.

## Elegir en qué nivel probar una regla nueva

| Pregunta | Si la respuesta es sí | Nivel |
|---|---|---|
| ¿Es una regla de negocio pura, sin I/O? | Se prueba con objetos en memoria | Unitario (dominio) |
| ¿Orquesta varios puertos sin lógica propia de SQL ni HTTP? | Se prueba con dobles de los puertos | Unitario (aplicación) |
| ¿Depende de SQL, de un índice único, de una clave foránea o de una consulta? | Solo un motor real la valida | Integración |
| ¿Es un contrato HTTP (código de estado, forma del JSON, validación de entrada, autorización)? | Hay que pasar por el enrutado y la serialización | API |
| ¿Es un flujo de varias pantallas que solo existe en el navegador? | Solo un navegador real lo ve | Extremo a extremo, pocos |

Una misma regla puede merecer dos niveles, como aquí: la regla en el dominio (unitario) y la traducción a `409` en la API. Lo que no merece es el mismo detalle en los cuatro. La metodología que dirige qué test escribir primero está en [TDD](../tdd-bdd-sdd/TDD.md).

## Organizar los tests en el repositorio

Un proyecto de pruebas por tipo (o por capa) permite ejecutar, referenciar y ordenar cada tipo por separado, y evita que el proyecto de tests unitarios arrastre paquetes de integración:

```text
Tienda.sln
├── src/
│   ├── Tienda.Dominio/
│   ├── Tienda.Aplicacion/
│   ├── Tienda.Infraestructura/
│   └── Tienda.Api/
└── tests/
    ├── Tienda.Dominio.Tests/           ← unitarios del dominio (referencia solo Tienda.Dominio)
    ├── Tienda.Aplicacion.Tests/        ← unitarios del caso de uso, con dobles de los puertos
    ├── Tienda.Infraestructura.Tests/   ← integración con EF Core + SQLite
    └── Tienda.Api.Tests/               ← API con WebApplicationFactory
```

Para ejecutar solo un tipo hay dos caminos. El primero, por proyecto:

```bash
dotnet test tests/Tienda.Dominio.Tests
```

El segundo, por etiqueta con `[Trait]` y `--filter`, válido sobre toda la solución. La sintaxis `Clave=Valor` funciona con xUnit 2.9.3, la versión del ejemplo:

```bash
dotnet test --filter "Tipo=Unitario"
```

```text
Correctas! - Con error:     0, Superado:     2, Omitido:     0, Total:     2, Duración: 29 ms - Tienda.Dominio.Tests.dll (net10.0)
Correctas! - Con error:     0, Superado:     2, Omitido:     0, Total:     2, Duración: 47 ms - Tienda.Aplicacion.Tests.dll (net10.0)
```

Los proyectos sin tests con esa etiqueta no ejecutan nada y el runner avisa de que ninguna prueba coincide con el filtro. Para varios tipos se combinan con `|`:

```bash
dotnet test --filter "Tipo=Api|Tipo=Integracion"
```

```text
Correctas! - Con error:     0, Superado:     2, Omitido:     0, Total:     2, Duración: 1 s - Tienda.Infraestructura.Tests.dll (net10.0)
Correctas! - Con error:     0, Superado:     2, Omitido:     0, Total:     2, Duración: 1 s - Tienda.Api.Tests.dll (net10.0)
```

Las salidas del runner salen localizadas según el idioma del sistema (aquí en español; en inglés dice `Passed!`). El filtro se verificó con xUnit v2; con xUnit v3 y el runner de Microsoft Testing Platform la forma de filtrar cambia (no se comprobó aquí).

### Orden en integración continua

En la integración continua se ejecutan primero los rápidos: los unitarios (segundos) dan el primer aviso, después los de integración y la API, y los de extremo a extremo al final o en un trabajo aparte. Así un error de lógica se descubre en segundos y no tras esperar a que arranque la base. La configuración del *pipeline* está en [CI/CD](../../devops/ci-cd/README.md).

## Lo que la cobertura no dice

La cobertura mide qué líneas ejecutó algún test, no de qué tipo era ni si comprobó algo: un test de integración puede cubrir el 100 % de una clase sin una sola aserción útil. Ver [Coverlet](Coverlet.md).

## Otros tipos, sin desarrollar

- **Rendimiento (carga, estrés):** miden tiempos y capacidad bajo carga, con herramientas específicas; no sustituyen a los funcionales.
- **Seguridad:** buscan vulnerabilidades (inyección, autorización rota) con análisis estático, escáneres o pruebas de autorización en la API.
- **Mutación:** cambian el código a propósito (un `>` por `>=`) y comprueban si algún test lo detecta, para medir la calidad de los tests; Stryker.NET (paquete `dotnet-stryker` en NuGet, consultado el 2026-11-09) es la herramienta para .NET.

## El cono de helado

El **cono de helado** es la pirámide invertida: casi todo son tests de extremo a extremo y manuales, pocos de integración y apenas unitarios. Suele surgir sin decidirlo, porque es lo más fácil de empezar a escribir con una aplicación ya hecha. Sus efectos: suites de media hora, fallos intermitentes (*flaky*) que enseñan a ignorar el rojo, y defectos de lógica que solo se descubren pasando por la interfaz, con un diagnóstico de «el flujo falló». Se corrige empujando cada regla al nivel más bajo que pueda comprobarla y dejando arriba solo los flujos críticos.

## Errores frecuentes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| Un test de integración arranca base de datos para comprobar un cálculo | Lógica pura probada en un nivel caro | Moverla a un test unitario del dominio |
| El test pasa aunque se borre la regla, y nunca falla | Tantos dobles que solo se prueban los dobles | Sustituir solo lo que no controlas; comprobar el resultado, no las llamadas |
| Un test unitario con un repositorio *fake* pasa y la consulta real falla (`could not be translated`) | El *fake* ejecuta C# donde la base ejecuta SQL | Probar las consultas contra una base real en integración |
| Los tests de integración pasan solos y fallan juntos, o según el orden | Comparten base o datos (p. ej. el pedido #4711 sembrado en una base común) | Una base o un estado limpio por test; no depender de datos de otro test |
| Cientos de tests de navegador y la suite tarda media hora | Un test de extremo a extremo por cada regla | Probar la regla en dominio o API; el navegador solo para el flujo completo |
| Un test cuelga y bloquea el *pipeline* | Una espera sin límite (contenedor, red, bloqueo) | Poner un tiempo máximo explícito |

## Buenas prácticas avanzadas

- **Decide qué NO sustituyes.** Si el comportamiento que importa vive en la base de datos (un índice único, una restricción, una consulta), pruébalo contra una base real; con un doble pruebas el doble.
- **Empieza por el test de humo.** Un `GET /healthz` con la API en memoria detecta la mitad de los errores de configuración por el precio de un test.
- **Ponle tiempo máximo a los tests asíncronos que tocan recursos.** Un `CancellationTokenSource` con límite convierte un cuelgue en un fallo con mensaje:

```csharp
using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
var respuesta = await client.GetAsync("/healthz", cts.Token);
```

- **Aísla el estado de cada test de integración.** Una base nueva por test (como con SQLite en memoria arriba) o una limpieza explícita; cuando compartirla sea imprescindible por coste, hazlo con fixtures y sin depender del orden ([Fixtures y ciclo de vida](Fixtures-y-ciclo-de-vida.md)).
- **Etiqueta con `[Trait]` además de separar por proyectos.** Los proyectos reflejan capas de código; la etiqueta permite cortes transversales («todo lo de pedidos», «lo rápido») en la integración continua.
- **Mide el tipo, no solo el porcentaje.** Una suite con 90 % de cobertura hecha solo de tests de integración lentos es difícil de mantener; el reparto por tipo es una métrica útil.

## Documentación oficial

- [Pruebas en .NET](https://learn.microsoft.com/dotnet/core/testing/): punto de entrada de Microsoft Learn sobre pruebas; sirve para ver qué tipos y marcos existen y cómo ejecutarlos con `dotnet test`.
- [Prácticas recomendadas para pruebas unitarias](https://learn.microsoft.com/dotnet/core/testing/unit-testing-best-practices): guía sobre nombres, aislamiento y uso de dobles; conviene antes de escribir los primeros tests unitarios.

## Recursos didácticos

- [The Practical Test Pyramid](https://martinfowler.com/articles/practical-test-pyramid.html): artículo de referencia sobre la pirámide, con ejemplos y matices (en inglés).
- [http.cat](https://http.cat/): cada código de estado HTTP ilustrado con un gato; útil cuando se asertan códigos como el `409` del ejemplo.

---

*En resumen: los tipos de test son capas de una misma defensa; la regla se fija abajo, donde es barata, y cada capa superior solo comprueba lo que la inferior no puede ver.*
