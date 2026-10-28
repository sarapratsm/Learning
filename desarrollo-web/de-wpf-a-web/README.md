# De C# WPF a C# para web — Guía de transición

Esta colección está pensada para personas que ya programan en **C# con WPF** (aplicaciones
de escritorio, XAML, MVVM, binding) y dan el salto a **C# para la web** con ASP.NET Core.

No parte de cero en programación: asume que conoces C#. Lo que hace es **traducir** lo que
ya sabes de escritorio al mundo web, apoyándose en analogías con WPF para que cada
concepto nuevo tenga un ancla familiar. El objetivo es que entiendas el cambio de
mentalidad y conozcas las opciones que tienes para hacer web con C#, sin perderte.

---

## Orden de lectura recomendado

Sigue este orden si vienes de WPF y empiezas de cero en web. Cada bloque prepara el
siguiente: primero el mapa del recorrido, luego el cambio de mentalidad, la nueva
interfaz, el framework y, por último, las formas concretas de construir la aplicación.

### 1. Por dónde empezar

Si prefieres aprender construyendo, esta ficha te guía de una carpeta vacía a una web
publicada y te dice qué leer en cada paso. Las demás fichas siguen siendo la referencia
de cada concepto.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 1 | [Hoja de ruta: tu primera web](Hoja-de-ruta-primera-web.md) | Ocho hitos de un catálogo de productos con Razor Pages, con la ficha a leer antes de cada uno. |

### 2. El cambio de mentalidad

Lo más importante no es la sintaxis nueva, sino entender por qué la web funciona distinto
a una app de escritorio.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 2 | [Modelo Cliente-Servidor](Modelo-Cliente-Servidor.md) | El cambio de base: tu app deja de ser una pieza y se parte en navegador + servidor. Leer primero. |
| 3 | [HTTP](HTTP.md) | El idioma con el que cliente y servidor se hablan, y por qué "no tiene memoria". |

### 3. De la interfaz XAML a la interfaz web

Tu XAML ya no sirve en el navegador. Esto es lo que lo reemplaza.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 4 | [HTML y CSS](HTML-y-CSS.md) | El "XAML de la web": estructura (HTML) y estilo (CSS) de cualquier interfaz. |
| 5 | [JavaScript y el navegador](JavaScript-y-el-Navegador.md) | Qué se ejecuta en el cliente y por qué tu C# no corre ahí (salvo con Blazor). |

### 4. El framework: ASP.NET Core

El motor sobre el que se construye todo lo demás, con sus piezas transversales.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 6 | [ASP.NET Core](ASP-NET-Core.md) | El "App" de tu aplicación web: el motor que atiende peticiones. Base de todo lo siguiente. |
| 7 | [Inyección de dependencias](Inyeccion-de-Dependencias.md) | Cómo se organizan y entregan los servicios; viene integrada en el framework. |
| 8 | [Hosts y builders en .NET](Hosts-y-Builders.md) | Por qué el arranque de una web y el de una app de consola se parecen tanto, y en qué se diferencian de verdad. |
| 9 | [Routing y Middleware](Routing-y-Middleware.md) | Cómo se decide qué código atiende cada URL y qué pasos comunes atraviesa toda petición. |

### 5. Las tres formas de hacer web con C#

Con los fundamentos claros, estas son las opciones para construir la aplicación. Léelas
para saber cuál elegir en cada caso.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 10 | [Razor Pages y MVC](Razor-Pages-y-MVC.md) | HTML generado en el servidor; el camino más corto desde WPF. |
| 11 | [Web API y REST](Web-API-y-REST.md) | El backend que devuelve datos (JSON) cuando la interfaz la pone otra cosa. |
| 12 | [Blazor](Blazor.md) | Interfaces interactivas en C# con componentes y binding: el puente más cercano a WPF. |
| 13 | [FluentValidation](FluentValidation.md) | Cómo validar los datos de entrada de una petición antes de que lleguen a la lógica de negocio. |

### 6. Conceptos transversales

Temas que cruzan todas las opciones anteriores y que conviene entender antes de poner algo en producción.

| # | Archivo | Por qué leerlo aquí |
|---|---|---|
| 14 | [Autenticación y estado web](Autenticacion-y-Estado-Web.md) | Cómo sabe la app quién eres y cómo recuerda algo, pese a que HTTP no tiene memoria. |
| 15 | [Entity Framework Core](../../bases-de-datos/acceso-a-datos-dotnet/Entity-Framework-Core.md) ↗ | El acceso a datos: persistir en una base de datos lo que en WPF te bastaba con tener en memoria. La ficha vive en la colección de [acceso a datos en .NET](../../bases-de-datos/acceso-a-datos-dotnet/README.md), donde tiene al lado el driver y el micro-ORM con los que se compara. |
| 16 | [SignalR](SignalR.md) | Tiempo real: el servidor empuja datos al navegador, como los eventos del escritorio pero por la red. |
| 17 | [Comunicación entre frontend y backend](Comunicacion-Frontend-Backend.md) | Cómo hablan en la práctica un frontend SPA y tu Web API: proxy en desarrollo, CORS y contenedores en producción. |

---

> ¿Te interesa cómo organizar el código del servidor una vez tengas la base web? Echa un
> vistazo a la guía de [Clean Architecture](../../arquitectura-de-software/clean-architecture/README.md), que encaja
> de forma natural con la [inyección de dependencias](Inyeccion-de-Dependencias.md) de ASP.NET Core. Si el frontend
> es React, la guía de [React y su ecosistema](../frontend-react/README.md) es el equivalente del otro lado.
