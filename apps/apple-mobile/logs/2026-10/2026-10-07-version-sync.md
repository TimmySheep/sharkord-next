# iPhone app version sync

- Updated the iPhone app and its Live Activity extension in Debug and Release configurations to
  marketing version 1.1 and build number 2. The unrelated Apple Watch target remains at version
  0.1.0 and build number 1.
- `xcodebuild -list` recognized the project targets and schemes. The iPhone simulator build was
  attempted but failed compiling `Sharkord/RootView.swift` because its `session.phase` switch does
  not handle `.awaitingServerPassword`. That source file was not changed in this task.
