if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Themed Inspect Sheet
--  Mirrors the Character Sheet skinning for inspected characters.
--  Shared helpers (CludesUI.GetUpgradeTrack, CludesUI.GetEnchantText)
--  are exported by CharacterSheet and loaded before this file.
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
local skinned = false
local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD, GetFFD = CludesUI.NewFrameData()

-- Equipment slot lists
local CUI_ALL_SLOTS = {
    "InspectHeadSlot",
    "InspectNeckSlot",
    "InspectShoulderSlot",
    "InspectBackSlot",
    "InspectChestSlot",
    "InspectShirtSlot",
    "InspectTabardSlot",
    "InspectWristSlot",
    "InspectHandsSlot",
    "InspectWaistSlot",
    "InspectLegsSlot",
    "InspectFeetSlot",
    "InspectTrinket0Slot",
    "InspectTrinket1Slot",
    "InspectFinger0Slot",
    "InspectFinger1Slot",
    "InspectMainHandSlot",
    "InspectSecondaryHandSlot",
    "InspectRangedSlot", -- WoW Forever only (nil on retail)
}

-- Slot grid layout mapping
local slotGrid = {
    InspectHeadSlot = { col = 0, row = 0 },
    InspectNeckSlot = { col = 0, row = 1 },
    InspectShoulderSlot = { col = 0, row = 2 },
    InspectBackSlot = { col = 0, row = 3 },
    InspectChestSlot = { col = 0, row = 4 },
    InspectShirtSlot = { col = 0, row = 5 },
    InspectTabardSlot = { col = 0, row = 6 },
    InspectWristSlot = { col = 0, row = 7 },
    InspectHandsSlot = { col = 1, row = 0 },
    InspectWaistSlot = { col = 1, row = 1 },
    InspectLegsSlot = { col = 1, row = 2 },
    InspectFeetSlot = { col = 1, row = 3 },
    InspectFinger0Slot = { col = 1, row = 4 },
    InspectFinger1Slot = { col = 1, row = 5 },
    InspectTrinket0Slot = { col = 1, row = 6 },
    InspectTrinket1Slot = { col = 1, row = 7 },
    InspectMainHandSlot = { slot = "MainHand" },
    InspectSecondaryHandSlot = { slot = "SecondaryHand" },
    InspectRangedSlot = { slot = "Ranged" }, -- WoW Forever only
}

-- Drop every label a previous styling pass left on this slot. The widgets
-- are parked in per-slot cache fields and reused by the next pass: the
-- client never frees frames or font strings, so recreating them on every
-- pass would grow the widget count for the rest of the session.
local function CUI_ClearSlotLabels(slotFrame)
    local skinData = GetFFD(slotFrame)
    if skinData.iLvlText then
        skinData.iLvlText:Hide()
        skinData.cachedILvlText = skinData.iLvlText
        skinData.iLvlText = nil
    end
    if skinData.enchantText then
        skinData.enchantText:Hide()
        skinData.cachedEnchantText = skinData.enchantText
        skinData.enchantText = nil
    end
    if skinData.enchantHoverFrame then
        skinData.enchantHoverFrame:Hide()
        skinData.cachedEnchantHover = skinData.enchantHoverFrame
        skinData.enchantHoverFrame = nil
    end
    if skinData.upgradeText then
        skinData.upgradeText:Hide()
        skinData.cachedUpgradeText = skinData.upgradeText
        skinData.upgradeText = nil
    end
end

