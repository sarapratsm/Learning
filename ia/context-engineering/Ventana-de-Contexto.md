# Ventana de Contexto

## ¿Qué es?

La ventana de contexto (*context window*) es la cantidad máxima de texto que un modelo puede tener delante en una sola llamada, medida en **tokens** (los fragmentos en los que el modelo trocea el texto), no en caracteres ni en palabras. Según la documentación de Anthropic, abarca todo lo que el modelo puede consultar al generar una respuesta, **incluida la propia respuesta**: el *prompt* de sistema, cada mensaje de `messages` (con resultados de herramientas, imágenes y documentos), las definiciones de herramientas y lo que el modelo genera, razonamiento incluido.

## ¿Por qué existe?

Un modelo de lenguaje no guarda estado entre llamadas ni consulta una base de datos interna sobre la marcha: lo único que «sabe» de tu caso en una petición es lo que viaja en esa petición. Además, el mecanismo de atención de los transformadores compara cada token con todos los demás, lo que Anthropic describe como «n² pairwise relationships for n tokens» en su artículo sobre context engineering (2025-09-29). Procesar más contexto cuesta más cómputo, y eso impone un tope técnico y económico por llamada. Ese tope es la ventana.

> Si ya conoces la memoria RAM, piensa en la ventana como la RAM de la llamada: es finita, todo lo que el programa necesita ahora tiene que estar dentro, y lo que no cabe se trae del disco cuando hace falta (en este caso, recuperándolo con [RAG](RAG.md)) en vez de tenerlo todo cargado a la vez.

## ¿Cuándo y para qué se usa?

Es la primera restricción con la que choca cualquier asistente real. Ejemplo conductor de esta colección: un asistente de soporte de una tienda online que responde sobre el pedido #4711, la política de devoluciones y el catálogo. Cada turno de esa conversación manda a la API, de nuevo, el *prompt* de sistema, las definiciones de herramientas, el historial y los datos recuperados (la política de devoluciones, la ficha del producto). Con las conversaciones largas, los documentos extensos o las muchas fuentes aparece siempre la misma pregunta: qué hacer cuando lo disponible supera lo que cabe. Las secciones siguientes enseñan a medir cuánto ocupa cada cosa, a ver cómo se llena y a decidir qué hacer antes de que se llene.

## Tokens: la unidad de medida

El modelo no ve caracteres ni palabras, sino tokens: fragmentos de tamaño variable (una palabra corta, un trozo de palabra larga, un signo, un salto de línea). Todo se mide y se factura en tokens: el límite de la ventana, el precio y la latencia. El detalle del mecanismo está en [Cómo piensa un LLM](../ingenieria-con-llms/Como-Piensa-un-LLM.md); aquí solo interesa cuánto ocupa un texto.

### Aproximar sin tokenizador

La regla de uso común es «unos 4 caracteres por token» o «algo más de un token por palabra». Es una aproximación, y el script la aplica a la misma pregunta de soporte en español y en inglés:

```python
import math

ES = "¿Puedo devolver los auriculares del pedido #4711? Los recibí hace diez días y la caja sigue sin abrir."
EN = "Can I return the headphones from order #4711? I received them ten days ago and the box is still unopened."

def por_caracteres(t, cpt=4):   # regla: ~4 caracteres por token
    return math.ceil(len(t) / cpt)

def por_palabras(t, tpp=1.3):   # regla: ~1,3 tokens por palabra
    return math.ceil(len(t.split()) * tpp)

for nombre, t in (("es", ES), ("en", EN)):
    print(f"{nombre}: {len(t)} car., {len(t.split())} palabras, "
          f"car/4={por_caracteres(t)}, palabras*1,3={por_palabras(t)}")
```

Salida (ejecutada el 2026-11-10; `tiktoken` no estaba instalado y no se instaló, así que **no hay medición con un tokenizador real**):

```text
es: 102 car., 18 palabras, car/4=26, palabras*1,3=24
en: 105 car., 20 palabras, car/4=27, palabras*1,3=26
```

