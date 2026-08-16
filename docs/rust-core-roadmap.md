# Hoja de ruta del núcleo Rust

## Estado de la Fase 7

`core/hearthbit-core` es una biblioteca Rust pura que decodifica frames
HearthBit v1/v2, genera la representación canónica de firma, calcula SHA-256 y
verifica Ed25519 estrictamente. También decodifica el payload de rotación de
clave para cubrir el vector compartido correspondiente.

Esta fase **no integra FFI**, no cambia el camino de producción y no reemplaza
los codecs actuales de Kotlin, Swift o Dart.

## Fases siguientes

### Fase 8: ABI C estable

- Crear una capa FFI separada del crate de dominio.
- Exponer buffers con propietario explícito, códigos de error estables y una
  función única para liberar memoria.
- Prohibir `panic` al cruzar la ABI y añadir pruebas de sanitizadores.
- Versionar la ABI y generar cabeceras reproducibles en CI.

### Fase 9: Android

- Compilar bibliotecas por ABI con el NDK y empaquetarlas en el módulo Android.
- Añadir un adaptador Kotlin/JNI sin cambiar inicialmente el codec activo.
- Ejecutar cada fixture contra Kotlin y Rust y comparar resultado, error,
  bytes canónicos y hash.
- Activar Rust primero en builds internas mediante una bandera local
  reversible; no mezclar resultados de ambos codecs en una misma operación.

### Fase 10: iOS

- Producir un XCFramework para dispositivo y simulador desde la misma revisión.
- Añadir un wrapper Swift que copie datos en los límites de propiedad y
  traduzca códigos de error a tipos Swift.
- Repetir la ejecución diferencial con los fixtures y medir tiempo, memoria y
  tamaño del binario antes de habilitarlo.

### Fase 11: Dart y Flutter

- Exponer la ABI C mediante `dart:ffi` detrás de una interfaz Dart estable.
- Ejecutar llamadas costosas fuera del isolate de interfaz.
- Empaquetar Android e iOS sin descargar binarios durante el build.
- Mantener una implementación Dart únicamente donde exista hoy un codec de
  producción que aún no haya migrado.

### Fase 12: migración gradual

El cambio de lectura y escritura se hará por operación, no por plataforma
completa:

1. Decodificación en sombra, sin efectos, y comparación con la implementación
   existente.
2. Lectura Rust con escritura existente.
3. Lectura y escritura Rust para usuarios internos.
4. Despliegue porcentual con métricas de incompatibilidad y fallos FFI.
5. Retirada del codec anterior solo después de dos versiones estables.

La verificación de firma debe usar siempre los bytes producidos por el mismo
codec que decodificó el paquete. No se aceptará un paquete porque uno de dos
codecs discrepe de manera favorable.

## Criterios para avanzar

- Todos los fixtures aplicables producen resultados idénticos byte a byte en
  cada plataforma.
- Casos truncados, padding inválido, rutas duplicadas, expansión excesiva y
  firmas alteradas se rechazan de forma equivalente.
- Cero fallos de memoria o `panic` en fuzzing y sanitizadores.
- Sin regresiones relevantes de latencia, memoria, batería ni tamaño.
- Builds reproducibles para todas las arquitecturas soportadas.
- Telemetría agregada sin payloads, claves, identificadores ni firmas.
- Procedimiento de soporte y rollback ensayado antes de ampliar el despliegue.

## Rollback

- La selección del codec será una bandera local versionada con valor seguro por
  defecto; no dependerá de red para recuperar la app.
- Mientras exista despliegue gradual, se conservarán ambos codecs y sus
  fixtures en CI.
- Un aumento de errores FFI, discrepancias canónicas o fallos de firma detendrá
  el despliegue y volverá a la implementación anterior en la siguiente
  operación.
- Los formatos persistidos seguirán siendo los bytes de protocolo, no structs
  privados de Rust, para que el rollback no requiera migrar datos.
- No se hará rollback aceptando validaciones más débiles. Si ambos codecs
  fallan o discrepan en seguridad, el paquete se rechaza.
