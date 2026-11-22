-- What's New (the patch notes page, CUI_WhatsNew_Options.lua with its content in
-- CUI__General_Options.lua): opened from the sidebar entry and snapshotted with
-- the newest patch's card open (the default), so every hero card, feature and
-- fix line of that patch is built; the patch count and versions are listed.
local CUI = rawget(_G, "CludesUI")
local patches = CUI and CUI._WHATSNEW_PATCHES
OUT:write("== patches: " .. tostring(patches and #patches) .. "\n")
for _, patch in ipairs(patches or {}) do
    OUT:write(
        "   "
            .. tostring(patch.version)
            .. " heroes "
            .. #(patch.heroes or {})
            .. " features "
            .. #(patch.features or {})
            .. " fixes "
            .. #(patch.fixes or {})
            .. "\n"
    )
end
local ok, err = pcall(function()
    CUI:SelectModule("_CUIPatchNotes")
    CUI:SelectPage("Patch Notes")
end)
OUT:write("== opened " .. (ok and "ok" or tostring(err)) .. "\n")
SNAP("whatsnew", CUI._mainFrame)
