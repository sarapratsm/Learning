# Reescritura al formato de guía completa

Documento de trabajo: plan, checklist y estado de la conversión de todas las colecciones del repositorio del formato antiguo (introducciones breves) al **formato de guía completa**.

No es una ficha de tutorial. Vive en la raíz porque tiene que estar versionado y ser fácil de encontrar entre sesiones. Cuando la conversión termine, este fichero se puede borrar.

**Última actualización:** 10 de noviembre de 2026.

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
- **Los agentes de fichas hermanas se contradicen sobre lo que dicen las otras.** El 09/11/2026, un agente de `clean-architecture` afirmó que dos fichas hermanas señalaban los fallos con una excepción porque el brief se lo indicaba, sin haberlas leído; una de las dos devolvía un enum tipado. Y el mismo enum se llamó de tres formas distintas en tres fichas. La verificación de estructura no lo detecta: hay que cruzar con `grep` los nombres compartidos y las afirmaciones sobre otras fichas, y el brief debe fijar el nombre exacto de cada tipo compartido.
- **Un brief común en un fichero ahorra repetirlo en cada agente.** El 09/11/2026 las reglas, el esqueleto, el ejemplo conductor y el mapa de la colección de `patrones-de-diseno` se escribieron una vez en un fichero del scratchpad y cada agente recibió un prompt corto con su contenido específico y la ruta del brief. Funcionó igual que el brief inline y el hilo principal envió una fracción del texto.
- **Los agentes arreglan afirmaciones falsas de las fichas antiguas si el brief les pide verificar.** Con la licencia de MediatR y la igualdad de colecciones en `record`, las fichas antiguas afirmaban cosas incorrectas; los agentes las comprobaron y las corrigieron porque el brief decía «verifícalo antes de mantenerlo». Conviene pedirlo siempre que la ficha antigua contenga un dato que cambia con el tiempo (versiones, licencias, precios).
- **El metacomentario («esta guía», «esta ficha», «este documento») reaparece aunque el brief lo prohíba.** El 09/11/2026 salieron once casos en las nueve fichas primeras de `tipos-de-apis`, casi todos al describir de dónde salen las salidas citadas («las salidas de esta guía provienen de…»). Tras cada tanda: `grep -nE '(esta|la|de la|en esta) ficha|esta guía|este documento' *.md`. La corrección es quitar la referencia al documento y dejar el dato («las salidas provienen de…»).
- **Los fragmentos de código de las fichas se abrevian respecto al código probado, y a veces con helpers inventados.** El agente de `REST` usó un atajo `Problem(400, ...)` que no existe en el servidor que compiló. Pedir en el brief que el código de la ficha sea el probado, o que lo abreviado se marque como tal, y buscar en el informe del agente las frases «recortado», «abreviado» y «ilustrativo» antes de comitear.
- **No afirmes en el brief lo que no has verificado: los agentes lo comprueban y, a veces, lo desmienten.** El 09/11/2026 el brief de `multi-tenancy` decía que `FromSqlRaw` se salta el filtro de EF y que un valor de `AsyncLocal` puede quedarse en el hilo del pool; el agente de cada ficha ejecutó el caso y ninguna de las dos cosas era cierta. Ambos informes lo señalaron y las fichas lo recogen. Conviene formular esas premisas en el brief como «comprueba si…», y cruzar después con `grep` las demás fichas de la colección que repitan la premisa errónea (una celda de `Multi-Tenancy.md` seguía citando `FromSql`).
- **Los agentes dejan servidores de prueba vivos.** Tras la tanda de `multi-tenancy` quedó un `Attack.exe` escuchando en `localhost:6417`, aunque el agente informó de haber terminado sus procesos. Tras cada tanda: `tasklist | grep -iE '\.exe'` y revisar los puertos del rango del brief. Si el sistema deniega parar un proceso, no se rodea: se deja y se avisa.
- **Un agente denegado por el sistema no lo rodea.** El 09/11/2026 el sistema denegó al agente de `gRPC` descargar y ejecutar `grpcurl`; el agente no buscó un camino alternativo y la ficha muestra solo los comandos, sin salida inventada. Es el comportamiento esperado: la ficha dice lo que no se pudo ejecutar.
- **Se puede parar una tanda a mitad sin dejar destrozos.** Al cerrar la sesión del 28/07/2026 se detuvieron cuatro agentes en marcha: tres estaban leyendo o preparando y no habían tocado nada, y el cuarto había terminado un documento válido y solo le quedaba una pasada de recorte. Ninguna ficha quedó a medio escribir. Aun así, tras parar conviene comprobar la estructura de cada fichero afectado antes de comitear.

