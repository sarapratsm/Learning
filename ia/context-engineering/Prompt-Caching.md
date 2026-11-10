# Prompt Caching

## ¿Qué es?

El prompt caching (caché de prompt) permite que el proveedor del modelo reutilice el procesamiento ya hecho sobre el comienzo de una petición cuando esa misma porción vuelve a llegar en una llamada posterior. La parte reutilizada se factura a una fracción del precio de entrada normal.

## ¿Por qué existe?

Un LLM no recuerda nada entre llamadas: en cada petición hay que reenviar todo el contexto (herramientas, instrucciones, documentos, historial) y el modelo lo procesa entero. En un asistente de soporte de una tienda online, las instrucciones, la política de devoluciones y la descripción de las herramientas pesan miles de tokens y son idénticas en la pregunta por el pedido #4711 y en la pregunta siguiente. Sin caché se paga por procesarlas una y otra vez.

> Si ya conoces la caché de consultas de una base de datos o la caché de un CDN, la idea es parecida, con una diferencia: la clave de la entrada es el **prefijo completo** de la petición, no un identificador que eliges tú. Es como un CDN cuya clave fuera «todos los bytes enviados hasta aquí»: un solo byte distinto al principio y la clave es otra.

## ¿Cuándo y para qué se usa?

- Asistentes con un bloque de instrucciones y documentos de referencia grande y estable, repetido en cada turno.
- Conversaciones largas donde el historial se reenvía completo en cada turno (el coste de entrada crece con cada turno; véase [Coste, latencia y fiabilidad](../ingenieria-con-llms/Coste-Latencia-y-Fiabilidad.md)).
- Agentes con muchas definiciones de herramientas, que forman un prefijo pesado e idéntico en cada iteración.
- Lotes de peticiones que comparten un mismo documento o un mismo conjunto de instrucciones.

No reduce el coste ni el tiempo de la salida: la caché afecta solo a la entrada.

## Cómo funciona: coincidencia de prefijo

Los datos proceden de la documentación oficial de Anthropic, [Prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) (leída el 2026-11-10), salvo indicación contraria.

La petición se construye en este orden: **`tools` → `system` → `messages`**. La caché guarda el procesamiento de un prefijo de esa secuencia, hasta el bloque donde se coloca un **punto de corte** (*cache breakpoint*, el marcador `cache_control`). Para que haya acierto (*cache hit*) el prefijo debe ser idéntico: según la documentación, los aciertos requieren «100 percent identical prompt segments», incluidos todo el texto y las imágenes hasta el bloque marcado.

Consecuencia: **un cambio en cualquier nivel invalida ese nivel y todos los posteriores**.

```text
Llamada 1: [tools A][system B][política C][pregunta 1]   -> escribe en caché hasta C
Llamada 2: [tools A][system B][política C][pregunta 2]   -> lee la caché hasta C; procesa la pregunta 2
Llamada 3: [tools A][system B'][política C][pregunta 3]  -> cambió B: no hay acierto desde B en adelante
```

La documentación indica que los cambios en un nivel invalidan ese nivel y los siguientes. Algunos casos, tomados de su tabla de invalidación:

| Qué cambia | Caché de tools | Caché de system | Caché de messages |
|---|---|---|---|
| Definiciones de herramientas (nombres, descripciones, parámetros) | se invalida | se invalida | se invalida |
| Activar o desactivar búsqueda web o citas | se mantiene | se invalida | se invalida |
| `tool_choice` | se mantiene | se mantiene | se invalida |
| Añadir o quitar imágenes en cualquier punto | se mantiene | se mantiene | se invalida |
| Parámetros de razonamiento (`thinking`: modo o `budget_tokens`) | según modelo | según modelo | se invalida |

Dos reglas más de la misma página:

- **Ventana de búsqueda de 20 posiciones.** Para cada punto de corte, el sistema comprueba como máximo 20 posiciones hacia atrás buscando una entrada previa. Si una conversación crece 20 o más bloques desde la última escritura, esa entrada queda fuera de la ventana. Las escrituras solo ocurren en el punto de corte marcado.
- **Concurrencia.** Una entrada solo está disponible cuando empieza la primera respuesta. Si se lanzan peticiones en paralelo con el mismo prefijo, ninguna se beneficia hasta que la primera responde.

