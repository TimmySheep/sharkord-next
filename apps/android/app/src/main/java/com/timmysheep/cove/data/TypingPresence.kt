package com.timmysheep.cove.data

import kotlinx.serialization.Serializable

@Serializable
data class TypingEvent(val channelId: Int, val userId: Int, val parentMessageId: Int? = null)

data class TypingScope(val channelId: Int, val parentMessageId: Int? = null)

data class TypingPresence(val scope: TypingScope, val userId: Int, val lastSeen: Long)

internal const val TYPING_WINDOW_MS = 6_000L

internal fun List<TypingPresence>.recordTyping(event: TypingEvent, now: Long): List<TypingPresence> {
    val scope = TypingScope(event.channelId, event.parentMessageId)
    return filterNot { it.scope == scope && it.userId == event.userId } + TypingPresence(scope, event.userId, now)
}

internal fun List<TypingPresence>.activeTyping(now: Long): List<TypingPresence> =
    filter { now - it.lastSeen in 0 until TYPING_WINDOW_MS }

fun SessionState.typingNames(scope: TypingScope): String = typingPresence
    .filter { it.scope == scope && it.userId != ownUserId }
    .mapNotNull { presence -> users.firstOrNull { it.id == presence.userId }?.name }
    .sorted()
    .joinToString(", ")
