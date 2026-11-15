-- Resource Bars options: every page (bars, cast bar, GCD bar, swing timer on
-- WoW Forever, totem bar) as built, then the bars page again after a few
-- settings change (health hidden, power text and border, class resource
-- thresholds) so the preview header and the gated rows rebuild.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIResourceBars
CUI:SelectModule("CludesUIResourceBars")
for _, page in ipairs({ "Class, Power and Health Bars", "Cast Bar", "GCD Bar", "Swing Timer", "Totem Bar" }) do
    CUI:SelectPage(page)
    SNAP("rb " .. page, CUI._scrollFrame)
    SNAP("rb header " .. page, CUI._contentHeader or CUI._headerFrame)
end
local db = rawget(_G, "_CURB_AceDB")
local p = db and db.profile
if p then
    if p.health then p.health.enabled = false end
    if p.primary then p.primary.borderSize = 2; p.primary.textFormat = "both" end
    if p.secondary then p.secondary.thresholdEnabled = true end
end
CUI:SelectPage("Class, Power and Health Bars")
CUI:InvalidatePageCache()
CUI:RefreshPage(true)
SNAP("rb bars set", CUI._scrollFrame)
SNAP("rb header set", CUI._contentHeader or CUI._headerFrame)