## Cómo marcar el prefijo

La documentación ofrece dos formas de activar la caché:

| Forma | Cómo | Cuándo |
|---|---|---|
| **Automática** | Un único `cache_control` en el nivel superior de la petición. El sistema coloca el punto de corte en el último bloque cacheable y lo desplaza al crecer la conversación. | Caso general, sobre todo conversaciones que crecen. |
| **Explícita** | `cache_control` dentro de bloques concretos (herramientas, bloques de `system`, mensajes). | Cuando se quiere controlar qué se cachea y repartir el prompt en partes con distinta frecuencia de cambio. |

Se pueden definir **hasta 4 puntos de corte**; la caché automática consume uno de esos 4 cuando se combina con puntos explícitos (si ya hay 4 explícitos, la API devuelve 400). La documentación añade que en la mayoría de los casos basta un único punto de corte al final del contenido estable, colocado en el último bloque idéntico entre peticiones.

### Ejemplo de petición (caché automática)

Estructura tomada del ejemplo de la documentación (cURL, caché automática), con el contenido adaptado al asistente de soporte. **No ejecutado** (no se llama a ninguna API).

```json
{
  "model": "claude-opus-5-5",
  "max_tokens": 1024,
  "cache_control": {"type": "ephemeral"},
  "system": "Eres el asistente de soporte de la tienda. Política de devoluciones: ...(texto largo y estable)...",
  "messages": [
    {"role": "user", "content": "¿Dónde está mi pedido #4711?"}
  ]
}
```

Cabeceras que usa el ejemplo de la documentación: `content-type: application/json`, `x-api-key` y `anthropic-version: 2026-10-21` (el valor de `anthropic-version` es el que figura en la documentación consultada).

### Ejemplo con el SDK de Python

Misma estructura que el ejemplo del SDK de la documentación, con contenido adaptado. **No ejecutado.**

```python
import anthropic

client = anthropic.Anthropic()

response = client.messages.create(
    model="claude-opus-5-5",
    max_tokens=1024,
    cache_control={"type": "ephemeral"},   # activa la caché automática
    system="Eres el asistente de soporte de la tienda. Política de devoluciones: ...(texto largo y estable)...",
    messages=[
        {"role": "user", "content": "¿Dónde está mi pedido #4711?"},
    ],
)
print(response.usage.model_dump_json())
```

Qué hace: el sistema marca el último bloque cacheable como punto de corte. La primera llamada escribe la entrada en caché y las siguientes con el mismo prefijo la leen. Qué devuelve: la respuesta normal, más el objeto `usage` con los contadores de caché (siguiente sección).

### Duración: 5 minutos o 1 hora

- Por defecto, la entrada dura **5 minutos** (`{"type": "ephemeral"}`). La duración se cuenta desde el **inicio de la petición** que escribe o lee la entrada, y se renueva sin coste cada vez que se usa.
- Con `"ttl": "1h"` dentro de `cache_control`, dura **1 hora**: `{"type": "ephemeral", "ttl": "1h"}`.
- Si se mezclan duraciones, las entradas de 1 hora deben aparecer antes que las de 5 minutos.

## Cómo comprobar que funciona

La respuesta incluye en `usage` estos campos:

| Campo | Qué cuenta |
|---|---|
| `cache_creation_input_tokens` | Tokens escritos en caché en esta llamada. |
| `cache_read_input_tokens` | Tokens leídos de caché en esta llamada. |
| `input_tokens` | Tokens **posteriores al último punto de corte**, procesados a precio normal. |
| `cache_creation` | Desglose de la escritura: `ephemeral_5m_input_tokens` y `ephemeral_1h_input_tokens`. |
| `output_tokens` | Tokens de salida (la caché no los afecta). |

El tamaño total de la entrada es la suma de tres campos:

```text
total_input_tokens = cache_read_input_tokens + cache_creation_input_tokens + input_tokens
```

Lectura típica de dos llamadas consecutivas con el mismo prefijo (valores ilustrativos, no medidos):

