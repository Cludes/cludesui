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
    local title, total = heading.title, heading.itemCount
    local tl, el = title:GetLeft(), edge:GetLeft()
    if not (tl and el) then
        return
    end
    if heading.slotLines then
        heading.slotLines[1]:Hide()
        heading.slotLines[2]:Hide()
    end
    local room = el - 12 - tl
    local tw = title:GetUnboundedStringWidth()
    if tw > room then
        title:SetWidth(math.max(room, 1))
        total:SetAlpha(0)
        return
    end
    title:SetWidth(tw + 1)
    local countRoom = room - tw - 8
    local first, second = (total:GetText() or ""):match("^([^\n]+)\n(.+)$")
    if first then
        -- Each capacity line truncates independently instead of wrapping into the other.
        if not heading.slotLines then
            heading.slotLines = {}
            for i = 1, 2 do
                local divider = heading:CreateFontString(nil, "OVERLAY")
                SetBagFont(divider, 11)
                divider:SetWordWrap(false)
                divider:SetJustifyH("LEFT")
                heading.slotLines[i] = divider
            end
        end
        local _, size = total:GetFont()
        local region, g, b = total:GetTextColor()
        for i = 1, 2 do
            local divider = heading.slotLines[i]
            divider:SetFont(total:GetFont())
            divider:SetTextColor(region, g, b, 1)
            divider:SetPoint("LEFT", title, "RIGHT", 8, i == 1 and size / 2 or -size / 2)
            divider:SetText(i == 1 and first or second)
            divider:SetWidth(math.max(math.min(divider:GetUnboundedStringWidth() + 1, countRoom), 1))
            divider:SetShown(countRoom >= 16)
        end
        total:SetAlpha(0)
        return
    end
    total:SetWidth(math.max(math.min(total:GetUnboundedStringWidth() + 1, countRoom), 1))
    total:SetAlpha(countRoom >= 16 and 1 or 0)
end

