if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Bags_Shared.lua
--
--  The pieces the bank shares through ns (inset border, item button skin,
--  sidebar header, grid scrollbar), controller support and the stack
--  splitter.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local mod = select(2, ...)
local Inner = mod._bagsInternals
-- CludesUIBags.lua or an earlier CUI_Bags_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local GetItemInfoInstant = C_Item.GetItemInfoInstant
local CUI = CludesUI

local BP, GetFont, SetBagFont = Inner.BP, Inner.GetFont, Inner.SetBagFont

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._bagsInternals, which hands the value to every copy.
local selectedCategoryIndex = Inner.selectedCategoryIndex
Inner.categoryIndexSetters[#Inner.categoryIndexSetters + 1] = function(val)
    selectedCategoryIndex = val
end

-------------------------------------------------------------------------------
--  Inset border helper (1 physical pixel inside frame edge)
-------------------------------------------------------------------------------
local FV_SLOT_FRAME = "Interface\\Buttons\\UI-Quickslot2"
local FV_QUALITY_FRAME = "Interface\\Common\\WhiteIconFrame"

local function CreateInsetBorder(button, isSlot, iconTex)
    if isSlot and mod.BagsForever() then
        local widget = button:CreateTexture(nil, "OVERLAY")
        widget:SetAllPoints(button)
        widget:SetTexture(FV_SLOT_FRAME)
        -- The visible 37x37 area of the stock 64x64 rim, centered one unit down.
        widget:SetTexCoord(13.5 / 64, 50.5 / 64, 12.5 / 64, 49.5 / 64)
        local mask = button.Mask
        if not mask then
            mask = button:CreateMaskTexture()
            mask:SetAllPoints(button)
            mask:SetTexture(
                "Interface\\Common\\common-iconmask",
                "CLAMPTOBLACKADDITIVE",
                "CLAMPTOBLACKADDITIVE"
            )
        end
        widget:AddMaskTexture(mask)
        if iconTex then
            iconTex:AddMaskTexture(mask)
            button._fvIconMask = mask
        elseif button.icon then
            button.icon:AddMaskTexture(mask)
        end
        button._fvSlotBorder = widget
        return
    end
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    local WHITE = "Interface\\Buttons\\WHITE8X8"
    local tex = button:CreateTexture(nil, "OVERLAY", nil, 2)
    tex:SetTexture(WHITE)
    tex:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    tex:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    tex:SetHeight(px)
    local widget = button:CreateTexture(nil, "OVERLAY", nil, 2)
    widget:SetTexture(WHITE)
    widget:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    widget:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    widget:SetHeight(px)
    local l = button:CreateTexture(nil, "OVERLAY", nil, 2)
    l:SetTexture(WHITE)
    l:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    l:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    l:SetWidth(px)
    local region = button:CreateTexture(nil, "OVERLAY", nil, 2)
    region:SetTexture(WHITE)
    region:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    region:SetWidth(px)
    button._brdT, button._brdB, button._brdL, button._brdR = tex, widget, l, region
end

local function SetInsetBorderColor(button, cr, cg, callback, ca)
    local widget = button._fvSlotBorder
    if widget then
        widget.r, widget.g, widget.b, widget.a = cr, cg, callback, ca
        local color = ca > 0 and (cr ~= cg or cg ~= callback or cr > 0.25)
        local shade = not color and cr < 0.25 and cr or 1
        widget:SetVertexColor(shade, shade, shade, ca)
        local glow = button._fvQualityBorder
        if color and not glow then
            glow = button:CreateTexture(nil, "OVERLAY", nil, 1)
            glow:SetAllPoints(button)
            glow:SetTexture(FV_QUALITY_FRAME)
            button._fvQualityBorder = glow
        end
        if glow then
            glow:SetShown(color)
            if color then
                glow:SetVertexColor(cr, cg, callback, ca)
            end
        end
    elseif button._brdT then
        button._brdT:SetColorTexture(cr, cg, callback, ca)
        button._brdB:SetColorTexture(cr, cg, callback, ca)
        button._brdL:SetColorTexture(cr, cg, callback, ca)
        button._brdR:SetColorTexture(cr, cg, callback, ca)
    end
end

local function GetInsetBorderStyle(button)
    local widget = button._fvSlotBorder
    if widget then
        return widget.r, widget.g, widget.b, widget.a
    end
    local topY = button._brdT
    if not topY then
        return
    end
    local red, green, blue, a = topY:GetVertexColor()
    return red, green, blue, a, topY:GetHeight()
end

-- Border thickness in px (1 normally, 2 for quest items); must be re-applied per render because item buttons are pooled.
local function SetInsetBorderThickness(button, px)
    if button._brdT then
        button._brdT:SetHeight(px)
        button._brdB:SetHeight(px)
        button._brdL:SetWidth(px)
        button._brdR:SetWidth(px)
    end
end

-------------------------------------------------------------------------------
--  Shared with the bank (CludesUIBags_Bank.lua loads after this file) via ns
-------------------------------------------------------------------------------
mod.CreateInsetBorder = CreateInsetBorder
mod.SetBagFont = SetBagFont
mod.SetInsetBorderColor = SetInsetBorderColor

function mod.GetSlotQuestFlags(bag, slot)
    local details = C_Container.GetContainerItemQuestInfo(bag, slot)
    if details and (details.isQuestItem or details.questID) then
        return true, details.questID and not details.isActive or nil
    end
end

function mod.SetForeverSlotQuestBorder(button, isQuest, isStarter)
    local edgeTex = button._fvQuestBorder
    if isQuest then
        if not edgeTex then
            edgeTex = button:CreateTexture(nil, "OVERLAY", nil, 2)
            edgeTex:SetPoint("TOPLEFT", button, "TOPLEFT")
            edgeTex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, -1)
            button._fvQuestBorder = edgeTex
        end
        local asset = isStarter and TEXTURE_ITEM_QUEST_BANG or TEXTURE_ITEM_QUEST_BORDER
        if edgeTex._asset ~= asset then
            edgeTex._asset = asset
            edgeTex:SetTexture(asset)
        end
        edgeTex:Show()
    elseif edgeTex then
        edgeTex:Hide()
    end
