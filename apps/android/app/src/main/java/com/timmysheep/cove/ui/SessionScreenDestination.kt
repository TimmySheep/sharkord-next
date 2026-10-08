package com.timmysheep.cove.ui

internal enum class SessionScreenDestination {
    WORKSPACE,
    RECOVERY,
    CONNECT
}

internal fun sessionScreenDestination(
    isConnected: Boolean,
    hasSavedLogin: Boolean,
    hasActiveSession: Boolean,
    userRequestedDisconnect: Boolean
): SessionScreenDestination = when {
    isConnected -> SessionScreenDestination.WORKSPACE
    userRequestedDisconnect -> SessionScreenDestination.CONNECT
    hasSavedLogin || hasActiveSession -> SessionScreenDestination.RECOVERY
    else -> SessionScreenDestination.CONNECT
}
