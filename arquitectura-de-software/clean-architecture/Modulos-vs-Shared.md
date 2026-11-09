# Módulos vs Shared

## ¿Qué es?

En un **monolito modular** (una aplicación que se despliega como un único ejecutable pero cuyo código se divide en módulos con fronteras estrictas) cada capacidad de negocio vive en su **módulo**, y lo que varios módulos necesitan por igual vive en los proyectos **compartidos** (*shared*). Ante cada pieza de código nueva, el criterio de reparto decide a cuál de los dos lugares pertenece.

## ¿Por qué existe?

Cuando una aplicación crece sin fronteras, cualquier cambio toca veinte sitios. La solución habitual es partirla en módulos, cada uno dueño de un trozo del negocio. Pero en cuanto existen dos módulos aparece la tentación contraria: «esto lo pueden necesitar otros, lo pongo en shared por si acaso». Si se cede con todo, shared engorda hasta ser un cajón de sastre del que dependen todos los módulos, y se vuelve al punto de partida: cualquier cambio afecta a todo, con carpetas más bonitas.

Hace falta un criterio de reparto explícito.

> Piensa en un edificio de apartamentos. Cada módulo es un apartamento: tiene sus muebles, su cocina y su cerradura, y sus dueños lo reforman cuando quieren sin pedir permiso. Shared son las zonas comunes: la escalera, el portal, las tuberías generales. Nadie deja su sofá en el portal «por si otro vecino lo quiere usar», y nadie reforma la escalera cada semana, porque un cambio ahí afecta a todo el edificio.

## ¿Cuándo y para qué se usa?

La decisión aparece cada vez que se crea una clase nueva en un monolito modular: una entidad, un caso de uso, un cliente HTTP, un tipo de respuesta. Se aplica a una solución con varias capacidades de negocio que conviven en un mismo ejecutable y que, a ser posible, evolucionan a ritmos distintos.

