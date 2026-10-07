package com.timmysheep.cove.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class VoiceGridLayoutTest {
    @Test
    fun usesOneFullStageForOneParticipant() {
        assertEquals(1, calculateVoiceGridColumns(1, 400f, 800f))
    }

    @Test
    fun stacksSmallGroupsInPortrait() {
        assertEquals(1, calculateVoiceGridColumns(3, 400f, 800f))
    }

    @Test
    fun usesMultipleColumnsWhenTheStageIsWide() {
        assertEquals(2, calculateVoiceGridColumns(2, 800f, 400f))
    }

    @Test
    fun fallsBackToOneColumnForAnUnmeasuredStage() {
        assertEquals(1, calculateVoiceGridColumns(4, 0f, 800f))
    }
}
