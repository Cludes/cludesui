if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Blocks\LDB.lua
-- LibDataBroker plugin block factory.

local ADDON_NAME, mod = ...
local L = mod.L
local K = mod.BlockKit

-- Upvalues
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local type = type
local pcall = pcall
local floor = math.floor
local max = math.max

local ICON_GAP = K.ICON_GAP
local CONTENT_BASE = K.CONTENT_BASE
local InstKey = K.InstKey
local MakeEventFrame = K.MakeEventFrame
local RegisterInstEvents = K.RegisterInstEvents
local UnregisterInstEvents = K.UnregisterInstEvents
local VSlotW = K.VSlotW
local MaybeRelayout = K.MaybeRelayout
local AttachTextOffset = K.AttachTextOffset
local BlockColorOf = K.BlockColorOf
local IconColorOf = K.IconColorOf

-------------------------------------------------------------------------------
--  BROKER PLUGIN (LibDataBroker) -- one block type for every data source
-------------------------------------------------------------------------------
-- The only block whose content is written by code we do not own, and three
-- rules follow from that:
--   1. Never write to the data object. A display READS; the plugin owns its own
--      text, and a stray write would fight whoever set it.
--   2. Every call into the plugin (OnEnter/OnLeave/OnClick/OnTooltipShow/
--      OnMouseWheel) goes through pcall. A plugin that errors inside our hover
--      or refresh path would otherwise take the bar's layout down with it.
--   3. Width is never assumed stable. The other text blocks reserve width from
--      a stable template so neighbours never shift; broker text has no shape we
--      can predict, so this one measures live and offers a Max Width clamp.
--
-- Tooltips route three ways, in the plugin's own order of preference:
--   OnEnter        the plugin draws its own tooltip (LibQTip, usually) into the
--                  frame we hand it, and OnLeave takes it away. The owned
--                  tooltip stays out of it -- two tooltips for one block, and
--                  the plugin's is the one carrying the data.
--   OnTooltipShow  the broker contract's GameTooltip path, and the one place in
--                  this addon that still uses GameTooltip: the plugin writes
--                  into it directly, which we cannot re-render.
--   neither        name + text in the owned tooltip, so hover is never dead.

-- Attributes worth a repaint. The library fires a per-NAME event carrying the
-- changed key, so one registration covers the whole plugin and this set decides
-- what is worth redrawing: a bar full of broker blocks never wakes for each
-- other's updates, and a plugin parking its own state on the data object does
-- not drag us through a re-measure for a key we never render.
local LDB_WATCH = {
    text = true,
    value = true,
    suffix = true,
    label = true,
    icon = true,
    iconR = true,
    iconG = true,
    iconB = true,
    iconCoords = true,
}

-- Broker text arrives full of the plugin's own color codes, which silently beat
-- this block's Text Color and its accent hover. Stripping them (default on)
-- hands the color back to the block; leaving them keeps the plugin's palette.
local function LDBStripColors(str)
    if not str then
        return str
    end
    str = str:gsub("|c%x%x%x%x%x%x%x%x", "")
    str = str:gsub("|cn[%a%d_]+:", "") -- named-color form (|cnGREEN_FONT_COLOR:)
    str = str:gsub("|r", "")
    return str
end

-- text is the display string; value+suffix is the fallback pair for plugins
-- that publish the number and its unit separately.
local function LDBDisplayText(object)
    if not object then
        return nil
    end
    local t = object.text
    if type(t) == "string" and t ~= "" then
        return t
    end
    local val = object.value
    if val ~= nil then
        local str = tostring(val)
        local suf = object.suffix
        if type(suf) == "string" and suf ~= "" then
            str = str .. " " .. suf
        end
        return str
    end
    return nil
end

