#!/usr/bin/env bash
# Captures a screen recording of the showcase tour for marketing.
# Prereq: `xcodebuild build-for-testing ... -scheme marble` has already built the
# MarbleUITests bundle (so this only launches + records, no long build during capture).
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

UDID=${MARBLE_SIMULATOR_ID:-$("${ROOT_DIR}/scripts/sim_destination.sh" | sed 's/^id=//')}
OUT_DIR="marketing/assets/recordings"
RAW="${OUT_DIR}/tour-raw.mov"
mkdir -p "$OUT_DIR"

echo "Simulator: $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

# Clean, deterministic status bar (9:41, full signal/battery, no carrier text).
xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --operatorName "" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 || true

# Start recording in the background.
rm -f "$RAW"
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$RAW" &
REC_PID=$!
sleep 1

# Run the tour against the already-built bundle (fast launch, no compile).
set +e
xcodebuild test-without-building \
  -project marble.xcodeproj -scheme marble \
  -destination "id=${UDID}" -configuration Debug \
  -only-testing:MarbleUITests/AdCaptureUITests/testShowcaseTour \
  -resultBundlePath TestResults/AdCapture.xcresult 2>&1 | tail -6
set -e

# Stop recording and flush the file.
kill -INT "$REC_PID" 2>/dev/null || true
wait "$REC_PID" 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear || true

echo "Raw recording:"
ls -la "$RAW" || true

# Optional trim/transcode if ffmpeg is available (drop the harness lead-in).
if command -v ffmpeg >/dev/null 2>&1; then
  FINAL="${OUT_DIR}/tour.mp4"
  ffmpeg -y -ss 4 -i "$RAW" -t 31 -an -vcodec libx264 -pix_fmt yuv420p "$FINAL" >/dev/null 2>&1 || true
  echo "Trimmed recording: ${FINAL}"
  ls -la "$FINAL" || true
fi
