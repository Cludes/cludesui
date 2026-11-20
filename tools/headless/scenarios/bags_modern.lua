-- The Modern bag display (CUI_Bags_Modern.lua): the bags profile switched to
-- "modern" and the display-mode latch reset (through the debug library, as
-- a /reload would), the bags opened and the window snapshotted (header, chip
-- strip, grid); then each chip clicked in turn, the selection and the window
-- snapshotted after each. Old code without the Modern display shows the
-- Grid display throughout.
local ns = CludesUI._ModuleNS and CludesUI._ModuleNS["CludesUIBags"]
local bags = rawget(_G, "CUI_Bags")
if not (ns and bags) then
    OUT:write("== no bags module\n")
    return
end
local inner = ns._bagsInternals
local p = inner and inner.BP and inner.BP()
if not p then
    OUT:write("== no bags profile\n")
    return
end
p.bagDisplayMode = "modern"
-- Reset IsListMode's latch so the next read takes the new mode
local fn = bags.IsListMode
for i = 1, 20 do
    local name = debug.getupvalue(fn, i)
    if not name then break end
    if name == "_listMode" then
        debug.setupvalue(fn, i, nil)
    end
end
OUT:write("== modern: " .. tostring(bags.IsModernMode and bags.IsModernMode()) .. " list: " .. tostring(bags.IsListMode()) .. "\n")

local function Open()
    local ok, err = pcall(function()
        if not bags:IsShown() then bags:Show() end
        bags:RefreshInventory()
    end)
    if not ok then OUT:write("== refresh ERR " .. tostring(err) .. "\n") end
    HARNESS_ADVANCE(0.5)
end
Open()
SNAP("bags", bags)

local function Chips()
    local out = {}
    for _, c in ipairs({ bags:GetChildren() }) do
        if c:IsShown() and c["\0kind"] == "Frame" then
            for _, b in ipairs(c["\0children"] or {}) do
                if b["\0kind"] == "Button" and b:IsShown() and rawget(b, "_catIdx") ~= nil then
                    out[#out + 1] = b
                end
            end
        end
    end
    return out
end
local list = Chips()
OUT:write("== chips " .. #list .. "\n")
for i = 1, #list do
    local chip = Chips()[i]
    if chip then
        local ok, err = pcall(chip["\0scripts"].OnClick, chip, "LeftButton")
        HARNESS_ADVANCE(0.3)
        local sel, grp = ns.GetSelection()
        OUT:write("== chip " .. i .. " " .. tostring(rawget(chip, "_catIdx")) .. "/" .. tostring(rawget(chip, "_groupName")) .. " " .. (ok and "ok" or ("ERR " .. tostring(err))) .. " -> " .. tostring(sel) .. "/" .. tostring(grp) .. "\n")
        SNAP("after chip " .. i, bags)
    end
end
