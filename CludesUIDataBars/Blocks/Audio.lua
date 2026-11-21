if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Blocks\Audio.lua - Info Bar block: a volume bar for one sound channel.
--
--  Icon plus a thin bar showing the channel's volume. Drag the bar or turn
--  the mouse wheel to set it (1% a notch, 10% with Shift); click the icon to
--  mute or unmute the channel. The tooltip lists every channel: click a row
--  to mute it, turn the wheel over it to set its volume. A muted channel (or
--  master sound off) turns the icon and bar red.
--
--  The volumes are the game's sound settings, which addons may change in
--  combat. Plain SetCVar, not CludesUI.SetCVar: these are the player's own
--  volumes, which uninstalling CludesUI leaves as they are.
--
--  Settings (blockCfg.settings): channel (master, sfx, music, ambience,
--  dialog; default master), showIcon (default on).
-------------------------------------------------------------------------------
local _, mod = ...
local L = mod.L
local K = mod.BlockKit

local floor, max, abs = math.floor, math.max, math.abs

local CHANNELS = {
    master = { cvar = "Sound_MasterVolume", enable = "Sound_EnableAllSound", label = "AUDIO_MASTER" },
    sfx = { cvar = "Sound_SFXVolume", enable = "Sound_EnableSFX", label = "AUDIO_SFX" },
    music = { cvar = "Sound_MusicVolume", enable = "Sound_EnableMusic", label = "AUDIO_MUSIC" },
    ambience = { cvar = "Sound_AmbienceVolume", enable = "Sound_EnableAmbience", label = "AUDIO_AMBIENCE" },
    dialog = { cvar = "Sound_DialogVolume", enable = "Sound_EnableDialog", label = "AUDIO_DIALOG" },
}
local ORDER = { "master", "sfx", "music", "ambience", "dialog" }
mod.AUDIO_CHANNELS = CHANNELS
mod.AUDIO_CHANNEL_ORDER = ORDER

local MUTED = { 1, 0.3, 0.3 }
local BAR_H = 5 -- the volume bar's thickness

local function Volume(ch)
    -- A missing setting reads as full volume.
    local v = tonumber(GetCVar(ch.cvar)) or 1
    return v < 0 and 0 or (v > 1 and 1 or v)
end

-- Writes a channel's volume, clamped to 0..1, only when it changes: the game
-- answers each write with a redraw of the block (and the tooltip), so a drag
-- held still or a wheel turned past the end writes nothing.
local function SetVolume(ch, v)
    v = v < 0 and 0 or (v > 1 and 1 or v)
    if abs(v - Volume(ch)) < 0.0005 then return end
    SetCVar(ch.cvar, v)
end

-- One wheel notch: 1%, or 10% with Shift, on whole percents so steps never drift.
local function Notch(v, delta)
    return floor((v + delta * (IsShiftKeyDown() and 0.10 or 0.01)) * 100 + 0.5) / 100
end

local function ToggleMute(ch) SetCVar(ch.enable, GetCVarBool(ch.enable) and 0 or 1) end

local function Audible(ch) return GetCVarBool(ch.enable) and GetCVarBool(CHANNELS.master.enable) end

