# iPhone version metadata sync for Android UI release

- The Android-only navigation change advanced Android to version `1.1`, build `23`. Per the native
  app version rule, the iPhone app and Live Activity `MARKETING_VERSION` values were synchronized to
  `1.1`, with their `CURRENT_PROJECT_VERSION` values advanced to `20`.
- Apple Watch targets were not changed. No iOS feature source was modified and no iOS build was run.
- `plutil -lint apps/apple-mobile/Sharkord.xcodeproj/project.pbxproj` passed.

## Navigation visibility correction follow-up

- Advanced the iPhone app and Live Activity metadata to `1.2`, build `21`, alongside Android `1.2`,
  build `24`, for the follow-up navigation correction. Apple Watch remains unchanged.
- No iOS feature source was modified and no iOS build was run. `plutil -lint` passed.

## Navigation banner follow-up

- Advanced iPhone app and Live Activity metadata to `1.3`, build `22`, alongside Android `1.3`,
  build `25`. Apple Watch remains unchanged.
- No iOS feature source was modified and no iOS build was run. `plutil -lint` passed.

## Android gesture-spacing follow-up

- Advanced iPhone app and Live Activity metadata to `1.4`, build `23`, alongside Android `1.4`,
  build `26`. Apple Watch remains unchanged.
- No iOS feature source was modified and no iOS build was run. `plutil -lint` passed.

## Android voice connection controls follow-up

- Advanced iPhone app and Live Activity metadata to `1.5`, build `24`, alongside Android `1.5`,
  build `27`. Apple Watch remains unchanged.
- No iOS feature source was modified and no iOS build was run. `plutil -lint` passed.

## Android direct-message overflow follow-up

- Advanced iPhone app and Live Activity metadata to `1.6`, build `25`, alongside Android `1.6`,
  build `28`. Apple Watch remains unchanged.
- No iOS feature source was modified and no iOS build was run. `plutil -lint` passed.

## Android direct-message empty-state follow-up

- Advanced iPhone app and Live Activity metadata to `1.7`, build `26`, alongside Android `1.7`,
  build `29`. Apple Watch remains unchanged.
- No iOS feature source was modified and no iOS build was run. `plutil -lint` passed.

## Android screen-sharing follow-up

- Advanced the iPhone app and Live Activity metadata to `1.8`, build `27`, alongside Android
  `1.8`, build `30`. Apple Watch settings were not changed by this task.
- No iOS feature source was modified and no iOS build was run. `plutil -lint` passed.
