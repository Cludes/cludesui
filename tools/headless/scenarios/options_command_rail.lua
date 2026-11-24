-- The options sidebar's Command Rail (CludesUI_Panel.lua): an icon per group
-- down the left, and the list beside it shows only the picked group. Opening
-- picks the open module's group; a rail click switches; picking a module
-- elsewhere (a search) moves the rail; the setting off brings back the list.
local CUI = rawget(_G, "CludesUI")
CUI:Show()
HARNESS_ADVANCE(0.2)
local child = CUI._addonScrollChild
local function List(label)
    local rows = {}
    for _, kid in ipairs({ child:GetChildren() }) do
        if kid:IsShown() and kid._label then
            local _, _, _, x, y = kid:GetPoint(1)
            rows[#rows + 1] = { y = -(y or 0), text = (kid._isGroup and "# " or "") .. tostring(kid._label:GetText()) }
        end
    end
    table.sort(rows, function(a, b) return a.y < b.y end)
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = r.text end
    local scroller = CUI._addonScrollFrame
    local _, _, _, sx = scroller:GetPoint(1)
    OUT:write(("== %s: list x=%s w=%s | %s\n"):format(label, tostring(sx), tostring(scroller:GetWidth()), table.concat(out, ", ")))
end
List("open")
SNAP("rail sidebar", CUI._sidebar)
local NS = CUI._NS
-- The rail: a full-height 60 wide column; section squares hang from its top,
-- the Global Settings / Profiles / Patch Notes / Layout Mode squares from its foot.
local rail
for _, kid in ipairs({ CUI._sidebar:GetChildren() }) do
    if kid:GetWidth() == 60 then rail = kid end
end
local sections, foot = {}, {}
for _, kid in ipairs(rail and { rail:GetChildren() } or {}) do
    local point = kid:GetPoint(1)
    if point == "TOP" then sections[#sections + 1] = kid elseif point == "BOTTOM" then foot[#foot + 1] = kid end
end
OUT:write(("== rail: %d sections, %d foot squares, fixed Layout Mode row shown %s\n"):format(#sections, #foot,
    tostring(CUI._unlockSidebarBtn and CUI._unlockSidebarBtn:IsShown())))
if sections[#sections] then sections[#sections]:GetScript("OnClick")(sections[#sections]) end
List("last group")
CUI:SelectModule("CludesUIActionBars")
List("search to action bars")
CludesUIDB.sidebarRail = false
CUI.RefreshSidebarLayout()
List("rail off")
OUT:write("== rail off: rail shown " .. tostring(rail and rail:IsShown()) .. ", Layout Mode row shown " .. tostring(CUI._unlockSidebarBtn and CUI._unlockSidebarBtn:IsShown()) .. "\n")
-- Back on: Core Settings shows its own pages in the list; a module shows its pages under its row.
CludesUIDB.sidebarRail = nil
CUI:SelectModule("_CUIGlobal")
CUI.RefreshSidebarLayout()
List("core settings")
CUI:SelectModule("CludesUIActionBars")
List("action bars pages")
-- Two-line rows and the section status under the list.
local function Status()
    local out = {}
    for _, kid in ipairs({ CUI._sidebar:GetChildren() }) do
        for _, f in ipairs({ kid:GetChildren() }) do
            for _, r in ipairs({ f:GetChildren() }) do
                if r.name and r.cpu and r:IsShown() then out[#out + 1] = r.name:GetText() .. "=" .. r.cpu:GetText() end
            end
        end
    end
    return table.concat(out, ", ")
end
local first = CUI._addonScrollChild and select(2, CUI._addonScrollChild:GetChildren())
OUT:write("== status: " .. Status() .. "\n")
for _, kid in ipairs({ CUI._addonScrollChild:GetChildren() }) do
    if kid._desc and kid:IsShown() then OUT:write("== row: " .. tostring(kid._label:GetText()) .. " | " .. tostring(kid._desc:GetText()) .. "\n") break end
end
-- The tabs hide while the rail lists the pages.
local function TabsShown()
    local n = 0
    for _, b in ipairs(CUI._tabBar._tabButtons) do if b:IsShown() then n = n + 1 end end
    return n .. " of " .. #CUI._tabBar._tabButtons
end
OUT:write("== tabs shown (rail on): " .. TabsShown() .. "\n")
CludesUIDB.sidebarRail = false
CUI.RefreshSidebarLayout()
OUT:write("== tabs shown (rail off): " .. TabsShown() .. "\n")
-- Window Skins and Chat list only their own pages (no rows that open another
-- module); Core Settings clicked while already open (after browsing a section)
-- shows its pages.
CludesUIDB.sidebarRail = nil
CUI.RefreshSidebarLayout()
CUI:SelectModule("CludesUIBlizzardSkin")
List("window skins pages")
CUI:SelectModule("CludesUIChat")
List("chat pages")
CUI:SelectModule("_CUIGlobal")
sections[2]:GetScript("OnClick")(sections[2])
List("browsing a section")
sections[1]:GetScript("OnClick")(sections[1])
List("core settings clicked again")
-- A Section Status row opens its module.
sections[2]:GetScript("OnClick")(sections[2])
for _, kid in ipairs({ CUI._sidebar:GetChildren() }) do
    for _, f in ipairs({ kid:GetChildren() }) do
        for _, r in ipairs({ f:GetChildren() }) do
            if r.name and r.cpu and r:IsShown() and r.name:GetText() == "Nameplates" then r:GetScript("OnClick")(r) end
        end
    end
end
List("after status click")
