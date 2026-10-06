# Sharkord iOS (first skeleton)

> **本版没有任何功能，只是把框架搭出来了。**
> 屏幕、导航、目标结构、灵动岛扩展都能编译和运行，但**不连接任何服务器**，
> 里面的频道、消息、成员、语音状态全部是写死的示例数据，界面上都标了"离线示例"。
>
> **No functionality in this version: this is a framework only.** Every screen, route,
> build target and the Dynamic Island extension compile and launch, but **nothing talks
> to a server**. All channel, message, member and voice state is hard-coded sample data,
> labelled as such on screen.

The native iPhone/iPad client. This is **stage one: a shell only.** Every screen, route and piece of
navigation exists and compiles; **nothing talks to a server yet.** The sample workspace is local data
deliberately labelled as such on screen, so no mock can be mistaken for a working session.

Design document for the whole native programme is [`docs/NATIVE_STRATEGY.md`](../../docs/NATIVE_STRATEGY.md).
This directory implements its §3.1 layout.

## Build it

```bash
cd apps/apple-mobile
open Sharkord.xcodeproj          # run the Sharkord scheme on any iOS 17+ simulator
```

or from the command line (no signing needed for the simulator):

```bash
xcodebuild -project Sharkord.xcodeproj -scheme Sharkord \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

That builds both targets: `Sharkord` (the app) and `SharkordLiveActivity` (the widget extension),
and embeds the extension in `Sharkord.app/PlugIns/`.

Verified on Xcode 27.0 with the iOS 27.0 SDK: `clean build` succeeds with **zero Swift warnings**,
the extension validates as an embedded binary, and the produced `Info.plist` contains
`NSSupportsLiveActivities = true` plus `NSExtensionPointIdentifier = com.apple.widgetkit-extension`.

## Targets

| Target | Product | Contents |
| --- | --- | --- |
| `Sharkord` | `Sharkord.app` | the app: onboarding, workspace, design system, `LiveActivityController` |
| `SharkordLiveActivity` | `SharkordLiveActivity.appex` | widget extension: `ActivityConfiguration` rendering the lock screen view and all four Dynamic Island regions |

Both compile `Sharkord/Activities/LiveActivityAttributes.swift` directly (listed twice in
`project.pbxproj`), so the two sides cannot drift apart on what a session looks like. The extension
also compiles `Sharkord/DesignSystem.swift` for the brand colour rather than repeating the hex value.

## What is on screen

| Screen | State |
| --- | --- |
| `ConnectView` | server address, account, password. The connect button is intentionally disabled; the card below it opens the offline workspace so the layout can be reviewed. |
| `ChannelListView` | categories and channels, text and voice, with selection. Drives a push stack on iPhone and a split view detail on iPad. |
| `ChannelDetailView` | text channel: topic, message list, working local composer. voice channel: member roster, join button disabled. |
| `MembersView` | roster grouped by presence, speaking ring on the avatar. |
| `SettingsView` | stub rows that mark where real values land once the session layer exists; a Live Activity preview hook; plus the way back to onboarding. |

iPhone gets a tab bar plus a navigation stack; iPad gets a `NavigationSplitView`, per
[`docs/NATIVE_STRATEGY.md`](../../docs/NATIVE_STRATEGY.md) §3.1 "UI" row.

## Dynamic Island (Live Activity)

Framework is in place, **driven by nothing**:

- `Sharkord/Activities/LiveActivityAttributes.swift` — `ActivityAttributes` plus `ContentState`
  (`channelName`, `topic`, `participantCount`, `isSpeaking`) shared with the extension.
- `Sharkord/Activities/LiveActivityController.swift` — `start` / `update` / `end` around ActivityKit.
  No session code calls it.
- `SharkordLiveActivity/LiveActivityWidget.swift` — lock screen view plus `.leading`, `.trailing`,
  `.bottom`, `compactLeading`, `compactTrailing` and `minimal` regions.
- The app declares `NSSupportsLiveActivities`.

The only caller is the **"预览示例灵动岛"** row in Settings. It starts an activity carrying sample
data purely so the widget can be inspected before any session exists; when voice lands, that hook is
replaced by the real join and leave events and `LiveActivityController` should not need to change.

To see it: run on a device or simulator, allow Live Activities for Sharkord in system Settings, then
start the preview from the Settings tab. Live Activities require the app to be built with a team
selected (see below).

## What is deliberately not here

- **No networking.** No `GET /info`, no `POST /login`, no websocket handshake. That is Phase-1 steps 1
  to 10 in the strategy document.
- **No voice.** No WebRTC, no mediasoup, no `AVAudioSession`. The microphone usage string is already
  declared so Phase-2 does not need an Info.plist change.
- **No live session behind the Live Activity.** The extension renders whatever `ContentState` it is
  handed; nothing hands it real state.
- **No `packages/apple-core` yet.** The strategy document puts shared logic in a SwiftPM package that
  `apps/macos` will also vendor. Extracting it now would move files that have no logic to share, so the
  code is instead laid out in the folders the package will use (`Models`, `DesignSystem`, `AppModel`,
  `Activities`, `Onboarding`, `Workspace`). The extraction is a mechanical move when real protocol
  code arrives.
- **No string catalog.** Strings are inline Chinese for now, matching how `webspeak-ios` writes its
  design system. `Localizable.xcstrings` comes with the first user-facing feature.
- **No `DEVELOPMENT_TEAM`.** Open the project in Xcode and pick your team before running on a device
  or checking the Dynamic Island on hardware. The simulator does not need one.

## Notes for whoever picks this up

- `apps/apple-mobile` has **no `package.json`**, so Bun workspaces ignore it. Do not add one unless you
  want it in the workspace graph (`bun install` behaviour is verified in
  [`docs/NATIVE_STRATEGY.md`](../../docs/NATIVE_STRATEGY.md) §3).
- Bundle ids are `com.timmysheep.sharkord.ios` (app) and `com.timmysheep.sharkord.ios.LiveActivity`
  (extension); deployment target iOS 17.0; `TARGETED_DEVICE_FAMILY = 1,2`.
- The accent colour comes from the web client's `--sidebar-primary` token, and the avatar palette from
  its `--chart-*` tokens, so the native app reads as the same product rather than a different one.
- Visual language follows `webspeak-ios`: continuous corner radii, glass cards, uppercase eyebrow
  section labels, tinted 42pt icon chips. Reuse `DesignSystem.swift` instead of restyling per screen.
- Adding a Swift file means adding it to `Sharkord.xcodeproj/project.pbxproj` (file reference, build
  file, group child, Sources phase), and to the extension's Sources phase too if the extension needs
  it. Xcode does that for you when the file is added through the IDE.
