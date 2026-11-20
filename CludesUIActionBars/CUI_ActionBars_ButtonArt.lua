if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBars_ButtonArt.lua
--
--  Button appearance: stripping the stock art, the classic button art, the
--  button borders and the shape masks. Loads right after
--  CUI_ActionBars_Setup.lua, reads the main file through ns only, and hands
--  its entry points to the files after it through ns._internals (bottom of
--  this file).
-------------------------------------------------------------------------------
local _, mod = ...

local ipairs, pcall = ipairs, pcall
local max = math.max
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After
local Pix = CludesUI.PP
local EFD = mod.EFD

local ABAR, EAB_VTABLE = mod.EAB, mod.EAB_VTABLE
local HIGHLIGHT_TEXTURES, ResolveBorderThickness, ButtonHasAction =
    mod.HIGHLIGHT_TEXTURES, mod.ResolveBorderThickness, mod.ButtonHasAction
local SHAPE_MASKS, SHAPE_BORDERS, SHAPE_INSETS = mod.SHAPE_MASKS, mod.SHAPE_BORDERS, mod.SHAPE_INSETS
local SHAPE_ZOOM_DEFAULTS, SHAPE_ICON_EXPAND, SHAPE_ICON_EXPAND_OFFSETS =
    mod.SHAPE_ZOOM_DEFAULTS, mod.SHAPE_ICON_EXPAND, mod.SHAPE_ICON_EXPAND_OFFSETS
local Inner = mod._internals
local SHAPE_EDGE_SCALES, _quickKeybindState, HideSlotArt =
    Inner.SHAPE_EDGE_SCALES, Inner._quickKeybindState, Inner.HideSlotArt

-------------------------------------------------------------------------------
--  Visual Customization Button Appearance
-------------------------------------------------------------------------------
local function HideSelfDeferred(self)
    -- Reuse a cached closure per frame to avoid allocation on every OnShow
    local frameData = EFD(self)
    if not frameData.hideFn then
        frameData.hideFn = function()
            if self and not self:IsForbidden() then
                self:Hide()
            end
        end
    end
    C_Timer_After(0, frameData.hideFn)
end

local function HideBorder(btnFrame)
    if btnFrame.NormalTexture then
        btnFrame.NormalTexture:Hide()
        btnFrame.NormalTexture:SetAlpha(0)
    end
    if btnFrame.Border then
        -- Equipped Item Color (Effects > Item Information) keeps Blizzard's
        -- equipped-item border, in our square art; its shown state stays
        -- with the updates.
        if ABAR.db.profile.showEquippedBorder then
            mod.AB_EquippedBorderLook(btnFrame.Border, btnFrame)
        else
            btnFrame.Border:Hide()
            btnFrame.Border:SetAlpha(0)
        end
    end
    if btnFrame.icon and btnFrame.IconMask then
        btnFrame.icon:RemoveMaskTexture(btnFrame.IconMask)
        -- Neutralize IconMask: UpdateButtonArt re-applies it via
        -- icon:AddMaskTexture on combat transitions, page changes, etc.
        btnFrame.IconMask:Hide()
        btnFrame.IconMask:SetTexture(nil)
        btnFrame.IconMask:ClearAllPoints()
        btnFrame.IconMask:SetSize(0.001, 0.001)
    end
end

local function SetSquareTexture(tex, texPath)
    if not tex then
        return
    end
    tex:SetAtlas(nil)
    tex:SetTexture(texPath)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:ClearAllPoints()
    tex:SetAllPoints(tex:GetParent())
end

