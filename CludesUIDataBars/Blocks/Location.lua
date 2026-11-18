if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Blocks\Location.lua - Info Bar blocks: the zone, and map coordinates.
--
--  Two blocks on one text renderer, placed independently. Location shows
--  "Zone: Subzone" (or just the subzone), as wide as the name, or exactly
--  Manual Width. Coordinates show x, y to 0-2 decimals at the width of the
--  widest reading ("88.8, 88.8"), and leave the bar inside dungeons and raids.
--  Hover (either) shows the zone, continent and PvP status; a click opens the
--  world map.
--
--  The click goes through a secure button that presses the game's Quest Log
--  micro button, so the map opens as if the player clicked it. Once that
--  button exists the bar is protected: in combat the text changes and the
--  layout waits for the end of combat.
--
--  Coordinates read the position twice a second (moving raises no event). At
--  a fixed width a new reading just sets the text; nothing is laid out again.
--  Zone events draw only when the name (or the instance state) changed.
-------------------------------------------------------------------------------
local _, mod = ...
local L = mod.L
local K = mod.BlockKit

local InCombatLockdown = InCombatLockdown
local format, floor, max = string.format, math.floor, math.max

-- Manual mode's width when none is set; the options slider shows the same.
local DEFAULT_WIDTH = 200
mod.LOC_MAX_WIDTH_DEFAULT = DEFAULT_WIDTH

-- The map pin is tall and narrow, so it needs less room than wide icons.
local ICON_EXTRA = 4

-- The width mode, in one place for the block and the options page.
function mod.LocationWidthMode(s)
    return s.widthMode or "auto"
end

local COORD_FORMAT = { [0] = "%.0f, %.0f", [1] = "%.1f, %.1f", [2] = "%.2f, %.2f" }
local COORD_WIDEST = { [0] = "88, 88", [1] = "88.8, 88.8", [2] = "88.88, 88.88" }

local CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2

-- "Zone: Subzone", or the subzone (the minimap's text already falls back to
-- the zone where there is no subzone).
local function PlaceName(withSubzone)
    local zone = GetRealZoneText() or ""
    local sub = GetMinimapZoneText() or ""
    if withSubzone and sub ~= "" and sub ~= zone then
        return zone .. ": " .. sub
    end
    return sub ~= "" and sub or zone
end

local function Position()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then
        return nil
    end
    local x, y = position:GetXY()
    -- Places with no player map report 0, 0 rather than nothing.
    if not (x and y) or (x == 0 and y == 0) then
        return nil
    end
    return x * 100, y * 100
end

local function Coordinates(precision)
    local x, y = Position()
    if not x then
        return "-"
    end
    return format(COORD_FORMAT[precision] or COORD_FORMAT[0], x, y)
end

local function Continent()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    while mapID and mapID ~= 0 do
        local info = C_Map.GetMapInfo(mapID)
        if not info then
            return nil
        end
        if info.mapType == CONTINENT then
            return info.name
        end
        mapID = info.parentMapID
    end
end

