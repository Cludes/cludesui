if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Blocks\Stats.lua
-- FPS, latency, durability and combat block factories.

local ADDON_NAME, mod = ...
local L = mod.L
local K = mod.BlockKit

-- Upvalues
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local GetTime = GetTime
local format = string.format
local tsort = table.sort
local floor = math.floor
local max = math.max
local min = math.min

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
--  FPS + MS (separate block types built on one single-line stat renderer)
-------------------------------------------------------------------------------
-- Game-wide addon memory scan cache (fps tooltip; shared by design).
local sysMemTable = {}
local function sysMemSort(a, b)
    return a.mem > b.mem
end
local sysLastMemScanTime = 0

local FPS_THRESHOLD = 60
local function GetFPSColor(fps)
    local lb = FPS_THRESHOLD * 0.5
    local perc = 1
    if fps < FPS_THRESHOLD then
        perc = (fps - lb) / lb
    end
    return mod.SlowColorGradient(perc)
end

-- Latency quality in three bands (green/yellow/red = good/fair/poor); colors are the client's own font-color globals so they match the UI (plain fallbacks if absent). Thresholds in ms.
local LAT_GOOD, LAT_FAIR = 100, 250
local function BandColor(fontColor, dr, dg, saved)
    if fontColor and fontColor.GetRGB then
        return fontColor:GetRGB()
    end
    return dr, dg, saved
end
local function GetLatColor(lat)
    if lat <= LAT_GOOD then
        return BandColor(GREEN_FONT_COLOR, 0.1, 1.0, 0.1)
    end
    if lat <= LAT_FAIR then
        return BandColor(YELLOW_FONT_COLOR, 1.0, 0.82, 0.0)
    end
    return BandColor(RED_FONT_COLOR, 1.0, 0.1, 0.1)
end

