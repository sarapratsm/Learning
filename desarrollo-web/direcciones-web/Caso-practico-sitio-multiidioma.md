# Caso práctico: un sitio estático multiidioma, paso a paso

## ¿Qué es?

Un recorrido de principio a fin, con código, por todo lo que una web estática en varios idiomas debe declarar sobre sus direcciones: una dirección base única, la lista de versiones por idioma de cada página, la raíz que reparte a las personas visitantes, el mapa del sitio y el `robots.txt`. Las fichas anteriores explican cada pieza por separado; aquí se montan juntas sobre una tienda online ficticia.

## ¿Por qué existe?

Cada pieza suelta es sencilla. Lo difícil es que **no se contradigan**: que la canónica de una página, sus `hreflang` y su entrada en el mapa digan lo mismo, que ninguna dirección se escriba a mano en tres sitios y que lo que no existe en un idioma no aparezca declarado en ninguna parte. Este caso práctico propone un diseño en el que todo sale de **una sola tabla** y de **una sola dirección base**, de modo que las incoherencias no tengan dónde nacer.

> Si has trabajado con bases de datos, piensa en la tabla de direcciones como la *fuente de verdad* y en las etiquetas, el mapa y los tests como *vistas* calculadas a partir de ella.

## ¿Cuándo y para qué se usa?

Cuando construyes una web de contenido (tienda, blog, web corporativa) que se publica como ficheros estáticos en varios idiomas y quieres que los buscadores muestren a cada persona la versión de su idioma. El ejemplo usa Next.js con exportación estática, pero la idea de la tabla única sirve con cualquier generador de sitios.

---

## El escenario

Una tienda ficticia en `https://tienda.example`, con tres idiomas (`es`, `en`, `fr`) y estas páginas:

| Página | `es` | `en` | `fr` |
|---|---|---|---|
| Inicio | `/es/` | `/en/` | `/fr/` |
| Contacto | `/es/contacto/` | `/en/contact/` | `/fr/contact/` |
| Zapatilla «Trail Runner» | `/es/zapatillas/trail-runner/` | `/en/shoes/trail-runner/` | *(no traducida todavía)* |

El producto aún no está disponible en francés. Ese hueco es deliberado: servirá para comprobar que una página **solo declara las versiones que existen**.

Las direcciones llevan el idioma delante y terminan en `/`. Con `trailingSlash: true` en `next.config`, `/es/contacto` y `/es/contacto/` serían direcciones distintas para un buscador, así que se escribe siempre una sola forma (ver [Direcciones y rutas](Direcciones-y-rutas.md)).

## Paso 1: la dirección base, una sola vez

La dirección base es un valor de configuración, no un texto repetido por el código:

```ts
// config/sitio.ts
export const SITIO = {
  url: 'https://tienda.example', // sin barra final
} as const
```

Y una función que convierte una ruta interna en absoluta, para todo lo que **no** pasa por la API de metadatos de Next.js:

```ts
// lib/urls.ts
import { SITIO } from '@/config/sitio'

export function urlAbsoluta(ruta: string): string {
  if (!ruta.startsWith('/')) throw new Error(`La ruta debe empezar por "/": ${ruta}`)
  return `${SITIO.url}${ruta}`
}

export function rutaDe(idioma: string, direccion = ''): string {
  return direccion === '' ? `/${idioma}/` : `/${idioma}/${direccion}/`
}
```

```ts
urlAbsoluta('/es/contacto/') // 'https://tienda.example/es/contacto/'
rutaDe('en', 'shoes/trail-runner') // '/en/shoes/trail-runner/'
```

Para los metadatos de las páginas (canónica, `hreflang`, Open Graph), Next.js completa las rutas relativas con `metadataBase`, que lee el mismo valor:

```tsx
// app/[lang]/layout.tsx
import type { Metadata } from 'next'
import { SITIO } from '@/config/sitio'

export const metadata: Metadata = {
  metadataBase: new URL(SITIO.url),
}
```

