# Versionado de contratos

## ¿Qué es?

Versionar un contrato es asignarle un número que dice **qué clase de cambio** ha sufrido desde la versión anterior. Se usa el **versionado semántico** (`MAYOR.MENOR.PARCHE`) aplicado a la API: el número le dice a quien consume si puede actualizarse sin miedo o si debe revisar algo antes.

## ¿Por qué existe?

Quien consume una API no controla cuándo cambia. Si el número de versión no distingue entre «he corregido una errata en una descripción» y «he quitado un campo», todo cambio da la misma ansiedad y el aviso pierde valor.

Con una convención compartida, la versión funciona como un semáforo: un parche se aplica sin mirar, un cambio menor se puede adoptar con calma, y uno mayor exige una conversación.

> Si ya conoces el versionado de paquetes NuGet o npm, es lo mismo: `2.3.1` → `2.3.2` es seguro, `2.3.1` → `3.0.0` puede romper. La diferencia es que aquí «romper» no lo detecta un compilador: lo descubre un cliente en producción.

## ¿Cuándo y para qué se usa?

Siempre que haya consumidores que no se despliegan a la vez que el servidor: una web y una app móvil (que los usuarios actualizan tarde), un socio externo, o simplemente otro equipo con su propio calendario. El ejemplo de esta ficha es el contrato de una tienda online, que empieza en la versión `1.0.0`.

## Qué cuenta como ruptura

La regla de oro: **una ruptura la define quien consume**. Un cambio rompe si un cliente correcto, escrito contra la versión anterior, deja de funcionar o empieza a comportarse mal.

| Cambio | ¿Rompe? | Por qué |
|---|---|---|
| Añadir un endpoint nuevo | No | Nadie lo usaba |
| Añadir un campo **opcional** a una respuesta | No (casi siempre) | Los clientes que no lo conocen lo ignoran. Ver la excepción en [additionalProperties y clientes generados](Additional-Properties-y-Clientes-Generados.md) |
| Añadir un campo **obligatorio** a una petición | **Sí** | Los clientes antiguos no lo envían y la petición falla |
| Añadir un campo **obligatorio** a una respuesta | No | Quien consume solo lee: un campo de más se ignora |
| Quitar o renombrar un campo de una respuesta | **Sí** | El cliente lo leía |
| Dejar de garantizar un campo de una respuesta (pasa de obligatorio a opcional) | **Sí** | El cliente daba por hecho que siempre venía y ahora puede faltar |
| Permitir que un campo de una respuesta valga nulo cuando antes nunca lo valía | **Sí** | El cliente no comprueba nulos donde el contrato prometía un valor |
| Cambiar el tipo de un campo (`price` de número a texto) | **Sí** | El cliente lo interpreta mal |
| Hacer más estricta una validación (antes `name` aceptaba 100 caracteres, ahora 50) | **Sí** | Peticiones que eran válidas dejan de serlo |
| Hacer más laxa una validación de **petición** | No | Lo antiguo sigue siendo válido |
| Añadir un valor a un `enum` que se devuelve | **Posible** | Un cliente con un `switch` cerrado no sabe qué hacer con el valor nuevo |
| Cambiar un valor por defecto | **Sí** | Quien no enviaba el parámetro obtiene otro resultado |
| Cambiar **qué significa** un campo sin cambiar su forma | **Sí**, aunque no lo parezca | Ver la sección siguiente |

## Mayor, menor y parche

Aplicado a un contrato:

| Número | Cuándo sube | Ejemplo en la tienda |
|---|---|---|
| **MAYOR** (`1.x.x` → `2.0.0`) | Hay una ruptura | `price` pasa de `number` a un objeto `{ amount, currency }` |
| **MENOR** (`1.2.x` → `1.3.0`) | Se añade algo compatible | Nuevo endpoint `GET /products/{id}/reviews`, o un campo opcional `brand` |
| **PARCHE** (`1.2.3` → `1.2.4`) | Se corrige o se aclara sin cambiar lo que un cliente correcto ve | Documentar un error `409` que el servidor ya devolvía, o corregir un texto |

El número vive en `info.version` del contrato y **cambia en el mismo cambio que el código**:

```yaml
info:
  title: Tienda — API de catálogo
  version: 1.3.0
```

## La ruptura silenciosa: cambiar el significado sin cambiar la forma

Es la que más cuesta ver, porque ningún comparador de esquemas la detecta. Imagina que `price` siempre ha sido el precio **sin impuestos**, y un día el servidor empieza a devolverlo **con impuestos incluidos**:

```json
{ "id": "3f2c...", "name": "Taza de cerámica", "price": 9.5 }
```

El JSON es idéntico y el esquema también (`number`). Pero quien sumaba el IVA por su cuenta ahora lo cobra dos veces.

