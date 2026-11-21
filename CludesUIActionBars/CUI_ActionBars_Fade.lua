if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBars_Fade.lua
--
--  Mouseover fade: hover states, fade in and out, and the hover hooks on
--  bars and data bars.
--  Loads after CUI_ActionBars_Layout.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...

local _G = _G
local ipairs, pairs = ipairs, pairs
local C_Timer_After = C_Timer.After

local ABAR, EAB_VTABLE, barButtons = mod.EAB, mod.EAB_VTABLE, mod.barButtons
local Inner = mod._internals
local _gridState, _quickKeybindState, ALL_BARS, FadeTo =
    Inner._gridState, Inner._quickKeybindState, Inner.ALL_BARS, Inner.FadeTo
local StopFade = Inner.StopFade
local barFrames, blizzMovableHolders, dataBarFrames =
    Inner.barFrames, Inner.blizzMovableHolders, Inner.dataBarFrames
local extraBarHolders, GetEABFlyout = Inner.extraBarHolders, Inner.GetEABFlyout
local SyncPagingAlpha = Inner.SyncPagingAlpha
local BAR_LOOKUP, _dragState, _fadeAlpha = Inner.BAR_LOOKUP, Inner._dragState, Inner._fadeAlpha
local abs = math.abs

-------------------------------------------------------------------------------
--  Mouseover Fade System
-------------------------------------------------------------------------------
local hoverStates = {} -- shared by action bars, data bars, and extra bars

-- Every mouseover-enabled bar follows the same state machine: entering marks
-- it hovered and fades in, leaving schedules a guarded fade-out on the next
-- frame. Per-bar attach functions only provide edge-case policies that differ
-- between action bars, data bars, and Blizzard-owned extra bars.
function EAB_VTABLE.Hover.GetSettings(barId)
    return ABAR.db and ABAR.db.profile and ABAR.db.profile.bars and ABAR.db.profile.bars[barId]
end

function EAB_VTABLE.Hover.GetState(barId, widget)
    local status = hoverStates[barId]
    if not status then
        status = { frame = widget, isHovered = false, fadeDir = nil }
        hoverStates[barId] = status
    else
        status.frame = widget or status.frame
    end
    return status
end

-- The frame a bar's alpha lives on: ours, or for an extra bar (the micro menu,
-- the bag bar) the Blizzard frame itself, which is what AttachExtraBarHoverHooks
-- fades. Shared by the mouseover refresh and the Advanced Fade layer.
local function BarAlphaFrame(key, details)
    local widget = barFrames[key]
        or (details.isDataBar and dataBarFrames[key])
        or (details.isBlizzardMovable and blizzMovableHolders[key])
        or extraBarHolders[key]
        or (details.visibilityOnly and details.frameName and _G[details.frameName])
    if widget and details.visibilityOnly and not details.isDataBar and not details.isBlizzardMovable then
        local blizzFrame = details.frameName and _G[details.frameName]
        if blizzFrame then widget = blizzFrame end
    end
    return widget
end

-------------------------------------------------------------------------------
--  Advanced Fade: an optional per-bar alpha layer, on while at least one of the
--  bar's conditions (advancedFadeConditions) is checked; none checked, the
--  default, is off. A bar with none never reaches it: Visibility, Bar Opacity
--  and the mouseover fade stay that bar's only alpha writers. On a bar with
--  one, the layer runs after those writers and only moves the alpha between
--  the resting value and Advanced Fade Opacity (fadeMaxAlpha); Visibility
--  still decides whether the bar shows at all.
-------------------------------------------------------------------------------
-- WoW Forever has no skyriding: its options leave the condition out, so a
-- profile from retail that carries it is not on for it there.
local FLYING_COUNTS = not CludesUI.IS_FOREVER
function EAB_VTABLE.Hover.AdvancedFadeEnabled(cfg)
    local c = cfg and cfg.advancedFadeConditions
    return type(c) == "table"
            and (c.combat or c.party or c.raid or c.instance or c.mounted or (FLYING_COUNTS and c.flying) or c.target or c.enemy_target or c.mouseover)
            and true
        or false
end
-- The hooks' gate asks the same question.
EAB_VTABLE.Hover.HasCustomFade = EAB_VTABLE.Hover.AdvancedFadeEnabled
-- For the options page (Bar Opacity repaints the layer of a bar that has it on).
ABAR.AdvancedFadeOn = EAB_VTABLE.Hover.AdvancedFadeEnabled