mod.BlockFactories.audio = function(blockCfg, slot, contentFrame, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    inst.events = { "CVAR_UPDATE", "PLAYER_ENTERING_WORLD" }

    local function Settings() return blockCfg.settings or {} end
    local function Channel() return CHANNELS[Settings().channel] or CHANNELS.master end

    local button = CreateFrame("Button", nil, contentFrame)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:EnableMouseWheel(true)
    button:RegisterForClicks("LeftButtonUp")
    local iconTex = button:CreateTexture(nil, "OVERLAY")
    local track = button:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.15, 0.15, 0.15, 0.6)
    local fillTex = CreateFrame("StatusBar", nil, button)
    fillTex:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    fillTex:SetMinMaxValues(0, 1)
    -- The drag area: the bar plus 4px above and below, so the thin bar is easy
    -- to grab; a click on the icon never sets the volume.
    local grab = CreateFrame("Button", nil, button)
    grab:EnableMouse(true)

    local hovered, dragging = false, false

    -- Colours and the bar's value: red when the channel cannot be heard, the
    -- accent on hover, else the block's icon colour (the bar is accent-filled).
    local function Paint()
        local red, green, blue = mod.GetAccent()
        if not Audible(Channel()) then
            red, green, blue = MUTED[1], MUTED[2], MUTED[3]
            iconTex:SetVertexColor(red, green, blue, 1)
        elseif hovered then
            iconTex:SetVertexColor(red, green, blue, 1)
        else
            local ir, ig, ib = K.IconColorOf(blockCfg)
            iconTex:SetVertexColor(ir, ig, ib, 1)
        end
        fillTex:SetStatusBarColor(red, green, blue, 1)
        fillTex:SetValue(Volume(Channel()))
    end

    -- Tooltip rows: click mutes that channel, the wheel sets its volume.
    local rowClick, rowWheel = {}, {}
    for _, key in ipairs(ORDER) do
        local ch = CHANNELS[key]
        rowClick[key] = function(mouseButton)
            if mouseButton == "LeftButton" then ToggleMute(ch) end
        end
        rowWheel[key] = function(delta) SetVolume(ch, Notch(Volume(ch), delta)) end
    end

    local function ShowTooltip()
        mod.Tip_Begin(button)
        mod.Tip_AddLine("|cFFFFFFFF[|r" .. L["AUDIO"] .. "|cFFFFFFFF]|r", 1, 1, 1)
        mod.Tip_AddLine(" ")
        local selected = Channel()
        -- With master off every other channel is silent: their rows dim (the
        -- block's own channel a step brighter); a muted channel says Muted in red.
        local masterOn = GetCVarBool(CHANNELS.master.enable)
        for _, key in ipairs(ORDER) do
            local ch = CHANNELS[key]
            local name, value = ch == selected and 1 or 0.65, 1
            if not masterOn and key ~= "master" then
                name, value = ch == selected and 0.55 or 0.35, 0.45
            end
            if GetCVarBool(ch.enable) then
                local pct = floor(Volume(ch) * 100 + 0.5) .. "%"
                mod.Tip_AddClickable(L[ch.label], pct, rowClick[key], name, name, name, value, value, value)
            else
                mod.Tip_AddClickable(
                    L[ch.label],
                    L["AUDIO_MUTED"],
                    rowClick[key],
                    name,
                    name,
                    name,
                    unpack(MUTED)
                )
            end
            mod.Tip_SetRowWheel(rowWheel[key])
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["LEFT_CLICK"], L["AUDIO_MUTE_HINT"], 1, 1, 1, 1, 1, 1)
        mod.Tip_AddDouble(L["DRAG_BAR"], L["AUDIO_SET_HINT"], 1, 1, 1, 1, 1, 1)
        mod.Tip_AddDouble(L["SCROLL_WHEEL"], L["AUDIO_SCROLL_HINT"], 1, 1, 1, 1, 1, 1)
        mod.Tip_AddLine(L["AUDIO_SHIFT_HINT"], 0.65, 0.65, 0.65)
        mod.Tip_Show()
    end

    -- Hovering only repaints; nothing moves, so nothing is laid out again.
    local function Enter()
        hovered = true
        Paint()
        ShowTooltip()
    end
    local function Leave()
        hovered = false
        Paint()
        mod.Tip_HideUnlessInteractive(button)
    end
    button:SetScript("OnEnter", Enter)
    button:SetScript("OnLeave", Leave)
    grab:SetScript("OnEnter", Enter)
    grab:SetScript("OnLeave", Leave)

    button:SetScript("OnClick", function() ToggleMute(Channel()) end)
    button:SetScript(
        "OnMouseWheel",
        function(_, delta) SetVolume(Channel(), Notch(Volume(Channel()), delta)) end
    )

    -- Drag: the volume follows the cursor across the bar.
    local function FollowCursor()
        local left, width = track:GetLeft(), track:GetWidth()
        if not left or not width or width <= 0 then return end
        local scale = track:GetEffectiveScale()
        if not scale or scale == 0 then scale = 1 end
        SetVolume(Channel(), (GetCursorPosition() / scale - left) / width)
    end
    grab:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        dragging = true
        FollowCursor()
        grab:SetScript("OnUpdate", FollowCursor) -- only for the length of the drag
    end)
    grab:SetScript("OnMouseUp", function()
        if not dragging then return end
        dragging = false
        grab:SetScript("OnUpdate", nil)
        inst:Refresh()
    end)

    function inst:Refresh()
        K.SetBlockIcon(iconTex, blockCfg)
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        local showIcon = Settings().showIcon ~= false
        local iconSize = showIcon and fontSize + 4 or 0
        local gap = showIcon and K.ICON_GAP or 0
        iconTex:SetShown(showIcon)
        if showIcon then iconTex:SetSize(iconSize, iconSize) end
        Paint()

        iconTex:ClearAllPoints()
        track:ClearAllPoints()
        if barCtx.IsVertical() then
            -- Icon above the bar, both centred in the bar's width.
            local slotW = K.VSlotW(inst)
            iconTex:SetPoint("TOP", button, "TOP", 0, -4)
            track:SetSize(max(30, slotW - 8), BAR_H)
            if showIcon then
                track:SetPoint("TOP", iconTex, "BOTTOM", 0, -4)
            else
                track:SetPoint("TOP", button, "TOP", 0, -6)
            end
            contentFrame:SetSize(slotW, max(4 + iconSize + 4 + BAR_H + 4, 40))
        else
            -- Icon then bar, left to right.
            local barW = max(40, floor(K.CONTENT_BASE * 2 + 0.5))
            iconTex:SetPoint("LEFT", button, "LEFT", 0, 0)
            track:SetSize(barW, BAR_H)
            track:SetPoint("LEFT", button, "LEFT", iconSize + gap, 0)
            contentFrame:SetSize(iconSize + gap + barW, barH)
        end
        fillTex:ClearAllPoints()
        fillTex:SetAllPoints(track)
        grab:ClearAllPoints()
        grab:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 4)
        grab:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, -4)
        button:ClearAllPoints()
        button:SetAllPoints(contentFrame)

        -- The tooltip follows too while it is ours (the cursor may sit on its
        -- rows, not on the block), except mid-drag.
        if mod.Tip_IsOwned(button) and not dragging then ShowTooltip() end
        K.MaybeRelayout(inst)
    end

    -- Only sound settings (changed here or in the game's own options) redraw it.
    inst.eventFrame = K.MakeEventFrame(inst, function(self, event, cvar)
        if event == "CVAR_UPDATE" and type(cvar) == "string" and not cvar:find("^Sound_") then return end
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
        if barCtx.IsVertical() then return max(contentFrame:GetHeight() or 40, 40) end
        local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        local iconPart = Settings().showIcon ~= false and fontSize + 4 + K.ICON_GAP or 0
        return iconPart + max(40, floor(K.CONTENT_BASE * 2 + 0.5))
    end

    function inst:Destroy()
        self._dead = true
        K.UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    inst:Refresh()
    return inst
end
