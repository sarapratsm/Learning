# Desarrollo web — Guías

Guías centradas en el desarrollo web con .NET y React, pensadas especialmente para quien viene de otro entorno (como escritorio) y da el salto a la web. Se reparten en dos bloques: las que enseñan un stack concreto y las que tratan criterios de calidad que valen para cualquier stack.

---

## Para aprender un stack

### [Primeros pasos con ASP.NET Core](asp-net-core/README.md)
Introducción a ASP.NET Core para quien ya sabe C#/.NET pero no ha hecho web: qué añade el framework sobre .NET Core (servidor, DI, middleware, routing), los atributos que aparecen en cualquier API (`[ApiController]`, verbos, model binding, validación y `[Authorize]`) los modelos de programación web que puedes elegir (MVC, Razor Pages, Web API, Minimal APIs, Blazor) y cómo encajan con Clean Architecture, y cómo desplegar la app en producción (`dotnet publish`, contenedores, reverse proxy).

### [De C# WPF a C# para web](de-wpf-a-web/README.md)
Traduce lo que ya sabes de WPF (XAML, MVVM, binding) al modelo de ASP.NET Core: HTTP, Razor/MVC, Web API, Entity Framework Core, autenticación, SignalR y cómo se comunica con un frontend moderno.

### [React y su ecosistema](frontend-react/README.md)
Stack React + Vite + TypeScript, con analogías al mundo C#/.NET: componentes, estilos con Tailwind, estado y datos, calidad de código y testing con Vitest.

### [Manual de usuario dentro de una app web](manual-de-usuario-en-la-app/README.md)
Cómo integrar el manual de usuario en una app React: Markdown convertido a HTML en build-time, `dangerouslySetInnerHTML` y XSS, i18n con claves, índice con scroll-spy, modal con zoom y arrastre, capturas automáticas con Playwright y exportación a Word con `python-docx`.

---

## Criterios de calidad de una web

Cualquier web debería cumplirlos, con independencia de la tecnología con la que esté construida.

### [Accesibilidad web](accesibilidad-web/README.md)
WCAG, el estándar que define cuándo una web es accesible: sus cuatro principios, los niveles A, AA y AAA, las versiones 2.0, 2.1 y 2.2, los fallos más frecuentes con su arreglo en código y cómo se comprueba con herramientas, teclado y lector de pantalla.

### [Webs multiidioma](webs-multiidioma/README.md)
Buenas prácticas para ofrecer una web en varios idiomas: el idioma en la URL, `lang` y `hreflang` para navegadores y buscadores, textos con claves y plurales, estructura de carpetas de las traducciones, formatos de fecha, número y moneda con `Intl`, maquetación (textos largos y RTL) y traducciones en base de datos.

### [SEO web](seo-web/README.md)
Cómo hacer que un buscador encuentre y entienda las páginas de una web: rastreo e indexación (códigos de estado, `robots.txt`, `noindex`, sitemap, contenido en el HTML), títulos y URLs, datos estructurados con JSON-LD, Core Web Vitals y diagnóstico con Search Console.

### [Direcciones web y SEO técnico](direcciones-web/README.md)
Lo que una web declara sobre sus propias direcciones: la dirección base, absolutas y relativas, la barra final, la dirección canónica, `hreflang` y `x-default`, `robots.txt` y el sitemap, la vista previa al compartir (Open Graph), los datos estructurados con JSON-LD, las redirecciones 301 y 302 (incluida la de idioma) y cómo se genera todo con la API de metadatos de Next.js en una exportación estática, con un caso práctico de un sitio multiidioma de principio a fin.
