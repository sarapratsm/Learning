# Direcciones y rutas

## ¿Qué es?

Una dirección web (*URL*) es el texto que identifica un recurso en internet: `https://ejemplo.com/es/productos/?color=azul`. Una **ruta** es la parte que dice dónde está dentro del sitio (`/es/productos/`), y una **dirección base** es el prefijo común a todas las direcciones de tu web (`https://ejemplo.com`).

## ¿Por qué existe?

Una página que funciona perfectamente en el navegador puede ser, para un buscador o para una aplicación de mensajería, una dirección ambigua: ¿la `/` del enlace significa la raíz de tu dominio o la de otro? ¿`/es/productos` y `/es/productos/` son la misma página? ¿`http` y `https` cuentan como dos sitios?

Cada etiqueta de SEO que verás en esta colección (canónica, `hreflang`, mapa del sitio, vista previa al compartir) está **fuera de la página donde la ve una persona**: la lee un robot en otro momento y desde otro sitio. Por eso la mayoría exige direcciones completas, y por eso conviene fijar de una vez cómo se escribe cada dirección de tu web.

## ¿Cuándo y para qué se usa?

Cada vez que algo necesita **nombrar** una página sin estar dentro de ella: la etiqueta que declara cuál es la dirección preferida, el mapa del sitio que las lista todas, la imagen que se muestra al compartir un enlace, el correo con un enlace a un pedido. Imagina una tienda online en tres idiomas: la ficha de un producto tiene tres direcciones, y cada documento que la menciona debe usar siempre exactamente la misma forma de cada una.

---

## Anatomía de una dirección

```text
https://ejemplo.com:443/es/productos/?color=azul&pagina=2#opiniones
└─┬──┘   └────┬─────┘└┬┘└─────┬─────┘└──────────┬────────┘└───┬───┘
esquema     host   puerto    ruta            parámetros    fragmento
```

- **Esquema**: `https` o `http`. Son sitios distintos para un buscador.
- **Host**: el dominio (`ejemplo.com`). `www.ejemplo.com` es otro host distinto, aunque sirva lo mismo.
- **Puerto**: casi nunca se escribe; `443` es el de `https`.
- **Ruta**: dónde está el recurso dentro del host. En la mayoría de servidores **distingue mayúsculas de minúsculas**: `/Productos/` y `/productos/` pueden ser dos páginas.
- **Parámetros** (*query string*): lo que va tras `?`. Sirven para filtrar o paginar; una misma página con otros parámetros es, para un buscador, otra dirección.
- **Fragmento**: lo que va tras `#`. Lo resuelve el navegador y **no se envía al servidor**, así que no identifica una página distinta.

Lo puedes comprobar con la clase `URL`, que existe en navegadores y en Node:

```ts
const url = new URL('https://ejemplo.com/es/productos/?color=azul&pagina=2#opiniones')

url.origin    // 'https://ejemplo.com'
url.pathname  // '/es/productos/'
url.search    // '?color=azul&pagina=2'
url.searchParams.get('color') // 'azul'
url.hash      // '#opiniones'
```

## Dirección base, direcciones absolutas y relativas

- Una dirección **absoluta** lleva esquema y host: `https://ejemplo.com/es/productos/`.
- Una dirección **relativa a la raíz** empieza por `/`: `/es/productos/`. Es relativa al host desde el que se lee.
- Una dirección **relativa a la página actual** no empieza por `/`: `../envios/`.

Dentro de tu HTML, las relativas son cómodas y funcionan. El problema aparece cuando la dirección la lee **otro**. Estas piezas piden dirección completa (esquema y host incluidos):

| Dónde aparece | Qué pasa con una relativa |
|---|---|
| Etiquetas `hreflang` | Google las exige completas: `//ejemplo.com/foo` o `/foo` no son válidas. |
| Entradas de un `sitemap.xml` | Deben ser absolutas y completamente cualificadas. |
| `og:image` en la vista previa | Debe ser absoluta. |
| `Sitemap:` en `robots.txt` | Debe ser una dirección completa. |
| Canónica (`rel="canonical"`) | Google admite relativas pero recomienda absolutas, porque pueden causar problemas a largo plazo, por ejemplo si se rastrea por error un sitio de pruebas. |

La solución es tener **una sola dirección base** en un único sitio de tu proyecto y construir todo lo demás a partir de ella:

```ts
// base.ts — el único sitio donde se escribe el dominio
const BASE = 'https://ejemplo.com' // sin barra final

export function urlAbsoluta(ruta: string): string {
  return new URL(ruta, BASE).toString()
}

urlAbsoluta('/es/productos/') // 'https://ejemplo.com/es/productos/'
```

Con esto, cambiar de dominio (o pasar del dominio de pruebas al de producción) es cambiar una línea. Si el dominio estuviera copiado en cien sitios, un cambio dejaría direcciones mezcladas.

> Ojo con la resolución de rutas: `new URL('/es/', 'https://ejemplo.com/tienda')` da `https://ejemplo.com/es/`, porque una ruta que empieza por `/` **sustituye** a la ruta de la base. Si tu sitio vive bajo un prefijo (`/tienda`), tendrás que añadirlo tú o usar una herramienta que lo gestione, como el `metadataBase` de Next.js que se ve en [Metadatos en Next.js](Metadatos-en-Next-js.md).

## La barra final

`/es/productos` y `/es/productos/` son **direcciones distintas**. Muchos servidores hacen que ambas funcionen o que una redirija a la otra, pero eso lo decide cada servidor y cada herramienta de construcción. La única excepción es la raíz del dominio: `https://ejemplo.com` y `https://ejemplo.com/` son la misma dirección, porque el navegador siempre pide la ruta `/`.

En un sitio **estático** la diferencia se nota en los ficheros que se generan:

| Convención | Fichero generado para `/es/productos` |
|---|---|
| Sin barra final | `es/productos.html` |
| Con barra final | `es/productos/index.html` |

Next.js, por ejemplo, genera la primera forma por defecto y la segunda con `trailingSlash: true`. Cuál elijas es indiferente; lo importante es que sea **la misma en todas partes**: los enlaces internos, la canónica, el mapa del sitio, las etiquetas `hreflang` y la vista previa. Si una parte escribe `/es/productos` y otra `/es/productos/`, cada visita pasa por una redirección o, peor, el buscador ve dos páginas con el mismo contenido.

## Errores frecuentes

- **Mezclar `http` y `https`**, o `www` y sin `www`. Elige una forma, y redirige las demás a ella.
- **Barra final incoherente** entre enlaces, mapa del sitio y canónica.
- **Mayúsculas y acentos** en la ruta: dos formas de escribir la misma página. Rutas en minúsculas, sin acentos y con guiones (`/es/zapatillas-de-running/`).
- **Dominio escrito a mano en muchos sitios**, en lugar de una dirección base única.
- **Creer que el fragmento (`#`) distingue páginas**: no llega al servidor y los buscadores lo ignoran como identidad de la página.

## Buenas prácticas avanzadas

- **Una única función construye las direcciones absolutas.** Que no exista código que concatene `'https://ejemplo.com' + ruta` por su cuenta: es la forma más habitual de acabar con barras dobles (`.com//es/`) o con un `http` que se coló.
- **Valida la dirección base al arrancar o al construir.** Debe empezar por `https://` y no terminar en `/`; un fallo aquí aparece en cientos de páginas a la vez, y es más barato que rompa la construcción.
- **Trata cada host como un sitio distinto en tus entornos.** El dominio de pruebas y el de producción deben tener cada uno su propia base, y el de pruebas no debería poder indexarse; una canónica relativa en pruebas se puede convertir sin querer en una canónica hacia producción o viceversa.
- **Las direcciones con parámetros no son páginas nuevas.** Si un filtro o una paginación cambian la dirección pero no el contenido principal, decide cuál es la forma preferida y decláralo con una canónica (siguiente ficha).

## Documentación oficial

- [Clase `URL` en MDN](https://developer.mozilla.org/en-US/docs/Web/API/URL) — qué propiedades tiene y cómo resuelve una ruta relativa contra una base; es lo primero que consultar si una dirección sale distinta de la esperada.
- [URL Standard (WHATWG)](https://url.spec.whatwg.org/) — la especificación normativa, para cuando la duda es qué dice el estándar sobre una dirección rara.
- [Consolidar direcciones duplicadas (Google)](https://developers.google.com/search/docs/crawling-indexing/consolidate-duplicate-urls) — qué considera Google la «misma» página en varias direcciones y cómo indicar la preferida.

---

*En resumen: una dirección base escrita una sola vez, una forma única de terminar las rutas y direcciones absolutas siempre que otro las lea.*