-- Shared single-line stat block (icon + value text). opts:
--   hbPrefix   heartbeat key prefix
--   texture    icon file
--   interval   heartbeat SECONDS between samples (1 = every tick)
--   sample()   -> current value (number)
--   suffix()   -> display suffix string
--   tooltip(inst, skipScan)  owned-tooltip builder
--   click(inst, isOverFn)    optional OnClick factory
local function MakeStatBlock(blockCfg, slot, contentFrame, barCtx, options)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)

    local function D()
        return blockCfg.settings or {}
    end
    local function BC()
        return barCtx.cfg
    end

    local mouseOver = false
    local lastVal = -1
    local tickCount = 0
    local _fitBuf = { "" }

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
    -- Hidden ruler: the block's width is reserved from a stable TEMPLATE, never the live string, so value changes cannot shift neighbors.
    local measureFS = widget:CreateFontString(nil, "OVERLAY")
    measureFS:Hide()

    -- Hover feedback is COLOR ONLY: never re-samples or re-renders the value.
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

    function instance:Refresh()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        -- 0.4333 = 13px at the 30 base (1px under the standard 0.46 block text).
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local d = D()
        local gap = ICON_GAP
        local isSide = barCtx.IsVertical()
        if lastVal < 0 then
            lastVal = options.sample()
        end
        local str = lastVal .. options.suffix()

        local iconSz = 0
        if icon then
            K.SetBlockIcon(icon, blockCfg)
        end
        if icon and d.showIcon ~= false then
            iconSz = fontSize + (options.iconExtra or 0)
        end

        -- No fit-to-slot: fixed size (base font x Text Scale x Content Scale).

        mod.SetFont(textValue, fontSize, barCfg)
        textValue:SetText(str)
        ApplyColors()

        if iconSz > 0 then
            icon:SetSize(iconSz, iconSz)
            icon:Show()
        elseif icon then
            icon:Hide()
        end

        if InCombatLockdown() then
            return
        end

        local lineH = max(fontSize + 4, iconSz)
        if isSide then
            local slotW = VSlotW(instance)
            local innerW = max(36, slotW - 8)
            widget:SetSize(innerW, lineH)
            widget:ClearAllPoints()
            widget:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
            if iconSz > 0 then
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", widget, "LEFT", 0, 0)
                textValue:ClearAllPoints()
                textValue:SetPoint("LEFT", icon, "RIGHT", gap, 0)
                mod.SetWrappedText(textValue, max(16, innerW - iconSz - gap - 2), "LEFT")
            else
                textValue:ClearAllPoints()
                textValue:SetPoint("CENTER", widget, "CENTER", 0, 0)
                mod.SetWrappedText(textValue, innerW, "CENTER")
            end
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
            -- Template width: digits become "8" padded to >=3, so width only
            -- moves on a digit-count crossing (999ms->1000ms), never on ordinary
            -- changes. Icon/number stay LEFT-anchored; slack sits on the right.
            local digits = #tostring(lastVal)
            if digits < 3 then
                digits = 3
            end
            mod.SetFont(measureFS, fontSize, barCfg)
            measureFS:SetText(string.rep("8", digits) .. options.suffix())
            local wid = iconPad + mod.SnapToPixelGrid(measureFS:GetStringWidth() or 30) + 2
            if wid < 30 then
                wid = 30
            end
            widget:SetSize(wid, barH)
            widget:ClearAllPoints()
            widget:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
            contentFrame:SetSize(wid, barH)
        end
        MaybeRelayout(instance)
    end

    local function Tick()
        tickCount = tickCount + 1
        if tickCount < (options.interval or 1) then
            return
        end
        tickCount = 0
        local val = options.sample()
        if val == lastVal then
            return
        end
        lastVal = val
        instance:Refresh()
        if mouseOver then
            options.tooltip(instance, true)
        end
    end

    widget:SetScript("OnEnter", function()
        mouseOver = true
        ApplyColors()
        options.tooltip(instance, false)
    end)
    widget:SetScript("OnLeave", function()
        mouseOver = false
        mod.Tip_Hide(contentFrame)
        ApplyColors()
    end)
    if options.click then
        widget:SetScript(
            "OnClick",
            options.click(instance, function()
                return mouseOver
            end)
        )
    end

    -- Evented stat blocks (opts.events) never touch the heartbeat: the game
    -- names the exact edges their value changes on, so the block samples only
    -- there and costs nothing between them. Time-driven blocks (fps/ms) keep
    -- the shared 1s ticker.
    local function ForceTick()
        tickCount = (options.interval or 1) - 1
        Tick()
    end

    -- Lets a tooltip resync the bar text with what it just sampled.
    function instance:ForceSample()
        ForceTick()
    end

    -- A sample taken right when an event fires can catch the source before
    -- it's populated. Resample once more after a short delay to catch that.
    -- One outstanding retry at a time: event bursts (durability drops hit
    -- many items per damage wave) would otherwise queue a timer closure each.
    local retryPending = false
    local function ForceTickChecked()
        ForceTick()
        if options.retryDelay and not retryPending then
            retryPending = true
            C_Timer.After(options.retryDelay, function()
                retryPending = false
                if not instance._dead then
                    ForceTick()
                end
            end)
        end
    end

    -- Same-frame event bursts (a damage wave fires the durability AND alert
    -- events per slot) collapse to ONE sample after the frame settles.
    local flushPending = false
    local function FlushEventSample()
        flushPending = false
        if not instance._dead then
            ForceTickChecked()
        end
    end
    local function OnEventSample()
        if flushPending then
            return
        end
        flushPending = true
        C_Timer.After(0, FlushEventSample)
    end

    function instance:Enable()
        contentFrame:Show()
        lastVal = -1
        -- Sample on the very first tick regardless of interval.
        tickCount = (options.interval or 1) - 1
        if options.events then
            if not self.eventFrame then
                self.events = options.events
                self.eventFrame = MakeEventFrame(self, OnEventSample)
            end
            RegisterInstEvents(self)
            ForceTickChecked()
        else
            mod.RegisterHeartbeat(options.hbPrefix .. ":" .. self.key, Tick)
        end
    end

    function instance:Disable()
        UnregisterInstEvents(self)
        mod.UnregisterHeartbeat(options.hbPrefix .. ":" .. self.key)
        contentFrame:Hide()
    end

    function instance:GetAutoLength()
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 40)
        end
        return max(contentFrame:GetWidth() or 70, 40)
    end

    function instance:Destroy()
        self._dead = true
        UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    return instance
end

