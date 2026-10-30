# SDD (Spec-Driven Development)

## ¿Qué es?

SDD es una forma de desarrollar en la que **la especificación escrita es el artefacto central**: primero se acuerda, por escrito y de forma verificable, qué debe hacer el sistema; después se implementa, se prueba y se revisa contra ese documento. La especificación puede ser prosa estructurada (requisitos y criterios de aceptación), un contrato máquina-legible (un documento OpenAPI) o una mezcla de ambos.

La sigla es ambigua. Conviene distinguir sus sentidos:

| Sentido | Significado | Dónde se usa |
|---|---|---|
| **Spec-Driven Development** (el de esta ficha) | La especificación guía la implementación, sea humana o de un agente de IA | Equipos que trabajan con agentes de codificación; herramientas como GitHub Spec Kit, Kiro u OpenSpec |
| **Contract-first / API-first** | El contrato de una interfaz (OpenAPI, gRPC, esquemas) se escribe antes que el código y manda sobre él | Integración entre servicios y equipos desde hace años |
| **Diseño guiado por especificación formal** | La especificación se escribe en un lenguaje formal (TLA+, Z, Alloy) y se verifica matemáticamente | Sistemas críticos: protocolos distribuidos, aeronáutica |

Los tres comparten la idea de fondo (especificar antes y comprobar contra la especificación) y difieren en el rigor del lenguaje y en quién consume el documento. Esta ficha trata el primer sentido y, dentro de él, el contrato HTTP (segundo sentido) por ser el que más se encuentra en un backend .NET. Los métodos formales quedan fuera.

## ¿Por qué existe?

Porque la mayoría de los defectos caros no son errores de código, sino de **entendimiento**: el código hace exactamente lo que su autor entendió, y lo entendido no era lo pedido. Esos desajustes salen a la luz tarde: en la revisión del PR, en QA o en producción.

Tomemos la regla del cupón de descuento de una tienda online. Alguien pide: «que los clientes puedan aplicar un cupón». Tres personas distintas pueden implementar tres cosas razonables:

- El cupón `SAVE10` se calcula sobre el subtotal, o sobre subtotal más envío.
- Un segundo cupón sustituye al primero, se suma o se rechaza.
- Un cupón caducado devuelve un error, o se ignora en silencio y el pedido sigue.

Ninguna de las tres es un bug de código. Son tres decisiones de negocio que nadie tomó explícitamente. Una especificación obliga a tomarlas **cuando todavía cuesta un párrafo corregirlas**.

La motivación se ha reforzado con los agentes de IA: un agente implementa en minutos lo que antes costaba una tarde, de modo que el trabajo caro pasa a ser decidir qué se construye y comprobar que lo construido es lo decidido. El flujo práctico con un agente (explorar, especificar, planificar, implementar, verificar) está en [Desarrollo dirigido por especificación](../../ia/ingenieria-con-llms/Desarrollo-Dirigido-por-Especificacion.md). Esta ficha cubre el concepto general, cómo se escribe una buena especificación y cómo se mantiene viva.

> Si ya conoces los tests, piensa en la especificación como el «qué» y en los tests como el «cómo se demuestra». Si conoces OpenAPI, piensa en SDD como llevar esa misma disciplina (escribir el contrato primero y comprobar contra él) de la firma HTTP a todo el comportamiento.

## ¿Cuándo y para qué se usa?

- **Funcionalidades con reglas de negocio**: cupones, impuestos, devoluciones, estados de un pedido. Hay varias respuestas razonables y alguien debe elegir.
- **Interfaces entre equipos o sistemas**: un endpoint que consumirá otro equipo o una app móvil. El contrato es lo único que ambos lados comparten.
- **Trabajo delegado a un agente de IA** o a otra persona que no puede preguntar en cada duda.
- **Cambios que se revisan en equipo**: la especificación convierte la revisión de «¿me gusta este código?» en «¿cumple lo acordado?».

El ejemplo conductor de la ficha es una **tienda online en C#/.NET** con carrito, productos y la regla «cupón de descuento»: `SAVE10` aplica un 10 % sobre el subtotal, no es acumulable con otros cupones, caduca y exige un importe mínimo. El pedido que seguiremos es el **#4711**, con un subtotal de 149,90 EUR. La colección tiene dos fichas hermanas que atacan el mismo ejemplo desde otro ángulo: [TDD](TDD.md) y [BDD](BDD.md).

---

## Los tres niveles de rigor

No todo SDD usa la especificación igual. Böckeler (Thoughtworks), en un artículo publicado en martinfowler.com el 15 de octubre de 2025 que compara herramientas de SDD, distingue tres niveles según qué papel conserva la especificación con el tiempo:

| Nivel | Qué se hace con la especificación | Qué pasa después de la tarea |
|---|---|---|
| **Spec-first** | Se escribe primero y se usa para guiar la tarea en curso | Puede descartarse: era un andamio |
| **Spec-anchored** | Se escribe primero y se **mantiene** después | Sigue guiando la evolución y el mantenimiento de la funcionalidad |
| **Spec-as-source** | La especificación es el artefacto principal; las personas solo la editan a ella | El código se genera y no se toca a mano |