-- The game's own words for the zone's PvP state (the colour comes from
-- ZoneReactionColor, which the block's Dynamic colour also uses).
local PVP_WORDS = {
    sanctuary = "SANCTUARY_TERRITORY",
    arena = "ARENA",
    friendly = "FRIENDLY",
    hostile = "HOSTILE",
    combat = "COMBAT",
    contested = "CONTESTED_TERRITORY",
}
local function Status()
    local pvp = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
    if PVP_WORDS[pvp] then
        return _G[PVP_WORDS[pvp]]
    end
    if IsInInstance() then
        return AGGRO_WARNING_IN_INSTANCE
    end
    return CONTESTED_TERRITORY
end

-- One tooltip for both: they name the same place.
local function ShowTooltip(owner)
    local region, g, b = mod.GetAccent()
    mod.Tip_Begin(owner)
    mod.Tip_AddDouble(ZONE, PlaceName(true), 0.6, 0.6, 0.6, 1, 1, 1)
    local continent = Continent()
    if continent then
        mod.Tip_AddDouble(_G.CONTINENT, continent, 0.6, 0.6, 0.6, 1, 1, 1)
    end
    local sr, sg, sb = K.ZoneReactionColor()
    mod.Tip_AddDouble(STATUS, Status(), 0.6, 0.6, 0.6, sr, sg, sb)
    mod.Tip_AddLine(" ")
    mod.Tip_AddDouble(L["LEFT_CLICK"], L["TOGGLE_WORLD_MAP"], 1, 1, 1, region, g, b)
    mod.Tip_Show()
end

-- spec: text() the string; widest() a width template, or nil to measure the
-- text; width() a fixed width, or nil; collapse() true = off the bar;
-- events; tick (seconds) for a value no event announces.
local function TextBlock(blockCfg, slot, contentFrame, barCtx, spec)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    inst.events = spec.events

    local hovered = false
    local ticker
    local drawnText -- the text on screen (nil while collapsed or not drawn)
    local fixed = false -- the width does not depend on the text
    local owed = false -- something waits for the end of combat

    local widget = CreateFrame("Button", nil, contentFrame)
    widget:SetSize(60, 20)
    widget:EnableMouse(true)
    widget:RegisterForClicks("AnyUp")
    local iconTex = widget:CreateTexture(nil, "OVERLAY")
    iconTex:SetPoint("LEFT")
    local label = widget:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, label)
    label:SetPoint("LEFT")
    local ruler
    if spec.widest then
        ruler = widget:CreateFontString(nil, "OVERLAY")
        ruler:Hide()
    end

    local function Paint()
        local region, g, b
        if hovered then
            region, g, b = mod.GetAccent()
        else
            region, g, b = K.BlockColorOf(blockCfg)
        end
        label:SetTextColor(region, g, b, 1)
        if not hovered then
            region, g, b = K.IconColorOf(blockCfg)
        end
        iconTex:SetVertexColor(region, g, b, 1)
    end

    local function Enter()
        hovered = true
        Paint()
        ShowTooltip(widget)
    end
    local function Leave()
        hovered = false
        mod.Tip_Hide(widget)
        Paint()
    end
    -- Until the secure button exists (made in combat), the block itself takes the hover.
    widget:SetScript("OnEnter", Enter)
    widget:SetScript("OnLeave", Leave)

    -- The secure button: presses the Quest Log micro button (as the micro menu
    -- block does). Never made in combat; in combat its click does nothing
    -- (the state driver drops it) but it keeps the hover.
    local secure
    local function EnsureSecure()
        if secure or InCombatLockdown() then
            return
        end
        local micro = _G.QuestLogMicroButton
        if not micro then
            return
        end
        secure = CreateFrame(
            "Button",
            "CUIInfoBar_Loc_" .. inst.key,
            widget,
            "SecureActionButtonTemplate,SecureHandlerStateTemplate"
        )
        secure:SetAllPoints(widget)
        secure:SetAttribute("*clickbutton1", micro)
        -- Act on the release, whatever the player's act-on-key-down setting.
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

    local function Collapsed()
        return spec.collapse and spec.collapse() or false
    end

    -- text: the string if the caller already read it (a position read allocates).
    function inst:Refresh(text)
        EnsureSecure()
        if not secure then
            owed = true
        end
        local collapsed = Collapsed()
        -- Show/Hide are protected once the secure button exists: only on a
        -- real change, and not in combat.
        if contentFrame:IsShown() == collapsed then
            if InCombatLockdown() then
                owed = true
            else
                contentFrame:SetShown(not collapsed)
            end
        end
        if collapsed then
            drawnText = nil
            K.MaybeRelayout(self)
            return
        end

        local s = blockCfg.settings or {}
        local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        local barH = barCtx.GetThickness()
        text = text or spec.text()
        drawnText = text
        mod.SetFont(label, fontSize, barCtx.cfg)
        label:SetText(text)
        Paint()
        K.SetBlockIcon(iconTex, blockCfg)
        local iconSize = 0
        if s.showIcon ~= false then
            iconSize = fontSize + ICON_EXTRA
            iconTex:SetSize(iconSize, iconSize)
            iconTex:Show()
        else
            iconTex:Hide()
        end
        if InCombatLockdown() then
            owed = true
            fixed = false
            return
        end

        if barCtx.IsVertical() then
            local slotW = K.VSlotW(self)
            local inner = max(36, slotW - 8)
            label:ClearAllPoints()
            if iconSize > 0 then
                iconTex:ClearAllPoints()
                iconTex:SetPoint("LEFT", widget, "LEFT", 0, 0)
                label:SetPoint("LEFT", iconTex, "RIGHT", K.ICON_GAP, 0)
                mod.SetWrappedText(label, max(16, inner - iconSize - K.ICON_GAP - 2), "LEFT")
            else
                label:SetPoint("CENTER", widget, "CENTER", 0, 0)
                mod.SetWrappedText(label, inner, "CENTER")
            end
            local lineH =
                max(fontSize + 4, iconSize, mod.SnapToPixelGrid(label:GetStringHeight() or fontSize))
            widget:SetSize(inner, lineH)
            widget:ClearAllPoints()
            widget:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
            contentFrame:SetSize(slotW, max(lineH + 8, barH))
            fixed = false -- wrapped text can change height
        else
            mod.ResetInlineText(label, "LEFT")
            local lead = 0
            if iconSize > 0 then
                lead = iconSize + K.ICON_GAP
                iconTex:ClearAllPoints()
                iconTex:SetPoint("LEFT", widget, "LEFT", 0, 0)
            end
            label:ClearAllPoints()
            label:SetPoint("LEFT", widget, "LEFT", lead, 0)
            -- Manual width: exactly this wide whatever the name (longer ones
            -- are cut off), the only mode that never moves neighbours. Not
            -- taken from the slot: in automatic sizing the slot is this
            -- block's own width, which would shrink it on every pass.
            local width = spec.width and spec.width()
            if width then
                label:SetWidth(max(20, width - lead - 2))
                label:SetWordWrap(false)
                fixed = true
            elseif spec.widest then
                mod.SetFont(ruler, fontSize, barCtx.cfg)
                ruler:SetText(spec.widest())
                width = lead + mod.SnapToPixelGrid(ruler:GetStringWidth() or 40) + 2
                fixed = true
            else
                width = lead + mod.SnapToPixelGrid(label:GetStringWidth() or 40) + 2
                fixed = false
            end
            width = max(width, 24)
            widget:SetSize(width, barH)
            widget:ClearAllPoints()
            widget:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
            contentFrame:SetSize(width, barH)
        end
        if secure and not InCombatLockdown() then
            owed = false
        end
        K.MaybeRelayout(self)
    end

    -- A new text: nothing if the same, just the text at a fixed width, else a pass.
    local function Show(text)
        if text == drawnText then
            return
        end
        if fixed and drawnText then
            label:SetText(text)
            drawnText = text
            Paint() -- the Dynamic colour follows the zone
        else
            inst:Refresh(text)
        end
    end

    -- The end of combat: only if something waited for it. Other events: a
    -- pass if the block appears or leaves, else only a changed text.
    inst.eventFrame = K.MakeEventFrame(inst, function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if owed then
                self:Refresh()
            end
            return
        end
        if owed or Collapsed() ~= (drawnText == nil) then
            self:Refresh()
        elseif drawnText then
            Show(spec.text())
        end
    end)

    function inst:Enable()
        if not contentFrame:IsShown() and not InCombatLockdown() then
            contentFrame:Show()
        end
        drawnText = nil
        EnsureSecure()
        K.RegisterInstEvents(self)
        -- Twice a second (as the minimap's coordinates): the one-second
        -- heartbeat makes running numbers visibly jump.
        if spec.tick and not ticker then
            ticker = C_Timer.NewTicker(spec.tick, function()
                -- Off the bar (in an instance): leaving it is an event, so nothing to do.
                if not Collapsed() then
                    Show(spec.text())
                end
            end)
        end
    end

    function inst:Disable()
        K.UnregisterInstEvents(self)
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        if not InCombatLockdown() then
            contentFrame:Hide() -- protected once the secure button exists
        end
    end

    function inst:GetAutoLength()
        if not contentFrame:IsShown() then
            return 0
        end
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 30)
        end
        return max(contentFrame:GetWidth() or 60, 24)
    end

    function inst:Destroy()
        self._dead = true
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        if secure then
            K.ParkSecureFrame(secure, self.key .. "_loc")
            secure = nil
        end
        if not InCombatLockdown() then
            contentFrame:Hide()
        end
    end

    return inst
