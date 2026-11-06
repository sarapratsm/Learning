# additionalProperties y clientes generados

## ¿Qué es?

`additionalProperties` es la palabra clave de un esquema que decide **si un objeto puede llevar propiedades que el esquema no ha declarado**. Junto con `required` y la forma de expresar «puede ser nulo», determina cómo se ve el contrato desde el otro lado: el **cliente generado** que otras personas compilan a partir de él.

## ¿Por qué existe?

Parece un detalle de validación, pero decide algo mucho más importante: **si añadir un campo a una respuesta es un cambio seguro o una ruptura**.

Escenario: la tienda online tiene el esquema `Product` con tres propiedades y `additionalProperties: false`. Un día el servidor empieza a devolver también `brand`. El contrato se actualiza a la vez, pero el equipo de la aplicación móvil tiene un cliente generado de la versión anterior que **valida cada respuesta contra el esquema**. Para esa validación, `brand` es una propiedad prohibida: la respuesta entera se rechaza y la ficha de producto desaparece. Un cambio que sobre el papel era «aditivo» ha roto una versión de la aplicación que ya estaba en las tiendas de aplicaciones.

> Si ya conoces las clases `sealed` de C#, un esquema con `additionalProperties: false` es parecido: cerrado a extensiones. Quien lo usa tiene la garantía de que nada inesperado aparecerá, y a cambio el esquema no puede crecer sin avisar.

## ¿Cuándo y para qué se usa?

Aparece en cada contrato que se vaya a **generar** (clientes, validadores, documentación) o a **validar** en ejecución. El ejemplo de esta ficha es el esquema `Product` de la tienda online.

## `additionalProperties`: abierto o cerrado

En OpenAPI 3.1 (basado en JSON Schema 2020-12), **si no se escribe, vale `true`**: el objeto puede llevar propiedades de más. Se cierra explícitamente así:

```yaml
Product:
  type: object
  additionalProperties: false
  required: [id, name, price]
  properties:
    id: { type: string, format: uuid }
    name: { type: string }
    price: { type: number }
```

El efecto es distinto según el sentido:

| | Petición (cliente → servidor) | Respuesta (servidor → cliente) |
|---|---|---|
| **Cerrado** (`false`) | El servidor rechaza campos desconocidos. Atrapa errores tipográficos del cliente (`pirce`) | Los clientes que validan la respuesta **rechazan cualquier campo nuevo** |
| **Abierto** (por defecto) | El servidor ignora lo que no conoce y un `pirce` pasa en silencio | Los clientes ignoran lo que no conocen: añadir campos es seguro |

La combinación que suele funcionar mejor es **cerrado en las peticiones y abierto en las respuestas**: se atrapan los errores de quien llama sin impedir que el servidor evolucione. Si decides cerrar también las respuestas, asumes que **añadir un campo es una ruptura** y lo versionas como tal (ver [Versionado de contratos](Versionado-de-Contratos.md)).

## Obligatorio, opcional, nulo y vacío no son lo mismo

Cuatro situaciones distintas que se confunden con facilidad:

| Situación | En el esquema | En el JSON |
|---|---|---|
| El campo siempre viene | En `required` | `"brand": "Acme"` |
| El campo puede **no venir** | Fuera de `required` | (la propiedad no aparece) |
| El campo viene y **vale nulo** | `type: [string, 'null']` | `"brand": null` |
| El campo viene y **está vacío** | `type: string`, sin `minLength` | `"brand": ""` |

En OpenAPI 3.1 el nulo se expresa con la lista de tipos; `nullable: true` es de la versión 3.0 y ya no se usa. Un campo puede ser opcional **y** nulable a la vez:

```yaml
brand:
  type: [string, 'null']
  description: Marca del producto. Ausente si no se ha informado; nulo si se ha borrado.
```

Esa distinción importa: «ausente» suele significar *no sé* y «nulo» *se ha vaciado a propósito*.

El **vacío** (`""`) añade un tercer significado posible, y conviene decidirlo y escribirlo. Imagina que cada pedido guarda la `nota` que dejó quien compró. Una convención razonable es que `""` signifique *«se preguntó y no hubo nota»* y `null` *«este pedido es anterior a que existiera el campo, no se sabe»*. Si el contrato no lo dice, cada cliente adivina, y la duda aparece justo cuando algo hereda el valor: una copia del pedido sin nota y una copia de un pedido antiguo se comportarían igual aunque no lo sean. Cuando elijas esta distinción, déjala en la `description` del campo.

## Del contrato al cliente generado

