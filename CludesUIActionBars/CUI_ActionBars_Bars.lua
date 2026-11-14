if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBars_Bars.lua
--
--  The secure bar frames, SetupBar and the first-install capture of
--  Blizzard's layout.
--  Loads after CUI_ActionBars_Paging.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...

local _G = _G
local ipairs, pairs, type, pcall = ipairs, pairs, type, pcall
local min, upper = math.min, math.max
local InCombatLockdown = InCombatLockdown
local RegisterStateDriver = RegisterStateDriver

local ABAR, EAB_VTABLE, barButtons = mod.EAB, mod.EAB_VTABLE, mod.barButtons
local EFD = mod.EFD
local Inner = mod._internals
local BAR_CONFIG = Inner.BAR_CONFIG
local RegisterBarWithOverrideController = Inner.RegisterBarWithOverrideController
local BAR_SLOT_OFFSETS, barBaseSize, barFrames = Inner.BAR_SLOT_OFFSETS, Inner.barBaseSize, Inner.barFrames
local BINDING_MAP, buttonToBar, GetEABFlyout = Inner.BINDING_MAP, Inner.buttonToBar, Inner.GetEABFlyout
local GetOrCreateButton, ReRegisterButtonEvents = Inner.GetOrCreateButton, Inner.ReRegisterButtonEvents
local SecureSetupHandler_RegisterBarFrame = Inner.SecureSetupHandler_RegisterBarFrame
local GetClassPagingConditions = Inner.GetClassPagingConditions

