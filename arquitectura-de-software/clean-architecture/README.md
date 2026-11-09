# Clean Architecture — Guía de tecnologías

Guías sobre **Clean Architecture**: cómo organizar el código de una aplicación de negocio para que sea fácil de mantener, probar y cambiar. Cubren desde la idea general y sus dos principios hasta cada capa por separado, las fronteras entre capas y el reparto del código cuando la aplicación se divide en módulos. Están pensadas para perfiles backend junior-medio que programan a diario y quieren decidir bien dónde va cada pieza.

Todas las guías comparten el mismo ejemplo: una **tienda online** con el pedido **#4711**, organizada en los proyectos `Tienda.Dominio`, `Tienda.Aplicacion`, `Tienda.Infraestructura` y `Tienda.Api`. El código es C# / .NET, pero los principios valen para cualquier lenguaje con interfaces.

---

## Orden de lectura recomendado

### 1. La idea y sus reglas

Qué propone Clean Architecture y los dos principios que la sostienen.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Clean Architecture](Clean-Architecture.md) | El mapa general: las capas, qué vive en cada una y cuándo compensa. Empieza por aquí. |
| 2 | [Regla de Dependencia](Regla-de-Dependencia.md) | El principio central: las dependencias de código solo apuntan hacia dentro, y cómo hacer que el compilador lo vigile. |
| 3 | [Inversión de Dependencias](Inversion-de-Dependencias.md) | El mecanismo que permite cumplir la regla cuando el centro necesita algo externo. |

### 2. Las capas, de dentro hacia fuera

El orden en que conviene diseñarlas: del corazón estable al borde cambiante.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 4 | [Capa de Dominio](Capa-de-Dominio.md) | El centro: entidades, objetos de valor y reglas de negocio puras. |
| 5 | [Casos de Uso](Casos-de-Uso.md) | Cómo se orquesta cada acción de la aplicación alrededor del dominio. |
| 6 | [Puertos y Adaptadores](Puertos-y-Adaptadores.md) | El vocabulario de las fronteras: cómo entra y sale la información del centro. |
| 7 | [Capa de Infraestructura](Capa-de-Infraestructura.md) | El borde técnico: base de datos, servicios externos y demás detalles reemplazables. |
| 8 | [Códigos de Resultado por Capa](Codigos-de-Resultado-por-Capa.md) | En qué capa vive el enum que dice cómo terminó una operación, y por qué. |

### 3. Organizar el código a lo grande

Con las capas claras, queda la pregunta del día a día en un monolito modular: dónde va cada pieza nueva.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 9 | [Módulos vs Shared](Modulos-vs-Shared.md) | El criterio para decidir si el código nuevo va a un módulo propio o a los proyectos compartidos. |

---

## Dónde vive cada pieza

Referencia rápida con el ejemplo de la tienda. La columna «Referencia a» es lo que el proyecto puede conocer; nunca al revés.

| Pieza | Proyecto | Referencia a | Ficha |
|---|---|---|---|
| `Pedido`, `LineaPedido`, `Dinero`, `Email` | `Tienda.Dominio` | nada | [Capa de Dominio](Capa-de-Dominio.md) |
| `ConfirmarPedido`, `CancelarPedido` | `Tienda.Aplicacion` | `Tienda.Dominio` | [Casos de Uso](Casos-de-Uso.md) |
| `IRepositorioPedidos`, `IPasarelaPago`, `INotificador` (los puertos) | `Tienda.Aplicacion` | `Tienda.Dominio` | [Puertos y Adaptadores](Puertos-y-Adaptadores.md) |
| Enum de resultado (`ConfirmarPedidoResultado`) | `Tienda.Aplicacion` | `Tienda.Dominio` | [Códigos de Resultado por Capa](Codigos-de-Resultado-por-Capa.md) |
| `RepositorioPedidosSql`, `PasarelaPagoStripe`, `NotificadorEmail` (los adaptadores de salida) | `Tienda.Infraestructura` | `Tienda.Aplicacion` | [Capa de Infraestructura](Capa-de-Infraestructura.md) |
| Controladores, traducción a HTTP, registro de servicios | `Tienda.Api` | los tres anteriores | [Regla de Dependencia](Regla-de-Dependencia.md), [Inversión de Dependencias](Inversion-de-Dependencias.md) |

## Preguntas que resuelve cada ficha

| Pregunta | Ficha |
|---|---|
| ¿Merece la pena aplicar capas en este proyecto? | [Clean Architecture](Clean-Architecture.md) |
| ¿Puede esta clase referenciar aquel proyecto? | [Regla de Dependencia](Regla-de-Dependencia.md) |
| ¿Cómo uso un servicio externo sin que el negocio lo conozca? | [Inversión de Dependencias](Inversion-de-Dependencias.md) |
| ¿Dónde pongo una regla de negocio? | [Capa de Dominio](Capa-de-Dominio.md) |
| ¿Dónde pongo el «leer, confirmar, guardar»? | [Casos de Uso](Casos-de-Uso.md) |
| ¿Esto es un puerto o un adaptador? ¿De entrada o de salida? | [Puertos y Adaptadores](Puertos-y-Adaptadores.md) |
| ¿Dónde se traducen las excepciones del proveedor? | [Capa de Infraestructura](Capa-de-Infraestructura.md) |
| ¿Dónde declaro el enum `PagoRechazado`? | [Códigos de Resultado por Capa](Codigos-de-Resultado-por-Capa.md) |
| ¿Este código va a un módulo o a shared? | [Módulos vs Shared](Modulos-vs-Shared.md) |

---

> Guías relacionadas: [Patrones de diseño](../patrones-de-diseno/README.md) (Repositorios, Result Pattern, Value Objects, MediatR) y [De C# WPF a C# para web](../../desarrollo-web/de-wpf-a-web/README.md).
