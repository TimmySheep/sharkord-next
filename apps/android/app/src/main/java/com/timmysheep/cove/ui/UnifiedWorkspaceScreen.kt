package com.timmysheep.cove.ui

import android.Manifest
import android.content.pm.PackageManager
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.R
import com.timmysheep.cove.data.Channel
import com.timmysheep.cove.data.ChannelType
import com.timmysheep.cove.data.SearchFile
import com.timmysheep.cove.data.SessionState
import com.timmysheep.cove.data.directMessagesEnabled

private enum class WorkspacePage {
    NAVIGATION,
    CHANNEL,
    DIRECT_MESSAGES,
    SETTINGS,
    CHANNEL_SEARCH,
    MESSAGE_SEARCH,
    VOICE_ROOM
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UnifiedWorkspaceScreen(state: SessionState, model: CoveViewModel) {
    val context = LocalContext.current
    var pageName by rememberSaveable { mutableStateOf(WorkspacePage.NAVIGATION.name) }
    var restoredServerAddress by rememberSaveable { mutableStateOf("") }
    var restorationRequestedChannelId by remember { mutableStateOf<Int?>(null) }
    var pendingChannelRestoration by remember { mutableStateOf(false) }
    var detailOriginName by rememberSaveable { mutableStateOf(WorkspacePage.NAVIGATION.name) }
    var settingsOriginName by rememberSaveable { mutableStateOf(WorkspacePage.NAVIGATION.name) }
    var searchOriginName by rememberSaveable { mutableStateOf(WorkspacePage.NAVIGATION.name) }
    var voiceRoomOriginName by rememberSaveable { mutableStateOf(WorkspacePage.NAVIGATION.name) }
    var showMemberPicker by rememberSaveable { mutableStateOf(false) }
    var voicePreviewChannelId by rememberSaveable { mutableStateOf<Int?>(null) }
    val page = WorkspacePage.valueOf(pageName)
    val selectedChannel = state.activeChannelId?.let { id -> state.channels.firstOrNull { it.id == id } }
    val voiceChannel = (state.voiceChannelId ?: state.voiceAttemptChannelId)?.let { id ->
        state.channels.firstOrNull { it.id == id }
    }
    val listState = rememberSaveable(saver = LazyListState.Saver) { LazyListState() }
    val snackbarHostState = remember { SnackbarHostState() }
    val navigationPreferences = remember(context) {
        context.getSharedPreferences("workspace_navigation", android.content.Context.MODE_PRIVATE)
    }
    val microphonePermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) model.setMicrophoneEnabled(true)
        else Toast.makeText(context, R.string.microphone_permission_denied, Toast.LENGTH_LONG).show()
    }

    val openPage: (WorkspacePage) -> Unit = { next -> pageName = next.name }
    val openChannel: (Int) -> Unit = { channelId ->
        detailOriginName = WorkspacePage.NAVIGATION.name
        restorationRequestedChannelId = channelId
        model.selectChannel(channelId)
        openPage(WorkspacePage.CHANNEL)
    }
    val openVoiceRoom: () -> Unit = {
        voiceRoomOriginName = page.name
        openPage(WorkspacePage.VOICE_ROOM)
    }
    val navigateBack: () -> Unit = {
        when (page) {
            WorkspacePage.NAVIGATION -> Unit
            WorkspacePage.CHANNEL -> {
                if (detailOriginName == WorkspacePage.DIRECT_MESSAGES.name) model.closeChannel()
                openPage(WorkspacePage.valueOf(detailOriginName))
            }
            WorkspacePage.DIRECT_MESSAGES -> {
                if (selectedChannel?.isDm == true) model.closeChannel()
                else openPage(WorkspacePage.NAVIGATION)
            }
            WorkspacePage.SETTINGS -> openPage(WorkspacePage.valueOf(settingsOriginName))
            WorkspacePage.CHANNEL_SEARCH, WorkspacePage.MESSAGE_SEARCH -> {
                model.clearSearch()
                openPage(WorkspacePage.valueOf(searchOriginName))
            }
            WorkspacePage.VOICE_ROOM -> openPage(WorkspacePage.valueOf(voiceRoomOriginName))
        }
    }

    BackHandler(enabled = page != WorkspacePage.NAVIGATION) { navigateBack() }

    LaunchedEffect(state.error) {
        state.error?.let { message ->
            snackbarHostState.showSnackbar(message)
            model.clearError()
        }
    }
    LaunchedEffect(state.directMessagesEnabled, page, selectedChannel?.isDm) {
        if (!state.directMessagesEnabled &&
            (page == WorkspacePage.DIRECT_MESSAGES || (page == WorkspacePage.CHANNEL && selectedChannel?.isDm == true))
        ) {
            showMemberPicker = false
            model.closeChannel()
            openPage(WorkspacePage.NAVIGATION)
        }
    }
    LaunchedEffect(state.connected) {
        if (!state.connected) {
            voicePreviewChannelId = null
            restorationRequestedChannelId = null
            pendingChannelRestoration = false
        }
    }
    LaunchedEffect(
        state.connected,
        state.serverAddress,
        state.channels,
        state.conversations,
        state.directMessagesLoaded,
        state.activeChannelId,
        pageName,
        pendingChannelRestoration,
        restoredServerAddress
    ) {
        if (!state.connected || state.serverAddress.isBlank()) return@LaunchedEffect
        val key = workspacePreferenceKey(state.serverAddress)
        val restoreSavedChannel = {
            val channelId = navigationPreferences.getInt("$key:channel", -1)
            val channel = state.channels.firstOrNull { it.id == channelId }
            val canRestore: Boolean? = when {
                channel == null -> false
                channel.isDm && state.directMessagesEnabled && !state.directMessagesLoaded -> null
                channel.isDm -> state.directMessagesEnabled && state.conversations.any { it.channelId == channel.id }
                // server-returned channels already passed the view permission check
                else -> true
            }
            if (canRestore == true && restorationRequestedChannelId != channelId) {
                restorationRequestedChannelId = channelId
                detailOriginName = navigationPreferences.getString("$key:origin", WorkspacePage.NAVIGATION.name)
                    ?: WorkspacePage.NAVIGATION.name
                model.selectChannel(channelId)
                pageName = WorkspacePage.CHANNEL.name
            }
            canRestore
        }
        if (restoredServerAddress != state.serverAddress) {
            val savedPage = navigationPreferences.getString("$key:page", WorkspacePage.NAVIGATION.name)
            if (savedPage == WorkspacePage.CHANNEL.name) {
                when (restoreSavedChannel()) {
                    true -> {
                        pendingChannelRestoration = false
                        restoredServerAddress = state.serverAddress
                    }
                    false -> {
                        pendingChannelRestoration = false
                        pageName = WorkspacePage.NAVIGATION.name
                        restoredServerAddress = state.serverAddress
                    }
                    null -> pendingChannelRestoration = true
                }
            } else if (savedPage == WorkspacePage.DIRECT_MESSAGES.name && state.directMessagesEnabled) {
                pageName = WorkspacePage.DIRECT_MESSAGES.name
                restoredServerAddress = state.serverAddress
            } else {
                pageName = WorkspacePage.NAVIGATION.name
                restoredServerAddress = state.serverAddress
            }
        } else if (pendingChannelRestoration && state.directMessagesLoaded) {
            pendingChannelRestoration = false
            if (restoreSavedChannel() != true) pageName = WorkspacePage.NAVIGATION.name
            restoredServerAddress = state.serverAddress
        } else if (pageName == WorkspacePage.CHANNEL.name && state.activeChannelId == null) {
            if (restoreSavedChannel() == false) pageName = WorkspacePage.NAVIGATION.name
        }
    }
    LaunchedEffect(state.connected, state.serverAddress, pageName, selectedChannel?.id, restoredServerAddress) {
        if (!state.connected || state.serverAddress != restoredServerAddress) return@LaunchedEffect
        if (page == WorkspacePage.CHANNEL && selectedChannel == null && restorationRequestedChannelId != null) {
            return@LaunchedEffect
        }
        val key = workspacePreferenceKey(state.serverAddress)
        val persistablePage = when (page) {
            WorkspacePage.CHANNEL -> if (selectedChannel != null) WorkspacePage.CHANNEL else WorkspacePage.NAVIGATION
            WorkspacePage.DIRECT_MESSAGES -> if (selectedChannel?.isDm == true) WorkspacePage.CHANNEL else WorkspacePage.DIRECT_MESSAGES
            else -> WorkspacePage.NAVIGATION
        }
        navigationPreferences.edit()
            .putString("$key:page", persistablePage.name)
            .apply {
                if (persistablePage == WorkspacePage.CHANNEL && selectedChannel != null) {
                    putInt("$key:channel", selectedChannel.id)
                    putString(
                        "$key:origin",
                        if (page == WorkspacePage.DIRECT_MESSAGES && selectedChannel.isDm) {
                            WorkspacePage.DIRECT_MESSAGES.name
                        } else {
                            detailOriginName
                        }
                    )
                }
            }
    }

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val wideLayout = maxWidth >= 840.dp
        val directMessagesSplitLayout = maxWidth >= 1080.dp
        val showPersistentBars = page != WorkspacePage.VOICE_ROOM
        val imeVisible = WindowInsets.ime.getBottom(LocalDensity.current) > 0
        val selectNavigationChannel: (Int) -> Unit = { channelId ->
            val channel = state.channels.firstOrNull { it.id == channelId }
            when {
                channel?.isDm == true && directMessagesSplitLayout -> {
                    detailOriginName = WorkspacePage.NAVIGATION.name
                    model.selectChannel(channelId)
                    openPage(WorkspacePage.DIRECT_MESSAGES)
                }
                channel?.type == ChannelType.VOICE -> {
                    if (state.voiceChannelId == channelId) openVoiceRoom()
                    else voicePreviewChannelId = channelId
                }
                else -> openChannel(channelId)
            }
        }
        Scaffold(
            topBar = {
                TopAppBar(
                    title = {
                        if (page == WorkspacePage.NAVIGATION) {
                            Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                                UserAvatar(
                                    name = state.serverName.ifBlank { stringResource(R.string.app_name) },
                                    avatar = state.serverLogo,
                                    model = model,
                                    size = 30.dp
                                )
                                Spacer(Modifier.width(10.dp))
                                Text(
                                    text = state.serverName.ifBlank { stringResource(R.string.app_name) },
                                    style = MaterialTheme.typography.titleLarge,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        } else {
                            val title = when (page) {
                                WorkspacePage.NAVIGATION -> stringResource(R.string.app_name)
                                WorkspacePage.CHANNEL -> selectedChannel?.name.orEmpty()
                                WorkspacePage.DIRECT_MESSAGES -> stringResource(R.string.all_direct_messages)
                                WorkspacePage.SETTINGS -> stringResource(R.string.settings)
                                WorkspacePage.CHANNEL_SEARCH -> stringResource(R.string.search_channels)
                                WorkspacePage.MESSAGE_SEARCH -> stringResource(R.string.search_messages)
                                WorkspacePage.VOICE_ROOM -> voiceChannel?.name.orEmpty()
                            }
                            Text(
                                text = title,
                                style = MaterialTheme.typography.titleLarge,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    },
                    navigationIcon = {
                        if (page != WorkspacePage.NAVIGATION) {
                            IconButton(onClick = navigateBack, modifier = Modifier.width(48.dp)) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                            }
                        }
                    },
                    actions = {
                        if (page == WorkspacePage.NAVIGATION) {
                            IconButton(
                                onClick = {
                                    searchOriginName = page.name
                                    openPage(WorkspacePage.CHANNEL_SEARCH)
                                },
                                modifier = Modifier.width(48.dp)
                            ) {
                                Icon(Icons.Default.Search, contentDescription = stringResource(R.string.search_channels))
                            }
                        } else if (page == WorkspacePage.CHANNEL) {
                            IconButton(
                                onClick = {
                                    searchOriginName = page.name
                                    openPage(WorkspacePage.MESSAGE_SEARCH)
                                },
                                modifier = Modifier.width(48.dp)
                            ) {
                                Icon(Icons.Default.Search, contentDescription = stringResource(R.string.search_messages))
                            }
                        }
                        if (page == WorkspacePage.DIRECT_MESSAGES && state.directMessagesEnabled) {
                            IconButton(
                                onClick = { showMemberPicker = true },
                                modifier = Modifier.width(48.dp)
                            ) {
                                Icon(Icons.Default.PersonAdd, contentDescription = stringResource(R.string.new_message))
                            }
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface)
                )
            },
            bottomBar = {
                if (showPersistentBars && !imeVisible) {
                    if (wideLayout) {
                        Row(modifier = Modifier.navigationBarsPadding()) {
                            Column(modifier = Modifier.width(320.dp)) {
                                if (state.voiceConnectionStatus != com.timmysheep.cove.data.VoiceConnectionStatus.DISCONNECTED) {
                                    VoiceConnectionBar(
                                        channelName = voiceChannel?.name ?: stringResource(R.string.voice_call_notification_title),
                                        status = state.voiceConnectionStatus,
                                        canControl = state.voiceChannelId != null,
                                        onOpenVoiceRoom = openVoiceRoom,
                                        onLeave = model::leaveVoice
                                    )
                                }
                                UserStatusBar(
                                    state = state,
                                    model = model,
                                    microphoneControlEnabled = state.voiceChannelId != null && (state.speakerEnabled || state.microphoneEnabled),
                                    onToggleMicrophone = {
                                        if (state.microphoneEnabled) {
                                            model.setMicrophoneEnabled(false)
                                        } else if (state.speakerEnabled && ContextCompat.checkSelfPermission(
                                                context,
                                                Manifest.permission.RECORD_AUDIO
                                            ) == PackageManager.PERMISSION_GRANTED
                                        ) {
                                            model.setMicrophoneEnabled(true)
                                        } else if (state.speakerEnabled) {
                                            microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
                                        }
                                    },
                                    onToggleHeadphones = { model.setSpeakerEnabled(!state.speakerEnabled) },
                                    onOpenSettings = {
                                        settingsOriginName = page.name
                                        openPage(WorkspacePage.SETTINGS)
                                    }
                                )
                            }
                        }
                    } else {
                        Column(modifier = Modifier.navigationBarsPadding()) {
                            if (state.voiceConnectionStatus != com.timmysheep.cove.data.VoiceConnectionStatus.DISCONNECTED) {
                                VoiceConnectionBar(
                                    channelName = voiceChannel?.name ?: stringResource(R.string.voice_call_notification_title),
                                    status = state.voiceConnectionStatus,
                                    canControl = state.voiceChannelId != null,
                                    onOpenVoiceRoom = openVoiceRoom,
                                    onLeave = model::leaveVoice
                                )
                            }
                            UserStatusBar(
                                state = state,
                                model = model,
                                microphoneControlEnabled = state.voiceChannelId != null && (state.speakerEnabled || state.microphoneEnabled),
                                onToggleMicrophone = {
                                    if (state.microphoneEnabled) {
                                        model.setMicrophoneEnabled(false)
                                    } else if (state.speakerEnabled && ContextCompat.checkSelfPermission(
                                            context,
                                            Manifest.permission.RECORD_AUDIO
                                        ) == PackageManager.PERMISSION_GRANTED
                                    ) {
                                        model.setMicrophoneEnabled(true)
                                    } else if (state.speakerEnabled) {
                                        microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
                                    }
                                },
                                onToggleHeadphones = { model.setSpeakerEnabled(!state.speakerEnabled) },
                                onOpenSettings = {
                                    settingsOriginName = page.name
                                    openPage(WorkspacePage.SETTINGS)
                                }
                            )
                        }
                    }
                }
            },
            snackbarHost = { SnackbarHost(snackbarHostState) }
        ) { padding ->
            Row(modifier = Modifier.fillMaxSize().padding(padding)) {
                if (wideLayout) {
                    MainNavigationDestination(
                        state = state,
                        model = model,
                        listState = listState,
                        onOpenChannel = selectNavigationChannel,
                        onOpenDirectMessages = {
                            showMemberPicker = false
                            model.closeChannel()
                            openPage(WorkspacePage.DIRECT_MESSAGES)
                        },
                        onNewDirectMessage = {
                            showMemberPicker = true
                            model.closeChannel()
                            openPage(WorkspacePage.DIRECT_MESSAGES)
                        },
                        modifier = Modifier.width(320.dp).fillMaxHeight()
                    )
                    androidx.compose.material3.VerticalDivider()
                }

                Box(modifier = Modifier.weight(1f).fillMaxHeight()) {
                    when (page) {
                        WorkspacePage.NAVIGATION -> {
                            if (!wideLayout) {
                                MainNavigationDestination(
                                    state = state,
                                    model = model,
                                    listState = listState,
                                    onOpenChannel = selectNavigationChannel,
                                    onOpenDirectMessages = {
                                        showMemberPicker = false
                                        model.closeChannel()
                                        openPage(WorkspacePage.DIRECT_MESSAGES)
                                    },
                                    onNewDirectMessage = {
                                        showMemberPicker = true
                                        model.closeChannel()
                                        openPage(WorkspacePage.DIRECT_MESSAGES)
                                    }
                                )
                            } else {
                                EmptyContent(
                                    title = stringResource(R.string.select_channel_title),
                                    body = stringResource(R.string.select_channel_body),
                                    modifier = Modifier.fillMaxSize()
                                )
                            }
                        }
                        WorkspacePage.CHANNEL -> {
                            if (selectedChannel != null) {
                                ChannelChatScreen(state = state, model = model, channel = selectedChannel)
                            } else {
                                EmptyContent(title = stringResource(R.string.select_channel_title), modifier = Modifier.fillMaxSize())
                            }
                        }
                        WorkspacePage.DIRECT_MESSAGES -> DirectMessagesDestination(
                            state = state,
                            model = model,
                            selectedChannel = if (directMessagesSplitLayout) selectedChannel?.takeIf { it.isDm } else null,
                            splitLayout = directMessagesSplitLayout,
                            showMemberPicker = showMemberPicker,
                            onMemberPickerDismiss = { showMemberPicker = false },
                            onOpenConversation = {
                                detailOriginName = WorkspacePage.DIRECT_MESSAGES.name
                                openPage(WorkspacePage.CHANNEL)
                            },
                            onCreateConversation = { showMemberPicker = true }
                        )
                        WorkspacePage.SETTINGS -> SettingsDestination(state = state, model = model)
                        WorkspacePage.CHANNEL_SEARCH -> ChannelDestination(
                            state = state,
                            model = model,
                            selectedChannel = null,
                            searchMode = true,
                            onSearchResultSelected = {
                                searchOriginName = WorkspacePage.NAVIGATION.name
                                detailOriginName = WorkspacePage.NAVIGATION.name
                                openPage(WorkspacePage.CHANNEL)
                            }
                        )
                        WorkspacePage.MESSAGE_SEARCH -> MessageSearchScreen(
                            state = state,
                            model = model,
                            onOpenMessage = { result ->
                                model.clearSearch()
                                model.selectChannel(result.channelId, result.id)
                                detailOriginName = WorkspacePage.NAVIGATION.name
                                openPage(WorkspacePage.CHANNEL)
                            },
                            onOpenFile = { result: SearchFile ->
                                model.clearSearch()
                                model.openMessage(result.messageId)
                                detailOriginName = WorkspacePage.NAVIGATION.name
                                openPage(WorkspacePage.CHANNEL)
                            }
                        )
                        WorkspacePage.VOICE_ROOM -> {
                            if (voiceChannel != null) {
                                ChannelChatScreen(
                                    state = state,
                                    model = model,
                                    channel = voiceChannel,
                                    voiceRoomOnly = true
                                )
                            } else {
                                EmptyContent(title = stringResource(R.string.voice_disconnected), modifier = Modifier.fillMaxSize())
                            }
                        }
                    }
                }
            }
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
                detailOriginName = WorkspacePage.NAVIGATION.name
                model.selectChannel(channel.id)
                openPage(WorkspacePage.CHANNEL)
            },
            microphoneEnabledOnJoin = model.microphoneEnabledOnJoin.collectAsStateWithLifecycle().value,
            onToggleMicrophoneOnJoin = {
                val enabled = model.microphoneEnabledOnJoin.value
                if (enabled) {
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

private fun workspacePreferenceKey(serverAddress: String): String =
    "server-${serverAddress.lowercase().hashCode().toUInt().toString(16)}"
