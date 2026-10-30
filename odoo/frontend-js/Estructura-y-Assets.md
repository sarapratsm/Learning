# Estructura y assets del frontend de Odoo

## ¿Qué es?

El frontend de Odoo es el código JavaScript, las plantillas XML y las hojas de estilo SCSS que se ejecutan en el navegador. Un módulo los guarda en `static/src/` y los declara en el apartado `assets` de su `__manifest__.py`; Odoo los empaqueta en *bundles* y los sirve al cliente web.

## ¿Por qué existe?

Un módulo Python se carga porque está en el `addons_path`. Con el frontend no basta: el navegador solo descarga lo que el servidor le ofrece dentro de un paquete concreto. Si creas un fichero `.js` en `static/src/` y no lo declaras, existe en disco pero nadie lo carga, y no aparece ningún error.

> Si vienes del mundo web clásico, un *bundle* es lo que genera Webpack o Vite: varios ficheros fusionados y minificados en uno. La diferencia es que aquí lo hace el servidor de Odoo al vuelo, a partir de la lista del manifest.

## ¿Cuándo y para qué se usa?

Cada vez que tu módulo añade algo que el usuario ve o con lo que interactúa en el cliente web: un icono en la barra superior, una vista con comportamiento propio, un botón que reacciona sin recargar la página o simplemente unos cuantos estilos.

---

## La estructura de carpetas

Por convención, todo lo del cliente vive bajo `static/src/`:

```
mi_modulo/
├── __manifest__.py
└── static/
    └── src/
        ├── components/
        │   └── contador/
        │       ├── contador.js     ← lógica del componente
        │       ├── contador.xml    ← plantilla
        │       └── contador.scss   ← estilos
        └── views/
            └── calendario_vista.js
```

Agrupar por componente, con los tres ficheros juntos y el mismo nombre base, facilita encontrar todo lo que afecta a una pieza de la interfaz.

## Declarar los ficheros en el manifest

El apartado `assets` asocia una lista de rutas a un bundle. Para el backend (la interfaz de trabajo interna), el bundle es `web.assets_backend`:

```python
{
    'name': 'Mi módulo',
    'depends': ['web'],
    'assets': {
        'web.assets_backend': [
            'mi_modulo/static/src/components/contador/contador.js',
            'mi_modulo/static/src/components/contador/contador.xml',
            'mi_modulo/static/src/components/contador/contador.scss',
        ],
    },
}
```

Hay que saber tres cosas:

- Las rutas empiezan por el **nombre técnico del módulo**, no por `static/`.
- Los tres tipos de fichero (`.js`, `.xml`, `.scss`) van en la misma lista. Odoo los distingue por la extensión.
- Con muchos ficheros puedes usar un comodín: `'mi_modulo/static/src/**/*'` incluye todo lo que cuelga de `static/src`. Es cómodo, pero también arrastra ficheros que no querías; ten cuidado con tests o ficheros de prueba en esa carpeta.

Otros bundles que verás: `web.assets_frontend` (el sitio web público y el portal) y `web.assets_tests` (tests de integración). Para este tutorial basta con `web.assets_backend`.

## Importar entre ficheros

El código de Odoo usa módulos ES (`import` / `export`). Cada fichero declara lo que necesita:

```js
import { Component, useState } from "@odoo/owl";
import { registry } from "@web/core/registry";
```

Las rutas con `@` siguen una regla fija: `@<modulo>/<ruta bajo static/src sin extensión>`.

| Quieres importar | Escribes |
|---|---|
| El framework Owl | `@odoo/owl` |
| `static/src/core/registry.js` del módulo `web` | `@web/core/registry` |
| `static/src/components/contador/contador.js` de `mi_modulo` | `@mi_modulo/components/contador/contador` |

No hace falta que el fichero lleve la cabecera `/** @odoo-module **/` en Odoo 18: los ficheros de `static/src` declarados en un bundle ya se tratan como módulos. En versiones anteriores sí era obligatoria; si la ves en código de otro proyecto, es inofensiva.

Para poder importar algo de otro módulo, ese módulo tiene que estar en el `depends` del manifest (o ser una dependencia indirecta), porque si no su código no estará en el bundle cuando se evalúe el tuyo.

## Ver los cambios: el ciclo de trabajo

Aquí es donde más tiempo se pierde al empezar. Los bundles se generan una vez y se guardan en caché, de modo que cambiar un fichero no basta para que el navegador lo vea.

| Situación | Qué hacer |
|---|---|
| Desarrollo local | Abre la URL con `?debug=assets`. Odoo sirve los ficheros sueltos y los regenera al recargar. |
| Has creado un fichero nuevo o cambiado el manifest | Reinicia el servidor y actualiza el módulo (`-u mi_modulo`). |
| Servidor de pruebas o producción | Actualiza el módulo (`-u mi_modulo`) y reinicia el servicio. Después, recarga el navegador con `Ctrl+F5`. |

Si tras actualizar sigues viendo el comportamiento antiguo, casi siempre es la caché del navegador. Prueba con `Ctrl+F5` o con `?debug=assets`.

## Errores frecuentes

- **"Mi componente no aparece."** El fichero no está en el manifest, o la ruta tiene una errata (`static/` al principio, mayúsculas distintas). Odoo no avisa de rutas que no existen en todos los casos.
- **`Cannot find module '@mi_modulo/...'`** en la consola del navegador. La ruta de importación no sigue la regla de arriba, o el fichero importado no está en ningún bundle.
- **La plantilla XML no se encuentra** (`Missing template`). El `.xml` se te olvidó en el manifest, aunque el `.js` sí esté.
- **Los cambios no se ven.** Estás sin `?debug=assets`, o en un servidor donde no has actualizado el módulo.

## Buenas prácticas avanzadas

- **Lista los ficheros uno a uno hasta que el módulo se estabilice.** El comodín `**/*` oculta de un vistazo qué cargas, y al añadir un fichero experimental termina en producción sin que nadie lo decida.
- **Mantén el mismo nombre base para `.js`, `.xml` y `.scss` de una pieza.** Cuando buscas "dónde se pinta esto" en un proyecto con cientos de ficheros, buscar por nombre es lo más rápido.
- **Pon las dependencias en el `depends` aunque ya vengan indirectas.** Si mañana el módulo intermedio deja de depender del que usas, tu import se rompe sin aviso.
- **No metas lógica de negocio en el frontend.** Un cálculo que decide una factura o un permiso va en Python. El cliente puede ser manipulado desde la consola del navegador; el servidor, no.
- **Comprueba en la pestaña *Network* con `?debug=assets`** que tu fichero se descarga. Es la prueba más rápida de que el manifest está bien.

## Documentación oficial

- [Assets (Odoo 18)](https://www.odoo.com/documentation/18.0/developer/reference/frontend/assets.html) — la referencia de bundles, de la sintaxis de `assets` en el manifest y de las directivas (`include`, `prepend`, `replace`, `remove`). Empieza por la sección sobre cómo declarar assets.

## Recursos didácticos

- Las herramientas de desarrollo del navegador (`F12`, pestañas *Sources* y *Network*) son el mejor instrumento: con `?debug=assets` verás tus ficheros por nombre en *Sources* y podrás poner puntos de interrupción.

---

*En resumen: un fichero del frontend solo existe para Odoo si está en la lista `assets` del manifest, y un cambio solo se ve si recargas con `?debug=assets` o actualizas el módulo.*