El escenario es una tienda online. La solución `Tienda` tiene cuatro módulos (`Catalogo`, `Pedidos`, `Envios`, `Autenticacion`) y un único ejecutable, `Tienda.Api`, que los referencia. Un pedido (#4711) pasa por varios: se comprueba que el cliente puede comprar, se confirma, se reserva el envío.

## Qué es un módulo y qué son los proyectos compartidos

### El módulo

Un **módulo** es un *bounded context* (ver [Domain-Driven Design](../patrones-de-diseno/Domain-Driven-Design.md)): una capacidad de negocio completa con sus **casos de uso**, sus **tablas** y su **ciclo de vida propio** (evoluciona a su ritmo, con sus propios requisitos). Se materializa como una pareja de proyectos, y el dominio vive en una carpeta dentro del proyecto de aplicación:

```text
Tienda.Pedidos.Aplicacion        casos de uso (ConfirmarPedido) y dominio (Pedido, LineaPedido)
Tienda.Pedidos.Infraestructura   repositorios, migraciones, clientes externos de Pedidos
```

Las capas de dentro de cada módulo se explican en [Clean Architecture](Clean-Architecture.md).

### Los tres proyectos compartidos

| Proyecto | Qué contiene | Qué no debe contener |
|---|---|---|
| `Tienda.Compartido.Nucleo` | *SharedKernel* (el «núcleo compartido» de DDD): tipos base de dominio sin dependencias, como `EntidadBase` o `Dinero`. Es lo más estable de la solución | Entidades de un módulo (`Pedido`), reglas de negocio |
| `Tienda.Compartido.Aplicacion` | Contratos entre módulos (interfaces y sus DTO) y tipos de resultado comunes | Casos de uso, implementaciones de los contratos |
| `Tienda.Compartido.Infraestructura` | Fontanería técnica: fábrica de conexiones a la base de datos, ejecución de migraciones, logging | Una gota de negocio: ni consultas de un módulo ni reglas |

## El criterio de reparto

En una frase: **shared guarda lo estable y genérico que ya necesitan dos o más módulos; los módulos guardan lo que cambia con el negocio.**

De ahí sale la **regla del 2**: nada sube a shared por anticipación («seguro que alguien lo usará»). Sube cuando aparece el segundo consumidor real. Hasta entonces, vive en su módulo. Subir algo a shared es una tarde; sacarlo cuando ya dependen tres módulos es una obra.

### Ejemplo: un cliente HTTP que sube cuando aparece el segundo consumidor

Antes, solo `Pedidos` cobra con la pasarela de pago. Todo vive en su módulo:

```text
Tienda.Pedidos.Aplicacion/Pagos/IPasarelaPago.cs                 (contrato)
Tienda.Pedidos.Infraestructura/Pagos/ClientePasarelaPago.cs      (cliente HTTP)
```

Después aparece `Suscripciones`, un módulo nuevo (hipotético, para el ejemplo) que cobra cuotas con la misma pasarela. Es el segundo consumidor real. Ahora el contrato y el cliente suben, porque dos módulos necesitan exactamente lo mismo y no cambia con el negocio de ninguno:

```text
Tienda.Compartido.Aplicacion/Pagos/IPasarelaPago.cs              (contrato)
Tienda.Compartido.Infraestructura/Pagos/ClientePasarelaPago.cs   (cliente HTTP)
```

`Pedidos.Aplicacion` y `Suscripciones.Aplicacion` referencian `Compartido.Aplicacion`; nunca se referencian entre sí. Lo que cada módulo decide con el cobro (qué hacer si se rechaza, cuándo reintentar) sigue en su módulo: shared solo ofrece la llamada.

## Un módulo aunque «todos lo usen»: Autenticacion

Es el error más frecuente. La autenticación tiene casos de uso propios (`IniciarSesion`, cerrar sesión), tablas propias (cuentas, sesiones) y evoluciona con requisitos de negocio (caducidad de sesión, bloqueo de cuentas, doble factor). Eso es la definición de módulo. Que casi todos los demás la necesiten no la convierte en shared: a shared van sus **contratos**.

```csharp
// Tienda.Compartido.Aplicacion — el contrato que otros módulos pueden usar
public record ResumenCuenta(int ClienteId, string Email, bool Activa);

public interface IConsultaCuentas
{
    Task<ResumenCuenta?> ObtenerPorId(int clienteId);
}

// Tienda.Autenticacion.Aplicacion — la implementación, con las tripas del módulo
public class ConsultaCuentas : IConsultaCuentas
{
    public Task<ResumenCuenta?> ObtenerPorId(int clienteId) { /* ... */ }
}

// Tienda.Pedidos.Aplicacion — el consumidor solo conoce el contrato
public class ConfirmarPedido(IConsultaCuentas cuentas)
{
    public async Task<bool> Ejecutar(int pedidoId, int clienteId) =>
        (await cuentas.ObtenerPorId(clienteId))?.Activa == true;
}
```

`ConfirmarPedido` pregunta si la cuenta del cliente de un pedido está activa sin saber que existe un módulo `Autenticacion`. El ejecutable `Tienda.Api` es quien registra `ConsultaCuentas` como implementación de `IConsultaCuentas` (ver [Inversión de Dependencias](Inversion-de-Dependencias.md)). Si `Autenticacion` cambia de motor de sesiones o parte su tabla en dos, `Pedidos` no se entera.

## Los módulos se hablan por contratos, no se referencian

La estructura de proyectos de la solución:

```text
Tienda.Api                          ──► Tienda.Pedidos.Infraestructura
                                    ──► Tienda.Autenticacion.Infraestructura

Tienda.Pedidos.Infraestructura      ──► Tienda.Pedidos.Aplicacion
                                    ──► Tienda.Compartido.Infraestructura
Tienda.Pedidos.Aplicacion           ──► Tienda.Compartido.Aplicacion

Tienda.Autenticacion.Infraestructura ──► Tienda.Autenticacion.Aplicacion
                                     ──► Tienda.Compartido.Infraestructura
Tienda.Autenticacion.Aplicacion      ──► Tienda.Compartido.Aplicacion

Tienda.Compartido.Aplicacion        ──► Tienda.Compartido.Nucleo
```

Lo que importa está en el `.csproj` de `Tienda.Pedidos.Aplicacion`:

```xml
<ItemGroup>
  <!-- ✅ Pedidos depende del contrato compartido -->
  <ProjectReference Include="..\Tienda.Compartido.Aplicacion\Tienda.Compartido.Aplicacion.csproj" />

  <!-- ❌ Pedidos referencia el proyecto de otro módulo: acopla los dos para siempre
  <ProjectReference Include="..\Tienda.Autenticacion.Aplicacion\Tienda.Autenticacion.Aplicacion.csproj" />
  -->
</ItemGroup>
```

Con la segunda referencia, ya no hay dos módulos sino uno grande disfrazado: `Pedidos` compila contra clases internas de `Autenticacion`, no puede cambiar sin recompilar el otro y, con el tiempo, acaba usando lo que no debía.

### Cómo se impide con un test de arquitectura

Quitar la referencia protege hasta que alguien la vuelve a añadir «solo esta vez». Un test de arquitectura convierte la frontera en un fallo de compilación de la integración continua. Se usa NetArchTest igual que en [Regla de Dependencia](Regla-de-Dependencia.md), donde se explica la herramienta; aquí la regla es entre módulos:

```csharp
using NetArchTest.Rules;
using Tienda.Autenticacion.Aplicacion;
using Tienda.Pedidos.Aplicacion;
using Xunit;

public class ModulosTests
{
    [Fact]
    public void Pedidos_no_depende_de_Autenticacion()
    {
        var resultado = Types.InAssembly(typeof(ConfirmarPedido).Assembly)
            .ShouldNot().HaveDependencyOnAny("Tienda.Autenticacion")
            .GetResult();

        Assert.True(resultado.IsSuccessful,
            "Violan la regla: " + string.Join(", ", resultado.FailingTypeNames ?? []));
    }

    [Fact]
    public void Autenticacion_no_depende_de_Pedidos()
    {
        var resultado = Types.InAssembly(typeof(ConsultaCuentas).Assembly)
            .ShouldNot().HaveDependencyOnAny("Tienda.Pedidos")
            .GetResult();

        Assert.True(resultado.IsSuccessful,
            "Violan la regla: " + string.Join(", ", resultado.FailingTypeNames ?? []));
    }
}
```

Con el diseño correcto, los dos tests pasan. Si alguien añade la `ProjectReference` prohibida y crea una clase `Malo` en `Pedidos` que usa `ConsultaCuentas`, el primero falla y nombra al culpable (salida real de `dotnet test`):

```text
ModulosTests.Pedidos_no_depende_de_Autenticacion [FAIL]
  Mensaje de error:
   Violan la regla: Tienda.Pedidos.Aplicacion.Malo
```

Hay una regla por cada pareja de módulos y por cada proyecto del módulo (`Aplicacion` e `Infraestructura`); cuando se añade un módulo, se añaden sus reglas.

## Qué va dónde

| Tipo de código | Destino | Motivo |
|---|---|---|
| Entidad de un módulo (`Pedido`, `LineaPedido`) | Su módulo, dentro de `Aplicacion` | Cambia con el negocio de ese módulo |
| Tipo base genérico (`EntidadBase`, `Dinero`) | `Compartido.Nucleo` | Estable, sin dependencias, lo usan varios |
| Caso de uso (`ConfirmarPedido`, `IniciarSesion`) | **Siempre** su módulo | La lógica de negocio nunca es compartida |
| Cliente HTTP usado por un solo módulo | Ese módulo | Regla del 2: aún no hay segundo consumidor |
| Cliente HTTP usado por dos o más módulos | `Compartido.Infraestructura`, con su contrato en `Compartido.Aplicacion` | Segundo consumidor real |
| Fábrica de conexiones, ejecución de migraciones, logging | `Compartido.Infraestructura` | Fontanería sin negocio |
| Tipo de resultado común a todos los módulos | `Compartido.Aplicacion` (ver [Códigos de Resultado por Capa](Codigos-de-Resultado-por-Capa.md)) | Genérico y estable |
| Contrato para consultar a otro módulo (`IConsultaCuentas`) y sus DTO | `Compartido.Aplicacion` | Es la superficie pública del módulo dueño |
| DTO de un evento entre módulos (`PedidoConfirmado`) | `Compartido.Aplicacion` | Lo conocen quien lo publica y quien lo escucha |

## Señales de alarma y cómo detectarlas

**Shared engordado con lógica de negocio.** Si en `Compartido.*` aparecen `if` de negocio, casos de uso o entidades de un módulo, shared deja de ser zona común: cualquier cambio obliga a repensar todos los módulos a la vez. Se ve en la revisión de código y en una pregunta sencilla: ¿este tipo cambiaría si cambiase una regla de negocio de un solo módulo? Si sí, no es de shared.

**Módulos que se referencian entre sí.** Se detecta de forma mecánica con `dotnet list reference`. Este script, ejecutado en la raíz de las fuentes, lista cada referencia de un módulo hacia un proyecto de otro módulo:

```bash
for m in Pedidos Autenticacion; do
  for p in Tienda.$m.*/; do
    p=${p%/}
    dotnet list $p reference \
      | grep -E "Tienda\.(Pedidos|Autenticacion|Catalogo|Envios)\." \
      | grep -v "Tienda\.$m\." | sed "s|^|$p -> |"
  done
done
```

Con la solución bien dividida no imprime nada. Con la referencia prohibida de la sección anterior:

```text
Tienda.Pedidos.Aplicacion -> ..\Tienda.Autenticacion.Aplicacion\Tienda.Autenticacion.Aplicacion.csproj
```

La salida vacía es lo esperado; cada línea es una frontera rota. La misma pregunta, aplicada a shared, es `dotnet list Tienda.Compartido.Aplicacion reference`: no debe aparecer ningún proyecto de módulo, solo `Tienda.Compartido.Nucleo`.

## El acoplamiento por la base de datos

De nada sirve que `Pedidos` no referencie a `Autenticacion` si su SQL hace un `JOIN` contra la tabla de cuentas:

```sql
-- ❌ Pedidos lee las tripas de Autenticacion
SELECT p.id, c.email
FROM pedidos p
JOIN cuentas c ON c.id = p.cliente_id;
```

Si `Autenticacion` renombra una columna, `Pedidos` se rompe en producción sin que ningún compilador lo avise. Cada módulo debe ser dueño exclusivo de sus tablas, y un esquema de base de datos por módulo lo hace visible:

```csharp
// Tienda.Pedidos.Infraestructura — todas las tablas de Pedidos cuelgan del esquema "pedidos"
public class PedidosDbContext(DbContextOptions<PedidosDbContext> opciones) : DbContext(opciones)
{
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("pedidos");
        modelBuilder.Entity<Pedido>().ToTable("pedidos");   // → pedidos.pedidos
    }
}
```

El permiso de cada esquema se puede restringir al usuario de base de datos de su módulo. Los datos ajenos se piden por el contrato (`IConsultaCuentas`), no por debajo de la mesa. Este fragmento de EF Core no se ha ejecutado en la ficha; la forma de configurar el esquema por defecto está en la [documentación de EF Core](https://learn.microsoft.com/en-us/ef/core/modeling/entity-types).

## Eventos cuando el contrato síncrono acopla demasiado

Un contrato como `IConsultaCuentas` es una **pregunta**: `Pedidos` llama y espera respuesta. Cuando es `Pedidos` quien tiene que **avisar** de algo (el pedido #4711 se ha confirmado, hay que reservar el envío, descontar stock, mandar un correo), llamar a cada interesado hace que `Pedidos` acabe conociéndolos a todos. Un **evento** invierte la relación: `Pedidos` publica el hecho y no sabe quién escucha.

```csharp
// Tienda.Compartido.Aplicacion — el evento y los contratos de publicar y escuchar
public record PedidoConfirmado(int PedidoId, int ClienteId, DateTime ConfirmadoEnUtc);

public interface IManejadorEvento<in TEvento>
{
    Task Manejar(TEvento evento, CancellationToken ct);
}

public interface IPublicadorEventos
{
    Task Publicar<TEvento>(TEvento evento, CancellationToken ct);
}

// Tienda.Pedidos.Aplicacion — publica, sin saber quién escucha
public class ConfirmarPedido(IConsultaCuentas cuentas, IPublicadorEventos eventos)
{
    public async Task<bool> Ejecutar(int pedidoId, int clienteId, CancellationToken ct)
    {
        if ((await cuentas.ObtenerPorId(clienteId))?.Activa != true) return false;
        await eventos.Publicar(new PedidoConfirmado(pedidoId, clienteId, DateTime.UtcNow), ct);
        return true;
    }
}

// Tienda.Envios.Infraestructura — se suscribe a lo que le interesa
public class ReservarEnvio : IManejadorEvento<PedidoConfirmado>
{
    public Task Manejar(PedidoConfirmado evento, CancellationToken ct) { /* reservar envío */ }
}
```

El publicador en proceso, que vive en `Compartido.Infraestructura` por ser fontanería, busca en el contenedor de dependencias todos los manejadores del evento y los invoca uno a uno:

```csharp
public class PublicadorEnProceso(IServiceProvider servicios) : IPublicadorEventos
{
    public async Task Publicar<TEvento>(TEvento evento, CancellationToken ct)
    {
        foreach (var manejador in servicios.GetServices<IManejadorEvento<TEvento>>())
            await manejador.Manejar(evento, ct);
    }
}
```

`GetServices` requiere el paquete `Microsoft.Extensions.DependencyInjection.Abstractions`. Todo ocurre dentro del mismo proceso y la misma petición: si un manejador falla, falla `Publicar`. Tomar decisiones de diseño sobre eventos (qué es un evento de dominio, cuándo se publica, consistencia) se trata en [Domain Events](../patrones-de-diseno/Domain-Events.md).

## Duplicar frente a compartir mal

Que dos módulos tengan clases parecidas no viola DRY (*Don't Repeat Yourself*): DRY aplica al **conocimiento de negocio**, no al código que hoy se parece por casualidad.

`Pedidos` necesita una `Direccion` para facturar (calle, ciudad, código postal, NIF opcional) y `Envios` otra para entregar (calle, ciudad, código postal, franja horaria, instrucciones del repartidor):

```csharp
// Tienda.Pedidos.Aplicacion/Dominio
public record Direccion(string Calle, string Ciudad, string CodigoPostal, string? Nif);

// Tienda.Envios.Aplicacion/Dominio
public record Direccion(string Calle, string Ciudad, string CodigoPostal, string? Instrucciones);
```

Unificarlas en `Compartido.Nucleo` obligaría a las dos a llevar siempre `Nif` e `Instrucciones` y a evolucionar juntas: cada regla nueva de entrega afectaría a la facturación. Cuando `Pedidos` confirma, pasa los datos que `Envios` necesita en el evento o en un DTO de contrato, y `Envios` construye su propia `Direccion`. La duplicación se corrige mañana si resulta ser conocimiento común; el acoplamiento no.

La unificación sí procede si es genuinamente el mismo concepto con las mismas reglas, p. ej. `Dinero` (importe y moneda): ahí no hay un `Dinero` de facturación distinto de otro de envíos.

## Los contratos compartidos son API pública

Cambiar la firma de `IConsultaCuentas` obliga a tocar a la vez todos los módulos que la consumen. Los contratos de `Compartido.Aplicacion` y los tipos de `Compartido.Nucleo` se tratan como la API pública de una librería: la evolución es **aditiva** (añadir un método nuevo, un campo opcional a `ResumenCuenta`) y los cambios incompatibles se hacen en dos pasos (añadir lo nuevo, migrar a los consumidores, retirar lo viejo).

```csharp
// ✅ Aditivo: los consumidores existentes siguen compilando
public record ResumenCuenta(int ClienteId, string Email, bool Activa, string? Idioma = null);

// ❌ Incompatible: rompe a todos los módulos a la vez
public record ResumenCuenta(int Id, string Correo, EstadoCuenta Estado);
```

## Cuándo no partir en módulos

Los módulos tienen un coste: proyectos, contratos, algo de duplicación y disciplina para mantener las fronteras. No siempre compensa.

| Situación | Qué conviene |
|---|---|
| Equipo pequeño (una o dos personas) y un único ritmo de cambio | Un solo proyecto con carpetas por área; partir cuando duela |
| Dominio aún inestable: no está claro dónde acaba `Pedidos` y empieza `Envios` | Esperar: una frontera mal trazada es más cara que ninguna |
| Varias áreas que cambian siempre juntas | Un solo módulo: separarlas añade contratos sin añadir independencia |
| Equipos distintos que se pisan o ritmos de cambio muy dispares | Módulos: es el caso para el que sirven |

Y la división en módulos **no decide el despliegue**: todos los módulos y shared se compilan juntos en `Tienda.Api` y arrancan en un único proceso. Es una frontera de código, no de servidores.

## Buenas prácticas avanzadas

- **Trata los contratos compartidos como una API pública.** Cambiar la firma de `IConsultaCuentas` en `Compartido.Aplicacion` obliga a tocar a la vez todos los módulos que la consumen. Haz que evolucionen de forma aditiva (métodos nuevos, campos opcionales; no renombrar ni cambiar firmas) y piensa dos veces antes de «refactorizar rápido» algo de shared: su onda expansiva es toda la solución.
- **Vigila el acoplamiento por la base de datos igual que el de código.** Que `Pedidos` no referencie `Autenticacion.Aplicacion` no sirve si su SQL hace `JOIN` contra la tabla de cuentas. Cada módulo es dueño exclusivo de sus tablas, con esquemas o prefijos separados para que se vea, y pide los datos ajenos por el contrato.
- **Duplicar es más barato que compartir mal.** Dos módulos con clases parecidas no violan DRY. Si `Envios` y `Pedidos` tienen cada uno su `Direccion` con reglas distintas, unificarla en shared las condena a evolucionar juntas para siempre.
- **Pasa a eventos cuando el contrato síncrono acopla demasiado.** Si `Pedidos` tiene que avisar de cada pedido confirmado a tres módulos, acabará conociendo a todos sus consumidores. Publicar `PedidoConfirmado` invierte la relación: `Pedidos` no sabe quién escucha y cada módulo se suscribe solo a lo que le interesa.
- **Escribe el test de arquitectura al crear el módulo, no cuando ya hay referencias cruzadas.** Una frontera sin test se erosiona con la primera prisa. Añadir las reglas del módulo nuevo es parte de crearlo, y cuesta unos minutos que no cuestan nada después.
- **Revisa los `.csproj` de `Compartido.*` en cada pull request.** Que `Compartido.Aplicacion` referencie un proyecto de módulo, o `Compartido.Nucleo` referencie algo, es el síntoma más temprano de que shared se está torciendo; `dotnet list reference` lo muestra en un segundo.

## Documentación oficial

- [Arquitecturas comunes de aplicaciones web (Microsoft)](https://learn.microsoft.com/en-us/dotnet/architecture/modern-web-apps-azure/common-web-application-architectures) — la sección sobre aplicaciones monolíticas y su organización en capas y proyectos; el punto de partida para ver dónde encaja un monolito modular en .NET.
- [Bounded Context (Martin Fowler)](https://martinfowler.com/bliki/BoundedContext.html) — el artículo breve que explica la idea de dividir un dominio en contextos con su propio modelo; léelo para decidir dónde trazar las fronteras de los módulos.
- [Modular Monolith with DDD (Kamil Grzybek)](https://github.com/kgrzybek/modular-monolith-with-ddd) — un repositorio de referencia en .NET con módulos, contratos entre módulos y tests de arquitectura; útil para ver la estructura completa a escala.

## Recursos didácticos

- [MonolithFirst (Martin Fowler)](https://martinfowler.com/bliki/MonolithFirst.html) — argumento para empezar con un monolito bien dividido antes de plantearse servicios separados; ayuda a decidir cuándo partir y cuándo esperar.

---

*En resumen: los módulos guardan lo que cambia con el negocio y shared solo lo estable y genérico que ya necesitan dos o más módulos; cuando dudes, déjalo en su módulo, que subir a shared siempre estás a tiempo.*
