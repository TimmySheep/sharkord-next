package com.timmysheep.cove.ui

import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.os.LocaleListCompat
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.R
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
    var languageMenuOpen by remember { mutableStateOf(false) }
    var confirmDisconnect by rememberSaveable { mutableStateOf(false) }
    val selectedLanguage = AppCompatDelegate.getApplicationLocales().toLanguageTags()
        .substringBefore(',').ifBlank { "" }

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        Text(
            text = stringResource(R.string.appearance),
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold
        )
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
            ListItem(
                headlineContent = { Text(stringResource(R.string.language)) },
                supportingContent = { Text(stringResource(R.string.system_default)) },
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
            Column {
                ListItem(
                    headlineContent = { Text(state.serverName.ifBlank { stringResource(R.string.app_name) }) },
                    supportingContent = { Text(state.serverAddress) },
                    leadingContent = { Icon(Icons.Default.Link, contentDescription = null) }
                )
            }
        }

        Spacer(Modifier.weight(1f))
        OutlinedButton(
            onClick = { confirmDisconnect = true },
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.AutoMirrored.Filled.Logout, contentDescription = null)
            Spacer(Modifier.width(10.dp))
            Text(stringResource(R.string.disconnect))
        }
        Text(
            text = stringResource(R.string.about),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.fillMaxWidth()
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
