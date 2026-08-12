package com.hearthbit.app.mesh

/**
 * Presupuesto de bytes del anuncio BLE legado (31 bytes por PDU).
 *
 * Cada campo AD cuesta 2 bytes de cabecera (longitud + tipo) más su contenido.
 * Android añade además el campo de banderas (3 bytes) al anuncio conectable.
 * BitChat resuelve el límite repartiendo los campos entre el anuncio y la
 * respuesta de escaneo; este objeto documenta ese reparto y permite probarlo
 * sin depender de clases de Android.
 */
internal object MeshAdvertisePlan {
    const val LEGACY_PDU_LIMIT_BYTES = 31

    const val FLAGS_FIELD_BYTES = 3
    const val AD_FIELD_HEADER_BYTES = 2
    const val SERVICE_UUID_BYTES = 16
    const val PEER_ID_BYTES = 8

    /** Anuncio principal: banderas + UUID de servicio de 128 bits. */
    const val ADVERTISEMENT_BYTES =
        FLAGS_FIELD_BYTES + AD_FIELD_HEADER_BYTES + SERVICE_UUID_BYTES

    /** Respuesta de escaneo: service data = UUID + peerId (sin banderas). */
    const val SCAN_RESPONSE_BYTES =
        AD_FIELD_HEADER_BYTES + SERVICE_UUID_BYTES + PEER_ID_BYTES

    /** Distribución previa (todo en un PDU) que provocaba el fallo código 1. */
    const val LEGACY_SINGLE_PDU_BYTES =
        FLAGS_FIELD_BYTES +
            AD_FIELD_HEADER_BYTES + SERVICE_UUID_BYTES +
            AD_FIELD_HEADER_BYTES + SERVICE_UUID_BYTES + PEER_ID_BYTES
}
