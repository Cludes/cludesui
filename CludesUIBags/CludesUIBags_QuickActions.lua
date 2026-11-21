if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIBags_QuickActions.lua
--  Quick Actions (Bag Top Bar Icons, off by default): the header icon toggles a
--  mode that dims every bag item but the ones a known spell works on, marked
--  with its icon; a click casts it. Alt-click does the same outside the mode.
--
--  Taint: one SecureActionButtonTemplate button of our own (type "spell" with
--  target-bag / target-slot), moved, set and shown out of combat only over the
--  hovered slot, hidden on PLAYER_REGEN_DISABLED. Slots only get OnEnter /
--  OnLeave hooks; marks live on btn._textOverlay.
-------------------------------------------------------------------------------
local mod = select(2, ...)
if not (mod and mod.GetSelection) then return end

local CUI = CludesUI
local _emptyP = {}
local function BP() return (CUI._bagsDB and CUI._bagsDB.profile) or _emptyP end

-- Milling and Prospecting are profession salvage recipes, not item-targeted spells.
local DISENCHANT, PICK_LOCK, COMPREHEND = 13262, 1804, 1296017
local IC_WEAPON, IC_ARMOR, IC_MISC = Enum.ItemClass.Weapon, Enum.ItemClass.Armor, Enum.ItemClass.Miscellaneous
local ARMOR_COSMETIC = Enum.ItemArmorSubclass.Cosmetic
local FIRST_BAG, LAST_BAG = Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag -- not the bank
local SHADE_ALPHA = 0.7
local ICON_ATLAS = "cursor_cast_64"

-- A set of ids written as one list of numbers: [[ id id ... ]] -> { [id] = true }.
local function IdSet(ids)
    local set = {}
    for id in ids:gmatch("%S+") do
        set[tonumber(id)] = true
    end
    return set
end

-- WoW Forever's Comprehension scrolls (the items requiring that Mage skill)
local SCROLLS = IdSet([[
    211780 211784 211785 211786 211787 211853 211854 211855 213543 213544 213545 213546 213547
    281015 281016 281017 281018
]])

local enabled -- the Quick Actions Icon is on (true or nil)
local isActive -- the mode is on (true or nil)
local hovered -- the bag slot under the mouse while Alt is watched
local castBtn -- the secure button, built on its first use
local events -- combat and Alt watch, each registered only while needed
local hideHooked
local tipCache = {} -- item link -> tooltip verdict, kept while the mode is on
local slots = setmetatable({}, { __mode = "k" }) -- slot button -> { bag, slot, spell }
local marks = setmetatable({}, { __mode = "k" }) -- slot button -> { shade, spell }
local hooked = setmetatable({}, { __mode = "k" })
local SetActive, StopHover, TryAlt -- defined below

local function Known(spellId) return C_SpellBook.IsSpellKnown(spellId) end

-- Whether the bag item's tooltip has a line reading exactly text.
local function TooltipHas(bag, slot, textValue)
    local tipText = C_TooltipInfo.GetBagItem(bag, slot)
    if not (tipText and tipText.lines) then return false end
    for _, line in ipairs(tipText.lines) do
        if line.leftText == textValue then return true end
    end
    return false
end

-- TooltipHas for a line that never changes for a given item, cached while the
-- mode paints every slot.
local function ItemTooltipHas(bag, slot, itemLink, textValue)
    if not (itemLink and isActive) then return TooltipHas(bag, slot, textValue) end
    local val = tipCache[itemLink]
    if val == nil then
        val = TooltipHas(bag, slot, textValue)
        tipCache[itemLink] = val
    end
    return val
end

-- The spell the player can cast on this bag item, or nil. Equipment set gear
-- is never offered to Disenchant.
local function SpellFor(bag, slot, details)
    local itemId = details.itemID
    if CUI.IS_FOREVER and SCROLLS[itemId] then return Known(COMPREHEND) and COMPREHEND or nil end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(itemId)
    if classID == IC_WEAPON or classID == IC_ARMOR then
        local q = details.quality or 0
        if
            q >= 2
            and q <= 4
            and not (classID == IC_ARMOR and subID == ARMOR_COSMETIC)
            and Known(DISENCHANT)
            and not C_Container.GetContainerItemEquipmentSetInfo(bag, slot)
            and not ItemTooltipHas(bag, slot, details.hyperlink, ITEM_DISENCHANT_NOT_DISENCHANTABLE)
        then
            return DISENCHANT
        end
    elseif (classID == IC_MISC or details.hasLoot) and Known(PICK_LOCK) and TooltipHas(bag, slot, LOCKED) then -- read each time: unlocking changes it
        return PICK_LOCK
    end
end

