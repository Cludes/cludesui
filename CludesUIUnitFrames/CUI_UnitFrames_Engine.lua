if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_Engine.lua
--
--  The unit-frame update engine: event routing and repaint scheduling for the
--  single-unit frames (player/target/focus/pet/tot/fot/boss1-5). Owns NOTHING
--  visual -- painters live in the other CUI_UnitFrames_*.lua files and are
--  registered per channel; this file decides only WHO gets painted and WHEN.
--
--  Design rules:
--  - One tracker frame per unit token, created once, events registered via
--    RegisterUnitEvent so the client filters delivery C-side. Tokens are fixed
--    for the session; nothing re-registers except an opt-in channel
--    (Engine.SetChannelOn), whose events exist only while a setting wants it.
--  - Vehicle handling is done at REGISTRATION, not remap time: the player
--    frame's tracker registers every unit event for BOTH "player" and
--    "vehicle", the pet frame's for both "pet" and "player". Painters read
--    frame._cuiUnit (the live token) at paint time, so a vehicle swap needs no
--    event surgery at all.
--  - targettarget/focustarget have no unit events of their own; ONE shared
--    0.5s ticker repaints them (value channels every tick, identity channels
--    only when the GUID actually changed), and the parent unit's UNIT_TARGET
--    (the target's or focus's own target changing: a mob turning on someone
--    else, a tank swap) repaints them at once, so the occupant never waits
--    out a tick. The ticker frame is hidden -- and therefore completely idle
--    -- whenever neither frame is shown.
--  - Same-frame dedupe: each (frame, channel) paint is stamped with a global
--    generation + GetTime pair; stacked triggers inside one frame collapse to
--    one paint (heal prediction adds one trailing next-frame paint for a
--    deduped repeat, see predFlush). The player's power value channel is
--    never stamped: its events only mark the frame, and one flush pass
--    paints it (see valFlush). The text channel is not stamped either: its
--    painter collapses per zone (PaintText in CUI_UnitFrames_Text.lua).
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local CludesUI = _G.CludesUI
if not CludesUI then
    return
end

local issecretvalue = _G.issecretvalue
local UnitExists, UnitGUID, GetTime = UnitExists, UnitGUID, GetTime
local CreateFrame = CreateFrame

local Engine = {}
ns.Engine = Engine

-------------------------------------------------------------------------------
--  Painter registry: channel -> fn(frame, unit, event). Registered once by the
--  owning file. A channel with no painter is simply never scheduled.
-------------------------------------------------------------------------------
local painters = {}

function Engine.SetPainter(channelling, func)
    painters[channelling] = func
end

-------------------------------------------------------------------------------
--  Channel -> unit events. This mirrors the exact event set the old element
--  wiring listened to, so update timing is indistinguishable to the user.
--  (health carries connection/faction; text rides health+power+name/level;
--  absorb covers both absorb kinds; incoming heals are the opt-in healpred
--  channel, OPTIN_EVENTS below.)
-------------------------------------------------------------------------------
local CHANNEL_EVENTS = {
    -- UNIT_MAX_HEALTH_MODIFIERS_CHANGED rides health/text: modifier changes can
    -- move the value and effective max with no UNIT_HEALTH/UNIT_MAXHEALTH behind
    -- them (Blizzard's own unit frames repaint health from this event).
    health = {
        "UNIT_HEALTH",
        "UNIT_MAXHEALTH",
        "UNIT_CONNECTION",
        "UNIT_FACTION",
        "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
    },
    power = {
        "UNIT_POWER_UPDATE",
        "UNIT_MAXPOWER",
        "UNIT_DISPLAYPOWER",
        "UNIT_POWER_BAR_SHOW",
        "UNIT_POWER_BAR_HIDE",
        "UNIT_CONNECTION",
    },
    -- UNIT_AURA deliberately absent here too: absorb VALUE changes already
    -- ride the two absorb events below, so the long-form Absorb / Heal Absorb
    -- text zones only go stale on the no-event timer-expiry class -- and the
    -- armed belt's disarm edge (ns.UF_AbDisarm) recomposes text once at
    -- exactly that moment. (The "Short" variants ride the Override's
    -- _absGate lockstep instead, which the absorb channel already covers.)
    -- UNIT_TARGET: the unit's OWN target changing -- only trigger for
    -- "Name > Target" content, otherwise relies on an unrelated event
    -- (health/power tick) to happen to fire around the same time.
    text = {
        "UNIT_HEALTH",
        "UNIT_MAXHEALTH",
        "UNIT_POWER_UPDATE",
        "UNIT_MAXPOWER",
        "UNIT_DISPLAYPOWER",
        "UNIT_NAME_UPDATE",
        "UNIT_LEVEL",
        "UNIT_CONNECTION",
        "UNIT_FACTION",
        "UNIT_ABSORB_AMOUNT_CHANGED",
        "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
        "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
        "UNIT_TARGET",
    },
    -- (UNIT_HEAL_PREDICTION deliberately absent: the absorb painter never
    -- renders incoming heals; they are the opt-in healpred channel, whose
    -- events are registered only while a frame shows them.)
    -- UNIT_AURA deliberately absent (Blizzard parity): the timer-expiry
    -- shield with no event at all (VDH Infernal Strike field class) is
    -- covered by the armed-frames belt in the main file (ns.UF_AbArm), not
    -- by riding the chattiest event in the game. Raid Frames uses the same
    -- belt design. UNIT_HEALTH deliberately absent too: the absorb painter
    -- reads amounts/max/sizes but never current health -- the overlays are
    -- clip-anchored to the health texture edge, which the client moves for
    -- free (Blizzard's CUF needs health-driven prediction repaints only
    -- because its bars compute widths in Lua). Max range changes still ride
    -- UNIT_MAXHEALTH; the event-less shield clear rides the belt.
    absorb = {
        "UNIT_MAXHEALTH",
        "UNIT_ABSORB_AMOUNT_CHANGED",
        "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
        "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
    },
    portrait = { "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_CONNECTION" },
}

-- Opt-in channels (Engine.SetChannelOn): not attached with the frame, routed
-- only while a setting turns them on. healpred = incoming heals: its own
-- event plus the range and heal-absorb edges that change what it draws. The
-- calculator clamps to maximum health, so current health is not an input.
-- absglow = the Blizzard Glow Line's overshield flip: whether the shield
-- exceeds missing health moves with current health too, so while a frame
-- draws the line in a placement that reads it, health changes repaint the flip.
-- powerval = the player's power value: UNIT_POWER_FREQUENT fires on every
-- power change (UNIT_POWER_UPDATE is throttled), and moves only the bar value
-- and the power text through the value flush below; the power channel keeps
-- the full paint on its own events.
local OPTIN_EVENTS = {
    healpred = {
        "UNIT_HEAL_PREDICTION",
        "UNIT_MAXHEALTH",
        "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
        "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
    },
    absglow = { "UNIT_HEALTH" },
    maxhp = { "UNIT_MAX_HEALTH_MODIFIERS_CHANGED", "UNIT_MAXHEALTH" },
    powerval = { "UNIT_POWER_FREQUENT" },
}

-- Events consumed by the castbar channel; routed raw (event identity matters
-- to the painter), never deduped -- a STOP and a START in one frame are both
-- real.
local CASTBAR_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP",
}

