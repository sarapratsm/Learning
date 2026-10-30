# Plantillas QWeb de cliente

## ¿Qué es?

QWeb es el lenguaje de plantillas XML de Odoo. Una plantilla describe un trozo de HTML con huecos: «aquí va el título, repite esto por cada elemento, pinta esto solo si...». En el cliente web, cada componente OWL se pinta con una plantilla QWeb guardada en un `.xml` dentro de `static/src/`.

## ¿Por qué existe?

Una plantilla es la parte «visual» de un componente: separa lo que se muestra de la lógica que decide los datos. Mezclar HTML y JavaScript en cadenas de texto es ilegible y propenso a errores; con una plantilla, el HTML sigue pareciendo HTML y las decisiones se expresan con atributos `t-...`.

> Si conoces Jinja, Razor o Thymeleaf, es lo mismo: un HTML con directivas. La diferencia es que las directivas son atributos XML (`t-if`, `t-foreach`) y que el fichero tiene que ser XML válido: todas las etiquetas cerradas, atributos entre comillas.

## ¿Cuándo y para qué se usa?

Siempre que pintes una pieza de interfaz propia, y también cuando quieras **modificar la plantilla de una pieza que ya existe** (añadir un campo a una tarjeta, cambiar el texto de un botón).

Hay dos «sabores» de QWeb en Odoo y conviene no confundirlos:

| | QWeb de servidor | QWeb de cliente |
|---|---|---|
| Dónde vive | `views/*.xml` (informes, páginas web) | `static/src/**/*.xml` |
| Quién lo evalúa | Python, en el servidor | OWL, en el navegador |
| Lenguaje de las expresiones | Python | JavaScript |
| Se declara en | `data` del manifest | `assets` del manifest |

Esta ficha trata del de cliente. Las directivas se parecen, pero las expresiones son JavaScript, no Python: `props.items.length`, no `len(items)`.

---

## Estructura de un fichero

Un `.xml` de cliente es una lista de plantillas con nombre, dentro de `<templates>`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<templates xml:space="preserve">

    <t t-name="mi_modulo.TaskCard">
        <div class="card">
            <h5 t-esc="props.task.name"/>
        </div>
    </t>

</templates>
```

El `t-name` es lo que el componente referencia en `static template`. El atributo `xml:space="preserve"` evita que el XML se coma los espacios entre etiquetas; se pone siempre.

## Pintar datos

Dos directivas muestran un valor, y las dos escapan el HTML:

```xml
<span t-esc="props.task.name"/>
<span t-out="props.task.name"/>
```

En Odoo 18 hacen lo mismo con texto normal. Usa `t-out` en código nuevo. Para insertar HTML ya formado hay que marcarlo como seguro en el JavaScript (`markup(...)`); si no, se ve como texto con las etiquetas visibles. Es una protección deliberada contra inyección de código.

Dentro de un atributo o de un texto con otras palabras, el valor se interpola con llaves:

```xml
<a t-att-href="'/tasks/' + props.task.id" t-esc="props.task.name"/>
<div t-attf-class="card card-#{props.task.priority}">...</div>
```

- `t-att-<atributo>` — el atributo entero es una expresión JavaScript.
- `t-attf-<atributo>` — es un texto con trozos `#{...}` de JavaScript dentro. Cómodo para componer clases.

## Condiciones y bucles

```xml
<ul>
    <li t-foreach="props.tasks" t-as="task" t-key="task.id">
        <span t-esc="task.name"/>
        <span t-if="task.done" class="badge text-bg-success">Hecho</span>
        <span t-elif="task.late" class="badge text-bg-danger">Retrasada</span>
        <span t-else="" class="badge text-bg-secondary">Pendiente</span>
    </li>
</ul>
```

- `t-foreach` + `t-as` — repite el elemento por cada entrada; `task` es el nombre de la variable de cada vuelta.
- `t-key` — **obligatorio** en el cliente. Es un identificador único y estable de cada elemento (casi siempre el `id`), que OWL usa para saber qué elemento es cuál al repintar. Sin él, la plantilla falla al compilar.
- `t-if` / `t-elif` / `t-else` — el `t-else` va con comillas vacías: `t-else=""`.

Si necesitas una condición o un bucle sin pintar ninguna etiqueta propia, usa `<t>` como contenedor invisible:

```xml
<t t-if="props.tasks.length">
    ...
</t>
```

## Eventos

`t-on-<evento>` conecta un evento del navegador con un método del componente:

```xml
<button t-on-click="() => this.complete(task.id)">Completar</button>
<input t-on-input="onSearch" t-att-value="state.query"/>
```

Con una flecha pasas argumentos; con el nombre pelado, recibes el evento. Detalle: dentro de la plantilla, el componente se llama `this`.

