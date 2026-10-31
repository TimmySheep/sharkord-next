package com.timmysheep.cove.ui

import kotlin.math.abs

private const val OPTIMAL_VOICE_TILE_ASPECT_RATIO = 1.5f

internal fun calculateVoiceGridColumns(
    totalCards: Int,
    containerWidth: Float,
    containerHeight: Float
): Int {
    if (totalCards <= 1 || containerWidth <= 0f || containerHeight <= 0f) return 1

    var bestColumns = 1
    var bestScore = Float.POSITIVE_INFINITY

    for (columns in 1..totalCards) {
        val rows = (totalCards + columns - 1) / columns
        val cellWidth = containerWidth / columns
        val cellHeight = containerHeight / rows
        val score = abs(cellWidth / cellHeight - OPTIMAL_VOICE_TILE_ASPECT_RATIO)

        if (score < bestScore) {
            bestScore = score
            bestColumns = columns
        }
    }

    return bestColumns
}

internal data class ScreenSharePreviewSize(
    val width: Float,
    val height: Float
)

internal fun calculateScreenSharePreviewSize(
    containerWidth: Float,
    containerHeight: Float
): ScreenSharePreviewSize {
    if (containerWidth <= 0f || containerHeight <= 0f) return ScreenSharePreviewSize(0f, 0f)

    val isLandscape = containerWidth > containerHeight
    val widthFraction = if (isLandscape) 0.3f else 0.44f
    val heightFraction = if (isLandscape) 0.38f else 0.2f

    return ScreenSharePreviewSize(
        width = minOf(containerWidth * widthFraction, 240f),
        height = minOf(containerHeight * heightFraction, 168f)
    )
}
