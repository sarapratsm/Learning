# Compactación de Contexto

## ¿Qué es?

La compactación es reducir el historial que se reenvía a un LLM en cada llamada —resumiéndolo, podándolo o recortándolo— para liberar espacio en la ventana de contexto conservando lo que la tarea sigue necesitando. Se aplica a un historial que ya existe; no decide qué información entra al principio (eso es [RAG](RAG.md)) ni qué sobrevive entre sesiones (eso es [Memoria de Agentes](Memoria-de-Agentes.md)).

## ¿Por qué existe?

Un modelo no recuerda nada entre llamadas: la aplicación reenvía el historial entero cada vez (el mecanismo está en [Llamadas a la API](../ingenieria-con-llms/Llamadas-a-la-API.md)). Cada turno añade mensajes, y en un agente con herramientas añade además sus resultados, que suelen pesar mucho más que la conversación. Tarde o temprano el historial no cabe en la [ventana de contexto](Ventana-de-Contexto.md), y mucho antes de que no quepa ya cuesta más y se maneja peor.

Las dos salidas ingenuas fallan. Reenviar todo agota la ventana. Quedarse solo con los últimos N mensajes pierde justo lo que se dijo al principio: el número de pedido, la decisión ya tomada. La compactación busca el término medio: tirar lo que ya no aporta y condensar lo que sí.

> Si ya conoces la rotación de logs, piensa en la compactación como una política de retención: los registros recientes se guardan enteros, los antiguos se agregan o se descartan, y lo que no puede perderse se marca para que no se rote.

## ¿Cuándo y para qué se usa?

Aparece cuando el contexto crece sin techo claro:

- **Un chat de soporte largo.** El asistente de la tienda atiende a una clienta durante decenas de mensajes: consulta el pedido #4711, la política de devoluciones y el catálogo, y la conversación acumula miles de tokens de resultados de herramientas.
- **Un agente que trabaja por pasos.** Cada paso lee ficheros o consulta APIs y deja su salida en el historial.
- **Una sesión de programación asistida.** Los agentes de codificación compactan automáticamente al acercarse al límite (ver [Agentes de codificación](../ingenieria-con-llms/Agentes-de-Codificacion.md), que cubre los hábitos de uso; aquí se explica el mecanismo).

No hace falta si la conversación típica ocupa una fracción pequeña de la ventana: medirlo y no hacer nada es una decisión válida, porque compactar añade piezas que pueden fallar.

## Estrategias y cuándo usar cada una

Cinco familias. Las tres primeras son deterministas (código sin modelo, gratuitas y predecibles); las dos últimas necesitan que un modelo escriba un resumen.

| Estrategia | Qué hace | Qué pierde | Cuándo |
|---|---|---|---|
| **Truncado de lo más antiguo** | Borra los mensajes más viejos hasta caber en un presupuesto | Todo lo antiguo, importante o no | Conversaciones donde lo antiguo caduca solo (consultas sueltas) |
| **Ventana deslizante** | Conserva el *system prompt* y los últimos N mensajes | Todo lo anterior a la ventana | Chats cortos sin decisiones que arrastrar |
| **Poda de resultados de herramienta** | Sustituye por un marcador las salidas voluminosas ya usadas | El detalle de esas salidas (recuperable si se repite la llamada) | Agentes con herramientas: casi siempre la primera medida |
| **Resumen progresivo** | Un modelo resume lo antiguo; el resumen se acumula con los mensajes nuevos | Matices y datos que el resumen omita | Conversaciones largas cuyo hilo hay que conservar |
| **Resumen estructurado** | Igual, pero con campos fijos (decisiones, hechos, pendientes) | Menos: los campos obligan a listar lo crítico | Cuando hay datos que no pueden perderse (números de pedido, acuerdos) |

Tabla de decisión por situación:

| Situación | Elige |
|---|---|
| El historial es sobre todo resultados de herramientas | Poda de resultados primero; resumir solo si sigue sin caber |
| Chat corto, sin datos que arrastrar | Ventana deslizante |
| Hay decisiones o identificadores que deben sobrevivir | Resumen estructurado |
| La tarea es larga y crece sin parar | Poda + resumen estructurado con los últimos turnos literales |
| Necesitas coste y comportamiento 100 % predecibles | Solo políticas deterministas |

