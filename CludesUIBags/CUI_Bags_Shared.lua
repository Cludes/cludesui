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

local function CreateInsetBorder(btn, isSlot, icon)
    if isSlot and mod.BagsForever() then
        local widget = btn:CreateTexture(nil, "OVERLAY")
        widget:SetAllPoints(btn)
        widget:SetTexture(FV_SLOT_FRAME)
        -- The visible 37x37 area of the stock 64x64 rim, centered one unit down.
        widget:SetTexCoord(13.5 / 64, 50.5 / 64, 12.5 / 64, 49.5 / 64)
        local mask = btn.Mask
        if not mask then
            mask = btn:CreateMaskTexture()
            mask:SetAllPoints(btn)
            mask:SetTexture(
                "Interface\\Common\\common-iconmask",
                "CLAMPTOBLACKADDITIVE",
                "CLAMPTOBLACKADDITIVE"
            )
        end
        widget:AddMaskTexture(mask)
        if icon then
            icon:AddMaskTexture(mask)
            btn._fvIconMask = mask
        elseif btn.icon then
            btn.icon:AddMaskTexture(mask)
        end
        btn._fvSlotBorder = widget
        return
    end
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    local WHITE = "Interface\\Buttons\\WHITE8X8"
    local t = btn:CreateTexture(nil, "OVERLAY", nil, 2)
    t:SetTexture(WHITE)
    t:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    t:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    t:SetHeight(px)
    local b = btn:CreateTexture(nil, "OVERLAY", nil, 2)
    b:SetTexture(WHITE)
    b:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    b:SetHeight(px)
    local l = btn:CreateTexture(nil, "OVERLAY", nil, 2)
    l:SetTexture(WHITE)
    l:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    l:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    l:SetWidth(px)
    local r = btn:CreateTexture(nil, "OVERLAY", nil, 2)
    r:SetTexture(WHITE)
    r:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    r:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    r:SetWidth(px)
    btn._brdT, btn._brdB, btn._brdL, btn._brdR = t, b, l, r
end

local function SetInsetBorderColor(btn, cr, cg, cb, ca)
    local widget = btn._fvSlotBorder
    if widget then
        widget.r, widget.g, widget.b, widget.a = cr, cg, cb, ca
        local color = ca > 0 and (cr ~= cg or cg ~= cb or cr > 0.25)
        local shade = not color and cr < 0.25 and cr or 1
        widget:SetVertexColor(shade, shade, shade, ca)
        local glow = btn._fvQualityBorder
        if color and not glow then
            glow = btn:CreateTexture(nil, "OVERLAY", nil, 1)
            glow:SetAllPoints(btn)
            glow:SetTexture(FV_QUALITY_FRAME)
            btn._fvQualityBorder = glow
        end
        if glow then
            glow:SetShown(color)
            if color then
                glow:SetVertexColor(cr, cg, cb, ca)
            end
        end
    elseif btn._brdT then
        btn._brdT:SetColorTexture(cr, cg, cb, ca)
        btn._brdB:SetColorTexture(cr, cg, cb, ca)
        btn._brdL:SetColorTexture(cr, cg, cb, ca)
        btn._brdR:SetColorTexture(cr, cg, cb, ca)
    end
end

local function GetInsetBorderStyle(btn)
    local widget = btn._fvSlotBorder
    if widget then
        return widget.r, widget.g, widget.b, widget.a
    end
    local topY = btn._brdT
    if not topY then
        return
    end
    local r, g, b, a = topY:GetVertexColor()
    return r, g, b, a, topY:GetHeight()
end

-- Border thickness in px (1 normally, 2 for quest items); must be re-applied per render because item buttons are pooled.
local function SetInsetBorderThickness(btn, px)
    if btn._brdT then
        btn._brdT:SetHeight(px)
        btn._brdB:SetHeight(px)
        btn._brdL:SetWidth(px)
        btn._brdR:SetWidth(px)
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

