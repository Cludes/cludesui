-- Colour picker: with and without opacity, and a hex entry.
local CUI = rawget(_G, "CludesUI")
local function Picker() return rawget(_G, "CludesUIColorPicker") end
CUI:ShowColorPicker({ r = 1, g = 0.5, b = 0.25, swatchFunc = function() end, cancelFunc = function() end })
SNAP("picker", Picker())
CUI:ShowColorPicker({ r = 0.2, g = 0.4, b = 0.6, opacity = 0.5, hasOpacity = true, swatchFunc = function() end, opacityFunc = function() end, cancelFunc = function() end })
SNAP("picker opacity", Picker())