Según ese mismo artículo, en el momento de escribirse las herramientas se situaban así: Kiro, mayoritariamente spec-first; GitHub Spec Kit, spec-first aunque aspirando a spec-anchored en su mensaje; y Tessl, la única que apunta explícitamente a spec-anchored y explora spec-as-source. Esa clasificación es una foto de octubre de 2025 y las herramientas evolucionan rápido: la tabla de arriba es útil para pensar, la de herramientas hay que contrastarla con su estado actual.

Tres consecuencias prácticas:

- **Spec-first** es el nivel que casi todo equipo puede adoptar mañana: no exige mantener nada y ya elimina las suposiciones ocultas.
- **Spec-anchored** exige un compromiso de mantenimiento. Sin proceso que mantenga viva la especificación, degenera en documentación obsoleta (ver la sección de deriva).
- **Spec-as-source** es el nivel más exigente: si nadie edita el código, la especificación debe contener todo el detalle que el código necesita. Cuanto más detalle, más se parece la especificación a un lenguaje de programación. Es un punto de la clasificación que describe lo que algunas herramientas persiguen, no una práctica asentada.

Los contratos OpenAPI del apartado de contract-first son un caso real de **spec-anchored** en la industria: el documento vive en el repositorio y el código y los clientes se generan o se validan contra él.

---

## Anatomía de una buena especificación

Una especificación útil responde, en este orden, a seis preguntas:

| Sección | Pregunta que responde | Error típico |
|---|---|---|
| **Objetivo** | ¿Qué problema se resuelve y para quién? | Describir la solución en vez del problema |
| **Alcance y no-alcance** | ¿Qué entra y, sobre todo, qué **no** entra? | Omitir el no-alcance: el agente (o la persona) rellena el hueco por su cuenta |
| **Requisitos verificables** | ¿Qué debe cumplirse, de forma comprobable? | Adjetivos («rápido», «correcto») en vez de condiciones |
| **Casos de error** | ¿Qué pasa cuando algo sale mal? | Solo describir el camino feliz |
| **Criterios de aceptación** | ¿Cómo sabemos que está terminado? | Que no se puedan convertir en tests |
| **Decisiones y preguntas abiertas** | ¿Qué se decidió, por qué y qué falta por decidir? | Mezclar decisiones con dudas, o esconder las dudas |

### Escribir requisitos verificables con EARS

**EARS** (Easy Approach to Requirements Syntax) es una sintaxis de plantillas para redactar requisitos sin ambigüedad. La desarrollaron Alistair Mavin y colegas en Rolls-Royce mientras analizaban normativa de aeronavegabilidad para el control de un motor a reacción, y se publicó en 2009. Cada requisito sigue una frase con palabras clave según su tipo:

| Patrón | Plantilla | Cuándo |
|---|---|---|
| **Ubicuo** | El sistema **deberá** [respuesta] | Siempre activo |
| **Guiado por estado** | **Mientras** [estado], el sistema **deberá** [respuesta] | Mientras dure un estado |
| **Guiado por evento** | **Cuando** [evento], el sistema **deberá** [respuesta] | Ante un disparador |
| **Funcionalidad opcional** | **Donde** [funcionalidad presente], el sistema **deberá** [respuesta] | Solo si el producto incluye esa funcionalidad |
| **Comportamiento no deseado** | **Si** [situación indeseada], **entonces** el sistema **deberá** [respuesta] | Errores y condiciones anómalas |
| **Complejo** | Combinación de las anteriores | Estado más evento |

(En el original inglés las palabras clave son *While*, *When*, *Where*, *If/Then* y *shall*.) Kiro, por ejemplo, documenta que su fichero `requirements.md` usa notación EARS con el patrón «WHEN [condición/evento] THE SYSTEM SHALL [comportamiento esperado]».

El efecto de EARS es forzar a nombrar el **disparador** y la **respuesta**, que es lo que casi siempre falta en un requisito vago. Con la regla del cupón:

```text
❌ El sistema debe gestionar bien los cupones caducados.
✅ Si el cupón ha caducado en el momento de aplicarlo, entonces el sistema
   deberá rechazar la petición con el código HTTP 422 y el motivo "expired".
```

```text
❌ El descuento debe ser correcto.
✅ Cuando se aplica un cupón válido, el sistema deberá fijar el descuento en
   el 10 % del subtotal, redondeado a dos decimales, sin incluir gastos de envío.
```

```text
❌ No se pueden usar varios cupones.
✅ Si el carrito ya tiene un cupón aplicado, entonces el sistema deberá
   rechazar un segundo cupón con el código HTTP 409 y dejar el carrito sin cambios.
```

```text
❌ El cupón tiene un mínimo.
✅ Si el subtotal del carrito es inferior a 50,00 EUR, entonces el sistema deberá
   rechazar el cupón SAVE10 con el código HTTP 422 y el motivo "minimum-not-met".
```