end

mod.BlockFactories.location = function(blockCfg, slot, contentFrame, barCtx)
    local function Settings()
        return blockCfg.settings or {}
    end
    return TextBlock(blockCfg, slot, contentFrame, barCtx, {
        events = {
            "ZONE_CHANGED",
            "ZONE_CHANGED_INDOORS",
            "ZONE_CHANGED_NEW_AREA",
            "PLAYER_ENTERING_WORLD",
            "PLAYER_REGEN_ENABLED",
        },
        text = function()
            return PlaceName(Settings().showSubZone ~= false)
        end,
        -- Sized from the live name (zone changes are rare; reserving the
        -- longest zone name would waste the space all the time).
        width = function()
            local s = Settings()
            if mod.LocationWidthMode(s) ~= "manual" then
                return nil
            end
            return s.maxWidth or DEFAULT_WIDTH
        end,
    })
end

mod.BlockFactories.coords = function(blockCfg, slot, contentFrame, barCtx)
    local function Settings()
        return blockCfg.settings or {}
    end
    local function Precision()
        return Settings().precision or 0
    end
    return TextBlock(blockCfg, slot, contentFrame, barCtx, {
        events = { "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" },
        tick = 0.5,
        text = function()
            return Coordinates(Precision())
        end,
        widest = function()
            return COORD_WIDEST[Precision()] or COORD_WIDEST[0]
        end,
        -- Off the bar in dungeons and raids. Housing counts as an instance
        -- but has a real map (its coordinates work); being a sanctuary tells it apart.
        collapse = function()
            if Settings().hideInInstance == false or not IsInInstance() then
                return false
            end
            local pvp = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
            return pvp ~= "sanctuary"
        end,
    })
end
