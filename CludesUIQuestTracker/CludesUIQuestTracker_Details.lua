if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not CludesUI.IS_FOREVER then
    return
end
-------------------------------------------------------------------------------
-- CludesUIQuestTracker_Details.lua  (WoW Forever only)
--
-- Our own quest details window, opened from the custom tracker. Built only
-- from quest log reads keyed by quest ID, so no Blizzard quest or map code
-- runs from it: opening Blizzard's map or quest popup from addon code taints
-- the map's pins (SetPassThroughButtons blocked in combat). Works in combat.
-------------------------------------------------------------------------------
local _, mod = ...
local EQT = mod.EQT

local W, H = 360, 480
local PAD = 14
local HEADER_H = 52 -- title, meta line, divider
local FOOTER_H = 50 -- divider, button row
local BTN_H = 24
local TILE = 34
local GAP = 6
local WHEEL = 40
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local CLOSE = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png"

-- CludesUI panel look (see CludesUI_Popups.lua).
local BG = { 0.062, 0.070, 0.082, 0.97 }
local TILE_BG = { 0.11, 0.10, 0.09, 1 }

-------------------------------------------------------------------------------
-- Rewards: XP, money, then one entry per currency, item and choice.
-- Entry: name, texture, count, quality, itemID, type ("reward" / "choice"),
-- index (for the quest log tooltip calls), currency. Nil when none.
-------------------------------------------------------------------------------
function EQT.QuestRewards(questID)
    if not C_QuestLog.ShouldShowQuestRewards(questID) then
        return
    end
    local r = {
        xp = GetQuestLogRewardXP(questID),
        money = GetQuestLogRewardMoney(questID),
        rewards = {},
        choices = {},
    }
    for idx, current in ipairs(C_QuestLog.GetQuestRewardCurrencies(questID)) do
        r.rewards[#r.rewards + 1] = {
            name = current.name,
            texture = current.texture,
            count = current.totalRewardAmount,
            quality = current.quality,
            type = "reward",
            index = idx,
            currency = true,
        }
    end
    for idx = 1, GetNumQuestLogRewards(questID) do
        local name, texture, total, quality, _, itemId = GetQuestLogRewardInfo(idx, questID)
        r.rewards[#r.rewards + 1] = {
            name = name,
            texture = texture,
            count = total,
            quality = quality,
            itemID = itemId,
            type = "reward",
            index = idx,
        }
    end
    for idx = 1, GetNumQuestLogChoices(questID) do
        local name, texture, total, quality, _, itemId = GetQuestLogChoiceInfo(idx, questID)
        r.choices[#r.choices + 1] = {
            name = name,
            texture = texture,
            count = total,
            quality = quality,
            itemID = itemId,
            type = "choice",
            index = idx,
        }
    end
    if r.xp <= 0 and r.money <= 0 and #r.rewards == 0 and #r.choices == 0 then
        return
    end
    return r
end

-- Calls fn once an entry's uncached item loads.
function EQT.OnRewardLoad(e, func)
    local item = e.itemID and Item:CreateFromItemID(e.itemID)
    if item and not item:IsItemEmpty() and not item:IsItemDataCached() then
        item:ContinueOnItemLoad(func)
    end
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------
local window, scroll, childFrame, title, meta
local texts, tiles, marks = {}, {}, {}
local usedTexts, usedTiles, usedMarks = 0, 0, 0
local questID
local moved = false -- dragged by the player: stop following the tracker

local function Accent()
    local g = CludesUI.CLUDES_GREEN
    return g.r, g.g, g.b
end

local function Dim()
    local d = CludesUI.TEXT_DIM
    return d.r, d.g, d.b, d.a
end

local function StyleText(fontStr, size)
    local flag = CludesUI.GetFontOutlineFlag("questTracker")
    if not pcall(fontStr.SetFont, fontStr, EQT.GetFont(), size, flag) then
        fontStr:SetFont("Fonts/FRIZQT__.TTF", size, flag)
    end
