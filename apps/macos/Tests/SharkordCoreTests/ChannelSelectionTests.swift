import Testing
@testable import SharkordCore

@MainActor
struct ChannelSelectionTests {
    @Test func clearingTheOpenChannelResetsSelection() {
        let session = SharkordSession()
        session.selectedChannelId = 42

        session.clearChannelSelection()

        #expect(session.selectedChannelId == nil)
    }
}
