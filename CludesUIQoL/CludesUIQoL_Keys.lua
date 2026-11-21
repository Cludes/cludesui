if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if CludesUI and CludesUI.IS_FOREVER then
    return
end -- no keystones on WoW Forever: no /keys popup, no events, no slash commands; the options section is not built there and every reader nil-guards
-------------------------------------------------------------------------------
--  CludesUIQoL_Keys.lua
--  /keys slash command: displays party keystone levels in a styled popup.
--  Uses LibKeystone (BigWigs/DBM) for keystone data exchange.
-------------------------------------------------------------------------------
local LibKeystone = LibStub and LibStub("LibKeystone", true)

local myRealm = (GetRealmName():gsub("%s", ""))
local partyKeys = {} -- [playerName] = { dungeon = mapID, keyLevel = N, rating = N }

-- Dungeon mapID -> teleport spellID
-- mapIDs here match what C_ChallengeMode returns and what keystone links store.
-- Built dynamically from C_ChallengeMode.GetMapTable + spell lookup.
local MAP_TELEPORT_SPELLS = {}
local TELEPORT_BY_NAME = {}
local RebuildTeleportTables
do
    -- Rebuildable: on login, C_ChallengeMode/GetLFGDungeonInfo data can still be
    -- uncached the first time this file runs, leaving both tables empty forever
    -- since this used to be a one-shot do-block. RebuildTeleportTables() re-runs
    -- from ShowKeystonePopup() and from a resolver miss whenever
    -- MAP_TELEPORT_SPELLS is still empty, so a late-populated cache self-heals
    -- instead of leaving every teleport button (and the LFG teleport prompt's
    -- localized names) dead for the session. Idempotent: same keys rewritten.
    function RebuildTeleportTables()
        -- Spell IDs indexed by dungeon name (case-insensitive matching), built
        -- from the shared season list (CludesUI.SEASON_PORTALS) -- one place
        -- to update per season.
        for _, entry in ipairs(CludesUI.SEASON_PORTALS) do
            for _, num in ipairs(entry.names) do
                TELEPORT_BY_NAME[num] = entry.spellID
            end
            -- Locale-agnostic: GetLFGDungeonInfo returns the dungeon's name in
            -- whatever locale THIS client is running -- the same source the LFG
            -- teleport prompt's activity fullName comes from -- so this covers
            -- every client locale automatically instead of only the languages
            -- hardcoded in `names` above (English/Russian only, so e.g. a German
            -- client never got a match and the LFG Reminder popup silently never fired).
            if entry.dungeonID and GetLFGDungeonInfo then
                local success, localName = pcall(GetLFGDungeonInfo, entry.dungeonID)
                if success and type(localName) == "string" and localName ~= "" then
                    TELEPORT_BY_NAME[localName:lower()] = entry.spellID
                end
            end
        end
        if C_ChallengeMode and C_ChallengeMode.GetMapTable then
            local maps = C_ChallengeMode.GetMapTable()
            for _, mapID in ipairs(maps) do
                local name = C_ChallengeMode.GetMapUIInfo(mapID)
                if name then
                    local spellId = TELEPORT_BY_NAME[name:lower()]
                    if spellId then
                        MAP_TELEPORT_SPELLS[mapID] = spellId
                    end
                end
            end
        end
    end
    RebuildTeleportTables()

    -- Clean resolver: dungeon display name -> teleport spellID. Returns a plain
    -- integer literal (never a secret value) or nil. Used by the LFG teleport
    -- prompt to map an accepted dungeon's name to its teleport spell without
    -- touching any secret LFG field. Strips a trailing parenthetical suffix.
    -- A miss while the map table is still empty means the localized names never
    -- loaded either: rebuild once and look again (the popup path heals the same way).
    CludesUI.ResolveTeleportSpellByName = function(displayName)
        if type(displayName) ~= "string" then
            return nil
        end
        local num = displayName:lower():gsub("%s*%b()%s*$", "")
        local spellId = TELEPORT_BY_NAME[num]
        if not spellId and not next(MAP_TELEPORT_SPELLS) then
            RebuildTeleportTables()
            spellId = TELEPORT_BY_NAME[num]
        end
        return spellId
    end
