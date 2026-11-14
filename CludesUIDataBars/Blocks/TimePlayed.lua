if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Blocks\TimePlayed.lua - Info Bar block: time played, and the account-wide
--  record of every character's total.
--
--  Shows the time at this level, or the total (at max level, or when the
--  setting asks). Hover lists every recorded character by realm with the sum;
--  Ctrl+Alt+click on a row forgets that character, Ctrl+Shift+right-click on
--  the block forgets them all.
--
--  Where the time comes from: the server gives it only through /played, and
--  the game prints two chat lines for each request. So a login asks once
--  while a block is enabled (CludesUI.RequestTimePlayed, shared with the XP
--  bar), and the time then counts on locally. A /reload asks nothing: the
--  time is saved at PLAYER_LOGOUT (which fires on /reload too) and taken back
--  at the next load's first PLAYER_ENTERING_WORLD, plus the seconds the reload
--  took (/played counts on through a reload).
--
--  The record: CludesUIDB.timePlayedChars, outside the profile, by GUID (WoW
--  Forever first names are not the whole name, and a rename keeps the GUID):
--      [guid] = { name, realm, class, level, total }   -- total in seconds
--  plus, from PLAYER_LOGOUT until the next load's first PLAYER_ENTERING_WORLD,
--  lvlTime (the seconds at this level) and at (the GetTime() both are as of).
--
--  Settings (blockCfg.settings): alwaysTotal (show the total below max level).
-------------------------------------------------------------------------------
local _, mod = ...
local L = mod.L
local K = mod.BlockKit

-- Kept as locals: the minute heartbeat runs these for as long as a block is on.
local GetTime, UnitLevel, InCombatLockdown = GetTime, UnitLevel, InCombatLockdown
local format, floor, max, min = string.format, math.floor, math.max, math.min
local Duration = CludesUI.FormatDuration

-- A saved time older than this is not taken back (an earlier session's, or a
-- reload that ran long) and the load asks the server instead.
local RELOAD_WINDOW = 120

local blocks = {} -- every enabled block, as a set
local listener = CreateFrame("Frame")

-- The last reply, counted on from `since` (a GetTime()); nil until one comes.
local total, levelTime, since, charLevel
local lastMinute -- the heartbeat's last seen minute counters
local awaitingWorld -- a saved time waits for the first PLAYER_ENTERING_WORLD

local function Total()
    return total + (GetTime() - since)
end
local function AtThisLevel()
    return levelTime + (GetTime() - since)
end

local function Record()
    local db = CludesUIDB
    if type(db) ~= "table" then
        return nil
    end
    if type(db.timePlayedChars) ~= "table" then
        db.timePlayedChars = {}
    end
    return db.timePlayedChars
end

-- This character's key in the record; nil while the GUID cannot be read.
local function MyKey()
    local guid = UnitGUID("player")
    if not guid or CludesUI.IsSecret(guid) then
        return nil
    end
    return guid
end

-- Writes the live total to this character's entry.
local function SaveMe()
    if not total then
        return
    end
    local record, key = Record(), MyKey()
    if not record or not key then
        return
    end
    local entry = record[key]
    if not entry then
        entry = {}
        record[key] = entry
    end
    local _, class = UnitClass("player")
    -- The full name, whatever the show-surname preference.
    local name, surname = (UnitNameUnmodified or UnitName)("player")
    entry.name = CludesUI.WithSurname(name, surname, true)
    entry.realm = CludesUI.RealmGroupName()
    entry.class = class
    entry.level = charLevel
    entry.total = Total()
end

-- Every block lays out again (a new reply, a level-up).
local function RedrawAll()
    for block in pairs(blocks) do
        block:Refresh()
    end
end

-- Forgets every character; this one is recorded again at once, the others
-- when they next log in with a block enabled.
local function ForgetAll()
    if type(CludesUIDB) == "table" then
        CludesUIDB.timePlayedChars = nil
    end
    SaveMe()
end

-- Every second: when a minute rolls over, save, and update each block, which
-- redraws only if its text changed (over a day the text shows hours, so most
-- minutes change nothing on screen).
local function Heartbeat()
    if not total then
        return
    end
    local minute = floor(Total() / 60) + floor(AtThisLevel() / 60)
    if minute == lastMinute then
        return
    end
    lastMinute = minute
    SaveMe()
    for block in pairs(blocks) do
        block:Tick()
    end
end

-- Takes a reply as of now; ignores anything else (no reply known yet).
local function TakeReply(sum, atLevel)
    if type(sum) ~= "number" or type(atLevel) ~= "number" then
        return
    end
    total, levelTime, since, charLevel = sum, atLevel, GetTime(), UnitLevel("player")
    SaveMe()
    RedrawAll()
end

