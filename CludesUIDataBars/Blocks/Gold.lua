if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  Blocks\Gold.lua - Info Bar block: gold, the session and every character.
--
--  Shows the character's money (gold only, or with silver and copper; coin
--  letters tinted or as icons; abbreviated), optionally free bag slots. Hover:
--  this session's earned / spent / net, every recorded character by realm with
--  the warbank and the total, and the WoW Token price. Left-click opens the
--  bags, right-click the currencies; Ctrl+right-click resets the session,
--  Ctrl+Shift+right-click forgets every character, Ctrl+Alt+click on a row
--  forgets that one.
--
--  One session record is shared by every gold block. Money comes through the
--  account gold ledger (CludesUI.GetGoldLedger, shared with Bags), which
--  records characters and the warbank. A redraw happens only when what the
--  block shows changed: bags change constantly, and the slot count matters
--  only when it is shown.
--
--  Settings (blockCfg.settings): showSmall, coinIcons, abbreviate,
--  forceEnglishUnits, showIcons (default on), showBagSpace; tipSession,
--  tipCharacters, tipToken (each default on). blockCfg.useCoinColor is the
--  default text colour (set once per block, below).
-------------------------------------------------------------------------------
local _, mod = ...
local L = mod.L
local K = mod.BlockKit

local format, concat = string.format, table.concat
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local Ledger = CUI.GetGoldLedger()

-- This session, shared by every gold block.
local session = { earned = 0, spent = 0, lastMoney = nil, tokenPrice = nil }
local blocks = {} -- every enabled gold block, as a set
local listener

local function UpdateAll()
    for block in pairs(blocks) do
        block:QueueRefresh()
    end
end

local function Forget(key)
    Ledger.Forget(key)
    UpdateAll()
end

-- Every character and the warbank forgotten; this character and the warbank
-- are recorded again at once, the others when they next log in.
local function ForgetAll()
    Ledger.Reset()
    Ledger.RecordCharacter()
    Ledger.RecordWarband()
    UpdateAll()
end

-- The ledger calls this after recording. money is the live balance (nil for
-- warbank changes or an unusable read), so the session only sees numbers.
local function OnMoney(_, money)
    if money and session.lastMoney then
        local change = money - session.lastMoney
        if change > 0 then
            session.earned = session.earned + change
        elseif change < 0 then
            session.spent = session.spent - change
        end
    end
    if money then session.lastMoney = money end
    UpdateAll()
end

local function OnEvent(_, event)
    if event == "TOKEN_MARKET_PRICE_UPDATED" then
        local price = C_WowTokenPublic
            and C_WowTokenPublic.GetCurrentMarketPrice
            and C_WowTokenPublic.GetCurrentMarketPrice()
        if issecretvalue and issecretvalue(price) then price = nil end
        if C_WowTokenPublic and C_WowTokenPublic.GetCurrentMarketPrice then session.tokenPrice = price end
        return
    end
    UpdateAll() -- BAG_UPDATE
end

local function Listen()
    if next(blocks) then
        if not listener then
            listener = CreateFrame("Frame")
            listener:SetScript("OnEvent", OnEvent)
        end
        listener:RegisterEvent("BAG_UPDATE")
        listener:RegisterEvent("TOKEN_MARKET_PRICE_UPDATED")
        Ledger.Register("databars-gold", OnMoney)
    else
        if listener then listener:UnregisterAllEvents() end
        Ledger.Unregister("databars-gold")
    end
end

-- Free slots in general bags only (family 0): a quiver, soul or profession
-- bag cannot take ordinary loot.
local function FreeSlots()
    local free = 0
    for bag = 0, 4 do
        local n, family = C_Container.GetContainerNumFreeSlots(bag)
        if n and (not family or family == 0) then free = free + n end
    end
    return free
end

