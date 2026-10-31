package com.timmysheep.cove.data

import java.io.ByteArrayOutputStream
import java.io.InputStream
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

fun SessionState.canUploadAttachments(channel: Channel): Boolean =
    hasServerPermission("UPLOAD_FILES") &&
        publicSettings["storageUploadEnabled"]?.jsonPrimitive?.booleanOrNull != false &&
        (!channel.isDm || publicSettings["storageFileSharingInDirectMessages"]?.jsonPrimitive?.booleanOrNull != false)

fun SessionState.attachmentSlots(pendingCount: Int): Int =
    ((publicSettings["storageMaxFilesPerMessage"]?.jsonPrimitive?.intOrNull ?: 10) - pendingCount).coerceAtLeast(0)

internal fun readAttachment(input: InputStream, maximumSize: Long?, tooLargeMessage: String): ByteArray {
    val output = ByteArrayOutputStream()
    val buffer = ByteArray(8_192)
    var total = 0L
    while (true) {
        val read = input.read(buffer)
        if (read < 0) break
        total += read
        require(maximumSize == null || total <= maximumSize) { tooLargeMessage }
        output.write(buffer, 0, read)
    }
    return output.toByteArray()
}
