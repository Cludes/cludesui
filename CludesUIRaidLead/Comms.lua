if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Comms.lua -- Raid Lead: messages between CludesUI users in a group.
--
--  One addon-message prefix, "CUIRL". Messages:
--    V?                    asks every CludesUI user for their version
--    V|<version>           the answer
--    N|<id>|<i>|<n>|<boss>|<part>   one part of a shared reminder note
--    R|<report>            a ready check report (ReadyCheck.lua)
--    K|<nickname>          a player's nickname (Nicknames.lua), also to the guild
--    B|<seconds>           a break of that length, 0 ends it (BreakTimer.lua)
--
--  The game allows 255 characters a message and about one message a second
--  per prefix after a burst of ten, so long notes are split and paced. It also
--  refuses addon messages at times (AddOnMessageLockdown); a send that fails
--  is reported once, never retried in a loop.
-------------------------------------------------------------------------------
local _, ns = ...

local PREFIX = "CUIRL"
local PART = 200          -- characters of note per message, leaving room for the header
local PACE = 1.1          -- seconds between messages after the first burst
local BURST = 8

local function Say(text) CludesUI.Print("|cff4cc9f0Raid Lead:|r " .. text) end

local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local queue, sending, sentInBurst = {}, false, 0
local failedWarned = false

local function Pump()
    local item = table.remove(queue, 1)
    if not item then sending, sentInBurst = false, 0; return end
    local msg, channel = item[1], item[2] or Channel()
    if channel then
        local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel)
        local code = ok and (type(result) == "number" and result or 0) or 9
        if code ~= 0 and not failedWarned then
            failedWarned = true
            Say("the game would not send a message just now (code " .. code .. "). Try again out of combat.")
            wipe(queue)
        end
    end
    sentInBurst = sentInBurst + 1
    C_Timer.After(sentInBurst < BURST and 0.05 or PACE, Pump)
end

local function Send(msg, channel)
    if not (channel or Channel()) then return false end
    queue[#queue + 1] = { msg, channel }
    if not sending then
        sending, failedWarned = true, false
        Pump()
    end
    return true
end

local function MyVersion()
    return (C_AddOns.GetAddOnMetadata("CludesUI", "Version")) or "?"
end

-- Only the group leader or an assistant may hand out notes.
local function IsLeaderOrAssist(sender)
    if not sender then return false end
    local short = Ambiguate(sender, "none")
    if UnitIsGroupLeader(short) or UnitIsGroupAssistant(short) then return true end
    return UnitIsUnit(short, "player")
end

-------------------------------------------------------------------------------
--  Version check
-------------------------------------------------------------------------------
local versions = {}       -- name -> version, from the last check
ns.versions = versions

--- Asks the group for CludesUI versions and prints the result after a few seconds.
function ns.VersionCheck()
    if not Channel() then return Say("you are not in a group.") end
    wipe(versions)
    versions[UnitName("player")] = MyVersion()
    Send("V?")
    C_Timer.After(4, function()
        local have, missing = {}, {}
        for i = 1, GetNumGroupMembers() do
            local unit = IsInRaid() and ("raid" .. i) or (i == 1 and "player" or ("party" .. (i - 1)))
            local name = UnitName(unit)
            if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
                local v = versions[name]
                if v then have[#have + 1] = name .. " " .. v else missing[#missing + 1] = name end
            end
        end
        table.sort(have); table.sort(missing)
        Say(#have .. " with CludesUI: " .. (#have > 0 and table.concat(have, ", ") or "none"))
        if #missing > 0 then Say(#missing .. " without it (or did not answer): " .. table.concat(missing, ", ")) end
        if ns.OnVersionsChanged then ns.OnVersionsChanged() end
    end)
end

-------------------------------------------------------------------------------
--  Shared reminder notes
-------------------------------------------------------------------------------
local incoming = {}       -- id -> { boss, n, parts = {} }

--- Sends a reminder note to every CludesUI user in the group.
function ns.ShareNote(boss, text)
    if not Channel() then return Say("you are not in a group.") end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return Say("only the leader or an assistant can send reminders.")
    end
    boss = (boss or "any"):gsub("|", "")
    text = (text or ""):gsub("|", "||")  -- keep colour codes literal in transit
    local id = tostring(math.random(10000, 99999))
    local n = math.max(1, math.ceil(#text / PART))
    for i = 1, n do
        Send(("N|%s|%d|%d|%s|%s"):format(id, i, n, boss, text:sub((i - 1) * PART + 1, i * PART)))
    end
    Say(("sending the %s reminders to the group (%d message%s)."):format(boss, n, n == 1 and "" or "s"))
end

local function OnNotePart(sender, id, i, n, boss, part)
    if not IsLeaderOrAssist(sender) then return end
    if UnitIsUnit(Ambiguate(sender, "none"), "player") then return end
    local key = sender .. id
    local entry = incoming[key] or { boss = boss, n = n, parts = {}, got = 0 }
    incoming[key] = entry
    if not entry.parts[i] then
        entry.parts[i] = part
        entry.got = entry.got + 1
    end
    if entry.got >= entry.n then
        incoming[key] = nil
        local text = table.concat(entry.parts):gsub("||", "|")
        if ns.ReceiveSharedNote then ns.ReceiveSharedNote(Ambiguate(sender, "none"), entry.boss, text) end
    end
end

-------------------------------------------------------------------------------
--  Ready check reports and nicknames
-------------------------------------------------------------------------------
function ns.SendReadyReport(report) Send("R|" .. report) end

--- channel nil = the group; "GUILD" = the guild.
function ns.SendNickname(nick, channel) Send("K|" .. nick, channel) end

function ns.SendBreak(seconds) return Send("B|" .. seconds) end

-------------------------------------------------------------------------------
--  Receiving
-------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
    if prefix ~= PREFIX or type(msg) ~= "string" then return end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then return end
    if msg == "V?" then
        Send("V|" .. MyVersion())
    elseif msg:sub(1, 2) == "R|" then
        if ns.ReceiveReadyReport then ns.ReceiveReadyReport(Ambiguate(sender, "none"), msg:sub(3)) end
    elseif msg:sub(1, 2) == "K|" then
        if ns.ReceiveNickname then ns.ReceiveNickname(sender, msg:sub(3, 40)) end
    elseif msg:sub(1, 2) == "B|" then
        local seconds = tonumber(msg:match("^B|(%d+)$"))
        if seconds and IsLeaderOrAssist(sender) and ns.ReceiveBreak then
            local who = Ambiguate(sender, "none")
            ns.ReceiveBreak(seconds, not UnitIsUnit(who, "player") and who or nil)
        end
    elseif msg:sub(1, 2) == "V|" then
        versions[Ambiguate(sender, "none")] = msg:sub(3, 40)
    elseif msg:sub(1, 2) == "N|" then
        local id, i, n, boss, part = msg:match("^N|(%d+)|(%d+)|(%d+)|([^|]*)|(.*)$")
        i, n = tonumber(i), tonumber(n)
        if id and i and n and n <= 60 and i >= 1 and i <= n then
            OnNotePart(sender, id, i, n, boss, part)
        end
    end
end)
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
