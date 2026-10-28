# `robots.txt` y `sitemap.xml`

## ¿Qué es?

`robots.txt` es un fichero de texto en la raíz de tu dominio que dice a los robots de los buscadores **qué partes de la web pueden rastrear**. `sitemap.xml` es un fichero XML que les da **la lista de las direcciones que quieres que conozcan**, con sus versiones por idioma.

## ¿Por qué existe?

Un robot llega a tu web siguiendo enlaces. Si una página no la enlaza nadie, o está a cinco clics de la portada, puede tardar semanas en descubrirla. Y al revés: si tu web tiene miles de direcciones sin interés (resultados de búsqueda interna, filtros combinados), el robot puede gastar su tiempo ahí.

El mapa del sitio es la **invitación** («estas son mis páginas») y `robots.txt` es el **aviso en la puerta** («por aquí no hace falta pasar»). Ninguno de los dos manda sobre el buscador: son pistas.

## ¿Cuándo y para qué se usa?

- `sitemap.xml`: en cualquier web con más de unas pocas páginas, y sobre todo si tiene versiones por idioma.
- `robots.txt`: para declarar dónde está el mapa y, si hace falta, para pedir que no se rastreen zonas concretas (un panel interno, resultados de búsqueda).
- Escenario típico: una tienda online en tres idiomas con miles de productos; el mapa lista cada producto con sus tres versiones.

---

## `robots.txt`

Debe estar en la **raíz del host** (`https://ejemplo.com/robots.txt`), en UTF-8. Cada host, protocolo y puerto tiene el suyo: el de `https://ejemplo.com` no vale para `https://tienda.ejemplo.com`.

```text
User-agent: *
Allow: /

Sitemap: https://ejemplo.com/sitemap.xml
```

- `User-agent` indica a qué robot se aplican las reglas; `*` significa todos.
- `Disallow: /ruta/` pide no rastrear esa ruta; `Allow:` hace una excepción dentro de una ruta bloqueada.
- Las rutas **distinguen mayúsculas de minúsculas**: `Disallow: /Admin/` no afecta a `/admin/`.
- `Sitemap:` debe ser una dirección **completa**, y puede repetirse.
- `#` inicia un comentario.

Un ejemplo con una zona bloqueada:

```text
User-agent: *
Disallow: /buscar/
Allow: /

Sitemap: https://ejemplo.com/sitemap.xml
```

### Lo que `robots.txt` no hace

Es el malentendido más caro del SEO: **no sirve para que una página no aparezca en Google**. Si otras páginas enlazan una dirección que has bloqueado, Google puede indexarla igualmente, solo que sin descripción. Para mantener una página fuera hay que usar `noindex` (y dejar que el robot la lea para verlo) o protegerla con contraseña. Y para información sensible, ni uno ni otro: los robots **no están obligados** a respetar el fichero.

Dos consecuencias prácticas:

- **No bloquees las direcciones con parámetros** si quieres que el buscador lea su canónica: un robot que no puede abrir la página no ve la etiqueta que le dice cuál es la dirección preferida.
- **No bloquees nada que necesite una página para verse bien** (hojas de estilo, scripts) si la página pierde claridad sin ello.

## `sitemap.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:xhtml="http://www.w3.org/1999/xhtml">
  <url>
    <loc>https://ejemplo.com/es/zapatillas/</loc>
    <xhtml:link rel="alternate" hreflang="es" href="https://ejemplo.com/es/zapatillas/"/>
    <xhtml:link rel="alternate" hreflang="en" href="https://ejemplo.com/en/shoes/"/>
    <xhtml:link rel="alternate" hreflang="x-default" href="https://ejemplo.com/"/>
  </url>
  <url>
    <loc>https://ejemplo.com/en/shoes/</loc>
    <xhtml:link rel="alternate" hreflang="es" href="https://ejemplo.com/es/zapatillas/"/>
    <xhtml:link rel="alternate" hreflang="en" href="https://ejemplo.com/en/shoes/"/>
    <xhtml:link rel="alternate" hreflang="x-default" href="https://ejemplo.com/"/>
  </url>
