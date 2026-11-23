-- XP bar effects (CUI_ActionBars_XPBarFX.lua): the shine and spark on the
-- fill, rested stripes and edge, the ready glow when completed quests cover
-- the level, the quest hand-in pulse and "+XP", the level-up flash, the hover
-- breakdown lines, the toggles turning each off, and the PvP hide.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIActionBars
local FX = mod and mod.XPBarFX
OUT:write("== fx " .. tostring(FX ~= nil) .. "\n")
if not FX then return end

local xp = { 1000, 5000, 600 }
UnitXP = function() return xp[1] end
UnitXPMax = function() return xp[2] end
GetXPExhaustion = function() return xp[3] end
UnitLevel = function() return 20 end
BreakUpLargeNumbers = function(n) return tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end
IsPlayerAtEffectiveMaxLevel = function() return false end
IsLevelAtEffectiveMaxLevel = function() return false end
GetMaxLevelForPlayerExpansion = function() return 60 end
IsXPUserDisabled = function() return false end
local kind = "none"
IsInInstance = function() return kind ~= "none", kind end
local quests = { { 11, true, 2500 }, { 12, false, 900 } }
C_QuestLog = C_QuestLog or {}
C_QuestLog.GetNumQuestLogEntries = function() return #quests end
C_QuestLog.GetQuestIDForLogIndex = function(i) return quests[i] and quests[i][1] end
C_QuestLog.IsComplete = function(q) for _, e in ipairs(quests) do if e[1] == q then return e[2] end end end
GetQuestLogRewardXP = function(q) for _, e in ipairs(quests) do if e[1] == q then return e[3] end end end

local cfg = mod.EAB.db.profile.bars.XPBar
local widget = mod.dataBarFrames.XPBar
OUT:write("== live bar " .. tostring(widget ~= nil) .. " fx " .. tostring(widget and widget._fx ~= nil) .. "\n")
if not (widget and widget._fx) then
    -- The bar is built at enable only when the XP bar is on; build a stand-in.
    widget = mod.CreateXPBarFrame(function() end)
    widget:SetSize(400, 14)
    widget._bar:SetAllPoints(widget)
end
local fx = widget._fx
widget._bar:SetSize(400, 14)

local function State(tag)
    local function s(t) return t:IsShown() and "on" or "off" end
    OUT:write(("== %s: sheen=%s shade=%s spark=%s stripes=%s edge=%s ready=%s star=%s gain=%s text=%s level=%s\n"):format(
        tag, s(fx.sheen), s(fx.shade), s(fx.spark), s(fx.stripes), s(fx.edge), s(fx.ready), s(fx.star),
        s(fx.gain), s(fx.text), s(fx.level)))
end
local function Paint() mod.PaintXPFill(widget, cfg, xp[1], xp[2], xp[3]) end

FX.ScanQuests()
OUT:write(("== quest xp done=%d open=%d\n"):format(FX.QuestXP()))
Paint()
State("1000/5000 rested 600, 2500 done")
OUT:write(("== sheen w=%s spark x=%s\n"):format(tostring(fx.sheen:GetWidth()), tostring(select(4, fx.spark:GetPoint(1)))))

quests[1][3] = 4200
FX.ScanQuests()
Paint()
State("done 4200 covers the level")

cfg.fxShine, cfg.fxStripes, cfg.fxReady = false, false, false
Paint()
State("shine, stripes, ready off")
cfg.fxShine, cfg.fxStripes, cfg.fxReady = nil, nil, nil

FX.Gain(widget, 4200)
xp[1] = 5200 - 5000
Paint()
State("quest handed in")
OUT:write("== gain text " .. tostring(fx.text:GetText()) .. "\n")

FX.LevelUp(widget)
State("level up")

local lines = {}
local tip = {
    AddLine = function(_, t) lines[#lines + 1] = t end,
    AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. " | " .. r end,
}
FX.Breakdown(tip)
OUT:write("== breakdown: " .. table.concat(lines, " ; ") .. "\n")
OUT:write(("== kills lvl20 left 4000 rested 600: %d, no rested: %d\n"):format(FX.Kills(20, 4000, 600), FX.Kills(20, 4000, 0)))

OUT:write("== max before pvp " .. tostring(mod.XPBarAtMaxLevel()) .. "\n")
kind = "pvp"
HARNESS_FIRE_EVENT("PLAYER_ENTERING_WORLD")
OUT:write("== max in bg " .. tostring(mod.XPBarAtMaxLevel()) .. "\n")
cfg.showInPvP = true
OUT:write("== max in bg, show in pvp " .. tostring(mod.XPBarAtMaxLevel()) .. "\n")
cfg.showInPvP = nil
kind = "none"
HARNESS_FIRE_EVENT("PLAYER_ENTERING_WORLD")
OUT:write("== max after leaving " .. tostring(mod.XPBarAtMaxLevel()) .. "\n")

cfg.orientation = "VERTICAL"
Paint()
State("vertical bar")
cfg.orientation = nil