end
local guildKeys = {} -- [playerName] = { dungeon = mapID, keyLevel = N, rating = N }

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function PlayerName(unitToken)
    local name, realm = UnitFullName(unitToken or "player")
    if not name then
        return UnitName(unitToken or "player") or "Unknown"
    end
    if realm and realm ~= "" and realm ~= myRealm then
        return name .. "-" .. realm
    end
    return name
end

local function StripRealm(fullName)
    if not fullName then
        return "?"
    end
    if Ambiguate then
        return Ambiguate(fullName, "short") or fullName
    end
    return fullName:match("^([^%-]+)") or fullName
end

-- Class-color lookup for popup rows, built ONCE per popup rebuild: a single
-- pass over the guild roster plus the group units, keyed by short name.
-- Rows then resolve their color with one table read. (A per-row linear roster
-- scan multiplies into millions of GetGuildRosterInfo calls per rebuild in a
-- large guild and was the source of rare multi-second frame freezes.)
local function BuildClassColorMap()
    local map = {}
    -- Guild roster first so group/player entries below win on name collisions
    if IsInGuild() and GetNumGuildMembers then
        local sum = GetNumGuildMembers()
        for index = 1, sum do
            local gName, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(index)
            if gName and class then
                local gShort = Ambiguate and Ambiguate(gName, "short") or gName:match("^([^%-]+)")
                if gShort then
                    map[gShort] = class
                end
            end
        end
    end
    local prefixText, count
    if IsInRaid() then
        prefixText, count = "raid", GetNumGroupMembers()
    elseif IsInGroup() then
        prefixText, count = "party", GetNumGroupMembers() - 1
    else
        prefixText, count = nil, 0
    end
    if prefixText then
        for index = 1, count do
            local unitToken = prefixText .. index
            local uName = UnitName(unitToken)
            if uName then
                local _, class = UnitClass(unitToken)
                if class then
                    map[uName] = class
                end
            end
        end
    end
    local myName = UnitName("player")
    if myName then
        local _, class = UnitClass("player")
        if class then
            map[myName] = class
        end
    end
    return map
end

local function GetMyKeystone()
    if not C_MythicPlus then
        return 0, 0
    end
    local map = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        or 0
    local lvl = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel() or 0
    return map, lvl
end

local function DungeonNameFromMap(mapID)
    if not mapID or mapID == 0 then
        return nil
    end
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        return (C_ChallengeMode.GetMapUIInfo(mapID))
    end
    return "Unknown"
end

-------------------------------------------------------------------------------
--  Keystone read / request
-------------------------------------------------------------------------------
local function StoreOwnKey()
    local map, lvl = GetMyKeystone()
    local rating = 0
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
        if summary and summary.currentSeasonScore then
            rating = summary.currentSeasonScore
        end
    end
    local me = UnitName("player")
    local _, myClassFile = UnitClass("player")
    if me then
        partyKeys[me] = { dungeon = map, keyLevel = lvl, rating = rating, classFile = myClassFile }
    end
end

local function QueryPartyKeys()
    if not LibKeystone then
        return
    end
    -- A party of your own: PARTY from a Dungeon Finder group alone only brings back "You aren't in a party."
    if IsInGroup(LE_PARTY_CATEGORY_HOME) then
        LibKeystone.Request("PARTY")
    end
    LibKeystone.Request("GUILD")
end

-------------------------------------------------------------------------------
--  Popup UI
-------------------------------------------------------------------------------
local CUI = CludesUI
local Pix = CUI and CUI.PP
local POPUP_W = 330
local ROW_H = 20
local ROW_GAP = 4
local TITLE_H = 27
local PAD = 10
local HDR_H = 18 -- section header height ("Party", "Guild")
local HDR_GAP = 1 -- gap after section header
local SEC_GAP = 20 -- gap before Guild section
local MAX_CONTENT_H = 300

local dialog, rowFrames
local ShowKeystonePopup -- forward declaration

local function ResolveFont()
    return (CUI.GetFontPath("extras")) or "Fonts\\FRIZQT__.TTF"
end

