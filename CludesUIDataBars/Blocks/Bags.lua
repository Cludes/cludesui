if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Blocks\Bags.lua
-- Bag space block factory.

local ADDON_NAME, mod = ...
local L = mod.L
local Keys = mod.BlockKit

-- Upvalues
local CreateFrame = CreateFrame
local C_Container = C_Container
local floor = math.floor
local upper = math.max
local min = math.min

local ICON_GAP = Keys.ICON_GAP
local CONTENT_BASE = Keys.CONTENT_BASE
local InstKey = Keys.InstKey
local MakeEventFrame = Keys.MakeEventFrame
local RegisterInstEvents = Keys.RegisterInstEvents
local UnregisterInstEvents = Keys.UnregisterInstEvents
local HBudget = Keys.HBudget
local VSlotW = Keys.VSlotW
local MaybeRelayout = Keys.MaybeRelayout
local AttachTextOffset = Keys.AttachTextOffset
local BlockColorOf = Keys.BlockColorOf
local IconColorOf = Keys.IconColorOf

-- Backpack + four bag slots; the reagent bag is opt-in per block.
local LAST_BAG = NUM_BAG_SLOTS or 4
local REAGENT_BAG = Enum.BagIndex.ReagentBag

-- Low space text color default (soft red, matches durability's low tint).
local LOW_R, LOW_G, LOW_B = 1, 0.35, 0.35
mod.BAGS_LOW_COLOR = { LOW_R, LOW_G, LOW_B }

-------------------------------------------------------------------------------
--  BAGS (free / used slot counts)
-------------------------------------------------------------------------------
mod.BlockFactories.bags = function(blockCfg, slotIndex, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slotIndex, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)
    -- BAG_UPDATE_DELAYED: one event per batch of bag changes, not one per bag.
    instance.events = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" }

    local mouseOver = false

    local function D()
        return blockCfg.settings or {}
    end
    local function BC()
        return barCtx.cfg
    end

    local btnFrame = CreateFrame("Button", nil, contentFrame)
    btnFrame:SetAllPoints()
    btnFrame:EnableMouse(true)
    btnFrame:RegisterForClicks("AnyUp")

    local glyph = btnFrame:CreateTexture(nil, "OVERLAY")
    local bagText = btnFrame:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(instance, bagText)

    local function IncludeBag(bag)
        return bag ~= REAGENT_BAG or D().reagent == true
    end

    -- Returns free, total across the counted bags. Only general-purpose bags
    -- (family 0, as Blizzard's own free-space checks count): a quiver, soul
    -- bag or profession bag cannot take ordinary loot.
    local function Count()
        local free, sum = 0, 0
        for bag = 0, LAST_BAG do
            local nFree, family = C_Container.GetContainerNumFreeSlots(bag)
            if not family or family == 0 then
                sum = sum + (C_Container.GetContainerNumSlots(bag) or 0)
                free = free + (nFree or 0)
            end
        end
        if IncludeBag(REAGENT_BAG) then
            sum = sum + (C_Container.GetContainerNumSlots(REAGENT_BAG) or 0)
            free = free + (C_Container.GetContainerNumFreeSlots(REAGENT_BAG) or 0)
        end
        return free, sum
    end

    -- The counts on screen, from whichever path painted last (an event, a
    -- hover, a settings change): the event gate compares against these.
    local lastFree, lastTotal

    function instance:Refresh()
        local s = D()
        Keys.SetBlockIcon(glyph, blockCfg)
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = upper(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()

        local free, sum = Count()
        lastFree, lastTotal = free, sum
        local modeName = s.value or "free"
        local textValue
        if modeName == "used" then
            textValue = tostring(sum - free)
        elseif modeName == "usedTotal" then
            textValue = (sum - free) .. "/" .. sum
        elseif modeName == "freeTotal" then
            textValue = free .. "/" .. sum
        else
            textValue = tostring(free)
        end

        local iconSz = 0
        -- +4: matches the gold block's bag icon.
        if s.showIcon ~= false then
            iconSz = fontSize + 4
            glyph:Show()
        else
            glyph:Hide()
        end

        mod.SetFont(bagText, fontSize, barCfg)
        glyph:SetVertexColor(IconColorOf(blockCfg))
        local low = s.lowThreshold or 0
        if mouseOver then
            bagText:SetTextColor(mod.GetAccent())
        elseif low > 0 and free < low then
            local c = s.lowColor
            if c then
                bagText:SetTextColor(c.r or LOW_R, c.g or LOW_G, c.b or LOW_B)
            else
                bagText:SetTextColor(LOW_R, LOW_G, LOW_B)
            end
        else
            bagText:SetTextColor(BlockColorOf(blockCfg))
        end

        if isSide then
            local slotW = VSlotW(instance)
            local innerW = upper(24, slotW - 8)
            bagText:SetText(textValue)
            local totalH = 8
            if iconSz > 0 then
                glyph:SetSize(iconSz, iconSz)
                glyph:ClearAllPoints()
                glyph:SetPoint("TOP", btnFrame, "TOP", 0, -4)
                totalH = totalH + iconSz + 2
            end
            mod.SetWrappedText(bagText, innerW, "CENTER")
            bagText:ClearAllPoints()
            if iconSz > 0 then
                bagText:SetPoint("TOP", glyph, "BOTTOM", 0, -2)
            else
                bagText:SetPoint("TOP", btnFrame, "TOP", 0, -4)
            end
            totalH = totalH + mod.SnapToPixelGrid(bagText:GetStringHeight()) + 4
            totalH = upper(totalH, barH)
            contentFrame:SetSize(slotW, totalH)
            btnFrame:SetSize(slotW, totalH)
        else
            local slotW = HBudget(instance, 120)
            mod.ResetInlineText(bagText, "LEFT")
            bagText:SetText(textValue)
            if iconSz > 0 then
                glyph:SetSize(iconSz, iconSz)
                glyph:ClearAllPoints()
                glyph:SetPoint("LEFT", btnFrame, "LEFT", 0, 0)
            end
            bagText:ClearAllPoints()
            local xOff = 0
            if iconSz > 0 then
                xOff = iconSz + ICON_GAP - 2
            end
            bagText:SetPoint("LEFT", btnFrame, "LEFT", xOff, 0)
            local tw = mod.SnapToPixelGrid(bagText:GetStringWidth())
            local totalW = min(slotW, xOff + tw + 4)
            contentFrame:SetSize(upper(totalW, 10), barH)
            btnFrame:SetSize(upper(totalW, 10), barH)
        end

        MaybeRelayout(instance)
    end

    local function AddBagRow(bag)
        local num = C_Container.GetContainerNumSlots(bag) or 0
        if num <= 0 then
            return
        end
        local used = num - (C_Container.GetContainerNumFreeSlots(bag) or 0)
        mod.Tip_AddDouble(
            C_Container.GetBagName(bag) or ("#" .. bag),
            used .. "/" .. num,
            0.6,
            0.6,
            0.6,
            1,
            1,
            1
        )
    end

    local function ShowBagsTooltip()
        local ar, ag, ab = mod.GetAccent()
        local free, sum = Count()
        mod.Tip_Begin(btnFrame)
        mod.Tip_AddLine(L["BAGS"], 1, 1, 1)
        mod.Tip_AddLine(" ")
        for bag = 0, LAST_BAG do
            AddBagRow(bag)
        end
        if IncludeBag(REAGENT_BAG) then
            AddBagRow(REAGENT_BAG)
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["FREE"], free .. "/" .. sum, 1, 1, 1, 1, 1, 1)
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_BAGS"], 1, 1, 1, ar, ag, ab)
        mod.Tip_Show()
    end

    btnFrame:SetScript("OnEnter", function()
        mouseOver = true
        instance:Refresh()
        ShowBagsTooltip()
    end)
    btnFrame:SetScript("OnLeave", function()
        mouseOver = false
        mod.Tip_Hide(btnFrame)
        instance:Refresh()
    end)
    btnFrame:SetScript("OnClick", function(_, mb)
        if mb == "LeftButton" then
            ToggleAllBags()
        end
    end)

    -- Most bag batches (a potion, stacking, sorting) leave the counts on
    -- screen unchanged, and those skip the repaint.
    instance.eventFrame = MakeEventFrame(instance, function(self, evt)
        if evt == "BAG_UPDATE_DELAYED" then
            local free, sum = Count()
            if free == lastFree and sum == lastTotal then
                return
            end
        end
        self:Refresh()
    end)

    function instance:Enable()
        lastFree, lastTotal = nil, nil
        contentFrame:Show()
        RegisterInstEvents(self)
    end

    function instance:Disable()
        UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    function instance:GetAutoLength()
        if barCtx.IsVertical() then
            return upper(contentFrame:GetHeight() or 40, 30)
        end
        return upper(contentFrame:GetWidth() or 40, 24)
    end

    function instance:Destroy()
        self._dead = true
        UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    return instance
end
