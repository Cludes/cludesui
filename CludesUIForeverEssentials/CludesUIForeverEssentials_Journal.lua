if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Journal.lua  (WoW Forever only)
--  Dungeon Journal: every WoW Forever dungeon and raid, its bosses in kill
--  order (rares, chests and trash too), what each drops and how often, a tip
--  for each boss, and the dungeon's quests with what you have done.
--    /cjournal          opens it, on the dungeon you are in, else one for your
--                       level.
--    An item            hover for its tooltip, Shift-click to link it,
--                       Alt+Shift-click to add it to your BiS list. Your BiS
--                       items have a star; ones you own say so.
--    A quest            ticked when handed in, marked while in your log; only
--                       your side's quests are listed.
--    The map          each floor's art with a pin per boss (hover for it)
--                       and the entrance.
--  The data (bosses, loot, chances, tips, quests) is in JournalData.lua;
--  this file is the window around it.
-------------------------------------------------------------------------------
local _, module = ...

local J = { dungeons = {}, byKey = {} }
module.Journal = J

--- Called by JournalData.lua for each dungeon.
J.factions = {}

--- Called by JournalData.lua for each faction (reputation and PvP).
function J.AddFaction(key, f)
    f.key, f.faction = key, true
    J.factions[#J.factions + 1] = f
end

function J.AddDungeon(key, d)
    d.key = key
    J.dungeons[#J.dungeons + 1] = d
    J.byKey[key] = d
end

local QUEST_ID, QUEST_NAME, QUEST_LEVEL, QUEST_SIDE, QUEST_SHARE, QUEST_WHERE = 1, 2, 3, 4, 5, 6
local NOTYET_NAME, NOTYET_ICON = 7, 6

local function Font()
    return CludesUI.GetFontPath("essentials")
end

-- Quest lists and levels, matched to dungeons by instance map or name.
local prepared
local function Prepare()
    if prepared then
        return
    end
    prepared = true
    local byMap, byName = {}, {}
    for _, q in ipairs(J.QuestData or {}) do
        if q.map then
            byMap[q.map] = q
        end
        byName[q.name] = q
    end
    for _, d in ipairs(J.dungeons) do
        d.questInfo = (d.instance and byMap[d.instance]) or byName[d.name]
        d.levels = d.questInfo and d.questInfo.levels
    end
    table.sort(J.dungeons, function(a, b)
        local la, lb = a.levels and a.levels[1] or 99, b.levels and b.levels[1] or 99
        if la ~= lb then
            return la < lb
        end
        return a.name < b.name
    end)
end

local function LevelText(d)
    local lv = d.levels
    if not lv then
        return ""
    end
    local range = lv[1] == lv[2] and tostring(lv[1]) or (lv[1] .. "-" .. lv[2])
    local mine = UnitLevel("player")
    local at = mine < lv[1] and lv[1] or (mine > lv[2] and lv[2] or mine)
    local c = GetQuestDifficultyColor and GetQuestDifficultyColor(at)
    if c then
        return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, range)
    end
    return range
end

--- The dungeon you are in, else the first one for your level.
local function Suggested()
    Prepare()
    local inside, kind = IsInInstance()
    if inside and (kind == "party" or kind == "raid") then
        local name, _, _, _, _, _, _, id = GetInstanceInfo()
        for _, d in ipairs(J.dungeons) do
            if d.instance == id or d.name == name then
                return d
            end
        end
    end
    local level = UnitLevel("player")
    for _, d in ipairs(J.dungeons) do
        if d.levels and level >= d.levels[1] and level <= d.levels[2] then
            return d
        end
    end
    return J.dungeons[1]
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local W, H, LIST_W = 820, 560, 220
local win, list, scroll, content
local listButtons, pool, used = {}, {}, 0
local current
local Show

local function Text(parent, size, colour)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(fs, size, "essentials")
    fs:SetJustifyH("LEFT")
    if colour then
        fs:SetTextColor(unpack(colour))
    end
    return fs
end

local function Build()
    if win then
        return
    end
    win = CreateFrame("Frame", "CludesUIJournal", UIParent)
    win:SetSize(W, H)
    win:SetPoint("CENTER", 0, 30)
    CludesUI.Kit.Panel(win, 0.96)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetFrameStrata("HIGH")
    local title = Text(win, 15)
    CludesUI.Kit.Font(title, 15, "essentials")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Dungeon Journal")
    CludesUI.Kit.AccentText(title)
    local close = CludesUI.Kit.Glyph(win, "x", function()
        win:Hide()
    end, nil, "essentials")
    close:SetPoint("TOPRIGHT", -5, -5)

    -- Dungeon list
    list = (CludesUI.Kit.Scroll(win))
    list:SetPoint("TOPLEFT", 8, -32)
    list:SetSize(LIST_W - 24, H - 42)
    local lc = CreateFrame("Frame", nil, list)
    lc:SetSize(LIST_W - 24, 10)
    list:SetScrollChild(lc)
    list.child = lc

    -- Detail
    scroll = (CludesUI.Kit.Scroll(win))
    scroll:SetPoint("TOPLEFT", LIST_W + 4, -32)
    scroll:SetSize(W - LIST_W - 36, H - 42)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(W - LIST_W - 36, 10)
    scroll:SetScrollChild(content)

    win:Hide()
    tinsert(UISpecialFrames, "CludesUIJournal")
end

local function FillList()
    Prepare()
    local y = 0
    -- Dungeons, then a Reputation heading and the factions (sorted by name).
    local entries = {}
    for _, d in ipairs(J.dungeons) do
        entries[#entries + 1] = d
    end
    if #J.factions > 0 then
        table.sort(J.factions, function(a, b)
            return a.name < b.name
        end)
        entries[#entries + 1] = { heading = "Reputation" }
        for _, f in ipairs(J.factions) do
            entries[#entries + 1] = f
        end
    end
    for i, d in ipairs(entries) do
        local b = listButtons[i]
        if not b then
            b = CreateFrame("Button", nil, list.child)
            b:SetSize(LIST_W - 30, 20)
            b.text = Text(b, 12)
            b.text:SetPoint("LEFT", 4, 0)
            b.text:SetWidth(LIST_W - 70)
            b.text:SetWordWrap(false)
            b.lv = Text(b, 11)
            b.lv:SetPoint("RIGHT", -2, 0)
            b.sel = b:CreateTexture(nil, "BACKGROUND")
            b.sel:SetAllPoints()
            local ar, ag, ab = CludesUI.Kit.Accent()
            b.sel:SetColorTexture(ar, ag, ab, 0.18)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.06)
            b:SetScript("OnClick", function(self)
                Show(self.dungeon)
            end)
            listButtons[i] = b
        end
        b.dungeon = not d.heading and d or nil
        b:EnableMouse(not d.heading)
        if d.heading then
            b.text:SetText(CludesUI.Kit.AccentHex() .. d.heading .. "|r")
            b.lv:SetText("")
        elseif d.faction then
            b.text:SetText(d.name .. (d.tab == "pvp" and " |cff9aa6b2(PvP)|r" or ""))
            b.lv:SetText("")
        else
            b.text:SetText(
                (d.raid and "|cffffb040" or "")
                    .. d.name
                    .. (d.raid and "|r" or "")
                    .. (d.closed and " |cff9aa6b2(closed)|r" or "")
            )
            b.lv:SetText(LevelText(d))
        end
        b:SetPoint("TOPLEFT", 0, -y)
        b.sel:SetShown(d == current)
        b:Show()
        y = y + 20
    end
    list.child:SetHeight(y)
end

-- Pooled row frames for the detail pane.
local function Acquire()
    used = used + 1
    local r = pool[used]
    if not r then
        r = CreateFrame("Button", nil, content)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT", 14, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.text = Text(r, 12)
        r.text:SetWordWrap(true)
        r:RegisterForClicks("AnyUp")
        r:SetScript("OnEnter", function(self)
            if not self.itemID then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        r:SetScript("OnClick", function(self)
            if not self.itemID then
                return
            end
            if IsAltKeyDown() and IsShiftKeyDown() then
                if module.ToggleBis then
                    module.ToggleBis(self.itemID)
                end
                Show(current)
            elseif IsModifiedClick("CHATLINK") then
                local link = select(2, C_Item.GetItemInfo(self.itemID))
                if link then
                    ChatEdit_InsertLink(link)
                end
            end
        end)
        pool[used] = r
    end
    r.itemID = nil
    r:ClearAllPoints()
    r.icon:Hide()
    r.text:ClearAllPoints()
    r:Show()
    return r
end

local y
local function Line(text, size, indent, colour)
    local r = Acquire()
    CludesUI.Kit.Font(r.text, size or 12, "essentials")
    r.text:SetTextColor(unpack(colour or { 1, 1, 1 }))
    r.text:SetPoint("TOPLEFT", r, "TOPLEFT", indent or 0, 0)
    r.text:SetWidth(content:GetWidth() - (indent or 0) - 8)
    r.text:SetText(text)
    local h = math.max(16, r.text:GetStringHeight() + 4)
    r:SetSize(content:GetWidth(), h)
    r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    y = y + h
    return r
end

local function ItemLine(id, chance)
    local r = Acquire()
    r.itemID = id
    local name, link, quality = C_Item.GetItemInfo(id)
    local notYet = J.NotYet and J.NotYet[id]
    if not name and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(id)
    end
    local icon = C_Item.GetItemIconByID(id) or (notYet and notYet[NOTYET_ICON])
    r.icon:SetTexture(icon)
    r.icon:Show()
    local label = link
        or (notYet and ("|cff9aa6b2" .. notYet[NOTYET_NAME] .. " (not in the game yet)|r"))
        or ("item " .. id)
    local extra = {}
    if chance and chance > 0 then
        extra[#extra + 1] = ("|cff9aa6b2%d%%|r"):format(chance)
    elseif chance then
        extra[#extra + 1] = "|cff9aa6b2rare|r"
    end
    if module.BisSlotOf and module.BisSlotOf(id) then
        extra[#extra + 1] = (module.Owned and module.Owned(id)) and "|cffff9933*|r |cff60d080BiS, yours|r"
            or "|cffff9933* BiS|r"
    end
    CludesUI.Kit.Font(r.text, 12, "essentials")
    r.text:SetTextColor(1, 1, 1)
    r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.text:SetWidth(content:GetWidth() - 50)
    r.text:SetText(label .. "  " .. table.concat(extra, "  "))
    r:SetSize(content:GetWidth(), 20)
    r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    y = y + 20
end

-------------------------------------------------------------------------------
--  Dungeon map: the dungeon's art per floor, a pin per boss (numbered in kill
--  order; R, O, Q, C for rares, optional and quest bosses and chests) and the
--  entrance. Hover a pin for its boss. Several floors: < and > step through
--  those that hold a boss or the entrance, in the order you walk them.
-------------------------------------------------------------------------------
local MAP_PIN, MAP_ENTRANCE = 26, 26
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local TAG_SHORT = { rare = "R", optional = "O", quest = "Q", chest = "C" }
local TAG_WORDS = { rare = "Rare", optional = "Optional", quest = "Quest boss", chest = "Chest" }
local mapView

local function BossTag(boss)
    return boss.rare and "rare"
        or boss.optional and "optional"
        or boss.quest and "quest"
        or boss.chest and "chest"
        or nil
end

local function BossKey(boss)
    return boss.npc or (boss.chest and -boss.chest) or nil
end

local function Walked(map, n)
    for i, f in ipairs(map.order or {}) do
        if f == n then
            return i
        end
    end
    return n
end

local function FloorName(map, n)
    return map.names and map.names[n] or ("Floor %d"):format(Walked(map, n))
end

local function Round(frame, tex)
    local mask = frame:CreateMaskTexture()
    mask:SetAllPoints(tex)
    mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    tex:AddMaskTexture(mask)
end

local function PinEnter(pin)
    local boss = pin.boss
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText((pin.number and (pin.number .. ". ") or "") .. boss.name, 1, 1, 1)
    local tag = BossTag(boss)
    if tag then
        GameTooltip:AddLine(TAG_WORDS[tag], 0.6, 0.65, 0.7)
    end
    local tip = boss.npc and J.Tips and J.Tips[boss.npc]
    local ar, ag, ab = CludesUI.Kit.Accent()
    if tip then
        GameTooltip:AddLine(tip, ar, ag, ab, true)
    end
    GameTooltip:Show()
end

local function NewMapPin(canvas)
    local pin = CreateFrame("Frame", nil, canvas)
    pin:SetSize(MAP_PIN, MAP_PIN)
    pin:SetMouseMotionEnabled(true)
    pin.ring = pin:CreateTexture(nil, "BORDER")
    pin.ring:SetPoint("CENTER")
    pin.ring:SetSize(MAP_PIN + 4, MAP_PIN + 4)
    Round(pin, pin.ring)
    pin.plate = pin:CreateTexture(nil, "ARTWORK")
    pin.plate:SetAllPoints()
    pin.plate:SetColorTexture(0.06, 0.07, 0.09, 1)
    Round(pin, pin.plate)
    pin.text = pin:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(pin.text, 13, "essentials")
    pin.text:SetPoint("CENTER")
    pin:SetScript("OnEnter", PinEnter)
    pin:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return pin
end

local function MapBuild()
    if mapView then
        return mapView
    end
    local v = { pins = {}, floors = {} }
    local width = W - LIST_W - 44
    v.w, v.h = width, math.floor(width * 2 / 3)
    v.bar = CreateFrame("Frame", nil, content)
    v.bar:SetSize(width, 22)
    local function Step(by)
        local at = 1
        for i, f in ipairs(v.floors) do
            if f == v.floor then
                at = i
            end
        end
        v.floor = v.floors[(at - 1 + by) % #v.floors + 1]
        v:Draw()
    end
    v.down = CludesUI.Kit.Button(v.bar, "", 90, 22, nil, { key = "essentials" })
    v.down:SetSize(24, 20)
    v.down:SetPoint("LEFT", 0, 0)
    v.down:SetText("<")
    v.down:SetScript("OnClick", function()
        Step(-1)
    end)
    v.name = Text(v.bar, 12)
    v.name:SetPoint("LEFT", v.down, "RIGHT", 8, 0)
    v.up = CludesUI.Kit.Button(v.bar, "", 90, 22, nil, { key = "essentials" })
    v.up:SetSize(24, 20)
    v.up:SetPoint("LEFT", v.name, "RIGHT", 8, 0)
    v.up:SetText(">")
    v.up:SetScript("OnClick", function()
        Step(1)
    end)
    v.canvas = CreateFrame("Frame", nil, content)
    v.canvas:SetSize(width, v.h)
    v.canvas:SetClipsChildren(true)
    CludesUI.Kit.Border(v.canvas, 0, 0, 0, 1)
    v.picture = v.canvas:CreateTexture(nil, "BACKGROUND")
    v.picture:SetAllPoints()
    v.door = CreateFrame("Frame", nil, v.canvas)
    v.door:SetSize(MAP_ENTRANCE, MAP_ENTRANCE)
    v.door.icon = v.door:CreateTexture(nil, "ARTWORK")
    v.door.icon:SetAllPoints()
    v.door.icon:SetAtlas("dungeon")
    v.door.text = v.door:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(v.door.text, 12, "essentials")
    v.door.text:SetPoint("LEFT", v.door, "RIGHT", 2, 0)
    v.door.text:SetText("Entrance")

    function v:At(frame, x, y)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", self.canvas, "TOPLEFT", x * self.w, -y * self.h)
    end

    function v:Draw()
        local map = self.map
        local image = map.images and map.images[self.floor]
        if not image and map.image then
            image = self.floor > 1 and map.image .. self.floor or map.image
        end
        self.picture:SetTexture(image, nil, nil, "TRILINEAR")
        self.picture:SetTexCoord(0, 1, 0, map.imageBottom or (683 / 1024))
        for _, pin in ipairs(self.pins) do
            pin:Hide()
        end
        local used = 0
        for _, wing in ipairs(self.dungeon.wings or {}) do
            local number = 0
            for _, boss in ipairs(wing.bosses or {}) do
                local tag = BossTag(boss)
                local numbered = not (tag or boss.trash)
                if numbered then
                    number = number + 1
                end
                local key = BossKey(boss)
                local spot = key and map.pins[key]
                if spot and spot[1] == self.floor then
                    used = used + 1
                    local pin = self.pins[used] or NewMapPin(self.canvas)
                    self.pins[used] = pin
                    pin.boss, pin.number = boss, numbered and number or nil
                    pin.text:SetText(pin.number or TAG_SHORT[tag] or "")
                    if numbered then
                        pin.ring:SetColorTexture(CludesUI.Kit.Accent())
                    else
                        pin.ring:SetColorTexture(0.6, 0.65, 0.7, 1)
                    end
                    self:At(pin, spot[2], spot[3])
                    pin:Show()
                end
            end
        end
        local door = map.entrance
        local here = door and door[1] == self.floor
        self.door:SetShown(here or false)
        if here then
            self:At(self.door, door[2], door[3])
        end
        self.bar:SetShown(#self.floors > 1)
        self.name:SetText(FloorName(map, self.floor))
    end

    function v:Open(dungeon)
        local map = J.Maps[dungeon.key]
        self.dungeon, self.map = dungeon, map
        wipe(self.floors)
        local seen = {}
        local function Offer(spot)
            if type(spot) == "table" and spot[1] <= map.floors and not seen[spot[1]] then
                seen[spot[1]] = true
                self.floors[#self.floors + 1] = spot[1]
            end
        end
        Offer(map.entrance)
        for _, wing in ipairs(dungeon.wings or {}) do
            for _, boss in ipairs(wing.bosses or {}) do
                local key = BossKey(boss)
                Offer(key and map.pins[key])
            end
        end
        table.sort(self.floors, function(a, b)
            return Walked(map, a) < Walked(map, b)
        end)
        if #self.floors == 0 then
            for n = 1, map.order and #map.order or map.floors do
                self.floors[n] = map.order and map.order[n] or n
            end
        end
        self.floor = self.floors[1]
    end

    mapView = v
    return v
end

local function MapHide()
    if mapView then
        mapView.bar:Hide()
        mapView.canvas:Hide()
    end
end

-- The map at y in the detail pane; returns the new y.
local function MapShow(d, at)
    if not (J.Maps and J.Maps[d.key]) then
        MapHide()
        return at
    end
    local v = MapBuild()
    if v.dungeon ~= d then
        v:Open(d)
    end
    v:Draw()
    if v.bar:IsShown() then
        v.bar:ClearAllPoints()
        v.bar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -at)
        at = at + 26
    end
    v.canvas:ClearAllPoints()
    v.canvas:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -at)
    v.canvas:Show()
    return at + v.h + 8
end

local SIDE = { Alliance = "A", Horde = "H" }

Show = function(d)
    Build()
    Prepare()
    current = d or current or Suggested()
    win:Show()
    FillList()
    for i = 1, used do
        pool[i]:Hide()
    end
    used, y = 0, 0
    MapHide()
    local dd = current
    if not dd then
        return
    end

    if dd.faction then
        -- Your standing now, when the game will say.
        local standing
        if C_Reputation and C_Reputation.GetFactionDataByID then
            local ok, data = pcall(C_Reputation.GetFactionDataByID, dd.id)
            if ok and type(data) == "table" then
                standing = data.reaction
            end
        elseif GetFactionInfoByID then
            standing = select(3, GetFactionInfoByID(dd.id))
        end
        Line(dd.name .. (dd.tab == "pvp" and "  |cffff6060PvP|r" or ""), 16, 0, CludesUI.Kit.SyncAccent({}))
        local facts = {}
        if dd.zone then
            facts[#facts + 1] = dd.zone
        end
        if standing then
            facts[#facts + 1] = "You: " .. (_G["FACTION_STANDING_LABEL" .. standing] or standing)
        end
        Line(table.concat(facts, "   "), 12, 0, { 0.6, 0.65, 0.7 })
        local qm = dd.quartermaster
        if qm then
            local mapInfo = qm.map and C_Map.GetMapInfo(qm.map)
            Line(
                ("Quartermaster: %s%s"):format(
                    qm.name,
                    mapInfo and (" (" .. mapInfo.name .. " " .. qm.x .. ", " .. qm.y .. ")") or ""
                ),
                12,
                0
            )
        end
        if dd.dungeons and #dd.dungeons > 0 then
            Line("Reputation from: " .. table.concat(dd.dungeons, ", "), 12, 0)
        end
        local mySide = SIDE[UnitFactionGroup("player") or ""]
        if dd.turnins and #dd.turnins > 0 then
            y = y + 4
            Line("Turn-ins", 14, 0, { 1, 0.82, 0 })
            for _, t in ipairs(dd.turnins) do
                local takes = t.takes and t.takes[1]
                local itemName = takes and (select(1, C_Item.GetItemInfo(takes)) or ("item " .. takes))
                Line(
                    ("%s  |cff9aa6b2+%d rep%s%s|r"):format(
                        t.name,
                        t.rep or 0,
                        t.level and (", level " .. t.level) or "",
                        takes and (", hand in " .. (t.takes[2] or 1) .. "x " .. itemName) or ""
                    ),
                    12,
                    0
                )
                for _, q in ipairs(t.quests or {}) do
                    if q[2] == "B" or q[2] == mySide then
                        Line(q[3], 11, 14, { 0.55, 0.6, 0.65 })
                    end
                end
                for _, from in ipairs(t.from or {}) do
                    local mobs = {}
                    for i = 3, #from do
                        mobs[#mobs + 1] = from[i]
                    end
                    Line(
                        ("%s: %s%s"):format(
                            from[1],
                            table.concat(mobs, ", "),
                            (from[2] or 0) > #mobs and " ..." or ""
                        ),
                        11,
                        14,
                        { 0.55, 0.6, 0.65 }
                    )
                end
            end
        end
        for _, tier in ipairs(dd.tiers or {}) do
            y = y + 4
            local label = _G["FACTION_STANDING_LABEL" .. tier.standing] or ("Standing " .. tier.standing)
            local reached = standing and standing >= tier.standing
            Line(label .. (reached and "  |cff60d080reached|r" or ""), 14, 0, { 1, 0.82, 0 })
            for _, id in ipairs(tier.items or {}) do
                ItemLine(id)
            end
        end
        content:SetHeight(y + 10)
        return
    end

    Line(dd.name .. (dd.raid and "  |cffffb040Raid|r" or ""), 16, 0, CludesUI.Kit.SyncAccent({}))
    local facts = {}
    if dd.levels then
        facts[#facts + 1] = "Levels " .. LevelText(dd)
    end
    if dd.zone then
        facts[#facts + 1] = dd.zone
    end
    if dd.territory then
        facts[#facts + 1] = dd.territory
    end
    if dd.entrance then
        facts[#facts + 1] = ("entrance %.1f, %.1f"):format(dd.entrance.x, dd.entrance.y)
    end
    Line(table.concat(facts, "   "), 12, 0, { 0.6, 0.65, 0.7 })
    if dd.note then
        Line(dd.note, 12, 0, { 1, 0.8, 0.3 })
    end
    y = y + 6
    y = MapShow(dd, y)

    local n = 0
    for _, wing in ipairs(dd.wings or {}) do
        if wing.name then
            Line(wing.name, 14, 0, { 1, 0.82, 0 })
        end
        for _, boss in ipairs(wing.bosses or {}) do
            local tag = boss.rare and " |cffb070ffrare|r"
                or boss.optional and " |cff9aa6b2optional|r"
                or boss.quest and " |cffffd060quest|r"
                or boss.chest and " |cff9aa6b2chest|r"
                or ""
            local numbered = not (boss.rare or boss.optional or boss.quest or boss.chest or boss.trash)
            if numbered then
                n = n + 1
            end
            Line((numbered and (n .. ". ") or "") .. boss.name .. tag, 14, 0, { 1, 1, 1 })
            local tip = boss.npc and J.Tips and J.Tips[boss.npc]
            if tip then
                Line(tip, 12, 14, { 0.6, 0.65, 0.7 })
            end
            for i, id in ipairs(boss.loot or {}) do
                ItemLine(id, boss.chance and boss.chance[i])
            end
            y = y + 6
        end
    end

    local quests = dd.questInfo and dd.questInfo.quests
    if quests and #quests > 0 then
        y = y + 4
        Line("Quests", 14, 0, { 1, 0.82, 0 })
        local mySide = SIDE[UnitFactionGroup("player") or ""]
        for _, q in ipairs(quests) do
            local side = q[QUEST_SIDE]
            if side == "B" or side == mySide then
                local id = q[QUEST_ID]
                local state = ""
                if C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) then
                    state = "|cff60d080done|r  "
                elseif C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then
                    state = "|cffffd060in your log|r  "
                end
                local pre = q[QUEST_SHARE] == "pre" and " |cff9aa6b2(needs earlier quests)|r" or ""
                Line(("%s|cff9aa6b2%d|r  %s%s"):format(state, q[QUEST_LEVEL] or 0, q[QUEST_NAME], pre), 12, 0)
                if q[QUEST_WHERE] then
                    Line(q[QUEST_WHERE], 11, 14, { 0.55, 0.6, 0.65 })
                end
            end
        end
    end
    content:SetHeight(y + 10)
end

function module.ShowJournal(d)
    if win and win:IsShown() and not d then
        win:Hide()
        return
    end
    Show(d)
end

-- Item names arrive after the window asks for them: repaint once they settle.
local ev = CreateFrame("Frame")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local queued
ev:SetScript("OnEvent", function()
    if not (win and win:IsShown()) or queued then
        return
    end
    queued = true
    C_Timer.After(0.3, function()
        queued = nil
        if win:IsShown() then
            Show(current)
        end
    end)
end)

CludesUI._Journal = {
    Show = function()
        module.ShowJournal()
    end,
}

SLASH_CUIJOURNAL1 = "/cjournal"
SlashCmdList.CUIJOURNAL = function()
    module.ShowJournal()
end
