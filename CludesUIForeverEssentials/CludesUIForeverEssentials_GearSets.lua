if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
if not (C_EquipmentSet and C_EquipmentSet.UseEquipmentSet) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_GearSets.lua  (WoW Forever only)
--  Gear Sets: a bar of your equipment sets (the game's own equipment
--  manager, so the same sets the character sheet shows). Click one to wear
--  it; the set you are wearing is lit. Optional automatic swaps: a set to
--  wear while mounted and one while resting, with the gear you had on put
--  back when you dismount or leave the inn.
--
--  The game will not change armour in combat, so a swap asked for in combat
--  waits for the fight to end.
-------------------------------------------------------------------------------
local _, module = ...

local DEFAULTS = { enabled = false, iconSize = 32, mountedSet = "", restingSet = "" }
local F = module.Feature("gearSets", DEFAULTS, { point = "CENTER", relPoint = "CENTER", x = -300, y = -240 })
local Get, Enabled = F.Get, F.Enabled

local GAP = 3
local holder
local buttons = {}
local queuedSet          -- a set to wear once combat ends
local previous           -- the set worn before an automatic swap

local function Font() return CludesUI.GetFontPath("essentials") end
local function Say(text) CludesUI.Print("|cff4cc9f0Gear Sets:|r " .. text) end

--- { {id, name, icon, equipped}, ... } sorted by name.
function module.GearSetList()
    local out = {}
    for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name, icon, _, equipped = C_EquipmentSet.GetEquipmentSetInfo(id)
        if name then out[#out + 1] = { id = id, name = name, icon = icon, equipped = equipped } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function Wearing()
    for _, s in ipairs(module.GearSetList()) do
        if s.equipped then return s.id end
    end
end

local function SetByName(name)
    if not name or name == "" then return nil end
    return C_EquipmentSet.GetEquipmentSetID(name)
end

local function Wear(id)
    if not id then return end
    if InCombatLockdown() then
        queuedSet = id
        return
    end
    queuedSet = nil
    C_EquipmentSet.UseEquipmentSet(id)
end

local function Paint()
    for _, b in ipairs(buttons) do
        if b:IsShown() and b.setID then
            local _, _, _, equipped = C_EquipmentSet.GetEquipmentSetInfo(b.setID)
            b.lit:SetShown(equipped and true or false)
            b.icon:SetDesaturated(not equipped)
        end
    end
end

local function Button(i)
    local b = buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, holder)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    b.lit = b:CreateTexture(nil, "OVERLAY")
    b.lit:SetPoint("TOPLEFT", -2, 2)
    b.lit:SetPoint("BOTTOMRIGHT", 2, -2)
    local ar, ag, ab = CludesUI.Kit.Accent()
    b.lit:SetColorTexture(ar, ag, ab, 0.35)
    b.name = b:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(b.name, 10, "essentials")
    b.name:SetPoint("TOP", b, "BOTTOM", 0, -2)
    b:SetScript("OnClick", function(self)
        if InCombatLockdown() then Say("you will change into " .. (self.setName or "it") .. " when the fight ends.") end
        previous = nil      -- a choice of your own ends any automatic swap
        Wear(self.setID)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if not (GameTooltip.SetEquipmentSet and pcall(GameTooltip.SetEquipmentSet, GameTooltip, self.setID)) then
            GameTooltip:SetText(self.setName or "")
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[i] = b
    return b
end

local function Layout()
    if not holder then return end
    local size = Get("iconSize")
    local list = Enabled() and module.GearSetList() or {}
    for i, s in ipairs(list) do
        local b = Button(i)
        b.setID, b.setName = s.id, s.name
        b.icon:SetTexture(s.icon)
        b.name:SetText(s.name)
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("LEFT", holder, "LEFT", (i - 1) * (size + GAP), 0)
        b:Show()
    end
    for i = #list + 1, #buttons do buttons[i]:Hide(); buttons[i].setID = nil end
    holder:SetSize(math.max(1, #list) * (size + GAP) - GAP, size)
    holder:SetShown(Enabled() and (#list > 0 or CludesUI._unlockActive) and true or false)
    Paint()
end

-- Automatic swaps: mounted wins over resting; leaving both puts back what
-- was worn before the first automatic swap.
local function AutoSwap()
    if not Enabled() then return end
    local want
    if IsMounted() then want = SetByName(Get("mountedSet")) end
    if not want and IsResting() then want = SetByName(Get("restingSet")) end
    if want then
        if not previous then previous = Wearing() or false end
        if Wearing() ~= want then Wear(want) end
    elseif previous ~= nil then
        local back = previous
        previous = nil
        if back then Wear(back) end
    end
end

local function Build()
    if holder then return holder end
    holder = CreateFrame("Frame", "CludesUIGearSets", UIParent)
    holder:SetSize(Get("iconSize"), Get("iconSize"))
    return holder
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if queuedSet then Wear(queuedSet) end
        return AutoSwap()
    elseif event == "EQUIPMENT_SETS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        Layout()
        if event == "PLAYER_ENTERING_WORLD" then AutoSwap() end
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "PLAYER_UPDATE_RESTING" then
        AutoSwap()
    else
        Paint()
    end
end)

local function Apply()
    if Enabled() then
        Build()
        for _, e in ipairs({ "EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED", "PLAYER_EQUIPMENT_CHANGED",
                             "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PLAYER_MOUNT_DISPLAY_CHANGED",
                             "PLAYER_UPDATE_RESTING" }) do
            ev:RegisterEvent(e)
        end
        if not CludesUI._unlockActive then F.Place(holder) end
    else
        ev:UnregisterAllEvents()
        previous, queuedSet = nil, nil
    end
    Layout()
end

--- Saves what you wear as a set (a new one, or over the set of that name).
function module.SaveGearSet(name)
    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" then return Say("give the set a name.") end
    if InCombatLockdown() then return Say("sets cannot be saved in combat.") end
    local id = C_EquipmentSet.GetEquipmentSetID(name)
    if id then
        C_EquipmentSet.SaveEquipmentSet(id)
        Say("saved what you wear over " .. name .. ".")
    else
        C_EquipmentSet.CreateEquipmentSet(name)
        Say("saved a new set, " .. name .. ".")
    end
end

CludesUI._GearSets = { Get = Get, Read = F.Read, Cfg = F.Cfg, Apply = Apply, List = module.GearSetList, Save = module.SaveGearSet }

F.Start(Apply, {
    key = "CUI_GearSets", label = "Gear Sets", order = 740,
    frame = function(build) if build then Build(); Layout() end; return holder end,
    size = function()
        local size = Get("iconSize")
        return size * 4 + GAP * 3, size
    end,
    noAnchorTarget = true, noSizeMatchTarget = true,
})