function EAB_VTABLE.Hover.AdvancedFadeHovered(status)
    return status and (status.isHovered == true or status.fadeDir == "in") or false
end

-- Any picked condition that holds reveals the bar. The group, instance, mount
-- and skyriding probes are the visibility lanes' own, so a condition reads
-- exactly as the same lane does on the Visibility row.
function EAB_VTABLE.Hover.CustomFadeConditionMet(barId, cfg)
    if not EAB_VTABLE.Hover.AdvancedFadeEnabled(cfg) then return false end
    local c = cfg.advancedFadeConditions
    if type(c) ~= "table" then return false end

    if c.mouseover and EAB_VTABLE.Hover.AdvancedFadeHovered(hoverStates[barId]) then return true end
    if c.combat and CludesUI.IsInCombat() then return true end
    local inRaid = IsInRaid()
    if c.raid and inRaid then return true end
    if c.party and IsInGroup() and not inRaid then return true end
    if c.instance and CludesUI.IsInInstancedContent() then return true end
    if c.mounted and CludesUI.IsPlayerMountedLike() then return true end
    if c.flying and CludesUI.IsAirborneSkyriding() then return true end
    local targetExists = UnitExists("target")
    if c.target and targetExists then return true end
    if c.enemy_target and targetExists and UnitCanAttack("player", "target") then return true end
    return false
end

function EAB_VTABLE.Hover.CustomFadeFrame(barId)
    local details = BAR_LOOKUP[barId]
    if not details or details.noManagedVisibility then return nil, details end
    return BarAlphaFrame(barId, details), details
end

function EAB_VTABLE.Hover.RefreshCustomFadeBar(barId, animate, force)
    local cfg = EAB_VTABLE.Hover.GetSettings(barId)
    if not EAB_VTABLE.Hover.AdvancedFadeEnabled(cfg) then return false end

    -- Temporary surfacing modes remain authoritative over alpha rules.
    local spellbookForced = (_gridState._sbNeverForced and _gridState._sbNeverForced[barId])
        or (_gridState._sbMoForced and _gridState._sbMoForced[barId])
    local myslotForced = ABAR.db and ABAR.db.profile and ABAR.db.profile._myslotVisBackup
    if
        _gridState.shown
        or _dragState.visible
        or _quickKeybindState.open
        or spellbookForced
        or myslotForced
    then
        local st = hoverStates[barId]
        if st then st.customFadeTarget = nil end
        return false
    end

    local widget = EAB_VTABLE.Hover.CustomFadeFrame(barId)
    if not widget then return false end
    local status = hoverStates[barId]

    -- Visibility comes first. While it gates the bar on Mouseover, the hidden
    -- side stays the mouseover fade's: the layer only moves the alpha of a bar
    -- the hover has revealed.
    local visibilityWantsHover =
        CludesUI.VisWantsMouseover(cfg, "barVisibility", nil, CludesUI.VIS_CAPS_DEFAULT)
    local hoverHidden = false
    if visibilityWantsHover then
        local over = EAB_VTABLE.Hover.AdvancedFadeHovered(status)
        if not over and ABAR.db.profile.mouseoverShowAll then over = mod.AnyMouseoverBarHovered() end
        hoverHidden = not over
    end

    -- Visibility's Mouseover mode parks the real Bar Opacity in _savedBarAlpha
    -- (mouseoverAlpha reads 0 then), so that is the resting alpha to start from.
    local base
    if cfg.mouseoverEnabled and cfg._savedBarAlpha ~= nil then
        base = cfg._savedBarAlpha
    else
        base = cfg.mouseoverAlpha or 1
    end

    local target = base
    if EAB_VTABLE.Hover.CustomFadeConditionMet(barId, cfg) then
        target = cfg.fadeMaxAlpha
        if target == nil then target = 1 end
    end
    if hoverHidden then target = 0 end
    if target < 0 then
        target = 0
    elseif target > 1 then
        target = 1
    end

    if status and not force and status.customFadeTarget == target then return true end
    if status then status.customFadeTarget = target end

    local current = _fadeAlpha[widget] or 1
    if current == target then return true end
    StopFade(widget, current)
    if animate and abs(current - target) >= 0.01 then
        local duration = hoverHidden and (cfg.mouseoverSpeed or 0.15)
            or ((target > current) and (cfg.fadeInSpeed or 0.15) or (cfg.fadeOutSpeed or 0.15))
        if duration < 0.01 then duration = 0.01 end
        FadeTo(widget, target, duration)
    else
        StopFade(widget, target)
    end
    if barId == "MainBar" then SyncPagingAlpha(target) end
    return true