Con un generador, el contrato produce tipos de forma mecánica. Con `openapi-typescript`:

```bash
npx openapi-typescript ./contratos/catalogo.openapi.yaml -o src/api/catalogo.ts
```

Y el esquema `Product` de arriba, ampliado con `brand`, se convierte aproximadamente en:

```ts
Product: {
  id: string;
  name: string;
  price: number;
  /** Marca del producto. Ausente si no se ha informado; nulo si se ha borrado. */
  brand?: string | null;
};
```

Cada decisión del contrato se ve en el tipo: lo obligatorio no lleva `?`, lo opcional sí, y lo nulable añade `| null`. Si el contrato cambia y el código del cliente lo contradice, **no compila**. Ese es el valor de generar en vez de escribir los tipos a mano.

Para que funcione de verdad:

- **El fichero generado se versiona y se regenera en el mismo cambio que el contrato.** Si no, el repositorio dice una cosa y el cliente otra.
- **Nadie lo edita a mano.** La siguiente regeneración borra el cambio.
- **Una comprobación en integración continua** que regenere y falle si hay diferencias (`git diff --exit-code`) cierra el círculo.

## Los `enum` también son cerrados

Un `enum` de respuesta es un compromiso de que solo saldrán esos valores. Si el cliente lo trata con un `switch` exhaustivo, añadir uno nuevo lo rompe en silencio:

```ts
type Estado = 'PENDIENTE' | 'ENVIADO' | 'ENTREGADO'

function etiqueta(e: Estado): string {
  switch (e) {
    case 'PENDIENTE': return 'Preparando'
    case 'ENVIADO': return 'En camino'
    case 'ENTREGADO': return 'Entregado'
  }
}
```

Cuando el servidor empieza a devolver `'DEVUELTO'`, esta función devuelve `undefined` y la interfaz enseña un hueco. Dos defensas, complementarias: que el contrato **avise** de que el `enum` puede crecer, y que el cliente tenga una rama `default` («Estado desconocido»).

## Un esquema por propósito

Reutilizar el mismo `Product` para crear y para leer parece cómodo, hasta que el `id` aparece como obligatorio en la petición de creación, que es justo la que aún no lo tiene. Hay dos salidas:

- **Marcas `readOnly` / `writeOnly`:** `id` con `readOnly: true` solo cuenta en respuestas, y `secret` con `writeOnly: true` solo en peticiones.
- **Esquemas separados:** `ProductCreate` y `Product`. Es más verboso, pero cada esquema dice una sola cosa.

## Buenas prácticas avanzadas

- **Decide `additionalProperties` por sentido, y escríbelo.** Dejar el valor por defecto sin pensar es decidir «abierto» por omisión, y cerrar «por si acaso» convierte cada campo nuevo en una ruptura. Cualquiera de las dos es válida; ninguna lo es por accidente.
- **Distingue «ausente» de «nulo» y documenta cuál significa qué.** En un `PATCH`, esa diferencia es lo que separa «no toques este campo» de «bórralo».
- **No reutilices el esquema de respuesta como esquema de petición.** Acaba arrastrando campos que el cliente no puede ni debe enviar (`id`, fechas de creación).
- **Fija la versión del generador.** Dos versiones del mismo generador pueden producir tipos distintos a partir del mismo contrato; una actualización accidental cambia el cliente sin que cambie nada más.
- **Trata el `format` como contrato.** `format: uuid` y `format: date-time` no son decoración: los generadores y los validadores los comprueban, y cambiar de `date-time` a `date` es una ruptura.
- **Las respuestas de error tienen el mismo rigor.** Si el esquema de error es cerrado, añadirle una propiedad a *ese* esquema afecta a todas las operaciones que lo usan (ver [Modelado de errores](Modelado-de-Errores.md)).

## Documentación oficial

- [Especificación OpenAPI 3.1: Schema Object](https://spec.openapis.org/oas/v3.1.0#schema-object) — dónde se define qué admite un esquema y en qué se diferencia de la versión 3.0.
- [Understanding JSON Schema: objetos](https://json-schema.org/understanding-json-schema/reference/object) — la explicación más clara de `additionalProperties`, `required` y sus interacciones.
- [openapi-typescript](https://openapi-ts.dev/) — el generador de tipos usado en los ejemplos; la sección de *Node API* explica cómo integrarlo en un `script` del proyecto.

---

*En resumen: una línea del esquema decide si añadir un campo es seguro o rompe a quien ya compiló; ábrelo o ciérralo a propósito, y regenera el cliente en el mismo cambio que el contrato.*
