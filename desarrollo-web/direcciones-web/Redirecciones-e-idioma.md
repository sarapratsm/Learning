# Redirecciones: 301, 302 y la redirección por idioma

## ¿Qué es?

Una **redirección** es una respuesta del servidor que dice «lo que buscas no está aquí, está en esta otra dirección». Lleva un código de estado (301, 302, 307, 308...) y una cabecera `Location` con el destino. El navegador, o el robot, la sigue de forma automática.

## ¿Por qué existe?

Las direcciones cambian: una página se renombra, el sitio cambia de dominio, la portada debe llevar a cada visitante a su idioma. Sin redirecciones, cada cambio rompe los enlaces que apuntan a la dirección antigua. Y hay un matiz que da lugar a la mayoría de los errores: **no todas las redirecciones significan lo mismo**. Algunas dicen «esto cambió para siempre» y otras «de momento, ve allí».

## ¿Cuándo y para qué se usa?

- **Permanente**: una página cambia de dirección y no vuelve; la web migra a un nuevo dominio; se unifica `http`/`https` o con y sin `www`.
- **Temporal**: la portada manda a cada persona a su idioma; una página en mantenimiento.
- Escenario típico: una tienda online que pasa de `/zapatillas/` a `/es/zapatillas/` al añadir idiomas, y cuya raíz `/` lleva a `/es/`, `/ca/` o `/en/`.

---

## Los códigos

| Código | Tipo (según Google) | Uso |
|---|---|---|
| 301 | Permanente | El cambio es definitivo. |
| 308 | Permanente | Igual, pero garantiza que el método HTTP no cambia. |
| 302 | Temporal | Redirección pasajera o que depende de quién pregunta. |
| 307 | Temporal | Igual que 302, pero garantiza que el método HTTP no cambia. |

La diferencia entre 301/302 y 308/307 solo importa si la petición no es un `GET` (un `POST` que se redirige con 301 o 302 puede convertirse en `GET`; con 307 y 308, no). Para las páginas que ve una persona, 301 y 302 bastan.

**Cómo las trata Google.** Con una redirección permanente, el destino pasa a ser la dirección canónica y la antigua desaparece de los resultados con el tiempo. Con una temporal, **la dirección de origen sigue siendo la que se muestra**. Por eso importa elegir bien: una redirección 301 «de prueba» sustituye a la antigua; una 302 que se queda años no consolida nada.

## Redirecciones permanentes bien hechas

```text
GET /zapatillas/aire/       →  301  Location: /es/zapatillas/aire/
```

- **Un solo salto.** Que `/a` lleve a `/b` y `/b` a `/c` (una cadena) alarga la carga y dispersa señales; apunta siempre al destino final.
- **A su equivalente más cercano**, no a la portada. Redirigir en masa toda dirección antigua a la home engaña a las personas y a los buscadores; una dirección sin equivalente es un 404 honesto.
- **Mantén las redirecciones** mientras existan enlaces a la dirección antigua: meses, a menudo años.
- **No las encadenes con la canónica.** El destino debe ser la dirección canónica, con la misma barra final, esquema y host que declara su página.

## La redirección por idioma de la raíz

Quien entra por `https://ejemplo.com/` no ha elegido idioma. Una web multiidioma puede llevarle al de su navegador. Las reglas que evitan problemas:

1. **Temporal (302), no permanente.** El destino depende de quién visita; los navegadores pueden guardar un 301 en su caché, y esa persona iría siempre al mismo idioma aunque luego cambie su configuración.
2. **Solo en la raíz.** Si alguien entra por `/es/zapatillas/`, ya ha elegido: no lo muevas. La cabecera `Accept-Language` es una **pista**, y quien ha escrito o pulsado una dirección concreta manda sobre ella.
3. **Sin IP ni cookie.** La IP dice dónde está una persona, no qué idioma lee (un turista, una VPN), y una cookie añade un consentimiento que no necesitas. El idioma del navegador basta.
4. **Con un selector de idioma visible** en cada página, para quien quiera otro.
5. **La raíz sigue siendo una página real para los robots**, con enlaces a cada idioma y declarada como `x-default` de todas las páginas (ver [Canónica y hreflang](Canonica-y-hreflang.md)): los buscadores no declaran su idioma de forma fiable.

### `Accept-Language` y `navigator.languages`

El navegador envía en cada petición la cabecera `Accept-Language` con los idiomas preferidos de la persona, ordenados con pesos de calidad (`q`):

