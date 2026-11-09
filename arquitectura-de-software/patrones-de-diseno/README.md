# Patrones de diseño — Guía de tecnologías

Guías sobre los patrones que aparecen con más frecuencia al modelar el dominio de una aplicación de negocio: primero las piezas de **Domain-Driven Design** (DDD), después una selección de patrones de diseño clásicos (GoF) y, por último, el patrón que comunica los fallos esperados como valores. Están pensadas para perfiles backend junior-medio que quieren saber qué patrón aplicar, cómo se escribe en C# y cuándo no merece la pena.

Todas comparten el mismo ejemplo: una **tienda online** con el pedido **#4711** y los proyectos `Tienda.Dominio`, `Tienda.Aplicacion`, `Tienda.Infraestructura` y `Tienda.Api`. Esta colección explica **con qué patrones** se modela el contenido de las capas; la colección [Clean Architecture](../clean-architecture/README.md) explica **en qué capa** vive cada cosa y por qué las dependencias solo apuntan hacia dentro.

---

## Orden de lectura recomendado

### 1. Domain-Driven Design: la visión general y sus piezas

El enfoque general y los bloques con los que se construye un modelo de dominio rico.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Domain-Driven Design](Domain-Driven-Design.md) | El mapa general: lenguaje ubicuo, contextos delimitados y cómo encaja con Clean Architecture. Empieza por aquí. |
| 2 | [Value Objects](Value-Objects.md) | La pieza más pequeña: datos inmutables definidos por su valor, no por una identidad. |
| 3 | [Entidades y Agregados](Entidades-y-Agregados.md) | La pieza con identidad, y cómo se agrupan varias bajo una raíz que protege sus reglas conjuntas. |
| 4 | [Repositorios](Repositorios.md) | Cómo el dominio carga y guarda sus agregados sin conocer la tecnología de persistencia. |
| 5 | [Domain Events](Domain-Events.md) | Cómo un agregado comunica que algo ha pasado, sin acoplarse a quien reacciona. |

### 2. Patrones de diseño clásicos (GoF)

Patrones de propósito general que aparecen al construir el dominio y sus alrededores.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 6 | [Factory](Factory.md) | Cómo centralizar y proteger la creación de objetos con reglas propias. |
| 7 | [Strategy](Strategy.md) | Cómo intercambiar un algoritmo (cálculo, validación, ordenación) sin `switch` gigantes. |
| 8 | [Decorator](Decorator.md) | Cómo añadir capacidades (caché, logging, reintentos) envolviendo un objeto sin tocar su implementación. |
| 9 | [Mediator](Mediator.md) | Cómo desacoplar a quien pide una acción de quien la ejecuta, hablando siempre a través de un mediador. |
| 10 | [MediatR](MediatR.md) | El patrón Mediator en .NET: CQRS en proceso, comunicación entre módulos y pipelines de comportamiento. Se lee después de Mediator. |

### 3. Comunicar el resultado de una operación

Un patrón que aparece junto a los anteriores al diseñar cómo responden los casos de uso.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 11 | [Result Pattern](Result-Pattern.md) | Cómo comunicar un fallo esperado del negocio como valor de retorno, en vez de con una excepción. |

---

## Qué patrón resuelve cada problema

| Problema | Patrón |
|---|---|
| El mismo término significa cosas distintas en partes distintas del sistema | [Domain-Driven Design](Domain-Driven-Design.md) (contextos delimitados) |
| `decimal` y `string` sueltos que se pueden combinar mal | [Value Objects](Value-Objects.md) |
| Código externo rompe las reglas que unen varias clases | [Entidades y Agregados](Entidades-y-Agregados.md) |
| El dominio conoce SQL, el ORM o la red | [Repositorios](Repositorios.md) |
| Otras partes del sistema tienen que reaccionar a un hecho, sin que el agregado las conozca | [Domain Events](Domain-Events.md) |
| La construcción de un objeto tiene reglas o varias variantes | [Factory](Factory.md) |
| Un `switch` crece con cada variante de un algoritmo | [Strategy](Strategy.md) |
| Hay que añadir caché, logging o reintentos sin tocar la clase | [Decorator](Decorator.md) |
| Quien pide una acción conoce demasiado a quien la ejecuta | [Mediator](Mediator.md), [MediatR](MediatR.md) |
| Un fallo del negocio se comunica con excepciones y nadie las captura | [Result Pattern](Result-Pattern.md) |

## Dónde vive cada patrón en las capas

Con el ejemplo de la tienda. Las capas se explican en [Clean Architecture](../clean-architecture/Clean-Architecture.md).

| Patrón | Dónde vive | Ejemplo |
|---|---|---|
| Value Object | `Tienda.Dominio` | `Dinero`, `Email` |
| Entidad y agregado | `Tienda.Dominio` | `Pedido` (raíz) con sus `LineaPedido` |
| Fábrica | `Tienda.Dominio` (fábrica de la entidad) o `Tienda.Infraestructura` (elige una implementación) | `Pedido.Crear(...)` |
| Domain Event | Se define en `Tienda.Dominio`; los manejadores, en `Tienda.Aplicacion` | `PedidoConfirmado` |
| Repositorio | El puerto, en `Tienda.Aplicacion`; la implementación, en `Tienda.Infraestructura` | `IRepositorioPedidos` |
| Strategy | Donde viva la regla que varía | Cálculo de gastos de envío |
| Decorator | Normalmente `Tienda.Infraestructura`, o `Tienda.Aplicacion` para lo transversal de casos de uso | Caché sobre `IRepositorioPedidos` |
| Mediator / MediatR | `Tienda.Aplicacion` | Envío de `ConfirmarPedido` |
| Result Pattern | `Tienda.Aplicacion` | `ConfirmarPedidoResultado` |

---

> Antes de esta colección conviene conocer cómo se organizan las capas: [Capa de Dominio](../clean-architecture/Capa-de-Dominio.md), [Casos de Uso](../clean-architecture/Casos-de-Uso.md) y [Puertos y Adaptadores](../clean-architecture/Puertos-y-Adaptadores.md).