La prueba de un requisito verificable es sencilla: **¿se puede escribir un test que falle si no se cumple, sin preguntar nada?** En las cuatro versiones ❌ la respuesta es no. En las ✅ sí, y el test casi se deduce de la frase.

### Ejemplo completo: la especificación del cupón

Esta es una especificación de tamaño medio para la funcionalidad. Es spec-first: vive en el repositorio junto al código, en `docs/specs/carts-coupons.md`.

```markdown
# Cupones de descuento en el carrito

## Objetivo
Permitir que quien compra aplique un cupón al carrito antes de confirmar el
pedido, y ver el descuento desglosado en el resumen.

## Alcance
Dentro:
- Aplicar un cupón a un carrito mediante `POST /api/carts/{cartId}/coupons`.
- Validar el cupón (existe, no ha caducado, importe mínimo).
- Recalcular `discount` y `total` del carrito.

Fuera:
- Crear, editar o desactivar cupones (ya existe en el panel de gestión).
- Cupones acumulables y cupones por producto.
- Quitar un cupón ya aplicado (spec propia).

## Reglas de negocio
- R1. Un cupón se identifica por un código alfanumérico de 4 a 12 caracteres,
  sin distinguir mayúsculas de minúsculas.
- R2. `SAVE10` concede un 10 % sobre el subtotal, redondeado a dos decimales.
- R3. El descuento no incluye gastos de envío ni impuestos de envío.
- R4. Un carrito admite como máximo un cupón.
- R5. Un cupón caduca al final de su fecha de expiración (23:59:59 UTC).
- R6. Un cupón exige un subtotal mínimo; para `SAVE10` es de 50,00 EUR.
- R7. El total nunca es negativo.

## Requisitos
- REQ-01. Cuando se aplica un cupón válido, el sistema deberá devolver el
  carrito con `discount` igual al 10 % del subtotal y `total` recalculado.
- REQ-02. Si el carrito ya tiene un cupón, entonces el sistema deberá
  responder 409 y dejar el carrito sin cambios.
- REQ-03. Si el cupón no existe, entonces el sistema deberá responder 404 con
  el motivo `coupon-not-found`.
- REQ-04. Si el cupón ha caducado, entonces el sistema deberá responder 422 con
  el motivo `expired`.
- REQ-05. Si el subtotal es inferior al mínimo del cupón, entonces el sistema
  deberá responder 422 con el motivo `minimum-not-met`.
- REQ-06. Si el carrito no existe, entonces el sistema deberá responder 404 con
  el motivo `cart-not-found`.

## Criterios de aceptación
- CA-1. El carrito del pedido #4711 (subtotal 149,90 EUR) con `SAVE10` devuelve
  `discount` 14,99 y `total` 134,91 EUR (sin envío).
- CA-2. Un carrito con subtotal 49,99 EUR y `SAVE10` devuelve 422 `minimum-not-met`.
- CA-3. `save10` y `SAVE10` dan el mismo resultado.
- CA-4. Aplicar un segundo cupón a un carrito que ya tiene uno devuelve 409 y el
  carrito no cambia.
- CA-5. Un cupón caducado devuelve 422 `expired`.
- CA-6. Para cualquier carrito y cupón válidos, `0 <= total <= subtotal`.

## Decisiones
- D1. El descuento se guarda en el carrito en el momento de aplicarlo. Si el
  cupón caduca entre aplicarlo y confirmar, se respeta el precio visto.
  Motivo: evitar que el total cambie sin que la persona haya hecho nada.
- D2. Rechazar el segundo cupón (409) en vez de sustituirlo. Motivo: la
  sustitución silenciosa oculta un descuento perdido.

## Preguntas abiertas
- Q1. ¿El mínimo de 50,00 EUR se mide antes o después de otros descuentos
  automáticos? Pendiente de producto.
- Q2. ¿Los 14,99 EUR de descuento se reparten por línea para el cálculo de
  impuestos? Pendiente de contabilidad.
```

Detalles que hacen que funcione:

- **Los identificadores (`R1`, `REQ-04`, `CA-3`) son parte del diseño.** Permiten nombrar cada afirmación en un test, un commit o una revisión, y son la base de la trazabilidad del apartado correspondiente.
- **Las preguntas abiertas se escriben como preguntas, con responsable pendiente.** Una duda escondida en una frase ambigua llega a producción; una duda visible se resuelve o se acota.
- **Las decisiones llevan su motivo.** Sin motivo, la siguiente persona «corrige» lo que era deliberado.
- **Cabe en una pantalla y media.** Si crece mucho, probablemente describa implementación en vez de comportamiento.

---

## Contract-first con OpenAPI

Cuando la especificación incluye una interfaz HTTP, esa parte puede escribirse en un formato que las máquinas entienden. **OpenAPI** es un estándar independiente del lenguaje para describir APIs HTTP; la versión publicada en el sitio oficial en el momento de escribir esta ficha es la 3.2.1 (septiembre de 2026). Un documento OpenAPI (un YAML o JSON) lista rutas, operaciones, parámetros, cuerpos y respuestas.

