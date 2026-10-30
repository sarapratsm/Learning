# Componentes OWL

## ¿Qué es?

OWL (*Odoo Web Library*) es el framework de componentes con el que está escrito el cliente web de Odoo. Un componente es una clase de JavaScript que va emparejada con una plantilla XML: la clase guarda el estado y la lógica, y la plantilla dice cómo se pinta ese estado.

## ¿Por qué existe?

Construir una interfaz con `document.querySelector` y `innerHTML` obliga a sincronizar a mano lo que ves con los datos: cambia un dato y tienes que acordarte de actualizar cada trozo de pantalla que lo muestra. Un componente invierte el planteamiento: declaras cómo se ve la pantalla **para un estado dado**, y el framework repinta solo lo que cambió cuando el estado cambia.

> Si conoces React o Vue, OWL es lo mismo en otro idioma: componentes, estado reactivo y *hooks*. Si no, piensa en una plantilla de servidor (como las de Jinja o Razor) que se vuelve a evaluar sola cada vez que cambia una variable.

Odoo 18 usa Owl 2.

## ¿Cuándo y para qué se usa?

Todo lo interactivo del cliente web es un componente: el icono de la barra superior, cada vista (lista, kanban, calendario), cada campo de un formulario, cada diálogo. Si quieres añadir una pieza de interfaz propia, o cambiar una existente, vas a escribir o a extender uno.

---

## Un componente mínimo

Una clase, una plantilla y un registro de dónde se usa. Este contador es el «hola mundo»:

```js
import { Component, useState } from "@odoo/owl";

export class Counter extends Component {
    static template = "mi_modulo.Counter";
    static props = {};

    setup() {
        this.state = useState({ value: 0 });
    }

    increment() {
        this.state.value++;
    }
}
```

```xml
<templates xml:space="preserve">
    <t t-name="mi_modulo.Counter">
        <button class="btn btn-primary" t-on-click="increment">
            Clicks: <t t-esc="state.value"/>
        </button>
    </t>
</templates>
```

Qué hace cada pieza:

- `static template` — el nombre de la plantilla (`t-name`) que pinta este componente. Por convención, `<modulo>.<Componente>`.
- `static props` — las propiedades que el componente acepta de quien lo usa (ver más abajo). `{}` significa que no recibe ninguna.
- `setup()` — el sustituto del constructor. Aquí se prepara el estado y se enganchan los *hooks*. En un componente de Odoo **no se usa `constructor`**.
- `useState` — convierte un objeto en estado reactivo. Al hacer `this.state.value++`, OWL detecta el cambio y repinta el botón.
- `t-on-click="increment"` — la plantilla llama al método de la clase.

Al pulsar, el texto pasa de `Clicks: 0` a `Clicks: 1` sin escribir ninguna línea de actualización del DOM.

## Props: lo que un componente recibe

Las *props* son los parámetros del componente, y son de solo lectura. Se declaran con su tipo para que OWL avise (en modo desarrollo) si alguien pasa algo equivocado:

```js
export class Badge extends Component {
    static template = "mi_modulo.Badge";
    static props = {
        label: String,
        color: { type: String, optional: true },
    };
}
```

```xml
<t t-name="mi_modulo.Badge">
    <span class="badge" t-att-class="'text-bg-' + (props.color || 'secondary')">
        <t t-esc="props.label"/>
    </span>
</t>
```

Y se usa desde otra plantilla como si fuera una etiqueta, pasando las props como atributos:

```xml
<Badge label="'Urgente'" color="'danger'"/>
```

Fíjate en las comillas simples dentro de las dobles: lo que va entre comillas dobles es una **expresión JavaScript**, así que una cadena literal necesita sus propias comillas. Sin ellas, OWL buscaría una variable llamada `Urgente`.

Para que una plantilla pueda usar un componente hijo, la clase padre lo declara en `static components = { Badge }`.

## El ciclo de vida: los *hooks* `on...`

Un componente nace, se actualiza y muere. Los *hooks* de ciclo de vida son funciones que se llaman en `setup()` y registran código para cada momento:

| Hook | Cuándo se ejecuta | Uso típico |
|---|---|---|
| `onWillStart(async () => ...)` | Antes del primer pintado; se espera a que acabe | Cargar datos del servidor |
| `onMounted(() => ...)` | Cuando el componente ya está en pantalla | Medir el DOM, enfocar un campo |
| `onPatched(() => ...)` | Después de cada repintado | Reaccionar a un cambio ya visible |
| `onWillUnmount(() => ...)` | Justo antes de retirarse | Limpiar temporizadores y suscripciones |

