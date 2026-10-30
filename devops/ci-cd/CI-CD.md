# CI/CD

## ¿Qué es?

CI/CD es la práctica de **automatizar el camino entre escribir código y ponerlo en producción**. Las siglas significan *Continuous Integration* (Integración Continua) y *Continuous Delivery* o *Continuous Deployment* (Entrega o Despliegue Continuo). Una herramienta —GitHub Actions, GitLab CI, Jenkins— vigila el repositorio y, cada vez que el código cambia, repite siempre los mismos pasos: compilar, probar, empaquetar y, si procede, desplegar.

## ¿Por qué existe?

Sin automatizar, publicar el pedido #4711 de una tienda online en producción significa que alguien, a mano: baja la última versión del código, ejecuta los tests, compila, sube el resultado al VPS y reinicia el servicio. Cada paso es una oportunidad de olvidar algo o de hacerlo distinto a la vez anterior («en mi máquina funcionaba»). Y cuanto más doloroso es publicar, menos se publica: los cambios se acumulan, cada entrega es mayor y, por tanto, más arriesgada.

CI/CD invierte esa espiral: un robot ejecuta siempre la misma receta en cuanto hay un cambio, así que publicar deja de ser un evento y pasa a ser rutina.

> Si vienes del mundo de la cocina: CI/CD es una cadena de montaje. Se dejan los ingredientes (el código) y la cadena cocina, emplata y sirve siempre igual, sin que se olvide la sal.

## ¿Cuándo y para qué se usa?

En casi cualquier proyecto con más de una persona o que se actualice con frecuencia. Con la tienda online de ejemplo (servicios `pedidos`, `pagos`, `inventario` y `emails`, desplegados en un VPS `203.0.113.10` bajo `tienda.ejemplo.com`):

- Cada *pull request* ejecuta los tests de los servicios afectados antes de que nadie la revise.
- Cada fusión a `main` genera una imagen y la despliega en un entorno de pruebas.
- Cada etiqueta de versión (`v1.4.0`) publica la versión en producción.

El objetivo es siempre el mismo: enterarse de los errores en minutos y no en producción, y entregar con cambios pequeños y frecuentes.

## Las tres siglas, por separado

| Término | Qué automatiza | Quién decide el último paso |
|---|---|---|
| **Integración Continua (CI)** | Cada cambio se integra en la rama común y se compila y prueba automáticamente | El robot: si falla, el cambio no entra |
| **Entrega Continua (Continuous Delivery)** | Además, deja un artefacto listo para producción en todo momento | Una persona pulsa el botón de desplegar |
| **Despliegue Continuo (Continuous Deployment)** | Además, despliega a producción sin intervención | Nadie: si todo está verde, se publica |

La diferencia entre las dos «CD» es solo quién pulsa el botón final. Entrega continua exige que *se pueda* desplegar en cualquier momento; despliegue continuo exige además confiar tanto en los tests que se despliega sin mirar.

## El recorrido de un cambio

Un cambio recorre cuatro fases, y cada una es un punto donde el robot puede pararlo:

1. **Disparador.** Ocurre algo en Git (`push`, abrir una *pull request*, crear una etiqueta) y la herramienta lo detecta.
2. **Integrar y probar (CI).** Descarga el código, instala dependencias, compila, pasa el linter y los tests.
3. **Empaquetar.** Genera el artefacto desplegable: un binario, un `.zip` o, lo más habitual, una imagen de contenedor.
4. **Entregar o desplegar (CD).** Publica el artefacto en el entorno que toque.

Un ejemplo mínimo con GitHub Actions, que cubre las dos primeras fases para el servicio `pedidos`:

```yaml
name: ci
on:
  pull_request:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npm test
```

El bloque `on` dice cuándo se ejecuta: en cada *pull request* y en cada `push` a `main`. El job `test` arranca una máquina Ubuntu limpia, descarga el código y ejecuta `npm ci` y `npm test`. Si cualquiera de los dos devuelve un código de salida distinto de 0, el job falla y la *pull request* muestra una cruz roja. Cómo se escribe esto con todo detalle está en [GitHub Actions](GitHub-Actions.md); cómo se organizan jobs y fases, en [Pipeline](Pipeline.md).

La fase de despliegue, en su forma más simple, es una conexión SSH al VPS:

```bash
ssh deployer@203.0.113.10 "cd /srv/tienda && docker compose pull && docker compose up -d"
```

Qué hace: entra como `deployer`, descarga las imágenes nuevas y reinicia solo los contenedores que cambiaron. Las alternativas para hacerlo sin cortes y con vuelta atrás están en [Estrategias de despliegue](Estrategias-de-Despliegue.md), y cómo guardar la clave SSH sin ponerla en el repositorio, en [Secrets y variables](Secrets-y-Variables.md).