end

function ABAR:RefreshCustomFadeGate()
    local any = false
    if self.db and self.db.profile and self.db.profile.bars then
        for _, details in ipairs(ALL_BARS) do
            if EAB_VTABLE.Hover.HasCustomFade(self.db.profile.bars[details.key]) then
                any = true
                break
            end
        end
    end
    self._anyCustomFade = any
    if any then
        self:EnsureAdvancedFadeHooks()
        if not self._advancedFadeUpdaterRegistered then
            CludesUI.RegisterVisibilityUpdater(self._advancedFadeUpdater)
            self._advancedFadeUpdaterRegistered = true
        end
    elseif self._advancedFadeUpdaterRegistered then
        CludesUI.UnregisterVisibilityUpdater(self._advancedFadeUpdater)
        self._advancedFadeUpdaterRegistered = nil
    end
    return any
end

function ABAR:RefreshCustomFadeForBar(barId, animate)
    self:RefreshCustomFadeGate()
    return EAB_VTABLE.Hover.RefreshCustomFadeBar(barId, animate, true)
end

function ABAR:RefreshAllCustomFade(animate, force)
    local any = self:RefreshCustomFadeGate()
    if not any and not force then return end
    for _, details in ipairs(ALL_BARS) do
        local barCfg = self.db.profile.bars[details.key]
        -- Only bars with a condition checked; force repaints even a bar whose
        -- last target still stands, never a native bar.
        if EAB_VTABLE.Hover.AdvancedFadeEnabled(barCfg) then
            EAB_VTABLE.Hover.RefreshCustomFadeBar(details.key, animate, force and true or false)
        end
    end
end

-- The one-time handoff when a bar is left with no condition checked: stops an
-- Advanced Fade still in flight and paints the alpha the mouseover fade would
-- show this instant. No saved Visibility or Opacity setting is touched.
function EAB_VTABLE.Hover.ReleaseAdvancedFadeBar(barId)
    local cfg = EAB_VTABLE.Hover.GetSettings(barId)
    if not cfg then return end
    local widget = EAB_VTABLE.Hover.CustomFadeFrame(barId)
    if not widget then return end

    local status = hoverStates[barId]
    local over = EAB_VTABLE.Hover.AdvancedFadeHovered(status)
    if not over and ABAR.db.profile.mouseoverShowAll then over = mod.AnyMouseoverBarHovered() end
    local target, wantsHover = EAB_VTABLE.Hover.RestingAlpha(barId, cfg)
    if wantsHover and over then target = cfg._savedBarAlpha or 1 end

    StopFade(widget, target)
    if status then
        status.customFadeTarget = nil
        if cfg.mouseoverEnabled and over then
            status.fadeDir = "in"
        elseif cfg.mouseoverEnabled and target == 0 then
            status.fadeDir = "out"
        else
            status.fadeDir = nil
        end
    end
    if barId == "MainBar" then SyncPagingAlpha(target) end
end

-- A change to a bar's conditions (or a copy of them) rebuilds no Visibility
-- driver and writes no other setting: a first condition arms the layer's
-- hooks, a bar left with none runs the one-time alpha handoff above.
function ABAR:RefreshAdvancedFadeEnabled(changed)
    if type(changed) == "string" then
        local barCfg = self.db.profile.bars[changed]
        if barCfg and not EAB_VTABLE.Hover.AdvancedFadeEnabled(barCfg) then
            EAB_VTABLE.Hover.ReleaseAdvancedFadeBar(changed)
        end
    elseif type(changed) == "table" then
        for _, barId in ipairs(changed) do
            local barCfg = self.db.profile.bars[barId]
            if barCfg and not EAB_VTABLE.Hover.AdvancedFadeEnabled(barCfg) then
                EAB_VTABLE.Hover.ReleaseAdvancedFadeBar(barId)
            end
        end
    end

    self:RefreshCustomFadeGate()

    -- While a bar still has a condition, the mouseover refresh runs and its
    -- post-hook layers the Advanced Fade onto those bars; with none left
    -- anywhere the handoff above was all there was to do.
    if self._anyCustomFade then self:RefreshMouseover() end
end

