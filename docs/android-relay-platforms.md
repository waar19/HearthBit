# Relays en Android TV y Android Automotive

El módulo `app/android/relay` produce dos APK nativos, separados de la
aplicación Flutter. Ambos reutilizan sin bifurcar el motor BLE Android de
HearthBit y no presentan chat, SOS, ubicación ni radar. Su única función es
mantener enlaces BLE y retransmitir paquetes opacos de la malla.

## Android TV

La variante `tv` declara Leanback, interfaz horizontal operable con control
remoto y un servicio en primer plano de tipo `connectedDevice`. No solicita
permisos de ubicación: requiere Android 12 (API 31) o posterior y usa
`BLUETOOTH_SCAN` con `neverForLocation`.

Antes de iniciar, detecta en runtime:

- presencia de BLE y rol GATT central;
- estado del adaptador;
- `isMultipleAdvertisementSupported`;
- disponibilidad efectiva de `BluetoothLeAdvertiser`.

Si advertising está disponible, opera como relay dual: escanea, anuncia,
acepta enlaces GATT y crea enlaces GATT centrales. Si no está disponible,
inicia el mismo motor en modo degradado de **escaneo + GATT central**. En ese
modo el televisor solo puede encontrar nodos que se anuncien y conectarse a
ellos; ningún nodo puede descubrir el televisor. Por tanto, la cobertura
depende de que haya al menos dos periféricos anunciantes alcanzables y el modo
degradado no equivale a un relay dual.

Comandos de desarrollo en Windows:

```powershell
cd app\android
.\gradlew.bat :relay:testTvDebugUnitTest
.\gradlew.bat :relay:assembleTvDebug
```

El APK se genera bajo `app/build/relay/outputs/apk/tv/debug`. Es necesario
probar el modelo exacto de TV: varios equipos incluyen BLE para controles pero
no implementan advertising múltiple ni un GATT periférico usable por apps.

## Android Automotive OS

La variante `automotive` declara `android.hardware.type.automotive`, entrada
`CAR_LAUNCHER`, BLE y los mismos permisos de dispositivos cercanos. No declara
GPS, servicio de ubicación, radar, micrófono, telefonía, Wi-Fi ni cámara.

La política incluida es conservadora y falla cerrada:

1. El conductor inicia explícitamente el relay desde la pantalla estacionada.
2. El servicio solo arranca mientras existe una sesión visible e interactiva
   de la aplicación.
3. Al salir de la actividad, apagar la pantalla, cerrar la tarea o recibir el
   apagado del sistema, se borra la autorización de sesión, se detiene el
   motor y el servicio usa `START_NOT_STICKY`.
4. El sistema no inicia el relay al arrancar el vehículo.

Esta política garantiza que el port genérico no continúe deliberadamente en
segundo plano con la interfaz apagada. No pretende inferir el estado de
ignición a partir de señales Android ambiguas. Para una integración OEM, el
fabricante debe sustituir la compuerta conservadora por su señal autorizada de
energía/ignición (por ejemplo, la API de energía de Car disponible para apps
privilegiadas), manteniendo la regla **apagado o estado desconocido ⇒ relay
detenido**. No se debe usar `BOOT_COMPLETED`, temporizadores ni el estado de
carga como sustitutos de la ignición.

```powershell
cd app\android
.\gradlew.bat :relay:testAutomotiveDebugUnitTest
.\gradlew.bat :relay:assembleAutomotiveDebug
```

Android Automotive restringe las categorías distribuibles mediante Google
Play. Un relay BLE permanente no es una categoría de conducción aprobada por
defecto; esta variante está destinada a validación, distribución privada u
homologación OEM. No debe publicarse como app para uso durante la conducción
sin revisión de seguridad y cumplimiento del fabricante.

## Validación mínima en hardware

Para cada TV o unidad AAOS:

1. Confirmar que la UI informa `relay BLE completo` o `modo central`.
2. Verificar la notificación persistente mientras el relay está activo.
3. Con tres nodos, enviar un paquete entre extremos y comprobar que cruza el
   relay; repetir tras reiniciar Bluetooth.
4. En modo central, confirmar que el equipo no se anuncia y que aun así crea
   enlaces hacia periféricos anunciantes.
5. En Automotive, apagar la pantalla y salir de la app; el servicio y el
   advertising deben desaparecer inmediatamente.
6. Revisar el manifiesto combinado del APK y confirmar que no contiene
   permisos de ubicación ni `foregroundServiceType="location"`.

Las pruebas unitarias cubren la selección de modo, pero un emulador no valida
el controlador BLE, coexistencia de radio, alcance ni comportamiento de
energía del fabricante.

## Plataformas posteriores

Windows y macOS quedan como trabajo posterior. Este repositorio no contiene
binarios, servicios ni paquetes instalables de relay para esas plataformas y
no se afirma soporte actual.

Un port futuro debe comprobar antes de anunciar compatibilidad:

- advertising BLE conectable y escaneo simultáneos;
- servidor y cliente GATT concurrentes con varios peers;
- ejecución prolongada y reanudación tras suspensión;
- permisos, instalación y servicio de fondo propios del sistema;
- interoperabilidad y pruebas de relay de tres nodos con los paquetes
  existentes, sin modificar el protocolo.

En equipos donde el sistema solo permita rol central, la única degradación
aceptable es escaneo + GATT central con la limitación visible descrita arriba;
no debe presentarse como relay dual.
