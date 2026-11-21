if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_Visibility.lua
--
--  Frame alpha and visibility helpers (fade out of combat, resting alpha,
--  show on missing health) and the frame hover handlers, published as
--  I.UnitFrame_OnEnter / I.UnitFrame_OnLeave for CUI_UnitFrames_Init.lua.
--  Reads the main file through ns and ns._internals; db via I.dbSetters.
-------------------------------------------------------------------------------
local _, mod = ...

local Inner = mod._internals
local frameList = Inner.frames
local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val) saved = val end

-- Effective whole-frame alpha for a unit frame. When "Fade Out of Combat" is enabled
-- and the player is out of combat, shows at oocAlpha; otherwise full opacity (off by
-- default, existing setups unchanged). Every "shown" SetAlpha site (visibility loop +
-- mouseover hover) routes through this so a combat transition or hover can't clobber
-- the fade. Combat state comes from the caller (the visibility loop's event-tracked
-- _ufInCombat, which leads InCombatLockdown() on regen events). On ns: the pass calls it.
function mod.ResolveFrameAlpha(cfg, inCombat)
    if cfg and cfg.oocFadeEnabled and not inCombat then return cfg.oocAlpha or 0.5 end
    return 1
end

-- The alpha a unit frame RESTS at while the cursor is not on it, plus whether that resting
-- state is a hover gate (an alpha 0 a hover may legitimately lift). Single source of truth:
-- the visibility pass and both hover handlers derive from it, so a mouse leave cannot land
-- on a different verdict than the pass would. On ns: the pass calls it. hiddenByOpts
-- leads because it did in the pass too (it re-forced 0 at the end of the chain); returning
-- hoverGated false with it stops a hover from revealing what an option lane has hidden.
function mod.ResolveVisResting(cfg, widget, ext, hiddenByOpts, inCombat)
    if hiddenByOpts then return 0, false end
    local shownAlpha = mod.ResolveFrameAlpha(cfg, inCombat)
    if ext == "mouseover" then return 0, true end
    if ext ~= nil then
        -- Driver registered: it owns hiding, so alpha only carries the ooc fade.
        if widget and widget._cuiVisDriver then return shownAlpha, false end
        return ext and shownAlpha or 0, false
    end
    local vis = cfg.barVisibility or "always"
    -- Never rides the alpha too, not just the Show/Hide bucket: that bucket is
    -- lockdown-gated, so a Never picked in combat would otherwise leave the frame at
    -- full alpha until PLAYER_REGEN_ENABLED. An override reaches the ext block above.
    if vis == "never" then return 0, false end
    if vis == "in_combat" then return inCombat and shownAlpha or 0, false end
    if vis == "out_of_combat" then return (not inCombat) and shownAlpha or 0, false end
    if cfg.showWhenHealthMissing then
        if vis == "in_raid" then return IsInRaid() and shownAlpha or 0, false end
        if vis == "in_party" then return (IsInGroup() and not IsInRaid()) and shownAlpha or 0, false end
        if vis == "solo" then return (not IsInGroup()) and shownAlpha or 0, false end
    end
    if vis == "mouseover" then
        -- Legacy single mouseover: a configured "Hide if" override that is NOT currently
        -- triggering counts as a positive show, so the frame does not require hover
        -- (fixes "dismount in combat keeps frame hidden" / "hide if no target inverted").
        local hasAnyHideOpt = CludesUI.VisHasAnyOption(cfg)
        if hasAnyHideOpt then return shownAlpha, false end
        return 0, true
    end
    return shownAlpha, false
end

-- Same verdict for callers outside the visibility pass (the hover handlers): derives the
-- two inputs the pass would have handed over. State is left nil so the shared engine fills
-- it from its own combat/group tracking.
function mod.ResolveVisRestingLive(s, widget)
    local hiddenByOpts = CludesUI.CheckVisibilityOptions(s)
    local ext = CludesUI.EvalVisibilityExtended(s, "barVisibility", nil, CludesUI.VIS_CAPS_DEFAULT)
    local alpha, hoverGated = mod.ResolveVisResting(s, widget, ext, hiddenByOpts, InCombatLockdown())
    return alpha, hoverGated, hiddenByOpts
end

--- Is the hover mechanism wired for this frame at all? The cheap static prefilter both
--- handlers use, kept static on purpose (a live verdict here would write alpha on every
--- mouse leave of every frame). An applied Visibility override answers it too: it holds
--- the hover state itself, and without this the frame would rest at alpha 0 with no
--- handler willing to reveal it again.
function mod.VisMouseoverWired(cfg)
    if not cfg then return false end
    if (cfg.barVisibility or "always") == "mouseover" then return true end
    return (CludesUI.VisOverrideValue(cfg)) == "mouseover"
