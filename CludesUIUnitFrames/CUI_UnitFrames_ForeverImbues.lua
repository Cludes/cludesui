if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_ForeverImbues.lua  (WoW Forever only)
--
--  The weapon enchants the Player Aura Bars Buffs bar's own weapon-enchant
--  cells leave out. On WoW Forever a weapon can carry an imbue (Rockbiter,
--  Windfury, a rogue's poisons: Enum.ItemEnchantType.Imbue) and a temporary
--  enchant (oils, stones) at once, while C_PaperDollInfo.
--  GetTemporaryEnchantmentInfo -- the one source those engine cells read --
--  reports one enchant per weapon: since the 1.60.1 launch the imbue, which
--  takes priority, and before it only the temporary one. C_Item.
--  GetWeaponEnchantInfo lists every enchant per weapon, so the one the engine
--  cell does not show (an oil or stone under an imbue; on an older client the
--  imbue) is drawn here as a cell of the bar's own style (AK.CreateStyledCell),
--  leading the bar where the engine's weapon-enchant cells lead it: the
--  container moves along its growth by the cells shown and its line
--  shortens by as much, so the bar keeps its box. Centered growth has no
--  fixed leading corner: there the cells sit as a line of their own just
--  before the bar (above it, or left of it for vertical growth). A cell shows
--  its weapon's icon, or the enchant's own while the game's Display Temporary
--  Enchant Icon CVar is on, as Blizzard's buff frame does.
--
--  The Player Aura Bars file calls ns.PAB_FvImbueLayout (ApplyEnchants),
--  ns.PAB_FvImbueSync (SyncEnchantEvents) and ns.PAB_FvImbueCount
--  (BuffAuraMax); all three stay nil on every other client, where this file
--  returns at once.
--
--  Cost: nothing while the Buffs bar's weapon-enchant row is off. On: the
--  weapon events; the bar re-lays only when the number of imbues changes,
--  and the countdown text runs on the engine's duration binding.
-------------------------------------------------------------------------------
local _, mod = ...
local CludesUI = _G.CludesUI
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
local ET, WS = Enum.ItemEnchantType, Enum.WeaponSlot
if not (ET and ET.Imbue and WS and C_Item and C_Item.GetWeaponEnchantInfo) then
    return
end

local IMBUE, TEMPORARY = ET.Imbue, ET.Temporary
local STYLE = "playerAuraBars_buffs" -- the default Buffs bar's style key
-- Weapons in cell order from the bar's corner: the engine's weapon-enchant
-- cells run in reverse slot order, so main hand sits next to the rest.
local WEAPONS = { WS.Ranged, WS.OffHand, WS.MainHand }
local INV = {
    [WS.MainHand] = INVSLOT_MAINHAND or 16,
    [WS.OffHand] = INVSLOT_OFFHAND or 17,
    [WS.Ranged] = INVSLOT_RANGED or 18,
}
-- Each weapon's place among the bar's declared weapon-enchant slots (main hand,
-- off hand, ranged: ENCH_INV_SLOTS in CUI_PlayerAuraBars_Bars.lua).
local DECLARED = { [WS.MainHand] = 1, [WS.OffHand] = 2, [WS.Ranged] = 3 }

local enabled = false
local isShown = {} -- enchants in cell order: { inv, icon, charges, endTime, total }
local numShown = 0 -- enchants the last scan found
local numLaidFrom = 0 -- numShown the last layout was built from
local numLaid = 0 -- cells the last layout placed (they come off the aura budget)
local numDeclared = 0 -- weapon-enchant slots the bar declared at its last layout
local track = {} -- weapon slot -> { id, endTime, total }
local cells = {} -- cell index -> { f, d, dur, binding, inv }
local events

local function Readable(val)
    return val ~= nil and not issecretvalue(val)
end

local function Active(e)
    return Readable(e.hasEnchant)
        and e.hasEnchant
        and Readable(e.enchantType)
        and Readable(e.timeLeft)
        and e.timeLeft > 0
end

-- The enchant ID the bar's own weapon-enchant cell shows for this weapon, or nil:
-- what GetTemporaryEnchantmentInfo reports, on a slot the bar declared, with a
-- duration (the engine cells hide permanent enchants).
local function EngineEnchantID(ws)
    if DECLARED[ws] > numDeclared then
        return nil
    end
    local details = C_PaperDollInfo.GetTemporaryEnchantmentInfo(INV[ws])
    if not (details and Readable(details.hasExpirationTime) and details.hasExpirationTime) then
        return nil
    end
    return Readable(details.enchantID) and details.enchantID or nil
end

-- Fills `shown` from the weapons; returns the count. Equipment data, read on
-- the weapon events and at each layout only.
local function Scan()
    local num, nowTime = 0, GetTime()
    local enchantIcon = C_CVar.GetCVarBool("displayTemporaryEnchantIcon")
    for _, ws in ipairs(WEAPONS) do
        local entries = C_Item.GetWeaponEnchantInfo(ws)
        local imbue, temp
        if type(entries) == "table" then
            for _, entry in ipairs(entries) do
                if Active(entry) then
                    if entry.enchantType == IMBUE then
                        imbue = entry
                    elseif entry.enchantType == TEMPORARY then
                        temp = entry
                    end
                end
            end
        end
        -- The engine cell's enchant: told apart by ID, else the imbue (it takes
        -- priority in what the game reports).
        local engine, covered = (imbue or temp) and EngineEnchantID(ws), nil
        if engine then
            covered = (temp and temp.enchantID == engine) and temp or imbue or temp
        end
        -- A cell here for the other one: an imbue the engine cell leaves out, or
        -- an oil or stone under the imbue it shows.
        local found
        if imbue and imbue ~= covered then
            found = imbue
        elseif temp and covered and temp ~= covered then
            found = temp
        end
        if found then
            local leftX = found.timeLeft / 1000
            local endTime = nowTime + leftX
            local t = track[ws]
            if not t then
                t = {}
                track[ws] = t
            end
            -- A new imbue, or the same one cast again (its end moved out): the
            -- swipe restarts from what is left now.
            if t.id ~= found.enchantID or endTime > (t.endTime or 0) + 1 then
                t.total = leftX
            end
            t.id, t.endTime = found.enchantID, endTime
            num = num + 1
            local s = isShown[num]
            if not s then
                s = {}
                isShown[num] = s
            end
            s.inv = INV[ws]
            local iconTex = found.enchantIconID
            if not (enchantIcon and Readable(iconTex) and iconTex ~= 0) then
                iconTex = GetInventoryItemTexture("player", s.inv) or 134400
            end
            s.icon = iconTex
            s.charges = Readable(found.charges) and found.charges or 0
            s.endTime, s.total = endTime, t.total
        else
            track[ws] = nil
        end
    end
    numShown = num
    return num