Un patrón se repite en casi todas: **los últimos turnos se conservan literales**, porque son los que el modelo está usando ahora mismo.

## Las políticas deterministas, con código

La simulación usa Python estándar. Los tokens se estiman como caracteres/4: es una aproximación, no un tokenizador real (no medido con ninguno). La «ventana» de 8.000 tokens es ficticia, solo para ver los porcentajes. La conversación simulada es un soporte de tienda con 40 mensajes (usuario, asistente, llamadas a herramientas y sus resultados), con resultados voluminosos: el JSON del pedido #4711 con su historial de eventos, la política de devoluciones y listados de catálogo. Incluye hechos que no deben perderse: el pedido #4711, la decisión de reembolsar a la tarjeta terminada en 4242 y no con vale, que el pedido ya está en reparto y no se puede cambiar la dirección, y el seguimiento TX-90817234.

El código completo es corto; estas son las piezas centrales.

```python
def tokens(texto):
    """Aproximación: 1 token ~ 4 caracteres. No es un tokenizador real."""
    return max(1, len(texto) // 4)

def total(msgs):
    return sum(tokens(m["content"]) for m in msgs)
```

Cada mensaje es un diccionario `{"role", "kind", "content", "turn"}`; `kind` distingue `msg`, `tool_call` y `tool_result`.

### Truncado de lo más antiguo

Se descartan los mensajes más viejos, salvo el *system prompt*, hasta entrar en un presupuesto.

```python
def truncar_antiguos(msgs, presupuesto):
    sistema, resto = msgs[:1], msgs[1:]
    while resto and total(sistema + resto) > presupuesto:
        resto = resto[1:]
    return sistema + resto
```

### Ventana deslizante

Se conservan el *system prompt* y los últimos `n` mensajes.

```python
def ventana_deslizante(msgs, n):
    return msgs[:1] + msgs[-n:]
```

### Poda de resultados de herramienta

Los resultados antiguos se sustituyen por un marcador que dice qué había y cuánto pesaba; se conserva el último. Los mensajes del usuario y del asistente quedan intactos.

```python
def podar_resultados(msgs, conservar=1):
    idx = [i for i, m in enumerate(msgs) if m["kind"] == "tool_result"]
    viejos = set(idx[:-conservar]) if conservar else set(idx)
    return [
        {**m, "content": f"[resultado eliminado: ~{tokens(m['content'])} tokens]"}
        if i in viejos else m
        for i, m in enumerate(msgs)
    ]
```

### Resultado

Salida real de ejecutar las tres políticas sobre la conversación (2026-11-10, Python 3.12, sin tokenizador real). Antes de compactar: 40 mensajes, 7.892 tokens aproximados, de los cuales 7.508 son resultados de herramientas.

| Política | Mensajes | Tokens aprox. | Reducción | #4711 | Decisión (tarjeta 4242) | Dirección no modificable | Seguimiento |
|---|---|---|---|---|---|---|---|
| Truncado (presupuesto 3.000) | 40 → 15 | 7.892 → 2.531 | 67 % | pierde | pierde | pierde | pierde |
| Ventana deslizante (8 últimos) | 40 → 9 | 7.892 → 1.191 | 84 % | pierde | pierde | pierde | pierde |
| Poda de resultados (conserva 1) | 40 → 40 | 7.892 → 1.534 | 80 % | conserva | conserva | conserva | conserva |

Casi todo el peso estaba en los resultados de herramientas, no en la conversación. Podarlos ahorra tanto como la ventana deslizante sin perder ninguno de los hechos, porque los hechos viven en los mensajes del asistente y del usuario, que se mantienen. Truncado y ventana ahorran, pero cortan por antigüedad y no por importancia: el número de pedido y la decisión están en los primeros mensajes y son lo primero que desaparece.

Lo que la poda sí pierde es el contenido de los resultados (los 25 eventos del transportista, las cláusulas de la política). Es aceptable porque el agente puede volver a llamar a la herramienta; no lo es si el resultado no se puede reproducir (una consulta a un sistema que cambia, una petición con coste).

