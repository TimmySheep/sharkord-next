#!/bin/sh
set -eu

root="$(cd "$(dirname "$0")/../../.." && pwd)"
macos_media="$root/apps/macos/Resources/voice-media"
windows_media="$root/apps/windows/src/Sharkord.App/Assets/VoiceMedia"
rnnoise_bundle="$root/apps/client/public/rnnoise/rnnoise-bundle.js"
rnnoise_processor="$root/apps/client/public/rnnoise/rnnoise-worklet-processor.js"
rnnoise_marker='// rnnoise-worklet-processor.js'

bun build "$root/apps/client/scripts/voice-worker.ts" \
  --target browser \
  --outfile "$macos_media/voice-worker.js"
cp "$root/apps/client/scripts/voice-media.html" "$macos_media/index.html"
cp "$macos_media/voice-worker.js" "$windows_media/voice-worker.js"
cp "$macos_media/index.html" "$windows_media/index.html"

for media_dir in "$macos_media" "$windows_media"; do
  python3 - "$rnnoise_bundle" "$rnnoise_processor" "$rnnoise_marker" "$media_dir/rnnoise-bundle.js" <<'PY'
from pathlib import Path
import sys

bundle_path, processor_path, marker, output_path = map(Path, sys.argv[1:])
bundle = bundle_path.read_text()
prefix, separator, _ = bundle.partition(str(marker))
if not separator:
    raise SystemExit("RNNoise bundle processor marker was not found")
processor = processor_path.read_text()
Path(output_path).write_text(prefix.rstrip() + "\n\n" + processor)
PY
done

cp "$root/apps/client/public/rnnoise/COPYING" "$macos_media/RNNOISE-COPYING.txt"
cp "$root/apps/client/public/rnnoise/COPYING" "$windows_media/RNNOISE-COPYING.txt"
