-- Info Bar > M+ Summary block (retail): no runs (shown, then hidden when
-- empty), runs (timed and depleted), a new run arriving, hover and tooltip,
-- clicks (open, clear), and a vertical bar. Counts draws.
local H = dofile("tools/headless/scenarios/_common.lua")
H.OUT = OUT
local runs = {}
local CUI = rawget(_G, "CludesUI")
CLEARED, OPENED = 0, 0
CUI._MythicRuns = { Get = function() return runs end, Clear = function() CLEARED = CLEARED + 1 end }
SlashCmdList.CUIMPLUS = function() OPENED = OPENED + 1 end
C_ChallengeMode.GetKeystoneLevelRarityColor = function(l) return { r = l > 10 and 1 or 0, g = 0.5, b = 0.2 } end
local b = H.Block("mplussummary")
H.Show("mplus none")
H.Hover("mplus none hover")
b.settings.hideWhenEmpty = true
H.Show("mplus none hidden")
runs[1] = { level = 12, mapName = "Ara-Kara", timeMS = 1745000, onTime = true }
runs[2] = { level = 9, mapName = "The Dawnbreaker", timeMS = 2400000, onTime = false }
CUI._MythicRuns.OnChanged()
SNAP("mplus runs arrive", H.Bar())
H.Hover("mplus hover")
H.Count("hover and leave", function()
    local h = H.Buttons()[1]
    h["\0scripts"].OnEnter(h)
    h["\0scripts"].OnLeave(h)
end)
local h = H.Buttons()[1]
h["\0scripts"].OnClick(h, "LeftButton")
OUT:write("== opened: ", OPENED, "\n")
table.insert(runs, 1, { level = 15, mapName = "Priory of the Sacred Flame", timeMS = 1900000, onTime = true })
CUI._MythicRuns.OnChanged()
SNAP("mplus newest", H.Bar())
H.Vertical("mplus vertical")
