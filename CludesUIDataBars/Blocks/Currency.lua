if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Blocks\Currency.lua
-- Currency block factory.

local ADDON_NAME, mod = ...
local L = mod.L
local K = mod.BlockKit

-- Upvalues
local CreateFrame = CreateFrame
local floor = math.floor
local max = math.max
local min = math.min

local ICON_GAP = K.ICON_GAP
local CONTENT_BASE = K.CONTENT_BASE
local InstKey = K.InstKey
local MakeEventFrame = K.MakeEventFrame
local RegisterInstEvents = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local HBudget = K.HBudget
local VSlotW = K.VSlotW
local MaybeRelayout = K.MaybeRelayout
local AttachTextOffset = K.AttachTextOffset
local BlockColorOf = K.BlockColorOf
local IconColorOf = K.IconColorOf

-------------------------------------------------------------------------------
--  CURRENCY (searchable-picker driven; icon + amount + owned tooltip)
-------------------------------------------------------------------------------
mod.BlockFactories.currency = function(blockCfg, slot, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)
    instance.events = { "CURRENCY_DISPLAY_UPDATE" }

    local mouseOver = false
    local _curFitBuf = { "" }

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

    local icon = btnFrame:CreateTexture(nil, "OVERLAY")
    local amountText = btnFrame:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(instance, amountText)

    local function GetInfo()
        local s = D()
        if not s.currencyId then
            return nil
        end
        if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then
            return nil
        end
        local details = C_CurrencyInfo.GetCurrencyInfo(s.currencyId)
        if details and details.discovered ~= false then
            return details
        end
        return nil
    end

    local function Num(val)
        if BreakUpLargeNumbers then
            return BreakUpLargeNumbers(val or 0)
        end
        return tostring(val or 0)
    end

    function instance:Refresh()
        local s = D()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()
        local gap = ICON_GAP

        local details = GetInfo()
        local textValue
        if not s.currencyId then
            -- Bar text goes straight through SetText, which does not route through the
            -- locale like the Tip_* helpers, so translate by hand (as the Great Vault block does for its own label).
            textValue = CludesUI.L(L["SELECT_CURRENCY"])
        elseif details then
            if BreakUpLargeNumbers then
                textValue = BreakUpLargeNumbers(details.quantity or 0)
            else
                textValue = tostring(details.quantity or 0)
            end
        else
            textValue = "-"
        end

        local iconSz = 0
        if s.showIcon ~= false and details and details.iconFileID then
            iconSz = fontSize + 2
            icon:SetTexture(details.iconFileID)
            icon:SetTexCoord(5 / 64, 59 / 64, 5 / 64, 59 / 64)
            icon:Show()
        else
            icon:Hide()
        end

        if isSide then
            local slotW = VSlotW(instance)
            local innerW = max(24, slotW - 8)
            _curFitBuf[1] = textValue
            mod.SetFont(amountText, fontSize, barCfg)
            amountText:SetText(textValue)
            local totalH = 8
            if iconSz > 0 then
                icon:SetSize(iconSz, iconSz)
                icon:ClearAllPoints()
                icon:SetPoint("TOP", btnFrame, "TOP", 0, -4)
                totalH = totalH + iconSz + 2
            end
            mod.SetWrappedText(amountText, innerW, "CENTER")
            amountText:ClearAllPoints()
            if iconSz > 0 then
                amountText:SetPoint("TOP", icon, "BOTTOM", 0, -2)
            else
                amountText:SetPoint("TOP", btnFrame, "TOP", 0, -4)
            end
            totalH = totalH + mod.SnapToPixelGrid(amountText:GetStringHeight()) + 4
            totalH = max(totalH, barH)
            contentFrame:SetSize(slotW, totalH)
            btnFrame:SetSize(slotW, totalH)
        else
            local slotW = HBudget(instance, 120)
            local textBudget = max(20, slotW - iconSz - gap - 8)
            _curFitBuf[1] = textValue
            mod.SetFont(amountText, fontSize, barCfg)
            mod.ResetInlineText(amountText, "LEFT")
            amountText:SetText(textValue)
            if iconSz > 0 then
                iconSz = fontSize + 2
                icon:SetSize(iconSz, iconSz)
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", btnFrame, "LEFT", 0, 0)
            end
            amountText:ClearAllPoints()
            local xOff = 0
            if iconSz > 0 then
                xOff = iconSz + gap
            end
            amountText:SetPoint("LEFT", btnFrame, "LEFT", xOff, 0)
            local tw = mod.SnapToPixelGrid(amountText:GetStringWidth())
            local totalW = min(slotW, iconSz + (iconSz > 0 and gap or 0) + tw + 4)
            contentFrame:SetSize(max(totalW, 10), barH)
            btnFrame:SetSize(max(totalW, 10), barH)
        end

        local cbr, cbg, cbb = BlockColorOf(blockCfg)
        do
            local ir, ig, ib = IconColorOf(blockCfg)
            icon:SetVertexColor(ir, ig, ib, 1)
        end
        if not s.currencyId then
            amountText:SetTextColor(0.55, 0.55, 0.55, 1)
        elseif mouseOver then
            local ar, ag, ab = mod.GetAccent()
            amountText:SetTextColor(ar, ag, ab, 1)
        else
            amountText:SetTextColor(cbr, cbg, cbb, 1)
        end
        MaybeRelayout(instance)
    end

    -- Manual tooltip composition (the owned tooltip has no SetCurrencyByID).
    local function ShowCurrencyTooltip()
        local s = D()
        local ar, ag, ab = mod.GetAccent()
        -- Unconfigured: the placeholder is the whole block, so the tooltip has to say where the currency is actually picked.
        if not s.currencyId then
            mod.Tip_Begin(btnFrame)
            mod.Tip_AddLine(L["SELECT_CURRENCY"], 1, 1, 1)
            mod.Tip_AddLine(" ")
            mod.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_SETTINGS"], 1, 1, 1, ar, ag, ab)
            mod.Tip_Show()
            return
        end
        local details = nil
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            details = C_CurrencyInfo.GetCurrencyInfo(s.currencyId)
        end
        if not details then
            return
        end
        mod.Tip_Begin(btnFrame)
        local qr, qg, qb = 1, 1, 1
        if details.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[details.quality] then
            local qc = ITEM_QUALITY_COLORS[details.quality]
            qr, qg, qb = qc.r, qc.g, qc.b
        end
        mod.Tip_AddLine(details.name or "?", qr, qg, qb)
        -- Some currencies carry paragraphs of flavor text that tower over the bar. Opt-out keeps name, total and click hint; only the text goes.
        if s.showDescription ~= false and details.description and details.description ~= "" then
            mod.Tip_AddLine(" ")
            mod.Tip_AddWrappedLine(details.description, 280, 0.8, 0.8, 0.8)
        end
        mod.Tip_AddLine(" ")
        local qty = Num(details.quantity)
        local cap = details.maxQuantity
        if cap and cap > 0 then
            -- useTotalEarnedForMaxQty currencies (crests) cap what you EARNED this
            -- season, not what you hold, so the wallet total is the wrong numerator.
            if details.useTotalEarnedForMaxQty then
                mod.Tip_AddDouble(
                    L["TOTAL"],
                    qty .. " |cffaaaaaa(" .. Num(details.totalEarned) .. "/" .. Num(cap) .. ")|r",
                    0.6,
                    0.6,
                    0.6,
                    1,
                    1,
                    1
                )
            else
                mod.Tip_AddDouble(L["TOTAL"], qty .. " / " .. Num(cap), 0.6, 0.6, 0.6, 1, 1, 1)
            end
        else
            mod.Tip_AddDouble(L["TOTAL"], qty, 0.6, 0.6, 0.6, 1, 1, 1)
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_CURRENCIES"], 1, 1, 1, ar, ag, ab)
        mod.Tip_Show()
    end

    btnFrame:SetScript("OnEnter", function()
        mouseOver = true
        instance:Refresh()
        ShowCurrencyTooltip()
    end)
    btnFrame:SetScript("OnLeave", function()
        mouseOver = false
        mod.Tip_Hide(btnFrame)
        instance:Refresh()
    end)
    btnFrame:SetScript("OnClick", function(_, mb)
        if mb == "LeftButton" then
            -- No currency picked yet: the Blizzard panel cannot assign one, so send the player to the picker instead of dead-ending there.
            if not D().currencyId then
                -- The options never open in combat.
                if InCombatLockdown() then
                    CludesUI.PrintError("Cannot open options during combat.")
                    return
                end
                -- Options surface is LoadOnDemand; load it so OpenBlockSettings exists.
                if not mod.OpenBlockSettings then
                    CludesUI:EnsureLoaded()
                end
                if mod.OpenBlockSettings then
                    mod.OpenBlockSettings(barCtx.id, blockCfg.id, "currency")
                end
                return
            end
            if C_CurrencyInfo and C_CurrencyInfo.OpenCurrencyPanel then
                C_CurrencyInfo.OpenCurrencyPanel()
            elseif ToggleCharacter then
                ToggleCharacter("TokenFrame")
            end
        end
    end)

    instance.eventFrame = MakeEventFrame(instance, function(self)
        self:Refresh()
    end)

    function instance:Enable()
        contentFrame:Show()
        RegisterInstEvents(self)
    end

    function instance:Disable()
        UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    function instance:GetAutoLength()
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 30)
        end
        return max(contentFrame:GetWidth() or 60, 24)
    end

    function instance:Destroy()
        self._dead = true
        contentFrame:Hide()
    end

    return instance
end
