if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_CombatExtras.lua  (WoW Forever only)
--  Three small combat helpers, each with its own switch:
--    Combat Timer     how long the current fight has run, held for a few
--                     seconds after it ends, and the length in chat if wanted.
--    Combat Alert     "+ Combat" / "- Combat" fading in the middle of the
--                     screen as you enter and leave combat, with a sound.
--    Stealth Reminder for a rogue, or a druid in Cat Form: "Not stealthed"
--                     while out of combat and out of stealth. Never in an inn
--                     or a city, and optionally only in a group.
-------------------------------------------------------------------------------
local _, module = ...

local function Font()
    return CludesUI.GetFontPath("essentials")
end

local function Text(hostFrame, size)
    local fontStr = hostFrame:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(fontStr, size, "essentials")
    fontStr:SetPoint("CENTER")
    return fontStr
end

-------------------------------------------------------------------------------
--  Combat Timer
-------------------------------------------------------------------------------
local T = module.Feature(
    "combatTimer",
    { enabled = false, chat = false, hold = 5 },
    { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 }
)
local timerFrame, timerText, started, ticker

local function TimerBuild()
    if timerFrame then
        return timerFrame
    end
    timerFrame = CreateFrame("Frame", "CludesUICombatTimer", UIParent)
    timerFrame:SetSize(80, 22)
    timerText = Text(timerFrame, 16)
    timerFrame:Hide()
    return timerFrame
end

local function Clock(s)
    s = math.max(0, math.floor(s))
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function TimerTick()
    if started then
        timerText:SetText(Clock(GetTime() - started))
    end
end

local timerEv = CreateFrame("Frame")
timerEv:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_REGEN_DISABLED" then
        started = GetTime()
        timerText:SetTextColor(1, 1, 1)
        timerFrame:Show()
        TimerTick()
        if ticker then
            ticker:Cancel()
        end
        ticker = C_Timer.NewTicker(0.25, TimerTick)
    elseif started then
        local length = GetTime() - started
        started = nil
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        timerText:SetText(Clock(length))
        timerText:SetTextColor(CludesUI.Kit.Accent())
        if T.Get("chat") and length >= 3 then
            CludesUI.Print("|cff4cc9f0Combat:|r that fight took " .. Clock(length) .. ".")
        end
        C_Timer.After(T.Get("hold"), function()
            if not started and not CludesUI._unlockActive then
                timerFrame:Hide()
            end
        end)
    end
end)

local function TimerApply()
    if T.Enabled() then
        TimerBuild()
        timerEv:RegisterEvent("PLAYER_REGEN_DISABLED")
        timerEv:RegisterEvent("PLAYER_REGEN_ENABLED")
        if not CludesUI._unlockActive then
            T.Place(timerFrame)
        end
    else
        timerEv:UnregisterAllEvents()
        if timerFrame then
            timerFrame:Hide()
        end
    end
end

