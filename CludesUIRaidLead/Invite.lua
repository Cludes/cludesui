if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Invite.lua -- Raid Lead: invite a saved list and promote assistants.
--
--  The roster list and the assistant list are names separated by commas,
--  spaces or new lines (Name or Name-Realm). Invite sends invites to everyone
--  on the list who is not already in the group; a party becomes a raid as
--  soon as there is someone to convert it with. Auto Promote makes everyone
--  on the assistant list an assistant when they join, while you lead.
-------------------------------------------------------------------------------
local _, mod = ...

local PARTY_MAX = 5

local function Say(textValue) CludesUI.Print("|cff4cc9f0Raid Lead:|r " .. textValue) end

local function Settings()
    local profile = mod.RaidLeadDB()
    profile.invites = profile.invites or {}
    local cfg = profile.invites
    cfg.list = cfg.list or ""
    cfg.promote = cfg.promote or ""
    if cfg.autoPromote == nil then cfg.autoPromote = false end
    return cfg
end
mod.InviteSettings = Settings

--- Names from a list: split on commas, semicolons and white space.
function mod.SplitNames(textValue)
    local result, seen = {}, {}
    for name in (textValue or ""):gmatch("[^,;%s]+") do
        local key = name:lower()
        if not seen[key] then
            seen[key] = true
            result[#result + 1] = name
        end
    end
    return result
end

local function InGroup(name)
    local short = name:match("^([^%-]+)") or name
    return UnitInParty(short) or UnitInRaid(short) or UnitIsUnit(short, "player")
end

local pending = {}

local function InviteSome()
    if #pending == 0 then return end
    if
        IsInGroup()
        and not IsInRaid()
        and UnitIsGroupLeader("player")
        and GetNumGroupMembers() + #pending > PARTY_MAX
    then
        pcall(C_PartyInfo.ConvertToRaid)
    end
    local room = IsInRaid() and 40 - GetNumGroupMembers() or PARTY_MAX - math.max(GetNumGroupMembers(), 1)
    while room > 0 and #pending > 0 do
        local name = table.remove(pending, 1)
        if not InGroup(name) then
            pcall(C_PartyInfo.InviteUnit, name)
            room = room - 1
        end
    end
end

--- Invites everyone on the saved list who is not in the group yet.
function mod.InviteList()
    if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return Say("only the leader or an assistant can invite.")
    end
    wipe(pending)
    for _, name in ipairs(mod.SplitNames(Settings().list)) do
        if not InGroup(name) then pending[#pending + 1] = name end
    end
    if #pending == 0 then return Say("everyone on the list is already in the group.") end
    Say("inviting " .. #pending .. " player" .. (#pending == 1 and "" or "s") .. ".")
    InviteSome()
end

local promoted = {}

--- Makes everyone on the assistant list who is in the raid an assistant.
function mod.PromoteList(quiet)
    if not (IsInRaid() and UnitIsGroupLeader("player")) then
        if not quiet then Say("only the raid leader can promote assistants.") end
        return
    end
    local num = 0
    for _, name in ipairs(mod.SplitNames(Settings().promote)) do
        local short = name:match("^([^%-]+)") or name
        if UnitInRaid(short) and not UnitIsGroupAssistant(short) and not UnitIsGroupLeader(short) then
            if not (quiet and promoted[short:lower()]) then
                promoted[short:lower()] = true
                pcall(C_PartyInfo.PromoteToAssistant, short)
                num = num + 1
            end
        end
    end
    if not quiet then
        Say(num > 0 and ("promoted " .. num .. ".") or "nobody on the list needed promoting.")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function()
    if #pending > 0 then C_Timer.After(0.5, InviteSome) end
    if Settings().autoPromote then C_Timer.After(1, function() mod.PromoteList(true) end) end
end)
