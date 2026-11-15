-- Resource Bars > Cast Bar page with the preview styled every way the
-- updater handles: icon on the right, divider, gradient, fill opacity,
-- textured background, spark, total duration, centred spell text, border,
-- class colour; then the icon off.
local CUI = rawget(_G, "CludesUI")
local db = rawget(_G, "_CURB_AceDB")
local cb = db and db.profile and db.profile.castBar
if cb then
    cb.enabled = true; cb.showIcon = true; cb.iconOnRight = true; cb.showIconDivider = true
    cb.gradientEnabled = true; cb.gradientR, cb.gradientG, cb.gradientB, cb.gradientA = 0.2, 0.4, 1, 1
    cb.fillOpacity = 60; cb.textureBg = true; cb.showSpark = true; cb.showTimer = true
    cb.showTotalDuration = true; cb.showSpellText = true; cb.spellTextSide = "center"
    cb.borderSize = 2; cb.borderR = 0.6; cb.classColored = true
end
CUI:SelectModule("CludesUIResourceBars")
CUI:SelectPage("Cast Bar")
SNAP("cast styled header", CUI._contentHeader or CUI._headerFrame)
if cb then
    cb.showIcon = false; cb.gradientEnabled = false; cb.fillOpacity = 100; cb.timerSide = "left"; cb.spellTextSide = "right"
end
CUI:InvalidatePageCache()
CUI:SelectPage("GCD Bar")
CUI:SelectPage("Cast Bar")
SNAP("cast plain header", CUI._contentHeader or CUI._headerFrame)
