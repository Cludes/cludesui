if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIBags_Grid.lua
--  Grid and Compact bag displays (bagDisplayMode = "grid" / "compact"): the
--  secure item-slot factory, RenderButton, and the layout pass of
--  CUI_Bags:RefreshInventory. Compact hands the pass's groups to
--  CludesUIBags_Compact.lua instead of drawing them in grid rows.
--  Mode is latched per session (CUI_Bags.IsListMode / IsCompactMode): in
--  list mode nothing here is ever built.
-------------------------------------------------------------------------------
local mod = select(2, ...)
if not (mod and mod.GetSelection) then
    return
end

local CUI = CludesUI
local _emptyP = {}
local function BP()
    return (CUI._bagsDB and CUI._bagsDB.profile) or _emptyP
end
local GetItemInfo = C_Item.GetItemInfo
local GetItemQualityColor = C_Item.GetItemQualityColor

local SLOT_SIZE, SPACING = mod.SLOT_SIZE, mod.SPACING
mod.OnSlotMetrics(function(m)
    SLOT_SIZE, SPACING = m[1], m[2]
end)
local itemSlots = mod.itemSlots
local _itemDragFrame = mod.itemDragFrame
local _catHeaders = mod.catHeaders
local _expSubHeaders = mod.expSubHeaders
local QUEST_BORDER_COLOR = mod.QUEST_BORDER_COLOR
local QualityBorderColor = mod.QualityBorderColor
local BagsItemUnusable = mod.BagsItemUnusable
local GetFont = mod.GetFont
local GetCatTitleSize = mod.GetCatTitleSize
local SetBagFont = mod.SetBagFont
local CreateInsetBorder = mod.CreateInsetBorder
local SetInsetBorderColor = mod.SetInsetBorderColor
local SetInsetBorderThickness = mod.SetInsetBorderThickness
local SlotMiddleClick = mod.SlotMiddleClick
local UpdatePawnArrow = mod.UpdatePawnArrow
local IsItemPinned = mod.IsItemPinned
local PreCacheSortFields = mod.PreCacheSortFields
local VisualSortCompare = mod.VisualSortCompare
local RecentCompare = mod.RecentCompare
local MergeDuplicates = mod.MergeDuplicates
local ApplySavedOrder = mod.ApplySavedOrder
-- Junk Marker state, read once per RenderGridView pass for every RenderButton
local junkOn = false
-- Compact display state, read once per RenderGridView pass
local compact = false
local BuildExpansionBuckets = mod.BuildExpansionBuckets
local BuildSlotBuckets = mod.BuildSlotBuckets
-- Section label for a bag ID (MultiBag grid and list)
function mod.BagDisplayName(bag)
    if bag == 0 then
        return CludesUI.L("Backpack")
    end
    if bag == 5 then
        return CludesUI.L("Reagent Bag")
    end
    local invID = C_Container.ContainerIDToInventoryID(bag)
    local link = invID and GetInventoryItemLink("player", invID)
    return (link and GetItemInfo(link)) or CludesUI.Lf("Bag %d", bag)
end

local ArmorySlotGroupingEnabled = mod.ArmorySlotGroupingEnabled
local IsArmoryGearCategory = mod.IsArmoryGearCategory
local IsGearOnlyGroup = mod.IsGearOnlyGroup
local GetOrCreateCatHeader = mod.GetOrCreateCatHeader
local GetOrCreateExpSubHeader = mod.GetOrCreateExpSubHeader
local ShowRecentClearButton = mod.ShowRecentClearButton
local GetOrCreatePinOverlay = mod.GetOrCreatePinOverlay
local GetOrCreateAssignOverlay = mod.GetOrCreateAssignOverlay
local ResetAssignOverlays = mod.ResetAssignOverlays

-------------------------------------------------------------------------------
--  Slot Factory
-------------------------------------------------------------------------------
local function GetOrCreateSlot(position)
    if itemSlots[position] then
        return itemSlots[position]
    end
    -- NEVER CreateFrame a secure ContainerFrameItemButtonTemplate in combat -- a button
    -- born in combat is tainted (UseContainerItem() -> ADDON_ACTION_FORBIDDEN in M+/Delves).
    -- Pre-warmed pool covers normal counts; past it, callers skip the slot until PLAYER_REGEN_ENABLED
    -- builds it (_poolShort).
    if InCombatLockdown() then
        CUI_Bags._poolShort = true
        return nil
    end

    local slotParent = CreateFrame("Frame", nil, CUI_Bags)
    mod.SizeSlot(slotParent)
    local button = CreateFrame("ItemButton", nil, slotParent, "ContainerFrameItemButtonTemplate")
    mod.PinItemButton(button, CUI_Bags)
    button:SetAllPoints(slotParent)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:HookScript("OnDragStart", function()
        _itemDragFrame:Show()
    end)

    -- Right-click deposit routing to the selected bank tab (see BankRoutePreClick)
    button:HookScript("PreClick", mod.BankRoutePreClick)
    button:HookScript("OnClick", mod.BankRouteOnClick)

    button:HookScript("OnMouseUp", SlotMiddleClick)

    -- Shift-click on a stack: the split dialog. Always on in the All Items and
    -- category views (they draw no empty slots, so Blizzard's cursor split has
    -- nowhere to land there); the Stack Splitter setting extends it to the rest.
    button:HookScript("PostClick", function(self)
        CUI_Bags.ShowStackSplitter(self, mod.SplitTargetBags(self:GetParent():GetID()), CUI_Bags)
    end)

    local textOverlay = mod.SkinItemButton(button, { anchorIcon = true, cooldownFont = true })
    local countSize = BP().bagCountFontSize or 11
    local fontFile = GetFont()

    -- Keystone level text (top-left, same as item level)
    if not button.KeystoneText then
        button.KeystoneText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        button.KeystoneText:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        button.KeystoneText:SetTextColor(1, 1, 1, 1)
    end
    button.KeystoneText:SetFont(fontFile, countSize, (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    button.KeystoneText:SetText("")
    -- Keystone dungeon abbreviation (bottom-right, same position as stack count)
    if not button.KeystoneDungeonText then
        button.KeystoneDungeonText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        button.KeystoneDungeonText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 2)
        button.KeystoneDungeonText:SetTextColor(1, 1, 1, 1)
        button.KeystoneDungeonText:SetJustifyH("RIGHT")
    end
    button.KeystoneDungeonText:SetFont(
        fontFile,
        math.max(countSize - 2, 7),
        (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    )
    button.KeystoneDungeonText:SetText("")

    -- Equipment set name FontString is lazy-created in RenderButton: never
    -- built while Show Set Name on Gear is off (zero cost disabled).

    itemSlots[position] = button
    return button
end
mod.GetOrCreateSlot = GetOrCreateSlot

-- A slot's desaturation (locked; grey items and Junk Marker junk while Junk
-- Item Visuals' Desaturate is on) and its Junk Marker coin badge (its Show Coin
-- Icon): the game's coin, cropped round, lifted past the bottom-left corner.
local function PaintJunkState(button, details, markerJunk)
    local profile = BP()
    local quality = details.quality or 1
    SetItemButtonDesaturated(
        button,
        details.isLocked or (profile.bagDesaturateJunkItems == true and (quality == 0 or markerJunk)) or false
    )
    if markerJunk and profile.bagShowJunkCoin == true then
        local coin = button._junkCoin
        if not coin then
            coin = button:CreateTexture(nil, "OVERLAY", nil, 6)
            coin:SetTexture(mod.JUNK_COIN)
            coin:SetTexCoord(0.12, 0.88, 0.12, 0.88)
            local mask = button:CreateMaskTexture()
            mask:SetTexture(
                "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
                "CLAMPTOBLACKADDITIVE",
                "CLAMPTOBLACKADDITIVE"
            )
            mask:SetAllPoints(coin)
            coin:AddMaskTexture(mask)
            coin:SetSize(12, 12)
            coin:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -3, -3)
            button._junkCoin = coin
        end
        coin:Show()
    elseif button._junkCoin then
        button._junkCoin:Hide()
    end
end

-- Mark mode repaints the one slot it toggled
function mod.GridPaintJunk(button, details)
    PaintJunkState(button, details, CUI_CategoryManager:IsJunk(details.itemID, details.quality or 1))
end

