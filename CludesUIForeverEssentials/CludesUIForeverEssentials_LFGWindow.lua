if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_LFGWindow.lua  (WoW Forever only)
--  The Looking For Group window (/clfg), three tabs:
--    Browse      Forever's listings for your level (or every dungeon, or
--                one): leader, level, zone, the group's roles and size,
--                the dungeon, and for CludesUI leaders their Gear Score,
--                boss kills, quests and what they need. Apply sends your
--                card; Whisper opens a whisper to any leader.
--    Your Group  your listing and the CludesUI players who applied, best
--                Gear Score first: Invite or Decline each.
--    Create      list a dungeon in Forever's finder: the roles you still
--                need, a minimum Gear Score, a style and a note.
--  Opening it turns Looking For Group on. The rules are in
--  CludesUIForeverEssentials_LFG.lua.
-------------------------------------------------------------------------------
local _, module = ...

local GF = module.LFG
if not GF then return end
local LFG = CUI._LFG
local Kit = CUI.Kit
local Pal = Kit.Palette
local Card, Comms, Listings, Search, Group, Browse = GF.Card, GF.Comms, GF.Listings, GF.Search, GF.Group, GF.Browse

local WIN_W, WIN_H = 660, 480
local PAD = 10
local TAB_H = 22
local BAR_H = 24
local ROW_H = 42
local TILE_COLS, TILE_H, TILE_GAP = 4, 40, 6
local STYLES = { GROUP_FINDER_GENERAL_PLAYSTYLE1 or "Learning", GROUP_FINDER_GENERAL_PLAYSTYLE2 or "Relaxed",
    GROUP_FINDER_GENERAL_PLAYSTYLE3 or "Competitive", GROUP_FINDER_GENERAL_PLAYSTYLE4 or "Carry Offered" }
local SORT_NAMES = { newest = "Newest", score = "Gear Score", level = "Dungeon Level" }
local SORT_ORDER = { "newest", "score", "level" }
local ROLE_LETTERS = { { Card.TANK, "T" }, { Card.HEALER, "H" }, { Card.DAMAGE, "D" } }

local window, tabs, pages = nil, {}, {}
local tab = "browse"
local browse, yours, create = {}, {}, {}
local needle = ""
local order = {}

local function Secret(v) return v ~= nil and issecretvalue and issecretvalue(v) end

local function Text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Kit.Font(fs, size or Kit.TEXT_SIZE, "essentials")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    local c = color or Pal.text
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

local function ClassHex(class)
    local token = type(class) == "number" and select(2, GetClassInfo(class)) or class
    local cc = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    return cc and ("|cff%02x%02x%02x"):format(cc.r * 255, cc.g * 255, cc.b * 255) or "|cffffffff"
end

