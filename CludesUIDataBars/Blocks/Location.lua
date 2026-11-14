if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Blocks\Location.lua
-- Location and coordinates block factories.

local ADDON_NAME, mod = ...
local L = mod.L
local K = mod.BlockKit

-- Upvalues
local _G = _G
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local format = string.format
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
local ZoneReactionColor = K.ZoneReactionColor
local IconColorOf = K.IconColorOf
local ParkSecureFrame = K.ParkSecureFrame

-------------------------------------------------------------------------------
--  LOCATION + COORDINATES (two block types on one text renderer)
-------------------------------------------------------------------------------
-- Location and coords are separate blocks, placed independently (a bar may want coords
-- alone, or the name centered with numbers to one side); only one sizes from its own text
-- (below). Sourced from live client APIs -- no zone level range or battle pet range, since the client exposes neither, and the data libraries that do carry them are hand-maintained Classic-era tables that say little once level scaling applies.

-- Location block width in Manual mode (px): fits a typical "Zone: Subzone" pair at the
-- default font. Exported so the options slider reports the same number the block renders while maxWidth is unset (two literals would drift).
local LOC_MAX_WIDTH_DEFAULT = 200
mod.LOC_MAX_WIDTH_DEFAULT = LOC_MAX_WIDTH_DEFAULT

-- Icon size above the text size. The map pin is a tall, narrow glyph, so it needs less headroom than the wide icons (durability's forge runs at +7).
local LOC_ICON_EXTRA = 4

-- Effective width mode, resolved in one place so the block and the options page can never disagree (same reason ns.LatencyMode is exported).
function mod.LocationWidthMode(s)
    return s.widthMode or "auto"
end

local COORD_FMT = {
    [0] = "%.0f, %.0f",
    [1] = "%.1f, %.1f",
    [2] = "%.2f, %.2f",
}
-- Width rulers: the readout changes every step, so coords reserves width from each precision's widest value, never the live one (as with "888" stats).
local COORD_TEMPLATE = {
    [0] = "88, 88",
    [1] = "88.8, 88.8",
    [2] = "88.88, 88.88",
}

local CONTINENT_MAP_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2

local function LocDisplayText(showSubZone)
    -- Two reads on purpose: the real zone name builds "Zone: Subzone", while
    -- the minimap zone already falls back to the zone name where there is no
    -- subzone, which IS the subzone-only form with no extra branch.
    local zone = GetRealZoneText() or ""
    local sub = GetMinimapZoneText() or ""
    if showSubZone and sub ~= "" and sub ~= zone then
        return zone .. ": " .. sub
    end
    if sub ~= "" then
        return sub
    end
    return zone
end

local function LocPlayerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit) then
        return nil
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        return nil
    end
    local place = C_Map.GetPlayerMapPosition(mapID, "player")
    if not place then
        return nil
    end
    local posX, posY = place:GetXY()
    -- Instances with no player map report flat 0,0 rather than nothing.
    if not (posX and posY) or (posX == 0 and posY == 0) then
        return nil
    end
    return posX * 100, posY * 100
end

local function LocCoordText(precision)
    local posX, posY = LocPlayerPosition()
    if not posX then
        return "-"
    end
    return format(COORD_FMT[precision] or COORD_FMT[0], posX, posY)
end

local function LocContinentName()
    if not (C_Map and C_Map.GetBestMapForUnit) then
        return nil
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    while mapID and mapID ~= 0 do
        local details = C_Map.GetMapInfo(mapID)
        if not details then
            return nil
        end
        if details.mapType == CONTINENT_MAP_TYPE then
            return details.name
        end
        mapID = details.parentMapID
    end
    return nil
end

-- Status label. COLOR comes from ZoneReactionColor so the tooltip status line and the block's Dynamic text mode agree; labels are localized Blizz globals.
local function LocZoneStatus()
    local pvpType = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
    if pvpType == "sanctuary" then
        return SANCTUARY_TERRITORY
    end
    if pvpType == "arena" then
        return ARENA
    end
    if pvpType == "friendly" then
        return FRIENDLY
    end
    if pvpType == "hostile" then
        return HOSTILE
    end
    if pvpType == "combat" then
        return COMBAT
    end
    if pvpType == "contested" then
        return CONTESTED_TERRITORY
    end
    if IsInInstance() then
        return AGGRO_WARNING_IN_INSTANCE
    end
    return CONTESTED_TERRITORY
