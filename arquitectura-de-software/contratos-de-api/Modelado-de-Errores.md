# Modelado de errores

## ¿Qué es?

Modelar los errores es decidir **cómo responde una API cuando algo sale mal** y escribirlo en el contrato con el mismo rigor que la respuesta de éxito: qué estado HTTP, qué forma tiene el cuerpo y qué información le llega a quien consume para poder reaccionar.

## ¿Por qué existe?

El error es la parte del contrato que más se descuida y la que más se ve. Una API cuyo error es siempre «Petición inválida» obliga al cliente a adivinar qué ha fallado, y la pantalla acaba mintiendo.

Escenario: en el panel de una tienda online, una persona da de alta un *webhook* con dos campos, `callbackUrl` (debe empezar por `https://`) y `secret` (mínimo 8 caracteres). Escribe `ttps://tienda.ejemplo.com/hook` —le falta la `h`— y una clave correcta. El servidor valida, ve que la URL no cumple y responde:

```http
HTTP/1.1 400 Bad Request

{ "code": "VALIDATION_ERROR", "message": "El secreto no puede estar vacío o la URL es inválida." }
```

El cliente solo conserva el `code` (por una buena razón, que se verá enseguida), así que sabe que *algo* es inválido, pero no qué. Hace lo único que puede: mostrar el mensaje del caso más probable, «El secreto no puede estar vacío». Con el secreto perfectamente relleno. La causa real estaba en el servidor, que tenía el nombre del campo y la regla incumplida y **los tiró**.

## Estructura base: `code` y `message`

El mínimo razonable es un objeto con dos propiedades:

```json
{ "code": "WEBHOOK_NOT_FOUND", "message": "No existe un webhook con ese identificador." }
```

| Propiedad | Para quién | Qué cumple |
|---|---|---|
| `code` | El **programa** cliente | Estable, en mayúsculas, parte del contrato. Se decide con él (`if (error.code === ...)`) y se traduce a cada idioma |
| `message` | Las **personas** que leen logs | Orientativo, puede cambiar, no se muestra al usuario final ni se usa para decidir |

Por eso el cliente de arriba descarta el `message`: es texto del servidor, probablemente en otro idioma que la interfaz, y puede filtrar detalles internos. Lo que sí debe poder hacer es **decidir por `code`**. Y para eso el `code` tiene que ser lo bastante fino.

## Errores por campo

Cuando una petición tiene varios datos, el error útil es **«este campo, por esta regla»**:

```json
{
  "code": "VALIDATION_ERROR",
  "message": "Petición inválida.",
  "errors": [
    { "field": "callbackUrl", "code": "URL_SIN_HTTPS" }
  ]
}
```

Con esto, la interfaz pinta «La URL debe empezar por https://» **debajo de la URL** y no culpa a otro campo. Las reglas que mantienen esa estructura sana:

- **Un código por regla, no por campo.** `callbackUrl` puede fallar por `URL_OBLIGATORIA` o por `URL_SIN_HTTPS`; son cosas distintas que se traducen distinto.
- **Un solo error por campo**, el primero que se incumple. Un secreto vacío incumple a la vez «no vacío» y «mínimo 8 caracteres»; mostrar los dos es ruido. El orden de las reglas decide cuál sale.
- **El nombre del campo es el del JSON**, no el de la propiedad del servidor. Si el servidor valida `CallbackUrl` y el JSON lleva `callbackUrl`, alguien tiene que convertirlo y conviene que sea con un mapa explícito, no con reflexión.
- **El `message` y el `code` de nivel superior se conservan.** Un cliente antiguo que solo lee `code` sigue funcionando.

## Cuando fallan varias cosas a la vez

Una petición puede incumplir dos cosas a la vez: un cuerpo mal formado y, además, un campo demasiado largo. Si cada comprobación vive en una capa distinta (el *framework* valida el JSON, el servidor valida las reglas de negocio), **la respuesta lleva un solo código** y manda el de la comprobación que corre antes.

Eso es aceptable si se decide a propósito y se documenta. La persona que consume corrige el primer error, reintenta y, si el segundo sigue ahí, lo recibe entonces. Lo que no es aceptable es que el orden dependa del azar de la implementación, porque el mismo cuerpo daría códigos distintos según la versión del servidor.

