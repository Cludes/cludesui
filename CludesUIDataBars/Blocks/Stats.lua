if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Blocks\Stats.lua - Info Bar blocks: FPS, latency, durability, combat.
--
--  FPS and durability share one "single value" block: an optional icon and a
--  number with its unit. Its width comes from a template ("888fps"), not the
--  live number, so neighbours never shift; it changes only when the number
--  gains or loses a digit. So a new value with the same number of digits just
--  sets the text. FPS samples on the shared one-second ticker (every third
--  tick); durability only on the game's durability events.
--
--  Latency shows home, world or both, each with its own icon; it reads the
--  game's cached net stats every second and draws only when they change.
--  Combat shows "In Combat" / "Out of Combat" at the width of the wider one,
--  optionally only while in combat.
--
--  Hovering any of them only recolours: nothing is measured again.
-------------------------------------------------------------------------------
local _, mod = ...
local L = mod.L
local K = mod.BlockKit

local InCombatLockdown = InCombatLockdown
local format, floor, max, min = string.format, math.floor, math.max, math.min

local function TextSize()
    return max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
end

-------------------------------------------------------------------------------
--  Colours
-------------------------------------------------------------------------------
local FPS_GOOD = 60
local function FPSColour(fps)
    local half = FPS_GOOD * 0.5
    return mod.SlowColorGradient(fps < FPS_GOOD and (fps - half) / half or 1)
end

-- Latency in three bands (ms), in the client's own green / yellow / red.
local LAT_GOOD, LAT_FAIR = 100, 250
local function FontColour(color, region, g, b)
    if color and color.GetRGB then
        return color:GetRGB()
    end
    return region, g, b
end
local function LatencyColour(ms)
    if ms <= LAT_GOOD then
        return FontColour(GREEN_FONT_COLOR, 0.1, 1.0, 0.1)
    elseif ms <= LAT_FAIR then
        return FontColour(YELLOW_FONT_COLOR, 1.0, 0.82, 0.0)
    end
    return FontColour(RED_FONT_COLOR, 1.0, 0.1, 0.1)
end

local function Memory(kb)
    if kb > 1024 then
        return format("%.2f MB", kb / 1024)
    end
    return format("%.0f KB", kb)
end

