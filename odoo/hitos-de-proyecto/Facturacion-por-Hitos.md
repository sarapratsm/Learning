# Facturación por hitos

## ¿Qué es?

Es una política de facturación de Odoo en la que **un servicio se da por entregado, y por tanto facturable, cuando se alcanza un hito del proyecto**, en lugar de cuando se registran horas o se marca la entrega a mano. La pieza que lo hace posible es el módulo `sale_project`, que une el módulo de Ventas con el de Proyecto.

## ¿Por qué existe?

Hay trabajos que no se cobran por horas: "desarrollo del módulo de pagos por 6 000 €, pagado 40 % al aceptar el diseño y 60 % al entregar". Con las políticas habituales de Odoo, esto se resuelve mal:

- *Por horas imputadas* factura lo que se trabajó, no lo pactado.
- *Cantidades entregadas, manual* obliga a que alguien se acuerde de editar la cantidad entregada de la línea del pedido.

La política **Basada en hitos** (*Based on Milestones*) conecta las dos cosas: el hito del proyecto lleva asociada una línea del pedido de venta y un porcentaje, y al marcarlo como alcanzado Odoo actualiza solo la cantidad entregada de esa línea. La factura se genera después, como siempre, con lo entregado.

> Si ya conoces los pagos por hito de un contrato de obra o de un proyecto a precio cerrado, es exactamente ese esquema: el calendario de cobro está en los hitos, no en un contador de horas.

## ¿Cuándo y para qué se usa?

Proyectos de **precio cerrado con pagos escalonados**, ligados a entregas comprobables. No es apropiado cuando el cliente paga por tiempo consumido, ni cuando los hitos son internos y el cliente no los reconoce.

Antes de seguir, hay que conocer [Hitos de proyecto](Hitos-de-Proyecto.md): aquí se da por sabido qué es un hito, cómo se activa y que pertenece a un solo proyecto.

---

## La cadena completa

Para que un hito dispare la facturación, hay cuatro piezas enlazadas:

```
Producto (servicio, política "Basada en hitos")
   └─► Línea del pedido de venta   ← aquí se acumula "Cantidad entregada"
          └─► Hito del proyecto    ← lleva el porcentaje y la casilla "Alcanzado"
                 └─► Tarea         ← opcional: el trabajo que lo respalda
```

Cuando se marca un hito como alcanzado, la cantidad entregada de su línea de pedido pasa a ser la **suma de los porcentajes de los hitos alcanzados × la cantidad pedida**. Todo lo demás (factura, pago) es el flujo estándar de Ventas.

## Configurarlo paso a paso

**1. Producto.** En la ficha del producto: tipo *Servicio* y política de facturación **Basada en hitos**. La opción solo aparece si los hitos están activados en los ajustes de Proyecto. En *Crear en el pedido* conviene elegir *Tarea*, *Proyecto* o *Proyecto y tarea*, para que al confirmar el pedido nazca el proyecto.

**2. Pedido de venta.** Se añade el servicio al pedido y se confirma. En ese momento Odoo hace una de dos cosas:

- Si el proyecto **ya tiene hitos sin línea asignada**, los enlaza a esta línea y reparte la cantidad a partes iguales entre ellos.
- Si no hay ninguno, **crea un hito con el nombre de la línea** y un 100 %, y (si el producto crea una tarea en el proyecto) enlaza la tarea a él.

**3. Hitos.** Desde el botón *Hitos* del pedido se crean o ajustan. Cada hito tiene, además de nombre y fecha, la **línea del pedido** a la que alimenta y su **cantidad / porcentaje**.

**4. Alcanzar y facturar.** Se marca el hito como alcanzado y, en el pedido, *Crear factura* genera un borrador solo con lo entregado.

## Ejemplo guiado: un pago repartido 40/60

Un pedido con una línea: "Desarrollo del módulo de pagos", cantidad 1, precio 6 000 €. Se crean dos hitos en el proyecto, ligados a esa línea:

| Hito | Cantidad (%) | Importe que representa |
|---|---|---|
| Diseño aceptado | 40 % | 2 400 € |
| Módulo entregado | 60 % | 3 600 € |

Se ajustan en el formulario del hito, en el campo de porcentaje (o de cantidad: son dos formas de escribir lo mismo, y Odoo calcula una a partir de la otra).