## Resumir: el contraste que importa

Cuando hace falta un resumen, lo que cambia el resultado es qué se le pide que conserve. Los dos resúmenes siguientes están escritos a mano, sin llamar a un modelo, para ver el efecto; un modelo real puede producir resúmenes mejores o peores que estos (no medido aquí). En ambos casos se conservan literales los dos últimos mensajes, y en ninguno de los dos aparece ya el número de pedido en esos mensajes.

❌ Resumen libre que pierde los datos críticos:

```text
Resumen escrito a mano, sin llamar a un modelo: la clienta preguntó por un pedido,
consultó devoluciones y productos, y se le atendió.
```

Mensajes 40 → 4, tokens aprox. 7.892 → 79. Pierde el pedido #4711, la decisión del reembolso, la imposibilidad de cambiar la dirección y el seguimiento. Cuando la clienta pregunte «¿qué quedamos con el reembolso de mi pedido?», el asistente no tiene de dónde sacarlo y es probable que invente o vuelva a preguntar. (Conserva «CAM-220 talla M» solo porque aparece en los dos últimos mensajes literales.)

✅ Resumen estructurado con campos fijos:

```text
Resumen escrito a mano, sin llamar a un modelo.
DECISIONES: reembolso al método de pago original (tarjeta terminada en 4242), no vale.
HECHOS: pedido #4711 enviado con TransExpress, seguimiento TX-90817234; no se puede
cambiar la dirección (ya en reparto); plazo de devolución 30 días; CAM-220 talla M, 3 unidades.
PENDIENTES: confirmar fecha de entrega; añadida CAM-220 M al pedido nuevo.
```

Mensajes 40 → 4, tokens aprox. 7.892 → 143. Conserva los cinco hechos de control. Cuesta 64 tokens más que el vago, y ese es todo el precio de no perder el pedido.

La regla de fondo: **un resumen sin campos obligatorios omite lo que no parece importante, y lo importante solo se sabe después**. Los campos fijos (decisiones, hechos, pendientes) fuerzan a listar los identificadores y los acuerdos antes de redactar prosa. Cuando uses un modelo para resumir, pide esa estructura en la instrucción de resumen y dile explícitamente qué datos no debe omitir.

## Cuándo disparar la compactación

Disparar por umbral porcentual de la ventana, no por «cuando falle»:

```python
def deberia_compactar(tokens_actuales, ventana, umbral=0.75):
    return tokens_actuales >= ventana * umbral
```

Con la ventana ficticia de 8.000 tokens, la conversación de 7.892 supera el 75 % y la función devuelve `True`. El 75 % es un valor de ejemplo, no una recomendación: el razonamiento para elegirlo es el siguiente.

- **Tiene que quedar margen para trabajar.** Compactar cuesta tokens (un resumen con modelo es una llamada más, que lee el historial entero) y la respuesta del turno actual también necesita sitio. Un umbral cercano al 100 % deja sin hueco para ambas.
- **Un umbral bajo compacta demasiado.** Cada compactación pierde detalle y, en los resúmenes con modelo, cuesta una llamada; compactar al 30 % desperdicia ventana disponible.
- **El tamaño efectivo es menor que el nominal.** La documentación de Anthropic indica que la calidad de las respuestas se degrada al crecer la conversación (ver [Ventana de Contexto](Ventana-de-Contexto.md)), así que el umbral útil suele quedar por debajo del límite técnico.
- **Los tokens hay que medirlos, no estimarlos a ojo.** En la API de Anthropic, el tamaño de la próxima petición se estima sumando `input_tokens` y `output_tokens` de la última respuesta, más `cache_read_input_tokens` y `cache_creation_input_tokens` si usas caché; también existe el endpoint de conteo (página «Compaction on demand», leída el 2026-11-10).
- **Compacta en un punto natural.** Entre subobjetivos, no a mitad de una depuración: lo resumido pierde detalle.

El valor concreto se calibra con las conversaciones reales de la aplicación: mide cuántos turnos tardan en llegar al umbral y cuánto detalle se pierde.

