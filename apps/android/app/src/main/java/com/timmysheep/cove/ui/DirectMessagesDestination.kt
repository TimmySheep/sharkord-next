package com.timmysheep.cove.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.R
import com.timmysheep.cove.data.Channel
import com.timmysheep.cove.data.DirectMessageConversation
import com.timmysheep.cove.data.SessionState
import com.timmysheep.cove.data.User

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DirectMessagesDestination(
    state: SessionState,
    model: CoveViewModel,
    selectedChannel: Channel?,
    showMemberPicker: Boolean,
    onMemberPickerDismiss: () -> Unit,
    onOpenConversation: () -> Unit
) {
    var query by rememberSaveable { mutableStateOf("") }
    val conversations = remember(state.conversations, state.channels, state.users) {
        state.conversations.mapNotNull { conversation ->
            val channel = state.channels.firstOrNull { it.id == conversation.channelId } ?: return@mapNotNull null
            val user = state.users.firstOrNull { it.id == conversation.userId } ?: return@mapNotNull null
            conversation to (channel to user)
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        if (maxWidth >= 840.dp) {
            Row(Modifier.fillMaxSize()) {
                ConversationList(
                    conversations = conversations,
                    unreadByChannel = state.unreadByChannel,
                    query = query,
                    onQueryChange = { query = it },
                    onSelect = { channelId ->
                        model.selectChannel(channelId)
                        onOpenConversation()
                    },
                    modifier = Modifier.width(340.dp).fillMaxHeight()
                )
                VerticalDivider()
                if (selectedChannel != null) {
                    ChannelChatScreen(state = state, model = model, channel = selectedChannel)
                } else {
                    EmptyContent(
                        title = stringResource(R.string.select_conversation_title),
                        body = stringResource(R.string.select_conversation_body),
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        } else if (selectedChannel != null) {
            ChannelChatScreen(state = state, model = model, channel = selectedChannel)
        } else {
            ConversationList(
                conversations = conversations,
                unreadByChannel = state.unreadByChannel,
                query = query,
                onQueryChange = { query = it },
                onSelect = { channelId ->
                    model.selectChannel(channelId)
                    onOpenConversation()
                },
                modifier = Modifier.fillMaxSize()
            )
        }
    }

    if (showMemberPicker) {
        ModalBottomSheet(
            onDismissRequest = onMemberPickerDismiss,
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ) {
            MemberPicker(
                state = state,
                query = query,
                onQueryChange = { query = it },
                onSelect = { userId ->
                    onMemberPickerDismiss()
                    model.openDirectMessage(userId)
                    onOpenConversation()
                }
            )
        }
    }
}

@Composable
private fun ConversationList(
    conversations: List<Pair<DirectMessageConversation, Pair<Channel, User>>>,
    unreadByChannel: Map<Int, Int>,
    query: String,
    onQueryChange: (String) -> Unit,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val visibleConversations = remember(conversations, query) {
        conversations.filter { (_, pair) -> pair.second.name.contains(query.trim(), ignoreCase = true) }
    }

    Column(modifier = modifier.padding(horizontal = 16.dp)) {
        OutlinedTextField(
            value = query,
            onValueChange = onQueryChange,
            label = { Text(stringResource(R.string.search_members)) },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 8.dp)
        )
        if (visibleConversations.isEmpty()) {
            EmptyContent(title = stringResource(R.string.no_conversations), modifier = Modifier.weight(1f))
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                items(visibleConversations, key = { "dm-${it.first.channelId}" }) { (conversation, pair) ->
                    val (channel, user) = pair
                    ConversationRow(
                        user = user,
                        unreadCount = unreadByChannel[conversation.channelId] ?: conversation.unreadCount,
                        preview = null,
                        onClick = { onSelect(channel.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun ConversationRow(
    user: User,
    unreadCount: Int,
    preview: String?,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            UserAvatar(name = user.name, size = 48.dp, online = user.status == "online")
            Spacer(Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(user.name, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (preview != null) {
                    Text(
                        preview,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            if (unreadCount > 0) {
                Text(
                    text = unreadCount.coerceAtMost(99).toString(),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}

@Composable
private fun MemberPicker(
    state: SessionState,
    query: String,
    onQueryChange: (String) -> Unit,
    onSelect: (Int) -> Unit
) {
    val members = remember(state.users, state.ownUserId, query) {
        state.users.filter { it.id != state.ownUserId && it.name.contains(query.trim(), ignoreCase = true) }
    }

    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 24.dp)
    ) {
        Text(
            text = stringResource(R.string.new_message),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(bottom = 12.dp)
        )
        OutlinedTextField(
            value = query,
            onValueChange = onQueryChange,
            label = { Text(stringResource(R.string.search_members)) },
            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        if (members.isEmpty()) {
            EmptyContent(title = stringResource(R.string.no_members))
        } else {
            LazyColumn(modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
                items(members, key = User::id) { user ->
                    ConversationRow(
                        user = user,
                        unreadCount = 0,
                        preview = if (user.status == "online") stringResource(R.string.online) else stringResource(R.string.offline),
                        onClick = { onSelect(user.id) }
                    )
                }
            }
        }
    }
}
