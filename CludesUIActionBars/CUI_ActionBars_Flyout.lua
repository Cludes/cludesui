if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI Action Bars - Spell Flyout Reskin
--  Reskins Blizzard's native SpellFlyout buttons to match the parent bar's
--  shape, borders, and zoom. Purely visual -- no secure state is touched.
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...

local SHAPE_MASKS = mod.SHAPE_MASKS
local SHAPE_BORDERS = mod.SHAPE_BORDERS
local SHAPE_ZOOM_DEFAULTS = mod.SHAPE_ZOOM_DEFAULTS
local SHAPE_ICON_EXPAND = mod.SHAPE_ICON_EXPAND
local SHAPE_ICON_EXPAND_OFFSETS = mod.SHAPE_ICON_EXPAND_OFFSETS
local SHAPE_INSETS = mod.SHAPE_INSETS
local ResolveBorderThickness = mod.ResolveBorderThickness
local ABAR = mod.EAB
local EFD = mod.EFD

-------------------------------------------------------------------------------
--  SkinBlizzardFlyoutButton
--  Apply shape/border/zoom to a single SpellFlyout button.
-------------------------------------------------------------------------------
local function SkinBlizzardFlyoutButton(button, shape, zoom, brdOn, cr, cg, cb, ca, sbR, sbG, sbB, sbA, brdSz)
    -- Strip default Blizzard art (one-time)
    local fd = EFD(button)
    if not fd.blizzStripped then
        fd.blizzStripped = true
        local nt = button.NormalTexture or button:GetNormalTexture()
        if nt then
            nt:SetAlpha(0)
        end
        if button.IconMask and CludesUI and CludesUI._hiddenParent then
            button.IconMask:SetParent(CludesUI._hiddenParent)
        end
    end

    local icon = button.icon or button.Icon
    if not icon then
        return
    end

    if shape ~= "none" and shape ~= "cropped" and SHAPE_MASKS and SHAPE_MASKS[shape] then
        local maskTex = SHAPE_MASKS[shape]
        if not fd.shapeMask then
            fd.shapeMask = button:CreateMaskTexture()
        end
        local mask = fd.shapeMask
        mask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:ClearAllPoints()
        if brdSz and brdSz >= 1 then
            local Pix = CludesUI and CludesUI.PP
            if Pix then
                Pix.Point(mask, "TOPLEFT", button, "TOPLEFT", 1, -1)
                Pix.Point(mask, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
            else
                mask:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
                mask:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
            end
        else
            mask:SetAllPoints(button)
        end
        mask:Show()
        pcall(icon.RemoveMaskTexture, icon, mask)
        icon:AddMaskTexture(mask)

        -- Expand icon for shape inset
        local shapeOffset = SHAPE_ICON_EXPAND_OFFSETS and SHAPE_ICON_EXPAND_OFFSETS[shape] or 0
        local shapeDefault = (SHAPE_ZOOM_DEFAULTS and SHAPE_ZOOM_DEFAULTS[shape] or 6.0) / 100
        local iconExp = (SHAPE_ICON_EXPAND or 0) + shapeOffset + ((zoom or 0) - shapeDefault) * 200
        if iconExp < 0 then
            iconExp = 0
        end
        local halfIE = iconExp / 2
        local Pix = CludesUI and CludesUI.PP
        if Pix then
            icon:ClearAllPoints()
            Pix.Point(icon, "TOPLEFT", button, "TOPLEFT", -halfIE, halfIE)
            Pix.Point(icon, "BOTTOMRIGHT", button, "BOTTOMRIGHT", halfIE, -halfIE)
        end

        -- Shape texcoord expand
        local insetPx = SHAPE_INSETS and SHAPE_INSETS[shape] or 17
        local visRatio = (128 - 2 * insetPx) / 128
        local expand = ((1 / visRatio) - 1) * 0.5
        icon:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand)

        -- Mask cooldown
        if button.cooldown and not button.cooldown:IsForbidden() then
            pcall(button.cooldown.RemoveMaskTexture, button.cooldown, mask)
            pcall(button.cooldown.AddMaskTexture, button.cooldown, mask)
            if button.cooldown.SetSwipeTexture then
                pcall(button.cooldown.SetSwipeTexture, button.cooldown, maskTex)
            end
            if button.cooldown.SetUseCircularEdge then
                pcall(button.cooldown.SetUseCircularEdge, button.cooldown, true)
            end
        end

        -- Shape border
        if not fd.shapeBorder then
            fd.shapeBorder = button:CreateTexture(nil, "OVERLAY", nil, 6)
        end
        local borderTex = fd.shapeBorder
        pcall(borderTex.RemoveMaskTexture, borderTex, mask)
        borderTex:ClearAllPoints()
        borderTex:SetAllPoints(button)
        if brdOn and SHAPE_BORDERS and SHAPE_BORDERS[shape] then
            borderTex:SetTexture(SHAPE_BORDERS[shape])
            borderTex:SetVertexColor(sbR, sbG, sbB, sbA)
            borderTex:Show()
        else
            borderTex:Hide()
        end

        if fd.borders and CludesUI and CludesUI.PP then
            CludesUI.PP.HideBorder(button)
        end
    else
        -- Square / cropped / none
        if fd.shapeMask then
            pcall(icon.RemoveMaskTexture, icon, fd.shapeMask)
            if button.cooldown and not button.cooldown:IsForbidden() then
                pcall(button.cooldown.RemoveMaskTexture, button.cooldown, fd.shapeMask)
                pcall(button.cooldown.SetSwipeTexture, button.cooldown, "")
            end
            fd.shapeMask:Hide()
        end
        if fd.shapeBorder then
            fd.shapeBorder:Hide()
        end

        icon:ClearAllPoints()
        icon:SetAllPoints(button)
        if shape == "cropped" then
            local z = zoom or 0
            icon:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
        elseif zoom and zoom > 0 then
            icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        else
            icon:SetTexCoord(0, 1, 0, 1)
        end

        local Pix = CludesUI and CludesUI.PP
        if Pix then
            if brdOn then
                if not fd.borders then
                    Pix.CreateBorder(button, 0, 0, 0, 1, 1, "OVERLAY", -1)
                    fd.borders = Pix.GetBorders(button)
                end
                Pix.UpdateBorder(button, brdSz, cr, cg, cb, ca)
                Pix.ShowBorder(button)
            elseif fd.borders then
                Pix.HideBorder(button)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  OnBlizzardFlyoutShow
