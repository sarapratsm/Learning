# Contratos de API — Guía de tecnologías

Cómo escribir, versionar y mantener el **contrato** de una API (un fichero OpenAPI) para que siga siendo un acuerdo fiable entre quien la ofrece y quien la consume: desde escribirlo antes del código y declarar quién puede llamar a cada operación, hasta decidir quién aprueba un cambio y qué comprueba la integración continua.

Está pensada para perfiles backend que ya han construido o consumido una API REST, pero que han vivido el día en que un cambio «pequeño» rompió a otro equipo. No presupone conocer OpenAPI: cada concepto se explica desde el problema que resuelve, con un fragmento de contrato y su efecto en el cliente.

Todas las fichas usan el mismo ejemplo de principio a fin —el contrato de una tienda online con `Product` y `Order`— para que las piezas encajen entre documentos. Para entender los distintos estilos de API (REST, GraphQL, gRPC...), consulta antes [Tipos de APIs](../tipos-de-apis/README.md).

---

## Orden de lectura recomendado

Sigue este orden si partes de cero. Cada bloque responde a una pregunta distinta sobre el contrato y se apoya en el anterior.

### 1. El contrato como punto de partida

Antes de versionar o gobernar nada, hay que entender qué es un contrato y por qué se escribe primero.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Contrato primero](Contrato-Primero.md) | Qué es un contrato OpenAPI, su anatomía mínima y por qué conviene acordarlo antes de programar. |

### 2. Que el contrato pueda crecer sin romper a nadie

La API va a cambiar. Este bloque enseña a distinguir un cambio seguro de una ruptura y qué papel juega el esquema.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 2 | [Versionado de contratos](Versionado-de-Contratos.md) | Qué cuenta como ruptura, cuándo sube cada número de la versión y la ruptura silenciosa de cambiar el significado sin cambiar la forma. |
| 3 | [additionalProperties y clientes generados](Additional-Properties-y-Clientes-Generados.md) | Una línea del esquema decide si añadir un campo es seguro. Y cómo se ve el contrato desde el cliente generado. |

### 3. Que el contrato diga la verdad

Un contrato que miente es peor que ninguno. Aquí, las dos partes que más se desfasan: los errores y la parte escrita para personas.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 4 | [Modelado de errores](Modelado-de-Errores.md) | `code` estable, errores por campo y por qué un error nunca debe devolver el valor que falló. |
| 5 | [Descripciones y ejemplos fieles](Descripciones-y-Ejemplos-Fieles.md) | Qué debe contar una descripción, cómo deben ser los ejemplos y cómo detectar que se han desfasado. |

### 4. Que el contrato diga quién puede llamar

La parte del contrato que decide qué ve cada persona y que casi nunca se escribe.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 6 | [Seguridad en el contrato](Seguridad-en-el-Contrato.md) | Declarar la credencial, la diferencia entre `401`, `403` y `404`, exponer lo mínimo en una operación abierta y probar las garantías de acceso. |

### 5. Que el contrato cambie a propósito

El cierre del recorrido: el proceso que mantiene todo lo anterior.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 7 | [Gobierno de cambios en contratos](Gobierno-de-Cambios-en-Contratos.md) | Quién aprueba qué, qué comprueba la integración continua y qué hacer cuando el código y el contrato discrepan. |

---

<details>
<summary>Ver todos los archivos</summary>

- [Contrato primero](Contrato-Primero.md)
- [Versionado de contratos](Versionado-de-Contratos.md)
- [additionalProperties y clientes generados](Additional-Properties-y-Clientes-Generados.md)
- [Modelado de errores](Modelado-de-Errores.md)
- [Descripciones y ejemplos fieles](Descripciones-y-Ejemplos-Fieles.md)
- [Seguridad en el contrato](Seguridad-en-el-Contrato.md)
- [Gobierno de cambios en contratos](Gobierno-de-Cambios-en-Contratos.md)

</details>

> Relacionado: [REST](../tipos-de-apis/REST.md) explica el estilo de API cuyo contrato se describe aquí, y [Tipos de APIs](../tipos-de-apis/README.md) sitúa REST entre el resto de estilos.
