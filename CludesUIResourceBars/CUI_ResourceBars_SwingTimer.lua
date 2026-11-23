if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
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
    -- Target Swing (off by default, showTGT): the current hostile target's own
    -- swing, started by its physical hits landing on the player (UNIT_COMBAT,
    -- while the player is its target) and sped up by its parries. No range
    -- check, attack state, seal or window: none of them are the player's.
    { type = "target", key = "tgt", tag = "TGT", show = "showTGT", target = true },
}

-- Target Swing: the hits that mark the target's swing (UNIT_COMBAT actions on
-- the player, physical school only) and the parry haste rule: a parry with
-- more than PARRY_HIGH of the swing left takes PARRY_CUT of the swing off it,
-- with more than PARRY_LOW left it cuts it to PARRY_LOW, else nothing.
local TARGET_HITS = {
    WOUND = true,
    MISS = true,
    DODGE = true,
    PARRY = true,
    BLOCK = true,
    DEFLECT = true,
    ABSORB = true,
    IMMUNE = true,
    EVADE = true,
}
local PHYSICAL = 1
local PARRY_HIGH, PARRY_CUT, PARRY_LOW = 0.6, 0.4, 0.2

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

-- Seal Colors (paladin): while a seal is up the melee rows take its colour
-- (sealRighteousR/G/B/A, ...), so the swing that carries it is visible. Seals
-- are matched by name, so every rank counts; names resolve once per session,
-- for a paladin only. The aura is followed through UNIT_AURA's update info
-- (added / updated / removed, by auraInstanceID) whenever the client lets
-- auras be read, combat included; a seal cast while they are secret is taken
-- from UNIT_SPELLCAST_SUCCEEDED and runs out on a timer of its last known
-- length (SEAL_TIME until one is read).
local SEALS = {
    { id = 20154, key = "sealRighteous", r = 0.95, g = 0.85, b = 0.40 }, -- Seal of Righteousness
    { id = 21082, key = "sealCrusader", r = 0.95, g = 0.55, b = 0.20 }, -- Seal of the Crusader
    { id = 20375, key = "sealCommand", r = 0.75, g = 0.35, b = 0.95 }, -- Seal of Command
    { id = 20164, key = "sealJustice", r = 0.60, g = 0.65, b = 0.75 }, -- Seal of Justice
    { id = 20165, key = "sealLight", r = 1, g = 0.95, b = 0.70 }, -- Seal of Light
    { id = 20166, key = "sealWisdom", r = 0.35, g = 0.65, b = 1 }, -- Seal of Wisdom
    { id = 1311649, key = "sealFury", r = 0.95, g = 0.25, b = 0.20 }, -- Seal of Fury
    { id = 407798, key = "sealMartyrdom", r = 0.90, g = 0.40, b = 0.70 }, -- Seal of Martyrdom
}
local SEAL_TIME = 30
local MAX_AURAS = 40

-- Swing Window: the last swingWindowTime seconds of each melee swing (plus one
-- latency with windowLatency), the time left to queue an attack onto it.
local WINDOW_TIME = 0.4
local WINDOW_COLOR = { r = 1, g = 1, b = 1, a = 0.35 }

-- Cast Clip: a tick on the Main Hand row where the cast in progress ends; it
-- turns red when the cast runs past the swing (the swing waits for it).
local CAST_OK = { r = 1, g = 1, b = 1 }
local CAST_BAD = { r = 1, g = 0.15, b = 0.15 }
local TICK_WIDTH = 2
local CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP",
}

-- Shell at FILE SCOPE (attribution rule, see _erbEventFrame in the main file):
-- the OnEvent work bills ResourceBars. Children stay lazy.
local shellFrame = CreateFrame("Frame", "ERB_SwingTimerFrame", UIParent)
shellFrame:Hide()

