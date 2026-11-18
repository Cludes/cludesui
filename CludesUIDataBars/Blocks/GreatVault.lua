if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if CludesUI.IS_FOREVER then
    return
end -- no Great Vault on WoW Forever (the main file drops the block type there too)
-------------------------------------------------------------------------------
--  Blocks\GreatVault.lua - Info Bar block: the Great Vault and keystones.
--
--  The block is an icon and "Great Vault"; a click opens the vault. Hover
--  shows the week's three reward rows (raids, Mythic+, world: done, partial
--  or empty, as the minimap's vault tooltip colours them), the player's own
--  keystone and the party's.
--
--  The rewards are read when the tooltip opens, so the block listens to no
--  vault events. Party keystones come from LibKeystone (packaged in, absent
--  from a source checkout: then that section just never shows): a request
--  asks the group, replies arrive about a second later and repaint the open
--  tooltip in place. Replies are kept only for current group members.
-------------------------------------------------------------------------------
local _, mod = ...
local L = mod.L
local K = mod.BlockKit

local format, floor, max, min = string.format, math.floor, math.max, math.min

local Threshold = Enum and Enum.WeeklyRewardChestThresholdType
local RAID = Threshold and Threshold.Raid or 3
local MPLUS = Threshold and Threshold.Activities or 1
local WORLD = Threshold and Threshold.World or 6

local STATE_COLOR = {
    done = { 0.176, 0.796, 0.349 },
    partial = { 0.812, 0.592, 0.212 },
    empty = { 0.58, 0.58, 0.58 },
}

local function ByIndex(a, b)
    local ai, bi = (a and a.index) or 0, (b and b.index) or 0
    if ai == bi then
        return ((a and a.threshold) or 0) < ((b and b.threshold) or 0)
    end
    return ai < bi
end

-- Reused: both are used up before the next row is built (the tooltip copies).
local sorted = {}
local cells = { "", "", "" }

-- One reward row as three coloured cells, which the tooltip lines up in columns.
local function RewardCells(kind, isRaid)
    local list = C_WeeklyRewards and C_WeeklyRewards.GetActivities and C_WeeklyRewards.GetActivities(kind)
    if type(list) ~= "table" or #list == 0 then
        list = nil
    else
        wipe(sorted)
        for i = 1, #list do
            sorted[i] = list[i]
        end
        table.sort(sorted, ByIndex)
        list = sorted
    end
    for i = 1, 3 do
        local a = list and list[i]
        local text, state = "-", "empty"
        if a then
            local progress = max(0, tonumber(a.progress) or 0)
            local need = max(0, tonumber(a.threshold) or 0)
            local level = max(0, tonumber(a.level) or 0)
            if need > 0 then
                text = format("%d/%d", progress, need)
                if progress >= need then
                    state = "done"
                    -- A finished Mythic+ or world slot shows the level it earned
                    -- (raids have none, so they keep the count).
                    if not isRaid and level > 0 then
                        text = "+" .. level
                    end
                elseif progress > 0 then
                    state = "partial"
                end
            end
        end
        local c = STATE_COLOR[state]
        cells[i] = CludesUI.HexColor(c[1], c[2], c[3]) .. text .. "|r"
    end
    return cells
end

local function Dungeon(mapID)
    if not mapID or mapID == 0 then
        return nil
    end
    return C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and (C_ChallengeMode.GetMapUIInfo(mapID)) or nil
end

-- The player's own keystone: dungeon name and level, or nil.
local function MyKeystone()
    local mp = C_MythicPlus
    if not mp then
        return nil
    end
    local mapID = mp.GetOwnedKeystoneChallengeMapID and mp.GetOwnedKeystoneChallengeMapID()
    local level = mp.GetOwnedKeystoneLevel and mp.GetOwnedKeystoneLevel()
    if not mapID or not level or level <= 0 then
        return nil
    end
    local name = Dungeon(mapID)
    if name then
        return name, level
    end
end

local function ShortName(name)
    return name and (name:match("^([^-]+)") or name)
end

-------------------------------------------------------------------------------
--  Party keystones
-------------------------------------------------------------------------------
local keys = {} -- ["Name-Realm"] = { mapID, level }
local token = {} -- our LibKeystone registration
local listening = false
local lastAsked = 0
local ASK_EVERY = 5 -- seconds; a filling group sends roster updates in bursts
local ASK_EVERY_EMPTY = 1 -- when the tooltip has nothing to show for this group

local function Lib()
    return LibStub and LibStub("LibKeystone", true)
end

-- The open tooltip, so a late reply repaints it where it is. A burst of
-- replies repaints once.
local openOwner, openPaint
local repaintQueued = false
local function RepaintSoon()
    if not openPaint or repaintQueued then
        return
    end
    repaintQueued = true
    C_Timer.After(0.2, function()
        repaintQueued = false
        if openPaint and openOwner and mod.Tip_IsOwned(openOwner) then
            openPaint()
        end
    end)
end

