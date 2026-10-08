package com.timmysheep.cove.ui

import org.junit.Assert.assertTrue
import org.junit.Test

class StartupSplashScreenTest {
    @Test
    fun startupLogoEntranceUsesNonLinearEasing() {
        assertTrue(startupSplashEnterEasing.transform(0.5f) > 0.5f)
    }

    @Test
    fun startupLogoExitUsesNonLinearEasing() {
        assertTrue(startupSplashExitEasing.transform(0.5f) > 0.5f)
    }
}
