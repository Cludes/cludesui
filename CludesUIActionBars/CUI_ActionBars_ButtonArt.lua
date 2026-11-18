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
    local fd = EFD(self)
    if not fd.hideFn then
        fd.hideFn = function()
            if self and not self:IsForbidden() then
                self:Hide()
            end
        end
    end
    C_Timer_After(0, fd.hideFn)
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

local function SetSquareTexture(texture, texPath)
    if not texture then
        return
    end
    texture:SetAtlas(nil)
    texture:SetTexture(texPath)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:ClearAllPoints()
    texture:SetAllPoints(texture:GetParent())
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
        local texture = not isItem and GetActionTexture(action)
        if not (isItem or texture) then
            return
        end
        for slot = 1, 19 do
            local hit
            if isItem then
                hit = GetInventoryItemID("player", slot) == ident
            else
                hit = GetInventoryItemTexture("player", slot) == texture
            end
            if hit then
                return GetInventoryItemQuality("player", slot)
            end
        end
        if isItem then
            return C_Item.GetItemQualityByID(ident)
        end
    end

    function mod.AB_EquippedBorderLook(edge, button)
        if busy then
            return
        end
        busy = true
        SetSquareTexture(edge, HIGHLIGHT_TEXTURES[1])
        busy = false
        local a = button and button:GetAttribute("action")
        local q = a and IsEquippedAction(a) and EquippedQuality(a)
        if q then
            local region, g, b = C_Item.GetItemQualityColor(q)
            edge:SetVertexColor(region, g, b, 1)
        else
            edge:SetVertexColor(0, 1, 0, 0.5)
        end
        edge:SetAlpha(1)
    end

    -- The equipped-item Border from live slot contents, for every path that
    -- changes what a button holds (slot changes, page flips, bar reveals,
    -- setup). Our square buttons show it only with Equipped Item Color
    -- on; the Blizzard and Classic styles keep Blizzard's own look.
    function mod.AB_SyncEquippedBorder(button, action)
        local edge = button.Border
        if not edge then
            return
        end
        local fd = mod._eabFD[button]
        local square = fd and fd.squared
        if square and not ABAR.db.profile.showEquippedBorder then
            return
        end
        local on = action and IsEquippedAction(action) and true or false
        if square and on then
            mod.AB_EquippedBorderLook(edge, button)
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
function mod.AB_ClassicSlotRing(button, filled)
    filled = filled and true or false
    local fd = EFD(button)
    if fd.classicFilled == filled then
        return
    end
    fd.classicFilled = filled
    local nt = button.NormalTexture
    if nt then
        nt:SetTexture(filled and mod.AB_CLASSIC.slot or mod.AB_CLASSIC.empty)
        nt:SetTexCoord(0, 1, 0, 1)
    end
end

-- Plain Blizzard Style on the Forever client: the border the template's
-- OnLoad left on our button's NormalTexture (IconFrame-AddRow, as our
-- buttons have no .bar; IconFrame on a bar-art button) is redrawn once from
-- its retail sheet, where the client's atlas would draw Forever art.
function mod.AB_StockNormal(button)
    local fd = EFD(button)
    if fd.stockNT then
        return
    end
    fd.stockNT = true
    if mod.AB_Forever() then
        return
    end
    local nt = button.NormalTexture
    local a = nt and nt:GetAtlas()
    if not a then
        return
    end
    local l = strlower(a)
    if l == "ui-hud-actionbar-iconframe-addrow" or l == "ui-hud-actionbar-iconframe" then
        CludesUI.StockAtlas(nt, a)
    end
end