local function ResolveOutline()
    return (CUI.GetFontOutlineFlag("extras")) or ""
end

-- family: a text that shows a player's name takes the font as a font family,
-- which draws the scripts the font lacks
local function MakeLabel(hostFrame, size, _, red, green, blue, a, family)
    local fontStr = hostFrame:CreateFontString(nil, "OVERLAY")
    local flags = ResolveOutline()
    if family then
        CludesUI.SetFontFamily(fontStr, ResolveFont(), size, flags, flags == "")
    else
        CludesUI.PrimeFontShadow(fontStr, flags == "")
        fontStr:SetFont(ResolveFont(), size, flags)
    end
    if red then
        fontStr:SetTextColor(red, green or 1, blue or 1, a or 1)
    end
    return fontStr
end

local function MakeSolid(hostFrame, layer, red, green, blue, a, sub)
    local tex = hostFrame:CreateTexture(nil, layer, nil, sub or 0)
    tex:SetColorTexture(red, green, blue, a)
    return tex
end

local function MakePopup()
    if dialog then
        return dialog
    end
    rowFrames = {}

    dialog = CreateFrame("Frame", "CUIKeysPopup", UIParent)
    dialog:SetSize(POPUP_W, 100)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(s)
        s:StartMoving()
    end)
    dialog:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
    end)

    local backdrop = dialog:CreateTexture(nil, "BACKGROUND", nil, 0)
    backdrop:SetAllPoints()
    backdrop:SetTexture("Interface\\AddOns\\CludesUI\\media\\modern_blizz.png")
    backdrop:SetTexCoord(0.25, 1, 0, 0.75)
    local overlayFrame = dialog:CreateTexture(nil, "BACKGROUND", nil, 1)
    overlayFrame:SetAllPoints()
    overlayFrame:SetColorTexture(0, 0, 0, 0.55)

    if Pix and Pix.CreateBorder then
        Pix.CreateBorder(dialog, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)
    end

    local hdrBg = MakeSolid(dialog, "BORDER", 0, 0, 0, 0.25)
    hdrBg:SetPoint("TOPLEFT", 1, -1)
    hdrBg:SetPoint("TOPRIGHT", -1, 0)
    hdrBg:SetHeight(TITLE_H)

    local title = MakeLabel(dialog, 11, "OUTLINE", 1, 1, 1, 1)
    title:SetPoint("TOPLEFT", PAD, -8)
    title:SetText("CludesUI Keystones")

    local ICON_SZ = 14
    local ICON_ALPHA = 0.5

    local xBtn = CreateFrame("Button", nil, dialog)
    xBtn:SetSize(ICON_SZ, ICON_SZ)
    xBtn:SetPoint("RIGHT", hdrBg, "RIGHT", -8, 0)
    local xTex = xBtn:CreateTexture(nil, "ARTWORK")
    xTex:SetAllPoints()
    xTex:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png")
    xTex:SetAlpha(ICON_ALPHA)
    xBtn:SetScript("OnEnter", function()
        xTex:SetAlpha(1)
    end)
    xBtn:SetScript("OnLeave", function()
        xTex:SetAlpha(ICON_ALPHA)
    end)
    xBtn:SetScript("OnClick", function()
        dialog:Hide()
    end)

    -- Refresh button
    local refBtn = CreateFrame("Button", nil, dialog)
    refBtn:SetSize(ICON_SZ, ICON_SZ)
    refBtn:SetPoint("RIGHT", xBtn, "LEFT", -6, 0)
    local refTex = refBtn:CreateTexture(nil, "ARTWORK")
    refTex:SetAllPoints()
    refTex:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\unlock-reset.png")
    refTex:SetAlpha(ICON_ALPHA)
    refBtn:SetScript("OnEnter", function()
        refTex:SetAlpha(1)
        CUI.ShowWidgetTooltip(refBtn, "Refresh Data")
    end)
    refBtn:SetScript("OnLeave", function()
        refTex:SetAlpha(ICON_ALPHA)
        CUI.HideWidgetTooltip()
    end)
    local refLocked = false
    refBtn:SetScript("OnClick", function()
        if refLocked then
            return
        end
        refLocked = true
        refBtn:EnableMouse(false)
        refTex:SetAlpha(0.15)
        StoreOwnKey()
        if IsInGroup() then
            QueryPartyKeys()
        end
        ShowKeystonePopup()
        if IsInGroup() then
            C_Timer.After(1.0, ShowKeystonePopup)
        end
        C_Timer.After(2, function()
            refLocked = false
            refBtn:EnableMouse(true)
            refTex:SetAlpha(ICON_ALPHA)
        end)
    end)

    if CUI and CUI.RegisterEscapeClose then
        CUI.RegisterEscapeClose(dialog)
    end

    -- Scroll frame for content
    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog)
    scrollFrame:SetPoint("TOPLEFT", PAD, -(TITLE_H + 8))
    scrollFrame:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local childFrame = self:GetScrollChild()
        local maxS = math.max(0, (childFrame and childFrame:GetHeight() or 0) - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxS, current - delta * 20)))
    end)
    dialog._body = CreateFrame("Frame", nil, scrollFrame)
    dialog._body:SetWidth(POPUP_W - PAD * 2)
    dialog._body:SetHeight(1)
    scrollFrame:SetScrollChild(dialog._body)
    dialog._sf = scrollFrame

    -- Apply saved scale
    local conf = CludesUIDB and CludesUIDB.keystonePopup
    dialog:SetScale(conf and conf.scale or 1.05)

    dialog:Hide()
    return dialog