## Compactación en Claude Code

Según la documentación de Claude Code (páginas *Explore the context window* y *Manage costs effectively*, leídas el 2026-11-10):

- **Compactación automática.** Claude Code compacta solo al acercarse al límite de contexto. Con `/autocompact` y un número de tokens (por ejemplo `/autocompact 500k`) se fija cuánto se llena la ventana antes de que actúe; también existe la variable de entorno `CLAUDE_CODE_AUTO_COMPACT_WINDOW`. Los umbrales por defecto dependen del modelo y están en la sección *Default auto-compact thresholds* de la página *model-config*; no se han podido leer completos aquí y no se citan.
- **`/compact`.** Lo ejecuta quien usa la herramienta, con instrucciones opcionales: `/compact focus on the auth bug fix`. El resumen conserva lo que se indica en lugar de lo que la pasada automática «adivina».
- **Instrucciones permanentes.** Un apartado `# Compact instructions` en `CLAUDE.md` indica qué priorizar al resumir (el ejemplo de la documentación: «focus on test output and code changes»).
- **Compactar solo una parte.** `/rewind`, elegir un mensaje y **Summarize from here** o **Summarize up to here**.
- **Qué sobrevive.** El *system prompt* y el estilo de salida siguen aplicando; el `CLAUDE.md` de la raíz y las reglas sin `paths:` se reinyectan desde disco; se vuelven a leer hasta cinco de los ficheros leídos o editados (los más recientes, y los de más de 5.000 tokens vuelven como referencia sin contenido). Lo que solo estaba en la conversación, incluidas las reglas con `paths:` ya cargadas y lo que añadieron los *hooks*, se resume con el resto. De ahí la práctica: lo que debe sobrevivir, a un fichero.
- **Empezar de cero.** `/clear` descarta la conversación sin coste; compactar sirve cuando quieres continuidad.

## Funciones de la API de Anthropic

Todas son *beta* según la documentación consultada el 2026-11-10 (páginas de `platform.claude.com/docs/en/build-with-claude/`). Los nombres, cabeceras y modelos compatibles cambian con frecuencia: verifica antes de usarlos. No se ha llamado a ninguna API para escribir esta sección.

### Compactación del servidor, a petición

Es la opción que la página general *Compaction overview* recomienda donde esté disponible: la aplicación decide cuándo, enviando una petición, y la API devuelve un resumen escrito por el modelo en lugar de una respuesta.

- Cabecera beta: `anthropic-beta: compact-2026-09-04` (en el SDK de Python, `betas=["compact-2026-09-04"]`), en la petición de resumen y en todas las posteriores que lleven el bloque.
- Parámetro de primer nivel: `compaction`, con `{"type": "summarize"}`. Opcionalmente `instructions` (hasta 16.384 caracteres), que **sustituye por completo** al *prompt* de resumen por defecto.
- Respuesta: un único bloque `compaction` con el texto del resumen en `content` y una `signature`, y `stop_reason` igual a `"compaction"`. El bloque se reenvía tal cual, sin modificar `signature` ni `content`: si se altera, la API responde 400 (`compaction_signature_invalid` o `compaction_content_mismatch`).
- Continuar: el bloque va el primero en `messages`, en lugar de los mensajes que resume, y el siguiente turno va detrás. Para compactar otra vez, se envía `compaction` de nuevo; el bloque nuevo resume el anterior y lo posterior.
- No se puede combinar `compaction` con `context_management` en la misma petición. Imágenes, documentos y URL recuperadas dentro de lo resumido desaparecen con el bloque.

```python
response = client.beta.messages.create(
    model="claude-opus-5-5",
    max_tokens=4096,
    betas=["compact-2026-09-04"],
    messages=historial,
    compaction={
        "type": "summarize",
        "instructions": "Resume la conversación de soporte. Conserva el número de pedido, "
                        "las decisiones tomadas y los pendientes. No llames a herramientas.",
    },
)
# response.stop_reason == "compaction"; response.content[0].type == "compaction"
```

