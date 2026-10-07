package com.timmysheep.cove

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.timmysheep.cove.data.AppDiagnosticsLog
import com.timmysheep.cove.ui.ConnectScreen
import com.timmysheep.cove.ui.CoveTheme
import com.timmysheep.cove.ui.WorkspaceScreen

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
            val credentialStorageFailed = model.credentialStorageFailed.collectAsStateWithLifecycle().value

            CoveTheme {
                if (state.connected) {
                    WorkspaceScreen(state = state, model = model)
                } else {
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
        }
    }
}
