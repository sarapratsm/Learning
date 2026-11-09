# Multi-Tenancy — Guía de tecnologías

Guías sobre **multi-tenancy**: cómo una sola aplicación da servicio a muchas empresas clientes —*tenants*— manteniendo sus datos separados. Cubren desde el concepto y las estrategias de aislamiento hasta cómo se identifica el tenant en cada petición, cómo se garantiza que nadie vea datos de otro tenant y cómo se opera el sistema cuando crece. Están pensadas para perfiles backend junior-medio que conocen C#, EF Core y HTTP, sin experiencia previa con SaaS.

Todas comparten el mismo ejemplo: una aplicación SaaS de gestión de pedidos con los tenants `acme` y `globex` en `miapp.ejemplo.com`. El peligro que cada guía ilustra desde su ángulo es siempre el mismo: que un pedido de `acme` llegue a verlo `globex`. Los ejemplos son C#/.NET y las ideas valen para cualquier stack.

---

## Orden de lectura recomendado

### 1. El concepto

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Multi-Tenancy](Multi-Tenancy.md) | La idea base: una aplicación, muchos clientes, datos separados, y el riesgo de la fuga entre tenants. |

### 2. Dónde viven los datos

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 2 | [Estrategias de Aislamiento](Estrategias-de-Aislamiento.md) | Base por tenant, esquema por tenant o base compartida: el equilibrio entre aislamiento, coste y complejidad. |

### 3. Cómo sabe la aplicación de quién es cada petición

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 3 | [Identificación del Tenant](Identificacion-del-Tenant.md) | Averiguar a qué tenant pertenece cada petición (subdominio, cabecera, token) y por qué importa quién controla el dato. |
| 4 | [Tenant Context](Tenant-Context.md) | Dónde se guarda el tenant actual para que todas las capas lo usen, también fuera de una petición HTTP. |

### 4. Garantizar que nadie vea datos de otro

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 5 | [Aislamiento por Fila](Aislamiento-por-Fila.md) | Filtrar siempre por `TenantId` de forma automática: *query filters* de EF Core y Row-Level Security del motor. |

### 5. Operar a escala

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 6 | [Aprovisionamiento y Migraciones](Aprovisionamiento-y-Migraciones.md) | Crear el espacio de cada tenant nuevo y aplicar cambios de esquema a todos. |
| 7 | [Retos Avanzados](Retos-Avanzados.md) | Vecino ruidoso, configuración por tenant, caché y fugas entre tenants. |

---

## Qué decide cada pieza

El recorrido de una petición, con la ficha que explica cada paso.

| Paso | Qué se decide | Ficha |
|---|---|---|
| 1. Llega la petición a `acme.miapp.ejemplo.com` | De qué tenant es | [Identificación del Tenant](Identificacion-del-Tenant.md) |
| 2. Se guarda el tenant para esa petición | Quién puede leerlo y cuánto vive | [Tenant Context](Tenant-Context.md) |
| 3. Se elige dónde están sus datos | Base, esquema o fila | [Estrategias de Aislamiento](Estrategias-de-Aislamiento.md) |
| 4. Se consulta la base de datos | Que solo salgan filas del tenant | [Aislamiento por Fila](Aislamiento-por-Fila.md) |
| Al dar de alta un cliente o cambiar el esquema | Cómo se crea y se migra cada tenant | [Aprovisionamiento y Migraciones](Aprovisionamiento-y-Migraciones.md) |
| En producción, con muchos clientes | Convivencia, caché y configuración | [Retos Avanzados](Retos-Avanzados.md) |

## Preguntas que resuelve cada ficha

| Pregunta | Ficha |
|---|---|
| ¿Merece la pena servir a todos los clientes desde una sola instalación? | [Multi-Tenancy](Multi-Tenancy.md) |
| ¿Una base de datos por cliente, o todos en la misma? | [Estrategias de Aislamiento](Estrategias-de-Aislamiento.md) |
| ¿Puedo fiarme de la cabecera `X-Tenant-Id`? | [Identificación del Tenant](Identificacion-del-Tenant.md) |
| ¿Dónde guardo el tenant actual, y qué pasa en un trabajo en segundo plano? | [Tenant Context](Tenant-Context.md) |
| ¿Cómo evito que una consulta olvide el filtro por tenant? | [Aislamiento por Fila](Aislamiento-por-Fila.md) |
| ¿Cómo aplico una migración a 500 clientes? | [Aprovisionamiento y Migraciones](Aprovisionamiento-y-Migraciones.md) |
| ¿Cómo evito que un cliente degrade a los demás, o que la caché mezcle datos? | [Retos Avanzados](Retos-Avanzados.md) |

---

> Guías relacionadas: [Clean Architecture](../clean-architecture/README.md) explica dónde encajan el contexto del tenant y los repositorios; [Migraciones de esquema](../../bases-de-datos/migraciones-de-esquema/README.md) y [Caching](../../bases-de-datos/caching/README.md) profundizan en dos de los retos de la última ficha.
