-- The bank in the Modern display (CludesUIBags_Bank.lua): the bags profile
-- switched to "modern" (the display latch reset, as a /reload would), a
-- stand-in bank with one bought tab of 48 slots (3 items) and a tab still to
-- buy, BANKFRAME_OPENED fired. Snapshots the window and lists what shows:
-- the sidebar (old) or the chip strip (new), each entry's text and count,
-- and where the slot grid starts. Then clicks OneBank and Tab 1 and lists the
-- selection after each, and puts the display back to Grid to show the
-- sidebar returns.
local ns = CludesUI._ModuleNS and CludesUI._ModuleNS["CludesUIBags"]
local bags = rawget(_G, "CUI_Bags")
local bank = rawget(_G, "CUI_BankFrame")
if not (ns and bags and bank) then
    OUT:write("== no bags/bank\n")
    return
end
local p = ns._bagsInternals.BP()
local function SetMode(mode)
    p.bagDisplayMode = mode
    local fn = bags.IsListMode
    for i = 1, 20 do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == "_listMode" then debug.setupvalue(fn, i, nil) end
    end
    bags.IsListMode()
end
-- The fake client's item buttons lack their template's textures, which the
-- shared skinning reads; let it pass so the bank's layout can be seen.
for name, fn in pairs(ns) do
    if type(fn) == "function" and (name:find("^Skin") or name:find("^SetSlot")) then
        ns[name] = function(...) pcall(fn, ...) end
    end
end
SetMode("modern")
OUT:write("== modern: " .. tostring(bags.IsModernMode()) .. "\n")

local tabBag = Enum.BagIndex.CharacterBankTab_1
rawset(C_Bank, "FetchPurchasedBankTabData", function(kind)
    if kind == Enum.BankType.Character then return { { name = "Tab 1", icon = 133652, depositFlags = 0 } } end
    return {}
end)
rawset(C_Bank, "CanPurchaseBankTab", function(kind) return kind == Enum.BankType.Character end)
rawset(C_Bank, "HasMaxBankTabs", function() return false end)
local items = { [1] = 2840, [2] = 2854, [5] = 3470 }
local realSlots, realInfo = C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo
rawset(C_Container, "GetContainerNumSlots", function(bag)
    if bag == tabBag then return 48 end
    return realSlots(bag)
end)
rawset(C_Container, "GetContainerItemInfo", function(bag, slot)
    if bag == tabBag then
        local id = items[slot]
        return id and { itemID = id, stackCount = 1, iconFileID = 134400, hyperlink = "item:" .. id, quality = 1 } or nil
    end
    return realInfo(bag, slot)
end)

HARNESS_FIRE_EVENT("BANKFRAME_OPENED")
HARNESS_ADVANCE(0.5)
bags:Hide() -- the bank opens the bags too; their grid is not under test
bank:RefreshBank()
HARNESS_ADVANCE(0.2)

local function Entries(label)
    local strip = rawget(bank, "_modernStrip")
    local where = {}
    local function Walk(frame, depth)
        for _, child in ipairs(frame["\0children"] or {}) do
            if child["\0kind"] == "Button" and child:IsVisible() and rawget(child, "_entryName") then
                where[#where + 1] = ("%s[%s]%s%s"):format(
                    tostring(child._entryName),
                    tostring(child._count:IsShown() and child._count:GetText() or ""),
                    child._isSelected and "*" or "",
                    (strip and child:GetParent() == strip) and " chip" or " row"
                )
            elseif depth < 4 then
                Walk(child, depth + 1)
            end
        end
    end
    Walk(bank, 0)
    local _, _, _, x, y = bank._scrollFrame:GetPoint(1)
    OUT:write(
        ("== %s: shown=%s strip=%s grid at x=%s y=%s width=%s\n   %s\n"):format(
            label,
            tostring(bank:IsShown()),
            tostring(strip and strip:IsShown()),
            tostring(x),
            tostring(y),
            tostring(bank:GetWidth()),
            table.concat(where, "; ")
        )
    )
end
Entries("opened")
do
    -- The fake client's SetParent leaves children lists alone: walk them all
    -- and ask each overlay for its parent.
    local strip, overlays, visible = rawget(bank, "_modernStrip"), 0, 0
    local function Walk(frame, depth)
        for _, child in ipairs(frame["\0children"] or {}) do
            local visual = rawget(child, "_visualBtn")
            if visual and child:IsShown() then
                if strip and child:GetParent() == strip then overlays = overlays + 1 end
                if child:IsVisible() and visual:IsVisible() then visible = visible + 1 end
            end
            if depth < 4 then Walk(child, depth + 1) end
        end
    end
    Walk(bank, 0)
    OUT:write(("== buy overlays: in the strip %d, visible over a visible entry %d\n"):format(overlays, visible))
end
SNAP("bank", bank)

local function Click(name)
    local function Find(frame, depth)
        for _, child in ipairs(frame["\0children"] or {}) do
            if child["\0kind"] == "Button" and child:IsVisible() and rawget(child, "_entryName") == name then return child end
            if depth < 4 then
                local found = Find(child, depth + 1)
                if found then return found end
            end
        end
    end
    local button = Find(bank, 0)
    if button then
        button["\0scripts"].OnClick(button, "LeftButton")
        HARNESS_ADVANCE(0.2)
    end
    Entries("clicked " .. name .. (button and "" or " (not found)"))
end
Click("OneBank")
Click("Tab 1")

SetMode("grid")
bank:RefreshBank()
HARNESS_ADVANCE(0.2)
Entries("back to grid")
