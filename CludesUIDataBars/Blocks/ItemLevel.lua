if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  Blocks\ItemLevel.lua - Info Bar block: average item level.
--
--  Shows the equipped or overall average (or both), to 0-2 decimals, with a
--  short ("ilvl"), long ("Item Level"), icon or no prefix. Hover lists both
--  averages and the PvP one when the gear has it; a click opens the
--  character sheet.
--
--  The click goes through a secure button that presses the game's own
--  Character micro button, so the sheet opens as if the player clicked it
--  (opening it from addon code taints it). Once that button exists the bar
--  is protected: in combat the block only changes its text, and its size
--  and place are set again when combat ends.
--
--  Settings (blockCfg.settings): value = "equipped" | "total" | "both";
--  precision (0-2, default 0); prefix = "short" | "long" | "icon" | "none".
-------------------------------------------------------------------------------
local _, mod = ...
local Loc = mod.L
local K = mod.BlockKit

local format, floor, max, min = string.format, math.floor, math.max, math.min

-- The three averages, with any the client keeps secret left out: a secret
-- value breaks format() and text measuring, so it never gets past here.
local function Averages()
    local all, equipped, pvp = GetAverageItemLevel()
    local function Plain(v)
        if issecretvalue and issecretvalue(v) then return nil end
        return v
    end
    return Plain(all), Plain(equipped), Plain(pvp)
end

local function Show(v, decimals) return v and format("%." .. decimals .. "f", v) or "-" end

-- The game's own translated "Item Level" label, else ours.
local function LongLabel() return STAT_AVERAGE_ITEM_LEVEL or CUI.L(Loc["ITEM_LEVEL"]) end

