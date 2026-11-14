if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Widgets_Visibility.lua
--  Unified visibility row and its checklist. Builds on the checkbox
--  dropdown, so it loads after CludesUI_Widgets_CheckboxDropdowns.lua.
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI

-- The options page pool (CludesUI_FramePool.lua, the options addon's first
-- file): the row and the checklist come from the factory builders, which pool
-- what they make. This file makes no frame of its own today; the line is kept on
-- purpose, so a frame it makes later goes through the pool like the rest.
local CreateFrame = CludesUI._Pool.CreateFrame

-------------------------------------------------------------------------------
--  Unified Visibility Row (opts contract for the 10 module callers)
--  ONE control replacing the "Visibility" + "Visibility Options" pair. Every condition is
--  an AXIS with a Show and a Hide lane: Show means the axis must match, Hide means it must
--  not, the two lanes are mutually exclusive per axis, an unconstrained axis imposes
--  nothing, and axes AND together. The three group rows stay ONE OR-group, as the mode
--  engine in CludesUI_Visibility.lua already evaluates them. Storage stays split (mode
--  axes through the shared engine, option axes as existing per-axis booleans) -- no
--  evaluator, secure driver, profile sync or spec-override path changes; only lanes with no
--  prior counterpart use a new key (CludesUI.VIS_OPT_KEYS).
--  opts = {
--      getStore/legacyKey  = store accessor + scalar key (required)
--      getStores           = optional fn() -> array of every store this control writes the
--                            override marker to, getStore()'s first (Resource Bars drives
--                            health/primary/secondary from one row). Defaults to that one
--                            store; the marker replaces the shared value, so it has to
--                            reach exactly the stores that value does.
--      caps                = { noMouseover, noGroupModes, noOverrideMouseover,
--                              luaDragonriding, lockedTooltips }
--      applyScalarFn       = optional fn(store, mode) for scalar side effects
--      getOption/setOption = optional fn(key)/fn(key, value) when option booleans live
--                            outside getStore() (Resource Bars writes three stores)
--      trueDefaultOpts     = optional set { [visOptKey] = true, ... } for opt-axis keys whose
--                            shipped DEFAULTS value is true; unchecking such a key persists an
--                            explicit false instead of nil, so DeepMergeDefaults on next login
--                            does not re-fill it back to true (the built-in CDM bars ship
--                            housing-hide on, so they need this)
--      onChanged/onOptionChanged = fired after a mode / option write (latter falls back)
--      extraItems          = { { key, label, tooltip, get, set, default }, ... } single-lane
--                            rows; a missing get/set uses the boolean getStore()[key], with
--                            `default` as its unset value (a write equal to it stores nil)
--      leftCfg             = optional DualRow config for the LEFT slot; the checklist then
--                            takes the RIGHT slot (excludes rightVis and rightCfg)
--      label/width/tooltip/disabledFn/disabledTooltip/rawTooltip/refreshPageArg
--  }
--  rightCfg: DualRow right-slot config -- the old Visibility Options dropdown's old slot,
--  now free for whatever the page needs. Returns row, height, same as W:DualRow.
-------------------------------------------------------------------------------

