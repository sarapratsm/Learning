# Publicar imágenes en una web

## ¿Qué es?

Es el conjunto de hábitos que convierten una imagen con licencia válida en una imagen bien publicada: documentada, acreditada, accesible, propia (alojada en tu servidor) y ligera.

## ¿Por qué existe?

Tener derecho a usar una foto es solo el primer paso. Pasados unos meses, nadie recuerda de dónde salió, bajo qué licencia ni quién debe aparecer en el crédito; y si llega una reclamación, no hay forma de demostrar nada. A eso se suman problemas técnicos: imágenes que pesan megas, enlaces a imágenes de otro sitio que desaparecen o textos alternativos vacíos. Estas prácticas son baratas de aplicar el día que se publica la imagen y carísimas de reconstruir después.

## ¿Cuándo y para qué se usa?

Cada vez que se añade una imagen a una tienda online, un blog o la web de una pyme: la foto del cabecero, la galería de un producto, la ilustración de un artículo.

---

## Registrar el origen de cada imagen

Por cada imagen guarda, como mínimo: **URL de la página de origen, autoría, licencia (con enlace), fecha de descarga y dónde se usa en la web**. Una hoja de cálculo o un fichero versionado junto al código basta:

```csv
fichero,autoria,origen,licencia,descargada,usada_en
cabecero-inicio.webp,Nombre Apellido,https://www.pexels.com/photo/ejemplo/,Licencia de Pexels,2026-11-03,/
taller.webp,Nombre Apellido,https://commons.wikimedia.org/wiki/File:Ejemplo.jpg,CC BY-SA 4.0,2026-11-03,/nosotros
```

Qué hace: deja un registro auditable. Si mañana una licencia cambia o llega una reclamación, sabes qué imágenes afecta y puedes sustituirlas o demostrar que las usaste con permiso.

## Dar crédito aunque no sea obligatorio

Varias licencias de bancos (Pexels, Unsplash, Pixabay) no exigen atribución; la de Unsplash la agradece expresamente. Otras (CC BY, CC BY-SA) sí la exigen. Conviene unificar el criterio:

- **Si la licencia lo exige**, cumple exactamente lo que pide: normalmente autoría, título, licencia con enlace y origen.
- **Si no lo exige**, dar crédito es un gesto de cortesía y deja más rastro de procedencia. Puede ir en una página de créditos o junto a la imagen.

```html
<figure>
  <img src="/img/taller.webp" alt="Persona soldando una pieza metálica en un taller" width="1200" height="800">
  <figcaption>
    Foto de Nombre Apellido,
    <a href="https://commons.wikimedia.org/wiki/File:Ejemplo.jpg">Wikimedia Commons</a>,
    <a href="https://creativecommons.org/licenses/by-sa/4.0/">CC BY-SA 4.0</a>.
  </figcaption>
</figure>
```

Qué hace: muestra el crédito pegado a la imagen con el enlace a la fuente y a la licencia.

## Texto alternativo

El atributo `alt` describe la imagen para quien no la ve (lector de pantalla) y para el navegador cuando falla la carga. Es un requisito de accesibilidad, y también ayuda a los buscadores.

```html
<!-- ❌ MAL: vacío o genérico -->
<img src="/img/taller.webp" alt="">
<img src="/img/taller.webp" alt="imagen1">

<!-- ✅ BIEN: describe lo que aporta -->
<img src="/img/taller.webp" alt="Persona soldando una pieza metálica en un taller">
```

Reglas prácticas: describe el contenido y su función, no empieces con «imagen de»; si la imagen es puramente decorativa, deja `alt=""` a propósito para que los lectores de pantalla la ignoren.

## No enlazar la imagen desde otro sitio (*hotlinking*)

Hotlinking es poner en `src` la URL de una imagen alojada en otro sitio:

```html
<!-- ❌ MAL: depende de un servidor ajeno -->
<img src="https://otra-web.example/fotos/taller.jpg" alt="...">
```

Problemas: la otra web puede borrar o mover la imagen (se rompe la tuya), puede cambiarla por otra, consume su ancho de banda sin permiso y no deja registro de licencia ni control de rendimiento. Descarga la imagen (si la licencia lo permite), súbela a tu propio servidor y enlázala desde ahí. Wikimedia indica en su página de reutilización que se puede enlazar directamente a un archivo pero no lo recomienda.

## Optimizar y convertir a webp

Una foto original de cámara pesa varios megas; en una página eso es inaceptable. Antes de publicar:

