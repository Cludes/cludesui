if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- CUI_ResourceBars_SwingTimer.lua
-- WoW FOREVER ONLY: Swing Timer resource bar.
--
-- Addons lost the combat log in 12.0 (no SWING_DAMAGE / SWING_MISSED), so the
-- classic swing-timer recipe is dead. Forever instead ships a native timer
-- (Blizzard_SwingTimer, AllowLoadGameType camelot) and the API under it:
--   PLAYER_SWING(swingDuration, swingType)          -- one per player swing
--   C_SwingTimer.EnableRangeCheck(swingType, bool)  -- opt in to range edges
--   PLAYER_SWING_RANGE_UPDATE(swingType, isInRange, checksRange)
--   C_SwingTimer.IsTargetWithinSwingRange(swingType) -- nil = no check possible
--   Enum.PlayerSwingType.MainHand | OffHand | Ranged
-- This file mirrors Blizzard's semantics (which rows exist, when a row restarts,
-- how out-of-range reads) on CUI's own frames; it never touches Blizzard's.
--
-- One frame, up to three ROWS (Main Hand / Off Hand / Ranged) stacked top to
-- bottom. A row exists while UnitAttackSpeed reports a speed for its slot
-- (Main Hand always does); the frame shrinks to the rows shown. Each row is a
-- StatusBar in a clip frame with bg, PP border, spark and two FontStrings
-- (remaining time, slot tag). Combine Hands takes the Off Hand row out of the
-- stack: it is laid over the Main Hand row with no bg, border, text or fill of
-- its own, so only its spark shows, riding its own engine-timed fill edge along
-- the Main Hand bar (no Lua per frame there either).
--
-- Cost on: PLAYER_SWING re-sets the row's C_DurationUtil duration object and
-- arms the bar timer (SetTimerDuration), so the engine animates the fill with
-- no Lua per frame, the way the QoL swing timer ran. The remaining-time text is
-- the engine's too: a duration text binding on the same duration object
-- writes it through a tenths formatter. Lua runs at a swing's edges only: its
-- start, and deadlines at its end (idle fill or waiting, Hide When Idle) and,
-- on a Movement Guide row, at Stop by and the last latency (the edges with no
-- event). Range and the
-- Attack State (queued, on, waiting) are event-driven
-- (PLAYER_SWING_RANGE_UPDATE, ACTIONBAR_UPDATE_STATE, the auto attack and
-- auto-repeat edges). A row whose attack is on with no swing running waits
-- (parked full), entered on the end edge or an attack edge and left on the
-- next swing or an attack-stop edge. The Movement Guide's GO and STILL zones
-- are placed once per swing, its smoothing is arithmetic on the swing start,
-- and its aim phase starts on a deadline at Stop by or a stop that ends a
-- held shot, with PLAYER_STARTED/STOPPED_MOVING registered only while a wand
-- or Auto Shot is on with that mode. An idle row costs nothing: its timer holds
-- a finished duration, which paints a static state.
--
-- Everything is gated on the swing API and the engine timer it feeds: on retail
-- this file returns right below and nothing below exists. Off by default = no
-- frame children, no events, no timers. A druid form switched off, or talent
-- conditions that do not hold, park it the same way (RuledOut).

local _, mod = ...
local CludesUI = _G.CludesUI

-- The swing API, its enum (SwingTimerDocumentation.lua: 0/1/2) and the bar
-- timer plumbing all come from the Forever client; no fallbacks for any of them.
if
    not (
        C_SwingTimer
        and Enum.PlayerSwingType
        and C_DurationUtil
        and C_DurationUtil.CreateDuration
        and Enum.StatusBarTimerDirection
        and Enum.StatusBarInterpolation
    )
then
    return
end
local SWING = Enum.PlayerSwingType
local DIR = Enum.StatusBarTimerDirection
-- A re-arm snaps to the timer's current value: a restart mid-swing must not
-- ease back from the old fill.
local IMMEDIATE = Enum.StatusBarInterpolation.Immediate

local UNLOCK_KEY = "ERB_SwingTimer"
local MO_KEY = "swing" -- ERB._moEligible slot for the shared mouseover poll

-- Display order, top to bottom. `key` is the colour-key prefix in the store
-- (mhR/mhG/... ohR/... rR/..., and mhSparkR/... for the spark), `show` the
-- per-row toggle key, `melee` the rows the Auto Attack state colors, `queue` the
-- row a queued attack always lands on (Main Hand).
local ROWS = {
    { type = SWING.MainHand, key = "mh", tag = "MH", show = "showMH", melee = true, queue = true },
    { type = SWING.OffHand, key = "oh", tag = "OH", show = "showOH", melee = true },
    { type = SWING.Ranged, key = "r", tag = "R", show = "showR" },
}

-- On-next-swing attacks: CludesUI.FOREVER_NEXT_SWING (Warrior Heroic Strike
-- / Cleave, Druid Maul, Hunter Raptor Strike). While one is queued the melee
-- rows take that attack's colour and carry its name, so the swing that will
-- consume it is visible. Colours: `key` is the colour-key prefix in the store
-- (queueR/G/B/A, queueCleaveR/...), r/g/b its fallback; Cleave has its own,
-- every other attack shares "queue". Names resolve once per session and only
-- for a class that has one: ACTIONBAR_UPDATE_STATE storms in combat and is
-- registered only while there are names to compare (the paint touches the rows
-- only when the queued attack changes).
-- Heroic Strike / Raptor Strike / Maul colors (queueHS, queueRaptor, queueMaul);
-- while unset they use the shared "queue" color (`shared`).
local QUEUE_COLOR = { key = "queue", r = 1, g = 0.70, b = 0.20 }
local QUEUE_COLORS = {
    [845] = { key = "queueCleave", r = 0.95, g = 0.35, b = 0.25 }, -- Cleave
    [78] = { key = "queueHS", r = 1, g = 0.70, b = 0.20, shared = "queue" }, -- Heroic Strike
    [2973] = { key = "queueRaptor", r = 1, g = 0.70, b = 0.20, shared = "queue" }, -- Raptor Strike
    [6807] = { key = "queueMaul", r = 1, g = 0.70, b = 0.20, shared = "queue" }, -- Maul
}

-- Attack State Full, On: while a row's auto attack is on, its fill takes the On
-- colour (melee rows: Auto Attack; Ranged: the auto-repeat shot, Shoot or
-- Auto Shot). The on/off edges are events; START_AUTOREPEAT_SPELL fires on the
-- press, so a shot queued behind a cast already reads as on. AUTO_ATTACK and
-- the action slot scan seed the state the edges missed (enable, /reload
-- mid-attack).
local ACTIVE_COLOR = { r = 0.298, g = 0.788, b = 0.941 }
local AUTO_ATTACK = 6603
local MAX_ACTION_SLOT = 180

-- Attack State Full, Waiting: the colour of a waiting row (attack on, no swing
-- running: its timer ran out, the attack started out of range or behind a
-- cast, or moving holds the shot).
local PENDING_COLOR = { r = 0.659, g = 0.502, b = 0.949 }

-- Movement Guide smoothing: swings land around the bar end with network /
-- server jitter, so each swing starts from the expected rhythm moved SMOOTH_GAIN of
-- the way toward its arrival, instead of at the arrival. A swing further than
-- SMOOTH_TOL from the rhythm is a real interruption: start from it as is.
local SMOOTH_TOL = 0.25
local SMOOTH_GAIN = 0.25

-- Aim: wand Shoot and Auto Shot need the player to stand still for AIM_TIME
-- before a shot (Forever beta patch note). The countdown runs alongside the
-- reported swing, from each stop, so the shot lands at the later of the
-- swing's end and AIM_TIME after the player last stopped moving, never while
-- moving: a stop must be made AIM_TIME plus one latency before the bar's end
-- (Stop by). AIM_CLASS: the classes whose Ranged row is one of the two;
-- AIM_COLOR: STILL's fallback.
local AIM_TIME = 0.5
local AIM_CLASS = { PRIEST = true, MAGE = true, WARLOCK = true, HUNTER = true }
local AIM_COLOR = { r = 1, g = 0.82, b = 0.25 }

-- Shell at FILE SCOPE (attribution rule, see _erbEventFrame in the main file):
-- the OnEvent work bills ResourceBars. Children stay lazy.
local shell = CreateFrame("Frame", "ERB_SwingTimerFrame", UIParent)
shell:Hide()