Un ejemplo habitual es recargar algo cada cierto tiempo. El temporizador se crea al arrancar y **se borra al salir**:

```js
setup() {
    const timer = setInterval(() => this.reload(), 2 * 60 * 1000);
    onWillUnmount(() => clearInterval(timer));
}
```

Sin el `onWillUnmount`, el intervalo seguiría ejecutándose aunque el usuario ya hubiera cambiado de pantalla, y cada visita acumularía otro. Es una de las fugas más comunes.

## Servicios y utilidades de Odoo

Para hablar con el servidor, mostrar avisos o abrir acciones, el cliente web ofrece **servicios**, que se piden con `useService`:

```js
import { useService } from "@web/core/utils/hooks";

setup() {
    this.orm = useService("orm");
    this.notification = useService("notification");
}

async markDone(taskId) {
    await this.orm.write("project.task", [taskId], { state: "done" });
    this.notification.add("Tarea guardada", { type: "success" });
}
```

- `orm` — llamar a métodos del modelo (`read`, `write`, `searchRead`, `call`...) sin escribir la petición HTTP.
- `notification` — el aviso flotante.
- `action` — abrir una acción de ventana, un formulario...

Para llamadas a un endpoint propio (un `@http.route` de tu módulo), se usa `rpc` de `@web/core/network/rpc`.

Dos utilidades más que conviene conocer: `useBus` (escuchar el bus de eventos, ver [el bus de eventos de OWL](../bus-de-eventos-owl/Bus-de-Eventos-OWL.md)) y `useDebounced` de `@web/core/utils/timing`, que agrupa llamadas repetidas en una sola (útil para guardar mientras alguien escribe).

## Errores frecuentes

- **El estado no repinta.** Estás cambiando un objeto normal en lugar de uno envuelto con `useState`, o reasignas la variable en vez de mutar el estado. `this.state = {...}` fuera de `setup` no es reactivo.
- **`Invalid props for component 'X'`.** Falta una prop declarada como obligatoria, o llega con un tipo distinto. El mensaje de la consola dice cuál.
- **`Missing template`.** El `static template` no coincide con el `t-name`, o el `.xml` no está en el manifest ([Estructura y assets](Estructura-y-Assets.md)).
- **`this` es `undefined` dentro de una función.** Pasaste un método como callback sin atarlo. En plantillas, `t-on-click="increment"` ya lo ata; en JavaScript usa una flecha: `() => this.increment()`.

## Buenas prácticas avanzadas

- **Limpia siempre lo que creas.** Cada `setInterval`, `addEventListener` o suscripción manual necesita su `onWillUnmount`. En una aplicación que el usuario deja abierta todo el día, una fuga pequeña se vuelve un navegador lento.
- **Carga datos en `onWillStart`, no en `setup`.** `setup` es síncrono: una llamada `await` ahí no bloquea el primer pintado, y el componente aparece vacío y luego «salta» cuando llegan los datos.
- **Mantén el estado mínimo.** Guarda en `useState` lo que no se puede derivar. Lo que se calcula a partir del estado va en un `get` de la clase, que se reevalúa solo.
- **Un componente, una responsabilidad.** Si una plantilla crece más allá de lo que cabe en una pantalla, extrae un hijo con sus propias props. Es más fácil de probar y de heredar.
- **Aprovecha las clases de Odoo antes de escribir las tuyas.** Muchas piezas (diálogos, desplegables, campos) ya existen. Extenderlas casi siempre sale más barato que reescribirlas.

## Documentación oficial

- [Owl components (Odoo 18)](https://www.odoo.com/documentation/18.0/developer/reference/frontend/owl_components.html) — la referencia de Odoo sobre cómo se usa Owl dentro del cliente web; empieza por aquí para ver la integración con servicios y registros.
- [Owl, documentación del proyecto](https://github.com/odoo/owl/blob/master/doc/readme.md) — el detalle del framework en sí: hooks, props, referencias, ciclo de vida. Útil cuando la duda es de Owl y no de Odoo.

## Recursos didácticos

- [Owl playground](https://odoo.github.io/owl/playground/) — un editor en el navegador con ejemplos de Owl para ejecutar y modificar sin instalar nada. Es la manera más rápida de ver cómo reacciona el estado.

---

*En resumen: un componente OWL es una clase con estado reactivo y una plantilla que lo pinta; tú cambias el estado y el framework se ocupa del resto, siempre que limpies lo que creas al salir.*
