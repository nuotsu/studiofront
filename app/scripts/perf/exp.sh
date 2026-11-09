#!/bin/zsh
# Usage: exp.sh [nobuild] <flagset> [<flagset> ...]   (flagset "none" = no flags)
# Runs the benchmark on the cached account once per flag set and prints a
# summary line for each.
set -e
SCRATCH=/private/tmp/claude-501/-Users-mitchell-Developer-nuotsu-studiofront/6e65bfec-6b8c-477f-bb02-27e92659f93f/scratchpad
APPDIR=/Users/mitchell/Developer/nuotsu/studiofront/.claude/worktrees/v0.3-org-sidebar/app
cd "$APPDIR"
if [ "$1" = nobuild ]; then
  shift
else
  xcodegen generate --quiet
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project Studiofront.xcodeproj -scheme Studiofront -configuration Release \
    -derivedDataPath "$SCRATCH/dd-bench" \
    SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) BENCHMARK' \
    build > "$SCRATCH/bench-build.log" 2>&1 || { grep -E "error:" "$SCRATCH/bench-build.log" | head -20; echo BUILD FAILED; exit 1; }
fi
APP="$SCRATCH/dd-bench/Build/Products/Release/Studiofront.app"
for FLAGS in "$@"; do
  OUT="$SCRATCH/exp-$FLAGS.txt"
  rm -f "$OUT"
  if [ "$FLAGS" = none ]; then
    open -n -W --stdout "$OUT" --stderr "$SCRATCH/bench-stderr.txt" "$APP" --args --benchmark
  else
    open -n -W --stdout "$OUT" --stderr "$SCRATCH/bench-stderr.txt" "$APP" --args --benchmark "--perf=$FLAGS"
  fi
  python3 -I "$SCRATCH/summarize.py" "$FLAGS" "$OUT"
done
