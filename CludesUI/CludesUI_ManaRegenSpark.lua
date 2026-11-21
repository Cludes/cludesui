if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- CludesUI_ManaRegenSpark.lua
-- WoW FOREVER ONLY: mana regen spark on mana power bars.
--
-- The five second rule: Spirit regen stops when a spell that costs mana
-- finishes casting and resumes five seconds later. A completed cast of a
-- spell that costs mana starts one 5s sweep, and another such cast restarts
-- it. A host in Regen Ticks mode also shows the 2s regen ticks: when the
-- window ends (or mana starts changing while idle) 2s sweeps run back to
-- back, never reset mid-sweep, until a sweep sees no mana update (mana full:
-- the event only fires on a change). The ticks are an estimate of the server
-- tick. Mana is SECRET, so nothing here reads or compares a mana value: the
-- signals are the cast event, the spell's cost type and, for ticks only,
-- UNIT_POWER_UPDATE as a keep-alive (UNIT_POWER_FREQUENT fires many times
-- per tick). All hosts share one timer; a 5-Second Rule host hides during
-- the tick sweeps.
--
-- Hosts ("erb" Resource Bars power bar, "uf" Unit Frames player power bar)
-- Attach their StatusBar while their option is on and the bar can draw, and
-- Detach it otherwise. Attach also lays the spark out, so hosts call it on
-- every rebuild, after the bar's orientation and reverse fill are set.
-- SetMana reports whether the bar shows mana, attached or not. The spark
-- rides an overlay StatusBar, shown only while the sweep draws on it, whose
-- fill the engine animates (SetTimerDuration); one reused animation group
-- times the sweep, so no Lua runs per frame and no sweep creates a timer.
-- Cost: the cast event is registered only while an attached host bar is
-- visible (OnShow/OnHide of our own bars), UNIT_POWER_UPDATE only while such
-- a bar is in Regen Ticks mode. A bar showing Energy or Rage (a
-- druid in a form) keeps it, so a cast there still starts the sweep and the
-- spark joins it on the return to mana. Off, only the unregistered event
-- frame, its animation group and one duration object exist; warriors and
-- rogues, who have no mana, get nothing at all.
-------------------------------------------------------------------------------

local CUI = _G.CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
local _, PLAYER_CLASS = UnitClass("player")
if PLAYER_CLASS == "WARRIOR" or PLAYER_CLASS == "ROGUE" then return end

local MANA = Enum.PowerType.Mana
local WINDOW = 5 -- five second rule
local TICK = 2 -- regen tick interval (Regen Ticks mode)
local SPARK_W = 8 -- spark thickness along the fill direction
local SPARK_TEX = "Interface\\AddOns\\CludesUI\\media\\cast_spark.tga"
local IMMEDIATE = Enum.StatusBarInterpolation.Immediate
local ELAPSED = Enum.StatusBarTimerDirection.ElapsedTime

local hosts = {} -- key -> host record while attached
local built = {} -- bar -> host record (kept across detach)
local mana = {} -- key -> true while that host's bar shows mana
local listening = false -- the cast event is registered
local ticking = false -- UNIT_POWER_UPDATE is registered (a Regen Ticks host)
local sweepEnd -- end time of the running sweep; nil while idle
local inWindow = false -- true while the 5s sweep runs
local regenSeen = false -- mana update seen during the current tick sweep
local dur = C_DurationUtil.CreateDuration()
local eventFrame = CreateFrame("Frame")
local timer = eventFrame:CreateAnimationGroup() -- one-shot, one sweep long
local timerSpan = timer:CreateAnimation("Animation")

-- True when the spell's cost includes mana. A secret amount counts as a cost;
-- only a plain 0 is free.
local function CostsMana(spellId)
    if issecretvalue(spellId) or not spellId then return false end
    local costs = C_Spell.GetSpellPowerCost(spellId)
    if not costs then return false end
    for idx = 1, #costs do
        local c = costs[idx]
        if not issecretvalue(c.type) and c.type == MANA then
            local amt = c.cost
            return issecretvalue(amt) or (type(amt) == "number" and amt > 0)
        end
    end
    return false
end

-- Lays the spark on the overlay's fill edge in the host bar's orientation.
-- Two points span the bar's thickness, so resizes follow with no Lua. The
-- inputs are the bar's orientation and reverse fill (the overlay's fill
-- texture is set once, at build); while they hold, the anchors stand.
local function Layout(hgt)
    local bar = hgt.bar
    local vert = bar:GetOrientation() == "VERTICAL"
    local rev = bar:GetReverseFill() and true or false
    if hgt.vert == vert and hgt.rev == rev then return end
    hgt.vert, hgt.rev = vert, rev
    local o, s = hgt.overlay, hgt.spark
    o:SetOrientation(vert and "VERTICAL" or "HORIZONTAL")
    o:SetReverseFill(rev)
    local ft = o:GetStatusBarTexture()
    s:ClearAllPoints()
    if vert then
        -- The spark texture transposed into a horizontal line.
        s:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
        s:SetPoint("LEFT", ft, rev and "BOTTOMLEFT" or "TOPLEFT")
        s:SetPoint("RIGHT", ft, rev and "BOTTOMRIGHT" or "TOPRIGHT")
        s:SetHeight(SPARK_W)
    else
        s:SetTexCoord(0, 1, 0, 1)
        s:SetPoint("TOP", ft, rev and "TOPLEFT" or "TOPRIGHT")
        s:SetPoint("BOTTOM", ft, rev and "BOTTOMLEFT" or "BOTTOMRIGHT")
        s:SetWidth(SPARK_W)
    end
