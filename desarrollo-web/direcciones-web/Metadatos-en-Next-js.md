# Metadatos en Next.js con exportación estática

## ¿Qué es?

Es la forma que tiene Next.js (App Router) de generar las etiquetas del `<head>` que has visto en esta colección (título, descripción, canónica, `hreflang`, Open Graph) y los ficheros `sitemap.xml` y `robots.txt`, a partir de objetos TypeScript en lugar de HTML escrito a mano. Con `output: 'export'` todo se calcula **en la construcción** y se guarda como ficheros estáticos.

## ¿Por qué existe?

Escribir `<link rel="canonical">` y `<meta property="og:...">` a mano en cada página no escala, y es fácil que una se quede sin su etiqueta o con una dirección relativa. La API de metadatos centraliza el trabajo: tú describes los datos y Next.js genera el HTML correcto, combina lo que declara el layout con lo que declara la página y, con `metadataBase`, convierte las direcciones relativas en absolutas.

## ¿Cuándo y para qué se usa?

En cualquier proyecto Next.js con App Router donde el SEO importe. Con exportación estática, en una web de contenido (tienda, blog, web corporativa) que se publica como carpeta de ficheros en cualquier servidor, sin Node en producción.

---

## Declarar metadatos: `metadata` y `generateMetadata`

Hay dos formas, y no puedes usar las dos en el mismo segmento de ruta:

```tsx
// app/[lang]/contacto/page.tsx — datos fijos: objeto `metadata`
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Contacto',
  description: 'Escríbenos o reserva una llamada.',
}
```

```tsx
// app/[lang]/productos/[slug]/page.tsx — datos que dependen de la ruta: `generateMetadata`
import type { Metadata } from 'next'

type Props = { params: Promise<{ lang: string; slug: string }> }

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { lang, slug } = await params
  const producto = await cargarProducto(lang, slug) // se ejecuta durante `next build`
  return { title: producto.titulo, description: producto.descripcion }
}
```

Dos reglas que conviene conocer:

- Solo funcionan en **Server Components**. Si tu página es un componente de cliente, deja `page.tsx` como servidor y mueve la interactividad a otro fichero.
- Next.js evalúa los metadatos **de la raíz hacia la página** y los combina con una mezcla *superficial*: cada clave que declara un segmento **sustituye por completo** a la del padre. Si el layout define `openGraph: { title, description }` y la página define `openGraph: { title }`, la descripción **desaparece**. Si la página no declara `openGraph`, hereda todo.

## `metadataBase`: de relativas a absolutas

Aquí enlaza con [Direcciones y rutas](Direcciones-y-rutas.md): canónica, `hreflang` y `og:image` necesitan direcciones absolutas. `metadataBase` te deja escribir rutas relativas en todos esos campos y Next las completa con tu dirección base:

```tsx
// app/[lang]/layout.tsx
import type { Metadata } from 'next'

export const metadata: Metadata = {
  metadataBase: new URL('https://ejemplo.com'),
}
```

```tsx
// en una página
export const metadata: Metadata = {
  alternates: { canonical: '/es/zapatillas/' },
  openGraph: { images: '/vista-previa.png' },
}
// → <link rel="canonical" href="https://ejemplo.com/es/zapatillas/" />
// → <meta property="og:image" content="https://ejemplo.com/vista-previa.png" />
```

Lo que dice la documentación:

- Se suele definir en el **layout raíz** para que lo hereden todas las rutas.
- **Usar una ruta relativa sin `metadataBase` rompe la construcción.** Es una red de seguridad útil.
- Si un campo ya trae una dirección absoluta, `metadataBase` se ignora.
- Puede incluir un subdominio o una ruta base (`https://ejemplo.com/tienda`).
- Una ruta que empieza por `/` se trata como **relativa al final de `metadataBase`**, y las barras duplicadas se normalizan: `/pagos` con la base `https://ejemplo.com` da `https://ejemplo.com/pagos`. Ojo: es distinto de lo que haría `new URL('/pagos', base)`, que sustituiría la ruta de la base.