## Qué nivel de automatización elegir

| Situación | Punto de partida razonable |
|---|---|
| Proyecto nuevo, sin tests todavía | Solo CI: compilar y ejecutar lo que haya en cada *pull request* |
| Tests fiables, un entorno de pruebas | CI + despliegue automático a pruebas |
| Producción con clientes reales y despliegues semanales | Entrega continua: artefacto listo, despliegue con aprobación manual |
| Tests muy completos, cambios pequeños, vuelta atrás en un comando | Despliegue continuo |
| Cumplimiento normativo que exige aprobación documentada | Entrega continua con aprobación explícita; el botón humano es un requisito, no un fallo |

Se avanza por escalones: cada nivel exige confiar más en los tests que el anterior. Saltarse niveles suele acabar con un despliegue automático que publica errores a toda velocidad.

## Errores frecuentes

| Síntoma | Causa habitual |
|---|---|
| Pasa en local y falla en CI con `Cannot find module 'x'` o `command not found` | El robot parte de una máquina limpia: una dependencia o herramienta que solo existe en el equipo de quien programa no está declarada |
| Falla en CI con `Process completed with exit code 1.` sin más pista | El comando devolvió error; la causa real está en las líneas anteriores del log del step, no en la última |
| Falla a veces y se arregla relanzando | Test intermitente (*flaky*), dependencia de la hora, del orden o de un servicio externo |
| El pipeline está verde y producción está rota | Los tests no cubren lo que falló; CI solo garantiza lo que se prueba |
| `Permission denied (publickey)` en el despliegue | La clave SSH del robot no está autorizada para el usuario `deployer` del VPS |
| La rama lleva dos semanas abierta y la fusión es un infierno | No hay integración continua aunque haya pipeline: integrar a menudo es la práctica, no la herramienta |

## Cuándo no merece la pena (todavía)

- **Un script de usar y tirar** que no se va a mantener: montar el pipeline cuesta más que el script.
- **Sin ningún test y sin intención de escribirlos**: el pipeline compilará y desplegará, pero la señal de «verde» no significará nada. Primero un mínimo de tests; después, la automatización.
- **Despliegue continuo sin forma de volver atrás**: si deshacer una versión es un proceso manual de una hora, mejor entrega continua con aprobación.

CI/CD tampoco escribe los tests, ni decide qué probar, ni qué hacer cuando falla: automatiza la ejecución, no el criterio.

## Buenas prácticas avanzadas

- **Integrar a menudo es la práctica; el pipeline es solo la herramienta.** Un equipo con ramas que viven semanas no hace Integración Continua aunque tenga el mejor pipeline: los conflictos y las sorpresas se acumulan igual. La señal de CI real es que los cambios llegan a la rama común cada pocos días como mucho.
- **Compila una vez y despliega muchas** (*build once, deploy many*). El artefacto que pasa los tests debe ser exactamente el que llega a producción. Recompilar para cada entorno despliega algo que nunca se probó: una diferencia de versión de compilador o dependencia se cuela sin que ningún test la vea. Se promociona la misma imagen entre entornos.
- **Ordena el pipeline para fallar pronto.** Primero lo barato y lo que más falla (linter, compilación, tests unitarios); al final lo caro (E2E, construcción de imágenes). Fallar en el segundo 30 en vez de en el minuto 20 multiplica los ciclos que caben en un día.
- **Trata los tests intermitentes como averías.** Si la costumbre es relanzar hasta que salga verde, el equipo deja de creerse los rojos y el día que uno es real se ignora. Se ponen en cuarentena y se arreglan o se borran: un test en el que no se confía es peor que no tenerlo.
- **Vigila la duración total como una métrica de producto.** Con más de ~10 minutos, la gente agrupa cambios grandes para «no esperar dos veces» y se destruye lo que CI/CD pretende: cambios pequeños y frecuentes. Paralelizar y cachear es trabajo de primera clase.

## Documentación oficial

- [Continuous Integration, de Martin Fowler](https://martinfowler.com/articles/continuousIntegration.html) — el artículo de referencia sobre qué prácticas definen la Integración Continua (rama común, build automático, arreglar el rojo primero); léelo cuando la discusión sea «¿hacemos CI de verdad?» y no «qué herramienta usar».
- [Understanding GitHub Actions](https://docs.github.com/en/actions/get-started/understand-github-actions) — la visión general de una plataforma concreta de CI/CD: eventos, workflows, jobs y runners.

---

*En resumen: CI/CD es una cadena de montaje automática para el código — integra, prueba y despliega siempre de la misma forma, para que entregar software deje de dar miedo.*
