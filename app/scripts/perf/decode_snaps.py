"""decode_snaps.py <bench-output.txt> <output-prefix>"""
import base64
import sys
from collections import Counter

out, prefix = sys.argv[1], sys.argv[2]
sizes = Counter()
for line in open(out):
    parts = line.rstrip("\n").split("\t")
    if parts[0] == "SNAP" and len(parts) == 3:
        name = "".join(c if c.isalnum() or c in "-_" else "_" for c in parts[1])
        path = f"{prefix}-{name}.png"
        open(path, "wb").write(base64.b64decode(parts[2]))
        print("wrote", path)
    elif parts[0] == "ROWSIZE" and len(parts) == 4:
        sizes[(parts[1], parts[2], parts[3])] += 1
for (kind, width, height), count in sorted(sizes.items()):
    print(f"row size  {kind:9s} {width} x {height}   ({count} reports)")