-- built, rows[i] (row frames in ROWS order), byType[swingType] = row, shown (rows
-- stacked on screen; a combined off hand takes no slot), live (rows mid-swing),
-- rangeOn[swingType] = bool, sample (unlock mode preview on), moHooked,
-- unlockHooked, lastH (frame height last laid out), queueSpells (this class's
-- on-next-swing attacks: id, colour key + fallback, resolved name), queued (the
-- entry painted, false = none), meleeOn / repeatOn (auto attack / auto-repeat
-- on, from the edges), seeded (both read since the highlight came on), active
-- (the state painted), aimClass (this class's AIM_CLASS),
-- moveEvents / moving (the movement edges registered / the player moving),
-- ruled (the form or talents ruled the timer out at the last apply, RuledOut).
-- Per row, _rtt (the latency read for its swing) and, on a guide row, _aimAt
-- (its Stop by point), _aiming and _aimFrom (an aim phase running, and from
-- when).
local S = {
    rows = {},
    byType = {},
    shown = 0,
    live = 0,
    rangeOn = {},
    queueSpells = {},
    queued = false,
    meleeOn = false,
    repeatOn = false,
    active = { melee = false, ranged = false },
}

-------------------------------------------------------------------------------
--  Settings access
-------------------------------------------------------------------------------

local function P()
    local ERB = mod.ERB
    local saved = ERB and ERB.db
    local p = saved and saved.profile
    return p and p.swingTimer or nil
end

local _, playerClass = UnitClass("player")

-- Forms and talents (the Visibility row's Forms and Talents cog): true while the
-- druid's current form is switched off (barDisabledForms, the per-form map the
-- other bars use) or the talent conditions saved for the player's class do not
-- hold (classTalentConditions[class], the Talent Conditions picker's list; per
-- class, so one profile serves every class). Ruled out, the timer stands down
-- like switched off (ns.ST_Apply).
local function RuledOut(conf)
    if _G._CURB_BarHiddenByForm(conf) then
        return true
    end
    local byClass = conf.classTalentConditions
    local conds = byClass and byClass[playerClass]
    return conds ~= nil and not CludesUI.TalentConditionsHold(conds)
end

local function HasTalentConds(conf)
    local byClass = conf.classTalentConditions
    return byClass ~= nil and byClass[playerClass] ~= nil
end

-- The look the rows wear: the Resource Bars row of Global Settings > Style
-- (ns.ERB_BarsStyle, latched for the session; WoW Forever draws Blizzard Style).
function mod.ST_Style()
    return mod.ERB_BarsStyle()
end

-- Under a stock style every row wears its own frame, whose rim reaches past
-- the row: the stack adds the rims of two neighbours to Row Spacing, so the
-- setting stays the gap between frames.
local function StockGap(conf)
    local style = mod.ST_Style()
    if style == "blizzard" then
        local _, ph = mod.ERB_BlizzMatchPad(false)
        return ph or 0
    elseif style == "classic" then
        local _, ph = mod.ERB_ClassicMatchPad(0, 0, false, mod.ERB_ClassicFrameK(conf))
        return math.ceil(ph)
    end
    return 0
end

local function RowGap(conf)
    return (conf.rowSpacing or 0) + StockGap(conf)
end

-- Secret values throw on comparison and on truth tests: every read from the
-- swing API and from UnitAttackSpeed passes here before it is looked at, and a
-- restricted answer is treated as "no information" (no swing, no range
-- verdict, and a row keeps what was last known about it). Never infer an
-- interval from restricted data.
local function Plain(val)
    return not (issecretvalue and issecretvalue(val))
end

-- Blizzard's CanSwing: Main Hand always applies; Off Hand / Ranged only while
-- UnitAttackSpeed reports a positive speed for the slot. Those speeds are
-- secret while unit stats are restricted (SecretWhenUnitStatsRestricted), and a
-- haste proc's UNIT_ATTACK_SPEED lands right there in combat: that answer is
-- nil ("unknown"), never "no weapon".
local function CanSwing(swingType)
    if swingType == SWING.MainHand then
        return true
    end
    local _, oh, ranged = UnitAttackSpeed("player")
    local speed
    if swingType == SWING.OffHand then
        speed = oh
    elseif swingType == SWING.Ranged then
        speed = ranged
    else
        return false
    end
    if not Plain(speed) then
        return nil
    end
    return type(speed) == "number" and speed > 0
end

-- Shield in the off hand slot: it never swings but counts as an off hand.
local OFFHAND_SLOT = 17
local function OffHandIsShield()
    local ident = GetInventoryItemID("player", OFFHAND_SLOT)
    if not (ident and Plain(ident)) then
        return false
    end
    local _, _, _, loc = C_Item.GetItemInfoInstant(ident)
    return Plain(loc) and loc == "INVTYPE_SHIELD"
end

-- Shield handling (and its event) is active only with Show Shield As Off Hand
-- or Always Show Rows on.
local function ShieldAware(conf)
    return conf and (conf.shieldRow or conf.alwaysShowRows) and true or false
end
local function ShieldOff(conf)
    return ShieldAware(conf) and OffHandIsShield()
end

-- Rows a queued attack shows on: Main Hand, plus Off Hand unless Queued On Main
-- Hand Only is on.
local function QueueRow(def, conf)
    return def.queue or (def.melee and not conf.queueMainHandOnly)
end

-- A row is shown while its toggle is on and its slot can swing: the live answer
-- when it is plain, else the last one known for that row (a swing of its type
-- is proof too, see PLAYER_SWING). Nothing known yet reads as no row. Always
-- Show Rows shows every ticked row; row._canSwing keeps the real answer.
local function RowWanted(def, conf, row)
    if conf and conf[def.show] == false then
        return false
    end
    local can = CanSwing(def.type)
    if can == nil then
        can = row and row._canSwing or false
    elseif row then
        row._canSwing = can
    end
    if conf and conf.alwaysShowRows then
        return true
    end
    if not can and def.type == SWING.OffHand and ShieldOff(conf) then
        return true
    end
    return can
end

-- Rows the frame would stack right now (from the live rows once built, from the
-- weapon slots before). Feeds the unlock mover's size before the first build.
-- A combined off hand rides the Main Hand bar and takes no row (RefreshRows).
local function ShownCount()
    if S.built then
        return math.max(S.shown, 1)
    end
    local conf = P()
    local num = 0
    for i = 1, #ROWS do
        if RowWanted(ROWS[i], conf) then
            num = num + 1
        end
    end
    -- ROWS[1] / ROWS[2] = Main Hand / Off Hand
    if
        conf
        and conf.combineHands
        and RowWanted(ROWS[1], conf)
        and RowWanted(ROWS[2], conf)
        and not ShieldOff(conf)
    then
        num = num - 1
    end
    return math.max(num, 1)
end

-- Frame size: width x (rows * height + gaps).
local function Size(conf)
    conf = conf or P()
    if not conf then
        return 220, 12
    end
    local num = ShownCount()
    local hgt = conf.height or 12
    local sp = RowGap(conf)
    return conf.width or 220, num * hgt + (num - 1) * sp
end

local function RowColor(conf, def)
    if conf.classColored then
        local cc = mod.CLASS_COLORS and mod.CLASS_COLORS[select(2, UnitClass("player"))]
        if cc then
            return cc[1], cc[2], cc[3], conf[def.key .. "A"] or 1
        end
    end
    local k = def.key
    return conf[k .. "R"] or 1, conf[k .. "G"] or 1, conf[k .. "B"] or 1, conf[k .. "A"] or 1
end

-- Spark tint: the row's own spark colour once set, else white. A combined off
-- hand's spark is its whole display: unset, it takes the row's fill colour.
-- unset: the tint it has without a colour of its own.
local function SparkColor(conf, def, merged, unset)
    local k = def.key .. "Spark"
    local region = not unset and conf[k .. "R"]
    if region then
        return region, conf[k .. "G"] or 1, conf[k .. "B"] or 1, conf[k .. "A"] or 1
    end
    if merged then
        return RowColor(conf, def)
    end
    return 1, 1, 1, 1
end

-------------------------------------------------------------------------------
--  Countdown text
-------------------------------------------------------------------------------

-- The remaining time in tenths ("1.2"), written by the engine. The first table
-- also leaves the last 0.05s blank, as the text always has (never "0.0"); if
-- the client refuses it, the plain tenths table the Tracking Bars use stands
-- in. nil: no countdown (neither table taken).
local timeFormatter -- false once both tables were refused
local function TimeFormatter()
    if timeFormatter ~= nil then
        return timeFormatter or nil
    end
    timeFormatter = false
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding) then
        return nil
    end
    local Nearest = Enum.NumericRuleFormatRounding.Nearest
    local tables = {
        {
            { threshold = 0, format = "", rounding = Nearest },
            { threshold = 0.05, format = "%.1f", rounding = Nearest },
        },
        { { threshold = 0, format = "%.1f", rounding = Nearest } },
    }
    for i = 1, #tables do
        local frame = C_StringUtil.CreateNumericRuleFormatter()
        if pcall(frame.SetBreakpoints, frame, tables[i]) then
            timeFormatter = frame
            return frame
        end
    end
    return nil
end

-- The Text Cue's Move countdown in tenths ("Move 1.2"). nil: the client
-- refused the format, and the plain countdown stands in.
local cueFormatter -- false once refused
local function CueFormatter()
    if cueFormatter ~= nil then
        return cueFormatter or nil
    end
    cueFormatter = false
    if not TimeFormatter() then
        return nil
    end
    local frame = C_StringUtil.CreateNumericRuleFormatter()
    local rule = {
        {
            threshold = 0,
            format = CludesUI.L("Move %.1f"),
            rounding = Enum.NumericRuleFormatRounding.Nearest,
        },
    }
    if pcall(frame.SetBreakpoints, frame, rule) then
        cueFormatter = frame
    end
    return cueFormatter or nil
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------

