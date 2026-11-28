if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Layers.lua  (WoW Forever only)
--  Layer Tracker: which layer of the zone you are on, read from the GUID of
--  the NPCs around you (target, mouseover, nameplates): Creature-0-server-
--  instance-zoneUID-..., where server and zoneUID name the copy. A new layer
--  counts only after two different NPCs agree, so one stray reading cannot
--  move it. A countdown when the game is about to move you to another layer,
--  and a chat line when it has. Hover it for the layers seen in this zone.
--  Auto-Accept Layer Swap: confirms the game's layer swap prompt when you
--  join a group.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature(
    "layerTracker",
    { enabled = false, countdown = true, chat = true, size = 14 },
    { point = "TOP", relPoint = "TOP", x = -274, y = -77 }
)
local Get, Enabled = F.Get, F.Enabled
local SPOTTED_TOP = 12
local NPC_KINDS = { Creature = true, Vehicle = true }

local function Typeface() return CUI.GetFontPath("essentials") end
local function Secret(val) return issecretvalue and issecretvalue(val) end

local function LayerOf(unitId)
    if type(unitId) ~= "string" or Secret(unitId) then return end
    local kind, _, server, _, area = strsplit("-", unitId)
    if not NPC_KINDS[kind] then return end
    server, area = tonumber(server), tonumber(area)
    if not (server and area and server > 0 and area > 0) then return end
    return ("%d-%d"):format(server, area), area
end

local function AreaChart()
    local ident = C_Map.GetBestMapForUnit("player")
    local details = ident and C_Map.GetMapInfo(ident)
    while details and details.mapType > Enum.UIMapType.Zone and details.parentMapID ~= 0 do
        ident = details.parentMapID
        details = C_Map.GetMapInfo(ident)
    end
    return ident
end

local widget, ticker
local layer, isShown, chart, inside, renewAt, wasId, wasArea, pendingKey, pendingId
local spotted = {}

local function Jot(where, id, area)
    if not where then return end
    local roster = spotted[where]
    if not roster then
        roster = { n = 0, entries = {} }
        spotted[where] = roster
    end
    local e = roster.entries[id]
    if not e then
        if roster.n >= SPOTTED_TOP then
            local oldest
            for id, val in pairs(roster.entries) do
                if not oldest or val.at < roster.entries[oldest].at then oldest = id end
            end
            roster.entries[oldest] = nil
            roster.n = roster.n - 1
        end
        e = { key = id, zone = area }
        roster.entries[id] = e
        roster.n = roster.n + 1
    end
    e.at = time()
end

-- The zone UID alone, unless two layers seen here share it: then the full key.
local function Label(id, area)
    local roster = chart and spotted[chart]
    if not roster then return area end
    for other, item in pairs(roster.entries) do
        if other ~= id and item.zone == area then return id end
    end
    return area
end

local function Text()
    local labelValue = ("Layer %s"):format(layer and Label(layer, isShown) or "?")
    if renewAt and Get("countdown") then
        local leftX = renewAt - GetTime()
        if leftX <= 0 then return labelValue .. " - changing" end
        return ("%s - changes in %d:%02d"):format(labelValue, math.floor(leftX / 60), math.floor(leftX % 60))
    end
    return labelValue
end

local function Refresh()
    if not widget then return end
    if not Enabled() or (inside and not CUI._unlockActive) then
        widget:Hide()
        return
    end
    CUI.Kit.Font(widget.text, Get("size"), "essentials")
    widget.text:SetText(Text())
    widget:SetSize(widget.text:GetStringWidth() + 16, Get("size") + 8)
    widget:Show()
end

local function Clock()
    local desired = renewAt and Get("countdown")
    if desired and not ticker then
        ticker = C_Timer.NewTicker(1, Refresh)
    elseif not desired and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function Spotted(id, area, unitId)
    if id == layer then
        pendingKey, pendingId = nil, nil
        return
    end
    -- A change needs a second, different NPC on the same layer.
    if id ~= pendingKey or unitId == pendingId then
        pendingKey, pendingId = id, unitId
        return
    end
    pendingKey, pendingId = nil, nil
    layer, isShown = id, area
    Jot(chart, id, area)
    if wasId and wasId ~= id and Get("chat") then
        CUI.Print(
            ("|cff4cc9f0Layers:|r you moved to layer %s (it was %s)."):format(
                Label(id, area),
                Label(wasId, wasArea)
            )
        )
    end
    wasId, wasArea = nil, nil
    Refresh()
end

local function Load(unitToken, replace)
    if inside or (layer and not replace) then return end
    local id, area = LayerOf(UnitGUID(unitToken))
    if id then Spotted(id, area, UnitGUID(unitToken)) end
end

local function Forget()
    layer, isShown, pendingKey, pendingId = nil, nil, nil, nil
    Refresh()
end

