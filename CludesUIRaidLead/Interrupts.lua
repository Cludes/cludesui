if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Interrupts.lua -- Raid Lead: kick rotation.
--
--  A box that says whose interrupt is next: the cast number and the name,
--  lit yellow when you are next and red, with a sound, when it is yours now.
--
--  The order comes from the boss's note (Raid Lead > Reminders), as a block:
--      intstart
--      Alice Bob Carol
--      Dave Erin
--      intend
--  Each line is one rotation (one mob or one team); you follow the line
--  with your name or nickname on it. Without a note, the Kick Order typed
--  on the Setup page is used. Each time the tracked unit (your focus, or
--  boss1) finishes or loses a cast, the turn moves to the next name.
--
--  Under 12.1 an addon cannot tell which spell a boss casts in combat, so
--  every cast of the tracked unit counts. Put the mob you kick on focus.
-------------------------------------------------------------------------------
local _, mod = ...

local W, H = 180, 34

function mod.KickSettings()
    local p = mod.RaidLeadDB()
    p.kicks = p.kicks or {}
    local s = p.kicks
    if s.enabled == nil then
        s.enabled = true
    end
    if s.unit == nil then
        s.unit = "focus"
    end
    if s.sound == nil then
        s.sound = true
    end
    if s.order == nil then
        s.order = ""
    end
    return s
end

local function Lower(s)
    return (s or ""):lower()
end

