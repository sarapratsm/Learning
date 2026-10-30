# Reescritura al formato de guía completa

Documento de trabajo: plan, checklist y estado de la conversión de todas las colecciones del repositorio del formato antiguo (introducciones breves) al **formato de guía completa**.

No es una ficha de tutorial. Vive en la raíz porque tiene que estar versionado y ser fácil de encontrar entre sesiones. Cuando la conversión termine, este fichero se puede borrar.

**Última actualización:** 30 de octubre de 2026.

---

## 1. Qué cambia y por qué

El repositorio se escribió como colección de **introducciones breves**: fichas de 60-120 líneas con un índice de secciones cerrado, pensadas para leerse en pocos minutos y quedarse con "lo mínimo para no perderse".

La decisión nueva es que sean **guías completas**: la ficha sigue empezando por una introducción accesible, pero a partir de ahí desarrolla el tema con la profundidad que pida, con el objetivo de que quien la lea acabe sabiendo usar la tecnología sin tener que buscar lo importante en otro sitio.

Los tres cambios concretos:

| | Antes | Ahora |
|---|---|---|
| Extensión | 60-120 líneas | La que pida el tema (en la práctica, 300-500) |
| Índice de secciones | Cerrado, sin inventar secciones | Apertura y cierre fijos, desarrollo libre |
| Ejemplos de código | Snippet suelto | Ejemplo **guiado**: introducción → código → qué hace y qué devuelve |

La skill `crear-tutorial` (en `~/.claude/skills/crear-tutorial/SKILL.md`) ya está actualizada con estas reglas y es la referencia normativa. Este documento no la sustituye: organiza su aplicación al contenido que ya existía.

> **Nota del 14/09/2026:** la skill se suavizó para consumir menos tokens: ya no exige que la extensión llegue a 300-500 líneas ni que cada opción secundaria lleve su propio ejemplo guiado (el ejemplo guiado se reserva para el uso habitual; ver el principio 5 y 6 de la skill). El contrato de esta sección sigue siendo válido en lo estructural (esqueleto, reglas duras), pero la cifra de extensión de la tabla de abajo y la exigencia de "todo párrafo con snippet" quedan desde esta fecha por debajo de lo que dicta la skill actual — prevalece la skill.

---

## 2. El contrato de formato

Esqueleto obligatorio. Apertura y cierre fijos, desarrollo intermedio libre.

```markdown
# <Título>

## ¿Qué es?                            ← FIJA. Una o dos frases.
## ¿Por qué existe?                    ← FIJA. El problema que resuelve + blockquote de analogía.
## ¿Cuándo y para qué se usa?           ← Recomendada, no obligatoria.

## <las secciones que pida el tema>     ← LIBRES. Tantas como haga falta,
## <...>                                   ordenadas como progresión de aprendizaje.

## Buenas prácticas avanzadas           ← FIJA. 3-6 puntos, específicos y accionables.
## Documentación oficial                ← FIJA desde el 28/07/2026. Fuentes canónicas.
## Recursos didácticos                  ← FIJA. Omitible solo si no hay nada que valga la pena.

---

*En resumen: <una frase memorable>.*  ← FIJA.
```

> **`Documentación oficial` es una sección nueva** (28/07/2026), añadida porque los enlaces canónicos quedaban mezclados con los didácticos y pasaban desapercibidos. La división: `Documentación oficial` son las fuentes canónicas (documentación del proyecto, especificación o RFC, *cheat sheet* normativa, repositorio), de 1 a 4 enlaces y cada uno con una línea que diga qué parte merece la pena y cuándo ir ahí; `Recursos didácticos` es todo lo que ayuda a aprender pero no es la fuente. Un enlace no va en las dos.
>
> **Decisión explícita: no hay retrofit.** La sección se aplica al contenido escrito de aquí en adelante. Las fichas ya convertidas se quedan sin ella; están listadas en la tabla de la sección 7 y se puede hacer una pasada más adelante si se quiere, pero no es un requisito para cerrar la conversión.

