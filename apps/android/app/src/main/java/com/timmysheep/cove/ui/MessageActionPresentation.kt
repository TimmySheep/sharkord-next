package com.timmysheep.cove.ui

internal fun isEmojiOnlyMessageContent(content: String): Boolean {
    val codePoints = content.trim().codePoints().toArray()
    if (codePoints.isEmpty()) return false

    val hasKeycap = codePoints.contains(0x20E3)
    val hasEmojiSymbol = codePoints.any {
        val type = Character.getType(it)
        type == Character.OTHER_SYMBOL.toInt() || type == Character.MODIFIER_SYMBOL.toInt()
    }
    if (!hasEmojiSymbol && !hasKeycap) return false

    return codePoints.all { codePoint ->
        when (Character.getType(codePoint)) {
            Character.OTHER_SYMBOL.toInt(),
            Character.MODIFIER_SYMBOL.toInt(),
            Character.NON_SPACING_MARK.toInt(),
            Character.COMBINING_SPACING_MARK.toInt(),
            Character.ENCLOSING_MARK.toInt(),
            Character.FORMAT.toInt() -> true
            else -> hasKeycap && (codePoint in '0'.code..'9'.code || codePoint == '#'.code || codePoint == '*'.code)
        }
    }
}