-------------------------------------------------------------------------------
--  The secure cast button
-------------------------------------------------------------------------------
local function HideCastButton()
    if castBtn and not InCombatLockdown() then
        if GameTooltip:IsOwned(castBtn) then GameTooltip:Hide() end
        castBtn:Hide()
        castBtn:ClearAllPoints()
        castBtn.owner = nil
    end
end

local function OnEvent(_, evt)
    if evt == "MODIFIER_STATE_CHANGED" then
        if IsAltKeyDown() then
            TryAlt()
        elseif not isActive then
            HideCastButton()
        end
    elseif isActive then -- PLAYER_REGEN_DISABLED fires before the lockdown
        SetActive(false)
    else
        HideCastButton()
        StopHover()
    end
end

-- Combat is watched while the mode is on or a slot is hovered, Alt only then.
local function SyncEvents()
    if not events then
        if not (isActive or hovered) then return end
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    if isActive or hovered then
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
    else
        events:UnregisterEvent("PLAYER_REGEN_DISABLED")
    end
    if hovered then
        events:RegisterEvent("MODIFIER_STATE_CHANGED")
    else
        events:UnregisterEvent("MODIFIER_STATE_CHANGED")
    end
end

function StopHover()
    if not hovered then return end
    hovered = nil
    SyncEvents()
end

local function CastOnEnter(self)
    if not self.owner then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(self.bag, self.slot)
    local red, green, blue = CUI.GetAccentColor()
    GameTooltip:AddLine(CludesUI.Lf("Click: %s", C_Spell.GetSpellName(self.spell) or ""), red, green, blue)
    GameTooltip:Show()
end

local function CastOnLeave()
    GameTooltip:Hide()
    HideCastButton()
    if hovered and not hovered:IsMouseOver() then StopHover() end
end

local function BuildCast()
    castBtn = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    castBtn:RegisterForClicks("LeftButtonUp", "LeftButtonDown", "RightButtonUp", "RightButtonDown")
    castBtn:SetAttribute("type", "spell")
    -- Above the bag window: at the slot's own strata the slot keeps the mouse.
    castBtn:SetFrameStrata("TOOLTIP")
    local highlight = castBtn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.15)
    castBtn:SetScript("OnEnter", CastOnEnter)
    castBtn:SetScript("OnLeave", CastOnLeave)
    castBtn:Hide()
end

local function ShowCast(button, spell, bag, slot)
    if not castBtn then BuildCast() end
    castBtn:ClearAllPoints()
    castBtn:SetAllPoints(button)
    castBtn:SetAttribute("spell", spell)
    castBtn:SetAttribute("target-bag", bag)
    castBtn:SetAttribute("target-slot", slot)
    castBtn.owner, castBtn.spell, castBtn.bag, castBtn.slot = button, spell, bag, slot
    castBtn:Show()
end

-- Alt held over the hovered slot: the cast button goes over it when a spell fits.
function TryAlt()
    if not hovered or InCombatLockdown() or not IsAltKeyDown() then return end
    if not hovered:IsMouseOver() then
        StopHover()
        return
    end
    local cfg = slots[hovered]
    local details = cfg and C_Container.GetContainerItemInfo(cfg.bag, cfg.slot)
    local spell = details and details.itemID and SpellFor(cfg.bag, cfg.slot, details)
    if spell then ShowCast(hovered, spell, cfg.bag, cfg.slot) end
end

local function OnSlotEnter(button)
    local cfg = enabled and slots[button]
    if not cfg or InCombatLockdown() then return end
    if isActive then
        if cfg.spell then ShowCast(button, cfg.spell, cfg.bag, cfg.slot) end
    else
        hovered = button
        SyncEvents()
        TryAlt()
    end
end

local function OnSlotLeave(button)
    -- The cast button over the slot takes the mouse: still on it.
    if hovered == button and not (castBtn and castBtn.owner == button) then StopHover() end
end

-------------------------------------------------------------------------------
--  The painter (CUI_Bags.RunItemOverlays), registered while the icon is on
-------------------------------------------------------------------------------
-- The spell icon in a corner, or a shade over the item.
local function Marks(button)
    local m = marks[button]
    if m then return m end
    local owner = button._textOverlay
    m = {}
    m.shade = owner:CreateTexture(nil, "OVERLAY", nil, 6)
    m.shade:SetAllPoints(owner)
    m.shade:SetColorTexture(0, 0, 0, SHADE_ALPHA)
    m.spell = owner:CreateTexture(nil, "OVERLAY", nil, 7)
    -- The item's top-right quarter: 16 px on a grid slot, smaller on a List
    -- row's icon, which it would otherwise cover.
    m.spell:SetPoint("TOPRIGHT", owner, "TOPRIGHT", -1, -1)
    m.spell:SetPoint("BOTTOMLEFT", owner, "CENTER")
    m.spell:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    marks[button] = m
    return m
end

