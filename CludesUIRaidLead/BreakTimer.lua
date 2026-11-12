if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  BreakTimer.lua -- Raid Lead: a shared break countdown.
--
--  The leader or an assistant starts a break (/raidlead break 5, or the
--  buttons under Raid Lead > Setup). Every CludesUI user in the group gets
--  the same bar counting down, a chat line at one minute left, and a sound
--  when it ends. /raidlead break 0 ends it for everyone. Players without
--  CludesUI see nothing from it, so say the break in chat as well.
-------------------------------------------------------------------------------
local _, ns = ...

local W, H = 260, 22
local MAX_MINUTES = 60

function ns.BreakSettings()
    local p = ns.RaidLeadDB()
    p.breakTimer = p.breakTimer or {}
    local s = p.breakTimer
    if s.enabled == nil then s.enabled = true end
    if s.sound == nil then s.sound = true end
    return s
end

local function Say(text) CludesUI.Print("|cff4cc9f0Raid Lead:|r " .. text) end

local bar, label, ticker
local current             -- { ends, total, from, warned }

local function Build()
    if bar then return end
    bar = CreateFrame("StatusBar", "CludesUIRaidLeadBreak", UIParent, "BackdropTemplate")
    bar:SetSize(W, H)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:GetStatusBarTexture():SetVertexColor(0.30, 0.79, 0.94, 0.9)
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    bar:SetBackdropColor(0.05, 0.06, 0.08, 0.85)
    bar:SetBackdropBorderColor(0, 0, 0, 1)
    label = bar:CreateFontString(nil, "OVERLAY")
    label:SetFont((CludesUI.GetFontPath and CludesUI.GetFontPath()) or STANDARD_TEXT_FONT, 13, "OUTLINE")
    label:SetPoint("CENTER")
    bar:Hide()
    ns.ApplyBreakPosition()
end

function ns.ApplyBreakPosition()
    if not bar or InCombatLockdown() then return end
    local p = ns.BreakSettings().pos
    bar:ClearAllPoints()
    if p then
        bar:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -130)
    end
end

local function Stop()
    current = nil
    if ticker then ticker:Cancel(); ticker = nil end
    if bar then bar:Hide() end
end

local function Update()
    if not current then return end
    local left = current.ends - GetTime()
    if left <= 0 then
        Stop()
        Say("the break is over.")
        if ns.BreakSettings().sound then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
        return
    end
    if left <= 60 and not current.warned then
        current.warned = true
        if current.total > 90 then Say("one minute of break left.") end
    end
    bar:SetValue(left)
    label:SetText(("Break  %s%s"):format(ns.FormatDuration(left),
        current.from and ("  |cff9aa6b2" .. current.from .. "|r") or ""))
end

--- Shows a break of `seconds` (0 ends it). `from` is who started it.
function ns.ReceiveBreak(seconds, from)
    if not ns.BreakSettings().enabled then return end
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds <= 0 then
        if current then Stop(); Say("the break was ended" .. (from and (" by " .. from) or "") .. ".") end
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
function ns.StartBreak(minutes)
    minutes = tonumber(minutes)
    if not minutes or minutes < 0 or minutes > MAX_MINUTES then
        return Say("give the break in minutes, 1 to " .. MAX_MINUTES .. ", or 0 to end it.")
    end
    if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return Say("only the leader or an assistant can start a break.")
    end
    local seconds = math.floor(minutes * 60 + 0.5)
    -- In a group the message comes back to us too, which starts our own bar.
    if not (ns.SendBreak and ns.SendBreak(seconds)) then ns.ReceiveBreak(seconds, nil) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
local registered
ev:SetScript("OnEvent", function()
    if registered or InCombatLockdown() or not CludesUI.RegisterUnlockElements then return end
    Build()
    registered = true
    CludesUI:RegisterUnlockElements({
        CludesUI.MakeUnlockElement({
            key = "RLEAD_Break", label = "Break Timer", group = "Raid Lead", order = 663,
            noAnchorTarget = true, noResize = true,
            isHidden = function() return not ns.BreakSettings().enabled end,
            getFrame = function() return bar end,
            getSize = function() return W, H end,
            savePos = function(_, point, relPoint, x, y)
                ns.BreakSettings().pos = { point = point, relPoint = relPoint, x = x, y = y }
            end,
            loadPos = function() return ns.BreakSettings().pos end,
            clearPos = function() ns.BreakSettings().pos = nil end,
            applyPos = ns.ApplyBreakPosition,
        }),
    }, "CludesUIRaidLead")
end)