end

-- Item buttons (ContainerFrameItemButtonTemplate) carry frameLevel="10" in
-- Blizzard's XML, a fixed level that never follows their window: under a window
-- raised past it (High starts at 100) the window takes the clicks. So each one
-- sits at its window's level + 9: the template's own 10 over a window at level 1,
-- under Compact's drop zones (window + 22). The text overlay (+3, above the
-- cooldown swipe) and the warbank dim (+6) are fixed levels too and move with it.
local function PinItemButtonLevel(button, level)
    button:SetFrameLevel(level)
    if button._textOverlay then
        button._textOverlay:SetFrameLevel(level + 3)
    end
    if button._warbankDim then
        button._warbankDim:SetFrameLevel(level + 6)
    end
end

-- background color/opacity for bags and bank: the texture fades with the
-- opacity, the tint on top takes the color
function mod.ApplyWindowBackground(backdrop, overlayFrame)
    if not (backdrop and overlayFrame) then
        return
    end
    local profile = BP()
    local o = (profile.bagBgOpacity or 100) / 100
    local color = profile.bagBgColor
    backdrop:SetAlpha(o)
    overlayFrame:SetColorTexture(color and color.r or 0, color and color.g or 0, color and color.b or 0, color and color.a or 0.25)
    overlayFrame:SetAlpha(o)
end

local slotBackgroundAtlases
function mod.SetSlotBackgroundTexture(texture, interactive)
    if mod.BagsForever() then
        if not slotBackgroundAtlases then
            slotBackgroundAtlases = {}
        end
        local atlas = interactive and "bags-item-slot64" or "bags-item-slot-blank"
        local exists = slotBackgroundAtlases[atlas]
        if exists == nil then
            exists = C_Texture.GetAtlasInfo(atlas) ~= nil
            slotBackgroundAtlases[atlas] = exists
        end
        if exists then
            texture:SetAtlas(atlas)
            return
        end
    end
    texture:SetTexture("Interface\\AddOns\\CludesUIBags\\Media\\icon-bg.png")
end

-- Tint over an empty slot's backdrop. Keep painted regions weakly so a
-- color change can retint them without a relayout.
local slotBgs = setmetatable({}, { __mode = "k" })
function mod.PaintSlotBackground(texture, alpha)
    texture._slotBgAlpha = alpha
    slotBgs[texture] = true
    local color = BP().bagSlotBgColor
    if color then
        texture:SetVertexColor(color.r, color.g, color.b)
        texture:SetAlpha(alpha * (color.a or 1))
    else
        texture:SetVertexColor(1, 1, 1)
        texture:SetAlpha(alpha)
    end
end

-- the slot background picker: just the shown ones (hidden ones get painted when they show)
function mod.RetintSlotBackgrounds()
    for texture in pairs(slotBgs) do
        if texture:IsVisible() then
            mod.PaintSlotBackground(texture, texture._slotBgAlpha)
        end
    end
end

function mod.PinItemButton(button, window)
    PinItemButtonLevel(button, window:GetFrameLevel() + 9)
end

-- Re-pins a pool after its window's level moved (a strata change, a raise), once
-- per level: window[memoKey] holds the level the pool was last pinned at. Nothing
-- else moves these buttons, and new ones are pinned at creation from the live level.
function mod.PinItemPool(pool, window, memoKey)
    local level = window:GetFrameLevel() + 9
    if window[memoKey] == level then
        return
    end
    window[memoKey] = level
    for _, button in pairs(pool) do
        PinItemButtonLevel(button, level)
    end
end

-- WoW Forever's item buttons round the icon and the pushed art with the
-- button's own Mask (retail's templates carry IconMask, stripped where the
-- slots are skinned). The bags draw both square.
local function DropMask(texture, m)
    if not texture then
        return
    end
    for index = texture:GetNumMaskTextures(), 1, -1 do
        if texture:GetMaskTexture(index) == m then
            texture:RemoveMaskTexture(m)
        end
    end
end
function mod.UnmaskItemButton(button)
    local m = button.Mask
    if not m then
        return
    end
    DropMask(button.icon, m)
    DropMask(button:GetPushedTexture(), m)
end

-- An item's icon on a slot. WoW Forever's SetItemButtonTexture resets the
-- icon's crop on every call (retail's keeps it), so the zoom goes back on.
function mod.SetSlotIcon(button, texture)
    button:SetItemButtonTexture(texture)
    local zoom = BP().bagItemIconZoom or 0.08
    button.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
end