-- Returns true when the slot's item or tooltip data has not arrived yet (its
-- labels wait for it: RefreshSlotStyles reads the slot again as it comes).
local function CUI_UpdateSlotStyle(slotKey, slotID, textLayer, rightSide)
    local slotFrame = _G[slotKey]
    if not slotFrame or not textLayer then
        return
    end
    local waiting = false

    -- Blizzard reuses the SAME global slot frames (InspectHeadSlot etc) for
    -- every target, so a label belongs to whoever was inspected last until
    -- something clears it. The create-once guards below are no-ops while a
    -- stale label exists, which left the previous target's numbers sitting
    -- next to the new target's icons. Only RefreshSlotStyles used to clear,
    -- so a sheet opened without a following INSPECT_READY (the client already
    -- had that unit cached) kept the old values indefinitely -- the reported
    -- "shows the first player's item levels". Clear here instead, so EVERY
    -- styling pass rebuilds from the live item link no matter who calls.
    CUI_ClearSlotLabels(slotFrame)

    local skipLabels = (slotKey == "InspectShirtSlot" or slotKey == "InspectTabardSlot")
    -- WoW Forever's ranged slot sits right of the off hand, so there the off
    -- hand's labels stack above it (the ranged slot's go right, as by default).
    local above = slotKey == "InspectSecondaryHandSlot" and InspectRangedSlot ~= nil

    local inspectUnit = InspectFrame and InspectFrame.unit
    if not inspectUnit then
        return
    end

    local fontFile = CludesUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
    local linkText = GetInventoryItemLink(inspectUnit, slotID)
    GetFFD(slotFrame).itemLink = linkText

    local borderR, borderG, borderB = 0.4, 0.4, 0.4
    if linkText then
        local quality = C_Item.GetItemQualityByID(linkText)
        if quality then
            borderR, borderG, borderB = C_Item.GetItemQualityColor(quality)
        end
    end

    if CludesUI and CludesUI.PanelPP then
        CludesUI.PanelPP.SetBorderColor(slotFrame, borderR, borderG, borderB, 1)
    end
    GetFFD(slotFrame).border = true

    -- Item level label (font size matches CharacterSheet)
    if linkText and not GetFFD(slotFrame).iLvlText and not skipLabels then
        -- GetItemInfo's itemLevel is the cached base level, wrong for upgrade-track
        -- pieces; the detailed level reads the link's bonus IDs.
        local _, _, quality, baseIlvl = GetItemInfo(linkText)
        local itemLevel = C_Item.GetDetailedItemLevelInfo(linkText) or baseIlvl
        if itemLevel and itemLevel > 0 then
            local itemLevelSize = CludesUIDB and CludesUIDB.charSheetItemLevelSize or 11
            local levelText = GetFFD(slotFrame).cachedILvlText or textLayer:CreateFontString(nil, "OVERLAY")
            levelText:SetFont(fontFile, itemLevelSize, "")
            levelText:SetTextColor(1, 1, 1, 0.8)
            levelText:SetJustifyH("CENTER")
            levelText:ClearAllPoints()

            if above then
                levelText:SetPoint("BOTTOM", slotFrame, "TOP", 0, 3)
            elseif slotKey == "InspectMainHandSlot" then
                levelText:SetPoint("CENTER", slotFrame, "LEFT", -15, 10)
            elseif slotKey == "InspectSecondaryHandSlot" then
                levelText:SetPoint("CENTER", slotFrame, "RIGHT", 15, 10)
            elseif rightSide then
                levelText:SetPoint("CENTER", slotFrame, "LEFT", -15, 10)
            else
                levelText:SetPoint("CENTER", slotFrame, "RIGHT", 15, 10)
            end

            levelText:SetText(itemLevel)

            local displayColor = CludesUI.GetItemLevelColor(linkText, quality)
            levelText:SetTextColor(displayColor.r, displayColor.g, displayColor.b, 0.9)
            levelText:Show()

            GetFFD(slotFrame).iLvlText = levelText
        else
            waiting = true
        end
    end

    -- Enchant label: its icon (the name on hover), or under Text the name
    -- itself, outlined and tinted from the item level's color, as on the
    -- character sheet (a missing enchant keeps its red icon). WoW Forever's
    -- enchants carry no icon, so the name always shows there (plain unless
    -- Colored Text), named as that client's character sheet names it.
    local enchantText = linkText
        and not GetFFD(slotFrame).enchantText
        and not skipLabels
        and CludesUI.GetEnchantText(slotID, inspectUnit)
    -- An enchanted item whose tooltip has not arrived reads as no enchant:
    -- no label until it does, never the red missing-enchant icon.
    if enchantText == "" then
        local linkEnchant = tonumber(linkText:match("item:%d+:(%d+)"))
        if linkEnchant and linkEnchant ~= 0 then
            waiting = true
            enchantText = nil
        end
    end
    if enchantText then
        local iconOnly, tipText, _, hasEnchant =
            mod.ParseEnchantLabel(enchantText, slotID, linkText, inspectUnit)
        if mod.ForeverEnchantName then
            tipText = mod.ForeverEnchantName(enchantText)
        end

        local enchantsShown = (not CludesUIDB) or (CludesUIDB.inspectShowEnchants ~= false)
        local styled = CludesUIDB and CludesUIDB.inspectEnchantNames
        local useName = (styled or CludesUI.IS_FOREVER) and hasEnchant and tipText and tipText ~= ""
        local captionText = useName and tipText or iconOnly

        if enchantsShown and captionText and captionText ~= "" then
            -- The inspect sheet's own size, else the character sheet's
            local enchantSize = (
                CludesUIDB and (CludesUIDB.inspectEnchantSize or CludesUIDB.charSheetEnchantSize)
            ) or 9
            local enchantText = GetFFD(slotFrame).cachedEnchantText
                or textLayer:CreateFontString(nil, "OVERLAY")
            if useName and styled then
                enchantText:SetFont(fontFile, enchantSize, CludesUI.SlugFlag("OUTLINE, SLUG"))
                local _, _, quality = GetItemInfo(linkText)
                local c = CludesUI.GetItemLevelColor(linkText, quality)
                enchantText:SetTextColor(
                    c.r + (1 - c.r) * 0.5,
                    c.g + (1 - c.g) * 0.5,
                    c.b + (1 - c.b) * 0.5,
                    0.9
                )
            else
                enchantText:SetFont(fontFile, enchantSize, "")
                enchantText:SetTextColor(1, 1, 1, 0.8)
            end
            -- A name is capped at 45% of the gap between the two columns, so
            -- it never runs over the model or into the other column (cut
            -- short; the full name stays on the hover).
            local maxW
            if useName then
                local lr = _G.InspectHeadSlot and _G.InspectHeadSlot:GetRight()
                local rl = _G.InspectHandsSlot and _G.InspectHandsSlot:GetLeft()
                if
                    lr
                    and rl
                    and not (issecretvalue and (issecretvalue(lr) or issecretvalue(rl)))
                    and rl > lr
                then
                    maxW = (rl - lr) * 0.45
                end
            end
            enchantText:SetWordWrap(false)
            enchantText:SetWidth(maxW or 0)
            enchantText:ClearAllPoints()

            -- Justified toward its slot, so a capped name hugs it
            if above then
                local lvlText = GetFFD(slotFrame).iLvlText
                enchantText:SetPoint("BOTTOM", lvlText or slotFrame, "TOP", 0, lvlText and 1 or 3)
                enchantText:SetJustifyH("CENTER")
            elseif slotKey == "InspectMainHandSlot" then
                enchantText:SetPoint("RIGHT", slotFrame, "LEFT", -5, -5)
                enchantText:SetJustifyH("RIGHT")
            elseif slotKey == "InspectSecondaryHandSlot" then
                enchantText:SetPoint("LEFT", slotFrame, "RIGHT", 5, -5)
                enchantText:SetJustifyH("LEFT")
            elseif rightSide then
                enchantText:SetPoint("RIGHT", slotFrame, "LEFT", -5, -5)
                enchantText:SetJustifyH("RIGHT")
            else
                enchantText:SetPoint("LEFT", slotFrame, "RIGHT", 5, -5)
                enchantText:SetJustifyH("LEFT")
            end

            enchantText:SetText(captionText)
            enchantText:Show()
            GetFFD(slotFrame).enchantText = enchantText

            local hoverArea = GetFFD(slotFrame).cachedEnchantHover or CreateFrame("Frame", nil, textLayer)
            hoverArea:SetSize(20, 20)
            hoverArea:SetFrameLevel(textLayer:GetFrameLevel() + 20)
            hoverArea:ClearAllPoints()
            if above then
                hoverArea:SetPoint("CENTER", enchantText, "CENTER", 0, 0)
            elseif slotKey == "InspectMainHandSlot" then
                hoverArea:SetPoint("RIGHT", slotFrame, "LEFT", -5, -5)
            elseif slotKey == "InspectSecondaryHandSlot" then
                hoverArea:SetPoint("LEFT", slotFrame, "RIGHT", 5, -5)
            elseif rightSide then
                hoverArea:SetPoint("RIGHT", slotFrame, "LEFT", -5, -5)
            else
                hoverArea:SetPoint("LEFT", slotFrame, "RIGHT", 5, -5)
            end
            hoverArea:EnableMouse(true)

            hoverArea:SetScript("OnEnter", function()
                if tipText and tipText ~= "" and CludesUI.ShowWidgetTooltip then
                    CludesUI.ShowWidgetTooltip(hoverArea, tipText)
                end
            end)
            hoverArea:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            hoverArea:Show()

            GetFFD(slotFrame).enchantHoverFrame = hoverArea
        end
    end

    -- Upgrade track label (font size matches CharacterSheet)
    if linkText and not GetFFD(slotFrame).upgradeText and GetFFD(slotFrame).iLvlText and not skipLabels then
        local upgradeTrackSize = CludesUIDB and CludesUIDB.charSheetUpgradeTrackSize or 11
        local upgradeText, upgradeColor = CludesUI.GetUpgradeTrack(linkText)
        if upgradeText and upgradeText ~= "" then
            local upgradeLabel = GetFFD(slotFrame).cachedUpgradeText
                or textLayer:CreateFontString(nil, "OVERLAY")
            upgradeLabel:SetFont(fontFile, upgradeTrackSize, "")
            upgradeLabel:SetTextColor(upgradeColor.r, upgradeColor.g, upgradeColor.b, 0.8)
            upgradeLabel:SetJustifyH("CENTER")
            upgradeLabel:ClearAllPoints()

            if above then
                upgradeLabel:SetPoint("LEFT", GetFFD(slotFrame).iLvlText, "RIGHT", 3, 0)
            elseif slotKey == "InspectMainHandSlot" then
                upgradeLabel:SetPoint("RIGHT", GetFFD(slotFrame).iLvlText, "LEFT", -3, 0)
            elseif slotKey == "InspectSecondaryHandSlot" then
                upgradeLabel:SetPoint("LEFT", GetFFD(slotFrame).iLvlText, "RIGHT", 3, 0)
            elseif rightSide then
                upgradeLabel:SetPoint("RIGHT", GetFFD(slotFrame).iLvlText, "LEFT", -3, 0)
            else
                upgradeLabel:SetPoint("LEFT", GetFFD(slotFrame).iLvlText, "RIGHT", 3, 0)
            end

            upgradeLabel:SetText("(" .. upgradeText .. ")")
            upgradeLabel:Show()
            GetFFD(slotFrame).upgradeText = upgradeLabel
        end
    end
    return waiting
end

-- Apply tab visibility: show labels only on Tab 1
-- Similar to ApplyTabVisibility in CharacterSheet.lua
-- Takes a boolean parameter: true = show labels (Tab 1), false = hide labels (Tab 2/3)
local function ApplyTabVisibility(showLabels)
    local widget = InspectFrame
    if not widget then
        return
    end

    -- Show/hide individual labels based on settings
    local showItemLevel = (not CludesUIDB) or (CludesUIDB.inspectShowItemLevel ~= false)
    local showUpgradeTrack = (not CludesUIDB) or (CludesUIDB.inspectShowUpgradeTrack ~= false)
    local enchantsShown = (not CludesUIDB) or (CludesUIDB.inspectShowEnchants ~= false)

    for slotKey, _ in pairs(slotGrid) do
        local slotFrame = _G[slotKey]
        if slotFrame then
            -- Only show labels if on Tab 1 and settings allow
            if GetFFD(slotFrame).iLvlText then
                GetFFD(slotFrame).iLvlText:SetShown(showLabels and showItemLevel)
            end
            if GetFFD(slotFrame).upgradeText then
                GetFFD(slotFrame).upgradeText:SetShown(showLabels and showUpgradeTrack)
            end
            if GetFFD(slotFrame).enchantText then
                GetFFD(slotFrame).enchantText:SetShown(showLabels and enchantsShown)
            end
            -- Its hover spot too, or the other tabs keep an invisible tooltip
            if GetFFD(slotFrame).enchantHoverFrame then
                GetFFD(slotFrame).enchantHoverFrame:SetShown(showLabels and enchantsShown)
            end
        end
    end

    -- Hide/show avg ilvl + M+ score
    local widget = InspectFrame
    if widget then
        if GetFFD(widget).avgIlvlText then
            GetFFD(widget).avgIlvlText:SetShown(showLabels)
        end
        if GetFFD(widget).mPlusScoreText then
            GetFFD(widget).mPlusScoreText:SetShown(showLabels)
        end
    end
end