local function BuildRow(def)
    local row = CreateFrame("Frame", nil, shell)
    row._def = def

    local backdrop = row:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    row._bg = backdrop

    local bdr = CreateFrame("Frame", nil, row)
    bdr:SetAllPoints(row)
    bdr:SetFrameLevel(row:GetFrameLevel() + 5)
    row._border = bdr
    local Pix = CludesUI and CludesUI.PP
    if Pix then
        Pix.CreateBorder(bdr, 0, 0, 0, 1, 1)
    end

    local clip = CreateFrame("Frame", nil, row)
    clip:SetClipsChildren(true)
    row._clip = clip

    local barFrame = CreateFrame("StatusBar", nil, clip)
    barFrame:SetMinMaxValues(0, 1)
    barFrame:SetValue(0)
    row._bar = barFrame
    -- One duration object per row, re-set per swing and handed to the bar
    -- timer (the QoL timer's shape); never read back in Lua.
    row._durObj = C_DurationUtil.CreateDuration()

    -- Spark (same texture/approach as the cast and GCD bars)
    local sparkFrame = CreateFrame("Frame", nil, clip)
    sparkFrame:SetAllPoints(barFrame)
    sparkFrame:SetFrameLevel(barFrame:GetFrameLevel() + 2)
    local spark = sparkFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    spark:SetTexture(mod.SPARK_TEX)
    spark:SetBlendMode("ADD")
    row._spark = spark
    row._sparkFrame = sparkFrame

    -- Text above the fill; the tag on the left, the countdown on the right.
    local textFrame = CreateFrame("Frame", nil, row)
    textFrame:SetAllPoints(row)
    textFrame:SetFrameLevel(barFrame:GetFrameLevel() + 3)
    row._textFrame = textFrame
    -- Font before any SetText: a FontString with no font errors on SetText
    -- ("Font not set", seen on the Forever client). ApplyRowLook re-sizes it.
    local tag = textFrame:CreateFontString(nil, "OVERLAY")
    mod.SetRBFont(tag, mod.GetRBFont(), 11)
    tag:SetPoint("LEFT", row, "LEFT", 4, 0)
    tag:SetJustifyH("LEFT")
    tag:SetWordWrap(false)
    tag:SetText(def.tag)
    row._tag = tag
    local time = textFrame:CreateFontString(nil, "OVERLAY")
    mod.SetRBFont(time, mod.GetRBFont(), 11)
    time:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    time:SetJustifyH("RIGHT")
    time:SetWordWrap(false)
    time:SetText("")
    row._time = time
    -- The countdown, written engine-side from the row's duration object.
    local fmt = C_DurationUtil.CreateDurationTextBinding and TimeFormatter()
    if fmt then
        local b = C_DurationUtil.CreateDurationTextBinding()
        b:SetFontString(time)
        b:SetDuration(row._durObj)
        b:SetFormatter(fmt)
        b:SetUpdateInterval(0.05)
        b:SetExpiredText("")
        b:SetZeroDurationText("")
        b:SetEnabled(false)
        row._timeBind = b
        row._timeBindOn = false
    end

    row._outOfRange = false
    return row
end

-- Out-of-range look: Blizzard dims the whole row to 0.4 and paints the text
-- red. Unlock mode suppresses the dimming without touching the state. A
-- combined off-hand row keeps no bg, border or stock frame (alpha, not Hide: a
-- border re-apply shows its frame again); its range dims the clip, i.e. its
-- spark.
local function ApplyRangeLook(row, conf)
    conf = conf or P()
    local oor = row._outOfRange and not S.sample
    local alpha = oor and ((conf and conf.outOfRangeAlpha) or 0.4) or 1
    local frameAlpha = row._merged and 0 or alpha
    row._bg:SetAlpha(frameAlpha)
    row._border:SetAlpha(frameAlpha)
    if row._blizzBarBg then
        row._blizzBarBg:SetAlpha(frameAlpha)
    end
    if row._classicArt then
        row._classicArt:SetAlpha(frameAlpha)
    end
    row._clip:SetAlpha(alpha)
    if oor then
        row._tag:SetTextColor(1, 0.1, 0.1, 1)
        row._time:SetTextColor(1, 0.1, 0.1, 1)
    else
        row._tag:SetTextColor(1, 1, 1, 1)
        row._time:SetTextColor(1, 1, 1, 1)
    end
end

local function SetOutOfRange(row, oor)
    oor = oor and true or false
    if row._outOfRange == oor then
        return
    end
    row._outOfRange = oor
    ApplyRangeLook(row)
end

-- Range tracking is one engine flag per swing type, and Blizzard's own timer
-- flips it on its edges too (its Edit Mode toggle sends false for the slot), so
-- this never dedupes: every row refresh and every target change re-asserts our
-- answer, and a flip from the other frame can never leave a row undimmed.
-- S.rangeOn is the memo UpdateRangeRow reads, not a send gate.
local function SetRangeCheck(swingType, on)
    on = on and true or false
    S.rangeOn[swingType] = on
    C_SwingTimer.EnableRangeCheck(swingType, on)
end

-- Re-read range for one row from the API (target change, row shown).
local function UpdateRangeRow(row)
    if not S.rangeOn[row._def.type] then
        SetOutOfRange(row, false)
        return
    end
    -- nil = no check could be made (no target, untargetable, no weapon): NOT out of range.
    local inRange = C_SwingTimer.IsTargetWithinSwingRange(row._def.type)
    SetOutOfRange(row, Plain(inRange) and inRange == false)
end

local function UpdateRangeAll()
    for i = 1, #S.rows do
        local row = S.rows[i]
        if row:IsShown() then
            UpdateRangeRow(row)
        end
    end
end

-- Spark visibility, set on the row's edges only (swing start, swing end, look
-- apply), never per frame. Show Spark's spark shows only while its row is
-- mid-swing (not while it waits: no edge moves). A combined off-hand
-- row's spark IS the off-hand display: it ignores Show Spark and shows only
-- mid-swing. Unlock movers up show both.
local function UpdateSpark(row, conf)
    local on
    if row._merged then
        on = row._live or S.sample
    else
        on = conf and conf.showSpark and ((row._live and not row._waiting) or S.sample)
    end
    row._spark:SetShown(on and true or false)
end

-- Zones mark the end of a running swing: GO (`lat`: the swing's last world
-- latency, the cast bar's ShowLatencyOverlay recipe; anything started there
-- lands after the swing) on every row, and STILL (`aim`: the AIM_TIME a wand or
-- Auto Shot needs the player still, one latency before GO; be still by its
-- edge) on a guide row in Segments. With Deplete Fill the swing ends on the
-- left under the fill, so a zone draws over it there (front); a filling bar
-- ends on the right and sweeps over a zone below it (back). Each is a
-- back/front texture pair built on first enable and placed once per swing; GO
-- draws over STILL. None on an idle, waiting or combined off-hand row.
local function HideZone(z)
    if z then
        z.back:Hide()
        z.front:Hide()
    end
end

local function HideZones(row)
    local zones = row._zones
    if zones then
        HideZone(zones.lat)
        HideZone(zones.aim)
    end
end

local function StyleZone(row, key, on, texPath, region, g, b, a, backSub, frontSub)
    local zones = row._zones
    local z = zones and zones[key]
    if not on or row._merged then
        HideZone(z)
        return
    end
    if not z then
        if not zones then
            zones = {}
            row._zones = zones
        end
        z = {
            back = row._clip:CreateTexture(nil, "ARTWORK", nil, backSub),
            front = row._bar:CreateTexture(nil, "OVERLAY", nil, frontSub),
        }
        z.back:Hide()
        z.front:Hide()
        zones[key] = z
    end
    z.back:SetTexture(texPath)
    z.back:SetVertexColor(region, g, b, a)
    z.front:SetTexture(texPath)
    z.front:SetVertexColor(region, g, b, a)
end

-- `deplete`: the phase ends on the left (its fill drains), else on the right.
-- `offset`: seconds the zone sits back from that end (STILL, one latency).
local function PlaceZone(row, z, conf, secs, dur, deplete, offset)
    if not (secs and secs > 0 and dur and dur > 0) then
        HideZone(z)
        return
    end
    local wid = row._clip:GetWidth()
    if not (wid and wid > 0) then
        wid = conf.width or 220
    end
    local off = (offset and offset > 0) and wid * math.min(1, offset / dur) or 0
    local room = wid - off
    if room < 1 then
        HideZone(z)
        return
    end
    local zw = wid * math.min(1, secs / dur)
    if zw < 1 then
        zw = 1
    elseif zw > room then
        zw = room
    end
    local zone = deplete and z.front or z.back
    local other = deplete and z.back or z.front
    other:Hide()
    zone:ClearAllPoints()
    if deplete then
        zone:SetPoint("TOPLEFT", row._clip, "TOPLEFT", off, 0)
        zone:SetPoint("BOTTOMLEFT", row._clip, "BOTTOMLEFT", off, 0)
    else
        zone:SetPoint("TOPRIGHT", row._clip, "TOPRIGHT", -off, 0)
        zone:SetPoint("BOTTOMRIGHT", row._clip, "BOTTOMRIGHT", -off, 0)
    end
    zone:SetWidth(zw)
    zone:Show()
end

-- World latency in seconds (home until world is measured), nil when unknown.
local function NetLatency()
    local _, _, home, world = GetNetStats()
    local ms = (world and world > 0) and world or home
    return ms and ms / 1000
end

-- Attack State: Queued Only (the default) colours a queued on-next-swing
-- attack; Full adds On and Waiting. Movement Guide (Segments or Wind-Up Bar):
-- GO on every row, smoothed swing timing, and on a guide row (the Ranged row of
-- a wand or Auto Shot class) STILL as a segment or as its own phase.
local function QueueOn(conf)
    return conf.attackState ~= "off"
end
local function StateFull(conf)
    return conf.attackState == "full"
end
local function GuideOn(conf)
    return conf.moveGuide == "segments" or conf.moveGuide == "windup"
end

local function GuideRow(row, conf)
    return GuideOn(conf) and S.aimClass and row._def.type == SWING.Ranged
end

local function WindRow(row, conf)
    return conf.moveGuide == "windup" and GuideRow(row, conf)
end

local function StillRow(row, conf)
    return conf.moveGuide == "segments" and GuideRow(row, conf)
end

local function StyleZones(row, conf, texPath)
    StyleZone(
        row,
        "lat",
        GuideOn(conf),
        texPath,
        conf.latencyR or 0.949,
        conf.latencyG or 0.957,
        conf.latencyB or 0.969,
        conf.latencyA or 0.9,
        7,
        0
    )
    local c = AIM_COLOR
    StyleZone(
        row,
        "aim",
        StillRow(row, conf),
        texPath,
        conf.aimR or c.r,
        conf.aimG or c.g,
        conf.aimB or c.b,
        conf.aimA or 0.6,
        6,
        -1
    )
end

-- Both zones on a swing, from the latency read at its start (_rtt). A Wind-Up
-- row's swing ends at its aim, not at the shot, so its GO waits for the aim
-- phase (PlaceAimLatency).
local function UpdateZones(row, conf, dur)
    local zones = row._zones
    if not zones then
        return
    end
    local lat, aim = zones.lat, zones.aim
    local rtt = row._rtt or NetLatency() or 0
    if lat then
        if GuideOn(conf) and not row._merged and not WindRow(row, conf) then
            PlaceZone(row, lat, conf, rtt, dur, conf.depleteFill)
        else
            HideZone(lat)
        end
    end
    if aim then
        if StillRow(row, conf) then
            PlaceZone(row, aim, conf, AIM_TIME, dur, conf.depleteFill, rtt)
        else
            HideZone(aim)
        end
    end
end

-- GO at the end of an aim phase, which runs opposite to the swing.
local function PlaceAimLatency(row, conf, from, to)
    local lat = row._zones and row._zones.lat
    if lat and GuideOn(conf) and not row._merged then
        PlaceZone(row, lat, conf, NetLatency(), to - from, not conf.depleteFill)
    end
end

-- Defined with the look below; the swing edges above it repaint through it.
local ApplyRowFill
-- Defined with the edge helpers below; the idle render already writes through it.
local SyncTimeText

-- The auto attack and auto-repeat edges are tracked while a feature reads them:
-- Attack State Full, or the Movement Guide for a wand or Auto Shot class.
local function TracksAttack(conf)
    return StateFull(conf) or (GuideOn(conf) and S.aimClass) or false
