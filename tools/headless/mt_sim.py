"""Per-file share of lines identical to the original copy (trimmed, >3 chars).

    python -I tools/headless/mt_sim.py <eui-addon-dir> <our-addon-dir>
"""
import os
import sys

eui, ours = sys.argv[1], sys.argv[2]


def lines(path):
    out = []
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if len(line) > 3:
            out.append(line)
    return out


theirs = set()
for name in os.listdir(eui):
    if name.endswith(".lua"):
        theirs.update(lines(os.path.join(eui, name)))
for name in sorted(os.listdir(ours)):
    if name.endswith(".lua"):
        mine = lines(os.path.join(ours, name))
        same = sum(1 for line in mine if line in theirs)
        print("%-42s %6d lines %5.1f%% identical" % (name, len(mine), 100.0 * same / max(1, len(mine))))
