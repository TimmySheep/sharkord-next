package com.timmysheep.cove.ui

import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.R
import com.timmysheep.cove.data.AdminUser
import com.timmysheep.cove.data.SessionState
import com.timmysheep.cove.data.canBanOrDeleteUser
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.launch

private enum class PendingUserAction {
    KICK,
    BAN,
    UNBAN,
    DELETE,
    REMOVE_ROLE
}

@Composable
internal fun UserManagementDialog(
    state: SessionState,
    model: CoveViewModel,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val loadFailedText = stringResource(R.string.user_management_load_failed)
    val actionFailedText = stringResource(R.string.user_management_action_failed)
    val actionSucceededText = stringResource(R.string.user_management_action_succeeded)
    var users by remember { mutableStateOf<List<AdminUser>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var query by rememberSaveable { mutableStateOf("") }
    var selectedUserId by rememberSaveable { mutableStateOf<Int?>(null) }
    var pendingAction by remember { mutableStateOf<PendingUserAction?>(null) }
    var pendingRoleId by remember { mutableStateOf<Int?>(null) }
    var rolePickerOpen by remember { mutableStateOf(false) }
    var selectedRoleId by remember { mutableIntStateOf(0) }
    var actionReason by rememberSaveable { mutableStateOf("") }
    var wipeUserData by rememberSaveable { mutableStateOf(false) }
    var isWorking by remember { mutableStateOf(false) }

    suspend fun refreshUsers() {
        isLoading = true
        loadError = null
        runCatching { model.getAdminUsers() }
            .onSuccess { users = it.filterNot(AdminUser::isDeletedPlaceholder) }
            .onFailure { loadError = it.message ?: loadFailedText }
        isLoading = false
    }

    LaunchedEffect(Unit) {
        refreshUsers()
    }

    val liveStatuses = remember(state.users) { state.users.associate { it.id to it.status } }
    val visibleUsers = remember(users, liveStatuses, query) {
        users.map { adminUser ->
            adminUser.copy(
                status = liveStatuses[adminUser.id] ?: adminUser.status
            )
        }.filter { it.name.contains(query.trim(), ignoreCase = true) }
            .sortedBy { it.name.lowercase() }
    }
    val selectedUser = visibleUsers.firstOrNull { it.id == selectedUserId }
        ?: users.firstOrNull { it.id == selectedUserId }?.let { adminUser ->
            adminUser.copy(
                status = liveStatuses[adminUser.id] ?: adminUser.status
            )
        }
    val selectedRole = state.roles.firstOrNull { it.id == selectedRoleId }
    val pendingRole = state.roles.firstOrNull { it.id == pendingRoleId }
    val availableRoles = selectedUser?.let { user -> state.roles.filterNot { it.id in user.roleIds } }.orEmpty()

    suspend fun submitPendingAction() {
        val user = selectedUser ?: return
        val action = pendingAction ?: return
        isWorking = true
        try {
            when (action) {
                PendingUserAction.KICK -> model.kickUser(user.id, actionReason.trim())
                PendingUserAction.BAN -> model.banUser(user.id, actionReason.trim())
                PendingUserAction.UNBAN -> model.unbanUser(user.id)
                PendingUserAction.DELETE -> model.deleteUser(user.id, wipeUserData)
                PendingUserAction.REMOVE_ROLE -> {
                    val roleId = pendingRoleId ?: return
                    model.removeUserRole(user.id, roleId)
                }
            }
            pendingAction = null
            pendingRoleId = null
            actionReason = ""
            wipeUserData = false
            if (action == PendingUserAction.DELETE) selectedUserId = null
            Toast.makeText(context, actionSucceededText, Toast.LENGTH_SHORT).show()
            refreshUsers()
        } catch (error: Throwable) {
            Toast.makeText(context, error.message ?: actionFailedText, Toast.LENGTH_LONG).show()
        } finally {
            isWorking = false
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier.fillMaxWidth(0.96f).fillMaxHeight(0.94f),
            shape = MaterialTheme.shapes.extraLarge,
            color = MaterialTheme.colorScheme.surface
        ) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (selectedUser != null) {
                        IconButton(onClick = { selectedUserId = null }, enabled = !isWorking) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                        }
                    }
                    Text(
                        text = stringResource(if (selectedUser == null) R.string.user_management_title else R.string.user_management_details),
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold
                    )
                    IconButton(onClick = onDismiss, enabled = !isWorking) {
                        Icon(Icons.Default.Close, contentDescription = stringResource(R.string.user_management_close))
                    }
                }

                if (selectedUser == null) {
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it },
                        label = { Text(stringResource(R.string.user_management_search)) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    when {
                        isLoading -> Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator()
                        }
                        loadError != null -> Column(
                            modifier = Modifier.weight(1f).fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center
                        ) {
                            Text(loadError.orEmpty(), color = MaterialTheme.colorScheme.error)
                            TextButton(onClick = { scope.launch { refreshUsers() } }) {
                                Icon(Icons.Default.Refresh, contentDescription = null)
                                Spacer(Modifier.width(6.dp))
                                Text(stringResource(R.string.user_management_retry))
                            }
                        }
                        visibleUsers.isEmpty() -> Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                            Text(stringResource(R.string.user_management_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        else -> LazyColumn(
                            modifier = Modifier.weight(1f).fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            items(visibleUsers, key = AdminUser::id) { user ->
                                ManagedUserRow(user, state, model) { selectedUserId = user.id }
                            }
                        }
                    }
                    if (!isLoading && loadError == null) {
                        TextButton(onClick = { scope.launch { refreshUsers() } }, enabled = !isWorking) {
                            Icon(Icons.Default.Refresh, contentDescription = null)
                            Spacer(Modifier.width(6.dp))
                            Text(stringResource(R.string.user_management_refresh))
                        }
                    }
                } else {
                    ManagedUserDetails(
                        user = selectedUser,
                        state = state,
                        model = model,
                        isWorking = isWorking,
                        onKick = {
                            actionReason = ""
                            pendingAction = PendingUserAction.KICK
                        },
                        onBan = {
                            actionReason = ""
                            pendingAction = if (selectedUser.banned) PendingUserAction.UNBAN else PendingUserAction.BAN
                        },
                        onDelete = {
                            wipeUserData = false
                            pendingAction = PendingUserAction.DELETE
                        },
                        onAssignRole = {
                            selectedRoleId = 0
                            rolePickerOpen = true
                        },
                        onRemoveRole = { roleId ->
                            pendingRoleId = roleId
                            pendingAction = PendingUserAction.REMOVE_ROLE
                        }
                    )
                }
            }
        }
    }

    if (rolePickerOpen && selectedUser != null) {
        AlertDialog(
            onDismissRequest = { if (!isWorking) rolePickerOpen = false },
            title = { Text(stringResource(R.string.user_management_assign_role)) },
            text = {
                Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                    if (selectedUser.id == state.ownUserId) {
                        Text(
                            stringResource(R.string.user_management_self_role_warning),
                            color = MaterialTheme.colorScheme.error,
                            modifier = Modifier.padding(bottom = 8.dp)
                        )
                    }
                    if (availableRoles.isEmpty()) {
                        Text(stringResource(R.string.user_management_no_available_roles))
                    } else {
                        availableRoles.forEach { role ->
                            Row(
                                modifier = Modifier.fillMaxWidth().clickable { selectedRoleId = role.id },
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                RadioButton(
                                    selected = selectedRoleId == role.id,
                                    onClick = { selectedRoleId = role.id }
                                )
                                Text(role.name)
                            }
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val roleId = selectedRole?.id ?: return@TextButton
                        scope.launch {
                            isWorking = true
                            runCatching { model.addUserRole(selectedUser.id, roleId) }
                                .onSuccess {
                                    rolePickerOpen = false
                                    Toast.makeText(context, actionSucceededText, Toast.LENGTH_SHORT).show()
                                    refreshUsers()
                                }
                                .onFailure { Toast.makeText(context, it.message ?: actionFailedText, Toast.LENGTH_LONG).show() }
                            isWorking = false
                        }
                    },
                    enabled = selectedRole != null && !isWorking
                ) { Text(stringResource(R.string.user_management_assign_role)) }
            },
            dismissButton = {
                TextButton(onClick = { rolePickerOpen = false }, enabled = !isWorking) {
                    Text(stringResource(R.string.cancel))
                }
            }
        )
    }

    val actionToConfirm = pendingAction
    val userToConfirm = selectedUser
    if (actionToConfirm != null && userToConfirm != null) {
        val actionTitle = when (actionToConfirm) {
            PendingUserAction.KICK -> R.string.user_management_kick_title
            PendingUserAction.BAN -> R.string.user_management_ban_title
            PendingUserAction.UNBAN -> R.string.user_management_unban_title
            PendingUserAction.DELETE -> R.string.user_management_delete_title
            PendingUserAction.REMOVE_ROLE -> R.string.user_management_remove_role_title
        }
        val actionLabel = when (actionToConfirm) {
            PendingUserAction.KICK -> R.string.user_management_kick
            PendingUserAction.BAN -> R.string.user_management_ban
            PendingUserAction.UNBAN -> R.string.user_management_unban
            PendingUserAction.DELETE -> R.string.user_management_delete
            PendingUserAction.REMOVE_ROLE -> R.string.user_management_remove_role
        }
        AlertDialog(
            onDismissRequest = { if (!isWorking) pendingAction = null },
            title = { Text(stringResource(actionTitle, userToConfirm.name, pendingRole?.name.orEmpty())) },
            text = {
                when (actionToConfirm) {
                    PendingUserAction.KICK, PendingUserAction.BAN -> OutlinedTextField(
                        value = actionReason,
                        onValueChange = { actionReason = it.take(500) },
                        label = {
                            Text(stringResource(if (actionToConfirm == PendingUserAction.KICK) R.string.user_management_kick_reason else R.string.user_management_ban_reason))
                        },
                        minLines = 2,
                        maxLines = 4,
                        modifier = Modifier.fillMaxWidth()
                    )
                    PendingUserAction.UNBAN -> Text(stringResource(R.string.user_management_unban_prompt, userToConfirm.name))
                    PendingUserAction.DELETE -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(stringResource(R.string.user_management_delete_prompt, userToConfirm.name))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(R.string.user_management_wipe_data), modifier = Modifier.weight(1f))
                            Switch(checked = wipeUserData, onCheckedChange = { wipeUserData = it })
                        }
                        Text(
                            stringResource(if (wipeUserData) R.string.user_management_wipe_warning else R.string.user_management_keep_data_warning),
                            color = if (wipeUserData) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    PendingUserAction.REMOVE_ROLE -> Text(
                        stringResource(R.string.user_management_remove_role_prompt, pendingRole?.name.orEmpty(), userToConfirm.name)
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = { scope.launch { submitPendingAction() } }, enabled = !isWorking) {
                    Text(stringResource(actionLabel), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingAction = null }, enabled = !isWorking) {
                    Text(stringResource(R.string.cancel))
                }
            }
        )
    }
}

