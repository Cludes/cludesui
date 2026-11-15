-- Resource Bars threshold popups: the band editor (bar values, count based,
-- percent-locked stagger) with bands added, and the buff / spender colour
-- list editors, each opened on the power bar's first threshold entry.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIResourceBars
CUI:SelectModule("CludesUIResourceBars")
CUI:SelectPage("Class, Power and Health Bars")
local env = mod._CURB_OptEnv
local db = rawget(_G, "_CURB_AceDB")
local p = db and db.profile
local anchor = CUI._scrollFrame
local bar = p.primary
bar.thresholdSpecs = bar.thresholdSpecs or {}
bar.thresholdSpecs[1] = bar.thresholdSpecs[1] or { thresholdPct = 40, thresholdR = 0.9 }
local function Bar() return bar end
local overlay = CUI.OverlayParent()
if env and env.ShowBandEditor then
    env.ShowBandEditor({ getBarData = Bar, refreshFn = function() end, entryIdx = 1, anchor = anchor })
    SNAP("band editor", overlay)
    bar.thresholdSpecs[1].bands[2] = { to = 70, r = 0.2, g = 0.9, b = 0.2, a = 1 }
    env.ShowBandEditor({ getBarData = Bar, refreshFn = function() end, entryIdx = 1, anchor = anchor, countBased = true })
    SNAP("band editor count", overlay)
    env.ShowBandEditor({ getBarData = Bar, refreshFn = function() end, entryIdx = 1, anchor = anchor, lockPercent = true, percentMax = 500 })
    SNAP("band editor stagger", overlay)
end
for _, name in ipairs({ "ShowBuffEditor", "ShowSpenderEditor" }) do
    if env and env[name] then
        bar.thresholdSpecs[1].buffColors = { { spellID = 1, r = 1, g = 0, b = 0, a = 1 } }
        bar.thresholdSpecs[1].spenderColors = { { spellID = 2, r = 0, g = 1, b = 0, a = 1 } }
        env[name]({ getBarData = Bar, refreshFn = function() end, entryIdx = 1, anchor = anchor })
        SNAP(name, overlay)
    end
end
