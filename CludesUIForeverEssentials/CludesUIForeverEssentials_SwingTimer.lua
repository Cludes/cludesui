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

local holder
local bars = {} -- [swingType] = StatusBar with .started, .duration

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

local function OnUpdate(bar)
    local left = bar.started + bar.duration - GetTime()
    if left > 0 then
        bar:SetValue(bar.duration - left)
        bar.text:SetText(("%.1f"):format(left))
    else
        bar:SetValue(bar.duration)
        bar.text:SetText("")
        if left < -IDLE_AFTER then
            bar.started = nil
            bar:SetScript("OnUpdate", nil)
            module.SwingLayout()
        end
    end
end

local function Bar(t)
    local b = bars[t]
    if b then
        return b
    end
    b = CreateFrame("StatusBar", nil, holder)
    b:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    if t == SWING.MainHand then
        CludesUI.Kit.SyncAccent(COLOR[t])
    end
    b:GetStatusBarTexture():SetVertexColor(unpack(COLOR[t]))
    CludesUI.Kit.Panel(b, 0.85)
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)
    b.label = b:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(b.label, 10, "essentials")
    b.label:SetPoint("LEFT", 3, 0)
    b.label:SetText(LABEL[t])
    b.text = b:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(b.text, 10, "essentials")
    b.text:SetPoint("RIGHT", -3, 0)
    bars[t] = b
    return b
end

local function Build()
    if holder then
        return holder
    end
    holder = CreateFrame("Frame", "CludesUISwingTimer", UIParent)
    holder:SetSize(Get("width"), Get("height"))
    for _, t in ipairs(ORDER) do
        Bar(t)
    end
    return holder
end

--- Stacks the bars in use: a bar shows while it is swinging, or always when
--- Hide When Idle is off (and the weapon is there), or while Layout Mode is up.
function module.SwingLayout()
    if not holder then
        return
    end
    local w, h = Get("width"), Get("height")
    local preview = CludesUI._unlockActive
    local y, shown = 0, 0
    for _, t in ipairs(ORDER) do
        local b = bars[t]
        local on = Enabled() and HasWeapon(t) and (b.started or not Get("hideIdle") or preview)
        if on then
            b:SetSize(w, h)
            b:ClearAllPoints()
            b:SetPoint("TOP", holder, "TOP", 0, y)
            y = y - h - GAP
            shown = shown + 1
            b:Show()
        else
            b:Hide()
        end
    end
    holder:SetSize(w, math.max(1, shown) * (h + GAP) - GAP)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, duration, swingType)
    if event == "PLAYER_SWING" then
        local b = bars[swingType]
        if
            not b
            or type(duration) ~= "number"
            or (issecretvalue and issecretvalue(duration))
            or duration <= 0
        then
            return
        end
        local wasIdle = not b.started
        b.started, b.duration = GetTime(), duration
        b:SetMinMaxValues(0, duration)
        b:SetValue(0)
        b:SetScript("OnUpdate", OnUpdate)
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
        ev:RegisterEvent("PLAYER_SWING")
        ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        if not CludesUI._unlockActive then
            F.Place(holder)
        end
    else
        ev:UnregisterAllEvents()
        for _, b in pairs(bars) do
            b.started = nil
            b:SetScript("OnUpdate", nil)
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
        return holder
    end,
    size = function()
        return Get("width"), Get("height") * 3 + GAP * 2
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