Para decidir qué número poner, la pregunta es **quién depende del comportamiento antiguo**:

| Situación | Tratamiento |
|---|---|
| Hay consumidores que dependían del significado antiguo | Se trata como **mayor** o, mejor, se añade un campo nuevo (`priceWithTax`) y el antiguo no cambia |
| El servidor **nunca** cumplió lo que el contrato documentaba y se corrige para que lo cumpla | **Parche**, con nota explícita y aprobación, porque los consumidores ya se apoyaban en lo documentado |
| El contrato era ambiguo y se aclara sin cambiar el comportamiento real | **Parche** |

El segundo caso es delicado: es un parche porque el contrato no cambia de forma, pero **hay que decirlo con todas las letras** en el propio contrato (ver la sección siguiente) y pasarlo por el mismo proceso de aprobación que un cambio mayor.

## Dejar rastro en el propio contrato

Cada versión se anota al principio de `info.description`, con fecha, qué cambia y por qué. Lo más reciente, arriba:

```yaml
info:
  version: 1.3.1
  description: >
    **v1.3.1 (2026-03-12)** — patch, cambio de semántica sin cambio de forma. El campo
    `price` pasa a incluir impuestos, que es lo que el contrato documentaba desde 1.0.0.
    Ninguna operación gana campos ni cambia su respuesta.

    **v1.3.0 (2026-02-20)** — nuevo endpoint `getProductReviews`.
```

Y cuando una frase de una versión anterior deja de ser cierta, **no se borra en silencio**: se tacha y se explica, porque quien llegue a ese párrafo leerá la versión vieja creyéndola vigente.

```yaml
    · ~~«`price` no incluye impuestos»~~ (escrito en 1.0.0) **deja de ser cierto desde 1.3.1**.
```

Si una nota se corrige el mismo día que se escribe, también se dice: *«Corrección del mismo día: la primera redacción de esta versión decía X; se descartó antes de publicarla»*. Un historial honesto vale más que uno limpio.

## Evolucionar sin romper

Casi siempre hay una vía que evita el salto de versión mayor: **añadir en vez de cambiar**.

```yaml
properties:
  price:
    type: number
    deprecated: true
    description: Precio sin impuestos. Obsoleto desde 1.4.0; usar `priceWithTax`.
  priceWithTax:
    type: number
    description: Precio con impuestos incluidos.
```

El ciclo es *añadir lo nuevo → marcar lo viejo como `deprecated` con fecha → retirarlo en la siguiente versión mayor*, cuando ya nadie lo use.

## Buenas prácticas avanzadas

- **No reutilices un campo para dos significados.** Si `status` hoy vale `"active"` y mañana también `"pending_review"` con otro sentido, cada cliente lo interpretará a su manera. Un campo, un significado; para otro, un campo nuevo.
- **Un valor por defecto es parte del contrato.** Cambiar `pageSize` de 20 a 50 es una ruptura para quien contaba con 20 páginas. Si el parámetro es opcional, documenta el valor por defecto en el esquema y trátalo como lo que es.
- **Anuncia la retirada con la cabecera `Sunset`.** Además de `deprecated: true` en el contrato, el servidor puede enviar `Sunset: Wed, 01 Oct 2026 00:00:00 GMT` en las respuestas del endpoint obsoleto; quien monitorice las cabeceras se entera sin leer el changelog.
- **Una ruptura de verdad no se esconde en un parche.** Si hay dudas entre parche y mayor, la pregunta correcta es «¿puede un cliente correcto romperse?». Si la respuesta es sí, es mayor, aunque el número suene a mucho.
- **Mide antes de afirmar que nadie usa un campo.** Quitar un campo «que no usa nadie» sin comprobarlo en los registros del servidor es la causa clásica de una mañana difícil.
- **Versiona en la ruta solo cuando una ruptura es inevitable.** `/v2/products` obliga a mantener dos APIs a la vez; la evolución aditiva con campos obsoletos mantiene una sola.

## Documentación oficial

- [Versionado semántico (semver.org)](https://semver.org/lang/es/) — la especificación original, corta; las reglas sobre qué número sube están en los puntos 6 a 8.
- [Google AIP-180: compatibilidad hacia atrás](https://google.aip.dev/180) — la lista más cuidadosa que existe de qué cambios de una API son compatibles y cuáles no.
- [Cómo versiona Stripe su API](https://stripe.com/blog/api-versioning) — un caso real de una API que lleva años evolucionando sin romper a quien se quedó en una versión antigua.
- [oasdiff](https://github.com/oasdiff/oasdiff) — compara dos contratos OpenAPI y clasifica los cambios; sirve para automatizar la tabla de arriba.

---

*En resumen: el número de versión es una promesa sobre lo que un cliente correcto puede esperar, y la ruptura más peligrosa es la que no cambia ni una coma del esquema.*
