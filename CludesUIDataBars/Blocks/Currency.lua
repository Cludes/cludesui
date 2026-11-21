if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Blocks\Currency.lua - Info Bar block: one currency the player picks.
--
--  Shows the currency's icon and amount; until one is picked it says so, and
--  a click opens the block's settings to pick it. Hover shows the name (in
--  its quality colour), the description (unless turned off), the total
--  against any cap, and the click hint.
--
--  Settings (blockCfg.settings): currencyId, showIcon (default on),
--  showDescription (default on).
-------------------------------------------------------------------------------
local _, mod = ...
local L = mod.L
local K = mod.BlockKit

local floor, max, min = math.floor, math.max, math.min

-- A currency icon's own border, trimmed (5 of 64 pixels each side).
local TRIM = 5 / 64

local function Number(n)
    n = n or 0
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

mod.BlockFactories.currency = function(blockCfg, slot, contentFrame, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    inst.events = { "CURRENCY_DISPLAY_UPDATE" }

    local function Settings() return blockCfg.settings or {} end

    local button = CreateFrame("Button", nil, contentFrame)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")
    local iconTex = button:CreateTexture(nil, "OVERLAY")
    local label = button:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, label)

    -- The picked currency's details, or nil (none picked, unknown, or not discovered yet).
    local function Details()
        local id = Settings().currencyId
        if not (id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
        local skinData = C_CurrencyInfo.GetCurrencyInfo(id)
        if skinData and skinData.discovered ~= false then return skinData end
    end

    local hovered = false

    -- The text colour alone: grey until a currency is picked, the accent on hover.
    local function PaintText()
        if not Settings().currencyId then
            label:SetTextColor(0.55, 0.55, 0.55, 1)
        elseif hovered then
            local red, green, blue = mod.GetAccent()
            label:SetTextColor(red, green, blue, 1)
        else
            local red, green, blue = K.BlockColorOf(blockCfg)
            label:SetTextColor(red, green, blue, 1)
        end
    end

    function inst:Refresh()
        local cfg = Settings()
        local skinData = Details()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        local text
        if not cfg.currencyId then
            -- Bar text is set directly, not through the tooltip helpers that
            -- translate, so it is translated here.
            text = CludesUI.L(L["SELECT_CURRENCY"])
        elseif skinData then
            text = Number(skinData.quantity)
        else
            text = "-"
        end

        local iconSize = 0
        if cfg.showIcon ~= false and skinData and skinData.iconFileID then
            iconSize = fontSize + 2
            iconTex:SetTexture(skinData.iconFileID)
            iconTex:SetTexCoord(TRIM, 1 - TRIM, TRIM, 1 - TRIM)
            iconTex:Show()
        else
            iconTex:Hide()
        end
        local red, green, blue = K.IconColorOf(blockCfg)
        iconTex:SetVertexColor(red, green, blue, 1)
        mod.SetFont(label, fontSize, barCtx.cfg)

        if barCtx.IsVertical() then
            -- Icon above the amount, both centred in the bar's width.
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
            -- Icon then amount, as wide as they need (up to the slot's budget).
            local budget = K.HBudget(inst, 120)
            mod.ResetInlineText(label, "LEFT")
            label:SetText(text)
            local x = 0
            if iconSize > 0 then
                iconTex:SetSize(iconSize, iconSize)
                iconTex:ClearAllPoints()
                iconTex:SetPoint("LEFT", button, "LEFT", 0, 0)
                x = iconSize + K.ICON_GAP
            end
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", x, 0)
            local width = max(min(budget, x + mod.SnapToPixelGrid(label:GetStringWidth()) + 4), 10)
            contentFrame:SetSize(width, barH)
            button:SetSize(width, barH)
        end
        PaintText()
        K.MaybeRelayout(inst)
    end

    -- Composed by hand: the owned tooltip has no SetCurrencyByID.
    local function ShowTooltip()
        local cfg = Settings()
        local ar, ag, ab = mod.GetAccent()
        if not cfg.currencyId then
            -- The placeholder is the whole block, so the tooltip says where a currency is picked.
            mod.Tip_Begin(button)
            mod.Tip_AddLine(L["SELECT_CURRENCY"], 1, 1, 1)
            mod.Tip_AddLine(" ")
            mod.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_SETTINGS"], 1, 1, 1, ar, ag, ab)
            mod.Tip_Show()
            return
        end
        local skinData = C_CurrencyInfo
            and C_CurrencyInfo.GetCurrencyInfo
            and C_CurrencyInfo.GetCurrencyInfo(cfg.currencyId)
        if not skinData then return end
        mod.Tip_Begin(button)
        local q = skinData.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[skinData.quality]
        mod.Tip_AddLine(skinData.name or "?", q and q.r or 1, q and q.g or 1, q and q.b or 1)
        -- Some descriptions run to paragraphs; the setting drops just the text.
        if cfg.showDescription ~= false and skinData.description and skinData.description ~= "" then
            mod.Tip_AddLine(" ")
            mod.Tip_AddWrappedLine(skinData.description, 280, 0.8, 0.8, 0.8)
        end
        mod.Tip_AddLine(" ")
        local total = Number(skinData.quantity)
        local cap = skinData.maxQuantity
        if cap and cap > 0 and skinData.useTotalEarnedForMaxQty then
            -- A season cap (crests) limits what was EARNED, not what is held.
            total = total .. " |cffaaaaaa(" .. Number(skinData.totalEarned) .. "/" .. Number(cap) .. ")|r"
        elseif cap and cap > 0 then
            total = total .. " / " .. Number(cap)
        end
        mod.Tip_AddDouble(L["TOTAL"], total, 0.6, 0.6, 0.6, 1, 1, 1)
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_CURRENCIES"], 1, 1, 1, ar, ag, ab)
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
        if mouseButton ~= "LeftButton" then return end
        if not Settings().currencyId then
            -- Nothing picked: the game's panel cannot pick one, so open the block's settings.
            if InCombatLockdown() then
                CludesUI.PrintError("Cannot open options during combat.")
                return
            end
            if not mod.OpenBlockSettings then
                CludesUI:EnsureLoaded() -- the settings load on demand
            end
            if mod.OpenBlockSettings then mod.OpenBlockSettings(barCtx.id, blockCfg.id, "currency") end
        elseif C_CurrencyInfo and C_CurrencyInfo.OpenCurrencyPanel then
            C_CurrencyInfo.OpenCurrencyPanel()
        elseif ToggleCharacter then
            ToggleCharacter("TokenFrame")
        end
    end)

    -- Only this block's currency (or an update of every currency, which names
    -- none) redraws it; the game sends this event for any currency that moves.
    inst.eventFrame = K.MakeEventFrame(inst, function(self, _, currencyId)
        if currencyId and currencyId ~= Settings().currencyId then return end
        self:Refresh()
    end)

    function inst:Enable()
        contentFrame:Show()
        K.RegisterInstEvents(self)
    end

    function inst:Disable()
        K.UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then return max(contentFrame:GetHeight() or 40, 30) end
        return max(contentFrame:GetWidth() or 60, 24)
    end

    -- The bar disables a block before destroying it; this also stops the
    -- events in case Destroy is ever called on its own.
    function inst:Destroy()
        self._dead = true
        K.UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    return inst
end
