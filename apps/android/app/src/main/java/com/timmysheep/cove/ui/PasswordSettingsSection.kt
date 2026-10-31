package com.timmysheep.cove.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.R
import com.timmysheep.cove.data.SessionState
import kotlinx.coroutines.launch

@Composable
internal fun PasswordSettingsSection(state: SessionState, model: CoveViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var currentPassword by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    val canSubmit = currentPassword.length in 4..128 &&
        newPassword.length in 4..128 &&
        confirmPassword.length in 4..128 &&
        newPassword == confirmPassword &&
        newPassword != currentPassword &&
        !isSaving

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            text = stringResource(R.string.password_settings_title),
            style = MaterialTheme.typography.titleLarge
        )
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                if (!state.ownUserPasswordSet) {
                    Text(
                        text = stringResource(R.string.password_managed_by_identity_provider),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    OutlinedTextField(
                        value = currentPassword,
                        onValueChange = { currentPassword = it.take(128) },
                        label = { Text(stringResource(R.string.current_password)) },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = newPassword,
                        onValueChange = { newPassword = it.take(128) },
                        label = { Text(stringResource(R.string.new_password)) },
                        supportingText = {
                            Text(stringResource(R.string.password_length_hint))
                        },
                        isError = newPassword.isNotEmpty() && newPassword.length < 4,
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = confirmPassword,
                        onValueChange = { confirmPassword = it.take(128) },
                        label = { Text(stringResource(R.string.confirm_new_password)) },
                        supportingText = {
                            if (confirmPassword.isNotEmpty() && confirmPassword != newPassword) {
                                Text(stringResource(R.string.passwords_do_not_match))
                            }
                        },
                        isError = confirmPassword.isNotEmpty() && confirmPassword != newPassword,
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        modifier = Modifier.fillMaxWidth()
                    )
                    Button(
                        onClick = {
                            scope.launch {
                                isSaving = true
                                val updated = model.updateOwnPassword(currentPassword, newPassword, confirmPassword)
                                isSaving = false
                                if (updated) {
                                    currentPassword = ""
                                    newPassword = ""
                                    confirmPassword = ""
                                    val message = if (model.credentialStorageFailed.value) {
                                        R.string.password_updated_saved_login_removed
                                    } else {
                                        R.string.password_updated
                                    }
                                    Toast.makeText(context, message, Toast.LENGTH_LONG).show()
                                } else {
                                    Toast.makeText(context, R.string.password_update_failed, Toast.LENGTH_LONG).show()
                                }
                            }
                        },
                        enabled = canSubmit
                    ) {
                        if (isSaving) {
                            CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                        } else {
                            Text(stringResource(R.string.update_password))
                        }
                    }
                }
            }
        }
    }
}