end

-- The row's attack is on right now (melee rows: Auto Attack; Ranged: the
-- auto-repeat shot).
local function AttackOn(def)
    if def.melee then
        return S.meleeOn == true
    end
    return S.repeatOn == true
end

-- A row not mid-swing waits (parks full) while its attack is on, under Attack
-- State Full or on a guide row (a held shot). A hidden row (no weapon in the
-- slot) never waits: it would count as live and hold the bar up under Hide
-- When Idle.
local function ShouldWait(row, conf)
    return row:IsShown()
            and row._canSwing ~= false
            and not row._merged
            and AttackOn(row._def)
            and (StateFull(conf) or GuideRow(row, conf))
            and true
        or false
end

-- Idle render: empty (background) by default, full of the fill colour with
-- idleShowFill. The time text is blank (no "0.0"). This is also the disarm:
-- the bar timer is re-armed on a finished duration, whose terminal state is
-- static (RemainingTime paints empty, ElapsedTime full: the GCD bar's idle
-- recipe), so the engine has nothing left to animate. The SetValue keeps the
-- value channel coherent with what is drawn.
local function IdleRow(row, conf)
    if row._waiting or row._aiming then
        row._waiting, row._aiming = nil, nil
        if conf then
            ApplyRowFill(row, conf)
        end
    end
    row._aimAt = nil
    if row._live then
        row._live = nil
        S.live = S.live - 1
        UpdateSpark(row, conf)
    end
    row._end = nil
    local full = conf and conf.idleShowFill == true
    local object = row._durObj
    object:SetTimeFromStart(GetTime() - 1, 1)
    row._bar:SetTimerDuration(object, IMMEDIATE, full and DIR.ElapsedTime or DIR.RemainingTime)
    row._bar:SetValue(full and 1 or 0)
    SyncTimeText(row, conf)
    row._time:SetText("")
    HideZones(row)
end

-- Defined below the waiting state; ArmEdges schedules it at a swing's edges.
local EndEdge

-- A deadline that fires a frame early still counts as its edge: the countdown
-- already reads blank in a swing's last 0.05s.
local END_SLACK = 0.05

-- The deadlines a running row needs: its end; on a guide row Stop by (a
-- Wind-Up row's aim phase, the Text Cue's Still) and, with the Text Cue, the
-- last latency (Go). Each runs EndEdge, which acts only on what is due, so a
-- stale or repeated one does nothing.
local function ArmEdges(row, conf)
    local e = row._end
    if not e then
        return
    end
    local nowTime = GetTime()
    C_Timer.After(math.max(e - nowTime, 0), EndEdge)
    if not GuideRow(row, conf) then
        return
    end
    local a = row._aimAt
    if a and not row._aiming and (conf.moveCue or WindRow(row, conf)) then
        C_Timer.After(math.max(a - nowTime, 0), EndEdge)
    end
    if conf.moveCue then
        local go = e - (row._rtt or 0)
        if go > nowTime then
            C_Timer.After(go - nowTime, EndEdge)
        end
    end
end

-- The Text Cue's Move countdown: a second binding on the row's time text, on a
-- duration object that ends at Stop by, reading Still once it runs out. nil
-- when the client refused the format.
local function CueBind(row)
    if row._cueBind then
        return row._cueBind
    end
    local fmt = row._timeBind and CueFormatter()
    if not fmt then
        return nil
    end
    row._cueObj = C_DurationUtil.CreateDuration()
    local b = C_DurationUtil.CreateDurationTextBinding()
    b:SetFontString(row._time)
    b:SetDuration(row._cueObj)
    b:SetFormatter(fmt)
    b:SetUpdateInterval(0.05)
    b:SetExpiredText(CludesUI.L("Still"))
    b:SetZeroDurationText(CludesUI.L("Still"))
    b:SetEnabled(false)
    row._cueBind, row._cueBindOn = b, false
    return b
end

-- The time text. Mid-swing the engine writes it: the swing's countdown, or with
-- the Text Cue on a guide row the seconds left to move until Stop by, then
-- Still and, in the swing's last latency, Go. Every other state writes its own
-- text with both bindings off. Runs at each edge and on a settings pass.
function SyncTimeText(row, conf)
    local b = row._timeBind
    if not b then
        return
    end
    local phase
    if
        conf
        and conf.showTime ~= false
        and not row._merged
        and row._live
        and not row._waiting
        and not S.sample
    then
        phase = "swing"
        if conf.moveCue and GuideRow(row, conf) then
            local nowTime = GetTime()
            if row._end and row._end - nowTime <= (row._rtt or 0) + END_SLACK then
                phase = "go"
            elseif row._aiming or not (row._aimAt and row._start) or nowTime >= row._aimAt - END_SLACK then
                phase = "still"
            elseif CueBind(row) then
                phase = "move"
            end
        end
    end
    local swingOn = phase == "swing"
    if swingOn then
        -- A Wind-Up row's bar runs only to Stop by; its countdown still runs to
        -- the shot, on a duration object of its own.
        local target = row._durObj
        if not row._aiming and row._start and row._end and WindRow(row, conf) then
            local so = row._swingObj
            if not so then
                so = C_DurationUtil.CreateDuration()
                row._swingObj = so
            end
            so:SetTimeFromStart(row._start, row._end - row._start)
            target = so
        end
        if target ~= row._bindObj then
            row._bindObj = target
            b:SetDuration(target)
        end
    end
    if swingOn ~= row._timeBindOn then
        row._timeBindOn = swingOn
        b:SetEnabled(swingOn)
    end
    local callback = row._cueBind
    local moveOn = phase == "move"
    if moveOn then
        row._cueObj:SetTimeFromStart(row._start, math.max(row._aimAt - row._start, 0.01))
    end
    if callback and moveOn ~= row._cueBindOn then
        row._cueBindOn = moveOn
        callback:SetEnabled(moveOn)
    end
    if swingOn then
        b:UpdateFontString()
    elseif moveOn then
        callback:UpdateFontString()
    elseif phase == "still" then
        row._time:SetText(CludesUI.L("Still"))
    elseif phase == "go" then
        row._time:SetText(CludesUI.L("Go"))
    end
end

-- The fill and the countdown are the engine's: the row's duration object takes
-- this swing, the bar timer animates it every frame with no Lua, draining
-- (Deplete Fill) or filling exactly as the direction says, and the countdown
-- binding writes its remaining time. The end time stays in Lua only for the
-- end edge's deadline; the duration object is never read in Lua. _due (when the
-- next swing is expected) outlives the idle render, so a swing that lands just
-- after the end edge still smooths against it (Movement Guide only). _rtt is
-- the latency read for this swing. A guide row's _aimAt is its Stop by point:
-- AIM_TIME plus one latency before the shot. A Wind-Up row's bar is the reload
-- only, up to _aimAt; a deadline there starts the aim phase.
local function StartRow(row, dur, conf)
    if type(dur) ~= "number" or dur ~= dur or dur <= 0 or dur == math.huge then
        return
    end
    local nowTime = GetTime()
    local start = nowTime
    local due = row._due
    if GuideOn(conf) and due then
        local late = nowTime - due
        if late > -SMOOTH_TOL and late < SMOOTH_TOL then
            start = due + late * SMOOTH_GAIN
        end
    end
    row._end = start + dur
    row._due = row._end
    row._dur = dur
    row._start = start
    row._rtt = NetLatency() or 0
    local wind = WindRow(row, conf)
    row._aimAt = GuideRow(row, conf) and (row._end - AIM_TIME - row._rtt) or nil
    if row._waiting or row._aiming then
        row._waiting, row._aiming = nil, nil
        ApplyRowFill(row, conf)
        UpdateSpark(row, conf)
    end
    if not row._live then
        row._live = true
        S.live = S.live + 1
        UpdateSpark(row, conf)
    end
    local object = row._durObj
    object:SetTimeFromStart(start, wind and math.max(row._aimAt - start, 0.01) or dur)
    row._bar:SetTimerDuration(object, IMMEDIATE, conf.depleteFill and DIR.RemainingTime or DIR.ElapsedTime)
    UpdateZones(row, conf, dur)
    ArmEdges(row, conf)
    SyncTimeText(row, conf)
    if conf.hideWhenIdle and S.live == 1 and mod.ST_UpdateVisibility then
        mod.ST_UpdateVisibility()
    end
end

-- Waiting (attack on, no swing running): parked full, in the Waiting colour
-- under Attack State Full, else the row's own. Entered from a finished swing or
-- from idle (a guide row also from a shot held by moving); the row counts as
-- live (Hide When Idle keeps it) but has no deadline. The next swing
-- (StartRow), an attack-stop edge (IdleRow) or a stop that restarts the aim
-- (EnterAim) ends it, never a timer.
local function EnterWaiting(row, conf)
    row._waiting = true
    row._aiming = nil
    row._end = nil
    if not row._live then
        row._live = true
        S.live = S.live + 1
    end
    local object = row._durObj
    object:SetTimeFromStart(GetTime() - 1, 1)
    row._bar:SetTimerDuration(object, IMMEDIATE, DIR.ElapsedTime)
    row._bar:SetValue(1)
    SyncTimeText(row, conf)
    row._time:SetText(
        (conf.moveCue and conf.showTime ~= false and GuideRow(row, conf)) and CludesUI.L("Still") or ""
    )
    HideZones(row)
    UpdateSpark(row, conf)
    ApplyRowFill(row, conf)
end

-- Aim phase: the half second a wand or Auto Shot needs the player still, plus
-- one latency, as its own fill from `from` to the predicted shot `to`, in the
-- Still colour: a Wind-Up row's every swing from Stop by, and any guide row's
-- restart after a held shot. It runs opposite to the swing so the two join
-- (Deplete Fill: the reload drains, the aim fills), with GO at its end.
local function EnterAim(row, conf, from, to)
    row._waiting = nil
    row._aiming = true
    row._aimFrom = from
    row._end = to
    if not row._live then
        row._live = true
        S.live = S.live + 1
    end
    local object = row._durObj
    object:SetTimeFromStart(from, to - from)
    row._bar:SetTimerDuration(object, IMMEDIATE, conf.depleteFill and DIR.ElapsedTime or DIR.RemainingTime)
    HideZones(row)
    PlaceAimLatency(row, conf, from, to)
    UpdateSpark(row, conf)
    ApplyRowFill(row, conf)
    ArmEdges(row, conf)
    SyncTimeText(row, conf)
