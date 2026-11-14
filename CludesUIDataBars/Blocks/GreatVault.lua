if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if CludesUI.IS_FOREVER then
    return
end -- no Great Vault on WoW Forever: no factory, no keystone feed (the main file drops the block from BLOCK_TYPES too)
-- Blocks\GreatVault.lua
-- Great Vault block factory.

local ADDON_NAME, mod = ...
local L = mod.L
local K = mod.BlockKit

-- Upvalues
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local GetTime = GetTime
local pairs = pairs
local type = type
local wipe = wipe
local format = string.format
local tsort = table.sort
local floor = math.floor
local max = math.max
local min = math.min

local ICON_GAP = K.ICON_GAP
local CONTENT_BASE = K.CONTENT_BASE
local InstKey = K.InstKey
local MakeEventFrame = K.MakeEventFrame
local RegisterInstEvents = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local HBudget = K.HBudget
local VSlotW = K.VSlotW
local MaybeRelayout = K.MaybeRelayout
local AttachTextOffset = K.AttachTextOffset
local BlockColorOf = K.BlockColorOf
local IconColorOf = K.IconColorOf

-------------------------------------------------------------------------------
--  GREAT VAULT (weekly reward progress + owned / party keystones)
--
--  The three reward rows mirror the minimap's vault tooltip (same activity types,
--  thresholds, done/partial/empty colors); reward data is read live when the
--  tooltip opens, so this block registers NO vault events.
--
--  Party keystones are the only async part, riding LibKeystone (injected at package
--  time via .pkgmeta, absent from a source checkout -- missing, the party section
--  just never renders, same as for group members whose client broadcasts nothing).
-------------------------------------------------------------------------------
local GV_RAID = (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Raid)
    or 3
local GV_MPLUS = (
    Enum
    and Enum.WeeklyRewardChestThresholdType
    and Enum.WeeklyRewardChestThresholdType.Activities
) or 1
local GV_WORLD = (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.World)
    or 6

local function GVTokenColor(status)
    if status == "done" then
        return 0.176, 0.796, 0.349
    end
    if status == "partial" then
        return 0.812, 0.592, 0.212
    end
    return 0.58, 0.58, 0.58
end

local function GVColorize(textValue, r, g, b)
    return format("%s%s|r", CludesUI.HexColor(r, g, b), textValue)
end

local function GVSortActivities(a, b)
    local ai = (a and a.index) or 0
    local bi = (b and b.index) or 0
    if ai == bi then
        return ((a and a.threshold) or 0) < ((b and b.threshold) or 0)
    end
    return ai < bi
end

-- Both buffers are consumed before the next call in the same row build.
local _gvSortBuf = {}
local _gvTokenBuf = { "", "", "" }

-- One reward row as three tokens, each carrying its own state color inline. Tip_AddColumns
-- lays them out in pixel-aligned sub-columns so the three rows line up vertically; the shared buffer is safe because it copies.
local function GVRowTokens(activityType, isRaid)
    local acts
    if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
        acts = C_WeeklyRewards.GetActivities(activityType)
    end
    if type(acts) ~= "table" or #acts == 0 then
        acts = nil
    else
        wipe(_gvSortBuf)
        for idx = 1, #acts do
            _gvSortBuf[idx] = acts[idx]
        end
        tsort(_gvSortBuf, GVSortActivities)
        acts = _gvSortBuf
    end

    for idx = 1, 3 do
        local details = acts and acts[idx]
        local textValue, status = "-", "empty"
        if details then
            local progress = max(0, tonumber(details.progress) or 0)
            local threshold = max(0, tonumber(details.threshold) or 0)
            local level = max(0, tonumber(details.level) or 0)
            if threshold > 0 then
                if progress >= threshold then
                    status = "done"
                    -- A cleared M+ / world slot reports the reward level it earned; raids have no such level and keep the count.
                    if not isRaid and level > 0 then
                        textValue = "+" .. level
                    else
                        textValue = format("%d/%d", progress, threshold)
                    end
                else
                    textValue = format("%d/%d", progress, threshold)
                    if progress > 0 then
                        status = "partial"
                    end
                end
            end
        end
        _gvTokenBuf[idx] = GVColorize(textValue, GVTokenColor(status))
    end
    return _gvTokenBuf
end

local function GVDungeonName(mapID)
    if not mapID or mapID == 0 then
        return nil
    end
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        return (C_ChallengeMode.GetMapUIInfo(mapID))
    end
    return nil
end

local function GVOwnedKeystone()
    if not C_MythicPlus then
        return nil
    end
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID
        and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
    if not mapID or not level or level <= 0 then
        return nil
    end
    local name = GVDungeonName(mapID)
    if not name then
        return nil
    end
    return name, level
end

