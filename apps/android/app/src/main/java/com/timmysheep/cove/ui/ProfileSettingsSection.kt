package com.timmysheep.cove.ui

import android.graphics.BitmapFactory
import android.net.Uri
import android.webkit.MimeTypeMap
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.R
import com.timmysheep.cove.data.MessageFile
import com.timmysheep.cove.data.SessionState
import com.timmysheep.cove.data.User
import kotlinx.coroutines.launch

private enum class ProfileImageTarget(val isAvatar: Boolean) {
    AVATAR(true),
    BANNER(false)
}

@Composable
internal fun ProfileSettingsSection(state: SessionState, model: CoveViewModel) {
    val user = state.users.firstOrNull { it.id == state.ownUserId } ?: return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var name by remember(user.id, user.name) { mutableStateOf(user.name) }
    var bio by remember(user.id, user.bio) { mutableStateOf(user.bio) }
    var profileColor by remember(user.id, user.profileColor) {
        mutableStateOf(user.profileColor.ifBlank { "#262626" })
    }
    var isSaving by remember { mutableStateOf(false) }
    var isUploading by remember { mutableStateOf(false) }
    var imageTarget by remember { mutableStateOf<ProfileImageTarget?>(null) }

    val imagePicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        val target = imageTarget ?: return@rememberLauncherForActivityResult
        if (uri != null) {
            scope.launch {
                isUploading = true
                val temporaryFileId = uploadProfileImage(context, uri, model)
                if (temporaryFileId == null) {
                    Toast.makeText(context, R.string.profile_upload_failed, Toast.LENGTH_LONG).show()
                } else if (model.changeOwnProfileImage(target.isAvatar, temporaryFileId)) {
                    Toast.makeText(context, R.string.profile_image_updated, Toast.LENGTH_SHORT).show()
                } else {
                    model.deleteTemporaryFile(temporaryFileId)
                    Toast.makeText(context, R.string.profile_upload_failed, Toast.LENGTH_LONG).show()
                }
                isUploading = false
            }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = stringResource(R.string.profile_settings_title),
            style = MaterialTheme.typography.titleLarge
        )
        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                ProfileImageControl(
                    label = stringResource(R.string.profile_avatar),
                    file = user.avatar,
                    model = model,
                    isBusy = isUploading,
                    onChoose = {
                        imageTarget = ProfileImageTarget.AVATAR
                        imagePicker.launch("image/*")
                    },
                    onRemove = {
                        scope.launch {
                            if (model.changeOwnProfileImage(isAvatar = true, fileId = null)) {
                                Toast.makeText(context, R.string.profile_image_removed, Toast.LENGTH_SHORT).show()
                            } else {
                                Toast.makeText(context, R.string.profile_upload_failed, Toast.LENGTH_LONG).show()
                            }
                        }
                    }
                )
                ProfileImageControl(
                    label = stringResource(R.string.profile_banner),
                    file = user.banner,
                    model = model,
                    isBusy = isUploading,
                    onChoose = {
                        imageTarget = ProfileImageTarget.BANNER
                        imagePicker.launch("image/*")
                    },
                    onRemove = {
                        scope.launch {
                            if (model.changeOwnProfileImage(isAvatar = false, fileId = null)) {
                                Toast.makeText(context, R.string.profile_image_removed, Toast.LENGTH_SHORT).show()
                            } else {
                                Toast.makeText(context, R.string.profile_upload_failed, Toast.LENGTH_LONG).show()
                            }
                        }
                    }
                )
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it.take(24) },
                    label = { Text(stringResource(R.string.profile_name)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = bio,
                    onValueChange = { bio = it.take(160) },
                    label = { Text(stringResource(R.string.profile_bio)) },
                    minLines = 2,
                    maxLines = 4,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = profileColor,
                    onValueChange = { profileColor = it },
                    label = { Text(stringResource(R.string.profile_color)) },
                    singleLine = true,
                    isError = !isValidProfileColor(profileColor),
                    supportingText = {
                        Text(stringResource(if (isValidProfileColor(profileColor)) R.string.profile_color_hint else R.string.profile_color_invalid))
                    },
                    modifier = Modifier.fillMaxWidth()
                )
                Button(
                    onClick = {
                        scope.launch {
                            isSaving = true
                            val saved = model.updateOwnProfile(name, profileColor, bio)
                            isSaving = false
                            Toast.makeText(
                                context,
                                if (saved) R.string.profile_saved else R.string.profile_save_failed,
                                if (saved) Toast.LENGTH_SHORT else Toast.LENGTH_LONG
                            ).show()
                        }
                    },
                    enabled = !isSaving && !isUploading && name.isNotBlank() && isValidProfileColor(profileColor)
                ) {
                    if (isSaving) {
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    } else {
                        Text(stringResource(R.string.profile_save))
                    }
                }
            }
        }
    }
}

internal fun isValidProfileColor(value: String): Boolean =
    Regex("^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$").matches(value)

@Composable
private fun ProfileImageControl(
    label: String,
    file: MessageFile?,
    model: CoveViewModel,
    isBusy: Boolean,
    onChoose: () -> Unit,
    onRemove: () -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ProfileImagePreview(file, model, Modifier.size(width = 92.dp, height = 72.dp))
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, style = MaterialTheme.typography.titleSmall)
            OutlinedButton(onClick = onChoose, enabled = !isBusy) {
                Text(stringResource(R.string.profile_choose_image))
            }
            if (file != null) {
                OutlinedButton(onClick = onRemove, enabled = !isBusy) {
                    Text(stringResource(R.string.profile_remove_image))
                }
            }
        }
    }
}

@Composable
private fun ProfileImagePreview(file: MessageFile?, model: CoveViewModel, modifier: Modifier = Modifier) {
    val url = file?.let(model::publicFileUrl)
    val bitmap by produceState<ImageBitmap?>(null, url) {
        value = url?.let { fileUrl ->
            runCatching {
                val bytes = model.downloadPublicFile(fileUrl)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
            }.getOrNull()
        }
    }
    val shape = RoundedCornerShape(12.dp)
    Card(modifier = modifier, shape = shape) {
        if (bitmap == null) {
            androidx.compose.foundation.layout.Box(contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.profile_no_image), style = MaterialTheme.typography.labelSmall)
            }
        } else {
            Image(
                bitmap = bitmap!!,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().height(72.dp).clip(shape)
            )
        }
    }
}

private suspend fun uploadProfileImage(
    context: android.content.Context,
    uri: Uri,
    model: CoveViewModel
): String? = runCatching {
    val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        ?: throw IllegalStateException("Unable to read selected image")
    val mimeType = context.contentResolver.getType(uri) ?: "image/jpeg"
    val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType) ?: "jpg"
    model.uploadAttachment(bytes, "profile-image.$extension", mimeType).id
}.getOrNull()