mod.BlockFactories.fps = function(blockCfg, slot, contentFrame, barCtx)
    local function FpsTooltip(instance, skipMemoryScan)
        local ar, ag, ab = 1, 1, 1
        mod.Tip_Begin(contentFrame)
        local fps = floor(GetFramerate())
        local fr2, fg2, fb2 = GetFPSColor(fps)
        mod.Tip_AddDouble(L["FPS"], fps .. mod.GetFPSSuffix(), 0.6, 0.6, 0.6, fr2, fg2, fb2)

        local nowTime = GetTime()
        -- UpdateAddOnMemoryUsage() iterates every loaded addon and is a noticeable spike; amortise the rescan to once per 30s.
        -- Skipped entirely in combat: on a busy pull that spike can push the
        -- hovered tooltip's whole script past the "script ran too long" watchdog
        -- (field report: Murder Row, adds casting Felfire Orb). The data is
        -- already tolerated at up to 30s stale, so holding it longer is not a
        -- new behaviour; the next out-of-combat hover rescans normally.
        if not skipMemoryScan and not InCombatLockdown() and (nowTime - sysLastMemScanTime) >= 30 then
            sysLastMemScanTime = nowTime
            UpdateAddOnMemoryUsage()
            local total = 0
            for idx = 1, C_AddOns.GetNumAddOns() do
                local _, name = C_AddOns.GetAddOnInfo(idx)
                local mem = GetAddOnMemoryUsage(idx)
                if mem > 0 then
                    total = total + 1
                    if not sysMemTable[total] then
                        sysMemTable[total] = {}
                    end
                    sysMemTable[total].name = name
                    sysMemTable[total].mem = mem
                end
            end
            for idx = total + 1, #sysMemTable do
                sysMemTable[idx] = nil
            end
            tsort(sysMemTable, sysMemSort)
        end

        if #sysMemTable > 0 then
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(L["MEMORY_USAGE"], ar, ag, ab)
            mod.Tip_AddLine(" ")
            for idx = 1, min(10, #sysMemTable) do
                local ms
                if sysMemTable[idx].mem > 1024 then
                    ms = format("%.2f MB", sysMemTable[idx].mem / 1024)
                else
                    ms = format("%.0f KB", sysMemTable[idx].mem)
                end
                mod.Tip_AddDouble(sysMemTable[idx].name, ms, 1, 1, 1, ar, ag, ab)
            end
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["SHIFT_LEFT_CLICK"], L["FORCE_GC"], 1, 1, 1, ar, ag, ab)
        mod.Tip_Show()
    end

    return MakeStatBlock(blockCfg, slot, contentFrame, barCtx, {
        hbPrefix = "fps",
        interval = 3,
        sample = function()
            return floor(GetFramerate())
        end,
        suffix = function()
            return mod.GetFPSSuffix()
        end,
        tooltip = FpsTooltip,
        click = function(instance, isOver)
            return function(_, btnFrame)
                if btnFrame ~= "LeftButton" then
                    return
                end
                -- A full GC cycle stalls a frame; only force it when Shift is held so a casual click just prints the snapshot.
                if IsShiftKeyDown() then
                    collectgarbage("collect")
                end
                local memKb = collectgarbage("count")
                local msg
                if memKb > 1024 then
                    msg = format("%.2f MB", memKb / 1024)
                else
                    msg = format("%.0f KB", memKb)
                end
                print("|cff4cc9f0Info Bar|r: Memory usage snapshot |cffffff00" .. msg .. "|r")
                if isOver() then
                    FpsTooltip(instance, false)
                end
            end
        end,
    })
end

-- LATENCY. Own factory, not MakeStatBlock: shows one OR two links (home/world/both), each
-- with its own house/globe icon, which the single-icon stat helper cannot do. Bar keeps the
-- block color; green/yellow/red criticality is tooltip-only (GetLatColor).

-- home | world | both. Falls back to the useWorldLatency boolean. Shared by the block and its options row, which must agree on what "selected" means.
function mod.LatencyMode(s)
    if s.latencyMode then
        return s.latencyMode
    end
    if s.useWorldLatency then
        return "world"
    end
    return "home"
end

