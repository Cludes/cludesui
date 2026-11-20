if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIQoL_MovementAlert.lua
--  Three independent on-screen trackers for class mobility abilities:
--    1. Movement Cooldown Alert -- shows the current spec's mobility spell(s)
--       counting down on cooldown (text / icon / bar), so you always know
--       exactly when your gap-closer/escape is back up.
--    2. Time Spiral -- flashes a "FREE MOVEMENT" banner whenever a tracked
--       mobility spell's cooldown is proc-reset (Blizzard's generic
--       "spell activation overlay glow" on a spell we're tracking). A second,
--       CDM-bar based implementation of the same proc also exists as the
--       "timespiral" Tracked Buff Bar preset in
--       CludesUICooldownManager\CUI_CDM_BuffBarPresets.lua (
--       TIME_SPIRAL_TRIGGERS/TIME_SPIRAL_GLOW_FILTERS) for users who run CDM
--       bars. The two are intentionally independent (this one needs no CDM
--       bar at all), but they track the same spell/talent-filter lists --
--       keep both in sync if either list changes.
--    3. Gateway Shard -- Warlock only. Alerts when the Gateway Control Shard
--       item is usable.
--  Sits under CludesUIQoLDB.profile.movementAlert, an additive sibling of
--  battleRes/bloodlust/cursor (see CludesUIQoL_BattleRes.lua). Zero cost
--  when idle: no combat/spell events are registered until a tracker's master
--  toggle is on.
-------------------------------------------------------------------------------

local ns = select(2, ...)

local IsSecret = CludesUI.IsSecret

local inCombat = false
local playerClassToken = select(2, UnitClass("player")) -- class never changes: resolved once

-------------------------------------------------------------------------------
--  Mobility spell tables
--  spellID lists are keyed by class -> specID. These are the actual ability
--  IDs and WILL drift as talents/expansions change -- validate against the
--  live client before shipping and keep an eye on the in-options "Tracked
--  Spells" add/override list, which lets users self-correct gaps without an
--  addon update. The `filter` sub-table (Time Spiral cast filtering) mirrors
--  CUI_CDM_BuffBarPresets.lua's TIME_SPIRAL_GLOW_FILTERS -- keep both in sync.
-------------------------------------------------------------------------------
local MOVEMENT_ABILITIES = {
    DEATHKNIGHT = {
        [250] = { 48265, 212552 },
        [251] = { 48265, 212552 },
        [252] = { 48265, 444010, 444347, 212552 },
    },
    DEMONHUNTER = {
        [577] = { 195072 },
        [581] = { 189110 },
        [1480] = { 1234796 },
        filter = {
            [427640] = { 198793, 370965, 195072 },
            [427794] = { 195072 },
        },
    },
    DRUID = {
        [102] = { 102401, 252216, 1850, 102417 },
        [103] = { 102401, 252216, 1850, 102417 },
        [104] = { 102401, 252216, 106898, 1850, 102417 },
        [105] = { 102401, 252216, 1850, 102417 },
    },
    EVOKER = { [1467] = { 358267 }, [1468] = { 358267 }, [1473] = { 358267 } },
    HUNTER = { [253] = { 186257, 781 }, [254] = { 186257, 781 }, [255] = { 186257, 781 } },
    MAGE = { [62] = { 212653, 1953 }, [63] = { 212653, 1953 }, [64] = { 212653, 1953 } },
    MONK = {
        [268] = { 115008, 109132, 119085, 361138 },
        [269] = { 109132, 119085, 361138, 101545 },
        [270] = { 109132, 119085, 361138 },
    },
    PALADIN = { [65] = { 190784 }, [66] = { 190784 }, [70] = { 190784 } },
    PRIEST = { [256] = { 121536, 73325 }, [257] = { 121536, 73325 }, [258] = { 121536, 73325 } },
    ROGUE = { [259] = { 36554, 2983 }, [260] = { 195457, 2983 }, [261] = { 36554, 2983 } },
    SHAMAN = {
        [262] = { 79206, 90328, 192063, 58875 },
        [263] = { 90328, 192063, 58875 },
        [264] = { 79206, 90328, 192063, 58875 },
    },
    WARLOCK = {
        [265] = { 48020, 111400 },
        [266] = { 48020, 111400 },
        [267] = { 48020, 111400 },
        filter = { [385899] = { 385899 } },
    },
    WARRIOR = { [71] = { 6544 }, [72] = { 6544 }, [73] = { 6544 } },
}

-- Buff-active spells: the label shown while the aura is up, in place of a
-- cooldown countdown. Membership here decides HOW a spell is tracked, never
-- whether it is on -- Burning Rush ships unchecked via MOVEMENT_DEFAULT_OFF
-- below. It has no cooldown and no duration to count down, so the presence of
-- its aura is the only thing there is to track.
local BUFF_ACTIVE_SPELLS = {
    [111400] = "Burning Rush Active!",
}

local SPELL_ALIAS_GROUPS = {
    { 102401, 16979, 102417, 252216 },
    { 106898, 77761, 77764 },
}

local SPELL_CATEGORY_DURATION = {
    [102401] = 15,
    [16979] = 15,
    [102417] = 15,
    [252216] = 15,
    [1850] = 18,
    [106898] = 120,
    [77761] = 120,
}

local TALENT_CD_REDUCTIONS = {
    { talent = 451041, trigger = 116841, spell = 109132, reduce = 5 },
    { talent = 451041, trigger = 116841, spell = 115008, reduce = 5 },
}
local TALENT_CD_TRIGGER_SPELLS = {}
for _, mod in ipairs(TALENT_CD_REDUCTIONS) do
    TALENT_CD_TRIGGER_SPELLS[mod.trigger] = true
end

CludesUI.MOVEMENT_ABILITIES = MOVEMENT_ABILITIES

-- Preset spells that default to DISABLED: with no saved override, these are
-- not tracked (checking their box writes an explicit enabled=true override;
-- everything else stays enabled-by-absence). Shared with the options grid
-- via the export so the checkboxes and the tracker read the same truth.
local MOVEMENT_DEFAULT_OFF = {
    [2983] = true, -- Sprint
    [73325] = true, -- Leap of Faith
    [106898] = true,
    [77761] = true,
    [77764] = true, -- Stampeding Roar
    [1850] = true, -- Dash
    [252216] = true, -- Tiger Dash
    [212552] = true, -- Wraith Walk
    [79206] = true, -- Spiritwalker's Grace
    [58875] = true,
    [90328] = true, -- Spirit Walk
    [111400] = true, -- Burning Rush (off by default since 8.5.3)
}
CludesUI._MovementDefaultOff = MOVEMENT_DEFAULT_OFF

-- Effective enabled state for a preset/tracked spell id: an explicit saved
-- enabled wins; otherwise absence means enabled unless default-off.
local function SpellEffectivelyEnabled(overrideId, alertSpell)
    if overrideId and overrideId.enabled ~= nil then
        return overrideId.enabled ~= false
    end
    return not MOVEMENT_DEFAULT_OFF[alertSpell]
end

local SPELL_ALIAS_MAP = {}
do
    for _, set in ipairs(SPELL_ALIAS_GROUPS) do
        for _, ident in ipairs(set) do
            SPELL_ALIAS_MAP[ident] = set
        end
        for _, ident in ipairs(set) do
            if not SPELL_CATEGORY_DURATION[ident] then
                for _, other in ipairs(set) do
                    if SPELL_CATEGORY_DURATION[other] then
                        SPELL_CATEGORY_DURATION[ident] = SPELL_CATEGORY_DURATION[other]
                        break
                    end
                end
            end
        end
    end
end

local function GetKnownCategoryDuration(alertSpell)
    if SPELL_CATEGORY_DURATION[alertSpell] then
        return SPELL_CATEGORY_DURATION[alertSpell]
    end
    local set = SPELL_ALIAS_MAP[alertSpell]
    if set then
        for _, ident in ipairs(set) do
            if SPELL_CATEGORY_DURATION[ident] then
                return SPELL_CATEGORY_DURATION[ident]
            end
        end
    end
    return 0
end

-- Shared lockout vs. the ability's own cooldown. Casting one charge-type
-- ability briefly locks out its siblings through a start-recovery/cooldown
-- category -- Druid Skull Bash does this to Wild Charge for ~2s -- and the
-- client reports that window through the very same cooldown fields a real
-- cooldown uses, with isOnGCD false, so the GCD gate above it never catches
-- it. The discriminator is magnitude: a window far shorter than the ability's
-- own base cooldown cannot BE that cooldown, so it is not something to alert
-- on. Blizzard classifies the same way in Blizzard_CooldownViewer
-- (MIN_GLOBAL_RECOVERY_TIME), just at GCD length. Gated on the base cooldown
-- being the longer of the two, so a user-added spell that genuinely has a
-- 1-2s cooldown still tracks normally.
local MIN_REAL_COOLDOWN = 3

-- entry.baseDuration is learned from LIVE cooldown reads, and those are secret in
-- instanced content, so an entry first cached there carries no base at all. That
-- disabled the classifier below exactly where the lockout is most visible: in
-- combat. Static spell data is not live cooldown state and stays readable, so
-- fall back to it rather than treating an unknown base as "cannot classify".
-- GetSpellBaseCooldown is the GLOBAL (client-verified: no C_Spell form exists).
local function ResolveBaseDuration(record)
    local base = record and record.baseDuration
    if type(base) == "number" and not IsSecret(base) then
        return base
    end
    local ident = record and (record.baseSpellId or record.spellId)
    if not ident then
        return 0
    end
    if GetSpellBaseCooldown then
        local ms = GetSpellBaseCooldown(ident)
        if type(ms) == "number" and not IsSecret(ms) then
            local secs = ms / 1000
            if secs > MIN_REAL_COOLDOWN then
                return secs
            end
        end
    end
    return GetKnownCategoryDuration(ident)
end

local function IsLockoutWindow(record, seconds)
    if type(seconds) ~= "number" or IsSecret(seconds) then
        return false
    end
    local base = ResolveBaseDuration(record)
    if type(base) ~= "number" or base <= MIN_REAL_COOLDOWN then
        return false
    end
    return seconds < MIN_REAL_COOLDOWN
end

-- The same classification when the window is SECRET, which is the case Lua cannot
-- do at all: IsLockoutWindow refuses a secret and lets it through, so in instanced
-- content the lockout reached the display with a number on it. Hand the comparison
-- to the engine instead, with the curve trick the charge-visibility path already
-- uses: a step curve is 0 below the threshold and 1 above, the duration object
-- evaluates it in C, and the result drives alpha. Never read the result, only feed it.
local lockoutAlphaCurve = nil -- nil = not built, false = API unavailable
local function GetLockoutAlphaCurve()
    if lockoutAlphaCurve == nil then
        if C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType then
            local c = C_CurveUtil.CreateCurve()
            c:SetType(Enum.LuaCurveType.Step)
            c:AddPoint(0, 0) -- cross-ability lockout: hide
            c:AddPoint(MIN_REAL_COOLDOWN, 1) -- the ability's own cooldown: show
            lockoutAlphaCurve = c
        else
            lockoutAlphaCurve = false
        end
    end
    return lockoutAlphaCurve or nil
end

-- 1, or a possibly-secret 0/1 from the engine. Gated on the entry's own base being
-- the longer of the two, so a user-added spell with a genuine 1-2s cooldown still
-- tracks normally -- the same condition IsLockoutWindow applies.
local function LockoutAlpha(record, dur)
    if not dur or not dur.EvaluateTotalDuration then
        return 1
    end
    local base = ResolveBaseDuration(record)
    if type(base) ~= "number" or base <= MIN_REAL_COOLDOWN then
        return 1
    end
    local curve = GetLockoutAlphaCurve()
    if not curve then
        return 1
    end
    return dur:EvaluateTotalDuration(curve, 1) or 1
end

-------------------------------------------------------------------------------
--  DB
-------------------------------------------------------------------------------
local defaultSet = {
    profile = {
        movementAlert = {
            -- nil = feature fully disabled (zero cost); { WARRIOR = true, ... }
            -- = enabled while playing a checked class (Totem Bar convention).
            enabledClasses = nil,
            combatOnly = false,
            -- text_nd = "Name Duration", text_dn = "Duration Name"; the
            -- legacy "text" value renders identically to text_dn.
            displayMode = "text", -- text (legacy) | text_nd | text_dn | text_d (number only) | icon | bar
            textSize = 24,
            iconSize = 40,
            textColorR = 1,
            textColorG = 1,
            textColorB = 1,
            textColorUseClass = false,
            barShowIcon = true,
            barShowDuration = true, -- bar mode's countdown number
            barTexture = "none", -- key into the bar texture catalog
            precision = 1,
            spellOverrides = {}, -- [spellId] = { enabled, customText, class }
            pos = nil, -- { point, relPoint, x, y, width, height }
            maSoundKey = "none", -- CludesUI._groupDeathSoundPaths key
            maTtsEnabled = false, -- takes priority over maSoundKey when on; speaks the ability name once when it comes off cooldown
            maTtsVoiceID = 0,
            maTtsVolume = 100,

            tsEnabled = false,
            tsTextFormat = "FREE MOVEMENT\\n%.1f",
            tsColorR = 0.53,
            tsColorG = 1,
            tsColorB = 0,
            tsColorUseClass = false,
            tsSoundKey = "none", -- CludesUI._groupDeathSoundPaths key
            tsTtsEnabled = false, -- takes priority over tsSoundKey when on
            tsTtsVoiceID = 0,
            tsTtsMessage = "Free movement",
            tsTtsVolume = 100,
            tsPos = nil,

            gwEnabled = false,
            gwCombatOnly = false,
            gwText = "GATEWAY READY",
            gwColorR = 0.7,
            gwColorG = 0,
            gwColorB = 1,
            gwColorUseClass = false,
            gwSoundKey = "none", -- CludesUI._groupDeathSoundPaths key
            gwTtsEnabled = false, -- takes priority over gwSoundKey when on
            gwTtsVoiceID = 0,
            gwTtsMessage = "Gateway ready",
            gwTtsVolume = 100,
            gwPos = nil,
        },
    },
}

local saved = CludesUI.Lite.NewDB("CludesUIQoLDB", defaultSet)
local function MA()
    return saved.profile.movementAlert
end

-- Movement Cooldown Alert enable state: enabledClasses is a per-class
-- checkbox set (nil = nothing checked = fully disabled). Everything at
-- runtime keys off the PLAYER's class -- a character whose class is
-- unchecked pays exactly the same zero cost as the feature being off.
local function MovementEnabled()
    local alertCfg = MA()
    local ec = alertCfg and alertCfg.enabledClasses
    if not ec then
        return false
    end
    return ec[playerClassToken] == true
end
_G._CUI_MovementAlert_DB = function()
    return saved
end
CludesUI._ResetMovementAlert = function()
    saved:ResetProfile()
    if CludesUI._RebuildMovementSpellLookup then
        CludesUI._RebuildMovementSpellLookup()
    end
    if CludesUI._CacheMovementSpells then
        CludesUI._CacheMovementSpells(true)
    end
    if CludesUI._UpdateMovementAlertEvents then
        CludesUI._UpdateMovementAlertEvents()
    end
    if CludesUI._applyMovementAlert then
        CludesUI._applyMovementAlert()
    end
    if CludesUI._applyTimeSpiral then
        CludesUI._applyTimeSpiral()
    end
    if CludesUI._applyGateway then
        CludesUI._applyGateway()
    end
    -- Explicit self-correct: ApplyMovementFrame/CheckGatewayUsable only hide
    -- an actively-displayed frame when their own tracker is enabled, which
    -- ResetProfile() just turned off -- without these, a frame that was
    -- showing at reset-time stays frozen on screen.
    if CludesUI._CheckMovementCooldown then
        CludesUI._CheckMovementCooldown()
    end
    if CludesUI._CheckGatewayUsable then
        CludesUI._CheckGatewayUsable()
    end
