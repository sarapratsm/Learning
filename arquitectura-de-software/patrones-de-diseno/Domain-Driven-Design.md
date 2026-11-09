# Domain-Driven Design

## ¿Qué es?

Domain-Driven Design (DDD) es un enfoque para diseñar software con mucha complejidad de negocio: el **modelo del negocio** se construye junto a quien lo conoce, con su mismo vocabulario, y es lo que ordena las decisiones técnicas. Se compone de un diseño *estratégico* (lenguaje, fronteras entre modelos, dónde invertir) y de un diseño *táctico* (las piezas con las que se escribe cada modelo).

## ¿Por qué existe?

En un sistema grande, la misma palabra significa cosas distintas según quién la use, y el código lo paga de dos maneras:

- **Se traduce a ciegas.** El negocio dice «confirmar el pedido»; el código dice `ProcessOrderData` y `status = 3`. Cada conversación entre negocio y desarrollo exige una traducción, y en esa traducción se pierden reglas.
- **Se fuerza un modelo único.** Una sola clase `Pedido` o `Producto` que debe servir a catálogo, pedidos y envíos acumula campos opcionales y condiciones que solo tienen sentido para una parte de los usos.

DDD acepta que existen varios modelos y le pone fronteras: cada parte de la aplicación (un **contexto delimitado**) tiene su propio modelo, coherente por dentro, escrito en el idioma de quien conoce esa parte del negocio.

> Los departamentos de una empresa: «pedido» para el almacén son bultos que preparar; para contabilidad es una factura pendiente de cobro. Cada departamento tiene razón dentro de su propio contexto. El problema aparece cuando alguien intenta imponer una única definición a todos.

## ¿Cuándo y para qué se usa?

