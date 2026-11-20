if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIQoL_SelfCombatText.lua - your own combat text, above your frame.
--
--  Damage taken, heals received, avoids and entering/leaving combat, drawn
--  above the player frame instead of the game's text pinned in the world.
--  Each message rises (straight), arcs to alternating sides (fountain) or
--  stays (static), and fades over the last 30% of its time; with Stagger,
--  messages in flight make room so none overlap.
--
--  The game's CombatText frame is only hidden, never written to (it ignores
--  events while hidden). The event values are secret, so they only ever reach
--  the game's own formatters and FontString setters: nothing here compares
--  or computes with them. Messages move on animation groups (no OnUpdate).
--  While off, nothing is created or listened to.
--
--  Settings: the QoL profile's selfCombatText table, read into a cache by
--  Refresh (login, profile swaps and the options all call it). The box is a
--  Layout Mode element (CUI_SelfCombatText); unmoved, it sits above the
--  player frame.
-------------------------------------------------------------------------------
local _, mod = ...
local CUI = _G.CludesUI
-- WoW Forever: numbers under 10,000 do not abbreviate (CludesUI_NumberFormat.lua).
local Abbreviate = (CUI.IS_FOREVER and CUI.ForeverAbbreviateNumbers) or AbbreviateNumbers

local LAYOUT_KEY = "CUI_SelfCombatText"
local MESSAGES = 12 -- at once; a burst past this restarts the oldest
local FADE_PART = 0.3 -- fading over the last 30% of a message's time
local BOX_W, BOX_H = 200, 30
local LINE = 1.15 -- a message's height per point of font size
local GAP = 2 -- px between staggered messages

