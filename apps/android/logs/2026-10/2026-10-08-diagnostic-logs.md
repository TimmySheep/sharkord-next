# Android diagnostic logs and export

## Changes

- Added a local rolling diagnostic log store in the app's private files directory. It retains
  current and previous log files, records lifecycle, connection, HTTP/tRPC, JSON decode, and
  voice/screen-share failures, and includes stack traces for errors.
- Added redaction for credential assignments, query parameters, and Bearer tokens. Logs do not
  intentionally record message bodies or media content.
- Added a log preview and Android system document export action in Settings, plus an export
  action on the connect screen so logs remain accessible while disconnected.
- Added English, Simplified Chinese, German, Spanish, and French strings, plus tests for redaction
  and rotation.
- Advanced Android to version `1.10`, build `11`, in sync with the iPhone and Live Activity.

## Verification

- `:app:testDebugUnitTest`, `:app:lintDebug`, and `:app:assembleDebug` passed.
- No physical Android device was operated; on-device visual and export acceptance remains pending.
