-- Quest Area Tint (CludesUIForeverEssentials_QuestAreaTint.lua): the quest
-- blob pins take the chosen colour's textures and opacity, a pin added later
-- is tinted on the next map change, and off puts the game's textures back.
local CUI = rawget(_G, "CludesUI")
local QT = CUI._QuestAreaTint
OUT:write("== tint " .. tostring(QT ~= nil) .. "\n")
if not QT then return end

local function Pin()
    local p = { log = {} }
    function p:SetFillTexture(t) self.log.fill = t end
    function p:SetBorderTexture(t) self.log.edge = t end
    function p:SetFillAlpha(a) self.log.fillA = a end
    function p:SetBorderAlpha(a) self.log.edgeA = a end
    return p
end
local pins = { Pin() }
local map = _G.WorldMapFrame
map.EnumeratePinsByTemplate = function(_, template)
    local i = 0
    return function()
        i = i + 1
        if template == "QuestBlobPinTemplate" then return pins[i] end
    end
end
map.OnMapChanged = map.OnMapChanged or function() end
local function Show(tag, p)
    local l = p.log
    OUT:write(("== %s: fill=%s edge=%s alpha=%s/%s\n"):format(tag, tostring(l.fill and l.fill:match("[^\\]+$")),
        tostring(l.edge and l.edge:match("[^\\]+$")), tostring(l.fillA), tostring(l.edgeA)))
end

QT.Cfg().enabled = true
QT.Apply()
Show("on, blue 50%", pins[1])
QT.Cfg().color, QT.Cfg().fill = "gold", 0.3
QT.Apply()
Show("gold 30%", pins[1])
pins[2] = Pin()
map:OnMapChanged()
Show("a pin added, map changed", pins[2])
QT.Cfg().enabled = false
QT.Apply()
Show("off", pins[1])
