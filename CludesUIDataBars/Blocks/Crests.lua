if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if CludesUI.IS_FOREVER then
    return
end -- no season crests on WoW Forever: no factory, no ns.CrestColorMode (the main file drops the block from BLOCK_TYPES too)
-- Blocks\Crests.lua
-- Crests block factory.

local ADDON_NAME, mod = ...
local L = mod.L
local Keys = mod.BlockKit

-- Upvalues
local CreateFrame = CreateFrame
local wipe = wipe
local format = string.format
local tconcat = table.concat
local floor = math.floor
local upper = math.max
local min = math.min

local CONTENT_BASE = Keys.CONTENT_BASE
local CRESTS = Keys.CRESTS
local InstKey = Keys.InstKey
local MakeEventFrame = Keys.MakeEventFrame
local RegisterInstEvents = Keys.RegisterInstEvents
local UnregisterInstEvents = Keys.UnregisterInstEvents
local HBudget = Keys.HBudget
local VSlotW = Keys.VSlotW
local MaybeRelayout = Keys.MaybeRelayout
local AttachTextOffset = Keys.AttachTextOffset
local BlockColorOf = Keys.BlockColorOf

-------------------------------------------------------------------------------
--  CRESTS (season upgrade currencies, one compact readout)
--
--  Renders into ONE FontString using inline |T|t icon and |cff color escapes
--  rather than a texture/fontstring pair per crest: the segment count is
--  variable (the checklist and Hide Empty both drop entries) and crest coloring
--  is per-segment anyway, so a single measured string beats up to fourteen
--  regions. Same reason its icons sit out of the Icon Color row -- see the note
--  by ICON_DEFAULTS in Blocks\Shared.lua.
-------------------------------------------------------------------------------

-- Separator glyph. A literal pipe has to be doubled or the text engine reads it
-- as the start of an escape sequence.
-- Dim tone for the tooltip's secondary (season progress) figure. Same value the
-- character stats tooltip uses for its parenthesized ratings, kept local so the
-- two sections stay independent.
local CREST_DIM = "|cffaaaaaa"

local CREST_SEPARATORS = {
    slash = " / ",
    line = " || ",
    dash = " - ",
    space = "   ",
}

-- Crest Colors is this block's nothing-stored default, so it resolves the same
-- way the Icon Color row's "Default" swatch does instead of Gold's forced
-- one-shot write: an untouched block is crest colored, and the first Custom
-- click seeds b.color, which takes over. Shared with the options page so the
-- 4th swatch lights on exactly this test.
function mod.CrestColorMode(b)
    if b.useCrestColor then
        return true
    end
    return not b.useClassColor and not b.useAccentColor and not b.useDynamicColor and b.color == nil
end