end

local function ContentWidth()
    return W - PAD * 2
end

-- Wrapped text at (x, y); returns its height.
local function AddText(textValue, posX, posY, size, r, g, b, a)
    usedTexts = usedTexts + 1
    local fontStr = texts[usedTexts]
    if not fontStr then
        fontStr = childFrame:CreateFontString(nil, "OVERLAY")
        fontStr:SetJustifyH("LEFT")
        fontStr:SetWordWrap(true)
        texts[usedTexts] = fontStr
    end
    StyleText(fontStr, size)
    fontStr:SetSpacing(2)
    fontStr:SetWidth(ContentWidth() - posX)
    fontStr:SetTextColor(r, g, b, a or 1)
    fontStr:SetText(textValue)
    fontStr:ClearAllPoints()
    fontStr:SetPoint("TOPLEFT", childFrame, "TOPLEFT", posX, -posY)
    fontStr:Show()
    return math.ceil(fontStr:GetStringHeight())
end

-- Section header: small accent capitals over a hairline.
local function AddSection(textValue, posY)
    local r, g, b = Accent()
    local hgt = AddText(textValue:upper(), 0, posY, 11, r, g, b)
    return hgt + 6
end

-- Objective marker: a check when finished, else a small accent square.
local function AddMark(done, posY)
    usedMarks = usedMarks + 1
    local m = marks[usedMarks]
    if not m then
        m = childFrame:CreateTexture(nil, "ARTWORK")
        marks[usedMarks] = m
    end
    m:ClearAllPoints()
    if done then
        m:SetTexture(CHECK)
        m:SetVertexColor(1, 1, 1, 1)
        m:SetSize(12, 12)
        m:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, -posY)
    else
        local r, g, b = Accent()
        m:SetColorTexture(r, g, b, 0.9)
        m:SetSize(4, 4)
        m:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 4, -(posY + 5))
    end
    m:Show()
end

local function TileEnter(self)
    local r, g, b = Accent()
    self.frame:SetColor(r, g, b, 0.6)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.entry.currency then
        GameTooltip:SetQuestLogCurrency(self.entry.type, self.entry.index, questID)
    else
        GameTooltip:SetQuestLogItem(self.entry.type, self.entry.index, questID)
    end
    GameTooltip:Show()
end

local function TileRest(t)
    local c = CludesUI.BORDER_COLOR
    t.frame:SetColor(c.r, c.g, c.b, 0.15)
end

local function TileLeave(self)
    TileRest(self)
    GameTooltip:Hide()
end

local function AddTile(e, posX, posY, wid)
    usedTiles = usedTiles + 1
    local t = tiles[usedTiles]
    if not t then
        t = CreateFrame("Button", nil, childFrame)
        local backdrop = t:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(TILE_BG[1], TILE_BG[2], TILE_BG[3], TILE_BG[4])
        t.frame = CludesUI.MakeBorder(t, 1, 1, 1, 0.15)
        local holderFrame = CreateFrame("Frame", nil, t)
        holderFrame:SetSize(TILE - 8, TILE - 8)
        holderFrame:SetPoint("LEFT", 4, 0)
        t.icon = holderFrame:CreateTexture(nil, "ARTWORK")
        t.icon:SetAllPoints()
        t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.quality = CludesUI.MakeBorder(holderFrame, 0, 0, 0, 1)
        t.count = holderFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        t.count:SetPoint("BOTTOMRIGHT", 1, 0)
        t.name = t:CreateFontString(nil, "OVERLAY")
        t.name:SetPoint("LEFT", holderFrame, "RIGHT", 6, 0)
        t.name:SetPoint("RIGHT", -4, 0)
        t.name:SetJustifyH("LEFT")
        t.name:SetMaxLines(2)
        t:SetScript("OnEnter", TileEnter)
        t:SetScript("OnLeave", TileLeave)
        tiles[usedTiles] = t
    end
    t.entry = e
    t:SetSize(wid, TILE)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", childFrame, "TOPLEFT", posX, -posY)
    local c = e.quality and ColorManager.GetColorDataForItemQuality(e.quality)
    if c then
        t.quality:SetColor(c.r, c.g, c.b, 1)
    else
        t.quality:SetColor(0, 0, 0, 1)
    end
    t.icon:SetTexture(e.texture)
    t.count:SetText((e.count and e.count > 1) and e.count or "")
    StyleText(t.name, 11)
    t.name:SetText(e.name or RETRIEVING_DATA)
    if c then
        t.name:SetTextColor(c.r, c.g, c.b)
    else
        t.name:SetTextColor(1, 1, 1)
    end
    TileRest(t)
    t:Show()
