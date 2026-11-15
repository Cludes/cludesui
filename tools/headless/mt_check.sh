#!/bin/sh
# mt_check.sh <file> <scenario> <tag>: stylua, globals read, compare on retail.
F=$1
S=$2
T=$3
"/c/Users/benne/AppData/Local/Microsoft/WinGet/Packages/JohnnyMorganz.StyLua_Microsoft.Winget.Source_8wekyb3d8bbwe/stylua" "$F" || exit 1
/c/Users/benne/AppData/Local/Programs/LuaJIT/bin/luajit -bl "$F" > "$TEMP/bl_$T.txt" || exit 1
grep -o 'GGET.*"[A-Za-z_]*"' "$TEMP/bl_$T.txt" | grep -o '"[A-Za-z_]*"' | sort -u | tr '\n' ' '
echo
COMPARE_TAG=$T python -I tools/headless/compare.py HEAD "$S" retail 2>&1 | grep -v "^---" | grep -v "^+++" | cut -c1-230