Ambas reglas dan cifras parecidas para las dos frases, y ese es justo el límite del método: una regla fija no capta lo que hace distinto a cada idioma. Conceptualmente, el tokenizador se construye a partir de una colección de textos de entrenamiento y reparte mejor los fragmentos que más aparecen en ella. Un texto en un idioma poco representado, o con muchas formas que el vocabulario no trae enteras (acentos, conjugaciones, nombres propios, código), tiende a partirse en más piezas. Cuánto más exactamente en español frente a inglés **no se midió aquí** y varía con el tokenizador y con el texto; para saberlo con tu contenido hay que contarlo con el tokenizador del modelo (ver [Conteo previo](#conteo-previo-de-tokens)).

La documentación de modelos de Anthropic ofrece una equivalencia de referencia para la tokenización actual (introducida con Claude Opus 4.7): 1M de tokens equivalen a unas 555k palabras o 2,5M de caracteres Unicode, y 200k tokens a unas 150k palabras. Los modelos anteriores a ese tokenizador metían unas 750k palabras en 1M de tokens (`platform.claude.com/docs/en/models/overview`, leída el 2026-11-10; la página no precisa el idioma del texto de referencia).

Dos consecuencias prácticas:

- **Cambiar de modelo puede cambiar el conteo sin cambiar el texto.** La documentación de conteo de tokens indica que los modelos desde Claude 4.7 producen aproximadamente un 30 % más de tokens para el mismo texto que los anteriores, según el contenido. Un cálculo hecho con un modelo no vale para otro.
- **No estimes con el tokenizador de otro proveedor.** Cada familia de modelos tiene el suyo.

## Qué cuenta contra la ventana

Toda petición se compone de piezas que suman. Con el asistente de la tienda:

| Pieza | Ejemplo | Crece con... |
|---|---|---|
| *Prompt* de sistema | Tono, reglas, «no inventes políticas» | Se queda fijo |
| Definiciones de herramientas | `consultar_pedido`, `buscar_catalogo` | Cada herramienta añadida |
| Historial | Mensajes previos de cliente y asistente | Cada turno |
| Resultados de herramientas y documentos | El estado del pedido #4711, el texto de la política | Cada consulta |
| Pregunta actual | «¿Puedo devolver los auriculares?» | Se queda pequeña |
| Respuesta generada, con razonamiento | La respuesta del asistente | `max_tokens` y esfuerzo |

Tres matices que documenta Anthropic (`.../build-with-claude/context-windows`, leída el 2026-11-10):

- Con *prompt caching*, la entrada se reparte entre `input_tokens`, `cache_read_input_tokens` y `cache_creation_input_tokens`, y las tres cuentan para la ventana. La caché cambia lo que pagas, no lo que ocupa (ver [Prompt Caching](Prompt-Caching.md)).
- Los bloques de razonamiento (*thinking*) de la respuesta cuentan. Los de turnos anteriores se conservan por defecto en los modelos más recientes y también cuentan; en modelos anteriores, la API los descarta al devolverlos.
- Cada respuesta informa de lo consumido en su campo `usage`.

## Tamaños vigentes y límite de salida

Valores leídos de la documentación oficial el 2026-11-10 (`.../models/overview` y `.../build-with-claude/context-windows`):

| Modelo | ID de API | Ventana | Salida máxima (`max_tokens`, API síncrona) |
|---|---|---|---|
| Claude Fable 5.2 | `claude-fable-5-2` | 1M tokens | 128K tokens |
| Claude Opus 5.5 | `claude-opus-5-5` | 1M tokens | 128K tokens |
| Claude Sonnet 5.5 | `claude-sonnet-5-5` | 1M tokens | 128K tokens |
| Claude Haiku 5.5 | `claude-haiku-5-5` | 1M tokens | 128K tokens |

La página de ventanas de contexto añade que otros modelos Claude, entre ellos Claude Sonnet 4.5 (marcado como obsoleto), tienen una ventana de 200k tokens. Para los modelos con ventana de 1M, esa cifra es el valor por defecto, sin cabecera *beta*.

Otras tres cifras que importan al diseñar:

- **Salida:** `max_tokens` es el techo de lo que genera una petición; por encima de 128K en modelos con ese límite solo se llega en la API de lotes con una cabecera *beta* (`output-300k-2026-03-24`, hasta 300k, según la página de modelos).
- **Imágenes y PDF:** hasta 600 imágenes o páginas de PDF por petición (100 en modelos de 200k), y puede saltar antes el límite de tamaño de la petición que el de tokens.
- **Precio por tramo:** en los modelos de 1M, una petición de 900k tokens se factura a la misma tarifa por token que una de 9k, salvo en Claude Haiku 5.5, cuyas peticiones de más de 100.000 tokens cuestan más (página de precios, leída el 2026-11-10).

Estos números cambian con cada generación. Para leerlos desde código en vez de copiarlos, la Models API devuelve `max_input_tokens` (ventana) y `max_tokens` (salida) de cada modelo.

## Cómo se llena una conversación

En una API sin estado, cada turno reenvía todo: el modelo «recuerda» porque tú le vuelves a mandar el historial. La entrada del turno *n* contiene los *n−1* turnos anteriores completos, resultados de herramientas incluidos.

El siguiente script simula la conversación de soporte con una ventana de juguete de 1.000 tokens, con 300 reservados para la respuesta. Los tokens se aproximan con caracteres/4; no es un tokenizador real, pero sirve para ver la mecánica:

```python
import math

VENTANA = 1_000          # ventana de juguete, en tokens
MAX_TOKENS = 300         # reserva para la respuesta
def tok(t): return math.ceil(len(t) / 4)   # APROXIMACIÓN, no un tokenizador real

SISTEMA = ("Eres el asistente de soporte de una tienda online. Responde con cortesía, "
           "cita el número de pedido y no inventes políticas. Devoluciones: 30 días.")
HERRAMIENTAS = 220       # definiciones de herramientas (consultar_pedido, buscar_catalogo)

turnos = [  # (usuario, asistente, resultado de herramienta)
 ("¿Cómo va mi pedido #4711?", "Tu pedido #4711 salió ayer y llega mañana.", "estado=enviado; transportista=...; " * 8),
 ("¿Puedo devolver los auriculares?", "Sí, tienes 30 días desde la entrega.", ""),
 ("¿Y si la caja está abierta?", "Se admite si el producto está en buen estado.", "política_devoluciones: " + "texto de la política. " * 25),
 ("¿Tenéis la versión negra?", "Sí, hay stock de la versión negra.", "catálogo: " + "ficha de producto. " * 30),
 ("¿Cuánto tarda el reembolso?", "Entre 5 y 7 días laborables tras recibirlo.", ""),
 ("¿Puedo cambiar la dirección?", "Mientras no salga del almacén, sí.", "pedido #4711: " + "línea de pedido. " * 40),
 ("Gracias, ¿algo más que deba saber?", "Conserva el justificante de envío.", ""),
]

usado = tok(SISTEMA) + HERRAMIENTAS
for i, (u, a, r) in enumerate(turnos, 1):
    entrada = usado + tok(u) + tok(r)            # lo que se envía en este turno
    total = entrada + MAX_TOKENS
    estado = "cabe" if total <= VENTANA else ("ENTRADA NO CABE" if entrada > VENTANA else "la salida puede cortarse")
    print(f"{i:>5} {entrada:>18} {total:>10}  {estado}")
    if total > VENTANA:
        break
    usado = entrada + tok(a)                      # la respuesta pasa al historial
```

Salida (ejecutada el 2026-11-10; las columnas son turno, tokens de entrada acumulados y entrada más reserva de salida):

```text
    1                334        634  cabe
    2                353        653  cabe
    3                513        813  cabe
    4                677        977  cabe
    5                693        993  cabe
    6                885       1185  la salida puede cortarse
```

La entrada del turno 6 (885) todavía cabe en la ventana de 1.000, pero entrada más reserva de respuesta (1.185) no. Dos observaciones:

- **Los resultados de herramientas son lo que más pesa**, no los mensajes de la conversación: el texto de la política (turno 3), la ficha del catálogo (turno 4) y el detalle del pedido (turno 6) ocupan mucho más que las preguntas y respuestas.
- **El desborde llega antes de lo que sugiere la entrada sola**, porque la respuesta también ocupa sitio. En una ventana real de 1M el mismo mecanismo se alcanza con agentes que leen ficheros o con conversaciones de cientos de turnos.

### Qué hace la API al desbordar

Según la página de ventanas de contexto (leída el 2026-11-10):

- Si **solo la entrada** ya supera la ventana, la API devuelve un 400 `invalid_request_error` («prompt is too long») en todos los modelos.
- En Claude 4.5 y posteriores, si entrada más `max_tokens` supera la ventana, **la API acepta la petición**; si la generación llega al límite, se detiene con `stop_reason: "model_context_window_exceeded"`, y la respuesta debe tratarse como truncada. En modelos anteriores, devolvía un error de validación.

Por tanto, el simulador anterior reproduce la lógica del segundo caso: no hay error, sino una respuesta que se queda a medias.

```python
respuesta = client.messages.create(model="claude-sonnet-5-5", max_tokens=4096, messages=mensajes)

if respuesta.stop_reason in ("max_tokens", "model_context_window_exceeded"):
    # La respuesta está truncada: no la guardes como completa.
    ...
```

`max_tokens` significa que se agotó el presupuesto de salida de la propia petición; `model_context_window_exceeded` significa que se agotó la ventana. Las dos cortan la respuesta y ninguna es un error HTTP. La gestión del primero está en [Llamadas a la API](../ingenieria-con-llms/Llamadas-a-la-API.md).

## Coste y latencia crecientes

Si cada turno reenvía el historial, la factura de entrada por turno crece linealmente con el número de turnos, y la factura de la conversación completa crece de forma cuadrática. Con las tarifas de Claude Sonnet 5.5 ($2 por millón de tokens de entrada y $10 por millón de salida, página de precios leída el 2026-11-10) y unos supuestos explícitos (3.000 tokens fijos de sistema y herramientas, 150 por mensaje de cliente, 250 por respuesta):

```python
P_IN, P_OUT = 2.0, 10.0
FIJO, USUARIO, ASISTENTE = 3_000, 150, 250

acum_in = acum_out = historial = 0
for t in range(1, 41):
    entrada = FIJO + historial + USUARIO
    acum_in += entrada; acum_out += ASISTENTE
    historial += USUARIO + ASISTENTE
    if t in (1, 10, 20, 40):
        coste_turno = entrada / 1e6 * P_IN + ASISTENTE / 1e6 * P_OUT
        print(t, f"{entrada:,}", f"{coste_turno:.4f}", f"{acum_in/1e6*P_IN + acum_out/1e6*P_OUT:.4f}")
print(f"entrada facturada: {acum_in:,}; texto distinto enviado: {FIJO + 40*(USUARIO+ASISTENTE):,}")
```

Salida (ejecutada el 2026-11-10; columnas: turno, tokens de entrada del turno, coste del turno en dólares, coste acumulado en dólares):

```text
1 3,150 0.0088 0.0088
10 6,750 0.0160 0.1240
20 10,750 0.0240 0.3280
40 18,750 0.0400 0.9760
entrada facturada: 438,000; texto distinto enviado: 19,000
```

En 40 turnos se facturan 438.000 tokens de entrada para 19.000 tokens de texto realmente distinto: el modelo vuelve a leer, y a cobrarse, el mismo historial en cada turno. El importe es pequeño por conversación y se multiplica por el tráfico. La palanca contra esto es el [Prompt Caching](Prompt-Caching.md), que rebaja el precio de la parte repetida (las tarifas de caché, en la página de precios) sin quitarla de la ventana.

**Latencia.** La documentación de modelos indica que la latencia real depende de la longitud del *prompt*, la longitud de la salida y el esfuerzo de razonamiento (`.../models/overview`, 2026-11-10). No se midió aquí ni hay cifras que citar: si importa, se mide con tu propio tráfico.

## Más contexto no es mejor contexto

Que algo quepa no significa que el modelo lo use bien. Cuatro fuentes, leídas el 2026-11-10 y **no medidas aquí**:

- **Documentación de Anthropic.** La página de ventanas de contexto dice que a medida que crece el número de tokens la precisión y la capacidad de recuperación se degradan, un fenómeno llamado *context rot*, y que por eso decidir qué entra en el contexto importa tanto como cuánto espacio hay.
- **«Lost in the Middle: How Language Models Use Long Contexts»** (Liu et al., arXiv 2307.03172, enviado en julio de 2023, revisado en noviembre de 2023). Los autores observan que el rendimiento suele ser máximo cuando la información relevante está al principio o al final de la entrada y baja cuando está en medio, incluso en modelos pensados para contextos largos. Es un resultado de modelos de 2023: no se puede dar por válido tal cual para los modelos actuales.
- **«Context Rot: How Increasing Input Tokens Impacts LLM Performance»** (Hong, Troynikov y Huber, Chroma, 14 de julio de 2025). Probaron 18 modelos y concluyen que el rendimiento se vuelve menos fiable al crecer la entrada, incluso en tareas simples; que un distractor relacionado con el tema ya reduce la precisión; y que, en una prueba de memoria conversacional (LongMemEval), los modelos rindieron mejor con solo el historial relevante que con el historial completo de unos 113k tokens.
- **«Effective context engineering for AI agents»** (Anthropic, 29 de septiembre de 2025). Propone tratar el contexto como «a finite resource with diminishing marginal returns».

Para el asistente de soporte, la lección práctica es poner delante del modelo la política de devoluciones relevante, no los treinta documentos de la base de conocimiento.

## Cuando no cabe: estrategias

Hay cuatro familias de respuesta. Cada una tiene su ficha.

| Estrategia | Qué hace | Cuándo | Ficha |
|---|---|---|---|
| **Recortar** | Descarta lo más antiguo o menos útil (turnos viejos, resultados de herramientas ya usados) | Hay contenido que ya no aporta; tolera perder detalle | [Compactación de Contexto](Compactacion-de-Contexto.md) |
| **Resumir** | Sustituye el historial por un resumen más corto | Conversación larga cuyo hilo hay que conservar | [Compactación de Contexto](Compactacion-de-Contexto.md) |
| **Recuperar** | Deja el conocimiento fuera y trae solo los fragmentos relevantes cuando se necesitan | Base de conocimiento mayor que la ventana | [RAG](RAG.md), [Chunking](Chunking.md) |
| **Dividir** | Reparte la tarea entre varios agentes, cada uno con su propia ventana | Subtareas independientes con mucho ruido | [Aislamiento de Contexto](Aislamiento-de-Contexto.md) |

Otras dos fichas se cruzan: [Memoria de Agentes](Memoria-de-Agentes.md) para lo que debe sobrevivir entre sesiones, y [Prompt Caching](Prompt-Caching.md) para abaratar la parte que no cambia. Anthropic ofrece además la compactación en el servidor (en *beta*; los modelos compatibles figuran en la documentación, consultada el 2026-11-10) y la edición de contexto (limpiar resultados antiguos de herramientas o bloques de razonamiento), descritas en la página de ventanas de contexto.

Cuándo **no** hace falta ninguna: si la conversación típica ocupa una fracción pequeña de la ventana, medirlo y no hacer nada es una decisión válida. Cada estrategia añade piezas que fallar.

## Conteo previo de tokens

Para no depender de aproximaciones, la API de Anthropic tiene un endpoint de conteo, `POST /v1/messages/count_tokens`, que acepta la misma estructura que la creación de un mensaje (sistema, herramientas, imágenes, PDF) y devuelve el total de tokens de entrada. Según la documentación (`.../build-with-claude/token-counting`, leída el 2026-11-10):

- Es gratuito, con un límite de peticiones por minuto según tu nivel de uso (5.000, 10.000 o 20.000 en los niveles Start, Build y Scale) y límites independientes de los de crear mensajes.
- El resultado es una **estimación**: el número real puede diferir en poca cantidad, y puede incluir tokens que añade Anthropic por optimización y que no se facturan.
- Cuenta con el tokenizador del modelo que indiques en `model`.
- Falla con `invalid_request_error` para algunas entradas que la API de mensajes sí admite: herramientas de servidor (búsqueda web, ejecución de código...), el conector MCP, y bloques de imagen o documento con origen `url` o `file`.
- No usa la caché de *prompts*: aunque pases `cache_control`, la caché solo actúa al crear el mensaje.

La forma de la llamada, tomada de la documentación (no se ejecutó aquí: exige clave y petición a la API):

```python
import anthropic

client = anthropic.Anthropic()

respuesta = client.messages.count_tokens(
    model="claude-sonnet-5-5",
    system=SISTEMA,
    tools=HERRAMIENTAS,
    messages=mensajes,
)
print(respuesta.input_tokens)
```

Con el ejemplo básico de la documentación (`"You are a scientist"` y `"Hello, Claude"`), el resultado documentado es `{ "input_tokens": 14 }`. El patrón de uso es un guardián previo a la llamada:

```python
PRESUPUESTO_ENTRADA = 800_000   # decisión de diseño, no un valor de la API

if respuesta.input_tokens > PRESUPUESTO_ENTRADA:
    mensajes = compactar(mensajes)   # ver Compactación de Contexto
```

Si la entrada ya supera la ventana, el conteo no la reduce: solo avisa a tiempo para que decidas qué recortar antes de la llamada.

## Errores frecuentes

| Síntoma | Causa |
|---|---|
| 400 `invalid_request_error` («prompt is too long») | La entrada sola ya supera la ventana. Hay que reducirla antes de enviar: el modelo no puede «apañárselas» |
| Respuesta cortada a mitad de frase o JSON incompleto, sin error HTTP | `stop_reason` es `max_tokens` o `model_context_window_exceeded`; se guardó como completa sin comprobarlo |
| Respuestas truncadas justo cuando la conversación se hace larga | Entrada más `max_tokens` roza la ventana: no se reservó sitio para la salida |
| Cálculo de costes que no cuadra tras cambiar de modelo | El tokenizador cambió; se reutilizó un conteo hecho con otro modelo |
| `input_tokens` bajo en la respuesta pese a un prompt enorme | Con caché, ese campo es solo la parte no cacheada; el *prompt* completo es la suma de `input_tokens`, `cache_read_input_tokens` y `cache_creation_input_tokens` |
| El asistente ignora una instrucción dicha hace muchos turnos | No se «olvidó»: quedó enterrada en un contexto largo (ver *lost in the middle* y *context rot*), o está contradicha más adelante |
| Imágenes o PDF rechazados antes de llegar al límite de tokens | Salta antes el límite de tamaño de la petición (o el de 600 imágenes o páginas) |

## Buenas prácticas avanzadas

- **Reserva la salida antes de decidir cuánto meter de entrada.** El presupuesto es `ventana − max_tokens − tokens fijos`, y no al revés. En los modelos recientes el desborde por entrada más `max_tokens` no da error sino una respuesta truncada, por lo que es fácil no enterarse.
- **Cuenta por pieza, no solo el total.** Cuando la ventana se llena, casi siempre es por los resultados de herramientas y los documentos, no por la conversación (como en el simulador). Medir cada pieza dice qué recortar; el total solo dice que hay que recortar.
- **Lee la suma completa de `usage`.** Con caché, `input_tokens` no es el tamaño del *prompt*. Un panel de consumo que solo mira ese campo infraestima lo que ocupa la ventana.
- **Recuenta al cambiar de modelo.** La documentación avisa de que el tokenizador de Claude 4.7 y posteriores produce aproximadamente un 30 % más de tokens para el mismo texto que modelos anteriores: un presupuesto de contexto pensado con otro modelo puede quedarse corto sin que cambie una línea.
- **Pon lo crítico donde menos se pierde.** Las instrucciones y el dato decisivo (la regla de devolución que aplica) van al principio o al final del contexto, no en medio de un volcado de documentos. Los estudios citados son de modelos concretos y fechas concretas: valídalo con tus propias evaluaciones (ver [Evaluaciones de LLMs](../ingenieria-con-llms/Evaluaciones-de-LLMs.md)).
- **Trata el tamaño máximo como techo, no como objetivo.** Una ventana de 1M tiene sentido para el caso que realmente lo exige (un repositorio entero, un contrato largo). Rellenarla «porque hay sitio» sube el coste lineal y expone a la degradación descrita arriba.

## Documentación oficial

- [Context windows](https://platform.claude.com/docs/en/build-with-claude/context-windows) — qué cuenta contra la ventana, tamaños por modelo, comportamiento al desbordar y la compactación del lado del servidor. La sección «Context window overflow behavior» es la que conviene leer primero.
- [Token counting](https://platform.claude.com/docs/en/build-with-claude/token-counting) — el endpoint de conteo previo: qué acepta, qué rechaza, límites de uso y diferencias de tokenizador entre modelos.
- [Models overview](https://platform.claude.com/docs/en/models/overview) — tabla comparativa con ventana, salida máxima, IDs y precio de cada modelo vigente.
- [Pricing](https://platform.claude.com/docs/en/about-claude/pricing) — tarifas por millón de tokens, caché y el tramo de precio de Claude Haiku 5.5 por encima de 100.000 tokens.

## Recursos didácticos

- [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — el artículo de Anthropic que presenta el contexto como recurso finito con rendimientos decrecientes.
- [Lost in the Middle (arXiv 2307.03172)](https://arxiv.org/abs/2307.03172) — el estudio que popularizó el efecto de posición en contextos largos.
- [Context Rot (Chroma)](https://www.trychroma.com/research/context-rot) — informe técnico con experimentos sobre 18 modelos y su degradación al crecer la entrada.

---

*En resumen: la ventana de contexto es la RAM de cada llamada —finita, medida en tokens y compartida entre lo que envías y lo que el modelo responde—, y diseñar un presupuesto (medir, reservar la salida y decidir qué recortar, resumir, recuperar o dividir) vale más que confiar en que quepa.*
