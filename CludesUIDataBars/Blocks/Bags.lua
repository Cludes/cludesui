if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Blocks\Bags.lua - Info Bar block: bag space.
--
--  Shows the free (or used) slots of the bags that take ordinary loot: the
--  backpack and the four bag slots, plus the reagent bag when the block says
--  so. A quiver, soul bag or profession bag holds only its own kind of item,
--  so it is left out of the count (as the game's own free-space checks do)
--  and shown dimmed in the tooltip.
--
--  Settings (blockCfg.settings): value = "free" | "used" | "freeTotal" |
--  "usedTotal"; showIcon (default on); lowThreshold (free slots under it
--  turn the text lowColor, default soft red); reagent (count the reagent bag).
-------------------------------------------------------------------------------
local _, mod = ...
local Loc = mod.L
local K = mod.BlockKit

local C_Container = C_Container
local floor, max, min = math.floor, math.max, math.min

local LAST_BAG = NUM_BAG_SLOTS or 4
local REAGENT_BAG = Enum.BagIndex.ReagentBag

-- Low-space text colour default (soft red, as durability's low tint).
local LOW = { 1, 0.35, 0.35 }
mod.BAGS_LOW_COLOR = LOW

-- The text for each display mode, from free and total.
local SHOW = {
    free = function(free) return tostring(free) end,
    used = function(free, total) return tostring(total - free) end,
    freeTotal = function(free, total) return free .. "/" .. total end,
    usedTotal = function(free, total) return (total - free) .. "/" .. total end,
}

mod.BlockFactories.bags = function(blockCfg, slot, contentFrame, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    -- BAG_UPDATE_DELAYED: one event per batch of bag changes, not one per bag.
    inst.events = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" }

    local function Settings() return blockCfg.settings or {} end

    local button = CreateFrame("Button", nil, contentFrame)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")
    local iconTex = button:CreateTexture(nil, "OVERLAY")
    local label = button:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, label)

    -- Whether a bag's slots are counted: a general-purpose bag (family 0), or
    -- the reagent bag when the block includes it.
    local function Counted(bag)
        if bag == REAGENT_BAG then return Settings().reagent == true end
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        return not family or family == 0
    end

    local function Count()
        local free, total = 0, 0
        for bag = 0, LAST_BAG do
            if Counted(bag) then
                total = total + (C_Container.GetContainerNumSlots(bag) or 0)
                free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
            end
        end
        if Counted(REAGENT_BAG) then
            total = total + (C_Container.GetContainerNumSlots(REAGENT_BAG) or 0)
            free = free + (C_Container.GetContainerNumFreeSlots(REAGENT_BAG) or 0)
        end
        return free, total
    end

    local hovered = false
    local shownFree, shownTotal -- the counts on screen; a bag event that leaves them as they are skips the redraw

    -- The text colour alone: hover, low space or the block's own colour.
    local function PaintText()
        local cfg = Settings()
        if hovered then
            label:SetTextColor(mod.GetAccent())
        elseif (cfg.lowThreshold or 0) > 0 and (shownFree or 0) < cfg.lowThreshold then
            local color = cfg.lowColor
            label:SetTextColor(
                color and color.r or LOW[1],
                color and color.g or LOW[2],
                color and color.b or LOW[3]
            )
        else
            label:SetTextColor(K.BlockColorOf(blockCfg))
        end
    end

    -- Lays the block out for counts already read (free, total), or reads them.
    function inst:Refresh(free, total)
        if not free then
            free, total = Count()
        end
        shownFree, shownTotal = free, total
        local cfg = Settings()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        -- +4: the size of the gold block's bag icon.
        local iconSize = cfg.showIcon ~= false and fontSize + 4 or 0

        K.SetBlockIcon(iconTex, blockCfg)
        iconTex:SetVertexColor(K.IconColorOf(blockCfg))
        iconTex:SetShown(iconSize > 0)
        mod.SetFont(label, fontSize, barCtx.cfg)
        PaintText()
        local text = (SHOW[cfg.value] or SHOW.free)(free, total)

        if barCtx.IsVertical() then
            -- Icon above the number, both centred in the bar's width.
            local slotW = K.VSlotW(inst)
            label:SetText(text)
            local height = 8
            if iconSize > 0 then
                iconTex:SetSize(iconSize, iconSize)
                iconTex:ClearAllPoints()
                iconTex:SetPoint("TOP", button, "TOP", 0, -4)
                height = height + iconSize + 2
            end
            mod.SetWrappedText(label, max(24, slotW - 8), "CENTER")
            label:ClearAllPoints()
            if iconSize > 0 then
                label:SetPoint("TOP", iconTex, "BOTTOM", 0, -2)
            else
                label:SetPoint("TOP", button, "TOP", 0, -4)
            end
            height = max(height + mod.SnapToPixelGrid(label:GetStringHeight()) + 4, barH)
            contentFrame:SetSize(slotW, height)
            button:SetSize(slotW, height)
        else
            -- Icon then number, left to right, as wide as they need (up to the slot's budget).
            local budget = K.HBudget(inst, 120)
            mod.ResetInlineText(label, "LEFT")
            label:SetText(text)
            local x = 0
            if iconSize > 0 then
                iconTex:SetSize(iconSize, iconSize)
                iconTex:ClearAllPoints()
                iconTex:SetPoint("LEFT", button, "LEFT", 0, 0)
                x = iconSize + K.ICON_GAP - 2
            end
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", x, 0)
            local width = max(min(budget, x + mod.SnapToPixelGrid(label:GetStringWidth()) + 4), 10)
            contentFrame:SetSize(width, barH)
            button:SetSize(width, barH)
        end
        K.MaybeRelayout(inst)
    end

    -- Tooltip: each bag's used/total, the ones not counted dimmed, then the total free.
    local function ShowTooltip()
        local free, total = Count()
        mod.Tip_Begin(button)
        mod.Tip_AddLine(Loc["BAGS"], 1, 1, 1)
        mod.Tip_AddLine(" ")
        local function Row(bag)
            local size = C_Container.GetContainerNumSlots(bag) or 0
            if size <= 0 then return end
            local used = size - (C_Container.GetContainerNumFreeSlots(bag) or 0)
            local shade = Counted(bag) and 1 or 0.45
            mod.Tip_AddDouble(
                C_Container.GetBagName(bag) or ("#" .. bag),
                used .. "/" .. size,
                0.6 * shade,
                0.6 * shade,
                0.6 * shade,
                shade,
                shade,
                shade
            )
        end
        for bag = 0, LAST_BAG do
            Row(bag)
        end
        if Settings().reagent == true then Row(REAGENT_BAG) end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(Loc["FREE"], free .. "/" .. total, 1, 1, 1, 1, 1, 1)
        mod.Tip_AddLine(" ")
        local red, green, blue = mod.GetAccent()
        mod.Tip_AddDouble(Loc["LEFT_CLICK"], Loc["OPEN_BAGS"], 1, 1, 1, red, green, blue)
        mod.Tip_Show()
    end

    -- Hovering only recolours the text; nothing moves, so nothing is laid out again.
    button:SetScript("OnEnter", function()
        hovered = true
        PaintText()
        ShowTooltip()
    end)
    button:SetScript("OnLeave", function()
        hovered = false
        mod.Tip_Hide(button)
        PaintText()
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" then ToggleAllBags() end
    end)

    -- Bags are counted once per event: most batches (a potion, stacking,
    -- sorting) leave the numbers as they are and draw nothing.
    inst.eventFrame = K.MakeEventFrame(inst, function(self, event)
        local free, total = Count()
        if event == "BAG_UPDATE_DELAYED" and free == shownFree and total == shownTotal then return end
        self:Refresh(free, total)
    end)

    function inst:Enable()
        shownFree, shownTotal = nil, nil
        contentFrame:Show()
        K.RegisterInstEvents(self)
    end

    function inst:Disable()
        K.UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then return max(contentFrame:GetHeight() or 40, 30) end
        return max(contentFrame:GetWidth() or 40, 24)
    end

    function inst:Destroy()
        self._dead = true
        K.UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    return inst
end
