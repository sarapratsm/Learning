# Vista previa al compartir un enlace: Open Graph

## ¿Qué es?

*Open Graph* es un conjunto de etiquetas `<meta>` que declaras en el `<head>` de cada página para decidir **qué título, descripción e imagen aparecen** cuando alguien pega su enlace en una red social o en un chat.

## ¿Por qué existe?

Cuando pegas un enlace en LinkedIn o en un chat, la aplicación no te enseña tu página: envía un robot a descargarla, busca unas etiquetas concretas y con ellas construye una tarjeta. Si no las encuentra, improvisa con lo que halla (un trozo de texto al azar, ninguna imagen) y el enlace se ve pobre.

El protocolo lo creó Facebook y lo leen hoy casi todas las aplicaciones que muestran tarjetas de enlaces.

## ¿Cuándo y para qué se usa?

En **toda página que alguien pueda compartir**: la portada, un producto, un artículo. En una tienda online, es lo que decide si el enlace a una zapatilla llega a un grupo de mensajería con foto y precio o como una línea de texto gris.

---

## Las etiquetas

El protocolo (ogp.me) exige cuatro propiedades y define otras opcionales:

| Propiedad | Para qué sirve |
|---|---|
| `og:title` | Título de la tarjeta. |
| `og:type` | Tipo de contenido; para páginas normales, `website`. |
| `og:image` | Imagen de la tarjeta. |
| `og:url` | La dirección canónica de la página. |
| `og:description` | Una o dos frases (opcional, pero se usa siempre). |
| `og:site_name` | Nombre del sitio (opcional). |
| `og:locale` | Idioma y territorio, con formato `idioma_TERRITORIO` (`es_ES`); por defecto `en_US`. |
| `og:image:width`, `og:image:height`, `og:image:alt` | Tamaño y texto alternativo de la imagen. |

```html
<head>
  <meta property="og:title" content="Zapatillas de running Aire" />
  <meta property="og:description" content="Ligeras, con amortiguación y envío en 24 horas." />
  <meta property="og:type" content="website" />
  <meta property="og:url" content="https://ejemplo.com/es/zapatillas/aire/" />
  <meta property="og:image" content="https://ejemplo.com/vista-previa.png" />
  <meta property="og:image:width" content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:image:alt" content="Zapatilla Aire sobre fondo azul" />
</head>
```

Detalles que importan:

- **Las direcciones deben ser absolutas** (`og:image`, `og:url`). Una `/vista-previa.png` relativa falla porque quien la lee no sabe de qué dominio hablas.
- **`og:url` es la canónica**, no la dirección con parámetros de campaña con la que llegó alguien.
- **Título y descripción**: lo normal es reutilizar los mismos que ya usas para buscadores, **en el idioma de cada versión**.

## La imagen

Según las recomendaciones de Facebook:

- Recomendado: **1200 × 630 píxeles** (relación 1,91:1), para verse bien en pantallas de alta resolución y sin recortes en escritorio ni en móvil.
- Mínimo: 200 × 200 píxeles; con menos de 600 × 315 se muestra pequeña.
- Peso máximo: 8 MB.

Para que una web pequeña no dependa de una imagen por página, es habitual usar **una imagen por defecto** (el logotipo sobre un fondo de marca) para todas, y reservar imágenes propias para páginas donde tenga sentido (un producto con su foto).

## Cómo se comporta la caché

Las aplicaciones **guardan la tarjeta** la primera vez que ven un enlace. Esto se traduce en tres sorpresas:

- Si cambias la imagen y mantienes su dirección, muchas aplicaciones seguirán enseñando la vieja. Para cambiarla, **usa una dirección nueva** (`vista-previa-v2.png`).
- Los enlaces ya compartidos no se actualizan solos.
- La primera persona que comparte un enlace nuevo puede no ver la imagen, porque la aplicación aún la está descargando. Declarar `og:image:width` y `og:image:height` permite que se renderice sin esperar.

Las plataformas ofrecen herramientas para **forzar el refresco**: el *Sharing Debugger* de Facebook y el *Post Inspector* de LinkedIn.

## Probarlo antes de publicar

El robot de la aplicación necesita **llegar a tu página**: un entorno local o de pruebas con contraseña no se puede previsualizar. Antes de publicar, tu comprobación es mirar el HTML generado y verificar que cada página tiene las etiquetas con direcciones absolutas. La prueba real (pegar el enlace en LinkedIn o en un chat) se hace una vez publicada.

## Buenas prácticas avanzadas

- **Etiquetas en el HTML, no añadidas por JavaScript.** Los robots de las aplicaciones de mensajería suelen leer solo el HTML recibido y no ejecutan scripts: si tus etiquetas aparecen tras ejecutar JavaScript, pueden no verse. Es otra ventaja de generar el HTML en la construcción.
- **Imagen con texto legible en pequeño.** La tarjeta se ve a menudo del tamaño de un sello en móvil; un logotipo grande y poco texto resisten mejor que una foto con letra fina.
- **Mismo título que el de buscadores, pero revisa el largo.** Cada aplicación recorta los títulos y descripciones largos a su manera, y no es fácil de verificar: escribe lo importante al principio.
- **`og:locale` coherente con la versión.** Una página en catalán con `en_US` por defecto se ve rara en algunos sistemas.
- **Rompe la caché con una dirección nueva, no con el mismo fichero.** Y no borres la imagen antigua: puede haber tarjetas ya compartidas que la usen.
- **No dependas de una sola red.** El mismo bloque de etiquetas sirve a la mayoría; solo si necesitas una tarjeta distinta en X (antes Twitter) añade sus etiquetas `twitter:*`.

## Documentación oficial

- [The Open Graph protocol](https://ogp.me/) — las propiedades requeridas y opcionales; la fuente original del estándar.
- [Imágenes para compartir (Facebook)](https://developers.facebook.com/docs/sharing/webmasters/images/) — tamaños recomendados y cómo se guarda la imagen en caché.

## Recursos didácticos

- [Sharing Debugger de Facebook](https://developers.facebook.com/tools/debug/) — pega una dirección publicada y ve la tarjeta que se genera; también permite refrescar la caché.
- [Post Inspector de LinkedIn](https://www.linkedin.com/post-inspector/) — lo mismo para LinkedIn.

---

*En resumen: título, descripción, imagen y dirección canónica en etiquetas `og:` dentro del HTML, con direcciones absolutas y una imagen de 1200 × 630 píxeles.*
