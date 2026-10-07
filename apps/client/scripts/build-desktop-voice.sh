#!/bin/sh
set -eu

root="$(cd "$(dirname "$0")/../../.." && pwd)"
macos_media="$root/apps/macos/Resources/voice-media"
windows_media="$root/apps/windows/src/Sharkord.App/Assets/VoiceMedia"

bun build "$root/apps/client/scripts/voice-worker.ts" \
  --target browser \
  --outfile "$macos_media/voice-worker.js"
cp "$root/apps/client/scripts/voice-media.html" "$macos_media/index.html"
cp "$macos_media/voice-worker.js" "$windows_media/voice-worker.js"
cp "$macos_media/index.html" "$windows_media/index.html"
