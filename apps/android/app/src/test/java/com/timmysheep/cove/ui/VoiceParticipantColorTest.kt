package com.timmysheep.cove.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceParticipantColorTest {
    @Test
    fun choosesTheDominantAvatarTone() {
        val dominantColor = 0xFFCC8844.toInt()
        val samples = IntArray(12) { dominantColor } + IntArray(3) { 0xFF3355CC.toInt() }

        assertEquals(dominantColor, avatarTileBackgroundColor(samples, 0xFF202126.toInt()))
    }

    @Test
    fun adjustsSimilarAvatarAndSurfaceColorsToRemainDistinct() {
        val background = 0xFF303030.toInt()
        val result = avatarTileBackgroundColor(IntArray(16) { 0xFF333333.toInt() }, background)

        assertNotNull(result)
        assertTrue(colorContrastRatio(requireNotNull(result), background) >= 3.0)
    }

    @Test
    fun choosesReadableForegroundColorForTheAvatarCard() {
        val foreground = avatarTileForegroundColor(0xFF8A4D31.toInt())

        assertTrue(colorContrastRatio(foreground, 0xFF8A4D31.toInt()) >= 4.5)
    }

    @Test
    fun ignoresFullyTransparentSamples() {
        assertNull(avatarTileBackgroundColor(intArrayOf(0x00112233), 0xFF202126.toInt()))
    }
}
