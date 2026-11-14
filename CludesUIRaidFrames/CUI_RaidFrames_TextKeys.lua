if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_TextKeys.lua
--
--  The texts a raid frame can show, by their setting keys: Name, Level, Health,
--  Power and Heal Absorb Text on their own keys, plus a second Health Text and
--  up to four Custom texts. Every text keeps its position, offsets, size and
--  colour (texts may share a position). Read by the engine and the tiles.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ipairs = ipairs

-- The nine spots, in grid order (the tile order of the Text Display list).
local POSITIONS =
    { "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
local POS_INDEX = {}
for idx, p in ipairs(POSITIONS) do
    POS_INDEX[p] = idx
end
mod.RF_TEXT_POSITIONS, mod.RF_TEXT_POS_INDEX = POSITIONS, POS_INDEX

-- One text: kind, label, and its keys. mode: the mode key (Health, Power, Heal
-- Absorb); fmt: the template key (Custom); above: Show Above Icons (unset: as the
-- name's). The level is drawn in the name's colour.
local function Text(ident, kindOf, labelText, prefixText, modeName)
    return {
        id = ident,
        kind = kindOf,
        label = labelText,
        mode = modeName and (prefixText .. "Mode") or nil,
        pos = prefixText .. "Position",
        x = prefixText .. "OffsetX",
        y = prefixText .. "OffsetY",
        size = prefixText .. "Size",
        cm = prefixText .. "ColorMode",
        col = prefixText .. "CustomColor",
        above = prefixText .. "AboveIcons",
    }
end

local TEXTS = {
    {
        id = "name",
        kind = "name",
        label = "Name",
        pos = "namePosition",
        x = "nameOffsetX",
        y = "nameOffsetY",
        size = "nameSize",
        cm = "nameColorMode",
        col = "nameCustomColor",
        above = "nameTextAboveIcons",
    },
    {
        id = "level",
        kind = "level",
        label = "Level",
        pos = "levelTextPosition",
        x = "levelTextOffsetX",
        y = "levelTextOffsetY",
        size = "levelTextSize",
        cm = "nameColorMode",
        col = "nameCustomColor",
        above = "levelTextAboveIcons",
    },
    Text("hp", "hp", "Health Text", "healthText", true),
    Text("hp2", "hp", "Second Health Text", "healthText2", true),
    Text("pp", "pp", "Power Text", "powerText", true),
    Text("ha", "ha", "Heal Absorb Text", "healAbsorbText", true),
}
mod.RF_CUSTOM_TEXT_MAX = 4
for num = 1, mod.RF_CUSTOM_TEXT_MAX do
    local t = Text("custom" .. num, "custom", "Custom Text " .. num, "customText" .. num)
    t.fmt = "customText" .. num .. "Format"
    TEXTS[#TEXTS + 1] = t
end
mod.RF_TEXTS = TEXTS

-- The keys this PR adds (the second Health Text and the Custom texts), for the
-- party sync list and the scaled sizes and offsets. Defaults: off.
local NEW_KEYS, NEW_SCALE_KEYS = {}, {}
local p = Inner.defaults.profile
for _, t in ipairs(TEXTS) do
    if t.id == "hp2" or t.kind == "custom" then
        for _, key in ipairs({ t.mode or t.fmt, t.pos, t.x, t.y, t.size, t.cm, t.col }) do
            NEW_KEYS[#NEW_KEYS + 1] = key
        end
        NEW_SCALE_KEYS[#NEW_SCALE_KEYS + 1] = t.size
        NEW_SCALE_KEYS[#NEW_SCALE_KEYS + 1] = t.x
        NEW_SCALE_KEYS[#NEW_SCALE_KEYS + 1] = t.y
        if t.mode then
            p[t.mode] = "none"
        end
        p[t.pos] = (t.kind == "custom") and "none" or "bottom"
        p[t.x], p[t.y], p[t.size], p[t.cm] = 0, 0, (t.kind == "custom") and 10 or 9, "custom"
        p[t.col] = { r = 1, g = 1, b = 1 }
    end
    -- Show Above Icons per text: new for every text but the name (no default).
    if t.id ~= "name" then
        NEW_KEYS[#NEW_KEYS + 1] = t.above
    end
end
mod.RF_TEXT_NEW_KEYS, mod.RF_TEXT_NEW_SCALE_KEYS = NEW_KEYS, NEW_SCALE_KEYS

Inner.broken = false
