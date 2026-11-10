# Búsqueda y filtros en Odoo — Guía de tecnología

Guía sobre **cómo se filtran y se buscan registros en Odoo**: desde el lenguaje de dominios que hay debajo de todo, hasta la vista de búsqueda, el *search panel* lateral y los filtros que se calculan según el contexto. Está pensada para perfiles backend que empiezan a desarrollar o personalizar vistas en Odoo y ya conocen los [fundamentos](../fundamentos/README.md).

A diferencia de la carpeta de [pruebas seguras](../pruebas-seguras/README.md), el foco aquí es de **desarrollo**: cómo se construyen las herramientas de búsqueda que ve la persona usuaria. Las fichas se contrastan con la documentación oficial y con el código fuente de la rama estable vigente de `odoo/odoo`, con la versión indicada en cada afirmación; no se ejecutó ninguna instancia de Odoo para escribirlas, y cada ficha lo dice.

---

## Orden de lectura recomendado

Cada ficha apoya a la siguiente: primero el mecanismo común, luego dónde se declara y por último cómo se calcula según el contexto.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Dominios](Dominios.md) | El cimiento: el lenguaje con el que Odoo expresa cualquier filtro, con su notación polaca y sus operadores. |
| 2 | [Vista de búsqueda](Vista-de-Busqueda.md) | Dónde se declaran los campos buscables, los filtros y las agrupaciones de un listado. |
| 3 | [Search Panel](Search-Panel.md) | El panel lateral de filtrado por facetas. |
| 4 | [Dominios dinámicos](Dominios-Dinamicos.md) | Filtros que se calculan según otro campo, el usuario o una lógica en Python. |

---

> ¿Vas a probar estos cambios sobre datos reales? Repasa antes cómo hacerlo sin riesgos en [Pruebas seguras](../pruebas-seguras/README.md). La estructura que devuelve cualquier búsqueda está en [Recordsets](../fundamentos/Recordsets.md).