end

local function AcquireRow(index)
    if rowFrames[index] then
        return rowFrames[index]
    end
    local p = MakePopup()
    local region = CreateFrame("Frame", nil, p._body)
    region:SetHeight(ROW_H)

    if index % 2 == 0 then
        local alt = MakeSolid(region, "BACKGROUND", 0, 0, 0, 0.15)
        alt:SetAllPoints()
    end

    region._nameFS = MakeLabel(region, 11, nil, 1, 1, 1, 0.85, true)
    region._nameFS:SetPoint("LEFT", 2, 0)
    region._nameFS:SetWidth(80)
    region._nameFS:SetJustifyH("LEFT")
    region._nameFS:SetWordWrap(false)

    region._ratingFS = MakeLabel(region, 10, nil, 0.6, 0.6, 0.6, 1)
    region._ratingFS:SetPoint("LEFT", region._nameFS, "RIGHT", 4, 0)
    region._ratingFS:SetWidth(40)
    region._ratingFS:SetJustifyH("LEFT")

    region._dungeonFS = MakeLabel(region, 11, nil, 0.7, 0.7, 0.7, 1)
    region._dungeonFS:SetPoint("LEFT", region._ratingFS, "RIGHT", 4, 0)
    region._dungeonFS:SetWidth(130)
    region._dungeonFS:SetJustifyH("LEFT")
    region._dungeonFS:SetWordWrap(false)

    -- Teleport button overlaying the dungeon name
    local tpBtn = CreateFrame("Button", nil, region, "InsecureActionButtonTemplate")
    tpBtn:SetPoint("TOPLEFT", region._dungeonFS, "TOPLEFT", 0, 0)
    tpBtn:SetPoint("BOTTOMLEFT", region._dungeonFS, "BOTTOMLEFT", 0, 0)
    tpBtn:SetWidth(130)
    tpBtn:SetFrameLevel(region:GetFrameLevel() + 5)
    tpBtn:RegisterForClicks("AnyUp", "AnyDown")
    tpBtn:SetAttribute("type", "spell")
    local ACC = CludesUI.CLUDES_GREEN
    tpBtn:SetScript("OnEnter", function()
        local spellRef = tpBtn._spellID
        if not spellRef then
            return
        end
        local known = IsPlayerSpell(spellRef)
        if known then
            if ACC then
                region._dungeonFS:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
            end
            local cdInfo = C_Spell.GetSpellCooldown(spellRef)
            if cdInfo and cdInfo.duration and cdInfo.duration > 0 then
                CludesUI.ShowWidgetTooltip(tpBtn, "Portal on Cooldown")
            end
        end
    end)
    tpBtn:SetScript("OnLeave", function()
        region._dungeonFS:SetTextColor(0.7, 0.7, 0.7, 1)
        CludesUI.HideWidgetTooltip()
    end)
    tpBtn:Hide()
    region._tpBtn = tpBtn

    region._levelFS = MakeLabel(region, 11, "OUTLINE", 1, 1, 1, 1)
    region._levelFS:SetPoint("RIGHT", -2, 0)
    region._levelFS:SetJustifyH("RIGHT")

    local sep = region:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.10)
    if Pix and Pix.DisablePixelSnap then
        Pix.DisablePixelSnap(sep)
    end
    sep:SetHeight((Pix and Pix.mult) or 1)
    local gapMid = -math.floor(ROW_GAP / 2)
    sep:SetPoint("BOTTOMLEFT", 0, gapMid)
    sep:SetPoint("BOTTOMRIGHT", 0, gapMid)

    rowFrames[index] = region
    return region
