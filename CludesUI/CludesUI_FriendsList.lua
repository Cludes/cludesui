if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_FriendsList.lua
--  The custom friends list: rows of our own drawn over Blizzard's Social UI
--  friends list, for a tile height and friend groups Blizzard's list cannot
--  have (its row height is fixed when the window loads, and any change to its
--  data taints Battle.net whispers: see CludesUI_FriendsKit.lua).
--
--  HOW IT STAYS CLEAN. Blizzard's list keeps running underneath at alpha 0;
--  ours is drawn over it and takes the mouse. Every row carries a frame made
--  from Blizzard's InlineHyperlinkFrameTemplate that holds one invisible
--  Battle.net player link across the row. The template's click handler is
--  Blizzard's own (it calls SetItemRef), so a right click opens the friend
--  menu through the code a click on a friend's name in chat runs, and that
--  menu's Whisper opens the chat box with nothing of ours in between. A left
--  click only selects the friend, as on Blizzard's list: a click layer of
--  ours lies over every row's link and takes every button but the right one,
--  which it passes down to the link (see Clicks), so Blizzard's handler never
--  sees that click, and the release sets nothing but our own selection.
--  Field-checked on WoW Forever 1.60.1 (70790): a whisper through the link,
--  the menu's Whisper and entries added to that menu all stayed
--  Blizzard-secure, while a whisper opened from addon code did not.
--  Rules that keep it so:
--    - never give the link frame a click script (OnClick, OnMouseDown / Up,
--      OnHyperlinkClick): a post-hook on the link click is safe, a
--      replacement is not; a right click is never touched;
--    - never open a whisper or Blizzard's friend menu from our code
--      (ChatFrameUtil.SendBNetTell, UnitPopup_OpenMenu);
--    - our entries reach that menu through Menu.ModifyMenu only, and call
--      plain friend functions (note, favorite, tags, remove) or our own
--      group store;
--    - nothing is written onto a Blizzard frame, and Blizzard's list, its
--      provider and its cards are left alone but for the alpha of the list
--      and its scroll bar.
--
--  The link must be ONE line of text taller than the row: its line box is the
--  live zone (wrapped text is live on its first two lines only, and an inline
--  texture is not clickable).
--
--  Availability: its host starts it, and its host's settings carry its
--  switch, customTiles (false stands it down; settings without the key keep
--  it on). On WoW Forever that is the Friends List card's Custom Friends
--  List Tiles, which follows the card's look until picked: on while the card
--  is skinned, off under Blizz Default, where the host starts for the list
--  alone. The Social UI friends list must exist and the client's menu code
--  must isolate added entries (Menu.IsMenuProxy came with that change). The
--  list stands down under WoW Forever's Gamepad interface style, where a
--  controller drives Blizzard's list.
--
--  The scroll area is the rect of Blizzard's own list, a tile is inset from
--  its sides as Blizzard's cards are, and the scroll bar is a frame of ours
--  made from the template of Blizzard's bar and laid over it: the list looks
--  like the lists of the window's other tabs. It scrolls as they do too: the
--  wheel is that bar's own step, with no easing. An online friend's row
--  wears Blizzard's own card art at the alpha its host gives it (onlineCards;
--  WoW Forever's card: whole under Blizz Default, a quarter under its tiles).
--
--  Cost: at the start one frame is made, a child of the friends view that
--  carries its show and hide edge; nothing else is built, registered or run
--  until that view shows, and then only while it shows. Friend events are
--  coalesced to one rebuild per frame, a change to one friend that moves
--  nothing repaints that row alone, and rows and headers are pooled:
--  scrolling paints only the rows entering view.
--
--  Groups are account data in CludesUIDB.global (outside the profiles and
--  outside exports): the group list, order, colours and collapsed state, and
--  each friend's group by BattleTag. A "||<tag>:Group||" tag an old Friends
--  build left in a friend note is read once and never written.
--
--  Favorites is Battle.net's own favorite list shown as a section among the
--  groups, and the friend menu offers it as one: a friend's custom group wins
--  over it, and a pick that moves a friend into Favorites, or out of it to
--  the ungrouped friends, sets Battle.net's favorite switch.
-------------------------------------------------------------------------------
local FL = {}
CludesUI.FriendsList = FL

local Kit = CludesUI.FriendsKit
local T = Kit._tile
local IsSecret = CludesUI.IsSecret