### Reglas duras

- **Español** en la prosa. Términos técnicos consolidados, comandos y código en su idioma original.
- **Audiencia: backend junior-medio.** Programa a diario y puede conocer partes del stack, pero es nuevo en la tecnología concreta. No se explica qué es una API; sí se definen los términos propios antes de usarlos.
- **Género neutro** para el lector; masculino genérico solo si el neutro queda forzado.
- **Autónoma.** Sin referencias a proyectos, módulos ni dominios privados. Escenarios genéricos y reconocibles.
- **Todo párrafo que hable de código lleva su ejemplo guiado.** Regla práctica: si un párrafo habla de código y no hay snippet cerca, falta el snippet.
- **Muestra la salida real** cuando aporte (respuesta JSON, log de consola, mensaje de error concreto) y usa contrastes ✅/❌.
- **Prohibido el relleno:** repetir lo ya dicho, parafrasear la documentación oficial, enumerar la API entera sin explicar nada.
- **Sin banners de metacomentario** tipo `> 🧭 Tutorial recomendado de forma proactiva…`. Son contexto del repositorio, no de la tecnología.
- **Nombres de ejemplo genéricos y coherentes** dentro de la misma ficha y, a ser posible, de la misma colección. Nunca `foo`/`bar`.

### Lo que aporta valor de verdad

Lo que diferencia una ficha convertida buena de una simplemente más larga:

- Una **tabla de decisión** para las disyuntivas reales del tema ("¿cola o topic?", "¿incrustar o referenciar?").
- Una sección de **errores frecuentes** con formato síntoma → causa.
- El **cálculo o la salida concreta** que hace tangible un peligro abstracto (la explosión de cardinalidad con números, la media que esconde el p99).
- **Cuándo NO usar** la tecnología.
- Los puntos de «Buenas prácticas avanzadas» pasan el criterio: *¿esto lo sabe solo quien de verdad domina el tema?*

---

## 3. Convenciones transversales

**Ejemplo conductor por colección.** Todas las fichas de una colección comparten escenario y nombres, para que las piezas encajen entre documentos. El que se está usando en `devops/`:

> Tienda online. Pedido **#4711**. Servicios `pedidos`, `pagos`, `inventario`, `emails`. VPS en `203.0.113.10`, dominio `tienda.ejemplo.com`, usuario de despliegue `deployer`.

**READMEs-índice.** Los escribe siempre la persona (o el hilo principal), nunca un subagente: son lo que da coherencia a la colección. Además del orden de lectura, funcionan muy bien con tablas operativas al final (comandos de verificación, dónde se aplica cada cambio, los errores que se pagan caros).

**Enlaces.** Toda ruta relativa debe resolver, mayúsculas incluidas. Verificar antes de comitear.

**Un commit por colección**, con el detalle de qué cobertura se ha añadido, no solo "reescribe X".

---

## 4. Procedimiento por colección

Checklist repetible. Marca una copia de esto por cada colección que abordes.

- [ ] **1. Leer la colección entera** (todas las fichas y su README) para conservar sus decisiones de contenido y su analogía si es buena.
- [ ] **2. Decidir el ejemplo conductor** y anotarlo, para que todas las fichas lo compartan.
- [ ] **3. Esbozar el índice de secciones** de cada ficha antes de redactar. Si un tema es inabarcable, plantear partirlo en varias fichas enlazadas.
- [ ] **4. Repartir en subagentes** (ver sección 6) con el brief completo: contrato de formato + ejemplo conductor + contenido a cubrir + enlaces a verificar.
- [ ] **5. Escribir el README-índice** a mano mientras trabajan los agentes.
- [ ] **6. Esperar la notificación de fin de cada agente.** No mirar el tamaño del fichero y asumir que ha terminado.
- [ ] **7. Verificar** (comandos en la sección 5): estructura, enlaces, banners, fugas de datos privados.
- [ ] **8. Leer una ficha completa** de las que escribió un agente. La verificación automática comprueba forma, no calidad.
- [ ] **9. Actualizar los índices superiores:** README de la categoría y README raíz si la descripción se queda corta.
- [ ] **10. Commit y push** de la colección.
- [ ] **11. Actualizar la tabla de estado** de este documento.

