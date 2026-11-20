if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Bags_Slots.lua
--
--  Drag-to-drop, the slot factory, the fast font and icon-zoom updates,
--  bind text, border color and the item overlay icons.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local mod = select(2, ...)
local Inner = mod._bagsInternals
-- CludesUIBags.lua or an earlier CUI_Bags_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local GetItemInfo = C_Item.GetItemInfo
local CUI = CludesUI

local _bankRouted, BP, GetFont, IsGearItem = Inner._bankRouted, Inner.BP, Inner.GetFont, Inner.IsGearItem
local NormalizePinKey, PinnedItems, bagSlots = Inner.NormalizePinKey, Inner.PinnedItems, Inner.bagSlots
local itemSlots, reagentSlots = Inner.itemSlots, Inner.reagentSlots
local CreateInsetBorder, SetInsetBorderColor = Inner.CreateInsetBorder, Inner.SetInsetBorderColor

-------------------------------------------------------------------------------
--  Drag-to-drop: template handles pickup, we handle drop on mouse release
-------------------------------------------------------------------------------
local _itemDragFrame = CreateFrame("Frame")
_itemDragFrame:Hide()
_itemDragFrame:SetScript("OnUpdate", function(self)
    if IsMouseButtonDown("LeftButton") then
        return
    end
    self:Hide()
    -- Blizzard's OnReceiveDrag (bars/equipment) fires BEFORE OnUpdate in the same
    -- frame; if it consumed the item, GetCursorInfo returns nil.
    if GetCursorInfo() ~= "item" then
        return
    end
    -- Cursor into each button's OWN coordinate space: GetRect() is in effective-scale
    -- units, so divide by btn:GetEffectiveScale() (not UIParent's -- matches only at scale 1.0).
    local rawCx, rawCy = GetCursorPosition()
    for _, button in pairs(itemSlots) do
        if button:IsShown() and button:GetParent():IsShown() then
            local es = button:GetEffectiveScale()
            local cx, cy = rawCx / es, rawCy / es
            local l, b, wid, hgt = button:GetRect()
            if l and b and cx >= l and cx <= l + wid and cy >= b and cy <= b + hgt then
                local destBag = button:GetParent():GetID()
                local destSlot = button:GetID()
                if destSlot > 0 then
                    C_Container.PickupContainerItem(destBag, destSlot)
                end
                return
            end
        end
    end
    local bankFrame = _G.CUI_BankFrame
    local bankSlots = bankFrame and bankFrame._bankSlots
    if bankSlots and bankFrame:IsVisible() then
        for _, button in pairs(bankSlots) do
            if button:IsShown() and button:GetParent():IsShown() then
                local es = button:GetEffectiveScale()
                local cx, cy = rawCx / es, rawCy / es
                local l, b, wid, hgt = button:GetRect()
                if l and b and cx >= l and cx <= l + wid and cy >= b and cy <= b + hgt then
                    local destBag = button:GetParent():GetID()
                    local destSlot = button:GetID()
                    if destSlot > 0 then
                        C_Container.PickupContainerItem(destBag, destSlot)
                    end
                    return
                end
            end
        end
    end
    -- Not over a bag/bank slot: leave item on cursor (bars/equipment already handled by OnReceiveDrag).
end)

-------------------------------------------------------------------------------
--  Slot Factory
-------------------------------------------------------------------------------
-- Middle-click: unassign an assigned item, else toggle its pin. Shared by the
-- grid slots and the list rows (ns.SlotMiddleClick).
local function SlotMiddleClick(self, btnFrame)
    if btnFrame ~= "MiddleButton" then
        return
    end
    local bagID = self:GetParent():GetID()
    local slotID = self:GetID()
    if not bagID or not slotID or slotID == 0 then
        return
    end
    local details = C_Container.GetContainerItemInfo(bagID, slotID)
    if not details or not details.itemID then
        return
    end
    -- If this item has a custom category assignment, middle-click unassigns it
    local assignments = CludesUIDB and CludesUIDB.bagItemAssignments
    if assignments and assignments[details.itemID] then
        CUI_CategoryManager:UnassignItem(details.itemID)
        if CUI_Bags.RefreshInventory then
            CUI_Bags:RefreshInventory()
        end
        return
    end
    local pinned = PinnedItems(true)
    if not pinned then
        return
    end
    local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
    local isGear = IsGearItem(itemLink)
    -- Pin key is the normalized itemID+bonusIDs identity (distinguishes
    -- upgrade tracks -- see NormalizePinKey in CludesUIBags.lua); pinKey == info.itemID
    -- when no link is available. A legacy itemID-keyed pin (written before
    -- this fix, conflating every track) is adopted into `cur` once and
    -- then always cleared here, regardless of which specific track was
    -- clicked -- there's no way to know which track a legacy entry
    -- originally meant, so the honest self-heal is "this interaction
    -- resolves the ambiguity," not "this interaction guesses which track
    -- it was." Re-pin afterward to set a precise, track-specific entry.
    local pinKey = NormalizePinKey(itemLink, details.itemID)
    local legacyCur = pinned[details.itemID] or 0
    local current = pinned[pinKey] or 0
    if legacyCur > 0 and current == 0 then
        current = legacyCur
    end
    pinned[details.itemID] = nil
    if isGear then
        -- Gear: per-stack count toggle
        if current > 0 then
            current = current - 1
            pinned[pinKey] = current > 0 and current or nil
        else
            pinned[pinKey] = current + 1
        end
    else
        -- Non-gear: pin/unpin all stacks at once
        if current > 0 then
            pinned[pinKey] = nil
        else
            pinned[pinKey] = 999
        end
    end
    if CUI_Bags.RefreshInventory then
        CUI_Bags:RefreshInventory()
    end
end
mod.SlotMiddleClick = SlotMiddleClick

-- Right-click deposit routing: with a bank tab selected, queue the transfer instead of
-- Blizzard's default first-free-slot routing (queue handles locked items/allocation so rapid
-- clicks don't collide). State lives in an EXTERNAL weak table, never on the frame: PreClick
-- custom keys taint the secure chain -> ADDON_ACTION_FORBIDDEN. Shared by grid slots and list rows.
function mod.BankRoutePreClick(self, btnFrame)
    if btnFrame ~= "RightButton" then
        return
    end
    local bank = _G.CUI_BankFrame
    if not bank or not bank:IsVisible() then
        return
    end
    local targetBag = bank:GetSelectedTabBagID()
    if not targetBag then
        return
    end
    local srcBag = self:GetParent():GetID()
    local srcSlot = self:GetID()
    if not srcBag or not srcSlot or srcSlot == 0 then
        return
    end
    local details = C_Container.GetContainerItemInfo(srcBag, srcSlot)
    if not details then
        return
    end
    bank:QueueTransfer(srcBag, srcSlot)
    _bankRouted[self] = true
end
function mod.BankRouteOnClick(self, btnFrame)
    if btnFrame == "RightButton" and _bankRouted[self] then
        _bankRouted[self] = nil
        ClearCursor()
    end
end

local function GetOrCreateReagentSlot(position)
    if reagentSlots[position] then
        return reagentSlots[position]
    end
    -- Never create a secure button during combat (taint). See GetOrCreateSlot.
    if InCombatLockdown() then
        CUI_Bags._poolShort = true
        return nil
    end

    local slotParent = CreateFrame("Frame", nil, CUI_BagsReagent)
    mod.SizeSlot(slotParent)
    local button = CreateFrame("ItemButton", nil, slotParent, "ContainerFrameItemButtonTemplate")
    mod.PinItemButton(button, CUI_BagsReagent)
    button:SetAllPoints(slotParent)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    -- Methods only: writing properties onto Blizzard template sub-objects taints
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
        button.icon:ClearAllPoints()
        button.icon:SetAllPoints(button)
    end

    local ht = button:GetHighlightTexture()
    if ht then
        ht:ClearAllPoints()
        ht:SetAllPoints(button)
    end
    local pt = button:GetPushedTexture()
    if pt then
        pt:SetAtlas(nil)
        pt:SetTexture("Interface\\AddOns\\CludesUIBags\\Media\\highlight-3.png")
        pt:SetTexCoord(0, 1, 0, 1)
        pt:ClearAllPoints()
        pt:SetAllPoints(button)
        pt:SetVertexColor(0.973, 0.839, 0.604, 1)
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

    if button.Cooldown then
        local cdText = button.Cooldown:GetRegions()
        if cdText and cdText.SetFont then
            CludesUI.ApplyIconTextFont(cdText, GetFont(), 11, "bags")
        end
    end

    CreateInsetBorder(button, true)
    SetInsetBorderColor(button, 0.25, 0.25, 0.25, 1)

    -- Text overlay: above the cooldown swipe, so counts and item levels stay visible
    local textOverlay = CreateFrame("Frame", nil, button)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel(button:GetFrameLevel() + 3)
    button._textOverlay = textOverlay

    local countFS = button.Count
    if countFS then
        countFS:SetParent(textOverlay)
        CludesUI.ApplyIconTextFont(countFS, GetFont(), BP().bagCountFontSize or 11, "bags")
        countFS:ClearAllPoints()
        countFS:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    end

    if not button.ItemLevelText then
        button.ItemLevelText = textOverlay:CreateFontString(nil, "OVERLAY", nil, 7)
        button.ItemLevelText:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        button.ItemLevelText:SetTextColor(1, 1, 1, 1)
    end
    local fontSize = BP().itemlevelFontSize or 12
    button.ItemLevelText:SetFont(
        STANDARD_TEXT_FONT,
        fontSize,
        (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    )
    button.ItemLevelText:SetText("")

    button:HookScript("PostClick", function(self)
        CUI_Bags.ShowStackSplitter(self, mod.SplitTargetBags(5), CUI_BagsReagent)
    end)

    reagentSlots[position] = button
    return button
end

-- Builds the secure item-button pools up to the current bag sizes (main pool = bags 0-5,
-- reagent pool = bag 5), creating only the slots that do not exist yet and hiding only
-- those. Stops at the first slot the combat guard refuses, or once msBudget (ms, optional)
-- is spent; either way CUI_Bags._poolShort stays set so combat end tops the pool up.
-- Returns true when both pools are complete. Callers: the loading-screen pass on a
-- /reload in combat, StartAddon, and PLAYER_REGEN_ENABLED.
function CUI_Bags:WarmSlotPool(msBudget)
    local t0 = msBudget and debugprofilestop()
    local sum = 0
    for bag = 0, 5 do
        sum = sum + (C_Container.GetContainerNumSlots(bag) or 0)
    end
    -- Only the pool for the latched display mode is built; mode unknown
    -- (profile not loaded yet) builds neither and retries at combat end.
    local listMode = CUI_Bags.IsListMode()
    if listMode == nil then
        CUI_Bags._poolShort = true
    elseif listMode then
        -- Pinned and Recent repeat their items as extra rows
        local pinned = PinnedItems()
        if pinned then
            for _ in pairs(pinned) do
                sum = sum + 1
            end
        end
        if CUI_Bags._recentItems then
            for _ in pairs(CUI_Bags._recentItems) do
                sum = sum + 1
            end
        end
        if not mod.WarmListRows(sum, t0, msBudget) then
            return false
        end
    else
        for i = 1, sum do
            if not itemSlots[i] then
                local b = mod.GetOrCreateSlot(i)
                if not b then
                    CUI_Bags._poolShort = true
                    return false
                end
                b:GetParent():Hide()
                if t0 and debugprofilestop() - t0 > msBudget then
                    CUI_Bags._poolShort = true
                    return false
                end
            end
        end
    end
    for i = 1, (C_Container.GetContainerNumSlots(5) or 0) do
        if not reagentSlots[i] then
            local b = GetOrCreateReagentSlot(i)
            if not b then
                CUI_Bags._poolShort = true
                return false
            end
            b:GetParent():Hide()
            if t0 and debugprofilestop() - t0 > msBudget then
                CUI_Bags._poolShort = true
                return false
            end
        end
    end
    return true
end

local function GetOrCreateBagSlot(position)
    if bagSlots[position] then
        return bagSlots[position]
    end
    local slotParent = CreateFrame("Frame", nil, CUI_BagsWindow)
    mod.SizeSlot(slotParent)
    local button = CreateFrame("Button", nil, slotParent)
    button:SetAllPoints(slotParent)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    local zoom = BP().bagItemIconZoom or 0.08
    button.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    button.icon:SetAllPoints(button)
    button.Count = button:CreateFontString(nil, "OVERLAY")
    CludesUI.ApplyIconTextFont(button.Count, GetFont(), BP().bagCountFontSize or 11, "bags")
    button.Count:SetPoint("BOTTOMRIGHT", -2, 2)
    button.Count:SetTextColor(1, 1, 1)
    CreateInsetBorder(button, true)
    SetInsetBorderColor(button, 0.25, 0.25, 0.25, 1)

    -- Drag-and-drop: equip a bag into this slot, or swap it with the
    -- equipped bag on the cursor
    local function TrySwapBag(self)
        if InCombatLockdown() then
            return
        end
        if not CursorHasItem() then
            return
        end
        local bagID = self:GetID()
        if bagID == 0 then
            return
        end -- can't replace backpack
        PutItemInBag(C_Container.ContainerIDToInventoryID(bagID))
    end
    button:SetScript("OnReceiveDrag", TrySwapBag)
    button:HookScript("OnClick", TrySwapBag)
    -- Drag an equipped bag out of its slot (drop it on another slot to swap)
    button:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then
            return
        end
        local bagID = self:GetID()
        if bagID == 0 then
            return
        end -- the backpack can't be moved
        PickupBagFromSlot(C_Container.ContainerIDToInventoryID(bagID))
    end)

    -- Tooltip: bag name + used/total slots (computed live on hover)
    button:SetScript("OnEnter", function(self)
        SetInsetBorderColor(self, 1, 1, 1, 1)
        local bagIdx = self:GetID()
        local bName
        if bagIdx == 0 then
            bName = "Backpack"
        else
            local bLink = GetInventoryItemLink("player", C_Container.ContainerIDToInventoryID(bagIdx))
            bName = bLink and GetItemInfo(bLink) or CUI.Lf("Bag %1$d", bagIdx)
        end
        local bTotal = C_Container.GetContainerNumSlots(bagIdx)
        local bFree = C_Container.GetContainerNumFreeSlots(bagIdx)
        local tipText = bName
        if bTotal > 0 then
            tipText = tipText .. "  (" .. (bTotal - bFree) .. "/" .. bTotal .. ")"
        end
        CUI.ShowWidgetTooltip(self, tipText)
    end)
    button:SetScript("OnLeave", function(self)
        SetInsetBorderColor(self, self._bdrR, self._bdrG, self._bdrB, 1)
        CUI.HideWidgetTooltip()
    end)

    bagSlots[position] = button
    return button
end

-------------------------------------------------------------------------------
--  Fast font size update (options sliders): no full RefreshInventory
-------------------------------------------------------------------------------
local function RefreshTextSizes()
    local fontFile = GetFont()
    local countSize = BP().bagCountFontSize or 11
    local ilvlSize = BP().itemlevelFontSize or 12
    local bindTypeSize = BP().bagBindTypeFontSize or 11
    for _, button in pairs(itemSlots) do
        if button.Count then
            CludesUI.ApplyIconTextFont(button.Count, fontFile, countSize, "bags")
        end
        if button.ItemLevelText then
            button.ItemLevelText:SetFont(
                fontFile,
                ilvlSize,
                (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
            )
        end
        if button.KeystoneText then
            button.KeystoneText:SetFont(
                fontFile,
                countSize,
                (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
            )
        end
        if button.KeystoneDungeonText then
            button.KeystoneDungeonText:SetFont(
                fontFile,
                math.max(countSize - 2, 7),
                (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
            )
        end
        if button.BindTypeText then
            button.BindTypeText:SetFont(
                fontFile,
                bindTypeSize,
                (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
            )
        end
        if button.SetNameText then
            button.SetNameText:SetFont(
                fontFile,
                BP().bagSetNameFontSize or 9,
                (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
            )
        end
    end
    for _, button in pairs(reagentSlots) do
        if button.Count then
            CludesUI.ApplyIconTextFont(button.Count, fontFile, countSize, "bags")
        end
        if button.ItemLevelText then
            button.ItemLevelText:SetFont(
                STANDARD_TEXT_FONT,
                ilvlSize,
                (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
            )
        end
    end
end
CUI_Bags.RefreshTextSizes = RefreshTextSizes

-------------------------------------------------------------------------------
--  Fast icon-zoom update (options zoom cog): no full RefreshInventory
-------------------------------------------------------------------------------
local function RefreshIconZoom()
    local zoom = BP().bagItemIconZoom or 0.08
    for _, button in pairs(itemSlots) do
        if button.icon then
            button.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
    end
    for _, button in pairs(reagentSlots) do
        if button.icon then
            button.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
    end
    for _, button in pairs(bagSlots) do
        if button.icon then
            button.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
    end
end
CUI_Bags.RefreshIconZoom = RefreshIconZoom

-------------------------------------------------------------------------------
--  Bind type text (shared by bags and bank render paths)
-------------------------------------------------------------------------------
-- WuE items report bindType == OnEquip (no dedicated enum): check WuE first.
function CUI_Bags.SetBindTypeText(fontStr, isWuE, bindType, quality)
    local c
    if isWuE then
        c = ITEM_QUALITY_COLORS[7] -- Heirloom color (no quality enum for WuE)
        fontStr:SetText(CludesUI.L("WuE"))
    elseif bindType == Enum.ItemBind.OnEquip then
        c = ITEM_QUALITY_COLORS[quality]
        fontStr:SetText(CludesUI.L("BoE"))
    else
        fontStr:SetText("")
        return
    end
    if c then
        fontStr:SetTextColor(c.r, c.g, c.b)
    else
        fontStr:SetTextColor(1, 1, 1)
    end
end

-------------------------------------------------------------------------------
--  Bind keyword search (shared by bags and bank): typing BoP / BoE / WuE / BoA /
--  Soulbound / Warbound (any case), optionally with an item level (bop=300,
--  wue 290-300, boe>=280), filters by bind type instead of the native tooltip
--  search.
-------------------------------------------------------------------------------
-- In a block so the main chunk's local count (close to the 200 cap) stays put.
do
    local BIND_KEYWORDS = {
        bop = true,
        boe = true,
        wue = true,
        boa = true,
        soulbound = true,
        warbound = true,
    }

    -- Bind expressions: terms joined with and / or / not (also & | !) and
    -- parentheses, not > and > or; terms side by side mean and. A term is a
    -- keyword with an optional item level: "<keyword>", "<keyword> <op><ilvl>"
    -- (op: = == > >= < <=; a bare number means =) or "<keyword> <ilvl>-<ilvl>",
    -- e.g. "bop=300", "wue 290-300", "boe and not wue", "(bop or boe) and
    -- soulbound". Anything else parses to nil and goes to the native search
    -- untouched.
    local OPS = { ["="] = "=", ["=="] = "=", [">"] = ">", [">="] = ">=", ["<"] = "<", ["<="] = "<=" }
    local MAX_DEPTH = 12

    local function Tokenize(s)
        local toks, i, n = {}, 1, #s
        while i <= n do
            local c = s:sub(i, i)
            if c:find("^%s") then
                i = i + 1
            elseif c == "(" then
                toks[#toks + 1] = { k = "lp" }
                i = i + 1
            elseif c == ")" then
                toks[#toks + 1] = { k = "rp" }
                i = i + 1
            elseif c == "!" then
                toks[#toks + 1] = { k = "not" }
                i = i + 1
            elseif c == "&" then
                toks[#toks + 1] = { k = "and" }
                i = i + #s:match("^&&?", i)
            elseif c == "|" then
                toks[#toks + 1] = { k = "or" }
                i = i + #s:match("^||?", i)
            elseif c:find("^[<>=]") then
                local op = s:match("^[<>=]=?", i)
                if not OPS[op] then
                    return nil
                end
                toks[#toks + 1] = { k = "op", v = OPS[op] }
                i = i + #op
            elseif c:find("^%d") then
                local a, b, e = s:match("^(%d+)%s*%-%s*(%d+)()", i)
                if a then
                    toks[#toks + 1] = { k = "range", lo = tonumber(a), hi = tonumber(b) }
                    i = e
                else
                    local skinData = s:match("^%d+", i)
                    toks[#toks + 1] = { k = "num", v = tonumber(skinData) }
                    i = i + #skinData
                end
            elseif c:find("^%a") then
                local wid = s:match("^%a+", i)
                i = i + #wid
                if wid == "and" or wid == "or" or wid == "not" then
                    toks[#toks + 1] = { k = wid }
                elseif BIND_KEYWORDS[wid] then
                    toks[#toks + 1] = { k = "kw", v = wid }
                else
                    return nil
                end
            else
                return nil
            end
        end
        return toks
    end

    local function ParseBindQuery(textValue)
        local toks = Tokenize(strtrim(textValue or ""):lower())
        if not toks or #toks == 0 then
            return nil
        end
        local p = 1
        local ParseOr

        local function ParsePrimary(depth)
            local t = toks[p]
            if not t then
                return nil
            end
            if t.k == "lp" then
                if depth >= MAX_DEPTH then
                    return nil
                end
                p = p + 1
                local e = ParseOr(depth + 1)
                if not e or not toks[p] or toks[p].k ~= "rp" then
                    return nil
                end
                p = p + 1
                return e
            end
            if t.k ~= "kw" then
                return nil
            end
            p = p + 1
            local node = { t = "term", kw = t.v }
            local nx = toks[p]
            if nx and nx.k == "op" then
                local num = toks[p + 1]
                if not num or num.k ~= "num" then
                    return nil
                end
                node.op, node.lo = nx.v, num.v
                p = p + 2
            elseif nx and nx.k == "range" then
                node.op, node.lo, node.hi = "-", math.min(nx.lo, nx.hi), math.max(nx.lo, nx.hi)
                p = p + 1
            elseif nx and nx.k == "num" then
                node.op, node.lo = "=", nx.v
                p = p + 1
            end
            return node
        end

        local function ParseNot(depth)
            local t = toks[p]
            if t and t.k == "not" then
                if depth >= MAX_DEPTH then
                    return nil
                end
                p = p + 1
                local a = ParseNot(depth + 1)
                return a and { t = "not", a = a }
            end
            return ParsePrimary(depth)
        end

        local function ParseAnd(depth)
            local l = ParseNot(depth)
            -- Terms side by side ("wue290-300 not warbound") mean and.
            while
                l
                and toks[p]
                and (toks[p].k == "and" or toks[p].k == "kw" or toks[p].k == "not" or toks[p].k == "lp")
            do
                if toks[p].k == "and" then
                    p = p + 1
                end
                local region = ParseNot(depth)
                l = region and { t = "and", a = l, b = region }
            end
            return l
        end

        ParseOr = function(depth)
            local l = ParseAnd(depth)
            while l and toks[p] and toks[p].k == "or" do
                p = p + 1
                local region = ParseAnd(depth)
                l = region and { t = "or", a = l, b = region }
            end
            return l
        end

        local root = ParseOr(0)
        if root and p == #toks + 1 then
            return root
        end
        return nil
    end

    -- Facts about the item being tested, set by ApplyBindKeyword before each
    -- Eval; the item level and the WuE check are read only when a term asks.
    local curLink, curBound, curBindType, curIsAccount, curWue, curIlvl
    -- One location reused for every slot: a keyword pass visits every item on
    -- each refresh, and CreateFromBagAndSlot builds a new mixin table per call.
    local loc = ItemLocation:CreateEmpty()
    local GetItemLevelAtLocation = Inner.GetItemLevelAtLocation

    -- The level the slot shows: the item's current level at its location.
    local function ItemLevelMatches(q)
        if curIlvl == nil then
            curIlvl = GetItemLevelAtLocation(loc, curLink) or false
        end
        local ilvl = curIlvl
        if not ilvl then
            return false
        end
        local op, lo = q.op, q.lo
        if op == "=" then
            return ilvl == lo
        end
        if op == ">" then
            return ilvl > lo
        end
        if op == ">=" then
            return ilvl >= lo
        end
        if op == "<" then
            return ilvl < lo
        end
        if op == "<=" then
            return ilvl <= lo
        end
        return ilvl >= lo and ilvl <= q.hi
    end

    local function TermMatches(q)
        local key = q.kw
        local match = false
        if key == "bop" then
            match = curBindType == Enum.ItemBind.OnAcquire
        elseif key == "boa" then
            match = curBindType == Enum.ItemBind.ToWoWAccount
        elseif key == "soulbound" then
            -- Account-bound items are bound too, but are not soulbound.
            match = curBound and not curIsAccount
        elseif key == "warbound" then
            -- Either account bind type (Bind to Account, Binds to Warband) once
            -- bound.
            match = curBound and curIsAccount
        elseif not curBound then
            -- BoE and WuE both mean "not bound yet". WuE reads as OnEquip from
            -- GetItemInfo, so the account check tells the two apart.
            if curWue == nil then
                curWue = C_Item.IsBoundToAccountUntilEquip(loc) and true or false
            end
            if key == "wue" then
                match = curWue
            else
                match = not curWue and curBindType == Enum.ItemBind.OnEquip
            end
        end
        if match and q.op then
            match = ItemLevelMatches(q)
        end
        return match and true or false
    end

    local function Eval(n)
        local t = n.t
        if t == "term" then
            return TermMatches(n)
        end
        if t == "not" then
            return not Eval(n.a)
        end
        if t == "and" then
            return Eval(n.a) and Eval(n.b)
        end
        return Eval(n.a) or Eval(n.b)
    end

    -- The game applies a search after SetItemSearch returns and reports the
    -- result with INVENTORY_SEARCH_UPDATE, the event Blizzard's own bags repaint
    -- on, so the open windows repaint there, never at once (they would still
    -- show the previous search). Listened to from a search change until the
    -- search is clear again or no window shows (the next open reads the
    -- settled result).
    local searchWatch
    local function OnSearchUpdate(self)
        local bank = _G.CUI_BankFrame
        if CUI_Bags._appliedSearch == "" or not (CUI_Bags:IsVisible() or (bank and bank:IsVisible())) then
            self:UnregisterEvent("INVENTORY_SEARCH_UPDATE")
        end
        if CUI_Bags:IsVisible() then
            CUI_Bags:RefreshInventory()
        end
        if BP().detachReagentBag and CUI_BagsReagent:IsVisible() then
            CUI_BagsReagent:RefreshInventory()
        end
        mod.RefreshOpenBank()
    end

    -- The game's item search is client-wide and has no getter, so this is its
    -- one writer and keeps the text it last applied: a search box asking for
    -- that same text has nothing to change or repaint.
    function CUI_Bags.SetSearchText(textValue)
        CUI_Bags._bindKeyword = ParseBindQuery(textValue)
        CUI_Bags._appliedSearch = textValue
        if not searchWatch then
            searchWatch = CreateFrame("Frame")
            searchWatch:SetScript("OnEvent", OnSearchUpdate)
        end
        searchWatch:RegisterEvent("INVENTORY_SEARCH_UPDATE")
        C_Container.SetItemSearch(textValue)
    end

    -- Text changes of a search box (the bags and the bank each have one):
    -- typing applies SEARCH_DEBOUNCE seconds after the last keystroke, so a
    -- burst of keystrokes repaints once; any other change (the clear button,
    -- Escape, a window opening or closing) applies at once. A text the game's
    -- search already holds does nothing. apply(text) writes the search (the
    -- windows repaint when the game reports it, see SetSearchText). Returns
    -- the box's change handler.
    local SEARCH_DEBOUNCE = 0.1
    function CUI_Bags.WatchSearchBox(box, apply)
        local armed, lastKeyAt = false, 0
        local function flush()
            local wait = lastKeyAt + SEARCH_DEBOUNCE - GetTime()
            if wait > 0 then
                C_Timer.After(wait, flush)
                return
            end
            armed = false
            local textValue = box:GetText()
            if textValue ~= CUI_Bags._appliedSearch then
                apply(textValue)
            end
        end
        return function(userInput)
            if userInput then
                lastKeyAt = GetTime()
                if not armed then
                    armed = true
                    C_Timer.After(SEARCH_DEBOUNCE, flush)
                end
                return
            end
            local textValue = box:GetText()
            if textValue ~= CUI_Bags._appliedSearch then
                apply(textValue)
            end
        end
    end

    -- Clears the game's search unless it is already clear (the clear buttons,
    -- Escape and the bank's open and close, after emptying their box).
    function CUI_Bags.ClearSearch()
        if CUI_Bags._appliedSearch ~= "" then
            CUI_Bags.SetSearchText("")
        end
    end

    -- Overrides info.isFiltered for the active expression; no-op when none is active.
    function CUI_Bags.ApplyBindKeyword(details, bag, slot)
        local q = CUI_Bags._bindKeyword
        if not q or not details then
            return
        end
        local match = false
        loc:SetBagAndSlot(bag, slot)
        if C_Item.DoesItemExist(loc) then
            curLink, curBound = details.hyperlink, details.isBound
            curBindType = curLink and select(14, GetItemInfo(curLink))
            curIsAccount = curBindType == Enum.ItemBind.ToWoWAccount
                or curBindType == Enum.ItemBind.ToBnetAccount
            curWue, curIlvl = nil, nil
            match = Eval(q)
        end
        details.isFiltered = not match
    end
end

-------------------------------------------------------------------------------
--  Item border color (shared by bags and bank render paths)
-------------------------------------------------------------------------------
-- Quality Item Border: the item's quality color while the option is on (every
-- display), else the neutral grey an unknown quality gets.
function mod.QualityBorderColor(quality)
    local c
    if BP().bagQualityBorder ~= false then
        if mod.BagsForever() and ColorManager and ColorManager.GetColorDataForBagItemQuality then
            c = ColorManager.GetColorDataForBagItemQuality(quality)
        else
            c = ITEM_QUALITY_COLORS[quality]
        end
    end
    if c then
        return c.r, c.g, c.b
    end
    return 0.25, 0.25, 0.25
end

-------------------------------------------------------------------------------
--  Third-party item overlay icons (opt-in extension point for compatibility bridges with addons like CanIMogIt)
-------------------------------------------------------------------------------
-- Public API (other addons call it): updateFn(btn, data) runs for every
-- painted slot in the bags, the reagent bag and the bank, grid slots and List
-- view rows alike. btn is our secure container item button: keep state off it
-- (parent frames to btn._textOverlay, which covers the item icon, and track
-- them in your own table), never touch it from a click handler.
-- data = { bag, slot, info, itemLink }, valid during the call only (the bank
-- reuses one table); placeholder slots pass bag 0 / slot 0 and no item. A
-- painter error is reported and never stops our render.
CUI_Bags.itemOverlayIcons = CUI_Bags.itemOverlayIcons or {}

function CUI_Bags.RegisterItemOverlayIcon(name, updateFn)
    CUI_Bags.itemOverlayIcons[name] = updateFn
end

function CUI_Bags.UnregisterItemOverlayIcon(name)
    CUI_Bags.itemOverlayIcons[name] = nil
end

function CUI_Bags.RunItemOverlays(button, payload)
    local fns = CUI_Bags.itemOverlayIcons
    if next(fns) == nil then
        return
    end
    for _, func in pairs(fns) do
        securecallfunction(func, button, payload)
    end
end

Inner._itemDragFrame, Inner.GetOrCreateBagSlot = _itemDragFrame, GetOrCreateBagSlot
Inner.GetOrCreateReagentSlot = GetOrCreateReagentSlot
Inner.broken = false
