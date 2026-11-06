# Seguridad en el contrato

## ¿Qué es?

Poner la seguridad en el contrato es escribir, en el mismo fichero OpenAPI, **quién puede llamar a cada operación** (con qué credencial y con qué permiso), **qué respuesta recibe quien no puede** y **qué datos se exponen** a quien sí. Es la parte del contrato que decide si una operación es pública, privada o restringida a ciertos roles.

## ¿Por qué existe?

Si el contrato no dice nada de seguridad, cada cliente lo descubre probando: llama, recibe un `401` o un `403` y adivina qué le falta. Y quien revisa el contrato no puede comprobar que una operación sensible está protegida, porque ese dato no está escrito en ningún sitio.

Escenario: en la tienda online, `GET /orders/{id}` devuelve un pedido. El servidor comprueba que hay sesión, pero no que el pedido sea de quien lo pide. Cualquier persona autenticada puede leer pedidos ajenos cambiando el número de la URL. El contrato no mencionaba permisos, así que ninguna revisión del YAML lo habría señalado. Si el contrato hubiera dicho «solo quien hizo el pedido, o el personal de la tienda», la pregunta «¿y el servidor lo comprueba?» habría salido en la revisión y en un test.

> Si ya conoces los atributos `[Authorize]` de ASP.NET, es la misma idea llevada al contrato: la anotación del servidor deja de ser un detalle de código y pasa a ser parte de lo que se promete y se revisa.

## ¿Cuándo y para qué se usa?

En cualquier contrato con operaciones que no sean abiertas a todo el mundo. El ejemplo de esta ficha es el contrato de la tienda online: el catálogo es público, los pedidos son privados y la configuración de la tienda solo la edita el personal.

## Declarar la credencial

El contrato describe **cómo se identifica** quien llama (`securitySchemes`) y **qué operaciones lo exigen** (`security`):

```yaml
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT

security:
  - bearerAuth: []          # por defecto, toda operación exige sesión

paths:
  /products:
    get:
      operationId: listProducts
      security: []          # esta es pública: el catálogo lo ve cualquiera
```

Con esto, quien lee el contrato sabe que todo es privado salvo lo que dice `security: []`. **Que una operación pública lo sea es una decisión explícita**, no un olvido: el valor por defecto seguro es exigir sesión.

## 401, 403 y 404: tres respuestas, tres significados

| Estado | Significa | Cuándo se devuelve |
|---|---|---|
| `401` | «No sé quién eres» | No hay credencial, o es inválida o ha caducado |
| `403` | «Sé quién eres, pero no puedes hacer esto» | Hay sesión, pero el rol o el permiso no bastan |
| `404` | «Eso no existe» (para ti) | El recurso no existe, **o existe pero no te corresponde y no se quiere revelar** |

El caso delicado es el recurso ajeno. Ante `GET /orders/42` de un pedido que existe pero es de otra persona:

- Con `403`, la respuesta confirma que **el pedido 42 existe**. Para una tienda puede ser irrelevante; para otros datos (historiales, expedientes) es una fuga.
- Con `404`, no se revela nada, a costa de que quien consume no distinga «no existe» de «no es tuyo».

No hay una respuesta única correcta, pero sí una obligación: **elegirla y escribirla** en la `description` de la respuesta, porque un cliente que ve `404` necesita saber que puede significar las dos cosas.

```yaml
'404':
  description: >
    No existe un pedido con ese identificador, o existe pero pertenece a otra
    persona. No se distingue un caso del otro para no revelar la existencia de
    pedidos ajenos.
```

## Exponer lo mínimo

Cada campo que una respuesta publica es un compromiso de mantenerlo y, además, un dato que sale del servidor. Esto pesa especialmente en operaciones abiertas a **cualquier persona con sesión**, porque el listado de quién puede verlas es el más amplio.

Imagina que la tienda guarda su configuración (moneda por defecto, texto legal, cuenta bancaria del reembolso) y que el formulario de compra necesita solo la moneda. Hay dos formas de exponerlo:

- **Mala:** `GET /settings`, abierto a cualquier persona con sesión, que devuelve el objeto de configuración entero. Hoy tiene tres campos; cuando alguien añada uno sensible, saldrá a todo el mundo sin que nadie lo decida.
- **Buena:** una operación de lectura **aparte** y con su propio esquema, que devuelve solo lo que quien compra necesita.

