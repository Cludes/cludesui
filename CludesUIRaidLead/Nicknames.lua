if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
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
local _, ns = ...

local MAX_LEN = 20

local function Store()
    CludesUIDB.nicknames = CludesUIDB.nicknames or {}
    return CludesUIDB.nicknames
end

local function Short(name)
    return (name or ""):match("^([^%-]+)") or name or ""
end

function ns.MyNickname() return CludesUIDB.cuiNickname or "" end

--- The nickname for a character name (Name or Name-Realm), or nil.
function CludesUI.GetNickname(name)
    if type(name) ~= "string" or name == "" then return nil end
    if issecretvalue and issecretvalue(name) then return nil end
    if CludesUIDB.cuiNicknamesOff then return nil end
    local store = Store()
    return store[name:lower()] or store[Short(name):lower()]
end

local function Clean(nick)
    nick = (nick or ""):gsub("[|%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return nick:sub(1, MAX_LEN)
end

local function Remember(name, nick)
    nick = Clean(nick)
    local store = Store()
    local key, short = name:lower(), Short(name):lower()
    if nick == "" then
        store[key], store[short] = nil, nil
    else
        store[key], store[short] = nick, nick
    end
    if ns.OnNicknamesChanged then ns.OnNicknamesChanged() end
end

--- Called by Comms.lua when someone announces their nickname.
function ns.ReceiveNickname(sender, nick)
    if not sender or (issecretvalue and issecretvalue(sender)) then return end
    Remember(sender, nick)
end

local lastGroupSend = 0

local function Announce(toGroup)
    local nick = ns.MyNickname()
    if nick == "" or not ns.SendNickname then return end
    if IsInGuild() then ns.SendNickname(nick, "GUILD") end
    if toGroup and IsInGroup() and GetTime() - lastGroupSend > 60 then
        lastGroupSend = GetTime()
        ns.SendNickname(nick, nil)
    end
end

--- Sets your nickname and tells the guild and group.
function ns.SetMyNickname(nick)
    CludesUIDB.cuiNickname = Clean(nick)
    Remember(UnitName("player"), CludesUIDB.cuiNickname)
    lastGroupSend = 0
    Announce(true)
end

--- Adds "Character=Nickname" lines. Returns how many were read.
function ns.ImportNicknames(text)
    local n = 0
    for name, nick in (text or ""):gmatch("([^=\n\r,;]+)=([^\n\r,;]+)") do
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then Remember(name, nick); n = n + 1 end
    end
    return n
end

function ns.NicknameCount()
    local n = 0
    for k in pairs(Store()) do if not k:find("-", 1, true) then n = n + 1 end end
    return n
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_JOINED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(15, function() Announce(false) end)
    else
        C_Timer.After(3, function() Announce(true) end)
    end
end)