-------------------------------------------------------------------------------
--  Secure Bar Frame Creation
--  Each bar gets a SecureHandlerStateTemplate frame. Our buttons are created
--  with SetID(0) + an explicit "action" attribute, so CalculateAction resolves
--  the slot from that attribute (path 2), NOT from actionpage. Paging works by
--  the bar's _onstate-page handler doing ChildUpdate("eab-page", page), and each
--  button's _childupdate-eab-page snippet rewriting its "action" attribute. The
--  frame "actionpage" attribute is kept only for insecure range-check reads.
-------------------------------------------------------------------------------
local function CreateBarFrame(details)
    local key = details.key
    local widget = CreateFrame("Frame", "EABBar_" .. key, UIParent, "SecureHandlerStateTemplate")
    widget:SetSize(1, 1)
    widget:SetPoint("CENTER")
    -- Render above any Blizzard bar art that might bleed through
    widget:SetFrameLevel(math.max(widget:GetFrameLevel(), 10))
    -- Bar frames never intercept clicks (only buttons do); motion is enabled
    -- later by the hover system for OnEnter/OnLeave.
    if widget.SetMouseClickEnabled then
        widget:SetMouseClickEnabled(false)
    end
    widget._barKey = key
    widget._barInfo = details

    if key == "MainBar" then
        -- MainBar paging: the state driver evaluates conditions (forms,
        -- vehicle, override, possess, bonus bars, modifiers); _onstate-page
        -- runs ChildUpdate("eab-page", page), and each button's
        -- _childupdate-eab-page rewrites action = baseIndex + (page-1)*12.
        local barSettings = ABAR and ABAR.db and ABAR.db.profile and ABAR.db.profile.bars[key]
        local customPaging = barSettings and barSettings.paging
        local pagingConditions
        if EAB_VTABLE.HasCustomPaging(barSettings) then
            pagingConditions = EAB_VTABLE.BuildPagingConditions("MainBar", customPaging, 1)
        else
            -- No custom paging: use hardcoded class defaults (zero impact)
            pagingConditions = GetClassPagingConditions()
        end

        -- Mark MainBar as the override bar target so the override controller
        -- propagates vehicle/override/petbattle state changes.
        widget:SetAttribute("state-overridebar", true)

        -- Propagate page state to actionpage in the restricted environment so
        -- it stays untainted. The same write goes to MainActionBar: the native
        -- ACTIONBUTTONn keys fire Blizzard's ActionButton1-12, which resolve
        -- their slot from that frame's actionpage at click time, and Blizzard's
        -- own writer (ActionBarController_UpdateAll) cannot be relied on once
        -- the stock bars are disposed, so without the mirror a key can fire a
        -- page the icon does not show. The secure ChildUpdate is
        -- the missing half of the paging contract: each button gets an
        -- attribute change so OnAttributeChanged -> UpdateAction re-evaluates
        -- the derived slot even in combat. NEVER CallMethod here: vehicle/
        -- override transitions evaluate all state drivers in one secure pass,
        -- and CallMethod exits to insecure Lua mid-pass, tainting the context
        -- -- Blizzard's ActionBarController drivers in the same pass inherit
        -- it and OverrideActionBar:Show() hits ADDON_ACTION_BLOCKED. Page
        -- sync instead rides ACTIONBAR_PAGE_CHANGED (paging frame OnEvent).
        widget:SetFrameRef("blizzmainbar", MainActionBar)
        widget:SetAttributeNoHandler(
            "_onstate-page",
            [[
            local page = tonumber(newstate) or 1
            self:SetAttribute("actionpage", page)
            self:ChildUpdate("eab-page", page)
            self:GetFrameRef("blizzmainbar"):SetAttribute("actionpage", page)
        ]]
        )

        RegisterStateDriver(widget, "page", pagingConditions)
        widget._eabPagingConds = pagingConditions
    end

    -- Bars 2-8 (nativeActionPage) and 9-10 (customPage): buttons have static action
    -- attrs set in SetupBar pointing at the bar's default page. Custom paging installs
    -- a state driver + ChildUpdate to recalculate the action attr on page change --
    -- identical machinery either way, differing only in the default page source.
    local defaultPage = details.nativeActionPage or details.customPage
    if defaultPage then
        widget:Execute(("self:SetAttribute('actionpage', %d)"):format(defaultPage))

        -- Configurable paging: install a state driver on top of the default
        -- page; when no conditions match, fall back to the bar's default.
        local barSettings = ABAR and ABAR.db and ABAR.db.profile and ABAR.db.profile.bars[key]
        local customPaging = barSettings and barSettings.paging
        widget._eabPagingConds = false
        if EAB_VTABLE.HasCustomPaging(barSettings) then
            widget:SetAttributeNoHandler(
                "_onstate-page",
                [[
                local page = tonumber(newstate) or 1
                self:SetAttribute("actionpage", page)
                self:ChildUpdate("eab-page", page)
            ]]
            )
            widget._eabPagingInstalled = true
            local conditions = EAB_VTABLE.BuildPagingConditions(key, customPaging, defaultPage)
            if conditions then
                RegisterStateDriver(widget, "page", conditions)
                widget._eabPagingConds = conditions
            end
        end
    end

    barFrames[key] = widget

    -- Empower re-check: setting "state-eabempower" dispatches ChildUpdate to
    -- re-evaluate pressAndHoldAction on all children. MUST be an _onstate-
    -- handler on a state- attribute: these bars are SecureHandlerStateTemplate,
    -- whose dispatcher only matches "^state%-(.+)" -> "_onstate-<id>". No
    -- _onattributechanged path exists here (that's SecureHandlerAttributeTemplate,
    -- i.e. OverrideController); a plain-attribute trigger fires NOTHING.
    widget:SetAttributeNoHandler(
        "_onstate-eabempower",
        [[
        self:ChildUpdate("eab-empower", "")
    ]]
    )

    -- Secure visibility: show/hide even in combat by setting the state
    -- attribute directly. RegisterStateDriver installs the snippet at
    -- creation (out of combat); later SetAttribute("state-eabvis", "hide")
    -- triggers it from the secure environment.
    widget:SetAttribute(
        "_onstate-eabvis",
        [[
        if newstate == "hide" then
            self:Hide()
        else
            self:Show()
        end
    ]]
    )
    -- If always-hidden or disabled, start hidden so the secure snippet hides
    -- it immediately, before combat can return after a brief reload regen.
    local s = ABAR.db and ABAR.db.profile.bars[key]
    local startHidden = s and (ABAR.VisibilityCompat.IsNever(s) or s.enabled == false)
    RegisterStateDriver(widget, "eabvis", startHidden and "hide" or "show")

    -- Register with the override controller so vehicle/override/petbattle
    -- state changes propagate to this bar frame.
    RegisterBarWithOverrideController(widget)

    -- Register with secure handler so it can reparent buttons to this frame
    SecureSetupHandler_RegisterBarFrame(key, widget)
    -- Custom modifier paging rewrites button action attrs from a SECURE state
    -- driver, no dispatcher event exists. The driver's "state-page" write
    -- fires this frame's insecure OnAttributeChanged -- the one clean owning
    -- edge to retire the filled lists and slot->button map so the next
    -- cooldown pass rebuilds against the new mapping.
    widget:HookScript("OnAttributeChanged", function(f, name)
        if name == "state-page" then
            mod._cdFilledDirty = true
            mod._slotBtnMapDirty = true
            mod._cdDirtyUntil = GetTime() + 2
            -- Out-of-range coloring re-acquires the bar's new slots and the
            -- proc glows re-scan (CUI_ActionBars_Range.lua / _Glows.lua): the
            -- page is applied by now, which ACTIONBAR_PAGE_CHANGED's own
            -- passes cannot rely on (it fires before the state driver runs)
            if mod._eabRangePageEdge then
                mod._eabRangePageEdge(f._barKey)
            end
            if mod._eabQueueGlowRescan then
                mod._eabQueueGlowRescan()
            end
        end
    end)

    -- Bar dormancy edges. OnShow/OnHide fire on EFFECTIVE visibility, secure
    -- driver flips included, and the dormancy handler is all unprotected API,
    -- so both edges are combat-legal. Buttons don't exist yet at creation
    -- time (handler no-ops until they do); FinishSetup's initial sync covers
    -- bars that START hidden (their OnHide never fires).
    widget:HookScript("OnShow", function(f)
        if mod.ApplyBarDormancy then
            mod.ApplyBarDormancy(f._barKey, false)
        end
    end)
    widget:HookScript("OnHide", function(f)
        if mod.ApplyBarDormancy then
            mod.ApplyBarDormancy(f._barKey, true)
        end
    end)
    return widget
