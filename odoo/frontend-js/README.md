# Frontend de Odoo — Guía de tecnología

Cómo se construye la parte del cliente web de Odoo que se ejecuta en el navegador: dónde viven los ficheros de un módulo y cómo se declaran en el manifest, los componentes Owl, las plantillas QWeb de cliente y los estilos SCSS. Pensada para quien ya sabe programar pero no ha tocado el frontend de Odoo.

---

## Orden de lectura recomendado

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Estructura y assets](Estructura-y-Assets.md) | Dónde van los ficheros, cómo se declaran en el `assets` del manifest y cómo ver los cambios. Sin esto, nada de lo demás se carga. |
| 2 | [Componentes OWL](Componentes-OWL.md) | La pieza central: clase, estado reactivo, props, ciclo de vida y servicios de Odoo. |
| 3 | [Plantillas QWeb de cliente](Plantillas-QWeb-de-Cliente.md) | El lenguaje de plantillas de cada componente y cómo heredar la plantilla de una pieza existente. |
| 4 | [SCSS y clases CSS](SCSS-y-Clases-CSS.md) | Dar estilo sin afectar a otras pantallas y resolver los choques con Bootstrap y con Odoo. |

---

> Para ver estas piezas aplicadas a un caso concreto, la guía del [systray](../systray/README.md) construye un icono propio con un componente Owl, y la del [bus de eventos de OWL](../bus-de-eventos-owl/README.md) conecta dos componentes que no se conocen.
