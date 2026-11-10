# Context Engineering — Guía de conceptos

Guía de context engineering: cómo diseñar y gestionar todo lo que recibe un modelo de lenguaje (LLM) en cada llamada —instrucciones, historial, documentos recuperados y salidas de herramientas— dentro de un espacio limitado. Recorre desde la idea general y su límite (la ventana de contexto) hasta las técnicas que lo llenan con información relevante (RAG), lo mantienen bajo control en tareas largas (memoria, compactación, aislamiento) y abaratan las llamadas (caché de *prompt*).

Está escrita para perfiles backend junior-medio con experiencia en APIs y bases de datos, pero sin experiencia previa integrando modelos de lenguaje. Los ejemplos comparten un escenario: un asistente de soporte de una tienda online que responde sobre pedidos (pedido #4711), devoluciones y catálogo. Las demostraciones de recuperación, troceado y presupuesto de tokens se ejecutaron con Python estándar, sin llamar a ningún modelo; lo que depende de un modelo real (calidad, precios, límites) procede de la documentación oficial citada en cada ficha, con su fecha.

---

## Orden de lectura recomendado

### 1. La idea general y su límite fundamental

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Context Engineering](Context-Engineering.md) | El mapa general: las piezas del contexto, el presupuesto, los fallos típicos y qué técnica ataca cada problema. |
| 2 | [Ventana de Contexto](Ventana-de-Contexto.md) | La restricción con la que choca todo lo demás: cuánto cabe en una llamada, qué cuesta y qué pasa al desbordarla. |

### 2. Cómo se llena el contexto con información relevante (RAG)

Las piezas que permiten que un modelo responda con datos propios y actualizados en vez de solo con lo que ya sabía.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 3 | [Embeddings y Bases de Datos Vectoriales](Embeddings-y-Bases-de-Datos-Vectoriales.md) | La pieza que permite buscar por significado: similitud, coste de la búsqueda e índices aproximados. |
| 4 | [Chunking](Chunking.md) | Cómo trocear documentos largos antes de indexarlos, y qué cortes rompen la recuperación. |
| 5 | [RAG](RAG.md) | El pipeline completo de búsqueda y generación, su evaluación y cuándo no usarlo. |

### 3. Cómo se gestiona el contexto en tareas y conversaciones largas

Qué hacer cuando la conversación o la tarea dura más de lo que cabe en una sola ventana.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 6 | [Memoria de Agentes](Memoria-de-Agentes.md) | Cómo un asistente recuerda entre mensajes y sesiones cuando el modelo no recuerda nada por sí mismo. |
| 7 | [Compactación de Contexto](Compactacion-de-Contexto.md) | Cómo resumir o podar el historial sin perder lo que importa. |
| 8 | [Aislamiento de Contexto](Aislamiento-de-Contexto.md) | Cómo repartir una tarea entre subagentes sin que el ruido de unos contamine a los demás. |

### 4. Optimización

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 9 | [Prompt Caching](Prompt-Caching.md) | Cómo evitar pagar dos veces por la parte del contexto que no cambia entre llamadas. |

---

## Qué ficha consultar según el problema

| Si el problema es… | Ficha |
|---|---|
| La conversación ya no cabe en la ventana | [Ventana de Contexto](Ventana-de-Contexto.md) y [Compactación de Contexto](Compactacion-de-Contexto.md) |
| El modelo no conoce los datos de la empresa | [RAG](RAG.md) |
| La búsqueda no encuentra el documento que existe | [Chunking](Chunking.md) y [Embeddings y Bases de Datos Vectoriales](Embeddings-y-Bases-de-Datos-Vectoriales.md) |
| El asistente repite preguntas ya contestadas en otra sesión | [Memoria de Agentes](Memoria-de-Agentes.md) |
| Las lecturas y búsquedas intermedias llenan el contexto principal | [Aislamiento de Contexto](Aislamiento-de-Contexto.md) |
| El coste por llamada crece con un prefijo que no cambia | [Prompt Caching](Prompt-Caching.md) |

---

> Esta colección trata el contexto de una llamada. La construcción de aplicaciones sobre LLM (agentes, herramientas, evaluación, seguridad) está en [Ingeniería con LLMs](../ingenieria-con-llms/README.md). Y para cómo se diseñan las APIs que exponen o consumen estos modelos, la guía de [Tipos de APIs](../../arquitectura-de-software/tipos-de-apis/README.md).
