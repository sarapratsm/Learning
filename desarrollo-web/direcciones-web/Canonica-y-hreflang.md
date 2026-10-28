# Dirección canónica, `hreflang` y `x-default`

## ¿Qué es?

Son tres etiquetas de la cabecera (`<head>`) de una página que le cuentan a los buscadores **qué dirección es la preferida** de esa página (la *canónica*) y **qué versiones por idioma existen** de ella (`hreflang`, con un valor de reserva llamado `x-default`).

## ¿Por qué existe?

Una misma página puede tener muchas direcciones: con y sin parámetros de seguimiento, con y sin barra final, en tres idiomas. Para un buscador son páginas distintas con contenido casi idéntico, y tiene que **adivinar** cuál mostrar. Si adivina mal, enseña la versión en inglés a quien busca en castellano, o reparte las señales de una página entre varias direcciones y ninguna posiciona bien.

Estas etiquetas sustituyen la adivinanza por una declaración explícita.

> Si ya conoces las claves de una base de datos, piensa en la canónica como la **clave primaria** de una página y en `hreflang` como las **claves foráneas** que la enlazan con sus traducciones.

## ¿Cuándo y para qué se usa?

- En **toda web con más de un idioma**: cada página declara las versiones que tiene.
- En **cualquier web con direcciones duplicadas**: listados con filtros, páginas con parámetros de campañas, versiones con y sin barra final.
- Para los escenarios de una tienda online: la ficha de un producto en `/es/`, `/en/` y `/ca/`, o el listado de zapatillas con `?color=azul&pagina=2`.

---

## La dirección canónica

Se declara con un `<link>` en el `<head>`:

```html
<link rel="canonical" href="https://ejemplo.com/es/zapatillas/" />
```

Reglas que dan buen resultado:

- **Usa una dirección absoluta.** Google admite relativas, pero las desaconseja.
- **La página se declara canónica de sí misma** (canónica autorreferencial). No hace falta que haya duplicados para ponerla.
- **Una versión por idioma nunca es canónica de otro idioma.** La canónica de `/es/zapatillas/` es `/es/zapatillas/`, no `/en/shoes/`. Si lo hicieras, estarías diciendo «la página en castellano es un duplicado de la inglesa» y la castellana dejaría de mostrarse.
- **Una sola forma de declararla.** Google recomienda elegir entre el elemento `<link>` y la cabecera HTTP `Link`, porque usar los dos a la vez es más propenso a errores.
- **No mezcles direcciones distintas** para la misma página en la canónica, el mapa del sitio y los enlaces internos.
- **No pongas fragmentos** (`#...`) en una canónica.
- **No uses `robots.txt` ni `noindex` para canonicalizar.** Bloquear con `robots.txt` no evita que Google indexe la dirección sin contenido, y `noindex` quita la página por completo de los resultados en lugar de consolidarla.

### Listados con parámetros

Si un listado se filtra con `?color=azul` o se pagina con `?pagina=2` y esos parámetros solo **leen o presentan** lo mismo, la canónica es la del listado sin parámetros. En una web estática ocurre sin esfuerzo: el HTML que se sirve es el mismo con y sin parámetros (los filtros se aplican en el navegador), así que la etiqueta de la página ya apunta a la dirección limpia.

```html
<!-- Servida igual en /es/zapatillas/ y en /es/zapatillas/?color=azul&pagina=2 -->
<link rel="canonical" href="https://ejemplo.com/es/zapatillas/" />
```

## `hreflang`: las versiones por idioma

Cada versión de una página declara **todas las versiones que existen, incluida ella misma**:

```html
<!-- En https://ejemplo.com/es/zapatillas/ -->
<link rel="alternate" hreflang="ca" href="https://ejemplo.com/ca/sabatilles/" />
<link rel="alternate" hreflang="es" href="https://ejemplo.com/es/zapatillas/" />
<link rel="alternate" hreflang="en" href="https://ejemplo.com/en/shoes/" />
<link rel="alternate" hreflang="x-default" href="https://ejemplo.com/" />
```