| Opción | Cuándo encaja |
|---|---|
| Un código y orden fijo | Las comprobaciones viven en capas distintas y el caso es raro desde la interfaz |
| Todos los errores a la vez (`errors`) | Es un formulario con varios campos y la persona agradece verlos juntos (ver la sección anterior) |

Si eliges la primera, escribe el orden en la `description` de la operación: «un cuerpo mal formado se responde con `VALIDATION_ERROR` antes de comprobar los límites de cada campo».

## Lo que un error no debe llevar

Un cuerpo de error acaba en pantallas, en logs, en herramientas de monitorización y en capturas que se pegan en un chat. Por eso:

- **Nunca el valor rechazado.** Si `secret` es demasiado corto, el error dice `SECRETO_CORTO`, no «`abc12` es demasiado corto». Un secreto no puede viajar de vuelta en una respuesta de error.
- **Nunca un mensaje de librería sin revisar.** Muchas librerías de validación permiten plantillas con el valor (`{PropertyValue}`). Una plantilla que hoy no lo incluye puede incluirlo mañana. Si lo que viaja es solo `field` y `code`, ese riesgo no existe.
- **Nunca trazas de pila, SQL ni rutas del servidor.** Eso va al registro interno, con un identificador de petición que el error sí puede devolver.

## Un esquema de error distinto por operación

Es tentador añadir `errors` al esquema `Error` que comparten todas las operaciones. Hay dos razones para no hacerlo:

1. El `Error` común suele ser **cerrado** (`additionalProperties: false`, ver [additionalProperties y clientes generados](Additional-Properties-y-Clientes-Generados.md)): meter un campo ahí cambia la respuesta de **todas** las operaciones, aunque solo una lo necesite.
2. Un cliente generado a partir de ese esquema no sabe en qué operaciones viene `errors` y en cuáles no.

La solución es un esquema aparte, solo para la operación que lo necesita:

```yaml
components:
  schemas:
    Error:
      type: object
      additionalProperties: false
      required: [code, message]
      properties:
        code: { type: string }
        message: { type: string }
    ValidationError:
      type: object
      additionalProperties: false
      required: [code, message, errors]
      properties:
        code: { type: string, const: VALIDATION_ERROR }
        message: { type: string }
        errors:
          type: array
          items:
            type: object
            additionalProperties: false
            required: [field, code]
            properties:
              field: { type: string, enum: [callbackUrl, secret] }
              code:
                type: string
                enum: [URL_OBLIGATORIA, URL_SIN_HTTPS, SECRETO_VACIO, SECRETO_CORTO]
```

Y la operación apunta a él en su `400`:

```yaml
'400':
  description: Algún campo no cumple su regla.
  content:
    application/json:
      schema: { $ref: '#/components/schemas/ValidationError' }
```

Listar los `code` posibles como `enum` permite que quien consume sepa de antemano qué debe traducir. Añadir `ValidationError` es un cambio **aditivo**: ninguna otra operación se ve afectada (ver [Versionado de contratos](Versionado-de-Contratos.md)).

## Cómo se produce en el servidor

Una validación con códigos de error y un controlador que los traslada. En C# con FluentValidation:

```csharp
RuleFor(x => x.CallbackUrl)
    .Cascade(CascadeMode.Stop)
    .NotEmpty().WithErrorCode("URL_OBLIGATORIA")
    .Must(u => u.StartsWith("https://", StringComparison.Ordinal)).WithErrorCode("URL_SIN_HTTPS");

RuleFor(x => x.Secret)
    .NotEmpty().WithErrorCode("SECRETO_VACIO")
    .MinimumLength(8).WithErrorCode("SECRETO_CORTO");
```

```csharp
var validacion = await validator.ValidateAsync(cmd, ct);
if (!validacion.IsValid)
{
    var errores = validacion.Errors
        .GroupBy(e => e.PropertyName)                       // un solo error por campo
        .Select(g => new FieldError(CampoJson(g.Key), g.First().ErrorCode))
        .ToList();
    return BadRequest(new ValidationErrorResponse("VALIDATION_ERROR", "Petición inválida.", errores));
}
```

`CampoJson` es un `switch` explícito (`"CallbackUrl" => "callbackUrl"`). Fíjate en lo que **no** hay: ningún texto del validador ni el valor enviado.

