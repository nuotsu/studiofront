"""Summarize a `sample` report: inclusive main-thread samples per symbol.

Usage: analyze_sample.py <sample.txt> [--under SUBSTR] [filter-substring ...]

--under SUBSTR only counts frames that have an ancestor containing SUBSTR.
"""
import re
import sys
from collections import Counter

args = sys.argv[1:]
path = args.pop(0)
under = None
if args and args[0] == "--under":
    args.pop(0)
    under = args.pop(0).lower()
filters = [a.lower() for a in args]

thread_re = re.compile(r"^\s*(\d+)\s+Thread_")
line_re = re.compile(r"^([ +!:|]*)(\d+) (.+?)  \(in ([^)]+)\)")

inclusive = Counter()
total = 0
in_main = False
stack = []  # (depth, symbol)
with open(path, errors="replace") as handle:
    for raw in handle:
        thread = thread_re.match(raw)
        if thread:
            in_main = "Main Thread" in raw or "com.apple.main-thread" in raw
            stack = []
            if in_main:
                total = int(thread.group(1))
            continue
        if raw.startswith("Total number in stack") or raw.startswith("Sort by top of stack"):
            in_main = False
        if not in_main:
            continue
        m = line_re.match(raw)
        if not m:
            continue
        depth = len(m.group(1))
        count = int(m.group(2))
        symbol = f"{m.group(3)} [{m.group(4)}]"
        while stack and stack[-1][0] >= depth:
            stack.pop()
        ancestors = [s for _, s in stack]
        if symbol not in ancestors and (under is None or any(under in a.lower() for a in ancestors)):
            inclusive[symbol] += count
        stack.append((depth, symbol))

print(f"main thread samples: {total}")
shown = 0
for symbol, count in inclusive.most_common():
    if filters and not any(f in symbol.lower() for f in filters):
        continue
    print(f"{count:6d}  {symbol[:190]}")
    shown += 1
    if shown >= 80:
        break