local DEFAULTS = {
    enabled = false,
    size = 16,
    critScale = 1.5,
    rise = 80,
    duration = 1.9,
    stagger = true,
    anim = "straight", -- straight | fountain | static
    direction = "up", -- up | down
    font = "__combat", -- __combat (the game's combat text font), __global (the QoL font) or a font
    outline = "OUTLINE", -- NONE | OUTLINE | THICKOUTLINE
    shadow = false,
    abbreviate = false,
    damage = true,
    heal = true,
    avoid = true,
    combat = true,
    damageColor = { r = 1, g = 0.1, b = 0.1 },
    healColor = { r = 0.1, g = 1, b = 0.1 },
    avoidColor = { r = 1, g = 1, b = 1 },
    combatColor = { r = 1, g = 0.1, b = 0.1 },
}

-- Event type -> is it a crit.
local DAMAGE = {
    DAMAGE = false,
    SPELL_DAMAGE = false,
    DAMAGE_SHIELD = false,
    DAMAGE_CRIT = true,
    SPELL_DAMAGE_CRIT = true,
}
local HEAL = { HEAL = false, PERIODIC_HEAL = false, HEAL_CRIT = true, PERIODIC_HEAL_CRIT = true }
-- Avoids, shown with the game's COMBAT_TEXT_* word (the SPELL_ form too).
local AVOIDS =
    { "MISS", "DODGE", "PARRY", "EVADE", "IMMUNE", "DEFLECT", "REFLECT", "RESIST", "BLOCK", "ABSORB" }
local avoidWord = {}

-- The fountain's arc: a quarter circle of radius 1 (sideways, along the scroll).
local ARC = { { 0.134, 0.5 }, { 0.5, 0.866 }, { 1, 1 } }

local box, listener, db
local messages = {}
local last = 0 -- the last message used
local on = false
local side = 1 -- the fountain's next side
-- The settings as messages read them (refilled by Refresh). fontGen tells a
-- pooled message its font is out of date.
local S = { fontGen = 0 }

-- The QoL profile (no defaults merged in: Get falls back to DEFAULTS).
local function Profile()
    db = db or CUI.Lite.NewDB("CludesUIQoLDB")
    return db.profile
end

local function SctGet(key)
    local tbl = Profile().selfCombatText
    local value = tbl and tbl[key]
    if value == nil then
        return DEFAULTS[key]
    end
    return value
end

local function Own()
    local profile = Profile()
    profile.selfCombatText = profile.selfCombatText or {}
    return profile.selfCombatText
end

local function Wanted()
    return SctGet("enabled") == true
end

-- The font follows these settings only (a global or QoL font change asks
-- for a reload).
local function ReadSettings()
    local font = SctGet("font")
    if font == "__global" then
        S.font = CUI.GetFontPath("extras")
    elseif font ~= "__combat" then
        S.font = CUI.ResolveFontName(font)
    else
        local frame = _G.CombatTextFont
        S.font = frame and frame:GetFont() or STANDARD_TEXT_FONT
    end
    local outline = SctGet("outline")
    if outline == "OUTLINE" then
        S.flags = CUI.SlugFlag("OUTLINE, SLUG")
    elseif outline == "THICKOUTLINE" then
        S.flags = CUI.SlugFlag("THICKOUTLINE, SLUG")
    else
        S.flags = ""
    end
    S.shadow = SctGet("shadow") == true
    S.size = SctGet("size")
    S.critSize = S.size * SctGet("critScale")
    S.fontGen = S.fontGen + 1
    S.anim, S.rise, S.duration = SctGet("anim"), SctGet("rise"), SctGet("duration")
    S.dy = SctGet("direction") == "down" and -S.rise or S.rise
    S.stagger, S.abbreviate = SctGet("stagger"), SctGet("abbreviate")
    S.damage, S.heal, S.avoid, S.combat = SctGet("damage"), SctGet("heal"), SctGet("avoid"), SctGet("combat")
    S.damageColor, S.healColor = SctGet("damageColor"), SctGet("healColor")
    S.avoidColor, S.combatColor = SctGet("avoidColor"), SctGet("combatColor")
end

-------------------------------------------------------------------------------
--  Where the box sits (Layout Mode's once moved)
-------------------------------------------------------------------------------
local function Place()
    if not box then
        return
    end
    local position = SctGet("pos")
    box:ClearAllPoints()
    if position then
        box:SetPoint(position.point, UIParent, position.relPoint or position.point, position.x, position.y)
        return
    end
    local player = _G.CludesUIUnitFrames_Player
    if player then
        box:SetPoint("BOTTOM", player, "TOP", 0, 10)
    else
        box:SetPoint("BOTTOM", UIParent, "CENTER", 0, -140)
    end
end

local function AddToLayoutMode()
    CUI:RegisterUnlockElements({
        CUI.MakeUnlockElement({
            key = LAYOUT_KEY,
            label = "Self Combat Text",
            group = "Utilities",
            order = 730,
            noResize = true,
            isHidden = function()
                return not Wanted()
            end,
            getFrame = function()
                return on and box or nil
            end,
            getSize = function()
                return BOX_W, BOX_H
            end,
            savePos = function(_, point, relPoint, x, y)
                if not point then
                    return
                end
                Own().pos = { point = point, relPoint = relPoint or point, x = x, y = y }
                if not CUI._unlockActive then
                    Place()
                end
            end,
            loadPos = function()
                local position = SctGet("pos")
                if position then
                    return { point = position.point, relPoint = position.relPoint or position.point, x = position.x, y = position.y }
                end
            end,
            clearPos = function()
                local tbl = Profile().selfCombatText
                if tbl then
                    tbl.pos = nil
                end
                Place()
            end,
            applyPos = Place,
        }),
    }, "CludesUIQoL")
end

-------------------------------------------------------------------------------
--  Messages
-------------------------------------------------------------------------------
-- Sets every message's animation to the current style and time.
local function Tune()
    local time, style = S.duration, S.anim
    for _, m in ipairs(messages) do
        m.move:SetOffset(0, style == "straight" and S.dy or 0)
        m.move:SetDuration(time)
        m.arc:SetDuration(time)
        if style ~= "fountain" then
            for _, point in ipairs(m.points) do
                point:SetOffset(0, 0)
            end
        end
        m.fade:SetStartDelay(time * (1 - FADE_PART))
        m.fade:SetDuration(time * FADE_PART)
    end
end

local function Build()
    box = CreateFrame("Frame", nil, UIParent)
    box:SetSize(BOX_W, BOX_H)
    box:SetFrameStrata("HIGH")
    for i = 1, MESSAGES do
        local m = box:CreateFontString(nil, "OVERLAY")
        m:Hide()
        local group = m:CreateAnimationGroup()
        m.move = group:CreateAnimation("Translation")
        m.arc = group:CreateAnimation("Path")
        m.arc:SetCurveType("SMOOTH")
        m.points = {}
        for j = 1, #ARC do
            m.points[j] = m.arc:CreateControlPoint(nil, nil, j)
        end
        m.fade = group:CreateAnimation("Alpha")
        m.fade:SetFromAlpha(1)
        m.fade:SetToAlpha(0)
        group:SetScript("OnFinished", function()
            m:Hide()
            m.live = nil
        end)
        m.group = group
        messages[i] = m
    end
    for _, kind in ipairs(AVOIDS) do
        local word = _G["COMBAT_TEXT_" .. kind]
        avoidWord[kind], avoidWord["SPELL_" .. kind] = word, word
    end
    listener = CreateFrame("Frame")
    Place()
    AddToLayoutMode()
end

-- How far along its scroll a message is now (a part of the distance):
-- straight is linear, the fountain follows its arc's height (its points are
-- evenly spaced in time), static does not move.
local function Progress(m, now)
    if S.anim == "static" then
        return 0
    end
    local t = math.min((now - m.t0) / S.duration, 1)
    if S.anim ~= "fountain" then
        return t
    end
    local at = t * #ARC
    local i = math.floor(at)
    if i >= #ARC then
        return ARC[#ARC][2]
    end
    local from = i > 0 and ARC[i][2] or 0
    return from + (ARC[i + 1][2] - from) * (at - i)
end

-- Stagger: before a message of height h starts at the box, the messages in
-- flight in its lane (all of them, or one side of the fountain) move on
-- together until the nearest is clear of it. Spacing holds, and the newest
-- always starts at the box; static stacks the same way.
local function MakeRoom(lane, h)
    local now, time, dy = GetTime(), S.duration, S.dy
    local direction = dy < 0 and -1 or 1
    local nearest, distance
    for _, m in ipairs(messages) do
        if m.live and m.lane == lane and now - m.t0 < time then
            local skinData = direction * (m.y0 + dy * Progress(m, now))
            if not distance or skinData < distance then
                nearest, distance = m, skinData
            end
        end
    end
    if not nearest then
        return
    end
    -- Rising, the new one's top must clear the nearest's bottom; falling, the
    -- nearest's top must clear the box.
    local need = (direction > 0 and h or nearest.h) + GAP - distance
    if need <= 0 then
        return
    end
    for _, m in ipairs(messages) do
        if m.live and m.lane == lane and now - m.t0 < time then
            m.y0 = m.y0 + direction * need
            m:SetPoint("BOTTOM", box, "BOTTOM", 0, m.y0)
        end
    end
end

local function Show(format, value, color, crit)
    last = last % MESSAGES + 1
    local m = messages[last]
    m.group:Stop()
    m.live = nil
    local lane = 0
    if S.anim == "fountain" then
        -- Alternating sides, as the game's fountain does.
        side = -side
        lane = side
        for j, point in ipairs(m.points) do
            point:SetOffset(side * ARC[j][1] * S.rise, ARC[j][2] * S.dy)
        end
    end
    local size = crit and S.critSize or S.size
    local h = size * LINE
    if S.stagger then
        MakeRoom(lane, h)
    end
    m.t0, m.y0, m.h, m.lane, m.live = GetTime(), 0, h, lane, true
    m:ClearAllPoints()
    m:SetPoint("BOTTOM", box, "BOTTOM", 0, 0)
    -- A pooled message's font changes only with the settings, or between a
    -- hit and a crit.
    local kind = crit and 2 or 1
    if m.fontGen ~= S.fontGen or m.fontKind ~= kind then
        m.fontGen, m.fontKind = S.fontGen, kind
        CUI.PrimeFontShadow(m, S.shadow)
        m:SetFont(S.font, size, S.flags)
    end
    m:SetTextColor(color.r, color.g, color.b)
    m:SetFormattedText(format, value)
    m:SetAlpha(1)
    m:Show()
    m.group:Play()
end

-- Both are the game's own formatters, which take secret numbers.
local function Amount(n)
    if S.abbreviate then
        return Abbreviate(n)
    end
    return BreakUpLargeNumbers(n)
end

local function OnEvent(_, event, kind, inVehicle)
    if event == "COMBAT_TEXT_UPDATE" then
        local crit = DAMAGE[kind]
        if crit ~= nil then
            if S.damage then
                Show("-%s", Amount(C_CombatText.GetCurrentEventInfo()), S.damageColor, crit)
            end
            return
        end
        crit = HEAL[kind]
        if crit ~= nil then
            if S.heal then
                -- A heal's info is (healer, amount).
                local _, amount = C_CombatText.GetCurrentEventInfo()
                Show("+%s", Amount(amount), S.healColor, crit)
            end
            return
        end
        local word = S.avoid and avoidWord[kind]
        if word then
            Show("%s", word, S.avoidColor, false)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        Show("%s", _G.ENTERING_COMBAT or "+Combat", S.combatColor, false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        Show("%s", _G.LEAVING_COMBAT or "-Combat", S.combatColor, false)
    elseif event == "UNIT_ENTERED_VEHICLE" then
        C_CombatText.SetActiveUnit(inVehicle and "vehicle" or "player")
    elseif event == "UNIT_EXITING_VEHICLE" then
        C_CombatText.SetActiveUnit("player")
    elseif event == "ADDON_LOADED" and kind == "Blizzard_CombatText" and _G.CombatText then
        _G.CombatText:Hide()
        listener:UnregisterEvent("ADDON_LOADED")
    end
end

-- Only the events the switched-on kinds need.
local function Listen()
    if S.damage or S.heal or S.avoid then
        listener:RegisterEvent("COMBAT_TEXT_UPDATE")
        listener:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
        listener:RegisterUnitEvent("UNIT_EXITING_VEHICLE", "player")
    else
        listener:UnregisterEvent("COMBAT_TEXT_UPDATE")
        listener:UnregisterEvent("UNIT_ENTERED_VEHICLE")
        listener:UnregisterEvent("UNIT_EXITING_VEHICLE")
    end
    if S.combat then
        listener:RegisterEvent("PLAYER_REGEN_DISABLED")
        listener:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        listener:UnregisterEvent("PLAYER_REGEN_DISABLED")
        listener:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function Refresh()
    local want = Wanted()
    if want == on then
        if want then
            ReadSettings()
            Tune()
            Listen()
        end
        return
    end
    on = want
    if want then
        if not box then
            Build()
        end
        ReadSettings()
        Tune()
        box:Show()
        listener:SetScript("OnEvent", OnEvent)
        Listen()
        C_CombatText.SetActiveUnit(UnitHasVehicleUI("player") and "vehicle" or "player")
        if _G.CombatText then
            _G.CombatText:Hide()
        else
            listener:RegisterEvent("ADDON_LOADED")
        end
    else
        listener:UnregisterAllEvents()
        box:Hide()
        if _G.CombatText then
            _G.CombatText:Show()
        end
    end
end

mod.SCT_Refresh = Refresh
mod.SCT_Get = SctGet
CUI._applySelfCombatText = Refresh -- profile swaps (RefreshAllAddons)

function mod.SCT_Set(key, value)
    Own()[key] = value
    Refresh()
end

-- The QoL page's reset: every setting back to its default, and the box's
-- Layout Mode anchor link dropped.
function mod.SCT_Reset()
    Profile().selfCombatText = nil
    if CludesUIDB.unlockAnchors then
        CludesUIDB.unlockAnchors[LAYOUT_KEY] = nil
    end
    Refresh()
    Place()
end