-- Paints the whole kit on `btn` for a `w` x `h` button (its own size when
-- omitted). Our bar buttons pass their native size; flyout buttons pass none.
function mod.AB_PaintClassicButton(button, wid, hgt)
    local fd = EFD(button)
    local art = mod.AB_CLASSIC
    if not wid then
        wid, hgt = button:GetSize()
    end
    if not wid or wid <= 0 then
        wid = 45
    end
    if not hgt or hgt <= 0 then
        hgt = wid
    end
    local sw, sh = wid / 36, hgt / 36
    local iconTex = button.icon
    if iconTex then
        if button.IconMask then
            iconTex:RemoveMaskTexture(button.IconMask)
            button.IconMask:Hide()
            button.IconMask:SetTexture(nil)
            button.IconMask:ClearAllPoints()
            button.IconMask:SetSize(0.001, 0.001)
        end
        iconTex:SetTexCoord(0, 1, 0, 1)
    end
    -- The 12.1 rounded slot background stays transparent (the square ring
    -- below is the slot); alpha, so Blizzard's own art passes keep working.
    if button.SlotBackground then
        button.SlotBackground:SetAlpha(0)
    end
    if button.cooldown then
        button.cooldown:ClearAllPoints()
        button.cooldown:SetAllPoints(button)
    end
    -- Seeded from the same source the content edges use (the action
    -- attribute); buttons without one (flyout popups) ask the mixin.
    if fd.classicFilled == nil then
        local a = button.GetAttribute and button:GetAttribute("action")
        if a then
            fd.classicFilled = HasAction(a) and true or false
        else
            fd.classicFilled = ButtonHasAction(button) and true or false
        end
    end
    local nt = button.NormalTexture
    if nt then
        nt:SetAtlas(nil)
        nt:SetTexture(fd.classicFilled and art.slot or art.empty)
        nt:SetTexCoord(0, 1, 0, 1)
        nt:ClearAllPoints()
        nt:SetPoint("CENTER", button, "CENTER", 0, -sh)
        nt:SetSize(66 * sw, 66 * sh)
    end
    local pt = button.PushedTexture
    if pt then
        pt:SetAtlas(nil)
        pt:SetTexture(art.pushed)
        pt:SetTexCoord(0, 1, 0, 1)
        pt:SetDrawLayer("OVERLAY", 7)
        pt:ClearAllPoints()
        pt:SetAllPoints(button)
        pt:SetVertexColor(1, 1, 1, 1)
        pt:SetAlpha(1)
    end
    local ht = button.HighlightTexture
    if ht then
        ht:SetAtlas(nil)
        ht:SetTexture(art.hilight)
        ht:SetTexCoord(0, 1, 0, 1)
        ht:SetBlendMode("ADD")
        ht:ClearAllPoints()
        ht:SetAllPoints(button)
    end
    local ct = button.CheckedTexture
    if ct then
        ct:SetAtlas(nil)
        ct:SetTexture(art.checked)
        ct:SetTexCoord(0, 1, 0, 1)
        ct:SetBlendMode("ADD")
        ct:ClearAllPoints()
        ct:SetAllPoints(button)
    end
    local edge = button.Border
    if edge then
        edge:SetAtlas(nil)
        edge:SetTexture(art.equipped)
        edge:SetTexCoord(0, 1, 0, 1)
        edge:SetBlendMode("ADD")
        edge:ClearAllPoints()
        edge:SetPoint("CENTER", button, "CENTER", 0, sh)
        edge:SetSize(62 * sw, 62 * sh)
    end
    fd.classicArt = true
end

_quickKeybindState.art.ApplyButtonHighlight = function(button)
    local texture = button and button.QuickKeybindHighlightTexture
    if not texture then
        return
    end

    local p = ABAR and ABAR.db and ABAR.db.profile
    local useCC = p and p.highlightUseClassColor
    local customC = (p and p.highlightCustomColor) or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    local cr, cg, callback = customC.r, customC.g, customC.b
    if useCC then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then
                cr, cg, callback = cc.r, cc.g, cc.b
            end
        end
    end

    -- QuickKeybind manages hover/idle opacity itself. We only replace the
    -- Blizzard atlas with CUI's square highlight art and matching color.
    SetSquareTexture(texture, HIGHLIGHT_TEXTURES[1])
    texture:SetVertexColor(cr, cg, callback, 1)
end

_quickKeybindState.art.RefreshButton = function(button, show)
    if not button or button:IsForbidden() then
        return
    end
    _quickKeybindState.art.ApplyButtonHighlight(button)
    if show ~= nil then
        _quickKeybindState.art.ApplyButtonHighlightAlpha(button, show)
    end
end

_quickKeybindState.art.InitializeButton = function(button, show)
    _quickKeybindState.art.RefreshButton(button, show)
    _quickKeybindState.art.HookButton(button)
end

_quickKeybindState.art.HookButton = function(button)
    if not button or button:IsForbidden() or EFD(button).quickKeybindArtHooked then
        return
    end
    if button.QuickKeybindHighlightTexture and button.DoModeChange then
        hooksecurefunc(button, "DoModeChange", function(self, isInQuickbindMode)
            _quickKeybindState.art.RefreshButton(self, isInQuickbindMode)
        end)
        EFD(button).quickKeybindArtHooked = true
    end
end

_quickKeybindState.art.ApplyButtonHighlightAlpha = function(button, show)
    local texture = button and button.QuickKeybindHighlightTexture
    if not texture then
        return
    end

    if show then
        local idleAlpha = 0.5
        if button.IsMouseOver and button:IsMouseOver() then
            texture:SetAlpha(1)
        else
            texture:SetAlpha(idleAlpha)
        end
    else
        texture:SetAlpha(1)
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

local function HideTexture(texture)
    if not texture then
        return
    end
    texture:SetAlpha(0)
end

function EAB_VTABLE.HideRegionDeferred(regionFrame, resetAlpha)
    if not regionFrame then
        return
    end
    local fd = EFD(regionFrame)
    if not fd.hideFn then
        fd.hideFn = function()
            if regionFrame and not regionFrame:IsForbidden() then
                regionFrame:Hide()
                if resetAlpha then
                    regionFrame:SetAlpha(resetAlpha)
                end
            end
        end
    end
    C_Timer_After(0, fd.hideFn)
end