-- Calculate average item level from inspected player
local function CalculateAverageItemLevel()
    if not InspectFrame or not InspectFrame.unit then
        return 0
    end

    local unitToken = InspectFrame.unit

    -- Use the proper WoW API for getting inspect item level
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local itemLevel = C_PaperDollInfo.GetInspectItemLevel(unitToken)
        if itemLevel and itemLevel > 0 then
            return itemLevel
        end
    end

    return 0
end

local function SkinInspectSheet()
    if skinned then
        return
    end
    skinned = true

    local widget = InspectFrame
    if not widget then
        return
    end

    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05

    -- Create custom background texture FIRST before hiding anything
    if GetFFD(widget).bg then
        GetFFD(widget).bg:Show()
    else
        local backdrop, bgOverlay = mod.SheetBackdrop(widget)
        GetFFD(widget).bg = backdrop
        GetFFD(widget).bgOverlay = bgOverlay
        -- Follows the Character Sheet window's style pick (the two share one
        -- enable + style setting).
        if mod.WSkin and mod.WSkin.AdoptShell then
            mod.WSkin.AdoptShell("charsheet", widget, backdrop, GetFFD(widget).bgOverlay)
        end
    end

    -- Standard window-reskin border (the AdventureMap_TopBorder atlas texture),
    -- same as the character sheet and every other skinned Blizzard window.
    if mod.WSkin and mod.WSkin.AtlasBorder then
        mod.WSkin.AtlasBorder(widget)
    end

    -- Hide Blizzard backgrounds and borders
    for _, elem in ipairs({
        widget.NineSlice,
        widget.Background,
        widget.TitleBg,
        widget.TopTileStreaks,
        widget.Portrait,
        widget.Bg,
        InspectModelFrameBackgroundOverlay,
        InspectModelFrameBorderRight,
        InspectModelFrameBorderLeft,
        InspectModelFrameBorderBottom,
        InspectModelFrameBorderTop,
    }) do
        if elem then
            elem:Hide()
        end
    end

    -- Hide Blizzard Bg textures (our atlas bg covers everything)
    if InspectFrameBg then
        InspectFrameBg:SetAlpha(0)
    end
    if InspectFrameInset and InspectFrameInset.Bg then
        InspectFrameInset.Bg:SetAlpha(0)
    end

    -- Create model background (matches character sheet: character-bg.png, no glow/gradient)
    -- Deferred until InspectModelFrame exists (created lazily by Blizzard)
    local function TryCreateModelBg()
        if GetFFD(widget).modelBgFrame then
            return
        end
        local modelFrame = _G.InspectModelFrame
        if not modelFrame then
            return
        end
        local backdrop = CreateFrame("Frame", nil, modelFrame)
        backdrop:SetFrameLevel(math.max(1, modelFrame:GetFrameLevel() - 1))
        backdrop:ClearAllPoints()
        -- Match the Character sheet: span the backdrop across the full gear
        -- width (left gear column to right gear column) and down to the model
        -- bottom, so character-bg.png covers the whole gear + model area. The
        -- inspect model sits at Blizzard's default center spot, so its right edge
        -- stops short of the right gear; anchor the right edge to the right gear
        -- column instead. Falls back progressively if the slots are not up yet.
        local headSlot = _G.InspectHeadSlot
        local handsSlot = _G.InspectHandsSlot
        if headSlot and handsSlot then
            backdrop:SetPoint("TOPLEFT", headSlot, "TOPLEFT", -8, 10)
            backdrop:SetPoint("RIGHT", handsSlot, "RIGHT", 8, 0)
            backdrop:SetPoint("BOTTOM", modelFrame, "BOTTOM", 0, -18)
        elseif headSlot then
            backdrop:SetPoint("TOPLEFT", headSlot, "TOPLEFT", -8, 10)
            backdrop:SetPoint("BOTTOMRIGHT", modelFrame, "BOTTOMRIGHT", 0, -18)
        else
            backdrop:SetPoint("TOPLEFT", modelFrame, "TOPLEFT", -8, 10)
            backdrop:SetPoint("BOTTOMRIGHT", modelFrame, "BOTTOMRIGHT", 0, -18)
        end
        local bgTex = backdrop:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints(backdrop)
        bgTex:SetTexture("Interface\\AddOns\\CludesUIBlizzardSkin\\Media\\character-bg.png")
        bgTex:SetAlpha(1)

        GetFFD(widget).modelBg = bgTex
        GetFFD(widget).modelBgFrame = backdrop
    end
    TryCreateModelBg()
    -- Retry on show in case model frame wasn't ready on first skin.
    -- Staggered retries: Blizzard creates InspectModelFrame lazily
    -- after the inspect target is set, which can take multiple frames.
    -- HookScript only once to prevent accumulation on repeated reskins.
    if not GetFFD(widget)._modelBgHooked then
        GetFFD(widget)._modelBgHooked = true
        widget:HookScript("OnShow", function()
            C_Timer.After(0, TryCreateModelBg)
            C_Timer.After(0.2, TryCreateModelBg)
            C_Timer.After(0.5, TryCreateModelBg)
        end)
    end

    -- Hide portrait (separate handling to ensure it's fully hidden)
    if InspectFramePortrait then
        InspectFramePortrait:Hide()
        InspectFramePortrait:SetAlpha(0)
    end

    -- Hide TopTileStreaks explicitly
    if widget.TopTileStreaks then
        widget.TopTileStreaks:Hide()
        widget.TopTileStreaks:SetAlpha(0)
    end

    -- Hide InspectModelScene ControlFrame (similar to CharacterModelScene in CharacterSheet)
    if InspectModelScene then
        if InspectModelScene.ControlFrame then
            InspectModelScene.ControlFrame:SetAlpha(0)
            InspectModelScene.ControlFrame:EnableMouse(false)
        end
    end

    -- Hide individual control buttons and textures
    local controlButtons = {
        "InspectModelFrameControlFrameZoomInButton",
        "InspectModelFrameControlFrameZoomOutButton",
        "InspectModelFrameControlFramePanButton",
        "InspectModelFrameControlFrameRotateLeftButton",
        "InspectModelFrameControlFrameRotateRightButton",
        "InspectModelFrameControlFrameRotateResetButton",
        "InspectModelFrameControlFrameLeft",
        "InspectModelFrameControlFrameMiddle",
        "InspectModelFrameControlFrameRight",
    }
    for _, buttonName in ipairs(controlButtons) do
        local button = _G[buttonName]
        if button then
            button:SetAlpha(0)
            button:EnableMouse(false)
        end
    end

    -- Hide InspectModelFrameBorder edges and corners explicitly
    for _, border in ipairs({
        InspectModelFrameBorderBottom,
        InspectModelFrameBorderLeft,
        InspectModelFrameBorderTop,
        InspectModelFrameBorderRight,
        InspectModelFrameBorderBottomRight,
        InspectModelFrameBorderBottomLeft,
        InspectModelFrameBorderTopRight,
        InspectModelFrameBorderTopLeft,
        InspectModelFrameBorderBottom2,
    }) do
        if border then
            border:Hide()
            border:SetAlpha(0)
        end
    end

    -- Hide InspectModelFrameBackgroundOverlay explicitly
    if InspectModelFrameBackgroundOverlay then
        InspectModelFrameBackgroundOverlay:Hide()
        InspectModelFrameBackgroundOverlay:SetAlpha(0)
    end

    -- Hide InspectFrameInset.NineSlice (borders) but keep the frame for background
    if InspectFrameInset then
        if InspectFrameInset.NineSlice then
            InspectFrameInset.NineSlice:Hide()
            InspectFrameInset.NineSlice:SetAlpha(0)
        end
    end

    -- Hide InspectModelFrameBackground corners
    for _, corner in ipairs({
        InspectModelFrameBackgroundTopLeft,
        InspectModelFrameBackgroundTopRight,
        InspectModelFrameBackgroundBotLeft,
        InspectModelFrameBackgroundBotRight,
    }) do
        if corner then
            corner:Hide()
            corner:SetAlpha(0)
        end
    end

    if widget.PaperDollFrame and widget.PaperDollFrame.InnerBorder then
        for _, name in ipairs({
            "Top",
            "Bottom",
            "Left",
            "Right",
            "TopLeft",
            "TopRight",
            "BottomLeft",
            "BottomRight",
        }) do
            if widget.PaperDollFrame.InnerBorder[name] then
                widget.PaperDollFrame.InnerBorder[name]:Hide()
            end
        end
    end

    -- Hide PVP Frame background elements. Frames other addons parent in here
    -- are theirs to draw (see WSkin.IsForeignFrame), and the WoW Forever PvP
    -- frame keeps all of its content in one unnamed child, MainInfoFrame.
    local IsForeign = mod.WSkin and mod.WSkin.IsForeignFrame
    if InspectPVPFrame then
        local contentFrame = InspectPVPFrame.MainInfoFrame
        local children = { InspectPVPFrame:GetChildren() }
        for idx = 1, #children do
            local childFrame = children[idx]
            if
                childFrame
                and childFrame ~= contentFrame
                and not childFrame:GetName()
                and not (IsForeign and IsForeign(childFrame, InspectPVPFrame))
            then
                childFrame:Hide()
            end
        end
    end

    -- Hide Guild Frame background elements
    if InspectGuildFrame then
        local children = { InspectGuildFrame:GetChildren() }
        for idx = 1, #children do
            local childFrame = children[idx]
            if
                childFrame
                and not childFrame:GetName()
                and not (IsForeign and IsForeign(childFrame, InspectGuildFrame))
            then
                childFrame:Hide()
            end
        end
    end

    -- Hide unnamed decoration frames in main InspectFrame
    local children = { widget:GetChildren() }
    for idx = 1, #children do
        local childFrame = children[idx]
        if
            childFrame
            and not childFrame:GetName()
            and childFrame:GetObjectType() == "Frame"
            and not (IsForeign and IsForeign(childFrame, widget))
        then
            -- Only hide if it's not one of our known frames and not the TitleFrame or title parent
            local isTitleFrame = (widget.TitleFrame and childFrame == widget.TitleFrame)
            local isTitleParent = (
                _G.inspectFrameTitleText and childFrame == _G.inspectFrameTitleText:GetParent()
            )
            if
                childFrame ~= widget.PaperDollFrame
                and childFrame ~= InspectPVPFrame
                and childFrame ~= InspectGuildFrame
                and not isTitleFrame
                and not isTitleParent
            then
                childFrame:Hide()
            end
        end
    end

    -- Add pixel-perfect border to the frame
    if CludesUI and CludesUI.PanelPP then
        CludesUI.PanelPP.CreateBorder(widget, 0.2, 0.2, 0.2, 1, 1, "OVERLAY", 7)
    end

    -- Style close button
    local closeBtn = widget.CloseButton or _G.InspectFrameCloseButton
    if closeBtn and mod.WSkin and mod.WSkin.CloseButton then
        mod.WSkin.CloseButton(closeBtn)
    end

    -- Restyle Blizzard's Talents + View (dressing room) buttons in place.
    -- User clicks the actual Blizzard button so the secure handler fires
    -- natively with no addon taint in the call stack.
    do
        local fontFile = CludesUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
        -- Narrower beside Forever's three-slot weapon row.
        local BTN_W, BTN_H = InspectRangedSlot and 76 or 90, 21
        local BTN_Y = 8

        local function RestyleButton(button, captionText, anchorFrame, anchorPoint, xOff)
            if not button then
                return
            end
            local ffd = GetFFD(button)
            if ffd.restyled then
                return
            end
            ffd.restyled = true

            button:ClearAllPoints()
            button:SetPoint(anchorFrame, widget, anchorPoint, xOff, BTN_Y)
            button:SetSize(BTN_W, BTN_H)
            button:SetFrameLevel(widget:GetFrameLevel() + 20)

            -- Standard Blizzard-window-skin button look: dark fill + theme
            -- border + hover highlight. WSkin.Button fades the native textures.
            if mod.WSkin and mod.WSkin.Button then
                mod.WSkin.Button(button)
            end

            -- Hide the native label (the View button is a dressing-room icon,
            -- not "Transmog") and draw our own, white like other skinned buttons.
            for _, regionFrame in ipairs({ button:GetRegions() }) do
                if regionFrame.GetObjectType and regionFrame:GetObjectType() == "FontString" then
                    regionFrame:SetTextColor(0, 0, 0, 0)
                end
            end
            local caption = button:CreateFontString(nil, "OVERLAY")
            caption:SetFont(fontFile, 10, "")
            caption:SetPoint("CENTER", button, "CENTER", 0, 0)
            caption:SetJustifyH("CENTER")
            caption:SetText(captionText)
            caption:SetTextColor(1, 1, 1, 1)
            ffd.label = caption

            button:SetAlpha(1)
            button:EnableMouse(true)
            button:Show()
        end

        -- Suppress other unnamed buttons in InspectPaperDollItemsFrame.
        -- Never touch buttons other addons parent in here (theirs to run).
        local paperDollItemsFrame = InspectPaperDollItemsFrame
        if paperDollItemsFrame then
            local IsForeignBtn = mod.WSkin and mod.WSkin.IsForeignFrame
            -- Retail only: WoW Forever's inspect window has no Talents button.
            local talentsBtn = paperDollItemsFrame.InspectTalents
            local children2 = { paperDollItemsFrame:GetChildren() }
            for idx = 1, #children2 do
                local childFrame = children2[idx]
                if
                    childFrame
                    and childFrame:GetObjectType() == "Button"
                    and not childFrame:GetName()
                    and childFrame ~= talentsBtn
                    and not (IsForeignBtn and IsForeignBtn(childFrame, paperDollItemsFrame))
                then
                    childFrame:SetAlpha(0)
                    childFrame:EnableMouse(false)
                end
            end
            RestyleButton(talentsBtn, "Talents", "BOTTOMRIGHT", "BOTTOMRIGHT", -7)
        end

        local blizViewBtn = InspectPaperDollFrame and InspectPaperDollFrame.ViewButton
        RestyleButton(blizViewBtn, "Transmog", "BOTTOMLEFT", "BOTTOMLEFT", 10)
    end

    -- Hide slot wrapper frames
    for _, slotKey in ipairs(CUI_ALL_SLOTS) do
        local frameName = slotKey .. "Frame"
        if _G[frameName] then
            _G[frameName]:Hide()
        end
    end

    -- Show actual slot buttons and style them
    for _, slotKey in ipairs(CUI_ALL_SLOTS) do
        local slotFrame = _G[slotKey]
        if slotFrame then
            slotFrame:Show()

            -- Hide ALL unnamed Texturen in den Slots (die Dekoration)
            local regionList = { slotFrame:GetRegions() }
            for idx = 1, #regionList do
                local regionFrame = regionList[idx]
                if regionFrame and regionFrame:IsObjectType("Texture") then
                    local regionName = regionFrame:GetName()
                    -- Hide nur unnamed Texturen (nicht die Icon)
                    if not regionName or regionName ~= (slotKey .. "IconTexture") then
                        regionFrame:SetAlpha(0)
                    end
                end
            end

            -- Hide Blizzard border and textures
            if slotFrame.IconBorder then
                slotFrame.IconBorder:Hide()
            end
            if slotFrame.IconOverlay then
                slotFrame.IconOverlay:Hide()
            end
            if slotFrame.IconOverlay2 then
                slotFrame.IconOverlay2:Hide()
            end

            -- Crop icon
            if slotFrame.icon then
                local z = (CludesUIDB and CludesUIDB.charSheetIconZoom) or 0.07
                slotFrame.icon:SetTexCoord(z, 1 - z, z, 1 - z)
            end

            local normalTexture = _G[slotKey .. "NormalTexture"]
            if normalTexture then
                normalTexture:Hide()
            end

            -- Get item rarity for border color
            local linkText = GetInventoryItemLink("inspect", slotFrame:GetID())
            local borderR, borderG, borderB = 0.4, 0.4, 0.4 -- Default gray
            if linkText then
                local _, _, quality = GetItemInfo(linkText)
                if quality then
                    borderR, borderG, borderB = C_Item.GetItemQualityColor(quality)
                end
            end

            -- Add rarity-colored border
            if CludesUI and CludesUI.PanelPP then
                CludesUI.PanelPP.CreateBorder(slotFrame, borderR, borderG, borderB, 1, 2, "OVERLAY", 7)
            end

            local hostFrame = slotFrame:GetParent()
            if hostFrame then
                hostFrame:Show()
            end
        end
    end

    -- Grid layout: 2 columns, 8 rows
    local cellWidth = 280
    local cellHeight = 41
    local gridStartX = 10
    local gridStartY = -60

    -- Create overlay frame for text labels (above items, transparent, no mouse input)
    -- Reuse existing overlay to prevent frame multiplication on repeated reskins
    local textLayer = GetFFD(widget).textOverlayFrame
    if not textLayer then
        textLayer = CreateFrame("Frame", "CUI_InspectSheet_TextOverlay", widget)
        textLayer:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)
        textLayer:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 0, 0)
        textLayer:SetFrameLevel(widget:GetFrameLevel() + 10)
        textLayer:EnableMouse(false)
        GetFFD(widget).textOverlayFrame = textLayer
    end
    textLayer:SetAlpha(GetFFD(widget).textHidden and 0 or 1)
    textLayer:Show()

    -- Top-left eyeball toggle: temporarily hides all item slot text (item level,
    -- upgrade track, enchants) by alpha-ing the shared overlay. Session-only,
    -- matches the CharacterSheet eyeball. State lives in FFD so it survives the
    -- frequent inspect re-skins (the SetAlpha above re-applies it each pass).
    if not GetFFD(widget).textEyeBtn then
        local EYE_VISIBLE = CludesUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = CludesUI.EYE_INVISIBLE_ICON
        local eyeBtn = CreateFrame("Button", "CUI_InspectSheet_TextEyeBtn", widget)
        eyeBtn:SetSize(20, 20)
        eyeBtn:SetPoint("TOPLEFT", widget, "TOPLEFT", 14, -6)
        eyeBtn:SetFrameLevel(widget:GetFrameLevel() + 20)
        eyeBtn:SetAlpha(0.4)
        local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        eyeTex:SetTexture(GetFFD(widget).textHidden and EYE_INVISIBLE or EYE_VISIBLE)
        eyeBtn:SetScript("OnClick", function()
            local hidden = not GetFFD(widget).textHidden
            GetFFD(widget).textHidden = hidden
            eyeTex:SetTexture(hidden and EYE_INVISIBLE or EYE_VISIBLE)
            if GetFFD(widget).textOverlayFrame then
                GetFFD(widget).textOverlayFrame:SetAlpha(hidden and 0 or 1)
            end
        end)
        eyeBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.8)
            CludesUI.ShowWidgetTooltip(
                self,
                GetFFD(widget).textHidden and "Show Item Text" or "Hide Item Text",
                { width = 135 }
            )
        end)
        eyeBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.4)
            CludesUI.HideWidgetTooltip()
        end)
        GetFFD(widget).textEyeBtn = eyeBtn
    end

    -- Position slots and style them
    if InspectPaperDollItemsFrame then
        for slotKey, gridCell in pairs(slotGrid) do
            local slotFrame = _G[slotKey]
            if slotFrame then
                -- Skip weapon slots (they have no col/row, positioned separately)
                if not gridCell.col then
                    -- Still style them, but don't position
                    local rightSide = false
                    CUI_UpdateSlotStyle(slotKey, slotFrame:GetID(), textLayer, rightSide)
                else
                    slotFrame:ClearAllPoints()
                    local xOffset = gridStartX + (gridCell.col * cellWidth)
                    local yOffset = gridStartY - (gridCell.row * cellHeight)
                    slotFrame:SetPoint("TOPLEFT", InspectPaperDollItemsFrame, "TOPLEFT", xOffset, yOffset)

                    -- Style the slot with borders, ilvl, enchants (right column = col 1)
                    local rightSide = gridCell.col == 1
                    CUI_UpdateSlotStyle(slotKey, slotFrame:GetID(), textLayer, rightSide)
                end
            end
        end
    end

    -- Position weapon slots at bottom (matches CharacterSheet pattern --
    -- hardcoded offset, no GetWidth which can return a secret value).
    if InspectMainHandSlot and InspectSecondaryHandSlot then
        InspectMainHandSlot:ClearAllPoints()
        InspectMainHandSlot:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", InspectRangedSlot and 104 or 128, 10)
        InspectSecondaryHandSlot:ClearAllPoints()
        InspectSecondaryHandSlot:SetPoint("TOPLEFT", InspectMainHandSlot, "TOPRIGHT", 12, 0)
        -- Forever only: a third weapon slot, the row recentred for it.
        if InspectRangedSlot then
            InspectRangedSlot:ClearAllPoints()
            InspectRangedSlot:SetPoint("TOPLEFT", InspectSecondaryHandSlot, "TOPRIGHT", 12, 0)
        end
    end

    -- Average item level + M+ score, centered below the title/level text.
    -- Anchored to frame TOP so they sit below the character info header.
    do
        local fontFile = CludesUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT

        -- Text overlay frame above model bg and fade
        if not GetFFD(widget).textOverlay then
            local txo = CreateFrame("Frame", nil, widget)
            txo:SetAllPoints(widget)
            txo:SetFrameLevel(
                (_G.InspectModelFrame and _G.InspectModelFrame:GetFrameLevel() or widget:GetFrameLevel()) + 5
            )
            txo:EnableMouse(false)
            GetFFD(widget).textOverlay = txo
        end
        local txo = GetFFD(widget).textOverlay
        txo:Show()

        if not GetFFD(widget).avgIlvlText then
            local ilvlFS = txo:CreateFontString(nil, "OVERLAY")
            ilvlFS:SetFont(fontFile, 16, "")
            ilvlFS:SetTextColor(0.6, 0.2, 1, 1)
            ilvlFS:SetJustifyH("CENTER")
            -- Under Blizzard's level line wherever the client draws it (WoW
            -- Forever puts it lower and larger than retail).
            local levelText = _G.InspectLevelText
            if levelText then
                ilvlFS:SetPoint("TOP", levelText, "BOTTOM", 0, -3)
            else
                ilvlFS:SetPoint("TOP", widget, "TOP", 0, -43)
            end
            GetFFD(widget).avgIlvlText = ilvlFS
        end

        if not GetFFD(widget).mPlusScoreText then
            local mpFS = txo:CreateFontString(nil, "OVERLAY")
            mpFS:SetFont(fontFile, 12, "")
            mpFS:SetTextColor(0.8, 0.8, 0.8, 1)
            mpFS:SetJustifyH("CENTER")
            mpFS:SetPoint("TOP", GetFFD(widget).avgIlvlText, "BOTTOM", 0, -2)
            GetFFD(widget).mPlusScoreText = mpFS
        end

        local avg = CalculateAverageItemLevel()
        if avg and avg > 0 then
            GetFFD(widget).avgIlvlText:SetFormattedText("%.2f", avg)
            GetFFD(widget).avgIlvlText:Show()
        else
            GetFFD(widget).avgIlvlText:Hide()
        end

        local inspectUnit = widget.unit
        local mpScore = 0
        if inspectUnit and C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
            local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(inspectUnit)
            if summary and summary.currentSeasonScore then
                mpScore = summary.currentSeasonScore
            end
        end
        if mpScore > 0 then
            local hex = mod.GetMPScoreHex(mpScore)
            GetFFD(widget).mPlusScoreText:SetFormattedText("M+ Score: |cff%s%d|r", hex, math.floor(mpScore))
            GetFFD(widget).mPlusScoreText:Show()
        else
            GetFFD(widget).mPlusScoreText:Hide()
        end
    end

    -- Style Tabs (InspectFrameTab1, 2, 3)
    local fontFile = CludesUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT
    local ACC = CludesUI.CLUDES_GREEN or { r = 0.51, g = 0.784, b = 1 }
    local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05

    local inspTabs = {}
    for idx = 1, 3 do
        local tabBtn = _G["InspectFrameTab" .. idx]
        if tabBtn then
            inspTabs[#inspTabs + 1] = tabBtn
            -- Remove Blizzard textures
            local regionList = { tabBtn:GetRegions() }
            for jdx = 1, #regionList do
                local regionFrame = regionList[jdx]
                if regionFrame and regionFrame:IsObjectType("Texture") then
                    regionFrame:SetTexture("")
                    if regionFrame.SetAtlas then
                        regionFrame:SetAtlas("")
                    end
                end
            end

            if tabBtn.Left then
                tabBtn.Left:SetTexture("")
            end
            if tabBtn.Middle then
                tabBtn.Middle:SetTexture("")
            end
            if tabBtn.Right then
                tabBtn.Right:SetTexture("")
            end
            if tabBtn.LeftDisabled then
                tabBtn.LeftDisabled:SetTexture("")
            end
            if tabBtn.MiddleDisabled then
                tabBtn.MiddleDisabled:SetTexture("")
            end
            if tabBtn.RightDisabled then
                tabBtn.RightDisabled:SetTexture("")
            end

            local highlight = tabBtn:GetHighlightTexture()
            if highlight then
                highlight:SetTexture("")
            end

            -- Add custom background (matches character sheet tab color)
            if not GetFFD(tabBtn).bg then
                GetFFD(tabBtn).bg = tabBtn:CreateTexture(nil, "BACKGROUND")
                GetFFD(tabBtn).bg:SetAllPoints()
                GetFFD(tabBtn).bg:SetColorTexture(0.043, 0.031, 0.027, 1)
            else
                GetFFD(tabBtn).bg:Show()
                GetFFD(tabBtn).bg:SetColorTexture(0.043, 0.031, 0.027, 1)
            end

            -- Add active highlight
            if not GetFFD(tabBtn).activeHL then
                local activeHL = tabBtn:CreateTexture(nil, "ARTWORK", nil, -6)
                activeHL:SetAllPoints()
                activeHL:SetColorTexture(1, 1, 1, 0.02)
                activeHL:SetBlendMode("ADD")
                activeHL:Hide()
                GetFFD(tabBtn).activeHL = activeHL
            else
                -- The Blizzard-texture strip loop above clears EVERY one of the
                -- tab's texture regions, including this one, on each re-skin
                -- (inspect re-skins on every INSPECT_READY as data streams in).
                -- Restore the fill, or the active-tab highlight blanks out --
                -- the same reason the background is re-colored above.
                GetFFD(tabBtn).activeHL:SetColorTexture(1, 1, 1, 0.02)
                GetFFD(tabBtn).activeHL:SetBlendMode("ADD")
            end

            -- Replace Blizzard label with custom font
            local blizLabel = tabBtn:GetFontString()
            local captionText = blizLabel and blizLabel:GetText() or ("Tab " .. idx)
            if blizLabel then
                blizLabel:SetTextColor(0, 0, 0, 0)
            end
            tabBtn:SetPushedTextOffset(0, 0)

            if not GetFFD(tabBtn).label then
                local caption = tabBtn:CreateFontString(nil, "OVERLAY")
                caption:SetFont(fontFile, 9, nil)
                caption:SetPoint("CENTER", tabBtn, "CENTER", 0, 0)
                caption:SetJustifyH("CENTER")
                caption:SetText(captionText)
                GetFFD(tabBtn).label = caption

                hooksecurefunc(tabBtn, "SetText", function(_, newText)
                    if newText and caption then
                        caption:SetText(newText)
                    end
                end)
            end

            -- Add underline for active tab
            if not GetFFD(tabBtn).underline then
                local underline = tabBtn:CreateTexture(nil, "OVERLAY", nil, 6)
                if CludesUI and CludesUI.PanelPP and CludesUI.PanelPP.DisablePixelSnap then
                    CludesUI.PanelPP.DisablePixelSnap(underline)
                    underline:SetHeight(CludesUI.PanelPP.mult or 1)
                else
                    underline:SetHeight(1)
                end
                underline:SetPoint("BOTTOMLEFT", tabBtn, "BOTTOMLEFT", 0, 0)
                underline:SetPoint("BOTTOMRIGHT", tabBtn, "BOTTOMRIGHT", 0, 0)
                underline:SetColorTexture(ACC.r or 0.51, ACC.g or 0.784, ACC.b or 1, 1)
                CludesUI.RegAccent({ type = "solid", obj = underline, a = 1 })
                underline:Hide()
                GetFFD(tabBtn).underline = underline
            else
                -- Same strip-loop restore as activeHL above: re-apply the accent
                -- fill so the active-tab underline does not blank out on re-skin.
                GetFFD(tabBtn).underline:SetColorTexture(ACC.r or 0.51, ACC.g or 0.784, ACC.b or 1, 1)
            end
        end
    end
    if mod.WSkin and mod.WSkin.NormalizeTabRow then
        mod.WSkin.NormalizeTabRow(inspTabs)
    end

    -- Update tab visuals on show
    local function UpdateTabVisuals()
        local onFirstTab = (widget.selectedTab or 1) == 1

        -- Show model background only on Tab 1
        if GetFFD(widget).modelBg then
            GetFFD(widget).modelBg:SetShown(onFirstTab)
        end
        if GetFFD(widget).modelBgGlow then
            GetFFD(widget).modelBgGlow:SetShown(onFirstTab)
        end

        -- Show Talents/Transmog buttons only on Tab 1 (Character sheet)
        if GetFFD(widget).talentsBtn then
            GetFFD(widget).talentsBtn:SetShown(onFirstTab)
        end
        if GetFFD(widget).transmogBtn then
            GetFFD(widget).transmogBtn:SetShown(onFirstTab)
        end
        -- The item text eyeball only has slots to act on on Tab 1
        if GetFFD(widget).textEyeBtn then
            GetFFD(widget).textEyeBtn:SetShown(onFirstTab)
        end

        -- Update label visibility with ApplyTabVisibility - only show on Tab 1
        ApplyTabVisibility(onFirstTab)

        for idx = 1, 3 do
            local tabBtn = _G["InspectFrameTab" .. idx]
            if tabBtn then
                local isActive = (widget.selectedTab or 1) == idx
                -- Ensure background is always visible
                if GetFFD(tabBtn).bg then
                    GetFFD(tabBtn).bg:Show()
                end
                if GetFFD(tabBtn).label then
                    GetFFD(tabBtn).label:SetTextColor(1, 1, 1, isActive and 1 or 0.5)
                end
                if GetFFD(tabBtn).underline then
                    GetFFD(tabBtn).underline:SetShown(isActive)
                end
                if GetFFD(tabBtn).activeHL then
                    GetFFD(tabBtn).activeHL:SetShown(isActive)
                end
            end
        end
    end

    -- Hook to update tabs when they change (once only). Every switch goes
    -- through InspectSwitchTabs: the bottom tabs on retail, the side tabs on
    -- WoW Forever and Blizzard's own resets to the character tab.
    if widget.HookScript and not GetFFD(widget)._tabHooked then
        GetFFD(widget)._tabHooked = true
        widget:HookScript("OnShow", function()
            UpdateTabVisuals()
        end)
        if _G.InspectSwitchTabs then
            hooksecurefunc("InspectSwitchTabs", function()
                UpdateTabVisuals()
            end)
        end
    end

    UpdateTabVisuals()

    -- Scale fully owned by Blizzard (SetScale on secure panels taints
    -- UIParentPanelManager execution context).
    widget:SetFrameStrata("HIGH")

    -- Center the title within the frame (406px wide). Hardcoded to avoid
    -- frame:GetWidth() which can return a secret value and cause taint.
    if widget.TitleContainer then
        widget.TitleContainer:Show()
        widget.TitleContainer:SetAlpha(1)
        widget.TitleContainer:SetFrameStrata("HIGH")
        widget.TitleContainer:SetFrameLevel(20)
        widget.TitleContainer:ClearAllPoints()
        widget.TitleContainer:SetWidth(406)
        widget.TitleContainer:SetPoint("TOP", widget, "TOP", 0, 0)

        local children2 = { widget.TitleContainer:GetChildren() }
        for idx = 1, #children2 do
            local childFrame = children2[idx]
            if childFrame and childFrame:GetObjectType() == "FontString" then
                childFrame:SetJustifyH("CENTER")
            end
        end
    end
end

-- Replicates stock Blizzard's Inspect-docks-beside-Character layout, since
-- nothing here pairs the two otherwise and InspectFrame's live model bleeds
-- through CharacterFrame's when they overlap. Docking beside CharacterFrame
-- removes the overlap, so no strata/z-order fight is needed -- a strata write
-- on a protected frame is an insecure, tainting write, so we never do one.
local DOCK_MARGIN = 4

-- InspectFrame can be a protected frame, and a plain ClearAllPoints/SetPoint on
-- a protected frame taints its tree. Reposition through a SecureHandler
-- restricted-environment snippet instead: it executes securely and never
-- taints. The handler is parented to UIParent, so self:GetParent() inside the
-- snippet IS UIParent and the frame anchors relative to UIParent. Combat-gated,
-- since secure repositioning of a protected frame is blocked in combat.
local securePositioner = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
local function SecureSetPoint(widget, point, relPoint, posX, posY)
    if InCombatLockdown() then
        return false
    end
    securePositioner:SetFrameRef("f", widget)
    securePositioner:SetAttribute("p", point)
    securePositioner:SetAttribute("rp", relPoint)
    securePositioner:SetAttribute("x", posX)
    securePositioner:SetAttribute("y", posY)
    securePositioner:Execute([[
        local f = self:GetFrameRef("f")
        if not f then return end
        f:ClearAllPoints()
        f:SetPoint(self:GetAttribute("p"), self:GetParent(), self:GetAttribute("rp"), self:GetAttribute("x"), self:GetAttribute("y"))
    ]])
    return true
end

local function ShifterPinned(name)
    return CludesUIDB and CludesUIDB.shifterPositions and CludesUIDB.shifterPositions[name] ~= nil
end

-- Reposition `mover` immediately beside `anchor`, on whichever side has screen room.
-- Room is compared in SCREEN-ABSOLUTE units (each frame's coords normalized through ITS
-- OWN effective scale), so a scaled or edge-pinned anchor never shoves the mover off
-- screen and back into an overlap. A protected mover goes through SecureSetPoint (never
-- a raw SetPoint -> taint); since that only anchors to UIParent, the beside-anchor
-- target is converted to a UIParent- CENTER offset.
local function DockBeside(dragHandle, anchorFrame)
    if not dragHandle or not anchorFrame then
        return
    end
    local as = anchorFrame:GetEffectiveScale() or 1
    local modelScene = dragHandle:GetEffectiveScale() or 1
    local ues = UIParent:GetEffectiveScale() or 1
    local wAbs = (dragHandle:GetWidth() or 0) * modelScene
    local leftRoom = (anchorFrame:GetLeft() or 0) * as
    local rightRoom = (GetScreenWidth() or 0) * ues - (anchorFrame:GetRight() or 0) * as
    local dockLeft = leftRoom >= wAbs + DOCK_MARGIN * modelScene or leftRoom >= rightRoom

    if dragHandle:IsProtected() then
        if InCombatLockdown() then
            return
        end
        local hAbs = (dragHandle:GetHeight() or 0) * modelScene
        local absCenterX
        if dockLeft then
            absCenterX = leftRoom - DOCK_MARGIN * modelScene - wAbs / 2
        else
            absCenterX = (anchorFrame:GetRight() or 0) * as + DOCK_MARGIN * modelScene + wAbs / 2
        end
        local absCenterY = (anchorFrame:GetTop() or 0) * as - hAbs / 2
        local ucx, ucy = UIParent:GetCenter()
        if ucx and modelScene > 0 then
            SecureSetPoint(
                dragHandle,
                "CENTER",
                "CENTER",
                (absCenterX - ucx * ues) / modelScene,
                (absCenterY - ucy * ues) / modelScene
            )
        end
    else
        dragHandle:ClearAllPoints()
        if dockLeft then
            dragHandle:SetPoint("TOPRIGHT", anchorFrame, "TOPLEFT", -DOCK_MARGIN, 0)
        else
            dragHandle:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", DOCK_MARGIN, 0)
        end
    end
end

-- Each window's pre-dock anchor, captured the first time WE move it so it can be
-- put back once its partner is gone. Keyed in an external table (never written
-- onto the Blizzard frame -> no taint). _ignoreSP guards the SetPoint hooks
-- against our own repositioning.
local _savedPoint = {}
local _moved = {}
local _ignoreSP = false

local function CapturePoint(widget)
    if not widget or _savedPoint[widget] then
        return
    end
    local p, rel, rp, posX, posY = widget:GetPoint(1)
    if p then
        _savedPoint[widget] = { p, rel, rp, posX, posY }
    end
end

local function RestorePoint(widget)
    local p = _savedPoint[widget]
    if not p or not widget then
        return
    end
    if widget:IsProtected() then
        -- Secure restore reproduces the native anchor only when it was
        -- UIParent-relative (the usual case for a top-level panel; a nil
        -- relativeTo defaults to the parent, UIParent, inside the snippet).
        if p[2] == nil or p[2] == UIParent then
            SecureSetPoint(widget, p[1], p[3], p[4], p[5])
        end
    else
        widget:ClearAllPoints()
        widget:SetPoint(p[1], p[2], p[3], p[4], p[5])
    end
end

-- Keep the Inspect and Character windows from overlapping while both are open. The
-- INSPECT window is held still and the CHARACTER sheet is the one that docks beside it.
-- If the user has pinned the character sheet with the Shifter, that is respected (it
-- stays put) and the inspect window yields instead; if both are pinned, neither moves.
local function RefreshDock()
    local insp, castFrame = InspectFrame, _G.CharacterFrame
    if not insp or not castFrame then
        return
    end
    if CludesUIDB and (CludesUIDB.themedInspectSheet == false or CludesUI.BlizzWindowSkinsKilled()) then
        return
    end

    if not (insp:IsShown() and castFrame:IsShown()) then
        _ignoreSP = true
        if _moved[castFrame] then
            _moved[castFrame] = nil
            RestorePoint(castFrame)
            _savedPoint[castFrame] = nil
        end
        if _moved[insp] then
            _moved[insp] = nil
            RestorePoint(insp)
            _savedPoint[insp] = nil
        end
        _ignoreSP = false
        return
    end

    local dragHandle, anchorFrame
    if not ShifterPinned("CharacterFrame") then
        dragHandle, anchorFrame = castFrame, insp
    elseif not ShifterPinned("InspectFrame") then
        dragHandle, anchorFrame = insp, castFrame
    else
        return
    end

    _ignoreSP = true
    CapturePoint(dragHandle)
    _moved[dragHandle] = true
    DockBeside(dragHandle, anchorFrame)
    _ignoreSP = false
end

-- Main function to apply themed inspect sheet
local function ApplyThemedInspectSheet()
    if CludesUIDB and (CludesUIDB.themedInspectSheet == false or CludesUI.BlizzWindowSkinsKilled()) then
        return
    end

    if InspectFrame then
        SkinInspectSheet()
        -- Show labels on Tab 1
        ApplyTabVisibility((InspectFrame.selectedTab or 1) == 1)
    end
end

-- Persistently hide NineSlice borders
local function EnsureInspectNineSliceHidden()
    if CludesUIDB and (CludesUIDB.themedInspectSheet == false or CludesUI.BlizzWindowSkinsKilled()) then
        return
    end
    if not InspectFrame then
        return
    end

    local widget = InspectFrame

    -- Hide InspectFrame.NineSlice
    if widget.NineSlice then
        widget.NineSlice:Hide()
        widget.NineSlice:SetAlpha(0)
    end

    -- Hide InspectFrameInset.NineSlice (borders). The inset is left transparent
    -- so the window's modern_blizz bg + 0.62 black overlay show through, matching
    -- the character sheet. Filling it with a solid color stacked a second dark
    -- layer behind the model.
    if InspectFrameInset and InspectFrameInset.NineSlice then
        InspectFrameInset.NineSlice:Hide()
        InspectFrameInset.NineSlice:SetAlpha(0)
    end
end

-- Register with parent addon
if CludesUI then
    CludesUI.ApplyThemedInspectSheet = ApplyThemedInspectSheet

    -- Register hooks when Blizzard_InspectUI loads (it's load-on-demand,
    -- so InspectFrame doesn't exist at PLAYER_LOGIN)
    local initFrame = CreateFrame("Frame")
    local _inspHooked = false

    local function HookInspectFrame()
        if _inspHooked or not InspectFrame then
            return
        end
        _inspHooked = true

        InspectFrame:HookScript("OnShow", function()
            skinned = false
            ApplyThemedInspectSheet()
            RefreshDock()
            C_Timer.After(0.1, function()
                if not InspectFrame or not InspectFrame:IsShown() then
                    return
                end
                if CludesUI._refreshInspectItemLevelVisibility then
                    CludesUI._refreshInspectItemLevelVisibility()
                end
                if CludesUI._refreshInspectUpgradeTrackVisibility then
                    CludesUI._refreshInspectUpgradeTrackVisibility()
                end
                if CludesUI._refreshInspectEnchantsVisibility then
                    CludesUI._refreshInspectEnchantsVisibility()
                end
            end)
        end)

        InspectFrame:HookScript("OnHide", function()
            skinned = false
            RefreshDock()
        end)

        -- When the inspect window itself moves (Shifter drag, Blizzard relayout),
        -- the docked character sheet follows it, so re-pair on its SetPoint too.
        hooksecurefunc(InspectFrame, "SetPoint", function()
            if not _ignoreSP then
                RefreshDock()
            end
        end)

        -- CharacterFrame is core UI, already loaded here (unlike InspectFrame).
        -- OnShow/OnHide re-pair; the SetPoint hook catches Blizzard's own panel
        -- relayout (which otherwise blinks the sheet back to its default spot).
        if _G.CharacterFrame then
            _G.CharacterFrame:HookScript("OnShow", RefreshDock)
            _G.CharacterFrame:HookScript("OnHide", RefreshDock)
            hooksecurefunc(_G.CharacterFrame, "SetPoint", function()
                if not _ignoreSP then
                    RefreshDock()
                end
            end)
        end

        local nineSliceHiddenFrame = CreateFrame("Frame")
        nineSliceHiddenFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        nineSliceHiddenFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
        nineSliceHiddenFrame:SetScript("OnEvent", function(self, evt, ...)
            if InspectFrame and InspectFrame:IsShown() then
                EnsureInspectNineSliceHidden()
            end
        end)

        InspectFrame:HookScript("OnShow", EnsureInspectNineSliceHidden)
    end

    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:RegisterEvent("ADDON_LOADED")
    initFrame:SetScript("OnEvent", function(self, evt, arg1)
        if evt == "PLAYER_LOGIN" then
            HookInspectFrame()
        elseif evt == "ADDON_LOADED" and arg1 == "Blizzard_InspectUI" then
            self:UnregisterEvent("ADDON_LOADED")
            HookInspectFrame()
        end
    end)

    -- Slots whose item or tooltip data had not arrived are read again as it
    -- does: item and tooltip data events, registered only while a slot waits,
    -- for at most WAIT_SECS from this inspect's first incomplete read (a new
    -- INSPECT_READY starts a new wait), one pass per burst.
    local WAIT_SECS = 5
    local waitStart, retryTimer
    local RefreshSlotStyles -- forward
    local dataWatch = CreateFrame("Frame")
    local function StopWait()
        dataWatch:UnregisterAllEvents()
    end
    local function EquippedByInspected(itemId)
        local unitToken = InspectFrame and InspectFrame.unit
        if not unitToken or not itemId then
            return false
        end
        for slotKey in pairs(slotGrid) do
            local slotFrame = _G[slotKey]
            if slotFrame and GetInventoryItemID(unitToken, slotFrame:GetID()) == itemId then
                return true
            end
        end
        return false
    end
    dataWatch:SetScript("OnEvent", function(_, evt, arg1)
        if retryTimer then
            return
        end
        if evt == "GET_ITEM_INFO_RECEIVED" and not EquippedByInspected(arg1) then
            return
        end
        retryTimer = C_Timer.NewTimer(0.12, function()
            retryTimer = nil
            if InspectFrame and InspectFrame:IsShown() then
                RefreshSlotStyles()
            else
                StopWait()
            end
        end)
    end)

    -- Function to refresh all slot styles when inspect data changes
    RefreshSlotStyles = function()
        if not InspectPaperDollItemsFrame then
            return
        end
        if not InspectFrame then
            return
        end
        local textLayer = GetFFD(InspectFrame).textOverlayFrame
        if not textLayer then
            return
        end

        local waiting = false
        for slotKey, gridCell in pairs(slotGrid) do
            local slotFrame = _G[slotKey]
            if slotFrame then
                -- Label clearing now lives in CUI_UpdateSlotStyle, so it covers
                -- ApplyThemedInspectSheet's styling pass too, not just this one.
                GetFFD(slotFrame).border = false
                -- Re-style (right column = col 1)
                local rightSide = gridCell.col == 1
                if CUI_UpdateSlotStyle(slotKey, slotFrame:GetID(), textLayer, rightSide) then
                    waiting = true
                end
            end
        end
        local nowTime = GetTime()
        if waiting and nowTime - (waitStart or nowTime) < WAIT_SECS then
            waitStart = waitStart or nowTime
            dataWatch:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            dataWatch:RegisterEvent("TOOLTIP_DATA_UPDATE")
        else
            StopWait()
        end
        -- Update label visibility after all slots have been styled
        local widget = InspectFrame
        if widget then
            ApplyTabVisibility(InspectPaperDollItemsFrame and InspectPaperDollItemsFrame:IsShown())
        end
    end

    -- Options refresher for the enchant display: restyles every slot of a
    -- shown sheet; a hidden one restyles on its next show.
    function CludesUI._refreshInspectSlotLabels()
        if not (InspectFrame and InspectFrame:IsShown()) then
            return
        end
        if CludesUIDB and (CludesUIDB.themedInspectSheet == false or CludesUI.BlizzWindowSkinsKilled()) then
            return
        end
        RefreshSlotStyles()
    end

    -- Also hook to INSPECT_READY to reskin when new inspection data arrives
    local inspectHook = CreateFrame("Frame")
    inspectHook:RegisterEvent("INSPECT_READY")
    inspectHook:SetScript("OnEvent", function(self, evt, unitGuid)
        if not InspectFrame or not InspectFrame:IsShown() then
            return
        end
        waitStart = nil -- new inspect data: a fresh wait for what it still lacks
        skinned = false
        ApplyThemedInspectSheet()
        EnsureInspectNineSliceHidden()
        RefreshSlotStyles()
        local widget = InspectFrame
        if widget then
            ApplyTabVisibility(InspectPaperDollItemsFrame and InspectPaperDollItemsFrame:IsShown())
            -- Apply visibility settings after styling
            if CludesUI._refreshInspectItemLevelVisibility then
                CludesUI._refreshInspectItemLevelVisibility()
            end
            if CludesUI._refreshInspectUpgradeTrackVisibility then
                CludesUI._refreshInspectUpgradeTrackVisibility()
            end
            if CludesUI._refreshInspectEnchantsVisibility then
                CludesUI._refreshInspectEnchantsVisibility()
            end
            if CludesUI._refreshInspectAverageItemLevelVisibility then
                CludesUI._refreshInspectAverageItemLevelVisibility()
            end
        end
    end)
else
    -- CludesUI.Print not available here (CludesUI is nil)
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffff0000Error:|r CludesUI not found! Themed Inspect Sheet requires CludesUI."
    )
