# Chunking

## ¿Qué es?

Chunking es dividir un documento largo en fragmentos más pequeños (*chunks*, «trozos») antes de indexarlos para la búsqueda. Cada trozo se convierte en una unidad independiente: se calcula su vector (*embedding*) y se guarda con sus metadatos, y es lo que luego se recupera y se entrega al modelo.

## ¿Por qué existe?

Un sistema de búsqueda semántica o de RAG ([RAG](RAG.md)) no recupera «documentos»: recupera la unidad que se indexó. Si esa unidad es la política de devoluciones completa, la búsqueda devuelve las 1500 palabras aunque la pregunta sea «¿cuánto tarda el reembolso a mi tarjeta?». Hay tres razones para trocear:

- **Límite del modelo de embeddings.** Cada modelo de embeddings admite un máximo de tokens de entrada; lo que lo supera no se representa entero. El límite concreto está en la ficha de cada modelo y no se mide aquí (véase [Embeddings y Bases de Datos Vectoriales](Embeddings-y-Bases-de-Datos-Vectoriales.md)).
- **Precisión.** Un vector resume un texto entero en una sola posición. Si el texto trata de plazos, condiciones, envíos y reembolsos, el vector es un promedio de todo y no se parece mucho a ninguna pregunta concreta. Un trozo que habla de una sola cosa tiene un vector que apunta a esa cosa.
- **Coste y espacio de contexto.** Lo recuperado acaba dentro de la [ventana de contexto](Ventana-de-Contexto.md) y se paga por token en cada llamada. Entregar un trozo de ~200 tokens en lugar de un documento de ~2200 deja sitio para otras cosas y cuesta una fracción.

> Si ya conoces la paginación de una API o los índices de una base de datos, piensa en el chunking como decidir el tamaño de página de un índice de búsqueda: páginas demasiado grandes devuelven ruido; demasiado pequeñas, fragmentos que no se entienden solos.

## ¿Cuándo y para qué se usa?