Reparto de papeles: **las páginas escriben rutas relativas**; `metadataBase` y `urlAbsoluta` son los únicos sitios donde aparece el dominio. Si algún día cambia el dominio, se cambia `SITIO.url` y nada más. El test más barato de esta capa:

```ts
it('urlAbsoluta antepone la base y rechaza rutas sin barra inicial', () => {
  expect(urlAbsoluta('/en/')).toBe('https://tienda.example/en/')
  expect(() => urlAbsoluta('en/')).toThrow()
})
```

## Paso 2: la tabla y la función `versionesDe`

### La tabla de direcciones

Para cada idioma, un mapa de **clave** a **dirección sin prefijo de idioma**. La clave es la misma en todos los idiomas: es lo que dice «este es el mismo contenido»; la dirección cambia porque se escribe a mano en cada idioma.

```ts
// content/direcciones.ts
export type Idioma = 'es' | 'en' | 'fr'
export type Tabla = Partial<Record<Idioma, Record<string, string>>>

export const IDIOMAS: Idioma[] = ['es', 'en', 'fr']

export const direcciones: Tabla = {
  es: { contacto: 'contacto', 'producto/trail-runner': 'zapatillas/trail-runner' },
  en: { contacto: 'contact', 'producto/trail-runner': 'shoes/trail-runner' },
  fr: { contacto: 'contact' }, // el producto no está traducido: no tiene entrada
}
```

La regla de oro: **si un contenido no está completo en un idioma, no está en la tabla de ese idioma**. Nadie escribe una excepción en otro sitio.

La portada no tiene dirección propia (es la raíz del idioma). Se trata con una clave reservada que se añade al leer la tabla:

```ts
export function conInicio(tabla: Tabla, idiomas: Idioma[]): Tabla {
  return Object.fromEntries(
    idiomas.map((lang) => [lang, { inicio: '', ...tabla[lang] }]),
  ) as Tabla
}
```

Conviene un test que garantice que ninguna página real se llame `inicio`; de lo contrario, la clave reservada la pisaría sin avisar.

### La función pura

`versionesDe` recibe la tabla, el idioma actual y la clave, y devuelve todo lo que cualquier etiqueta o mapa necesita:

```ts
// lib/versiones.ts
import { rutaDe } from './urls'
import type { Idioma, Tabla } from '@/content/direcciones'

// x-default es la raíz de la web: la página de entrada que elige el idioma según el navegador.
export const RUTA_RAIZ = '/'

export interface Versiones {
  canonica: string
  idiomas: Partial<Record<Idioma, string>>
  porDefecto: string
}

export function versionesDe(tabla: Tabla, idioma: Idioma, clave: string): Versiones {
  const idiomas: Partial<Record<Idioma, string>> = {}
  for (const [lang, rutas] of Object.entries(tabla) as [Idioma, Record<string, string>][]) {
    if (clave in rutas) idiomas[lang] = rutaDe(lang, rutas[clave])
  }
  const canonica = idiomas[idioma]
  if (canonica === undefined) throw new Error(`«${clave}» no existe en «${idioma}»`)
  return { canonica, idiomas, porDefecto: RUTA_RAIZ }
}
```

Con la tabla del escenario:

```ts
versionesDe(conInicio(direcciones, IDIOMAS), 'es', 'producto/trail-runner')
// {
//   canonica: '/es/zapatillas/trail-runner/',
//   idiomas: {
//     es: '/es/zapatillas/trail-runner/',
//     en: '/en/shoes/trail-runner/',
//   },
//   porDefecto: '/',
// }
```

No aparece `fr`: no hay un `if` especial para «lo que falta». Simplemente no está en la tabla.

### Reglas que salen gratis

