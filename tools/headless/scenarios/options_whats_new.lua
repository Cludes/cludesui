-- The Patch Notes page (CUI._WHATSNEW_PATCHES): the newest entry and its
-- version match CUI.NOTES_VERSION (what lights the sidebar dot).
local CUI = rawget(_G, "CludesUI")
CUI:Show()
HARNESS_ADVANCE(0.2)
CUI:SelectModule("_CUIPatchNotes")
HARNESS_ADVANCE(0.2)
local newest = CUI._WHATSNEW_PATCHES and CUI._WHATSNEW_PATCHES[1]
OUT:write(("== newest notes %s, NOTES_VERSION %s, heroes %d, features %d, fixes %d\n"):format(
    tostring(newest and newest.version), tostring(CUI.NOTES_VERSION),
    newest and #(newest.heroes or {}) or 0, newest and #(newest.features or {}) or 0, newest and #(newest.fixes or {}) or 0))
