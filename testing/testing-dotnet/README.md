# Testing en .NET — Guía de metodologías

Guía de testing en .NET para desarrolladoras y desarrolladores con experiencia backend que quieren escribir tests con criterio: qué herramienta usar en cada capa, cómo estructurar los tests y qué prácticas distinguen una suite fiable de una que solo pinta verde.

Cada ficha explica qué es la tecnología o el patrón, por qué existe y cómo se usa, con ejemplos ejecutados sobre un dominio común: una tienda online con pedidos, líneas de pedido y cupones de descuento.

---

## Orden de lectura recomendado

### 1. Fundamentos

El mapa de los tipos de test y las dos herramientas con las que se escribe cualquiera de ellos: el framework y las aserciones.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Tipos de tests](Tipos-de-tests.md) | El mapa general: unitario, integración y end-to-end, y cuándo usar cada uno. |
| 2 | [xUnit](xUnit.md) | El framework sobre el que se escribe todo lo demás: `[Fact]`, `[Theory]`, el modelo de ejecución y la línea de comandos. |
| 3 | [Shouldly](Shouldly.md) | Aserciones legibles, con mensajes de fallo que dicen qué se esperaba y qué llegó. |
| 4 | [Arrange-Act-Assert](Arrange-Act-Assert.md) | La estructura interna de cada test, con el contraste entre un test que prueba tres cosas y uno que prueba una. |

### 2. Compartir recursos caros

Cuando los tests necesitan un host web o una base de datos, arrancarlos por test es inviable: aquí entra el ciclo de vida de xUnit.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 5 | [Fixtures y ciclo de vida](Fixtures-y-ciclo-de-vida.md) | `IClassFixture`, `ICollectionFixture` e `IAsyncLifetime`: la base de los tests de integración. |

### 3. Tests de API e integración

Las dos herramientas que permiten probar la aplicación real: el host en memoria y la base de datos efímera.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 6 | [WebApplicationFactory](WebApplicationFactory.md) | Arranca la API completa en memoria y la ataca por HTTP. |
| 7 | [Testcontainers](Testcontainers.md) | PostgreSQL real y efímero en Docker para probar SQL, esquema y migraciones. |

### 4. Aislamiento y medición

El complemento de los tests de integración: aislar la lógica pura y medir qué queda sin cubrir.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 8 | [NSubstitute](NSubstitute.md) | Dobles de prueba para tests unitarios de lógica de negocio. |
| 9 | [Coverlet](Coverlet.md) | Cobertura de código: encontrar los huecos que ningún test pisa y fijar umbrales. |

---

## Qué ficha consultar según la pregunta

| Si la pregunta es… | Ficha |
|---|---|
| ¿Qué tipo de test escribo para esta capa? | [Tipos de tests](Tipos-de-tests.md) |
| ¿Cómo declaro un test con varios casos de entrada? | [xUnit](xUnit.md) |
| ¿Cómo ordeno el cuerpo de un test? | [Arrange-Act-Assert](Arrange-Act-Assert.md) |
| ¿Cómo comparto un recurso caro entre tests sin que se contaminen? | [Fixtures y ciclo de vida](Fixtures-y-ciclo-de-vida.md) |
| ¿Cómo pruebo un endpoint sin levantar un servidor real? | [WebApplicationFactory](WebApplicationFactory.md) |
| ¿Cómo pruebo contra el motor de base de datos de producción? | [Testcontainers](Testcontainers.md) |
| ¿Cómo aíslo una dependencia externa en un test unitario? | [NSubstitute](NSubstitute.md) |
| ¿Qué código no ejecuta ningún test? | [Coverlet](Coverlet.md) |

---

> Para el ciclo de escribir primero el test, ver [TDD, BDD y SDD](../tdd-bdd-sdd/README.md); para los tests de navegador, [Playwright](../e2e/README.md). Quien viene del frontend tiene en [Vitest](../../desarrollo-web/frontend-react/Vitest.md) el equivalente de xUnit en TypeScript.