local eventWindow = CreateFrame("Frame")
eventWindow:SetScript("OnEvent", function(_, evt, unitToken)
    if evt == "NAME_PLATE_UNIT_ADDED" then
        if not (layer or Secret(unitToken)) then Load(unitToken) end
    elseif evt == "PLAYER_TARGET_CHANGED" then
        Load("target", true)
    elseif evt == "UPDATE_MOUSEOVER_UNIT" then
        Load("mouseover", true)
    elseif evt == "SHARD_TRANSFER_IMMINENT" then
        renewAt = GetTime() + (GetEvictionTimeRemaining and GetEvictionTimeRemaining() or 0)
        Clock()
        Refresh()
    elseif evt == "SHARD_TRANSFER_CANCELLED" then
        renewAt = nil
        Clock()
        Refresh()
    elseif evt == "SHARD_TRANSFER" then
        renewAt = nil
        Clock()
        wasId, wasArea = layer, isShown
        Forget()
    else
        wasId, wasArea = nil, nil
        inside = IsInInstance()
        chart = AreaChart()
        Forget()
        if evt == "PLAYER_ENTERING_WORLD" then Load("target", true) end
    end
end)

local function Make()
    if widget then return widget end
    widget = CreateFrame("Frame", "CludesUILayerTracker", UIParent)
    widget.text = widget:CreateFontString(nil, "OVERLAY")
    widget.text:SetPoint("CENTER")
    widget:EnableMouse(true)
    widget:SetScript("OnEnter", function(self)
        local details = chart and C_Map.GetMapInfo(chart)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(("Layers in %s"):format(details and details.name or "?"), 1, 1, 1)
        local sequence = {}
        for _, item in pairs(chart and spotted[chart] and spotted[chart].entries or {}) do
            sequence[#sequence + 1] = item
        end
        table.sort(sequence, function(lhs, rhs) return lhs.at > rhs.at end)
        if #sequence == 0 then
            GameTooltip:AddLine("Target or mouse over an NPC to read your layer.", 0.6, 0.6, 0.6, true)
        end
        for _, item in ipairs(sequence) do
            if item.key == layer then
                GameTooltip:AddDoubleLine(
                    Label(item.key, item.zone),
                    "You are here",
                    1,
                    1,
                    1,
                    CUI.Kit.Accent()
                )
            else
                local since = time() - item.at
                GameTooltip:AddDoubleLine(
                    Label(item.key, item.zone),
                    since < 60 and (since .. "s ago") or (math.floor(since / 60) .. "m ago"),
                    1,
                    1,
                    1,
                    0.6,
                    0.6,
                    0.6
                )
            end
        end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
    widget:Hide()
    return widget
end

local function Apply()
    eventWindow:UnregisterAllEvents()
    if not Enabled() then
        layer, isShown, wasId, wasArea, renewAt, pendingKey, pendingId =
            nil, nil, nil, nil, nil, nil, nil
        Clock()
        if widget then widget:Hide() end
        return
    end
    Make()
    if not CUI._unlockActive then F.Place(widget) end
    for _, event in ipairs({
        "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA",
        "PLAYER_TARGET_CHANGED",
        "UPDATE_MOUSEOVER_UNIT",
        "NAME_PLATE_UNIT_ADDED",
        "SHARD_TRANSFER_IMMINENT",
        "SHARD_TRANSFER_CANCELLED",
        "SHARD_TRANSFER",
    }) do
        pcall(eventWindow.RegisterEvent, eventWindow, event)
    end
    inside = IsInInstance()
    chart = AreaChart()
    Load("target", true)
    Clock()
    Refresh()
end

F.Start(Apply, {
    key = "CUI_LayerTracker",
    label = "Layer Tracker",
    order = 753,
    frame = function(make)
        if make then
            Make()
            Refresh()
        end
        return widget
    end,
    size = function() return 160, Get("size") + 8 end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})

-------------------------------------------------------------------------------
--  Auto-Accept Layer Swap
-------------------------------------------------------------------------------
local S = module.Feature("layerSwap", { enabled = false })
local swapEv = CreateFrame("Frame")
local hooked

local function Accept()
    local prompt = _G.ShardTransferImminentFrame
    if not (S.Enabled() and IsInGroup() and prompt and prompt:IsShown()) then return end
    local wasGain = StaticPopup1 and StaticPopup1:IsShown()
    prompt:Click("LeftButton", true)
    if not wasGain and StaticPopup1 and StaticPopup1:IsShown() then StaticPopup1Button1:Click() end
end

local function Attach()
    local prompt = _G.ShardTransferImminentFrame
    if hooked or not prompt then return end
    prompt:HookScript("OnShow", Accept)
    hooked = true
end

swapEv:SetScript("OnEvent", function()
    Attach()
    Accept()
end)

S.Start(function()
    if S.Enabled() then
        swapEv:RegisterEvent("GROUP_JOINED")
        Attach()
    else
        swapEv:UnregisterAllEvents()
    end
end)

CUI._Layers =
    { tracker = { Get = Get, Cfg = F.Cfg, Apply = Apply }, swap = { Get = S.Get, Cfg = S.Cfg } }