-- Flat look for a ContainerFrameItemButtonTemplate slot, plus the text overlay
-- (above the cooldown swipe) with Count, ItemLevelText and BindTypeText.
-- Methods only: writing properties onto Blizzard template sub-objects taints.
-- opts: anchorIcon (re-anchor icon to the button), cooldownFont (restyle the
-- cooldown text), flatHighlight (bank: 8% white highlight, with highlight and
-- pushed textures looked up by template field first). Returns the overlay.
function mod.SkinItemButton(button, options)
    if button.NewItemTexture then
        button.NewItemTexture:Hide()
        button.NewItemTexture:SetAlpha(0)
    end
    if button.BattlepayItemTexture then
        button.BattlepayItemTexture:Hide()
        button.BattlepayItemTexture:SetAlpha(0)
    end
    if button.flash then
        button.flash:Hide()
        button.flash:SetAlpha(0)
    end
    if button.newitemglowAnim then
        button.newitemglowAnim:Stop()
    end

    mod.SizeSlot(button)
    if button.icon then
        local zoom = BP().bagItemIconZoom or 0.08
        button.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        if options.anchorIcon then
            button.icon:ClearAllPoints()
            button.icon:SetAllPoints(button)
        end
    end

    local ht, point
    if options.flatHighlight then
        ht = button.HighlightTexture or button:GetHighlightTexture()
        if ht then
            ht:SetTexture(nil)
            ht:SetColorTexture(1, 1, 1, 0.08)
        end
        point = button.PushedTexture or button:GetPushedTexture()
    else
        ht = button:GetHighlightTexture()
        point = button:GetPushedTexture()
    end
    if ht then
        ht:ClearAllPoints()
        ht:SetAllPoints(button)
    end
    if point then
        point:SetAtlas(nil)
        point:SetTexture("Interface\\AddOns\\CludesUIBags\\Media\\highlight-3.png")
        point:SetTexCoord(0, 1, 0, 1)
        point:ClearAllPoints()
        point:SetAllPoints(button)
        point:SetVertexColor(0.973, 0.839, 0.604, 1)
    end

    if button.NormalTexture then
        button.NormalTexture:SetAlpha(0)
    end
    if button.IconBorder then
        button.IconBorder:SetAlpha(0)
    end

    if button.icon and button.IconMask then
        button.icon:RemoveMaskTexture(button.IconMask)
        button.IconMask:Hide()
        button.IconMask:SetTexture(nil)
        button.IconMask:ClearAllPoints()
        button.IconMask:SetSize(0.001, 0.001)
    end
    mod.UnmaskItemButton(button)

    if options.cooldownFont and button.Cooldown then
        local cdText = button.Cooldown:GetRegions()
        if cdText and cdText.SetFont then
            CludesUI.ApplyIconTextFont(cdText, GetFont(), 11, "bags")
        end
    end

    CreateInsetBorder(button, true)
    SetInsetBorderColor(button, 0.25, 0.25, 0.25, 1)

    local textOverlay = CreateFrame("Frame", nil, button)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel(button:GetFrameLevel() + 3)
    button._textOverlay = textOverlay

    local fontFile = GetFont()
    local outline = (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    local countFS = button.Count
    if countFS then
        countFS:SetParent(textOverlay)
        CludesUI.ApplyIconTextFont(countFS, fontFile, BP().bagCountFontSize or 11, "bags")
        countFS:ClearAllPoints()
        countFS:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    end

    -- Item level text (top-left, gear only)
    if not button.ItemLevelText then
        button.ItemLevelText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        button.ItemLevelText:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        button.ItemLevelText:SetTextColor(1, 1, 1, 1)
    end
    button.ItemLevelText:SetFont(fontFile, BP().itemlevelFontSize or 12, outline)
    button.ItemLevelText:SetText("")

    -- Bind Type text (bottom-left)
    if not button.BindTypeText then
        button.BindTypeText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        button.BindTypeText:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 2)
        button.BindTypeText:SetTextColor(1, 1, 1, 1)
    end
    button.BindTypeText:SetFont(fontFile, BP().bagBindTypeFontSize or 11, outline)
    button.BindTypeText:SetText("")
    return textOverlay
end

-- The sidebar's 12 px collapse / expand arrow (the caller anchors it and turns
-- its icon): 0.4 alpha, 0.9 on hover with its tooltip (a string, or a
-- function returning one).
do
    local function ArrowOnEnter(self)
        self._icon:SetAlpha(0.9)
        local tipText = self._tip
        if type(tipText) == "function" then
            tipText = tipText()
        end
        CUI.ShowWidgetTooltip(self, tipText)
    end
    local function ArrowOnLeave(self)
        self._icon:SetAlpha(0.4)
        CUI.HideWidgetTooltip()
    end
    function mod.SidebarArrowButton(hostFrame, tipText)
        local button = CreateFrame("Button", nil, hostFrame)
        button:SetSize(12, 12)
        button._icon = button:CreateTexture(nil, "OVERLAY")
        button._icon:SetAllPoints()
        button._icon:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-left.png")
        button._icon:SetAlpha(0.4)
        button._tip = tipText
        button:SetScript("OnEnter", ArrowOnEnter)
        button:SetScript("OnLeave", ArrowOnLeave)
        return button
    end
end

