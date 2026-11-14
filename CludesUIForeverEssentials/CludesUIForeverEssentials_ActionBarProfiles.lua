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

local function Say(text)
    CludesUI.Print("|cff4cc9f0Action Bars:|r " .. text)
end
local function Plain(v, kind)
    if not (issecretvalue and issecretvalue(v)) and type(v) == (kind or "number") then
        return v
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
    local out = {}
    for name in pairs(Profiles()) do
        out[#out + 1] = name
    end
    table.sort(out)
    return out
end

local function ReadSlot(slot)
    local kind, id, sub = GetActionInfo(slot)
    if not kind then
        return nil
    end
    local row = { kind = kind, id = Plain(id), sub = sub }
    if kind == "macro" and row.id then
        local name, icon, body = GetMacroInfo(row.id)
        row.name, row.icon, row.body = name, icon, body
    elseif kind == "equipmentset" then
        row.name = id
    end
    return row
end

function module.SaveActionProfile(name)
    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" then
        return Say("give the profile a name.")
    end
    local p = { actions = {}, saved = time() }
    for slot = 1, MAX_SLOT do
        p.actions[slot] = ReadSlot(slot)
    end
    if Get("bindings") then
        p.bindings = {}
        for i = 1, GetNumBindings() do
            local command, _, key1, key2 = GetBinding(i)
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
local function Pickup(row)
    ClearCursor()
    if row.kind == "spell" and row.id then
        if not C_SpellBook.IsSpellKnown(row.id) then
            return false
        end
        C_Spell.PickupSpell(row.id)
    elseif row.kind == "item" and row.id then
        if (C_Item.GetItemCount(row.id) or 0) == 0 and not C_Item.IsEquippedItem(row.id) then
            return false
        end
        C_Item.PickupItem(row.id)
    elseif row.kind == "macro" and row.name then
        local index = GetMacroIndexByName(row.name)
        if (not index or index == 0) and row.body then
            local ok, made = pcall(CreateMacro, row.name, row.icon or "INV_Misc_QuestionMark", row.body, true)
            index = ok and made or 0
        end
        if not index or index == 0 then
            return false
        end
        PickupMacro(index)
    elseif row.kind == "equipmentset" and row.name then
        local id = C_EquipmentSet.GetEquipmentSetID(row.name)
        if not id then
            return false
        end
        C_EquipmentSet.PickupEquipmentSet(id)
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
    for slot = 1, MAX_SLOT do
        local row = p.actions[slot]
        local current = ReadSlot(slot)
        if not row then
            if current then
                PickupAction(slot)
                ClearCursor()
            end
        elseif
            not (current and current.kind == row.kind and current.id == row.id and current.name == row.name)
        then
            if Pickup(row) then
                PlaceAction(slot)
                placed = placed + 1
            else
                skipped = skipped + 1
            end
            ClearCursor()
        end
    end
    if p.bindings and Get("bindings") then
        for i = 1, GetNumBindings() do
            local _, _, key1, key2 = GetBinding(i)
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
        local names = module.ActionProfileNames()
        Say(
            "/cbars save <name>, /cbars load <name>, /cbars delete <name>. Saved for your class: "
                .. (#names > 0 and table.concat(names, ", ") or "none")
                .. "."
        )
    end
end
