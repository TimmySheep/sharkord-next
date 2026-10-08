# Xcode simulator build fix

## Changes

- Added the `.awaitingServerPassword` session phase to the iPhone root view routing. The phase now
  displays the connect screen instead of leaving the `switch` incomplete.
- Synchronized Android, iPhone, and Live Activity to version `1.13`, build `14`. Updated Apple Watch
  to version `1.9`, build `10` because its simulator build was part of this fix.

## Verification

- `xcodebuild -project apps/apple-mobile/Sharkord.xcodeproj -scheme Sharkord -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -configuration Debug build -quiet` passed.
- `xcodebuild -project apps/apple-mobile/Sharkord.xcodeproj -scheme SharkordWatch -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 4 (49mm)' -configuration Debug build -quiet` passed after the version update.
- The 68 Watch `Undefined symbol` diagnostics shown in Xcode were not reproduced by the command-line Watch scheme build. Their exact origin is unconfirmed; no claim is made that the simulator app was launched or visually tested.
