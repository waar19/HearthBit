# Plantilla para pedir una tarea de vibecoding

Copie y complete sólo lo que aplique. Una buena solicitud describe el cambio observable; no necesita conocer los nombres internos de las clases.

```markdown
## Objetivo
Como [tipo de persona usuaria], quiero [acción o resultado] para [motivo].

## Flujo afectado
[Chat / SOS / radar / transferencias / privacidad / familia / relay / ancla]

## Comportamiento esperado
- [resultado visible o funcional]
- [resultado visible o funcional]

## Límites y no objetivos
- No cambiar [protocolo, seguridad, compatibilidad, textos, etc.]
- No prometer [entrega, precisión, segundo plano, alcance] sin evidencia.

## Criterio de aceptación
- [escenario concreto que debe funcionar]
- [caso de error o borde que debe conservarse]

## Diseño y texto
[referencia visual, copy deseado o “proponer una alternativa”]

## Validación esperada
[prueba Flutter / Android / iOS / relay / conformidad / hardware pendiente]
```

## Ejemplo breve

```markdown
## Objetivo
Como rescatista, quiero ver por qué el radar dejó de recibir muestras para decidir si debo volver sobre mis pasos.

## Flujo afectado
Radar.

## Comportamiento esperado
- Mostrar un estado claro cuando no llegan muestras durante el umbral vigente.
- Mantener el lenguaje de estimación y no afirmar una distancia exacta.

## Límites y no objetivos
- No cambiar el protocolo de consentimiento ni el algoritmo RSSI.
- No añadir una dependencia de red.

## Criterio de aceptación
- Una prueba cubre la transición de señal disponible a señal perdida.
- Las seis localizaciones contienen el nuevo texto visible.

## Validación esperada
Flutter analyze y pruebas enfocadas; validación de campo queda pendiente.
```

## Preguntas que es válido dejar abiertas

Si una decisión cambia seguridad, compatibilidad o el significado de una confirmación, formule la solicitud como una pregunta de diseño. Por ejemplo: “propón dos alternativas y sus consecuencias antes de implementarla”. Eso es preferible a pedir al agente que elija una política de seguridad por defecto.