-------------------------------------------------------------------------------
--  RenderButton
-------------------------------------------------------------------------------
local function RenderButton(button, payload, _, colour, row, startX, currentY, _, interactiveEmpties)
    local hostFrame = button:GetParent()
    hostFrame:ClearAllPoints()
    hostFrame:SetPoint(
        "TOPLEFT",
        startX + (colour * (SLOT_SIZE + SPACING)),
        currentY - (row * (SLOT_SIZE + SPACING))
    )
    hostFrame:Show()
    button:Show()

    button:SetID(payload.slot or 0)
    hostFrame:SetID(payload.bag or 0)

    -- Always clear overlays upfront (pooled buttons carry stale state from prior items)
    if button.ProfessionQualityOverlay then
        button.ProfessionQualityOverlay:SetAlpha(0)
    end
    if button.IconOverlay then
        button.IconOverlay:SetAlpha(0)
        button.IconOverlay:Hide()
    end
    if button.IconOverlay2 then
        button.IconOverlay2:SetAlpha(0)
        button.IconOverlay2:Hide()
    end

    -- Empty slot background (created once, reused)
    if not button._emptyBg then
        button._emptyBg = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        button._emptyBg:SetAllPoints()
        mod.SetSlotBackgroundTexture(button._emptyBg, true)
    end

    if not payload.info then
        button:SetItemButtonTexture(nil)
        button:SetItemButtonCount(0)
        SetItemButtonDesaturated(button, false)
        if button.icon then
            button.icon:Hide()
        end
        button._emptyBg:Show()
        if interactiveEmpties then
            button:EnableMouse(true)
            mod.PaintSlotBackground(button._emptyBg, 0.6)
            SetInsetBorderColor(button, 0.15, 0.15, 0.15, 0.5)
        else
            button:EnableMouse(false)
            mod.PaintSlotBackground(button._emptyBg, 0.35)
            SetInsetBorderColor(button, 0, 0, 0, 0.3)
        end
        -- Reset to 1px and drop the marker, or a pooled slot vacated by a quest item keeps the 2px gold border + atlas.
        SetInsetBorderThickness(button, (CUI and CUI.PP and CUI.PP.mult) or 1)
        if button._fvQuestBorder then
            button._fvQuestBorder:Hide()
        end
        if button._questMarker then
            button._questMarker:Hide()
        end
        if button._junkCoin then
            button._junkCoin:Hide()
        end
        if button.Cooldown then
            button.Cooldown:Clear()
        end
        if button.ItemLevelText then
            button.ItemLevelText:SetText("")
        end
        if button.KeystoneText then
            button.KeystoneText:SetText("")
        end
        if button.KeystoneDungeonText then
            button.KeystoneDungeonText:SetText("")
        end
        if button.BindTypeText then
            button.BindTypeText:SetText("")
        end
        if button.SetNameText then
            button.SetNameText:SetText("")
        end
        if button.ProfessionQualityOverlay then
            button.ProfessionQualityOverlay:Hide()
        end
        if button.IconBorder then
            button.IconBorder:Hide()
        end
        if button.NormalTexture then
            button.NormalTexture:SetAlpha(0)
        end
        if button._warbankDim then
            button._warbankDim:Hide()
        end
        button:SetAlpha(1)
    else
        button:EnableMouse(true)
        button._emptyBg:Hide()
        if button.icon then
            button.icon:Show()
        end
        mod.SetSlotIcon(button, payload.info.iconFileID)
        button:SetItemButtonCount(payload._mergedCount or payload.info.stackCount)
        button._isMerged = payload._mergedCount and true or nil

        local quality = payload.info.quality or 1
        PaintJunkState(
            button,
            payload.info,
            junkOn and CUI_CategoryManager:IsJunk(payload.info.itemID, quality)
        )

        -- Search misses, and a pinned item in a OneBag / MultiBag bag section
        -- (the interactive slot sections) while Dim Items in OneBag/MultiBag
        -- is on: its bright copy sits in the Pinned Items section.
        local filtered = payload.info.isFiltered or (interactiveEmpties and payload._pinDim) or false
        button:SetAlpha(filtered and 0.2 or 1)
        if button._textOverlay then
            button._textOverlay:SetAlpha(filtered and 0.2 or 1)
        end

        local iType = payload._giType

        -- Item Level + Upgrade Rank (gear only)
        if button.ItemLevelText then
            if payload._isGear then
                local showIlvl = BP().showItemlevelInBags ~= false
                if showIlvl then
                    button.ItemLevelText:SetText(payload._giIlvl or "")
                    -- Track color + rank (pre-cached on data table)
                    local red, green, blue
                    local rankText = payload._giTrackRank or ""
                    local trackColor = payload._giTrackColor
                    if BP().itemlevelUseCustomColor and BP().itemlevelCustomColor then
                        red, green, blue =
                            BP().itemlevelCustomColor.r,
                            BP().itemlevelCustomColor.g,
                            BP().itemlevelCustomColor.b
                    elseif trackColor then
                        red, green, blue = trackColor.r, trackColor.g, trackColor.b
                    else
                        red, green, blue = GetItemQualityColor(payload._giQuality or 1)
                    end
                    button.ItemLevelText:SetTextColor(red, green, blue, 1)
                    local countFS = button.Count
                    if countFS and BP().bagShowTrackRank and rankText ~= "" then
                        countFS:SetText(rankText:match("^(%d+)/") or rankText)
                        countFS:SetTextColor(red, green, blue, 1)
                        countFS:Show()
                    end
                else
                    button.ItemLevelText:SetText("")
                end
            else
                button.ItemLevelText:SetText("")
            end
        end

        -- Keystone: level top-left, abbreviated dungeon name bottom-right
        if button.KeystoneText then
            if payload._ksLevel then
                button.KeystoneText:SetText(payload._ksLevel)
                button.KeystoneText:SetTextColor(payload._ksR or 1, payload._ksG or 1, payload._ksB or 1, 1)
                if button.KeystoneDungeonText then
                    button.KeystoneDungeonText:SetText(payload._ksAbbrev or "")
                    button.KeystoneDungeonText:SetTextColor(1, 1, 1, 1)
                end
            else
                button.KeystoneText:SetText("")
                if button.KeystoneDungeonText then
                    button.KeystoneDungeonText:SetText("")
                end
            end
        end

        -- BoE/WuE bottom-left (gear only); skipped for quest starters, which use that corner for the quest marker.
        if button.BindTypeText then
            if
                payload._isGear
                and not payload.info.isBound
                and not payload._isQuestStarter
                and BP().bagDisplayBindType
            then
                CUI_Bags.SetBindTypeText(button.BindTypeText, payload._isWuE, payload._giBindType, quality)
            else
                button.BindTypeText:SetText("")
            end
        end

        -- Equipment set name bottom-center (stamped by ClassifyAll for set gear;
        -- stamping is gated on the toggle, so _setName is nil while it's off).
        -- FontString is lazy: never built while off; once built it is cleared on
        -- every render because buttons are pooled.
        if payload._setName then
            -- Yields when the upgrade-track rank occupies Count in the same row
            -- (mirrors the rank-display condition in the ItemLevelText block above)
            local rankShown = payload._isGear
                and BP().bagShowTrackRank
                and BP().showItemlevelInBags ~= false
                and (payload._giTrackRank or "") ~= ""
            if not rankShown then
                if not button.SetNameText then
                    local overlayFrame = button._textOverlay or button
                    button.SetNameText = overlayFrame:CreateFontString(nil, "OVERLAY", nil, 7)
                    button.SetNameText:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
                    button.SetNameText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
                    button.SetNameText:SetTextColor(1, 1, 1, 1)
                    button.SetNameText:SetJustifyH("CENTER")
                    button.SetNameText:SetWordWrap(false)
                    button.SetNameText:SetMaxLines(1)
                    button.SetNameText:SetFont(
                        GetFont(),
                        BP().bagSetNameFontSize or 9,
                        (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
                    )
                end
                button.SetNameText:SetText(payload._setName)
            elseif button.SetNameText then
                button.SetNameText:SetText("")
            end
        elseif button.SetNameText then
            button.SetNameText:SetText("")
        end

        -- Profession quality overlay: let SetItemButtonQuality decide so every item type is covered, not just guessed "profession" ones.
        if payload.itemLink then
            button:SetItemButtonQuality(quality, payload.itemLink, false, false)
        end
        -- Visibility via alpha 0/1 only (immune to parent inheritance), even though SetItemButtonQuality may have called Show() internally.
        if button.ProfessionQualityOverlay then
            if button.ProfessionQualityOverlay:IsShown() then
                button.ProfessionQualityOverlay:SetAlpha(1)
                if button._textOverlay then
                    button.ProfessionQualityOverlay:SetParent(button._textOverlay)
                end
            else
                button.ProfessionQualityOverlay:SetAlpha(0)
            end
        end
        -- Cosmetic/warbound overlays: SetItemButtonQuality re-shows these, so handle AFTER it; reparent to textOverlay to render above inset borders.
        if button.IconOverlay then
            if button.IconOverlay:IsShown() then
                button.IconOverlay:SetAlpha(1)
                if button._textOverlay then
                    button.IconOverlay:SetParent(button._textOverlay)
                end
            else
                button.IconOverlay:SetAlpha(0)
            end
        end
        if button.icon and payload.info and payload.info.itemID then
            if BagsItemUnusable(payload.bag, payload.slot, payload.itemLink, payload.info.itemID) then
                button.icon:SetVertexColor(1, 0.1, 0.1)
            else
                button.icon:SetVertexColor(1, 1, 1)
            end
        end
        if button.IconOverlay2 then
            if button.IconOverlay2:IsShown() then
                button.IconOverlay2:SetAlpha(1)
                if button._textOverlay then
                    button.IconOverlay2:SetParent(button._textOverlay)
                end
            else
                button.IconOverlay2:SetAlpha(0)
            end
        end
        if button.IconBorder then
            button.IconBorder:Hide()
        end
        if button.NormalTexture then
            button.NormalTexture:SetAlpha(0)
        end

        -- Quest items get a gold 2px border overriding the 1px quality border;
        -- thickness is re-set every render because buttons are pooled.
        local _bpx = (CUI and CUI.PP and CUI.PP.mult) or 1
        if button._fvSlotBorder then
            local red, green, blue = QualityBorderColor(quality)
            SetInsetBorderColor(button, red, green, blue, 1)
            mod.SetForeverSlotQuestBorder(button, payload._isQuest, payload._isQuestStarter)
        elseif payload._isQuest then
            SetInsetBorderThickness(button, _bpx * 2)
            SetInsetBorderColor(
                button,
                QUEST_BORDER_COLOR.r,
                QUEST_BORDER_COLOR.g,
                QUEST_BORDER_COLOR.b,
                filtered and 0.2 or 1
            )
        else
            SetInsetBorderThickness(button, _bpx)
            local red, green, blue = QualityBorderColor(quality)
            SetInsetBorderColor(button, red, green, blue, filtered and 0.2 or 1)
        end
        -- Quest marker atlas (lazy, reused). Only for items that START a quest you
        -- have not accepted; active-quest objective items get the border, no marker.
        if payload._isQuestStarter and not button._fvSlotBorder then
            if not button._questMarker then
                local qm = (button._textOverlay or button):CreateTexture(nil, "OVERLAY", nil, 6)
                qm:SetAtlas("Crosshair_Quest_64")
                qm:SetSize(22, 22)
                qm:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -3, 2)
                button._questMarker = qm
            end
            button._questMarker:Show()
        elseif button._questMarker then
            button._questMarker:Hide()
        end

        -- Warbank dim overlay: dim non-warbound items while a warband tab is open.
        if not button._warbankDim then
            local dimFrame = CreateFrame("Frame", nil, button)
            dimFrame:SetAllPoints()
            -- Above the text overlay (+3); ns.PinItemButton moves it with the button
            dimFrame:SetFrameLevel(button:GetFrameLevel() + 6)
            local size = dimFrame:CreateTexture(nil, "OVERLAY")
            size:SetAllPoints()
            size:SetColorTexture(0, 0, 0, 0.75)
            dimFrame:Hide()
            button._warbankDim = dimFrame
        end
        local bank = _G.CUI_BankFrame
        local showDim = bank
            and bank:IsVisible()
            and bank.IsWarbandView
            and bank:IsWarbandView()
            and not payload._isWarbound
        if showDim then
            button._warbankDim:Show()
        else
            button._warbankDim:Hide()
        end

        if button.Cooldown then
            if payload._cdStart then
                button.Cooldown:SetDrawEdge(true)
                button.Cooldown:SetCooldown(payload._cdStart, payload._cdDuration)
            else
                button.Cooldown:Clear()
            end
        end
    end
    UpdatePawnArrow(button, payload.itemLink)
    CUI_Bags.RunItemOverlays(button, payload)

    -- Same requery the native container update does after re-assigning a slot: the
    -- cursor can be resting on this button while the repaint moves another item under
    -- it, and nothing re-reads the tooltip until the mouse moves (it kept showing the
    -- sold item, or stayed hidden for the one that slid in). Presence comes from our
    -- own render data: the template's HasItem() reads a field only its own update writes.
    if GameTooltip:IsOwned(button) then
        if payload.info and button.UpdateTooltip then
            button:UpdateTooltip()
        else
            GameTooltip:Hide()
        end
    end
end
mod.RenderButton = RenderButton -- shared with CludesUIBags_Compact.lua

-- "Hide" link on a Pinned / Recent header. Headers are pooled across views, so
-- the link reads the setting it turns off (_dbKey) and its tooltip (_tooltip)
-- from fields that every pass showing it sets.
local function GetHeaderHideButton(heading)
    local headerBtn = heading._hideBtn
    if headerBtn then
        return headerBtn
    end
    headerBtn = CreateFrame("Button", nil, heading)
    headerBtn:SetSize(30, 16)
    headerBtn._fs = headerBtn:CreateFontString(nil, "OVERLAY")
    SetBagFont(headerBtn._fs, 9)
    headerBtn._fs:SetAllPoints()
    headerBtn._fs:SetText(CludesUI.L("Hide"))
    headerBtn._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
    headerBtn:SetScript("OnEnter", function(self)
        self._fs:SetTextColor(1, 1, 1, 0.9)
        CUI.ShowWidgetTooltip(self, self._tooltip)
    end)
    headerBtn:SetScript("OnLeave", function(self)
        self._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
        CUI.HideWidgetTooltip()
    end)
    headerBtn:SetScript("OnClick", function(self)
        BP()[self._dbKey] = false
        CUI_Bags:RefreshInventory()
    end)
    heading._hideBtn = headerBtn
    return headerBtn
end

-------------------------------------------------------------------------------
--  Grid layout pass. Called by RefreshInventory after the shared scan,
--  classify, filter and scroll setup; returns the content bottom (curY).
-------------------------------------------------------------------------------
function mod.RenderGridView(
    tempItems,
    displayItems,
    emptySlots,
    childFrame,
    colCount,
    gridW,
    gridPadX,
    showPinned,
    pinnedSet
)
    local selectedCategoryIndex, selectedGroupName = mod.GetSelection()
    junkOn = CUI_CategoryManager:IsJunkMarkerEnabled()
    compact = CUI_Bags.IsCompactMode() == true

    -- 5. Render grid into scroll child
    for _, button in pairs(itemSlots) do
        if button.ProfessionQualityOverlay then
            button.ProfessionQualityOverlay:SetAlpha(0)
        end
        if button.IconOverlay then
            button.IconOverlay:SetAlpha(0)
            button.IconOverlay:Hide()
        end
        if button.IconOverlay2 then
            button.IconOverlay2:SetAlpha(0)
            button.IconOverlay2:Hide()
        end
    end
    if CUI_Bags._emptyPads then
        for _, pad in pairs(CUI_Bags._emptyPads) do
            pad:Hide()
        end
    end
    local catTitleSize = GetCatTitleSize()
    for _, heading in pairs(_catHeaders) do
        heading:Hide()
        heading._hint:SetText("")
        if heading._hintText then
            mod.SetHeaderHint(heading, nil)
        end
        if heading._hideBtn then
            heading._hideBtn:Hide()
        end
        if heading._clearBtn then
            heading._clearBtn:Hide()
        end
        heading._line:ClearAllPoints()
        heading._line:SetPoint("LEFT", heading._hint, "RIGHT", 6, 0)
        heading._line:SetPoint("RIGHT", heading, "RIGHT", -SPACING, 0)
        SetBagFont(heading._label, catTitleSize)
        SetBagFont(heading._hint, catTitleSize - 1)
    end
    -- The user category's Edit | Delete row sits on the scroll child, outside
    -- its header; the single category view shows it again when needed
    do
        local editDelete = _catHeaders[1] and _catHeaders[1]._editDeleteFrame
        if editDelete then
            editDelete:Hide()
        end
    end
    for _, sh in pairs(_expSubHeaders) do
        sh:Hide()
    end
    if CUI_Bags._pinOverlayBtn then
        CUI_Bags._pinOverlayBtn:Hide()
    end
    ResetAssignOverlays()

    -- Items position relative to scroll child (startX = padding only, no sidebar offset)
    local startX = gridPadX + 5
    local nextY = -6
    local slotIndex = 0
    if compact then
        mod.CompactBagsBegin()
    end

    -- Lightweight empty pad pool (no ItemButton template, just bg + border)
    if not CUI_Bags._emptyPads then
        CUI_Bags._emptyPads = {}
    end
    local _emptyPads = CUI_Bags._emptyPads
    local _emptyPadIdx = 0

    local function GetOrCreateEmptyPad(position)
        if _emptyPads[position] then
            return _emptyPads[position]
        end
        local frame = CreateFrame("Frame", nil, CUI_Bags)
        mod.SizeSlot(frame)
        frame:EnableMouse(false)
        frame._bg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        frame._bg:SetAllPoints()
        mod.SetSlotBackgroundTexture(frame._bg, false)
        frame._bg:SetAlpha(0.35)
        CreateInsetBorder(frame, true)
        SetInsetBorderColor(frame, 0, 0, 0, 0.3)
        _emptyPads[position] = frame
        return frame
    end

    local function RenderEmptyPad(itemTotal, padSlots)
        for p = 1, padSlots do
            _emptyPadIdx = _emptyPadIdx + 1
            local pad = GetOrCreateEmptyPad(_emptyPadIdx)
            pad:SetParent(childFrame)
            pad:ClearAllPoints()
            local totalIdx = itemTotal + p
            local colour = (totalIdx - 1) % colCount
            local row = math.floor((totalIdx - 1) / colCount)
            pad:SetPoint(
                "TOPLEFT",
                startX + (colour * (SLOT_SIZE + SPACING)),
                nextY - (row * (SLOT_SIZE + SPACING))
            )
            mod.PaintSlotBackground(pad._bg, 0.35)
            pad:Show()
        end
    end

    local function RenderItemBlock(blockItems)
        local num = #blockItems
        for jdx, payload in ipairs(blockItems) do
            slotIndex = slotIndex + 1
            local button = GetOrCreateSlot(slotIndex)
            if button then -- nil during combat (avoids minting tainted secure buttons)
                button:GetParent():SetParent(childFrame)
                local colour = (jdx - 1) % colCount
                local row = math.floor((jdx - 1) / colCount)
                RenderButton(button, payload, slotIndex, colour, row, startX, nextY, colCount)
            end
        end
        local leftover = num % colCount
        local padSlots
        if num == 0 then
            padSlots = colCount
        elseif leftover == 0 then
            padSlots = 0
        else
            padSlots = colCount - leftover
        end
        -- Filler pads are cosmetic row-fillers (the "+" button is the only real slot); NEVER clamp to #emptySlots or they vanish when bags are full.
        if padSlots > 0 then
            RenderEmptyPad(num, padSlots)
        end
        local totalInBlock = num + math.max(padSlots, 0)
        local blockRows = math.ceil(totalInBlock / colCount)
        nextY = nextY - (blockRows * (SLOT_SIZE + SPACING))
    end

    -- Compact Armory layout. Reuses the existing slot, sub-header, empty-pad,
    -- and assignment pools; only the coordinates differ from the full-row path.
    local armorySlotGrouping = ArmorySlotGroupingEnabled()
    local RenderCompactSlotBuckets
    if not compact and BP().bagCompactArmorySlotGroups and armorySlotGrouping then
        RenderCompactSlotBuckets = function(bucketList, subHeaderIdx, assignCatKey)
            local stride = SLOT_SIZE + SPACING
            local usableWidth = colCount * stride - SPACING
            local headerGap = 18
            local epsilon = 0.5
            local categoryGap = math.max(8, SPACING * 3)
            local assignBucket = assignCatKey and bucketList[1] and 1 or nil

            -- Prepare the headers first so their text widths can reserve enough
            -- horizontal space before the buckets are packed into rows.
            for index, catBucket in ipairs(bucketList) do
                subHeaderIdx = subHeaderIdx + 1
                local headerBar = GetOrCreateExpSubHeader(subHeaderIdx)
                headerBar:SetParent(childFrame)
                headerBar._label:SetText(catBucket.label .. " (" .. #catBucket.items .. ")")
                SetBagFont(headerBar._label, math.max(8, catTitleSize - 2))

                local itemTotal = #catBucket.items + ((index == assignBucket) and 1 or 0)
                local span = math.min(colCount, itemTotal)
                local bucketWidth = span * stride - SPACING
                catBucket._compactHeader = headerBar
                catBucket._compactItemCount = itemTotal
                catBucket._compactSpan = span
                catBucket._compactRows = math.ceil(itemTotal / span)
                catBucket._compactWidth = bucketWidth

                if itemTotal <= colCount then
                    categoryGap =
                        math.max(categoryGap, (headerBar._label:GetStringWidth() or 0) + 6 - bucketWidth)
                end
            end

            local function RenderPadsAt(itemTop, usedWidth)
                local padSlots = math.floor((usableWidth - usedWidth + epsilon) / stride)
                for index = 1, padSlots do
                    _emptyPadIdx = _emptyPadIdx + 1
                    local pad = GetOrCreateEmptyPad(_emptyPadIdx)
                    pad:SetParent(childFrame)
                    pad:ClearAllPoints()
                    pad:SetPoint(
                        "TOPLEFT",
                        childFrame,
                        "TOPLEFT",
                        startX + usedWidth + SPACING + (index - 1) * stride,
                        itemTop
                    )
                    mod.PaintSlotBackground(pad._bg, 0.35)
                    pad:Show()
                end
            end

            local rowTop = nextY
            local usedWidth = 0
            local rowItemRows = 0

            for index, catBucket in ipairs(bucketList) do
                local span = catBucket._compactSpan
                local itemRows = catBucket._compactRows
                local bucketWidth = catBucket._compactWidth
                local startOffset = usedWidth > 0 and usedWidth + categoryGap or 0

                -- Multi-row buckets always begin on a fresh row. Smaller buckets
                -- share a row for as long as the next one still fits.
                if usedWidth > 0 and (startOffset + bucketWidth > usableWidth + epsilon or itemRows > 1) then
                    RenderPadsAt(rowTop - headerGap, usedWidth)
                    rowTop = rowTop - headerGap - rowItemRows * stride
                    usedWidth = 0
                    rowItemRows = 0
                    startOffset = 0
                end

                local headerBar = catBucket._compactHeader
                headerBar:ClearAllPoints()
                headerBar:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX + startOffset, rowTop)
                headerBar:SetWidth(math.max(1, bucketWidth))
                headerBar:Show()

                for itemIndex, payload in ipairs(catBucket.items) do
                    slotIndex = slotIndex + 1
                    local button = GetOrCreateSlot(slotIndex)
                    if button then
                        button:GetParent():SetParent(childFrame)
                        local colour = (itemIndex - 1) % span
                        local row = math.floor((itemIndex - 1) / span)
                        RenderButton(
                            button,
                            payload,
                            slotIndex,
                            colour,
                            row,
                            startX + startOffset,
                            rowTop - headerGap,
                            colCount
                        )
                    end
                end

                if index == assignBucket then
                    slotIndex = slotIndex + 1
                    local assignSlot = GetOrCreateSlot(slotIndex)
                    if assignSlot then
                        assignSlot:GetParent():SetParent(childFrame)
                        local itemIndex = #catBucket.items + 1
                        local colour = (itemIndex - 1) % span
                        local row = math.floor((itemIndex - 1) / span)
                        RenderButton(
                            assignSlot,
                            { bag = 0, slot = 0 },
                            slotIndex,
                            colour,
                            row,
                            startX + startOffset,
                            rowTop - headerGap,
                            colCount
                        )
                        local overlayFrame = GetOrCreateAssignOverlay()
                        overlayFrame._assignCatKey = assignCatKey
                        overlayFrame:SetParent(childFrame)
                        overlayFrame:ClearAllPoints()
                        overlayFrame:SetAllPoints(assignSlot)
                        overlayFrame:Show()
                    end
                end

                usedWidth = startOffset + bucketWidth
                rowItemRows = math.max(rowItemRows, itemRows)

                if itemRows > 1 then
                    local leftover = catBucket._compactItemCount % colCount
                    if leftover > 0 then
                        local lastRowWidth = leftover * stride - SPACING
                        RenderPadsAt(rowTop - headerGap - (itemRows - 1) * stride, lastRowWidth)
                    end
                    rowTop = rowTop - headerGap - itemRows * stride
                    usedWidth = 0
                    rowItemRows = 0
                end
            end

            if usedWidth > 0 then
                RenderPadsAt(rowTop - headerGap, usedWidth)
                rowTop = rowTop - headerGap - rowItemRows * stride
            end

            nextY = rowTop - 6
            return subHeaderIdx
        end
    end

    local RenderSlotBuckets
    if armorySlotGrouping and not compact then
        RenderSlotBuckets = function(bucketList, subHeaderIdx, assignCatKey)
            if RenderCompactSlotBuckets then
                return RenderCompactSlotBuckets(bucketList, subHeaderIdx, assignCatKey)
            end

            local assignShown = false
            for _, catBucket in ipairs(bucketList) do
                if #catBucket.items > 0 then
                    subHeaderIdx = subHeaderIdx + 1
                    local headerBar = GetOrCreateExpSubHeader(subHeaderIdx)
                    headerBar:SetParent(childFrame)
                    headerBar:ClearAllPoints()
                    headerBar:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, nextY)
                    headerBar:SetWidth(gridW)
                    headerBar._label:SetText(catBucket.label .. " (" .. #catBucket.items .. ")")
                    SetBagFont(headerBar._label, math.max(8, catTitleSize - 2))
                    headerBar:Show()
                    nextY = nextY - 18
                    RenderItemBlock(catBucket.items)

                    if assignCatKey and not assignShown then
                        assignShown = true
                        local leftover = #catBucket.items % colCount
                        if leftover ~= 0 then
                            nextY = nextY + (SLOT_SIZE + SPACING)
                        end
                        slotIndex = slotIndex + 1
                        local assignSlot = GetOrCreateSlot(slotIndex)
                        if assignSlot then
                            assignSlot:GetParent():SetParent(childFrame)
                            RenderButton(
                                assignSlot,
                                { bag = 0, slot = 0 },
                                slotIndex,
                                leftover,
                                0,
                                startX,
                                nextY,
                                colCount
                            )
                            local overlayFrame = GetOrCreateAssignOverlay()
                            overlayFrame._assignCatKey = assignCatKey
                            overlayFrame:SetParent(childFrame)
                            overlayFrame:ClearAllPoints()
                            overlayFrame:SetAllPoints(assignSlot)
                            overlayFrame:Show()
                        end
                        nextY = nextY - (SLOT_SIZE + SPACING)
                    end
                end
            end
            nextY = nextY - 6
            return subHeaderIdx
        end
    end

    if selectedCategoryIndex == -1 or selectedCategoryIndex == -2 then
        -- OneBag/MultiBag: Pinned Items (display-only) + bag section(s) + Reagent Bag. OneBag
        -- merges bags 0-4 into one "Main Bags" section, MultiBag renders one per bag; reuses tempItems + emptySlots instead of re-querying bags.
        local headerIndex = 0
        local isMulti = (selectedCategoryIndex == -2)

        -- Pinned Items quickview (display-only duplicates)
        local showPinnedOneBag = (BP().bagPinnedInOneBag ~= false) and showPinned
        if showPinnedOneBag then
            local pinItems = {}
            if pinnedSet then
                for _, skinData in ipairs(tempItems) do
                    if skinData.info and skinData.info.itemID and IsItemPinned(pinnedSet, skinData.itemLink, skinData.info.itemID) then
                        pinItems[#pinItems + 1] = skinData
                    end
                end
            end
            if #pinItems > 0 then
                pinItems = MergeDuplicates(pinItems)
            end
            if compact then
                mod.CompactBagsSection(CludesUI.L("Pinned Items"), pinItems, "pinned")
            else
                headerIndex = headerIndex + 1
                local pinnedHeader = GetOrCreateCatHeader(headerIndex)
                pinnedHeader:SetParent(childFrame)
                pinnedHeader:ClearAllPoints()
                pinnedHeader:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, nextY)
                pinnedHeader:SetWidth(colCount * (SLOT_SIZE + SPACING))
                pinnedHeader._label:SetText(CludesUI.L("Pinned Items"))
                mod.SetHeaderHint(pinnedHeader, CludesUI.L("Middle Click to Add or Remove"))
                local pinHide = GetHeaderHideButton(pinnedHeader)
                pinHide._dbKey = "bagPinnedInOneBag"
                pinHide._tooltip = "Hides Pinned Items. Re-show in settings."
                pinnedHeader._hideBtn:ClearAllPoints()
                pinnedHeader._hideBtn:SetPoint("RIGHT", pinnedHeader, "RIGHT", 0, 0)
                pinnedHeader._hideBtn:Show()
                pinnedHeader._line:ClearAllPoints()
                pinnedHeader._line:SetPoint("LEFT", pinnedHeader._hint, "RIGHT", 6, 0)
                pinnedHeader._line:SetPoint("RIGHT", pinnedHeader._hideBtn, "LEFT", -6, 0)
                pinnedHeader:Show()
                nextY = nextY - 22

                for jdx, payload in ipairs(pinItems) do
                    slotIndex = slotIndex + 1
                    local button = GetOrCreateSlot(slotIndex)
                    if button then -- nil during combat (avoids minting tainted secure buttons)
                        button:GetParent():SetParent(childFrame)
                        local colour = (jdx - 1) % colCount
                        local row = math.floor((jdx - 1) / colCount)
                        RenderButton(button, payload, slotIndex, colour, row, startX, nextY, colCount)
                    end
                end
                local pinItemCount = #pinItems
                do
                    local pinIdx = pinItemCount + 1
                    slotIndex = slotIndex + 1
                    local pinSlot = GetOrCreateSlot(slotIndex)
                    if pinSlot then -- nil during combat (avoids minting tainted secure buttons)
                        pinSlot:GetParent():SetParent(childFrame)
                        local colour = (pinIdx - 1) % colCount
                        local row = math.floor((pinIdx - 1) / colCount)
                        RenderButton(pinSlot, { bag = 0, slot = 0 }, slotIndex, colour, row, startX, nextY, colCount)
                        local shade = GetOrCreatePinOverlay()
                        shade:SetParent(childFrame)
                        shade:ClearAllPoints()
                        shade:SetAllPoints(pinSlot)
                        shade:Show()
                        pinItemCount = pinItemCount + 1
                    end
                end
                -- Pad remaining slots in last row
                local pinRemainder = pinItemCount % colCount
                local pinPadCount = pinRemainder == 0 and 0 or (colCount - pinRemainder)
                if pinItemCount == 0 then
                    pinPadCount = colCount
                end
                if pinPadCount > 0 then
                    RenderEmptyPad(pinItemCount, pinPadCount)
                end
                local pinTotal = pinItemCount + pinPadCount
                local pinRows = math.ceil(pinTotal / colCount)
                nextY = nextY - (pinRows * (SLOT_SIZE + SPACING)) - 6
            end -- compact vs grid
        end

        -- Recent Items quickview (display-only duplicates)
        local showRecentOneBag = BP().bagRecentInOneBag == true
        local showRecent = BP().bagShowRecentItems ~= false
        if showRecentOneBag and showRecent then
            local recentList = {}
            if CUI_Bags._recentItems then
                for _, skinData in ipairs(tempItems) do
                    if
                        not skinData._pinnedOnly
                        and skinData.info
                        and skinData.info.itemID
                        and CUI_Bags._recentItems[skinData.info.itemID]
                    then
                        recentList[#recentList + 1] = skinData
                    end
                end
            end
            if #recentList > 0 then
                recentList = MergeDuplicates(recentList)
                table.sort(recentList, RecentCompare)
            end
            if compact then
                mod.CompactBagsSection(CludesUI.L("Recent Items"), recentList, "recent")
            else
                headerIndex = headerIndex + 1
                local recentHeader = GetOrCreateCatHeader(headerIndex)
                recentHeader:SetParent(childFrame)
                recentHeader:ClearAllPoints()
                recentHeader:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, nextY)
                recentHeader:SetWidth(colCount * (SLOT_SIZE + SPACING))
                recentHeader._label:SetText(CludesUI.L("Recent Items"))
                mod.SetHeaderHint(
                    recentHeader,
                    CludesUI.L("Extra quickview display, your items are also in their category")
                )
                local recHide = GetHeaderHideButton(recentHeader)
                recHide._dbKey = "bagRecentInOneBag"
                recHide._tooltip = "Hides Recent Items. Re-show in settings."
                recentHeader._hideBtn:ClearAllPoints()
                recentHeader._hideBtn:SetPoint("RIGHT", recentHeader, "RIGHT", 0, 0)
                recentHeader._hideBtn:Show()
                local recLineAnchor = recentHeader._hideBtn
                if
                    BP().bagShowRecentClear == true
                    and CUI_Bags._recentItems
                    and next(CUI_Bags._recentItems)
                then
                    recLineAnchor = ShowRecentClearButton(recentHeader, recentHeader._hideBtn)
                end
                recentHeader._line:ClearAllPoints()
                recentHeader._line:SetPoint("LEFT", recentHeader._hint, "RIGHT", 6, 0)
                recentHeader._line:SetPoint("RIGHT", recLineAnchor, "LEFT", -6, 0)
                recentHeader:Show()
                nextY = nextY - 22

                for jdx, payload in ipairs(recentList) do
                    slotIndex = slotIndex + 1
                    local button = GetOrCreateSlot(slotIndex)
                    if button then -- nil during combat (avoids minting tainted secure buttons)
                        button:GetParent():SetParent(childFrame)
                        local colour = (jdx - 1) % colCount
                        local row = math.floor((jdx - 1) / colCount)
                        RenderButton(button, payload, slotIndex, colour, row, startX, nextY, colCount)
                    end
                end
                local recItemCount = #recentList
                local recRemainder = recItemCount % colCount
                local recPadCount = recRemainder == 0 and 0 or (colCount - recRemainder)
                if recItemCount == 0 then
                    recPadCount = colCount
                end
                if recPadCount > 0 then
                    RenderEmptyPad(recItemCount, recPadCount)
                end
                local recTotal = recItemCount + recPadCount
                local recRows = math.ceil(recTotal / colCount)
                nextY = nextY - (recRows * (SLOT_SIZE + SPACING)) - 6
            end -- compact vs grid
        end

        -- One section header + item grid for a slot list, advancing the shared
        -- curY/slotIdx/headerIdx upvalues (used by OneBag's "Main Bags" and MultiBag's per-bag sections).
        local function RenderBagGrid(labelText, slotList)
            if #slotList == 0 then
                return
            end
            if compact then
                mod.CompactBagsSlots(labelText, slotList)
                return
            end
            headerIndex = headerIndex + 1
            local heading = GetOrCreateCatHeader(headerIndex)
            heading:SetParent(childFrame)
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, nextY)
            heading:SetWidth(colCount * (SLOT_SIZE + SPACING))
            heading._label:SetText(labelText)
            heading:Show()
            nextY = nextY - 22
            for i, payload in ipairs(slotList) do
                slotIndex = slotIndex + 1
                local button = GetOrCreateSlot(slotIndex)
                if button then -- nil during combat (avoids minting tainted secure buttons)
                    button:GetParent():SetParent(childFrame)
                    local colour = (i - 1) % colCount
                    local row = math.floor((i - 1) / colCount)
                    RenderButton(button, payload, slotIndex, colour, row, startX, nextY, colCount, true)
                end
            end
            local rowList = math.ceil(#slotList / colCount)
            nextY = nextY - (rowList * (SLOT_SIZE + SPACING)) - 6
        end

        -- One bag's items + empties as a section titled with the bag's name, in
        -- slot order (MultiBag's bags, OneBag's special bags).
        local BagDisplayName = mod.BagDisplayName
        local function RenderOneBag(bag)
            local bagList = {}
            local bagFilled = 0
            for _, skinData in ipairs(tempItems) do
                if skinData.bag == bag then
                    bagList[#bagList + 1] = skinData
                    bagFilled = bagFilled + 1
                end
            end
            for _, skinData in ipairs(emptySlots) do
                if skinData.bag == bag then
                    bagList[#bagList + 1] = skinData
                end
            end
            if #bagList > 0 then
                table.sort(bagList, function(lhs, rhs)
                    return lhs.slot < rhs.slot
                end)
                RenderBagGrid(BagDisplayName(bag) .. " (" .. bagFilled .. " / " .. #bagList .. ")", bagList)
            end
        end

        if not isMulti then
            -- OneBag: Main Bags (0-4) merged, in bag:slot order; a WoW Forever
            -- special bag (ns.SpecialBags) gets its own section after it.
            local special = mod.SpecialBags()
            local mainSlots = {}
            local mainFilled = 0
            for _, skinData in ipairs(tempItems) do
                if skinData.bag ~= 5 and not (special and special[skinData.bag]) then
                    mainSlots[#mainSlots + 1] = skinData
                    mainFilled = mainFilled + 1
                end
            end
            for _, skinData in ipairs(emptySlots) do
                if skinData.bag ~= 5 and not (special and special[skinData.bag]) then
                    mainSlots[#mainSlots + 1] = skinData
                end
            end
            table.sort(mainSlots, function(lhs, rhs)
                if lhs.bag ~= rhs.bag then
                    return lhs.bag < rhs.bag
                end
                return lhs.slot < rhs.slot
            end)
            RenderBagGrid(CludesUI.Lf("Main Bags (%d / %d)", mainFilled, #mainSlots), mainSlots)
            if special then
                for bag = 1, 4 do
                    if special[bag] then
                        RenderOneBag(bag)
                    end
                end
            end
        else
            -- MultiBag: one section per equipped bag (0-4)
            for bag = 0, 4 do
                RenderOneBag(bag)
            end
        end

        -- Reagent Bag (5): items + empties from bag 5
        local reagentSlotList = {}
        for _, skinData in ipairs(tempItems) do
            if skinData.bag == 5 then
                reagentSlotList[#reagentSlotList + 1] = skinData
            end
        end
        for _, skinData in ipairs(emptySlots) do
            if skinData.bag == 5 then
                reagentSlotList[#reagentSlotList + 1] = skinData
            end
        end
        table.sort(reagentSlotList, function(lhs, rhs)
            return lhs.slot < rhs.slot
        end)

        if #reagentSlotList > 0 then
            local reagFilled = 0
            for _, skinData in ipairs(reagentSlotList) do
                if skinData.info then
                    reagFilled = reagFilled + 1
                end
            end
            local reagLabel = CludesUI.Lf("Reagent Bag (%d / %d)", reagFilled, #reagentSlotList)
            if compact then
                mod.CompactBagsSlots(reagLabel, reagentSlotList)
            else
                headerIndex = headerIndex + 1
                local reagHdr = GetOrCreateCatHeader(headerIndex)
                reagHdr:SetParent(childFrame)
                reagHdr:ClearAllPoints()
                reagHdr:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, nextY)
                reagHdr:SetWidth(colCount * (SLOT_SIZE + SPACING))
                reagHdr._label:SetText(reagLabel)
                reagHdr:Show()
                nextY = nextY - 22

                for i, payload in ipairs(reagentSlotList) do
                    slotIndex = slotIndex + 1
                    local button = GetOrCreateSlot(slotIndex)
                    if button then -- nil during combat (avoids minting tainted secure buttons)
                        button:GetParent():SetParent(childFrame)
                        local colour = (i - 1) % colCount
                        local row = math.floor((i - 1) / colCount)
                        RenderButton(button, payload, slotIndex, colour, row, startX, nextY, colCount, true)
                    end
                end
                local reagRows = math.ceil(#reagentSlotList / colCount)
                nextY = nextY - (reagRows * (SLOT_SIZE + SPACING))
            end -- compact vs grid
        end
    elseif selectedCategoryIndex == 0 and not selectedGroupName then
        -- "All Items" view: group by category with headers
        local categories = CUI_CategoryManager:GetCategories()
        local itemsByCat = {}
        for i = 1, #categories do
            itemsByCat[i] = {}
        end
        for _, payload in ipairs(displayItems) do
            local ci = payload.categoryIndex
            if ci and itemsByCat[ci] and not payload._pinnedOnly then
                itemsByCat[ci][#itemsByCat[ci] + 1] = payload
            end
        end
        for i = 1, #categories do
            if #itemsByCat[i] > 0 and not categories[i].groupName and not categories[i].isRecent then
                ApplySavedOrder(i, itemsByCat[i])
            end
        end
        -- Merge duplicates after ordering so first-in-visual-order wins
        for i = 1, #categories do
            if #itemsByCat[i] > 1 then
                itemsByCat[i] = MergeDuplicates(itemsByCat[i])
            end
        end

        -- Build render sections: ungrouped = individual, grouped = merged under group name
        local renderedGroups = {}
        local headerIndex = 0
        local expSubIdx = 0

        local function RenderSection(
            sectionName,
            sectionItems,
            isUserCreated,
            showPinAdd,
            alwaysShow,
            assignCatIdx,
            nestByExpansion
        )
            local itemTotal = #sectionItems
            if itemTotal == 0 and not isUserCreated and not showPinAdd and not alwaysShow then
                return
            end

            local useSlotNest = armorySlotGrouping
                and IsGearOnlyGroup(sectionName)
                and itemTotal > 0
                and not showPinAdd
                and not alwaysShow

            local useExpNest = nestByExpansion
                and BP().bagNestByExpansion
                and not useSlotNest
                and itemTotal > 0
                and not showPinAdd
                and not alwaysShow

            -- sectionName is the group's key; this is what the label shows
            local labelText = CUI_CategoryManager:GroupDisplayName(sectionName)

            -- Compact: the collector draws this section (CludesUIBags_Compact.lua)
            if compact then
                local assignKey
                if assignCatIdx and CUI_CategoryManager:CanAssignToCategory(assignCatIdx) then
                    local aCat = CUI_CategoryManager:GetCategories()[assignCatIdx]
                    assignKey = aCat and aCat._defaultName
                end
                local kind = (showPinAdd and "pinned")
                    or (alwaysShow and "recent")
                    or (useSlotNest and "slot")
                    or (useExpNest and "exp")
                    or "flat"
                mod.CompactBagsSection(labelText, sectionItems, kind, assignKey)
                return
            end

            headerIndex = headerIndex + 1
            local heading = GetOrCreateCatHeader(headerIndex)
            heading:SetParent(childFrame)
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, nextY)
            heading:SetWidth(gridW)
            heading._label:SetText(labelText .. " (" .. itemTotal .. ")")
            -- Pinned / Recent: their hint shows while the label is hovered
            if showPinAdd then
                mod.SetHeaderHint(heading, CludesUI.L("Middle Click to Add or Remove"))
            elseif alwaysShow then
                mod.SetHeaderHint(
                    heading,
                    CludesUI.L("Extra quickview display, your items are also in their category")
                )
            end
            -- Hide button for Pinned / Recent sections
            if showPinAdd or alwaysShow then
                GetHeaderHideButton(heading)
                heading._hideBtn._dbKey = showPinAdd and "bagShowPinnedItems" or "bagShowRecentItems"
                heading._hideBtn._tooltip = showPinAdd and "Hides Pinned Items. Re-show in settings."
                    or "Hides Recent Items. Re-show in settings."
                heading._hideBtn:ClearAllPoints()
                heading._hideBtn:SetPoint("RIGHT", heading, "RIGHT", 0, 0)
                heading._hideBtn:Show()
                -- Recent Items only, opt-in: "Clear" left of "Hide", and only when
                -- there is something to clear.
                local lineAnchor = heading._hideBtn
                if
                    alwaysShow
                    and not showPinAdd
                    and BP().bagShowRecentClear == true
                    and CUI_Bags._recentItems
                    and next(CUI_Bags._recentItems)
                then
                    lineAnchor = ShowRecentClearButton(heading, heading._hideBtn)
                end
                heading._line:ClearAllPoints()
                heading._line:SetPoint("LEFT", heading._hint, "RIGHT", 6, 0)
                heading._line:SetPoint("RIGHT", lineAnchor, "LEFT", -6, 0)
            end
            heading:Show()
            nextY = nextY - 22

            if useSlotNest then
                local bucketList = BuildSlotBuckets(sectionItems)
                if #bucketList > 0 then
                    local showAssign = assignCatIdx
                        and CUI_CategoryManager
                        and CUI_CategoryManager:CanAssignToCategory(assignCatIdx)
                    local categories = showAssign and CUI_CategoryManager:GetCategories()
                    local assignCat = categories and categories[assignCatIdx]
                    expSubIdx = RenderSlotBuckets(bucketList, expSubIdx, assignCat and assignCat._defaultName)
                    return
                end
            end

            if useExpNest then
                local bucketList = BuildExpansionBuckets(sectionItems)
                if #bucketList > 0 then
                    local showAssign = assignCatIdx
                        and CUI_CategoryManager
                        and CUI_CategoryManager:CanAssignToCategory(assignCatIdx)
                    local assignShown = false
                    for _, buck in ipairs(bucketList) do
                        if #buck.items > 0 then
                            expSubIdx = expSubIdx + 1
                            local sh = GetOrCreateExpSubHeader(expSubIdx)
                            sh:SetParent(childFrame)
                            sh:ClearAllPoints()
                            sh:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, nextY)
                            sh:SetWidth(gridW)
                            sh._label:SetText(buck.label .. " (" .. #buck.items .. ")")
                            SetBagFont(sh._label, math.max(8, catTitleSize - 2))
                            sh:Show()
                            nextY = nextY - 18
                            RenderItemBlock(buck.items)
                            -- Place assign "+" after the first bucket's items (newest expansion)
                            if showAssign and not assignShown then
                                assignShown = true
                                local categories = CUI_CategoryManager:GetCategories()
                                local aCat = categories[assignCatIdx]
                                if aCat then
                                    -- RenderItemBlock already advanced curY; back up to place at the next slot after the items.
                                    local num = #buck.items
                                    local leftover = num % colCount
                                    if leftover == 0 then
                                        -- Last row filled exactly: curY already sits on the new row the button needs.
                                    else
                                        -- Back up to the row the items are on
                                        nextY = nextY + (SLOT_SIZE + SPACING)
                                    end
                                    slotIndex = slotIndex + 1
                                    local aSlot = GetOrCreateSlot(slotIndex)
                                    if aSlot then
                                        aSlot:GetParent():SetParent(childFrame)
                                        local colour = leftover
                                        RenderButton(
                                            aSlot,
                                            { bag = 0, slot = 0 },
                                            slotIndex,
                                            colour,
                                            0,
                                            startX,
                                            nextY,
                                            colCount
                                        )
                                        local addOverlay = GetOrCreateAssignOverlay()
                                        addOverlay._assignCatKey = aCat._defaultName
                                        addOverlay:SetParent(childFrame)
                                        addOverlay:ClearAllPoints()
                                        addOverlay:SetAllPoints(aSlot)
                                        addOverlay:Show()
                                    end
                                    -- Re-advance curY for the row
                                    nextY = nextY - (SLOT_SIZE + SPACING)
                                end
                            end
                        end
                    end
                    nextY = nextY - 6
                    return
                end
            end

            for jdx, payload in ipairs(sectionItems) do
                slotIndex = slotIndex + 1
                local button = GetOrCreateSlot(slotIndex)
                if button then
                    button:GetParent():SetParent(childFrame)
                    local colour = (jdx - 1) % colCount
                    local row = math.floor((jdx - 1) / colCount)
                    RenderButton(button, payload, slotIndex, colour, row, startX, nextY, colCount)
                end
            end

            -- Pin "+" button: a regular empty slot with a "+" overlay on top
            if showPinAdd then
                local pinIdx = itemTotal + 1
                slotIndex = slotIndex + 1
                local pinSlot = GetOrCreateSlot(slotIndex)
                if pinSlot then
                    pinSlot:GetParent():SetParent(childFrame)
                    local colour = (pinIdx - 1) % colCount
                    local row = math.floor((pinIdx - 1) / colCount)
                    RenderButton(pinSlot, { bag = 0, slot = 0 }, slotIndex, colour, row, startX, nextY, colCount)
                    local shade = GetOrCreatePinOverlay()
                    shade:SetParent(childFrame)
                    shade:ClearAllPoints()
                    shade:SetAllPoints(pinSlot)
                    shade:Show()
                    itemTotal = itemTotal + 1
                end
            end

            -- Assign "+" button: for categories that accept item assignments
            if
                assignCatIdx
                and CUI_CategoryManager
                and CUI_CategoryManager:CanAssignToCategory(assignCatIdx)
            then
                local categories = CUI_CategoryManager:GetCategories()
                local aCat = categories[assignCatIdx]
                if aCat then
                    local aIdx = itemTotal + 1
                    slotIndex = slotIndex + 1
                    -- GetOrCreateSlot returns nil in combat lockdown (a slot born in combat is tainted); skip, PLAYER_REGEN_ENABLED replays the refresh.
                    local aSlot = GetOrCreateSlot(slotIndex)
                    if aSlot then
                        aSlot:GetParent():SetParent(childFrame)
                        local colour = (aIdx - 1) % colCount
                        local row = math.floor((aIdx - 1) / colCount)
                        RenderButton(aSlot, { bag = 0, slot = 0 }, slotIndex, colour, row, startX, nextY, colCount)
                        local addOverlay = GetOrCreateAssignOverlay()
                        addOverlay._assignCatKey = aCat._defaultName
                        addOverlay:SetParent(childFrame)
                        addOverlay:ClearAllPoints()
                        addOverlay:SetAllPoints(aSlot)
                        addOverlay:Show()
                        itemTotal = itemTotal + 1
                    end
                end
            end

            local leftover = itemTotal % colCount
            local padSlots
            if itemTotal == 0 then
                padSlots = colCount
            elseif leftover == 0 then
                padSlots = 0
            else
                padSlots = colCount - leftover
            end
            -- Filler pads are cosmetic (the "+" assign/pin button is the only real slot); NEVER clamp to #emptySlots or they vanish when bags are full.
            if padSlots > 0 then
                RenderEmptyPad(itemTotal, padSlots)
            end

            local totalInSection = itemTotal + math.max(padSlots, 0)
            local sectionRows = math.ceil(totalInSection / colCount)
            nextY = nextY - (sectionRows * (SLOT_SIZE + SPACING)) - 6
        end

        local hiddenSet = BP().bagHiddenInAllItems or {}
        for ci, category in ipairs(categories) do
            if category.isPinned then
                -- Pinned Items quickview
                if pinnedSet and showPinned then
                    local pinItems = {}
                    for _, payload in ipairs(displayItems) do
                        if
                            payload.info
                            and payload.info.itemID
                            and IsItemPinned(pinnedSet, payload.itemLink, payload.info.itemID)
                        then
                            pinItems[#pinItems + 1] = payload
                        end
                    end
                    if #pinItems > 0 then
                        pinItems = MergeDuplicates(pinItems)
                    end
                    RenderSection(category.name, pinItems, false, true)
                end
            elseif category.isRecent then
                -- Recent Items: display-only duplicate (items also appear in their normal category)
                if CUI_Bags._recentItems and (BP().bagShowRecentItems ~= false) then
                    local recentList = {}
                    for _, payload in ipairs(displayItems) do
                        if
                            not payload._pinnedOnly
                            and payload.info
                            and payload.info.itemID
                            and CUI_Bags._recentItems[payload.info.itemID]
                        then
                            recentList[#recentList + 1] = payload
                        end
                    end
                    if #recentList > 0 then
                        recentList = MergeDuplicates(recentList)
                        table.sort(recentList, RecentCompare)
                    end
                    RenderSection(CludesUI.L("Recent Items"), recentList, false, false, true)
                end
            elseif category.groupName then
                if not renderedGroups[category.groupName] then
                    renderedGroups[category.groupName] = true
                    if not hiddenSet[category.groupName] then
                        local members = CUI_CategoryManager:GetGroupMembers(category.groupName)
                        local merged = {}
                        for _, mi in ipairs(members) do
                            if itemsByCat[mi] then
                                for _, payload in ipairs(itemsByCat[mi]) do
                                    merged[#merged + 1] = payload
                                end
                            end
                            -- The Item Set Gear anchor folds in its set children's items
                            if
                                BP().bagSplitSetGearBySet
                                and categories[mi]
                                and categories[mi].isSetGear
                                and not categories[mi].isEquipSet
                            then
                                for i, c in ipairs(categories) do
                                    if c.isEquipSet and itemsByCat[i] then
                                        for _, payload in ipairs(itemsByCat[i]) do
                                            merged[#merged + 1] = payload
                                        end
                                    end
                                end
                            end
                        end
                        if #merged > 0 then
                            ApplySavedOrder(category.groupName, merged)
                        end
                        RenderSection(category.groupName, merged, false, nil, nil, members[1], true)
                    end
                end
            elseif category.isEquipSet then
                -- Set children render inside their anchor's section
            else
                if not hiddenSet[category._defaultName] then
                    local catItems = itemsByCat[ci] or {}
                    -- The Item Set Gear anchor folds in its set children's items
                    if category.isSetGear and BP().bagSplitSetGearBySet then
                        local folded = nil
                        for i, c in ipairs(categories) do
                            if c.isEquipSet and itemsByCat[i] then
                                if not folded then
                                    folded = {}
                                    for _, payload in ipairs(catItems) do
                                        folded[#folded + 1] = payload
                                    end
                                end
                                for _, payload in ipairs(itemsByCat[i]) do
                                    folded[#folded + 1] = payload
                                end
                            end
                        end
                        catItems = folded or catItems
                    end
                    local isUserCreated = category.isUserCreated
                    RenderSection(
                        category.name,
                        catItems,
                        isUserCreated,
                        category.isPinned,
                        category.isRecent,
                        ci,
                        true
                    )
                end
            end
        end
    else
        if selectedGroupName then
            -- Group view: items split by member category with headers
            local categories = CUI_CategoryManager:GetCategories()
            local members = CUI_CategoryManager:GetGroupMembers(selectedGroupName)
            local headerIndex = 0
            local expSubIdx = 0
            local useSlotNest = armorySlotGrouping and IsGearOnlyGroup(selectedGroupName)

            local itemsByMember = {}
            for _, mi in ipairs(members) do
                itemsByMember[mi] = {}
            end
            -- Split-mode set children fold into their anchor member's section
            local anchorMi, childSet
            if BP().bagSplitSetGearBySet then
                for _, mi in ipairs(members) do
                    if categories[mi] and categories[mi].isSetGear and not categories[mi].isEquipSet then
                        anchorMi = mi
                        break
                    end
                end
                if anchorMi then
                    childSet = {}
                    for i, c in ipairs(categories) do
                        if c.isEquipSet then
                            childSet[i] = true
                        end
                    end
                end
            end
            for _, payload in ipairs(displayItems) do
                local ci = payload.categoryIndex
                if ci and itemsByMember[ci] then
                    itemsByMember[ci][#itemsByMember[ci] + 1] = payload
                elseif ci and childSet and childSet[ci] then
                    itemsByMember[anchorMi][#itemsByMember[anchorMi] + 1] = payload
                end
            end

            local hideEmpty = BP().bagHideEmptyCategories ~= false
            for _, mi in ipairs(members) do
                local memberCat = categories[mi]
                local memberItems = itemsByMember[mi] or {}
                if not (hideEmpty and #memberItems == 0) then
                    if #memberItems > 0 then
                        PreCacheSortFields(memberItems)
                        table.sort(memberItems, VisualSortCompare)
                        memberItems = MergeDuplicates(memberItems)
                    end

                    if compact then
                        local aKey = CUI_CategoryManager:CanAssignToCategory(mi)
                                and memberCat
                                and memberCat._defaultName
                            or nil
                        mod.CompactBagsSection(
                            memberCat and memberCat.name or "?",
                            memberItems,
                            useSlotNest and "slot" or "flat",
                            aKey
                        )
                    else
                        headerIndex = headerIndex + 1
                        local heading = GetOrCreateCatHeader(headerIndex)
                        heading:SetParent(childFrame)
                        heading:ClearAllPoints()
                        heading:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, nextY)
                        heading:SetWidth(gridW)
                        heading._label:SetText(
                            (memberCat and memberCat.name or "?") .. " (" .. #memberItems .. ")"
                        )
                        heading:Show()
                        nextY = nextY - 22

                        if useSlotNest and #memberItems > 0 then
                            local bucketList = BuildSlotBuckets(memberItems)
                            local showAssign = CUI_CategoryManager
                                and CUI_CategoryManager:CanAssignToCategory(mi)
                            expSubIdx = RenderSlotBuckets(
                                bucketList,
                                expSubIdx,
                                showAssign and memberCat and memberCat._defaultName
                            )
                        else
                            for jdx, payload in ipairs(memberItems) do
                                slotIndex = slotIndex + 1
                                local button = GetOrCreateSlot(slotIndex)
                                if button then
                                    button:GetParent():SetParent(childFrame)
                                    local colour = (jdx - 1) % colCount
                                    local row = math.floor((jdx - 1) / colCount)
                                    RenderButton(button, payload, slotIndex, colour, row, startX, nextY, colCount)
                                end
                            end

                            -- Assign "+" per member sub-section in group view
                            local memberItemCount = #memberItems
                            if CUI_CategoryManager and CUI_CategoryManager:CanAssignToCategory(mi) then
                                local aIdx = memberItemCount + 1
                                slotIndex = slotIndex + 1
                                local aSlot = GetOrCreateSlot(slotIndex)
                                if aSlot then -- nil during combat (avoids minting tainted secure buttons)
                                    aSlot:GetParent():SetParent(childFrame)
                                    local colour = (aIdx - 1) % colCount
                                    local row = math.floor((aIdx - 1) / colCount)
                                    RenderButton(
                                        aSlot,
                                        { bag = 0, slot = 0 },
                                        slotIndex,
                                        colour,
                                        row,
                                        startX,
                                        nextY,
                                        colCount
                                    )
                                    local addOverlay = GetOrCreateAssignOverlay()
                                    addOverlay._assignCatKey = memberCat._defaultName
                                    addOverlay:SetParent(childFrame)
                                    addOverlay:ClearAllPoints()
                                    addOverlay:SetAllPoints(aSlot)
                                    addOverlay:Show()
                                    memberItemCount = memberItemCount + 1
                                end
                            end

                            local leftover = memberItemCount % colCount
                            local padSlots
                            if memberItemCount == 0 then
                                padSlots = colCount
                            elseif leftover == 0 then
                                padSlots = 0
                            else
                                padSlots = colCount - leftover
                            end
                            -- Cosmetic filler pads -- never clamp to free bag slots (see above).
                            if padSlots > 0 then
                                RenderEmptyPad(memberItemCount, padSlots)
                            end

                            local totalInSection = memberItemCount + math.max(padSlots, 0)
                            local sectionRows = math.ceil(totalInSection / colCount)
                            nextY = nextY - (sectionRows * (SLOT_SIZE + SPACING)) - 6
                        end -- slot nest vs flat grid
                    end -- compact vs grid
                end -- hideEmpty guard
            end
        else
            -- Single category view: header + flat grid with empty padding
            local categories = CUI_CategoryManager:GetCategories()
            local selectedCat = categories[selectedCategoryIndex]
            if #displayItems > 0 then
                if not (selectedCat and selectedCat.isRecent) then
                    PreCacheSortFields(displayItems)
                    table.sort(displayItems, VisualSortCompare)
                end
                displayItems = MergeDuplicates(displayItems)
                if selectedCat and selectedCat.isRecent then
                    table.sort(displayItems, RecentCompare)
                end
            end
            local headerName = selectedCat and selectedCat.name
            if headerName then
                local headerIndex = 1
                local heading = GetOrCreateCatHeader(headerIndex)

                -- "Edit | Delete" links for user-created categories
                if not heading._editDeleteFrame then
                    local editFrame = CreateFrame("Frame", nil, childFrame)
                    editFrame:SetHeight(16)
                    editFrame:SetFrameLevel((heading:GetFrameLevel() or 1) + 1)

                    local deleteBtn = CreateFrame("Button", nil, editFrame)
                    deleteBtn:SetHeight(20)
                    deleteBtn._fs = deleteBtn:CreateFontString(nil, "OVERLAY")
                    SetBagFont(deleteBtn._fs, 10)
                    deleteBtn._fs:SetPoint("RIGHT", editFrame, "RIGHT", 0, 0)
                    deleteBtn._fs:SetText(CludesUI.L("Delete"))
                    deleteBtn._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    deleteBtn:SetWidth(deleteBtn._fs:GetStringWidth() + 4)
                    deleteBtn:SetAllPoints(deleteBtn._fs)
                    deleteBtn:SetScript("OnEnter", function(cfg)
                        cfg._fs:SetTextColor(1, 0.3, 0.3, 1)
                    end)
                    deleteBtn:SetScript("OnLeave", function(cfg)
                        cfg._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    end)
                    deleteBtn:SetScript("OnClick", function()
                        local ci = mod.GetSelection()
                        if ci and ci > 0 and CUI_CategoryManager then
                            CUI:ShowConfirmPopup({
                                title = "Delete Category",
                                message = CludesUI.L(
                                    "Are you sure you want to delete this category? All item assignments will be removed."
                                ),
                                confirmText = "Delete",
                                cancelText = "Cancel",
                                onConfirm = function()
                                    CUI_CategoryManager:RemoveCustomCategory(ci)
                                    mod.SetSelection(0, nil)
                                    CUI_Bags:RefreshInventory()
                                end,
                            })
                        end
                    end)
                    editFrame._delBtn = deleteBtn

                    local divider = editFrame:CreateFontString(nil, "OVERLAY")
                    SetBagFont(divider, 10)
                    divider:SetPoint("RIGHT", deleteBtn._fs, "LEFT", -6, 0)
                    divider:SetText("|")
                    divider:SetTextColor(0.3, 0.3, 0.3, 0.7)
                    editFrame._divider = divider

                    local editButton = CreateFrame("Button", nil, editFrame)
                    editButton:SetHeight(20)
                    editButton._fs = editButton:CreateFontString(nil, "OVERLAY")
                    SetBagFont(editButton._fs, 10)
                    editButton._fs:SetPoint("RIGHT", divider, "LEFT", -6, 0)
                    editButton._fs:SetText(CludesUI.L("Edit"))
                    editButton._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    editButton:SetWidth(editButton._fs:GetStringWidth() + 4)
                    editButton:SetAllPoints(editButton._fs)
                    editButton:SetScript("OnEnter", function(cfg)
                        cfg._fs:SetTextColor(1, 1, 1, 1)
                    end)
                    editButton:SetScript("OnLeave", function(cfg)
                        cfg._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    end)
                    editButton:SetScript("OnClick", function()
                        local ci = mod.GetSelection()
                        if ci and ci > 0 and CUI_CategoryManager and CUI then
                            local cats2 = CUI_CategoryManager:GetCategories()
                            local cat2 = cats2[ci]
                            if not cat2 then
                                return
                            end
                            CUI:ShowInputPopup({
                                title = "Rename Category",
                                message = CludesUI.L("Enter a new name:"),
                                placeholder = cat2.name,
                                confirmText = "Rename",
                                cancelText = "Cancel",
                                onConfirm = function(textValue)
                                    if textValue and textValue ~= "" then
                                        CUI_CategoryManager:RenameCategory(ci, textValue)
                                        CUI_Bags:RefreshInventory()
                                    end
                                end,
                            })
                        end
                    end)
                    editFrame._editBtn = editButton

                    editFrame:SetWidth(60)
                    heading._editDeleteFrame = editFrame
                end

                -- Position Edit | Delete above the header, then the header below
                if selectedCat and selectedCat.isUserCreated then
                    local editFrame = heading._editDeleteFrame
                    editFrame:SetParent(childFrame)
                    editFrame:ClearAllPoints()
                    editFrame:SetPoint("TOPRIGHT", childFrame, "TOPLEFT", startX + gridW, nextY)
                    editFrame:SetWidth(gridW)
                    editFrame:Show()
                    nextY = nextY - 18
                elseif heading._editDeleteFrame then
                    heading._editDeleteFrame:Hide()
                end

                -- Compact draws the name as the group's label instead
                if not compact then
                    heading:SetParent(childFrame)
                    heading:ClearAllPoints()
                    heading:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, nextY)
                    heading:SetWidth(gridW)
                    heading._label:SetText(headerName .. " (" .. #displayItems .. ")")
                    -- Pinned / Recent: their hint shows while the label is hovered
                    if selectedCat and selectedCat.isPinned then
                        mod.SetHeaderHint(heading, CludesUI.L("Middle Click to Add or Remove"))
                    elseif selectedCat and selectedCat.isRecent then
                        mod.SetHeaderHint(
                            heading,
                            CludesUI.L("Extra quickview display, your items are also in their category")
                        )
                    end
                    heading:Show()
                    nextY = nextY - 22
                end -- grid header
            end

            local itemTotal = #displayItems
            local useSlotNest = armorySlotGrouping
                and selectedCat
                and IsArmoryGearCategory(selectedCat)
                and itemTotal > 0

            if compact then
                local aKey
                if
                    useSlotNest
                    and selectedCategoryIndex > 0
                    and CUI_CategoryManager:CanAssignToCategory(selectedCategoryIndex)
                then
                    aKey = selectedCat._defaultName
                end
                -- The grid header's Pinned / Recent hint, on the label's hover
                local hint
                if selectedCat and selectedCat.isPinned then
                    hint = CludesUI.L("Middle Click to Add or Remove")
                elseif selectedCat and selectedCat.isRecent then
                    hint = CludesUI.L("Extra quickview display, your items are also in their category")
                end
                mod.CompactBagsSection(
                    headerName or "",
                    displayItems,
                    useSlotNest and "slot" or "flat",
                    aKey,
                    true,
                    hint
                )
            elseif useSlotNest then
                local expSubIdx = 0
                local bucketList = BuildSlotBuckets(displayItems)
                local showAssign = selectedCategoryIndex > 0
                    and CUI_CategoryManager
                    and CUI_CategoryManager:CanAssignToCategory(selectedCategoryIndex)
                expSubIdx =
                    RenderSlotBuckets(bucketList, expSubIdx, showAssign and selectedCat and selectedCat._defaultName)
            else
                for i, payload in ipairs(displayItems) do
                    slotIndex = slotIndex + 1
                    local button = GetOrCreateSlot(slotIndex)
                    if button then
                        button:GetParent():SetParent(childFrame)
                        local colour = (i - 1) % colCount
                        local row = math.floor((i - 1) / colCount)
                        RenderButton(button, payload, slotIndex, colour, row, startX, nextY, colCount)
                    end
                end

                local leftover = itemTotal % colCount
                local padSlots
                if itemTotal == 0 then
                    padSlots = colCount
                elseif leftover == 0 then
                    padSlots = 0
                else
                    padSlots = colCount - leftover
                end
                -- Cosmetic filler pads -- never clamp to free bag slots (see above).
                if padSlots > 0 then
                    RenderEmptyPad(itemTotal, padSlots)
                end

                local totalItems = itemTotal + math.max(padSlots, 0)
                local gridRows = math.ceil(totalItems / colCount)
                nextY = nextY - (gridRows * (SLOT_SIZE + SPACING))
            end -- slot nest vs flat grid
        end
    end

    -- Compact: pack and draw the groups this pass collected
    if compact then
        slotIndex, nextY = mod.CompactBagsPlace(childFrame, startX, nextY, colCount, slotIndex)
    end

    -- Hide slots that were not rendered this pass
    for i = slotIndex + 1, #itemSlots do
        local button = itemSlots[i]
        if button then
            button:GetParent():Hide()
        end
    end
    return nextY
end
