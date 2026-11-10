# Configuración de parámetros en Odoo — Guía de tecnología

Guía sobre **las distintas maneras de configurar parámetros en Odoo**: dónde poner cada valor configurable para no dejarlo clavado en el código. Va desde la configuración del servidor hasta las referencias a registros concretos, pasando por los parámetros globales, la pantalla de Ajustes, la configuración por compañía y los valores por defecto. Está pensada para perfiles backend que empiezan a desarrollar o administrar Odoo.

La pregunta que une toda la colección es una sola: **¿dónde vive este valor?** Elegir bien el sitio evita el problema más común en un módulo descuidado: números y textos «mágicos» repartidos por el código que se rompen al cambiar de entorno. Las fichas se contrastan con la documentación oficial y con el código fuente de la rama estable vigente de `odoo/odoo`, con la versión indicada; no se ejecutó ninguna instancia de Odoo para escribirlas, y cada ficha lo dice.

---

## Orden de lectura recomendado

De la capa más externa (el servidor) a la más interna (referencias entre registros). Cada ficha resuelve un tipo de valor distinto.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [El fichero odoo.conf](El-Fichero-odoo-conf.md) | La capa de infraestructura: lo que el servidor necesita para arrancar, antes de que exista lógica de negocio. |
| 2 | [Parámetros del sistema (ir.config_parameter)](Parametros-del-Sistema.md) | El almacén global clave-valor de la base de datos: valores que se cambian en caliente sin redeploy. |
| 3 | [Ajustes (res.config.settings)](Ajustes.md) | La pantalla que expone esos parámetros a quien administra el negocio. |
| 4 | [Configuración por compañía](Configuracion-por-Compania.md) | El mismo parámetro con un valor distinto en cada empresa (multi-compañía). |
| 5 | [Valores por defecto](Valores-por-Defecto.md) | Qué se precarga en un campo al crear un registro y desde dónde definirlo. |
| 6 | [Referencias por ID externo (XML ID)](Referencias-por-ID-Externo.md) | Cómo apuntar a un registro concreto sin clavar su ID numérico y cómo adoptar un registro creado a mano sin duplicarlo. |

---

## Dónde vive cada valor

| El valor es… | Se guarda en… | Ficha |
|---|---|---|
| Necesario para arrancar el servidor (base de datos, puertos, workers) | `odoo.conf` | [El fichero odoo.conf](El-Fichero-odoo-conf.md) |
| Global a la base de datos y cambia sin reiniciar | `ir.config_parameter` | [Parámetros del sistema](Parametros-del-Sistema.md) |
| Editable por quien administra, desde la interfaz | `res.config.settings` | [Ajustes](Ajustes.md) |
| Distinto en cada compañía | Campo de la compañía o `company_dependent` | [Configuración por compañía](Configuracion-por-Compania.md) |
| El valor inicial de un campo al crear un registro | `default=`, contexto o `ir.default` | [Valores por defecto](Valores-por-Defecto.md) |
| Un registro concreto al que hay que apuntar | ID externo (`ir.model.data`) | [Referencias por ID externo](Referencias-por-ID-Externo.md) |

---

> ¿Vas a aplicar estos cambios sobre un sistema real? Repasa antes cómo hacerlo sin riesgos en [Pruebas seguras](../pruebas-seguras/README.md). Los conceptos previos están en [Fundamentos](../fundamentos/README.md).