-- The units to check (the player's own key has its own row), and how many.
local function Roster()
    if IsInRaid() then
        return "raid", GetNumGroupMembers()
    end
    return "party", GetNumGroupMembers() - 1
end

-- Whether a player (by short name, however the library spells it) is in the group.
local function InGroup(name)
    if not IsInGroup() then
        return false
    end
    local short = ShortName(name)
    if not short then
        return false
    end
    local unit, count = Roster()
    for i = 1, count do
        if ShortName(GetUnitName(unit .. i, true)) == short then
            return true
        end
    end
    return false
end

-- Listens for keystone replies (from the first enabled block on, so a user
-- without one pays nothing). Kept by group membership, not by channel: a
-- groupmate who is also a guildmate can reply on GUILD.
local function Listen()
    if listening then
        return
    end
    local lib = Lib()
    if not lib then
        return
    end
    listening = true
    lib.Register(token, function(level, mapID, _, name)
        if not name or not InGroup(name) then
            return
        end
        local entry = keys[name]
        if entry then
            entry.mapID, entry.level = mapID, level
        else
            keys[name] = { mapID = mapID, level = level }
        end
        RepaintSoon()
    end)
end

-- Asks the group for keystones (silently, on the addon channel). Only in a
-- party of the player's own (a Dungeon Finder group answers PARTY with an
-- error). emptyHanded: the tooltip had nothing for this group, so only a
-- short wait applies (a new member may have missed the last request).
local function Ask(emptyHanded)
    local lib = Lib()
    if not lib or not IsInGroup(LE_PARTY_CATEGORY_HOME) then
        return
    end
    local now = GetTime()
    if now - lastAsked < (emptyHanded and ASK_EVERY_EMPTY or ASK_EVERY) then
        return
    end
    lastAsked = now
    lib.Request("PARTY")
end

-- Drops players no longer in the group (never one still here). A roster
-- update can arrive before the units resolve; then nothing is dropped.
local function Prune()
    if not next(keys) then
        return
    end
    if not IsInGroup() then
        wipe(keys)
        return
    end
    local unit, count = Roster()
    local resolved = false
    for i = 1, count do
        if GetUnitName(unit .. i, true) then
            resolved = true
            break
        end
    end
    if not resolved then
        return
    end
    for name in pairs(keys) do
        if not InGroup(name) then
            keys[name] = nil
        end
    end
end

-- The group's keystones as rows, highest level first (then by name). Reused
-- tables: the sort swaps references, so they survive to be refilled.
local rows, rowCount, byShort = {}, 0, {}

local function AddRow(name, dungeon, level, region, g, b)
    rowCount = rowCount + 1
    local row = rows[rowCount]
    if not row then
        row = {}
        rows[rowCount] = row
    end
    row.name, row.dungeon, row.level, row.r, row.g, row.b = name, dungeon, level, region, g, b
end

local function Before(a, b)
    if a.level ~= b.level then
        return a.level > b.level
    end
    return a.name < b.name
end

-- The library reports "Name-Realm", the roster a bare name for same-realm
-- members: the exact name first, the short one as a fallback. Two members
-- sharing a short name are skipped (better none than the wrong key).
local function PartyRows()
    rowCount = 0
    if not IsInGroup() then
        return 0
    end
    wipe(byShort)
    local any = false
    for name, entry in pairs(keys) do
        if entry and (entry.level or 0) > 0 then
            local short = ShortName(name)
            if short then
                byShort[short] = byShort[short] == nil and entry or false
                any = true
            end
        end
    end
    if not any then
        return 0
    end
    local unit, count = Roster()
    for i = 1, count do
        local u = unit .. i
        if UnitExists(u) and not UnitIsUnit(u, "player") then
            local full = GetUnitName(u, true)
            local entry = keys[full]
            if not (entry and (entry.level or 0) > 0) then
                entry = byShort[ShortName(full)] or nil
            end
            local dungeon = entry and Dungeon(entry.mapID)
            if dungeon then
                local _, class = UnitClass(u)
                local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                AddRow(
                    GetUnitName(u) or u,
                    dungeon,
                    entry.level,
                    c and c.r or 1,
                    c and c.g or 1,
                    c and c.b or 1
                )
            end
        end
    end
    -- Insertion sort: a handful of rows, no garbage.
    for i = 2, rowCount do
        local j = i
        while j > 1 and Before(rows[j], rows[j - 1]) do
            rows[j], rows[j - 1] = rows[j - 1], rows[j]
            j = j - 1
        end
    end
    return rowCount
end