mod.BlockFactories.ldb = function(blockCfg, slot, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)

    local mouseOver = false
    local bound -- source name we currently hold attribute callbacks for
    local tipMode -- "own" | "gametip" | nil; picked at hover, read at leave

    -- The collapse flip below is a Show/Hide, which lockdown can refuse. A block
    -- built or re-sourced mid-combat therefore settles here rather than waiting
    -- for a plugin update that may never come.
    instance.events = { "PLAYER_REGEN_ENABLED" }

    local function D()
        return blockCfg.settings or {}
    end
    local function BC()
        return barCtx.cfg
    end

    local btnFrame = CreateFrame("Button", nil, contentFrame)
    btnFrame:EnableMouse(true)
    btnFrame:RegisterForClicks("AnyUp")

    local icon = btnFrame:CreateTexture(nil, "OVERLAY")
    local textValue = btnFrame:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(instance, textValue)

    -- The chosen source, or nil while its addon has not registered it yet.
    local function Obj()
        local name = D().source
        if not name then
            return nil
        end
        local LDB = mod.GetLDB()
        if not LDB then
            return nil
        end
        return LDB:GetDataObjectByName(name)
    end

    local function Unbind()
        local LDB = mod.GetLDB()
        if LDB and bound then
            pcall(LDB.UnregisterCallback, instance, "LibDataBroker_AttributeChanged_" .. bound)
        end
        bound = nil
    end

    -- Idempotent: re-binds only when the chosen source actually changed.
    local function Bind()
        local name = D().source
        if bound == name then
            return
        end
        Unbind()
        if not name then
            return
        end
        local LDB = mod.GetLDB()
        if not LDB then
            return
        end
        -- Args are (event, sourceName, key, value, obj); only the key matters.
        local function OnAttr(_, _, key)
            if LDB_WATCH[key] and not instance._dead then
                instance:Refresh()
            end
        end
        pcall(LDB.RegisterCallback, instance, "LibDataBroker_AttributeChanged_" .. name, OnAttr)
        bound = name
    end

    -- Untouched Icon Color leaves the plugin's artwork alone, honouring the
    -- iconR/G/B tint if it declares one; any explicit choice in the options wins,
    -- exactly as on every other icon-bearing block.
    local function IconTint(object)
        local b = blockCfg
        if b.iconColor or b.useIconClassColor or b.useIconAccentColor or b.useIconDefaultColor then
            return IconColorOf(b)
        end
        if object and type(object.iconR) == "number" then
            return object.iconR, object.iconG or 1, object.iconB or 1
        end
        return 1, 1, 1
    end

    function instance:Refresh()
        local s = D()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()
        local gap = ICON_GAP
        Bind()

        local object = Obj()

        -- A source picked on a session where its addon WAS loaded, opened on one
        -- where it is not: collapse rather than show a dead slot. GetAutoLength
        -- reports 0 and the solver drops the block and its gaps entirely.
        local collapsed = (s.source ~= nil) and (object == nil)
        -- Show/Hide can be protected (another block on this bar may hold a
        -- secure child): flip only on a real state change, never in lockdown.
        if contentFrame:IsShown() == collapsed and not InCombatLockdown() then
            if collapsed then
                contentFrame:Hide()
            else
                contentFrame:Show()
            end
        end
        if collapsed then
            MaybeRelayout(instance)
            return
        end

        local str
        local placeholder = false
        if not s.source then
            -- Bar text goes straight through SetText, which does not route
            -- through the locale like the Tip_* helpers do, so translate by hand.
            str = CludesUI.L(L["SELECT_PLUGIN"])
            placeholder = true
        else
            local body = LDBDisplayText(object)
            if s.showText == false then
                body = nil
            end
            local labelFS = object.label
            if s.showLabel and type(labelFS) == "string" and labelFS ~= "" then
                if body then
                    str = labelFS .. ": " .. body
                else
                    str = labelFS
                end
            else
                str = body
            end
            if s.stripColors ~= false then
                str = LDBStripColors(str)
            end
            if not str then
                str = ""
            end
        end

        local iconSz = 0
        local texture = object and object.icon
        if s.showIcon ~= false and texture then
            iconSz = fontSize + 2
            icon:SetTexture(texture)
            local c = object.iconCoords
            if type(c) == "table" and #c == 4 then
                icon:SetTexCoord(c[1], c[2], c[3], c[4])
            else
                icon:SetTexCoord(0, 1, 0, 1)
            end
            icon:SetSize(iconSz, iconSz)
            local ir, ig, ib = IconTint(object)
            icon:SetVertexColor(ir, ig, ib, 1)
            icon:Show()
        else
            icon:Hide()
        end

        -- Only steal the wheel for a plugin that asked for it.
        btnFrame:EnableMouseWheel((object and object.OnMouseWheel) ~= nil)

        if placeholder then
            textValue:SetTextColor(0.55, 0.55, 0.55, 1)
        elseif mouseOver then
            local ar, ag, ab = mod.GetAccent()
            textValue:SetTextColor(ar, ag, ab, 1)
        else
            local tr, tg, tb = BlockColorOf(blockCfg)
            textValue:SetTextColor(tr, tg, tb, 1)
        end

        mod.SetFont(textValue, fontSize, barCfg)

        if isSide then
            local slotW = VSlotW(instance)
            local innerW = max(24, slotW - 8)
            local totalH = 8
            if iconSz > 0 then
                icon:ClearAllPoints()
                icon:SetPoint("TOP", btnFrame, "TOP", 0, -4)
                totalH = totalH + iconSz + 2
            end
            mod.SetWrappedText(textValue, innerW, "CENTER")
            textValue:SetText(str)
            textValue:ClearAllPoints()
            if iconSz > 0 then
                textValue:SetPoint("TOP", icon, "BOTTOM", 0, -2)
            else
                textValue:SetPoint("TOP", btnFrame, "TOP", 0, -4)
            end
            totalH = totalH + mod.SnapToPixelGrid(textValue:GetStringHeight() or fontSize) + 4
            totalH = max(totalH, barH)
            contentFrame:SetSize(slotW, totalH)
            btnFrame:SetSize(slotW, totalH)
        else
            mod.ResetInlineText(textValue, "LEFT")
            textValue:SetText(str)
            local iconPad = 0
            if iconSz > 0 then
                iconPad = iconSz + gap
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", btnFrame, "LEFT", 0, 0)
            end
            textValue:ClearAllPoints()
            textValue:SetPoint("LEFT", btnFrame, "LEFT", iconPad, 0)
            local wid = s.maxWidth
            if wid then
                -- Max Width: the block holds this width whatever the plugin
                -- publishes, and longer strings clip. The setting that stops a
                -- chatty broker from shoving its neighbours on every update.
                textValue:SetWidth(max(20, wid - iconPad - 2))
                textValue:SetWordWrap(false)
            else
                wid = iconPad + mod.SnapToPixelGrid(textValue:GetStringWidth() or 40) + 2
            end
            if wid < 24 then
                wid = 24
            end
            contentFrame:SetSize(wid, barH)
            btnFrame:SetSize(wid, barH)
        end

        btnFrame:ClearAllPoints()
        btnFrame:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
        MaybeRelayout(instance)
    end

    local function HideTip()
        if tipMode == "own" then
            local object = Obj()
            if object and object.OnLeave then
                pcall(object.OnLeave, btnFrame)
            end
        elseif tipMode == "gametip" then
            if GameTooltip:IsOwned(btnFrame) then
                GameTooltip:Hide()
            end
        else
            mod.Tip_Hide(btnFrame)
        end
        tipMode = nil
    end

    local function ShowTip()
        local s = D()
        local ar, ag, ab = mod.GetAccent()
        -- Cleared up front so every early return below leaves the LAST hover's
        -- route behind: HideTip reads this to decide whose tooltip to take away.
        tipMode = nil
        -- Unconfigured: the placeholder is the whole block, so the tooltip has
        -- to say where a plugin is actually picked.
        if not s.source then
            mod.Tip_Begin(btnFrame)
            mod.Tip_AddLine(L["SELECT_PLUGIN"], 1, 1, 1)
            mod.Tip_AddLine(" ")
            mod.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_SETTINGS"], 1, 1, 1, ar, ag, ab)
            mod.Tip_Show()
            return
        end
        local object = Obj()
        if not object then
            return
        end
        if object.OnEnter then
            tipMode = "own"
            pcall(object.OnEnter, btnFrame)
            return
        end
        if object.OnTooltipShow then
            tipMode = "gametip"
            GameTooltip:SetOwner(btnFrame, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            -- Same flip the owned tooltip does: a top bar drops its tooltip
            -- below itself, a bottom bar lifts it above.
            if barCtx.IsBarAtTop() then
                GameTooltip:SetPoint("TOPLEFT", btnFrame, "BOTTOMLEFT", 0, -6)
            else
                GameTooltip:SetPoint("BOTTOMLEFT", btnFrame, "TOPLEFT", 0, 6)
            end
            GameTooltip:ClearLines()
            if pcall(object.OnTooltipShow, GameTooltip) then
                GameTooltip:Show()
            else
                GameTooltip:Hide()
                tipMode = nil
            end
            return
        end
        mod.Tip_Begin(btnFrame)
        mod.Tip_AddLine(mod.LDBLabel(s.source, object), 1, 1, 1)
        local body = LDBDisplayText(object)
        if body then
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(LDBStripColors(body), 0.8, 0.8, 0.8)
        end
        mod.Tip_Show()
    end

    btnFrame:SetScript("OnEnter", function()
        mouseOver = true
        instance:Refresh()
        ShowTip()
    end)
    btnFrame:SetScript("OnLeave", function()
        mouseOver = false
        HideTip()
        instance:Refresh()
    end)
    btnFrame:SetScript("OnClick", function(_, mb)
        -- No plugin picked yet: nothing to forward the click to, so send the
        -- player to the picker instead of dead-ending there.
        if not D().source then
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
                mod.OpenBlockSettings(barCtx.id, blockCfg.id, "ldb")
            end
            return
        end
        local object = Obj()
        if object and object.OnClick then
            pcall(object.OnClick, btnFrame, mb)
        end
    end)
    btnFrame:SetScript("OnMouseWheel", function(_, delta)
        local object = Obj()
        if object and object.OnMouseWheel then
            pcall(object.OnMouseWheel, btnFrame, delta)
        end
    end)

    -- A source whose plugin registers later -- its addon loads after us, or on
    -- demand -- binds the moment it appears; without this the block would sit
    -- collapsed until something else happened to force a Refresh.
    local function OnCreated(_, name)
        if name == D().source and not instance._dead then
            Bind()
            instance:Refresh()
        end
    end

    function instance:Enable()
        contentFrame:Show()
        if not self.eventFrame then
            self.eventFrame = MakeEventFrame(self, function(me)
                if not me._dead then
                    me:Refresh()
                end
            end)
        end
        RegisterInstEvents(self)
        local LDB = mod.GetLDB()
        if LDB then
            pcall(LDB.RegisterCallback, instance, "LibDataBroker_DataObjectCreated", OnCreated)
        end
        Bind()
    end

    function instance:Disable()
        UnregisterInstEvents(self)
        local LDB = mod.GetLDB()
        if LDB then
            pcall(LDB.UnregisterCallback, instance, "LibDataBroker_DataObjectCreated")
        end
        Unbind()
        contentFrame:Hide()
    end

    function instance:GetAutoLength()
        if not contentFrame:IsShown() then
            return 0
        end
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 30)
        end
        return max(contentFrame:GetWidth() or 60, 24)
    end

    function instance:Destroy()
        self._dead = true
        UnregisterInstEvents(self)
        local LDB = mod.GetLDB()
        if LDB then
            pcall(LDB.UnregisterCallback, instance, "LibDataBroker_DataObjectCreated")
        end
        Unbind()
        HideTip()
        contentFrame:Hide()
    end

    return instance
end