end

-- The edges, run by the deadlines ArmEdges schedules: a Wind-Up row's reload
-- done at Stop by starts its aim phase, each row whose swing is over goes idle
-- or waits while its attack is on, a running row's time text takes its next
-- step (the Text Cue's Still and Go), and Hide When Idle hides the bar once no
-- swing runs. No SetValue here, the fill is the engine's.
function EndEdge()
    local conf = P()
    if not (conf and conf.enabled and S.built) then
        return
    end
    local nowTime = GetTime()
    local running = false
    for i = 1, #S.rows do
        local row = S.rows[i]
        -- Wind-Up reload done at Stop by: the aim phase, held while moving, none
        -- once the shot is off (no shot is coming). Segments keeps its bar.
        if
            row._live
            and not row._waiting
            and row._aimAt
            and not row._aiming
            and nowTime >= row._aimAt - END_SLACK
            and WindRow(row, conf)
        then
            if not AttackOn(row._def) then
                IdleRow(row, conf)
            elseif S.moving then
                EnterWaiting(row, conf)
            else
                EnterAim(row, conf, row._aimAt, row._end)
            end
        end
        if row._live and not row._waiting then
            if row._end - nowTime <= END_SLACK then
                if ShouldWait(row, conf) then
                    EnterWaiting(row, conf)
                else
                    IdleRow(row, conf)
                end
            else
                running = true
                SyncTimeText(row, conf)
            end
        end
    end
    if not running and conf.hideWhenIdle and mod.ST_UpdateVisibility then
        mod.ST_UpdateVisibility()
    end
end

-------------------------------------------------------------------------------
--  Layout + look
-------------------------------------------------------------------------------

-- Fill colour: the row's own (or class) colour; the On colour while its auto
-- attack is on (Attack State Full); the queued attack's own colour on a melee
-- row while an on-next-swing attack is queued (not with Attack State Off); the
-- Still colour (opaque) in an aim phase; the Waiting colour while the row waits
-- under Attack State Full (each wins over the ones before). A combined
-- off-hand row paints no fill: its bar keeps running under its spark, unseen.
function ApplyRowFill(row, conf)
    local fillTex = row._bar:GetStatusBarTexture()
    if row._merged then
        mod.ApplyBarFlat(fillTex, 0, 0, 0, 0)
        return
    end
    local def = row._def
    local pend = row._waiting and StateFull(conf)
    local aim = not pend and row._aiming
    local q = not (pend or aim) and QueueRow(def, conf) and S.queued
    local act = not (pend or aim or q) and S.active[def.melee and "melee" or "ranged"]
    local fR, fG, fB, fA
    if pend then
        local c = PENDING_COLOR
        fR, fG, fB, fA = conf.pendingR or c.r, conf.pendingG or c.g, conf.pendingB or c.b, conf.pendingA or 1
    elseif aim then
        local c = AIM_COLOR
        fR, fG, fB, fA = conf.aimR or c.r, conf.aimG or c.g, conf.aimB or c.b, 1
    elseif q then
        local k = q.key
        -- Unset per-ability colour: the shared Queued colour (older profiles).
        if q.shared and conf[k .. "R"] == nil then
            k = q.shared
        end
        fR, fG, fB, fA =
            conf[k .. "R"] or q.r, conf[k .. "G"] or q.g, conf[k .. "B"] or q.b, conf[k .. "A"] or 1
    elseif act then
        local c = ACTIVE_COLOR
        fR, fG, fB, fA = conf.activeR or c.r, conf.activeG or c.g, conf.activeB or c.b, conf.activeA or 1
    else
        fR, fG, fB, fA = RowColor(conf, def)
    end
    if conf.gradientEnabled and not (pend or aim or q or act) then
        mod.ApplyBarGradient(
            fillTex,
            conf.gradientDir or "HORIZONTAL",
            fR,
            fG,
            fB,
            fA,
            conf.gradientR,
            conf.gradientG,
            conf.gradientB,
            conf.gradientA
        )
    else
        mod.ApplyBarFlat(fillTex, fR, fG, fB, fA)
    end
end

-- The slot tag, or "Shield" on an Off Hand row with a shield equipped.
local function TagText(row, conf)
    if row._def.type == SWING.OffHand and row._canSwing == false and ShieldOff(conf) then
        return CludesUI.L("Shield")
    end
    return row._def.tag
end

-- Slot tag, with the queued attack's name on the Main Hand row while one is queued.
-- Written only when the slot text or the queued attack changed: RefreshRows runs
-- this for every row on each weapon and attack speed change.
local function ApplyRowTag(row, conf)
    local def = row._def
    local q = S.queued and QueueRow(def, conf) and S.queued.name or false
    local base = q and def.tag or TagText(row, conf)
    if base == row._tagBase and q == row._tagQueued then
        return
    end
    row._tagBase, row._tagQueued = base, q
    row._tag:SetText(q and (base .. " - " .. q) or base)
end

-- Which on-next-swing attack is queued right now (its S.queueSpells entry), or
-- false. Reads only the names resolved at build; a restricted answer counts as
-- not queued.
local function QueuedSpell()
    local entries = S.queueSpells
    if #entries == 0 or not (C_Spell and C_Spell.IsCurrentSpell) then
        return false
    end
    for i = 1, #entries do
        local current = C_Spell.IsCurrentSpell(entries[i].name)
        if Plain(current) and current then
            return entries[i]
        end
    end
    return false
end

-- Delta paint: touches the melee rows only when the queued attack changed.
local function PaintQueue(conf)
    conf = conf or P()
    if not (conf and S.built) then
        return
    end
    local queued = QueueOn(conf) and QueuedSpell() or false
    if queued == S.queued then
        return
    end
    S.queued = queued
    for i = 1, #S.rows do
        local row = S.rows[i]
        if QueueRow(row._def, conf) then
            ApplyRowFill(row, conf)
            ApplyRowTag(row, conf)
        end
    end
end

-- One-shot read of both states, for the edges this frame was not listening
-- to: the action bars' own auto-repeat test, and Auto Attack as the current
-- spell. The edges keep them current from here.
local function SeedActive()
    S.seeded = true
    local rep = false
    local isRep = C_ActionBar and C_ActionBar.IsAutoRepeatAction
    if isRep then
        for slot = 1, MAX_ACTION_SLOT do
            local val = isRep(slot)
            if Plain(val) and val then
                rep = true
                break
            end
        end
    end
    S.repeatOn = rep
    local current = C_Spell and C_Spell.IsCurrentSpell and C_Spell.IsCurrentSpell(AUTO_ATTACK)
    S.meleeOn = (Plain(current) and current) and true or false
end

-- Delta paint: touches only the rows whose active state flipped.
local function PaintActive(conf)
    conf = conf or P()
    if not (conf and S.built) then
        return
    end
    local on = StateFull(conf)
    local melee = on and S.meleeOn == true
    local ranged = on and S.repeatOn == true
    local A = S.active
    local dMelee, dRanged = melee ~= A.melee, ranged ~= A.ranged
    if not (dMelee or dRanged) then
        return
    end
    A.melee, A.ranged = melee, ranged
    for i = 1, #S.rows do
        local row = S.rows[i]
        if (row._def.melee and dMelee) or (not row._def.melee and dRanged) then
            ApplyRowFill(row, conf)
        end
    end
end

-- Matches every row not mid-swing to its attack: waiting while it is on, idle
-- once it stops. Runs on the attack edges, after a loading screen and when the
-- weapon rows change; a row mid-swing is left to its end edge.
local function SyncWaiting(conf)
    local changed = false
    for i = 1, #S.rows do
        local row = S.rows[i]
        if not (row._live and not row._waiting) then
            if ShouldWait(row, conf) then
                if not row._waiting then
                    EnterWaiting(row, conf)
                    changed = true
                end
            elseif row._waiting then
                IdleRow(row, conf)
                changed = true
            end
        end
    end
    if changed and conf.hideWhenIdle and mod.ST_UpdateVisibility then
        mod.ST_UpdateVisibility()
    end
end

-- Stack the applicable rows and size the frame to them; a combined off-hand
-- row is laid over the Main Hand row instead of taking a slot. Returns true
-- when the frame height changed (anchored neighbours need a nudge).
local function Layout(conf)
    local hgt = conf.height or 12
    local sp = RowGap(conf)
    local wid = conf.width or 220
    local position = 0
    for i = 1, #S.rows do
        local row = S.rows[i]
        if row:IsShown() then
            row:ClearAllPoints()
            if row._merged then
                row:SetAllPoints(S.byType[SWING.MainHand])
            else
                row:SetPoint("TOPLEFT", shell, "TOPLEFT", 0, -position * (hgt + sp))
                row:SetSize(wid, hgt)
                position = position + 1
            end
        end
    end
    S.shown = position
    local num = math.max(position, 1)
    local totalH = num * hgt + (num - 1) * sp
    shell:SetSize(wid, totalH)
    local changed = S.lastH ~= nil and S.lastH ~= totalH
    S.lastH = totalH
    return changed
end

-- Stock styles: the row's stock frame round its bar (the Blizzard Style panel
-- or the Classic WoW UI frame, ns.ERB_ApplyBlizzBarChrome), built on first
-- use. Under Blizzard Style the bar-shape mask also takes the fill and the
-- GO / STILL zones. A combined off-hand row is only a spark over the Main
-- Hand row: its frame takes alpha 0 (ApplyRangeLook) and its bevel hides.
local function StockChrome(row, conf, wid, hgt)
    local barFrame = row._bar
    if row._merged then
        local sh = barFrame._blizzShadow
        if sh then
            for i = 1, 4 do
                sh[i]:Hide()
            end
        end
        return
    end
    mod.ERB_ApplyBlizzBarChrome(row, barFrame, wid, hgt, false, mod.ERB_ClassicFrameK(conf))
    local mask = row._blizzBarMask
    if mask then
        mod.ERB_SeatBlizzMask(row, barFrame)
        local zones = row._zones
        if zones then
            for _, z in pairs(zones) do
                mod.ERB_MaskTex(z.back, mask)
                mod.ERB_MaskTex(z.front, mask)
            end
        end
    end
    -- The vanilla frame art sits at the row's level + 9, over the bar's ends.
    if mod.ERB_BarsClassic() then
        row._textFrame:SetFrameLevel(row:GetFrameLevel() + 10)
    end
