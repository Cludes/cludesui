#!/bin/sh
# qt_check.sh <file> <scenario> <tag>: stylua, globals, compare on both clients.
F=$1; S=$2; T=$3
"/c/Users/benne/AppData/Local/Microsoft/WinGet/Packages/JohnnyMorganz.StyLua_Microsoft.Winget.Source_8wekyb3d8bbwe/stylua" "$F" || exit 1
/c/Users/benne/AppData/Local/Programs/LuaJIT/bin/luajit -bl "$F" > "$TEMP/bl_$T.txt" || exit 1
grep -o 'GGET.*"[A-Za-z_]*"' "$TEMP/bl_$T.txt" | grep -o '"[A-Za-z_]*"' | sort -u | tr '\n' ' '; echo
for fl in retail forever; do
    COMPARE_TAG="${T}_$fl" python -I tools/headless/compare.py HEAD "$S" $fl 2>&1 | grep -v "^---\|^+++" | cut -c1-230
done
