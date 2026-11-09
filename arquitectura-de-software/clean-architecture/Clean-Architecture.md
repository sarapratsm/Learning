# Clean Architecture

## ¿Qué es?

Clean Architecture es una forma de organizar el código de una aplicación en **capas concéntricas**: las reglas de negocio quedan en el centro y los detalles técnicos (base de datos, framework web, servicios externos) en el borde. Cada capa solo conoce a las que están más hacia dentro, nunca al revés.

## ¿Por qué existe?

Cuando un proyecto crece sin estructura, todo acaba mezclado: la regla «un pedido sin líneas no se puede confirmar» vive en un controlador, el cálculo del total se hace con una consulta SQL escrita a mano, y la llamada a la pasarela de pago está en medio de ambas. El resultado es un código que solo se puede probar levantando la base de datos y el servicio de pagos, y que da miedo cambiar: se toca una columna y se rompe una pantalla.

Clean Architecture separa **qué hace** la aplicación (las reglas de negocio) de **cómo lo hace** (la tecnología concreta). Se puede cambiar de base de datos, de framework web o de pasarela de pago sin reescribir las reglas, y las reglas se pueden probar sin levantar nada.

> Si ya conoces el patrón Modelo-Vista-Controlador (MVC), piensa en Clean Architecture como «MVC llevado al extremo»: no solo se separa la vista de la lógica, sino que la lógica queda aislada de **absolutamente todo** lo que sea un detalle técnico, incluida la base de datos.

## ¿Cuándo y para qué se usa?

