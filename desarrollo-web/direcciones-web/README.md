# Direcciones web y SEO técnico — Guía de tecnologías

Todo lo que una web declara **sobre sus propias direcciones** para que buscadores y aplicaciones la entiendan: qué es una dirección base y por qué conviene escribirla una sola vez, cuál es la dirección preferida de cada página, cómo se enlazan las versiones por idioma, qué dicen `robots.txt` y el mapa del sitio, cómo se ve un enlace al compartirlo, qué son los datos estructurados, qué redirección usar en cada caso y cómo se genera todo esto en una web de Next.js exportada como ficheros estáticos.

Está pensada para perfiles backend que programan a diario pero no han tenido que preparar una web para buscadores. Cada ficha parte del problema que resuelve, con el fallo y su arreglo, y se apoya en la documentación oficial de Google, de Next.js y de los estándares.

---

## Orden de lectura recomendado

### 1. Las bases: qué es una dirección

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Direcciones y rutas](Direcciones-y-rutas.md) | La anatomía de una dirección, la dirección base, absolutas frente a relativas y la barra final. Todo lo demás se apoya aquí. |

### 2. Decir a los buscadores cuál es cada página

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 2 | [Canónica y `hreflang`](Canonica-y-hreflang.md) | La dirección preferida de cada página y cómo se declaran sus versiones por idioma, con reciprocidad y `x-default`. |
| 3 | [`robots.txt` y sitemap](Robots-y-sitemap.md) | Dónde pueden entrar los robots y la lista de direcciones que quieres que conozcan, con sus alternativas por idioma. |
| 4 | [Vista previa al compartir: Open Graph](Vista-previa-Open-Graph.md) | Qué título, descripción e imagen aparecen cuando alguien pega tu enlace. |
| 5 | [Datos estructurados con JSON-LD](Datos-estructurados-JSON-LD.md) | `Organization` y `BreadcrumbList`, y el escape de `<` que evita una inyección. |

### 3. Mover direcciones y generarlo todo

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 6 | [Redirecciones: 301, 302 y por idioma](Redirecciones-e-idioma.md) | Cuándo es permanente y cuándo temporal, y cómo redirigir la raíz según el idioma del navegador. |
| 7 | [Metadatos en Next.js con exportación estática](Metadatos-en-Next-js.md) | `metadataBase`, `alternates`, `sitemap.ts` y `robots.ts`, y qué no puede hacer una exportación estática. |

---

> Piezas relacionadas: [SEO web](../seo-web/README.md) para el panorama general (rastreo, contenido, rendimiento y Search Console), [Webs multiidioma](../webs-multiidioma/README.md) para el diseño de una web en varios idiomas y [HTTP](../de-wpf-a-web/HTTP.md) para los códigos de estado y las cabeceras.
