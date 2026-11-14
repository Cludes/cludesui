if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Bags_Header.lua
--
--  The header bar: title, search, sort and the header buttons.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local mod = select(2, ...)
local Inner = mod._bagsInternals
-- CludesUIBags.lua or an earlier CUI_Bags_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local CUI = CludesUI

local BP, GetFont, SetBagFont, HEADER_H = Inner.BP, Inner.GetFont, Inner.SetBagFont, Inner.HEADER_H
local PreCacheSortFields, SaveCategoryOrder = Inner.PreCacheSortFields, Inner.SaveCategoryOrder
local VisualSortCompare = Inner.VisualSortCompare

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._bagsInternals, which hands the value to every copy.
local selectedCategoryIndex = Inner.selectedCategoryIndex
Inner.categoryIndexSetters[#Inner.categoryIndexSetters + 1] = function(val)
    selectedCategoryIndex = val
end

-------------------------------------------------------------------------------
--  UI Components -- Header
-------------------------------------------------------------------------------
-- Fits the title and item count between their start and the leftmost header icon
-- (SyncHeaderIcons): the count truncates first, then the title, both with "...".
function CUI_Bags:FitHeaderText()
    local heading, edge = self.Header, self._hdrEdge
    if not (heading and edge) then
        return
    end
    local titleText, count = heading.title, heading.itemCount
    local tl, el = titleText:GetLeft(), edge:GetLeft()
    if not (tl and el) then
        return
    end
    if heading.slotLines then
        heading.slotLines[1]:Hide()
        heading.slotLines[2]:Hide()
    end
    local room = el - 12 - tl
    local tw = titleText:GetUnboundedStringWidth()
    if tw > room then
        titleText:SetWidth(math.max(room, 1))
        count:SetAlpha(0)
        return
    end
    titleText:SetWidth(tw + 1)
    local countRoom = room - tw - 8
    local first, second = (count:GetText() or ""):match("^([^\n]+)\n(.+)$")
    if first then
        -- Each capacity line truncates independently instead of wrapping into the other.
        if not heading.slotLines then
            heading.slotLines = {}
            for i = 1, 2 do
                local lineTex = heading:CreateFontString(nil, "OVERLAY")
                SetBagFont(lineTex, 11)
                lineTex:SetWordWrap(false)
                lineTex:SetJustifyH("LEFT")
                heading.slotLines[i] = lineTex
            end
        end
        local _, dim = count:GetFont()
        local r, g, b = count:GetTextColor()
        for i = 1, 2 do
            local lineTex = heading.slotLines[i]
            lineTex:SetFont(count:GetFont())
            lineTex:SetTextColor(r, g, b, 1)
            lineTex:SetPoint("LEFT", titleText, "RIGHT", 8, i == 1 and dim / 2 or -dim / 2)
            lineTex:SetText(i == 1 and first or second)
            lineTex:SetWidth(math.max(math.min(lineTex:GetUnboundedStringWidth() + 1, countRoom), 1))
            lineTex:SetShown(countRoom >= 16)
        end
        count:SetAlpha(0)
        return
    end
    count:SetWidth(math.max(math.min(count:GetUnboundedStringWidth() + 1, countRoom), 1))
    count:SetAlpha(countRoom >= 16 and 1 or 0)
end

local function CreateHeader()
    if CUI_Bags.Header then
        return
    end
    local forever = mod.BagsForever()
    local headerFrame = CreateFrame("Frame", nil, CUI_Bags)
    headerFrame:SetPoint("TOPLEFT", 1, -1)
    headerFrame:SetPoint("TOPRIGHT", -1, -1)
    if forever then
        mod.LayoutForeverBagHeader(headerFrame)
    else
        headerFrame:SetHeight(HEADER_H)
    end
    headerFrame.bg = headerFrame:CreateTexture(nil, "BACKGROUND")
    headerFrame.bg:SetAllPoints()
    headerFrame.bg:SetColorTexture(0, 0, 0, 0.5)

    headerFrame.title = headerFrame:CreateFontString(nil, "OVERLAY")
    SetBagFont(headerFrame.title, 13)
    headerFrame.title:SetPoint("LEFT", headerFrame, "LEFT", 8, 0)
    headerFrame.title:SetText(CludesUI.L("Inventory"))
    headerFrame.title:SetTextColor(1, 1, 1)

    -- Item count (updated by RefreshInventory)
    headerFrame.itemCount = headerFrame:CreateFontString(nil, "OVERLAY")
    SetBagFont(headerFrame.itemCount, 11)
    headerFrame.itemCount:SetPoint("LEFT", headerFrame.title, "RIGHT", 8, 0)
    headerFrame.itemCount:SetTextColor(0.6, 0.6, 0.6)

    -- Title and count stop short of the header icons (CUI_Bags:FitHeaderText),
    -- refitted whenever either text, the title's spot or the header width changes.
    headerFrame.title:SetWordWrap(false)
    headerFrame.title:SetJustifyH("LEFT")
    headerFrame.itemCount:SetWordWrap(false)
    headerFrame.itemCount:SetJustifyH("LEFT")
    if not forever then
        local function Fit()
            CUI_Bags:FitHeaderText()
        end
        hooksecurefunc(headerFrame.title, "SetText", Fit)
        hooksecurefunc(headerFrame.title, "SetPoint", Fit)
        hooksecurefunc(headerFrame.itemCount, "SetText", Fit)
        headerFrame:HookScript("OnSizeChanged", Fit)
        headerFrame:HookScript("OnShow", Fit)
    end

    local search = CreateFrame("EditBox", "CUI_BagSearchBox", headerFrame)
    search:SetSize(160, 22)
    search:SetPoint("RIGHT", -35, 0)
    search:SetFont(GetFont(), 12, CUI.GetFontOutlineFlag("bags"))
    search:SetAutoFocus(false)
    search:SetTextInsets(5, 26, 0, 0)
    search.bg = search:CreateTexture(nil, "BACKGROUND")
    search.bg:SetAllPoints()
    search.bg:SetColorTexture(0.02, 0.02, 0.02, 1)
    if not forever and CUI.PanelPP then
        CUI.PanelPP.CreateBorder(search, 0.25, 0.25, 0.25, 1, 1, "OVERLAY", 7)
    end

    local placeholder = search:CreateFontString(nil, "OVERLAY")
    SetBagFont(placeholder, 11)
    placeholder:SetPoint("LEFT", search, "LEFT", 5, 0)
    placeholder:SetText(CludesUI.L("Search..."))
    placeholder:SetTextColor(0.4, 0.4, 0.4)
    CUI_Bags._searchBox = search

    local sort = CreateFrame("Button", nil, headerFrame)
    sort:SetSize(24, 24)
    sort:SetPoint("RIGHT", search, "LEFT", -13, 0)
    sort.icon = sort:CreateTexture(nil, "OVERLAY")
    sort.icon:SetAllPoints()
    sort.icon:SetTexture("Interface\\AddOns\\CludesUIBags\\Media\\clean-up.png")
    sort.icon:SetAlpha(0.9)

    if forever then
        headerFrame.bg:Hide()
        mod.AddForeverBagPortrait(headerFrame, "Interface\\Icons\\Inv_misc_bag_08")
        mod.SkinForeverBagTitle(headerFrame.title, headerFrame.itemCount)
        sort:ClearAllPoints()
        sort:SetPoint("RIGHT", headerFrame, "TOPRIGHT", -9, headerFrame._foreverToolsY)
    end

    sort:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        CUI.ShowWidgetTooltip(self, "Sort Items")
    end)
    sort:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        CUI.HideWidgetTooltip()
    end)

    local sortLocked = false
    -- Sorts that move items (OneBag, MultiBag) wait out combat; the other
    -- views' sort only reorders the display.
    local function SortMovesItems()
        return selectedCategoryIndex == -1 or selectedCategoryIndex == -2
    end
    -- The sort button is clickable only while no sort runs, and where it
    -- moves items only out of combat.
    local function ApplySortEnabled()
        local enabled = not sortLocked and not (InCombatLockdown() and SortMovesItems())
        sort:EnableMouse(enabled)
        sort.icon:SetAlpha(enabled and 0.9 or 0.2)
    end
    -- A view switch in combat re-runs it from the refresh (FinishRefresh).
    CUI_Bags._applySortEnabled = ApplySortEnabled
    -- Combat edges only matter while the bags are open; the show edge catches
    -- up on any change while they were closed.
    local combatWatch = CreateFrame("Frame")
    combatWatch:SetScript("OnEvent", ApplySortEnabled)
    CUI_Bags:HookScript("OnShow", function()
        combatWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
        combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
        ApplySortEnabled()
    end)
    CUI_Bags:HookScript("OnHide", function()
        combatWatch:UnregisterEvent("PLAYER_REGEN_DISABLED")
        combatWatch:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end)
    -- One reusable BAG_UPDATE listener per role. Both phases are strictly
    -- sequential, and a fresh CreateFrame per round leaked frames per click
    -- (frames are never collected). The run token keeps a second sort from
    -- inheriting the first one's callbacks: EndDragDrop can unlock the button
    -- mid-run, and a stale callback clearing the live chain's OnEvent would
    -- strand it with refreshEnabled false (bags frozen until reload).
    local consolidateFrame, retryFrame
    local function LockSort()
        sortLocked = true
        ApplySortEnabled()
    end
    local function UnlockSort()
        if not sortLocked then
            return
        end
        sortLocked = false
        ApplySortEnabled()
    end
    CUI_Bags._unlockSort = UnlockSort

    local DoVisualSort -- forward declaration

    -- One physical sort at a time: a sidebar drag can unlock the button
    -- mid-run, and a second run would take the muted sound effects for the
    -- player's own and give them back muted.
    local physicalActive = false
    -- Combat ends a physical sort at its edge: PLAYER_REGEN_DISABLED comes
    -- before the lockdown, so no item moves in combat, and the cleanup (the
    -- sound effects back, the bags refreshed) runs while it is still allowed.
    -- Registered only while a physical sort runs, with CVAR_UPDATE (the player
    -- taking the muted sound effects over).
    local sortCombatStop = CreateFrame("Frame")
    -- Seconds a pass's item moves may take to show in a bag update before the
    -- run counts as stuck (ArmBackstop).
    local SORT_STUCK_AFTER = 5

    -- mergeOnly (category views): consolidate partial stacks, then the visual sort.
    local function DoPhysicalSort(mergeOnly)
        if InCombatLockdown() or physicalActive then
            return
        end -- confirm popup can outlive the pull
        physicalActive = true
        LockSort()
        CUI_Bags.refreshEnabled = false

        local sfxWas = GetCVar("Sound_EnableSFX")
        -- Blizzard's clean-up sound. Sound effects stay muted for the whole
        -- run (item moves), which would cut it short, so it goes out on the
        -- Master channel, and only while the player's sound effects are on
        -- and their volume is above zero.
        if sfxWas == "1" and (tonumber(GetCVar("Sound_SFXVolume")) or 0) > 0 then
            PlaySound(SOUNDKIT.UI_BAG_SORTING_01, "Master")
        end
        CludesUI.HoldCVar("Sound_EnableSFX", "0", "CludesUIBags")
        -- The player changed the sound effects while they were muted: the
        -- mute ends where it stands, and the run gives nothing back.
        local tookOver = false

        local FinishSort -- the run's end, below
        -- The run's waiting callbacks check their frame's token: cleared, they
        -- drop out. Either frame is made on first use.
        local function StopWaiting(f)
            if not f then
                return
            end
            f._runToken = nil
            f._wait = nil
            f:UnregisterAllEvents()
            f:SetScript("OnEvent", nil)
        end
        -- Fail-open backstop: a pass whose moves all fail (an item locked
        -- elsewhere: a mail attachment, the auction house, a trade) brings no
        -- bag update, and the run would wait for good, the bags frozen and the
        -- sound effects muted. A wait with no update SORT_STUCK_AFTER seconds
        -- on ends the run as finished; a sort cut short can simply run again.
        local function ArmBackstop(f, token)
            local wait = {}
            f._wait = wait
            C_Timer.After(SORT_STUCK_AFTER, function()
                if f._runToken ~= token or f._wait ~= wait then
                    return
                end
                StopWaiting(consolidateFrame)
                StopWaiting(retryFrame)
                FinishSort()
            end)
        end

        -----------------------------------------------------------------------
        --  Phase 1: consolidate partial stacks (smallest onto largest of the same itemID; the engine performs the combine).
        -----------------------------------------------------------------------
        local function ConsolidateStacks(onDone)
            -- Max stack size is a static per-itemID fact, but it was re-read
            -- through GetItemInfo for every occupied slot on every pass (up to
            -- 30 passes over six bags). Memo it for the run instead; the
            -- ItemLocation + DoesItemExist guard it used to sit behind is
            -- redundant, GetContainerItemInfo just returned the item.
            local maxStackByID = {}
            local function ByCount(a, b)
                return a.count < b.count
            end
            local function DoOnePass()
                if InCombatLockdown() then
                    return false
                end -- combat started: stop moving items
                local stacks = {} -- itemID -> { {bag,slot,count}, ... }
                -- A WoW Forever special bag's stacks merge only with each other
                -- (a key of their own), so nothing leaves or enters the bag.
                local special = mod.SpecialBags()
                for bag = 0, 5 do
                    local numSlots = C_Container.GetContainerNumSlots(bag)
                    for slotIndex = 1, numSlots do
                        local details = C_Container.GetContainerItemInfo(bag, slotIndex)
                        if details and details.itemID and details.stackCount then
                            local maxStack = maxStackByID[details.itemID]
                            if not maxStack then
                                maxStack = select(8, C_Item.GetItemInfo(details.itemID))
                                -- Uncached item data: don't memo the fallback,
                                -- a later pass can still resolve it.
                                if maxStack then
                                    maxStackByID[details.itemID] = maxStack
                                else
                                    maxStack = 1
                                end
                            end
                            if maxStack > 1 and details.stackCount < maxStack then
                                local key = details.itemID
                                if special and special[bag] then
                                    key = bag .. ":" .. key
                                end
                                if not stacks[key] then
                                    stacks[key] = {}
                                end
                                stacks[key][#stacks[key] + 1] = {
                                    bag = bag,
                                    slot = slotIndex,
                                    count = details.stackCount,
                                }
                            end
                        end
                    end
                end
                -- Emptiest partial merges into fullest, second-emptiest into
                -- second-fullest, and so on: every slot is touched at most
                -- once, so all pairs of this pass still fire same-frame -- but
                -- an item with 2n partial stacks now converges in log rounds
                -- instead of n BAG_UPDATE round trips. Overflow waits for a
                -- later pass, same as before.
                local merged = false
                for _, partials in pairs(stacks) do
                    local num = #partials
                    if num >= 2 then
                        table.sort(partials, ByCount)
                        local lo, hi = 1, num
                        while lo < hi do
                            local source, targetUnit = partials[lo], partials[hi]
                            local srcLoc = ItemLocation:CreateFromBagAndSlot(source.bag, source.slot)
                            local dstLoc = ItemLocation:CreateFromBagAndSlot(targetUnit.bag, targetUnit.slot)
                            if not C_Item.IsLocked(srcLoc) and not C_Item.IsLocked(dstLoc) then
                                C_Container.PickupContainerItem(source.bag, source.slot)
                                C_Container.PickupContainerItem(targetUnit.bag, targetUnit.slot)
                                ClearCursor()
                                merged = true
                            end
                            lo = lo + 1
                            hi = hi - 1
                        end
                    end
                end
                return merged
            end

            if not DoOnePass() then
                onDone()
                return
            end

            local consolidateRetry = 0
            if not consolidateFrame then
                consolidateFrame = CreateFrame("Frame")
            end
            local runToken = {}
            consolidateFrame._runToken = runToken
            consolidateFrame:RegisterEvent("BAG_UPDATE")
            ArmBackstop(consolidateFrame, runToken)
            consolidateFrame:SetScript("OnEvent", function(self)
                if self._runToken ~= runToken then
                    return
                end
                self._wait = nil
                self:UnregisterAllEvents()
                consolidateRetry = consolidateRetry + 1
                C_Timer.After(0.15, function()
                    if consolidateFrame._runToken ~= runToken then
                        return
                    end
                    if consolidateRetry < 30 and DoOnePass() then
                        self:RegisterEvent("BAG_UPDATE")
                        ArmBackstop(self, runToken)
                    else
                        self:SetScript("OnEvent", nil)
                        onDone()
                    end
                end)
            end)
        end

        -----------------------------------------------------------------------
        --  Phase 2: Sort
        -----------------------------------------------------------------------

        -- Scan, compute sorted order and execute all moves in one pass; re-scans every call so retries work from fresh state.
        local function ComputeAndExecute(bagMin, bagMax)
            if InCombatLockdown() then
                return false
            end -- combat started: stop moving items
            bagMin = bagMin or 0
            bagMax = bagMax or 4
            local sum = 0
            local sBag, sSlot, sKey, sID = {}, {}, {}, {}

            local itemList = {}
            -- A WoW Forever special bag adds no slots: its items stay put and
            -- nothing is moved into it.
            local special = mod.SpecialBags()
            for bag = bagMin, bagMax do
                local numSlots = (special and special[bag]) and 0 or C_Container.GetContainerNumSlots(bag)
                for slotIndex = 1, numSlots do
                    sum = sum + 1
                    sBag[sum] = bag
                    sSlot[sum] = slotIndex
                    local details = C_Container.GetContainerItemInfo(bag, slotIndex)
                    if details then
                        local link = C_Container.GetContainerItemLink(bag, slotIndex)
                        local key = link .. "\0" .. (details.stackCount or 0)
                        sKey[sum] = key
                        sID[sum] = details.itemID
                        itemList[#itemList + 1] = {
                            pos = sum,
                            bag = bag,
                            slot = slotIndex,
                            info = details,
                            itemLink = link,
                            key = key,
                        }
                    end
                end
            end

            if #itemList == 0 then
                return false
            end

            CUI_CategoryManager:ClassifyAll(itemList)
            local cats = CUI_CategoryManager:GetCategories()
            local sectionOrder = {}
            local ord = 0
            local doneGroups = {}
            for ci, category in ipairs(cats) do
                if category.groupName then
                    if not doneGroups[category.groupName] then
                        doneGroups[category.groupName] = true
                        ord = ord + 1
                        local members = CUI_CategoryManager:GetGroupMembers(category.groupName)
                        if members then
                            for _, mi in ipairs(members) do
                                sectionOrder[mi] = ord
                            end
                        end
                    end
                else
                    ord = ord + 1
                    sectionOrder[ci] = ord
                end
            end

            PreCacheSortFields(itemList)
            for _, d in ipairs(itemList) do
                d._sectionOrder = sectionOrder[d.categoryIndex] or 9999
            end
            table.sort(itemList, function(a, b)
                if a._sectionOrder ~= b._sectionOrder then
                    return a._sectionOrder < b._sectionOrder
                end
                return VisualSortCompare(a, b)
            end)

            -- Compute moves via selection sort on pre-computed data (zero API calls)
            local atPos = {}
            local whereIs = {}
            for position, d in ipairs(itemList) do
                atPos[d.pos] = position
                whereIs[position] = d.pos
            end

            -- Sorted item i targets slot i; Sort to Bottom offsets so the block lands in the LAST
            -- #items slots (free slots float up either way). The walk must move toward the free slots
            -- (forward for top, backward for bottom), or a displaced item lands in an already-visited slot -- costing a retry per move, risking the 15-retry cap.
            local offset, first, last, step = 0, 1, #itemList, 1
            if BP().bagSortToBottom then
                offset = sum - #itemList
                first, last, step = #itemList, 1, -1
            end

            local moves = {}
            for i = first, last, step do
                local t = i + offset
                local s = whereIs[i]
                if s ~= t then
                    local displaced = atPos[t]
                    if displaced and sID[s] and sID[t] and sID[s] == sID[t] then
                        -- Same itemID: skip to avoid merge, retry will resolve
                    else
                        moves[#moves + 1] = { sBag[s], sSlot[s], sBag[t], sSlot[t] }
                        whereIs[i] = t
                        if displaced then
                            whereIs[displaced] = s
                        end
                        atPos[t] = i
                        atPos[s] = displaced
                        sID[s], sID[t] = sID[t], sID[s]
                        sKey[s], sKey[t] = sKey[t], sKey[s]
                    end
                end
            end

            for _, m in ipairs(moves) do
                C_Container.PickupContainerItem(m[1], m[2])
                C_Container.PickupContainerItem(m[3], m[4])
                ClearCursor()
            end

            return #moves > 0
        end

        -- combat: ended at the combat edge, so the bags refresh at once, still
        -- outside the lockdown; the button waits out combat (ApplySortEnabled).
        FinishSort = function(combat)
            physicalActive = false
            sortCombatStop:UnregisterAllEvents()
            if not tookOver then
                CludesUI.ReleaseCVar("Sound_EnableSFX", sfxWas, "CludesUIBags")
            end
            if combat then
                CUI_Bags.refreshEnabled = true
                CUI_Bags:RefreshInventory()
                C_Timer.After(3, UnlockSort)
                return
            end
            C_Timer.After(0.3, function()
                CUI_Bags.refreshEnabled = true
                CUI_Bags:RefreshInventory()
                C_Timer.After(3, UnlockSort)
            end)
        end

        local function RunRetryLoop(bagMin, bagMax, onDone)
            local moved = ComputeAndExecute(bagMin, bagMax)
            if not moved then
                onDone()
                return
            end

            local retryCount = 0
            if not retryFrame then
                retryFrame = CreateFrame("Frame")
            end
            local runToken = {}
            retryFrame._runToken = runToken
            retryFrame:RegisterEvent("BAG_UPDATE")
            ArmBackstop(retryFrame, runToken)
            retryFrame:SetScript("OnEvent", function(self)
                if self._runToken ~= runToken then
                    return
                end
                self._wait = nil
                self:UnregisterAllEvents()
                retryCount = retryCount + 1
                C_Timer.After(0.15, function()
                    if retryFrame._runToken ~= runToken then
                        return
                    end
                    local moved = ComputeAndExecute(bagMin, bagMax)
                    if moved and retryCount < 15 then
                        self:RegisterEvent("BAG_UPDATE")
                        ArmBackstop(self, runToken)
                    else
                        self:SetScript("OnEvent", nil)
                        onDone()
                    end
                end)
            end)
        end

        local function RunSort()
            RunRetryLoop(0, 4, function()
                if C_Container.GetContainerNumSlots(5) > 0 then
                    RunRetryLoop(5, 5, FinishSort)
                else
                    FinishSort()
                end
            end)
        end

        -- Registered after the mute (CVAR_UPDATE is synchronous: the mute's own
        -- write is never heard, nor, past FinishSort's unregister, the
        -- release's) and before the first pass, which can finish the whole run
        -- at once.
        sortCombatStop:SetScript("OnEvent", function(_, evt, cvar)
            if evt == "CVAR_UPDATE" then
                if type(cvar) == "string" and cvar:lower() == "sound_enablesfx" then
                    tookOver = true
                    sortCombatStop:UnregisterEvent("CVAR_UPDATE")
                    CludesUI.DropHold("Sound_EnableSFX", "CludesUIBags")
                end
                return
            end
            StopWaiting(consolidateFrame)
            StopWaiting(retryFrame)
            FinishSort(true)
        end)
        sortCombatStop:RegisterEvent("PLAYER_REGEN_DISABLED")
        sortCombatStop:RegisterEvent("CVAR_UPDATE")
        -- mergeOnly: the display sort saves its order and FinishSort refreshes the bags.
        ConsolidateStacks(mergeOnly and function()
            DoVisualSort(true)
            FinishSort()
        end or RunSort)
    end

    -- skipRefresh: the caller refreshes the bags (a category sort's merge run).
    DoVisualSort = function(skipRefresh)
        -- Sort items per category and save the order
        local cats = CUI_CategoryManager:GetCategories()
        local tempItems = {}
        for bag = 0, 5 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slotIndex = 1, numSlots do
                local details = C_Container.GetContainerItemInfo(bag, slotIndex)
                if details then
                    local itemLink = C_Container.GetContainerItemLink(bag, slotIndex)
                    tempItems[#tempItems + 1] =
                        { bag = bag, slot = slotIndex, info = details, itemLink = itemLink }
                end
            end
        end
        CUI_CategoryManager:ClassifyAll(tempItems)

        local itemsByCat = {}
        for i = 1, #cats do
            itemsByCat[i] = {}
        end
        for _, payload in ipairs(tempItems) do
            local ci = payload.categoryIndex
            if ci and itemsByCat[ci] then
                itemsByCat[ci][#itemsByCat[ci] + 1] = payload
            end
        end

        local sortedGroups = {}
        for ci = 1, #cats do
            local category = cats[ci]
            if category.groupName then
                if not sortedGroups[category.groupName] then
                    sortedGroups[category.groupName] = true
                    -- Merge all members, sort as one, save under group name
                    local members = CUI_CategoryManager:GetGroupMembers(category.groupName)
                    local merged = {}
                    for _, mi in ipairs(members) do
                        for _, payload in ipairs(itemsByCat[mi] or {}) do
                            merged[#merged + 1] = payload
                        end
                    end
                    if #merged > 1 then
                        PreCacheSortFields(merged)
                        table.sort(merged, VisualSortCompare)
                    end
                    SaveCategoryOrder(category.groupName, merged)
                    -- Also save per-member order for individual category views
                    for _, mi in ipairs(members) do
                        local memberItems = itemsByCat[mi]
                        if memberItems and #memberItems > 1 then
                            PreCacheSortFields(memberItems)
                            table.sort(memberItems, VisualSortCompare)
                        end
                        SaveCategoryOrder(mi, memberItems or {})
                    end
                end
            elseif not category.isRecent and not category.isPinned then
                local catItems = itemsByCat[ci]
                if #catItems > 1 then
                    PreCacheSortFields(catItems)
                    table.sort(catItems, VisualSortCompare)
                end
                SaveCategoryOrder(ci, catItems)
            end
        end

        if not skipRefresh then
            CUI_Bags:RefreshInventory()
        end
        LockSort()
        C_Timer.After(3, UnlockSort)
    end

    -- MultiBag sort defers to Blizzard's native sort (insecure-callable, no taint; BAG_UPDATE
    -- storm drives our refresh). Sort to Bottom rides their fill direction (right-to-left = start
    -- at backpack = our top), floating free slots to our top. Real Blizzard CVar (also drives their Clean Up); set only while the option is on, re-asserted each sort.
    local function DoBlizzardSort()
        if InCombatLockdown() then
            return
        end
        PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
        LockSort()
        if BP().bagSortToBottom and C_Container.SetSortBagsRightToLeft then
            C_Container.SetSortBagsRightToLeft(false)
        end
        C_Container.SortBags()
        C_Timer.After(3, UnlockSort)
    end

    sort:SetScript("OnClick", function()
        if sortLocked or (InCombatLockdown() and SortMovesItems()) then
            return
        end
        if selectedCategoryIndex == -1 then
            if CludesUIDB and CludesUIDB.bagSortWarningDismissed then
                DoPhysicalSort()
            else
                CUI:ShowConfirmPopup({
                    title = "OneBag Sort",
                    message = "OneBag sorting will physically reorganize items in your bags. The changes persist even if you disable CludesUI Bags.",
                    confirmText = "Sort",
                    cancelText = "Cancel",
                    checkbox = "Don't show me again",
                    onConfirm = function(dontShowAgain)
                        if dontShowAgain then
                            if not CludesUIDB then
                                CludesUIDB = {}
                            end
                            CludesUIDB.bagSortWarningDismissed = true
                        end
                        DoPhysicalSort()
                    end,
                })
            end
        elseif selectedCategoryIndex == -2 then
            if CludesUIDB and CludesUIDB.bagMultiSortWarningDismissed then
                DoBlizzardSort()
            else
                CUI:ShowConfirmPopup({
                    title = "MultiBag Sort",
                    message = "MultiBag uses Blizzard's built-in sorting system, which reorganizes the items in your default Blizzard bags. The changes persist even if you disable CludesUI Bags.",
                    confirmText = "Sort",
                    cancelText = "Cancel",
                    checkbox = "Don't show me again",
                    onConfirm = function(dontShowAgain)
                        if dontShowAgain then
                            if not CludesUIDB then
                                CludesUIDB = {}
                            end
                            CludesUIDB.bagMultiSortWarningDismissed = true
                        end
                        DoBlizzardSort()
                    end,
                })
            end
        elseif InCombatLockdown() then
            -- Merging moves items, so in combat only the display sort runs. Sound
            -- here, not in DoVisualSort: the first-open auto sort stays silent.
            PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
            DoVisualSort()
        else
            -- Partial stacks merge first, then the display sort. The run plays the
            -- sort sound itself, on Master: its sound effects mute would cut a
            -- sound played here short.
            DoPhysicalSort(true)
        end
    end)
    CUI_Bags._doVisualSort = DoVisualSort
    CUI_Bags._sortBtn = sort
    ApplySortEnabled() -- a /reload mid-combat builds the button locked

    local bagsBtn = CreateFrame("Button", nil, headerFrame)
    bagsBtn:SetSize(24, 24)
    bagsBtn.icon = bagsBtn:CreateTexture(nil, "ARTWORK")
    bagsBtn.icon:SetAllPoints()
    bagsBtn.icon:SetAtlas("bag-main")
    bagsBtn.icon:SetAlpha(0.9)

    bagsBtn:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        if not CUI_BagsWindow:IsVisible() and CUI.ShowWidgetTooltip then
            CUI.ShowWidgetTooltip(self, "Show Bags")
        end
    end)
    bagsBtn:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        CUI.HideWidgetTooltip()
    end)
    bagsBtn:SetScript("OnClick", function()
        if CUI_BagsWindow:IsVisible() then
            CUI_BagsWindow:Hide()
        else
            CUI.HideWidgetTooltip()
            CUI_BagsWindow:Show()
            CUI_BagsWindow:RefreshBags()
        end
    end)
    CUI_Bags._bagsBtn = bagsBtn
    CUI_Bags:SyncHeaderIcons() -- places Sort / Show Bags / the coin (built only while on)

    local clear = CreateFrame("Button", nil, search)
    clear:SetSize(22, 22)
    clear:SetPoint("RIGHT", search, "RIGHT", 0, 0)
    clear.tex = clear:CreateFontString(nil, "OVERLAY")
    SetBagFont(clear.tex, 14)
    clear.tex:SetText("x")
    clear.tex:SetPoint("CENTER", 0, 1)
    clear.tex:SetTextColor(0.8, 0.8, 0.8)
    if forever then
        mod.SkinForeverBagSearch(search, search.bg, placeholder, clear)
    end
    clear:Hide()
    clear:SetScript("OnClick", function()
        search:SetText("")
        search:ClearFocus()
        CUI_Bags.ClearSearch()
    end)

    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        CUI_Bags.ClearSearch()
    end)
    -- SetItemSearch is client-global and the bank reads isFiltered too: the
    -- bags, the reagent bag and an open bank all repaint when the game reports
    -- the search (CUI_Bags.SetSearchText), so both windows show the same filter.
    local searchChanged = CUI_Bags.WatchSearchBox(search, CUI_Bags.SetSearchText)
    search:SetScript("OnTextChanged", function(self, userInput)
        local textValue = self:GetText()
        placeholder:SetShown(textValue == "")
        clear:SetShown(textValue ~= "")
        searchChanged(userInput)
    end)

    local close = CreateFrame("Button", nil, headerFrame)
    close:SetSize(12, 12)
    close:SetPoint("RIGHT", -9, 0)
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
    if forever then
        mod.PositionForeverBagClose(close)
    end
    close:SetScript("OnClick", function()
        CUI_Bags:Hide()
        CUI_BagsReagent:Hide()
        if not CludesUIDB then
            CludesUIDB = {}
        end
        CludesUIDB.bagsVisible = false
        -- Controller cursor: keep Blizzard's hidden bag frames closed too.
        if CUI.PadInUse() then
            mod.PadReleaseBlizzBags()
        end
    end)
    CUI_Bags._closeBtn = close -- Junk Marker mode lets a click on it through
    -- Controller cursor: Cancel finds each window's close control.
    if CUI.PadCP() then
        CUI_Bags.CloseButton = close
        CUI_BagsWindow.CloseButton = bagsBtn
    end

    -- Bottom-edge separator (1px physical pixel)
    if not forever then
        local Pix = CUI and CUI.PP
        local px = (Pix and Pix.mult) or 1
        local hdrSep = headerFrame:CreateTexture(nil, "ARTWORK")
        hdrSep:SetHeight(px)
        hdrSep:SetPoint("BOTTOMLEFT", headerFrame, "BOTTOMLEFT", 0, 0)
        hdrSep:SetPoint("BOTTOMRIGHT", headerFrame, "BOTTOMRIGHT", 0, 0)
        hdrSep:SetColorTexture(0.15, 0.15, 0.15, 1)
    end

    CUI_Bags.Header = headerFrame
    CUI_Bags._bagsBtn = bagsBtn
end

Inner.CreateHeader = CreateHeader
Inner.broken = false