-- built, rows[i] (row frames in ROWS order), byType[swingType] = row, shown (rows
-- stacked on screen; a combined off hand takes no slot), live (rows mid-swing),
-- rangeOn[swingType] = bool, sample (unlock mode preview on), moHooked,
-- unlockHooked, lastH (frame height last laid out), queueSpells (this class's
-- on-next-swing attacks: id, colour key + fallback, resolved name), queued (the
-- entry painted, false = none), meleeOn / repeatOn (auto attack / auto-repeat
-- on, from the edges), seeded (both read since the highlight came on), active
-- (the state painted), aimClass (this class's AIM_CLASS),
-- moveEvents / moving (the movement edges registered / the player moving),
-- ruled (the form or talents ruled the timer out at the last apply, RuledOut),
-- sealByName (this paladin's seals by name), seal (the SEALS entry painted,
-- false = none), sealInst / sealTimer / sealSecs (its aura instance, run-out
-- timer and last known length), sealEvents / castEvents (registered), castEnd
-- (when the player's cast or channel ends, nil = none).
-- Per row, _rtt (the latency read for its swing) and, on a guide row, _aimAt
-- (its Stop by point), _aiming and _aimFrom (an aim phase running, and from
-- when).
local SwingState = {
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
    sealByName = {},
    seal = false,
}

-------------------------------------------------------------------------------
--  Settings access
-------------------------------------------------------------------------------

local function P()
    local ERB = mod.ERB
    local saved = ERB and ERB.db
    local profile = saved and saved.profile
    return profile and profile.swingTimer or nil
end

local _, playerClass = UnitClass("player")

-- Forms and talents (the Visibility row's Forms and Talents cog): true while the
-- druid's current form is switched off (barDisabledForms, the per-form map the
-- other bars use) or the talent conditions saved for the player's class do not
-- hold (classTalentConditions[class], the Talent Conditions picker's list; per
-- class, so one profile serves every class). Ruled out, the timer stands down
-- like switched off (ns.ST_Apply).
local function RuledOut(conf)
    if _G._CURB_BarHiddenByForm(conf) then return true end
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
function mod.ST_Style() return mod.ERB_BarsStyle() end

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

local function RowGap(conf) return (conf.rowSpacing or 0) + StockGap(conf) end

-- Secret values throw on comparison and on truth tests: every read from the
-- swing API and from UnitAttackSpeed passes here before it is looked at, and a
-- restricted answer is treated as "no information" (no swing, no range
-- verdict, and a row keeps what was last known about it). Never infer an
-- interval from restricted data.
local function IsPlainVal(val) return not (issecretvalue and issecretvalue(val)) end

-- Blizzard's CanSwing: Main Hand always applies; Off Hand / Ranged only while
-- UnitAttackSpeed reports a positive speed for the slot. Those speeds are
-- secret while unit stats are restricted (SecretWhenUnitStatsRestricted), and a
-- haste proc's UNIT_ATTACK_SPEED lands right there in combat: that answer is
-- nil ("unknown"), never "no weapon".
local function CanSwing(swingType)
    if swingType == SWING.MainHand then return true end
    if swingType == "target" then
        -- Target Swing: a living target the player can attack, with a speed.
        local hostile, dead = UnitCanAttack("player", "target"), UnitIsDead("target")
        if not (IsPlainVal(hostile) and IsPlainVal(dead)) then return nil end
        if not hostile or dead then return false end
        local speed = UnitAttackSpeed("target")
        if not IsPlainVal(speed) then return nil end
        return type(speed) == "number" and speed > 0
    end
    local _, oh, ranged = UnitAttackSpeed("player")
    local swingSpeed
    if swingType == SWING.OffHand then
        swingSpeed = oh
    elseif swingType == SWING.Ranged then
        swingSpeed = ranged
    else
        return false
    end
    if not IsPlainVal(swingSpeed) then return nil end
    return type(swingSpeed) == "number" and swingSpeed > 0
end

-- Shield in the off hand slot: it never swings but counts as an off hand.
local OFFHAND_SLOT = 17
local function OffHandIsShield()
    local ident = GetInventoryItemID("player", OFFHAND_SLOT)
    if not (ident and IsPlainVal(ident)) then return false end
    local _, _, _, loc = C_Item.GetItemInfoInstant(ident)
    return IsPlainVal(loc) and loc == "INVTYPE_SHIELD"
end

-- Shield handling (and its event) is active only with Show Shield As Off Hand
-- or Always Show Rows on.
local function ShieldAware(conf) return conf and (conf.shieldRow or conf.alwaysShowRows) and true or false end
local function ShieldOff(conf) return ShieldAware(conf) and OffHandIsShield() end

-- Rows a queued attack shows on: Main Hand, plus Off Hand unless Queued On Main
-- Hand Only is on.
local function QueueRow(defaults, conf)
    return defaults.queue or (defaults.melee and not conf.queueMainHandOnly)
end

-- A row is shown while its toggle is on and its slot can swing: the live answer
-- when it is plain, else the last one known for that row (a swing of its type
-- is proof too, see PLAYER_SWING). Nothing known yet reads as no row. Always
-- Show Rows shows every ticked row; row._canSwing keeps the real answer.
local function RowWanted(defaults, conf, swingRow)
    if conf and conf[defaults.show] == false then return false end
    if defaults.target then
        -- Opt-in, and shown with its sample while the movers are up.
        if not (conf and conf.showTGT == true) then return false end
        if SwingState.sample then return true end
    end
    local canSwing = CanSwing(defaults.type)
    if canSwing == nil then
        canSwing = swingRow and swingRow._canSwing or false
    elseif swingRow then
        swingRow._canSwing = canSwing
    end
    if conf and conf.alwaysShowRows then return true end
    if not canSwing and defaults.type == SWING.OffHand and ShieldOff(conf) then return true end
    return canSwing
end

-- Rows the frame would stack right now (from the live rows once built, from the
-- weapon slots before). Feeds the unlock mover's size before the first build.
-- A combined off hand rides the Main Hand bar and takes no row (RefreshRows).
local function ShownCount()
    if SwingState.built then return math.max(SwingState.shown, 1) end
    local conf = P()
    local num = 0
    for i = 1, #ROWS do
        if RowWanted(ROWS[i], conf) then num = num + 1 end
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
    if not conf then return 220, 12 end
    local num = ShownCount()
    local hgt = conf.height or 12
    local sp = RowGap(conf)
    return conf.width or 220, num * hgt + (num - 1) * sp
end

local function RowColor(conf, defaults)
    if conf.classColored then
        local cc = mod.CLASS_COLORS and mod.CLASS_COLORS[select(2, UnitClass("player"))]
        if cc then return cc[1], cc[2], cc[3], conf[defaults.key .. "A"] or 1 end
    end
    local k = defaults.key
    return conf[k .. "R"] or 1, conf[k .. "G"] or 1, conf[k .. "B"] or 1, conf[k .. "A"] or 1
end

-- Spark tint: the row's own spark colour once set, else white. A combined off
-- hand's spark is its whole display: unset, it takes the row's fill colour.
-- unset: the tint it has without a colour of its own.
local function SparkColor(conf, defaults, merged, unset)
    local k = defaults.key .. "Spark"
    local region = not unset and conf[k .. "R"]
    if region then return region, conf[k .. "G"] or 1, conf[k .. "B"] or 1, conf[k .. "A"] or 1 end
    if merged then return RowColor(conf, defaults) end
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
local function SwingTimeFormat()
    if timeFormatter ~= nil then return timeFormatter or nil end
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
    if cueFormatter ~= nil then return cueFormatter or nil end
    cueFormatter = false
    if not SwingTimeFormat() then return nil end
    local frame = C_StringUtil.CreateNumericRuleFormatter()
    local rule = {
        {
            threshold = 0,
            format = CludesUI.L("Move %.1f"),
            rounding = Enum.NumericRuleFormatRounding.Nearest,
        },
    }
    if pcall(frame.SetBreakpoints, frame, rule) then cueFormatter = frame end
    return cueFormatter or nil
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------

local function BuildRow(defaults)
    local swingRow = CreateFrame("Frame", nil, shellFrame)
    swingRow._def = defaults

    local backdrop = swingRow:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    swingRow._bg = backdrop

    local borderTex = CreateFrame("Frame", nil, swingRow)
    borderTex:SetAllPoints(swingRow)
    borderTex:SetFrameLevel(swingRow:GetFrameLevel() + 5)
    swingRow._border = borderTex
    local Pix = CludesUI and CludesUI.PP
    if Pix then Pix.CreateBorder(borderTex, 0, 0, 0, 1, 1) end

    local clipper = CreateFrame("Frame", nil, swingRow)
    clipper:SetClipsChildren(true)
    swingRow._clip = clipper

    local barFrame = CreateFrame("StatusBar", nil, clipper)
    barFrame:SetMinMaxValues(0, 1)
    barFrame:SetValue(0)
    swingRow._bar = barFrame
    -- One duration object per row, re-set per swing and handed to the bar
    -- timer (the QoL timer's shape); never read back in Lua.
    swingRow._durObj = C_DurationUtil.CreateDuration()

    -- Spark (same texture/approach as the cast and GCD bars)
    local sparkHolder = CreateFrame("Frame", nil, clipper)
    sparkHolder:SetAllPoints(barFrame)
    sparkHolder:SetFrameLevel(barFrame:GetFrameLevel() + 2)
    local spark = sparkHolder:CreateTexture(nil, "OVERLAY", nil, 1)
    spark:SetTexture(mod.SPARK_TEX)
    spark:SetBlendMode("ADD")
    swingRow._spark = spark
    swingRow._sparkFrame = sparkHolder

    -- Text above the fill; the tag on the left, the countdown on the right.
    local textFrame = CreateFrame("Frame", nil, swingRow)
    textFrame:SetAllPoints(swingRow)
    textFrame:SetFrameLevel(barFrame:GetFrameLevel() + 3)
    swingRow._textFrame = textFrame
    -- Font before any SetText: a FontString with no font errors on SetText
    -- ("Font not set", seen on the Forever client). ApplyRowLook re-sizes it.
    local tagText = textFrame:CreateFontString(nil, "OVERLAY")
    mod.SetRBFont(tagText, mod.GetRBFont(), 11)
    tagText:SetPoint("LEFT", swingRow, "LEFT", 4, 0)
    tagText:SetJustifyH("LEFT")
    tagText:SetWordWrap(false)
    tagText:SetText(defaults.tag)
    swingRow._tag = tagText
    local swingTime = textFrame:CreateFontString(nil, "OVERLAY")
    mod.SetRBFont(swingTime, mod.GetRBFont(), 11)
    swingTime:SetPoint("RIGHT", swingRow, "RIGHT", -4, 0)
    swingTime:SetJustifyH("RIGHT")
    swingTime:SetWordWrap(false)
    swingTime:SetText("")
    swingRow._time = swingTime
    -- The countdown, written engine-side from the row's duration object.
    local fmt = C_DurationUtil.CreateDurationTextBinding and SwingTimeFormat()
    if fmt then
        local widget = C_DurationUtil.CreateDurationTextBinding()
        widget:SetFontString(swingTime)
        widget:SetDuration(swingRow._durObj)
        widget:SetFormatter(fmt)
        widget:SetUpdateInterval(0.05)
        widget:SetExpiredText("")
        widget:SetZeroDurationText("")
        widget:SetEnabled(false)
        swingRow._timeBind = widget
        swingRow._timeBindOn = false
    end

    swingRow._outOfRange = false
    return swingRow
end

-- Out-of-range look: Blizzard dims the whole row to 0.4 and paints the text
-- red. Unlock mode suppresses the dimming without touching the state. A
-- combined off-hand row keeps no bg, border or stock frame (alpha, not Hide: a
-- border re-apply shows its frame again); its range dims the clip, i.e. its
-- spark.
local function ApplyRangeLook(swingRow, conf)
    conf = conf or P()
    local outOfRange = swingRow._outOfRange and not SwingState.sample
    local alpha = outOfRange and ((conf and conf.outOfRangeAlpha) or 0.4) or 1
    local frameAlpha = swingRow._merged and 0 or alpha
    swingRow._bg:SetAlpha(frameAlpha)
    swingRow._border:SetAlpha(frameAlpha)
    if swingRow._blizzBarBg then swingRow._blizzBarBg:SetAlpha(frameAlpha) end
    if swingRow._classicArt then swingRow._classicArt:SetAlpha(frameAlpha) end
    swingRow._clip:SetAlpha(alpha)
    if outOfRange then
        swingRow._tag:SetTextColor(1, 0.1, 0.1, 1)
        swingRow._time:SetTextColor(1, 0.1, 0.1, 1)
    else
        swingRow._tag:SetTextColor(1, 1, 1, 1)
        swingRow._time:SetTextColor(1, 1, 1, 1)
    end
end

local function SetOutOfRange(swingRow, outOfRange)
    outOfRange = outOfRange and true or false
    if swingRow._outOfRange == outOfRange then return end
    swingRow._outOfRange = outOfRange
    ApplyRangeLook(swingRow)
end

-- Range tracking is one engine flag per swing type, and Blizzard's own timer
-- flips it on its edges too (its Edit Mode toggle sends false for the slot), so
-- this never dedupes: every row refresh and every target change re-asserts our
-- answer, and a flip from the other frame can never leave a row undimmed.
-- S.rangeOn is the memo UpdateRangeRow reads, not a send gate. The Target
-- Swing row is not a swing type: it never checks range.
local function SetRangeCheck(swingType, enabled)
    if swingType == "target" then return end
    enabled = enabled and true or false
    SwingState.rangeOn[swingType] = enabled
    C_SwingTimer.EnableRangeCheck(swingType, enabled)
end

-- Re-read range for one row from the API (target change, row shown).
local function UpdateRangeRow(swingRow)
    if not SwingState.rangeOn[swingRow._def.type] then
        SetOutOfRange(swingRow, false)
        return
    end
    -- nil = no check could be made (no target, untargetable, no weapon): NOT out of range.
    local inRange = C_SwingTimer.IsTargetWithinSwingRange(swingRow._def.type)
    SetOutOfRange(swingRow, IsPlainVal(inRange) and inRange == false)
end

local function SyncAllRanges()
    for i = 1, #SwingState.rows do
        local swingRow = SwingState.rows[i]
        if swingRow:IsShown() then UpdateRangeRow(swingRow) end
    end
end

-- Spark visibility, set on the row's edges only (swing start, swing end, look
-- apply), never per frame. Show Spark's spark shows only while its row is
-- mid-swing (not while it waits: no edge moves). A combined off-hand
-- row's spark IS the off-hand display: it ignores Show Spark and shows only
-- mid-swing. Unlock movers up show both.
local function UpdateSpark(swingRow, conf)
    local enabled
    if swingRow._merged then
        enabled = swingRow._live or SwingState.sample
    else
        enabled = conf
            and conf.showSpark
            and ((swingRow._live and not swingRow._waiting) or SwingState.sample)
    end
    swingRow._spark:SetShown(enabled and true or false)
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
local function HideSwingZone(z)
    if z then
        z.back:Hide()
        z.front:Hide()
    end
end

local function HideZones(swingRow)
    local zoneList = swingRow._zones
    if zoneList then
        HideSwingZone(zoneList.lat)
        HideSwingZone(zoneList.aim)
        HideSwingZone(zoneList.win)
    end
end

local function StyleZone(swingRow, key, enabled, texPath, red, green, blue, a, backSub, frontSub)
    local zoneList = swingRow._zones
    local z = zoneList and zoneList[key]
    if not enabled or swingRow._merged then
        HideSwingZone(z)
        return
    end
    if not z then
        if not zoneList then
            zoneList = {}
            swingRow._zones = zoneList
        end
        z = {
            back = swingRow._clip:CreateTexture(nil, "ARTWORK", nil, backSub),
            front = swingRow._bar:CreateTexture(nil, "OVERLAY", nil, frontSub),
        }
        z.back:Hide()
        z.front:Hide()
        zoneList[key] = z
    end
    z.back:SetTexture(texPath)
    z.back:SetVertexColor(red, green, blue, a)
    z.front:SetTexture(texPath)
    z.front:SetVertexColor(red, green, blue, a)
end

-- `deplete`: the phase ends on the left (its fill drains), else on the right.
-- `offset`: seconds the zone sits back from that end (STILL, one latency).
local function PlaceZone(swingRow, z, conf, secs, dur, deplete, offset)
    if not (secs and secs > 0 and dur and dur > 0) then
        HideSwingZone(z)
        return
    end
    local wid = swingRow._clip:GetWidth()
    if not (wid and wid > 0) then wid = conf.width or 220 end
    local off = (offset and offset > 0) and wid * math.min(1, offset / dur) or 0
    local room = wid - off
    if room < 1 then
        HideSwingZone(z)
        return
    end
    local zw = wid * math.min(1, secs / dur)
    if zw < 1 then
        zw = 1
    elseif zw > room then
        zw = room
    end
    local zoneTex = deplete and z.front or z.back
    local other = deplete and z.back or z.front
    other:Hide()
    zoneTex:ClearAllPoints()
    if deplete then
        zoneTex:SetPoint("TOPLEFT", swingRow._clip, "TOPLEFT", off, 0)
        zoneTex:SetPoint("BOTTOMLEFT", swingRow._clip, "BOTTOMLEFT", off, 0)
    else
        zoneTex:SetPoint("TOPRIGHT", swingRow._clip, "TOPRIGHT", -off, 0)
        zoneTex:SetPoint("BOTTOMRIGHT", swingRow._clip, "BOTTOMRIGHT", -off, 0)
    end
    zoneTex:SetWidth(zw)
    zoneTex:Show()
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
local function QueueOn(conf) return conf.attackState ~= "off" end
local function StateFull(conf) return conf.attackState == "full" end
local function GuideOn(conf) return conf.moveGuide == "segments" or conf.moveGuide == "windup" end

local function GuideRow(swingRow, conf)
    return GuideOn(conf) and SwingState.aimClass and swingRow._def.type == SWING.Ranged
end

local function WindRow(swingRow, conf) return conf.moveGuide == "windup" and GuideRow(swingRow, conf) end

local function StillRow(swingRow, conf) return conf.moveGuide == "segments" and GuideRow(swingRow, conf) end

-- Swing Window: melee rows only, not a combined off hand (only its spark shows).
local function WindowRow(swingRow, conf)
    return conf.swingWindow == true and swingRow._def.melee and not swingRow._merged
end

local function StyleZones(swingRow, conf, texPath)
    StyleZone(
        swingRow,
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
    local color = AIM_COLOR
    StyleZone(
        swingRow,
        "aim",
        StillRow(swingRow, conf),
        texPath,
        conf.aimR or color.r,
        conf.aimG or color.g,
        conf.aimB or color.b,
        conf.aimA or 0.6,
        6,
        -1
    )
    local wc = WINDOW_COLOR
    StyleZone(
        swingRow,
        "win",
        WindowRow(swingRow, conf),
        texPath,
        conf.windowR or wc.r,
        conf.windowG or wc.g,
        conf.windowB or wc.b,
        conf.windowA or wc.a,
        5,
        -2
    )
end

-- Both zones on a swing, from the latency read at its start (_rtt). A Wind-Up
-- row's swing ends at its aim, not at the shot, so its GO waits for the aim
-- phase (PlaceAimLatency).
local function UpdateZones(swingRow, conf, dur)
    local zoneList = swingRow._zones
    if not zoneList then return end
    local lat, aimTex = zoneList.lat, zoneList.aim
    local rtt = swingRow._rtt or NetLatency() or 0
    if lat then
        if GuideOn(conf) and not swingRow._merged and not WindRow(swingRow, conf) then
            PlaceZone(swingRow, lat, conf, rtt, dur, conf.depleteFill)
        else
            HideSwingZone(lat)
        end
    end
    if aimTex then
        if StillRow(swingRow, conf) then
            PlaceZone(swingRow, aimTex, conf, AIM_TIME, dur, conf.depleteFill, rtt)
        else
            HideSwingZone(aimTex)
        end
    end
    local win = zoneList.win
    if win then
        if WindowRow(swingRow, conf) then
            local secs = conf.swingWindowTime or WINDOW_TIME
            if conf.windowLatency then secs = secs + rtt end
            PlaceZone(swingRow, win, conf, secs, dur, conf.depleteFill)
        else
            HideSwingZone(win)
        end
    end
end

-- Cast Clip (Main Hand row): where the player's cast or channel ends against
-- the running swing. The tick is built on first use, over the fill; hidden
-- while the row is not mid-swing, waiting, aiming, or shows its sample.
local function CastTick(conf)
    local swingRow = SwingState.byType[SWING.MainHand]
    if not swingRow then return end
    local tick = swingRow._tick
    local castEnd = SwingState.castEnd
    local start, e = swingRow._start, swingRow._end
    if
        not (
            conf
            and conf.castClip == true
            and castEnd
            and swingRow._live
            and start
            and e
            and e > start
            and not swingRow._waiting
            and not swingRow._aiming
            and not SwingState.sample
        )
    then
        if tick then tick:Hide() end
        return
    end
    if not tick then
        tick = swingRow._sparkFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        swingRow._tick = tick
    end
    local frac = (castEnd - start) / (e - start)
    if frac > 1 then
        frac = 1
    elseif frac < 0 then
        frac = 0
    end
    if conf.depleteFill then frac = 1 - frac end
    local wid = swingRow._clip:GetWidth()
    if not (wid and wid > 0) then wid = conf.width or 220 end
    local bad = castEnd > e
    local key, def = bad and "castBad" or "castOk", bad and CAST_BAD or CAST_OK
    tick:SetColorTexture(conf[key .. "R"] or def.r, conf[key .. "G"] or def.g, conf[key .. "B"] or def.b, conf[key .. "A"] or 1)
    tick:ClearAllPoints()
    tick:SetPoint("TOP", swingRow._clip, "TOPLEFT", wid * frac, 0)
    tick:SetPoint("BOTTOM", swingRow._clip, "BOTTOMLEFT", wid * frac, 0)
    tick:SetWidth(TICK_WIDTH)
    tick:Show()
end

-- The player's cast or channel end, in seconds (GetTime's clock); nil when
-- there is none or the answer is restricted.
local function ReadCast()
    local e = select(5, UnitCastingInfo("player"))
    if IsPlainVal(e) and not e then e = select(5, UnitChannelInfo("player")) end
    SwingState.castEnd = (IsPlainVal(e) and type(e) == "number" and e > 0) and e / 1000 or nil
end

-- GO at the end of an aim phase, which runs opposite to the swing.
local function PlaceAimLatency(swingRow, conf, from, to)
    local lat = swingRow._zones and swingRow._zones.lat
    if lat and GuideOn(conf) and not swingRow._merged then
        PlaceZone(swingRow, lat, conf, NetLatency(), to - from, not conf.depleteFill)
    end
end

-- Defined with the look below; the swing edges above it repaint through it.
local ApplyRowFill
-- Defined with the edge helpers below; the idle render already writes through it.
local SyncTimeText

-- The auto attack and auto-repeat edges are tracked while a feature reads them:
-- Attack State Full, or the Movement Guide for a wand or Auto Shot class.
local function TracksAttack(conf) return StateFull(conf) or (GuideOn(conf) and SwingState.aimClass) or false end

-- The row's attack is on right now (melee rows: Auto Attack; Ranged: the
-- auto-repeat shot).
local function AttackOn(defaults)
    if defaults.melee then return SwingState.meleeOn == true end
    return SwingState.repeatOn == true
end

-- A row not mid-swing waits (parks full) while its attack is on, under Attack
-- State Full or on a guide row (a held shot). A hidden row (no weapon in the
-- slot) never waits: it would count as live and hold the bar up under Hide
-- When Idle.
local function ShouldWait(swingRow, conf)
    return swingRow:IsShown()
            and swingRow._canSwing ~= false
            and not swingRow._merged
            and not swingRow._def.target
            and AttackOn(swingRow._def)
            and (StateFull(conf) or GuideRow(swingRow, conf))
            and true
        or false
end

-- Idle render: empty (background) by default, full of the fill colour with
-- idleShowFill. The time text is blank (no "0.0"). This is also the disarm:
-- the bar timer is re-armed on a finished duration, whose terminal state is
-- static (RemainingTime paints empty, ElapsedTime full: the GCD bar's idle
-- recipe), so the engine has nothing left to animate. The SetValue keeps the
-- value channel coherent with what is drawn.
local function IdleRow(swingRow, conf)
    if swingRow._waiting or swingRow._aiming then
        swingRow._waiting, swingRow._aiming = nil, nil
        if conf then ApplyRowFill(swingRow, conf) end
    end
    swingRow._aimAt = nil
    if swingRow._live then
        swingRow._live = nil
        SwingState.live = SwingState.live - 1
        UpdateSpark(swingRow, conf)
    end
    swingRow._end = nil
    local full = conf and conf.idleShowFill == true
    local object = swingRow._durObj
    object:SetTimeFromStart(GetTime() - 1, 1)
    swingRow._bar:SetTimerDuration(object, IMMEDIATE, full and DIR.ElapsedTime or DIR.RemainingTime)
    swingRow._bar:SetValue(full and 1 or 0)
    SyncTimeText(swingRow, conf)
    swingRow._time:SetText("")
    HideZones(swingRow)
    if swingRow._tick then swingRow._tick:Hide() end
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
local function ArmEdges(swingRow, conf)
    local e = swingRow._end
    if not e then return end
    local nowTime = GetTime()
    C_Timer.After(math.max(e - nowTime, 0), EndEdge)
    if not GuideRow(swingRow, conf) then return end
    local a = swingRow._aimAt
    if a and not swingRow._aiming and (conf.moveCue or WindRow(swingRow, conf)) then
        C_Timer.After(math.max(a - nowTime, 0), EndEdge)
    end
    if conf.moveCue then
        local go = e - (swingRow._rtt or 0)
        if go > nowTime then C_Timer.After(go - nowTime, EndEdge) end
    end
end

-- The Text Cue's Move countdown: a second binding on the row's time text, on a
-- duration object that ends at Stop by, reading Still once it runs out. nil
-- when the client refused the format.
local function CueBind(swingRow)
    if swingRow._cueBind then return swingRow._cueBind end
    local fmt = swingRow._timeBind and CueFormatter()
    if not fmt then return nil end
    swingRow._cueObj = C_DurationUtil.CreateDuration()
    local widget = C_DurationUtil.CreateDurationTextBinding()
    widget:SetFontString(swingRow._time)
    widget:SetDuration(swingRow._cueObj)
    widget:SetFormatter(fmt)
    widget:SetUpdateInterval(0.05)
    widget:SetExpiredText(CludesUI.L("Still"))
    widget:SetZeroDurationText(CludesUI.L("Still"))
    widget:SetEnabled(false)
    swingRow._cueBind, swingRow._cueBindOn = widget, false
    return widget
end

-- The time text. Mid-swing the engine writes it: the swing's countdown, or with
-- the Text Cue on a guide row the seconds left to move until Stop by, then
-- Still and, in the swing's last latency, Go. Every other state writes its own
-- text with both bindings off. Runs at each edge and on a settings pass.
function SyncTimeText(swingRow, conf)
    local widget = swingRow._timeBind
    if not widget then return end
    local phaseNum
    if
        conf
        and conf.showTime ~= false
        and not swingRow._merged
        and swingRow._live
        and not swingRow._waiting
        and not SwingState.sample
    then
        phaseNum = "swing"
        if conf.moveCue and GuideRow(swingRow, conf) then
            local nowTime = GetTime()
            if swingRow._end and swingRow._end - nowTime <= (swingRow._rtt or 0) + END_SLACK then
                phaseNum = "go"
            elseif
                swingRow._aiming
                or not (swingRow._aimAt and swingRow._start)
                or nowTime >= swingRow._aimAt - END_SLACK
            then
                phaseNum = "still"
            elseif CueBind(swingRow) then
                phaseNum = "move"
            end
        end
    end
    local swinging = phaseNum == "swing"
    if swinging then
        -- A Wind-Up row's bar runs only to Stop by; its countdown still runs to
        -- the shot, on a duration object of its own.
        local target = swingRow._durObj
        if not swingRow._aiming and swingRow._start and swingRow._end and WindRow(swingRow, conf) then
            local swingOpts = swingRow._swingObj
            if not swingOpts then
                swingOpts = C_DurationUtil.CreateDuration()
                swingRow._swingObj = swingOpts
            end
            swingOpts:SetTimeFromStart(swingRow._start, swingRow._end - swingRow._start)
            target = swingOpts
        end
        if target ~= swingRow._bindObj then
            swingRow._bindObj = target
            widget:SetDuration(target)
        end
    end
    if swinging ~= swingRow._timeBindOn then
        swingRow._timeBindOn = swinging
        widget:SetEnabled(swinging)
    end
    local callback = swingRow._cueBind
    local moveOn = phaseNum == "move"
    if moveOn then
        swingRow._cueObj:SetTimeFromStart(swingRow._start, math.max(swingRow._aimAt - swingRow._start, 0.01))
    end
    if callback and moveOn ~= swingRow._cueBindOn then
        swingRow._cueBindOn = moveOn
        callback:SetEnabled(moveOn)
    end
    if swinging then
        widget:UpdateFontString()
    elseif moveOn then
        callback:UpdateFontString()
    elseif phaseNum == "still" then
        swingRow._time:SetText(CludesUI.L("Still"))
    elseif phaseNum == "go" then
        swingRow._time:SetText(CludesUI.L("Go"))
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
local function StartRow(swingRow, dur, conf)
    if type(dur) ~= "number" or dur ~= dur or dur <= 0 or dur == math.huge then return end
    local nowTime = GetTime()
    local start = nowTime
    local due = swingRow._due
    if GuideOn(conf) and due and not swingRow._def.target then
        local late = nowTime - due
        if late > -SMOOTH_TOL and late < SMOOTH_TOL then start = due + late * SMOOTH_GAIN end
    end
    swingRow._end = start + dur
    swingRow._due = swingRow._end
    swingRow._dur = dur
    swingRow._start = start
    swingRow._rtt = NetLatency() or 0
    local wind = WindRow(swingRow, conf)
    swingRow._aimAt = GuideRow(swingRow, conf) and (swingRow._end - AIM_TIME - swingRow._rtt) or nil
    if swingRow._waiting or swingRow._aiming then
        swingRow._waiting, swingRow._aiming = nil, nil
        ApplyRowFill(swingRow, conf)
        UpdateSpark(swingRow, conf)
    end
    if not swingRow._live then
        swingRow._live = true
        SwingState.live = SwingState.live + 1
        UpdateSpark(swingRow, conf)
    end
    local object = swingRow._durObj
    object:SetTimeFromStart(start, wind and math.max(swingRow._aimAt - start, 0.01) or dur)
    swingRow._bar:SetTimerDuration(
        object,
        IMMEDIATE,
        conf.depleteFill and DIR.RemainingTime or DIR.ElapsedTime
    )
    UpdateZones(swingRow, conf, dur)
    if swingRow._def.type == SWING.MainHand then CastTick(conf) end
    ArmEdges(swingRow, conf)
    SyncTimeText(swingRow, conf)
    if conf.hideWhenIdle and SwingState.live == 1 and mod.ST_UpdateVisibility then
        mod.ST_UpdateVisibility()
    end
end

-- Waiting (attack on, no swing running): parked full, in the Waiting colour
-- under Attack State Full, else the row's own. Entered from a finished swing or
-- from idle (a guide row also from a shot held by moving); the row counts as
-- live (Hide When Idle keeps it) but has no deadline. The next swing
-- (StartRow), an attack-stop edge (IdleRow) or a stop that restarts the aim
-- (EnterAim) ends it, never a timer.
local function EnterWaiting(swingRow, conf)
    swingRow._waiting = true
    swingRow._aiming = nil
    swingRow._end = nil
    if not swingRow._live then
        swingRow._live = true
        SwingState.live = SwingState.live + 1
    end
    local object = swingRow._durObj
    object:SetTimeFromStart(GetTime() - 1, 1)
    swingRow._bar:SetTimerDuration(object, IMMEDIATE, DIR.ElapsedTime)
    swingRow._bar:SetValue(1)
    SyncTimeText(swingRow, conf)
    swingRow._time:SetText(
        (conf.moveCue and conf.showTime ~= false and GuideRow(swingRow, conf)) and CludesUI.L("Still") or ""
    )
    HideZones(swingRow)
    if swingRow._tick then swingRow._tick:Hide() end
    UpdateSpark(swingRow, conf)
    ApplyRowFill(swingRow, conf)
end

-- Aim phase: the half second a wand or Auto Shot needs the player still, plus
-- one latency, as its own fill from `from` to the predicted shot `to`, in the
-- Still colour: a Wind-Up row's every swing from Stop by, and any guide row's
-- restart after a held shot. It runs opposite to the swing so the two join
-- (Deplete Fill: the reload drains, the aim fills), with GO at its end.
local function EnterAim(swingRow, conf, from, to)
    swingRow._waiting = nil
    swingRow._aiming = true
    swingRow._aimFrom = from
    swingRow._end = to
    if not swingRow._live then
        swingRow._live = true
        SwingState.live = SwingState.live + 1
    end
    local object = swingRow._durObj
    object:SetTimeFromStart(from, to - from)
    swingRow._bar:SetTimerDuration(
        object,
        IMMEDIATE,
        conf.depleteFill and DIR.ElapsedTime or DIR.RemainingTime
    )
    HideZones(swingRow)
    if swingRow._tick then swingRow._tick:Hide() end
    PlaceAimLatency(swingRow, conf, from, to)
    UpdateSpark(swingRow, conf)
    ApplyRowFill(swingRow, conf)
    ArmEdges(swingRow, conf)
    SyncTimeText(swingRow, conf)
end

-- The edges, run by the deadlines ArmEdges schedules: a Wind-Up row's reload
-- done at Stop by starts its aim phase, each row whose swing is over goes idle
-- or waits while its attack is on, a running row's time text takes its next
-- step (the Text Cue's Still and Go), and Hide When Idle hides the bar once no
-- swing runs. No SetValue here, the fill is the engine's.
function EndEdge()
    local conf = P()
    if not (conf and conf.enabled and SwingState.built) then return end
    local nowTime = GetTime()
    local running = false
    for i = 1, #SwingState.rows do
        local swingRow = SwingState.rows[i]
        -- Wind-Up reload done at Stop by: the aim phase, held while moving, none
        -- once the shot is off (no shot is coming). Segments keeps its bar.
        if
            swingRow._live
            and not swingRow._waiting
            and swingRow._aimAt
            and not swingRow._aiming
            and nowTime >= swingRow._aimAt - END_SLACK
            and WindRow(swingRow, conf)
        then
            if not AttackOn(swingRow._def) then
                IdleRow(swingRow, conf)
            elseif SwingState.moving then
                EnterWaiting(swingRow, conf)
            else
                EnterAim(swingRow, conf, swingRow._aimAt, swingRow._end)
            end
        end
        if swingRow._live and not swingRow._waiting then
            if swingRow._end - nowTime <= END_SLACK then
                if ShouldWait(swingRow, conf) then
                    EnterWaiting(swingRow, conf)
                else
                    IdleRow(swingRow, conf)
                end
            else
                running = true
                SyncTimeText(swingRow, conf)
            end
        end
    end
    if not running and conf.hideWhenIdle and mod.ST_UpdateVisibility then mod.ST_UpdateVisibility() end
end

-------------------------------------------------------------------------------
--  Layout + look
-------------------------------------------------------------------------------

-- Fill colour: the row's own (or class) colour; the seal's colour on a melee
-- row while a paladin seal is up (Seal Colors); the On colour while its auto
-- attack is on (Attack State Full); the queued attack's own colour on a melee
-- row while an on-next-swing attack is queued (not with Attack State Off); the
-- Still colour (opaque) in an aim phase; the Waiting colour while the row waits
-- under Attack State Full (each wins over the ones before). A combined
-- off-hand row paints no fill: its bar keeps running under its spark, unseen.
function ApplyRowFill(swingRow, conf)
    local fillTex = swingRow._bar:GetStatusBarTexture()
    if swingRow._merged then
        mod.ApplyBarFlat(fillTex, 0, 0, 0, 0)
        return
    end
    local defaults = swingRow._def
    local pend = swingRow._waiting and StateFull(conf)
    local aimTex = not pend and swingRow._aiming
    local q = not (pend or aimTex) and QueueRow(defaults, conf) and SwingState.queued
    local act = not (pend or aimTex or q or defaults.target)
        and SwingState.active[defaults.melee and "melee" or "ranged"]
    local sl = not (pend or aimTex or q or act) and defaults.melee and SwingState.seal
    local fR, fG, fB, fA
    if pend then
        local color = PENDING_COLOR
        fR, fG, fB, fA =
            conf.pendingR or color.r, conf.pendingG or color.g, conf.pendingB or color.b, conf.pendingA or 1
    elseif aimTex then
        local color = AIM_COLOR
        fR, fG, fB, fA = conf.aimR or color.r, conf.aimG or color.g, conf.aimB or color.b, 1
    elseif q then
        local k = q.key
        -- Unset per-ability colour: the shared Queued colour (older profiles).
        if q.shared and conf[k .. "R"] == nil then k = q.shared end
        fR, fG, fB, fA =
            conf[k .. "R"] or q.r, conf[k .. "G"] or q.g, conf[k .. "B"] or q.b, conf[k .. "A"] or 1
    elseif act then
        local color = ACTIVE_COLOR
        fR, fG, fB, fA =
            conf.activeR or color.r, conf.activeG or color.g, conf.activeB or color.b, conf.activeA or 1
    elseif sl then
        local k = sl.key
        fR, fG, fB, fA =
            conf[k .. "R"] or sl.r, conf[k .. "G"] or sl.g, conf[k .. "B"] or sl.b, conf[k .. "A"] or 1
    else
        fR, fG, fB, fA = RowColor(conf, defaults)
    end
    if conf.gradientEnabled and not (pend or aimTex or q or act or sl) then
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
local function TagText(swingRow, conf)
    if swingRow._def.type == SWING.OffHand and swingRow._canSwing == false and ShieldOff(conf) then
        return CludesUI.L("Shield")
    end
    return swingRow._def.tag
end

-- Slot tag, with the queued attack's name on the Main Hand row while one is queued.
-- Written only when the slot text or the queued attack changed: RefreshRows runs
-- this for every row on each weapon and attack speed change.
local function ApplyRowTag(swingRow, conf)
    local defaults = swingRow._def
    local q = SwingState.queued and QueueRow(defaults, conf) and SwingState.queued.name or false
    local base = q and defaults.tag or TagText(swingRow, conf)
    if base == swingRow._tagBase and q == swingRow._tagQueued then return end
    swingRow._tagBase, swingRow._tagQueued = base, q
    swingRow._tag:SetText(q and (base .. " - " .. q) or base)
end

-- Which on-next-swing attack is queued right now (its S.queueSpells entry), or
-- false. Reads only the names resolved at build; a restricted answer counts as
-- not queued.
local function QueuedSpell()
    local entries = SwingState.queueSpells
    if #entries == 0 or not (C_Spell and C_Spell.IsCurrentSpell) then return false end
    for i = 1, #entries do
        local current = C_Spell.IsCurrentSpell(entries[i].name)
        if IsPlainVal(current) and current then return entries[i] end
    end
    return false
end

-- Delta paint: touches the melee rows only when the queued attack changed.
local function PaintQueue(conf)
    conf = conf or P()
    if not (conf and SwingState.built) then return end
    local queued = QueueOn(conf) and QueuedSpell() or false
    if queued == SwingState.queued then return end
    SwingState.queued = queued
    for i = 1, #SwingState.rows do
        local swingRow = SwingState.rows[i]
        if QueueRow(swingRow._def, conf) then
            ApplyRowFill(swingRow, conf)
            ApplyRowTag(swingRow, conf)
        end
    end
end

-- Seal Colors: on for a paladin unless switched off (sealColors ~= false).
local function SealOn(conf) return conf.sealColors ~= false and next(SwingState.sealByName) ~= nil end

local function StopSealTimer()
    local timer = SwingState.sealTimer
    if timer then
        timer:Cancel()
        SwingState.sealTimer = nil
    end
end

-- Delta paint: touches the melee rows only when the seal changed.
local function SetSeal(entry)
    if not entry then
        StopSealTimer()
        SwingState.sealInst = nil
    end
    if entry == SwingState.seal then return end
    SwingState.seal = entry
    local conf = P()
    if not (conf and SwingState.built) then return end
    for i = 1, #SwingState.rows do
        local swingRow = SwingState.rows[i]
        if swingRow._def.melee then ApplyRowFill(swingRow, conf) end
    end
end

local function SealRanOut()
    SwingState.sealTimer = nil
    SetSeal(false)
end

local function SealEndsIn(secs)
    StopSealTimer()
    SwingState.sealTimer = C_Timer.NewTimer(math.max(secs, 0), SealRanOut)
end

local function AurasSecret()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() and true or false
end

-- The SEALS entry an aura is, or nil; a seal also leaves its instance, length
-- and run-out time behind.
local function SealFromAura(aura)
    local name = aura and aura.name
    if not (IsPlainVal(name) and name) then return nil end
    local entry = SwingState.sealByName[name]
    if not entry then return nil end
    local inst, dur, ends = aura.auraInstanceID, aura.duration, aura.expirationTime
    SwingState.sealInst = IsPlainVal(inst) and inst or nil
    if IsPlainVal(dur) and type(dur) == "number" and dur > 0 then SwingState.sealSecs = dur end
    if IsPlainVal(ends) and type(ends) == "number" and ends > 0 then
        SealEndsIn(ends - GetTime())
    else
        StopSealTimer()
    end
    return entry
end

-- Full read of the player's buffs (enable, a full update).
local function ScanSeal()
    if AurasSecret() or not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    local found = false
    for i = 1, MAX_AURAS do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local entry = SealFromAura(aura)
        if entry then
            found = entry
            break
        end
    end
    SetSeal(found)
end

-- UNIT_AURA's update info: the tracked seal removed, a seal added, or the
-- tracked seal refreshed (a new run-out time).
local function SealAuraUpdate(info)
    if type(info) ~= "table" or info.isFullUpdate then return ScanSeal() end
    if AurasSecret() then return end
    local removed, inst = info.removedAuraInstanceIDs, SwingState.sealInst
    if removed and inst then
        for i = 1, #removed do
            if IsPlainVal(removed[i]) and removed[i] == inst then
                SetSeal(false)
                break
            end
        end
    end
    local added = info.addedAuras
    if added then
        for i = 1, #added do
            local entry = SealFromAura(added[i])
            if entry then
                SetSeal(entry)
                break
            end
        end
    end
    local updated = info.updatedAuraInstanceIDs
    inst = SwingState.sealInst
    if updated and inst and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        for i = 1, #updated do
            if IsPlainVal(updated[i]) and updated[i] == inst then
                SealFromAura(C_UnitAuras.GetAuraDataByAuraInstanceID("player", inst))
                break
            end
        end
    end
end

-- A seal cast: shown at once, running out after its last known length, unless
-- its aura already reported it (then the aura's own times hold).
local function SealCast(spellID)
    if not (IsPlainVal(spellID) and spellID and C_Spell and C_Spell.GetSpellName) then return end
    local name = C_Spell.GetSpellName(spellID)
    local entry = IsPlainVal(name) and name and SwingState.sealByName[name]
    if not entry then return end
    if entry == SwingState.seal and SwingState.sealInst then return end
    SwingState.sealInst = nil
    SetSeal(entry)
    SealEndsIn(SwingState.sealSecs or SEAL_TIME)
end

-- Target Swing parry haste: the running swing moved earlier, re-armed the way
-- a settings pass re-arms a running row.
local function ParryHaste(swingRow, conf)
    local nowTime, dur = GetTime(), swingRow._dur
    local rem = swingRow._end - nowTime
    if rem > PARRY_HIGH * dur then
        rem = rem - PARRY_CUT * dur
    elseif rem > PARRY_LOW * dur then
        rem = PARRY_LOW * dur
    else
        return
    end
    swingRow._end = nowTime + rem
    swingRow._due = swingRow._end
    swingRow._start = swingRow._end - dur
    local object = swingRow._durObj
    object:SetTimeFromStart(swingRow._start, dur)
    swingRow._bar:SetTimerDuration(object, IMMEDIATE, conf.depleteFill and DIR.RemainingTime or DIR.ElapsedTime)
    ArmEdges(swingRow, conf)
    SyncTimeText(swingRow, conf)
end

-- UNIT_COMBAT for the Target Swing row: the target's physical hit (or miss,
-- dodge, parry...) on the player starts its swing, read while the player is
-- its target; the target parrying hastes it. Restricted answers do nothing.
local function TargetCombat(conf, unit, action, school)
    local swingRow = SwingState.byType.target
    if not (swingRow and swingRow:IsShown()) or SwingState.sample then return end
    if not (IsPlainVal(unit) and IsPlainVal(action) and IsPlainVal(school)) then return end
    if unit == "player" then
        if school ~= PHYSICAL or not TARGET_HITS[action] then return end
        local onMe = UnitIsUnit("targettarget", "player")
        if not (IsPlainVal(onMe) and onMe) then return end
        local speed = UnitAttackSpeed("target")
        if IsPlainVal(speed) and type(speed) == "number" and speed > 0 then StartRow(swingRow, speed, conf) end
    elseif unit == "target" and action == "PARRY" and swingRow._live and swingRow._end and swingRow._dur then
        ParryHaste(swingRow, conf)
    end
end

-- The Target Swing row shows or hides with the target (hostile, alive): the
-- stack re-lays out only when that answer changed.
local function TargetRowChanged(conf)
    local swingRow = SwingState.byType.target
    return swingRow and (RowWanted(swingRow._def, conf, swingRow) and true or false) ~= swingRow:IsShown()
end

-- One-shot read of both states, for the edges this frame was not listening
-- to: the action bars' own auto-repeat test, and Auto Attack as the current
-- spell. The edges keep them current from here.
local function SeedActiveSwings()
    SwingState.seeded = true
    local rep = false
    local isRep = C_ActionBar and C_ActionBar.IsAutoRepeatAction
    if isRep then
        for slot = 1, MAX_ACTION_SLOT do
            local val = isRep(slot)
            if IsPlainVal(val) and val then
                rep = true
                break
            end
        end
    end
    SwingState.repeatOn = rep
    local current = C_Spell and C_Spell.IsCurrentSpell and C_Spell.IsCurrentSpell(AUTO_ATTACK)
    SwingState.meleeOn = (IsPlainVal(current) and current) and true or false
end

-- Delta paint: touches only the rows whose active state flipped.
local function PaintActive(conf)
    conf = conf or P()
    if not (conf and SwingState.built) then return end
    local enabled = StateFull(conf)
    local melee = enabled and SwingState.meleeOn == true
    local ranged = enabled and SwingState.repeatOn == true
    local A = SwingState.active
    local dMelee, dRanged = melee ~= A.melee, ranged ~= A.ranged
    if not (dMelee or dRanged) then return end
    A.melee, A.ranged = melee, ranged
    for i = 1, #SwingState.rows do
        local swingRow = SwingState.rows[i]
        local defaults = swingRow._def
        if (defaults.melee and dMelee) or (not defaults.melee and not defaults.target and dRanged) then
            ApplyRowFill(swingRow, conf)
        end
    end
end

-- Matches every row not mid-swing to its attack: waiting while it is on, idle
-- once it stops. Runs on the attack edges, after a loading screen and when the
-- weapon rows change; a row mid-swing is left to its end edge.
local function SyncWaiting(conf)
    local changed = false
    for i = 1, #SwingState.rows do
        local swingRow = SwingState.rows[i]
        if not (swingRow._live and not swingRow._waiting) then
            if ShouldWait(swingRow, conf) then
                if not swingRow._waiting then
                    EnterWaiting(swingRow, conf)
                    changed = true
                end
            elseif swingRow._waiting then
                IdleRow(swingRow, conf)
                changed = true
            end
        end
    end
    if changed and conf.hideWhenIdle and mod.ST_UpdateVisibility then mod.ST_UpdateVisibility() end
end

-- Stack the applicable rows and size the frame to them; a combined off-hand
-- row is laid over the Main Hand row instead of taking a slot. Returns true
-- when the frame height changed (anchored neighbours need a nudge).
local function Layout(conf)
    local hgt = conf.height or 12
    local sp = RowGap(conf)
    local wid = conf.width or 220
    local position = 0
    for i = 1, #SwingState.rows do
        local swingRow = SwingState.rows[i]
        if swingRow:IsShown() then
            swingRow:ClearAllPoints()
            if swingRow._merged then
                swingRow:SetAllPoints(SwingState.byType[SWING.MainHand])
            else
                swingRow:SetPoint("TOPLEFT", shellFrame, "TOPLEFT", 0, -position * (hgt + sp))
                swingRow:SetSize(wid, hgt)
                position = position + 1
            end
        end
    end
    SwingState.shown = position
    local num = math.max(position, 1)
    local totalH = num * hgt + (num - 1) * sp
    shellFrame:SetSize(wid, totalH)
    local changed = SwingState.lastH ~= nil and SwingState.lastH ~= totalH
    SwingState.lastH = totalH
    return changed
end

-- Stock styles: the row's stock frame round its bar (the Blizzard Style panel
-- or the Classic WoW UI frame, ns.ERB_ApplyBlizzBarChrome), built on first
-- use. Under Blizzard Style the bar-shape mask also takes the fill and the
-- GO / STILL zones. A combined off-hand row is only a spark over the Main
-- Hand row: its frame takes alpha 0 (ApplyRangeLook) and its bevel hides.
local function StockChrome(swingRow, conf, wid, hgt)
    local barFrame = swingRow._bar
    if swingRow._merged then
        local sh = barFrame._blizzShadow
        if sh then
            for i = 1, 4 do
                sh[i]:Hide()
            end
        end
        return
    end
    mod.ERB_ApplyBlizzBarChrome(swingRow, barFrame, wid, hgt, false, mod.ERB_ClassicFrameK(conf))
    local mask = swingRow._blizzBarMask
    if mask then
        mod.ERB_SeatBlizzMask(swingRow, barFrame)
        local zoneList = swingRow._zones
        if zoneList then
            for _, z in pairs(zoneList) do
                mod.ERB_MaskTex(z.back, mask)
                mod.ERB_MaskTex(z.front, mask)
            end
        end
    end
    -- The vanilla frame art sits at the row's level + 9, over the bar's ends.
    if mod.ERB_BarsClassic() then swingRow._textFrame:SetFrameLevel(swingRow:GetFrameLevel() + 10) end
end

-- Tag visibility: Show Weapon Label, not on a combined off hand, and with Hide
-- Label Without Weapon not on a weaponless row (a shield keeps its tag).
local function ApplyRowLabel(swingRow, conf)
    local show = conf.showLabel ~= false and not swingRow._merged
    if
        show
        and conf.hideLabelNoWeapon
        and swingRow._canSwing == false
        and not (swingRow._def.type == SWING.OffHand and ShieldOff(conf))
    then
        show = false
    end
    ApplyRowTag(swingRow, conf)
    if show then
        swingRow._tag:Show()
    else
        swingRow._tag:Hide()
    end
end

local function ApplyRowLook(swingRow, conf, wid, hgt)
    swingRow._restyle = nil
    local Pix = CludesUI.PP
    -- A stock style's frame (StockChrome) replaces the CUI border.
    local stock = mod.ST_Style() ~= "cui"
    local bs = (not stock and conf.borderSize) or 0
    local borderTex = swingRow._border
    local pl = swingRow:GetFrameLevel()
    borderTex:SetFrameLevel(conf.borderBehind and math.max(0, pl - 1) or (pl + 5))
    -- Lost-rect recovery, see the cast bar border in the main file.
    if not borderTex:GetLeft() then borderTex:SetAllPoints(swingRow) end
    if stock then
        CludesUI.ApplyBorderStyle(borderTex, 0, 0, 0, 0, 0, "solid")
    else
        CludesUI.ApplyBorderStyle(
            borderTex,
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
    local clipper, barFrame = swingRow._clip, swingRow._bar
    local inset = (bs > 0 and Pix and Pix.mult) or 0
    clipper:ClearAllPoints()
    clipper:SetPoint("TOPLEFT", swingRow, "TOPLEFT", inset, -inset)
    clipper:SetPoint("BOTTOMRIGHT", swingRow, "BOTTOMRIGHT", -inset, inset)
    clipper:SetFrameLevel(pl + 1)
    barFrame:ClearAllPoints()
    barFrame:SetAllPoints(clipper)

    local texPath =
        CludesUI.ResolveTexturePath(_G._CURB_BarTextures, conf.texture, "Interface\\Buttons\\WHITE8x8")
    barFrame:SetStatusBarTexture(texPath)
    barFrame:SetOrientation("HORIZONTAL")
    barFrame:SetRotatesTexture(false)
    barFrame:SetReverseFill(false)
    swingRow._bg:SetTexture(nil)
    swingRow._bg:SetColorTexture(conf.bgR or 0, conf.bgG or 0, conf.bgB or 0, conf.bgA or 0.7)
    StyleZones(swingRow, conf, texPath)
    if stock then StockChrome(swingRow, conf, wid, hgt) end

    ApplyRowFill(swingRow, conf)

    -- Leading-edge spark: anchored to the fill texture's moving edge so it
    -- tracks the fill (the GCD bar's horizontal case). On a combined off-hand
    -- row it is the whole display. An overhang reaches past the bar's top and
    -- bottom: the spark leaves the bar's clip (and the rounded body) for a clip
    -- of its own, built on first use, that still cuts it at the bar's ends.
    local spark, sparkHolder = swingRow._spark, swingRow._sparkFrame
    local over = conf.sparkOverhang or 0
    if over > 0 then
        local swingColor = swingRow._sparkClip
        if not swingColor then
            swingColor = CreateFrame("Frame", nil, swingRow)
            swingColor:SetClipsChildren(true)
            swingRow._sparkClip = swingColor
        end
        swingColor:ClearAllPoints()
        swingColor:SetPoint("TOPLEFT", clipper, "TOPLEFT", 0, over)
        swingColor:SetPoint("BOTTOMRIGHT", clipper, "BOTTOMRIGHT", 0, -over)
        swingColor:SetFrameLevel(barFrame:GetFrameLevel() + 1)
        sparkHolder:SetParent(swingColor)
    else
        sparkHolder:SetParent(clipper)
    end
    sparkHolder:SetFrameLevel(barFrame:GetFrameLevel() + 2)
    spark:ClearAllPoints()
    spark:SetSize(conf.sparkWidth or 8, hgt + 2 * over)
    spark:SetPoint("CENTER", barFrame:GetStatusBarTexture(), "RIGHT", 0, 0)
    spark:SetVertexColor(SparkColor(conf, swingRow._def, swingRow._merged))
    UpdateSpark(swingRow, conf)

    local size = conf.textSize or 11
    mod.SetRBFont(swingRow._tag, mod.GetRBFont(), size)
    mod.SetRBFont(swingRow._time, mod.GetRBFont(), size)
    -- Label on the left, time on the right, each with its own offsets.
    swingRow._tag:ClearAllPoints()
    swingRow._tag:SetPoint("LEFT", swingRow, "LEFT", 4 + (conf.labelX or 0), conf.labelY or 0)
    swingRow._time:ClearAllPoints()
    swingRow._time:SetPoint("RIGHT", swingRow, "RIGHT", -4 + (conf.timeX or 0), conf.timeY or 0)
    ApplyRowTag(swingRow, conf)
    -- A combined off-hand row shows no text; the Main Hand row keeps its own.
    local merged = swingRow._merged
    ApplyRowLabel(swingRow, conf)
    if conf.showTime ~= false and not merged then
        swingRow._time:Show()
    else
        swingRow._time:Hide()
    end
    ApplyRangeLook(swingRow, conf)
    -- Rounded corners (CludesUI_RoundedCorners.lua; nothing at radius 0).
    -- A combined off-hand row is only a spark over the Main Hand row: no fill.
    -- The stock frames are square.
    local radius = (not stock and conf.cornerRadius) or 0
    if radius > 0 then
        CludesUI.RoundCorners(swingRow, radius, {
            roots = { clipper },
            textures = { swingRow._bg },
            border = not merged and borderTex or nil,
            clip = clipper,
            style = conf.borderTexture or "solid",
            corners = conf.cornerMask,
        })
    else
        CludesUI.RoundCorners(swingRow, 0)
    end
end

local function ApplyLook(conf)
    local wid, hgt = conf.width or 220, conf.height or 12
    for i = 1, #SwingState.rows do
        ApplyRowLook(SwingState.rows[i], conf, wid, hgt)
    end
end

-- Restyles the rows RefreshRows marked (see there).
local function RestyleMarked(conf)
    local wid, hgt = conf.width or 220, conf.height or 12
    for i = 1, #SwingState.rows do
        local swingRow = SwingState.rows[i]
        if swingRow._restyle then ApplyRowLook(swingRow, conf, wid, hgt) end
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
    if not (conf and SwingState.built) then return end
    local wantRange = conf.enabled and conf.rangeCheck ~= false
    local mhShown, marked = false, false
    for i = 1, #SwingState.rows do
        local swingRow = SwingState.rows[i]
        local defaults = swingRow._def
        local canSwing = RowWanted(defaults, conf, swingRow)
        ApplyRowLabel(swingRow, conf)
        if canSwing then
            if not swingRow:IsShown() then
                swingRow._restyle = true
                marked = true
            end
            swingRow:Show()
        else
            swingRow:Hide()
            if swingRow._live then IdleRow(swingRow, conf) end
        end
        if defaults.type == SWING.MainHand then mhShown = canSwing end
        local merged = (
            defaults.type == SWING.OffHand
            and canSwing
            and mhShown
            and conf.combineHands
            and not ShieldOff(conf)
        )
                and true
            or nil
        if merged ~= swingRow._merged then
            swingRow._merged = merged
            swingRow._restyle = true
            marked = true
        end
        SetRangeCheck(defaults.type, wantRange and canSwing)
    end
    if Layout(conf) and CludesUI.NotifyElementResized then CludesUI.NotifyElementResized(UNLOCK_KEY) end
    SyncAllRanges()
    return marked
end

-- Position: the unlock anchor chain first, then a saved unlock position, then
-- the CENTER offsets. Same three-way split as the GCD bar.
local function ApplyPosition(conf)
    local wid, hgt = Size(conf)
    shellFrame:SetSize(wid, hgt)
    if CludesUI._TryOverrideAnchor and CludesUI._TryOverrideAnchor(UNLOCK_KEY, shellFrame) then return end
    if CludesUI._unlockActive then return end
    local place = conf.unlockPos
    if place and place.point then
        local anchored = CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(UNLOCK_KEY)
        if anchored and shellFrame:GetLeft() then return end
        local rp = place.relPoint or place.point
        local sx, sy = mod.SnapXY(place.x or 0, place.y or 0, shellFrame, place)
        shellFrame:ClearAllPoints()
        shellFrame:SetPoint(place.point, UIParent, rp, sx, sy)
    else
        shellFrame:ClearAllPoints()
        shellFrame:SetPoint("CENTER", UIParent, "CENTER", conf.anchorX or 0, conf.anchorY or 0)
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------

-- The movement edges a guide row holds and restarts its aim on, only while an
-- aim can run: the Movement Guide on, a wand or Auto Shot class, and the shot on.
-- Registering reads where the player is now (GetUnitSpeed, restricted = still).
local function ApplyMoveEvents(conf)
    if not SwingState.events then return end
    if SwingState.aimClass and GuideOn(conf) and SwingState.repeatOn then
        if not SwingState.moveEvents then
            SwingState.moveEvents = true
            shellFrame:RegisterEvent("PLAYER_STARTED_MOVING")
            shellFrame:RegisterEvent("PLAYER_STOPPED_MOVING")
            local swingSpeed = GetUnitSpeed("player")
            SwingState.moving = (IsPlainVal(swingSpeed) and swingSpeed > 0) and true or false
        end
    elseif SwingState.moveEvents then
        SwingState.moveEvents = nil
        shellFrame:UnregisterEvent("PLAYER_STARTED_MOVING")
        shellFrame:UnregisterEvent("PLAYER_STOPPED_MOVING")
        SwingState.moving = false
    end
end

shellFrame:SetScript("OnEvent", function(self, evt, a1, a2, a3, _a4, a5)
    local conf = P()
    if not (conf and conf.enabled and SwingState.built) then return end
    if evt == "PLAYER_SWING" then
        -- a1 = swingDuration, a2 = swingType
        if not (IsPlainVal(a1) and IsPlainVal(a2)) then return end
        local swingRow = SwingState.byType[a2]
        if swingRow then
            -- A swing proves its slot can swing: a row hidden only because its
            -- speed read was restricted comes back with it.
            if not swingRow:IsShown() and not swingRow._canSwing and conf[swingRow._def.show] ~= false then
                swingRow._canSwing = true
                if RefreshRows(conf) then RestyleMarked(conf) end
            end
            if swingRow:IsShown() then StartRow(swingRow, a1, conf) end
        end
        PaintQueue(conf)
    elseif evt == "ACTIONBAR_UPDATE_STATE" then
        PaintQueue(conf)
    elseif evt == "START_AUTOREPEAT_SPELL" or evt == "STOP_AUTOREPEAT_SPELL" then
        SwingState.repeatOn = evt == "START_AUTOREPEAT_SPELL"
        if not SwingState.repeatOn then
            -- No shot is coming: an aim in progress ends with it.
            local swingRow = SwingState.byType[SWING.Ranged]
            if swingRow and swingRow._aiming then IdleRow(swingRow, conf) end
        end
        ApplyMoveEvents(conf)
        SyncWaiting(conf)
        PaintActive(conf)
    elseif evt == "PLAYER_STARTED_MOVING" then
        -- Moving holds the shot: an aim in progress stops and waits.
        SwingState.moving = true
        local swingRow = SwingState.byType[SWING.Ranged]
        if swingRow and swingRow._aiming then EnterWaiting(swingRow, conf) end
    elseif evt == "PLAYER_STOPPED_MOVING" then
        -- Standing still again: a shot held, or stopped for only after Stop by,
        -- fires AIM_TIME from now plus the round trip (the stop reaches the
        -- server, the swing comes back). Both guide styles show it as an aim.
        SwingState.moving = false
        local swingRow = SwingState.byType[SWING.Ranged]
        if swingRow and swingRow._live and GuideRow(swingRow, conf) and AttackOn(swingRow._def) then
            local nowTime = GetTime()
            if
                swingRow._waiting or (swingRow._aimAt and not swingRow._aiming and nowTime >= swingRow._aimAt)
            then
                local shot = nowTime + AIM_TIME + (NetLatency() or 0)
                if swingRow._end and swingRow._end > shot then shot = swingRow._end end
                EnterAim(swingRow, conf, nowTime, shot)
                swingRow._due = shot
            end
        end
    elseif evt == "PLAYER_ENTER_COMBAT" or evt == "PLAYER_LEAVE_COMBAT" then
        SwingState.meleeOn = evt == "PLAYER_ENTER_COMBAT"
        SyncWaiting(conf)
        PaintActive(conf)
    elseif evt == "PLAYER_DEAD" then
        for i = 1, #SwingState.rows do
            if SwingState.rows[i]._live then IdleRow(SwingState.rows[i], conf) end
        end
        SwingState.meleeOn, SwingState.repeatOn = false, false
        ApplyMoveEvents(conf)
        PaintActive(conf)
    elseif evt == "PLAYER_SWING_RANGE_UPDATE" then
        -- a1 = swingType, a2 = isInRange, a3 = checksRange
        if not (IsPlainVal(a1) and IsPlainVal(a2) and IsPlainVal(a3)) then return end
        local swingRow = SwingState.byType[a1]
        if swingRow then SetOutOfRange(swingRow, a3 == true and a2 == false) end
    elseif evt == "PLAYER_TARGET_CHANGED" then
        -- Re-assert the range flags before the re-read (see SetRangeCheck).
        local wantRange = conf.rangeCheck ~= false
        for i = 1, #SwingState.rows do
            local swingRow = SwingState.rows[i]
            SetRangeCheck(swingRow._def.type, wantRange and swingRow:IsShown())
        end
        SyncAllRanges()
        -- A new target: the Target Swing row starts over, shown or not by it.
        local tgtRow = conf.showTGT == true and SwingState.byType.target
        if tgtRow then
            if tgtRow._live then IdleRow(tgtRow, conf) end
            if RefreshRows(conf) then RestyleMarked(conf) end
        end
    elseif evt == "UNIT_COMBAT" then
        -- a1 = unit, a2 = action, a5 = school
        TargetCombat(conf, a1, a2, a5)
    elseif evt == "UNIT_FACTION" or evt == "UNIT_FLAGS" then
        if TargetRowChanged(conf) and RefreshRows(conf) then RestyleMarked(conf) end
    elseif evt == "UNIT_AURA" then
        -- a2 = updateInfo
        SealAuraUpdate(a2)
    elseif evt == "UNIT_SPELLCAST_SUCCEEDED" then
        -- a3 = spellID
        SealCast(a3)
    elseif evt == "UNIT_SPELLCAST_STOP" or evt == "UNIT_SPELLCAST_CHANNEL_STOP" then
        SwingState.castEnd = nil
        CastTick(conf)
    elseif evt:find("^UNIT_SPELLCAST_") then
        ReadCast()
        CastTick(conf)
    else
        -- WEAPON_SLOT_CHANGED / PLAYER_EQUIPMENT_CHANGED (off hand slot only) /
        -- UNIT_ATTACK_SPEED / PLAYER_ENTERING_WORLD
        if evt == "PLAYER_EQUIPMENT_CHANGED" and a1 ~= OFFHAND_SLOT then return end
        if RefreshRows(conf) then RestyleMarked(conf) end
        if TracksAttack(conf) then
            -- A loading screen can end an attack without its edge reaching us.
            if evt == "PLAYER_ENTERING_WORLD" then
                SeedActiveSwings()
                ApplyMoveEvents(conf)
            end
            -- A row the weapon change just showed takes its attack's state.
            SyncWaiting(conf)
            PaintActive(conf)
        end
    end
end)

local function RegisterEvents()
    if SwingState.events then return end
    SwingState.events = true
    shellFrame:RegisterEvent("PLAYER_SWING")
    shellFrame:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
    shellFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    shellFrame:RegisterEvent("WEAPON_SLOT_CHANGED")
    shellFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    shellFrame:RegisterEvent("PLAYER_DEAD")
    shellFrame:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
end

-- The queue paint's event is registered only while the highlight is on (it is
-- the one chatty event here).
local function ApplyQueueEvents(conf)
    if not SwingState.events then return end
    if QueueOn(conf) and #SwingState.queueSpells > 0 then
        shellFrame:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    else
        shellFrame:UnregisterEvent("ACTIONBAR_UPDATE_STATE")
    end
end

-- Equipment changes matter only to the shield handling.
local function ApplyShieldEvents(conf)
    if not SwingState.events then return end
    if ShieldAware(conf) then
        shellFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    else
        shellFrame:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
    end
end

-- The auto attack and auto-repeat edges, only while something reads them
-- (TracksAttack).
local function ApplyActiveEvents(conf)
    if not SwingState.events then return end
    if TracksAttack(conf) then
        shellFrame:RegisterEvent("START_AUTOREPEAT_SPELL")
        shellFrame:RegisterEvent("STOP_AUTOREPEAT_SPELL")
        shellFrame:RegisterEvent("PLAYER_ENTER_COMBAT")
        shellFrame:RegisterEvent("PLAYER_LEAVE_COMBAT")
    else
        shellFrame:UnregisterEvent("START_AUTOREPEAT_SPELL")
        shellFrame:UnregisterEvent("STOP_AUTOREPEAT_SPELL")
        shellFrame:UnregisterEvent("PLAYER_ENTER_COMBAT")
        shellFrame:UnregisterEvent("PLAYER_LEAVE_COMBAT")
    end
end

-- Seal Colors: the player's aura and cast-success edges, only for a paladin
-- with the option on.
local function ApplySealEvents(conf)
    if not SwingState.events then return end
    if SealOn(conf) then
        if not SwingState.sealEvents then
            SwingState.sealEvents = true
            shellFrame:RegisterUnitEvent("UNIT_AURA", "player")
            shellFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        end
        ScanSeal()
    else
        if SwingState.sealEvents then
            SwingState.sealEvents = nil
            shellFrame:UnregisterEvent("UNIT_AURA")
            shellFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        end
        SetSeal(false)
    end
end

-- Target Swing: the combat edges of the player and target, and the target's
-- hostility edges, only while the row is ticked.
local function ApplyTargetEvents(conf)
    if not SwingState.events then return end
    local on = conf.showTGT == true
    if on == (SwingState.tgtEvents or false) then return end
    SwingState.tgtEvents = on or nil
    if on then
        shellFrame:RegisterUnitEvent("UNIT_COMBAT", "player", "target")
        shellFrame:RegisterUnitEvent("UNIT_FACTION", "target")
        shellFrame:RegisterUnitEvent("UNIT_FLAGS", "target")
    else
        shellFrame:UnregisterEvent("UNIT_COMBAT")
        shellFrame:UnregisterEvent("UNIT_FACTION")
        shellFrame:UnregisterEvent("UNIT_FLAGS")
    end
end

-- Cast Clip: the player's cast edges, only while the option is on.
local function ApplyCastEvents(conf)
    if not SwingState.events then return end
    local on = conf.castClip == true
    if on ~= (SwingState.castEvents or false) then
        SwingState.castEvents = on or nil
        for i = 1, #CAST_EVENTS do
            if on then
                shellFrame:RegisterUnitEvent(CAST_EVENTS[i], "player")
            else
                shellFrame:UnregisterEvent(CAST_EVENTS[i])
            end
        end
    end
    if on then
        ReadCast()
    else
        SwingState.castEnd = nil
    end
end

local function UnregisterEvents()
    if not SwingState.events then return end
    SwingState.events = nil
    SwingState.sealEvents, SwingState.castEvents, SwingState.tgtEvents = nil, nil, nil
    SwingState.moveEvents, SwingState.moving = nil, false
    shellFrame:UnregisterAllEvents()
end

-------------------------------------------------------------------------------
--  Build / apply
-------------------------------------------------------------------------------

local function EnsureBuilt()
    if SwingState.built then return end
    SwingState.built = true
    shellFrame:SetFrameLevel(15)
    for i = 1, #ROWS do
        local swingRow = BuildRow(ROWS[i])
        SwingState.rows[i] = swingRow
        SwingState.byType[ROWS[i].type] = swingRow
    end
    local _, class = UnitClass("player")
    SwingState.aimClass = AIM_CLASS[class]
    -- On-next-swing spell names, once per session, for a class that has one.
    local ids = CludesUI.FOREVER_NEXT_SWING and CludesUI.FOREVER_NEXT_SWING[class]
    if ids and C_Spell and C_Spell.GetSpellName then
        for i = 1, #ids do
            local name = C_Spell.GetSpellName(ids[i])
            if IsPlainVal(name) and name then
                local color = QUEUE_COLORS[ids[i]] or QUEUE_COLOR
                SwingState.queueSpells[#SwingState.queueSpells + 1] = {
                    id = ids[i],
                    key = color.key,
                    shared = color.shared,
                    r = color.r,
                    g = color.g,
                    b = color.b,
                    name = name,
                }
            end
        end
    end
    -- Seal names, once per session, for a paladin.
    if class == "PALADIN" and C_Spell and C_Spell.GetSpellName then
        for i = 1, #SEALS do
            local name = C_Spell.GetSpellName(SEALS[i].id)
            if IsPlainVal(name) and name then SwingState.sealByName[name] = SEALS[i] end
        end
    end
    -- Mouseover hover-reveal: same plain-table proxy the class/power/health bars
    -- register, gated on the eligibility flag ST_UpdateVisibility maintains.
    if not SwingState.moHooked and CludesUI.RegisterMouseoverTarget then
        SwingState.moHooked = true
        local proxy = {}
        proxy.GetRect = function() return shellFrame:GetRect() end
        proxy.GetEffectiveScale = function() return shellFrame:GetEffectiveScale() end
        proxy.SetAlpha = function() end
        proxy.EnableMouse = function() end
        proxy.Show = function() CludesUI.SetElementVisibility(shellFrame, true) end
        proxy.Hide = function() CludesUI.SetElementVisibility(shellFrame, false) end
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
local function TearDownSwing()
    if not SwingState.built then return end
    UnregisterEvents()
    SwingState.seeded = nil -- the edges stop here: re-read on the next enable
    local conf = P()
    for i = 1, #SwingState.rows do
        local swingRow = SwingState.rows[i]
        if swingRow._live then IdleRow(swingRow, conf) end
        SetRangeCheck(swingRow._def.type, false)
    end
    local ERB = mod.ERB
    if ERB and ERB._moEligible then ERB._moEligible[MO_KEY] = false end
    CludesUI.SetElementVisibility(shellFrame, false)
end

-- A running timer's events and attack state: the full apply and a resume
-- after a park both start here.
local function Arm(conf)
    RegisterEvents()
    ApplyQueueEvents(conf)
    ApplyActiveEvents(conf)
    ApplyShieldEvents(conf)
    ApplySealEvents(conf)
    ApplyCastEvents(conf)
    ApplyTargetEvents(conf)
    -- Highlight turned off with an attack queued: the paint below must clear it.
    if not QueueOn(conf) then SwingState.queued = false end
    -- Attack state: read once per enable, kept by the edges while on.
    if not TracksAttack(conf) then
        SwingState.seeded = nil
    elseif not SwingState.seeded then
        SeedActiveSwings()
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
    for i = 1, #SwingState.rows do
        local swingRow = SwingState.rows[i]
        local object = swingRow._durObj
        if SwingState.sample then
            -- A combined off hand parks empty, so its spark shows at the far
            -- end from a full Main Hand bar's.
            local oh = swingRow._merged
            object:SetTimeFromStart(GetTime() - 1, 1)
            swingRow._bar:SetTimerDuration(object, IMMEDIATE, oh and DIR.RemainingTime or DIR.ElapsedTime)
            swingRow._bar:SetValue(oh and 0 or 1)
            SyncTimeText(swingRow, conf)
            swingRow._time:SetText("1.2")
            UpdateZones(swingRow, conf, swingRow._dur or 2)
        elseif swingRow._live and not swingRow._waiting and swingRow._dur then
            local guide, wind = GuideRow(swingRow, conf), WindRow(swingRow, conf)
            if not guide and (swingRow._aiming or swingRow._aimAt) then
                -- Movement Guide turned off mid-swing: back to one plain swing.
                swingRow._aiming, swingRow._aimAt = nil, nil
                ApplyRowFill(swingRow, conf)
            end
            if swingRow._aiming then
                object:SetTimeFromStart(swingRow._aimFrom, swingRow._end - swingRow._aimFrom)
                swingRow._bar:SetTimerDuration(
                    object,
                    IMMEDIATE,
                    conf.depleteFill and DIR.ElapsedTime or DIR.RemainingTime
                )
                HideZones(swingRow)
                PlaceAimLatency(swingRow, conf, swingRow._aimFrom, swingRow._end)
            else
                local start = swingRow._end - swingRow._dur
                swingRow._start = start
                if guide then swingRow._aimAt = swingRow._end - AIM_TIME - (swingRow._rtt or 0) end
                object:SetTimeFromStart(
                    start,
                    wind and math.max(swingRow._aimAt - start, 0.01) or swingRow._dur
                )
                swingRow._bar:SetTimerDuration(
                    object,
                    IMMEDIATE,
                    conf.depleteFill and DIR.RemainingTime or DIR.ElapsedTime
                )
                UpdateZones(swingRow, conf, swingRow._dur)
            end
            ArmEdges(swingRow, conf)
            SyncTimeText(swingRow, conf)
        elseif ShouldWait(swingRow, conf) then
            EnterWaiting(swingRow, conf)
        else
            IdleRow(swingRow, conf)
        end
    end
    CastTick(conf)
end

-- Back from a park (a shapeshift or talent edit that no longer rules the timer
-- out): events and the row state come back. The rows kept their spot and look
-- while parked (a settings change made then runs the full apply, which styles
-- them), so only rows that came back are restyled.
local function Resume(conf)
    Arm(conf)
    if RefreshRows(conf) then RestyleMarked(conf) end
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
    if not SwingState.built then return end
    local conf = P()
    local ERB = mod.ERB
    if not (conf and conf.enabled and ERB) then return end
    local ruled = RuledOut(conf)
    if ruled ~= (SwingState.ruled or false) then
        -- Set first: the row edges below can run this pass again.
        SwingState.ruled = ruled
        if not CludesUI._unlockActive then
            if ruled then
                TearDownSwing()
            else
                Resume(conf)
            end
        end
    end
    local vis
    if CludesUI._unlockActive then
        vis = true
    elseif SwingState.ruled then
        vis = false
    else
        vis = not ERB._inVehicle and mod.ShouldShowBar(conf)
        if vis and conf.hideWhenIdle and SwingState.live == 0 then vis = false end
    end
    ERB._moEligible = ERB._moEligible or {}
    ERB._moEligible[MO_KEY] = (vis == "mouseover")
    CludesUI.SetElementVisibility(shellFrame, vis == true)
end

-- The colour a row's spark paints (by colour key), for the options swatch;
-- unset = true gives the tint it has without a colour of its own.
function mod.ST_SparkColor(key, unset)
    local conf = P()
    if not conf then return 1, 1, 1, 1 end
    for i = 1, #ROWS do
        if ROWS[i].key == key then
            local swingRow = SwingState.rows[i]
            return SparkColor(conf, ROWS[i], swingRow and swingRow._merged, unset)
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
    if conf and conf.enabled and HasTalentConds(conf) then CludesUI.TalentCondInvalidate() end
end

function mod.ST_Apply()
    local conf = P()
    if not conf or not conf.enabled then
        SwingState.ruled = nil
        TearDownSwing()
        return
    end
    SwingState.ruled = RuledOut(conf)
    -- Ruled out by form or talents (outside Unlock Mode, which shows it with its
    -- sample): laid out and styled as usual, so anchored elements keep their
    -- spot and a resume needs no restyle, then parked like switched off (no
    -- events, every row idle, alpha 0).
    local park = SwingState.ruled and not CludesUI._unlockActive
    EnsureBuilt()
    shellFrame:SetFrameStrata(conf.frameStrata or "MEDIUM")
    shellFrame:Show()
    if not park then Arm(conf) end
    -- Size and stack the rows BEFORE styling them: the textured border is a
    -- BackdropTemplate nine-slice keyed on first setup, and set up on a 0x0
    -- row it never paints (cast/GCD bars size first for the same reason).
    RefreshRows(conf)
    ApplyPosition(conf)
    ApplyLook(conf)
    if park then
        TearDownSwing()
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
    if not MK then return nil end
    local Pix = CludesUI.PP

    if not SwingState.unlockHooked and CludesUI.RegisterUnlockModeListener then
        SwingState.unlockHooked = true
        CludesUI:RegisterUnlockModeListener(UNLOCK_KEY, function(isActive)
            -- Sample fill while the movers are up so an idle bar has something
            -- to drag; ST_Apply restores the real state on exit.
            SwingState.sample = isActive and true or nil
            if mod.ST_Apply then mod.ST_Apply() end
        end)
    end

    local function save(key, anchorPoint, relPoint, posX, posY)
        if not anchorPoint then return end
        local conf = P()
        if not conf then return end
        conf.unlockPos = { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
        if not CludesUI._unlockActive and SwingState.built then
            shellFrame:ClearAllPoints()
            shellFrame:SetPoint(anchorPoint, UIParent, relPoint or anchorPoint, posX, posY)
        end
    end
    local function load()
        local conf = P()
        local place = conf and conf.unlockPos
        if not place then return nil end
        return { point = place.point, relPoint = place.relPoint or place.point, x = place.x, y = place.y }
    end
    local function clear()
        local conf = P()
        if not conf then return end
        conf.unlockPos = nil
        conf.anchorX = 0
        conf.anchorY = -130
    end
    local function apply()
        local conf = P()
        local place = conf and conf.unlockPos
        if not (place and SwingState.built) then return end
        local sx, sy = mod.SnapXY(place.x, place.y, shellFrame, place)
        shellFrame:ClearAllPoints()
        shellFrame:SetPoint(place.point, UIParent, place.relPoint or place.point, sx, sy)
    end

    return MK({
        key = UNLOCK_KEY,
        label = "Swing Timer",
        group = "Resource Bars",
        order = 508,
        getFrame = function() return SwingState.built and shellFrame or nil end,
        isHidden = function()
            local conf = P()
            return not (conf and conf.enabled)
        end,
        getSize = function() return Size(P()) end,
        -- What a row draws outside itself: every row spans the full width and
        -- the outer rows' edges are the stack's, so one row's reach. A stock
        -- style's frame rim, else the textured border (ns.ERB_EuiBorderPad).
        getMatchPad = function()
            local conf = P()
            local style = mod.ST_Style()
            if style == "blizzard" then return mod.ERB_BlizzMatchPad(false) end
            if style == "classic" then
                return mod.ERB_ClassicMatchPad(0, 0, false, mod.ERB_ClassicFrameK(conf))
            end
            return mod.ERB_EuiBorderPad(conf)
        end,
        -- Rebuild is a full ApplyAll and the settle pass hands the size again
        -- after every resize burst: an unchanged size rebuilds nothing.
        setWidth = function(_, wid)
            local conf = P()
            if not conf then return end
            local val = Pix.Snap(math.max(wid, 10))
            if conf.width == val then return end
            conf.width = val
            Rebuild()
        end,
        -- The mover resizes the whole stack; the per-row height is what is stored.
        setHeight = function(_, hgt)
            local conf = P()
            if not conf then return end
            -- A spec layout holds the stack height of the character that saved
            -- it, whose row count can differ; the row height is the profile's.
            if CludesUI._unlockLayerApplying then return end
            local num = ShownCount()
            local sp = RowGap(conf)
            local val = Pix.Snap(math.max((hgt - (num - 1) * sp) / num, 4))
            if conf.height == val then return end
            conf.height = val
            Rebuild()
        end,
        savePos = save,
        loadPos = load,
        clearPos = clear,
        applyPos = apply,
    })
end