- **Solo se declara lo que existe.** La página del producto no menciona el francés. Si faltara también el inglés, tampoco se declararía la versión `en`, pero `x-default` seguiría ahí.
- **Reciprocidad.** La versión `es` declara la `en` y la `en` declara la `es`, porque las dos leen la misma tabla y llaman a la misma función.
- **La canónica es siempre la propia.** La versión `es` no apunta a la `en` como «la buena»: cada versión es la preferida de sí misma.
- **`x-default` es la página que se muestra a quien no encaja en ningún idioma, y aquí es la raíz.** La raíz `/` es una página que elige idioma según el navegador, justo el tipo de página para el que se diseñó la etiqueta (ver [Canónica y `hreflang`](Canonica-y-hreflang.md)). Es la misma en todas las páginas, exista o no la versión inglesa. Si el criterio cambiara, se cambia en esta función y se aplica en todas partes.

### De `versionesDe` a las etiquetas

Una segunda función traduce el resultado a la API de metadatos de Next.js. Es el **único** lugar que construye `alternates`:

```ts
// lib/metadatos.ts
import type { Metadata } from 'next'
import { conInicio, direcciones, IDIOMAS, type Idioma } from '@/content/direcciones'
import { versionesDe } from './versiones'

interface Datos { idioma: Idioma; clave: string; titulo: string; descripcion: string }

export function metadatosDe({ idioma, clave, titulo, descripcion }: Datos): Metadata {
  const v = versionesDe(conInicio(direcciones, IDIOMAS), idioma, clave)
  return {
    title: titulo,
    description: descripcion,
    alternates: {
      canonical: v.canonica,
      languages: { ...v.idiomas, 'x-default': v.porDefecto },
    },
    openGraph: { title: titulo, description: descripcion, url: v.canonica, type: 'website' },
  }
}
```

Y cada página la usa sin escribir una sola etiqueta:

```tsx
// app/[lang]/zapatillas/[slug]/page.tsx (esquema)
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { lang } = await params
  return metadatosDe({
    idioma: lang as Idioma,
    clave: 'producto/trail-runner',
    titulo: 'Trail Runner',
    descripcion: 'Zapatilla de montaña con suela de agarre.',
  })
}
```

Con `metadataBase` activo, el HTML de `/es/zapatillas/trail-runner/` incluye:

```html
<link rel="canonical" href="https://tienda.example/es/zapatillas/trail-runner/">
<link rel="alternate" hreflang="es" href="https://tienda.example/es/zapatillas/trail-runner/">
<link rel="alternate" hreflang="en" href="https://tienda.example/en/shoes/trail-runner/">
<link rel="alternate" hreflang="x-default" href="https://tienda.example/">
```

Sin `fr`, porque el producto no existe en francés, y con `x-default` hacia la raíz. Los detalles de cada etiqueta están en [Canónica y `hreflang`](Canonica-y-hreflang.md) y la API de Next.js en [Metadatos en Next.js](Metadatos-en-Next-js.md).

Una advertencia sobre las direcciones con parámetros, como `/es/zapatillas/?talla=42`: con exportación estática el HTML es el mismo con y sin parámetros, y los parámetros no llegan a `generateMetadata`. La canónica del listado es, por tanto, siempre la del listado sin parámetros, sin ninguna lógica adicional.

### Pruebas con tablas inventadas

Como `versionesDe` es pura, se prueba sin tocar el contenido real, y los casos raros (un contenido sin versión en inglés, incompleto en un idioma) se cubren **inventando la tabla**:

```ts
import { describe, expect, it } from 'vitest'
import { versionesDe } from './versiones'

const tabla = {
  es: { 'producto/a': 'zapatillas/a', 'producto/solo-es': 'zapatillas/solo-es' },
  en: { 'producto/a': 'shoes/a' },
  fr: {},
}

describe('versionesDe', () => {
  it('declara solo los idiomas en los que existe', () => {
    expect(versionesDe(tabla, 'es', 'producto/a').idiomas).toEqual({
      es: '/es/zapatillas/a/',
      en: '/en/shoes/a/',
    })
  })

  it('la reciprocidad sale de usar la misma tabla', () => {
    const desdeEs = versionesDe(tabla, 'es', 'producto/a').idiomas
    const desdeEn = versionesDe(tabla, 'en', 'producto/a').idiomas
    expect(desdeEn).toEqual(desdeEs)
  })

  it('sin versión en inglés se declara igualmente la raíz como x-default', () => {
    const v = versionesDe(tabla, 'es', 'producto/solo-es')
    expect(v.idiomas.en).toBeUndefined()
    expect(v.porDefecto).toBe('/')
  })

  it('pedir una clave que no existe en ese idioma es un error', () => {
    expect(() => versionesDe(tabla, 'en', 'producto/solo-es')).toThrow()
  })
})
```

