if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  BossPace.lua -- Raid Lead: Boss Pace.
--
--  A bar with the boss's health beside a marker for where its health should
--  be by now, to kill it in the target time you set for that boss. The bar is
--  green while you are ahead of that pace and red while you are behind.
--
--  How, under 12.1: the game hides the boss's health from addons as a number,
--  so nothing here compares it. The bar is filled with the hidden value (a
--  status bar may show it), and its colour comes from a colour curve the game
--  evaluates on the hidden value: red below the expected percent, green at or
--  above it. The expected percent is plain arithmetic on the clock.
--
--  The pace is a straight line from 100% at the pull to 0% at the target time.
--  Fights with phases or intermissions do not lose health evenly, so treat it
--  as a guide, and set the target to a kill time you have had before.
-------------------------------------------------------------------------------
local _, mod = ...

local GREEN = CreateColor(0.38, 0.82, 0.45, 1)
local RED = CreateColor(0.93, 0.33, 0.25, 1)
local TICK = 0.25

function mod.PaceSettings()
    local profile = mod.RaidLeadDB()
    profile.pace = profile.pace or {}
    local cfg = profile.pace
    if cfg.enabled == nil then
        cfg.enabled = true
    end
    cfg.targets = cfg.targets or {} -- { { boss = "name", seconds = 300 }, ... }
    return cfg
end

--- "m:ss" or "s" to seconds.
function mod.ParseDuration(textValue)
    local m, sec = (textValue or ""):match("^%s*(%d+):(%d%d)%s*$")
    if m then
        return tonumber(m) * 60 + tonumber(sec)
    end
    local only = (textValue or ""):match("^%s*(%d+)%s*$")
    return only and tonumber(only) or nil
end

function mod.FormatDuration(s)
    s = math.max(0, math.floor(s + 0.5))
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function TargetFor(bossName)
    local key = (bossName or ""):lower()
    for _, t in ipairs(mod.PaceSettings().targets) do
        if (t.boss or ""):lower() == key then
            return t.seconds
        end
    end
end

local bar, marker, labelText, curve
local fight -- { start, target, name }

local function Build()
    if bar then
        return
    end
    bar = CreateFrame("StatusBar", "CludesUIRaidLeadPace", UIParent)
    bar:SetSize(260, 22)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, 100)
    CludesUI.Kit.Panel(bar, 0.85)
    marker = bar:CreateTexture(nil, "OVERLAY")
    marker:SetColorTexture(1, 1, 1, 0.95)
    marker:SetSize(2, 26)
    labelText = bar:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(labelText, 13, nil)
    labelText:SetPoint("BOTTOM", bar, "TOP", 0, 3)
    curve = C_CurveUtil.CreateColorCurve()
    bar:Hide()
    mod.ApplyPacePosition()
end

function mod.ApplyPacePosition()
    if not bar or InCombatLockdown() then
        return
    end
    local p = mod.PaceSettings().pos
    bar:ClearAllPoints()
    if p then
        bar:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -90)
    end
end

local function Update()
    if not fight then
        return
    end
    local elapsed = GetTime() - fight.start
    local expected = math.max(0, 100 - elapsed / fight.target * 100)
    -- Red below the expected percent, green from it upward: two points a
    -- hair apart make the jump (the same pattern as the nameplate execute glow).
    local t = math.max(0, math.min(expected / 100, 0.999))
    curve:ClearPoints()
    curve:AddPoint(0, RED)
    curve:AddPoint(t, RED)
    curve:AddPoint(t + 0.0001, GREEN)
    curve:AddPoint(1, GREEN)
    local unitToken = UnitExists("boss1") and "boss1" or nil
    if unitToken then
        bar:SetValue(UnitHealthPercent(unitToken, true, CurveConstants and CurveConstants.ScaleTo100) or 0)
        local colour = UnitHealthPercent(unitToken, true, curve)
        if colour and colour.GetRGB then
            bar:GetStatusBarTexture():SetVertexColor(colour:GetRGB())
        end
    end
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", bar, "LEFT", bar:GetWidth() * expected / 100, 0)
    labelText:SetText(
        ("%s  |cff9aa6b2pace %d%%  %s / %s|r"):format(
            fight.name,
            math.floor(expected + 0.5),
            mod.FormatDuration(elapsed),
            mod.FormatDuration(fight.target)
        )
    )
end

local ticker

local function Stop()
    fight = nil
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if bar then
        bar:Hide()
    end
end

--- Starts the bar for a boss with a target kill time, as at a pull.
function mod.StartPace(name, seconds)
    Build()
    if not (bar and seconds and seconds > 0) then
        return
    end
    fight = { start = GetTime(), target = seconds, name = name }
    bar:Show()
    if ticker then
        ticker:Cancel()
    end
    ticker = C_Timer.NewTicker(TICK, Update)
    Update()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ENCOUNTER_START")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
local registered
eventFrame:SetScript("OnEvent", function(_, evt, _, encounterName)
    if evt == "ENCOUNTER_END" then
        return Stop()
    end
    if evt == "PLAYER_ENTERING_WORLD" then
        if registered or InCombatLockdown() or not CludesUI.RegisterUnlockElements then
            return
        end
        Build()
        registered = true
        CludesUI:RegisterUnlockElements({
            CludesUI.MakeUnlockElement({
                key = "RLEAD_Pace",
                label = "Boss Pace",
                group = "Raid Lead",
                order = 662,
                noAnchorTarget = true,
                noResize = true,
                isHidden = function()
                    return not mod.PaceSettings().enabled
                end,
                getFrame = function()
                    return bar
                end,
                getSize = function()
                    return 260, 22
                end,
                savePos = function(_, anchorPoint, relPoint, posX, posY)
                    mod.PaceSettings().pos = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                end,
                loadPos = function()
                    return mod.PaceSettings().pos
                end,
                clearPos = function()
                    mod.PaceSettings().pos = nil
                end,
                applyPos = mod.ApplyPacePosition,
            }),
        }, "CludesUIRaidLead")
        return
    end
    if not mod.PaceSettings().enabled then
        return
    end
    if type(encounterName) ~= "string" or (issecretvalue and issecretvalue(encounterName)) then
        return
    end
    local target = TargetFor(encounterName)
    if target then
        mod.StartPace(encounterName, target)
    end
end)