end

-------------------------------------------------------------------------------
--  Font / color helpers -- reuses the shared "extras" font/outline settings
--  (same category Combat Alert uses) instead of a dedicated per-feature font
--  picker, and the shared Group Death sound list instead of building a new
--  sound/TTS system.
-------------------------------------------------------------------------------
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local function AlertFontPath()
    return (CludesUI.GetFontPath("extras")) or FALLBACK_FONT
end
local function AlertFontOutline()
    local o = (CludesUI.GetFontOutlineFlag("extras")) or ""
    if not o:find("OUTLINE") then
        o = (o == "") and "OUTLINE" or (o .. ", OUTLINE")
    end
    return o
end
local function ResolveAlertColor(prefixText, useClassKey)
    local alertCfg = MA()
    if alertCfg[useClassKey] then
        local _, classToken = UnitClass("player")
        local c = classToken and CludesUI.GetClassColor(classToken)
        if c then
            return c.r, c.g, c.b
        end
    end
    return alertCfg[prefixText .. "R"] or 1, alertCfg[prefixText .. "G"] or 1, alertCfg[prefixText .. "B"] or 1
end
-- LSM "sound" entries are either a file path (string) or a Blizzard
-- SoundKitID (number -- most of the built-in SOUNDKIT.* entries other addons
-- register use this). PlaySoundFile only understands the former, so route by
-- type. Shared with CUI_QoL_MovementAlert_Options.lua's preview button via
-- CludesUI._PlayLSMSound so both play a given LSM value identically.
local function PlayLSMSound(value)
    if not value or value == 1 then
        return
    end
    if type(value) == "number" then
        PlaySound(value, "Master")
    else
        PlaySoundFile(value, "Master")
    end
end
CludesUI._PlayLSMSound = PlayLSMSound

-- Resolves through CludesUI._groupDeathSoundPaths -- the addon's existing
-- sound-list table (curated built-ins + every LibSharedMedia "sound" entry,
-- merged in once at login by CludesUI.AppendSharedMediaSounds). Reuses
-- that instead of querying LSM directly a second time, so there's one sound
-- list/preview implementation in the addon, not two.
local function PlayAlertSound(key)
    if not key or key == "none" then
        return
    end
    local value = CludesUI._groupDeathSoundPaths and CludesUI._groupDeathSoundPaths[key]
    if value then
        PlayLSMSound(value)
    end
end

-- Text-to-speech: local-only playback via C_VoiceChat. The live-client
-- argument order is (voiceID, text, destination, volume, interrupt), NOT
-- (voiceID, text, destination, rate, volume) as older API docs suggest.
-- Enum.VoiceTtsDestination doesn't exist on live clients either, so
-- destination is the literal 1 (local playback). Silently no-ops if TTS
-- isn't available instead of erroring.
local function SpeakAlertText(voiceId, textValue, volume)
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then
        return
    end
    if not textValue or textValue == "" then
        return
    end
    pcall(C_VoiceChat.SpeakText, voiceId or 0, textValue, 1, volume or 100, true)
end