Compensa cuando las reglas del negocio son numerosas y cambiantes, y varias partes del sistema hablan de «lo mismo» con matices distintos: una tienda online con catálogo, pedidos, envíos y promociones, un sistema de seguros, una logística. Se aplica por contexto, no a toda la solución: puede haber un contexto con modelo rico y otro de simple CRUD en la misma aplicación. Las condiciones en que no compensa están en [Cuándo no compensa](#cuándo-no-compensa).

## Lenguaje ubicuo

El **lenguaje ubicuo** es el vocabulario que comparten quienes programan y quienes conocen el negocio, **dentro de un contexto**. Se usa en las reuniones, en la documentación y en el código, sin traducción.

```csharp
// ❌ Vocabulario técnico: nadie del negocio reconoce esto
public class OrderManager
{
    public void ProcessOrderData(int orderId)
    {
        var order = _repo.Get(orderId);
        if (order.Items.Count > 0) order.status = 3;
    }
}

// ✅ Vocabulario del negocio: se puede leer en voz alta delante de quien gestiona pedidos
pedido.Confirmar(ahora);
if (pedido.Estado == EstadoPedido.Confirmado) { /* ... */ }
```

El nombre sale de una conversación como esta:

| Quien conoce el negocio dice | El código no debe decir | El código dice |
|---|---|---|
| «Cuando el cliente confirma el pedido, ya no puede añadir productos» | `order.status = 3; order.locked = true` | `pedido.Confirmar(ahora)`; `AñadirLinea` falla si el estado no es `Borrador` |
| «Un pedido pagado ya no se cancela; se devuelve» | `if (order.paid) throw ...` dentro de un servicio | `pedido.Cancelar()` lanza `ReglaDeDominioException`; la devolución es otra operación |
| «Un pedido en borrador» | `status = 0` | `EstadoPedido.Borrador` |

Si en la conversación aparece un término que el código no tiene (por ejemplo, «devolución»), falta una clase o un método. Si el código tiene un término que el negocio no usa (`OrderManager`, `ProcessData`), sobra o está mal nombrado. Cuando una persona de negocio corrige un nombre, el cambio se hace en el código y no solo en la documentación.

## Contextos delimitados

Un **contexto delimitado** (*bounded context*) es la frontera dentro de la cual un modelo y su lenguaje son válidos. Fuera de ella, la misma palabra puede significar otra cosa. En la tienda, tres contextos hablan del «pedido» y del «producto»:

| Contexto | Qué es un «pedido» o un «producto» ahí | Datos que importan |
|---|---|---|
| `Catalogo` | Producto: lo que se muestra y se vende | precio, descripción, imágenes |
| `Pedidos` | Pedido: la compra de una persona | líneas, estado, total |
| `Envios` | Pedido: lo que hay que entregar | bulto, dirección, transportista |

El mismo pedido #4711 se modela distinto en cada contexto, porque cada uno resuelve un problema distinto:

```csharp
namespace Tienda.Pedidos.Dominio;

// Pedidos: reglas de la compra (líneas, estado, total)
public sealed class Pedido
{
    private readonly List<LineaPedido> _lineas = [];

    public IdPedido Id { get; }
    public EstadoPedido Estado { get; private set; }
    public IReadOnlyList<LineaPedido> Lineas => _lineas.AsReadOnly();

    public void Confirmar(DateTimeOffset ahora) { /* sin líneas no se confirma */ }
    public void Cancelar() { /* un pedido pagado no se cancela */ }
}
```

```csharp
namespace Tienda.Envios.Dominio;

// Envios: reglas de la entrega (qué bultos, adónde, con quién)
public sealed class Pedido
{
    public IdPedido Id { get; }
    public Direccion Destino { get; }
    public IReadOnlyList<Bulto> Bultos { get; }
    public Transportista Transportista { get; private set; }

    public void AsignarTransportista(Transportista transportista) { /* ... */ }
    public void MarcarEntregado(DateTimeOffset ahora) { /* ... */ }
}
```

Son dos clases con el mismo nombre en dos espacios de nombres distintos, y no es duplicación: `Envios` no sabe qué es una línea ni cuánto cuesta algo, y `Pedidos` no sabe qué transportista lleva el paquete. Cada contexto cambia por sus propios motivos.

### Mapa de contextos

El **mapa de contextos** (*context map*) dice qué contextos existen y cómo se relacionan. Un contexto es **aguas arriba** (*upstream*) cuando otro depende de lo que publica; el que depende es **aguas abajo** (*downstream*).

```text
 Catalogo ──── precio y nombre del producto ────▶ Pedidos
 (aguas arriba)        contrato síncrono          (aguas abajo)

 Pedidos ───── evento PedidoConfirmado ─────────▶ Envios
 (aguas arriba)   { IdPedido, IdCliente, líneas }  (aguas abajo)
                                  │
                                  └─ Envios traduce el evento a su propio modelo
                                     de pedido (capa anticorrupción)
```

- `Catalogo` → `Pedidos`: `Pedidos` pregunta por el precio y el nombre vigentes de un producto al añadir una línea, y guarda en la línea el precio de ese momento (un cambio posterior en el catálogo no altera pedidos ya hechos). El contrato es una interfaz con un DTO mínimo (id, nombre, precio).
- `Pedidos` → `Envios`: `Pedidos` publica el hecho `PedidoConfirmado` con lo que `Envios` necesita; `Envios` decide cuándo y cómo reaccionar. Cómo se publica y se maneja está en la sección de eventos de [Módulos vs Shared](../clean-architecture/Modulos-vs-Shared.md).

Las relaciones entre contextos se nombran con un vocabulario fijo. Estas cuatro son las más habituales:

| Relación | Qué significa | Ejemplo en la tienda |
|---|---|---|
| **Cliente-proveedor** (*customer-supplier*) | El contexto aguas arriba (proveedor) tiene en cuenta las necesidades del aguas abajo (cliente) al planificar su trabajo; el cliente puede pedir cambios en el contrato | `Catalogo` añade al contrato el campo que `Pedidos` pide |
| **Conformista** (*conformist*) | El aguas abajo adopta tal cual el modelo del aguas arriba, porque este no va a adaptarse | `Pedidos` usa el modelo de producto de un proveedor externo de catálogo sin traducirlo |
| **Capa anticorrupción** (*anticorruption layer*) | El aguas abajo traduce el modelo ajeno al suyo en una capa propia, para que el ajeno no se filtre en su dominio | `Envios` convierte `PedidoConfirmado` en su `Pedido` de entrega, o traduce la API de un transportista |
| **Núcleo compartido** (*shared kernel*) | Dos contextos comparten un subconjunto pequeño del modelo y lo cambian solo de común acuerdo | `Dinero` y los ids tipados en un proyecto compartido |

La capa anticorrupción es la opción por defecto ante un modelo ajeno que no se controla (un sistema heredado, una API de terceros): cuesta una clase de traducción y evita que el vocabulario ajeno se cuele en el dominio.

## Dominio nuclear, de apoyo y genérico

No todas las partes del negocio merecen el mismo esfuerzo de modelado. DDD las clasifica en tres tipos de subdominio:

| Tipo | Qué es | Qué se hace | En la tienda (ejemplo) |
|---|---|---|---|
| **Nuclear** (*core*) | Lo que diferencia al negocio de la competencia | Se construye a medida, con el mejor equipo y modelo rico | Las reglas de `Pedidos` y las promociones, si ahí está la ventaja de la tienda |
| **De apoyo** (*supporting*) | Necesario, pero no diferencia; es específico del negocio | Se construye, con modelo sencillo | `Catalogo` y `Envios` |
| **Genérico** (*generic*) | Resuelto igual en cualquier empresa | Se compra o se adopta: servicio, librería, producto | `Autenticacion`, la pasarela de pago, el envío de correo |

La clasificación depende de la estrategia de cada negocio: para una tienda cuya ventaja es la logística, `Envios` sería el núcleo. Sirve para decidir **dónde gastar el modelado**: un modelo rico con agregados y eventos en el núcleo; un CRUD correcto en el apoyo; nada propio en lo genérico, donde construir es gastar tiempo en algo que otra empresa ya mantiene mejor.

## Las piezas tácticas

Dentro de cada contexto, DDD ofrece estos bloques para escribir el modelo. Cada uno tiene su propia ficha o se desarrolla en otra parte:

| Pieza | Qué es | Dónde se desarrolla |
|---|---|---|
| **Objeto de valor** | Dato inmutable que se define por su valor (`Dinero`, `Email`) | [Value Objects](Value-Objects.md) |
| **Entidad** | Objeto que se distingue por su identidad (el pedido #4711) | [Entidades y Agregados](Entidades-y-Agregados.md) |
| **Agregado** | Grupo de entidades con una raíz y una frontera de consistencia (`Pedido` con sus `LineaPedido`) | [Entidades y Agregados](Entidades-y-Agregados.md) |
| **Repositorio** | Colección de agregados que se carga y se guarda como si estuviera en memoria | [Repositorios](Repositorios.md) |
| **Servicio de dominio** | Regla de negocio que no encaja en una sola entidad (por ejemplo, calcular un descuento que depende del pedido y del cliente) y no guarda estado | [Capa de Dominio](../clean-architecture/Capa-de-Dominio.md) |
| **Evento de dominio** | Hecho ya ocurrido que otros pueden reaccionar (`PedidoConfirmado`) | [Domain Events](Domain-Events.md) |
| **Fábrica** | Centraliza la creación de objetos complejos o con reglas (`Pedido.Crear`) | [Factory](Factory.md) |

En esta colección la interfaz del repositorio (`IRepositorioPedidos`) vive en `Tienda.Aplicacion` y no en el dominio, como pide el DDD clásico. Es equivalente porque el dominio sigue sin depender de nada y la interfaz solo cambia de carpeta; el motivo está en [Inversión de Dependencias](../clean-architecture/Inversion-de-Dependencias.md).

## Encaje con Clean Architecture

Responden a preguntas distintas. DDD dice **qué** poner en el centro: un modelo rico con el lenguaje del negocio. Clean Architecture dice **dónde** ponerlo y cómo protegerlo: las capas y la [regla de dependencia](../clean-architecture/Regla-de-Dependencia.md). El modelo de DDD es lo que vive en la [capa de dominio](../clean-architecture/Capa-de-Dominio.md).

La correspondencia con la estructura de proyectos es directa: **un contexto delimitado se materializa como un módulo**, con sus casos de uso, sus tablas y su ciclo de vida propios (ver [Módulos vs Shared](../clean-architecture/Modulos-vs-Shared.md)).

```text
Tienda.Catalogo.*      contexto Catalogo
Tienda.Pedidos.*       contexto Pedidos   (Pedido, LineaPedido, ConfirmarPedido)
Tienda.Envios.*        contexto Envios    (Pedido de entrega, Bulto)
Tienda.Compartido.*    núcleo compartido y contratos entre contextos
```

Las relaciones del mapa de contextos se convierten en reglas de referencias: un módulo no referencia a otro, se hablan por contratos y eventos.

## Cuándo no compensa

| Situación | Por qué DDD sobra | Alternativa |
|---|---|---|
| CRUD: el sistema guarda y muestra datos con pocas reglas | No hay invariantes que proteger ni vocabulario que afinar; el modelo rico es ceremonia | Capa de acceso a datos directa, formularios y validaciones |
| El equipo no tiene acceso a quien conoce el negocio | El lenguaje ubicuo sale de esa conversación; sin ella se inventa un vocabulario y se consolida un malentendido | Resolver primero el acceso; mientras tanto, modelo simple y reversible |
| Dominio simple o de vida corta (una herramienta interna, un prototipo) | El coste de acordar fronteras y lenguaje no se amortiza | Estructura en capas sin diseño estratégico |
| Subdominio genérico (autenticación, pago, correo) | Otra empresa ya lo resuelve y lo mantiene | Comprar o adoptar un servicio, detrás de una interfaz propia |
| Partes de la aplicación con complejidad muy desigual | Aplicar el mismo rigor a todo ralentiza lo que no lo necesita | DDD en el núcleo; CRUD en el resto, en la misma solución |

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| Hay entidades, repositorios y agregados, pero el negocio no reconoce ningún nombre del código | Se usaron solo las piezas tácticas sin construir el lenguaje ubicuo con quien conoce el negocio |
| Una clase `Cliente` o `Producto` con quince campos, la mitad nulos según quién la use | Un modelo único para toda la empresa en lugar de un modelo por contexto |
| Cambiar una tabla en `Pedidos` rompe consultas de `Envios` | Los contextos comparten tablas: la base de datos es un contrato implícito que nadie versiona |
| Un contexto referencia clases internas de otro y no compila sin él | Faltan contratos entre contextos: son un módulo grande disfrazado |
| Cada operación sobre un pedido bloquea o carga cientos de objetos; las transacciones chocan | Agregado enorme: se metió en él todo lo relacionado en lugar de lo que debe ser consistente a la vez |
| Las clases de dominio son propiedades con `get; set;` y la lógica vive en servicios | Modelo anémico: se adoptó el vocabulario sin el comportamiento |
| Cada reunión con el negocio redefine los nombres y nadie sabe cuál manda | No se delimitó el contexto: un mismo término se usa con dos significados en el mismo modelo |

## Buenas prácticas avanzadas

- **Dibuja el mapa de contextos antes que las clases.** Identificar qué contextos existen y cuál es aguas arriba evita que un `Cliente` acabe con campos que solo tienen sentido en la mitad de los usos.
- **Duplica el nombre, no el modelo compartido.** Reutilizar una única clase `Pedido` en `Pedidos` y `Envios` «para no repetir» acopla contextos que deben evolucionar por separado. Lo único que se comparte es lo mínimo estable (`Dinero`, ids tipados) y los contratos.
- **Entre contextos se referencia por id.** `Envios` guarda un `IdPedido`, no un objeto `Pedido` de otro contexto: así ninguno carga el modelo del otro.
- **Cada contexto es dueño de sus tablas.** Un contexto no lee ni escribe las tablas de otro; si necesita sus datos, los pide por contrato o los recibe por evento. Es la comprobación más barata de que la frontera es real.
- **Pon una capa anticorrupción ante todo modelo que no controlas.** Sistema heredado, API de un transportista o de una pasarela: la traducción vive en un sitio, y el dominio solo ve sus propios términos.
- **Concentra el modelado donde está la ventaja.** Antes de aplicar el modelo táctico completo a un contexto, pregunta si es núcleo, apoyo o genérico; la respuesta fija cuánto invertir.
- **Usa el diseño estratégico completo solo en negocios complejos.** El *event storming* (taller en el que se modelan los eventos de negocio con notas adhesivas) y el mapa de contextos formal rinden en dominios grandes con varios equipos; en una aplicación pequeña con un único contexto claro son coste sin retorno.

## Documentación oficial

- [*Domain-Driven Design Reference*](https://www.domainlanguage.com/ddd/reference/): resumen de Eric Evans (2015) con las definiciones de lenguaje ubicuo, contexto delimitado, mapa de contextos y sus relaciones (cliente-proveedor, conformista, capa anticorrupción, núcleo compartido). Útil para fijar el significado exacto de cada término.
- [Microservicio orientado a DDD (Microsoft Learn)](https://learn.microsoft.com/en-us/dotnet/architecture/microservices/microservice-ddd-cqrs-patterns/ddd-oriented-microservice): cómo organizar un servicio .NET con capas y modelo de dominio. Útil al bajar la estrategia a proyectos.
- [Análisis de dominio para microservicios (Azure Architecture Center)](https://learn.microsoft.com/en-us/azure/architecture/microservices/model/domain-analysis): paso de eventos y contextos a servicios. Útil para decidir fronteras.

## Recursos didácticos

El libro de referencia es *Domain-Driven Design: Tackling Complexity in the Heart of Software* (Eric Evans, 2003), conocido como «el libro azul»: las primeras partes (lenguaje, modelo, contextos) son las que más valor dan a quien empieza.

---

*En resumen: DDD acuerda con el negocio un lenguaje, le pone fronteras a cada modelo y concentra el esfuerzo donde está la ventaja del negocio.*
