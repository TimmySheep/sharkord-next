package com.timmysheep.cove.ui

import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Link
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.os.LocaleListCompat
import com.timmysheep.cove.BuildConfig
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.R
import com.timmysheep.cove.data.AppDiagnosticsLog
import com.timmysheep.cove.data.SessionState

private data class AppLanguage(val tag: String, val labelResource: Int)

private val appLanguages = listOf(
    AppLanguage("", R.string.system_default),
    AppLanguage("en", R.string.language_english),
    AppLanguage("zh-CN", R.string.language_chinese),
    AppLanguage("es", R.string.language_spanish),
    AppLanguage("fr", R.string.language_french),
    AppLanguage("de", R.string.language_german)
)

@Composable
fun SettingsDestination(state: SessionState, model: CoveViewModel) {
    val context = LocalContext.current
    var languageMenuOpen by remember { mutableStateOf(false) }
    var confirmDisconnect by rememberSaveable { mutableStateOf(false) }
    var showLogs by rememberSaveable { mutableStateOf(false) }
    var logText by remember { mutableStateOf("") }
    val exportFailedText = stringResource(R.string.diagnostics_export_failed)
    val exportLogsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("text/plain")
    ) { uri ->
        if (uri != null) {
            runCatching {
                val output = context.contentResolver.openOutputStream(uri)
                    ?: throw IllegalStateException("Could not open the selected file")
                output.use { it.write(AppDiagnosticsLog.exportText(context).toByteArray(Charsets.UTF_8)) }
            }.onFailure {
                AppDiagnosticsLog.error("export", "diagnostic log export failed", it)
                Toast.makeText(context, exportFailedText, Toast.LENGTH_LONG).show()
            }
        }
    }
    val selectedLanguage = AppCompatDelegate.getApplicationLocales().toLanguageTags()
        .substringBefore(',').ifBlank { "" }

    Column(modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 12.dp)) {
        Column(
            modifier = Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            ProfileSettingsSection(state, model)
            Text(
                text = stringResource(R.string.appearance),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold
            )
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.language)) },
                    leadingContent = { Icon(Icons.Default.Language, contentDescription = null) },
                    trailingContent = {
                        androidx.compose.foundation.layout.Box {
                            TextButton(onClick = { languageMenuOpen = true }) {
                                Text(stringResource(appLanguages.firstOrNull { it.tag.equals(selectedLanguage, ignoreCase = true) }?.labelResource ?: R.string.system_default))
                            }
                            DropdownMenu(
                                expanded = languageMenuOpen,
                                onDismissRequest = { languageMenuOpen = false }
                            ) {
                                appLanguages.forEach { language ->
                                    DropdownMenuItem(
                                        text = { Text(stringResource(language.labelResource)) },
                                        onClick = {
                                            languageMenuOpen = false
                                            AppCompatDelegate.setApplicationLocales(
                                                if (language.tag.isEmpty()) LocaleListCompat.getEmptyLocaleList()
                                                else LocaleListCompat.forLanguageTags(language.tag)
                                            )
                                        }
                                    )
                                }
                            }
                        }
                    }
                )
            }

            Text(
                text = stringResource(R.string.connection),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(top = 4.dp)
            )
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                ListItem(
                    headlineContent = { Text(state.serverName.ifBlank { stringResource(R.string.app_name) }) },
                    supportingContent = { Text(state.serverAddress) },
                    leadingContent = { Icon(Icons.Default.Link, contentDescription = null) }
                )
            }

            Text(
                text = stringResource(R.string.diagnostics_title),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(top = 4.dp)
            )
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                Column(modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.diagnostics_title)) },
                        supportingContent = { Text(stringResource(R.string.diagnostics_description)) },
                        leadingContent = { Icon(Icons.Default.Info, contentDescription = null) }
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        OutlinedButton(
                            onClick = {
                                logText = AppDiagnosticsLog.previewText(context)
                                showLogs = true
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(stringResource(R.string.view_logs))
                        }
                        OutlinedButton(
                            onClick = { exportLogsLauncher.launch("cove-logs.txt") },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(stringResource(R.string.export_logs))
                        }
                    }
                }
            }

            Text(
                text = stringResource(R.string.about),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(top = 4.dp)
            )
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.app_name)) },
                    supportingContent = {
                        Text(stringResource(R.string.app_version, BuildConfig.VERSION_NAME))
                    },
                    leadingContent = { Icon(Icons.Default.Info, contentDescription = null) }
                )
            }
        }

        OutlinedButton(
            onClick = { confirmDisconnect = true },
            modifier = Modifier.fillMaxWidth().padding(top = 18.dp)
        ) {
            Icon(Icons.AutoMirrored.Filled.Logout, contentDescription = null)
            Spacer(Modifier.width(10.dp))
            Text(stringResource(R.string.disconnect))
        }
    }

    if (showLogs) {
        AlertDialog(
            onDismissRequest = { showLogs = false },
            title = { Text(stringResource(R.string.diagnostics_title)) },
            text = {
                SelectionContainer {
                    Text(
                        text = logText.ifBlank { stringResource(R.string.no_diagnostics_logs) },
                        modifier = Modifier.heightIn(max = 380.dp).verticalScroll(rememberScrollState()),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { showLogs = false }) { Text(stringResource(R.string.cancel)) }
            }
        )
    }

    if (confirmDisconnect) {
        AlertDialog(
            onDismissRequest = { confirmDisconnect = false },
            title = { Text(stringResource(R.string.disconnect_confirm_title)) },
            text = { Text(stringResource(R.string.disconnect_confirm_body)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDisconnect = false
                    model.disconnect()
                }) { Text(stringResource(R.string.disconnect)) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDisconnect = false }) { Text(stringResource(R.string.cancel)) }
            }
        )
    }
}
