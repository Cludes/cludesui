if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
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
--    D|<kind>              the sender dropped a feast, cauldron ... (GroupHelpers.lua)
--
--  The game allows 255 characters a message and about one message a second
--  per prefix after a burst of ten, so long notes are split and paced. It also
--  refuses addon messages at times (AddOnMessageLockdown); a send that fails
--  is reported once, never retried in a loop.
-------------------------------------------------------------------------------
local _, mod = ...

local PREFIX = "CUIRL"
local PART = 200 -- characters of note per message, leaving room for the header
local PACE = 1.1 -- seconds between messages after the first burst
local BURST = 8

local function Say(textValue)
    CludesUI.Print("|cff4cc9f0Raid Lead:|r " .. textValue)
end

local function Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid() then
        return "RAID"
    end
    if IsInGroup() then
        return "PARTY"
    end
    return nil
end

local queue, sending, sentInBurst = {}, false, 0
local failedWarned = false

local function Pump()
    local itemInfo = table.remove(queue, 1)
    if not itemInfo then
        sending, sentInBurst = false, 0
        return
    end
    local msg, channel = itemInfo[1], itemInfo[2] or Channel()
    if channel then
        local success, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel)
        local code = success and (type(result) == "number" and result or 0) or 9
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
    if not (channel or Channel()) then
        return false
    end
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
    if not sender then
        return false
    end
    local short = Ambiguate(sender, "none")
    if UnitIsGroupLeader(short) or UnitIsGroupAssistant(short) then
        return true
    end
    return UnitIsUnit(short, "player")
end

-------------------------------------------------------------------------------
--  Version check
-------------------------------------------------------------------------------
local versions = {} -- name -> version, from the last check
mod.versions = versions

--- Asks the group for CludesUI versions and prints the result after a few seconds.
function mod.VersionCheck()
    if not Channel() then
        return Say("you are not in a group.")
    end
    wipe(versions)
    versions[UnitName("player")] = MyVersion()
    Send("V?")
    C_Timer.After(4, function()
        local have, missing = {}, {}
        for idx = 1, GetNumGroupMembers() do
            local unitToken = IsInRaid() and ("raid" .. idx)
                or (idx == 1 and "player" or ("party" .. (idx - 1)))
            local name = UnitName(unitToken)
            if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
                local val = versions[name]
                if val then
                    have[#have + 1] = name .. " " .. val
                else
                    missing[#missing + 1] = name
                end
            end
        end
        table.sort(have)
        table.sort(missing)
        Say(#have .. " with CludesUI: " .. (#have > 0 and table.concat(have, ", ") or "none"))
        if #missing > 0 then
            Say(#missing .. " without it (or did not answer): " .. table.concat(missing, ", "))
        end
        if mod.OnVersionsChanged then
            mod.OnVersionsChanged()
        end
    end)
end

-------------------------------------------------------------------------------
--  Shared reminder notes
-------------------------------------------------------------------------------
local incoming = {} -- id -> { boss, n, parts = {} }

--- Sends a reminder note to every CludesUI user in the group.
function mod.ShareNote(boss, textValue)
    if not Channel() then
        return Say("you are not in a group.")
    end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return Say("only the leader or an assistant can send reminders.")
    end
    boss = (boss or "any"):gsub("|", "")
    textValue = (textValue or ""):gsub("|", "||") -- keep colour codes literal in transit
    local ident = tostring(math.random(10000, 99999))
    local num = math.max(1, math.ceil(#textValue / PART))
    for idx = 1, num do
        Send(
            ("N|%s|%d|%d|%s|%s"):format(
                ident,
                idx,
                num,
                boss,
                textValue:sub((idx - 1) * PART + 1, idx * PART)
            )
        )
    end
    Say(("sending the %s reminders to the group (%d message%s)."):format(boss, num, num == 1 and "" or "s"))
end

local function OnNotePart(sender, ident, idx, num, boss, part)
    if not IsLeaderOrAssist(sender) then
        return
    end
    if UnitIsUnit(Ambiguate(sender, "none"), "player") then
        return
    end
    local key = sender .. ident
    local record = incoming[key] or { boss = boss, n = num, parts = {}, got = 0 }
    incoming[key] = record
    if not record.parts[idx] then
        record.parts[idx] = part
        record.got = record.got + 1
    end
    if record.got >= record.n then
        incoming[key] = nil
        local textValue = table.concat(record.parts):gsub("||", "|")
        if mod.ReceiveSharedNote then
            mod.ReceiveSharedNote(Ambiguate(sender, "none"), record.boss, textValue)
        end
    end
end

-------------------------------------------------------------------------------
--  Ready check reports and nicknames
-------------------------------------------------------------------------------
function mod.SendReadyReport(report)
    Send("R|" .. report)
end

--- channel nil = the group; "GUILD" = the guild.
function mod.SendNickname(nick, channel)
    Send("K|" .. nick, channel)
end

function mod.SendBreak(seconds)
    return Send("B|" .. seconds)
end

function mod.SendDrop(kindOf)
    return Send("D|" .. kindOf)
end

-------------------------------------------------------------------------------
--  Receiving
-------------------------------------------------------------------------------
local widget = CreateFrame("Frame")
widget:RegisterEvent("CHAT_MSG_ADDON")
widget:SetScript("OnEvent", function(_, _, prefixText, msg, channel, sender)
    if prefixText ~= PREFIX or type(msg) ~= "string" then
        return
    end
    if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then
        return
    end
    if msg == "V?" then
        Send("V|" .. MyVersion())
    elseif msg:sub(1, 2) == "R|" then
        if mod.ReceiveReadyReport then
            mod.ReceiveReadyReport(Ambiguate(sender, "none"), msg:sub(3))
        end
    elseif msg:sub(1, 2) == "K|" then
        if mod.ReceiveNickname then
            mod.ReceiveNickname(sender, msg:sub(3, 40))
        end
    elseif msg:sub(1, 2) == "D|" then
        if mod.ReceiveDrop then
            mod.ReceiveDrop(Ambiguate(sender, "none"), msg:sub(3, 20))
        end
    elseif msg:sub(1, 2) == "B|" then
        local seconds = tonumber(msg:match("^B|(%d+)$"))
        if seconds and IsLeaderOrAssist(sender) and mod.ReceiveBreak then
            local who = Ambiguate(sender, "none")
            mod.ReceiveBreak(seconds, not UnitIsUnit(who, "player") and who or nil)
        end
    elseif msg:sub(1, 2) == "V|" then
        versions[Ambiguate(sender, "none")] = msg:sub(3, 40)
    elseif msg:sub(1, 2) == "N|" then
        local ident, idx, num, boss, part = msg:match("^N|(%d+)|(%d+)|(%d+)|([^|]*)|(.*)$")
        idx, num = tonumber(idx), tonumber(num)
        if ident and idx and num and num <= 60 and idx >= 1 and idx <= num then
            OnNotePart(sender, ident, idx, num, boss, part)
        end
    end
end)
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
