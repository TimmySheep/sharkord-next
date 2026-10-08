# Connect screen appearance and screen-share permissions

## Changes

- The iOS connect flow now follows the system appearance. The workspace remains dark as
  before. Shared surface and text colors now use adaptive system colors so the connect form,
  card, and background stay legible in light and dark appearance.
- The shared server permission summary now includes the existing Owner bypass for private
  non-DM channels. This prevents the iOS screen-share permission check from rejecting an
  Owner based on a stale false value. Server authorization rules did not change.

## Verification

- Swift parser checks passed for `RootView.swift`, `DesignSystem.swift`, and `ConnectView.swift`.
- `DesignSystem.swift` passed iOS Simulator SDK type checking.
- A full Xcode app build remains blocked by existing Watch target build problems: its app icon
  asset catalog has no applicable `AppIcon` content, and the Watch target attempts to link an
  iOS-simulator `SharkordCore.o`. These project and Watch asset changes predate this task and
  were left untouched.
- Simulator rendering and device appearance still need visual acceptance.

## Follow-up: corrected Xcode verification

The failures above came from the verification command passing `-sdk iphonesimulator` globally
to a scheme that also builds the Watch target. That forced the wrong SDK onto Watch build
steps. Re-running without a global SDK override and selecting an iOS Simulator destination
passed, and the resulting iOS app contains the embedded Watch app. The project and Watch icon
files did not need repair; the earlier build-blocker diagnosis was incorrect.
