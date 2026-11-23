if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CludesUIQoL_WaypointPin.lua  (both clients, where the game has navigation)
--  Waypoint Pin: the game's tracked spot in the world (a map pin, a quest,
--  your corpse) drawn in the CludesUI look: a flat diamond, square or dot in
--  the accent colour, what it is above it, the distance under it, three
--  downward arrows over it, and for a quest its unfinished objectives.
--
--  It rides the game's own SuperTrackedFrame, which follows the navigation
--  frame, clamps to the screen edge and fades near the spot; only the game's
--  icon, its border and its distance text go to alpha 0 (its edge arrow
--  stays, pointing the way while the spot is off screen). Nothing here sets
--  a waypoint or tracking (see CludesUIQoL_Waypoint.lua on taint).
--  Settings: CludesUIDB.waypointPin { enabled, shape, size, arrows, objectives }.
-------------------------------------------------------------------------------

local DEFAULTS = { enabled = false, shape = "diamond", size = 1, arrows = true, objectives = true }
local PIN = 30
local GAME_PARTS = { "Icon", "IconBorder", "DistanceText" }
local CIRCLE = "Interface\\AddOns\\CludesUI\\media\\rounded\\circle-32.tga"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ARROW = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-down3.png"
local OBJECTIVES_MAX = 6
local UPDATE_EVERY = 0.1

local pin, gameHidden
local events = CreateFrame("Frame")

local function Get(key)
    local c = CludesUIDB and CludesUIDB.waypointPin
    local v = c and c[key]
    if v == nil then return DEFAULTS[key] end
    return v
end
local function Cfg()
    if not CludesUIDB then return {} end
    CludesUIDB.waypointPin = CludesUIDB.waypointPin or {}
    return CludesUIDB.waypointPin
end
local function Secret(v) return issecretvalue and issecretvalue(v) end

local function HideGameParts(hide)
    if hide == gameHidden or not SuperTrackedFrame then return end
    gameHidden = hide
    for _, key in ipairs(GAME_PARTS) do
        local part = SuperTrackedFrame[key]
        if part then part:SetAlpha(hide and 0 or 1) end
    end
end

