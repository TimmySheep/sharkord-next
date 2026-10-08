package com.timmysheep.cove.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.data.SessionState

@Composable
fun ServerBannerCard(state: SessionState, model: CoveViewModel) {
    // sharkord exposes a server logo, not a separate banner asset
    val logoUrl = state.serverLogo?.let(model::publicFileUrl)
    val bitmap by produceState<androidx.compose.ui.graphics.ImageBitmap?>(null, logoUrl) {
        value = logoUrl?.let { url ->
            runCatching {
                val bytes = model.downloadPublicFile(url)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
            }.getOrNull()
        }
    }
    val shape = MaterialTheme.shapes.large

    Surface(
        shape = shape,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 8.dp)
    ) {
        Box(modifier = Modifier.fillMaxWidth().height(104.dp)) {
            bitmap?.let { image ->
                Image(
                    bitmap = image,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxWidth().height(104.dp).clip(shape)
                )
            }
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.Black.copy(alpha = if (bitmap == null) 0f else 0.42f), shape)
                    .padding(horizontal = 16.dp, vertical = 20.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = state.serverName,
                    style = MaterialTheme.typography.titleLarge,
                    color = if (bitmap == null) MaterialTheme.colorScheme.onSurface else Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = state.serverAddress,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (bitmap == null) MaterialTheme.colorScheme.onSurfaceVariant else Color.White.copy(alpha = 0.86f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}