**Contract-first** significa escribir ese documento **antes** del código y tratarlo como fuente de verdad. Frente a **code-first** (el contrato se genera a partir del código), da tres ventajas: se revisa antes de implementar, quien consume la API puede trabajar contra él desde el primer día y cualquier desvío es detectable por diferencia.

### El contrato del endpoint del cupón

```yaml
openapi: 3.0.3
info:
  title: Shop API
  version: 1.0.0
paths:
  /api/carts/{cartId}/coupons:
    post:
      operationId: applyCoupon
      summary: Aplica un cupón a un carrito
      parameters:
        - name: cartId
          in: path
          required: true
          schema: { type: string, format: uuid }
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ApplyCouponRequest'
      responses:
        '200':
          description: Cupón aplicado; carrito recalculado
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Cart'
        '404':
          description: Carrito o cupón inexistente
          content:
            application/problem+json:
              schema:
                $ref: '#/components/schemas/CouponProblem'
        '409':
          description: El carrito ya tiene un cupón
          content:
            application/problem+json:
              schema:
                $ref: '#/components/schemas/CouponProblem'
        '422':
          description: Cupón caducado o importe mínimo no alcanzado
          content:
            application/problem+json:
              schema:
                $ref: '#/components/schemas/CouponProblem'
components:
  schemas:
    ApplyCouponRequest:
      type: object
      required: [code]
      properties:
        code:
          type: string
          minLength: 4
          maxLength: 12
          example: SAVE10
    Cart:
      type: object
      required: [id, subtotal, discount, total]
      properties:
        id: { type: string, format: uuid }
        subtotal: { type: number, format: double, example: 149.90 }
        discount: { type: number, format: double, example: 14.99 }
        total: { type: number, format: double, example: 134.91 }
        couponCode: { type: string, nullable: true, example: SAVE10 }
    CouponProblem:
      type: object
      required: [reason]
      properties:
        reason:
          type: string
          enum: [cart-not-found, coupon-not-found, already-applied, expired, minimum-not-met]
```

Cada respuesta del contrato corresponde a un requisito de la especificación en prosa: el 200 es `REQ-01`, el 409 es `REQ-02`, los 404 son `REQ-03` y `REQ-06`, los 422 son `REQ-04` y `REQ-05`. El contrato fija la **forma**; la prosa fija las **reglas** (qué cuenta como caducado, de dónde sale el 10 %). Ninguno sustituye al otro.

El ejemplo usa la versión 3.0.3 porque es la que soportan sin discusión las herramientas citadas abajo. Antes de pasar a 3.1 o posterior, comprueba el soporte de cada herramienta de tu cadena (generador, validador y detector de cambios).

### Herramientas en .NET

