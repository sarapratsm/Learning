---
name: feedback-crear-tutorial-autocommit
description: La skill crear-tutorial tiene autorización permanente para hacer commit y push sin pedir confirmación
metadata: 
  node_type: memory
  type: feedback
  originSessionId: d737f85a-9f14-45c8-be84-abe42ab8881f
---

Cuando se use la skill `crear-tutorial` (repo Learning) y el trabajo termine verificado y satisfactorio, hay que hacer `git add` (selectivo, solo lo tocado por la skill, nunca `-A`/`.`), `git commit` y `git push` directamente, sin preguntar "¿hago commit y push?".

**Why:** la usuaria pidió explícitamente dejarlo definido así en `.claude/skills/crear-tutorial/SKILL.md` (paso 7 del flujo de trabajo y checklist final) tras una sesión en la que se le preguntó antes de comitear. Es una autorización estándar (equivalente a una instrucción en CLAUDE.md) que sustituye la regla por defecto de "nunca comitear sin pedirlo explícitamente" para esta skill en concreto.

**How to apply:** solo aplica al contenido generado por la skill `crear-tutorial` (fichas y READMEs de tutoriales). No autoriza a subir cambios ajenos que ya estuvieran en el working tree antes de empezar la tarea — esos se dejan sin stagear y se avisa. Si el trabajo quedó incompleto, hubo fallos, la usuaria no está conforme, o se hizo con varios subagentes en paralelo y conviene una revisión de conjunto antes de subir, no comitear y explicar por qué. Fuera del contexto de esta skill (otros repos, otras tareas), sigue rigiendo la regla general de pedir confirmación antes de comitear.
