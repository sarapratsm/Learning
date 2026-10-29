# CSS Parallax

## ¿Qué es?

El *parallax* (paralaje) es un efecto de profundidad: al hacer scroll, las capas del fondo se mueven más despacio que las del primer plano, y la página parece tener volumen en lugar de ser una hoja plana. Con CSS se consigue sin una sola línea de JavaScript.

## ¿Por qué existe?

El nombre viene de la astronomía y de la vida diaria: desde la ventanilla de un tren, los postes de al lado pasan como un rayo y las montañas del horizonte casi no se mueven. El cerebro usa esa diferencia de velocidad para calcular distancias. Si una pantalla la imita, el ojo interpreta que hay profundidad aunque todo sea plano.

En la web, el efecto se popularizó antes de que CSS tuviera herramientas para hacerlo bien. Durante años se resolvió con JavaScript escuchando el evento `scroll` y recolocando elementos a mano, con un coste claro: tirones, batería y código frágil. La historia del parallax en CSS es la de ir moviendo esa responsabilidad al navegador, que sabe animar sin bloquear la página.

> Si ya conoces las animaciones con `@keyframes`, piensa en el parallax como una animación cuyo "reloj" no es el tiempo, sino la posición del scroll.

## Un poco de historia

El efecto es muy anterior a la web. Estos son los hitos que suelen citarse:

| Cuándo | Qué pasó |
|---|---|
| 1838 | Friedrich Bessel mide por primera vez el paralaje de una estrella (61 Cygni) y calcula su distancia: el término nace de la astronomía. |
| 1933-1937 | En la animación aparece la **cámara multiplano**: dibujos sobre cristales a distintas distancias de la cámara, que se mueven a velocidades distintas. Disney la estrena con el corto *The Old Mill* (1937) y la populariza con *Blancanieves*. |
| 1982 | Los videojuegos de recreativa, con *Moon Patrol* como ejemplo habitual, adoptan el *parallax scrolling*: fondo lejano y fondo cercano que se desplazan a distinta velocidad. |
| 2011 | Webs promocionales muy comentadas, como la de *Nike Better World*, ponen de moda el parallax en la web, hecho con JavaScript. |
| 2014-2015 | Se difunde la técnica de `perspective` + `translateZ`, que hace parallax real solo con CSS (la divulgó Keith Clark en su artículo sobre webs de parallax en CSS puro). |
| 2023 | Chrome 115 incorpora las **animaciones dirigidas por scroll** (*scroll-driven animations*): `animation-timeline`, la solución nativa y estándar. |

Hoy existen tres técnicas de CSS con compromisos distintos. Esta guía las recorre de la más simple a la más moderna.

## ¿Cuándo y para qué se usa?

Es un recurso decorativo: una portada de tienda online con una foto que "flota" tras el titular, la cabecera de un blog de viajes, una landing que cuenta una historia a medida que se baja. Sirve para dar ritmo y sensación de profundidad. No sirve para transmitir información: si quitar el efecto hace que la página deje de entenderse, el efecto está mal usado.

---

## Técnica 1: `background-attachment: fixed`

Es la más corta. Un fondo con `fixed` queda anclado a la ventana, así que el contenido pasa por encima mientras la imagen se queda quieta, como una ventana al fondo.

```css
.hero {
  min-height: 80vh;
  background-image: url("/img/montanas.jpg");
  background-attachment: fixed;
  background-size: cover;
  background-position: center;
}
```

Con esto, al hacer scroll el `.hero` se desplaza y la imagen se queda quieta. Es un parallax "de velocidad cero" para el fondo, sin control fino.

Limitaciones que la descartan en muchos casos:

- **Móviles**: iOS Safari ignora `fixed` en fondos y otros navegadores móviles lo desactivan por rendimiento. El efecto desaparece sin error.
- **Una sola velocidad**: el fondo no se mueve nada; no puedes tener varias capas a velocidades intermedias.
- **Repintado**: en algunos navegadores obliga a repintar el fondo en cada fotograma de scroll.

Úsala para un único fondo decorativo en el que no importa que en móvil se vea estático.

## Técnica 2: `perspective` y `translateZ`

