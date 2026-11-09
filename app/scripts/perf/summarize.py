"""summarize.py <label> <bench-output.txt> : one summary line."""
import sys

label, path = sys.argv[1], sys.argv[2]
typing = typing_rows = 0.0
typing_store = typing_layout = typing_sync = 0.0
mount = other = 0.0
worst = 0.0
for line in open(path):
    parts = line.rstrip("\n").split("\t")
    if len(parts) < 4 or parts[0] != "BENCH":
        continue
    try:
        sync = float(parts[2])
        total = float(parts[3])
    except ValueError:
        continue
    extra = {}
    for part in parts[4:]:
        if "=" in part:
            key, value = part.split("=", 1)
            extra[key] = float(value)
    name = parts[1]
    if name == "mount":
        mount = total
    elif name.startswith("type") or name.startswith("delete"):
        typing += total
        typing_sync += sync
        typing_rows += extra.get("rows", 0)
        typing_store += extra.get("store", 0)
        typing_layout += extra.get("layout", 0)
        worst = max(worst, total)
    else:
        other += total
display = typing_sync - typing_store - typing_layout
print(f"{label:30s} mount {mount:6.1f} | typing 18 keys: total {typing:6.1f} = store {typing_store:5.1f} + layout {typing_layout:6.1f} + display {display:6.1f} + later {typing - typing_sync:5.1f}  (worst key {worst:5.1f}, {int(typing_rows)} rows) | other {other:6.1f}")
