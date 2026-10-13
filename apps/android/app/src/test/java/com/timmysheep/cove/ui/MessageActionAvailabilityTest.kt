package com.timmysheep.cove.ui

import com.timmysheep.cove.data.Message
import org.junit.Assert.assertEquals
import org.junit.Test

class MessageActionAvailabilityTest {
    private val message = Message(id = 1, channelId = 2)

    @Test
    fun ownMessageAllowsEditAndDeleteButNotPrivilegedActions() {
        assertEquals(
            MessageActionAvailability(edit = true, delete = true, pin = false, react = false),
            messageActionAvailability(message, isOwnMessage = true, canManageMessages = false, canReact = false)
        )
    }

    @Test
    fun serverMarkedUneditableMessagesCannotBeEdited() {
        assertEquals(false, messageActionAvailability(message.copy(editable = false), true, true, true).edit)
    }

    @Test
    fun moderatorCanDeleteAndPinButCannotEditAnotherUsersMessage() {
        assertEquals(
            MessageActionAvailability(edit = false, delete = true, pin = true, react = true),
            messageActionAvailability(message, isOwnMessage = false, canManageMessages = true, canReact = true)
        )
    }

    @Test
    fun ordinaryUserCannotModifyAnotherUsersMessage() {
        assertEquals(
            MessageActionAvailability(edit = false, delete = false, pin = false, react = true),
            messageActionAvailability(message, isOwnMessage = false, canManageMessages = false, canReact = true)
        )
    }
}