end

-- Rebuild the paging state driver for a bar after settings change. Called from the
-- options panel when the user modifies paging config, and from ApplyAll with
-- onlyIfChanged so a profile swap or spec override apply picks up the new paging
-- settings; onlyIfChanged skips a bar whose conditions match the ones installed
-- (frame._eabPagingConds, false = fixed page) instead of re-registering its driver
-- on every full apply, and returns true for a rebuilt bar instead of running the
-- keybind pass, which ApplyAll runs once for all of them. Must be called out of combat.
function mod.RebuildBarPaging(barId, onlyIfChanged)
    if InCombatLockdown() then
        return
    end
    local widget = barFrames[barId]
    if not widget then
        return
    end
    local details = widget._barInfo
    if not details then
        return
    end
    local barSettings = ABAR and ABAR.db and ABAR.db.profile and ABAR.db.profile.bars[barId]
    local customPaging = barSettings and barSettings.paging

    if barId == "MainBar" then
        local pagingConditions
        if EAB_VTABLE.HasCustomPaging(barSettings) then
            pagingConditions = EAB_VTABLE.BuildPagingConditions("MainBar", customPaging, 1)
        else
            pagingConditions = GetClassPagingConditions()
        end
        if onlyIfChanged and pagingConditions == widget._eabPagingConds then
            return
        end
        widget._eabPagingConds = pagingConditions
        -- Force re-evaluation by unregistering first
        UnregisterStateDriver(widget, "page")
        RegisterStateDriver(widget, "page", pagingConditions)
    elseif details.nativeActionPage or details.customPage then
        local defaultPage = details.nativeActionPage or details.customPage
        local hasCustom = EAB_VTABLE.HasCustomPaging(barSettings)
        local conditions = hasCustom and EAB_VTABLE.BuildPagingConditions(barId, customPaging, defaultPage)
            or false
        if onlyIfChanged and conditions == widget._eabPagingConds then
            return
        end
        widget._eabPagingConds = conditions
        if hasCustom then
            -- Install handler if not already present
            if not widget._eabPagingInstalled then
                widget:SetAttributeNoHandler(
                    "_onstate-page",
                    [[
                    local page = tonumber(newstate) or 1
                    self:SetAttribute("actionpage", page)
                    self:ChildUpdate("eab-page", page)
                ]]
                )
                widget._eabPagingInstalled = true
                -- Must set the secure "action" attr (buttons are ID=0, so
                -- CalculateAction never consults "actionpage"). Same builder
                -- as SetupBar so paging added live behaves identically -- no /reload needed.
                local btns = barButtons[barId]
                if btns then
                    for position, button in ipairs(btns) do
                        if not button:GetAttribute("_childupdate-eab-page") then
                            button:SetAttributeNoHandler(
                                "_childupdate-eab-page",
                                mod._eabBuildPageChildSnippet(position)
                            )
                        end
                    end
                end
            end
            if conditions then
                UnregisterStateDriver(widget, "page")
                RegisterStateDriver(widget, "page", conditions)
            end
        else
            -- No paging configured: remove state driver, restore fixed page
            UnregisterStateDriver(widget, "page")
            widget:Execute(("self:SetAttribute('actionpage', %d)"):format(defaultPage))
        end
    end

    -- Keybind routing derives from paging config (UpdateKeybinds pass 1):
    -- custom paging and auto-paging opt-outs both force click-routed keys.
    -- Rebuild now since toggling a paging setting fires no binding event
    -- (waiting on UPDATE_BINDINGS could wait forever); the signature diff
    -- makes this a no-op when routing didn't change, and UpdateKeybinds
    -- re-arms itself out of combat, so calling it unconditionally is safe.
    if onlyIfChanged then
        return true
    end
    if _G._CUAB_UpdateKeybinds then
        _G._CUAB_UpdateKeybinds()
    end