## Paso 3: la raíz de la web

Quien entra por `https://tienda.example/` no está en ningún idioma. Hace falta una página en `public/index.html`, escrita a mano, que cumpla tres cometidos: ser la página `x-default` para los buscadores, ofrecer enlaces visibles a cada idioma y llevar a la persona al suyo.

```html
<!-- public/index.html -->
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Tienda</title>
    <link rel="canonical" href="https://tienda.example/" />
    <link rel="alternate" hreflang="es" href="https://tienda.example/es/" />
    <link rel="alternate" hreflang="en" href="https://tienda.example/en/" />
    <link rel="alternate" hreflang="fr" href="https://tienda.example/fr/" />
    <link rel="alternate" hreflang="x-default" href="https://tienda.example/" />
  </head>
  <body>
    <nav>
      <a href="/es/">Español</a> · <a href="/en/">English</a> · <a href="/fr/">Français</a>
    </nav>
    <script>
      const soportados = ['es', 'en', 'fr']
      const lenguas = navigator.languages && navigator.languages.length ? navigator.languages : []
      const idioma =
        lenguas.map((l) => l.split('-')[0].toLowerCase()).find((c) => soportados.includes(c)) || 'en'
      location.replace('/' + idioma + '/')
    </script>
  </body>
</html>
```

Qué hace cada parte:

- **Metadatos:** la raíz declara las versiones por idioma y se declara a sí misma como `x-default`. Como todas las páginas apuntan de vuelta a ella con ese mismo `x-default` (paso 2), el conjunto es recíproco y los buscadores lo tienen en cuenta. Sin `noindex` ni `<meta http-equiv="refresh">`: debe poder indexarse como puerta de entrada.
- **Enlaces visibles:** si el script no se ejecuta (un robot, JavaScript desactivado), la persona o el robot ve tres enlaces normales.
- **Script:** `navigator.languages` es la lista de idiomas preferidos, por ejemplo `['de-DE', 'fr-FR']`. Se queda con el código base (`de`, `fr`), toma el primero soportado (`fr`) y, si ninguno lo está o la lista está vacía o no existe, usa `en`. `location.replace` evita que la raíz quede en el historial.

No usa la IP ni cookies: solo lo que el navegador ya declara. La raíz es el **respaldo** de la redirección que idealmente hace el servidor con un `302` leyendo `Accept-Language` (ver [Redirecciones: 301, 302 y por idioma](Redirecciones-e-idioma.md)); con una exportación estática no hay servidor propio, y esta página da el mismo resultado sin él.

El `html` de la raíz está escrito a mano y **no** puede leer `config/sitio.ts`, así que sus direcciones absolutas son un duplicado. Un test lo vigila:

```ts
import { readFileSync } from 'node:fs'
import { SITIO } from '@/config/sitio'
import { IDIOMAS } from '@/content/direcciones'

it('la raíz estática usa la dirección base y los idiomas de la configuración', () => {
  const html = readFileSync('public/index.html', 'utf8')
  for (const lang of IDIOMAS) {
    expect(html).toContain(`hreflang="${lang}" href="${SITIO.url}/${lang}/"`)
    expect(html).toContain(`<a href="/${lang}/">`)
  }
  expect(html).toContain(`hreflang="x-default" href="${SITIO.url}/"`)
  expect(html).not.toContain('noindex')
})
```

Si se añade un idioma y se olvida actualizar el fichero, el test falla.

### Probar la redirección con Playwright

