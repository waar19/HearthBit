# Validación física de HearthBit en iOS

Estado de esta guía: **pendiente de ejecución en Mac y hardware físico**. Define
procedimiento y criterios; no demuestra que ningún caso haya pasado.

## Preparación y privacidad

Hardware mínimo:

- Un iPhone con iOS 16 o posterior, Developer Mode habilitado y HearthBit. La
  captura automatizada con `devicectl` requiere iOS 17 o posterior.
- Un segundo teléfono con HearthBit; para interoperabilidad, un iPhone con la
  versión oficial de BitChat usada en la ejecución.
- Cable para la captura inicial y una Mac con Xcode 15 o posterior.

Use alias `IOS-A`, `HB-B` y `BC-A`. No incluya nombres personales, ubicación
exacta, MAC, identificadores del iPhone, UUID de Bluetooth, claves, tokens ni
contenido privado real. Use únicamente marcadores sintéticos:

```bash
export RUN_ID="RUN-$(date -u +%Y%m%dT%H%M%SZ)"
export HB_TO_IOS="D1-NOISE-01-HB2IOS-$RUN_ID"
export IOS_TO_HB="D1-NOISE-01-IOS2HB-$RUN_ID"
xcrun devicectl list devices
```

Instale el build, abra una terminal en la raíz del repositorio e inicie una
captura. El script reinicia HearthBit mediante
`devicectl --console --terminate-existing`, sanea la salida antes de escribirla,
calcula SHA-256 y deja el resultado `PENDING`:

```bash
bash scripts/field-test/collect-ios-field-log.sh \
  --case-id D1-NOISE-01 \
  --run-id "$RUN_ID" \
  --node-alias IOS-A \
  --device-id "<identificador mostrado por devicectl>" \
  --duration 300
```

Ejecute una captura independiente por caso. Revise también la consola visual de
Xcode si hace falta, pero no exporte una consola completa sin sanear. El script
no puede probar por sí solo entrega visual, cifrado, ejecución en segundo plano,
ausencia de duplicados ni topología física.

En iOS 16, `devicectl` no ofrece esta captura: use
`Xcode > Window > Devices and Simulators > Open Console`, filtre por el proceso
Runner y por `HearthBitMesh`, y redacte la exportación antes de conservarla. No
copie Device Console completa ni la considere equivalente a la evidencia
automatizada con hash; registre el caso como `BLOCKED` si no puede producir una
captura saneada verificable.

## D1-NOISE-01 — HearthBit ↔ HearthBit

1. Coloque `IOS-A` y `HB-B` a menos de cinco metros, sin otro relay, Wi-Fi ni
   datos móviles. Mantenga Bluetooth activo.
2. Abra el chat privado, espere el indicador de canal seguro y envíe
   `$HB_TO_IOS` desde `HB-B`. Responda desde iOS con `$IOS_TO_HB`.
3. Cierre y vuelva a abrir la conversación sin borrar identidad. Envíe un tercer
   marcador y confirme que la sesión se conserva o renegocia sin intervención.

**PASS:** ambos sentidos muestran el marcador en el chat privado correcto,
exactamente una vez; las dos interfaces indican canal seguro y no hay fallo de
estado/protocolo Noise, identidad rechazada ni texto claro.

**FAIL:** falta una dirección, el mensaje aparece en público o en otro peer, se
duplica, exige borrar identidad o aparece un fallo Noise. Un log sin
confirmación visual en ambos teléfonos no permite declarar PASS.

## Reconexión HearthBit ↔ BitChat

1. Cree una conversación previa entre HearthBit y BitChat y confirme un mensaje
   privado seguro en cada sentido.
2. Con el chat abierto, desactive Bluetooth en un extremo durante 30 segundos.
   Envíe desde HearthBit un marcador nuevo durante la desconexión.
3. Reactive Bluetooth sin cerrar el chat. Mida desde la reactivación hasta que
   el canal vuelva a seguro; envíe una respuesta desde el extremo que conservó
   la sesión anterior.
4. Repita desconectando el otro extremo y luego con el perfil de energía crítico.
5. Ejecute una variante de ausencia prolongada: deje el iPhone fuera de alcance
   durante dos horas. Después de cuatro minutos, confirme que la conversación
   permanece pero el peer figura desconectado. Envíe un marcador y compruebe que
   queda pendiente con un ID estable, sin intento de envío nativo.
6. Al volver el iPhone, confirme la secuencia alcanzable/no seguro → handshake
   nuevo → seguro. El pendiente debe salir con el mismo ID una sola vez; un
   segundo `ANNOUNCE` dentro de cuatro minutos no debe volver a invalidar Noise.

**PASS:** el peer cambia de desconectado a reconectando y seguro; Noise se
renegocia automáticamente, la vista no se cierra, cada marcador se entrega una
sola vez, ningún marcador se registra como enviado mientras el peer está stale
y el peer conocido recibe prioridad sin esperar el ciclo completo de ahorro.

**FAIL:** BitChat solo reaparece al borrar identidad o reabrir manualmente el
chat, hay error de identidad/Noise, pérdida, duplicado o conexión repetitiva.

## Segundo plano y bloqueo de pantalla

1. Con un canal seguro establecido, envíe HearthBit o BitChat al segundo plano y
   bloquee el iPhone durante diez minutos. No cierre la app desde el selector.
