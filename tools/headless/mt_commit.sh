#!/bin/sh
# mt_commit.sh "<message>" files...: harness on both clients, then commit (no push).
M=$1
shift
LJ=/c/Users/benne/AppData/Local/Programs/LuaJIT/bin/luajit
for f in retail forever; do
    $LJ tools/headless/harness.lua $f 2>&1 | grep "addons loaded" | grep -q " 0 distinct errors" || { echo "HARNESS FAIL $f"; exit 1; }
done
git add "$@" || exit 1
printf '%s\n' "$M" | git commit -q -F - || exit 1
git log --oneline -1
