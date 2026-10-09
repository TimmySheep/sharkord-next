package com.timmysheep.cove.voice

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull

private val PRODUCER_AUDIO_STAT_TYPES = setOf("media-source", "outbound-rtp")
private val CONSUMER_AUDIO_STAT_TYPES = setOf("inbound-rtp", "track")

internal fun producerAudioLevel(stats: String?): Float? =
    audioLevelFromStats(stats, PRODUCER_AUDIO_STAT_TYPES)

internal fun consumerAudioLevel(stats: String?): Float? =
    audioLevelFromStats(stats, CONSUMER_AUDIO_STAT_TYPES)

internal fun isVoiceSpeaking(audioLevel: Float?): Boolean {
    if (audioLevel == null || !audioLevel.isFinite()) return false
    return if (audioLevel <= 1f) audioLevel > 0.02f else audioLevel > 5f
}

private fun audioLevelFromStats(stats: String?, acceptedTypes: Set<String>): Float? {
    if (stats.isNullOrBlank()) return null
    return runCatching {
        Json.parseToJsonElement(stats).jsonArray.firstNotNullOfOrNull { element ->
            val stat = element.jsonObject
            val type = stat["type"]?.jsonPrimitive?.contentOrNull
            if (type !in acceptedTypes) return@firstNotNullOfOrNull null
            stat["audioLevel"]?.jsonPrimitive?.contentOrNull?.toFloatOrNull()
        }?.takeIf(Float::isFinite)
    }.getOrNull()
}
