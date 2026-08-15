# Política de Privacidad de HearthBit

**Fecha de entrada en vigor:** 15 de agosto de 2026  
**Última actualización:** 15 de agosto de 2026

[English version](privacy-policy.md)

HearthBit es una aplicación de comunicación para emergencias que prioriza el
funcionamiento sin conexión y es mantenida por el proyecto HearthBit. Esta
política explica cómo HearthBit procesa información cuando utilizas la
aplicación móvil.

HearthBit no exige crear una cuenta y el responsable del proyecto no opera un
servidor central de mensajes, identidades ni analítica. La mayoría de la
información se procesa y almacena en tu dispositivo o se envía directamente a
los dispositivos y servicios que decides utilizar.

## Información que procesa HearthBit

### Identidad e información del dispositivo

HearthBit genera en tu dispositivo claves de identidad criptográfica y una
identidad de par. Tu apodo, claves públicas, capacidades del dispositivo,
tokens rotativos de descubrimiento y metadatos de radio o red pueden
intercambiarse con dispositivos compatibles cercanos para que puedan descubrir,
autenticar y comunicarse con tu dispositivo.

Los observadores cercanos pueden inferir que existe un dispositivo compatible
y observar la intensidad de señal y los horarios. El modo privado de HearthBit
reduce los identificadores persistentes durante el descubrimiento Bluetooth
normal, pero no puede garantizar el anonimato por radio. Activar la
interoperabilidad opcional con BitChat aumenta la información de identidad
visible para dispositivos compatibles.

### Mensajes, archivos, notas de voz y contactos de confianza

Los mensajes, elementos pendientes de la bandeja de salida, transferencias de
archivos, notas de voz y configuración familiar de confianza pueden guardarse
localmente para que HearthBit funcione sin internet. Los mensajes de canales
públicos y las alertas SOS públicas se comparten intencionalmente con los
participantes alcanzables de la malla. Los mensajes y transferencias privadas
utilizan sesiones autenticadas y cifradas.

HearthBit no solicita acceso a tu agenda de contactos. Si introduces el número
de teléfono de un contacto de confianza, se guarda localmente y solo se entrega
a la aplicación de mensajería que elijas cuando le pides a HearthBit preparar
un SMS. HearthBit no envía el SMS automáticamente.

### Ubicación

HearthBit puede procesar la ubicación precisa o aproximada para:

- adjuntar una ubicación a un SOS cuando eliges explícitamente ubicación
  exacta, aproximada o ninguna;
- actualizar las emisiones SOS del modo rescate y calcular la distancia del
  radar de rescate;
- proporcionar actualizaciones temporales de ubicación a familiares de
  confianza verificados; y
- mostrar mapas y guardar teselas para usarlas sin conexión.

En Android, HearthBit solicita ubicación en segundo plano porque el modo rescate
debe poder actualizar las coordenadas del SOS con la pantalla apagada. La
ubicación en segundo plano se utiliza para esta función de emergencia mientras
está activo el servicio en primer plano de malla/rescate, con una notificación
persistente del sistema. HearthBit no envía tu ubicación al responsable del
proyecto.

Un SOS público comparte intencionalmente la precisión de ubicación seleccionada
y la identidad criptográfica con los participantes alcanzables de la malla. Los
avisos familiares privados se envían por canales privados cifrados. El sistema
operativo puede conservar de forma independiente registros de permisos y
accesos a ubicación.

### Micrófono

El acceso al micrófono solo se utiliza cuando inicias una nota de voz o una
medición acústica de distancia opcional. Las notas de voz se almacenan
localmente y se envían al destinatario que seleccionas. La medición acústica
graba ventanas cortas de audio en memoria para detectar señales de distancia;
HearthBit no guarda intencionalmente esas ventanas como grabaciones de voz. El
audio no se envía al responsable del proyecto.

### Cámara

El acceso a la cámara se utiliza cuando eliges escanear códigos QR para
verificar familiares de confianza o realizar una transferencia óptica de
archivos. Los fotogramas se procesan en el dispositivo y no se envían al
responsable del proyecto.

### Bluetooth, dispositivos cercanos y redes locales

HearthBit utiliza Bluetooth Low Energy, Android Nearby Connections, Wi-Fi Aware,
conexiones LAN/hotspot y señales relacionadas para descubrir dispositivos
compatibles, retransmitir mensajes, estimar proximidad y transferir archivos.
Según el transporte seleccionado, los dispositivos cercanos y proveedores de
la plataforma pueden procesar identificadores del dispositivo, direcciones de
red y metadatos de radio o transferencia.

### Diagnósticos

HearthBit puede crear registros de diagnóstico en el dispositivo para ayudar a
explicar fallos. Estos registros no se suben automáticamente. Revisa y elimina
información personal o de emergencias antes de decidir compartir un informe de
diagnóstico.

## Acceso a internet y servicios de terceros