local function GVShortName(name)
    if not name then
        return nil
    end
    return name:match("^([^-]+)") or name
end

-- Keystone feed: registered on the first Enable of a Great Vault block, so a user without one pays nothing per incoming keystone message.
local _gvKeys = {} -- ["Name-Realm"] = { mapID = n, level = n }
local _gvLibToken = {}
local _gvRegistered = false
local _gvLastRequest = 0

local function GVLib()
    return LibStub and LibStub("LibKeystone", true)
end

-- The open tooltip, so a reply landing a second after the hover can repaint it in place instead of waiting for the next hover.
local _gvOpenBtn, _gvOpenFn
local _gvRepaintQueued = false

-- Debounced like the QoL keystone popup: a request solicits a reply from every group member, and each rebuild re-lays-out the whole tooltip.
local function GVRepaintOpenTooltip()
    if not _gvOpenFn or _gvRepaintQueued then
        return
    end
    _gvRepaintQueued = true
    C_Timer.After(0.2, function()
        _gvRepaintQueued = false
        if _gvOpenFn and _gvOpenBtn and mod.Tip_IsOwned(_gvOpenBtn) then
            _gvOpenFn()
        end
    end)
end

local GVInGroup -- forward declaration; defined below with the roster helpers

local function GVEnsureKeystoneFeed()
    if _gvRegistered then
        return
    end
    local lib = GVLib()
    if not lib then
        return
    end
    _gvRegistered = true
    -- Filtered on group membership, NOT the delivery channel: a group member who is
    -- also a guildmate can have their reply arrive tagged GUILD, and dropping it
    -- blanks their row. Membership is still required so a guild-wide reply burst cannot flood the cache with unshowable players.
    lib.Register(_gvLibToken, function(keyLevel, keyMapID, _, playerName)
        if not playerName or not GVInGroup(playerName) then
            return
        end
        local e = _gvKeys[playerName]
        if e then
            e.mapID, e.level = keyMapID, keyLevel
        else
            _gvKeys[playerName] = { mapID = keyMapID, level = keyLevel }
        end
        GVRepaintOpenTooltip()
    end)
end

-- Polls the group over LibKeystone. Silent: an addon-channel request, and QoL's keystone
-- popup ignores incoming data while closed, so no window surfaces. Throttled: a filling group fires GROUP_ROSTER_UPDATE repeatedly.
local GV_REQUEST_THROTTLE = 5
local GV_REQUEST_FLOOR = 1

-- `emptyHand` = the caller has nothing to show for this group, exactly when the poll
-- matters most, so it respects only a short floor: a member who just joined may not
-- have answered the roster-change request, and swallowing the hover request too would leave the tooltip blank until a later re-hover.
local function GVRequestKeys(emptyHand)
    local lib = GVLib()
    -- A party of your own: the request goes out on PARTY, which a Dungeon Finder group alone answers with "You aren't in a party."
    if not lib or not IsInGroup(LE_PARTY_CATEGORY_HOME) then
        return
    end
    local nowTime = GetTime()
    local wait = emptyHand and GV_REQUEST_FLOOR or GV_REQUEST_THROTTLE
    if nowTime - _gvLastRequest < wait then
        return
    end
    _gvLastRequest = nowTime
    lib.Request("PARTY")
end

-- The player's own unit is excluded everywhere: their key has its own row, read straight from C_MythicPlus.
local function GVGroupRange()
    if IsInRaid() then
        return "raid", GetNumGroupMembers()
    end
    return "party", GetNumGroupMembers() - 1
end

-- Matched on the short name, exactly like the render path, so a sender is recognised whether the library reports "Name" or "Name-Realm".
function GVInGroup(playerName)
    if not IsInGroup() then
        return false
    end
    local short = GVShortName(playerName)
    if not short then
        return false
    end
    local prefixText, total = GVGroupRange()
    for idx = 1, total do
        if GVShortName(GetUnitName(prefixText .. idx, true)) == short then
            return true
        end
    end
    return false
end

-- The cache is roster-scoped: otherwise every player met across an evening of pugs
-- leaves a permanent entry that can never display again, since rendering only looks
-- at the current group. Pruning drops only names already gone, so it can never blank a member still here while the request throttle is closed.
local function GVPruneKeys()
    if not next(_gvKeys) then
        return
    end
    if not IsInGroup() then
        wipe(_gvKeys)
        return
    end

    -- GROUP_ROSTER_UPDATE can land before units resolve; pruning an unresolved roster discards live keys and costs a request round-trip on next hover.
    local prefixText, total = GVGroupRange()
    local resolved = false
    for idx = 1, total do
        if GetUnitName(prefixText .. idx, true) then
            resolved = true
            break
        end
    end
    if not resolved then
        return
    end

    for name in pairs(_gvKeys) do
        if not GVInGroup(name) then
            _gvKeys[name] = nil
        end
    end
