if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_ActionBarProfiles.lua  (WoW Forever only)
--  Action Bar Profiles: save every action bar slot (spells, items, macros,
--  equipment sets) and, if you like, your keybinds, under a name. Load it on
--  any character of the same class on your account. Out of combat only.
--
--  Loading puts back what the character can use: a spell it has not learned
--  yet, an item it does not carry or a macro body it has none of are
--  counted and skipped (a missing macro is made, as a character macro). An
--  empty slot in the profile empties that slot.
-------------------------------------------------------------------------------
local _, module = ...

local MAX_SLOT = 180
local F = module.Feature("actionBarProfiles", { enabled = true, bindings = false })
local Get = F.Get

local function Say(textValue)
    CludesUI.Print("|cff4cc9f0Action Bars:|r " .. textValue)
end
local function Plain(val, kindOf)
    if not (issecretvalue and issecretvalue(val)) and type(val) == (kindOf or "number") then
        return val
    end
end

local _, CLASS = UnitClass("player")

-- profiles[class][name] = { actions = { [slot] = {...} }, bindings = { {command, key1, key2}, ... } }
local function Profiles()
    local c = F.Cfg()
    c.profiles = c.profiles or {}
    c.profiles[CLASS] = c.profiles[CLASS] or {}
    return c.profiles[CLASS]
end

--- Profile names for this class, sorted.
function module.ActionProfileNames()
    local result = {}
    for name in pairs(Profiles()) do
        result[#result + 1] = name
    end
    table.sort(result)
    return result
end

local function ReadSlot(slotIndex)
    local kindOf, ident, subFrame = GetActionInfo(slotIndex)
    if not kindOf then
        return nil
    end
    local rowFrame = { kind = kindOf, id = Plain(ident), sub = subFrame }
    if kindOf == "macro" and rowFrame.id then
        local name, glyph, body = GetMacroInfo(rowFrame.id)
        rowFrame.name, rowFrame.icon, rowFrame.body = name, glyph, body
    elseif kindOf == "equipmentset" then
        rowFrame.name = ident
    end
    return rowFrame
end

function module.SaveActionProfile(name)
    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" then
        return Say("give the profile a name.")
    end
    local p = { actions = {}, saved = time() }
    for slotIndex = 1, MAX_SLOT do
        p.actions[slotIndex] = ReadSlot(slotIndex)
    end
    if Get("bindings") then
        p.bindings = {}
        for idx = 1, GetNumBindings() do
            local command, _, key1, key2 = GetBinding(idx)
            if command and (key1 or key2) then
                p.bindings[#p.bindings + 1] = { command, key1, key2 }
            end
        end
    end
    Profiles()[name] = p
    Say(("saved %s."):format(name))
end

function module.DeleteActionProfile(name)
    if Profiles()[name] then
        Profiles()[name] = nil
        Say("deleted " .. name .. ".")
    end
end

-- Puts one saved row on the cursor; true when something is on it.
local function Pickup(rowFrame)
    ClearCursor()
    if rowFrame.kind == "spell" and rowFrame.id then
        if not C_SpellBook.IsSpellKnown(rowFrame.id) then
            return false
        end
        C_Spell.PickupSpell(rowFrame.id)
    elseif rowFrame.kind == "item" and rowFrame.id then
        if (C_Item.GetItemCount(rowFrame.id) or 0) == 0 and not C_Item.IsEquippedItem(rowFrame.id) then
            return false
        end
        C_Item.PickupItem(rowFrame.id)
    elseif rowFrame.kind == "macro" and rowFrame.name then
        local slotPos = GetMacroIndexByName(rowFrame.name)
        if (not slotPos or slotPos == 0) and rowFrame.body then
            local success, made = pcall(
                CreateMacro,
                rowFrame.name,
                rowFrame.icon or "INV_Misc_QuestionMark",
                rowFrame.body,
                true
            )
            slotPos = success and made or 0
        end
        if not slotPos or slotPos == 0 then
            return false
        end
        PickupMacro(slotPos)
    elseif rowFrame.kind == "equipmentset" and rowFrame.name then
        local ident = C_EquipmentSet.GetEquipmentSetID(rowFrame.name)
        if not ident then
            return false
        end
        C_EquipmentSet.PickupEquipmentSet(ident)
    else
        return false
    end
    return GetCursorInfo() ~= nil
end

function module.LoadActionProfile(name)
    local p = Profiles()[name]
    if not p then
        return Say("there is no profile called " .. tostring(name) .. ".")
    end
    if InCombatLockdown() then
        return Say("action bars cannot change in combat.")
    end
    local placed, skipped = 0, 0
    for slotIndex = 1, MAX_SLOT do
        local rowFrame = p.actions[slotIndex]
        local current = ReadSlot(slotIndex)
        if not rowFrame then
            if current then
                PickupAction(slotIndex)
                ClearCursor()
            end
        elseif
            not (
                current
                and current.kind == rowFrame.kind
                and current.id == rowFrame.id
                and current.name == rowFrame.name
            )
        then
            if Pickup(rowFrame) then
                PlaceAction(slotIndex)
                placed = placed + 1
            else
                skipped = skipped + 1
            end
            ClearCursor()
        end
    end
    if p.bindings and Get("bindings") then
        for idx = 1, GetNumBindings() do
            local _, _, key1, key2 = GetBinding(idx)
            if key1 then
                SetBinding(key1)
            end
            if key2 then
                SetBinding(key2)
            end
        end
        for _, b in ipairs(p.bindings) do
            if b[2] then
                SetBinding(b[2], b[1])
            end
            if b[3] then
                SetBinding(b[3], b[1])
            end
        end
        SaveBindings(GetCurrentBindingSet())
    end
    Say(
        ("loaded %s: %d slot%s changed%s."):format(
            name,
            placed,
            placed == 1 and "" or "s",
            skipped > 0 and (", " .. skipped .. " skipped (not learned or not carried)") or ""
        )
    )
end

CludesUI._ActionBarProfiles = {
    Get = Get,
    Cfg = F.Cfg,
    Names = module.ActionProfileNames,
    Save = module.SaveActionProfile,
    Load = module.LoadActionProfile,
    Delete = module.DeleteActionProfile,
}

SLASH_CUIABPROFILE1 = "/cbars"
SlashCmdList.CUIABPROFILE = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "save" then
        module.SaveActionProfile(rest)
    elseif cmd == "load" then
        module.LoadActionProfile(rest)
    elseif cmd == "delete" then
        module.DeleteActionProfile(rest)
    else
        local nameList = module.ActionProfileNames()
        Say(
            "/cbars save <name>, /cbars load <name>, /cbars delete <name>. Saved for your class: "
                .. (#nameList > 0 and table.concat(nameList, ", ") or "none")
                .. "."
        )
    end
end
