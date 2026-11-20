if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_SharedHelpers.lua
--  Frame data store, third-party skin registry, Edit Mode-safe anchoring and
--  frame placers, Blizzard cast bar ownership and suppression, and small
--  shared helpers (Swiftmend, level colors, faction art, split-module guard
--  tables). Loads right after CludesUI_VisibilityRules.lua.
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)

-------------------------------------------------------------------------------
--  External weak-keyed lookup table for frame state (prevents tainting Blizzard
--  frames). NewFrameData returns a fresh table and its getter; each file keeps
--  its own, so two files never share fields on one frame. The core's pair is
--  stored on CludesUI to avoid the 200-local cap in CludesUI.lua.
-------------------------------------------------------------------------------
function CludesUI.NewFrameData()
    local FFD = setmetatable({}, { __mode = "k" })
    return FFD,
        function(widget)
            local d = FFD[widget]
            if not d then
                d = {}
                FFD[widget] = d
            end
            return d
        end
end
if not CludesUI._FFD then
    CludesUI._FFD, CludesUI._GetFFD = CludesUI.NewFrameData()
end

-- Stock styles, enable-time catch-up seeds: a profile already on a stock
-- style from before the per-style slots (the Style page did not switch it,
-- so nothing saved the CludesUI look's values) keeps those values in its
-- CludesUI slot before a seed writes over them, so switching back
-- restores them. `keys` = the module's slot keys (dotted paths one level
-- deep into `p`, as the Style page's SLOT_KEYS). Callers bank only while
-- none of the module's seed stamps is set; an existing slot is never touched.
function CludesUI.BankEuiStyleSlot(profile, keyList)
    if type(profile) ~= "table" then
        return
    end
    local slots = profile._styleSlots
    if type(slots) == "table" and type(slots.cui) == "table" then
        return
    end
    if type(slots) ~= "table" then
        slots = {}
        profile._styleSlots = slots
    end
    local result = {}
    for idx = 1, #keyList do
        local filePath = keyList[idx]
        local a, b = filePath:match("^([^.]+)%.(.+)$")
        if a then
            local cfg = profile[a]
            if type(cfg) == "table" then
                result[filePath] = cfg[b]
            end
        else
            result[filePath] = profile[filePath]
        end
    end
    slots.cui = result
end

-------------------------------------------------------------------------------
--  Third-Party Skin Registration (public API) -- other addons call
--  CludesUI.RegisterSkin("TheirAddon", function(S) ... end) to have their frames painted in
--  the CUI house style. This stub only queues: the Blizz UI Enhanced child addon drains the
--  queue at PLAYER_LOGIN (or immediately for late/LoD registrations) and passes the skinning
--  facade S. Queuing keeps registration order-independent -- third-party addons may load before
--  or after the child -- and the API stays callable (a silent no-op) when the child addon is
--  disabled. Developer guide: SKINNING_API.md. Stored on CludesUI to avoid the 200-local cap in CludesUI.lua.
-------------------------------------------------------------------------------
CludesUI._skinRegistry = CludesUI._skinRegistry or {}
function CludesUI.RegisterSkin(label, applyFn)
    if type(label) ~= "string" or label == "" or type(applyFn) ~= "function" then
        return
    end
    local reg = CludesUI._skinRegistry
    for idx = 1, #reg do
        if reg[idx].name == label then
            return
        end
    end
    local record = { name = label, apply = applyFn }
    reg[#reg + 1] = record
    if CludesUI._DispatchSkinRegistration then
        CludesUI._DispatchSkinRegistration(record)
    end
    return true
end

-------------------------------------------------------------------------------
--  Alpha-Zero Visibility Helper
--  For anchor-participating container frames: use alpha 0 + EnableMouse(false)
--  instead of :Hide() so the frame stays in the layout engine with valid bounds.
--  Sub-widgets (icons, text, glows) inside these frames still use :Hide()/:Show().
-------------------------------------------------------------------------------
function CludesUI.SetElementVisibility(widget, visible)
    if not widget then
        return
    end
    if visible then
        widget:SetAlpha(CludesUI._GetFFD(widget).restoreAlpha or 1)
        widget:EnableMouse(CludesUI._GetFFD(widget).restoreMouse or false)
    else
        local a = widget:GetAlpha()
        if not issecretvalue(a) and a > 0 then
            CludesUI._GetFFD(widget).restoreAlpha = a
        end
        CludesUI._GetFFD(widget).restoreMouse = widget:IsMouseEnabled()
        widget:SetAlpha(0)
        widget:EnableMouse(false)
    end
end

-------------------------------------------------------------------------------
--  An Edit Mode system's own child (its Selection box, a resize button) made
--  inert in place while a module of ours owns that frame's spot or size, so
--  Edit Mode cannot pick it up: alpha and mouse only, never reparented (a
--  region its owner still writes stays in its tree). inert = false turns it
--  back on; a caller does that only for a child it turned off itself.
--  GetAlpha can read secret on some widgets in lockdown; a secret skips the
--  compare and re-asserts.
-------------------------------------------------------------------------------
function CludesUI.SetEditModeChildInert(frame, inert)
    if not frame then
        return
    end
    local alpha = inert and 0 or 1
    local a = frame:GetAlpha()
    if issecretvalue(a) or a ~= alpha then
        frame:SetAlpha(alpha)
    end
    if frame.SetMouseClickEnabled then
        local enabled = not inert
        if frame:IsMouseClickEnabled() ~= enabled then
            frame:SetMouseClickEnabled(enabled)
        end
        if frame:IsMouseMotionEnabled() ~= enabled then
            frame:SetMouseMotionEnabled(enabled)
        end
    end
end

-------------------------------------------------------------------------------
--  Anchoring a frame that may be a Blizzard Edit Mode system (ChatFrame1, the
--  action bars, the quest tracker, ...). Edit Mode replaces those frames'
--  SetPoint and ClearAllPoints with Lua overrides that, called from our code,
--  mark Edit Mode's anchor sweep and the frame's snap state as written by us.
--  These call the saved C methods instead; any other frame uses its own.
-------------------------------------------------------------------------------
function CludesUI.ClearFramePoints(widget)
    local clear = widget.ClearAllPointsBase or widget.ClearAllPoints
    clear(widget)
end

function CludesUI.SetFramePoint(widget, anchorPoint, relativeTo, relativePoint, x, y)
    local setPoint = widget.SetPointBase or widget.SetPoint
    setPoint(widget, anchorPoint, relativeTo, relativePoint, x, y)
end

-- Edit Mode's SetScale override, called from our code, re-anchors the system
-- through its SetPoint override and re-runs the managed frame layout; the
-- saved C method only scales, leaving the anchor offsets as they are.
-- keepPosition: an Edit Mode system's offsets are rescaled as the override
-- does it, so the system keeps its spot (Edit Mode's save reads a moved
-- system's anchor back from its geometry times its scale).
function CludesUI.SetFrameScale(widget, scale, keepPosition)
    local setScale = widget.SetScaleBase
    if not setScale then
        widget:SetScale(scale)
        return
    end
    local old = keepPosition and widget:GetScale()
    setScale(widget, scale)
    if not old then
        return
    end
    local new = widget:GetScale()
    if issecretvalue(old) or issecretvalue(new) or new == old or new <= 0 then
        return
    end
    local k = old / new
    for idx = 1, widget:GetNumPoints() do
        local p, rel, rp, x, y = widget:GetPoint(idx)
        if
            not (
                issecretvalue(p)
                or issecretvalue(rel)
                or issecretvalue(rp)
                or issecretvalue(x)
                or issecretvalue(y)
            )
        then
            CludesUI.SetFramePoint(widget, p, rel, rp, x * k, y * k)
        end
    end
end

-- Edit Mode's Hide override on a system sized to its children (a layout
-- frame: the party, raid and boss frame containers), called from our code,
-- first breaks the snap of every system snapped to it, re-anchoring each one
-- and writing it into the active layout under our taint. This hides through
-- the saved C method instead, so those stay snapped (Edit Mode's own save
-- still breaks snaps to party, raid and boss frames); any other frame uses
-- its own Hide. A protected frame still hides only out of combat. Show has
-- no such override (a plain Show undoes this), except on Blizzard's action
-- bars, whose overrides keep their own shown state, which this leaves as it
-- was.
function CludesUI.HideFrame(widget)
    local hide = widget.HideBase or widget.Hide
    hide(widget)
end

-------------------------------------------------------------------------------
--  Frame placers: keep an unprotected Blizzard frame that Blizzard keeps
--  re-anchoring (a bottom managed column frame such as GroupLootContainer) at
--  a spot of ours, with nothing written onto the frame.
--
--  CludesUI.SetFramePlacer(frame, owner, fn): owners are tried in the fixed
--  order of PLACER_RANKS, "shifter" (the player's saved spot) before "cdm" (an
--  automatic spot); a new owner adds its rank there. fn(frame, point,
--  relativeTo, relativePoint, x, y) gets the anchor Blizzard last set (an
--  anchor to the parent comes with the parent) and returns the anchor to use,
--  nil to pass to the next owner, or false to pass and be asked again when
--  combat ends (an input it reads is secret); nil from every owner keeps
--  Blizzard's anchor. fn = nil removes the owner, and the last owner leaving
--  puts Blizzard's anchor back. Returns false, registering nothing, for an
--  unknown owner, a value that is not a frame, an fn that is not a function,
--  or a protected, forbidden or anchoring-restricted frame (a secret answer
--  counts as yes).
--  CludesUI.RequestFramePlacement(frame): place it again after a saved
--  spot or another input of an owner changed.
--
--  Post-hooks installed at the frame's first registration watch writes from
--  anyone but us. A SetPoint or SetAllPoints marks the frame and a
--  ClearAllPoints does not (Blizzard re-anchors through SetPoint when it
--  shows the frame again). A frame in a managed column (its layoutParent)
--  is placed as the column's Layout returns, whatever ran it, so Blizzard's
--  anchor is never drawn: one post-hook per column, which costs one check
--  while nothing is marked. One hidden frame of ours places every frame
--  still marked from its OnUpdate (the same frame when Blizzard re-anchors
--  from an event, one frame later when it does so from a timer, an
--  animation or another OnUpdate). The anchor such a write leaves is
--  Blizzard's new one, unless the frame then has more than one point: those
--  anchors stay, except that a point a SetPoint adds beside ours (no clear
--  first) puts ours back on alone. A placement or hand-back that cannot run
--  (the frame refused at that moment, or Blizzard's anchor secret) runs
--  again when combat ends. Placer frames are unprotected, so placements run
--  in combat too: the refusal check before every write stands in for a
--  combat gate. An owner fn must not register or remove placers.
-------------------------------------------------------------------------------
do
    local PLACER_RANKS = { shifter = 1, cdm = 2 }
    local NUM_PLACER_RANKS = 0
    for _, rank in pairs(PLACER_RANKS) do
        if rank > NUM_PLACER_RANKS then
            NUM_PLACER_RANKS = rank
        end
    end
    local placerStates = setmetatable({}, { __mode = "k" })
    local PlacerRetry

    local function PlacerRefused(widget)
        local val = widget:IsForbidden()
        if issecretvalue(val) or val then
            return true
        end
        val = widget:IsProtected()
        if issecretvalue(val) or val then
            return true
        end
        if widget.IsAnchoringRestricted then
            val = widget:IsAnchoringRestricted()
            if issecretvalue(val) or val then
                return true
            end
        end
        return false
    end

    local function PlacerSet(widget, anchorPoint, relativeTo, relativePoint, x, y)
        CludesUI.ClearFramePoints(widget)
        CludesUI.SetFramePoint(widget, anchorPoint, relativeTo, relativePoint, x, y)
    end

    -- False when SetPoint refused the anchor (an anchor loop): the frame was
    -- left with no points, and the error goes to the error handler. Either
    -- way no point of anyone else is left on the frame.
    local function PlacerApply(widget, placerState, anchorPoint, relativeTo, relativePoint, x, y)
        placerState.applying = true
        local success, err = pcall(PlacerSet, widget, anchorPoint, relativeTo, relativePoint, x, y)
        placerState.applying, placerState.over = false, false
        if not success then
            geterrorhandler()(err)
        end
        return success
    end

    -- Runs the state again when combat ends (one keyed entry in the core's
    -- combat queue, however many states wait).
    local function PlacerOwe(placerState)
        placerState.owed = true
        CludesUI.CombatQueue.Defer("FramePlacerRetry", PlacerRetry)
    end

    local function PlacerResolve(widget, placerState)
        placerState.owed = false
        if placerState.count == 0 and not placerState.placed then
            return
        end
        if PlacerRefused(widget) then
            PlacerOwe(placerState)
            return
        end
        if placerState.count == 0 then
            -- A hand-back refused earlier: our anchor is still on the frame.
            placerState.placed = false
            PlacerApply(widget, placerState, placerState.bp, placerState.br, placerState.brp, placerState.bx, placerState.by)
            return
        end
        if not placerState.placed then
            -- The frame holds Blizzard's anchor: kept for the owners and the hand-back.
            if widget:GetNumPoints() ~= 1 then
                return
            end
            local p, r, rp, x, y = widget:GetPoint(1)
            if
                issecretvalue(p)
                or issecretvalue(r)
                or issecretvalue(rp)
                or issecretvalue(x)
                or issecretvalue(y)
            then
                PlacerOwe(placerState)
                return
            end
            if r == nil then
                -- An anchor to the parent can read back with no relative
                -- frame; an explicit nil would anchor to the screen instead.
                r = widget:GetParent()
                if issecretvalue(r) then
                    PlacerOwe(placerState)
                    return
                end
            end
            placerState.bp, placerState.br, placerState.brp, placerState.bx, placerState.by = p, r, rp, x, y
        end
        local fns = placerState.fns
        local later = false
        local success, p, r, rp, x, y
        for rank = 1, NUM_PLACER_RANKS do
            local func = fns[rank]
            if func then
                -- An owner that errors passes, so it never stops the others.
                success, p, r, rp, x, y = pcall(func, widget, placerState.bp, placerState.br, placerState.brp, placerState.bx, placerState.by)
                if not success then
                    geterrorhandler()(p)
                    p = nil
                elseif p == false then
                    later = true
                end
                if p then
                    break
                end
            end
        end
        if later then
            PlacerOwe(placerState)
        end
        if p then
            if
                placerState.placed
                and not placerState.over
                and p == placerState.ap
                and r == placerState.ar
                and rp == placerState.arp
                and x == placerState.ax
                and y == placerState.ay
            then
                return
            end
            if PlacerApply(widget, placerState, p, r, rp, x, y) then
                placerState.placed = true
                placerState.ap, placerState.ar, placerState.arp, placerState.ax, placerState.ay = p, r, rp, x, y
                return
            end
        elseif later or not placerState.placed then
            -- Nothing placed yet, or an owner decides after combat: the
            -- anchor on the frame stays.
            return
        end
        -- No owner wants a spot, or the owner's anchor was refused.
        placerState.placed = false
        PlacerApply(widget, placerState, placerState.bp, placerState.br, placerState.brp, placerState.bx, placerState.by)
    end

    -- Shown exactly while a state is marked, so its OnUpdate runs only in a
    -- frame where one was.
    local placerDriver = CreateFrame("Frame")
    placerDriver:Hide()

    local function PlacerFlush()
        placerDriver:Hide()
        for widget, placerState in pairs(placerStates) do
            if placerState.dirty then
                placerState.dirty = false
                PlacerResolve(widget, placerState)
            end
        end
    end
    placerDriver:SetScript("OnUpdate", PlacerFlush)

    -- Post-hook of a managed column's Layout. Whatever runs the layout (an
    -- event, a timer, an animation that ends, the column's own OnUpdate), the
    -- frames it re-anchored are placed as it returns, before anything draws.
    local function PlacerSettle()
        if placerDriver:IsShown() then
            PlacerFlush()
        end
    end
    local placerColumns = {}

    local function PlacerMark(placerState)
        placerState.dirty = true
        placerDriver:Show()
    end

    PlacerRetry = function()
        for _, placerState in pairs(placerStates) do
            if placerState.owed then
                PlacerMark(placerState)
            end
        end
    end

    local function PlacerNewState(widget)
        local placerState = { fns = {}, count = 0 }
        placerStates[widget] = placerState
        -- A write from anyone but us (ours run with st.applying set) that
        -- replaces or clears our anchor drops it, owners or not, so a waiting
        -- hand-back has nothing left to do; a SetPoint or SetAllPoints also
        -- asks for a placement while there are owners. A SetPoint on another
        -- point than ours leaves our anchor on the frame beside it (st.over):
        -- it stays ours, and the next placement or hand-back leaves one point.
        hooksecurefunc(widget, "SetPoint", function(_, anchorPoint)
            if placerState.applying then
                return
            end
            if placerState.placed and anchorPoint ~= placerState.ap then
                placerState.over = true
            else
                placerState.placed, placerState.over = false, false
            end
            if placerState.count > 0 then
                PlacerMark(placerState)
            end
        end)
        hooksecurefunc(widget, "SetAllPoints", function()
            if placerState.applying then
                return
            end
            placerState.placed, placerState.over = false, false
            if placerState.count > 0 then
                PlacerMark(placerState)
            end
        end)
        hooksecurefunc(widget, "ClearAllPoints", function()
            if not placerState.applying then
                placerState.placed, placerState.over = false, false
            end
        end)
        local column = widget.layoutParent
        if type(column) == "table" and type(column.Layout) == "function" and not placerColumns[column] then
            placerColumns[column] = true
            hooksecurefunc(column, "Layout", PlacerSettle)
        end
        return placerState
    end

    function CludesUI.SetFramePlacer(widget, ownerFrame, func)
        local rank = PLACER_RANKS[ownerFrame]
        if
            not rank
            or type(widget) ~= "table"
            or not widget.IsForbidden
            or (func ~= nil and type(func) ~= "function")
        then
            return false
        end
        local placerState = placerStates[widget]
        if func then
            if placerState and placerState.fns[rank] == func then
                return true
            end
            if PlacerRefused(widget) then
                return false
            end
            placerState = placerState or PlacerNewState(widget)
            if not placerState.fns[rank] then
                placerState.count = placerState.count + 1
            end
            placerState.fns[rank] = func
            PlacerMark(placerState)
            return true
        end
        if not (placerState and placerState.fns[rank]) then
            return true
        end
        placerState.fns[rank] = nil
        placerState.count = placerState.count - 1
        if placerState.count > 0 then
            PlacerMark(placerState)
        elseif placerState.placed then
            -- placed still means the frame holds our anchor (a write that
            -- replaces or clears it drops placed), so Blizzard's recorded
            -- anchor is current. A frame refused right now keeps our anchor,
            -- still marked as ours, until the hand-back can run.
            if PlacerRefused(widget) then
                PlacerOwe(placerState)
            else
                placerState.placed = false
                PlacerApply(widget, placerState, placerState.bp, placerState.br, placerState.brp, placerState.bx, placerState.by)
            end
        end
        return true
    end

    function CludesUI.RequestFramePlacement(widget)
        local placerState = placerStates[widget]
        if placerState and placerState.count > 0 then
            PlacerMark(placerState)
        end
    end
end

-------------------------------------------------------------------------------
--  Blizzard Cast Bar Event Ownership -- standalone cast bar addons claim Blizzard's
--  player/pet cast bars by unregistering their events. oUF's Castbar element writes the same
--  state -- it silences those frames when it enables on the player frame and re-arms them when
--  it disables -- so CUI can hand a user's cast bar back to Blizzard on top of the addon they
--  replaced it with. CUI hides Blizzard's bar by re-parenting it (see SetPlayerCastBarSuppressed),
--  so it never needs the event state changed: wrap anything that flips it in Capture/Restore and only ever undo CUI's own writes.
-------------------------------------------------------------------------------
function CludesUI._BlizzCastBars()
    local barList = CludesUI._blizzCastBarList
    if barList then
        return barList
    end

    barList = {}
    if PlayerCastingBarFrame then
        barList[#barList + 1] = { frame = PlayerCastingBarFrame, unit = "player" }
    end
    if PetCastingBarFrame then
        barList[#barList + 1] = { frame = PetCastingBarFrame, unit = "pet" }
    end
    CludesUI._blizzCastBarList = barList

    for idx = 1, #barList do
        local barFrame = barList[idx]
        -- An UnregisterAllEvents outside one of our own Capture/Restore windows is another
        -- addon claiming the frame: CUI drops its claim and records the claim as foreign.
        -- "Foreign" is tracked separately from "not ours" because those are very different states -- see RestoreBlizzCastBarEvents.
        hooksecurefunc(barFrame.frame, "UnregisterAllEvents", function()
            if not CludesUI._blizzCastBarSnapshot then
                barFrame.owned = false
                barFrame.foreign = true
            end
        end)
    end
    return barList
end

function CludesUI.CaptureBlizzCastBarEvents()
    local barList = CludesUI._BlizzCastBars()
    local snapshot = {}
    for idx = 1, #barList do
        snapshot[idx] = barList[idx].frame:IsEventRegistered("UNIT_SPELLCAST_START") and true or false
    end
    CludesUI._blizzCastBarSnapshot = snapshot
end

function CludesUI.RestoreBlizzCastBarEvents()
    local snapshot = CludesUI._blizzCastBarSnapshot
    if not snapshot then
        return
    end
    CludesUI._blizzCastBarSnapshot = nil

    local barList = CludesUI._blizzCastBarList
    for idx = 1, #barList do
        local barFrame = barList[idx]
        local live = barFrame.frame:IsEventRegistered("UNIT_SPELLCAST_START") and true or false
        if live ~= snapshot[idx] then
            if not live then
                barFrame.owned = true
            elseif barFrame.owned then
                barFrame.owned = false
            elseif barFrame.foreign then
                -- Another addon silenced this frame and we just re-registered it
                -- on the way past; put it back the way we found it instead of
                -- resurrecting Blizzard's cast bar next to theirs.
                barFrame.frame:UnregisterAllEvents()
                barFrame.frame:Hide()
            else
                -- Registered inside our own window with nobody claiming it.
                -- That is CUI's own bookkeeping having lost track (a silence
                -- that produced no transition to observe), NOT another addon,
                -- so re-silencing here would kill Blizzard's cast bar for the
                -- session with no way back short of a reload. Leave it armed:
                -- a visible Blizzard bar is something the user can turn off, a
                -- dead one is not.
            end
        end
    end
end

-- The cast events Blizzard's bars listen on, registered per unit. Mirrors the set oUF's
-- Castbar element restores when it disables, which is the only path that has ever successfully re-armed these frames.
--
-- SetUnit is deliberately NOT used to re-arm: its body is guarded on `self.unit ~= unit`, and
-- the frame still holds the unit Blizzard assigned at load, so passing that same unit registers
-- nothing at all. Forcing the guard open is worse -- SetUnit runs StopAnims -> StopFinishAnims,
-- which iterates a table that cannot be accessed while tainted, so from addon execution it throws
-- outright ("attempted to iterate a table that cannot be accessed while tainted") and takes down
-- whatever called it. Registering the events directly is what oUF does, is taint-clean, and touches no Blizzard code at all.
local BLIZZ_CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

-- Give Blizzard's cast bars their event wiring back, unless another addon has claimed them.
-- Covers the pet bar too: oUF silences both and only re-arms them from its Castbar element's
-- Disable, so any release path that does not run that (the element was never enabled to begin with) leaves both dead.
function CludesUI.RearmBlizzCastBars()
    local barList = CludesUI._blizzCastBarList
    if not barList then
        return
    end
    for idx = 1, #barList do
        local barFrame = barList[idx]
        if not barFrame.foreign and not barFrame.frame:IsEventRegistered("UNIT_SPELLCAST_START") then
            barFrame.owned = false
            for jdx = 1, #BLIZZ_CAST_EVENTS do
                barFrame.frame:RegisterUnitEvent(BLIZZ_CAST_EVENTS[jdx], barFrame.unit)
            end
            barFrame.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
            if barFrame.unit == "pet" then
                barFrame.frame:RegisterEvent("UNIT_PET")
            end
        end
    end
end

-- Arm the ownership hooks at load rather than on first capture. Rearm's only shield against
-- resurrecting a bar a standalone cast bar addon silenced is the foreign flag, and that flag can
-- only be set once the UnregisterAllEvents hooks exist -- a lazy first capture at PLAYER_LOGIN
-- leaves every earlier silence unattributed. File scope runs during the ADDON_LOADED sequence,
-- before any addon's PLAYER_LOGIN handler, so this closes the window to everything except
-- file-scope silences in addons that load before CUI. Guarded on BOTH frames: the list is cached on first build, so building it while either frame is missing would drop that bar for the whole session.
if PlayerCastingBarFrame and PetCastingBarFrame then
    CludesUI._BlizzCastBars()
end

-------------------------------------------------------------------------------
--  Shared Player Cast Bar Suppression -- multiple CUI modules can temporarily suppress
--  Blizzard's player cast bar while they render their own. Centralized here so modules cooperate
--  with each other and leave third-party visibility control alone once no CUI module is actively using a replacement bar.
-------------------------------------------------------------------------------
function CludesUI.SetPlayerCastBarSuppressed(ownerFrame, suppressed)
    if not ownerFrame or ownerFrame == "" then
        return
    end

    local owners = CludesUI._playerCastBarSuppressors
    if not owners then
        owners = {}
        CludesUI._playerCastBarSuppressors = owners
    end

    if suppressed then
        owners[ownerFrame] = true
    else
        owners[ownerFrame] = nil
    end

    local stockBar = PlayerCastingBarFrame
    if not stockBar then
        return
    end

    local shouldSuppress = next(owners) ~= nil
    local hiddenHost = CludesUI._playerCastBarHiddenParent

    if shouldSuppress then
        if not hiddenHost then
            hiddenHost = CreateFrame("Frame")
            hiddenHost:Hide()
            CludesUI._playerCastBarHiddenParent = hiddenHost
        end

        if stockBar:GetParent() ~= hiddenHost then
            CludesUI._GetFFD(stockBar).origParent = stockBar:GetParent()
        end
        CludesUI._GetFFD(stockBar).castBarSuppressed = true

        -- Skip the re-parent while Edit Mode is open: SetParent fires Blizzard's synchronous
        -- layout handlers in this execution, and the UnitFrames Edit-Mode-close hook re-applies this state afterwards.
        if
            stockBar:GetParent() ~= hiddenHost
            and not (EditModeManagerFrame and EditModeManagerFrame:IsShown())
        then
            stockBar:SetParent(hiddenHost)
        end

        -- Edit Mode re-anchors the cast bar on every layout apply (spec changes, and every
        -- level-up on WoW Forever); keep re-applying our hidden parent while any CUI owner
        -- suppresses it. The re-park runs in the SAME frame from a one-shot OnUpdate on a
        -- frame of ours (after this frame's handlers, before it renders; a timer showed
        -- Blizzard's bar for a frame), so no addon code runs inside Blizzard's call. In
        -- combat it waits for PLAYER_REGEN_ENABLED instead of being dropped: leaving the
        -- managed layout must not run from addon code in combat, and a dropped re-park
        -- left Blizzard's bar on screen for the rest of the session.
        if not CludesUI._GetFFD(stockBar).setParentHooked then
            CludesUI._GetFFD(stockBar).setParentHooked = true
            local repark = CreateFrame("Frame")
            repark:Hide()
            local function Repark()
                -- Never re-parent while Edit Mode is open: SetParent fires Blizzard's
                -- synchronous layout handlers under addon taint and poisons the manager's state for its next pass (the Edit Mode close hook in UnitFrames re-applies suppression).
                if
                    CludesUI._GetFFD(stockBar).castBarSuppressed
                    and not (EditModeManagerFrame and EditModeManagerFrame:IsShown())
                    and stockBar:GetParent() ~= CludesUI._playerCastBarHiddenParent
                then
                    stockBar:SetParent(CludesUI._playerCastBarHiddenParent)
                end
            end
            repark:SetScript("OnUpdate", function(self)
                self:Hide()
                if InCombatLockdown() then
                    self:RegisterEvent("PLAYER_REGEN_ENABLED")
                else
                    Repark()
                end
            end)
            repark:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                Repark()
            end)
            hooksecurefunc(stockBar, "SetParent", function(self, newParent)
                if
                    CludesUI._GetFFD(self).castBarSuppressed
                    and newParent ~= CludesUI._playerCastBarHiddenParent
                then
                    repark:Show()
                end
            end)
        end

        local picked = stockBar.Selection
        if picked then
            if not CludesUI._GetFFD(picked).suppressed then
                CludesUI._GetFFD(picked).restoreAlpha = picked:GetAlpha()
                CludesUI._GetFFD(picked).restoreMouse = picked:IsMouseEnabled()
            end
            CludesUI._GetFFD(picked).suppressed = true
            picked:SetAlpha(0)
            picked:EnableMouse(false)

            if not CludesUI._GetFFD(picked).showHooked then
                CludesUI._GetFFD(picked).showHooked = true
                hooksecurefunc(picked, "Show", function(self)
                    -- Deferred: Show fires inside Edit Mode's secure ShowSystemSelections pass; write nothing there.
                    C_Timer.After(0, function()
                        if
                            PlayerCastingBarFrame
                            and CludesUI._GetFFD(PlayerCastingBarFrame).castBarSuppressed
                        then
                            self:SetAlpha(0)
                            self:EnableMouse(false)
                        end
                    end)
                end)
            end
        end

        return
    end

    CludesUI._GetFFD(stockBar).castBarSuppressed = false

    -- Hand the bar back to the parent CUI took it from -- but never to one that is itself hidden.
    -- Blizzard parents this bar under PlayerFrame, and Edit Mode re-parents it into a layout frame
    -- that gets hidden on exit, while CUI hides PlayerFrame whenever it renders its own player
    -- frame. Restoring there leaves Blizzard's cast bar fully armed but permanently invisible,
    -- which reads exactly like the suppression never lifted. UIParent is where Edit Mode positions the bar from anyway, and SetParent keeps the existing anchors, so the bar still lands where the user had it.
    local origParent = CludesUI._GetFFD(stockBar).origParent
    local currentParent = stockBar:GetParent()
    local restoreHost = origParent
    if not restoreHost or not restoreHost.IsVisible or not restoreHost:IsVisible() then
        restoreHost = UIParent
    end

    -- Only ever un-park a bar CUI itself parked: either it is still sitting in our hidden parent,
    -- or an earlier release handed it back to the captured parent and that parent is itself
    -- hidden. Matching the captured parent exactly is what separates "Blizzard's own parent
    -- happens to be hidden" from "another addon parked this bar under its own hidden frame" -- the latter is left alone, since resurrecting it is the bug this whole ownership dance exists to prevent.
    local parkedByUs = (hiddenHost and currentParent == hiddenHost)
        or (
            origParent
            and currentParent == origParent
            and currentParent.IsVisible
            and not currentParent:IsVisible()
        )

    -- The Edit Mode gate can skip this; ApplyBlizzCastbarState re-runs the release on
    -- PLAYER_ENTERING_WORLD and on Edit Mode close, so a bar left parked by a skipped pass is healed as soon as re-parenting is legal.
    if
        parkedByUs
        and currentParent ~= restoreHost
        and not (EditModeManagerFrame and EditModeManagerFrame:IsShown())
    then
        stockBar:SetParent(restoreHost)
    end

    local picked = stockBar.Selection
    if picked and CludesUI._GetFFD(picked).suppressed then
        CludesUI._GetFFD(picked).suppressed = false
        picked:SetAlpha(CludesUI._GetFFD(picked).restoreAlpha or 1)
        picked:EnableMouse(CludesUI._GetFFD(picked).restoreMouse or false)
    end

    -- Let Blizzard rebuild its normal event wiring without forcing visibility back on, so profile
    -- switches and UnitFrames/oUF teardown stay compatible with Blizzard's own cast bar logic.
    -- Only when CUI silenced the frame in the first place: a standalone cast bar addon silences
    -- the same frame, and re-registering its events is what pops Blizzard's cast bar back on screen next to theirs once CUI's own cast bar is switched off.
    CludesUI.RearmBlizzCastBars()
end

-------------------------------------------------------------------------------
--  Swiftmend Brightness Fix (shared hook utility) -- Blizzard dims Swiftmend based on
--  Efflorescence state (secret value in Midnight). Child addons call this on icon textures they identify as Swiftmend; the hook prevents vertex-color dimming and desaturation.
-------------------------------------------------------------------------------
do
    local hooked = {}
    local function isEnabled()
        return not CludesUIDB or CludesUIDB.brightenSwiftmend ~= false
    end
    function CludesUI._HookSwiftmendIcon(texture)
        if not texture or hooked[texture] then
            -- Already hooked; just force bright if re-enabling
            if texture and hooked[texture] and isEnabled() then
                texture:SetVertexColor(1, 1, 1)
            end
            return
        end
        hooked[texture] = true
        local vcGuard = false
        hooksecurefunc(texture, "SetVertexColor", function(_, red, green, blue)
            if not vcGuard and isEnabled() and not (red == 1 and green == 1 and blue == 1) then
                vcGuard = true
                texture:SetVertexColor(1, 1, 1)
                vcGuard = false
            end
        end)
        -- Force bright immediately (icon may already be dimmed before hook)
        if isEnabled() then
            texture:SetVertexColor(1, 1, 1)
        end
    end
    CludesUI._SWIFTMEND_SPELL = 18562
    CludesUI._SWIFTMEND_ICON = 134914
end

-------------------------------------------------------------------------------
--  Level difficulty colors (unit frame and nameplate level text), Blizzard's
--  rule: "??" (level <= 0) red, a unit you cannot attack gold, otherwise the
--  color for its level against yours.
-------------------------------------------------------------------------------
function CludesUI.GetLevelDifficultyColor(lvl, attackable)
    if lvl <= 0 then
        return 1, 0.1, 0.1
    end
    if not attackable then
        local c = UNIT_LEVEL_NON_ATTACKABLE
        if c then
            return c.r, c.g, c.b
        end
        return 1, 0.82, 0
    end
    local mine = UnitEffectiveLevel("player")
    if issecretvalue and issecretvalue(mine) then
        return nil
    end
    if CludesUI.IS_FOREVER then
        -- WoW Forever's own nameplate rule (the vanilla one): grey past the
        -- trivial range, green 3+ below, yellow within 2, orange 3-4 above, red 5+.
        local diff = lvl - mine
        local fc
        if diff < -C_QuestLog.GetTrivialRange() then
            fc = TRIVIAL_DIFFICULTY_COLOR
        elseif diff <= -3 then
            fc = EASY_DIFFICULTY_COLOR
        elseif diff <= 2 then
            fc = FAIR_DIFFICULTY_COLOR
        elseif diff <= 4 then
            fc = DIFFICULT_DIFFICULTY_COLOR
        else
            fc = IMPOSSIBLE_DIFFICULTY_COLOR
        end
        if fc then
            return fc.r, fc.g, fc.b
        end
        return nil
    end
    local color = (GetRelativeDifficultyColor and GetRelativeDifficultyColor(mine, lvl))
        or (GetQuestDifficultyColor and GetQuestDifficultyColor(lvl))
    if color then
        return color.r, color.g, color.b
    end
end
-- For a unit; nil when the level or attackability cannot be read (secret).
-- includeFriendly: friendly units get their difficulty color too, not gold.
function CludesUI.GetLevelColor(unitToken, lvl, includeFriendly)
    local sv = issecretvalue
    if lvl == nil or (sv and sv(lvl)) then
        return nil
    end
    if includeFriendly then
        return CludesUI.GetLevelDifficultyColor(lvl, true)
    end
    local attackable = UnitCanAttack("player", unitToken)
    if sv and sv(attackable) then
        return nil
    end
    return CludesUI.GetLevelDifficultyColor(lvl, attackable)
end
function CludesUI.ColorText(textValue, red, green, blue)
    if not red then
        return textValue
    end
    return ("|cff%02x%02x%02x%s|r"):format(
        math.floor(red * 255 + 0.5),
        math.floor(green * 255 + 0.5),
        math.floor(blue * 255 + 0.5),
        textValue
    )
end

-------------------------------------------------------------------------------
--  Faction badge art, shared by the unit frame and nameplate faction indicators
--  and their options previews. Each style is a Horde/Alliance pair, an atlas or a
--  file; "%s" takes the faction ("lower" = lowercased, "num" = 1 Horde / 2 Alliance).
--  "coords" crops a file whose art does not fill it (the Classic banner sits in the
--  top-left 42 of 64 pixels).
--  Unknown styles fall back to "pvp", the default.
-------------------------------------------------------------------------------
CludesUI.FACTION_ART = {
    pvp = { atlas = "UI-HUD-UnitFrame-Player-PVP-%sIcon" },
    honor = { atlas = "honorsystem-portrait-%s", lower = true, badge = true },
    poi = { atlas = "poi-%s", lower = true },
    classic = { file = "Interface\\TargetingFrame\\UI-PVP-%s", coords = { 0, 0.65625, 0, 0.65625 } },
    banner = { file = "Interface\\Icons\\INV_BannerPVP_0%s", num = true },
    honoricon = { file = "Interface\\Icons\\PVPCurrency-Honor-%s" },
    friends = { file = "Interface\\FriendsFrame\\PlusManz-%s" },
}
CludesUI.FACTION_ART_ORDER = { "pvp", "honor", "poi", "classic", "banner", "honoricon", "friends" }
CludesUI.FACTION_ART_LABELS = {
    pvp = "PvP Emblem",
    honor = "Honor Portrait",
    poi = "Map Flag",
    classic = "Classic Banner",
    banner = "Banner Icon",
    honoricon = "Honor Icon",
    friends = "Friends Crest",
}
-- Honor Portrait is an empty hexagon; the unit's honor badge is drawn on top (30 on 50).
-- Returns that badge's file id, or nil. Callers pass it to SetFactionArt and memoize it.
local HONOR_BADGE_RATIO = 30 / 50
local honorBadgeFiles = {}
function CludesUI.FactionBadgeFor(style, unitToken)
    local artTex = CludesUI.FACTION_ART[style]
    if not (artTex and artTex.badge and unitToken) then
        return nil
    end
    local lvl = UnitHonorLevel and UnitHonorLevel(unitToken)
    if issecretvalue(lvl) or not lvl or lvl <= 0 then
        return nil
    end
    local filePath = honorBadgeFiles[lvl]
    if filePath == nil then
        local details = C_PvP and C_PvP.GetHonorRewardInfo and C_PvP.GetHonorRewardInfo(lvl)
        filePath = (details and details.badgeFileDataID) or false
        honorBadgeFiles[lvl] = filePath
    end
    return filePath or nil
end

-- The badge sits on a frame that follows the faction texture (textures cannot be parents);
-- the texture's Show/Hide/alpha/desaturation are mirrored onto it.
local function GetBadgeHost(texture)
    local owner = texture._honorBadgeHost
    if owner then
        return owner
    end
    local par = texture:GetParent()
    owner = CreateFrame("Frame", nil, par)
    owner:SetAllPoints(texture)
    owner:SetFrameLevel(par:GetFrameLevel() + 1)
    owner:Hide()
    owner:SetAlpha(texture:GetAlpha())
    local icon = owner:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("CENTER")
    icon:SetDesaturated(texture:IsDesaturated())
    owner.icon = icon
    owner:SetScript("OnSizeChanged", function(_, wid)
        local s = wid * HONOR_BADGE_RATIO
        icon:SetSize(s, s)
    end)
    hooksecurefunc(texture, "Hide", function()
        owner:Hide()
    end)
    hooksecurefunc(texture, "Show", function()
        if owner.wanted then
            owner:Show()
        end
    end)
    hooksecurefunc(texture, "SetAlpha", function(_, a)
        owner:SetAlpha(a)
    end)
    hooksecurefunc(texture, "SetDesaturated", function(_, d)
        icon:SetDesaturated(d)
    end)
    texture._honorBadgeHost = owner
    return owner
end

local function SetBadge(texture, filePath)
    local owner = texture._honorBadgeHost
    if not filePath then
        if owner then
            owner.wanted = false
            owner:Hide()
        end
        return
    end
    owner = owner or GetBadgeHost(texture)
    owner.icon:SetTexture(filePath)
    local wid = texture:GetWidth()
    if wid and wid > 0 then
        local s = wid * HONOR_BADGE_RATIO
        owner.icon:SetSize(s, s)
    end
    owner.wanted = true
    if texture:IsShown() then
        owner:Show()
    end
end

function CludesUI.SetFactionArt(texture, style, faction, badgeFile)
    SetBadge(texture, badgeFile)
    local artTex = CludesUI.FACTION_ART[style] or CludesUI.FACTION_ART.pvp
    -- The resolved atlas or file name is built once per style and faction and kept
    -- on the style's entry (art.Horde / art.Alliance).
    local label = artTex[faction]
    if not label then
        local key = faction
        if artTex.lower then
            key = faction:lower()
        elseif artTex.num then
            key = (faction == "Horde") and "1" or "2"
        end
        label = (artTex.atlas or artTex.file):format(key)
        artTex[faction] = label
    end
    if artTex.atlas then
        -- SetAtlas keeps an earlier SetTexCoord (e.g. the Classic banner's crop)
        -- unless told to reset it, so clear it first and ask for the reset too.
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetAtlas(label, false, nil, true)
    else
        texture:SetTexture(label)
        local c = artTex.coords
        if c then
            texture:SetTexCoord(c[1], c[2], c[3], c[4])
        else
            texture:SetTexCoord(0, 1, 0, 1)
        end
    end
end

-------------------------------------------------------------------------------
--  Secret values (12.1): the one test every module uses, and the string reader
--  that gives back a readable, non-empty string or nil. Hot paths import both
--  as locals; no module keeps a copy.
-------------------------------------------------------------------------------
local issecretvalue = issecretvalue or function()
    return false
end
function CludesUI.IsSecret(val)
    return val ~= nil and issecretvalue(val)
end
function CludesUI.PlainString(val)
    -- The secrecy test comes first: comparing a secret string raises.
    if type(val) == "string" and not issecretvalue(val) and val ~= "" then
        return val
    end
    return nil
end

-------------------------------------------------------------------------------
--  Power text formats ("smart", "curpp", "perpp", ...): WoW Forever offers no
--  Smart Text, which chooses percent or value by spec, and Forever has no
--  specs. There a saved "smart" reads as the value (Power Value, "curpp"; the
--  Unit Frames smart rule, CludesUI.IsSmartPowerPercent, answers no there),
--  and every format list leaves it out. Stored values moved once
--  (forever_power_text_value_v1, CludesUI_Migration.lua).
-------------------------------------------------------------------------------
function CludesUI.PowerTextFormat(fmt)
    if fmt == "smart" and CludesUI.IS_FOREVER then
        return "curpp"
    end
    return fmt
end
-- A format dropdown's order list for this client: the same table, or on WoW
-- Forever a copy without "smart".
function CludesUI.PowerTextFormatOrder(sequence)
    if not CludesUI.IS_FOREVER then
        return sequence
    end
    local result = {}
    for idx = 1, #sequence do
        if sequence[idx] ~= "smart" then
            result[#result + 1] = sequence[idx]
        end
    end
    return result
end

-------------------------------------------------------------------------------
--  Guard table of a split module: the main file's names that its part files
--  re-import. setters maps Set<Name> to a list in t; Set<Name>(v) hands v to
--  every function in that list, and a function added to the list after a
--  Set<Name> call gets the last value at once (registered as
--  list[#list + 1] = fn: table.insert sets raw and skips that). broken starts
--  false (a file chain that guards on t.last ignores it). Reading a name the
--  table lacks raises at the reader; label names the owner in that message
--  (default "ns"). The parent's own chain calls the private copy on CUI_NS, so
--  the parent's namespace never passes through a public slot.
-------------------------------------------------------------------------------
do
    local function NewFanOut(entries)
        local has, current = false, nil
        setmetatable(entries, {
            __newindex = function(l, idx, func)
                rawset(l, idx, func)
                if has then
                    func(current)
                end
            end,
        })
        return function(val)
            has, current = true, val
            for idx = 1, #entries do
                entries[idx](val)
            end
        end
    end

    local function NewInternals(mod, field, tbl, setters, labelText)
        local label = (labelText or "ns") .. "." .. field
        if setters then
            for setter, listName in pairs(setters) do
                local entries = tbl[listName]
                if type(entries) ~= "table" then
                    error(label .. ": " .. setter .. " has no list " .. tostring(listName), 2)
                end
                tbl[setter] = NewFanOut(entries)
            end
        end
        tbl.broken = false
        mod[field] = setmetatable(tbl, {
            __index = function(_, key)
                error(label .. " has no entry " .. tostring(key), 2)
            end,
        })
        return mod[field]
    end
    CUI_NS.NewInternals = NewInternals
    CludesUI.NewInternals = NewInternals
end

-------------------------------------------------------------------------------
--  Detached portrait click buttons (Unit Frames and Party Frames)
--  A detached portrait floats outside its unit button, so clicks on it fall
--  through to the world. While a module's Clickable Portrait is on, a second
--  secure unit button for the same unit covers the portrait, set up like the
--  owner's own: target on left-click, the secure menu on right-click, and
--  handed to click-casting, so Blizzard's native click casting, CUI's engine
--  and click-cast addons bind it as they bind the owner. Hover replays the
--  owner's own hover work through the module's callbacks.
--  The overlay is parented to the owner and anchored to it by measured
--  offsets, never to the backdrop: a protected frame anchored to the backdrop
--  would lock the backdrop's anchors in combat. Built on the first wanted
--  sync; out of combat only (in combat it re-runs at combat end).
--    owner : the unit button the portrait belongs to
--    cfg   : one static table per module:
--      wanted(owner)   -> true while the overlay should cover the portrait
--      backdrop(owner) -> the portrait backdrop frame
--      onEnter(owner), onLeave(owner) -> the owner's own hover work
--      register(btn)   -> hands the overlay to click-casting
--      parentUnit      -> true: the unit resolves through the owner (header
--                         buttons, whose unit moves in combat); else the
--                         owner's unit attribute is copied once
--  Returns true while the owner wants the overlay (placed, or waiting for a
--  rect); nil when it does not, and in combat.
-------------------------------------------------------------------------------
do
    local overlays = setmetatable({}, { __mode = "k" }) -- owner -> overlay
    local pending = setmetatable({}, { __mode = "k" }) -- owner -> cfg, awaiting a rect
    local placed = setmetatable({}, { __mode = "k" }) -- overlay -> its last offsets and size

    local function OverlayEnter(self)
        local conf = self._cuiPtCfg
        if conf and conf.onEnter then
            conf.onEnter(self:GetParent())
        end
    end
    local function OverlayLeave(self)
        local conf = self._cuiPtCfg
        if conf and conf.onLeave then
            conf.onLeave(self:GetParent())
        end
    end

    local Sync
    Sync = function(ownerFrame, conf)
        local button = overlays[ownerFrame]
        if not button and not conf.wanted(ownerFrame) then
            return
        end
        if InCombatLockdown() then
            CludesUI.CombatQueue.Defer(ownerFrame, function()
                Sync(ownerFrame, conf)
            end)
            return
        end
        if not conf.wanted(ownerFrame) then
            pending[ownerFrame] = nil
            button:Hide()
            return
        end
        if not button then
            local label = ownerFrame:GetName()
            button = CreateFrame(
                "Button",
                label and (label .. "PortraitClick"),
                ownerFrame,
                "SecureUnitButtonTemplate"
            )
            if conf.parentUnit then
                button:SetAttribute("useparent-unit", true)
            else
                button:SetAttribute("unit", ownerFrame:GetAttribute("unit"))
            end
            button:SetAttribute("*type1", "target")
            button:SetAttribute("toggleForVehicle", true)
            button:RegisterForClicks("AnyUp")
            CludesUI.AttachSecureUnitMenu(button)
            button._cuiPtCfg = conf
            button:HookScript("OnEnter", OverlayEnter)
            button:HookScript("OnLeave", OverlayLeave)
            overlays[ownerFrame] = button
            if conf.register then
                conf.register(button)
            end
            -- An owner never shown yet has no rect to measure: measure on its first show.
            ownerFrame:HookScript("OnShow", function(o)
                local c = pending[o]
                if c then
                    Sync(o, c)
                end
            end)
        end
        local edge = conf.backdrop(ownerFrame)
        local fl, ft = ownerFrame:GetLeft(), ownerFrame:GetTop()
        local bl, bt = edge:GetLeft(), edge:GetTop()
        if not (fl and ft and bl and bt) then
            pending[ownerFrame] = conf
            button:Hide()
            return true
        end
        pending[ownerFrame] = nil
        -- Placed again only when the portrait moved or resized against the owner.
        local k = edge:GetEffectiveScale() / ownerFrame:GetEffectiveScale()
        local x, y = bl * k - fl, bt * k - ft
        local wid, hgt = edge:GetWidth() * k, edge:GetHeight() * k
        local r = placed[button]
        if not r then
            r = {}
            placed[button] = r
        end
        if r.x ~= x or r.y ~= y or r.w ~= wid or r.h ~= hgt then
            r.x, r.y, r.w, r.h = x, y, wid, hgt
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", ownerFrame, "TOPLEFT", x, y)
            button:SetSize(wid, hgt)
        end
        -- The layer is read back from the overlay: a strata change on the owner moves it too.
        local strata = edge:GetFrameStrata()
        if button:GetFrameStrata() ~= strata then
            button:SetFrameStrata(strata)
        end
        local lvl = edge:GetFrameLevel() + 1
        if button:GetFrameLevel() ~= lvl then
            button:SetFrameLevel(lvl)
        end
        button:Show()
        return true
    end
    CludesUI.SyncPortraitClick = Sync
end

-- 3D models ignore parent alpha, UIParent's too: UIScaledAlpha applies a UIParent
-- fade to a model's mirrored alpha; OnUIAlphaChanged hooks UIParent:SetAlpha lazily.
do
    local listeners, lastAlpha
    local function Notify()
        -- The listeners' one input is UIParent's alpha: a SetAlpha that repeats the last
        -- one moves nothing. A secret alpha cannot be compared, so it always notifies.
        local ui = UIParent:GetAlpha()
        if issecretvalue(ui) then
            lastAlpha = nil
        elseif ui == lastAlpha then
            return
        else
            lastAlpha = ui
        end
        for idx = 1, #listeners do
            listeners[idx]()
        end
    end
    function CludesUI.UIScaledAlpha(a)
        local ui = UIParent:GetAlpha()
        if issecretvalue(ui) or ui >= 1 then
            return a
        end
        if issecretvalue(a) then
            return ui <= 0 and 0 or a
        end
        return a * ui
    end
    function CludesUI.OnUIAlphaChanged(func)
        if not listeners then
            listeners = {}
            hooksecurefunc(UIParent, "SetAlpha", Notify)
        end
        for idx = 1, #listeners do
            if listeners[idx] == func then
                return
            end
        end
        listeners[#listeners + 1] = func
    end
end

-------------------------------------------------------------------------------
--  Full Craft Time (player cast bars). A repeat craft queues the rest of the
--  batch behind the current cast. SetCraftBatch fills f._craftExtra (seconds
--  queued after this cast), the batch total and the " (n/N)" name suffix, or
--  clears them when on is false or the cast is not part of a batch. Done
--  counts finished casts so the total stays fixed; a re-read of the same cast
--  (settings refresh mid-cast) keeps the batch as is.
-------------------------------------------------------------------------------
do
    local floor, format = math.floor, string.format

    function CludesUI.SetCraftBatch(f, enabled, spellId, castID, castDur)
        local getLeft = C_TradeSkillUI and C_TradeSkillUI.GetRemainingRecasts
        if not (enabled and getLeft) then
            f._craftExtra, f._craftLeft = nil, nil
            return
        end
        local leftX = getLeft() or 0
        if castID and castID == f._craftCast then
            leftX = f._craftLeft or leftX
        elseif f._craftLeft and spellId == f._craftSpell and leftX == f._craftLeft - 1 then
            f._craftDone = f._craftDone + 1
        else
            f._craftDone = 0
        end
        f._craftLeft, f._craftSpell, f._craftCast = leftX, spellId, castID
        if leftX == 0 and f._craftDone == 0 then
            f._craftExtra = nil
            return
        end
        local done = f._craftDone
        local sum = floor((done + 1 + leftX) * castDur)
        f._craftExtra = leftX * castDur
        f._craftTotal = sum
        f._craftTotalSuffix = format(" / %d:%02d", floor(sum / 60), sum % 60)
        f._craftCountSuffix = format(" (%d/%d)", done + 1, done + 1 + leftX)
        f._craftSecs = nil
    end

    -- Whole batch left (or elapsed / total), repainted once per second.
    function CludesUI.SetCraftTimerText(f, fontStr, remaining, totalMode)
        local leftX = (remaining > 0 and remaining or 0) + f._craftExtra
        local secs = floor(totalMode and (f._craftTotal - leftX) or leftX)
        if secs < 0 then
            secs = 0
        end
        if secs ~= f._craftSecs then
            f._craftSecs = secs
            fontStr:SetText(
                format("%d:%02d", floor(secs / 60), secs % 60) .. (totalMode and f._craftTotalSuffix or "")
            )
        end
    end
end

-------------------------------------------------------------------------------
--  Cast names: the client names the quest-object cast "Opening - No Text";
--  cast bars show the plain "Opening". A secret or non-string name is returned
--  as it is.
-------------------------------------------------------------------------------
function CludesUI.CleanCastName(label)
    if issecretvalue(label) or type(label) ~= "string" then
        return label
    end
    local clean = label:gsub("%s*%-%s*No Text$", "")
    return clean ~= "" and clean or label
end

-------------------------------------------------------------------------------
--  Show Full Spell Name (cast bars). Shrinks the spell name's font just enough
--  for the whole name to fit the FontString's set width, and puts it back at
--  baseSize for names that already fit. Measured on a private FontString that
--  only ever holds clean text, so the cast text's own (possibly secret) metrics
--  are never read. A secret name stays at baseSize and truncates as before.
--  A name on one of our font families (CludesUI.SetFontFamily: it may hold a
--  target's name) keeps a family at every size and is measured on one, so a
--  Cyrillic, Korean or Chinese name is measured in the face that draws it.
-------------------------------------------------------------------------------
do
    local floor = math.floor
    local MIN_SIZE = 6
    local measure, measureFam

    -- fs's face, size and flags. A string on one of our families gives its roman
    -- member's (the chosen font, whatever script the text holds), true, and
    -- whether the family carries a shadow; any other string its own GetFont.
    local function FontOf(fontStr)
        local fo = fontStr:GetFontObject()
        local set = CludesUI._fontFamilySet
        if fo and set and set[fo] and fo.GetFontObjectForAlphabet then
            local roman = fo:GetFontObjectForAlphabet("roman")
            local face, size, flags
            if roman then
                face, size, flags = roman:GetFont()
            end
            if face then
                local _, _, _, sa = fo:GetShadowColor()
                return face, size, flags, true, (sa or 0) > 0
            end
        end
        local face, size, flags = fontStr:GetFont()
        return face, size, flags, false, false
    end

    -- Two measuring strings: a plain SetFont pins a string's face, so the one that
    -- takes families never takes a plain font.
    local function MeasureString(fam)
        local m
        if fam then
            m = measureFam
        else
            m = measure
        end
        if not m then
            m = UIParent:CreateFontString(nil, "BACKGROUND")
            m:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 100, -100)
            m:SetAlpha(0)
            if fam then
                measureFam = m
            else
                measure = m
            end
        end
        return m
    end

    -- Width of a clean string in fs's font face (at size, or fs's own size).
    local function Measure(fontStr, str, size)
        local font, current, flags, isFam, shadow = FontOf(fontStr)
        if not font then
            return 0
        end
        local fam = isFam and CludesUI.GetFontFamily(font, size or current, flags, shadow)
        local m = MeasureString(fam)
        if fam then
            m:SetFontObject(fam)
        else
            m:SetFont(font, size or current, flags)
        end
        m:SetText(str)
        return m:GetUnboundedStringWidth() or 0
    end
    CludesUI.MeasureCastText = Measure

    function CludesUI.FitCastName(fontStr, str, baseSize)
        local font, current, flags, isFam, shadow = FontOf(fontStr)
        if not font then
            return
        end
        local size = baseSize
        local room = fontStr:GetWidth()
        if str and not issecretvalue(str) and str ~= "" and room and not issecretvalue(room) and room > 1 then
            local wid = Measure(fontStr, str, baseSize)
            -- 1px slack: glyph hinting can round a scaled string up a pixel.
            if wid and wid > room - 1 then
                size = floor(baseSize * (room - 1) / wid * 2) / 2
                if size < MIN_SIZE then
                    size = MIN_SIZE
                end
            end
        end
        if current ~= size then
            if isFam then
                CludesUI.SetFontFamily(fontStr, font, size, flags, shadow)
            else
                fontStr:SetFont(font, size, flags)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Blizzard's animated rest icon (PlayerFrame.xml PlayerRestLoop) on `tex`:
--  the flipbook atlas, a 6 x 7 grid of 42 frames, looping while `frame` is
--  shown. MUST use SetAtlas: a raw SetTexture slices the sheet's padding into
--  the FlipBook. `duration` is one loop in seconds (Blizzard: 1.5). Build once
--  per frame of ours: it sets the frame's OnShow and OnHide scripts.
-------------------------------------------------------------------------------
function CludesUI.AddRestFlipbook(widget, texture, duration)
    texture:SetAtlas("UI-HUD-UnitFrame-Player-Rest-Flipbook")
    local anim = widget:CreateAnimationGroup()
    anim:SetLooping("REPEAT")
    if anim.SetToFinalAlpha then
        anim:SetToFinalAlpha(true)
    end
    local flipped = anim:CreateAnimation("FlipBook")
    flipped:SetTarget(texture)
    flipped:SetDuration(duration or 1.5)
    flipped:SetOrder(1)
    if flipped.SetSmoothing then
        flipped:SetSmoothing("NONE")
    end
    flipped:SetFlipBookRows(7)
    flipped:SetFlipBookColumns(6)
    flipped:SetFlipBookFrames(42)
    flipped:SetFlipBookFrameWidth(0)
    flipped:SetFlipBookFrameHeight(0)
    widget:SetScript("OnShow", function()
        anim:Play()
    end)
    widget:SetScript("OnHide", function()
        anim:Stop()
    end)
    return anim
end

-------------------------------------------------------------------------------
--  WoW Forever talent trees, read by Forever Essentials' Classic Talents
--  window and the Talent Conditions picker (CludesUI.ShowTalentConditionsPopup).
--  The active config's one trait tree holds the class's three vanilla trees
--  as trait groups.
-------------------------------------------------------------------------------
do
    local function ByOrder(a, b)
        return a.orderIndex < b.orderIndex
    end

    -- The active config ID and tree ID, and the trees in their order, each
    -- { groupID, name, nodes = { nodeID, ... } } with its visible talents
    -- (name: the game's own). The list is nil while there is no tree.
    function CludesUI.ForeverTalentTrees()
        local configId = C_ClassTalents.GetActiveConfigID()
        local config = configId and C_Traits.GetConfigInfo(configId)
        local treeID = config and config.treeIDs[1]
        if not treeID then
            return configId, nil, nil
        end
        local groups = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
        table.sort(groups, ByOrder)
        local trees, byGroup = {}, {}
        for idx, group in ipairs(groups) do
            trees[idx] = { groupID = group.groupID, name = group.displayName, nodes = {} }
            byGroup[group.groupID] = trees[idx]
        end
        for _, nodeId in ipairs(C_Traits.GetTreeNodes(treeID)) do
            local details = C_Traits.GetNodeInfo(configId, nodeId)
            if details and details.isVisible and details.entryIDs[1] then
                for _, groupID in ipairs(details.groupIDs) do
                    local t = byGroup[groupID]
                    if t then
                        t.nodes[#t.nodes + 1] = nodeId
                        break
                    end
                end
            end
        end
        return configId, treeID, trees
    end

    -- One axis of a tree's grid from its node positions: the first line, the
    -- step, and the last line before any position far beyond the rest. The step
    -- is the smallest gap between neighbouring positions above a quarter of the
    -- median gap: some nodes sit a few units off their line (the hunter's,
    -- paladin's and warlock's trees), and a gap that small is the same line, never
    -- a step of its own (taken as one, it spread a tree over hundreds of rows).
    local gaps = {}
    local function GridAxis(values)
        table.sort(values)
        local n = 0
        for idx = 2, #values do
            local d = values[idx] - values[idx - 1]
            if d > 0 then
                n = n + 1
                gaps[n] = d
            end
        end
        for idx = #gaps, n + 1, -1 do
            gaps[idx] = nil
        end
        local first = values[1] or 0
        if n == 0 then
            return first, 1, first
        end
        table.sort(gaps)
        local least = gaps[math.floor(n / 2) + 1] / 4
        local step
        for idx = 1, n do
            if gaps[idx] > least then
                step = gaps[idx]
                break
            end
        end
        -- Lines follow each other a few steps apart at most; past a bigger jump
        -- the rest lie off the grid (see Line).
        local last = first
        for idx = 2, #values do
            if values[idx] - values[idx - 1] > 4 * step then
                break
            end
            last = values[idx]
        end
        return first, step, last
    end

    -- A position's line (from 0) on one axis. A node far beyond the others whose
    -- tenth falls on the grid is read there: an extra zero in the game's data
    -- (the hunter's and priest's trees have such nodes).
    local function Line(val, first, step, last)
        if val > last + 4 * step then
            local t = val / 10
            local k = (t - first) / step
            local r = math.floor(k + 0.5)
            if r >= 0 and t <= last + step / 4 and math.abs(k - r) < 0.25 then
                val = t
            end
        end
        return math.floor((val - first) / step + 0.5)
    end

    -- Each talent's column and row (from 0) in its tree, from the node
    -- positions: cells[nodeID] = { col, row, info } and the row count.
    function CludesUI.TalentTreeGrid(configId, nodes)
        local xs, ys, infos = {}, {}, {}
        for idx, nodeId in ipairs(nodes) do
            local details = C_Traits.GetNodeInfo(configId, nodeId)
            infos[nodeId] = details
            xs[idx], ys[idx] = details.posX, details.posY
        end
        local x0, dx, xLast = GridAxis(xs)
        local y0, dy, yLast = GridAxis(ys)
        local cells, rowList = {}, 0
        for _, nodeId in ipairs(nodes) do
            local details = infos[nodeId]
            local col = Line(details.posX, x0, dx, xLast)
            local row = Line(details.posY, y0, dy, yLast)
            cells[nodeId] = { col = col, row = row, info = details }
            rowList = math.max(rowList, row)
        end
        return cells, rowList + 1
    end
end

-------------------------------------------------------------------------------
--  Talent Conditions: a list of { nodeID, entryID, spellID, taken } holds
--  while every talent it names is taken (a committed rank) or not taken, as
--  each entry asks. entryID only for a choice node (which side must be
--  picked); spellID is for display only. Read by the Cooldown Manager's
--  per-icon conditions and the WoW Forever swing timer; the picker is
--  CludesUI.ShowTalentConditionsPopup (CludesUIOptions).
--
--  Node states are cached per node for the active talent config (a new config
--  ID starts the cache over). Each reader wipes it on its own talent events
--  through CludesUI.TalentCondInvalidate, so nothing here listens.
-------------------------------------------------------------------------------
do
    -- nodeID -> the node's committed entryID when taken (true if the client
    -- reports a rank but no entry), false when not taken or not in the tree.
    local nodeState, nodeConfig = {}, nil

    function CludesUI.TalentCondInvalidate()
        wipe(nodeState)
        nodeConfig = nil
    end

    local function NodeState(nodeId, configId)
        if configId ~= nodeConfig then
            wipe(nodeState)
            nodeConfig = configId
        end
        local placerState = nodeState[nodeId]
        if placerState == nil then
            placerState = false
            -- Guarded: a saved nodeID can outlive a talent-tree rework in a patch.
            -- Runs on a cache miss only (once per node per talent change).
            local success, details
            if configId then
                success, details = pcall(C_Traits.GetNodeInfo, configId, nodeId)
            end
            if success and details then
                -- Committed state only: activeRank/activeEntry also count picks staged
                -- in the talent UI and never applied. A granted rank (activeRank above
                -- ranksPurchased) cannot be staged, so it counts as taken as well.
                local committed = details.entryIDsWithCommittedRanks
                if committed and #committed > 0 then
                    placerState = committed[1]
                elseif (details.activeRank or 0) > (details.ranksPurchased or 0) then
                    placerState = (details.activeEntry and details.activeEntry.entryID) or true
                end
            end
            nodeState[nodeId] = placerState
        end
        return placerState
    end

    local function IsTaken(nodeId, entryID, configId)
        local placerState = NodeState(nodeId, configId)
        if placerState == false then
            return false
        end
        return entryID == nil or placerState == entryID
    end

    -- True when the node (or, for a choice node, that side of it) is taken now.
    function CludesUI.TalentCondIsTaken(nodeId, entryID)
        return IsTaken(nodeId, entryID, C_ClassTalents.GetActiveConfigID())
    end

    -- True when every condition in the list holds (an empty or missing list
    -- holds). A node that is not in the active tree reads as not taken.
    -- configID: the config a caller already read for a whole pass (false =
    -- none); nil reads the active one.
    function CludesUI.TalentConditionsHold(conds, configId)
        if type(conds) ~= "table" then
            return true
        end
        if configId == nil then
            configId = C_ClassTalents.GetActiveConfigID()
        end
        for idx = 1, #conds do
            local c = conds[idx]
            if type(c) == "table" and c.nodeID then
                if IsTaken(c.nodeID, c.entryID, configId or nil) ~= (c.taken ~= false) then
                    return false
                end
            end
        end
        return true
    end
end