end

local function GVSortPartyRows(a, b)
    if a.level ~= b.level then
        return a.level > b.level
    end
    return a.name < b.name
end

-- Reused row tables (no per-show garbage). The sort swaps table REFERENCES inside the buffer, so the row tables survive to be refilled next hover.
local _gvPartyBuf = {}
local _gvPartyCount = 0
local _gvShortIdx = {}

local function GVAddPartyRow(name, dungeon, level, r, g, b)
    _gvPartyCount = _gvPartyCount + 1
    local e = _gvPartyBuf[_gvPartyCount]
    if not e then
        e = {}
        _gvPartyBuf[_gvPartyCount] = e
    end
    e.name, e.dungeon, e.level = name, dungeon, level
    e.r, e.g, e.b = r, g, b
end

-- LibKeystone reports "Name-Realm" while the roster hands back a bare name for
-- same-realm members: try the exact match first, short name only as fallback. Two
-- cross-realm members CAN share a first name, so colliding short names are marked ambiguous (false) and skipped -- better nothing than the wrong key.
local function GVBuildPartyRows()
    _gvPartyCount = 0
    if not IsInGroup() then
        return 0
    end

    wipe(_gvShortIdx)
    local any = false
    for name, details in pairs(_gvKeys) do
        if details and (details.level or 0) > 0 then
            local short = GVShortName(name)
            if short then
                if _gvShortIdx[short] == nil then
                    _gvShortIdx[short] = details
                else
                    _gvShortIdx[short] = false
                end
                any = true
            end
        end
    end
    if not any then
        return 0
    end

    local prefixText, total = GVGroupRange()
    for idx = 1, total do
        local unitToken = prefixText .. idx
        if UnitExists(unitToken) and not UnitIsUnit(unitToken, "player") then
            local unitName = GetUnitName(unitToken, true)
            local details = _gvKeys[unitName]
            if not (details and (details.level or 0) > 0) then
                details = _gvShortIdx[GVShortName(unitName)] or nil
            end
            local dungeon = details and GVDungeonName(details.mapID)
            if dungeon then
                local _, class = UnitClass(unitToken)
                local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                GVAddPartyRow(
                    GetUnitName(unitToken) or unitToken,
                    dungeon,
                    details.level,
                    (cc and cc.r) or 1,
                    (cc and cc.g) or 1,
                    (cc and cc.b) or 1
                )
            end
        end
    end

    for idx = 2, _gvPartyCount do
        local jdx = idx
        while jdx > 1 and GVSortPartyRows(_gvPartyBuf[jdx], _gvPartyBuf[jdx - 1]) do
            _gvPartyBuf[jdx], _gvPartyBuf[jdx - 1] = _gvPartyBuf[jdx - 1], _gvPartyBuf[jdx]
            jdx = jdx - 1
        end
    end
    return _gvPartyCount
end

