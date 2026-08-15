package com.hearthbit.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class EmergencySmsPolicyTest {
    @Test
    fun `normaliza el mismo formato aceptado por Flutter`() {
        assertEquals("+56912345678", normalizeNativeSmsRecipient(" (+56) 9-1234-5678 "))
        assertEquals("13100", normalizeNativeSmsRecipient("13 100"))
    }

    @Test
    fun `rechaza esquemas letras y longitudes fuera de rango`() {
        assertNull(normalizeNativeSmsRecipient("smsto:+56912345678"))
        assertNull(normalizeNativeSmsRecipient("+56CALLHELP"))
        assertNull(normalizeNativeSmsRecipient("1234"))
        assertNull(normalizeNativeSmsRecipient("+1234567890123456"))
    }
}