-------------------------------------------------------------------------------
--  The block
-------------------------------------------------------------------------------
mod.BlockFactories.greatvault = function(blockCfg, slot, contentFrame, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    -- The block never changes with the roster: these only tidy the keystone
    -- list and keep it fresh for the next hover.
    inst.events = { "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }

    local button = CreateFrame("Button", nil, contentFrame)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")
    local iconTex = button:CreateTexture(nil, "OVERLAY")
    K.SetBlockIcon(iconTex, blockCfg)
    local label = button:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, label)

    local hovered = false

    -- Text and icon colours (both the accent on hover).
    local function Paint()
        if hovered then
            local region, g, b = mod.GetAccent()
            label:SetTextColor(region, g, b, 1)
            iconTex:SetVertexColor(region, g, b, 1)
        else
            local region, g, b = K.BlockColorOf(blockCfg)
            label:SetTextColor(region, g, b, 1)
            local ir, ig, ib = K.IconColorOf(blockCfg)
            iconTex:SetVertexColor(ir, ig, ib, 1)
        end
    end

    function inst:Refresh()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        local iconSize = fontSize + 4
        -- The core translator: these words share entries with the minimap's vault tooltip.
        local text = CludesUI.L("Great Vault")
        mod.SetFont(label, fontSize, barCtx.cfg)
        iconTex:SetSize(iconSize, iconSize)
        iconTex:ClearAllPoints()
        if barCtx.IsVertical() then
            local slotW = K.VSlotW(self)
            label:SetText(text)
            iconTex:SetPoint("TOP", button, "TOP", 0, -4)
            mod.SetWrappedText(label, max(24, slotW - 8), "CENTER")
            label:ClearAllPoints()
            label:SetPoint("TOP", iconTex, "BOTTOM", 0, -2)
            local height = max(8 + iconSize + 2 + mod.SnapToPixelGrid(label:GetStringHeight()) + 4, barH)
            contentFrame:SetSize(slotW, height)
            button:SetSize(slotW, height)
        else
            local budget = K.HBudget(self, 120)
            mod.ResetInlineText(label, "LEFT")
            label:SetText(text)
            iconTex:SetPoint("LEFT", button, "LEFT", 0, 0)
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", iconSize + K.ICON_GAP, 0)
            local width = min(budget, iconSize + K.ICON_GAP + mod.SnapToPixelGrid(label:GetStringWidth()) + 4)
            contentFrame:SetSize(max(width, 10), barH)
            button:SetSize(max(width, 10), barH)
        end
        Paint()
        K.MaybeRelayout(self)
    end

    -- Returns how many party rows it showed.
    local function ShowTooltip()
        local region, g, b = mod.GetAccent()
        mod.Tip_Begin(button)
        mod.Tip_AddLine("|cFFFFFFFF[|r" .. CludesUI.L("Great Vault") .. "|cFFFFFFFF]|r", region, g, b)
        mod.Tip_AddLine(" ")
        mod.Tip_AddColumns(CludesUI.L("Raids"), RewardCells(RAID, true), 0.8, 0.8, 0.8)
        mod.Tip_AddColumns(CludesUI.L("Mythic+"), RewardCells(MPLUS, false), 0.8, 0.8, 0.8)
        mod.Tip_AddColumns(CludesUI.L("World"), RewardCells(WORLD, false), 0.8, 0.8, 0.8)
        local dungeon, level = MyKeystone()
        if dungeon then
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(CludesUI.L("Your Keystone"), region, g, b)
            mod.Tip_AddDouble(dungeon, "+" .. level, 0.8, 0.8, 0.8, 1, 1, 1)
        end
        local count = PartyRows()
        if count > 0 then
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(CludesUI.L("Party Keystones"), region, g, b)
            for i = 1, count do
                local row = rows[i]
                local right = row.dungeon .. " |cffffffff+" .. row.level .. "|r"
                mod.Tip_AddDouble(row.name, right, row.r, row.g, row.b, 0.6, 0.6, 0.6)
            end
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["LEFT_CLICK"], CludesUI.L("Open Great Vault"), 1, 1, 1, region, g, b)
        mod.Tip_Show()
        return count
    end

    -- Hover recolours (nothing moves), shows what is known, then asks the
    -- group: a member can get a new key without the group changing.
    button:SetScript("OnEnter", function()
        hovered = true
        Paint()
        local shown = ShowTooltip()
        openOwner, openPaint = button, ShowTooltip
        Ask(shown == 0)
    end)
    button:SetScript("OnLeave", function()
        hovered = false
        openOwner, openPaint = nil, nil
        mod.Tip_Hide(button)
        Paint()
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            CludesUI.ToggleGreatVault()
        end
    end)

    inst.eventFrame = K.MakeEventFrame(inst, function()
        Prune()
        Ask()
    end)

    -- A bar rebuild can remove the block with its tooltip open (no OnLeave);
    -- the open-tooltip reference would then keep this block alive.
    local function ForgetTooltip()
        if openOwner == button then
            openOwner, openPaint = nil, nil
        end
    end

    function inst:Enable()
        contentFrame:Show()
        Listen()
        K.RegisterInstEvents(self)
        Ask()
    end

    function inst:Disable()
        ForgetTooltip()
        K.UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 30)
        end
        return max(contentFrame:GetWidth() or 60, 24)
    end

    function inst:Destroy()
        self._dead = true
        ForgetTooltip()
        contentFrame:Hide()
    end

    return inst
end