--- The rotation lines between intstart and intend in a note.
function mod.ParseKickBlock(textValue)
    local lines, inside = {}, false
    for raw in (textValue or ""):gmatch("[^\r\n]+") do
        local line = raw:gsub("|+c%x%x%x%x%x%x%x%x", ""):gsub("|+r", ""):match("^%s*(.-)%s*$")
        local l = Lower(line)
        if l == "intstart" then
            inside = true
        elseif l == "intend" then
            break
        elseif inside and line ~= "" then
            local nameList = {}
            for n in line:gmatch("%S+") do
                nameList[#nameList + 1] = n
            end
            if #nameList > 0 then
                lines[#lines + 1] = nameList
            end
        end
    end
    return lines
end

local function IsMe(name)
    local me = UnitName("player")
    local nick = CludesUI.GetNickname and CludesUI.GetNickname(me)
    local n = Lower(name):gsub("%-.*$", "")
    return n == Lower(me) or (nick and n == Lower(nick))
end

--- The rotation you are on, from a note's block or the typed order.
function mod.MyKickRotation(noteText)
    local lines = mod.ParseKickBlock(noteText)
    if #lines == 0 then
        local typed = mod.KickSettings().order
        if typed ~= "" then
            lines = { {} }
            for n in typed:gmatch("%S+") do
                table.insert(lines[1], n)
            end
        end
    end
    for _, nameList in ipairs(lines) do
        for idx, n in ipairs(nameList) do
            if IsMe(n) then
                return nameList, idx
            end
        end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Display
-------------------------------------------------------------------------------
local box, num, labelText
local rot -- { names, mine, count, casting }

local function Font()
    return CludesUI.GetFontPath(nil)
end

local function Build()
    if box then
        return
    end
    box = CreateFrame("Frame", "CludesUIRaidLeadKicks", UIParent)
    box:SetSize(W, H)
    CludesUI.Kit.Panel(box)
    num = box:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(num, 20, nil)
    num:SetPoint("LEFT", 8, 0)
    labelText = box:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(labelText, 15, nil)
    labelText:SetPoint("LEFT", num, "RIGHT", 10, 0)
    box:Hide()
    mod.ApplyKickPosition()
end

function mod.ApplyKickPosition()
    if not box or InCombatLockdown() then
        return
    end
    local p = mod.KickSettings().pos
    box:ClearAllPoints()
    if p then
        box:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else
        box:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    end
end

local function Paint()
    if not (box and rot) then
        return
    end
    local n = #rot.names
    local who = rot.names[rot.count]
    local nextUp = rot.count % n + 1
    local display = (CludesUI.GetNickname and CludesUI.GetNickname(who)) or who
    num:SetText(rot.count)
    if rot.count == rot.mine and rot.casting then
        box._kitBg:SetColorTexture(0.80, 0.15, 0.12, 0.95)
        labelText:SetText("KICK NOW")
    elseif rot.count == rot.mine then
        box._kitBg:SetColorTexture(0.85, 0.65, 0.10, 0.95)
        labelText:SetText("You are next")
    elseif nextUp == rot.mine then
        box._kitBg:SetColorTexture(0.10, 0.11, 0.14, 0.92)
        labelText:SetText(display .. "  |cffffd060then you|r")
    else
        box._kitBg:SetColorTexture(0.10, 0.11, 0.14, 0.92)
        labelText:SetText(display)
    end
    box:Show()
end

local ev = CreateFrame("Frame")

local function Stop()
    rot = nil
    ev:UnregisterEvent("UNIT_SPELLCAST_START")
    ev:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    ev:UnregisterEvent("UNIT_SPELLCAST_STOP")
    ev:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    ev:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    if box then
        box:Hide()
    end
end
mod.StopKicks = Stop

--- Starts the rotation from a note (nil: the typed order).
function mod.StartKicks(noteText)
    local s = mod.KickSettings()
    if not s.enabled then
        return
    end
    local nameList, mine = mod.MyKickRotation(noteText)
    if not nameList then
        return Stop()
    end
    Build()
    rot = { names = nameList, mine = mine, count = 1, casting = false }
    for _, event in ipairs({
        "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_INTERRUPTED",
    }) do
        ev:RegisterUnitEvent(event, s.unit)
    end
    Paint()
end

ev:SetScript("OnEvent", function(_, evt)
    if evt == "ENCOUNTER_START" or evt == "PLAYER_REGEN_DISABLED" then
        return
    end
    if not rot then
        return
    end
    if evt == "UNIT_SPELLCAST_START" or evt == "UNIT_SPELLCAST_CHANNEL_START" then
        rot.casting = true
        if rot.count == rot.mine and mod.KickSettings().sound then
            PlaySound(SOUNDKIT.RAID_WARNING, "Master")
        end
    elseif rot.casting then
        -- A cast that ended (kicked or not) passes the turn on.
        rot.casting = false
        rot.count = rot.count % #rot.names + 1
    end
    Paint()
end)

local boss = CreateFrame("Frame")
boss:RegisterEvent("ENCOUNTER_START")
boss:RegisterEvent("ENCOUNTER_END")
boss:RegisterEvent("PLAYER_REGEN_DISABLED")
boss:RegisterEvent("PLAYER_REGEN_ENABLED")
boss:RegisterEvent("PLAYER_ENTERING_WORLD")
local registered, inEncounter
boss:SetScript("OnEvent", function(_, evt, _, encounterName)
    if evt == "PLAYER_ENTERING_WORLD" then
        if registered or InCombatLockdown() or not CludesUI.RegisterUnlockElements then
            return
        end
        Build()
        registered = true
        CludesUI:RegisterUnlockElements({
            CludesUI.MakeUnlockElement({
                key = "RLEAD_Kicks",
                label = "Kick Rotation",
                group = "Raid Lead",
                order = 664,
                noAnchorTarget = true,
                noResize = true,
                isHidden = function()
                    return not mod.KickSettings().enabled
                end,
                getFrame = function()
                    return box
                end,
                getSize = function()
                    return W, H
                end,
                savePos = function(_, anchorPoint, relPoint, posX, posY)
                    mod.KickSettings().pos = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                end,
                loadPos = function()
                    return mod.KickSettings().pos
                end,
                clearPos = function()
                    mod.KickSettings().pos = nil
                end,
                applyPos = mod.ApplyKickPosition,
            }),
        }, "CludesUIRaidLead")
    elseif evt == "ENCOUNTER_START" then
        inEncounter = true
        local note = type(encounterName) == "string"
            and not (issecretvalue and issecretvalue(encounterName))
            and mod.NoteFor
            and mod.NoteFor(encounterName)
        mod.StartKicks(note or nil)
    elseif evt == "ENCOUNTER_END" then
        inEncounter = false
        Stop()
    elseif evt == "PLAYER_REGEN_DISABLED" then
        -- Trash and keys: the typed order runs for any fight in a group.
        if not inEncounter and IsInGroup() and mod.KickSettings().order ~= "" then
            mod.StartKicks(nil)
        end
    elseif evt == "PLAYER_REGEN_ENABLED" then
        if not inEncounter then
            Stop()
        end
    end
end)

--- Shows the box with a sample rotation, for placing and checking it.
function mod.PreviewKicks()
    Build()
    rot = { names = { UnitName("player"), "Alice", "Bob" }, mine = 1, count = 1, casting = false }
    Paint()
    C_Timer.After(8, function()
        if rot and rot.names[2] == "Alice" then
            Stop()
        end
    end)
end