La documentación de Playwright garantiza que la opción `locale` cambia `navigator.language` y la cabecera `Accept-Language`, pero no dice nada de `navigator.languages`. Para que la prueba sea determinista, se fija la lista explícitamente antes de que cargue la página:

```ts
import { expect, test } from '@playwright/test'

function conIdiomas(lenguas: string[]) {
  return async ({ page }: { page: import('@playwright/test').Page }) => {
    await page.addInitScript((l) => {
      Object.defineProperty(navigator, 'languages', { get: () => l })
    }, lenguas)
  }
}

test('una lista con idioma soportado va a ese idioma', async ({ page }) => {
  await conIdiomas(['de-DE', 'fr-FR'])({ page })
  await page.goto('/')
  await expect(page).toHaveURL(/\/fr\/$/)
})

test('sin ningún idioma soportado va a /en/', async ({ page }) => {
  await conIdiomas(['ja-JP'])({ page })
  await page.goto('/')
  await expect(page).toHaveURL(/\/en\/$/)
})

test('una lista vacía va a /en/', async ({ page }) => {
  await conIdiomas([])({ page })
  await page.goto('/')
  await expect(page).toHaveURL(/\/en\/$/)
})

test('una página que no es la raíz no redirige', async ({ page }) => {
  await conIdiomas(['fr-FR'])({ page })
  await page.goto('/es/contacto/')
  await expect(page).toHaveURL(/\/es\/contacto\/$/)
})

test('la raíz muestra los tres enlaces sin JavaScript', async ({ browser }) => {
  const contexto = await browser.newContext({ javaScriptEnabled: false })
  const page = await contexto.newPage()
  await page.goto('/')
  await expect(page.getByRole('link')).toHaveCount(3)
  await contexto.close()
})
```

## Paso 4: el mapa del sitio y el `robots.txt`

Ambos se generan en la construcción desde ficheros de código, y ambos leen **la misma tabla** que las etiquetas.

```ts
// app/sitemap.ts
import type { MetadataRoute } from 'next'
import { conInicio, direcciones, IDIOMAS } from '@/content/direcciones'
import { urlAbsoluta } from '@/lib/urls'
import { versionesDe } from '@/lib/versiones'

export const dynamic = 'force-static'

export default function sitemap(): MetadataRoute.Sitemap {
  const tabla = conInicio(direcciones, IDIOMAS)
  return IDIOMAS.flatMap((idioma) =>
    Object.keys(tabla[idioma] ?? {}).map((clave) => {
      const v = versionesDe(tabla, idioma, clave)
      return {
        url: urlAbsoluta(v.canonica),
        alternates: {
          languages: {
            ...Object.fromEntries(Object.entries(v.idiomas).map(([l, r]) => [l, urlAbsoluta(r)])),
            'x-default': urlAbsoluta(v.porDefecto),
          },
        },
      }
    }),
  )
}
```

`export const dynamic = 'force-static'` marca la ruta como estática. La guía de exportación estática de Next.js lo pide para los *Route Handlers* y `sitemap.ts` y `robots.ts` funcionan como tales; añadirlo es inocuo y evita un error de construcción si tu versión lo exige.

Aquí sí hay que escribir **direcciones absolutas**: `metadataBase` no se aplica a este fichero, por eso se usa `urlAbsoluta`. El resultado en `out/sitemap.xml` incluye, por cada dirección, sus alternativas con elementos `xhtml:link` (soporte de `alternates` en el mapa desde Next.js 14.2):

```xml
<url>
  <loc>https://tienda.example/es/zapatillas/trail-runner/</loc>
  <xhtml:link rel="alternate" hreflang="es" href="https://tienda.example/es/zapatillas/trail-runner/" />
  <xhtml:link rel="alternate" hreflang="en" href="https://tienda.example/en/shoes/trail-runner/" />
  <xhtml:link rel="alternate" hreflang="x-default" href="https://tienda.example/" />
</url>
```

