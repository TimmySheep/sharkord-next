# Android and iOS feature parity

## Goal

Implement the four requested mobile feature areas on both native clients while reusing the
existing server protocol and keeping server authorization unchanged. Automated tests and
builds are in scope; device-level acceptance is for the user.

## Work areas

1. Message attachments: pick and upload files, attach them to messages, preview images, and
   open other file attachments.
2. Search and threads: search server messages/files, navigate to results, open a thread,
   load replies, and send replies into that thread.
3. Camera and media controls: publish local camera video, switch cameras, expose available
   receive-quality controls, and keep voice state synchronized.
4. Screen sharing: harden start/stop/error cleanup, make permission gates match the server,
   and keep the sharing control and remote stream presentation consistent on both clients.

## Acceptance boundary

- Run relevant Android unit tests, server permission/protocol tests if server code changes,
  Android lint/build, and iOS simulator build plus Swift checks.
- Do not install dependencies, deploy server changes, transfer artifacts, or operate a user
  device without separate authorization.
- Report any platform-specific limitation and give the user concise manual steps for device
  acceptance.

## Progress

- Both clients now have attachment upload/opening, image preview, message/file search, result
  navigation, thread paging/replies, local camera publishing and switching, and controls for
  available remote simulcast quality layers.
- Android and iOS screen-share start/stop paths use server and channel permission gates.
  Android uses MediaProjection; iOS currently captures Cove only. iOS full-device sharing
  after switching apps remains out of scope until a ReplayKit Broadcast Upload Extension is
  implemented.
- Automated checks passed: Android unit tests, lint and Debug build; targeted server voice and
  channel-permission tests plus type/lint/format checks; and the iOS Simulator build. Real-device
  camera, attachment, voice, and screen-share acceptance remains for the user.

## Android UX follow-up

- After login, Android should remain on the channel list home with no channel selected; opening a
  channel is an explicit user action. The channel title is larger and search stays in the top bar.
- Voice and channel chat are separate swipeable pages. Joined-call controls are pinned above
  the app tabs, and the message composer applies IME insets.
- Screen-share capture is no longer blocked by a potentially stale local permission snapshot;
  the server remains authoritative when the producer is created.
- Automated Android tests, lint, and Debug build passed. Device-level confirmation remains
  pending because no Android device is attached.
- At the user's request, copied the Debug APK to a local Downloads folder and verified its
  checksum against the project build output. No device was installed or operated.
- Centered the Android connect form within the visible safe area, retaining scrolling for short
  screens and IME. Tests, lint, and Debug build passed. A new APK was saved separately in
  Downloads as `cove-android-debug-2026-10-07-connect-centered.apk`; the earlier APK was kept.

## Saved sign-in follow-up

- Android stores remembered credentials with AES-GCM and an Android Keystore key; Apple Watch
  stores them in its device-only Keychain. Both clients attempt auto sign-in at startup and
  offer a saved-account quick action plus a forget option. Remember-login is enabled by default
  and can be turned off. Server authentication is not bypassed.
- Includes the optional server password in secure storage. The Watch keeps the server-password
  challenge flow available if a saved login does not include a required password.
- Verification passed: Android unit tests, lint and Debug build; Watch simulator-target build;
  `bun run magic`, `bun run synci18n`, and `git diff --check`. Device acceptance remains with the
  user; neither an Android device nor an Apple Watch was operated.

## Android channel-home landing correction

- Removed the post-login assignment of the first text channel and the immediate `selectChannel`
  call. A successful login now opens the Channels destination with no active channel, so message
  loading and read-state changes begin only after the user selects one.
- The earlier post-login auto-selection behavior was incorrect and is superseded. Android tests,
  lint, and Debug build passed after the correction. Real-device confirmation remains pending;
  no Android device was operated.

## Android voice-channel interface polish

- Removed the channel-topic subtitle from channel detail so the channel name remains the single
  page heading.