1. **Redimensiona** al tamaño máximo en que se va a mostrar (por ejemplo, 1600 px de ancho para un cabecero).
2. **Convierte a webp**, un formato que suele pesar bastante menos que JPEG con calidad visual similar y que soportan los navegadores actuales.
3. **Comprime** con una calidad razonable (empieza en torno a 75-85 y compara a ojo).

```bash
# Con la herramienta cwebp (viene en el paquete de utilidades de WebP)
cwebp -q 80 -resize 1600 0 cabecero.jpg -o cabecero.webp
```

Qué hace: genera `cabecero.webp` con 1600 px de ancho, altura proporcional y calidad 80.

Importante: **convertir y redimensionar son modificaciones técnicas**. Si la licencia es ND (sin derivadas), pueden ser problemáticas. Es otro motivo para evitar imágenes ND. Conserva también siempre el original sin tocar.

## Comprobar el origen: búsqueda inversa de imágenes

Si te entregan una imagen sin origen claro, o una de un banco te parece sospechosamente profesional, haz una **búsqueda inversa**: subes la imagen (o su URL) a un buscador y te devuelve dónde más aparece. Sirve para ver si es una foto de pago, si tiene autoría conocida o si está atribuida a otra persona.

Herramientas reales: Google Lens / Búsqueda de imágenes de Google, TinEye y la búsqueda por imagen de Bing. Es una pista útil, no una prueba: que no aparezca en ningún sitio no demuestra que sea libre, y que aparezca no demuestra que sea ajena.

## Lista de verificación antes de publicar

- [ ] Sé de dónde viene la imagen y puedo enlazar su página de origen.
- [ ] He leído la licencia de esa imagen concreta (no solo la del banco) y la he guardado.
- [ ] La licencia permite el uso comercial, si la web lo es.
- [ ] No es NC ni ND, y si es BY o BY-SA cumplo el crédito.
- [ ] No hay rostros reconocibles ni logotipos, o tengo la autorización correspondiente.
- [ ] Está registrada (origen, autoría, licencia, fecha, dónde se usa).
- [ ] Está alojada en mi servidor, redimensionada y convertida a webp.
- [ ] Tiene `alt` útil (o vacío si es decorativa), y `width` y `height`.
- [ ] El crédito está visible o en la página de créditos, si procede.

## Aviso

Este tutorial es orientativo y no es asesoramiento legal. Las licencias cambian con el tiempo: lo vinculante es lo que diga la página del banco el día en que descargas la imagen.

---

## Buenas prácticas avanzadas

- **Guarda el original y trabaja sobre copias.** Si la licencia cambia o necesitas otro tamaño, partes del original y no de un webp ya degradado.
- **Indica `width` y `height` en cada `<img>`.** El navegador reserva el hueco antes de cargar la imagen y evitas saltos de maquetación (CLS) que penalizan la experiencia y las métricas web.
- **Carga diferida salvo en la imagen principal.** `loading="lazy"` en las imágenes por debajo del pliegue; no la pongas en la imagen principal visible al abrir la página, porque la retrasa.
- **Limpia los metadatos al exportar, pero no pierdas la procedencia.** Las fotos pueden llevar datos EXIF (ubicación GPS, cámara) que no quieres publicar; quítalos de la copia pública y conserva el registro de origen aparte, no dentro del fichero.
- **Revisa el registro periódicamente.** Una vez al año, repasa qué licencias siguen vigentes y qué imágenes siguen en uso; retira o sustituye las dudosas.
- **Evita el nombre de fichero genérico.** `IMG_4521.jpg` no dice nada; `taller-soldadura.webp` ayuda a ti y a los buscadores.

## Documentación oficial

- [Wikimedia Commons: reutilizar contenido](https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia) — lista de pasos para reutilizar y atribuir correctamente un archivo; sirve de modelo para cualquier crédito.
- [MDN: el elemento `<img>`](https://developer.mozilla.org/es/docs/Web/HTML/Element/img) — referencia de `alt`, `width`, `height` y `loading`.
- [MDN: tipos de imagen y formatos](https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Formats/Image_types) (en inglés) — qué soporta cada navegador y cuándo conviene cada formato, incluido WebP.

## Recursos didácticos

- [TinEye](https://tineye.com/) — buscador de imagen inversa; útil para rastrear el origen y otros usos de una foto.
- [Google Lens](https://lens.google/) — búsqueda por imagen de Google, también desde el navegador.
- [Selector de licencias de Creative Commons](https://creativecommons.org/choose/) — para entender qué condiciones lleva cada combinación.

---

*En resumen: una imagen bien publicada tiene su origen y su licencia registrados, el crédito cuando toca, un `alt` útil, se aloja en tu servidor y se sirve ligera; y antes de publicar hay una lista corta que conviene recorrer siempre.*