Cada versión es su propia entrada `<url>`, y todas llevan la misma lista de alternativas, con el `x-default` hacia la raíz, igual que las etiquetas de sus páginas. Que la raíz aparezca como alternativa no la convierte en una entrada del mapa (véase la tabla siguiente). Como ambas salen de `versionesDe`, **no pueden discrepar**.

### Qué entra y qué no, sin lista de exclusiones

| Entra | No entra | Por qué |
|---|---|---|
| Inicio de cada idioma | La página 404 | No tiene dirección en la tabla |
| Contacto y productos | `/es/zapatillas/?talla=42` | Los parámetros no son una clave de la tabla |
| El producto en `es` y `en` | El producto en `fr` | No existe en la tabla de `fr` |
| | La raíz `/` | Es la página `x-default`, no una dirección de idioma |
| | Una dirección antigua que redirige | No está en la tabla; solo la actual |

El mapa no tiene ninguna lista de exclusiones. Lo que no debe estar **no está en la tabla**, y el mapa solo recorre la tabla. Es el mismo mecanismo que mantiene las etiquetas honestas.

### El `robots.txt`

```ts
// app/robots.ts
import type { MetadataRoute } from 'next'
import { urlAbsoluta } from '@/lib/urls'

export const dynamic = 'force-static'

export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: '*', allow: '/' },
    sitemap: urlAbsoluta('/sitemap.xml'),
  }
}
```

```text
User-Agent: *
Allow: /

Sitemap: https://tienda.example/sitemap.xml
```

Parece que falta algo: no bloquea nada, tampoco las direcciones con parámetros. Es deliberado. Un robot **no puede leer** la canónica de una página que tiene prohibido visitar; si bloqueas `/es/zapatillas/?talla=42`, nadie descubre que su canónica es `/es/zapatillas/`. Para evitar contenido duplicado se usa la canónica, no el bloqueo. (Una advertencia: `robots.txt` **no es** un mecanismo de seguridad ni de privacidad; es una petición educada.)

### Pruebas del mapa y del `robots.txt`

```ts
import { describe, expect, it } from 'vitest'
import robots from './robots'
import sitemap from './sitemap'

describe('sitemap', () => {
  const entradas = sitemap()
  const urls = entradas.map((e) => e.url)

  it('todas las direcciones son absolutas y no llevan parámetros', () => {
    expect(urls.every((u) => u.startsWith('https://tienda.example/'))).toBe(true)
    expect(urls.some((u) => u.includes('?'))).toBe(false)
  })

  it('no incluye la raíz', () => {
    expect(urls).not.toContain('https://tienda.example/')
  })

  it('el producto no aparece en francés', () => {
    expect(urls.some((u) => u.startsWith('https://tienda.example/fr/') && u.includes('shoes'))).toBe(false)
    expect(urls.some((u) => u.startsWith('https://tienda.example/fr/contact/'))).toBe(true)
  })

  it('cada entrada declara sus alternativas con x-default hacia la raíz', () => {
    const producto = entradas.find((e) => e.url.endsWith('/es/zapatillas/trail-runner/'))
    const languages = producto?.alternates?.languages ?? {}
    expect(Object.keys(languages).sort()).toEqual(['en', 'es', 'x-default'])
    expect(languages['x-default']).toBe('https://tienda.example/')
  })
})

describe('robots', () => {
  it('permite todo y declara el mapa', () => {
    const r = robots()
    expect(r.rules).toEqual({ userAgent: '*', allow: '/' })
    expect(r.sitemap).toBe('https://tienda.example/sitemap.xml')
  })
})
```

Y un test sobre la construcción (`out/`) que cierre el círculo:

```bash
next build
grep -c '<url>' out/sitemap.xml
cat out/robots.txt
grep -o '<link rel="canonical"[^>]*>' out/es/zapatillas/trail-runner/index.html
```

## Errores frecuentes