---

## 5. Comandos de verificación

Estructura de todas las fichas de una colección:

```bash
cd ~/GitRepos/Learning
COL=devops/observabilidad
for f in $COL/*.md; do b=$(basename "$f"); [ "$b" = "README.md" ] && continue
  printf "%-40s q:%s p:%s bp:%s r:%s res:%s  %s líneas\n" "$b" \
    "$(grep -c '^## ¿Qué es?$' "$f")" "$(grep -c '^## ¿Por qué existe?$' "$f")" \
    "$(grep -c '^## Buenas prácticas avanzadas$' "$f")" "$(grep -c '^## Recursos didácticos$' "$f")" \
    "$(grep -c '^\*En resumen:' "$f")" "$(wc -l < "$f")"
done
```

Todos los enlaces relativos del repositorio:

```bash
total=0; roto=0
for f in $(find . -name "*.md" -not -path "./.git/*"); do d=$(dirname "$f")
  while read -r l; do [ -z "$l" ] && continue; total=$((total+1))
    [ -e "$d/$l" ] || { roto=$((roto+1)); echo "ROTO ${f#./} -> $l"; }
  done < <(grep -oE '\]\([^)]+\)' "$f" | sed -E 's/^\]\(//; s/\)$//' | grep -vE '^(https?:|#|mailto:)' | sed 's/#.*//')
done
echo "$total enlaces, $roto rotos"
```

Banners de metacomentario pendientes y bloques de código sin cerrar:

```bash
grep -rl '🧭' --include="*.md" .
for f in $(find . -name "*.md" -not -path "./.git/*"); do
  n=$(grep -c '^```' "$f"); [ $((n % 2)) -ne 0 ] && echo "IMPAR $f ($n)"