- Replaced the voice-room member-count heading and horizontal name chips with wrapping square
  participant tiles. The join action remains available, and participants are visible before joining.
- Made microphone, speaker, camera, and screen-share controls equal-width labeled tonal buttons;
  hang-up is the fifth, red-emphasized control. Camera switching remains available as a small
  secondary action on the camera control.
- Android unit tests, lint, and Debug build passed. `bun run magic` completed with existing lint
  warnings and no errors; `git diff --check` passed. Device visual acceptance remains with the user.

## Android message-action cleanup

- Removed the per-message “Start a thread” / reply-count chip from the chat timeline. The existing
  action sheet opened from the message's three-dot button now contains that action and preserves
  the reply-count label when replies exist. Reaction chips remain inline.
- Android unit tests, lint, and Debug build passed. `bun run magic` completed with existing lint
  warnings and no errors; `git diff --check` passed. No Android device was operated.
- For attachment-only messages, the action sheet now omits the empty-message placeholder. Emoji
  reactions appear before a circular reply icon with no visible text; the thread action remains.
- Revalidation passed: Android unit tests, lint, Debug build, `bun run magic`, and
  `git diff --check`. Device visual acceptance remains pending.

## Android connect-screen theme contrast and version 1.1

- Set the remember-login label color explicitly to `MaterialTheme.colorScheme.onSurface` so it
  follows light and dark themes.
- Started the requested native version sequence: Android `versionName` and the iPhone app plus
  its Live Activity extension `MARKETING_VERSION` are now `1.1`; their build numbers are `2`.
  The unrelated Apple Watch target remains at `0.1.0` / build `1`.
- Android unit tests, lint, and Debug build passed. `bun run magic` completed with existing lint
  warnings and no errors; `git diff --check` passed. The iPhone simulator build is blocked by a
  Swift compile error in `Sharkord/RootView.swift`: its phase switch omits
  `.awaitingServerPassword`. That file was not changed in this task.

## Android voice-stage grid reference and version 1.2

- Reviewed the supplied Discord screenshot and the Web voice grid. Replaced fixed 104 dp voice
  participant tiles with a full-stage grid that selects columns from the measured stage dimensions
  using the Web grid's 1.5 target aspect ratio. In portrait, small groups stack and share the
  available height; avatar size follows each tile. Webcam streams now occupy their participant
  tile, while screen-share streams get a separate tile. Microphone and camera controls were left
  unchanged.
- Added unit coverage for single-user, portrait, wide-stage, and unmeasured layouts. Android unit
  tests, lint, and Debug build passed. `bun run magic` completed with existing repository warnings
  and no errors. No physical device was operated, so visual acceptance remains pending.
- Advanced Android and iPhone app versions together to `1.2`, build number `3`; Apple Watch remains
  unchanged. The iPhone project settings were updated but not rebuilt for this Android UI change.

## Android message-action layout and version 1.3

- Reviewed `Screenshot_2026-10-07-20-54-44-820_com.timmysheep.cove.jpg`. Emoji-only message content
  no longer occupies a redundant line above the quick-reaction choices, which now form a horizontal
  scrolling strip. Replaced the two prominent reply/thread actions with one reply dropdown; both
  direct reply and thread actions remain available inside it.
- Added unit tests for emoji-only content detection, including joined emoji and keycaps. Android
  unit tests, lint, and Debug build passed. `bun run magic` passed with existing repository lint
  warnings and no errors; `git diff --check` passed. No physical device was operated.
- Synchronized Android and iPhone versions to `1.3`, build number `4`; Apple Watch remains unchanged.
  Only the Android app was built for this UI change.

## Android settings cleanup and version 1.4

- Removed the language row's hardcoded “System default” subtitle, which duplicated the trailing
  current-language value and remained incorrect when another language was selected.
- Replaced the standalone About footer text with an About section and app-info card showing the
  name and current version. The content scrolls while the disconnect action remains fixed below it.