-------------------------------------------------------------------------------
--  The single-value block (FPS, durability). spec:
--    tickKey, interval (heartbeat seconds per sample), or events (sampled
--    only on those, with retryDelay for a second look);
--    sample() -> number; suffix() -> unit; tooltip(inst, fromTick);
--    click(inst, isHovered) -> OnClick; hasIcon, iconExtra.
-------------------------------------------------------------------------------
local function SingleValueBlock(blockCfg, slot, contentFrame, barCtx, spec)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    local tickKey = spec.tickKey .. ":" .. inst.key

    local hovered = false
    local value = -1 -- the last sample; -1 = none yet
    local ticks = 0
    local digitsDrawn -- the template's digit count when last laid out

    local widget = CreateFrame("Button", nil, contentFrame)
    widget:SetSize(60, 20)
    widget:EnableMouse(true)
    widget:RegisterForClicks("AnyUp")
    local iconTex
    if spec.hasIcon then
        iconTex = widget:CreateTexture(nil, "OVERLAY")
        iconTex:SetPoint("LEFT")
    end
    local label = widget:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, label)
    label:SetPoint("LEFT")
    -- Measures the template, never shown.
    local ruler = widget:CreateFontString(nil, "OVERLAY")
    ruler:Hide()

    local function Paint()
        local region, g, b
        if hovered then
            region, g, b = mod.GetAccent()
        else
            region, g, b = K.BlockColorOf(blockCfg)
        end
        label:SetTextColor(region, g, b, 1)
        if iconTex then
            if not hovered then
                region, g, b = K.IconColorOf(blockCfg)
            end
            iconTex:SetVertexColor(region, g, b, 1)
        end
    end

    -- The template's digits: at least three, so 60 -> 100 fps keeps its width.
    local function Digits()
        return max(3, #tostring(value))
    end

    function inst:Refresh()
        local s = blockCfg.settings or {}
        local fontSize = TextSize()
        local barH = barCtx.GetThickness()
        if value < 0 then
            value = spec.sample()
        end
        local iconSize = 0
        if iconTex then
            K.SetBlockIcon(iconTex, blockCfg)
            if s.showIcon ~= false then
                iconSize = fontSize + (spec.iconExtra or 0)
            end
        end
        mod.SetFont(label, fontSize, barCtx.cfg)
        label:SetText(value .. spec.suffix())
        Paint()
        if iconSize > 0 then
            iconTex:SetSize(iconSize, iconSize)
            iconTex:Show()
        elseif iconTex then
            iconTex:Hide()
        end
        -- In combat the layout waits (the next full pass places it).
        if InCombatLockdown() then
            digitsDrawn = nil
            return
        end
        local lineH = max(fontSize + 4, iconSize)
        if barCtx.IsVertical() then
            local slotW = K.VSlotW(self)
            local inner = max(36, slotW - 8)
            widget:SetSize(inner, lineH)
            widget:ClearAllPoints()
            widget:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
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
            contentFrame:SetSize(slotW, max(lineH + 8, barH))
            digitsDrawn = nil -- wrapped text can change height with any value
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
            -- The width of "8" x digits + unit; the number sits left, slack right.
            mod.SetFont(ruler, fontSize, barCtx.cfg)
            ruler:SetText(string.rep("8", Digits()) .. spec.suffix())
            local width = max(lead + mod.SnapToPixelGrid(ruler:GetStringWidth() or 30) + 2, 30)
            widget:SetSize(width, barH)
            widget:ClearAllPoints()
            widget:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
            contentFrame:SetSize(width, barH)
            digitsDrawn = Digits()
        end
        K.MaybeRelayout(self)
    end

    -- A new value: just the text while the template's width holds, a full
    -- pass when it would change (or on a side bar, where text wraps).
    local function Take(v)
        if v == value then
            return
        end
        value = v
        if digitsDrawn and Digits() == digitsDrawn and not barCtx.IsVertical() then
            label:SetText(value .. spec.suffix())
            Paint() -- a dynamic colour (durability's icon tint) follows the value
        else
            inst:Refresh()
        end
        if hovered then
            spec.tooltip(inst, true)
        end
    end

    local function Tick()
        ticks = ticks + 1
        if ticks < (spec.interval or 1) then
            return
        end
        ticks = 0
        Take(spec.sample())
    end
    local function SampleNow()
        ticks = (spec.interval or 1) - 1
        Tick()
    end
    -- The tooltip resyncs the bar with what it just read.
    function inst:ForceSample()
        SampleNow()
    end

    -- An event can fire before its data is in: one more look a moment later
    -- (one at a time, as damage arrives in bursts).
    local retrying = false
    local function SampleAndRetry()
        SampleNow()
        if spec.retryDelay and not retrying then
            retrying = true
            C_Timer.After(spec.retryDelay, function()
                retrying = false
                if not inst._dead then
                    SampleNow()
                end
            end)
        end
    end
    -- A burst of events in one frame (durability and alerts per slot) is one sample.
    local queued = false
    local function OnEvent()
        if queued then
            return
        end
        queued = true
        C_Timer.After(0, function()
            queued = false
            if not inst._dead then
                SampleAndRetry()
            end
        end)
    end

    widget:SetScript("OnEnter", function()
        hovered = true
        Paint()
        spec.tooltip(inst, false)
    end)
    widget:SetScript("OnLeave", function()
        hovered = false
        mod.Tip_Hide(contentFrame)
        Paint()
    end)
    if spec.click then
        widget:SetScript(
            "OnClick",
            spec.click(inst, function()
                return hovered
            end)
        )
    end

    function inst:Enable()
        contentFrame:Show()
        value = -1
        digitsDrawn = nil
        ticks = (spec.interval or 1) - 1 -- the first tick samples
        if spec.events then
            if not self.eventFrame then
                self.events = spec.events
                self.eventFrame = K.MakeEventFrame(self, OnEvent)
            end
            K.RegisterInstEvents(self)
            SampleAndRetry()
        else
            mod.RegisterHeartbeat(tickKey, Tick)
        end
    end

    function inst:Disable()
        K.UnregisterInstEvents(self)
        mod.UnregisterHeartbeat(tickKey)
        contentFrame:Hide()
    end

    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 40)
        end
        return max(contentFrame:GetWidth() or 70, 40)
    end

    function inst:Destroy()
        self._dead = true
        K.UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    return inst
end

-------------------------------------------------------------------------------
--  FPS
-------------------------------------------------------------------------------
-- Addon memory, shared by every FPS block; rescanned at most every 30s.
local memory = {}
local lastMemoryScan = 0
local function MostMemory(a, b)
    return a.mem > b.mem
end

-- UpdateAddOnMemoryUsage walks every addon and is a visible spike: never in
-- combat (on a busy pull it can trip the "script ran too long" check), and
-- the list may be up to 30s old anyway.
local function ScanMemory()
    local now = GetTime()
    if InCombatLockdown() or now - lastMemoryScan < 30 then
        return
    end
    lastMemoryScan = now
    UpdateAddOnMemoryUsage()
    local n = 0
    for i = 1, C_AddOns.GetNumAddOns() do
        local _, name = C_AddOns.GetAddOnInfo(i)
        local mem = GetAddOnMemoryUsage(i)
        if mem > 0 then
            n = n + 1
            local entry = memory[n] or {}
            memory[n] = entry
            entry.name, entry.mem = name, mem
        end
    end
    for i = n + 1, #memory do
        memory[i] = nil
    end
    table.sort(memory, MostMemory)
end

mod.BlockFactories.fps = function(blockCfg, slot, contentFrame, barCtx)
    local function Tooltip(_, fromTick)
        mod.Tip_Begin(contentFrame)
        local fps = floor(GetFramerate())
        local region, g, b = FPSColour(fps)
        mod.Tip_AddDouble(L["FPS"], fps .. mod.GetFPSSuffix(), 0.6, 0.6, 0.6, region, g, b)
        if not fromTick then
            ScanMemory()
        end
        if #memory > 0 then
            mod.Tip_AddLine(" ")
            mod.Tip_AddLine(L["MEMORY_USAGE"], 1, 1, 1)
            mod.Tip_AddLine(" ")
            for i = 1, min(10, #memory) do
                mod.Tip_AddDouble(memory[i].name, Memory(memory[i].mem), 1, 1, 1, 1, 1, 1)
            end
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["SHIFT_LEFT_CLICK"], L["FORCE_GC"], 1, 1, 1, 1, 1, 1)
        mod.Tip_Show()
    end

    return SingleValueBlock(blockCfg, slot, contentFrame, barCtx, {
        tickKey = "fps",
        interval = 3,
        sample = function()
            return floor(GetFramerate())
        end,
        suffix = mod.GetFPSSuffix,
        tooltip = Tooltip,
        click = function(inst, isHovered)
            return function(_, mouseButton)
                if mouseButton ~= "LeftButton" then
                    return
                end
                -- A full collection stalls a frame: only with Shift; a plain
                -- click just prints the figure.
                if IsShiftKeyDown() then
                    collectgarbage("collect")
                end
                print(
                    "|cff4cc9f0Info Bar|r: Memory usage snapshot |cffffff00"
                        .. Memory(collectgarbage("count"))
                        .. "|r"
                )
                if isHovered() then
                    Tooltip(inst, false)
                end
            end
        end,
    })
end

-------------------------------------------------------------------------------
--  Latency
-------------------------------------------------------------------------------
-- home | world | both (the old useWorldLatency flag reads as world). Shared
-- with the options row, which must agree on what is selected.
function mod.LatencyMode(s)
    if s.latencyMode then
        return s.latencyMode
    end
    return s.useWorldLatency and "world" or "home"
end

local LINKS = { home = { "home" }, world = { "world" }, both = { "home", "world" } }

mod.BlockFactories.ms = function(blockCfg, slot, contentFrame, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    local tickKey = "ms:" .. inst.key

    local function Settings()
        return blockCfg.settings or {}
    end

    local hovered = false
    local drawn -- mode, icon and both values as last drawn

    local button = CreateFrame("Button", nil, contentFrame)
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")
    -- Two parts (icon and value); the second shows only in "both".
    local parts = {}
    for i = 1, 2 do
        parts[i] =
            { icon = button:CreateTexture(nil, "OVERLAY"), text = button:CreateFontString(nil, "OVERLAY") }
        K.AttachTextOffset(inst, parts[i].text)
    end

    local function Paint()
        local region, g, b, ir, ig, ib
        if hovered then
            region, g, b = mod.GetAccent()
            ir, ig, ib = region, g, b
        else
            region, g, b = K.BlockColorOf(blockCfg)
            ir, ig, ib = K.IconColorOf(blockCfg)
        end
        for i = 1, 2 do
            parts[i].text:SetTextColor(region, g, b, 1)
            parts[i].icon:SetVertexColor(ir, ig, ib, 1)
        end
    end

    -- The full read: the bar's values in their quality colours, and bandwidth.
    local function Tooltip()
        mod.Tip_Begin(contentFrame)
        local down, up, home, world = GetNetStats()
        home, world = floor(home), floor(world)
        local unit = mod.GetMSSuffix()
        local hr, hg, hb = LatencyColour(home)
        local wr, wg, wb = LatencyColour(world)
        mod.Tip_AddDouble(L["HOME"], home .. unit, 0.6, 0.6, 0.6, hr, hg, hb)
        mod.Tip_AddDouble(L["WORLD"], world .. unit, 0.6, 0.6, 0.6, wr, wg, wb)
        local rate = " " .. L["KB_PER_SEC"]
        mod.Tip_AddDouble(L["DOWNLOAD"], format("%.1f", down or 0) .. rate, 0.6, 0.6, 0.6, 1, 1, 1)
        mod.Tip_AddDouble(L["UPLOAD"], format("%.1f", up or 0) .. rate, 0.6, 0.6, 0.6, 1, 1, 1)
        mod.Tip_Show()
    end

    local function State()
        local _, _, home, world = GetNetStats()
        local s = Settings()
        return mod.LatencyMode(s) .. (s.showIcon and "I" or "") .. floor(home) .. "/" .. floor(world)
    end

    function inst:Refresh()
        local fontSize = TextSize()
        local barH = barCtx.GetThickness()
        local withIcon = Settings().showIcon == true
        local links = LINKS[mod.LatencyMode(Settings())] or LINKS.home
        local iconSize = withIcon and fontSize + 2 or 0
        local _, _, home, world = GetNetStats()
        local values = { home = floor(home), world = floor(world) }
        local unit = mod.GetMSSuffix()
        -- Each value carries its unit, so "both" never shows a bare number.
        for i = 1, 2 do
            local part, link = parts[i], links[i]
            if link then
                mod.SetFont(part.text, fontSize, barCtx.cfg)
                mod.ResetInlineText(part.text, "LEFT")
                part.text:SetText(values[link] .. unit)
                part.text:Show()
                if withIcon then
                    K.SetBlockIcon(part.icon, blockCfg, link)
                    part.icon:SetSize(iconSize, iconSize)
                    part.icon:Show()
                else
                    part.icon:Hide()
                end
            else
                part.text:Hide()
                part.icon:Hide()
            end
        end
        Paint()

        local lineH = max(fontSize + 4, iconSize)
        if barCtx.IsVertical() then
            -- One centred "icon value" line per link.
            local slotW = K.VSlotW(self)
            local inner = max(24, slotW - 8)
            local y = -4
            for i = 1, #links do
                local part = parts[i]
                local groupW = (withIcon and (iconSize + K.ICON_GAP) or 0)
                    + mod.SnapToPixelGrid(part.text:GetStringWidth())
                local x = max(0, floor((inner - groupW) / 2))
                part.icon:ClearAllPoints()
                part.text:ClearAllPoints()
                if withIcon then
                    part.icon:SetPoint("TOPLEFT", button, "TOPLEFT", x, y - floor((lineH - iconSize) / 2))
                    part.text:SetPoint("LEFT", part.icon, "RIGHT", K.ICON_GAP, 0)
                else
                    part.text:SetPoint("TOPLEFT", button, "TOPLEFT", x, y)
                end
                y = y - lineH - 2
            end
            local height = max(-y + 2, barH)
            contentFrame:SetSize(slotW, height)
            button:SetSize(slotW, height)
        else
            -- In a row, 8px between the two.
            local x = 0
            for i = 1, #links do
                local part = parts[i]
                part.icon:ClearAllPoints()
                part.text:ClearAllPoints()
                if withIcon then
                    part.icon:SetPoint("LEFT", button, "LEFT", x, 0)
                    x = x + iconSize + K.ICON_GAP
                end
                part.text:SetPoint("LEFT", button, "LEFT", x, 0)
                x = x + mod.SnapToPixelGrid(part.text:GetStringWidth())
                if i < #links then
                    x = x + 8
                end
            end
            local width = max(x + 4, 10)
            contentFrame:SetSize(width, barH)
            button:SetSize(width, barH)
        end
        button:ClearAllPoints()
        button:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
        K.MaybeRelayout(self)
    end

    -- The game updates latency about every 30s: a draw only when what is shown changes.
    local function Tick()
        local state = State()
        if state ~= drawn then
            drawn = state
            inst:Refresh()
        end
    end

    button:SetScript("OnEnter", function()
        hovered = true
        Paint()
        Tooltip()
    end)
    button:SetScript("OnLeave", function()
        hovered = false
        mod.Tip_Hide(contentFrame)
        Paint()
    end)

    function inst:Enable()
        contentFrame:Show()
        drawn = nil
        mod.RegisterHeartbeat(tickKey, Tick)
    end
    function inst:Disable()
        mod.UnregisterHeartbeat(tickKey)
        contentFrame:Hide()
    end
    function inst:GetAutoLength()
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 30)
        end
        return max(contentFrame:GetWidth() or 60, 24)
    end
    function inst:Destroy()
        self._dead = true
        contentFrame:Hide()
    end

    return inst
end

-------------------------------------------------------------------------------
--  Durability
-------------------------------------------------------------------------------
mod.BlockFactories.durability = function(blockCfg, slot, contentFrame, barCtx)
    -- The lowest percent across equipped slots 1-18 (as the chat sidebar's icon).
    local function Lowest()
        local lowest = 100
        for s = 1, 18 do
            local current, most = GetInventoryItemDurability(s)
            if current and most and most > 0 then
                lowest = min(lowest, current / most * 100)
            end
        end
        local pct = floor(lowest)
        K.lastDurabilityPct = pct
        return pct
    end

    local function Tooltip(inst)
        if inst then
            inst:ForceSample() -- the bar matches what the tooltip reads
        end
        mod.Tip_Begin(contentFrame)
        mod.Tip_AddDouble("Durability", Lowest() .. "%", 1, 1, 1, 1, 1, 1)
        mod.Tip_Show()
    end

    return SingleValueBlock(blockCfg, slot, contentFrame, barCtx, {
        tickKey = "durability",
        hasIcon = true,
        iconExtra = 7,
        -- Durability changes only on the events the game sends, so no ticker.
        -- Self-repairing items update the alerts without the durability event.
        events = { "UPDATE_INVENTORY_DURABILITY", "UPDATE_INVENTORY_ALERTS", "PLAYER_ENTERING_WORLD" },
        retryDelay = 2,
        sample = Lowest,
        suffix = function()
            return "%"
        end,
        tooltip = Tooltip,
    })
end

-------------------------------------------------------------------------------
--  Combat
-------------------------------------------------------------------------------
mod.BlockFactories.combat = function(blockCfg, slot, contentFrame, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    inst.events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }

    local function Fighting()
        return UnitAffectingCombat("player") and 1 or 0
    end
    local function Words(v)
        return v == 1 and L["IN_COMBAT"] or L["OUT_OF_COMBAT"]
    end
    local function OnlyInCombat()
        return (blockCfg.settings or {}).onlyInCombat == true
    end

    local function Tooltip()
        mod.Tip_Begin(contentFrame)
        mod.Tip_AddDouble(L["COMBAT_STATUS"], Words(Fighting()), 1, 1, 1, 1, 1, 1)
        mod.Tip_Show()
    end

    local hovered = false
    local state = -1
    local fontSize = TextSize()

    local widget = CreateFrame("Button", nil, contentFrame)
    widget:SetSize(60, 20)
    widget:EnableMouse(true)
    widget:RegisterForClicks("AnyUp")
    local label = widget:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, label)
    label:SetPoint("LEFT")
    local ruler = widget:CreateFontString(nil, "OVERLAY")
    ruler:Hide()

    local function Paint()
        if hovered then
            label:SetTextColor(mod.GetAccent())
        else
            label:SetTextColor(K.BlockColorOf(blockCfg))
        end
    end

    function inst:Refresh()
        local barH = barCtx.GetThickness()
        if state < 0 then
            state = Fighting()
        end
        local collapsed = OnlyInCombat() and state ~= 1
        if not collapsed and not contentFrame:IsShown() then
            contentFrame:Show()
        end
        mod.SetFont(label, fontSize, barCtx.cfg)
        label:SetText(CludesUI.L(Words(state)))
        Paint()
        if InCombatLockdown() then
            K.MaybeRelayout(self)
            return
        end
        if barCtx.IsVertical() then
            local slotW = K.VSlotW(self)
            local inner = max(36, slotW - 8)
            widget:SetSize(inner, fontSize + 4)
            widget:ClearAllPoints()
            widget:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
            label:ClearAllPoints()
            label:SetPoint("CENTER", widget, "CENTER", 0, 0)
            mod.SetWrappedText(label, inner, "CENTER")
            contentFrame:SetSize(slotW, max(fontSize + 12, barH))
        else
            mod.ResetInlineText(label, blockCfg.align or "CENTER")
            label:ClearAllPoints()
            label:SetPoint("LEFT", widget, "LEFT", 0, 0)
            -- The wider of the two labels (which one depends on the language),
            -- so combat starting or ending never resizes the block.
            mod.SetFont(ruler, fontSize, barCtx.cfg)
            ruler:SetText(CludesUI.L(Words(0)))
            local outW = ruler:GetStringWidth() or 30
            ruler:SetText(CludesUI.L(Words(1)))
            local width = max(30, mod.SnapToPixelGrid(max(outW, ruler:GetStringWidth() or 30)) + 2)
            label:SetWidth(width)
            widget:SetSize(width, barH)
            widget:ClearAllPoints()
            widget:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
            contentFrame:SetSize(width, barH)
        end
        if collapsed then
            contentFrame:Hide()
            mod.Tip_Hide(contentFrame)
        end
        K.MaybeRelayout(self)
    end

    local function OnEvent()
        local now = Fighting()
        if now == state then
            return
        end
        state = now
        inst:Refresh()
        if hovered then
            Tooltip()
        end
    end

    widget:SetScript("OnEnter", function()
        hovered = true
        Paint()
        Tooltip()
    end)
    widget:SetScript("OnLeave", function()
        hovered = false
        mod.Tip_Hide(contentFrame)
        Paint()
    end)

    function inst:Enable()
        contentFrame:Show()
        state = -1
        if not self.eventFrame then
            self.eventFrame = K.MakeEventFrame(self, OnEvent)
        end
        K.RegisterInstEvents(self)
        OnEvent()
    end

    function inst:Disable()
        K.UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    function inst:GetAutoLength()
        if (OnlyInCombat() and state ~= 1) or not contentFrame:IsShown() then
            return 0
        end
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 40)
        end
        return max(contentFrame:GetWidth() or 70, 40)
    end

    function inst:Destroy()
        self._dead = true
        K.UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    return inst
end
