# Preferencias de usuario — Sara Prats

> Instrucciones de ámbito **global**: aplican a todas las sesiones y a todos los proyectos.
> Lo específico de un proyecto vive en el `CLAUDE.md` de su repositorio y en su memoria.

---

## Contexto autocontenido en los documentos que escribas

**No des por sabido en un documento el contexto que existe en la conversación.**

Cuando escribas documentación —specs, ADRs, planes, tableros, guías, READMEs, comentarios de código que expliquen una decisión—, quien la lea puede ser otra persona, o tú misma dentro de seis meses, o un agente que abra el fichero por la mitad. **Ninguno de ellos estuvo en la sesión en la que se escribió.**

En la práctica:

- **Nombra, no numeres.** «La inspiración», «la operación de edición», no «la 1» y «la 3». Si el orden importa, el número acompaña al nombre: *«1.ª inspiración»*.
- **Cada sección debe poder leerse suelta.** Si una sección larga se apoya en algo definido veinte párrafos antes, repite el mínimo imprescindible o enlaza al sitio exacto. **Eso se consigue repitiendo el dato, no anunciando que lo repites.**
- **Nada de «lo que hablamos», «el hallazgo de antes», «como comentamos».** El documento no recuerda la conversación.
- **El documento describe el estado actual, como si fuera la primera versión.** Nada de historial de cambios dentro del documento: ni «cambios del día tal», ni texto tachado, ni «decidido el…», ni «antes era…», ni quién propuso qué. Cuando algo cambia de significado (un término, una numeración, un estado), reescribe el documento entero con el significado nuevo, de modo que **ningún párrafo conserve el sentido viejo**. El historial vive en git o en el chat, no en el texto.
- **No rellenes huecos con contexto plausible.** Si no sabes quién aprueba algo, quién decidió algo o de dónde sale un dato, déjalo abierto y dilo. Un documento que afirma algo que nadie ha dicho es peor que uno que no lo menciona.
- **Autocontenido en el CONTENIDO, no en avisos sobre sí mismo. Nada de metacomentario.** El documento no explica cómo hay que leerlo, ni a quién va dirigido, ni por qué está ordenado así, ni qué parte es importante. Prohibido en títulos y en el cuerpo: *«El problema, para quien no estuvo»* (es «El problema»), *«esto es el corazón del diseño, no un detalle»*, *«los dos ejemplos están puestos a propósito juntos»*, *«lo pongo aquí para que no haya dos copias»*, *«conviene decir por qué, porque si no alguien leerá esto y no lo entenderá»*. **La prueba: si al borrar la frase no se pierde ningún dato, la frase sobraba.** Si algo importa, se nota porque está escrito, no porque se avise de que importa.
  **Lo que sí se queda**, porque informa: las advertencias de dato sin verificar, la procedencia de una cifra o de una observación (con su fecha, p. ej. «observado el 2026-10-21») y las decisiones abiertas, listadas como pendientes.

**Por qué está escrito esto.** Salió de un caso real: un ADR pasó de describir dos operaciones a describir tres, y quedaron referencias del tipo «el orden es 1 → 2 → 3» sin decir en ningún sitio cercano qué era cada número. Peor aún, **el mismo número significaba dos cosas distintas en dos partes del mismo documento**, sin ningún aviso. Cuando se escribe desde dentro de la conversación, esas referencias parecen obvias; al día siguiente no lo son.

**Y por qué se añadió la regla del metacomentario (2026-09-09).** Esta sección decía —y sigue diciendo— que quien lea el documento «no estuvo en la sesión en la que se escribió». Claude convirtió esa frase en **decoración de los títulos**, escribiendo cosas como `## 1. El problema, para quien no estuvo`, y sembró el cuerpo de avisos sobre el propio texto. Sara lo cortó así: *«intentemos no poner de más ni de menos; "para quien no estuvo" no aporta nada aparte de confusión»*. La regla pedía que el documento **se entienda** sin la conversación; no pedía **hablar de** la conversación ni del documento. Cumplirla anunciándola es incumplirla: añade ruido y confunde.

---

## Navegador (Chrome): no cierres las pestañas

**No cierres con `tabs_close_mcp` las pestañas que abras con las herramientas de Chrome.** Déjalas abiertas en la página relevante y di cuál es. Cierra una pestaña solo si Sara lo pide.

Esto sustituye a la pauta por defecto de limpiar las pestañas propias al terminar. Origen (2026-10-22): al consultar pedidos de la base de pruebas de Odoo, Claude cerró las pestañas al acabar y Sara pidió: *«no cierres la ventana de chrome porfa»*.

---

## Al terminar una tarea, deja el estado por escrito donde toque

Si el trabajo modifica el estado de un proyecto (una decisión tomada, una medida obtenida, algo que resultó ser falso), **el sitio donde vive ese estado es el repositorio**, no el chat ni solo la memoria. La conversación se pierde; el documento se lee.