## Canónica, `hreflang` y Open Graph

```tsx
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { lang } = await params
  return {
    title: 'Zapatillas',
    description: 'Calzado de running.',
    alternates: {
      canonical: '/es/zapatillas/',
      languages: {
        es: '/es/zapatillas/',
        en: '/en/shoes/',
        'x-default': '/en/shoes/',
      },
    },
    openGraph: {
      title: 'Zapatillas',
      description: 'Calzado de running.',
      url: '/es/zapatillas/',
      type: 'website',
      images: [{ url: '/vista-previa.png', width: 1200, height: 630 }],
    },
  }
}
```

Genera, ya con las direcciones absolutas:

```html
<link rel="canonical" href="https://ejemplo.com/es/zapatillas/" />
<link rel="alternate" hreflang="es" href="https://ejemplo.com/es/zapatillas/" />
<link rel="alternate" hreflang="en" href="https://ejemplo.com/en/shoes/" />
<link rel="alternate" hreflang="x-default" href="https://ejemplo.com/en/shoes/" />
<meta property="og:image" content="https://ejemplo.com/vista-previa.png" />
```

En un proyecto real, esas rutas no se escriben una a una: salen de una **función** que, dada la tabla de direcciones de un contenido, devuelve el bloque `alternates` y `openGraph` (ver la ficha de [`hreflang`](Canonica-y-hreflang.md)).

## La exportación estática

```ts
// next.config.ts
import type { NextConfig } from 'next'

const config: NextConfig = {
  output: 'export',
  trailingSlash: true, // `/es/zapatillas/` en lugar de `/es/zapatillas`
}

export default config
```

`next build` genera la carpeta `out/` con un HTML por ruta. Con `trailingSlash: true` cada ruta es una carpeta con su `index.html` (`out/es/zapatillas/index.html`); sin él, es un fichero `.html`. Esa elección debe coincidir con las direcciones de tus canónicas y de tu mapa (ver la primera ficha).

Qué **no** puedes usar con una exportación estática, según la documentación: las funciones que necesitan servidor, como `redirects`, `rewrites` y `headers` de `next.config`, el *proxy* (antes *middleware*), las rutas dinámicas sin `generateStaticParams()` o con `dynamicParams: true`, las Server Actions y la optimización de imágenes con el cargador por defecto.

Consecuencia directa: **no puedes redirigir la raíz según el idioma con Next.js**. Esa redirección va en el servidor web (ver [Redirecciones e idioma](Redirecciones-e-idioma.md)) o en una página estática de respaldo con un script.

Las rutas con parámetros, como `[lang]` o `[slug]`, necesitan `generateStaticParams` y, en una exportación, `dynamicParams = false`:

```tsx
export const dynamicParams = false

export function generateStaticParams() {
  return [{ lang: 'ca' }, { lang: 'es' }, { lang: 'en' }]
}
```

## `sitemap.ts` y `robots.ts`

Next.js tiene dos ficheros especiales en la raíz de `app/` que generan `sitemap.xml` y `robots.txt`. Son rutas de tipo *Route Handler*, y la guía de exportación estática indica que, con `output: 'export'`, hay que marcar esas rutas como estáticas con `export const dynamic = 'force-static'`. Añadir la línea es inocuo y evita un error de construcción si tu versión lo exige.

```ts
// app/sitemap.ts
import type { MetadataRoute } from 'next'

export const dynamic = 'force-static'

const BASE = 'https://ejemplo.com'

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    {
      url: `${BASE}/es/zapatillas/`,
      alternates: {
        languages: {
          es: `${BASE}/es/zapatillas/`,
          en: `${BASE}/en/shoes/`,
          'x-default': `${BASE}/en/shoes/`,
        },
      },
    },
    {
      url: `${BASE}/en/shoes/`,
      alternates: {
        languages: {
          es: `${BASE}/es/zapatillas/`,
          en: `${BASE}/en/shoes/`,
          'x-default': `${BASE}/en/shoes/`,
        },
      },
    },
  ]
}
```

