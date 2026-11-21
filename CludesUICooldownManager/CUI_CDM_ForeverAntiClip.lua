if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_ForeverAntiClip.lua -- WoW FOREVER ONLY: the Anti-Clip Glow.
--
--  Vanilla auras carry no time over on a refresh: a DoT cast again before it
--  runs out loses the ticks it had left, and Blizzard never opens a pandemic
--  window for it. So on Forever a bar's Pandemic Glow is the anti-clip glow: an
--  aura lights while casting its spell as your next action -- after your
--  current cast or channel and the GCD -- would land it at or after the running
--  one's expiry. The bars keep their Pandemic Glow keys and drawing (icons: the
--  buff ticker in CUI_CDM_HookViewers.lua; Tracking Bars: CUI_CDM_BuffBarTick.lua);
--  only the trigger lives here, reached through the nil-guarded ns.CDM_AntiClip,
--  ns.CDM_AntiClipPlaced (after every reanchor), ns.CDM_AntiClipSync (end of
--  every full rebuild) and ns.CDM_AntiClipBars (the Tracking Bars build).
--
--  The expiry is the item's own, read by ns.ReadAuraExpiration (Also Show Below
--  N Seconds reads it the same way): a time that reads secret lights nothing.
--  The cast time is the tracked spell's own (talents included), so an instant
--  lights only once the aura would run out before you are free, and nothing
--  lights while you are casting the spell itself. An input that cannot be read
--  counts as "free now" or "instant", which can only light the glow later.
--
--  Event-driven, probing the delta: the player's cast events say when the
--  current cast and the GCD end, and on those edges (and on cast-time changes
--  and the one idle-wait timer) only the icons the buff ticker last drew are
--  re-checked, the ticker woken only when one of them flips. An item's own aura
--  edges (a post-hook on CheckSetPandemicAlertTriggerTime, which Blizzard calls
--  on every application, refresh and removal) re-check it the same way, and
--  every reanchor wakes the ticker for the icons it placed.
--  Tracking Bars read the verdict on their own tick. Nothing is registered while
--  no bar uses the glow, and the aura-edge hooks then return at once.
-------------------------------------------------------------------------------
local _, mod = ...
-- WoW Forever (ns.CDM_ANTI_CLIP, CludesUICooldownManager.lua).
if not mod.CDM_ANTI_CLIP then return end

local GetTime = GetTime
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local PlainString = CludesUI.PlainString
local ReadExpiration = mod.ReadAuraExpiration
local GCD_SPELL = 61304
local HUGE = math.huge
local EMPTY = {}

local armed = false
local wantIcons, wantBars = false, false
local castEnd, gcdEnd = 0, 0 -- GetTime() at which the current cast / GCD ends
local castName -- the spell being cast or channelled (plain reads)
local castTimes = {} -- [spellID] = cast time in seconds (plain reads)
local nameList = {} -- [spellID] = spell name (plain reads)
local status = setmetatable({}, { __mode = "k" }) -- [icon item] = its last drawn verdict
local hooked = setmetatable({}, { __mode = "k" })
local nextWake = HUGE -- the earliest pending idle wake
local ev = mod.TakeShell()

local function WakeBuffTicker()
    mod._btDirty = true
    if mod.ArmBuffTicker then mod.ArmBuffTicker() end
end

local function SpellName(spellRef)
    local num = nameList[spellRef]
    if num then return num end
    num = PlainString(C_Spell.GetSpellName(spellRef))
    if num then nameList[spellRef] = num end
    return num
end

-- Cast time in seconds of a spell as the client reads it for you now (0 for an
-- instant). Cached; dropped when spells, talents, gear or haste change.
local function CastTime(spellRef)
    local c = castTimes[spellRef]
    if c then return c end
    local details = C_Spell.GetSpellInfo(spellRef)
    local ms = details and details.castTime
    if type(ms) ~= "number" or issecretvalue(ms) then return 0 end
    c = ms > 0 and ms / 1000 or 0
    castTimes[spellRef] = c
    return c