| Herramienta | Qué hace según su documentación | Sentido |
|---|---|---|
| `Microsoft.AspNetCore.OpenApi` | Soporte de primera parte para generar documentos OpenAPI desde endpoints de ASP.NET Core (controladores y Minimal API) | Código → contrato |
| `Microsoft.Extensions.ApiDescription.Server` | Genera y serializa el documento OpenAPI **en tiempo de compilación** (propiedad `OpenApiGenerateDocumentsOnBuild`) | Código → contrato en el build |
| **NSwag** | Cadena de herramientas Swagger/OpenAPI para .NET: genera especificaciones desde controladores y también clientes C# y controladores a partir de una especificación (soporta OpenAPI 2.0 y 3.0) | Ambos sentidos |
| **Kiota** | Herramienta de línea de comandos de Microsoft que genera clientes tipados (C#, Go, Java, PHP, Python, Ruby, TypeScript) a partir de un documento OpenAPI | Contrato → cliente |

Consecuencia para el flujo contract-first en .NET: el contrato escrito a mano vive en el repositorio; el servidor se implementa a mano (o se generan sus controladores con NSwag) y los clientes se generan con NSwag o Kiota. La parte «código → contrato» sirve para la **comprobación**: se genera el documento desde el código real en el build y se compara con el contrato versionado.

### Detectar desvíos en CI

Escribir el contrato no basta: hay que impedir que se desvíe. Dos comprobaciones complementarias:

1. **El código cumple el contrato.** El build genera el documento OpenAPI desde el código y una comparación falla si difiere del contrato versionado.
2. **El contrato no rompe a quien lo consume.** Una herramienta de cambios incompatibles compara el contrato del PR con el de la rama principal.

**oasdiff** es una herramienta de línea de comandos que compara dos especificaciones OpenAPI. Su comando `breaking` informa solo de los cambios que rompen a los clientes existentes, y acepta ficheros locales o URLs en YAML o JSON. Con `--fail-on ERR` termina con código de salida 1 si hay cambios de nivel error, lo que hace fallar el paso de CI. Tiene una acción de GitHub mantenida en `oasdiff/oasdiff-action`.

```bash
# Contrato de la rama principal vs contrato del PR
git show origin/main:docs/openapi.yaml > /tmp/openapi-main.yaml
oasdiff breaking --fail-on ERR /tmp/openapi-main.yaml docs/openapi.yaml
```

Qué pasa cuando alguien añade un campo obligatorio a la petición. Supón que un PR cambia el esquema de la petición:

```yaml
    ApplyCouponRequest:
      type: object
      required: [code, channel]     # channel es nuevo y obligatorio
```

Según la documentación de oasdiff, **añadir una propiedad obligatoria a la petición es un cambio incompatible**, aunque tenga valor por defecto, porque una petición que no la envíe pasa a ser inválida. El paso `oasdiff breaking --fail-on ERR` devuelve código 1 y el PR no puede fusionarse hasta que alguien decida de forma consciente: hacer el campo opcional, publicar una versión nueva de la API o aprobar la ruptura. El formato exacto del mensaje depende de la versión de oasdiff; ejecútalo localmente para ver el texto real.

La otra dirección del desvío es que el código se aparte del contrato. Si el servidor deja de devolver `422` para el cupón caducado y devuelve `400`, el documento generado desde el código ya no coincide con el versionado y la comparación del primer punto falla. Es el mismo principio que un test: **un desvío tiene que romper algo automáticamente**.

---

## La especificación como contrato ejecutable

Una especificación solo prosa es una opinión. Se convierte en contrato cuando cada afirmación tiene un test que falla si deja de ser cierta. Las capas se conectan en cadena:

```text
Criterio de aceptación  →  Escenario BDD  →  Test unitario/integración (TDD)
(qué se promete)           (cómo lo cuenta     (cómo lo demuestra el código)
                            negocio)
```

Con el ejemplo del cupón, para el criterio `CA-2`:

```text
CA-2   Un carrito con subtotal 49,99 EUR y SAVE10 devuelve 422 minimum-not-met.
```

El criterio pasa a escenario en lenguaje de dominio (la técnica se explica en [BDD](BDD.md)):

```gherkin
Scenario: CA-2 Cupón por debajo del importe mínimo
  Given un carrito con un subtotal de 49,99 EUR
  When la persona aplica el cupón "SAVE10"
  Then la respuesta es 422 con el motivo "minimum-not-met"
  And el carrito no cambia
```

Y el escenario se apoya en tests de menor nivel escritos con el ciclo de [TDD](TDD.md), por ejemplo sobre la regla de dominio:

```csharp
[Fact]
public void Apply_SubtotalBelowMinimum_ReturnsMinimumNotMet()
{
    var cart = CartBuilder.WithSubtotal(49.99m);
    var coupon = Coupon.Save10(expiresOn: new DateOnly(2026, 12, 31), minimum: 50.00m);

    var result = cart.Apply(coupon, today: new DateOnly(2026, 10, 30));

    Assert.Equal(CouponResult.MinimumNotMet, result);
    Assert.Null(cart.CouponCode);
}
```

El nombre del test no tiene que contener el identificador, pero **el identificador debe ser localizable**: un atributo de rasgo, un comentario o el nombre del escenario.

```csharp
[Fact, Trait("Spec", "CA-2")]
public async Task ApplyCoupon_BelowMinimum_Returns422() { /* test de integración */ }
```

### Tabla de trazabilidad

La trazabilidad responde a dos preguntas: «¿qué test comprueba este requisito?» y «¿para qué requisito existe este test?». Una tabla en la especificación lo deja explícito:

| Requisito | Criterio | Escenario BDD | Test que lo demuestra |
|---|---|---|---|
| REQ-01 | CA-1, CA-3 | «Cupón válido sobre el pedido #4711» | `Cart_Apply_Save10_Gives10PercentOfSubtotal`, `CouponApi_Apply_Returns200` |
| REQ-02 | CA-4 | «Segundo cupón rechazado» | `Cart_Apply_WhenAlreadyHasCoupon_Fails`, `CouponApi_Second_Returns409` |
| REQ-04 | CA-5 | «Cupón caducado» | `Coupon_IsExpiredAfterExpiryDate`, `CouponApi_Expired_Returns422` |
| REQ-05 | CA-2 | «Cupón por debajo del mínimo» | `Cart_Apply_BelowMinimum_Fails`, `CouponApi_BelowMinimum_Returns422` |

Una fila sin test es un requisito sin demostrar; un test sin fila es comportamiento sin especificar (o un test sobrante). Ambos son hallazgos de revisión. Con rasgos como el `Trait("Spec", "CA-2")` anterior, un script puede recorrer los identificadores de la especificación y los de los tests y fallar si alguno de la especificación no aparece en ningún test.

### Propiedades en lugar de ejemplos

Algunos criterios no se expresan bien con casos concretos. `CA-6` («para cualquier carrito y cupón válidos, el total está entre 0 y el subtotal») es una **propiedad**: una afirmación que debe cumplirse para toda entrada. El *property-based testing* genera muchas entradas aleatorias, comprueba la propiedad y, si falla, reduce el caso a un contraejemplo mínimo. En .NET existe **FsCheck**, que según su documentación se puede usar desde F#, C# y VB e instala complementos para NUnit y xUnit desde NuGet. Se mencionan aquí como complemento de los tests con ejemplos; la sintaxis concreta en C# se consulta en su documentación (no se reproduce en esta ficha porque no se ha verificado).

---

## Deriva (drift): cuando la especificación miente

Una especificación está en **deriva** cuando describe un comportamiento que el sistema ya no tiene, o el sistema hace algo que la especificación no recoge. Es el modo de fallo principal del SDD spec-anchored: una especificación obsoleta es peor que ninguna, porque se lee con autoridad.

La deriva aparece siempre por el mismo mecanismo: **cambiar el código es obligatorio (si no, no funciona) y cambiar la especificación es opcional (nadie lo comprueba)**. Las defensas consisten en convertir lo opcional en obligatorio:

| Defensa | Cómo funciona | Qué deriva evita |
|---|---|---|
| **Especificación versionada junto al código** | Vive en el mismo repositorio (`docs/specs/`, `docs/openapi.yaml`), no en una wiki aparte | La especificación y el código con versiones distintas |
| **Revisión en el mismo PR** | Un cambio de comportamiento sin cambio de especificación se rechaza en la revisión | El código que avanza sin su documento |
| **Tests que fallan si el contrato cambia** | Documento OpenAPI generado en el build y comparado con el versionado; `oasdiff` para cambios incompatibles | El contrato HTTP desviado |
| **Trazabilidad comprobada por script** | Cada identificador de la especificación debe aparecer en algún test | Requisitos sin demostrar |
| **Plantilla de PR con casilla** | «¿Cambia el comportamiento? ¿Está actualizada la especificación?» | El olvido |
| **Fecha o versión de revisión** | La especificación indica contra qué versión del código se verificó por última vez | La duda sobre si sigue vigente |

Una regla práctica adicional: **decide qué documento es la fuente de verdad de cada cosa**. La forma del endpoint vive en el OpenAPI; las reglas de negocio, en la especificación en prosa; el comportamiento exacto, en los tests. Cuando la misma afirmación está escrita en tres sitios sin que uno mande, tarde o temprano discrepan.

Y una decisión explícita por especificación: **¿es andamio o documentación permanente?** Una especificación spec-first que ya cumplió su función se archiva o se borra; una spec-anchored se mantiene. Dejarla en el repositorio sin decidirlo es la forma más habitual de generar deriva.

---

## SDD con agentes de IA: panorama

El auge actual del término viene de los agentes de codificación. Una especificación bien escrita es el contexto más eficaz que se le puede dar a un agente, y la revisión de la especificación sustituye a gran parte de la revisión del código. Las herramientas concretas ofrecen un andamiaje para ese flujo. Lo que sigue se ha comprobado en la documentación o el repositorio oficial de cada una en octubre de 2026 y cambia con rapidez.

| Herramienta | Qué es, según su fuente oficial | Artefactos y flujo |
|---|---|---|
| **GitHub Spec Kit** | Kit de código abierto de GitHub que da a los agentes de codificación procesos estructurados y plantillas | Se instala con `uv tool install specify-cli` y `specify init`. Flujo de SDD: constitución del proyecto (una vez), luego `specify`, `plan`, `tasks`, `implement` y `converge` como comandos del agente; repite `implement` y `converge` hasta que `converge` informe «Converged». Incluye también procesos para corregir bugs y evaluar ideas, que requieren extensiones |
| **Kiro** | IDE agéntico de AWS con «specs»: artefactos estructurados para funcionalidades y bugs | Cada spec genera `requirements.md` (o `bugfix.md`), `design.md` y `tasks.md`. Su `requirements.md` usa notación EARS |
| **OpenSpec** | Capa de SDD para asistentes de IA que añade un paso ligero de especificación | Estructura `openspec/specs/` (especificaciones vivas) y `openspec/changes/<cambio>/` con `proposal.md`, `specs/`, `design.md` y `tasks.md`. Flujo: explorar, proponer, aplicar y archivar (que fusiona el cambio en las especificaciones vivas). Los requisitos se escriben como `### Requirement:` con `#### Scenario:` y cláusulas WHEN/THEN |

Qué tienen en común, a pesar de las diferencias de formato:

- **Separan el qué del cómo y del orden**: requisitos, diseño y tareas son tres artefactos distintos.
- **Ponen una revisión humana antes del código**, que es donde la corrección es barata.
- **Dividen el trabajo en tareas pequeñas verificables**, no en un único prompt grande.
- **Dejan los artefactos en el repositorio**, como Markdown versionado.

Tessl aparece en el artículo de Böckeler como beta privada; su estado actual no se ha comprobado (sin verificar).

Riesgos específicos:

- **La especificación de cuarenta páginas.** Gasta ventana de contexto, especifica detalles de implementación irrelevantes y envejece en una semana. La prueba de olor: si una persona del equipo no podría implementarlo a partir del documento, falta información; si tarda más en leerlo que en implementarlo, sobra.
- **La falsa sensación de determinismo.** Una especificación detallada no garantiza que el agente la siga: el modelo es probabilístico y la misma especificación puede producir implementaciones distintas. La única garantía real son las comprobaciones automáticas (tests, contrato, CI). Una especificación sin comprobaciones solo es una petición más larga.
- **Revisar el documento en vez del resultado.** Aprobar la especificación no sustituye a verificar el código contra los criterios.

El flujo práctico con un agente (exploración sin escribir, especificación, plan, implementación por pasos, verificación con evidencia) está desarrollado en [Desarrollo dirigido por especificación](../../ia/ingenieria-con-llms/Desarrollo-Dirigido-por-Especificacion.md).

---

## SDD frente a TDD y BDD

Las tres prácticas no compiten: operan en capas distintas del mismo problema.

| | **TDD** | **BDD** | **SDD** |
|---|---|---|---|
| **Artefacto central** | Test unitario que falla | Escenario en lenguaje de dominio (Given/When/Then) | Especificación (prosa estructurada y/o contrato) |
| **Pregunta que responde** | ¿Este código hace lo que quiero? | ¿Lo que construimos es lo que el negocio espera? | ¿Qué hay que construir y dentro de qué límites? |
| **Quién participa** | Quien programa | Negocio, QA y desarrollo | Producto, desarrollo y, si procede, el agente de IA |
| **Qué verifica** | Corrección de una unidad de código | Comportamiento observable de una funcionalidad | Que el diseño y el alcance están acordados; con contratos, que el código no se aparta de ellos |
| **Cuándo se aplica** | Mientras se escribe cada unidad | Al definir y aceptar una funcionalidad | Antes de empezar el trabajo y durante su mantenimiento |
| **Coste** | Bajo por ciclo, constante | Medio: exige conversación y mantenimiento de escenarios | Medio-alto al inicio; el coste real es mantener la especificación viva |
| **Riesgo principal** | Probar la implementación en vez del comportamiento | Escenarios que nadie lee ni mantiene | Especificación obsoleta o excesiva |

### Cómo se combinan en capas

```text
SDD   Especificación del cupón: objetivo, reglas, requisitos, contrato OpenAPI
  │     "qué se construye y dónde acaba"
  ▼
BDD   Escenarios CA-1 … CA-5 en lenguaje de dominio
  │     "cómo se acepta cada criterio"
  ▼
TDD   Tests de Cart.Apply, Coupon.IsExpired…, escritos en ciclos rojo-verde-refactor
        "cómo se construye cada pieza con seguridad"
```

- La **especificación** (SDD) produce criterios de aceptación.
- Cada criterio se convierte en **escenarios** (BDD), compartidos con negocio.
- Cada escenario se implementa con **tests de unidad** (TDD) que guían el diseño del código.
- El **contrato OpenAPI** es la parte de la especificación que una máquina comprueba por sí sola.

### Tabla de decisión

| Situación | Qué usar |
|---|---|
| Función pura o regla de dominio aislada, sin dudas de alcance | TDD solo |
| Funcionalidad con reglas de negocio y personas no técnicas que deben validar | BDD sobre TDD |
| Funcionalidad con varias decisiones de diseño sin tomar | Especificación corta (SDD spec-first) y luego TDD |
| API consumida por otro equipo o cliente | Contrato OpenAPI primero, con comprobación en CI |
| Trabajo delegado a un agente de IA que tocará varios ficheros | SDD spec-first con criterios verificables, tests antes o junto con la implementación |
| Funcionalidad de larga vida con varios equipos que la modifican | SDD spec-anchored con trazabilidad y revisión en el PR |
| Corrección de un bug con causa conocida | Test que reproduce el fallo y arreglo, sin especificación |

---

## Cuándo NO usar SDD

- **Tareas pequeñas.** Renombrar, añadir un campo a un DTO o arreglar un test: se tarda más en el documento que en el cambio. Un umbral que funciona: un solo fichero y se tiene claro, directo al código; tres o más ficheros o una decisión con dos respuestas razonables, especificar.
- **Exploración y prototipos.** Cuando todavía no se sabe qué se quiere, escribir una especificación es fingir una certeza que no existe. Se explora primero y se especifica lo que sobreviva.
- **Dominios que cambian a diario.** Si los requisitos se reescriben cada semana, la especificación nace obsoleta; compensa más una conversación frecuente con tests de aceptación.
- **Cuando nadie va a mantenerla.** Una especificación spec-anchored sin dueño se convierte en deriva. Si no hay quien se comprometa, mejor spec-first y archivarla.
- **Como sustituto de la conversación.** La especificación fija lo acordado; no sirve para acordar. Entregar un documento a quien debe implementarlo sin hablar con producto traslada el malentendido al papel.

## Errores frecuentes

| Síntoma | Causa probable |
|---|---|
| El agente implementa administración de cupones que nadie pidió | La especificación no tiene no-alcance |
| Dos personas implementan el mismo requisito de forma distinta | El requisito usa adjetivos («rápido», «correcto») en vez de condición y respuesta |
| El PR cumple la especificación pero el negocio dice que «no es lo que se pidió» | Los criterios se escribieron a partir del código, no de la necesidad; o hay preguntas abiertas escondidas |
| Nadie abre la especificación pasadas dos semanas | Es demasiado larga, o vive fuera del repositorio |
| El cliente móvil falla tras un despliegue con la API «sin cambios» | Se cambió el contrato HTTP (campo obligatorio nuevo, código de estado) sin comprobación de cambios incompatibles en CI |
| La especificación dice 400 y el servidor devuelve 422 | Deriva: el código cambió en un PR que no tocó la especificación |
| Hay 40 requisitos y 12 tests con su identificador | Falta trazabilidad comprobada por script; requisitos sin demostrar |
| El agente «cumple» todos los criterios pero un caso límite falla en producción | Los criterios solo cubrían el camino feliz; faltaban casos de error y propiedades |
| El equipo abandona el proceso a los dos meses | Se aplica el ciclo completo a tareas pequeñas |
| La misma regla aparece en la prosa, en el YAML y en un test, con valores distintos | No hay fuente de verdad única para cada tipo de afirmación |

---

## Buenas prácticas avanzadas

- **Escribe el no-alcance antes que el alcance.** Es la sección más incómoda y la que más trabajo no pedido evita. Un agente (o una persona entusiasta) tiende a resolver el problema completo que percibe, no el que se pidió; sin límite escrito, «aplicar cupones» acaba incluyendo su administración y su historial.
- **Da identificadores estables a cada afirmación y no los reutilices.** `REQ-04` debe significar siempre lo mismo. Si un requisito se elimina, su identificador se retira, no se asigna a otro: los tests y los commits antiguos seguirían apuntando a algo distinto.
- **Marca las preguntas abiertas con un responsable y bloquea lo que dependa de ellas.** Una pregunta sin dueño se convierte en una suposición del implementador. Es preferible implementar solo lo que no depende de la pregunta que decidir por defecto.
- **Compara el contrato generado con el versionado en el build, no solo el del PR con el de la rama principal.** Son dos comprobaciones distintas: la primera detecta que el código se aparta del contrato; la segunda, que el contrato rompe a sus consumidores. Con una sola, un campo obligatorio nuevo pasa si código y contrato cambian juntos, y un desvío del código pasa si el contrato no se toca.
- **Distingue «incompatible» de «aprobado».** Un cambio incompatible puede ser legítimo (una versión nueva de la API). El control de CI no debe prohibirlo, sino obligar a que alguien lo apruebe de forma explícita, por ejemplo con un fichero de excepciones revisado por quien mantiene la API.
- **Expresa los invariantes como propiedades, no como más ejemplos.** «El total nunca es negativo» se rompe con entradas que ningún ejemplo escrito a mano contempla (importes con muchos decimales, cupones del 100 %). Una propiedad la comprueba con cientos de entradas generadas y reduce el fallo a un contraejemplo mínimo.

## Documentación oficial

- [OpenAPI Specification](https://spec.openapis.org/oas/latest.html) — la fuente normativa del formato del contrato; consúltala para la estructura exacta de `paths`, `responses` y `components`, y para las diferencias entre versiones.
- [Repositorio de GitHub Spec Kit](https://github.com/github/spec-kit) — instalación, comandos del flujo de SDD y extensiones; es la fuente primaria de lo que cada comando hace.
- [Repositorio de oasdiff](https://github.com/oasdiff/oasdiff) — comandos `breaking` y `changelog`, y enlaces a la lista de qué cambios cuentan como incompatibles; es el sitio donde confirmar la versión y las opciones de CI.
- [Specs en Kiro](https://kiro.dev/docs/specs/) — qué ficheros genera una spec y cómo se estructuran los requisitos.

## Recursos didácticos

- [Understanding Spec-Driven-Development: Kiro, spec-kit, and Tessl (Birgitta Böckeler, martinfowler.com)](https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html) — comparación crítica de tres herramientas y origen de la clasificación spec-first, spec-anchored y spec-as-source. Conviene leerlo para ver las limitaciones, no solo las promesas.
- [EARS: Easy Approach to Requirements Syntax (Alistair Mavin)](https://alistairmavin.com/ears/) — las plantillas explicadas por su autor, con ejemplos por patrón.
- [OpenSpec (repositorio)](https://github.com/Fission-AI/OpenSpec) — alternativa ligera para ver cómo se organiza una especificación viva por carpetas y cómo se archiva un cambio.
- [Documentación de OpenAPI en ASP.NET Core (Microsoft Learn)](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/openapi/overview?view=aspnetcore-9.0) — generación del documento en ejecución y en el build; punto de partida para la comprobación en CI.
- [Kiota (Microsoft Learn)](https://learn.microsoft.com/en-us/openapi/kiota/overview) y [NSwag](https://github.com/RicoSuter/NSwag) — generación de clientes C# desde el contrato; la documentación de cada uno detalla los comandos exactos.
- [FsCheck](https://fscheck.github.io/FsCheck/) — property-based testing para .NET, para los invariantes del tipo «el total nunca es negativo».

---

*En resumen: SDD hace que el qué se acuerde por escrito y de forma verificable antes del cómo, y solo funciona si cada afirmación de la especificación tiene una comprobación automática que falle cuando deje de ser cierta.*