end

-- Tag visibility: Show Weapon Label, not on a combined off hand, and with Hide
-- Label Without Weapon not on a weaponless row (a shield keeps its tag).
local function ApplyRowLabel(row, conf)
    local show = conf.showLabel ~= false and not row._merged
    if
        show
        and conf.hideLabelNoWeapon
        and row._canSwing == false
        and not (row._def.type == SWING.OffHand and ShieldOff(conf))
    then
        show = false
    end
    ApplyRowTag(row, conf)
    if show then
        row._tag:Show()
    else
        row._tag:Hide()
    end
end

local function ApplyRowLook(row, conf, wid, hgt)
    row._restyle = nil
    local Pix = CludesUI.PP
    -- A stock style's frame (StockChrome) replaces the CUI border.
    local stock = mod.ST_Style() ~= "cui"
    local bs = (not stock and conf.borderSize) or 0
    local bdr = row._border
    local pl = row:GetFrameLevel()
    bdr:SetFrameLevel(conf.borderBehind and math.max(0, pl - 1) or (pl + 5))
    -- Lost-rect recovery, see the cast bar border in the main file.
    if not bdr:GetLeft() then
        bdr:SetAllPoints(row)
    end
    if stock then
        CludesUI.ApplyBorderStyle(bdr, 0, 0, 0, 0, 0, "solid")
    else
        CludesUI.ApplyBorderStyle(
            bdr,
            bs,
            conf.borderR or 0,
            conf.borderG or 0,
            conf.borderB or 0,
            conf.borderA or 1,
            conf.borderTexture or "solid",
            conf.borderTextureOffset,
            conf.borderTextureOffsetY,
            conf.borderTextureShiftX,
            conf.borderTextureShiftY,
            "resourcebars",
            bs,
            nil,
            CludesUI.BorderPx(conf.borderSizePx, bs, conf.borderTexture or "solid")
        )
    end

    -- Clip + bar layout. The 1px inset keeps the fill from bleeding past the
    -- border; with no border there is nothing to clip to, so skip it.
    local clip, barFrame = row._clip, row._bar
    local inset = (bs > 0 and Pix and Pix.mult) or 0
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", row, "TOPLEFT", inset, -inset)
    clip:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -inset, inset)
    clip:SetFrameLevel(pl + 1)
    barFrame:ClearAllPoints()
    barFrame:SetAllPoints(clip)

    local texPath =
        CludesUI.ResolveTexturePath(_G._CURB_BarTextures, conf.texture, "Interface\\Buttons\\WHITE8x8")
    barFrame:SetStatusBarTexture(texPath)
    barFrame:SetOrientation("HORIZONTAL")
    barFrame:SetRotatesTexture(false)
    barFrame:SetReverseFill(false)
    row._bg:SetTexture(nil)
    row._bg:SetColorTexture(conf.bgR or 0, conf.bgG or 0, conf.bgB or 0, conf.bgA or 0.7)
    StyleZones(row, conf, texPath)
    if stock then
        StockChrome(row, conf, wid, hgt)
    end

    ApplyRowFill(row, conf)

    -- Leading-edge spark: anchored to the fill texture's moving edge so it
    -- tracks the fill (the GCD bar's horizontal case). On a combined off-hand
    -- row it is the whole display. An overhang reaches past the bar's top and
    -- bottom: the spark leaves the bar's clip (and the rounded body) for a clip
    -- of its own, built on first use, that still cuts it at the bar's ends.
    local spark, sparkFrame = row._spark, row._sparkFrame
    local over = conf.sparkOverhang or 0
    if over > 0 then
        local sc = row._sparkClip
        if not sc then
            sc = CreateFrame("Frame", nil, row)
            sc:SetClipsChildren(true)
            row._sparkClip = sc
        end
        sc:ClearAllPoints()
        sc:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, over)
        sc:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, -over)
        sc:SetFrameLevel(barFrame:GetFrameLevel() + 1)
        sparkFrame:SetParent(sc)
    else
        sparkFrame:SetParent(clip)
    end
    sparkFrame:SetFrameLevel(barFrame:GetFrameLevel() + 2)
    spark:ClearAllPoints()
    spark:SetSize(conf.sparkWidth or 8, hgt + 2 * over)
    spark:SetPoint("CENTER", barFrame:GetStatusBarTexture(), "RIGHT", 0, 0)
    spark:SetVertexColor(SparkColor(conf, row._def, row._merged))
    UpdateSpark(row, conf)

    local size = conf.textSize or 11
    mod.SetRBFont(row._tag, mod.GetRBFont(), size)
    mod.SetRBFont(row._time, mod.GetRBFont(), size)
    -- Label on the left, time on the right, each with its own offsets.
    row._tag:ClearAllPoints()
    row._tag:SetPoint("LEFT", row, "LEFT", 4 + (conf.labelX or 0), conf.labelY or 0)
    row._time:ClearAllPoints()
    row._time:SetPoint("RIGHT", row, "RIGHT", -4 + (conf.timeX or 0), conf.timeY or 0)
    ApplyRowTag(row, conf)
    -- A combined off-hand row shows no text; the Main Hand row keeps its own.
    local merged = row._merged
    ApplyRowLabel(row, conf)
    if conf.showTime ~= false and not merged then
        row._time:Show()
    else
        row._time:Hide()
    end
    ApplyRangeLook(row, conf)
    -- Rounded corners (CludesUI_RoundedCorners.lua; nothing at radius 0).
    -- A combined off-hand row is only a spark over the Main Hand row: no fill.
    -- The stock frames are square.
    local radius = (not stock and conf.cornerRadius) or 0
    if radius > 0 then
        CludesUI.RoundCorners(row, radius, {
            roots = { clip },
            textures = { row._bg },
            border = not merged and bdr or nil,
            clip = clip,
            style = conf.borderTexture or "solid",
            corners = conf.cornerMask,
        })
    else
        CludesUI.RoundCorners(row, 0)
    end
end

local function ApplyLook(conf)
    local wid, hgt = conf.width or 220, conf.height or 12
    for i = 1, #S.rows do
        ApplyRowLook(S.rows[i], conf, wid, hgt)
    end
end

-- Restyles the rows RefreshRows marked (see there).
local function RestyleMarked(conf)
    local wid, hgt = conf.width or 220, conf.height or 12
    for i = 1, #S.rows do
        local row = S.rows[i]
        if row._restyle then
            ApplyRowLook(row, conf, wid, hgt)
        end
    end
end

-- Show/hide rows to the weapon slots, then re-stack. Also the range-check
-- registration: on for every shown row while the option is on, off otherwise
-- (a combined off hand keeps its own: it still needs its swings, and its range
-- dims its spark). Combine Hands merges the Off Hand row only while the Main
-- Hand row is shown too (ROWS puts Main Hand first). Marks the rows whose
-- merge flipped or that just came back (styled while hidden at 0x0, their
-- textured border never painted) and returns true when any was marked:
-- ST_Apply restyles every row once the frame is placed, the events restyle
-- just those (RestyleMarked), so an off hand equipped or dropped mid-session
-- takes the right look without an options apply.
local function RefreshRows(conf)
    conf = conf or P()
    if not (conf and S.built) then
        return
    end
    local wantRange = conf.enabled and conf.rangeCheck ~= false
    local mhShown, marked = false, false
    for i = 1, #S.rows do
        local row = S.rows[i]
        local def = row._def
        local can = RowWanted(def, conf, row)
        ApplyRowLabel(row, conf)
        if can then
            if not row:IsShown() then
                row._restyle = true
                marked = true
            end
            row:Show()
        else
            row:Hide()
            if row._live then
                IdleRow(row, conf)
            end
        end
        if def.type == SWING.MainHand then
            mhShown = can
        end
        local merged = (
            def.type == SWING.OffHand
            and can
            and mhShown
            and conf.combineHands
            and not ShieldOff(conf)
        )
                and true
            or nil
        if merged ~= row._merged then
            row._merged = merged
            row._restyle = true
            marked = true
        end
        SetRangeCheck(def.type, wantRange and can)
    end
    if Layout(conf) and CludesUI.NotifyElementResized then
        CludesUI.NotifyElementResized(UNLOCK_KEY)
    end
    UpdateRangeAll()
    return marked
end

-- Position: the unlock anchor chain first, then a saved unlock position, then
-- the CENTER offsets. Same three-way split as the GCD bar.
local function ApplyPosition(conf)
    local wid, hgt = Size(conf)
    shell:SetSize(wid, hgt)
    if CludesUI._TryOverrideAnchor and CludesUI._TryOverrideAnchor(UNLOCK_KEY, shell) then
        return
    end
    if CludesUI._unlockActive then
        return
    end
    local place = conf.unlockPos
    if place and place.point then
        local anchored = CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(UNLOCK_KEY)
        if anchored and shell:GetLeft() then
            return
        end
        local rp = place.relPoint or place.point
        local sx, sy = mod.SnapXY(place.x or 0, place.y or 0, shell, place)
        shell:ClearAllPoints()
        shell:SetPoint(place.point, UIParent, rp, sx, sy)
    else
        shell:ClearAllPoints()
        shell:SetPoint("CENTER", UIParent, "CENTER", conf.anchorX or 0, conf.anchorY or 0)
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------

-- The movement edges a guide row holds and restarts its aim on, only while an
-- aim can run: the Movement Guide on, a wand or Auto Shot class, and the shot on.
-- Registering reads where the player is now (GetUnitSpeed, restricted = still).
local function ApplyMoveEvents(conf)
    if not S.events then
        return
    end
    if S.aimClass and GuideOn(conf) and S.repeatOn then
        if not S.moveEvents then
            S.moveEvents = true
            shell:RegisterEvent("PLAYER_STARTED_MOVING")
            shell:RegisterEvent("PLAYER_STOPPED_MOVING")
            local speed = GetUnitSpeed("player")
            S.moving = (Plain(speed) and speed > 0) and true or false
        end
    elseif S.moveEvents then
        S.moveEvents = nil
        shell:UnregisterEvent("PLAYER_STARTED_MOVING")
        shell:UnregisterEvent("PLAYER_STOPPED_MOVING")
        S.moving = false
    end
