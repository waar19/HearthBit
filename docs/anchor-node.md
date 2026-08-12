# Nodo ancla ESP32

El firmware fijado en `firmware/anchor-node` es Bitle. Funciona en ESP32-C3 y
ESP32-S3 con ESP-IDF 6, anuncia el servicio BitChat, ejecuta Noise XX, retransmite
paquetes y mantiene correo cifrado store-and-forward.

## Hardware recomendado

- Seeed XIAO ESP32-C3 con antena de 2,4 GHz para una casa.
- Alimentación USB estable, o batería LiPo con cargador y panel solar.
- Caja ventilada para interior o caja IP65 con control térmico para exterior.
- ESP32-S3 + SX1262 solo si se necesita un troncal LoRa entre barrios.

En Colombia, verifique con la ANE la frecuencia y potencia permitidas antes de
activar LoRa. El perfil Bitle documenta 915 MHz; no asuma que una configuración
de otro país es legal localmente.

## Preparación

```powershell
git submodule update --init --recursive
cd firmware\anchor-node
idf.py set-target esp32c3
idf.py build
idf.py -p COM5 flash monitor
```

Cambie `COM5` por el puerto real. Para ESP32-S3 use `idf.py set-target esp32s3`.

## Claves OTA

Antes de sellar una flota propia, genere su clave de propietario:

```powershell
python tools\gen_owner_key.py
```

No confirme la clave privada en Git ni la copie a los nodos. Guárdela offline
con respaldo. Perderla impide futuras actualizaciones; filtrarla permite a un
atacante firmar firmware para toda la flota.

## Despliegue

1. Pruebe cada nodo durante 24 horas antes de instalarlo.
2. Colóquelo alto, alejado de metal, hornos microondas y routers saturados.
3. Mantenga línea de vista hacia calles o casas vecinas cuando sea posible.
4. Registre coordenadas y responsable, pero no publique claves ni direcciones
   personales.
5. Revalide cobertura y batería cada tres meses.

El firmware y sus instrucciones completas conservan la licencia MIT y
atribución del proyecto Bitle dentro del submódulo.
