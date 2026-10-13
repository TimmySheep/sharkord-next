package com.timmysheep.cove.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.timmysheep.cove.R
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

internal val startupSplashEnterEasing = CubicBezierEasing(0.16f, 1f, 0.3f, 1f)
internal val startupSplashExitEasing = CubicBezierEasing(0.42f, 0f, 1f, 1f)

internal fun startupSplashExitDistance(maxHeightPx: Float, iconSizePx: Float): Float =
    maxHeightPx / 2f + iconSizePx

@Composable
internal fun StartupSplashScreen(
    isReady: Boolean,
    onFinished: () -> Unit
) {
    val iconSize = 144.dp
    val iconAlpha = remember { Animatable(0f) }
    val iconScale = remember { Animatable(0.78f) }
    val verticalOffset = remember { Animatable(0f) }
    var iconEntered by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        coroutineScope {
            launch {
                iconAlpha.animateTo(
                    targetValue = 1f,
                    animationSpec = tween(durationMillis = 170, easing = startupSplashEnterEasing)
                )
            }
            launch {
                iconScale.animateTo(
                    targetValue = 1f,
                    animationSpec = tween(durationMillis = 260, easing = startupSplashEnterEasing)
                )
            }
        }
        iconEntered = true
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        val density = LocalDensity.current
        val exitDistance = with(density) {
            startupSplashExitDistance(maxHeight.toPx(), iconSize.toPx())
        }

        LaunchedEffect(isReady, iconEntered, exitDistance) {
            if (!isReady || !iconEntered) return@LaunchedEffect

            delay(80)
            verticalOffset.animateTo(
                targetValue = exitDistance,
                animationSpec = tween(durationMillis = 520, easing = startupSplashExitEasing)
            )
            onFinished()
        }

        Image(
            painter = painterResource(R.mipmap.ic_launcher),
            contentDescription = null,
            modifier = Modifier
                .align(Alignment.Center)
                .size(iconSize)
                .clip(RoundedCornerShape(28.dp))
                .graphicsLayer {
                    alpha = iconAlpha.value
                    scaleX = iconScale.value
                    scaleY = iconScale.value
                }
                .offset { IntOffset(0, verticalOffset.value.roundToInt()) }
        )
    }
}
