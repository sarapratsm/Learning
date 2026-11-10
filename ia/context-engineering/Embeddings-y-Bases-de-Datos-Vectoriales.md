# Embeddings y Bases de Datos Vectoriales

## ¿Qué es?

Un *embedding* es un vector de longitud fija (cientos o miles de números decimales) que un modelo genera a partir de un texto y que codifica su significado: textos con significado parecido producen vectores cercanos. Una base de datos vectorial es un almacén que guarda esos vectores y, dado uno de consulta, devuelve los *k* más cercanos (los «vecinos más cercanos» o *nearest neighbors*).

## ¿Por qué existe?

Buscar con `LIKE '%devolver%'` falla en cuanto pregunta y documento usan palabras distintas: «¿puedo mandar de vuelta unas zapatillas?» no contiene ninguna palabra de «Política de devoluciones: 30 días desde la entrega», aunque hablen de lo mismo. El embedding mueve la comparación del texto al significado: ambas frases se convierten en vectores y se compara la distancia entre vectores.

Eso crea un segundo problema: comparar la consulta con cada vector guardado es un cálculo por documento, y con millones de documentos es demasiado lento. Las bases vectoriales (y las extensiones vectoriales de bases ya existentes) añaden índices que encuentran vecinos *casi* exactos en una fracción del tiempo.

> Si conoces los índices B-tree de SQL: un B-tree acelera «encuentra la fila con este valor exacto o en este rango». Un índice vectorial acelera «encuentra las filas cuyo vector está más cerca de este», una pregunta que `WHERE columna = valor` no sabe expresar.

## ¿Cuándo y para qué se usa?

En el asistente de soporte de una tienda online, la base de conocimiento reúne la política de devoluciones, las guías de tallas y las fichas de catálogo. Cuando una persona pregunta por el pedido #4711 y por cómo devolver unas zapatillas, el sistema convierte la pregunta en un vector, busca los fragmentos de documentación más cercanos y los pone en el contexto del modelo. Ese uso es la fase de recuperación de [RAG](RAG.md); los documentos largos se trocean antes de generar vectores, tema de [Chunking](Chunking.md).

Otros usos: recomendar productos parecidos al que un cliente ya vio, detectar tickets duplicados, agrupar reclamaciones por tema.

No aplica a datos que se consultan por valor exacto: el estado del pedido #4711 se obtiene con una consulta SQL por `id`, no con una búsqueda por parecido.

## Propiedades de un embedding

- **Dimensión fija.** Cada modelo emite siempre vectores de la misma longitud (por ejemplo 1024), sea la entrada una palabra o un párrafo.
- **Distancia ≈ parecido de significado.** Es una aproximación aprendida por el modelo: dos textos pueden salir cercanos por razones que una persona no consideraría relevantes.
- **No comparables entre modelos.** Cada modelo construye su propio espacio. Aunque dos modelos coincidan en dimensión, un vector de uno y un vector del otro no se pueden comparar: la distancia entre ellos no significa nada.
- **Un vector por texto de entrada**, con un límite de longitud de entrada que fija el modelo.

Los modelos reales no se pueden ejecutar aquí (no se llama a ninguna API de embeddings). Los vectores de los ejemplos siguientes son **vectores pequeños inventados a mano o aleatorios: no son embeddings de un modelo**; sirven para ver la mecánica de la comparación y del ranking.

## Medir la cercanía: coseno, producto escalar y distancia euclídea

Tres medidas habituales. Con vectores `a` y `b`:

- **Producto escalar**: `sum(a_i * b_i)`. Mayor = más parecidos.
- **Similitud coseno**: producto escalar dividido por el producto de las longitudes (normas). Mide solo el ángulo entre vectores; ignora su longitud. Va de -1 a 1.
- **Distancia euclídea**: la distancia en línea recta, `sqrt(sum((a_i - b_i)^2))`. Menor = más parecidos.

El script calcula las tres para una consulta y tres documentos de dos dimensiones, primero tal cual y después normalizados (cada vector dividido por su norma, de modo que mida 1):