end

shell:SetScript("OnEvent", function(self, evt, a1, a2, a3)
    local conf = P()
    if not (conf and conf.enabled and S.built) then
        return
    end
    if evt == "PLAYER_SWING" then
        -- a1 = swingDuration, a2 = swingType
        if not (Plain(a1) and Plain(a2)) then
            return
        end
        local row = S.byType[a2]
        if row then
            -- A swing proves its slot can swing: a row hidden only because its
            -- speed read was restricted comes back with it.
            if not row:IsShown() and not row._canSwing and conf[row._def.show] ~= false then
                row._canSwing = true
                if RefreshRows(conf) then
                    RestyleMarked(conf)
                end
            end
            if row:IsShown() then
                StartRow(row, a1, conf)
            end
        end
        PaintQueue(conf)
    elseif evt == "ACTIONBAR_UPDATE_STATE" then
        PaintQueue(conf)
    elseif evt == "START_AUTOREPEAT_SPELL" or evt == "STOP_AUTOREPEAT_SPELL" then
        S.repeatOn = evt == "START_AUTOREPEAT_SPELL"
        if not S.repeatOn then
            -- No shot is coming: an aim in progress ends with it.
            local row = S.byType[SWING.Ranged]
            if row and row._aiming then
                IdleRow(row, conf)
            end
        end
        ApplyMoveEvents(conf)
        SyncWaiting(conf)
        PaintActive(conf)
    elseif evt == "PLAYER_STARTED_MOVING" then
        -- Moving holds the shot: an aim in progress stops and waits.
        S.moving = true
        local row = S.byType[SWING.Ranged]
        if row and row._aiming then
            EnterWaiting(row, conf)
        end
    elseif evt == "PLAYER_STOPPED_MOVING" then
        -- Standing still again: a shot held, or stopped for only after Stop by,
        -- fires AIM_TIME from now plus the round trip (the stop reaches the
        -- server, the swing comes back). Both guide styles show it as an aim.
        S.moving = false
        local row = S.byType[SWING.Ranged]
        if row and row._live and GuideRow(row, conf) and AttackOn(row._def) then
            local nowTime = GetTime()
            if row._waiting or (row._aimAt and not row._aiming and nowTime >= row._aimAt) then
                local shot = nowTime + AIM_TIME + (NetLatency() or 0)
                if row._end and row._end > shot then
                    shot = row._end
                end
                EnterAim(row, conf, nowTime, shot)
                row._due = shot
            end
        end
    elseif evt == "PLAYER_ENTER_COMBAT" or evt == "PLAYER_LEAVE_COMBAT" then
        S.meleeOn = evt == "PLAYER_ENTER_COMBAT"
        SyncWaiting(conf)
        PaintActive(conf)
    elseif evt == "PLAYER_DEAD" then
        for i = 1, #S.rows do
            if S.rows[i]._live then
                IdleRow(S.rows[i], conf)
            end
        end
        S.meleeOn, S.repeatOn = false, false
        ApplyMoveEvents(conf)
        PaintActive(conf)
    elseif evt == "PLAYER_SWING_RANGE_UPDATE" then
        -- a1 = swingType, a2 = isInRange, a3 = checksRange
        if not (Plain(a1) and Plain(a2) and Plain(a3)) then
            return
        end
        local row = S.byType[a1]
        if row then
            SetOutOfRange(row, a3 == true and a2 == false)
        end
    elseif evt == "PLAYER_TARGET_CHANGED" then
        -- Re-assert the range flags before the re-read (see SetRangeCheck).
        local wantRange = conf.rangeCheck ~= false
        for i = 1, #S.rows do
            local row = S.rows[i]
            SetRangeCheck(row._def.type, wantRange and row:IsShown())
        end
        UpdateRangeAll()
    else
        -- WEAPON_SLOT_CHANGED / PLAYER_EQUIPMENT_CHANGED (off hand slot only) /
        -- UNIT_ATTACK_SPEED / PLAYER_ENTERING_WORLD
        if evt == "PLAYER_EQUIPMENT_CHANGED" and a1 ~= OFFHAND_SLOT then
            return
        end
        if RefreshRows(conf) then
            RestyleMarked(conf)
        end
        if TracksAttack(conf) then
            -- A loading screen can end an attack without its edge reaching us.
            if evt == "PLAYER_ENTERING_WORLD" then
                SeedActive()
                ApplyMoveEvents(conf)
            end
            -- A row the weapon change just showed takes its attack's state.
            SyncWaiting(conf)
            PaintActive(conf)
        end
    end
end)

local function RegisterEvents()
    if S.events then
        return
    end
    S.events = true
    shell:RegisterEvent("PLAYER_SWING")
    shell:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
    shell:RegisterEvent("PLAYER_TARGET_CHANGED")
    shell:RegisterEvent("WEAPON_SLOT_CHANGED")
    shell:RegisterEvent("PLAYER_ENTERING_WORLD")
    shell:RegisterEvent("PLAYER_DEAD")
    shell:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
end

-- The queue paint's event is registered only while the highlight is on (it is
-- the one chatty event here).
local function ApplyQueueEvents(conf)
    if not S.events then
        return
    end
    if QueueOn(conf) and #S.queueSpells > 0 then
        shell:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    else
        shell:UnregisterEvent("ACTIONBAR_UPDATE_STATE")
    end
end

-- Equipment changes matter only to the shield handling.
local function ApplyShieldEvents(conf)
    if not S.events then
        return
    end
    if ShieldAware(conf) then
        shell:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    else
        shell:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
    end
end

-- The auto attack and auto-repeat edges, only while something reads them
-- (TracksAttack).
local function ApplyActiveEvents(conf)
    if not S.events then
        return
    end
    if TracksAttack(conf) then
        shell:RegisterEvent("START_AUTOREPEAT_SPELL")
        shell:RegisterEvent("STOP_AUTOREPEAT_SPELL")
        shell:RegisterEvent("PLAYER_ENTER_COMBAT")
        shell:RegisterEvent("PLAYER_LEAVE_COMBAT")
    else
        shell:UnregisterEvent("START_AUTOREPEAT_SPELL")
        shell:UnregisterEvent("STOP_AUTOREPEAT_SPELL")
        shell:UnregisterEvent("PLAYER_ENTER_COMBAT")
        shell:UnregisterEvent("PLAYER_LEAVE_COMBAT")
    end
end

local function UnregisterEvents()
    if not S.events then
        return
    end
    S.events = nil
    S.moveEvents, S.moving = nil, false
    shell:UnregisterAllEvents()
end

-------------------------------------------------------------------------------
--  Build / apply
-------------------------------------------------------------------------------

