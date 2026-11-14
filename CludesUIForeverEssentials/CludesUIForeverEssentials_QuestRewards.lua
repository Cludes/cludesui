if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_QuestRewards.lua  (WoW Forever only)
--  Most Valuable Reward: among a quest's reward choices (quest window, quest
--  log and map), a money bag (the minimap's banker icon) at the bottom right
--  of the one that sells for most, its count included.
--
--  The game lays the rewards out within QuestInfo_Display (its templates
--  hold their own reference to QuestInfo_ShowRewards, so that one cannot be
--  hooked); a hooksecurefunc on QuestInfo_Display reads the shown choice
--  buttons' item links and puts the purse on a texture of our own. Nothing of
--  Blizzard's is written. An item the client has not cached yet waits for
--  its GET_ITEM_INFO_RECEIVED, then the choices are read again once.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in CludesUIDB.questRewards; unset keys read these.
local F = module.Feature("questRewards", { enabled = false })

-- The minimap's banker icon: a money bag drawn on transparency.
local PURSE = "Interface\\Minimap\\Tracking\\Banker"

local hooked, waiter, Update
local coins = setmetatable({}, { __mode = "k" }) -- reward button -> our coin

-- A choice button's item and count: its link, or its item ID while the client
-- has no link for it yet (not cached), so it still counts as missing.
local function ChoiceItem(btnFrame)
    local idx = btnFrame:GetID()
    if QuestInfoFrame.questLog then
        local _, _, total, _, _, itemId = GetQuestLogChoiceInfo(idx)
        return GetQuestLogItemLink("choice", idx) or itemId, total or 1
    end
    local _, _, total, _, _, itemId = GetQuestItemInfo("choice", idx)
    return GetQuestItemLink("choice", idx) or itemId, total or 1
end

local function Coin(btnFrame)
    local coin = coins[btnFrame]
    if coin then
        return coin
    end
    local holderFrame = CreateFrame("Frame", nil, btnFrame)
    holderFrame:SetAllPoints()
    holderFrame:SetFrameLevel(btnFrame:GetFrameLevel() + 2)
    coin = holderFrame:CreateTexture(nil, "OVERLAY")
    coin:SetTexture(PURSE)
    coin:SetSize(18, 18)
    coin:SetPoint("BOTTOMRIGHT", btnFrame, "BOTTOMRIGHT", 2, 0)
    coins[btnFrame] = coin
    return coin
end

local function WaitForItems()
    if not waiter then
        waiter = CreateFrame("Frame")
        waiter:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            if QuestInfoFrame.rewardsFrame and QuestInfoFrame.rewardsFrame:IsVisible() then
                Update()
            end
        end)
    end
    waiter:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

-- The coin on the shown choice that sells for most. Off, Apply has hidden
-- the coins.
function Update()
    if not F.Enabled() then
        return
    end
    for _, coin in pairs(coins) do
        coin:Hide()
    end
    local rewards = QuestInfoFrame.rewardsFrame
    if not (rewards and rewards.RewardButtons) then
        return
    end
    local best, bestValue, missing = nil, 0, false
    for _, btnFrame in ipairs(rewards.RewardButtons) do
        if btnFrame:IsShown() and btnFrame.type == "choice" and btnFrame.objectType == "item" then
            local item, total = ChoiceItem(btnFrame)
            if item then
                local sellPrice = select(11, C_Item.GetItemInfo(item))
                if not sellPrice then
                    missing = true
                elseif sellPrice * total > bestValue then
                    best, bestValue = btnFrame, sellPrice * total
                end
            end
        end
    end
    if missing then
        WaitForItems()
    end
    if best then
        Coin(best):Show()
    end
end

-- The hook goes in the first time the setting is on; off, it hides the coin
-- and returns.
local function Apply()
    if F.Enabled() and not hooked then
        hooked = true
        hooksecurefunc("QuestInfo_Display", Update)
    end
    if not F.Enabled() then
        for _, coin in pairs(coins) do
            coin:Hide()
        end
    end
end

-- Options-page entry points.
CludesUI._QuestRewards = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
