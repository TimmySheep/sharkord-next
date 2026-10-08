package com.timmysheep.cove.ui

import com.timmysheep.cove.data.Channel
import com.timmysheep.cove.data.ChannelType
import com.timmysheep.cove.data.SessionState
import com.timmysheep.cove.data.SharkordApi
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MainNavigationDestinationTest {
    @Test
    fun keepsServerReturnedChannelsWhenPermissionMapIsIncomplete() {
        val state = SessionState(
            channels = listOf(
                Channel(id = 11, type = ChannelType.TEXT, name = "general", isPrivate = true),
                Channel(id = 12, type = ChannelType.VOICE, name = "voice"),
                Channel(id = 13, type = ChannelType.TEXT, name = "dm", isDm = true)
            ),
            channelPermissions = SharkordApi.protocolJson.parseToJsonElement(
                """{"11":{"permissions":{"VIEW_CHANNEL":false}}}"""
            ).jsonObject
        )

        assertEquals(listOf(11, 12), navigationServerChannels(state).map(Channel::id))
    }

    @Test
    fun onlyShowsAllDirectMessagesWhenMoreThanThreeAreAvailable() {
        assertFalse(shouldShowAllDirectMessages(0))
        assertFalse(shouldShowAllDirectMessages(3))
        assertTrue(shouldShowAllDirectMessages(4))
    }
}
