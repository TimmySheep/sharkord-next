package com.timmysheep.cove.ui

import android.app.Activity
import android.content.Context.MEDIA_PROJECTION_SERVICE
import android.media.projection.MediaProjectionManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.automirrored.filled.ScreenShare
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Reply
import androidx.compose.material.icons.filled.ScreenShare
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import android.Manifest
import android.content.pm.PackageManager
import android.view.ViewGroup
import android.widget.Toast
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.R
import com.timmysheep.cove.data.Channel
import com.timmysheep.cove.data.ChannelType
import com.timmysheep.cove.data.Message
import com.timmysheep.cove.data.SessionState
import com.timmysheep.cove.voice.RemoteVideoTrack
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.webrtc.EglBase
import org.webrtc.SurfaceViewRenderer
import org.webrtc.VideoTrack

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChannelChatScreen(state: SessionState, model: CoveViewModel, channel: Channel) {
    val context = LocalContext.current
    val messages = state.messagesByChannel[channel.id].orEmpty()
    val remoteVideoTracks by model.remoteVideoTracks.collectAsState()
    val listState = rememberLazyListState()
    var draft by rememberSaveable(channel.id) { mutableStateOf("") }
    var replyingTo by remember { mutableStateOf<Message?>(null) }
    var actionMessage by remember { mutableStateOf<Message?>(null) }
    var editingMessage by remember { mutableStateOf<Message?>(null) }
    var deleteMessage by remember { mutableStateOf<Message?>(null) }
    var editText by remember(editingMessage?.id) {
        mutableStateOf(editingMessage?.let { htmlToPlainText(it.content) }.orEmpty())
    }

    val microphonePermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) model.setMicrophoneEnabled(true)
        else Toast.makeText(context, R.string.microphone_permission_denied, Toast.LENGTH_LONG).show()
    }
    val screenCapturePermission = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == Activity.RESULT_OK) model.startScreenShare(result.resultCode, result.data)
    }

    LaunchedEffect(channel.id) {
        if (messages.isNotEmpty()) listState.scrollToItem(messages.lastIndex)
    }

    LaunchedEffect(channel.id, messages.lastOrNull()?.id) {
        val lastVisibleIndex = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index
        if (messages.isNotEmpty() && lastVisibleIndex != null && lastVisibleIndex >= messages.lastIndex - 2) {
            listState.animateScrollToItem(messages.lastIndex)
        }
    }

    val voicePanel: @Composable (Modifier) -> Unit = { panelModifier ->
        VoiceCallPanel(
            channel = channel,
            state = state,
            remoteVideoTracks = remoteVideoTracks,
            onJoin = { model.joinVoice(channel.id) },
            onLeave = model::leaveVoice,
            onToggleMicrophone = {
                if (state.microphoneEnabled) {
                    model.setMicrophoneEnabled(false)
                } else if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                    model.setMicrophoneEnabled(true)
                } else {
                    microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
                }
            },
            onToggleSpeaker = { model.setSpeakerEnabled(!state.speakerEnabled) },
            onStartScreenShare = {
                val manager = context.getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                screenCapturePermission.launch(manager.createScreenCaptureIntent())
            },
            onStopScreenShare = model::stopScreenShare,
            modifier = panelModifier
        )
    }

    val conversation: @Composable ColumnScope.() -> Unit = {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (state.messageCursors[channel.id] != null) {
                    TextButton(onClick = { model.loadOlder(channel.id) }) {
                        Text(stringResource(R.string.load_older))
                    }
                } else {
                    Spacer(Modifier.height(1.dp))
                }
            }

            if (messages.isEmpty()) {
                EmptyContent(
                    title = stringResource(R.string.no_messages),
                    modifier = Modifier.weight(1f)
                )
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.weight(1f).fillMaxWidth().padding(horizontal = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    items(messages, key = Message::id) { message ->
                        MessageRow(
                            message = message,
                            authorName = state.users.firstOrNull { it.id == message.userId }?.name ?: stringResource(R.string.unknown_user),
                            isOwnMessage = message.userId == state.ownUserId,
                            ownUserId = state.ownUserId,
                            onOpenActions = { actionMessage = message },
                            onToggleReaction = { emoji -> model.toggleReaction(message.id, emoji) }
                        )
                    }
                }
            }

            replyingTo?.let { message ->
                ReplyingBanner(
                    message = message,
                    onDismiss = { replyingTo = null }
                )
            }
            editingMessage?.let { message ->
                EditBanner(
                    message = message,
                    onDismiss = {
                        editingMessage = null
                        editText = ""
                    }
                )
            }

            MessageComposer(
                value = if (editingMessage != null) editText else draft,
                onValueChange = { value -> if (editingMessage != null) editText = value else draft = value },
                isEditing = editingMessage != null,
                onSend = {
                    if (editingMessage != null) {
                        model.editMessage(editingMessage!!.id, editText)
                        editingMessage = null
                        editText = ""
                    } else {
                        model.sendMessage(channel.id, draft, replyingTo?.id)
                        draft = ""
                        replyingTo = null
                    }
                }
            )
    }

    Column(modifier = Modifier.fillMaxSize()) {
        if (channel.topic?.isNotBlank() == true) {
            Text(
                text = channel.topic,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 8.dp),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }

        if (channel.type == ChannelType.VOICE) {
            BoxWithConstraints(modifier = Modifier.weight(1f).fillMaxWidth()) {
                if (maxWidth >= 600.dp) {
                    Row(modifier = Modifier.fillMaxSize()) {
                        voicePanel(
                            Modifier
                                .width(300.dp)
                                .fillMaxHeight()
                                .verticalScroll(rememberScrollState())
                        )
                        VerticalDivider()
                        Column(modifier = Modifier.weight(1f).fillMaxHeight(), content = conversation)
                    }
                } else {
                    Column(modifier = Modifier.fillMaxSize()) {
                        voicePanel(
                            Modifier
                                .fillMaxWidth()
                                .heightIn(max = 280.dp)
                                .verticalScroll(rememberScrollState())
                        )
                        HorizontalDivider()
                        Column(modifier = Modifier.weight(1f).fillMaxWidth(), content = conversation)
                    }
                }
            }
        } else {
            Column(modifier = Modifier.weight(1f).fillMaxWidth(), content = conversation)
        }
    }

    actionMessage?.let { message ->
        ModalBottomSheet(
            onDismissRequest = { actionMessage = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ) {
            MessageActionSheet(
                message = message,
                isOwnMessage = message.userId == state.ownUserId,
                onReply = {
                    replyingTo = message
                    editingMessage = null
                    actionMessage = null
                },
                onEdit = {
                    editingMessage = message
                    replyingTo = null
                    actionMessage = null
                },
                onDelete = {
                    deleteMessage = message
                    actionMessage = null
                },
                onTogglePin = {
                    model.togglePin(message.id)
                    actionMessage = null
                },
                onToggleReaction = { emoji ->
                    model.toggleReaction(message.id, emoji)
                    actionMessage = null
                }
            )
        }
    }

    deleteMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { deleteMessage = null },
            title = { Text(stringResource(R.string.delete)) },
            text = { Text(stringResource(R.string.confirm_delete)) },
            confirmButton = {
                TextButton(onClick = {
                    model.deleteMessage(message.id)
                    deleteMessage = null
                }) { Text(stringResource(R.string.delete)) }
            },
            dismissButton = {
                TextButton(onClick = { deleteMessage = null }) { Text(stringResource(R.string.cancel)) }
            }
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageRow(
    message: Message,
    authorName: String,
    isOwnMessage: Boolean,
    ownUserId: Int,
    onOpenActions: () -> Unit,
    onToggleReaction: (String) -> Unit
) {
    val reactionGroups = remember(message.reactions, ownUserId) {
        message.reactions.groupBy { it.emoji }.mapValues { (_, reactions) ->
            reactions.size to reactions.any { it.userId == ownUserId }
        }
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = {}, onLongClick = onOpenActions)
            .padding(vertical = 8.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.Top
    ) {
        UserAvatar(name = authorName, size = 38.dp)
        Spacer(Modifier.width(10.dp))
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(authorName, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Spacer(Modifier.width(8.dp))
                Text(
                    text = formatMessageTime(message.createdAt),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (message.editedAt != null) {
                    Text(
                        text = stringResource(R.string.edited),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(start = 5.dp)
                    )
                }
            }
            message.replyTo?.let { reply ->
                Surface(
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    shape = MaterialTheme.shapes.small,
                    modifier = Modifier.padding(top = 5.dp, bottom = 4.dp)
                ) {
                    Text(
                        text = htmlToPlainText(reply.content),
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 5.dp)
                    )
                }
            }
            if (!message.content.isNullOrBlank()) {
                Text(
                    text = htmlToPlainText(message.content),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.padding(top = 3.dp)
                )
            }
            message.files.forEach { file ->
                Text(
                    text = file.originalName,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(top = 4.dp)
                )
            }
            if (reactionGroups.isNotEmpty() || message.replyCount > 0) {
                Row(
                    modifier = Modifier.padding(top = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    reactionGroups.forEach { (emoji, countAndMine) ->
                        AssistChip(
                            onClick = { onToggleReaction(emoji) },
                            label = { Text("$emoji ${countAndMine.first}") }
                        )
                    }
                    if (message.replyCount > 0) {
                        AssistChip(onClick = onOpenActions, label = { Text(pluralStringResource(R.plurals.reply_count, message.replyCount, message.replyCount)) })
                    }
                }
            }
            if (isOwnMessage && message.pinned) {
                Text(
                    text = stringResource(R.string.pinned_message),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(top = 4.dp)
                )
            }
        }
        IconButton(onClick = onOpenActions, modifier = Modifier.size(36.dp)) {
            Icon(Icons.Default.MoreVert, contentDescription = stringResource(R.string.message_actions))
        }
    }
}

@Composable
private fun MessageComposer(
    value: String,
    onValueChange: (String) -> Unit,
    isEditing: Boolean,
    onSend: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Bottom
    ) {
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            placeholder = { Text(stringResource(R.string.message_hint)) },
            modifier = Modifier.weight(1f),
            maxLines = 5,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { onSend() })
        )
        Spacer(Modifier.width(8.dp))
        FilledIconButton(onClick = onSend, enabled = value.isNotBlank()) {
            Icon(Icons.AutoMirrored.Filled.Send, contentDescription = stringResource(R.string.send))
        }
    }
}