end

-- Health visibility is a display-only reveal. The curve result is always secret
-- (UnitHealthPercent returns secrets): hand it directly to alpha setters, never
-- use it as a Lua condition. Those frames' GetAlpha then reads secret too.
function mod.HealthVisibilityEnabled(cfg, widget)
    if not cfg or not cfg.showWhenHealthMissing or not widget then return false end
    local unitToken = widget._cuiUnit
    if unitToken ~= "player" and unitToken ~= "target" and unitToken ~= "focus" then return false end
    if mod.VisUnitDisabled(saved.profile, unitToken) then return false end
    local override = CludesUI.VisOverrideValue(cfg)
    return (override or cfg.barVisibility or "always") ~= "never"
end

-- Every writer of the reveal (the visibility pass, both hover handlers) goes
-- through here, so the curve always maps full health to the base alpha last
-- painted, and _healthVisLive says whether the reveal currently applies.
function mod.HealthVisibilityAlpha(s, widget, baseAlpha, hoverGated, inCombat)
    if not mod.HealthVisibilityEnabled(s, widget) then
        if widget then widget._healthVisLive = nil end
        return baseAlpha
    end
    widget._healthVisLive = true
    -- A visibility refresh must preserve an active mouseover reveal. Keep
    -- this decision on clean UI state, before evaluating the health curve.
    if hoverGated and widget._healthVisHovered then baseAlpha = mod.ResolveFrameAlpha(s, inCombat) end
    if not widget._healthVisCurve then
        widget._healthVisCurve = C_CurveUtil.CreateCurve()
        widget._healthVisCurve:SetType(Enum.LuaCurveType.Step)
    end
    if widget._healthVisCurveAlpha ~= baseAlpha then
        widget._healthVisCurve:ClearPoints()
        widget._healthVisCurve:AddPoint(0, 1)
        widget._healthVisCurve:AddPoint(1, baseAlpha)
        widget._healthVisCurveAlpha = baseAlpha
    end
    return UnitHealthPercent(widget._cuiUnit, false, widget._healthVisCurve)
end

-- A health event moves only the curve's input: the base alpha and whether the
-- reveal applies change on visibility events and hover, which repaint through
-- HealthVisibilityAlpha above. So a health tick re-evaluates the stamped curve
-- and re-derives nothing (this runs on every UNIT_HEALTH in combat).
function mod.UpdateHealthVisibilityUnit(unitToken)
    local widget = frameList[unitToken]
    if not (widget and widget._healthVisLive and widget._healthVisCurve) then return end
    local alpha = UnitHealthPercent(unitToken, false, widget._healthVisCurve);
    (widget._visWrap or widget):SetAlpha(alpha)
    local model = widget.Portrait and widget.Portrait.backdrop and widget.Portrait.backdrop._3d
    if model then mod.UF_SetModelAlpha(model, alpha) end
    local mini = mod.UF_MINI_OF and frameList[mod.UF_MINI_OF[unitToken]]
    if mini and not (unitToken == "player" and saved.profile.pet and saved.profile.pet.alwaysShow) then
        mini:SetAlpha(alpha)
    end
end

