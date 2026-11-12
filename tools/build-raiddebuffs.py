"""Builds CludesUIForeverEssentials_RaidDebuffsData.lua: every Forever spell ID
carrying each raid debuff's name (all ranks, NPC and item versions), from
wago.tools SpellName for build 1.60.1.70888. Usage: python -I build_raiddebuffs.py <SpellName.csv> <out>"""
import csv, sys
src, out = sys.argv[1], sys.argv[2]
DEBUFFS = [
    ("sunder", "Sunder Armor", ["Sunder Armor"], True),
    ("faerie", "Faerie Fire", ["Faerie Fire", "Faerie Fire (Feral)"], True),
    ("expose", "Expose Armor", ["Expose Armor"], False),
    ("reck", "Curse of Recklessness", ["Curse of Recklessness"], True),
    ("elements", "Curse of the Elements", ["Curse of the Elements"], True),
    ("weakness", "Curse of Weakness", ["Curse of Weakness"], False),
    ("demo", "Demoralizing Shout / Roar", ["Demoralizing Shout", "Demoralizing Roar"], True),
    ("thunder", "Thunder Clap", ["Thunder Clap"], True),
    ("mark", "Hunter's Mark", ["Hunter's Mark"], False),
    ("weaving", "Shadow Weaving", ["Shadow Weaving"], False),
    ("chill", "Winter's Chill", ["Winter's Chill"], False),
    ("scorch", "Fire Vulnerability", ["Fire Vulnerability"], False),
    ("jwisdom", "Judgement of Wisdom", ["Judgement of Wisdom"], False),
    ("jlight", "Judgement of Light", ["Judgement of Light"], False),
]
by = {}
for row in csv.reader(open(src, encoding="utf-8")):
    if len(row) >= 2 and row[0].isdigit():
        by.setdefault(row[1], []).append(int(row[0]))
lines = [
    "if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)",
    "-------------------------------------------------------------------------------",
    "--  CludesUIForeverEssentials_RaidDebuffsData.lua -- GENERATED, do not edit.",
    "--  Every WoW Forever spell ID carrying each raid debuff's name (all ranks and",
    "--  NPC/item versions), from the game's SpellName table (wago.tools, build",
    "--  1.60.1.70888). The aura container matches enemy debuffs by spell ID only.",
    "-------------------------------------------------------------------------------",
    "local _, module = ...",
    "module.RAID_DEBUFFS = {",
]
for key, label, names, default in DEBUFFS:
    ids = sorted({i for n in names for i in by.get(n, [])})
    assert ids, label
    lines.append('    { key = "%s", label = "%s", default = %s, ids = { %s } },' % (key, label.replace('"', '\\"'), "true" if default else "false", ", ".join(map(str, ids))))
    print(label, len(ids))
lines.append("}")
open(out, "w", encoding="utf-8", newline="\r\n").write("\n".join(lines) + "\n")