end

-------------------------------------------------------------------------------
--  Bar Setup creates frames and buttons for each bar
-------------------------------------------------------------------------------
-- Build a bar's buttons into an EXISTING bar frame and record its base size.
-- Split out of SetupBar so a bar whose buttons were skipped at load can have
-- them built later, at the reveal edge: CreateBarFrame always creates a frame,
-- so re-running SetupBar there would leave a second one behind.
-- On ns rather than a file local: the lazy bar build in
-- CUI_ActionBars_VisibilityDrivers.lua calls it too.
mod.BuildBarButtons = function(details, widget, skipProtected)
    -- Shrink the clickable area to match a custom visual shape so a square
    -- hit rect can't steal clicks from diamond/circle/etc neighbours. Insets
    -- are a fraction of button size; "none" resets to full square.
    -- Out-of-combat only (SetHitRectInsets on a protected button is unsafe
    -- in combat), behind the same not-skipProtected guard as SetParent.
    local function ApplyShapeHitRects(button, shape)
        if not button then
            return
        end
        local wid, hgt = button:GetSize()
        if not wid or wid == 0 then
            wid = 45
        end
        if not hgt or hgt == 0 then
            hgt = 45
        end
        local insetX, insetY = 0, 0
        if shape == "diamond" or shape == "circle" then
            insetX = math.floor(wid * 0.146)
            insetY = math.floor(hgt * 0.146)
        elseif shape == "hexagon" then
            insetX = math.floor(wid * 0.12)
            insetY = math.floor(hgt * 0.12)
        elseif shape == "shield" then
            insetX = math.floor(wid * 0.10)
            insetY = math.floor(hgt * 0.15)
        end
        button:SetHitRectInsets(insetX, insetX, insetY, insetY)
    end

    local key = details.key
    local buttons = {}
    -- The layout shape: stock styles draw no custom shape, so their hit rects stay full.
    local buttonShape = ABAR
            and ABAR.db
            and ABAR.db.profile
            and ABAR.db.profile.bars[key]
            and mod.AB_LayoutShape(ABAR.db.profile.bars[key])
        or "none"

    if details.isStance then
        -- Stance bar: reuse StanceButton1-N
        for i = 1, details.count do
            local button = _G["StanceButton" .. i]
            if button then
                if not skipProtected then
                    ApplyShapeHitRects(button, buttonShape)
                    button:SetAttributeNoHandler("statehidden", nil)
                    ReRegisterButtonEvents(button, "stance")
                    button:SetParent(widget)
                end
                buttons[i] = button
            end
        end
    elseif details.isPetBar then
        -- Pet bar: reuse PetActionButton1-N
        for i = 1, details.count do
            local button = _G["PetActionButton" .. i]
            if button then
                if not skipProtected then
                    ApplyShapeHitRects(button, buttonShape)
                    button:SetAttributeNoHandler("statehidden", nil)
                    ReRegisterButtonEvents(button, "pet")
                    button:SetParent(widget)
                end
                buttons[i] = button
                -- Hook drag handlers so spellbook drops work even though
                -- the original PetActionBar is hidden and unregistered.
                button:HookScript("OnReceiveDrag", function(self)
                    if InCombatLockdown() then
                        return
                    end
                    -- Blizzard's mixin handler runs first; fall back to
                    -- PickupPetAction if it didn't fire. The resulting
                    -- PET_BAR_UPDATE triggers our full refresh automatically.
                    local cType = GetCursorInfo()
                    if cType == "petaction" then
                        PickupPetAction(self:GetID())
                    end
                end)
            end
        end
    else
        -- Action bars (never stance/pet in this branch): our own EABButtons.
        local slotOffset = BAR_SLOT_OFFSETS[key] or 0
        -- A paged bar's state driver resolves as its frame is made, before
        -- these buttons exist, so the page it stands on then (a form, a
        -- stance or a held modifier at a login or /reload, or at a later
        -- build) reached no button: each starts on that page, at the slot
        -- its _childupdate-eab-page sets.
        local curPage = widget._eabPagingConds and tonumber(widget:GetAttribute("state-page"))
        for i = 1, details.count do
            local slotIndex = slotOffset + i
            local button = GetOrCreateButton(slotIndex, widget, details, i, skipProtected)
            if button then
                -- The bar's key before the first paint below, so the count
                -- alpha reads this bar's Charge Numbers (LayoutBar stamps the
                -- same key later).
                EFD(button).barKey = key
                local bindPrefix = BINDING_MAP[key]
                if not skipProtected then
                    ApplyShapeHitRects(button, buttonShape)
                    local action = curPage and (i + (curPage - 1) * 12) or slotIndex
                    -- Explicit action attr: CalculateAction sees it non-zero
                    -- and returns it directly (path 2).
                    button:SetAttribute("action", action)
                    if bindPrefix then
                        button:SetAttributeNoHandler("binding", bindPrefix .. i)
                    end
                    -- Force visual refresh; events are centrally dispatched
                    -- (per-button registration on 96 buttons caused mass
                    -- OnEvent->UpdateAction calls per tick -- screen blink).
                    -- Taint-safe refresh; avoids passing secret cooldown values through a tainted call.
                    EAB_VTABLE.ForceButtonRefresh(button, action)
                    -- Reconcile attack visuals and the equipped border on rebuild.
                    mod.AB_SyncAttackState(button, action)
                    mod.AB_SyncEquippedBorder(button, action)
                end
                if bindPrefix then
                    button.commandName = bindPrefix .. i
                end
                -- Always register both so empower spells (hold-and-release)
                -- receive the key-down event even when CVar is key-up mode.
                -- useOnKeyDown controls which event fires normal spells.
                button:RegisterForClicks("AnyDown", "AnyUp")
                button:SetAttribute("useOnKeyDown", GetCVarBool("ActionButtonUseKeyDown"))
                if button.EnableMouseWheel then
                    button:EnableMouseWheel(true)
                end
                if not skipProtected then
                    button:SetAttribute("showgrid", 1)
                end
                GetEABFlyout():RegisterButton(button)
                -- Page child-update: rewrites the secure "action" attr on a page
                -- change, then re-checks hold-release. Shared builder so SetupBar
                -- and RebuildBarPaging install byte-identical handlers.
                if
                    (key == "MainBar" or widget._eabPagingInstalled)
                    and not button:GetAttribute("_childupdate-eab-page")
                then
                    button:SetAttributeNoHandler("_childupdate-eab-page", mod._eabBuildPageChildSnippet(i))
                end
                -- Empower re-check on slot change (spec swap, drag, etc.)
                -- The bar header's _onstate-eabempower dispatches ChildUpdate
                -- when addon code sets "state-eabempower".
                if not button:GetAttribute("_childupdate-eab-empower") then
                    button:SetAttributeNoHandler("_childupdate-eab-empower", mod._eabEmpowerSnippet)
                end
                buttons[i] = button
                buttonToBar[button] = { barKey = key, index = i }
            end
        end
    end

    barButtons[key] = buttons
    mod._eabBarNoButtons[key] = nil

    -- Store original button size before any shape/scale modifications.
    -- StanceButtons and PetActionButtons are 30x30; action buttons are 45x45.
    -- Round to nearest integer to eliminate floating-point noise from Blizzard's
    -- scaling the intended sizes are always whole numbers.
    local btn1 = buttons[1]
    barBaseSize[key] = {
        w = math.floor((btn1 and btn1:GetWidth() or 45) + 0.5),
        h = math.floor((btn1 and btn1:GetHeight() or 45) + 0.5),
    }

    return buttons