Qué hace: pide a la API un resumen del historial enviado con instrucciones propias. Qué devuelve: un mensaje de asistente cuyo único bloque es el resumen firmado; el historial de la aplicación pasa a ser ese mensaje más los turnos nuevos. (El ejemplo sigue la forma del de la documentación, con instrucciones adaptadas; no se ha ejecutado.)

### Compactación del servidor, por umbral

La API decide cuándo, dentro de peticiones normales. La página *Compaction at a token threshold* (leída el 2026-11-10) indica:

- Cabecera beta: `compact-2026-01-12`.
- Parámetro: `context_management` con una lista `edits` cuyo elemento tiene `type: "compact_20260112"`, `trigger` (`{"type": "input_tokens", "value": ...}`; por defecto 150.000, mínimo 50.000), `pause_after_compaction` (booleano, por defecto `false`) e `instructions`.
- Con `pause_after_compaction`, la respuesta se detiene con `stop_reason: "compaction"` para poder reinsertar turnos recientes literales.

### Edición de contexto (*context editing*)

No resume: borra por regla. La página *Context editing* (leída el 2026-11-10) describe:

- Cabecera beta: `context-management-2025-06-27`.
- Estrategia de resultados de herramienta: `clear_tool_uses_20250919`, con `trigger` (por defecto 100.000 tokens de entrada), `keep` (por defecto los 3 últimos pares uso/resultado), `clear_at_least`, `exclude_tools` y `clear_tool_inputs`. Los resultados borrados se sustituyen por un texto marcador, como la poda de la simulación.
- Estrategia de razonamiento: `clear_thinking_20251015`, con `keep`.
- Qué se aplicó, en la respuesta: `context_management.applied_edits`.
- La página recomienda la compactación del servidor para la mayoría de conversaciones largas y reserva la edición de contexto para cuando se necesita más control sobre qué se borra. Combinable con la herramienta de memoria (`memory_20250818`): antes de borrar, Claude recibe un aviso para guardar lo importante.

### Resumen de la API frente a un resumen propio

| | Compactación a petición | Compactación por umbral | Edición de contexto | Resumen propio (tu código) |
|---|---|---|---|---|
| Quién decide cuándo | Tu aplicación | La API | La API, por regla | Tu aplicación |
| Resume con modelo | Sí | Sí | No, borra | Sí |
| Control del contenido | `instructions` | `instructions` | `exclude_tools`, `keep` | Total |
| Código que escribes | Un bucle de compactación | Un parámetro | Un parámetro | La llamada, el *prompt* y la reescritura del historial |

Lo que hace falta confirmar para cada caso concreto (modelos compatibles, plataformas, si una cabecera sigue vigente) está en la sección *API support* de cada página; la lista de modelos cambia con cada lanzamiento.

## Riesgos

- **Pérdida de detalles críticos.** Cualquier compactación pierde algo. El resumen libre del contraste anterior perdió el pedido y la decisión sin dar aviso. Defensas: campos fijos, instrucciones que nombren qué conservar y lista de «datos que no pueden perderse» comprobada con código, como la simulación.
- **Deriva por resúmenes sucesivos.** Al compactar otra vez se resume un resumen: cada pasada puede omitir algo y lo omitido ya no se recupera. Los hechos críticos tienen que reaparecer en cada pasada (campos fijos otra vez) o vivir fuera de la conversación (en un fichero, en la base de datos del pedido, en memoria). Es una consecuencia razonada del mecanismo, no se ha medido aquí.
- **Romper la caché de *prompt*.** Compactar sustituye el historial por otro, de modo que el prefijo cambia y lo cacheado de la conversación deja de servir. La documentación de Claude Code lo confirma (página *How Claude Code uses prompt caching*, 2026-11-10): compactar invalida la capa de conversación, mientras que el *system prompt* y el contexto del proyecto pueden seguir cacheados. Cómo funciona la caché y cuánto cuesta está en [Prompt Caching](Prompt-Caching.md). La consecuencia práctica: compactar menos veces y con más margen cuesta menos que compactar a menudo.
- **El propio resumen cuesta.** Un resumen con modelo lee el historial entero; si el historial es enorme, la compactación es una petición grande.
- **Contenido que el resumen no puede llevar.** Imágenes y documentos dentro de lo resumido se pierden en la compactación de la API; hay que volver a aportarlos.

