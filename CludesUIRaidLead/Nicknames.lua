if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nicknames.lua -- Raid Lead: CludesUI's own nicknames, synced with the guild.
--
--  Set your nickname once. CludesUI sends it to your guild when you log in
--  and to your group when it changes, and keeps every nickname it hears. Raid
--  and unit frames then show nicknames in place of character names (the other
--  nickname addons CludesUI already reads still work alongside this).
--
--  Nicknames can also be pasted in, one "Character=Nickname" per line.
--
--  Account-wide (CludesUIDB.nicknames), not per profile: a guildmate's
--  nickname does not change when you switch layouts.
-------------------------------------------------------------------------------
local _, mod = ...

local MAX_LEN = 20

local function Store()
    CludesUIDB.nicknames = CludesUIDB.nicknames or {}
    return CludesUIDB.nicknames
end

local function Short(name)
    return (name or ""):match("^([^%-]+)") or name or ""
end

function mod.MyNickname()
    return CludesUIDB.cuiNickname or ""
end

--- The nickname for a character name (Name or Name-Realm), or nil.
function CludesUI.GetNickname(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    if issecretvalue and issecretvalue(name) then
        return nil
    end
    if CludesUIDB.cuiNicknamesOff then
        return nil
    end
    local storage = Store()
    return storage[name:lower()] or storage[Short(name):lower()]
end

local function Clean(nick)
    nick = (nick or ""):gsub("[|%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return nick:sub(1, MAX_LEN)
end

local function Remember(name, nick)
    nick = Clean(nick)
    local storage = Store()
    local key, short = name:lower(), Short(name):lower()
    if nick == "" then
        storage[key], storage[short] = nil, nil
    else
        storage[key], storage[short] = nick, nick
    end
    if mod.OnNicknamesChanged then
        mod.OnNicknamesChanged()
    end
end

--- Called by Comms.lua when someone announces their nickname.
function mod.ReceiveNickname(sender, nick)
    if not sender or (issecretvalue and issecretvalue(sender)) then
        return
    end
    Remember(sender, nick)
end

local lastGroupSend = 0

local function Announce(toGroup)
    local nick = mod.MyNickname()
    if nick == "" or not mod.SendNickname then
        return
    end
    if IsInGuild() then
        mod.SendNickname(nick, "GUILD")
    end
    if toGroup and IsInGroup() and GetTime() - lastGroupSend > 60 then
        lastGroupSend = GetTime()
        mod.SendNickname(nick, nil)
    end
end

--- Sets your nickname and tells the guild and group.
function mod.SetMyNickname(nick)
    CludesUIDB.cuiNickname = Clean(nick)
    Remember(UnitName("player"), CludesUIDB.cuiNickname)
    lastGroupSend = 0
    Announce(true)
end

--- Adds "Character=Nickname" lines. Returns how many were read.
function mod.ImportNicknames(textValue)
    local num = 0
    for name, nick in (textValue or ""):gmatch("([^=\n\r,;]+)=([^\n\r,;]+)") do
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then
            Remember(name, nick)
            num = num + 1
        end
    end
    return num
end

function mod.NicknameCount()
    local num = 0
    for key in pairs(Store()) do
        if not key:find("-", 1, true) then
            num = num + 1
        end
    end
    return num
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GROUP_JOINED")
eventFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_LOGIN" then
        C_Timer.After(15, function()
            Announce(false)
        end)
    else
        C_Timer.After(3, function()
            Announce(true)
        end)
    end
end)
