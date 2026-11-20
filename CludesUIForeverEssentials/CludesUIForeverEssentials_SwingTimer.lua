if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-- Forever's swing API (Blizzard_APIDocumentationGenerated/SwingTimerDocumentation.lua).
if not (C_SwingTimer and Enum and Enum.PlayerSwingType) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_SwingTimer.lua  (WoW Forever only)
--  Swing Timer: one bar per weapon that swings (Main Hand, Off Hand, Ranged).
--  The server sends each swing's real length with PLAYER_SWING
--  (swingDuration, swingType), so haste, parry haste and resets are already
--  in it; nothing is guessed. A bar fills from the swing to the next one and
--  hides again when nothing has swung for a moment (Hide When Idle).
-------------------------------------------------------------------------------
local _, module = ...

local DEFAULTS = {
    enabled = false,
    width = 220,
    height = 12,
    offHand = true,
    ranged = true,
    hideIdle = true,
}
local F = module.Feature("swingTimer", DEFAULTS, { point = "CENTER", relPoint = "CENTER", x = 0, y = -170 })
local Get, Enabled = F.Get, F.Enabled

local SWING = Enum.PlayerSwingType
local ORDER = { SWING.MainHand, SWING.OffHand, SWING.Ranged }
local LABEL = { [SWING.MainHand] = "MH", [SWING.OffHand] = "OH", [SWING.Ranged] = "R" }
local COLOR = {
    [SWING.MainHand] = {}, -- the theme accent, read when the bar is made
    [SWING.OffHand] = { 0.55, 0.65, 0.95 },
    [SWING.Ranged] = { 0.45, 0.85, 0.50 },
}
local GAP = 3
local IDLE_AFTER = 0.4 -- seconds past a swing's end before its bar counts as idle

local holderFrame
local barList = {} -- [swingType] = StatusBar with .started, .duration

local function Font()
    return CludesUI.GetFontPath("essentials")
end

-- Whether the player has a weapon for this swing type right now.
local function HasWeapon(t)
    if t == SWING.MainHand then
        return true
    end
    if t == SWING.OffHand then
        if not Get("offHand") then
            return false
        end
        local _, oh = UnitAttackSpeed("player")
        return type(oh) == "number" and not (issecretvalue and issecretvalue(oh)) and oh > 0
    end
    if not Get("ranged") then
        return false
    end
    local speed = UnitRangedDamage("player")
    return type(speed) == "number" and not (issecretvalue and issecretvalue(speed)) and speed > 0
end

local function OnUpdate(barFrame)
    local leftX = barFrame.started + barFrame.duration - GetTime()
    if leftX > 0 then
        barFrame:SetValue(barFrame.duration - leftX)
        barFrame.text:SetText(("%.1f"):format(leftX))
    else
        barFrame:SetValue(barFrame.duration)
        barFrame.text:SetText("")
        if leftX < -IDLE_AFTER then
            barFrame.started = nil
            barFrame:SetScript("OnUpdate", nil)
            module.SwingLayout()
        end
    end
end

local function Bar(t)
    local widget = barList[t]
    if widget then
        return widget
    end
    widget = CreateFrame("StatusBar", nil, holderFrame)
    widget:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    if t == SWING.MainHand then
        CludesUI.Kit.SyncAccent(COLOR[t])
    end
    widget:GetStatusBarTexture():SetVertexColor(unpack(COLOR[t]))
    CludesUI.Kit.Panel(widget, 0.85)
    widget:SetMinMaxValues(0, 1)
    widget:SetValue(0)
    widget.label = widget:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(widget.label, 10, "essentials")
    widget.label:SetPoint("LEFT", 3, 0)
    widget.label:SetText(LABEL[t])
    widget.text = widget:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(widget.text, 10, "essentials")
    widget.text:SetPoint("RIGHT", -3, 0)
    barList[t] = widget
    return widget
end

local function Build()
    if holderFrame then
        return holderFrame
    end
    holderFrame = CreateFrame("Frame", "CludesUISwingTimer", UIParent)
    holderFrame:SetSize(Get("width"), Get("height"))
    for _, t in ipairs(ORDER) do
        Bar(t)
    end
    return holderFrame
end

--- Stacks the bars in use: a bar shows while it is swinging, or always when
--- Hide When Idle is off (and the weapon is there), or while Layout Mode is up.
function module.SwingLayout()
    if not holderFrame then
        return
    end
    local wid, hgt = Get("width"), Get("height")
    local preview = CludesUI._unlockActive
    local posY, isShown = 0, 0
    for _, t in ipairs(ORDER) do
        local widget = barList[t]
        local on = Enabled() and HasWeapon(t) and (widget.started or not Get("hideIdle") or preview)
        if on then
            widget:SetSize(wid, hgt)
            widget:ClearAllPoints()
            widget:SetPoint("TOP", holderFrame, "TOP", 0, posY)
            posY = posY - hgt - GAP
            isShown = isShown + 1
            widget:Show()
        else
            widget:Hide()
        end
    end
    holderFrame:SetSize(wid, math.max(1, isShown) * (hgt + GAP) - GAP)
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, evt, duration, swingType)
    if evt == "PLAYER_SWING" then
        local widget = barList[swingType]
        if
            not widget
            or type(duration) ~= "number"
            or (issecretvalue and issecretvalue(duration))
            or duration <= 0
        then
            return
        end
        local wasIdle = not widget.started
        widget.started, widget.duration = GetTime(), duration
        widget:SetMinMaxValues(0, duration)
        widget:SetValue(0)
        widget:SetScript("OnUpdate", OnUpdate)
        if wasIdle then
            module.SwingLayout()
        end
    else
        module.SwingLayout() -- a weapon swap or login can add or drop a bar
    end
end)

local function Apply()
    if Enabled() then
        Build()
        eventFrame:RegisterEvent("PLAYER_SWING")
        eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        if not CludesUI._unlockActive then
            F.Place(holderFrame)
        end
    else
        eventFrame:UnregisterAllEvents()
        for _, bar in pairs(barList) do
            bar.started = nil
            bar:SetScript("OnUpdate", nil)
        end
    end
    module.SwingLayout()
end

CludesUI._SwingTimer = { Get = Get, Read = F.Read, Cfg = F.Cfg, Apply = Apply }

F.Start(Apply, {
    key = "CUI_SwingTimer",
    label = "Swing Timer",
    order = 736,
    frame = function(build)
        if build then
            Build()
            module.SwingLayout()
        end
        return holderFrame
    end,
    size = function()
        return Get("width"), Get("height") * 3 + GAP * 2
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