```python
import math

def dot(a, b): return sum(x * y for x, y in zip(a, b))
def norm(a): return math.sqrt(dot(a, a))
def coseno(a, b): return dot(a, b) / (norm(a) * norm(b))
def euclidea(a, b): return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))
def normalizar(a): n = norm(a); return [x / n for x in a]

consulta = [3.0, 4.0]
docs = {"A": [6.0, 8.0], "B": [4.0, 3.0], "C": [-3.0, 4.0]}

def tabla(titulo, q, d):
    print(titulo)
    print("doc  coseno  escalar  euclidea")
    for n, v in d.items():
        print(f"{n}    {coseno(q, v):6.3f}  {dot(q, v):7.3f}  {euclidea(q, v):8.3f}")

tabla("Sin normalizar", consulta, docs)
qn = normalizar(consulta)
dn = {n: normalizar(v) for n, v in docs.items()}
print()
tabla("Normalizados a longitud 1", qn, dn)
q, a = qn, dn["B"]
print("\n||q-d||^2 =", round(euclidea(q, a) ** 2, 6), "  2-2*coseno =", round(2 - 2 * coseno(q, a), 6))
```

Salida (ejecutado el 2026-11-10, Python 3.12):

```text
Sin normalizar
doc  coseno  escalar  euclidea
A     1.000   50.000     5.000
B     0.960   24.000     1.414
C     0.280    7.000     6.000

Normalizados a longitud 1
doc  coseno  escalar  euclidea
A     1.000    1.000     0.000
B     0.960    0.960     0.283
C     0.280    0.280     1.200

||q-d||^2 = 0.08   2-2*coseno = 0.08
```

Qué se ve:

- **Sin normalizar, las tres medidas discrepan.** `A` apunta exactamente en la misma dirección que la consulta pero es el doble de largo: el coseno lo pone primero (1.000), el producto escalar también (50), pero la distancia euclídea lo aleja (5.000) y prefiere `B` (1.414), más corto.
- **Normalizados, las tres dan el mismo orden.** El coseno y el producto escalar valen lo mismo (la división por las normas ya está hecha) y la distancia euclídea cumple `distancia² = 2 − 2·coseno` (0.08 en ambos lados), por lo que ordena igual, al revés.

