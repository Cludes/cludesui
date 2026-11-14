if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Blocks\TimePlayed.lua
-- Time Played block factory and the account-wide record of each character's total.

local ADDON_NAME, mod = ...
local L = mod.L
local K = mod.BlockKit

-- Upvalues
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local GetTime = GetTime
local UnitLevel = UnitLevel
local pairs = pairs
local ipairs = ipairs
local next = next
local type = type
local format = string.format
local tinsert = table.insert
local tsort = table.sort
local floor = math.floor
local max = math.max
local min = math.min

local CONTENT_BASE = K.CONTENT_BASE
local InstKey = K.InstKey
local HBudget = K.HBudget
local VSlotW = K.VSlotW
local MaybeRelayout = K.MaybeRelayout
local AttachTextOffset = K.AttachTextOffset
local BlockColorOf = K.BlockColorOf
local IsSecret = CludesUI.IsSecret
local FmtDur = CludesUI.FormatDuration

-------------------------------------------------------------------------------
--  TIME PLAYED
--
--  The server only gives played time through /played, and the game prints its
--  two lines in chat for each request. A login asks once while a block is
--  enabled (CludesUI.RequestTimePlayed, shared with the XP bar). A /reload
--  asks nothing: the time saved at PLAYER_LOGOUT (which fires on /reload too)
--  is taken back at the next load's first PLAYER_ENTERING_WORLD, plus the
--  seconds the reload took (/played counts on through a reload).
--  Totals live in CludesUIDB.timePlayedChars, outside the profile:
--      [guid] = { name, realm, class, level, total }  -- total in seconds
--  plus, from PLAYER_LOGOUT until the next load's first PLAYER_ENTERING_WORLD,
--  lvlTime (the seconds at this level) and at (the GetTime() both are as of).
--  By GUID: WoW Forever first names are not the whole name, and a rename keeps it.
-------------------------------------------------------------------------------
local liveInsts = {}
local eventFrame = CreateFrame("Frame")
-- Last known seconds as of baseAt (a GetTime()); nil until the first reply.
local baseTotal, baseLevel, baseAt
local baseCharLevel
local lastMinutes -- the heartbeat's last seen minute counters
-- A /reload takes seconds: a saved time older than this is not taken back
-- (an earlier session's, or a reload that ran long), and the load asks.
local RELOAD_WINDOW = 120
local reloadPending -- a saved time waits for the first PLAYER_ENTERING_WORLD

local function PlayedTotal()
    return baseTotal + (GetTime() - baseAt)
end
local function PlayedLevel()
    return baseLevel + (GetTime() - baseAt)
end

local function Store()
    local saved = CludesUIDB
    if type(saved) ~= "table" then
        return nil
    end
    if type(saved.timePlayedChars) ~= "table" then
        saved.timePlayedChars = {}
    end
    return saved.timePlayedChars
end

-- This character's store key; nil while the GUID cannot be read.
local function CharGUID()
    local unitGuid = UnitGUID("player")
    if not unitGuid or IsSecret(unitGuid) then
        return nil
    end
    return unitGuid
end

-- Writes the live total to this character's entry.
local function SaveCharacter()
    if not baseTotal then
        return
    end
    local storage = Store()
    local key = CharGUID()
    if not storage or not key then
        return
    end
    local e = storage[key]
    if not e then
        e = {}
        storage[key] = e
    end
    local _, class = UnitClass("player")
    -- The full name whatever the show-surname preference.
    local name, surname = (UnitNameUnmodified or UnitName)("player")
    e.name, e.realm, e.class, e.level, e.total =
        CludesUI.WithSurname(name, surname, true),
        CludesUI.RealmGroupName(),
        class,
        baseCharLevel,
        PlayedTotal()
end

local function RefreshAll()
    for instance in pairs(liveInsts) do
        instance:Refresh()
    end
end

-- Every character gone; this one is recorded again at once, the others when
-- they next log in with a block enabled.
local function ResetAll()
    local saved = CludesUIDB
    if type(saved) == "table" then
        saved.timePlayedChars = nil
    end
    SaveCharacter()
end

-- Repaints and saves only when a shown minute rolls over.
local function OnHeartbeat()
    if not baseTotal then
        return
    end
    local minutes = floor(PlayedTotal() / 60) + floor(PlayedLevel() / 60)
    if minutes == lastMinutes then
        return
    end
    lastMinutes = minutes
    SaveCharacter()
    RefreshAll()
end

-- Takes a reply, as of now. Ignores anything else (no reply known yet).
local function SetPlayed(sum, level)
    if type(sum) ~= "number" or type(level) ~= "number" then
        return
    end
    baseTotal, baseLevel, baseAt, baseCharLevel = sum, level, GetTime(), UnitLevel("player")
    SaveCharacter()
    RefreshAll()
end

local function RequestPlayed()
    -- Not before the first PLAYER_ENTERING_WORLD has looked at a saved time.
    if reloadPending then
        return
    end
    SetPlayed(CludesUI.RequestTimePlayed())
end

-- PLAYER_LOGOUT (on /reload too): the time as of now, for the next load.
local function SaveReload()
    if not baseTotal then
        return
    end
    SaveCharacter()
    local storage, key = Store(), CharGUID()
    local e = storage and key and storage[key]
    if e then
        e.lvlTime, e.at = PlayedLevel(), GetTime()
    end
end

-- The load's first PLAYER_ENTERING_WORLD: a /reload takes this character's
-- saved time back; every saved time is dropped, so none outlives this load.
local function TakeReload(isReloadingUi)
    reloadPending = nil
    local saved = CludesUIDB
    local storage = type(saved) == "table" and saved.timePlayedChars
    if type(storage) == "table" then
        local me, nowTime = CharGUID(), GetTime()
        for key, e in pairs(storage) do
            if type(e) == "table" and e.at ~= nil then
                local at, lvlTime = e.at, e.lvlTime
                e.at, e.lvlTime = nil, nil
                if
                    isReloadingUi
                    and key == me
                    and type(at) == "number"
                    and type(lvlTime) == "number"
                    and type(e.total) == "number"
                    and e.level == UnitLevel("player")
                    and at <= nowTime
                    and nowTime - at < RELOAD_WINDOW
                then
                    SetPlayed(e.total + (nowTime - at), lvlTime + (nowTime - at))
                end
            end
        end
    end
    if next(liveInsts) and not baseTotal then
        RequestPlayed()
    end
end

eventFrame:SetScript("OnEvent", function(_, evt, arg1, arg2)
    if evt == "TIME_PLAYED_MSG" then
        SetPlayed(arg1, arg2)
    elseif evt == "PLAYER_ENTERING_WORLD" then
        eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        TakeReload(arg2)
    elseif evt == "PLAYER_LOGOUT" then
        SaveReload()
    elseif baseTotal then
        -- PLAYER_LEVEL_UP: the new level starts at no time played.
        baseTotal, baseLevel, baseAt, baseCharLevel = PlayedTotal(), 0, GetTime(), arg1
        SaveCharacter()
        RefreshAll()
    end
end)

local function SyncEvents()
    if next(liveInsts) then
        eventFrame:RegisterEvent("TIME_PLAYED_MSG")
        eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
        eventFrame:RegisterEvent("PLAYER_LOGOUT")
        mod.RegisterHeartbeat("timeplayed", OnHeartbeat)
        -- A level-up while no block was enabled also makes the level time stale.
        if not baseTotal or baseCharLevel ~= UnitLevel("player") then
            RequestPlayed()
        end
    else
        -- Keeps the record current up to the moment the last block goes.
        SaveCharacter()
        -- A first PLAYER_ENTERING_WORLD still owed stays: it drops the saved time.
        eventFrame:UnregisterEvent("TIME_PLAYED_MSG")
        eventFrame:UnregisterEvent("PLAYER_LEVEL_UP")
        eventFrame:UnregisterEvent("PLAYER_LOGOUT")
        mod.UnregisterHeartbeat("timeplayed")
    end
end

-- A load after one that saved its time waits for its first
-- PLAYER_ENTERING_WORLD, which tells a /reload from a login, before it asks.
do
    local saved = CludesUIDB
    local storage = type(saved) == "table" and saved.timePlayedChars
    if type(storage) == "table" and not IsLoggedIn() then
        for _, e in pairs(storage) do
            if type(e) == "table" and e.at ~= nil then
                reloadPending = true
                eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
                break
            end
        end
    end
end

mod.BlockFactories.timeplayed = function(blockCfg, slot, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)

    local mouseOver = false

    local function D()
        return blockCfg.settings or {}
    end

    local btnFrame = CreateFrame("Button", nil, contentFrame)
    btnFrame:SetAllPoints()
    btnFrame:EnableMouse(true)
    btnFrame:RegisterForClicks("AnyUp")

    local labelText = btnFrame:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(instance, labelText)

    function instance:Refresh()
        if self._dead then
            return
        end
        local barCfg = barCtx.cfg
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local textValue = "--"
        if baseTotal then
            if D().alwaysTotal == true or K.AtMaxLevel() then
                textValue = FmtDur(PlayedTotal())
            else
                textValue = FmtDur(PlayedLevel())
            end
        end

        mod.SetFont(labelText, fontSize, barCfg)
        if mouseOver then
            labelText:SetTextColor(mod.GetAccent())
        else
            labelText:SetTextColor(BlockColorOf(blockCfg))
        end
        -- A secure overlay elsewhere on the bar protects its geometry in
        -- lockdown: only the text updates now, sizing waits for regen.
        if InCombatLockdown() then
            labelText:SetText(textValue)
            mod.DeferUntilOOC("timeplayed:" .. instance.key, function()
                instance:Refresh()
            end)
            return
        end
        if barCtx.IsVertical() then
            local slotW = VSlotW(instance)
            local innerW = max(24, slotW - 8)
            labelText:SetText(textValue)
            mod.SetWrappedText(labelText, innerW, "CENTER")
            labelText:ClearAllPoints()
            labelText:SetPoint("TOP", btnFrame, "TOP", 0, -4)
            local totalH = max(8 + mod.SnapToPixelGrid(labelText:GetStringHeight()) + 4, barH)
            contentFrame:SetSize(slotW, totalH)
            btnFrame:SetSize(slotW, totalH)
        else
            local slotW = HBudget(instance, 100)
            mod.ResetInlineText(labelText, "LEFT")
            labelText:SetText(textValue)
            labelText:ClearAllPoints()
            labelText:SetPoint("LEFT", btnFrame, "LEFT", 0, 0)
            local tw = mod.SnapToPixelGrid(labelText:GetStringWidth())
            local totalW = max(min(slotW, tw + 4), 10)
            contentFrame:SetSize(totalW, barH)
            btnFrame:SetSize(totalW, barH)
        end
        MaybeRelayout(instance)
    end

    local function ShowTooltip()
        local ar, ag, ab = mod.GetAccent()
        SaveCharacter()
        -- Every stored character by key, grouped by realm: realms A-Z, most played first.
        local storage = Store() or {}
        local selfKey = CharGUID()
        local byRealm, realms, sum, charCount = {}, {}, 0, 0
        for key, e in pairs(storage) do
            if type(e) == "table" and type(e.total) == "number" then
                local realm = e.realm or "?"
                if not byRealm[realm] then
                    byRealm[realm] = {}
                    tinsert(realms, realm)
                end
                tinsert(byRealm[realm], key)
                sum = sum + e.total
                charCount = charCount + 1
            end
        end
        tsort(realms)
        mod.Tip_Begin(btnFrame)
        mod.Tip_AddLine(CludesUI.L("Time Played"), ar, ag, ab)
        for _, realm in ipairs(realms) do
            local keyList = byRealm[realm]
            tsort(keyList, function(a, b)
                return storage[a].total > storage[b].total
            end)
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(realm, 0.5, 0.78, 1)
            for _, key in ipairs(keyList) do
                local e = storage[key]
                local cr, cg, cb = 1, 1, 1
                local cc = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
                if cc then
                    cr, cg, cb = cc.r, cc.g, cc.b
                end
                -- The live character's click is inert: it saves again every minute.
                local labelText = e.name or "?"
                if e.level then
                    labelText = format("%s (%d)", labelText, e.level)
                end
                mod.Tip_AddClickable(labelText, FmtDur(e.total), function(mouseButton)
                    if key == selfKey then
                        return
                    end
                    if mouseButton ~= "LeftButton" then
                        return
                    end
                    if not (IsControlKeyDown() and IsAltKeyDown()) then
                        return
                    end
                    storage[key] = nil
                    mod.Tip_Hide(btnFrame)
                end, cr, cg, cb, 1, 1, 1)
            end
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["TOTAL"], FmtDur(sum), 1, 1, 1, 1, 1, 1)
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["CTRL_SHIFT_RIGHT_CLICK"], L["RESET_ALL_DATA"], 1, 1, 1, ar, ag, ab)
        if charCount > 1 then
            mod.Tip_AddDouble(L["CTRL_ALT_LEFT_CLICK"], L["REMOVE_CHARACTER"], 1, 1, 1, ar, ag, ab)
        end
        mod.Tip_Show()
    end

    btnFrame:SetScript("OnEnter", function()
        mouseOver = true
        instance:Refresh()
        -- Retry a request whose reply never came.
        if not baseTotal then
            RequestPlayed()
        end
        ShowTooltip()
    end)
    btnFrame:SetScript("OnLeave", function()
        mouseOver = false
        -- The character rows are clickable, so the tooltip has to survive the cursor leaving the block.
        mod.Tip_HideUnlessInteractive(btnFrame)
        instance:Refresh()
    end)
    btnFrame:SetScript("OnClick", function(_, mb)
        if mb == "RightButton" and IsControlKeyDown() and IsShiftKeyDown() then
            mod.Tip_Hide(btnFrame)
            CludesUI:ShowConfirmPopup({
                title = "Reset Time Played Data",
                message = "Clear the time played of every character? This character is recorded again at once, the others when they next log in.",
                confirmText = "Reset",
                cancelText = "Cancel",
                onConfirm = ResetAll,
            })
        end
    end)

    function instance:Enable()
        contentFrame:Show()
        liveInsts[self] = true
        SyncEvents()
        self:Refresh()
    end

    function instance:Disable()
        liveInsts[self] = nil
        SyncEvents()
        mod.Tip_Hide(btnFrame)
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
        liveInsts[self] = nil
        SyncEvents()
        contentFrame:Hide()
    end

    return instance
end
