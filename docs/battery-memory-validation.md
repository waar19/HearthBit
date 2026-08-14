# Validación de batería y memoria

Esta prueba compara dos builds de HearthBit bajo las mismas condiciones. El
porcentaje mostrado por “Cuidado del dispositivo” es la participación de la
aplicación en el consumo registrado, no necesariamente puntos porcentuales de
la carga total.

## Preparación en Windows

1. Conecte el teléfono, autorice ADB y confirme que aparece:

   ```powershell
   adb devices
   ```

2. Cargue el teléfono al mismo nivel para cada medición, desconecte el cable y
   restablezca las estadísticas:

   ```powershell
   adb shell dumpsys batterystats --reset
   ```

3. Active la malla y use el teléfono durante 24 horas. Mantenga constantes:
   versión de Android, Bluetooth, ubicación, Wi-Fi/datos, brillo, perfil de
   energía de HearthBit y tiempo aproximado con pantalla encendida.

## Captura después de 24 horas

Ejecute desde la raíz del repositorio:

```powershell
adb shell dumpsys batterystats com.hearthbit.app > hearthbit-batterystats.txt
adb shell dumpsys batterystats --checkin > hearthbit-batterystats-checkin.csv
adb shell dumpsys meminfo com.hearthbit.app > hearthbit-meminfo.txt
adb shell dumpsys procstats --hours 24 com.hearthbit.app > hearthbit-procstats.txt
```

Anote además:

- porcentaje de batería inicial y final;
- minutos con pantalla encendida;
- tiempo en las pestañas Canal, Cercanos, Radar y Mapa;
- cantidad aproximada de mensajes, peers y transferencias;
- si el sistema activó ahorro de energía;
- pérdidas de descubrimiento, mensajes o reconexiones.

## Escenarios mínimos

1. **Reposo normal:** malla activa, HearthBit en segundo plano y sin abrir
   “Cercanos” durante dos horas.
2. **Presencias genéricas:** “Cercanos” visible durante diez minutos; al salir,
   comprobar que desaparecen los eventos genéricos y la malla sigue detectando
   peers HearthBit/BitChat.
3. **Reconexión:** alejar un peer por más de cuatro minutos y confirmar la
   reconexión y el envío del outbox al regresar.
4. **Rescate:** activar SOS durante al menos quince minutos y comprobar que la
   ubicación sigue actualizándose con precisión alta.
5. **Memoria prolongada:** abrir conversaciones antiguas y comprobar que
   `TOTAL PSS` no crece continuamente después de varias horas.

## Criterios de aceptación

- menor consumo en reposo que el build anterior bajo condiciones equivalentes;
- el escaneo genérico solo funciona con “Cercanos” visible y la app activa;
- sin regresiones de descubrimiento, BitChat, SOS, radar ni outbox;
- memoria estable después de repetir navegación y recepción de mensajes;
- SQLite conserva los 1000 mensajes más recientes y la interfaz mantiene hasta
  500 mensajes en memoria.

No publique capturas sin revisar coordenadas, identificadores de peers,
direcciones Bluetooth y contenido de mensajes.
