package com.timmysheep.cove.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.timmysheep.cove.R

@Composable
fun VoiceQuickControlsBar(
    channelName: String,
    microphoneEnabled: Boolean,
    speakerEnabled: Boolean,
    microphoneControlEnabled: Boolean,
    onOpenVoiceRoom: () -> Unit,
    onToggleMicrophone: () -> Unit,
    onToggleSpeaker: () -> Unit,
    onLeave: () -> Unit,
    modifier: Modifier = Modifier
) {
    val colors = MaterialTheme.colorScheme

    Surface(
        modifier = modifier,
        color = colors.surfaceContainerLow,
        tonalElevation = 2.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = Modifier.weight(1f).clickable(onClick = onOpenVoiceRoom),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = stringResource(R.string.voice_call_notification_title),
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.onSurfaceVariant,
                    maxLines = 1
                )
                Text(
                    text = channelName,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            FilledTonalIconButton(
                onClick = onToggleMicrophone,
                enabled = microphoneControlEnabled,
                modifier = Modifier.size(48.dp),
                colors = IconButtonDefaults.filledTonalIconButtonColors(
                    containerColor = if (microphoneEnabled) colors.secondaryContainer else colors.surfaceContainerHigh,
                    contentColor = if (microphoneEnabled) colors.onSecondaryContainer else colors.onSurfaceVariant
                )
            ) {
                Icon(
                    imageVector = if (microphoneEnabled) Icons.Default.Mic else Icons.Default.MicOff,
                    contentDescription = stringResource(
                        if (microphoneEnabled) R.string.voice_control_mute_microphone
                        else R.string.voice_control_unmute_microphone
                    )
                )
            }
            FilledTonalIconButton(
                onClick = onToggleSpeaker,
                modifier = Modifier.size(48.dp),
                colors = IconButtonDefaults.filledTonalIconButtonColors(
                    containerColor = if (speakerEnabled) colors.secondaryContainer else colors.surfaceContainerHigh,
                    contentColor = if (speakerEnabled) colors.onSecondaryContainer else colors.onSurfaceVariant
                )
            ) {
                Icon(
                    imageVector = if (speakerEnabled) Icons.AutoMirrored.Filled.VolumeUp else Icons.AutoMirrored.Filled.VolumeOff,
                    contentDescription = stringResource(
                        if (speakerEnabled) R.string.voice_control_disable_speaker
                        else R.string.voice_control_enable_speaker
                    )
                )
            }
            FilledIconButton(
                onClick = onLeave,
                modifier = Modifier.size(48.dp),
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = colors.error,
                    contentColor = colors.onError
                )
            ) {
                Icon(
                    imageVector = Icons.Default.CallEnd,
                    contentDescription = stringResource(R.string.leave_voice)
                )
            }
        }
    }
}
