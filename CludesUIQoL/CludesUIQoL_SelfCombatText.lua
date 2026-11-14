if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- CludesUIQoL_SelfCombatText.lua
-- Self combat text (damage taken, heals received, avoids, combat enter/leave)
-- drawn above the player frame in place of Blizzard's WorldFrame-pinned
-- scrolling text.
--
-- Blizzard's CombatText frame is only hidden, never written to: its OnEvent
-- bails while hidden. Event data from C_CombatText.GetCurrentEventInfo is
-- secret, so values only reach C formatters and FontString setters; nothing
-- here compares or does arithmetic on them. Messages scroll on engine
-- animation groups (no OnUpdate). Off, nothing is created or registered.
--
-- Settings: the QoL profile's selfCombatText table, read into a cache by
-- Refresh. Login (CludesUIQoL.lua), profile swaps (RefreshAllAddons) and
-- option changes all route through Refresh. The anchor box is an unlock mode
-- element (CUI_SelfCombatText): unlock mode applies saved positions and
-- anchor links; with nothing saved it sits above the player frame.
-------------------------------------------------------------------------------
local _, mod = ...
local CludesUI = _G.CludesUI
-- WoW Forever: no number under 10,000 abbreviates (CludesUI_NumberFormat.lua)
local AbbreviateNumbers = (CludesUI.IS_FOREVER and CludesUI.ForeverAbbreviateNumbers) or AbbreviateNumbers

local POOL_SIZE = 12
local FADE_FRAC = 0.3 -- fade over the last 30% of the scroll
local UNLOCK_KEY = "CUI_SelfCombatText"
local BOX_W, BOX_H = 200, 30
local LINE_H = 1.15 -- a message's line height per point of font size
local LINE_GAP = 2 -- px kept between staggered messages

