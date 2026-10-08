package com.timmysheep.cove.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class SessionScreenDestinationTest {
    @Test
    fun connectedSessionsShowTheWorkspace() {
        assertEquals(
            SessionScreenDestination.WORKSPACE,
            sessionScreenDestination(
                isConnected = true,
                hasSavedLogin = true,
                hasActiveSession = true,
                userRequestedDisconnect = false
            )
        )
    }

    @Test
    fun savedCredentialsUseRecoveryInsteadOfTheLoginForm() {
        assertEquals(
            SessionScreenDestination.RECOVERY,
            sessionScreenDestination(
                isConnected = false,
                hasSavedLogin = true,
                hasActiveSession = false,
                userRequestedDisconnect = false
            )
        )
    }

    @Test
    fun interruptedActiveSessionsUseRecoveryEvenWithoutSavedCredentials() {
        assertEquals(
            SessionScreenDestination.RECOVERY,
            sessionScreenDestination(
                isConnected = false,
                hasSavedLogin = false,
                hasActiveSession = true,
                userRequestedDisconnect = false
            )
        )
    }

    @Test
    fun explicitDisconnectShowsTheLoginForm() {
        assertEquals(
            SessionScreenDestination.CONNECT,
            sessionScreenDestination(
                isConnected = false,
                hasSavedLogin = true,
                hasActiveSession = false,
                userRequestedDisconnect = true
            )
        )
    }

    @Test
    fun firstLaunchWithoutCredentialsShowsTheLoginForm() {
        assertEquals(
            SessionScreenDestination.CONNECT,
            sessionScreenDestination(
                isConnected = false,
                hasSavedLogin = false,
                hasActiveSession = false,
                userRequestedDisconnect = false
            )
        )
    }
}
