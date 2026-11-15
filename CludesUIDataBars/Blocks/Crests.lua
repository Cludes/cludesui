if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if CludesUI.IS_FOREVER then
    return
end -- no season crests on WoW Forever (the main file drops the block type there too)
-------------------------------------------------------------------------------
--  Blocks\Crests.lua - Info Bar block: the season's upgrade crests.
--
--  Each ticked crest as icon + amount (or season progress, earned/cap), in
--  its crest colour, joined by a separator (one per line on a side bar). Hover
--  lists all five with what is held and the season's progress; a click opens
--  the currency panel.
--
--  The whole readout is ONE FontString, with inline |T icons and |c colours:
--  the number of crests shown varies (the ticks, Hide Empty) and each has its
--  own colour, so one measured string beats a texture and text per crest.
--
--  Settings (blockCfg.settings): t1..t5 (false = not shown), separator =
--  "slash" | "line" | "dash" | "space", reverse, showIcons (default on),
--  showSeasonProgress, hideEmpty.
-------------------------------------------------------------------------------
local _, mod = ...
local L = mod.L
local K = mod.BlockKit

local format, concat = string.format, table.concat
local floor, max, min = math.floor, math.max, math.min

local DIM = "|cffaaaaaa"
local SEPARATORS = { slash = " / ", line = " || ", dash = " - ", space = "   " } -- a pipe is doubled

-- Crest colours are this block's default: an untouched block is crest
-- coloured, and the first custom colour (b.color) takes over. The options
-- page lights its fourth swatch on the same test.
function mod.CrestColorMode(b)
    if b.useCrestColor then
        return true
    end
    return not b.useClassColor and not b.useAccentColor and not b.useDynamicColor and b.color == nil
end

local function Info(id)
    return C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
end

local function Number(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n or 0) or tostring(n or 0)
end

-- What counts towards the season cap: earned (crests), else what is held.
local function Earned(d)
    if d.useTotalEarnedForMaxQty then
        return d.totalEarned or d.quantity or 0
    end
    return d.quantity or 0
end

-- The bar's figure: what can be spent, or the season's earned/cap (a
-- different number once some are spent, hence "Season Progress", not "Cap").
local function BarAmount(d, progress)
    local cap = d.maxQuantity
    if not progress or not cap or cap <= 0 then
        return Number(d.quantity or 0)
    end
    return Number(Earned(d)) .. "/" .. Number(cap)
end

-- The tooltip's figure: what is held, then the season's progress dimmed, so
-- it never seems to contradict the bar.
local function TipAmount(d)
    local held = Number(d.quantity or 0)
    local cap = d.maxQuantity
    if not cap or cap <= 0 then
        return held
    end
    return held .. " " .. DIM .. "(" .. Number(Earned(d)) .. "/" .. Number(cap) .. ")|r"
end