## Cómo lo consume el cliente

Se traduce por código a cada idioma y hay un respaldo genérico para lo que no se conozca:

```ts
const textos: Record<string, string> = {
  URL_SIN_HTTPS: 'La URL debe empezar por https://',
  SECRETO_CORTO: 'El secreto debe tener al menos 8 caracteres',
}

function mensajeDeCampo(error: ApiError, campo: string): string | undefined {
  const fallo = error.fieldErrors?.find((f) => f.field === campo)
  return fallo ? (textos[fallo.code] ?? 'Revisa los datos introducidos') : undefined
}
```

Si llega un `400` **sin** `errors` (por ejemplo, un JSON mal formado que ni llega a la validación), el cliente muestra un mensaje genérico de formulario. Lo que nunca debe hacer es elegir el mensaje del caso más probable: ahí nació el error de la tienda de arriba.

## Probar el error

Un test que fija el contrato de error, y el que más rinde, es el que comprueba que el secreto no vuelve:

```csharp
[Fact]
public async Task PostWebhook_ConUrlSinHttps_DevuelveCampoYCodigo_SinEcoDelSecreto()
{
    var respuesta = await _client.PostAsJsonAsync("/webhooks",
        new { callbackUrl = "ttps://tienda.ejemplo.com/hook", secret = "secreto-de-prueba-123" });

    Assert.Equal(HttpStatusCode.BadRequest, respuesta.StatusCode);
    var cuerpo = await respuesta.Content.ReadAsStringAsync();
    Assert.Contains("\"field\":\"callbackUrl\"", cuerpo);
    Assert.Contains("URL_SIN_HTTPS", cuerpo);
    Assert.DoesNotContain("secreto-de-prueba-123", cuerpo);
}
```

## Buenas prácticas avanzadas

- **Los `code` son API: no se renombran.** Cambiar `SECRETO_CORTO` por `SECRETO_MUY_CORTO` rompe cada traducción que dependía de él. Si hace falta uno nuevo, se añade; el viejo se deja hasta la siguiente versión mayor.
- **Declara los `code` posibles de cada operación como `enum`.** Es lo que convierte «el error puede ser cualquier cosa» en una lista que el cliente puede cubrir, y lo que hace que un código nuevo aparezca en el diff del contrato.
- **El cliente siempre tiene un respaldo para un `code` que no conoce.** Un servidor más reciente que el cliente puede enviar uno nuevo; el respaldo evita una pantalla vacía.
- **Documenta también los errores que no pasan por tu validación.** El `400` de un JSON mal formado, el `413` de un cuerpo demasiado grande o el `429` de una cuota suelen generarlos el *framework* o un proxy, con un cuerpo distinto. Si el contrato no los menciona, quien consume los descubre en producción.
- **Distingue los estados con intención.** `400` para una petición mal formada, `404` para un recurso inexistente, `409` para un conflicto con el estado actual, `422` si se quiere separar «bien formada pero no procesable». Lo explica con más detalle [REST](../tipos-de-apis/REST.md); lo importante aquí es que el `code` complementa al estado, no lo sustituye.
- **Un identificador de petición en el error ayuda más que cualquier mensaje.** Quien reporta un fallo copia un `requestId`; quien investiga lo busca en el registro del servidor, donde sí está el detalle completo.

## Documentación oficial

- [RFC 9457: Problem Details for HTTP APIs](https://www.rfc-editor.org/rfc/rfc9457) — el estándar de la IETF para cuerpos de error en JSON (`application/problem+json`); útil si prefieres adoptar un formato común en vez de uno propio.
- [OWASP: Error Handling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Error_Handling_Cheat_Sheet.html) — qué información no debe filtrar un error; la sección sobre mensajes genéricos es la más relevante.
- [Microsoft REST API Guidelines](https://github.com/microsoft/api-guidelines) — la sección de errores propone una estructura con códigos estables y detalles anidados.

## Recursos didácticos

- [http.cat](https://http.cat/) — cada código de estado HTTP con un gato; ideal para recordar la diferencia entre `400`, `404`, `409` y `422`.

---

*En resumen: el error es parte del contrato; si el servidor sabe qué campo falló y por qué regla, debe decirlo con un código estable —y nunca con el valor que falló—, para que la pantalla no tenga que adivinar.*
