# Validación con Data Annotations

## ¿Qué es?

Las Data Annotations son atributos (`[Required]`, `[StringLength]`, `[Range]`, `[EmailAddress]`...) que se colocan sobre las propiedades de un modelo para declarar qué reglas deben cumplir sus datos. Viven en el namespace `System.ComponentModel.DataAnnotations`; en ASP.NET Core, el *model binding* (el paso que convierte la petición en objetos C#) las ejecuta justo después de enlazar el modelo y deja el resultado en `ModelState`.

## ¿Por qué existe?

Los datos que llegan de fuera nunca son de fiar: un formulario a medio rellenar, un cliente con un bug, alguien probando a romper la API. Sin validación declarativa, cada acción empieza con una tanda de `if (string.IsNullOrWhiteSpace(...)) return BadRequest(...)`, repetida y propensa a olvidos. Las Data Annotations declaran cada regla **una vez, junto al dato**, y el framework las comprueba antes de que la acción se ejecute.

> Si ya conoces SQL, es la idea de las restricciones `NOT NULL`, `CHECK` y `VARCHAR(n)` de una columna, pero aplicada al DTO de entrada. Y como atributos que son, siguen el mecanismo de [Atributos](../../lenguajes/csharp-dotnet/caracteristicas-del-lenguaje/Atributos.md): metadatos que otro código (aquí, el validador) lee por reflexión.

## ¿Cuándo y para qué se usa?

En los DTO de entrada de una API o un formulario. En la tienda online (`Tienda.Api`), el alta de un pedido (`CrearPedidoRequest`) exige un email válido, una dirección con longitud razonable, un cupón con formato `ABCD-1234` y al menos una línea con cantidad entre 1 y 100. Todo eso son reglas **sobre la forma del dato**, comprobables mirando solo la petición. Las reglas que necesitan consultar la base de datos («el producto existe», «hay stock») no caben aquí: ver [Límites](#límites-y-cuándo-pasar-a-fluentvalidation).

Cómo llega el cuerpo JSON al objeto (`[FromBody]`, `[FromQuery]`, qué tolera el *binding*) se explica en [Model binding](Model-Binding.md); aquí se parte de que el objeto ya está enlazado.

Las salidas citadas provienen de dos proyectos con el SDK de .NET 10.0.401, ejecutados el 2026-11-10 y atacados con `curl`: `Tienda.Api` (controladores) y `Tienda.Min` (Minimal APIs). Ambos con `<Nullable>enable</Nullable>`, que es el valor de las plantillas actuales.

## Los atributos básicos y el 400 automático

Un modelo de entrada con las reglas más habituales:

```csharp
public class CrearPedidoRequest
{
    [Required]
    [EmailAddress]
    public string? ClienteEmail { get; set; }

    [Required]
    [StringLength(200, MinimumLength = 10)]
    public string? DireccionEnvio { get; set; }

    [RegularExpression(@"^[A-Z]{4}-\d{4}$")]
    public string? Cupon { get; set; }

    [Required]
    [MinLength(1)]
    public List<LineaPedidoRequest>? Lineas { get; set; }
}

public class LineaPedidoRequest
{
    [Range(1, int.MaxValue)] public int ProductoId { get; set; }
    [Range(1, 100)]          public int Cantidad { get; set; }
}
```

(Abreviado: el modelo probado añade la propiedad `Facturacion`, que se ve más abajo.)

| Atributo | Qué exige | Notas |
|---|---|---|
| `[Required]` | Valor presente | En `string`, rechaza `null`, `""` y también solo espacios (`"   "`). |
| `[StringLength(max, MinimumLength = n)]` | Longitud de texto entre `n` y `max` | Solo para `string`. |
| `[MinLength(n)]` / `[MaxLength(n)]` | Longitud mínima/máxima | Sirven también para colecciones y arrays. |
| `[Range(min, max)]` | Valor numérico (o fecha, con la sobrecarga de tipo) dentro del rango | Los extremos son inclusivos. |
| `[EmailAddress]`, `[Phone]`, `[Url]` | Formato de email, teléfono o URL | Comprobaciones sencillas de forma, no de existencia. |
| `[RegularExpression(patrón)]` | Coincidencia con una expresión regular | Para formatos propios (cupón, código postal). |
| `[Compare("Otra")]` | Igual al valor de otra propiedad | Contraseña y confirmación. |

Con `[ApiController]` en el controlador, el framework comprueba el resultado antes de ejecutar la acción y, si hay errores, responde `400` sin llegar a ella (cómo se activa y se personaliza ese comportamiento está en [`[ApiController]`](ApiController.md)). Un pedido con todo mal:

```bash
curl -i -X POST http://localhost:6730/api/pedidos -H "Content-Type: application/json" \
  -d '{"clienteEmail":"no-es-email","direccionEnvio":"corta","cupon":"abc","lineas":[{"productoId":0,"cantidad":500}],"facturacion":{"codigoPostal":"123"}}'
```

```text
HTTP/1.1 400 Bad Request
Content-Type: application/problem+json; charset=utf-8
```

```json
{
  "type": "https://tools.ietf.org/html/rfc9110#section-15.5.1",
  "title": "One or more validation errors occurred.",
  "status": 400,
  "errors": {
    "Cupon": ["El cupón debe tener el formato ABCD-1234."],
    "ClienteEmail": ["The ClienteEmail field is not a valid e-mail address."],
    "DireccionEnvio": ["La dirección debe tener entre 10 y 200 caracteres."],
    "Facturacion.Nif": ["The Nif field is required."],
    "Facturacion.CodigoPostal": ["The field CodigoPostal must be a string with a minimum length of 5 and a maximum length of 5."],
    "Lineas[0].Cantidad": ["La cantidad debe estar entre 1 y 100."],
    "Lineas[0].ProductoId": ["The field ProductoId must be between 1 and 2147483647."]
  },
  "traceId": "00-4c49552cefc3e124d439065b97253206-55bba091f2623b76-00"
}
```

(El JSON va con sangría por legibilidad; el servidor lo devuelve en una línea.) Lo que muestra la respuesta:

- **Es un `ValidationProblemDetails`**: el formato estándar de errores HTTP (RFC 9457, antes RFC 7807) con la propiedad extra `errors`. El cliente recibe **todos** los errores a la vez, no solo el primero.
- **La clave de `errors` es la ruta de la propiedad** tal como está en el modelo C#: `Cupon`, `Facturacion.Nif`, `Lineas[0].Cantidad`. Respeta las mayúsculas de la propiedad (`ClienteEmail`), no el camelCase del JSON de entrada.
- **Cada campo lleva una lista**: si una propiedad incumple dos reglas, salen los dos mensajes.
- **Un cliente no necesita parsear los mensajes**: la clave identifica el campo para marcarlo en el formulario; el texto es para mostrarlo.

El mismo cuerpo, ya válido, llega a la acción: `200 OK` con `{"ok":true,"lineas":1}`.

## Mensajes personalizados y localización

Los mensajes por defecto salen en inglés y con el nombre de la propiedad (`The ClienteEmail field is not a valid e-mail address.`). Cada atributo acepta `ErrorMessage`, con marcadores para los parámetros de la regla:

```csharp
[StringLength(200, MinimumLength = 10,
    ErrorMessage = "La dirección debe tener entre {2} y {1} caracteres.")]
public string? DireccionEnvio { get; set; }
```

`{0}` es el nombre del campo; el resto depende del atributo. En `[StringLength]`, `{1}` es el máximo y `{2}` el mínimo (por eso la salida anterior dice «entre 10 y 200»); en `[Range]`, `{1}` es el mínimo y `{2}` el máximo.

Cambiar la cultura de la petición **no traduce** los mensajes por defecto. Con `UseRequestLocalization` activo y la cabecera `Accept-Language: es`, un `[Range(1, 100)]` sin `ErrorMessage` siguió respondiendo `The field Cantidad must be between 1 and 100.` Para servir un mensaje por idioma, `ErrorMessage` se usa como **clave** de un recurso `.resx`:

```csharp
// Program.cs (fragmento)
builder.Services.AddLocalization(o => o.ResourcesPath = "Recursos");
builder.Services.AddControllers()
    .AddDataAnnotationsLocalization(o =>
        o.DataAnnotationLocalizerProvider = (tipo, factoria) => factoria.Create(typeof(Mensajes)));

var culturas = new[] { new CultureInfo("es"), new CultureInfo("en") };
app.UseRequestLocalization(new RequestLocalizationOptions
{
    DefaultRequestCulture = new RequestCulture("en"),
    SupportedCultures = culturas,
    SupportedUICultures = culturas
});
```

```csharp
namespace Tienda.Api;
public class Mensajes { }   // clase vacía que ancla los recursos

public class ConRange
{
    [Range(1, 100, ErrorMessage = "Cantidad_Rango")]
    public int Cantidad { get; set; }
}
```

Con `Recursos/Mensajes.es.resx` y `Recursos/Mensajes.en.resx`, cada uno con la entrada `Cantidad_Rango` («La cantidad debe estar entre {1} y {2}.» / «Quantity must be between {1} and {2}.»):

| Cabecera `Accept-Language` | Mensaje de `Cantidad` |
|---|---|
| `es` | `La cantidad debe estar entre 1 y 100.` |
| `en` | `Quantity must be between 1 and 100.` |
| (ninguna) | `Quantity must be between 1 and 100.` (cultura por defecto) |

Si la clave no existe en el recurso, el framework muestra la propia clave como mensaje. Los recursos tienen que quedar bajo la ruta que indica `ResourcesPath`, y la clase ancla (`Mensajes`) debe estar en un namespace que case con esa ruta: con la clase en `Tienda.Api` y los `.resx` en `Recursos/`, funcionó; con la clase en `Tienda.Api.Modelos`, la búsqueda devolvió solo la clave (`Cantidad_Rango`) en las tres cabeceras.

## Objetos anidados y colecciones

La validación **desciende** por el grafo de objetos: las reglas de `DireccionFacturacion` se comprueban al validar el pedido, y cada elemento de `Lineas` se valida por separado.

```csharp
public class DireccionFacturacion
{
    [Required] public string? Nif { get; set; }
    [Required, StringLength(5, MinimumLength = 5)] public string? CodigoPostal { get; set; }
}
```

(En `CrearPedidoRequest`, la propiedad es `[Required] public DireccionFacturacion? Facturacion { get; set; }`.)

La respuesta de la sección anterior ya lo muestra: `Facturacion.Nif` y `Lineas[0].Cantidad` son rutas profundas, con el índice del elemento que falló. Dos matices:

- **`[Required]` sobre el objeto anidado decide si puede faltar entero.** Sin él, un `Facturacion` ausente es `null` y no se valida nada dentro; con él, un `Facturacion` ausente da el error `Facturacion` y no se descubren los errores internos.
- **`[MinLength(1)]` sobre la colección exige al menos un elemento.** `"lineas": []` devuelve `{"errors":{"Lineas":["El pedido necesita al menos una línea."]}}` (con `ErrorMessage` personalizado).

## Reglas entre campos: `[Compare]` e `IValidatableObject`

`[Compare]` cubre el caso típico de dos campos que deben coincidir:

```csharp
public class RegistroClase
{
    [Required, EmailAddress] public string? Email { get; set; }
    [Required, MinLength(8)] public string? Password { get; set; }

    [Compare(nameof(Password), ErrorMessage = "Las contraseñas no coinciden.")]
    public string? ConfirmarPassword { get; set; }
}
```

```json
{"errors":{"ConfirmarPassword":["Las contraseñas no coinciden."]}}
```

Para cualquier otra regla que mire varias propiedades a la vez, el modelo implementa `IValidatableObject`:

```csharp
public class PromocionRequest : IValidatableObject
{
    [Required] public string? Nombre { get; set; }
    public DateOnly Desde { get; set; }
    public DateOnly Hasta { get; set; }
    public decimal? DescuentoFijo { get; set; }
    public int? DescuentoPorcentaje { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext contexto)
    {
        if (Hasta < Desde)
            yield return new ValidationResult(
                "La fecha de fin no puede ser anterior a la de inicio.",
                [nameof(Hasta), nameof(Desde)]);

        if (DescuentoFijo is null == DescuentoPorcentaje is null)
            yield return new ValidationResult(
                "Indica un descuento fijo o un porcentaje, pero no ambos ni ninguno.");
    }
}
```

Con fechas invertidas y los dos descuentos informados:

```json
{"errors":{"":["Indica un descuento fijo o un porcentaje, pero no ambos ni ninguno."],"Desde":["La fecha de fin no puede ser anterior a la de inicio."],"Hasta":["La fecha de fin no puede ser anterior a la de inicio."]}}
```

El segundo argumento de `ValidationResult` (la lista de nombres de miembro) decide **en qué clave** aparece el mensaje: el primer error se asoció a `Desde` y `Hasta` (el mismo texto sale en ambas claves); el segundo no indicó ninguno y cae en la clave vacía `""`, que significa «error del objeto entero».

**`Validate` solo se ejecuta si todas las reglas de atributo pasaron.** Con `"nombre": ""` (incumple `[Required]`) y sin ningún descuento, la respuesta contiene únicamente `{"errors":{"Nombre":["The Nombre field is required."]}}`: la regla «ni ninguno» no se evaluó. El cliente corrige el nombre, reenvía y recibe entonces el segundo error. Es un comportamiento de diseño (las reglas cruzadas suelen asumir que los campos individuales ya son válidos), pero conviene tenerlo presente al probar.

## Atributos de validación propios

Cuando una regla se repite en varios modelos (el formato de SKU de producto, por ejemplo), se encapsula heredando de `ValidationAttribute`. Hay dos formas según lo que necesite la regla.

La simple, sobrescribiendo `IsValid(object? value)`, que devuelve un `bool`:

```csharp
[AttributeUsage(AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter)]
public sealed class SkuAttribute : ValidationAttribute
{
    public SkuAttribute() : base("El campo {0} debe tener el formato TIE-0000.") { }

    public override bool IsValid(object? value) =>
        value is null || (value is string s && Regex.IsMatch(s, @"^TIE-\d{4}$"));
}
```

La que recibe el contexto, sobrescribiendo `IsValid(object?, ValidationContext)`, cuando hace falta el nombre del campo, otras propiedades del objeto (`contexto.ObjectInstance`) o servicios (`contexto.GetService`):

```csharp
[AttributeUsage(AttributeTargets.Property)]
public sealed class PrecioMultiploDeAttribute(double paso) : ValidationAttribute
{
    protected override ValidationResult? IsValid(object? value, ValidationContext contexto)
    {
        if (value is decimal precio && precio % (decimal)paso != 0)
            return new ValidationResult(
                $"El precio debe ser múltiplo de {paso}.",
                [contexto.MemberName!]);
        return ValidationResult.Success;
    }
}

public class ProductoRequest
{
    [Required, StringLength(100)] public string? Nombre { get; set; }
    [Sku]                         public string? Sku { get; set; }
    [PrecioMultiploDe(0.05)]      public decimal Precio { get; set; }
}
```

```json
{"errors":{"Sku":["El campo Sku debe tener el formato TIE-0000."],"Precio":["El precio debe ser múltiplo de 0.05."]}}
```

Dos reglas de oficio: `IsValid` devuelve **éxito para `null`** (que un campo falte lo decide `[Required]`, no cada atributo; así los atributos se combinan sin pisarse) y el nombre de la clase termina en `Attribute` (se usa como `[Sku]`). La mecánica general de crear atributos está en [Atributos personalizados](../../lenguajes/csharp-dotnet/caracteristicas-del-lenguaje/Atributos-Personalizados.md).

## Los valores que se cuelan: tipos no nulables

Los atributos validan el valor **ya enlazado**, y los tipos de C# tienen un valor por defecto que puede ocultar que el cliente no envió nada. Cuatro casos, ejecutados con `{}` como cuerpo.

### `[Required]` sobre `int` y `bool` no detecta nada

```csharp
public class ConRequiredEnValor
{
    [Required] public int Cantidad { get; set; }
    [Required] public bool AceptaCondiciones { get; set; }
}
```

```text
POST /api/required-valor   {}
HTTP/1.1 200 OK
{"cantidad":0,"aceptaCondiciones":false}
```

Un `int` nunca es `null`: si falta, el enlazador deja `0` y `[Required]` ve un valor presente. La corrección es hacerlos anulables, con lo que `[Required]` vuelve a significar «no puede faltar»:

```csharp
public class ConAnulables
{
    [Required] public int? Cantidad { get; set; }
    [Required] public bool? AceptaCondiciones { get; set; }
}
```

```json
{"errors":{"Cantidad":["The Cantidad field is required."],"AceptaCondiciones":["The AceptaCondiciones field is required."]}}
```

Para un `int` que debe ser positivo, `[Range(1, 100)]` ya lo rechaza (`{}` da `The field Cantidad must be between 1 and 100.`): el `0` por defecto cae fuera del rango. El problema aparece solo cuando `0` o `false` son valores legítimos pero «ausente» no lo es.

### `string` no nulable: el `[Required]` implícito

Con las referencias anulables activadas (`<Nullable>enable</Nullable>`), MVC trata una propiedad `string` (no `string?`) como obligatoria aunque no lleve `[Required]`:

```csharp
public class SinRequired
{
    public string Nombre { get; set; } = default!;   // string no nulable, sin [Required]
    public string? Notas { get; set; }                // string anulable
}
```

```text
POST /api/sin-required   {}
HTTP/1.1 400 Bad Request
{"errors":{"Nombre":["The Nombre field is required."]}}
```

`Notas` (anulable) no genera error; `Nombre` sí, y el mensaje es el de `[Required]` aunque no esté escrito. Es una validación **implícita** que depende del contexto de nulabilidad del proyecto: se activa con las plantillas actuales, pero quien migra un proyecto antiguo sin `<Nullable>` no la tiene. Se apaga con la opción de MVC:

```csharp
builder.Services.AddControllers(o =>
    o.SuppressImplicitRequiredAttributeForNonNullableReferenceTypes = true);
```

Con la opción activa, el mismo `{}` devolvió `200 OK` con `{"nombre":null,"notas":null,"cantidad":0,"aceptaCondiciones":false}`: un `Nombre` no nulable con `null` dentro, sin que el compilador pueda avisar. Conviene **declarar la intención**: `[Required]` en lo obligatorio y `string?` en lo opcional, en lugar de depender de la regla implícita. (Esta regla implícita es de MVC; en Minimal APIs no existe, ver más abajo.)

### La palabra clave `required` no es una validación de Data Annotations

```csharp
public class ConRequiredKeyword
{
    public required string Nombre { get; set; }
    public required int Cantidad { get; set; }
}
```

```text
POST /api/keyword   {}
HTTP/1.1 400 Bad Request
{"errors":{
  "$":["JSON deserialization for type 'Tienda.Api.Modelos.ConRequiredKeyword' was missing required properties including: 'nombre', 'cantidad'."],
  "r":["The r field is required."]}}
```

La palabra clave `required` de C# 11 hace que el **deserializador JSON** (`System.Text.Json`) falle si falta la propiedad. El error es distinto del de las anotaciones: la clave es `$` (el cuerpo entero), el texto habla de deserialización y aparece además un error espurio sobre el parámetro (`r`, el nombre del parámetro de la acción). No sirve para formularios (`application/x-www-form-urlencoded`), donde no hay deserializador JSON, y tampoco detecta `null` explícito: `{"nombre":null,"cantidad":1}` pasa la deserialización y lo recoge la regla implícita de `string` no nulable (`The Nombre field is required.`). Útil como red de seguridad, pero no sustituye a `[Required]` cuando importa el mensaje por campo.

## Records posicionales: el atributo va en el parámetro

Un DTO como `record` con constructor primario se valida igual, pero los atributos se escriben sobre los **parámetros** del constructor:

```csharp
public record RegistroPosicional(
    [Required, EmailAddress] string Email,
    [Range(18, 120)] int Edad);
```

```json
{"errors":{"Edad":["The field Edad must be between 18 and 120."],"Email":["The Email field is not a valid e-mail address."]}}
```

Si se fuerza el destino de la propiedad con `[property: ...]`, MVC lo rechaza en ejecución. Con `[property: Compare("Password")]` sobre `ConfirmarPassword`, la petición terminó en `500 Internal Server Error` con cuerpo vacío y, en el log del servidor:

```text
System.InvalidOperationException: Record type 'Tienda.Api.Modelos.RegistroRequest' has validation metadata defined on property 'ConfirmarPassword' that will be ignored. 'ConfirmarPassword' is a parameter in the record primary constructor and validation metadata must be associated with the constructor parameter.
```

Y `[Compare]` no puede ir en el parámetro: su declaración solo admite propiedades, y escribirlo así no compila (`error CS0592: El atributo 'Compare' no es válido en este tipo de declaración. Solo es válido en declaraciones 'propiedad, indizador'`). Un modelo con `[Compare]` se escribe como clase (o como `record` con propiedades en el cuerpo), como `RegistroClase` más arriba.

## Validar a mano: `ModelState` y `Validator`

Sin `[ApiController]`, la validación **se ejecuta igual** (el enlazador rellena `ModelState`), pero nadie corta la petición: la acción entra con el modelo inválido. Un controlador sin el atributo y sin comprobar nada:

```csharp
[Route("manual")]
public class ManualController : ControllerBase
{
    [HttpPost("sin-comprobar")]
    public IActionResult SinComprobar([FromBody] ProductoRequest r) =>
        Ok(new { valido = ModelState.IsValid, r.Nombre });
}
```

```text
POST /manual/sin-comprobar   {"nombre":"","sku":"XX","precio":10.03}
HTTP/1.1 200 OK
{"valido":false,"nombre":""}
```

La acción devolvió `200` con datos inválidos. La comprobación explícita, con el mismo formato de respuesta que daría el atributo:

```csharp
[HttpPost("productos")]
public IActionResult Crear([FromBody] ProductoRequest r)
{
    if (!ModelState.IsValid) return ValidationProblem(ModelState);
    return Ok(r);
}
```

```json
{"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.","status":400,"errors":{"Sku":["El campo Sku debe tener el formato TIE-0000."],"Nombre":["The Nombre field is required."],"Precio":["El precio debe ser múltiplo de 0.05."]},"traceId":"00-ddbf0b0880bff5a623f3085b111c94e1-985ac6edd2499eb1-00"}
```

Fuera del *pipeline* de MVC (un servicio, un `BackgroundService`, un objeto construido a mano) nadie ejecuta las anotaciones: hay que invocar `Validator` explícitamente.

```csharp
var resultados = new List<ValidationResult>();
bool valido = Validator.TryValidateObject(
    producto, new ValidationContext(producto), resultados, validateAllProperties: true);
```

`validateAllProperties: true` es imprescindible: con el valor por defecto (`false`), `TryValidateObject` solo comprueba los `[Required]` y **ignora el resto de atributos**. Con él activado, el mismo producto inválido produjo tres entradas en `resultados`, cada una con su `MemberNames` y su `ErrorMessage`. `Validator` no desciende a objetos anidados ni a colecciones: es una validación de un solo nivel, a diferencia de MVC.

## Minimal APIs: `AddValidation` (.NET 10)

Un endpoint de Minimal API **no valida por defecto**, ni siquiera en .NET 10. El mismo modelo con atributos, enlazado en un `MapPost`, deja pasar cualquier cosa:

```csharp
app.MapPost("/api/pedidos", (CrearPedidoRequest r) => Results.Ok(new { ok = true, lineas = r.Lineas?.Count }));
```

```text
POST /api/pedidos   {"clienteEmail":"x","lineas":[{"cantidad":500}]}
HTTP/1.1 200 OK
{"ok":true,"lineas":1}
```

.NET 10 incorpora una validación integrada que se activa con una línea de registro, sin paquetes extra (compiló con la plantilla `dotnet new web` y el SDK 10.0.401):

```csharp
builder.Services.AddValidation();
```

Con ella, el mismo `POST`:

```text
HTTP/1.1 400 Bad Request
Content-Type: application/json; charset=utf-8
{"title":"One or more validation errors occurred.","errors":{"ClienteEmail":["The ClienteEmail field is not a valid e-mail address."],"Lineas[0].Cantidad":["The field Cantidad must be between 1 and 100."]}}
```

Qué hace y qué no, según lo observado:

- **Valida los tipos que aparecen como parámetros de un endpoint**, incluidos los anidados (`Lineas[0].Cantidad`) y los que implementan `IValidatableObject` (una `PromocionRequest` con fechas invertidas devolvió `{"errors":{"Hasta":["Fin anterior a inicio."]}}`). Un endpoint cuyo DTO no lleva atributos (`SinMarcar`) responde `200` sin más.
- **También valida parámetros sueltos**: `([Range(1, 1000)] int id)` con `id` 5000 devolvió `{"errors":{"id":["The field id must be between 1 and 1000."]}}`. Observado: un `[Required] string? etiqueta` de query ausente **pasó** (`{"id":5,"etiqueta":null}`), mientras que `?etiqueta=` (vacía) dio `The etiqueta field is required.`: un parámetro opcional ausente no llega a evaluarse. Si el parámetro es obligatorio, declararlo no anulable (`string etiqueta`) deja que lo rechace el binding.
- **El cuerpo del error es más escueto que el de MVC**: sin `type`, `status` ni `traceId`, y con `Content-Type: application/json`. Registrando además `builder.Services.AddProblemDetails()`, el `400` pasa a `application/problem+json` con `type`, `status` y `traceId`, igual que el de `[ApiController]`.
- **Se desactiva por endpoint** con `.DisableValidation()` (`POST /api/sin-validar` con `{}` devolvió `200`).
- **Las claves de `errors` conservan las mayúsculas de la propiedad**, como en MVC.
- **No existe la regla implícita de `string` no nulable**: en Minimal APIs lo obligatorio se marca con `[Required]` o `required`.

Cómo se enlazan los parámetros de un endpoint mínimo (`[FromBody]`, `[AsParameters]`...) está en [Model binding](Model-Binding.md#equivalencias-en-minimal-apis). El resto del mecanismo (opciones de `AddValidation`, soporte de tipos) se consulta en la documentación oficial enlazada al final; no se ha probado aquí más allá de lo descrito.

## Límites y cuándo pasar a FluentValidation

Las Data Annotations validan **la forma de un dato con la información del propio objeto**. Quedan fuera:

- **Reglas que necesitan datos externos.** «El email no está ya registrado», «el producto existe y hay stock» exigen una consulta; un atributo no tiene acceso cómodo a servicios ni es el sitio para I/O asíncrono (`IsValid` es síncrono). Esas reglas son de aplicación o de dominio y pertenecen a la capa que tiene el repositorio (ver [Clean Architecture](../../arquitectura-de-software/clean-architecture/)).
- **Transformaciones.** Los atributos no recortan espacios ni normalizan texto: solo dicen sí o no.
- **Reglas condicionales y por contexto.** «El CIF es obligatorio solo si el país es España» se puede hacer con `IValidatableObject`, pero queda mezclado con el modelo y es incómodo de probar de forma aislada.

Tabla de decisión:

| Situación | Herramienta |
|---|---|
| Obligatorio, longitud, rango, formato, coincidencia entre dos campos | Data Annotations |
| Una regla simple que se repite en varios modelos | Atributo propio (`ValidationAttribute`) |
| Pocas reglas cruzadas entre campos del mismo objeto | `IValidatableObject` |
| Muchas reglas condicionales, mensajes por contexto, o reglas que se quieren probar sin levantar el framework | [FluentValidation](../de-wpf-a-web/FluentValidation.md) (la guía de esa librería está en la colección de WPF a web) |
| Reglas que requieren base de datos o servicios externos | Capa de aplicación o dominio, con su propio resultado de error (el endpoint lo traduce a `409`, `422` o `400`) |
| Los modelos de dominio deben ser independientes de `System.ComponentModel.DataAnnotations` | FluentValidation, o validación dentro del propio dominio |

FluentValidation no se ha ejecutado aquí: la tabla recoge el criterio de diseño, no una comparativa medida.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `[Required] int Cantidad` no rechaza el cuerpo `{}` y la acción recibe `0` | Un `int` nunca es `null`; el enlazador deja el valor por defecto. Usar `int?` o un `[Range]` que excluya el `0`. |
| `400` con `"Nombre": ["The Nombre field is required."]` sin que el modelo tenga `[Required]` | Regla implícita de las referencias no nulables (`string Nombre` con `<Nullable>enable</Nullable>`). Declarar `string?` si es opcional. |
| `500` sin cuerpo y `InvalidOperationException: Record type '...' has validation metadata defined on property '...' that will be ignored` | Atributo con destino `[property: ...]` en un `record` posicional. Quitar el destino: el atributo va en el parámetro. |
| `error CS0592: El atributo 'Compare' no es válido en este tipo de declaración` | `[Compare]` solo admite propiedades. Usar una clase, o un `record` con propiedades en el cuerpo. |
| La regla de `IValidatableObject` no salta y sí lo hace tras corregir otro campo | `Validate` se ejecuta solo cuando todas las reglas de atributo pasaron. |
| La acción recibe datos inválidos con `200 OK` | Controlador sin `[ApiController]` y sin `if (!ModelState.IsValid)`. O un endpoint de Minimal API sin `AddValidation()`. |
| `Validator.TryValidateObject` devuelve `true` con un `[Range]` incumplido | Falta `validateAllProperties: true`. |
| Mensaje en inglés pese a `Accept-Language: es` | Los mensajes por defecto no se traducen; hace falta `ErrorMessage` con clave y `AddDataAnnotationsLocalization`. |
| El mensaje localizado sale como la clave (`Cantidad_Rango`) | El recurso `.resx` no se encuentra: la clase ancla o la ruta (`ResourcesPath`) no coinciden. |
| `400` con `"$": ["JSON deserialization for type '...' was missing required properties including: ..."]` | La palabra clave `required` de C# hace fallar al deserializador antes de llegar a las anotaciones. |

## Buenas prácticas avanzadas

- **Declara la nulabilidad como parte del contrato, no la dejes a la regla implícita.** Una `string` sin `?` es obligatoria en MVC y opcional en Minimal APIs, y la opción `SuppressImplicitRequiredAttributeForNonNullableReferenceTypes` la apaga globalmente. Escribir `[Required]` en lo obligatorio y `string?` en lo opcional hace que el comportamiento sea el mismo en los dos modelos de programación y sobreviva a un cambio de configuración.
- **Usa `int?`/`bool?` con `[Required]` cuando «no enviado» y «cero/falso» significan cosas distintas.** Una casilla de «acepto las condiciones» como `bool` con `[Required]` valida siempre; como `bool?` obliga a que el cliente la envíe. Para «debe ser `true`», el sitio es un atributo propio, no `[Required]`.
- **Que el atributo propio devuelva éxito para `null` y cuelgue el error del miembro correcto.** Usa la sobrecarga con `ValidationContext` y pasa `[contexto.MemberName!]` en el `ValidationResult`: sin él, el error cae en la clave `""` y el cliente no sabe qué campo marcar.
- **Mantén las reglas cruzadas en `IValidatableObject` solo mientras sean pocas, y no cuentes con que se evalúen junto a las de atributo.** Como `Validate` espera a que pasen los atributos, el cliente recibe los errores en dos rondas. Si esa segunda ronda molesta, es una señal para mover las reglas a FluentValidation, que las evalúa todas a la vez.
- **Traduce el `400` en un único sitio.** La forma del error (`errors` por campo) es parte del contrato de la API: si hay que cambiarla, se hace con `InvalidModelStateResponseFactory` (ver [`[ApiController]`](ApiController.md)) en un solo punto, no filtrando en cada acción. En Minimal APIs, `AddProblemDetails()` unifica el formato con el de MVC.
- **No bindees la entidad: valida el DTO de entrada.** Las anotaciones sobre una entidad de EF Core mezclan la forma de la petición con el esquema de la base de datos y habilitan el sobreposting (ver [Model binding](Model-Binding.md#sobreposting-no-enlazar-la-entidad)). Un `CrearPedidoRequest` con sus propias reglas desacopla ambos.

## Documentación oficial

- [Model validation in ASP.NET Core MVC and Razor Pages](https://learn.microsoft.com/en-us/aspnet/core/mvc/models/validation) — la referencia de los atributos, `ModelState`, validación de objetos anidados, `IValidatableObject` y atributos propios; empezar por los apartados de atributos integrados y de errores de validación.
- [Minimal APIs: parameter binding y validación](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/minimal-apis/parameter-binding) — dónde se documenta `AddValidation` para Minimal APIs en .NET 10, sus opciones y `DisableValidation`.
- [Namespace System.ComponentModel.DataAnnotations](https://learn.microsoft.com/en-us/dotnet/api/system.componentmodel.dataannotations) — la lista completa de atributos (`[Phone]`, `[Url]`, `[CreditCard]`, `[AllowedValues]`...) y la clase `Validator`.
- [FluentValidation](https://docs.fluentvalidation.net/) — la alternativa cuando las anotaciones se quedan cortas; la sección de reglas condicionales y la de integración con ASP.NET Core.

---

*En resumen: las Data Annotations declaran las reglas de forma de un DTO como atributos y el framework devuelve un `400` con los errores por campo sin que la acción se ejecute; los tipos por valor, las referencias no nulables y los records tienen trampas propias que se evitan declarando la nulabilidad a propósito, y cuando la regla necesita datos externos o se vuelve condicional, es hora de dar el salto a FluentValidation.*