```yaml
/settings/checkout-defaults:
  get:
    operationId: getCheckoutDefaults
    summary: Valores por defecto que necesita quien compra
    description: >
      Solo lectura, abierta a cualquier persona con sesión. Devuelve únicamente
      la moneda por defecto. La configuración completa se edita con otra operación,
      restringida al personal de la tienda.
    responses:
      '200':
        content:
          application/json:
            schema: { $ref: '#/components/schemas/CheckoutDefaults' }
```

El esquema `CheckoutDefaults` solo tiene `defaultCurrency`. Añadir un campo a la configuración interna ya no cambia lo que sale por aquí: para publicarlo hay que añadirlo a **este** esquema, con revisión.

Lo mismo vale cuando el mismo recurso se ve distinto según el rol: es más seguro tener esquemas separados (`OrderForCustomer`, `OrderForStaff`) que un solo esquema donde el servidor «oculta» campos según quien pregunta, porque el contrato deja entonces de decir qué se ve realmente.

## Probar las garantías

El esquema no expresa permisos, así que se prueban con tests que fijan lo que el contrato promete:

```csharp
[Fact]
public async Task GetPedido_DeOtraPersona_DevuelveNotFound_SinRevelarQueExiste()
{
    var respuesta = await _clienteDeOtraPersona.GetAsync($"/orders/{_pedidoDeAna.Id}");

    Assert.Equal(HttpStatusCode.NotFound, respuesta.StatusCode);
}

[Fact]
public async Task GetCheckoutDefaults_SinSesion_Devuelve401()
{
    var respuesta = await _clienteAnonimo.GetAsync("/settings/checkout-defaults");

    Assert.Equal(HttpStatusCode.Unauthorized, respuesta.StatusCode);
}
```

Un tercero comprueba que la respuesta de la operación abierta **solo** lleva los campos del esquema: es la forma de que un campo sensible añadido por descuido haga fallar un test en lugar de salir a producción.

## Buenas prácticas avanzadas

- **El valor por defecto es «exige sesión».** Declara `security` a nivel global y marca las operaciones públicas con `security: []`. Así una operación nueva nace protegida y hay que decidir explícitamente que sea abierta.
- **Pon `401` y `403` en las operaciones que los pueden devolver.** Si el contrato no los menciona, el cliente generado no tiene un camino para ellos y trata la caducidad de sesión como un error inesperado.
- **Escribe qué significa cada `404` de un recurso protegido.** Es la única forma de que quien consume sepa si puede deducir algo de él.
- **Separa la lectura abierta de la edición restringida en operaciones distintas.** Mezclarlas en una sola, con lógica de «si eres personal ves más», convierte cada campo nuevo en una decisión de seguridad que nadie toma.
- **No uses la presencia del campo como control de acceso.** «Los campos sensibles solo vienen si tienes permiso» es un contrato imposible de comprobar con el esquema; usa esquemas distintos.
- **Que un test cierre cada garantía de acceso.** Un permiso que solo vive en la cabeza de quien revisa se pierde con la siguiente reorganización del servidor.

## Documentación oficial

- [OpenAPI 3.1: Security Scheme Object](https://spec.openapis.org/oas/v3.1.0#security-scheme-object) — la fuente normativa de `securitySchemes` y `security`; consulta aquí los tipos de credencial admitidos y cómo se combinan.
- [OWASP API Security Top 10](https://owasp.org/API-Security/editions/2023/en/0x11-t10/) — el primer riesgo de la lista, la autorización rota a nivel de objeto, es el del pedido ajeno del escenario de arriba.
- [RFC 9110: semántica de HTTP](https://www.rfc-editor.org/rfc/rfc9110) — define con precisión `401`, `403` y `404`; las secciones de códigos de estado `4xx` son la referencia cuando hay dudas.

## Recursos didácticos

- [jwt.io](https://jwt.io/) — pega un token de ejemplo y verás sus partes decodificadas; ayuda a entender qué lleva una credencial y qué no.

---

*En resumen: si el contrato no dice quién puede llamar a cada operación y qué se ve, esa decisión la toma el código sin que nadie la revise; escríbela, prueba que se cumple y expón solo lo que quien llama necesita.*