end

-- Two columns of tiles; returns the height used.
local function AddTiles(entries, posY)
    local wid = (ContentWidth() - GAP) / 2
    for idx, e in ipairs(entries) do
        local col = (idx - 1) % 2
        AddTile(e, col * (wid + GAP), posY + math.floor((idx - 1) / 2) * (TILE + GAP), wid)
    end
    local rowList = math.ceil(#entries / 2)
    return rowList * TILE + math.max(0, rowList - 1) * GAP
end

-- Level (difficulty colored) and quest type, e.g. "Level 12  Elite".
local function MetaText()
    local level = C_QuestLog.GetQuestDifficultyLevel(questID)
    local parts = {}
    if level and level > 0 then
        local c = GetQuestDifficultyColor(level)
        parts[1] = CreateColor(c.r, c.g, c.b):WrapTextInColorCode(LEVEL .. " " .. level)
    end
    local tag = C_QuestLog.GetQuestTagInfo(questID)
    if tag and tag.tagName then
        parts[#parts + 1] = tag.tagName
    end
    if C_QuestLog.IsComplete(questID) then
        parts[#parts + 1] = COMPLETE
    end
    return table.concat(parts, "   ")
end

local Refresh

local function SetButtonEnabled(b, enabled)
    b:SetEnabled(enabled)
    b:SetAlpha(enabled and 1 or 0.35)
end

local function UpdateButtons()
    local focused = C_SuperTrack.GetSuperTrackedQuestID() == questID
    window.focus.label:SetText(focused and STOP_SUPER_TRACK_QUEST or SUPER_TRACK_QUEST)
    SetButtonEnabled(window.share, IsInGroup() and C_QuestLog.IsPushableQuest(questID))
    SetButtonEnabled(window.abandon, C_QuestLog.CanAbandonQuest(questID))
end

function Refresh()
    if not (window and window:IsShown() and questID) then
        return
    end
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    if not logIndex then
        window:Hide()
        return
    end
    usedTexts, usedTiles, usedMarks = 0, 0, 0
    local dr, dg, saved, da = Dim()
    title:SetText(C_QuestLog.GetTitleForQuestID(questID) or "")
    meta:SetText(MetaText())
    window.bar:SetColorTexture(Accent())

    local description, objectivesText = GetQuestLogQuestText(logIndex)
    local posY = 0
    local objectives = C_QuestLog.GetQuestObjectives(questID) or {}
    if #objectives > 0 or (objectivesText and objectivesText ~= "") then
        posY = posY + AddSection(QUEST_OBJECTIVES, posY)
        for _, o in ipairs(objectives) do
            if o.text and o.text ~= "" then
                AddMark(o.finished, posY)
                if o.finished then
                    posY = posY + AddText(o.text, 18, posY, 12, dr, dg, saved, da) + 4
                else
                    posY = posY + AddText(o.text, 18, posY, 12, 1, 1, 1) + 4
                end
            end
        end
        if objectivesText and objectivesText ~= "" then
            posY = posY + 4 + AddText(objectivesText, 0, posY + 4, 12, dr, dg, saved, da)
        end
        posY = posY + 16
    end
    if description and description ~= "" then
        posY = posY + AddSection(QUEST_DESCRIPTION, posY)
        posY = posY + AddText(description, 0, posY, 12, 0.9, 0.9, 0.9) + 16
    end

    local r = EQT.QuestRewards(questID)
    if r then
        posY = posY + AddSection(QUEST_REWARDS, posY)
        if r.xp > 0 then
            posY = posY + AddText(BONUS_OBJECTIVE_EXPERIENCE_FORMAT:format(r.xp), 0, posY, 12, 1, 1, 1) + 4
        end
        if r.money > 0 then
            posY = posY + AddText(GetMoneyString(r.money), 0, posY, 12, 1, 1, 1) + 4
        end
        if #r.rewards > 0 then
            posY = posY + 4 + AddTiles(r.rewards, posY + 4) + 4
        end
        if #r.choices > 0 then
            posY = posY + 8
            posY = posY + AddText(REWARD_CHOICES, 0, posY, 12, dr, dg, saved, da) + 6
            posY = posY + AddTiles(r.choices, posY)
        end
        -- Uncached items: redraw once each loads, if still on this quest.
        local isShown = questID
        for _, entries in ipairs({ r.rewards, r.choices }) do
            for _, e in ipairs(entries) do
                if not e.name then
                    EQT.OnRewardLoad(e, function()
                        if questID == isShown then
                            Refresh()
                        end
                    end)
                end
            end
        end
    end

    for idx = usedTexts + 1, #texts do
        texts[idx]:Hide()
    end
    for idx = usedTiles + 1, #tiles do
        tiles[idx]:Hide()
    end
    for idx = usedMarks + 1, #marks do
        marks[idx]:Hide()
    end
    childFrame:SetSize(ContentWidth(), math.max(1, posY))
    local maxScroll = math.max(0, posY - scroll:GetHeight())
    scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), maxScroll))
    UpdateButtons()
