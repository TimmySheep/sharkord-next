package com.timmysheep.cove.ui

import com.timmysheep.cove.data.Message

internal data class MessageActionAvailability(
    val edit: Boolean,
    val delete: Boolean,
    val pin: Boolean,
    val react: Boolean
)

internal fun messageActionAvailability(
    message: Message,
    isOwnMessage: Boolean,
    canManageMessages: Boolean,
    canReact: Boolean
) = MessageActionAvailability(
    edit = isOwnMessage && message.editable != false,
    delete = isOwnMessage || canManageMessages,
    pin = canManageMessages,
    react = canReact
)
