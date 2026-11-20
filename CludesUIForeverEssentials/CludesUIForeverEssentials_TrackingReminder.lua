if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_TrackingReminder.lua  (WoW Forever only)
--  Tracking Reminder: a row of icons for the tracking you know but have not
--  turned on (Find Treasure, the hunter tracks, Druid Track Humanoids, Sense
--  Undead, Sense Demons, and Find Herbs / Find Minerals unless turned off).
--  Click an icon to cast it. Forever can track several things at once, so
--  each one missing gets its own icon.
--
--  The icons are secure spell buttons. They are laid out only out of
--  combat, and a state driver hides the row in combat, so nothing protected
--  changes while fighting. What is on comes from the minimap's tracking list
--  (C_Minimap.GetTrackingInfo); a spell missing from that list is checked
--  on the player's buffs instead.
-------------------------------------------------------------------------------
local _, module = ...

local DEFAULTS = { enabled = false, iconSize = 32, gathering = true }
local F =
    module.Feature("trackingReminder", DEFAULTS, { point = "CENTER", relPoint = "CENTER", x = 260, y = 170 })
local Get, Enabled = F.Get, F.Enabled

-- Spell IDs checked against the Forever spell table (wago.tools SpellName,
-- build 1.60.1.70888).
local SPELLS = {
    2481, -- Find Treasure (Dwarf)
    1494,
    19883,
    19884,
    19885,
    19880,
    19878,
    19882,
    19879, -- Hunter tracks
    5225, -- Track Humanoids (Druid, Cat Form only)
    5502, -- Sense Undead (Paladin)
    5500, -- Sense Demons (Warlock)
}
local GATHERING = { 2383, 2580 } -- Find Herbs, Find Minerals
local CAT_ONLY = { [5225] = true }
local CAT_FORM = 1 -- GetShapeshiftFormID() in Cat Form

local GAP = 4
local holderFrame
local buttons = {}
local dirty = true

local function Known(ident)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(ident)
    end
    return IsSpellKnown and IsSpellKnown(ident) or false
end

-- [spellID] = true for each tracking that is on, and whether the list was read.
local function ActiveTracking()
    local on, listed = {}, {}
    local num = C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetNumTrackingTypes() or 0
    for index = 1, num do
        local a, _, c, _, _, frame = C_Minimap.GetTrackingInfo(index)
        local spellId, isActive
        if type(a) == "table" then
            spellId, isActive = a.spellID, a.active
        else
            spellId, isActive = frame, c
        end
        if spellId then
            listed[spellId] = true
            if isActive then
                on[spellId] = true
            end
        end
    end
    return on, listed
end

local function HasBuff(ident)
    local success, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ident)
    return success and aura ~= nil
end

-- The spells to remind about now, in list order.
local function Missing()
    local on, listed = ActiveTracking()
    local category = GetShapeshiftFormID and GetShapeshiftFormID() == CAT_FORM
    local result = {}
    local function Consider(ident)
        if not Known(ident) or on[ident] then
            return
        end
        if CAT_ONLY[ident] and not category then
            return
        end
        if not listed[ident] and HasBuff(ident) then
            return
        end
        result[#result + 1] = ident
    end
    for _, ident in ipairs(SPELLS) do
        Consider(ident)
    end
    if Get("gathering") then
        for _, ident in ipairs(GATHERING) do
            Consider(ident)
        end
    end
    return result
end

local function Build()
    if holderFrame then
        return holderFrame
    end
    holderFrame = CreateFrame("Frame", "CludesUITrackingReminder", UIParent)
    holderFrame:SetSize(Get("iconSize"), Get("iconSize"))
    RegisterStateDriver(holderFrame, "visibility", "[combat] hide; show")
    return holderFrame
end

local function Button(index)
    local widget = buttons[index]
    if widget then
        return widget
    end
    widget = CreateFrame("Button", nil, holderFrame, "SecureActionButtonTemplate")
    widget:RegisterForClicks("AnyUp", "AnyDown")
    widget:SetAttribute("type", "spell")
    widget.icon = widget:CreateTexture(nil, "ARTWORK")
    widget.icon:SetAllPoints()
    widget.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = widget:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    widget:SetScript("OnEnter", function(self)
        if not self.spellID then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetSpellByID(self.spellID)
        GameTooltip:AddLine(CludesUI.L("Click to turn this tracking on."), 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    buttons[index] = widget
    return widget
end

-- Lays the row out again. Out of combat only: the buttons are secure.
local function Refresh()
    if not holderFrame then
        return
    end
    if InCombatLockdown() then
        dirty = true
        return
    end
    dirty = false
    local size = Get("iconSize")
    local entries = Enabled() and Missing() or {}
    for index, ident in ipairs(entries) do
        local widget = Button(index)
        widget.spellID = ident
        widget:SetAttribute("spell", ident)
        widget.icon:SetTexture(C_Spell.GetSpellTexture(ident))
        widget:SetSize(size, size)
        widget:ClearAllPoints()
        widget:SetPoint("LEFT", holderFrame, "LEFT", (index - 1) * (size + GAP), 0)
        widget:Show()
    end
    for index = #entries + 1, #buttons do
        buttons[index]:Hide()
        buttons[index].spellID = nil
    end
    holderFrame:SetSize(math.max(1, #entries) * (size + GAP) - GAP, size)
end

local eventFrame = CreateFrame("Frame")
local EVENTS = {
    "MINIMAP_UPDATE_TRACKING",
    "SPELLS_CHANGED",
    "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD",
}
local queued
eventFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_REGEN_ENABLED" and not dirty then
        return
    end
    -- Aura and spell events come in bursts: one layout once they settle.
    if queued then
        return
    end
    queued = true
    C_Timer.After(0.3, function()
        queued = nil
        Refresh()
    end)
end)

local function Apply()
    if Enabled() then
        Build()
        for _, event in ipairs(EVENTS) do
            eventFrame:RegisterEvent(event)
        end
        eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
        if not CludesUI._unlockActive and not InCombatLockdown() then
            F.Place(holderFrame)
        end
    else
        eventFrame:UnregisterAllEvents()
    end
    Refresh()
end

-- Entry points for the options page.
CludesUI._TrackingReminder = { Get = Get, Read = F.Read, Cfg = F.Cfg, Apply = Apply }

F.Start(Apply, {
    key = "CUI_TrackingReminder",
    label = "Tracking Reminder",
    order = 735,
    frame = function(build)
        if build then
            Build()
        end
        return holderFrame
    end,
    size = function()
        local size = Get("iconSize")
        return size * 3 + GAP * 2, size
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
