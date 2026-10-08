package com.timmysheep.cove.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.timmysheep.cove.R

@Composable
internal fun SessionRecoveryScreen(
    error: String?,
    isConnecting: Boolean,
    canRetry: Boolean,
    onReconnect: () -> Unit,
    onDisconnect: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .safeDrawingPadding()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = stringResource(if (isConnecting) R.string.connecting else R.string.offline),
            style = MaterialTheme.typography.headlineSmall
        )

        if (isConnecting) {
            Spacer(Modifier.height(20.dp))
            CircularProgressIndicator()
        }

        if (!error.isNullOrBlank()) {
            Spacer(Modifier.height(20.dp))
            Text(
                text = error,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodyMedium
            )
        }

        if (canRetry) {
            Spacer(Modifier.height(20.dp))
            Button(onClick = onReconnect, enabled = !isConnecting) {
                Text(stringResource(R.string.connect))
            }
        }

        Spacer(Modifier.height(8.dp))
        TextButton(onClick = onDisconnect) {
            Text(stringResource(R.string.disconnect))
        }
    }
}