-- Equipped Item Color (Effects > Item Information, profile.showEquippedBorder):
-- Blizzard's equipped-item border on a square button, in our square highlight
-- art and the equipped item's rarity color (Blizzard's own green at half
-- opacity when the item cannot be found). The art swap fires the Border's
-- SetAtlas hook (MakeButtonSquare) again, which `busy` turns away.
do
    local busy = false
    local IsEquippedAction, GetActionTexture = C_ActionBar.IsEquippedAction, C_ActionBar.GetActionTexture

    -- Rarity of the equipped item an action holds, read from the slot that
    -- holds it (an item's quality can differ from its base record): an item
    -- action by its ID, anything else (a macro) by its icon.
    local function EquippedQuality(action)
        local aType, ident = GetActionInfo(action)
        local isItem = aType == "item" and ident
        local tex = not isItem and GetActionTexture(action)
        if not (isItem or tex) then
            return
        end
        for slot = 1, 19 do
            local hit
            if isItem then
                hit = GetInventoryItemID("player", slot) == ident
            else
                hit = GetInventoryItemTexture("player", slot) == tex
            end
            if hit then
                return GetInventoryItemQuality("player", slot)
            end
        end
        if isItem then
            return C_Item.GetItemQualityByID(ident)
        end
    end

    function mod.AB_EquippedBorderLook(edge, buttonFrame)
        if busy then
            return
        end
        busy = true
        SetSquareTexture(edge, HIGHLIGHT_TEXTURES[1])
        busy = false
        local a = buttonFrame and buttonFrame:GetAttribute("action")
        local q = a and IsEquippedAction(a) and EquippedQuality(a)
        if q then
            local red, green, blue = C_Item.GetItemQualityColor(q)
            edge:SetVertexColor(red, green, blue, 1)
        else
            edge:SetVertexColor(0, 1, 0, 0.5)
        end
        edge:SetAlpha(1)
    end

    -- The equipped-item Border from live slot contents, for every path that
    -- changes what a button holds (slot changes, page flips, bar reveals,
    -- setup). Our square buttons show it only with Equipped Item Color
    -- on; the Blizzard and Classic styles keep Blizzard's own look.
    function mod.AB_SyncEquippedBorder(buttonFrame, action)
        local edge = buttonFrame.Border
        if not edge then
            return
        end
        local frameData = mod._eabFD[buttonFrame]
        local square = frameData and frameData.squared
        if square and not ABAR.db.profile.showEquippedBorder then
            return
        end
        local on = action and IsEquippedAction(action) and true or false
        if square and on then
            mod.AB_EquippedBorderLook(edge, buttonFrame)
        end
        edge:SetShown(on)
    end
end

-------------------------------------------------------------------------------
--  Classic WoW UI button art (ns.AB_Style() == "classic")
--  The vanilla 36-button ring on a button, scaled by the button's own size:
--  NormalTexture UI-Quickslot2 (66/36 of the button, CENTER 0,-1/36), or
--  UI-Quickslot on an empty slot; PushedTexture UI-Quickslot-Depress over the
--  button; HighlightTexture ButtonHilight-Square ADD; CheckedTexture
--  CheckButtonHilight ADD; equipped Border UI-ActionButton-Border ADD (62/36,
--  CENTER 0,1/36). Square icon with full art: the stock IconMask is
--  neutralised the way HideBorder does it, the stock slot background kept
--  transparent, the cooldown swipe spans the icon. Idempotent: a layout pass
--  re-runs it per native size (our buttons' UpdateButtonArt is a noop, so
--  nothing of Blizzard's repaints the ring behind it).
-------------------------------------------------------------------------------
mod.AB_CLASSIC = {
    slot = "Interface\\Buttons\\UI-Quickslot2",
    empty = "Interface\\Buttons\\UI-Quickslot",
    pushed = "Interface\\Buttons\\UI-Quickslot-Depress",
    hilight = "Interface\\Buttons\\ButtonHilight-Square",
    checked = "Interface\\Buttons\\CheckButtonHilight",
    equipped = "Interface\\Buttons\\UI-ActionButton-Border",
}

-- Slot ring or empty-slot art on the NormalTexture. Memo per button: the
-- content edges (slot change, page flip) cost one comparison when unchanged.
function mod.AB_ClassicSlotRing(buttonFrame, filled)
    filled = filled and true or false
    local frameData = EFD(buttonFrame)
    if frameData.classicFilled == filled then
        return
    end
    frameData.classicFilled = filled
    local normalTex = buttonFrame.NormalTexture
    if normalTex then
        normalTex:SetTexture(filled and mod.AB_CLASSIC.slot or mod.AB_CLASSIC.empty)
        normalTex:SetTexCoord(0, 1, 0, 1)
    end
end

-- Plain Blizzard Style on the Forever client: the border the template's
-- OnLoad left on our button's NormalTexture (IconFrame-AddRow, as our
-- buttons have no .bar; IconFrame on a bar-art button) is redrawn once from
-- its retail sheet, where the client's atlas would draw Forever art.
function mod.AB_StockNormal(buttonFrame)
    local frameData = EFD(buttonFrame)
    if frameData.stockNT then
        return
    end
    frameData.stockNT = true
    if mod.AB_Forever() then
        return
    end
    local normalTex = buttonFrame.NormalTexture
    local a = normalTex and normalTex:GetAtlas()
    if not a then
        return
    end
    local l = strlower(a)
    if l == "ui-hud-actionbar-iconframe-addrow" or l == "ui-hud-actionbar-iconframe" then
        CludesUI.StockAtlas(normalTex, a)
    end
end

-- Paints the whole kit on `btn` for a `w` x `h` button (its own size when
-- omitted). Our bar buttons pass their native size; flyout buttons pass none.
function mod.AB_PaintClassicButton(buttonFrame, wid, hgt)
    local frameData = EFD(buttonFrame)
    local art = mod.AB_CLASSIC
    if not wid then
        wid, hgt = buttonFrame:GetSize()
    end
    if not wid or wid <= 0 then
        wid = 45
    end
    if not hgt or hgt <= 0 then
        hgt = wid
    end
    local sw, sh = wid / 36, hgt / 36
    local iconTex = buttonFrame.icon
    if iconTex then
        if buttonFrame.IconMask then
            iconTex:RemoveMaskTexture(buttonFrame.IconMask)
            buttonFrame.IconMask:Hide()
            buttonFrame.IconMask:SetTexture(nil)
            buttonFrame.IconMask:ClearAllPoints()
            buttonFrame.IconMask:SetSize(0.001, 0.001)
        end
        iconTex:SetTexCoord(0, 1, 0, 1)
    end
    -- The 12.1 rounded slot background stays transparent (the square ring
    -- below is the slot); alpha, so Blizzard's own art passes keep working.
    if buttonFrame.SlotBackground then
        buttonFrame.SlotBackground:SetAlpha(0)
    end
    if buttonFrame.cooldown then
        buttonFrame.cooldown:ClearAllPoints()
        buttonFrame.cooldown:SetAllPoints(buttonFrame)
    end
    -- Seeded from the same source the content edges use (the action
    -- attribute); buttons without one (flyout popups) ask the mixin.
    if frameData.classicFilled == nil then
        local a = buttonFrame.GetAttribute and buttonFrame:GetAttribute("action")
        if a then
            frameData.classicFilled = HasAction(a) and true or false
        else
            frameData.classicFilled = ButtonHasAction(buttonFrame) and true or false
        end
    end
    local normalTex = buttonFrame.NormalTexture
    if normalTex then
        normalTex:SetAtlas(nil)
        normalTex:SetTexture(frameData.classicFilled and art.slot or art.empty)
        normalTex:SetTexCoord(0, 1, 0, 1)
        normalTex:ClearAllPoints()
        normalTex:SetPoint("CENTER", buttonFrame, "CENTER", 0, -sh)
        normalTex:SetSize(66 * sw, 66 * sh)
    end
    local pushedTex = buttonFrame.PushedTexture
    if pushedTex then
        pushedTex:SetAtlas(nil)
        pushedTex:SetTexture(art.pushed)
        pushedTex:SetTexCoord(0, 1, 0, 1)
        pushedTex:SetDrawLayer("OVERLAY", 7)
        pushedTex:ClearAllPoints()
        pushedTex:SetAllPoints(buttonFrame)
        pushedTex:SetVertexColor(1, 1, 1, 1)
        pushedTex:SetAlpha(1)
    end
    local highlightTex = buttonFrame.HighlightTexture
    if highlightTex then
        highlightTex:SetAtlas(nil)
        highlightTex:SetTexture(art.hilight)
        highlightTex:SetTexCoord(0, 1, 0, 1)
        highlightTex:SetBlendMode("ADD")
        highlightTex:ClearAllPoints()
        highlightTex:SetAllPoints(buttonFrame)
    end
    local countText = buttonFrame.CheckedTexture
    if countText then
        countText:SetAtlas(nil)
        countText:SetTexture(art.checked)
        countText:SetTexCoord(0, 1, 0, 1)
        countText:SetBlendMode("ADD")
        countText:ClearAllPoints()
        countText:SetAllPoints(buttonFrame)
    end
    local edge = buttonFrame.Border
    if edge then
        edge:SetAtlas(nil)
        edge:SetTexture(art.equipped)
        edge:SetTexCoord(0, 1, 0, 1)
        edge:SetBlendMode("ADD")
        edge:ClearAllPoints()
        edge:SetPoint("CENTER", buttonFrame, "CENTER", 0, sh)
        edge:SetSize(62 * sw, 62 * sh)
    end
    frameData.classicArt = true
end

_quickKeybindState.art.ApplyButtonHighlight = function(buttonFrame)
    local tex = buttonFrame and buttonFrame.QuickKeybindHighlightTexture
    if not tex then
        return
    end

    local p = ABAR and ABAR.db and ABAR.db.profile
    local useCC = p and p.highlightUseClassColor
    local customC = (p and p.highlightCustomColor) or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    local cr, cg, callback = customC.r, customC.g, customC.b
    if useCC then
        local _, countText = UnitClass("player")
        if countText then
            local cc = RAID_CLASS_COLORS[countText]
            if cc then
                cr, cg, callback = cc.r, cc.g, cc.b
            end
        end
    end

    -- QuickKeybind manages hover/idle opacity itself. We only replace the
    -- Blizzard atlas with CUI's square highlight art and matching color.
    SetSquareTexture(tex, HIGHLIGHT_TEXTURES[1])
    tex:SetVertexColor(cr, cg, callback, 1)
end

_quickKeybindState.art.RefreshButton = function(buttonFrame, show)
    if not buttonFrame or buttonFrame:IsForbidden() then
        return
    end
    _quickKeybindState.art.ApplyButtonHighlight(buttonFrame)
    if show ~= nil then
        _quickKeybindState.art.ApplyButtonHighlightAlpha(buttonFrame, show)
    end
end

_quickKeybindState.art.InitializeButton = function(buttonFrame, show)
    _quickKeybindState.art.RefreshButton(buttonFrame, show)
    _quickKeybindState.art.HookButton(buttonFrame)
end

_quickKeybindState.art.HookButton = function(buttonFrame)
    if not buttonFrame or buttonFrame:IsForbidden() or EFD(buttonFrame).quickKeybindArtHooked then
        return
    end
    if buttonFrame.QuickKeybindHighlightTexture and buttonFrame.DoModeChange then
        hooksecurefunc(buttonFrame, "DoModeChange", function(self, isInQuickbindMode)
            _quickKeybindState.art.RefreshButton(self, isInQuickbindMode)
        end)
        EFD(buttonFrame).quickKeybindArtHooked = true
    end
end

_quickKeybindState.art.ApplyButtonHighlightAlpha = function(buttonFrame, show)
    local tex = buttonFrame and buttonFrame.QuickKeybindHighlightTexture
    if not tex then
        return
    end

    if show then
        local idleAlpha = 0.5
        if buttonFrame.IsMouseOver and buttonFrame:IsMouseOver() then
            tex:SetAlpha(1)
        else
            tex:SetAlpha(idleAlpha)
        end
    else
        tex:SetAlpha(1)
    end
end

_quickKeybindState.art.ForEachSpecialButton = function(func)
    if not func then
        return
    end
    if ExtraActionButton1 then
        func(ExtraActionButton1)
    end
end

_quickKeybindState.ReassertButtonsAfterCombatChange = function()
    if not _quickKeybindState.open then
        return
    end
    C_Timer_After(0, function()
        if _quickKeybindState.open and mod.EAB_UpdateQuickKeybindButtons then
            mod.EAB_UpdateQuickKeybindButtons(true)
        end
    end)
end

local function HideTexture(tex)
    if not tex then
        return
    end
    tex:SetAlpha(0)
end

function EAB_VTABLE.HideRegionDeferred(regionFrame, resetAlpha)
    if not regionFrame then
        return
    end
    local frameData = EFD(regionFrame)
    if not frameData.hideFn then
        frameData.hideFn = function()
            if regionFrame and not regionFrame:IsForbidden() then
                regionFrame:Hide()
                if resetAlpha then
                    regionFrame:SetAlpha(resetAlpha)
                end
            end
        end
    end
    C_Timer_After(0, frameData.hideFn)
end

local function MakeButtonSquare(buttonFrame)
    if EFD(buttonFrame).squared then
        return
    end
    -- Always hide SlotBackground regardless of style (our own icon
    -- background toggle controls slot backgrounds for all bars).
    HideSlotArt(buttonFrame)
    -- Skip the rest of Blizzard texture stripping for the stock styles
    local _p = ABAR.db and ABAR.db.profile
    if mod.AB_Style() ~= "cui" then
        return
    end
    HideBorder(buttonFrame)
    -- Ensure the button has GetPopupDirection for Blizzard's SpellFlyout system.
    -- ActionBarButtonTemplate may not always inherit this from FlyoutButtonMixin.
    if not buttonFrame.GetPopupDirection then
        buttonFrame.GetPopupDirection = function(self)
            return self:GetAttribute("flyoutDirection") or "UP"
        end
    end
    local frameData = EFD(buttonFrame)
    if buttonFrame.NormalTexture and not frameData.ntHooked then
        buttonFrame.NormalTexture:HookScript("OnShow", HideSelfDeferred)
        frameData.ntHooked = true
    end
    if not frameData.showHooked then
        -- Cache the deferred closure per button to avoid allocation on every OnShow
        local hideBorderFn = function()
            if buttonFrame and not buttonFrame:IsForbidden() then
                HideBorder(buttonFrame)
            end
        end
        buttonFrame:HookScript("OnShow", function()
            C_Timer_After(0, hideBorderFn)
        end)
        frameData.showHooked = true
    end
    -- Re-neutralize IconMask after Blizzard re-adds it (combat transitions,
    -- page changes, bonus bar swaps). Deferred via C_Timer to avoid tainting
    -- Blizzard's secure call chains.
    if not frameData.artHooked and buttonFrame.UpdateButtonArt then
        hooksecurefunc(buttonFrame, "UpdateButtonArt", function(self)
            local slotData = EFD(self)
            -- Coalesce: UpdateAction storms (mouseover-conditional macros) call
            -- this many times per frame; one deferred HideBorder covers them all.
            if slotData.artPending then
                return
            end
            slotData.artPending = true
            if not slotData.artFn then
                slotData.artFn = function()
                    slotData.artPending = nil
                    if self and not self:IsForbidden() then
                        HideBorder(self)
                    end
                end
            end
            C_Timer_After(0, slotData.artFn)
        end)
        frameData.artHooked = true
    end
    -- Hook UpdateAssistedCombatRotationFrame to scale the rotation frame
    -- when Blizzard creates it lazily (default 45x45, needs our button size).
    if not frameData.rotHooked and buttonFrame.UpdateAssistedCombatRotationFrame then
        hooksecurefunc(buttonFrame, "UpdateAssistedCombatRotationFrame", function(self)
            -- Fires at Blizzard's combat cadence while a rotation action is on
            -- a bar: change-guard so steady-state fires cost only the reads.
            local rtf = self.AssistedCombatRotationFrame
            if rtf and EFD(self).squared then
                local s = (self:GetWidth() or 45) / 45
                if rtf:GetScale() ~= s then
                    rtf:SetScale(s)
                end
            end
            -- Blizzard's swirl frame stays permanently hidden (its Lua OnUpdate polls
            -- every render frame while shown); our script-free spinner clone replaces
            -- it. UpdateState (the caller we hook behind) re-Shows it every call and
            -- this hook runs right after, synchronously, so it never renders.
            if rtf then
                if rtf:IsShown() then
                    rtf:Hide()
                end
                local spin = mod.EnsureAssistSpinner(self, rtf)
                local p2 = ABAR.db and ABAR.db.profile
                local enabled = not p2 or p2.obaIconEnabled ~= false
                local action = self.GetAttribute and self:GetAttribute("action") or self.action
                local isAssist = action
                        and C_ActionBar
                        and C_ActionBar.IsAssistedCombatAction
                        and C_ActionBar.IsAssistedCombatAction(action)
                    or false
                spin:SetShown(enabled and isAssist)
                -- Suggested-spell icon updates ride the assist ticker, armed
                -- here on the only signal that identifies an assist button (see
                -- ns._ArmAssistTicker for cost discipline). When the assist
                -- action leaves, stop the ticker if no assist button remains.
                if isAssist then
                    if mod._ArmAssistTicker then
                        mod._ArmAssistTicker()
                    end
                elseif mod._assistTicker and mod._assistTicker.IsPlaying() then
                    if mod.RepaintAssistIcons() == 0 then
                        mod._assistTicker.Stop()
                    end
                end
            end
        end)
        frameData.rotHooked = true
    end
    SetSquareTexture(buttonFrame.HighlightTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(buttonFrame.NewActionTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(buttonFrame.PushedTexture, HIGHLIGHT_TEXTURES[2])
    SetSquareTexture(buttonFrame.Flash, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(buttonFrame.CheckedTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(buttonFrame.Border, HIGHLIGHT_TEXTURES[1])
    _quickKeybindState.art.InitializeButton(buttonFrame)
    HideTexture(buttonFrame.FlyoutBorderShadow)
    if buttonFrame.BorderShadow then
        if CludesUI and CludesUI._hiddenParent then
            buttonFrame.BorderShadow:SetParent(CludesUI._hiddenParent)
        else
            HideTexture(buttonFrame.BorderShadow)
        end
    end
    if buttonFrame.cooldown then
        buttonFrame.cooldown:ClearAllPoints()
        buttonFrame.cooldown:SetAllPoints(buttonFrame)
    end
    -- Cast-anim suppression (SpellCastAnimFrame + InterruptDisplay): Hide the ANIMATED
    -- frame synchronously -- its animation group re-drives alpha on the next render
    -- tick, so SetAlpha(0) plus a deferred Hide leaks a one-frame blink of the cast
    -- sweep, while a hidden frame renders no animations. The deferred Hide stays as a
    -- fallback reset. Insecure UNIT_SPELLCAST/OnShow context, IsForbidden-guarded.
    if (buttonFrame.SpellCastAnimFrame and not frameData.castHooked) or (buttonFrame.InterruptDisplay and not frameData.intHooked) then
        local hideCastAnim = function(self)
            local prof = ABAR.db and ABAR.db.profile
            if not prof then
                return
            end
            local bfd = EFD(buttonFrame)
            if not prof.hideCastingAnimations and not bfd.shapeApplied and not bfd.cropped then
                return
            end
            self:SetAlpha(0)
            if not self:IsForbidden() then
                self:Hide()
            end
            EAB_VTABLE.HideRegionDeferred(self, 1)
        end
        if buttonFrame.SpellCastAnimFrame and not frameData.castHooked then
            buttonFrame.SpellCastAnimFrame:HookScript("OnShow", hideCastAnim)
            frameData.castHooked = true
        end
        if buttonFrame.InterruptDisplay and not frameData.intHooked then
            buttonFrame.InterruptDisplay:HookScript("OnShow", hideCastAnim)
            frameData.intHooked = true
        end
    end
    -- The cast-on-button anim's OnHide resets the swipe to opaque black on the
    -- button that hard-cast, clobbering the CD Swipe color/opacity setting there
    -- (cast-time spells only; instants never play the anim, and the suppression
    -- hook above trips the same OnHide at cast START). HookScript runs after the
    -- reset, so re-assert ours on the same edge -- fires only when a cast anim
    -- frame hides, nothing at idle.
    if buttonFrame.SpellCastAnimFrame and not frameData.castSwipeHooked then
        frameData.castSwipeHooked = true
        buttonFrame.SpellCastAnimFrame:HookScript("OnHide", function()
            local pdb = ABAR.db and ABAR.db.profile
            local cd = buttonFrame.cooldown
            if not pdb or not (cd and cd.SetSwipeColor) then
                return
            end
            local c = pdb.cdSwipeColor or { r = 0, g = 0, b = 0 }
            pcall(cd.SetSwipeColor, cd, c.r or 0, c.g or 0, c.b or 0, (pdb.cdSwipeAlpha or 80) / 100)
        end)
    end
    if buttonFrame.SlotBackground then
        buttonFrame.SlotBackground:SetAlpha(0)
        if not frameData.slotBgHooked then
            frameData.slotBgHooked = true
            hooksecurefunc(buttonFrame.SlotBackground, "SetAlpha", function(self, a)
                if (issecretvalue and issecretvalue(a)) or a ~= 0 then
                    self:SetAlpha(0)
                end
            end)
        end
    end
    if not frameData.slotBG then
        local backdrop = buttonFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
        backdrop:SetAllPoints(buttonFrame)
        local sc = (_p and _p.slotBgColor) or { r = 0.15, g = 0.15, b = 0.15 }
        local so = _p and _p.slotBgOpacity
        if so == nil then
            so = 50
        end
        backdrop:SetColorTexture(sc.r or 0.15, sc.g or 0.15, sc.b or 0.15, so / 100)
        frameData.slotBG = backdrop
    end
    if buttonFrame.SlotArt then
        buttonFrame.SlotArt:SetAlpha(0)
        if not frameData.slotArtHooked then
            frameData.slotArtHooked = true
            hooksecurefunc(buttonFrame.SlotArt, "SetAlpha", function(self, a)
                if (issecretvalue and issecretvalue(a)) or a ~= 0 then
                    self:SetAlpha(0)
                end
            end)
        end
    end
    -- Blizzard's equipped-item Border: it calls Border:SetAtlas()/Show() on
    -- refreshes (its Show follows a green SetVertexColor) and EAB owns the
    -- visible border, so it is suppressed, unless Equipped Item Color
    -- keeps it (in our square art and the item's rarity color).
    if buttonFrame.Border and not frameData.borderHooked then
        local function BorderRefresh(self)
            if ABAR.db.profile.showEquippedBorder then
                mod.AB_EquippedBorderLook(self, buttonFrame)
            else
                self:SetAlpha(0)
                EAB_VTABLE.HideRegionDeferred(self)
            end
        end
        hooksecurefunc(buttonFrame.Border, "SetAtlas", BorderRefresh)
        hooksecurefunc(buttonFrame.Border, "Show", BorderRefresh)
        frameData.borderHooked = true
    end
    frameData.squared = true
end

local function EnsureBorders(buttonFrame)
    local frameData = EFD(buttonFrame)
    if frameData.borders then
        return frameData.borders
    end
    local Pix = CludesUI and CludesUI.PP
    if Pix then
        Pix.CreateBorder(buttonFrame, 0, 0, 0, 1, 1, "OVERLAY", 2)
        frameData.borders = Pix.GetBorders(buttonFrame)
        -- Reparent the flyout arrow INTO the border frame and lift it above the
        -- strips (OVERLAY sublevel 2, from PP.CreateBorder above): sharing the
        -- frame is not enough, without a higher sublevel the arrow draws under.
        if buttonFrame.Arrow then
            buttonFrame.Arrow:SetParent(frameData.borders)
            if buttonFrame.Arrow.SetDrawLayer then
                buttonFrame.Arrow:SetDrawLayer("OVERLAY", 7)
            elseif buttonFrame.Arrow.SetFrameLevel then
                buttonFrame.Arrow:SetFrameLevel(frameData.borders:GetFrameLevel() + 1)
            end
        end
    end
    return frameData.borders
end

-- Frame level of a button's textured border backdrop (the bar border and its
-- Match Bar Border copy). "Show Behind": level-1 draws behind the icon.
-- "Border Above Effects": +20 clears the proc glow wrapper (+10), the assist
-- overlay (+14) and ring (+15), the cooldown swipe and the item-rank diamond
-- (+18). Otherwise the button's own level, in front of the icon. Show Behind
-- wins. On ns: CUI_ActionBars_Pushed.lua calls it too.
mod._eabBorderLevel = function(buttonFrame, behind, above)
    local lvl = buttonFrame:GetFrameLevel()
    if behind then
        return max(0, lvl - 1)
    end
    if above then
        return lvl + 20
    end
    return lvl
end

-- edgePx: the bar's exact size from ResolveBorderThickness (nil = legacy path).
-- above: the bar's "Border Above Effects" (textured borders only).
local function ApplyButtonBorders(
    buttonFrame,
    on,
    cr,
    cg,
    callback,
    ca,
    sz,
    zoom,
    textureKey,
    texOffset,
    texOffsetY,
    shiftX,
    shiftY,
    addonKey,
    sizeKey,
    behind,
    edgePx,
    above
)
    MakeButtonSquare(buttonFrame)
    local Pix = CludesUI and CludesUI.PP
    local frameData = EFD(buttonFrame)
    if not on then
        if frameData.borders then
            Pix.HideBorder(buttonFrame)
        end
        -- Also hide textured border if present
        if CludesUI._bdBorderData then
            local backdropFrame = CludesUI._bdBorderData[buttonFrame]
            if backdropFrame then
                backdropFrame:Hide()
            end
        end
        frameData.borderKey = nil
    else
        local texKey = textureKey or "solid"
        if texKey ~= "solid" then
            -- Textured borders: always apply (cheap SetBackdropBorderColor call)
            frameData.borderKey = nil
        else
            -- Solid borders: cache to avoid redundant PP updates (the exact size is
            -- a memo input of its own: a number or nil, compared as is)
            local es = buttonFrame:GetEffectiveScale()
            local stateKey = cr * 1000000
                + cg * 10000
                + callback * 100
                + ca
                + sz * 0.001
                + zoom * 10000000
                + es * 0.0001
            if frameData.borderKey == stateKey and frameData.borderTexKey == texKey and frameData.borderPxKey == edgePx then
                return
            end
            frameData.borderKey = stateKey
        end
        frameData.borderTexKey = texKey
        frameData.borderPxKey = edgePx
        if texKey == "solid" then
            EnsureBorders(buttonFrame)
        elseif frameData.borders then
            -- Switching from solid to textured: hide existing PP borders
            Pix.HideBorder(buttonFrame)
            local ppC = Pix.GetBorders(buttonFrame)
            if ppC then
                if ppC._top then
                    ppC._top:SetAlpha(0)
                end
                if ppC._bottom then
                    ppC._bottom:SetAlpha(0)
                end
                if ppC._left then
                    ppC._left:SetAlpha(0)
                end
                if ppC._right then
                    ppC._right:SetAlpha(0)
                end
            end
        end
        CludesUI.ApplyBorderStyle(
            buttonFrame,
            sz,
            cr,
            cg,
            callback,
            ca,
            textureKey,
            texOffset,
            texOffsetY,
            shiftX,
            shiftY,
            addonKey,
            sizeKey,
            nil,
            edgePx
        )
        -- "Show Behind": textured border frame is a child of btn; equal level draws
        -- in front of the icon, level-1 draws behind it. "Border Above Effects"
        -- raises it over the effects; turning it off lands back on the rule
        -- above on the next apply. Solid borders unaffected.
        if texKey ~= "solid" and CludesUI._bdBorderData then
            local backdropFrame = CludesUI._bdBorderData[buttonFrame]
            if backdropFrame then
                backdropFrame:SetFrameLevel(mod._eabBorderLevel(buttonFrame, behind, above))
            end
        end
        if frameData.borders and frameData.shapeMask and frameData.shapeMask:IsShown() then
            Pix.HideBorder(buttonFrame)
            if CludesUI._bdBorderData then
                local backdropFrame = CludesUI._bdBorderData[buttonFrame]
                if backdropFrame then
                    backdropFrame:Hide()
                end
            end
        end
    end
    if zoom > 0 then
        local iconTex = buttonFrame.icon or buttonFrame.Icon
        if iconTex and iconTex.SetTexCoord and not (frameData.shapeMask and frameData.shapeMask:IsShown()) and not frameData.cropped then
            iconTex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
    end
end

-------------------------------------------------------------------------------
--  Shape Masking
-------------------------------------------------------------------------------
local function MaskFrameTextures(widget, mask)
    if not widget or not mask then
        return
    end
    for _, regionFrame in ipairs({ widget:GetRegions() }) do
        if regionFrame.AddMaskTexture then
            pcall(regionFrame.AddMaskTexture, regionFrame, mask)
        end
    end
end

local function UnmaskFrameTextures(widget, mask)
    if not widget or not mask then
        return
    end
    for _, regionFrame in ipairs({ widget:GetRegions() }) do
        if regionFrame.RemoveMaskTexture then
            pcall(regionFrame.RemoveMaskTexture, regionFrame, mask)
        end
    end
end

local function ApplyShapeToButton(buttonFrame, shapeKey, brdOn, brdR, brdG, brdB, brdA, brdSize, zoom)
    _quickKeybindState.art.RefreshButton(buttonFrame)
    local frameData = EFD(buttonFrame)

    if shapeKey == "none" or shapeKey == "cropped" then
        -- Remove shape mask if previously applied
        if frameData.shapeMask then
            local mask = frameData.shapeMask
            local iconTex = buttonFrame.icon or buttonFrame.Icon
            if iconTex then
                pcall(iconTex.RemoveMaskTexture, iconTex, mask)
            end
            -- Unmask slot BG and icon BG from main mask
            if frameData.slotBG then
                pcall(frameData.slotBG.RemoveMaskTexture, frameData.slotBG, mask)
            end
            if frameData.iconBg then
                pcall(frameData.iconBg.RemoveMaskTexture, frameData.iconBg, mask)
            end
            -- Unmask cooldown frames and restore default swipe
            if buttonFrame.cooldown and not buttonFrame.cooldown:IsForbidden() then
                pcall(buttonFrame.cooldown.RemoveMaskTexture, buttonFrame.cooldown, mask)
                pcall(buttonFrame.cooldown.SetSwipeTexture, buttonFrame.cooldown, "")
            end
            if buttonFrame.chargeCooldown and not buttonFrame.chargeCooldown:IsForbidden() then
                pcall(buttonFrame.chargeCooldown.RemoveMaskTexture, buttonFrame.chargeCooldown, mask)
                pcall(buttonFrame.chargeCooldown.SetSwipeTexture, buttonFrame.chargeCooldown, "")
            end
            -- Neutralize the mask so a stale reference cannot clip anything
            mask:SetTexture(nil)
            mask:ClearAllPoints()
            mask:SetSize(0.001, 0.001)
            mask:Hide()
        end
        -- Remove overlay mask if it existed
        if frameData.overlayMask then
            local origMask = frameData.overlayMask
            if buttonFrame.HighlightTexture then
                pcall(buttonFrame.HighlightTexture.RemoveMaskTexture, buttonFrame.HighlightTexture, origMask)
            end
            if buttonFrame.PushedTexture then
                pcall(buttonFrame.PushedTexture.RemoveMaskTexture, buttonFrame.PushedTexture, origMask)
            end
            if buttonFrame.CheckedTexture then
                pcall(buttonFrame.CheckedTexture.RemoveMaskTexture, buttonFrame.CheckedTexture, origMask)
            end
            if buttonFrame.NewActionTexture then
                pcall(buttonFrame.NewActionTexture.RemoveMaskTexture, buttonFrame.NewActionTexture, origMask)
            end
            if buttonFrame.Flash then
                pcall(buttonFrame.Flash.RemoveMaskTexture, buttonFrame.Flash, origMask)
            end
            if buttonFrame.QuickKeybindHighlightTexture then
                pcall(
                    buttonFrame.QuickKeybindHighlightTexture.RemoveMaskTexture,
                    buttonFrame.QuickKeybindHighlightTexture,
                    origMask
                )
            end
            if buttonFrame.Border then
                pcall(buttonFrame.Border.RemoveMaskTexture, buttonFrame.Border, origMask)
            end
            local normalTex = buttonFrame.NormalTexture or buttonFrame:GetNormalTexture()
            if normalTex then
                pcall(normalTex.RemoveMaskTexture, normalTex, origMask)
            end
            if buttonFrame.SpellActivationAlert then
                UnmaskFrameTextures(buttonFrame.SpellActivationAlert, origMask)
                EFD(buttonFrame.SpellActivationAlert).shapeMasked = nil
            end
            origMask:SetTexture(nil)
            origMask:ClearAllPoints()
            origMask:SetSize(0.001, 0.001)
            origMask:Hide()
        elseif frameData.shapeMask then
            -- Overlays were on the main mask (no border case) clean them off
            local mask = frameData.shapeMask
            if buttonFrame.HighlightTexture then
                pcall(buttonFrame.HighlightTexture.RemoveMaskTexture, buttonFrame.HighlightTexture, mask)
            end
            if buttonFrame.PushedTexture then
                pcall(buttonFrame.PushedTexture.RemoveMaskTexture, buttonFrame.PushedTexture, mask)
            end
            if buttonFrame.CheckedTexture then
                pcall(buttonFrame.CheckedTexture.RemoveMaskTexture, buttonFrame.CheckedTexture, mask)
            end
            if buttonFrame.NewActionTexture then
                pcall(buttonFrame.NewActionTexture.RemoveMaskTexture, buttonFrame.NewActionTexture, mask)
            end
            if buttonFrame.Flash then
                pcall(buttonFrame.Flash.RemoveMaskTexture, buttonFrame.Flash, mask)
            end
            if buttonFrame.QuickKeybindHighlightTexture then
                pcall(
                    buttonFrame.QuickKeybindHighlightTexture.RemoveMaskTexture,
                    buttonFrame.QuickKeybindHighlightTexture,
                    mask
                )
            end
            if buttonFrame.Border then
                pcall(buttonFrame.Border.RemoveMaskTexture, buttonFrame.Border, mask)
            end
            local normalTex = buttonFrame.NormalTexture or buttonFrame:GetNormalTexture()
            if normalTex then
                pcall(normalTex.RemoveMaskTexture, normalTex, mask)
            end
            if buttonFrame.SpellActivationAlert then
                UnmaskFrameTextures(buttonFrame.SpellActivationAlert, mask)
                EFD(buttonFrame.SpellActivationAlert).shapeMasked = nil
            end
        end
        -- Clean up glow wrapper mask
        if frameData.glowWrapper then
            local mask = frameData.shapeMask
            if mask then
                UnmaskFrameTextures(frameData.glowWrapper, mask)
            end
            local wrapperData = EFD(frameData.glowWrapper)
            if wrapperData.ownMask then
                UnmaskFrameTextures(frameData.glowWrapper, wrapperData.ownMask)
                wrapperData.ownMask:Hide()
            end
        end
        if frameData.shapeBorder then
            frameData.shapeBorder:Hide()
            EFD(frameData.shapeBorder).wantsShow = false
            frameData.shapeBorder:SetTexture(nil)
        end
        -- Clear shape tracking flags
        frameData.shapeApplied = nil
        frameData.shapeName = nil
        frameData.shapeMaskPath = nil
        -- Restore cooldown edge to default (non-circular, not forced on)
        if buttonFrame.cooldown and not buttonFrame.cooldown:IsForbidden() then
            if buttonFrame.cooldown.SetUseCircularEdge then
                pcall(buttonFrame.cooldown.SetUseCircularEdge, buttonFrame.cooldown, false)
            end
        end
        if buttonFrame.chargeCooldown and not buttonFrame.chargeCooldown:IsForbidden() then
            if buttonFrame.chargeCooldown.SetUseCircularEdge then
                pcall(buttonFrame.chargeCooldown.SetUseCircularEdge, buttonFrame.chargeCooldown, false)
            end
        end
        -- Restore icon
        local iconTex = buttonFrame.icon or buttonFrame.Icon
        if iconTex then
            iconTex:ClearAllPoints()
            iconTex:SetSize(0, 0)
            iconTex:SetAllPoints(buttonFrame)
            if shapeKey == "cropped" then
                local z = (zoom or 0)
                iconTex:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
                frameData.cropped = true
            else
                frameData.cropped = false
                if zoom and zoom > 0 then
                    iconTex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
                else
                    iconTex:SetTexCoord(0, 1, 0, 1)
                end
            end
        end
        -- Show square borders only if border is enabled
        if frameData.borders and brdOn then
            -- Re-apply border style to restore correct type (PP or textured)
            local barId = frameData.barKey
            local texKey = barId
                    and ABAR.db
                    and ABAR.db.profile.bars[barId]
                    and ABAR.db.profile.bars[barId].borderTexture
                or "solid"
            if texKey ~= "solid" then
                local s = ABAR.db.profile.bars[barId]
                local c = s and s.borderColor or { r = 0, g = 0, b = 0, a = 1 }
                local sz, px = ResolveBorderThickness(s)
                local thKey = s.borderThickness or "thin"
                CludesUI.ApplyBorderStyle(
                    buttonFrame,
                    sz,
                    c.r,
                    c.g,
                    c.b,
                    c.a or 1,
                    texKey,
                    s.borderTextureOffset,
                    s.borderTextureOffsetY,
                    s.borderTextureShiftX,
                    s.borderTextureShiftY,
                    "actionbars",
                    thKey,
                    nil,
                    px
                )
                if CludesUI._bdBorderData then
                    local backdropFrame = CludesUI._bdBorderData[buttonFrame]
                    if backdropFrame then
                        backdropFrame:SetFrameLevel(mod._eabBorderLevel(buttonFrame, s.borderBehind, s.borderAboveEffects))
                    end
                end
            else
                Pix.ShowBorder(buttonFrame)
            end
        elseif frameData.borders then
            Pix.HideBorder(buttonFrame)
            if CludesUI._bdBorderData then
                local backdropFrame = CludesUI._bdBorderData[buttonFrame]
                if backdropFrame then
                    backdropFrame:Hide()
                end
            end
        end
        -- Re-enable Blizzard's Border texture (a custom shape hides it while
        -- Equipped Item Color is off)
        if buttonFrame.Border then
            SetSquareTexture(buttonFrame.Border, HIGHLIGHT_TEXTURES[1])
        end
        return
    end

    -- Custom shape
    local maskTex = SHAPE_MASKS[shapeKey]
    if not maskTex then
        return
    end

    if not frameData.shapeMask then
        frameData.shapeMask = buttonFrame:CreateMaskTexture()
    end
    local mask = frameData.shapeMask
    mask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:Show()

    local iconTex = buttonFrame.icon or buttonFrame.Icon

    -- Always remove existing mask references before re-adding
    -- (AddMaskTexture is additive; stale references cause shape-inside-shape)
    if iconTex then
        pcall(iconTex.RemoveMaskTexture, iconTex, mask)
    end
    if frameData.slotBG then
        pcall(frameData.slotBG.RemoveMaskTexture, frameData.slotBG, mask)
    end
    if frameData.iconBg then
        pcall(frameData.iconBg.RemoveMaskTexture, frameData.iconBg, mask)
    end
    if buttonFrame.cooldown and not buttonFrame.cooldown:IsForbidden() then
        pcall(buttonFrame.cooldown.RemoveMaskTexture, buttonFrame.cooldown, mask)
    end
    if buttonFrame.chargeCooldown and not buttonFrame.chargeCooldown:IsForbidden() then
        pcall(buttonFrame.chargeCooldown.RemoveMaskTexture, buttonFrame.chargeCooldown, mask)
    end
    do
        -- Remove overlay textures from whichever mask they were on
        local origMask = frameData.overlayMask or mask
        if buttonFrame.HighlightTexture then
            pcall(buttonFrame.HighlightTexture.RemoveMaskTexture, buttonFrame.HighlightTexture, origMask)
        end
        if buttonFrame.PushedTexture then
            pcall(buttonFrame.PushedTexture.RemoveMaskTexture, buttonFrame.PushedTexture, origMask)
        end
        if buttonFrame.CheckedTexture then
            pcall(buttonFrame.CheckedTexture.RemoveMaskTexture, buttonFrame.CheckedTexture, origMask)
        end
        if buttonFrame.NewActionTexture then
            pcall(buttonFrame.NewActionTexture.RemoveMaskTexture, buttonFrame.NewActionTexture, origMask)
        end
        if buttonFrame.Flash then
            pcall(buttonFrame.Flash.RemoveMaskTexture, buttonFrame.Flash, origMask)
        end
        if buttonFrame.QuickKeybindHighlightTexture then
            pcall(buttonFrame.QuickKeybindHighlightTexture.RemoveMaskTexture, buttonFrame.QuickKeybindHighlightTexture, origMask)
        end
        if buttonFrame.Border then
            pcall(buttonFrame.Border.RemoveMaskTexture, buttonFrame.Border, origMask)
        end
        local nt2 = buttonFrame.NormalTexture or buttonFrame:GetNormalTexture()
        if nt2 then
            pcall(nt2.RemoveMaskTexture, nt2, origMask)
        end
        if buttonFrame.SpellActivationAlert then
            UnmaskFrameTextures(buttonFrame.SpellActivationAlert, origMask)
            EFD(buttonFrame.SpellActivationAlert).shapeMasked = nil
        end
        -- Also clean from main mask if overlay mask was separate
        if frameData.overlayMask and frameData.overlayMask ~= mask then
            if buttonFrame.HighlightTexture then
                pcall(buttonFrame.HighlightTexture.RemoveMaskTexture, buttonFrame.HighlightTexture, mask)
            end
            if buttonFrame.PushedTexture then
                pcall(buttonFrame.PushedTexture.RemoveMaskTexture, buttonFrame.PushedTexture, mask)
            end
            if buttonFrame.CheckedTexture then
                pcall(buttonFrame.CheckedTexture.RemoveMaskTexture, buttonFrame.CheckedTexture, mask)
            end
            if buttonFrame.NewActionTexture then
                pcall(buttonFrame.NewActionTexture.RemoveMaskTexture, buttonFrame.NewActionTexture, mask)
            end
            if buttonFrame.Flash then
                pcall(buttonFrame.Flash.RemoveMaskTexture, buttonFrame.Flash, mask)
            end
            if buttonFrame.QuickKeybindHighlightTexture then
                pcall(
                    buttonFrame.QuickKeybindHighlightTexture.RemoveMaskTexture,
                    buttonFrame.QuickKeybindHighlightTexture,
                    mask
                )
            end
            if buttonFrame.Border then
                pcall(buttonFrame.Border.RemoveMaskTexture, buttonFrame.Border, mask)
            end
            if nt2 then
                pcall(nt2.RemoveMaskTexture, nt2, mask)
            end
        end
        if frameData.glowWrapper then
            UnmaskFrameTextures(frameData.glowWrapper, mask)
            local wrapperData = EFD(frameData.glowWrapper)
            if wrapperData.ownMask then
                UnmaskFrameTextures(frameData.glowWrapper, wrapperData.ownMask)
            end
        end
    end

    -- Apply mask to icon
    if iconTex then
        iconTex:AddMaskTexture(mask)
    end

    -- Overlay/animation mask: with a border (brdSize >= 1) use a separate inset
    -- mask so animations stop at the border edge instead of bleeding past it.
    local overMask
    if brdSize and brdSize >= 1 then
        if not frameData.overlayMask then
            frameData.overlayMask = buttonFrame:CreateMaskTexture()
        end
        overMask = frameData.overlayMask
        overMask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        overMask:ClearAllPoints()
        local inset = 3
        Pix.Point(overMask, "TOPLEFT", buttonFrame, "TOPLEFT", inset, -inset)
        Pix.Point(overMask, "BOTTOMRIGHT", buttonFrame, "BOTTOMRIGHT", -inset, inset)
        overMask:Show()
    else
        -- No border overlays share the main mask, hide overlay mask if it exists
        if frameData.overlayMask then
            frameData.overlayMask:Hide()
        end
        overMask = mask
    end

    -- Apply overlay mask to all button overlay textures
    if buttonFrame.HighlightTexture then
        pcall(buttonFrame.HighlightTexture.AddMaskTexture, buttonFrame.HighlightTexture, overMask)
    end
    if buttonFrame.PushedTexture then
        pcall(buttonFrame.PushedTexture.AddMaskTexture, buttonFrame.PushedTexture, overMask)
    end
    if buttonFrame.CheckedTexture then
        pcall(buttonFrame.CheckedTexture.AddMaskTexture, buttonFrame.CheckedTexture, overMask)
    end
    if buttonFrame.NewActionTexture then
        pcall(buttonFrame.NewActionTexture.AddMaskTexture, buttonFrame.NewActionTexture, overMask)
    end
    if buttonFrame.Flash then
        pcall(buttonFrame.Flash.AddMaskTexture, buttonFrame.Flash, overMask)
    end
    if buttonFrame.QuickKeybindHighlightTexture then
        pcall(buttonFrame.QuickKeybindHighlightTexture.AddMaskTexture, buttonFrame.QuickKeybindHighlightTexture, overMask)
    end
    -- The equipped-item Border follows the shape like the overlays above
    -- (Equipped Item Color); with that option off it stays hidden.
    if buttonFrame.Border then
        pcall(buttonFrame.Border.AddMaskTexture, buttonFrame.Border, overMask)
        if not ABAR.db.profile.showEquippedBorder then
            buttonFrame.Border:Hide()
        end
    end
    if frameData.slotBG then
        pcall(frameData.slotBG.AddMaskTexture, frameData.slotBG, mask)
    end
    if frameData.iconBg then
        pcall(frameData.iconBg.AddMaskTexture, frameData.iconBg, mask)
    end
    local normalTex = buttonFrame.NormalTexture or buttonFrame:GetNormalTexture()
    if normalTex then
        pcall(normalTex.AddMaskTexture, normalTex, overMask)
    end

    -- Expand icon beyond button frame
    local shapeOffset = SHAPE_ICON_EXPAND_OFFSETS[shapeKey] or 0
    local shapeDefault = (SHAPE_ZOOM_DEFAULTS[shapeKey] or 6.0) / 100
    local iconExp = SHAPE_ICON_EXPAND + shapeOffset + ((zoom or 0) - shapeDefault) * 200
    if iconExp < 0 then
        iconExp = 0
    end
    local halfIE = iconExp / 2
    if iconTex then
        iconTex:ClearAllPoints()
        Pix.Point(iconTex, "TOPLEFT", buttonFrame, "TOPLEFT", -halfIE, halfIE)
        Pix.Point(iconTex, "BOTTOMRIGHT", buttonFrame, "BOTTOMRIGHT", halfIE, -halfIE)
    end

    -- Mask inset for border
    mask:ClearAllPoints()
    if brdSize and brdSize >= 1 then
        Pix.Point(mask, "TOPLEFT", buttonFrame, "TOPLEFT", 1, -1)
        Pix.Point(mask, "BOTTOMRIGHT", buttonFrame, "BOTTOMRIGHT", -1, 1)
    else
        mask:SetAllPoints(buttonFrame)
    end

    -- Expand texcoords
    local insetPx = SHAPE_INSETS[shapeKey] or 17
    local visRatio = (128 - 2 * insetPx) / 128
    local expand = ((1 / visRatio) - 1) * 0.5
    if iconTex then
        iconTex:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand)
    end

    -- Hide square borders (both PP and textured)
    if frameData.borders then
        Pix.HideBorder(buttonFrame)
        if CludesUI._bdBorderData then
            local backdropFrame = CludesUI._bdBorderData[buttonFrame]
            if backdropFrame then
                backdropFrame:Hide()
            end
        end
    end

    -- Shape border texture
    if not frameData.shapeBorder then
        frameData.shapeBorder = buttonFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    end
    local edgeTex = frameData.shapeBorder
    pcall(edgeTex.RemoveMaskTexture, edgeTex, mask)
    edgeTex:ClearAllPoints()
    edgeTex:SetAllPoints(buttonFrame)
    local btfd = EFD(edgeTex)
    if brdOn and SHAPE_BORDERS[shapeKey] then
        edgeTex:SetTexture(SHAPE_BORDERS[shapeKey])
        edgeTex:SetVertexColor(brdR, brdG, brdB, brdA)
        edgeTex:Show()
        btfd.wantsShow = true
    else
        edgeTex:Hide()
        btfd.wantsShow = false
    end

    -- Apply mask to cooldown frames so swipe follows the shape
    if buttonFrame.cooldown and not buttonFrame.cooldown:IsForbidden() then
        pcall(buttonFrame.cooldown.AddMaskTexture, buttonFrame.cooldown, mask)
        if buttonFrame.cooldown.SetSwipeTexture then
            pcall(buttonFrame.cooldown.SetSwipeTexture, buttonFrame.cooldown, maskTex)
        end
    end
    if buttonFrame.chargeCooldown and not buttonFrame.chargeCooldown:IsForbidden() then
        pcall(buttonFrame.chargeCooldown.AddMaskTexture, buttonFrame.chargeCooldown, mask)
        if buttonFrame.chargeCooldown.SetSwipeTexture then
            pcall(buttonFrame.chargeCooldown.SetSwipeTexture, buttonFrame.chargeCooldown, maskTex)
        end
    end

    -- Mask proc glow animation frames
    if buttonFrame.SpellActivationAlert then
        MaskFrameTextures(buttonFrame.SpellActivationAlert, overMask)
        EFD(buttonFrame.SpellActivationAlert).shapeMasked = true
    end
    if frameData.glowWrapper then
        local wid = frameData.glowWrapper
        local wrapperData = EFD(wid)
        if not wrapperData.ownMask then
            wrapperData.ownMask = wid:CreateMaskTexture()
        end
        wrapperData.ownMask:ClearAllPoints()
        Pix.Point(wrapperData.ownMask, "TOPLEFT", buttonFrame, "TOPLEFT", 1, -1)
        Pix.Point(wrapperData.ownMask, "BOTTOMRIGHT", buttonFrame, "BOTTOMRIGHT", -1, 1)
        wrapperData.ownMask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        wrapperData.ownMask:Show()
        MaskFrameTextures(wid, wrapperData.ownMask)
    end

    -- Store shape tracking flags for cooldown edge system
    frameData.shapeApplied = true
    frameData.shapeName = shapeKey
    frameData.shapeMaskPath = maskTex

    -- Apply shape-specific cooldown edge: circular edge for non-square shapes,
    -- per-shape scale, custom texture + current color.
    local shapeEdgeScale = SHAPE_EDGE_SCALES[shapeKey] or 0.60
    local useCircular = (shapeKey ~= "square" and shapeKey ~= "csquare")
    do
        local edgeTex = "Interface\\AddOns\\CludesUIActionBars\\Media\\edge.png"
        local p = ABAR.db and ABAR.db.profile
        local cr, cg, callback, ca = 0.973, 0.839, 0.604, 1
        if p then
            if p.cooldownEdgeUseClassColor then
                local _, cls = UnitClass("player")
                local cc = RAID_CLASS_COLORS[cls]
                if cc then
                    cr, cg, callback = cc.r, cc.g, cc.b
                end
                ca = (p.cooldownEdgeColor and p.cooldownEdgeColor.a) or 1
            elseif p.cooldownEdgeColor then
                cr = p.cooldownEdgeColor.r or cr
                cg = p.cooldownEdgeColor.g or cg
                callback = p.cooldownEdgeColor.b or callback
                ca = p.cooldownEdgeColor.a or ca
            end
        end
        for _, cd in ipairs({ buttonFrame.cooldown, buttonFrame.chargeCooldown }) do
            if cd and not cd:IsForbidden() then
                if cd.SetEdgeTexture then
                    pcall(cd.SetEdgeTexture, cd, edgeTex)
                end
                if cd.SetEdgeColor then
                    pcall(cd.SetEdgeColor, cd, cr, cg, callback, ca)
                end
                if cd.SetUseCircularEdge then
                    pcall(cd.SetUseCircularEdge, cd, useCircular)
                end
                if cd.SetEdgeScale then
                    pcall(cd.SetEdgeScale, cd, shapeEdgeScale)
                end
            end
        end
    end

    frameData.cropped = false
end

-- Entry points the files after this one re-import by name.
Inner.SetSquareTexture = SetSquareTexture
Inner.ApplyButtonBorders = ApplyButtonBorders
Inner.ApplyShapeToButton = ApplyShapeToButton
Inner.MaskFrameTextures = MaskFrameTextures
