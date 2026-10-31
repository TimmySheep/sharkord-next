# TestFlight upload 1.28 (47)

## Outcome

- Uploaded `cove` iOS version 1.28, build 47 to App Store Connect on 2026-10-31.
- App Store Connect build ID: `b0810e63-3d47-40a9-a857-b3fbfde67bcd`.
- Verified build processing state `VALID` and beta state `READY_FOR_BETA_TESTING` after setting the build's non-exempt encryption flag to false. The upload tool also reported `is-on-app-store-connect: true`.
- External beta state is `READY_FOR_BETA_SUBMISSION`; external TestFlight review was not submitted as part of this upload.

## Changes required by App Store validation

- Moved `RPBroadcastProcessModeSampleBuffer` to be a direct child of `NSExtension` in `SharkordBroadcastUpload/Info.plist`, matching the structure App Store Connect accepts.
- Added the `cove` display name to `SharkordLiveActivity/Info.plist`.
- Aligned the embedded Watch app version and build to 1.28 (47), matching the containing iOS app.
- Restored owner write permission on the two extension plists and the Xcode project file so the release configuration could be corrected.

## Verification

- Device archive and App Store export succeeded with App Store distribution provisioning profiles.
- Inspected the exported IPA and confirmed the app, broadcast extension, Live Activity extension, and Watch app use version 1.28 and build 47. Confirmed the broadcast extension process mode and App Group entitlements.
- The first upload was rejected for the broadcast process mode plist hierarchy, missing Live Activity display name, and Watch version mismatch. Those items were corrected before the successful upload.
- Read back the App Store Connect build and beta detail after upload. The build is valid and ready for internal beta testing.
