#!/bin/zsh
# Usage: bench.sh <label> [extra app args...]
# Builds the Release benchmark variant and runs it, writing results to
# scratchpad/bench-<label>.txt
set -e
SCRATCH=/private/tmp/claude-501/-Users-mitchell-Developer-nuotsu-studiofront/6e65bfec-6b8c-477f-bb02-27e92659f93f/scratchpad
APPDIR=/Users/mitchell/Developer/nuotsu/studiofront/.claude/worktrees/v0.3-org-sidebar/app
LABEL=$1
shift
cd "$APPDIR"
xcodegen generate --quiet
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Studiofront.xcodeproj -scheme Studiofront -configuration Release \
  -derivedDataPath "$SCRATCH/dd-bench" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) BENCHMARK' \
  build > "$SCRATCH/bench-build.log" 2>&1 || { grep -E "error:" "$SCRATCH/bench-build.log" | head -20; echo BUILD FAILED; exit 1; }
APP="$SCRATCH/dd-bench/Build/Products/Release/Studiofront.app"
for MODE in cache synthetic=300; do
  OUT="$SCRATCH/bench-$LABEL-${MODE%%=*}.txt"
  rm -f "$OUT"
  if [ "$MODE" = cache ]; then
    open -n -W --stdout "$OUT" --stderr "$SCRATCH/bench-stderr.txt" "$APP" --args --benchmark "$@"
  else
    open -n -W --stdout "$OUT" --stderr "$SCRATCH/bench-stderr.txt" "$APP" --args --benchmark-synthetic=300 "$@"
  fi
  echo "== $MODE: $(grep -c BENCH "$OUT") lines"
done