mod.BlockFactories.crests = function(blockCfg, slot, contentFrame, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    inst.events = { "CURRENCY_DISPLAY_UPDATE" }

    local function Settings()
        return blockCfg.settings or {}
    end

    local button = CreateFrame("Button", nil, contentFrame)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")
    local label = button:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, label)

    local hovered = false
    local drawn -- the text on screen
    local parts = {} -- reused: the text is rebuilt on currency events

    local function FontSize()
        return max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
    end

    -- Crest colours, unless hovered: the accent can only show on plain text.
    local function Coloured()
        return mod.CrestColorMode(blockCfg) and not hovered
    end

    -- The readout for the current settings and amounts.
    local function Compose()
        local s = Settings()
        local coloured = Coloured()
        local iconSize = FontSize() + 2
        local first, last, step = 1, #K.CRESTS, 1
        if s.reverse == true then
            first, last, step = #K.CRESTS, 1, -1
        end
        wipe(parts)
        for i = first, last, step do
            local crest = K.CRESTS[i]
            if s[crest.key] ~= false then
                local d = Info(crest.id)
                if not d then
                    parts[#parts + 1] = "-"
                elseif not (s.hideEmpty == true and (d.quantity or 0) <= 0) then
                    local part = BarAmount(d, s.showSeasonProgress == true)
                    if s.showIcons ~= false and d.iconFileID then
                        part = format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", d.iconFileID, iconSize, iconSize)
                            .. part
                    end
                    if coloured then
                        part = "|cff" .. crest.hex .. part .. "|r"
                    end
                    parts[#parts + 1] = part
                end
            end
        end
        -- All filtered out: a placeholder keeps the block on the bar.
        if #parts == 0 then
            return "-"
        end
        if barCtx.IsVertical() then
            return concat(parts, "\n")
        end
        local sep = SEPARATORS[s.separator or "slash"] or SEPARATORS.slash
        if coloured then
            sep = "|cff808080" .. sep .. "|r"
        end
        return concat(parts, sep)
    end

    local function PaintText()
        if hovered then
            label:SetTextColor(mod.GetAccent())
        elseif Coloured() then
            label:SetTextColor(1, 1, 1, 1) -- each crest carries its own colour
        else
            label:SetTextColor(K.BlockColorOf(blockCfg))
        end
    end

    function inst:Refresh()
        local text = Compose()
        drawn = text
        local barH = barCtx.GetThickness()
        mod.SetFont(label, FontSize(), barCtx.cfg)
        if barCtx.IsVertical() then
            local slotW = K.VSlotW(self)
            label:SetText(text)
            mod.SetWrappedText(label, max(24, slotW - 8), "CENTER")
            label:ClearAllPoints()
            label:SetPoint("TOP", button, "TOP", 0, -4)
            local height = max(8 + mod.SnapToPixelGrid(label:GetStringHeight()), barH)
            contentFrame:SetSize(slotW, height)
            button:SetSize(slotW, height)
        else
            local budget = K.HBudget(self, 200)
            mod.ResetInlineText(label, "LEFT")
            label:SetText(text)
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", 0, 0)
            local width = max(min(budget, mod.SnapToPixelGrid(label:GetStringWidth()) + 4), 10)
            contentFrame:SetSize(width, barH)
            button:SetSize(width, barH)
        end
        PaintText()
        K.MaybeRelayout(self)
    end

    -- Hover swaps crest colours for the accent: colour codes take no width,
    -- so the text changes and nothing is laid out again.
    local function Repaint()
        drawn = Compose()
        label:SetText(drawn)
        PaintText()
    end

    local function ShowTooltip()
        local r, g, b = mod.GetAccent()
        mod.Tip_Begin(button)
        -- The header names the dimmed figure, as the game's own tooltip does.
        mod.Tip_AddDouble(L["CRESTS"], L["SEASON_MAXIMUM"], 1, 1, 1, 0.667, 0.667, 0.667)
        mod.Tip_AddLine(" ")
        -- All five, whatever the bar shows.
        for _, crest in ipairs(K.CRESTS) do
            local d = Info(crest.id)
            if d then
                mod.Tip_AddDouble(d.name or "?", TipAmount(d), crest.r, crest.g, crest.b, 1, 1, 1)
            end
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_CURRENCIES"], 1, 1, 1, r, g, b)
        mod.Tip_Show()
    end

    button:SetScript("OnEnter", function()
        hovered = true
        Repaint()
        ShowTooltip()
    end)
    button:SetScript("OnLeave", function()
        hovered = false
        mod.Tip_Hide(button)
        Repaint()
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then
            return
        end
        if C_CurrencyInfo and C_CurrencyInfo.OpenCurrencyPanel then
            C_CurrencyInfo.OpenCurrencyPanel()
        elseif ToggleCharacter then
            ToggleCharacter("TokenFrame")
        end
    end)

    -- Another currency is ignored; a crest's (or an update of all, which names
    -- none) redraws only if the readout changed.
    inst.eventFrame = K.MakeEventFrame(inst, function(self, _, currencyId)
        if currencyId and not mod.CREST_IDS[currencyId] then
            return
        end
        if Compose() ~= drawn then
            self:Refresh()
        end
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
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 30)
        end
        return max(contentFrame:GetWidth() or 120, 24)
    end

    function inst:Destroy()
        self._dead = true
        contentFrame:Hide()
    end

    return inst
end
