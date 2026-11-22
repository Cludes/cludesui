if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Visibility.lua
--  Shared visibility dispatcher. Each module (Minimap, Friends, QuestTracker,
--  Cursor) registers its own update function here; this file owns the event
--  frame, combat state, mouseover polling, and the global bridge names.
--
--  store.visibilityMatch: nil / "all" = every constrained axis must pass (the
--  original and still default behavior), "any" = at least one must. A plain store
--  scalar rather than a key inside visibilityModes, because an Any selection can
--  consist of option lanes alone, and those are stored without a mode set to hang
--  it on.
-------------------------------------------------------------------------------
local CUI = _G.CludesUI or {}
_G.CludesUI = CUI

-------------------------------------------------------------------------------
--  Combat state (single source of truth)
-------------------------------------------------------------------------------
local _inCombat = false

local function IsInCombat() return _inCombat end

CUI.IsInCombat = IsInCombat

-------------------------------------------------------------------------------
--  Eval helper (shared by all modules' cfg checks)
-------------------------------------------------------------------------------
-- Capability profile for the dispatcher-evaluated modules (Minimap, Friends,
-- Chat, Damage Meters, Quest Tracker): their legacy "In Party" means
-- party-exclusive-of-raid, so multi-selections keep that meaning here.
local DISPATCHER_CAPS = { partyIncludesRaid = false }

-- Returns true = show, false = hide, "mouseover" = mouseover mode
local function EvalVisibility(conf)
    if not conf then return true end
    -- Under Any, EvalVisibilityExtended owns the whole verdict, the option HIDE veto
    -- included, so asking CheckVisibilityOptions first re-ran every set lane's probe (the
    -- instance lookup, IsResting, the druid aura walk) once per updater per dispatcher
    -- event for no second opinion. Under All the veto still has to LEAD: the mode engine
    -- knows nothing about option lanes there, so a passing set must not settle it.
    -- A nil result under Any is the legacy-ORPHAN hand-back, and that case drops through
    -- to exactly the chain an All store takes, veto included.
    local ext
    if conf.visibilityMatch == "any" then
        ext = CUI.EvalVisibilityExtended
            and CUI.EvalVisibilityExtended(conf, "visibility", nil, DISPATCHER_CAPS)
        if ext ~= nil then return ext end
    end
    if CUI.CheckVisibilityOptions(conf) then return false end
    ext = CUI.EvalVisibilityExtended and CUI.EvalVisibilityExtended(conf, "visibility", nil, DISPATCHER_CAPS)
    if ext ~= nil then return ext end
    local mode = conf.visibility or "always"
    if mode == "mouseover" then return "mouseover" end
    if mode == "always" then return true end
    if mode == "never" then return false end
    if mode == "in_combat" then return _inCombat end
    if mode == "out_of_combat" then return not _inCombat end
    local inGroup = IsInGroup()
    local inRaid = IsInRaid()
    if mode == "in_raid" then return inRaid end
    if mode == "in_party" then return inGroup and not inRaid end
    if mode == "solo" then return not inGroup end
    return true
end

CUI.EvalVisibility = EvalVisibility

-------------------------------------------------------------------------------
--  Updater registry
-------------------------------------------------------------------------------
local updaters = {}