end

-- When the current cast or channel ends (0 while none) and which spell it is.
local function ReadCast()
    local _, _, _, _, e, _, _, _, spellRef = UnitCastingInfo("player")
    if type(e) ~= "number" or issecretvalue(e) then
        _, _, _, _, e, _, _, spellRef = UnitChannelInfo("player")
    end
    if type(e) == "number" and not issecretvalue(e) then
        castEnd = e / 1000
        castName = (type(spellRef) == "number" and not issecretvalue(spellRef)) and SpellName(spellRef) or nil
    else
        castEnd, castName = 0, nil
    end
end

-- When the running GCD ends; 0 while none runs (or it reads secret).
local function ReadGCD()
    local cd = C_Spell.GetSpellCooldown(GCD_SPELL)
    local s, skinData = cd and cd.startTime, cd and cd.duration
    if
        type(s) == "number"
        and type(skinData) == "number"
        and not issecretvalue(s)
        and not issecretvalue(skinData)
        and skinData > 0
    then
        gcdEnd = s + skinData
    else
        gcdEnd = 0
    end
end

-- The verdict for one aura item now: true while casting its spell as your next
-- action would land it at or after the running aura's expiry. A false verdict
-- also returns the moment an idle wait would turn it on.
local function Evaluate(widget, nowTime)
    local exp, rate = ReadExpiration(widget)
    if not exp then return false end
    -- The tracked spell is the one you cast (an aura's own id can differ: retail
    -- Immolate casts 348 and applies 157736); the aura's id stands in until resolved.
    local fc = mod._ecmeFC[widget]
    local spellRef = fc and fc.resolvedSid
    if type(spellRef) ~= "number" or spellRef <= 0 then
        -- A totem item's expiry came from its totem data, so the cached aura
        -- is unchecked here and may be a secret table (no index on one).
        local skinData = widget.auraDataCached
        spellRef = nil
        if not issecretvalue(skinData) and skinData then spellRef = skinData.spellId end
    end
    local plain = type(spellRef) == "number" and not issecretvalue(spellRef)
    -- Casting the spell itself refreshes the aura: nothing to queue.
    if castName and plain and castName == SpellName(spellRef) then return false end
    local c = plain and CastTime(spellRef) or 0
    local free = nowTime
    if castEnd > free then free = castEnd end
    if gcdEnd > free then free = gcdEnd end
    if (exp - nowTime) / rate <= (free - nowTime) + c then return true end
    -- Free from `free` on, it turns on once the aura's time left fits the cast.
    local t = exp - c * rate
    if t < free then t = free end
    return false, t
end

local Probe

-- A wake already superseded by an earlier one that ran stays quiet.
local function WakeDue()
    if GetTime() + 0.01 < nextWake then return end
    nextWake = HUGE
    Probe()
end

local function Schedule(t, nowTime)
    if t < nextWake then
        nextWake = t
        C_Timer.After(t - nowTime + 0.02, WakeDue)
    end
end

-- Re-check only the icons the buff ticker last drew; wake it only when one of
-- them flips (the ticker redraws it and stores the new verdict).
Probe = function()
    local nowTime = GetTime()
    local flipped = false
    for widget, was in pairs(status) do
        if widget:IsShown() then
            local on, t = Evaluate(widget, nowTime)
            if on ~= was then flipped = true end
            if t then Schedule(t, nowTime) end
        else
            status[widget] = nil
        end
    end
    if flipped then WakeBuffTicker() end
end

-- An item's aura changed: re-check the icons drawn, or let the ticker draw one
-- it has not drawn yet.
local function OnAuraEdge(widget)
    if not armed then return end
    if status[widget] == nil then
        WakeBuffTicker()
    else
        Probe()
    end
end

-- After every reanchor (icons joined or left the bars, an aura's first
-- activation among them): let the ticker draw the icons it has not drawn yet.
function mod.CDM_AntiClipPlaced()
    if armed then WakeBuffTicker() end
end

