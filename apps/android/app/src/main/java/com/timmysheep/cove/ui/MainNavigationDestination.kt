package com.timmysheep.cove.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForwardIos
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Tag
import androidx.compose.material3.Badge
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.R
import com.timmysheep.cove.data.Category
import com.timmysheep.cove.data.Channel
import com.timmysheep.cove.data.ChannelType
import com.timmysheep.cove.data.DirectMessageConversation
import com.timmysheep.cove.data.SessionState
import com.timmysheep.cove.data.User
import com.timmysheep.cove.data.directMessagesEnabled

// the server already filters this list by channel visibility
internal fun navigationServerChannels(state: SessionState): List<Channel> =
    state.channels.filterNot(Channel::isDm)

@Composable
fun MainNavigationDestination(
    state: SessionState,
    model: CoveViewModel,
    listState: LazyListState,
    onOpenChannel: (Int) -> Unit,
    onOpenDirectMessages: () -> Unit,
    onNewDirectMessage: () -> Unit,
    modifier: Modifier = Modifier
) {
    val categories = remember(state.categories) { state.categories.sortedBy(Category::position) }
    val visibleChannels = remember(state.channels) { navigationServerChannels(state) }
    val channelsByCategory = remember(visibleChannels) {
        visibleChannels.filter { it.categoryId != null }.groupBy(Channel::categoryId)
    }
    val uncategorized = remember(visibleChannels) {
        visibleChannels.filter { it.categoryId == null }.sortedBy(Channel::position)
    }
    val recentDirectMessages = remember(state.conversations, state.channels, state.users) {
        state.conversations.sortedByDescending(DirectMessageConversation::lastMessageAt)
            .take(3)
            .mapNotNull { conversation ->
                val channel = state.channels.firstOrNull { it.id == conversation.channelId && it.isDm }
                    ?: return@mapNotNull null
                val user = state.users.firstOrNull { it.id == conversation.userId } ?: return@mapNotNull null
                Triple(conversation, channel, user)
            }
        }
    val context = LocalContext.current
    val preferences = remember(context) {
        context.getSharedPreferences("navigation_preferences", android.content.Context.MODE_PRIVATE)
    }
    val preferencePrefix = remember(state.serverAddress) {
        "server-${state.serverAddress.lowercase().hashCode().toUInt().toString(16)}"
    }
    val directMessagesKey = "$preferencePrefix:direct-messages"
    val categoryKeys = categories.map(Category::id)
    val sectionExpanded = remember(preferencePrefix, categoryKeys, uncategorized.isNotEmpty()) {
        mutableStateMapOf<String, Boolean>().apply {
            put(directMessagesKey, preferences.getBoolean(directMessagesKey, true))
            if (uncategorized.isNotEmpty()) {
                val key = "$preferencePrefix:category-uncategorized"
                put(key, preferences.getBoolean(key, true))
            }
            categoryKeys.forEach { id ->
                val key = "$preferencePrefix:category-$id"
                put(key, preferences.getBoolean(key, true))
            }
        }
    }
    val dmExpanded = sectionExpanded[directMessagesKey] ?: true

    LazyColumn(
        state = listState,
        modifier = modifier.fillMaxSize().padding(horizontal = 12.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        if (state.serverLogo != null) {
            item(key = "server-banner") {
                ServerBannerCard(state, model)
            }
        }

        if (state.directMessagesEnabled) {
            item(key = "heading-direct-messages") {
                NavigationSectionHeading(
                    title = stringResource(R.string.direct_messages),
                    expanded = dmExpanded,
                    onToggle = {
                        val expanded = !(sectionExpanded[directMessagesKey] ?: true)
                        sectionExpanded[directMessagesKey] = expanded
                        preferences.edit().putBoolean(directMessagesKey, expanded).apply()
                    },
                    trailing = {
                        IconButton(onClick = onNewDirectMessage, modifier = Modifier.size(48.dp)) {
                            Icon(
                                Icons.Default.Add,
                                contentDescription = stringResource(R.string.new_message),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                )
            }
            if (dmExpanded) {
                items(recentDirectMessages, key = { "recent-dm-${it.first.channelId}" }) { (conversation, channel, user) ->
                    NavigationDirectMessageRow(
                        user = user,
                        unreadCount = state.unreadByChannel[conversation.channelId] ?: conversation.unreadCount,
                        selected = state.activeChannelId == channel.id,
                        model = model,
                        onClick = { onOpenChannel(channel.id) }
                    )
                }
                item(key = "view-all-direct-messages") {
                    TextButton(
                        onClick = onOpenDirectMessages,
                        modifier = Modifier.fillMaxWidth().height(44.dp)
                    ) {
                        Text(stringResource(R.string.view_all_direct_messages))
                        Spacer(Modifier.width(8.dp))
                        Icon(Icons.AutoMirrored.Filled.ArrowForwardIos, contentDescription = null, modifier = Modifier.size(14.dp))
                    }
                }
            }
        }

        if (uncategorized.isNotEmpty()) {
            val key = "$preferencePrefix:category-uncategorized"
            val expanded = sectionExpanded[key] ?: true
            item(key = "heading-uncategorized") {
                NavigationSectionHeading(
                    title = stringResource(R.string.uncategorized_channels),
                    expanded = expanded,
                    onToggle = {
                        sectionExpanded[key] = !expanded
                        preferences.edit().putBoolean(key, !expanded).apply()
                    }
                )
            }
            if (expanded) {
                items(uncategorized, key = { "channel-${it.id}" }) { channel ->
                    NavigationChannelRow(
                        channel = channel,
                        unreadCount = state.unreadByChannel[channel.id] ?: 0,
                        participantCount = voiceParticipantCount(state.voiceUsersByChannel[channel.id].orEmpty().keys),
                        selected = state.activeChannelId == channel.id,
                        connected = state.voiceChannelId == channel.id,
                        onClick = { onOpenChannel(channel.id) }
                    )
                }
            }
        }

        categories.forEach { category ->
            val categoryChannels = channelsByCategory[category.id].orEmpty().sortedBy(Channel::position)
            if (categoryChannels.isNotEmpty()) {
                val key = "$preferencePrefix:category-${category.id}"
                val expanded = sectionExpanded[key] ?: true
                item(key = "heading-category-${category.id}") {
                    NavigationSectionHeading(
                        title = category.name,
                        expanded = expanded,
                        onToggle = {
                            sectionExpanded[key] = !expanded
                            preferences.edit().putBoolean(key, !expanded).apply()
                        }
                    )
                }
                if (expanded) {
                    items(categoryChannels, key = { "channel-${it.id}" }) { channel ->
                        NavigationChannelRow(
                            channel = channel,
                            unreadCount = state.unreadByChannel[channel.id] ?: 0,
                            participantCount = voiceParticipantCount(state.voiceUsersByChannel[channel.id].orEmpty().keys),
                            selected = state.activeChannelId == channel.id,
                            connected = state.voiceChannelId == channel.id,
                            onClick = { onOpenChannel(channel.id) }
                        )
                    }
                }
            }
        }

        item(key = "navigation-bottom-spacer") { Spacer(Modifier.height(12.dp)) }
    }
}

@Composable
private fun NavigationSectionHeading(
    title: String,
    expanded: Boolean,
    onToggle: () -> Unit,
    trailing: (@Composable () -> Unit)? = null
) {
    Row(
        modifier = Modifier.fillMaxWidth().height(48.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(
            onClick = onToggle,
            color = androidx.compose.ui.graphics.Color.Transparent,
            modifier = Modifier.weight(1f).height(48.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = if (expanded) Icons.Default.KeyboardArrowDown else Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(22.dp)
                )
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(start = 6.dp)
                )
            }
        }
        trailing?.invoke()
    }
}

@Composable
private fun NavigationDirectMessageRow(
    user: User,
    unreadCount: Int,
    selected: Boolean,
    model: CoveViewModel,
    onClick: () -> Unit
) {
    NavigationRowSurface(selected, onClick) {
        UserAvatar(
            name = user.name,
            size = 38.dp,
            online = user.status == "online",
            avatar = user.avatar,
            model = model
        )
        Text(
            text = user.name,
            style = MaterialTheme.typography.bodyLarge,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).padding(start = 10.dp)
        )
        if (unreadCount > 0) {
            Badge(containerColor = MaterialTheme.colorScheme.primary) {
                Text(unreadCount.coerceAtMost(99).toString())
            }
        }
    }
}

@Composable
private fun NavigationChannelRow(
    channel: Channel,
    unreadCount: Int,
    participantCount: Int,
    selected: Boolean,
    connected: Boolean,
    onClick: () -> Unit
) {
    NavigationRowSurface(selected, onClick) {
        val isVoice = channel.type == ChannelType.VOICE
        Icon(
            imageVector = if (isVoice) Icons.Default.GraphicEq else Icons.Default.Tag,
            contentDescription = null,
            tint = if (connected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(22.dp)
        )
        Column(modifier = Modifier.weight(1f).padding(start = 10.dp)) {
            Text(
                text = channel.name,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = if (unreadCount > 0) FontWeight.SemiBold else FontWeight.Normal,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            if (isVoice && participantCount > 0) {
                Text(
                    text = pluralStringResource(R.plurals.voice_participant_count, participantCount, participantCount),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1
                )
            }
        }
        if (unreadCount > 0) {
            Badge(containerColor = MaterialTheme.colorScheme.primary) {
                Text(unreadCount.coerceAtMost(99).toString())
            }
        }
    }
}

@Composable
private fun NavigationRowSurface(selected: Boolean, onClick: () -> Unit, content: @Composable RowScope.() -> Unit) {
    Surface(
        onClick = onClick,
        shape = MaterialTheme.shapes.small,
        color = if (selected) MaterialTheme.colorScheme.surfaceContainerHigh else androidx.compose.ui.graphics.Color.Transparent,
        modifier = Modifier.fillMaxWidth().height(52.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = content
        )
    }
}