local function Text(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(fs, size, nil, "OUTLINE")
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    return fs
end

local function Build()
    if pin then return pin end
    local Kit = CUI.Kit
    pin = CreateFrame("Frame", "CludesUIWaypointPin", SuperTrackedFrame)
    pin:SetPoint("CENTER", SuperTrackedFrame, "CENTER")
    pin:SetSize(PIN, PIN)
    pin.rim = pin:CreateTexture(nil, "ARTWORK", nil, 1)
    pin.body = pin:CreateTexture(nil, "ARTWORK", nil, 2)
    pin.gem = pin:CreateTexture(nil, "ARTWORK", nil, 3)
    for _, t in ipairs({ pin.rim, pin.body, pin.gem }) do
        t:SetPoint("CENTER")
    end
    pin.arrows = {}
    for i = 1, 3 do
        local a = pin:CreateTexture(nil, "ARTWORK")
        a:SetTexture(ARROW)
        a:SetSize(12, 12)
        a:SetAlpha(0.4 + 0.2 * i)
        pin.arrows[i] = a
    end
    pin.title = Text(pin, 13)
    pin.distance = Text(pin, 12)
    pin.distance:SetPoint("TOP", pin, "BOTTOM", 0, -3)
    pin.objectives = Text(pin, 11)
    pin.objectives:SetWordWrap(true)
    pin.objectives:SetWidth(240)
    pin.objectives:SetJustifyV("BOTTOM")
    local m = Kit.Palette.text
    pin.title:SetTextColor(m[1], m[2], m[3])
    pin.objectives:SetTextColor(Kit.Palette.muted[1], Kit.Palette.muted[2], Kit.Palette.muted[3])
    return pin
end

-- Shape, size and the accent colour.
local function Style()
    local Kit = CUI.Kit
    local r, g, b = Kit.Accent()
    local size = PIN * (Get("size") or 1)
    pin:SetSize(size, size)
    local shape = Get("shape")
    local round = shape == "dot"
    local turn = shape == "diamond" and math.rad(45) or 0
    local inner = shape == "diamond" and 0.7 or 1
    for _, t in ipairs({ pin.rim, pin.body, pin.gem }) do
        t:SetTexture(round and CIRCLE or WHITE)
        t:SetRotation(turn)
    end
    local s = size * inner
    pin.rim:SetSize(s, s)
    pin.rim:SetVertexColor(0, 0, 0, 0.9)
    pin.body:SetSize(s - 4, s - 4)
    pin.body:SetVertexColor(r, g, b, 0.35)
    pin.gem:SetSize(s * 0.4, s * 0.4)
    pin.gem:SetVertexColor(r, g, b, 1)
    pin.distance:SetTextColor(r, g, b)
    for i, a in ipairs(pin.arrows) do
        a:SetVertexColor(r, g, b)
        a:ClearAllPoints()
        a:SetPoint("BOTTOM", pin, "TOP", 0, 4 + (3 - i) * 10)
        a:SetShown(Get("arrows") == true)
    end
end

-- What is tracked, and for a quest its unfinished objectives.
local function Describe()
    local types = Enum.SuperTrackingType
    local kind = C_SuperTrack.GetHighestPrioritySuperTrackingType and C_SuperTrack.GetHighestPrioritySuperTrackingType()
    local title, lines = CUI.L("Waypoint"), nil
    if types and kind == types.Quest then
        local quest = C_SuperTrack.GetSuperTrackedQuestID()
        title = (quest and C_QuestLog.GetTitleForQuestID(quest)) or CUI.L("Quest")
        if Get("objectives") and quest and C_QuestLog.GetQuestObjectives then
            for _, o in ipairs(C_QuestLog.GetQuestObjectives(quest) or {}) do
                if o.text and not o.finished and not Secret(o.text) then
                    lines = lines or {}
                    if #lines < OBJECTIVES_MAX then lines[#lines + 1] = o.text end
                end
            end
        end
    elseif types and kind == types.UserWaypoint then
        title = CUI.L("Map Pin")
    elseif types and kind == types.Corpse then
        title = CUI.L("Your Corpse")
    end
    return title, lines
end

local function Retitle()
    if not pin then return end
    local title, lines = Describe()
    pin.title:SetText(title)
    local top = Get("arrows") and (pin.arrows[1]) or pin
    pin.title:ClearAllPoints()
    pin.title:SetPoint("BOTTOM", top, "TOP", 0, 4)
    if lines then
        pin.objectives:SetText(table.concat(lines, "\n"))
        pin.objectives:ClearAllPoints()
        pin.objectives:SetPoint("BOTTOM", pin.title, "TOP", 0, 3)
        pin.objectives:Show()
    else
        pin.objectives:SetText("")
        pin.objectives:Hide()
    end
end

-- Distance under the pin; at the screen edge only the pin (smaller) and the
-- game's arrow show.
local since = 0
local function OnUpdate(_, elapsed)
    since = since + elapsed
    if since < UPDATE_EVERY then return end
    since = 0
    if not (C_Navigation and C_Navigation.HasValidScreenPosition and C_Navigation.HasValidScreenPosition()) then
        pin:SetAlpha(0)
        return
    end
    pin:SetAlpha(1)
    local clamped = C_Navigation.WasClampedToScreen()
    local edge = not Secret(clamped) and clamped == true
    pin:SetScale(edge and 0.6 or 1)
    pin.title:SetShown(not edge)
    pin.distance:SetShown(not edge)
    if pin.objectives:GetText() and pin.objectives:GetText() ~= "" then pin.objectives:SetShown(not edge) end
    for _, a in ipairs(pin.arrows) do
        a:SetShown(not edge and Get("arrows") == true)
    end
    if not edge then
        local yards = C_Navigation.GetDistance()
        if yards then pin.distance:SetFormattedText("%d " .. CUI.L("yd"), yards) end
    end
end

events:SetScript("OnEvent", function() Retitle() end)

local function Apply()
    local on = Get("enabled") == true and SuperTrackedFrame ~= nil and C_Navigation ~= nil
    if not on then
        events:UnregisterAllEvents()
        if pin then
            pin:SetScript("OnUpdate", nil)
            pin:Hide()
        end
        HideGameParts(false)
        return
    end
    Build()
    Style()
    pin:Show()
    pin:SetScript("OnUpdate", OnUpdate)
    HideGameParts(true)
    events:RegisterEvent("SUPER_TRACKING_CHANGED")
    events:RegisterEvent("QUEST_LOG_UPDATE")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    Retitle()
end

CUI._WaypointPin = { Get = Get, Cfg = Cfg, Apply = Apply }

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
end)