end

-- Beside the tracker, on the side facing the screen centre.
local function Place()
    if moved then
        return
    end
    local tracker = _G.CUI_CustomQuestTracker
    window:ClearAllPoints()
    local cx = tracker and tracker:GetCenter()
    if not cx then
        window:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
        return
    end
    if cx * tracker:GetEffectiveScale() > UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2 then
        window:SetPoint("TOPRIGHT", tracker, "TOPLEFT", -8, 0)
    else
        window:SetPoint("TOPLEFT", tracker, "TOPRIGHT", 8, 0)
    end
end

local function Button(textValue, onClick)
    local b = CreateFrame("Button", nil, window)
    b:SetSize((W - PAD * 2 - GAP * 3) / 4, BTN_H)
    local _, _, labelFS = CludesUI.MakeStyledButton(b, textValue, 11, CludesUI.WB_COLOURS, onClick)
    labelFS:SetWidth(b:GetWidth() - 6)
    labelFS:SetWordWrap(false)
    b.label = labelFS
    return b
end

local function Divider(posY, fromBottom)
    local c = CludesUI.BORDER_COLOR
    local t = window:CreateTexture(nil, "BORDER")
    t:SetColorTexture(c.r, c.g, c.b, 0.15)
    t:SetHeight(1)
    local anchorPoint = fromBottom and "BOTTOM" or "TOP"
    t:SetPoint(anchorPoint .. "LEFT", PAD, posY)
    t:SetPoint(anchorPoint .. "RIGHT", -PAD, posY)
end