mod.BlockFactories.ms = function(blockCfg, slot, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)

    local mouseOver = false
    local lastSig -- skip the relayout when nothing changed

    local function D()
        return blockCfg.settings or {}
    end
    local function BC()
        return barCtx.cfg
    end

    local btnFrame = CreateFrame("Button", nil, contentFrame)
    btnFrame:EnableMouse(true)
    btnFrame:RegisterForClicks("AnyUp")

    -- Two reusable segments (icon + value); the second stays hidden unless the block is in "both" mode.
    local seg = {}
    for idx = 1, 2 do
        local s = {
            icon = btnFrame:CreateTexture(nil, "OVERLAY"),
            text = btnFrame:CreateFontString(nil, "OVERLAY"),
        }
        AttachTextOffset(instance, s.text)
        seg[idx] = s
    end

    local function MsTooltip()
        mod.Tip_Begin(contentFrame)
        local inKB, outKB, home, world = GetNetStats()
        home = floor(home)
        world = floor(world)
        -- The tooltip is the full quality read: the colours the bar does not carry, plus bandwidth that is on no bar at all.
        local hr, hg, hb = GetLatColor(home)
        local wr, wg, wb = GetLatColor(world)
        local ms = mod.GetMSSuffix()
        mod.Tip_AddDouble(L["HOME"], home .. ms, 0.6, 0.6, 0.6, hr, hg, hb)
        mod.Tip_AddDouble(L["WORLD"], world .. ms, 0.6, 0.6, 0.6, wr, wg, wb)
        local kb = " " .. L["KB_PER_SEC"]
        mod.Tip_AddDouble(L["DOWNLOAD"], format("%.1f", inKB or 0) .. kb, 0.6, 0.6, 0.6, 1, 1, 1)
        mod.Tip_AddDouble(L["UPLOAD"], format("%.1f", outKB or 0) .. kb, 0.6, 0.6, 0.6, 1, 1, 1)
        mod.Tip_Show()
    end

    function instance:Refresh()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local isSide = barCtx.IsVertical()
        local showIcon = D().showIcon == true
        local m = mod.LatencyMode(D())
        local links
        if m == "both" then
            links = { "home", "world" }
        elseif m == "world" then
            links = { "world" }
        else
            links = { "home" }
        end
        local num = #links
        local iconSz = showIcon and (fontSize + 2) or 0

        local _, _, home, world = GetNetStats()
        local vals = { home = floor(home), world = floor(world) }
        local suffix = mod.GetMSSuffix()

        local tr, tg, tb, ir, ig, ib
        if mouseOver then
            tr, tg, tb = mod.GetAccent()
            ir, ig, ib = tr, tg, tb
        else
            tr, tg, tb = BlockColorOf(blockCfg)
            ir, ig, ib = IconColorOf(blockCfg)
        end

        -- Fill each segment; every value carries the unit ("45ms  92ms"), so a lone number never reads as unitless in "both" mode.
        for idx = 1, 2 do
            local s, itemLink = seg[idx], links[idx]
            if itemLink then
                mod.SetFont(s.text, fontSize, barCfg)
                mod.ResetInlineText(s.text, "LEFT")
                s.text:SetText(vals[itemLink] .. suffix)
                s.text:SetTextColor(tr, tg, tb, 1)
                s.text:Show()
                if showIcon then
                    K.SetBlockIcon(s.icon, blockCfg, itemLink)
                    s.icon:SetVertexColor(ir, ig, ib, 1)
                    s.icon:SetSize(iconSz, iconSz)
                    s.icon:Show()
                else
                    s.icon:Hide()
                end
            else
                s.text:Hide()
                s.icon:Hide()
            end
        end

        local lineH = max(fontSize + 4, iconSz)
        if isSide then
            -- Stack the links, each a centred "icon value" line.
            local slotW = VSlotW(instance)
            local innerW = max(24, slotW - 8)
            local posY = -4
            for idx = 1, num do
                local s = seg[idx]
                local tw = mod.SnapToPixelGrid(s.text:GetStringWidth())
                local grpW = (showIcon and (iconSz + ICON_GAP) or 0) + tw
                local x0 = max(0, floor((innerW - grpW) / 2))
                s.icon:ClearAllPoints()
                s.text:ClearAllPoints()
                if showIcon then
                    s.icon:SetPoint("TOPLEFT", btnFrame, "TOPLEFT", x0, posY - floor((lineH - iconSz) / 2))
                    s.text:SetPoint("LEFT", s.icon, "RIGHT", ICON_GAP, 0)
                else
                    s.text:SetPoint("TOPLEFT", btnFrame, "TOPLEFT", x0, posY)
                end
                posY = posY - lineH - 2
            end
            local totalH = max(-posY + 2, barH)
            contentFrame:SetSize(slotW, totalH)
            btnFrame:SetSize(slotW, totalH)
        else
            local posX, segGap = 0, 8
            for idx = 1, num do
                local s = seg[idx]
                s.icon:ClearAllPoints()
                s.text:ClearAllPoints()
                if showIcon then
                    s.icon:SetPoint("LEFT", btnFrame, "LEFT", posX, 0)
                    posX = posX + iconSz + ICON_GAP
                end
                s.text:SetPoint("LEFT", btnFrame, "LEFT", posX, 0)
                posX = posX + mod.SnapToPixelGrid(s.text:GetStringWidth())
                if idx < num then
                    posX = posX + segGap
                end
            end
            local totalW = max(posX + 4, 10)
            contentFrame:SetSize(totalW, barH)
            btnFrame:SetSize(totalW, barH)
        end
        btnFrame:ClearAllPoints()
        btnFrame:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
        MaybeRelayout(instance)
    end

    -- Latency only moves every ~30s (GetNetStats is cached), so re-lay-out only when the shown value, mode or icon state actually changes.
    local function Tick()
        local _, _, home, world = GetNetStats()
        local sig = mod.LatencyMode(D()) .. (D().showIcon and "I" or "") .. floor(home) .. "/" .. floor(world)
        if sig == lastSig then
            return
        end
        lastSig = sig
        instance:Refresh()
    end

    btnFrame:SetScript("OnEnter", function()
        mouseOver = true
        instance:Refresh()
        MsTooltip()
    end)
    btnFrame:SetScript("OnLeave", function()
        mouseOver = false
        mod.Tip_Hide(contentFrame)
        instance:Refresh()
    end)

    function instance:Enable()
        contentFrame:Show()
        lastSig = nil
        mod.RegisterHeartbeat("ms:" .. self.key, Tick)
    end
    function instance:Disable()
        mod.UnregisterHeartbeat("ms:" .. self.key)
        contentFrame:Hide()
    end
    function instance:GetAutoLength()
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 30)
        end
        return max(contentFrame:GetWidth() or 60, 24)
    end
    function instance:Destroy()
        self._dead = true
        contentFrame:Hide()
    end

    return instance
