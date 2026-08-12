# Perfil compatible con BitChat

HearthBit usa el UUID principal de BitChat:

- Servicio: `F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C`
- Característica: `A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D`

La característica acepta `write`, `write without response` y `notify`.

## Paquete v1

Los enteros usan orden big-endian.

1. Versión: 1 byte (`0x01`)
2. Tipo: 1 byte
3. TTL: 1 byte
4. Timestamp Unix en milisegundos: 8 bytes
5. Flags: 1 byte
6. Longitud de payload: 2 bytes
7. Sender ID: 8 bytes
8. Recipient ID: 8 bytes, si `flags & 0x01`
9. Payload
10. Firma Ed25519: 64 bytes, si `flags & 0x02`

Tipos implementados:

- `0x01`: anuncio de identidad TLV
- `0x02`: mensaje público
- `0x10`: handshake Noise XX
- `0x11`: transporte Noise cifrado

Los tamaños se normalizan a 256, 512, 1024 o 2048 bytes mediante padding
PKCS#7 cuando la diferencia cabe en un byte.

## Seguridad

Las firmas se calculan sobre el paquete sin firma y con TTL igual a cero. Así
los relés pueden reducir TTL sin invalidar la firma. Un anuncio se acepta solo
si su clave Noise produce el sender ID y su propia clave Ed25519 valida la
firma.

Los chats privados usan `Noise_XX_25519_ChaChaPoly_SHA256`. El payload de
transporte antepone un nonce UInt32 big-endian al ciphertext. El contenido
privado empieza con tipo `0x01` y contiene TLV `0x00` para ID y `0x01` para
texto.

La fuente normativa fijada para interoperabilidad está en
`vendor/bitchat-android`.
