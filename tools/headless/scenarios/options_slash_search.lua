-- "/cui <words>" (CludesUI.lua): opens the window with the words in the
-- settings search; plain "/cui" still toggles.
local CUI = rawget(_G, "CludesUI")
SlashCmdList.CUIOPTIONS("  nameplate colors ")
HARNESS_ADVANCE(0.5)
local box = CUI._sidebarSearchBox
OUT:write(("== /cui nameplate colors: shown %s, search %q\n"):format(
    tostring(CUI._mainFrame and CUI._mainFrame:IsShown() or (box and box:IsVisible())), tostring(box and box:GetText())))
