"""Uploads a release zip to the CludesUI CurseForge project (run by release.yml).

Env: CF_API_KEY (CurseForge API token), TAG (vX.Y.Z). Reads notes.md (the
GitHub release notes) as the changelog and CludesUI-<TAG>.zip as the file.
Game versions come from CludesUI.toc's ## Interface line (120105 -> 12.1.5),
matched by name against CurseForge's list. Upload API:
https://support.curseforge.com/en/support/solutions/articles/9000197321-curseforge-upload-api
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid

API = "https://wow.curseforge.com/api"
PROJECT = "1827658"
TOKEN = os.environ["CF_API_KEY"]
TAG = os.environ["TAG"]
HEADERS = {"X-Api-Token": TOKEN, "User-Agent": "CludesUI-release"}


def call(path, data=None, content_type=None):
    headers = dict(HEADERS)
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(API + path, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as err:
        sys.exit(f"CurseForge {path} failed: HTTP {err.code} {err.read().decode('utf-8', 'replace')}")


def interface_names():
    toc = open("CludesUI/CludesUI.toc", encoding="utf-8").read()
    line = re.search(r"^## Interface:\s*(.+)$", toc, re.M).group(1)
    names = set()
    for num in map(int, re.findall(r"\d+", line)):
        names.add(f"{num // 10000}.{num // 100 % 100}.{num % 100}")
    return names


def main():
    wanted = interface_names()
    versions = call("/game/versions")
    picked = [v for v in versions if v.get("name") in wanted]
    print("Interface versions:", ", ".join(sorted(wanted)))
    print("On CurseForge:", ", ".join(sorted({v["name"] for v in picked})) or "none")
    if not picked:
        newest = sorted(versions, key=lambda v: v.get("id", 0))[-15:]
        sys.exit("No game version matched. Newest on CurseForge: " + ", ".join(v.get("name", "?") for v in newest))

    metadata = {
        "changelog": open("notes.md", encoding="utf-8").read(),
        "changelogType": "markdown",
        "displayName": f"CludesUI {TAG}",
        "gameVersions": sorted({v["id"] for v in picked}),
        "releaseType": "release",
    }
    zip_name = f"CludesUI-{TAG}.zip"
    boundary = uuid.uuid4().hex
    body = b"".join([
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"metadata\"\r\n"
        f"Content-Type: application/json\r\n\r\n".encode(),
        json.dumps(metadata).encode(),
        f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{zip_name}\"\r\n"
        f"Content-Type: application/zip\r\n\r\n".encode(),
        open(zip_name, "rb").read(),
        f"\r\n--{boundary}--\r\n".encode(),
    ])
    result = call(f"/projects/{PROJECT}/upload-file", body, f"multipart/form-data; boundary={boundary}")
    print(f"Uploaded {zip_name} to CurseForge as file {result.get('id')}")


if __name__ == "__main__":
    main()