--  Fired via HookScript on SpellFlyout. Reads the parent button's bar
--  settings and applies styling to every visible flyout button.
-------------------------------------------------------------------------------
local function OnBlizzardFlyoutShow(flyout)
    local caller = flyout:GetParent()
    if not caller then
        return
    end

    local barId = EFD(caller).barKey
    if not barId then
        return
    end

    local prof = ABAR and ABAR.db and ABAR.db.profile
    if not prof then
        return
    end
    local s = prof.bars and prof.bars[barId]
    if not s then
        return
    end

    local shape = s.buttonShape or "none"
    local zoom = (s.iconZoom or prof.iconZoom or 5.5) / 100
    local brdSz, brdPx = ResolveBorderThickness(s)
    local brdOn = brdSz > 0
    -- The flyout border is always solid strips: the bar's exact size flows only
    -- when the bar itself is solid (a textured bar's exact size is its edge art).
    if brdPx and (s.borderTexture or "solid") == "solid" then
        brdSz = brdPx
    end
    local brdColor = s.borderColor or { r = 0, g = 0, b = 0, a = 1 }
    local cr, cg, cb, ca = brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
    if s.borderClassColor then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then
                cr, cg, cb = cc.r, cc.g, cc.b
            end
        end
    end
    local shapeBrdColor = s.shapeBorderColor or brdColor
    local sbR, sbG, sbB, sbA = shapeBrdColor.r, shapeBrdColor.g, shapeBrdColor.b, shapeBrdColor.a or 1
    if s.borderClassColor then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then
                sbR, sbG, sbB = cc.r, cc.g, cc.b
            end
        end
    end

    -- Hide Blizzard's flyout background art (re-applied every show,
    -- Blizzard resets these textures each time the flyout opens)
    if flyout.Background then
        if flyout.Background.End then
            flyout.Background.End:SetAlpha(0)
        end
        if flyout.Background.Start then
            flyout.Background.Start:SetAlpha(0)
        end
        if flyout.Background.HorizontalMiddle then
            flyout.Background.HorizontalMiddle:SetAlpha(0)
        end
        if flyout.Background.VerticalMiddle then
            flyout.Background.VerticalMiddle:SetAlpha(0)
        end
    end

    -- Skin each visible button. Classic WoW UI: the vanilla ring at the
    -- flyout button's own size in place of the CUI shape/border skin, painted
    -- once per button (its size never changes; the paint stamps classicArt
    -- in the button's record).
    local classic = mod.AB_Style() == "classic"
    local children = { flyout:GetChildren() }
    for idx = 1, #children do
        local childFrame = children[idx]
        if childFrame and childFrame:IsShown() and childFrame.icon then
            if classic then
                if not mod.EFD(childFrame).classicArt then
                    mod.AB_PaintClassicButton(childFrame)
                end
            else
                SkinBlizzardFlyoutButton(
                    childFrame,
                    shape,
                    zoom,
                    brdOn,
                    cr,
                    cg,
                    cb,
                    ca,
                    sbR,
                    sbG,
                    sbB,
                    sbA,
                    brdSz
                )
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Hook Installation (at login, with PLAYER_ENTERING_WORLD as the retry when
--  SpellFlyout is not there yet).
-------------------------------------------------------------------------------
local function InstallBlizzFlyoutHook()
    local scrollFrame = _G.SpellFlyout
    if not scrollFrame or not EFD then
        return false
    end
    if EFD(scrollFrame).hooked then
        return true
    end
    EFD(scrollFrame).hooked = true
    scrollFrame:HookScript("OnShow", OnBlizzardFlyoutShow)
    return true
end
do
    -- Shell from the main file's pool: born at ActionBars' file scope so the
    -- handler work bills this addon (see the pool note there).
    local hookFrame = mod.TakeShell()
    hookFrame:RegisterEvent("PLAYER_LOGIN")
    hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    hookFrame:SetScript("OnEvent", function(self)
        if InstallBlizzFlyoutHook() then
            self:UnregisterAllEvents()
            self:SetScript("OnEvent", nil)
        end
    end)
end

-------------------------------------------------------------------------------
--  EABFlyout API (thin wrapper over Blizzard's SpellFlyout)
--  The main file calls IsVisible/IsMouseOver/GetFrame for mouseover-fade
--  logic (keep bar visible while flyout is open). RegisterButton is now
--  a no-op since Blizzard handles flyout dispatch natively.
-------------------------------------------------------------------------------
local EABFlyout = {}

function EABFlyout:RegisterButton() end

function EABFlyout:IsVisible()
    local scrollFrame = _G.SpellFlyout
    return scrollFrame and scrollFrame:IsVisible()
end

function EABFlyout:IsMouseOver(...)
    local scrollFrame = _G.SpellFlyout
    return scrollFrame and scrollFrame:IsMouseOver(...)
end

function EABFlyout:GetFrame()
    return _G.SpellFlyout
end

function EABFlyout:GetParent()
    local scrollFrame = _G.SpellFlyout
    return scrollFrame and scrollFrame:GetParent()
end

mod.EABFlyout = EABFlyout