```text
Llamada 1: cache_creation_input_tokens=6000  cache_read_input_tokens=0     input_tokens=20
Llamada 2: cache_creation_input_tokens=0     cache_read_input_tokens=6000  input_tokens=25
```

Si en **ambos** campos de caché el valor es 0, el prompt no se cacheó. Un `input_tokens` pequeño no significa que el prompt sea pequeño: la parte cacheada no aparece ahí.

## El orden del prompt: lo estable primero, lo variable al final

Como la coincidencia es por prefijo, cualquier dato que cambie en cada llamada debe ir **después** de todo lo estable. Un dato variable colocado delante invalida todo lo que le sigue.

El script siguiente simula el matching de prefijo sobre las piezas del asistente de soporte (herramientas, rol, política de devoluciones, catálogo, hora, pregunta). No es la caché real: compara dos peticiones consecutivas pieza a pieza y cuenta cuántas piezas iniciales coinciden. Los tokens se aproximan como caracteres/4.

```python
import json

HERRAMIENTAS = [
    {"name": "consultar_pedido", "description": "Estado de un pedido por id"},
    {"name": "buscar_catalogo", "description": "Busca productos por texto"},
]
SISTEMA = "Eres el asistente de soporte de la tienda. Responde con precisión y brevedad."
POLITICA = "Devoluciones: 30 días desde la entrega, producto sin usar. " * 40
CATALOGO = "Catálogo: auriculares, teclados, ratones, monitores. " * 40

def piezas_mal(ahora, pregunta):
    # ❌ timestamp al principio del system
    return [("tools", json.dumps(HERRAMIENTAS)),
            ("system:hora", f"Fecha y hora actual: {ahora}"),
            ("system:rol", SISTEMA), ("system:politica", POLITICA),
            ("system:catalogo", CATALOGO), ("messages:pregunta", pregunta)]

def piezas_bien(ahora, pregunta):
    # ✅ lo estable primero; lo variable al final
    return [("tools", json.dumps(HERRAMIENTAS)),
            ("system:rol", SISTEMA), ("system:politica", POLITICA),
            ("system:catalogo", CATALOGO),
            ("messages:hora", f"Fecha y hora actual: {ahora}"),
            ("messages:pregunta", pregunta)]

def prefijo_comun(a, b):
    n = 0
    for x, y in zip(a, b):
        if x != y:
            break
        n += 1
    return n

def tokens(texto):  # aproximación: caracteres / 4 (no es un tokenizador real)
    return len(texto) // 4

def informe(nombre, fabrica):
    p1 = fabrica("2026-11-10 09:00:01", "¿Dónde está el pedido #4711?")
    p2 = fabrica("2026-11-10 09:00:47", "¿Puedo devolver unos auriculares?")
    n = prefijo_comun(p1, p2)
    reutil = sum(tokens(t) for _, t in p1[:n])
    total = sum(tokens(t) for _, t in p2)
    print(f"{nombre}: piezas reutilizables={n}/{len(p2)}  se rompe en='{p2[n][0]}'  "
          f"tokens reutilizables≈{reutil} de ≈{total}")

informe("❌ timestamp al principio", piezas_mal)
informe("✅ timestamp al final    ", piezas_bien)
```

Salida (ejecutado con Python 3.12, 2026-11-10):

```text
❌ timestamp al principio: piezas reutilizables=1/6  se rompe en='system:hora'  tokens reutilizables≈37 de ≈1194
✅ timestamp al final    : piezas reutilizables=4/6  se rompe en='messages:hora'  tokens reutilizables≈1176 de ≈1194
```

Con la hora delante, solo se salvan las herramientas (≈37 tokens); la política y el catálogo, que son el grueso, se reprocesan en cada llamada. Con la hora al final, el prefijo reutilizable es casi todo el prompt. La mecánica es la misma con un identificador de sesión, un nombre de usuario o cualquier valor que cambie por llamada.

## Cuánto se ahorra

Tarifas de la tabla de precios de la documentación citada (por millón de tokens, leídas el 2026-11-10): escribir en caché cuesta **1,25×** el precio de entrada con duración de 5 minutos y **2×** con duración de 1 hora; leer cuesta **0,1×** con carácter general. La propia página lista excepciones: por ejemplo, 0,05× para Opus 5.5 y Sonnet 5.5. El script usa los precios de la tabla para cada modelo, y calcula solo el prefijo (6.000 tokens; sin salida ni parte variable).

