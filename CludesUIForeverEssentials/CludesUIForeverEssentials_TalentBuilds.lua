if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_TalentBuilds.lua  (WoW Forever only)
--  Talent Builds (/cbuilds): talent builds as the order you spend points,
--  kept per class on the account.
--    Save Current  your talents now, in tree-row order
--    Follow        one build per character: its next talent shows in the
--                  window, lights up in CludesUI's talent window, and each
--                  level-up says it in chat; Learn spends your unspent
--                  points along it (out of combat)
--    Share         Export gives a line to paste; Import takes one
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("talentBuilds", { enabled = true, levelUpLine = true })
local Get, On = F.Get, F.Enabled
local PREFIX = "CUIB1"
local PALETTE = CUI.Kit.Palette

local Builds = {}

local function ClassID() return select(3, UnitClass("player")) end

-- This class's builds: { { name, points = { nodeID, ... } }, ... }
function Builds.List()
    local conf = F.Cfg()
    conf.builds = conf.builds or {}
    local class = ClassID()
    conf.builds[class] = conf.builds[class] or {}
    return conf.builds[class]
end

-- The build this character follows (by GUID), or nil.
function Builds.Followed()
    local guid = UnitGUID("player")
    local name = guid and (F.Read().follow or {})[guid]
    if not name then return end
    for _, build in ipairs(Builds.List()) do
        if build.name == name then return build end
    end
end

function Builds.Follow(build)
    local conf = F.Cfg()
    conf.follow = conf.follow or {}
    conf.follow[UnitGUID("player")] = build and build.name or nil
end

-------------------------------------------------------------------------------
--  The talent tree now
-------------------------------------------------------------------------------
-- configID, { [nodeID] = tree index }, trees
local function Trees()
    local configID, _, trees = CUI.ForeverTalentTrees()
    local where = {}
    for index, t in ipairs(trees or {}) do
        for _, node in ipairs(t.nodes) do
            where[node] = index
        end
    end
    return configID, where, trees or {}
end

