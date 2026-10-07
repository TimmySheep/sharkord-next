package com.timmysheep.cove.ui

import android.app.Activity
import android.content.Intent
import android.content.Context.MEDIA_PROJECTION_SERVICE
import android.graphics.BitmapFactory
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.CallEnd
import androidx.compose.material.icons.filled.FlipCameraAndroid
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
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
import com.timmysheep.cove.data.MessageFile
import com.timmysheep.cove.data.SessionState
import com.timmysheep.cove.data.User
import com.timmysheep.cove.data.VoiceUserState
import com.timmysheep.cove.data.hasChannelPermission
import com.timmysheep.cove.data.hasServerPermission
import com.timmysheep.cove.voice.RemoteVideoTrack
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import org.webrtc.EglBase
import org.webrtc.SurfaceViewRenderer
import org.webrtc.VideoTrack
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private data class PendingAttachment(val id: String, val name: String)

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun ChannelChatScreen(
    state: SessionState,
    model: CoveViewModel,
    channel: Channel,
    voiceRoomOnly: Boolean = false
) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    val uploadFailedText = stringResource(R.string.upload_failed)
    val fileTooLargeText = stringResource(R.string.file_too_large)
    val messages = state.messagesByChannel[channel.id].orEmpty()
    val threadParent = state.activeThreadParentId?.let { parentId ->
        state.messagesByChannel.values.asSequence().flatten().firstOrNull { it.id == parentId }
    }
    val remoteVideoTracks by model.remoteVideoTracks.collectAsState()
    val localCameraTrack by model.localCameraTrack.collectAsState()
    val listState = rememberLazyListState()
    var draft by rememberSaveable(channel.id) { mutableStateOf("") }
    var replyingTo by remember { mutableStateOf<Message?>(null) }
    var actionMessage by remember { mutableStateOf<Message?>(null) }
    var editingMessage by remember { mutableStateOf<Message?>(null) }
    var deleteMessage by remember { mutableStateOf<Message?>(null) }
    var pendingAttachments by remember(channel.id) { mutableStateOf<List<PendingAttachment>>(emptyList()) }
    var uploadingCount by remember(channel.id) { mutableIntStateOf(0) }
    var editText by remember(editingMessage?.id) {
        mutableStateOf(editingMessage?.let { htmlToPlainText(it.content) }.orEmpty())
    }

    val microphonePermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) model.setMicrophoneEnabled(true)
        else Toast.makeText(context, R.string.microphone_permission_denied, Toast.LENGTH_LONG).show()
    }
    val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) model.setCameraEnabled(true)
        else Toast.makeText(context, R.string.camera_permission_denied, Toast.LENGTH_LONG).show()
    }
    val screenCapturePermission = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == Activity.RESULT_OK) model.startScreenShare(result.resultCode, result.data)
    }
    val attachmentPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        uris.forEach { uri ->
            coroutineScope.launch {
                uploadingCount += 1
                try {
                    val fileName = queryDisplayName(context, uri)
                    val mimeType = context.contentResolver.getType(uri) ?: "application/octet-stream"
                    val bytes = withContext(Dispatchers.IO) {
                        context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                            ?: throw IllegalStateException(uploadFailedText)
                    }
                    val maximumSize = state.publicSettings["storageUploadMaxFileSize"]
                        ?.jsonPrimitive?.contentOrNull?.toLongOrNull()
                    if (maximumSize != null && bytes.size > maximumSize) {
                        throw IllegalArgumentException(fileTooLargeText)
                    }
                    val uploaded = model.uploadAttachment(bytes, fileName, mimeType)
                    pendingAttachments = pendingAttachments + PendingAttachment(uploaded.id, uploaded.originalName)
                } catch (error: Throwable) {
                    if (error is kotlinx.coroutines.CancellationException) throw error
                    Toast.makeText(context, error.message ?: uploadFailedText, Toast.LENGTH_LONG).show()
                } finally {
                    uploadingCount -= 1
                }
            }
        }
    }

    LaunchedEffect(channel.id) {
        if (messages.isNotEmpty()) listState.scrollToItem(messages.lastIndex)
    }

    LaunchedEffect(channel.id, messages.lastOrNull()?.id) {
        val lastVisibleIndex = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index
        val highlightedIndex = messages.indexOfFirst { it.id == state.highlightedMessageId }
        if (highlightedIndex >= 0) {
            listState.animateScrollToItem(highlightedIndex)
        } else if (messages.isNotEmpty() && lastVisibleIndex != null && lastVisibleIndex >= messages.lastIndex - 2) {
            listState.animateScrollToItem(messages.lastIndex)
        }
    }

    val voicePanel: @Composable (Modifier) -> Unit = { panelModifier ->
        VoiceCallPanel(
            channel = channel,
            state = state,
            remoteVideoTracks = remoteVideoTracks,
            localCameraTrack = localCameraTrack,
            onJoin = { model.joinVoice(channel.id) },
            onSetConsumerQuality = model::setConsumerQuality,
            modifier = panelModifier
        )
    }

    val voiceControls: @Composable (Modifier) -> Unit = { controlsModifier ->
        VoiceControlsBar(
            state = state,
            channel = channel,
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
            onToggleCamera = {
                if (state.cameraEnabled) {
                    model.setCameraEnabled(false)
                } else if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                    model.setCameraEnabled(true)
                } else {
                    cameraPermission.launch(Manifest.permission.CAMERA)
                }
            },
            onSwitchCamera = model::switchCamera,
            onStartScreenShare = {
                val manager = context.getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                screenCapturePermission.launch(manager.createScreenCaptureIntent())
            },
            onStopScreenShare = model::stopScreenShare,
            modifier = controlsModifier
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
                            model = model,
                            authorName = state.users.firstOrNull { it.id == message.userId }?.name ?: stringResource(R.string.unknown_user),
                            isOwnMessage = message.userId == state.ownUserId,
                            ownUserId = state.ownUserId,
                            onOpenActions = { actionMessage = message },
                            onToggleReaction = { emoji -> model.toggleReaction(message.id, emoji) },
                            onOpenAttachment = { file -> openAttachment(context, model.publicFileUrl(file), file) }
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
                attachments = pendingAttachments,
                uploading = uploadingCount > 0,
                onAttach = { attachmentPicker.launch(arrayOf("*/*")) },
                onRemoveAttachment = { attachment ->
                    model.deleteTemporaryFile(attachment.id)
                    pendingAttachments = pendingAttachments.filterNot { it.id == attachment.id }
                },
                onSend = {
                    if (editingMessage != null) {
                        model.editMessage(editingMessage!!.id, editText)
                        editingMessage = null
                        editText = ""
                    } else {
                        val text = draft
                        val files = pendingAttachments.toList()
                        model.sendMessage(channel.id, text, replyingTo?.id, files.map(PendingAttachment::id)) { sent ->
                            if (sent) {
                                draft = ""
                                replyingTo = null
                                pendingAttachments = emptyList()
                            }
                        }
                    }
                }
            )
    }

    Column(modifier = Modifier.fillMaxSize().imePadding()) {
        if (channel.type == ChannelType.VOICE) {
            if (voiceRoomOnly) {
                voicePanel(Modifier.weight(1f).fillMaxWidth())
            } else {
                Column(modifier = Modifier.weight(1f).fillMaxWidth(), content = conversation)
            }

            if (voiceRoomOnly && state.voiceChannelId == channel.id) {
                HorizontalDivider()
                voiceControls(Modifier.fillMaxWidth())
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
                onOpenThread = {
                    model.openThread(message.id, channel.id)
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

    if (state.activeThreadParentId != null && threadParent != null) {
        ThreadMessagesSheet(
            parent = threadParent,
            replies = state.threadMessagesByParent[state.activeThreadParentId].orEmpty(),
            nextCursor = state.threadCursors[state.activeThreadParentId],
            state = state,
            model = model,
            attachments = pendingAttachments,
            uploading = uploadingCount > 0,
            onAttach = { attachmentPicker.launch(arrayOf("*/*")) },
            onRemoveAttachment = { attachment ->
                model.deleteTemporaryFile(attachment.id)
                pendingAttachments = pendingAttachments.filterNot { it.id == attachment.id }
            },
            onSend = { text, onComplete ->
                val files = pendingAttachments.toList()
                model.sendMessage(channel.id, text, null, files.map(PendingAttachment::id), threadParent.id) { sent ->
                    if (sent) {
                        pendingAttachments = emptyList()
                        onComplete(true)
                    } else {
                        onComplete(false)
                    }
                }
            },
            onDismiss = model::closeThread
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageRow(
    message: Message,
    model: CoveViewModel,
    authorName: String,
    isOwnMessage: Boolean,
    ownUserId: Int,
    onOpenActions: () -> Unit,
    onToggleReaction: (String) -> Unit,
    onOpenAttachment: (MessageFile) -> Unit
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
                AttachmentPreview(
                    file = file,
                    url = model.publicFileUrl(file),
                    model = model,
                    onOpen = { onOpenAttachment(file) }
                )
            }
            if (reactionGroups.isNotEmpty()) {
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
private fun AttachmentPreview(
    file: MessageFile,
    url: String?,
    model: CoveViewModel,
    onOpen: () -> Unit
) {
    val imageFile = file.mimeType.startsWith("image/")
    var bitmap by remember(url) { mutableStateOf<android.graphics.Bitmap?>(null) }
    var showPreview by remember { mutableStateOf(false) }

    LaunchedEffect(url, imageFile) {
        if (imageFile && url != null) {
            bitmap = runCatching {
                val bytes = model.downloadPublicFile(url)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }.getOrNull()
        }
    }

    if (imageFile && bitmap != null) {
        Image(
            bitmap = bitmap!!.asImageBitmap(),
            contentDescription = file.originalName,
            modifier = Modifier
                .padding(top = 5.dp)
                .heightIn(max = 220.dp)
                .widthIn(max = 320.dp)
                .clip(RoundedCornerShape(12.dp))
                .clickable { showPreview = true },
            contentScale = ContentScale.Fit
        )
    } else {
        AssistChip(
            onClick = onOpen,
            label = { Text(file.originalName, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            leadingIcon = { Icon(Icons.Default.AttachFile, contentDescription = null) },
            modifier = Modifier.padding(top = 4.dp)
        )
    }

    if (showPreview && bitmap != null) {
        Dialog(onDismissRequest = { showPreview = false }) {
            Surface(shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.surface) {
                Column(modifier = Modifier.padding(12.dp), horizontalAlignment = Alignment.End) {
                    IconButton(onClick = { showPreview = false }) {
                        Icon(Icons.Default.Close, contentDescription = stringResource(R.string.cancel))
                    }
                    Image(
                        bitmap = bitmap!!.asImageBitmap(),
                        contentDescription = file.originalName,
                        modifier = Modifier.fillMaxWidth().heightIn(max = 640.dp).clickable(onClick = onOpen),
                        contentScale = ContentScale.Fit
                    )
                    Text(file.originalName, modifier = Modifier.padding(8.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ThreadMessagesSheet(
    parent: Message,
    replies: List<Message>,
    nextCursor: com.timmysheep.cove.data.MessagesCursor?,
    state: SessionState,
    model: CoveViewModel,
    attachments: List<PendingAttachment>,
    uploading: Boolean,
    onAttach: () -> Unit,
    onRemoveAttachment: (PendingAttachment) -> Unit,
    onSend: (String, (Boolean) -> Unit) -> Unit,
    onDismiss: () -> Unit
) {
    var draft by rememberSaveable(parent.id) { mutableStateOf("") }
    val context = LocalContext.current

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ) {
        Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.82f).padding(horizontal = 14.dp)) {
            Text(stringResource(R.string.thread), style = MaterialTheme.typography.titleLarge)
            Surface(
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                shape = MaterialTheme.shapes.medium,
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 8.dp)
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(state.users.firstOrNull { it.id == parent.userId }?.name ?: stringResource(R.string.unknown_user), style = MaterialTheme.typography.labelLarge)
                    Text(htmlToPlainText(parent.content), style = MaterialTheme.typography.bodyMedium)
                }
            }
            if (nextCursor != null) {
                TextButton(onClick = { model.loadOlderThread(parent.id) }) {
                    Text(stringResource(R.string.load_older))
                }
            }
            LazyColumn(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                items(replies, key = Message::id) { reply ->
                    MessageRow(
                        message = reply,
                        model = model,
                        authorName = state.users.firstOrNull { it.id == reply.userId }?.name ?: stringResource(R.string.unknown_user),
                        isOwnMessage = reply.userId == state.ownUserId,
                        ownUserId = state.ownUserId,
                        onOpenActions = {},
                        onToggleReaction = { model.toggleReaction(reply.id, it) },
                        onOpenAttachment = { file -> openAttachment(context, model.publicFileUrl(file), file) }
                    )
                }
            }
            MessageComposer(
                value = draft,
                onValueChange = { draft = it },
                isEditing = false,
                attachments = attachments,
                uploading = uploading,
                onAttach = onAttach,
                onRemoveAttachment = onRemoveAttachment,
                onSend = {
                    val text = draft
                    if (text.isNotBlank() || attachments.isNotEmpty()) {
                        onSend(text) { sent ->
                            if (sent) draft = ""
                        }
                    }
                }
            )
        }
    }
}

private fun openAttachment(context: android.content.Context, url: String?, file: MessageFile) {
    if (url == null) return
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(Uri.parse(url), file.mimeType))
    }.onFailure {
        Toast.makeText(context, R.string.open_attachment_failed, Toast.LENGTH_SHORT).show()
    }
}

private fun queryDisplayName(context: android.content.Context, uri: Uri): String {
    val projection = arrayOf(OpenableColumns.DISPLAY_NAME)
    context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
        val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
        if (column >= 0 && cursor.moveToFirst()) cursor.getString(column)?.let { return it }
    }
    return uri.lastPathSegment?.substringAfterLast('/') ?: "attachment"
}

@Composable
private fun MessageComposer(
    value: String,
    onValueChange: (String) -> Unit,
    isEditing: Boolean,
    attachments: List<PendingAttachment>,
    uploading: Boolean,
    onAttach: () -> Unit,
    onRemoveAttachment: (PendingAttachment) -> Unit,
    onSend: () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp)) {
        if (attachments.isNotEmpty()) {
            Row(
                modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(bottom = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                attachments.forEach { attachment ->
                    AssistChip(
                        onClick = { onRemoveAttachment(attachment) },
                        label = { Text(attachment.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        leadingIcon = { Icon(Icons.Default.Close, contentDescription = stringResource(R.string.remove_attachment)) }
                    )
                }
            }
        }
        Row(verticalAlignment = Alignment.Bottom) {
            IconButton(onClick = onAttach, enabled = !isEditing && !uploading) {
                Icon(Icons.Default.AttachFile, contentDescription = stringResource(R.string.attach_file))
            }
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
            FilledIconButton(
                onClick = onSend,
                enabled = !uploading && (value.isNotBlank() || attachments.isNotEmpty())
            ) {
                if (uploading) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                } else {
                    Icon(Icons.AutoMirrored.Filled.Send, contentDescription = stringResource(R.string.send))
                }
            }
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
    onOpenThread: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onTogglePin: () -> Unit,
    onToggleReaction: (String) -> Unit
) {
    val messageContent = htmlToPlainText(message.content)
    val threadActionText = if (message.replyCount > 0) {
        pluralStringResource(R.plurals.reply_count, message.replyCount, message.replyCount)
    } else {
        stringResource(R.string.start_thread)
    }
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 24.dp)) {
        if (messageContent.isNotBlank() && !isEmojiOnlyMessageContent(messageContent)) {
            Text(
                text = messageContent,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(bottom = 10.dp)
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            listOf("👍", "❤️", "😂", "🎉", "👀").forEach { emoji ->
                TextButton(onClick = { onToggleReaction(emoji) }) {
                    Text(emoji, style = MaterialTheme.typography.titleMedium)
                }
            }
        }

        if (isOwnMessage) {
            TextButton(onClick = onEdit, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.Edit, contentDescription = null)
                Spacer(Modifier.width(12.dp))
                Text(stringResource(R.string.edit))
            }
            TextButton(onClick = onDelete, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.Close, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                Spacer(Modifier.width(12.dp))
                Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error)
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            MessageActionButton(
                icon = Icons.AutoMirrored.Filled.Reply,
                label = stringResource(R.string.reply),
                onClick = onReply,
                modifier = Modifier.weight(1f)
            )
            MessageActionButton(
                icon = Icons.Default.Forum,
                label = threadActionText,
                onClick = onOpenThread,
                modifier = Modifier.weight(1f)
            )
            MessageActionButton(
                icon = Icons.Default.PushPin,
                label = stringResource(if (message.pinned) R.string.unpin else R.string.pin),
                onClick = onTogglePin,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun MessageActionButton(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    FilledTonalButton(
        onClick = onClick,
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = 4.dp, vertical = 10.dp)
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(icon, contentDescription = null)
            Text(
                text = label,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
private fun VoiceCallPanel(
    channel: Channel,
    state: SessionState,
    remoteVideoTracks: List<RemoteVideoTrack>,
    localCameraTrack: VideoTrack?,
    onJoin: () -> Unit,
    onSetConsumerQuality: (Int, String, Int?) -> Unit,
    modifier: Modifier = Modifier
) {
    val isInThisRoom = state.voiceChannelId == channel.id
    val participants = state.voiceUsersByChannel[channel.id].orEmpty()
    val participantIds = participants.keys
    val webcamTracks = remoteVideoTracks.filter { it.kind == "video" }.associateBy { it.remoteId }
    val stageItems = buildList {
        participants.forEach { (userId, voiceState) ->
            val user = state.users.firstOrNull { it.id == userId } ?: return@forEach
            val cameraTrack = if (isInThisRoom) {
                if (userId == state.ownUserId) {
                    localCameraTrack.takeIf { state.cameraEnabled }
                } else {
                    webcamTracks[userId]?.track
                }
            } else {
                null
            }
            val cameraKey = if (userId == state.ownUserId) "local-camera" else webcamTracks[userId]?.key

            add(VoiceStageItem("user-$userId") {
                if (cameraTrack != null) {
                    VideoTrackCard(
                        track = cameraTrack,
                        key = cameraKey ?: "remote-camera-$userId",
                        label = user.name
                    )
                } else {
                    VoiceParticipantTile(user = user, voiceState = voiceState)
                }
            })
        }

        if (isInThisRoom && localCameraTrack != null && state.cameraEnabled && state.ownUserId !in participantIds) {
            add(VoiceStageItem("local-camera") {
                VideoTrackCard(
                    track = localCameraTrack,
                    key = "local-camera",
                    label = stringResource(R.string.you)
                )
            })
        }

        if (isInThisRoom) {
            remoteVideoTracks
                .filter { it.kind == "screen" || (it.kind == "video" && it.remoteId !in participantIds) }
                .forEach { stream ->
                    add(VoiceStageItem("stream-${stream.key}") {
                        RemoteVideoCard(
                            stream = stream,
                            label = state.users.firstOrNull { it.id == stream.remoteId }?.name
                        ) { layer ->
                            onSetConsumerQuality(stream.remoteId, stream.kind, layer)
                        }
                    })
                }
        }
    }

    Column(
        modifier = modifier.fillMaxSize().padding(horizontal = 12.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (!isInThisRoom) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Button(onClick = onJoin) { Text(stringResource(R.string.join_voice)) }
            }
        }

        if (stageItems.isEmpty()) {
            Surface(
                color = MaterialTheme.colorScheme.surfaceContainerLow,
                shape = MaterialTheme.shapes.extraLarge,
                modifier = Modifier.weight(1f).fillMaxWidth()
            ) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        text = stringResource(R.string.no_voice_participants),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
        } else {
            VoiceStageGrid(
                items = stageItems,
                modifier = Modifier.weight(1f).fillMaxWidth()
            )
        }

    }
}

private data class VoiceStageItem(
    val key: String,
    val content: @Composable () -> Unit
)

@Composable
private fun VoiceStageGrid(items: List<VoiceStageItem>, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier = modifier) {
        val columns = remember(items.size, maxWidth, maxHeight) {
            calculateVoiceGridColumns(items.size, maxWidth.value, maxHeight.value)
        }
        val rows = items.chunked(columns)
        val cellWidth = (maxWidth - 8.dp * (columns - 1).toFloat()) / columns.toFloat()

        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            rows.forEach { rowItems ->
                Row(
                    modifier = Modifier.weight(1f).fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)
                ) {
                    rowItems.forEach { item ->
                        key(item.key) {
                            Box(modifier = Modifier.width(cellWidth).fillMaxHeight()) {
                                item.content()
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun VoiceParticipantTile(user: User, voiceState: VoiceUserState) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = MaterialTheme.shapes.extraLarge,
        modifier = Modifier.fillMaxSize()
    ) {
        BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
            val avatarSize = minOf(maxWidth * 0.34f, maxHeight * 0.28f).coerceIn(48.dp, 128.dp)
            UserAvatar(
                name = user.name,
                modifier = Modifier.align(Alignment.Center),
                size = avatarSize
            )
            Column(
                modifier = Modifier.align(Alignment.BottomCenter).padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = user.name,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = if (voiceState.micMuted) Icons.Default.MicOff else Icons.Default.Mic,
                        contentDescription = stringResource(if (voiceState.micMuted) R.string.muted else R.string.microphone),
                        tint = if (voiceState.micMuted) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(18.dp)
                    )
                    if (voiceState.webcamEnabled) {
                        Icon(Icons.Default.Videocam, contentDescription = null, modifier = Modifier.size(18.dp))
                    }
                    if (voiceState.sharingScreen) {
                        Icon(Icons.AutoMirrored.Filled.ScreenShare, contentDescription = null, modifier = Modifier.size(18.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun VoiceControlsBar(
    state: SessionState,
    channel: Channel,
    onLeave: () -> Unit,
    onToggleMicrophone: () -> Unit,
    onToggleSpeaker: () -> Unit,
    onToggleCamera: () -> Unit,
    onSwitchCamera: () -> Unit,
    onStartScreenShare: () -> Unit,
    onStopScreenShare: () -> Unit,
    modifier: Modifier = Modifier
) {
    val cameraPermitted = state.hasServerPermission("ENABLE_WEBCAM") &&
        state.hasChannelPermission(channel.id, "WEBCAM")

    Surface(
        modifier = modifier,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        tonalElevation = 2.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            VoiceIconControl(
                modifier = Modifier.weight(1f),
                contentDescription = stringResource(if (state.microphoneEnabled) R.string.microphone else R.string.muted),
                icon = if (state.microphoneEnabled) Icons.Default.Mic else Icons.Default.MicOff,
                active = state.microphoneEnabled,
                enabled = state.speakerEnabled || state.microphoneEnabled,
                onClick = onToggleMicrophone
            )
            VoiceIconControl(
                modifier = Modifier.weight(1f),
                contentDescription = stringResource(R.string.speaker),
                icon = if (state.speakerEnabled) Icons.AutoMirrored.Filled.VolumeUp else Icons.AutoMirrored.Filled.VolumeOff,
                active = state.speakerEnabled,
                enabled = true,
                onClick = onToggleSpeaker
            )
            VoiceIconControl(
                modifier = Modifier.weight(1f),
                contentDescription = stringResource(if (state.cameraEnabled) R.string.stop_camera else R.string.start_camera),
                icon = if (state.cameraEnabled) Icons.Default.Videocam else Icons.Default.VideocamOff,
                active = state.cameraEnabled,
                enabled = cameraPermitted || state.cameraEnabled,
                onClick = onToggleCamera,
                auxiliaryAction = if (state.cameraEnabled) onSwitchCamera else null,
                auxiliaryIcon = Icons.Default.FlipCameraAndroid,
                auxiliaryContentDescription = stringResource(R.string.switch_camera)
            )
            VoiceIconControl(
                modifier = Modifier.weight(1f),
                contentDescription = stringResource(if (state.sharingScreen) R.string.stop_sharing else R.string.share_screen),
                icon = Icons.AutoMirrored.Filled.ScreenShare,
                active = state.sharingScreen,
                enabled = true,
                onClick = if (state.sharingScreen) onStopScreenShare else onStartScreenShare
            )
            VoiceIconControl(
                modifier = Modifier.weight(1f),
                contentDescription = stringResource(R.string.leave_voice),
                icon = Icons.Default.CallEnd,
                active = false,
                enabled = true,
                onClick = onLeave,
                danger = true
            )
        }
    }
}

@Composable
private fun VoiceIconControl(
    modifier: Modifier = Modifier,
    contentDescription: String,
    icon: ImageVector,
    active: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    danger: Boolean = false,
    auxiliaryAction: (() -> Unit)? = null,
    auxiliaryIcon: ImageVector? = null,
    auxiliaryContentDescription: String? = null
) {
    val colors = MaterialTheme.colorScheme

    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Box(modifier = Modifier.size(48.dp)) {
            if (danger) {
                FilledIconButton(
                    onClick = onClick,
                    enabled = enabled,
                    modifier = Modifier.fillMaxSize(),
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = colors.error,
                        contentColor = colors.onError
                    )
                ) {
                    Icon(imageVector = icon, contentDescription = contentDescription)
                }
            } else {
                FilledTonalIconButton(
                    onClick = onClick,
                    enabled = enabled,
                    modifier = Modifier.fillMaxSize(),
                    colors = IconButtonDefaults.filledTonalIconButtonColors(
                        containerColor = if (active) colors.secondaryContainer else colors.surfaceContainerHigh,
                        contentColor = if (active) colors.onSecondaryContainer else colors.onSurfaceVariant
                    )
                ) {
                    Icon(imageVector = icon, contentDescription = contentDescription)
                }
            }
            if (auxiliaryAction != null && auxiliaryIcon != null) {
                Surface(
                    color = colors.tertiaryContainer,
                    shape = CircleShape,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .size(26.dp)
                        .clickable(onClick = auxiliaryAction)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = auxiliaryIcon,
                            contentDescription = auxiliaryContentDescription,
                            tint = colors.onTertiaryContainer,
                            modifier = Modifier.size(15.dp)
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RemoteVideoCard(
    stream: RemoteVideoTrack,
    label: String? = null,
    onQualityChange: (Int?) -> Unit
) {
    var menuExpanded by remember(stream.key) { mutableStateOf(false) }
    Box {
        VideoTrackCard(track = stream.track, key = stream.key, label = label)
        if (stream.qualityLayers.isNotEmpty()) {
            Box(modifier = Modifier.align(Alignment.TopEnd)) {
                IconButton(onClick = { menuExpanded = true }) {
                    Icon(Icons.Default.MoreVert, contentDescription = stringResource(R.string.video_quality))
                }
                DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.quality_auto)) },
                        onClick = {
                            menuExpanded = false
                            onQualityChange(null)
                        }
                    )
                    stream.qualityLayers.forEach { layer ->
                        DropdownMenuItem(
                            text = { Text(layer.label) },
                            onClick = {
                                menuExpanded = false
                                onQualityChange(layer.spatialLayer)
                            }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun VideoTrackCard(track: VideoTrack, key: String, label: String? = null) {
    val eglBase = remember(key) { EglBase.create() }
    var renderer by remember(key) { mutableStateOf<SurfaceViewRenderer?>(null) }

    Box(modifier = Modifier.fillMaxSize()) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { context ->
                SurfaceViewRenderer(context).apply {
                    init(eglBase.eglBaseContext, null)
                    setScalingType(org.webrtc.RendererCommon.ScalingType.SCALE_ASPECT_FIT)
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    track.addSink(this)
                    renderer = this
                }
            },
            update = { view ->
                renderer = view
                track.addSink(view)
            }
        )
        if (label != null) {
            Text(
                text = label,
                modifier = Modifier.align(Alignment.BottomStart).padding(8.dp),
                color = MaterialTheme.colorScheme.onSurface,
                style = MaterialTheme.typography.labelMedium
            )
        }
    }
    DisposableEffect(key, track) {
        onDispose {
            renderer?.let { view ->
                track.removeSink(view)
                view.release()
            }
            eglBase.release()
        }
    }
}
