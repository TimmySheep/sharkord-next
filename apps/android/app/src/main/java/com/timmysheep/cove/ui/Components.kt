package com.timmysheep.cove.ui

import android.graphics.BitmapFactory
import android.text.Html
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.data.MessageFile
import kotlin.math.absoluteValue
import kotlin.math.max

private val avatarBitmapCache = object : LruCache<String, android.graphics.Bitmap>(4 * 1024 * 1024) {
    override fun sizeOf(key: String, value: android.graphics.Bitmap): Int = max(value.allocationByteCount, 1)
}

@Composable
fun UserAvatar(
    name: String,
    modifier: Modifier = Modifier,
    size: androidx.compose.ui.unit.Dp = 42.dp,
    online: Boolean = false,
    avatar: MessageFile? = null,
    model: CoveViewModel? = null
) {
    val colors = listOf(
        MaterialTheme.colorScheme.primaryContainer,
        MaterialTheme.colorScheme.secondaryContainer,
        MaterialTheme.colorScheme.tertiaryContainer
    )
    val background = colors[name.hashCode().absoluteValue % colors.size]
    val avatarUrl = avatar?.let { file -> model?.publicFileUrl(file) }
    val image by produceState<androidx.compose.ui.graphics.ImageBitmap?>(null, avatarUrl) {
        value = null
        value = avatarUrl?.let { url ->
            runCatching {
                val cachedBitmap = avatarBitmapCache.get(url)
                val bitmap = cachedBitmap ?: run {
                    val bytes = model?.downloadPublicFile(url) ?: return@runCatching null
                    val options = BitmapFactory.Options().apply { inSampleSize = 4 }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)?.also {
                        avatarBitmapCache.put(url, it)
                    }
                }
                bitmap?.asImageBitmap()
            }.getOrNull()
        }
    }
    Box(modifier = modifier.size(size), contentAlignment = Alignment.Center) {
        Surface(color = background, shape = CircleShape, modifier = Modifier.size(size)) {
            if (image != null) {
                Image(
                    bitmap = image!!,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(size)
                )
            } else {
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        text = name.trim().firstOrNull()?.uppercase() ?: "?",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }
            }
        }
        if (online) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .size(12.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.tertiary)
            )
        }
    }
}

@Composable
fun SectionHeading(
    title: String,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )
        if (trailing != null) {
            Spacer(Modifier.width(8.dp))
            trailing()
        }
    }
}

@Composable
fun EmptyContent(
    title: String,
    modifier: Modifier = Modifier,
    body: String? = null
) {
    Box(modifier = modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
        androidx.compose.foundation.layout.Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            if (body != null) {
                Text(
                    text = body,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
        }
    }
}

fun htmlToPlainText(value: String?): String {
    if (value.isNullOrBlank()) return ""
    return Html.fromHtml(value, Html.FROM_HTML_MODE_COMPACT).toString().trim()
}

fun formatMessageTime(timestamp: Long): String {
    if (timestamp <= 0) return ""
    val instant = if (timestamp < 10_000_000_000L) timestamp * 1_000 else timestamp
    val formatter = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault())
    return formatter.format(java.util.Date(instant))
}