local function CreateHeader()
    if CUI_Bags.Header then
        return
    end
    local forever = mod.BagsForever()
    local headerBar = CreateFrame("Frame", nil, CUI_Bags)
    headerBar:SetPoint("TOPLEFT", 1, -1)
    headerBar:SetPoint("TOPRIGHT", -1, -1)
    if forever then
        mod.LayoutForeverBagHeader(headerBar)
    else
        headerBar:SetHeight(HEADER_H)
    end
    headerBar.bg = headerBar:CreateTexture(nil, "BACKGROUND")
    headerBar.bg:SetAllPoints()
    headerBar.bg:SetColorTexture(0, 0, 0, 0.5)

    headerBar.title = headerBar:CreateFontString(nil, "OVERLAY")
    SetBagFont(headerBar.title, 13)
    headerBar.title:SetPoint("LEFT", headerBar, "LEFT", 8, 0)
    headerBar.title:SetText(CludesUI.L("Inventory"))
    headerBar.title:SetTextColor(1, 1, 1)

    -- Item count (updated by RefreshInventory)
    headerBar.itemCount = headerBar:CreateFontString(nil, "OVERLAY")
    SetBagFont(headerBar.itemCount, 11)
    headerBar.itemCount:SetPoint("LEFT", headerBar.title, "RIGHT", 8, 0)
    headerBar.itemCount:SetTextColor(0.6, 0.6, 0.6)

    -- Title and count stop short of the header icons (CUI_Bags:FitHeaderText),
    -- refitted whenever either text, the title's spot or the header width changes.
    headerBar.title:SetWordWrap(false)
    headerBar.title:SetJustifyH("LEFT")
    headerBar.itemCount:SetWordWrap(false)
    headerBar.itemCount:SetJustifyH("LEFT")
    if not forever then
        local function Fit()
            CUI_Bags:FitHeaderText()
        end
        hooksecurefunc(headerBar.title, "SetText", Fit)
        hooksecurefunc(headerBar.title, "SetPoint", Fit)
        hooksecurefunc(headerBar.itemCount, "SetText", Fit)
        headerBar:HookScript("OnSizeChanged", Fit)
        headerBar:HookScript("OnShow", Fit)
    end

    local searchBox = CreateFrame("EditBox", "CUI_BagSearchBox", headerBar)
    searchBox:SetSize(160, 22)
    searchBox:SetPoint("RIGHT", -35, 0)
    searchBox:SetFont(GetFont(), 12, CUI.GetFontOutlineFlag("bags"))
    searchBox:SetAutoFocus(false)
    searchBox:SetTextInsets(5, 26, 0, 0)
    searchBox.bg = searchBox:CreateTexture(nil, "BACKGROUND")
    searchBox.bg:SetAllPoints()
    searchBox.bg:SetColorTexture(0.02, 0.02, 0.02, 1)
    if not forever and CUI.PanelPP then
        CUI.PanelPP.CreateBorder(searchBox, 0.25, 0.25, 0.25, 1, 1, "OVERLAY", 7)
    end

    local placeholder = searchBox:CreateFontString(nil, "OVERLAY")
    SetBagFont(placeholder, 11)
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 5, 0)
    placeholder:SetText(CludesUI.L("Search..."))
    placeholder:SetTextColor(0.4, 0.4, 0.4)
    CUI_Bags._searchBox = searchBox

    local sortBtn = CreateFrame("Button", nil, headerBar)
    sortBtn:SetSize(24, 24)
    sortBtn:SetPoint("RIGHT", searchBox, "LEFT", -13, 0)
    sortBtn.icon = sortBtn:CreateTexture(nil, "OVERLAY")
    sortBtn.icon:SetAllPoints()
    sortBtn.icon:SetTexture("Interface\\AddOns\\CludesUIBags\\Media\\clean-up.png")
    sortBtn.icon:SetAlpha(0.9)

    if forever then
        headerBar.bg:Hide()
        mod.AddForeverBagPortrait(headerBar, "Interface\\Icons\\Inv_misc_bag_08")
        mod.SkinForeverBagTitle(headerBar.title, headerBar.itemCount)
        sortBtn:ClearAllPoints()
        sortBtn:SetPoint("RIGHT", headerBar, "TOPRIGHT", -9, headerBar._foreverToolsY)
    end

    sortBtn:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        CUI.ShowWidgetTooltip(self, "Sort Items")
    end)
    sortBtn:SetScript("OnLeave", function(self)
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
        sortBtn:EnableMouse(enabled)
        sortBtn.icon:SetAlpha(enabled and 0.9 or 0.2)
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
    local consolidator, retrier
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
        local function StopWaiting(frame)
            if not frame then
                return
            end
            frame._runToken = nil
            frame._wait = nil
            frame:UnregisterAllEvents()
            frame:SetScript("OnEvent", nil)
        end
        -- Fail-open backstop: a pass whose moves all fail (an item locked
        -- elsewhere: a mail attachment, the auction house, a trade) brings no
        -- bag update, and the run would wait for good, the bags frozen and the
        -- sound effects muted. A wait with no update SORT_STUCK_AFTER seconds
        -- on ends the run as finished; a sort cut short can simply run again.
        local function ArmBackstop(frame, token)
            local wait = {}
            frame._wait = wait
            C_Timer.After(SORT_STUCK_AFTER, function()
                if frame._runToken ~= token or frame._wait ~= wait then
                    return
                end
                StopWaiting(consolidator)
                StopWaiting(retrier)
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
                for bagId = 0, 5 do
                    local numSlots = C_Container.GetContainerNumSlots(bagId)
                    for slot = 1, numSlots do
                        local details = C_Container.GetContainerItemInfo(bagId, slot)
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
                                if special and special[bagId] then
                                    key = bagId .. ":" .. key
                                end
                                if not stacks[key] then
                                    stacks[key] = {}
                                end
                                stacks[key][#stacks[key] + 1] = {
                                    bag = bagId,
                                    slot = slot,
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
                            local source, target = partials[lo], partials[hi]
                            local srcLoc = ItemLocation:CreateFromBagAndSlot(source.bag, source.slot)
                            local dstLoc = ItemLocation:CreateFromBagAndSlot(target.bag, target.slot)
                            if not C_Item.IsLocked(srcLoc) and not C_Item.IsLocked(dstLoc) then
                                C_Container.PickupContainerItem(source.bag, source.slot)
                                C_Container.PickupContainerItem(target.bag, target.slot)
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
            if not consolidator then
                consolidator = CreateFrame("Frame")
            end
            local runId = {}
            consolidator._runToken = runId
            consolidator:RegisterEvent("BAG_UPDATE")
            ArmBackstop(consolidator, runId)
            consolidator:SetScript("OnEvent", function(self)
                if self._runToken ~= runId then
                    return
                end
                self._wait = nil
                self:UnregisterAllEvents()
                consolidateRetry = consolidateRetry + 1
                C_Timer.After(0.15, function()
                    if consolidator._runToken ~= runId then
                        return
                    end
                    if consolidateRetry < 30 and DoOnePass() then
                        self:RegisterEvent("BAG_UPDATE")
                        ArmBackstop(self, runId)
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
        local function ComputeAndExecute(firstBag, lastBag)
            if InCombatLockdown() then
                return false
            end -- combat started: stop moving items
            firstBag = firstBag or 0
            lastBag = lastBag or 4
            local sum = 0
            local sBag, sSlot, sKey, slotId = {}, {}, {}, {}

            local itemList = {}
            -- A WoW Forever special bag adds no slots: its items stay put and
            -- nothing is moved into it.
            local special = mod.SpecialBags()
            for bagId = firstBag, lastBag do
                local numSlots = (special and special[bagId]) and 0 or C_Container.GetContainerNumSlots(bagId)
                for slot = 1, numSlots do
                    sum = sum + 1
                    sBag[sum] = bagId
                    sSlot[sum] = slot
                    local details = C_Container.GetContainerItemInfo(bagId, slot)
                    if details then
                        local link = C_Container.GetContainerItemLink(bagId, slot)
                        local key = link .. "\0" .. (details.stackCount or 0)
                        sKey[sum] = key
                        slotId[sum] = details.itemID
                        itemList[#itemList + 1] = {
                            pos = sum,
                            bag = bagId,
                            slot = slot,
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
            for _, skinData in ipairs(itemList) do
                skinData._sectionOrder = sectionOrder[skinData.categoryIndex] or 9999
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
            for position, skinData in ipairs(itemList) do
                atPos[skinData.pos] = position
                whereIs[position] = skinData.pos
            end

            -- Sorted item i targets slot i; Sort to Bottom offsets so the block lands in the LAST
            -- #items slots (free slots float up either way). The walk must move toward the free slots
            -- (forward for top, backward for bottom), or a displaced item lands in an already-visited slot -- costing a retry per move, risking the 15-retry cap.
            local off, first, last, step = 0, 1, #itemList, 1
            if BP().bagSortToBottom then
                off = sum - #itemList
                first, last, step = #itemList, 1, -1
            end

            local moves = {}
            for i = first, last, step do
                local t = i + off
                local s = whereIs[i]
                if s ~= t then
                    local displaced = atPos[t]
                    if displaced and slotId[s] and slotId[t] and slotId[s] == slotId[t] then
                        -- Same itemID: skip to avoid merge, retry will resolve
                    else
                        moves[#moves + 1] = { sBag[s], sSlot[s], sBag[t], sSlot[t] }
                        whereIs[i] = t
                        if displaced then
                            whereIs[displaced] = s
                        end
                        atPos[t] = i
                        atPos[s] = displaced
                        slotId[s], slotId[t] = slotId[t], slotId[s]
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

        local function RunRetryLoop(firstBag, lastBag, onDone)
            local moved = ComputeAndExecute(firstBag, lastBag)
            if not moved then
                onDone()
                return
            end

            local retryCount = 0
            if not retrier then
                retrier = CreateFrame("Frame")
            end
            local runId = {}
            retrier._runToken = runId
            retrier:RegisterEvent("BAG_UPDATE")
            ArmBackstop(retrier, runId)
            retrier:SetScript("OnEvent", function(self)
                if self._runToken ~= runId then
                    return
                end
                self._wait = nil
                self:UnregisterAllEvents()
                retryCount = retryCount + 1
                C_Timer.After(0.15, function()
                    if retrier._runToken ~= runId then
                        return
                    end
                    local moved = ComputeAndExecute(firstBag, lastBag)
                    if moved and retryCount < 15 then
                        self:RegisterEvent("BAG_UPDATE")
                        ArmBackstop(self, runId)
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
            StopWaiting(consolidator)
            StopWaiting(retrier)
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
        for bagId = 0, 5 do
            local numSlots = C_Container.GetContainerNumSlots(bagId)
            for slot = 1, numSlots do
                local details = C_Container.GetContainerItemInfo(bagId, slot)
                if details then
                    local itemLink = C_Container.GetContainerItemLink(bagId, slot)
                    tempItems[#tempItems + 1] =
                        { bag = bagId, slot = slot, info = details, itemLink = itemLink }
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

    sortBtn:SetScript("OnClick", function()
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
    CUI_Bags._sortBtn = sortBtn
    ApplySortEnabled() -- a /reload mid-combat builds the button locked

    local bagsButton = CreateFrame("Button", nil, headerBar)
    bagsButton:SetSize(24, 24)
    bagsButton.icon = bagsButton:CreateTexture(nil, "ARTWORK")
    bagsButton.icon:SetAllPoints()
    bagsButton.icon:SetAtlas("bag-main")
    bagsButton.icon:SetAlpha(0.9)

    bagsButton:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        if not CUI_BagsWindow:IsVisible() and CUI.ShowWidgetTooltip then
            CUI.ShowWidgetTooltip(self, "Show Bags")
        end
    end)
    bagsButton:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        CUI.HideWidgetTooltip()
    end)
    bagsButton:SetScript("OnClick", function()
        if CUI_BagsWindow:IsVisible() then
            CUI_BagsWindow:Hide()
        else
            CUI.HideWidgetTooltip()
            CUI_BagsWindow:Show()
            CUI_BagsWindow:RefreshBags()
        end
    end)
    CUI_Bags._bagsBtn = bagsButton
    CUI_Bags:SyncHeaderIcons() -- places Sort / Show Bags / the coin (built only while on)

    local clearBtn = CreateFrame("Button", nil, searchBox)
    clearBtn:SetSize(22, 22)
    clearBtn:SetPoint("RIGHT", searchBox, "RIGHT", 0, 0)
    clearBtn.tex = clearBtn:CreateFontString(nil, "OVERLAY")
    SetBagFont(clearBtn.tex, 14)
    clearBtn.tex:SetText("x")
    clearBtn.tex:SetPoint("CENTER", 0, 1)
    clearBtn.tex:SetTextColor(0.8, 0.8, 0.8)
    if forever then
        mod.SkinForeverBagSearch(searchBox, searchBox.bg, placeholder, clearBtn)
    end
    clearBtn:Hide()
    clearBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
        CUI_Bags.ClearSearch()
    end)

    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        CUI_Bags.ClearSearch()
    end)
    -- SetItemSearch is client-global and the bank reads isFiltered too: the
    -- bags, the reagent bag and an open bank all repaint when the game reports
    -- the search (CUI_Bags.SetSearchText), so both windows show the same filter.
    local searchChanged = CUI_Bags.WatchSearchBox(searchBox, CUI_Bags.SetSearchText)
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        local textValue = self:GetText()
        placeholder:SetShown(textValue == "")
        clearBtn:SetShown(textValue ~= "")
        searchChanged(userInput)
    end)

    local closeBtn = CreateFrame("Button", nil, headerBar)
    closeBtn:SetSize(12, 12)
    closeBtn:SetPoint("RIGHT", -9, 0)
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
    if forever then
        mod.PositionForeverBagClose(closeBtn)
    end
    closeBtn:SetScript("OnClick", function()
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
    CUI_Bags._closeBtn = closeBtn -- Junk Marker mode lets a click on it through
    -- Controller cursor: Cancel finds each window's close control.
    if CUI.PadCP() then
        CUI_Bags.CloseButton = closeBtn
        CUI_BagsWindow.CloseButton = bagsButton
    end

    -- Bottom-edge separator (1px physical pixel)
    if not forever then
        local Pix = CUI and CUI.PP
        local px = (Pix and Pix.mult) or 1
        local hdrSep = headerBar:CreateTexture(nil, "ARTWORK")
        hdrSep:SetHeight(px)
        hdrSep:SetPoint("BOTTOMLEFT", headerBar, "BOTTOMLEFT", 0, 0)
        hdrSep:SetPoint("BOTTOMRIGHT", headerBar, "BOTTOMRIGHT", 0, 0)
        hdrSep:SetColorTexture(0.15, 0.15, 0.15, 1)
    end

    CUI_Bags.Header = headerBar
    CUI_Bags._bagsBtn = bagsButton
end

Inner.CreateHeader = CreateHeader
Inner.broken = false