Next.js lo convierte en un `sitemap.xml` con elementos `xhtml:link` por cada alternativa (disponible desde la versión 14.2). Aquí **sí** hay que escribir direcciones absolutas: `metadataBase` no se aplica a este fichero.

```ts
// app/robots.ts
import type { MetadataRoute } from 'next'

export const dynamic = 'force-static'

export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: '*', allow: '/' },
    sitemap: 'https://ejemplo.com/sitemap.xml',
  }
}
```

Produce:

```text
User-Agent: *
Allow: /

Sitemap: https://ejemplo.com/sitemap.xml
```

## Comprobar el resultado

Como todo está en `out/`, puedes verificarlo sin servidor y sin navegador:

```bash
next build
grep -o '<link rel="canonical"[^>]*>' out/es/zapatillas/index.html
grep -c 'hreflang' out/es/zapatillas/index.html
cat out/sitemap.xml
cat out/robots.txt
```

Y automatizarlo con un test que lea esos ficheros: es la forma de asegurar que **ninguna página sin canónica o sin `hreflang` llegue al despliegue**.

## Errores frecuentes

- **Rutas relativas sin `metadataBase`**: error de construcción (es lo que quieres: te avisa).
- **`openGraph` en el layout y otro `openGraph` en la página**: el de la página sustituye al completo, y pierdes campos.
- **`generateMetadata` en un componente de cliente**: solo funciona en servidor.
- **Usar `searchParams` para cambiar la canónica en un sitio estático**: no hay petición, así que no hay parámetros; la canónica es siempre la de la página sin ellos.
- **Olvidar `sitemap.ts`/`robots.ts` en `force-static`** con exportación estática, o copiar al mapa direcciones sin la base.
- **Barra final inconsistente** entre `trailingSlash`, las rutas del mapa y las canónicas.

## Buenas prácticas avanzadas

- **Una función `metadatosDe(...)` para todo.** Que ninguna página escriba `alternates` u `openGraph` a mano; así una regla (por ejemplo, «`x-default` es la inglesa si existe») se aplica en un único sitio.
- **El mapa y las canónicas leen de la misma tabla.** Si el mapa se escribe aparte, tarde o temprano discreparán.
- **`metadataBase` desde una configuración, no desde una cadena en el layout.** Cambiar de dominio o de entorno es cambiar un valor.
- **Valida la construcción en el CI.** Un test sobre `out/` (canónica, `hreflang` recíprocos, `og:image`, `sitemap.xml`, `robots.txt`) es más barato que descubrir el problema en Search Console.
- **Cuidado con la mezcla superficial de metadatos.** Si repartes `openGraph` entre layout y página, extrae lo común a una constante y haz *spread* para no perder campos.
- **Una exportación estática no sustituye la configuración del servidor.** Redirecciones, cabeceras de seguridad y exclusión del entorno de pruebas del índice se configuran donde se aloja la web.

## Documentación oficial

- [`generateMetadata` (Next.js)](https://nextjs.org/docs/app/api-reference/functions/generate-metadata) — todos los campos de `Metadata`, `metadataBase` con su tabla de composición y las reglas de mezcla; consulta primero `metadataBase` y `alternates`.
- [`sitemap.xml` (Next.js)](https://nextjs.org/docs/app/api-reference/file-conventions/metadata/sitemap) — el tipo `MetadataRoute.Sitemap` y la sección de sitemap localizado.
- [`robots.txt` (Next.js)](https://nextjs.org/docs/app/api-reference/file-conventions/metadata/robots) — la forma de `rules` y `sitemap`.
- [Exportación estática (Next.js)](https://nextjs.org/docs/app/guides/static-exports) — `output: 'export'`, `trailingSlash`, lo que no se soporta y cómo servir `out/`.

---

*En resumen: en Next.js estático describes los metadatos con objetos, `metadataBase` los vuelve absolutos y `sitemap.ts`/`robots.ts` generan los ficheros en la construcción; lo que necesita servidor, como las redirecciones, queda fuera.*
