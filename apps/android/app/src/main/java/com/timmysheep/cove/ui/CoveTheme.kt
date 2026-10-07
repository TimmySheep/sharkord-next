package com.timmysheep.cove.ui

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

private val CoveLightColors = lightColorScheme(
    primary = Color(0xFF006A68),
    onPrimary = Color.White,
    primaryContainer = Color(0xFF71F7F0),
    onPrimaryContainer = Color(0xFF00201F),
    secondary = Color(0xFF416A68),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFC3EAE6),
    onSecondaryContainer = Color(0xFF00201E),
    tertiary = Color(0xFF496179),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFD1E4FF),
    onTertiaryContainer = Color(0xFF001D34),
    error = Color(0xFFBA1A1A),
    background = Color(0xFFF5FAF9),
    surface = Color(0xFFF5FAF9),
    surfaceVariant = Color(0xFFDAE5E3)
)

private val CoveDarkColors = darkColorScheme(
    primary = Color(0xFF4EDAD4),
    onPrimary = Color(0xFF003735),
    primaryContainer = Color(0xFF00504D),
    onPrimaryContainer = Color(0xFF71F7F0),
    secondary = Color(0xFFA7CECA),
    onSecondary = Color(0xFF103735),
    secondaryContainer = Color(0xFF294E4C),
    onSecondaryContainer = Color(0xFFC3EAE6),
    tertiary = Color(0xFFB1C9E5),
    onTertiary = Color(0xFF19334A),
    tertiaryContainer = Color(0xFF304A62),
    onTertiaryContainer = Color(0xFFD1E4FF),
    error = Color(0xFFFFB4AB),
    background = Color(0xFF0E1413),
    surface = Color(0xFF0E1413),
    surfaceVariant = Color(0xFF3F4947)
)

@Composable
fun CoveTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    val context = LocalContext.current
    val colors = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && darkTheme ->
            dynamicDarkColorScheme(context)
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            dynamicLightColorScheme(context)
        darkTheme -> CoveDarkColors
        else -> CoveLightColors
    }

    MaterialTheme(colorScheme = colors, content = content)
}