- **Escribir la tabla en dos sitios**: una para las etiquetas y otra para el mapa. Terminan divergiendo.
- **Dominio escrito a mano en el código**: cambiar de dominio exige buscar y sustituir; con `SITIO.url` es un valor.
- **Olvidar la barra final** en una ruta y no en otra: para el buscador son direcciones distintas.
- **Poner `noindex` en la raíz** «porque solo redirige»: la raíz es la `x-default` y debe poder indexarse.
- **Bloquear en `robots.txt` lo que quieres desindexar**: el robot no ve la canónica ni el `noindex`.
- **Probar la redirección solo con un idioma**: hay que cubrir también el respaldo y la lista vacía.

## Buenas prácticas avanzadas

- **Haz que lo imposible sea imposible, no que esté prohibido.** Una incoherencia entre etiquetas y mapa no debe evitarse con una revisión: debe ser irrepresentable porque ambos leen de la misma función. Cada vez que añadas una regla («`x-default` es siempre la raíz»), pregúntate si vive en un solo sitio.
- **Que las etiquetas de la raíz no queden sin respuesta.** Una raíz que declara los idiomas sin que las portadas apunten de vuelta a ella tiene etiquetas que los buscadores ignoran. Con `x-default` hacia la raíz en todas las páginas, la ida y la vuelta existen, y un test que compruebe la reciprocidad lo vigila.
- **Una clave que significa «el mismo contenido» en todos los idiomas.** La tabla funciona porque `producto/trail-runner` es estable aunque su dirección cambie; si usas la dirección como identidad, un cambio de título rompe la reciprocidad.
- **Cubre los casos raros con tablas inventadas, no con contenido real.** El contenido real casi siempre está completo; los casos de «falta el inglés» solo se ejercitan con datos de prueba.
- **Vigila lo que está duplicado a mano.** La raíz estática no puede leer la configuración; un test que compare su contenido con la fuente evita que se desincronice en silencio.
- **Valida `out/`, no solo el código.** Un test que lea los ficheros generados detecta lo que ningún test unitario ve: una canónica ausente o un mapa con direcciones relativas.
- **Deja claro qué no hace esta capa.** Una exportación estática no puede emitir un `302` ni cabeceras de exclusión para un entorno de pruebas; eso se configura en el servidor y conviene dejarlo anotado como pendiente, no olvidado.

## Documentación oficial

- [`generateMetadata` y `metadataBase` (Next.js)](https://nextjs.org/docs/app/api-reference/functions/generate-metadata) — campos de `Metadata`, `alternates` y cómo `metadataBase` completa rutas relativas.
- [`sitemap.xml` (Next.js)](https://nextjs.org/docs/app/api-reference/file-conventions/metadata/sitemap) — el tipo `MetadataRoute.Sitemap` y las alternativas por idioma.
- [`robots.txt` (Next.js)](https://nextjs.org/docs/app/api-reference/file-conventions/metadata/robots) — la forma de `rules` y `sitemap`.
- [Exportación estática (Next.js)](https://nextjs.org/docs/app/guides/static-exports) — `output: 'export'`, `trailingSlash` y qué rutas deben ser estáticas.
- [Versiones localizadas de una página (Google)](https://developers.google.com/search/docs/specialty/international/localized-versions) — la referencia sobre `hreflang`, reciprocidad y `x-default`.
- [Emulación de idioma en Playwright](https://playwright.dev/docs/emulation) — la opción `locale` y sus límites.

## Recursos didácticos

- [Fichas de esta colección](README.md) — cada pieza del caso práctico tiene su ficha conceptual: [Direcciones y rutas](Direcciones-y-rutas.md), [Canónica y `hreflang`](Canonica-y-hreflang.md), [`robots.txt` y sitemap](Robots-y-sitemap.md) y [Redirecciones](Redirecciones-e-idioma.md).
- [Webs multiidioma](../webs-multiidioma/README.md) — el diseño de una web en varios idiomas más allá de las direcciones.

---

*En resumen: pon la dirección base y la tabla de versiones por idioma en un solo sitio y calcula todo lo demás (etiquetas, raíz, mapa y pruebas) a partir de ellas, de modo que no haya dónde guardar una contradicción.*