local function HideMarks(button)
    local m = marks[button]
    if m then
        m.shade:Hide()
        m.spell:Hide()
    end
end

-- Keeps each bag item's place (and, in the mode, its spell and marks).
local function Paint(button, payload)
    local bag, details = payload.bag, payload.info
    local inBags = bag and bag >= FIRST_BAG and bag <= LAST_BAG
    local s
    if inBags and details and details.itemID then
        s = slots[button] or {}
        s.bag, s.slot = bag, payload.slot
        s.spell = isActive and SpellFor(bag, payload.slot, details) or nil
        slots[button] = s
        if not hooked[button] then
            hooked[button] = true
            button:HookScript("OnEnter", OnSlotEnter)
            button:HookScript("OnLeave", OnSlotLeave)
        end
    else
        slots[button] = nil
    end
    if isActive and inBags then -- the bank keeps its look
        local m = Marks(button)
        local spell = s and s.spell
        if spell then m.spell:SetTexture(C_Spell.GetSpellTexture(spell)) end
        m.spell:SetShown(spell ~= nil)
        m.shade:SetShown(spell == nil)
    else
        HideMarks(button)
    end
    -- The item under the cast button changed: look again.
    if castBtn and castBtn.owner == button and not InCombatLockdown() then
        HideCastButton()
        if button:IsMouseOver() then OnSlotEnter(button) end
    end
end

-------------------------------------------------------------------------------
--  The mode and its header icon
-------------------------------------------------------------------------------
local function SyncIconLook()
    local b = CUI_Bags._quickBtn
    if not b then return end
    if isActive then
        b.icon:SetVertexColor(CUI.GetAccentColor())
    else
        b.icon:SetVertexColor(1, 1, 1)
    end
end

function SetActive(on)
    on = on and true or false
    if on == (isActive or false) or (on and InCombatLockdown()) then return end
    isActive = on or nil
    StopHover()
    HideCastButton()
    if on then
        CUI_Bags:RefreshInventory() -- only the bag window: the bank keeps its look
    else
        for button in pairs(marks) do
            HideMarks(button)
        end
        wipe(tipCache)
    end
    SyncEvents()
    SyncIconLook()
end

local function BuildIcon()
    local widget = CreateFrame("Button", nil, CUI_Bags._bagsBtn:GetParent())
    widget:SetSize(22, 22)
    widget.icon = widget:CreateTexture(nil, "OVERLAY")
    widget.icon:SetAtlas(ICON_ATLAS)
    widget.icon:SetSize(18, 18)
    widget.icon:SetPoint("CENTER")
    widget.icon:SetAlpha(0.9)
    -- The spells by the client's own names (only WoW Forever's Mages
    -- comprehend scrolls).
    local nameList = {}
    for _, ident in
        ipairs(CUI.IS_FOREVER and { DISENCHANT, PICK_LOCK, COMPREHEND } or { DISENCHANT, PICK_LOCK })
    do
        nameList[#nameList + 1] = C_Spell.GetSpellName(ident)
    end
    local tipText = CludesUI.Lf(
        "Highlights the items your spells can work on (%s). Click a matching item while this mode is on, or Alt-click it. Out of combat only.",
        table.concat(nameList, ", ")
    )
    widget:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        CUI.ShowWidgetTooltip(self, isActive and CludesUI.L("Leave Quick Actions.") or tipText)
    end)
    widget:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        CUI.HideWidgetTooltip()
    end)
    widget:SetScript("OnClick", function()
        CUI.HideWidgetTooltip()
        SetActive(not isActive)
    end)
    CUI_Bags._quickBtn = widget
end

local function SyncEnabled(on)
    if on == (enabled or false) then return end
    enabled = on or nil
    if on then
        if not hideHooked then
            hideHooked = true
            CUI_Bags:HookScript("OnHide", function()
                SetActive(false)
                HideCastButton()
                StopHover()
            end)
        end
        CUI_Bags.RegisterItemOverlayIcon("CUI_QuickActions", Paint)
        if CUI_Bags:IsShown() then CUI_Bags:RefreshInventory() end
    else
        SetActive(false)
        CUI_Bags.UnregisterItemOverlayIcon("CUI_QuickActions")
        StopHover()
        HideCastButton()
        wipe(slots)
    end
end

-- Called by CUI_Bags:SyncHeaderIcons: places the icon left of prev while the
-- Quick Actions Icon is on, and returns it then.
function mod.SyncQuickActionsIcon(previous, gap)
    local on = BP().bagShowQuickIcon == true
    SyncEnabled(on)
    if on and not CUI_Bags._quickBtn then BuildIcon() end
    local widget = CUI_Bags._quickBtn
    if not widget then return nil end
    widget:ClearAllPoints()
    widget:SetPoint("RIGHT", previous, "LEFT", -gap, 0)
    widget:SetShown(on)
    return on and widget or nil
end
