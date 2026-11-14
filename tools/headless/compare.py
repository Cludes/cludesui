"""Side-by-side check for a rewrite: run one scenario against an older commit
and against the working tree, snapshot what the UI shows, and print every
difference.

    python -I tools/headless/compare.py <old-commit> <scenario.lua> [retail|forever]

The scenario is a harness probe (see harness.lua's HARNESS_PROBE). It gets
the loaded suite, does things (open a dialog, hover a button), and calls
SNAP(label, frame) for each frame tree to record; snapshot.lua does the
recording. Both runs use this checkout's harness, so the fake client is the
same; only the addon code differs.
"""
import difflib, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
LJ = os.environ.get("LUAJIT", "C:/Users/benne/AppData/Local/Programs/LuaJIT/bin/luajit.exe")

PRELUDE = r'''
local SNAP_LIB = dofile(%r)
local OUT = assert(io.open(%r, "w"))
function SNAP(label, frame)
    if not frame then OUT:write("== " .. label .. " (missing)\n") return end
    OUT:write("== " .. label .. "\n")
    for _, line in ipairs(SNAP_LIB.Take(frame, label)) do OUT:write(line, "\n") end
end
SETTLE = SNAP_LIB.Settle
'''

def run(tree, scenario, flavor, out):
    probe = os.path.join(tempfile.gettempdir(), "compare_probe.lua")
    body = open(scenario, encoding="utf-8").read()
    with open(probe, "w", encoding="utf-8") as f:
        f.write(PRELUDE % (os.path.join(HERE, "snapshot.lua").replace("\\", "/"), out.replace("\\", "/")))
        f.write(body)
        f.write("\nOUT:close()\n")
    env = dict(os.environ, HARNESS_PROBE=probe)
    r = subprocess.run([LJ, os.path.join(HERE, "harness.lua"), flavor], cwd=tree, env=env,
                       capture_output=True, text=True, errors="replace")
    tail = [l for l in r.stdout.splitlines() if "pages built" in l or l.startswith("[")]
    return tail

def main():
    old, scenario = sys.argv[1], os.path.abspath(sys.argv[2])
    flavor = sys.argv[3] if len(sys.argv) > 3 else "retail"
    wt = os.path.join(tempfile.gettempdir(), "cui_compare_old")
    subprocess.run(["git", "-C", REPO, "worktree", "remove", "--force", wt], capture_output=True)
    subprocess.run(["git", "-C", REPO, "worktree", "add", "--detach", wt, old], capture_output=True, check=True)
    try:
        a_out = os.path.join(tempfile.gettempdir(), "snap_old.txt")
        b_out = os.path.join(tempfile.gettempdir(), "snap_new.txt")
        print("old:", " | ".join(run(wt, scenario, flavor, a_out)))
        print("new:", " | ".join(run(REPO, scenario, flavor, b_out)))
        a = open(a_out, encoding="utf-8").read().splitlines()
        b = open(b_out, encoding="utf-8").read().splitlines()
        diff = list(difflib.unified_diff(a, b, "old", "new", lineterm="", n=0))
        print("snapshot lines: old %d, new %d, differences %d" % (len(a), len(b), sum(1 for l in diff if l[:1] in "+-" and l[:3] not in ("+++", "---"))))
        for l in diff:
            print(l)
    finally:
        subprocess.run(["git", "-C", REPO, "worktree", "remove", "--force", wt], capture_output=True)

if __name__ == "__main__":
    main()
