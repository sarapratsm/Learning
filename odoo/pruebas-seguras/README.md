# Pruebas seguras en Odoo — Guía de tecnología

Guía sobre **cómo probar cambios sobre un Odoo real sin llevárselo por delante**: dónde probar, cómo aislar los datos de producción y cómo tener siempre marcha atrás. Está pensada para perfiles backend que van a trabajar con un sistema que ya usan personas de verdad.

Da por sabidos los [fundamentos](../fundamentos/README.md) (qué es Odoo, módulos, modo desarrollador). El foco es la operación segura: separar entornos, duplicar y neutralizar la base de datos, y respaldar antes de cada cambio. Las fichas se contrastan con la documentación oficial de Odoo y de PostgreSQL y con el código fuente de la rama estable vigente de `odoo/odoo`, con la versión indicada; no se ejecutó ninguna instancia ni ningún comando de backup o restauración para escribirlas, y cada ficha marca como no ejecutado lo que lo es.

---

## Orden de lectura recomendado

De la idea general a la práctica concreta, y termina con el procedimiento que reúne todo.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Entornos: desarrollo, staging y producción](Entornos-dev-staging-produccion.md) | La idea base: separar entornos para tener un sitio donde equivocarse. |
| 2 | [Duplicar la base de datos](Duplicar-Base-de-Datos.md) | El primer paso: una copia realista de producción, con su filestore, para probar sobre datos de verdad. |
| 3 | [Neutralizar la base de datos](Neutralizar-Base-de-Datos.md) | El paso imprescindible: qué desactiva exactamente la neutralización en la copia y qué deja sin tocar. |
| 4 | [Backups y restauración](Backups-y-Restauracion.md) | La red de seguridad: qué respaldar, cómo restaurar y por qué un backup no probado no cuenta. |
| 5 | [Pruebas seguras sobre un Odoo en producción](Pruebas-Seguras-en-Produccion.md) | La síntesis: cuándo se puede tocar producción, el checklist y lo que no tiene vuelta atrás. |

---

> ¿Vas a desarrollar vistas o filtros sobre esa copia? Echa un ojo a [Búsqueda y filtros](../busqueda-y-filtros/README.md). Los comandos de copias de seguridad en un servidor propio se tratan también en [Copias de seguridad](../../devops/despliegue-en-vps/Copias-de-Seguridad.md).