## Heredar una plantilla existente

Para cambiar una pieza de Odoo no hace falta copiar su plantilla. Se crea una plantilla **de extensión** que apunta a la original y le aplica cambios con `xpath`, igual que en la herencia de vistas del servidor:

```xml
<t t-name="mi_modulo.TaskCardExtra"
   t-inherit="project.TaskCard"
   t-inherit-mode="extension">
    <xpath expr="//div[hasclass('card-body')]" position="inside">
        <span class="badge text-bg-info">Mi etiqueta</span>
    </xpath>
</t>
```

- `t-inherit` — el `t-name` de la plantilla que quieres modificar.
- `t-inherit-mode="extension"` — modifica la original **en el sitio**: todos los componentes que la usan verán el cambio.
- `t-inherit-mode="primary"` — crea una plantilla nueva a partir de la original, con tu `t-name`, sin tocar la original. Úsala cuando quieras una variante para un componente propio.
- `position` — `inside`, `after`, `before`, `replace`, `attributes`.
- `hasclass('x')` — la forma de buscar por clase en un xpath de QWeb, en lugar de `contains(@class, 'x')`.

Para saber qué `t-name` y qué estructura tiene la plantilla que quieres modificar, busca el nombre en el código fuente de Odoo, en el `.xml` del módulo correspondiente.

## Una advertencia: plantillas renderizadas «a mano»

Algunas piezas de Odoo no dejan que OWL pinte la plantilla dentro del árbol de componentes, sino que la convierten primero en texto HTML y la insertan después. Es el caso, por ejemplo, del contenido de cada bloque del calendario: lo pinta una librería externa que pide HTML ya hecho.

En esos casos, la plantilla **no es un componente vivo**: el estado reactivo no se actualiza dentro de ella y `t-on-click` no funciona. Sirve para mostrar datos que ya tienes, no para interactuar. Si necesitas interacción, usa el evento que ofrece el contenedor (por ejemplo, el clic en el bloque) y no la plantilla.

## Errores frecuentes

- **El XML no parsea.** Falta cerrar una etiqueta, hay un `&` sin escapar (escríbelo `&amp;`) o un `<` dentro de una expresión (usa `&lt;`). El error aparece al cargar la página, no al guardar el fichero.
- **`Missing template` o el componente sale vacío.** Fallo de nombre: `t-name` no coincide con `static template`, o el `.xml` no está en el manifest.
- **Una variable aparece como `undefined`.** En la plantilla solo ves lo que expone el componente (`this`, `props`, `state` y lo que cuelgue de ellos). Si necesitas un valor derivado, créalo como `get` en la clase.
- **`t-key` ausente en `t-foreach`.** OWL no compila la plantilla. El mensaje habla de `t-key`.
- **El xpath no encuentra el nodo.** La plantilla original cambió de estructura entre versiones, o no apuntas al nodo correcto. Comprueba el nombre exacto de clase y de etiqueta en el código fuente.

## Buenas prácticas avanzadas

- **Lógica fuera de la plantilla.** Una expresión de más de una línea en un atributo es una señal para sacarla a un `get` del componente. La plantilla debe leerse de un vistazo.
- **Usa claves `t-key` estables, nunca el índice.** Con el índice, si se inserta un elemento al principio, OWL cree que todos cambiaron y destruye y recrea el DOM de cada uno; con un id, mueve solo lo necesario.
- **Prefiere `extension` con xpath mínimos.** Cuanto más específico sea tu xpath (una clase concreta, no una posición `div[3]`), menos se rompe cuando Odoo actualiza la plantilla original.
- **Nombra tus plantillas con prefijo de módulo.** `mi_modulo.TaskCard`, no `TaskCard`. Los `t-name` son globales y un choque de nombres entre módulos es silencioso: gana el último en cargar.
- **No uses `t-raw` ni insertes HTML de usuario sin pasar por `markup`.** Un nombre de tarea con `<script>` es un ataque; `t-out` lo neutraliza por defecto y no debes saltarte esa protección.

## Documentación oficial

- [QWeb templates (Odoo 18)](https://www.odoo.com/documentation/18.0/developer/reference/frontend/qweb.html) — la referencia de todas las directivas `t-...`, con la sección específica de la herencia de plantillas en el cliente.
- [Owl, documentación de plantillas](https://github.com/odoo/owl/blob/master/doc/reference/templates.md) — el detalle de lo que soporta el compilador de plantillas de Owl: `t-key`, `t-call`, `t-slot`, `t-ref`.

---

*En resumen: una plantilla QWeb de cliente es HTML en XML con directivas `t-...` que se evalúan como JavaScript, y para cambiar una ya existente se hereda con `t-inherit` y `xpath` en lugar de copiarla.*
