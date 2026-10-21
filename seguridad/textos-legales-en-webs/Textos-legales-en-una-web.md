# Textos legales en una web

## ¿Qué es?

Los textos legales de una web son las páginas que informan de quién la gestiona, qué datos recoge, qué se guarda en el navegador y bajo qué condiciones se usa o se compra. Normalmente son cuatro: el **aviso legal**, la **política de privacidad**, la **política de cookies** y las **condiciones de uso o de venta**.

Esta ficha describe el marco de España y de la Unión Europea.

## ¿Por qué existe?

Una web es un servicio que se ofrece a personas que no conocen a quien lo presta. La normativa obliga a que esa persona pueda saber, sin pedirlo, con quién trata, qué hacen con sus datos y qué le están vendiendo. Los textos legales son la forma en que se cumple esa obligación: no son decoración del pie de página, son información exigida por ley.

Cada texto responde a una norma distinta y tiene un contenido mínimo propio, así que no basta con «poner un texto legal»: hay que saber cuál se necesita y qué debe decir.

## Los cuatro textos y la norma que los exige

| Texto | Qué cuenta | Norma de referencia |
|---|---|---|
| Aviso legal | Quién es el titular de la web y cómo contactarle | Artículo 10 de la LSSI-CE (Ley 34/2002) |
| Política de privacidad | Qué datos personales se recogen, para qué, con qué base, durante cuánto tiempo y qué derechos tiene la persona | Artículos 13 y 14 del RGPD |
| Política de cookies | Qué cookies y tecnologías similares usa la web y cómo se acepta o rechaza | Artículo 22.2 de la LSSI-CE, junto con el RGPD |
| Condiciones de uso o de venta | Las reglas del servicio o de la compra | Depende de lo que se ofrezca; no hay una única norma que fije su contenido |

Los tres primeros tienen un contenido mínimo fijado por una norma. El cuarto es contractual: su contenido lo decide quien vende, dentro de los límites de la legislación aplicable, y esta ficha no lo desarrolla.

La política de privacidad y la de cookies se explican con detalle en [Datos personales y RGPD](../cookies-y-datos-personales/Datos-personales-RGPD.md) y en [Cookies y consentimiento](../cookies-y-datos-personales/Cookies-y-consentimiento.md). Aquí se trata el aviso legal, que es el que más se olvida.

## El aviso legal: qué datos exige el artículo 10

El artículo 10 de la LSSI-CE obliga a quien presta un servicio de la sociedad de la información a facilitar, **«de forma permanente, fácil, directa y gratuita»**, estos datos:

- Nombre o denominación social, domicilio (o la dirección de un establecimiento permanente en España), correo electrónico y cualquier otro dato que permita una comunicación directa y efectiva.
- Los datos de inscripción en el Registro Mercantil, si la entidad está inscrita.
- El número de identificación fiscal.
- Si el servicio hace referencia a precios: información clara y exacta del precio, con indicación de si incluye impuestos y, en su caso, los gastos de envío.
- Si la actividad requiere autorización administrativa previa, los datos de la autorización y del órgano que la supervisa.
- Si se ejerce una profesión regulada: el colegio profesional y el número de colegiado, el título académico o profesional, el Estado que lo expidió y las normas profesionales aplicables.
- Los códigos de conducta a los que se esté adherido, si los hay.

El apartado 2 del mismo artículo da por cumplida la obligación si estos datos están en la propia web «en las condiciones señaladas»: es decir, de forma permanente, fácil, directa y gratuita.

### Cómo se ve en una web

«Permanente y directa» se traduce en un enlace presente en todas las páginas, no solo en la portada. Lo habitual es el pie de página compartido:

```html
<footer>
  <nav aria-label="Información legal">
    <a href="/aviso-legal">Aviso legal</a>
    <a href="/privacidad">Política de privacidad</a>
    <a href="/cookies">Política de cookies</a>
    <a href="/condiciones-de-venta">Condiciones de venta</a>
  </nav>
</footer>
```

Y el contenido del aviso legal de una tienda online, con datos de ejemplo:

