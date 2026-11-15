-- Resource Bars options, bars page built with the power and health previews
-- styled every way PreviewBar.Style handles: text formats, gradient, fill
-- opacity, custom colours, hash lines (percent and value), a threshold, a
-- border, the bar texture on the background.
local CUI = rawget(_G, "CludesUI")
local db = rawget(_G, "_CURB_AceDB")
local p = db and db.profile
if p then
    local h, pw = p.health, p.primary
    h.enabled = true
    h.textFormat = "curmaxhp"; h.gradientEnabled = true; h.gradientR = 0.2
    h.fillOpacity = 50; h.hashEnabled = true; h.hashValues = "25, 50,75"; h.hashMode = "percent"
    h.borderSize = 2; h.borderR = 0.5
    pw.enabled = true
    pw.textFormat = "both"; pw.showPercent = false; pw.customColored = true
    pw.fillR, pw.fillG, pw.fillB = 0.1, 0.2, 0.9
    pw.hashEnabled = true; pw.hashValues = "30,60"; pw.hashMode = "value"
    pw.textCustomColored = false; pw.textAnchor = "LEFT"; pw.textXOffset = 4
    p.general.barTextureBg = true
end
CUI:SelectModule("CludesUIResourceBars")
CUI:SelectPage("Class, Power and Health Bars")
SNAP("rb styled", CUI._scrollFrame)
SNAP("rb styled header", CUI._contentHeader or CUI._headerFrame)
for _, f in ipairs({ "both", "curhpshort", "perhpnosign", "perhpnum", "perhp" }) do
    if p then p.health.textFormat = f end
    CUI:InvalidatePageCache()
    CUI:SelectPage("Cast Bar")
    CUI:SelectPage("Class, Power and Health Bars")
    SNAP("rb health " .. f, CUI._contentHeader or CUI._headerFrame)
end