@Composable
private fun ReplyingBanner(message: Message, onDismiss: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.AutoMirrored.Filled.Reply, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Text(
            text = stringResource(R.string.replying_to, htmlToPlainText(message.content).take(72)),
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.weight(1f).padding(start = 8.dp),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        IconButton(onClick = onDismiss) { Icon(Icons.Default.Close, contentDescription = stringResource(R.string.cancel)) }
    }
}

@Composable
private fun EditBanner(message: Message, onDismiss: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Default.Edit, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Text(
            text = stringResource(R.string.editing_message),
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.weight(1f).padding(start = 8.dp)
        )
        IconButton(onClick = onDismiss) { Icon(Icons.Default.Close, contentDescription = stringResource(R.string.cancel)) }
    }
}

@Composable
private fun MessageActionSheet(
    message: Message,
    isOwnMessage: Boolean,
    onReply: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onTogglePin: () -> Unit,
    onToggleReaction: (String) -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 24.dp)) {
        Text(
            text = htmlToPlainText(message.content).ifBlank { stringResource(R.string.no_messages) },
            style = MaterialTheme.typography.titleMedium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(bottom = 10.dp)
        )
        TextButton(onClick = onReply, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.AutoMirrored.Filled.Reply, contentDescription = null)
            Spacer(Modifier.width(12.dp))
            Text(stringResource(R.string.reply))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            listOf("👍", "❤️", "😂", "🎉", "👀").forEach { emoji ->
                TextButton(onClick = { onToggleReaction(emoji) }) { Text(emoji) }
            }
        }
        if (isOwnMessage) {
            TextButton(onClick = onEdit, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.Edit, contentDescription = null)
                Spacer(Modifier.width(12.dp))
                Text(stringResource(R.string.edit))
            }
        }
        TextButton(onClick = onTogglePin, modifier = Modifier.fillMaxWidth()) {
            Icon(Icons.Default.PushPin, contentDescription = null)
            Spacer(Modifier.width(12.dp))
            Text(stringResource(if (message.pinned) R.string.unpin else R.string.pin))
        }
        if (isOwnMessage) {
            TextButton(onClick = onDelete, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.Close, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                Spacer(Modifier.width(12.dp))
                Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun VoiceCallPanel(
    channel: Channel,
    state: SessionState,
    remoteVideoTracks: List<RemoteVideoTrack>,
    onJoin: () -> Unit,
    onLeave: () -> Unit,
    onToggleMicrophone: () -> Unit,
    onToggleSpeaker: () -> Unit,
    onStartScreenShare: () -> Unit,
    onStopScreenShare: () -> Unit,
    modifier: Modifier = Modifier
) {
    val isInThisRoom = state.voiceChannelId == channel.id
    val participants = state.voiceUsersByChannel[channel.id].orEmpty()
    val projectionPermitted =
        !channel.isPrivate ||
            state.channelPermissions[channel.id.toString()]
                ?.jsonObject?.get("permissions")?.jsonObject?.get("SHARE_SCREEN")?.jsonPrimitive?.booleanOrNull == true

    Column(
        modifier = modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerLow,
            shape = MaterialTheme.shapes.extraLarge,
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.People, contentDescription = null, tint = MaterialTheme.colorScheme.onSecondaryContainer)
                    Spacer(Modifier.width(10.dp))
                    Text(
                        text = stringResource(R.string.voice_member_count, participants.size),
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier.weight(1f)
                    )
                    if (!isInThisRoom) {
                        Button(onClick = onJoin) { Text(stringResource(R.string.join_voice)) }
                    } else {
                        TextButton(onClick = onLeave) { Text(stringResource(R.string.leave_voice)) }
                    }
                }
                if (isInThisRoom) {
                    Row(
                        modifier = Modifier.horizontalScroll(androidx.compose.foundation.rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        AssistChip(
                            onClick = onToggleMicrophone,
                            enabled = state.speakerEnabled || state.microphoneEnabled,
                            label = { Text(stringResource(R.string.microphone)) },
                            leadingIcon = {
                                Icon(
                                    imageVector = if (state.microphoneEnabled) Icons.Default.Mic else Icons.Default.MicOff,
                                    contentDescription = null
                                )
                            }
                        )
                        AssistChip(
                            onClick = onToggleSpeaker,
                            label = { Text(stringResource(R.string.speaker)) },
                            leadingIcon = {
                                Icon(
                                    imageVector = if (state.speakerEnabled) Icons.AutoMirrored.Filled.VolumeUp else Icons.AutoMirrored.Filled.VolumeOff,
                                    contentDescription = null
                                )
                            }
                        )
                        if (!state.sharingScreen) {
                            AssistChip(
                                onClick = onStartScreenShare,
                                enabled = projectionPermitted,
                                label = { Text(stringResource(R.string.share_screen)) },
                                leadingIcon = { Icon(Icons.AutoMirrored.Filled.ScreenShare, contentDescription = null) }
                            )
                        } else {
                            AssistChip(onClick = onStopScreenShare, label = { Text(stringResource(R.string.stop_sharing)) })
                        }
                    }
                    if (!state.speakerEnabled && !state.microphoneEnabled) {
                        Text(
                            text = stringResource(R.string.microphone_blocked),
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                    if (participants.isNotEmpty()) {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(participants.toList(), key = { it.first }) { (userId, voiceState) ->
                                state.users.firstOrNull { it.id == userId }?.let { user ->
                                    AssistChip(
                                        onClick = {},
                                        label = {
                                            Text(
                                                text = user.name + if (voiceState.micMuted) " · ${stringResource(R.string.muted)}" else "",
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis
                                            )
                                        },
                                        leadingIcon = { UserAvatar(name = user.name, size = 24.dp) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        if (isInThisRoom) {
            remoteVideoTracks.forEach { stream ->
                key(stream.key, stream.track) {
                    RemoteVideoCard(stream = stream)
                }
            }
        }
    }
}

@Composable
private fun RemoteVideoCard(stream: RemoteVideoTrack) {
    val eglBase = remember(stream.key) { EglBase.create() }
    var renderer by remember(stream.key) { mutableStateOf<SurfaceViewRenderer?>(null) }

    AndroidView(
        modifier = Modifier.fillMaxWidth().height(220.dp),
        factory = { context ->
            SurfaceViewRenderer(context).apply {
                init(eglBase.eglBaseContext, null)
                setScalingType(org.webrtc.RendererCommon.ScalingType.SCALE_ASPECT_FIT)
                layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                stream.track.addSink(this)
                renderer = this
            }
        },
        update = { view ->
            renderer = view
        }
    )
    DisposableEffect(stream.key) {
        onDispose {
            renderer?.let {
                stream.track.removeSink(it)
                it.release()
            }
            eglBase.release()
        }
    }
}
