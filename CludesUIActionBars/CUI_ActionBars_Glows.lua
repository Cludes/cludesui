if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
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

local function StopAllProceduralGlows(glowHolder) _G_Glows.StopAllGlows(glowHolder) end

local _procState = { hooked = false, active = {} }

local function UpdateFlipbook(button)
    local regionFrame = button.SpellActivationAlert
    local frameData = EFD(button)
    if
        regionFrame
        and frameData.shapeMask
        and frameData.shapeApplied
        and not EFD(regionFrame).shapeMasked
    then
        for _, texture in ipairs({ regionFrame:GetRegions() }) do
            if texture and texture.AddMaskTexture then
                pcall(texture.AddMaskTexture, texture, frameData.shapeMask)
            end
        end
        EFD(regionFrame).shapeMasked = true
    end

    local profile = ABAR.db and ABAR.db.profile
    if not profile then return end

    -- Size from profile settings, not btn:GetWidth(): on initial login the
    -- frame may not be sized by LayoutBar yet and GetWidth returns the
    -- default 45. Replicates LayoutBar's shape expansion/cropped math so the
    -- ratio matches the actual rendered size.
    local _ufBtnW, _ufBtnH
    do
        local barKey = frameData.barKey
        if not barKey then
            local bi = buttonToBar[button]
            if bi then barKey = bi.barKey end
        end
        local resolved
        if barKey and profile.bars and profile.bars[barKey] then
            local cfg = profile.bars[barKey]
            local baseLevel = barBaseSize[barKey]
            local buttonW = baseLevel and baseLevel.w or 45
            local buttonH = baseLevel and baseLevel.h or 45
            local wid = (cfg.buttonWidth and cfg.buttonWidth > 0) and cfg.buttonWidth or buttonW
            local hgt = (cfg.buttonHeight and cfg.buttonHeight > 0) and cfg.buttonHeight or buttonH
            local shape = mod.AB_LayoutShape(cfg)
            if shape ~= "none" and shape ~= "cropped" then
                wid = wid + SHAPE_BTN_EXPAND
                hgt = hgt + SHAPE_BTN_EXPAND
            end
            if shape == "cropped" then hgt = hgt * 0.80 end
            _ufBtnW, _ufBtnH = wid, hgt
            resolved = true
        end
        if not resolved then
            _ufBtnW = button:GetWidth() or 45
            _ufBtnH = button:GetHeight() or 45
        end
    end

    if not profile.procGlowEnabled then
        -- "Default" glow: use our glow library with Modern WoW Glow (#6)
        if not (frameData.shapeMask and frameData.shapeApplied) then
            if not frameData.glowWrapper then
                local glowHolder = CreateFrame("Frame", nil, button:GetParent() or button)
                glowHolder:SetAllPoints(button)
                glowHolder:SetAlpha(0)
                frameData.glowWrapper = glowHolder
            end
            local glowHolder = frameData.glowWrapper
            glowHolder:SetFrameLevel(button:GetFrameLevel() + 10)
            _G_Glows.StopAllGlows(glowHolder)
            glowHolder:SetAlpha(1)
            glowHolder:Show()
            _G_Glows.StartGlow(glowHolder, 6, _ufBtnW, 1, 0.788, 0.137, nil, _ufBtnH)
            if regionFrame then regionFrame:SetAlpha(0) end
            frameData.customizedFlipbook = true
            return
        end
    end

    -- Color mode: the class flag alone decides Class (legacy profiles and older
    -- spec overrides carry only the flag); the mode key tells Default from
    -- Custom. The options getter reads the same rule.
    local color = profile.procGlowColor or { r = 1, g = 0.776, b = 0.376 }
    local cr, cg, callback = _G_Glows.ResolveColor(
        profile.procGlowUseClassColor and "class"
            or (profile.procGlowColorMode == "default" and "default" or "custom"),
        color.r,
        color.g,
        color.b
    )

    local loopIdx = profile.procGlowType or 1
    if loopIdx < 1 or loopIdx > #LOOP_GLOW_TYPES then loopIdx = 1 end
    -- Force Shape Glow for custom shapes regardless of user selection
    if frameData.shapeMask and frameData.shapeApplied then
        for si, record in ipairs(LOOP_GLOW_TYPES) do
            if record.shapeGlow then
                loopIdx = si
                break
            end
        end
    end
    local loopRec = LOOP_GLOW_TYPES[loopIdx]
    -- Default mode (nil color): the drawn engines use the suite gold; FlipBooks
    -- keep the atlas's own untinted look.
    if cr == nil and (loopRec.procedural or loopRec.buttonGlow or loopRec.autocast or loopRec.shapeGlow) then
        local skinData = _G_Glows.DEFAULT_COLOR
        cr, cg, callback = skinData.r, skinData.g, skinData.b
    end

    if not frameData.glowWrapper then
        local glowHolder = CreateFrame("Frame", nil, button:GetParent() or button)
        glowHolder:SetAllPoints(button)
        frameData.glowWrapper = glowHolder
    end
    local glowHolder = frameData.glowWrapper
    glowHolder:SetFrameLevel(button:GetFrameLevel() + 10)

    local holderData = EFD(glowHolder)
    if frameData.shapeMask and frameData.shapeApplied and frameData.shapeMaskPath then
        if not holderData.ownMask then holderData.ownMask = glowHolder:CreateMaskTexture() end
        holderData.ownMask:ClearAllPoints()
        Pix.Point(holderData.ownMask, "TOPLEFT", button, "TOPLEFT", 1, -1)
        Pix.Point(holderData.ownMask, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        holderData.ownMask:SetTexture(frameData.shapeMaskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        holderData.ownMask:Show()
    elseif holderData.ownMask then
        holderData.ownMask:Hide()
    end

    if loopRec.procedural or loopRec.buttonGlow or loopRec.autocast or loopRec.shapeGlow then
        frameData.customizedFlipbook = true
        -- Suppress Blizzard's native flipbook visuals (hide textures, not durations)
        if regionFrame then regionFrame:SetAlpha(0) end

        StopAllProceduralGlows(glowHolder)
        glowHolder:Show()

        local buttonW, buttonH = _ufBtnW, _ufBtnH

        if loopRec.procedural then
            local N = profile.procGlowLines or 8
            local th = profile.procGlowThickness or 2
            local period = profile.procGlowSpeed or 4
            local lineLen = floor((buttonW + buttonH) * (2 / N - 0.1))
            lineLen = min(lineLen, min(buttonW, buttonH))
            if lineLen < 1 then lineLen = 1 end
            -- No fallback table per proc: an unset background color reads as black.
            local bgOn, bgc = profile.procGlowBackground, profile.procGlowBackgroundColor
            _G_Glows.StartProceduralAnts(
                glowHolder,
                N,
                th,
                period,
                lineLen,
                cr,
                cg,
                callback,
                buttonW,
                buttonH,
                bgOn and (bgc and bgc.r or 0) or nil,
                bgOn and (bgc and bgc.g or 0) or nil,
                bgOn and (bgc and bgc.b or 0) or nil,
                bgOn and 1 or nil
            )
        elseif loopRec.buttonGlow then
            _G_Glows.StartButtonGlow(glowHolder, buttonW, cr, cg, callback, nil, buttonH)
        elseif loopRec.autocast then
            _G_Glows.StartAutoCastShine(glowHolder, buttonW, cr, cg, callback, 1.0, buttonH)
        elseif loopRec.shapeGlow then
            local maskPath = frameData.shapeMaskPath or SHAPE_MASKS[frameData.shapeName or ""]
            local borderPath = SHAPE_BORDERS[frameData.shapeName or ""]
            _G_Glows.StartShapeGlow(glowHolder, min(buttonW, buttonH), cr, cg, callback, 1.20, {
                maskPath = maskPath,
                borderPath = borderPath,
                shapeMask = frameData.shapeMask,
                anchorFrame = button,
            })
        end
        if holderData.ownMask then MaskFrameTextures(glowHolder, holderData.ownMask) end
    else
        -- FlipBook styles render on our own wrapper (SetAllPoints on btn) so the
        -- glow matches button size with no scale math; Blizzard's is suppressed.
        frameData.customizedFlipbook = true
        if regionFrame then regionFrame:SetAlpha(0) end

        _G_Glows.StopAllGlows(glowHolder)
        glowHolder:Show()
        _G_Glows.StartFlipBookGlow(glowHolder, _ufBtnW, loopRec, cr, cg, callback, _ufBtnH)
        if holderData.ownMask then MaskFrameTextures(glowHolder, holderData.ownMask) end
    end

    if regionFrame and frameData.shapeMask and frameData.shapeApplied then
        MaskFrameTextures(regionFrame, frameData.shapeMask)
        EFD(regionFrame).shapeMasked = true
    end
end

-- Resolve the spellID for a button.
-- Stored on _procState rather than as a file-level local.
_procState.GetButtonSpellID = function(button)
    local slot = GetButtonActionSlot(button)
    if not slot or not HasAction or not HasAction(slot) then return nil end
    local actionType, ident, subType = GetActionInfo(slot)
    if actionType == "spell" then
        return ident
    elseif actionType == "macro" then
        if subType == "spell" then
            return ident
        elseif subType == "item" then
            return nil
        end
        local macroName = GetActionText(slot)
        local macroIdx = macroName and GetMacroIndexByName(macroName)
        if macroIdx and macroIdx > 0 then
            if GetMacroItem and GetMacroItem(macroIdx) then return nil end
            return GetMacroSpell(macroIdx)
        end
    end
    return nil
end

-- Proc glow via SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE events.
-- Loops all buttons to find matches by spellID.
function ABAR:HookProcGlow()
    if _procState.hooked then return end
    _procState.hooked = true

    -- Stock art (Blizzard or Classic): the native glow shows on its own.
    local function IsBlizzStyle() return mod.AB_Style() ~= "cui" end

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
            if _procState.active[button] then HideGlow(button) end
            return
        end
        local ISO = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
        if not ISO then return end
        if ISO(spellId) then
            ShowGlow(button)
        elseif _procState.active[button] then
            HideGlow(button)
        end
    end

    local glowLayer = mod.TakeShell()
    glowLayer:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    glowLayer:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    glowLayer:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    glowLayer:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    glowLayer:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    glowLayer:RegisterEvent("SPELL_UPDATE_ICON")
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
            if not ident or not C_SpellActivationOverlay.IsSpellOverlayed(ident) then HideGlow(button) end
        end
        local blizz = IsBlizzStyle()
        for _, details in ipairs(BAR_CONFIG) do
            -- Dormant bars skip the IsSpellOverlayed walk; their show edge
            -- queues a rescan (ApplyBarDormancy), which runs after the
            -- dormancy map flipped, so a revealed bar is covered here.
            local buttonList = (not mod._eabBarDormant[details.key]) and barButtons[details.key] or nil
            if buttonList then
                for _, button in ipairs(buttonList) do
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
            local timePassed = GetTime() - _glowLastScan
            C_Timer_After(timePassed >= 0.25 and 0 or (0.25 - timePassed), GlowRescan)
        end
    end
    glowLayer:SetScript("OnEvent", function(_, evt, arg1)
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
                local timePassed = GetTime() - _glowLastScan
                C_Timer_After(timePassed >= 0.25 and 0 or (0.25 - timePassed), GlowRescan)
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
                    if not toHide then toHide = {} end
                    toHide[#toHide + 1] = button
                end
            end
            if toHide then
                for index = 1, #toHide do
                    HideGlow(toHide[index])
                end
            end
        else
            -- SHOW: scan all buttons for the matching spellID. Dormant bars
            -- skip (nobody can see the glow); the show-edge rescan restores
            -- any proc glow that is still live when the bar reveals.
            local blizz2 = IsBlizzStyle()
            for _, details in ipairs(BAR_CONFIG) do
                local buttonList = (not mod._eabBarDormant[details.key]) and barButtons[details.key] or nil
                if buttonList then
                    for _, button in ipairs(buttonList) do
                        if button and (EFD(button).squared or blizz2) then
                            local ident = GetButtonSpellID(button)
                            if ident and ident == arg1 then ShowGlow(button) end
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

    local function AssistCVarOn() return GetCVarBool and GetCVarBool("assistedCombatHighlight") end

    local function AssistCreate(button)
        local success, assistHighlight =
            pcall(CreateFrame, "Frame", nil, button, "ActionBarButtonAssistedCombatHighlightTemplate")
        if not success or not assistHighlight then return nil end
        assistHighlight:SetPoint("CENTER")
        -- Above the cooldown swipe, border frame, glowOverlay (+6) and proc
        -- alerts -- same margin the CDM twin uses.
        assistHighlight:SetFrameLevel(button:GetFrameLevel() + 15)
        -- Freeze on a single flipbook frame until we actually animate (in combat).
        if assistHighlight.Flipbook and assistHighlight.Flipbook.Anim then
            assistHighlight.Flipbook.Anim:Play()
            assistHighlight.Flipbook.Anim:Stop()
        end
        assistHighlight:Hide()
        return assistHighlight
    end

    -- The custom Assisted Highlight glows run on the shared glow engines with
    -- settings of their own (assistGlow*), never the Custom Proc Glow's.
    -- Their colour: the palette's class colour or the picked one; the one
    -- reader for the live buttons and the Animations page preview.
    mod._AssistCustomGlowColor = function()
        local profile = ABAR.db and ABAR.db.profile
        local color = profile and profile.assistGlowColor
        return _G_Glows.ResolveColor(
            _G_Glows.DeriveColorMode(nil, profile and profile.assistGlowUseClassColor),
            color and color.r,
            color and color.g,
            color and color.b,
            0.15,
            0.5,
            1
        )
    end

    mod._AssistCustomGlowStop = function(button)
        local frameData = EFD(button)
        local glowHolder = frameData.assistGlowWrapper
        if glowHolder then
            _G_Glows.StopAllGlows(glowHolder)
            glowHolder:Hide()
        end
    end

    mod._AssistCustomGlowStart = function(button, loopIdx, cr, cg, callback, buttonW, buttonH)
        local loopRec = LOOP_GLOW_TYPES[loopIdx]
        if not loopRec then
            mod._AssistCustomGlowStop(button)
            return false
        end

        local frameData = EFD(button)
        if not frameData.assistGlowWrapper then
            local glowHolder = CreateFrame("Frame", nil, button)
            glowHolder:SetAllPoints(button)
            frameData.assistGlowWrapper = glowHolder
        end

        local glowHolder = frameData.assistGlowWrapper
        glowHolder:SetAllPoints(button)
        glowHolder:SetFrameLevel(button:GetFrameLevel() + 15)
        glowHolder:SetAlpha(1)

        local holderData = EFD(glowHolder)
        if frameData.shapeMask and frameData.shapeApplied and frameData.shapeMaskPath then
            if not holderData.ownMask then holderData.ownMask = glowHolder:CreateMaskTexture() end
            holderData.ownMask:ClearAllPoints()
            Pix.Point(holderData.ownMask, "TOPLEFT", button, "TOPLEFT", 1, -1)
            Pix.Point(holderData.ownMask, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
            holderData.ownMask:SetTexture(
                frameData.shapeMaskPath,
                "CLAMPTOBLACKADDITIVE",
                "CLAMPTOBLACKADDITIVE"
            )
            holderData.ownMask:Show()
        elseif holderData.ownMask then
            holderData.ownMask:Hide()
        end

        _G_Glows.StopAllGlows(glowHolder)
        glowHolder:Show()

        _G_Glows.StartSpecGlow(
            glowHolder,
            { style = loopIdx, r = cr, g = cg, b = callback },
            buttonW,
            buttonH,
            "icon",
            {
                maskWith = holderData.ownMask and holderData.ownMask:IsShown() and holderData.ownMask or nil,
                maskPath = frameData.shapeMaskPath or SHAPE_MASKS[frameData.shapeName or ""],
                borderPath = SHAPE_BORDERS[frameData.shapeName or ""],
                shapeMask = frameData.shapeMask,
                anchorFrame = button,
            }
        )
        return true
    end

    -- Ring teardown alone. Split out of AssistHide because AssistShow also
    -- needs it on its own: with the overlay style picked, or with Blizzard
    -- painting its own ring on a hovered button, our ring must go while the
    -- overlay stays up.
    mod._AssistRingHide = function(button)
        local assistHighlight = EFD(button).assistHL
        if not assistHighlight then return end
        if assistHighlight.Flipbook and assistHighlight.Flipbook.Anim then
            assistHighlight.Flipbook.Anim:Stop()
        end
        assistHighlight:Hide()
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
        local frameData = EFD(button)
        local shade = frameData.assistOverlay
        if not look or look == 1 then
            if shade then shade:Hide() end
            return
        end
        local profile = ABAR.db and ABAR.db.profile
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
            frameData.assistOverlay = shade
        end
        -- Footprint. Alone (style 2) the tint covers exactly the button. Under
        -- the ring (style 3) it grows or shrinks with the ring's outset so the
        -- two end flush -- the tint never sticks out past the ring, which is
        -- what a negative outset would otherwise produce. With Fit Ring to
        -- Cropped Buttons fitting the ring (ns._AssistFit), the tint takes the
        -- same top and bottom pull-in so the two stay flush. Change-guarded: the
        -- rescan runs several times a second while a suggestion is up.
        local pad = (look == 3) and ((profile and profile.assistGlowOutset) or 0) or 0
        local padY = pad
        if look == 3 and frameData.cropped and profile and profile.assistGlowFitCropped then
            padY = pad - mod._ASSIST_CROP_TRIM / 2
        end
        local overlayData = EFD(shade)
        if overlayData.pad ~= pad or overlayData.padY ~= padY then
            overlayData.pad, overlayData.padY = pad, padY
            shade:ClearAllPoints()
            shade:SetPoint("TOPLEFT", button, "TOPLEFT", -pad, padY)
            shade:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", pad, -padY)
        end
        -- Re-assert: bar layout can change the button's frame level after create.
        shade:SetFrameLevel(button:GetFrameLevel() + 14)
        local color = (profile and profile.assistGlowOverlayColor) or { r = 0.15, g = 0.5, b = 1 }
        local a = (profile and profile.assistGlowOverlayAlpha) or 30
        shade.tex:SetColorTexture(color.r or 0.15, color.g or 0.5, color.b or 1, a / 100)
        -- Custom button shapes win over the rounded corners: a circle mask must
        -- not end up as a rounded square. Keyed on the mask OBJECT, not a
        -- boolean -- a shape change swaps the mask, and the stale one has to be
        -- removed before the new one goes on. Applied to the tint texture
        -- directly rather than via MaskFrameTextures: that walks GetRegions(),
        -- which here would also hand the mask to our own roundMask region.
        local wanted = (frameData.shapeMask and frameData.shapeApplied) and frameData.shapeMask
            or shade.roundMask
        if overlayData.shapeMasked ~= wanted then
            if overlayData.shapeMasked then
                pcall(shade.tex.RemoveMaskTexture, shade.tex, overlayData.shapeMasked)
            end
            pcall(shade.tex.AddMaskTexture, shade.tex, wanted)
            overlayData.shapeMasked = wanted
        end
        shade:Show()
    end

    -- Full teardown of everything we paint for one button. Also un-fades
    -- Blizzard's own ring: the overlay-only style parks it at alpha 0, and a
    -- button that stops being the suggestion (or the CVar going off) must not
    -- leave it invisible for whoever shows it next.
    local function AssistHide(button)
        local frameData = EFD(button)
        if frameData.assistCustomActive then
            mod._AssistCustomGlowStop(button)
            frameData.assistCustomActive = nil
            frameData.assistCustomType = nil
            frameData.assistCustomMask = nil
            frameData.assistCustomShapeMask = nil
            frameData.assistCustomW, frameData.assistCustomH = nil, nil
            frameData.assistCustomR, frameData.assistCustomG, frameData.assistCustomB = nil, nil, nil
        end
        mod._AssistRingHide(button)
        mod._AssistOverlay(button)
        local bf = button.AssistedCombatHighlightFrame
        if bf then bf:SetAlpha(1) end
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
        local profile = ABAR.db and ABAR.db.profile
        local outset = (profile and profile.assistGlowOutset) or 0
        local s = (wid + outset * 2) / 45
        if s < 0.05 then s = 0.05 end
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
    mod._AssistFit = function(button, ringTex, cropped)
        local profile = ABAR.db and ABAR.db.profile
        local ringData = mod._eabFD[ringTex]
        if not (cropped and profile and profile.assistGlowFitCropped) then
            if ringData and ringData.fitW then
                ringData.fitW, ringData.fitH = nil, nil
                ringTex:SetSize(ringData.origW, ringData.origH)
                local fb = ringTex.Flipbook
                if fb and ringData.fbW then fb:SetSize(ringData.fbW, ringData.fbH) end
            end
            return false
        end
        ringData = EFD(ringTex)
        local fb = ringTex.Flipbook
        if not ringData.origW then
            ringData.origW, ringData.origH = ringTex:GetSize()
            if fb then
                ringData.fbW, ringData.fbH = fb:GetSize()
            end
        end
        local outset = profile.assistGlowOutset or 0
        local wid = button:GetWidth() + outset * 2
        local hgt = button:GetHeight() + outset * 2 - mod._ASSIST_CROP_TRIM
        if wid < 1 then wid = 1 end
        if hgt < 1 then hgt = 1 end
        if ringTex:GetScale() ~= 1 then ringTex:SetScale(1) end
        if ringData.fitW ~= wid or ringData.fitH ~= hgt then
            ringData.fitW, ringData.fitH = wid, hgt
            ringTex:SetSize(wid, hgt)
            if fb and ringData.fbW and ringData.origW > 0 and ringData.origH > 0 then
                fb:SetSize(ringData.fbW * wid / ringData.origW, ringData.fbH * hgt / ringData.origH)
            end
        end
        return true
    end

    -- Paint the suggestion on one button in whatever style the user picked.
    -- Owns the "Blizzard already draws its own ring here" case too (it used to
    -- live at the call site): the overlay is ours either way, so the two
    -- decisions have to be made together.
    local function AssistShow(button)
        local frameData = EFD(button)
        local profile = ABAR.db and ABAR.db.profile
        local customKind = (profile and profile.assistGlowType) or 0
        if customKind < 1 or customKind > #LOOP_GLOW_TYPES or not LOOP_GLOW_TYPES[customKind] then
            customKind = 0
        end

        if customKind > 0 and _assistInCombat then
            if frameData.shapeMask and frameData.shapeApplied then
                for si, record in ipairs(LOOP_GLOW_TYPES) do
                    if record.shapeGlow then
                        customKind = si
                        break
                    end
                end
            end
            local shade = frameData.assistOverlay
            if shade and shade:IsShown() then mod._AssistOverlay(button) end
            local assistHighlight = frameData.assistHL
            if assistHighlight and assistHighlight:IsShown() then mod._AssistRingHide(button) end

            local bf = button.AssistedCombatHighlightFrame
            if bf then bf:SetAlpha(0) end

            local cr, cg, callback = mod._AssistCustomGlowColor()
            local buttonW, buttonH = button:GetWidth() or 45, button:GetHeight() or 45
            if
                frameData.assistCustomActive
                and frameData.assistCustomType == customKind
                and frameData.assistCustomW == buttonW
                and frameData.assistCustomH == buttonH
                and frameData.assistCustomMask == frameData.shapeMaskPath
                and frameData.assistCustomShapeMask == frameData.shapeMask
                and frameData.assistCustomR == cr
                and frameData.assistCustomG == cg
                and frameData.assistCustomB == callback
                and frameData.assistGlowWrapper
                and frameData.assistGlowWrapper:IsShown()
            then
                return
            end

            if mod._AssistCustomGlowStart(button, customKind, cr, cg, callback, buttonW, buttonH) then
                frameData.assistCustomActive = true
                frameData.assistCustomType = customKind
                frameData.assistCustomW, frameData.assistCustomH = buttonW, buttonH
                frameData.assistCustomMask = frameData.shapeMaskPath
                frameData.assistCustomShapeMask = frameData.shapeMask
                frameData.assistCustomR, frameData.assistCustomG, frameData.assistCustomB = cr, cg, callback
            end
            return
        end

        if frameData.assistCustomActive then
            mod._AssistCustomGlowStop(button)
            frameData.assistCustomActive = nil
            frameData.assistCustomType = nil
            frameData.assistCustomMask = nil
            frameData.assistCustomShapeMask = nil
            frameData.assistCustomW, frameData.assistCustomH = nil, nil
            frameData.assistCustomR, frameData.assistCustomG, frameData.assistCustomB = nil, nil, nil
            local bf = button.AssistedCombatHighlightFrame
            if bf then bf:SetAlpha(1) end
        end

        local look = (profile and profile.assistGlowStyle) or 1
        -- A custom glow runs in combat only: outside it, Blizzard's frozen ring.
        if customKind > 0 or look == 0 then look = 1 end

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
            if frameData.squared and not mod._AssistFit(button, bf, frameData.cropped) then
                local s = mod._AssistScale(button)
                if bf:GetScale() ~= s then bf:SetScale(s) end
            end
            return
        end

        if look == 2 then
            mod._AssistRingHide(button)
            return
        end

        local assistHighlight = frameData.assistHL
        if not assistHighlight then
            assistHighlight = AssistCreate(button)
            if not assistHighlight then return end
            frameData.assistHL = assistHighlight
        end
        if not mod._AssistFit(button, assistHighlight, frameData.cropped) then
            assistHighlight:SetScale(mod._AssistScale(button))
        end
        -- Re-assert: bar layout can change the button's frame level after create.
        assistHighlight:SetFrameLevel(button:GetFrameLevel() + 15)
        assistHighlight:Show()
        if assistHighlight.Flipbook and assistHighlight.Flipbook.Anim then
            if _assistInCombat then
                assistHighlight.Flipbook.Anim:Play()
            else
                assistHighlight.Flipbook.Anim:Stop()
            end
        end
    end

    -- The (spell) id a button currently represents, mirroring
    -- AssistedCombatManager:GetActionButtonSpellForAssistedHighlight.
    -- Attribute first: secure paging writes "action", the authoritative slot
    -- (see ForceCooldownPaint); btn.action is a derived mirror.
    local function ButtonSpell(button)
        local action = button.GetAttribute and button:GetAttribute("action")
        if action == nil then action = button.action end
        if action == nil then return nil end
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
                    local buttonList = barButtons[details.key]
                    if buttonList then
                        for index = 1, #buttonList do
                            local button = buttonList[index]
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
            if not newSet[button] then AssistHide(button) end
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
        if _assistRescanPending then return end
        _assistRescanPending = true
        local timePassed = GetTime() - _assistLastScan
        local delay = (timePassed >= 0.15) and 0 or (0.15 - timePassed)
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
        local profile = ABAR.db and ABAR.db.profile
        local repaint = changed and ((profile and profile.assistGlowType) or 0) > 0
        for button in pairs(_assistGlowed) do
            if repaint then AssistShow(button) end
            local assistHighlight = EFD(button).assistHL
            if
                assistHighlight
                and assistHighlight:IsShown()
                and assistHighlight.Flipbook
                and assistHighlight.Flipbook.Anim
            then
                if _assistInCombat then
                    if not assistHighlight.Flipbook.Anim:IsPlaying() then
                        assistHighlight.Flipbook.Anim:Play()
                    end
                else
                    if assistHighlight.Flipbook.Anim:IsPlaying() then assistHighlight.Flipbook.Anim:Stop() end
                end
            end
        end
        -- Blizzard's rotation swirl needs no combat gating: the
        -- UpdateAssistedCombatRotationFrame hook keeps it permanently hidden and
        -- the script-free spinner (ns.EnsureAssistSpinner) costs no Lua ever.
    end

    local function InstallAssistHook()
        if _assistHookInstalled then return end
        _assistHookInstalled = true
        SyncAssistCombat()
        if EventRegistry and EventRegistry.RegisterCallback then
            -- No hooksecurefunc on UpdateAllAssistedHighlightFramesForSpell:
            -- the manager calls it then fires this event right after, so a
            -- hook would run the full walk twice per suggestion change.
            EventRegistry:RegisterCallback(
                "AssistedCombatManager.OnAssistedHighlightSpellChange",
                function() QueueAssistRescan() end,
                "EAB_AssistHighlight"
            )
            -- Fires when the assistedCombatHighlight CVar is toggled at runtime.
            EventRegistry:RegisterCallback(
                "AssistedCombatManager.OnSetUseAssistedHighlight",
                function() QueueAssistRescan() end,
                "EAB_AssistHighlight_CVar"
            )
            -- Page swaps / drags / hover re-candidacy: the suggestion may not
            -- change, but which button holds it (or whether Blizzard shows its
            -- own frame on a hovered button) does. Same signal Blizzard uses.
            EventRegistry:RegisterCallback(
                "ActionButton.OnActionChanged",
                function() QueueAssistRescan() end,
                "EAB_AssistHighlight_Action"
            )
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
        local buttonList = barButtons[details.key]
        if buttonList then
            for index = 1, #buttonList do
                local button = buttonList[index]
                if button and _procState.active[button] then UpdateFlipbook(button) end
            end
        end
    end
end

function ABAR:ScanExistingProcs()
    local found = 0
    local sum = 0
    local blizz = mod.AB_Style() ~= "cui"
    for _, details in ipairs(BAR_CONFIG) do
        local buttonList = barButtons[details.key]
        if buttonList then
            for index = 1, #buttonList do
                local button = buttonList[index]
                if button and (EFD(button).squared or blizz) then
                    sum = sum + 1
                    local spellId = _procState.GetButtonSpellID(button)
                    local ISO = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
                    local overlayed = spellId and ISO and ISO(spellId)
                    if not overlayed and spellId and ISO then
                        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                            local ovr = C_SpellBook.FindSpellOverrideByID(spellId)
                            if ovr and ovr > 0 and ovr ~= spellId then overlayed = ISO(ovr) end
                        end
                        if not overlayed and C_Spell and C_Spell.GetBaseSpell then
                            local baseLevel = C_Spell.GetBaseSpell(spellId)
                            if baseLevel and baseLevel > 0 and baseLevel ~= spellId then
                                overlayed = ISO(baseLevel)
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
    local _, class = UnitClass("player")
    local color = RAID_CLASS_COLORS[class]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

local function ResolveCooldownEdgeColor(profile)
    if profile.cooldownEdgeUseClassColor then
        local cr, cg, callback = GetClassColor()
        local color = profile.cooldownEdgeColor or { a = 1 }
        return cr, cg, callback, color.a or 1
    end
    local color = profile.cooldownEdgeColor or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    return color.r, color.g, color.b, color.a
end

local function ApplySingleCooldownEdge(cooldownFrame, edgeSize, cr, cg, callback, ca)
    if not cooldownFrame then return end
    if cooldownFrame:IsForbidden() then return end
    if cooldownFrame.SetEdgeTexture then cooldownFrame:SetEdgeTexture(EDGE_TEXTURE) end
    if cooldownFrame.SetEdgeScale then cooldownFrame:SetEdgeScale(edgeSize) end
    if cooldownFrame.SetEdgeColor then cooldownFrame:SetEdgeColor(cr, cg, callback, ca) end
end

-- After applying edge cosmetics, enforce shape-based edge visibility. Must be called
-- after ApplySingleCooldownEdge since SetEdgeTexture may re-enable drawing.
local function EnforceShapeEdgeSingle(cd, edgeScale, useCircular)
    if not cd or cd:IsForbidden() then return end
    if cd.SetEdgeTexture then pcall(cd.SetEdgeTexture, cd, EDGE_TEXTURE) end
    if cd.SetUseCircularEdge then pcall(cd.SetUseCircularEdge, cd, useCircular) end
    if cd.SetEdgeScale then pcall(cd.SetEdgeScale, cd, edgeScale) end
end

local function EnforceShapeEdge(button)
    local efd = EFD(button)
    if not button or not efd.shapeApplied then return end
    local shapeName = efd.shapeName
    if not shapeName then return end
    local edgeScale = SHAPE_EDGE_SCALES[shapeName] or 0.60
    local useCircular = (shapeName ~= "square" and shapeName ~= "csquare")
    EnforceShapeEdgeSingle(button.cooldown, edgeScale, useCircular)
    EnforceShapeEdgeSingle(button.chargeCooldown, edgeScale, useCircular)
end

local function ApplyButtonCooldownEdge(button, edgeSize, cr, cg, callback, ca)
    -- Square/csquare use the user's edge size; other shapes force 1.0
    -- since EnforceShapeEdge will override with per-shape scale anyway.
    local efd = EFD(button)
    local sn = efd.shapeApplied and efd.shapeName
    local sz = edgeSize
    if sn and sn ~= "square" and sn ~= "csquare" then sz = 1.0 end
    ApplySingleCooldownEdge(button.cooldown, sz, cr, cg, callback, ca)
    ApplySingleCooldownEdge(button.chargeCooldown, sz, cr, cg, callback, ca)
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
    local profile = ABAR.db and ABAR.db.profile
    if not profile then
        wipe(_cdEdge.pending)
        _cdEdge.pendingCount = 0
        return
    end
    local cr, cg, callback, ca = ResolveCooldownEdgeColor(profile)
    local baseSz = profile.cooldownEdgeSize or 2.1
    for cooldownFrame, button in pairs(_cdEdge.pending) do
        if cooldownFrame and not cooldownFrame:IsForbidden() then
            local sz = baseSz
            local buttonData = EFD(button)
            local sn = buttonData.shapeApplied and buttonData.shapeName
            if sn and sn ~= "square" and sn ~= "csquare" then sz = 1.0 end
            ApplySingleCooldownEdge(cooldownFrame, sz, cr, cg, callback, ca)
            if buttonData.shapeMaskPath and buttonData.shapeApplied then
                local mask = buttonData.shapeMask
                if mask then
                    pcall(cooldownFrame.RemoveMaskTexture, cooldownFrame, mask)
                    pcall(cooldownFrame.AddMaskTexture, cooldownFrame, mask)
                end
                if cooldownFrame.SetSwipeTexture then
                    pcall(cooldownFrame.SetSwipeTexture, cooldownFrame, buttonData.shapeMaskPath)
                end
            end
            EnforceShapeEdge(button)
            EFD(cooldownFrame).edgeDone = true
        end
    end
    wipe(_cdEdge.pending)
    _cdEdge.pendingCount = 0
end

local function HookButtonCooldownEdge(button)
    if not button or not EFD(button).squared then return end
    if EFD(button).cdEdgeHooked then return end
    EFD(button).cdEdgeHooked = true

    local function OnSetCooldown(cooldownFrame)
        -- Cooldown edge patch (skip if edge was already applied to this frame)
        if cooldownFrame and not EFD(cooldownFrame).edgeDone then
            if not _cdEdge.pending[cooldownFrame] then _cdEdge.pendingCount = _cdEdge.pendingCount + 1 end
            _cdEdge.pending[cooldownFrame] = button
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
    if not button or EFD(button).cdFontsHooked then return end
    EFD(button).cdFontsHooked = true
    -- Piggybacks on HookButtonCooldownEdge rather than a second hooksecurefunc
    -- on the same SetCooldown: that hook already fires on every SetCooldown and
    -- queues the font patch. If it has not run yet, it picks fonts up when it does.
end

local function HookCooldownEdge()
    if _cdEdge.hooked then return end
    _cdEdge.hooked = true
    for _, details in ipairs(BAR_CONFIG) do
        local buttonList = barButtons[details.key]
        if buttonList then
            for index = 1, #buttonList do
                local button = buttonList[index]
                if button and EFD(button).squared then HookButtonCooldownEdge(button) end
            end
        end
    end
end

function ABAR:ApplyCooldownEdge()
    if not self.db.profile.squareIcons then return end
    HookCooldownEdge()
    local profile = self.db.profile
    local cr, cg, callback, ca = ResolveCooldownEdgeColor(profile)
    local sz = profile.cooldownEdgeSize or 2.1
    for _, details in ipairs(BAR_CONFIG) do
        local buttonList = barButtons[details.key]
        if buttonList then
            for index = 1, #buttonList do
                local button = buttonList[index]
                if button and EFD(button).squared then
                    -- Clear edge cache so the hook re-applies on next cooldown
                    if button.cooldown then EFD(button.cooldown).edgeDone = nil end
                    if button.chargeCooldown then EFD(button.chargeCooldown).edgeDone = nil end
                    ApplyButtonCooldownEdge(button, sz, cr, cg, callback, ca)
                end
            end
        end
    end
end

function EAB_VTABLE.CooldownFonts.HookAll()
    for _, details in ipairs(BAR_CONFIG) do
        local buttonList = barButtons[details.key]
        if buttonList then
            for index = 1, #buttonList do
                local button = buttonList[index]
                if button then EAB_VTABLE.CooldownFonts.HookButton(button) end
            end
        end
    end
end

function ABAR:ApplyMiscTextures()
    local profile = self.db.profile

    -- Color the "other" button textures (CheckedTexture, NewActionTexture,
    -- Border) using the pushed texture color settings.  These are the
    -- hard-coded textures the user can't individually customize.
    local useCC = profile.pushedUseClassColor
    local customC = profile.pushedCustomColor or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    local cr, cg, callback, ca = customC.r, customC.g, customC.b, customC.a or 1
    if useCC then
        local _, classTok = UnitClass("player")
        if classTok then
            local cc = RAID_CLASS_COLORS[classTok]
            if cc then
                cr, cg, callback = cc.r, cc.g, cc.b
            end
        end
    end
    for _, details in ipairs(BAR_CONFIG) do
        local buttonList = barButtons[details.key]
        if buttonList then
            for index = 1, #buttonList do
                local button = buttonList[index]
                if button and EFD(button).squared then
                    -- Do NOT color CheckedTexture or Border Blizzard uses
                    -- these for item rarity borders (green/blue/purple) on
                    -- active trinkets / equipped items.
                    if button.NewActionTexture then
                        button.NewActionTexture:SetDesaturated(true)
                        button.NewActionTexture:SetVertexColor(cr, cg, callback, ca)
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
    local profile = self.db.profile
    if profile.showCastHighlight == false then return 0 end
    if barId and profile.castHighlightBorder and mod._ixElig[barId] then return 0 end
    return 1
end

function ABAR:ApplyCheckedTextures()
    local profile = self.db.profile
    local _, _, ixOn = mod._ixRolesOn(profile)
    local ixEver = mod._ixEver
    for _, details in ipairs(BAR_CONFIG) do
        local buttonList = barButtons[details.key]
        if buttonList then
            local s = profile.bars[details.key]
            -- Eligibility first: GetCheckedAlpha reads it.
            local ixBar = ixOn and mod._ixBarEligible(details.key)
            local a = self:GetCheckedAlpha(details.key)
            for index = 1, #buttonList do
                local button = buttonList[index]
                if button and button.CheckedTexture then button.CheckedTexture:SetAlpha(a) end
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
            local buttonList = barButtons[details.key]
            if buttonList then
                for _, button in ipairs(buttonList) do
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
