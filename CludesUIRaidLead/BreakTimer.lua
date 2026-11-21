if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  BreakTimer.lua -- Raid Lead: a shared break countdown.
--
--  The leader or an assistant starts a break (/raidlead break 5, or the
--  buttons under Raid Lead > Setup). Every CludesUI user in the group gets
--  the same bar counting down, a chat line at one minute left, and a sound
--  when it ends. /raidlead break 0 ends it for everyone. Players without
--  CludesUI see nothing from it, so say the break in chat as well.
-------------------------------------------------------------------------------
local _, mod = ...

local W, H = 260, 22
local MAX_MINUTES = 60

function mod.BreakSettings()
    local profile = mod.RaidLeadDB()
    profile.breakTimer = profile.breakTimer or {}
    local cfg = profile.breakTimer
    if cfg.enabled == nil then cfg.enabled = true end
    if cfg.sound == nil then cfg.sound = true end
    return cfg
end

local function Say(textValue) CUI.Print("|cff4cc9f0Raid Lead:|r " .. textValue) end

local bar, labelText, ticker
local current -- { ends, total, from, warned }

local function Build()
    if bar then return end
    bar = CreateFrame("StatusBar", "CludesUIRaidLeadBreak", UIParent)
    bar:SetSize(W, H)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local ar, ag, ab = CUI.Kit.Accent()
    bar:GetStatusBarTexture():SetVertexColor(ar, ag, ab, 0.9)
    CUI.Kit.Panel(bar, 0.85)
    labelText = bar:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(labelText, 13, nil)
    labelText:SetPoint("CENTER")
    bar:Hide()
    mod.ApplyBreakPosition()
end

function mod.ApplyBreakPosition()
    if not bar or InCombatLockdown() then return end
    local p = mod.BreakSettings().pos
    bar:ClearAllPoints()
    if p then
        bar:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -130)
    end
end

local function Stop()
    current = nil
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if bar then bar:Hide() end
end

local function Update()
    if not current then return end
    local leftX = current.ends - GetTime()
    if leftX <= 0 then
        Stop()
        Say("the break is over.")
        if mod.BreakSettings().sound then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
        return
    end
    if leftX <= 60 and not current.warned then
        current.warned = true
        if current.total > 90 then Say("one minute of break left.") end
    end
    bar:SetValue(leftX)
    labelText:SetText(
        ("Break  %s%s"):format(
            mod.FormatDuration(leftX),
            current.from and ("  |cff9aa6b2" .. current.from .. "|r") or ""
        )
    )
end

--- Shows a break of `seconds` (0 ends it). `from` is who started it.
function mod.ReceiveBreak(seconds, from)
    if not mod.BreakSettings().enabled then return end
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds <= 0 then
        if current then
            Stop()
            Say("the break was ended" .. (from and (" by " .. from) or "") .. ".")
        end
        return
    end
    seconds = math.min(seconds, MAX_MINUTES * 60)
    Build()
    current = { ends = GetTime() + seconds, total = seconds, from = from }
    bar:SetMinMaxValues(0, seconds)
    bar:Show()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(0.5, Update)
    Update()
end

--- Starts (minutes > 0) or ends (0) a break for the group.
function mod.StartBreak(minutes)
    minutes = tonumber(minutes)
    if not minutes or minutes < 0 or minutes > MAX_MINUTES then
        return Say("give the break in minutes, 1 to " .. MAX_MINUTES .. ", or 0 to end it.")
    end
    if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return Say("only the leader or an assistant can start a break.")
    end
    local seconds = math.floor(minutes * 60 + 0.5)
    -- In a group the message comes back to us too, which starts our own bar.
    if not (mod.SendBreak and mod.SendBreak(seconds)) then mod.ReceiveBreak(seconds, nil) end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
local registered
eventFrame:SetScript("OnEvent", function()
    if registered or InCombatLockdown() or not CUI.RegisterUnlockElements then return end
    Build()
    registered = true
    CUI:RegisterUnlockElements({
        CUI.MakeUnlockElement({
            key = "RLEAD_Break",
            label = "Break Timer",
            group = "Raid Lead",
            order = 663,
            noAnchorTarget = true,
            noResize = true,
            isHidden = function() return not mod.BreakSettings().enabled end,
            getFrame = function() return bar end,
            getSize = function() return W, H end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                mod.BreakSettings().pos = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
            end,
            loadPos = function() return mod.BreakSettings().pos end,
            clearPos = function() mod.BreakSettings().pos = nil end,
            applyPos = mod.ApplyBreakPosition,
        }),
    }, "CludesUIRaidLead")
end)