end

local function CellEnter(self)
    local c = self.fvImbue
    local style = CludesUI.AuraKit.styles[STYLE]
    if not (c and c.inv) or (style and style.noTooltips) then
        return
    end
    if style and style.tooltipCombatHide and InCombatLockdown() then
        return
    end
    GameTooltip:SetOwner(
        self,
        (style and style.tooltipAnchor == "cursor") and "ANCHOR_CURSOR" or "ANCHOR_BOTTOMLEFT"
    )
    GameTooltip:SetInventoryItem("player", c.inv)
    GameTooltip:Show()
end

local function CellLeave()
    GameTooltip:Hide()
end

local function Cell(index, hostFrame)
    local c = cells[index]
    if c then
        if c.f:GetParent() ~= hostFrame then
            c.f:SetParent(hostFrame)
        end
        return c
    end
    local AK = CludesUI.AuraKit
    -- The weapon-enchant init: Blizzard Style rings these cells like the
    -- engine's own weapon-enchant cells.
    local frame, skinData = AK.CreateStyledCell(hostFrame, STYLE, AK.EnchantCellInit)
    -- Hover shows the weapon's tooltip; clicks pass through (removing an
    -- imbue is a protected call).
    frame:EnableMouse(true)
    frame:SetMouseClickEnabled(false)
    frame:SetScript("OnEnter", CellEnter)
    frame:SetScript("OnLeave", CellLeave)
    c = { f = frame, d = skinData }
    if C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
        c.dur = C_DurationUtil.CreateDuration()
        c.binding = C_DurationUtil.CreateDurationTextBinding()
        c.binding:SetFontString(skinData.duration)
        c.binding:SetDuration(c.dur)
    end
    frame.fvImbue = c
    cells[index] = c
    return c
end

