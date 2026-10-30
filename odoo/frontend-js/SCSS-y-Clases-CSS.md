# SCSS y clases CSS en el cliente de Odoo

## ¿Qué es?

El aspecto del cliente web de Odoo se define con hojas de estilo SCSS (CSS con variables, anidamiento y bucles) que se compilan a CSS al empaquetar los *bundles*. Tu módulo añade las suyas igual que añade JavaScript: las declara en el manifest y Odoo las fusiona con el resto.

## ¿Por qué existe?

El cliente web no empieza de cero: ya trae Bootstrap, su propio sistema de diseño y librerías de terceros con sus propios estilos. Escribir CSS en Odoo es sobre todo **convivir** con todo eso: saber qué clase pinta qué, cuál gana cuando dos reglas chocan, y cómo cambiar el aspecto de una pieza sin romper las demás.

## ¿Cuándo y para qué se usa?

Para dar estilo a un componente propio y, más a menudo de lo que parece, para **corregir el estilo de una pieza existente**: un texto que se corta, una altura que no te sirve, un color que no distingue.

---

## Dónde se escribe

Un `.scss` va en `static/src/` junto a su componente y se declara en el mismo bundle que el JavaScript:

```python
'assets': {
    'web.assets_backend': [
        'mi_modulo/static/src/components/task_card/task_card.js',
        'mi_modulo/static/src/components/task_card/task_card.xml',
        'mi_modulo/static/src/components/task_card/task_card.scss',
    ],
},
```

Odoo compila el SCSS a CSS al generar el bundle. Los cambios en desarrollo se ven con `?debug=assets`; en servidor, tras actualizar el módulo (ver [Estructura y assets](Estructura-y-Assets.md)).

El SCSS de Odoo ya conoce las variables de Bootstrap y las propias del tema (`$primary`, `$border-color`, `$o-brand-primary`...), así que puedes usarlas sin importarlas.

## De dónde salen las clases que vas a ver

Cuando inspeccionas un elemento en el navegador (clic derecho → Inspeccionar), las clases tienen tres orígenes distintos, y distinguirlos ahorra mucho tiempo:

| Prefijo o aspecto | Origen | Se puede cambiar en |
|---|---|---|
| `o_...` (`o_form_view`, `o_event_title`) | Odoo | El `.xml` o `.scss` de Odoo |
| `btn`, `badge`, `d-flex`, `text-truncate`, `col-6` | Bootstrap | Se usan, no se redefinen |
| `fc-...` (`fc-event-main`) | Una librería de terceros (aquí FullCalendar) | Solo con CSS propio |

Y una cuarta categoría: las **clases dinámicas**, como `o_timer_zoom_2`, que nadie declara en ningún CSS. Las genera el JavaScript (por ejemplo, desde un getter de la clase) y el CSS solo las usa como gancho. Si buscas dónde está declarada una clase y no la encuentras, busca en el JavaScript.

## Acotar los estilos: el selector manda

La regla más importante de todas: **tus estilos deben afectar solo a tu pieza**. Todo el CSS de Odoo comparte una sola hoja global, así que una regla demasiado general cambia pantallas que ni sabías que existían.

```scss
// ❌ Afecta a todos los calendarios de Odoo
.fc-event-main > .o_event_title {
    white-space: normal;
}

// ✅ Solo al de tu vista, colgando de una clase que pone tu componente
.o_task_calendar .fc-event-main > .o_event_title {
    white-space: normal;
}
```

La clase de contexto (`o_task_calendar`) la pones tú en tu vista o componente. Un prefijo propio (`o_mi_modulo_...`) evita choques con clases de Odoo.

## Cuando dos reglas chocan

Si tu regla no tiene efecto, casi siempre hay otra más fuerte. Dos causas habituales:

**1. Especificidad.** Un selector con más partes (`.a .b .c`) gana a uno con menos (`.c`). Si la regla de Odoo es más específica que la tuya, no basta con repetir la propiedad: tu selector tiene que ser igual o más específico.

**2. Las utilidades de Bootstrap llevan `!important`.** Clases como `text-truncate`, `d-none` o `fw-bold` fuerzan su valor y ninguna regla normal las supera:

