if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_QuestAreaTint.lua  (WoW Forever only)
--  Quest Area Tint: the world map's quest objective areas in a colour of
--  your choice with a solid glowing edge, instead of the game's faint
--  yellow. The areas are Blizzard's quest blob pins; only their fill and
--  edge textures and alphas change (the pin's own setters), on each map
--  change and when the map opens, so pins made later are tinted too. Off,
--  the game's own textures go back. Textures:
--  CludesUI/media/questarea/<colour>_fill / _edge.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("questAreaTint", { enabled = false, color = "blue", fill = 0.5 })
local Get, Enabled = F.Get, F.Enabled

local TEMPLATE = "QuestBlobPinTemplate"
local MEDIA = "Interface\\AddOns\\CludesUI\\media\\questarea\\"
local GAME_FILL = "Interface\\WorldMap\\UI-QuestBlob-Inside"
local GAME_EDGE = "Interface\\WorldMap\\UI-QuestBlob-Outside"
local GAME_FILL_ALPHA, GAME_EDGE_ALPHA = 128, 192
local COLORS = { blue = true, violet = true, green = true, gold = true, red = true }

local tinted, hooked

local function Paint(pin, fill, edge, fillAlpha, edgeAlpha)
    pin:SetFillTexture(fill)
    pin:SetBorderTexture(edge)
    pin:SetFillAlpha(fillAlpha)
    pin:SetBorderAlpha(edgeAlpha)
end

local function Tint()
    local map = _G.WorldMapFrame
    if not (map and map.EnumeratePinsByTemplate) then return end
    local on = Enabled()
    if not (on or tinted) then return end
    local color = COLORS[Get("color")] and Get("color") or "blue"
    local fillAlpha = math.floor(Get("fill") * 255 + 0.5)
    for pin in map:EnumeratePinsByTemplate(TEMPLATE) do
        if pin.SetFillTexture then
            if on then
                Paint(pin, MEDIA .. color .. "_fill", MEDIA .. color .. "_edge", fillAlpha, 255)
            else
                Paint(pin, GAME_FILL, GAME_EDGE, GAME_FILL_ALPHA, GAME_EDGE_ALPHA)
            end
        end
    end
    tinted = on
end

local function Apply()
    local map = _G.WorldMapFrame
    if Enabled() and map and not hooked then
        hooked = true
        if map.OnMapChanged then hooksecurefunc(map, "OnMapChanged", Tint) end
        map:HookScript("OnShow", Tint)
    end
    Tint()
end

CUI._QuestAreaTint = { Get = Get, Cfg = F.Cfg, Apply = Apply }
F.Start(Apply)
