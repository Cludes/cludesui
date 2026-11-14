if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBars_Glows.lua
--
--  Proc glows, the glue to the shared glow engines, the assisted combat
--  highlight, the cooldown edge and countdown font hooks, and the misc and
--  checked button textures. Loads after the main file,
--  CUI_ActionBars_ButtonArt.lua and CUI_ActionBars_Range.lua and reads them
--  through ns only.
-------------------------------------------------------------------------------
local _, mod = ...

local ipairs, pairs, pcall = ipairs, pairs, pcall
local floor, min = math.floor, math.min
local wipe = wipe
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After
local Pix = CludesUI.PP
local EFD = mod.EFD

local ABAR, EAB_VTABLE, barButtons = mod.EAB, mod.EAB_VTABLE, mod.barButtons
local SHAPE_MASKS, SHAPE_BORDERS, SHAPE_BTN_EXPAND = mod.SHAPE_MASKS, mod.SHAPE_BORDERS, mod.SHAPE_BTN_EXPAND
local Inner = mod._internals
local BAR_CONFIG, buttonToBar, barBaseSize = Inner.BAR_CONFIG, Inner.buttonToBar, Inner.barBaseSize
local SHAPE_EDGE_SCALES = Inner.SHAPE_EDGE_SCALES
local GetButtonActionSlot, MaskFrameTextures = Inner.GetButtonActionSlot, Inner.MaskFrameTextures

-------------------------------------------------------------------------------
--  Custom Proc Glow (FlipBook-based, no LibCustomGlow)
--  Hooks Blizzard's SpellActivationAlert to reconfigure the FlipBook
--  textures/animations with user-selected glow styles.
-------------------------------------------------------------------------------

-- Loop glow types: the shared glow styles in their shared order (saved procGlowType
-- values are shared indices).
local LOOP_GLOW_TYPES = CludesUI.Glows.MakeView({ 1, 2, 3, 4, 5, 6, 7 }).list
mod.LOOP_GLOW_TYPES = LOOP_GLOW_TYPES

-- Proc start types: the initial burst animation
local PROC_START_TYPES = {
    { name = "Modern Blizzard Proc", atlas = "UI-HUD-ActionBar-Proc-Start-Flipbook" },
    { name = "Blue Proc", atlas = "RotationHelper-ProcStartBlue-Flipbook-2x" },
    { name = "Hide", hide = true },
}
mod.PROC_START_TYPES = PROC_START_TYPES

-------------------------------------------------------------------------------
--  Glow Engines provided by shared CludesUI_Glows.lua
-------------------------------------------------------------------------------
local _G_Glows = CludesUI.Glows
mod.Glows = _G_Glows

local function StopAllProceduralGlows(wrapper)
    _G_Glows.StopAllGlows(wrapper)
end

local _procState = { hooked = false, active = {} }