mod.BlockFactories.greatvault = function(blockCfg, slot, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)
    instance.events = { "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }

    local mouseOver = false

    local btnFrame = CreateFrame("Button", nil, contentFrame)
    btnFrame:SetAllPoints()
    btnFrame:EnableMouse(true)
    btnFrame:RegisterForClicks("AnyUp")

    local icon = btnFrame:CreateTexture(nil, "OVERLAY")
    K.SetBlockIcon(icon, blockCfg)
    local labelText = btnFrame:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(instance, labelText)

    function instance:Refresh()
        local barCfg = barCtx.cfg
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()
        -- Core translator, not the file's English-only `L` table: vault terms share catalog entries with the minimap's vault tooltip.
        local textValue = CludesUI.L("Great Vault")
        local iconSz = fontSize + 4

        if isSide then
            local slotW = VSlotW(instance)
            local innerW = max(24, slotW - 8)
            mod.SetFont(labelText, fontSize, barCfg)
            labelText:SetText(textValue)
            icon:SetSize(iconSz, iconSz)
            icon:ClearAllPoints()
            icon:SetPoint("TOP", btnFrame, "TOP", 0, -4)
            mod.SetWrappedText(labelText, innerW, "CENTER")
            labelText:ClearAllPoints()
            labelText:SetPoint("TOP", icon, "BOTTOM", 0, -2)
            local totalH = 8 + iconSz + 2 + mod.SnapToPixelGrid(labelText:GetStringHeight()) + 4
            totalH = max(totalH, barH)
            contentFrame:SetSize(slotW, totalH)
            btnFrame:SetSize(slotW, totalH)
        else
            local slotW = HBudget(instance, 120)
            local gap = ICON_GAP
            mod.SetFont(labelText, fontSize, barCfg)
            mod.ResetInlineText(labelText, "LEFT")
            labelText:SetText(textValue)
            icon:SetSize(iconSz, iconSz)
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", btnFrame, "LEFT", 0, 0)
            labelText:ClearAllPoints()
            labelText:SetPoint("LEFT", btnFrame, "LEFT", iconSz + gap, 0)
            local tw = mod.SnapToPixelGrid(labelText:GetStringWidth())
            local totalW = min(slotW, iconSz + gap + tw + 4)
            contentFrame:SetSize(max(totalW, 10), barH)
            btnFrame:SetSize(max(totalW, 10), barH)
        end

        if mouseOver then
            local ar, ag, ab = mod.GetAccent()
            labelText:SetTextColor(ar, ag, ab, 1)
            icon:SetVertexColor(ar, ag, ab, 1)
        else
            local cbr, cbg, cbb = BlockColorOf(blockCfg)
            local ir, ig, ib = IconColorOf(blockCfg)
            labelText:SetTextColor(cbr, cbg, cbb, 1)
            icon:SetVertexColor(ir, ig, ib, 1)
        end
        MaybeRelayout(instance)
    end

    local function ShowVaultTooltip()
        local ar, ag, ab = mod.GetAccent()
        mod.Tip_Begin(btnFrame)
        mod.Tip_AddLine("|cFFFFFFFF[|r" .. CludesUI.L("Great Vault") .. "|cFFFFFFFF]|r", ar, ag, ab)
        mod.Tip_AddLine(" ")
        mod.Tip_AddColumns(CludesUI.L("Raids"), GVRowTokens(GV_RAID, true), 0.8, 0.8, 0.8)
        mod.Tip_AddColumns(CludesUI.L("Mythic+"), GVRowTokens(GV_MPLUS, false), 0.8, 0.8, 0.8)
        mod.Tip_AddColumns(CludesUI.L("World"), GVRowTokens(GV_WORLD, false), 0.8, 0.8, 0.8)

        local myDungeon, myLevel = GVOwnedKeystone()
        if myDungeon then
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(CludesUI.L("Your Keystone"), ar, ag, ab)
            mod.Tip_AddDouble(myDungeon, "+" .. myLevel, 0.8, 0.8, 0.8, 1, 1, 1)
        end

        local partyCount = GVBuildPartyRows()
        if partyCount > 0 then
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(CludesUI.L("Party Keystones"), ar, ag, ab)
            for idx = 1, partyCount do
                local e = _gvPartyBuf[idx]
                mod.Tip_AddDouble(
                    e.name,
                    e.dungeon .. " |cffffffff+" .. e.level .. "|r",
                    e.r,
                    e.g,
                    e.b,
                    0.6,
                    0.6,
                    0.6
                )
            end
        end

        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["LEFT_CLICK"], CludesUI.L("Open Great Vault"), 1, 1, 1, ar, ag, ab)
        mod.Tip_Show()
        return partyCount
    end

    btnFrame:SetScript("OnEnter", function()
        mouseOver = true
        instance:Refresh()
        -- Paint from the cache first, then poll: a member can pick up a new key without
        -- the group changing, and the painted row count says whether we had anything --
        -- an empty section bypasses the throttle. Replies land ~1s later and repaint the tip in place.
        local isShown = ShowVaultTooltip()
        _gvOpenBtn, _gvOpenFn = btnFrame, ShowVaultTooltip
        GVRequestKeys(isShown == 0)
    end)
    btnFrame:SetScript("OnLeave", function()
        mouseOver = false
        _gvOpenBtn, _gvOpenFn = nil, nil
        mod.Tip_Hide(btnFrame)
        instance:Refresh()
    end)
    btnFrame:SetScript("OnClick", function(_, mb)
        if mb == "LeftButton" then
            CludesUI.ToggleGreatVault()
        end
    end)

    -- The block's visuals never change with the roster; these events exist only to drop departed members and keep the cache warm for the next hover.
    instance.eventFrame = MakeEventFrame(instance, function()
        GVPruneKeys()
        GVRequestKeys()
    end)

    -- Teardown can happen while the tip is open (a bar rebuild never fires OnLeave),
    -- and _gvOpenFn is module-level: left set, it would pin this factory's whole scope for the rest of the session.
    local function ForgetOpenTip()
        if _gvOpenBtn == btnFrame then
            _gvOpenBtn, _gvOpenFn = nil, nil
        end
    end

    function instance:Enable()
        contentFrame:Show()
        GVEnsureKeystoneFeed()
        RegisterInstEvents(self)
        GVRequestKeys()
    end

    function instance:Disable()
        ForgetOpenTip()
        UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    function instance:GetAutoLength()
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 30)
        end
        return max(contentFrame:GetWidth() or 60, 24)
    end

    function instance:Destroy()
        self._dead = true
        ForgetOpenTip()
        contentFrame:Hide()
    end

    return instance
end