-- Sidebar header: label + collapse arrow for the profile flag dbKey. The
-- caller's OnClick flips the flag, then calls the returned UpdateArrow.
function mod.CreateSidebarHeader(sidebar, labelText, dbKey)
    local heading = CreateFrame("Frame", nil, sidebar)
    heading:SetHeight(24)
    heading:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)
    heading:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)

    heading._label = heading:CreateFontString(nil, "OVERLAY")
    SetBagFont(heading._label, 10)
    heading._label:SetPoint("LEFT", heading, "LEFT", 8, 0)
    heading._label:SetText(labelText)
    heading._label:SetTextColor(0.5, 0.5, 0.5)

    local collapseBtn = mod.SidebarArrowButton(heading, function()
        return BP()[dbKey] and "Expand Sidebar" or "Collapse Sidebar"
    end)

    local function UpdateArrow()
        collapseBtn:ClearAllPoints()
        if BP()[dbKey] then
            collapseBtn._icon:SetRotation(math.pi)
            collapseBtn:SetPoint("CENTER", heading, "CENTER", 0, 0)
        else
            collapseBtn._icon:SetRotation(0)
            collapseBtn:SetPoint("RIGHT", heading, "RIGHT", -6, 0)
        end
    end
    UpdateArrow()
    return heading, collapseBtn, UpdateArrow
end

-- Item-grid scrollbar: a 4px thumb in a 16px hit strip; the caller anchors the
-- returned track. Scrolls instantly, not smoothed (so not AttachSmoothScrollbar).
-- clamp: pull the scroll back into range on every update (content may have
-- shrunk). rawWheel: the wheel reads sf's scroll range directly rather than the
-- thumb metrics, which give up when the track is too short for a thumb.
local SCROLLBAR_HIT_W = 16 -- invisible hit area width
function mod.AttachGridScrollbar(owner, scrollFrame, clamp, rawWheel)
    local SCROLLBAR_W = 4 -- thumb width
    local SCROLL_STEP = 40 -- pixels per mouse wheel tick
    local THUMB_MIN_H = 20 -- minimum thumb height

    local rail = CreateFrame("Button", nil, owner)
    rail:SetWidth(SCROLLBAR_HIT_W)
    rail:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)

    local railBg = rail:CreateTexture(nil, "BACKGROUND")
    railBg:SetWidth(SCROLLBAR_W)
    railBg:SetPoint("TOP", rail, "TOP", 0, 0)
    railBg:SetPoint("BOTTOM", rail, "BOTTOM", 0, 0)
    railBg:SetPoint("RIGHT", rail, "RIGHT", 0, 0)
    railBg:SetColorTexture(1, 1, 1, 0.06)

    local knob = rail:CreateTexture(nil, "ARTWORK")
    knob:SetWidth(SCROLLBAR_W)
    knob:SetColorTexture(1, 1, 1, 0.25)
    knob:Hide()

    local _isDragging = false
    local _dragStartY = 0
    local _dragStartPct = 0

    local function GetScrollMetrics()
        local scrollRange = scrollFrame:GetVerticalScrollRange()
        if not scrollRange or scrollRange <= 0 then
            return nil
        end
        local trackH = rail:GetHeight()
        local ext = scrollFrame:GetHeight() / (scrollFrame:GetHeight() + scrollRange)
        local knobHeight = math.max(THUMB_MIN_H, trackH * ext)
        local travelMax = trackH - knobHeight
        if travelMax <= 0 then
            return nil
        end
        local percent = scrollFrame:GetVerticalScroll() / scrollRange
        return percent, knobHeight, travelMax, scrollRange
    end

    local function UpdateThumb()
        if clamp then
            local range = scrollFrame:GetVerticalScrollRange() or 0
            local current = scrollFrame:GetVerticalScroll()
            if current > range then
                scrollFrame:SetVerticalScroll(range)
            end
        end
        local percent, knobHeight, travelMax = GetScrollMetrics()
        if not percent then
            knob:Hide()
            railBg:Hide()
            return
        end
        knob:SetHeight(knobHeight)
        knob:ClearAllPoints()
        knob:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, -(percent * travelMax))
        knob:Show()
        railBg:Show()
    end

    -- On the scroll frame and on host (items might not cover the full area)
    local function OnWheel(_, delta)
        local scrollRange
        if rawWheel then
            scrollRange = scrollFrame:GetVerticalScrollRange()
            if scrollRange and scrollRange <= 0 then
                scrollRange = nil
            end
        else
            scrollRange = select(4, GetScrollMetrics())
        end
        if not scrollRange then
            return
        end
        local current = scrollFrame:GetVerticalScroll()
        local newVal = math.max(0, math.min(scrollRange, current - delta * SCROLL_STEP))
        scrollFrame:SetVerticalScroll(newVal)
        UpdateThumb()
    end
    scrollFrame:SetScript("OnMouseWheel", OnWheel)
    owner:EnableMouseWheel(true)
    owner:SetScript("OnMouseWheel", OnWheel)

    -- Thumb dragging (dragUpdate must be declared before OnMouseDown uses it)
    local dragUpdate = CreateFrame("Frame")
    dragUpdate:Hide()
    dragUpdate:SetScript("OnUpdate", function(self)
        if not _isDragging then
            self:Hide()
            return
        end
        if not IsMouseButtonDown("LeftButton") then
            _isDragging = false
            self:Hide()
            knob:SetColorTexture(1, 1, 1, 0.25)
            return
        end
        local percent, knobHeight, travelMax, scrollRange = GetScrollMetrics()
        if not percent then
            _isDragging = false
            self:Hide()
            return
        end
        local zoom = rail:GetEffectiveScale()
        local _, midY = GetCursorPosition()
        local deltaY = (_dragStartY - midY / zoom)
        local deltaPct = deltaY / travelMax
        local newPct = math.max(0, math.min(1, _dragStartPct + deltaPct))
        scrollFrame:SetVerticalScroll(newPct * scrollRange)
        UpdateThumb()
    end)

    rail:RegisterForDrag("LeftButton")
    rail:SetScript("OnMouseDown", function(_, btnFrame)
        if btnFrame ~= "LeftButton" then
            return
        end
        local percent, knobHeight, travelMax, scrollRange = GetScrollMetrics()
        if not percent then
            return
        end

        local zoom = rail:GetEffectiveScale()
        local _, midY = GetCursorPosition()
        local trackTop = rail:GetTop() * zoom
        local cursorLocalY = (trackTop - midY) / zoom

        -- Check if cursor is on the thumb
        local thumbTop = percent * travelMax
        local thumbBot = thumbTop + knobHeight
        if cursorLocalY >= thumbTop and cursorLocalY <= thumbBot then
            _isDragging = true
            _dragStartY = midY / zoom
            _dragStartPct = percent
            dragUpdate:Show()
        else
            -- Click on track: jump to position
            local clickPct = math.max(0, math.min(1, (cursorLocalY - knobHeight / 2) / travelMax))
            scrollFrame:SetVerticalScroll(clickPct * scrollRange)
            UpdateThumb()
            _isDragging = true
            _dragStartY = midY / zoom
            _dragStartPct = clickPct
            dragUpdate:Show()
        end
    end)

    rail:SetScript("OnMouseUp", function()
        _isDragging = false
    end)

    rail:SetScript("OnEnter", function()
        knob:SetColorTexture(1, 1, 1, 0.4)
    end)
    rail:SetScript("OnLeave", function()
        if not _isDragging then
            knob:SetColorTexture(1, 1, 1, 0.25)
        end
    end)

    -- Controller cursor (a pad has no wheel): one-notch step buttons at the
    -- track ends, a visible track, a thumb that follows every scroll (the
    -- cursor scrolls the grid itself) and a track that is not a cursor stop
    -- (a press there would jump to the hidden pointer). The owner calls
    -- track.PadSync(on) at its show edge; nothing is built before a
    -- controller is in use.
    local padUp, padDown, padOn
    local function PadSteps()
        local show = padOn and railBg:IsShown() or false
        padUp:SetShown(show)
        padDown:SetShown(show)
    end
    function rail.PadSync(enabled)
        enabled = enabled and true or false
        if not padUp then
            if not enabled then
                return
            end
            padUp, padDown = mod.PadStepButtons(owner, SCROLLBAR_HIT_W, function(delta)
                OnWheel(nil, delta)
            end)
            padUp:SetFrameLevel(rail:GetFrameLevel() + 1)
            padDown:SetFrameLevel(rail:GetFrameLevel() + 1)
            padUp:SetPoint("TOP", rail, "TOP", 0, 0)
            padDown:SetPoint("BOTTOM", rail, "BOTTOM", 0, 0)
            hooksecurefunc(railBg, "Show", PadSteps)
            hooksecurefunc(railBg, "Hide", PadSteps)
            scrollFrame:HookScript("OnVerticalScroll", function()
                UpdateThumb()
            end)
            CUI.PadHint(rail, "nodeignore")
        end
        if enabled == padOn then
            return
        end
        padOn = enabled
        railBg:SetColorTexture(1, 1, 1, enabled and 0.15 or 0.06)
        PadSteps()
    end
    return rail, knob, UpdateThumb
