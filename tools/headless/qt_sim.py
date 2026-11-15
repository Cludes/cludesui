import sys, os
a, b = sys.argv[1], sys.argv[2]
A = set()
for f in os.listdir(a):
    if f.endswith(".lua"):
        A |= set(l.strip() for l in open(os.path.join(a, f), encoding="utf-8", errors="replace") if len(l.strip()) > 3)
for f in sorted(os.listdir(b)):
    if not f.endswith(".lua"):
        continue
    B = [l.strip() for l in open(os.path.join(b, f), encoding="utf-8", errors="replace") if len(l.strip()) > 3]
    same = sum(1 for l in B if l in A)
    print(f"{f:45s} {len(B):5d} {100 * same / max(1, len(B)):5.1f}%")
