-- The options window keeps its place across reloads (CludesUI_Panel.lua):
-- the open module and each module's page are saved in CludesUIDB.
local CUI = rawget(_G, "CludesUI")
CUI:Show()
HARNESS_ADVANCE(0.2)
CUI:SelectModule("CludesUINameplates")
CUI:SelectPage("Colors")
CUI:SelectModule("CludesUIActionBars")
OUT:write(("== saved module %s, nameplates page %s, action bars page %s\n"):format(
    tostring(CludesUIDB.optionsLastModule),
    tostring(CludesUIDB.optionsLastPages and CludesUIDB.optionsLastPages.CludesUINameplates),
    tostring(CludesUIDB.optionsLastPages and CludesUIDB.optionsLastPages.CludesUIActionBars)))
