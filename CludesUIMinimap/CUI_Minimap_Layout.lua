if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Minimap_Layout.lua
--
--  BuildCustomIndicators, the mouseover controller, LayoutIndicatorFrames,
--  the Blizzard minimap snapshot, the Omnium Folio and the map hover
--  reveal.
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIMinimap.lua or an earlier CUI_Minimap_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local _addonVisible, cachedAddonButtons, SKIN = Inner._addonVisible, Inner.cachedAddonButtons, Inner.EBS
local GetFFD, Pix, flyoutSavedParents = Inner.GetFFD, Inner.PP, Inner.flyoutSavedParents
local GetBtnRowMode, GetCustomTooltipScale = Inner.GetBtnRowMode, Inner.GetCustomTooltipScale
local GetElementRowMode, GetInteractableBtnSize = Inner.GetElementRowMode, Inner.GetInteractableBtnSize
local GetRowBase, IsJunkTexture, IsUngrouped = Inner.GetRowBase, Inner.IsJunkTexture, Inner.IsUngrouped
local RestoreButtonDecorations = Inner.RestoreButtonDecorations
local StripButtonDecorations, GetCoordsModePos = Inner.StripButtonDecorations, Inner.GetCoordsModePos
local UpdateCoords, ApplyBtnOffset = Inner.UpdateCoords, Inner.ApplyBtnOffset
local EnableFreeMove, FOLIO_REPLACEMENT_BUTTONS = Inner.EnableFreeMove, Inner.FOLIO_REPLACEMENT_BUTTONS
local _customIndicators, CreateGreatVaultBtn = Inner._customIndicators, Inner.CreateGreatVaultBtn
local CreateIndicatorBtn, CreatePortalBtn = Inner.CreateIndicatorBtn, Inner.CreatePortalBtn
local INDICATOR_ATLAS_OFFSET = Inner.INDICATOR_ATLAS_OFFSET
local INDICATOR_ATLAS_RATIO = Inner.INDICATOR_ATLAS_RATIO
local INDICATOR_ATLAS_SCALE, SizeGreatVaultBtn = Inner.INDICATOR_ATLAS_SCALE, Inner.SizeGreatVaultBtn
local SizePortalBtn, FRIENDS_ATLAS = Inner.SizePortalBtn, Inner.FRIENDS_ATLAS
local GetCalendarLockoutEntries = Inner.GetCalendarLockoutEntries
local HideCalendarTooltip, HideFriendsTooltip = Inner.HideCalendarTooltip, Inner.HideFriendsTooltip
local ShowCalendarTooltip, ShowFriendsTooltip = Inner.ShowCalendarTooltip, Inner.ShowFriendsTooltip
local SetMOEvaluate = Inner.SetMOEvaluate

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local flyoutToggle
Inner.flyoutToggleSetters[#Inner.flyoutToggleSetters + 1] = function(val)
    flyoutToggle = val
end
local flyoutPanel
Inner.flyoutPanelSetters[#Inner.flyoutPanelSetters + 1] = function(val)
    flyoutPanel = val
end
local _portalFlyout
Inner.portalFlyoutSetters[#Inner.portalFlyoutSetters + 1] = function(val)
    _portalFlyout = val
end
local coordFrame
Inner.coordFrameSetters[#Inner.coordFrameSetters + 1] = function(val)
    coordFrame = val
end
local coordTicker
Inner.coordTickerSetters[#Inner.coordTickerSetters + 1] = function(val)
    coordTicker = val
end
local clockBg
Inner.clockBgSetters[#Inner.clockBgSetters + 1] = function(val)
    clockBg = val
end

-- Assigned below; SetMOEvaluate hands it to the earlier files. It runs once,
-- at load: a file behind this one would have to import the function.
local MO_Evaluate

-- Calendar invite alert: defined below BuildCustomIndicators, which calls them.
local SyncCalendarInvites, DismissCalendarInvites

-- The Great Vault and M+ Portal buttons, built in BuildCustomIndicators.
local _greatVaultBtn = nil
local _portalBtn = nil

-- Outside the gamepad style our click opens the tracking menu. A press on ours while it is
-- open lets Blizzard's menu manager close it first, so that click must not reopen it.
do
    local opened, watch = false, nil
    local function Done()
        opened = false
        if watch then
            watch:UnregisterEvent("GLOBAL_MOUSE_UP")
        end
    end
    local function MenuOpen(blizBtn)
        return blizBtn.menu ~= nil and blizBtn.menu:IsShown()
    end
    -- After our click opened it: closed by something else (a release off ours) forgets it.
    function SKIN._TrackingMenuOpened(blizBtn, ours)
        opened = MenuOpen(blizBtn)
        if not opened then
            return
        end
        if not watch then
            watch = CreateFrame("Frame")
            watch:SetScript("OnEvent", function()
                if not MenuOpen(blizBtn) and not ours:IsMouseOver() then
                    Done()
                end
            end)
        end
        watch:RegisterEvent("GLOBAL_MOUSE_UP")
    end
    -- True when this click closed the menu our click opened (it is gone now).
    function SKIN._TrackingMenuClosedByPress(blizBtn)
        if not opened or MenuOpen(blizBtn) then
            return false
        end
        Done()
        return true
    end
    -- Closed while the mouse was away (Escape): forgotten on the way back in.
    function SKIN._TrackingMenuForget(blizBtn)
        if opened and not MenuOpen(blizBtn) then
            Done()
        end
    end
end

local function BuildCustomIndicators(minimap)
    if _customIndicators.tracking then
        -- Re-apply accent to the friends icon: a later ApplyAll (e.g. PLAYER_ENTERING_WORLD, after
        -- theme resolution mutates CLUDES_GREEN) must override the create-once read below, since creation can race theme resolution (same pattern as CreateFlyoutToggle).
        local fi = _customIndicators.friends and _customIndicators.friends._icon
        if fi then
            local EG2 = CludesUI.CLUDES_GREEN
            fi:SetVertexColor(EG2.r, EG2.g, EG2.b, 1)
        end
        return
    end

    -- Tracking
    _customIndicators.tracking = CreateIndicatorBtn(
        "_tracking",
        minimap,
        "UI-HUD-Minimap-Tracking-Up",
        "UI-HUD-Minimap-Tracking-Mouseover",
        "UI-HUD-Minimap-Tracking-Down",
        function(self)
            -- Gamepad UI: Blizzard's own button takes the click instead (SyncTrackingHotspot);
            -- a press here closed its open menu, so it takes clicks again.
            if SKIN._TrackingHotspotActive() then
                SKIN._TrackingClickState()
                return
            end
            local blizBtn = MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button
            if not blizBtn or not blizBtn.OpenMenu then
                return
            end

            if blizBtn.menu and blizBtn.menu:IsShown() then
                blizBtn.menu:Hide()
                return
            end
            if SKIN._TrackingMenuClosedByPress(blizBtn) then
                return
            end

            -- Position hidden Blizzard button at our custom button
            blizBtn:ClearAllPoints()
            blizBtn:SetPoint("CENTER", self, "CENTER", 0, 0)
            blizBtn:SetAlpha(0)
            blizBtn:EnableMouse(false)
            blizBtn:OpenMenu()

            if blizBtn.menu then
                blizBtn.menu:ClearAllPoints()
                blizBtn.menu:SetPoint("TOPRIGHT", self, "TOPLEFT", -4, 0)
            end
            SKIN._TrackingMenuOpened(blizBtn, self)
        end
    )
    local trackBaseEnter = _customIndicators.tracking:GetScript("OnEnter")
    local trackBaseLeave = _customIndicators.tracking:GetScript("OnLeave")
    _customIndicators.tracking:SetScript("OnEnter", function(self)
        if trackBaseEnter then
            trackBaseEnter(self)
        end
        -- Before a press: follow a live switch of the gamepad style and settle the hotspot.
        if SKIN._TrackingHotspotActive() then
            SKIN._TrackingClickState()
        end
        local blizBtn = MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button
        if blizBtn then
            SKIN._TrackingMenuForget(blizBtn)
        end
        if not GetFFD(self).freeMoveJustDragged then
            CludesUI.ShowWidgetTooltip(
                self,
                "Tracking",
                { anchor = SKIN._Grow.TT(), scale = GetCustomTooltipScale() }
            )
        end
    end)
    _customIndicators.tracking:SetScript("OnLeave", function(self)
        if trackBaseLeave then
            trackBaseLeave(self)
        end
        CludesUI.HideWidgetTooltip()
    end)

    -- Calendar (day-of-month atlas)
    local calDay = tonumber(date("%d")) or 1
    local calPrefix = "UI-HUD-Calendar-" .. calDay
    _customIndicators.calendar = CreateIndicatorBtn(
        "_gameTime",
        minimap,
        calPrefix .. "-Up",
        calPrefix .. "-Mouseover",
        calPrefix .. "-Down",
        function()
            DismissCalendarInvites()
            if ToggleCalendar then
                ToggleCalendar()
            end
        end
    )
    _customIndicators.calendar._calDay = calDay
    local calBaseEnter = _customIndicators.calendar:GetScript("OnEnter")
    local calBaseLeave = _customIndicators.calendar:GetScript("OnLeave")
    _customIndicators.calendar:SetScript("OnEnter", function(self)
        if calBaseEnter then
            calBaseEnter(self)
        end
        if GetFFD(self).freeMoveJustDragged then
            return
        end
        -- While the invite alert shows, the tooltip says why (as Blizzard's does).
        if self._invite and self._invite:IsShown() then
            CludesUI.ShowWidgetTooltip(
                self,
                GAMETIME_TOOLTIP_CALENDAR_INVITES,
                { anchor = SKIN._Grow.TT(), scale = GetCustomTooltipScale() }
            )
            return
        end
        local lockoutEntries
        if not (CludesUI.InProtectedInstance()) then
            lockoutEntries = GetCalendarLockoutEntries()
        end
        if lockoutEntries then
            ShowCalendarTooltip(self, lockoutEntries)
        else
            CludesUI.ShowWidgetTooltip(
                self,
                "Calendar",
                { anchor = SKIN._Grow.TT(), scale = GetCustomTooltipScale() }
            )
        end
    end)
    _customIndicators.calendar:SetScript("OnLeave", function(self)
        if calBaseLeave then
            calBaseLeave(self)
        end
        HideCalendarTooltip()
        CludesUI.HideWidgetTooltip()
    end)

    -- Mail (informational: tooltip + hover atlas only)
    _customIndicators.mail = CreateIndicatorBtn(
        "_mail",
        minimap,
        "UI-HUD-Minimap-Mail-Up",
        "UI-HUD-Minimap-Mail-Mouseover",
        nil,
        nil
    )
    local mailBaseEnter = _customIndicators.mail:GetScript("OnEnter")
    local mailBaseLeave = _customIndicators.mail:GetScript("OnLeave")
    _customIndicators.mail:SetScript("OnEnter", function(self)
        if SKIN._HVRevealMapHover then
            SKIN._HVRevealMapHover()
        end
        if mailBaseEnter then
            mailBaseEnter(self)
        end
        if not GetFFD(self).freeMoveJustDragged then
            local labelText = HAVE_MAIL
            -- Up to three latest senders, as Blizzard's own mail icon lists them
            -- (our button replaces it, so without this the names are lost).
            local senders = GetLatestThreeSenders and { GetLatestThreeSenders() } or nil
            if senders and #senders > 0 then
                labelText = HAVE_MAIL_FROM .. "\n" .. table.concat(senders, "\n")
            end
            CludesUI.ShowWidgetTooltip(
                self,
                labelText,
                { anchor = SKIN._Grow.TT(), scale = GetCustomTooltipScale() }
            )
        end
    end)
    _customIndicators.mail:SetScript("OnLeave", function(self)
        if mailBaseLeave then
            mailBaseLeave(self)
        end
        CludesUI.HideWidgetTooltip()
    end)

    -- Crafting Order (informational: tooltip + hover atlas only)
    _customIndicators.crafting = CreateIndicatorBtn(
        "_crafting",
        minimap,
        "UI-HUD-Minimap-CraftingOrder-Up-2x",
        "UI-HUD-Minimap-CraftingOrder-Over-2x",
        "UI-HUD-Minimap-CraftingOrder-Down-2x",
        nil
    )
    local craftBaseEnter = _customIndicators.crafting:GetScript("OnEnter")
    local craftBaseLeave = _customIndicators.crafting:GetScript("OnLeave")
    _customIndicators.crafting:SetScript("OnEnter", function(self)
        if craftBaseEnter then
            craftBaseEnter(self)
        end
        if not GetFFD(self).freeMoveJustDragged then
            local labelText = "Crafting Orders"
            if C_CraftingOrders and C_CraftingOrders.GetPersonalOrdersInfo then
                local infos = C_CraftingOrders.GetPersonalOrdersInfo()
                if type(infos) == "table" then
                    local lines = {}
                    for _, details in ipairs(infos) do
                        local total = tonumber(details.numPersonalOrders) or 0
                        if total > 0 then
                            local name = tostring(details.professionName or details.profession or "Unknown")
                            lines[#lines + 1] = total .. " " .. name .. " Order" .. (total > 1 and "s" or "")
                        end
                    end
                    if #lines > 0 then
                        labelText = labelText .. "\n" .. table.concat(lines, "\n")
                    end
                end
            end
            CludesUI.ShowWidgetTooltip(
                self,
                labelText,
                { anchor = SKIN._Grow.TT(), scale = GetCustomTooltipScale() }
            )
        end
    end)
    _customIndicators.crafting:SetScript("OnLeave", function(self)
        if craftBaseLeave then
            craftBaseLeave(self)
        end
        CludesUI.HideWidgetTooltip()
    end)

    -- Friends Online button
    _customIndicators.friends = CreateIndicatorBtn(
        "_friends",
        minimap,
        FRIENDS_ATLAS,
        FRIENDS_ATLAS,
        nil,
        function()
            if InCombatLockdown() then
                UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.3, 0.3, 1.0)
                return
            end
            ToggleFriendsFrame()
        end
    )
    -- Not in INDICATOR_ATLAS_RATIO, so the icon uses inset anchoring; desaturated idle.
    if _customIndicators.friends._icon then
        _customIndicators.friends._icon:SetDesaturated(true)
        CludesUI.RegAccent({ type = "vertex", obj = _customIndicators.friends._icon })
        -- Apply current accent immediately (initial accent pass already ran)
        local g = CludesUI.CLUDES_GREEN
        if g then
            _customIndicators.friends._icon:SetVertexColor(g.r, g.g, g.b, 1)
        end
        _customIndicators.friends._icon:SetAlpha(0.85)
    end
    local friendsBtnEnter = _customIndicators.friends:GetScript("OnEnter")
    local friendsBtnLeave = _customIndicators.friends:GetScript("OnLeave")
    _customIndicators.friends:SetScript("OnEnter", function(self)
        if friendsBtnEnter then
            friendsBtnEnter(self)
        end
        if self._icon then
            self._icon:SetAlpha(1)
        end
        if GetFFD(self).freeMoveJustDragged then
            return
        end
        ShowFriendsTooltip(self)
    end)
    _customIndicators.friends:SetScript("OnLeave", function(self)
        if friendsBtnLeave then
            friendsBtnLeave(self)
        end
        if self._icon then
            self._icon:SetAlpha(0.85)
        end
        HideFriendsTooltip()
    end)

    -- Great Vault + M+ Portal buttons: built once, anchored in LayoutIndicatorFrames.
    -- Neither exists on WoW Forever (no vault, no keystone portals): the buttons are
    -- never built there, every reader guards on nil, and the options drop their rows.
    if not CludesUI.IS_FOREVER then
        _greatVaultBtn = CreateGreatVaultBtn(minimap)
        _portalBtn = CreatePortalBtn(minimap)
    end
end

-- Gamepad UI only: Blizzard's tracking button takes the clicks on ours, so its menu
-- opens from a hardware press (closing an addon-opened one taints the gamepad bindings).
local SyncTrackingHotspot
do
    local ev, home, isActive
    local function Btns()
        return MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button,
            _customIndicators.tracking
    end
    -- No clicks while its menu is open: the menu's close check sees ours under the mouse, so
    -- a press on ours closes it instead of close+reopen. Settled on release, enter and click.
    function SKIN._TrackingClickState()
        local blizBtn = Btns()
        if not (isActive and blizBtn) then
            return
        end
        local mp = SKIN.db and SKIN.db.profile.minimap
        local shift = mp and mp.freeMoveBtns and IsShiftKeyDown()
        blizBtn:SetMouseClickEnabled(not shift and not (blizBtn.IsMenuOpen and blizBtn:IsMenuOpen()))
    end
    -- The style is read live (no event): our button's enter and click re-check it.
    function SKIN._TrackingHotspotActive()
        local mp = SKIN.db and SKIN.db.profile.minimap
        if mp and isActive ~= (CludesUI.PadGamepadUI() and true or false) then
            SyncTrackingHotspot(mp)
        end
        return isActive
    end
    SyncTrackingHotspot = function(p)
        local blizBtn, ours = Btns()
        if not (blizBtn and ours) then
            return
        end
        local enabled = CludesUI.PadGamepadUI() and not p.hideTrackingButton and ours:IsShown() or false
        if enabled then
            if not home then
                local wid, hgt = blizBtn:GetSize()
                home = { blizBtn:GetParent(), wid, hgt, blizBtn:GetPoint(1) }
            end
            -- Its menu hangs from its bottom-left: the frame sits just above ours, so the menu
            -- opens beside ours (as the click handler places it); the hit rect is moved onto ours.
            local wid, hgt = ours:GetSize()
            if blizBtn:GetParent() ~= ours then
                blizBtn:SetParent(ours)
            end
            blizBtn:ClearAllPoints()
            blizBtn:SetSize(wid, hgt)
            blizBtn:SetPoint("BOTTOMLEFT", ours, "TOPLEFT", -4, 0)
            blizBtn:SetHitRectInsets(4, -4, hgt, -hgt)
            blizBtn:SetAlpha(0)
            blizBtn:SetFrameLevel(ours:GetFrameLevel() + 5)
        elseif home and blizBtn:GetParent() == ours then
            blizBtn:SetParent(home[1])
            blizBtn:ClearAllPoints()
            blizBtn:SetSize(home[2], home[3])
            if home[4] then
                blizBtn:SetPoint(home[4], home[5], home[6], home[7], home[8])
            end
            blizBtn:SetHitRectInsets(0, 0, 0, 0)
            blizBtn:SetAlpha(1)
            blizBtn:EnableMouse(false)
        end
        -- The click state is settled on every release, and on a modifier key while Free
        -- Move is on: it drags ours with Shift held, so the hotspot steps aside meanwhile.
        local fm = enabled and p.freeMoveBtns and true or false
        isActive = enabled
        if enabled and not ev then
            ev = CreateFrame("Frame")
            ev:SetScript("OnEvent", function()
                SKIN._TrackingClickState()
            end)
        end
        if ev then
            if enabled then
                ev:RegisterEvent("GLOBAL_MOUSE_UP")
            else
                ev:UnregisterEvent("GLOBAL_MOUSE_UP")
            end
            if fm then
                ev:RegisterEvent("MODIFIER_STATE_CHANGED")
            else
                ev:UnregisterEvent("MODIFIER_STATE_CHANGED")
            end
        end
        if not enabled then
            return
        end
        -- Clicks only: hover stays on ours (its tooltip and art), Blizzard's tooltip never shows.
        blizBtn:SetMouseMotionEnabled(false)
        SKIN._TrackingClickState()
    end
end

-- Hide the Blizzard originals so they never render or intercept clicks
local function HideBlizzardIndicators()
    local tracking = MinimapCluster and MinimapCluster.Tracking
    if tracking then
        tracking:SetAlpha(0)
        tracking:EnableMouse(false)
        -- The click and tooltip scripts live on the child button, and a
        -- parent's mouse state does not reach it: left enabled it is an
        -- invisible hotspot at the cluster's corner.
        if tracking.Button then
            tracking.Button:EnableMouse(false)
        end
    end
    local gameTime = _G.GameTimeFrame
    if gameTime then
        gameTime:SetAlpha(0)
        gameTime:EnableMouse(false)
    end
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    if indicator then
        if indicator.MailFrame then
            indicator.MailFrame:SetAlpha(0)
            indicator.MailFrame:EnableMouse(false)
        end
        if indicator.CraftingOrderFrame then
            indicator.CraftingOrderFrame:SetAlpha(0)
            indicator.CraftingOrderFrame:EnableMouse(false)
        end
    end
end

-------------------------------------------------------------------------------
--  Calendar invite alert: the pulsing notice Blizzard's own calendar button
--  shows for pending invites, which our button replaces, so it is on whenever
--  Calendar is shown. Same rules as Blizzard's: it shows when the pending count
--  rises while the calendar is closed, clicking the button dismisses it until
--  another invite arrives, and it clears once no invite is pending.
--  With Calendar hidden the event frame stays inert; the notice is built on
--  first show.
-------------------------------------------------------------------------------
local _inviteEvents = CreateFrame("Frame")
local _inviteListening = false -- its two events are registered
local _inviteSeen = 0 -- pending count already alerted (or dismissed)

local function SetInviteShown(cal, show)
    if show and not cal._invite then
        -- Own child frame, so the pulse fades only the notice, never the day icon.
        local invite = CreateFrame("Frame", nil, cal)
        invite:SetAllPoints(cal)
        invite:SetFrameLevel(cal:GetFrameLevel() + 2)
        invite:Hide()
        local glow = invite:CreateTexture(nil, "OVERLAY", nil, 1)
        glow:SetTexture("Interface\\Calendar\\EventNotificationGlow")
        glow:SetBlendMode("ADD")
        glow:SetPoint("TOPLEFT", invite, "TOPLEFT", -6, 6)
        glow:SetPoint("BOTTOMRIGHT", invite, "BOTTOMRIGHT", 6, -6)
        local notice = invite:CreateTexture(nil, "OVERLAY", nil, 2)
        notice:SetTexture("Interface\\Calendar\\EventNotification")
        notice:SetTexCoord(0.03125, 0.6484375, 0.03125, 0.8671875)
        notice:SetAllPoints(invite)
        -- Fade out and back in, a full cycle every two seconds; runs only while shown.
        local pulse = invite:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(1)
        fade:SetSmoothing("IN_OUT")
        invite:SetScript("OnShow", function()
            pulse:Play()
        end)
        invite:SetScript("OnHide", function()
            pulse:Stop()
        end)
        cal._invite = invite
    end
    if cal._invite then
        cal._invite:SetShown(show)
    end
end

SyncCalendarInvites = function()
    local cal = _customIndicators.calendar
    if not cal then
        return
    end
    local mp = SKIN.db and SKIN.db.profile.minimap
    local enabled = mp and not mp.hideGameTime or false
    if enabled ~= _inviteListening then
        _inviteListening = enabled
        if enabled then
            _inviteEvents:RegisterEvent("CALENDAR_UPDATE_PENDING_INVITES")
            _inviteEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
        else
            _inviteEvents:UnregisterAllEvents()
        end
    end
    if not enabled then
        _inviteSeen = 0
        SetInviteShown(cal, false)
        return
    end
    local pending = C_Calendar.GetNumPendingInvites() or 0
    -- Answering an invite lowers the count: the next new one must alert again.
    if pending < _inviteSeen then
        _inviteSeen = pending
    end
    if pending == 0 then
        _inviteSeen = 0
        SetInviteShown(cal, false)
    elseif pending > _inviteSeen and not (CalendarFrame and CalendarFrame:IsShown()) then
        _inviteSeen = pending
        SetInviteShown(cal, true)
    end
end
_inviteEvents:SetScript("OnEvent", function()
    SyncCalendarInvites()
end)

DismissCalendarInvites = function()
    local cal = _customIndicators.calendar
    if cal then
        SetInviteShown(cal, false)
    end
end

local function SyncIndicatorVisibility()
    SyncCalendarInvites()
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    if _customIndicators.mail then
        local hasMail = false
        if HasNewMail then
            local raw = HasNewMail()
            if not issecretvalue(raw) then
                hasMail = raw or false
            end
        end
        local mp = SKIN.db and SKIN.db.profile.minimap
        if mp and mp.hideMail then
            hasMail = false
        end
        _customIndicators.mail:SetShown(hasMail)
    end
    if _customIndicators.crafting then
        local blizCraft = indicator and indicator.CraftingOrderFrame
        local hasCraft = blizCraft and blizCraft:IsShown()
        _customIndicators.crafting:SetShown(hasCraft or false)
    end
end

-------------------------------------------------------------------------------
--  Mouseover Extra Buttons: Great Vault/Portals/Friends/Group Button show only while
--  the mouse is over the minimap or one of them (either flyout open keeps them shown
--  until it closes). Event-driven off OnEnter/OnLeave, with a small deferred hide so
--  crossing tiny inter-frame gaps doesn't flicker.
-------------------------------------------------------------------------------
local _moActive = false -- mouseover mode currently engaged
local _moButtons = {} -- extra buttons under control this layout
local _moHooked = {} -- frames whose OnEnter/OnLeave we've already hooked
local _moHideTimer = nil

local function MO_OverAny()
    if Minimap then
        local mapRegion = GetFFD(Minimap).pingBlocker or GetFFD(Minimap).layoutFrame or Minimap
        if mapRegion:IsMouseOver() then
            return true
        end
    end
    if _portalFlyout and _portalFlyout:IsShown() then
        return true
    end
    if flyoutPanel and flyoutPanel:IsShown() then
        return true
    end
    -- The friends tooltip is interactive (whisper/invite rows), so it keeps the stack
    -- shown like a flyout; it self-hides on a real exit and its OnHide re-evaluates.
    local ftt = SKIN._friendsTT
    if ftt and ftt:IsShown() then
        return true
    end
    for i = 1, #_moButtons do
        local b = _moButtons[i]
        if b:IsShown() and b:IsMouseOver() then
            return true
        end
    end
    return false
end

local function MO_Apply(show)
    local a = show and 1 or 0
    for i = 1, #_moButtons do
        _moButtons[i]:SetAlpha(a)
    end
end

local function MO_CancelHide()
    if _moHideTimer then
        _moHideTimer:Cancel()
        _moHideTimer = nil
    end
end

-- Assign the forward-declared upvalue so the earlier flyout hooks can re-evaluate.
MO_Evaluate = function()
    if not _moActive then
        return
    end
    MO_CancelHide()
    if MO_OverAny() then
        MO_Apply(true)
    else
        -- Brief delay bridges adjacent-frame gaps (minimap -> button, button -> button)
        -- so crossing one doesn't flash the stack off and on.
        _moHideTimer = C_Timer.NewTimer(0.12, function()
            _moHideTimer = nil
            if _moActive and not MO_OverAny() then
                MO_Apply(false)
            end
        end)
    end
end
SetMOEvaluate(MO_Evaluate)

local function MO_HookFrame(widget)
    if not widget or _moHooked[widget] then
        return
    end
    _moHooked[widget] = true
    widget:HookScript("OnEnter", function()
        if _moActive then
            MO_CancelHide()
            MO_Apply(true)
        end
    end)
    widget:HookScript("OnLeave", function()
        if _moActive then
            MO_Evaluate()
        end
    end)
end

-- Rebuild the managed-button list from profile + hide state, hook minimap/buttons
-- (once), set initial alpha. Called at the end of every layout so it stays current.
local function MO_Refresh(p)
    wipe(_moButtons)
    local heb = (p and p.hideExtraBtns) or {}
    if p and p.mouseoverExtraBtns then
        if _greatVaultBtn and not heb.greatVault then
            _moButtons[#_moButtons + 1] = _greatVaultBtn
        end
        if _customIndicators.friends and not heb.friendsOnline then
            _moButtons[#_moButtons + 1] = _customIndicators.friends
        end
        if _portalBtn and not heb.portals then
            _moButtons[#_moButtons + 1] = _portalBtn
        end
        if flyoutToggle and not heb.groupButton then
            _moButtons[#_moButtons + 1] = flyoutToggle
        end
        -- Ungrouped addon buttons count as extra buttons for this setting too.
        for _, button in ipairs(cachedAddonButtons) do
            if _addonVisible[button] ~= false and IsUngrouped(button) then
                _moButtons[#_moButtons + 1] = button
            end
        end
    end
    _moActive = (#_moButtons > 0)
    if _moActive then
        MO_HookFrame(Minimap)
        for i = 1, #_moButtons do
            MO_HookFrame(_moButtons[i])
        end
        MO_Evaluate()
    else
        MO_CancelHide()
        -- Restore full alpha (harmless on buttons hidden by hideExtraBtns).
        if _greatVaultBtn then
            _greatVaultBtn:SetAlpha(1)
        end
        if _customIndicators.friends then
            _customIndicators.friends:SetAlpha(1)
        end
        if _portalBtn then
            _portalBtn:SetAlpha(1)
        end
        if flyoutToggle then
            flyoutToggle:SetAlpha(1)
        end
        -- Restore ungrouped addon buttons we may have dimmed.
        for _, button in ipairs(cachedAddonButtons) do
            if IsUngrouped(button) then
                button:SetAlpha(1)
            end
        end
    end
end

local MAIL_CORNER_POINTS = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

-- Stock styles and Forever Square: dress one of OUR row buttons (and, under
-- Classic WoW UI, the indicators) as the stock round minimap
-- button: a 31px button with the 53px ring-border texture hung from its
-- top-left exactly as addon buttons hang it (its shadow falls bottom-right).
-- Measured on that texture at the 53px draw size, the gold band's inner
-- opening spans x 7..26 and y 7..25 -- centre 16.6,-16.2 from the button's
-- top-left, with the band's inner shadow on the top-left -- so the dark disc
-- and the icon are centred THERE, not at the addon-button icon slot (7,-6 at
-- 17px), which is drawn for icons with transparent margins; ours are
-- full-bleed art. The icon is clipped round by a mask so a square icon reads
-- as a round button. `crop` trims an atlas icon to its centre fraction (the
-- group toggle's plate art carries a small glyph) through the sheet file and
-- coords, since SetTexCoord on an atlas samples garbage. Extra args are the
-- button's own icon textures; the CUI black box hides. Created once,
-- re-applied per pass. Our own buttons only (keys are written on the button).
function SKIN._ClassicRingButton(button, crop, ...)
    if not button then
        return
    end
    button:SetSize(31, 31)
    if button._bg then
        button._bg:Hide()
    end
    local ring = button._classicRing
    if not ring then
        ring = button:CreateTexture(nil, "OVERLAY")
        ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        ring:SetSize(53, 53)
        ring:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        button._classicRing = ring
        local disc = button:CreateTexture(nil, "BACKGROUND")
        disc:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        disc:SetSize(20, 20)
        disc:SetPoint("CENTER", button, "TOPLEFT", 16.6, -16.2)
        button._classicDisc = disc
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        highlight:SetBlendMode("ADD")
        highlight:SetAllPoints(button)
        button._classicHL = highlight
        -- Icon 16px inside the 20px disc: a sliver of disc shows round the
        -- icon, as on the stock round buttons, rather than the art running
        -- under the band (which reads as zoomed in).
        local mask = button:CreateMaskTexture()
        mask:SetTexture(
            "Interface\\AddOns\\CludesUI\\media\\portraits\\circle_mask.tga",
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        mask:SetSize(16, 16)
        mask:SetPoint("CENTER", button, "TOPLEFT", 16.6, -16.2)
        button._classicMask = mask
    end
    ring:Show()
    button._classicDisc:Show()
    button._classicHL:Show()
    for i = 1, select("#", ...) do
        local texture = select(i, ...)
        if texture then
            texture:ClearAllPoints()
            texture:SetSize(16, 16)
            texture:SetPoint("CENTER", button, "TOPLEFT", 16.6, -16.2)
            if crop then
                -- GetAtlas is nil once the sheet file is on the texture, so
                -- this runs once per texture.
                local atlas = texture:GetAtlas()
                local details = atlas and C_Texture.GetAtlasInfo(atlas)
                if details and (details.file or details.filename) then
                    local region, g, b, a = texture:GetVertexColor()
                    texture:SetTexture(details.file or details.filename)
                    local l, rt, t, bt =
                        details.leftTexCoord,
                        details.rightTexCoord,
                        details.topTexCoord,
                        details.bottomTexCoord
                    local dw, dh = (rt - l) * crop, (bt - t) * crop
                    texture:SetTexCoord(l + dw, rt - dw, t + dh, bt - dh)
                    texture:SetVertexColor(region, g, b, a)
                end
            end
            if not texture._classicMasked then
                texture:AddMaskTexture(button._classicMask)
                texture._classicMasked = true
            end
        end
    end
end

-- A ring button's ring inside its box: the left, top, right and bottom
-- insets (the button's units) from the box's edges to the ring's opaque
-- edge. The ring is the minimap tracking-border file (64px, its opaque ring
-- in columns 4..36 and rows 3..36) hung from the button's top-left at any
-- size, as the common minimap-button library (50 or 53px), our own button
-- and EBS._ClassicRingButton (53px) hang it. Found once per button (our
-- dress's ring, else the button's region drawing that file; a weak-keyed
-- record of ours, never a key on the button); a button without one, or with
-- its ring hung elsewhere, reads as its box.
SKIN._ringTex = setmetatable({}, { __mode = "k" })
function SKIN._RingInsets(button)
    local ring = button._classicRing
    if not ring then
        ring = SKIN._ringTex[button]
        if ring == nil then
            ring = false
            for i = 1, select("#", button:GetRegions()) do
                local region = select(i, button:GetRegions())
                if region:IsObjectType("Texture") then
                    local texture = region:GetTexture()
                    if
                        (region.GetTextureFileID and region:GetTextureFileID()) == 136430
                        or (type(texture) == "string" and texture:find("MiniMap%-TrackingBorder"))
                    then
                        ring = region
                        break
                    end
                end
            end
            SKIN._ringTex[button] = ring
        end
    end
    if not ring or not ring:IsShown() then
        return 0, 0, 0, 0
    end
    local pt, rel, rp, posX, posY = ring:GetPoint(1)
    if pt ~= "TOPLEFT" or rp ~= "TOPLEFT" or rel ~= button then
        return 0, 0, 0, 0
    end
    local wid, hgt = ring:GetWidth(), ring:GetHeight()
    posX, posY = posX or 0, -(posY or 0)
    return posX + wid * 4 / 64,
        posY + hgt * 3 / 64,
        button:GetWidth() - posX - wid * 37 / 64,
        button:GetHeight() - posY - hgt * 37 / 64
end

-- Takes the ring dress off a button the pass renders bare (a mail pinned to a
-- corner): ring, disc and highlight hide and the round mask comes off the
-- textures given, so the pass's own geometry shows unclipped. Re-dressing
-- puts everything back; a button never dressed is left alone.
function SKIN._ClassicRingUndress(button, ...)
    local ring = button and button._classicRing
    if not ring then
        return
    end
    ring:Hide()
    button._classicDisc:Hide()
    button._classicHL:Hide()
    for i = 1, select("#", ...) do
        local texture = select(i, ...)
        if texture and texture._classicMasked then
            texture:RemoveMaskTexture(button._classicMask)
            texture._classicMasked = nil
        end
    end
end

-- Forever Square's element row: an indicator (tracking, calendar, mail,
-- crafting order) in the button row's ring dress, its icon at its atlas
-- aspect and scale on the ring's 16px icon height, nudged as the indicator
-- pass nudges it (INDICATOR_ATLAS_*), so the art sits as it does in the box.
-- Re-applied per pass: the indicator pass sizes the icon for the box first.
function SKIN._RingIndicator(button)
    local iconTex, up = button._icon, button._upAtlas
    SKIN._ClassicRingButton(button, nil, iconTex)
    local ratio = iconTex and up and INDICATOR_ATLAS_RATIO[up]
    if ratio then
        local s = INDICATOR_ATLAS_SCALE[up] or 1
        local off = INDICATOR_ATLAS_OFFSET[button._indicatorKey]
        iconTex:SetSize(16 * ratio * s, 16 * s)
        iconTex:ClearAllPoints()
        iconTex:SetPoint(
            "CENTER",
            button,
            "TOPLEFT",
            16.6 + (off and off[1] or 0),
            -16.2 + (off and off[2] or 0)
        )
    end
end

-- WoW Forever's minimap header: its bar art (EBS._ApplyBlizzMinimapChrome)
-- and its own button arts, each plate and glyph in one atlas.
SKIN.FV_HEADER_ATLAS = "ui-hud-minimap-header-button"
SKIN.FV_HEADER_BUTTONS = {
    tracking = { "ui-hud-minimap-tracking-button", 23, 23 },
    calendar = { "ui-hud-minimap-calendar-button", 23, 23 },
    mail = { "ui-hud-minimap-mail-icon", 32, 24 },
}
-- An indicator (tracking, calendar, mail) in its WoW Forever header art at
-- the header's scale `s` (map size / 198): the art fills the button in place
-- of the icon's own (every hover state reads the same atlas, so the swaps go
-- quiet) and an additive copy lights it on mouseover at Blizzard's 0.1, as
-- the stock header buttons light. Re-applied per pass: the indicator pass
-- sizes the button for the CUI row and the day rollover repaints the
-- calendar's icon before it. Our own buttons only.
function SKIN._FvHeaderIndicator(button, key, s)
    local art = button and SKIN.FV_HEADER_BUTTONS[key]
    if not art then
        return
    end
    local atlas = art[1]
    button:SetSize(art[2] * s, art[3] * s)
    if button._bg then
        button._bg:Hide()
    end
    button._upAtlas, button._overAtlas, button._downAtlas = atlas, atlas, atlas
    local iconTex = button._icon
    iconTex:ClearAllPoints()
    iconTex:SetAllPoints(button)
    iconTex:SetAtlas(atlas)
    local highlight = button._fvHeaderHL
    if not highlight then
        highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetBlendMode("ADD")
        highlight:SetAllPoints(button)
        highlight:SetAlpha(0.1)
        button._fvHeaderHL = highlight
    end
    highlight:SetAtlas(atlas)
end

local function LayoutIndicatorFrames(minimap, p, circleMode)
    local flvl = minimap:GetFrameLevel() + 10
    local mapAnchor = GetFFD(minimap).layoutFrame or minimap
    -- The rows' anchor: the map, or Forever Square's outer frame edge.
    local rowAnchor = (SKIN._fvSquare and GetFFD(minimap).fvOuter) or mapAnchor

    -- Build our custom buttons once, hide Blizzard originals
    BuildCustomIndicators(minimap)
    HideBlizzardIndicators()
    SyncIndicatorVisibility()

    local ci = _customIndicators
    local sz = GetInteractableBtnSize()
    local showBg = p.btnBackgrounds ~= false
    -- Mail Position: "button" = element row; a corner pins it there (as Omnium Folio).
    local mailCorner = MAIL_CORNER_POINTS[p.mailPosition] and p.mailPosition or nil
    -- Resize buttons and update icon aspect ratios
    local inset = 3
    local avail = sz - inset * 2
    local blizzHdr = SKIN._MinimapBlizz() and GetFFD(minimap).blizzHeader or nil
    local function ResizeIndicator(button)
        if not button then
            return
        end
        button:SetSize(sz, sz)
        -- Stock styles: no CUI black box behind the indicators.
        if button._bg then
            button._bg:SetShown(showBg and not blizzHdr)
        end
        local ratio = button._upAtlas and INDICATOR_ATLAS_RATIO[button._upAtlas]
        if ratio and button._icon then
            local scale = INDICATOR_ATLAS_SCALE[button._upAtlas] or 1
            local iconW, iconH
            if ratio >= 1 then
                iconW = avail * scale
                iconH = (avail / ratio) * scale
            else
                iconH = avail * scale
                iconW = (avail * ratio) * scale
            end
            button._icon:ClearAllPoints()
            button._icon:SetSize(iconW, iconH)
            local off = button._indicatorKey and INDICATOR_ATLAS_OFFSET[button._indicatorKey]
            button._icon:SetPoint("CENTER", button, "CENTER", off and off[1] or 0, off and off[2] or 0)
        end
    end
    ResizeIndicator(ci.tracking)
    -- Update calendar day if it changed (midnight rollover)
    if ci.calendar then
        local today = tonumber(date("%d")) or 1
        if ci.calendar._calDay ~= today then
            ci.calendar._calDay = today
            local prefixText = "UI-HUD-Calendar-" .. today
            ci.calendar._upAtlas = prefixText .. "-Up"
            ci.calendar._overAtlas = prefixText .. "-Mouseover"
            ci.calendar._downAtlas = prefixText .. "-Down"
            if ci.calendar._icon then
                ci.calendar._icon:SetAtlas(ci.calendar._upAtlas)
            end
        end
    end
    ResizeIndicator(ci.calendar)
    ResizeIndicator(ci.mail)
    ResizeIndicator(ci.crafting)
    -- Corner-pinned mail renders bare: no black box, just the mail icon
    if mailCorner and ci.mail and ci.mail._bg then
        ci.mail._bg:SetShown(false)
    end
    if flyoutToggle then
        flyoutToggle:SetSize(sz, sz)
        if flyoutToggle._bg then
            flyoutToggle._bg:SetShown(showBg)
        end
        -- Reset to base anchor so free-move offsets don't accumulate across relayouts
        local rowMode = GetBtnRowMode(p)
        local rowBaseX, rowBaseY = GetRowBase(rowMode, p.btnRowDistance)
        local resES = minimap:GetEffectiveScale()
        flyoutToggle:ClearAllPoints()
        flyoutToggle:SetPoint(
            rowMode.point,
            rowAnchor,
            rowMode.rel,
            Pix.SnapForES(rowBaseX, resES),
            Pix.SnapForES(rowBaseY, resES)
        )
    end

    if ci.calendar then
        ci.calendar:SetShown(not p.hideGameTime)
    end

    -- Difficulty flag (instance type/size indicator)
    local diffFrame = (MinimapCluster and MinimapCluster.InstanceDifficulty) or _G.MiniMapInstanceDifficulty
    if diffFrame then
        diffFrame:SetParent(minimap)
        diffFrame:SetFrameLevel(flvl + 2)
        diffFrame:ClearAllPoints()
        diffFrame:SetPoint("TOPRIGHT", mapAnchor, "TOPRIGHT", 2, 1)
        -- Text mode overrides Show Blizzard Elements: the flag is always suppressed.
        -- Alpha leaves the hit region live, so a suppressed flag still answers mouseover
        -- with Blizzard's difficulty tooltip at the top-right corner.
        local suppressed = p.hideRaidDifficulty or p.diffTextEnabled
        diffFrame:SetAlpha(suppressed and 0 or 1)
        diffFrame:EnableMouseMotion(not suppressed)
        if diffFrame.Guild then
            diffFrame.Guild:EnableMouseMotion(not suppressed)
        end
    end
    if not minimap.Layout then
        minimap.Layout = function() end
    end

    if blizzHdr then
        -- Stock styles: placement around the top bar -- tracking on its left,
        -- calendar on its right, crafting stacked under the tracking button,
        -- the difficulty flag hung under the bar's right end. Blizzard Style
        -- stacks the mail under the tracking button too; Classic WoW UI puts
        -- it at the vanilla spot on the ring's upper right, below the flag,
        -- and dresses the row's indicators as the vanilla round buttons (a
        -- corner-pinned mail renders bare). WoW Forever's bar takes its own
        -- header buttons (EBS._FvHeaderIndicator) where its client puts them:
        -- tracking centred 8.5 past the bar's left end, the calendar
        -- overlapping its right end by 4, the mail icon under its left end
        -- (a corner mail keeps that art). Corner mail and every hide toggle
        -- still apply.
        local classic = SKIN._MinimapClassic()
        local cs = (p.mapSize or 140) / 140
        local fvBar = blizzHdr._fvBar
        local hs = (p.mapSize or 140) / 198
        if ci.tracking and not p.hideTrackingButton then
            if classic then
                SKIN._ClassicRingButton(ci.tracking, nil, ci.tracking._icon)
            elseif fvBar then
                SKIN._FvHeaderIndicator(ci.tracking, "tracking", hs)
            elseif not ci.tracking._blizzRing then
                -- The stock tracking button sits on a round plate (our own button, so the
                -- texture lives on it directly).
                local ring = ci.tracking:CreateTexture(nil, "BACKGROUND")
                ring:SetAllPoints(ci.tracking)
                SKIN._StockAtlas(ring, "ui-hud-minimap-button")
                ci.tracking._blizzRing = ring
            end
            ci.tracking:ClearAllPoints()
            if fvBar then
                ci.tracking:SetPoint("CENTER", blizzHdr, "LEFT", -8.5 * hs, 0)
            else
                ci.tracking:SetPoint("RIGHT", blizzHdr, "LEFT", -2, 0)
            end
            ci.tracking:Show()
        elseif ci.tracking then
            ci.tracking:Hide()
        end
        if ci.calendar and not p.hideGameTime then
            -- Stock: the clock hangs from the bar's top-right corner.
            ci.calendar:ClearAllPoints()
            if fvBar then
                SKIN._FvHeaderIndicator(ci.calendar, "calendar", hs)
                ci.calendar:SetPoint("TOPLEFT", blizzHdr, "TOPRIGHT", -4 * hs, 0)
            else
                ci.calendar:SetPoint("TOPLEFT", blizzHdr, "TOPRIGHT", 1, 0)
            end
        end
        local under = (ci.tracking and ci.tracking:IsShown() and not fvBar) and ci.tracking or nil
        if ci.mail and ci.mail:IsShown() then
            if fvBar then
                SKIN._FvHeaderIndicator(ci.mail, "mail", hs)
            end
            if classic then
                if mailCorner then
                    SKIN._ClassicRingUndress(ci.mail, ci.mail._icon)
                else
                    SKIN._ClassicRingButton(ci.mail, nil, ci.mail._icon)
                    -- The dress squares its icon; the envelope keeps its atlas
                    -- aspect at the ring's 16px icon height.
                    local ratio = ci.mail._upAtlas and INDICATOR_ATLAS_RATIO[ci.mail._upAtlas]
                    if ratio and ci.mail._icon then
                        ci.mail._icon:SetSize(16 * ratio, 16)
                    end
                end
            end
            ci.mail:ClearAllPoints()
            if mailCorner then
                ci.mail:SetPoint(mailCorner, mapAnchor, mailCorner, p.mailOffsetX or 0, p.mailOffsetY or 0)
            elseif classic then
                -- The vanilla mail frame: 33px, its TOPRIGHT 24,-37 off the map's
                -- top-right corner, ring border hung from its top-left; placed by
                -- that top-left, 6 lower than the vanilla spot so the difficulty
                -- flag hanging under the banner's right end clears the ring.
                ci.mail:SetPoint("TOPLEFT", minimap, "TOPRIGHT", -9 * cs, -43 * cs)
            elseif fvBar then
                ci.mail:SetPoint("TOPLEFT", blizzHdr, "BOTTOMLEFT", 0, 0)
                under = ci.mail
            else
                if under then
                    ci.mail:SetPoint("TOP", under, "BOTTOM", 0, 0)
                else
                    ci.mail:SetPoint("RIGHT", blizzHdr, "LEFT", -2, 0)
                end
                under = ci.mail
            end
        end
        if ci.crafting and ci.crafting:IsShown() then
            if classic then
                SKIN._ClassicRingButton(ci.crafting, nil, ci.crafting._icon)
            end
            ci.crafting:ClearAllPoints()
            if under then
                ci.crafting:SetPoint("TOP", under, "BOTTOM", 0, 0)
            else
                ci.crafting:SetPoint("RIGHT", blizzHdr, "LEFT", -2, 0)
            end
        end
        if diffFrame then
            diffFrame:ClearAllPoints()
            diffFrame:SetPoint("TOPRIGHT", blizzHdr, "BOTTOMRIGHT", 0, 1)
        end
    elseif circleMode then
        -- Circle layout: horizontal row growing left from the clock. Each element chains
        -- to the previous shown one; a hidden element is skipped, since anchoring to a
        -- frame that was never positioned leaves the whole chain undrawn.
        local leftAnchor = (clockBg and clockBg:IsShown()) and clockBg or nil
        local function PlaceLeft(button)
            button:ClearAllPoints()
            if leftAnchor then
                button:SetPoint("RIGHT", leftAnchor, "LEFT", 0, 0)
            else
                button:SetPoint("TOP", mapAnchor, "TOP", -20, -3)
            end
            leftAnchor = button
        end

        if ci.tracking and not p.hideTrackingButton then
            PlaceLeft(ci.tracking)
            ci.tracking:Show()
        elseif ci.tracking then
            ci.tracking:Hide()
        end

        if ci.calendar and not p.hideGameTime then
            ci.calendar:ClearAllPoints()
            if clockBg and clockBg:IsShown() then
                ci.calendar:SetPoint("LEFT", clockBg, "RIGHT", 0, 0)
            else
                ci.calendar:SetPoint("TOP", mapAnchor, "TOP", 20, -3)
            end
        end

        if ci.mail and ci.mail:IsShown() then
            if mailCorner then
                ci.mail:ClearAllPoints()
                ci.mail:SetPoint(mailCorner, mapAnchor, mailCorner, p.mailOffsetX or 0, p.mailOffsetY or 0)
            else
                PlaceLeft(ci.mail)
            end
        end

        if ci.crafting and ci.crafting:IsShown() then
            PlaceLeft(ci.crafting)
        end
    else
        -- Square layout: element row (corner + growth from Element Row Position), same running-total
        -- placement as the button row below using each element's real width so horizontal rows stay flush despite varying atlas ratios.
        local rowMode = GetElementRowMode(p)
        local baseX, baseY = GetRowBase(rowMode, p.elementRowDistance)
        local elES = minimap:GetEffectiveScale()
        local elPx = Pix.perfect / elES
        local elGap = Pix.SnapForES(p.elementRowSpacing or 0, elES)
        local elX = Pix.SnapForES(baseX, elES)
        local elY = Pix.SnapForES(baseY, elES)
        -- Forever Square: the row wears the button row's ring dress
        -- (EBS._RingIndicator), each ring rather than its box placed on the
        -- row (EBS._RingInsets), EBS.FV_RING_GAP apart.
        local fvRings = SKIN._fvSquare
        local ringGap = fvRings and Pix.SnapForES(SKIN.FV_RING_GAP, elES) or 0
        local ptRight = rowMode.point:find("RIGHT") ~= nil
        local ptTop = rowMode.point:find("TOP") ~= nil
        local function PlaceElement(button)
            if fvRings then
                SKIN._RingIndicator(button)
            end
            local adv = (rowMode.dirX ~= 0) and button:GetWidth() or button:GetHeight()
            local ox, oy = 0, 0
            if fvRings then
                local l, t, region, b = SKIN._RingInsets(button)
                adv = adv - ((rowMode.dirX ~= 0) and (l + region) or (t + b)) + ringGap
                ox = Pix.SnapForES(ptRight and region or -l, elES)
                oy = Pix.SnapForES(ptTop and t or -b, elES)
            end
            button:ClearAllPoints()
            button:SetPoint(rowMode.point, rowAnchor, rowMode.rel, elX + ox, elY + oy)
            adv = math.floor(adv / elPx + 0.001) * elPx + elGap
            elX = elX + adv * rowMode.dirX
            elY = elY + adv * rowMode.dirY
        end

        if ci.tracking and not p.hideTrackingButton then
            PlaceElement(ci.tracking)
            ci.tracking:Show()
        elseif ci.tracking then
            ci.tracking:Hide()
        end

        if ci.calendar and not p.hideGameTime then
            PlaceElement(ci.calendar)
        end

        if ci.mail and ci.mail:IsShown() then
            if mailCorner then
                -- A corner mail renders bare, its ring dress off.
                if fvRings then
                    SKIN._ClassicRingUndress(ci.mail, ci.mail._icon)
                end
                ci.mail:ClearAllPoints()
                ci.mail:SetPoint(mailCorner, mapAnchor, mailCorner, p.mailOffsetX or 0, p.mailOffsetY or 0)
            else
                PlaceElement(ci.mail)
            end
        end

        if ci.crafting and ci.crafting:IsShown() then
            PlaceElement(ci.crafting)
        end
    end

    -- Ungrouped buttons along the button row; the flyout toggle is its first slot.
    if flyoutToggle then
        local rowMode = GetBtnRowMode(p)
        local rowBaseX, rowBaseY = GetRowBase(rowMode, p.btnRowDistance)
        local ungroupBtnSize = GetInteractableBtnSize()
        -- Running-total placement: cursor starts at snapped Distance from Map, advances per button
        -- by its size FLOORED to whole physical pixels (rounding up opens hairline seams; flooring can only overlap-flush) plus snapped Icon Spacing.
        local rowES = minimap:GetEffectiveScale()
        local rowPx = Pix.perfect / rowES
        local rowGap = Pix.SnapForES(p.btnRowSpacing or 0, rowES)
        local rowX = Pix.SnapForES(rowBaseX, rowES)
        local rowY = Pix.SnapForES(rowBaseY, rowES)
        -- Round maps: the row follows the ring instead of the square's edge,
        -- starting at the row's corner and walking round in its growth
        -- direction; Icon Spacing becomes the arc gap. Stock styles centre each
        -- button on the circle just outside the map, as the stock map's addon
        -- buttons do (the stock addon-button radius, 5px scaled with the map,
        -- plus Distance from Map). The CludesUI look's circle centres each
        -- button on the map's edge, half over the map so it reads as attached,
        -- Distance from Map further out, with a base gap between buttons. With
        -- Free Move on it keeps the straight row: saved offsets are relative to
        -- the row slots they were dragged from.
        local arcR, arcT, arcDir
        local arcGap = 0
        if blizzHdr or (circleMode and not p.freeMoveBtns) then
            local mapW = minimap:GetWidth() or 140
            if blizzHdr then
                arcR = mapW / 2 + 5 * (mapW / 198) + (p.btnRowDistance or 0)
            else
                local edge = (p.shape == "textured_circle") and 2 or (p.borderSize or 1)
                arcR = mapW / 2 + edge + (p.btnRowDistance or 0)
                arcGap = Pix.SnapForES(4, rowES)
            end
            arcT = math.rad(rowMode.arc or 225)
            arcDir = rowMode.arcDir or -1
        end
        -- Stock styles and Forever Square: every button on the row wears the
        -- round minimap-button look -- ours dressed by EBS._ClassicRingButton,
        -- addon buttons in their own native dress (the common minimap-button
        -- library draws exactly that look). The CludesUI look keeps its own
        -- dress, its circle too.
        local ringDress = (blizzHdr or SKIN._fvSquare) and true or false
        -- Forever Square's straight row places each ring, not its box: a ring
        -- sits off-centre in its button and at its own size (EBS._RingInsets),
        -- so each ring's edge lands on the row's edge and the next ring
        -- follows EBS.FV_RING_GAP past it.
        local fvRings = ringDress and SKIN._fvSquare
        local ringGap = fvRings and Pix.SnapForES(SKIN.FV_RING_GAP, rowES) or 0
        local ptRight = rowMode.point:find("RIGHT") ~= nil
        local ptTop = rowMode.point:find("TOP") ~= nil
        local function PlaceRowButton(button)
            local adv = (rowMode.dirX ~= 0) and button:GetWidth() or button:GetHeight()
            local ox, oy = 0, 0
            if fvRings then
                local l, t, region, b = SKIN._RingInsets(button)
                adv = adv - ((rowMode.dirX ~= 0) and (l + region) or (t + b)) + ringGap
                ox = Pix.SnapForES(ptRight and region or -l, rowES)
                oy = Pix.SnapForES(ptTop and t or -b, rowES)
            end
            adv = math.floor(adv / rowPx + 0.001) * rowPx + rowGap
            if arcR then
                SKIN._ArcPoint(button, minimap, arcR, arcT, rowES)
                arcT = arcT + arcDir * (adv + arcGap) / arcR
            else
                button:SetPoint(rowMode.point, rowAnchor, rowMode.rel, rowX + ox, rowY + oy)
                rowX = rowX + adv * rowMode.dirX
                rowY = rowY + adv * rowMode.dirY
            end
        end
        if ringDress then
            SKIN._ClassicRingButton(
                flyoutToggle,
                0.12,
                flyoutToggle._norm,
                flyoutToggle._pushed,
                flyoutToggle._hl
            )
        end
        -- WoW Forever: a row starting at the bottom-left corner starts past
        -- the queue eye Action Bars parks there (half the 45px eye, the gap
        -- and half a ring button, as arc length).
        if arcR and CludesUI.IS_FOREVER and rowMode.arc == 225 then
            local ab = CludesUI._ModuleNS.CludesUIActionBars
            if ab and ab.AB_ForeverEyeParked() then
                arcT = arcT + arcDir * (22.5 + rowGap + arcGap + flyoutToggle:GetWidth() / 2) / arcR
            end
        end
        flyoutToggle:ClearAllPoints()
        local flyoutVisible = flyoutToggle:IsShown()
        if flyoutVisible then
            PlaceRowButton(flyoutToggle)
        elseif arcR then
            SKIN._ArcPoint(flyoutToggle, minimap, arcR, arcT, rowES)
        else
            flyoutToggle:SetPoint(rowMode.point, rowAnchor, rowMode.rel, rowX, rowY)
        end
        local mp = SKIN.db and SKIN.db.profile.minimap
        local ungrouped = {}
        for _, button in ipairs(cachedAddonButtons) do
            if _addonVisible[button] ~= false and IsUngrouped(button) then
                local name = button:GetName()
                local sequence = mp and mp.ungroupedButtons and mp.ungroupedButtons[name] or 999
                if type(sequence) == "boolean" then
                    sequence = 999
                end
                ungrouped[#ungrouped + 1] = { btn = button, order = sequence }
            end
        end
        table.sort(ungrouped, function(a, b)
            return a.order < b.order
        end)
        for index, record in ipairs(ungrouped) do
            local button = record.btn
            -- Restore from flyout if needed
            if flyoutSavedParents[button] then
                if GetFFD(button).flyoutRing then
                    GetFFD(button).flyoutRing:Hide()
                end
                if button.SetFixedFrameStrata then
                    button:SetFixedFrameStrata(false)
                end
                if button.SetFixedFrameLevel then
                    button:SetFixedFrameLevel(false)
                end
                flyoutSavedParents[button] = nil
            end
            button:SetParent(minimap)
            button:SetFrameLevel(minimap:GetFrameLevel() + 11)
            button:ClearAllPoints()
            -- Black boxes only on the CUI look; Blizzard Style keeps the button's
            -- own dress (the common library dress is the stock round minimap
            -- button) at its native size, restored BEFORE placement so the row
            -- advances by the size the button really draws at.
            local rowBoxes = showBg and not ringDress
            if rowBoxes then
                -- Strip BEFORE resize so the snapshot captures the real native size.
                StripButtonDecorations(button)
                button:SetSize(ungroupBtnSize, ungroupBtnSize)
            else
                RestoreButtonDecorations(button)
            end
            PlaceRowButton(button)
            button:SetMovable(false)
            button:RegisterForDrag()
            button:SetScript("OnDragStart", nil)
            button:SetScript("OnDragStop", nil)
            if rowBoxes then
                local iconTex = button.icon or button.Icon
                if not iconTex then
                    for _, regionFrame in ipairs({ button:GetRegions() }) do
                        if
                            regionFrame:IsObjectType("Texture")
                            and regionFrame:IsShown()
                            and regionFrame:GetAlpha() > 0
                            and not IsJunkTexture(regionFrame)
                            and regionFrame ~= GetFFD(button).ungroupBg
                        then
                            iconTex = regionFrame
                            break
                        end
                    end
                end
                if iconTex then
                    iconTex:ClearAllPoints()
                    iconTex:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
                    iconTex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
                    pcall(iconTex.SetTexCoord, iconTex, 0.05, 0.95, 0.05, 0.95)
                    -- Foreign icon: no global SetTexCoord snap hook, so disable once.
                    if CludesUI.PP then
                        CludesUI.PP.DisablePixelSnap(iconTex)
                    end
                end
                SKIN._ShowAddonBtnBox(button)
                if button._ungroupRing then
                    button._ungroupRing:Hide()
                end
            else
                -- No boxes: native appearance (restored above), our overlays hidden. Do NOT
                -- override button size -- native ring textures have fixed anchors correct only at the original size.
                if GetFFD(button).ungroupBg then
                    GetFFD(button).ungroupBg:Hide()
                end
                if button._ungroupRing then
                    button._ungroupRing:Hide()
                end
            end
            SKIN._suppressVisTrack = true
            button:SetAlpha(1)
            button:Show()
            SKIN._suppressVisTrack = false
        end

        local heb = p.hideExtraBtns or {}

        -- Extra buttons: Great Vault, Friends Online, M+ Portals. Visibility from
        -- hideExtraBtns; row order from extraBtnOrder (drag-to-reorder in options; nil = fallback list below).
        local function PlaceExtraButton(key)
            if key == "greatVault" then
                if _greatVaultBtn then
                    if heb.greatVault then
                        _greatVaultBtn:Hide()
                    else
                        SizeGreatVaultBtn(_greatVaultBtn, showBg)
                        if ringDress then
                            SKIN._ClassicRingButton(_greatVaultBtn, nil, _greatVaultBtn._whole)
                        end
                        _greatVaultBtn:SetParent(minimap)
                        _greatVaultBtn:SetFrameLevel(minimap:GetFrameLevel() + 11)
                        _greatVaultBtn:ClearAllPoints()
                        PlaceRowButton(_greatVaultBtn)
                        _greatVaultBtn:Show()
                    end
                end
            elseif key == "friendsOnline" then
                if ci.friends then
                    if heb.friendsOnline then
                        ci.friends:Hide()
                    else
                        ci.friends:SetSize(sz, sz)
                        if ci.friends._bg then
                            ci.friends._bg:SetShown(showBg)
                        end
                        if ringDress then
                            SKIN._ClassicRingButton(ci.friends, nil, ci.friends._icon)
                        end
                        ci.friends:SetParent(minimap)
                        ci.friends:SetFrameLevel(minimap:GetFrameLevel() + 11)
                        ci.friends:ClearAllPoints()
                        PlaceRowButton(ci.friends)
                        ci.friends:Show()
                    end
                end
            elseif key == "portals" then
                if _portalBtn then
                    if heb.portals then
                        _portalBtn:Hide()
                    else
                        SizePortalBtn(_portalBtn, showBg)
                        if ringDress then
                            SKIN._ClassicRingButton(_portalBtn, nil, _portalBtn._icon)
                        end
                        _portalBtn:SetParent(minimap)
                        _portalBtn:SetFrameLevel(minimap:GetFrameLevel() + 11)
                        _portalBtn:ClearAllPoints()
                        PlaceRowButton(_portalBtn)
                        _portalBtn:Show()
                    end
                end
            end
        end
        local placedExtra = {}
        if type(p.extraBtnOrder) == "table" then
            for _, key in ipairs(p.extraBtnOrder) do
                if not placedExtra[key] then
                    placedExtra[key] = true
                    PlaceExtraButton(key)
                end
            end
        end
        -- Safety net: place anything a stale saved order is missing
        for _, key in ipairs({ "greatVault", "friendsOnline", "portals" }) do
            if not placedExtra[key] then
                placedExtra[key] = true
                PlaceExtraButton(key)
            end
        end

        -- Flyout toggle (CUI group button for addon icons)
        if flyoutToggle and heb.groupButton then
            flyoutToggle:Hide()
        end
    end

    -- Free Move: hook shift+drag on all indicator buttons and apply saved offsets
    local heb = p.hideExtraBtns or {}
    local freeMove = p.freeMoveBtns
    local fmTargets = {}
    if ci.tracking and not p.hideTrackingButton then
        fmTargets[#fmTargets + 1] = ci.tracking
    end
    if ci.calendar and not p.hideGameTime then
        fmTargets[#fmTargets + 1] = ci.calendar
    end
    if ci.mail then
        fmTargets[#fmTargets + 1] = ci.mail
    end
    if ci.crafting then
        fmTargets[#fmTargets + 1] = ci.crafting
    end
    if flyoutToggle then
        fmTargets[#fmTargets + 1] = flyoutToggle
    end
    if _greatVaultBtn and not heb.greatVault then
        fmTargets[#fmTargets + 1] = _greatVaultBtn
    end
    if _portalBtn and not heb.portals then
        fmTargets[#fmTargets + 1] = _portalBtn
    end
    if ci.friends and not heb.friendsOnline then
        fmTargets[#fmTargets + 1] = ci.friends
    end
    -- Include ungrouped addon buttons
    for _, button in ipairs(cachedAddonButtons) do
        if _addonVisible[button] ~= false and IsUngrouped(button) then
            fmTargets[#fmTargets + 1] = button
        end
    end
    for _, widget in ipairs(fmTargets) do
        EnableFreeMove(widget)
        if freeMove then
            ApplyBtnOffset(widget)
        end
    end

    SyncTrackingHotspot(p)

    -- After layout so the managed-button list and alpha reflect the shown state.
    MO_Refresh(p)
end

-------------------------------------------------------------------------------
-- Snapshot Blizzard minimap size and position on first install: native size and
-- center so we start matching the user's Edit Mode setup. Once per profile.
-------------------------------------------------------------------------------
local function CaptureBlizzardMinimap()
    local minimap = Minimap
    if not minimap then
        return
    end
    local p = SKIN.db.profile.minimap
    if p._capturedOnce then
        return
    end

    local uiScale = UIParent:GetEffectiveScale()
    local mScale = minimap:GetEffectiveScale()
    local ratio = mScale / uiScale

    -- Capture size (use the larger dimension to keep it square)
    local wid, hgt = minimap:GetWidth(), minimap:GetHeight()
    if wid and wid > 10 then
        local sz = math.floor(math.max(wid, hgt) * ratio + 0.5)
        p.mapSize = sz
    end

    -- Capture center position as CENTER/CENTER offset from UIParent
    local cx, cy = minimap:GetCenter()
    if cx and cy then
        local uiW, uiH = UIParent:GetSize()
        cx = cx * ratio
        cy = cy * ratio
        p.position = {
            point = "CENTER",
            relPoint = "CENTER",
            x = cx - (uiW / 2),
            y = cy - (uiH / 2),
        }
    end

    -- WoW Forever: a new profile starts with our button, then the error-list
    -- addon's (its LibDBIcon name; an absent button costs nothing), on the
    -- button row out of the group. A first-capture seed, not a default: a
    -- player's regroup clears the entry for good.
    if CludesUI.IS_FOREVER == true then
        local ug = p.ungroupedButtons
        if type(ug) ~= "table" then
            ug = {}
            p.ungroupedButtons = ug
        end
        if next(ug) == nil then
            ug.LibDBIcon10_CludesUI = 1
            ug.LibDBIcon10_BugSack = 2
        end
    end

    p._capturedOnce = true
end

-- Expansion landing page button ("Omnium Folio"): kept off the addon-button flyout (see
-- flyoutBlacklist), anchored to a minimap corner and raised above it. We never force it
-- visible -- Blizzard decides when it appears, so we never display a stale old-expansion
-- button; our setting only HIDES it. Plain (non-secure) button, so SetParent/SetPoint are safe.
local _omniumFolioHooked = false

-- True while a replacement button (FOLIO_REPLACEMENT_BUTTONS) is on screen. Our
-- RefreshButton nudge below would undo the replacement's hide -- it re-Shows Blizzard's
-- button, which the replacement never re-hides (believing it already did), leaving both
-- visible. So while a replacement is in charge we keep hands off; it re-Shows Blizzard's itself if disabled, and our Show hook re-applies our state then.
local function IsFolioReplacedByAddOn()
    for _, name in ipairs(FOLIO_REPLACEMENT_BUTTONS) do
        -- IsShown presence check: if anything squats one of these global names with a non-frame value, treat it as no replacement instead of erroring.
        local b = _G[name]
        if b and b.IsShown and b:IsShown() then
            return true
        end
    end
    return false
end

-- Folio mode with legacy fallback: pre-dropdown data carries showOmniumFolio (default ON; only false is ever stored).
local function GetOmniumFolioMode(mp)
    -- No expansion landing page on WoW Forever: every folio path reads "never".
    if CludesUI.IS_FOREVER then
        return "never"
    end
    if not mp then
        return "always"
    end
    if mp.omniumFolioMode then
        return mp.omniumFolioMode
    end
    if mp.showOmniumFolio == false then
        return "never"
    end
    return "always"
end

-- Re-entrancy guard: PositionOmniumFolio calls the SetParent/SetScale/SetPoint we hook below, so our own writes must not recurse.
local _omniumFolioApplying = false
local function PositionOmniumFolio(button)
    if not button or not Minimap then
        return
    end
    local mp = SKIN.db and SKIN.db.profile and SKIN.db.profile.minimap
    if not mp then
        return
    end
    _omniumFolioApplying = true
    if button:GetParent() ~= Minimap then
        button:SetParent(Minimap)
    end
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 10)
    button:SetScale(mp.omniumFolioScale or 0.75)
    button:ClearAllPoints()
    -- Anchor the button's chosen corner to the minimap's same corner; X/Y nudge from there (positive X = right, positive Y = up, regardless of corner).
    local corner = mp.omniumFolioCorner or "BOTTOMLEFT"
    if SKIN._MinimapBlizz() then
        -- Stock styles: the stock spot on the ring (the button's centre
        -- 84 left and 63.5 below the map centre at the stock 198px map: the
        -- backdrop's TOPLEFT -3,-150 for the 53px button), mirrored to the chosen
        -- corner and scaled with the map. Anchor offsets are in the button's own
        -- scale, so the map units divide by it; the nudges stay as they were.
        local mapW = Minimap:GetWidth() or (mp.mapSize or 140)
        local s = (mapW / 198) / (button:GetScale() or 1)
        local cx = (corner == "BOTTOMRIGHT" or corner == "TOPRIGHT") and 84 or -84
        local cy = (corner == "TOPLEFT" or corner == "TOPRIGHT") and 63.5 or -63.5
        button:SetPoint(
            "CENTER",
            Minimap,
            "CENTER",
            cx * s + (mp.omniumFolioX or 0),
            cy * s + (mp.omniumFolioY or 0)
        )
    else
        button:SetPoint(
            corner,
            GetFFD(Minimap).layoutFrame or Minimap,
            corner,
            mp.omniumFolioX or 0,
            mp.omniumFolioY or 0
        )
    end
    _omniumFolioApplying = false
end

-- True while the cursor is over the map region OR the hover-mode folio (which can
-- overhang the minimap rect at reduced scale). The 4px slop matters: OnEnter fires on
-- the engine's exact-pixel focus test, while this Lua-side test rounds cursor coords
-- through effective scale and can round the other way sub-pixel at the boundary
-- (resolution/scale dependent, which is why it repros on some machines only); the
-- expanded rect ensures "engine entered" implies "this test passes", so the exit watcher never fires early.
function SKIN._HoverStillOver(minimap)
    local hoverFrame = GetFFD(minimap).pingBlocker or GetFFD(minimap).layoutFrame or minimap
    if hoverFrame:IsMouseOver(4, -4, -4, 4) then
        return true
    end
    local b = _G.ExpansionLandingPageMinimapButton
    if b and b:IsShown() and b:IsMouseOver(4, -4, -4, 4) then
        return true
    end
    return false
end

-- Immediate hide for map-region hover elements (zoom buttons, hover-mode folio,
-- coordinates): fired from the minimap's OnLeave on a real exit (in step with
-- Blizzard's own zoom fade), and from the exit watcher for exits across a child
-- element (those never fire a second minimap OnLeave). Cancels the watcher.
function SKIN._HVHideNow()
    local minimap = Minimap
    if not minimap then
        return
    end
    local ffd = GetFFD(minimap)
    if ffd.hvWatcher then
        ffd.hvWatcher:Cancel()
        ffd.hvWatcher = nil
    end
    local zi, zo = minimap.ZoomIn, minimap.ZoomOut
    if zi then
        zi:Hide()
    end
    if zo then
        zo:Hide()
    end
    local m2 = SKIN.db and SKIN.db.profile.minimap
    if m2 then
        if GetOmniumFolioMode(m2) == "hover" then
            local b = _G.ExpansionLandingPageMinimapButton
            if b then
                b:Hide()
            end
        end
        if GetCoordsModePos(m2) == "hover" then
            if coordFrame then
                coordFrame:Hide()
            end
            if coordTicker then
                coordTicker:Hide()
            end
        end
    end
    -- Extra buttons hide in the SAME instant: the 0.12s deferral only bridges gap-
    -- crossings between stack frames mid-hover, and a true region exit has nothing to
    -- bridge. If the cursor is still over part of the stack (row button, open flyouts,
    -- friends tooltip), OverAny keeps it shown via the normal path.
    if _moActive then
        if MO_OverAny() then
            if MO_Evaluate then
                MO_Evaluate()
            end
        else
            MO_CancelHide()
            MO_Apply(false)
        end
    end
end

-- Central map-region hover reveal (EBS field, see CludesUIMinimap.lua). Fired from the
-- minimap's OnEnter/OnLeave and from over-map children's OnEnter (clock, FPS text,
-- corner mail, folio): no-ops off-region, reveals zoom buttons and hover-mode folio,
-- and runs one self-cancelling watcher (minimap's FFD data) that hides them once the
-- cursor truly leaves -- including exits FROM a child, which never fire a 2nd OnLeave.
function SKIN._HVRevealMapHover()
    local minimap = Minimap
    if not minimap then
        return
    end
    local ffd = GetFFD(minimap)
    if not ffd.active then
        return
    end
    if not SKIN._HoverStillOver(minimap) then
        -- OnEnter is SINGLE-SHOT per hover: if this check fails at the boundary, nothing
        -- re-attempts the reveal for the whole hover (slow entries dwelt there and
        -- failed consistently). Retry briefly and self-cancel when clearly gone.
        if not ffd.hvRetry then
            local tries = 0
            ffd.hvRetry = C_Timer.NewTicker(0.1, function()
                tries = tries + 1
                if SKIN._HoverStillOver(minimap) then
                    ffd.hvRetry:Cancel()
                    ffd.hvRetry = nil
                    SKIN._HVRevealMapHover()
                elseif tries >= 8 then
                    ffd.hvRetry:Cancel()
                    ffd.hvRetry = nil
                end
            end)
        end
        return
    end
    if ffd.hvRetry then
        ffd.hvRetry:Cancel()
        ffd.hvRetry = nil
    end
    local mp = SKIN.db and SKIN.db.profile.minimap
    if not mp then
        return
    end
    local function raiseZoom()
        local zi, zo = minimap.ZoomIn, minimap.ZoomOut
        if UIFrameFadeRemoveFrame then
            if zi then
                UIFrameFadeRemoveFrame(zi)
            end
            if zo then
                UIFrameFadeRemoveFrame(zo)
            end
        end
        if zi then
            zi:SetAlpha(1)
            zi:Show()
        end
        if zo then
            zo:SetAlpha(1)
            zo:Show()
        end
    end
    if not mp.hideZoomButtons then
        raiseZoom()
    end
    if GetOmniumFolioMode(mp) == "hover" and not IsFolioReplacedByAddOn() then
        local b = _G.ExpansionLandingPageMinimapButton
        if b then
            PositionOmniumFolio(b)
            if not b:IsShown() and b.RefreshButton then
                b:RefreshButton(true)
            end
        end
    end
    if GetCoordsModePos(mp) == "hover" then
        if coordFrame then
            coordFrame:Show()
        end
        if coordTicker then
            coordTicker:Show()
        end
        UpdateCoords()
    end
    -- Same "map region hovered" notion; MO_Evaluate self-guards when the feature is off.
    if MO_Evaluate then
        MO_Evaluate()
    end
    if ffd.hvWatcher then
        return
    end
    ffd.hvWatcher = C_Timer.NewTicker(0.2, function()
        if SKIN._HoverStillOver(minimap) then
            -- Still over the map: keep defeating Blizzard's fader (an intervening
            -- OnLeave may have re-armed it).
            local m2 = SKIN.db and SKIN.db.profile.minimap
            if m2 and not m2.hideZoomButtons then
                raiseZoom()
            end
            return
        end
        SKIN._HVHideNow()
    end)
end

local function ApplyOmniumFolio()
    -- No expansion landing page on WoW Forever: the button is left to
    -- Blizzard entirely (its own refresh path errors there), no hooks either.
    if CludesUI.IS_FOREVER then
        return
    end
    local button = _G.ExpansionLandingPageMinimapButton
    if not button or not Minimap then
        return
    end
    local mp = SKIN.db and SKIN.db.profile and SKIN.db.profile.minimap
    if not mp then
        return
    end

    -- One-time persistent hooks: Blizzard re-anchors/rescales/reparents this button
    -- after loading screens (RefreshButton, edit-mode relayout) often WITHOUT calling
    -- Show(), so a Show-only hook would let it drift to the default TOPLEFT anchor
    -- inside the alpha-0 MinimapCluster (wrong position or missing button until
    -- /reload) -- re-assert on every parent/point/scale change too.
    if not _omniumFolioHooked then
        _omniumFolioHooked = true
        local function reassert(self)
            if _omniumFolioApplying then
                return
            end
            local m = SKIN.db and SKIN.db.profile and SKIN.db.profile.minimap
            if not m then
                return
            end
            local mode = GetOmniumFolioMode(m)
            -- Boundary-tolerant like the reveal path: RefreshButton Hide()/Show()s the button, and a raw IsMouseOver could veto that Show at the exact edge.
            if
                mode == "never"
                or IsFolioReplacedByAddOn()
                or (mode == "hover" and not (Minimap and SKIN._HoverStillOver(Minimap)))
            then
                self:Hide()
            else
                PositionOmniumFolio(self)
            end
        end
        hooksecurefunc(button, "Show", reassert)
        hooksecurefunc(button, "SetParent", reassert)
        hooksecurefunc(button, "SetPoint", reassert)
        hooksecurefunc(button, "SetScale", reassert)
        -- Hovering the folio counts as hovering the map region (also covers entering the map directly onto it).
        button:HookScript("OnEnter", function()
            SKIN._HVRevealMapHover()
        end)
    end

    local mode = GetOmniumFolioMode(mp)
    if mode == "never" then
        button:Hide()
        return
    end
    -- Replacement on screen: leave Blizzard's alone rather than resurrecting it beside the replacement (see IsFolioReplacedByAddOn).
    if IsFolioReplacedByAddOn() then
        return
    end
    if mode == "hover" and not Minimap:IsMouseOver() then
        button:Hide()
        return
    end
    -- Enabled: position/raise, then ensure visible. Blizzard Shows this button when the
    -- ExpansionLandingPage overlay applies, but "OverlayChanged" can fire before the
    -- button registers its callback (after /reload and zoning), leaving it at its XML
    -- hidden default. When hidden, nudge Blizzard's own RefreshButton instead of a raw
    -- Show(): it re-runs the real show/hide decision (hides when ShouldShow is false or
    -- in an empty Garrison) and repaints the current expansion icon, so this never forces
    -- a stale button unlike a raw Show(). Its Show() re-fires our reposition hook.
    PositionOmniumFolio(button)
    if not button:IsShown() and button.RefreshButton then
        button:RefreshButton(true)
    end
end

Inner.ApplyOmniumFolio, Inner.CaptureBlizzardMinimap = ApplyOmniumFolio, CaptureBlizzardMinimap
Inner.LayoutIndicatorFrames = LayoutIndicatorFrames
Inner.SyncIndicatorVisibility = SyncIndicatorVisibility
Inner.broken = false