-- The alpha a bar RESTS at while the cursor is not on it, plus whether that resting state
-- is a hover gate. Single source of truth for every alpha writer here, so a fade-out
-- cannot land on a different verdict than the visibility refresh would. mouseoverEnabled
-- is STATIC (true whenever mouseover is selected at all, any Match Mode), so it can only
-- answer "is the hover mechanism wired"; VisWantsMouseover answers "is it gating now".
-- _savedBarAlpha is load-bearing: ApplyMode parks mouseoverAlpha at 0 and stashes the real
-- value there while a mouseover selection is stored, so the shown branch would paint 0.
-- On the vtable, not a chunk local.
function EAB_VTABLE.Hover.RestingAlpha(barId, cfg)
    cfg = cfg or EAB_VTABLE.Hover.GetSettings(barId)
    if not cfg then return 1, false end
    local wantsHover
    if cfg.mouseoverEnabled and CludesUI.VisWantsMouseover then
        wantsHover = CludesUI.VisWantsMouseover(cfg, "barVisibility", nil, CludesUI.VIS_CAPS_DEFAULT)
    else
        wantsHover = cfg.mouseoverEnabled
    end
    if wantsHover then return 0, true end
    return cfg._savedBarAlpha or cfg.mouseoverAlpha or 1, false
end

-- Fade ONE bar in, no broadcast. The fadeDir memo makes repeat calls while
-- already fading/faded O(1) table reads, so a sweep across a bar's 12 buttons
-- costs 12 memo hits and one real fade. On the vtable,
-- not a chunk local.
function EAB_VTABLE.Hover.FadeInOne(barId, status)
    local cfg = EAB_VTABLE.Hover.GetSettings(barId)
    if cfg and cfg.mouseoverEnabled and status and status.fadeDir ~= "in" then
        local targetAlpha = cfg._savedBarAlpha or 1
        status.fadeDir = "in"
        StopFade(status.frame)
        -- The shared per-frame fader starts a show-all edge on every bar in
        -- the same frame (lockstep, no ripple).
        FadeTo(status.frame, targetAlpha, cfg.mouseoverSpeed or 0.15)
        if barId == "MainBar" then SyncPagingAlpha(targetAlpha) end
    end
end

function EAB_VTABLE.Hover.FadeIn(barId, status)
    EAB_VTABLE.Hover.FadeInOne(barId, status)
    -- "Show All Bars on Mouseover": bring other bars along, all starting THIS
    -- frame in lockstep. Cheap because every fade rides the shared fader (a
    -- table write per bar). Iterative, not recursive: no reentrancy latch to get stuck.
    -- Gated on THIS bar being Mouseover itself -- AttachHoverHooks wires the
    -- same OnEnter onto every bar regardless of its own visibility mode, so
    -- without this check hovering an Always-visible bar broadcast the same
    -- as hovering a real Mouseover one (tooltip promises the latter only).
    local cfg = EAB_VTABLE.Hover.GetSettings(barId)
    if cfg and cfg.mouseoverEnabled and ABAR.db.profile.mouseoverShowAll then
        local FadeInOne = EAB_VTABLE.Hover.FadeInOne
        for otherKey, otherState in pairs(hoverStates) do
            if otherKey ~= barId then FadeInOne(otherKey, otherState) end
        end
    end
end

function EAB_VTABLE.Hover.FadeOut(barId, status)
    if _gridState.shown then return end -- keep bars visible during spell drag
    local cfg = EAB_VTABLE.Hover.GetSettings(barId)
    if cfg and cfg.mouseoverEnabled and status and status.fadeDir ~= "out" then
        -- Fade back to the bar's RESTING alpha, not a hardcoded 0: under Any a passing
        -- disjunct keeps the bar visible with no hover involved, and fading it away here
        -- would leave it wrong until the next visibility refresh.
        local resting = EAB_VTABLE.Hover.RestingAlpha(barId, cfg)
        status.fadeDir = "out"
        StopFade(status.frame)
        FadeTo(status.frame, resting, cfg.mouseoverSpeed or 0.15)
        if barId == "MainBar" then SyncPagingAlpha(resting) end
    end
end

-- Check if any mouseover-enabled bar is currently hovered.
function mod.AnyMouseoverBarHovered()
    for otherKey, otherState in pairs(hoverStates) do
        if otherState.isHovered then
            local os = EAB_VTABLE.Hover.GetSettings(otherKey)
            if os and os.mouseoverEnabled then return true end
        end
    end
    return false
end