end

-- Section header pool
local secHeaders = {}
local function AcquireSecHeader(index)
    if secHeaders[index] then
        return secHeaders[index]
    end
    local p = MakePopup()
    local hgt = CreateFrame("Frame", nil, p._body)
    hgt:SetHeight(HDR_H)
    hgt._label = MakeLabel(hgt, 10, "OUTLINE", 1, 1, 1, 0.56)
    hgt._label:SetPoint("LEFT", 0, 0)
    hgt._label:SetJustifyH("LEFT")
    secHeaders[index] = hgt
    return hgt
end

local function GetTextSize()
    local conf = CludesUIDB and CludesUIDB.keystonePopup
    return conf and conf.textSize or 11
end

local function ApplyRowFontSize(region)
    local sz = GetTextSize()
    local font = ResolveFont()
    local flags = ResolveOutline()
    CludesUI.SetFontFamily(region._nameFS, font, sz, flags, flags == "")
    region._ratingFS:SetFont(font, sz - 1, flags)
    region._dungeonFS:SetFont(font, sz, flags)
    region._levelFS:SetFont(font, sz, flags)
end

local function PopulateRow(region, e, ccMap)
    ApplyRowFontSize(region)
    region._nameFS:SetText(StripRealm(e.name))
    region._nameFS:SetWidth(80)
    -- Cheap paths first: the entry's own classFile, then the per-rebuild map
    local castFrame = e.classFile
    if not castFrame and ccMap then
        castFrame = ccMap[StripRealm(e.name)]
    end
    local cc = castFrame and RAID_CLASS_COLORS[castFrame]
    if cc then
        region._nameFS:SetTextColor(cc.r, cc.g, cc.b, 1)
    else
        region._nameFS:SetTextColor(1, 1, 1, 0.85)
    end
    region._ratingFS:SetText(e.rating and e.rating > 0 and tostring(e.rating) or "")
    if e.dungeonName then
        region._dungeonFS:SetText(e.dungeonName)
        region._dungeonFS:SetTextColor(0.7, 0.7, 0.7, 1)
        region._levelFS:SetText("+" .. e.lvl)
        if e.lvl >= 12 then
            region._levelFS:SetTextColor(1, 0.5, 0, 1)
        elseif e.lvl >= 10 then
            region._levelFS:SetTextColor(0.63, 0.2, 0.93, 1)
        elseif e.lvl >= 7 then
            region._levelFS:SetTextColor(0, 0.44, 0.87, 1)
        elseif e.lvl >= 4 then
            region._levelFS:SetTextColor(0.12, 1, 0, 1)
        else
            region._levelFS:SetTextColor(1, 1, 1, 1)
        end
        -- Teleport button
        local spellId = e.mapID and MAP_TELEPORT_SPELLS[e.mapID]
        if spellId and region._tpBtn then
            region._tpBtn._spellID = spellId
            region._tpBtn:SetAttribute("spell", spellId)
            region._tpBtn:Show()
        elseif region._tpBtn then
            region._tpBtn._spellID = nil
            region._tpBtn:Hide()
        end
    else
        region._dungeonFS:SetText("No keystone")
        region._dungeonFS:SetTextColor(0.5, 0.5, 0.5, 0.7)
        region._levelFS:SetText("")
        if region._tpBtn then
            region._tpBtn:Hide()
        end
    end
