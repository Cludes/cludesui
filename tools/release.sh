#!/bin/sh
# tools/release.sh [major|minor|patch|X.Y.Z]: puts the new version in every
# addon's .toc and in CludesUI.VERSION, commits it as "Release vX.Y.Z", tags
# it and pushes both. The tag starts the Release workflow, which builds
# CludesUI-vX.Y.Z.zip and publishes it with notes listing every change since
# the last release. Every ordinary push to master already makes the next patch
# release, so this is for a minor or major version (or an exact one); it
# numbers from the newest tag, which is ahead of the .toc files.
# Default: patch.
set -e
cd "$(dirname "$0")/.."
# --force: the release workflow moves its "curseforge" marker tag.
git fetch -q --tags --force
cur=$(git tag --list 'v*' --sort=-v:refname | head -1 | sed 's/^v//')
want=${1:-patch}
IFS=. read -r MA MI PA <<EOF
$cur
EOF
case "$want" in
    major) new="$((MA + 1)).0.0" ;;
    minor) new="$MA.$((MI + 1)).0" ;;
    patch) new="$MA.$MI.$((PA + 1))" ;;
    *.*.*) new="$want" ;;
    *) echo "usage: tools/release.sh [major|minor|patch|X.Y.Z]" >&2; exit 1 ;;
esac
if git rev-parse -q --verify "refs/tags/v$new" >/dev/null; then
    echo "v$new is already tagged" >&2
    exit 1
fi
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "commit your changes first" >&2
    exit 1
fi
# Every addon's ## Version line, line endings kept.
for toc in CludesUI*/*.toc; do
    if grep -q '^## Version:' "$toc"; then
        sed -b -i "s/^## Version: [0-9][0-9.]*/## Version: $new/" "$toc"
        git add "$toc"
    fi
done
# The version the suite reports in game (version check, patch notes).
sed -b -i "s/^CUI\.VERSION = \"[0-9.]*\"/CUI.VERSION = \"$new\"/" CludesUI/CludesUI.lua
git add CludesUI/CludesUI.lua
if [ "$cur" != "$new" ]; then
    git commit -q -m "Release v$new"
fi
git tag -a "v$new" -m "CludesUI v$new"
git push -q origin HEAD
git push -q origin "v$new"
echo "v$cur -> v$new pushed; the Release workflow publishes the zip"
