# Datos estructurados con JSON-LD: `Organization` y `BreadcrumbList`

## ¿Qué es?

Los **datos estructurados** son una descripción en formato máquina de lo que hay en una página: «esto es una organización, con este nombre, este logotipo y esta dirección». **JSON-LD** es la forma de escribirlos más extendida: un bloque JSON dentro de una etiqueta `<script type="application/ld+json">`, con el vocabulario de [schema.org](https://schema.org/).

## ¿Por qué existe?

Un buscador lee el texto de tu página y deduce de qué trata, pero **deducir no es saber**. Un número de teléfono es una cadena de dígitos; que sea el teléfono de contacto de tu empresa es una interpretación. Con datos estructurados lo declaras en lugar de dejar que lo adivine, y el buscador puede usarlo para identificar a tu organización o para mostrar la ruta de una página en los resultados.

## ¿Cuándo y para qué se usa?

- `Organization`, en la portada o en la página «quiénes somos»: quién eres, cómo te llaman, dónde estás, dónde tienes perfiles.
- `BreadcrumbList`, en las páginas de detalle: la posición de una página dentro de la web (Tienda › Zapatillas › Aire).
- Hay muchos más tipos (`Product`, `Article`, `FAQPage`...); esta ficha usa estos dos para centrarse en cómo escribirlos bien. Para una visión general, mira [SEO web](../seo-web/SEO.md).

---

## `Organization`

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Organization",
  "name": "Ejemplo SL",
  "url": "https://ejemplo.com",
  "logo": "https://ejemplo.com/logo.png",
  "description": "Tienda online de calzado deportivo.",
  "email": "hola@ejemplo.com",
  "telephone": "+34-900-000-000",
  "address": {
    "@type": "PostalAddress",
    "streetAddress": "Calle Mayor 1",
    "addressLocality": "Madrid",
    "postalCode": "28001",
    "addressCountry": "ES"
  },
  "sameAs": [
    "https://www.linkedin.com/company/ejemplo",
    "https://www.youtube.com/@ejemplo"
  ]
}
</script>
```

Según la documentación de Google:

- **No hay propiedades obligatorias**; se recomienda añadir todas las que apliquen.
- `logo`: mínimo 112 × 112 píxeles, en un formato que admita Google Imágenes, rastreable, y que se vea bien sobre fondo blanco.
- `address` es un `PostalAddress`; el país va en código ISO 3166-1 alfa-2 (`ES`).
- `sameAs` lista tus perfiles en otros sitios.
- Si hay un subtipo más específico, úsalo: `OnlineStore` en lugar de `Organization` para una tienda.
- **Pon solo datos que ya son públicos en la página** (el mismo teléfono y la misma dirección del pie). Si el marcado dice una cosa y la página otra, pierde valor. Lo mejor es que ambos salgan del mismo dato, sin copia aparte.
- No hace falta incluir datos que no quieras publicar (fax, razón social, NIF): son opcionales.

## `BreadcrumbList`

La ruta de migas es la fila «Tienda › Zapatillas › Aire» de una página. Su marcado dice lo mismo a los buscadores:

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "itemListElement": [
    { "@type": "ListItem", "position": 1, "name": "Zapatillas",
      "item": "https://ejemplo.com/es/zapatillas/" },
    { "@type": "ListItem", "position": 2, "name": "Aire" }
  ]
}
</script>
```

Reglas, según Google:

- `itemListElement` es obligatorio y lleva **al menos dos** elementos, en orden.
- Cada `ListItem` lleva `position` (empieza en 1), `name` (el texto que ve la persona) e `item` (la dirección).
- En el **último elemento `item` es opcional**: si falta, se usa la dirección de la propia página.
- No hace falta incluir la portada ni la página actual como tramo si no tiene sentido en tu web.
- Debe representar **una ruta típica de la persona**, no necesariamente la estructura de las direcciones.

La regla práctica: **el marcado y la ruta que se ve deben coincidir**. Lo más seguro es que ambos se calculen en el mismo sitio, a partir de los mismos nombres, y que el JSON-LD use direcciones absolutas.

## El escape de `<`: un fallo de seguridad que parece un detalle

`<script>` es una etiqueta HTML, y el navegador cierra su contenido en cuanto encuentra `</script>`, **también dentro de una cadena JSON**. Si pintas datos que no controlas (el nombre de un producto, un título editado por alguien) con `JSON.stringify` tal cual, un valor como esto cierra tu bloque e inyecta código:

```text
"name": "</script><script>robarSesion()</script>"
```

La solución que recomienda Next.js es sustituir cada `<` del JSON ya serializado por su escape Unicode, que sigue siendo JSON válido pero ya no cierra la etiqueta:

```tsx
function DatosEstructurados({ datos }: { datos: object }) {
  const json = JSON.stringify(datos).replace(/</g, '\\u003c')
  return <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: json }} />
}
```

Para quien lea JSON-LD (los buscadores), `"<"` y `"<"` son el mismo carácter. Para el navegador, la etiqueta no se puede cerrar desde dentro.

## Comprobar el marcado

Dos herramientas gratuitas: la [prueba de resultados enriquecidos de Google](https://search.google.com/test/rich-results) (qué entiende Google) y el [validador de schema.org](https://validator.schema.org/) (si el JSON es válido contra el vocabulario). En una web estática, lo mejor es complementarlas con un test automático que recorra el HTML generado, extraiga los bloques y compruebe los campos.

## Buenas prácticas avanzadas

- **Un único origen para marcado y contenido visible.** El teléfono del pie y el del `Organization` salen del mismo dato; un cambio se refleja en ambos.
- **Escapa `<` siempre que sirvas JSON-LD**, aunque hoy el contenido sea tuyo: mañana lo editará otra persona.
- **No marques lo que no se ve.** Google puede ignorar o penalizar marcado que describe algo que la página no muestra.
- **Direcciones absolutas dentro del JSON-LD**, con la misma dirección base que usas en canónicas y mapa del sitio.
- **El marcado va en el HTML servido.** Aunque Google ejecuta JavaScript, otros lectores no: generar el `<script>` en la construcción es lo más fiable.
- **Tipa el JSON-LD.** Paquetes como `schema-dts` detectan un `@type` mal escrito o una propiedad inexistente al compilar.

## Documentación oficial

- [Datos estructurados de `Organization` (Google)](https://developers.google.com/search/docs/appearance/structured-data/organization) — propiedades recomendadas y requisitos del logotipo.
- [Datos estructurados de ruta de migas (Google)](https://developers.google.com/search/docs/appearance/structured-data/breadcrumb) — propiedades obligatorias y cómo tratar el último elemento.
- [JSON-LD en Next.js](https://nextjs.org/docs/app/guides/json-ld) — el patrón del componente y el escape de `<`.
- [schema.org](https://schema.org/) — el vocabulario completo, para buscar el tipo y las propiedades de lo que describes.

---

*En resumen: JSON-LD declara en formato máquina quién eres y dónde está cada página; escríbelo con las mismas fuentes que el contenido visible, con direcciones absolutas y escapando `<`.*