```text
Titular: Tienda Ejemplo, S.L.
NIF: B00000000
Domicilio: Calle Ejemplo 1, 08000 Barcelona
Correo de contacto: hola@tienda.ejemplo.com
Registro Mercantil de Barcelona, tomo 0000, folio 00, hoja B-000000
Precios: IVA incluido; los gastos de envío se indican antes de pagar.
```

Cada línea responde a una letra del artículo 10.1. Si falta el NIF o los datos del registro, el aviso legal está incompleto aunque la página exista.

## Quién es responsable del contenido

El texto lo firma, en sentido jurídico, el titular de la web, no quien la programa. Quien desarrolla puede colocar los enlaces, mantener las páginas y asegurarse de que lo que dice el texto coincide con lo que hace la web, pero los datos del titular y los compromisos que se asumen son de la organización. La ficha [Quién puede evaluar los textos legales](Quien-puede-evaluar-los-textos-legales.md) trata quién puede revisarlos y con qué cualificación.

## Errores frecuentes

- **Copiar el texto de otra web.** Arrastra el nombre, el NIF y los proveedores de la web original. Además de ser inexacto, deja publicados datos de otra empresa.
- **Una política que no refleja lo que hace la web.** El texto dice «no usamos cookies» y el código carga una herramienta de analítica. El texto se escribe una vez; el código cambia cada semana.
- **El enlace solo está en la portada.** Quien entra por una página interior, desde un buscador, no ve ni una sola vía de acceso al aviso legal.
- **No actualizarlo al añadir un proveedor.** Un servicio nuevo de correo, de pagos o de mapas cambia quién recibe los datos y debe reflejarse en la política de privacidad.

## Buenas prácticas avanzadas

- **Haz que el texto salga del mismo sitio que el dato.** Si el NIF o el domicilio se escriben a mano en tres páginas, tarde o temprano habrá tres versiones. Guárdalos en un único fichero de configuración y genera el aviso legal desde él.
- **Pon fecha de última actualización a cada texto y revísala cuando cambie el código.** Una regla práctica: cualquier cambio que añada un formulario, un script de terceros o un proveedor lleva una revisión del texto asociado en la misma solicitud de cambios.
- **Contrasta el texto con lo que hace la web, no con lo que se pretendía.** Abre las herramientas de desarrollo del navegador, revisa las peticiones de red y las cookies reales y compáralas con lo que dice la política.
- **Versiona los textos junto al código.** Así se puede demostrar qué decía la política en una fecha concreta, que es lo que se pregunta cuando alguien reclama.
- **Mantén los textos legales accesibles para todo el mundo.** Un aviso legal que un lector de pantalla no puede recorrer no cumple la exigencia de acceso «fácil y directo».

## Documentación oficial

- [LSSI-CE, Ley 34/2002 (BOE)](https://www.boe.es/buscar/act.php?id=BOE-A-2002-13758) — el artículo 10 es el aviso legal y el 22.2 es el de las cookies; el artículo 43 dice quién sanciona cada infracción.
- [Reglamento (UE) 2016/679, RGPD (EUR-Lex)](https://eur-lex.europa.eu/legal-content/ES/TXT/?uri=CELEX:32016R0679) — los artículos 13 y 14 fijan lo que debe decir la información al recoger datos.
- [AEPD, orientación a pymes](https://www.aepd.es/derechos-y-deberes/cumple-tus-deberes/directrices-de-aplicacion/pymes) — la guía de la autoridad de control para organizaciones pequeñas.

## Recursos didácticos

- [Facilita RGPD de la AEPD](https://www.aepd.es/guias-y-herramientas/herramientas/facilita-rgpd) — herramienta gratuita que genera cláusulas informativas para tratamientos de bajo riesgo. La propia AEPD advierte de que obtener los documentos no implica cumplir automáticamente el RGPD.

---

*En resumen: cada texto legal responde a una norma con contenido mínimo propio, lo firma el titular de la web y debe describir lo que la web hace de verdad, no lo que se copió de otra.*
