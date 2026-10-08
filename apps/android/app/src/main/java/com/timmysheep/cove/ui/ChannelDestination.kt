package com.timmysheep.cove.ui

import android.Manifest
import android.content.pm.PackageManager
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Tag
import androidx.compose.material3.Badge
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.compose.foundation.layout.BoxWithConstraints
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.R
import com.timmysheep.cove.data.Channel
import com.timmysheep.cove.data.ChannelType
import com.timmysheep.cove.data.Category
import com.timmysheep.cove.data.SessionState

@Composable
fun ChannelDestination(
    state: SessionState,
    model: CoveViewModel,
    selectedChannel: Channel?,
    searchMode: Boolean = false,
    onSearchResultSelected: () -> Unit = {}
) {
    val context = LocalContext.current
    var query by rememberSaveable { mutableStateOf("") }
    var voicePreviewChannelId by rememberSaveable { mutableStateOf<Int?>(null) }
    val microphoneEnabledOnJoin by model.microphoneEnabledOnJoin.collectAsStateWithLifecycle()
    val microphonePermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) model.setMicrophoneEnabledOnJoin(true)
        else Toast.makeText(context, R.string.microphone_permission_denied, Toast.LENGTH_LONG).show()
    }
    val matches = remember(state.channels, query) {
        state.channels.filter { !it.isDm && it.name.contains(query.trim(), ignoreCase = true) }
    }
    val onChannelSelected: (Int) -> Unit = { channelId ->
        val channel = state.channels.firstOrNull { it.id == channelId }
        if (channel?.type == ChannelType.VOICE) {
            voicePreviewChannelId = channelId
        } else {
            if (searchMode) onSearchResultSelected()
            model.selectChannel(channelId)
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        if (maxWidth >= 840.dp) {
            Row(Modifier.fillMaxSize()) {
                ChannelListPanel(
                    state = state,
                    model = model,
                    channels = matches,
                    query = query,
                    showSearchField = searchMode,
                    onQueryChange = { query = it },
                    onChannelSelected = onChannelSelected,
                    modifier = Modifier.width(340.dp).fillMaxHeight()
                )
                VerticalDivider()
                if (selectedChannel != null) {
                    ChannelChatScreen(state = state, model = model, channel = selectedChannel)
                } else {
                    EmptyContent(
                        title = stringResource(R.string.select_channel_title),
                        body = stringResource(R.string.select_channel_body),
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        } else if (selectedChannel != null && !searchMode) {
            ChannelChatScreen(state = state, model = model, channel = selectedChannel)
        } else {
            ChannelListPanel(
                state = state,
                model = model,
                channels = matches,
                query = query,
                showSearchField = searchMode,
                onQueryChange = { query = it },
                onChannelSelected = onChannelSelected,
                modifier = Modifier.fillMaxSize()
            )
        }
    }

    state.channels.firstOrNull { it.id == voicePreviewChannelId }?.let { channel ->
        VoiceChannelPreviewSheet(
            channel = channel,
            state = state,
            onDismiss = { voicePreviewChannelId = null },
            onJoin = {
                voicePreviewChannelId = null
                model.joinVoice(channel.id)
            },
            onOpenChat = {
                voicePreviewChannelId = null
                if (searchMode) onSearchResultSelected()
                model.selectChannel(channel.id)
            },
            microphoneEnabledOnJoin = microphoneEnabledOnJoin,
            onToggleMicrophoneOnJoin = {
                if (microphoneEnabledOnJoin) {
                    model.setMicrophoneEnabledOnJoin(false)
                } else if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                    model.setMicrophoneEnabledOnJoin(true)
                } else {
                    microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
                }
            }
        )
    }
}

@Composable
private fun ChannelListPanel(
    state: SessionState,
    model: CoveViewModel,
    channels: List<Channel>,
    query: String,
    showSearchField: Boolean,
    onQueryChange: (String) -> Unit,
    onChannelSelected: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val byCategory = remember(channels) { channels.filter { it.categoryId != null }.groupBy(Channel::categoryId) }
    val uncategorized = remember(channels) { channels.filter { it.categoryId == null } }

    Column(modifier = modifier.padding(horizontal = 16.dp)) {
        if (showSearchField) {
            OutlinedTextField(
                value = query,
                onValueChange = onQueryChange,
                shape = MaterialTheme.shapes.large,
                label = { Text(stringResource(R.string.search_channels)) },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 8.dp)
            )
        }

        if (channels.isEmpty()) {
            EmptyContent(
                title = stringResource(R.string.no_channels),
                modifier = Modifier.weight(1f)
            )
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                if (!showSearchField) {
                    item(key = "server-banner") {
                        ServerBannerCard(state, model)
                    }
                }
                if (uncategorized.isNotEmpty()) {
                    item(key = "uncategorized-heading") {
                        SectionHeading(
                            title = stringResource(R.string.channels),
                            modifier = Modifier.padding(top = 12.dp, bottom = 4.dp)
                        )
                    }
                    items(uncategorized, key = { "channel-${it.id}" }) { channel ->
                        ChannelListRow(
                            channel = channel,
                            unreadCount = state.unreadByChannel[channel.id] ?: 0,
                            participantCount = voiceParticipantCount(state.voiceUsersByChannel[channel.id].orEmpty().keys),
                            onClick = { onChannelSelected(channel.id) }
                        )
                    }
                }
                state.categories.forEach { category: Category ->
                    val categoryChannels = byCategory[category.id].orEmpty()
                    if (categoryChannels.isNotEmpty()) {
                        item(key = "category-${category.id}") {
                            SectionHeading(
                                title = category.name,
                                modifier = Modifier.padding(top = 16.dp, bottom = 4.dp)
                            )
                        }
                        items(categoryChannels.sortedBy(Channel::position), key = { "channel-${it.id}" }) { channel ->
                            ChannelListRow(
                                channel = channel,
                                unreadCount = state.unreadByChannel[channel.id] ?: 0,
                                participantCount = voiceParticipantCount(state.voiceUsersByChannel[channel.id].orEmpty().keys),
                                onClick = { onChannelSelected(channel.id) }
                            )
                        }
                    }
                }
            }
        }
    }
}

internal fun voiceParticipantCount(participantIds: Set<Int>): Int = participantIds.size

@Composable
private fun ChannelListRow(
    channel: Channel,
    unreadCount: Int,
    participantCount: Int,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            val isVoice = channel.type == ChannelType.VOICE
            Icon(
                imageVector = if (isVoice) Icons.Default.GraphicEq else Icons.Default.Tag,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(channel.name, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                channel.topic?.takeIf(String::isNotBlank)?.let { topic ->
                    Text(
                        text = topic,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                if (isVoice) {
                    if (participantCount > 0) {
                        Text(
                            text = pluralStringResource(R.plurals.voice_participant_count, participantCount, participantCount),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
            if (unreadCount > 0) {
                Badge(containerColor = MaterialTheme.colorScheme.primary) {
                    Text(unreadCount.coerceAtMost(99).toString())
                }
            }
        }
    }
}