done
```

---

## 6. Trabajar con subagentes

Lo que funciona, aprendido en la primera tanda:

- **3-4 agentes en paralelo por colección**, uno por ficha. Más agentes no va más rápido y complica la verificación.
- **El brief tiene que ser autosuficiente:** contrato de formato completo, ejemplo conductor, lista de contenido a cubrir, lista de enlaces a verificar con `ls` antes de usarlos, y una ficha ya convertida como referencia de tono.
- **Indicar explícitamente qué NO debe cubrir**, para que no se solape con la ficha vecina.
- **El README lo escribe el hilo principal.** Un agente no ve la colección completa.
- **Esperar la notificación de fin. No hay atajo.** Consultar el fichero y deducir que ha acabado produce commits de estados intermedios. Pasó en la primera tanda y **volvió a pasar el 28/07/2026** con `algoritmos-de-hash/Hashing-En-CSharp.md`: el documento estaba completo y coherente (todas las secciones fijas, delimitadores pares, cierre presente), se verificó a conciencia y se comiteó — y el agente siguió trabajando después con una pasada de compresión de párrafos. Hubo que arreglarlo con un commit de seguimiento. La lección afinada: **verificar la estructura no distingue «terminado» de «casi terminado»**, porque el agente llega a un documento válido antes de dar el último repaso. Solo la notificación lo distingue.
- **Contar con errores 529 del API.** En la primera tanda, 6 de 8 agentes terminaron con `529 Overloaded`, todos en el paso final de recortar longitud, después de haber producido un documento completo y coherente. Ante un fallo: verificar estructura (secciones fijas, delimitadores de código pares, cierre presente) antes de asumir que hay que rehacerlo. Uno de los ocho murió antes de escribir nada y se reescribió a mano.
- **La extensión se va por encima del rango indicado, y suele estar justificada.** En la segunda tanda se pidieron 250-350 líneas y salieron entre 327 y 519, sin relleno: cuando el brief lista 14-16 bloques de contenido y cada uno pide su snippet o su tabla, la aritmética no da para menos. Dos consecuencias prácticas: **el rango del brief funciona como orientación, no como límite**, y si de verdad quieres una ficha corta hay que recortar la lista de contenido, no repetir el número. No pidas a un agente que recorte al final: es justo donde murieron los de la primera tanda.
- **Avisar al agente de que verá cambios ajenos en `git status`.** Con varios agentes en paralelo, cada uno ve los ficheros de los demás como modificados y lo reporta como anomalía. No es un problema, pero ensucia el informe final.
- **Pedirle que escriba pronto y refine con ediciones, no que vuelque el documento al final.** El 28/07/2026 un agente murió con `Connection closed mid-response` justo después de leer las referencias y antes de escribir una sola línea: se perdió todo su trabajo. Los que escriben temprano y van editando sobreviven a un fallo tardío con un documento aprovechable. Ante un agente caído, lo primero es mirar el fichero: si sigue en su versión original, se relanza sin más.
- **Dar a cada agente su propia carpeta de trabajo en el scratchpad.** El 30/10/2026, dos agentes de la tanda de `devops/git` usaron `scratchpad/lab/tienda` para sus repositorios de prueba: uno ejecutó `rm -rf lab` y borró el del otro, y un tercero lanzó `git rebase` sobre un repositorio ajeno (sin efecto, el hash no cambió). Solo se perdieron repositorios de prueba, pero el brief debe indicar un directorio distinto por agente (por ejemplo `scratchpad/<ficha>/`).
- **Se puede parar una tanda a mitad sin dejar destrozos.** Al cerrar la sesión del 28/07/2026 se detuvieron cuatro agentes en marcha: tres estaban leyendo o preparando y no habían tocado nada, y el cuarto había terminado un documento válido y solo le quedaba una pasada de recorte. Ninguna ficha quedó a medio escribir. Aun así, tras parar conviene comprobar la estructura de cada fichero afectado antes de comitear.

---

## 7. Estado

**Convertidas: 111 fichas en 19 colecciones. Pendientes: 148 fichas en 15 colecciones.**

Llevan la sección `Documentación oficial` las 7 de `algoritmos-de-hash` y EF Core, las 10 de `autenticacion-y-autorizacion` (ya completa), las 12 de `devops/ci-cd` y las 19 de `devops/git`. El resto son anteriores a esa regla y no la tienen (ver la nota de la sección 2: no hay retrofit).

### `seguridad/autenticacion-y-autorizacion`: completa (14/09/2026)

Las cuatro fichas que quedaban (`JWT-Refresh.md`, `JWT-Refresh-vs-Tokens-Opacos.md`, `RBAC-y-Claims.md`, `ACL.md`) y el `README.md` (quitado el banner 🧭) se convirtieron con una pasada ligera en vez de la reescritura completa que llevaron las seis primeras: su contenido ya era bueno (los apartados «Lo mínimo que necesitas saber» y «Lo que NO hace» se reorganizaron en secciones `##` propias y se plegaron en la prosa, respectivamente), así que se ajustó a la skill suavizada del 14/09/2026 en vez de expandir a 300-500 líneas. `RBAC-y-Claims.md` se alineó con el ejemplo conductor (`Administradora`/`Editor` → `Cliente`/`Empleado`/`Administrador`). Todas quedaron entre 75 y 95 líneas, con `Documentación oficial` añadida a las cuatro.

### Hecho