-- Content only (the style pass owns size, border, fonts and anchors).
local function Paint(c, cfg)
    local AK = CludesUI.AuraKit
    local style = AK.styles[STYLE] or {}
    local skinData = c.d
    c.inv = cfg.inv
    skinData.icon:SetTexture(cfg.icon)
    skinData.stack:SetText(cfg.charges > 0 and tostring(cfg.charges) or "")
    skinData.cooldown:SetCooldown(cfg.endTime - cfg.total, cfg.total)
    local b = c.binding
    if b then
        c.dur:SetTimeFromEnd(cfg.endTime, cfg.total)
        local fmt = AK.GetDurationFormatter(style.durationShowSeconds, style.durationPrecisionThreshold)
        if fmt then
            b:SetFormatter(fmt)
        end
        if style.durationUpdateInterval then
            b:SetUpdateInterval(style.durationUpdateInterval)
        end
        local tc = style.durationColorCurve and AK.DurationTextColor(style.durationColorCurve)
        if tc then
            b:SetTextColorCurve(tc.curve, tc.property)
        else
            b:ClearTextColorCurve()
        end
        b:SetEnabled(true)
    end
end

local function HideFrom(first)
    for index = first, #cells do
        local c = cells[index]
        c.f:Hide()
        if c.binding then
            c.binding:SetEnabled(false)
        end
    end
end

-- ApplyEnchants, after the container took its normal anchor and line width
-- this pass: places the cells and makes room for them. `layout` is the bar's
-- group layout (element size and spacing), `anchor` the container's point.
function mod.PAB_FvImbueLayout(boxHolder, hostFrame, conf, grid, layout, anchor)
    if not (enabled and boxHolder and hostFrame and conf and grid and layout and anchor) then
        return
    end
    numDeclared = grid.enchSlots or 0
    Scan()
    numLaidFrom = numShown
    local num = math.min(numShown, grid.enchSlots or 0)
    local direction = conf.growDirection or "LEFT"
    -- A column steps by the cell's height (a Cropped icon is shorter than wide).
    local vertical = direction == "UP" or direction == "DOWN" or direction == "CENTER_VERTICAL"
    local step = (vertical and layout.elementHeight or layout.elementWidth) + layout.elementSpacing
    local lineGap = layout.lineSpacing or layout.elementSpacing
    local dx, dy = 0, 0
    if direction == "LEFT" then
        dx = -step
    elseif direction == "RIGHT" then
        dx = step
    elseif direction == "DOWN" then
        dy = -step
    elseif direction == "UP" then
        dy = step
    end
    local centered = dx == 0 and dy == 0
    for index = 1, num do
        local c = Cell(index, hostFrame)
        local frame = c.f
        frame:ClearAllPoints()
        if not centered then
            frame:SetPoint(anchor, hostFrame, anchor, (index - 1) * dx, (index - 1) * dy)
        elseif direction == "CENTER_VERTICAL" then
            frame:SetPoint("RIGHT", hostFrame, "LEFT", -lineGap, ((num + 1) / 2 - index) * step)
        else
            frame:SetPoint("BOTTOM", hostFrame, "TOP", (index - (num + 1) / 2) * step, lineGap)
        end
        Paint(c, isShown[index])
        frame:Show()
    end
    HideFrom(num + 1)
    numLaid = num
    if num > 0 and not centered then
        boxHolder:ClearAllPoints()
        boxHolder:SetPoint(anchor, hostFrame, anchor, num * dx, num * dy)
        CludesUI.AuraKit.SetContainerRowWidth(boxHolder, math.max(step, grid.rowWidth - num * step))
    end
end

-- Cells showing, for the bar's aura budget (BuffAuraMax).
function mod.PAB_FvImbueCount()
    return enabled and numLaid or 0
end

local function OnEvent()
    if not enabled then
        return
    end
    Scan()
    if numShown ~= numLaidFrom then
        -- A cell came or went: the bar re-lays (and this file with it).
        if mod.PAB_ApplyLiveConfig then
            mod.PAB_ApplyLiveConfig(true)
        end
        return
    end
    -- Same cells, new content (a re-cast, a weapon swap between imbued
    -- weapons, charges): repaint in place.
    for index = 1, numLaid do
        Paint(cells[index], isShown[index])
    end
end

-- SyncEnchantEvents: the Buffs bar's weapon-enchant row on or off.
function mod.PAB_FvImbueSync(wanted)
    wanted = wanted and true or false
    if wanted == enabled then
        return
    end
    enabled = wanted
    if enabled then
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", OnEvent)
        end
        events:RegisterEvent("WEAPON_ENCHANT_CHANGED")
        events:RegisterEvent("WEAPON_SLOT_CHANGED")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
    else
        if events then
            events:UnregisterAllEvents()
        end
        HideFrom(1)
        numLaid, numLaidFrom = 0, 0
    end
end