```xml
<!-- Esta clase fuerza white-space: nowrap con !important -->
<div class="o_event_title text-truncate"/>
```

```scss
.o_task_calendar .o_event_title {
    white-space: normal;   /* no tiene efecto: !important de la utilidad gana */
}
```

Dos maneras de salir:

- **La buena:** quitar la clase de utilidad de la plantilla. Si la plantilla es tuya o la heredas ([Plantillas QWeb de cliente](Plantillas-QWeb-de-Cliente.md)), basta con no ponerla.
- **La de último recurso:** añadir `!important` a tu regla. Funciona, pero cada `!important` hace más difícil el siguiente cambio.

## Generar reglas con bucles

SCSS permite repetir un bloque. Resulta útil cuando una familia de clases solo cambia en un número:

```scss
@each $level in (1, 2, 4) {
    .o_task_zoom_#{$level} .fc-timegrid-slot {
        height: calc(1.5em * #{$level});
    }
}
```

Esto genera tres reglas: `.o_task_zoom_1`, `.o_task_zoom_2` y `.o_task_zoom_4`, cada una con su altura. `#{...}` inserta el valor de la variable dentro de un nombre o dentro de `calc()`. La clase correspondiente la pone el JavaScript según el nivel elegido.

## Errores frecuentes

- **El estilo no se aplica.** Primero: ¿está el `.scss` en el manifest y has recargado con `?debug=assets`? Después: inspecciona el elemento y mira, en la pestaña *Styles*, si tu regla aparece tachada. Si está tachada, otra regla (o un `!important`) gana.
- **Afecta a otras pantallas.** El selector es demasiado general. Cuelga todo de una clase de contexto propia.
- **Funciona en escritorio y no en móvil.** Odoo carga hojas distintas para pantalla pequeña (`..._mobile.scss`) con reglas propias; revisa los puntos de corte de Bootstrap (`lg`, `md`).
- **No se ve en modo oscuro.** Si usas colores fijos (`#fff`), no se adaptan. Usa las variables de Bootstrap y de Odoo, que ya tienen su versión oscura.
- **Error de compilación del bundle.** Una llave sin cerrar o una variable que no existe rompe el SCSS entero y la página queda sin estilos. El error aparece en el log del servidor al generar el bundle.

## Buenas prácticas avanzadas

- **Pon la clase de contexto en el elemento raíz de tu componente** y cuelga de ella todos los selectores. Es la forma más barata de garantizar que no tocas nada ajeno.
- **Cambia la plantilla antes de pelear con `!important`.** Quitar una clase de utilidad en el XML es un cambio de una línea y no deja deuda.
- **Evita depender de la estructura interna de una librería de terceros.** Clases como `fc-event-main` pueden cambiar con una versión nueva. Si no hay otra opción, deja un comentario que diga qué librería y qué comportamiento pretendes, para quien tenga que revisarlo tras una actualización.
- **Comenta el porqué, no el qué.** `white-space: normal` se entiende solo; «el título baja de línea en lugar de cortarse» explica la intención.
- **Prueba en los dos temas y a dos anchos.** Un cambio de CSS puede estar perfecto en claro y escritorio y ser ilegible en oscuro o en móvil.

## Documentación oficial

- [Assets y SCSS (Odoo 18)](https://www.odoo.com/documentation/18.0/developer/reference/frontend/assets.html) — cómo se compilan las hojas y qué variables están disponibles; útil para saber en qué *bundle* declarar los ficheros.
- [Bootstrap 5, utilidades](https://getbootstrap.com/docs/5.3/utilities/api/) — qué hacen las clases `text-truncate`, `d-flex`, etc. y por qué llevan `!important`.

## Recursos didácticos

- [CSS Specificity Calculator (Specificity Calculator)](https://specificity.keegan.st/) — pega dos selectores y ve cuál gana y por qué. Resuelve la mayoría de los «mi regla no se aplica».

---

*En resumen: el CSS de Odoo es una hoja compartida, así que acota todo con una clase propia, localiza quién gana cuando dos reglas chocan, y cambia la plantilla antes de recurrir a `!important`.*
