-- Auras, Buffs & Consumables page rebuilt with a textured border style (its
-- offset row and options cog), then with a masked icon shape (Border Size
-- becomes None / Strong).
local CUI = rawget(_G, "CludesUI")
local db = rawget(_G, "_CUABR_AceDB")
local d = db and db.profile and db.profile.display
local function Rebuild()
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    CUI:SelectModule("CludesUIAuraBuffReminders")
    CUI:SelectPage("Auras, Buffs & Consumables")
end
local textured
for _, style in ipairs(CUI._builtinBorderTextures or {}) do
    if style.key ~= "solid" and style.key ~= "" then textured = style.key break end
end
local masked
for key in pairs(CUI.SHAPE_MASKS or {}) do
    if key ~= "none" and key ~= "cropped" and (not masked or key < masked) then masked = key end
end
OUT:write("== styles " .. tostring(textured) .. " " .. tostring(masked) .. "\n")
if d and textured then
    d.borderTexture = textured; d.borderTextureShiftX = 2; d.borderTextureOffset = 3; d.borderBehind = true
    Rebuild()
    SNAP("textured border", CUI._scrollFrame)
end
if d and masked then
    d.borderTexture = "solid"; d.iconShape = masked; d.borderSize = 0
    Rebuild()
    SNAP("masked shape", CUI._scrollFrame)
end