function EAB_VTABLE.Hover.ScheduleFadeOut(barId, status, options)
    options = options or {}

    -- The bar frame and every button hook OnLeave, so one mouse sweep across a
    -- 12-button bar lands here 12+ times. Coalesced: one pending timer per bar covers
    -- the whole sweep (same pattern as _range.slotPending in
    -- CUI_ActionBars_Range.lua) instead of a timer+closure
    -- per OnLeave each running the O(bars) hovered scan. Callback built once per state
    -- and reused; opts is stable per bar (one BuildHandlers call).
    if status.foPending then return end
    status.foPending = true
    local callback = status.foCb
    if not callback then
        callback = function()
            status.foPending = false
            if options.isStillHovered and options.isStillHovered(status) then
                if options.markHoveredWhileActive then status.isHovered = true end
                return
            end
            if status.isHovered then return end
            -- Ground truth: Enter/Leave interleaves between a bar frame and
            -- its children can leave isHovered false while the cursor never
            -- left the bar (fade flicker per twitch). One C call settles it.
            if status.frame and status.frame:IsMouseOver() then
                status.isHovered = true
                return
            end
            if _quickKeybindState.open then return end
            if options.blockFadeOut and options.blockFadeOut(status) then return end
            -- When showing all bars together, keep visible while any bar is hovered
            if ABAR.db.profile.mouseoverShowAll and mod.AnyMouseoverBarHovered() then return end
            EAB_VTABLE.Hover.FadeOut(barId, status)
            -- Broadcast fade-out to all other mouseover bars, lockstep
            -- (cheap via the shared fader, same as the fade-in broadcast).
            if ABAR.db.profile.mouseoverShowAll then
                for otherKey, otherState in pairs(hoverStates) do
                    if otherKey ~= barId and not otherState.isHovered then
                        EAB_VTABLE.Hover.FadeOut(otherKey, otherState)
                    end
                end
            end
        end
        status.foCb = callback
    end
    C_Timer_After(0.1, callback)
end

function EAB_VTABLE.Hover.BuildHandlers(barId, status, options)
    options = options or {}

    local function OnEnter(self)
        if options.canEnter and not options.canEnter(self, status) then return end
        status.isHovered = true
        EAB_VTABLE.Hover.FadeIn(barId, status)
    end

    local function OnLeave()
        status.isHovered = false
        EAB_VTABLE.Hover.ScheduleFadeOut(barId, status, options)
    end

    return OnEnter, OnLeave
end

local function AttachDataBarHoverHooks(barId)
    if hoverStates[barId] then return end

    local widget = dataBarFrames[barId]
    if not widget then return end

    local status = EAB_VTABLE.Hover.GetState(barId, widget)
    local OnEnter, OnLeave = EAB_VTABLE.Hover.BuildHandlers(barId, status)

    widget:HookScript("OnEnter", OnEnter)
    widget:HookScript("OnLeave", OnLeave)
end

local function AttachHoverHooks(barId)
    -- Idempotency (same guard as both sibling attach functions): HookScript
    -- stacks and can never be unhooked, so a second pass would permanently
    -- double every hover handler on the bar and its 12 buttons.
    if hoverStates[barId] then return end

    local widget = barFrames[barId]
    local buttons = barButtons[barId]
    if not widget or not buttons then return end

    local status = EAB_VTABLE.Hover.GetState(barId, widget)

    local function CanEnter(self)
        -- Skip hidden empty buttons (alwaysShowButtons off)
        local cfg = ABAR.db.profile.bars[barId]
        if cfg then
            local showEmpty = cfg.alwaysShowButtons
            if showEmpty == nil then showEmpty = true end
            if not showEmpty then
                if self ~= widget then
                    -- Individual button: skip a parked empty slot (our own
                    -- record, never GetAlpha: another addon may fade the button).
                    if mod._eabParked(self) then return false end
                else
                    -- Bar frame itself (gaps between buttons): allow only if the
                    -- cursor is within pad of a shown button that is not parked.
                    local curX, curY = GetCursorPosition()
                    local scale = widget:GetEffectiveScale()
                    curX, curY = curX / scale, curY / scale
                    local pad = (cfg.buttonPadding or 2) + 2
                    local nearVisible = false
                    for index = 1, #buttons do
                        local button = buttons[index]
                        if button and button:IsShown() and not mod._eabParked(button) then
                            local bl, bb, bw, bh = button:GetRect()
                            if
                                bl
                                and curX >= bl - pad
                                and curX <= bl + bw + pad
                                and curY >= bb - pad
                                and curY <= bb + bh + pad
                            then
                                nearVisible = true
                                break
                            end
                        end
                    end
                    if not nearVisible then return false end
                end
            end
        end
        return true
    end

    local OnEnter, OnLeave = EAB_VTABLE.Hover.BuildHandlers(barId, status, {
        canEnter = CanEnter,
        blockFadeOut = function()
            -- Keep bar visible while a spell flyout spawned from this bar is open.
            return GetEABFlyout():IsVisible() and GetEABFlyout():IsMouseOver()
        end,
    })

    widget:HookScript("OnEnter", OnEnter)
    widget:HookScript("OnLeave", OnLeave)
    for index = 1, #buttons do
        local button = buttons[index]
        if button then
            button:HookScript("OnEnter", OnEnter)
            button:HookScript("OnLeave", OnLeave)
        end
    end