CludesUI.VIS_ROW_ITEMS = {
    { key = "never", label = "Never" },
    { key = "always", label = "Always" },
    {
        key = "mouseover",
        label = "Mouseover",
        tooltip = "Reveal on hover only. Combines with the conditions below: hover-reveals while they all pass, stays hidden while any fails.",
        tooltipAny = "Combines with the conditions below: shows outright once at least one passes, otherwise still reveals on hover. A checked Hide state still hides it, hover included.",
    },
    -- Modifiers, not conditions: they decide how the rows below combine, so they stay
    -- out of the summary and the Show/Hide lane pairs. Radio pair (matchValue) over one
    -- scalar: picking one unpicks the other, there is no "neither" state.
    { isHeader = true, label = "Match Mode" },
    {
        key = "matchAll",
        label = "Match All Conditions",
        modifier = true,
        matchValue = "all",
        tooltip = "Every condition you set has to match. The default.",
    },
    {
        key = "matchAny",
        label = "Match Any Condition",
        modifier = true,
        matchValue = "any",
        tooltip = "This element shows as soon as ONE Show condition matches. Hide keeps its meaning in both match modes: a checked Hide always hides, on every row.",
    },
    { isHeader = true, label = "Show", rightLabel = "Hide" },
    -- Every condition gets its own row, the inverse ones included, because a Hide lane is
    -- a veto rather than "show while this is false": without an "Out of Combat" row there
    -- would be no way left to say "show while out of combat" as one Any disjunct.
    {
        key = "combat",
        label = "In Combat",
        axis = "mode",
        show = "in_combat",
        hide = "hide_in_combat",
    },
    {
        key = "outOfCombat",
        label = "Out of Combat",
        axis = "mode",
        show = "out_of_combat",
        hide = "hide_out_of_combat",
    },
    { key = "in_raid", label = "In Raid Group", axis = "group", hide = "hide_in_raid" },
    { key = "in_party", label = "In Party", axis = "group", hide = "hide_in_party" },
    { key = "solo", label = "Solo", axis = "group", hide = "hide_solo" },
    -- `forever`: the value WoW Forever pins this condition to (that client has no
    -- skyriding and no housing), "never" or "always" true. AttachVisibilityChecklist
    -- leaves such a row out there unless a lane that still acts on that client is set
    -- (see ForeverRowHidden).
    {
        key = "skyAirborne",
        label = "Skyriding (Airborne)",
        axis = "mode",
        forever = "never",
        show = "show_dragonriding",
        hide = "hide_dragonriding",
        tooltip = "Only while AIRBORNE on a glide-capable mount or flight form. For the mount itself, ground included, use Skyriding Mount.",
    },
    {
        key = "notSkyAirborne",
        label = "Not Skyriding (Airborne)",
        axis = "mode",
        forever = "always",
        show = "show_not_dragonriding",
        hide = "hide_not_dragonriding",
        tooltip = "The exact inverse of Skyriding (Airborne): anything that is not airborne on a glide-capable mount or flight form, standing on the ground included.",
    },
    {
        key = "skyMount",
        label = "Skyriding Mount",
        axis = "opt",
        forever = "never",
        show = "visOnlySkyriding",
        hide = "visHideDragonriding",
        tooltip = "While on a glide-capable mount, ground included, where Blizzard shows its vigor HUD. Skyriding (Airborne) additionally requires you to be flying.",
    },
    {
        key = "instances",
        label = "Instances",
        axis = "opt",
        show = "visOnlyInstances",
        hide = "visHideInstances",
        tooltip = "Dungeons, raids, scenarios, arenas and battlegrounds. Garrisons do not count.",
    },
    {
        key = "dungeons",
        label = "Dungeons",
        axis = "opt",
        show = "visOnlyDungeons",
        hide = "visHideDungeons",
        tooltip = "Five-player dungeons, Mythic+ included. Delves, raids and scenarios do not count.",
    },
    {
        key = "housing",
        label = "Housing",
        axis = "opt",
        forever = "never",
        show = "visOnlyHousing",
        hide = "visHideHousing",
        tooltip = "While you are inside a house or plot.",
    },
    {
        key = "mounted",
        label = "Mounted",
        axis = "opt",
        show = "visOnlyMounted",
        hide = "visHideMounted",
        tooltip = "Druid travel, aquatic and flight forms count as mounted.",
    },
    {
        key = "target",
        label = "Target",
        axis = "opt",
        show = "visHideNoTarget",
        hide = "visHideWithTarget",
        tooltip = "*Blizzard's auto targeting (soft target) setting can cause brief flickering when your actual target dies but a soft-target is still active.",
    },
    {
        key = "enemyTarget",
        label = "Enemy Target",
        axis = "opt",
        show = "visHideNoEnemy",
        hide = "visHideWithEnemy",
        tooltip = "A target you can attack.",
    },
    {
        key = "resting",
        label = "Resting",
        axis = "opt",
        show = "visOnlyResting",
        hide = "visHideResting",
        tooltip = "While resting, in a city or at an inn.",
    },
    {
        key = "vehicle",
        label = "In Vehicle",
        axis = "opt",
        show = "visOnlyVehicle",
        hide = "visHideVehicle",
        tooltip = "While seated in a vehicle.",
    },
}