local function RoleText(mask)
    local parts = {}
    for _, pair in ipairs(ROLE_LETTERS) do
        if bit.band(mask or 0, pair[1]) ~= 0 then parts[#parts + 1] = pair[2] end
    end
    return table.concat(parts)
end

local function Age(seconds)
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return ("%dm ago"):format(seconds / 60) end
    return ("%dh ago"):format(seconds / 3600)
end

local function Score(tenths) return tenths and ("%.1f"):format(tenths / 10) or nil end

local function KillsText(cardRec)
    if not (cardRec and cardRec.killsShared) then return nil end
    local total = 0
    for i = 1, cardRec.killCount do
        total = total + cardRec.killList[i]
    end
    if total == 0 then return "First time" end
    return total == 1 and "1 boss kill" or ("%d boss kills"):format(total)
end

local function QuestsText(cardRec)
    if not (cardRec and cardRec.questsShared) or cardRec.haveCount == 0 then return nil end
    return cardRec.haveCount == 1 and "1 quest" or ("%d quests"):format(cardRec.haveCount)
end

local function Whisper(name)
    local SendTell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if SendTell then SendTell(name, DEFAULT_CHAT_FRAME) end
end

local function TurnOn()
    if not LFG.Get("enabled") then
        LFG.Cfg().enabled = true
        LFG.Apply()
    end
end

local Paint

-------------------------------------------------------------------------------
--  Browse
-------------------------------------------------------------------------------
local function PickText()
    if Search.pick == Search.ALL then return "Every dungeon" end
    if Search.pick == Search.LEVEL then return "For your level" end
    local act = Listings.ActivityFacts(Search.pick)
    return act and act.short or "For your level"
end

local function DungeonMenu(owner)
    Kit.ContextMenu(owner, function(_, root)
        root:CreateRadio("For your level", function() return Search.pick == Search.LEVEL end, function() Search.Run(Search.LEVEL) Paint() end)
        root:CreateRadio("Every dungeon", function() return Search.pick == Search.ALL end, function() Search.Run(Search.ALL) Paint() end)
        root:CreateDivider()
        local items = {}
        Search.ActivityList(items)
        for _, ref in ipairs(items) do
            local act = Listings.ActivityFacts(ref)
            local label = act.max > 0 and ("%s  %d-%d"):format(act.short, act.min, act.max) or act.short
            if not Search.FitsLevel(ref) then label = "|cff808080" .. label .. "|r" end
            root:CreateRadio(label, function() return Search.pick == ref end, function() Search.Run(ref) Paint() end)
        end
    end)
end

local function SortMenu(owner)
    Kit.ContextMenu(owner, function(_, root)
        for _, nameKey in ipairs(SORT_ORDER) do
            root:CreateRadio(SORT_NAMES[nameKey], function() return LFG.Get("sort") == nameKey end, function()
                LFG.Cfg().sort = nameKey
                Paint()
            end)
        end
    end)
end

local function ApplyRow(row)
    if row.leaderName then Browse.Apply(row.leaderName, row.dungeon) end
    Paint()
end

local function NewBrowseRow(i)
    local content = browse.content
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 2))
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.05)
    row.head = Text(row, Kit.TEXT_SIZE)
    row.head:SetPoint("TOPLEFT", 8, -6)
    row.head:SetPoint("RIGHT", row, "RIGHT", -230, 0)
    row.sub = Text(row, Kit.SMALL_SIZE, Pal.muted)
    row.sub:SetPoint("BOTTOMLEFT", 8, 6)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -150, 0)
    row.slots = Text(row, Kit.SMALL_SIZE, Pal.text)
    row.slots:SetPoint("TOPRIGHT", row, "TOPRIGHT", -150, -6)
    row.slots:SetJustifyH("RIGHT")
    row.age = Text(row, Kit.SMALL_SIZE, Pal.muted)
    row.age:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -150, 6)
    row.age:SetJustifyH("RIGHT")
    row.apply = Kit.Button(row, "Apply", 64, 20, function() ApplyRow(row) end, { key = "essentials" })
    row.apply:SetPoint("RIGHT", row, "RIGHT", -74, 0)
    row.whisper = Kit.Button(row, "Whisper", 64, 20, function()
        if row.leaderName then Whisper(row.leaderName) end
    end, { key = "essentials" })
    row.whisper:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.status = Text(row, Kit.SMALL_SIZE, Pal.green)
    row.status:SetPoint("RIGHT", row.whisper, "LEFT", -8, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for _, line in ipairs(self.tip) do
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    browse.rows[i] = row
    return row
end

local function PaintBrowseRow(row, lst)
    local act = lst.activity and Listings.ActivityFacts(lst.activity)
    local leadName = lst.members[1]
    for m = 1, lst.nMembers do
        if lst.members[m].leader then leadName = lst.members[m] end
    end
    local cardRec = lst.leader and Browse.KnownCard(lst.leader)
    row.leaderName, row.dungeon = lst.leader, lst.dungeon
    local head = {}
    if leadName then
        head[#head + 1] = ClassHex(leadName.class) .. (lst.leader or leadName.name or "?") .. "|r"
        if leadName.level then head[#head + 1] = tostring(leadName.level) end
        if leadName.zone then head[#head + 1] = "|cff9aa6b2" .. leadName.zone .. "|r" end
    else
        head[#head + 1] = lst.leader or "?"
    end
    local score = cardRec and Score(cardRec.score)
    if score then head[#head + 1] = "|cffffd100GS " .. score .. "|r" end
    row.head:SetText(table.concat(head, "  "))
    local sub = {}
    if act then
        sub[#sub + 1] = act.max > 0 and ("%s %d-%d"):format(act.name, act.min, act.max) or act.name
    end
    local killList, quests = KillsText(cardRec), QuestsText(cardRec)
    if killList then sub[#sub + 1] = killList end
    if quests then sub[#sub + 1] = quests end
    row.sub:SetText(table.concat(sub, "   "))
    local size = act and act.size or 5
    if lst.numMembers <= 1 and leadName then
        row.slots:SetText(RoleText(leadName.roles))
    else
        row.slots:SetText(("T%d H%d D%d  %d/%d"):format(lst.tankCount, lst.healerCount, lst.damageCount, lst.numMembers, size))
    end
    row.age:SetText(Age(lst.age))
    local sentTo = lst.leader and Comms.AppliedTo(lst.leader)
    row.apply:SetShown(cardRec ~= nil and not lst.mine and not lst.delisted and not sentTo)
    row.whisper:SetShown(not lst.mine and lst.leader ~= nil)
    if lst.mine then
        row.status:SetText("Your group")
    elseif sentTo then
        row.status:SetText(sentTo.declined and "Declined" or sentTo.acked and "Received" or "Applied")
    else
        row.status:SetText("")
    end
    row:SetAlpha(lst.delisted and 0.4 or 1)
    local tip = {}
    local groupInfo = cardRec and cardRec.group
    if groupInfo then
        if groupInfo.min > 0 then tip[#tip + 1] = ("Minimum Gear Score %.1f"):format(groupInfo.min / 10) end
        tip[#tip + 1] = ("Needs %d tank, %d healer, %d damage"):format(groupInfo.tankCount, groupInfo.healerCount, groupInfo.damageCount)
        if groupInfo.memo ~= "" then tip[#tip + 1] = groupInfo.memo end
    end
    for m = 1, lst.nMembers do
        local m2 = lst.members[m]
        tip[#tip + 1] = ("%s%s|r %s %s%s"):format(ClassHex(m2.class), m2.name or "?", m2.level or "",
            RoleText(m2.roles), m2.zone and ("  |cff9aa6b2" .. m2.zone .. "|r") or "")
    end
    row.tip = #tip > 0 and tip or nil
    row:Show()
end

local function PaintBrowse()
    browse.pick:SetText("Dungeon: " .. PickText())
    browse.sort:SetText("Sort: " .. (SORT_NAMES[LFG.Get("sort")] or "Newest"))
    local n = Listings.Refresh()
    wipe(order)
    for i = 1, n do
        local lst = Listings.listingsList[i]
        if Browse.PassesFilter(lst, needle) then order[#order + 1] = lst end
    end
    Browse.Order(order, LFG.Get("sort"))
    for i, lst in ipairs(order) do
        PaintBrowseRow(browse.rows[i] or NewBrowseRow(i), lst)
    end
    for i = #order + 1, #browse.rows do
        browse.rows[i]:Hide()
    end
    browse.content:SetHeight(math.max(1, #order * (ROW_H + 2)))
    local state = Search.state
    local memo
    if InCombatLockdown() and IsEncounterInProgress and IsEncounterInProgress() then
        memo = "The group finder is closed during a boss fight."
    elseif state == "searching" then
        memo = "Searching..."
    elseif state == "failed" then
        memo = "The search failed. Try Search again."
    elseif state == "unavailable" then
        memo = "The group finder has nothing for your level yet."
    elseif Listings.state == "locked" then
        memo = "Listings cannot be read right now. Try again after combat."
    elseif not Listings.searched then
        memo = "Press Search to find groups."
    elseif #order == 0 then
        memo = needle ~= "" and "No group matches your filter." or "No groups listed right now."
    end
    browse.memo:SetText(memo or "")
    browse.count:SetText(Listings.searched and (#order == 1 and "1 group" or ("%d groups"):format(#order)) or "")
    Browse.Request()
end

local function BuildBrowse(page)
    browse.rows = {}
    browse.pick = Kit.Button(page, "Dungeon: For your level", 200, BAR_H - 2, function(self) DungeonMenu(self) end, { key = "essentials" })
    browse.pick:SetPoint("TOPLEFT", 0, 0)
    browse.filter = Kit.Input(page, 200, BAR_H - 2, "Filter dungeon, leader or note", "essentials")
    browse.filter:SetPoint("LEFT", browse.pick, "RIGHT", 8, 0)
    browse.filter:HookScript("OnTextChanged", function(self)
        needle = (self:GetText() or ""):lower()
        if window and window:IsShown() then PaintBrowse() end
    end)
    browse.sort = Kit.Button(page, "Sort: Newest", 130, BAR_H - 2, function(self) SortMenu(self) end, { key = "essentials" })
    browse.sort:SetPoint("LEFT", browse.filter, "RIGHT", 8, 0)
    browse.search = Kit.Button(page, "Search", 90, BAR_H - 2, function()
        Search.Run()
        Paint()
    end, { key = "essentials" })
    browse.search:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    browse.count = Text(page, Kit.SMALL_SIZE, Pal.muted)
    browse.count:SetPoint("TOPLEFT", 2, -(BAR_H + 4))
    local scroll, content = Kit.Scroll(page)
    scroll:SetPoint("TOPLEFT", 0, -(BAR_H + 22))
    scroll:SetPoint("BOTTOMRIGHT", -10, 0)
    browse.content = content
    browse.memo = Text(page, Kit.TEXT_SIZE, Pal.muted)
    browse.memo:SetPoint("TOP", scroll, "TOP", 0, -30)
    browse.memo:SetJustifyH("CENTER")
end

-------------------------------------------------------------------------------
--  Your Group
-------------------------------------------------------------------------------
local function NewApplicantRow(i)
    local content = yours.content
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW_H + 2))
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.05)
    row.head = Text(row, Kit.TEXT_SIZE)
    row.head:SetPoint("TOPLEFT", 8, -6)
    row.head:SetPoint("RIGHT", row, "RIGHT", -160, 0)
    row.sub = Text(row, Kit.SMALL_SIZE, Pal.muted)
    row.sub:SetPoint("BOTTOMLEFT", 8, 6)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -160, 0)
    row.invite = Kit.Button(row, "Invite", 70, 20, function()
        local app = row.app
        if app and not app.invited and Group.Answering() and Comms.IsApplicant(app) then
            C_PartyInfo.InviteUnit(app.name)
            app.invited = true
            Paint()
        end
    end, { key = "essentials" })
    row.invite:SetPoint("RIGHT", row, "RIGHT", -82, 0)
    row.decline = Kit.Button(row, "Decline", 70, 20, function()
        local app = row.app
        if app and Group.Answering() and Comms.IsApplicant(app) then
            if not Comms.Refuse(app.name) then
                CUI.Print("|cff4cc9f0Looking For Group:|r too many whispers are waiting to be sent. Try Decline again in a moment.")
            end
            Paint()
        end
    end, { key = "essentials" })
    row.decline:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not (self.app and self.app.memo) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.app.memo, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    yours.rows[i] = row
    return row
end

local applicantOrder = {}
local function PaintYours()
    local listed = Group.Listed()
    local res = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
    local lines = {}
    if listed and res and res.activityIDs and res.activityIDs[1] then
        local act = Listings.ActivityFacts(res.activityIDs[1])
        lines[#lines + 1] = act and act.name or "Your listing"
    else
        lines[#lines + 1] = "You are not listed. Use Create to list your group."
    end
    local facts = {}
    local mineInfo = Group.Info()
    if mineInfo then
        if Group.style and STYLES[Group.style] then facts[#facts + 1] = STYLES[Group.style] end
        if Group.min > 0 then facts[#facts + 1] = ("Minimum Gear Score %.1f"):format(Group.min / 10) end
        if Group.listedAt then facts[#facts + 1] = "Listed " .. Age(GetTime() - Group.listedAt) end
    end
    facts[#facts + 1] = #Comms.incomingApps == 1 and "1 applied" or ("%d applied"):format(#Comms.incomingApps)
    yours.title:SetText(lines[1])
    yours.facts:SetText(listed and table.concat(facts, "   ") or "")
    local party = {}
    for i = 1, GetNumGroupMembers() do
        local unit = IsInRaid() and ("raid" .. i) or (i == 1 and "player" or ("party" .. (i - 1)))
        local name, level = UnitName(unit), UnitLevel(unit)
        local _, class = UnitClass(unit)
        if name and not Secret(name) then party[#party + 1] = ClassHex(class) .. name .. "|r " .. (level or "") end
    end
    yours.party:SetText(table.concat(party, "   "))
    yours.delist:SetShown(listed and Group.CanEdit())
    wipe(applicantOrder)
    if Group.CanEdit() then
        for _, app in ipairs(Comms.incomingApps) do
            applicantOrder[#applicantOrder + 1] = app
        end
    end
    table.sort(applicantOrder, function(a, b) return (a.card.score or -1) > (b.card.score or -1) end)
    for i, app in ipairs(applicantOrder) do
        local row = yours.rows[i] or NewApplicantRow(i)
        row.app = app
        local cardRec = app.card
        local head = { ClassHex(cardRec.class) .. app.name .. "|r", tostring(cardRec.level), RoleText(cardRec.roles) }
        local score = Score(cardRec.score)
        if score then head[#head + 1] = "|cffffd100GS " .. score .. "|r" end
        row.head:SetText(table.concat(head, "  "))
        local sub = {}
        local killList, quests = KillsText(cardRec), QuestsText(cardRec)
        if killList then sub[#sub + 1] = killList end
        if quests then sub[#sub + 1] = quests end
        sub[#sub + 1] = Age(GetTime() - app.at)
        row.sub:SetText(table.concat(sub, "   "))
        row.invite:SetText(app.invited and "Invited" or "Invite")
        row:Show()
    end
    for i = #applicantOrder + 1, #yours.rows do
        yours.rows[i]:Hide()
    end
    yours.content:SetHeight(math.max(1, #applicantOrder * (ROW_H + 2)))
    yours.empty:SetShown(listed and #applicantOrder == 0)
end

local function BuildYours(page)
    yours.rows = {}
    yours.title = Text(page, 14, CUI.Kit.SyncAccent({}))
    yours.title:SetPoint("TOPLEFT", 0, 0)
    yours.title:SetPoint("RIGHT", page, "RIGHT", -100, 0)
    yours.delist = Kit.Button(page, "Delist", 90, BAR_H - 2, function()
        Group.Delist()
        Paint()
    end, { key = "essentials" })
    yours.delist:SetPoint("TOPRIGHT", 0, 0)
    yours.facts = Text(page, Kit.SMALL_SIZE, Pal.muted)
    yours.facts:SetPoint("TOPLEFT", 0, -22)
    yours.party = Text(page, Kit.SMALL_SIZE)
    yours.party:SetPoint("TOPLEFT", 0, -40)
    local scroll, content = Kit.Scroll(page)
    scroll:SetPoint("TOPLEFT", 0, -62)
    scroll:SetPoint("BOTTOMRIGHT", -10, 0)
    yours.content = content
    yours.empty = Text(page, Kit.TEXT_SIZE, Pal.muted)
    yours.empty:SetPoint("TOP", scroll, "TOP", 0, -30)
    yours.empty:SetText("No one has applied yet. CludesUI players who apply show here.")
end

-------------------------------------------------------------------------------
--  Create
-------------------------------------------------------------------------------
local acts = {}
local function Kicker(page, textLine)
    local fs = Text(page, Kit.SMALL_SIZE, CUI.Kit.SyncAccent({}))
    fs:SetText(textLine)
    return fs
end

local function PaintCreate()
    local page = create.page
    local width = (page:GetWidth() and page:GetWidth() > 0) and page:GetWidth() or (WIN_W - PAD * 2)
    local tileW = math.floor((width - (TILE_COLS - 1) * TILE_GAP) / TILE_COLS)
    local n = Search.ActivityList(acts)
    create.empty:SetShown(n == 0)
    local y = 16
    for i = 1, n do
        local tile = create.tiles[i]
        if not tile then
            tile = Kit.Button(page, "", tileW, TILE_H, function(self)
                Group.activity = self.activity
                Paint()
            end, { key = "essentials" })
            tile.range = Text(tile, Kit.SMALL_SIZE, Pal.muted)
            tile.range:SetPoint("BOTTOMLEFT", 6, 4)
            create.tiles[i] = tile
        end
        local ref = acts[i]
        local act = Listings.ActivityFacts(ref)
        tile.activity = ref
        tile:SetSize(tileW, TILE_H)
        tile:ClearAllPoints()
        local column, line = (i - 1) % TILE_COLS, math.floor((i - 1) / TILE_COLS)
        tile:SetPoint("TOPLEFT", column * (tileW + TILE_GAP), -(y + line * (TILE_H + TILE_GAP)))
        tile:SetText(act.short)
        tile.range:SetText(act.max > 0 and ("%d-%d"):format(act.min, act.max) or "")
        local color = GetQuestDifficultyColor and GetQuestDifficultyColor(act.min > 0 and act.min or UnitLevel("player"))
        if color then tile.range:SetTextColor(color.r, color.g, color.b) end
        tile:SetActive(Group.activity == ref)
        tile:Show()
    end
    for i = n + 1, #create.tiles do
        create.tiles[i]:Hide()
    end
    y = y + math.max(1, math.ceil(n / TILE_COLS)) * (TILE_H + TILE_GAP) + 10
    create.kRoles:SetPoint("TOPLEFT", 0, -y)
    y = y + 16
    for i, role in ipairs(create.roles) do
        role:ClearAllPoints()
        role:SetPoint("TOPLEFT", (i - 1) * 190, -y)
        role.value:SetText(Group[role.field])
    end
    y = y + 32
    create.kMin:SetPoint("TOPLEFT", 0, -y)
    create.kStyle:SetPoint("TOPLEFT", 260, -y)
    y = y + 16
    create.minRow:SetPoint("TOPLEFT", 0, -y)
    create.minValue:SetText(Group.min > 0 and ("%.1f"):format(Group.min / 10) or "None")
    for i, button in ipairs(create.styles) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 260 + (i - 1) * 96, -y)
        button:SetActive(Group.style == i)
    end
    y = y + 32
    create.kNote:SetPoint("TOPLEFT", 0, -y)
    y = y + 16
    create.memo:SetPoint("TOPLEFT", 0, -y)
    create.count:SetText(("%d/%d"):format(#Group.memo, Card.NOTE_MAX))
    create.list:SetText(Group.Listed() and "Update Group" or "List Group")
    local why
    if not Group.CanEdit() then
        why = "Only your group's leader can change its listing."
    elseif not Group.Ready() then
        why = "Pick a dungeon and a style to list your group."
    end
    create.why:SetText(why or "")
end

local function BuildCreate(page)
    create.page = page
    create.tiles = {}
    create.kDungeon = Kicker(page, "DUNGEON")
    create.kDungeon:SetPoint("TOPLEFT", 0, 0)
    create.empty = Text(page, Kit.TEXT_SIZE, Pal.muted)
    create.empty:SetPoint("TOPLEFT", 0, -18)
    create.empty:SetText("The group finder has no dungeons for your level yet.")
    create.kRoles = Kicker(page, "ROLES NEEDED")
    create.roles = {}
    for i, role in ipairs({ { "tankCount", "Tank" }, { "healerCount", "Healer" }, { "damageCount", "Damage" } }) do
        local holder = CreateFrame("Frame", nil, page)
        holder:SetSize(180, 22)
        holder.field = role[1]
        local label = Text(holder, Kit.TEXT_SIZE)
        label:SetPoint("LEFT")
        label:SetText(role[2])
        local plus = Kit.Button(holder, "+", 22, 20, function()
            Group[role[1]] = math.min(Card.NEED_MAX, Group[role[1]] + 1)
            Paint()
        end, { key = "essentials" })
        plus:SetPoint("RIGHT")
        holder.value = Text(holder, Kit.TEXT_SIZE)
        holder.value:SetPoint("RIGHT", plus, "LEFT", -8, 0)
        local minus = Kit.Button(holder, "-", 22, 20, function()
            Group[role[1]] = math.max(0, Group[role[1]] - 1)
            Paint()
        end, { key = "essentials" })
        minus:SetPoint("RIGHT", holder.value, "LEFT", -8, 0)
        create.roles[i] = holder
    end
    create.kMin = Kicker(page, "MINIMUM GEAR SCORE")
    create.minRow = CreateFrame("Frame", nil, page)
    create.minRow:SetSize(220, 22)
    local minus = Kit.Button(create.minRow, "-", 22, 20, function()
        Group.min = math.max(0, Group.min - 50)
        Paint()
    end, { key = "essentials" })
    minus:SetPoint("LEFT")
    create.minValue = Text(create.minRow, Kit.TEXT_SIZE)
    create.minValue:SetPoint("LEFT", minus, "RIGHT", 10, 0)
    create.minValue:SetWidth(50)
    create.minValue:SetJustifyH("CENTER")
    local plus = Kit.Button(create.minRow, "+", 22, 20, function()
        Group.min = math.min(1000, Group.min + 50)
        Paint()
    end, { key = "essentials" })
    plus:SetPoint("LEFT", create.minValue, "RIGHT", 10, 0)
    create.kStyle = Kicker(page, "STYLE")
    create.styles = {}
    for i, name in ipairs(STYLES) do
        create.styles[i] = Kit.Button(page, name, 90, 20, function()
            Group.style = i
            Paint()
        end, { key = "essentials" })
    end
    create.kNote = Kicker(page, "NOTE")
    create.memo = Kit.Input(page, 420, 22, "What you are looking for (only CludesUI players see it)", "essentials")
    create.memo:SetMaxLetters(Card.NOTE_MAX)
    create.memo:HookScript("OnTextChanged", function(self)
        Group.memo = Card.TidyNote(self:GetText())
        if create.count then create.count:SetText(("%d/%d"):format(#Group.memo, Card.NOTE_MAX)) end
    end)
    create.count = Text(page, Kit.SMALL_SIZE, Pal.muted)
    create.count:SetPoint("LEFT", create.memo, "RIGHT", 8, 0)
    create.list = Kit.Button(page, "List Group", 120, BAR_H, function()
        if Group.List() then
            tab = "yours"
        end
        Paint()
    end, { key = "essentials" })
    create.list:SetPoint("BOTTOMRIGHT", 0, 0)
    create.reset = Kit.Button(page, "Reset", 80, BAR_H, function()
        Group.activity, Group.style, Group.min, Group.memo = nil, nil, 0, ""
        Group.tankCount, Group.healerCount, Group.damageCount = 1, 1, 3
        create.memo:SetText("")
        Paint()
    end, { key = "essentials" })
    create.reset:SetPoint("RIGHT", create.list, "LEFT", -8, 0)
    create.why = Text(page, Kit.SMALL_SIZE, Pal.amber)
    create.why:SetPoint("BOTTOMLEFT", 0, 4)
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local TABS = { { "browse", "Browse" }, { "yours", "Your Group" }, { "create", "Create" } }

function Paint()
    if not (window and window:IsShown()) then return end
    for nameKey, page in pairs(pages) do
        page:SetShown(nameKey == tab)
    end
    for _, button in ipairs(tabs) do
        button:SetActive(button.key == tab)
    end
    if tab == "browse" then
        PaintBrowse()
    elseif tab == "yours" then
        PaintYours()
    else
        PaintCreate()
    end
end

local function Build()
    if window then return window end
    window = Kit.Window("CludesUILookingForGroup", WIN_W, WIN_H, CUI.L("Looking For Group"), { key = "essentials" })
    local x = PAD
    for i, def in ipairs(TABS) do
        local button = Kit.Button(window, def[2], 100, TAB_H, function()
            tab = def[1]
            Paint()
        end, { key = "essentials" })
        button.key = def[1]
        button:SetPoint("TOPLEFT", x, -(Kit.HEADER_H + 6))
        x = x + 104
        tabs[i] = button
    end
    for _, def in ipairs(TABS) do
        local page = CreateFrame("Frame", nil, window)
        page:SetPoint("TOPLEFT", PAD, -(Kit.HEADER_H + TAB_H + 14))
        page:SetPoint("BOTTOMRIGHT", -PAD, PAD)
        pages[def[1]] = page
    end
    BuildBrowse(pages.browse)
    BuildYours(pages.yours)
    BuildCreate(pages.create)
    window:SetScript("OnShow", function()
        if Search.state == "idle" and not Listings.searched then Search.Run() end
        Paint()
    end)
    window:Hide()
    return window
end

local function Toggle()
    if InCombatLockdown() and not (window and window:IsShown()) then
        CUI.AfterCombat(function() Build():Show() end, "Looking For Group")
        return
    end
    TurnOn()
    Build()
    window:SetShown(not window:IsShown())
end

for _, what in ipairs({ "listings", "listing", "search", "card", "noreply", "offline", "applicant", "received",
    "declined", "withdrawn", "expired", "applicantExpired", "applied", "group" }) do
    GF.Subscribe(what, function() Paint() end)
end

CUI._LFG.Toggle = Toggle
CUI._LFG.Show = function()
    TurnOn()
    Build():Show()
end

SLASH_CUILFG1 = "/clfg"
SlashCmdList.CUILFG = Toggle
