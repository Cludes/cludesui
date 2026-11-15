-- Resource Bars > GCD Bar and Totem Bar headers, each with its bar on and
-- off (the preview hint shows only while on), and the Cast Bar header off.
local CUI = rawget(_G, "CludesUI")
local db = rawget(_G, "_CURB_AceDB")
local p = db and db.profile
CUI:SelectModule("CludesUIResourceBars")
for _, on in ipairs({ true, false }) do
    if p and p.gcdBar then p.gcdBar.enabled = on end
    if p and p.totemBar then p.totemBar.enabled = on end
    if p and p.castBar then p.castBar.enabled = on end
    CUI:InvalidatePageCache()
    CUI:SelectPage("GCD Bar")
    SNAP("gcd header " .. tostring(on), CUI._contentHeader or CUI._headerFrame)
    CUI:SelectPage("Totem Bar")
    SNAP("totem header " .. tostring(on), CUI._contentHeader or CUI._headerFrame)
    CUI:SelectPage("Cast Bar")
    SNAP("cast header " .. tostring(on), CUI._contentHeader or CUI._headerFrame)
end
-- Swing Timer (WoW Forever only), then the cached GCD and Cast pages again.
if rawget(_G, "C_SwingTimer") then
    CUI:SelectPage("Swing Timer")
    SNAP("swing page", CUI._contentHeader or CUI._headerFrame)
end
CUI:SelectPage("GCD Bar")
SNAP("gcd again", CUI._contentHeader or CUI._headerFrame)
CUI:SelectPage("Cast Bar")
SNAP("cast again", CUI._contentHeader or CUI._headerFrame)
