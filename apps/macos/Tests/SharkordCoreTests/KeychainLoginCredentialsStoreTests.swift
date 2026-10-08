import Foundation
import Testing

@testable import SharkordCore

@Suite
struct KeychainLoginCredentialsStoreTests {
    @Test
    func storedCredentialsRoundTripIncludingOptionalServerPassword() throws {
        let credentials = StoredLoginCredentials(
            host: "https://chat.example",
            identity: "ada",
            password: "account-password",
            serverPassword: "room-password"
        )
        let data = try JSONEncoder().encode(credentials)
        let decoded = try JSONDecoder().decode(StoredLoginCredentials.self, from: data)

        #expect(decoded == credentials)
    }

    @Test
    func missingKeychainItemReturnsNoCredentials() {
        let store = KeychainLoginCredentialsStore(service: "com.timmysheep.cove.tests.\(UUID().uuidString)")

        #expect(store.credentials() == nil)
    }
}
