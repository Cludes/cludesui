-- Utilities > QoL, its lower sections (keys popup, LFG reminder, /way, auto
-- logging) as built, then with each feature's settings changed (popups off,
-- /way on with arrival, logging on with triggers and notify) and re-read.
local CUI = rawget(_G, "CludesUI")
CUI:SelectModule("CludesUIQoL")
CUI:SelectPage("QoL")
SNAP("qol", CUI._scrollFrame)
CludesUIDB.keystonePopup = { enabled = false, textSize = 13 }
CludesUIDB.teleportPrompt = { enabled = false, scale = 1.2 }
CludesUIDB.waypointCmd = { enabled = true, manualArrival = true }
CludesUIDB.autoLogging = { enabled = true, logArena = false, logBlitz = true, notify = true, delaystop = false }
CUI:InvalidatePageCache()
CUI:RefreshPage(true)
SNAP("qol set", CUI._scrollFrame)