| Colección | Fichas | Notas |
|---|---:|---|
| `devops/despliegue-en-vps` | 14 | Creada ya en formato nuevo. Define el ejemplo conductor de `devops/`. |
| `devops/mensajeria-asincrona` | 5 | Código de RabbitMQ actualizado a la API asíncrona 7.x. |
| `devops/observabilidad` | 11 | Añadido `¿Qué es?` a `ILogger-T` y `log4net`; y BBPP + Recursos a `log4net`. |
| `devops/docker` | 3 | El README delimita la frontera con `despliegue-en-vps`. |
| `bases-de-datos/mongodb` | 1 | |
| `bases-de-datos/postgresql` | 1 | |
| `seguridad/secretos-en-llamadas-salientes` | 1 | |
| `devops/github-organizaciones` | 5 | Creada ya en formato nuevo, en una sesión aparte. |
| `ia/ingenieria-con-llms` | 10 | Creada ya en formato nuevo. Ya tiene README-índice, enlazado desde `ia/README.md` (ver sección 8). |
| `bases-de-datos/acceso-a-datos-dotnet` | 3 | Al convertir `Dapper.md` se actualizaron las referencias de tono de `SKILL.md`. `Entity-Framework-Core.md` se **movió aquí** desde `desarrollo-web/de-wpf-a-web` el 28/07/2026: es una tecnología de acceso a datos y la colección no estaba completa sin el ORM. Es la única ficha con la sección `Documentación oficial`. |
| `seguridad/gestion-de-secretos-en-desarrollo` | 3 | |
| `bases-de-datos/caching` | 4 | |
| `bases-de-datos/migraciones-de-esquema` | 5 | |
| `seguridad/autenticacion-y-autorizacion` | 10 | Cerrada el 14/09/2026. Detalle arriba, en «completa (14/09/2026)». |
| `herramientas/correo-transaccional` | 1 | Cerrada el 14/09/2026. El contenido ya era bueno (una sola ficha, sin banner): se reorganizó "Lo mínimo que necesitas saber" en secciones `##` propias, se plegó "Lo que NO hace" en la prosa y se añadió `Documentación oficial` ([MailKit](https://mimekit.net/docs/html/T_MailKit_Net_Smtp_SmtpClient.htm), [dmarc.org](https://dmarc.org/overview/)) y `Recursos didácticos` ([mail-tester.com](https://www.mail-tester.com/)). 154 → 144 líneas: la reorganización no necesitó añadir contenido nuevo. |
| `testing/e2e` | 1 | Cerrada el 14/09/2026. Mismo tratamiento que `correo-transaccional`: reorganización, no expansión (178 → 174 líneas). Se detectó y quitó un enlace roto que ya traía la ficha antigua, `try.playwright.dev` (el dominio ya no resuelve, `NXDOMAIN`); no se sustituyó por otro porque no había una URL verificada a mano para reemplazarlo. Añadida `Documentación oficial` (docs de Playwright y su página de Best Practices). |
| `devops/ci-cd` | 12 | Cerrada el 30/10/2026. Reescritura completa de las 12 fichas (118-418 líneas) con el ejemplo conductor de `devops/`; las tres plataformas (`GitHub-Actions`, `GitLab-CI`, `Jenkins`) comparten un pipeline equivalente y una tabla de equivalencia de vocabulario. En `Release-por-Tag.md` se sustituyó el rollback con `git push --force-with-lease` (no despliega nada) por `workflow_dispatch` con el tag a desplegar. |
| `devops/git` | 19 | Cerrada el 30/10/2026. Las salidas de comandos se capturaron con Git 2.54 en repositorios temporales. `GitHub-Actions.md` queda como introducción breve del vínculo Git↔Actions y remite a la ficha de `ci-cd`. `Tokens-de-Acceso-en-Remotos.md` pasó de 41 a 172 líneas y ya no recomienda incrustar el token en la URL. |
| `testing/tdd-bdd-sdd` | 3 | Creada el 30/10/2026 directamente en formato nuevo (no es una conversión): `TDD.md`, `BDD.md` y `SDD.md` (544-721 líneas), con el ejemplo conductor del cupón de descuento en C#/.NET. `SDD.md` remite a `ia/ingenieria-con-llms/Desarrollo-Dirigido-por-Especificacion.md` para el flujo con agentes. |

### Pendiente

Orden propuesto: por valor de uso y por dependencias entre colecciones. Las pequeñas primero dentro de cada categoría, porque cerrar una colección entera permite comitear.

| # | Colección | Fichas | Avisos |
|---:|---|---:|---|
| 1 | `arquitectura-de-software/clean-architecture` | 9 | |
| 2 | `arquitectura-de-software/patrones-de-diseno` | 11 | 9 ficheros con banner 🧭. Carpeta renombrada de `patrones-de-diseño` el 27/07/2026. |
| 3 | `arquitectura-de-software/tipos-de-apis` | 13 | |
| 4 | `arquitectura-de-software/multi-tenancy` | 7 | |
| 5 | `lenguajes/csharp-dotnet` (+ 2 subcarpetas) | 8 | Tiene subcarpetas con README propio. |
| 6 | `testing/testing-dotnet` | 9 | Se cruza con `docker/Testcontainers.md`, ya convertida. |
| 7 | `desarrollo-web/asp-net-core` | 9 | |
| 8 | `desarrollo-web/de-wpf-a-web` | 15 | `Entity-Framework-Core.md` salió de aquí a `bases-de-datos/acceso-a-datos-dotnet` el 28/07/2026; el README la enlaza en su nueva ubicación. |
| 9 | `desarrollo-web/frontend-react` | 28 | ⚠️ La más grande. La skill citaba su `README.md` como modelo de índice y `clsx.md` como ejemplo; ya no (ver sección 8). |
| 10 | `redes/redes-y-acceso-remoto` | 11 | `SSH.md` y `VPN.md` se cruzan con `despliegue-en-vps`, ya convertida. |
| 11 | `odoo/fundamentos` | 4 | |
| 12 | `odoo/busqueda-y-filtros` | 4 | |
| 13 | `odoo/pruebas-seguras` | 5 | |
| 14 | `odoo/configuracion-parametros` | 6 | |
| 15 | `ia/context-engineering` | 9 | Revisar solapamiento con `ia/ingenieria-con-llms`, ya en formato nuevo. |

> `odoo/notificaciones` no está en esta lista: se creó directamente en formato nuevo (no es una conversión), y está incompleta a propósito — le faltan 3 fichas propias, detalladas en su README.

---

## 8. Asuntos abiertos

- **`ia/ingenieria-con-llms/`: resuelto.** Tiene README-índice, está enlazada desde `ia/README.md` y la descripción de la categoría IA en el README raíz ya la incluye. Queda revisar si se solapa con `ia/context-engineering` (sigue en la tabla de pendientes, último punto).
- **Referencias de tono en la skill: resueltas** el 28/07/2026. `SKILL.md` cita ahora `devops/despliegue-en-vps/UFW.md` (tono), `bases-de-datos/acceso-a-datos-dotnet/Dapper.md` (guía completa con tablas de decisión y errores frecuentes) y `devops/despliegue-en-vps/README.md` (modelo de índice), las tres en formato nuevo. La nota de «calibra el tono, no la extensión» se sustituyó por un aviso de que en el repositorio aún queda contenido en formato antiguo y no sirve como referencia de profundidad. Ese aviso se puede borrar cuando la conversión termine.
- **Fin de línea.** El repositorio convierte LF a CRLF al indexar, así que tras comitear los ficheros pueden reaparecer como modificados. Es ruido, no un cambio real: se confirma con `git diff --ignore-all-space`.
- **Al terminar la conversión**, revisar el README raíz: ya no describe la colección como «guías introductorias», pero conviene una lectura final de coherencia.
