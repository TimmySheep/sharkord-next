package com.timmysheep.cove.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.R
import com.timmysheep.cove.data.SessionState
import com.timmysheep.cove.data.VoiceConnectionStatus

@Composable
fun VoiceConnectionBar(
    channelName: String,
    status: VoiceConnectionStatus,
    canControl: Boolean,
    onOpenVoiceRoom: () -> Unit,
    onLeave: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        color = MaterialTheme.colorScheme.tertiaryContainer,
        contentColor = MaterialTheme.colorScheme.onTertiaryContainer,
        shape = RoundedCornerShape(12.dp),
        modifier = modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().clickable(enabled = canControl, onClick = onOpenVoiceRoom).padding(start = 12.dp, end = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Default.GraphicEq, contentDescription = null, modifier = Modifier.size(20.dp))
            Text(
                text = stringResource(
                    if (status == VoiceConnectionStatus.CONNECTING) R.string.voice_connecting_to else R.string.voice_connected_to,
                    channelName
                ),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            IconButton(onClick = onLeave, enabled = canControl, modifier = Modifier.size(48.dp)) {
                Icon(Icons.Default.CallEnd, contentDescription = stringResource(R.string.leave_voice))
            }
        }
    }
}

@Composable
fun UserStatusBar(
    state: SessionState,
    model: CoveViewModel,
    microphoneControlEnabled: Boolean,
    onToggleMicrophone: () -> Unit,
    onToggleHeadphones: () -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier
) {
    val user = state.users.firstOrNull { it.id == state.ownUserId }
    Row(
        modifier = modifier.fillMaxWidth().padding(start = 12.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        UserAvatar(
            name = user?.name.orEmpty(),
            size = 40.dp,
            online = user?.status == "online",
            avatar = user?.avatar,
            model = model
        )
        Text(
            text = user?.name.orEmpty(),
            style = MaterialTheme.typography.titleSmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).padding(start = 8.dp)
        )
        IconButton(
            onClick = onToggleMicrophone,
            enabled = microphoneControlEnabled,
            modifier = Modifier.size(48.dp)
        ) {
            Icon(
                imageVector = if (state.microphoneEnabled) Icons.Default.Mic else Icons.Default.MicOff,
                contentDescription = stringResource(
                    if (state.microphoneEnabled) R.string.voice_control_mute_microphone
                    else R.string.voice_control_unmute_microphone
                ),
                tint = when {
                    state.voiceChannelId == null -> MaterialTheme.colorScheme.onSurfaceVariant
                    state.microphoneEnabled -> MaterialTheme.colorScheme.onSurface
                    else -> MaterialTheme.colorScheme.error
                }
            )
        }
        IconButton(
            onClick = onToggleHeadphones,
            enabled = state.voiceChannelId != null,
            modifier = Modifier.size(48.dp)
        ) {
            val errorColor = MaterialTheme.colorScheme.error
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    Icons.Default.Headphones,
                    contentDescription = stringResource(
                        if (state.speakerEnabled) R.string.voice_control_disable_speaker
                        else R.string.voice_control_enable_speaker
                    ),
                    tint = when {
                        state.voiceChannelId == null -> MaterialTheme.colorScheme.onSurfaceVariant
                        state.speakerEnabled -> MaterialTheme.colorScheme.onSurface
                        else -> MaterialTheme.colorScheme.error
                    }
                )
                if (!state.speakerEnabled) {
                    Canvas(modifier = Modifier.size(22.dp)) {
                        drawLine(
                            color = errorColor,
                            start = Offset(size.width * 0.12f, size.height * 0.12f),
                            end = Offset(size.width * 0.88f, size.height * 0.88f),
                            strokeWidth = 2.dp.toPx(),
                            cap = StrokeCap.Round
                        )
                    }
                }
            }
        }
        IconButton(onClick = onOpenSettings, modifier = Modifier.size(48.dp)) {
            Icon(Icons.Default.Settings, contentDescription = stringResource(R.string.settings))
        }
    }
}
