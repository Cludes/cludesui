if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not CludesUI.IS_FOREVER then
    return
end
-------------------------------------------------------------------------------
--  CludesUIQuestTracker_Details.lua - our quest details window (WoW Forever).
--
--  Opened from our tracker. Everything in it is read from the quest log by
--  quest ID, so no Blizzard quest or map code runs from it: opening their
--  map or quest popup from addon code taints the map's pins (their
--  SetPassThroughButtons is then blocked in combat). It works in combat.
--
--  The quest log updates constantly while questing, so the window is drawn
--  again only when what it shows changed; the buttons are always checked.
-------------------------------------------------------------------------------
local _, mod = ...
local EQT = mod.EQT

local WIDTH, HEIGHT = 360, 480
local PAD = 14
local HEADER = 52 -- title, the level line, a divider
local FOOTER = 50 -- a divider, the button row
local BUTTON_H = 24
local TILE = 34
local GAP = 6
local WHEEL_STEP = 40
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local CLOSE = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png"

-- The CludesUI panel look (see CludesUI_Popups.lua).
local PANEL_BG = { 0.062, 0.070, 0.082, 0.97 }
local TILE_BG = { 0.11, 0.10, 0.09, 1 }

-------------------------------------------------------------------------------
--  Rewards: XP, money, then one entry per currency, item and choice. An
--  entry: name, texture, count, quality, itemID, type ("reward" or "choice"),
--  index (for the quest log tooltip calls), currency. Nil when there are none.
-------------------------------------------------------------------------------
local function Entry(kind, index, name, texture, count, quality, itemID)
    return {
        name = name,
        texture = texture,
        count = count,
        quality = quality,
        itemID = itemID,
        type = kind,
        index = index,
    }
end

