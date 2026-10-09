package com.timmysheep.cove.data

import org.junit.Assert.*
import org.junit.Test

class TypingPresenceTest {
    @Test
    fun typingIsScopedToChannelAndThreadAndExcludesOwnUser() {
        val presence = emptyList<TypingPresence>()
            .recordTyping(TypingEvent(1, 2), 100)
            .recordTyping(TypingEvent(1, 3, 10), 100)
            .recordTyping(TypingEvent(1, 1), 100)
        val state = SessionState(ownUserId = 1, users = listOf(User(1, "self"), User(2, "channel"), User(3, "thread")), typingPresence = presence)
        assertEquals("channel", state.typingNames(TypingScope(1)))
        assertEquals("thread", state.typingNames(TypingScope(1, 10)))
        assertEquals("", state.typingNames(TypingScope(2)))
    }

    @Test
    fun repeatedEventsReplacePresenceAndExpiryIsBounded() {
        val presence = emptyList<TypingPresence>().recordTyping(TypingEvent(1, 2), 100).recordTyping(TypingEvent(1, 2), 200)
        assertEquals(1, presence.size)
        assertEquals(1, presence.activeTyping(6_199).size)
        assertTrue(presence.activeTyping(6_200).isEmpty())
        assertTrue(presence.activeTyping(199).isEmpty())
    }
}