end

-------------------------------------------------------------------------------
--  Controller support (the bags and the bank). Everything here runs only on
--  an edge that already exists (a show, a click, a menu open) behind the
--  shared controller signal; mouse/keyboard players never build any of it.
-------------------------------------------------------------------------------
do
    local ARROW_UP = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-up3.png"
    local ARROW_DOWN = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-down3.png"

    local function MakeStep(hostFrame, size, iconTex, onClick)
        local widget = CreateFrame("Button", nil, hostFrame)
        widget:SetSize(size, size)
        local tex = widget:CreateTexture(nil, "OVERLAY")
        tex:SetSize(size - 4, size - 4)
        tex:SetPoint("CENTER", widget, "CENTER", 0, 0)
        tex:SetTexture(iconTex)
        widget:SetAlpha(0.5)
        widget:SetScript("OnEnter", function(self)
            self:SetAlpha(0.9)
        end)
        widget:SetScript("OnLeave", function(self)
            self:SetAlpha(0.5)
        end)
        widget:SetScript("OnClick", onClick)
        widget:Hide()
        return widget
    end

    -- Up/down step buttons for a wheel-only scroller: step(1) scrolls up one
    -- notch, step(-1) down. Created hidden; the caller anchors them.
    function mod.PadStepButtons(hostFrame, size, step)
        return MakeStep(hostFrame, size, ARROW_UP, function()
            step(1)
        end),
            MakeStep(hostFrame, size, ARROW_DOWN, function()
                step(-1)
            end)
    end

    -- Sidebar step buttons (categories, bank tabs) in the sidebar header, left
    -- of the collapse arrow: shown while a controller is in use, the sidebar
    -- is expanded and its entries overflow. Each click runs the sidebar's own
    -- wheel handler once (one entry). Called at the window's show edge.
    local function SidebarStepsUpdate(state)
        local show = state.on and not BP()[state.key] and (state.child:GetHeight() - state.sf:GetHeight()) > 0.5
        state.up:SetShown(show)
        state.down:SetShown(show)
    end

    function mod.PadSidebarSync(heading, scrollFrame, childFrame, dbKey, enabled)
        if not (heading and scrollFrame and childFrame) then
            return
        end
        local state = heading._padSteps
        if not state then
            if not enabled then
                return
            end
            local up, down = mod.PadStepButtons(heading, 14, function(delta)
                local wheel = scrollFrame:GetScript("OnMouseWheel")
                if wheel then
                    wheel(scrollFrame, delta)
                end
            end)
            down:SetPoint("RIGHT", heading, "RIGHT", -22, 0)
            up:SetPoint("RIGHT", down, "LEFT", -2, 0)
            state = { up = up, down = down, sf = scrollFrame, child = childFrame, key = dbKey }
            heading._padSteps = state
            -- The rebuild sets the list height; the window can resize it too.
            local function Update()
                SidebarStepsUpdate(state)
            end
            hooksecurefunc(childFrame, "SetHeight", Update)
            scrollFrame:HookScript("OnSizeChanged", Update)
        end
        state.on = enabled and true or false
        SidebarStepsUpdate(state)
    end

    -- Blizzard's bag frames live under a hidden parent. One that its own
    -- toggle opened keeps reporting shown after we close the bags ourselves,
    -- so the next Back press counts as "closed a bag" and does nothing else.
    -- Only frames that are shown but not visible (still under that parent)
    -- are touched, and no Blizzard OnHide runs for them.
    function mod.PadReleaseBlizzBags()
        local frame = ContainerFrameCombinedBags
        if frame and frame:IsShown() and not frame:IsVisible() then
            frame:Hide()
        end
        for index = 1, 13 do
            frame = _G["ContainerFrame" .. index]
            if frame and frame:IsShown() and not frame:IsVisible() then
                frame:Hide()
            end
        end
    end

    -- WoW Forever's Gamepad interface style navigates Blizzard's own bags and
    -- bank with the D-pad, so the takeover stands down for the session there.
    -- Decided once, at login; a later style switch asks for a reload, once.
    local standDown, styleAsked
    function mod.PadUIStandDown()
        if standDown == nil then
            standDown = CUI.PadGamepadUI()
        end
        return standDown
    end

    function mod.PadStyleChanged()
        if styleAsked then
            return
        end
        styleAsked = true
        -- The Gamepad style's D-pad cannot reach the popup, so chat says it too.
        -- A confirm, not RequestReload: this can run outside a click, which
        -- cannot reload; the popup's click can.
        CludesUI.PrintError(CludesUI.L("The interface style changed. Type /reload so the bags match it."))
        CUI:ShowConfirmPopup({
            title = CludesUI.L("Reload Required"),
            message = CludesUI.L("The interface style changed. Reload so the bags match it."),
            confirmText = CludesUI.L("Reload Now"),
            cancelText = CludesUI.L("Later"),
            reload = true,
        })
    end