local function Ask()
    -- Not before the first PLAYER_ENTERING_WORLD has looked at a saved time.
    if awaitingWorld then
        return
    end
    TakeReply(CludesUI.RequestTimePlayed())
end

-- PLAYER_LOGOUT (on /reload too): the time as of now, for the next load.
local function SaveForReload()
    if not total then
        return
    end
    SaveMe()
    local record, key = Record(), MyKey()
    local entry = record and key and record[key]
    if entry then
        entry.lvlTime, entry.at = AtThisLevel(), GetTime()
    end
end

-- The load's first PLAYER_ENTERING_WORLD: a /reload takes this character's
-- saved time back. Every saved time is dropped, so none outlives this load.
local function TakeBackReload(isReload)
    awaitingWorld = nil
    local db = CludesUIDB
    local record = type(db) == "table" and db.timePlayedChars
    if type(record) == "table" then
        local me, now = MyKey(), GetTime()
        for key, entry in pairs(record) do
            if type(entry) == "table" and entry.at ~= nil then
                local at, atLevel = entry.at, entry.lvlTime
                entry.at, entry.lvlTime = nil, nil
                local usable = isReload
                    and key == me
                    and type(at) == "number"
                    and type(atLevel) == "number"
                    and type(entry.total) == "number"
                    and entry.level == UnitLevel("player")
                    and at <= now
                    and now - at < RELOAD_WINDOW
                if usable then
                    TakeReply(entry.total + (now - at), atLevel + (now - at))
                end
            end
        end
    end
    if next(blocks) and not total then
        Ask()
    end
end

listener:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "TIME_PLAYED_MSG" then
        TakeReply(arg1, arg2)
    elseif event == "PLAYER_ENTERING_WORLD" then
        listener:UnregisterEvent("PLAYER_ENTERING_WORLD")
        TakeBackReload(arg2)
    elseif event == "PLAYER_LOGOUT" then
        SaveForReload()
    elseif total then
        -- PLAYER_LEVEL_UP: the new level starts at no time played.
        total, levelTime, since, charLevel = Total(), 0, GetTime(), arg1
        SaveMe()
        RedrawAll()
    end
end)

-- Listens (and ticks) only while a block is enabled.
local function Listen()
    if next(blocks) then
        listener:RegisterEvent("TIME_PLAYED_MSG")
        listener:RegisterEvent("PLAYER_LEVEL_UP")
        listener:RegisterEvent("PLAYER_LOGOUT")
        mod.RegisterHeartbeat("timeplayed", Heartbeat)
        -- A level-up while no block was enabled also leaves the level time stale.
        if not total or charLevel ~= UnitLevel("player") then
            Ask()
        end
    else
        -- The record stays current up to the moment the last block goes.
        SaveMe()
        -- A first PLAYER_ENTERING_WORLD still owed stays: it drops the saved time.
        listener:UnregisterEvent("TIME_PLAYED_MSG")
        listener:UnregisterEvent("PLAYER_LEVEL_UP")
        listener:UnregisterEvent("PLAYER_LOGOUT")
        mod.UnregisterHeartbeat("timeplayed")
    end
end

-- A load after one that saved its time waits for its first
-- PLAYER_ENTERING_WORLD, which tells a /reload from a login, before it asks.
do
    local db = CludesUIDB
    local record = type(db) == "table" and db.timePlayedChars
    if type(record) == "table" and not IsLoggedIn() then
        for _, entry in pairs(record) do
            if type(entry) == "table" and entry.at ~= nil then
                awaitingWorld = true
                listener:RegisterEvent("PLAYER_ENTERING_WORLD")
                break
            end
        end
    end
end