</urlset>
```

Reglas del formato, según la documentación de Google:

- **Direcciones absolutas** y completamente cualificadas, en UTF-8, con los caracteres especiales escapados como en cualquier XML (`&` es `&amp;`).
- **Límite**: 50 000 direcciones o 50 MB sin comprimir por fichero; si superas uno, divide en varios y agrúpalos con un índice de sitemaps.
- **Alcance**: un sitemap, si no lo envías por Search Console, solo cubre las direcciones de su directorio y subdirectorios; ponlo en la raíz.
- **`lastmod`** solo cuenta si es coherente y exacto (cambios significativos del contenido, no la fecha del pie de página). **`changefreq` y `priority`**, Google los ignora.
- **Cada versión por idioma aparece como una entrada propia**, y cada entrada lista a todas las versiones, incluida ella misma, igual que las etiquetas de la página. Los dos métodos deben decir exactamente lo mismo.
- Es una **sugerencia**: no garantiza que Google rastree ni indexe todo.

### Qué entra y qué no

Entran las direcciones **canónicas, que devuelven 200 y que quieres encontrar en un buscador**. Quedan fuera:

- la página 404,
- las direcciones con parámetros de filtro o de página (su canónica ya es la del listado),
- las direcciones antiguas que redirigen a otra,
- el contenido que no existe en un idioma (esa versión no se lista),
- y cualquier página con `noindex`.

Una regla útil para saber si has acertado: **todo lo que está en el mapa debería coincidir con la canónica de su página**.

### Cómo se declara y se envía

Añade la línea `Sitemap:` a `robots.txt` (así lo encuentra cualquier robot) o envíalo desde el informe de sitemaps de Search Console.

## Generarlos en lugar de escribirlos

Un mapa escrito a mano queda desfasado en cuanto se añade una página. Lo sensato es generarlo **a partir de la misma tabla de direcciones** que alimenta las canónicas y las etiquetas `hreflang`:

```ts
type Entrada = { url: string; alternativas: Record<string, string> }

function aSitemap(entradas: Entrada[]): string {
  const filas = entradas.map(({ url, alternativas }) => {
    const enlaces = Object.entries(alternativas)
      .map(([idioma, href]) => `<xhtml:link rel="alternate" hreflang="${idioma}" href="${href}"/>`)
      .join('')
    return `<url><loc>${url}</loc>${enlaces}</url>`
  })
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">${filas.join('')}</urlset>`
}
```

Dos matices que importan: las direcciones deben escaparse si pueden contener `&` (cualquier librería XML lo hace; una concatenación de cadenas, no), y el fichero debe regenerarse en **cada construcción**, nunca editarse a mano.

## Buenas prácticas avanzadas

- **El mapa se genera, y refleja exactamente lo publicado.** Si una página sale del sitio, sale del mapa en la misma construcción; un mapa con direcciones que dan 404 resta confianza al resto.
- **Excluye por construcción, no por revisión.** Define una vez qué entra (completo en ese idioma, sin parámetros, sin redirección) y deja que el código lo aplique; revisar a ojo falla.
- **Mantén `robots.txt` casi vacío.** Cuanto más escribas, más posibilidades de bloquear algo por error. Una web pequeña suele necesitar `Allow: /` y la línea `Sitemap:`.
- **Distingue «no rastrear» de «no indexar».** Lo primero es `robots.txt`; lo segundo, `noindex`. Combinar las dos reglas sobre la misma página hace que una anule a la otra.
- **No indexes los entornos de prueba.** Un subdominio de pruebas con la web duplicada compite con la de producción; protégelo con contraseña o con `noindex`, no solo con un `robots.txt`.

## Documentación oficial

- [Crear un `robots.txt` (Google)](https://developers.google.com/search/docs/crawling-indexing/robots/create-robots-txt) — sintaxis, ubicación y qué hace cada regla; empieza por la sección de reglas.
- [Introducción a `robots.txt` (Google)](https://developers.google.com/search/docs/crawling-indexing/robots/intro) — para qué sirve y, sobre todo, para qué no.
- [Crear un sitemap (Google)](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap) — límites, formato y cómo se envía.
- [Protocolo de Sitemaps](https://www.sitemaps.org/protocol.html) — la especificación del formato.

---

*En resumen: `robots.txt` avisa de por dónde no pasar y el sitemap invita a conocer las páginas; ambos son pistas, y el mapa debe generarse con la misma tabla que las canónicas.*