| Modelo | Entrada base | Escritura 5 min | Escritura 1 h | Lectura |
|---|---|---|---|---|
| Sonnet 5.5 | 2,00 $ | 2,50 $ | 4,00 $ | 0,10 $ |
| Opus 5 | 5,00 $ | 6,25 $ | 10,00 $ | 0,50 $ |
| Haiku 4.5 | 1,00 $ | 1,25 $ | 2,00 $ | 0,10 $ |

```python
TARIFAS = {  # entrada base, escritura 5m, escritura 1h, lectura ($ por millón de tokens)
    "Sonnet 5.5": (2.00, 2.50, 4.00, 0.10),
    "Opus 5":     (5.00, 6.25, 10.00, 0.50),
    "Haiku 4.5":  (1.00, 1.25, 2.00, 0.10),
}
def sin_cache(n, x, base):
    return n * x * base / 1e6
def con_cache(n, x, base, escritura, lectura):
    return (x * escritura + (n - 1) * x * lectura) / 1e6   # 1 escritura + (n-1) lecturas

X = 6000  # prefijo estable del asistente de soporte (tokens)
for modelo, (b, w5, w1, r) in TARIFAS.items():
    for n in (1, 2, 3, 10, 100):
        s, c5, c1 = sin_cache(n, X, b), con_cache(n, X, b, w5, r), con_cache(n, X, b, w1, r)
        print(f"{modelo:<11}{n:>5}{s:>13.5f}{c5:>12.5f}{c1:>12.5f}{(1 - c5 / s) * 100:>10.1f}%")

for modelo, (b, w5, w1, r) in TARIFAS.items():
    for etiqueta, w in (("5m", w5), ("1h", w1)):
        n = 1
        while con_cache(n, X, b, w, r) > sin_cache(n, X, b):
            n += 1
        print(f"  {modelo:<11}{etiqueta}: {n} llamadas = 1 escritura + {n - 1} lectura(s)")
```

Salida (ejecutado con Python 3.12, 2026-11-10; el script completo incluye cabeceras de tabla):

```text
modelo         N  sin caché $  caché 5m $  caché 1h $  ahorro 5m
Sonnet 5.5     1      0.01200     0.01500     0.02400     -25.0%
Sonnet 5.5     2      0.02400     0.01560     0.02460      35.0%
Sonnet 5.5     3      0.03600     0.01620     0.02520      55.0%
Sonnet 5.5    10      0.12000     0.02040     0.02940      83.0%
Sonnet 5.5   100      1.20000     0.07440     0.08340      93.8%
Opus 5         1      0.03000     0.03750     0.06000     -25.0%
Opus 5         2      0.06000     0.04050     0.06300      32.5%
Opus 5         3      0.09000     0.04350     0.06600      51.7%
Opus 5        10      0.30000     0.06450     0.08700      78.5%
Opus 5       100      3.00000     0.33450     0.35700      88.8%
Haiku 4.5      1      0.00600     0.00750     0.01200     -25.0%
Haiku 4.5      2      0.01200     0.00810     0.01260      32.5%
Haiku 4.5      3      0.01800     0.00870     0.01320      51.7%
Haiku 4.5     10      0.06000     0.01290     0.01740      78.5%
Haiku 4.5    100      0.60000     0.06690     0.07140      88.8%

Punto de equilibrio (menor N con coste con caché <= sin caché):
  Sonnet 5.5 5m: 2 llamadas = 1 escritura + 1 lectura(s)
  Sonnet 5.5 1h: 3 llamadas = 1 escritura + 2 lectura(s)
  Opus 5     5m: 2 llamadas = 1 escritura + 1 lectura(s)
  Opus 5     1h: 3 llamadas = 1 escritura + 2 lectura(s)
  Haiku 4.5  5m: 2 llamadas = 1 escritura + 1 lectura(s)
  Haiku 4.5  1h: 3 llamadas = 1 escritura + 2 lectura(s)
```

Cómo leerlo:

- **Una sola llamada sale más cara** (−25 % con escritura de 5 minutos): la escritura cuesta más que procesar sin caché y no hay lecturas que lo compensen.
- **El punto de equilibrio es la 2.ª llamada con 5 minutos y la 3.ª con 1 hora**, siempre que cada lectura caiga dentro del tiempo de vida de la entrada. Con escritura de 5 min, 1 lectura basta; con 1 h, hacen falta 2.
- El ahorro tiende al 90 % cuando el número de lecturas crece (el límite teórico con lectura a 0,1×). El cálculo supone que todas las llamadas del periodo aciertan; con tráfico real, cada vencimiento de la entrada obliga a una nueva escritura.
- La **salida** y la parte variable del prompt se facturan igual con y sin caché y no están en la tabla. El ahorro sobre la factura total es menor que el de la tabla.

## Cuándo NO compensa

| Situación | Por qué |
|---|---|
| Prefijo por debajo del mínimo cacheable | No se cachea y **no se devuelve error** (ver «Errores frecuentes»). |
| Una llamada o muy pocas con el mismo prefijo | La escritura (1,25× o 2×) no se amortiza: una sola llamada cuesta un 25 % más con duración de 5 minutos. |
| Tráfico esporádico: el hueco entre llamadas supera la duración | La entrada vence (5 minutos, o 1 hora si se pidió) y cada llamada vuelve a pagar escritura. Con la caché de 5 minutos, una consulta cada 10 minutos paga siempre la escritura y no obtiene lecturas. |
| El prefijo cambia en cada llamada (datos por usuario al principio) | No hay prefijo común que reutilizar. |
| Latencia o coste dominados por la salida | La caché no afecta a la generación. |

Mínimos de tokens cacheables, según la documentación consultada: **512** en Opus 5.5, Opus 5, Sonnet 5.5, Fable 5.x, Mythos 5.x y Haiku 5.5; **1.024** en Sonnet 5, Sonnet 4.6 y 4.5 y Opus 4.8; **2.048** en Opus 4.7; **4.096** en Opus 4.6, Opus 4.5 y Haiku 4.5. La tabla de la página cubre más modelos; la lista completa y vigente está allí. En el cálculo de arriba, Haiku 4.5 con 6.000 tokens supera su mínimo de 4.096; con un prefijo de 3.000 tokens no se habría cacheado.

## Relación con la compactación y con RAG

La caché premia el prefijo que no se toca. Dos técnicas de esta colección lo modifican:

- **[Compactación de contexto](Compactacion-de-Contexto.md).** Resumir o recortar el historial **reescribe una parte del prefijo**: desde el punto modificado, la caché no coincide y se paga una nueva escritura. Compactar rara vez y de una vez (en lugar de recortar un poco en cada turno) permite que el prefijo nuevo se cachee y se lea en los turnos siguientes. Modificar el historial turno a turno impide ahorrar en lo que viene después de la modificación.
- **[RAG](RAG.md).** Los fragmentos recuperados cambian según la pregunta, así que van **después** de lo estable (herramientas, instrucciones, política). La documentación muestra un reparto con varios puntos de corte (herramientas, instrucciones, documentos y conversación) para poder cambiar los documentos sin invalidar herramientas ni instrucciones. Si el mismo conjunto de documentos se reutiliza entre preguntas, también es candidato a un punto de corte propio.

Añadir turnos al final del historial **no rompe** el prefijo anterior; cambiar, reordenar o eliminar mensajes anteriores sí lo rompe desde ese punto.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| `cache_read_input_tokens` siempre en 0 y `cache_creation_input_tokens` también en 0 | El prefijo no llega al mínimo de tokens del modelo. La API procesa sin caché y **no devuelve error**. |
| `cache_creation_input_tokens` alto en cada llamada y lecturas en 0 | Algo cambia antes del punto de corte: un timestamp, un ID de sesión, un nombre de usuario. Se paga la escritura cada vez. |
| Aciertos que aparecen y desaparecen sin cambios aparentes | Orden no determinista al serializar JSON o al construir la lista de herramientas (iterar un `set` o un diccionario en órdenes distintos). |
| La caché deja de funcionar al activar o cambiar una opción | Parámetros que forman parte del prefijo: definiciones de herramientas, `tool_choice`, imágenes, `thinking`, búsqueda web, citas (ver la tabla de invalidación). |
| Llamadas en paralelo con el mismo prefijo sin aciertos | La entrada solo existe cuando empieza la primera respuesta; las paralelas no la ven. |
| Aciertos en las primeras iteraciones de un agente que se pierden después | La conversación creció 20 o más bloques desde la última escritura y la entrada quedó fuera de la ventana de búsqueda. |
| Coste mayor con caché que sin ella | Pocas lecturas por escritura o tráfico con huecos mayores que la duración. |

