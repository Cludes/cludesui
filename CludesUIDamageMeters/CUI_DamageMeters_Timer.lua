if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_DamageMeters_Timer.lua
--
--  The standalone combat timer, the show/hide hotkey and the timer's
--  unlock element.
--  Reads the earlier Damage Meters files through ns and ns._dmInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._dmInternals
-- CludesUIDamageMeters.lua or an earlier CUI_DamageMeters_*.lua file
-- failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local CUI = CludesUI

local DB, MAX_WINDOWS, _windows = Inner.DB, Inner.MAX_WINDOWS, Inner._windows
local GetCurrentViewDuration, FormatTimer = Inner.GetCurrentViewDuration, Inner.FormatTimer
local FormatTimerDecimal, GetAccentRGB = Inner.FormatTimerDecimal, Inner.GetAccentRGB
local SetDMFont, SetSATimer = Inner.SetDMFont, Inner.SetSATimer
local SetUpdateSATimerText = Inner.SetUpdateSATimerText

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._dmInternals, which hands the value to every copy.
local _inCombat = Inner._inCombat
Inner.inCombatSetters[#Inner.inCombatSetters + 1] = function(val) _inCombat = val end
local _needsFinalRefresh = Inner._needsFinalRefresh
Inner.needsFinalRefreshSetters[#Inner.needsFinalRefreshSetters + 1] = function(val) _needsFinalRefresh = val end
local _ttFrame
Inner.ttFrameSetters[#Inner.ttFrameSetters + 1] = function(val) _ttFrame = val end

-- Assigned below and handed to the earlier files (SetUpdateSATimerText).
local UpdateSATimerText

-- Standalone Combat Timer
local _saTimer -- frame reference
local _saTimerFS -- fontstring
Inner.saTimerSetters[#Inner.saTimerSetters + 1] = function(val) _saTimer = val end
local _saTimerBG -- backdrop texture
local _saTimerBorder -- PP border child frame
local _saTimerPreview = false
local _saTimerLive = false -- last live/idle state seen (drives OOC desaturation)

local function GetSATimerPreviewText() return DB().standaloneTimerDecimal and "11:37.0" or "11:37" end

-- Per-user font override for the standalone timer only (standaloneTimerFont,
-- a dropdown key: "__global"/nil = follow the Damage Meters module font).
local function GetSATimerFontOverride()
    local key = DB().standaloneTimerFont
    if key and key ~= "__global" and CludesUI and CludesUI.ResolveFontName then
        local filePath = CludesUI.ResolveFontName(key)
        if filePath and filePath ~= "" then return filePath end
    end
    return nil
end

local function GetSATimerColor()
    local conf = DB()
    if conf.standaloneTimerUseAccent then return GetAccentRGB() end
    local color = conf.standaloneTimerColor
    return color and color.r or 1, color and color.g or 1, color and color.b or 1
end

local function ApplySATimerColor()
    if not _saTimerFS then return end
    local conf = DB()
    local red, green, blue = GetSATimerColor()
    if conf.standaloneTimerDesatOOC and not (_inCombat or _needsFinalRefresh) then
        -- Luminance gray: desaturation keeps the configured color's brightness
        local l = 0.299 * red + 0.587 * green + 0.114 * blue
        red, green, blue = l, l, l
    end
    _saTimerFS:SetTextColor(red, green, blue, 1)
end

local function ApplySATimerStyle()
    if not _saTimer or not _saTimerFS then return end
    local conf = DB()
    _saTimer:SetFrameStrata(conf.standaloneTimerStrata or "HIGH")

    local outline = conf.standaloneTimerOutline or "INHERIT"
    local outlineFlags
    if outline == "NONE" then
        outlineFlags = ""
    elseif outline == "THICKOUTLINE" then
        outlineFlags = "THICKOUTLINE"
    elseif outline == "INHERIT" then
        outlineFlags = nil
    else
        outlineFlags = "OUTLINE"
    end
    SetDMFont(_saTimerFS, conf.standaloneTimerSize or 26, outlineFlags, GetSATimerFontOverride())
    ApplySATimerColor()

    local previousText = _saTimerFS:GetText()
    -- Auto-size worst case must cover the decimal form, or live tenths clip.
    _saTimerFS:SetText(conf.standaloneTimerDecimal and "99:99.9" or "99:99")
    local autoWidth = (_saTimerFS:GetStringWidth() or 30) + 4
    local autoHeight = (_saTimerFS:GetStringHeight() or 14) + 4
    _saTimerFS:SetText(previousText)
    _saTimer:SetSize(
        conf.standaloneTimerWidth and math.max(40, conf.standaloneTimerWidth) or autoWidth,
        conf.standaloneTimerHeight and math.max(20, conf.standaloneTimerHeight) or autoHeight
    )

    if _saTimerBG then
        local color = conf.standaloneTimerBackgroundColor or { r = 0, g = 0, b = 0, a = 0 }
        _saTimerBG:SetColorTexture(color.r or 0, color.g or 0, color.b or 0, color.a or 0)
    end

    if _saTimerBorder then
        local Pix = CludesUI and CludesUI.PP
        local color = conf.standaloneTimerBorderColor or { r = 0, g = 0, b = 0, a = 1 }
        local borderSize = math.max(0, math.floor((conf.standaloneTimerBorderSize or 0) + 0.5))
        if borderSize > 0 and Pix and Pix.UpdateBorder then
            Pix.UpdateBorder(
                _saTimerBorder,
                borderSize,
                color.r or 0,
                color.g or 0,
                color.b or 0,
                color.a == nil and 1 or color.a
            )
            _saTimerBorder:Show()
        else
            _saTimerBorder:Hide()
        end
    end

    _saTimerFS:ClearAllPoints()
    local borderSize = conf.standaloneTimerBorderSize or 0
    local inset = borderSize > 0 and borderSize + 3 or 0
    _saTimerFS:SetPoint("LEFT", _saTimer, "LEFT", inset, 0)
    _saTimerFS:SetPoint("RIGHT", _saTimer, "RIGHT", -inset, 0)
    -- Preserve the old binary left-align preference until the user chooses
    -- a value in the new three-way alignment control.
    local textAlign = conf.standaloneTimerTextAlign
    if not textAlign then
        local anchor = conf.standaloneTimerAnchor or "free"
        if anchor == "free" then
            textAlign = conf.standaloneTimerAlignLeft and "LEFT" or "RIGHT"
        else
            textAlign = (anchor == "topleft" or anchor == "bottomleft") and "LEFT" or "RIGHT"
        end
    end
    _saTimerFS:SetJustifyH(textAlign)
end

-- Decimal display: API duration is whole seconds, so tenths are derived from a GetTime() anchor
-- reset on every API value change -- display-only smoothing clamped inside the current second; the API stays authoritative and re-anchors each tick, so it cannot drift.
local _saDecBase, _saDecAnchor = nil, 0

UpdateSATimerText = function()
    if not _saTimer or not _saTimerFS then return end
    local conf = DB()
    if not conf.standaloneTimer then return end
    -- The timer runs on its own ticker and re-shows itself every 0.1s, so the hotkey
    -- toggle has to be checked here rather than hiding the frame from the outside
    if
        mod._toggleHidden
        and conf.toggleIncludeTimer
        and not mod._optionsOpen
        and not CUI._unlockActive
        and not _saTimerPreview
    then
        if _saTimer:IsShown() then _saTimer:Hide() end
        return
    end
    -- Same source as the window's Current timer so the two can never disagree. Visible while
    -- combat is live (or polling a group fight we're not in); out of combat it hides unless Show Out of Combat keeps it up (last fight's frozen duration).
    local live = _inCombat or _needsFinalRefresh
    if live or conf.standaloneTimerShowOOC then
        if not _saTimer:IsShown() and not _saTimerPreview then _saTimer:Show() end
        if live or not _saTimerPreview then
            local dur = GetCurrentViewDuration()
            if conf.standaloneTimerDecimal then
                if live then
                    if dur ~= _saDecBase then
                        _saDecBase = dur
                        _saDecAnchor = GetTime()
                    end
                    local frac = GetTime() - _saDecAnchor
                    if frac > 0.9 then frac = 0.9 end
                    dur = dur + frac
                end
                _saTimerFS:SetText(FormatTimerDecimal(dur))
            else
                _saTimerFS:SetText(FormatTimer(dur))
            end
        end
    else
        if not _saTimerPreview then
            if _saTimer:IsShown() then _saTimer:Hide() end
            _saTimerFS:SetText("")
        end
    end
    if _saTimerLive ~= live then
        _saTimerLive = live
        ApplySATimerColor()
    end
end
SetUpdateSATimerText(UpdateSATimerText)

local function PlaceTimer()
    if not _saTimer then return end
    local conf = DB()
    -- While the timer has a live unlock anchor link, the anchor system owns
    -- its position -- do not fight it.
    if CUI.IsUnlockAnchored and CUI.IsUnlockAnchored("EDM_CombatTimer") then return end
    local anchor = conf.standaloneTimerAnchor or "free"

    _saTimer:ClearAllPoints()

    if anchor == "free" then
        -- Lock Position & Disable Click: click-through and immovable; the
        -- shift+drag lane only exists while unlocked. Our own frame, so the
        -- direct mouse-state writes are safe.
        local locked = conf.standaloneTimerLocked == true
        _saTimer:SetMovable(not locked)
        _saTimer:EnableMouse(not locked)
        if _saTimer.EnableMouseMotion then _saTimer:EnableMouseMotion(not locked) end
        local place = conf.standaloneTimerPos
        if place and place.point then
            _saTimer:SetPoint(
                place.point,
                UIParent,
                place.relPoint or place.point,
                place.x or 0,
                place.y or 0
            )
        elseif place and place.x and place.y then
            -- Legacy drag format: TOPLEFT offset from UIParent's BOTTOMLEFT
            _saTimer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", place.x, place.y)
        else
            local W1 = _windows[1]
            if W1 and W1.frame then
                _saTimer:SetPoint("BOTTOMRIGHT", W1.frame, "TOPRIGHT", 0, 5)
            else
                _saTimer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
        return
    end

    _saTimer:SetMovable(false)
    _saTimer:EnableMouse(false)
    if _saTimer.EnableMouseMotion then _saTimer:EnableMouseMotion(false) end

    -- Find the highest (max top) and lowest (min bottom) window
    local topWin, botWin
    local maxTop, minBot = -math.huge, math.huge
    for _, wid in ipairs(_windows) do
        if wid.frame and wid.frame:IsShown() then
            local t = wid.frame:GetTop()
            local b = wid.frame:GetBottom()
            if t and t > maxTop then
                maxTop = t
                topWin = wid
            end
            if b and b < minBot then
                minBot = b
                botWin = wid
            end
        end
    end

    local isTop = anchor == "topleft" or anchor == "topright"
    local isLeft = anchor == "topleft" or anchor == "bottomleft"
    local ref = isTop and topWin or botWin

    if not ref or not ref.frame then
        _saTimer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end

    if isTop and isLeft then
        _saTimer:SetPoint("BOTTOMLEFT", ref.frame, "TOPLEFT", 0, 0)
    elseif isTop then
        _saTimer:SetPoint("BOTTOMRIGHT", ref.frame, "TOPRIGHT", 0, 0)
    elseif isLeft then
        _saTimer:SetPoint("TOPLEFT", ref.frame, "BOTTOMLEFT", 0, 0)
    else
        _saTimer:SetPoint("TOPRIGHT", ref.frame, "BOTTOMRIGHT", 0, 0)
    end
end

-- Styles, places and hides the standalone timer as it is built (combat state then
-- decides whether it shows); a profile swap runs it again on the kept timer.
local function SetupSATimer()
    _saTimer:SetMovable(true)
    _saTimer:EnableMouse(true)
    ApplySATimerStyle()
    _saTimerFS:SetText("0:00")

    PlaceTimer()

    _saTimer:Hide() -- starts hidden; combat state controls visibility
    UpdateSATimerText() -- Show Out of Combat can bring it straight back up
end

local function CreateSATimer()
    if _saTimer then return end
    local conf = DB()

    SetSATimer(CreateFrame("Frame", "CludesUIDMStandaloneTimer", UIParent))
    _saTimer:SetSize(1, 1)
    _saTimer:SetClampedToScreen(true)
    _saTimer:SetFrameStrata("HIGH")
    _saTimer:SetScript("OnMouseDown", function(self, btnFrame)
        if btnFrame == "LeftButton" and IsShiftKeyDown() then
            local cfg = DB()
            -- Belt and braces: locked timers are click-through (EnableMouse
            -- off), so this handler should never fire while locked.
            if cfg.standaloneTimerLocked then return end
            if (cfg.standaloneTimerAnchor or "free") == "free" then self:StartMoving() end
        end
    end)
    _saTimer:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local cfg = DB()
        if (cfg.standaloneTimerAnchor or "free") == "free" then
            local leftX, topY = self:GetLeft(), self:GetTop()
            if leftX and topY then cfg.standaloneTimerPos = { x = leftX, y = topY } end
        end
    end)

    _saTimerBG = _saTimer:CreateTexture(nil, "BACKGROUND")
    _saTimerBG:SetAllPoints()

    _saTimerBorder = CreateFrame("Frame", nil, _saTimer)
    _saTimerBorder:SetAllPoints(_saTimer)
    _saTimerBorder:SetFrameLevel(_saTimer:GetFrameLevel() + 5)
    local Pix = CludesUI and CludesUI.PP
    if Pix and Pix.CreateBorder then Pix.CreateBorder(_saTimerBorder, 0, 0, 0, 1, 1) end

    _saTimerFS = _saTimer:CreateFontString(nil, "OVERLAY")
    SetupSATimer()
end

mod.ApplySATimer = function()
    local conf = DB()
    if conf.standaloneTimer then
        if not _saTimer then CreateSATimer() end
        ApplySATimerStyle()
        local prevText = _saTimerFS:GetText()
        PlaceTimer()
        if _saTimerPreview then
            _saTimerFS:SetText(GetSATimerPreviewText())
        else
            _saTimerFS:SetText(prevText or "0:00")
            UpdateSATimerText()
        end
    else
        if _saTimer then _saTimer:Hide() end
    end
end

mod.ShowSATimerPreview = function()
    if not _saTimer then CreateSATimer() end
    if not _saTimer then return end
    -- Show Out of Combat already keeps real data on screen (last segment duration, or 0:00) -- never clobber it with the preview value
    if DB().standaloneTimerShowOOC then
        UpdateSATimerText()
        return
    end
    _saTimerPreview = true
    _saTimerFS:SetText(GetSATimerPreviewText())
    _saTimer:Show()
end
mod.HideSATimerPreview = function()
    local wasPreview = _saTimerPreview
    _saTimerPreview = false
    if not _saTimer then return end
    local conf = DB()
    if conf.standaloneTimer and conf.standaloneTimerShowOOC then
        -- Show Out of Combat was enabled during this preview session: swap the preview value for the real one (last segment, or 0:00)
        if wasPreview then UpdateSATimerText() end
        return
    end
    if not _inCombat then _saTimer:Hide() end
end

-------------------------------------------------------------------------------
--  Show/hide all windows hotkey
-------------------------------------------------------------------------------

-- Re-applies the current toggle state to every frame it covers. Also used by the
-- options page when the Combat Timer / Spell History checkboxes change while the
-- toggle is already active, so the newly included element follows immediately.
-- includeSpellHistory is read here rather than inside ApplySpellHistory because that
-- entry point rebuilds the icon strip and the bar window unconditionally; with the
-- default (Spell History not covered) the hotkey would pay both rebuilds per press.
mod.ApplyDMToggleState = function(includeSpellHistory)
    -- The row tooltip is parented to UIParent, not to the window, so it would be
    -- left floating if the hotkey is pressed while hovering a row
    if mod._toggleHidden and _ttFrame then _ttFrame:Hide() end
    for _, wid in ipairs(_windows) do
        wid.UpdateVisibility()
    end
    if _saTimer then UpdateSATimerText() end
    if includeSpellHistory == nil then includeSpellHistory = DB().toggleIncludeSpellHistory end
    if includeSpellHistory and mod.ApplySpellHistory then mod.ApplySpellHistory() end
end

mod.ToggleDMWindows = function()
    mod._toggleHidden = not mod._toggleHidden
    mod.ApplyDMToggleState()
    -- The mouseover scan caches each target's isActive answer per visibility
    -- generation, so without a bump it keeps the pre-toggle answer and re-shows a
    -- hover-gated window on the next pass. Deferred by a frame the way the
    -- dispatcher defers its own events: this runs from a hardware keypress, and
    -- other modules' updaters have no business running in that context.
    if CUI.RequestVisibilityUpdate then C_Timer.After(0, CUI.RequestVisibilityUpdate) end
end

-- Both damage meter hotkeys live on override bindings, which are protected: a rebind
-- during combat has to wait for regen (pressing the key itself is a hardware click and
-- works in combat). UPDATE_BINDINGS matters too -- LoadBindings, which the settings
-- panel runs on cancel and on a binding-set switch, drops every override, so a
-- configured key would otherwise stay dead until the next profile change. Our own
-- writes raise that event as well, hence the short self-write window.
-- Zero cost with no key: the event is registered only while a key is laid down, and a
-- pass that finds nothing configured and nothing applied never touches the binding API.
do
    local kbFrame = CreateFrame("Frame")
    local selfWriteUntil = 0
    -- The key each button currently carries (nil = none). Tracked apart from the
    -- configured key so that clearing a key still gets its one ClearOverrideBindings,
    -- and so a key dropped by LoadBindings is re-laid from the configured value.
    local appliedReset, appliedToggle

    local function WantKey(key)
        if key == nil or key == "" then return nil end
        return key
    end

    mod.ApplyDMKeybinds = function()
        local cfg = DB()
        local wantReset, wantToggle = WantKey(cfg.resetDataKey), WantKey(cfg.toggleWindowsKey)
        if not wantReset and not wantToggle and not appliedReset and not appliedToggle then
            kbFrame:UnregisterEvent("UPDATE_BINDINGS")
            return
        end
        if InCombatLockdown() then
            mod.CombatQueue.Defer("DMKeybinds", mod.ApplyDMKeybinds)
            return
        end
        selfWriteUntil = GetTime() + 0.5
        local resetBtn = _G.CludesUIDMResetBindBtn
        if resetBtn then
            ClearOverrideBindings(resetBtn)
            if wantReset then SetOverrideBindingClick(resetBtn, true, wantReset, "CludesUIDMResetBindBtn") end
            appliedReset = wantReset
        end
        local toggleBtn = _G.CludesUIDMToggleBindBtn
        if toggleBtn then
            ClearOverrideBindings(toggleBtn)
            if wantToggle then
                SetOverrideBindingClick(toggleBtn, true, wantToggle, "CludesUIDMToggleBindBtn")
            end
            appliedToggle = wantToggle
        end
        if wantReset or wantToggle then
            kbFrame:RegisterEvent("UPDATE_BINDINGS")
        else
            kbFrame:UnregisterEvent("UPDATE_BINDINGS")
        end
    end

    kbFrame:SetScript("OnEvent", function(_, evt)
        -- Ours, echoing back: ignore, or we re-enter forever
        if evt == "UPDATE_BINDINGS" and GetTime() < selfWriteUntil then return end
        mod.ApplyDMKeybinds()
    end)
end

-- Accent color callback for standalone timer
CUI.RegAccent({
    type = "callback",
    fn = function()
        if not _saTimer or not _saTimerFS then return end
        local conf = DB()
        if conf.standaloneTimerUseAccent then ApplySATimerColor() end
    end,
})

-- Unlock-mode element for the standalone timer, built on demand by ns.RegisterDMUnlock (lives here since the closures need the _saTimer upvalues above). Sizes to its text and would shift children, so it may anchor TO elements but never serve as an anchor target.
mod.MakeSATimerUnlockElement = function(MK)
    return MK({
        key = "EDM_CombatTimer",
        label = "Combat Timer",
        group = "Damage Meters",
        order = 650 + MAX_WINDOWS + 1,
        noResize = true,
        noAnchorTarget = true,
        getFrame = function() return _saTimer end,
        getSize = function()
            if _saTimer then return _saTimer:GetWidth(), _saTimer:GetHeight() end
            return 60, 20
        end,
        isHidden = function() return not DB().standaloneTimer end,
        savePos = function(_, anchorPoint, relPoint, posX, posY)
            local conf = DB()
            conf.standaloneTimerPos =
                { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
            -- A manual unlock-mode move implies free placement: un-snap the window-anchor mode or RepositionSATimer would fight the drag
            if (conf.standaloneTimerAnchor or "free") ~= "free" then conf.standaloneTimerAnchor = "free" end
        end,
        loadPos = function()
            local place = DB().standaloneTimerPos
            if not place then return nil end
            if place.point then
                return { point = place.point, relPoint = place.relPoint, x = place.x, y = place.y }
            end
            if place.x and place.y then
                -- Legacy drag format: TOPLEFT offset from UIParent's BOTTOMLEFT
                return { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = place.x, y = place.y }
            end
            return nil
        end,
        clearPos = function() DB().standaloneTimerPos = nil end,
        applyPos = function() PlaceTimer() end,
    })
end

Inner.CreateSATimer, Inner.SetupSATimer = CreateSATimer, SetupSATimer
Inner.UpdateSATimerText = UpdateSATimerText
Inner.broken = false
