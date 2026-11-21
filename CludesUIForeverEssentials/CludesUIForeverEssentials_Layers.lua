if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
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
local SEEN_MAX = 12
local NPC_KINDS = { Creature = true, Vehicle = true }

local function Font() return CludesUI.GetFontPath("essentials") end
local function Secret(val) return issecretvalue and issecretvalue(val) end

local function LayerOf(unitGuid)
    if type(unitGuid) ~= "string" or Secret(unitGuid) then return end
    local kind, _, server, _, zone = strsplit("-", unitGuid)
    if not NPC_KINDS[kind] then return end
    server, zone = tonumber(server), tonumber(zone)
    if not (server and zone and server > 0 and zone > 0) then return end
    return ("%d-%d"):format(server, zone), zone
end

local function ZoneMap()
    local ident = C_Map.GetBestMapForUnit("player")
    local details = ident and C_Map.GetMapInfo(ident)
    while details and details.mapType > Enum.UIMapType.Zone and details.parentMapID ~= 0 do
        ident = details.parentMapID
        details = C_Map.GetMapInfo(ident)
    end
    return ident
end

local widget, ticker
local layer, isShown, map, inside, refreshAt, wasKey, wasZone, pendingKey, pendingGuid
local seen = {}

local function Note(where, key, zone)
    if not where then return end
    local list = seen[where]
    if not list then
        list = { n = 0, entries = {} }
        seen[where] = list
    end
    local e = list.entries[key]
    if not e then
        if list.n >= SEEN_MAX then
            local oldest
            for key, val in pairs(list.entries) do
                if not oldest or val.at < list.entries[oldest].at then oldest = key end
            end
            list.entries[oldest] = nil
            list.n = list.n - 1
        end
        e = { key = key, zone = zone }
        list.entries[key] = e
        list.n = list.n + 1
    end
    e.at = time()
end

-- The zone UID alone, unless two layers seen here share it: then the full key.
local function Label(key, zone)
    local list = map and seen[map]
    if not list then return zone end
    for other, entry in pairs(list.entries) do
        if other ~= key and entry.zone == zone then return key end
    end
    return zone
end

local function Text()
    local textValue = ("Layer %s"):format(layer and Label(layer, isShown) or "?")
    if refreshAt and Get("countdown") then
        local leftX = refreshAt - GetTime()
        if leftX <= 0 then return textValue .. " - changing" end
        return ("%s - changes in %d:%02d"):format(textValue, math.floor(leftX / 60), math.floor(leftX % 60))
    end
    return textValue
end

local function Update()
    if not widget then return end
    if not Enabled() or (inside and not CludesUI._unlockActive) then
        widget:Hide()
        return
    end
    CludesUI.Kit.Font(widget.text, Get("size"), "essentials")
    widget.text:SetText(Text())
    widget:SetSize(widget.text:GetStringWidth() + 16, Get("size") + 8)
    widget:Show()
end

local function Clock()
    local wanted = refreshAt and Get("countdown")
    if wanted and not ticker then
        ticker = C_Timer.NewTicker(1, Update)
    elseif not wanted and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function Seen(key, zone, unitGuid)
    if key == layer then
        pendingKey, pendingGuid = nil, nil
        return
    end
    -- A change needs a second, different NPC on the same layer.
    if key ~= pendingKey or unitGuid == pendingGuid then
        pendingKey, pendingGuid = key, unitGuid
        return
    end
    pendingKey, pendingGuid = nil, nil
    layer, isShown = key, zone
    Note(map, key, zone)
    if wasKey and wasKey ~= key and Get("chat") then
        CludesUI.Print(
            ("|cff4cc9f0Layers:|r you moved to layer %s (it was %s)."):format(
                Label(key, zone),
                Label(wasKey, wasZone)
            )
        )
    end
    wasKey, wasZone = nil, nil
    Update()
end

local function Read(unitToken, replace)
    if inside or (layer and not replace) then return end
    local key, zone = LayerOf(UnitGUID(unitToken))
    if key then Seen(key, zone, UnitGUID(unitToken)) end
end