En aplicaciones de negocio que van a vivir y crecer durante años: el backend de una tienda online, la gestión de pedidos de un almacén, una plataforma de reservas. En todas ellas las reglas («un pedido pagado no se puede cancelar», «el stock no puede ser negativo») son lo más valioso y lo que más conviene proteger de los cambios técnicos. La sección [Cuándo sí y cuándo no](#cuándo-sí-y-cuándo-no) concreta dónde compensa y dónde no.

Cada pieza se desarrolla en su propia ficha: [Regla de Dependencia](Regla-de-Dependencia.md), [Inversión de Dependencias](Inversion-de-Dependencias.md), [Capa de Dominio](Capa-de-Dominio.md), [Casos de Uso](Casos-de-Uso.md), [Puertos y Adaptadores](Puertos-y-Adaptadores.md) y [Capa de Infraestructura](Capa-de-Infraestructura.md).

---

## El problema: un controlador que lo hace todo

Una tienda online tiene el endpoint `POST /pedidos/4711/confirmar`. Esta es la versión en la que todo está junto:

```csharp
// ❌ Un solo método valida, calcula, consulta, cobra y escribe en la base de datos
[ApiController]
[Route("pedidos")]
public class PedidosController(IConfiguration config, HttpClient http) : ControllerBase
{
    [HttpPost("{id}/confirmar")]
    public async Task<IActionResult> Confirmar(int id)
    {
        using var db = new SqlConnection(config.GetConnectionString("Tienda"));

        var lineas = (await db.QueryAsync<(int ProductoId, int Cantidad, decimal Precio)>(
            "SELECT ProductoId, Cantidad, PrecioUnitario FROM LineasPedido WHERE PedidoId = @id",
            new { id })).ToList();

        if (lineas.Count == 0)                       // regla de negocio
            return BadRequest("Un pedido sin líneas no se puede confirmar.");

        var total = lineas.Sum(l => l.Cantidad * l.Precio);   // cálculo

        var cobro = await http.PostAsJsonAsync(      // servicio externo
            "https://pagos.example.com/cobros", new { pedido = id, importe = total });
        if (!cobro.IsSuccessStatusCode)
            return StatusCode(502, "Pago rechazado.");

        await db.ExecuteAsync(                       // persistencia
            "UPDATE Pedidos SET Estado = 'Pagado' WHERE Id = @id", new { id });
        return Ok(new { id, total });
    }
}
```

Para probar la regla del pedido vacío hace falta una base de datos real. Para cambiar de pasarela de pago hay que editar el controlador. Y si mañana el pedido se confirma también desde una cola de mensajes, la regla hay que copiarla.

La misma funcionalidad separada por capas queda así:

```csharp
// ✅ El controlador solo traduce HTTP
[ApiController]
[Route("pedidos")]
public class PedidosController(ConfirmarPedido confirmarPedido) : ControllerBase
{
    [HttpPost("{id}/confirmar")]
    public async Task<IActionResult> Confirmar(int id, CancellationToken ct)
    {
        try
        {
            var resumen = await confirmarPedido.Ejecutar(id, ct);
            return Ok(resumen);
        }
        catch (ReglaDeNegocioException ex)
        {
            return Conflict(ex.Message);
        }
    }
}

// ✅ El caso de uso orquesta; no sabe de HTTP, de SQL ni de la pasarela concreta
public class ConfirmarPedido(IRepositorioPedidos pedidos, IPasarelaPago pasarela, INotificador notificador)
{
    public async Task<ResumenPedido> Ejecutar(int pedidoId, CancellationToken ct)
    {
        var pedido = await pedidos.Obtener(pedidoId, ct)
            ?? throw new ReglaDeNegocioException($"El pedido {pedidoId} no existe.");

        pedido.Confirmar();                                   // la regla vive en la entidad
        var cobro = await pasarela.Cobrar(pedido.Id, pedido.Total, ct);
        if (!cobro.Aceptado)
            throw new ReglaDeNegocioException("El pago ha sido rechazado.");

        pedido.RegistrarPago();
        await pedidos.Guardar(pedido, ct);
        await notificador.PedidoConfirmado(pedido.Id, ct);

        return new ResumenPedido(pedido.Id, pedido.Estado, pedido.Total);
    }
}

// ✅ La entidad protege sus propias reglas
public class Pedido(int id)
{
    private readonly List<LineaPedido> _lineas = [];

    public int Id { get; } = id;
    public EstadoPedido Estado { get; private set; } = EstadoPedido.Borrador;
    public IReadOnlyList<LineaPedido> Lineas => _lineas;
    public decimal Total => _lineas.Sum(l => l.Cantidad * l.PrecioUnitario);

    public void Confirmar()
    {
        if (_lineas.Count == 0)
            throw new ReglaDeNegocioException("Un pedido sin líneas no se puede confirmar.");
        Estado = EstadoPedido.Confirmado;
    }

    public void RegistrarPago() => Estado = EstadoPedido.Pagado;

    public void Cancelar()
    {
        if (Estado == EstadoPedido.Pagado)
            throw new ReglaDeNegocioException("Un pedido pagado no se puede cancelar.");
        Estado = EstadoPedido.Cancelado;
    }
}
```

`IRepositorioPedidos`, `IPasarelaPago` e `INotificador` son interfaces: el caso de uso declara qué necesita y otra capa decide cómo. Con ellas, la regla del pedido vacío se prueba con un `new Pedido(4711)` y sin ninguna base de datos, y cambiar de pasarela es escribir otra implementación de `IPasarelaPago`.

## Las cuatro capas

| Capa | Qué vive en ella | Ejemplo en la tienda | Cambia cuando... |
|---|---|---|---|
| **Dominio** | Entidades, objetos de valor y reglas de negocio | `Pedido`, `LineaPedido`, `Cliente`, `Producto`; «el stock no puede ser negativo» | cambia el negocio |
| **Aplicación** (casos de uso) | Orquestación de una acción completa; interfaces (puertos) de lo que necesita del exterior | `ConfirmarPedido`, `CancelarPedido`, `IRepositorioPedidos`, `IPasarelaPago`, `INotificador` | cambia lo que la aplicación ofrece |
| **Adaptadores** | Traducen entre el formato del exterior y el de la aplicación | `PedidosController` (entrada), `RepositorioPedidosEf` (salida) | cambia un formato o un contrato externo |
| **Infraestructura** | Las herramientas concretas: ORM, base de datos, cliente HTTP, colas, SMTP | Entity Framework Core, SQL Server, `HttpClient` hacia la pasarela | cambia una herramienta |

De dentro hacia fuera, la estabilidad baja: el dominio casi no cambia, la infraestructura se sustituye con frecuencia. Por eso cada capa conoce a las de dentro y nunca a las de fuera (detalle en [Regla de Dependencia](Regla-de-Dependencia.md)).

En .NET, los adaptadores y la infraestructura suelen convivir en los mismos proyectos: los adaptadores de entrada (controladores) en `Tienda.Api` y los de salida (repositorios, clientes de la pasarela) en `Tienda.Infraestructura`. La frontera entre «adaptador» e «infraestructura» es conceptual: el adaptador *traduce*, la herramienta *hace el trabajo*. Más en [Puertos y Adaptadores](Puertos-y-Adaptadores.md).

### Recorrido de «confirmar el pedido #4711»

Una petición atraviesa las capas hacia dentro y vuelve hacia fuera:

```text
POST /pedidos/4711/confirmar
  │
  ▼  Api / adaptador de entrada
PedidosController.Confirmar(4711)          traduce HTTP → llamada al caso de uso
  │
  ▼  Aplicación
ConfirmarPedido.Ejecutar(4711)             orquesta los pasos
  │   ├─ IRepositorioPedidos.Obtener(4711)     ┐ puerto: la aplicación pide «dame el pedido»
  │   │        └─ RepositorioPedidosEf          │ adaptador de salida → SQL Server (infraestructura)
  │   ├─ Pedido.Confirmar()                    ← Dominio: ¿tiene líneas? → estado Confirmado
  │   ├─ IPasarelaPago.Cobrar(4711, total)     ┐ puerto
  │   │        └─ PasarelaPagoHttp              │ adaptador → HttpClient (infraestructura)
  │   ├─ Pedido.RegistrarPago()                ← Dominio: estado Pagado
  │   ├─ IRepositorioPedidos.Guardar(pedido)   → UPDATE en la base de datos
  │   └─ INotificador.PedidoConfirmado(4711)   → correo al cliente
  │
  ▼  vuelta
ResumenPedido(4711, Pagado, 89,90)  →  controlador  →  200 OK + JSON
```

Qué hace cada capa en este recorrido:

- **Adaptador de entrada:** extrae `4711` de la ruta y convierte el resultado en un código HTTP. Si hay una `ReglaDeNegocioException`, responde `409 Conflict`. No decide nada de negocio.
- **Caso de uso:** conoce el orden (cargar, confirmar, cobrar, guardar, notificar) pero no las reglas. No sabe si el pedido tiene líneas: se lo pregunta a la entidad.
- **Dominio:** `Pedido.Confirmar()` aplica la regla. No sabe que existe una base de datos ni HTTP.
- **Adaptadores de salida e infraestructura:** convierten `Pedido` en filas y viceversa, y llaman a la pasarela por HTTP. Son la única parte que cambia si cambia la base de datos.

Dónde se abre y se cierra la transacción, y qué pasa si la petición se repite, es asunto de [Casos de Uso](Casos-de-Uso.md).

## La solución .NET: proyectos y referencias

Cada capa interna es un proyecto de la solución, y las referencias entre proyectos hacen cumplir la regla: si `Tienda.Dominio` no referencia a nadie, es imposible que use Entity Framework por accidente, porque el compilador no lo permite.

```text
Tienda.sln
├── Tienda.Dominio           ← no referencia a ningún proyecto ni paquete de infraestructura
├── Tienda.Aplicacion        ← referencia a Tienda.Dominio
├── Tienda.Infraestructura   ← referencia a Tienda.Aplicacion (y, por tanto, al dominio)
└── Tienda.Api               ← referencia a Tienda.Aplicacion y a Tienda.Infraestructura
```

```xml
<!-- Tienda.Infraestructura.csproj -->
<ItemGroup>
  <ProjectReference Include="..\Tienda.Aplicacion\Tienda.Aplicacion.csproj" />
  <PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" Version="8.0.*" />
</ItemGroup>
```

`Tienda.Api` referencia a `Tienda.Infraestructura` solo por una razón: en `Program.cs` se registran las implementaciones concretas (`IRepositorioPedidos` → `RepositorioPedidosEf`). Ese es el único punto donde las capas externas se juntan; cómo se hace y por qué la flecha de código sigue apuntando hacia dentro se explica en [Inversión de Dependencias](Inversion-de-Dependencias.md).

La contraparte de tener un proyecto por capa es que el sistema de proyectos de .NET solo vigila las referencias entre proyectos, no los `using` dentro de uno. Un proyecto único con carpetas `Dominio/`, `Aplicacion/`... funciona, pero la regla se sostiene solo por disciplina o con tests de arquitectura.

## Cuándo sí y cuándo no

| Situación | ¿Capas completas? | Por qué |
|---|---|---|
| CRUD puro (alta, edición y listado de datos sin reglas) | No | Entidad + caso de uso + DTO + mapeo por cada formulario es coste sin protección que ofrecer |
| Prototipo o herramienta interna de vida corta | No | La estructura tarda más en pagarse que lo que dura el código |
| Lógica de negocio compleja: estados, reglas que se combinan, varias formas de entrar (API, colas, tareas programadas) | Sí | Es lo que las capas protegen, y se prueba sin infraestructura |
| Producto de larga vida donde se prevé cambiar de base de datos, pasarela o proveedor | Sí | El coste del cambio queda confinado a un adaptador |
| Una aplicación con una parte con reglas y otra de simple mantenimiento de datos | Mixto | Capas donde hay reglas (`Pedido`), atajo donde no (catálogo de provincias) |

Atajos legítimos, siempre deliberados y documentados:

- **Lecturas directas.** Un listado de pedidos para una pantalla puede consultar la base de datos y devolver un modelo de lectura sin pasar por entidades de dominio: solo lee, no puede violar ninguna regla.
- **Mantenimiento de tablas auxiliares** sin reglas (países, tipos de IVA) con un CRUD directo.

Lo que no es un atajo legítimo: escribir en la base de datos desde el controlador cuando hay una regla de negocio en medio. Ese es el patrón del controlador de la primera sección.

## El coste real

Las capas no son gratis, y conviene verlo con un ejemplo. Se añade un campo `Telefono` a `Cliente` que debe guardarse y mostrarse en la API. Número orientativo de ficheros que se tocan en cada enfoque:

| Pieza | CRUD directo (un modelo para todo) | Con capas y modelos separados |
|---|---|---|
| Entidad con el campo | 1 (`Cliente`) | 1 (`Cliente` en `Tienda.Dominio`) |
| Modelo de persistencia / configuración del ORM | — (es la misma clase) | 1 (`ClienteEntidadBd` o su configuración) |
| Mapeo dominio ↔ persistencia | — | 1 |
| Migración de base de datos | 1 | 1 |
| Resultado del caso de uso (DTO de aplicación) | — | 1 |
| Petición/respuesta de la API (DTO HTTP) | — | 1 o 2 |
| Mapeo DTO ↔ resultado | — | 1 |
| **Total** | **2** | **entre 7 y 8** |

Son recuentos de una solución con modelos distintos en cada capa; en la práctica varían, pero el orden de magnitud se mantiene. Ese sobrecoste solo se justifica si lo que se compra es real: cambiar la columna `Telefono` por `TelefonoMovil` rompe en el CRUD directo el contrato público de la API; con capas se arregla en el mapeo de persistencia y la API no se entera.

Dos advertencias que reducen el coste sin romper la separación:

- No hace falta un DTO por capa cuando dos capas comparten forma y es improbable que diverjan; sí hace falta cuando una de ellas es un contrato externo (la API) o un detalle de almacenamiento (la tabla).
- Los mapeos son código aburrido y de bajo riesgo: es preferible escribirlos a mano que ocultarlos tras una configuración mágica que nadie lee.

## Organización de carpetas: por negocio, no por tipo

Dentro de cada proyecto hay dos formas de ordenar los ficheros:

```text
✅ Por negocio                       ❌ Por tipo técnico
Tienda.Aplicacion/                   Tienda.Aplicacion/
├── Pedidos/                         ├── Servicios/
│   ├── ConfirmarPedido.cs           │   ├── ConfirmarPedido.cs
│   ├── CancelarPedido.cs            │   ├── CancelarPedido.cs
│   └── IRepositorioPedidos.cs       │   └── AltaCliente.cs
├── Clientes/                        ├── Interfaces/
│   └── AltaCliente.cs               │   ├── IRepositorioPedidos.cs
└── Catalogo/                        │   └── IRepositorioClientes.cs
    └── ...                          └── Dtos/ ...
```

La estructura por negocio responde a la pregunta «¿de qué va este sistema?» solo con abrir el repositorio: `Pedidos`, `Clientes`, `Catalogo`. La estructura por tipo solo dice qué framework se usó. A esa idea se la llama *screaming architecture* («arquitectura que grita»): la arquitectura debería gritar «tienda online», no «ASP.NET MVC». Cuando el sistema crece lo bastante para repartirse en módulos independientes con sus propias reglas de qué compartir, se pasa a [Módulos frente a Shared](Modulos-vs-Shared.md).

## Buenas prácticas avanzadas

- **Vigila los paquetes, no solo los `using`.** El acoplamiento más sutil entra por NuGet: basta que `Tienda.Dominio` referencie el paquete del ORM para decorar una entidad con `[Table]`, y el centro ya depende de la base de datos aunque ningún `using` lo delate. El proyecto de dominio debería tener cero referencias a paquetes de infraestructura; lo ideal, ninguna externa. Revisarlo es mirar el `.csproj`, no el código.
- **No reutilices el mismo modelo en todas las capas.** Usar `Pedido` como entidad de dominio, fila de base de datos y respuesta JSON ahorra mapeos hoy y suelda las capas para siempre: renombrar una columna pasa a romper el contrato público. Duplicar clases en las fronteras es el precio de poder cambiar cada capa por separado.
- **No repartas un CRUD en cuatro capas por disciplina.** Aplica la separación donde hay reglas que proteger, y deja atajos explícitos (lecturas directas, tablas auxiliares) donde no. Un atajo escrito y justificado es diseño; un atajo que aparece por descuido es deuda.
- **Convierte la regla de dependencias en un test.** Una herramienta de tests de arquitectura (por ejemplo NetArchTest) puede afirmar «`Tienda.Dominio` no depende de `Tienda.Infraestructura`» y fallar en la integración continua. Sin ese test, la estructura se degrada con la primera prisa.
- **El nombre de un caso de uso es una acción de negocio, no una operación técnica.** `ConfirmarPedido` o `CancelarPedido` cuentan qué ocurre; `PedidoService.Update` no. Cuando la clase de aplicación se llama `PedidoService` y acumula quince métodos, es la señal de que los casos de uso se están disolviendo en un cajón de sastre.
- **Prueba el centro sin infraestructura y la frontera con ella.** Las reglas del dominio y los casos de uso se prueban con implementaciones falsas de los puertos (rápido); los adaptadores, contra una base de datos real, por ejemplo con [Testcontainers](../../devops/docker/Testcontainers.md). Probar los adaptadores con falsos solo comprueba que el falso funciona.

## Documentación oficial

- [The Clean Architecture (Robert C. Martin)](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html) — el artículo que popularizó el diagrama de círculos concéntricos; breve, y donde se define la regla de dependencia.
- [Common web application architectures (Microsoft Learn)](https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/common-web-application-architectures) — cómo se traduce la idea a proyectos de ASP.NET Core; ir a la sección de arquitectura limpia para ver la estructura de proyectos recomendada.
- [Screaming Architecture (Robert C. Martin)](https://blog.cleancoder.com/uncle-bob/2011/09/30/Screaming-Architecture.html) — el argumento original a favor de organizar por negocio.

## Recursos didácticos

- [Hexagonal Architecture (Alistair Cockburn)](https://alistair.cockburn.us/hexagonal-architecture/) — el origen de los puertos y adaptadores, la idea sobre la que se apoya Clean Architecture; útil para ver que son la misma familia con distinto dibujo.
- [Domain-Driven Design](../patrones-de-diseno/Domain-Driven-Design.md) y [Entidades y Agregados](../patrones-de-diseno/Entidades-y-Agregados.md) — cómo se modela el contenido del círculo central.

---

*En resumen: Clean Architecture pone las reglas de negocio en el centro y empuja las herramientas al borde, para que cambiar de base de datos o de framework sea cambiar un adaptador y no reescribir la aplicación.*
