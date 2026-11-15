#!/bin/sh
# compare_all.sh <old-commit> [jobs] [scenario-glob]: every scenario on each
# client it applies to, in parallel; prints one line per run, non-zero first.
OLD=${1:-HEAD}; JOBS=${2:-6}; GLOB=${3:-tools/headless/scenarios/infobar_*.lua}
for s in $GLOB; do
    for f in retail forever; do
        case "$s" in
            *supplies*) [ $f = retail ] && continue ;;
            *crests*|*mplus*|*vault*|*spec.lua) [ $f = forever ] && continue ;;
        esac
        echo "$s $f"
    done
done | xargs -P "$JOBS" -L 1 sh -c '
    tag=$(basename "$0" .lua)_$1
    r=$(COMPARE_TAG=$tag python -I tools/headless/compare.py '"$OLD"' "$0" "$1" 2>&1 | grep "differences")
    echo "$(basename "$0") $1: ${r:-NO RESULT}"
' | sort -t: -k2 | sort -s -k1,1 | awk "/differences 0\$/ {ok=ok \$0 \"\n\"; next} {print} END {printf \"%s\", ok}"