T.Start(TimerApply, {
    key = "CUI_CombatTimer",
    label = "Combat Timer",
    order = 742,
    frame = function(build)
        if build then
            TimerBuild()
            timerText:SetText("0:00")
            timerFrame:Show()
        end
        return timerFrame
    end,
    size = function()
        return 80, 22
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

-------------------------------------------------------------------------------
--  Combat Alert
-------------------------------------------------------------------------------
local A = module.Feature(
    "combatAlert",
    { enabled = false, sound = true },
    { point = "CENTER", relPoint = "CENTER", x = 0, y = 220 }
)
local alertFrame, alertText, fade

local function AlertBuild()
    if alertFrame then
        return alertFrame
    end
    alertFrame = CreateFrame("Frame", "CludesUICombatAlert", UIParent)
    alertFrame:SetSize(200, 30)
    alertText = Text(alertFrame, 24)
    fade = alertFrame:CreateAnimationGroup()
    local hold = fade:CreateAnimation("Alpha")
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetDuration(0.8)
    hold:SetOrder(1)
    local result = fade:CreateAnimation("Alpha")
    result:SetFromAlpha(1)
    result:SetToAlpha(0)
    result:SetDuration(0.6)
    result:SetOrder(2)
    fade:SetScript("OnFinished", function()
        alertFrame:Hide()
    end)
    alertFrame:Hide()
    return alertFrame
end

local alertEv = CreateFrame("Frame")
alertEv:SetScript("OnEvent", function(_, evt)
    local entering = evt == "PLAYER_REGEN_DISABLED"
    alertText:SetText(entering and "+ Combat" or "- Combat")
    if entering then
        alertText:SetTextColor(1, 0.35, 0.3)
    else
        alertText:SetTextColor(0.4, 0.9, 0.5)
    end
    fade:Stop()
    alertFrame:SetAlpha(1)
    alertFrame:Show()
    fade:Play()
    if A.Get("sound") then
        PlaySound(entering and SOUNDKIT.IG_PLAYER_INVITE or SOUNDKIT.IG_QUEST_LIST_SELECT, "Master")
    end
end)

local function AlertApply()
    if A.Enabled() then
        AlertBuild()
        alertEv:RegisterEvent("PLAYER_REGEN_DISABLED")
        alertEv:RegisterEvent("PLAYER_REGEN_ENABLED")
        if not CludesUI._unlockActive then
            A.Place(alertFrame)
        end
    else
        alertEv:UnregisterAllEvents()
    end
end

A.Start(AlertApply, {
    key = "CUI_CombatAlert",
    label = "Combat Alert",
    order = 743,
    frame = function(build)
        if build then
            AlertBuild()
            alertText:SetText("+ Combat")
            alertFrame:SetAlpha(1)
            alertFrame:Show()
        end
        return alertFrame
    end,
    size = function()
        return 200, 30
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

-------------------------------------------------------------------------------
--  Stealth Reminder
-------------------------------------------------------------------------------
local S = module.Feature(
    "stealthReminder",
    { enabled = false, groupOnly = false },
    { point = "CENTER", relPoint = "CENTER", x = 0, y = 180 }
)
local stealthFrame, stealthText
local _, class = UnitClass("player")
local CAT_FORM = 1

local function StealthWanted()
    if not S.Enabled() then
        return false
    end
    if CludesUI._unlockActive then
        return true
    end
    if class == "DRUID" then
        if not (GetShapeshiftFormID and GetShapeshiftFormID() == CAT_FORM) then
            return false
        end
    elseif class ~= "ROGUE" then
        return false
    end
    if InCombatLockdown() or IsStealthed() or IsResting() or UnitIsDeadOrGhost("player") or IsMounted() then
        return false
    end
    if S.Get("groupOnly") and not IsInGroup() then
        return false
    end
    return true
end

local function StealthBuild()
    if stealthFrame then
        return stealthFrame
    end
    stealthFrame = CreateFrame("Frame", "CludesUIStealthReminder", UIParent)
    stealthFrame:SetSize(180, 26)
    stealthText = Text(stealthFrame, 18)
    stealthText:SetText("Not stealthed")
    stealthText:SetTextColor(1, 0.8, 0.2)
    stealthFrame:Hide()
    return stealthFrame
end

local function StealthUpdate()
    if stealthFrame then
        stealthFrame:SetShown(StealthWanted())
    end
end

local stealthEv = CreateFrame("Frame")
stealthEv:SetScript("OnEvent", StealthUpdate)

local function StealthApply()
    if S.Enabled() then
        StealthBuild()
        for _, e in ipairs({
            "UPDATE_STEALTH",
            "UPDATE_SHAPESHIFT_FORM",
            "PLAYER_REGEN_DISABLED",
            "PLAYER_REGEN_ENABLED",
            "PLAYER_UPDATE_RESTING",
            "GROUP_ROSTER_UPDATE",
            "PLAYER_ENTERING_WORLD",
            "PLAYER_MOUNT_DISPLAY_CHANGED",
            "PLAYER_ALIVE",
            "PLAYER_UNGHOST",
        }) do
            stealthEv:RegisterEvent(e)
        end
        if not CludesUI._unlockActive then
            S.Place(stealthFrame)
        end
    else
        stealthEv:UnregisterAllEvents()
    end
    StealthUpdate()
end

S.Start(StealthApply, {
    key = "CUI_StealthReminder",
    label = "Stealth Reminder",
    order = 744,
    frame = function(build)
        if build then
            StealthBuild()
            StealthUpdate()
        end
        return stealthFrame
    end,
    size = function()
        return 180, 26
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

CludesUI._CombatExtras = {
    timer = { Get = T.Get, Cfg = T.Cfg, Apply = TimerApply },
    alert = { Get = A.Get, Cfg = A.Cfg, Apply = AlertApply },
    stealth = { Get = S.Get, Cfg = S.Cfg, Apply = StealthApply },
}