local TEMPLATE = "InlineHyperlinkFrameTemplate"
-- name : account id : line id : chat type : chat target (the chat frame's own form)
local LINK_FORMAT = "|HBNplayer:%s:%d:0:BN_WHISPER:%s|h%s|h"
-- More letters than any row needs: the text is cut at the block's width
local LINK_FILLER = string.rep("M", 64)
-- The link text against its row: font size over the row's height, and how far
-- above the row's top it starts
local LINK_TALLER, LINK_ABOVE = 8, 5
local MENU_TAGS = { "MENU_UNIT_BN_FRIEND", "MENU_UNIT_BN_FRIEND_OFFLINE" }
local ICONS = "Interface\\AddOns\\CludesUI\\media\\icons\\"
-- Blizzard's own art from its friend cards: the invite button and the status
-- icons. The button is 34 across on Blizzard's 70-tall card; ours is halfway
-- between that share of the tile and a flat 28, plus BTN_EXTRA (StyleRow):
-- 26 on the default tile.
local BTN_NORMAL, BTN_PUSHED = "common-button-tertiary-square-normal", "common-button-tertiary-square-pressed"
local BTN_NATIVE, BTN_SHARE, BTN_MIN, BTN_FLAT, BTN_EXTRA = 34, 0.52, 16, 28, 2
local STATUS_ATLAS = {
    online = "friends-status-online",
    away = "friends-status-away",
    busy = "friends-status-busy",
    offline = "friends-status-offline",
}
-- The status icon against the end of the text before it: its art keeps empty
-- edges, so it sits a little into the text's box and above its middle
local STATUS_DX, STATUS_DY = -1, 2

local TILE_MIN, TILE_MAX, TILE_DEFAULT = 24, 70, 40
local HEADER_H = 24
local ROW_GAP, GROUP_GAP = 2, 4
local PAD_TOP, PAD_BOTTOM = 6, 6
-- A tile's inset from the sides of the scroll area: those of Blizzard's own
-- list, so a tile is as wide as one of its cards
local PAD_LEFT, PAD_RIGHT = 10, 7
local TEXT_GAP = 4 -- between the icon square and the text
local CHAR_GAP = 5 -- between the Battle.net name and the character after it
local CHAR_LIFT = 1 -- the character text's bottom above the name's
local EDGE_PAD = 4 -- between a row's right edge and what sits there
local NOTE_MAX = 127 -- Blizzard's own limit on a friend note
local GROUP_NAME_MAX = 32

local FAV, UNGROUPED = "_favorites", "_ungrouped"
local KIND_HEADER, KIND_FRIEND = 0, 1

-- The kit's host (settings, look, font): set once by FL.Start
local host
local driver, rootFrame, scrollFrame, contentFrame, bar, flusher, event, filterX
local isActive = false -- live: shown, listening
local covering = false -- Blizzard's list is hidden under ours
local viewH, rowW = 0, 0
local tileHeight, tierIndex = TILE_DEFAULT, 2
local ring = 8 -- pool slots: more than the items one view spans
local styleGen, modelGen, visGen = 0, 0, 0
local fullDirty, dirtyInvites = false, false
local searchActive = false
local searchCollapsed = {} -- sections folded during a search, for that search alone
local hoveredRow
local selectedId -- the selected friend's account id (a left click picks it)
local rowPool, headerPool = {}, {} -- by ring slot
local rowList, headerList = {}, {} -- every frame made, in order
local itemList, itemCount = {}, 0
local records, recordCount = {}, 0
local byId, byIndex = {}, {}
local rendered, renderedCount = {}, 0
local menuHandles = {}

local function Settings()
    return host and host.Settings()
end

local function View()
    local frame = _G.SocialUIFrame
    return frame and frame.FriendsList
end

local function ClampTile(val)
    val = tonumber(val) or TILE_DEFAULT
    return math.max(TILE_MIN, math.min(TILE_MAX, math.floor(val + 0.5)))
end

-------------------------------------------------------------------------------
--  Group store
-------------------------------------------------------------------------------
local function Store()
    if not CludesUIDB then
        CludesUIDB = {}
    end
    local group = CludesUIDB.global
    if type(group) ~= "table" then
        group = {}
        CludesUIDB.global = group
    end
    if type(group.friendGroups) ~= "table" then
        group.friendGroups = {}
    end
    if type(group.friendGroupsByTag) ~= "table" then
        group.friendGroupsByTag = {}
    end
    if type(group.friendGroupColors) ~= "table" then
        group.friendGroupColors = {}
    end
    if type(group.friendGroupOrder) ~= "table" then
        group.friendGroupOrder = {}
    end
    return group
end

local function FindGroup(group, nameText)
    local entries = group.friendGroups
    for idx = 1, #entries do
        if entries[idx].name == nameText then
            return entries[idx], idx
        end
    end
end

-- The section order with every section in it once: the saved order first,
-- then Favorites on top, new groups above the ungrouped friends, and those
-- last. The saved list is rewritten only when it was not already that.
local orderBuf, seenOrder = {}, {}
local function ValidOrder(group)
    local saved = group.friendGroupOrder
    wipe(orderBuf)
    wipe(seenOrder)
    local num = 0
    for idx = 1, #saved do
        local sortKey = saved[idx]
        if not seenOrder[sortKey] and (sortKey == FAV or sortKey == UNGROUPED or FindGroup(group, sortKey)) then
            num = num + 1
            orderBuf[num] = sortKey
            seenOrder[sortKey] = true
        end
    end
    if not seenOrder[FAV] then
        table.insert(orderBuf, 1, FAV)
        seenOrder[FAV] = true
        num = num + 1
    end
    local entries = group.friendGroups
    for idx = 1, #entries do
        local nameText = entries[idx].name
        if not seenOrder[nameText] then
            local at = num + 1
            for k = 1, num do
                if orderBuf[k] == UNGROUPED then
                    at = k
                    break
                end
            end
            table.insert(orderBuf, at, nameText)
            seenOrder[nameText] = true
            num = num + 1
        end
    end
    if not seenOrder[UNGROUPED] then
        num = num + 1
        orderBuf[num] = UNGROUPED
    end
    local same = #saved == num
    if same then
        for idx = 1, num do
            if saved[idx] ~= orderBuf[idx] then
                same = false
                break
            end
        end
    end
    if not same then
        local fresh = {}
        for idx = 1, num do
            fresh[idx] = orderBuf[idx]
        end
        group.friendGroupOrder = fresh
    end
    return orderBuf, num
end

local function IsCollapsed(group, sortKey)
    if sortKey == FAV then
        return group.friendFavCollapsed == true
    end
    if sortKey == UNGROUPED then
        return group.friendUngroupedCollapsed == true
    end
    local grp = FindGroup(group, sortKey)
    return grp ~= nil and grp.collapsed == true
end

local function CleanGroupName(textValue)
    if type(textValue) ~= "string" then
        return nil
    end
    local nameText = strtrim(textValue)
    if nameText == "" or nameText == FAV or nameText == UNGROUPED then
        return nil
    end
    if #nameText > GROUP_NAME_MAX then
        nameText = nameText:sub(1, GROUP_NAME_MAX)
    end
    return nameText
end

-------------------------------------------------------------------------------
--  Friend facts
-------------------------------------------------------------------------------
-- A friend's key in the group store: the BattleTag, or for a friend added by
-- character (no BattleTag) the character Blizzard whispers. Kept per account
-- id until the friend list changes size.
local keyById, sortById = {}, {}
local function FriendKey(details)
    local ident = details.bnetAccountID
    local sortKey = keyById[ident]
    if sortKey ~= nil then
        return sortKey or nil
    end
    local tagText = details.battleTag
    if type(tagText) == "string" and not IsSecret(tagText) and tagText ~= "" then
        sortKey = tagText
    elseif C_BattleNet.GetDefaultTitleWhisperTarget then
        local target = C_BattleNet.GetDefaultTitleWhisperTarget(ident)
        if type(target) == "string" and not IsSecret(target) and target ~= "" then
            sortKey = "title:" .. target
        end
    end
    keyById[ident] = sortKey or false
    return sortKey
end

local function SortName(details)
    local ident = details.bnetAccountID
    local nameText = sortById[ident]
    if nameText then
        return nameText
    end
    local tagText = details.battleTag
    if type(tagText) == "string" and not IsSecret(tagText) and tagText ~= "" then
        nameText = tagText:lower()
        nameText = nameText:match("^(.-)#") or nameText
    else
        nameText = ""
    end
    sortById[ident] = nameText
    return nameText
end

-- 1 online in this game, 2 another WoW, 3 another game, 4 the app, 5 offline
local function Priority(gameInfo)
    if gameInfo and gameInfo.isOnline then
        local cp = gameInfo.clientProgram
        if cp == BNET_CLIENT_WOW then
            return (gameInfo.wowProjectID == WOW_PROJECT_ID or gameInfo.wowProjectID == nil) and 1 or 2
        end
        if not cp or cp == "" or cp == "BSAp" or cp == "App" then
            return 4
        end
        return 3
    end
    return 5
end

-- Whether a friend counts as a favorite: Battle.net's flag, or what a menu
-- pick asked Battle.net for until its answer arrives, so the friend sits
-- where it was put at once. Kept per account id while the list shows; a flag
-- the game keeps secret counts as not set.
local favAsked = {}
local function IsFavorite(details)
    local fav = details.isFavorite
    fav = not IsSecret(fav) and fav == true
    local ident = details.bnetAccountID
    local asked = favAsked[ident]
    if asked == nil then
        return fav
    end
    if asked == fav then
        favAsked[ident] = nil
    end
    return asked
end

-- The section a friend sits in: its custom group first, then Favorites for a
-- favorite, else the ungrouped friends
local function BucketOf(group, details, sortKey)
    local nameText = sortKey and group.friendGroupsByTag[sortKey]
    if nameText and FindGroup(group, nameText) then
        return nameText
    end
    if IsFavorite(details) then
        return FAV
    end
    return UNGROUPED
end

-- The group an old Friends build wrote into a friend note, read once so those
-- groups come back. Nothing is written to the note.
local function MigrateNoteTags(group)
    if group.friendGroupsTagMigrated then
        return
    end
    local sum = BNGetNumFriends() or 0
    if sum == 0 then
        return
    end
    group.friendGroupsTagMigrated = true
    for idx = 1, sum do
        local details = C_BattleNet.GetFriendAccountInfo(idx)
        local note = details and details.note
        if type(note) == "string" and not IsSecret(note) then
            local s = note:find("||E" .. "UI:", 1, true)
            local e = s and note:find("||", s + 6, true)
            local nameText = e and CleanGroupName(note:sub(s + 6, e - 1))
            local sortKey = nameText and FriendKey(details)
            if sortKey and not group.friendGroupsByTag[sortKey] then
                if not FindGroup(group, nameText) then
                    group.friendGroups[#group.friendGroups + 1] = { name = nameText, collapsed = false }
                end
                group.friendGroupsByTag[sortKey] = nameText
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Search: Blizzard's own search box and filter menu keep working. The game
--  refuses the friend search call to an addon (C_BattleNet.SearchFriends: a
--  blocked action), so the list never makes it: Blizzard's list, alive under
--  ours, runs each search itself and holds the answer in its tree of
--  sections, and the friends that passed are read from there. Plain getters
--  only: nothing of Blizzard's is written or asked to work.
-------------------------------------------------------------------------------
local allowedSet = {}

-- One of Blizzard's filters is ticked
local function FiltersOn(viewMode)
    local selected = viewMode.selectedSearchFilterOptions
    if type(selected) == "table" then
        for _, on in pairs(selected) do
            if on then
                return true
            end
        end
    end
    return false
end

-- Blizzard's search box holds text
local function SearchTextOn(viewMode)
    local bar = viewMode.FilterBar and viewMode.FilterBar.SearchBar
    local textValue = bar and bar.GetText and bar:GetText()
    return IsSecret(textValue) or (type(textValue) == "string" and textValue ~= "")
end

-- The friends in Blizzard's list: its sections, then the friends under each
-- (a section Blizzard shows collapsed still holds its friends)
local function ReadBlizzardList(viewMode, into)
    local sections = viewMode.ScrollBox:GetDataProvider():GetRootNode():GetNodes()
    for idx = 1, #sections do
        local nodes = sections[idx]:GetNodes()
        for k = 1, #nodes do
            local payload = nodes[k]:GetData()
            local index = payload and payload.friendIndex
            if index then
                into[index] = true
            end
        end
    end
end

-- The friend indexes a search or filter lets through; nil with none active,
-- and when Blizzard's list cannot be read (every friend shows then)
local function SearchSet(viewMode, filtered)
    if not (filtered or SearchTextOn(viewMode)) then
        return nil
    end
    wipe(allowedSet)
    if not pcall(ReadBlizzardList, viewMode, allowedSet) then
        return nil
    end
    return allowedSet
end

-------------------------------------------------------------------------------
--  Model: friends read into records, sorted into sections, laid out as items
-------------------------------------------------------------------------------
local buckets, onlineIn = {}, {}

local function CompareRecords(a, b)
    if a.priority ~= b.priority then
        return a.priority < b.priority
    end
    if a.sortName ~= b.sortName then
        return a.sortName < b.sortName
    end
    return a.index < b.index
end

local function NewItem(kind, y, hgt)
    itemCount = itemCount + 1
    local item = itemList[itemCount]
    if not item then
        item = {}
        itemList[itemCount] = item
    end
    item.kind, item.y, item.h, item.gen, item.rec = kind, y, hgt, modelGen, nil
    return item
end

local function Rebuild()
    local group = Store()
    MigrateNoteTags(group)
    modelGen = modelGen + 1

    local viewMode = View()
    local filtered = FiltersOn(viewMode)
    if filterX then
        filterX:SetShown(filtered)
    end
    local allowed = SearchSet(viewMode, filtered)
    -- The sections folded during a search open again as it ends
    if searchActive and not allowed then
        wipe(searchCollapsed)
    end
    searchActive = allowed ~= nil

    for _, entries in pairs(buckets) do
        wipe(entries)
    end
    wipe(onlineIn)
    wipe(byId)
    wipe(byIndex)

    local sum = BNGetNumFriends() or 0
    local num = 0
    for idx = 1, sum do
        if not allowed or allowed[idx] then
            local details = C_BattleNet.GetFriendAccountInfo(idx)
            if details then
                num = num + 1
                local record = records[num]
                if not record then
                    record = {}
                    records[num] = record
                end
                local gameInfo = details.gameAccountInfo
                local ident = details.bnetAccountID
                record.index, record.id, record.info = idx, ident, details
                record.online = gameInfo ~= nil and gameInfo.isOnline == true
                record.priority = Priority(gameInfo)
                record.sortName = SortName(details)
                record.key = FriendKey(details)
                record.bucket = BucketOf(group, details, record.key)
                byId[ident] = record
                byIndex[idx] = record
                local entries = buckets[record.bucket]
                if not entries then
                    entries = {}
                    buckets[record.bucket] = entries
                end
                entries[#entries + 1] = record
                if record.online then
                    onlineIn[record.bucket] = (onlineIn[record.bucket] or 0) + 1
                end
            end
        end
    end
    for idx = num + 1, recordCount do
        records[idx].info = nil
    end
    recordCount = num

    local sequence, orderCount = ValidOrder(group)

    renderedCount = 0
    for idx = 1, orderCount do
        local sortKey = sequence[idx]
        local entries = buckets[sortKey]
        if entries and #entries > 0 then
            renderedCount = renderedCount + 1
            rendered[renderedCount] = sortKey
        end
    end
    for idx = renderedCount + 1, #rendered do
        rendered[idx] = nil
    end

    itemCount = 0
    local y = PAD_TOP
    for idx = 1, renderedCount do
        local sortKey = rendered[idx]
        local entries = buckets[sortKey]
        table.sort(entries, CompareRecords)
        local head = NewItem(KIND_HEADER, y, HEADER_H)
        head.key = sortKey
        head.custom = sortKey ~= FAV and sortKey ~= UNGROUPED
        head.first, head.last = idx == 1, idx == renderedCount
        local nameText = sortKey
        if sortKey == FAV then
            nameText = FAVORITES or CludesUI.L("Favorites")
        elseif sortKey == UNGROUPED then
            nameText = FRIENDS or CludesUI.L("Friends")
        end
        head.label = ("%s  (%d/%d)"):format(nameText, onlineIn[sortKey] or 0, #entries)
        y = y + HEADER_H + ROW_GAP
        -- A search opens every section it finds a friend in, until a click
        -- on the section's header folds it for that search
        local open
        if searchActive then
            open = not searchCollapsed[sortKey]
        else
            open = not IsCollapsed(group, sortKey)
        end
        if open then
            for k = 1, #entries do
                NewItem(KIND_FRIEND, y, tileHeight).rec = entries[k]
                y = y + tileHeight + ROW_GAP
            end
        end
        y = y + GROUP_GAP
    end
    for idx = itemCount + 1, #itemList do
        itemList[idx].rec = nil
    end
    contentFrame:SetHeight(math.max(1, y + PAD_BOTTOM))
end

-------------------------------------------------------------------------------
--  Group changes (each one redraws at once: it is the user's own click)
-------------------------------------------------------------------------------
local Refill -- defined with the layout below

local function CreateGroup(textValue, assignKey)
    local nameText = CleanGroupName(textValue)
    if not nameText then
        return
    end
    local group = Store()
    if not FindGroup(group, nameText) then
        group.friendGroups[#group.friendGroups + 1] = { name = nameText, collapsed = false }
    end
    if assignKey then
        group.friendGroupsByTag[assignKey] = nameText
    end
    if isActive then
        Refill()
    end
end

local function RenameGroup(old, textValue)
    local nameText = CleanGroupName(textValue)
    local group = Store()
    local grp = FindGroup(group, old)
    if not (nameText and grp) or nameText == old or FindGroup(group, nameText) then
        return
    end
    grp.name = nameText
    if group.friendGroupColors[old] then
        group.friendGroupColors[nameText] = group.friendGroupColors[old]
        group.friendGroupColors[old] = nil
    end
    local sequence = group.friendGroupOrder
    for idx = 1, #sequence do
        if sequence[idx] == old then
            sequence[idx] = nameText
            break
        end
    end
    for sortKey, grpName in pairs(group.friendGroupsByTag) do
        if grpName == old then
            group.friendGroupsByTag[sortKey] = nameText
        end
    end
    if isActive then
        Refill()
    end
end

local function DeleteGroup(nameText)
    local group = Store()
    local _, at = FindGroup(group, nameText)
    if not at then
        return
    end
    table.remove(group.friendGroups, at)
    for sortKey, grpName in pairs(group.friendGroupsByTag) do
        if grpName == nameText then
            group.friendGroupsByTag[sortKey] = nil
        end
    end
    group.friendGroupColors[nameText] = nil
    if isActive then
        Refill()
    end
end

-- Battle.net's favorite switch for a friend, sent only when the friend is not
-- already that, or on its way to it
local function AskFavorite(ident, wanted)
    local details = C_BattleNet.GetAccountInfoByID(ident)
    if not details or IsFavorite(details) == wanted then
        return
    end
    favAsked[ident] = wanted
    BNSetFriendFavoriteFlag(ident, wanted)
end

-- Puts a friend in one section: a custom group (ours alone; it wins over
-- Favorites, so Battle.net is not asked), Favorites or the ungrouped friends
-- (no custom group, and Battle.net's favorite switch on or off)
local function PlaceFriend(ident, sortKey, target)
    local byTag = Store().friendGroupsByTag
    if target == FAV or target == UNGROUPED then
        if sortKey then
            byTag[sortKey] = nil
        end
        AskFavorite(ident, target == FAV)
    elseif sortKey then
        byTag[sortKey] = target
    else
        return
    end
    if isActive then
        Refill()
    end
end

local function ToggleCollapsed(sortKey)
    local group = Store()
    if sortKey == FAV then
        group.friendFavCollapsed = not group.friendFavCollapsed
    elseif sortKey == UNGROUPED then
        group.friendUngroupedCollapsed = not group.friendUngroupedCollapsed
    else
        local grp = FindGroup(group, sortKey)
        if grp then
            grp.collapsed = not grp.collapsed
        end
    end
    if isActive then
        Refill()
    end
end

-- Swaps a section with the next one shown above (-1) or below (1) it
local function MoveGroup(sortKey, dir)
    local at
    for idx = 1, renderedCount do
        if rendered[idx] == sortKey then
            at = idx
            break
        end
    end
    local other = at and rendered[at + dir]
    if not other then
        return
    end
    local group = Store()
    ValidOrder(group)
    local sequence = group.friendGroupOrder
    local a, b
    for idx = 1, #sequence do
        if sequence[idx] == sortKey then
            a = idx
        elseif sequence[idx] == other then
            b = idx
        end
    end
    if a and b then
        sequence[a], sequence[b] = sequence[b], sequence[a]
        if isActive then
            Refill()
        end
    end
end

local function PromptNewGroup(assignKey)
    CludesUI:ShowInputPopup({
        title = "New Friend Group",
        message = "Enter a name for the new group:",
        placeholder = "Enter name...",
        confirmText = "Create",
        cancelText = "Cancel",
        maxLetters = GROUP_NAME_MAX,
        onConfirm = function(textValue)
            CreateGroup(textValue, assignKey)
        end,
    })
end

local function PromptDeleteGroup(nameText)
    CludesUI:ShowConfirmPopup({
        title = "Delete Friend Group",
        message = CludesUI.Lf(
            "Delete the group %1$s? Its friends go back to Favorites or the Friends section.",
            nameText
        ),
        confirmText = "Delete",
        cancelText = "Cancel",
        onConfirm = function()
            DeleteGroup(nameText)
        end,
    })
end

-------------------------------------------------------------------------------
--  Tooltips (ours: never the game tooltip)
-------------------------------------------------------------------------------
local tipBuf = {}
local function FriendTooltip(record)
    local details = record.info
    local gameInfo = details.gameAccountInfo
    local U = FriendsListUtil
    wipe(tipBuf)
    local num = 1
    tipBuf[1] = T.Name(details)
    if record.online and gameInfo then
        if record.priority == 1 and gameInfo.characterName then
            local realm = T.Ruleset(details) or gameInfo.realmDisplayName or gameInfo.realmName
            num = num + 1
            tipBuf[num] = (realm and realm ~= "") and (gameInfo.characterName .. "-" .. realm) or gameInfo.characterName
            if gameInfo.characterLevel and gameInfo.className and FRIENDS_LEVEL_TEMPLATE then
                num = num + 1
                tipBuf[num] = FRIENDS_LEVEL_TEMPLATE:format(gameInfo.characterLevel, gameInfo.className)
            end
            if gameInfo.areaName and gameInfo.areaName ~= "" then
                num = num + 1
                tipBuf[num] = gameInfo.areaName
            end
        elseif gameInfo.richPresence and gameInfo.richPresence ~= "" then
            num = num + 1
            tipBuf[num] = gameInfo.richPresence
        end
    elseif U and U.GetLastOnlineText then
        num = num + 1
        tipBuf[num] = U.GetLastOnlineText(details)
    end
    local note = CludesUI.StripFriendNoteTag(details.note)
    if note then
        num = num + 1
        tipBuf[num] = CludesUI.COLOR_CODES.DIM .. note .. "|r"
    end
    local broadcast = U and U.BuildTooltipBroadcastText and U.BuildTooltipBroadcastText(details)
    if broadcast then
        num = num + 1
        tipBuf[num] = broadcast
    end
    return table.concat(tipBuf, "\n", 1, num)
end

local TIP_OPTS = { anchor = "right", justify = "LEFT" }

-- A row is lit while the pointer is on it or its friend is selected: one look
-- for both, the kit's hover.
local function Light(frame)
    local on = hoveredRow == frame or frame.selected == true
    frame.d.hoverBar:SetShown(on)
    frame.d.hoverFill:SetShown(on)
end

-- The pointer comes onto a row: the hover look and the friend's tooltip.
-- Over a link the game runs a frame's hyperlink hover scripts in place of its
-- plain ones (Blizzard's Quick Join rows forward them the same way), and the
-- link covers the row, so both land here.
local function RowEnter(hitbox)
    local frame = hitbox:GetParent()
    if hoveredRow == frame then
        return
    end
    local old = hoveredRow
    hoveredRow = frame
    if old then
        Light(old)
    end
    Light(frame)
    if frame.rec and frame.rec.info then
        CludesUI.ShowWidgetTooltip(frame, FriendTooltip(frame.rec), TIP_OPTS)
    end
end

local function RowLeave(hitbox)
    local frame = hitbox:GetParent()
    if hoveredRow ~= frame then
        return
    end
    hoveredRow = nil
    Light(frame)
    CludesUI.HideWidgetTooltip()
end

-------------------------------------------------------------------------------
--  Selection: a left click selects a friend, as on Blizzard's list, and a
--  second one lets go. A selected row keeps the hover look.
-------------------------------------------------------------------------------
local function SetSelected(frame, on)
    frame.selected = on
    Light(frame)
end

local function ToggleSelected(frame)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    selectedId = (selectedId ~= frame.rec.id) and frame.rec.id or nil
    for idx = 1, #rowList do
        local row = rowList[idx]
        if row.item then
            SetSelected(row, row.rec.id == selectedId)
        end
    end
end

-------------------------------------------------------------------------------
--  Clicks. The link covers the row, and Blizzard's handler for it opens the
--  friend menu on the right button and whispers on any other. The game has
--  settled which frame a click belongs to by the time it tells a press, so
--  nothing done at the press can take a click back from the link. A left
--  click is to select, so every row carries a click layer of ours over its
--  link, there all the time: it takes every button but the right one, which
--  it passes down to the link, so that click stays Blizzard's from press to
--  menu. The pointer's movement is passed down too: the link keeps the hover.
--  Both routings are refused in combat on every frame, so a row made in
--  combat gets its layer as combat ends and keeps the link's own left click
--  (a whisper) until then.
-------------------------------------------------------------------------------
local unrouted = {} -- rows made in combat: their click layer still to route

local function SetLink(frame)
    local details = frame.rec.info
    -- SetFormattedText, so a name the game keeps secret still goes in
    pcall(
        frame.link.SetFormattedText,
        frame.link,
        LINK_FORMAT,
        details.accountName,
        frame.rec.id,
        details.accountName,
        LINK_FILLER
    )
end

-- A release on the click layer: the left button selects
local function CatchRelease(catchFrame, btnFrame)
    local frame = catchFrame:GetParent()
    if btnFrame == "LeftButton" and frame.item and frame.rec and catchFrame:IsMouseOver() then
        ToggleSelected(frame)
    end
end

-- The layer's routing (out of combat only), then the layer goes over the link
local function RouteCatch(frame)
    local catchFrame = frame.catch
    catchFrame:SetPassThroughButtons("RightButton")
    catchFrame:SetPropagateMouseMotion(true)
    catchFrame:Show()
end

local function RoutePending()
    for idx = #unrouted, 1, -1 do
        RouteCatch(unrouted[idx])
        unrouted[idx] = nil
    end
end

-------------------------------------------------------------------------------
--  Invite button (Blizzard's own rules through its friends list helpers)
-------------------------------------------------------------------------------
-- The friend's index, only while it still names this friend (the game
-- renumbers friends as they come and go; a rebuild follows within a frame)
local function LiveIndex(record)
    local details = record and C_BattleNet.GetFriendAccountInfo(record.index)
    if details and details.bnetAccountID == record.id then
        return record.index
    end
end

-- What the button would do, and in red why it cannot (Blizzard's invite
-- restriction)
local function InviteEnter(button)
    local index = LiveIndex(button:GetParent().rec)
    local U = FriendsListUtil
    if not (index and U and U.GetBattleNetFriendInviteInfo) then
        return
    end
    local textValue = U.GetBattleNetFriendInviteTypeLabel(U.GetBattleNetFriendInviteInfo(index).inviteType)
        or ""
    local why
    if not button:IsEnabled() and button.restriction and U.GetBattleNetFriendPartyInviteRestrictionText then
        why = U.GetBattleNetFriendPartyInviteRestrictionText(button.restriction)
    end
    if why and why ~= "" then
        why = CludesUI.COLOR_CODES.BAD .. why .. "|r"
        textValue = textValue ~= "" and (textValue .. "\n" .. why) or why
    end
    if textValue ~= "" then
        CludesUI.ShowWidgetTooltip(button, textValue)
    end
end

local function InviteLeave()
    CludesUI.HideWidgetTooltip()
end

-- The icon steps down and right while the button is held, as Blizzard's does
local function InvitePress(button)
    if button:IsEnabled() then
        button.icon:SetPoint("CENTER", button, "CENTER", 1, -1)
    end
end

local function InviteRelease(button)
    button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
end

-- An atlas's own size (the icon keeps it, scaled with the button)
local atlasSize = {}
local function AtlasSize(atlasName)
    local px = atlasSize[atlasName]
    if not px then
        local details = C_Texture.GetAtlasInfo(atlasName)
        px = { details and details.width or 20, details and details.height or 20 }
        atlasSize[atlasName] = px
    end
    return px[1], px[2]
end

-- A friend on several characters: which one to invite
local function ShowAccountMenu(button, index)
    local U = FriendsListUtil
    local none = BattleNetFriendPartyInviteRestrictionType.None
    local dropMenu = {}
    for idx = 1, C_BattleNet.GetFriendNumGameAccounts(index) do
        local gameInfo = C_BattleNet.GetFriendGameAccountInfo(index, idx)
        if gameInfo then
            local canInvite = U.IsPlayingWoW(gameInfo) and U.GetGameAccountPartyInviteRestriction(gameInfo) == none
            local labelText = gameInfo.characterName or gameInfo.richPresence or ""
            if gameInfo.characterLevel and gameInfo.className and FRIENDS_LEVEL_TEMPLATE and U.IsPlayingWoW(gameInfo) then
                labelText = labelText
                    .. "  "
                    .. FRIENDS_LEVEL_TEMPLATE:format(gameInfo.characterLevel, gameInfo.className)
            end
            local accountID = gameInfo.gameAccountID
            dropMenu[#dropMenu + 1] = {
                text = labelText,
                noLoc = true,
                isDisabled = function()
                    return not canInvite
                end,
                onClick = function()
                    local fresh = C_BattleNet.GetGameAccountInfoByID(accountID)
                    if fresh and fresh.playerGuid then
                        U.InviteOrRequestToJoin(fresh.playerGuid, accountID)
                    end
                end,
            }
        end
    end
    if #dropMenu > 0 then
        CludesUI.ShowContextMenu(button, dropMenu)
    end
end

local function InviteClick(button)
    if not button:IsEnabled() then
        return
    end
    local index = LiveIndex(button:GetParent().rec)
    local U = FriendsListUtil
    if not (index and U and U.InviteOrRequestToJoin) then
        return
    end
    local direct = U.GetBattleNetFriendGameAccountInfoIfExactlyOneDirectInviteTargetExists(index)
    if direct then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        U.InviteOrRequestToJoin(direct.playerGuid, direct.gameAccountID)
    elseif U.HasMultipleGameAccounts(index) then
        ShowAccountMenu(button, index)
    end
end

-- Only a friend playing this game has the button (f.playing: the row shows
-- their character): an offline friend, or one in another game, has nobody to
-- invite. Off, with its icon greyed, while Blizzard's rules do not let you
-- invite them. Returns whether the button shows.
local function UpdateInvite(frame, record)
    local button = frame.PartyButton
    local U = FriendsListUtil
    if
        not (
            frame.playing
            and U
            and U.GetBattleNetFriendPartyInviteRestriction
            and BattleNetFriendPartyInviteRestrictionType
        )
    then
        button:Hide()
        return false
    end
    local restriction = U.GetBattleNetFriendPartyInviteRestriction(record.index)
    local enabled = restriction == BattleNetFriendPartyInviteRestrictionType.None
    local unitGuid = record.info.gameAccountInfo.playerGuid
    local inGroup = unitGuid ~= nil
        and C_SocialQueue ~= nil
        and C_SocialQueue.IsSystemSupported ~= nil
        and C_SocialQueue.IsSystemSupported()
        and C_SocialQueue.GetGroupForPlayer(unitGuid) ~= nil
    button.restriction = restriction
    if button.on ~= enabled then
        button.on = enabled
        button:SetEnabled(enabled)
    end
    local atlasName
    if inGroup then
        atlasName = enabled and "friends-icon-friendsInGroup" or "friends-icon-friendsInGroup-dis"
    else
        atlasName = enabled and "friends-icon-friendsAvailable" or "friends-icon-friendsAvailable-dis"
    end
    if button.atlas ~= atlasName or button.iconFor ~= frame.btnSize then
        button.atlas, button.iconFor = atlasName, frame.btnSize
        local wid, hgt = AtlasSize(atlasName)
        local k = frame.btnSize / BTN_NATIVE
        button.icon:SetAtlas(atlasName)
        button.icon:SetSize(wid * k, hgt * k)
    end
    button:Show()
    return true
end

-------------------------------------------------------------------------------
--  Friend rows
-------------------------------------------------------------------------------
local function MakeRow(slotFrame)
    local frame = CreateFrame("Frame", nil, contentFrame)
    -- Tile art and the text lines: the kit's, as on Blizzard's cards. Its
    -- state for this frame is the kit's frame data. The status after the
    -- name is Blizzard's own icon here, not the kit's orb.
    local data = T.Skin(frame)
    frame.d = data
    data.orb:Hide()
    frame.status = frame:CreateTexture(nil, "OVERLAY", nil, 3)
    -- Blizzard's own card, which an online friend's row wears (PaintRow), at
    -- the host's alpha for it: whole, it takes the place of the tile's shade
    -- and online tint; fainter, it lies under them
    if host.onlineCards then
        frame.card = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        frame.card:SetAllPoints()
        frame.card:SetAlpha(host.onlineCards)
        frame.card:Hide()
        frame.cardWhole = host.onlineCards >= 1
    end

    -- The invite button, in the art of the one on Blizzard's card. Named as
    -- there: the kit hangs its region icon beside it.
    local button = CreateFrame("Button", nil, frame)
    button:SetFrameLevel(frame:GetFrameLevel() + 6)
    button:SetPoint("RIGHT", frame, "RIGHT", -EDGE_PAD, 0)
    button:SetNormalAtlas(BTN_NORMAL)
    button:SetPushedAtlas(BTN_PUSHED)
    button:SetHighlightAtlas(BTN_NORMAL, "ADD")
    button:SetMotionScriptsWhileDisabled(true)
    button.icon = button:CreateTexture(nil, "OVERLAY")
    button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetScript("OnClick", InviteClick)
    button:SetScript("OnEnter", InviteEnter)
    button:SetScript("OnLeave", InviteLeave)
    button:SetScript("OnMouseDown", InvitePress)
    button:SetScript("OnMouseUp", InviteRelease)
    frame.PartyButton = button

    -- The link layer. Its click script stays the template's: Blizzard's.
    -- The hover scripts are ours (the template's ask the game tooltip for the
    -- link): the frame's and the link's both, since the link covers the row.
    local hitbox = CreateFrame("Frame", nil, frame, TEMPLATE)
    hitbox:SetAllPoints(frame)
    hitbox:SetFrameLevel(frame:GetFrameLevel() + 3)
    hitbox:EnableMouse(true)
    hitbox:SetScript("OnHyperlinkEnter", RowEnter)
    hitbox:SetScript("OnHyperlinkLeave", RowLeave)
    hitbox:SetScript("OnEnter", RowEnter)
    hitbox:SetScript("OnLeave", RowLeave)
    frame.hit = hitbox

    -- The click layer over the link (see Clicks): under the invite button,
    -- hidden until its routing is set
    local catchFrame = CreateFrame("Frame", nil, frame)
    catchFrame:SetAllPoints(frame)
    catchFrame:SetFrameLevel(frame:GetFrameLevel() + 4)
    catchFrame:EnableMouse(true)
    catchFrame:SetScript("OnMouseUp", CatchRelease)
    catchFrame:SetScript("OnEnter", RowEnter)
    catchFrame:SetScript("OnLeave", RowLeave)
    catchFrame:Hide()
    frame.catch = catchFrame
    if InCombatLockdown() then
        unrouted[#unrouted + 1] = frame
        CludesUI.CombatQueue.Defer("FriendsListRoute", RoutePending)
    else
        RouteCatch(frame)
    end

    local itemLink = hitbox:CreateFontString(nil, "ARTWORK")
    itemLink:SetJustifyH("LEFT")
    itemLink:SetJustifyV("TOP")
    itemLink:SetWordWrap(false)
    itemLink:SetAlpha(0)
    frame.link = itemLink

    frame:Hide()
    rowPool[slotFrame] = frame
    rowList[#rowList + 1] = frame
    return frame
end

-- Size and fonts for the tile height in force. The text is two lines, or a
-- single line on a short tile; a tall tile takes the larger name.
local function StyleRow(frame)
    local data = frame.d
    local font = T.FontPath()
    frame.style = styleGen
    frame.layKey, frame.layStop, frame.nameW, frame.charW, frame.iconMode = nil, nil, nil, nil, nil
    frame:SetSize(rowW, tileHeight)

    -- One line of text taller than the row that starts above and left of it
    -- (the sizes checked in game on rows of 24, 40 and 64): its line box is
    -- the link's live zone. The text is cut to whole letters, so the block
    -- runs two letters past the row's right edge.
    local px = tileHeight + LINK_TALLER
    frame.link:SetFont(STANDARD_TEXT_FONT, px, "")
    frame.link:ClearAllPoints()
    frame.link:SetPoint("TOPLEFT", frame.hit, "TOPLEFT", -4, LINK_ABOVE)
    frame.link:SetPoint("RIGHT", frame.hit, "RIGHT", 2 * px + 12, 0)

    local share = math.max(BTN_MIN, math.min(BTN_NATIVE, tileHeight * BTN_SHARE))
    local btnSize = math.floor((share + math.min(BTN_FLAT, tileHeight - 6)) / 2 + 0.5) + BTN_EXTRA
    frame.btnSize = btnSize
    frame.PartyButton:SetSize(btnSize, btnSize)

    local nameSize, lineSize = 15, 12
    if tierIndex == 2 then
        nameSize = 14
    elseif tierIndex == 1 then
        nameSize, lineSize = 13, 11
    end
    -- The kit's lines are font families (they show friends' names and notes)
    CludesUI.SetFontFamily(data.name, font, nameSize, "", true)
    CludesUI.SetFontFamily(data.charLine, font, lineSize, "", true)
    CludesUI.SetFontFamily(data.info, font, lineSize, "", true)
    data.name:SetTextColor(1, 1, 1, 1)
    data.charLine:SetTextColor(1, 1, 1, 1)
    data.info:SetTextColor(1, 1, 1, 1)
    data.info:SetJustifyH(tierIndex == 1 and "RIGHT" or "LEFT")
    frame.status:SetSize(nameSize, nameSize)
    frame.nameSize, frame.lineSize = nameSize, lineSize
end

-- Line 1 is the Battle.net name, the character in brackets after it and the
-- status icon; the place (with the note) is the line below, or the right end
-- of a one-line tile. The texts stop at the leftmost of the invite button and
-- the region icon (stop; false with neither, and they run to the row's
-- edge): reserve is the width those keep on the right.
local function LayoutText(frame, hasCharacter, stop, reserve)
    local data = frame.d
    local nameText, char = data.name, data.charLine
    local posX = tileHeight + TEXT_GAP
    local avail = rowW - posX - reserve - 6
    local statusW = frame.nameSize + STATUS_DX

    -- The name keeps its own width unless it would crowd the rest out
    local maxName
    if tierIndex == 1 then
        maxName = avail * (hasCharacter and 0.4 or 0.55)
    else
        maxName = hasCharacter and avail * 0.6 or avail - statusW
    end
    if maxName < 20 then
        maxName = 20
    end
    local nameW = 0
    local nw = nameText:GetUnboundedStringWidth()
    local known = not IsSecret(nw)
    if known and nw > maxName then
        nameW, nw = maxName, maxName
    end
    if frame.nameW ~= nameW then
        frame.nameW = nameW
        nameText:SetWidth(nameW)
    end

    -- The character takes what the line has left, and goes when that is too
    -- little
    local showChar = hasCharacter
    if hasCharacter then
        local charW = 0
        if known then
            local room = avail - nw - CHAR_GAP - statusW
            if tierIndex == 1 then
                room = math.min(room, avail * 0.3)
            end
            if room < 30 then
                showChar = false
            else
                local cw = char:GetUnboundedStringWidth()
                if not IsSecret(cw) and cw > room then
                    charW = room
                end
            end
        end
        if showChar and frame.charW ~= charW then
            frame.charW = charW
            char:SetWidth(charW)
        end
    end
    char:SetShown(showChar)

    local sortKey = showChar and 1 or 0
    if frame.layKey == sortKey and frame.layStop == stop then
        return
    end
    frame.layKey, frame.layStop = sortKey, stop
    local details, status = data.info, frame.status
    nameText:ClearAllPoints()
    char:ClearAllPoints()
    details:ClearAllPoints()
    status:ClearAllPoints()
    char:SetPoint("BOTTOMLEFT", nameText, "BOTTOMRIGHT", CHAR_GAP, CHAR_LIFT)
    -- The status icon keeps one height on every row, STATUS_DY above the
    -- name's middle. Beside the character it is set by its bottom against the
    -- character's, which stands CHAR_LIFT above the name's; the icon is as
    -- tall as the name, so that is the same height.
    if showChar then
        status:SetPoint("BOTTOMLEFT", char, "BOTTOMRIGHT", STATUS_DX, STATUS_DY - CHAR_LIFT)
    else
        status:SetPoint("LEFT", nameText, "RIGHT", STATUS_DX, STATUS_DY)
    end
    if tierIndex == 1 then
        nameText:SetPoint("LEFT", frame, "LEFT", posX, 0)
        details:SetPoint("LEFT", status, "RIGHT", 8, -STATUS_DY)
    else
        local gap = tierIndex == 3 and 5 or 3
        local block = frame.nameSize + gap + frame.lineSize
        nameText:SetPoint("TOPLEFT", frame, "TOPLEFT", posX, -math.max(0, (tileHeight - block) / 2))
        details:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -gap)
    end
    if stop then
        details:SetPoint("RIGHT", stop, "LEFT", -6, 0)
    else
        details:SetPoint("RIGHT", frame, "RIGHT", -EDGE_PAD - 6, 0)
    end
end

-- The character line in brackets, the brackets in the colour of its level
local bracketCache = setmetatable({}, { __mode = "k" })
local function Bracketed(details, textValue)
    local color = T.LevelColor(details)
    if not (color and color.WrapTextInColorCode) then
        return "(" .. textValue .. ")"
    end
    local pair = bracketCache[color]
    if not pair then
        pair = { color:WrapTextInColorCode("("), color:WrapTextInColorCode(")") }
        bracketCache[color] = pair
    end
    return pair[1] .. textValue .. pair[2]
end

-- Blizzard's own reading of a friend's status. Away and busy can arrive as
-- values the game keeps secret: one that cannot be read counts as not set.
local function Presence(details)
    local gameInfo = details.gameAccountInfo
    if not (gameInfo and gameInfo.isOnline) then
        return "offline"
    end
    local afk, gameAfk = details.isAFK, gameInfo.isGameAFK
    if (not IsSecret(afk) and afk) or (not IsSecret(gameAfk) and gameAfk) then
        return "away"
    end
    local dnd, gameBusy = details.isDND, gameInfo.isGameBusy
    if (not IsSecret(dnd) and dnd) or (not IsSecret(gameBusy) and gameBusy) then
        return "busy"
    end
    return "online"
end

local function UpdateIcon(frame, details, parts)
    local glyph = frame.d.classIcon
    if parts and parts.showClassIcons == false then
        glyph:Hide()
        return
    end
    local state = T.State(details)
    local hgt = tileHeight - 4
    if state == "retail" then
        local class = T.ClassFile(details)
        if not class then
            glyph:Hide()
            return
        end
        if frame.iconMode ~= 1 then
            frame.iconMode = 1
            local px = hgt - 2 * math.floor(hgt * 0.025 + 0.5)
            glyph:ClearAllPoints()
            glyph:SetSize(px, px)
            glyph:SetPoint("LEFT", frame, "LEFT", 4 + (hgt - px) / 2, 0)
        end
        T.ClassIconTex(glyph, (parts and parts.iconStyle) or "modern", class)
        glyph:SetAlpha(1)
    else
        if frame.iconMode ~= 2 then
            frame.iconMode = 2
            local px = math.floor(hgt * 0.75)
            glyph:ClearAllPoints()
            glyph:SetSize(px, px)
            glyph:SetPoint("LEFT", frame, "LEFT", 4 + math.floor((hgt - px) / 2), 0)
        end
        glyph:SetTexCoord(0, 1, 0, 1)
        if state == "other_game" and C_Texture.SetTitleIconTexture then
            local gameInfo = details.gameAccountInfo
            C_Texture.SetTitleIconTexture(glyph, gameInfo.clientProgram, Enum.TitleIconVersion.Medium, gameInfo.subIcon)
            glyph:SetAlpha(1)
        else
            glyph:SetTexture(T.OFFLINE_ICON)
            glyph:SetAlpha(0.5)
        end
    end
    glyph:SetDesaturated(false)
    glyph:Show()
end

local function PaintRow(frame, item)
    local record = item.rec
    local details = record.info
    local data = frame.d
    if frame.style ~= styleGen then
        StyleRow(frame)
    end
    frame.item, frame.gen, frame.rec = item, item.gen, record

    SetLink(frame)

    -- Every string arrives wrapped in Blizzard's colour codes
    local charText = T.CharLine(details)
    local hasCharacter = charText ~= ""
    frame.playing = hasCharacter

    local parts = Settings()
    T.Region(frame, data, details)
    -- The kit sizes its region icon once, as it makes it, and hangs it left of
    -- the invite button: ours follows the tile, and takes the button's place
    -- on a row without one
    local regionFrame = data.regionBtn
    local regionSize = math.min(28, math.floor(tileHeight * 0.8))
    if regionFrame and frame.regionFor ~= tileHeight then
        frame.regionFor = tileHeight
        regionFrame:SetSize(regionSize, regionSize)
    end
    local invite = UpdateInvite(frame, record)
    if regionFrame and frame.regionBy ~= invite then
        frame.regionBy = invite
        regionFrame:ClearAllPoints()
        if invite then
            regionFrame:SetPoint("RIGHT", frame.PartyButton, "LEFT", -2, 0)
        else
            regionFrame:SetPoint("RIGHT", frame, "RIGHT", -EDGE_PAD, 0)
        end
    end
    local regionShown = regionFrame ~= nil and regionFrame:IsShown()

    data.name:SetText(T.Name(details))
    if hasCharacter then
        data.charLine:SetText(Bracketed(details, charText))
    end
    data.info:SetText(T.Info(details))
    LayoutText(
        frame,
        hasCharacter,
        regionShown and regionFrame or (invite and frame.PartyButton),
        EDGE_PAD
            + (invite and frame.btnSize or 0)
            + (regionShown and regionSize or 0)
            + ((invite and regionShown) and 2 or 0)
    )

    local presence = Presence(details)
    if frame.presence ~= presence then
        frame.presence = presence
        frame.status:SetAtlas(STATUS_ATLAS[presence])
    end

    UpdateIcon(frame, details, parts)
    if frame.card then
        -- An online friend's row wears Blizzard's own card, as on its list: a
        -- game-level friend's or a Battle.net friend's, picked as Blizzard picks
        -- it (a level the game keeps secret counts as Battle.net). Whole, it
        -- hides the tile's shade (MakeRow). The file is at Lua's local cap,
        -- hence no constants of its own.
        local atlasName
        if record.online then
            local level, levels = details.friendLevel, Enum.BattleNetFriendLevel
            atlasName = (levels and not IsSecret(level) and level == levels.Title) and "friends-card-default"
                or "friends-card-battleNet"
        end
        if frame.cardAtlas ~= atlasName then
            frame.cardAtlas = atlasName
            if atlasName then
                frame.card:SetAtlas(atlasName, false)
            end
            frame.card:SetShown(atlasName ~= nil)
            if frame.cardWhole then
                data.tileBg:SetShown(atlasName == nil)
            end
        end
    end
    if not frame.cardWhole then
        data.onlineBg:SetShown(record.online)
    end
    T.Faction(frame, data, details)
    SetSelected(frame, record.id == selectedId)

    -- A reused row under the pointer shows the new friend's tooltip
    if hoveredRow == frame then
        CludesUI.ShowWidgetTooltip(frame, FriendTooltip(record), TIP_OPTS)
    end
end

-------------------------------------------------------------------------------
--  Section headers
-------------------------------------------------------------------------------
local ICON_ALPHA, ICON_HOVER, ICON_OFF = 0.35, 0.7, 0.06

local function AccentRGB()
    local r, group, b = CludesUI.GetAccentColor()
    if r then
        return r, group, b
    end
    local brandGreen = CludesUI.CLUDES_GREEN
    return brandGreen.r, brandGreen.g, brandGreen.b
end

-- A header icon under the pointer: its hover look and what it does, unless it
-- is switched off (the first section's up arrow, the last one's down arrow)
local function HeaderIconEnter(button)
    if button.off then
        CludesUI.HideWidgetTooltip()
        return
    end
    button:SetAlpha(ICON_HOVER)
    local tipText = button.tip
    if type(tipText) == "function" then
        tipText = tipText(button)
    end
    CludesUI.ShowWidgetTooltip(button, tipText)
end

local function HeaderIconLeave(button)
    button:SetAlpha(button.off and ICON_OFF or ICON_ALPHA)
    CludesUI.HideWidgetTooltip()
end

-- tip: the tooltip, or a function of the button that returns it
local function HeaderIcon(hostFrame, texture, onClick, tipText)
    local button = CreateFrame("Button", nil, hostFrame)
    button:SetSize(14, 14)
    button:SetFrameLevel(hostFrame:GetFrameLevel() + 2)
    local glyph = button:CreateTexture(nil, "OVERLAY")
    glyph:SetAllPoints()
    glyph:SetTexture(ICONS .. texture)
    button:SetAlpha(ICON_ALPHA)
    button.tip = tipText
    button:SetScript("OnEnter", HeaderIconEnter)
    button:SetScript("OnLeave", HeaderIconLeave)
    button:SetScript("OnClick", onClick)
    return button
end

-- Folds or opens the section; during a search, for that search alone (the
-- saved state is the one the list keeps without a search)
local function HeaderClick(hgt)
    if not searchActive then
        ToggleCollapsed(hgt.key)
        return
    end
    searchCollapsed[hgt.key] = not searchCollapsed[hgt.key] or nil
    if isActive then
        Refill()
    end
end

local function HeaderEnter(hgt)
    hgt.hover:Show()
end

local function HeaderLeave(hgt)
    hgt.hover:Hide()
end

local function HeaderUp(button)
    if not button.off then
        MoveGroup(button:GetParent().key, -1)
    end
end

local function HeaderDown(button)
    if not button.off then
        MoveGroup(button:GetParent().key, 1)
    end
end

local function HeaderDelete(button)
    PromptDeleteGroup(button:GetParent().key)
end

-- A section name's colour: the one picked for it, else the accent
local function SectionRGB(sortKey)
    local color = Store().friendGroupColors[sortKey]
    if color then
        return color.r, color.g, color.b
    end
    return AccentRGB()
end

local RepaintHeaders -- defined with the header painter below

-- The colour picker for a section's name (it lives in the options addon,
-- which the game will not load in combat). Each pick repaints the section
-- names in view, and a cancel puts the old colour back.
local function PickSectionColor(sortKey, anchor, onChange)
    if not sortKey or InCombatLockdown() then
        return
    end
    CludesUI:EnsureLoaded()
    if not CludesUI.ShowColorPicker then
        return
    end
    local colors = Store().friendGroupColors
    local was, picked = colors[sortKey], nil
    local function Set(color)
        colors[sortKey] = color
        RepaintHeaders()
        if onChange then
            onChange()
        end
    end
    local r, group, b = SectionRGB(sortKey)
    CludesUI:ShowColorPicker({
        r = r,
        g = group,
        b = b,
        hasOpacity = false,
        swatchFunc = function()
            local dialog = CludesUI._colorPickerPopup
            if not dialog then
                return
            end
            picked = picked or {}
            picked.r, picked.g, picked.b = dialog:GetColorRGB()
            Set(picked)
        end,
        cancelFunc = function()
            Set(was)
        end,
    }, anchor)
end

-- A custom group's name and colour in one popup: the swatch beside the name
-- opens the colour picker, whose own OK and Cancel keep or drop the colour
-- (the popup's buttons are the name's alone).
local function PromptEditGroup(nameText)
    CludesUI:ShowInputPopup({
        title = "Rename Friend Group",
        message = "Enter a new name for this group:",
        initialText = nameText,
        placeholder = "Enter name...",
        confirmText = "Rename",
        cancelText = "Cancel",
        maxLetters = GROUP_NAME_MAX,
        swatch = {
            get = function()
                return SectionRGB(nameText)
            end,
            onClick = function(colorSwatch, repaint)
                PickSectionColor(nameText, colorSwatch, repaint)
            end,
            tooltip = "Color",
        },
        onConfirm = function(textValue)
            RenameGroup(nameText, textValue)
        end,
    })
end

-- The pencil: a custom group's popup, or the colour alone for a section that
-- cannot be renamed
local function HeaderEdit(button)
    local hgt = button:GetParent()
    if hgt.custom then
        PromptEditGroup(hgt.key)
    else
        PickSectionColor(hgt.key, button)
    end
end

local function EditTip(button)
    return button:GetParent().custom and "Edit Group" or "Change Color"
end

local function MakeHeader(slotFrame)
    local hgt = CreateFrame("Button", nil, contentFrame)
    hgt:SetHeight(HEADER_H)
    local backdrop = hgt:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(1, 1, 1, 0.04)
    hgt.hover = hgt:CreateTexture(nil, "ARTWORK", nil, -5)
    hgt.hover:SetAllPoints()
    hgt.hover:SetColorTexture(1, 1, 1, 0.06)
    hgt.hover:Hide()

    -- A group's name, as the player typed it: a font family, set by PaintHeader
    hgt.label = hgt:CreateFontString(nil, "OVERLAY")
    hgt.label:SetPoint("CENTER", hgt, "CENTER", 0, 0)

    hgt.up = HeaderIcon(hgt, "cui-arrow-up3.png", HeaderUp, "Move Up")
    hgt.down = HeaderIcon(hgt, "cui-arrow-down3.png", HeaderDown, "Move Down")
    hgt.edit = HeaderIcon(hgt, "cui-edit.png", HeaderEdit, EditTip)
    hgt.x = HeaderIcon(hgt, "cui-close.png", HeaderDelete, "Delete Group")
    hgt.up:SetPoint("LEFT", hgt, "LEFT", 8, 0)
    hgt.down:SetPoint("RIGHT", hgt, "RIGHT", -8, 0)
    hgt.edit:SetPoint("LEFT", hgt.up, "RIGHT", 4, 0)
    hgt.x:SetPoint("RIGHT", hgt.down, "LEFT", -4, 0)

    hgt.lineL = hgt:CreateTexture(nil, "OVERLAY")
    hgt.lineL:SetColorTexture(1, 1, 1, 0.1)
    hgt.lineL:SetHeight(1)
    hgt.lineL:SetPoint("LEFT", hgt.edit, "RIGHT", 6, 0)
    hgt.lineL:SetPoint("RIGHT", hgt.label, "LEFT", -6, 0)
    hgt.lineR = hgt:CreateTexture(nil, "OVERLAY")
    hgt.lineR:SetColorTexture(1, 1, 1, 0.1)
    hgt.lineR:SetHeight(1)

    -- A click anywhere on the bar but its icons, the name included, collapses
    hgt:SetScript("OnClick", HeaderClick)
    hgt:SetScript("OnEnter", HeaderEnter)
    hgt:SetScript("OnLeave", HeaderLeave)
    hgt:Hide()
    headerPool[slotFrame] = hgt
    headerList[#headerList + 1] = hgt
    return hgt
end

local function SetIconOff(button, off)
    button.off = off
    button:SetAlpha(off and ICON_OFF or ICON_ALPHA)
end

local function PaintHeader(hgt, item)
    hgt.item, hgt.gen, hgt.key = item, item.gen, item.key
    if hgt.style ~= styleGen then
        hgt.style = styleGen
        hgt.custom = nil
        hgt:SetWidth(rowW)
        CludesUI.SetFontFamily(hgt.label, T.FontPath(), 12, "", true)
    end
    hgt.label:SetText(item.label)
    local r, group, b = SectionRGB(item.key)
    hgt.label:SetTextColor(r, group, b, 1)
    SetIconOff(hgt.up, item.first)
    SetIconOff(hgt.down, item.last)
    -- Only a custom group can be deleted; every section has the pencil
    if hgt.custom ~= item.custom then
        hgt.custom = item.custom
        hgt.x:SetShown(item.custom)
        hgt.lineR:ClearAllPoints()
        hgt.lineR:SetPoint("LEFT", hgt.label, "RIGHT", 6, 0)
        hgt.lineR:SetPoint("RIGHT", item.custom and hgt.x or hgt.down, "LEFT", -6, 0)
    end
    -- Painted again under the pointer (a click on an arrow moved the
    -- sections): the hovered icon's look and tooltip follow what it does now
    if hgt.up:IsMouseMotionFocus() then
        HeaderIconEnter(hgt.up)
    end
    if hgt.down:IsMouseMotionFocus() then
        HeaderIconEnter(hgt.down)
    end
    if hgt.edit:IsMouseMotionFocus() then
        HeaderIconEnter(hgt.edit)
    end
end

RepaintHeaders = function()
    for idx = 1, #headerList do
        local hgt = headerList[idx]
        if hgt.item and hgt:IsShown() then
            PaintHeader(hgt, hgt.item)
        end
    end
end

-------------------------------------------------------------------------------
--  Layout: only the items in view hold a frame. An item keeps one pool slot
--  (its index around the ring), so scrolling repaints only what enters view.
-------------------------------------------------------------------------------
local function FirstVisible(topY)
    local lo, hi = 1, itemCount
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        local item = itemList[mid]
        if item.y + item.h < topY then
            lo = mid + 1
        else
            hi = mid
        end
    end
    return lo
end

local function HideUnseen(entries)
    for idx = 1, #entries do
        local frame = entries[idx]
        if frame.vis ~= visGen and frame.item then
            frame.item, frame.rec = nil, nil
            if hoveredRow == frame then
                hoveredRow = nil
                CludesUI.HideWidgetTooltip()
            end
            frame:Hide()
        end
    end
end

local function LayoutVisible()
    if not isActive then
        return
    end
    visGen = visGen + 1
    if itemCount > 0 and viewH > 0 then
        local topY = scrollFrame:GetVerticalScroll()
        local bottom = topY + viewH
        for idx = FirstVisible(topY), itemCount do
            local item = itemList[idx]
            if item.y >= bottom then
                break
            end
            local slotFrame = (idx - 1) % ring + 1
            local frame
            if item.kind == KIND_FRIEND then
                frame = rowPool[slotFrame] or MakeRow(slotFrame)
                if frame.item ~= item or frame.gen ~= item.gen or frame.style ~= styleGen then
                    PaintRow(frame, item)
                end
            else
                frame = headerPool[slotFrame] or MakeHeader(slotFrame)
                if frame.item ~= item or frame.gen ~= item.gen or frame.style ~= styleGen then
                    PaintHeader(frame, item)
                end
            end
            if frame.posY ~= item.y then
                frame.posY = item.y
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PAD_LEFT, -item.y)
            end
            frame.vis = visGen
            frame:Show()
        end
    end
    HideUnseen(rowList)
    HideUnseen(headerList)
end

-------------------------------------------------------------------------------
--  The scroll bar: a frame of ours made from the template of Blizzard's own
--  bar and laid over that bar, so the two lists look alike. It follows the
--  list (how much is in view, where the view stands, one tile per arrow
--  press), and a drag of its thumb or a press on an arrow or its track
--  scrolls the list. So does the wheel, over the list as over the bar: it is
--  the bar's own wheel step, two tiles a tick, at once, as on Blizzard's list.
-------------------------------------------------------------------------------
local barBusy = false -- the bar and the list are telling each other one spot

local function ScrollRange()
    return math.max(0, contentFrame:GetHeight() - scrollFrame:GetHeight())
end

-- Where the view stands, after a scroll step of the list
local function SyncBarSpot()
    local range = ScrollRange()
    barBusy = true
    bar:SetScrollPercentage(range > 0 and scrollFrame:GetVerticalScroll() / range or 0, true)
    barBusy = false
end

-- The whole bar, after the list or the view changed size
local function SyncBar()
    local range = ScrollRange()
    barBusy = true
    bar:SetVisibleExtentPercentage(range > 0 and scrollFrame:GetHeight() / contentFrame:GetHeight() or 1)
    bar:SetPanExtentPercentage(range > 0 and (tileHeight + ROW_GAP) / range or 0)
    bar:SetScrollPercentage(range > 0 and scrollFrame:GetVerticalScroll() / range or 0, true)
    barBusy = false
end

-- The list moved: the rows in view, and the bar unless the bar moved it
local function OnListScroll()
    LayoutVisible()
    if not barBusy then
        SyncBarSpot()
    end
end

-- The list to a spot inside its range, at once
local function ScrollTo(val)
    scrollFrame:SetVerticalScroll(val)
    OnListScroll()
end

-- The bar moved by hand
local function OnBarScroll(_, percentage)
    if barBusy then
        return
    end
    barBusy = true
    ScrollTo(percentage * ScrollRange())
    barBusy = false
end

-- Everything from the friend data up: model, scroll range, the rows in view.
-- The view keeps its spot; only a spot past the new end is pulled back.
Refill = function()
    Rebuild()
    local range = ScrollRange()
    if scrollFrame:GetVerticalScroll() > range then
        ScrollTo(range)
    else
        LayoutVisible()
    end
    SyncBar()
end

-- The tile height in force and what follows from it
local function ApplyMetrics()
    local parts = Settings()
    tileHeight = ClampTile(parts and parts.tileHeight)
    tierIndex = tileHeight >= 52 and 3 or (tileHeight >= 34 and 2 or 1)
    viewH = scrollFrame:GetHeight() or 0
    rowW = math.max(1, (scrollFrame:GetWidth() or 0) - PAD_LEFT - PAD_RIGHT)
    contentFrame:SetWidth(math.max(1, scrollFrame:GetWidth() or 0))
    -- Slots for every item one view can span, and a few to spare
    ring = math.ceil(viewH / (math.min(tileHeight, HEADER_H) + ROW_GAP)) + 4
    -- Every row and header in view restyles on the next layout; one the new
    -- layout no longer reaches still holds its item, so that pass hides it
    styleGen = styleGen + 1
    -- Every row those slots can need is made now, so a scroll never has to
    -- make one
    if viewH > 0 then
        for slotFrame = 1, ring do
            if not rowPool[slotFrame] then
                MakeRow(slotFrame)
            end
        end
    end
end

-- One friend changed and nothing that places it did: its row alone repaints
local function TryRowDelta(index)
    if searchActive then
        return false
    end
    local record = byIndex[index]
    if not record then
        return false
    end
    local details = C_BattleNet.GetFriendAccountInfo(index)
    if not details or details.bnetAccountID ~= record.id then
        return false
    end
    local gameInfo = details.gameAccountInfo
    if
        (gameInfo ~= nil and gameInfo.isOnline == true) ~= record.online
        or Priority(gameInfo) ~= record.priority
        or BucketOf(Store(), details, record.key) ~= record.bucket
    then
        return false
    end
    record.info = details
    for idx = 1, #rowList do
        local frame = rowList[idx]
        if frame.rec == record and frame.item then
            PaintRow(frame, frame.item)
            break
        end
    end
    return true
end

local function RepaintInvites()
    for idx = 1, #rowList do
        local frame = rowList[idx]
        if frame.item and frame.rec and frame.rec.info then
            UpdateInvite(frame, frame.rec)
        end
    end
end

local function OnEvent(_, evt, arg1)
    if evt == "GROUP_ROSTER_UPDATE" then
        dirtyInvites = true
    else
        if evt == "BN_FRIEND_LIST_SIZE_CHANGED" then
            wipe(keyById)
            wipe(sortById)
        end
        -- A rebuild is on its way already, or one friend changed in place
        if fullDirty then
            return
        end
        if evt == "BN_FRIEND_INFO_CHANGED" and arg1 and TryRowDelta(arg1) then
            return
        end
        fullDirty = true
    end
    flusher:Show()
end

local function OnFlush(self)
    self:Hide()
    if not isActive then
        return
    end
    if fullDirty then
        fullDirty, dirtyInvites = false, false
        Refill()
    elseif dirtyInvites then
        dirtyInvites = false
        RepaintInvites()
    end
end

-- Blizzard's search box or filter menu changed what its own list shows
local function OnBlizzardSearch()
    if isActive then
        fullDirty = true
        flusher:Show()
    end
end

-------------------------------------------------------------------------------
--  Our entries on Blizzard's friend menu, only for a menu opened from a row of
--  this list (the pointer is on it while the menu is built)
-------------------------------------------------------------------------------
local function PromptNote(ident)
    local details = C_BattleNet.GetAccountInfoByID(ident)
    if not details then
        return
    end
    CludesUI:ShowInputPopup({
        title = "Set Note",
        message = "Enter a note for this friend:",
        initialText = CludesUI.StripFriendNoteTag(details.note) or "",
        placeholder = "Enter note...",
        confirmText = "Save",
        cancelText = "Cancel",
        maxLetters = NOTE_MAX,
        allowEmpty = true, -- an empty note deletes it
        onConfirm = function(textValue)
            BNSetFriendNote(ident, textValue or "")
        end,
    })
end

local function PromptRemove(ident)
    CludesUI:ShowConfirmPopup({
        title = "Remove Friend",
        message = "Remove this friend from your friends list?",
        confirmText = "Remove",
        cancelText = "Cancel",
        onConfirm = function()
            BNRemoveFriend(ident)
        end,
    })
end

-- Blizzard's friend tags as checkboxes: one set for the interests and the
-- roles, sent whole on every tick
local function AddTagEntries(sub, ident, details)
    local set = {}
    local have = details.friendTags
    if type(have) == "table" then
        for idx = 1, #have do
            set[have[idx]] = true
        end
    end
    local function IsOn(tagText)
        return set[tagText] == true
    end
    local function Toggle(tagText)
        set[tagText] = not set[tagText] or nil
        local entries = {}
        for t in pairs(set) do
            entries[#entries + 1] = t
        end
        C_BattleNet.SetFriendTags(ident, entries)
    end
    local function Add(tags)
        if type(tags) ~= "table" then
            return
        end
        for idx = 1, #tags do
            sub:CreateCheckbox(SocialUIUtil.GetLabelForBattleNetFriendTag(tags[idx]), IsOn, Toggle, tags[idx])
        end
    end
    Add(SocialUIUtil.GetSupportedBattleNetFriendTagInterestsForCurrentGameType())
    Add(SocialUIUtil.GetSupportedBattleNetFriendTagRolesForCurrentGameType())
end

local registering = false
local function AddMenuEntries(_, dropMenu, contextData)
    if registering or not (isActive and rootFrame:IsMouseOver()) then
        return
    end
    if type(contextData) ~= "table" or contextData.friendsList then
        return
    end
    local record = byId[tonumber(contextData.bnetIDAccount) or 0]
    local details = record and record.info
    if not details then
        return
    end
    local ident, sortKey = record.id, record.key
    local group = Store()
    local current = BucketOf(group, details, sortKey)

    -- The friend entries Blizzard's menu offers only from its own list. No
    -- divider before them: they join its last section, as there. The
    -- favorite line does what the Favorites entries further down do.
    dropMenu:CreateButton(SET_NOTE or CludesUI.L("Set Note"), function()
        PromptNote(ident)
    end)
    if current == FAV then
        dropMenu:CreateButton(REMOVE_FAVORITE_STATUS or CludesUI.L("Remove Favorite"), function()
            PlaceFriend(ident, sortKey, UNGROUPED)
        end)
    else
        dropMenu:CreateButton(ADD_FAVORITE_STATUS or CludesUI.L("Add Favorite"), function()
            PlaceFriend(ident, sortKey, FAV)
        end)
    end
    if
        SocialUIUtil
        and C_BattleNet.AreFriendTagsEnabled
        and C_BattleNet.AreFriendTagsEnabled()
        and C_BattleNet.SetFriendTags
    then
        AddTagEntries(
            dropMenu:CreateButton(SOCIAL_UI_BATTLE_NET_FRIEND_TAGS_LABEL or CludesUI.L("Tags")),
            ident,
            details
        )
    end
    dropMenu:CreateButton(REMOVE_FRIEND or CludesUI.L("Remove Friend"), function()
        PromptRemove(ident)
    end)

    -- Our own sections, after them: Favorites and the custom groups alike,
    -- less the one the friend sits in
    if sortKey then
        dropMenu:CreateDivider()
        dropMenu:CreateTitle("CludesUI")
        local grouped = current ~= UNGROUPED
        local sub =
            dropMenu:CreateButton(grouped and CludesUI.L("Move to Group") or CludesUI.L("Add to Group"))
        sub:CreateButton(CludesUI.L("New Group..."), function()
            PromptNewGroup(sortKey)
        end)
        local entries = group.friendGroups
        if current ~= FAV or #entries > 0 then
            sub:CreateDivider()
        end
        if current ~= FAV then
            sub:CreateButton(FAVORITES or CludesUI.L("Favorites"), function()
                PlaceFriend(ident, sortKey, FAV)
            end)
        end
        for idx = 1, #entries do
            local nameText = entries[idx].name
            if nameText ~= current then
                sub:CreateButton(nameText, function()
                    PlaceFriend(ident, sortKey, nameText)
                end)
            end
        end
        if grouped then
            sub:CreateDivider()
            sub:CreateButton(CludesUI.L("Remove from Group"), function()
                PlaceFriend(ident, sortKey, UNGROUPED)
            end)
        end
    end
end

-------------------------------------------------------------------------------
--  Build (once), show and stand down
-------------------------------------------------------------------------------
local function Build()
    local viewMode = View()
    rootFrame = CreateFrame("Frame", nil, viewMode)
    -- Over Blizzard's list and its scroll bar: as wide as the view's top
    -- divider and a little past it, down to the bottom one. Above every
    -- card, and it takes the mouse, so the list underneath gets none.
    rootFrame:SetPoint("TOPLEFT", viewMode.TopDivider, "TOPLEFT", 0, -5)
    rootFrame:SetPoint("TOPRIGHT", viewMode.TopDivider, "TOPRIGHT", 3, -5)
    rootFrame:SetPoint("BOTTOM", viewMode.BottomDivider, "TOP", 0, 1)
    rootFrame:SetFrameLevel(viewMode:GetFrameLevel() + 40)
    rootFrame:EnableMouse(true)
    rootFrame:Hide()

    -- The scroll area is the one Blizzard's list has
    scrollFrame = CreateFrame("ScrollFrame", nil, rootFrame)
    scrollFrame:SetAllPoints(viewMode.ScrollBox)
    contentFrame = CreateFrame("Frame", nil, scrollFrame)
    contentFrame:SetSize(1, 1)
    scrollFrame:SetScrollChild(contentFrame)
    bar = CreateFrame("EventFrame", nil, rootFrame, "MinimalScrollBar")
    bar:SetAllPoints(viewMode.ScrollBar)
    bar:RegisterCallback(ScrollBarMixin.Event.OnScroll, OnBarScroll, bar)
    -- The wheel over the list is the bar's own (the template's handler over
    -- the bar): two tiles a tick, at once
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        bar:OnMouseWheel(delta)
    end)
    scrollFrame:SetScript("OnSizeChanged", function()
        if not isActive then
            return
        end
        ApplyMetrics()
        Refill()
    end)

    -- Blizzard's friends filter shows nothing while a filter is ticked, so
    -- the house X sits where a filter menu's reset button does. It takes no
    -- mouse: a click on it reaches the Filter button under it, whose menu
    -- unticks the filters (a filter changed from our code would run the
    -- friend search as ours, which the game refuses).
    local dropdown = viewMode.FilterBar and viewMode.FilterBar.SearchFilterDropdown
    if dropdown then
        filterX = CreateFrame("Frame", nil, rootFrame)
        filterX:SetSize(10, 10)
        filterX:SetPoint("CENTER", dropdown, "TOPRIGHT", -3, 0)
        local posX = filterX:CreateTexture(nil, "OVERLAY", nil, 7)
        posX:SetAllPoints()
        posX:SetAtlas("uitools-icon-close", false)
        posX:SetVertexColor(1, 1, 1, 0.9)
        filterX:Hide()
    end

    -- Friend events mark the list; this hidden frame redraws it once, on the
    -- next frame, then hides again
    flusher = CreateFrame("Frame")
    flusher:Hide()
    flusher:SetScript("OnUpdate", OnFlush)

    event = CreateFrame("Frame")
    event:SetScript("OnEvent", OnEvent)

    -- The one hook on Blizzard's view: its search box and filter menu both
    -- end in this call. A post-hook; it only marks our list.
    if viewMode.RefreshSearchResults then
        hooksecurefunc(viewMode, "RefreshSearchResults", OnBlizzardSearch)
    end

    -- A new accent colour repaints the section names that follow it
    CludesUI.RegAccent({
        type = "callback",
        fn = function()
            if not isActive then
                return
            end
            styleGen = styleGen + 1
            LayoutVisible()
        end,
    })
end

local function WantActive()
    local parts = Settings()
    if not (parts and parts.enabled ~= false and parts.customTiles ~= false) then
        return false
    end
    if not FL.Available() or CludesUI.PadGamepadUI() then
        return false
    end
    if
        C_SocialRestrictions
        and C_SocialRestrictions.IsFriendsDisabled
        and C_SocialRestrictions.IsFriendsDisabled()
    then
        return false
    end
    return true
end

-- The friends view hid: nothing of ours runs until it shows again. Blizzard's
-- list stays covered, so its cards are not painted for nothing meanwhile.
local function Park()
    if not isActive then
        return
    end
    isActive = false
    rootFrame:Hide()
    flusher:Hide()
    fullDirty, dirtyInvites = false, false
    event:UnregisterAllEvents()
    for idx = #menuHandles, 1, -1 do
        menuHandles[idx]:Unregister()
        menuHandles[idx] = nil
    end
    hoveredRow, selectedId = nil, nil
    wipe(favAsked)
    wipe(searchCollapsed)
    CludesUI.HideWidgetTooltip()
end

-- The list stands down: Blizzard's own list shows again
local function Uncover()
    if not covering then
        return
    end
    covering = false
    Kit._listShown = false
    local viewMode = View()
    if viewMode then
        viewMode.ScrollBox:SetAlpha(1)
        viewMode.ScrollBar:SetAlpha(1)
    end
    -- Blizzard's cards the kit left unpainted while ours covered them
    Kit.RedecorateTiles()
end

local function Activate()
    if not rootFrame then
        Build()
    end
    if not covering then
        covering = true
        Kit._listShown = true
        local viewMode = View()
        -- Top-level alpha only: Blizzard's list keeps running underneath
        viewMode.ScrollBox:SetAlpha(0)
        viewMode.ScrollBar:SetAlpha(0)
    end
    local opening = not isActive
    if opening then
        isActive = true
        rootFrame:Show()
        event:RegisterEvent("BN_FRIEND_INFO_CHANGED")
        event:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
        event:RegisterEvent("BN_CONNECTED")
        event:RegisterEvent("BN_DISCONNECTED")
        event:RegisterEvent("GROUP_ROSTER_UPDATE")
        -- ModifyMenu replays the callback at once on the last menu built
        registering = true
        for idx = 1, #MENU_TAGS do
            menuHandles[#menuHandles + 1] = Menu.ModifyMenu(MENU_TAGS[idx], AddMenuEntries)
        end
        registering = false
    end
    ApplyMetrics()
    Refill()
    -- A filter left ticked: Blizzard's list fills as the view shows, which may
    -- come after this, so the friends it keeps are read once more next frame
    if opening and searchActive then
        fullDirty = true
        flusher:Show()
    end
end

-- The friends view showed, or a setting changed. The list is live only while
-- the view shows; it stays over Blizzard's hidden list until it stands down.
local function Sync()
    if not WantActive() then
        Park()
        Uncover()
    elseif driver and driver:IsVisible() then
        Activate()
    else
        Park()
    end
end

-------------------------------------------------------------------------------
--  Public
-------------------------------------------------------------------------------
-- The Social UI friends list exists, and entries added to Blizzard's friend
-- menu are isolated on this client
function FL.Available()
    return View() ~= nil and Menu ~= nil and Menu.ModifyMenu ~= nil and Menu.IsMenuProxy ~= nil
end

-- Lowest, highest and default Tile Height, for the options slider
function FL.TileRange()
    return TILE_MIN, TILE_MAX, TILE_DEFAULT
end

-- A setting changed (the host's options call this), or the list starts
function FL.Refresh()
    if not host then
        return
    end
    local parts = Settings()
    if not (parts and parts.enabled ~= false and parts.customTiles ~= false and FL.Available()) then
        if driver then
            driver:Hide()
        end
        Park()
        Uncover()
        return
    end
    if not driver then
        -- A child of the friends view: its show and hide are the list's
        driver = CreateFrame("Frame", nil, View())
        driver:SetScript("OnShow", Sync)
        driver:SetScript("OnHide", Park)
    end
    driver:Show()
    Sync()
end

-- Starts the list for the session, once, after the kit's tiles
-- (Kit.StartTiles, with or without its cards): it draws with the same
-- host's settings and font, and only under the CludesUI look (a stock
-- look keeps Blizzard's list).
function FL.Start()
    if host then
        return
    end
    local hgt = T.Host()
    if not hgt or hgt.style ~= "cui" then
        return
    end
    host = hgt
    FL.Refresh()
end
