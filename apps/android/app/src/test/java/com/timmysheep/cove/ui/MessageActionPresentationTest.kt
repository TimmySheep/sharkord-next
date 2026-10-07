package com.timmysheep.cove.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MessageActionPresentationTest {
    @Test
    fun recognizesSingleEmoji() {
        assertTrue(isEmojiOnlyMessageContent("😀"))
    }

    @Test
    fun recognizesJoinedEmojiAndKeycaps() {
        assertTrue(isEmojiOnlyMessageContent("👩‍👩‍👧‍👦"))
        assertTrue(isEmojiOnlyMessageContent("1️⃣"))
    }

    @Test
    fun preservesTextAndPlainNumbers() {
        assertFalse(isEmojiOnlyMessageContent("hello 😀"))
        assertFalse(isEmojiOnlyMessageContent("1"))
    }
}