end

ShowKeystonePopup = function()
    StoreOwnKey()
    if not next(MAP_TELEPORT_SPELLS) then
        RebuildTeleportTables()
    end
    local p = MakePopup()
    local body = p._body
    local contentW = POPUP_W - PAD * 2

    -- Collect party keys (only current group members)
    local currentMembers = {}
    currentMembers[PlayerName("player")] = true
    if IsInGroup() then
        local prefixText = IsInRaid() and "raid" or "party"
        local count = GetNumGroupMembers()
        for index = 1, (IsInRaid() and count or count - 1) do
            local name = PlayerName(prefixText .. index)
            if name then
                currentMembers[name] = true
            end
        end
    end
    local partyEntries = {}
    for name, details in pairs(partyKeys) do
        if currentMembers[name] or currentMembers[StripRealm(name)] then
            local dName = DungeonNameFromMap(details.dungeon)
            partyEntries[#partyEntries + 1] = {
                name = name,
                dungeonName = dName,
                lvl = details.keyLevel or 0,
                rating = details.rating or 0,
                classFile = details.classFile,
                mapID = details.dungeon,
            }
        end
    end
    table.sort(partyEntries, function(lhs, rhs)
        if lhs.lvl ~= rhs.lvl then
            return lhs.lvl > rhs.lvl
        end
        return lhs.name < rhs.name
    end)

    -- Collect guild keys (exclude ourselves)
    local guildEntries = {}
    local myName = PlayerName("player")
    for name, details in pairs(guildKeys) do
        if name ~= myName and StripRealm(name) ~= StripRealm(myName) and (details.keyLevel or 0) > 0 then
            local dName = DungeonNameFromMap(details.dungeon)
            guildEntries[#guildEntries + 1] = {
                name = name,
                dungeonName = dName,
                lvl = details.keyLevel,
                rating = details.rating or 0,
                classFile = details.classFile,
                mapID = details.dungeon,
            }
        end
    end
    table.sort(guildEntries, function(lhs, rhs)
        if lhs.lvl ~= rhs.lvl then
            return lhs.lvl > rhs.lvl
        end
        return lhs.name < rhs.name
    end)

    -- One class-color pass for the whole rebuild, and only when some entry
    -- actually lacks a stored classFile (guild data arrives without one)
    local ccMap
    do
        local needMap = false
        for _, entry in ipairs(partyEntries) do
            if not entry.classFile then
                needMap = true
                break
            end
        end
        if not needMap then
            for _, entry in ipairs(guildEntries) do
                if not entry.classFile then
                    needMap = true
                    break
                end
            end
        end
        if needMap then
            ccMap = BuildClassColorMap()
        end
    end

    -- Hide all pooled frames
    for index = 1, #rowFrames do
        rowFrames[index]:Hide()
    end
    for index = 1, #secHeaders do
        secHeaders[index]:Hide()
    end

    local curY = 0
    local rowIdx = 0
    local hdrIdx = 0

    -- Party section
    hdrIdx = hdrIdx + 1
    local partyHdr = AcquireSecHeader(hdrIdx)
    partyHdr._label:SetText("PARTY")
    partyHdr:ClearAllPoints()
    partyHdr:SetPoint("TOPLEFT", body, "TOPLEFT", 0, curY)
    partyHdr:SetWidth(contentW)
    partyHdr:Show()
    curY = curY - HDR_H - HDR_GAP

    if #partyEntries == 0 then
        rowIdx = rowIdx + 1
        local row = AcquireRow(rowIdx)
        row._nameFS:SetText("No keystones found")
        row._nameFS:SetWidth(contentW)
        row._nameFS:SetTextColor(0.5, 0.5, 0.5, 0.7)
        row._ratingFS:SetText("")
        row._dungeonFS:SetText("")
        row._levelFS:SetText("")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, curY)
        row:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, curY)
        row:Show()
        curY = curY - ROW_H
    else
        for _, entry in ipairs(partyEntries) do
            rowIdx = rowIdx + 1
            local row = AcquireRow(rowIdx)
            PopulateRow(row, entry, ccMap)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, curY)
            row:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, curY)
            row:Show()
            curY = curY - (ROW_H + ROW_GAP)
        end
        curY = curY + ROW_GAP -- remove trailing gap
    end

    -- Guild section
    curY = curY - SEC_GAP
    hdrIdx = hdrIdx + 1
    local guildHdr = AcquireSecHeader(hdrIdx)
    guildHdr._label:SetText("GUILD")
    guildHdr:ClearAllPoints()
    guildHdr:SetPoint("TOPLEFT", body, "TOPLEFT", 0, curY)
    guildHdr:SetWidth(contentW)
    guildHdr:Show()
    curY = curY - HDR_H - HDR_GAP

    if #guildEntries == 0 then
        rowIdx = rowIdx + 1
        local row = AcquireRow(rowIdx)
        row._nameFS:SetText("Waiting for data...")
        row._nameFS:SetWidth(contentW)
        row._nameFS:SetTextColor(0.5, 0.5, 0.5, 0.5)
        row._ratingFS:SetText("")
        row._dungeonFS:SetText("")
        row._levelFS:SetText("")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, curY)
        row:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, curY)
        row:Show()
        curY = curY - ROW_H
    else
        for _, entry in ipairs(guildEntries) do
            rowIdx = rowIdx + 1
            local row = AcquireRow(rowIdx)
            PopulateRow(row, entry, ccMap)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, curY)
            row:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, curY)
            row:Show()
            curY = curY - (ROW_H + ROW_GAP)
        end
        curY = curY + ROW_GAP
    end

    -- Set scroll child height
    local totalH = math.abs(curY)
    body:SetHeight(totalH)

    -- Size popup: content capped at MAX_CONTENT_H, scrollable beyond that
    local visH = math.min(totalH, MAX_CONTENT_H)
    p:SetHeight(TITLE_H + 8 + visH + PAD)

    p:Show()