function mod.SyncHealthVisibilityEvents()
    local player = mod.HealthVisibilityEnabled(saved.profile.player, frameList.player)
    local target = mod.HealthVisibilityEnabled(saved.profile.target, frameList.target)
    local focus = mod.HealthVisibilityEnabled(saved.profile.focus, frameList.focus)
    local mask = (player and 1 or 0) + (target and 2 or 0) + (focus and 4 or 0)
    local eventFrame = mod.healthVisibilityEvents
    if not eventFrame then
        if mask == 0 then return end
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, evt, unitToken)
            if evt == "PLAYER_FOCUS_CHANGED" then unitToken = "focus" end
            mod.UpdateHealthVisibilityUnit(unitToken)
        end)
        mod.healthVisibilityEvents = eventFrame
    end
    if eventFrame.mask == mask then return end
    eventFrame.mask = mask
    eventFrame:UnregisterAllEvents()
    if mask ~= 0 then
        local units = eventFrame.units or {}
        eventFrame.units = units
        wipe(units)
        if player then units[#units + 1] = "player" end
        if target then units[#units + 1] = "target" end
        if focus then units[#units + 1] = "focus" end
        eventFrame:RegisterUnitEvent("UNIT_HEALTH", unpack(units))
        eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", unpack(units))
        if focus then eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED") end
    end
end

local function UnitFrame_OnEnter(self)
    local unitToken = self._cuiUnit
    if not unitToken then return end
    local unitKey = unitToken:match("^boss%d$") and "boss" or unitToken
    local cfg = saved and saved.profile and saved.profile[unitKey]
    if cfg and cfg.showWhenHealthMissing then self._healthVisHovered = true end
    if mod.VisMouseoverWired(cfg) then
        -- Reveal only what is actually hover-gated right now. Under Any the frame may
        -- already be shown on another passing disjunct, in which case there is nothing to
        -- reveal and OnLeave must not undo anything either -- both handlers read the same
        -- resting verdict so they cannot disagree.
        local _, hoverGated = mod.ResolveVisRestingLive(cfg, self)
        if hoverGated then
            local a = mod.ResolveFrameAlpha(cfg, InCombatLockdown())
            if cfg.showWhenHealthMissing then a = mod.HealthVisibilityAlpha(cfg, self, a) end
            (self._visWrap or self):SetAlpha(a)
            -- 3D models don't inherit parent alpha: reveal the portrait too
            local bd3d = self.Portrait and self.Portrait.backdrop and self.Portrait.backdrop._3d
            if bd3d then mod.UF_SetModelAlpha(bd3d, a) end
            -- Mini-frame inheritance: the companion frame reveals with us.
            -- Always Show Pet Frame opts the pet out (it is already visible
            -- and must not pick up the player's fade alpha).
            local mini = mod.UF_MINI_OF and frameList[mod.UF_MINI_OF[unitKey]]
            if mini and not (unitKey == "player" and saved.profile.pet and saved.profile.pet.alwaysShow) then
                mini:SetAlpha(a)
            end
        end
    end
    if unitToken and GameTooltip and GameTooltip_SetDefaultAnchor then
        local showTooltip = not cfg or cfg.showUnitTooltip ~= false
        if showTooltip then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
            if GameTooltip:SetUnit(unitToken) then GameTooltip:Show() end
            if self._tooltipTicker then self._tooltipTicker:Cancel() end
            self._tooltipTicker = C_Timer.NewTicker(0.5, function()
                if not self:IsMouseOver() then
                    if self._tooltipTicker then
                        self._tooltipTicker:Cancel()
                        self._tooltipTicker = nil
                    end
                    return
                end
                GameTooltip_SetDefaultAnchor(GameTooltip, self)
                if GameTooltip:SetUnit(self._cuiUnit) then GameTooltip:Show() end
            end)
        end
    end
end

local function UnitFrame_OnLeave(self)
    self._healthVisHovered = nil
    local unitToken = self._cuiUnit
    if not unitToken then return end
    local unitKey = unitToken:match("^boss%d$") and "boss" or unitToken
    local cfg = saved and saved.profile and saved.profile[unitKey]
    if mod.VisMouseoverWired(cfg) then
        -- Return to the resting alpha the visibility pass would paint, never a hardcoded
        -- 0: under Any a passing disjunct keeps the frame visible with no hover involved,
        -- and hiding it here would leave it wrong until the next visibility event fires.
        local leaveAlpha, _, hiddenByOpts = mod.ResolveVisRestingLive(cfg, self)
        if cfg.showWhenHealthMissing and not hiddenByOpts then
            leaveAlpha = mod.HealthVisibilityAlpha(cfg, self, leaveAlpha)
        else
            self._healthVisLive = nil
        end
        (self._visWrap or self):SetAlpha(leaveAlpha)
        -- 3D models don't inherit parent alpha: hide/dim the portrait too
        local bd3d = self.Portrait and self.Portrait.backdrop and self.Portrait.backdrop._3d
        if bd3d then mod.UF_SetModelAlpha(bd3d, leaveAlpha) end
        -- Mini-frame inheritance: the companion frame hides/dims with us.
        -- Always Show Pet Frame opts the pet out (a leave alpha of 0 would
        -- hide a pet frame that must stay visible).
        local mini = mod.UF_MINI_OF and frameList[mod.UF_MINI_OF[unitKey]]
        if mini and not (unitKey == "player" and saved.profile.pet and saved.profile.pet.alwaysShow) then
            mini:SetAlpha(leaveAlpha)
        end
    end
    if self._tooltipTicker then
        self._tooltipTicker:Cancel()
        self._tooltipTicker = nil
    end
    if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

Inner.UnitFrame_OnEnter = UnitFrame_OnEnter
Inner.UnitFrame_OnLeave = UnitFrame_OnLeave