@Composable
private fun ManagedUserRow(
    user: AdminUser,
    state: SessionState,
    model: CoveViewModel,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 4.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        UserAvatar(
            name = user.name,
            size = 44.dp,
            online = user.status == "online",
            avatar = user.avatar,
            model = model
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(user.name, style = MaterialTheme.typography.titleSmall, maxLines = 1)
            val roles = state.roles.filter { it.id in user.roleIds }.joinToString { it.name }
            Text(
                text = roles.ifBlank { stringResource(R.string.user_management_member) },
                style = MaterialTheme.typography.bodySmall,
                maxLines = 1
            )
        }
        val statusLabel = when {
            user.banned -> stringResource(R.string.user_management_banned)
            user.status == "online" -> stringResource(R.string.user_management_online)
            user.status == "idle" -> stringResource(R.string.user_management_idle)
            else -> stringResource(R.string.user_management_offline)
        }
        val statusColor = when {
            user.banned -> MaterialTheme.colorScheme.error
            user.status == "online" -> MaterialTheme.colorScheme.tertiary
            user.status == "idle" -> MaterialTheme.colorScheme.secondary
            else -> MaterialTheme.colorScheme.onSurfaceVariant
        }
        Text(statusLabel, style = MaterialTheme.typography.bodySmall, color = statusColor)
    }
}