local function UpdateFlipbook(button)
    local regionFrame = button.SpellActivationAlert
    local fd = EFD(button)
    if regionFrame and fd.shapeMask and fd.shapeApplied and not EFD(regionFrame).shapeMasked then
        for _, texture in ipairs({ regionFrame:GetRegions() }) do
            if texture and texture.AddMaskTexture then
                pcall(texture.AddMaskTexture, texture, fd.shapeMask)
            end
        end
        EFD(regionFrame).shapeMasked = true
    end

    local p = ABAR.db and ABAR.db.profile
    if not p then
        return
    end

    -- Size from profile settings, not btn:GetWidth(): on initial login the
    -- frame may not be sized by LayoutBar yet and GetWidth returns the
    -- default 45. Replicates LayoutBar's shape expansion/cropped math so the
    -- ratio matches the actual rendered size.
    local _ufBtnW, _ufBtnH
    do
        local bk = fd.barKey
        if not bk then
            local bi = buttonToBar[button]
            if bi then
                bk = bi.barKey
            end
        end
        local resolved
        if bk and p.bars and p.bars[bk] then
            local s = p.bars[bk]
            local baseValue = barBaseSize[bk]
            local bW = baseValue and baseValue.w or 45
            local bH = baseValue and baseValue.h or 45
            local wid = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth or bW
            local hgt = (s.buttonHeight and s.buttonHeight > 0) and s.buttonHeight or bH
            local shape = mod.AB_LayoutShape(s)
            if shape ~= "none" and shape ~= "cropped" then
                wid = wid + SHAPE_BTN_EXPAND
                hgt = hgt + SHAPE_BTN_EXPAND
            end
            if shape == "cropped" then
                hgt = hgt * 0.80
            end
            _ufBtnW, _ufBtnH = wid, hgt
            resolved = true
        end
        if not resolved then
            _ufBtnW = button:GetWidth() or 45
            _ufBtnH = button:GetHeight() or 45
        end
    end

    if not p.procGlowEnabled then
        -- "Default" glow: use our glow library with Modern WoW Glow (#6)
        if not (fd.shapeMask and fd.shapeApplied) then
            if not fd.glowWrapper then
                local wrapper = CreateFrame("Frame", nil, button:GetParent() or button)
                wrapper:SetAllPoints(button)
                wrapper:SetAlpha(0)
                fd.glowWrapper = wrapper
            end
            local wrapper = fd.glowWrapper
            wrapper:SetFrameLevel(button:GetFrameLevel() + 10)
            _G_Glows.StopAllGlows(wrapper)
            wrapper:SetAlpha(1)
            wrapper:Show()
            _G_Glows.StartGlow(wrapper, 6, _ufBtnW, 1, 0.788, 0.137, nil, _ufBtnH)
            if regionFrame then
                regionFrame:SetAlpha(0)
            end
            fd.customizedFlipbook = true
            return
        end
    end

    -- Color mode: the class flag alone decides Class (legacy profiles and older
    -- spec overrides carry only the flag); the mode key tells Default from
    -- Custom. The options getter reads the same rule.
    local c = p.procGlowColor or { r = 1, g = 0.776, b = 0.376 }
    local cr, cg, cb = _G_Glows.ResolveColor(
        p.procGlowUseClassColor and "class" or (p.procGlowColorMode == "default" and "default" or "custom"),
        c.r,
        c.g,
        c.b
    )

    local loopIdx = p.procGlowType or 1
    if loopIdx < 1 or loopIdx > #LOOP_GLOW_TYPES then
        loopIdx = 1
    end
    -- Force Shape Glow for custom shapes regardless of user selection
    if fd.shapeMask and fd.shapeApplied then
        for si, record in ipairs(LOOP_GLOW_TYPES) do
            if record.shapeGlow then
                loopIdx = si
                break
            end
        end
    end
    local loopEntry = LOOP_GLOW_TYPES[loopIdx]
    -- Default mode (nil color): the drawn engines use the suite gold; FlipBooks
    -- keep the atlas's own untinted look.
    if
        cr == nil
        and (loopEntry.procedural or loopEntry.buttonGlow or loopEntry.autocast or loopEntry.shapeGlow)
    then
        local d = _G_Glows.DEFAULT_COLOR
        cr, cg, cb = d.r, d.g, d.b
    end

    if not fd.glowWrapper then
        local wrapper = CreateFrame("Frame", nil, button:GetParent() or button)
        wrapper:SetAllPoints(button)
        fd.glowWrapper = wrapper
    end
    local wrapper = fd.glowWrapper
    wrapper:SetFrameLevel(button:GetFrameLevel() + 10)

    local wfd = EFD(wrapper)
    if fd.shapeMask and fd.shapeApplied and fd.shapeMaskPath then
        if not wfd.ownMask then
            wfd.ownMask = wrapper:CreateMaskTexture()
        end
        wfd.ownMask:ClearAllPoints()
        Pix.Point(wfd.ownMask, "TOPLEFT", button, "TOPLEFT", 1, -1)
        Pix.Point(wfd.ownMask, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        wfd.ownMask:SetTexture(fd.shapeMaskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        wfd.ownMask:Show()
    elseif wfd.ownMask then
        wfd.ownMask:Hide()
    end

    if loopEntry.procedural or loopEntry.buttonGlow or loopEntry.autocast or loopEntry.shapeGlow then
        fd.customizedFlipbook = true
        -- Suppress Blizzard's native flipbook visuals (hide textures, not durations)
        if regionFrame then
            regionFrame:SetAlpha(0)
        end

        StopAllProceduralGlows(wrapper)
        wrapper:Show()

        local bW, bH = _ufBtnW, _ufBtnH

        if loopEntry.procedural then
            local N = p.procGlowLines or 8
            local th = p.procGlowThickness or 2
            local period = p.procGlowSpeed or 4
            local lineLen = floor((bW + bH) * (2 / N - 0.1))
            lineLen = min(lineLen, min(bW, bH))
            if lineLen < 1 then
                lineLen = 1
            end
            -- No fallback table per proc: an unset background color reads as black.
            local bgOn, bgc = p.procGlowBackground, p.procGlowBackgroundColor
            _G_Glows.StartProceduralAnts(
                wrapper,
                N,
                th,
                period,
                lineLen,
                cr,
                cg,
                cb,
                bW,
                bH,
                bgOn and (bgc and bgc.r or 0) or nil,
                bgOn and (bgc and bgc.g or 0) or nil,
                bgOn and (bgc and bgc.b or 0) or nil,
                bgOn and 1 or nil
            )
        elseif loopEntry.buttonGlow then
            _G_Glows.StartButtonGlow(wrapper, bW, cr, cg, cb, nil, bH)
        elseif loopEntry.autocast then
            _G_Glows.StartAutoCastShine(wrapper, bW, cr, cg, cb, 1.0, bH)
        elseif loopEntry.shapeGlow then
            local maskPath = fd.shapeMaskPath or SHAPE_MASKS[fd.shapeName or ""]
            local borderPath = SHAPE_BORDERS[fd.shapeName or ""]
            _G_Glows.StartShapeGlow(wrapper, min(bW, bH), cr, cg, cb, 1.20, {
                maskPath = maskPath,
                borderPath = borderPath,
                shapeMask = fd.shapeMask,
                anchorFrame = button,
            })
        end
        if wfd.ownMask then
            MaskFrameTextures(wrapper, wfd.ownMask)
        end
    else
        -- FlipBook styles render on our own wrapper (SetAllPoints on btn) so the
        -- glow matches button size with no scale math; Blizzard's is suppressed.
        fd.customizedFlipbook = true
        if regionFrame then
            regionFrame:SetAlpha(0)
        end

        _G_Glows.StopAllGlows(wrapper)
        wrapper:Show()
        _G_Glows.StartFlipBookGlow(wrapper, _ufBtnW, loopEntry, cr, cg, cb, _ufBtnH)
        if wfd.ownMask then
            MaskFrameTextures(wrapper, wfd.ownMask)
        end
    end

    if regionFrame and fd.shapeMask and fd.shapeApplied then
        MaskFrameTextures(regionFrame, fd.shapeMask)
        EFD(regionFrame).shapeMasked = true
    end
end

-- Resolve the spellID for a button.
-- Stored on _procState rather than as a file-level local.
_procState.GetButtonSpellID = function(button)
    local slotIndex = GetButtonActionSlot(button)
    if not slotIndex or not HasAction or not HasAction(slotIndex) then
        return nil
    end
    local actionType, ident, subType = GetActionInfo(slotIndex)
    if actionType == "spell" then
        return ident
    elseif actionType == "macro" then
        if subType == "spell" then
            return ident
        elseif subType == "item" then
            return nil
        end
        local macroName = GetActionText(slotIndex)
        local macroIndex = macroName and GetMacroIndexByName(macroName)
        if macroIndex and macroIndex > 0 then
            if GetMacroItem and GetMacroItem(macroIndex) then
                return nil
            end
            return GetMacroSpell(macroIndex)
        end
    end
    return nil
end

-- Proc glow via SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE events.
-- Loops all buttons to find matches by spellID.
function ABAR:HookProcGlow()
    if _procState.hooked then
        return
    end
    _procState.hooked = true

    -- Stock art (Blizzard or Classic): the native glow shows on its own.
    local function IsBlizzStyle()
        return mod.AB_Style() ~= "cui"
    end

    local function ShowGlow(button)
        _procState.active[button] = true
        UpdateFlipbook(button)
    end

    local function HideGlow(button)
        _procState.active[button] = nil
        local gw = EFD(button).glowWrapper
        if gw then
            StopAllProceduralGlows(gw)
            gw:Hide()
        end
        local sa = button.SpellActivationAlert
        if sa then
            sa:SetAlpha(1)
            sa:Hide()
        end
    end
    local GetButtonSpellID = _procState.GetButtonSpellID

    -- IsSpellOverlayed ground truth for one button: check ONLY the button's
    -- current spell. A base/override fallback causes false positives (Tempest
    -- glowing because its base Lightning Bolt was overlayed by Stormkeeper).
    local function UpdateOverlayGlow(button)
        local spellId = GetButtonSpellID(button)
        if not spellId then
            if _procState.active[button] then
                HideGlow(button)
            end
            return
        end
        local ISO = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
        if not ISO then
            return
        end
        if ISO(spellId) then
            ShowGlow(button)
        elseif _procState.active[button] then
            HideGlow(button)
        end
    end

    local glowFrame = mod.TakeShell()
    glowFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    glowFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    glowFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    glowFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    glowFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    glowFrame:RegisterEvent("SPELL_UPDATE_ICON")
    -- Deferred full re-scan, coalesced: mouseover-conditional macros
    -- re-resolve on every mouseover flip and fire ACTIONBAR_SLOT_CHANGED
    -- storms (dozens/sec sweeping nameplates). One pending scan covers it.
    local _glowRescanPending = false
    local _glowLastScan = 0
    local function GlowRescan()
        _glowRescanPending = false
        _glowLastScan = GetTime()
        -- Clear glows that no longer match, add new ones
        for button in pairs(_procState.active) do
            local ident = GetButtonSpellID(button)
            if not ident or not C_SpellActivationOverlay.IsSpellOverlayed(ident) then
                HideGlow(button)
            end
        end
        local blizz = IsBlizzStyle()
        for _, details in ipairs(BAR_CONFIG) do
            -- Dormant bars skip the IsSpellOverlayed walk; their show edge
            -- queues a rescan (ApplyBarDormancy), which runs after the
            -- dormancy map flipped, so a revealed bar is covered here.
            local buttons = (not mod._eabBarDormant[details.key]) and barButtons[details.key] or nil
            if buttons then
                for _, button in ipairs(buttons) do
                    if button and (EFD(button).squared or blizz) and not _procState.active[button] then
                        UpdateOverlayGlow(button)
                    end
                end
            end
        end
    end
    -- Bar-reveal reconcile (ApplyBarDormancy show edge): a proc that fired
    -- while the bar was dormant was skipped by the GLOW_SHOW scan; queue the
    -- same coalesced rescan the slot/page edges use to restore it.
    mod._eabQueueGlowRescan = function()
        if not _glowRescanPending then
            _glowRescanPending = true
            local elapsed = GetTime() - _glowLastScan
            C_Timer_After(elapsed >= 0.25 and 0 or (0.25 - elapsed), GlowRescan)
        end
    end
    glowFrame:SetScript("OnEvent", function(_, evt, arg1)
        if
            evt == "ACTIONBAR_SLOT_CHANGED"
            or evt == "ACTIONBAR_PAGE_CHANGED"
            or evt == "UPDATE_BONUS_ACTIONBAR"
            or evt == "SPELL_UPDATE_ICON"
        then
            -- Defer the re-scan: paging may not have finished when the event
            -- fires, so slot->spell mappings are stale. Min 0.25s between
            -- scans on top of coalescing -- the assist slot's re-stamp storm
            -- (SLOT_CHANGED + SPELL_UPDATE_ICON) would otherwise queue a full
            -- IsSpellOverlayed walk every frame. An isolated event still
            -- scans next frame; proc edges stay instant via GLOW_SHOW/HIDE below.
            if not _glowRescanPending then
                _glowRescanPending = true
                local elapsed = GetTime() - _glowLastScan
                C_Timer_After(elapsed >= 0.25 and 0 or (0.25 - elapsed), GlowRescan)
            end
            return
        end
        local isShow = (evt == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        if not isShow then
            -- HIDE: only need to check buttons with active glows (small set).
            -- Collect first to avoid modifying _procState.active during iteration.
            local toHide
            for button in pairs(_procState.active) do
                local ident = GetButtonSpellID(button)
                if
                    (ident and ident == arg1)
                    or not ident
                    or not C_SpellActivationOverlay.IsSpellOverlayed(ident)
                then
                    if not toHide then
                        toHide = {}
                    end
                    toHide[#toHide + 1] = button
                end
            end
            if toHide then
                for idx = 1, #toHide do
                    HideGlow(toHide[idx])
                end
            end
        else
            -- SHOW: scan all buttons for the matching spellID. Dormant bars
            -- skip (nobody can see the glow); the show-edge rescan restores
            -- any proc glow that is still live when the bar reveals.
            local blizz2 = IsBlizzStyle()
            for _, details in ipairs(BAR_CONFIG) do
                local buttons = (not mod._eabBarDormant[details.key]) and barButtons[details.key] or nil
                if buttons then
                    for _, button in ipairs(buttons) do
                        if button and (EFD(button).squared or blizz2) then
                            local ident = GetButtonSpellID(button)
                            if ident and ident == arg1 then
                                ShowGlow(button)
                            end
                        end
                    end
                end
            end
        end
    end)

    -- Suppress Blizzard's native SpellActivationAlert on our buttons (we render
    -- our own glow via UpdateFlipbook). Skipped when our custom glow is active
    -- (both use SpellActivationAlert) and for Blizzard-styled bars, whose
    -- native glows must show normally.
    if ActionButtonSpellAlertManager and ActionButtonSpellAlertManager.ShowAlert then
        hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, button)
            if
                button
                and EFD(button).squared
                and not IsBlizzStyle()
                and not _procState.active[button]
                and button.SpellActivationAlert
            then
                button.SpellActivationAlert:SetAlpha(0)
            end
        end)
    end
end

-- Per-button usability updates are native: UNIT_POWER_FREQUENT and
-- PLAYER_TARGET_CHANGED live in BUTTON_EVENT_LISTS.action, so each button
-- reacts on its own through Blizzard's C-side dispatcher. No global walk here.

-- NO AssistedCombatManager hooks here: with an assist action on a bar AND the highlight
-- CVar on, the manager calls UpdateAllAssistedHighlightFramesForSpell /
-- UpdateAllAssistedCombatRotationFrames at rotation-evaluation cadence (effectively
-- continuous in combat), so a hooked full-bar walk would run on EVERY call. Scaling
-- happens only where it can change something: Blizzard's highlight frame inside the
-- rate-limited rescan pass (already visits exactly the buttons that can hold the
-- suggestion), rotation frames via the per-button change-guarded rotHooked hook, and
-- existing frames via the bar layout path on size changes.

-------------------------------------------------------------------------------
--  Assisted Combat Highlight (self-painted): our EABButton frames are
--  permanently removed from ActionBarButtonEventsFrame.frames (the taint
--  fix), so Blizzard's AssistedCombatManager never builds them into its
--  highlight-candidate list (it walks .frames once at activation): its shine
--  would appear only after a mouseover re-added that one button, and never
--  survive a reload or mid-session CVar toggle. We paint our own shine from
--  the same AssistedCombatManager events the CDM module uses, immune to that
--  timing. Blizzard may still show its own frame on a hovered button
--  (candidate re-add); we defer to it there so two identical shines never stack.
-------------------------------------------------------------------------------
do
    local _assistGlowed = {} -- btn -> true while showing our shine
    local _assistInCombat = false
    local _assistHookInstalled = false

    local function AssistCVarOn()
        return GetCVarBool and GetCVarBool("assistedCombatHighlight")
    end

    local function AssistCreate(button)
        local success, hf =
            pcall(CreateFrame, "Frame", nil, button, "ActionBarButtonAssistedCombatHighlightTemplate")
        if not success or not hf then
            return nil
        end
        hf:SetPoint("CENTER")
        -- Above the cooldown swipe, border frame, glowOverlay (+6) and proc
        -- alerts -- same margin the CDM twin uses.
        hf:SetFrameLevel(button:GetFrameLevel() + 15)
        -- Freeze on a single flipbook frame until we actually animate (in combat).
        if hf.Flipbook and hf.Flipbook.Anim then
            hf.Flipbook.Anim:Play()
            hf.Flipbook.Anim:Stop()
        end
        hf:Hide()
        return hf
    end

    -- The custom Assisted Highlight glows run on the shared glow engines with
    -- settings of their own (assistGlow*), never the Custom Proc Glow's.
    -- Their colour: the palette's class colour or the picked one; the one
    -- reader for the live buttons and the Animations page preview.
    mod._AssistCustomGlowColor = function()
        local p = ABAR.db and ABAR.db.profile
        local c = p and p.assistGlowColor
        return _G_Glows.ResolveColor(
            _G_Glows.DeriveColorMode(nil, p and p.assistGlowUseClassColor),
            c and c.r,
            c and c.g,
            c and c.b,
            0.15,
            0.5,
            1
        )
    end

    mod._AssistCustomGlowStop = function(button)
        local fd = EFD(button)
        local wrapper = fd.assistGlowWrapper
        if wrapper then
            _G_Glows.StopAllGlows(wrapper)
            wrapper:Hide()
        end
    end

    mod._AssistCustomGlowStart = function(button, loopIdx, cr, cg, cb, bW, bH)
        local loopEntry = LOOP_GLOW_TYPES[loopIdx]
        if not loopEntry then
            mod._AssistCustomGlowStop(button)
            return false
        end

        local fd = EFD(button)
        if not fd.assistGlowWrapper then
            local wrapper = CreateFrame("Frame", nil, button)
            wrapper:SetAllPoints(button)
            fd.assistGlowWrapper = wrapper
        end

        local wrapper = fd.assistGlowWrapper
        wrapper:SetAllPoints(button)
        wrapper:SetFrameLevel(button:GetFrameLevel() + 15)
        wrapper:SetAlpha(1)

        local wfd = EFD(wrapper)
        if fd.shapeMask and fd.shapeApplied and fd.shapeMaskPath then
            if not wfd.ownMask then
                wfd.ownMask = wrapper:CreateMaskTexture()
            end
            wfd.ownMask:ClearAllPoints()
            Pix.Point(wfd.ownMask, "TOPLEFT", button, "TOPLEFT", 1, -1)
            Pix.Point(wfd.ownMask, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
            wfd.ownMask:SetTexture(fd.shapeMaskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            wfd.ownMask:Show()
        elseif wfd.ownMask then
            wfd.ownMask:Hide()
        end

        _G_Glows.StopAllGlows(wrapper)
        wrapper:Show()

        _G_Glows.StartSpecGlow(wrapper, { style = loopIdx, r = cr, g = cg, b = cb }, bW, bH, "icon", {
            maskWith = wfd.ownMask and wfd.ownMask:IsShown() and wfd.ownMask or nil,
            maskPath = fd.shapeMaskPath or SHAPE_MASKS[fd.shapeName or ""],
            borderPath = SHAPE_BORDERS[fd.shapeName or ""],
            shapeMask = fd.shapeMask,
            anchorFrame = button,
        })
        return true
    end

    -- Ring teardown alone. Split out of AssistHide because AssistShow also
    -- needs it on its own: with the overlay style picked, or with Blizzard
    -- painting its own ring on a hovered button, our ring must go while the
    -- overlay stays up.
    mod._AssistRingHide = function(button)
        local hf = EFD(button).assistHL
        if not hf then
            return
        end
        if hf.Flipbook and hf.Flipbook.Anim then
            hf.Flipbook.Anim:Stop()
        end
        hf:Hide()
    end

    -- Flat tint over the button -- the alternative (or companion) to the ring.
    -- Its own child frame at btn+14, one below the ring, so it draws over the
    -- icon and the cooldown swipe deterministically instead of racing draw-layer
    -- sublevels against Blizzard's own button textures. A color fill plus one
    -- mask: no animation and no driver entry, so it is strictly cheaper than the
    -- flipbook ring. Created lazily, so nobody on the ring-only default pays
    -- for it.
    -- style: nil/1 = hide, 2 = overlay only, 3 = overlay under the ring.
    mod._AssistOverlay = function(button, look)
        local fd = EFD(button)
        local shade = fd.assistOverlay
        if not look or look == 1 then
            if shade then
                shade:Hide()
            end
            return
        end
        local p = ABAR.db and ABAR.db.profile
        if not shade then
            shade = CreateFrame("Frame", nil, button)
            shade.tex = shade:CreateTexture(nil, "OVERLAY")
            shade.tex:SetAllPoints(shade)
            -- Rounded corners: the addon's own Curved Square mask, so the tint
            -- follows the button art instead of ending in hard 90-degree
            -- corners. Only used when no button shape mask is in play -- that
            -- one already defines the silhouette.
            shade.roundMask = shade:CreateMaskTexture()
            shade.roundMask:SetAllPoints(shade)
            shade.roundMask:SetTexture(SHAPE_MASKS.csquare, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            fd.assistOverlay = shade
        end
        -- Footprint. Alone (style 2) the tint covers exactly the button. Under
        -- the ring (style 3) it grows or shrinks with the ring's outset so the
        -- two end flush -- the tint never sticks out past the ring, which is
        -- what a negative outset would otherwise produce. With Fit Ring to
        -- Cropped Buttons fitting the ring (ns._AssistFit), the tint takes the
        -- same top and bottom pull-in so the two stay flush. Change-guarded: the
        -- rescan runs several times a second while a suggestion is up.
        local pad = (look == 3) and ((p and p.assistGlowOutset) or 0) or 0
        local padY = pad
        if look == 3 and fd.cropped and p and p.assistGlowFitCropped then
            padY = pad - mod._ASSIST_CROP_TRIM / 2
        end
        local ofd = EFD(shade)
        if ofd.pad ~= pad or ofd.padY ~= padY then
            ofd.pad, ofd.padY = pad, padY
            shade:ClearAllPoints()
            shade:SetPoint("TOPLEFT", button, "TOPLEFT", -pad, padY)
            shade:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", pad, -padY)
        end
        -- Re-assert: bar layout can change the button's frame level after create.
        shade:SetFrameLevel(button:GetFrameLevel() + 14)
        local c = (p and p.assistGlowOverlayColor) or { r = 0.15, g = 0.5, b = 1 }
        local a = (p and p.assistGlowOverlayAlpha) or 30
        shade.tex:SetColorTexture(c.r or 0.15, c.g or 0.5, c.b or 1, a / 100)
        -- Custom button shapes win over the rounded corners: a circle mask must
        -- not end up as a rounded square. Keyed on the mask OBJECT, not a
        -- boolean -- a shape change swaps the mask, and the stale one has to be
        -- removed before the new one goes on. Applied to the tint texture
        -- directly rather than via MaskFrameTextures: that walks GetRegions(),
        -- which here would also hand the mask to our own roundMask region.
        local wanted = (fd.shapeMask and fd.shapeApplied) and fd.shapeMask or shade.roundMask
        if ofd.shapeMasked ~= wanted then
            if ofd.shapeMasked then
                pcall(shade.tex.RemoveMaskTexture, shade.tex, ofd.shapeMasked)
            end
            pcall(shade.tex.AddMaskTexture, shade.tex, wanted)
            ofd.shapeMasked = wanted
        end
        shade:Show()
    end

    -- Full teardown of everything we paint for one button. Also un-fades
    -- Blizzard's own ring: the overlay-only style parks it at alpha 0, and a
    -- button that stops being the suggestion (or the CVar going off) must not
    -- leave it invisible for whoever shows it next.
    local function AssistHide(button)
        local fd = EFD(button)
        if fd.assistCustomActive then
            mod._AssistCustomGlowStop(button)
            fd.assistCustomActive = nil
            fd.assistCustomType = nil
            fd.assistCustomMask = nil
            fd.assistCustomShapeMask = nil
            fd.assistCustomW, fd.assistCustomH = nil, nil
            fd.assistCustomR, fd.assistCustomG, fd.assistCustomB = nil, nil, nil
        end
        mod._AssistRingHide(button)
        mod._AssistOverlay(button)
        local bf = button.AssistedCombatHighlightFrame
        if bf then
            bf:SetAlpha(1)
        end
    end

    -- Scale that makes the 45px template art cover the button plus the user's
    -- outset on every side. The frame is anchored CENTER, so scaling grows or
    -- shrinks it symmetrically -- a positive outset pushes the blue swirl
    -- outside the proc glow's edge, a negative one tucks it inside. Clamped
    -- above zero: SetScale(0) is invalid, and a large negative outset on a
    -- small button would otherwise reach it.
    -- Stored on ns rather than as a local.
    mod._AssistScale = function(button)
        local wid = button:GetWidth() or 45
        local p = ABAR.db and ABAR.db.profile
        local outset = (p and p.assistGlowOutset) or 0
        local s = (wid + outset * 2) / 45
        if s < 0.05 then
            s = 0.05
        end
        return s
    end

    -- "Fit Ring to Cropped Buttons": a Cropped button is shorter than it is
    -- wide, so the width-only scale above lets the square ring overhang its top
    -- and bottom. With the option on, a ring on a Cropped button runs at scale 1
    -- and takes the button's rectangle plus the outset on every side, less a
    -- fixed 2 px at top and bottom. Its Flipbook keeps the template's overscan
    -- on each axis: the ants art has transparent padding baked in (the template
    -- draws a 66px Flipbook over its 45px frame so the ants land on the frame's
    -- edge), so a Flipbook stretched to the frame would draw the ring well
    -- inside the button. The Flipbook stays on its own CENTER anchor; only its
    -- size follows the frame, per axis, in the snapshot's own ratio. The ring's
    -- and its Flipbook's original sizes are snapshotted on first touch and
    -- restored exactly when the button leaves Cropped or the option goes off.
    -- State lives in EFD(ring), never on Blizzard's frame. Change-guarded:
    -- AssistShow re-runs several times a second. Returns true when it sized
    -- the ring (the caller then skips the width scale).
    -- The fitted ring's height trim: 2 px pulled in at the top and at the
    -- bottom. The Ring + Overlay tint reads it too, to stay flush.
    mod._ASSIST_CROP_TRIM = 4
    mod._AssistFit = function(button, ring, cropped)
        local p = ABAR.db and ABAR.db.profile
        local rfd = mod._eabFD[ring]
        if not (cropped and p and p.assistGlowFitCropped) then
            if rfd and rfd.fitW then
                rfd.fitW, rfd.fitH = nil, nil
                ring:SetSize(rfd.origW, rfd.origH)
                local fb = ring.Flipbook
                if fb and rfd.fbW then
                    fb:SetSize(rfd.fbW, rfd.fbH)
                end
            end
            return false
        end
        rfd = EFD(ring)
        local fb = ring.Flipbook
        if not rfd.origW then
            rfd.origW, rfd.origH = ring:GetSize()
            if fb then
                rfd.fbW, rfd.fbH = fb:GetSize()
            end
        end
        local outset = p.assistGlowOutset or 0
        local wid = button:GetWidth() + outset * 2
        local hgt = button:GetHeight() + outset * 2 - mod._ASSIST_CROP_TRIM
        if wid < 1 then
            wid = 1
        end
        if hgt < 1 then
            hgt = 1
        end
        if ring:GetScale() ~= 1 then
            ring:SetScale(1)
        end
        if rfd.fitW ~= wid or rfd.fitH ~= hgt then
            rfd.fitW, rfd.fitH = wid, hgt
            ring:SetSize(wid, hgt)
            if fb and rfd.fbW and rfd.origW > 0 and rfd.origH > 0 then
                fb:SetSize(rfd.fbW * wid / rfd.origW, rfd.fbH * hgt / rfd.origH)
            end
        end
        return true
    end

    -- Paint the suggestion on one button in whatever style the user picked.
    -- Owns the "Blizzard already draws its own ring here" case too (it used to
    -- live at the call site): the overlay is ours either way, so the two
    -- decisions have to be made together.
    local function AssistShow(button)
        local fd = EFD(button)
        local p = ABAR.db and ABAR.db.profile
        local customType = (p and p.assistGlowType) or 0
        if customType < 1 or customType > #LOOP_GLOW_TYPES or not LOOP_GLOW_TYPES[customType] then
            customType = 0
        end

        if customType > 0 and _assistInCombat then
            if fd.shapeMask and fd.shapeApplied then
                for si, record in ipairs(LOOP_GLOW_TYPES) do
                    if record.shapeGlow then
                        customType = si
                        break
                    end
                end
            end
            local shade = fd.assistOverlay
            if shade and shade:IsShown() then
                mod._AssistOverlay(button)
            end
            local hf = fd.assistHL
            if hf and hf:IsShown() then
                mod._AssistRingHide(button)
            end

            local bf = button.AssistedCombatHighlightFrame
            if bf then
                bf:SetAlpha(0)
            end

            local cr, cg, cb = mod._AssistCustomGlowColor()
            local bW, bH = button:GetWidth() or 45, button:GetHeight() or 45
            if
                fd.assistCustomActive
                and fd.assistCustomType == customType
                and fd.assistCustomW == bW
                and fd.assistCustomH == bH
                and fd.assistCustomMask == fd.shapeMaskPath
                and fd.assistCustomShapeMask == fd.shapeMask
                and fd.assistCustomR == cr
                and fd.assistCustomG == cg
                and fd.assistCustomB == cb
                and fd.assistGlowWrapper
                and fd.assistGlowWrapper:IsShown()
            then
                return
            end

            if mod._AssistCustomGlowStart(button, customType, cr, cg, cb, bW, bH) then
                fd.assistCustomActive = true
                fd.assistCustomType = customType
                fd.assistCustomW, fd.assistCustomH = bW, bH
                fd.assistCustomMask = fd.shapeMaskPath
                fd.assistCustomShapeMask = fd.shapeMask
                fd.assistCustomR, fd.assistCustomG, fd.assistCustomB = cr, cg, cb
            end
            return
        end

        if fd.assistCustomActive then
            mod._AssistCustomGlowStop(button)
            fd.assistCustomActive = nil
            fd.assistCustomType = nil
            fd.assistCustomMask = nil
            fd.assistCustomShapeMask = nil
            fd.assistCustomW, fd.assistCustomH = nil, nil
            fd.assistCustomR, fd.assistCustomG, fd.assistCustomB = nil, nil, nil
            local bf = button.AssistedCombatHighlightFrame
            if bf then
                bf:SetAlpha(1)
            end
        end

        local look = (p and p.assistGlowStyle) or 1
        -- A custom glow runs in combat only: outside it, Blizzard's frozen ring.
        if customType > 0 or look == 0 then
            look = 1
        end

        mod._AssistOverlay(button, look)

        -- Blizzard may show its own ring on a hovered button (candidate
        -- re-add). Defer to it so two identical shines never stack, but keep it
        -- scaled to our button size + outset. With the overlay-only style we
        -- fade it rather than Hide() it: their manager re-shows it, so a Hide
        -- would just be undone. Alpha is re-asserted on every pass, so it
        -- self-corrects when the style changes back.
        local bf = button.AssistedCombatHighlightFrame
        if bf and bf:IsShown() then
            mod._AssistRingHide(button)
            bf:SetAlpha(look == 2 and 0 or 1)
            if fd.squared and not mod._AssistFit(button, bf, fd.cropped) then
                local s = mod._AssistScale(button)
                if bf:GetScale() ~= s then
                    bf:SetScale(s)
                end
            end
            return
        end

        if look == 2 then
            mod._AssistRingHide(button)
            return
        end

        local hf = fd.assistHL
        if not hf then
            hf = AssistCreate(button)
            if not hf then
                return
            end
            fd.assistHL = hf
        end
        if not mod._AssistFit(button, hf, fd.cropped) then
            hf:SetScale(mod._AssistScale(button))
        end
        -- Re-assert: bar layout can change the button's frame level after create.
        hf:SetFrameLevel(button:GetFrameLevel() + 15)
        hf:Show()
        if hf.Flipbook and hf.Flipbook.Anim then
            if _assistInCombat then
                hf.Flipbook.Anim:Play()
            else
                hf.Flipbook.Anim:Stop()
            end
        end
    end

    -- The (spell) id a button currently represents, mirroring
    -- AssistedCombatManager:GetActionButtonSpellForAssistedHighlight.
    -- Attribute first: secure paging writes "action", the authoritative slot
    -- (see ForceCooldownPaint); btn.action is a derived mirror.
    local function ButtonSpell(button)
        local action = button.GetAttribute and button:GetAttribute("action")
        if action == nil then
            action = button.action
        end
        if action == nil then
            return nil
        end
        local atype, ident, subType = GetActionInfo(action)
        if atype == "spell" and subType ~= "assistedcombat" then
            return ident
        elseif atype == "macro" and subType == "spell" then
            return ident
        end
        return nil
    end

    local function UpdateAssistHighlights()
        if not AssistCVarOn() then
            for button in pairs(_assistGlowed) do
                AssistHide(button)
                _assistGlowed[button] = nil
            end
            return
        end
        local suggested = C_AssistedCombat
            and C_AssistedCombat.GetNextCastSpell
            and C_AssistedCombat.GetNextCastSpell()
        local newSet = {}
        if suggested then
            -- Match base ids in both directions (button or suggestion may hold
            -- either the base or an override), same as the CDM side. sid > 0
            -- guards item/macro pseudo-ids out of GetBaseSpell.
            local GetBaseSpell = C_Spell and C_Spell.GetBaseSpell
            local suggestedBase = (GetBaseSpell and GetBaseSpell(suggested)) or suggested
            for _, details in ipairs(BAR_CONFIG) do
                if not details.isStance and not details.isPetBar then
                    local buttons = barButtons[details.key]
                    if buttons then
                        for idx = 1, #buttons do
                            local button = buttons[idx]
                            if button and button:IsShown() then
                                local spellRef = ButtonSpell(button)
                                if spellRef then
                                    local match = (spellRef == suggested) or (spellRef == suggestedBase)
                                    if not match and GetBaseSpell and spellRef > 0 then
                                        match = GetBaseSpell(spellRef) == suggestedBase
                                    end
                                    if match then
                                        -- AssistShow owns the style decision and
                                        -- the defer-to-Blizzard's-own-ring case.
                                        AssistShow(button)
                                        newSet[button] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        for button in pairs(_assistGlowed) do
            if not newSet[button] then
                AssistHide(button)
            end
        end
        _assistGlowed = newSet
    end
    mod.UpdateAssistHighlights = UpdateAssistHighlights

    -- Coalesced re-run: OnActionChanged fires per button on page swaps and in
    -- SLOT_CHANGED storms dozens of times per second (mouseover-conditional
    -- macros re-resolving). Next-frame coalescing alone still meant one full
    -- all-bars GetActionInfo walk PER FRAME for the whole storm (assist CVar
    -- off early-outs, so only assist users saw it). Rate-limit to one pass
    -- per 0.15s: idle still runs same-frame, a storm pays at most ~7
    -- walks/sec, and 150ms of shine lag is invisible on a pulsing cosmetic.
    local _assistRescanPending = false
    local _assistLastScan = 0
    local function QueueAssistRescan()
        if _assistRescanPending then
            return
        end
        _assistRescanPending = true
        local elapsed = GetTime() - _assistLastScan
        local delay = (elapsed >= 0.15) and 0 or (0.15 - elapsed)
        C_Timer.After(delay, function()
            _assistRescanPending = false
            _assistLastScan = GetTime()
            UpdateAssistHighlights()
        end)
    end
    mod.QueueAssistRescan = QueueAssistRescan

    local function SyncAssistCombat()
        local inCombat = (InCombatLockdown() or UnitAffectingCombat("player")) and true or false
        local changed = _assistInCombat ~= inCombat
        _assistInCombat = inCombat
        -- Exposed for the per-button rotation hook (different scope), which
        -- re-freezes Blizzard's swirl after its UpdateState calls.
        mod._assistCombatState = _assistInCombat
        -- A custom glow runs in combat only (the frozen ring stands in outside
        -- it), so its buttons are painted again on the edge; the stock styles
        -- only start or stop their flipbook below.
        local p = ABAR.db and ABAR.db.profile
        local repaint = changed and ((p and p.assistGlowType) or 0) > 0
        for button in pairs(_assistGlowed) do
            if repaint then
                AssistShow(button)
            end
            local hf = EFD(button).assistHL
            if hf and hf:IsShown() and hf.Flipbook and hf.Flipbook.Anim then
                if _assistInCombat then
                    if not hf.Flipbook.Anim:IsPlaying() then
                        hf.Flipbook.Anim:Play()
                    end
                else
                    if hf.Flipbook.Anim:IsPlaying() then
                        hf.Flipbook.Anim:Stop()
                    end
                end
            end
        end
        -- Blizzard's rotation swirl needs no combat gating: the
        -- UpdateAssistedCombatRotationFrame hook keeps it permanently hidden and
        -- the script-free spinner (ns.EnsureAssistSpinner) costs no Lua ever.
    end

    local function InstallAssistHook()
        if _assistHookInstalled then
            return
        end
        _assistHookInstalled = true
        SyncAssistCombat()
        if EventRegistry and EventRegistry.RegisterCallback then
            -- No hooksecurefunc on UpdateAllAssistedHighlightFramesForSpell:
            -- the manager calls it then fires this event right after, so a
            -- hook would run the full walk twice per suggestion change.
            EventRegistry:RegisterCallback("AssistedCombatManager.OnAssistedHighlightSpellChange", function()
                QueueAssistRescan()
            end, "EAB_AssistHighlight")
            -- Fires when the assistedCombatHighlight CVar is toggled at runtime.
            EventRegistry:RegisterCallback("AssistedCombatManager.OnSetUseAssistedHighlight", function()
                QueueAssistRescan()
            end, "EAB_AssistHighlight_CVar")
            -- Page swaps / drags / hover re-candidacy: the suggestion may not
            -- change, but which button holds it (or whether Blizzard shows its
            -- own frame on a hovered button) does. Same signal Blizzard uses.
            EventRegistry:RegisterCallback("ActionButton.OnActionChanged", function()
                QueueAssistRescan()
            end, "EAB_AssistHighlight_Action")
        end
        local castFrame = mod.TakeShell()
        castFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        castFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        castFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        castFrame:SetScript("OnEvent", function(_, evt)
            if evt == "PLAYER_ENTERING_WORLD" then
                SyncAssistCombat()
                UpdateAssistHighlights()
            else
                SyncAssistCombat()
            end
        end)
        UpdateAssistHighlights()
    end
    InstallAssistHook()
end

function ABAR:RefreshProcGlows()
    for _, details in ipairs(BAR_CONFIG) do
        local buttons = barButtons[details.key]
        if buttons then
            for idx = 1, #buttons do
                local button = buttons[idx]
                if button and _procState.active[button] then
                    UpdateFlipbook(button)
                end
            end
        end
    end
end

function ABAR:ScanExistingProcs()
    local found = 0
    local sum = 0
    local blizz = mod.AB_Style() ~= "cui"
    for _, details in ipairs(BAR_CONFIG) do
        local buttons = barButtons[details.key]
        if buttons then
            for idx = 1, #buttons do
                local button = buttons[idx]
                if button and (EFD(button).squared or blizz) then
                    sum = sum + 1
                    local spellId = _procState.GetButtonSpellID(button)
                    local ISO = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
                    local overlayed = spellId and ISO and ISO(spellId)
                    if not overlayed and spellId and ISO then
                        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                            local ovr = C_SpellBook.FindSpellOverrideByID(spellId)
                            if ovr and ovr > 0 and ovr ~= spellId then
                                overlayed = ISO(ovr)
                            end
                        end
                        if not overlayed and C_Spell and C_Spell.GetBaseSpell then
                            local baseValue = C_Spell.GetBaseSpell(spellId)
                            if baseValue and baseValue > 0 and baseValue ~= spellId then
                                overlayed = ISO(baseValue)
                            end
                        end
                    end
                    if overlayed then
                        found = found + 1
                        _procState.active[button] = true
                        UpdateFlipbook(button)
                    end
                end
            end
        end
    end
end

local EDGE_TEXTURE = "Interface\\AddOns\\CludesUIActionBars\\Media\\edge.png"

local function GetClassColor()
    local _, classFile = UnitClass("player")
    local c = RAID_CLASS_COLORS[classFile]
    if c then
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

local function ResolveCooldownEdgeColor(p)
    if p.cooldownEdgeUseClassColor then
        local cr, cg, cb = GetClassColor()
        local c = p.cooldownEdgeColor or { a = 1 }
        return cr, cg, cb, c.a or 1
    end
    local c = p.cooldownEdgeColor or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    return c.r, c.g, c.b, c.a
end

local function ApplySingleCooldownEdge(cdFrame, edgeSize, cr, cg, cb, ca)
    if not cdFrame then
        return
    end
    if cdFrame:IsForbidden() then
        return
    end
    if cdFrame.SetEdgeTexture then
        cdFrame:SetEdgeTexture(EDGE_TEXTURE)
    end
    if cdFrame.SetEdgeScale then
        cdFrame:SetEdgeScale(edgeSize)
    end
    if cdFrame.SetEdgeColor then
        cdFrame:SetEdgeColor(cr, cg, cb, ca)
    end
end

-- After applying edge cosmetics, enforce shape-based edge visibility. Must be called
-- after ApplySingleCooldownEdge since SetEdgeTexture may re-enable drawing.
local function EnforceShapeEdgeSingle(cd, edgeScale, useCircular)
    if not cd or cd:IsForbidden() then
        return
    end
    if cd.SetEdgeTexture then
        pcall(cd.SetEdgeTexture, cd, EDGE_TEXTURE)
    end
    if cd.SetUseCircularEdge then
        pcall(cd.SetUseCircularEdge, cd, useCircular)
    end
    if cd.SetEdgeScale then
        pcall(cd.SetEdgeScale, cd, edgeScale)
    end
end

local function EnforceShapeEdge(button)
    local efd = EFD(button)
    if not button or not efd.shapeApplied then
        return
    end
    local shapeName = efd.shapeName
    if not shapeName then
        return
    end
    local edgeScale = SHAPE_EDGE_SCALES[shapeName] or 0.60
    local useCircular = (shapeName ~= "square" and shapeName ~= "csquare")
    EnforceShapeEdgeSingle(button.cooldown, edgeScale, useCircular)
    EnforceShapeEdgeSingle(button.chargeCooldown, edgeScale, useCircular)
end

local function ApplyButtonCooldownEdge(button, edgeSize, cr, cg, cb, ca)
    -- Square/csquare use the user's edge size; other shapes force 1.0
    -- since EnforceShapeEdge will override with per-shape scale anyway.
    local efd = EFD(button)
    local sn = efd.shapeApplied and efd.shapeName
    local sz = edgeSize
    if sn and sn ~= "square" and sn ~= "csquare" then
        sz = 1.0
    end
    ApplySingleCooldownEdge(button.cooldown, sz, cr, cg, cb, ca)
    ApplySingleCooldownEdge(button.chargeCooldown, sz, cr, cg, cb, ca)
    EnforceShapeEdge(button)
end

-- Hook to re-apply edge settings whenever Blizzard resets a cooldown.

-- Per-button hooks avoid tainting the secure execution path.
local _cdEdge = {
    hooked = false,
    pending = {}, -- reusable { [cdFrame] = btn, ... }
    pendingCount = 0,
    timerScheduled = false,
}

local function _FlushCDPatch()
    _cdEdge.timerScheduled = false
    local p = ABAR.db and ABAR.db.profile
    if not p then
        wipe(_cdEdge.pending)
        _cdEdge.pendingCount = 0
        return
    end
    local cr, cg, cb, ca = ResolveCooldownEdgeColor(p)
    local baseSz = p.cooldownEdgeSize or 2.1
    for cdFrame, button in pairs(_cdEdge.pending) do
        if cdFrame and not cdFrame:IsForbidden() then
            local sz = baseSz
            local bfd = EFD(button)
            local sn = bfd.shapeApplied and bfd.shapeName
            if sn and sn ~= "square" and sn ~= "csquare" then
                sz = 1.0
            end
            ApplySingleCooldownEdge(cdFrame, sz, cr, cg, cb, ca)
            if bfd.shapeMaskPath and bfd.shapeApplied then
                local maskTex = bfd.shapeMask
                if maskTex then
                    pcall(cdFrame.RemoveMaskTexture, cdFrame, maskTex)
                    pcall(cdFrame.AddMaskTexture, cdFrame, maskTex)
                end
                if cdFrame.SetSwipeTexture then
                    pcall(cdFrame.SetSwipeTexture, cdFrame, bfd.shapeMaskPath)
                end
            end
            EnforceShapeEdge(button)
            EFD(cdFrame).edgeDone = true
        end
    end
    wipe(_cdEdge.pending)
    _cdEdge.pendingCount = 0
end

local function HookButtonCooldownEdge(button)
    if not button or not EFD(button).squared then
        return
    end
    if EFD(button).cdEdgeHooked then
        return
    end
    EFD(button).cdEdgeHooked = true

    local function OnSetCooldown(cdFrame)
        -- Cooldown edge patch (skip if edge was already applied to this frame)
        if cdFrame and not EFD(cdFrame).edgeDone then
            if not _cdEdge.pending[cdFrame] then
                _cdEdge.pendingCount = _cdEdge.pendingCount + 1
            end
            _cdEdge.pending[cdFrame] = button
            if not _cdEdge.timerScheduled then
                _cdEdge.timerScheduled = true
                C_Timer_After(0, _FlushCDPatch)
            end
        end
        -- Cooldown font patch (shared hook, avoids a second hooksecurefunc on
        -- SetCooldown). Skip only when BOTH cooldown frames carry the applied
        -- stamp (set by ApplyToFrame, cleared on settings change): the charge
        -- cooldown can appear after the main one is already stamped.
        local chargeCd = button.chargeCooldown
        local mainNeeds = not (button.cooldown and EFD(button.cooldown).cdFontStamp)
        local chargeNeeds = chargeCd and not EFD(chargeCd).cdFontStamp
        if mainNeeds or chargeNeeds then
            -- A cooldown showing no countdown numbers has no FontString for
            -- ApplyToFrame to find, so it can never take the stamp; an unconditional
            -- queue would re-arm on EVERY cooldown edge for the rest of the session.
            -- Chase only frames whose numbers are on. Nothing is missed: both un-hide
            -- paths queue the patch themselves (UpdateChargeNumbersVisibility for the
            -- charge frame; for the main frame the next SetCooldown after the CVar
            -- flips lands here with numbersOn true). Deliberately AFTER the stamp test,
            -- so the steady state exits above without paying for the CVar read.
            local numbersOn = GetCVarBool("countdownForCooldowns")
            if
                (mainNeeds and numbersOn)
                or (chargeNeeds and EFD(chargeCd).rechargeNumbersHidden == false)
            then
                EAB_VTABLE.CooldownFonts.pending[button] = true
                if not EAB_VTABLE.CooldownFonts.timerScheduled then
                    EAB_VTABLE.CooldownFonts.timerScheduled = true
                    C_Timer_After(0, EAB_VTABLE.CooldownFonts.FlushPatch)
                end
            end
        end
    end

    if button.cooldown and button.cooldown.SetCooldown then
        hooksecurefunc(button.cooldown, "SetCooldown", OnSetCooldown)
    end
    if button.chargeCooldown and button.chargeCooldown.SetCooldown then
        hooksecurefunc(button.chargeCooldown, "SetCooldown", OnSetCooldown)
    end
end

EAB_VTABLE.CooldownFonts.pending = {}
EAB_VTABLE.CooldownFonts.timerScheduled = false

function EAB_VTABLE.CooldownFonts.FlushPatch()
    EAB_VTABLE.CooldownFonts.timerScheduled = false

    for button in pairs(EAB_VTABLE.CooldownFonts.pending) do
        local details = buttonToBar[button]
        local barId = details and details.barKey
        local s = barId
            and ABAR.db
            and ABAR.db.profile
            and ABAR.db.profile.bars
            and ABAR.db.profile.bars[barId]
        if s then
            local fontFile, cdSize, cdOX, cdOY, cdColor, cdFit = EAB_VTABLE.CooldownFonts.GetSettings(s)
            EAB_VTABLE.CooldownFonts.ApplyToButton(button, fontFile, cdSize, cdOX, cdOY, cdColor, cdFit)
        end
        EAB_VTABLE.CooldownFonts.pending[button] = nil
    end
end

function EAB_VTABLE.CooldownFonts.HookButton(button)
    if not button or EFD(button).cdFontsHooked then
        return
    end
    EFD(button).cdFontsHooked = true
    -- Piggybacks on HookButtonCooldownEdge rather than a second hooksecurefunc
    -- on the same SetCooldown: that hook already fires on every SetCooldown and
    -- queues the font patch. If it has not run yet, it picks fonts up when it does.
end

local function HookCooldownEdge()
    if _cdEdge.hooked then
        return
    end
    _cdEdge.hooked = true
    for _, details in ipairs(BAR_CONFIG) do
        local buttons = barButtons[details.key]
        if buttons then
            for idx = 1, #buttons do
                local button = buttons[idx]
                if button and EFD(button).squared then
                    HookButtonCooldownEdge(button)
                end
            end
        end
    end
end

function ABAR:ApplyCooldownEdge()
    if not self.db.profile.squareIcons then
        return
    end
    HookCooldownEdge()
    local p = self.db.profile
    local cr, cg, cb, ca = ResolveCooldownEdgeColor(p)
    local sz = p.cooldownEdgeSize or 2.1
    for _, details in ipairs(BAR_CONFIG) do
        local buttons = barButtons[details.key]
        if buttons then
            for idx = 1, #buttons do
                local button = buttons[idx]
                if button and EFD(button).squared then
                    -- Clear edge cache so the hook re-applies on next cooldown
                    if button.cooldown then
                        EFD(button.cooldown).edgeDone = nil
                    end
                    if button.chargeCooldown then
                        EFD(button.chargeCooldown).edgeDone = nil
                    end
                    ApplyButtonCooldownEdge(button, sz, cr, cg, cb, ca)
                end
            end
        end
    end
end

function EAB_VTABLE.CooldownFonts.HookAll()
    for _, details in ipairs(BAR_CONFIG) do
        local buttons = barButtons[details.key]
        if buttons then
            for idx = 1, #buttons do
                local button = buttons[idx]
                if button then
                    EAB_VTABLE.CooldownFonts.HookButton(button)
                end
            end
        end
    end
end

function ABAR:ApplyMiscTextures()
    local p = self.db.profile

    -- Color the "other" button textures (CheckedTexture, NewActionTexture,
    -- Border) using the pushed texture color settings.  These are the
    -- hard-coded textures the user can't individually customize.
    local useCC = p.pushedUseClassColor
    local customC = p.pushedCustomColor or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    local cr, cg, cb, ca = customC.r, customC.g, customC.b, customC.a or 1
    if useCC then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then
                cr, cg, cb = cc.r, cc.g, cc.b
            end
        end
    end
    for _, details in ipairs(BAR_CONFIG) do
        local buttons = barButtons[details.key]
        if buttons then
            for idx = 1, #buttons do
                local button = buttons[idx]
                if button and EFD(button).squared then
                    -- Do NOT color CheckedTexture or Border Blizzard uses
                    -- these for item rarity borders (green/blue/purple) on
                    -- active trinkets / equipped items.
                    if button.NewActionTexture then
                        button.NewActionTexture:SetDesaturated(true)
                        button.NewActionTexture:SetVertexColor(cr, cg, cb, ca)
                    end
                end
            end
        end
    end

    -- ActionBarActionEventsFrame is killed at file-load time
    -- (CUI_ActionBars_Disposal.lua's ns.QuietBroadcasters).
    -- Spellcast events are no longer re-registered here -- our central
    -- dispatcher + ACTIONBAR_UPDATE_COOLDOWN handles cooldown/GCD swipes.
end

-- "Show Highlight on Spell Cast": CheckedTexture is the highlight shown while a
-- spell is the current/active action. Option off drives its alpha to 0 (the same
-- hide-via-alpha pattern the "none" pushed/highlight types use). Single source
-- of truth, so every site setting CheckedTexture alpha stays consistent.
-- barKey: "Show as Border" (Spell Cast Highlight cog) holds the fill at 0 on
-- the bars where the button's border copy stands in for it (ns._ixElig, kept
-- current by every pass that can change it while the option is on).
function ABAR:GetCheckedAlpha(barId)
    local p = self.db.profile
    if p.showCastHighlight == false then
        return 0
    end
    if barId and p.castHighlightBorder and mod._ixElig[barId] then
        return 0
    end
    return 1
end

function ABAR:ApplyCheckedTextures()
    local p = self.db.profile
    local _, _, ixOn = mod._ixRolesOn(p)
    local ixEver = mod._ixEver
    for _, details in ipairs(BAR_CONFIG) do
        local buttons = barButtons[details.key]
        if buttons then
            local s = p.bars[details.key]
            -- Eligibility first: GetCheckedAlpha reads it.
            local ixBar = ixOn and mod._ixBarEligible(details.key)
            local a = self:GetCheckedAlpha(details.key)
            for idx = 1, #buttons do
                local button = buttons[idx]
                if button and button.CheckedTexture then
                    button.CheckedTexture:SetAlpha(a)
                end
                if button then
                    if ixBar then
                        mod._ixRole(button, s, "ixCast", true)
                    elseif ixEver then
                        mod._ixRole(button, s, "ixCast", false)
                    end
                end
            end
        end
    end
end

-- Re-apply charge-spell recharge-number visibility across all buttons. Same
-- logic the dispatcher's per-tick + CVAR_UPDATE paths use; called when the
-- "Cooldown Numbers" cog toggle flips so the change is immediate (a DB
-- toggle does not fire CVAR_UPDATE). Cached per chargeCd, so it is near-free.
function ABAR:RefreshChargeRechargeNumbers()
    for _, details in ipairs(BAR_CONFIG) do
        if not details.isStance and not details.isPetBar then
            local buttons = barButtons[details.key]
            if buttons then
                for _, button in ipairs(buttons) do
                    local chargeCd = button.chargeCooldown
                    if chargeCd then
                        local action = button:GetAttribute("action")
                        local success = action and HasAction(action)
                        mod.UpdateChargeNumbersVisibility(
                            button,
                            chargeCd,
                            success and C_ActionBar.GetActionCooldown(action) or nil,
                            success and C_ActionBar.GetActionCharges(action) or nil
                        )
                    end
                end
            end
        end
    end
end