-------------------------------------------------------------------------------
--  Attaches ONE visibility checklist to a DualRow region. Split out of
--  BuildVisibilityRow so a single row can carry two independent ones (Action Bars
--  puts Micro Menu and Bag Bar visibility side by side). Callers that want the
--  standard labelled row use BuildVisibilityRow; this is the raw attach.
--  The caller must have skipped the search pre-build pass already.
-------------------------------------------------------------------------------
function CludesUI.AttachVisibilityChecklist(regionFrame, options)
    local Pix = CludesUI.PanelPP
    local caps = options.caps or {}
    local legacyKey = options.legacyKey or "visibility"
    local GROUP_KEYS = (CludesUI.VIS_AXES and CludesUI.VIS_AXES.group) or { "in_raid", "in_party", "solo" }

    -- Only the two exclusive states survive an override: the checklist writes them to
    -- the legacy scalar, which the value system can hold. Everything else lives in the
    -- mode SET, the match mode or an option lane, all excluded from it, so a session
    -- locks those rows instead of letting a click land that would be dropped.
    -- SlotOverridable, not EditSessionActive: the session flag is global, but this row
    -- also sits on pages that are excluded from the override systems (Quest Tracker,
    -- Damage Meters, the CDM Tracking Bars tab). There a picked state would write a
    -- marker the capture gates drop as blacklisted, leaving it stranded in the shared
    -- profile with nothing owning it. On those pages the row simply behaves as it does
    -- outside a session.
    local function OvSessionActive()
        return (CludesUI.SpecOverrides_SlotOverridable()) and true or false
    end
    local OV_LOCK_TIP =
        "Not overridable. These conditions are shared and can only be changed while no override is being edited. An override replaces the Visibility setting outright -- Never, Always or Mouseover -- and ignores everything set here while it applies."
    local OV_PICK_TIP =
        "Makes this the override. It replaces the whole Visibility setting, so the conditions below no longer apply while it does. Click it again to remove the override."
    -- The block carries ONE tooltip, so the module that also has to seal Mouseover
    -- says why right there instead of losing the reason to the shared text.
    local OV_LOCK_TIP_MO = OV_LOCK_TIP
        .. " Mouseover is sealed here too for this element: its hover mechanism follows the shared setting, so an override could only leave it shown."

    -- Per-module row list. `listed` collects the legacy SCALAR values this row can
    -- actually reach, so the orphan rule below only fires for genuinely foreign ones.
    local itemList, defs, listed = {}, {}, {}
    -- Defined below, forward-declared because the rows built here close over them.
    local GetMatchAny

    -- The stored scalar when it is a legacy alias this row cannot express, else nil.
    -- Read at build (the orphan's own row) and live by the Match Mode rows, which lock
    -- while an orphan is stored: Any hands an orphan back to the caller's legacy chain,
    -- which knows nothing about the option lanes. Never/Always stay clickable as the exit.
    local function OrphanScalar()
        local storage = options.getStore()
        if not storage then
            return nil
        end
        -- Shared value (ignoreOverride): an orphan is a stored SCALAR this row cannot
        -- express, and an applied override neither creates nor cures one.
        local sel, isMulti = CludesUI.GetVisibilitySelection(storage, legacyKey, true)
        if isMulti then
            return nil
        end
        local current = next(sel)
        if current and not listed[current] then
            return current
        end
        return nil
    end
    local function OrphanActive()
        return OrphanScalar() ~= nil
    end

    -- WoW Forever: a row flagged `forever` is left out unless this store has a lane on
    -- that still does something there -- the Show lane of a never-true condition (it
    -- keeps the element hidden), or either lane of an always-true one. A value that
    -- arrived with an imported profile therefore stays visible and can be cleared;
    -- every other lane of such a row is inert on that client.
    local foreverSel
    local function ForeverLaneOn(spec_def, k)
        if spec_def.axis == "opt" then
            if options.getOption then
                return options.getOption(k) == true
            end
            local storage = options.getStore()
            return (storage and storage[k]) == true
        end
        if foreverSel == nil then
            local storage = options.getStore()
            foreverSel = storage and CludesUI.GetVisibilitySelection(storage, legacyKey, true) or false
        end
        return foreverSel ~= false and foreverSel[k] == true
    end
    local function ForeverRowHidden(spec_def)
        if ForeverLaneOn(spec_def, spec_def.show) then
            return false
        end
        return not (spec_def.forever == "always" and ForeverLaneOn(spec_def, spec_def.hide))
    end

    for _, spec_def in ipairs(CludesUI.VIS_ROW_ITEMS) do
        if spec_def.isHeader then
            itemList[#itemList + 1] = spec_def
        elseif
            not (spec_def.key == "mouseover" and caps.noMouseover)
            and not (spec_def.forever and CludesUI.IS_FOREVER and ForeverRowHidden(spec_def))
        then
            local itemInfo = {
                key = spec_def.key,
                label = spec_def.label,
                tooltip = spec_def.tooltip,
                dual = spec_def.axis and true or nil,
                isModifier = spec_def.modifier,
            }
            -- Never / Always / Mouseover are the exclusive states: each one writes the
            -- legacy scalar on its own, which an override CAN hold. Everything else is
            -- the compound half.
            if spec_def.key ~= "never" and spec_def.key ~= "always" and spec_def.key ~= "mouseover" then
                itemInfo.ovLockedFn = OvSessionActive
                itemInfo.ovLockedTooltip = OV_LOCK_TIP
            elseif spec_def.key == "mouseover" and caps.noOverrideMouseover then
                -- Joins the sealed run: this row sits directly above the section header
                -- the block starts at, so it simply grows by one and stays contiguous,
                -- with Never and Always left outside it.
                itemInfo.ovLockedFn = OvSessionActive
                itemInfo.ovLockedTooltip = OV_LOCK_TIP_MO
            end
            if caps.noGroupModes and spec_def.axis == "group" then
                itemInfo.locked = true
                itemInfo.lockedTooltip = (caps.lockedTooltips and caps.lockedTooltips[spec_def.key])
                    or "This element cannot use group-based visibility."
            end
            -- Only the two airborne rows need the takeoff/landing edge; the mount row
            -- rides PLAYER_CAN_GLIDE_CHANGED, which is always registered.
            if
                caps.luaDragonriding and (spec_def.key == "skyAirborne" or spec_def.key == "notSkyAirborne")
            then
                itemInfo.lockedFn = function()
                    return not CludesUI._hasGlidingEvent
                end
                itemInfo.lockedTooltip = "Requires a client with gliding events."
            end
            if spec_def.modifier then
                itemInfo.lockedFn = OrphanActive
                itemInfo.lockedTooltip =
                    "Not available while a legacy visibility value is selected. Pick Never or Always first."
            end
            -- Rows whose tooltip states a combining rule have to restate it under Any.
            if spec_def.tooltipAny then
                itemInfo.tooltip = function()
                    return GetMatchAny() and spec_def.tooltipAny or spec_def.tooltip
                end
            end
            -- The three exclusive states behave differently inside a session, so they
            -- say so instead of showing their normal text.
            if spec_def.key == "never" or spec_def.key == "always" or spec_def.key == "mouseover" then
                local baseTip = itemInfo.tooltip
                itemInfo.tooltip = function()
                    if OvSessionActive() then
                        return OV_PICK_TIP
                    end
                    if type(baseTip) == "function" then
                        return baseTip()
                    end
                    return baseTip
                end
            end
            itemList[#itemList + 1] = itemInfo
            defs[spec_def.key] = spec_def
            if spec_def.axis == "mode" then
                listed[spec_def.show] = true
                listed[spec_def.hide] = true
            elseif spec_def.axis == "group" then
                listed[spec_def.key] = true
            elseif spec_def.modifier then
                -- Never a stored scalar, so it must not shadow the orphan rule.
            elseif not spec_def.axis then
                listed[spec_def.key] = true
            end
        end
    end

    if options.extraItems then
        for _, ex in ipairs(options.extraItems) do
            -- A missing accessor reads or writes a boolean in the checklist's own
            -- store, which never holds the row's default.
            local get, set = ex.get, ex.set
            local k, dflt = ex.key, ex.default == true
            if not get then
                get = function()
                    local storage = options.getStore()
                    local val = storage and storage[k]
                    if val == nil then
                        return dflt
                    end
                    return val == true
                end
            end
            if not set then
                set = function(val)
                    local storage = options.getStore()
                    if not storage then
                        return
                    end
                    val = val == true
                    if val == dflt then
                        storage[k] = nil
                    else
                        storage[k] = val
                    end
                end
            end
            itemList[#itemList + 1] = { key = ex.key, label = ex.label, tooltip = ex.tooltip }
            defs[ex.key] = { key = ex.key, axis = "extra", get = get, set = set }
        end
    end

    -- Legacy-orphan rule, unchanged from the old checklist: a stored scalar this row
    -- cannot reach renders as a checked entry only while it is the current value.
    do
        local current = OrphanScalar()
        if current then
            itemList[#itemList + 1] = { key = current, label = current }
            defs[current] = { key = current, orphan = true }
        end
    end

    -- Legacy group Hide encoding: before the Hide lanes had keys of their own, "Hide: In
    -- Raid Group" was stored as the other two Show lanes. Under Match All the two are
    -- equivalent, so the row keeps presenting it as the Hide lane and the next write
    -- persists the normalized form through WriteSel. Under Any they are NOT equivalent
    -- (two Show lanes are two disjuncts, a Hide lane is a veto), so those stores are left
    -- exactly as they are. Hide keys are "hide_" .. the show key, per VIS_MODE_AXES.
    local function NormalizeGroupHide(sel)
        if GetMatchAny() then
            return sel
        end
        local missing, isShown = nil, 0
        for idx = 1, #GROUP_KEYS do
            local k = GROUP_KEYS[idx]
            if sel["hide_" .. k] then
                return sel
            end
            if sel[k] then
                isShown = isShown + 1
            else
                missing = k
            end
        end
        if missing and isShown == #GROUP_KEYS - 1 then
            for idx = 1, #GROUP_KEYS do
                sel[GROUP_KEYS[idx]] = nil
            end
            sel["hide_" .. missing] = true
        end
        return sel
    end

    -- Every store the override marker has to reach. One by default; a module that drives
    -- several stores from ONE control (Resource Bars writes health/primary/secondary in
    -- lockstep) lists them all through opts.getStores, with the store opts.getStore
    -- returns first. The marker replaces the shared value, so it has to travel exactly as
    -- far as that value does, or the mirrored elements keep obeying what it took over.
    local function OvStores()
        if options.getStores then
            return options.getStores() or {}
        end
        local storage = options.getStore()
        if not storage then
            return {}
        end
        return { storage }
    end

    -- The SHARED selection, which is what every row below edits. Read with ignoreOverride
    -- on purpose: while an override applies, the evaluator-facing read hides the stored
    -- set, and taking that view here rendered the rows as the bare legacy scalar and let
    -- the next click write that rump back over the set. The override itself is reported by
    -- the summary (ovHeldFn) and by GetChecked's exclusive-row branch, never from here.
    local function Sel()
        local storage = options.getStore()
        if not storage then
            return nil
        end
        return NormalizeGroupHide(CludesUI.GetVisibilitySelection(storage, legacyKey, true)), storage
    end

    -- Read-only view for GetChecked, memoized. Every refresh sweep and every menu open
    -- calls GetChecked twice per condition row, and each call allocated a fresh selection
    -- table. The key is everything Sel()'s answer depends on, and SetVisibilitySelection
    -- assigns a NEW visibilityModes table on every write, so an identity compare catches
    -- this row's writes and everyone else's alike (an override applying, a profile switch,
    -- a sync copy). Callers that MUTATE the selection keep using Sel().
    local _selCache, _selStore, _selModes, _selScalar, _selMatch, _selOv
    local function SelRead()
        local storage = options.getStore()
        if not storage then
            return nil, nil
        end
        if
            _selCache
            and storage == _selStore
            and storage.visibilityModes == _selModes
            and storage[legacyKey] == _selScalar
            and storage.visibilityMatch == _selMatch
            and storage.visibilityOverride == _selOv
        then
            return _selCache, storage
        end
        _selStore, _selModes = storage, storage.visibilityModes
        _selScalar, _selMatch = storage[legacyKey], storage.visibilityMatch
        _selOv = storage.visibilityOverride
        _selCache = NormalizeGroupHide(CludesUI.GetVisibilitySelection(storage, legacyKey, true))
        return _selCache, storage
    end

    local function WriteSel(sel, storage)
        -- Never-empty invariant: clearing the last condition means Always.
        if not next(sel) then
            sel.always = true
        end
        -- A shared edit outside a session also clears a STRANDED override marker. Two
        -- ways one can be left behind: the management list's Remove drops the entry but
        -- deliberately leaves live values alone, and a profile exported while an override
        -- applied carries the key into every import of it. Either way nothing owns the
        -- key any more and the element would be stuck on it; a real applied override
        -- simply writes it back on its next apply.
        if not OvSessionActive() and storage.visibilityOverride ~= nil then
            local stores = OvStores()
            for idx = 1, #stores do
                stores[idx].visibilityOverride = nil
            end
        end
        CludesUI.SetVisibilitySelection(storage, legacyKey, sel, options.applyScalarFn)
    end

    -- Stranded-marker heal, once per page build. A live override marker nothing owns any
    -- more pins the element on that state with no path back: the management list's Remove
    -- drops the entry but deliberately leaves applied values alone, and a profile exported
    -- while an override applied carries the marker into every import that did not also
    -- take the overrides. Never inside a session -- the marker being edited is exactly the
    -- one no map holds yet -- and never for a marker a real override still owns, which
    -- simply gets written back on its next apply. WriteSel's clear stays as the belt.
    if not CludesUI._prebuilding and not (CludesUI.SpecOverrides_EditSessionActive()) then
        local stores, healed = OvStores(), false
        for idx = 1, #stores do
            local st = stores[idx]
            if
                st.visibilityOverride ~= nil
                and CludesUI.SpecOverrides_KeyIsOwned
                and not CludesUI.SpecOverrides_KeyIsOwned(st, "visibilityOverride")
            then
                st.visibilityOverride = nil
                healed = true
            end
        end
        -- The element is sitting on the state the marker pinned it to, so it needs the
        -- module's visibility pass to catch up. onOptionChanged, not onChanged: the light
        -- re-apply chain, none of whose callers rebuild the page. Deferred a frame anyway,
        -- so nothing runs a module refresh from inside the page build that started it.
        if healed and options.onOptionChanged then
            C_Timer.After(0, options.onOptionChanged)
        end
    end

    local function GetOpt(k)
        if options.getOption then
            return options.getOption(k) == true
        end
        local storage = options.getStore()
        return (storage and storage[k]) == true
    end

    local function SetOpt(k, val)
        -- Uncheck normally persists as nil ("never set"), which is correct for every
        -- shipped-off key. A key whose DEFAULTS entry is true needs an explicit false
        -- instead, or DeepMergeDefaults re-fills the nil back to true on next login.
        local storedValue
        if val then
            storedValue = true
        elseif options.trueDefaultOpts and options.trueDefaultOpts[k] then
            storedValue = false
        else
            storedValue = nil
        end
        if options.setOption then
            options.setOption(k, storedValue)
            return
        end
        local storage = options.getStore()
        if storage then
            storage[k] = storedValue
        end
    end

    -- The match is a store-level scalar, but it fans out like the option lanes do
    -- (Resource Bars writes health/primary/secondary through these hooks), so it rides them.
    GetMatchAny = function()
        if options.getOption then
            return options.getOption("visibilityMatch") == "any"
        end
        local storage = options.getStore()
        return (storage and storage.visibilityMatch) == "any"
    end

    local function SetMatchAny(enabled)
        if options.setOption then
            options.setOption("visibilityMatch", enabled and "any" or nil)
            return
        end
        local storage = options.getStore()
        if storage then
            storage.visibilityMatch = enabled and "any" or nil
        end
    end

    -- Option axes live outside the selection, so Always vs. an active Show lane (which
    -- narrows what Always claims is unrestricted) is reconciled in GetChecked/SetChecked.
    -- Same under Any: always is not a tallied axis, so a lone Show lane narrows the same way.
    -- A selection whose only members are Hide lanes reads as Always: nothing restricts
    -- where the element shows, a veto just carves out where it does not. Same shape the
    -- option Hide lanes have always had (they live outside the selection entirely).
    local function OnlyHideLanes(sel)
        local hasHide = false
        for k in pairs(sel) do
            if not CludesUI.VIS_MODE_HIDE_KEYS[k] then
                return false
            end
            hasHide = true
        end
        return hasHide
    end

    local function AnyShowOptActive()
        for _, d in pairs(defs) do
            if d.axis == "opt" and GetOpt(d.show) then
                return true
            end
        end
        return false
    end

    local cbDD, cbDDRefresh
    local pendingRefresh = false

    -- The module refresh chain runs on every click so changes apply live, but the page
    -- REBUILD waits for menu close: rebuilding under the open menu destroys the button
    -- it is anchored to, and the point of a checklist is setting several axes in one
    -- visit. Terminal picks (Never/Always, orphans) close the menu themselves.
    -- alsoOther: the click wrote a mode AND an option (a lane clearing Never, or Always
    -- clearing the Show lanes), so both caller chains run; neither is a subset of the other
    -- (Action Bars recompiles its housing driver only in the option chain).
    local function AfterChange(closeMenu, isOption, alsoOther)
        local optionFn = (isOption or alsoOther) and options.onOptionChanged
        local modeFn = ((not isOption) or alsoOther) and options.onChanged
        if optionFn then
            optionFn()
        end
        if modeFn then
            modeFn()
        end
        -- A caller that supplies only onChanged still gets that chain for option writes.
        if not optionFn and not modeFn and options.onChanged then
            options.onChanged()
        end
        pendingRefresh = true
        if closeMenu and cbDD and cbDD._ddMenu then
            cbDD._ddMenu:Hide()
        end
    end

    local function GetChecked(k, neg)
        local spec_def = defs[k]
        if not spec_def then
            return false
        end
        if spec_def.modifier then
            return (spec_def.matchValue == "any") == GetMatchAny()
        end
        if spec_def.axis == "extra" then
            return spec_def.get() == true
        end
        if spec_def.axis == "opt" then
            return GetOpt(neg and spec_def.hide or spec_def.show)
        end
        local sel, storage = SelRead()
        if not sel then
            return k == "always"
        end
        -- While an override is being EDITED the three exclusive rows show what it holds.
        -- Outside a session they show the shared value again, because that is what these
        -- rows edit -- an applied override is announced by the summary and the panel's
        -- own gold marker, not by checking a row the click would not change. Read from
        -- the store Sel() just resolved rather than calling opts.getStore() again: a
        -- getter is not guaranteed free (CDM's tracked buff bars CREATE their table on
        -- read), and inside a session such a write becomes a capture of its own.
        if OvSessionActive() and (k == "never" or k == "always" or k == "mouseover") then
            local shade = storage and CludesUI.VisOverrideValue(storage)
            if shade then
                return (not neg) and (k == shade)
            end
        end
        if spec_def.axis == "mode" then
            return sel[neg and spec_def.hide or spec_def.show] == true
        end
        if spec_def.axis == "group" then
            return sel[neg and spec_def.hide or spec_def.key] == true
        end
        if k == "always" then
            return (sel.always == true or OnlyHideLanes(sel)) and not AnyShowOptActive()
        end
        return sel[k] == true
    end

    local function SetChecked(k, checked, neg)
        local spec_def = defs[k]
        if not spec_def then
            return
        end

        -- Inside an override session the three exclusive states are the only thing an
        -- override can carry, and they REPLACE the configuration instead of editing it.
        -- Exactly ONE key is written and nothing else: the shared scalar, the stored
        -- selection, the match mode and the option lanes stay untouched, so nothing
        -- underneath can be lost or swept into the override by accident. Picking the
        -- state the override already holds clears it again.
        if (k == "never" or k == "always" or k == "mouseover") and OvSessionActive() then
            local stores = OvStores()
            local storage = stores[1]
            if not storage then
                return
            end
            local held = CludesUI.VisOverrideValue(storage)
            if held == k then
                -- Cleared on every store first, so the re-snapshot ClearStoreKey takes
                -- at the end already sees the finished state and nothing diffs back into
                -- a capture of its own.
                for idx = 1, #stores do
                    stores[idx].visibilityOverride = nil
                end
                CludesUI.SpecOverrides_ClearStoreKey(stores, "visibilityOverride")
            else
                for idx = 1, #stores do
                    stores[idx].visibilityOverride = k
                end
            end
            AfterChange(true)
            return
        end

        -- Modifier: a radio pair over one scalar; picking one unpicks the other and
        -- deliberately clears nothing else.
        if spec_def.modifier then
            SetMatchAny(spec_def.matchValue == "any")
            AfterChange(false, true)
            return
        end

        if spec_def.axis == "extra" then
            spec_def.set(checked)
            AfterChange(false, true)
            return
        end

        if spec_def.axis == "opt" then
            local lane, other = spec_def.show, spec_def.hide
            if neg then
                lane, other = spec_def.hide, spec_def.show
            end
            SetOpt(lane, checked)
            if checked then
                SetOpt(other, false)
            end
            -- Checking a lane under Never leaves Never (WriteSel's never-empty invariant
            -- lands on Always, which the lane then narrows); unchecking one leaves Never alone.
            local clearedNever = false
            if checked then
                local sel, storage = Sel()
                if storage and sel.never then
                    sel.never = nil
                    WriteSel(sel, storage)
                    clearedNever = true
                end
            end
            AfterChange(false, true, clearedNever)
            return
        end

        local sel, storage = Sel()
        if not storage then
            return
        end
        -- Any condition write clears the exclusive scalars (Never/Always/orphan) but
        -- combines with every other axis.
        if spec_def.axis or k == "mouseover" then
            for key in pairs(sel) do
                if not CludesUI.VIS_COMBINABLE_KEYS[key] then
                    sel[key] = nil
                end
            end
        end

        if spec_def.axis == "mode" then
            local lane, other = spec_def.show, spec_def.hide
            if neg then
                lane, other = spec_def.hide, spec_def.show
            end
            sel[lane] = checked or nil
            if checked then
                sel[other] = nil
            end
            WriteSel(sel, storage)
            AfterChange(false)
            return
        end

        if spec_def.axis == "group" then
            local lane, other = spec_def.key, spec_def.hide
            if neg then
                lane, other = spec_def.hide, spec_def.key
            end
            sel[lane] = checked or nil
            if checked then
                sel[other] = nil
            end
            WriteSel(sel, storage)
            AfterChange(false)
            return
        end

        if k == "mouseover" then
            sel.mouseover = checked or nil
            WriteSel(sel, storage)
            AfterChange(false)
            return
        end

        if k == "never" or k == "always" then
            -- Exclusive and terminal, like a plain single-select. Always clears the SHOW
            -- side only -- a Hide lane survives it, exactly as an option Hide lane does.
            -- Never is terminal for everything, vetoes included.
            for key in pairs(sel) do
                if k == "never" or not CludesUI.VIS_MODE_HIDE_KEYS[key] then
                    sel[key] = nil
                end
            end
            if checked then
                sel[k] = true
            end
            WriteSel(sel, storage)
            -- Always clears the Show lanes (else GetChecked keeps its box unchecked and the
            -- click is a no-op); Hide lanes survive, and Never leaves every lane untouched.
            local clearedOpts = false
            if k == "always" and checked then
                for _, d in pairs(defs) do
                    if d.axis == "opt" and GetOpt(d.show) then
                        SetOpt(d.show, false)
                        clearedOpts = true
                    end
                end
            end
            AfterChange(true, false, clearedOpts)
            return
        end

        -- Legacy orphan re-checked while its row is still visible.
        if checked then
            if options.applyScalarFn then
                options.applyScalarFn(storage, k)
            else
                storage[legacyKey] = k
            end
            storage.visibilityModes = nil
            SetMatchAny(false)
            AfterChange(true)
        end
    end

    local function OnMenuClosed()
        if pendingRefresh then
            pendingRefresh = false
            CludesUI:RefreshPage(options.refreshPageArg)
        end
    end

    local leftRgn = regionFrame
    if leftRgn._control then
        leftRgn._control:Hide()
    end
    cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
        leftRgn,
        options.width or 210,
        leftRgn:GetFrameLevel() + 2,
        itemList,
        GetChecked,
        SetChecked,
        nil,
        12,
        nil,
        nil,
        OnMenuClosed,
        {
            emptyLabel = "Always",
            -- Override sessions have to see each click as it happens: parts of this
            -- control are excluded from them and the session says so per write.
            notifyWrites = true,
            -- Seals the excluded rows off as one block while a session is live, announced
            -- once instead of by every row.
            ovLockedFn = OvSessionActive,
            ovLockedTooltip = caps.noOverrideMouseover and OV_LOCK_TIP_MO or OV_LOCK_TIP,
            -- The value a live override holds, applied or edited: the summary shows it
            -- instead of the shared selection it replaces.
            ovHeldFn = function()
                local _, storage = SelRead()
                return storage and CludesUI.VisOverrideValue(storage) or nil
            end,
            -- The separator reads the match live: under Any the conditions are OR'd.
            separatorFn = function()
                return GetMatchAny() and " or " or ", "
            end,
            -- Every row follows the same rule now: a checked Hide lane hides while its
            -- condition holds, in both match modes.
            hideLaneTooltip = "Hide while this condition is true",
        }
    )
    Pix.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
    leftRgn._control = cbDD
    leftRgn._lastInline = nil
    CludesUI.RegisterWidgetRefresh(cbDDRefresh)

    -- Spec Overrides capture overlay: exposes the scalar view (a captured multi applies
    -- as its representative single mode). Option axes are not spec-capturable, same as
    -- before the merge.
    leftRgn._captureCfg = {
        type = "dropdown",
        text = options.label or "Visibility",
        getValue = function()
            local s = options.getStore()
            if not s then
                return "always"
            end
            -- Both are read on purpose, and unconditionally: the gold walk traces what a
            -- getter READS, so a row whose override lives in either key has to touch both
            -- or it never marks itself as overridden. The override wins as the value,
            -- being the effective one this is meant to report.
            local shade, baseValue = s.visibilityOverride, s[legacyKey]
            return shade or baseValue or "always"
        end,
        setValue = function(val)
            local s = options.getStore()
            if not s then
                return
            end
            -- Round-trip with getValue above: while a marker is live the value this slot
            -- REPORTS is the override, so a value handed back belongs there too. Writing
            -- it into the shared scalar instead would replace a setting the override was
            -- only standing in front of. A value no override can hold falls through and
            -- edits the shared side, exactly as every other slot does under an override.
            local ovIn = CludesUI.VisOverrideValue(s) and CludesUI.VisOverrideNormalize(val)
            if ovIn then
                local stores = OvStores()
                for idx = 1, #stores do
                    stores[idx].visibilityOverride = ovIn
                end
                if options.onChanged then
                    options.onChanged()
                end
                return
            end
            if
                CludesUI.VIS_CONDITION_KEYS[val]
                or val == "never"
                or val == "always"
                or val == "mouseover"
            then
                local one = {}
                one[val] = true
                CludesUI.SetVisibilitySelection(s, legacyKey, one, options.applyScalarFn)
            else
                if options.applyScalarFn then
                    options.applyScalarFn(s, val)
                else
                    s[legacyKey] = val
                end
                s.visibilityModes = nil
                -- Same reset as the row's orphan branch: Any cannot express an orphan.
                SetMatchAny(false)
            end
            if options.onChanged then
                options.onChanged()
            end
        end,
    }

    if options.disabledFn then
        local function ApplyChecklistDisabled()
            local offset = options.disabledFn()
            cbDD:SetAlpha(offset and 0.3 or 1)
            cbDD:EnableMouse(not offset)
        end
        CludesUI.RegisterWidgetRefresh(ApplyChecklistDisabled)
        ApplyChecklistDisabled()
    end
end

function CludesUI.BuildVisibilityRow(Widgets, hostFrame, posY, options, rightCfg)
    -- The placeholder slot the checklist replaces; W:DualRow only knows plain widgets.
    local function Slot(o)
        return {
            type = "dropdown",
            text = o.label or "Visibility",
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            tooltip = o.tooltip,
            disabled = o.disabledFn,
            disabledTooltip = o.disabledTooltip,
            rawTooltip = o.rawTooltip,
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        }
    end

    -- opts.rightVis: a second, fully independent visibility checklist in the right
    -- slot (its own store, legacyKey, caps and callbacks). Mutually exclusive with
    -- rightCfg, which stays the way to put any ordinary widget there.
    -- opts.leftCfg: an ordinary widget in the LEFT slot and this checklist in the RIGHT
    -- one. Excludes rightVis and rightCfg.
    local rightVis = options.rightVis
    local leftCfg = options.leftCfg
    local rowFrame, hgt
    if leftCfg then
        rowFrame, hgt = Widgets:DualRow(hostFrame, posY, leftCfg, Slot(options))
    else
        rowFrame, hgt = Widgets:DualRow(
            hostFrame,
            posY,
            Slot(options),
            rightVis and Slot(rightVis) or rightCfg or { type = "label", text = "" }
        )
    end

    -- Search pre-build: the row is an absorber, so the chrome below would throw. The
    -- row's labels were already indexed by the factory stubs; nothing here registers.
    if CludesUI._prebuilding then
        return rowFrame, hgt
    end

    CludesUI.AttachVisibilityChecklist(leftCfg and rowFrame._rightRegion or rowFrame._leftRegion, options)
    if rightVis and not leftCfg then
        CludesUI.AttachVisibilityChecklist(rowFrame._rightRegion, rightVis)
    end

    return rowFrame, hgt
end
