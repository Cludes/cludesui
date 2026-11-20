if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Setup.lua -- Raid Lead: the setup manager.
--
--  /raidlead roles   tanks, melee, ranged, healers, filling group 1 upward
--  /raidlead split   two balanced halves (for split runs)
--  /raidlead undo    puts everyone back where they were before the last sort
--  /raidlead stop    stops a sort that is under way
--
--  The plan comes from Planner.lua. This file reads the roster, then makes
--  ONE move and waits for the game to report the new roster before the next,
--  because raid indexes can change after every move.
--
--  The game refuses group moves in combat and from anyone who is not the raid
--  leader or an assistant, so both are checked first and a sort stops when
--  combat starts. Nothing here runs until a command is typed.
-------------------------------------------------------------------------------
local _, mod = ...
local Planner = mod.Planner
CludesUI._ModuleNS["CludesUIRaidLead"] = mod
local CUI = _G.CludesUI

local MAX_MOVES = 120 -- a 40-player raid needs under 40; this is the runaway stop
local STEP_WAIT = 0.6 -- seconds to wait for a roster update before trying again

local job -- { target, moves, label } while a sort is under way
local lastLayout -- target[name] = group from before the last sort
local widget = CreateFrame("Frame")

local function Say(textValue)
    local line = "|cff4cc9f0Raid Lead:|r " .. textValue
    if CUI and CUI.Print then
        CUI.Print(line)
    else
        print(line)
    end
end

-- The raid as the planner wants it. Members whose name the game will not give
-- in plain form (it hides identities during some encounters) are left out, so
-- they simply stay where they are.
local function Roster()
    local members = {}
    for idx = 1, GetNumGroupMembers() do
        local name, _, subgroup, _, _, class, _, _, _, _, _, combatRole = GetRaidRosterInfo(idx)
        local hidden = issecretvalue
            and (issecretvalue(name) or issecretvalue(subgroup) or issecretvalue(class))
        if name and not hidden then
            members[#members + 1] = {
                index = idx,
                name = name,
                group = subgroup,
                role = combatRole or "NONE",
                class = class,
            }
        end
    end
    return members
end

local function CanSort()
    if not IsInRaid() then
        return false, "you are not in a raid group."
    end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return false, "only the raid leader or an assistant can move players."
    end
    if InCombatLockdown() then
        return false, "the game does not allow group moves in combat."
    end
    return true
end

local function Finish(textValue)
    job = nil
    widget:UnregisterEvent("GROUP_ROSTER_UPDATE")
    widget:UnregisterEvent("PLAYER_REGEN_DISABLED")
    if textValue then
        Say(textValue)
    end
end

local function Step()
    if not job then
        return
    end
    local success, why = CanSort()
    if not success then
        return Finish("stopped: " .. why)
    end
    local move = Planner.NextMove(Roster(), job.target)
    if not move then
        return Finish(job.label .. " done in " .. job.moves .. " moves.")
    end
    job.moves = job.moves + 1
    if job.moves > MAX_MOVES then
        return Finish(
            "stopped after " .. MAX_MOVES .. " moves without finishing. Type /raidlead undo to go back."
        )
    end
    if move.op == "set" then
        SetRaidSubgroup(move.index, move.group)
    else
        SwapRaidSubgroup(move.index, move.other)
    end
    -- The roster event normally arrives first and drives the next move. This
    -- covers a move the game ignored: it only acts if this same move is still
    -- the latest one and no roster update has answered it.
    local mine, number = job, job.moves
    C_Timer.After(STEP_WAIT, function()
        if job == mine and mine.moves == number and mine.seen < number then
            mine.seen = number
            Step()
        end
    end)
end

widget:SetScript("OnEvent", function(_, evt)
    if not job then
        return
    end
    if evt == "PLAYER_REGEN_DISABLED" then
        Finish("stopped: combat started. Type the command again afterwards.")
    else
        job.seen = job.moves
        Step()
    end
end)

local function KindLine(cfg)
    local parts = {}
    if cfg.TANK > 0 then
        parts[#parts + 1] = cfg.TANK .. " tank"
    end
    if cfg.MELEE > 0 then
        parts[#parts + 1] = cfg.MELEE .. " melee"
    end
    if cfg.RANGED > 0 then
        parts[#parts + 1] = cfg.RANGED .. " ranged"
    end
    if cfg.HEALER > 0 then
        parts[#parts + 1] = cfg.HEALER .. " heal"
    end
    return table.concat(parts, ", ")
end

local function Start(labelText, target, members, keepUndo)
    if not keepUndo then
        lastLayout = Planner.Snapshot(members)
    end
    local summary = Planner.Summary(members, target)
    for g = 1, 8 do
        if summary[g] then
            Say("group " .. g .. ": " .. KindLine(summary[g]))
        end
    end
    job = { target = target, moves = 0, seen = 0, label = labelText }
    widget:RegisterEvent("GROUP_ROSTER_UPDATE")
    widget:RegisterEvent("PLAYER_REGEN_DISABLED")
    Step()
end

local function Command(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "stop" then
        if job then
            Finish("stopped.")
        else
            Say("nothing is being sorted.")
        end
        return
    end
    if cmd == "break" then
        return mod.StartBreak((msg or ""):match("^%s*%S+%s+(%S+)") or "")
    end
    if cmd == "" then
        if InCombatLockdown() then
            return Say("the settings panel cannot open in combat.")
        end
        C_Timer.After(0, function()
            if InCombatLockdown() then
                return
            end
            if CUI.EnsureOptionsLoaded and not CUI.EnsureOptionsLoaded() then
                return
            end
            CUI:ShowModule("CludesUIRaidLead")
        end)
        return
    end
    if cmd ~= "roles" and cmd ~= "split" and cmd ~= "undo" then
        Say("commands:")
        Say("/raidlead roles  -  tanks, melee, ranged, healers, from group 1 up")
        Say("/raidlead split  -  two balanced halves")
        Say("/raidlead undo   -  back to how the groups were before the last sort")
        Say("/raidlead stop   -  stop a sort that is under way")
        Say("/raidlead break 5  -  a 5 minute break for the group (0 ends it)")
        return
    end
    if job then
        return Say("a sort is already under way. Type /raidlead stop first.")
    end
    local success, why = CanSort()
    if not success then
        return Say("cannot sort: " .. why)
    end
    local members = Roster()
    if cmd == "undo" then
        if not lastLayout then
            return Say("there is no earlier layout to go back to.")
        end
        local target = lastLayout
        lastLayout = nil
        Start("Undo", target, members, true)
    elseif cmd == "roles" then
        Start("Sort by role", Planner.ByRole(members), members)
    else
        local target, perSide = Planner.Split(members)
        Say(
            "side one is groups 1 to "
                .. perSide
                .. ", side two is groups "
                .. (perSide + 1)
                .. " to "
                .. (perSide * 2)
                .. "."
        )
        Start("Split", target, members)
    end
end

mod.Command = Command

SLASH_CUIRAIDLEAD1 = "/raidlead"
SLASH_CUIRAIDLEAD2 = "/crl"
SlashCmdList.CUIRAIDLEAD = Command