Siempre que una base de conocimiento tenga documentos más largos que unas pocas frases: en el asistente de soporte de una tienda online, la política de devoluciones, la guía de tallas, las fichas de catálogo y las preguntas frecuentes. Las respuestas sobre un pedido concreto (el #4711) no pasan por aquí: vienen de una consulta a la base de datos, no de texto indexado.

No hace falta trocear si cada documento ya es una unidad pequeña y autocontenida (una pregunta frecuente de dos líneas, una ficha de producto corta). Trocear algo que cabe en un trozo solo añade complejidad.

## El texto de trabajo

Los ejemplos usan la política de devoluciones de la tienda: un documento Markdown de 1521 palabras, 8847 caracteres (~2200 tokens, aproximado como caracteres / 4; no hay tokenizador real). Tiene 11 secciones con encabezado `##`, una lista de pasos, una lista de condiciones y una tabla de gastos de envío. Se mide en **caracteres** para que el código sea de librería estándar; los tamaños en tokens son una aproximación.

Fragmentos del texto que importan más adelante:

```markdown
## 1. Plazo de devolución
Los productos pueden devolverse en un plazo de 30 días naturales desde la fecha de entrega...
Los productos de electrónica, como auriculares, teclados, altavoces o cargadores, pueden devolverse
en un plazo de 14 días naturales desde la entrega.

## 5. Gastos de envío de la devolución
| Motivo | Método | Coste para el cliente |
| Desistimiento | Punto de recogida | 2,95 € |
| Pedidos superiores a 80 € | Punto de recogida | 0 € |

## 10. Casos especiales
Los pedidos enviados a otro país de la Unión Europea siguen las mismas condiciones, pero el coste de la
devolución lo asume siempre el cliente, ya que el transporte internacional no es gratuito ni siquiera
en pedidos superiores a 80 €.
```

## Las cuatro estrategias básicas

Todas reciben el texto y devuelven una lista de cadenas. Se miden sobre el mismo documento (salidas del 2026-11-10; tamaño objetivo 800 caracteres, ~200 tokens).

### Tamaño fijo

Corta cada N caracteres sin mirar el contenido.

```python
def fixed(text, size, overlap=0):
    step = size - overlap
    return [text[i:i + size] for i in range(0, len(text), step) if text[i:i + size].strip()]
```

Es lo más simple y el más rápido; no sabe dónde acaba una palabra. Con `size=800` salen 12 trozos, todos de 800 caracteres salvo el último (47). Frontera entre los trozos 9 y 10:

```text
❌ trozo 9 termina:  "...lo asume siempre el cliente, ya que el trans"
   trozo 10 empieza: "porte internacional no es gratuito ni siquiera en pedidos superiores a 80 €."
```

El trozo 10, leído solo, parece decir que algo «no es gratuito ni siquiera» por encima de 80 €, sin saber que se habla de envíos internacionales ni de quién paga. La condición quedó partida: la regla está en un trozo y su sujeto en otro.

### Por frases

Trocea en frases y las agrupa hasta un máximo de caracteres, de modo que nunca corta una frase.

```python
import re
SENTENCE_END = re.compile(r"(?<=[.!?:])\s+|\n+")

def by_sentences(text, max_chars):
    chunks, current = [], ""
    for s in (s.strip() for s in SENTENCE_END.split(text) if s.strip()):
        if current and len(current) + 1 + len(s) > max_chars:
            chunks.append(current)
            current = s
        else:
            current = f"{current} {s}".strip()
    if current:
        chunks.append(current)
    return chunks
```

Con `max_chars=800` salen 12 trozos de 535 a 799 caracteres (mediana 759). Ninguna frase queda partida, pero este separador, que trata los dos puntos y los saltos de línea como fin de frase, rompe la estructura:

```text
❌ "...de modo que puedas aceptarla o recuperar el producto. Los productos de ropa..."  (fines de línea desaparecen)
❌ "Cambios de talla o de producto Si lo que necesitas es una talla..."   (el encabezado se funde con el párrafo, sin '##')
❌ "Tarjeta de crédito o débito:"  | "hasta 5 días hábiles desde la aprobación..."   (la etiqueta y su valor, en trozos distintos)
```

Las tablas y las listas se aplastan en una línea. Un separador de frases mejor (o una librería) mitiga parte de esto, pero la estructura del documento sigue sin entrar en la decisión.

### Por secciones (encabezados Markdown)

Corta en cada encabezado `##`. Cada trozo es una sección completa, con su título.

```python
def by_sections(text):
    parts = re.split(r"(?m)^(?=## )", text)
    return [p.strip() for p in parts if p.strip()]
```

Salen 12 trozos (la introducción y las 11 secciones) de 272 a 1188 caracteres (mediana 712). Respetan el significado y llevan su título. El problema es la irregularidad: una sección de 4000 caracteres se indexaría como un trozo único, de modo que esta estrategia depende de que el documento esté bien estructurado y de que las secciones no sean enormes.

### Recursivo con separadores jerárquicos

Intenta cortar por el separador de más alto nivel y baja al siguiente solo si un trozo sigue siendo demasiado grande: primero encabezados, luego párrafos, luego líneas, luego frases, luego palabras.

```python
def recursive(text, size, overlap=0, seps=("\n## ", "\n\n", "\n", ". ", " ")):
    if len(text) <= size:
        return [text.strip()] if text.strip() else []
    for sep in seps:
        if sep in text:
            break
    else:
        return fixed(text, size, overlap)
    if sep == "\n## ":                       # el encabezado viaja al inicio del trozo siguiente
        pieces = re.split(r"(?=\n## )", text)
    else:
        pieces = text.split(sep)
        pieces = [p + sep if i < len(pieces) - 1 else p for i, p in enumerate(pieces)]
    chunks, current = [], ""
    for p in pieces:
        if len(p) > size:                    # demasiado grande: recursión con el siguiente separador
            if current.strip():
                chunks.append(current.strip()); current = ""
            rest = seps[seps.index(sep) + 1:]
            chunks.extend(recursive(p, size, overlap, rest or (" ",)))
        elif len(current) + len(p) > size:
            chunks.append(current.strip())
            current = (current[-overlap:] if overlap else "") + p
        else:
            current += p
    if current.strip():
        chunks.append(current.strip())
    return chunks
```

Con `size=800` salen 17 trozos de 168 a 756 caracteres (mediana 536). Casi todos empiezan en un encabezado o en un párrafo; ninguno corta una frase. Es la estrategia por defecto razonable cuando los documentos tienen estructura y se quiere un tope de tamaño.

Tiene un defecto visible: la sección «4. Cómo solicitar una devolución» (introducción de 168 caracteres) queda separada de la lista de pasos (753 caracteres), porque la lista no cabía junto al encabezado. El trozo de los pasos empieza en `1. Accede a Mis pedidos...` sin decir de qué trata. Es el error de los encabezados que no viajan (véase más abajo).

### Resumen de las salidas

| Estrategia | Trozos | Tamaño (caracteres) mín / mediana / máx | Volumen indexado frente al original |
|---|---|---|---|
| Fijo 800 | 12 | 47 / 800 / 800 | ×1,00 |
| Fijo 800 + solape 160 | 14 | 527 / 800 / 800 | ×1,24 |
| Frases (hasta 800) | 12 | 535 / 759 / 799 | ×0,99 |
| Secciones (`##`) | 12 | 272 / 712 / 1188 | ×1,00 |
| Recursivo 800 | 17 | 168 / 536 / 756 | ×1,00 |
| Recursivo 800 + solape 160 | 17 | 168 / 641 / 917 | ×1,16 |

## El compromiso entre tamaño, precisión y contexto

No hay un tamaño universal. Cada tamaño gana en una cosa y pierde en otra:

| | Trozos pequeños (~75 tokens) | Trozos medianos (~200 tokens) | Trozos grandes (≥500 tokens) |
|---|---|---|---|
| **Precisión del vector** | Alta: una sola idea | Buena | Baja: promedia varios temas |
| **Autocontención** | Baja: «sí, dentro de 30 días» sin saber de qué | Media | Alta |
| **Riesgo de partir una condición** | Alto | Medio | Bajo |
| **Tokens por trozo recuperado** | Pocos: caben muchos | Intermedio | Muchos: caben pocos |
| **Nº de trozos a indexar** | Muchos (30 con 300 caracteres) | 12-17 | Pocos (5 con 2000 caracteres) |

Los rangos son orientativos: el tamaño correcto depende de los documentos, de la pregunta típica y del modelo de embeddings, y se decide midiendo con preguntas reales (véase el experimento más abajo). Anthropic, en su artículo sobre recuperación contextual (2024-09-19), indica que los trozos suelen ser de unos pocos cientos de tokens como máximo y que el tamaño, los límites y el solapamiento afectan al rendimiento de recuperación, así que conviene ajustarlos al caso.

## Solapamiento y su coste

El solapamiento (*overlap*) repite el final de un trozo al inicio del siguiente. Es un seguro contra cortes: si una condición cae justo en una frontera, queda entera en al menos uno de los dos trozos.

```python
fixed(text, 800, overlap=160)   # cada trozo repite los últimos 160 caracteres del anterior
```

La contrapartida es volumen: todo lo que se solapa se indexa dos veces. Con trozos de 800 caracteres sobre el texto de 8847 caracteres:

| Solapamiento | Trozos | Caracteres indexados | Tokens aprox. | Aumento |
|---|---|---|---|---|
| 0 | 12 | 8847 | ~2211 | 0 % |
| 80 (10 %) | 13 | 9807 | ~2451 | +11 % |
| 160 (20 %) | 14 | 10 927 | ~2731 | +24 % |
| 240 (30 %) | 16 | 12 447 | ~3111 | +41 % |
| 400 (50 %) | 23 | 17 294 | ~4323 | +95 % |

El aumento no es lineal: es aproximadamente `solape / (tamaño - solape)`, porque el paso entre trozos se acorta. Un 50 % de solape casi duplica el almacenamiento, el coste de calcular embeddings y el número de candidatos casi idénticos que compiten en los resultados. Con la política de 8847 caracteres es irrelevante; con millones de documentos es una decisión de coste. Valores del 10 al 20 % bastan en la mayoría de los casos; más solape suele significar que la estrategia de corte es mala y compensa cambiarla antes que solaparla.

Además, el solapamiento no arregla un trozo huérfano: repite 160 caracteres, no el título de la sección.

## Metadatos por trozo: fuente, sección y posición

Un trozo sin metadatos es texto sin procedencia. Guardar con cada trozo de dónde viene permite citar la fuente en la respuesta, filtrar la búsqueda («solo la política de devoluciones») y volver al documento original.

```python
def with_metadata(chunks_text, text, source="politica_devoluciones.md"):
    heads = [(m.start(), m.group(0).lstrip("# ").strip()) for m in re.finditer(r"(?m)^#{1,2} .+$", text)]
    out, cursor = [], 0
    for i, c in enumerate(chunks_text):
        pos = text.find(c[:60], max(0, cursor - 200))   # posición del trozo en el original
        pos = pos if pos >= 0 else cursor
        cursor = pos
        section = [h for s, h in heads if s <= pos][-1]
        out.append({"id": i, "source": source, "section": section, "offset": pos, "text": c})
    return out
```

Devuelve, para dos trozos del chunking recursivo:

```json
{"id": 9,  "source": "politica_devoluciones.md", "section": "5. Gastos de envío de la devolución", "offset": 4313, "text": "## 5. Gastos de envío de la devolución\n\nQuién paga el envío de vuelta ..."}
{"id": 10, "source": "politica_devoluciones.md", "section": "6. Reembolsos", "offset": 5049, "text": "## 6. Reembolsos\n\nEl reembolso se realiza por el mismo medio de pago q..."}
```

Con esos campos, la respuesta del asistente puede decir «según la sección 6 (Reembolsos) de la política de devoluciones» en lugar de afirmar algo sin respaldo, y quien audite una respuesta localiza el pasaje exacto por `offset`. Otros metadatos útiles: página, versión o fecha del documento (una política cambia), idioma y tipo de contenido.

## Trozos jerárquicos: padre-hijo y ventana de contexto

Hay una tensión entre **buscar** y **entender**: los trozos pequeños buscan mejor y los grandes se entienden mejor. El patrón padre-hijo resuelve las dos cosas: se indexan trozos pequeños (hijos) y, al recuperar uno, se entrega el trozo grande que lo contiene (padre), o sus vecinos.

```python
parents  = by_sections(text)        # 12 secciones: lo que se entrega al modelo
children = recursive(text, 300)     # 49 trozos de ~178 caracteres de media: lo que se indexa

best = search(children, query)      # se busca entre los hijos
parent = parent_of(best)            # se devuelve la sección que lo contiene
window = children[i - 1 : i + 2]    # o el hijo con su vecino anterior y siguiente
```

Con las 6 preguntas del experimento siguiente (recall@1: el primer resultado contiene la respuesta), sobre los mismos 49 hijos de unos 300 caracteres:

| Qué se entrega | Aciertos | Tamaño entregado |
|---|---|---|
| El hijo | 4/6 | 125-297 caracteres |
| El hijo con ±1 vecino | 5/6 | 449-753 caracteres |
| La sección padre | 5/6 | 660-1188 caracteres |

Entregar el contexto alrededor recuperó una pregunta más: el hijo había acertado el tema pero no traía la parte con el dato (reembolso por tarjeta). No arregla un hijo mal clasificado: en la pregunta sobre el límite de 80 € el primer hijo recuperado era un paso del procedimiento de devolución, y su padre tampoco traía la respuesta. Con 6 preguntas la diferencia es de una sola pregunta; no permite concluir más.

## Tablas, código y listas

Los separadores genéricos (caracteres, frases) no entienden estas estructuras y las rompen.

### Tablas

Cortar una tabla por tamaño separa las filas de su cabecera, y una fila suelta como `| Desistimiento | Tienda física | 0 € |` no dice qué columna es qué. Dos opciones: mantener la tabla entera si cabe, o un trozo por fila con la cabecera y el título repetidos en cada una.

```python
head = ["Motivo", "Método", "Coste para el cliente"]
chunk = "Gastos de envío de la devolución. " + "; ".join(f"{h}: {v}" for h, v in zip(head, row))
```

```text
❌ | Pedidos superiores a 80 € | Punto de recogida | 0 € |
✅ Gastos de envío de la devolución. Motivo: Pedidos superiores a 80 €; Método: Punto de recogida; Coste para el cliente: 0 €
```

Con los 6 trozos de fila, la pregunta «¿cuánto cuesta devolver en un punto de recogida un pedido de más de 80 €?» devuelve en primer lugar la fila correcta (similitud 0,540 frente a 0,427 de la siguiente).

### Código

Se corta por unidades sintácticas (función, clase, método), no por líneas. La librería estándar de Python ofrece `ast` para localizarlas:

```python
import ast
tree = ast.parse(src)
for node in tree.body:
    if isinstance(node, (ast.FunctionDef, ast.ClassDef)):
        segment = ast.get_source_segment(src, node)      # el código completo de la unidad
        print(type(node).__name__, node.name, node.lineno, node.end_lineno)
```

Para un módulo con una función y una clase con dos métodos, devuelve `FunctionDef total_con_iva` (líneas 3-5) y `ClassDef Reembolso` (7-13), y los métodos dentro de la clase (8-10 y 12-13). Para otros lenguajes se usa un analizador sintáctico propio de cada uno.

### Listas

Una lista sin su frase de introducción pierde el sujeto: «Estar sin usar... Conservar el embalaje original...» no dice que son las condiciones para aceptar una devolución. Se mantiene la lista junta con su encabezado y su frase de introducción, o se antepone la introducción a cada elemento.

## Medir el efecto en la recuperación

Para ver cómo cambia la recuperación con la estrategia hay un experimento mínimo: 6 preguntas sobre la política, un índice TF-IDF escrito a mano y recall@1 (el primer resultado contiene la información necesaria para contestar).

> **Los vectores TF-IDF no son embeddings de un modelo.** Miden coincidencia de palabras ponderada por su rareza, sin entender significado. Sirven para ver la mecánica de trocear, indexar y ordenar; no predicen cuánto recuperaría un modelo de embeddings real, algo que no se ha medido aquí.

```python
def build_index(chunks):
    docs = [Counter(tokenize(c)) for c in chunks]               # tokenize: minúsculas, sin tildes
    df = Counter(t for d in docs for t in d)
    idf = {t: math.log((len(chunks) + 1) / (df[t] + 1)) + 1 for t in df}
    return [{t: tf * idf[t] for t, tf in d.items()} for d in docs], idf

def search(vecs, idf, query, k=1):
    q = {t: tf * idf.get(t, 0.0) for t, tf in Counter(tokenize(query)).items()}
    return sorted(((cosine(q, v), i) for i, v in enumerate(vecs)), reverse=True)[:k]
```

Las preguntas y lo que debe contener el trozo para contar como acierto (todas las cadenas de un grupo; criterio literal, sin tolerancia):

| # | Pregunta | El trozo debe contener |
|---|---|---|
| 1 | ¿Cuántos días tengo para devolver unos auriculares? | «auriculares» y «14 días naturales» |
| 2 | ¿Cuánto tarda el reembolso en llegar a mi tarjeta? | «Tarjeta de crédito o débito» y «5 días hábiles» |
| 3 | ¿Se puede devolver ropa interior si ya he quitado el precinto? | «Ropa interior» y «precinto» |
| 4 | ¿Cuántos días tengo para devolver algo comprado en el Black Friday? | «Black Friday» y «45 días naturales» |
| 5 | ¿Cuánto cuesta devolver en un punto de recogida un pedido de más de 80 €? | la fila de la tabla o la frase «superó los 80 €, la devolución en punto de recogida es gratuita» |
| 6 | ¿Cuánto tiempo vale la etiqueta de devolución? | «7 días» y «etiqueta caduca» |

Resultados (salidas del 2026-11-10):

| Estrategia | Trozos | recall@1 | recall@3 | Caracteres del trozo recuperado (media) |
|---|---|---|---|---|
| Fijo 300 | 30 | 2/6 | 3/6 | 300 |
| Fijo 800 | 12 | 5/6 | 6/6 | 800 |
| Fijo 2000 | 5 | 5/6 | 6/6 | 2000 |
| Fijo 800 + solape 160 | 14 | 5/6 | 6/6 | 800 |
| Frases (hasta 800) | 12 | 5/6 | 5/6 | 695 |
| Secciones (`##`) | 12 | 6/6 | 6/6 | 984 |
| Recursivo 800 | 17 | 6/6 | 6/6 | 645 |
| Recursivo 800 + solape 160 | 17 | 6/6 | 6/6 | 698 |

Qué falló en cada caso:

- **Fijo 300:** las preguntas 1 y 4 recuperaron un trozo que termina en mitad de la respuesta («...plazo de 14 días» | «naturales desde la entrega»); con el criterio literal cuentan como fallo, aunque una persona habría dado por válido el dato. En las preguntas 2 y 3 la respuesta estaba partida o el trozo correcto quedó en 3.ª posición o no apareció entre los 3 primeros.
- **Fijo 800:** la pregunta 5 recuperó el trozo de introducción; el que traía la tabla quedó en 2.º lugar. Es un fallo de ordenación, no de corte.
- **Fijo 800 + solape 160:** la pregunta 3 falló, y el trozo correcto quedó en 2.º lugar. El solapamiento no mejoró nada medible en esta muestra.
- **Frases:** la pregunta 2 falló porque la etiqueta «Tarjeta de crédito o débito:» y su plazo quedaron en trozos distintos al separar por dos puntos; ningún trozo contiene ambas.

**Lectura con cautela.** Son 6 preguntas sobre un único documento y un recuperador léxico: una pregunta de diferencia es 1/6 (17 puntos). No permite concluir que por secciones o recursivo sea «mejor» en general, ni cuantificar el beneficio del solapamiento. Sí muestra algo cualitativo: los cortes que respetan la estructura no partieron ninguna respuesta y los trozos muy pequeños fallaron más. Un experimento serio necesita decenas o cientos de preguntas reales sobre varios documentos y el modelo de embeddings que se vaya a usar.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| El asistente responde «sí, dentro de 30 días» sin que el contexto diga de qué producto | Trozo huérfano: la respuesta se recuperó sin el título ni la frase que la contextualizan |
| Se recupera la lista de pasos pero no se sabe qué proceso describe | El encabezado quedó en otro trozo (en el chunking recursivo, «4. Cómo solicitar una devolución» se separó de sus siete pasos) |
| La respuesta afirma una regla que el texto cumple solo con condiciones | Un corte partió la condición: la regla quedó en un trozo y su excepción («ni siquiera en pedidos superiores a 80 €») en otro |
| Una fila de tabla recuperada es ininteligible | Se troceó la tabla como texto, y las filas quedaron sin cabecera |
| Los resultados traen cinco trozos casi idénticos | Solapamiento alto: los vecinos repiten el mismo contenido y llenan el top-k |
| Buenos resultados en pruebas, malos en producción | El tamaño se eligió a ojo, sin conjunto de preguntas con respuesta conocida para medirlo |
| Trozos finales de 47 caracteres | El último trozo del corte fijo es un resto sin contexto; se fusiona con el anterior |

Dos soluciones concretas al trozo huérfano. Si se antepone el título de sección al texto que se indexa (no al que se muestra), el recall@1 de «Fijo 800» pasó de 5/6 a 6/6 en el experimento (con 6 preguntas, una más; en «Fijo 300» se quedó en 2/6, y en «Recursivo 800» en 6/6, donde el título ya viajaba en el trozo). Y Anthropic describe, en su artículo sobre recuperación contextual (2024-09-19), anteponer a cada trozo una explicación breve generada por un modelo a partir del documento completo (unos 50 a 100 tokens): reporta una reducción del 35 % en fallos de recuperación del top-20 con embeddings contextuales y del 49 % combinándolos con BM25 contextual, sobre sus propios conjuntos de datos, no medidos aquí.

## Buenas prácticas avanzadas

- **Trocea por la estructura del documento y usa el tamaño solo como tope.** Los encabezados, párrafos y listas ya expresan unidades de significado; el recursivo con separadores jerárquicos las respeta. El corte por caracteres es el último recurso, para texto sin estructura.
- **Indexa el título, muestra el cuerpo.** Anteponer la ruta de encabezados («Política de devoluciones > 6. Reembolsos») al texto que se convierte en vector da a los trozos pequeños el contexto que les falta, sin ensuciar lo que se entrega al modelo.
- **Mide el solapamiento en volumen antes de añadirlo.** El aumento es aproximadamente `solape / (tamaño - solape)`: un 20 % cuesta +24 % de almacenamiento y embeddings. Úsalo como seguro contra cortes en texto sin estructura, no como sustituto de una buena estrategia de corte.
- **Trata cada tipo de contenido con su propio troceador.** Tablas por fila con cabecera, código por unidades sintácticas, listas con su introducción y prosa por párrafos. Un único separador para todo el corpus rompe lo que no es prosa.
- **Guarda `source`, `section` y `offset` desde el primer día.** Reconstruir de dónde salió un trozo después de indexar obliga a reindexar. Con la versión del documento, además, se puede invalidar y reindexar solo lo que cambió.
- **Construye un conjunto de preguntas con respuesta conocida y repite la medición al cambiar de estrategia o de tamaño.** Es la única manera de saber si un cambio mejora algo; 6 preguntas sirven para ver la mecánica, no para decidir.

## Documentación oficial

- [Introducing Contextual Retrieval (Anthropic)](https://www.anthropic.com/news/contextual-retrieval) — el efecto de anteponer contexto a cada trozo y de combinar embeddings con BM25 y reranking, con cifras sobre sus conjuntos de datos.
- [Embeddings (documentación de Claude)](https://docs.anthropic.com/en/docs/build-with-claude/embeddings) — guía de embeddings de la documentación de Claude; punto de partida para consultar los límites de entrada del modelo elegido (contenido no revisado en detalle aquí).
- [Text splitters (LangChain)](https://python.langchain.com/docs/concepts/text_splitters/) — catálogo de troceadores ya implementados (recursivo, por encabezados Markdown, por código) para comparar con las versiones escritas aquí.

---

*En resumen: trocear bien es cortar por el significado y no por la regla; cada trozo debe entenderse solo, llevar su procedencia y medirse con preguntas reales antes de fiarse de un tamaño.*