Ejemplo de orden no determinista de JSON (ejecutado con Python 3.12, 2026-11-10): las mismas herramientas construidas en dos órdenes producen prefijos distintos, y con `sort_keys=True` coinciden.

```python
import json, hashlib

def huella(texto):
    return hashlib.sha256(texto.encode()).hexdigest()[:12]

a = {"consultar_pedido": "Estado de un pedido", "buscar_catalogo": "Busca productos"}
b = {"buscar_catalogo": "Busca productos", "consultar_pedido": "Estado de un pedido"}

print("sin ordenar :", huella(json.dumps(a)), huella(json.dumps(b)))
print("sort_keys   :", huella(json.dumps(a, sort_keys=True)), huella(json.dumps(b, sort_keys=True)))
```

```text
sin ordenar : d586d04564e0 a5febf03e6ee
sort_keys   : a5febf03e6ee a5febf03e6ee
```

## Buenas prácticas avanzadas

- **Coloca el punto de corte en el último bloque estable, no en el último bloque.** Marcar un bloque que cambia en cada petición (un timestamp, la pregunta del usuario) escribe una entrada nueva cada vez y nunca produce lecturas. La documentación indica que, si un bloque posterior varía, el punto de corte va antes, en el último bloque estable.
- **Mide con `usage`, no con la intuición.** Registra `cache_read_input_tokens` y `cache_creation_input_tokens` por llamada y calcula la proporción de lectura. Una proporción baja con tráfico continuo señala un invalidador en el prefijo.
- **Compara los bytes del prefijo entre dos peticiones cuando no haya aciertos.** La diferencia entre la petición N y la N+1 localiza el invalidador (una fecha, un UUID, un orden distinto) con más rapidez que revisar el código.
- **Calienta la caché antes de lanzar peticiones en paralelo.** Como la entrada solo existe tras empezar la primera respuesta, se envía una sola petición y las demás después de que responda. La documentación también describe un precalentamiento con `max_tokens: 0` (con restricciones: no con streaming, razonamiento extendido, salidas estructuradas, `tool_choice` forzado ni dentro de lotes).
- **Elige la duración por el patrón de tráfico.** Con una llamada cada pocos minutos, los 5 minutos se renuevan solos y la escritura es más barata (1,25× frente a 2×). Con huecos largos pero previsibles (por ejemplo, un lote cuyas peticiones tardan entre 5 minutos y 1 hora), la de 1 hora evita reescribir. La documentación recomienda esa estrategia para lotes: enviar una petición con el prefijo y duración de 1 hora y, al terminar, el resto.
- **Reparte el prompt en puntos de corte según la frecuencia de cambio.** Herramientas, instrucciones, documentos recuperados e historial pueden ir cada uno con su punto de corte (el máximo es 4), de modo que cambiar los documentos no invalide herramientas ni instrucciones.

## Documentación oficial

- [Prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) — la fuente de todas las cifras: duraciones, multiplicadores, mínimos por modelo, tabla de invalidación y campos de `usage`. Consulta primero la tabla de precios y la de invalidación.
- [Pricing](https://platform.claude.com/docs/en/about-claude/pricing) — tarifas vigentes por modelo, incluidas las de caché, para actualizar el script de ahorro cuando cambien.

---

*En resumen: la caché de prompt reutiliza el prefijo idéntico de la petición (herramientas, system, mensajes) y cobra su lectura a una fracción del precio; pon lo estable primero y lo variable al final, comprueba `cache_read_input_tokens` en cada respuesta y recuerda que por debajo del mínimo de tokens la caché no se crea y no avisa.*
