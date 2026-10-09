package com.timmysheep.cove.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.GraphicEq
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.R
import com.timmysheep.cove.data.SessionState

@Composable
fun VoiceConnectionBar(
    channelName: String,
    canControl: Boolean,
    microphoneEnabled: Boolean,
    microphoneControlEnabled: Boolean,
    onOpenVoiceRoom: () -> Unit,
    onToggleMicrophone: () -> Unit,
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
                text = channelName,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            IconButton(
                onClick = onToggleMicrophone,
                enabled = canControl && microphoneControlEnabled,
                modifier = Modifier.size(48.dp)
            ) {
                Icon(
                    imageVector = if (microphoneEnabled) Icons.Default.Mic else Icons.Default.MicOff,
                    contentDescription = stringResource(
                        if (microphoneEnabled) R.string.voice_control_mute_microphone
                        else R.string.voice_control_unmute_microphone
                    ),
                    tint = if (microphoneEnabled) MaterialTheme.colorScheme.onTertiaryContainer
                    else MaterialTheme.colorScheme.error
                )
            }
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
        IconButton(onClick = onOpenSettings, modifier = Modifier.size(48.dp)) {
            Icon(Icons.Default.Settings, contentDescription = stringResource(R.string.settings))
        }
    }
}