mod.BlockFactories.crests = function(blockCfg, slotIndex, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slotIndex, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)
    instance.events = { "CURRENCY_DISPLAY_UPDATE" }

    local mouseOver = false
    -- Reused across refreshes: the string is rebuilt on every currency event,
    -- so a fresh table per pass would allocate in a hot path.
    local _segBuf = {}

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

    local crestText = btnFrame:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(instance, crestText)

    local function GetInfo(ident)
        if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then
            return nil
        end
        return C_CurrencyInfo.GetCurrencyInfo(ident)
    end

    local function Num(val)
        if BreakUpLargeNumbers then
            return BreakUpLargeNumbers(val or 0)
        end
        return tostring(val or 0)
    end

    -- Bar figure. Off: the spendable amount. On: season progress, which for
    -- crests means totalEarned/maxQuantity -- a DIFFERENT number, which is why
    -- the option is labelled Show Season Progress rather than Show Cap.
    local function AmountText(details, seasonProgress)
        local qty = details.quantity or 0
        if not seasonProgress then
            return Num(qty)
        end
        local cap = details.maxQuantity
        if not cap or cap <= 0 then
            return Num(qty)
        end
        local isShown = qty
        if details.useTotalEarnedForMaxQty then
            isShown = details.totalEarned or qty
        end
        return Num(isShown) .. "/" .. Num(cap)
    end

    -- Tooltip figure: the spendable amount first (what the bar shows), then the
    -- season cap progress dimmed in parentheses. Those two diverge as soon as
    -- you spend a crest, so showing only one of them is what made the tooltip
    -- read as contradicting the bar.
    local function TooltipAmount(details)
        local owned = Num(details.quantity or 0)
        local cap = details.maxQuantity
        if not cap or cap <= 0 then
            return owned
        end
        local earned = details.quantity or 0
        if details.useTotalEarnedForMaxQty then
            earned = details.totalEarned or earned
        end
        return owned .. " " .. CREST_DIM .. "(" .. Num(earned) .. "/" .. Num(cap) .. ")|r"
    end

    function instance:Refresh()
        local s = D()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = upper(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()

        local showIcons = s.showIcons ~= false
        local seasonProg = s.showSeasonProgress == true
        local hideEmpty = s.hideEmpty == true
        -- Crest tints are baked into the string, so hovering has to fall back
        -- to plain segments for the accent wash to read (same as Gold).
        local crestMode = mod.CrestColorMode(blockCfg) and not mouseOver
        local iconSz = fontSize + 2

        local from, to, step = 1, #CRESTS, 1
        if s.reverse == true then
            from, to, step = #CRESTS, 1, -1
        end

        wipe(_segBuf)
        for idx = from, to, step do
            local c = CRESTS[idx]
            if s[c.key] ~= false then
                local details = GetInfo(c.id)
                local seg
                if details then
                    if not (hideEmpty and (details.quantity or 0) <= 0) then
                        seg = AmountText(details, seasonProg)
                        if showIcons and details.iconFileID then
                            seg = format(
                                "|T%s:%d:%d:0:0:64:64:5:59:5:59|t",
                                details.iconFileID,
                                iconSz,
                                iconSz
                            ) .. seg
                        end
                        if crestMode then
                            seg = "|cff" .. c.hex .. seg .. "|r"
                        end
                    end
                else
                    seg = "-"
                end
                if seg then
                    _segBuf[#_segBuf + 1] = seg
                end
            end
        end

        local textValue
        if #_segBuf == 0 then
            -- Everything filtered out (Hide Empty on an empty wallet, or the
            -- whole checklist cleared): a placeholder keeps the block on the
            -- bar instead of silently collapsing to nothing.
            textValue = "-"
        elseif isSide then
            -- One crest per line on a side bar, like the Gold block's tokens.
            textValue = tconcat(_segBuf, "\n")
        else
            local sep = CREST_SEPARATORS[s.separator or "slash"] or CREST_SEPARATORS.slash
            if crestMode then
                sep = "|cff808080" .. sep .. "|r"
            end
            textValue = tconcat(_segBuf, sep)
        end

        mod.SetFont(crestText, fontSize, barCfg)
        if isSide then
            local slotW = VSlotW(instance)
            local innerW = upper(24, slotW - 8)
            crestText:SetText(textValue)
            mod.SetWrappedText(crestText, innerW, "CENTER")
            crestText:ClearAllPoints()
            crestText:SetPoint("TOP", btnFrame, "TOP", 0, -4)
            local totalH = upper(8 + mod.SnapToPixelGrid(crestText:GetStringHeight()), barH)
            contentFrame:SetSize(slotW, totalH)
            btnFrame:SetSize(slotW, totalH)
        else
            local slotW = HBudget(instance, 200)
            mod.ResetInlineText(crestText, "LEFT")
            crestText:SetText(textValue)
            crestText:ClearAllPoints()
            crestText:SetPoint("LEFT", btnFrame, "LEFT", 0, 0)
            local tw = mod.SnapToPixelGrid(crestText:GetStringWidth())
            local totalW = min(slotW, tw + 4)
            contentFrame:SetSize(upper(totalW, 10), barH)
            btnFrame:SetSize(upper(totalW, 10), barH)
        end

        if mouseOver then
            crestText:SetTextColor(mod.GetAccent())
        elseif crestMode then
            -- Every segment carries its own escape; a white base keeps the
            -- separators and any placeholder neutral.
            crestText:SetTextColor(1, 1, 1, 1)
        else
            crestText:SetTextColor(BlockColorOf(blockCfg))
        end
        MaybeRelayout(instance)
    end

    local function ShowCrestTooltip()
        local ar, ag, ab = mod.GetAccent()
        mod.Tip_Begin(btnFrame)
        -- The header row doubles as the column legend: the parenthesized
        -- figure below is the same one Blizzard's currency tooltip prints
        -- under "Current season maximum", so naming it here costs no extra row.
        mod.Tip_AddDouble(L["CRESTS"], L["SEASON_MAXIMUM"], 1, 1, 1, 0.667, 0.667, 0.667)
        mod.Tip_AddLine(" ")
        -- All five, whatever the bar shows: the block is the compact view and
        -- the tooltip is the full one.
        for idx = 1, #CRESTS do
            local c = CRESTS[idx]
            local details = GetInfo(c.id)
            if details then
                mod.Tip_AddDouble(details.name or "?", TooltipAmount(details), c.r, c.g, c.b, 1, 1, 1)
            end
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_CURRENCIES"], 1, 1, 1, ar, ag, ab)
        mod.Tip_Show()
    end

    btnFrame:SetScript("OnEnter", function()
        mouseOver = true
        instance:Refresh()
        ShowCrestTooltip()
    end)
    btnFrame:SetScript("OnLeave", function()
        mouseOver = false
        mod.Tip_Hide(btnFrame)
        instance:Refresh()
    end)
    btnFrame:SetScript("OnClick", function(_, mb)
        if mb ~= "LeftButton" then
            return
        end
        if C_CurrencyInfo and C_CurrencyInfo.OpenCurrencyPanel then
            C_CurrencyInfo.OpenCurrencyPanel()
        elseif ToggleCharacter then
            ToggleCharacter("TokenFrame")
        end
    end)

    -- Payload-gated: a single-currency update that is not a crest is skipped;
    -- a nil currencyType (bulk update) refreshes.
    instance.eventFrame = MakeEventFrame(instance, function(self, _, currencyType)
        if currencyType and not mod.CREST_IDS[currencyType] then
            return
        end
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
            return upper(contentFrame:GetHeight() or 40, 30)
        end
        return upper(contentFrame:GetWidth() or 120, 24)
    end

    function instance:Destroy()
        self._dead = true
        contentFrame:Hide()
    end

    return instance
end