function EQT.QuestRewards(questID)
    if not C_QuestLog.ShouldShowQuestRewards(questID) then
        return
    end
    local found = {
        xp = GetQuestLogRewardXP(questID),
        money = GetQuestLogRewardMoney(questID),
        rewards = {},
        choices = {},
    }
    for i, c in ipairs(C_QuestLog.GetQuestRewardCurrencies(questID)) do
        local e = Entry("reward", i, c.name, c.texture, c.totalRewardAmount, c.quality)
        e.currency = true
        found.rewards[#found.rewards + 1] = e
    end
    for i = 1, GetNumQuestLogRewards(questID) do
        local name, texture, count, quality, _, itemID = GetQuestLogRewardInfo(i, questID)
        found.rewards[#found.rewards + 1] = Entry("reward", i, name, texture, count, quality, itemID)
    end
    for i = 1, GetNumQuestLogChoices(questID) do
        local name, texture, count, quality, _, itemID = GetQuestLogChoiceInfo(i, questID)
        found.choices[#found.choices + 1] = Entry("choice", i, name, texture, count, quality, itemID)
    end
    if found.xp <= 0 and found.money <= 0 and #found.rewards == 0 and #found.choices == 0 then
        return
    end
    return found
end

-- Calls fn once an entry's item, not yet cached, has loaded.
function EQT.OnRewardLoad(e, fn)
    local entry = e.itemID and Item:CreateFromItemID(e.itemID)
    if entry and not entry:IsItemEmpty() and not entry:IsItemDataCached() then
        entry:ContinueOnItemLoad(fn)
    end
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local window, scroll, content, title, levelLine
local texts, tiles, marks = {}, {}, {}
local nTexts, nTiles, nMarks = 0, 0, 0
local questID
local drawn -- what the window shows, as one string
local dragged = false -- the player moved it: it no longer follows the tracker

local function Accent()
    local c = CludesUI.CLUDES_GREEN
    return c.r, c.g, c.b
end

local function Dim()
    local c = CludesUI.TEXT_DIM
    return c.r, c.g, c.b, c.a
end

local function Style(text, size)
    local outline = CludesUI.GetFontOutlineFlag("questTracker")
    if not pcall(text.SetFont, text, EQT.GetFont(), size, outline) then
        text:SetFont("Fonts/FRIZQT__.TTF", size, outline)
    end
end

local INNER = WIDTH - PAD * 2

-- Wrapped text at x, y in the scrolled content; returns its height.
local function AddText(value, x, y, size, red, green, blue, a)
    nTexts = nTexts + 1
    local text = texts[nTexts]
    if not text then
        text = content:CreateFontString(nil, "OVERLAY")
        text:SetJustifyH("LEFT")
        text:SetWordWrap(true)
        texts[nTexts] = text
    end
    Style(text, size)
    text:SetSpacing(2)
    text:SetWidth(INNER - x)
    text:SetTextColor(red, green, blue, a or 1)
    text:SetText(value)
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
    text:Show()
    return math.ceil(text:GetStringHeight())
end

-- A section heading: small capitals in the accent colour.
local function AddHeading(value, y)
    local red, green, blue = Accent()
    return AddText(value:upper(), 0, y, 11, red, green, blue) + 6
end

-- An objective's mark: a tick when done, else a small accent square.
local function AddMark(done, y)
    nMarks = nMarks + 1
    local mark = marks[nMarks]
    if not mark then
        mark = content:CreateTexture(nil, "ARTWORK")
        marks[nMarks] = mark
    end
    mark:ClearAllPoints()
    if done then
        mark:SetTexture(CHECK)
        mark:SetVertexColor(1, 1, 1, 1)
        mark:SetSize(12, 12)
        mark:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    else
        local red, green, blue = Accent()
        mark:SetColorTexture(red, green, blue, 0.9)
        mark:SetSize(4, 4)
        mark:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 5))
    end
    mark:Show()
end

local function TileAtRest(tile)
    local c = CludesUI.BORDER_COLOR
    tile.frame:SetColor(c.r, c.g, c.b, 0.15)
end

local function TileEnter(self)
    local red, green, blue = Accent()
    self.frame:SetColor(red, green, blue, 0.6)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.entry.currency then
        GameTooltip:SetQuestLogCurrency(self.entry.type, self.entry.index, questID)
    else
        GameTooltip:SetQuestLogItem(self.entry.type, self.entry.index, questID)
    end
    GameTooltip:Show()
end

local function TileLeave(self)
    TileAtRest(self)
    GameTooltip:Hide()
end

local function NewTile()
    local tile = CreateFrame("Button", nil, content)
    local bgTex = tile:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(TILE_BG[1], TILE_BG[2], TILE_BG[3], TILE_BG[4])
    tile.frame = CludesUI.MakeBorder(tile, 1, 1, 1, 0.15)
    local holder = CreateFrame("Frame", nil, tile)
    holder:SetSize(TILE - 8, TILE - 8)
    holder:SetPoint("LEFT", 4, 0)
    tile.icon = holder:CreateTexture(nil, "ARTWORK")
    tile.icon:SetAllPoints()
    tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tile.quality = CludesUI.MakeBorder(holder, 0, 0, 0, 1)
    tile.count = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    tile.count:SetPoint("BOTTOMRIGHT", 1, 0)
    tile.name = tile:CreateFontString(nil, "OVERLAY")
    tile.name:SetPoint("LEFT", holder, "RIGHT", 6, 0)
    tile.name:SetPoint("RIGHT", -4, 0)
    tile.name:SetJustifyH("LEFT")
    tile.name:SetMaxLines(2)
    tile:SetScript("OnEnter", TileEnter)
    tile:SetScript("OnLeave", TileLeave)
    return tile
end

local function AddTile(e, x, y, width)
    nTiles = nTiles + 1
    local tile = tiles[nTiles]
    if not tile then
        tile = NewTile()
        tiles[nTiles] = tile
    end
    tile.entry = e
    tile:SetSize(width, TILE)
    tile:ClearAllPoints()
    tile:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
    local c = e.quality and ColorManager.GetColorDataForItemQuality(e.quality)
    if c then
        tile.quality:SetColor(c.r, c.g, c.b, 1)
    else
        tile.quality:SetColor(0, 0, 0, 1)
    end
    tile.icon:SetTexture(e.texture)
    tile.count:SetText((e.count and e.count > 1) and e.count or "")
    Style(tile.name, 11)
    tile.name:SetText(e.name or RETRIEVING_DATA)
    if c then
        tile.name:SetTextColor(c.r, c.g, c.b)
    else
        tile.name:SetTextColor(1, 1, 1)
    end
    TileAtRest(tile)
    tile:Show()
end

-- Tiles in two columns; returns the height used.
local function AddTiles(entries, y)
    local width = (INNER - GAP) / 2
    for i, e in ipairs(entries) do
        local column, row = (i - 1) % 2, math.floor((i - 1) / 2)
        AddTile(e, column * (width + GAP), y + row * (TILE + GAP), width)
    end
    local rows = math.ceil(#entries / 2)
    return rows * TILE + math.max(0, rows - 1) * GAP
end

-- The level (in its difficulty colour), the quest type and "Complete".
local function LevelLine()
    local parts = {}
    local level = C_QuestLog.GetQuestDifficultyLevel(questID)
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

local function SetButtonOn(button, on)
    button:SetEnabled(on)
    button:SetAlpha(on and 1 or 0.35)
end

local function UpdateButtons()
    local focused = C_SuperTrack.GetSuperTrackedQuestID() == questID
    window.focus.label:SetText(focused and STOP_SUPER_TRACK_QUEST or SUPER_TRACK_QUEST)
    SetButtonOn(window.share, IsInGroup() and C_QuestLog.IsPushableQuest(questID))
    SetButtonOn(window.abandon, C_QuestLog.CanAbandonQuest(questID))
end

-- Everything the window would show, read once, with a fingerprint of it.
local function Read(logIndex)
    local q = {
        title = C_QuestLog.GetTitleForQuestID(questID) or "",
        level = LevelLine(),
        objectives = C_QuestLog.GetQuestObjectives(questID) or {},
        rewards = EQT.QuestRewards(questID),
    }
    q.description, q.objectivesText = GetQuestLogQuestText(logIndex)
    local parts = { q.title, q.level, tostring(q.description), tostring(q.objectivesText) }
    for _, o in ipairs(q.objectives) do
        parts[#parts + 1] = tostring(o.text) .. (o.finished and "+" or "-")
    end
    local region = q.rewards
    if region then
        parts[#parts + 1] = region.xp .. "/" .. region.money
        for _, list in ipairs({ region.rewards, region.choices }) do
            for _, e in ipairs(list) do
                parts[#parts + 1] = table.concat(
                    { tostring(e.name), tostring(e.texture), tostring(e.count), tostring(e.quality) },
                    ","
                )
            end
            parts[#parts + 1] = "|"
        end
    end
    return q, table.concat(parts, "\n")
end

local Refresh

-- force: draw even if nothing seems to have changed.
function Refresh(force)
    if not (window and window:IsShown() and questID) then
        return
    end
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    if not logIndex then
        window:Hide()
        return
    end
    local q, fingerprint = Read(logIndex)
    if not force and fingerprint == drawn then
        UpdateButtons()
        return
    end
    drawn = fingerprint
    nTexts, nTiles, nMarks = 0, 0, 0
    local dr, dg, db, da = Dim()
    title:SetText(q.title)
    levelLine:SetText(q.level)
    window.bar:SetColorTexture(Accent())

    local y = 0
    local objectivesText = q.objectivesText
    if #q.objectives > 0 or (objectivesText and objectivesText ~= "") then
        y = y + AddHeading(QUEST_OBJECTIVES, y)
        for _, o in ipairs(q.objectives) do
            if o.text and o.text ~= "" then
                AddMark(o.finished, y)
                if o.finished then
                    y = y + AddText(o.text, 18, y, 12, dr, dg, db, da) + 4
                else
                    y = y + AddText(o.text, 18, y, 12, 1, 1, 1) + 4
                end
            end
        end
        if objectivesText and objectivesText ~= "" then
            y = y + 4 + AddText(objectivesText, 0, y + 4, 12, dr, dg, db, da)
        end
        y = y + 16
    end
    if q.description and q.description ~= "" then
        y = y + AddHeading(QUEST_DESCRIPTION, y)
        y = y + AddText(q.description, 0, y, 12, 0.9, 0.9, 0.9) + 16
    end

    local region = q.rewards
    if region then
        y = y + AddHeading(QUEST_REWARDS, y)
        if region.xp > 0 then
            y = y + AddText(BONUS_OBJECTIVE_EXPERIENCE_FORMAT:format(region.xp), 0, y, 12, 1, 1, 1) + 4
        end
        if region.money > 0 then
            y = y + AddText(GetMoneyString(region.money), 0, y, 12, 1, 1, 1) + 4
        end
        if #region.rewards > 0 then
            y = y + 4 + AddTiles(region.rewards, y + 4) + 4
        end
        if #region.choices > 0 then
            y = y + 8
            y = y + AddText(REWARD_CHOICES, 0, y, 12, dr, dg, db, da) + 6
            y = y + AddTiles(region.choices, y)
        end
        -- An item not cached yet: draw again when it loads, if still on this quest.
        local shownQuest = questID
        for _, list in ipairs({ region.rewards, region.choices }) do
            for _, e in ipairs(list) do
                if not e.name then
                    EQT.OnRewardLoad(e, function()
                        if questID == shownQuest then
                            Refresh(true)
                        end
                    end)
                end
            end
        end
    end

    for i = nTexts + 1, #texts do
        texts[i]:Hide()
    end
    for i = nTiles + 1, #tiles do
        tiles[i]:Hide()
    end
    for i = nMarks + 1, #marks do
        marks[i]:Hide()
    end
    content:SetSize(INNER, math.max(1, y))
    local furthest = math.max(0, y - scroll:GetHeight())
    scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), furthest))
    UpdateButtons()
end

-- Beside the tracker, on the side towards the middle of the screen.
local function Place()
    if dragged then
        return
    end
    local tracker = _G.CUI_CustomQuestTracker
    window:ClearAllPoints()
    local x = tracker and tracker:GetCenter()
    if not x then
        window:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    elseif x * tracker:GetEffectiveScale() > UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2 then
        window:SetPoint("TOPRIGHT", tracker, "TOPLEFT", -8, 0)
    else
        window:SetPoint("TOPLEFT", tracker, "TOPRIGHT", 8, 0)
    end
end

local function Button(label, onClick)
    local button = CreateFrame("Button", nil, window)
    button:SetSize((WIDTH - PAD * 2 - GAP * 3) / 4, BUTTON_H)
    local _, _, text = CludesUI.MakeStyledButton(button, label, 11, CludesUI.WB_COLOURS, onClick)
    text:SetWidth(button:GetWidth() - 6)
    text:SetWordWrap(false)
    button.label = text
    return button
end

local function Divider(y, fromBottom)
    local c = CludesUI.BORDER_COLOR
    local line = window:CreateTexture(nil, "BORDER")
    line:SetColorTexture(c.r, c.g, c.b, 0.15)
    line:SetHeight(1)
    local side = fromBottom and "BOTTOM" or "TOP"
    line:SetPoint(side .. "LEFT", PAD, y)
    line:SetPoint(side .. "RIGHT", -PAD, y)
end

local function Build()
    window = CreateFrame("Frame", "CUI_QuestDetails", UIParent)
    window:SetSize(WIDTH, HEIGHT)
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
        dragged = true
    end)
    window:Hide()

    local bgTex = window:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(PANEL_BG[1], PANEL_BG[2], PANEL_BG[3], PANEL_BG[4])
    local c = CludesUI.BORDER_COLOR
    CludesUI.MakeBorder(window, c.r, c.g, c.b, 0.15)

    -- The header: an accent bar, the title, the level line.
    window.bar = window:CreateTexture(nil, "ARTWORK")
    window.bar:SetSize(2, 32)
    window.bar:SetPoint("TOPLEFT", PAD, -PAD + 2)
    title = window:CreateFontString(nil, "OVERLAY")
    Style(title, 15)
    title:SetTextColor(1, 1, 1)
    title:SetPoint("TOPLEFT", window.bar, "TOPRIGHT", 8, 0)
    title:SetPoint("RIGHT", -34, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    levelLine = window:CreateFontString(nil, "OVERLAY")
    Style(levelLine, 11)
    levelLine:SetTextColor(Dim())
    levelLine:SetPoint("BOTTOMLEFT", window.bar, "BOTTOMRIGHT", 8, 0)
    levelLine:SetJustifyH("LEFT")
    Divider(-HEADER)

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
    scroll:SetPoint("TOPLEFT", PAD, -HEADER - 12)
    scroll:SetPoint("BOTTOMRIGHT", -PAD, FOOTER + 8)
    scroll:SetClipsChildren(true)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local furthest = math.max(0, content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScroll() - delta * WHEEL_STEP, furthest)))
    end)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(INNER, 1)
    scroll:SetScrollChild(content)

    -- The footer: one row of buttons.
    Divider(FOOTER, true)
    local act = EQT.CustomQuestActions
    window.focus = Button(SUPER_TRACK_QUEST, function()
        act.Focus(questID)
    end)
    window.focus:SetPoint("BOTTOMLEFT", PAD, PAD)
    window.untrack = Button(UNTRACK_QUEST_ABBREV, function()
        act.Untrack(questID)
    end)
    window.untrack:SetPoint("LEFT", window.focus, "RIGHT", GAP, 0)
    window.share = Button(SHARE_QUEST_ABBREV, function()
        QuestLogPushQuest(C_QuestLog.GetLogIndexForQuestID(questID))
    end)
    window.share:SetPoint("LEFT", window.untrack, "RIGHT", GAP, 0)
    window.abandon = Button(ABANDON_QUEST_ABBREV, function()
        act.Abandon(questID)
    end)
    window.abandon:SetPoint("LEFT", window.share, "RIGHT", GAP, 0)

    window:SetScript("OnEvent", function(_, event, id)
        if event == "QUEST_REMOVED" then
            if id == questID then
                window:Hide()
            end
        elseif event == "SUPER_TRACKING_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
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
        drawn = nil
    end)
    CludesUI.RegisterEscapeClose(window)
end

-- Opens the window for a quest; a second click on the same quest closes it.
function EQT.ShowQuestDetails(id)
    if not window then
        Build()
    end
    if window:IsShown() and questID == id then
        window:Hide()
        return
    end
    questID = id
    scroll:SetVerticalScroll(0)
    Place()
    window:Show()
    Refresh(true)
end