- Added app-version translations for all Android locales. `bun run synci18n` reported all
  translations up to date. Android unit tests, lint, Debug build, `bun run magic`, and
  `git diff --check` passed; `bun run magic` reported existing repository lint warnings.
- Synchronized Android and iPhone versions to `1.4`, build number `5`; Apple Watch remains
  unchanged. No physical device was operated and the iPhone app was not rebuilt.

## Android search field shape and version 1.5

- Applied the same rounded-rectangle Material shape to search fields in channel filtering, direct
  messages, the new-message member picker, and message search. Connection forms and the chat
  composer were not changed.
- Android unit tests, lint, Debug build, `bun run magic`, and `git diff --check` passed. The build
  emitted the existing Gradle deprecation and manifest warnings; `bun run magic` reported existing
  repository lint warnings. No physical device was operated, so visual acceptance remains pending.
- Synchronized Android and iPhone versions to `1.5`, build number `6`; Apple Watch remains
  unchanged. The iPhone app was not rebuilt.

## Android persistent voice quick controls and version 1.6

- Added a top control strip while connected to voice and browsing other destinations. It shows the
  active voice room and provides microphone, speaker-output, and leave actions. The active voice
  room retains its existing full control group so buttons are not duplicated.
- Microphone toggling reuses the runtime permission flow and all three actions reuse existing voice
  engine methods. Added accessibility descriptions in all five Android-supported locales.
- Android unit tests, lint, Debug build, `bun run magic`, and `git diff --check` passed. Existing
  repository lint warnings remain. No physical device was operated, so visual acceptance remains
  pending.
- Synchronized Android and iPhone versions to `1.6`, build number `7`; Apple Watch remains
  unchanged. The iPhone app was not rebuilt.
- Published Android source branch `release/android-1.6` at commit `0b27768` and the public preview
  release `native-android-v1.6`: https://github.com/TimmySheep/sharkord-next/releases/tag/native-android-v1.6
- Uploaded the 73,719,418-byte Debug APK; GitHub's SHA-256 matches the locally verified artifact:
  `2de3ffccf44188c8d2f4e33b6b7a2a67579f0cc1abb4f6ff02a9f5e5777e3678`. The release identifies it
  as a debug-signed preview, not a production or Play Store build.

## Cross-platform app icons and appearance variants

- Replaced the iPhone/iPad and Android launcher artwork with the supplied light and dark source
  images. iOS/iPadOS use the system-managed `Any` and `Dark` app-icon appearances; Xcode is set
  to include all app-icon assets while retaining the iOS 17 minimum deployment target. Android
  uses the `night` resource qualifier, with the light image as the default fallback.
- Replaced the Apple Watch app icon with the light image. watchOS uses light app icons rather than
  the iPhone/iPad dark appearance variant.
- Bumped Android, iPhone, Live Activity, and Watch versions to `1.7`, build `8`.
- Android unit tests, lint, and Debug build passed; the APK contains both launcher resource
  configurations and reports version `1.7` / `8`. The Watch simulator build passed, and Xcode
  asset output contains both iPhone and iPad icon appearances. The full iOS simulator build is
  blocked by the pre-existing `.awaitingServerPassword` switch case omission in `RootView.swift`.
- Changes are local only and were not pushed to GitHub. No simulator or physical device was
  operated.

## Android language switching fix and version 1.8

- The in-app locale picker used `AppCompatDelegate.setApplicationLocales` from a Compose host that
  extended `ComponentActivity`. Android's Compose per-app language guidance requires the host to
  extend `AppCompatActivity` for this API; the missing integration prevented the locale change from
  being applied to the activity.
- Switched `MainActivity` to `AppCompatActivity`, updated both Android theme resources to an
  AppCompat DayNight parent, and enabled AppCompat locale persistence for Android 12 and earlier.
- Android unit tests, lint, and Debug build passed. The APK reports version `1.8` / `9`, and its
  merged manifest contains the locale storage service and metadata. Device-level switching was not
  tested; the user needs to confirm on-device.
