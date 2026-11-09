#!/bin/zsh
# Usage: profile.sh <label>
# Builds an optimized, sampleable (Debug-signed) benchmark variant, runs it
# on the cached account, and samples the main thread while it runs.
set -e
SCRATCH=/private/tmp/claude-501/-Users-mitchell-Developer-nuotsu-studiofront/6e65bfec-6b8c-477f-bb02-27e92659f93f/scratchpad
APPDIR=/Users/mitchell/Developer/nuotsu/studiofront/.claude/worktrees/v0.3-org-sidebar/app
LABEL=$1
cd "$APPDIR"
xcodegen generate --quiet
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Studiofront.xcodeproj -scheme Studiofront -configuration Debug \
  -derivedDataPath "$SCRATCH/dd-prof" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) BENCHMARK' \
  SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule \
  build > "$SCRATCH/prof-build.log" 2>&1 || { grep -E "error:" "$SCRATCH/prof-build.log" | head -20; echo BUILD FAILED; exit 1; }
APP="$SCRATCH/dd-prof/Build/Products/Debug/Studiofront.app"
OUT="$SCRATCH/prof-$LABEL-bench.txt"
rm -f "$OUT" "$SCRATCH/prof-$LABEL-sample.txt"
open -n --stdout "$OUT" --stderr "$SCRATCH/prof-stderr.txt" "$APP" --args --benchmark ${2:+--perf=$2}
sleep 1.2
PID=$(pgrep -n -x Studiofront)
echo "sampling pid $PID"
sample "$PID" 9 1 -file "$SCRATCH/prof-$LABEL-sample.txt" > /dev/null 2>&1 || echo "sample failed"
sleep 6
echo "bench lines: $(grep -c BENCH "$OUT" 2>/dev/null)"
ls -la "$SCRATCH/prof-$LABEL-sample.txt"
