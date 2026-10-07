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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Tag
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.R
import com.timmysheep.cove.data.Channel
import com.timmysheep.cove.data.SessionState
import com.timmysheep.cove.data.SearchFile

private enum class MainDestination(
    val label: Int,
    val icon: androidx.compose.ui.graphics.vector.ImageVector
) {
    CHANNELS(R.string.channels, Icons.Default.Tag),
    MESSAGES(R.string.direct_messages, Icons.AutoMirrored.Filled.Chat),
    SETTINGS(R.string.settings, Icons.Default.Settings)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkspaceScreen(state: SessionState, model: CoveViewModel) {
    val context = LocalContext.current
    var destinationIndex by rememberSaveable { mutableIntStateOf(MainDestination.CHANNELS.ordinal) }
    var showMemberPicker by rememberSaveable { mutableStateOf(false) }
    var showSearch by rememberSaveable { mutableStateOf(false) }
    val destination = MainDestination.entries[destinationIndex.coerceIn(0, MainDestination.entries.lastIndex)]
    val selectedChannel = state.channels.firstOrNull { it.id == state.activeChannelId }
    val voiceChannel = state.voiceChannelId?.let { channelId ->
        state.channels.firstOrNull { it.id == channelId }
    }
    val channelDetail = destination == MainDestination.CHANNELS && selectedChannel != null && !selectedChannel.isDm
    val messageDetail = destination == MainDestination.MESSAGES && selectedChannel?.isDm == true
    val inDetail = !showSearch && (channelDetail || messageDetail)
    val activeVoiceRoomIsVisible = !showSearch &&
        destination == MainDestination.CHANNELS &&
        selectedChannel?.id == state.voiceChannelId
    val snackbarHostState = remember { SnackbarHostState() }
    val microphonePermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) model.setMicrophoneEnabled(true)
        else Toast.makeText(context, R.string.microphone_permission_denied, Toast.LENGTH_LONG).show()
    }

    BackHandler(enabled = showSearch) {
        showSearch = false
        model.clearSearch()
    }
    BackHandler(enabled = inDetail) { model.closeChannel() }

    LaunchedEffect(state.error) {
        state.error?.let { message ->
            snackbarHostState.showSnackbar(message)
            model.clearError()
        }
    }

    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val wideLayout = maxWidth >= 840.dp
        Row(modifier = Modifier.fillMaxSize()) {
            if (wideLayout) {
                NavigationRail {
                    MainDestination.entries.forEach { item ->
                        NavigationRailItem(
                            selected = destination == item,
                            onClick = { selectDestination(item, selectedChannel, model) { destinationIndex = it.ordinal } },
                            icon = { Icon(item.icon, contentDescription = null) },
                            label = { Text(stringResource(item.label)) }
                        )
                    }
                }
            }

            Scaffold(
                modifier = Modifier.weight(1f),
                topBar = {
                    Column {
                        TopAppBar(
                            title = {
                                Text(
                                    text = when {
                                        showSearch -> stringResource(R.string.search_messages)
                                        inDetail -> selectedChannel?.name.orEmpty()
                                        else -> stringResource(destination.label)
                                    },
                                    style = if (inDetail) {
                                        MaterialTheme.typography.headlineSmall
                                    } else {
                                        MaterialTheme.typography.titleLarge
                                    },
                                    maxLines = 1
                                )
                            },
                            navigationIcon = {
                                if (showSearch || inDetail) {
                                    IconButton(onClick = {
                                        if (showSearch) {
                                            showSearch = false
                                            model.clearSearch()
                                        } else {
                                            model.closeChannel()
                                        }
                                    }) {
                                        Icon(
                                            Icons.AutoMirrored.Filled.ArrowBack,
                                            contentDescription = stringResource(R.string.back)
                                        )
                                    }
                                }
                            },
                            actions = {
                                if (!showSearch) {
                                    IconButton(onClick = { showSearch = true }) {
                                        Icon(Icons.Default.Search, contentDescription = stringResource(R.string.search_messages))
                                    }
                                }
                                if (!showSearch && destination == MainDestination.MESSAGES && !messageDetail) {
                                    IconButton(onClick = {
                                        model.closeChannel()
                                        destinationIndex = MainDestination.MESSAGES.ordinal
                                        showMemberPicker = true
                                    }) {
                                        Icon(Icons.Default.PersonAdd, contentDescription = stringResource(R.string.new_message))
                                    }
                                }
                            },
                            colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface)
                        )
                        if (state.voiceChannelId != null && !activeVoiceRoomIsVisible) {
                            VoiceQuickControlsBar(
                                channelName = voiceChannel?.name
                                    ?: stringResource(R.string.voice_call_notification_title),
                                microphoneEnabled = state.microphoneEnabled,
                                speakerEnabled = state.speakerEnabled,
                                microphoneControlEnabled = state.speakerEnabled || state.microphoneEnabled,
                                onToggleMicrophone = {
                                    if (state.microphoneEnabled) {
                                        model.setMicrophoneEnabled(false)
                                    } else if (ContextCompat.checkSelfPermission(
                                            context,
                                            Manifest.permission.RECORD_AUDIO
                                        ) == PackageManager.PERMISSION_GRANTED
                                    ) {
                                        model.setMicrophoneEnabled(true)
                                    } else {
                                        microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
                                    }
                                },
                                onToggleSpeaker = { model.setSpeakerEnabled(!state.speakerEnabled) },
                                onLeave = model::leaveVoice
                            )
                        }
                    }
                },
                bottomBar = {
                    if (!wideLayout) {
                        NavigationBar {
                            MainDestination.entries.forEach { item ->
                                NavigationBarItem(
                                    selected = destination == item,
                                    onClick = { selectDestination(item, selectedChannel, model) { destinationIndex = it.ordinal } },
                                    icon = { Icon(item.icon, contentDescription = null) },
                                    label = { Text(stringResource(item.label)) }
                                )
                            }
                        }
                    }
                },
                snackbarHost = { SnackbarHost(snackbarHostState) }
            ) { padding ->
                Box(modifier = Modifier.fillMaxSize().padding(padding)) {
                    if (showSearch) {
                        MessageSearchScreen(
                            state = state,
                            model = model,
                            onOpenMessage = { result ->
                                showSearch = false
                                destinationIndex = MainDestination.CHANNELS.ordinal
                                if (result.parentMessageId != null) {
                                    model.openThread(result.parentMessageId, result.channelId)
                                } else {
                                    model.selectChannel(result.channelId, result.id)
                                }
                            },
                            onOpenFile = { result: SearchFile ->
                                showSearch = false
                                destinationIndex = MainDestination.CHANNELS.ordinal
                                model.openMessage(result.messageId)
                            }
                        )
                    } else when (destination) {
                        MainDestination.CHANNELS -> ChannelDestination(
                            state = state,
                            model = model,
                            selectedChannel = selectedChannel?.takeUnless { it.isDm }
                        )
                        MainDestination.MESSAGES -> DirectMessagesDestination(
                            state = state,
                            model = model,
                            selectedChannel = selectedChannel?.takeIf { it.isDm },
                            showMemberPicker = showMemberPicker,
                            onMemberPickerDismiss = { showMemberPicker = false },
                            onOpenConversation = { destinationIndex = MainDestination.MESSAGES.ordinal }
                        )
                        MainDestination.SETTINGS -> SettingsDestination(state = state, model = model)
                    }
                }
            }
        }
    }
}

private fun selectDestination(
    destination: MainDestination,
    selectedChannel: Channel?,
    model: CoveViewModel,
    setDestination: (MainDestination) -> Unit
) {
    setDestination(destination)
    if (destination == MainDestination.CHANNELS && selectedChannel?.isDm == true) model.closeChannel()
    if (destination == MainDestination.MESSAGES && selectedChannel?.isDm == false) model.closeChannel()
}