- Synchronized iPhone and Live Activity versions to `1.8`, build `9`; Apple Watch remains at
  `1.7`, build `8`. No iOS build was run for the version-only change.
- Changes are local and have not been pushed to GitHub.

## Android message action hierarchy and version 1.9

- Replaced the dominant full-width reply button and separate pin row with three equal-width,
  same-style controls at the bottom of the message action sheet: reply, thread/replies, and
  pin/unpin. Quick reactions remain in their existing row above. Message-owner edit/delete actions
  remain separate and above the shared bottom row.
- Android unit tests, lint, and Debug build passed. No simulator or physical device was operated,
  so visual acceptance remains pending.
- Synchronized Android, iPhone, and Live Activity versions to `1.9`, build `10`; Apple Watch remains
  at `1.7`, build `8`. Changes are local only and were not pushed to GitHub.

## Cross-platform diagnostics logging and version 1.10

- Added private, bounded local logs and user-triggered text export for Android, iPhone, and Apple
  Watch. The apps capture selected lifecycle, connection, protocol, voice, storage, and crash
  failures, with common credential values redacted. The UI states that message bodies and media
  are not intentionally collected.
- Android Settings can preview/export logs, and the connect screen can export them while
  disconnected. iPhone Settings and the connect screen open a diagnostics preview/share flow.
  Apple Watch exposes a diagnostics view and share action from its navigation.
- Android unit tests, lint, and Debug build passed. The Watch Simulator build passed. The iOS
  Simulator build is still blocked by the existing `.awaitingServerPassword` switch omission in
  `Sharkord/RootView.swift`; that unrelated file was not changed. No real device was operated.
- Synchronized Android, iPhone, and Live Activity to `1.10`, build `11`; Apple Watch is now `1.8`,
  build `9`. Changes are local only and were not pushed to GitHub.

## Android voice microphone-state hint and version 1.11

- Removed the redundant inline speaker-output instruction shown while the microphone is disabled
  in the voice room. The microphone button remains disabled and visually muted while speaker output
  is off; the existing microphone guard is unchanged.
- Removed the unused hint resource from all five Android locales. Android unit tests, lint, and
  Debug build passed. Existing Gradle, manifest, and Android API deprecation warnings remain. No
  physical device was operated.
- Synchronized Android, iPhone, and Live Activity to `1.11`, build `12`; Apple Watch remains at
  `1.8`, build `9`. Changes are local only and were not pushed to GitHub.

## Android voice-call notification and version 1.12

- Replaced the generic notification copy with the current voice channel name, a centered dot and
  participant count; the subtitle reflects the live microphone state. Content and action labels
  update as the call state changes.
- Added speaker, microphone, and leave-channel actions. The leave action exits only the voice
  channel. The ongoing notification now remains while connected even if both speaker and mic are
  off. Android strings and participant plurals cover all five supported locales.
- Android unit tests, lint, and Debug build passed. No physical device was operated, so the
  notification layout and actions remain pending device acceptance.
- Synchronized Android, iPhone, and Live Activity to `1.12`, build `13`; Apple Watch remains at
  `1.8`, build `9` in the local worktree. This GitHub sync includes Android progress and iPhone/Live
  Activity version settings; Watch and other platform changes remain local.

## iOS and Watch Xcode simulator build fix, version 1.13

- Added `.awaitingServerPassword` to the iPhone root view's session-phase routing, resolving the
  incomplete-switch compile error.
- iPhone Simulator Debug build for iPhone 18 Pro and Watch Simulator Debug build for Apple Watch
  Ultra 4 (49mm) both passed. The 68 Watch `Undefined symbol` diagnostics from Xcode did not
  reproduce in the command-line Watch build, so their exact origin remains unconfirmed. Simulator
  apps were not launched for visual testing.
- Synchronized Android, iPhone, and Live Activity to `1.13`, build `14`; Apple Watch is now `1.9`,
  build `10`.