end

-- Initialize defaults
do
    local defaultStamp = CreateFrame("Frame")
    defaultStamp:RegisterEvent("ADDON_LOADED")
    defaultStamp:SetScript("OnEvent", function(self, _, addon)
        if addon ~= "CludesUI" then
            return
        end
        self:UnregisterAllEvents()
        if not CludesUIDB then
            CludesUIDB = {}
        end
        local defaultSet = {
            themedInspectSheet = true,
            inspectShowItemLevel = true,
            inspectShowUpgradeTrack = true,
            inspectShowEnchants = true,
        }
        for key, val in pairs(defaultSet) do
            if CludesUIDB[key] == nil then
                CludesUIDB[key] = val
            end
        end
    end)
end

-- Function to refresh item level visibility when toggle changes
function CludesUI._refreshInspectItemLevelVisibility()
    if not InspectFrame or not InspectPaperDollItemsFrame then
        return
    end

    local showItemLevel = (not CludesUIDB) or (CludesUIDB.inspectShowItemLevel ~= false)
    local onFirstTab = InspectPaperDollItemsFrame and InspectPaperDollItemsFrame:IsShown()

    for slotKey, _ in pairs(slotGrid) do
        local slotFrame = _G[slotKey]
        if slotFrame and GetFFD(slotFrame).iLvlText then
            -- Only show if Tab 1 AND setting is enabled
            GetFFD(slotFrame).iLvlText:SetShown(onFirstTab and showItemLevel)
        end
    end