local function EnsureBuilt()
    if S.built then
        return
    end
    S.built = true
    shell:SetFrameLevel(15)
    for i = 1, #ROWS do
        local row = BuildRow(ROWS[i])
        S.rows[i] = row
        S.byType[ROWS[i].type] = row
    end
    local _, class = UnitClass("player")
    S.aimClass = AIM_CLASS[class]
    -- On-next-swing spell names, once per session, for a class that has one.
    local ids = CludesUI.FOREVER_NEXT_SWING and CludesUI.FOREVER_NEXT_SWING[class]
    if ids and C_Spell and C_Spell.GetSpellName then
        for i = 1, #ids do
            local name = C_Spell.GetSpellName(ids[i])
            if Plain(name) and name then
                local c = QUEUE_COLORS[ids[i]] or QUEUE_COLOR
                S.queueSpells[#S.queueSpells + 1] =
                    { id = ids[i], key = c.key, shared = c.shared, r = c.r, g = c.g, b = c.b, name = name }
            end
        end
    end
    -- Mouseover hover-reveal: same plain-table proxy the class/power/health bars
    -- register, gated on the eligibility flag ST_UpdateVisibility maintains.
    if not S.moHooked and CludesUI.RegisterMouseoverTarget then
        S.moHooked = true
        local proxy = {}
        proxy.GetRect = function()
            return shell:GetRect()
        end
        proxy.GetEffectiveScale = function()
            return shell:GetEffectiveScale()
        end
        proxy.SetAlpha = function() end
        proxy.EnableMouse = function() end
        proxy.Show = function()
            CludesUI.SetElementVisibility(shell, true)
        end
        proxy.Hide = function()
            CludesUI.SetElementVisibility(shell, false)
        end
        CludesUI.RegisterMouseoverTarget(proxy, function()
            local ERB = mod.ERB
            return ERB and ERB._moEligible and ERB._moEligible[MO_KEY] or false
        end)
    end
end

-- Off: drop events and range checks, and idle every live row (its bar timer is
-- parked on a finished duration, its countdown off; a pending end-edge deadline
-- finds the timer off and does nothing); the frame stays shown at alpha 0
-- so anchored neighbours keep a valid rect (SetElementVisibility rule).
local function Teardown()
    if not S.built then
        return
    end
    UnregisterEvents()
    S.seeded = nil -- the edges stop here: re-read on the next enable
    local conf = P()
    for i = 1, #S.rows do
        local row = S.rows[i]
        if row._live then
            IdleRow(row, conf)
        end
        SetRangeCheck(row._def.type, false)
    end
    local ERB = mod.ERB
    if ERB and ERB._moEligible then
        ERB._moEligible[MO_KEY] = false
    end
    CludesUI.SetElementVisibility(shell, false)
end

-- A running timer's events and attack state: the full apply and a resume
-- after a park both start here.
local function Arm(conf)
    RegisterEvents()
    ApplyQueueEvents(conf)
    ApplyActiveEvents(conf)
    ApplyShieldEvents(conf)
    -- Highlight turned off with an attack queued: the paint below must clear it.
    if not QueueOn(conf) then
        S.queued = false
    end
    -- Attack state: read once per enable, kept by the edges while on.
    if not TracksAttack(conf) then
        S.seeded = nil
    elseif not S.seeded then
        SeedActive()
    end
    ApplyMoveEvents(conf)
end

-- Every row takes its paint here on every apply, always by re-arming the
-- bar timer, never by a plain SetValue: a parked timer keeps painting its
-- terminal state and SetValue does not repaint it (the GCD bar's idle
-- recipe). Unlock movers up: a full bar with a sample time. A row
-- mid-swing: its running swing (or Wind-Up reload / aim phase) again, in
-- the direction now configured (unlock exit, a Deplete Fill or Movement
-- Guide change). A row whose attack is on: parked
-- full (waiting), also when the option just came on mid-attack. Otherwise
-- the idle render, so a Show Fill Color When Idle change shows at once, not
-- at the next swing's end.
local function PaintRows(conf)
    for i = 1, #S.rows do
        local row = S.rows[i]
        local object = row._durObj
        if S.sample then
            -- A combined off hand parks empty, so its spark shows at the far
            -- end from a full Main Hand bar's.
            local oh = row._merged
            object:SetTimeFromStart(GetTime() - 1, 1)
            row._bar:SetTimerDuration(object, IMMEDIATE, oh and DIR.RemainingTime or DIR.ElapsedTime)
            row._bar:SetValue(oh and 0 or 1)
            SyncTimeText(row, conf)
            row._time:SetText("1.2")
            UpdateZones(row, conf, row._dur or 2)
        elseif row._live and not row._waiting and row._dur then
            local guide, wind = GuideRow(row, conf), WindRow(row, conf)
            if not guide and (row._aiming or row._aimAt) then
                -- Movement Guide turned off mid-swing: back to one plain swing.
                row._aiming, row._aimAt = nil, nil
                ApplyRowFill(row, conf)
            end
            if row._aiming then
                object:SetTimeFromStart(row._aimFrom, row._end - row._aimFrom)
                row._bar:SetTimerDuration(
                    object,
                    IMMEDIATE,
                    conf.depleteFill and DIR.ElapsedTime or DIR.RemainingTime
                )
                HideZones(row)
                PlaceAimLatency(row, conf, row._aimFrom, row._end)
            else
                local start = row._end - row._dur
                row._start = start
                if guide then
                    row._aimAt = row._end - AIM_TIME - (row._rtt or 0)
                end
                object:SetTimeFromStart(start, wind and math.max(row._aimAt - start, 0.01) or row._dur)
                row._bar:SetTimerDuration(
                    object,
                    IMMEDIATE,
                    conf.depleteFill and DIR.RemainingTime or DIR.ElapsedTime
                )
                UpdateZones(row, conf, row._dur)
            end
            ArmEdges(row, conf)
            SyncTimeText(row, conf)
        elseif ShouldWait(row, conf) then
            EnterWaiting(row, conf)
        else
            IdleRow(row, conf)
        end
    end
end

-- Back from a park (a shapeshift or talent edit that no longer rules the timer
-- out): events and the row state come back. The rows kept their spot and look
-- while parked (a settings change made then runs the full apply, which styles
-- them), so only rows that came back are restyled.
local function Resume(conf)
    Arm(conf)
    if RefreshRows(conf) then
        RestyleMarked(conf)
    end
    PaintQueue(conf)
    PaintActive(conf)
    PaintRows(conf)
end

-- Visibility pass: runs from the main file's UpdateVisibility on every edge it
-- sees (combat, target, group, zone, shapeshift, the debounced pass after a
-- talent edit, custom conditional) and from the swing edges hideWhenIdle cares
-- about. A form or talent change that moves the gate (RuledOut) parks the timer
-- (Teardown) or resumes it; Unlock Mode keeps it running either way, and
-- leaving Unlock Mode runs the full apply, which parks it while ruled out.
function mod.ST_UpdateVisibility()
    if not S.built then
        return
    end
    local conf = P()
    local ERB = mod.ERB
    if not (conf and conf.enabled and ERB) then
        return
    end
    local ruled = RuledOut(conf)
    if ruled ~= (S.ruled or false) then
        -- Set first: the row edges below can run this pass again.
        S.ruled = ruled
        if not CludesUI._unlockActive then
            if ruled then
                Teardown()
            else
                Resume(conf)
            end
        end
    end
    local vis
    if CludesUI._unlockActive then
        vis = true
    elseif S.ruled then
        vis = false
    else
        vis = not ERB._inVehicle and mod.ShouldShowBar(conf)
        if vis and conf.hideWhenIdle and S.live == 0 then
            vis = false
        end
    end
    ERB._moEligible = ERB._moEligible or {}
    ERB._moEligible[MO_KEY] = (vis == "mouseover")
    CludesUI.SetElementVisibility(shell, vis == true)
end

-- The colour a row's spark paints (by colour key), for the options swatch;
-- unset = true gives the tint it has without a colour of its own.
function mod.ST_SparkColor(key, unset)
    local conf = P()
    if not conf then
        return 1, 1, 1, 1
    end
    for i = 1, #ROWS do
        if ROWS[i].key == key then
            local row = S.rows[i]
            return SparkColor(conf, ROWS[i], row and row._merged, unset)
        end
    end
    return 1, 1, 1, 1
end

-- Talent edits (Resource Bars' TRAIT_CONFIG_UPDATED / PLAYER_TALENT_UPDATE)
-- and the apply after each loading screen (a login read can come before the
-- talent data is in): the shared talent check's cache is read again, by the
-- debounced visibility pass after an edit and by that apply.
function mod.ST_TalentChanged()
    local conf = P()
    if conf and conf.enabled and HasTalentConds(conf) then
        CludesUI.TalentCondInvalidate()
    end
end

function mod.ST_Apply()
    local conf = P()
    if not conf or not conf.enabled then
        S.ruled = nil
        Teardown()
        return
    end
    S.ruled = RuledOut(conf)
    -- Ruled out by form or talents (outside Unlock Mode, which shows it with its
    -- sample): laid out and styled as usual, so anchored elements keep their
    -- spot and a resume needs no restyle, then parked like switched off (no
    -- events, every row idle, alpha 0).
    local park = S.ruled and not CludesUI._unlockActive
    EnsureBuilt()
    shell:SetFrameStrata(conf.frameStrata or "MEDIUM")
    shell:Show()
    if not park then
        Arm(conf)
    end
    -- Size and stack the rows BEFORE styling them: the textured border is a
    -- BackdropTemplate nine-slice keyed on first setup, and set up on a 0x0
    -- row it never paints (cast/GCD bars size first for the same reason).
    RefreshRows(conf)
    ApplyPosition(conf)
    ApplyLook(conf)
    if park then
        Teardown()
        return
    end
    PaintQueue(conf)
    PaintActive(conf)
    PaintRows(conf)
    mod.ST_UpdateVisibility()
end

-------------------------------------------------------------------------------
--  Unlock element
-------------------------------------------------------------------------------

function mod.ST_MakeUnlockElement(MK, Rebuild)
    if not MK then
        return nil
    end
    local Pix = CludesUI.PP

    if not S.unlockHooked and CludesUI.RegisterUnlockModeListener then
        S.unlockHooked = true
        CludesUI:RegisterUnlockModeListener(UNLOCK_KEY, function(isActive)
            -- Sample fill while the movers are up so an idle bar has something
            -- to drag; ST_Apply restores the real state on exit.
            S.sample = isActive and true or nil
            if mod.ST_Apply then
                mod.ST_Apply()
            end
        end)
    end

    local function save(key, anchorPoint, relPoint, posX, posY)
        if not anchorPoint then
            return
        end
        local conf = P()
        if not conf then
            return
        end
        conf.unlockPos = { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
        if not CludesUI._unlockActive and S.built then
            shell:ClearAllPoints()
            shell:SetPoint(anchorPoint, UIParent, relPoint or anchorPoint, posX, posY)
        end
    end
    local function load()
        local conf = P()
        local place = conf and conf.unlockPos
        if not place then
            return nil
        end
        return { point = place.point, relPoint = place.relPoint or place.point, x = place.x, y = place.y }
    end
    local function clear()
        local conf = P()
        if not conf then
            return
        end
        conf.unlockPos = nil
        conf.anchorX = 0
        conf.anchorY = -130
    end
    local function apply()
        local conf = P()
        local place = conf and conf.unlockPos
        if not (place and S.built) then
            return
        end
        local sx, sy = mod.SnapXY(place.x, place.y, shell, place)
        shell:ClearAllPoints()
        shell:SetPoint(place.point, UIParent, place.relPoint or place.point, sx, sy)
    end

    return MK({
        key = UNLOCK_KEY,
        label = "Swing Timer",
        group = "Resource Bars",
        order = 508,
        getFrame = function()
            return S.built and shell or nil
        end,
        isHidden = function()
            local conf = P()
            return not (conf and conf.enabled)
        end,
        getSize = function()
            return Size(P())
        end,
        -- What a row draws outside itself: every row spans the full width and
        -- the outer rows' edges are the stack's, so one row's reach. A stock
        -- style's frame rim, else the textured border (ns.ERB_EuiBorderPad).
        getMatchPad = function()
            local conf = P()
            local style = mod.ST_Style()
            if style == "blizzard" then
                return mod.ERB_BlizzMatchPad(false)
            end
            if style == "classic" then
                return mod.ERB_ClassicMatchPad(0, 0, false, mod.ERB_ClassicFrameK(conf))
            end
            return mod.ERB_EuiBorderPad(conf)
        end,
        -- Rebuild is a full ApplyAll and the settle pass hands the size again
        -- after every resize burst: an unchanged size rebuilds nothing.
        setWidth = function(_, wid)
            local conf = P()
            if not conf then
                return
            end
            local val = Pix.Snap(math.max(wid, 10))
            if conf.width == val then
                return
            end
            conf.width = val
            Rebuild()
        end,
        -- The mover resizes the whole stack; the per-row height is what is stored.
        setHeight = function(_, hgt)
            local conf = P()
            if not conf then
                return
            end
            -- A spec layout holds the stack height of the character that saved
            -- it, whose row count can differ; the row height is the profile's.
            if CludesUI._unlockLayerApplying then
                return
            end
            local num = ShownCount()
            local sp = RowGap(conf)
            local val = Pix.Snap(math.max((hgt - (num - 1) * sp) / num, 4))
            if conf.height == val then
                return
            end
            conf.height = val
            Rebuild()
        end,
        savePos = save,
        loadPos = load,
        clearPos = clear,
        applyPos = apply,
    })
end
