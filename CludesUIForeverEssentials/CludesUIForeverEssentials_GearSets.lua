if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
if not (C_EquipmentSet and C_EquipmentSet.UseEquipmentSet) then
    return
end
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
local holderFrame
local buttons = {}
local queuedSet -- a set to wear once combat ends
local previous -- the set worn before an automatic swap

local function Font()
    return CludesUI.GetFontPath("essentials")
end
local function Say(textValue)
    CludesUI.Print("|cff4cc9f0Gear Sets:|r " .. textValue)
end

--- { {id, name, icon, equipped}, ... } sorted by name.
function module.GearSetList()
    local result = {}
    for _, ident in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
        local name, iconTex, _, equipped = C_EquipmentSet.GetEquipmentSetInfo(ident)
        if name then
            result[#result + 1] = { id = ident, name = name, icon = iconTex, equipped = equipped }
        end
    end
    table.sort(result, function(lhs, rhs)
        return lhs.name < rhs.name
    end)
    return result
end

local function Wearing()
    for _, s in ipairs(module.GearSetList()) do
        if s.equipped then
            return s.id
        end
    end
end

local function SetByName(name)
    if not name or name == "" then
        return nil
    end
    return C_EquipmentSet.GetEquipmentSetID(name)
end

local function Wear(ident)
    if not ident then
        return
    end
    if InCombatLockdown() then
        queuedSet = ident
        return
    end
    queuedSet = nil
    C_EquipmentSet.UseEquipmentSet(ident)
end

local function Paint()
    for _, btn in ipairs(buttons) do
        if btn:IsShown() and btn.setID then
            local _, _, _, equipped = C_EquipmentSet.GetEquipmentSetInfo(btn.setID)
            btn.lit:SetShown(equipped and true or false)
            btn.icon:SetDesaturated(not equipped)
        end
    end
end

local function Button(index)
    local widget = buttons[index]
    if widget then
        return widget
    end
    widget = CreateFrame("Button", nil, holderFrame)
    widget.icon = widget:CreateTexture(nil, "ARTWORK")
    widget.icon:SetAllPoints()
    widget.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = widget:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    widget.lit = widget:CreateTexture(nil, "OVERLAY")
    widget.lit:SetPoint("TOPLEFT", -2, 2)
    widget.lit:SetPoint("BOTTOMRIGHT", 2, -2)
    local ar, ag, ab = CludesUI.Kit.Accent()
    widget.lit:SetColorTexture(ar, ag, ab, 0.35)
    widget.name = widget:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(widget.name, 10, "essentials")
    widget.name:SetPoint("TOP", widget, "BOTTOM", 0, -2)
    widget:SetScript("OnClick", function(self)
        if InCombatLockdown() then
            Say("you will change into " .. (self.setName or "it") .. " when the fight ends.")
        end
        previous = nil -- a choice of your own ends any automatic swap
        Wear(self.setID)
    end)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if
            not (GameTooltip.SetEquipmentSet and pcall(GameTooltip.SetEquipmentSet, GameTooltip, self.setID))
        then
            GameTooltip:SetText(self.setName or "")
        end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    buttons[index] = widget
    return widget
end

local function Layout()
    if not holderFrame then
        return
    end
    local size = Get("iconSize")
    local entries = Enabled() and module.GearSetList() or {}
    for index, s in ipairs(entries) do
        local widget = Button(index)
        widget.setID, widget.setName = s.id, s.name
        widget.icon:SetTexture(s.icon)
        widget.name:SetText(s.name)
        widget:SetSize(size, size)
        widget:ClearAllPoints()
        widget:SetPoint("LEFT", holderFrame, "LEFT", (index - 1) * (size + GAP), 0)
        widget:Show()
    end
    for index = #entries + 1, #buttons do
        buttons[index]:Hide()
        buttons[index].setID = nil
    end
    holderFrame:SetSize(math.max(1, #entries) * (size + GAP) - GAP, size)
    holderFrame:SetShown(Enabled() and (#entries > 0 or CludesUI._unlockActive) and true or false)
    Paint()
end

-- Automatic swaps: mounted wins over resting; leaving both puts back what
-- was worn before the first automatic swap.
local function AutoSwap()
    if not Enabled() then
        return
    end
    local wanted
    if IsMounted() then
        wanted = SetByName(Get("mountedSet"))
    end
    if not wanted and IsResting() then
        wanted = SetByName(Get("restingSet"))
    end
    if wanted then
        if not previous then
            previous = Wearing() or false
        end
        if Wearing() ~= wanted then
            Wear(wanted)
        end
    elseif previous ~= nil then
        local back = previous
        previous = nil
        if back then
            Wear(back)
        end
    end
end

local function Build()
    if holderFrame then
        return holderFrame
    end
    holderFrame = CreateFrame("Frame", "CludesUIGearSets", UIParent)
    holderFrame:SetSize(Get("iconSize"), Get("iconSize"))
    return holderFrame
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_REGEN_ENABLED" then
        if queuedSet then
            Wear(queuedSet)
        end
        return AutoSwap()
    elseif evt == "EQUIPMENT_SETS_CHANGED" or evt == "PLAYER_ENTERING_WORLD" then
        Layout()
        if evt == "PLAYER_ENTERING_WORLD" then
            AutoSwap()
        end
    elseif evt == "PLAYER_MOUNT_DISPLAY_CHANGED" or evt == "PLAYER_UPDATE_RESTING" then
        AutoSwap()
    else
        Paint()
    end
end)

local function Apply()
    if Enabled() then
        Build()
        for _, event in ipairs({
            "EQUIPMENT_SETS_CHANGED",
            "EQUIPMENT_SWAP_FINISHED",
            "PLAYER_EQUIPMENT_CHANGED",
            "PLAYER_REGEN_ENABLED",
            "PLAYER_ENTERING_WORLD",
            "PLAYER_MOUNT_DISPLAY_CHANGED",
            "PLAYER_UPDATE_RESTING",
        }) do
            eventFrame:RegisterEvent(event)
        end
        if not CludesUI._unlockActive then
            F.Place(holderFrame)
        end
    else
        eventFrame:UnregisterAllEvents()
        previous, queuedSet = nil, nil
    end
    Layout()
end

--- Saves what you wear as a set (a new one, or over the set of that name).
function module.SaveGearSet(name)
    name = (name or ""):match("^%s*(.-)%s*$")
    if name == "" then
        return Say("give the set a name.")
    end
    if InCombatLockdown() then
        return Say("sets cannot be saved in combat.")
    end
    local ident = C_EquipmentSet.GetEquipmentSetID(name)
    if ident then
        C_EquipmentSet.SaveEquipmentSet(ident)
        Say("saved what you wear over " .. name .. ".")
    else
        C_EquipmentSet.CreateEquipmentSet(name)
        Say("saved a new set, " .. name .. ".")
    end
end

CludesUI._GearSets = {
    Get = Get,
    Read = F.Read,
    Cfg = F.Cfg,
    Apply = Apply,
    List = module.GearSetList,
    Save = module.SaveGearSet,
}

F.Start(Apply, {
    key = "CUI_GearSets",
    label = "Gear Sets",
    order = 740,
    frame = function(build)
        if build then
            Build()
            Layout()
        end
        return holderFrame
    end,
    size = function()
        local size = Get("iconSize")
        return size * 4 + GAP * 3, size
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
