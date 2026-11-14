-- One options page as built: Action Bars' first page, the whole panel.
local CUI = rawget(_G, "CludesUI")
CUI:SelectModule("CludesUIActionBars")
SNAP("panel", CUI._mainFrame)
