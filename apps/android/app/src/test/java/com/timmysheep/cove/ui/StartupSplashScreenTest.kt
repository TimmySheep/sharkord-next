package com.timmysheep.cove.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StartupSplashScreenTest {
    @Test
    fun startupLogoEntranceUsesNonLinearEasing() {
        assertTrue(startupSplashEnterEasing.transform(0.5f) > 0.5f)
    }

    @Test
    fun startupLogoExitAcceleratesAsItMovesDown() {
        assertTrue(startupSplashExitEasing.transform(0.5f) < 0.5f)
        assertEquals(1f, startupSplashExitEasing.transform(1f), 0f)
    }

    @Test
    fun startupLogoExitDistanceMovesTheWholeIconPastTheBottomEdge() {
        val screenHeightPx = 2_000f
        val iconSizePx = 432f
        val exitDistance = startupSplashExitDistance(screenHeightPx, iconSizePx)
        val iconTopAfterExit = (screenHeightPx - iconSizePx) / 2f + exitDistance

        assertTrue(iconTopAfterExit > screenHeightPx)
    }
}
