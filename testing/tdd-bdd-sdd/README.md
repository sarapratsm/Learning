# TDD, BDD y SDD — Guía de metodologías

Tres formas de usar las pruebas y las especificaciones para decidir qué código escribir, y no solo para comprobarlo después: **TDD** (desarrollo guiado por pruebas), **BDD** (desarrollo guiado por comportamiento) y **SDD** (desarrollo guiado por especificación). Cada ficha es una guía completa con sesiones guiadas, tablas de decisión y errores frecuentes.

Todas comparten escenario: una tienda online en C#/.NET con un carrito (`Cart`) y la regla de «cupón de descuento» (`SAVE10`: 10 % sobre el subtotal, no acumulable, con caducidad y subtotal mínimo de 50,00). Los tests usan xUnit, Shouldly y NSubstitute, explicados en [Testing en .NET](../testing-dotnet/README.md).

---

## Orden de lectura recomendado

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [TDD](TDD.md) | El ciclo rojo-verde-refactor sobre el cupón, de la primera prueba que falla al diseño resultante. Es la base de las otras dos. |
| 2 | [BDD](BDD.md) | Cómo llevar la conversación con negocio a escenarios Gherkin ejecutables con Reqnroll, y cómo encajan sobre el ciclo de TDD. |
| 3 | [SDD](SDD.md) | La especificación como artefacto central: su anatomía, el contrato OpenAPI, la trazabilidad hasta los tests y el trabajo con agentes de IA. |

---

## Cuál aplicar

| | TDD | BDD | SDD |
|---|---|---|---|
| Artefacto central | Test unitario | Escenario Gherkin | Documento de especificación y contrato |
| Quién participa | Quien programa | Negocio, QA y desarrollo | Quien decide el alcance y quien implementa |
| Pregunta que responde | ¿Hace mi código lo que quiero y está bien diseñado? | ¿Entendemos todos lo mismo por «hecho»? | ¿Qué hay que construir exactamente, antes de construirlo? |
| Se aplica mejor a | Lógica de dominio y reglas de cálculo | Comportamiento visible para negocio | Cambios que cruzan varios ficheros, equipos o contratos |

Se combinan en capas: el criterio de aceptación de la especificación se convierte en escenario BDD, y ese escenario se implementa con ciclos de TDD. [SDD](SDD.md) desarrolla esa trazabilidad en una tabla.

---

## Otras guías relacionadas

- [Desarrollo dirigido por especificación con agentes](../../ia/ingenieria-con-llms/Desarrollo-Dirigido-por-Especificacion.md): el flujo práctico de SDD con un agente de codificación.
- [Tipos de tests](../testing-dotnet/Tipos-de-tests.md): la pirámide de tests en la que se sitúan los tres enfoques.