```http
Accept-Language: es-ES, es;q=0.9, en;q=0.8, *;q=0.5
```

`navigator.languages` es **la misma lista**, leída desde JavaScript (`['es-ES', 'es', 'en']`), sin los pesos porque ya va ordenada. Por privacidad, algunos navegadores muestran una sola lengua o una lista reducida. Los dos sirven para el mismo propósito; cuál usar depende de **dónde** decides:

| Dónde redirigir | Qué lees |
|---|---|
| En el servidor, antes de enviar nada | La cabecera `Accept-Language`. |
| En una página estática, en el navegador | `navigator.languages`. |

La lógica es siempre la misma: **la primera lengua de la lista cuyo código base esté soportado; si ninguna lo está, un idioma por defecto**.

#### En el navegador (página estática)

```html
<script>
  const soportados = ['ca', 'es', 'en']
  const lenguas = navigator.languages && navigator.languages.length ? navigator.languages : []
  const idioma =
    lenguas.map((l) => l.split('-')[0].toLowerCase()).find((c) => soportados.includes(c)) || 'en'
  location.replace('/' + idioma + '/')
</script>
```

`location.replace` evita añadir la raíz al historial, y el botón «Atrás» no devuelve a la página de paso.

#### En el servidor (nginx)

```nginx
map $http_accept_language $idioma {
    default  en;
    ~*^ca    ca;
    ~*^es    es;
}

server {
    location = / {
        return 302 /$idioma/;
    }
}
```

Es una versión simple: mira solo la primera lengua de la cabecera, sin interpretar los pesos `q`. Para casi todos los casos basta.

### Si no puedes redirigir en el servidor

Un sitio estático alojado en un servicio que no permite redirecciones (o una exportación estática de un framework, que no genera redirecciones propias) no puede enviar un 302. La alternativa es una **página raíz mínima**:

- Tres enlaces visibles, uno por idioma, que funcionan sin JavaScript.
- Un script como el anterior que redirige en el navegador.
- Las etiquetas `hreflang` con `x-default` hacia ella misma, y **sin `noindex`**: es la página que reciben los buscadores.

Evita en ella el `<meta http-equiv="refresh" content="0; url=/es/">`: Google lo interpreta como una **redirección permanente** cuando el retardo es cero, lo contrario de lo que quieres. Y recuerda que Google ejecuta el JavaScript después del rastreo, y si falla, puede no ver la redirección: por eso los enlaces visibles son obligatorios.

## Errores frecuentes

- **Redirigir la raíz con 301.** Puede quedar en la caché del navegador y romper el cambio de idioma.
- **Redirigir por idioma en todas las páginas**, no solo en la raíz. Impide compartir un enlace en otro idioma.
- **Cadena de redirecciones** al migrar.
- **Todo a la portada** en lugar de a su equivalente o a un 404.
- **Redirección por JavaScript como único camino**, sin enlaces visibles.

## Buenas prácticas avanzadas

- **Define el destino como una función de la tabla de direcciones, no de listas sueltas.** La misma tabla que construye canónicas y mapa del sitio dice a qué dirección nueva va cada antigua; así una redirección nunca apunta a una página que ya no existe.
- **Comprueba que no hay cadenas con un test.** Recorre la tabla: el destino de cada redirección no puede ser el origen de otra.
- **Prueba las redirecciones en el entorno real antes del lanzamiento**; su comportamiento depende del servidor, y un rastreo de prueba te enseña saltos que no se ven con el navegador.
- **Mide antes de migrar.** Las direcciones que más tráfico traen son las que no puedes permitirte romper; un inventario de las de la web actual es el primer paso.
- **Un 404 honesto** para lo que ya no existe es mejor señal que una redirección falsa.

## Documentación oficial

- [Redirecciones y Google Search (Google)](https://developers.google.com/search/docs/crawling-indexing/301-redirects) — tipos de redirección y cómo trata cada una; empieza por la tabla de permanentes y temporales.
- [`Accept-Language` en MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Accept-Language) — formato de la cabecera, pesos `q` y por qué no debe anular una elección explícita.
- [Redirecciones HTTP en MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Redirections) — los códigos 3xx y sus diferencias.

---

*En resumen: 301 para lo que cambia para siempre, 302 para lo que depende de quién pregunta; la raíz redirige por idioma solo ella, sin IP ni cookies, y siempre con enlaces visibles de respaldo.*
