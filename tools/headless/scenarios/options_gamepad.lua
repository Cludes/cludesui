-- Global Settings > Gamepad as built (on load, all pages are built once), then
-- with saved values set (a bar hidden, both cast bar toggles on) and the
-- page's rows re-read.
local CUI = rawget(_G, "CludesUI")
CUI:SelectModule(CUI.GLOBAL_KEY or "_CUIGlobal")
CUI:SelectPage("Gamepad")
SNAP("gamepad", CUI._scrollFrame)

local ab = CUI.ModuleNS("CludesUIActionBars")
local bars = ab and ab.EAB and ab.EAB.db and ab.EAB.db.profile.bars
if bars then
    for _, key in ipairs(ab.BAR_DROPDOWN_ORDER) do
        if bars[key] and not ab.VISIBILITY_ONLY[key] then bars[key].gamepadHideBar = true break end
    end
end
local uf = CUI.ModuleNS("CludesUIUnitFrames")
if uf and uf.db then uf.db.profile.player.castbarGamepadHide = true end
local rb = rawget(_G, "_CURB_AceDB")
if rb then rb.profile.castBar.gamepadHide = true end

CUI:RefreshPage()
SNAP("gamepad set", CUI._scrollFrame)