local function MakeButtonSquare(button)
    if EFD(button).squared then
        return
    end
    -- Always hide SlotBackground regardless of style (our own icon
    -- background toggle controls slot backgrounds for all bars).
    HideSlotArt(button)
    -- Skip the rest of Blizzard texture stripping for the stock styles
    local _p = ABAR.db and ABAR.db.profile
    if mod.AB_Style() ~= "cui" then
        return
    end
    HideBorder(button)
    -- Ensure the button has GetPopupDirection for Blizzard's SpellFlyout system.
    -- ActionBarButtonTemplate may not always inherit this from FlyoutButtonMixin.
    if not button.GetPopupDirection then
        button.GetPopupDirection = function(self)
            return self:GetAttribute("flyoutDirection") or "UP"
        end
    end
    local fd = EFD(button)
    if button.NormalTexture and not fd.ntHooked then
        button.NormalTexture:HookScript("OnShow", HideSelfDeferred)
        fd.ntHooked = true
    end
    if not fd.showHooked then
        -- Cache the deferred closure per button to avoid allocation on every OnShow
        local hideBorderFn = function()
            if button and not button:IsForbidden() then
                HideBorder(button)
            end
        end
        button:HookScript("OnShow", function()
            C_Timer_After(0, hideBorderFn)
        end)
        fd.showHooked = true
    end
    -- Re-neutralize IconMask after Blizzard re-adds it (combat transitions,
    -- page changes, bonus bar swaps). Deferred via C_Timer to avoid tainting
    -- Blizzard's secure call chains.
    if not fd.artHooked and button.UpdateButtonArt then
        hooksecurefunc(button, "UpdateButtonArt", function(self)
            local sfd = EFD(self)
            -- Coalesce: UpdateAction storms (mouseover-conditional macros) call
            -- this many times per frame; one deferred HideBorder covers them all.
            if sfd.artPending then
                return
            end
            sfd.artPending = true
            if not sfd.artFn then
                sfd.artFn = function()
                    sfd.artPending = nil
                    if self and not self:IsForbidden() then
                        HideBorder(self)
                    end
                end
            end
            C_Timer_After(0, sfd.artFn)
        end)
        fd.artHooked = true
    end
    -- Hook UpdateAssistedCombatRotationFrame to scale the rotation frame
    -- when Blizzard creates it lazily (default 45x45, needs our button size).
    if not fd.rotHooked and button.UpdateAssistedCombatRotationFrame then
        hooksecurefunc(button, "UpdateAssistedCombatRotationFrame", function(self)
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
        fd.rotHooked = true
    end
    SetSquareTexture(button.HighlightTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(button.NewActionTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(button.PushedTexture, HIGHLIGHT_TEXTURES[2])
    SetSquareTexture(button.Flash, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(button.CheckedTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(button.Border, HIGHLIGHT_TEXTURES[1])
    _quickKeybindState.art.InitializeButton(button)
    HideTexture(button.FlyoutBorderShadow)
    if button.BorderShadow then
        if CludesUI and CludesUI._hiddenParent then
            button.BorderShadow:SetParent(CludesUI._hiddenParent)
        else
            HideTexture(button.BorderShadow)
        end
    end
    if button.cooldown then
        button.cooldown:ClearAllPoints()
        button.cooldown:SetAllPoints(button)
    end
    -- Cast-anim suppression (SpellCastAnimFrame + InterruptDisplay): Hide the ANIMATED
    -- frame synchronously -- its animation group re-drives alpha on the next render
    -- tick, so SetAlpha(0) plus a deferred Hide leaks a one-frame blink of the cast
    -- sweep, while a hidden frame renders no animations. The deferred Hide stays as a
    -- fallback reset. Insecure UNIT_SPELLCAST/OnShow context, IsForbidden-guarded.
    if (button.SpellCastAnimFrame and not fd.castHooked) or (button.InterruptDisplay and not fd.intHooked) then
        local hideCastAnim = function(self)
            local prof = ABAR.db and ABAR.db.profile
            if not prof then
                return
            end
            local bfd = EFD(button)
            if not prof.hideCastingAnimations and not bfd.shapeApplied and not bfd.cropped then
                return
            end
            self:SetAlpha(0)
            if not self:IsForbidden() then
                self:Hide()
            end
            EAB_VTABLE.HideRegionDeferred(self, 1)
        end
        if button.SpellCastAnimFrame and not fd.castHooked then
            button.SpellCastAnimFrame:HookScript("OnShow", hideCastAnim)
            fd.castHooked = true
        end
        if button.InterruptDisplay and not fd.intHooked then
            button.InterruptDisplay:HookScript("OnShow", hideCastAnim)
            fd.intHooked = true
        end
    end
    -- The cast-on-button anim's OnHide resets the swipe to opaque black on the
    -- button that hard-cast, clobbering the CD Swipe color/opacity setting there
    -- (cast-time spells only; instants never play the anim, and the suppression
    -- hook above trips the same OnHide at cast START). HookScript runs after the
    -- reset, so re-assert ours on the same edge -- fires only when a cast anim
    -- frame hides, nothing at idle.
    if button.SpellCastAnimFrame and not fd.castSwipeHooked then
        fd.castSwipeHooked = true
        button.SpellCastAnimFrame:HookScript("OnHide", function()
            local pdb = ABAR.db and ABAR.db.profile
            local cd = button.cooldown
            if not pdb or not (cd and cd.SetSwipeColor) then
                return
            end
            local c = pdb.cdSwipeColor or { r = 0, g = 0, b = 0 }
            pcall(cd.SetSwipeColor, cd, c.r or 0, c.g or 0, c.b or 0, (pdb.cdSwipeAlpha or 80) / 100)
        end)
    end
    if button.SlotBackground then
        button.SlotBackground:SetAlpha(0)
        if not fd.slotBgHooked then
            fd.slotBgHooked = true
            hooksecurefunc(button.SlotBackground, "SetAlpha", function(self, a)
                if (issecretvalue and issecretvalue(a)) or a ~= 0 then
                    self:SetAlpha(0)
                end
            end)
        end
    end
    if not fd.slotBG then
        local backdrop = button:CreateTexture(nil, "BACKGROUND", nil, -1)
        backdrop:SetAllPoints(button)
        local sc = (_p and _p.slotBgColor) or { r = 0.15, g = 0.15, b = 0.15 }
        local so = _p and _p.slotBgOpacity
        if so == nil then
            so = 50
        end
        backdrop:SetColorTexture(sc.r or 0.15, sc.g or 0.15, sc.b or 0.15, so / 100)
        fd.slotBG = backdrop
    end
    if button.SlotArt then
        button.SlotArt:SetAlpha(0)
        if not fd.slotArtHooked then
            fd.slotArtHooked = true
            hooksecurefunc(button.SlotArt, "SetAlpha", function(self, a)
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
    if button.Border and not fd.borderHooked then
        local function BorderRefresh(self)
            if ABAR.db.profile.showEquippedBorder then
                mod.AB_EquippedBorderLook(self, button)
            else
                self:SetAlpha(0)
                EAB_VTABLE.HideRegionDeferred(self)
            end
        end
        hooksecurefunc(button.Border, "SetAtlas", BorderRefresh)
        hooksecurefunc(button.Border, "Show", BorderRefresh)
        fd.borderHooked = true
    end
    fd.squared = true
end

local function EnsureBorders(button)
    local fd = EFD(button)
    if fd.borders then
        return fd.borders
    end
    local Pix = CludesUI and CludesUI.PP
    if Pix then
        Pix.CreateBorder(button, 0, 0, 0, 1, 1, "OVERLAY", 2)
        fd.borders = Pix.GetBorders(button)
        -- Reparent the flyout arrow INTO the border frame and lift it above the
        -- strips (OVERLAY sublevel 2, from PP.CreateBorder above): sharing the
        -- frame is not enough, without a higher sublevel the arrow draws under.
        if button.Arrow then
            button.Arrow:SetParent(fd.borders)
            if button.Arrow.SetDrawLayer then
                button.Arrow:SetDrawLayer("OVERLAY", 7)
            elseif button.Arrow.SetFrameLevel then
                button.Arrow:SetFrameLevel(fd.borders:GetFrameLevel() + 1)
            end
        end
    end
    return fd.borders
end

-- Frame level of a button's textured border backdrop (the bar border and its
-- Match Bar Border copy). "Show Behind": level-1 draws behind the icon.
-- "Border Above Effects": +20 clears the proc glow wrapper (+10), the assist
-- overlay (+14) and ring (+15), the cooldown swipe and the item-rank diamond
-- (+18). Otherwise the button's own level, in front of the icon. Show Behind
-- wins. On ns: CUI_ActionBars_Pushed.lua calls it too.
mod._eabBorderLevel = function(button, behind, above)
    local lvl = button:GetFrameLevel()
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
    button,
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
    MakeButtonSquare(button)
    local Pix = CludesUI and CludesUI.PP
    local fd = EFD(button)
    if not on then
        if fd.borders then
            Pix.HideBorder(button)
        end
        -- Also hide textured border if present
        if CludesUI._bdBorderData then
            local bdFrame = CludesUI._bdBorderData[button]
            if bdFrame then
                bdFrame:Hide()
            end
        end
        fd.borderKey = nil
    else
        local texKey = textureKey or "solid"
        if texKey ~= "solid" then
            -- Textured borders: always apply (cheap SetBackdropBorderColor call)
            fd.borderKey = nil
        else
            -- Solid borders: cache to avoid redundant PP updates (the exact size is
            -- a memo input of its own: a number or nil, compared as is)
            local es = button:GetEffectiveScale()
            local stateKey = cr * 1000000
                + cg * 10000
                + callback * 100
                + ca
                + sz * 0.001
                + zoom * 10000000
                + es * 0.0001
            if fd.borderKey == stateKey and fd.borderTexKey == texKey and fd.borderPxKey == edgePx then
                return
            end
            fd.borderKey = stateKey
        end
        fd.borderTexKey = texKey
        fd.borderPxKey = edgePx
        if texKey == "solid" then
            EnsureBorders(button)
        elseif fd.borders then
            -- Switching from solid to textured: hide existing PP borders
            Pix.HideBorder(button)
            local ppC = Pix.GetBorders(button)
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
            button,
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
            local bdFrame = CludesUI._bdBorderData[button]
            if bdFrame then
                bdFrame:SetFrameLevel(mod._eabBorderLevel(button, behind, above))
            end
        end
        if fd.borders and fd.shapeMask and fd.shapeMask:IsShown() then
            Pix.HideBorder(button)
            if CludesUI._bdBorderData then
                local bdFrame = CludesUI._bdBorderData[button]
                if bdFrame then
                    bdFrame:Hide()
                end
            end
        end
    end
    if zoom > 0 then
        local iconTex = button.icon or button.Icon
        if iconTex and iconTex.SetTexCoord and not (fd.shapeMask and fd.shapeMask:IsShown()) and not fd.cropped then
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

local function ApplyShapeToButton(button, shape, brdOn, brdR, brdG, brdB, brdA, brdSize, zoom)
    _quickKeybindState.art.RefreshButton(button)
    local fd = EFD(button)

    if shape == "none" or shape == "cropped" then
        -- Remove shape mask if previously applied
        if fd.shapeMask then
            local mask = fd.shapeMask
            local iconTex = button.icon or button.Icon
            if iconTex then
                pcall(iconTex.RemoveMaskTexture, iconTex, mask)
            end
            -- Unmask slot BG and icon BG from main mask
            if fd.slotBG then
                pcall(fd.slotBG.RemoveMaskTexture, fd.slotBG, mask)
            end
            if fd.iconBg then
                pcall(fd.iconBg.RemoveMaskTexture, fd.iconBg, mask)
            end
            -- Unmask cooldown frames and restore default swipe
            if button.cooldown and not button.cooldown:IsForbidden() then
                pcall(button.cooldown.RemoveMaskTexture, button.cooldown, mask)
                pcall(button.cooldown.SetSwipeTexture, button.cooldown, "")
            end
            if button.chargeCooldown and not button.chargeCooldown:IsForbidden() then
                pcall(button.chargeCooldown.RemoveMaskTexture, button.chargeCooldown, mask)
                pcall(button.chargeCooldown.SetSwipeTexture, button.chargeCooldown, "")
            end
            -- Neutralize the mask so a stale reference cannot clip anything
            mask:SetTexture(nil)
            mask:ClearAllPoints()
            mask:SetSize(0.001, 0.001)
            mask:Hide()
        end
        -- Remove overlay mask if it existed
        if fd.overlayMask then
            local omask = fd.overlayMask
            if button.HighlightTexture then
                pcall(button.HighlightTexture.RemoveMaskTexture, button.HighlightTexture, omask)
            end
            if button.PushedTexture then
                pcall(button.PushedTexture.RemoveMaskTexture, button.PushedTexture, omask)
            end
            if button.CheckedTexture then
                pcall(button.CheckedTexture.RemoveMaskTexture, button.CheckedTexture, omask)
            end
            if button.NewActionTexture then
                pcall(button.NewActionTexture.RemoveMaskTexture, button.NewActionTexture, omask)
            end
            if button.Flash then
                pcall(button.Flash.RemoveMaskTexture, button.Flash, omask)
            end
            if button.QuickKeybindHighlightTexture then
                pcall(
                    button.QuickKeybindHighlightTexture.RemoveMaskTexture,
                    button.QuickKeybindHighlightTexture,
                    omask
                )
            end
            if button.Border then
                pcall(button.Border.RemoveMaskTexture, button.Border, omask)
            end
            local nt = button.NormalTexture or button:GetNormalTexture()
            if nt then
                pcall(nt.RemoveMaskTexture, nt, omask)
            end
            if button.SpellActivationAlert then
                UnmaskFrameTextures(button.SpellActivationAlert, omask)
                EFD(button.SpellActivationAlert).shapeMasked = nil
            end
            omask:SetTexture(nil)
            omask:ClearAllPoints()
            omask:SetSize(0.001, 0.001)
            omask:Hide()
        elseif fd.shapeMask then
            -- Overlays were on the main mask (no border case) clean them off
            local mask = fd.shapeMask
            if button.HighlightTexture then
                pcall(button.HighlightTexture.RemoveMaskTexture, button.HighlightTexture, mask)
            end
            if button.PushedTexture then
                pcall(button.PushedTexture.RemoveMaskTexture, button.PushedTexture, mask)
            end
            if button.CheckedTexture then
                pcall(button.CheckedTexture.RemoveMaskTexture, button.CheckedTexture, mask)
            end
            if button.NewActionTexture then
                pcall(button.NewActionTexture.RemoveMaskTexture, button.NewActionTexture, mask)
            end
            if button.Flash then
                pcall(button.Flash.RemoveMaskTexture, button.Flash, mask)
            end
            if button.QuickKeybindHighlightTexture then
                pcall(
                    button.QuickKeybindHighlightTexture.RemoveMaskTexture,
                    button.QuickKeybindHighlightTexture,
                    mask
                )
            end
            if button.Border then
                pcall(button.Border.RemoveMaskTexture, button.Border, mask)
            end
            local nt = button.NormalTexture or button:GetNormalTexture()
            if nt then
                pcall(nt.RemoveMaskTexture, nt, mask)
            end
            if button.SpellActivationAlert then
                UnmaskFrameTextures(button.SpellActivationAlert, mask)
                EFD(button.SpellActivationAlert).shapeMasked = nil
            end
        end
        -- Clean up glow wrapper mask
        if fd.glowWrapper then
            local mask = fd.shapeMask
            if mask then
                UnmaskFrameTextures(fd.glowWrapper, mask)
            end
            local wfd = EFD(fd.glowWrapper)
            if wfd.ownMask then
                UnmaskFrameTextures(fd.glowWrapper, wfd.ownMask)
                wfd.ownMask:Hide()
            end
        end
        if fd.shapeBorder then
            fd.shapeBorder:Hide()
            EFD(fd.shapeBorder).wantsShow = false
            fd.shapeBorder:SetTexture(nil)
        end
        -- Clear shape tracking flags
        fd.shapeApplied = nil
        fd.shapeName = nil
        fd.shapeMaskPath = nil
        -- Restore cooldown edge to default (non-circular, not forced on)
        if button.cooldown and not button.cooldown:IsForbidden() then
            if button.cooldown.SetUseCircularEdge then
                pcall(button.cooldown.SetUseCircularEdge, button.cooldown, false)
            end
        end
        if button.chargeCooldown and not button.chargeCooldown:IsForbidden() then
            if button.chargeCooldown.SetUseCircularEdge then
                pcall(button.chargeCooldown.SetUseCircularEdge, button.chargeCooldown, false)
            end
        end
        -- Restore icon
        local iconTex = button.icon or button.Icon
        if iconTex then
            iconTex:ClearAllPoints()
            iconTex:SetSize(0, 0)
            iconTex:SetAllPoints(button)
            if shape == "cropped" then
                local z = (zoom or 0)
                iconTex:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
                fd.cropped = true
            else
                fd.cropped = false
                if zoom and zoom > 0 then
                    iconTex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
                else
                    iconTex:SetTexCoord(0, 1, 0, 1)
                end
            end
        end
        -- Show square borders only if border is enabled
        if fd.borders and brdOn then
            -- Re-apply border style to restore correct type (PP or textured)
            local barId = fd.barKey
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
                    button,
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
                    local bdFrame = CludesUI._bdBorderData[button]
                    if bdFrame then
                        bdFrame:SetFrameLevel(mod._eabBorderLevel(button, s.borderBehind, s.borderAboveEffects))
                    end
                end
            else
                Pix.ShowBorder(button)
            end
        elseif fd.borders then
            Pix.HideBorder(button)
            if CludesUI._bdBorderData then
                local bdFrame = CludesUI._bdBorderData[button]
                if bdFrame then
                    bdFrame:Hide()
                end
            end
        end
        -- Re-enable Blizzard's Border texture (a custom shape hides it while
        -- Equipped Item Color is off)
        if button.Border then
            SetSquareTexture(button.Border, HIGHLIGHT_TEXTURES[1])
        end
        return
    end

    -- Custom shape
    local maskTex = SHAPE_MASKS[shape]
    if not maskTex then
        return
    end

    if not fd.shapeMask then
        fd.shapeMask = button:CreateMaskTexture()
    end
    local mask = fd.shapeMask
    mask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:Show()

    local iconTex = button.icon or button.Icon

    -- Always remove existing mask references before re-adding
    -- (AddMaskTexture is additive; stale references cause shape-inside-shape)
    if iconTex then
        pcall(iconTex.RemoveMaskTexture, iconTex, mask)
    end
    if fd.slotBG then
        pcall(fd.slotBG.RemoveMaskTexture, fd.slotBG, mask)
    end
    if fd.iconBg then
        pcall(fd.iconBg.RemoveMaskTexture, fd.iconBg, mask)
    end
    if button.cooldown and not button.cooldown:IsForbidden() then
        pcall(button.cooldown.RemoveMaskTexture, button.cooldown, mask)
    end
    if button.chargeCooldown and not button.chargeCooldown:IsForbidden() then
        pcall(button.chargeCooldown.RemoveMaskTexture, button.chargeCooldown, mask)
    end
    do
        -- Remove overlay textures from whichever mask they were on
        local omask = fd.overlayMask or mask
        if button.HighlightTexture then
            pcall(button.HighlightTexture.RemoveMaskTexture, button.HighlightTexture, omask)
        end
        if button.PushedTexture then
            pcall(button.PushedTexture.RemoveMaskTexture, button.PushedTexture, omask)
        end
        if button.CheckedTexture then
            pcall(button.CheckedTexture.RemoveMaskTexture, button.CheckedTexture, omask)
        end
        if button.NewActionTexture then
            pcall(button.NewActionTexture.RemoveMaskTexture, button.NewActionTexture, omask)
        end
        if button.Flash then
            pcall(button.Flash.RemoveMaskTexture, button.Flash, omask)
        end
        if button.QuickKeybindHighlightTexture then
            pcall(button.QuickKeybindHighlightTexture.RemoveMaskTexture, button.QuickKeybindHighlightTexture, omask)
        end
        if button.Border then
            pcall(button.Border.RemoveMaskTexture, button.Border, omask)
        end
        local nt2 = button.NormalTexture or button:GetNormalTexture()
        if nt2 then
            pcall(nt2.RemoveMaskTexture, nt2, omask)
        end
        if button.SpellActivationAlert then
            UnmaskFrameTextures(button.SpellActivationAlert, omask)
            EFD(button.SpellActivationAlert).shapeMasked = nil
        end
        -- Also clean from main mask if overlay mask was separate
        if fd.overlayMask and fd.overlayMask ~= mask then
            if button.HighlightTexture then
                pcall(button.HighlightTexture.RemoveMaskTexture, button.HighlightTexture, mask)
            end
            if button.PushedTexture then
                pcall(button.PushedTexture.RemoveMaskTexture, button.PushedTexture, mask)
            end
            if button.CheckedTexture then
                pcall(button.CheckedTexture.RemoveMaskTexture, button.CheckedTexture, mask)
            end
            if button.NewActionTexture then
                pcall(button.NewActionTexture.RemoveMaskTexture, button.NewActionTexture, mask)
            end
            if button.Flash then
                pcall(button.Flash.RemoveMaskTexture, button.Flash, mask)
            end
            if button.QuickKeybindHighlightTexture then
                pcall(
                    button.QuickKeybindHighlightTexture.RemoveMaskTexture,
                    button.QuickKeybindHighlightTexture,
                    mask
                )
            end
            if button.Border then
                pcall(button.Border.RemoveMaskTexture, button.Border, mask)
            end
            if nt2 then
                pcall(nt2.RemoveMaskTexture, nt2, mask)
            end
        end
        if fd.glowWrapper then
            UnmaskFrameTextures(fd.glowWrapper, mask)
            local wfd = EFD(fd.glowWrapper)
            if wfd.ownMask then
                UnmaskFrameTextures(fd.glowWrapper, wfd.ownMask)
            end
        end
    end

    -- Apply mask to icon
    if iconTex then
        iconTex:AddMaskTexture(mask)
    end

    -- Overlay/animation mask: with a border (brdSize >= 1) use a separate inset
    -- mask so animations stop at the border edge instead of bleeding past it.
    local overlayMask
    if brdSize and brdSize >= 1 then
        if not fd.overlayMask then
            fd.overlayMask = button:CreateMaskTexture()
        end
        overlayMask = fd.overlayMask
        overlayMask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        overlayMask:ClearAllPoints()
        local inset = 3
        Pix.Point(overlayMask, "TOPLEFT", button, "TOPLEFT", inset, -inset)
        Pix.Point(overlayMask, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
        overlayMask:Show()
    else
        -- No border overlays share the main mask, hide overlay mask if it exists
        if fd.overlayMask then
            fd.overlayMask:Hide()
        end
        overlayMask = mask
    end

    -- Apply overlay mask to all button overlay textures
    if button.HighlightTexture then
        pcall(button.HighlightTexture.AddMaskTexture, button.HighlightTexture, overlayMask)
    end
    if button.PushedTexture then
        pcall(button.PushedTexture.AddMaskTexture, button.PushedTexture, overlayMask)
    end
    if button.CheckedTexture then
        pcall(button.CheckedTexture.AddMaskTexture, button.CheckedTexture, overlayMask)
    end
    if button.NewActionTexture then
        pcall(button.NewActionTexture.AddMaskTexture, button.NewActionTexture, overlayMask)
    end
    if button.Flash then
        pcall(button.Flash.AddMaskTexture, button.Flash, overlayMask)
    end
    if button.QuickKeybindHighlightTexture then
        pcall(button.QuickKeybindHighlightTexture.AddMaskTexture, button.QuickKeybindHighlightTexture, overlayMask)
    end
    -- The equipped-item Border follows the shape like the overlays above
    -- (Equipped Item Color); with that option off it stays hidden.
    if button.Border then
        pcall(button.Border.AddMaskTexture, button.Border, overlayMask)
        if not ABAR.db.profile.showEquippedBorder then
            button.Border:Hide()
        end
    end
    if fd.slotBG then
        pcall(fd.slotBG.AddMaskTexture, fd.slotBG, mask)
    end
    if fd.iconBg then
        pcall(fd.iconBg.AddMaskTexture, fd.iconBg, mask)
    end
    local nt = button.NormalTexture or button:GetNormalTexture()
    if nt then
        pcall(nt.AddMaskTexture, nt, overlayMask)
    end

    -- Expand icon beyond button frame
    local shapeOffset = SHAPE_ICON_EXPAND_OFFSETS[shape] or 0
    local shapeDefault = (SHAPE_ZOOM_DEFAULTS[shape] or 6.0) / 100
    local iconExp = SHAPE_ICON_EXPAND + shapeOffset + ((zoom or 0) - shapeDefault) * 200
    if iconExp < 0 then
        iconExp = 0
    end
    local halfIE = iconExp / 2
    if iconTex then
        iconTex:ClearAllPoints()
        Pix.Point(iconTex, "TOPLEFT", button, "TOPLEFT", -halfIE, halfIE)
        Pix.Point(iconTex, "BOTTOMRIGHT", button, "BOTTOMRIGHT", halfIE, -halfIE)
    end

    -- Mask inset for border
    mask:ClearAllPoints()
    if brdSize and brdSize >= 1 then
        Pix.Point(mask, "TOPLEFT", button, "TOPLEFT", 1, -1)
        Pix.Point(mask, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    else
        mask:SetAllPoints(button)
    end

    -- Expand texcoords
    local insetPx = SHAPE_INSETS[shape] or 17
    local visRatio = (128 - 2 * insetPx) / 128
    local expand = ((1 / visRatio) - 1) * 0.5
    if iconTex then
        iconTex:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand)
    end

    -- Hide square borders (both PP and textured)
    if fd.borders then
        Pix.HideBorder(button)
        if CludesUI._bdBorderData then
            local bdFrame = CludesUI._bdBorderData[button]
            if bdFrame then
                bdFrame:Hide()
            end
        end
    end

    -- Shape border texture
    if not fd.shapeBorder then
        fd.shapeBorder = button:CreateTexture(nil, "OVERLAY", nil, 6)
    end
    local borderTex = fd.shapeBorder
    pcall(borderTex.RemoveMaskTexture, borderTex, mask)
    borderTex:ClearAllPoints()
    borderTex:SetAllPoints(button)
    local btfd = EFD(borderTex)
    if brdOn and SHAPE_BORDERS[shape] then
        borderTex:SetTexture(SHAPE_BORDERS[shape])
        borderTex:SetVertexColor(brdR, brdG, brdB, brdA)
        borderTex:Show()
        btfd.wantsShow = true
    else
        borderTex:Hide()
        btfd.wantsShow = false
    end

    -- Apply mask to cooldown frames so swipe follows the shape
    if button.cooldown and not button.cooldown:IsForbidden() then
        pcall(button.cooldown.AddMaskTexture, button.cooldown, mask)
        if button.cooldown.SetSwipeTexture then
            pcall(button.cooldown.SetSwipeTexture, button.cooldown, maskTex)
        end
    end
    if button.chargeCooldown and not button.chargeCooldown:IsForbidden() then
        pcall(button.chargeCooldown.AddMaskTexture, button.chargeCooldown, mask)
        if button.chargeCooldown.SetSwipeTexture then
            pcall(button.chargeCooldown.SetSwipeTexture, button.chargeCooldown, maskTex)
        end
    end

    -- Mask proc glow animation frames
    if button.SpellActivationAlert then
        MaskFrameTextures(button.SpellActivationAlert, overlayMask)
        EFD(button.SpellActivationAlert).shapeMasked = true
    end
    if fd.glowWrapper then
        local wid = fd.glowWrapper
        local wfd = EFD(wid)
        if not wfd.ownMask then
            wfd.ownMask = wid:CreateMaskTexture()
        end
        wfd.ownMask:ClearAllPoints()
        Pix.Point(wfd.ownMask, "TOPLEFT", button, "TOPLEFT", 1, -1)
        Pix.Point(wfd.ownMask, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        wfd.ownMask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        wfd.ownMask:Show()
        MaskFrameTextures(wid, wfd.ownMask)
    end

    -- Store shape tracking flags for cooldown edge system
    fd.shapeApplied = true
    fd.shapeName = shape
    fd.shapeMaskPath = maskTex

    -- Apply shape-specific cooldown edge: circular edge for non-square shapes,
    -- per-shape scale, custom texture + current color.
    local shapeEdgeScale = SHAPE_EDGE_SCALES[shape] or 0.60
    local useCircular = (shape ~= "square" and shape ~= "csquare")
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
        for _, cd in ipairs({ button.cooldown, button.chargeCooldown }) do
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

    fd.cropped = false
end

-- Entry points the files after this one re-import by name.
Inner.SetSquareTexture = SetSquareTexture
Inner.ApplyButtonBorders = ApplyButtonBorders
Inner.ApplyShapeToButton = ApplyShapeToButton
Inner.MaskFrameTextures = MaskFrameTextures