---

## 7. Estado

**Convertidas: 205 fichas en 29 colecciones completas. Pendientes: 54 fichas en 5 colecciones.**

Llevan la sección `Documentación oficial` las 7 de `algoritmos-de-hash` y EF Core, las 10 de `autenticacion-y-autorizacion` (ya completa), las 12 de `devops/ci-cd`, las 19 de `devops/git`, las 9 de `arquitectura-de-software/clean-architecture`, las 11 de `arquitectura-de-software/patrones-de-diseno`, las 13 de `arquitectura-de-software/tipos-de-apis`, las 7 de `arquitectura-de-software/multi-tenancy` y las 8 de `lenguajes/csharp-dotnet`. El resto son anteriores a esa regla y no la tienen (ver la nota de la sección 2: no hay retrofit).

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
| `arquitectura-de-software/clean-architecture` | 9 | Cerrada el 09/11/2026. Fichas de 241 a 435 líneas con el ejemplo conductor de la tienda (`Tienda.Dominio`, `Tienda.Aplicacion`, `Tienda.Infraestructura`, `Tienda.Api`; pedido #4711). El código de cada ficha se compiló con .NET 10 y las salidas citadas son reales, salvo lo que cada ficha marca como no ejecutado (adaptadores contra SQL Server y Stripe, `HasDefaultSchema`). `Modulos-vs-Shared.md` y `Codigos-de-Resultado-por-Capa.md` perdieron el vocabulario de un proyecto privado (`BaseCommandResponse`, `Manager`, `Strategy`). `Clean-Architecture.md` señala los fallos con una excepción de negocio y `Casos-de-Uso.md` con un enum tipado; `Codigos-de-Resultado-por-Capa.md` presenta ambas opciones. El enum se llama `ConfirmarPedidoResultado` en todas las fichas, con miembros propios en cada una. Sin `Recursos didácticos` en `Capa-de-Dominio`, `Capa-de-Infraestructura`, `Inversion-de-Dependencias`, `Puertos-y-Adaptadores` y `Regla-de-Dependencia`: no había recursos que valieran la pena. |
| `arquitectura-de-software/patrones-de-diseno` | 11 | Cerrada el 09/11/2026. Fichas de 215 a 537 líneas con el ejemplo conductor de la tienda, coherente con `clean-architecture` (los puertos viven en `Tienda.Aplicacion`; las firmas de `Pedido`, `Dinero` y los ids salen de `Capa-de-Dominio.md`). Código compilado con .NET 10 y salidas reales, incluidos los fallos que ilustran cada patrón (el `IQueryable` genérico que lee 5000 filas sin `WHERE`, el evento despachado antes de guardar, la caché obsoleta, un benchmark de excepción frente a resultado). `MediatR.md` corrige la ficha antigua: afirmaba «MIT hasta la v12» y los paquetes 12.x declaran Apache-2.0; desde la 13 la licencia es RPL-1.5 o comercial (consultado el 09/11/2026; las condiciones comerciales no se pudieron confirmar). Los ejemplos de `MediatR.md` se probaron con la 12.5.0. `Value-Objects.md` corrige la afirmación de la ficha antigua de que un `record` con una colección inmutable compara por valor: con `List<T>` y con `ImmutableArray<T>` la igualdad da `False`. `Capa-de-Dominio.md` pasó a redondear con `MidpointRounding.AwayFromZero` explícito para coincidir con `Value-Objects.md`. Sin `Recursos didácticos` salvo en `Decorator`, `Domain-Driven-Design` y `Value-Objects`. |
| `arquitectura-de-software/tipos-de-apis` | 13 | Cerrada el 09/11/2026. Fichas de 211 a 583 líneas con el ejemplo conductor de la tienda (`products`, `orders`, `customers`, rutas en inglés), el mismo que `contratos-de-api`. Cada estilo se demuestra con un servidor mínimo de .NET 10 y salidas reales de `curl`: el `304` y `412` de REST, el N+1 de GraphQL (de 21 llamadas a 2 con `BatchDataLoader`), JSON-RPC 2.0 contrastado con la especificación, gRPC (192 bytes en JSON frente a 33 en protobuf), SOAP con CoreWCF y `dotnet-svcutil`, el handshake de WebSockets, la trampa de `eventType:` en `TypedResults.ServerSentEvents`, long polling con 1000 peticiones retenidas, la firma HMAC y el SSRF de los webhooks, un broker en memoria para eventos y Kiota para SDK. Los límites de uso por audiencia usan `AddRateLimiter`. Sin `Recursos didácticos` en ninguna ficha. Quedan sin probar: `grpcurl` (el sistema denegó descargar el binario; la ficha muestra solo los comandos), los efectos de proxys reales en SSE y long polling, y cualquier prueba en un navegador real. |
| `arquitectura-de-software/multi-tenancy` | 7 | Cerrada el 09/11/2026. Fichas de 217 a 598 líneas con el ejemplo conductor de una aplicación SaaS de pedidos (tenants `acme` y `globex` en `miapp.ejemplo.com`). Todo el código se ejecutó con .NET 10, EF Core 10 y SQLite, y cada ficha ilustra la fuga entre tenants desde su ángulo con salidas reales: el endpoint sin filtro, la cabecera `X-Tenant-Id` falsificada, el contexto `Singleton`, el tenant capturado en el modelo de EF, la caché sin prefijo y el borrado sin `Where`. No se ejecutó nada contra PostgreSQL ni SQL Server (esquema por tenant, Row-Level Security, `CREATE DATABASE`): las fichas lo marcan y citan la documentación del motor leída. Correcciones respecto al brief, descubiertas al ejecutar: `FromSqlRaw` sobre un `DbSet` SÍ aplica el filtro de EF (los huecos reales son `SqlQueryRaw`, `ExecuteSqlRaw` y la conexión directa); `Update`/`Attach` de una entidad desconectada con el `Id` de otro tenant escribe en la fila ajena; y un valor de `AsyncLocal` no se queda en el hilo del pool tras una tarea (la trampa real es el flujo lógico). `Aprovisionamiento-y-Migraciones.md` usa `Status` (`Provisioning`/`Active`/`Failed`) en lugar de `IsActive` y lo justifica. Sin `Recursos didácticos` en ninguna ficha. |
| `lenguajes/csharp-dotnet` | 8 | Cerrada el 09/11/2026 (las 8 fichas de `fundamentos/`, `caracteristicas-del-lenguaje/` y la raíz; los READMEs de las dos subcarpetas no se tocaron). Fichas de 346 a 572 líneas con la tienda como ejemplo conductor. Todo se ejecutó con el SDK 10.0.401 y las salidas citadas son reales, con los avisos y errores del compilador y de NuGet con su código: `NU1605`, `NU1603`, `NU1903`, `NU1004`, `NU1008`, `CS8618`, `CS0592`, `CS0579`, `CS0182`, `MSB4006`. Hallazgos al ejecutar: el SDK 10 crea `Tienda.slnx` (formato XML nuevo) y no `.sln` (`MSBuild.md` usa `--format sln`); Native AOT no se pudo probar (`Platform linker not found`) y no hay cifras de AOT; `ValidateDataAnnotations()` exige el paquete `Microsoft.Extensions.Options.DataAnnotations`; un `record` con constructor primario da `MissingMethodException` en `IOptions<T>`; `OnChange` se dispara dos veces por una escritura de fichero; sin `Dispose`, 200 000 `CancellationTokenSource` retienen unos 28 MB; la URL base de atributos del compilador de Microsoft Learn da 404. Fechas de soporte leídas el 09/11/2026: .NET 10 LTS hasta el 14/11/2028; .NET 8 y .NET 9 hasta el 10/11/2026. Sin `Recursos didácticos` salvo en `CSharp.md`, `Atributos.md`, `Atributos-Personalizados.md` y `MSBuild.md`. |
| `odoo/fundamentos` | 5 | Cerrada el 10/11/2026 (`Recordsets.md` ya estaba convertida; se reescribieron `Odoo`, `Modulos-y-Apps`, `Partner-Usuario-y-Empleado` y `Modo-Desarrollador`, de 231 a 504 líneas). **No se ejecutó ninguna instancia de Odoo**: no la hay en la máquina y no se descargó ninguna imagen. Todo se contrastó leyendo la documentación oficial y el código fuente de la rama `20.0` de `odoo/odoo` (commit `4611da6` del 10/11/2026), con comprobaciones puntuales en 19.0 y 18.0, y cada ficha cita fichero o página y versión; no hay salidas ni capturas de una instancia. Odoo 20.0 se lanzó en septiembre de 2026 según la documentación de soporte; 20.0, 19.0 y 18.0 tienen soporte estándar y 17.0 terminó el suyo en septiembre de 2026. Hallazgos que corrigen las fichas antiguas: en 20.0 `ir.model.access` e `ir.rule` se unifican en `ir.access` (`security/ir.access.csv`; en 18.0 y 19.0 siguen separados); XML-RPC está obsoleto (el servicio `db` se eliminó en 20.0 y `common`/`object` se eliminarán en 22) y la API externa actual es `/json/2`; Odoo mantiene 3 años de soporte estándar más soporte extendido de pago, no «las tres últimas versiones»; las URL `/web?debug=1` son anteriores a `/odoo?debug=1`, el modo desarrollador es de sesión de servidor y `?debug=assets, tests` con espacio se normaliza a `assets,1`; el menú Técnico no aparece por falta del modo o por falta de acceso a Ajustes; `hr.employee` hereda por delegación de `hr.version` en 20.0 y `work_contact_id` se crea automáticamente; la OCA vive en `www.odoo-community.org`, no en `oca.odoo-community.org`. La ficha antigua de personas traía contenido de un proyecto privado, retirado. Sin verificar contra una instancia: el comportamiento real de botones y menús, las funciones y precios por edición, y qué ocurre al actualizar con un fichero de permisos antiguo. Sin `Recursos didácticos` salvo en `Modulos-y-Apps`. |
| `ia/context-engineering` | 9 | Cerrada el 10/11/2026. Fichas de 275 a 476 líneas con un asistente de soporte de la tienda como ejemplo conductor. Sin llamar a ningún modelo ni API: troceadores, TF-IDF/BM25/RRF, almacén de memoria, simulaciones de ventana, compactación y aislamiento, y cálculo de ahorro de caché, todo con Python estándar y tokens aproximados como caracteres/4 (rotulado); los datos de modelos, precios, TTL, cabeceras beta y parámetros proceden de la documentación oficial de Anthropic leída el 10/11/2026 y cada ficha cita página y fecha. Los «embeddings» de las demostraciones no son de un modelo (rotulado). Resultados medidos: RAG sobre 10 preguntas con recall@1 de 0,80-0,90 según método (muestra pequeña, no concluyente); solapamiento de trozos con +11 % (10 %) a +95 % (50 %) de volumen indexado; delegar en un subagente reduce el contexto del principal de unos 10.994 a unos 581 tokens pero el total del sistema sube de 10.994 a 12.127; fuerza bruta de vecinos más cercanos con d=64: 5,1 ms (n=1 000), 49,7 ms (n=10 000), 496,5 ms (n=100 000). Hallazgos que corrigen las fichas antiguas: superar la ventana con entrada más `max_tokens` ya no da error desde Claude 4.5 (respuesta truncada con `stop_reason: model_context_window_exceeded`) y solo la entrada sola por encima de la ventana da 400; los modelos vigentes tienen ventana de 1M; hay dos cabeceras beta distintas de compactación (`compact-2026-09-04` a petición, `compact-2026-01-12` por umbral); la lectura de caché cuesta 0,05× en algunos modelos y 0,1× en el resto; un resumen vago pierde el número de pedido y las decisiones, uno estructurado no. No se ejecutó nada contra ningún modelo, reranker, base vectorial ni pgvector. Sin `Recursos didácticos` salvo en `Embeddings`, `RAG` y `Ventana`. |
| `redes/redes-y-acceso-remoto` | 11 | Cerrada el 10/11/2026. Fichas de 205 a 454 líneas con el escenario de una oficina de la tienda (red `192.168.1.0/24`, equipo `192.168.1.20`, NAS `192.168.1.50`, VPS `203.0.113.10`); README con tabla de decisión por necesidad. Se ejecutó solo lo seguro en una máquina de trabajo real: comandos de lectura, claves de prueba en carpeta aislada y servidores falsos en `127.0.0.1` (FTP en claro con credenciales visibles, mensaje de versión RFB, WebDAV con `PROPFIND` 207, listeners para mostrar puerto abierto/cerrado), y `sftp -D` contra el `sftp-server` de Git for Windows. No se ejecutó nada que cambie la red, el cortafuegos, recursos compartidos, RDP ni WireGuard. Hallazgos que corrigen las fichas antiguas: Windows Home no puede ser anfitrión de RDP; SMB 1 no viene instalado y Windows 11 24H2 exige firma SMB por defecto (rompe NAS antiguos y recursos de invitado); SFTP no es FTP sobre SSH; `scp` usa SFTP desde OpenSSH 9.0; sin chroot SFTP no restringe al usuario a su carpeta; OpenSSH 10 retiró DSA y negocia por defecto un intercambio de claves híbrido post-cuántico; RustDesk usa 21115-21117 (+21118/21119 cliente web); TeamViewer cuenta el teletrabajo como uso comercial; el cliente WebDAV de Windows (WebClient) está marcado como obsoleto desde noviembre de 2023; un RAID 5 de 4×4 TB tiene un 38 % de probabilidad de reconstruir sin error de lectura con URE 1e-14 y 91 % con 1e-15 (cálculo propio). No se ejecutó: túneles SSH, túnel WireGuard, RDP real, montajes SMB/WebDAV, NAS real, rsync. Sin verificar contra la fuente oficial: licencias de RealVNC, TightVNC, UltraVNC, FileZilla y AnyDesk, y el cifrado de AnyDesk. Sin `Recursos didácticos` en `Red-local-e-IP`, `Herramientas-de-Control-Remoto`, `VNC`, `VPN` y `NAS`. |
| `desarrollo-web/asp-net-core` | 9 | Cerrada el 10/11/2026. Fichas de 383 a 544 líneas con la API de la tienda (`Tienda.Api`, `/api/productos`, `/api/pedidos`, pedido #4711) sobre .NET 10.0.401, atacada con `curl`; README con tabla de síntomas. Hallazgos al ejecutar que corrigen las fichas antiguas: sin `[ApiController]` un cuerpo JSON válido llega vacío a la acción y responde 200; «pon las rutas específicas antes» es falso (decide la precedencia de la plantilla, no el orden de declaración) y dos plantillas con `:int` idénticas siguen siendo ambiguas; la query usa cultura invariante y el formulario la del servidor (`total=1.5` dio `15` con `es-ES`); `[BindNever]`/`[BindRequired]` no actúan sobre `[FromBody]` JSON; `[Required]` sobre `int`/`bool` deja pasar `{}` y una `string` no nulable es obligatoria sin atributo con `<Nullable>enable</Nullable>`; las Minimal APIs no validan sin `AddValidation()` (.NET 10); `IResult` y `ActionResult<T>` serializan con opciones JSON distintas (un enum sale como `"Enviado"` por una vía y `2` por la otra); en .NET 10 `Program` ya es público en proyectos web y omitir `UseAuthentication`/`UseAuthorization` sigue protegiendo (los añade el host; solo con `UseRouting()` explícito falla); con el mapeo de claims por defecto `name` no se traduce y `Identity.Name` es null; la plantilla `blazorserver` ya no existe; un `Scoped` inyectado en un `Singleton` solo falla al arrancar en Development, en Production queda congelado en silencio; `-c Release` no quita el `.pdb`; `KnownNetworks` está obsoleto (`KnownIPNetworks`); con `PublishTrimmed` los tipos anónimos no compilan y los `record` fallan en la primera respuesta JSON sin `JsonSerializerContext`; un `appsettings` no encontrado no da error. No se ejecutó: `docker build` del Dockerfile (no hay `aspnet:10.0` en la máquina y no se descargó), systemd, nginx, SIGTERM en Linux, FluentValidation, la parte interactiva de Blazor, `Asp.Versioning.Mvc` y IIS. Sin `Recursos didácticos` en `ApiController`, `Authorize`, `Model-Binding`, `Validacion-con-DataAnnotations` y `Despliegue`. |
| `testing/testing-dotnet` | 9 | Cerrada el 10/11/2026 (las cuatro primeras fichas se reescribieron el 09/11/2026). Fichas de 333 a 731 líneas con la tienda como ejemplo conductor y un proyecto xUnit 2.9.3 sobre .NET 10 ejecutado de verdad; hay un `Pedido` reducido distinto en `xUnit`/`Fixtures`/`Coverlet`/`Testcontainers`/`WebApplicationFactory` según lo que cada ficha necesita, y `NSubstitute.md` usa el del caso de uso de `clean-architecture`. Hallazgos al ejecutar: xUnit 2.9.3 no garantiza el orden de clases ni de colecciones (ocho ejecuciones, ocho órdenes) y un constructor de fixture que lanza hace fallar toda la clase; en .NET 10 `Program` ya es público en proyectos web (`PublicProgramSourceGenerator`), así que `public partial class Program` no hace falta; desde EF Core 9 cambiar de proveedor exige quitar también `IDbContextOptionsConfiguration<T>`; `ConfigureAppConfiguration` no afecta a lo que `Program.cs` lee durante la construcción (`UseSetting` sí); `ReturnsAsync` no existe en NSubstitute (`CS1061`) y `Arg.Compat` está obsoleto; `coverlet.collector` no tiene umbral (`-p:Threshold` termina en verde sin avisar) y con xUnit v3 la vía es `coverlet.mtp`; las tres herramientas de cobertura dan totales de línea distintos con el mismo código (causa sin investigar); Respawn también vacía `__EFMigrationsHistory` salvo que se excluya; `Contains("acme")` se comporta igual en SQLite y en PostgreSQL (devuelve 0 frente a "ACME"), y la diferencia real aparece con `EF.Functions.Like` (SQLite devuelve 1, PostgreSQL 0). Con Docker Desktop (29.5.3) se ejecutó PostgreSQL 16 real; el arranque medido fue de 2,8-3,0 s por contenedor y 12,7 s para 10 tests con uno compartido frente a 42,3 s con uno por test. No se ejecutó: Docker parado, Ryuk limpiando huérfanos, xUnit v3 (salvo en `Coverlet.md`), Stryker.NET y el YAML de GitHub Actions. Corregido de paso `devops/docker/Testcontainers.md`: `WithReuse` funcionó sin `testcontainers.reuse.enable`. Sin `Recursos didácticos` en `Fixtures` ni `Testcontainers`. |
| `testing/tdd-bdd-sdd` | 3 | Creada el 30/10/2026 directamente en formato nuevo (no es una conversión): `TDD.md`, `BDD.md` y `SDD.md` (544-721 líneas), con el ejemplo conductor del cupón de descuento en C#/.NET. `SDD.md` remite a `ia/ingenieria-con-llms/Desarrollo-Dirigido-por-Especificacion.md` para el flujo con agentes. |

### Pendiente

Orden propuesto: por valor de uso y por dependencias entre colecciones. Las pequeñas primero dentro de cada categoría, porque cerrar una colección entera permite comitear.

| # | Colección | Fichas | Avisos |
|---:|---|---:|---|
| 1 | `desarrollo-web/de-wpf-a-web` | 15 | `Entity-Framework-Core.md` salió de aquí a `bases-de-datos/acceso-a-datos-dotnet` el 28/07/2026; el README la enlaza en su nueva ubicación. |
| 2 | `desarrollo-web/frontend-react` | 28 | ⚠️ La más grande. La skill citaba su `README.md` como modelo de índice y `clsx.md` como ejemplo; ya no (ver sección 8). |
| 3 | `odoo/busqueda-y-filtros` | 4 | |
| 4 | `odoo/pruebas-seguras` | 5 | |
| 5 | `odoo/configuracion-parametros` | 6 | |

> `odoo/notificaciones` no está en esta lista: se creó directamente en formato nuevo (no es una conversión), y está incompleta a propósito — le faltan 3 fichas propias, detalladas en su README.

---

## 8. Asuntos abiertos

- **`ia/ingenieria-con-llms/`: resuelto.** Tiene README-índice, está enlazada desde `ia/README.md` y la descripción de la categoría IA en el README raíz ya la incluye. El solapamiento con `ia/context-engineering` se trató al convertirla: sus fichas enlazan a las de `ingenieria-con-llms` en vez de repetirlas.
- **Referencias de tono en la skill: resueltas** el 28/07/2026. `SKILL.md` cita ahora `devops/despliegue-en-vps/UFW.md` (tono), `bases-de-datos/acceso-a-datos-dotnet/Dapper.md` (guía completa con tablas de decisión y errores frecuentes) y `devops/despliegue-en-vps/README.md` (modelo de índice), las tres en formato nuevo. La nota de «calibra el tono, no la extensión» se sustituyó por un aviso de que en el repositorio aún queda contenido en formato antiguo y no sirve como referencia de profundidad. Ese aviso se puede borrar cuando la conversión termine.
- **`ia/ingenieria-con-llms/Coste-Latencia-y-Fiabilidad.md`: precios por revisar.** El 10/11/2026 `ia/context-engineering/Prompt-Caching.md` leyó la tabla de precios oficial y no coincide con lo que dice esa ficha para `Sonnet 5` (3,00 $ de entrada) ni con su «~0,1×» de lectura de caché (0,05× en algunos modelos); no se contrastó modelo a modelo, por lo que puede ser una diferencia de modelo y no un error. Pendiente de comprobar contra la página de precios vigente.
- **Fin de línea.** El repositorio convierte LF a CRLF al indexar, así que tras comitear los ficheros pueden reaparecer como modificados. Es ruido, no un cambio real: se confirma con `git diff --ignore-all-space`.
- **Al terminar la conversión**, revisar el README raíz: ya no describe la colección como «guías introductorias», pero conviene una lectura final de coherencia.
