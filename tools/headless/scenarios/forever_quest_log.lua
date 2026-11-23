-- Forever quest log rows (CludesUIBlizzardSkin_QuestLogForever.lua): stand-in
-- QuestScrollFrame pools with a quest row (track checkbox), a header (+/-
-- button) and the quest count box. The gold square goes for a flat one with an
-- accent tick, the +/- turns white and stays white after a toggle, the count
-- box goes flat with white text, and a re-run adds nothing twice.
local ns = CludesUI._ModuleNS and CludesUI._ModuleNS["CludesUIBlizzardSkin"]
local QLF = ns and ns._QuestLogForever
OUT:write("== qlf " .. tostring(QLF ~= nil) .. "\n")
if not QLF then return end
local Skin = ns.WSkin

local function Pool(list)
    return { EnumerateActive = function()
        local i = 0
        return function()
            i = i + 1
            return list[i]
        end
    end }
end

local scroll = CreateFrame("Frame", "QuestScrollFrame", UIParent)
local row = CreateFrame("Button", nil, scroll)
row.Checkbox = CreateFrame("Frame", nil, row)
row.Checkbox:SetSize(14, 14)
local square = row.Checkbox:CreateTexture(nil, "BACKGROUND")
row.Checkbox.CheckMark = row.Checkbox:CreateTexture(nil, "ARTWORK")
local hl = row.Checkbox:CreateTexture(nil, "HIGHLIGHT")
local header = CreateFrame("Button", nil, scroll)
header.CollapseButton = CreateFrame("Button", nil, header)
header.CollapseButton.Icon = header.CollapseButton:CreateTexture(nil, "ARTWORK")
function header.CollapseButton:UpdateCollapsedState(c)
    self.collapsed = c
    self.Icon:SetVertexColor(1, 0.82, 0, 1)
end
scroll.titleFramePool = Pool({ row })
scroll.headerFramePool = Pool({ header })
local count = CreateFrame("Frame", "QuestLogCount", scroll)
count:SetSize(100, 20)
for _, k in ipairs({ "Left", "Middle", "Right" }) do count[k] = count:CreateTexture(nil, "BACKGROUND") end
local countText = count:CreateFontString("QuestLogQuestCount", "ARTWORK")
countText:SetTextColor(1, 0.82, 0)

QLF.Rows()
local function A(t) return string.format("%.2f", t:GetAlpha()) end
OUT:write(("== checkbox square=%s highlight=%s tick=%s\n"):format(A(square), A(hl), A(row.Checkbox.CheckMark)))
SNAP("checkbox", row.Checkbox)
header.CollapseButton:UpdateCollapsedState(true)
OUT:write(("== collapse after toggle: %s\n"):format(table.concat({ header.CollapseButton.Icon:GetVertexColor() }, ",")))
OUT:write(("== count left=%s text=%s\n"):format(A(count.Left), table.concat({ countText:GetTextColor() }, ",")))
local before = select("#", row.Checkbox:GetRegions())
QLF.Rows()
OUT:write(("== regions before/after re-run %d/%d\n"):format(before, select("#", row.Checkbox:GetRegions())))