end

-- Function to refresh upgrade track visibility when toggle changes
function CludesUI._refreshInspectUpgradeTrackVisibility()
    if not InspectFrame or not InspectPaperDollItemsFrame then
        return
    end

    local showUpgradeTrack = (not CludesUIDB) or (CludesUIDB.inspectShowUpgradeTrack ~= false)
    local onFirstTab = InspectPaperDollItemsFrame and InspectPaperDollItemsFrame:IsShown()

    for slotKey, _ in pairs(slotGrid) do
        local slotFrame = _G[slotKey]
        if slotFrame and GetFFD(slotFrame).upgradeText then
            -- Only show if Tab 1 AND setting is enabled
            GetFFD(slotFrame).upgradeText:SetShown(onFirstTab and showUpgradeTrack)
        end
    end
end

-- Function to refresh enchants visibility when toggle changes
function CludesUI._refreshInspectEnchantsVisibility()
    if not InspectFrame or not InspectPaperDollItemsFrame then
        return
    end

    local enchantsShown = (not CludesUIDB) or (CludesUIDB.inspectShowEnchants ~= false)
    local onFirstTab = InspectPaperDollItemsFrame and InspectPaperDollItemsFrame:IsShown()

    for slotKey, _ in pairs(slotGrid) do
        local slotFrame = _G[slotKey]
        if slotFrame and GetFFD(slotFrame).enchantText then
            -- Only show if Tab 1 AND setting is enabled (its hover spot too)
            GetFFD(slotFrame).enchantText:SetShown(onFirstTab and enchantsShown)
            if GetFFD(slotFrame).enchantHoverFrame then
                GetFFD(slotFrame).enchantHoverFrame:SetShown(onFirstTab and enchantsShown)
            end
        end
    end
end