-- Fires TTS if enabled for this tracker (prefix "ts"/"gw"/"ma"), otherwise
-- falls back to the tracker's configured sound. TTS always wins when both
-- are configured -- keeps the two controls from fighting over which one
-- plays. abilityName, if given, substitutes "%a" in the TTS message (used by
-- the Movement Cooldown Alert's per-spell "ready" callout).
local function FireTrackerAlert(prefixText, abilityName)
    local alertCfg = MA()
    if alertCfg[prefixText .. "TtsEnabled"] then
        -- The Movement Cooldown Alert always speaks the ability name (or its
        -- per-spell Custom Text) -- there is no message setting for it. The
        -- other trackers speak their fixed configured message.
        local message = abilityName or alertCfg[prefixText .. "TtsMessage"]
        SpeakAlertText(alertCfg[prefixText .. "TtsVoiceID"], message, alertCfg[prefixText .. "TtsVolume"])
    else
        PlayAlertSound(alertCfg[prefixText .. "SoundKey"])
    end
end

-------------------------------------------------------------------------------
--  Movement Cooldown Alert display frame (pooled multi-slot: some specs
--  track more than one mobility spell, e.g. Druid across forms)
-------------------------------------------------------------------------------
local moveFrame = CreateFrame("Frame", "CUI_MovementAlertFrame", UIParent)
moveFrame:SetSize(200, 40)
moveFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
moveFrame:Hide()

-- Bar texture catalog: the same curated set the CDM Tracking Bars "Bar
-- Texture" dropdown uses (CludesUICooldownManager\CludesUICdmBuffBars.lua);
-- the options page appends SharedMedia statusbar textures into these tables.
-- Rendering resolves through ResolveTexturePath ("none" = flat WHITE8x8).
local BAR_TEXTURES, BAR_TEXTURE_NAMES, BAR_TEXTURE_ORDER = CludesUI.BuildBarTextureTables()
CludesUI._MovementBarTextures = {
    lookup = BAR_TEXTURES,
    order = BAR_TEXTURE_ORDER,
    names = BAR_TEXTURE_NAMES,
}

-- Named font object for the icon mode's cooldown countdown numbers --
-- SetCountdownFont takes the NAME of a named font object, and StyleSlot
-- re-points this one at the user's font/size.
local movementCdFont = CreateFont("CUI_MovementAlertCdFont")
-- A fresh font object has no font file; give it one immediately so text
-- attached to it can render before the first StyleSlot pass re-points it
-- at the user's font and size.
movementCdFont:SetFont(FALLBACK_FONT, 24, "OUTLINE")

local displayPool = {}
local activeSlotCount = 0
-- Tracks which tracked (non-buffActive) spellIDs were on cooldown as of the
-- last poll, so the "ready" TTS callout fires exactly once per cooldown
-- ending instead of every poll tick while the spell sits ready.
local readyAlertShown = {}
local readyAlertScratch = {} -- swapped with readyAlertShown each check: no per-check table
-- Spells whose own cooldown is running: the player cast them, or a check showed
-- them with a readable cooldown of MIN_REAL_COOLDOWN or more. The callout fires
-- only for an armed spell, so a window the spell sits in for another reason (the
-- global cooldown, the lockout after a wand shot or another ability, a window too
-- secret to classify) never announces it. Leaving the shown set disarms it, and
-- the first check after the display was taken down disarms every spell it does
-- not show (readyAlertFresh), so no arm outlives its cooldown.
local readyAlertArmed = {}
local readyAlertFresh = false

-- The end of a countdown the engine times (a secret remaining Lua cannot read)
-- comes from the Cooldown frame itself, the edge Blizzard's cooldown viewer
-- refreshes on, and runs a full check at once. A done in its bind's own frame
-- is the bind of an already-finished cooldown, and a frame reports at most four
-- a second, so an engine that also reports expired binds cannot spin the check;
-- the repaint's backstop check covers an end left unreported. The parent's
-- visibility, not the frame's (a finished cooldown hides itself), drops the
-- Clear of a display that is coming down.
local RequestMovementCheck
local function OnSlotCooldownDone(cooldown)
    local nowTime = GetTime()
    if nowTime == cooldown._maBoundAt or nowTime - (cooldown._maDoneAt or 0) < 0.25 or not cooldown:GetParent():IsVisible() then
        return
    end
    cooldown._maDoneAt = nowTime
    RequestMovementCheck()
end

local function CreateDisplaySlot()
    local slotRec = CreateFrame("Frame", nil, moveFrame)
    slotRec:SetSize(200, 40)

    slotRec.text = slotRec:CreateFontString(nil, "OVERLAY")
    slotRec.text:SetPoint("CENTER")

    slotRec.icon = CreateFrame("Frame", nil, slotRec)
    slotRec.icon:SetSize(40, 40)
    slotRec.icon:SetPoint("CENTER")
    slotRec.icon.border = slotRec.icon:CreateTexture(nil, "BACKGROUND")
    slotRec.icon.border:SetAllPoints()
    slotRec.icon.border:SetColorTexture(0, 0, 0, 1)
    slotRec.icon.tex = slotRec.icon:CreateTexture(nil, "ARTWORK")
    slotRec.icon.tex:SetPoint("TOPLEFT", 2, -2)
    slotRec.icon.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    slotRec.icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slotRec.icon.cooldown = CreateFrame("Cooldown", nil, slotRec.icon, "CooldownFrameTemplate")
    slotRec.icon.cooldown:SetAllPoints(slotRec.icon.tex)
    slotRec.icon.cooldown:SetDrawEdge(false)
    slotRec.icon.cooldown:SetScript("OnCooldownDone", OnSlotCooldownDone)
    if slotRec.icon.cooldown.SetCountdownFont then
        slotRec.icon.cooldown:SetCountdownFont("CUI_MovementAlertCdFont")
    end
    -- Own countdown text for icon mode: the poll drives this FontString for
    -- readable durations (our precision/decimal control); the engine numbers
    -- take over only for secret durations, which Lua cannot format (see the
    -- engine-countdown block below for the CVar posture).
    slotRec.icon.timeText = slotRec.icon.cooldown:CreateFontString(nil, "OVERLAY")
    slotRec.icon.timeText:SetFontObject(movementCdFont)
    slotRec.icon.timeText:SetPoint("CENTER")
    slotRec.icon.timeText:SetText("")
    slotRec.icon:Hide()

    -- Engine-drawn countdown for text modes. See ShowEngineCountdown.
    slotRec.cdNum = CreateFrame("Cooldown", nil, slotRec, "CooldownFrameTemplate")
    slotRec.cdNum:SetDrawSwipe(false)
    slotRec.cdNum:SetDrawEdge(false)
    slotRec.cdNum:SetScript("OnCooldownDone", OnSlotCooldownDone)
    if slotRec.cdNum.SetDrawBling then
        slotRec.cdNum:SetDrawBling(false)
    end
    slotRec.cdNum:SetHideCountdownNumbers(false)
    if slotRec.cdNum.SetCountdownFont then
        slotRec.cdNum:SetCountdownFont("CUI_MovementAlertCdFont")
    end
    -- Blizzard suppresses countdown text on short cooldowns by default, which
    -- would silently drop the number on exactly the short mobility cooldowns
    -- this feature exists for.
    if slotRec.cdNum.SetMinimumCountdownDuration then
        slotRec.cdNum:SetMinimumCountdownDuration(0)
    end
    -- The engine exposes the FontString it draws into, so the number can be
    -- placed and sized against our own text instead of being inferred from the
    -- host frame's geometry (which is what made it render at a different size).
    if slotRec.cdNum.GetCountdownFontString then
        slotRec.cdNumText = slotRec.cdNum:GetCountdownFontString()
    end
    slotRec.cdNum:Hide()

    slotRec.bar = CreateFrame("StatusBar", nil, slotRec)
    slotRec.bar:SetSize(150, 20)
    slotRec.bar:SetPoint("CENTER")
    slotRec.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    slotRec.bar:SetMinMaxValues(0, 1)
    slotRec.bar:SetValue(0)
    slotRec.bar.bg = slotRec.bar:CreateTexture(nil, "BACKGROUND")
    slotRec.bar.bg:SetAllPoints()
    slotRec.bar.bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    slotRec.bar.text = slotRec.bar:CreateFontString(nil, "OVERLAY")
    slotRec.bar.text:SetPoint("CENTER")
    slotRec.bar.icon = slotRec.bar:CreateTexture(nil, "OVERLAY")
    slotRec.bar.icon:SetSize(20, 20)
    slotRec.bar.icon:SetPoint("RIGHT", slotRec.bar, "LEFT", -4, 0)
    slotRec.bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slotRec.bar:Hide()

    return slotRec
end

local function GetDisplaySlot(index)
    if not displayPool[index] then
        displayPool[index] = CreateDisplaySlot()
    end
    return displayPool[index]
end

local function LayoutDisplaySlots(stacks)
    local frameW, frameH = moveFrame:GetWidth(), moveFrame:GetHeight()
    for index = 1, stacks do
        local slotRec = displayPool[index]
        if slotRec then
            slotRec:ClearAllPoints()
            slotRec:SetSize(frameW, frameH)
            if index == 1 then
                slotRec:SetPoint("BOTTOM", moveFrame, "BOTTOM", 0, 0)
            else
                slotRec:SetPoint("BOTTOM", displayPool[index - 1], "TOP", 0, 2)
            end
        end
    end
end

local function StyleSlot(slotRec)
    local alertCfg = MA()
    local fontFile, outline = AlertFontPath(), AlertFontOutline()
    local frameH, frameW = moveFrame:GetHeight(), moveFrame:GetWidth()
    local fontPx = math.max(8, math.min(72, alertCfg.textSize or 24))
    local tR, tG, tB = ResolveAlertColor("textColor", "textColorUseClass")
    local showIcon = alertCfg.barShowIcon ~= false
    local texPath = (
        CludesUI.ResolveTexturePath(BAR_TEXTURES, alertCfg.barTexture or "none", "Interface\\Buttons\\WHITE8x8")
    ) or "Interface\\Buttons\\WHITE8x8"
    local iconSz = math.max(16, math.min(128, alertCfg.iconSize or 40))

    -- Pin the engine's countdown FontString to the same font object and colour
    -- every pass: left alone it sizes itself against its host frame rather than
    -- the user's Text Size.
    if slotRec.cdNumText then
        slotRec.cdNumText:SetFontObject(movementCdFont)
        slotRec.cdNumText:SetTextColor(tR, tG, tB)
    end

    -- The rest only when one of its inputs moved: every poll tick (10 per second
    -- while an alert shows) re-shows each slot.
    local st = slotRec._style
    if not st then
        st = {}
        slotRec._style = st
    end
    if
        st.font == fontFile
        and st.outline == outline
        and st.size == fontPx
        and st.r == tR
        and st.g == tG
        and st.b == tB
        and st.w == frameW
        and st.h == frameH
        and st.icon == showIcon
        and st.tex == texPath
        and st.iconSz == iconSz
    then
        return
    end
    st.font, st.outline, st.size, st.r, st.g, st.b = fontFile, outline, fontPx, tR, tG, tB
    st.w, st.h, st.icon, st.tex, st.iconSz = frameW, frameH, showIcon, texPath, iconSz

    if not slotRec.text:SetFont(fontFile, fontPx, outline) then
        slotRec.text:SetFont(FALLBACK_FONT, fontPx, outline)
    end
    slotRec.text:SetTextColor(tR, tG, tB)
    slotRec.icon.timeText:SetTextColor(tR, tG, tB)

    local barH = math.max(12, math.floor(frameH * 0.5))
    local barW = frameW - (showIcon and (barH + 8) or 0) - 10
    slotRec.bar:SetSize(math.max(50, barW), barH)
    slotRec.bar.icon:SetSize(barH, barH)
    -- Text Size drives every mode's text: the free text, the bar's number,
    -- and (via the named countdown font) the icon's countdown numbers.
    -- Font-object SetFont has no success return; reuse the fontstring's
    -- validation to pick the path that actually loaded.
    if not slotRec.bar.text:SetFont(fontFile, fontPx, outline) then
        slotRec.bar.text:SetFont(FALLBACK_FONT, fontPx, outline)
        movementCdFont:SetFont(FALLBACK_FONT, fontPx, outline)
    else
        movementCdFont:SetFont(fontFile, fontPx, outline)
    end
    -- The engine draws its countdown numbers straight from this font object,
    -- so the colour has to live here too or the prototype's number ignores the
    -- user's Text Colour.
    movementCdFont:SetTextColor(tR, tG, tB)

    if slotRec.bar._lastTexPath ~= texPath then
        slotRec.bar:SetStatusBarTexture(texPath)
        slotRec.bar._lastTexPath = texPath
    end

    slotRec.icon:SetSize(iconSz, iconSz)
end

-------------------------------------------------------------------------------
--  Engine-drawn countdown for the text modes
--
--  A secret remaining cannot be formatted in Lua (that is the 0.0 bug), but
--  the ENGINE can draw it: a Cooldown widget handed the same duration object
--  renders the number itself, which is exactly why icon mode still counts down
--  in combat. Everything except the number is switched off here, so all this
--  widget contributes is text sitting beside the name.
--
--  CVar posture: Blizzard READS countdownForCooldowns and passes it into
--  SetHideCountdownNumbers for its own buttons (Blizzard_ActionBar/Shared/
--  ActionButton.lua) -- the CVar gates Blizzard's calls, not the widget
--  internals -- so forcing false here draws numbers regardless
--  (field-verified 8.7.8). If a client configuration exists where it does
--  not, the degradation is no number, same as before this path existed.
-------------------------------------------------------------------------------
-- The duration OBJECT is the only safe way to drive this. Cooldown:SetCooldown
-- is SecretArguments = "AllowedWhenUntainted", so handing it the secret start
-- and duration from the cdInfo path would error out of our own tainted ticker;
-- the object itself is not a secret value, so passing it is fine. When there is
-- no object there is simply no number, which is the same degradation as before.
local function BindEngineCountdown(cooldown, dur)
    if dur and cooldown.SetCooldownFromDurationObject then
        cooldown:SetCooldownFromDurationObject(dur)
        cooldown._maBoundAt = GetTime()
        return true
    end
    return false
end

local function HideEngineCountdown(slotRec)
    if slotRec.cdNum then
        slotRec.cdNum:Hide()
    end
    -- ShowEngineCountdown slides the name off centre to make room for the
    -- number, so every render has to start from the plain centred layout or
    -- the offset accumulates across modes.
    if slotRec.text then
        slotRec.text:ClearAllPoints()
        slotRec.text:SetPoint("CENTER")
    end
end

local function ShowEngineCountdown(slotRec, showMode, dur)
    local cooldown = slotRec.cdNum
    if not cooldown then
        return false
    end
    local alertCfg = MA()
    local fontPx = math.max(8, math.min(72, alertCfg.textSize or 24))
    -- Decimals: this is the engine's version of the Show Decimal toggle. Above
    -- the threshold it prints whole seconds, below it one decimal place, so
    -- "always" is a threshold past any cooldown and "never" is zero.
    local decimals = ((tonumber(alertCfg.precision) or 1) > 0) and 1 or 0
    if cooldown.SetCountdownMillisecondsThreshold then
        cooldown:SetCountdownMillisecondsThreshold(decimals == 1 and 86400 or 0)
    end
    -- Blizzard abbreviates past two minutes by default, so a 90s cooldown would
    -- print "1:30" where every other path in this feature prints "90".
    if cooldown.SetCountdownAbbrevThreshold then
        cooldown:SetCountdownAbbrevThreshold(0)
    end
    -- Layout. The number is a separate object from the name, so the pair has to
    -- be centred as a unit: reserve a fixed width for the number and slide the
    -- name half of that the other way. The width is RESERVED rather than
    -- measured because the number's own width changes as it counts down
    -- (100.0 -> 9.9), and centring on a measured width would shuffle the name
    -- sideways on every tick.
    local gap = math.max(2, fontPx * 0.15)
    local reserved = fontPx * (decimals == 1 and 2.4 or 1.6)
    local shift = (reserved + gap) / 2
    local numberFirst = (showMode ~= "text_nd")
    -- text_d: no name at all, the number IS the text -- centre it on the slot.
    local numberOnly = (showMode == "text_d")
    if numberOnly then
        shift = 0
    end

    slotRec.text:ClearAllPoints()
    slotRec.text:SetPoint("CENTER", slotRec, "CENTER", numberFirst and shift or -shift, 0)

    -- Position the FontString itself when the engine hands it over, so the
    -- number matches our own text exactly; fall back to moving the host frame
    -- (whose centred number only approximates the same place) when it does not.
    cooldown:ClearAllPoints()
    local fontStr = slotRec.cdNumText
    if fontStr then
        cooldown:SetSize(1, 1)
        cooldown:SetPoint("CENTER", slotRec.text, "CENTER", 0, 0)
        fontStr:ClearAllPoints()
        -- No SetWidth: the anchor below already grows the digits outward, and a
        -- hard width clips five-glyph values like "120.0" (Stampeding Roar).
        -- reserved is only an estimate for the centring shift above.
        if numberOnly then
            fontStr:SetJustifyH("CENTER")
            fontStr:SetPoint("CENTER", slotRec.text, "CENTER", 0, 0)
        elseif numberFirst then
            fontStr:SetJustifyH("RIGHT")
            fontStr:SetPoint("RIGHT", slotRec.text, "LEFT", -gap, 0)
        else
            fontStr:SetJustifyH("LEFT")
            fontStr:SetPoint("LEFT", slotRec.text, "RIGHT", gap, 0)
        end
    else
        cooldown:SetSize(reserved, fontPx * 1.4)
        if numberOnly then
            cooldown:SetPoint("CENTER", slotRec.text, "CENTER", 0, 0)
        elseif numberFirst then
            cooldown:SetPoint("RIGHT", slotRec.text, "LEFT", -gap, 0)
        else
            cooldown:SetPoint("LEFT", slotRec.text, "RIGHT", gap, 0)
        end
    end
    if not BindEngineCountdown(cooldown, dur) then
        -- Nothing to drive the number with: undo the room made for it, or the
        -- name is left sitting off centre with an empty gap beside it.
        HideEngineCountdown(slotRec)
        return false
    end
    cooldown:Show()
    return true
end

-- Bar mode's number lives centred in the bar with no name beside it, so it
-- needs the binding but none of the two-object layout above.
local function ShowEngineCountdownCentred(slotRec, anchor, dur)
    local cooldown = slotRec.cdNum
    if not cooldown then
        return false
    end
    local alertCfg = MA()
    local fontPx = math.max(8, math.min(72, alertCfg.textSize or 24))
    local decimals = ((tonumber(alertCfg.precision) or 1) > 0) and 1 or 0
    if cooldown.SetCountdownMillisecondsThreshold then
        cooldown:SetCountdownMillisecondsThreshold(decimals == 1 and 86400 or 0)
    end
    -- Blizzard abbreviates past two minutes by default, so a 90s cooldown would
    -- print "1:30" where every other path in this feature prints "90".
    if cooldown.SetCountdownAbbrevThreshold then
        cooldown:SetCountdownAbbrevThreshold(0)
    end
    cooldown:ClearAllPoints()
    -- The host frame is created before slot.bar, so without this the number is
    -- painted under the bar's background and fill and never appears.
    if anchor.GetFrameLevel then
        cooldown:SetFrameLevel(anchor:GetFrameLevel() + 5)
    end
    local fontStr = slotRec.cdNumText
    if fontStr then
        cooldown:SetSize(1, 1)
        cooldown:SetPoint("CENTER", anchor, "CENTER", 0, 0)
        fontStr:ClearAllPoints()
        fontStr:SetWidth(0)
        fontStr:SetJustifyH("CENTER")
        fontStr:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    else
        cooldown:SetSize(fontPx * 3, fontPx * 1.4)
        cooldown:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end
    if not BindEngineCountdown(cooldown, dur) then
        cooldown:Hide()
        return false
    end
    cooldown:Show()
    return true
end

-------------------------------------------------------------------------------
--  Spell tracking core (charges, cooldowns, spec resolution)
-------------------------------------------------------------------------------
local knownChargeSpells = {}

local function SafeGetChargeInfo(alertSpell)
    local chargeInfo = C_Spell.GetSpellCharges(alertSpell)
    if not chargeInfo then
        local cached = knownChargeSpells[alertSpell]
        if cached then
            return true, cached.maxCh, cached.rechDur
        end
        return false, 1, 0
    end
    local m = chargeInfo.maxCharges or 1
    local region = chargeInfo.cooldownDuration or 0
    if IsSecret(m) or IsSecret(region) then
        local cached = knownChargeSpells[alertSpell]
        if cached then
            return true, cached.maxCh, cached.rechDur
        end
        return false, 1, 0
    end
    if m > 1 then
        knownChargeSpells[alertSpell] = { maxCh = m, rechDur = region }
        return true, m, region
    end
    local cached = knownChargeSpells[alertSpell]
    if cached then
        return true, cached.maxCh, cached.rechDur
    end
    return false, m, region
end

local function SafeGetBaseDuration(alertSpell)
    if C_Spell.GetSpellCooldownDuration then
        -- ignoreGCD: without it this reads the global cooldown whenever one is
        -- running, and the 1.5 floor below then throws the answer away.
        local dur = C_Spell.GetSpellCooldownDuration(alertSpell, true)
        if dur then
            local sum = dur:GetTotalDuration()
            if not IsSecret(sum) and sum and sum > 1.5 then
                return sum
            end
        end
    end
    -- Global, not C_Spell (client-verified: no C_Spell form exists). Static
    -- spell data, so it stays readable when the live cooldown is secret.
    if GetSpellBaseCooldown then
        local ms = GetSpellBaseCooldown(alertSpell)
        if not IsSecret(ms) and ms and ms > 1500 then
            return ms / 1000
        end
    end
    local cdInfo = C_Spell.GetSpellCooldown(alertSpell)
    if cdInfo and cdInfo.duration then
        local skinData = cdInfo.duration
        if not IsSecret(skinData) and skinData > 1.5 then
            return skinData
        end
    end
    return 0
end

local function ResolvePlayerSpecId()
    local specInfo = C_SpecializationInfo.GetSpecialization()
    if not specInfo then
        return nil
    end
    local specId = C_SpecializationInfo.GetSpecializationInfo(specInfo)
    if specId and specId > 0 then
        return specId
    end
    return nil
end

local cachedMovementSpells = {}
local cachedChargeCount = {}
local rechargeTimers = {}
local chargeRechargeStart = {}
local spellWasCast = {}
local spellCastTime = {}
local trackedSpellSet = {}
local cacheResetTime = 0
-- The countdown repaint after a full check (ArmMovementRepaint): deadlines on a
-- frame shown only while an alert is up, so no timer object is made per tick.
-- movementRepaintAt: the next 100 ms repaint of the numbers Lua times;
-- movementBackstopAt: the next full check while a slot's end is timed by the
-- engine alone (math.huge otherwise). Its OnUpdate is set beside the check funnel.
local movementRepaintAt = 0
local movementBackstopAt = math.huge
local MOVEMENT_BACKSTOP = 0.5
local movementRepaintFrame = CreateFrame("Frame")
movementRepaintFrame:Hide()
local movementPreviewTicker = nil -- options-panel preview loop (nil = off)
local CheckMovementCooldown
local CancelAllRechargeTimers

-- WoW Forever: the class counts as each of its retail specs, so the tracker
-- walks every spec list of the class, merged in class order without repeats.
-- Ids that are a different spell there are left out (781 is the threat-drop
-- Disengage there, not a movement spell).
-- Built once: its inputs (the player's class, the static MOVEMENT_ABILITIES)
-- never change in a session. nil when the class has no list.
local ForeverMovementList
do
    local merged
    ForeverMovementList = function()
        if not merged then
            merged = {}
            local skip = { [781] = true }
            local classAbilities = MOVEMENT_ABILITIES[playerClassToken]
            local ids = classAbilities and CludesUI.ForeverClassSpecIDs(playerClassToken)
            for index = 1, (ids and #ids or 0) do
                local specList = classAbilities[ids[index]]
                for jdx = 1, (specList and #specList or 0) do
                    local spellRef, dup = specList[jdx], false
                    for k = 1, #merged do
                        if merged[k] == spellRef then
                            dup = true
                            break
                        end
                    end
                    if not dup and not skip[spellRef] then
                        merged[#merged + 1] = spellRef
                    end
                end
            end
        end
        return merged[1] and merged or nil
    end
end

local function GetPlayerMovementSpells()
    local classFile = select(2, UnitClass("player"))
    local specId = ResolvePlayerSpecId()
    if not specId then
        return {}
    end

    local overrides = MA().spellOverrides or {}
    local classAbilities = MOVEMENT_ABILITIES[classFile]
    if not classAbilities then
        return {}
    end
    local specAbilities = classAbilities[specId]
    if CludesUI.IS_FOREVER then
        specAbilities = ForeverMovementList()
    end
    if not specAbilities then
        return {}
    end

    local result, seen = {}, {}

    for _, alertSpell in ipairs(specAbilities) do
        if not seen[alertSpell] then
            local overrideId = overrides[alertSpell]
            if SpellEffectivelyEnabled(overrideId, alertSpell) then
                if
                    (IsPlayerSpell and IsPlayerSpell(alertSpell))
                    or (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(alertSpell))
                then
                    local shownId = alertSpell
                    if C_Spell.GetOverrideSpell then
                        local okOvr, oid = pcall(C_Spell.GetOverrideSpell, alertSpell)
                        if okOvr and oid and oid > 0 and oid ~= alertSpell then
                            shownId = oid
                        end
                    end
                    if not seen[shownId] then
                        seen[alertSpell] = true
                        seen[shownId] = true
                        local spellData = C_Spell.GetSpellInfo(shownId)
                        local isCharge, maxCh, rechargeDur = SafeGetChargeInfo(shownId)
                        local baseSpell = (shownId ~= alertSpell) and alertSpell or nil
                        if not isCharge and baseSpell then
                            isCharge, maxCh, rechargeDur = SafeGetChargeInfo(baseSpell)
                        end
                        if spellData then
                            local defaultCustom = BUFF_ACTIVE_SPELLS[shownId] or BUFF_ACTIVE_SPELLS[alertSpell]
                            if defaultCustom then
                                table.insert(result, {
                                    spellId = shownId,
                                    spellName = spellData.name,
                                    spellIcon = spellData.iconID,
                                    customText = overrideId
                                            and overrideId.customText ~= ""
                                            and overrideId.customText
                                        or defaultCustom,
                                    checkType = "buffActive",
                                })
                            else
                                local rawBaseDur = SafeGetBaseDuration(shownId)
                                if rawBaseDur <= 0 and baseSpell then
                                    rawBaseDur = SafeGetBaseDuration(baseSpell)
                                end
                                if not isCharge and rawBaseDur <= 0 and rechargeDur > 0 then
                                    rawBaseDur = rechargeDur
                                end
                                if rawBaseDur <= 0 then
                                    rawBaseDur = GetKnownCategoryDuration(shownId)
                                end
                                if rawBaseDur <= 0 and baseSpell then
                                    rawBaseDur = GetKnownCategoryDuration(baseSpell)
                                end
                                table.insert(result, {
                                    spellId = shownId,
                                    baseSpellId = baseSpell,
                                    spellName = spellData.name,
                                    spellIcon = spellData.iconID,
                                    customText = overrideId
                                            and overrideId.customText ~= ""
                                            and overrideId.customText
                                        or nil,
                                    isChargeSpell = isCharge,
                                    maxCharges = maxCh,
                                    rechargeDuration = rechargeDur,
                                    baseDuration = isCharge and rechargeDur or rawBaseDur,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    -- User-added custom overrides for this class not already covered above
    for alertSpell, overrideId in pairs(overrides) do
        if not seen[alertSpell] and overrideId.class == classFile and overrideId.enabled ~= false then
            if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(alertSpell) then
                local shownId = alertSpell
                if C_Spell.GetOverrideSpell then
                    local okOvr, oid = pcall(C_Spell.GetOverrideSpell, alertSpell)
                    if okOvr and oid and oid > 0 and oid ~= alertSpell then
                        shownId = oid
                    end
                end
                if not seen[shownId] then
                    seen[alertSpell] = true
                    seen[shownId] = true
                    local spellData = C_Spell.GetSpellInfo(shownId)
                    local isCharge, maxCh, rechargeDur = SafeGetChargeInfo(shownId)
                    local baseSpell = (shownId ~= alertSpell) and alertSpell or nil
                    if not isCharge and baseSpell then
                        isCharge, maxCh, rechargeDur = SafeGetChargeInfo(baseSpell)
                    end
                    if spellData then
                        -- Same buff-active branch the default path takes above.
                        -- Without it a user-added aura-toggle spell was always
                        -- built as a cooldown entry, and since it has no cooldown
                        -- the display loop had nothing to show.
                        local defaultCustom = BUFF_ACTIVE_SPELLS[shownId] or BUFF_ACTIVE_SPELLS[alertSpell]
                        if defaultCustom then
                            table.insert(result, {
                                spellId = shownId,
                                spellName = spellData.name,
                                spellIcon = spellData.iconID,
                                customText = overrideId.customText ~= "" and overrideId.customText
                                    or defaultCustom,
                                checkType = "buffActive",
                            })
                        else
                            local rawBaseDur = SafeGetBaseDuration(shownId)
                            if rawBaseDur <= 0 and baseSpell then
                                rawBaseDur = SafeGetBaseDuration(baseSpell)
                            end
                            if not isCharge and rawBaseDur <= 0 and rechargeDur > 0 then
                                rawBaseDur = rechargeDur
                            end
                            if rawBaseDur <= 0 then
                                rawBaseDur = GetKnownCategoryDuration(shownId)
                            end
                            table.insert(result, {
                                spellId = shownId,
                                baseSpellId = baseSpell,
                                spellName = spellData.name,
                                spellIcon = spellData.iconID,
                                customText = overrideId.customText ~= "" and overrideId.customText or nil,
                                isChargeSpell = isCharge,
                                maxCharges = maxCh,
                                rechargeDuration = rechargeDur,
                                baseDuration = isCharge and rechargeDur or rawBaseDur,
                            })
                        end
                    end
                end
            end
        end
    end

    return result
end

local function UpdateCachedCharges()
    if inCombat or InCombatLockdown() then
        return
    end
    for _, record in ipairs(cachedMovementSpells) do
        if record.checkType == "buffActive" then
            -- Aura-tracked: no cooldown and no charges to cache.
        elseif record.isChargeSpell then
            local chargeId = record.baseSpellId or record.spellId
            local chargeInfo = C_Spell.GetSpellCharges(chargeId)
            if chargeInfo and chargeInfo.currentCharges and not IsSecret(chargeInfo.currentCharges) then
                cachedChargeCount[record.spellId] = chargeInfo.currentCharges
            end
        else
            local cdInfo = C_Spell.GetSpellCooldown(record.spellId)
            -- A shared lockout must not be adopted as the ability's base
            -- cooldown either -- that would poison the very value
            -- IsLockoutWindow classifies against.
            if
                cdInfo
                and cdInfo.duration
                and not IsSecret(cdInfo.duration)
                and cdInfo.duration > 0
                and not IsLockoutWindow(record, cdInfo.duration)
            then
                record.baseDuration = cdInfo.duration
            end
        end
    end
end

local function CacheMovementSpells(fullReset)
    local classFile = select(2, UnitClass("player"))
    local specId = ResolvePlayerSpecId()

    if fullReset then
        CancelAllRechargeTimers()
        wipe(spellWasCast)
        wipe(spellCastTime)
        wipe(chargeRechargeStart)
        wipe(readyAlertArmed)
        cacheResetTime = GetTime()
    end

    local prevSpells = cachedMovementSpells
    local newSpells = GetPlayerMovementSpells()
    if #newSpells == 0 and prevSpells and #prevSpells > 0 and not specId then
        cachedMovementSpells = prevSpells
    else
        cachedMovementSpells = newSpells
    end

    if not fullReset and prevSpells and #prevSpells > 0 then
        for _, newEntry in ipairs(cachedMovementSpells) do
            local newBase = newEntry.baseSpellId or newEntry.spellId
            for _, oldEntry in ipairs(prevSpells) do
                local oldBase = oldEntry.baseSpellId or oldEntry.spellId
                if oldBase == newBase and oldEntry.spellId ~= newEntry.spellId then
                    local oldId, newId = oldEntry.spellId, newEntry.spellId
                    if spellWasCast[oldId] ~= nil then
                        spellWasCast[newId] = spellWasCast[oldId]
                        spellWasCast[oldId] = nil
                    end
                    if spellCastTime[oldId] ~= nil then
                        spellCastTime[newId] = spellCastTime[oldId]
                        spellCastTime[oldId] = nil
                    end
                    if cachedChargeCount[oldId] ~= nil then
                        cachedChargeCount[newId] = cachedChargeCount[oldId]
                        cachedChargeCount[oldId] = nil
                    end
                    if chargeRechargeStart[oldId] ~= nil then
                        chargeRechargeStart[newId] = chargeRechargeStart[oldId]
                        chargeRechargeStart[oldId] = nil
                    end
                    if rechargeTimers[oldId] ~= nil then
                        rechargeTimers[newId] = rechargeTimers[oldId]
                        rechargeTimers[oldId] = nil
                    end
                    if readyAlertArmed[oldId] ~= nil then
                        readyAlertArmed[newId] = readyAlertArmed[oldId]
                        readyAlertArmed[oldId] = nil
                    end
                end
            end
        end
    end

    -- The "ready" callout compares the spells shown on cooldown before and after
    -- each check by spell ID. Carry each one over to its entry in the new list (a
    -- form can swap a spell for its override) and drop the ones the list no
    -- longer tracks, so a form or spec change never announces a spell that is
    -- still on cooldown. The scratch table is wiped by the next check anyway.
    if next(readyAlertShown) then
        local carried = readyAlertScratch
        wipe(carried)
        for _, newEntry in ipairs(cachedMovementSpells) do
            local newBase = newEntry.baseSpellId or newEntry.spellId
            for _, oldEntry in pairs(readyAlertShown) do
                if (oldEntry.baseSpellId or oldEntry.spellId) == newBase then
                    carried[newEntry.spellId] = newEntry
                    break
                end
            end
        end
        readyAlertShown, readyAlertScratch = carried, readyAlertShown
    end

    wipe(trackedSpellSet)
    for _, record in ipairs(cachedMovementSpells) do
        trackedSpellSet[record.spellId] = record.spellId
        if C_Spell.GetOverrideSpell then
            local okOvr, oid = pcall(C_Spell.GetOverrideSpell, record.spellId)
            if okOvr and oid and oid > 0 and oid ~= record.spellId then
                trackedSpellSet[oid] = record.spellId
            end
        end
    end

    local overrides = MA().spellOverrides or {}
    local classAbilities = MOVEMENT_ABILITIES[classFile]
    local specAbilities = classAbilities and specId and classAbilities[specId]
    if CludesUI.IS_FOREVER and specId then
        specAbilities = ForeverMovementList()
    end
    if specAbilities then
        for _, alertSpell in ipairs(specAbilities) do
            local spellOverride = overrides[alertSpell]
            if SpellEffectivelyEnabled(spellOverride, alertSpell) and not trackedSpellSet[alertSpell] then
                local set = SPELL_ALIAS_MAP[alertSpell]
                if set then
                    for _, aliasId in ipairs(set) do
                        if trackedSpellSet[aliasId] and not trackedSpellSet[alertSpell] then
                            trackedSpellSet[alertSpell] = trackedSpellSet[aliasId]
                        end
                    end
                end
            end
        end
    end

    UpdateCachedCharges()
end
CludesUI._CacheMovementSpells = CacheMovementSpells

CancelAllRechargeTimers = function()
    for _, timer in pairs(rechargeTimers) do
        timer:Cancel()
    end
    wipe(rechargeTimers)
end

local function StartRechargeTimer(record, delay)
    if rechargeTimers[record.spellId] then
        return
    end
    local dur = delay or record.rechargeDuration or 0
    if dur <= 0 then
        return
    end
    rechargeTimers[record.spellId] = C_Timer.NewTimer(dur, function()
        rechargeTimers[record.spellId] = nil
        local current = cachedChargeCount[record.spellId] or 0
        local max = record.maxCharges or 1
        local newVal = math.min(current + 1, max)
        cachedChargeCount[record.spellId] = newVal
        if newVal < max then
            chargeRechargeStart[record.spellId] = GetTime()
            StartRechargeTimer(record)
        else
            chargeRechargeStart[record.spellId] = nil
        end
        if CheckMovementCooldown then
            CheckMovementCooldown()
        end
    end)
end

local function OnTrackedSpellCast(alertSpell)
    local baseSpell = trackedSpellSet[alertSpell]
    -- The cast starts the cooldown the "ready" callout announces.
    if baseSpell then
        readyAlertArmed[baseSpell] = true
    end
    if (GetTime() - cacheResetTime) < 2 then
        return
    end
    if TALENT_CD_TRIGGER_SPELLS[alertSpell] then
        return
    end
    if not baseSpell then
        return
    end
    spellWasCast[baseSpell] = true
    spellCastTime[baseSpell] = GetTime()

    if not inCombat then
        for _, record in ipairs(cachedMovementSpells) do
            if record.spellId == baseSpell and not record.isChargeSpell then
                local dur = SafeGetBaseDuration(baseSpell)
                if dur <= 0 and record.baseSpellId then
                    dur = SafeGetBaseDuration(record.baseSpellId)
                end
                if dur <= 0 and record.rechargeDuration and record.rechargeDuration > 0 then
                    dur = record.rechargeDuration
                end
                if dur <= 0 then
                    dur = GetKnownCategoryDuration(baseSpell)
                end
                if dur <= 0 and record.baseSpellId then
                    dur = GetKnownCategoryDuration(record.baseSpellId)
                end
                if dur > 0 then
                    record.baseDuration = dur
                end
                break
            end
        end
    end

    if not inCombat then
        return
    end
    for _, record in ipairs(cachedMovementSpells) do
        if record.spellId == baseSpell and record.isChargeSpell then
            local current = cachedChargeCount[baseSpell] or record.maxCharges or 1
            cachedChargeCount[baseSpell] = math.max(0, current - 1)
            if not chargeRechargeStart[baseSpell] then
                chargeRechargeStart[baseSpell] = GetTime()
            end
            if not rechargeTimers[baseSpell] then
                StartRechargeTimer(record)
            end
            return
        end
    end
end

-------------------------------------------------------------------------------
--  Movement bar rendering
-------------------------------------------------------------------------------
local function CancelMovementCountdown()
    movementRepaintFrame:Hide()
end

-- buffActive engine-lane handles (declared here so HideMovementDisplay -- the
-- universal off-path -- can park the host; defined in the lane block below).
local buffAlertHost, buffAlertBuilt, buffAlertRegenFn, buffAlertLastCount
local buffAlertContainer, buffAlertAssist, buffAlertVehicle

-- keepBuffLane: the cooldown display is going away but the buffActive lane is
-- not. A buffActive spell takes no slot, so an empty cooldown stack is its
-- NORMAL state -- parking the host there would hide the alert permanently.
local function HideMovementDisplay(keepBuffLane)
    wipe(readyAlertShown)
    -- Taken down for good (not the empty end of a check): the next check starts
    -- the callout over, see readyAlertArmed.
    if not keepBuffLane then
        readyAlertFresh = true
    end
    moveFrame:Hide()
    for _, slotRec in ipairs(displayPool) do
        slotRec.text:Hide()
        slotRec.icon:Hide()
        slotRec.icon.cooldown:Clear()
        slotRec.bar:Hide()
        HideEngineCountdown(slotRec)
        slotRec:Hide()
    end
    activeSlotCount = 0
    if buffAlertHost and not keepBuffLane then
        buffAlertHost:Hide()
    end
    CancelMovementCountdown()
end

-- The countdown number's format per precision (0 or 1 decimal).
local PREC_FMT = { [0] = "%.0f", [1] = "%.1f" }

local function ShowMovementSlot(index, cdInfo, spellEntry, dur)
    local alertCfg = MA()
    local slotRec = GetDisplaySlot(index)
    StyleSlot(slotRec)
    local showMode = alertCfg.displayMode or "text"
    -- Clamp to a clean 0/1 (matches the binary Show Decimal toggle). A legacy
    -- numeric-input value could be a string ("1") or a stored -0; feeding -0 to
    -- the format below builds an invalid "%.-0f". This local drives every
    -- format site (PREC_FMT).
    local decimals = ((tonumber(alertCfg.precision) or 1) > 0) and 1 or 0
    local spellName = spellEntry.customText or spellEntry.spellName or "Movement"
    local spellIcon = spellEntry.spellIcon
    -- The text format follows the mode, the precision and the name only, so it
    -- is built when one of them changes, not on every poll tick.
    local formatStr = spellEntry._maFmt
    if
        spellEntry._maFmtMode ~= showMode
        or spellEntry._maFmtPrec ~= decimals
        or spellEntry._maFmtName ~= spellName
    then
        local precFmt = PREC_FMT[decimals]
        -- spellName is free-form user text (per-spell Custom Text); escape
        -- literal "%" so SetFormattedText cannot misread it as a format
        -- directive expecting arguments it never gets.
        local escapedName = (spellName:gsub("%%", "%%%%"))
        -- Three fixed text arrangements: two read as "No <ability>" (the alert
        -- shows while the spell is unavailable), text_d is the bare number; the
        -- legacy "text" value keeps the old default's duration-first order.
        if showMode == "text_nd" then
            formatStr = "No " .. escapedName .. " " .. precFmt
        elseif showMode == "text_d" then
            formatStr = precFmt
        else
            formatStr = precFmt .. " No " .. escapedName
        end
        spellEntry._maFmt, spellEntry._maFmtMode = formatStr, showMode
        spellEntry._maFmtPrec, spellEntry._maFmtName = decimals, spellName
    end

    slotRec.text:Hide()
    slotRec.icon:Hide()
    slotRec.bar:Hide()
    HideEngineCountdown(slotRec)
    -- How the repaint keeps this slot current until the next full check (see
    -- RepaintMovementSlots): "num" = a countdown Lua paints, "fill" = a bar
    -- filled from a secret duration object, "engine" = a number the engine
    -- draws, "static" = nothing that moves. Each branch below sets its own.
    slotRec._maKind = "static"

    -- Start-recovery branch. GetSpellCooldown's timeUntilEndOfStartRecovery
    -- is ALWAYS present as a number on this client (0 outside an actual
    -- start-recovery window), so it must be gated on a POSITIVE value --
    -- plain truthiness hijacked EVERY render into this branch, which is why
    -- icon mode never drew its cooldown swipe or number. Secret check comes
    -- first (relational compares on secret numbers throw); a secret recovery
    -- falls through to the main path, whose engine sinks accept secrets.
    local recov = cdInfo and cdInfo.timeUntilEndOfStartRecovery
    if issecretvalue and issecretvalue(recov) then
        recov = nil
    end
    if type(recov) == "number" and recov > 0 and not IsLockoutWindow(spellEntry, recov) then
        -- Repainted until the window ends or drops under MIN_REAL_COOLDOWN, where
        -- IsLockoutWindow reclassifies it (IsLockoutWindow(entry, 0) asks whether
        -- this entry has that threshold at all).
        slotRec._maKind, slotRec._maEnd = "num", GetTime() + recov
        slotRec._maFloor = IsLockoutWindow(spellEntry, 0) and MIN_REAL_COOLDOWN or 0
        if showMode == "icon" and spellIcon then
            slotRec.icon.tex:SetTexture(spellIcon)
            -- Recharge swipe: derived from the entry's recharge duration
            -- (same source the bar branch scales by).
            local rechargeDur = spellEntry.rechargeDuration or 0
            if rechargeDur > 0 then
                slotRec.icon.cooldown:SetCooldown(GetTime() - (rechargeDur - recov), rechargeDur)
                slotRec.icon.cooldown._maBoundAt = GetTime()
            else
                slotRec.icon.cooldown:Clear()
            end
            slotRec.icon.cooldown:SetHideCountdownNumbers(true)
            slotRec.icon.timeText:SetFormattedText(PREC_FMT[decimals], recov)
            slotRec._maOut, slotRec._maFmt = "icon", PREC_FMT[decimals]
            slotRec.icon:Show()
        elseif showMode == "bar" then
            local rechargeDur = spellEntry.rechargeDuration or 0
            slotRec.bar:SetMinMaxValues(0, rechargeDur)
            slotRec.bar:SetValue(recov)
            local red, green, blue = ResolveAlertColor("textColor", "textColorUseClass")
            slotRec.bar:SetStatusBarColor(red, green, blue)
            slotRec.bar.text:SetShown(alertCfg.barShowDuration ~= false)
            if alertCfg.barShowDuration ~= false then
                slotRec.bar.text:SetFormattedText(PREC_FMT[decimals], recov)
            end
            slotRec._maOut, slotRec._maFmt, slotRec._maBarText =
                "bar", PREC_FMT[decimals], alertCfg.barShowDuration ~= false
            if alertCfg.barShowIcon ~= false and spellIcon then
                slotRec.bar.icon:SetTexture(spellIcon)
                slotRec.bar.icon:Show()
            else
                slotRec.bar.icon:Hide()
            end
            slotRec.bar:Show()
        else
            slotRec.text:SetFormattedText(formatStr, recov)
            slotRec._maOut, slotRec._maFmt = "text", formatStr
            slotRec.text:Show()
        end
        slotRec:Show()
        return true
    end

    local cdLeft, cdStart, cdDuration, cdModRate
    local hasSecretDuration = false
    -- True only when the duration OBJECT supplied the values below. The engine
    -- countdown is driven from that object, so anything resolved from cdInfo
    -- instead must not try to use it: the object was either absent or already
    -- rejected here, and SetCooldownFromDurationObject clears to nothing on an
    -- expired one while still reporting success.
    local fromDuration = false
    if dur then
        local rem, sum = dur:GetRemainingDuration(), dur:GetTotalDuration()
        if IsSecret(rem) or IsSecret(sum) then
            hasSecretDuration = true
            fromDuration = true
            cdLeft, cdDuration = rem, sum
            cdStart, cdModRate = dur:GetStartTime(), dur:GetModRate()
        elseif sum and sum > 1.5 and not IsLockoutWindow(spellEntry, sum) and rem and rem > 0 then
            fromDuration = true
            cdLeft, cdDuration = rem, sum
            cdStart, cdModRate = dur:GetStartTime(), dur:GetModRate()
        end
    end

    if not cdLeft and cdInfo then
        local s, skinData, m = cdInfo.startTime or 0, cdInfo.duration or 0, cdInfo.modRate or 1
        if IsSecret(s) or IsSecret(skinData) then
            hasSecretDuration = true
            cdStart, cdDuration, cdModRate, cdLeft = s, skinData, m, true
        -- This fallback never had the duration-object branch's own GCD floor,
        -- so anything the branch above rejected as too short landed here and
        -- rendered anyway.
        elseif skinData > 0 and not IsLockoutWindow(spellEntry, skinData) then
            cdStart, cdDuration, cdModRate = s, skinData, m
            cdLeft = math.max(0, (s + skinData) - GetTime())
        end
    end

    if not cdLeft then
        return false
    end
    if not hasSecretDuration and cdLeft <= 0 then
        return false
    end

    -- The text branches format cdRemaining themselves, so what decides them is
    -- whether THAT value can be rendered, not whether some other field of the
    -- same cooldown happened to be secret: hasSecretDuration is set when EITHER
    -- the remaining or the total is secret, and a secret total leaves a
    -- perfectly renderable remaining behind. Bar mode keeps using
    -- hasSecretDuration because it also feeds cdDuration to SetMinMaxValues.
    -- Both tests are secret-safe (no comparison against a secret): the sentinel
    -- is a plain boolean, and IsSecret is issecretvalue.
    local unreadableRemaining = type(cdLeft) == "boolean" or IsSecret(cdLeft)
    -- Show a number only when there is a real, positive one to show. The <= 0
    -- test is reachable ONLY once unreadableRemaining is false, so it never
    -- compares against a secret. It matters because the guard above lets a
    -- non-positive remaining through whenever hasSecretDuration was set by the
    -- OTHER field, which is the last route by which a literal 0.0 could still
    -- reach the display.
    local showRemaining = not unreadableRemaining and cdLeft > 0

    if showMode == "icon" then
        if spellIcon then
            slotRec.icon.tex:SetTexture(spellIcon)
            -- Single-argument form: every proven duration-object consumer in
            -- the suite calls it this way; the extra boolean is not part of
            -- the working pattern.
            if dur and slotRec.icon.cooldown.SetCooldownFromDurationObject then
                slotRec.icon.cooldown:SetCooldownFromDurationObject(dur)
            else
                slotRec.icon.cooldown:SetCooldown(cdStart, cdDuration, cdModRate)
            end
            slotRec.icon.cooldown._maBoundAt = GetTime()
            if hasSecretDuration then
                -- Secret timing: only the engine can render the number.
                slotRec.icon.cooldown:SetHideCountdownNumbers(false)
                slotRec.icon.timeText:SetText("")
                slotRec._maKind = "engine"
            else
                -- Our own countdown text for readable durations, refreshed by
                -- the repaint every tick; the engine numbers are suppressed here
                -- and serve only the secret branch.
                slotRec.icon.cooldown:SetHideCountdownNumbers(true)
                slotRec.icon.timeText:SetFormattedText(PREC_FMT[decimals], cdLeft)
                slotRec._maKind, slotRec._maEnd, slotRec._maFloor = "num", GetTime() + cdLeft, 0
                slotRec._maOut, slotRec._maFmt = "icon", PREC_FMT[decimals]
            end
            slotRec.icon:Show()
        else
            -- Icon mode with no icon falls back to text, so it needs the same
            -- guard as the text branch below.
            if not showRemaining then
                slotRec.text:SetText("No " .. spellName)
                if fromDuration and ShowEngineCountdown(slotRec, showMode, dur) then
                    slotRec._maKind = "engine"
                end
            else
                slotRec.text:SetFormattedText(formatStr, cdLeft)
                slotRec._maKind, slotRec._maEnd, slotRec._maFloor = "num", GetTime() + cdLeft, 0
                slotRec._maOut, slotRec._maFmt = "text", formatStr
            end
            slotRec.text:Show()
        end
    elseif showMode == "bar" then
        local red, green, blue = ResolveAlertColor("textColor", "textColorUseClass")
        slotRec.bar:SetStatusBarColor(red, green, blue)
        if type(cdLeft) == "boolean" then
            -- Only the sentinel leaves nothing to scale the fill with: show a
            -- full bar so the alert still reads as "unavailable" instead of an
            -- empty one, which would look like a cooldown that just finished.
            slotRec.bar:SetMinMaxValues(0, 1)
            slotRec.bar:SetValue(1)
        else
            -- A SECRET remaining still animates: SimpleStatusBar's SetValue and
            -- SetMinMaxValues are both AllowedWhenTainted, so the engine scales
            -- the fill from values Lua may not read. Gating this on
            -- hasSecretDuration would freeze the bar at 100% for no reason.
            slotRec.bar:SetMinMaxValues(0, cdDuration)
            slotRec.bar:SetValue(cdLeft)
            -- The repaint moves the fill: from our own remaining when readable,
            -- from the duration object (secret values allowed) when not.
            if showRemaining then
                slotRec._maKind, slotRec._maEnd, slotRec._maFloor = "num", GetTime() + cdLeft, 0
                slotRec._maOut, slotRec._maFmt, slotRec._maBarText =
                    "bar", PREC_FMT[decimals], alertCfg.barShowDuration ~= false
            elseif fromDuration then
                slotRec._maKind, slotRec._maDur = "fill", dur
            end
        end
        -- The NUMBER is the part Lua cannot produce, so it comes from our own
        -- formatter when readable and from the engine when not.
        if alertCfg.barShowDuration == false then
            slotRec.bar.text:SetShown(false)
        elseif showRemaining then
            slotRec.bar.text:SetShown(true)
            slotRec.bar.text:SetFormattedText(PREC_FMT[decimals], cdLeft)
        else
            slotRec.bar.text:SetShown(false)
            if fromDuration then
                ShowEngineCountdownCentred(slotRec, slotRec.bar, dur)
            end
        end
        if alertCfg.barShowIcon ~= false and spellIcon then
            slotRec.bar.icon:SetTexture(spellIcon)
            slotRec.bar.icon:Show()
        else
            slotRec.bar.icon:Hide()
        end
        slotRec.bar:Show()
    else -- any text mode (text_nd / text_dn / legacy "text")
        if not showRemaining then
            -- Whenever the remaining is unreadable, drop the number: the alert
            -- still says the ability is unavailable, which is the part that
            -- matters. Formatting it ourselves renders 0.0, which reads as
            -- "ready" -- the exact opposite of what the alert means.
            --
            -- BOTH producers land here, which is what the first pass at this
            -- got wrong. The cdInfo fallback stores a BOOLEAN sentinel (Lua
            -- cannot compute a remaining from a secret start plus duration),
            -- and the Duration-object path above stores a raw SECRET NUMBER.
            -- Only the sentinel used to be guarded, on the assumption that
            -- SetFormattedText being AllowedWhenTainted meant the engine would
            -- render a secret's real value. It does not: field-confirmed on
            -- 8.7.8, a secret remaining renders as 0.0 here. Icon mode never
            -- relied on that assumption -- it blanks its own text and lets the
            -- Cooldown widget draw the secret -- so the two branches disagreed
            -- and the text one was wrong. Gating on hasSecretDuration covers
            -- both producers and drops the fragile type() test with it.
            -- text_d shows only the number, so the label stays empty and the
            -- engine countdown is centred on the slot instead of beside it.
            slotRec.text:SetText(showMode == "text_d" and "" or ("No " .. spellName))
            -- The number Lua cannot format, drawn by the engine.
            if fromDuration and ShowEngineCountdown(slotRec, showMode, dur) then
                slotRec._maKind = "engine"
            end
        else
            slotRec.text:SetFormattedText(formatStr, cdLeft)
            slotRec._maKind, slotRec._maEnd, slotRec._maFloor = "num", GetTime() + cdLeft, 0
            slotRec._maOut, slotRec._maFmt = "text", formatStr
        end
        slotRec.text:Show()
    end

    slotRec:Show()
    -- Second return: the slot shows a readable cooldown long enough to be the
    -- spell's own, which arms the "ready" callout (see readyAlertArmed).
    return true, not hasSecretDuration and type(cdDuration) == "number" and cdDuration >= MIN_REAL_COOLDOWN
end

-------------------------------------------------------------------------------
--  buffActive lane (Burning Rush): ENGINE-OWNED end to end.
--  GetPlayerAuraBySpellID is RequiresNonSecretAura -- under aura restriction
--  (/cuidev = M+/raid combat, the viability bar) it returns ZERO VALUES for a
--  flagged spell WHILE THE BUFF IS UP, indistinguishable from absent
--  (field-settled 2026-08-13). No Lua probe or payload state machine can know
--  presence there; the engine can. One hidden AuraContainer with
--  includeSpellIDs shows/hides its button on presence entirely C-side,
--  identical in and out of restriction; the alert visual is a region ON the
--  engine button (visibility inherits, SetText is a display-only sink).
--  HOST RULES (forbidden-dependent geometry lock): UIParent-parented AND
--  UIParent-anchored, positioned NUMERICALLY, out of combat only -- the
--  engine child makes the host's own geometry writes ADDON_ACTION_BLOCKED
--  inside lockdown, so combat repositions park on a one-shot regen re-apply.
-------------------------------------------------------------------------------
local BUFF_ALERT_STYLE = "qol:movealert"

local function BuffAlertApplyExtra(btnFrame, skinData, style)
    local alertCfg = MA()
    local mode = alertCfg.displayMode or "text"
    if not skinData.maText then
        skinData.maText = btnFrame:CreateFontString(nil, "OVERLAY")
    end
    local record = style.maEntry
    local labelText = (record and (record.customText or record.spellName)) or "Active!"
    local red, green, blue = ResolveAlertColor("textColor", "textColorUseClass")
    -- same font, outline and size as the other alerts
    local fp, outline = AlertFontPath(), AlertFontOutline()
    local size = math.max(8, math.min(72, alertCfg.textSize or 24))
    if not skinData.maText:SetFont(fp, size, outline) then
        skinData.maText:SetFont(FALLBACK_FONT, size, outline)
    end
    skinData.maText:SetTextColor(red, green, blue)
    skinData.maText:ClearAllPoints()
    if mode == "icon" then
        if skinData.icon then
            skinData.icon:SetAlpha(1)
        end
        skinData.maText:Hide()
    else
        -- text AND bar modes render as the plain label: a permanent toggle
        -- buff has no duration for a bar to add, and the engine button is the
        -- only restriction-safe visibility carrier either way.
        if skinData.icon then
            skinData.icon:SetAlpha(0)
        end
        skinData.maText:SetPoint("CENTER", btnFrame, "CENTER", 0, 0)
        skinData.maText:SetText(labelText)
        skinData.maText:Show()
    end
end

local function BuildBuffAlertStyle(record)
    local alertCfg = MA()
    local px = (CludesUI.PP and CludesUI.PP.Scale and CludesUI.PP.Scale(alertCfg.iconSize or 32))
        or alertCfg.iconSize
        or 32
    return {
        width = px,
        height = px,
        iconCrop = true,
        hideDurationText = true, -- permanent buff: no countdown to draw
        hideSwipe = true,
        noTooltips = true,
        applyExtra = BuffAlertApplyExtra,
        maEntry = record,
    }
end

-- Identity gate (Blizzard_AuraContainer/Blizzard_AuraContainerUtil.lua,
-- AuraContainerUtil.CanApplyIdentityCandidateFilters + DoesAuraPassCandidateFilters,
-- verified 12.1.0.69299): includeSpellIDs is applied to a HELPFUL aura only while
-- UnitCanAssist("player", unit) holds, and it FAILS OPEN -- when the gate fails the
-- spell-ID filter is skipped entirely and the aura passes on its filter string
-- alone, so a group asking for one spell renders every buff. Boarding a
-- vehicle drops the player's own assistability, so this one-button HELPFUL group
-- stops meaning "Burning Rush" and renders whatever buff it finds first, wearing
-- the Burning Rush label. Membership is cached per aura instance and UNIT_AURA
-- only re-parses what changed, so the degraded parse outlived the ride: the alert
-- stayed up after dismounting until a reload rebuilt the container.
-- Latched from the vehicle events rather than probed here, because
-- UnitUsingVehicle is still true across the EXIT transition (see the RF assist
-- gate's AssistProbe, which guards the same engine gate one unit over).
local function BuffAlertAssistable()
    if buffAlertVehicle then
        return false
    end
    -- Cinematics flip the same flag without a vehicle (UNIT_FACTION edge). A
    -- CLEANLY-false answer denies; unreadable ones stay fail-open, since a
    -- transient nil must not blank a working alert.
    local success, canAssist = pcall(UnitCanAssist, "player", "player")
    if success and not IsSecret(canAssist) and canAssist == false then
        return false
    end
    return true
end

-- Reconcile the latch against the live flag. Needed wherever the EXITED edge
-- could have been missed: while the tracker's events are unregistered nothing
-- clears the latch, so a tracker switched off mid-ride (or a profile swap, or
-- being teleported out of a vehicle) would otherwise come back with the lane
-- suppressed for the rest of the session.
local function SyncBuffAlertVehicleLatch()
    local probe = UnitUsingVehicle or UnitInVehicle
    buffAlertVehicle = (probe and probe("player")) and true or false
end

-- Build once per session on first eligible pass (warlock + Movement Alerts on
-- + Burning Rush checked); later passes only refresh the style (mode/size/
-- color edits ride RestyleSoon) and the host's shown state. Engine frames are
-- permanent, so disable parks via host:Hide() (the container is a CHILD of the
-- host -- creation-time parenting is legal) and re-enable reuses everything.
local function EnsureBuffAlertLane()
    local AK = CludesUI.AuraKit
    if not (AK and AK.RequestContainer and AK.AddGroupToContainer and AK.RestyleSoon) then
        return
    end
    local record
    for _, e in ipairs(cachedMovementSpells) do
        if e.checkType == "buffActive" then
            record = e
            break
        end
    end
    if not record then
        if buffAlertHost then
            buffAlertHost:Hide()
        end
        return
    end
    -- Resolved ahead of the Show() below, not beside it: every pass runs through
    -- here, so a gate applied anywhere else would be undone by the next tick.
    local assist = BuffAlertAssistable()
    local wasDenied = (buffAlertAssist == false)
    buffAlertAssist = assist
    if buffAlertBuilt then
        if not assist then
            buffAlertHost:Hide()
            return
        end
        buffAlertHost:Show()
        -- Whatever was parsed during the degraded window is wrong, and leaving a
        -- vehicle produces no aura edge for buffs that were already up, so the
        -- engine would keep serving the stale membership (it is cached per aura
        -- instance; UNIT_AURA re-parses only what changed). The Show() above
        -- re-parses on its own -- AuraContainerPrivateMixin:OnShow_Intrinsic in
        -- Blizzard_AuraContainer/Blizzard_AuraContainer.lua calls UpdateAllAuras --
        -- and this is that same lever stated outright, so the recovery does not
        -- silently depend on the host being hidden rather than faded. NOTE the
        -- method is a no-op on AuraContainerSharedMixin; the real
        -- MarkDirty(FullAuraRebuild) is ManagedAuraContainerSharedMixin's
        -- override, which reaches the addon-callable partition through
        -- ManagedAuraContainerInboundMixin. Bounded to the real denied->allowed flip.
        if wasDenied and buffAlertContainer and buffAlertContainer.UpdateAllAuras then
            buffAlertContainer:UpdateAllAuras()
        end
        AK.styles[BUFF_ALERT_STYLE] = BuildBuffAlertStyle(record)
        AK.RestyleSoon(BUFF_ALERT_STYLE)
        return
    end
    -- Denial must not postpone the BUILD, only the display: logging in inside a
    -- vehicle (or behind an intro cinematic) would otherwise defer creation to
    -- the first allowed pass. Build unconditionally and park at the end; the
    -- container is created and hidden inside one call, so nothing renders in
    -- between.
    buffAlertBuilt = true
    buffAlertHost = CreateFrame("Frame", nil, UIParent)
    buffAlertHost:SetSize(2, 2)
    -- Provisional numeric seat; RepositionBuffAlertHost follows the alert
    -- stack on every out-of-combat render pass.
    buffAlertHost:SetPoint("CENTER", UIParent, "CENTER", 0, -260)
    AK.styles[BUFF_ALERT_STYLE] = BuildBuffAlertStyle(record)
    local include = { [record.spellId] = true }
    -- Override form too (talent variants share the alert); Burning Rush has
    -- none today, guarded for the day it grows one.
    if FindSpellOverrideByID then
        local shade = FindSpellOverrideByID(record.spellId)
        if type(shade) == "number" and shade > 0 then
            include[shade] = true
        end
    end
    AK.RequestContainer(buffAlertHost, "player", {
        point = { "CENTER", buffAlertHost, "CENTER", 0, 0 },
        layout = { anchorPoint = "CENTER", padding = { 0, 0, 0, 0 }, rowWidth = 400 },
    }, function(boxHolder)
        buffAlertContainer = boxHolder
        AK.AddGroupToContainer(boxHolder, {
            key = "buffalert",
            filter = { "HELPFUL" },
            style = BUFF_ALERT_STYLE,
            maxFrameCount = 1,
            candidateFilters = { includeSpellIDs = include },
            layout = { anchorPoint = "CENTER", padding = { 0, 0, 0, 0 }, rowWidth = 400 },
        })
    end)
    if not assist then
        buffAlertHost:Hide()
    end
end

-- Numeric follow of the alert stack's top (slots grow UP from movementFrame's
-- bottom, +2px gaps). Geometry reads are on OUR movementFrame (no engine
-- content beneath it -- always legal); the WRITE on the host is lockdown-
-- blocked, so combat passes arm a one-shot regen re-apply reading the LAST
-- counted stack height.
local function RepositionBuffAlertHost(stacks)
    if not buffAlertHost then
        return
    end
    buffAlertLastCount = stacks
    if InCombatLockdown() then
        if not buffAlertRegenFn then
            buffAlertRegenFn = function()
                RepositionBuffAlertHost(buffAlertLastCount or 0)
            end
        end
        ns.CombatQueue.Defer("BuffAlertHostPos", buffAlertRegenFn)
        return
    end
    local fw, fh = moveFrame:GetWidth(), moveFrame:GetHeight()
    local leftX, bottom = moveFrame:GetLeft(), moveFrame:GetBottom()
    if not (fw and fh and leftX and bottom) then
        return
    end
    buffAlertHost:ClearAllPoints()
    buffAlertHost:SetPoint(
        "CENTER",
        UIParent,
        "BOTTOMLEFT",
        leftX + fw / 2,
        bottom + stacks * (fh + 2) + fh / 2
    )
end

-------------------------------------------------------------------------------
--  Charge spells: "no movement remaining" must mean ZERO charges left.
--  currentCharges is a SECRET value -- verified live on Devourer's Shift, where
--  maxCharges reads 3 but currentCharges, cooldownDuration and every timing
--  field come back SECRET even out of combat -- so Lua can never branch on the
--  count, and IsSpellUsable reads true at 0 charges as well (also verified), so
--  it cannot stand in.
--  Blizzard's own discriminator is the cooldown's TOTAL duration: while a
--  charge is banked the spell reports only a GCD-length cooldown, and the full
--  recharge drives it only once the last charge is spent. A Step curve turns
--  that secret total into a secret ALPHA the engine resolves itself, with no
--  Lua comparison anywhere -- the same trick Action Bars uses to stop
--  banked-charge buttons desaturating (desatCurveReal / GetCdAlphaCurve).
--  Non-charge spells get LockoutAlpha instead: 1 in every readable case, and the
--  engine-resolved 0/1 when a secret window needs classifying -- a pooled slot
--  still can't keep a stale 0, because this runs for every shown slot each pass.
-------------------------------------------------------------------------------
local chargeAlphaCurve = nil -- nil = not built, false = API unavailable
local function GetChargeAlphaCurve()
    if chargeAlphaCurve == nil then
        if C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType then
            local c = C_CurveUtil.CreateCurve()
            c:SetType(Enum.LuaCurveType.Step)
            c:AddPoint(0, 0) -- GCD-length cooldown: a charge is banked -> hide
            c:AddPoint(1.6, 1) -- real recharge: out of charges -> show
            chargeAlphaCurve = c
        else
            chargeAlphaCurve = false
        end
    end
    return chargeAlphaCurve or nil
end

local function ApplyChargeVisibility(slotRec, alertSpell, chargeInfo, record, dur)
    if not slotRec then
        return
    end
    -- maxCharges stays PLAIN even when the rest of the charge record is secret,
    -- so this branch is safe (and is why the entry's cached isChargeSpell flag
    -- is not consulted -- SafeGetChargeInfo throws the whole record away when
    -- cooldownDuration is secret, leaving Shift cached as a 1-charge cooldown).
    local mc = chargeInfo and chargeInfo.maxCharges
    -- Non-charge: the only thing that hides the slot is a cross-ability lockout,
    -- and when its window is secret the engine-side compare in LockoutAlpha is
    -- the ONLY way to classify it. This is also the single writer of alpha on
    -- that path, so it must not be reduced to a bare SetAlpha(1) -- that is what
    -- let the lockout show through.
    if mc == nil or IsSecret(mc) or mc <= 1 then
        slotRec:SetAlpha(LockoutAlpha(record, dur))
        return
    end
    local curve = GetChargeAlphaCurve()
    -- Deliberately WITHOUT ignoreGCD: the GCD-length total IS the banked-charge
    -- signal the step curve keys on (a banked charge reports only a GCD-length
    -- cooldown; the full recharge drives it only once the last charge is spent).
    -- Asking the API to skip the GCD would change that signal's class and show
    -- the alert while a charge is still banked.
    local durObj = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(alertSpell)
    if curve and durObj and durObj.EvaluateTotalDuration then
        -- Result may be SECRET: never compare it. SetAlpha accepts secrets, and
        -- "or 1" on a secret number is safe (a secret is always truthy).
        slotRec:SetAlpha(durObj:EvaluateTotalDuration(curve, 1) or 1)
    else
        slotRec:SetAlpha(1)
    end
end

-- Same-frame coalescer for the check: cooldown/usable/charge storms and player
-- aura batches fire several times per frame, and every check re-queries each
-- tracked spell, so duplicates collapse into ONE check on the next OnUpdate.
-- The frame is shown only while a check is pending (zero cost idle); the full
-- checks the repaint asks for ride the same funnel so they can never double up
-- with an event-driven check in the same frame.
local movementCheckCharges = false
local movementCheckFrame = CreateFrame("Frame")
movementCheckFrame:Hide()
movementCheckFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    if movementCheckCharges then
        movementCheckCharges = false
        UpdateCachedCharges()
    end
    CheckMovementCooldown()
end)
RequestMovementCheck = function()
    movementCheckFrame:Show()
end
local function RequestMovementCheckWithCharges()
    movementCheckCharges = true
    movementCheckFrame:Show()
end

-- One repaint over the shown slots between full checks: a countdown Lua times
-- gets its new number (and bar fill), a bar timed by a secret duration object
-- its new fill; the engine draws every other number and swipe itself, and the
-- visibility curves read the cooldown's total, which only an event changes.
-- False once a countdown has run out or a start-recovery window has dropped
-- under its lockout threshold: the caller runs a full check instead.
local function RepaintMovementSlots(nowTime)
    for index = 1, activeSlotCount do
        local slotRec = displayPool[index]
        local kind = slotRec._maKind
        if kind == "num" then
            local rem = slotRec._maEnd - nowTime
            if rem <= 0 or rem < slotRec._maFloor then
                return false
            end
            local out = slotRec._maOut
            if out == "text" then
                slotRec.text:SetFormattedText(slotRec._maFmt, rem)
            elseif out == "icon" then
                slotRec.icon.timeText:SetFormattedText(slotRec._maFmt, rem)
            else
                slotRec.bar:SetValue(rem)
                if slotRec._maBarText then
                    slotRec.bar.text:SetFormattedText(slotRec._maFmt, rem)
                end
            end
        elseif kind == "fill" then
            slotRec.bar:SetValue(slotRec._maDur:GetRemainingDuration())
        end
    end
    return true
end

-- After a full check with slots up: repaint every 100 ms while a slot shows a
-- countdown Lua paints, and run the next full check by MOVEMENT_BACKSTOP while
-- a slot's end is timed by the engine alone (its OnCooldownDone normally runs
-- that check first; the backstop only bounds an end the engine leaves unreported).
local function ArmMovementRepaint(stacks)
    local nowTime = GetTime()
    local tick, untimed = false, false
    for index = 1, stacks do
        local kind = displayPool[index]._maKind
        if kind == "num" or kind == "fill" then
            tick = true
        end
        if kind ~= "num" then
            untimed = true
        end
    end
    movementBackstopAt = untimed and (nowTime + MOVEMENT_BACKSTOP) or math.huge
    movementRepaintAt = tick and (nowTime + 0.1) or movementBackstopAt
    movementRepaintFrame:Show()
end

movementRepaintFrame:SetScript("OnUpdate", function(self)
    local nowTime = GetTime()
    if nowTime < movementRepaintAt then
        return
    end
    if nowTime >= movementBackstopAt or not RepaintMovementSlots(nowTime) then
        self:Hide()
        RequestMovementCheck()
        return
    end
    movementRepaintAt = math.min(nowTime + 0.1, movementBackstopAt)
end)

CheckMovementCooldown = function()
    -- The options-panel preview owns the display while it runs; the real
    -- renderer resumes from the preview's stop path. Costs one nil-check.
    if movementPreviewTicker then
        return
    end
    local alertCfg = MA()
    if not MovementEnabled() then
        HideMovementDisplay()
        return
    end
    if alertCfg.combatOnly and not inCombat then
        HideMovementDisplay()
        return
    end
    if #cachedMovementSpells == 0 then
        HideMovementDisplay()
        return
    end

    local stacks = 0
    local nowShownReady = readyAlertScratch
    wipe(nowShownReady)
    for _, record in ipairs(cachedMovementSpells) do
        if record.checkType == "buffActive" then
            -- Engine-owned lane: presence rendering never passes through Lua
            -- (see EnsureBuffAlertLane). The entry deliberately takes no slot.
        else
            local alertSpell = record.baseSpellId or record.spellId
            local hasCharges = C_Spell.GetSpellCharges(alertSpell)
            local spellData = C_Spell.GetSpellCooldown(alertSpell)
            if
                spellData
                and spellData.timeUntilEndOfStartRecovery
                and (spellData.isOnGCD == false or (spellData.isOnGCD == nil and not hasCharges))
            then
                -- The duration OBJECT is the only thing that can put a number on
                -- screen while the cooldown is secret, so getting one matters more
                -- than which API supplies it. Two reasons it used to come back
                -- empty in combat: GetSpellCooldownDuration's second argument is
                -- ignoreGCD and it DEFAULTS TO FALSE, so while a global cooldown
                -- is running -- which in combat is most of the time -- it
                -- describes the GCD rather than the spell's own cooldown, and a
                -- GCD-length total is then rejected downstream; and an entry
                -- cached while its charge data was secret has isChargeSpell false
                -- even for a charge spell, sending it to the wrong API entirely.
                -- Ask for the real cooldown, and fall back to the other API
                -- rather than giving up.
                local dur
                if record.isChargeSpell and C_Spell.GetSpellChargeDuration then
                    dur = C_Spell.GetSpellChargeDuration(alertSpell)
                elseif C_Spell.GetSpellCooldownDuration then
                    dur = C_Spell.GetSpellCooldownDuration(alertSpell, true)
                end
                if not dur then
                    if record.isChargeSpell and C_Spell.GetSpellCooldownDuration then
                        dur = C_Spell.GetSpellCooldownDuration(alertSpell, true)
                    elseif C_Spell.GetSpellChargeDuration then
                        dur = C_Spell.GetSpellChargeDuration(alertSpell)
                    end
                end
                local isShown, ownCooldown = ShowMovementSlot(stacks + 1, spellData, record, dur)
                if isShown then
                    stacks = stacks + 1
                    nowShownReady[record.spellId] = record
                    if ownCooldown then
                        readyAlertArmed[record.spellId] = true
                    end
                    -- Charge spells alpha-hide while a charge is still banked;
                    -- non-charge slots get the secret-lockout classification.
                    ApplyChargeVisibility(GetDisplaySlot(stacks), alertSpell, hasCharges, record, dur)
                end
            end
        end
    end

    -- Engine lane: resolve build/park once per pass (self-hides when no
    -- buffActive spell is enabled for the spec), then seat the host at the
    -- stack top -- write side is OOC-gated inside RepositionBuffAlertHost.
    EnsureBuffAlertLane()
    RepositionBuffAlertHost(stacks)

    -- "Ready" callout (text to speech, else the picked sound): fires once per
    -- spell exactly when it drops out of the on-cooldown set above (not while
    -- it sits ready, and not on the first poll after the feature/spec/class
    -- gates just opened up), and only for a spell whose own cooldown was
    -- running (readyAlertArmed).
    if readyAlertFresh then
        readyAlertFresh = false
        for alertSpell in pairs(readyAlertArmed) do
            if not nowShownReady[alertSpell] then
                readyAlertArmed[alertSpell] = nil
            end
        end
    end
    local announce = alertCfg.maTtsEnabled or (alertCfg.maSoundKey and alertCfg.maSoundKey ~= "none")
    for alertSpell, record in pairs(readyAlertShown) do
        if not nowShownReady[alertSpell] then
            if announce and readyAlertArmed[alertSpell] then
                FireTrackerAlert("ma", record.customText or record.spellName)
            end
            readyAlertArmed[alertSpell] = nil
        end
    end
    readyAlertShown, readyAlertScratch = nowShownReady, readyAlertShown

    for index = stacks + 1, activeSlotCount do
        local slotRec = displayPool[index]
        if slotRec then
            slotRec.text:Hide()
            slotRec.icon:Hide()
            slotRec.icon.cooldown:Clear()
            slotRec.bar:Hide()
            HideEngineCountdown(slotRec)
            slotRec:Hide()
        end
    end

    if stacks > 0 then
        activeSlotCount = stacks
        LayoutDisplaySlots(stacks)
        moveFrame:Show()
        -- Smooth countdown repaint (and the backstop check) from here; every
        -- check moves both deadlines.
        ArmMovementRepaint(stacks)
    else
        activeSlotCount = 0
        -- EnsureBuffAlertLane just showed/parked the host for this pass; leave
        -- its verdict alone (see keepBuffLane).
        HideMovementDisplay(true)
    end
end
CludesUI._CheckMovementCooldown = function()
    if CheckMovementCooldown then
        CheckMovementCooldown()
    end
end

local function ApplyMovementFrame()
    local alertCfg = MA()
    if not alertCfg then
        return
    end
    moveFrame:ClearAllPoints()
    local place = alertCfg.pos
    if place and place.point then
        moveFrame:SetPoint(
            place.point,
            UIParent,
            place.relPoint or place.point,
            place.x or 0,
            place.y or 0
        )
        moveFrame:SetSize(place.width or 200, place.height or 40)
    else
        moveFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
        moveFrame:SetSize(200, 40)
    end
    for _, slotRec in ipairs(displayPool) do
        StyleSlot(slotRec)
    end
    if MovementEnabled() and not CludesUI._unlockActive then
        CheckMovementCooldown()
    end
end
CludesUI._applyMovementAlert = ApplyMovementFrame

-------------------------------------------------------------------------------
--  Options-panel preview: loops a fake cooldown through the real display
--  path, so every user setting (mode, size, color, format, precision, poll
--  rate) renders exactly as it will live. Zero cost while off: nothing here
--  exists but the functions, one ticker is created on activation, and the
--  real renderer pays a single nil-check. The tick self-terminates when the
--  options window closes or the user leaves the Movement Alerts page.
-------------------------------------------------------------------------------
local PREVIEW_CD = 8
local previewEnds = 0
local previewEntry = nil
local previewCdInfo = { startTime = 0, duration = PREVIEW_CD, modRate = 1 }

local function PreviewEntry()
    -- Prefer the player's first real tracked cooldown so the preview shows a
    -- familiar name/icon; fall back to any known class mobility spell.
    local e = cachedMovementSpells[1]
    if e and e.checkType ~= "buffActive" then
        return e
    end
    local classFile = select(2, UnitClass("player"))
    local classAbilities = MOVEMENT_ABILITIES[classFile]
    if classAbilities then
        for key, entries in pairs(classAbilities) do
            if type(key) == "number" and type(entries) == "table" then
                for _, spellRef in ipairs(entries) do
                    local details = C_Spell.GetSpellInfo(spellRef)
                    if details then
                        return { spellId = spellRef, spellName = details.name, spellIcon = details.iconID }
                    end
                end
            end
        end
    end
    local details = C_Spell.GetSpellInfo(2983) -- Sprint: any-class fallback art
    return {
        spellId = 2983,
        spellName = (details and details.name) or "Movement",
        spellIcon = details and details.iconID,
    }
end

local function StopMovementPreview()
    if not movementPreviewTicker then
        return
    end
    movementPreviewTicker:Cancel()
    movementPreviewTicker = nil
    previewEntry = nil
    HideMovementDisplay()
    -- Hand the display back to the real tracker state.
    CheckMovementCooldown()
end

local function PreviewTick()
    local alertCfg = MA()
    -- Auto-shutoff: options window closed, or the user navigated to another
    -- page/module. (Page name must match PAGE_MOVEMENT in CUI_QoL_Options.lua.)
    local isShown = CludesUI._mainFrame and CludesUI._mainFrame:IsShown()
    local onPage = isShown
        and CludesUI:GetActiveModule() == "CludesUIQoL"
        and CludesUI:GetActivePage() == "MoveAlert"
    if not alertCfg or not onPage then
        StopMovementPreview()
        return
    end

    local nowTime = GetTime()
    if nowTime >= previewEnds then
        previewEnds = nowTime + PREVIEW_CD
    end
    previewCdInfo.startTime = previewEnds - PREVIEW_CD
    if ShowMovementSlot(1, previewCdInfo, previewEntry) then
        for index = 2, activeSlotCount do
            local slotRec = displayPool[index]
            if slotRec then
                slotRec.text:Hide()
                slotRec.icon:Hide()
                slotRec.icon.cooldown:Clear()
                slotRec.bar:Hide()
                HideEngineCountdown(slotRec)
                slotRec:Hide()
            end
        end
        activeSlotCount = 1
        LayoutDisplaySlots(1)
        moveFrame:Show()
    end
end

local function StartMovementPreview()
    if movementPreviewTicker then
        return
    end
    local alertCfg = MA()
    if not alertCfg then
        return
    end
    previewEntry = PreviewEntry()
    previewEnds = GetTime() + PREVIEW_CD
    -- The preview owns the display: stop the real poll loop (its state
    -- resumes from StopMovementPreview's CheckMovementCooldown call).
    CancelMovementCountdown()
    movementPreviewTicker = C_Timer.NewTicker(0.1, PreviewTick)
    PreviewTick()
end

CludesUI._MovementAlertPreviewActive = function()
    return movementPreviewTicker ~= nil
end
CludesUI._MovementAlertPreview = function(on)
    if on then
        StartMovementPreview()
    else
        StopMovementPreview()
    end
end

-------------------------------------------------------------------------------
--  Time Spiral -- flashes when a tracked mobility spell's cooldown is
--  proc-reset (generic spell-activation-overlay glow on a tracked spell).
--  A second, CDM-bar based implementation of this same proc exists in
--  CludesUICooldownManager\CUI_CDM_BuffBarPresets.lua's "timespiral"
--  Tracked Buff Bar preset. The two are independent (this one
--  works without any CDM bar) but share the same spell/talent-filter lists --
--  keep MOVEMENT_ABILITIES[...].filter above in sync with that file's
--  TIME_SPIRAL_GLOW_FILTERS if either changes. Enabling both trackers at
--  once will fire both alerts off the same glow event -- harmless, just a
--  possible double-notification if a user turns both on.
-------------------------------------------------------------------------------
local spiralFrame = CreateFrame("Frame", "CUI_TimeSpiralFrame", UIParent)
spiralFrame:SetSize(200, 40)
spiralFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
spiralFrame:Hide()
local timeSpiralText = spiralFrame:CreateFontString(nil, "OVERLAY")
timeSpiralText:SetPoint("CENTER")

local timeSpiralActiveTime = nil
local timeSpiralActiveSpells = {}
local timeSpiralCountdownTimer = nil
local glowCooldown = 0
local procDebounce = 0
local castFilters = {}

local function RefreshCastFilters()
    wipe(castFilters)
    local classData = MOVEMENT_ABILITIES[select(2, UnitClass("player"))]
    if not classData or not classData.filter then
        return
    end
    for talentId, spells in pairs(classData.filter) do
        if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(talentId) then
            for _, ident in ipairs(spells) do
                castFilters[ident] = true
            end
        end
    end
end

local function OnSpellCast(alertSpell)
    if castFilters[alertSpell] then
        glowCooldown = GetTime() + 1.5
    end
end

local allMobilitySpells = {}
local function RebuildMobilitySpellLookup()
    wipe(allMobilitySpells)
    for _, classData in pairs(MOVEMENT_ABILITIES) do
        for key, value in pairs(classData) do
            if type(key) == "number" and type(value) == "table" then
                for _, alertSpell in ipairs(value) do
                    if not BUFF_ACTIVE_SPELLS[alertSpell] then
                        allMobilitySpells[alertSpell] = true
                    end
                end
            end
        end
    end
    local overrides = MA().spellOverrides
    if overrides then
        for alertSpell, overrideId in pairs(overrides) do
            if overrideId.enabled ~= false and not BUFF_ACTIVE_SPELLS[alertSpell] then
                allMobilitySpells[alertSpell] = true
            end
        end
    end
end
CludesUI._RebuildMovementSpellLookup = RebuildMobilitySpellLookup

local function IsValidTimeSpiralProc(alertSpell)
    local nowTime = GetTime()
    if BUFF_ACTIVE_SPELLS[alertSpell] then
        return false
    end
    local classFile = select(2, UnitClass("player"))
    local specId = ResolvePlayerSpecId()
    local classData = MOVEMENT_ABILITIES[classFile]
    local specSpells = classData and specId and classData[specId]
    if CludesUI.IS_FOREVER and specId then
        specSpells = ForeverMovementList()
    end
    local matched = false
    if specSpells then
        for _, ident in ipairs(specSpells) do
            if ident == alertSpell then
                matched = true
                break
            end
            if C_Spell.GetOverrideSpell then
                local okOvr, oid = pcall(C_Spell.GetOverrideSpell, ident)
                if okOvr and oid and oid == alertSpell then
                    matched = true
                    break
                end
            end
        end
    end
    if not matched and allMobilitySpells[alertSpell] then
        matched = true
    end
    if not matched then
        return false
    end
    if nowTime < glowCooldown then
        return false
    end
    if (nowTime - procDebounce) < 0.12 then
        return false
    end
    return true
end

local function CancelTimeSpiralCountdown()
    if timeSpiralCountdownTimer then
        timeSpiralCountdownTimer:Cancel()
        timeSpiralCountdownTimer = nil
    end
end

local function UpdateTimeSpiralCountdown()
    local alertCfg = MA()
    if not alertCfg.tsEnabled or not timeSpiralActiveTime then
        spiralFrame:Hide()
        CancelTimeSpiralCountdown()
        return
    end
    local remaining = 10 - (GetTime() - timeSpiralActiveTime)
    if remaining > 0 then
        local formatStr = (alertCfg.tsTextFormat or "FREE MOVEMENT\\n%.1f"):gsub("\\n", "\n")
        timeSpiralText:SetFormattedText(formatStr, remaining)
        spiralFrame:Show()
        timeSpiralCountdownTimer = C_Timer.NewTimer(0.1, UpdateTimeSpiralCountdown)
    else
        timeSpiralActiveTime = nil
        spiralFrame:Hide()
        CancelTimeSpiralCountdown()
    end
end

local function ApplyTimeSpiralFrame()
    local alertCfg = MA()
    if not alertCfg then
        return
    end
    -- Self-correct: if this got turned off while the banner was actively
    -- showing/counting down, the disable path only cancels the countdown
    -- timer (the one thing that would otherwise hide it) -- explicitly hide
    -- here so it can't get stuck on screen.
    if not alertCfg.tsEnabled then
        timeSpiralActiveTime = nil
        CancelTimeSpiralCountdown()
        spiralFrame:Hide()
        return
    end
    spiralFrame:ClearAllPoints()
    local place = alertCfg.tsPos
    if place and place.point then
        spiralFrame:SetPoint(
            place.point,
            UIParent,
            place.relPoint or place.point,
            place.x or 0,
            place.y or 0
        )
        spiralFrame:SetSize(place.width or 200, place.height or 40)
    else
        spiralFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        spiralFrame:SetSize(200, 40)
    end
    local fontFile, outline = AlertFontPath(), AlertFontOutline()
    local fontPx = math.max(10, math.min(72, math.floor(spiralFrame:GetHeight() * 0.55)))
    if not timeSpiralText:SetFont(fontFile, fontPx, outline) then
        timeSpiralText:SetFont(FALLBACK_FONT, fontPx, outline)
    end
    local red, green, blue = ResolveAlertColor("tsColor", "tsColorUseClass")
    timeSpiralText:SetTextColor(red, green, blue)
end
CludesUI._applyTimeSpiral = ApplyTimeSpiralFrame

-------------------------------------------------------------------------------
--  Gateway Shard -- Warlock's Demonic Gateway control item
-------------------------------------------------------------------------------
local GATEWAY_SHARD_ITEM_ID = 188152
local gateFrame = CreateFrame("Frame", "CUI_GatewayShardFrame", UIParent)
gateFrame:SetSize(200, 40)
gateFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
gateFrame:Hide()
local gatewayText = gateFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
gatewayText:SetPoint("CENTER")

local lastGatewayUsable = false
local lastGatewayText = nil
local gatewayPollTicker = nil

local function StopGatewayPolling()
    if gatewayPollTicker then
        gatewayPollTicker:Cancel()
        gatewayPollTicker = nil
    end
end

local function CheckGatewayUsable()
    local alertCfg = MA()
    if not alertCfg.gwEnabled then
        gateFrame:Hide()
        StopGatewayPolling()
        return
    end

    local success, itemCount = pcall(C_Item.GetItemCount, GATEWAY_SHARD_ITEM_ID)
    itemCount = success and itemCount or 0
    if itemCount == 0 then
        gateFrame:Hide()
        lastGatewayUsable = false
        return
    end

    -- Combat Only + out of combat: the result can't change until the next
    -- combat transition (PLAYER_REGEN_DISABLED resumes polling), so pause
    -- the ticker instead of continuing to poll the item API 10x/second for
    -- nothing.
    if alertCfg.gwCombatOnly and not inCombat then
        gateFrame:Hide()
        lastGatewayUsable = false
        StopGatewayPolling()
        return
    end

    local isUsable = not not C_Item.IsUsableItem(GATEWAY_SHARD_ITEM_ID)
    if isUsable and not lastGatewayUsable then
        FireTrackerAlert("gw")
    end
    lastGatewayUsable = isUsable

    -- 10 Hz poll: only the usability read is per-tick work; the label and
    -- visibility are written on change (a label edit still lands live).
    if isUsable then
        local txt = alertCfg.gwText or "GATEWAY READY"
        if txt ~= lastGatewayText then
            lastGatewayText = txt
            gatewayText:SetText(txt)
        end
        if not gateFrame:IsShown() then
            gateFrame:Show()
        end
    elseif gateFrame:IsShown() then
        gateFrame:Hide()
    end
end
CludesUI._CheckGatewayUsable = CheckGatewayUsable

local function StartGatewayPolling()
    StopGatewayPolling()
    local alertCfg = MA()
    if not alertCfg.gwEnabled then
        return
    end
    CheckGatewayUsable()
    -- CheckGatewayUsable already self-pauses (via StopGatewayPolling) when
    -- Combat Only is on and we're out of combat -- don't immediately
    -- recreate the ticker it just stopped. PLAYER_REGEN_DISABLED calls
    -- StartGatewayPolling() again on combat entry to resume it.
    if alertCfg.gwCombatOnly and not inCombat then
        return
    end
    gatewayPollTicker = C_Timer.NewTicker(0.1, CheckGatewayUsable)
end

local function ApplyGatewayFrame()
    local alertCfg = MA()
    if not alertCfg then
        return
    end
    gateFrame:ClearAllPoints()
    local place = alertCfg.gwPos
    if place and place.point then
        gateFrame:SetPoint(
            place.point,
            UIParent,
            place.relPoint or place.point,
            place.x or 0,
            place.y or 0
        )
        gateFrame:SetSize(place.width or 200, place.height or 40)
    else
        gateFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
        gateFrame:SetSize(200, 40)
    end
    local fontFile, outline = AlertFontPath(), AlertFontOutline()
    local fontPx = math.max(10, math.min(72, math.floor(gateFrame:GetHeight() * 0.55)))
    if not gatewayText:SetFont(fontFile, fontPx, outline) then
        gatewayText:SetFont(FALLBACK_FONT, fontPx, outline)
    end
    local red, green, blue = ResolveAlertColor("gwColor", "gwColorUseClass")
    gatewayText:SetTextColor(red, green, blue)
    if not alertCfg.gwEnabled then
        StopGatewayPolling()
        gateFrame:Hide()
    elseif CludesUI._unlockActive then
        -- Pause the poll ticker while Unlock Mode is active: CheckGatewayUsable
        -- can Hide() this frame the instant the item isn't currently usable
        -- (the common case), fighting the user mid-drag. Force it visible
        -- instead so it can be repositioned regardless of current item state.
        StopGatewayPolling()
        gateFrame:Show()
    else
        StartGatewayPolling()
    end
end
CludesUI._applyGateway = ApplyGatewayFrame

-------------------------------------------------------------------------------
--  Event registration
-------------------------------------------------------------------------------
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("PLAYER_LOGIN")

-- Baseline events (spec/talent/combat/world transitions) drive the shared
-- caches all three trackers read. They are registered only while at least
-- one tracker is enabled, so a user with the whole page off pays for
-- nothing: no events fire and no spellbook cache work ever runs.
local BASELINE_EVENTS = {
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_DEAD",
}

local baselineEventsRegistered = false
local movementEventsRegistered = false
local timeSpiralEventsRegistered = false

local function UpdateEventRegistration()
    local alertCfg = MA()
    if not alertCfg then
        return
    end

    local moveOn = MovementEnabled()
    local anyEnabled = moveOn or alertCfg.tsEnabled or alertCfg.gwEnabled
    if anyEnabled and not baselineEventsRegistered then
        for _, ev in ipairs(BASELINE_EVENTS) do
            loadFrame:RegisterEvent(ev)
        end
        baselineEventsRegistered = true
        -- The lookup/cache passes are skipped at login while everything is
        -- off, so the first enable must build them (and pick up the real
        -- combat state) before any tracker logic runs.
        inCombat = UnitAffectingCombat("player")
        RebuildMobilitySpellLookup()
        CacheMovementSpells(true)
        -- Register the bar-texture tables with SharedMedia (idempotent; also
        -- installs the session-long late-registration callback), matching the
        -- CDM Tracking Bars setup: a saved SM texture renders correctly
        -- without the options panel ever opening.
        CludesUI.AppendSharedMediaTextures(BAR_TEXTURE_NAMES, BAR_TEXTURE_ORDER, nil, BAR_TEXTURES)
    elseif not anyEnabled and baselineEventsRegistered then
        for _, ev in ipairs(BASELINE_EVENTS) do
            loadFrame:UnregisterEvent(ev)
        end
        baselineEventsRegistered = false
        CancelAllRechargeTimers()
    end

    if moveOn and not movementEventsRegistered then
        loadFrame:RegisterEvent("SPELL_UPDATE_USABLE")
        loadFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        loadFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
        loadFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        loadFrame:RegisterUnitEvent("UNIT_AURA", "player")
        -- buffActive lane's identity gate (see BuffAlertAssistable): the
        -- occupancy latch plus the faction edge cinematics flip. Player-only,
        -- and only while the tracker is on. ENTERING as well as ENTERED --
        -- the filters degrade from the boarding transition. CINEMATIC_STOP
        -- covers the addon-cancelled skip, whose faction restore can order
        -- ahead of the edge above (the RF gate carries it for the same reason);
        -- the lane runs no ticker, so a missed restore leaves it hidden.
        loadFrame:RegisterUnitEvent("UNIT_ENTERING_VEHICLE", "player")
        loadFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
        loadFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
        loadFrame:RegisterUnitEvent("UNIT_FACTION", "player")
        loadFrame:RegisterEvent("CINEMATIC_STOP")
        -- The EXITED edge cannot reach a lane whose events are unregistered.
        SyncBuffAlertVehicleLatch()
        movementEventsRegistered = true
    elseif not moveOn and movementEventsRegistered then
        loadFrame:UnregisterEvent("SPELL_UPDATE_USABLE")
        loadFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        loadFrame:UnregisterEvent("SPELL_UPDATE_CHARGES")
        loadFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        loadFrame:UnregisterEvent("UNIT_AURA")
        loadFrame:UnregisterEvent("UNIT_ENTERING_VEHICLE")
        loadFrame:UnregisterEvent("UNIT_EXITED_VEHICLE")
        loadFrame:UnregisterEvent("UNIT_ENTERED_VEHICLE")
        loadFrame:UnregisterEvent("UNIT_FACTION")
        loadFrame:UnregisterEvent("CINEMATIC_STOP")
        movementEventsRegistered = false
        CancelMovementCountdown()
    end

    if alertCfg.tsEnabled and not timeSpiralEventsRegistered then
        loadFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        loadFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
        loadFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
        timeSpiralEventsRegistered = true
        RefreshCastFilters()
    elseif not alertCfg.tsEnabled and timeSpiralEventsRegistered then
        loadFrame:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        loadFrame:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
        loadFrame:UnregisterEvent("UNIT_SPELLCAST_SENT")
        timeSpiralEventsRegistered = false
        CancelTimeSpiralCountdown()
    end

    if alertCfg.gwEnabled then
        StartGatewayPolling()
    else
        StopGatewayPolling()
        if not alertCfg.gwEnabled then
            gateFrame:Hide()
        end
    end
end
CludesUI._UpdateMovementAlertEvents = UpdateEventRegistration

loadFrame:SetScript("OnEvent", function(self, evt, ...)
    local alertCfg = MA()
    if not alertCfg then
        return
    end

    if evt == "PLAYER_LOGIN" then
        -- Zero cost while every tracker is off: UpdateEventRegistration does
        -- the lookup/cache build when the first tracker registers baseline
        -- events (now, or later from the options toggle) -- nothing below
        -- runs for a user with the whole page disabled except the cheap
        -- unlock-mover registration.
        UpdateEventRegistration()
        if MovementEnabled() or alertCfg.tsEnabled or alertCfg.gwEnabled then
            ApplyMovementFrame()
            ApplyTimeSpiralFrame()
            ApplyGatewayFrame()
            CheckMovementCooldown()
            C_Timer.After(0.5, function()
                if ResolvePlayerSpecId() then
                    CacheMovementSpells(true)
                    CheckMovementCooldown()
                end
            end)
        end
        -- Unlock Mode elements: RegisterUnlockElements/MakeUnlockElement are
        -- safe to call immediately at login (no need for the extra delay
        -- some older modules used) -- registration itself just stores the
        -- config, it doesn't require Unlock Mode's own body to be loaded yet.
        if CludesUI.RegisterUnlockElements and CludesUI.MakeUnlockElement then
            local MK = CludesUI.MakeUnlockElement

            local function MakeMoverEntry(key, labelText, sequence, isHiddenKey, getFrameFn, applyFn, posKey)
                return MK({
                    key = key,
                    label = labelText,
                    group = "Utilities",
                    order = sequence,
                    -- isHiddenKey: profile key name, or a predicate function
                    -- (the movement tracker's enable state is per-class).
                    isHidden = function()
                        if type(isHiddenKey) == "function" then
                            return not isHiddenKey()
                        end
                        return not MA()[isHiddenKey]
                    end,
                    getFrame = getFrameFn,
                    getSize = function()
                        local place = MA()[posKey]
                        return (place and place.width) or 200, (place and place.height) or 40
                    end,
                    setWidth = function(_, wid)
                        local m = MA()
                        m[posKey] = m[posKey] or {}
                        m[posKey].width = math.max(60, math.floor(wid + 0.5))
                        applyFn()
                    end,
                    setHeight = function(_, hgt)
                        local m = MA()
                        m[posKey] = m[posKey] or {}
                        m[posKey].height = math.max(20, math.floor(hgt + 0.5))
                        applyFn()
                    end,
                    savePos = function(_, point, relPoint, posX, posY)
                        if not point then
                            return
                        end
                        local m = MA()
                        m[posKey] = m[posKey] or {}
                        m[posKey].point, m[posKey].relPoint, m[posKey].x, m[posKey].y =
                            point, relPoint, posX, posY
                    end,
                    loadPos = function()
                        local place = MA()[posKey]
                        if place and place.point then
                            return place
                        end
                        return nil
                    end,
                    clearPos = function()
                        MA()[posKey] = nil
                        applyFn()
                    end,
                    applyPos = applyFn,
                })
            end

            CludesUI:RegisterUnlockElements({
                MakeMoverEntry("CUI_MovementAlert", "Movement Alerts", 750, MovementEnabled, function()
                    return moveFrame
                end, ApplyMovementFrame, "pos"),
                MakeMoverEntry(
                    "CUI_TimeSpiralAlert",
                    "Movement Alerts - Time Spiral",
                    751,
                    "tsEnabled",
                    function()
                        return spiralFrame
                    end,
                    ApplyTimeSpiralFrame,
                    "tsPos"
                ),
                MakeMoverEntry(
                    "CUI_GatewayShardAlert",
                    "Movement Alerts - Gateway Shard",
                    752,
                    "gwEnabled",
                    function()
                        return gateFrame
                    end,
                    ApplyGatewayFrame,
                    "gwPos"
                ),
            })
        end
        return
    end

    if
        evt == "PLAYER_SPECIALIZATION_CHANGED"
        or evt == "PLAYER_TALENT_UPDATE"
        or evt == "TRAIT_CONFIG_UPDATED"
    then
        if not InCombatLockdown() then
            CacheMovementSpells(true)
            CheckMovementCooldown()
            RefreshCastFilters()
        end
    elseif evt == "UPDATE_SHAPESHIFT_FORM" then
        CacheMovementSpells()
        CheckMovementCooldown()
    elseif evt == "PLAYER_ENTERING_WORLD" then
        inCombat = UnitAffectingCombat("player")
        -- Safety net for an exit that never fires UNIT_EXITED_VEHICLE (being
        -- teleported out of one).
        SyncBuffAlertVehicleLatch()
        wipe(timeSpiralActiveSpells)
        timeSpiralActiveTime = nil
        CacheMovementSpells(true)
        CheckMovementCooldown()
        CheckGatewayUsable()
    elseif evt == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        CheckMovementCooldown()
        -- Combat Only paused the ticker on the last out-of-combat check;
        -- StartGatewayPolling() resumes it now that inCombat is true.
        -- (No-op beyond a single CheckGatewayUsable call when Combat Only
        -- isn't set, since the ticker was never stopped in that case.)
        if alertCfg.gwEnabled then
            StartGatewayPolling()
        else
            CheckGatewayUsable()
        end
    elseif evt == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        CancelAllRechargeTimers()
        wipe(chargeRechargeStart)
        for alertSpell in pairs(spellWasCast) do
            local cdInfo = C_Spell.GetSpellCooldown(alertSpell)
            local cdRemain = 0
            if
                cdInfo
                and cdInfo.startTime
                and cdInfo.duration
                and not IsSecret(cdInfo.startTime)
                and not IsSecret(cdInfo.duration)
                and cdInfo.duration > 0
            then
                cdRemain = math.max(0, (cdInfo.startTime + cdInfo.duration) - GetTime())
            end
            if cdRemain <= 0 then
                spellWasCast[alertSpell] = nil
                spellCastTime[alertSpell] = nil
            end
        end
        CacheMovementSpells()
        CheckMovementCooldown()
        CheckGatewayUsable()
    elseif
        evt == "SPELL_UPDATE_COOLDOWN"
        or evt == "SPELL_UPDATE_USABLE"
        or evt == "SPELL_UPDATE_CHARGES"
    then
        RequestMovementCheckWithCharges()
    elseif evt == "UNIT_AURA" then
        RequestMovementCheckWithCharges()
    elseif evt == "UNIT_ENTERING_VEHICLE" or evt == "UNIT_ENTERED_VEHICLE" then
        buffAlertVehicle = true
        RequestMovementCheck()
    elseif evt == "UNIT_EXITED_VEHICLE" then
        buffAlertVehicle = false
        RequestMovementCheck()
    elseif evt == "UNIT_FACTION" or evt == "CINEMATIC_STOP" then
        -- Re-drive ONLY: a cinematic flips assistability with no vehicle
        -- involved, and BuffAlertAssistable's own probe reads that. Neither
        -- may touch the latch -- UNIT_FACTION also fires on the BOARDING
        -- transition, where clearing it would undo the suppression we just set.
        RequestMovementCheck()
    elseif evt == "PLAYER_DEAD" then
        RequestMovementCheck()
    elseif evt == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitToken, _, alertSpell = ...
        for _, mod in ipairs(TALENT_CD_REDUCTIONS) do
            if alertSpell == mod.trigger and IsPlayerSpell and IsPlayerSpell(mod.talent) then
                for _, record in ipairs(cachedMovementSpells) do
                    if record.spellId == mod.spell or record.baseSpellId == mod.spell then
                        local spellRef = record.spellId
                        local current = cachedChargeCount[spellRef] or 0
                        if current == 0 then
                            local rechargeStart = chargeRechargeStart[spellRef] or spellCastTime[spellRef]
                            local rechargeDur = record.rechargeDuration or 0
                            if rechargeStart and rechargeDur > 0 then
                                local remaining = math.max(0, (rechargeStart + rechargeDur) - GetTime())
                                if remaining > 0 then
                                    if rechargeTimers[spellRef] then
                                        rechargeTimers[spellRef]:Cancel()
                                        rechargeTimers[spellRef] = nil
                                    end
                                    local newRemaining = remaining - mod.reduce
                                    if newRemaining > 0 then
                                        chargeRechargeStart[spellRef] = GetTime() - (rechargeDur - newRemaining)
                                        StartRechargeTimer(record, newRemaining)
                                    else
                                        cachedChargeCount[spellRef] =
                                            math.min(current + 1, record.maxCharges or 1)
                                        spellWasCast[spellRef] = nil
                                        spellCastTime[spellRef] = nil
                                        if (cachedChargeCount[spellRef] or 0) < (record.maxCharges or 1) then
                                            chargeRechargeStart[spellRef] = GetTime()
                                            StartRechargeTimer(record)
                                        else
                                            chargeRechargeStart[spellRef] = nil
                                        end
                                    end
                                end
                            end
                        end
                        break
                    end
                end
            end
        end
        OnTrackedSpellCast(alertSpell)
        RequestMovementCheck()
    elseif evt == "UNIT_SPELLCAST_SENT" then
        local _, _, _, alertSpell = ...
        OnSpellCast(alertSpell)
    elseif evt == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        local alertSpell = ...
        if alertCfg.tsEnabled and IsValidTimeSpiralProc(alertSpell) then
            procDebounce = GetTime()
            timeSpiralActiveSpells[alertSpell] = true
            timeSpiralActiveTime = GetTime()
            FireTrackerAlert("ts")
            CancelTimeSpiralCountdown()
            UpdateTimeSpiralCountdown()
        end
    elseif evt == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        local alertSpell = ...
        if alertSpell then
            timeSpiralActiveSpells[alertSpell] = nil
        end
        if not next(timeSpiralActiveSpells) then
            timeSpiralActiveTime = nil
            CancelTimeSpiralCountdown()
            spiralFrame:Hide()
        end
    end
end)