-- Register a module's update function. Called whenever visibility state may
-- have changed (combat/zone/group/target change). The function should read
-- its own DB state and Show/Hide its frame accordingly.
function CUI.RegisterVisibilityUpdater(func)
    if type(func) ~= "function" then return end
    updaters[#updaters + 1] = func
end

function CUI.UnregisterVisibilityUpdater(func)
    for idx = #updaters, 1, -1 do
        if updaters[idx] == func then
            table.remove(updaters, idx)
            return
        end
    end
end

-- Mouseover poll registry: each entry is { frame=, visible=, isActive=fn, getAlpha=fn }.
-- isActive returns true when that frame currently wants mouseover behavior.
-- getAlpha (optional) returns the alpha a reveal applies, for a target whose shown
-- state is not full alpha (the Minimap's Opacity); nil reveals at 1. It runs only on
-- the reveal edge, never per tick.
local mouseoverTargets = {}
-- Mouseover predicates are pure functions of module settings plus the same state edges
-- the dispatcher already watches, so each target's answer is cached and re-derived only
-- when this generation moves: synchronously on every dispatcher event (the combat edge
-- must land before the next scan tick -- a stale "active" through a combat flip would
-- let the scan touch the protected Minimap during lockdown), on every
-- RequestVisibilityUpdate (every module apply pokes it), and on every shared
-- visibility-selection write. Each target's isActive closure runs at most once per
-- generation instead of once per 0.15s tick.
local _moGen = 1
local MouseoverScan -- defined with the scan below; bound here for the subscribe

function CUI.RegisterMouseoverTarget(widget, isActive, getAlpha)
    if not widget or type(isActive) ~= "function" then return end
    if type(getAlpha) ~= "function" then getAlpha = nil end
    -- visible starts nil = "state not applied yet", not false: the scan below treats nil
    -- as unknown and applies the hidden state on its first active tick. Seeding false
    -- would make that first tick a no-op (already-false edge), so a target that becomes
    -- active with the cursor away never received its Hide() until the first real hover.
    mouseoverTargets[#mouseoverTargets + 1] =
        { frame = widget, visible = nil, isActive = isActive, getAlpha = getAlpha }
    -- First target arms the shared 0.15s scan on the Mouse service (same-key
    -- subscribe is idempotent). No targets registered = the scan never runs.
    CludesUI.Mouse.SubscribeTick("visMouseover", 0.15, MouseoverScan)
end

-- Closable panels (Friends) unregister while hidden so the scan never spends
-- their isActive closure on a panel that cannot be revealed anyway. Callers
-- unregister only while their frame is hidden/dormant; no alpha restore runs.
function CUI.UnregisterMouseoverTarget(widget)
    for idx = #mouseoverTargets, 1, -1 do
        if mouseoverTargets[idx].frame == widget then table.remove(mouseoverTargets, idx) end
    end
end

-------------------------------------------------------------------------------
--  Dispatcher
-------------------------------------------------------------------------------
local function RequestVisibilityUpdate()
    _moGen = _moGen + 1
    for idx = 1, #updaters do
        local success = pcall(updaters[idx])
        if not success then
            -- swallow; one bad updater should not take down the rest
        end
    end
end

CUI.RequestVisibilityUpdate = RequestVisibilityUpdate

-- Deferred callback so we don't re-allocate a closure on every event
local function DeferredRequest() RequestVisibilityUpdate() end

-------------------------------------------------------------------------------
--  Event frame
-------------------------------------------------------------------------------
local visibilityFrame = CreateFrame("Frame")
visibilityFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
visibilityFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
visibilityFrame:RegisterEvent("PLAYER_DEAD")
visibilityFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
visibilityFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
visibilityFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
visibilityFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
visibilityFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
visibilityFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
-- Resting edge: IsResting() itself has no dedicated poll, so without this the Resting
-- checklist row only re-evaluates when some unrelated event (mount/zone/combat) happens
-- to fire the dispatcher afterward -- e.g. it looked "bound to landing" because dismounting
-- fires PLAYER_MOUNT_DISPLAY_CHANGED, not because resting is actually tied to mounting.
visibilityFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
-- Vehicle edges: same reasoning as Resting -- the In Vehicle axis needs its
-- own edge or it only re-evaluates on incidental traffic. Player-filtered:
-- other units' vehicle changes are irrelevant to these axes.
visibilityFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
visibilityFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
-- Dragonriding edges: mount-capability changes fire PLAYER_CAN_GLIDE_CHANGED
-- (repo-proven event); takeoff/landing while staying mounted fires
-- PLAYER_IS_GLIDING_CHANGED, which is probed because nothing registered it before this
-- feature. When the probe fails on a client, the dragonriding checklist items lock
-- (CUI._hasGlidingEvent) instead of evaluating with stale edges.
visibilityFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
do
    local success
    if C_EventUtils and C_EventUtils.IsEventValid then
        success = C_EventUtils.IsEventValid("PLAYER_IS_GLIDING_CHANGED") and true or false
        if success then visibilityFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED") end
    else
        success = pcall(visibilityFrame.RegisterEvent, visibilityFrame, "PLAYER_IS_GLIDING_CHANGED") and true
            or false
    end
    CUI._hasGlidingEvent = success
end

visibilityFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_REGEN_DISABLED" then
        _inCombat = true
    elseif evt == "PLAYER_REGEN_ENABLED" then
        _inCombat = false
    elseif evt == "PLAYER_DEAD" then
        -- A dead player is never in combat, but PLAYER_REGEN_ENABLED is not
        -- guaranteed to fire on death (notably when dying mid-encounter in an
        -- instance). A missed "left combat" event would otherwise leave
        -- _inCombat stuck true, hiding every "Out of Combat" frame until a
        -- reload. Clearing it here is the safety net for that case.
        _inCombat = false
    elseif evt == "PLAYER_ENTERING_WORLD" then
        -- Re-sync from the real combat state across world / instance boundaries
        -- in case a regen toggle was missed while loading.
        _inCombat = InCombatLockdown() and true or false
    end
    -- Synchronous: the cache must flip before any same-frame scan tick.
    _moGen = _moGen + 1
    C_Timer.After(0, DeferredRequest)
end)

-------------------------------------------------------------------------------
--  Mouseover poll
-------------------------------------------------------------------------------
-- Cursor-in-bounds check (works on hidden frames using saved position/size).
-- Coordinates come from the shared Mouse service sample.
local function IsCursorOver(widget, rawX, rawY)
    if not widget.GetRect then return false end
    local l, b, wid, hgt = widget:GetRect()
    if not l then return false end
    local es = widget:GetEffectiveScale()
    local cx, cy = rawX / es, rawY / es
    return cx >= l and cx <= l + wid and cy >= b and cy <= b + hgt
end

-- The mouseover-visibility scan, dispatched by the shared Mouse service at the same
-- 0.15s cadence the old poll used -- but with no per-frame OnUpdate underneath (the
-- service's anim ticker sleeps in C between fires), one shared cursor sample instead of
-- one per target, and zero cost until the first target registers.
MouseoverScan = function(rawX, rawY)
    for idx = 1, #mouseoverTargets do
        local tbl = mouseoverTargets[idx]
        local widget = tbl.frame
        if widget then
            local active
            if tbl._genSeen == _moGen then
                active = tbl._genActive
            else
                active = tbl.isActive() and true or false
                tbl._genSeen = _moGen
                tbl._genActive = active
            end
            if active then
                tbl._wasActive = true
                local over = IsCursorOver(widget, rawX, rawY)
                -- Compared against true/false rather than truthiness, so the unknown
                -- state (nil, at registration and after a deactivation) applies once
                -- instead of being read as "already hidden".
                if over then
                    if tbl.visible ~= true then
                        tbl.visible = true
                        local ga = tbl.getAlpha
                        widget:SetAlpha(ga and ga() or 1)
                        widget:EnableMouse(true)
                        widget:Show()
                    end
                elseif tbl.visible ~= false then
                    tbl.visible = false
                    widget:Hide()
                end
            elseif tbl._wasActive then
                -- isActive just turned off -- clear tracking state and let
                -- UpdateVisibility handle the alpha for the new mode.
                tbl._wasActive = false
                tbl.visible = nil
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Compat globals (kept for the many call sites already using them)
-------------------------------------------------------------------------------
_G._CUBS_InCombat = IsInCombat
_G._CUBS_EvalVisibility = EvalVisibility
_G._CUBS_UpdateVisibility = RequestVisibilityUpdate

-------------------------------------------------------------------------------
--  Multi-Select Visibility Engine
--  The Visibility dropdown is a checklist: one checked item behaves exactly
--  like the legacy single mode (stored in the legacy scalar key, evaluated by
--  the module's existing code, byte-identical); two or more checked condition
--  items store a set in `visibilityModes` and evaluate here.
--
--  Combination semantics: OR within an axis, AND across axes.
--    combat axis:  in_combat / out_of_combat
--    group axis:   in_raid / in_party / solo
--    dragon axis:  show_dragonriding / show_not_dragonriding
--  An axis with none (or all) of its items checked imposes no constraint.
--  Never / Always are exclusive single selections and never appear in a set.
--  Mouseover under All is one more AND gate (hover-gated conditions): the
--  element is hover-revealed while every condition axis passes and hidden
--  outright while any fails. Under Any it is a disjunct of its own instead: a
--  passing condition shows the element outright, and hover stays available when
--  none passes. A set containing mouseover stores the scalar "mouseover" as its
--  representative, so every legacy mouseover mechanism (Action Bars' fade, UF
--  hover handlers, the dispatcher poll) engages without per-module rewiring.
-------------------------------------------------------------------------------

CUI.VIS_AXES = {
    combat = { "in_combat", "out_of_combat" },
    group = { "in_raid", "in_party", "solo" },
    dragon = { "show_dragonriding", "show_not_dragonriding" },
}

-- Shared caps table for Action Bars, CDM, Unit Frames, and Resource Bars.
-- In Party and In Raid Group are disjoint here, same as every other module --
-- checking one does not implicitly check the other. Kept on the namespace so
-- files at the Lua 5.1 200-local cap don't need a new local.
CUI.VIS_CAPS_DEFAULT = { partyIncludesRaid = false }

-- Copy-target caps for elements that cannot express group modes (Pet Bar).
CUI.VIS_CAPS_NO_GROUP = { partyIncludesRaid = false, noGroupModes = true }

-- Canonical priority order for the representative scalar: the single legacy
-- mode written alongside a multi-selection so older addon versions and every
-- existing scalar reader see a sane, user-recognizable value.
local VIS_REPRESENTATIVE_ORDER = {
    "in_combat",
    "out_of_combat",
    "in_raid",
    "in_party",
    "solo",
    "show_dragonriding",
    "show_not_dragonriding",
}
local VIS_CONDITION_KEYS = {}
for _, key in ipairs(VIS_REPRESENTATIVE_ORDER) do
    VIS_CONDITION_KEYS[key] = true
end
CUI.VIS_CONDITION_KEYS = VIS_CONDITION_KEYS

-- Mode-row axes: one entry per condition ROW of the shared Visibility checklist, the
-- mirror of CludesUI.VIS_OPT_AXES for the option rows. show = the key that acts as a
-- conjunct under All and a disjunct under Any; hide = the veto key, which hides whenever
-- the row's condition holds, in EVERY match mode; token = the macro conditional that is
-- true while the condition holds, so a hide gate compiles to "[token] hide"; probe = the
-- same answer in Lua. luaOnly = no positive bracket form exists, so a driver-building
-- caller has to resolve the veto in Lua. combatFlip = the probe can change INSIDE combat,
-- where a driver can no longer be rewritten. group = part of the three-way group row set.
CUI.VIS_MODE_AXES = {
    {
        show = "in_combat",
        hide = "hide_in_combat",
        token = "combat",
        probe = function(status) return status.inCombat and true or false end,
    },
    {
        show = "out_of_combat",
        hide = "hide_out_of_combat",
        token = "nocombat",
        probe = function(status) return not status.inCombat end,
    },
    {
        show = "in_raid",
        hide = "hide_in_raid",
        token = "group:raid",
        group = true,
        probe = function(status) return status.inRaid and true or false end,
    },
    -- [group:party] alone is TRUE inside a raid; nogroup:raid narrows it to a real party,
    -- exactly as the driver compilers below do for the show lane.
    {
        show = "in_party",
        hide = "hide_in_party",
        token = "group:party,nogroup:raid",
        group = true,
        probe = function(status, caps)
            if status.inParty then return true end
            return (caps and caps.partyIncludesRaid and status.inRaid) and true or false
        end,
    },
    {
        show = "solo",
        hide = "hide_solo",
        token = "nogroup",
        group = true,
        probe = function(status) return not status.inRaid and not status.inParty end,
    },
    {
        show = "show_dragonriding",
        hide = "hide_dragonriding",
        token = "advflyable,flying",
        combatFlip = true,
        probe = function() return CUI.IsAirborneSkyriding() end,
    },
    -- NOT(advflyable AND flying) has no single positive bracket, so this veto is the one
    -- mode lane a secure driver cannot carry; it is resolved in Lua at build time.
    -- Under Match ANY only, that means the combat escape hatch: entering combat on the
    -- ground reveals the element until the next out-of-combat rebuild. Under All it folds
    -- into an "advflyable,flying," conjunct and stays live, as does the same intent
    -- written as Show on Skyriding (Airborne). A gate would need a two-bracket clause
    -- ("[noadvflyable][noflying] hide; ") rather than the single `token` here, and whether
    -- [noadvflyable] parses is NOT established: macro conditionals are C-side and in no
    -- Lua source. Confirm it in game before widening this on the assumption alone.
    {
        show = "show_not_dragonriding",
        hide = "hide_not_dragonriding",
        luaOnly = true,
        combatFlip = true,
        probe = function() return not CUI.IsAirborneSkyriding() end,
    },
}

-- The seven hide keys as a flat list for the set walks below, and as a lookup for
-- callers that have to tell a veto lane from a show lane (the options checklist).
local VIS_MODE_HIDE = {}
CUI.VIS_MODE_HIDE_KEYS = {}
for idx = 1, #CUI.VIS_MODE_AXES do
    VIS_MODE_HIDE[idx] = CUI.VIS_MODE_AXES[idx].hide
    CUI.VIS_MODE_HIDE_KEYS[VIS_MODE_HIDE[idx]] = true
end

-- Keys allowed inside a visibilityModes set: the seven conditions, their seven hide
-- lanes, plus mouseover (the hover-gate). Never/Always stay exclusive scalars. Hide keys
-- deliberately stay out of VIS_CONDITION_KEYS / VIS_REPRESENTATIVE_ORDER: a veto lane has
-- no legacy scalar representation, so it can only ever live inside a stored set.
local VIS_COMBINABLE_KEYS = { mouseover = true }
for _, key in ipairs(VIS_REPRESENTATIVE_ORDER) do
    VIS_COMBINABLE_KEYS[key] = true
end
for idx = 1, #VIS_MODE_HIDE do
    VIS_COMBINABLE_KEYS[VIS_MODE_HIDE[idx]] = true
end
CUI.VIS_COMBINABLE_KEYS = VIS_COMBINABLE_KEYS

-- An override session can only carry one of the three EXCLUSIVE states, and it
-- REPLACES the element's whole Visibility configuration instead of merging with it:
-- while this key holds a value, the legacy scalar, the mode set, the match mode and
-- every option lane are ignored. Absent -- every normal profile -- it changes nothing.
-- A plain scalar on purpose, so the override value system captures and restores it
-- like any other setting, and clearing it is an ordinary revert.
local VIS_OVERRIDE_VALUES = { never = true, always = true, mouseover = true }

function CUI.VisOverrideValue(storage)
    if not storage then return nil end
    local val = storage.visibilityOverride
    return VIS_OVERRIDE_VALUES[val] and val or nil
end

-- Same validation for a caller holding the raw value rather than the store: the options
-- row reads it through the module's own fan-out hooks (Resource Bars mirrors one control
-- onto three bar stores), which hand back a value, not a table.
function CUI.VisOverrideNormalize(val) return VIS_OVERRIDE_VALUES[val] and val or nil end

-- True when the set carries at least one mode hide lane.
local function VisHasModeHide(visModes)
    for idx = 1, #VIS_MODE_HIDE do
        if visModes[VIS_MODE_HIDE[idx]] then return true end
    end
    return false
end

-- Airborne skyriding predicate shared by CheckVisibilityMode's dragonriding
-- branches and the multi-select engine. Mirrors the secure driver's
-- [advflyable,flying]: glide capability plus airborne, and nothing else.
-- An IsMounted() term used to sit here, which made every non-secure module
-- disagree with the secure Action Bars driver in a flight form (Druid and
-- Haranir flight forms are shapeshifts, not mounts, so IsMounted() is false
-- while [advflyable] still matches).
function CUI.IsAirborneSkyriding()
    if not (IsFlying and IsFlying()) then return false end
    if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
        local _, canGlide = C_PlayerInfo.GetGlidingInfo()
        return canGlide == true
    end
    -- No capability API to consult: keep the old mounted heuristic rather
    -- than count ordinary (non-skyriding) flight as dragonriding.
    return (IsMounted and IsMounted()) and true or false
end

local function VisRepresentative(modes)
    -- A hover-gated set is represented by "mouseover": downgrades keep the
    -- closest UX (hover-only everywhere), and every legacy scalar reader
    -- (mouseoverEnabled derivation, hover handlers, the poll) engages.
    if modes.mouseover then return "mouseover" end
    for idx = 1, #VIS_REPRESENTATIVE_ORDER do
        local key = VIS_REPRESENTATIVE_ORDER[idx]
        if modes[key] then return key end
    end
    return nil
end

-- Returns the store's visibilityModes table when it is authoritative, else nil
-- (legacy scalar authoritative). A non-empty set is authoritative only while the
-- legacy scalar still equals its canonical representative: the shared setter always
-- writes the pair together, so a mismatch proves an out-of-band scalar write (e.g. a
-- Visibility change made on an older addon version) that must win. Stale sets are
-- ignored, never wiped -- a transient partial state (profile sync applying keys one
-- by one) heals itself once both keys arrive.
-- ignoreOverride: read the SHARED selection even while an override applies. The options
-- checklist, the sync-icon compare and the sync copy all edit or compare the shared value
-- (the override is a separate marker they never touch), so hiding the set from them made
-- the row render a bare scalar and the next click write that rump back over the stored
-- set. Evaluators and driver compilers pass nothing and keep the replacing behaviour.
local function ActiveModes(storage, legacyKey, ignoreOverride)
    -- An override replaces the whole configuration, the stored set included.
    if not ignoreOverride and CUI.VisOverrideValue(storage) then return nil end
    local visModes = storage.visibilityModes
    if type(visModes) ~= "table" then return nil end
    local rep = VisRepresentative(visModes)
    local scalarMode = storage[legacyKey]
    if not rep then
        -- Hide-only set: a veto lane has no scalar of its own, so the pair the setter
        -- writes is "always" plus the set. The heal rule still applies -- any other
        -- scalar proves an out-of-band write that must win.
        if not VisHasModeHide(visModes) then return nil end
        if scalarMode ~= nil and scalarMode ~= "always" then return nil end
        return visModes
    end
    if scalarMode ~= nil and scalarMode ~= rep then return nil end
    return visModes
end

-- Public heal-aware read of the raw set: returns the authoritative
-- visibilityModes table or nil (used by the Action Bars macro compiler).
function CUI.GetActiveVisibilityModes(storage, legacyKey)
    if not storage then return nil end
    return ActiveModes(storage, legacyKey)
end

-- True when the selection can flip purely because combat started or ended.
-- Consumers whose Show()/Hide() is protected need this: those transitions are
-- delivered inside combat lockdown (PLAYER_REGEN_DISABLED already reports
-- InCombatLockdown), so a protected updater has to switch to an unprotected
-- mechanism for them rather than skip the update.
function CUI.VisDependsOnCombat(storage, legacyKey)
    if not storage then return false end
    -- None of the three override states can flip on a combat edge.
    if CUI.VisOverrideValue(storage) then return false end
    local visModes = ActiveModes(storage, legacyKey)
    if visModes then
        return (
            visModes.in_combat
            or visModes.out_of_combat
            or visModes.hide_in_combat
            or visModes.hide_out_of_combat
        )
                and true
            or false
    end
    local scalarMode = storage[legacyKey]
    return scalarMode == "in_combat" or scalarMode == "out_of_combat"
end

-- Read view: the current selection as a set (always freshly allocated).
-- Second return is true when a multi-selection is active. ignoreOverride: see ActiveModes
-- -- the options row passes it, because it edits the shared value an override replaces.
function CUI.GetVisibilitySelection(storage, legacyKey, ignoreOverride)
    local picked = {}
    if not storage then
        picked.always = true
        return picked, false
    end
    local visModes = ActiveModes(storage, legacyKey, ignoreOverride)
    if visModes then
        for key in pairs(visModes) do
            if VIS_COMBINABLE_KEYS[key] then picked[key] = true end
        end
        return picked, true
    end
    picked[storage[legacyKey] or "always"] = true
    return picked, false
end

-- The single write path. Normalizes the selection, writes the legacy scalar (via
-- applyScalarFn when the module's scalar write has side effects, e.g. Action Bars'
-- VisibilityCompat.ApplyMode), and assigns or clears visibilityModes. A fresh table is
-- assigned on every multi write (never mutated in place): profile sync, Myslot backups,
-- and spec-override snapshots may hold references to the previous table.
function CUI.SetVisibilitySelection(storage, legacyKey, chosen, applyScalarFn)
    if not storage then return end
    local conditions = {}
    local total = 0
    for idx = 1, #VIS_REPRESENTATIVE_ORDER do
        local key = VIS_REPRESENTATIVE_ORDER[idx]
        if chosen[key] then
            conditions[key] = true
            total = total + 1
        end
    end
    -- Hide lanes ride along in the same set. They never contribute to `count`: that
    -- counts the keys a scalar could represent, and a veto lane cannot be one.
    local hideCount = 0
    for idx = 1, #VIS_MODE_HIDE do
        local key = VIS_MODE_HIDE[idx]
        if chosen[key] then
            conditions[key] = true
            hideCount = hideCount + 1
        end
    end
    local hasMouseover = chosen.mouseover and true or false
    local scalarMode
    if total == 0 then
        -- Pure special (or empty -> Always). Conditions win over never/always when both
        -- appear; the checklist enforces that on click, this is defense in depth.
        if chosen.never then
            scalarMode = "never"
        elseif hasMouseover then
            scalarMode = "mouseover"
        else
            scalarMode = "always"
        end
    elseif hasMouseover then
        -- Hover-gated conditions: the set carries mouseover alongside the conditions
        -- and the scalar reads "mouseover" so every legacy mouseover mechanism engages.
        scalarMode = "mouseover"
    else
        scalarMode = VisRepresentative(conditions)
    end
    -- Whenever the scalar reads "mouseover" the set has to carry it too, or the pair
    -- would not match and ActiveModes would drop the set, hide lanes included.
    if scalarMode == "mouseover" then conditions.mouseover = true end
    if applyScalarFn then
        applyScalarFn(storage, scalarMode)
    else
        storage[legacyKey] = scalarMode
    end
    -- A set is stored for >=2 conditions, for any condition + mouseover (which cannot
    -- collapse to a single scalar), and for any hide lane (which has no scalar at all).
    -- Never is terminal, so nothing is stored alongside it.
    local storeSet = scalarMode ~= "never" and (total >= 2 or (total >= 1 and hasMouseover) or hideCount >= 1)
    storage.visibilityModes = storeSet and conditions or nil
    -- Direct belt for the shared Visibility widget: a mouseover-mode edit
    -- must re-arm the scan without waiting for a dispatcher event.
    _moGen = _moGen + 1
end

-- Per-axis verdicts for the three mode axes: (constrained, passed). state = { inCombat,
-- inRaid, inParty }, inParty = party-exclusive-of-raid; caps.partyIncludesRaid widens
-- in_party to raids (no caller sets it). An empty or fully-checked axis is never counted.
-- stopAt "fail" returns at the first failing axis, "any" at the first passing one; the
-- undercounted `constrained` is safe because both callers stop reading it there.
function CUI.TallyVisibilityModeAxes(chosen, status, caps, stopAt)
    local incRaid = caps and caps.partyIncludesRaid
    local isConstrained, passes = 0, 0

    -- Combat axis
    local c1, c2 = chosen.in_combat, chosen.out_of_combat
    if c1 and not c2 then
        isConstrained = isConstrained + 1
        if status.inCombat then passes = passes + 1 end
    elseif c2 and not c1 then
        isConstrained = isConstrained + 1
        if not status.inCombat then passes = passes + 1 end
    end

    if stopAt == "fail" and passes < isConstrained then return isConstrained, passes end
    if stopAt == "any" and passes > 0 then return isConstrained, passes end

    -- Group axis (the three items are ONE axis, OR'd together)
    local g1, g2, g3 = chosen.in_raid, chosen.in_party, chosen.solo
    if (g1 or g2 or g3) and not (g1 and g2 and g3) then
        isConstrained = isConstrained + 1
        local pass = false
        if g1 and status.inRaid then pass = true end
        if not pass and g2 and (status.inParty or (incRaid and status.inRaid)) then pass = true end
        if not pass and g3 and not status.inRaid and not status.inParty then pass = true end
        if pass then passes = passes + 1 end
    end

    if stopAt == "fail" and passes < isConstrained then return isConstrained, passes end
    if stopAt == "any" and passes > 0 then return isConstrained, passes end

    -- Dragonriding axis
    local d1, d2 = chosen.show_dragonriding, chosen.show_not_dragonriding
    if (d1 or d2) and not (d1 and d2) then
        isConstrained = isConstrained + 1
        local dr = CUI.IsAirborneSkyriding()
        if (d1 and dr) or (d2 and not dr) then passes = passes + 1 end
    end

    return isConstrained, passes
end

-- Default "all" match: every constrained axis has to pass. Public entry point (other
-- files evaluate mode sets with it).
function CUI.EvalVisibilityModes(chosen, status, caps)
    -- A checked Hide lane vetoes in every match mode. Under All that is equivalent to the
    -- AND-conjunct of the negated condition the tally already computes for the opposite
    -- SHOW key, so selections without hide lanes -- every pre-existing one -- are
    -- unaffected by this gate.
    if CUI.VisModeHideVeto(chosen, status, caps) then return false end
    local isConstrained, passes = CUI.TallyVisibilityModeAxes(chosen, status, caps, "fail")
    return isConstrained == passes
end

-- Module-facing dispatcher. Returns a value when the multi-select engine
-- owns the decision -- an authoritative visibilityModes set, or a
-- dragonriding scalar (so both dragonriding modes work in every module
-- through this one path) -- or nil when the caller's legacy evaluation
-- should run untouched, byte-identical. Owned results:
--   true        show
--   false       hide
--   "mouseover" hover-gated: conditions pass, reveal on hover only (the
--               caller's existing mouseover mechanism does the revealing;
--               a failing set returns plain false, hover included)
local _dispatchState = {} -- reused; filled per call when no state is passed

local function FillDispatchState()
    local inRaid = IsInRaid()
    _dispatchState.inCombat = _inCombat
    _dispatchState.inRaid = inRaid
    _dispatchState.inParty = IsInGroup() and not inRaid
    return _dispatchState
end

-- Hide-lane veto for the mode rows, the mirror of CludesUI.VisOptionHideVeto for the
-- option rows: Match Mode governs how the SHOW side combines, a checked Hide lane always
-- hides. filter: nil walks every axis, "luaOnly" only the ones a secure driver cannot
-- express, "driver" only the ones it can. Both lanes of one row checked counts as
-- unconstrained, the same rule the option tally uses. Second return: the firing axis is
-- combatFlip, so a driver-building caller must bake a combat escape hatch.
function CUI.VisModeHideVeto(picked, status, caps, filter)
    if not picked then return false end
    local axisList = CUI.VIS_MODE_AXES
    for idx = 1, #axisList do
        local ax = axisList[idx]
        local skip = (filter == "luaOnly" and not ax.luaOnly) or (filter == "driver" and ax.luaOnly)
        if not skip and picked[ax.hide] and not picked[ax.show] then
            status = status or FillDispatchState()
            if ax.probe(status, caps) then return true, ax.combatFlip or false end
        end
    end
    return false
end

-- Any match: every constrained axis is a disjunct; mode axes and option SHOW lanes tally
-- TOGETHER (CheckVisibilityOptions steps aside for such a store, except for its hide
-- veto). _anySel is a reused scalar view so a single stored mode costs no allocation per
-- dispatcher event.
local _anySel, _anySelKey = {}, nil

local function EvalAnyMatch(storage, legacyKey, visModes, status, caps)
    local picked = visModes
    if not picked then
        if _anySelKey then _anySel[_anySelKey] = nil end
        _anySelKey = storage[legacyKey] or "always"
        _anySel[_anySelKey] = true
        picked = _anySel
    end
    -- Never stays terminal: an exclusive scalar is not an axis, so no other lane can
    -- out-vote it.
    if picked.never then return false end
    -- So is a firing Hide lane: the match mode governs how the SHOW side combines, a
    -- Hide lane always hides. Mouseover included -- a hover must not reveal what a Hide
    -- lane hid (same rule as UF-3 in VisibilityCombineOr_MasterBriefing.md).
    if CUI.VisOptionHideVeto(storage) then return false end
    status = status or FillDispatchState()
    -- Same rule for the mode rows' Hide lanes.
    if CUI.VisModeHideVeto(picked, status, caps) then return false end
    local isConstrained, passes = CUI.TallyVisibilityModeAxes(picked, status, caps, "any")
    -- One passing disjunct settles it; the option probes (instance, housing, the druid
    -- form walk) only run when no mode axis passed.
    if passes == 0 and CUI.TallyVisibilityOptionAxes then
        local optC, optP = CUI.TallyVisibilityOptionAxes(storage)
        isConstrained, passes = isConstrained + optC, passes + optP
    end
    -- Nothing constrained at all reads as Always, exactly as it does under All.
    local pass = (isConstrained == 0) or (passes > 0)
    -- Mouseover is a disjunct in its own right under Any, not a gate on top of the
    -- others: a passing condition shows outright (no hover needed), and a set that
    -- constrains nothing but mouseover -- or whose other conditions all fail -- stays
    -- hover-revealable instead of hiding outright.
    if picked.mouseover then return (passes > 0) and true or "mouseover" end
    return pass
end

function CUI.EvalVisibilityExtended(storage, legacyKey, status, caps)
    if not storage then return nil end
    -- An applied override settles it alone: this is the one path every Lua consumer
    -- runs through, so the three states reach all of them without a per-module edit.
    local shade = CUI.VisOverrideValue(storage)
    if shade then
        if shade == "never" then return false end
        if shade == "mouseover" then return "mouseover" end
        return true
    end
    local visModes = ActiveModes(storage, legacyKey)
    -- Any owns the whole verdict (option lanes included, even with no mode set). The one
    -- case handed back is a legacy ORPHAN scalar: the caller's chain resolves the mode
    -- and the option lanes stop applying; the Visibility row locks Match Mode while an
    -- orphan is stored so that state is unreachable from the UI.
    if storage.visibilityMatch == "any" then
        local scalarMode = storage[legacyKey]
        if
            visModes
            or scalarMode == nil
            or VIS_CONDITION_KEYS[scalarMode]
            or scalarMode == "never"
            or scalarMode == "always"
            or scalarMode == "mouseover"
        then
            return EvalAnyMatch(storage, legacyKey, visModes, status, caps)
        end
    end
    if not visModes then
        local scalarMode = storage[legacyKey]
        if scalarMode == "show_dragonriding" then
            return CUI.IsAirborneSkyriding()
        elseif scalarMode == "show_not_dragonriding" then
            return not CUI.IsAirborneSkyriding()
        end
        return nil
    end
    status = status or FillDispatchState()
    local pass = CUI.EvalVisibilityModes(visModes, status, caps)
    if visModes.mouseover then return pass and "mouseover" or false end
    return pass
end

-- Hover-eligibility for the mouseover poll and hover handlers: true when
-- the element should currently reveal on hover. Legacy single "mouseover"
-- keeps its historical behavior (scalar check only); a hover-gated set
-- additionally requires its condition axes to pass right now.
function CUI.VisWantsMouseover(storage, legacyKey, status, caps)
    if not storage then return false end
    local shade = CUI.VisOverrideValue(storage)
    if shade then return shade == "mouseover" end
    -- Under Any the hover gate arms only while the disjunction (option lanes included)
    -- passes, so the verdict comes from the one evaluator that sees both halves.
    if storage.visibilityMatch == "any" then
        return CUI.EvalVisibilityExtended(storage, legacyKey, status, caps) == "mouseover"
    end
    local visModes = ActiveModes(storage, legacyKey)
    if visModes then
        if not visModes.mouseover then return false end
        return CUI.EvalVisibilityExtended(storage, legacyKey, status, caps) == "mouseover"
    end
    return storage[legacyKey] == "mouseover"
end

-- Set-aware equality for the sync icons: compares the effective selection of
-- two stores (multi set vs multi set, else scalar vs scalar). The SHARED selection on
-- both sides (ignoreOverride): the icon reports whether the copy would make them equal,
-- and a copy carries the shared value, never the per-spec override marker.
function CUI.VisSelectionEquals(a, aKey, b, bKey)
    if not a or not b then return false end
    if (a.visibilityMatch == "any") ~= (b.visibilityMatch == "any") then return false end
    local ma = ActiveModes(a, aKey, true)
    local mb = ActiveModes(b, bKey, true)
    if ma or mb then
        if not (ma and mb) then return false end
        for key in pairs(ma) do
            if VIS_COMBINABLE_KEYS[key] and not mb[key] then return false end
        end
        for key in pairs(mb) do
            if VIS_COMBINABLE_KEYS[key] and not ma[key] then return false end
        end
        return true
    end
    return (a[aKey] or "always") == (b[bKey] or "always")
end

-------------------------------------------------------------------------------
--  Secure driver compiler
--  Compiles a set into macro-conditional grammar (comma = AND inside a
--  bracket, bracket groups = OR) for RegisterAttributeDriver
--  "state-visibility" drivers. Shared by the Action Bars drivers and the
--  Unit Frames condition drivers.
-------------------------------------------------------------------------------

-- Returns the AND-term string shared by every bracket group (with trailing comma, or
-- "") plus the leading unconditional hide gate used for a lone negated dragon axis (""
-- when unused; the same technique the callers' hide-prefix gates already use -- no
-- negated-flying tokens needed). Non-axis keys (mouseover) are ignored. OR within an
-- axis, AND across axes; a saturated or empty axis contributes nothing.
function CUI.BuildVisModeConjuncts(visModes)
    local conjunction, negGate = "", ""
    -- Hide lanes are vetoes, but under All a veto is exactly the AND-conjunct of the
    -- negated condition, so each one folds into the term its opposite SHOW lane already
    -- emits instead of needing a gate of its own. A lane whose OWN row also has its Show
    -- box set is skipped, the same rule VisModeHideVeto applies, so the two never fold
    -- into a term the Lua verdict does not agree with.
    local hc1 = visModes.hide_in_combat and not visModes.in_combat
    local hc2 = visModes.hide_out_of_combat and not visModes.out_of_combat
    local hd1 = visModes.hide_dragonriding and not visModes.show_dragonriding
    local hd2 = visModes.hide_not_dragonriding and not visModes.show_not_dragonriding
    -- Both Hide lanes of one axis: every state is vetoed. Folding them would cancel out
    -- and read as a saturated (unconstrained) axis, while the Lua veto hides everywhere.
    -- An unconditional leading clause is the honest compilation; both compilers prepend
    -- negGate, so it wins as the first matching clause.
    if (hc1 and hc2) or (hd1 and hd2) then return "", "hide; " end
    local d1 = visModes.show_dragonriding or hd2
    local d2 = visModes.show_not_dragonriding or hd1
    if d1 and not d2 then
        conjunction = conjunction .. "advflyable,flying,"
    elseif d2 and not d1 then
        negGate = "[advflyable,flying] hide; "
    end
    local c1 = visModes.in_combat or hc2
    local c2 = visModes.out_of_combat or hc1
    if c1 and not c2 then
        conjunction = conjunction .. "combat,"
    elseif c2 and not c1 then
        conjunction = conjunction .. "nocombat,"
    end
    return conjunction, negGate
end

-- Leading hide gates for the macro-expressible mode Hide lanes, the mirror of
-- BuildVisOptHideGates below. `which` = "group" limits the walk to the three group rows,
-- which is all the All-match compiler needs (it folds the combat and dragon lanes into
-- its conjuncts above). The luaOnly lane has no token and is never emitted here.
-- Returns the gate string and how many gates it holds.
function CUI.BuildVisModeHideGates(visModes, which)
    local result, num = "", 0
    local axisList = CUI.VIS_MODE_AXES
    for idx = 1, #axisList do
        local ax = axisList[idx]
        if ax.token and (which ~= "group" or ax.group) and visModes[ax.hide] and not visModes[ax.show] then
            result = result .. "[" .. ax.token .. "] hide; "
            num = num + 1
        end
    end
    return result, num
end

-- Compiles the driver tail appended after `prefix` (caller-supplied leading hide gates:
-- unit existence, pet battle, vehicle, option clauses...). Group-axis disjuncts
-- distribute into separate bracket groups, each carrying the shared AND terms. in_raid
-- and in_party are disjoint -- checking In Party alone does not also show in a raid
-- group; In Raid Group must be checked separately for that.
function CUI.BuildVisibilityDriverString(prefixText, visModes)
    local conjunction, negGate = CUI.BuildVisModeConjuncts(visModes)
    -- The group rows' Hide lanes cannot fold into `conj` (their show side distributes
    -- into separate bracket groups), so they lead as gates. Under All that is the same
    -- verdict either way -- a hide clause and an AND term both veto.
    prefixText = prefixText .. negGate .. CUI.BuildVisModeHideGates(visModes, "group")

    local g1, g2, g3 = visModes.in_raid, visModes.in_party, visModes.solo
    if (g1 or g2 or g3) and not (g1 and g2 and g3) then
        local result = prefixText
        local emitted = {}
        local function emitToken(tok)
            if emitted[tok] then return end
            emitted[tok] = true
            result = result .. "[" .. conjunction .. tok .. "] show; "
        end
        if g1 then emitToken("group:raid") end
        -- [group:party] alone is TRUE inside a raid; nogroup:raid narrows the
        -- party disjunct to a real party (a separate group:raid clause, when
        -- In Raid Group is also checked, still shows there).
        if g2 then emitToken("group:party,nogroup:raid") end
        if g3 then emitToken("nogroup") end
        return result .. "hide"
    end

    if conjunction == "" then
        -- All axes saturated/empty: Always-equivalent (negGate, when
        -- present, still hides while dragonriding).
        return prefixText .. "show"
    end
    return prefixText .. "[" .. conjunction:sub(1, -2) .. "] show; hide"
end

-- Any-match tail: one bracket group per constrained axis (adjacent groups OR in macro
-- grammar). `opts` = the option lanes the driver can express (Lua-only ones are the
-- caller's); `wrap` = tokens every bracket must carry (Pet Bar); `extraConstrained` =
-- axes decided outside this string, so a Lua-only-constrained selection compiles to hide.
-- `hasMouseover` = the selection also carries the hover-gate: this compiler cannot
-- express mouseover as a macro token, so every branch that would otherwise HIDE the
-- frame outright falls back to showing it instead -- a hard-hidden secure frame can
-- never be revealed again by the unprotected Lua hover poll. The alpha layer (outside
-- this compiler) is what actually decides full opacity vs. hover-gated 0 from there.
function CUI.BuildVisibilityDriverStringAny(
    prefixText,
    visModes,
    options,
    extraConstrained,
    wrap,
    hasMouseover,
    forceShow
)
    visModes, options, wrap = visModes or {}, options or {}, wrap or ""
    local lead = (wrap ~= "") and (wrap .. ",") or ""
    local result, axisList = "", 0
    -- Hide lanes are vetoes, not disjuncts: they lead the whole string. Mode rows and
    -- option rows follow the same rule, so both gate sets are emitted here.
    local modeGates, modeGateCount = CUI.BuildVisModeHideGates(visModes)
    local gates, gateCount = CUI.BuildVisOptHideGates(options)
    prefixText = prefixText .. modeGates .. gates
    gateCount = gateCount + modeGateCount
    -- A show lane whose macro token cannot see what its probe sees (druid travel form vs.
    -- [mounted]): the disjunction is settled, but the gates above still apply.
    if forceShow then
        return prefixText .. ((wrap ~= "") and ("[" .. wrap .. "] show; hide") or "show"), 0, gateCount
    end
    local emitted = {}
    local function emitToken(tok)
        if emitted[tok] then return end
        emitted[tok] = true
        result = result .. "[" .. lead .. tok .. "] show; "
    end

    -- Combat axis
    local c1, c2 = visModes.in_combat, visModes.out_of_combat
    if c1 and not c2 then
        axisList = axisList + 1
        emitToken("combat")
    elseif c2 and not c1 then
        axisList = axisList + 1
        emitToken("nocombat")
    end

    -- Group axis: three items, ONE axis, already OR'd among themselves.
    local g1, g2, g3 = visModes.in_raid, visModes.in_party, visModes.solo
    if (g1 or g2 or g3) and not (g1 and g2 and g3) then
        axisList = axisList + 1
        if g1 then emitToken("group:raid") end
        -- [group:party] alone is TRUE inside a raid; nogroup:raid narrows the party
        -- disjunct to a real party, same as the all-match tail does.
        if g2 then emitToken("group:party,nogroup:raid") end
        if g3 then emitToken("nogroup") end
    end

    -- Option axes with a macro conditional of their own. SHOW lanes only: their Hide
    -- counterparts are the leading gates above, so no negated disjunct is emitted.
    if options.visOnlyMounted and not options.visHideMounted then
        axisList = axisList + 1
        emitToken("mounted")
    end
    if options.visHideNoTarget and not options.visHideWithTarget then
        axisList = axisList + 1
        emitToken("exists")
    end
    if options.visHideNoEnemy and not options.visHideWithEnemy then
        axisList = axisList + 1
        emitToken("harm")
    end

    -- Dragonriding axis. NOT(advflyable AND flying) has no single bracket form, so the
    -- negative lane becomes the TAIL: once no other disjunct matched, hide while
    -- airborne, show otherwise (first matching clause wins).
    local d1, d2 = visModes.show_dragonriding, visModes.show_not_dragonriding
    local dragonTail = false
    if d1 and not d2 then
        axisList = axisList + 1
        emitToken("advflyable,flying")
    elseif d2 and not d1 then
        axisList = axisList + 1
        dragonTail = true
    end

    local wrappedShow = (wrap ~= "") and ("[" .. wrap .. "] show; hide") or "show"
    local noMatch = hasMouseover and wrappedShow or "hide"
    if axisList == 0 then
        -- Nothing this string can decide: either nothing is constrained anywhere
        -- (Always), or the only constrained axes are Lua-only ones that all failed.
        if (extraConstrained or 0) > 0 then return prefixText .. noMatch, 0, gateCount end
        return prefixText .. wrappedShow, 0, gateCount
    end
    if dragonTail then
        -- Under mouseover the negative-dragon veto would just be dead weight: dropping
        -- it lets the trailing wrappedShow (itself the hover-gated fallback) cover the
        -- airborne case too, instead of nesting wrappedShow's own bracket/semicolons
        -- inside this clause's action slot.
        if hasMouseover then return prefixText .. result .. wrappedShow, axisList, gateCount end
        return prefixText .. result .. "[" .. lead .. "advflyable,flying] hide; " .. wrappedShow,
            axisList,
            gateCount
    end
    return prefixText .. result .. noMatch, axisList, gateCount
end

-- Leading hide gates for the macro-expressible HIDE lanes. They veto in every match
-- mode, so they precede the Any disjuncts (first matching clause wins) and are never
-- softened by the mouseover fallback: a hover must not reveal what a Hide lane hid.
-- Deliberately unwrapped -- `wrap` is an AND term of the SHOW side (Pet Bar), not
-- something a veto has to wait for. Returns the gate string and how many gates it holds.
function CUI.BuildVisOptHideGates(options)
    local result, num = "", 0
    if options.visHideMounted and not options.visOnlyMounted then
        result = result .. "[mounted] hide; "
        num = num + 1
    end
    if options.visHideWithTarget and not options.visHideNoTarget then
        result = result .. "[exists] hide; "
        num = num + 1
    end
    if options.visHideWithEnemy and not options.visHideNoEnemy then
        result = result .. "[harm] hide; "
        num = num + 1
    end
    return result, num
end

-- Two macro tokens disagree with their Lua probe: [exists] counts a soft target and
-- [mounted] cannot see druid travel/flight forms. The correction is per lane, never a
-- blanket veto that would silence the other axes:
--   show lane, token would wrongly PASS -> drop the disjunct
--   show lane, token would wrongly FAIL -> show outright
--   hide lane, gate would wrongly FIRE  -> drop the gate
--   hide lane, gate would wrongly STAY  -> hide outright (forceHide)
-- Each probe runs only when its own lanes are set (the mount one walks the druid auras).
local function AnyDriverLaneFixups(storage, edges)
    local dropKey, forceShow, forceHide = nil, false, false

    local wantsTarget = (edges and edges.softTarget)
        and (storage.visHideNoTarget or storage.visHideWithTarget)
    if wantsTarget then
        local softOnly = not UnitExists("target")
            and (UnitExists("softinteract") or UnitExists("softenemy") or UnitExists("softfriend"))
        if softOnly then
            -- Show lane: [exists] would show on the soft target the probe does not count.
            if storage.visHideNoTarget and not storage.visHideWithTarget then
                dropKey = { visHideNoTarget = true }
            -- Hide lane: the [exists] gate would hide on a soft target the probe does not
            -- count as one; drop the gate and leave the axis to the Lua veto.
            elseif storage.visHideWithTarget and not storage.visHideNoTarget then
                dropKey = { visHideWithTarget = true }
            end
        end
    end

    if storage.visOnlyMounted or storage.visHideMounted then
        local formOnly = not (IsMounted and IsMounted()) and CUI.IsPlayerMountedLike()
        if formOnly then
            -- Show lane: [mounted] misses the form the probe counts as mounted.
            if storage.visOnlyMounted and not storage.visHideMounted then
                forceShow = true
            -- Hide lane: the [mounted] gate cannot see the form, so it never fires while
            -- the probe says mounted. The caller hides and bakes the combat escape hatch.
            elseif storage.visHideMounted and not storage.visOnlyMounted then
                forceHide = true
            end
        end
    end

    return dropKey, forceShow, forceHide
end

-- Store -> Any-match driver tail, shared by Action Bars, Unit Frames and the Minimap.
-- SHOW lanes and mode axes compile to disjuncts, HIDE lanes to leading vetoes.
-- Returns tail, constrained (a LOWER BOUND: the early-outs stop counting once settled)
-- and liveAxes (axes that are LIVE macro terms in `tail`; 0 for a constant). A
-- driver-registering caller gates on liveAxes: constrained can be positive purely from
-- Lua-resolved axes, which a driver could never keep honest.
function CUI.BuildAnyMatchTail(storage, legacyKey, visModes, wrap, edges)
    wrap = wrap or ""
    -- An override replaces the selection, so the tail is a constant. Reported as one
    -- live axis: it IS a driver worth registering, and it cannot go stale (the value
    -- only changes when the override system rewrites it, which rebuilds the driver).
    local shade = CUI.VisOverrideValue(storage)
    if shade then return (shade == "never") and "hide" or "show", 1, 1 end
    -- Never is an exclusive scalar, not an axis, so nothing can out-vote it.
    if (storage[legacyKey] or "always") == "never" then return "hide", 1, 0 end

    -- Hide lanes veto in every match mode, so they settle the verdict before any
    -- disjunct is looked at. The ones this consumer cannot compile are resolved here, at
    -- build time -- as fresh as the last driver rebuild, exactly like the Lua-only show
    -- lanes below. combatFlip (mount, skyriding mount, vehicle) means the probe can flip
    -- while a driver cannot be rewritten, so those must not freeze as a dead "hide":
    -- they hide out of combat and hand the rest of the string back in combat, the same
    -- escape hatch the Action Bars "combathide" path bakes under All.
    local combatEscape = false
    if CUI.VisOptionHideVeto then
        local vetoed, vetoFlip = CUI.VisOptionHideVeto(storage, "luaOnly", edges)
        if vetoed then
            if not vetoFlip then return "hide", 1, 0 end
            combatEscape = true
        end
    end

    -- The mode rows' Hide lanes veto the same way. All but one compile to a leading gate
    -- inside BuildVisibilityDriverStringAny; hide_not_dragonriding has no positive bracket
    -- form and is resolved here, as fresh as the last driver rebuild. It is combatFlip
    -- (takeoff and landing happen mid-combat), so it always takes the escape hatch.
    if visModes and CUI.VisModeHideVeto then
        local mVetoed, mFlip = CUI.VisModeHideVeto(visModes, nil, nil, "luaOnly")
        if mVetoed then
            if not mFlip then return "hide", 1, 0 end
            combatEscape = true
        end
    end

    -- Runs before the Lua-only show lanes settle anything: its mount branch can produce a
    -- veto of its own, and a veto outranks a passing disjunct. Its probes only run when
    -- the matching lanes are set.
    local dropKey, forceShow, forceHide = AnyDriverLaneFixups(storage, edges)
    if forceHide then combatEscape = true end

    -- Wraps every return below: out of combat the veto stands, in combat the compiled
    -- string decides (mode axes, prefixes and any live gate keep working there).
    local function Finish(tail, isConstrained, live)
        if combatEscape then return "[nocombat] hide; " .. tail, isConstrained + 1, live + 1 end
        return tail, isConstrained, live
    end

    local luaC, luaP = 0, 0
    if CUI.TallyVisibilityOptionAxes then
        luaC, luaP = CUI.TallyVisibilityOptionAxes(storage, "luaOnly", edges)
    end
    -- A passing Lua-only SHOW lane settles the disjunction, but it must not settle the
    -- vetoes: returning a bare "show" here would skip the compiler below, and the compiler
    -- is the only place the leading hide gates are emitted. forceShow already means exactly
    -- this -- show outright, gates intact -- so the fall-through reuses it.
    local settled = luaP > 0

    local modes = visModes
    if not modes then
        -- A single stored mode is one constrained axis, the shape a set would have.
        modes = {}
        local scalarMode = storage[legacyKey]
        if VIS_CONDITION_KEYS[scalarMode] then modes[scalarMode] = true end
    end
    -- The compiler sees only the lanes THIS consumer compiles: Lua-resolved axes are
    -- already in luaC, dropped ones still count as constrained but cannot be disjuncts.
    local axisList = CUI.VIS_OPT_AXES
    local needsFilter = dropKey ~= nil
    if not needsFilter and axisList then
        for idx = 1, #axisList do
            if CUI.VisAxisIsLuaOnly(axisList[idx], edges) then
                needsFilter = true
                break
            end
        end
    end
    local options, dropped = storage, 0
    if needsFilter then
        options = {}
        for idx = 1, #axisList do
            local ax = axisList[idx]
            if not CUI.VisAxisIsLuaOnly(ax, edges) then
                if dropKey and (dropKey[ax.show] or dropKey[ax.hide]) then
                    -- A dropped SHOW lane is still a constrained disjunct this string
                    -- cannot decide; a dropped HIDE gate is a veto that is NOT firing,
                    -- which constrains nothing at all.
                    if dropKey[ax.show] then dropped = dropped + 1 end
                else
                    options[ax.show] = storage[ax.show]
                    options[ax.hide] = storage[ax.hide]
                end
            end
        end
    end
    local hasMouseover = (visModes and visModes.mouseover) or (storage[legacyKey] == "mouseover") or false
    local tail, axisList, gates = CUI.BuildVisibilityDriverStringAny(
        "",
        modes,
        options,
        luaC + dropped,
        wrap,
        hasMouseover,
        forceShow or settled
    )
    -- liveAxes counts the gates too: a string that carries nothing but "[mounted] hide"
    -- is still a live driver worth registering.
    return Finish(tail, axisList + luaC + dropped, axisList + gates)
end

-- Set-aware copy for the sync icons. dstCaps.noGroupModes strips group-axis
-- items the target cannot express (Pet Bar); the stripped selection
-- re-normalizes through the setter (a now-single selection collapses to the
-- scalar, a now-empty one becomes Always). applyScalarFn runs the target
-- module's scalar side effects, same contract as SetVisibilitySelection.
function CUI.VisCopySelection(dst, source, legacyKey, dstCaps, applyScalarFn)
    if not dst or not source then return end
    -- The match travels with every copy, mode-only ones included.
    dst.visibilityMatch = (source.visibilityMatch == "any") and "any" or nil
    -- The shared selection, not what an override on the source currently replaces it with.
    local ms = ActiveModes(source, legacyKey, true)
    if ms then
        local picked = {}
        for key in pairs(ms) do
            if VIS_COMBINABLE_KEYS[key] then picked[key] = true end
        end
        if dstCaps and dstCaps.noGroupModes then
            picked.in_raid, picked.in_party, picked.solo = nil, nil, nil
            picked.hide_in_raid, picked.hide_in_party, picked.hide_solo = nil, nil, nil
        end
        if dstCaps and dstCaps.noMouseover then picked.mouseover = nil end
        CUI.SetVisibilitySelection(dst, legacyKey, picked, applyScalarFn)
        return
    end
    -- Legacy single value: copy the raw scalar (orphan values included,
    -- matching the pre-rework copy behavior) and clear any stale set.
    local scalarMode = source[legacyKey] or "always"
    if applyScalarFn then
        applyScalarFn(dst, scalarMode)
    else
        dst[legacyKey] = scalarMode
    end
    dst.visibilityModes = nil
end

-- The unified Visibility row puts the mode selection and the option booleans behind
-- ONE control, so its sync icon copies and compares both halves at once. These two
-- wrap the existing mode-only pair; callers that still build the legacy two-dropdown
-- layout keep using VisCopySelection / VisSelectionEquals with their own option loop.
function CUI.VisFullCopy(dst, source, legacyKey, dstCaps, applyScalarFn)
    if not dst or not source then return end
    CUI.VisCopySelection(dst, source, legacyKey, dstCaps, applyScalarFn)
    local keyList = CUI.VIS_OPT_KEYS
    if not keyList then return end
    for idx = 1, #keyList do
        local key = keyList[idx]
        dst[key] = source[key] or nil
    end
end

-- True when the store has ANY visibility option lane set. Callers gate work on this:
-- event passes that would otherwise be skipped, hover keep-shown, drag surfacing. A
-- hand-written subset here is exactly how a newly added lane silently stops working, so
-- this always walks VIS_OPT_KEYS rather than naming fields.
function CUI.VisHasAnyOption(storage)
    if not storage then return false end
    local keyList = CUI.VIS_OPT_KEYS
    if not keyList then return false end
    for idx = 1, #keyList do
        if storage[keyList[idx]] then return true end
    end
    return false
end

function CUI.VisFullEquals(a, aKey, b, bKey)
    if not a or not b then return false end
    if not CUI.VisSelectionEquals(a, aKey, b, bKey) then return false end
    local keyList = CUI.VIS_OPT_KEYS
    if not keyList then return true end
    for idx = 1, #keyList do
        local key = keyList[idx]
        if (a[key] or false) ~= (b[key] or false) then return false end
    end
    return true
end
