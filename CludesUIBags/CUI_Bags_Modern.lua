if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Bags_Modern.lua
--  The Modern bag display (bagDisplayMode = "modern"): the Grid display with
--  no sidebar. A strip of category chips under the header picks what the
--  grid shows (All, or one group or category that holds items), the grid
--  keeps its inline category headers, and the search box is wider.
--  Everything else (slots, sorting, refresh) is the Grid display's own.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local mod = select(2, ...)
local Inner = mod._bagsInternals
-- CludesUIBags.lua or an earlier CUI_Bags_*.lua file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local CUI = CludesUI
local GetAccentRGB, SetBagFont = Inner.GetAccentRGB, Inner.SetBagFont
local SetSelectedCategoryIndex = Inner.SetSelectedCategoryIndex
local SetSelectedGroupName = Inner.SetSelectedGroupName

local selectedCategoryIndex = Inner.selectedCategoryIndex
Inner.categoryIndexSetters[#Inner.categoryIndexSetters + 1] = function(val) selectedCategoryIndex = val end
local selectedGroupName
Inner.groupNameSetters[#Inner.groupNameSetters + 1] = function(val) selectedGroupName = val end

local STRIP_H = 32 -- the chip strip under the header
local CHIP_H = 22
local CHIP_GAP = 6
local CHIP_PAD = 10 -- text inset each side of a chip
local SEARCH_W = 240 -- the search box, wider than the Grid display's

local function Modern() return CUI_Bags and CUI_Bags.IsModernMode and CUI_Bags.IsModernMode() == true end

--- Height the Modern strip adds under the header (0 in every other display).
function mod.ModernStripH() return Modern() and STRIP_H or 0 end

local strip
local chips = {}

local function PaintChip(chip, on)
    local red, green, blue = GetAccentRGB()
    if on then
        chip._fill:SetColorTexture(red, green, blue, 1)
        chip._label:SetTextColor(0.04, 0.05, 0.06, 1)
    elseif chip._hovered then
        chip._fill:SetColorTexture(1, 1, 1, 0.10)
        chip._label:SetTextColor(1, 1, 1, 1)
    else
        chip._fill:SetColorTexture(1, 1, 1, 0.05)
        chip._label:SetTextColor(0.78, 0.80, 0.84, 1)
    end
end

local function ChipSelected(chip)
    if chip._groupName then return selectedGroupName == chip._groupName end
    return not selectedGroupName and selectedCategoryIndex == chip._catIdx
end

local function OnChipClick(chip)
    SetSelectedGroupName(chip._groupName)
    SetSelectedCategoryIndex(chip._catIdx)
    if CUI_Bags._scrollFrame then CUI_Bags._scrollFrame:SetVerticalScroll(0) end
    CUI_Bags:RefreshInventory()
end

local function GetChip(i)
    local chip = chips[i]
    if chip then return chip end
    chip = CreateFrame("Button", nil, strip)
    chip:SetHeight(CHIP_H)
    chip._fill = chip:CreateTexture(nil, "BACKGROUND")
    chip._fill:SetAllPoints()
    if CUI.PanelPP then CUI.PanelPP.CreateBorder(chip, 1, 1, 1, 0.12, 1, "OVERLAY", 7) end
    chip._label = chip:CreateFontString(nil, "OVERLAY")
    SetBagFont(chip._label, 11)
    chip._label:SetPoint("CENTER", 0, 0)
    chip:SetScript("OnEnter", function(self)
        self._hovered = true
        PaintChip(self, ChipSelected(self))
    end)
    chip:SetScript("OnLeave", function(self)
        self._hovered = false
        PaintChip(self, ChipSelected(self))
    end)
    chip:SetScript("OnClick", OnChipClick)
    chips[i] = chip
    return chip
end

local function EnsureStrip()
    if strip or not CUI_Bags.Header then return strip end
    strip = CreateFrame("Frame", nil, CUI_Bags)
    strip:SetPoint("TOPLEFT", CUI_Bags.Header, "BOTTOMLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", CUI_Bags.Header, "BOTTOMRIGHT", 0, 0)
    strip:SetHeight(STRIP_H)
    strip:SetFrameLevel(CUI_Bags.Header:GetFrameLevel())
    local shade = strip:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.25)
    local Pix = CUI.PP
    local px = (Pix and Pix.mult) or 1
    local rule = strip:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(px)
    rule:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)
    rule:SetColorTexture(0.15, 0.15, 0.15, 1)
    -- The wider search box: the header has room once the sidebar is gone
    if CUI_Bags._searchBox then CUI_Bags._searchBox:SetWidth(SEARCH_W) end
    return strip
end

--- Repaints the chip strip: All, then each group or category holding items,
--- in the categories' own order (a group once, by its name). Chips that do
--- not fit on the strip's one row are left off; All always fits.
function mod.BuildModernChips(categoryCounts, totalCount)
    if not Modern() or not EnsureStrip() then return end
    local list = { { catIdx = 0, name = CUI.L("All Items"), count = totalCount } }
    local categories = CUI_CategoryManager and CUI_CategoryManager:GetCategories() or {}
    local seenGroups = {}
    for ci, category in ipairs(categories) do
        if category.groupName then
            if not seenGroups[category.groupName] then
                seenGroups[category.groupName] = true
                local total = 0
                for _, mi in ipairs(CUI_CategoryManager:GetGroupMembers(category.groupName)) do
                    total = total + (categoryCounts and categoryCounts[mi] or 0)
                end
                if total > 0 then
                    list[#list + 1] = {
                        catIdx = 0,
                        groupName = category.groupName,
                        name = category.groupName,
                        count = total,
                    }
                end
            end
        elseif not category.isEquipSet then
            local n = categoryCounts and categoryCounts[ci] or 0
            if n > 0 then list[#list + 1] = { catIdx = ci, name = category.name, count = n } end
        end
    end

    local room = strip:GetWidth() - 2 * CHIP_GAP
    local x = CHIP_GAP
    local shown = 0
    for i, record in ipairs(list) do
        local chip = GetChip(i)
        chip._catIdx = record.catIdx
        chip._groupName = record.groupName
        chip._label:SetText(record.name)
        local w = math.ceil(chip._label:GetStringWidth()) + 2 * CHIP_PAD
        if i > 1 and x + w > room + CHIP_GAP then break end
        chip:SetWidth(w)
        chip:ClearAllPoints()
        chip:SetPoint("LEFT", strip, "LEFT", x, 0)
        PaintChip(chip, ChipSelected(chip))
        chip:Show()
        x = x + w + CHIP_GAP
        shown = i
    end
    for i = shown + 1, #chips do
        chips[i]:Hide()
    end
    strip:Show()
end

Inner.broken = false
