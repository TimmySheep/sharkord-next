package com.timmysheep.cove.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.R
import com.timmysheep.cove.data.SearchFile
import com.timmysheep.cove.data.SearchMessage
import com.timmysheep.cove.data.SessionState
import kotlinx.coroutines.delay

@Composable
fun MessageSearchScreen(
    state: SessionState,
    model: CoveViewModel,
    onOpenMessage: (SearchMessage) -> Unit,
    onOpenFile: (SearchFile) -> Unit
) {
    var query by rememberSaveable { mutableStateOf("") }

    LaunchedEffect(query) {
        val normalized = query.trim()
        model.clearSearch()
        if (normalized.length < 2) {
            return@LaunchedEffect
        } else {
            delay(350)
            model.searchMessages(normalized)
        }
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            shape = MaterialTheme.shapes.large,
            modifier = Modifier.fillMaxWidth(),
            label = { Text(stringResource(R.string.search_messages)) },
            placeholder = { Text(stringResource(R.string.search_messages_hint)) },
            singleLine = true
        )

        val result = state.searchResult
        if (state.searchError != null) {
            Text(state.searchError, color = MaterialTheme.colorScheme.error)
        } else if (state.isSearching || query.trim().length >= 2 && result == null) {
            Text(stringResource(R.string.searching), color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else if (result != null && result.messages.isEmpty() && result.files.isEmpty()) {
            Text(stringResource(R.string.no_search_results), color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else if (result != null) {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (result.messages.isNotEmpty()) {
                    item(key = "message-heading") {
                        Text(stringResource(R.string.search_messages), style = MaterialTheme.typography.titleSmall)
                    }
                    items(result.messages, key = { "message-${it.id}" }) { message ->
                        SearchResultCard(
                            title = "#${message.channelName}",
                            body = message.plainContent,
                            modifier = Modifier.clickable { onOpenMessage(message) }
                        )
                    }
                }
                if (result.files.isNotEmpty()) {
                    item(key = "file-heading") {
                        Text(stringResource(R.string.search_files), style = MaterialTheme.typography.titleSmall)
                    }
                    items(result.files, key = { "file-${it.file.id}-${it.messageId}" }) { match ->
                        SearchResultCard(
                            title = "#${match.channelName} · ${match.file.originalName}",
                            body = match.messageContent?.let(::htmlToPlainText).orEmpty(),
                            modifier = Modifier.clickable { onOpenFile(match) }
                        )
                    }
                }
                if (result.truncated) {
                    item(key = "truncated") {
                        Text(stringResource(R.string.search_results_truncated), style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
}

@Composable
private fun SearchResultCard(title: String, body: String, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerLow
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Text(body.ifBlank { stringResource(R.string.attachment) }, maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
    }
}
