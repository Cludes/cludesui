if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local _, mod = ...
-- Born in this module's main chunk, so the aura containers it builds bill this
-- module (AuraKit's shared build scheduler).
local AKWorker = CludesUI.AuraKit.NewBuildWorker()

-- ===========================================================================
--  CludesUI CDM -- Custom Active State engine (isolated)
-- ===========================================================================
-- Draws OUR OWN icon (saturated, with its own duration swipe) on top of an
-- existing CDM icon while a custom "active window" is open, then hides it. It
-- NEVER modifies the underlying icon -- no desaturation, no swipe, no cooldown
-- changes; the underlying icon just sits beneath, covered while we are active.
--
-- Two rule sources:
--   1. Built-in rules (FAKE_ACTIVE_RULES) -- class/spec gated, can use an aura's
--      live remaining time (e.g. Aug Evoker Ebon Might).
--   2. User rules -- any cd/utility preset (trinket / potion / racial / custom
--      spell id) the player gives an "Active State" + timer to in the per-spell
--      menu. Stored at the PROFILE level keyed by spell (ns.GetCustomActiveStates),
--      so it travels with the spell across bars and specs. Triggered on use
--      (UNIT_SPELLCAST_SUCCEEDED); the entry's own Active Swipe / Active Glow /
--      Glow Effect Color fields style the overlay.
--
-- ISOLATION / ZERO-COST
--   * Built-in rules live in FAKE_ACTIVE_RULES below (one row each).
--   * Re-armed on every CDM full rebuild. If nothing is active for this spec /
--     profile, no events register and the engine is inert.
--
-- TAINT: trigger is a plain event; the overlay is entirely our own frames,
-- toggled by alpha (never Show/Hide). No Blizzard frame tables are written.
-- ===========================================================================

local GetTime = GetTime
local UnitClass = UnitClass
local GetSpecialization = C_SpecializationInfo.GetSpecialization
local GetInventoryItemID = GetInventoryItemID
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local C_Item = C_Item
local C_SpellBook = C_SpellBook
local wipe = wipe
local pcall = pcall
local type = type
local tonumber = tonumber
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local C_Container = C_Container
local GetInventoryItemCooldown = GetInventoryItemCooldown
local GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID

-- 12.1 ONLY: engine-slot driver for aura-triggered built-in rules. Ebon Might
-- (395296) was removed from the never-secret list in build 68824, so
-- GetPlayerAuraBySpellID returns nothing for it in restricted content and the numeric
-- expirationTime window can never open mid-combat. The replacement rides a hidden
-- one-slot aura container (includeSpellIDs on the player -- helpful-on-assistable
-- passes the identity gate regardless of secrecy) whose slot subtree IS the active
-- display, engine-driven end to end: the button shows only while the aura is up,
-- SetIcon binds the aura's own texture, SetDurationCooldown renders the swipe from the
-- real duration object (extensions included), and SetDurationText drives the countdown
-- text -- all styled inside the creation window (the subtree is denied to addon code
-- afterward, reads and writes both). The legacy overlay frame stays permanently dark on
-- 12.1; it survives only for border raising and the shared settings plumbing in
-- ApplyToFrame. Declared here (above ApplyToFrame) so the consumer sites capture it as
-- an upvalue; defined after ApplyRule below.
local FA121

-- ---------------------------------------------------------------------------
--  BUILT-IN RULES
-- ---------------------------------------------------------------------------
-- spellID        the CDM icon to decorate (the ability icon's spellID)
-- class / spec   optional gates (spec = index 1..4)
-- trigger        "aura" | "cast" | function(api) -> expiry|true|nil
-- auraSpellID    (aura)  player buff whose expirationTime drives the window
-- triggerSpellID (cast)  spell whose cast opens the window (default = spellID)
-- duration       window seconds ("aura": fallback when the aura reports none)
local FAKE_ACTIVE_RULES = {
    -- Augmentation Evoker -- Ebon Might (real buff window, extend/drop aware).
    {
        spellID = 395152,
        class = "EVOKER",
        spec = 3,
        trigger = "aura",
        auraSpellID = 395296,
        duration = 20,
    },
}

-- ---------------------------------------------------------------------------
--  State
-- ---------------------------------------------------------------------------
local _armed = false
local _rules = {} -- all live rules this spec/profile
local _auraRules = {} -- subset: aura trigger
local _customRules = {} -- subset: function trigger
local _castMap = {} -- castSpellID -> { rule, ... }
-- Cast rules with an item whose data had not loaded when they were mapped
-- (login, /reload): rule -> { itemID = true }. ITEM_DATA_LOAD_RESULT maps them
-- again as the data lands, registered only while a rule waits. Settled: the
-- items whose load answered since the last re-arm, never waited on again.
local _pendingCastRules = {}
local _settledCastItems = {}
local _needAura = false
local _needCast = false
local _windows = setmetatable({}, { __mode = "k" }) -- rule -> { start, dur, expiry }
local _lastCast
local _events
local _ticker
local _api = {}
local _overlays = setmetatable({}, { __mode = "k" }) -- iconFrame -> overlay data

-- Cooldown-state effects (continuous, cooldown-driven; presets only).
local _cdStateRules = {} -- subset: a cd-state hide, glow or ready sound set
-- Same-frame coalescer for edge-driven cd-state evaluation. The engine owns
-- the edges (widget push = cooldown started, OnCooldownDone = cooldown ended),
-- so there is NO poll ticker: evaluation runs only when an edge fires.
local _cdEvalQueued = false
local _hasUserRules = false -- any profile (user) rule armed
-- Any cd-state rule on Hidden Until Usable: its proc edges change only
-- usability, so SPELL_UPDATE_USABLE joins the edges while one exists. Any on
-- Hidden Outside Form/Stance: UPDATE_SHAPESHIFT_FORM, likewise, and the
-- player's UNIT_AURA for a powershift, whose return fires no form event
-- (_formSeen: the form ID at the last form edge). The form rules whose
-- answers hang on a druid exception aura (_formAuraRules) re-evaluate alone
-- when the UNIT_AURA payload shows one coming or going (ns.CdmFormAuraEdge).
local _needUsable, _needForms, _needFormAuras, _formSeen = false, false, false, nil
-- Any cd-state rule with a Stance Bar hide (CludesUICdmStanceBar.lua): a
-- stance bar page change (UPDATE_BONUS_ACTIONBAR, UPDATE_STEALTH for Prowl).
local _needStance = false
local _formAuraRules = {}
local _formAuraQueued = false

-- CD-ready sound "armed" state, keyed by ability so it survives the rule-object
-- churn of FakeActive_Rearm (rebuilds are frequent in M+ and would otherwise eat
-- the ready edge). Empty at login, so an already-ready preset never false-fires.
local _cdrArmedByKey = {}

-- Forward declarations
local GetOverlay, ResolveSwipeColor, IconTexture, ApplyToFrame, ApplyRule, RaiseOverlayBorders, RestoreOverlayBorders
local EnsureTicker, OpenWindow, CloseWindow, CloseAll, CastWindow
local OpenFromAura, EvalCustom, InitialStamp, OnEvent, UpdateListeners
local ResolveCastSpells, PresetAltItemIDs, RetryPendingCasts
local PresetOnCD, ApplyCdState, RestoreAllCdState, EvalCdStateNow, QueueCdStateEval, QueueFormAuraEval

-- ---------------------------------------------------------------------------
--  Icon identity: slot key <-> equipped item key
-- ---------------------------------------------------------------------------
-- The same icon can be named by two different tokens. An equipped trinket is
-- -itemID in the settings store (ResolveCustomActiveKey maps a slot frame to
-- the equipped item so each item tracks separately) and -13/-14 on the slot frame
-- itself. Which token a RULE ends up with depends on whether equipment data was
-- readable at re-arm -- and at login it is not: GetInventoryItemID returns nil, the
-- equipped-trinket skip in Rearm does not fire, and the rule is keyed -itemID while the
-- frame that renders moments later carries -13. Nothing reconciled them, so the rule
-- sat armed against an icon that did not exist for the rest of the session; any
-- settings touch re-armed with equipment present and it started working, which is the
-- "dead until I open the setting again" report.
--
-- Comparing through this map fixes every ordering variant at once, because it
-- resolves at MATCH time (frames render long after equipment is available)
-- rather than at arm time. Kept as a table so the hot loops below cost a
-- lookup rather than an API call per frame per rule.
local _slotItemKey = {}

-- EVERY equipment slot, not just the trinkets. ns.SlotIDFromKey accepts any
-- key in ns.INV_SLOT_NAMES (18 slots), ResolveCustomActiveKey resolves any of
-- them to the equipped item, and the per-spell menu chains per-item settings
-- over any of them -- so an on-use head piece or weapon has the identical
-- two-token problem a trinket does. Driving off the same table the rest of the
-- module uses keeps the two from drifting apart again.
local function RefreshSlotItemKeys()
    wipe(_slotItemKey)
    local slots = mod.INV_SLOT_NAMES
    if not slots then return end
    for slotId in pairs(slots) do
        local ident = GetInventoryItemID and GetInventoryItemID("player", slotId)
        if ident then _slotItemKey[-slotId] = -ident end
    end
end

-- Refreshed lazily while empty (covers the login window, where re-arm ran
-- before equipment was readable) and on every equipment change.
--
-- The throttle matters because an EMPTY map re-reads on EVERY call, and the callers are
-- hot: EvalCdStateNow runs on a 0.12s ticker and asks once per icon per rule.
-- Unthrottled that is a wipe plus a slot sweep hundreds of times a second for as long
-- as the map stays empty. It only ever engages while empty, so a character wearing
-- anything at all never reaches it -- which is also why widening the sweep above
-- shrinks this window to the brief login gap it was written for.
local _slotKeyNextTry = 0
local function KeyMatches(ruleKey, frameKey)
    -- An icon with no resolved identity matches NO rule. fc.spellID is nil for a
    -- window on every rebuild: BuildAllCDMBars clears it on each live icon, and
    -- FullCDMRebuild re-arms (which evaluates every rule) before the reanchor
    -- re-stamps it. Without this guard both lookups below fall through to
    -- nil == nil, so EVERY user rule claimed EVERY identity-less icon and any
    -- Hidden (CD Ready / On CD) rule alpha-0'd unrelated potions and trinkets.
    if ruleKey == nil or frameKey == nil then return false end
    if ruleKey == frameKey then return true end
    if not next(_slotItemKey) then
        local nowTime = GetTime()
        if nowTime >= _slotKeyNextTry then
            _slotKeyNextTry = nowTime + 0.2
            RefreshSlotItemKeys()
        end
    end
    return _slotItemKey[frameKey] == ruleKey or _slotItemKey[ruleKey] == frameKey
end

-- ---------------------------------------------------------------------------
--  Overlay icon: one per underlying icon frame, pooled. Toggled by alpha only.
-- ---------------------------------------------------------------------------
GetOverlay = function(iconBtn)
    local o = _overlays[iconBtn]
    if o then return o end
    o = {}
    local level = (iconBtn:GetFrameLevel() or 0) + 20

    local frame = CreateFrame("Frame", nil, iconBtn)
    frame:SetAllPoints(iconBtn)
    frame:SetFrameLevel(level)
    frame:SetAlpha(0)
    o.frame = frame

    local iconTex = frame:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(frame)
    o.icon = iconTex
    -- Blizzard Style: the copy rounds off with the art it copies (the
    -- viewer's mask on pooled frames, ours on own frames).
    if mod.CdmBlizzIcons and mod.CdmBlizzIcons() and mod.CdmBlizzIconMask then
        local m = mod.CdmBlizzIconMask(iconBtn)
        if m then pcall(iconTex.AddMaskTexture, iconTex, m) end
    end

    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(frame)
    cooldown:SetFrameLevel(level + 1)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(false)
    cooldown:SetSwipeTexture("Interface\\AddOns\\CludesUI\\media\\white-square.png")
    o.cd = cooldown

    -- Own glow frame for ns.ApplyActiveOverlays (never collides with the real
    -- active-state path's fd.glowOverlay).
    local glowOn = CreateFrame("Frame", nil, frame)
    glowOn:SetAllPoints(frame)
    glowOn:SetFrameLevel(level + 4)
    glowOn:SetAlpha(0)
    o.glowOverlay = glowOn

    _overlays[iconBtn] = o
    return o
end

-- ---------------------------------------------------------------------------
--  While an overlay is open it sits ABOVE the underlying icon (so it covers the
--  real icon + its swipe). Temporarily lift the icon's border frame(s) above the
--  overlay so the active swipe never paints over the border; restore on close.
--  "Show Behind" borders (bd.borderBehind) are intentionally behind the icon, so
--  leave those alone.
-- ---------------------------------------------------------------------------
RaiseOverlayBorders = function(iconBtn, o, edge)
    if o._brdRaised then return end
    local level = o.frame:GetFrameLevel() + 2
    local frameData = mod._hookFrameData and mod._hookFrameData[iconBtn]
    local ifc = mod._ecmeFC and mod._ecmeFC[iconBtn]
    if frameData and frameData.borderFrame and not (edge and edge.borderBehind) then
        o._brdSavedLvl = frameData.borderFrame:GetFrameLevel()
        pcall(frameData.borderFrame.SetFrameLevel, frameData.borderFrame, level)
    end
    if ifc and ifc.shapeBorderFrame then
        o._sbSavedLvl = ifc.shapeBorderFrame:GetFrameLevel()
        pcall(ifc.shapeBorderFrame.SetFrameLevel, ifc.shapeBorderFrame, level)
    end
    o._brdRaised = true
end

RestoreOverlayBorders = function(iconBtn, o)
    if not o._brdRaised then return end
    local frameData = mod._hookFrameData and mod._hookFrameData[iconBtn]
    local ifc = mod._ecmeFC and mod._ecmeFC[iconBtn]
    if frameData and frameData.borderFrame and o._brdSavedLvl then
        pcall(frameData.borderFrame.SetFrameLevel, frameData.borderFrame, o._brdSavedLvl)
    end
    if ifc and ifc.shapeBorderFrame and o._sbSavedLvl then
        pcall(ifc.shapeBorderFrame.SetFrameLevel, ifc.shapeBorderFrame, o._sbSavedLvl)
    end
    o._brdSavedLvl, o._sbSavedLvl, o._brdRaised = nil, nil, false
end

-- Active swipe colour: class, custom, or default gold. Drives our own swipe.
ResolveSwipeColor = function(spellSettings)
    local cr, cg, callback
    if spellSettings and spellSettings.activeSwipeClassColor then
        local _, classTok = UnitClass("player")
        if classTok then
            local cc = RAID_CLASS_COLORS[classTok]
            if cc then
                cr, cg, callback = cc.r, cc.g, cc.b
            end
        end
    end
    cr = cr or (spellSettings and spellSettings.activeSwipeR) or 1
    cg = cg or (spellSettings and spellSettings.activeSwipeG) or 0.776
    callback = callback or (spellSettings and spellSettings.activeSwipeB) or 0.376
    local ca = (spellSettings and spellSettings.activeSwipeA) or 0.7
    return cr, cg, callback, ca
end

-- Copy the underlying icon's texture + crop so the overlay looks identical
-- (works for both Blizzard pool frames .Icon and our preset frames ._tex).
IconTexture = function(iconBtn, o, activeRule)
    local source = iconBtn.Icon or iconBtn._tex
    if source and source.GetTexture then
        local t = source:GetTexture()
        if t then
            o.icon:SetTexture(t)
            o.icon:SetTexCoord(source:GetTexCoord())
            return
        end
    end
    if activeRule.spellID and activeRule.spellID > 0 and C_Spell and C_Spell.GetSpellInfo then
        local details = C_Spell.GetSpellInfo(activeRule.spellID)
        o.icon:SetTexture(details and details.iconID)
        o.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Threshold Text block for one rule's overlay countdown. Per-spell Threshold Text covers
-- the ACTIVE STATE countdown as well as cooldown and recharge, but a USER rule's styling
-- block is its customActiveStates entry, which carries threshold keys only when they were
-- set from the preset/custom menu -- a threshold set on the SPELL lives in the family
-- entry and would never reach these overlays. Fall through to the shared resolver, which
-- reads family first then cas. Returns ss untouched when it already arms the feature, and
-- when nobody uses it (session gate), so non-users pay nothing.
local function ThresholdFor(widget, activeRule, spellSettings)
    if (tonumber(spellSettings and spellSettings.thresholdSeconds) or 0) > 0 then return spellSettings end
    if not (mod._cdmAnyThresholdText and mod.ResolveThresholdTextSettings) then return spellSettings end
    local fcT = widget and mod._ecmeFC and mod._ecmeFC[widget]
    local bkT = fcT and fcT.barKey
    return mod.ResolveThresholdTextSettings(
        widget,
        activeRule.spellID,
        bkT and mod.GetBarSpellData and mod.GetBarSpellData(bkT),
        bkT
    )
end

-- The overlay's active glow (drawn on its own glow frame) holds the icon's
-- non-Blackout CD-state glow back, as the native active-state glow does:
-- ns.StartCdGlow reads fd._faActiveGlow from the icon's own frame data. `on`
-- is true only while that glow is lit AND the overlay renders (12.1 slot mode
-- keeps the overlay dark). Edge-gated: the rising edge takes down a CD-state
-- glow on the shared overlay and marks it owed, the falling edge relights it.
local function HoldCdGlow(iconBtn, enabled)
    local frameData = mod._hookFrameData and mod._hookFrameData[iconBtn]
    if not frameData or (frameData._faActiveGlow or false) == enabled then return end
    frameData._faActiveGlow = enabled or nil
    if enabled then
        -- A lit Blackout owns the memo (the active glow never holds it
        -- back): never clear the memo out from under it.
        local go = frameData.glowOverlay
        local bo = frameData.blackoutOverlay
        if
            go
            and go._glowActive
            and (frameData._cdStateGlowOn or frameData._presetCdGlowOn)
            and not (frameData.procGlowActive or frameData._activeGlowOn)
            and not (bo and bo._glowActive)
        then
            mod.StopNativeGlow(go)
            frameData._cdStateGlowOn = false
            frameData._presetCdGlowOn = false
            frameData._cdGlowOwed = true
        end
    elseif frameData._cdGlowOwed then
        mod.CdGlowKick(iconBtn)
    end
end

-- ---------------------------------------------------------------------------
--  Show / hide the overlay on a single icon frame.
-- ---------------------------------------------------------------------------
ApplyToFrame = function(iconBtn, activeRule, window)
    local o = GetOverlay(iconBtn)
    -- Bar data + per-spell settings. User rules carry their own styling entry
    -- (profile-level, travels with the spell); built-in rules (e.g. Ebon Might)
    -- read the bar's per-spell settings. barData is needed either way for the
    -- overlay's shape geometry, so resolve it unconditionally.
    local frameCache = mod._ecmeFC and mod._ecmeFC[iconBtn]
    local barId = frameCache and frameCache.barKey
    local edge = barId and mod.barDataByKey and mod.barDataByKey[barId]
    local spellSettings = activeRule.cas
    if not spellSettings then
        local sd = barId and mod.GetBarSpellData and mod.GetBarSpellData(barId)
        if mod.ResolveSpellSettings then
            spellSettings = mod.ResolveSpellSettings(iconBtn, activeRule.spellID, sd, barId)
        end
    end

    -- "Hide Active State" dropdown -> never show the overlay.
    local isHidden = spellSettings and spellSettings.activeSwipeMode == "none"

    if window and not isHidden then
        o._rule = activeRule -- remembered so a live restyle can re-sync this overlay
        IconTexture(iconBtn, o, activeRule)
        -- Mirror the underlying icon's custom shape onto our overlay so a shaped
        -- icon stays shaped (mask + swipe), then lift the border above us.
        if mod.ApplyShapeToOverlay then mod.ApplyShapeToOverlay(iconBtn, o.icon, o.cd, edge) end
        RaiseOverlayBorders(iconBtn, o, edge)
        o.icon:SetDesaturated(false)
        local cr, cg, callback, ca = ResolveSwipeColor(spellSettings)
        o.cd:SetSwipeColor(cr, cg, callback, ca)
        -- Per-spell Reverse Swipe: flip our active swipe's fill direction, the
        -- same setting the underlying icon honors (ss covers both sources: the
        -- resolved per-spell block for built-in rules, the customActiveStates
        -- entry for user rules). Gated by the session flag so it stays zero
        -- cost for anyone who never enables it; the flag is monotonic, so a
        -- toggle-off still passes through here and resets the pooled overlay.
        if mod._cdmAnyReverseSwipe then
            o.cd:SetReverse((spellSettings and spellSettings.reverseSwipe) and true or false)
        end
        o.cd:SetCooldown(window.start, window.dur)
        o._ss = spellSettings
        -- Match the icon's Duration Text settings on our own countdown number;
        -- otherwise it renders in Blizzard's default font.
        if mod.StyleOverlayCooldownText then
            mod.StyleOverlayCooldownText(o.cd, edge, spellSettings, iconBtn:GetScale())
        end
        -- Per-spell Threshold Text: the overlay countdown renders through the
        -- engine formatter (decimals / color change below the spell's Threshold
        -- Seconds). ss is the same block the swipe styling reads -- the user
        -- rule's customActiveStates entry, or the resolved per-spell settings
        -- for built-in rules. Gated = zero cost when unused; the apply helper
        -- only touches widgets it manages, and StyleOverlayCooldownText (above)
        -- already set the countdown numbers per the Duration Text state.
        if mod._cdmAnyThresholdText and mod.ApplyThresholdFormatter then
            mod.ApplyThresholdFormatter(o.cd, ThresholdFor(iconBtn, activeRule, spellSettings))
        end
        -- Feed the active glow + border the underlying icon's shape / border so
        -- Shape Glow masks to the shape (it reads the shape from its glow frame's
        -- parent FC) and Active Border can recolour the real (now-raised) border.
        local ufd = mod._hookFrameData and mod._hookFrameData[iconBtn]
        local uifc = mod._ecmeFC and mod._ecmeFC[iconBtn]
        o.borderFrame = (ufd and ufd.borderFrame) or nil
        local gfc = mod.FC and mod.FC(o.frame)
        if gfc then
            gfc.shapeApplied = (uifc and uifc.shapeApplied) or nil
            gfc.shapeName = (uifc and uifc.shapeName) or nil
            gfc.shapeMask = (uifc and uifc.shapeMask) or nil
            gfc.shapeBorder = (uifc and uifc.shapeBorder) or nil
        end
        if mod.ApplyActiveOverlays then mod.ApplyActiveOverlays(o.frame, o, spellSettings, true, edge) end
        local slotMode = (window.fa121 and FA121) and true or false
        if slotMode then
            -- 12.1 slot mode: the slot subtree renders the active display;
            -- Attach positions it and parks this legacy overlay at alpha 0.
            FA121.Attach(iconBtn, o, activeRule, spellSettings, edge)
        else
            o.frame:SetAlpha(1)
        end
        HoldCdGlow(iconBtn, o._activeGlowOn == true and not slotMode)
    else
        o._rule = nil
        o._ss = nil
        RestoreOverlayBorders(iconBtn, o)
        if mod.ApplyActiveOverlays then mod.ApplyActiveOverlays(o.frame, o, spellSettings, false, edge) end
        HoldCdGlow(iconBtn, false)
        o.cd:Clear()
        o.frame:SetAlpha(0)
        if FA121 then FA121.Detach(o) end
    end
end

-- User active states belong only to frames we inject. Removing a custom spell
-- clears its customSpellIDs tag but preserves its profile-level settings for
-- moves between bars. Those settings must not decorate a native viewer icon
-- when the spell is later added through normal CDM tracking.
local function IsInjectedFrame(frame)
    if
        frame._isCustomSpellFrame
        or frame._isRacialFrame
        or frame._isPresetFrame
        or frame._isItemPresetFrame
        or frame._isTrinketFrame
    then
        return true
    end
    -- Blizzard's own potion / healthstone row claimed under an item preset key
    -- (CUI_CDM_HookReanchor.lua, Phase 1) renders as that preset: its settings
    -- are the preset menu's, like a racial Blizzard tracks natively.
    local frameCache = mod._ecmeFC and mod._ecmeFC[frame]
    return mod.IsItemPresetKey(frameCache and frameCache.spellID)
end
mod.CdmIsInjectedFrame = IsInjectedFrame

-- BUILT-IN rules only ever target native viewer entries, so they only match
-- icons on the three native bars. Guards against a stale cached spellID on a
-- Blizzard-pool-reused icon frame matching a custom bar it never belonged to
-- (field: Ebon Might's built-in overlay painting a custom-bar potion slot
-- after icon-size/glow adjustments forced frame reuse). USER rules are
-- deliberately NOT scoped: they are barKey-less by design and follow the
-- injected spell to whichever bar hosts it (see the AddUserRule contract below).
-- Restrict their frame kind, not their bar, so native icons cannot inherit an
-- orphaned custom timer while custom-bar presets keep their active states.
local NATIVE_VIEWER_BARKEYS = { cooldowns = true, utility = true, buffs = true }

-- Apply (or clear) a rule on every matching live icon. A rule with .barKey
-- only matches icons on that bar; a user rule matches any bar; a built-in
-- rule matches native viewer bars only.
ApplyRule = function(activeRule, window)
    local icons = mod.cdmBarIcons
    local FCt = mod._ecmeFC
    if not icons or not FCt then return end
    local spellRef = activeRule.spellID
    for _, entries in pairs(icons) do
        for index = 1, #entries do
            local frame = entries[index]
            local frameCache = frame and FCt[frame]
            local barScopeOK
            if activeRule.barKey then
                barScopeOK = frameCache and frameCache.barKey == activeRule.barKey
            elseif activeRule.user then
                barScopeOK = frameCache ~= nil and IsInjectedFrame(frame)
            else
                barScopeOK = frameCache and frameCache.barKey and NATIVE_VIEWER_BARKEYS[frameCache.barKey]
            end
            if barScopeOK and KeyMatches(spellRef, frameCache.spellID) then
                ApplyToFrame(frame, activeRule, window)
                if mod._fakeActiveDebug then
                    print(
                        ("|cff4cc9f0CUI FakeActive|r %s sid=%s"):format(
                            window and "ON " or "off",
                            tostring(spellRef)
                        )
                    )
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
--  FA121 (12.1 only; see the declaration comment near the top). One state
--  entry per aura rule: { proxy, container, btn, cd, built, queued, armed,
--  o, iconFrame }. The container is built ONCE per rule through the AuraKit
--  scheduler (container shells are OOC-only; a job queued in combat holds to
--  regen) and parked by hiding the proxy -- a hidden container fully
--  unregisters its events, so the parked state costs nothing.
-- ---------------------------------------------------------------------------
FA121 = { byRule = {} }
local FA121_WIN = { fa121 = true, start = 0, dur = 0, expiry = 0 }

local function St(activeRule)
    local state = FA121.byRule[activeRule]
    if not state then
        state = {}
        FA121.byRule[activeRule] = state
    end
    return state
end

-- NO Lua presence signal exists: the button AND every child created in its creation
-- window are denied to addon code afterward (field-mapped 2026-07-22 -- reads and
-- writes both). The design therefore keeps the entire active display INSIDE the
-- slot subtree, engine-driven end to end: visibility (button shown only while the
-- aura is up), icon (SetIcon) and swipe (SetDurationCooldown) all render without
-- any addon code running. The legacy overlay (o.frame) stays alpha 0 on
-- 12.1 -- it exists only so RaiseOverlayBorders and settings plumbing
-- keep working through the shared ApplyToFrame path.

function FA121.Attach(iconBtn, o, activeRule, spellSettings, edge)
    local state = St(activeRule)
    state.o, state.iconFrame = o, iconBtn
    if not state.built then
        -- Slot not built yet (queued; held to regen when queued in
        -- combat): stay dark until the build tail re-arms.
        o.frame:SetAlpha(0)
        return
    end
    -- Repositioning is ALWAYS a proxy move: the slot button anchored
    -- SetAllPoints(proxy) once in its creation window, and the proxy is our frame
    -- -- legal any time, icon churn included. Parent to the ICON FRAME, never to
    -- o.frame: the legacy overlay is held at alpha 0 on 12.1 and children inherit
    -- EFFECTIVE alpha -- a proxy under o.frame renders the whole engine subtree
    -- invisible (field-hit 2026-07-22: everything worked, at alpha 0).
    state.proxy:SetParent(iconBtn)
    state.proxy:ClearAllPoints()
    state.proxy:SetAllPoints(iconBtn)
    state.proxy:Show()
    -- One container-level set lifts the whole engine subtree (buttons
    -- keep relative levels), seating the swipe in the overlay band.
    state.container:SetFrameLevel(o.frame:GetFrameLevel() + 1)
    -- Best-effort live restyle of the engine-bound cooldown. FIELD
    -- LESSON (68824): SetDurationCooldown takes ownership -- touching
    -- the region outside the creation window is forbidden-object
    -- access, so the cooldown was fully styled at build time and this
    -- block is optional polish: attempted once, abandoned on denial.
    if state.cd and not state.cdLocked then
        local ok = pcall(state.cd.SetSwipeColor, state.cd, ResolveSwipeColor(spellSettings))
        if ok then
            if mod._cdmAnyReverseSwipe then
                pcall(
                    state.cd.SetReverse,
                    state.cd,
                    (spellSettings and spellSettings.reverseSwipe) and true or false
                )
            end
            if mod.ApplyShapeToOverlay then
                pcall(mod.ApplyShapeToOverlay, iconBtn, o.icon, state.cd, edge)
            end
            if mod.StyleOverlayCooldownText then
                pcall(mod.StyleOverlayCooldownText, state.cd, edge, spellSettings, iconBtn:GetScale())
            end
            if mod._cdmAnyThresholdText and mod.ApplyThresholdFormatter then
                pcall(mod.ApplyThresholdFormatter, state.cd, ThresholdFor(iconBtn, activeRule, spellSettings))
            end
        else
            state.cdLocked = true
            if mod._fakeActiveDebug then
                print("|cff4cc9f0CUI FakeActive|r fa121 cd engine-locked (build-time styling only)")
            end
        end
    end
    -- The legacy overlay never renders on 12.1 (the slot subtree IS the
    -- active display); keep it dark regardless of what earlier paths
    -- set. Plain write -- always legal on our frame.
    o.frame:SetAlpha(0)
end

-- Close-branch handoff from ApplyToFrame: park the proxy so the engine
-- subtree renders nothing (covers rule unarm AND "Hide Active State").
function FA121.Detach(o)
    for _, state in pairs(FA121.byRule) do
        if state.o == o then
            state.o, state.iconFrame = nil, nil
            if state.proxy then state.proxy:Hide() end
        end
    end
end

local function Build(activeRule, state)
    local AK = CludesUI.AuraKit
    if state.built or not AK then return end
    AK.styles["cdm:fa121"] = AK.styles["cdm:fa121"] or { noRegions = true, width = 1, height = 1 }
    if not state.proxy then
        state.proxy = CreateFrame("Frame", nil, UIParent)
        state.proxy:Hide()
    end
    -- Resolve the rule's styling NOW (build runs at rearm time, when the
    -- icon usually exists) so the slot cooldown can be styled INSIDE the
    -- creation window. FIELD LESSON (68824): a region handed to an
    -- engine binding (SetDurationCooldown) is forbidden to addon code
    -- after initializeFrame returns -- even out of combat -- so
    -- creation-window styling is the only guaranteed styling.
    local spellSettings, edge, scale = nil, nil, 1
    do
        local icons, FCt = mod.cdmBarIcons, mod._ecmeFC
        if icons and FCt then
            for _, entries in pairs(icons) do
                for index = 1, #entries do
                    local frame = entries[index]
                    local frameCache = frame and FCt[frame]
                    -- Native-bars-only, same scope as ApplyRule's built-in
                    -- arm: this walk only ever runs for built-in engine-slot
                    -- rules, and a stale cached spellID on a reused custom-
                    -- bar frame must not donate srcFrame/crop/styling here.
                    if
                        frameCache
                        and frameCache.barKey
                        and NATIVE_VIEWER_BARKEYS[frameCache.barKey]
                        and KeyMatches(activeRule.spellID, frameCache.spellID)
                    then
                        local barId = frameCache.barKey
                        edge = barId and mod.barDataByKey and mod.barDataByKey[barId]
                        spellSettings = activeRule.cas
                        if not spellSettings and mod.ResolveSpellSettings then
                            local sd = barId and mod.GetBarSpellData and mod.GetBarSpellData(barId)
                            spellSettings = mod.ResolveSpellSettings(frame, activeRule.spellID, sd, barId)
                        end
                        scale = frame:GetScale() or 1
                        -- Bake the underlying icon's crop for the engine
                        -- icon (and remember the frame for shape masks).
                        state.srcFrame = frame
                        local source = frame.Icon or frame._tex
                        if source and source.GetTexCoord then
                            local ok, a1, a2, a3, a4, a5, a6, a7, a8 = pcall(source.GetTexCoord, source)
                            if ok and a1 then state.srcCoords = { a1, a2, a3, a4, a5, a6, a7, a8 } end
                        end
                        break
                    end
                end
                if spellSettings or edge then break end
            end
        end
    end
    -- No icon found = CDM bars not built yet (login race) OR the spell
    -- is not on any bar. Do NOT build: every baked decision (the text gate, fonts,
    -- swipe color, crop) resolved nil and would be wrong for the whole session
    -- (built latches). The rescan retries re-queue the build; once the icon exists,
    -- everything bakes from real settings. Field-hit as "swipe works, no text" in
    -- sessions where the build outran bar construction.
    if not state.srcFrame then return end
    local boxHolder = AK.CreateContainerShell(state.proxy, { point = { "CENTER" } })
    AK.AddSlotToContainer(boxHolder, {
        key = "fa",
        filter = { "HELPFUL" },
        -- Helpful spellID includes on the player pass the identity gate
        -- regardless of the spell's secrecy flag.
        candidateFilters = { includeSpellIDs = { [activeRule.auraSpellID] = true } },
        style = "cdm:fa121",
        extraInit = function(btnFrame)
            -- Creation window: the only legal moment for button-level wiring AND
            -- (per the field lessons above) the only reliable window for touching
            -- ANYTHING in this subtree -- post-window reads AND writes on the
            -- button and its children are denied. Therefore the subtree is entirely
            -- self-sufficient: the ENGINE drives visibility (button shown only
            -- while the aura is up), the icon (SetIcon binds the aura's own
            -- texture) and the swipe (SetDurationCooldown from the real duration
            -- object, extensions included). No Lua signal, no slave. Two-point
            -- anchoring sizes the button by anchors forever.
            btnFrame:SetAllPoints(state.proxy)
            if btnFrame.SetMouseMotionEnabled then btnFrame:SetMouseMotionEnabled(false) end
            -- Saturated icon: engine-bound, engine-shown. Zoom baked
            -- from the underlying CDM icon when it existed at build.
            local texture = btnFrame:CreateTexture(nil, "ARTWORK")
            texture:SetAllPoints(btnFrame)
            if state.srcCoords then
                -- 8-value corner form, straight from the source icon.
                texture:SetTexCoord(unpack(state.srcCoords))
            else
                texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            local cooldown = CreateFrame("Cooldown", nil, btnFrame, "CooldownFrameTemplate")
            cooldown:SetAllPoints(btnFrame)
            cooldown:SetDrawEdge(false)
            cooldown:SetDrawBling(false)
            cooldown:SetHideCountdownNumbers(false)
            cooldown:SetSwipeTexture("Interface\\AddOns\\CludesUI\\media\\white-square.png")
            cooldown:SetFrameLevel(btnFrame:GetFrameLevel() + 1)
            local cr, cg, callback, ca = ResolveSwipeColor(spellSettings)
            cooldown:SetSwipeColor(cr, cg, callback, ca)
            if spellSettings and spellSettings.reverseSwipe then cooldown:SetReverse(true) end
            if mod.StyleOverlayCooldownText then
                pcall(mod.StyleOverlayCooldownText, cooldown, edge, spellSettings, scale)
            end
            if mod.ApplyThresholdFormatter then
                -- Resolve INSIDE the protection: an argument expression evaluates before pcall
                -- is entered, and a throw in this creation window takes the whole slot down
                -- (its swipe with it), not just the countdown text.
                local okT, ttB = pcall(ThresholdFor, state.srcFrame, activeRule, spellSettings)
                pcall(mod.ApplyThresholdFormatter, cooldown, okT and ttB or spellSettings)
            end
            if mod.ApplyShapeToOverlay and state.srcFrame then
                pcall(mod.ApplyShapeToOverlay, state.srcFrame, texture, cooldown, edge)
            end
            -- Duration text: engine-bound cooldowns render NO widget countdown
            -- (time display belongs to the SetDurationText binding -- the AuraKit
            -- rule), so register a dedicated FontString styled like the icon's
            -- cooldown text. Only when the resolved cooldown-text setting is on:
            -- the engine SetText()s every REGISTERED string, and a no-text config
            -- should carry no binding at all. Fonted BEFORE registration (an
            -- unfonted registered FS hard-errors inside the engine).
            local showCD = mod.CdmDurationTextOn(edge)
            if spellSettings and spellSettings.showCooldownText ~= nil then
                showCD = spellSettings.showCooldownText
            end
            if showCD then
                -- ARMORED: an uncaught error inside initializeFrame aborts the
                -- engine's whole CreateFrameBatch and kills the slot declaration
                -- (and every declaration after it). Text is optional polish -- it
                -- must never take the swipe down with it. Failures land in
                -- st.fsErr for the debug dump.
                local okFS, errFS = pcall(function()
                    -- Text CARRIER above the cooldown: regions created
                    -- on a Cooldown render UNDER its swipe (the classic
                    -- gotcha -- field-hit here as "healthy dump, no
                    -- text"). Same pattern as AuraKit's stackCarrier.
                    local tc = CreateFrame("Frame", nil, btnFrame)
                    tc:SetAllPoints(btnFrame)
                    tc:SetFrameLevel(cooldown:GetFrameLevel() + 5)
                    local fontStr = tc:CreateFontString(nil, "OVERLAY")
                    local cdFont = (CludesUI.GetFontPath("cdm"))
                        or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
                    local fsScale = (scale and scale > 0.01) and scale or 1
                    local cdSize = (
                        (spellSettings and spellSettings.cooldownFontSize)
                        or (edge and edge.cooldownFontSize)
                        or 12
                    ) / fsScale
                    if CludesUI.ApplyIconTextFont then
                        CludesUI.ApplyIconTextFont(fontStr, cdFont, cdSize, "cdm")
                    else
                        fontStr:SetFont(cdFont, cdSize, "OUTLINE")
                    end
                    fontStr:SetTextColor(
                        (spellSettings and spellSettings.cooldownTextR) or (edge and edge.cooldownTextR) or 1,
                        (spellSettings and spellSettings.cooldownTextG) or (edge and edge.cooldownTextG) or 1,
                        (spellSettings and spellSettings.cooldownTextB) or (edge and edge.cooldownTextB) or 1
                    )
                    mod.AnchorCooldownText(
                        fontStr,
                        cooldown,
                        (spellSettings and spellSettings.cooldownTextPosition)
                            or (edge and edge.cooldownTextPosition)
                            or "center",
                        (spellSettings and spellSettings.cooldownTextX) or (edge and edge.cooldownTextX) or 0,
                        (spellSettings and spellSettings.cooldownTextY) or (edge and edge.cooldownTextY) or 0
                    )
                    local AK2 = CludesUI.AuraKit
                    local fmt = AK2 and AK2.GetDurationFormatter and AK2.GetDurationFormatter()
                    -- 68914 schema key (textFormatter); BuildDurationTextOpts
                    -- when available, bare table fallback otherwise.
                    local options
                    if AK2 and AK2.BuildDurationTextOpts then
                        options = AK2.BuildDurationTextOpts(fmt)
                    else
                        options = { textFormatter = fmt }
                    end
                    if AK2 and AK2.SetDurationTextSafe then
                        AK2.SetDurationTextSafe(btnFrame, fontStr, options)
                    else
                        btnFrame:SetDurationText(fontStr, options)
                    end
                end)
                if not okFS then state.fsErr = errFS end
            end
            btnFrame:SetIcon(texture)
            btnFrame:SetDurationCooldown(cooldown)
            state.btn, state.cd = btnFrame, cooldown
        end,
    })
    AK.FinishContainer(boxHolder, "player")
    state.container = boxHolder
    state.built = true
end

local function EnsureBuilt(activeRule)
    local state = St(activeRule)
    if state.built or state.queued then return end
    local AK = CludesUI.AuraKit
    if not (AK and AK.QueueBuildJob) then return end
    state.queued = true
    AKWorker:Queue(function()
        state.queued = nil
        Build(activeRule, state)
        -- Rescan ONLY after a build that actually completed (it attaches
        -- the fresh slot to the live icon). A BAILED build (icon not on
        -- any bar yet -- or ever) must NOT rescan from its own job tail:
        -- Rescan re-queues the build for unbuilt armed rules, so the tail
        -- call turned every permanent bail into a self-feeding job loop
        -- that burned the scheduler's full per-frame budget forever
        -- (field: Aug Evoker Ebon Might rule = 50% idle CPU + login and
        -- post-combat turbo-window FPS drops). Bailed builds retry on
        -- the EXTERNAL staggered rescans (PEW/rearm + 3s/8s), which are
        -- finite by design.
        if state.armed and state.built then FA121.Rescan() end
    end, "cdm:fa121-shell")
end

function FA121.Rescan()
    for activeRule, state in pairs(FA121.byRule) do
        if state.armed then
            -- A build that bailed (icon not yet created) retries here;
            -- EnsureBuilt's queued flag dedupes in-flight jobs.
            if not state.built then EnsureBuilt(activeRule) end
            ApplyRule(activeRule, FA121_WIN)
        end
    end
end

local function AnyArmed()
    for _, state in pairs(FA121.byRule) do
        if state.armed then return true end
    end
    return false
end

-- Rearm integration: BeginSweep marks every entry unwanted, Want re-marks
-- (and builds) the rules the new spec keeps, EndSweep parks the rest and
-- re-arms the wanted ones. The delayed rescan mirrors InitialStamp's 3s
-- login retry, which never covers slot rules (they are not in _rules).
function FA121.BeginSweep()
    for _, state in pairs(FA121.byRule) do
        state.armed = nil
    end
end

function FA121.Want(activeRule)
    local state = St(activeRule)
    state.armed = true
    EnsureBuilt(activeRule)
end

function FA121.EndSweep()
    for activeRule, state in pairs(FA121.byRule) do
        if not state.armed then
            ApplyRule(activeRule, nil)
            if state.proxy then state.proxy:Hide() end
            state.o, state.iconFrame = nil, nil
        end
    end
    if AnyArmed() then
        FA121.Rescan()
        if C_Timer then
            C_Timer.After(3, FA121.Rescan)
            C_Timer.After(8, FA121.Rescan)
        end
    end
end

-- Login/zone robustness: CDM icon frames can materialize AFTER the last
-- rearm's rescans (deferred reanchor queues) -- a missed attach leaves
-- the proxy parked and nothing renders all session (the field-observed
-- working/dark flip-flop across identical reloads). World entry re-scans
-- with staggered retries; Rescan is idempotent and armed-guarded, so
-- quiet sessions cost three no-op walks of a one-entry table.
local pew = mod.TakeShell()
pew:RegisterEvent("PLAYER_ENTERING_WORLD")
-- Cinematics fire UNIT_FACTION for the player and briefly drop
-- assistability, which disables the slot's spell-ID candidate filter
-- engine-side -- the fa121 slot then renders the FIRST helpful aura
-- instead of the rule's, and no aura edge is guaranteed to follow the
-- restore. Reparse armed built slots on that edge (typically one slot).
pew:RegisterUnitEvent("UNIT_FACTION", "player")
pew:SetScript("OnEvent", function(_, evt)
    if evt == "UNIT_FACTION" then
        for _, state in pairs(FA121.byRule) do
            if state.armed and state.built and state.container then state.container:UpdateAllAuras() end
        end
        return
    end
    FA121.Rescan()
    if C_Timer then
        C_Timer.After(3, FA121.Rescan)
        C_Timer.After(8, FA121.Rescan)
    end
end)

-- ---------------------------------------------------------------------------
--  Expiry ticker (self-hides when idle).
-- ---------------------------------------------------------------------------
EnsureTicker = function()
    if not _ticker then
        _ticker = CreateFrame("Frame")
        _ticker:Hide()
        _ticker._acc = 0
        _ticker:SetScript("OnUpdate", function(self, elapsed)
            self._acc = self._acc + elapsed
            if self._acc < 0.1 then return end
            self._acc = 0
            local nowTime = GetTime()
            local anyOpen = false
            for index = 1, #_rules do
                local activeRule = _rules[index]
                local window = _windows[activeRule]
                if window then
                    if nowTime >= window.expiry then
                        CloseWindow(activeRule)
                    else
                        anyOpen = true
                    end
                end
            end
            if not anyOpen then self:Hide() end
        end)
    end
    _ticker:Show()
end

OpenWindow = function(activeRule, window)
    _windows[activeRule] = window
    ApplyRule(activeRule, window)
    EnsureTicker()
end

CloseWindow = function(activeRule)
    _windows[activeRule] = nil
    ApplyRule(activeRule, nil)
end

CloseAll = function()
    for index = 1, #_rules do
        local activeRule = _rules[index]
        if _windows[activeRule] ~= nil then
            _windows[activeRule] = nil
            ApplyRule(activeRule, nil)
        end
    end
    if _ticker then _ticker:Hide() end
end

CastWindow = function(activeRule)
    local nowTime = GetTime()
    local duration = activeRule.duration or 0
    if duration <= 0 then return nil end
    return { start = nowTime, dur = duration, expiry = nowTime + duration }
end

-- ---------------------------------------------------------------------------
--  Trigger evaluators
-- ---------------------------------------------------------------------------
OpenFromAura = function(activeRule)
    local auraInfo = GetPlayerAuraBySpellID and GetPlayerAuraBySpellID(activeRule.auraSpellID)
    if auraInfo and auraInfo.expirationTime and auraInfo.expirationTime > 0 then
        local expiresAt = auraInfo.expirationTime
        local duration = auraInfo.duration
        if not duration or duration <= 0 then duration = activeRule.duration or (expiresAt - GetTime()) end
        OpenWindow(activeRule, { start = expiresAt - duration, dur = duration, expiry = expiresAt })
    elseif _windows[activeRule] ~= nil then
        CloseWindow(activeRule)
    end
end

EvalCustom = function(activeRule)
    _api.now = GetTime()
    _api.lastCast = _lastCast
    _api.GetPlayerAura = GetPlayerAuraBySpellID
    local ok, region = pcall(activeRule.trigger, _api)
    if not ok then return end
    local nowTime = GetTime()
    local window
    if region == true then
        local duration = activeRule.duration or 0
        if duration > 0 then window = { start = nowTime, dur = duration, expiry = nowTime + duration } end
    elseif type(region) == "number" and region > nowTime then
        local duration = activeRule.duration or (region - nowTime)
        window = { start = region - duration, dur = duration, expiry = region }
    end
    if window then
        OpenWindow(activeRule, window)
    elseif _windows[activeRule] ~= nil then
        CloseWindow(activeRule)
    end
end

InitialStamp = function()
    for index = 1, #_auraRules do
        OpenFromAura(_auraRules[index])
    end
    for index = 1, #_customRules do
        EvalCustom(_customRules[index])
    end
end

-- updateInfo: UNIT_AURA's payload (UNIT_SPELLCAST_SUCCEEDED's cast GUID, unused);
-- ITEM_DATA_LOAD_RESULT brings the item ID in unit and the success flag in updateInfo
OnEvent = function(self, evt, unitToken, updateInfo, spellId)
    if evt == "UNIT_AURA" then
        -- Registered for aura rules, or for form rules: a powershift's return,
        -- and the exception auras a form rule can hang on
        if _needAura then
            for index = 1, #_auraRules do
                OpenFromAura(_auraRules[index])
            end
            for index = 1, #_customRules do
                EvalCustom(_customRules[index])
            end
        end
        if _needForms then
            local form = mod.CdmCurrentFormID()
            if form ~= _formSeen then
                _formSeen = form
                mod.CdmRetryUnreadForms()
                QueueCdStateEval()
            elseif _needFormAuras and mod.CdmFormAuraEdge(updateInfo, "preset") then
                QueueFormAuraEval()
            end
        end
    elseif evt == "ITEM_DATA_LOAD_RESULT" then
        RetryPendingCasts(unitToken, updateInfo)
    elseif evt == "UNIT_SPELLCAST_SUCCEEDED" then
        _lastCast = spellId
        local hits = spellId and _castMap[spellId]
        if hits then
            for index = 1, #hits do
                local window = CastWindow(hits[index])
                if window then OpenWindow(hits[index], window) end
            end
        end
        for index = 1, #_customRules do
            EvalCustom(_customRules[index])
        end
    elseif evt == "PLAYER_EQUIPMENT_CHANGED" then
        -- The key map covers every equipment slot, so ANY swap can stale it --
        -- refresh unconditionally. It is a wipe plus one lookup per slot on an
        -- event that fires only when gear actually changes.
        RefreshSlotItemKeys()
        -- Gear changed: one re-evaluation so a swapped-in mid-cooldown item
        -- paints its cd-state (trinket slots re-arm below, which also evals).
        QueueCdStateEval()
        -- Re-arm stays TRINKET-ONLY on purpose. A trinket swap re-points a slot's
        -- settings to a different item, so the slot must pick up the newly-equipped
        -- trinket's rule (or none). Re-arming on every gear change would tear down and
        -- rebuild the whole rule set mid-gearing for no benefit -- the refreshed map
        -- above already keeps matching correct for the other slots.
        if unitToken == 13 or unitToken == 14 then mod.FakeActive_Rearm() end
    elseif evt == "UPDATE_BONUS_ACTIONBAR" or evt == "UPDATE_STEALTH" then
        -- A Stance Bar edge.
        QueueCdStateEval()
    elseif
        evt == "PLAYER_REGEN_ENABLED"
        or evt == "SPELL_UPDATE_USABLE"
        or evt == "UPDATE_SHAPESHIFT_FORM"
    then
        -- Combat end: cooldown reads were secret-dropped during combat, so any
        -- fail-open cd-state paint corrects on this first plain re-read.
        -- SPELL_UPDATE_USABLE: a Hidden Until Usable proc edge.
        -- UPDATE_SHAPESHIFT_FORM: a Hidden Outside Form/Stance edge; it and
        -- combat end also retry form answers that could not be read.
        if _needForms and evt ~= "SPELL_UPDATE_USABLE" then
            mod.CdmRetryUnreadForms()
            if evt == "UPDATE_SHAPESHIFT_FORM" then _formSeen = mod.CdmCurrentFormID() end
        end
        QueueCdStateEval()
    end
end

UpdateListeners = function()
    if _needAura or _needCast or _hasUserRules then
        if not _events then
            _events = CreateFrame("Frame")
            _events:SetScript("OnEvent", OnEvent)
        end
        if _needAura or _needForms then
            _events:RegisterUnitEvent("UNIT_AURA", "player")
        else
            _events:UnregisterEvent("UNIT_AURA")
        end
        if _needCast then
            _events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        else
            _events:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        end
        if next(_pendingCastRules) then
            _events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        else
            _events:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
        end
        if _needForms then
            _events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        else
            _events:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
        end
        if _needStance then
            _events:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
            _events:RegisterEvent("UPDATE_STEALTH")
        else
            _events:UnregisterEvent("UPDATE_BONUS_ACTIONBAR")
            _events:UnregisterEvent("UPDATE_STEALTH")
        end
        -- Combat end re-syncs cd-state once: cooldown reads secret-drop during
        -- combat, so the first plain read corrects anything painted fail-open.
        if #_cdStateRules > 0 then
            _events:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            _events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
        if _needUsable then
            _events:RegisterEvent("SPELL_UPDATE_USABLE")
        else
            _events:UnregisterEvent("SPELL_UPDATE_USABLE")
        end
        -- Trinket swaps only matter when the player actually uses custom states.
        if _hasUserRules then
            _events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        else
            _events:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
        end
    elseif _events then
        _events:UnregisterAllEvents()
    end
end

-- Item ID -> the cast spell IDs the consumables catalogue knows ahead
-- (CludesUI.CONSUMABLES spellIDs, the IDs the Tracking Bars potion presets
-- trigger on too), so a potion or healthstone rule maps before its item data
-- has loaded.
local _knownItemCasts
local function KnownItemCasts(itemId)
    if not _knownItemCasts then
        local families = CludesUI.CONSUMABLES
        _knownItemCasts = {}
        -- A family's own item wins over another family's alternate: 224464 is
        -- the Demonic Healthstone, also listed as a Healthstone alternate.
        for _, family in pairs(families) do
            if family.spellIDs then _knownItemCasts[family.itemID] = family.spellIDs end
        end
        for _, family in pairs(families) do
            if family.spellIDs then
                for _, ident in ipairs(family.altItemIDs or {}) do
                    if not _knownItemCasts[ident] then _knownItemCasts[ident] = family.spellIDs end
                end
            end
        end
    end
    return _knownItemCasts[itemId]
end

-- Spell ids whose successful cast should open a rule's window. For positive
-- keys: the spell (and its live override). For negative keys (item presets):
-- the item's on-use spell and the cast IDs known ahead for it. -13 / -14 are
-- the equipped trinket slots. An item key also returns the items whose on-use
-- spell cannot be read yet ({ itemID = true }: data not loaded).
ResolveCastSpells = function(ruleKey)
    local result, waiting = {}, nil
    if ruleKey > 0 then
        result[#result + 1] = ruleKey
        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            local shade = C_SpellBook.FindSpellOverrideByID(ruleKey)
            if shade and shade > 0 and shade ~= ruleKey then result[#result + 1] = shade end
        end
    else
        waiting = {}
        local seen = {}
        local function ItemSpell(itemId)
            local known = KnownItemCasts(itemId)
            if known then
                for _, spellId in ipairs(known) do
                    if not seen[spellId] then
                        seen[spellId] = true
                        result[#result + 1] = spellId
                    end
                end
            end
            local _, spellId = C_Item.GetItemSpell(itemId)
            if spellId then
                if not seen[spellId] then
                    seen[spellId] = true
                    result[#result + 1] = spellId
                end
            elseif
                not known
                and not _settledCastItems[itemId]
                and C_Item.IsItemDataCachedByID
                and not C_Item.IsItemDataCachedByID(itemId)
            then
                waiting[itemId] = true
            end
        end
        local itemId
        local slotId = mod.SlotIDFromKey and mod.SlotIDFromKey(ruleKey)
        if slotId then
            itemId = GetInventoryItemID and GetInventoryItemID("player", slotId)
        else
            itemId = -ruleKey
        end
        if itemId and C_Item and C_Item.GetItemSpell then
            -- Pot presets: map EVERY variant's on-use spell so drinking any
            -- rank / Fleeting / (swap toggle on) other-family pot opens the
            -- window, not just the primary item. Different variants can share
            -- an on-use spell, hence the dedupe.
            local chain = mod.GetPresetPotChain and mod.GetPresetPotChain(itemId)
            if chain then
                for index = 1, #chain do
                    ItemSpell(chain[index])
                end
            else
                ItemSpell(itemId)
                -- Other family presets (primary id only): map each alternate's
                -- on-use spell too (Demonic Healthstone, other mana pot ranks).
                local alts = PresetAltItemIDs(itemId)
                if alts then
                    for index = 1, #alts do
                        ItemSpell(alts[index])
                    end
                end
            end
        end
    end
    return result, waiting
end

-- ---------------------------------------------------------------------------
--  Cooldown State effects (presets): hide or glow the icon based on whether the
--  ability is on cooldown. A cooldown ENDING has no reliable event, so this is a
--  throttled poll -- but only while at least one preset actually uses it.
-- ---------------------------------------------------------------------------
-- Read an item's real (non-GCD) cooldown, container query first then C_Item,
-- mirroring ProcessPresetCooldowns. Returns start,dur (dur nil / <=1.5 = ready).
-- Secret Values are dropped HERE, before any truth-test or comparison: both
-- this helper and the alt-walk in PresetOnCD compare dur ahead of PresetOnCD's
-- tail guard, and comparing a secret raises a Lua error inside the poll ticker.
local function ReadItemCD(itemId)
    local startTime, duration
    if C_Container and C_Container.GetItemCooldown then
        startTime, duration = C_Container.GetItemCooldown(itemId)
    end
    if issecretvalue and (issecretvalue(startTime) or issecretvalue(duration)) then
        startTime, duration = nil, nil
    end
    if not (startTime and duration and duration > 1.5) and C_Item and C_Item.GetItemCooldown then
        startTime, duration = C_Item.GetItemCooldown(itemId)
        if issecretvalue and (issecretvalue(startTime) or issecretvalue(duration)) then
            startTime, duration = nil, nil
        end
    end
    return startTime, duration
end

-- itemID -> its preset's alternate item IDs. A preset (e.g. Light's Potential)
-- covers several ranks of the same consumable; the player owns one alternate and
-- the cooldown ticks on THAT id, not the primary. ProcessPresetCooldowns already
-- walks these, so PresetOnCD must too or the "CD Ready" glow never turns off;
-- ResolveCastSpells maps each alternate's on-use spell from it too.
local _presetAltMap
PresetAltItemIDs = function(itemId)
    if not _presetAltMap then
        _presetAltMap = {}
        for _, pr in ipairs(mod.CDM_ITEM_PRESETS or {}) do
            if pr.itemID and pr.altItemIDs then _presetAltMap[pr.itemID] = pr.altItemIDs end
        end
    end
    return _presetAltMap[itemId]
end

-- Unified "is this preset on a real (non-GCD) cooldown right now?" read.
-- Trinkets/items read the ITEM cooldown (its on-use spell can have a shorter
-- cooldown that would fire the ready edge early). Bail on nil / Secret Values.
PresetOnCD = function(ruleKey)
    local nowTime = GetTime()
    if ruleKey > 0 then
        -- A transform's real CD ticks on the override ID (e.g. Rushing Wind Kick over
        -- Rising Sun Kick); the base-ID query reads not-on-CD through that whole CD.
        local effectKey = ruleKey
        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            local shade = C_SpellBook.FindSpellOverrideByID(ruleKey)
            if shade and shade > 0 and shade ~= ruleKey then effectKey = shade end
        end
        local ci = C_Spell
            and C_Spell.GetSpellCooldown
            and (C_Spell.GetSpellCooldown(effectKey) or C_Spell.GetSpellCooldown(ruleKey))
        return (ci and ci.isActive and not ci.isOnGCD) or false
    end

    local startTime, duration, enable
    local invSlot = mod.SlotIDFromKey and mod.SlotIDFromKey(ruleKey)
    if invSlot then
        if GetInventoryItemCooldown then
            startTime, duration, enable = GetInventoryItemCooldown("player", invSlot)
        end
    else
        local itemId = -ruleKey
        -- Pot presets walk the swap-aware variant chain (partner family included while
        -- the toggle is on) -- only the owned/used id reports the shared potion
        -- cooldown. Everything else keeps the legacy primary-then-alts walk.
        local chain = mod.GetPresetPotChain and mod.GetPresetPotChain(itemId)
        if chain then
            for index = 1, #chain do
                startTime, duration = ReadItemCD(chain[index])
                if startTime and duration and duration > 1.5 then break end
            end
        else
            startTime, duration = ReadItemCD(itemId)
            -- The primary id often reads ready because the player owns one of the
            -- preset's alternates and the cooldown ticks on THAT id -- walk them,
            -- matching ProcessPresetCooldowns, so the glow can turn off.
            if not (startTime and duration and duration > 1.5) then
                local alts = PresetAltItemIDs(itemId)
                if alts then
                    for index = 1, #alts do
                        startTime, duration = ReadItemCD(alts[index])
                        if startTime and duration and duration > 1.5 then break end
                    end
                end
            end
        end
    end
    if startTime == nil or duration == nil then return false end
    if
        issecretvalue
        and (issecretvalue(startTime) or issecretvalue(duration) or (enable ~= nil and issecretvalue(enable)))
    then
        return false
    end
    if enable ~= nil and enable ~= 1 then return false end
    return (duration > 1.5 and nowTime < startTime + duration) or false
end

-- "Ready" for the Hidden (CD Ready) effects, which must not dismiss a charge spell that
-- is still recharging: a custom SPELL preset can have charges, so it defers to the
-- shared charge-aware read (ns.CdmCdStateReady). Items (key < 0) have no charges, so
-- onCD alone answers it. The override walk mirrors PresetOnCD above -- the charges live
-- on the override id (e.g. the transform), not the base one.
local function PresetCdReady(ruleKey, onCooldown)
    if ruleKey <= 0 then return not onCooldown end
    local effectKey = ruleKey
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        local shade = C_SpellBook.FindSpellOverrideByID(ruleKey)
        if shade and shade > 0 and shade ~= ruleKey then effectKey = shade end
    end
    return mod.CdmCdStateReady(effectKey, onCooldown)
end

-- Hidden Until Usable (ns.CdmSpellNotUsable) and Hidden Outside Form/Stance
-- (ns.CdmSpellOutsideForm) on a preset: spells only, through the same override
-- walk. An item key never reads unusable or outside its form, so the first
-- acts as Hidden (On CD) on items and the second always shows them.
local function PresetSpellTest(ruleKey, test)
    if ruleKey <= 0 then return false end
    local effectKey = ruleKey
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        local shade = C_SpellBook.FindSpellOverrideByID(ruleKey)
        if shade and shade > 0 and shade ~= ruleKey then effectKey = shade end
    end
    return test(effectKey)
end

-- Normal (shown) alpha for a frame, from its bar's opacity (out-of-combat fade folded
-- in via EffectiveBarAlpha so restores don't clobber the fade). Overflow-diverted
-- frames render inside the target bar, so their restore alpha follows that bar's
-- opacity (same source the visibility/layout passes use), not the identity bar's.
local function FrameBaseAlpha(frameCache)
    -- IconShownAlpha = EffectiveBarAlpha of the painted bar, forced to 0
    -- while that bar is visibility-hidden -- a restore here must never
    -- resurrect an icon the visibility engine has hidden.
    return mod.IconShownAlpha(frameCache)
end

-- cas is the rule's styling entry (passed in so a trinket, whose frame key is a
-- slot, still gets the per-item glow colour). Marks the frame "touched" so the
-- restore pass below can find it even after the trinket has been swapped out.
-- hide and glow are the two halves of the effect (ns.CdStateOf), each applied
-- on its own: the hide runs on hideCD (the form alone, or unusable counting as
-- unavailable; ready for Hidden (CD Ready)), the glow on the plain onCD.
ApplyCdState = function(widget, frameCache, customState, shouldHide, glowOn, hideCooldown, onCooldown, ready)
    local frameData = mod._hookFrameData and mod._hookFrameData[widget]
    if frameData then frameData._presetCdTouched = true end
    if
        shouldHide == "hiddenOnCD"
        or shouldHide == "hiddenReady"
        or shouldHide == "hiddenOnCDShift"
        or shouldHide == "hiddenReadyShift"
    then
        local isShift = (shouldHide == "hiddenOnCDShift" or shouldHide == "hiddenReadyShift")
        local isHidden
        if shouldHide == "hiddenOnCD" or shouldHide == "hiddenOnCDShift" then
            isHidden = hideCooldown
        else
            -- ready, not "not onCD": a charge spell is only READY at max charges,
            -- so the icon keeps tracking a running recharge (PresetCdReady).
            isHidden = ready
        end
        widget:SetAlpha(isHidden and 0 or FrameBaseAlpha(frameCache))
        -- Set the SAME flag the layout / visibility / refresh code already honors,
        -- so a relayout (mount, dismount, settings change) keeps it hidden instead
        -- of flashing it visible until the next tick.
        frameCache._cdStateHidden = isHidden or false
        -- Shift variants also maintain the bar-relayout flag (only relayouts
        -- on an actual transition; steady-state calls return immediately).
        if mod.SetCdStateShiftHidden then
            mod.SetCdStateShiftHidden(frameCache, isShift and isHidden or false)
        end
    elseif shouldHide == "lowerAlphaOnCD" then
        -- Identical to hiddenOnCD but with a customizable opacity instead of 0.
        -- Reuse the _cdStateHidden flag as "cd-state owns this alpha" so a relayout
        -- keeps the lowered value instead of flashing back to full opacity.
        -- A visibility-hidden bar (base 0) stays at 0 in both states.
        local faBase = FrameBaseAlpha(frameCache)
        widget:SetAlpha(
            faBase == 0 and 0
                or (hideCooldown and ((customState and customState.cdStateLowerAlpha) or 0.5) or faBase)
        )
        frameCache._cdStateHidden = hideCooldown or false
        if mod.SetCdStateShiftHidden then mod.SetCdStateShiftHidden(frameCache, false) end
    else
        -- No hide effect. Restore the alpha as well as the flag, exactly as the
        -- appearance refresh does on this transition: once a bar has settled
        -- nothing else re-asserts a preset frame's alpha, so clearing the flag
        -- alone leaves a hide from an earlier state painted for good.
        if frameCache._cdStateHidden then widget:SetAlpha(FrameBaseAlpha(frameCache)) end
        frameCache._cdStateHidden = false
        if mod.SetCdStateShiftHidden then mod.SetCdStateShiftHidden(frameCache, false) end
    end
    if not frameData then return end
    -- The glow: while the ability is READY (off cooldown), or while it is ON
    -- cooldown for Glow (On CD). A glow left from an earlier setting goes out.
    if not glowOn then
        if frameData._presetCdGlowOn then
            mod.StopCdGlow(frameData)
            frameData._presetCdGlowOn = false
        end
        return
    end
    -- Glow (On CD) wants the OPPOSITE cooldown state from the Ready variants
    -- (as the glowOnCD branch of the SetDesaturated hook in CUI_CDM_HookDecorate.lua).
    local isOnCdGlow = (glowOn == "glowOnCD")
    local wantsGlow = isOnCdGlow and onCooldown or (not isOnCdGlow and not onCooldown)
    if wantsGlow then
        local style = mod.CdReadyGlowStyle(glowOn, customState)
        local styleEntry = mod.GLOW_STYLES[style]
        -- A branch, not `and/or`: the Blackout frame does not exist before
        -- its first start, and the shared overlay must not stand in for it.
        local shade
        if styleEntry and styleEntry.solidFill then
            shade = frameData.blackoutOverlay
        else
            shade = frameData.glowOverlay
        end
        -- Re-assert against the overlay's REAL state (overlay._glowActive), not
        -- our flag alone. The overlay is shared with the proc-glow and
        -- appearance passes, and twelve of the thirteen sites that stop it never
        -- tell this engine -- so the flag said "lit" while the overlay was dark
        -- and a ready preset stayed unglowed until the next re-arm. A live
        -- proc or active-state glow keeps the shared overlay (ns.StartCdGlow
        -- returns nil), and the memo stays off until a later pass lights it.
        if not frameData._presetCdGlowOn or not (shade and shade._glowActive) then
            local cr, cg, callback = mod.CdReadyGlowColor(style, customState)
            frameData._presetCdGlowOn = mod.StartCdGlow(
                frameData,
                style,
                cr,
                cg,
                callback,
                mod.CdReadyGlowAlpha(customState)
            ) ~= nil
        end
    elseif frameData._presetCdGlowOn then
        mod.StopCdGlow(frameData)
        frameData._presetCdGlowOn = false
    end
end

-- Clear cd-state visuals on every icon we have touched (before a re-arm, so a
-- removed effect -- or a trinket swapped out of a slot -- un-hides / un-glows).
RestoreAllCdState = function()
    local icons = mod.cdmBarIcons
    local FCt = mod._ecmeFC
    if not icons or not FCt then return end
    for _, entries in pairs(icons) do
        for index = 1, #entries do
            local frame = entries[index]
            local frameData = mod._hookFrameData and mod._hookFrameData[frame]
            if frameData and frameData._presetCdTouched then
                local frameCache = FCt[frame]
                frame:SetAlpha(FrameBaseAlpha(frameCache))
                if frameCache then
                    frameCache._cdStateHidden = false
                    if mod.SetCdStateShiftHidden then mod.SetCdStateShiftHidden(frameCache, false) end
                end
                if frameData._presetCdGlowOn and (frameData.glowOverlay or frameData.blackoutOverlay) then
                    mod.StopCdGlow(frameData)
                    frameData._presetCdGlowOn = false
                end
                -- CloseAll wipes every window right after, but it reaches an
                -- icon only through its identity, which a rebuild clears on
                -- custom bars: drop the overlay's hold here so the icon's own
                -- CD-state glow is not refused until its next window ends.
                frameData._faActiveGlow = nil
                frameData._presetCdTouched = nil
            end
        end
    end
end

-- Same-frame coalesced evaluation: every engine edge funnels here. Zero cost
-- while no cd-state rules exist.
QueueCdStateEval = function()
    if _cdEvalQueued or #_cdStateRules == 0 then return end
    _cdEvalQueued = true
    C_Timer.After(0, function()
        _cdEvalQueued = false
        EvalCdStateNow()
    end)
end
-- The CD-state glow kick in CUI_CDM_HookTrinkets.lua (ns.CdGlowKick) relights an owed preset
-- glow through this pass.
mod.FakeActive_QueueCdStateEval = QueueCdStateEval

-- NOTE: pushes NEVER arm anything directly. The drain is push-through by
-- design (fresh duration objects land on frames constantly, including
-- zero-duration pushes onto READY frames when cooldown chatter waves arm it),
-- so a push proves nothing about cooldown state -- arming happens only in the
-- evaluation's read branch, on a cooldown actually observed running. A
-- push-side arm here fired ready sounds whenever ANY charge spell spent a
-- charge (the chatter pushed onto unrelated ready frames).

-- Install the engine-edge hooks on a rule-matched preset frame, once per frame
-- object (pool reuse keeps hooks valid: handlers resolve the frame's CURRENT
-- spell at fire time). The widget carries ONLY real cooldowns -- the drain
-- pushes with ignoreGCD -- so OnCooldownDone is the true ready edge with no
-- GCD confusion, and it fires under combat secrecy (the engine animates
-- durations Lua cannot read) and at alpha 0 (cd-state hides never Hide()).
local function WireCdStateFrame(frame)
    -- The wired mark lives in the frame's decoration data, never on the frame:
    -- a natively tracked racial's icon is Blizzard's own pooled viewer frame.
    local wfd = mod._hookFrameData and mod._hookFrameData[frame]
    if not wfd or wfd._cdsWired then return end
    local cooldown = frame.cd or frame.Cooldown
    if not cooldown then return end
    wfd._cdsWired = true
    cooldown:HookScript("OnCooldownDone", function() QueueCdStateEval() end)
    if cooldown.SetCooldownFromDurationObject then
        hooksecurefunc(cooldown, "SetCooldownFromDurationObject", function() QueueCdStateEval() end)
    end
    if cooldown.SetCooldown then
        hooksecurefunc(cooldown, "SetCooldown", function() QueueCdStateEval() end)
    end
    -- Early clears (encounter resets, drain falling edges) are ready edges.
    if cooldown.Clear then hooksecurefunc(cooldown, "Clear", function() QueueCdStateEval() end) end
end

-- One cd-state rule against every icon its key matches.
local function EvalCdStateRule(activeRule, icons, FCt)
    local customState = activeRule.cas
    -- The hide and the glow (ns.CdStateOf reads a blocking-false, a per-trinket
    -- "None" over a slot-level bar apply, as none); the sound may still be set.
    local shouldHide, glowOn = mod.CdStateOf(customState)
    local soundKey = customState and customState.cdReadySoundKey
    if soundKey == "none" then soundKey = nil end
    local stance = mod.CdmStanceBarOf(customState)
    if shouldHide or glowOn or soundKey or stance then
        local onCooldown = PresetOnCD(activeRule.spellID)
        -- Separate read for the Hidden (CD Ready) effects: a charge spell is
        -- ready only at max charges (items fall through to "not onCD").
        local ready = PresetCdReady(activeRule.spellID, onCooldown)
        -- Hidden Until Usable paints as Hidden (On CD) with "not usable"
        -- counting as unavailable, Hidden Outside Form/Stance with only the
        -- form deciding (ns.CD_STATE_HIDE); the glow and the sound below keep
        -- the plain onCD.
        local hideCooldown = onCooldown
        local m = shouldHide and mod.CD_STATE_HIDE[shouldHide]
        if m and (m.usable or m.form) then
            shouldHide = m.shift and "hiddenOnCDShift" or "hiddenOnCD"
            if m.form then
                hideCooldown = PresetSpellTest(activeRule.spellID, mod.CdmSpellOutsideForm)
            elseif not onCooldown then
                hideCooldown = PresetSpellTest(activeRule.spellID, mod.CdmSpellNotUsable)
            end
        end
        -- Stance Bar: hidden on (or off) a stance bar page whatever the
        -- cooldown, with its own Shift Icons choice; alone it never hides on
        -- the cooldown.
        if stance then
            local sHide, sShift = mod.CdmStanceBarHidden(stance)
            if sHide then
                shouldHide, hideCooldown = sShift and "hiddenOnCDShift" or "hiddenOnCD", true
            elseif not shouldHide then
                shouldHide, hideCooldown = "hiddenOnCD", false
            end
        end
        local spellRef = activeRule.spellID
        -- Sound only fires while the ability's icon is present on a bar.
        local hasIcon = false
        for _, entries in pairs(icons) do
            for index = 1, #entries do
                local frame = entries[index]
                local frameCache = frame and FCt[frame]
                -- rule.user rules come from the profile store; built-in rules
                -- (FAKE_ACTIVE_RULES) deliberately decorate Blizzard icons and
                -- keep their reach. Racials are also let through natively-tracked
                -- (non-injected) frames: the Presets cog is their only cd-state
                -- config surface, unlike custom spells which legitimately defer
                -- to normal per-spell settings once Blizzard tracks them for real.
                if
                    frameCache
                    and KeyMatches(spellRef, frameCache.spellID)
                    and (
                        not activeRule.user
                        or IsInjectedFrame(frame)
                        or (mod._myRacialsSet and mod._myRacialsSet[spellRef])
                    )
                then
                    hasIcon = true
                    WireCdStateFrame(frame)
                    if shouldHide or glowOn then
                        ApplyCdState(
                            frame,
                            frameCache,
                            customState,
                            shouldHide,
                            glowOn,
                            hideCooldown,
                            onCooldown,
                            ready
                        )
                    end
                end
            end
        end
        -- Audio Effect on CD Ready: arm while on cooldown, fire once on the ready
        -- edge. A missing icon leaves the armed state untouched so a rebuild at
        -- cooldown-end can't swallow the edge (armed state persists by key).
        if soundKey then
            local akey = activeRule.srcKey or spellRef
            if onCooldown then
                if hasIcon then _cdrArmedByKey[akey] = true end
            elseif hasIcon and _cdrArmedByKey[akey] then
                _cdrArmedByKey[akey] = nil
                if not (mod._cdmSoundSuppressed and mod._cdmSoundSuppressed()) then
                    local filePath = mod.FOCUSKICK_SOUND_PATHS and mod.FOCUSKICK_SOUND_PATHS[soundKey]
                    if filePath then PlaySoundFile(filePath, "Master") end
                end
            end
        end
    end
end

-- One full evaluation pass. Edge-driven (widget push / OnCooldownDone / Clear /
-- regen / gear, all through QueueCdStateEval) AND called synchronously at the
-- end of a re-arm, so a settings change does not leave the icon shown for a
-- frame before the next edge re-hides it.
EvalCdStateNow = function()
    local icons = mod.cdmBarIcons
    local FCt = mod._ecmeFC
    if not icons or not FCt then return end
    for region = 1, #_cdStateRules do
        EvalCdStateRule(_cdStateRules[region], icons, FCt)
    end
end

-- After an exception aura came or went (ns.CdmFormAuraEdge): only the form
-- rules that hang on one, unless a full pass is queued for the same frame.
local function RunFormAuraEval()
    _formAuraQueued = false
    if _cdEvalQueued then return end
    local icons = mod.cdmBarIcons
    local FCt = mod._ecmeFC
    if not icons or not FCt then return end
    for region = 1, #_formAuraRules do
        EvalCdStateRule(_formAuraRules[region], icons, FCt)
    end
end

QueueFormAuraEval = function()
    if _formAuraQueued or _cdEvalQueued then return end
    _formAuraQueued = true
    C_Timer.After(0, RunFormAuraEval)
end

local function MapCast(activeRule)
    local spells, waiting = ResolveCastSpells(activeRule.triggerSpellID or activeRule.spellID)
    _pendingCastRules[activeRule] = waiting and next(waiting) and waiting or nil
    for index = 1, #spells do
        local sp = spells[index]
        local entries = _castMap[sp]
        if not entries then
            entries = {}
            _castMap[sp] = entries
        end
        -- A rule maps again when one of its items loads (RetryPendingCasts):
        -- a spell it already had keeps one entry.
        local found = false
        for jdx = 1, #entries do
            if entries[jdx] == activeRule then
                found = true
                break
            end
        end
        if not found then entries[#entries + 1] = activeRule end
    end
    _needCast = true
end

-- ITEM_DATA_LOAD_RESULT: each rule waiting on the item maps again once it has
-- loaded (its other items may still wait), or stops waiting on it after a
-- failed load. Either way the item is settled until the next re-arm, and the
-- listener goes once no rule waits.
RetryPendingCasts = function(itemId, success)
    local changed = false
    for activeRule, waiting in pairs(_pendingCastRules) do
        if waiting[itemId] then
            _settledCastItems[itemId] = true
            if success then
                MapCast(activeRule)
            else
                waiting[itemId] = nil
                if not next(waiting) then _pendingCastRules[activeRule] = nil end
            end
            changed = true
        end
    end
    if changed and not next(_pendingCastRules) then UpdateListeners() end
end

local function AddRule(activeRule)
    _rules[#_rules + 1] = activeRule
    local tr = activeRule.trigger
    if tr == "aura" then
        _auraRules[#_auraRules + 1] = activeRule
        _needAura = true
    elseif type(tr) == "function" then
        _customRules[#_customRules + 1] = activeRule
        _needCast = true
    else -- "cast"
        MapCast(activeRule)
    end
end

-- ---------------------------------------------------------------------------
--  Re-sync a single overlay after its underlying icon was restyled.
-- ---------------------------------------------------------------------------
-- Called from RefreshCDMIconAppearance (via ApplyShapeToCDMIcon) whenever an icon
-- is re-shaped / re-bordered / re-zoomed -- including a settings change made WHILE
-- a fake-active window is open. That restyle re-textures the shared shapeMask and
-- resets the icon's border frame back to its normal level (below our overlay), so
-- without this the overlay would show the old/stale shape and the border would sit
-- hidden beneath us until the window next reopened. Re-applies our shape (new
-- mask + geometry + swipe) and forces a fresh border raise. No-op unless an
-- overlay is currently shown on this icon.
function mod.FakeActive_OnIconRestyled(iconBtn)
    local o = _overlays[iconBtn]
    if not o or not o._rule then return end -- no overlay / no open window
    local st121 = FA121 and FA121.byRule[o._rule]
    if st121 then
        -- 12.1 slot mode: the legacy overlay is permanently dark (alpha 0 --
        -- the slot subtree renders the active state), so the alpha gate
        -- below would always skip; resync whenever the rule is armed
        -- instead (covers the pcall'd best-effort cd mirror at the tail).
        if not st121.armed then return end
    elseif o.frame:GetAlpha() == 0 then
        return
    end -- overlay not currently shown
    local frameCache = mod._ecmeFC and mod._ecmeFC[iconBtn]
    local barId = frameCache and frameCache.barKey
    local edge = barId and mod.barDataByKey and mod.barDataByKey[barId]
    IconTexture(iconBtn, o, o._rule)
    if mod.ApplyShapeToOverlay then mod.ApplyShapeToOverlay(iconBtn, o.icon, o.cd, edge) end
    -- Re-apply Duration Text styling too (the font/size/colour may have changed).
    if mod.StyleOverlayCooldownText then
        mod.StyleOverlayCooldownText(o.cd, edge, o._ss, iconBtn:GetScale())
    end
    -- Re-assert Reverse Swipe as well: o._ss is the live chained settings
    -- block, so a toggle made while the window is open takes effect on this
    -- restyle pass instead of waiting for the next window.
    if mod._cdmAnyReverseSwipe then o.cd:SetReverse((o._ss and o._ss.reverseSwipe) and true or false) end
    -- The restyle reset the border to its normal level; clear the stale flag so
    -- RaiseOverlayBorders re-captures that level and lifts it above us again.
    o._brdRaised = false
    RaiseOverlayBorders(iconBtn, o, edge)
    -- Re-feed the active glow / border the underlying shape + border refs, then
    -- re-apply so a glow-colour / active-border edit takes effect live (the glow
    -- only restarts if its style/colour actually changed). ApplyShapeToCDMIcon
    -- just reset the shape border to its configured colour, so drop the stale
    -- saved colour first to re-capture it for restore-on-falloff.
    local ufd = mod._hookFrameData and mod._hookFrameData[iconBtn]
    local uifc = mod._ecmeFC and mod._ecmeFC[iconBtn]
    o.borderFrame = (ufd and ufd.borderFrame) or nil
    local gfc = mod.FC and mod.FC(o.frame)
    if gfc then
        gfc.shapeApplied = (uifc and uifc.shapeApplied) or nil
        gfc.shapeName = (uifc and uifc.shapeName) or nil
        gfc.shapeMask = (uifc and uifc.shapeMask) or nil
        gfc.shapeBorder = (uifc and uifc.shapeBorder) or nil
    end
    if o._ss and mod.ApplyActiveOverlays then
        o._sbColorSaved = false
        mod.ApplyActiveOverlays(o.frame, o, o._ss, true, edge)
        -- A live glow edit can switch the overlay's active glow on or off.
        HoldCdGlow(iconBtn, o._activeGlowOn == true and not st121)
    end
    -- 12.1 slot mode: the live swipe is the slot-child cooldown, not o.cd.
    -- Best-effort mirror only: the engine binding owns that region (field
    -- lesson, 68824), so these are pcall'd and skipped once known-denied.
    if st121 and st121.cd and not st121.cdLocked then
        if mod.StyleOverlayCooldownText then
            pcall(mod.StyleOverlayCooldownText, st121.cd, edge, o._ss, iconBtn:GetScale())
        end
        if mod._cdmAnyReverseSwipe then
            pcall(st121.cd.SetReverse, st121.cd, (o._ss and o._ss.reverseSwipe) and true or false)
        end
        if mod.ApplyShapeToOverlay then pcall(mod.ApplyShapeToOverlay, iconBtn, o.icon, st121.cd, edge) end
    end
end

-- The form rules whose answers hang on an exception aura (ns.CdmFormNeedsAura):
-- decided at every re-arm, and again when a talent change wipes the form
-- answers (ns.CdmWipeFormCache), since a talent can teach or drop one.
local function SyncFormAuraRules()
    wipe(_formAuraRules)
    for region = 1, #_cdStateRules do
        local activeRule = _cdStateRules[region]
        local shouldHide = activeRule.cas and mod.CdStateHideOf(activeRule.cas)
        local m = shouldHide and mod.CD_STATE_HIDE[shouldHide]
        if m and m.form and mod.CdmFormNeedsAura(activeRule.spellID) then
            _formAuraRules[#_formAuraRules + 1] = activeRule
        end
    end
    _needFormAuras = #_formAuraRules > 0
end
mod.FakeActive_SyncFormAuraRules = SyncFormAuraRules

-- ---------------------------------------------------------------------------
--  Re-arm for the current class + spec + profile. Called after every rebuild.
-- ---------------------------------------------------------------------------
function mod.FakeActive_Rearm()
    RestoreAllCdState() -- un-hide / un-glow icons from the outgoing rule set
    CloseAll()
    wipe(_rules)
    wipe(_auraRules)
    wipe(_customRules)
    wipe(_castMap)
    wipe(_cdStateRules)
    wipe(_pendingCastRules)
    wipe(_settledCastItems)
    -- Re-read rather than wipe: a re-arm during the login window would leave
    -- the map empty and the lazy refresh in KeyMatches would just rebuild it.
    RefreshSlotItemKeys()
    _needAura, _needCast, _armed, _hasUserRules, _needUsable, _needForms, _needFormAuras =
        false, false, false, false, false, false, false
    _needStance = false
    if FA121 then FA121.BeginSweep() end

    -- 1. Built-in rules (class/spec gated).
    local _, class = UnitClass("player")
    local specIdx = GetSpecialization()
    for index = 1, #FAKE_ACTIVE_RULES do
        local activeRule = FAKE_ACTIVE_RULES[index]
        if
            (not activeRule.class or activeRule.class == class)
            and (not activeRule.spec or activeRule.spec == specIdx)
        then
            if FA121 and activeRule.trigger == "aura" then
                -- 12.1: aura rules ride the engine slot, never the numeric
                -- GetPlayerAuraBySpellID window (dead for secret-flagged
                -- spells like Ebon Might since build 68824).
                FA121.Want(activeRule)
            else
                AddRule(activeRule)
            end
        end
    end
    if FA121 then FA121.EndSweep() end

    -- 2. User rules: profile-level custom active states, keyed by spell. These
    --    travel with the spell across every bar and spec, so no barKey scope --
    --    the overlay shows on whichever bar currently hosts the icon.
    -- A spell may have a cast-triggered active overlay (duration), a continuous
    -- cooldown-state effect (a hide and / or a glow, ns.CdStateOf), or both.
    local storage = mod.GetCustomActiveStates and mod.GetCustomActiveStates()
    if storage then
        -- Shared rule constructor. matchKey is the icon-identity key live frames
        -- carry (fc.spellID): positive spell id, -itemID item preset, or a trinket
        -- slot (-13/-14). srcKey keys the persistent CD-ready-sound armed state.
        -- cas is the styling entry the rule reads -- for trinket slots a chained
        -- item-over-slot view (see below).
        local function AddUserRule(matchKey, srcKey, customState)
            local hasDur = (customState.duration or 0) > 0
            -- Explicit false = a per-trinket "None" blocking the slot's bar-apply
            -- value from showing through; ns.CdStateOf reads it as none.
            local shouldHide, glowOn = mod.CdStateOf(customState)
            local stance = mod.CdmStanceBarOf(customState)
            local hasCd = shouldHide ~= nil or glowOn ~= nil or stance ~= nil
            local hasSound = customState.cdReadySoundKey ~= nil and customState.cdReadySoundKey ~= "none"
            -- Keep Colored (On CD) and Ignore Resource Cost need no rule of their
            -- own -- preset frames read them directly (PresetKeepsColor,
            -- PresetIgnoresResourceTint). Gates flipped BEFORE the early return:
            -- they are valid on a spell with no overlay, cd-state effect or sound.
            if customState.noDesatOnCD then mod._cdmAnyNoDesatOnCD = true end
            if customState.noResourceTint then mod._cdmAnyNoResourceTint = true end
            if not (hasDur or hasCd or hasSound) then return end
            local activeRule = { spellID = matchKey, srcKey = srcKey, cas = customState, user = true }
            _rules[#_rules + 1] = activeRule
            _hasUserRules = true
            if hasDur then
                activeRule.trigger = "cast"
                activeRule.duration = customState.duration
                MapCast(activeRule)
            end
            if hasCd or hasSound then
                -- Both effects ride the same cooldown poll (EvalCdStateNow).
                _cdStateRules[#_cdStateRules + 1] = activeRule
                local m = shouldHide and mod.CD_STATE_HIDE[shouldHide]
                if m and m.usable then _needUsable = true end
                if m and m.form then _needForms = true end
                if stance then _needStance = true end
            end
        end
        local eq13 = GetInventoryItemID and GetInventoryItemID("player", 13) or nil
        local eq14 = GetInventoryItemID and GetInventoryItemID("player", 14) or nil
        for ruleKey, customState in pairs(storage) do
            -- Skip trinket-SLOT keys (dedicated pass below) and the EQUIPPED
            -- trinkets' item keys (they ride their slot's rule as the own-value
            -- layer -- a second rule here would fight it on the same frame). An
            -- UNEQUIPPED trinket's item entry still becomes a rule; its key
            -- matches no frame, which is correct (dormant until equipped).
            if
                type(customState) == "table"
                and ruleKey ~= -13
                and ruleKey ~= -14
                and not (eq13 and ruleKey == -eq13)
                and not (eq14 and ruleKey == -eq14)
            then
                AddUserRule(ruleKey, ruleKey, customState)
            end
        end
        -- Trinket slots: ONE rule per slot. The slot entry (-13/-14) is the
        -- "Apply to Bar" stamp -- slot-keyed so a bar application covers
        -- whatever trinket is equipped, before and after swaps. The equipped
        -- item's own entry (per-spell menu settings) chains over it per key,
        -- so per-trinket choices win. Cast + cooldown already resolve the
        -- slot's CURRENT item via ResolveCastSpells / PresetOnCD.
        for slotId = 13, 14 do
            local slotE = storage[-slotId]
            if type(slotE) ~= "table" then slotE = nil end
            local itemId = (slotId == 13) and eq13 or eq14
            local itemE = itemId and storage[-itemId] or nil
            if type(itemE) ~= "table" then itemE = nil end
            local eff = itemE or slotE
            if eff then
                if itemE and mod.ChainSettings then mod.ChainSettings(itemE, slotE) end
                AddUserRule(-slotId, -slotId, eff)
            end
        end
    end

    SyncFormAuraRules()
    _armed = #_rules > 0
    UpdateListeners()
    -- Ask once for each item a cast trigger waits on; the answers arrive through
    -- ITEM_DATA_LOAD_RESULT, registered just above.
    if next(_pendingCastRules) and C_Item and C_Item.RequestLoadItemDataByID then
        local requested = {}
        for _, waiting in pairs(_pendingCastRules) do
            for itemId in pairs(waiting) do
                if not requested[itemId] then
                    requested[itemId] = true
                    C_Item.RequestLoadItemDataByID(itemId)
                end
            end
        end
    end
    if #_cdStateRules > 0 then
        -- Apply + wire the engine-edge hooks now so the rebuild doesn't flash
        -- the icon visible; from here every transition is edge-driven.
        EvalCdStateNow()
    end

    if not _armed then return end
    InitialStamp()
    if C_Timer then
        C_Timer.After(3, function()
            if not _armed then return end
            InitialStamp()
            EvalCdStateNow() -- frames may not have existed at re-arm (login)
        end)
    end
end

-- Re-arm on every CDM full rebuild, kept out of the (large) rebuild function.
local _origFullCDMRebuild = mod.FullCDMRebuild
mod.FullCDMRebuild = function(reason)
    -- Rebuilds read transient cooldown states while re-rendering; open the
    -- sound settle window first so re-primes can't false-arm ready sounds.
    if mod._cdmBumpSoundSettle then mod._cdmBumpSoundSettle() end
    -- Rebuilds are also the moments the tracked buff catalog can change
    -- (talents/spec/settings) -- let the next reanchor reconcile the buff
    -- display order.
    mod._cdmBuffOrderDirty = true
    if _origFullCDMRebuild then _origFullCDMRebuild(reason) end
    mod.FakeActive_Rearm()
end

-- Re-arm once after world entry.
--
-- A custom active state on an EQUIPPED TRINKET is stored under the item
-- (-itemID), while the live icon carries the SLOT key (-13 / -14). The two are
-- bridged in the slot pass of FakeActive_Rearm, which reads
-- GetInventoryItemID -- so a re-arm that runs before the client can answer that
-- builds no slot rule, and the icon it was meant to drive matches nothing.
--
-- The login re-arm rides FullCDMRebuild, which is early enough for that to happen, and
-- nothing re-arms afterwards: PLAYER_EQUIPMENT_CHANGED is only registered once user
-- rules exist and in any case needs a real gear swap. So the state stayed dormant for
-- the whole session, and the only thing that revived it was opening the options, which
-- re-arms as a side effect. That is exactly the reported shape: "works until you log
-- out, then you have to choose it again".
--
-- Once per session, deferred, and only for the FIRST world entry: re-arming is
-- a teardown and rebuild of every rule, so doing it on later zone-ins could cut
-- short an overlay that is currently running. Nothing is running this early.
-- Re-arm is idempotent, so this costs one rebuild of a small rule set.
do
    local rearmed = false
    local frame = mod.TakeShell()
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(self)
        if rearmed then return end
        rearmed = true
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if C_Timer then
            C_Timer.After(2, function()
                if mod.FakeActive_Rearm then mod.FakeActive_Rearm() end
            end)
        end
    end)
end

-- Debug toggle: /run CludesUI.FakeActiveDebug()
if CludesUI then
    function CludesUI.FakeActiveDebug()
        mod._fakeActiveDebug = not mod._fakeActiveDebug
        print(
            ("|cff4cc9f0CUI FakeActive|r debug %s | armed=%s rules=%d"):format(
                mod._fakeActiveDebug and "ON" or "off",
                tostring(_armed),
                #_rules
            )
        )

        -- Per-rule dump. "armed with N rules" reads true in every broken report,
        -- so on its own it separates nothing. What matters per rule is whether
        -- its trigger resolved to a cast spell at all, and whether any live icon
        -- carries its key -- the two independent ways a rule goes inert.
        local FCt, icons = mod._ecmeFC, mod.cdmBarIcons
        for index = 1, #_rules do
            local activeRule = _rules[index]
            local triggers = {}
            for sp, entries in pairs(_castMap) do
                for jdx = 1, #entries do
                    if entries[jdx] == activeRule then triggers[#triggers + 1] = sp end
                end
            end
            local matched = 0
            if FCt and icons then
                for _, entries in pairs(icons) do
                    for jdx = 1, #entries do
                        local frame = entries[jdx]
                        local frameCache = frame and FCt[frame]
                        if frameCache and KeyMatches(activeRule.spellID, frameCache.spellID) then
                            matched = matched + 1
                        end
                    end
                end
            end
            print(
                ("  rule%d key=%s src=%s dur=%s trigger=%s casts=[%s] frames=%d%s"):format(
                    index,
                    tostring(activeRule.spellID),
                    tostring(activeRule.srcKey),
                    tostring(activeRule.duration),
                    tostring(activeRule.trigger),
                    (#triggers > 0) and table.concat(triggers, ",") or "|cffff4444NONE|r",
                    matched,
                    (matched == 0) and " |cffff4444<- no icon|r" or ""
                )
            )
        end
    end
end