end

mod.BlockFactories.durability = function(blockCfg, slot, contentFrame, barCtx)
    -- Same reading as the Chat sidebar's durability icon: the LOWEST percent across equipped slots 1-18.
    local function SampleDurability()
        local lowest = 100
        for slotId = 1, 18 do
            local current, mx = GetInventoryItemDurability(slotId)
            if current and mx and mx > 0 then
                local pct = current / mx * 100
                if pct < lowest then
                    lowest = pct
                end
            end
        end
        local pct = floor(lowest)
        K.lastDurabilityPct = pct
        return pct
    end

    local function DurabilityTooltip(instance)
        -- Resync the bar text whenever the tooltip opens.
        if instance then
            instance:ForceSample()
        end
        local ar, ag, ab = 1, 1, 1
        mod.Tip_Begin(contentFrame)
        mod.Tip_AddDouble("Durability", SampleDurability() .. "%", 1, 1, 1, ar, ag, ab)
        mod.Tip_Show()
    end

    return MakeStatBlock(blockCfg, slot, contentFrame, barCtx, {
        hbPrefix = "durability",
        hasIcon = true,
        iconExtra = 7,
        -- Durability only moves on damage/repair edges the game announces, so
        -- the block samples on those events alone -- no heartbeat, and with no
        -- other time-driven block enabled the 1s ticker never runs at all.
        -- Self-repair items recalculate alerts without the durability event.
        events = { "UPDATE_INVENTORY_DURABILITY", "UPDATE_INVENTORY_ALERTS", "PLAYER_ENTERING_WORLD" },
        -- Retry each sample once, a moment later.
        retryDelay = 2,
        sample = SampleDurability,
        suffix = function()
            return "%"
        end,
        tooltip = DurabilityTooltip,
    })
end