end

-- Puts an attached host's spark into the running sweep, at its current
-- position, or hides it: it draws only while a sweep runs that the host
-- shows (the 5s window, or any sweep in Regen Ticks mode), the bar shows
-- mana and the bar is visible.
local function Arm(hgt)
    local o = hgt.overlay
    if sweepEnd and (inWindow or hgt.ticks) and mana[hgt.key] and hgt.bar:IsVisible() then
        o:Show()
        o:SetTimerDuration(dur, IMMEDIATE, ELAPSED)
    else
        o:Hide()
    end
end

local function Idle()
    timer:Stop()
    sweepEnd = nil
    inWindow = false
    regenSeen = false
    for _, hgt in pairs(hosts) do
        hgt.overlay:Hide()
    end
end

-- Starts a sweep of len seconds on every host. A tick sweep chains from the
-- end of the one before (start), so the cadence does not drift by a frame
-- per hop; a start already a full sweep behind restarts from now.
local function Sweep(len, start)
    local nowTime = GetTime()
    if not start or start + len <= nowTime then start = nowTime end
    sweepEnd = start + len
    dur:SetTimeFromStart(start, len)
    for _, hgt in pairs(hosts) do
        Arm(hgt)
    end
    timer:Stop()
    timerSpan:SetDuration(sweepEnd - nowTime)
    timer:Play()
end

-- A sweep ended. With a Regen Ticks host listening, the window just closing
-- or a mana update during a tick sweep runs another tick sweep; anything
-- else ends the cycle (regen has resumed, or mana is full).
timer:SetScript("OnFinished", function()
    if ticking and (inWindow or regenSeen) then
        inWindow = false
        regenSeen = false
        Sweep(TICK, sweepEnd)
    else
        Idle()
    end
end)

eventFrame:SetScript("OnEvent", function(_, evt, _, arg2, arg3)
    if evt == "UNIT_SPELLCAST_SUCCEEDED" then
        if CostsMana(arg3) then
            inWindow = true
            regenSeen = false
            Sweep(WINDOW)
        end
    elseif arg2 == "MANA" and not inWindow then
        -- UNIT_POWER_UPDATE, registered only for a Regen Ticks host.
        if sweepEnd then
            regenSeen = true
        else
            Sweep(TICK)
        end
    end
end)

-- The cast event is heard while at least one attached host bar is visible,
-- UNIT_POWER_UPDATE while one of those is in Regen Ticks mode. When the last
-- visible host goes, both are dropped and the cycle ends.
local function SyncListeners()
    local enabled, tk = false, false
    for _, hgt in pairs(hosts) do
        if hgt.bar:IsVisible() then
            enabled = true
            if hgt.ticks then tk = true end
        end
    end
    if tk ~= ticking then
        ticking = tk
        if tk then
            eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        else
            eventFrame:UnregisterEvent("UNIT_POWER_UPDATE")
        end
    end
    if enabled == listening then return end
    listening = enabled
    if enabled then
        eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        eventFrame:UnregisterAllEvents()
        ticking = false
        Idle()
    end
end

-- Hooked once on each host bar (our own StatusBars). A bar that is not
-- attached returns at once; a shown bar joins the running sweep.
local function OnHostShow(bar)
    local hgt = built[bar]
    if hosts[hgt.key] == hgt then
        SyncListeners()
        Arm(hgt)
    end
end

local function OnHostHide(bar)
    local hgt = built[bar]
    if hosts[hgt.key] == hgt then SyncListeners() end
end

local MRS = {}
CUI.ManaRegenSpark = MRS

-- The host's option is on and its bar can draw; ticks = Regen Ticks mode.
-- Lays the spark out on every call, so hosts call it on every rebuild.
function MRS.Attach(key, bar, ticks)
    ticks = ticks and true or false
    local hgt = built[bar]
    if not hgt then
        local o = CreateFrame("StatusBar", nil, bar)
        o:SetAllPoints(bar)
        o:SetFrameLevel(bar:GetFrameLevel() + 2)
        o:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        o:GetStatusBarTexture():SetAlpha(0)
        o:SetMinMaxValues(0, 1)
        o:SetValue(0)
        o:Hide()
        local s = o:CreateTexture(nil, "OVERLAY", nil, 1)
        s:SetTexture(SPARK_TEX)
        s:SetBlendMode("ADD")
        hgt = { bar = bar, overlay = o, spark = s }
        built[bar] = hgt
        bar:HookScript("OnShow", OnHostShow)
        bar:HookScript("OnHide", OnHostHide)
    end
    Layout(hgt)
    local old = hosts[key]
    if old == hgt then
        -- Same bar: only a mode change needs the events and the spark redone.
        if hgt.ticks ~= ticks then
            hgt.ticks = ticks
            SyncListeners()
            Arm(hgt)
        end
        return
    end
    if old then old.overlay:Hide() end
    hgt.key, hgt.ticks = key, ticks
    hosts[key] = hgt
    SyncListeners()
    Arm(hgt)
end

function MRS.Detach(key)
    local hgt = hosts[key]
    if not hgt then return end
    hosts[key] = nil
    hgt.overlay:Hide()
    SyncListeners()
end

-- The host reports whether its bar shows mana. Kept while detached, so an
-- attach starts from the last report; on the edge to mana a running sweep
-- shows at once, at its current position.
function MRS.SetMana(key, isMana)
    if mana[key] == isMana then return end
    mana[key] = isMana
    local hgt = hosts[key]
    if hgt then
        if isMana then Layout(hgt) end
        Arm(hgt)
    end
end