-- The tooltip's characters: keys sorted richest first, under the realm each
-- was recorded on (realms A-Z). Past maxRows the rest are left out unless
-- all (Shift) is set; the live character always shows. Returns the realms,
-- realm -> keys, and how many were left out.
local function ByRealm(chars, keys, all, me, maxRows)
    local byRealm, realms, shown, left = {}, {}, 0, 0
    for _, key in ipairs(keys) do
        if not all and shown >= maxRows and key ~= me then
            left = left + 1
        else
            shown = shown + 1
            local realm = chars[key].realm or "?"
            if not byRealm[realm] then
                byRealm[realm] = {}
                realms[#realms + 1] = realm
            end
            local list = byRealm[realm]
            list[#list + 1] = key
        end
    end
    table.sort(realms)
    return realms, byRealm, left
end

mod.BlockFactories.gold = function(blockCfg, slot, contentFrame, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)

    -- Coin colours (white numbers, tinted g/s/c) are the default, set once on
    -- every block whatever it had; the marker lets later choices stick.
    if not blockCfg.coinForced then
        blockCfg.coinForced = true
        blockCfg.useCoinColor = true
        blockCfg.useClassColor = nil
        blockCfg.useAccentColor = nil
    end

    local function Settings() return blockCfg.settings or {} end

    local button = CreateFrame("Button", nil, contentFrame)
    button:SetSize(120, 20)
    button:SetPoint("CENTER")
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")
    local iconTex = button:CreateTexture(nil, "OVERLAY")
    local label = button:CreateFontString(nil, "OVERLAY")
    local slots = button:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, label) -- the slot count follows the label

    local hovered = false
    local drawn -- money and slot count as last drawn

    local function State()
        local cfg = Settings()
        return (Ledger.Money() or 0) .. "|" .. (cfg.showBagSpace == true and FreeSlots() or "-")
    end

    -- The money text, coin coloured or plain (plain on hover, so the accent shows).
    local function MoneyText(money, coloured)
        local cfg = Settings()
        return mod.FormatMoney(
            money,
            coloured,
            cfg.showSmall == true,
            cfg.coinIcons == true,
            cfg.abbreviate == true,
            cfg.forceEnglishUnits == true
        )
    end

    -- The text colour: the accent on hover, white under coin colours, else the block's.
    local function TextColour()
        if hovered then
            return mod.GetAccent()
        elseif blockCfg.useCoinColor then
            return 1, 1, 1
        end
        return K.BlockColorOf(blockCfg)
    end

    local function PaintIcon()
        if hovered then
            iconTex:SetVertexColor(TextColour())
        else
            iconTex:SetVertexColor(K.IconColorOf(blockCfg))
        end
    end

    function inst:Refresh()
        local cfg = Settings()
        K.SetBlockIcon(iconTex, blockCfg)
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        -- The bag icon runs 4px bigger than the text, and sits 2px closer.
        local iconSize = cfg.showIcons ~= false and fontSize + 4 or 0
        local gap = K.ICON_GAP - 2
        local money = Ledger.Money() or 0
        local coinColours = blockCfg.useCoinColor == true and not hovered
        drawn = State()

        mod.SetFont(label, fontSize, barCtx.cfg)
        mod.SetFont(slots, fontSize, barCtx.cfg)
        local red, green, blue = TextColour()
        if barCtx.IsVertical() then
            -- One coin per line.
            local lines = mod.MoneyTokens(
                money,
                cfg.showSmall == true,
                cfg.coinIcons == true,
                coinColours,
                cfg.abbreviate == true,
                cfg.forceEnglishUnits == true
            )
            mod.SetFont(label, min(fontSize, max(10, floor(K.CONTENT_BASE * 0.52 + 0.5))), barCtx.cfg)
            label:SetText(concat(lines, "\n"))
        else
            label:SetText(MoneyText(money, coinColours))
        end
        label:SetTextColor(red, green, blue, 1)
        if cfg.showBagSpace == true then
            slots:SetText("(" .. FreeSlots() .. ")")
            slots:Show()
        else
            slots:Hide()
        end
        slots:SetTextColor(red, green, blue, 1)
        if iconSize > 0 then
            iconTex:SetSize(iconSize, iconSize)
            PaintIcon()
            iconTex:Show()
        else
            iconTex:Hide()
        end

        if barCtx.IsVertical() then
            -- Icon, the coins, then the slot count, stacked and centred.
            local slotW = K.VSlotW(self)
            local inner = max(30, slotW - 8)
            local height = 8
            if iconSize > 0 then
                iconTex:ClearAllPoints()
                iconTex:SetPoint("TOP", button, "TOP", 0, -4)
                height = height + iconSize + 2
            end
            mod.SetWrappedText(label, inner, "CENTER")
            label:ClearAllPoints()
            if iconSize > 0 then
                label:SetPoint("TOP", iconTex, "BOTTOM", 0, -2)
            else
                label:SetPoint("TOP", button, "TOP", 0, -4)
            end
            height = height + mod.SnapToPixelGrid(label:GetStringHeight())
            if slots:IsShown() then
                mod.SetWrappedText(slots, inner, "CENTER")
                slots:ClearAllPoints()
                slots:SetPoint("TOP", label, "BOTTOM", 0, -2)
                height = height + 2 + mod.SnapToPixelGrid(slots:GetStringHeight())
            end
            height = max(height, barH)
            button:SetSize(slotW, height)
            contentFrame:SetSize(slotW, height)
        else
            -- Icon, money, slot count in a row. The width is that of the wider
            -- of the two money texts (coloured and plain), so hover never
            -- resizes the block.
            local budget = K.HBudget(self, 100)
            mod.ResetInlineText(label, "LEFT")
            mod.ResetInlineText(slots, "LEFT")
            iconTex:SetSize(iconSize, iconSize)
            iconTex:ClearAllPoints()
            iconTex:SetPoint("LEFT", button, "LEFT", 0, 0)
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", iconSize + gap, 0)
            slots:ClearAllPoints()
            slots:SetPoint("LEFT", label, "RIGHT", 4, 0)
            local slotsW = cfg.showBagSpace == true and (slots:GetStringWidth() or 0) + 4 or 0
            local moneyW = label:GetStringWidth() or 0
            local ruler = mod.MeasureFS()
            if ruler then
                mod.SetFont(ruler, fontSize, barCtx.cfg)
                ruler:SetText(MoneyText(money, not coinColours and blockCfg.useCoinColor == true))
                moneyW = max(moneyW, ruler:GetStringWidth() or 0)
            end
            local width = min(budget, iconSize + gap + moneyW + slotsW + 4)
            button:SetSize(width, barH)
            contentFrame:SetSize(width, barH)
        end
        button:ClearAllPoints()
        button:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
        K.MaybeRelayout(self)
    end

    -- Hover: across, the width already fits both texts, so only the text and
    -- colours change; on a side bar each coin is its own line, so redraw.
    local function Repaint()
        if barCtx.IsVertical() then
            inst:Refresh()
            return
        end
        label:SetText(MoneyText(Ledger.Money() or 0, blockCfg.useCoinColor == true and not hovered))
        local red, green, blue = TextColour()
        label:SetTextColor(red, green, blue, 1)
        slots:SetTextColor(red, green, blue, 1)
        if iconTex:IsShown() then PaintIcon() end
    end

    -- Several changes in one frame are one update, and one that changes
    -- nothing shown draws nothing.
    function inst:QueueRefresh()
        if self._refreshQueued then return end
        self._refreshQueued = true
        C_Timer.After(0, function()
            inst._refreshQueued = false
            if blocks[inst] and State() ~= drawn then inst:Refresh() end
        end)
    end

    local function ShowTooltip()
        local cfg = Settings()
        local small, icons = cfg.showSmall == true, cfg.coinIcons == true
        local function Money(copper) return mod.FormatMoney(copper, true, small, icons) end
        -- Characters and the warbank need account tracking (Bags options);
        -- the session needs nothing.
        local tracking = Ledger.IsTracking()
        local withChars = cfg.tipCharacters ~= false and tracking
        mod.Tip_Begin(button)
        mod.Tip_AddLine(L["GOLD"], 1, 1, 1)
        if cfg.tipSession ~= false then
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(L["SESSION"], 0.8, 0.8, 0.8)
            mod.Tip_AddDouble(L["EARNED"], Money(session.earned), 0.6, 0.6, 0.6, 0, 1, 0)
            mod.Tip_AddDouble(L["SPENT"], Money(session.spent), 0.6, 0.6, 0.6, 1, 0.3, 0.3)
            local net = session.earned - session.spent
            if net > 0 then
                mod.Tip_AddDouble(L["PROFIT"], Money(net), 0.6, 0.6, 0.6, 0, 1, 0.3)
            elseif net < 0 then
                mod.Tip_AddDouble(L["DEFICIT"], Money(abs(net)), 0.6, 0.6, 0.6, 1, 0.3, 0.3)
            end
        end
        local listed, unlisted = 0, 0 -- unlisted: characters left out (the hint offers them)
        if withChars then
            local chars = Ledger.Data().chars
            local me = Ledger.CharKey()
            -- Only balances over 10,000 gold, plus the live character; the
            -- rest still count in the total. Shift shows everyone, with no
            -- row limit; WoW Forever has no floor (vanilla balances are small).
            local all = IsShiftKeyDown()
            local noFloor = all or CUI.IS_FOREVER
            local floorCopper = 10000 * 10000
            local sum, keys = 0, {}
            for key, entry in pairs(chars) do
                local copper = entry and entry.money -- the ledger stores numbers only
                if copper then
                    if noFloor or copper > floorCopper or key == me then
                        keys[#keys + 1] = key
                    else
                        unlisted = unlisted + 1
                    end
                    sum = sum + copper
                end
            end
            table.sort(keys, function(lhs, rhs) return (chars[lhs].money or 0) > (chars[rhs].money or 0) end)
            listed = #keys
            local realmCount = 0
            if listed > 0 then
                -- At most 10 rows, so many alts cannot push the total off screen.
                local realms, byRealm, left = ByRealm(chars, keys, all, me, 10)
                realmCount = #realms
                for _, realm in ipairs(realms) do
                    mod.Tip_AddLine(" ")
                    mod.Tip_AddLine(realm, 0.5, 0.78, 1)
                    for _, key in ipairs(byRealm[realm]) do
                        local entry = chars[key]
                        local color = entry.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class]
                        local red, green, blue = 1, 1, 1
                        if color then
                            red, green, blue = color.r, color.g, color.b
                        end
                        -- Ctrl+Alt+click forgets a character; never this one,
                        -- which is saved again on every money change.
                        local coins = mod.MoneyTokens(entry.money, small, icons, true)
                        mod.Tip_AddClickableColumns(entry.name or "?", coins, function(mouseButton)
                            if key == me or mouseButton ~= "LeftButton" then return end
                            if IsControlKeyDown() and IsAltKeyDown() then
                                Forget(key)
                                mod.Tip_Hide(button)
                            end
                        end, red, green, blue)
                    end
                end
                if left > 0 then
                    mod.Tip_AddLine(format(L["PLUS_N_MORE"], left), 0.6, 0.6, 0.6)
                    unlisted = unlisted + left
                end
            end
            -- The warbank is the last row (set apart when there are several
            -- realms, as it belongs to none): live when readable, else last known.
            Ledger.RecordWarband()
            local warband = Ledger.Data().warband
            local bank = warband and warband.money
            if bank and bank > 0 then
                if realmCount > 1 then mod.Tip_AddLine(" ") end
                mod.Tip_AddColumns(
                    CUI.L("Warbank"),
                    mod.MoneyTokens(bank, small, icons, true),
                    1,
                    0.82,
                    0
                )
                sum = sum + bank
            end
            mod.Tip_AddLine(" ")
            mod.Tip_AddDouble(L["TOTAL"], Money(sum), 1, 1, 1, 1, 1, 1)
        elseif not tracking and cfg.tipCharacters ~= false then
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(CUI.L("Account gold tracking is disabled"), 0.6, 0.6, 0.6)
        end
        if cfg.tipToken ~= false and session.tokenPrice and session.tokenPrice > 0 then
            mod.Tip_AddLine(" ")
            mod.Tip_AddDouble(L["WOW_TOKEN"], Money(session.tokenPrice), 0, 0.8, 1, 1, 1, 1)
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_BAGS"], 1, 1, 1, 1, 1, 1)
        mod.Tip_AddDouble(L["RIGHT_CLICK"], L["OPEN_CURRENCIES"], 1, 1, 1, 1, 1, 1)
        mod.Tip_AddDouble(L["CTRL_RIGHT_CLICK"], L["RESET_SESSION"], 1, 1, 1, 1, 1, 1)
        if withChars then
            mod.Tip_AddDouble(L["CTRL_SHIFT_RIGHT_CLICK"], L["RESET_ALL_DATA"], 1, 1, 1, 1, 1, 1)
        end
        if listed > 1 then
            mod.Tip_AddDouble(L["CTRL_ALT_LEFT_CLICK"], L["REMOVE_CHARACTER"], 1, 1, 1, 1, 1, 1)
        end
        if unlisted > 0 then
            mod.Tip_AddDouble(L["SHIFT_HOVER"], L["SHOW_EVERY_CHARACTER"], 1, 1, 1, 1, 1, 1)
        end
        mod.Tip_Show()
    end

    button:SetScript("OnEnter", function()
        hovered = true
        Repaint()
        ShowTooltip()
    end)
    button:SetScript("OnLeave", function()
        hovered = false
        -- The character rows are clickable, so the tooltip outlives the cursor leaving.
        mod.Tip_HideUnlessInteractive(button)
        Repaint()
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" and IsControlKeyDown() and IsShiftKeyDown() then
            mod.Tip_Hide(button)
            CUI:ShowConfirmPopup({
                title = "Reset Gold Data",
                message = "Clear the gold of every character and the warbank? This character and the warbank are recorded again at once, the others when they next log in.",
                confirmText = "Reset",
                cancelText = "Cancel",
                onConfirm = ForgetAll,
            })
        elseif mouseButton == "RightButton" and IsControlKeyDown() then
            session.earned, session.spent = 0, 0
            inst:Refresh()
            -- The tooltip stays up and shows the session at zero.
            if hovered then ShowTooltip() end
        elseif mouseButton == "RightButton" then
            if C_CurrencyInfo and C_CurrencyInfo.OpenCurrencyPanel then
                C_CurrencyInfo.OpenCurrencyPanel()
            elseif ToggleCharacter then
                ToggleCharacter("TokenFrame")
            end
        elseif mouseButton == "LeftButton" then
            ToggleAllBags()
        end
    end)

    function inst:Enable()
        contentFrame:Show()
        if session.lastMoney == nil then
            session.lastMoney = Ledger.RecordCharacter()
            session.earned, session.spent = 0, 0
        end
        if C_WowTokenPublic and C_WowTokenPublic.UpdateMarketPrice then
            C_WowTokenPublic.UpdateMarketPrice()
        end
        blocks[self] = true
        Listen()
    end

    function inst:Disable()
        blocks[self] = nil
        Listen()
        contentFrame:Hide()
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
            -- As Refresh: no icon room when icons are off.
            local cfg = blockCfg.settings
            local iconRoom = (not cfg or cfg.showIcons ~= false) and fontSize + 2 or 0
            local textH = label:GetStringHeight() or fontSize
            local slotsH = slots:IsShown() and (slots:GetStringHeight() or 0) + 2 or 0
            return max(8 + iconRoom + textH + slotsH + 4, barCtx.GetThickness(), 50)
        end
        return max(contentFrame:GetWidth() or 100, 40)
    end

    function inst:Destroy()
        self._dead = true
        blocks[self] = nil
        Listen()
        contentFrame:Hide()
    end

    return inst
end