local function Forget()
    layer, isShown, pendingKey, pendingGuid = nil, nil, nil, nil
    Update()
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, evt, unitToken)
    if evt == "NAME_PLATE_UNIT_ADDED" then
        if not (layer or Secret(unitToken)) then Read(unitToken) end
    elseif evt == "PLAYER_TARGET_CHANGED" then
        Read("target", true)
    elseif evt == "UPDATE_MOUSEOVER_UNIT" then
        Read("mouseover", true)
    elseif evt == "SHARD_TRANSFER_IMMINENT" then
        refreshAt = GetTime() + (GetEvictionTimeRemaining and GetEvictionTimeRemaining() or 0)
        Clock()
        Update()
    elseif evt == "SHARD_TRANSFER_CANCELLED" then
        refreshAt = nil
        Clock()
        Update()
    elseif evt == "SHARD_TRANSFER" then
        refreshAt = nil
        Clock()
        wasKey, wasZone = layer, isShown
        Forget()
    else
        wasKey, wasZone = nil, nil
        inside = IsInInstance()
        map = ZoneMap()
        Forget()
        if evt == "PLAYER_ENTERING_WORLD" then Read("target", true) end
    end
end)

local function Build()
    if widget then return widget end
    widget = CreateFrame("Frame", "CludesUILayerTracker", UIParent)
    widget.text = widget:CreateFontString(nil, "OVERLAY")
    widget.text:SetPoint("CENTER")
    widget:EnableMouse(true)
    widget:SetScript("OnEnter", function(self)
        local details = map and C_Map.GetMapInfo(map)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(("Layers in %s"):format(details and details.name or "?"), 1, 1, 1)
        local sequence = {}
        for _, entry in pairs(map and seen[map] and seen[map].entries or {}) do
            sequence[#sequence + 1] = entry
        end
        table.sort(sequence, function(lhs, rhs) return lhs.at > rhs.at end)
        if #sequence == 0 then
            GameTooltip:AddLine("Target or mouse over an NPC to read your layer.", 0.6, 0.6, 0.6, true)
        end
        for _, entry in ipairs(sequence) do
            if entry.key == layer then
                GameTooltip:AddDoubleLine(
                    Label(entry.key, entry.zone),
                    "You are here",
                    1,
                    1,
                    1,
                    CludesUI.Kit.Accent()
                )
            else
                local ago = time() - entry.at
                GameTooltip:AddDoubleLine(
                    Label(entry.key, entry.zone),
                    ago < 60 and (ago .. "s ago") or (math.floor(ago / 60) .. "m ago"),
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
    eventFrame:UnregisterAllEvents()
    if not Enabled() then
        layer, isShown, wasKey, wasZone, refreshAt, pendingKey, pendingGuid =
            nil, nil, nil, nil, nil, nil, nil
        Clock()
        if widget then widget:Hide() end
        return
    end
    Build()
    if not CludesUI._unlockActive then F.Place(widget) end
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
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    inside = IsInInstance()
    map = ZoneMap()
    Read("target", true)
    Clock()
    Update()
end

F.Start(Apply, {
    key = "CUI_LayerTracker",
    label = "Layer Tracker",
    order = 753,
    frame = function(build)
        if build then
            Build()
            Update()
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
    local wasUp = StaticPopup1 and StaticPopup1:IsShown()
    prompt:Click("LeftButton", true)
    if not wasUp and StaticPopup1 and StaticPopup1:IsShown() then StaticPopup1Button1:Click() end
end

local function Hook()
    local prompt = _G.ShardTransferImminentFrame
    if hooked or not prompt then return end
    prompt:HookScript("OnShow", Accept)
    hooked = true
end

swapEv:SetScript("OnEvent", function()
    Hook()
    Accept()
end)

S.Start(function()
    if S.Enabled() then
        swapEv:RegisterEvent("GROUP_JOINED")
        Hook()
    else
        swapEv:UnregisterAllEvents()
    end
end)

CludesUI._Layers =
    { tracker = { Get = Get, Cfg = F.Cfg, Apply = Apply }, swap = { Get = S.Get, Cfg = S.Cfg } }
