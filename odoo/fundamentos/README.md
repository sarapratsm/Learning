# Fundamentos de Odoo — Guía de tecnología

Guía para **entender qué es Odoo y cómo está montado por dentro** antes de tocar nada. Está pensada para perfiles backend que se acercan por primera vez a este ERP: qué problema resuelve, cómo se le añade funcionalidad, qué conceptos propios hay que tener claros (los modelos de «persona», el modo desarrollador) y la estructura de datos —el recordset— que devuelve cualquier consulta al ORM.

Es la base del resto de la carpeta: sin esto, ni las pruebas seguras ni el desarrollo de búsquedas y filtros tienen contexto. Las fichas se contrastan con la documentación oficial y con el código fuente de la rama estable vigente de `odoo/odoo`, indicando la versión en cada afirmación; no se ejecutó ninguna instancia de Odoo para escribirlas, y cada ficha lo dice.

---

## Orden de lectura recomendado

Cada ficha apoya a la siguiente: primero qué es Odoo, luego cómo crece, después su modelo de personas, la herramienta para ver la capa técnica y, por último, la estructura de datos del ORM.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Odoo](Odoo.md) | El punto de partida: qué es, su arquitectura (Python, PostgreSQL y cliente web), las ediciones y las versiones en soporte. |
| 2 | [Módulos y Apps](Modulos-y-Apps.md) | Cómo se añade funcionalidad, qué ocurre al instalar, actualizar y desinstalar, y por qué instalar un módulo es un cambio serio. |
| 3 | [Partner, Usuario y Empleado](Partner-Usuario-y-Empleado.md) | Los tres modelos de «persona» y por qué no son lo mismo: contacto, login y ficha laboral. |
| 4 | [Modo desarrollador](Modo-Desarrollador.md) | El interruptor que revela la capa técnica y los riesgos de usarlo sobre producción. |
| 5 | [Recordsets](Recordsets.md) | La estructura de datos que devuelve cualquier consulta del ORM, y la trampa de compararla contra un id plano. |

---

> ¿Listo para tocar un sistema real? Sigue con [Pruebas seguras](../pruebas-seguras/README.md) antes de probar nada sobre datos de producción.