local function Build()
    window = CreateFrame("Frame", "CUI_QuestDetails", UIParent)
    window:SetSize(W, H)
    window:SetFrameStrata("MEDIUM")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        moved = true
    end)
    window:Hide()

    local backdrop = window:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(BG[1], BG[2], BG[3], BG[4])
    local c = CludesUI.BORDER_COLOR
    CludesUI.MakeBorder(window, c.r, c.g, c.b, 0.15)

    -- Header: accent bar, title, meta line.
    window.bar = window:CreateTexture(nil, "ARTWORK")
    window.bar:SetSize(2, 32)
    window.bar:SetPoint("TOPLEFT", PAD, -PAD + 2)
    title = window:CreateFontString(nil, "OVERLAY")
    StyleText(title, 15)
    title:SetTextColor(1, 1, 1)
    title:SetPoint("TOPLEFT", window.bar, "TOPRIGHT", 8, 0)
    title:SetPoint("RIGHT", -34, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    meta = window:CreateFontString(nil, "OVERLAY")
    StyleText(meta, 11)
    meta:SetTextColor(Dim())
    meta:SetPoint("BOTTOMLEFT", window.bar, "BOTTOMRIGHT", 8, 0)
    meta:SetJustifyH("LEFT")
    Divider(-HEADER_H)

    local close = CreateFrame("Button", nil, window)
    close:SetSize(12, 12)
    close:SetPoint("TOPRIGHT", -PAD, -PAD)
    close.icon = close:CreateTexture(nil, "OVERLAY")
    close.icon:SetAllPoints()
    close.icon:SetTexture(CLOSE)
    close.icon:SetAlpha(0.7)
    close:SetScript("OnEnter", function()
        close.icon:SetAlpha(1)
    end)
    close:SetScript("OnLeave", function()
        close.icon:SetAlpha(0.7)
    end)
    close:SetScript("OnClick", function()
        window:Hide()
    end)

    scroll = CreateFrame("ScrollFrame", nil, window)
    scroll:SetPoint("TOPLEFT", PAD, -HEADER_H - 12)
    scroll:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H + 8)
    scroll:SetClipsChildren(true)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, childFrame:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScroll() - delta * WHEEL, max)))
    end)
    childFrame = CreateFrame("Frame", nil, scroll)
    childFrame:SetSize(ContentWidth(), 1)
    scroll:SetScrollChild(childFrame)

    -- Footer: one row of buttons.
    Divider(FOOTER_H, true)
    local a = EQT.CustomQuestActions
    window.focus = Button(SUPER_TRACK_QUEST, function()
        a.Focus(questID)
    end)
    window.focus:SetPoint("BOTTOMLEFT", PAD, PAD)
    window.untrack = Button(UNTRACK_QUEST_ABBREV, function()
        a.Untrack(questID)
    end)
    window.untrack:SetPoint("LEFT", window.focus, "RIGHT", GAP, 0)
    window.share = Button(SHARE_QUEST_ABBREV, function()
        QuestLogPushQuest(C_QuestLog.GetLogIndexForQuestID(questID))
    end)
    window.share:SetPoint("LEFT", window.untrack, "RIGHT", GAP, 0)
    window.abandon = Button(ABANDON_QUEST_ABBREV, function()
        a.Abandon(questID)
    end)
    window.abandon:SetPoint("LEFT", window.share, "RIGHT", GAP, 0)

    window:SetScript("OnEvent", function(_, evt, ident)
        if evt == "QUEST_REMOVED" then
            if ident == questID then
                window:Hide()
            end
        elseif evt == "SUPER_TRACKING_CHANGED" or evt == "GROUP_ROSTER_UPDATE" then
            UpdateButtons()
        else
            Refresh()
        end
    end)
    window:SetScript("OnShow", function(self)
        self:RegisterEvent("QUEST_LOG_UPDATE")
        self:RegisterEvent("QUEST_REMOVED")
        self:RegisterEvent("SUPER_TRACKING_CHANGED")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
    end)
    window:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        questID = nil
    end)
    CludesUI.RegisterEscapeClose(window)
end

-- Toggles the window for a quest; a second click on the same quest closes it.
function EQT.ShowQuestDetails(ident)
    if not window then
        Build()
    end
    if window:IsShown() and questID == ident then
        window:Hide()
        return
    end
    questID = ident
    scroll:SetVerticalScroll(0)
    Place()
    window:Show()
    Refresh()
end
