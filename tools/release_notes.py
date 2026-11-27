"""Writes a release's notes (run by release.yml): notes.md for GitHub and
cf_notes.md for CurseForge (tools/curseforge_upload.py uploads it as the
file's changelog).

Env: TAG (vX.Y.Z), GITHUB_REPOSITORY (owner/repo), CF_SINCE (the commit
CurseForge last got, from the "curseforge" tag: CurseForge gets only every few
releases, so its notes cover every release since then).

The lines are the "Player: ..." body lines of the addon-changing commits in
the range, oldest first; a line starting with "Fixed" or "Fix" goes under
Fixed, every other under New and improved. GitHub's copy (since the previous
tag) adds the zip install steps; CurseForge's leaves them out (its app
installs the addon).
"""
import os
import re
import subprocess

TAG = os.environ["TAG"]
REPO = os.environ.get("GITHUB_REPOSITORY", "Cludes/cludesui")
PATHS = ["--", ".", ":!tools", ":!.github", ":!*.md", ":!.stylua.toml", ":!.gitignore"]


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True).stdout.strip()


def notes(since, since_name):
    """The heading, grouped Player lines and compare link for since..TAG."""
    rng = f"{since}..{TAG}" if since else TAG
    day = git("log", "-1", "--format=%cd", "--date=format:%d %B %Y", TAG).lstrip("0")
    has_changes = bool(git("log", "--no-merges", "--format=%h", rng, *PATHS))
    bodies = git("log", "--no-merges", "--reverse", "--format=%B", rng, *PATHS)
    lines = [m.group(1).strip() for m in re.finditer(r"^Player:[ \t]*(.+)$", bodies, re.M)]
    fixed = [l for l in lines if re.match(r"(?i)fix(ed)?\b", l)]
    new = [l for l in lines if l not in fixed]

    body = [f"## CludesUI {TAG}", "", f"*Released {day}*", ""]
    if new:
        body += ["### New and improved", ""] + [f"- {l}" for l in new] + [""]
    if fixed:
        body += ["### Fixed", ""] + [f"- {l}" for l in fixed] + [""]
    if not lines:
        body += ["- " + ("Fixes and polish." if has_changes else f"No addon changes since {since_name}."), ""]
    link = []
    if since:
        ref = since_name if since_name.startswith("v") else since
        link = [f"[Every change since {since_name}](https://github.com/{REPO}/compare/{ref}...{TAG})"]
    return body, link


def main():
    prev = git("describe", "--tags", "--abbrev=0", "--match", "v*", TAG + "^")
    body, link = notes(prev, prev)
    install = [
        "### Install",
        "",
        "Unzip, then copy every `CludesUI...` folder into your game's `Interface\\AddOns` folder "
        "(Retail: `World of Warcraft\\_retail_\\Interface\\AddOns`) and restart the game.",
        "",
    ]
    with open("notes.md", "w", encoding="utf-8") as f:
        f.write("\n".join(body + install + link) + "\n")

    cf_since = os.environ.get("CF_SINCE") or prev
    cf_name = (git("describe", "--tags", "--exact-match", "--match", "v*", cf_since) or cf_since[:7]) if cf_since else ""
    cf_body, cf_link = notes(cf_since, cf_name)
    with open("cf_notes.md", "w", encoding="utf-8") as f:
        f.write("\n".join(cf_body + cf_link) + "\n")
    print(open("cf_notes.md", encoding="utf-8").read())


if __name__ == "__main__":
    main()
