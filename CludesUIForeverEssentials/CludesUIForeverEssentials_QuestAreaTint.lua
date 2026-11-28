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

local BLOB_TEMPLATE = "QuestBlobPinTemplate"
local TINT_DIR = "Interface\\AddOns\\CludesUI\\media\\questarea\\"
local STOCK_INSIDE = "Interface\\WorldMap\\UI-QuestBlob-Inside"
local STOCK_RIM = "Interface\\WorldMap\\UI-QuestBlob-Outside"
local STOCK_INSIDE_ALPHA, STOCK_RIM_ALPHA = 128, 192
local SWATCHES = { blue = true, violet = true, green = true, gold = true, red = true }

local recoloured, mapHooked

local function Recolor(pin, inside, rim, insideAlpha, rimAlpha)
    pin:SetFillTexture(inside)
    pin:SetBorderTexture(rim)
    pin:SetFillAlpha(insideAlpha)
    pin:SetBorderAlpha(rimAlpha)
end

local function TintAll()
    local worldMap = _G.WorldMapFrame
    if not (worldMap and worldMap.EnumeratePinsByTemplate) then return end
    local wanted = Enabled()
    if not (wanted or recoloured) then return end
    local swatch = SWATCHES[Get("color")] and Get("color") or "blue"
    local insideAlpha = math.floor(Get("fill") * 255 + 0.5)
    for pin in worldMap:EnumeratePinsByTemplate(BLOB_TEMPLATE) do
        if pin.SetFillTexture then
            if wanted then
                Recolor(pin, TINT_DIR .. swatch .. "_fill", TINT_DIR .. swatch .. "_edge", insideAlpha, 255)
            else
                Recolor(pin, STOCK_INSIDE, STOCK_RIM, STOCK_INSIDE_ALPHA, STOCK_RIM_ALPHA)
            end
        end
    end
    recoloured = wanted
end

local function Apply()
    local worldMap = _G.WorldMapFrame
    if Enabled() and worldMap and not mapHooked then
        mapHooked = true
        if worldMap.OnMapChanged then hooksecurefunc(worldMap, "OnMapChanged", TintAll) end
        worldMap:HookScript("OnShow", TintAll)
    end
    TintAll()
end

CUI._QuestAreaTint = { Get = Get, Cfg = F.Cfg, Apply = Apply }
F.Start(Apply)