2. Envíe un marcador desde el otro teléfono y luego realice la desconexión de
   Bluetooth de 30 segundos. Reactive Bluetooth sin desbloquear ni abrir la app.
3. Repita con HearthBit iOS en segundo plano y después con BitChat iOS en
   segundo plano. Mantenga una ejecución de al menos 25 minutos.
4. Registre estado foreground/background, hora UTC y si iOS suspendió o terminó
   el proceso. No interprete una terminación del sistema como entrega correcta.

**PASS:** dentro de las capacidades que iOS conceda al proceso, el peer se
mantiene o reaparece sin abrir la app, el canal se recupera sin tormenta de
conexiones y el marcador se muestra una sola vez al volver al primer plano.

**FAIL:** con el proceso aún vivo y permisos concedidos, el escaneo queda
detenido, hay reconexiones repetitivas, pérdida o duplicado. Si el usuario cerró
la app o iOS la terminó, marque `BLOCKED`, no PASS ni FAIL de radio.

## Outbox privado persistente y entrega once-only

1. Conserve una identidad segura conocida y desconecte al destinatario.
2. Envíe tres marcadores privados distintos desde HearthBit iOS. Confirme que
   quedan pendientes; no pulse enviar más de una vez por marcador.
3. Termine y vuelva a abrir HearthBit iOS antes de reconectar. Compruebe que los
   tres pendientes siguen visibles y en el mismo orden.
4. Reconecte el destinatario y espere el canal seguro. No reenvíe manualmente.
5. Cierre y abra ambas apps una vez más para detectar reintentos tardíos.

**PASS:** los tres IDs sobreviven al reinicio, salen solo después de recuperar
un peer seguro, cada ID aparece exactamente una vez en el destinatario y deja
de figurar como pendiente en el emisor.

**FAIL:** un pendiente desaparece antes de envío, se envía sin canal seguro,
cambia de destinatario, altera el orden, se pierde o aparece más de una vez.
Una captura sin conteo visual por ID no demuestra semántica once-only.

## Baliza física dirigida

1. En primer plano, solicite desde `HB-B` la baliza de `IOS-A`. Antes de aceptar,
   confirme que linterna, sonido y vibración siguen apagados.
2. Rechace la primera solicitud: no debe activarse ningún actuador.
3. Envíe una nueva solicitud, acepte explícitamente y observe el patrón SOS.
   Deténgalo desde iOS y confirme que la linterna se apaga de inmediato.
4. Repita con duración corta y deje expirar. Envíe una solicitud vencida,
   malformada o de más de cinco minutos si el cliente de prueba lo permite.
5. Active una baliza y mande la app al segundo plano: iOS debe detenerla de
   forma segura, pues el actuador solo opera con la app activa.

**PASS:** ninguna solicitud actúa sin consentimiento vigente; rechazo, parada,
expiración y segundo plano apagan la linterna; una solicitud válida dura como
máximo cinco minutos y las inválidas no se ejecutan.

**FAIL:** activación sin consentimiento, duración superior a cinco minutos,
linterna encendida tras detener/expirar/pasar a segundo plano, destinatario
equivocado o ejecución de una solicitud inválida.

## Mapa, ubicación y uso sin internet

1. Con internet y ubicación permitida, abra el mapa en iOS, centre «Mi
   ubicación» y descargue el área visible. No use una ubicación privada en la
   evidencia; registre solo precisión y distancia aproximadas.
2. Active modo avión y vuelva a habilitar únicamente Bluetooth. Abra de nuevo
   el mapa y confirme que los mosaicos descargados siguen disponibles.
3. Desde `HB-B`, envíe un SOS o check-in sintético con ubicación. Confirme en
   iOS el incidente, marcador, hora y distancia aproximada.
4. Con consentimiento de radar vigente, mueva `HB-B` una distancia medible y
   confirme actualización del marcador/trayecto. Revoque el consentimiento y
   verifique que dejan de llegar posiciones en vivo.
5. Bloquee y desbloquee iOS con permiso «Siempre» y modo rescate activo. Registre
   si la ubicación se actualiza; no asuma que `UIBackgroundModes` prueba la
   ejecución real.

**PASS:** posición local e incidente correcto aparecen sin intercambiar
coordenadas con otro peer; el mapa descargado funciona sin internet; las
actualizaciones remotas requieren consentimiento y se detienen al revocarlo.

**FAIL:** marcador asignado al peer equivocado, mosaicos descargados ausentes,
distancia incoherente, ubicación en vivo sin consentimiento o actualización
después de revocarlo. Si el sistema niega ubicación o falta señal GPS, marque
`BLOCKED`.

## Evidencia y decisión

Por caso, devuelva:

- `capture.json` y el log saneado cuyo SHA-256 coincida.
- Alias, modelos/versión de iOS, build, tiempos UTC, distancia aproximada y
  estados foreground/background.
- IDs sintéticos y conteo visual de apariciones por emisor y receptor.
- Resultado declarado `PASS`, `FAIL` o `BLOCKED` contra **todos** los criterios,
  con el primer criterio incumplido o bloqueo concreto.

No adjunte capturas con notificaciones, nombres personales o mapas que revelen
una ubicación exacta. Actualice `docs/field-test.md` únicamente con hechos
observados y nunca convierta una compilación o un log aislado en PASS físico.