end

-- Gold border for quest items (overrides the normal quality border).
local QUEST_BORDER_COLOR = { r = 1.0, g = 0.82, b = 0.0 }

-------------------------------------------------------------------------------
--  Stack splitter: replaces Blizzard's StackSplitFrame on our bag/bank slots
--  and on the guild bank's (opt-in) with a house dialog that adds Auto Split --
--  repeated splits into empty slots until the remainder is at most the chosen size.
-------------------------------------------------------------------------------
do
    local dialogFrame
    local task -- { bag, slot, itemID, size, targets, window, ops, pending, issuedAt }
    local StepJob

    -- Container and guild bank slots share the dialog and job; only the API differs.
    local containerOps = {
        ownerBag = function(ownerFrame)
            return ownerFrame:GetParent():GetID()
        end,
        info = C_Container.GetContainerItemInfo,
        numSlots = C_Container.GetContainerNumSlots,
        split = C_Container.SplitContainerItem,
        pickup = C_Container.PickupContainerItem,
    }
    local guildOps = {
        ownerBag = function()
            return GetCurrentGuildBankTab()
        end,
        -- A tab that is no longer viewed reads as empty so a running job stops there.
        info = function(tab, slot)
            if tab ~= GetCurrentGuildBankTab() then
                return nil
            end
            local texture, total, locked = GetGuildBankItemInfo(tab, slot)
            if not texture then
                return nil
            end
            local itemLink = GetGuildBankItemLink(tab, slot)
            return {
                stackCount = total,
                isLocked = locked,
                itemID = itemLink and GetItemInfoInstant(itemLink) or 0,
            }
        end,
        numSlots = function()
            return 98
        end,
        split = SplitGuildBankItem,
        pickup = PickupGuildBankItem,
    }

    local function StopJob()
        task = nil
    end

    -- Polled on a short timer. The new stack's slot can still read empty for a
    -- moment after the source count has updated, so slots already used as a
    -- destination are skipped for the rest of the job.
    local function Later()
        local this = task
        C_Timer.After(0.05, function()
            if task == this then
                StepJob()
            end
        end)
    end

    -- One split per server round trip: issue, wait for the source stack to
    -- settle at the expected count, repeat.
    StepJob = function()
        if not task then
            return
        end
        if not task.window:IsVisible() then
            StopJob()
            return
        end
        local opList = task.ops
        local details = opList.info(task.bag, task.slot)
        if not details or details.itemID ~= task.itemID then
            StopJob()
            return
        end
        if details.isLocked or (task.pending and details.stackCount ~= task.pending) then
            if GetTime() - task.issuedAt > 2 then
                ClearCursor()
                StopJob()
            else
                Later()
            end
            return
        end
        task.pending = nil
        if details.stackCount <= task.size then
            StopJob()
            return
        end
        for _, bagID in ipairs(task.targets) do
            for s = 1, opList.numSlots(bagID) do
                local key = bagID * 1000 + s
                if not task.used[key] and not opList.info(bagID, s) then
                    task.used[key] = true
                    ClearCursor()
                    opList.split(task.bag, task.slot, task.size)
                    opList.pickup(bagID, s)
                    -- Single placed split: one issue, no settle polling.
                    if task.once then
                        StopJob()
                        return
                    end
                    task.pending = details.stackCount - task.size
                    task.issuedAt = GetTime()
                    Later()
                    return
                end
            end
        end
        StopJob()
    end

    -- once = a single split placed into the first empty target slot (the views
    -- that draw no empty slots have nowhere to drop a cursor stack).
    local function StartJob(bag, slot, itemId, size, targets, window, opList, once)
        task = {
            bag = bag,
            slot = slot,
            itemID = itemId,
            size = size,
            targets = targets,
            window = window,
            ops = opList,
            used = {},
            issuedAt = GetTime(),
            once = once,
        }
        StepJob()
    end

    -- Closing the window a dialog or job belongs to ends it; other windows are unaffected.
    local function WindowHidden(win)
        if dialogFrame and dialogFrame._window == win then
            dialogFrame:Hide()
        end
        if task and task.window == win then
            StopJob()
        end
        -- Closing the bags ends every session unmerge; the next open merges again.
        if win == CUI_Bags and CUI_Bags._unmergedLinks then
            wipe(CUI_Bags._unmergedLinks)
        end
    end

    -- Re-checks the slot the dialog was opened on after every repaint: pooled
    -- buttons get repurposed, and the count can change under us.
    local function Validate()
        if not dialogFrame or not dialogFrame:IsShown() then
            return
        end
        local ownerFrame = dialogFrame._owner
        if
            not ownerFrame:IsVisible()
            or dialogFrame._ops.ownerBag(ownerFrame) ~= dialogFrame._bag
            or ownerFrame:GetID() ~= dialogFrame._slot
        then
            dialogFrame:Hide()
            return
        end
        local details = dialogFrame._ops.info(dialogFrame._bag, dialogFrame._slot)
        if
            not details
            or details.itemID ~= dialogFrame._itemID
            or not details.stackCount
            or details.stackCount < 2
        then
            dialogFrame:Hide()
            return
        end
        if details.stackCount ~= dialogFrame._max then
            dialogFrame:SetRange(1, details.stackCount)
            dialogFrame:SetValue(dialogFrame:Current())
        end
    end

    local function MakeButton(hostFrame, wid, hgt, labelText, Pix)
        local widget = CreateFrame("Button", nil, hostFrame)
        widget:SetSize(wid, hgt)
        local backdrop = widget:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.15, 0.15, 0.15, 1)
        if Pix and Pix.CreateBorder then
            Pix.CreateBorder(widget, 0.25, 0.25, 0.25, 1)
        end
        local fontStr = widget:CreateFontString(nil, "OVERLAY")
        SetBagFont(fontStr, 12)
        fontStr:SetPoint("CENTER", 0, 0)
        fontStr:SetTextColor(1, 1, 1, 0.9)
        fontStr:SetText(labelText)
        widget:SetScript("OnEnter", function()
            backdrop:SetColorTexture(0.2, 0.2, 0.2, 1)
        end)
        widget:SetScript("OnLeave", function()
            backdrop:SetColorTexture(0.15, 0.15, 0.15, 1)
        end)
        return widget
    end

    local function DoSplit(auto)
        local skinData = dialogFrame
        local bag, slot, num, opList = skinData._bag, skinData._slot, skinData:Current(), skinData._ops
        skinData:Hide()
        local details = opList.info(bag, slot)
        if
            not details
            or details.isLocked
            or details.itemID ~= skinData._itemID
            or not details.stackCount
            or num >= details.stackCount
        then
            return
        end
        -- Session unmerge mark, written BEFORE the split so the refresh it
        -- triggers already renders the pieces apart. Same link form the slot
        -- tables key on; bags and reagent window only (bank items never merge here).
        if skinData._window == CUI_Bags or skinData._window == CUI_BagsReagent then
            local itemLink = C_Container.GetContainerItemLink(bag, slot)
            if itemLink then
                local set = CUI_Bags._unmergedLinks
                if not set then
                    set = {}
                    CUI_Bags._unmergedLinks = set
                end
                set[itemLink] = true
            end
        end
        if auto or skinData._placeOnce then
            StartJob(bag, slot, details.itemID, num, skinData._targets, skinData._window, opList, not auto)
        else
            ClearCursor()
            opList.split(bag, slot, num)
        end
    end

    -- The splitter's own dark look on the shared quantity window
    -- (CludesUI.CreateQuantityDialog).
    local SKIN = {
        frame = function(skinData)
            local Pix = CUI.PP
            local backdrop = skinData:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(0.067, 0.067, 0.067, 0.95)
            if Pix and Pix.CreateBorder then
                Pix.CreateBorder(skinData, 0.2, 0.2, 0.2, 1)
            end
        end,
        font = SetBagFont,
        button = function(hostFrame, wid, hgt, labelText)
            return MakeButton(hostFrame, wid, hgt, labelText, CUI.PP)
        end,
        editBox = function(eb)
            local Pix = CUI.PP
            eb:SetFont(GetFont(), 12, "")
            local ebBg = eb:CreateTexture(nil, "BACKGROUND")
            ebBg:SetAllPoints()
            ebBg:SetColorTexture(0.1, 0.1, 0.1, 1)
            if Pix and Pix.CreateBorder then
                Pix.CreateBorder(eb, 0.15, 0.15, 0.15, 1)
            end
        end,
        close = function(closeBtn)
            closeBtn:SetSize(12, 12)
            closeBtn:SetPoint("TOPRIGHT", closeBtn:GetParent(), "TOPRIGHT", -9, -9)
            closeBtn.icon = closeBtn:CreateTexture(nil, "OVERLAY")
            closeBtn.icon:SetAllPoints()
            closeBtn.icon:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png")
            closeBtn.icon:SetAlpha(0.7)
            closeBtn:SetScript("OnEnter", function()
                closeBtn.icon:SetAlpha(0.9)
            end)
            closeBtn:SetScript("OnLeave", function()
                closeBtn.icon:SetAlpha(0.7)
            end)
        end,
    }

    local function CreateDialog()
        local skinData = CUI.CreateQuantityDialog({
            name = "CUI_BagsStackSplitFrame",
            width = 206,
            height = 94,
            title = CludesUI.L("Split Stack"),
            editWidth = 56,
            maxLetters = 5,
            skin = SKIN,
            onEnter = function()
                DoSplit(IsAltKeyDown())
            end,
            buttons = {
                {
                    key = "split",
                    label = CludesUI.L("Split"),
                    width = 88,
                    height = 24,
                    point = "BOTTOMLEFT",
                    onClick = function()
                        DoSplit(false)
                    end,
                    primary = true,
                },
                {
                    key = "auto",
                    label = CludesUI.L("Auto Split"),
                    width = 88,
                    height = 24,
                    point = "BOTTOMRIGHT",
                    onClick = function()
                        DoSplit(true)
                    end,
                    tooltip = CludesUI.L(
                        "Split this stack into empty slots repeatedly until only the chosen amount or less remains. Alt+Enter does the same."
                    ),
                },
            },
        })

        hooksecurefunc(CUI_Bags, "RefreshInventory", Validate)
        CUI_Bags:HookScript("OnHide", function()
            WindowHidden(CUI_Bags)
        end)
        hooksecurefunc(CUI_BagsReagent, "RefreshInventory", Validate)
        CUI_BagsReagent:HookScript("OnHide", function()
            WindowHidden(CUI_BagsReagent)
        end)
        local bankFrame = _G.CUI_BankFrame
        if bankFrame then
            hooksecurefunc(bankFrame, "RefreshBank", Validate)
            bankFrame:HookScript("OnHide", function()
                WindowHidden(bankFrame)
            end)
        end
        return skinData
    end

    -- Runs from the slot PostClick hooks, after Blizzard's OnModifiedClick has
    -- opened StackSplitFrame on this button (its lock/count/cursor checks passed).
    -- targets: bagIDs Auto Split may fill, in order; window: closing it aborts a job.
    function CUI_Bags.ShowStackSplitter(ownerFrame, targets, window, opList)
        -- Always on in the bags window's All Items (0) and category (> 0) views:
        -- they draw no empty slots, so Blizzard's cursor split has nowhere to
        -- land and a plain Split places its stack instead. Everywhere else the
        -- Stack Splitter setting decides whether the dialog replaces the popup.
        local placeOnce = (window == CUI_Bags and selectedCategoryIndex >= 0)
        if not placeOnce and BP().bagStackSplitter ~= true then
            return
        end
        local maxStack = CUI.StackSplitFor(ownerFrame)
        if not maxStack then
            return
        end
        -- Its OnHide leaves .owner on the owner button and writes a flag onto
        -- it, which nothing reads on a click path.
        CUI.TakeStackSplit()
        opList = opList or containerOps
        local bag, slot = opList.ownerBag(ownerFrame), ownerFrame:GetID()
        local details = opList.info(bag, slot)
        if not details or not details.itemID then
            return
        end
        dialogFrame = dialogFrame or CreateDialog()
        StopJob()
        dialogFrame._owner, dialogFrame._bag, dialogFrame._slot, dialogFrame._itemID = ownerFrame, bag, slot, details.itemID
        dialogFrame._targets, dialogFrame._window, dialogFrame._ops = targets, window, opList
        dialogFrame._placeOnce = placeOnce
        dialogFrame:SetRange(1, maxStack)
        dialogFrame:SetValue(1)
        dialogFrame:Open(ownerFrame)
        dialogFrame:FocusInput()
    end

    -- Blizzard's guild bank buttons open StackSplitFrame the same way ours do,
    -- so the same PostClick takeover applies. Auto Split stays on the viewed tab.
    local function HookGuildBank()
        local gb = GuildBankFrame
        if not gb or not gb.Columns then
            return
        end
        for _, colour in ipairs(gb.Columns) do
            for _, btn in ipairs(colour.Buttons) do
                btn:HookScript("PostClick", function(self)
                    CUI_Bags.ShowStackSplitter(self, { GetCurrentGuildBankTab() }, gb, guildOps)
                end)
            end
        end
        hooksecurefunc(gb, "Update", Validate)
        gb:HookScript("OnHide", function()
            WindowHidden(gb)
        end)
    end
    if EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_GuildBankUI", HookGuildBank)
    end
end

Inner.CreateInsetBorder, Inner.QUEST_BORDER_COLOR = CreateInsetBorder, QUEST_BORDER_COLOR
Inner.GetInsetBorderStyle = GetInsetBorderStyle
Inner.SCROLLBAR_HIT_W, Inner.SetInsetBorderColor = SCROLLBAR_HIT_W, SetInsetBorderColor
Inner.SetInsetBorderThickness = SetInsetBorderThickness
Inner.broken = false
