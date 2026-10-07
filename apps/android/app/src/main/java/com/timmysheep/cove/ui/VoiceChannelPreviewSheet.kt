package com.timmysheep.cove.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.timmysheep.cove.R
import com.timmysheep.cove.data.Channel
import com.timmysheep.cove.data.SessionState
import com.timmysheep.cove.data.VoiceUserState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoiceChannelPreviewSheet(
    channel: Channel,
    state: SessionState,
    onDismiss: () -> Unit,
    onJoin: () -> Unit,
    onOpenChat: () -> Unit
) {
    val participants = remember(channel.id, state.voiceUsersByChannel, state.users) {
        state.voiceUsersByChannel[channel.id].orEmpty().mapNotNull { (userId, voiceState) ->
            state.users.firstOrNull { it.id == userId }?.let { user -> user to voiceState }
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(channel.name, style = MaterialTheme.typography.titleLarge)
                Text(
                    text = stringResource(R.string.voice_member_count, participants.size),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            if (participants.isEmpty()) {
                Text(
                    text = stringResource(R.string.voice_preview_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 16.dp)
                )
            } else {
                LazyRow(
                    contentPadding = PaddingValues(vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    items(participants, key = { it.first.id }) { (user, voiceState) ->
                        VoicePreviewParticipant(user.name, voiceState)
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Surface(
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = MaterialTheme.shapes.large,
                    modifier = Modifier.size(48.dp)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Default.MicOff,
                            contentDescription = stringResource(R.string.muted),
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                }
                Button(
                    onClick = onJoin,
                    modifier = Modifier.weight(1f).heightIn(min = 56.dp)
                ) {
                    Text(stringResource(R.string.join_voice))
                }
                IconButton(onClick = onOpenChat, modifier = Modifier.size(48.dp)) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.Chat,
                        contentDescription = stringResource(R.string.voice_chat)
                    )
                }
            }
        }
    }
}

@Composable
private fun VoicePreviewParticipant(name: String, voiceState: VoiceUserState) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.size(width = 72.dp, height = 94.dp)
    ) {
        UserAvatar(name = name, size = 56.dp)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            if (voiceState.micMuted) {
                Icon(
                    imageVector = Icons.Default.MicOff,
                    contentDescription = stringResource(R.string.muted),
                    tint = MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(14.dp)
                )
            }
            Text(
                text = name,
                style = MaterialTheme.typography.labelMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}