Esta técnica usa la perspectiva 3D de CSS para que el navegador calcule el parallax: un elemento "más lejos" en el eje Z parece moverse más despacio al hacer scroll.

El contenedor con scroll declara una `perspective`, y cada capa se aleja con un `translateZ` negativo. Al alejarse, el elemento se ve más pequeño, así que se compensa con `scale`.

```html
<div class="scene">
  <section class="group">
    <div class="layer layer--back"><img src="/img/montanas.jpg" alt=""></div>
    <div class="layer layer--base"><h1>Viajes por Islandia</h1></div>
  </section>
</div>
```

```css
.scene {
  height: 100vh;
  overflow-x: hidden;
  overflow-y: auto;      /* el scroll vive en este contenedor, no en la página */
  perspective: 1px;
}

.group {
  position: relative;
  height: 100vh;
  transform-style: preserve-3d;
}

.layer {
  position: absolute;
  inset: 0;
}

.layer--base { transform: translateZ(0); }
.layer--back { transform: translateZ(-1px) scale(2); }
```

`.layer--back` está 1 px detrás del plano de la pantalla, con una perspectiva de 1 px: se ve a la mitad de tamaño y se desplaza a la mitad de velocidad. El `scale(2)` le devuelve su tamaño visual. El texto de `.layer--base` se mueve a velocidad normal.

Con `perspective: p` y una capa a `translateZ(-z)`:

| Magnitud | Valor |
|---|---|
| `scale` necesario | `1 + z / p` |
| velocidad relativa de la capa | `1 / (1 + z / p)` |

Por ejemplo, `translateZ(-2px) scale(3)` con `perspective: 1px` da una capa que se mueve a un tercio de la velocidad.

Ventajas: el scroll sigue siendo el nativo, fluido y compuesto en la GPU. Inconvenientes:

- El scroll tiene que vivir en un contenedor propio (`overflow: auto`), no en la página: la barra de scroll, los enlaces a anclas (`#seccion`) y algunas herramientas pueden comportarse distinto.
- Las capas escaladas se salen del recuadro: hace falta `overflow-x: hidden` y ajustar alturas a ojo.
- Es una técnica ingeniosa pero "hackeada": usa una función pensada para 3D con otro propósito, y mantenerla cuesta.

## Técnica 3: animaciones dirigidas por scroll

Es la forma moderna y, si el público lo permite, la primera opción. En lugar de simular profundidad con 3D, vinculas una animación normal de `@keyframes` al progreso del scroll con `animation-timeline`.

```css
@keyframes drift {
  from { transform: translateY(-15%); }
  to   { transform: translateY(15%); }
}

.hero {
  position: relative;
  min-height: 80vh;
  overflow: hidden;
}

.hero__bg {
  position: absolute;
  inset: -15% 0;             /* más alto que el hero, para que no se vean los bordes */
  background: url("/img/montanas.jpg") center / cover;
}

@supports (animation-timeline: view()) {
  @media (prefers-reduced-motion: no-preference) {
    .hero__bg {
      animation: drift linear both;
      animation-timeline: view();   /* progreso = cuánto ha cruzado la ventana el elemento */
      animation-range: cover;       /* de que entra por abajo a que sale por arriba */
    }
  }
}
```

Mientras `.hero` cruza la ventana, la imagen de fondo se desplaza dentro de su caja entre `-15%` y `15%` de su propia altura. Como el `.hero` ya se mueve con el scroll, la suma da una imagen que avanza a velocidad distinta: eso es el parallax.

Piezas a conocer:

- **`scroll()`**: el progreso lo marca el scroll de un contenedor (por defecto, el ancestro más cercano que hace scroll). Útil para efectos de página entera, como una barra de progreso de lectura.
- **`view()`**: el progreso lo marca la posición del propio elemento al cruzar la ventana. Es el que se usa para el parallax por sección.
- **`animation-range`**: delimita en qué tramo del recorrido corre la animación (`cover`, `entry`, `exit`...).
- **Orden**: `animation-timeline` va **después** del atajo `animation`, porque este lo reinicia.