Al marcar *Diseño aceptado* como alcanzado, la línea del pedido pasa a:

```
Cantidad pedida:    1
Cantidad entregada: 0,4      (40 % × 1)
Cantidad facturada: 0
```

Al pulsar *Crear factura* (factura normal), el borrador lleva **solo 0,4 unidades**, es decir, 2 400 €. Al marcar después *Módulo entregado*, la entregada sube a 1 y la siguiente factura lleva las 0,6 que faltan.

Si los porcentajes no se escriben, el valor de partida depende de cómo nació cada hito: los que ya existían sin línea al confirmar el pedido se reparten a partes iguales (50/50 aquí), pero un hito creado después desde el botón *Hitos* del pedido arranca con el **100 %** de la línea. Dos hitos creados así sumarían 200 %, y alcanzar el primero ya dejaría la línea entera como entregada. Es la causa más común de que "la primera factura sale por el importe equivocado".

## Errores frecuentes

**Un hito sin línea de pedido.** Se puede marcar como alcanzado y no pasa nada: ninguna cantidad entregada cambia, porque no hay línea a la que actualizar. En el hito, el campo de la línea del pedido tiene que estar relleno.

**La línea no aparece al elegirla.** El selector solo ofrece líneas del **mismo cliente** que el proyecto y cuyo producto use la política basada en hitos. Si falta, revisa primero el cliente del proyecto y después la política del producto.

**Los porcentajes no suman 100 %.** Odoo no lo comprueba, en ninguna dirección. Si los hitos de una línea suman 90 %, aunque se alcancen todos, la línea no llegará nunca a "totalmente entregada"; si suman 200 %, la cantidad entregada supera a la pedida. En ambos casos nadie recibe un aviso.

**Desmarcar un hito ya facturado.** La cantidad entregada baja, pero la factura ya emitida no se modifica. Queda más facturado que entregado y hay que corregirlo con una nota de crédito.

## Buenas prácticas avanzadas

- **Escribe los porcentajes en cuanto crees el hito y verifica que suman 100 %.** Los valores por defecto (reparto a partes iguales al confirmar, 100 % para los creados después) casi nunca coinciden con lo pactado, y Odoo no avisa de que la suma no cuadra. Una comprobación de dos segundos tras crear los hitos evita una factura equivocada.
- **Un hito, una línea.** Que un mismo hito alimente a varias líneas no es posible, y eso condiciona cómo se redacta el presupuesto: si el cliente quiere "diseño" y "desarrollo" en líneas separadas, cada una necesita sus propios hitos, aunque el trabajo se entregue junto.
- **Exige evidencia antes de marcar el hito.** Alcanzar un hito aquí no es un detalle del proyecto: es un acto de facturación. Conviene que quien lo marca no sea quien ejecutó el trabajo, o que exista un comentario en el chatter del hito con la aceptación del cliente.
- **Comprueba la columna *Entregado* del pedido tras cada hito.** Es el resumen visible de toda la cadena: si no se ha movido, algo en los cuatro eslabones está mal, y es más fácil verlo ahí que revisando hitos uno a uno.
- **Cuidado con activar hitos en una instalación con pedidos antiguos.** Al activar la función, Odoo convierte a "basada en hitos" los productos que ya tengan hitos con línea asignada. Haz el cambio en una copia de pruebas primero y revisa qué productos han cambiado de política.

## Documentación oficial

- [Facturar hitos de proyecto (Odoo 18)](https://www.odoo.com/documentation/18.0/applications/sales/sales/invoicing/milestone.html) — el recorrido completo desde el producto hasta el pago, con capturas. No menciona los porcentajes por hito, que sí existen en el código.
- [Código de `sale_project`](https://github.com/odoo/odoo/blob/18.0/addons/sale_project/models/project_milestone.py) — donde se ve cómo se calcula el porcentaje y la cantidad de cada hito, y cómo se reparte al confirmar el pedido.

---

*En resumen: en la facturación por hitos, marcar un hito como alcanzado equivale a entregar el porcentaje de la línea del pedido que tiene asignado, y de ahí sale la factura; por eso el hito deja de ser una anotación y pasa a ser un acto con consecuencias económicas.*
