# Arquitectura de software — Guías

Cómo organizar el código de una aplicación y cómo diseñar la comunicación entre sistemas: patrones de arquitectura, aislamiento multi-cliente, los distintos estilos de API y cómo mantener su contrato.

---

## Contenido

### [Clean Architecture](clean-architecture/README.md)
Cómo separar dominio, casos de uso e infraestructura para que el código sea fácil de mantener, probar y cambiar: la regla de dependencia, la inversión de dependencias, los puertos y adaptadores, dónde vive cada código de resultado y cómo repartir el código entre módulos y proyectos compartidos.

### [Patrones de diseño](patrones-de-diseno/README.md)
Domain-Driven Design (contextos delimitados, objetos de valor, entidades y agregados, repositorios, eventos de dominio), patrones de diseño clásicos (Factory, Strategy, Decorator, Mediator y su implementación MediatR) y el Result Pattern para comunicar fallos esperados como valores.

### [Multi-Tenancy](multi-tenancy/README.md)
Cómo una sola aplicación da servicio a muchos clientes (*tenants*) manteniendo sus datos aislados.

### [Tipos de APIs](tipos-de-apis/README.md)
Los distintos estilos para construir una API (REST, GraphQL, gRPC, SOAP, WebSockets, webhooks, eventos...) y cuándo elegir cada uno.

### [Contratos de API](contratos-de-api/README.md)
Cómo escribir, versionar y mantener el contrato OpenAPI de una API: contrato primero, qué cuenta como ruptura, modelado de errores, descripciones y ejemplos fieles, y el gobierno de los cambios.
