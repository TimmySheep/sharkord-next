package com.timmysheep.cove

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.timmysheep.cove.ui.ConnectScreen
import com.timmysheep.cove.ui.CoveTheme
import com.timmysheep.cove.ui.WorkspaceScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
