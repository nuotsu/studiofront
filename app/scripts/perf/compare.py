"""compare.py <before.txt> <after.txt> : side-by-side benchmark totals (ms)."""
import sys


def load(path):
    rows = []
    for line in open(path):
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 4 and parts[0] == "BENCH":
            try:
                rows.append((parts[1], float(parts[2]), float(parts[3])))
            except ValueError:
                pass
    return rows


before, after = load(sys.argv[1]), load(sys.argv[2])
after_map = {}
for label, sync, total in after:
    after_map.setdefault(label, []).append((sync, total))
seen = {}
print(f"{'step':34s} {'before':>8s} {'after':>8s}   (total main-thread ms)")
sum_b = sum_a = 0.0
for label, sync, total in before:
    index = seen.get(label, 0)
    seen[label] = index + 1
    values = after_map.get(label, [])
    if index < len(values):
        a = values[index][1]
        sum_b += total
        sum_a += a
        print(f"{label:34s} {total:8.1f} {a:8.1f}")
    else:
        print(f"{label:34s} {total:8.1f} {'-':>8s}")
print(f"{'TOTAL (matched steps)':34s} {sum_b:8.1f} {sum_a:8.1f}")
