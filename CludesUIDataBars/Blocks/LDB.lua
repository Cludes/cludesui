if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  Blocks\LDB.lua - Info Bar block: any LibDataBroker plugin.
--
--  Shows the picked plugin's icon and text (or value and suffix), optionally
--  with its label. Until one is picked it says so and a click opens the block's
--  settings. A plugin picked once but not loaded now collapses the block to
--  nothing rather than leave a dead slot, and fills it the moment it loads.
--
--  The content belongs to someone else's code, so:
--    - the block only READS the data object, never writes to it;
--    - every call into the plugin (OnEnter, OnLeave, OnClick, OnTooltipShow,
--      OnMouseWheel) is wrapped in pcall, so a plugin's error cannot break
--      the bar;
--    - the width is measured live, as the text has no predictable shape;
--      Max Width fixes it so a busy plugin cannot push its neighbours about.
--
--  Hover goes to the plugin's own OnEnter tooltip when it has one, else to
--  OnTooltipShow (the broker contract's GameTooltip, which the plugin writes
--  into itself), else to name and text in our tooltip.
--
--  Plugins update often (an FPS text every second), so an update redraws
--  only what changed: nothing if what is shown is the same, just the text at
--  a fixed Max Width, the layout otherwise.
--
--  Settings (blockCfg.settings): source (the plugin's name), showText,
--  showLabel, showIcon (default on), stripColors (default on), maxWidth.
-------------------------------------------------------------------------------
local _, mod = ...
local Loc = mod.L
local K = mod.BlockKit

local InCombatLockdown = InCombatLockdown
local floor, max = math.floor, math.max

-- The data object's keys this block shows; a change to any other is ignored.
local SHOWN_KEYS = {
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

-- Plugins colour their text, which would beat the block's colour and its
-- hover accent; stripping (the default) gives the colour back to the block.
local function StripColours(text)
    if not text then return text end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|cn[%a%d_]+:", "") -- the named form, |cnGREEN_FONT_COLOR:
    return (text:gsub("|r", ""))
end

-- The plugin's text, or its value and suffix for plugins that publish those.
local function PluginText(object)
    if not object then return nil end
    local text = object.text
    if type(text) == "string" and text ~= "" then return text end
    if object.value ~= nil then
        local out = tostring(object.value)
        local suffix = object.suffix
        if type(suffix) == "string" and suffix ~= "" then out = out .. " " .. suffix end
        return out
    end
    return nil
end

mod.BlockFactories.ldb = function(blockCfg, slot, contentFrame, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    -- Collapsing is a Show/Hide that combat can refuse; it is done when combat ends.
    inst.events = { "PLAYER_REGEN_ENABLED" }

    local function Settings() return blockCfg.settings or {} end

    local button = CreateFrame("Button", nil, contentFrame)
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")
    local iconTex = button:CreateTexture(nil, "OVERLAY")
    local label = button:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, label)

    local hovered = false
    local listening -- the plugin name we hold an update callback for
    local tipRoute -- "plugin" | "gametip" | nil (ours), chosen on hover, undone on leave
    local owesShow = false -- a collapse or uncollapse combat refused
    local drawnText, drawnArt -- what is on screen, to skip updates that change nothing

    -- The picked plugin's data object, or nil while its addon has not made it.
    local function Plugin()
        local name = Settings().source
        local lib = name and mod.GetLDB()
        return lib and lib:GetDataObjectByName(name) or nil
    end

    local function StopListening()
        local lib = mod.GetLDB()
        if lib and listening then
            pcall(lib.UnregisterCallback, inst, "LibDataBroker_AttributeChanged_" .. listening)
        end
        listening = nil
    end

    -- The text to show and whether it is the "pick a plugin" placeholder.
    local function Compose(object)
        local cfg = Settings()
        if not cfg.source then
            -- Bar text is set directly, not through the tooltip helpers that
            -- translate, so it is translated here.
            return CUI.L(Loc["SELECT_PLUGIN"]), true
        end
        local body = cfg.showText ~= false and PluginText(object) or nil
        local name = object.label
        local text = body
        if cfg.showLabel and type(name) == "string" and name ~= "" then
            text = body and (name .. ": " .. body) or name
        end
        if cfg.stripColors ~= false then text = StripColours(text) end
        return text or "", false
    end

    -- With Icon Color untouched the plugin's own tint (iconR/G/B) is used;
    -- a choice in the options wins, as on every other block.
    local function IconTint(object)
        local c = blockCfg
        if c.iconColor or c.useIconClassColor or c.useIconAccentColor or c.useIconDefaultColor then
            return K.IconColorOf(c)
        end
        if object and type(object.iconR) == "number" then
            return object.iconR, object.iconG or 1, object.iconB or 1
        end
        return 1, 1, 1
    end

    -- Everything about the icon that is drawn, as one string.
    local function Art(object)
        local texture = Settings().showIcon ~= false and object and object.icon
        if not texture then return "-" end
        local c = object.iconCoords
        local coords = (type(c) == "table" and #c == 4) and table.concat(c, ",") or "full"
        local red, green, blue = IconTint(object)
        return table.concat({ tostring(texture), coords, red, green, blue }, "|")
    end

    local function PaintText(placeholder)
        if placeholder then
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
        local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        local barH = barCtx.GetThickness()
        self:Listen()
        local object = Plugin()

        -- Picked, but its addon is not loaded: collapse (the bar then drops
        -- the block and its gaps). Show/Hide only on a real change, and not in
        -- combat, where it can be protected.
        local collapsed = cfg.source ~= nil and object == nil
        if contentFrame:IsShown() == collapsed then
            if InCombatLockdown() then
                owesShow = true
            else
                owesShow = false
                contentFrame:SetShown(not collapsed)
            end
        end
        drawnText, drawnArt = nil, nil
        if collapsed then
            K.MaybeRelayout(self)
            return
        end

        local text, placeholder = Compose(object)
        local texture = object and object.icon
        local iconSize = 0
        if cfg.showIcon ~= false and texture then
            iconSize = fontSize + 2
            iconTex:SetTexture(texture)
            local c = object.iconCoords
            if type(c) == "table" and #c == 4 then
                iconTex:SetTexCoord(c[1], c[2], c[3], c[4])
            else
                iconTex:SetTexCoord(0, 1, 0, 1)
            end
            iconTex:SetSize(iconSize, iconSize)
            local red, green, blue = IconTint(object)
            iconTex:SetVertexColor(red, green, blue, 1)
            iconTex:Show()
        else
            iconTex:Hide()
        end
        -- The wheel is taken only for a plugin that uses it.
        button:EnableMouseWheel((object and object.OnMouseWheel) ~= nil)
        PaintText(placeholder)
        mod.SetFont(label, fontSize, barCtx.cfg)

        if barCtx.IsVertical() then
            -- Icon above the text, both centred in the bar's width.
            local slotW = K.VSlotW(self)
            local height = 8
            if iconSize > 0 then
                iconTex:ClearAllPoints()
                iconTex:SetPoint("TOP", button, "TOP", 0, -4)
                height = height + iconSize + 2
            end
            mod.SetWrappedText(label, max(24, slotW - 8), "CENTER")
            label:SetText(text)
            label:ClearAllPoints()
            if iconSize > 0 then
                label:SetPoint("TOP", iconTex, "BOTTOM", 0, -2)
            else
                label:SetPoint("TOP", button, "TOP", 0, -4)
            end
            height = max(height + mod.SnapToPixelGrid(label:GetStringHeight() or fontSize) + 4, barH)
            contentFrame:SetSize(slotW, height)
            button:SetSize(slotW, height)
        else
            -- Icon then text; as wide as the text, or exactly Max Width
            -- (longer text is cut off).
            mod.ResetInlineText(label, "LEFT")
            label:SetText(text)
            local lead = 0
            if iconSize > 0 then
                lead = iconSize + K.ICON_GAP
                iconTex:ClearAllPoints()
                iconTex:SetPoint("LEFT", button, "LEFT", 0, 0)
            end
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", lead, 0)
            local width = cfg.maxWidth
            if width then
                label:SetWidth(max(20, width - lead - 2))
                label:SetWordWrap(false)
            else
                width = lead + mod.SnapToPixelGrid(label:GetStringWidth() or 40) + 2
            end
            width = max(width, 24)
            contentFrame:SetSize(width, barH)
            button:SetSize(width, barH)
        end
        button:ClearAllPoints()
        button:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
        drawnText, drawnArt = text, Art(object)
        K.MaybeRelayout(self)
    end

    -- A plugin update: nothing if what is shown is the same; at a fixed Max
    -- Width on a horizontal bar a new text is just set (the width cannot
    -- change); anything else lays the block out again.
    local function Update()
        if inst._dead then return end
        local object = Plugin()
        if not object or drawnText == nil then
            inst:Refresh()
            return
        end
        local text = Compose(object)
        if Art(object) ~= drawnArt then
            inst:Refresh()
        elseif text ~= drawnText then
            if Settings().maxWidth and not barCtx.IsVertical() then
                label:SetText(text)
                drawnText = text
            else
                inst:Refresh()
            end
        end
    end

    -- Listens to the picked plugin's updates; does nothing if already listening to it.
    function inst:Listen()
        local name = Settings().source
        if listening == name then return end
        StopListening()
        local lib = name and mod.GetLDB()
        if not lib then return end
        -- Called with (event, name, key, value, object); only the key matters.
        pcall(lib.RegisterCallback, inst, "LibDataBroker_AttributeChanged_" .. name, function(_, _, key)
            if SHOWN_KEYS[key] then Update() end
        end)
        listening = name
    end

    local function HideTip()
        if tipRoute == "plugin" then
            local object = Plugin()
            if object and object.OnLeave then pcall(object.OnLeave, button) end
        elseif tipRoute == "gametip" then
            if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        else
            mod.Tip_Hide(button)
        end
        tipRoute = nil
    end

    local function ShowTip()
        local cfg = Settings()
        -- Cleared first, so a return below never leaves the last hover's route.
        tipRoute = nil
        if not cfg.source then
            -- The placeholder is the whole block, so say where a plugin is picked.
            local red, green, blue = mod.GetAccent()
            mod.Tip_Begin(button)
            mod.Tip_AddLine(Loc["SELECT_PLUGIN"], 1, 1, 1)
            mod.Tip_AddLine(" ")
            mod.Tip_AddDouble(Loc["LEFT_CLICK"], Loc["OPEN_SETTINGS"], 1, 1, 1, red, green, blue)
            mod.Tip_Show()
            return
        end
        local object = Plugin()
        if not object then return end
        if object.OnEnter then
            tipRoute = "plugin"
            pcall(object.OnEnter, button)
            return
        end
        if object.OnTooltipShow then
            tipRoute = "gametip"
            GameTooltip:SetOwner(button, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            -- Below a bar at the top of the screen, above one at the bottom.
            if barCtx.IsBarAtTop() then
                GameTooltip:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -6)
            else
                GameTooltip:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 6)
            end
            GameTooltip:ClearLines()
            if pcall(object.OnTooltipShow, GameTooltip) then
                GameTooltip:Show()
            else
                GameTooltip:Hide()
                tipRoute = nil
            end
            return
        end
        mod.Tip_Begin(button)
        mod.Tip_AddLine(mod.LDBLabel(cfg.source, object), 1, 1, 1)
        local body = PluginText(object)
        if body then
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(StripColours(body), 0.8, 0.8, 0.8)
        end
        mod.Tip_Show()
    end

    -- Hovering only recolours the text; nothing moves, so nothing is laid out again.
    button:SetScript("OnEnter", function()
        hovered = true
        PaintText(not Settings().source)
        ShowTip()
    end)
    button:SetScript("OnLeave", function()
        hovered = false
        HideTip()
        PaintText(not Settings().source)
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if not Settings().source then
            -- Nothing to pass the click to: open the block's settings to pick one.
            if InCombatLockdown() then
                CUI.PrintError("Cannot open options during combat.")
                return
            end
            if not mod.OpenBlockSettings then
                CUI:EnsureLoaded() -- the settings load on demand
            end
            if mod.OpenBlockSettings then mod.OpenBlockSettings(barCtx.id, blockCfg.id, "ldb") end
            return
        end
        local object = Plugin()
        if object and object.OnClick then pcall(object.OnClick, button, mouseButton) end
    end)
    button:SetScript("OnMouseWheel", function(_, delta)
        local object = Plugin()
        if object and object.OnMouseWheel then pcall(object.OnMouseWheel, button, delta) end
    end)

    -- A plugin made after us (its addon loads later, or on demand) fills the
    -- block as soon as it exists.
    local function OnCreated(_, name)
        if name == Settings().source and not inst._dead then
            inst:Listen()
            inst:Refresh()
        end
    end

    local function StopAll()
        K.UnregisterInstEvents(inst)
        local lib = mod.GetLDB()
        if lib then pcall(lib.UnregisterCallback, inst, "LibDataBroker_DataObjectCreated") end
        StopListening()
    end

    function inst:Enable()
        contentFrame:Show()
        if not self.eventFrame then
            -- PLAYER_REGEN_ENABLED: only a Show/Hide that combat refused.
            self.eventFrame = K.MakeEventFrame(self, function(me)
                if owesShow and not me._dead then me:Refresh() end
            end)
        end
        K.RegisterInstEvents(self)
        local lib = mod.GetLDB()
        if lib then pcall(lib.RegisterCallback, inst, "LibDataBroker_DataObjectCreated", OnCreated) end
        self:Listen()
    end

    function inst:Disable()
        StopAll()
        contentFrame:Hide()
    end

    function inst:GetAutoLength()
        if not contentFrame:IsShown() then return 0 end
        if barCtx.IsVertical() then return max(contentFrame:GetHeight() or 40, 30) end
        return max(contentFrame:GetWidth() or 60, 24)
    end

    function inst:Destroy()
        self._dead = true
        StopAll()
        HideTip()
        contentFrame:Hide()
    end

    return inst
end