function mod.SetForeverSlotQuestBorder(btn, isQuest, isStarter)
    local border = btn._fvQuestBorder
    if isQuest then
        if not border then
            border = btn:CreateTexture(nil, "OVERLAY", nil, 2)
            border:SetPoint("TOPLEFT", btn, "TOPLEFT")
            border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, -1)
            btn._fvQuestBorder = border
        end
        local asset = isStarter and TEXTURE_ITEM_QUEST_BANG or TEXTURE_ITEM_QUEST_BORDER
        if border._asset ~= asset then
            border._asset = asset
            border:SetTexture(asset)
        end
        border:Show()
    elseif border then
        border:Hide()
    end
end

-- Item buttons (ContainerFrameItemButtonTemplate) carry frameLevel="10" in
-- Blizzard's XML, a fixed level that never follows their window: under a window
-- raised past it (High starts at 100) the window takes the clicks. So each one
-- sits at its window's level + 9: the template's own 10 over a window at level 1,
-- under Compact's drop zones (window + 22). The text overlay (+3, above the
-- cooldown swipe) and the warbank dim (+6) are fixed levels too and move with it.
local function PinItemButtonLevel(btn, level)
    btn:SetFrameLevel(level)
    if btn._textOverlay then
        btn._textOverlay:SetFrameLevel(level + 3)
    end
    if btn._warbankDim then
        btn._warbankDim:SetFrameLevel(level + 6)
    end
end

-- background color/opacity for bags and bank: the texture fades with the
-- opacity, the tint on top takes the color
function mod.ApplyWindowBackground(backdrop, overlayFrame)
    if not (backdrop and overlayFrame) then
        return
    end
    local p = BP()
    local o = (p.bagBgOpacity or 100) / 100
    local c = p.bagBgColor
    backdrop:SetAlpha(o)
    overlayFrame:SetColorTexture(c and c.r or 0, c and c.g or 0, c and c.b or 0, c and c.a or 0.25)
    overlayFrame:SetAlpha(o)
end

local slotBackgroundAtlases
function mod.SetSlotBackgroundTexture(tex, interactive)
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
            tex:SetAtlas(atlas)
            return
        end
    end
    tex:SetTexture("Interface\\AddOns\\CludesUIBags\\Media\\icon-bg.png")
end

-- Tint over an empty slot's backdrop. Keep painted regions weakly so a
-- color change can retint them without a relayout.
local slotBgs = setmetatable({}, { __mode = "k" })
function mod.PaintSlotBackground(tex, alpha)
    tex._slotBgAlpha = alpha
    slotBgs[tex] = true
    local c = BP().bagSlotBgColor
    if c then
        tex:SetVertexColor(c.r, c.g, c.b)
        tex:SetAlpha(alpha * (c.a or 1))
    else
        tex:SetVertexColor(1, 1, 1)
        tex:SetAlpha(alpha)
    end
end

-- the slot background picker: just the shown ones (hidden ones get painted when they show)
function mod.RetintSlotBackgrounds()
    for tex in pairs(slotBgs) do
        if tex:IsVisible() then
            mod.PaintSlotBackground(tex, tex._slotBgAlpha)
        end
    end
end

function mod.PinItemButton(btn, window)
    PinItemButtonLevel(btn, window:GetFrameLevel() + 9)
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
    for _, btn in pairs(pool) do
        PinItemButtonLevel(btn, level)
    end
end

-- WoW Forever's item buttons round the icon and the pushed art with the
-- button's own Mask (retail's templates carry IconMask, stripped where the
-- slots are skinned). The bags draw both square.
local function DropMask(tex, m)
    if not tex then
        return
    end
    for idx = tex:GetNumMaskTextures(), 1, -1 do
        if tex:GetMaskTexture(idx) == m then
            tex:RemoveMaskTexture(m)
        end
    end
end
function mod.UnmaskItemButton(btn)
    local m = btn.Mask
    if not m then
        return
    end
    DropMask(btn.icon, m)
    DropMask(btn:GetPushedTexture(), m)
end

-- An item's icon on a slot. WoW Forever's SetItemButtonTexture resets the
-- icon's crop on every call (retail's keeps it), so the zoom goes back on.
function mod.SetSlotIcon(btn, texture)
    btn:SetItemButtonTexture(texture)
    local z = BP().bagItemIconZoom or 0.08
    btn.icon:SetTexCoord(z, 1 - z, z, 1 - z)
