package com.timmysheep.cove.ui

import android.graphics.Bitmap
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

private const val MAX_AVATAR_COLOR_SAMPLES = 576
private const val MIN_TILE_CONTRAST = 3.0
private const val OPAQUE_ALPHA = 0xFF000000.toInt()
private const val WHITE = -1
private const val BLACK = OPAQUE_ALPHA

internal fun sampleAvatarPixels(bitmap: Bitmap): IntArray {
    val stepX = max((bitmap.width + 23) / 24, 1)
    val stepY = max((bitmap.height + 23) / 24, 1)
    val samples = ArrayList<Int>(MAX_AVATAR_COLOR_SAMPLES)
    for (y in 0 until bitmap.height step stepY) {
        for (x in 0 until bitmap.width step stepX) {
            val color = bitmap.getPixel(x, y)
            if ((color ushr 24) >= 0x80) samples += color
        }
    }
    return samples.toIntArray()
}

internal fun avatarTileBackgroundColor(samples: IntArray, surfaceColor: Int): Int? {
    val buckets = mutableMapOf<Int, ColorBucket>()
    samples.forEach { color ->
        if ((color ushr 24) < 0x80) return@forEach
        val red = color shr 16 and 0xFF
        val green = color shr 8 and 0xFF
        val blue = color and 0xFF
        val key = (red shr 3 shl 10) or (green shr 3 shl 5) or (blue shr 3)
        buckets.getOrPut(key, ::ColorBucket).add(red, green, blue)
    }
    val dominant = buckets.values.maxByOrNull(ColorBucket::count)?.toArgb() ?: return null
    return ensureTileContrast(dominant, surfaceColor)
}

internal fun avatarTileForegroundColor(backgroundColor: Int): Int =
    if (colorContrastRatio(WHITE, backgroundColor) >= colorContrastRatio(BLACK, backgroundColor)) {
        WHITE
    } else {
        BLACK
    }

internal fun colorContrastRatio(firstColor: Int, secondColor: Int): Double {
    val firstLuminance = relativeLuminance(firstColor)
    val secondLuminance = relativeLuminance(secondColor)
    return (max(firstLuminance, secondLuminance) + 0.05) /
        (min(firstLuminance, secondLuminance) + 0.05)
}

private fun ensureTileContrast(color: Int, surfaceColor: Int): Int {
    if (colorContrastRatio(color, surfaceColor) >= MIN_TILE_CONTRAST) return color
    val lightCandidate = blendToContrast(color, surfaceColor, WHITE)
    val darkCandidate = blendToContrast(color, surfaceColor, BLACK)
    return when {
        lightCandidate == null -> requireNotNull(darkCandidate).first
        darkCandidate == null -> lightCandidate.first
        lightCandidate.second <= darkCandidate.second -> lightCandidate.first
        else -> darkCandidate.first
    }
}

private fun blendToContrast(color: Int, surfaceColor: Int, target: Int): Pair<Int, Float>? {
    if (colorContrastRatio(target, surfaceColor) < MIN_TILE_CONTRAST) return null
    var low = 0f
    var high = 1f
    repeat(16) {
        val amount = (low + high) / 2f
        if (colorContrastRatio(blend(color, target, amount), surfaceColor) >= MIN_TILE_CONTRAST) {
            high = amount
        } else {
            low = amount
        }
    }
    return blend(color, target, high) to high
}

private fun blend(firstColor: Int, secondColor: Int, amount: Float): Int {
    val inverseAmount = 1f - amount
    val red = (((firstColor shr 16 and 0xFF) * inverseAmount) +
        ((secondColor shr 16 and 0xFF) * amount)).toInt()
    val green = (((firstColor shr 8 and 0xFF) * inverseAmount) +
        ((secondColor shr 8 and 0xFF) * amount)).toInt()
    val blue = (((firstColor and 0xFF) * inverseAmount) +
        ((secondColor and 0xFF) * amount)).toInt()
    return OPAQUE_ALPHA or (red shl 16) or (green shl 8) or blue
}

private fun relativeLuminance(color: Int): Double {
    val red = linearChannel(color shr 16 and 0xFF)
    val green = linearChannel(color shr 8 and 0xFF)
    val blue = linearChannel(color and 0xFF)
    return red * 0.2126 + green * 0.7152 + blue * 0.0722
}

private fun linearChannel(value: Int): Double {
    val channel = value / 255.0
    return if (channel <= 0.04045) channel / 12.92 else ((channel + 0.055) / 1.055).pow(2.4)
}

private class ColorBucket {
    var count = 0
        private set
    private var redTotal = 0
    private var greenTotal = 0
    private var blueTotal = 0

    fun add(red: Int, green: Int, blue: Int) {
        count += 1
        redTotal += red
        greenTotal += green
        blueTotal += blue
    }

    fun toArgb(): Int {
        val red = redTotal / count
        val green = greenTotal / count
        val blue = blueTotal / count
        return OPAQUE_ALPHA or (red shl 16) or (green shl 8) or blue
    }
}
