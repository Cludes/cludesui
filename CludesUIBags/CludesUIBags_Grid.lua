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
local compactOn = false
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
    local p = BP()
    local quality = details.quality or 1
    SetItemButtonDesaturated(
        button,
        details.isLocked or (p.bagDesaturateJunkItems == true and (quality == 0 or markerJunk)) or false
    )
    if markerJunk and p.bagShowJunkCoin == true then
        local coin = button._junkCoin
        if not coin then
            coin = button:CreateTexture(nil, "OVERLAY", nil, 6)
            coin:SetTexture(mod.JUNK_COIN)
            coin:SetTexCoord(0.12, 0.88, 0.12, 0.88)
            local maskTex = button:CreateMaskTexture()
            maskTex:SetTexture(
                "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
                "CLAMPTOBLACKADDITIVE",
                "CLAMPTOBLACKADDITIVE"
            )
            maskTex:SetAllPoints(coin)
            coin:AddMaskTexture(maskTex)
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
local function RenderButton(button, payload, _, column, rowFrame, startX, currentY, _, interactiveEmpties)
    local hostFrame = button:GetParent()
    hostFrame:ClearAllPoints()
    hostFrame:SetPoint(
        "TOPLEFT",
        startX + (column * (SLOT_SIZE + SPACING)),
        currentY - (rowFrame * (SLOT_SIZE + SPACING))
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
                    local r, g, b
                    local rankText = payload._giTrackRank or ""
                    local trackColor = payload._giTrackColor
                    if BP().itemlevelUseCustomColor and BP().itemlevelCustomColor then
                        r, g, b =
                            BP().itemlevelCustomColor.r,
                            BP().itemlevelCustomColor.g,
                            BP().itemlevelCustomColor.b
                    elseif trackColor then
                        r, g, b = trackColor.r, trackColor.g, trackColor.b
                    else
                        r, g, b = GetItemQualityColor(payload._giQuality or 1)
                    end
                    button.ItemLevelText:SetTextColor(r, g, b, 1)
                    local countFS = button.Count
                    if countFS and BP().bagShowTrackRank and rankText ~= "" then
                        countFS:SetText(rankText:match("^(%d+)/") or rankText)
                        countFS:SetTextColor(r, g, b, 1)
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
            local r, g, b = QualityBorderColor(quality)
            SetInsetBorderColor(button, r, g, b, 1)
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
            local r, g, b = QualityBorderColor(quality)
            SetInsetBorderColor(button, r, g, b, filtered and 0.2 or 1)
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
            local dim = dimFrame:CreateTexture(nil, "OVERLAY")
            dim:SetAllPoints()
            dim:SetColorTexture(0, 0, 0, 0.75)
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
    local hb = heading._hideBtn
    if hb then
        return hb
    end
    hb = CreateFrame("Button", nil, heading)
    hb:SetSize(30, 16)
    hb._fs = hb:CreateFontString(nil, "OVERLAY")
    SetBagFont(hb._fs, 9)
    hb._fs:SetAllPoints()
    hb._fs:SetText(CludesUI.L("Hide"))
    hb._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
    hb:SetScript("OnEnter", function(self)
        self._fs:SetTextColor(1, 1, 1, 0.9)
        CUI.ShowWidgetTooltip(self, self._tooltip)
    end)
    hb:SetScript("OnLeave", function(self)
        self._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
        CUI.HideWidgetTooltip()
    end)
    hb:SetScript("OnClick", function(self)
        BP()[self._dbKey] = false
        CUI_Bags:RefreshInventory()
    end)
    heading._hideBtn = hb
    return hb
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
    columns,
    gridW,
    gridPadX,
    showPinned,
    pinnedSet
)
    local selectedCategoryIndex, selectedGroupName = mod.GetSelection()
    junkOn = CUI_CategoryManager:IsJunkMarkerEnabled()
    compactOn = CUI_Bags.IsCompactMode() == true

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
    local curY = -6
    local slotIdx = 0
    if compactOn then
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
        local f = CreateFrame("Frame", nil, CUI_Bags)
        mod.SizeSlot(f)
        f:EnableMouse(false)
        f._bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f._bg:SetAllPoints()
        mod.SetSlotBackgroundTexture(f._bg, false)
        f._bg:SetAlpha(0.35)
        CreateInsetBorder(f, true)
        SetInsetBorderColor(f, 0, 0, 0, 0.3)
        _emptyPads[position] = f
        return f
    end

    local function RenderEmptyPad(itemCount, padCount)
        for p = 1, padCount do
            _emptyPadIdx = _emptyPadIdx + 1
            local pad = GetOrCreateEmptyPad(_emptyPadIdx)
            pad:SetParent(childFrame)
            pad:ClearAllPoints()
            local totalIdx = itemCount + p
            local column = (totalIdx - 1) % columns
            local rowFrame = math.floor((totalIdx - 1) / columns)
            pad:SetPoint(
                "TOPLEFT",
                startX + (column * (SLOT_SIZE + SPACING)),
                curY - (rowFrame * (SLOT_SIZE + SPACING))
            )
            mod.PaintSlotBackground(pad._bg, 0.35)
            pad:Show()
        end
    end

    local function RenderItemBlock(blockItems)
        local num = #blockItems
        for jdx, payload in ipairs(blockItems) do
            slotIdx = slotIdx + 1
            local button = GetOrCreateSlot(slotIdx)
            if button then -- nil during combat (avoids minting tainted secure buttons)
                button:GetParent():SetParent(childFrame)
                local column = (jdx - 1) % columns
                local rowFrame = math.floor((jdx - 1) / columns)
                RenderButton(button, payload, slotIdx, column, rowFrame, startX, curY, columns)
            end
        end
        local remainder = num % columns
        local padCount
        if num == 0 then
            padCount = columns
        elseif remainder == 0 then
            padCount = 0
        else
            padCount = columns - remainder
        end
        -- Filler pads are cosmetic row-fillers (the "+" button is the only real slot); NEVER clamp to #emptySlots or they vanish when bags are full.
        if padCount > 0 then
            RenderEmptyPad(num, padCount)
        end
        local totalInBlock = num + math.max(padCount, 0)
        local blockRows = math.ceil(totalInBlock / columns)
        curY = curY - (blockRows * (SLOT_SIZE + SPACING))
    end

    -- Compact Armory layout. Reuses the existing slot, sub-header, empty-pad,
    -- and assignment pools; only the coordinates differ from the full-row path.
    local armorySlotGrouping = ArmorySlotGroupingEnabled()
    local RenderCompactSlotBuckets
    if not compactOn and BP().bagCompactArmorySlotGroups and armorySlotGrouping then
        RenderCompactSlotBuckets = function(buckets, subHeaderIdx, assignCatKey)
            local stride = SLOT_SIZE + SPACING
            local usableWidth = columns * stride - SPACING
            local headerGap = 18
            local epsilon = 0.5
            local categoryGap = math.max(8, SPACING * 3)
            local assignBucket = assignCatKey and buckets[1] and 1 or nil

            -- Prepare the headers first so their text widths can reserve enough
            -- horizontal space before the buckets are packed into rows.
            for slotPos, bucket in ipairs(buckets) do
                subHeaderIdx = subHeaderIdx + 1
                local headerFrame = GetOrCreateExpSubHeader(subHeaderIdx)
                headerFrame:SetParent(childFrame)
                headerFrame._label:SetText(bucket.label .. " (" .. #bucket.items .. ")")
                SetBagFont(headerFrame._label, math.max(8, catTitleSize - 2))

                local itemCount = #bucket.items + ((slotPos == assignBucket) and 1 or 0)
                local span = math.min(columns, itemCount)
                local bucketWidth = span * stride - SPACING
                bucket._compactHeader = headerFrame
                bucket._compactItemCount = itemCount
                bucket._compactSpan = span
                bucket._compactRows = math.ceil(itemCount / span)
                bucket._compactWidth = bucketWidth

                if itemCount <= columns then
                    categoryGap =
                        math.max(categoryGap, (headerFrame._label:GetStringWidth() or 0) + 6 - bucketWidth)
                end
            end

            local function RenderPadsAt(itemTop, usedWidth)
                local padCount = math.floor((usableWidth - usedWidth + epsilon) / stride)
                for slotPos = 1, padCount do
                    _emptyPadIdx = _emptyPadIdx + 1
                    local pad = GetOrCreateEmptyPad(_emptyPadIdx)
                    pad:SetParent(childFrame)
                    pad:ClearAllPoints()
                    pad:SetPoint(
                        "TOPLEFT",
                        childFrame,
                        "TOPLEFT",
                        startX + usedWidth + SPACING + (slotPos - 1) * stride,
                        itemTop
                    )
                    mod.PaintSlotBackground(pad._bg, 0.35)
                    pad:Show()
                end
            end

            local rowTop = curY
            local usedWidth = 0
            local rowItemRows = 0

            for slotPos, bucket in ipairs(buckets) do
                local span = bucket._compactSpan
                local itemRows = bucket._compactRows
                local bucketWidth = bucket._compactWidth
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

                local headerFrame = bucket._compactHeader
                headerFrame:ClearAllPoints()
                headerFrame:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX + startOffset, rowTop)
                headerFrame:SetWidth(math.max(1, bucketWidth))
                headerFrame:Show()

                for itemIndex, payload in ipairs(bucket.items) do
                    slotIdx = slotIdx + 1
                    local button = GetOrCreateSlot(slotIdx)
                    if button then
                        button:GetParent():SetParent(childFrame)
                        local column = (itemIndex - 1) % span
                        local rowFrame = math.floor((itemIndex - 1) / span)
                        RenderButton(
                            button,
                            payload,
                            slotIdx,
                            column,
                            rowFrame,
                            startX + startOffset,
                            rowTop - headerGap,
                            columns
                        )
                    end
                end

                if slotPos == assignBucket then
                    slotIdx = slotIdx + 1
                    local assignSlot = GetOrCreateSlot(slotIdx)
                    if assignSlot then
                        assignSlot:GetParent():SetParent(childFrame)
                        local itemIndex = #bucket.items + 1
                        local column = (itemIndex - 1) % span
                        local rowFrame = math.floor((itemIndex - 1) / span)
                        RenderButton(
                            assignSlot,
                            { bag = 0, slot = 0 },
                            slotIdx,
                            column,
                            rowFrame,
                            startX + startOffset,
                            rowTop - headerGap,
                            columns
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
                    local remainder = bucket._compactItemCount % columns
                    if remainder > 0 then
                        local lastRowWidth = remainder * stride - SPACING
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

            curY = rowTop - 6
            return subHeaderIdx
        end
    end

    local RenderSlotBuckets
    if armorySlotGrouping and not compactOn then
        RenderSlotBuckets = function(buckets, subHeaderIdx, assignCatKey)
            if RenderCompactSlotBuckets then
                return RenderCompactSlotBuckets(buckets, subHeaderIdx, assignCatKey)
            end

            local assignShown = false
            for _, bucket in ipairs(buckets) do
                if #bucket.items > 0 then
                    subHeaderIdx = subHeaderIdx + 1
                    local headerFrame = GetOrCreateExpSubHeader(subHeaderIdx)
                    headerFrame:SetParent(childFrame)
                    headerFrame:ClearAllPoints()
                    headerFrame:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, curY)
                    headerFrame:SetWidth(gridW)
                    headerFrame._label:SetText(bucket.label .. " (" .. #bucket.items .. ")")
                    SetBagFont(headerFrame._label, math.max(8, catTitleSize - 2))
                    headerFrame:Show()
                    curY = curY - 18
                    RenderItemBlock(bucket.items)

                    if assignCatKey and not assignShown then
                        assignShown = true
                        local remainder = #bucket.items % columns
                        if remainder ~= 0 then
                            curY = curY + (SLOT_SIZE + SPACING)
                        end
                        slotIdx = slotIdx + 1
                        local assignSlot = GetOrCreateSlot(slotIdx)
                        if assignSlot then
                            assignSlot:GetParent():SetParent(childFrame)
                            RenderButton(
                                assignSlot,
                                { bag = 0, slot = 0 },
                                slotIdx,
                                remainder,
                                0,
                                startX,
                                curY,
                                columns
                            )
                            local overlayFrame = GetOrCreateAssignOverlay()
                            overlayFrame._assignCatKey = assignCatKey
                            overlayFrame:SetParent(childFrame)
                            overlayFrame:ClearAllPoints()
                            overlayFrame:SetAllPoints(assignSlot)
                            overlayFrame:Show()
                        end
                        curY = curY - (SLOT_SIZE + SPACING)
                    end
                end
            end
            curY = curY - 6
            return subHeaderIdx
        end
    end

    if selectedCategoryIndex == -1 or selectedCategoryIndex == -2 then
        -- OneBag/MultiBag: Pinned Items (display-only) + bag section(s) + Reagent Bag. OneBag
        -- merges bags 0-4 into one "Main Bags" section, MultiBag renders one per bag; reuses tempItems + emptySlots instead of re-querying bags.
        local headerIdx = 0
        local isMulti = (selectedCategoryIndex == -2)

        -- Pinned Items quickview (display-only duplicates)
        local showPinnedOneBag = (BP().bagPinnedInOneBag ~= false) and showPinned
        if showPinnedOneBag then
            local pinItems = {}
            if pinnedSet then
                for _, d in ipairs(tempItems) do
                    if d.info and d.info.itemID and IsItemPinned(pinnedSet, d.itemLink, d.info.itemID) then
                        pinItems[#pinItems + 1] = d
                    end
                end
            end
            if #pinItems > 0 then
                pinItems = MergeDuplicates(pinItems)
            end
            if compactOn then
                mod.CompactBagsSection(CludesUI.L("Pinned Items"), pinItems, "pinned")
            else
                headerIdx = headerIdx + 1
                local pinHdr = GetOrCreateCatHeader(headerIdx)
                pinHdr:SetParent(childFrame)
                pinHdr:ClearAllPoints()
                pinHdr:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, curY)
                pinHdr:SetWidth(columns * (SLOT_SIZE + SPACING))
                pinHdr._label:SetText(CludesUI.L("Pinned Items"))
                mod.SetHeaderHint(pinHdr, CludesUI.L("Middle Click to Add or Remove"))
                local pinHide = GetHeaderHideButton(pinHdr)
                pinHide._dbKey = "bagPinnedInOneBag"
                pinHide._tooltip = "Hides Pinned Items. Re-show in settings."
                pinHdr._hideBtn:ClearAllPoints()
                pinHdr._hideBtn:SetPoint("RIGHT", pinHdr, "RIGHT", 0, 0)
                pinHdr._hideBtn:Show()
                pinHdr._line:ClearAllPoints()
                pinHdr._line:SetPoint("LEFT", pinHdr._hint, "RIGHT", 6, 0)
                pinHdr._line:SetPoint("RIGHT", pinHdr._hideBtn, "LEFT", -6, 0)
                pinHdr:Show()
                curY = curY - 22

                for jdx, payload in ipairs(pinItems) do
                    slotIdx = slotIdx + 1
                    local button = GetOrCreateSlot(slotIdx)
                    if button then -- nil during combat (avoids minting tainted secure buttons)
                        button:GetParent():SetParent(childFrame)
                        local column = (jdx - 1) % columns
                        local rowFrame = math.floor((jdx - 1) / columns)
                        RenderButton(button, payload, slotIdx, column, rowFrame, startX, curY, columns)
                    end
                end
                local pinItemCount = #pinItems
                do
                    local pinIdx = pinItemCount + 1
                    slotIdx = slotIdx + 1
                    local pinSlot = GetOrCreateSlot(slotIdx)
                    if pinSlot then -- nil during combat (avoids minting tainted secure buttons)
                        pinSlot:GetParent():SetParent(childFrame)
                        local column = (pinIdx - 1) % columns
                        local rowFrame = math.floor((pinIdx - 1) / columns)
                        RenderButton(
                            pinSlot,
                            { bag = 0, slot = 0 },
                            slotIdx,
                            column,
                            rowFrame,
                            startX,
                            curY,
                            columns
                        )
                        local shade = GetOrCreatePinOverlay()
                        shade:SetParent(childFrame)
                        shade:ClearAllPoints()
                        shade:SetAllPoints(pinSlot)
                        shade:Show()
                        pinItemCount = pinItemCount + 1
                    end
                end
                -- Pad remaining slots in last row
                local pinRemainder = pinItemCount % columns
                local pinPadCount = pinRemainder == 0 and 0 or (columns - pinRemainder)
                if pinItemCount == 0 then
                    pinPadCount = columns
                end
                if pinPadCount > 0 then
                    RenderEmptyPad(pinItemCount, pinPadCount)
                end
                local pinTotal = pinItemCount + pinPadCount
                local pinRows = math.ceil(pinTotal / columns)
                curY = curY - (pinRows * (SLOT_SIZE + SPACING)) - 6
            end -- compact vs grid
        end

        -- Recent Items quickview (display-only duplicates)
        local showRecentOneBag = BP().bagRecentInOneBag == true
        local showRecent = BP().bagShowRecentItems ~= false
        if showRecentOneBag and showRecent then
            local recentItems = {}
            if CUI_Bags._recentItems then
                for _, d in ipairs(tempItems) do
                    if
                        not d._pinnedOnly
                        and d.info
                        and d.info.itemID
                        and CUI_Bags._recentItems[d.info.itemID]
                    then
                        recentItems[#recentItems + 1] = d
                    end
                end
            end
            if #recentItems > 0 then
                recentItems = MergeDuplicates(recentItems)
                table.sort(recentItems, RecentCompare)
            end
            if compactOn then
                mod.CompactBagsSection(CludesUI.L("Recent Items"), recentItems, "recent")
            else
                headerIdx = headerIdx + 1
                local recHdr = GetOrCreateCatHeader(headerIdx)
                recHdr:SetParent(childFrame)
                recHdr:ClearAllPoints()
                recHdr:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, curY)
                recHdr:SetWidth(columns * (SLOT_SIZE + SPACING))
                recHdr._label:SetText(CludesUI.L("Recent Items"))
                mod.SetHeaderHint(
                    recHdr,
                    CludesUI.L("Extra quickview display, your items are also in their category")
                )
                local recHide = GetHeaderHideButton(recHdr)
                recHide._dbKey = "bagRecentInOneBag"
                recHide._tooltip = "Hides Recent Items. Re-show in settings."
                recHdr._hideBtn:ClearAllPoints()
                recHdr._hideBtn:SetPoint("RIGHT", recHdr, "RIGHT", 0, 0)
                recHdr._hideBtn:Show()
                local recLineAnchor = recHdr._hideBtn
                if
                    BP().bagShowRecentClear == true
                    and CUI_Bags._recentItems
                    and next(CUI_Bags._recentItems)
                then
                    recLineAnchor = ShowRecentClearButton(recHdr, recHdr._hideBtn)
                end
                recHdr._line:ClearAllPoints()
                recHdr._line:SetPoint("LEFT", recHdr._hint, "RIGHT", 6, 0)
                recHdr._line:SetPoint("RIGHT", recLineAnchor, "LEFT", -6, 0)
                recHdr:Show()
                curY = curY - 22

                for jdx, payload in ipairs(recentItems) do
                    slotIdx = slotIdx + 1
                    local button = GetOrCreateSlot(slotIdx)
                    if button then -- nil during combat (avoids minting tainted secure buttons)
                        button:GetParent():SetParent(childFrame)
                        local column = (jdx - 1) % columns
                        local rowFrame = math.floor((jdx - 1) / columns)
                        RenderButton(button, payload, slotIdx, column, rowFrame, startX, curY, columns)
                    end
                end
                local recItemCount = #recentItems
                local recRemainder = recItemCount % columns
                local recPadCount = recRemainder == 0 and 0 or (columns - recRemainder)
                if recItemCount == 0 then
                    recPadCount = columns
                end
                if recPadCount > 0 then
                    RenderEmptyPad(recItemCount, recPadCount)
                end
                local recTotal = recItemCount + recPadCount
                local recRows = math.ceil(recTotal / columns)
                curY = curY - (recRows * (SLOT_SIZE + SPACING)) - 6
            end -- compact vs grid
        end

        -- One section header + item grid for a slot list, advancing the shared
        -- curY/slotIdx/headerIdx upvalues (used by OneBag's "Main Bags" and MultiBag's per-bag sections).
        local function RenderBagGrid(labelText, slotList)
            if #slotList == 0 then
                return
            end
            if compactOn then
                mod.CompactBagsSlots(labelText, slotList)
                return
            end
            headerIdx = headerIdx + 1
            local heading = GetOrCreateCatHeader(headerIdx)
            heading:SetParent(childFrame)
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, curY)
            heading:SetWidth(columns * (SLOT_SIZE + SPACING))
            heading._label:SetText(labelText)
            heading:Show()
            curY = curY - 22
            for i, payload in ipairs(slotList) do
                slotIdx = slotIdx + 1
                local button = GetOrCreateSlot(slotIdx)
                if button then -- nil during combat (avoids minting tainted secure buttons)
                    button:GetParent():SetParent(childFrame)
                    local column = (i - 1) % columns
                    local rowFrame = math.floor((i - 1) / columns)
                    RenderButton(button, payload, slotIdx, column, rowFrame, startX, curY, columns, true)
                end
            end
            local rowList = math.ceil(#slotList / columns)
            curY = curY - (rowList * (SLOT_SIZE + SPACING)) - 6
        end

        -- One bag's items + empties as a section titled with the bag's name, in
        -- slot order (MultiBag's bags, OneBag's special bags).
        local BagDisplayName = mod.BagDisplayName
        local function RenderOneBag(bag)
            local bagList = {}
            local bagFilled = 0
            for _, d in ipairs(tempItems) do
                if d.bag == bag then
                    bagList[#bagList + 1] = d
                    bagFilled = bagFilled + 1
                end
            end
            for _, d in ipairs(emptySlots) do
                if d.bag == bag then
                    bagList[#bagList + 1] = d
                end
            end
            if #bagList > 0 then
                table.sort(bagList, function(a, b)
                    return a.slot < b.slot
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
            for _, d in ipairs(tempItems) do
                if d.bag ~= 5 and not (special and special[d.bag]) then
                    mainSlots[#mainSlots + 1] = d
                    mainFilled = mainFilled + 1
                end
            end
            for _, d in ipairs(emptySlots) do
                if d.bag ~= 5 and not (special and special[d.bag]) then
                    mainSlots[#mainSlots + 1] = d
                end
            end
            table.sort(mainSlots, function(a, b)
                if a.bag ~= b.bag then
                    return a.bag < b.bag
                end
                return a.slot < b.slot
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
        for _, d in ipairs(tempItems) do
            if d.bag == 5 then
                reagentSlotList[#reagentSlotList + 1] = d
            end
        end
        for _, d in ipairs(emptySlots) do
            if d.bag == 5 then
                reagentSlotList[#reagentSlotList + 1] = d
            end
        end
        table.sort(reagentSlotList, function(a, b)
            return a.slot < b.slot
        end)

        if #reagentSlotList > 0 then
            local reagFilled = 0
            for _, d in ipairs(reagentSlotList) do
                if d.info then
                    reagFilled = reagFilled + 1
                end
            end
            local reagLabel = CludesUI.Lf("Reagent Bag (%d / %d)", reagFilled, #reagentSlotList)
            if compactOn then
                mod.CompactBagsSlots(reagLabel, reagentSlotList)
            else
                headerIdx = headerIdx + 1
                local reagHdr = GetOrCreateCatHeader(headerIdx)
                reagHdr:SetParent(childFrame)
                reagHdr:ClearAllPoints()
                reagHdr:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, curY)
                reagHdr:SetWidth(columns * (SLOT_SIZE + SPACING))
                reagHdr._label:SetText(reagLabel)
                reagHdr:Show()
                curY = curY - 22

                for i, payload in ipairs(reagentSlotList) do
                    slotIdx = slotIdx + 1
                    local button = GetOrCreateSlot(slotIdx)
                    if button then -- nil during combat (avoids minting tainted secure buttons)
                        button:GetParent():SetParent(childFrame)
                        local column = (i - 1) % columns
                        local rowFrame = math.floor((i - 1) / columns)
                        RenderButton(button, payload, slotIdx, column, rowFrame, startX, curY, columns, true)
                    end
                end
                local reagRows = math.ceil(#reagentSlotList / columns)
                curY = curY - (reagRows * (SLOT_SIZE + SPACING))
            end -- compact vs grid
        end
    elseif selectedCategoryIndex == 0 and not selectedGroupName then
        -- "All Items" view: group by category with headers
        local cats = CUI_CategoryManager:GetCategories()
        local itemsByCat = {}
        for i = 1, #cats do
            itemsByCat[i] = {}
        end
        for _, payload in ipairs(displayItems) do
            local ci = payload.categoryIndex
            if ci and itemsByCat[ci] and not payload._pinnedOnly then
                itemsByCat[ci][#itemsByCat[ci] + 1] = payload
            end
        end
        for i = 1, #cats do
            if #itemsByCat[i] > 0 and not cats[i].groupName and not cats[i].isRecent then
                ApplySavedOrder(i, itemsByCat[i])
            end
        end
        -- Merge duplicates after ordering so first-in-visual-order wins
        for i = 1, #cats do
            if #itemsByCat[i] > 1 then
                itemsByCat[i] = MergeDuplicates(itemsByCat[i])
            end
        end

        -- Build render sections: ungrouped = individual, grouped = merged under group name
        local renderedGroups = {}
        local headerIdx = 0
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
            local itemCount = #sectionItems
            if itemCount == 0 and not isUserCreated and not showPinAdd and not alwaysShow then
                return
            end

            local useSlotNest = armorySlotGrouping
                and IsGearOnlyGroup(sectionName)
                and itemCount > 0
                and not showPinAdd
                and not alwaysShow

            local useExpNest = nestByExpansion
                and BP().bagNestByExpansion
                and not useSlotNest
                and itemCount > 0
                and not showPinAdd
                and not alwaysShow

            -- sectionName is the group's key; this is what the label shows
            local labelText = CUI_CategoryManager:GroupDisplayName(sectionName)

            -- Compact: the collector draws this section (CludesUIBags_Compact.lua)
            if compactOn then
                local assignKey
                if assignCatIdx and CUI_CategoryManager:CanAssignToCategory(assignCatIdx) then
                    local aCat = CUI_CategoryManager:GetCategories()[assignCatIdx]
                    assignKey = aCat and aCat._defaultName
                end
                local kindOf = (showPinAdd and "pinned")
                    or (alwaysShow and "recent")
                    or (useSlotNest and "slot")
                    or (useExpNest and "exp")
                    or "flat"
                mod.CompactBagsSection(labelText, sectionItems, kindOf, assignKey)
                return
            end

            headerIdx = headerIdx + 1
            local heading = GetOrCreateCatHeader(headerIdx)
            heading:SetParent(childFrame)
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, curY)
            heading:SetWidth(gridW)
            heading._label:SetText(labelText .. " (" .. itemCount .. ")")
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
            curY = curY - 22

            if useSlotNest then
                local buckets = BuildSlotBuckets(sectionItems)
                if #buckets > 0 then
                    local showAssign = assignCatIdx
                        and CUI_CategoryManager
                        and CUI_CategoryManager:CanAssignToCategory(assignCatIdx)
                    local cats = showAssign and CUI_CategoryManager:GetCategories()
                    local assignCat = cats and cats[assignCatIdx]
                    expSubIdx = RenderSlotBuckets(buckets, expSubIdx, assignCat and assignCat._defaultName)
                    return
                end
            end

            if useExpNest then
                local buckets = BuildExpansionBuckets(sectionItems)
                if #buckets > 0 then
                    local showAssign = assignCatIdx
                        and CUI_CategoryManager
                        and CUI_CategoryManager:CanAssignToCategory(assignCatIdx)
                    local assignShown = false
                    for _, buck in ipairs(buckets) do
                        if #buck.items > 0 then
                            expSubIdx = expSubIdx + 1
                            local sh = GetOrCreateExpSubHeader(expSubIdx)
                            sh:SetParent(childFrame)
                            sh:ClearAllPoints()
                            sh:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, curY)
                            sh:SetWidth(gridW)
                            sh._label:SetText(buck.label .. " (" .. #buck.items .. ")")
                            SetBagFont(sh._label, math.max(8, catTitleSize - 2))
                            sh:Show()
                            curY = curY - 18
                            RenderItemBlock(buck.items)
                            -- Place assign "+" after the first bucket's items (newest expansion)
                            if showAssign and not assignShown then
                                assignShown = true
                                local cats = CUI_CategoryManager:GetCategories()
                                local aCat = cats[assignCatIdx]
                                if aCat then
                                    -- RenderItemBlock already advanced curY; back up to place at the next slot after the items.
                                    local num = #buck.items
                                    local remainder = num % columns
                                    if remainder == 0 then
                                        -- Last row filled exactly: curY already sits on the new row the button needs.
                                    else
                                        -- Back up to the row the items are on
                                        curY = curY + (SLOT_SIZE + SPACING)
                                    end
                                    slotIdx = slotIdx + 1
                                    local aSlot = GetOrCreateSlot(slotIdx)
                                    if aSlot then
                                        aSlot:GetParent():SetParent(childFrame)
                                        local column = remainder
                                        RenderButton(
                                            aSlot,
                                            { bag = 0, slot = 0 },
                                            slotIdx,
                                            column,
                                            0,
                                            startX,
                                            curY,
                                            columns
                                        )
                                        local aOv = GetOrCreateAssignOverlay()
                                        aOv._assignCatKey = aCat._defaultName
                                        aOv:SetParent(childFrame)
                                        aOv:ClearAllPoints()
                                        aOv:SetAllPoints(aSlot)
                                        aOv:Show()
                                    end
                                    -- Re-advance curY for the row
                                    curY = curY - (SLOT_SIZE + SPACING)
                                end
                            end
                        end
                    end
                    curY = curY - 6
                    return
                end
            end

            for jdx, payload in ipairs(sectionItems) do
                slotIdx = slotIdx + 1
                local button = GetOrCreateSlot(slotIdx)
                if button then
                    button:GetParent():SetParent(childFrame)
                    local column = (jdx - 1) % columns
                    local rowFrame = math.floor((jdx - 1) / columns)
                    RenderButton(button, payload, slotIdx, column, rowFrame, startX, curY, columns)
                end
            end

            -- Pin "+" button: a regular empty slot with a "+" overlay on top
            if showPinAdd then
                local pinIdx = itemCount + 1
                slotIdx = slotIdx + 1
                local pinSlot = GetOrCreateSlot(slotIdx)
                if pinSlot then
                    pinSlot:GetParent():SetParent(childFrame)
                    local column = (pinIdx - 1) % columns
                    local rowFrame = math.floor((pinIdx - 1) / columns)
                    RenderButton(
                        pinSlot,
                        { bag = 0, slot = 0 },
                        slotIdx,
                        column,
                        rowFrame,
                        startX,
                        curY,
                        columns
                    )
                    local shade = GetOrCreatePinOverlay()
                    shade:SetParent(childFrame)
                    shade:ClearAllPoints()
                    shade:SetAllPoints(pinSlot)
                    shade:Show()
                    itemCount = itemCount + 1
                end
            end

            -- Assign "+" button: for categories that accept item assignments
            if
                assignCatIdx
                and CUI_CategoryManager
                and CUI_CategoryManager:CanAssignToCategory(assignCatIdx)
            then
                local cats = CUI_CategoryManager:GetCategories()
                local aCat = cats[assignCatIdx]
                if aCat then
                    local aIdx = itemCount + 1
                    slotIdx = slotIdx + 1
                    -- GetOrCreateSlot returns nil in combat lockdown (a slot born in combat is tainted); skip, PLAYER_REGEN_ENABLED replays the refresh.
                    local aSlot = GetOrCreateSlot(slotIdx)
                    if aSlot then
                        aSlot:GetParent():SetParent(childFrame)
                        local column = (aIdx - 1) % columns
                        local rowFrame = math.floor((aIdx - 1) / columns)
                        RenderButton(
                            aSlot,
                            { bag = 0, slot = 0 },
                            slotIdx,
                            column,
                            rowFrame,
                            startX,
                            curY,
                            columns
                        )
                        local aOv = GetOrCreateAssignOverlay()
                        aOv._assignCatKey = aCat._defaultName
                        aOv:SetParent(childFrame)
                        aOv:ClearAllPoints()
                        aOv:SetAllPoints(aSlot)
                        aOv:Show()
                        itemCount = itemCount + 1
                    end
                end
            end

            local remainder = itemCount % columns
            local padCount
            if itemCount == 0 then
                padCount = columns
            elseif remainder == 0 then
                padCount = 0
            else
                padCount = columns - remainder
            end
            -- Filler pads are cosmetic (the "+" assign/pin button is the only real slot); NEVER clamp to #emptySlots or they vanish when bags are full.
            if padCount > 0 then
                RenderEmptyPad(itemCount, padCount)
            end

            local totalInSection = itemCount + math.max(padCount, 0)
            local sectionRows = math.ceil(totalInSection / columns)
            curY = curY - (sectionRows * (SLOT_SIZE + SPACING)) - 6
        end

        local hiddenSet = BP().bagHiddenInAllItems or {}
        for ci, category in ipairs(cats) do
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
                    local recentItems = {}
                    for _, payload in ipairs(displayItems) do
                        if
                            not payload._pinnedOnly
                            and payload.info
                            and payload.info.itemID
                            and CUI_Bags._recentItems[payload.info.itemID]
                        then
                            recentItems[#recentItems + 1] = payload
                        end
                    end
                    if #recentItems > 0 then
                        recentItems = MergeDuplicates(recentItems)
                        table.sort(recentItems, RecentCompare)
                    end
                    RenderSection(CludesUI.L("Recent Items"), recentItems, false, false, true)
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
                                and cats[mi]
                                and cats[mi].isSetGear
                                and not cats[mi].isEquipSet
                            then
                                for i, c in ipairs(cats) do
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
                        for i, c in ipairs(cats) do
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
            local cats = CUI_CategoryManager:GetCategories()
            local members = CUI_CategoryManager:GetGroupMembers(selectedGroupName)
            local headerIdx = 0
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
                    if cats[mi] and cats[mi].isSetGear and not cats[mi].isEquipSet then
                        anchorMi = mi
                        break
                    end
                end
                if anchorMi then
                    childSet = {}
                    for i, c in ipairs(cats) do
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
                local memberCat = cats[mi]
                local memberItems = itemsByMember[mi] or {}
                if not (hideEmpty and #memberItems == 0) then
                    if #memberItems > 0 then
                        PreCacheSortFields(memberItems)
                        table.sort(memberItems, VisualSortCompare)
                        memberItems = MergeDuplicates(memberItems)
                    end

                    if compactOn then
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
                        headerIdx = headerIdx + 1
                        local heading = GetOrCreateCatHeader(headerIdx)
                        heading:SetParent(childFrame)
                        heading:ClearAllPoints()
                        heading:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, curY)
                        heading:SetWidth(gridW)
                        heading._label:SetText(
                            (memberCat and memberCat.name or "?") .. " (" .. #memberItems .. ")"
                        )
                        heading:Show()
                        curY = curY - 22

                        if useSlotNest and #memberItems > 0 then
                            local buckets = BuildSlotBuckets(memberItems)
                            local showAssign = CUI_CategoryManager
                                and CUI_CategoryManager:CanAssignToCategory(mi)
                            expSubIdx = RenderSlotBuckets(
                                buckets,
                                expSubIdx,
                                showAssign and memberCat and memberCat._defaultName
                            )
                        else
                            for jdx, payload in ipairs(memberItems) do
                                slotIdx = slotIdx + 1
                                local button = GetOrCreateSlot(slotIdx)
                                if button then
                                    button:GetParent():SetParent(childFrame)
                                    local column = (jdx - 1) % columns
                                    local rowFrame = math.floor((jdx - 1) / columns)
                                    RenderButton(
                                        button,
                                        payload,
                                        slotIdx,
                                        column,
                                        rowFrame,
                                        startX,
                                        curY,
                                        columns
                                    )
                                end
                            end

                            -- Assign "+" per member sub-section in group view
                            local memberItemCount = #memberItems
                            if CUI_CategoryManager and CUI_CategoryManager:CanAssignToCategory(mi) then
                                local aIdx = memberItemCount + 1
                                slotIdx = slotIdx + 1
                                local aSlot = GetOrCreateSlot(slotIdx)
                                if aSlot then -- nil during combat (avoids minting tainted secure buttons)
                                    aSlot:GetParent():SetParent(childFrame)
                                    local column = (aIdx - 1) % columns
                                    local rowFrame = math.floor((aIdx - 1) / columns)
                                    RenderButton(
                                        aSlot,
                                        { bag = 0, slot = 0 },
                                        slotIdx,
                                        column,
                                        rowFrame,
                                        startX,
                                        curY,
                                        columns
                                    )
                                    local aOv = GetOrCreateAssignOverlay()
                                    aOv._assignCatKey = memberCat._defaultName
                                    aOv:SetParent(childFrame)
                                    aOv:ClearAllPoints()
                                    aOv:SetAllPoints(aSlot)
                                    aOv:Show()
                                    memberItemCount = memberItemCount + 1
                                end
                            end

                            local remainder = memberItemCount % columns
                            local padCount
                            if memberItemCount == 0 then
                                padCount = columns
                            elseif remainder == 0 then
                                padCount = 0
                            else
                                padCount = columns - remainder
                            end
                            -- Cosmetic filler pads -- never clamp to free bag slots (see above).
                            if padCount > 0 then
                                RenderEmptyPad(memberItemCount, padCount)
                            end

                            local totalInSection = memberItemCount + math.max(padCount, 0)
                            local sectionRows = math.ceil(totalInSection / columns)
                            curY = curY - (sectionRows * (SLOT_SIZE + SPACING)) - 6
                        end -- slot nest vs flat grid
                    end -- compact vs grid
                end -- hideEmpty guard
            end
        else
            -- Single category view: header + flat grid with empty padding
            local cats = CUI_CategoryManager:GetCategories()
            local selCat = cats[selectedCategoryIndex]
            if #displayItems > 0 then
                if not (selCat and selCat.isRecent) then
                    PreCacheSortFields(displayItems)
                    table.sort(displayItems, VisualSortCompare)
                end
                displayItems = MergeDuplicates(displayItems)
                if selCat and selCat.isRecent then
                    table.sort(displayItems, RecentCompare)
                end
            end
            local headerName = selCat and selCat.name
            if headerName then
                local headerIdx = 1
                local heading = GetOrCreateCatHeader(headerIdx)

                -- "Edit | Delete" links for user-created categories
                if not heading._editDeleteFrame then
                    local ef = CreateFrame("Frame", nil, childFrame)
                    ef:SetHeight(16)
                    ef:SetFrameLevel((heading:GetFrameLevel() or 1) + 1)

                    local delBtn = CreateFrame("Button", nil, ef)
                    delBtn:SetHeight(20)
                    delBtn._fs = delBtn:CreateFontString(nil, "OVERLAY")
                    SetBagFont(delBtn._fs, 10)
                    delBtn._fs:SetPoint("RIGHT", ef, "RIGHT", 0, 0)
                    delBtn._fs:SetText(CludesUI.L("Delete"))
                    delBtn._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    delBtn:SetWidth(delBtn._fs:GetStringWidth() + 4)
                    delBtn:SetAllPoints(delBtn._fs)
                    delBtn:SetScript("OnEnter", function(s)
                        s._fs:SetTextColor(1, 0.3, 0.3, 1)
                    end)
                    delBtn:SetScript("OnLeave", function(s)
                        s._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    end)
                    delBtn:SetScript("OnClick", function()
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
                    ef._delBtn = delBtn

                    local divider = ef:CreateFontString(nil, "OVERLAY")
                    SetBagFont(divider, 10)
                    divider:SetPoint("RIGHT", delBtn._fs, "LEFT", -6, 0)
                    divider:SetText("|")
                    divider:SetTextColor(0.3, 0.3, 0.3, 0.7)
                    ef._divider = divider

                    local editBtn = CreateFrame("Button", nil, ef)
                    editBtn:SetHeight(20)
                    editBtn._fs = editBtn:CreateFontString(nil, "OVERLAY")
                    SetBagFont(editBtn._fs, 10)
                    editBtn._fs:SetPoint("RIGHT", divider, "LEFT", -6, 0)
                    editBtn._fs:SetText(CludesUI.L("Edit"))
                    editBtn._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    editBtn:SetWidth(editBtn._fs:GetStringWidth() + 4)
                    editBtn:SetAllPoints(editBtn._fs)
                    editBtn:SetScript("OnEnter", function(s)
                        s._fs:SetTextColor(1, 1, 1, 1)
                    end)
                    editBtn:SetScript("OnLeave", function(s)
                        s._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
                    end)
                    editBtn:SetScript("OnClick", function()
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
                    ef._editBtn = editBtn

                    ef:SetWidth(60)
                    heading._editDeleteFrame = ef
                end

                -- Position Edit | Delete above the header, then the header below
                if selCat and selCat.isUserCreated then
                    local ef = heading._editDeleteFrame
                    ef:SetParent(childFrame)
                    ef:ClearAllPoints()
                    ef:SetPoint("TOPRIGHT", childFrame, "TOPLEFT", startX + gridW, curY)
                    ef:SetWidth(gridW)
                    ef:Show()
                    curY = curY - 18
                elseif heading._editDeleteFrame then
                    heading._editDeleteFrame:Hide()
                end

                -- Compact draws the name as the group's label instead
                if not compactOn then
                    heading:SetParent(childFrame)
                    heading:ClearAllPoints()
                    heading:SetPoint("TOPLEFT", childFrame, "TOPLEFT", startX, curY)
                    heading:SetWidth(gridW)
                    heading._label:SetText(headerName .. " (" .. #displayItems .. ")")
                    -- Pinned / Recent: their hint shows while the label is hovered
                    if selCat and selCat.isPinned then
                        mod.SetHeaderHint(heading, CludesUI.L("Middle Click to Add or Remove"))
                    elseif selCat and selCat.isRecent then
                        mod.SetHeaderHint(
                            heading,
                            CludesUI.L("Extra quickview display, your items are also in their category")
                        )
                    end
                    heading:Show()
                    curY = curY - 22
                end -- grid header
            end

            local itemCount = #displayItems
            local useSlotNest = armorySlotGrouping
                and selCat
                and IsArmoryGearCategory(selCat)
                and itemCount > 0

            if compactOn then
                local aKey
                if
                    useSlotNest
                    and selectedCategoryIndex > 0
                    and CUI_CategoryManager:CanAssignToCategory(selectedCategoryIndex)
                then
                    aKey = selCat._defaultName
                end
                -- The grid header's Pinned / Recent hint, on the label's hover
                local hint
                if selCat and selCat.isPinned then
                    hint = CludesUI.L("Middle Click to Add or Remove")
                elseif selCat and selCat.isRecent then
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
                local buckets = BuildSlotBuckets(displayItems)
                local showAssign = selectedCategoryIndex > 0
                    and CUI_CategoryManager
                    and CUI_CategoryManager:CanAssignToCategory(selectedCategoryIndex)
                expSubIdx =
                    RenderSlotBuckets(buckets, expSubIdx, showAssign and selCat and selCat._defaultName)
            else
                for i, payload in ipairs(displayItems) do
                    slotIdx = slotIdx + 1
                    local button = GetOrCreateSlot(slotIdx)
                    if button then
                        button:GetParent():SetParent(childFrame)
                        local column = (i - 1) % columns
                        local rowFrame = math.floor((i - 1) / columns)
                        RenderButton(button, payload, slotIdx, column, rowFrame, startX, curY, columns)
                    end
                end

                local remainder = itemCount % columns
                local padCount
                if itemCount == 0 then
                    padCount = columns
                elseif remainder == 0 then
                    padCount = 0
                else
                    padCount = columns - remainder
                end
                -- Cosmetic filler pads -- never clamp to free bag slots (see above).
                if padCount > 0 then
                    RenderEmptyPad(itemCount, padCount)
                end

                local totalItems = itemCount + math.max(padCount, 0)
                local gridRows = math.ceil(totalItems / columns)
                curY = curY - (gridRows * (SLOT_SIZE + SPACING))
            end -- slot nest vs flat grid
        end
    end

    -- Compact: pack and draw the groups this pass collected
    if compactOn then
        slotIdx, curY = mod.CompactBagsPlace(childFrame, startX, curY, columns, slotIdx)
    end

    -- Hide slots that were not rendered this pass
    for i = slotIdx + 1, #itemSlots do
        local button = itemSlots[i]
        if button then
            button:GetParent():Hide()
        end
    end
    return curY
end
