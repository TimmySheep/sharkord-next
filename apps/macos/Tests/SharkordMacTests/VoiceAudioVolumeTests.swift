import XCTest
@testable import SharkordMac

final class VoiceAudioVolumeTests: XCTestCase {
    private let suiteName = "VoiceAudioVolumeTests.\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testVolumeIsClampedToTheMediaElementRange() {
        XCTAssertEqual(VoiceAudioVolumeSettings.clamped(-0.2), 0)
        XCTAssertEqual(VoiceAudioVolumeSettings.clamped(0.35), 0.35)
        XCTAssertEqual(VoiceAudioVolumeSettings.clamped(1.4), 1)
        XCTAssertEqual(VoiceAudioVolumeSettings.clamped(.nan), 1)
    }

    func testPreferencesRemainSeparateByUserAndAudioStream() {
        let volumes = [
            VoiceAudioVolumeSettings.key(userId: 21, stream: .user): 0.4,
            VoiceAudioVolumeSettings.key(userId: 21, stream: .screenShare): 0.75
        ]

        XCTAssertEqual(
            VoiceAudioVolumeSettings.volume(userId: 21, stream: .user, in: volumes),
            0.4
        )
        XCTAssertEqual(
            VoiceAudioVolumeSettings.volume(userId: 21, stream: .screenShare, in: volumes),
            0.75
        )
        XCTAssertEqual(
            VoiceAudioVolumeSettings.volume(userId: 22, stream: .user, in: volumes),
            1
        )
    }

    func testLoadingDropsInvalidEntriesAndClampsPersistedValues() {
        defaults.set(
            [
                "21:audio": 0.4,
                "21:screen_audio": 0.75,
                "0:audio": 0.2,
                "22:unknown": 0.8,
                "not-a-user:audio": 0.6,
                "23:audio": 1.8
            ],
            forKey: VoiceAudioVolumeSettings.defaultsKey
        )

        XCTAssertEqual(
            VoiceAudioVolumeSettings.load(from: defaults),
            ["21:audio": 0.4, "21:screen_audio": 0.75, "23:audio": 1]
        )
    }

    func testSavingOnlyPersistsSupportedAudioStreams() {
        VoiceAudioVolumeSettings.save(
            ["21:audio": 0.4, "21:screen_audio": 0.75, "22:video": 0.2],
            to: defaults
        )

        XCTAssertEqual(
            VoiceAudioVolumeSettings.load(from: defaults),
            ["21:audio": 0.4, "21:screen_audio": 0.75]
        )
    }
}
