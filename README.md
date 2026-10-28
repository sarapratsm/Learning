# Learning — Guías de tecnología

Colección personal de guías de tecnología en español, organizadas por categoría. Cada carpeta de tema es autónoma: un README-índice y una ficha por tecnología o concepto, pensadas para leerse sin conocer ningún proyecto concreto. Empiezan por una introducción accesible y desarrollan el tema con la profundidad que pida, siempre con ejemplos de código guiados.

---

## Categorías

### [Arquitectura de software](arquitectura-de-software/README.md)
Clean Architecture, patrones de diseño y Domain-Driven Design, multi-tenancy, los distintos tipos de APIs y cómo escribir y mantener su contrato.

### [Desarrollo web](desarrollo-web/README.md)
ASP.NET Core desde cero (qué añade sobre .NET Core, sus atributos, sus modelos de programación web y su despliegue), la transición desde C# WPF a la web, el stack frontend React + Vite + TypeScript, la accesibilidad web con WCAG, las buenas prácticas en webs multiidioma, el SEO técnico, las direcciones web (canónica, `hreflang`, `robots.txt`, sitemap, Open Graph, JSON-LD y redirecciones) y cómo integrar un manual de usuario dentro de una app React.

### [Lenguajes y runtimes](lenguajes/README.md)
Fundamentos de C# y .NET (lenguaje, runtime, MSBuild y NuGet) y características del lenguaje como los atributos.

### [Bases de datos](bases-de-datos/README.md)
PostgreSQL, acceso a datos en .NET, caching con Redis, migraciones de esquema y bases de datos documentales (MongoDB).

### [Testing](testing/README.md)
Testing en .NET: xUnit, Shouldly, NSubstitute, fixtures, Testcontainers y más.

### [DevOps y control de versiones](devops/README.md)
Git, la administración de organizaciones de GitHub (permisos, equipos, rulesets, seguridad y gobierno), CI/CD, Docker, despliegue en un VPS propio (proxy inverso, HTTPS, backups, VPN), almacenamiento de objetos con Cloudflare R2, observabilidad y mensajería asíncrona.

### [Seguridad](seguridad/README.md)
Algoritmos de hash modernos, autenticación y autorización (OAuth2, OIDC, JWT), el límite de intentos del login (por IP y por cuenta, y la IP real tras un reverse proxy), las cookies y los datos personales (consentimiento y RGPD), los textos legales de una web y quién puede evaluarlos, y el manejo de secretos: guardarlos en desarrollo y no filtrarlos al usarlos en llamadas salientes.

### [Redes](redes/README.md)
Conexiones remotas, carpetas compartidas, NAS, SSH, VPN y compañía.

### [Odoo](odoo/README.md)
El ERP de código abierto, en diez bloques: los fundamentos para entenderlo, cómo hacer pruebas de forma segura sobre un Odoo en producción, cómo se construyen las búsquedas y los filtros (dominios, *search panel*, filtros dinámicos), las distintas maneras de configurar parámetros (odoo.conf, parámetros del sistema, ajustes, IDs externos), los mecanismos de notificación (avisos flotantes, excepciones, chatter y seguidores, plantillas de correo, actividades), los botones de acción (`type="object"`) con los que una vista dispara código propio sobre un registro, herencia de vistas con `xpath` incluida, el systray con el que se añade un icono propio a la barra de navegación, el bus de eventos de OWL (`env.bus`) para sincronizar partes de la interfaz que no se conocen entre sí, cómo contribuir un fix al núcleo de Odoo o a un módulo de la OCA cuando el bug no está en código propio, y los hitos de proyecto con los que se marcan las entregas y se factura por ellas.

### [Herramientas y sistemas](herramientas/README.md)
Correo transaccional.

### [IA](ia/README.md)
Texto: ingeniería con LLMs (programar con agentes de codificación, distribuir sus extensiones con plugins y marketplaces, y construir software con modelos: API, tool use, agentes, MCP, evaluaciones, coste y seguridad) y context engineering, cómo diseñar y gestionar todo lo que recibe un modelo en cada llamada. Imagen: modelos de difusión y control estructural con ControlNet (preprocesadores, peso y ventana de control, multi-ControlNet).