@Composable
private fun ColumnScope.ManagedUserDetails(
    user: AdminUser,
    state: SessionState,
    model: CoveViewModel,
    isWorking: Boolean,
    onKick: () -> Unit,
    onBan: () -> Unit,
    onDelete: () -> Unit,
    onAssignRole: () -> Unit,
    onRemoveRole: (Int) -> Unit
) {
    val canBanOrDelete = canBanOrDeleteUser(user, state.ownUserId)
    val userRoles = state.roles.filter { it.id in user.roleIds }
    val unknownDate = stringResource(R.string.user_management_unknown)

    Column(
        modifier = Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            UserAvatar(name = user.name, size = 56.dp, avatar = user.avatar, model = model)
            Column {
                Text(user.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(stringResource(R.string.user_management_id, user.id), style = MaterialTheme.typography.bodySmall)
            }
        }
        if (user.bio.isNotBlank()) Text(user.bio, style = MaterialTheme.typography.bodyMedium)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(stringResource(R.string.user_management_joined, formatAdminDate(user.createdAt, unknownDate)))
            Text(stringResource(R.string.user_management_last_login, formatAdminDate(user.lastLoginAt, unknownDate)))
            if (user.banned) {
                Text(stringResource(R.string.user_management_banned), color = MaterialTheme.colorScheme.error)
                if (!user.banReason.isNullOrBlank()) {
                    Text(stringResource(R.string.user_management_ban_reason_value, user.banReason))
                }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.user_management_roles), style = MaterialTheme.typography.titleSmall)
            if (userRoles.isEmpty()) {
                Text(stringResource(R.string.user_management_no_roles), color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                userRoles.forEach { role ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(role.name, modifier = Modifier.weight(1f))
                        TextButton(
                            onClick = { onRemoveRole(role.id) },
                            enabled = !isWorking && !user.isDeletedPlaceholder
                        ) { Text(stringResource(R.string.user_management_remove_role)) }
                    }
                }
            }
            Button(onClick = onAssignRole, enabled = !isWorking && !user.isDeletedPlaceholder) {
                Text(stringResource(R.string.user_management_assign_role))
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = onKick,
                enabled = !isWorking && user.status != "offline",
                modifier = Modifier.weight(1f)
            ) { Text(stringResource(R.string.user_management_kick)) }
            Button(
                onClick = onBan,
                enabled = !isWorking && canBanOrDelete,
                modifier = Modifier.weight(1f)
            ) {
                Text(stringResource(if (user.banned) R.string.user_management_unban else R.string.user_management_ban))
            }
        }
        TextButton(
            onClick = onDelete,
            enabled = !isWorking && canBanOrDelete,
            modifier = Modifier.fillMaxWidth()
        ) { Text(stringResource(R.string.user_management_delete), color = MaterialTheme.colorScheme.error) }
    }
}

private fun formatAdminDate(timestamp: Long, unknown: String): String {
    if (timestamp <= 0) return unknown
    return DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(timestamp))
}
