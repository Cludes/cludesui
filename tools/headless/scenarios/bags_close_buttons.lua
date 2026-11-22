-- Bags: the close "x" buttons of the bag window, the reagent bag, the bank and
-- the stack splitter. Every button holding the close icon is found by walking
-- the frames under each window; for each one: where it sits, its size, its
-- points, the icon's alpha at rest, under the cursor (OnEnter) and after
-- (OnLeave), and whether it has a click script.
local ns = CludesUI._ModuleNS and CludesUI._ModuleNS["CludesUIBags"]
local bags = rawget(_G, "CUI_Bags")
if not (ns and bags) then
    OUT:write("== no bags module\n")
    return
end
local inner = ns._bagsInternals
local p = inner and inner.BP and inner.BP()
if p then
    p.bagDisplayMode = "grid"
    local fn = bags.IsListMode
    for i = 1, 20 do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == "_listMode" then debug.setupvalue(fn, i, nil) end
    end
end

local function Open()
    local ok, err = pcall(function()
        if not bags:IsShown() then bags:Show() end
        bags:RefreshInventory()
    end)
    if not ok then OUT:write("== open ERR " .. tostring(err) .. "\n") end
    HARNESS_ADVANCE(0.5)
end
Open()

-- The stack splitter's dialog builds when first asked to open; stub what it asks.
local owner = CreateFrame("Button", nil, UIParent)
owner:SetID(1)
CludesUI.StackSplitFor = function() return 20 end
local opList = {
    ownerBag = function() return 0 end,
    info = function() return { itemID = 6948, stackCount = 20 } end,
}
local ok, err = pcall(bags.ShowStackSplitter, owner, { 0 }, bags, opList)
OUT:write("== stack splitter " .. (ok and "ok" or ("ERR " .. tostring(err))) .. "\n")

local function IsCloseIcon(tex)
    local path = tex["\0v"] and tex["\0v"].Texture
    return type(path) == "string" and path:find("cui-close", 1, true) ~= nil
end

local found = 0
local seen = {}
local function Walk(o, path)
    if type(o) ~= "table" or seen[o] then return end
    seen[o] = true
    if o["\0kind"] == "Button" then
        for _, r in ipairs(o["\0regions"] or {}) do
            if IsCloseIcon(r) then
                found = found + 1
                local rest = r["\0v"].Alpha
                local onEnter, onLeave = o["\0scripts"].OnEnter, o["\0scripts"].OnLeave
                if onEnter then onEnter(o) end
                local hover = r["\0v"].Alpha
                if onLeave then onLeave(o) end
                local left = r["\0v"].Alpha
                local pts = {}
                for _, pt in ipairs(o["\0points"] or {}) do
                    local rel = pt[2]
                    pts[#pts + 1] = tostring(pt[1]) .. "@" .. (type(rel) == "table" and (rel["\0name"] or rel["\0kind"]) or tostring(rel))
                        .. "," .. tostring(pt[3]) .. "," .. tostring(pt[4]) .. "," .. tostring(pt[5])
                end
                OUT:write(string.format("== close %s size=%sx%s alpha rest=%s hover=%s left=%s enter=%s leave=%s click=%s\n", path,
                    tostring(o["\0w"]), tostring(o["\0h"]), tostring(rest), tostring(hover), tostring(left),
                    tostring(onEnter ~= nil), tostring(onLeave ~= nil), tostring(o["\0scripts"].OnClick ~= nil)))
                OUT:write("   points: " .. table.concat(pts, " | ") .. "\n")
                OUT:write("   icon: " .. tostring(r["\0v"].Texture) .. " points=" .. #(r["\0points"] or {}) .. "\n")
            end
        end
    end
    for i, c in ipairs(o["\0children"] or {}) do
        Walk(c, path .. "/" .. (c["\0name"] or (tostring(c["\0kind"]) .. i)))
    end
end

for _, name in ipairs({ "CUI_Bags", "CUI_BagsReagent", "CUI_BankFrame", "CUI_BagsStackSplitFrame" }) do
    local root = rawget(_G, name)
    OUT:write("== root " .. name .. " " .. tostring(root ~= nil) .. "\n")
    if root then Walk(root, name) end
end
OUT:write("== close buttons found " .. found .. "\n")