Regla práctica: con vectores normalizados da igual cuál se use, y el producto escalar es la más barata (no divide ni calcula raíces). Con vectores sin normalizar hay que elegir la medida que corresponda al modelo, normalmente el coseno. La documentación de Voyage AI declara que sus embeddings vienen normalizados a longitud 1 y que, por tanto, coseno y producto escalar son equivalentes y coseno y distancia euclídea dan el mismo ranking (fuente: [documentación de embeddings de Anthropic](https://platform.claude.com/docs/en/build-with-claude/embeddings), pregunta «Which similarity function should I use?», consultada el 2026-11-10). Otros modelos pueden no normalizar: se comprueba en su documentación o midiendo la norma de un vector.

## Búsqueda de vecinos más cercanos por fuerza bruta

La búsqueda exacta compara la consulta con todos los vectores y se queda con los *k* mejores. Es el punto de partida y la referencia para medir la calidad de cualquier índice aproximado.

```python
import heapq, math, random, time

def top_k(consulta, vectores, k=5):
    """Fuerza bruta exacta: producto escalar con cada vector y los k mayores."""
    puntuados = ((sum(q * x for q, x in zip(consulta, v)), i) for i, v in enumerate(vectores))
    return heapq.nlargest(k, puntuados)

def unitario(d):
    v = [random.gauss(0, 1) for _ in range(d)]
    n = math.sqrt(sum(x * x for x in v))
    return [x / n for x in v]

random.seed(42)
d = 64
for n in (1_000, 10_000, 100_000):
    base = [unitario(d) for _ in range(n)]
    q = unitario(d)
    t0 = time.perf_counter()
    res = top_k(q, base)
    ms = (time.perf_counter() - t0) * 1000
    print(f"n={n:>7} d={d}: {ms:8.1f} ms  ({n*d:,} multiplicaciones)")
```

`top_k` devuelve una lista de `k` tuplas `(puntuación, posición)` ordenada de mayor a menor. Los vectores son aleatorios y unitarios (no son embeddings de un modelo): lo que se mide es el coste del recorrido, no la calidad de la búsqueda.

Salida (medida el 2026-11-10, Python 3 estándar sin NumPy, un solo hilo; los milisegundos varían de una ejecución a otra):

```text
n=   1000 d=64:      5.1 ms  (64,000 multiplicaciones)
n=  10000 d=64:     49.7 ms  (640,000 multiplicaciones)
n= 100000 d=64:    496.5 ms  (6,400,000 multiplicaciones)
```

Cada consulta cuesta O(n·d): una multiplicación por dimensión y por vector. Multiplicar `n` por 10 multiplica el tiempo por 10. Una segunda medida con n = 10 000 y distinta `d` muestra también el crecimiento con la dimensión, aunque no exactamente lineal (27, 67 y 93 ms para d = 32, 64 y 128: el recorrido de la lista y la ordenación tienen un coste fijo por vector y el ruido de una sola medida pesa).

Extrapolación lineal, no medida: con 1 millón de vectores de 1536 dimensiones habría unas 1,5 · 10⁹ multiplicaciones por consulta, del orden de minutos en este Python puro. Las implementaciones reales usan instrucciones vectorizadas (NumPy, SIMD, GPU) y son órdenes de magnitud más rápidas, pero el crecimiento sigue siendo lineal con `n`.

Cuándo la fuerza bruta basta: unos miles a decenas de miles de vectores con unas pocas consultas por segundo. Para la base de conocimiento de una tienda pequeña (unos cientos de fragmentos) no hace falta ninguna base vectorial.

## Índices aproximados (ANN)

Cuando `n` crece, recorrer todo es inviable por latencia. Los índices de *approximate nearest neighbors* (ANN) renuncian a garantizar el resultado exacto: devuelven los vecinos «casi seguro» correctos mirando solo una fracción de los vectores. La calidad se mide con el **recall@k**: de los `k` vecinos reales (los que daría la fuerza bruta), qué fracción devuelve el índice. Los ajustes de cada índice cambian recall, latencia y memoria, nunca los tres a la vez.

| Índice | Idea | Qué se gana | Qué cuesta |
|---|---|---|---|
| **HNSW** (grafo jerárquico) | Cada vector se conecta con vecinos cercanos en capas de grafos; la búsqueda baja de capa en capa acercándose a la consulta. | Buen recall con poca latencia; no necesita entrenarse. | Memoria extra por las conexiones del grafo; construir el índice es lento. |
| **IVF** (lista invertida) | Agrupa los vectores en *clusters* con centroides; la consulta solo examina los clusters más cercanos (`nprobe`). | Construcción rápida y memoria moderada. | Necesita datos para entrenar los centroides; si el vecino real está en un cluster no visitado, se pierde. |
| **PQ** (*product quantization*) | Divide cada vector en trozos y sustituye cada trozo por el código del centroide más cercano. | Reduce muchísimo la memoria por vector y acelera las comparaciones. | Distancias aproximadas: baja el recall; se suele combinar con IVF y re-puntuar los mejores candidatos con el vector completo. |

Descripción conceptual; no se ha ejecutado ningún índice. Los parámetros concretos (nombre y valores por defecto) dependen de la implementación: el ejemplo de pgvector más abajo trae los suyos, leídos de su documentación.

El artículo que introdujo HNSW es [Malkov y Yashunin, 2016](https://arxiv.org/abs/1603.09320).

## Dónde guardar los vectores

| Opción | Cuándo encaja | Cuándo se queda corta |
|---|---|---|
| **Cálculo en memoria** (fuerza bruta, p. ej. con NumPy) | Prototipos y corpus de hasta unas decenas de miles de vectores. | Corpus que crecen, o que deben persistir y actualizarse de forma concurrente. |
| **pgvector** (extensión de PostgreSQL) | Ya usas PostgreSQL; quieres vectores junto a los datos relacionales (pedidos, productos) y filtrar con SQL normal; corpus de hasta millones de vectores. | Cargas de búsqueda vectorial muy grandes o de latencia extrema que justifican un sistema dedicado y escalable por separado. |
| **SQLite-vec** (extensión de SQLite) | Aplicaciones embebidas, locales o de escritorio con un fichero de base de datos. | Servicios con muchos clientes concurrentes. |
| **Elasticsearch/OpenSearch** | Ya tienes el motor para búsqueda de texto y quieres combinar texto y vectores (búsqueda híbrida) en el mismo sitio. | Si no tenías ya el motor, es mucha infraestructura solo para vectores. |
| **Base vectorial dedicada** (Qdrant, Weaviate, Milvus, Pinecone...) | Corpus muy grandes, necesidad de escalar la búsqueda vectorial de forma independiente, funciones específicas (filtrado avanzado, multi-tenant). | Añade un sistema más que operar y mantener sincronizado con la base de datos principal. |

La tabla es una guía de decisión, no una comparativa medida: las capacidades de cada producto cambian y se verifican en su documentación antes de decidir.

**Cuándo basta pgvector.** Si ya hay una base PostgreSQL (ver [PostgreSQL](../../bases-de-datos/postgresql/PostgreSQL.md)), pgvector evita sincronizar dos sistemas: el vector vive en la misma fila que el texto y que el `id` del pedido o del producto, y se borra, actualiza y respalda con las mismas transacciones y copias de seguridad que el resto.

### pgvector: el SQL

Lo siguiente es SQL **leído de la documentación de pgvector** (`github.com/pgvector/pgvector`, consultada el 2026-11-10); no se ha ejecutado aquí. Crear la extensión, una tabla con una columna de 3 dimensiones y una consulta:

```sql
CREATE EXTENSION vector;  -- una vez por base de datos

CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));
INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');

SELECT * FROM items ORDER BY embedding <-> '[3,1,2]' LIMIT 5;
```

La consulta devuelve las 5 filas más cercanas. La dimensión de la columna (`vector(3)`) debe coincidir con la del modelo de embeddings (con un modelo de 1024 dimensiones, `vector(1024)`). Operadores de distancia:

| Operador | Medida | Clase de operador del índice |
|---|---|---|
| `<->` | Distancia euclídea (L2) | `vector_l2_ops` |
| `<#>` | Producto escalar **negativo** (se multiplica por -1 para el valor real) | `vector_ip_ops` |
| `<=>` | Distancia coseno | `vector_cosine_ops` |

Como el operador devuelve una *distancia* (menor = más cercano) se ordena de forma ascendente; la similitud coseno es `1 - (embedding <=> consulta)`. Según la documentación, un índice solo se usa cuando la consulta tiene `ORDER BY <operador de distancia>` ascendente con `LIMIT`. El operador y la clase del índice deben corresponder: un índice `vector_cosine_ops` no acelera una consulta con `<->`.

Índices (parámetros y valores por defecto según la documentación):

```sql
-- HNSW: m = 16 y ef_construction = 64 por defecto
CREATE INDEX ON items USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);
SET hnsw.ef_search = 100;   -- por defecto 40; más alto = más recall, más latencia

-- IVFFlat: se crea con datos ya cargados
CREATE INDEX ON items USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
SET ivfflat.probes = 10;    -- por defecto 1
```

`m` (conexiones por capa) y `ef_construction` controlan la calidad del grafo HNSW y su coste de construcción; `ef_search` controla cuánto se explora en cada consulta. En IVFFlat, `lists` es el número de clusters y `probes` cuántos se visitan por consulta; la documentación sugiere partir de `filas / 1000` para `lists` hasta 1 millón de filas. Son los parámetros de recall-latencia de la sección anterior con nombres propios. Límites de dimensión indexable, según la misma documentación: `vector` hasta 2000, `halfvec` (media precisión) hasta 4000.

### Filtros por metadatos

Casi nunca se busca en todo el corpus: «solo documentos del idioma del cliente», «solo del catálogo vigente», «solo de este cliente». Con pgvector el filtro es un `WHERE` normal:

```sql
SELECT id FROM fragmentos
WHERE idioma = 'es' AND vigente
ORDER BY embedding <=> $1
LIMIT 5;
```

Ojo con el orden de ejecución: la documentación de pgvector indica que los índices aproximados aplican el `WHERE` **después** del recorrido del índice, por lo que una consulta filtrada puede devolver menos de `k` filas (su ejemplo: si el filtro deja pasar el 10 % de las filas y `hnsw.ef_search` es 40, salen unas 4 de media). Opciones de la documentación: activar el escaneo iterativo (`SET hnsw.iterative_scan = strict_order;` o `relaxed_order`), crear un índice parcial para valores de filtro muy concretos, o un índice B-tree sobre la columna filtrada cuando el filtro deja pocas filas. Otros motores resuelven el filtrado de otras maneras (antes, durante o después de la búsqueda): se consulta su documentación y se mide con los filtros reales.

## Dimensión y coste de almacenamiento

Cada vector guarda `d` números; en el formato habitual (32 bits = 4 bytes por número):

```
1 000 000 vectores × 1536 dimensiones × 4 bytes = 6 144 000 000 bytes ≈ 6,1 GB (5,7 GiB)
```

Ese cálculo cubre solo los vectores crudos. Un índice HNSW suma además las conexiones del grafo, y el texto y los metadatos van aparte. Lo que importa para dimensionar:

- **El tamaño crece linealmente con `n` y con `d`.** Pasar de 1536 a 256 dimensiones divide por 6 el espacio y el tiempo de comparación.
- **Muchos modelos ofrecen varias dimensiones.** Los modelos Voyage 4 aceptan `output_dimension` de 256, 512, 1024 (por defecto) y 2048 (documentación de Voyage AI vía Anthropic, 2026-11-10). La documentación señala que son embeddings tipo *Matryoshka* (información de lo grueso a lo fino dentro del mismo vector), por lo que se pueden truncar a las primeras dimensiones **y volver a normalizar**.
- **Menos dimensiones suele costar calidad de recuperación.** Cuánta, depende del modelo y de los datos: no está medido aquí. Se mide con un conjunto de preguntas propias antes de recortar.

### Cuantización

Cuantizar es guardar cada número con menos bits. La misma documentación de Voyage AI lista las opciones: `float` (32 bits, la mayor precisión), `int8`/`uint8` (8 bits, reducción de 4 veces en almacenamiento) y `binary`/`ubinary` (1 bit por dimensión empaquetado, 32 veces menos). Aplicado al cálculo anterior, sin sumar índice:

| Formato | Bytes por vector de 1536 dim. | 1 millón de vectores |
|---|---|---|
| `float` (32 bits) | 6144 | ≈ 5,7 GiB |
| media precisión (16 bits, p. ej. `halfvec` de pgvector) | 3072 | ≈ 2,9 GiB |
| `int8` | 1536 | ≈ 1,4 GiB |
| binario (1 bit) | 192 | ≈ 0,17 GiB |

El coste es una pérdida de precisión en las distancias, que puede restar recall; no se ha medido aquí. Un patrón habitual es buscar con los vectores comprimidos y *re-puntuar* los mejores candidatos con los de precisión completa. Para PQ (comentado en el apartado de índices) la idea es la misma con otro mecanismo.

## Elegir un modelo de embeddings

Anthropic no ofrece un modelo de embeddings propio: su documentación remite a Voyage AI (documentación de Anthropic, 2026-11-10). Eso no impide usar otro proveedor. Qué mirar en cualquier modelo, con ejemplos de la tabla de modelos Voyage vigente en esa documentación:

| Criterio | Qué comprobar | Ejemplo (documentación de Voyage, 2026-11-10) |
|---|---|---|
| **Idioma** | Si es multilingüe o está afinado para un idioma. La tienda atiende en español: se prueba con preguntas reales en español. | `voyage-4`, `voyage-4-large` y `voyage-4-lite` se describen como de uso general y multilingüe. |
| **Dominio** | Hay modelos especializados (código, finanzas, legal). | `voyage-code-4` (código), `voyage-finance-2`, `voyage-law-2`. |
| **Dimensión** | Define el coste de almacenamiento y si el índice la admite (pgvector indexa `vector` hasta 2000). | 1024 por defecto; 256, 512 y 2048 opcionales. |
| **Longitud máxima de entrada** | Los fragmentos deben caber; lo que excede se trunca o da error, según el proveedor. | 32 000 tokens en los modelos de la familia 4. |
| **Coste y latencia** | Se paga por token procesado, y cada consulta de usuario también genera un embedding. | La familia ofrece `-large` (calidad), estándar (equilibrio) y `-lite` (latencia y coste). |

El precio no se copia aquí: la documentación de Anthropic remite a la página de precios de Voyage ([Model pricing](https://www.mongodb.com/docs/voyageai/management/billing/#model-pricing)), que es la vigente.

Los nombres y características de los modelos cambian con frecuencia; se contrastan con la página oficial el día de decidir. La decisión se valida con una evaluación propia: 30-50 preguntas reales de clientes, con el fragmento que debería salir, midiendo cuántas veces aparece entre los primeros `k` resultados con cada candidato. Las tablas de resultados públicas miden otros datos y otros idiomas.

### Consulta y documento

Para recuperación, algunos modelos tratan distinto la consulta (corta, una pregunta) y el documento (largo, la respuesta). En Voyage se indica con `input_type`, y la documentación pide no omitirlo en tareas de recuperación: con `input_type="query"` antepone al texto la instrucción «Represent the query for retrieving supporting documents: » y con `"document"`, «Represent the document for retrieval: ». Esquema, sin ejecutar (requiere clave de API):

```python
import voyageai

vo = voyageai.Client()   # lee VOYAGE_API_KEY del entorno

docs = ["Política de devoluciones: 30 días desde la entrega...", "Guía de tallas de calzado..."]
vectores_docs = vo.embed(docs, model="voyage-4", input_type="document").embeddings

vector_consulta = vo.embed(["¿puedo devolver unas zapatillas?"], model="voyage-4",
                           input_type="query").embeddings[0]
```

Ambas llamadas usan el **mismo modelo**; solo cambia `input_type`. Cada elemento de `.embeddings` es una lista de 1024 decimales con la configuración por defecto.

## Reindexar al cambiar de modelo

Como los espacios de dos modelos no son comparables, cambiar de modelo (o de dimensión, o de variante del mismo modelo) obliga a regenerar **todos** los vectores del corpus; no vale mezclar vectores viejos y nuevos en el mismo índice. Un procedimiento que evita cortes:

1. Guardar el nombre del modelo y la dimensión junto a cada vector (una columna `modelo`) o usar una tabla/índice por modelo.
2. Crear la tabla nueva y rellenarla con el modelo nuevo mientras la antigua sigue sirviendo.
3. Comparar ambos sobre el mismo conjunto de preguntas de evaluación.
4. Cambiar el tráfico a la tabla nueva y borrar la antigua cuando se confirme.

El coste es proporcional al número total de tokens del corpus, más el tiempo de construir el índice. Planificarlo desde el principio es más barato que descubrirlo con un millón de fragmentos ya indexados. El mismo mecanismo (un identificador de versión) sirve cuando cambia la forma de trocear los documentos.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| Los resultados parecen aleatorios tras «actualizar el modelo». | Los documentos se indexaron con un modelo y las consultas se embeben con otro. Los espacios no son comparables aunque coincida la dimensión. |
| Error de dimensiones distintas al insertar o consultar (pgvector; texto exacto no verificado aquí). | La columna `vector(1536)` recibe vectores de un modelo de 1024 dimensiones, o al revés. |
| El ranking cambia al pasar de producto escalar a coseno (o a distancia euclídea). | Los vectores no están normalizados, y las tres medidas solo coinciden con vectores de longitud 1 (la tabla de arriba). Se normaliza al insertar o se usa la medida que el modelo documenta. |
| Truncar un vector a menos dimensiones empeora el ranking de forma inesperada. | Tras truncar un vector Matryoshka hay que volver a normalizarlo (lo indica la documentación de Voyage). |
| La búsqueda ignora un código de producto exacto («ZP-4471»). | Los embeddings capturan significado, no coincidencia literal de códigos o nombres propios. Se combina con búsqueda por texto (búsqueda híbrida). |
| Las consultas con filtro devuelven menos de `k` resultados. | El índice aproximado aplica el `WHERE` después de recorrer el índice (documentación de pgvector); se usa escaneo iterativo, un índice parcial o más exploración. |
| El `ORDER BY embedding <=> ...` no usa el índice. | El índice se creó con otra clase de operador (`vector_l2_ops` con una consulta coseno), falta `LIMIT`, o la ordenación no es ascendente. |
| La recuperación es mediocre con documentos largos. | El vector de un texto largo mezcla temas. Se trocea antes de generar vectores ([Chunking](Chunking.md)). |
| Peor recuperación cuando consulta y documento se embeben igual. | Con modelos que distinguen ambos tipos de entrada se omitió `input_type` o se usó el mismo en los dos lados (Voyage recomienda no omitirlo en recuperación). |

## Buenas prácticas avanzadas

- **Guarda el modelo y la dimensión con cada vector.** Sin esa columna, el día que se cambie de modelo nadie sabrá qué filas están en qué espacio, y la migración pasa a ser «regenerar todo y esperar que cuadre».
- **Mide el recall del índice contra la fuerza bruta.** Con una muestra de consultas, compara los `k` vecinos del índice con los `k` exactos del `top_k` de arriba y ajusta `ef_search` / `probes` hasta el recall que necesites. Los valores por defecto no se ajustan a tus datos.
- **Normaliza una vez al insertar.** Con vectores de longitud 1 se puede usar siempre el producto escalar (la medida más barata) y desaparece una clase entera de errores de medida distinta entre índice y consulta.
- **Combina búsqueda vectorial y búsqueda por texto, y reordena.** El vector falla con identificadores exactos y el texto falla con paráfrasis; las dos listas se fusionan y, si hace falta más precisión, un *reranker* reordena los mejores candidatos. Voyage ofrece modelos de reranking en la misma documentación.
- **Dimensiona con el cálculo antes de elegir sistema.** `n × d × bytes` más el índice decide si cabe en la RAM de la base actual; si no, quizá baste reducir dimensiones o cuantizar antes de añadir infraestructura.
- **Prueba los filtros con los porcentajes reales.** Una consulta filtrada que va bien con el filtro al 50 % puede devolver casi nada con el filtro al 1 %; se prueba con la selectividad real de cada filtro.

## Documentación oficial

- [Embeddings (Anthropic)](https://platform.claude.com/docs/en/build-with-claude/embeddings) — Anthropic no tiene modelo propio y remite a Voyage AI; incluye la lista vigente de modelos con dimensiones y longitud de contexto, `input_type`, cuantización y truncado Matryoshka. Se consulta primero para elegir modelo.
- [Modelos de Voyage AI](https://www.mongodb.com/docs/voyageai/models/) — comparativa oficial de modelos y de reranking, y enlace a precios.
- [pgvector](https://github.com/pgvector/pgvector) — operadores, índices HNSW e IVFFlat, tipos `halfvec` y `bit`, filtrado y escaneo iterativo.

## Recursos didácticos

- [Vector similarity (Pinecone)](https://www.pinecone.io/learn/vector-similarity/) — explicación con diagramas de producto escalar, coseno y distancia euclídea; es el artículo que enlaza la documentación de Voyage para este tema.
- [sqlite-vec](https://github.com/asg017/sqlite-vec) — extensión de SQLite para búsqueda vectorial, útil para probar la idea sin montar un servidor.

---

*En resumen: un embedding convierte el significado de un texto en un vector de longitud fija comparable por distancia, la búsqueda exacta cuesta O(n·d) y un índice aproximado cambia un poco de recall por mucha latencia; con un solo modelo para indexar y consultar, vectores normalizados y pgvector si ya hay PostgreSQL, suele bastar.*
