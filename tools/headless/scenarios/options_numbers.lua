-- Global Settings > Numbers: header and page for every value type, with a
-- Precision set (threshold unlocked), the global Unit Style and Letter Case
-- changed and the Unit Frames override note shown.
local CUI = rawget(_G, "CludesUI")
local function Show(label)
    SNAP(label .. " header", CUI._contentHeader)
    SNAP(label .. " page", CUI._scrollFrame)
end
local function PickType(vt)
    CUI._setNumberFormatType(vt)
    _CUI_NumberFormatRefreshHeader()
    CUI:RefreshPage()
end
CUI:SelectModule(CUI.GLOBAL_KEY or "_CUIGlobal")
CUI:SelectPage("Numbers")
Show("defaults")
for _, vt in ipairs(CUI.NUMBER_FORMAT_TYPES) do
    PickType(vt)
    Show("type " .. vt)
end
local v = _CUI_NumberFormatVariants()
OUT:write("== variants: ", table.concat(v.keys, ","), " current ", tostring(v.currentKey), "\n")

local nf = CUI.GetNumberFormatDB(true)
nf.types = nf.types or {}
nf.types.health = { precision = "smart", threshold = 10000 }
nf.types.meter = { precision = 1 }
nf.case = "lower"
nf.units = "western"
CUI.RefreshNumberFormat()
local uf = CUI.ModuleNS("CludesUIUnitFrames")
if uf and uf.db then uf.db.profile.showDecimalOnText = true end
PickType("health")
Show("health smart")
PickType("meter")
Show("meter 1")