mod.BlockFactories.ilvl = function(blockCfg, slot, contentFrame, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    -- PLAYER_REGEN_ENABLED: size, place and the secure button all wait for the
    -- end of combat, so the block needs a pass then.
    inst.events = {
        "PLAYER_AVG_ITEM_LEVEL_UPDATE",
        "PLAYER_EQUIPMENT_CHANGED",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED",
    }

    local function Settings() return blockCfg.settings or {} end

    local button = CreateFrame("Button", nil, contentFrame)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")
    local iconTex = button:CreateTexture(nil, "OVERLAY")
    local label = button:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, label)

    local hovered = false
    local shownText -- the text on screen; a gear event that would not change it draws nothing
    local secure -- the secure button over the block, made out of combat when the Character button exists

    -- The text for the current averages and settings.
    local function Text()
        local cfg = Settings()
        local all, equipped = Averages()
        -- Shared with the options' "Band" colour swatch and its preview.
        K.lastAvgIlvl = equipped or all
        local decimals = cfg.precision or 0
        local body
        if cfg.value == "total" then
            body = Show(all, decimals)
        elseif cfg.value == "both" then
            body = Show(equipped, decimals) .. " / " .. Show(all, decimals)
        else
            body = Show(equipped, decimals)
        end
        -- Bar text is set directly, not through the tooltip helpers that
        -- translate, so the short prefix is translated here; the long one is
        -- the game's own translated label.
        local prefix = cfg.prefix or "short"
        if prefix == "short" then
            return CUI.L(Loc["ILVL"]) .. " " .. body
        elseif prefix == "long" then
            return LongLabel() .. " " .. body
        end
        return body
    end

    local function PaintText()
        if hovered then
            label:SetTextColor(mod.GetAccent())
        else
            label:SetTextColor(K.BlockColorOf(blockCfg))
        end
    end

    local function ShowTooltip()
        local all, equipped, pvp = Averages()
        mod.Tip_Begin(button)
        mod.Tip_AddLine(LongLabel(), 1, 1, 1)
        mod.Tip_AddLine(" ")
        if equipped then
            mod.Tip_AddDouble(Loc["EQUIPPED"], format("%.2f", equipped), 0.6, 0.6, 0.6, 1, 1, 1)
        end
        if all then mod.Tip_AddDouble(Loc["TOTAL"], format("%.2f", all), 0.6, 0.6, 0.6, 1, 1, 1) end
        -- A PvP average exists only with PvP-scaled gear.
        if pvp and pvp > 0 then
            mod.Tip_AddDouble(Loc["PVP_ITEM_LEVEL"], format("%.2f", pvp), 0.6, 0.6, 0.6, 1, 1, 1)
        end
        mod.Tip_AddLine(" ")
        local red, green, blue = mod.GetAccent()
        mod.Tip_AddDouble(Loc["LEFT_CLICK"], Loc["OPEN_CHARACTER"], 1, 1, 1, red, green, blue)
        mod.Tip_Show()
    end

    -- Hovering only recolours the text; nothing moves, so nothing is laid out again.
    local function Enter()
        hovered = true
        PaintText()
        ShowTooltip()
    end
    local function Leave()
        hovered = false
        mod.Tip_Hide(button)
        PaintText()
    end
    button:SetScript("OnEnter", Enter)
    button:SetScript("OnLeave", Leave)
    -- Until the secure button exists (made in combat, or no Character button):
    -- opening the sheet from here taints it, so this is only the fallback.
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" and ToggleCharacter then ToggleCharacter("PaperDollFrame") end
    end)

    -- The secure button: presses the Character micro button (as the location
    -- and micro menu blocks do). Never made in combat; in combat its click does
    -- nothing (the state driver drops it) but it keeps the hover.
    local function EnsureSecure()
        if secure or InCombatLockdown() then return end
        local micro = _G.CharacterMicroButton
        if not micro then return end
        secure = CreateFrame(
            "Button",
            "CUIInfoBar_ILvl_" .. inst.key,
            button,
            "SecureActionButtonTemplate,SecureHandlerStateTemplate"
        )
        secure:SetAllPoints(button)
        secure:SetAttribute("*clickbutton1", micro)
        -- Act on the release (the button listens for "AnyUp"), whatever the
        -- player's act-on-key-down setting.
        secure:SetAttribute("useOnKeyDown", false)
        secure:SetAttribute("*type1", "click")
        secure:EnableMouse(true)
        secure:RegisterForClicks("AnyUp")
        RegisterStateDriver(secure, "combatlock", "[combat] combat; nocombat")
        secure:SetAttribute(
            "_onstate-combatlock",
            [[
            if newstate == 'combat' then
                self:SetAttribute('*type1', nil)
            else
                self:SetAttribute('*type1', 'click')
            end
        ]]
        )
        secure:SetScript("OnEnter", Enter)
        secure:SetScript("OnLeave", Leave)
    end

    function inst:Refresh()
        EnsureSecure()
        local text = Text()
        shownText = text
        local prefixIcon = (Settings().prefix or "short") == "icon"
        local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        K.SetBlockIcon(iconTex, blockCfg)
        iconTex:SetVertexColor(K.IconColorOf(blockCfg))
        iconTex:SetShown(prefixIcon)
        mod.SetFont(label, fontSize, barCtx.cfg)
        PaintText()
        -- In combat the bar is protected: the text changes, the layout waits.
        if InCombatLockdown() then
            label:SetText(text)
            return
        end
        local iconSize = prefixIcon and fontSize + 2 or 0
        local barH = barCtx.GetThickness()
        if barCtx.IsVertical() then
            -- Icon above the text, both centred in the bar's width.
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
            -- Icon then text, as wide as they need (up to the slot's budget).
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
        K.MaybeRelayout(inst)
    end

    -- A change of gear sends two events; one whose average shows the same
    -- text as now draws nothing. Combat's end always does a pass (the layout
    -- and the secure button wait for it).
    inst.eventFrame = K.MakeEventFrame(inst, function(self, event)
        if
            (event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_AVG_ITEM_LEVEL_UPDATE")
            and Text() == shownText
        then
            return
        end
        self:Refresh()
    end)

    function inst:Enable()
        shownText = nil
        if not contentFrame:IsShown() and not InCombatLockdown() then contentFrame:Show() end
        EnsureSecure()
        K.RegisterInstEvents(self)
    end

    function inst:Disable()
        K.UnregisterInstEvents(self)
        if not InCombatLockdown() then
            contentFrame:Hide() -- protected once the secure button exists
        end
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
        if secure then
            K.ParkSecureFrame(secure, self.key .. "_ilvl")
            secure = nil
        end
        if not InCombatLockdown() then contentFrame:Hide() end
    end

    return inst
end