end

-- Debounced: incoming keystone data can arrive as a burst (a /keys request
-- solicits a reply from every online guild member running the lib), and each
-- rebuild re-lays-out every row. Coalesce bursts into one rebuild per 0.2s.
local refreshQueued = false
local function RefreshPopupIfOpen()
    if not (dialog and dialog:IsShown()) then
        return
    end
    if refreshQueued then
        return
    end
    refreshQueued = true
    C_Timer.After(0.2, function()
        refreshQueued = false
        if dialog and dialog:IsShown() then
            ShowKeystonePopup()
        end
    end)
end
_G._CUI_RefreshKeystonePopup = RefreshPopupIfOpen

-------------------------------------------------------------------------------
--  LibKeystone callback
--  Receives keystone data from any player running BigWigs/DBM (or any addon
--  that embeds LibKeystone). No manual comm handling needed.
-------------------------------------------------------------------------------
-- Registered only when the popup feature is enabled: the toggle is
-- reload-gated (see options), so the load-time flag is authoritative and a
-- disabled popup pays nothing per incoming keystone message.
local lksCallbackTable = {}
do
    local conf = CludesUIDB and CludesUIDB.keystonePopup
    local enabled = not conf or conf.enabled ~= false
    if LibKeystone and enabled then
        LibKeystone.Register(lksCallbackTable, function(keyLevel, keyMapID, playerRating, playerName, channel)
            if not playerName then
                return
            end
            local list = (channel == "GUILD") and guildKeys or partyKeys
            list[playerName] = { dungeon = keyMapID, keyLevel = keyLevel, rating = playerRating }
            RefreshPopupIfOpen()
        end)
    end
end

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
do
    local conf = CludesUIDB and CludesUIDB.keystonePopup
    local enabled = not conf or conf.enabled ~= false

    SLASH_CUIKEYS1 = "/keys"
    SLASH_CUIKEYS2 = "/ckeys"
    if enabled then
        SLASH_CUIKEYS3 = "/key"
    end

    SlashCmdList["CUIKEYS"] = function()
        if not enabled then
            return
        end
        StoreOwnKey()
        QueryPartyKeys()
        ShowKeystonePopup()
        C_Timer.After(1.0, ShowKeystonePopup)
    end
end