-------------------------------------------------------------------------------
--  Castbar driver. Owns the cast state machine for frame.Castbar and calls
--  the bar's Post* hooks with the same shapes the old element wiring used, so
--  every existing hook runs unchanged. The bar itself stays hidden while
--  idle, and its OnUpdate only exists to serve the time text and the
--  post-interrupt hold -- the fill animation is engine-driven through
--  SetTimerDuration (secret-safe by construction; Lua never reads the clock).
--
--  Event payload note: 12.1 delivers the cast identifier used for
--  cross-checking at the FOURTH event argument (and interrupt/empower stops
--  carry their extras before it); the positional reads below mirror the
--  field-proven live behavior exactly.
-------------------------------------------------------------------------------
do
    local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
    local FALLBACK_ICON = 136243

    local function ResetCastState(part)
        part.casting, part.channeling, part.empowering = nil, nil, nil
        part.notInterruptible, part.spellID, part.castID = nil, nil, nil
        part.spellName = nil
        part._craftExtra = nil
        -- Empower stage pips outlive the cast otherwise (the old element
        -- wiring hid them in its reset).
        if part.Pips then
            for _, pip in next, part.Pips do
                pip:Hide()
            end
        end
    end

    -- The time text shows tenths, so it repaints only when the shown tenth
    -- can have changed, not every frame. A readable remaining time waits
    -- exactly until its shown value rounds down to the next tenth; a secret
    -- one (another unit's cast in instanced combat) cannot be read, so it
    -- repaints on a fixed 0.05 s grid, two passes per tenth, so no tenth is
    -- skipped. _cuiTimeWait is the time left until the next repaint;
    -- StartCast and UpdateCast zero it so a new or changed cast paints on
    -- its next frame.
    local floor = math.floor
    local SECRET_TIME_STEP = 0.05

    local function CastOnUpdate(self, elapsed)
        if self.casting or self.channeling or self.empowering then
            local waitTime = (self._cuiTimeWait or 0) - elapsed
            if waitTime > 0 then
                self._cuiTimeWait = waitTime
                return
            end
            -- Stay on the grid (a late frame shortens the next wait); start
            -- over after a hitch longer than one step.
            waitTime = waitTime + SECRET_TIME_STEP
            if waitTime <= 0 then
                waitTime = SECRET_TIME_STEP
            end
            if self.Time then
                local durationObject = self:GetTimerDuration()
                if durationObject then
                    local rem = durationObject:GetRemainingDuration()
                    if (self.delay or 0) ~= 0 then
                        if self.CustomDelayText then
                            self:CustomDelayText(durationObject)
                        else
                            self.Time:SetFormattedText(
                                "%.1f|cffff0000%s%.2f|r",
                                rem,
                                self.channeling and "-" or "+",
                                self.delay
                            )
                        end
                    elseif self.CustomTimeText then
                        self:CustomTimeText(durationObject)
                    else
                        self.Time:SetFormattedText("%.1f", rem)
                    end
                    if not issecretvalue(rem) then
                        waitTime = rem - (floor(rem * 10 + 0.5) - 0.5) / 10
                    end
                end
            end
            self._cuiTimeWait = waitTime
        elseif (self.holdTime or 0) > 0 then
            self.holdTime = self.holdTime - elapsed
        else
            ResetCastState(self)
            self:Hide()
        end
    end

    -- Full (re)derivation of the current cast: real cast-start events and
    -- every identity repaint (target swap, show, force) land here, matching
    -- the old full-update behavior on those paths.
    local function StartCast(widget, part, unitId, evt)
        local fillDirection = Enum.StatusBarTimerDirection.ElapsedTime
        local castDur
        local name, textValue, texture, castStart, endTime, isTradeSkill, _, notInterruptible, spellId, castId =
            UnitCastingInfo(unitId)
        if name then
            part.casting = true
            part.channeling, part.empowering = nil, nil
            castDur = UnitCastingDuration(unitId)
        else
            local isEmpowered
            name, textValue, texture, castStart, endTime, isTradeSkill, notInterruptible, spellId, isEmpowered, _, castId =
                UnitChannelInfo(unitId)
            if isEmpowered then
                part.empowering = true
                part.casting, part.channeling = nil, nil
                castDur = UnitEmpoweredChannelDuration(unitId)
            else
                part.channeling = true
                part.casting, part.empowering = nil, nil
                castDur = UnitChannelDuration(unitId)
                fillDirection = Enum.StatusBarTimerDirection.RemainingTime
            end
        end

        if not name or (isTradeSkill and part.hideTradeSkills) then
            -- A target swap during the post-interrupt hold keeps the hold on
            -- screen; anything else clears the bar outright.
            if not (evt == "PLAYER_TARGET_CHANGED" and (part.holdTime or 0) > 0) then
                ResetCastState(part)
                part:Hide()
            end
            return
        end

        textValue = CludesUI.CleanCastName(textValue)

        part.delay = 0
        part.holdTime = 0
        part._cuiTimeWait = 0
        part.notInterruptible = notInterruptible
        part.castID = castId
        part.spellID = spellId
        part.spellName = textValue

        if unitId == "player" then
            -- Cast clock endpoints are only readable for the player.
            part.startTime = castStart / 1000
            if part.empowering then
                part.endTime = (endTime + GetUnitEmpowerHoldAtMaxTime(unitId)) / 1000
            else
                part.endTime = endTime / 1000
            end
        end

        part:SetTimerDuration(castDur, part.smoothing, fillDirection)

        if part.Icon then
            part.Icon:SetTexture(texture or FALLBACK_ICON)
        end
        if part.Spark then
            part.Spark:Show()
        end
        -- Full Craft Time (player only): batch countdown and " (n/N)" count.
        if unitId == "player" and (part._fullCraft or part._craftExtra) then
            CludesUI.SetCraftBatch(
                part,
                part._fullCraft and part.casting and isTradeSkill,
                spellId,
                castId,
                (endTime - castStart) / 1000
            )
        end
        if part.Text then
            part.Text:SetText(
                part._craftExtra and (textValue .. part._craftCountSuffix) or textValue
            )
        end
        if part.Time then
            part.Time:SetText()
        end

        local safeZone = part.SafeZone
        if safeZone and unitId == "player" then
            local isHoriz = part:GetOrientation() == "HORIZONTAL"
            safeZone:ClearAllPoints()
            safeZone:SetPoint(isHoriz and "TOP" or "LEFT")
            safeZone:SetPoint(isHoriz and "BOTTOM" or "RIGHT")
            if part.channeling then
                safeZone:SetPoint(
                    part:GetReverseFill() and (isHoriz and "RIGHT" or "TOP")
                        or (isHoriz and "LEFT" or "BOTTOM")
                )
            else
                safeZone:SetPoint(
                    part:GetReverseFill() and (isHoriz and "LEFT" or "BOTTOM")
                        or (isHoriz and "RIGHT" or "TOP")
                )
            end
            local zoneEnd = endTime
            if part.empowering then
                zoneEnd = zoneEnd + GetUnitEmpowerHoldAtMaxTime(unitId)
            end
            local ratio = (select(4, GetNetStats())) / (zoneEnd - castStart)
            if ratio > 1 then
                ratio = 1
            end
            safeZone[isHoriz and "SetWidth" or "SetHeight"](
                safeZone,
                part[isHoriz and "GetWidth" or "GetHeight"](part) * ratio
            )
        end

        if part.empowering and part.UpdatePips then
            part:UpdatePips(UnitEmpoweredStagePercentages(unitId))
        end

        if part.PostCastStart then
            part:PostCastStart(unitId)
        end
        part:Show()
    end

    local function UpdateCast(widget, part, unitId, evt, castId)
        if not part:IsShown() or not castId or part.castID ~= castId then
            return
        end
        local fillDirection = Enum.StatusBarTimerDirection.ElapsedTime
        local castDur, name, castStart, _
        if evt == "UNIT_SPELLCAST_DELAYED" then
            name, _, _, castStart = UnitCastingInfo(unitId)
            castDur = UnitCastingDuration(unitId)
        else
            name, _, _, castStart = UnitChannelInfo(unitId)
            if evt == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
                castDur = UnitEmpoweredChannelDuration(unitId)
            else
                castDur = UnitChannelDuration(unitId)
                fillDirection = Enum.StatusBarTimerDirection.RemainingTime
            end
        end
        if not name then
            return
        end
        if unitId == "player" then
            -- Delay accumulates only for the player (readable clock).
            castStart = castStart / 1000
            local delta
            if part.channeling then
                delta = part.startTime - castStart
            else
                delta = castStart - part.startTime
            end
            if delta < 0 then
                delta = 0
            end
            part.delay = (part.delay or 0) + delta
            -- The next pushback is measured from this one's start, so each
            -- adds only its own delay.
            part.startTime = castStart
        end
        part._cuiTimeWait = 0
        part:SetTimerDuration(castDur, part.smoothing, fillDirection)
        if part.PostCastUpdate then
            part:PostCastUpdate(unitId)
        end
    end

    local function StopCast(widget, part, unitId, evt, a, b, c)
        local castId, interrupter, empowerComplete
        if evt == "UNIT_SPELLCAST_STOP" then
            castId = a
        elseif evt == "UNIT_SPELLCAST_EMPOWER_STOP" then
            empowerComplete, interrupter, castId = a, b, c
        else -- UNIT_SPELLCAST_CHANNEL_STOP
            interrupter, castId = a, b
        end
        if not part:IsShown() or not castId or part.castID ~= castId then
            return
        end
        if part.Spark then
            part.Spark:Hide()
        end
        if interrupter then
            if part.Text then
                part.Text:SetText(INTERRUPTED)
            end
            part.holdTime = part.timeToHold or 0
            part:SetMinMaxValues(0, 1)
            part:SetValue(1)
            if part.PostCastInterrupted then
                part:PostCastInterrupted(unitId, interrupter)
            end
        else
            if part.PostCastStop then
                part:PostCastStop(unitId, empowerComplete)
            end
        end
        ResetCastState(part)
    end

    local function FailCast(widget, part, unitId, evt, a, b)
        local castId, interrupter
        if evt == "UNIT_SPELLCAST_INTERRUPTED" then
            interrupter, castId = a, b
        else -- UNIT_SPELLCAST_FAILED
            castId = a
        end
        if not part:IsShown() or not castId or part.castID ~= castId then
            return
        end
        if part.Text then
            part.Text:SetText(evt == "UNIT_SPELLCAST_FAILED" and FAILED or INTERRUPTED)
        end
        if part.Spark then
            part.Spark:Hide()
        end
        part.holdTime = part.timeToHold or 0
        part:SetMinMaxValues(0, 1)
        part:SetValue(1)
        if interrupter then
            if part.PostCastInterrupted then
                part:PostCastInterrupted(unitId, interrupter)
            end
        else
            if part.PostCastFail then
                part:PostCastFail(unitId)
            end
        end
        ResetCastState(part)
    end

    -- The castbar channel painter. Real events arrive as
    -- (frame, unit, event, eventUnit, e2, e3, e4, e5, e6): the cast
    -- identifier the handlers cross-check sits at event argument FOUR, with
    -- the interrupt/empower extras leading it -- the positions the live
    -- behavior is proven against. Identity repaints arrive with pseudo-event
    -- names and re-derive the current cast in full.
    local function CastbarPainter(widget, unitId, evt, _, e2, e3, e4, e5, e6)
        local part = widget.Castbar
        if not part then
            return
        end
        if not Engine.ElementOn(widget, "Castbar") then
            return
        end
        if not part._cuiCastDriver then
            part._cuiCastDriver = true
            -- One-time per-element state the old wiring seeded on enable:
            -- the pip registry (the module's UpdatePips indexes it, and an
            -- empower cast crashed StartCast before PostCastStart without
            -- it -- taking the icon/text/target updates down with it).
            part.Pips = part.Pips or {}
            part:SetScript("OnUpdate", CastOnUpdate)
        end
        if
            evt == "UNIT_SPELLCAST_START"
            or evt == "UNIT_SPELLCAST_CHANNEL_START"
            or evt == "UNIT_SPELLCAST_EMPOWER_START"
        then
            StartCast(widget, part, unitId, evt)
        elseif
            evt == "UNIT_SPELLCAST_DELAYED"
            or evt == "UNIT_SPELLCAST_CHANNEL_UPDATE"
            or evt == "UNIT_SPELLCAST_EMPOWER_UPDATE"
        then
            UpdateCast(widget, part, unitId, evt, e4)
        elseif
            evt == "UNIT_SPELLCAST_STOP"
            or evt == "UNIT_SPELLCAST_CHANNEL_STOP"
            or evt == "UNIT_SPELLCAST_EMPOWER_STOP"
        then
            StopCast(widget, part, unitId, evt, e4, e5, e6)
        elseif evt == "UNIT_SPELLCAST_FAILED" or evt == "UNIT_SPELLCAST_INTERRUPTED" then
            FailCast(widget, part, unitId, evt, e4, e5)
        elseif evt == "UNIT_SPELLCAST_INTERRUPTIBLE" or evt == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            if not part:IsShown() then
                return
            end
            part.notInterruptible = evt == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
            if part.PostCastInterruptible then
                part:PostCastInterruptible(unitId)
            end
        else
            -- Pseudo-event (Show/ForceUpdate/target swap): full re-derive.
            StartCast(widget, part, unitId, evt)
        end
    end
    Engine.SetPainter("castbar", CastbarPainter)
end

-------------------------------------------------------------------------------
--  Attached frames + trackers
-------------------------------------------------------------------------------
local attached = {} -- frame -> { unit = token, channels = { name, ... } }
local trackers = {} -- primary token -> tracker frame
local unitFrames = {} -- primary token -> frame (1:1 for our layout)

-- Which secondary token shares a frame's events (vehicle design, see header).
local SECONDARY_TOKEN = { player = "vehicle", pet = "player" }

-- Paint stamping: one generation per hardware frame is enough to collapse
-- stacked same-frame triggers without ever suppressing a later real change.
local paintGen = 0
local lastGenTime = 0

local function Bump()
    local nowTime = GetTime()
    if nowTime ~= lastGenTime then
        paintGen = paintGen + 1
        lastGenTime = nowTime
    end
    return paintGen
end

-- Identity edges are never eaten by a same-frame value paint: painters may
-- skip identity-only work (the text painter's name/level zones) on value
-- events, so an identity event landing after a value paint in the same
-- hardware frame must still reach the painter (RepaintAll wipes the stamps
-- for the same reason).
local IDENTITY_EVENTS = {
    UNIT_NAME_UPDATE = true,
    UNIT_LEVEL = true,
    UNIT_CONNECTION = true,
    UNIT_FACTION = true,
}

-- Heal prediction's trailing flush: a same-frame repeat can carry state the
-- first paint could not see (a heal landing and another cast starting, or a
-- cast and a heal absorb in one frame), so a deduped repeat marks the frame
-- and ONE next-frame pass repaints it from settled values. Idle while hidden.
local predPending = {} -- frame -> true
local predFlush = CreateFrame("Frame")
predFlush:Hide()
predFlush:SetScript("OnUpdate", function(self)
    self:Hide()
    local func = painters.healpred
    for widget in pairs(predPending) do
        predPending[widget] = nil
        if func and widget:IsShown() then
            func(widget, widget._cuiUnit, "Flush")
        end
    end
end)

-- Power value flush (the powerval channel): a matching UNIT_POWER_FREQUENT
-- only marks its frame, and ONE pass after the frame's events have landed
-- paints each marked frame from the live value, so a burst costs one value
-- paint per rendered frame and the last change always reaches the bar. Its
-- painter has its own slot (Engine.SetValuePainter), so the stamped repaints
-- (RepaintAll) skip the channel: the full power and text paints cover it
-- there. Idle while hidden.
local valuePainter
local valPending = {} -- frame -> true
local valFlush = CreateFrame("Frame")
valFlush:Hide()
valFlush:SetScript("OnUpdate", function(self)
    self:Hide()
    local func = valuePainter
    for widget in pairs(valPending) do
        valPending[widget] = nil
        if func and widget:IsShown() then
            func(widget, widget._cuiUnit)
        end
    end
end)

function Engine.SetValuePainter(func)
    valuePainter = func
end

local function Paint(widget, channelling, evt)
    local func = painters[channelling]
    if not func then
        return
    end
    local gen = Bump()
    local stamps = widget._cuiPaintStamps
    if not stamps then
        stamps = {}
        widget._cuiPaintStamps = stamps
    end
    -- Castbar events are never deduped: each event name is a distinct edge.
    -- The text painter collapses per zone instead (a value event repaints only
    -- the zones reading that value, so a channel stamp would eat the others).
    if channelling ~= "castbar" and channelling ~= "text" and not IDENTITY_EVENTS[evt] then
        local key = stamps[channelling]
        if key == gen then
            if channelling == "healpred" then
                predPending[widget] = true
                predFlush:Show()
            end
            return
        end
        stamps[channelling] = gen
    end
    func(widget, widget._cuiUnit, evt)
end

-- Full repaint of every attached channel on one frame (identity changes:
-- target swap, vehicle flip, PEW, explicit refresh from settings code).
function Engine.RepaintAll(widget, evt)
    local details = attached[widget]
    if not details then
        return
    end
    -- Clear stamps first: an identity repaint must never be eaten by a
    -- value paint that happened earlier in this same hardware frame.
    if widget._cuiPaintStamps then
        wipe(widget._cuiPaintStamps)
    end
    for i = 1, #details.channels do
        Paint(widget, details.channels[i], evt or "ForceUpdate")
    end
end

-- Suite-wide repaint (colors changed, profile switched). Replaces the old
-- library-object walk. Exported for the parent's color chokepoint.
function Engine.ForceAll(evt)
    for widget in pairs(attached) do
        Engine.RepaintAll(widget, evt or "ForceUpdate")
    end
end
CludesUI._UFEngineForceAll = Engine.ForceAll

-------------------------------------------------------------------------------
--  Event routing
-------------------------------------------------------------------------------
-- A max-health change lands in two steps: the max moves first, the value
-- follows. A paint driven by UNIT_MAXHEALTH runs between them and renders the
-- new max against the pre-change value, same-frame dedupe drops the correcting
-- UNIT_HEALTH, and at full health nothing else fires afterwards (druid form
-- stamina talents). One next-frame repaint reads settled values.
local RESETTLE_EVENTS = {
    UNIT_MAXHEALTH = true,
    UNIT_MAX_HEALTH_MODIFIERS_CHANGED = true,
}

-- tracker.channelsByEvent: event -> { channelName, ... } for its frame.
local function TrackerOnEvent(self, evt, unitToken, ...)
    local widget = self._cuiFrame
    if not widget or not widget:IsShown() then
        return
    end
    local channelList = self._cuiChannelsByEvent[evt]
    if not channelList then
        return
    end
    -- Boss slots re-sort mid-encounter (a new add takes boss2, the old one
    -- moves to boss3) and no event promises to name the move: the unit
    -- events of the new occupant kept painting health and casts under the
    -- old occupant's name. A GUID change on any event is the repaint edge.
    -- An unreadable GUID skips the probe (the engage repaint still runs).
    if self._cuiGuidGuard then
        local unitGuid = UnitGUID(widget._cuiUnit)
        if unitGuid ~= nil and not issecretvalue(unitGuid) then
            local old = self._cuiGuid
            self._cuiGuid = unitGuid
            if old ~= nil and old ~= unitGuid then
                Engine.RepaintAll(widget, "UnitChanged")
                return
            end
        end
    end
    for i = 1, #channelList do
        local ch = channelList[i]
        if ch == "castbar" then
            -- Raw route: event identity and payload both matter (cast edges),
            -- and consecutive same-frame events each carry distinct data --
            -- never deduped.
            local func = painters[ch]
            if func then
                func(widget, widget._cuiUnit, evt, unitToken, ...)
            end
        elseif ch == "powerval" then
            -- Value route, filtered like Blizzard's resource display: only a
            -- change of the power type the bar shows (the payload token
            -- against the token the full power paint stashed; none stashed =
            -- no filter) marks the frame for the value flush. The token is a
            -- plain string per the API docs; a secret one passes uncompared.
            local power = widget.Power
            local wanted = power and power._cuiPTok
            local pt = ...
            if wanted == nil or issecretvalue(pt) or pt == wanted then
                valPending[widget] = true
                valFlush:Show()
            end
        else
            Paint(widget, ch, evt)
        end
    end

    if RESETTLE_EVENTS[evt] and not self._cuiResettle then
        self._cuiResettle = true
        C_Timer.After(0, function()
            self._cuiResettle = nil
            local frame = self._cuiFrame
            if not frame or not frame:IsShown() then
                return
            end
            for i = 1, #channelList do
                Paint(frame, channelList[i], "Resettle")
            end
        end)
    end
end

local function EnsureTracker(token)
    local t = trackers[token]
    if t then
        return t
    end
    t = CreateFrame("Frame")
    t:SetScript("OnEvent", TrackerOnEvent)
    t._cuiChannelsByEvent = {}
    trackers[token] = t
    return t
end

--- Attaches a frame to the engine. channels = array of channel names; the
--- exact set drives which events get registered, so a frame with no castbar
--- never hears a spellcast event.
function Engine.Attach(widget, unitId, channels)
    local t = EnsureTracker(unitId)
    t._cuiFrame = widget
    attached[widget] = { unit = unitId, channels = channels }
    unitFrames[unitId] = widget
    t._cuiGuidGuard = unitId:match("^boss%d$") and true or nil
    -- Unit-watch shows happen while events were being dropped (hidden frames
    -- skip dispatch), so a freshly shown frame repaints in full.
    if not widget._cuiEngineShowHook then
        widget._cuiEngineShowHook = true
        widget:HookScript("OnShow", function(frame)
            Engine.RepaintAll(frame, "Show")
        end)
    end
    local secondary = SECONDARY_TOKEN[unitId]
    local byEvent = t._cuiChannelsByEvent
    for i = 1, #channels do
        local ch = channels[i]
        local events = (ch == "castbar") and CASTBAR_EVENTS or CHANNEL_EVENTS[ch]
        if events then
            for jdx = 1, #events do
                local eventName = events[jdx]
                local entries = byEvent[eventName]
                if not entries then
                    entries = {}
                    byEvent[eventName] = entries
                    if secondary then
                        t:RegisterUnitEvent(eventName, unitId, secondary)
                    else
                        t:RegisterUnitEvent(eventName, unitId)
                    end
                end
                local seen = false
                for k = 1, #entries do
                    if entries[k] == ch then
                        seen = true
                        break
                    end
                end
                if not seen then
                    entries[#entries + 1] = ch
                end
            end
        end
    end
end

--- Turns an opt-in channel on or off for one attached frame. On: the channel
--- joins the frame's repaint list and its events' routes; an event no other
--- channel uses is registered for the unit (plus its secondary token). Off:
--- the channel leaves every route, and an event left with no channel is
--- unregistered, so a channel that is off costs nothing. Idempotent; called
--- from settings code, never from a paint.
function Engine.SetChannelOn(widget, channelling, enabled)
    local details = attached[widget]
    local events = OPTIN_EVENTS[channelling]
    if not (details and events) then
        return
    end
    local channelList = details.channels
    local position
    for i = 1, #channelList do
        if channelList[i] == channelling then
            position = i
            break
        end
    end
    if enabled and not position then
        channelList[#channelList + 1] = channelling
    elseif not enabled and position then
        table.remove(channelList, position)
    end
    local unitId = details.unit
    local t = trackers[unitId]
    if not t then
        return
    end
    local byEvent = t._cuiChannelsByEvent
    local secondary = SECONDARY_TOKEN[unitId]
    for i = 1, #events do
        local eventName = events[i]
        local entries = byEvent[eventName]
        if enabled then
            if not entries then
                entries = {}
                byEvent[eventName] = entries
                if secondary then
                    t:RegisterUnitEvent(eventName, unitId, secondary)
                else
                    t:RegisterUnitEvent(eventName, unitId)
                end
            end
            local seen = false
            for k = 1, #entries do
                if entries[k] == channelling then
                    seen = true
                    break
                end
            end
            if not seen then
                entries[#entries + 1] = channelling
            end
        elseif entries then
            for k = #entries, 1, -1 do
                if entries[k] == channelling then
                    table.remove(entries, k)
                end
            end
            if #entries == 0 then
                byEvent[eventName] = nil
                t:UnregisterEvent(eventName)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Eventless units: targettarget/focustarget. One shared ticker, 0.5s (the
--  cadence users already know), alive only while at least one of the two
--  frames is shown. Value channels repaint every tick; identity channels
--  (portrait, full text) only when the GUID actually changed --
--  compared through a secret-safe equality that treats an unreadable GUID as
--  "changed" so restricted content fails open to a repaint, never to staleness.
-------------------------------------------------------------------------------
local pollFrames = {} -- frame -> true (tot/fot)
local pollTicker = CreateFrame("Frame")
pollTicker:Hide()
local pollAccum = 0
local POLL_INTERVAL = 0.5

local function GuidChanged(widget)
    local unitId = widget._cuiUnit
    local unitGuid = UnitExists(unitId) and UnitGUID(unitId) or nil
    local old = widget._cuiLastGuid
    if issecretvalue and (issecretvalue(unitGuid) or issecretvalue(old)) then
        widget._cuiLastGuid = unitGuid
        return true
    end
    if unitGuid ~= old then
        widget._cuiLastGuid = unitGuid
        return true
    end
    return false
end

pollTicker:SetScript("OnUpdate", function(self, elapsed)
    pollAccum = pollAccum + elapsed
    if pollAccum < POLL_INTERVAL then
        return
    end
    pollAccum = 0
    for widget in pairs(pollFrames) do
        if widget:IsShown() and UnitExists(widget._cuiUnit) then
            if GuidChanged(widget) then
                Engine.RepaintAll(widget, "PollIdentity")
            else
                Paint(widget, "health", "Poll")
                Paint(widget, "power", "Poll")
                Paint(widget, "text", "Poll")
                Paint(widget, "absorb", "Poll")
            end
        end
    end
end)

local function PollVisibilityChanged()
    for widget in pairs(pollFrames) do
        if widget:IsShown() then
            pollTicker:Show()
            return
        end
    end
    pollTicker:Hide()
end

--- Attaches an eventless frame (tot/fot): no tracker, ticker-driven. The
--- OnShow repaint keeps the first visible paint instant instead of waiting
--- out a poll interval.
function Engine.AttachPolled(widget, unitId, channels)
    attached[widget] = { unit = unitId, channels = channels }
    unitFrames[unitId] = widget
    pollFrames[widget] = true
    -- The polled-frame marker settings code checks (portrait art heal, text
    -- class-color reapply).
    widget.__eventless = true
    widget:HookScript("OnShow", function(frame)
        frame._cuiLastGuid = nil
        Engine.RepaintAll(frame, "Show")
        PollVisibilityChanged()
    end)
    widget:HookScript("OnHide", PollVisibilityChanged)
    PollVisibilityChanged()
end

-------------------------------------------------------------------------------
--  Secure layer: frame spawning, unit watching, vehicle resolution, and
--  default-frame suppression. All original code on the raw Blizzard secure
--  APIs; the click/menu surface uses the suite's own macro-proxy menu
--  (AttachSecureUnitMenu), the proven path around the 12.1 togglemenu bug.
-------------------------------------------------------------------------------

-- Everything we spawn parents here: one state driver hides the whole set
-- during pet battles.
local petBattleHider =
    CreateFrame("Frame", "CludesUIUnitFrames_Hider", UIParent, "SecureHandlerStateTemplate")
petBattleHider:SetAllPoints(UIParent)
RegisterStateDriver(petBattleHider, "visibility", "[petbattle] hide; show")

-- The live unit a secure button is presenting: the modified unit with the
-- pet-vs-vehicle distinction resolved (a pet button whose real unit is not
-- the pet is standing in for the vehicle).
local function ResolveActiveUnit(widget)
    local real = SecureButton_GetUnit(widget)
    local mod = SecureButton_GetModifiedUnit(widget)
    if real == "playerpet" then
        real = "pet"
    end
    if mod == "playerpet" then
        mod = "pet"
    end
    if mod == "playertarget" then
        mod = "target"
    end
    if mod == "pet" and real ~= "pet" then
        mod = "vehicle"
    end
    return mod or real or widget._cuiBaseUnit
end

local function SyncActiveUnit(widget)
    if not widget then
        return
    end
    local resolved = ResolveActiveUnit(widget)
    if resolved and resolved ~= widget._cuiUnit then
        -- Never adopt a unit that does not exist yet. Vehicle entry resolves
        -- "vehicle" at transition START, before the unit is queryable: adopting
        -- then paints empty text (UnitName nil renders ""), and every later
        -- vehicle edge no-ops on resolved == frame._cuiUnit, so an idle vehicle
        -- stays blank for the whole ride. Holding the OLD unit keeps this
        -- re-firing on each transition edge until the resolved unit is real,
        -- and THAT swap's RepaintAll paints with live data -- the same guard
        -- the oUF-era swap had. The base unit is exempt: it must always be
        -- adoptable (nonexistent target/focus frames hide via unit-watch, and
        -- refusing the base would strand a stale token instead).
        if resolved ~= widget._cuiBaseUnit and not UnitExists(resolved) then
            return
        end
        widget._cuiUnit = resolved
        Engine.RepaintAll(widget, "UnitChanged")
    end
end
Engine.EvalActiveUnit = SyncActiveUnit

-------------------------------------------------------------------------------
--  Element compatibility surface: the settings code toggles rendering per
--  element (portrait off, castbar off...) through the same three methods it
--  always called. "Disabled" = the matching painter skips it; the widgets and
--  their fields stay untouched.
-------------------------------------------------------------------------------
local ELEMENT_CHANNEL = {
    Health = "health",
    Power = "power",
    Castbar = "castbar",
    Portrait = "portrait",
    HealthPrediction = "absorb",
    RaidTargetIndicator = "raidicon",
}

--- True when a painter would render this element right now.
function Engine.ElementOn(widget, partName)
    local disabled = widget._cuiElementsOff
    return not (disabled and disabled[partName])
end

local function Frame_IsElementEnabled(self, partName)
    return self[partName] ~= nil and Engine.ElementOn(self, partName)
end

local function Frame_EnableElement(self, partName)
    local disabled = self._cuiElementsOff
    local wasOff = disabled and disabled[partName]
    if disabled then
        disabled[partName] = nil
    end
    -- Match the old enable semantics: an immediate refresh of that element.
    local channelling = ELEMENT_CHANNEL[partName]
    if channelling == "castbar" then
        local func = painters[channelling]
        if func then
            func(self, self._cuiUnit, "ForceUpdate")
        end
    elseif channelling then
        -- A channel with no unit events (the raid marker) is attached only
        -- when its element existed at spawn: one turned on later joins the
        -- frame's repaint list here, so a target or focus swap, a show and
        -- every other full repaint paint it too.
        local details = attached[self]
        if details and not CHANNEL_EVENTS[channelling] then
            local channelList = details.channels
            local listed = false
            for i = 1, #channelList do
                if channelList[i] == channelling then
                    listed = true
                    break
                end
            end
            if not listed then
                channelList[#channelList + 1] = channelling
            end
        end
        -- A paint earlier in this frame (the settings reload repaints every
        -- frame first) skipped the element while it was off: its stamp must
        -- not eat this one.
        local stamps = self._cuiPaintStamps
        if wasOff and stamps then
            stamps[channelling] = nil
        end
        Paint(self, channelling, "ForceUpdate")
    end
    -- The player's power value channel follows the Power element.
    if partName == "Power" then
        ns.UF_PowerValSync(self)
    end
end

local function Frame_DisableElement(self, partName)
    local disabled = self._cuiElementsOff
    if not disabled then
        disabled = {}
        self._cuiElementsOff = disabled
    end
    disabled[partName] = true
    if partName == "Power" then
        ns.UF_PowerValSync(self)
    end
end

--- Spawns one secure unit button. The caller styles it and attaches engine
--- channels afterward; RegisterUnitWatch owns show/hide from here on.
function Engine.SpawnUnitFrame(unitId, name)
    -- Contextual pings: TEMPLATE-PURE, and the button must NEVER carry a
    -- `.unit` FIELD. Blizzard's ping mixin reads `self.unit or
    -- self:GetAttribute("unit")` inside PingManager's secure gather, and an
    -- addon-written field is a tainted read that turns a secret GUID
    -- "inaccessible" to the securecopy at the secure boundary (hard error +
    -- wedged listener); the attribute is the sanctioned channel and keeps
    -- the whole chain secure, so secrets pass and enemy pings work exactly
    -- like the default frames (field-proven 2026-08-20). Hence the live
    -- token lives in `_cuiUnit`, and GetIsPingable/GetTargetInfo are never
    -- overridden here (raw override = securecopy error, secrecy-guarded
    -- override = pings dead in all restricted content; both field-failed).
    local widget =
        CreateFrame("Button", name, petBattleHider, "SecureUnitButtonTemplate, PingableUnitFrameTemplate")
    widget._cuiBaseUnit = unitId
    widget._cuiUnit = unitId
    widget.IsElementEnabled = Frame_IsElementEnabled
    widget.EnableElement = Frame_EnableElement
    widget.DisableElement = Frame_DisableElement
    widget:SetAttribute("unit", unitId)
    widget:SetAttribute("*type1", "target")
    widget:SetAttribute("toggleForVehicle", true)
    CludesUI.AttachSecureUnitMenu(widget)
    -- The secure environment rewrites the unit attribute on vehicle and pet
    -- transitions; re-resolve whenever it moves.
    widget:HookScript("OnAttributeChanged", function(self, attr)
        if attr == "unit" or attr == "toggleForVehicle" then
            SyncActiveUnit(self)
        end
    end)
    RegisterUnitWatch(widget)
    return widget
end

-------------------------------------------------------------------------------
--  Default Blizzard unit frame suppression: the module's battle-tested
--  ns.UF_HideBlizzard owns the mechanics (alt-power-bar taint handling, the
--  boss-container-no-reparent rule); the engine just routes to it.
-------------------------------------------------------------------------------
function Engine.HideBlizzardUnitFrame(unitId)
    if ns.UF_HideBlizzard then
        ns.UF_HideBlizzard(unitId)
    end
end

-- Vehicle/pet transitions for the player and pet frames: the dual-token
-- event registration means nothing re-registers here -- these just move
-- frame._cuiUnit and trigger the full repaint.
local vehicleWatch = CreateFrame("Frame")
vehicleWatch:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
vehicleWatch:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
vehicleWatch:RegisterUnitEvent("UNIT_PET", "player")
vehicleWatch:SetScript("OnEvent", function(_, evt)
    SyncActiveUnit(unitFrames.player)
    local pet = unitFrames.pet
    if evt == "UNIT_PET" and pet and pet._cuiUnit == "pet" and UnitExists("pet") then
        -- Pet SWAP: the token stays "pet", so EvalActiveUnit sees no change and
        -- nothing repaints the identity zones (name is static on value ticks,
        -- and no UNIT_NAME_UPDATE follows a swap) -- the old pet's name stuck
        -- until the next summon from empty. Blizzard's PetFrame full-updates on
        -- every UNIT_PET; one repaint per swap is the same shape.
        Engine.RepaintAll(pet, "UnitChanged")
        return
    end
    SyncActiveUnit(pet)
end)

-------------------------------------------------------------------------------
--  Global (non-unit) triggers
-------------------------------------------------------------------------------
local sharedFrame = CreateFrame("Frame")
sharedFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
sharedFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
sharedFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
sharedFrame:RegisterEvent("RAID_TARGET_UPDATE")
sharedFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
-- 2D portrait art streams in AFTER the paint that asked for it (loading
-- screens, vehicle transitions); this unitless event is the only trigger
-- that follows, so it fans the portrait painter out to every shown frame
-- (rare event, bounded fan-out -- the old element wiring registered it
-- unconditionally on every portrait frame).
sharedFrame:RegisterEvent("PORTRAITS_UPDATED")
-- The target's and the focus's own target changing: their small frames
-- repaint on the event instead of waiting out the poll tick. (A cast they
-- begin is no trigger: the unit's target field changes a moment after the
-- cast starts, or not at all, so a repaint at the cast would paint the old
-- occupant.)
sharedFrame:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
sharedFrame:SetScript("OnEvent", function(self, evt, unitId)
    if evt == "PLAYER_TARGET_CHANGED" then
        local frame = unitFrames.target
        if frame then
            Engine.RepaintAll(frame, evt)
        end
        local tot = unitFrames.targettarget
        if tot then
            tot._cuiLastGuid = nil
            pollAccum = POLL_INTERVAL
        end
    elseif evt == "PLAYER_FOCUS_CHANGED" then
        local frame = unitFrames.focus
        if frame then
            Engine.RepaintAll(frame, evt)
        end
        local fot = unitFrames.focustarget
        if fot then
            fot._cuiLastGuid = nil
            pollAccum = POLL_INTERVAL
        end
    elseif evt == "UNIT_TARGET" then
        local frame = (unitId == "target" and unitFrames.targettarget)
            or (unitId == "focus" and unitFrames.focustarget)
            or nil
        if frame and frame:IsShown() and UnitExists(frame._cuiUnit) then
            -- The whole occupant changed, so the repaint is an identity one
            -- (the text painter paints only its target zones for the event
            -- name itself, which would leave the old name under the new
            -- colour). The poll's GUID memo takes the new occupant, so its
            -- next tick does not repeat this paint.
            frame._cuiLastGuid = UnitGUID(frame._cuiUnit)
            Engine.RepaintAll(frame, "UnitChanged")
        end
    elseif evt == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        for i = 1, 5 do
            local frame = unitFrames["boss" .. i]
            if frame and frame:IsShown() then
                Engine.RepaintAll(frame, evt)
            end
        end
        -- The slots can still be settling when the event lands (one occupant
        -- moves down while the new one moves in): one next-frame pass reads
        -- the final order.
        if not self._cuiBossSettle then
            self._cuiBossSettle = true
            C_Timer.After(0, function()
                self._cuiBossSettle = nil
                for i = 1, 5 do
                    local frame = unitFrames["boss" .. i]
                    if frame and frame:IsShown() then
                        Engine.RepaintAll(frame, "UnitChanged")
                    end
                end
            end)
        end
    elseif evt == "RAID_TARGET_UPDATE" then
        local func = painters.raidicon
        if func then
            for widget, details in pairs(attached) do
                if widget:IsShown() then
                    func(widget, widget._cuiUnit, evt)
                end
            end
        end
    elseif evt == "PORTRAITS_UPDATED" then
        local func = painters.portrait
        if func then
            for widget in pairs(attached) do
                if widget:IsShown() then
                    func(widget, widget._cuiUnit, evt)
                end
            end
        end
    else -- PLAYER_ENTERING_WORLD: the world changed under every frame.
        -- Loading screens can land mid-vehicle-transition; re-resolve the
        -- swappable frames before repainting so the repaint reads the right
        -- unit.
        SyncActiveUnit(unitFrames.player)
        SyncActiveUnit(unitFrames.pet)
        for widget in pairs(attached) do
            if widget:IsShown() then
                Engine.RepaintAll(widget, evt)
            end
        end
    end
end)