El `@supports` hace que, donde no hay soporte, la página se vea estática pero correcta. El soporte sigue ampliándose entre navegadores: compruébalo en [Can I use](https://caniuse.com/?search=animation-timeline) antes de decidir.

### Cuando necesitas JavaScript

Si hay que soportar navegadores sin `animation-timeline` y el efecto es imprescindible, queda el enfoque clásico: un `IntersectionObserver` para saber qué sección está visible y `requestAnimationFrame` para actualizar una variable CSS (`--scroll`) que `transform` consuma. Es más código y más riesgo de tirones; se justifica solo si el efecto es parte del producto.

## Accesibilidad y rendimiento

El movimiento ligado al scroll puede provocar mareo o náuseas a personas con trastornos vestibulares. Por eso existe la media query `prefers-reduced-motion`, que refleja la preferencia del sistema operativo:

```css
@media (prefers-reduced-motion: reduce) {
  .hero__bg { animation: none; }
}
```

Es la idea que recoge [WCAG](../accesibilidad-web/WCAG.md) en su criterio sobre animación a partir de interacciones: el movimiento no esencial debe poder desactivarse. En el ejemplo de la técnica 3 ya va resuelto envolviendo el efecto en `prefers-reduced-motion: no-preference`, de modo que el efecto es *opt-in*.

En rendimiento, la regla es animar solo `transform` y `opacity`: son las propiedades que el navegador mueve en la GPU sin recalcular el layout. Animar `top`, `margin` o `background-position` fuerza trabajo en cada fotograma.

## Buenas prácticas avanzadas

- **Anima únicamente `transform` y `opacity`** — mover un fondo con `background-position` parece equivalente, pero obliga a repintar en cada fotograma; con `transform` el navegador solo recoloca una capa ya pintada.
- **Haz la capa móvil más grande que su caja y recórtala con `overflow: hidden`** — si mide lo mismo que el contenedor, al desplazarla aparecen huecos en los bordes. Calcula el margen extra a partir del desplazamiento máximo (en el ejemplo, `-15%` arriba y abajo).
- **Declara el efecto dentro de `prefers-reduced-motion: no-preference`** — empezar sin movimiento y añadirlo solo cuando es seguro es más robusto que acordarse de apagarlo después.
- **Usa `@supports` para degradar con elegancia** — que el fallback sea la página estática; evita efectos a medias en navegadores sin `animation-timeline`.
- **No pongas `will-change` por defecto** — reserva una capa de GPU por elemento y, usado en muchos, gasta memoria y empeora el rendimiento. Aplícalo solo si has medido un problema.
- **Pon `alt=""` a las imágenes puramente decorativas** — una foto de fondo que se mueve no aporta contenido, y el lector de pantalla no debería anunciarla.

## Documentación oficial

- [MDN: CSS scroll-driven animations](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_scroll-driven_animations) — la mejor referencia de `scroll()`, `view()`, `animation-range` y la tabla de compatibilidad; empieza por la página de conceptos.
- [CSS Scroll-driven Animations (especificación)](https://drafts.csswg.org/scroll-animations-1/) — la fuente normativa, para cuando la duda es qué dice el estándar.
- [MDN: `perspective`](https://developer.mozilla.org/en-US/docs/Web/CSS/perspective) — para entender cómo la perspectiva afecta al tamaño y desplazamiento aparentes en la técnica 2.

## Recursos didácticos

- [Scroll-driven Animations (demos y herramientas)](https://scroll-driven-animations.style/) — colección de demostraciones interactivas con su código, y un visor para ver qué recorrido cubre cada `animation-range`.
- [Pure CSS Parallax Websites (Keith Clark)](https://keithclark.co.uk/articles/pure-css-parallax-websites/) — el artículo que divulgó la técnica de `perspective` y `translateZ`, con el razonamiento paso a paso.
- [Can I use](https://caniuse.com/) — para comprobar el soporte de `animation-timeline` en los navegadores que te importan.

---

*En resumen: el parallax es hacer que las capas se muevan a distinta velocidad al hacer scroll; con CSS moderno se consigue con `animation-timeline`, y lo importante es que sea decorativo, ligero y desactivable.*