-- The GCD a cast starts can land a moment after the cast's own event.
local function Reread()
    local wasCast, wasGcd = castEnd, gcdEnd
    ReadCast()
    ReadGCD()
    if castEnd ~= wasCast or gcdEnd ~= wasGcd then Probe() end
end

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
}
-- Everything that can change a spell's cast time: spells, talents (Forever's
-- run on traits), gear and haste.
local CAST_TIME_EVENTS = {
    "SPELLS_CHANGED",
    "TRAIT_CONFIG_UPDATED",
    "CHARACTER_POINTS_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED",
}

ev:SetScript("OnEvent", function(_, evt)
    if
        evt == "UNIT_SPELL_HASTE"
        or evt == "SPELLS_CHANGED"
        or evt == "TRAIT_CONFIG_UPDATED"
        or evt == "CHARACTER_POINTS_CHANGED"
        or evt == "PLAYER_EQUIPMENT_CHANGED"
    then
        wipe(castTimes)
    else
        ReadCast()
        ReadGCD()
        if
            gcdEnd <= GetTime()
            and (
                evt == "UNIT_SPELLCAST_START"
                or evt == "UNIT_SPELLCAST_SUCCEEDED"
                or evt == "UNIT_SPELLCAST_CHANNEL_START"
            )
        then
            C_Timer.After(0.05, Reread)
        end
    end
    Probe()
end)

local function SetArmed(wanted)
    if wanted == armed then return end
    armed = wanted
    if wanted then
        for index = 1, #CAST_EVENTS do
            ev:RegisterUnitEvent(CAST_EVENTS[index], "player")
        end
        for index = 1, #CAST_TIME_EVENTS do
            ev:RegisterEvent(CAST_TIME_EVENTS[index])
        end
        ev:RegisterUnitEvent("UNIT_SPELL_HASTE", "player")
        ReadCast()
        ReadGCD()
    else
        ev:UnregisterAllEvents()
        castEnd, gcdEnd, castName = 0, 0, nil
        wipe(castTimes)
        wipe(status)
    end
    -- The next pass lights or takes down the glows under the new state.
    WakeBuffTicker()
end

-- End of every full rebuild (options, profile and spec swaps): does any enabled
-- bar draw the glow? Blizzard Default (-1) has no anti-clip look, so it draws
-- none. The glows are drawn again under the new settings.
function mod.CDM_AntiClipSync()
    local p = mod.ECME and mod.ECME.db and mod.ECME.db.profile
    local barList = p and p.cdmBars and p.cdmBars.bars
    local wanted = false
    for _, edge in ipairs(barList or EMPTY) do
        if edge.enabled and edge.pandemicGlow and (edge.pandemicGlowStyle or 1) ~= -1 then
            wanted = true
            break
        end
    end
    wantIcons = wanted
    wipe(status)
    if armed == (wantIcons or wantBars) then
        if armed then WakeBuffTicker() end
    else
        SetArmed(wantIcons or wantBars)
    end
end

-- The Tracking Bars build: does any enabled Tracking Bar draw the glow?
function mod.CDM_AntiClipBars(wanted)
    wantBars = wanted and true or false
    SetArmed(wantIcons or wantBars)
end

-- The verdict for one Blizzard Cooldown Manager aura item. wake: the buff
-- ticker's call (icons), which hooks the item's aura edges, stores the verdict
-- the cast edges re-check and asks for a wake at the moment an idle wait would
-- turn it on; the Tracking Bars tick needs none of that.
function mod.CDM_AntiClip(widget, wake)
    if not armed then return false end
    local nowTime = GetTime()
    local on, t = Evaluate(widget, nowTime)
    if wake then
        if not hooked[widget] and widget.CheckSetPandemicAlertTriggerTime then
            hooked[widget] = true
            hooksecurefunc(widget, "CheckSetPandemicAlertTriggerTime", OnAuraEdge)
        end
        status[widget] = on
        if t then Schedule(t, nowTime) end
    end
    return on
end