end

-- One tooltip for both blocks: they name the same place, so they say the same thing. Blizzard globals for the labels, module keys for the click hints.
local function LocTooltip(ownerFrame)
    local ar, ag, ab = mod.GetAccent()
    mod.Tip_Begin(ownerFrame)
    mod.Tip_AddDouble(ZONE, LocDisplayText(true), 0.6, 0.6, 0.6, 1, 1, 1)
    local continent = LocContinentName()
    if continent then
        mod.Tip_AddDouble(CONTINENT, continent, 0.6, 0.6, 0.6, 1, 1, 1)
    end
    local sr, sg, scrollBar = ZoneReactionColor()
    mod.Tip_AddDouble(STATUS, LocZoneStatus(), 0.6, 0.6, 0.6, sr, sg, scrollBar)
    mod.Tip_AddLine(" ")
    mod.Tip_AddDouble(L["LEFT_CLICK"], L["TOGGLE_WORLD_MAP"], 1, 1, 1, ar, ag, ab)
    mod.Tip_Show()
end

-- Shared single-line text block. opts:
--   text()        -> string to display
--   template()    -> stable width-reservation string; nil sizes from the live text instead
--   width()       -> fixed width in px, or nil to size from the text
--   collapse()    -> true drops the block from the bar entirely
--   hasIcon       -> shows the block's icon (K.SetBlockIcon), gated by the block's own showIcon setting (default on)
--   events        -> event list driving Refresh
--   tickSeconds   -> dedicated ticker period, for values no event announces
-- Tooltip and click are identical for both blocks (same place), so they are wired straight in rather than passed.
local function MakeLocationBlock(blockCfg, slot, contentFrame, barCtx, options)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)
    instance.events = options.events

    local function BC()
        return barCtx.cfg
    end
    local function D()
        return blockCfg.settings or {}
    end

    local mouseOver = false
    local ticker
    local lastText

    local widget = CreateFrame("Button", nil, contentFrame)
    widget:SetSize(60, 20)
    widget:EnableMouse(true)
    widget:RegisterForClicks("AnyUp")
    -- Icon is optional: blocks without opts.hasIcon are text-only.
    local icon
    if options.hasIcon then
        icon = widget:CreateTexture(nil, "OVERLAY")
        icon:SetPoint("LEFT")
    end
    local textValue = widget:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(instance, textValue)
    textValue:SetPoint("LEFT")
    -- Hidden ruler, only for the block reserving width from a template.
    local measureFS
    if options.template then
        measureFS = widget:CreateFontString(nil, "OVERLAY")
        measureFS:Hide()
    end

    local function ApplyColors()
        local r, g, b
        if mouseOver then
            r, g, b = mod.GetAccent()
        else
            r, g, b = BlockColorOf(blockCfg)
        end
        textValue:SetTextColor(r, g, b, 1)
        if icon then
            if mouseOver then
                icon:SetVertexColor(r, g, b, 1)
            else
                local ir, ig, ib = IconColorOf(blockCfg)
                icon:SetVertexColor(ir, ig, ib, 1)
            end
        end
    end

    local function HoverIn()
        mouseOver = true
        ApplyColors()
        LocTooltip(widget)
    end
    local function HoverOut()
        mouseOver = false
        mod.Tip_Hide(widget)
        ApplyColors()
    end

    -- Secure click passthrough to Blizzard's QuestLogMicroButton (opens the map): click
    -- runs inside Blizzard's own handler, so nothing here touches the map's panel flow
    -- (same mechanism as the micro menu block). Created lazily, never in lockdown (secure
    -- frames can't be configured there) -- until built the block displays/tooltips but can't
    -- click; PLAYER_REGEN_ENABLED drives Refresh's retry so a block built mid-fight becomes clickable once combat ends.
    local clickBtn
    local function EnsureClickButton()
        if clickBtn or InCombatLockdown() then
            return clickBtn
        end
        local micro = _G.QuestLogMicroButton
        if not micro then
            return nil
        end
        clickBtn = CreateFrame(
            "Button",
            "EWB_LOC_" .. instance.key,
            widget,
            "SecureActionButtonTemplate,SecureHandlerStateTemplate"
        )
        clickBtn:SetAllPoints(widget)
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
        -- Overlay covers the display frame and owns hover from here; tooltip stays
        -- anchored to the display frame so it doesn't shift when the button appears.
        clickBtn:SetScript("OnEnter", HoverIn)
        clickBtn:SetScript("OnLeave", HoverOut)
        return clickBtn
    end

    function instance:Refresh(pre)
        EnsureClickButton()

        local collapsed = (options.collapse and options.collapse()) or false
        -- Show/Hide are protected (the secure click button puts this block's whole
        -- bar under protection): flip only on a real state change, never in
        -- lockdown. Collapse edges are event-driven; regen re-runs.
        if contentFrame:IsShown() == collapsed and not InCombatLockdown() then
            if collapsed then
                contentFrame:Hide()
            else
                contentFrame:Show()
            end
        end
        -- Collapsed (coordinates inside an instance): GetAutoLength reports 0
        -- so the solver drops the slot and its gaps.
        if collapsed then
            lastText = nil
            MaybeRelayout(instance)
            return
        end

        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()
        local gap = ICON_GAP

        -- `pre` is the string the caller already computed (the ticker tests it
        -- before refreshing). Re-reading would double the position lookups
        -- twice a second forever, and each GetPlayerMapPosition allocates.
        local str = pre or options.text()
        lastText = str
        mod.SetFont(textValue, fontSize, barCfg)
        textValue:SetText(str)
        ApplyColors()

        local iconSz = 0
        if icon then
            K.SetBlockIcon(icon, blockCfg)
        end
        if icon and D().showIcon ~= false then
            iconSz = fontSize + LOC_ICON_EXTRA
            icon:SetSize(iconSz, iconSz)
            icon:Show()
        elseif icon then
            icon:Hide()
        end

        if InCombatLockdown() then
            return
        end

        if isSide then
            local slotW = VSlotW(instance)
            local innerW = max(36, slotW - 8)
            textValue:ClearAllPoints()
            if iconSz > 0 then
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", widget, "LEFT", 0, 0)
                textValue:SetPoint("LEFT", icon, "RIGHT", gap, 0)
                mod.SetWrappedText(textValue, max(16, innerW - iconSz - gap - 2), "LEFT")
            else
                textValue:SetPoint("CENTER", widget, "CENTER", 0, 0)
                mod.SetWrappedText(textValue, innerW, "CENTER")
            end
            local lineH =
                max(fontSize + 4, iconSz, mod.SnapToPixelGrid(textValue:GetStringHeight() or fontSize))
            widget:SetSize(innerW, lineH)
            widget:ClearAllPoints()
            widget:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
            contentFrame:SetSize(slotW, max(lineH + 8, barH))
        else
            mod.ResetInlineText(textValue, "LEFT")
            local iconPad = 0
            if iconSz > 0 then
                iconPad = iconSz + gap
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", widget, "LEFT", 0, 0)
            end
            textValue:ClearAllPoints()
            textValue:SetPoint("LEFT", widget, "LEFT", iconPad, 0)
            -- Manual width: exactly this wide whatever the zone is called (longer names
            -- clip); the only mode that never moves neighbours. NOT derived from the
            -- assigned slot: under auto sizing the slot IS this block's own measured
            -- width, so that would shrink it further on every pass. Icon included.
            local wid = options.width and options.width()
            if wid then
                textValue:SetWidth(max(20, wid - iconPad - 2))
                textValue:SetWordWrap(false)
            else
                -- Measured only when the width is not already decided: a
                -- GetStringWidth forces a FontString layout.
                local tpl = options.template and options.template()
                if tpl then
                    mod.SetFont(measureFS, fontSize, barCfg)
                    measureFS:SetText(tpl)
                    wid = iconPad + mod.SnapToPixelGrid(measureFS:GetStringWidth() or 40) + 2
                else
                    wid = iconPad + mod.SnapToPixelGrid(textValue:GetStringWidth() or 40) + 2
                end
            end
            if wid < 24 then
                wid = 24
            end
            widget:SetSize(wid, barH)
            widget:ClearAllPoints()
            widget:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
            contentFrame:SetSize(wid, barH)
        end
        MaybeRelayout(instance)
    end

    -- Fallback hover surface: used until the secure overlay exists (block built mid-combat); harmless after, since the overlay sits on top.
    widget:SetScript("OnEnter", HoverIn)
    widget:SetScript("OnLeave", HoverOut)

    instance.eventFrame = MakeEventFrame(instance, function(self)
        self:Refresh()
    end)

    function instance:Enable()
        if not contentFrame:IsShown() and not InCombatLockdown() then
            contentFrame:Show()
        end
        lastText = nil
        EnsureClickButton()
        RegisterInstEvents(self)
        -- Movement raises no event and the 1s engine heartbeat is coarse enough that
        -- numbers visibly jump while running. Same 0.5s period and lazy lifecycle as the minimap module's coordinate ticker.
        if options.tickSeconds and not ticker then
            ticker = C_Timer.NewTicker(options.tickSeconds, function()
                -- Collapsed: nothing to render; the un-collapse edge is event-driven
                -- (PLAYER_ENTERING_WORLD/ZONE_CHANGED_NEW_AREA fire on instance entry/exit).
                -- Without this the hide path re-runs twice a second for the whole dungeon.
                if options.collapse and options.collapse() then
                    return
                end
                -- Dirty gate: a full Refresh re-sets the font, re-measures the ruler,
                -- re-anchors and re-sizes -- all invariant between ticks. Standing still
                -- costs one position read; a moving player hands the string on instead of computing it twice.
                local str = options.text()
                if str == lastText then
                    return
                end
                instance:Refresh(str)
            end)
        end
    end

    function instance:Disable()
        UnregisterInstEvents(self)
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        -- Protected once the secure click button exists; the engine's combat gate covers the ApplyBar that reaches here, so this guards only the paths that bypass it.
        if not InCombatLockdown() then
            contentFrame:Hide()
        end
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
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        if clickBtn then
            ParkSecureFrame(clickBtn, self.key .. "_loc")
            clickBtn = nil
        end
        -- Same protected-call guard as Disable: parking the secure child is itself deferred in combat, so the bar is still protected here.
        if not InCombatLockdown() then
            contentFrame:Hide()
        end
    end

    return instance
end

mod.BlockFactories.location = function(blockCfg, slot, contentFrame, barCtx)
    local function D()
        return blockCfg.settings or {}
    end

    return MakeLocationBlock(blockCfg, slot, contentFrame, barCtx, {
        -- PLAYER_REGEN_ENABLED: Refresh can only re-anchor/resize out of combat, so a mid-fight zone change leaves stale geometry until then.
        events = {
            "ZONE_CHANGED",
            "ZONE_CHANGED_INDOORS",
            "ZONE_CHANGED_NEW_AREA",
            "PLAYER_ENTERING_WORLD",
            "PLAYER_REGEN_ENABLED",
        },
        hasIcon = true,
        text = function()
            return LocDisplayText(D().showSubZone ~= false)
        end,
        -- No template: sizes from the live name. Zone changes are rare, so one relayout each beats permanently reserving the longest zone name.
        width = function()
            local d = D()
            if mod.LocationWidthMode(d) ~= "manual" then
                return nil
            end
            return d.maxWidth or LOC_MAX_WIDTH_DEFAULT
        end,
    })
end

mod.BlockFactories.coords = function(blockCfg, slot, contentFrame, barCtx)
    local function D()
        return blockCfg.settings or {}
    end
    local function Precision()
        local p = D().precision
        if p == nil then
            p = 0
        end
        return p
    end

    return MakeLocationBlock(blockCfg, slot, contentFrame, barCtx, {
        -- PLAYER_REGEN_ENABLED: geometry, the collapse flip and the secure click button all wait for regen, so the block needs a pass there.
        events = {
            "ZONE_CHANGED_NEW_AREA",
            "PLAYER_ENTERING_WORLD",
            "PLAYER_REGEN_ENABLED",
        },
        tickSeconds = 0.5,
        hasIcon = true,
        text = function()
            return LocCoordText(Precision())
        end,
        template = function()
            return COORD_TEMPLATE[Precision()] or COORD_TEMPLATE[0]
        end,
        collapse = function()
            if D().hideInInstance == false then
                return false
            end
            if not IsInInstance() then
                return false
            end
            -- Housing counts as an instance but has a real player map, so its coords work; sanctuary is what tells it apart from dungeon/raid.
            local pvpType = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
            return pvpType ~= "sanctuary"
        end,
    })
end