local DEFAULTS = {
    enabled = false,
    size = 16,
    critScale = 1.5,
    rise = 80,
    duration = 1.9,
    stagger = true,
    anim = "straight", -- straight | fountain | static
    direction = "up", -- up | down
    font = "__combat", -- __combat (CombatTextFont), __global (QoL font) or a font key
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

-- type -> isCrit
local DAMAGE = {
    DAMAGE = false,
    SPELL_DAMAGE = false,
    DAMAGE_SHIELD = false,
    DAMAGE_CRIT = true,
    SPELL_DAMAGE_CRIT = true,
}
local HEAL = {
    HEAL = false,
    PERIODIC_HEAL = false,
    HEAL_CRIT = true,
    PERIODIC_HEAL_CRIT = true,
}
-- Avoid types; Build fills avoidLabel with their COMBAT_TEXT_* strings.
local AVOID = {
    "MISS",
    "DODGE",
    "PARRY",
    "EVADE",
    "IMMUNE",
    "DEFLECT",
    "REFLECT",
    "RESIST",
    "BLOCK",
    "ABSORB",
}
local avoidLabel = {}

-- Fountain arc: quarter circle of radius 1, x toward the side, y along the scroll
local ARC = { { 0.134, 0.5 }, { 0.5, 0.866 }, { 1, 1 } }

local anchor, ev, saved
local pool = {}
local nextIdx = 0
local enabled = false
local xDir = 1
-- Settings as the message path reads them, refilled by Refresh. fontVer tells
-- a pooled string its font is stale.
local S = { fontVer = 0 }

-- The QoL profile (the shared CludesUIQoLDB; no defaults are merged in:
-- Get falls back to DEFAULTS).
local function Profile()
    if not saved then
        saved = CludesUI.Lite.NewDB("CludesUIQoLDB")
    end
    return saved.profile
end

local function Get(k)
    local t = Profile().selfCombatText
    local val = t and t[k]
    if val == nil then
        return DEFAULTS[k]
    end
    return val
end

local function Settings()
    local p = Profile()
    local t = p.selfCombatText
    if not t then
        t = {}
        p.selfCombatText = t
    end
    return t
end

local function Enabled()
    return Get("enabled") == true
end

-- The font follows the settings only: a global or QoL font change asks for a
-- reload, so nothing else invalidates it.
local function ReadSettings()
    local key = Get("font")
    if key == "__global" then
        S.font = CludesUI.GetFontPath("extras")
    elseif key ~= "__combat" then
        S.font = CludesUI.ResolveFontName(key)
    else
        local f = _G.CombatTextFont
        S.font = f and f:GetFont() or STANDARD_TEXT_FONT
    end
    local outline = Get("outline")
    S.flags = (outline == "OUTLINE" and CludesUI.SlugFlag("OUTLINE, SLUG"))
        or (outline == "THICKOUTLINE" and CludesUI.SlugFlag("THICKOUTLINE, SLUG"))
        or ""
    S.shadow = Get("shadow") == true
    S.size = Get("size")
    S.critSize = S.size * Get("critScale")
    S.fontVer = S.fontVer + 1
    S.anim, S.rise, S.duration = Get("anim"), Get("rise"), Get("duration")
    S.dy = Get("direction") == "down" and -S.rise or S.rise
    S.stagger, S.abbreviate = Get("stagger"), Get("abbreviate")
    S.damage, S.heal, S.avoid, S.combat = Get("damage"), Get("heal"), Get("avoid"), Get("combat")
    S.damageColor, S.healColor = Get("damageColor"), Get("healColor")
    S.avoidColor, S.combatColor = Get("avoidColor"), Get("combatColor")
end

-------------------------------------------------------------------------------
--  Position (unlock mode owns it once saved)
-------------------------------------------------------------------------------
local function ApplyPos()
    if not anchor then
        return
    end
    local place = Get("pos")
    anchor:ClearAllPoints()
    if place then
        anchor:SetPoint(place.point, UIParent, place.relPoint or place.point, place.x, place.y)
        return
    end
    local popFrame = _G.CludesUIUnitFrames_Player
    if popFrame then
        anchor:SetPoint("BOTTOM", popFrame, "TOP", 0, 10)
    else
        anchor:SetPoint("BOTTOM", UIParent, "CENTER", 0, -140)
    end
end

local function RegisterMover()
    CludesUI:RegisterUnlockElements({
        CludesUI.MakeUnlockElement({
            key = UNLOCK_KEY,
            label = "Self Combat Text",
            group = "Utilities",
            order = 730,
            noResize = true,
            isHidden = function()
                return not Enabled()
            end,
            getFrame = function()
                return enabled and anchor or nil
            end,
            getSize = function()
                return BOX_W, BOX_H
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                if not anchorPoint then
                    return
                end
                Settings().pos =
                    { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
                if not CludesUI._unlockActive then
                    ApplyPos()
                end
            end,
            loadPos = function()
                local place = Get("pos")
                if not place then
                    return nil
                end
                return {
                    point = place.point,
                    relPoint = place.relPoint or place.point,
                    x = place.x,
                    y = place.y,
                }
            end,
            clearPos = function()
                local t = Profile().selfCombatText
                if t then
                    t.pos = nil
                end
                ApplyPos()
            end,
            applyPos = ApplyPos,
        }),
    }, "CludesUIQoL")
end

-------------------------------------------------------------------------------
--  Message pool
-------------------------------------------------------------------------------
local function ApplyAnim()
    local dur, mode = S.duration, S.anim
    for idx = 1, POOL_SIZE do
        local fontStr = pool[idx]
        fontStr.mv:SetOffset(0, mode == "straight" and S.dy or 0)
        fontStr.mv:SetDuration(dur)
        fontStr.path:SetDuration(dur)
        if mode ~= "fountain" then
            for jdx = 1, #ARC do
                fontStr.cps[jdx]:SetOffset(0, 0)
            end
        end
        fontStr.fade:SetStartDelay(dur * (1 - FADE_FRAC))
        fontStr.fade:SetDuration(dur * FADE_FRAC)
    end
end

local function Build()
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetSize(BOX_W, BOX_H)
    anchor:SetFrameStrata("HIGH")
    for idx = 1, POOL_SIZE do
        local fontStr = anchor:CreateFontString(nil, "OVERLAY")
        fontStr:Hide()
        local ag = fontStr:CreateAnimationGroup()
        fontStr.mv = ag:CreateAnimation("Translation")
        fontStr.path = ag:CreateAnimation("Path")
        fontStr.path:SetCurveType("SMOOTH")
        fontStr.cps = {}
        for jdx = 1, #ARC do
            fontStr.cps[jdx] = fontStr.path:CreateControlPoint(nil, nil, jdx)
        end
        fontStr.fade = ag:CreateAnimation("Alpha")
        fontStr.fade:SetFromAlpha(1)
        fontStr.fade:SetToAlpha(0)
        ag:SetScript("OnFinished", function()
            fontStr:Hide()
            fontStr.live = nil
        end)
        fontStr.ag = ag
        pool[idx] = fontStr
    end
    -- The plain and SPELL_ forms of an avoid share Blizzard's label.
    for idx = 1, #AVOID do
        local t = AVOID[idx]
        local labelText = _G["COMBAT_TEXT_" .. t]
        avoidLabel[t], avoidLabel["SPELL_" .. t] = labelText, labelText
    end
    ev = CreateFrame("Frame")
    ApplyPos()
    RegisterMover()
end

-- How far along its scroll a message is at `now`, as a fraction of the
-- distance: linear for Straight, the arc's height for Fountain (its control
-- points are evenly spaced in time), none for Static.
local function Travel(m, nowTime)
    local mode = S.anim
    if mode == "static" then
        return 0
    end
    local f = (nowTime - m.t0) / S.duration
    if f > 1 then
        f = 1
    end
    if mode ~= "fountain" then
        return f
    end
    local seg = f * #ARC
    local idx = math.floor(seg)
    if idx >= #ARC then
        return ARC[#ARC][2]
    end
    local from = idx > 0 and ARC[idx][2] or 0
    return from + (ARC[idx + 1][2] - from) * (seg - idx)
end

-- Stagger Hits: before a message of line height h starts at the anchor, push
-- its lane's live messages (the whole stream, or one side of the fountain) on
-- along the scroll until the one nearest the anchor sits clear of it. They all
-- move together, so the spacing holds, and the newest always starts at the
-- anchor; Static stacks the same way.
local function ClearLane(lane, hgt)
    local nowTime, dur, dy = GetTime(), S.duration, S.dy
    local s = dy < 0 and -1 or 1
    local near, nearD
    for idx = 1, POOL_SIZE do
        local m = pool[idx]
        if m.live and m.lane == lane and nowTime - m.t0 < dur then
            local d = s * (m.y0 + dy * Travel(m, nowTime))
            if not nearD or d < nearD then
                near, nearD = m, d
            end
        end
    end
    if not near then
        return
    end
    -- Scrolling up, the new message's top must clear the nearest one's bottom;
    -- scrolling down, the nearest one's top must clear the anchor.
    local need = (s > 0 and hgt or near.h) + LINE_GAP - nearD
    if need <= 0 then
        return
    end
    local shift = s * need
    for idx = 1, POOL_SIZE do
        local m = pool[idx]
        if m.live and m.lane == lane and nowTime - m.t0 < dur then
            m.y0 = m.y0 + shift
            m:SetPoint("BOTTOM", anchor, "BOTTOM", 0, m.y0)
        end
    end
end

-- Round-robin pool: a burst past POOL_SIZE restarts the oldest message.
local function Emit(fmt, value, c, crit)
    nextIdx = nextIdx % POOL_SIZE + 1
    local fontStr = pool[nextIdx]
    fontStr.ag:Stop()
    fontStr.live = nil
    local lane = 0
    if S.anim == "fountain" then
        -- Alternate sides, like Blizzard's fountain
        xDir = -xDir
        lane = xDir
        local rise, sy = S.rise, S.dy
        for jdx = 1, #ARC do
            fontStr.cps[jdx]:SetOffset(xDir * ARC[jdx][1] * rise, ARC[jdx][2] * sy)
        end
    end
    local hgt = (crit and S.critSize or S.size) * LINE_H
    if S.stagger then
        ClearLane(lane, hgt)
    end
    fontStr.t0, fontStr.y0, fontStr.h, fontStr.lane, fontStr.live = GetTime(), 0, hgt, lane, true
    fontStr:ClearAllPoints()
    fontStr:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
    -- A pooled string's font changes only with the settings or between a hit
    -- and a crit.
    local kind = crit and 2 or 1
    if fontStr.fontVer ~= S.fontVer or fontStr.fontKind ~= kind then
        fontStr.fontVer, fontStr.fontKind = S.fontVer, kind
        CludesUI.PrimeFontShadow(fontStr, S.shadow)
        fontStr:SetFont(S.font, crit and S.critSize or S.size, S.flags)
    end
    fontStr:SetTextColor(c.r, c.g, c.b)
    fontStr:SetFormattedText(fmt, value)
    fontStr:SetAlpha(1)
    fontStr:Show()
    fontStr.ag:Play()
end

-- Both formatters are C-side and accept secret numbers
local function FormatAmount(num)
    if S.abbreviate then
        return AbbreviateNumbers(num)
    end
    return BreakUpLargeNumbers(num)
end

local function SetUnit()
    C_CombatText.SetActiveUnit(UnitHasVehicleUI("player") and "vehicle" or "player")
end

local function OnEvent(_, evt, arg1, arg2)
    if evt == "COMBAT_TEXT_UPDATE" then
        -- data = amount (damage) or source name (heals); arg3 = heal amount
        local crit = DAMAGE[arg1]
        if crit ~= nil then
            if not S.damage then
                return
            end
            local payload = C_CombatText.GetCurrentEventInfo()
            Emit("-%s", FormatAmount(payload), S.damageColor, crit)
            return
        end
        crit = HEAL[arg1]
        if crit ~= nil then
            if not S.heal then
                return
            end
            local _, arg3 = C_CombatText.GetCurrentEventInfo()
            Emit("+%s", FormatAmount(arg3), S.healColor, crit)
            return
        end
        local labelText = S.avoid and avoidLabel[arg1]
        if labelText then
            Emit("%s", labelText, S.avoidColor, false)
        end
    elseif evt == "PLAYER_REGEN_DISABLED" then
        Emit("%s", _G.ENTERING_COMBAT or "+Combat", S.combatColor, false)
    elseif evt == "PLAYER_REGEN_ENABLED" then
        Emit("%s", _G.LEAVING_COMBAT or "-Combat", S.combatColor, false)
    elseif evt == "UNIT_ENTERED_VEHICLE" then
        C_CombatText.SetActiveUnit(arg2 and "vehicle" or "player")
    elseif evt == "UNIT_EXITING_VEHICLE" then
        C_CombatText.SetActiveUnit("player")
    elseif evt == "ADDON_LOADED" then
        if arg1 == "Blizzard_CombatText" and _G.CombatText then
            _G.CombatText:Hide()
            ev:UnregisterEvent("ADDON_LOADED")
        end
    end
end

-- Registers only the events the enabled categories need.
local function UpdateEvents()
    if S.damage or S.heal or S.avoid then
        ev:RegisterEvent("COMBAT_TEXT_UPDATE")
        ev:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
        ev:RegisterUnitEvent("UNIT_EXITING_VEHICLE", "player")
    else
        ev:UnregisterEvent("COMBAT_TEXT_UPDATE")
        ev:UnregisterEvent("UNIT_ENTERED_VEHICLE")
        ev:UnregisterEvent("UNIT_EXITING_VEHICLE")
    end
    if S.combat then
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        ev:UnregisterEvent("PLAYER_REGEN_DISABLED")
        ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function Refresh()
    local wanted = Enabled()
    if wanted == enabled then
        if wanted then
            ReadSettings()
            ApplyAnim()
            UpdateEvents()
        end
        return
    end
    enabled = wanted
    if wanted then
        if not anchor then
            Build()
        end
        ReadSettings()
        ApplyAnim()
        anchor:Show()
        ev:SetScript("OnEvent", OnEvent)
        UpdateEvents()
        SetUnit()
        if _G.CombatText then
            _G.CombatText:Hide()
        else
            ev:RegisterEvent("ADDON_LOADED")
        end
    else
        ev:UnregisterAllEvents()
        anchor:Hide()
        if _G.CombatText then
            _G.CombatText:Show()
        end
    end
end

mod.SCT_Refresh = Refresh
mod.SCT_Get = Get
CludesUI._applySelfCombatText = Refresh -- RefreshAllAddons (profile swaps)

function mod.SCT_Set(k, val)
    Settings()[k] = val
    Refresh()
end

-- QoL page reset: every setting back to its default, the anchor link dropped.
function mod.SCT_Reset()
    Profile().selfCombatText = nil
    if CludesUIDB.unlockAnchors then
        CludesUIDB.unlockAnchors[UNLOCK_KEY] = nil
    end
    Refresh()
    ApplyPos()
end
