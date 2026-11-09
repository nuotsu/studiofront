#!/bin/zsh
# Usage: snap.sh <label>
# Builds the Release benchmark variant, runs it once on the cached account
# with --snapshots, and decodes the images into scratchpad/snap-<label>-*.png
set -e
SCRATCH=/private/tmp/claude-501/-Users-mitchell-Developer-nuotsu-studiofront/6e65bfec-6b8c-477f-bb02-27e92659f93f/scratchpad
APPDIR=/Users/mitchell/Developer/nuotsu/studiofront/.claude/worktrees/v0.3-org-sidebar/app
LABEL=$1
cd "$APPDIR"
xcodegen generate --quiet
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Studiofront.xcodeproj -scheme Studiofront -configuration Release \
  -derivedDataPath "$SCRATCH/dd-bench" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) BENCHMARK' \
  build > "$SCRATCH/bench-build.log" 2>&1 || { grep -E "error:" "$SCRATCH/bench-build.log" | head -20; echo BUILD FAILED; exit 1; }
APP="$SCRATCH/dd-bench/Build/Products/Release/Studiofront.app"
OUT="$SCRATCH/snap-$LABEL.txt"
rm -f "$OUT"
open -n -W --stdout "$OUT" --stderr "$SCRATCH/bench-stderr.txt" "$APP" --args --benchmark --snapshots
python3 -I "$SCRATCH/decode_snaps.py" "$OUT" "$SCRATCH/snap-$LABEL"