Y las otras dos páginas llevan **el mismo bloque**. (El `x-default` hacia la raíz se explica justo debajo.) Las reglas, según la documentación de Google:

- **Reciprocidad.** Si la versión en castellano apunta a la inglesa y la inglesa no apunta de vuelta, Google **ignora esas etiquetas**. Es el fallo más habitual.
- **Direcciones completas**, con esquema y host. `/en/shoes/` no es válido.
- **Códigos de idioma** ISO 639-1 (`es`, `en`) y, opcionalmente, región ISO 3166-1 alfa-2 (`en-GB`), separados por guion. La región no puede ir sola, y no se admiten códigos como `es-419`. No distinguen mayúsculas de minúsculas.
- **Solo las versiones que existen.** Si un producto no está traducido al catalán, la página no declara la versión `ca`; declarar una dirección que devuelve 404 o redirige estropea el conjunto.

### `x-default`

`x-default` es la dirección de **respaldo**: la que se muestra a quien no encaja con ningún idioma declarado. No lleva código de idioma. Hay dos elecciones válidas, y conviene decidir una y aplicarla siempre:

| Elección | Cuándo conviene |
|---|---|
| **La raíz del sitio** (`/`), si es una página que deja elegir idioma o que redirige según el navegador | Lo recomendable cuando existe esa raíz: es justo el tipo de página para el que se pensó la etiqueta. Todas las páginas declaran la misma raíz. |
| **La versión en un idioma concreto** (por ejemplo, la inglesa) | Si no hay raíz que elija idioma y una de las lenguas hace de «idioma por defecto» del sitio. Hay que decidir qué pasa si esa versión no existe para un contenido. |

La documentación de Google dice que `x-default` «was designed for language selector pages and so it will work best with those», y que puede usarse en cualquier página («you can use the x-default value for any page»). Por eso, si tu raíz `/` es un selector o una página de inicio que redirige automáticamente según el idioma del navegador, esa raíz es la candidata natural a `x-default` de **todas** las páginas, y no una versión localizada.

La raíz, a su vez, declara las versiones por idioma y a sí misma como `x-default`:

```html
<!-- En https://ejemplo.com/ (la raíz) -->
<link rel="canonical" href="https://ejemplo.com/" />
<link rel="alternate" hreflang="es" href="https://ejemplo.com/es/" />
<link rel="alternate" hreflang="en" href="https://ejemplo.com/en/" />
<link rel="alternate" hreflang="x-default" href="https://ejemplo.com/" />
```

Así se cierra el círculo: la raíz apunta a las portadas y cada página apunta de vuelta a la raíz como `x-default`. Si la raíz declarase los idiomas pero ninguna página apuntase de vuelta a ella, esas etiquetas de la raíz se ignorarían (véase «Buenas prácticas avanzadas»).

### Tres sitios donde declararlo

Google trata como equivalentes tres métodos; elige **uno**, usar los tres a la vez no aporta nada:

| Método | Cuándo conviene |
|---|---|
| Etiquetas `<link>` en el `<head>` | Lo más sencillo si generas el HTML; es lo que se usa aquí. |
| Cabecera HTTP `Link` | Para ficheros que no son HTML, como un PDF. |
| Elementos `xhtml:link` en el `sitemap.xml` | Cómodo si ya generas el mapa del sitio y tienes muchas páginas (ver [robots.txt y sitemap](Robots-y-sitemap.md)). |

## Que la reciprocidad no dependa de la memoria

Si escribes las etiquetas a mano, tarde o temprano una versión se actualizará y otra no. Es más seguro **calcular** las declaraciones desde una única tabla de direcciones, de modo que la reciprocidad salga por construcción:

```ts
type Idioma = 'ca' | 'es' | 'en'
// Dirección de cada contenido en cada idioma en el que existe.
type Versiones = Partial<Record<Idioma, string>>

function alternativas(versiones: Versiones, urlAbsoluta: (ruta: string) => string) {
  const languages: Record<string, string> = {}
  for (const [idioma, ruta] of Object.entries(versiones)) languages[idioma] = urlAbsoluta(ruta)
  // x-default es siempre la raíz del sitio, la página que elige idioma.
  languages['x-default'] = urlAbsoluta('/')
  return languages
}

alternativas({ es: '/es/zapatillas/', en: '/en/shoes/' }, urlAbsoluta)
// { es: 'https://ejemplo.com/es/zapatillas/', en: '...', 'x-default': 'https://ejemplo.com/' }
```

Todas las versiones de un mismo contenido llaman a la misma función con la misma tabla, así que **todas declaran lo mismo**. Y un contenido que no existe en un idioma produce una tabla sin esa clave, sin lógica especial; el `x-default` sigue siendo la raíz.

## Errores frecuentes

- **Falta de la etiqueta de vuelta** (sin reciprocidad): el síntoma es que Google ignora el conjunto.
- **Un `x-default` distinto según la página**: unas apuntan a la raíz y otras a la versión inglesa. Escoge una regla y aplícala en todas.
- **La página no se declara a sí misma.**
- **Canónica apuntando a otro idioma.**
- **`hreflang` hacia una dirección con redirección o con 404.**
- **Código inventado** (`sp` en lugar de `es`, `en-UK` en lugar de `en-GB`).
- **Una canónica distinta de la dirección que figura en el `hreflang` y en el mapa del sitio** para la misma versión.

## Buenas prácticas avanzadas

- **Calcula las declaraciones, no las escribas.** Una tabla única de direcciones por contenido e idioma es la fuente de la canónica, de los `hreflang` y del mapa del sitio; así los tres coinciden siempre.
- **Declara solo lo que está completo.** Si un contenido está a medias en un idioma, no lo declares y ese idioma deja de existir para esa página, también en el selector de idioma, que debería llevar a la home del idioma en lugar de a una página inexistente.
- **El idioma del `<html lang>` debe coincidir con el `hreflang` de esa versión.** La etiqueta raíz (`<html lang="es">`) es lo que lee un lector de pantalla; si dice otra cosa, la web es incoherente para personas y para robots.
- **Si la raíz selecciona idioma, que sea el `x-default` de todas las páginas.** Es el uso para el que se diseñó la etiqueta, y evita un error sutil: una raíz que declara `hreflang` hacia `/es/` y `/en/` mientras ninguna de esas portadas apunta de vuelta a ella. Sin enlace de vuelta, Google ignora las etiquetas de la raíz («if two pages don't both point to each other, the tags will be ignored»), así que parece que la raíz «declara» los idiomas y en la práctica no tiene efecto. Y si las portadas declaran como `x-default` la versión inglesa mientras la raíz se declara a sí misma, el sitio dice dos cosas distintas a la vez.
- **Un test de reciprocidad es barato.** Recorre la tabla y comprueba que, si A declara B, B declara A. Detecta en la construcción lo que Google solo te enseñaría semanas después.
- **Una redirección por idioma del navegador no sustituye a `hreflang`.** Los buscadores no envían tu idioma de forma fiable: necesitan las etiquetas (ver [Redirecciones e idioma](Redirecciones-e-idioma.md)).

## Documentación oficial

- [Versiones localizadas (Google)](https://developers.google.com/search/docs/specialty/international/localized-versions) — las reglas de `hreflang`, `x-default` y los tres métodos; mira primero los códigos admitidos y la reciprocidad.
- [Consolidar direcciones duplicadas (Google)](https://developers.google.com/search/docs/crawling-indexing/consolidate-duplicate-urls) — canónica, redirecciones y mapa del sitio como señales de distinta fuerza.

---

*En resumen: cada versión se declara canónica de sí misma y lista a todas las demás, con reciprocidad y direcciones completas, y apunta como `x-default` a la raíz que elige idioma; y lo más seguro es que esas declaraciones las calcule el código.*