mod.BlockFactories.combat = function(blockCfg, slot, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)
    instance.events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }

    local function IsInCombat()
        return UnitAffectingCombat("player") and 1 or 0
    end

    local function CombatLabel(value)
        return value == 1 and L["IN_COMBAT"] or L["OUT_OF_COMBAT"]
    end

    local function CombatTooltip()
        mod.Tip_Begin(contentFrame)
        mod.Tip_AddDouble(L["COMBAT_STATUS"], CombatLabel(IsInCombat()), 1, 1, 1, 1, 1, 1)
        mod.Tip_Show()
    end

    local mouseOver = false
    local lastValue = -1
    local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))

    local function D()
        return blockCfg.settings or {}
    end
    local function BC()
        return barCtx.cfg
    end

    local widget = CreateFrame("Button", nil, contentFrame)
    widget:SetSize(60, 20)
    widget:EnableMouse(true)
    widget:RegisterForClicks("AnyUp")

    local textValue = widget:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(instance, textValue)
    textValue:SetPoint("LEFT")

    local measureFS = widget:CreateFontString(nil, "OVERLAY")
    measureFS:Hide()

    local function ApplyColors()
        local r, g, b
        if mouseOver then
            r, g, b = mod.GetAccent()
        else
            r, g, b = BlockColorOf(blockCfg)
        end
        textValue:SetTextColor(r, g, b, 1)
    end

    function instance:Refresh()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local isSide = barCtx.IsVertical()
        local value = lastValue
        if value < 0 then
            value = IsInCombat()
            lastValue = value
        end
        local collapsed = D().onlyInCombat == true and value ~= 1

        if not collapsed and not contentFrame:IsShown() then
            contentFrame:Show()
        end

        mod.SetFont(textValue, fontSize, barCfg)
        textValue:SetText(CludesUI.L(CombatLabel(value)))
        ApplyColors()

        if InCombatLockdown() then
            MaybeRelayout(instance)
            return
        end

        if isSide then
            local slotW = VSlotW(instance)
            local innerW = max(36, slotW - 8)
            widget:SetSize(innerW, fontSize + 4)
            widget:ClearAllPoints()
            widget:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
            textValue:ClearAllPoints()
            textValue:SetPoint("CENTER", widget, "CENTER", 0, 0)
            mod.SetWrappedText(textValue, innerW, "CENTER")
            contentFrame:SetSize(slotW, max(fontSize + 12, barH))
        else
            local align = blockCfg.align or "CENTER"
            mod.ResetInlineText(textValue, align)
            textValue:ClearAllPoints()
            textValue:SetPoint("LEFT", widget, "LEFT", 0, 0)
            mod.SetFont(measureFS, fontSize, barCfg)
            -- Fixed width from the wider label so the block never resizes on
            -- combat edges; either label can be the wide one per locale.
            measureFS:SetText(CludesUI.L(CombatLabel(0)))
            local wOut = measureFS:GetStringWidth() or 30
            measureFS:SetText(CludesUI.L(CombatLabel(1)))
            local width = max(30, mod.SnapToPixelGrid(max(wOut, measureFS:GetStringWidth() or 30)) + 2)
            textValue:SetWidth(width)
            widget:SetSize(width, barH)
            widget:ClearAllPoints()
            widget:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
            contentFrame:SetSize(width, barH)
        end
        if collapsed then
            contentFrame:Hide()
            mod.Tip_Hide(contentFrame)
        end
        MaybeRelayout(instance)
    end

    local function RefreshFromEvent()
        local value = IsInCombat()
        if value == lastValue then
            return
        end
        lastValue = value
        instance:Refresh()
        if mouseOver then
            CombatTooltip()
        end
    end

    widget:SetScript("OnEnter", function()
        mouseOver = true
        ApplyColors()
        CombatTooltip()
    end)
    widget:SetScript("OnLeave", function()
        mouseOver = false
        mod.Tip_Hide(contentFrame)
        ApplyColors()
    end)

    function instance:Enable()
        contentFrame:Show()
        lastValue = -1
        if not self.eventFrame then
            self.eventFrame = MakeEventFrame(self, RefreshFromEvent)
        end
        RegisterInstEvents(self)
        RefreshFromEvent()
    end

    function instance:Disable()
        UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    function instance:GetAutoLength()
        if D().onlyInCombat == true and lastValue ~= 1 then
            return 0
        end
        if not contentFrame:IsShown() then
            return 0
        end
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 40)
        end
        return max(contentFrame:GetWidth() or 70, 40)
    end

    function instance:Destroy()
        self._dead = true
        UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    return instance
end