end

-- Flat look for a ContainerFrameItemButtonTemplate slot, plus the text overlay
-- (above the cooldown swipe) with Count, ItemLevelText and BindTypeText.
-- Methods only: writing properties onto Blizzard template sub-objects taints.
-- opts: anchorIcon (re-anchor icon to the button), cooldownFont (restyle the
-- cooldown text), flatHighlight (bank: 8% white highlight, with highlight and
-- pushed textures looked up by template field first). Returns the overlay.
function mod.SkinItemButton(btn, options)
    if btn.NewItemTexture then
        btn.NewItemTexture:Hide()
        btn.NewItemTexture:SetAlpha(0)
    end
    if btn.BattlepayItemTexture then
        btn.BattlepayItemTexture:Hide()
        btn.BattlepayItemTexture:SetAlpha(0)
    end
    if btn.flash then
        btn.flash:Hide()
        btn.flash:SetAlpha(0)
    end
    if btn.newitemglowAnim then
        btn.newitemglowAnim:Stop()
    end

    mod.SizeSlot(btn)
    if btn.icon then
        local z = BP().bagItemIconZoom or 0.08
        btn.icon:SetTexCoord(z, 1 - z, z, 1 - z)
        if options.anchorIcon then
            btn.icon:ClearAllPoints()
            btn.icon:SetAllPoints(btn)
        end
    end

    local ht, pt
    if options.flatHighlight then
        ht = btn.HighlightTexture or btn:GetHighlightTexture()
        if ht then
            ht:SetTexture(nil)
            ht:SetColorTexture(1, 1, 1, 0.08)
        end
        pt = btn.PushedTexture or btn:GetPushedTexture()
    else
        ht = btn:GetHighlightTexture()
        pt = btn:GetPushedTexture()
    end
    if ht then
        ht:ClearAllPoints()
        ht:SetAllPoints(btn)
    end
    if pt then
        pt:SetAtlas(nil)
        pt:SetTexture("Interface\\AddOns\\CludesUIBags\\Media\\highlight-3.png")
        pt:SetTexCoord(0, 1, 0, 1)
        pt:ClearAllPoints()
        pt:SetAllPoints(btn)
        pt:SetVertexColor(0.973, 0.839, 0.604, 1)
    end

    if btn.NormalTexture then
        btn.NormalTexture:SetAlpha(0)
    end
    if btn.IconBorder then
        btn.IconBorder:SetAlpha(0)
    end

    if btn.icon and btn.IconMask then
        btn.icon:RemoveMaskTexture(btn.IconMask)
        btn.IconMask:Hide()
        btn.IconMask:SetTexture(nil)
        btn.IconMask:ClearAllPoints()
        btn.IconMask:SetSize(0.001, 0.001)
    end
    mod.UnmaskItemButton(btn)

    if options.cooldownFont and btn.Cooldown then
        local cdText = btn.Cooldown:GetRegions()
        if cdText and cdText.SetFont then
            CludesUI.ApplyIconTextFont(cdText, GetFont(), 11, "bags")
        end
    end

    CreateInsetBorder(btn, true)
    SetInsetBorderColor(btn, 0.25, 0.25, 0.25, 1)

    local textOverlay = CreateFrame("Frame", nil, btn)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel(btn:GetFrameLevel() + 3)
    btn._textOverlay = textOverlay

    local fontFile = GetFont()
    local outline = (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    local countFS = btn.Count
    if countFS then
        countFS:SetParent(textOverlay)
        CludesUI.ApplyIconTextFont(countFS, fontFile, BP().bagCountFontSize or 11, "bags")
        countFS:ClearAllPoints()
        countFS:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    end

    -- Item level text (top-left, gear only)
    if not btn.ItemLevelText then
        btn.ItemLevelText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.ItemLevelText:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        btn.ItemLevelText:SetTextColor(1, 1, 1, 1)
    end
    btn.ItemLevelText:SetFont(fontFile, BP().itemlevelFontSize or 12, outline)
    btn.ItemLevelText:SetText("")

    -- Bind Type text (bottom-left)
    if not btn.BindTypeText then
        btn.BindTypeText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        btn.BindTypeText:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 2)
        btn.BindTypeText:SetTextColor(1, 1, 1, 1)
    end
    btn.BindTypeText:SetFont(fontFile, BP().bagBindTypeFontSize or 11, outline)
    btn.BindTypeText:SetText("")
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
        local btn = CreateFrame("Button", nil, hostFrame)
        btn:SetSize(12, 12)
        btn._icon = btn:CreateTexture(nil, "OVERLAY")
        btn._icon:SetAllPoints()
        btn._icon:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-left.png")
        btn._icon:SetAlpha(0.4)
        btn._tip = tipText
        btn:SetScript("OnEnter", ArrowOnEnter)
        btn:SetScript("OnLeave", ArrowOnLeave)
        return btn
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
function mod.AttachGridScrollbar(host, scrollFrame, clamp, rawWheel)
    local SCROLLBAR_W = 4 -- thumb width
    local SCROLL_STEP = 40 -- pixels per mouse wheel tick
    local THUMB_MIN_H = 20 -- minimum thumb height

    local track = CreateFrame("Button", nil, host)
    track:SetWidth(SCROLLBAR_HIT_W)
    track:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetWidth(SCROLLBAR_W)
    trackBg:SetPoint("TOP", track, "TOP", 0, 0)
    trackBg:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    trackBg:SetPoint("RIGHT", track, "RIGHT", 0, 0)
    trackBg:SetColorTexture(1, 1, 1, 0.06)

    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(SCROLLBAR_W)
    thumb:SetColorTexture(1, 1, 1, 0.25)
    thumb:Hide()

    local _isDragging = false
    local _dragStartY = 0
    local _dragStartPct = 0

    local function GetScrollMetrics()
        local scrollRange = scrollFrame:GetVerticalScrollRange()
        if not scrollRange or scrollRange <= 0 then
            return nil
        end
        local trackH = track:GetHeight()
        local ext = scrollFrame:GetHeight() / (scrollFrame:GetHeight() + scrollRange)
        local thumbH = math.max(THUMB_MIN_H, trackH * ext)
        local maxTravel = trackH - thumbH
        if maxTravel <= 0 then
            return nil
        end
        local pct = scrollFrame:GetVerticalScroll() / scrollRange
        return pct, thumbH, maxTravel, scrollRange
    end

    local function UpdateThumb()
        if clamp then
            local range = scrollFrame:GetVerticalScrollRange() or 0
            local current = scrollFrame:GetVerticalScroll()
            if current > range then
                scrollFrame:SetVerticalScroll(range)
            end
        end
        local pct, thumbH, maxTravel = GetScrollMetrics()
        if not pct then
            thumb:Hide()
            trackBg:Hide()
            return
        end
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -(pct * maxTravel))
        thumb:Show()
        trackBg:Show()
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
    host:EnableMouseWheel(true)
    host:SetScript("OnMouseWheel", OnWheel)

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
            thumb:SetColorTexture(1, 1, 1, 0.25)
            return
        end
        local pct, thumbH, maxTravel, scrollRange = GetScrollMetrics()
        if not pct then
            _isDragging = false
            self:Hide()
            return
        end
        local scale = track:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        local deltaY = (_dragStartY - cy / scale)
        local deltaPct = deltaY / maxTravel
        local newPct = math.max(0, math.min(1, _dragStartPct + deltaPct))
        scrollFrame:SetVerticalScroll(newPct * scrollRange)
        UpdateThumb()
    end)

    track:RegisterForDrag("LeftButton")
    track:SetScript("OnMouseDown", function(_, btnFrame)
        if btnFrame ~= "LeftButton" then
            return
        end
        local pct, thumbH, maxTravel, scrollRange = GetScrollMetrics()
        if not pct then
            return
        end

        local scale = track:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        local trackTop = track:GetTop() * scale
        local cursorLocalY = (trackTop - cy) / scale

        -- Check if cursor is on the thumb
        local thumbTop = pct * maxTravel
        local thumbBot = thumbTop + thumbH
        if cursorLocalY >= thumbTop and cursorLocalY <= thumbBot then
            _isDragging = true
            _dragStartY = cy / scale
            _dragStartPct = pct
            dragUpdate:Show()
        else
            -- Click on track: jump to position
            local clickPct = math.max(0, math.min(1, (cursorLocalY - thumbH / 2) / maxTravel))
            scrollFrame:SetVerticalScroll(clickPct * scrollRange)
            UpdateThumb()
            _isDragging = true
            _dragStartY = cy / scale
            _dragStartPct = clickPct
            dragUpdate:Show()
        end
    end)

    track:SetScript("OnMouseUp", function()
        _isDragging = false
    end)

    track:SetScript("OnEnter", function()
        thumb:SetColorTexture(1, 1, 1, 0.4)
    end)
    track:SetScript("OnLeave", function()
        if not _isDragging then
            thumb:SetColorTexture(1, 1, 1, 0.25)
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
        local show = padOn and trackBg:IsShown() or false
        padUp:SetShown(show)
        padDown:SetShown(show)
    end
    function track.PadSync(enabled)
        enabled = enabled and true or false
        if not padUp then
            if not enabled then
                return
            end
            padUp, padDown = mod.PadStepButtons(host, SCROLLBAR_HIT_W, function(delta)
                OnWheel(nil, delta)
            end)
            padUp:SetFrameLevel(track:GetFrameLevel() + 1)
            padDown:SetFrameLevel(track:GetFrameLevel() + 1)
            padUp:SetPoint("TOP", track, "TOP", 0, 0)
            padDown:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
            hooksecurefunc(trackBg, "Show", PadSteps)
            hooksecurefunc(trackBg, "Hide", PadSteps)
            scrollFrame:HookScript("OnVerticalScroll", function()
                UpdateThumb()
            end)
            CUI.PadHint(track, "nodeignore")
        end
        if enabled == padOn then
            return
        end
        padOn = enabled
        trackBg:SetColorTexture(1, 1, 1, enabled and 0.15 or 0.06)
        PadSteps()
    end
    return track, thumb, UpdateThumb
end

-------------------------------------------------------------------------------
--  Controller support (the bags and the bank). Everything here runs only on
--  an edge that already exists (a show, a click, a menu open) behind the
--  shared controller signal; mouse/keyboard players never build any of it.
-------------------------------------------------------------------------------
do
    local ARROW_UP = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-up3.png"
    local ARROW_DOWN = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-down3.png"

    local function MakeStep(hostFrame, size, icon, onClick)
        local b = CreateFrame("Button", nil, hostFrame)
        b:SetSize(size, size)
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetSize(size - 4, size - 4)
        t:SetPoint("CENTER", b, "CENTER", 0, 0)
        t:SetTexture(icon)
        b:SetAlpha(0.5)
        b:SetScript("OnEnter", function(self)
            self:SetAlpha(0.9)
        end)
        b:SetScript("OnLeave", function(self)
            self:SetAlpha(0.5)
        end)
        b:SetScript("OnClick", onClick)
        b:Hide()
        return b
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
    local function SidebarStepsUpdate(st)
        local show = st.on and not BP()[st.key] and (st.child:GetHeight() - st.sf:GetHeight()) > 0.5
        st.up:SetShown(show)
        st.down:SetShown(show)
    end

    function mod.PadSidebarSync(heading, scrollFrame, childFrame, dbKey, enabled)
        if not (heading and scrollFrame and childFrame) then
            return
        end
        local st = heading._padSteps
        if not st then
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
            st = { up = up, down = down, sf = scrollFrame, child = childFrame, key = dbKey }
            heading._padSteps = st
            -- The rebuild sets the list height; the window can resize it too.
            local function Update()
                SidebarStepsUpdate(st)
            end
            hooksecurefunc(childFrame, "SetHeight", Update)
            scrollFrame:HookScript("OnSizeChanged", Update)
        end
        st.on = enabled and true or false
        SidebarStepsUpdate(st)
    end

    -- Blizzard's bag frames live under a hidden parent. One that its own
    -- toggle opened keeps reporting shown after we close the bags ourselves,
    -- so the next Back press counts as "closed a bag" and does nothing else.
    -- Only frames that are shown but not visible (still under that parent)
    -- are touched, and no Blizzard OnHide runs for them.
    function mod.PadReleaseBlizzBags()
        local f = ContainerFrameCombinedBags
        if f and f:IsShown() and not f:IsVisible() then
            f:Hide()
        end
        for idx = 1, 13 do
            f = _G["ContainerFrame" .. idx]
            if f and f:IsShown() and not f:IsVisible() then
                f:Hide()
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
    local dialog
    local job -- { bag, slot, itemID, size, targets, window, ops, pending, issuedAt }
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
        job = nil
    end

    -- Polled on a short timer. The new stack's slot can still read empty for a
    -- moment after the source count has updated, so slots already used as a
    -- destination are skipped for the rest of the job.
    local function Later()
        local this = job
        C_Timer.After(0.05, function()
            if job == this then
                StepJob()
            end
        end)
    end

    -- One split per server round trip: issue, wait for the source stack to
    -- settle at the expected count, repeat.
    StepJob = function()
        if not job then
            return
        end
        if not job.window:IsVisible() then
            StopJob()
            return
        end
        local ops = job.ops
        local details = ops.info(job.bag, job.slot)
        if not details or details.itemID ~= job.itemID then
            StopJob()
            return
        end
        if details.isLocked or (job.pending and details.stackCount ~= job.pending) then
            if GetTime() - job.issuedAt > 2 then
                ClearCursor()
                StopJob()
            else
                Later()
            end
            return
        end
        job.pending = nil
        if details.stackCount <= job.size then
            StopJob()
            return
        end
        for _, bagID in ipairs(job.targets) do
            for s = 1, ops.numSlots(bagID) do
                local key = bagID * 1000 + s
                if not job.used[key] and not ops.info(bagID, s) then
                    job.used[key] = true
                    ClearCursor()
                    ops.split(job.bag, job.slot, job.size)
                    ops.pickup(bagID, s)
                    -- Single placed split: one issue, no settle polling.
                    if job.once then
                        StopJob()
                        return
                    end
                    job.pending = details.stackCount - job.size
                    job.issuedAt = GetTime()
                    Later()
                    return
                end
            end
        end
        StopJob()
    end

    -- once = a single split placed into the first empty target slot (the views
    -- that draw no empty slots have nowhere to drop a cursor stack).
    local function StartJob(bag, slot, itemId, size, targets, window, ops, once)
        job = {
            bag = bag,
            slot = slot,
            itemID = itemId,
            size = size,
            targets = targets,
            window = window,
            ops = ops,
            used = {},
            issuedAt = GetTime(),
            once = once,
        }
        StepJob()
    end

    -- Closing the window a dialog or job belongs to ends it; other windows are unaffected.
    local function WindowHidden(win)
        if dialog and dialog._window == win then
            dialog:Hide()
        end
        if job and job.window == win then
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
        if not dialog or not dialog:IsShown() then
            return
        end
        local ownerFrame = dialog._owner
        if
            not ownerFrame:IsVisible()
            or dialog._ops.ownerBag(ownerFrame) ~= dialog._bag
            or ownerFrame:GetID() ~= dialog._slot
        then
            dialog:Hide()
            return
        end
        local details = dialog._ops.info(dialog._bag, dialog._slot)
        if
            not details
            or details.itemID ~= dialog._itemID
            or not details.stackCount
            or details.stackCount < 2
        then
            dialog:Hide()
            return
        end
        if details.stackCount ~= dialog._max then
            dialog:SetRange(1, details.stackCount)
            dialog:SetValue(dialog:Current())
        end
    end

    local function MakeButton(hostFrame, wid, hgt, labelText, Pix)
        local b = CreateFrame("Button", nil, hostFrame)
        b:SetSize(wid, hgt)
        local backdrop = b:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.15, 0.15, 0.15, 1)
        if Pix and Pix.CreateBorder then
            Pix.CreateBorder(b, 0.25, 0.25, 0.25, 1)
        end
        local fontStr = b:CreateFontString(nil, "OVERLAY")
        SetBagFont(fontStr, 12)
        fontStr:SetPoint("CENTER", 0, 0)
        fontStr:SetTextColor(1, 1, 1, 0.9)
        fontStr:SetText(labelText)
        b:SetScript("OnEnter", function()
            backdrop:SetColorTexture(0.2, 0.2, 0.2, 1)
        end)
        b:SetScript("OnLeave", function()
            backdrop:SetColorTexture(0.15, 0.15, 0.15, 1)
        end)
        return b
    end

    local function DoSplit(auto)
        local d = dialog
        local bag, slot, num, ops = d._bag, d._slot, d:Current(), d._ops
        d:Hide()
        local details = ops.info(bag, slot)
        if
            not details
            or details.isLocked
            or details.itemID ~= d._itemID
            or not details.stackCount
            or num >= details.stackCount
        then
            return
        end
        -- Session unmerge mark, written BEFORE the split so the refresh it
        -- triggers already renders the pieces apart. Same link form the slot
        -- tables key on; bags and reagent window only (bank items never merge here).
        if d._window == CUI_Bags or d._window == CUI_BagsReagent then
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
        if auto or d._placeOnce then
            StartJob(bag, slot, details.itemID, num, d._targets, d._window, ops, not auto)
        else
            ClearCursor()
            ops.split(bag, slot, num)
        end
    end

    -- The splitter's own dark look on the shared quantity window
    -- (CludesUI.CreateQuantityDialog).
    local SKIN = {
        frame = function(d)
            local Pix = CUI.PP
            local backdrop = d:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(0.067, 0.067, 0.067, 0.95)
            if Pix and Pix.CreateBorder then
                Pix.CreateBorder(d, 0.2, 0.2, 0.2, 1)
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
        close = function(close)
            close:SetSize(12, 12)
            close:SetPoint("TOPRIGHT", close:GetParent(), "TOPRIGHT", -9, -9)
            close.icon = close:CreateTexture(nil, "OVERLAY")
            close.icon:SetAllPoints()
            close.icon:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png")
            close.icon:SetAlpha(0.7)
            close:SetScript("OnEnter", function()
                close.icon:SetAlpha(0.9)
            end)
            close:SetScript("OnLeave", function()
                close.icon:SetAlpha(0.7)
            end)
        end,
    }

    local function CreateDialog()
        local d = CUI.CreateQuantityDialog({
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
        return d
    end

    -- Runs from the slot PostClick hooks, after Blizzard's OnModifiedClick has
    -- opened StackSplitFrame on this button (its lock/count/cursor checks passed).
    -- targets: bagIDs Auto Split may fill, in order; window: closing it aborts a job.
    function CUI_Bags.ShowStackSplitter(ownerFrame, targets, window, ops)
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
        ops = ops or containerOps
        local bag, slot = ops.ownerBag(ownerFrame), ownerFrame:GetID()
        local details = ops.info(bag, slot)
        if not details or not details.itemID then
            return
        end
        dialog = dialog or CreateDialog()
        StopJob()
        dialog._owner, dialog._bag, dialog._slot, dialog._itemID = ownerFrame, bag, slot, details.itemID
        dialog._targets, dialog._window, dialog._ops = targets, window, ops
        dialog._placeOnce = placeOnce
        dialog:SetRange(1, maxStack)
        dialog:SetValue(1)
        dialog:Open(ownerFrame)
        dialog:FocusInput()
    end

    -- Blizzard's guild bank buttons open StackSplitFrame the same way ours do,
    -- so the same PostClick takeover applies. Auto Split stays on the viewed tab.
    local function HookGuildBank()
        local gb = GuildBankFrame
        if not gb or not gb.Columns then
            return
        end
        for _, col in ipairs(gb.Columns) do
            for _, b in ipairs(col.Buttons) do
                b:HookScript("PostClick", function(self)
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