end

-- Keeps every bar frame on screen, the way Blizzard's own bars are: bar
-- positions are offsets from the screen centre, so a higher UI Scale, an
-- import made at another scale or a narrower screen would otherwise push a bar
-- near an edge past it. Display only: the saved position is never rewritten,
-- so the bar goes back to it once the screen has room. Protected on our secure
-- bar frames in combat, so the combat /reload build runs this at combat end.
-- On ns, not a file local.
mod._eabClampAllBars = function()
    for _, f in pairs(barFrames) do
        f:SetClampedToScreen(true)
    end
end

local function SetupBar(details, skipProtected)
    local key = details.key
    local widget = CreateBarFrame(details)
    if skipProtected or InCombatLockdown() then
        -- One key: every bar of the combat build shares the single pass.
        mod.CombatQueue.Defer("EABClampBars", mod._eabClampAllBars)
    else
        widget:SetClampedToScreen(true)
    end
    -- A bar that can never become visible AND has no key bound gets no buttons
    -- at load: the button loop is 95 % of such a bar's setup cost, and most of
    -- that is Blizzard's CreateFrame on the action button template, which only
    -- a lower button count can reach. A hidden bar with keys keeps its buttons:
    -- its bindings stay live by contract and click-routed keys need a button to
    -- route to. The frame IS still built, so barFrames[key] stays non-nil for
    -- its 52 indexing sites and barButtons[key] is empty, not nil.
    -- ns._eabBuildSkippedBars builds them when the bar leaves the Never set or
    -- a key lands on it.
    if mod.IsNeverBar(details) and not mod.BarHasBoundKeys(details) then
        barButtons[key] = {}
        mod._eabBarNoButtons[key] = true
        -- Placeholder only, same fallback the button-derived value would take
        -- with no buttons. BuildBarButtons recomputes it from the real button.
        barBaseSize[key] = { w = 45, h = 45 }
        return widget, barButtons[key]
    end
    return widget, mod.BuildBarButtons(details, widget, skipProtected)
