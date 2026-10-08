package com.timmysheep.cove.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProfileSettingsTest {
    @Test
    fun acceptsServerSupportedProfileColors() {
        assertTrue(isValidProfileColor("#abc"))
        assertTrue(isValidProfileColor("#A1b2C3"))
    }

    @Test
    fun rejectsColorsTheServerWouldReject() {
        assertFalse(isValidProfileColor("#12"))
        assertFalse(isValidProfileColor("red"))
        assertFalse(isValidProfileColor("#12345678"))
    }
}