end

-- onlyHoverGated: visit ONLY the bars whose hover gate can move on a state edge (Match
-- Any plus mouseover). The edge-driven caller passes it so a target change does not drag
-- every other bar through a StopFade/SetAlpha it cannot need.
function ABAR:RefreshMouseover(onlyHoverGated)
    for _, details in ipairs(ALL_BARS) do
        local key = details.key
        local barCfg = self.db.profile.bars[key]
        if
            barCfg and (not onlyHoverGated or (barCfg.mouseoverEnabled and barCfg.visibilityMatch == "any"))
        then
            local widget = BarAlphaFrame(key, details)
            if widget then
                if details.noManagedVisibility then
                    -- Position-only Blizzard-owned eye (QueueStatus): CUI no longer
                    -- controls its visibility, so never fade or alpha-hide it --
                    -- force full opacity regardless of stale mouseover settings.
                    StopFade(widget, 1)
                elseif barCfg.mouseoverEnabled then
                    if details.isDataBar then AttachDataBarHoverHooks(key) end
                    -- Ensure extra bars have hover hooks attached (may not have been
                    -- set up at load time if mouseover was disabled then)
                    if details.visibilityOnly and not details.isDataBar and not details.isBlizzardMovable then
                        mod.AttachExtraBarHoverHooks(details)
                    end
                    local status = hoverStates[key]
                    -- A bar the cursor is sitting on keeps what the hover gave it. This
                    -- used to be safe by accident (the function only ran on settings
                    -- changes); it now also runs on combat/group/mount edges, where
                    -- repainting would yank a hovered bar invisible mid-hover.
                    if not (status and status.isHovered) then
                        local resting = EAB_VTABLE.Hover.RestingAlpha(key, barCfg)
                        StopFade(widget, resting)
                        if status then status.fadeDir = (resting == 0) and "out" or nil end
                        if key == "MainBar" then SyncPagingAlpha(resting) end
                    end
                else
                    StopFade(widget, barCfg.mouseoverAlpha or 1)
                    local status = hoverStates[key]
                    if status then status.fadeDir = nil end
                    if key == "MainBar" then SyncPagingAlpha(barCfg.mouseoverAlpha or 1) end
                end
            end
        end
    end
end

-- The Advanced Fade hooks are installed once, the first time a bar has a
-- condition checked; a session whose bars never pick one runs the alpha
-- functions above with no hook on them at all.
function ABAR:EnsureAdvancedFadeHooks()
    if self._advancedFadeHooksInstalled then return end
    self._advancedFadeHooksInstalled = true

    hooksecurefunc(ABAR, "ApplyBarOpacity", function(_, barId)
        if ABAR._anyCustomFade then EAB_VTABLE.Hover.RefreshCustomFadeBar(barId, false, true) end
    end)

    hooksecurefunc(EAB_VTABLE.Hover, "FadeInOne", function(barId)
        if ABAR._anyCustomFade then EAB_VTABLE.Hover.RefreshCustomFadeBar(barId, true, true) end
    end)

    hooksecurefunc(EAB_VTABLE.Hover, "FadeOut", function(barId)
        if ABAR._anyCustomFade then EAB_VTABLE.Hover.RefreshCustomFadeBar(barId, true, true) end
    end)

    hooksecurefunc(ABAR, "RefreshMouseover", function(self)
        if self._anyCustomFade then self:RefreshAllCustomFade(false, true) end
    end)

    self._advancedFadeUpdater = function()
        if ABAR._anyCustomFade then ABAR:RefreshAllCustomFade(true, false) end
    end
end

-- Entry points the files after this one re-import by name.
Inner.hoverStates, Inner.AttachDataBarHoverHooks, Inner.AttachHoverHooks =
    hoverStates, AttachDataBarHoverHooks, AttachHoverHooks