end

-------------------------------------------------------------------------------
--  First-Install Capture: no saved vars, so read Blizzard Edit Mode settings
--  for initial bar positions, icon counts, orientation and visibility.
-------------------------------------------------------------------------------
local function CaptureBlizzardDefaults()
    local captured = {}
    local uiW, uiH = UIParent:GetSize()
    local uiScale = UIParent:GetEffectiveScale()

    -- Edit Mode stacks only the bottom bars that are SHOWN and parks a hidden
    -- one in its default position at UIParent's top-left corner until it
    -- shows. This returns the CENTER offsets of the slot the stack gives such
    -- a bar once it shows: right above the last shown bar before it in
    -- Blizzard's stack order, at the stack's left edge plus the bar's own
    -- indent (WoW Forever's default anchors carry one). nil when the bar is
    -- not parked there (moved in Edit Mode, or a layout with no stack).
    local function StackSlot(barFrame)
        local pt, rel, rpt, px, py = barFrame:GetPoint(1)
        if pt ~= "TOPLEFT" or rel ~= UIParent or rpt ~= "TOPLEFT" or px ~= 0 or py ~= 0 then
            return nil
        end
        local EU, EM = _G.EditModeUtil, _G.EditModeManagerFrame
        local success, entries
        if EU and EU.GetBottomActionBars then
            success, entries = pcall(EU.GetBottomActionBars, EU)
        elseif EM and EM.GetBottomActionBars then
            success, entries = pcall(EM.GetBottomActionBars, EM)
        end
        if not success or type(entries) ~= "table" then
            return nil
        end
        local function Anchor(f)
            if not (EM and EM.GetDefaultAnchor) then
                return nil
            end
            local okA, a = pcall(EM.GetDefaultAnchor, EM, f)
            return okA and type(a) == "table" and a or nil
        end
        local below, listed
        for i = 1, #entries do
            local f = entries[i]
            if f == barFrame then
                listed = true
                break
            end
            if
                f
                and f:IsShown()
                and not f.skipAutomaticPositioning
                and (not f.IsInDefaultPosition or f:IsInDefaultPosition())
            then
                local a = Anchor(f)
                if not (a and a.bottomBarExcludeFromStackIncrement) then
                    below = f
                end
            end
        end
        if not listed then
            return nil
        end
        below = below or _G.MainActionBar
        local l, t = below and below:GetLeft(), below and below:GetTop()
        local wid, hgt = barFrame:GetWidth(), barFrame:GetHeight()
        if not (l and t and wid and hgt) then
            return nil
        end
        local kB = below:GetEffectiveScale() / uiScale
        local k = barFrame:GetEffectiveScale() / uiScale
        local aB, a = Anchor(below), Anchor(barFrame)
        local leftX = (l - (aB and aB.bottomBarOffsetX or 0)) * kB + (a and a.bottomBarOffsetX or 0) * k
        local bottom = t * kB + (tonumber(_G.BOTTOM_ACTION_BARS_SPACER_Y) or 4) * k
        return leftX + wid * k / 2 - uiW / 2, bottom + hgt * k / 2 - uiH / 2
    end

    -- MainActionBar is the Edit Mode frame for Action Bar 1 (there is no MainMenuBar).
    -- Chain: ActionButton1 > MainActionBarButtonContainer1 > MainActionBar > UIParent
    local mainActionBar = _G["MainActionBar"]

    for _, details in ipairs(BAR_CONFIG) do
        local barFrame = _G[details.blizzFrame]
        if details.key == "MainBar" then
            -- MainBar reads Edit Mode settings + position from MainActionBar.
            -- Early disposal reparents it to the full-screen hiddenParent, so
            -- GetCenter still returns valid coordinates.
            local payload = {}
            local mabPos = mainActionBar
            if mabPos then
                local cx, cy = mabPos:GetCenter()
                if cx and cy then
                    local bScale = mabPos:GetEffectiveScale()
                    cx = cx * bScale / uiScale
                    cy = cy * bScale / uiScale
                    payload.point = "CENTER"
                    payload.relPoint = "CENTER"
                    payload.x = cx - (uiW / 2)
                    payload.y = cy - (uiH / 2)
                end
            end

            local mab = mainActionBar
            if mab then
                if mab.numButtonsShowable and mab.numButtonsShowable > 0 then
                    payload.numIcons = mab.numButtonsShowable
                end
                if mab.numRows and mab.numRows > 0 then
                    payload.numRows = mab.numRows
                end
                if mab.GetSettingValue then
                    local success, val = pcall(mab.GetSettingValue, mab, 0)
                    if success and val ~= nil then
                        payload.orientation = (val == 0) and "horizontal" or "vertical"
                    end
                    success, val = pcall(mab.GetSettingValue, mab, 3)
                    if success and val ~= nil and val > 0 then
                        payload.blizzIconScale = val / 100
                    end
                end
            end

            captured["MainBar"] = payload
        elseif barFrame and barFrame:GetPoint(1) then
            local payload = {}

            -- Position: convert to UIParent-relative CENTER coords.
            local cx, cy = barFrame:GetCenter()
            if cx and cy then
                local bScale = barFrame:GetEffectiveScale()
                cx = cx * bScale / uiScale
                cy = cy * bScale / uiScale
                payload.point = "CENTER"
                payload.relPoint = "CENTER"
                payload.x = cx - (uiW / 2)
                payload.y = cy - (uiH / 2)
            end

            -- A stance or pet bar hidden right now (no forms yet, no pet out)
            -- was never stacked: it takes the slot it gets once it shows.
            if (details.isStance or details.isPetBar) and not barFrame:IsShown() then
                local sx, sy = StackSlot(barFrame)
                if sx then
                    payload.point, payload.relPoint = "CENTER", "CENTER"
                    payload.x, payload.y, payload.stackSlot = sx, sy, true
                end
            end

            -- Number of visible buttons try Edit Mode setting 2 first
            if barFrame.GetSettingValue then
                local success, val = pcall(barFrame.GetSettingValue, barFrame, 2)
                if success and val and val >= 6 and val <= 12 then
                    payload.numIcons = val
                end
            end
            if not payload.numIcons and barFrame.numButtonsShowable and barFrame.numButtonsShowable > 0 then
                payload.numIcons = barFrame.numButtonsShowable
            end

            -- Number of rows try Edit Mode setting 1 first
            if barFrame.GetSettingValue then
                local success, val = pcall(barFrame.GetSettingValue, barFrame, 1)
                if success and val and val >= 1 and val <= 4 then
                    payload.numRows = val
                end
            end
            if not payload.numRows and barFrame.numRows and barFrame.numRows > 0 then
                payload.numRows = barFrame.numRows
            end

            -- Orientation
            if barFrame.isHorizontal ~= nil then
                payload.orientation = barFrame.isHorizontal and "horizontal" or "vertical"
            end
            if barFrame.GetSettingValue then
                local success, val = pcall(barFrame.GetSettingValue, barFrame, 0)
                if success and val ~= nil then
                    payload.orientation = (val == 0) and "horizontal" or "vertical"
                end
            end

            -- Icon size (Edit Mode setting 3).
            if barFrame.GetSettingValue then
                local success, val = pcall(barFrame.GetSettingValue, barFrame, 3)
                if success and val ~= nil and val > 0 then
                    payload.blizzIconScale = val / 100
                end
            end

            -- Always Show Buttons (setting 9): 0=off, 1=on
            if
                barFrame.GetSettingValue
                and details.key ~= "MainBar"
                and not details.isStance
                and not details.isPetBar
            then
                local success, val = pcall(barFrame.GetSettingValue, barFrame, 9)
                if success and val ~= nil then
                    payload.alwaysShowButtons = (val == 1)
                end
            end

            -- An empty bar with alwaysShowButtons off would vanish entirely once we take over, so force it on.
            if payload.alwaysShowButtons == false and details.blizzBtnPrefix then
                local numToCheck = payload.numIcons or details.count or 12
                local hasAny = false
                for i = 1, numToCheck do
                    local button = _G[details.blizzBtnPrefix .. i]
                    if button and button.action and HasAction(button.action) then
                        hasAny = true
                        break
                    end
                end
                if not hasAny then
                    payload.alwaysShowButtons = true
                end
            end

            -- Visibility (setting 5, bars 2-8 only): 0=Always, 1=InCombat,
            -- 2=OutOfCombat, 3=Hidden. A bar disabled via Gameplay > Action
            -- Bars (CVars) reports IsShown()=false while setting 5 still
            -- claims "Always Visible"; IsShown=false takes priority.
            if not barFrame:IsShown() then
                payload.visibility = 3
            elseif barFrame.GetSettingValue and not details.isStance and not details.isPetBar then
                local success, val = pcall(barFrame.GetSettingValue, barFrame, 5)
                if success and val ~= nil then
                    payload.visibility = val
                end
            end

            captured[details.key] = payload
        end
    end
    return captured
end

-- First-install end cap span: the elements in one row directly beside
-- Blizzard's Action Bar 1 at capture time (horizontal bars 2-8 shown at all
-- times, the micro menu, the bag bar; stance and pet bars depend on the class,
-- so never), walked outward from bar 1 on each side. The last one each way
-- carries bar 1's cap for that side (ns.AB_CapsSides). Same row = vertical
-- overlap of at least half the shorter one; directly beside = facing edges
-- -8..12 apart (Blizzard's WoW Forever row leaves 4.5 and 7), the nearest
-- first. Returns the left and right bar keys, nil for none.
function mod.AB_CaptureCapSpan(captured)
    local main = _G.MainActionBar
    local mc = captured and captured.MainBar
    if not main or not mc or mc.orientation == "vertical" then
        return nil, nil
    end
    local uiS = UIParent:GetEffectiveScale()
    local function Rect(f)
        if not (f and f.GetLeft) then
            return nil
        end
        local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
        if not (l and r and t and b) or r - l < 1 or t - b < 1 then
            return nil
        end
        local k = f:GetEffectiveScale() / uiS
        return { l * k, r * k, t * k, b * k }
    end
    local home = Rect(main)
    if not home or home[2] - home[1] < 20 then
        return nil, nil
    end
    local cands = {}
    for _, details in ipairs(BAR_CONFIG) do
        local d = captured[details.key]
        if
            details.key ~= "MainBar"
            and d
            and details.blizzFrame
            and not details.isStance
            and not details.isPetBar
            and d.orientation == "horizontal"
            and (d.visibility == nil or d.visibility == 0)
        then
            local r = Rect(_G[details.blizzFrame])
            if r then
                cands[#cands + 1] = { key = details.key, r = r }
            end
        end
    end
    local mcf, mm = _G.MicroMenuContainer, _G.MicroMenu
    if
        mcf
        and mcf:IsShown()
        and mm
        and mm:GetParent() == mcf
        and mm:IsShown()
        and mm.isHorizontal ~= false
    then
        local r = Rect(mcf)
        if r then
            cands[#cands + 1] = { key = "MicroBar", r = r }
        end
    end
    local bags = _G.BagsBar
    if bags and bags:IsShown() and bags.isHorizontal ~= false then
        local r = Rect(bags)
        if r then
            cands[#cands + 1] = { key = "BagBar", r = r }
        end
    end
    local function Walk(dir)
        local current, last, used = home, nil, {}
        while true do
            local best, bestGap
            for i = 1, #cands do
                local c = cands[i]
                if not used[c] then
                    local r = c.r
                    local shade = min(current[3], r[3]) - upper(current[4], r[4])
                    if shade >= 0.5 * min(current[3] - current[4], r[3] - r[4]) then
                        local gap = (dir > 0) and (r[1] - current[2]) or (current[1] - r[2])
                        if gap >= -8 and gap <= 12 and (not bestGap or gap < bestGap) then
                            best, bestGap = c, gap
                        end
                    end
                end
            end
            if not best then
                return last
            end
            used[best] = true
            last, current = best.key, best.r
        end
    end
    return Walk(-1), Walk(1)
end

-- Entry points the files after this one re-import by name.
Inner.CaptureBlizzardDefaults, Inner.SetupBar = CaptureBlizzardDefaults, SetupBar