## Errores frecuentes

| Síntoma | Causa habitual |
|---|---|
| El asistente pregunta de nuevo el número de pedido tras compactar | El resumen no tenía campo de identificadores; el dato estaba solo en un mensaje antiguo |
| El asistente contradice un acuerdo anterior | La decisión no se listó en el resumen o se resumió como prosa vaga |
| Tras varias compactaciones el asistente «se vuelve genérico» | Resumen de resumen: los datos se diluyen en cada pasada |
| La factura sube tras añadir compactación | Cada compactación rompe la caché del historial y el resumen es una llamada extra; se compacta con demasiada frecuencia |
| Error 400 `compaction_signature_invalid` | Se modificó el bloque `compaction` (contenido o firma) antes de reenviarlo |
| La API rechaza la petición de compactación | Se combinó `compaction` con `context_management`, o el último turno acaba en una llamada a herramienta sin resultado |
| La compactación salta a mitad de una tarea y el agente pierde el hilo | Se dispara solo por umbral, sin respetar un punto natural, y los pasos recientes se resumen |
| Se compacta «por si acaso» una conversación corta | No se midió; el coste y el riesgo superan el ahorro |
| Se podan resultados que el agente no puede volver a pedir | La poda asume que la herramienta se puede repetir |

## Buenas prácticas avanzadas

- **Poda antes que resumen.** Los resultados de herramientas suelen ser la mayor parte del historial (en la simulación, 7.508 de 7.892 tokens aproximados). Podarlos es gratis, determinista y no reescribe lo dicho; el resumen con modelo se reserva para lo que la poda no resuelve.
- **Prueba la compactación con una lista de hechos de control.** Como en la simulación: define los cinco o diez datos que no pueden perderse en tu dominio (identificadores, decisiones, importes) y comprueba tras compactar, con código, que siguen presentes. Es la única forma de detectar la pérdida silenciosa.
- **Mantén fuera de la conversación lo que debe vivir siempre.** Identificadores y acuerdos que ya existen en una fuente fiable (la base de datos del pedido, un fichero de notas) se pueden volver a consultar; lo que solo está en el chat es lo que la compactación pone en riesgo.
- **Conserva literales los últimos turnos y el *system prompt*.** El resumen sustituye lo antiguo; lo reciente es lo que el modelo está usando. Las funciones de la API ofrecen variantes para mantener turnos recientes literales (páginas *Compaction that keeps recent turns* y, con umbral, `pause_after_compaction`).
- **Guarda el historial íntegro aparte.** Aunque el modelo solo vea la versión compactada, el original sirve para auditar y depurar qué pasó y para volver a compactar con otra instrucción.
- **Escribe tu propia instrucción de resumen cuando el valor por defecto omite datos de tu dominio.** `instructions` sustituye al *prompt* por defecto entero, así que debe pedir explícitamente que no se llamen herramientas y qué campos conservar.

## Documentación oficial

Leída el 2026-11-10; los parámetros y cabeceras *beta* cambian, por lo que conviene contrastarlos con la fuente.

- [Compaction overview](https://platform.claude.com/docs/en/build-with-claude/compaction) — la tabla para elegir entre compactación a petición, por umbral y resumen propio; es el punto de entrada.
- [Compaction on demand](https://platform.claude.com/docs/en/build-with-claude/compaction-on-demand) — cabecera, parámetro `compaction`, el bucle de compactación, `instructions` y los errores; lo más detallado del mecanismo.
- [Context editing](https://platform.claude.com/docs/en/build-with-claude/context-editing) — la poda por regla (`clear_tool_uses_20250919`) y su efecto en la caché.
- [Explore the context window (Claude Code)](https://code.claude.com/docs/en/context-window) — qué sobrevive a la compactación en Claude Code y cómo actuar antes de la automática.

---

*En resumen: compactar es decidir qué se pierde antes de que lo decida el límite de la ventana; primero se podan los resultados de herramientas, y cuando hay que resumir, el resumen lleva campos fijos para que el número de pedido y las decisiones sobrevivan.*