-- Talent points not spent yet (the tree's currency, as the talent windows read it).
function Builds.Unspent()
    local configID, treeID = CUI.ForeverTalentTrees()
    local currency = configID and treeID and C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
    return currency and currency[1] and currency[1].quantity or 0
end

local function Rank(configID, node)
    local info = configID and C_Traits.GetNodeInfo(configID, node)
    return info and info.activeRank or 0
end

function Builds.TalentName(configID, node)
    local info = configID and C_Traits.GetNodeInfo(configID, node)
    local entryID = info and (info.activeEntry and info.activeEntry.entryID or info.entryIDs[1])
    local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
    local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
    local spell = def and def.spellID
    return spell and C_Spell.GetSpellName(spell) or ("Talent " .. node), spell and C_Spell.GetSpellTexture(spell)
end

-- Points per tree, "31/20/0".
function Builds.Split(points, where, count)
    local per = { 0, 0, 0 }
    for _, node in ipairs(points) do
        local t = where[node]
        if t then per[t] = (per[t] or 0) + 1 end
    end
    return table.concat(per, "/", 1, math.max(3, count or 3))
end

-- The build's next point you have not spent: its node and position, or nil.
function Builds.Next(build, configID)
    if not build then return end
    local counted = {}
    for index, node in ipairs(build.points) do
        counted[node] = (counted[node] or 0) + 1
        if Rank(configID, node) < counted[node] then return node, index end
    end
end

-- Your talents now, as a build: in each tree's row order, a talent's ranks
-- together.
function Builds.FromCurrent(name)
    local configID, _, trees = Trees()
    if not configID then return end
    local picked = {}
    for _, t in ipairs(trees) do
        local grid = CUI.TalentTreeGrid(configID, t.nodes) or {}
        for _, node in ipairs(t.nodes) do
            local rank = Rank(configID, node)
            if rank > 0 then
                local cell = grid[node]
                picked[#picked + 1] = { node = node, rank = rank, row = cell and cell.row or 0, col = cell and cell.col or 0 }
            end
        end
    end
    table.sort(picked, function(lhs, rhs)
        if lhs.row ~= rhs.row then return lhs.row < rhs.row end
        if lhs.col ~= rhs.col then return lhs.col < rhs.col end
        return lhs.node < rhs.node
    end)
    local points = {}
    for _, p in ipairs(picked) do
        for _ = 1, p.rank do
            points[#points + 1] = p.node
        end
    end
    if #points == 0 then return end
    return { name = name, points = points }
end

function Builds.Add(build)
    local list = Builds.List()
    for index, b in ipairs(list) do
        if b.name == build.name then
            list[index] = build
            return
        end
    end
    list[#list + 1] = build
end

function Builds.Remove(build)
    local list = Builds.List()
    for index, b in ipairs(list) do
        if b == build then table.remove(list, index) end
    end
    if Builds.Followed() == build then Builds.Follow(nil) end
end

function Builds.Export(build)
    local name = build.name:gsub("[:,]", " ")
    local nodes = {}
    for index, node in ipairs(build.points) do
        nodes[index] = tostring(node)
    end
    return table.concat({ PREFIX, tostring(ClassID()), name, table.concat(nodes, ",") }, ":")
end

-- A build from an Export line, or nil and why.
function Builds.Import(text)
    local prefix, class, name, list = (text or ""):match("^%s*(%w+):(%d+):([^:]*):([%d,]+)%s*$")
    if prefix ~= PREFIX then return nil, "That is not a CludesUI talent build." end
    if tonumber(class) ~= ClassID() then return nil, "That build is for another class." end
    local points = {}
    for node in list:gmatch("%d+") do
        points[#points + 1] = tonumber(node)
        if #points > 61 then return nil, "That build has too many points." end
    end
    if name == "" then name = "Imported" end
    return { name = name, points = points }
end

-- The commit saves into the loadout the game's window has selected for this
-- spec, as CludesUI's talent window's Learn does (never the active config's
-- own ID, which is no saved loadout).
local function SavedConfigID(configID)
    local specInfo = C_SpecializationInfo.GetSpecialization()
    local specID = specInfo and C_SpecializationInfo.GetSpecializationInfo(specInfo)
    if not specID then return nil end
    local saved = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    local consts = Constants and Constants.TraitConsts
    if saved == configID or (consts and saved == consts.STARTER_BUILD_TRAIT_CONFIG_ID) then return nil end
    return saved
end

-- Spends unspent points along the build; how many it learned.
function Builds.Learn(build)
    local configID = Trees()
    if not (build and configID) or InCombatLockdown() then return 0 end
    local bought = 0
    while true do
        local node = Builds.Next(build, configID)
        if not node or not C_Traits.PurchaseRank(configID, node) then break end
        bought = bought + 1
    end
    if bought > 0 and not C_ClassTalents.CommitConfig(SavedConfigID(configID)) then
        C_Traits.RollbackConfig(configID)
        return 0
    end
    return bought
end

-------------------------------------------------------------------------------
--  The window
-------------------------------------------------------------------------------
local window
local picked -- the build on show

local function Say(text) CUI.Print(CUI.HexColor(CUI.Kit.Accent()) .. "Talent Builds|r: " .. text) end

local Render

local function BuildWindow()
    local K = CUI.Kit
    window = K.Window("CludesUITalentBuilds", 380, 440, "Talent Builds", { key = "essentials" })
    window:Hide()
    local function Text(size, colour)
        local fs = window:CreateFontString(nil, "OVERLAY")
        K.Font(fs, size, "essentials")
        fs:SetTextColor(unpack(colour))
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        return fs
    end
    window.sub = Text(K.SMALL_SIZE, PALETTE.muted)
    window.sub:SetPoint("TOPLEFT", 12, -36)
    window.sub:SetPoint("RIGHT", -12, 0)
    window.rows = {}
    for index = 1, 8 do
        local row = CreateFrame("Button", nil, window)
        row:SetHeight(K.ROW_H)
        row:SetPoint("TOPLEFT", 10, -56 - (index - 1) * K.ROW_H)
        row:SetPoint("TOPRIGHT", -10, -56 - (index - 1) * K.ROW_H)
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 1, 1, 0.07)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.04)
        row.right = row:CreateFontString(nil, "OVERLAY")
        K.Font(row.right, K.SMALL_SIZE, "essentials")
        row.right:SetPoint("RIGHT", -6, 0)
        row.name = row:CreateFontString(nil, "OVERLAY")
        K.Font(row.name, K.TEXT_SIZE, "essentials")
        row.name:SetPoint("LEFT", 6, 0)
        row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            picked = self.build
            Render()
        end)
        window.rows[index] = row
    end
    window.empty = Text(K.TEXT_SIZE, PALETTE.muted)
    window.empty:SetPoint("TOPLEFT", 16, -62)
    window.empty:SetText("No builds yet: Save Current, or Import one.")
    -- the picked build: its next talent and Learn
    window.nextLabel = Text(K.SMALL_SIZE, PALETTE.muted)
    window.nextLabel:SetPoint("TOPLEFT", 12, -246)
    window.nextIcon = window:CreateTexture(nil, "ARTWORK")
    window.nextIcon:SetSize(24, 24)
    window.nextIcon:SetPoint("TOPLEFT", 12, -264)
    window.nextIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    window.nextName = Text(K.TEXT_SIZE, PALETTE.text)
    window.nextName:SetPoint("LEFT", window.nextIcon, "RIGHT", 8, 0)
    window.nextName:SetPoint("RIGHT", -150, 0)
    window.learn = K.Button(window, "Learn", 130, 26, function()
        local n = Builds.Learn(picked)
        if n > 0 then Say(("learned %d talent %s from %s."):format(n, n == 1 and "point" or "points", picked.name)) end
        Render()
    end, { key = "essentials", tip = "Spends your unspent talent points along this build, in its order. Not in combat." })
    window.learn:SetPoint("TOPRIGHT", -12, -264)
    window.learn:SetActive(true)
    window.follow = K.Button(window, "Follow", 80, 24, function()
        Builds.Follow(Builds.Followed() == picked and nil or picked)
        Render()
    end, { key = "essentials", tip = "Following a build: its next talent lights up in CludesUI's talent window, and each level-up says it in chat." })
    window.follow:SetPoint("TOPLEFT", 12, -302)
    window.export = K.Button(window, "Export", 70, 24, function()
        if not picked then return end
        window.line:SetText(Builds.Export(picked))
        window.line:SetFocus()
        window.line:HighlightText()
    end, { key = "essentials", tip = "Puts the build's line in the box below to copy and share." })
    window.export:SetPoint("LEFT", window.follow, "RIGHT", 6, 0)
    window.delete = K.Button(window, "Delete", 70, 24, function()
        if picked and IsShiftKeyDown() then
            Builds.Remove(picked)
            picked = nil
            Render()
        else
            Say("Shift-click Delete to delete the build.")
        end
    end, { key = "essentials", tip = "Shift-click to delete the build." })
    window.delete:SetPoint("LEFT", window.export, "RIGHT", 6, 0)
    window.line = K.Input(window, 356, 24, "Paste a build line here, then Import", "essentials")
    window.line:SetPoint("BOTTOMLEFT", 12, 48)
    window.save = K.Button(window, "Save Current", 110, 26, function()
        local name = ("%s %s"):format(UnitClass("player"), date("%d %b"))
        local build = Builds.FromCurrent(name)
        if not build then return Say("you have no talent points spent to save.") end
        Builds.Add(build)
        picked = build
        Render()
    end, { key = "essentials", tip = "Saves your talents now as a build, in tree-row order." })
    window.save:SetPoint("BOTTOMLEFT", 12, 12)
    window.import = K.Button(window, "Import", 80, 26, function()
        local build, why = Builds.Import(window.line:GetText())
        if not build then return Say(why) end
        Builds.Add(build)
        picked = build
        window.line:SetText("")
        Say(("added %s (%d points)."):format(build.name, #build.points))
        Render()
    end, { key = "essentials", tip = "Adds the build line in the box above." })
    window.import:SetPoint("LEFT", window.save, "RIGHT", 6, 0)
end

Render = function()
    if not (window and window:IsShown()) then return end
    local configID, where, trees = Trees()
    local list, followed = Builds.List(), Builds.Followed()
    local ar, ag, ab = CUI.Kit.Accent()
    local unspent = Builds.Unspent()
    window.sub:SetText(("%s builds, on this account. %d unspent %s."):format(
        UnitClass("player"),
        unspent,
        unspent == 1 and "point" or "points"
    ))
    if picked and not tContains(list, picked) then picked = nil end
    picked = picked or followed or list[1]
    for index, row in ipairs(window.rows) do
        local build = list[index]
        row.build = build
        row:SetShown(build ~= nil)
        if build then
            row.name:SetText(build.name .. (build == followed and ("  " .. CUI.HexColor(ar, ag, ab) .. "following|r") or ""))
            row.right:SetText(Builds.Split(build.points, where, #trees) .. "  " .. #build.points .. " pts")
            row.right:SetTextColor(unpack(PALETTE.muted))
            row.sel:SetShown(build == picked)
        end
    end
    window.empty:SetShown(#list == 0)
    local node = picked and Builds.Next(picked, configID)
    for _, w in ipairs({ window.nextLabel, window.nextIcon, window.nextName, window.learn, window.follow, window.export, window.delete }) do
        w:SetShown(picked ~= nil)
    end
    if picked then
        window.follow:SetText(picked == followed and "Unfollow" or "Follow")
        window.follow:SetActive(picked == followed)
        if node then
            local name, icon = Builds.TalentName(configID, node)
            window.nextLabel:SetText("NEXT TALENT")
            window.nextIcon:SetTexture(icon or 134400)
            window.nextName:SetText(name)
        else
            window.nextLabel:SetText("NEXT TALENT")
            window.nextIcon:SetTexture(nil)
            window.nextName:SetText("All of this build is learned.")
        end
        local points = Builds.Unspent()
        local can = node ~= nil and points > 0 and not InCombatLockdown()
        window.learn:SetText(can and ("Learn %d"):format(points) or "Learn")
        window.learn:SetEnabled(can)
        window.learn:SetAlpha(can and 1 or 0.45)
    end
end

function Builds.Toggle()
    if not On() then return Say("turn on Talent Builds in Forever Tools first.") end
    if not window then BuildWindow() end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
        Render()
    end
end

SLASH_CUITALENTBUILDS1 = "/cbuilds"
SlashCmdList.CUITALENTBUILDS = function() Builds.Toggle() end

-------------------------------------------------------------------------------
--  Following: the next talent for CludesUI's talent window, and level-ups
-------------------------------------------------------------------------------
-- The followed build's next node, for the talent window to light up.
-- Asked once per talent button on a repaint: kept for the frame.
local nextAt, nextNode = nil, nil
function Builds.FollowNext()
    if not On() then return end
    local now = GetTime()
    if nextAt == now then return nextNode end
    local build = Builds.Followed()
    nextAt, nextNode = now, build and (Builds.Next(build, (Trees()))) or nil
    return nextNode
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LEVEL_UP" then
        C_Timer.After(1, function()
            local build = Builds.Followed()
            local configID = Trees()
            local node = build and Builds.Next(build, configID)
            if node and Get("levelUpLine") then
                Say(("next from %s: %s. /cbuilds to learn it."):format(build.name, (Builds.TalentName(configID, node))))
            end
        end)
    end
    Render()
end)

local function Apply()
    events:UnregisterAllEvents()
    if window and not On() then window:Hide() end
    if not On() then return end
    for _, event in ipairs({ "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED", "CHARACTER_POINTS_CHANGED", "PLAYER_REGEN_ENABLED" }) do
        pcall(events.RegisterEvent, events, event)
    end
end

CUI._TalentBuilds = { Get = Get, Cfg = F.Cfg, Apply = Apply, Builds = Builds }

F.Start(Apply)