La malla local principal no necesita un servidor operado por HearthBit. Puede
haber acceso a la red cuando:

- cargas teselas de mapas en línea;
- utilizas un transporte del sistema operativo o de terceros, como Google Play
  Services Nearby;
- activas un gateway opcional MQTT, Matrix, Reticulum/LXMF o LAN;
- abres un enlace externo; o
- utilizas un servicio de donaciones o alojamiento del proyecto.

Estos proveedores pueden recibir información como tu dirección IP, la zona del
mapa solicitada, metadatos del dispositivo o red, identificadores, contenido de
mensajes o marcas de tiempo, según la función que actives. El tratamiento que
realizan se rige por sus propios términos y políticas de privacidad.

Los gateways opcionales trasladan intencionalmente mensajes fuera de la malla
local y cambian el límite de confianza. Sus operadores son responsables de
informar sobre el despliegue, proteger credenciales y registros, y cumplir la
legislación aplicable. Los puentes externos bloquean de forma predeterminada
las tramas de emergencia que contienen coordenadas, salvo que un operador
active explícitamente ese reenvío.

## Cómo se comparte la información

HearthBit solo comparte información cuando es necesario para las funciones que
activas:

- con participantes alcanzables de la malla cuando publicas un mensaje o SOS;
- con el destinatario seleccionado cuando envías un mensaje privado, archivo,
  nota de voz o actualización familiar;
- con dispositivos compatibles cercanos para descubrimiento, autenticación,
  enrutamiento y estimación de proximidad;
- con un gateway o servicio de terceros que activas; y
- con la aplicación de teléfono, SMS, archivos o navegador que eliges cuando
  inicias la acción correspondiente.

El responsable del proyecto HearthBit no vende información personal ni la usa
para publicidad o creación de perfiles de comportamiento.

## Almacenamiento, seguridad y conservación

HearthBit guarda datos operativos en tu dispositivo para funcionar sin
conexión. Las claves de identidad y otros secretos utilizan almacenamiento
protegido por la plataforma cuando está disponible. Los archivos y notas de voz
recibidos bajo el control de la app se cifran en reposo y pueden descifrarse
temporalmente para reproducirlos o exportarlos. Ningún mecanismo de seguridad
puede proteger la información después de que se compromete un dispositivo,
destinatario, gateway o clave de firma.

Los datos permanecen en tu dispositivo hasta que los eliminas, utilizas el
borrado de emergencia de HearthBit, borras los datos de la app o desinstalas la
app, sujeto al comportamiento del sistema operativo. El borrado de emergencia
elimina identidades, estado de confianza, mensajes, transferencias,
preferencias, cachés y archivos temporales conocidos que controla HearthBit. No
puede eliminar copias ya entregadas a otro dispositivo o servicio ni garantizar
su eliminación de copias de seguridad del sistema operativo, historial de
notificaciones o archivos exportados.

## Tus opciones

Puedes:

- denegar permisos opcionales, aunque la función relacionada no estará
  disponible;
- elegir ubicación exacta, aproximada o ninguna antes de un SOS público;
- desactivar el modo rescate, gateways opcionales, interoperabilidad y medición
  acústica;
- eliminar contenido individual cuando la app ofrece ese control;
- utilizar el borrado de emergencia para eliminar datos locales controlados por
  HearthBit; y
- borrar los datos de la app o desinstalar HearthBit desde el sistema operativo.

## Privacidad de menores

HearthBit no está diseñada para recopilar información personal de menores para
el responsable del proyecto. Debido a que los mensajes de emergencia pueden
revelar información sensible a otros dispositivos, un padre, madre o tutor debe
supervisar el uso por parte de un menor y revisar las opciones de ubicación y
comunicación.

## Limitaciones de emergencia y seguridad

HearthBit no es un sistema médico, de navegación, de servicios de emergencia ni
de seguridad pública certificado. No garantiza la entrega, la precisión de las
mediciones, el anonimato por radio ni la disponibilidad. Contacta con los
servicios de emergencia oficiales siempre que estén disponibles.

## Cambios en esta política

Los cambios importantes se publicarán en esta página con una nueva fecha de
“Última actualización”. La versión disponible en esta URL se aplica a la
versión pública actual, salvo que las notas de la versión indiquen lo contrario.

## Contacto

Para consultas de privacidad, contacta con el responsable de HearthBit mediante
el canal de contacto verificado del
[perfil de GitHub del propietario del repositorio](https://github.com/waar19).
No publiques ubicaciones, claves privadas, grabaciones, mensajes de emergencia
ni otra información sensible en una incidencia pública. Las vulnerabilidades de
seguridad deben comunicarse mediante el
[formulario privado de avisos de seguridad](https://github.com/waar19/HearthBit/security/advisories/new).

Encontrarás detalles técnicos adicionales en el
[documento de transparencia de HearthBit](transparency.es.md).
