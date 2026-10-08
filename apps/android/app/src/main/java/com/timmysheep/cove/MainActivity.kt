package com.timmysheep.cove

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.timmysheep.cove.data.AppDiagnosticsLog
import com.timmysheep.cove.ui.ConnectScreen
import com.timmysheep.cove.ui.CoveTheme
import com.timmysheep.cove.ui.SessionRecoveryScreen
import com.timmysheep.cove.ui.SessionScreenDestination
import com.timmysheep.cove.ui.StartupSplashScreen
import com.timmysheep.cove.ui.WorkspaceScreen
import com.timmysheep.cove.ui.sessionScreenDestination

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppDiagnosticsLog.initialize(this)
        AppDiagnosticsLog.info("lifecycle", "main activity created")
        enableEdgeToEdge()
        setContent {
            val model: CoveViewModel = viewModel()
            val state = model.state.collectAsStateWithLifecycle().value
            val hasSavedLogin = model.hasSavedLogin.collectAsStateWithLifecycle().value
            val hasActiveSession = model.hasActiveSession.collectAsStateWithLifecycle().value
            val credentialStorageFailed = model.credentialStorageFailed.collectAsStateWithLifecycle().value
            val startupReady = model.startupReady.collectAsStateWithLifecycle().value
            val userRequestedDisconnect = model.userRequestedDisconnect.collectAsStateWithLifecycle().value
            val lifecycleOwner = LocalLifecycleOwner.current

            CoveTheme {
                var showStartupSplash by remember { mutableStateOf(true) }
                var wasPaused by remember { mutableStateOf(false) }

                DisposableEffect(lifecycleOwner) {
                    val observer = LifecycleEventObserver { _, event ->
                        when (event) {
                            Lifecycle.Event.ON_PAUSE -> wasPaused = true
                            Lifecycle.Event.ON_RESUME -> {
                                if (wasPaused) {
                                    wasPaused = false
                                    showStartupSplash = true
                                }
                            }
                            else -> Unit
                        }
                    }
                    lifecycleOwner.lifecycle.addObserver(observer)
                    onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
                }

                Box(modifier = Modifier.fillMaxSize()) {
                    when (
                        sessionScreenDestination(
                            isConnected = state.connected,
                            hasSavedLogin = hasSavedLogin,
                            hasActiveSession = hasActiveSession,
                            userRequestedDisconnect = userRequestedDisconnect
                        )
                    ) {
                        SessionScreenDestination.WORKSPACE -> {
                            WorkspaceScreen(state = state, model = model)
                        }
                        SessionScreenDestination.CONNECT -> {
                            if (!showStartupSplash && startupReady) {
                                ConnectScreen(
                                    state = state,
                                    hasSavedLogin = hasSavedLogin,
                                    credentialStorageFailed = credentialStorageFailed,
                                    onConnect = model::connect,
                                    onQuickConnect = model::connectSavedLogin,
                                    onForgetSavedLogin = model::forgetSavedLogin
                                )
                            }
                        }
                        SessionScreenDestination.RECOVERY -> {
                            if (!showStartupSplash && startupReady) {
                                SessionRecoveryScreen(
                                    error = state.error,
                                    isConnecting = state.connecting,
                                    canRetry = hasSavedLogin,
                                    onReconnect = { model.connectSavedLogin(rememberLogin = true) },
                                    onDisconnect = model::disconnect
                                )
                            }
                        }
                    }

                    if (showStartupSplash || !startupReady) {
                        StartupSplashScreen(isReady = startupReady) {
                            showStartupSplash = false
                        }
                    }
                }
            }
        }
    }
}