-- Characters grouped by realm, realms A-Z, each realm's most played first;
-- returns the groups, the realm order, the sum and the count.
local function Roster(record)
    local byRealm, realms, sum, count = {}, {}, 0, 0
    for key, entry in pairs(record) do
        if type(entry) == "table" and type(entry.total) == "number" then
            local realm = entry.realm or "?"
            local list = byRealm[realm]
            if not list then
                list = {}
                byRealm[realm] = list
                realms[#realms + 1] = realm
            end
            list[#list + 1] = key
            sum = sum + entry.total
            count = count + 1
        end
    end
    table.sort(realms)
    local function MostPlayed(a, b)
        return record[a].total > record[b].total
    end
    for _, realm in ipairs(realms) do
        table.sort(byRealm[realm], MostPlayed)
    end
    return byRealm, realms, sum, count
end

mod.BlockFactories.timeplayed = function(blockCfg, slot, contentFrame, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)

    local function Settings()
        return blockCfg.settings or {}
    end

    local button = CreateFrame("Button", nil, contentFrame)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")
    local label = button:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, label)

    local hovered = false
    local shownText -- the text on screen; a minute that would not change it draws nothing

    local function Text()
        if not total then
            return "--"
        end
        if Settings().alwaysTotal == true or K.AtMaxLevel() then
            return Duration(Total())
        end
        return Duration(AtThisLevel())
    end

    local function PaintText()
        if hovered then
            label:SetTextColor(mod.GetAccent())
        else
            label:SetTextColor(K.BlockColorOf(blockCfg))
        end
    end

    function inst:Refresh()
        if self._dead then
            return
        end
        local text = Text()
        shownText = text
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        mod.SetFont(label, fontSize, barCtx.cfg)
        PaintText()
        -- A secure overlay elsewhere on the bar protects its layout in combat:
        -- the text changes now, the size when combat ends.
        if InCombatLockdown() then
            label:SetText(text)
            mod.DeferUntilOOC("timeplayed:" .. inst.key, function()
                inst:Refresh()
            end)
            return
        end
        if barCtx.IsVertical() then
            local slotW = K.VSlotW(inst)
            label:SetText(text)
            mod.SetWrappedText(label, max(24, slotW - 8), "CENTER")
            label:ClearAllPoints()
            label:SetPoint("TOP", button, "TOP", 0, -4)
            local height = max(8 + mod.SnapToPixelGrid(label:GetStringHeight()) + 4, barH)
            contentFrame:SetSize(slotW, height)
            button:SetSize(slotW, height)
        else
            local budget = K.HBudget(inst, 100)
            mod.ResetInlineText(label, "LEFT")
            label:SetText(text)
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", 0, 0)
            local width = max(min(budget, mod.SnapToPixelGrid(label:GetStringWidth()) + 4), 10)
            contentFrame:SetSize(width, barH)
            button:SetSize(width, barH)
        end
        K.MaybeRelayout(inst)
    end

    -- The heartbeat's minute: a redraw only when the shown text changes.
    function inst:Tick()
        if not self._dead and Text() ~= shownText then
            self:Refresh()
        end
    end

    local function ShowTooltip()
        local ar, ag, ab = mod.GetAccent()
        SaveMe()
        local record = Record() or {}
        local me = MyKey()
        local byRealm, realms, sum, count = Roster(record)
        mod.Tip_Begin(button)
        mod.Tip_AddLine(CludesUI.L("Time Played"), ar, ag, ab)
        for _, realm in ipairs(realms) do
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(realm, 0.5, 0.78, 1)
            for _, key in ipairs(byRealm[realm]) do
                local entry = record[key]
                local color = entry.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class]
                local r, g, b = 1, 1, 1
                if color then
                    r, g, b = color.r, color.g, color.b
                end
                local who = entry.name or "?"
                if entry.level then
                    who = format("%s (%d)", who, entry.level)
                end
                -- Ctrl+Alt+click forgets a character; never this one, which
                -- would be saved again within the minute.
                mod.Tip_AddClickable(who, Duration(entry.total), function(mouseButton)
                    if key == me or mouseButton ~= "LeftButton" then
                        return
                    end
                    if not (IsControlKeyDown() and IsAltKeyDown()) then
                        return
                    end
                    record[key] = nil
                    mod.Tip_Hide(button)
                end, r, g, b, 1, 1, 1)
            end
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["TOTAL"], Duration(sum), 1, 1, 1, 1, 1, 1)
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["CTRL_SHIFT_RIGHT_CLICK"], L["RESET_ALL_DATA"], 1, 1, 1, ar, ag, ab)
        if count > 1 then
            mod.Tip_AddDouble(L["CTRL_ALT_LEFT_CLICK"], L["REMOVE_CHARACTER"], 1, 1, 1, ar, ag, ab)
        end
        mod.Tip_Show()
    end

    -- Hovering only recolours the text; nothing moves, so nothing is laid out again.
    button:SetScript("OnEnter", function()
        hovered = true
        PaintText()
        -- Retry a request whose reply never came.
        if not total then
            Ask()
        end
        ShowTooltip()
    end)
    button:SetScript("OnLeave", function()
        hovered = false
        -- The rows are clickable, so the tooltip outlives the cursor leaving the block.
        mod.Tip_HideUnlessInteractive(button)
        PaintText()
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" and IsControlKeyDown() and IsShiftKeyDown() then
            mod.Tip_Hide(button)
            CludesUI:ShowConfirmPopup({
                title = "Reset Time Played Data",
                message = "Clear the time played of every character? This character is recorded again at once, the others when they next log in.",
                confirmText = "Reset",
                cancelText = "Cancel",
                onConfirm = ForgetAll,
            })
        end
    end)

    function inst:Enable()
        contentFrame:Show()
        blocks[self] = true
        Listen()
        self:Refresh()
    end

    function inst:Disable()
        blocks[self] = nil
        Listen()
        mod.Tip_Hide(button)
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
        blocks[self] = nil
        Listen()
        contentFrame:Hide()
    end

    return inst
end
