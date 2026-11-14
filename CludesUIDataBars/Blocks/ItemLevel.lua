if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Blocks\ItemLevel.lua
-- Item level block factory.

local ADDON_NAME, mod = ...
local L = mod.L
local K = mod.BlockKit

-- Upvalues
local _G = _G
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local format = string.format
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
local ParkSecureFrame = K.ParkSecureFrame

-------------------------------------------------------------------------------
--  ITEM LEVEL (equipped / total, with an optional prefix)
-------------------------------------------------------------------------------
mod.BlockFactories.ilvl = function(blockCfg, slot, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)
    -- PLAYER_REGEN_ENABLED: geometry and the secure click overlay both wait for regen, so the block needs a pass there.
    instance.events = {
        "PLAYER_AVG_ITEM_LEVEL_UPDATE",
        "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED",
    }

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

    local icon = btnFrame:CreateTexture(nil, "OVERLAY")
    local ilvlText = btnFrame:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(instance, ilvlText)

    local clickBtn
    local EnsureClickButton -- defined below, after the hover scripts it reuses

    -- Item level returns can be secret values, which detonate the moment they
    -- reach format() or a tooltip width measure (see the micro menu's char
    -- stats block). Strip them here, once, and every consumer below is safe.
    local function AvgIlvl()
        local sum, equipped, pvp = GetAverageItemLevel()
        if issecretvalue then
            if issecretvalue(sum) then
                sum = nil
            end
            if issecretvalue(equipped) then
                equipped = nil
            end
            if issecretvalue(pvp) then
                pvp = nil
            end
        end
        return sum, equipped, pvp
    end

    local function Fmt(val, p)
        if not val then
            return "-"
        end
        return format("%." .. p .. "f", val)
    end

    local function LongLabel()
        return STAT_AVERAGE_ITEM_LEVEL or CludesUI.L(L["ITEM_LEVEL"])
    end

    function instance:Refresh()
        EnsureClickButton()

        local s = D()
        K.SetBlockIcon(icon, blockCfg)
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()
        local gap = ICON_GAP

        local sum, equipped = AvgIlvl()
        -- Published for the "Band" text swatch (and its options preview).
        K.lastAvgIlvl = equipped or sum

        local p = s.precision
        if p == nil then
            p = 0
        end
        local mode = s.value or "equipped"
        local body
        if mode == "total" then
            body = Fmt(sum, p)
        elseif mode == "both" then
            body = Fmt(equipped, p) .. " / " .. Fmt(sum, p)
        else
            body = Fmt(equipped, p)
        end

        -- Bar text goes straight through SetText, which does not route through
        -- the locale like the Tip_* helpers, so the short prefix is translated
        -- by hand; the long one rides Blizzard's own localized global.
        local prefixText = s.prefix or "short"
        local textValue = body
        if prefixText == "short" then
            textValue = CludesUI.L(L["ILVL"]) .. " " .. body
        elseif prefixText == "long" then
            textValue = LongLabel() .. " " .. body
        end

        local iconSz = 0
        if prefixText == "icon" then
            iconSz = fontSize + 2
            icon:Show()
        else
            icon:Hide()
        end

        mod.SetFont(ilvlText, fontSize, barCfg)
        do
            local ir, ig, ib = IconColorOf(blockCfg)
            icon:SetVertexColor(ir, ig, ib, 1)
        end
        if mouseOver then
            ilvlText:SetTextColor(mod.GetAccent())
        else
            ilvlText:SetTextColor(BlockColorOf(blockCfg))
        end
        -- Sizing and anchoring are protected once the secure click overlay exists
        -- (it puts this block's whole bar under protection): in lockdown only the
        -- text updates, geometry waits for PLAYER_REGEN_ENABLED.
        if InCombatLockdown() then
            ilvlText:SetText(textValue)
            return
        end
        if isSide then
            local slotW = VSlotW(instance)
            local innerW = max(24, slotW - 8)
            ilvlText:SetText(textValue)
            local totalH = 8
            if iconSz > 0 then
                icon:SetSize(iconSz, iconSz)
                icon:ClearAllPoints()
                icon:SetPoint("TOP", btnFrame, "TOP", 0, -4)
                totalH = totalH + iconSz + 2
            end
            mod.SetWrappedText(ilvlText, innerW, "CENTER")
            ilvlText:ClearAllPoints()
            if iconSz > 0 then
                ilvlText:SetPoint("TOP", icon, "BOTTOM", 0, -2)
            else
                ilvlText:SetPoint("TOP", btnFrame, "TOP", 0, -4)
            end
            totalH = totalH + mod.SnapToPixelGrid(ilvlText:GetStringHeight()) + 4
            totalH = max(totalH, barH)
            contentFrame:SetSize(slotW, totalH)
            btnFrame:SetSize(slotW, totalH)
        else
            local slotW = HBudget(instance, 120)
            mod.ResetInlineText(ilvlText, "LEFT")
            ilvlText:SetText(textValue)
            if iconSz > 0 then
                icon:SetSize(iconSz, iconSz)
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", btnFrame, "LEFT", 0, 0)
            end
            ilvlText:ClearAllPoints()
            local xOff = 0
            if iconSz > 0 then
                xOff = iconSz + gap
            end
            ilvlText:SetPoint("LEFT", btnFrame, "LEFT", xOff, 0)
            local tw = mod.SnapToPixelGrid(ilvlText:GetStringWidth())
            local totalW = min(slotW, xOff + tw + 4)
            contentFrame:SetSize(max(totalW, 10), barH)
            btnFrame:SetSize(max(totalW, 10), barH)
        end

        MaybeRelayout(instance)
    end

    local function ShowIlvlTooltip()
        local ar, ag, ab = mod.GetAccent()
        local sum, equipped, pvp = AvgIlvl()
        mod.Tip_Begin(btnFrame)
        mod.Tip_AddLine(LongLabel(), 1, 1, 1)
        mod.Tip_AddLine(" ")
        if equipped then
            mod.Tip_AddDouble(L["EQUIPPED"], format("%.2f", equipped), 0.6, 0.6, 0.6, 1, 1, 1)
        end
        if sum then
            mod.Tip_AddDouble(L["TOTAL"], format("%.2f", sum), 0.6, 0.6, 0.6, 1, 1, 1)
        end
        -- PvP item level only exists in PvP-scaled gear; hide the row otherwise.
        if pvp and pvp > 0 then
            mod.Tip_AddDouble(L["PVP_ITEM_LEVEL"], format("%.2f", pvp), 0.6, 0.6, 0.6, 1, 1, 1)
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_CHARACTER"], 1, 1, 1, ar, ag, ab)
        mod.Tip_Show()
    end

    btnFrame:SetScript("OnEnter", function()
        mouseOver = true
        instance:Refresh()
        ShowIlvlTooltip()
    end)
    btnFrame:SetScript("OnLeave", function()
        mouseOver = false
        mod.Tip_Hide(btnFrame)
        instance:Refresh()
    end)
    -- Fallback only: used until the secure overlay exists (block built mid-combat,
    -- or no CharacterMicroButton). ToggleCharacter from addon Lua taints
    -- CharacterFrame's show path (secret health values -> TextStatusBar error).
    btnFrame:SetScript("OnClick", function(_, mb)
        if mb == "LeftButton" and ToggleCharacter then
            ToggleCharacter("PaperDollFrame")
        end
    end)

    -- Secure click passthrough to Blizzard's CharacterMicroButton, same mechanism as
    -- the location and micro menu blocks: the click runs inside Blizzard's own
    -- handler, so the character sheet opens untainted. Created lazily, never in
    -- lockdown; PLAYER_REGEN_ENABLED drives Refresh's retry.
    EnsureClickButton = function()
        if clickBtn or InCombatLockdown() then
            return clickBtn
        end
        local micro = _G.CharacterMicroButton
        if not micro then
            return nil
        end
        clickBtn = CreateFrame(
            "Button",
            "EWB_ILVL_" .. instance.key,
            btnFrame,
            "SecureActionButtonTemplate,SecureHandlerStateTemplate"
        )
        clickBtn:SetAllPoints(btnFrame)
        clickBtn:SetAttribute("*clickbutton1", micro)
        -- Without this, the ActionButtonUseKeyDown CVar makes the secure handler act on key-down only, discarding our "AnyUp" clicks.
        clickBtn:SetAttribute("useOnKeyDown", false)
        clickBtn:SetAttribute("*type1", "click")
        clickBtn:EnableMouse(true)
        clickBtn:RegisterForClicks("AnyUp")
        -- Combat: drop the click ACTION only, from inside the secure env. Stays mouse-enabled so hover works; a click while *type1 is nil does nothing.
        RegisterStateDriver(clickBtn, "combatlock", "[combat] combat; nocombat")
        clickBtn:SetAttribute(
            "_onstate-combatlock",
            [[
            if newstate == 'combat' then
                self:SetAttribute('*type1', nil)
            else
                self:SetAttribute('*type1', 'click')
            end
        ]]
        )
        -- Overlay covers the block and owns hover from here.
        clickBtn:SetScript("OnEnter", btnFrame:GetScript("OnEnter"))
        clickBtn:SetScript("OnLeave", btnFrame:GetScript("OnLeave"))
        return clickBtn
    end

    instance.eventFrame = MakeEventFrame(instance, function(self)
        self:Refresh()
    end)

    function instance:Enable()
        if not contentFrame:IsShown() and not InCombatLockdown() then
            contentFrame:Show()
        end
        EnsureClickButton()
        RegisterInstEvents(self)
    end

    function instance:Disable()
        UnregisterInstEvents(self)
        -- Protected once the secure click overlay exists.
        if not InCombatLockdown() then
            contentFrame:Hide()
        end
    end

    function instance:GetAutoLength()
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 30)
        end
        return max(contentFrame:GetWidth() or 60, 24)
    end

    function instance:Destroy()
        self._dead = true
        if clickBtn then
            ParkSecureFrame(clickBtn, self.key .. "_ilvl")
            clickBtn = nil
        end
        if not InCombatLockdown() then
            contentFrame:Hide()
        end
    end

    return instance
end
