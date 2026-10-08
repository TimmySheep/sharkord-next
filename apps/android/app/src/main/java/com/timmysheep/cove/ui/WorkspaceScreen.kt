package com.timmysheep.cove.ui

import androidx.compose.runtime.Composable
import com.timmysheep.cove.CoveViewModel
import com.timmysheep.cove.data.SessionState

@Composable
fun WorkspaceScreen(state: SessionState, model: CoveViewModel) {
    UnifiedWorkspaceScreen(state = state, model = model)
}
