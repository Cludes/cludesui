if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_ClassicTalents.lua  (WoW Forever only)
--  The vanilla talent window, drawn with the client's own art: one tree a
--  tab, talents on a grid with their ranks and prerequisite arrows. Points
--  are staged with a click and spent with Learn, as the game's own window
--  does. The talents key and the micro menu's Talents button open it in place
--  of the Talents & Spellbook window. The QoL Shifter moves it like the game's
--  windows. Active spec only.
-------------------------------------------------------------------------------
local _, module = ...

local SIZE = 32 -- talent button
local STEP = 63 -- between talents on the grid
local LEFT, TOP = 35, 20 -- first talent, inside the tree area
local VIEW_W, VIEW_H = 296, 332
local GAP = 8 -- beside the spellbook, past the tabs on its right side
local ART = "Interface\\TalentFrame\\"
local QUEUE_KEY = "ClassicTalentsBind"
local TOGGLE_NAME = "CUI_ClassicTalentsToggle"

-- Tree backgrounds by class, in tree order.
local BACKGROUNDS = {
    DRUID = { "DruidBalance", "DruidFeralCombat", "DruidRestoration" },
    HUNTER = { "HunterBeastMastery", "HunterMarksmanship", "HunterSurvival" },
    MAGE = { "MageArcane", "MageFire", "MageFrost" },
    PALADIN = { "PaladinHoly", "PaladinProtection", "PaladinCombat" },
    PRIEST = { "PriestDiscipline", "PriestHoly", "PriestShadow" },
    ROGUE = { "RogueAssassination", "RogueCombat", "RogueSubtlety" },
    SHAMAN = { "ShamanElementalCombat", "ShamanEnhancement", "ShamanRestoration" },
    WARLOCK = { "WarlockCurses", "WarlockSummoning", "WarlockDestruction" },
    WARRIOR = { "WarriorArms", "WarriorFury", "WarriorProtection" },
}

-- Pieces of the branch and arrow sheets: left, right, top of the lit row. The
-- unlit row sits half a sheet lower.
local BRANCH_DOWN = { 0, 0.125, 0 }
local BRANCH_RIGHT = { 0.2578125, 0.3828125, 0 }
local ARROW_TOP = { 0, 0.5, 0 }
local ARROW_RIGHT = { 1, 0.5, 0 }
local ARROW_LEFT = { 0.5, 1, 0 }

-- Settings live in CludesUIDB.classicTalents; unset keys read these.
local F = module.Feature("classicTalents", { enabled = false })

local window, toggle
local microLayer -- the click layer over the micro menu's Talents button (see Setup)
local route -- CUI_TalentsRoute (see Setup)
local trees = {} -- { groupID, name, nodes = { nodeID, ... } } in tree order
local tree = 1 -- the selected tree
local staged = {} -- [nodeID] = points staged here and not yet learned
local configID, treeID
local unspent = 0 -- talent points left to stage
local boundKeys -- the keys the toggle holds, space separated
local queued -- a repaint is due next frame

-------------------------------------------------------------------------------
--  Talent data (the trees and their grid: CludesUI.ForeverTalentTrees and
--  CludesUI.TalentTreeGrid, shared with the Cooldown Manager's Talent
--  Conditions popup)
-------------------------------------------------------------------------------
-- The trees whose own name is too long for a tab, by trait group ID.
local function ShortName(groupID)
    if groupID == 11326 then return CludesUI.L("Elemental") end -- Elemental Combat
    if groupID == 11347 then return CludesUI.L("Feral") end -- Feral Combat
    if groupID == 11622 then return CludesUI.L("Shadow") end -- Shadow Magic
end

local function ReadTrees()
    wipe(trees)
    local entries
    configID, treeID, entries = CludesUI.ForeverTalentTrees()
    if not entries then return end
    for index, t in ipairs(entries) do
        t.name = ShortName(t.groupID) or t.name
        trees[index] = t
    end
    if tree > #trees then tree = 1 end
end

-- Each talent's column and row (from 0) in its tree, from the node positions.
local function Grid(nodes) return CludesUI.TalentTreeGrid(configID, nodes) end

local function SpellOf(details)
    local entryID = details.activeEntry and details.activeEntry.entryID or details.entryIDs[1]
    local record = entryID and C_Traits.GetEntryInfo(configID, entryID)
    local def = record and record.definitionID and C_Traits.GetDefinitionInfo(record.definitionID)
    if not def then return end
    local iconTex = def.overrideIcon
    if not iconTex or iconTex == 0 then iconTex = def.spellID and C_Spell.GetSpellTexture(def.spellID) end
    return def.spellID, iconTex
end

-------------------------------------------------------------------------------
--  Talent buttons
-------------------------------------------------------------------------------
local Paint, QueuePaint

local function TalentEnter(b)
    if not b.spellID then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(b.spellID)
    GameTooltip:Show()
end

local function TalentLeave() GameTooltip:Hide() end

-- Left click stages a point; right click takes back one staged here.
local function TalentClick(b, btnFrame)
    local nodeID = b.nodeID
    if not nodeID then return end
    if btnFrame == "RightButton" then
        if (staged[nodeID] or 0) > 0 and C_Traits.RefundRank(configID, nodeID) then
            staged[nodeID] = staged[nodeID] - 1
        end
    elseif C_Traits.PurchaseRank(configID, nodeID) then
        staged[nodeID] = (staged[nodeID] or 0) + 1
    end
    QueuePaint()
end

local function NewTalent(hostFrame)
    local widget = CreateFrame("Button", nil, hostFrame)
    widget:SetSize(SIZE, SIZE)
    widget:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    widget.icon = widget:CreateTexture(nil, "ARTWORK")
    widget.icon:SetAllPoints()
    widget.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon's own frame
    widget.slot = widget:CreateTexture(nil, "BACKGROUND")
    widget.slot:SetTexture("Interface\\Buttons\\UI-EmptySlot-White")
    widget.slot:SetSize(64, 64)
    widget.slot:SetPoint("CENTER")
    widget.rankBorder = widget:CreateTexture(nil, "OVERLAY")
    widget.rankBorder:SetTexture(ART .. "TalentFrame-RankBorder")
    widget.rankBorder:SetSize(32, 32)
    widget.rankBorder:SetPoint("CENTER", widget, "BOTTOMRIGHT")
    widget.rank = widget:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    widget.rank:SetPoint("CENTER", widget.rankBorder)
    widget:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    widget:SetScript("OnEnter", TalentEnter)
    widget:SetScript("OnLeave", TalentLeave)
    widget:SetScript("OnClick", TalentClick)
    return widget
end

-- Gold when full, green while it holds points or can take the first one, else
-- grey with no rank.
local function FillTalent(widget, nodeID, cell)
    local details = cell.info
    local spellId, iconTex = SpellOf(details)
    widget.nodeID, widget.spellID = nodeID, spellId
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", LEFT + cell.col * STEP, -(TOP + cell.row * STEP))
    widget.icon:SetTexture(iconTex)
    local rank = details.activeRank
    local open = rank > 0 or (unspent > 0 and details.canPurchaseRank)
    widget.icon:SetDesaturated(not open)
    if rank >= details.maxRanks then
        widget.slot:SetVertexColor(1, 0.82, 0)
        widget.rank:SetTextColor(1, 0.82, 0)
    elseif open then
        widget.slot:SetVertexColor(0.1, 1, 0.1)
        widget.rank:SetTextColor(0.1, 1, 0.1)
    else
        widget.slot:SetVertexColor(0.5, 0.5, 0.5)
    end
    widget.rank:SetText(rank)
    widget.rank:SetShown(open)
    widget.rankBorder:SetShown(open)
    widget:Show()
end

-- One piece of a sheet: its lit row, or the unlit one half a sheet lower.
local function Piece(pool, num, hostFrame, sheet, coords, lit)
    local texture = pool[num]
    if not texture then
        texture = hostFrame:CreateTexture(nil, "ARTWORK")
        texture:SetTexture(ART .. sheet)
        pool[num] = texture
    end
    local topY = coords[3] + (lit and 0 or 0.5)
    texture:SetTexCoord(coords[1], coords[2], topY, topY + 0.5)
    texture:ClearAllPoints()
    texture:Show()
    return texture
end

-- A line and an arrow from a talent to the one it unlocks, when the two share
-- a column or a row.
local function Link(num, from, to, lit)
    local posX, posY = LEFT + from.col * STEP, -(TOP + from.row * STEP)
    if from.col == to.col and to.row > from.row then
        local line = Piece(window.lines, num, window.canvas, "UI-TalentBranches", BRANCH_DOWN, lit)
        line:SetSize(SIZE, (to.row - from.row) * STEP - SIZE)
        line:SetPoint("TOPLEFT", posX, posY - SIZE)
        local arrow = Piece(window.arrows, num, window.above, "UI-TalentArrows", ARROW_TOP, lit)
        arrow:SetSize(SIZE, SIZE)
        arrow:SetPoint("TOPLEFT", posX, posY - (to.row - from.row) * STEP + SIZE / 2)
    elseif from.row == to.row and to.col ~= from.col then
        local right = to.col > from.col
        local span = math.abs(to.col - from.col) * STEP - SIZE
        local line = Piece(window.lines, num, window.canvas, "UI-TalentBranches", BRANCH_RIGHT, lit)
        line:SetSize(span, SIZE)
        line:SetPoint("TOPLEFT", right and posX + SIZE or posX - span, posY)
        local arrow = Piece(
            window.arrows,
            num,
            window.above,
            "UI-TalentArrows",
            right and ARROW_RIGHT or ARROW_LEFT,
            lit
        )
        arrow:SetSize(SIZE, SIZE)
        arrow:SetPoint("TOPLEFT", right and posX + span + SIZE / 2 or posX - span - SIZE / 2, posY)
    else
        return false
    end
    return true
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local function HasStaged() return next(staged) ~= nil end

local function PaintBackground()
    local _, class = UnitClass("player")
    local name = BACKGROUNDS[class] and BACKGROUNDS[class][tree]
    for corner, texture in pairs(window.bg) do
        texture:SetTexture(name and ART .. name .. "-" .. corner or nil)
    end
end

Paint = function()
    local tbl = trees[tree]
    local currency = treeID and C_Traits.GetTreeCurrencyInfo(configID, treeID, false)[1]
    unspent = currency and currency.quantity or 0
    local cells, rowList = Grid(tbl and tbl.nodes or {})
    local used = 0
    for nodeID, cell in pairs(cells) do
        used = used + 1
        local b = window.talents[used]
        if not b then
            b = NewTalent(window.canvas)
            window.talents[used] = b
        end
        FillTalent(b, nodeID, cell)
    end
    for index = used + 1, #window.talents do
        window.talents[index]:Hide()
    end

    local links = 0
    for _, cell in pairs(cells) do
        for _, edge in ipairs(cell.info.visibleEdges) do
            local to = cells[edge.targetNode]
            if to and Link(links + 1, cell, to, edge.isActive) then links = links + 1 end
        end
    end
    for index = links + 1, #window.lines do
        window.lines[index]:Hide()
    end
    for index = links + 1, #window.arrows do
        window.arrows[index]:Hide()
    end
    window.canvas:SetSize(VIEW_W, math.max(VIEW_H, TOP * 2 + (rowList - 1) * STEP + SIZE))

    for index, tab in ipairs(window.tabs) do
        local payload = trees[index]
        tab:SetShown(payload ~= nil)
        if payload then
            tab.text:SetText(payload.name)
            local on = index == tree
            for _, texture in ipairs(tab.active) do
                texture:SetShown(on)
            end
            for _, texture in ipairs(tab.inactive) do
                texture:SetShown(not on)
            end
            local color = on and HIGHLIGHT_FONT_COLOR or NORMAL_FONT_COLOR
            tab.text:SetTextColor(color.r, color.g, color.b)
            tab.text:SetPoint("CENTER", 0, on and 4 or 2)
        end
    end
    local set = tbl and C_Traits.GetGroupCurrencyInfo(configID, { tbl.groupID })[1]
    local spent = set and set.currencyInfos[1] and set.currencyInfos[1].spent or 0
    -- The numbers are white beside their gold labels.
    local white = HIGHLIGHT_FONT_COLOR
    window.spent:SetText(
        tbl
                and CludesUI.Lf(
                    "Points spent in %1$s Talents: %2$s",
                    tbl.name,
                    white:WrapTextInColorCode(spent)
                )
            or ""
    )
    window.points:SetText(CludesUI.Lf("Talent Points: %s", white:WrapTextInColorCode(unspent)))
    window.learn:SetEnabled(HasStaged())
    PaintBackground()
end

local function Refresh()
    ReadTrees()
    Paint()
end

-- One repaint for a click and the burst of events it sets off.
local function Repaint()
    queued = nil
    if window:IsShown() then Refresh() end
end

QueuePaint = function()
    if queued then return end
    queued = true
    C_Timer.After(0, Repaint)
end

local function Rollback()
    if HasStaged() and configID then C_Traits.RollbackConfig(configID) end
    wipe(staged)
end

-- The loadout the game's own window has selected for this spec: a commit saves
-- into it too, as that window's does. None (the default loadout) commits the
-- active config alone. Never the active config's own ID: it is no saved
-- loadout, so the save half of the commit failed with an error while the
-- points were kept.
local function SavedConfigID()
    local specInfo = C_SpecializationInfo.GetSpecialization()
    local specID = specInfo and C_SpecializationInfo.GetSpecializationInfo(specInfo)
    if not specID then return nil end
    local saved = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
    local consts = Constants and Constants.TraitConsts
    if saved == configID or (consts and saved == consts.STARTER_BUILD_TRAIT_CONFIG_ID) then return nil end
    return saved
end

-- A refused commit (combat, an encounter) keeps the staged points, so closing
-- the window still rolls them back.
local function Learn()
    if not HasStaged() then return end
    if C_ClassTalents.CommitConfig(SavedConfigID()) then wipe(staged) end
end

local EVENTS = {
    "TRAIT_CONFIG_UPDATED",
    "TRAIT_NODE_CHANGED",
    "TRAIT_TREE_CURRENCY_INFO_UPDATED",
    "ACTIVE_COMBAT_CONFIG_CHANGED",
}

-- Listens only while open. Closing drops the points staged here.
local function WinShown(frame)
    for _, evt in ipairs(EVENTS) do
        frame:RegisterEvent(evt)
    end
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    Refresh()
end

local function WinHidden(frame)
    frame:UnregisterAllEvents()
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    Rollback()
end

-- A tab's art in three pieces (20 px ends, a stretched middle). The selected
-- tab's art is 3 px taller and starts 5 px higher, so it joins the window.
local TAB_ENDS = 0.15625
local function TabArt(tab, file, height, rise, bottom)
    local leftX = tab:CreateTexture(nil, "BACKGROUND")
    leftX:SetTexture("Interface\\PaperDollInfoFrame\\" .. file)
    leftX:SetTexCoord(0, TAB_ENDS, 0, bottom)
    leftX:SetSize(20, height)
    leftX:SetPoint("TOPLEFT", 0, rise)
    local right = tab:CreateTexture(nil, "BACKGROUND")
    right:SetTexture("Interface\\PaperDollInfoFrame\\" .. file)
    right:SetTexCoord(1 - TAB_ENDS, 1, 0, bottom)
    right:SetSize(20, height)
    right:SetPoint("TOPRIGHT", 0, rise)
    local middle = tab:CreateTexture(nil, "BACKGROUND")
    middle:SetTexture("Interface\\PaperDollInfoFrame\\" .. file)
    middle:SetTexCoord(TAB_ENDS, 1 - TAB_ENDS, 0, bottom)
    middle:SetPoint("TOPLEFT", leftX, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    return { leftX, middle, right }
end

local function NewTab(index)
    local tab = CreateFrame("Button", nil, window)
    tab:SetSize(108, 32)
    tab:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 12 + (index - 1) * 104, 78)
    tab.inactive = TabArt(tab, "UI-Character-InActiveTab", 32, 0, 1)
    tab.active = TabArt(tab, "UI-Character-ActiveTab", 35, 5, 0.546875)
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tab.text:SetPoint("CENTER", 0, 2)
    tab.text:SetWidth(92)
    tab.text:SetWordWrap(false)
    tab:SetScript("OnClick", function()
        if index == tree then return end
        tree = index
        window.scroll:SetVerticalScroll(0)
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        Paint()
    end)
    return tab
end

local function Build()
    if window then return end
    window = CreateFrame("Frame", "CUI_ClassicTalents", UIParent)
    window:Hide()
    window:SetSize(384, 512)
    window:SetFrameStrata("MEDIUM")
    window:SetToplevel(true)
    window:EnableMouse(true)
    window:SetHitRectInsets(0, 30, 0, 70)

    local portrait = window:CreateTexture(nil, "BACKGROUND")
    portrait:SetSize(60, 60)
    portrait:SetPoint("TOPLEFT", 7, -6)
    window.portrait = portrait
    for _, part in ipairs({
        { "Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft", "TOPLEFT", 256 },
        { "Interface\\PaperDollInfoFrame\\UI-Character-General-TopRight", "TOPRIGHT", 128 },
        { ART .. "UI-TalentFrame-BotLeft", "BOTTOMLEFT", 256 },
        { ART .. "UI-TalentFrame-BotRight", "BOTTOMRIGHT", 128 },
    }) do
        local texture = window:CreateTexture(nil, "ARTWORK")
        texture:SetTexture(part[1])
        texture:SetSize(part[3], 256)
        texture:SetPoint(part[2])
    end
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER", 6, 230)
    title:SetText(TALENTS)

    -- The tree's background, over the frame art and behind the scrolling
    -- talents: 320 x 331 in four pieces.
    window.bg = {}
    for _, part in ipairs({
        { "TopLeft", 0, 0, 256, 256 },
        { "TopRight", 256, 0, 64, 256 },
        { "BottomLeft", 0, -256, 256, 75 },
        { "BottomRight", 256, -256, 64, 75 },
    }) do
        local texture = window:CreateTexture(nil, "ARTWORK", nil, 1)
        texture:SetSize(part[4], part[5])
        texture:SetPoint("TOPLEFT", 23 + part[2], -77 + part[3])
        if part[5] < 256 then texture:SetTexCoord(0, 1, 0, part[5] / 128) end
        window.bg[part[1]] = texture
    end

    window.scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
    window.scroll:SetSize(VIEW_W, VIEW_H)
    window.scroll:SetPoint("TOPRIGHT", -65, -77)
    window.canvas = CreateFrame("Frame", nil, window.scroll)
    window.canvas:SetSize(VIEW_W, VIEW_H)
    window.scroll:SetScrollChild(window.canvas)
    -- Arrowheads lie over the talent they point at.
    window.above = CreateFrame("Frame", nil, window.canvas)
    window.above:SetAllPoints()
    window.above:SetFrameLevel(window.canvas:GetFrameLevel() + 5)

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("CENTER", window, "TOPRIGHT", -44, -25)

    -- The bordered bar the points-spent line sits in: the input box border,
    -- two 8 px ends and a stretched middle.
    local barFrame = {}
    for index, part in ipairs({ { 0, 0.0625 }, { 0.0625, 0.9375 }, { 0.9375, 1 } }) do
        barFrame[index] = window:CreateTexture(nil, "ARTWORK", nil, 2)
        barFrame[index]:SetTexture("Interface\\Common\\Common-Input-Border")
        barFrame[index]:SetTexCoord(part[1], part[2], 0, 0.625)
    end
    barFrame[1]:SetSize(8, 20)
    barFrame[1]:SetPoint("TOPLEFT", window, "TOP", -117, -48)
    barFrame[3]:SetSize(8, 20)
    barFrame[3]:SetPoint("TOPRIGHT", window, "TOP", 129, -48)
    barFrame[2]:SetPoint("TOPLEFT", barFrame[1], "TOPRIGHT")
    barFrame[2]:SetPoint("BOTTOMRIGHT", barFrame[3], "BOTTOMLEFT")
    window.spent = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    window.spent:SetPoint("CENTER", barFrame[2])
    window.points = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    window.learn = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    window.learn:SetSize(86, 20)
    window.learn:SetPoint("BOTTOMRIGHT", -40, 81)
    window.learn:SetText(LEARN)
    window.learn:SetScript("OnClick", Learn)
    window.points:SetPoint("RIGHT", window.learn, "LEFT", -10, 0)

    window.tabs, window.talents, window.lines, window.arrows = {}, {}, {}, {}
    for index = 1, 3 do
        window.tabs[index] = NewTab(index)
    end

    window:SetScript("OnShow", WinShown)
    window:SetScript("OnHide", WinHidden)
    window:SetScript("OnEvent", function(_, evt)
        -- A learn or a change made elsewhere: what was staged here is gone.
        if evt == "TRAIT_CONFIG_UPDATED" or evt == "ACTIVE_COMBAT_CONFIG_CHANGED" then wipe(staged) end
        QueuePaint()
    end)
    CludesUI.RegisterEscapeClose(window, { cursor = true })
    if CludesUI._ShifterAdopt then CludesUI._ShifterAdopt("CUI_ClassicTalents") end
end

-- Beside the Classic Spellbook while that is open and in its place while it is
-- closed, hanging from the book (the Shifter may have moved it); at the left of
-- the screen without one. A spot saved in the Shifter wins over all of these.
local function Place()
    if not window then return end
    local book = CUI_ClassicSpellbook
    window:ClearAllPoints()
    if not book then
        window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
    elseif book:IsShown() then
        window:SetPoint("TOPLEFT", book, "TOPRIGHT", GAP, 0)
    else
        window:SetPoint("TOPLEFT", book, "TOPLEFT")
    end
end

local function Close()
    if window then window:Hide() end
end

local function Toggle()
    Build()
    if window:IsShown() then
        window:Hide()
    else
        SetPortraitTexture(window.portrait, "player")
        Place()
        window:Show()
    end
end

-------------------------------------------------------------------------------
--  Setup
-------------------------------------------------------------------------------
-- The micro menu's Talents button opens the window too, through a click layer
-- of ours over it (module.MicroClickLayer), in combat as well: the window is a
-- plain frame. Our other panels that open the talents (the Data Bars micro
-- menu block, Quickdraw) click CUI_TalentsRoute: a secure click that goes to
-- the window's toggle while the feature is on and to the game's Talents micro
-- button otherwise. Made at load, out of combat; aimed by Bind.
if not InCombatLockdown() then
    route = CreateFrame("Button", "CUI_TalentsRoute", UIParent, "SecureActionButtonTemplate")
    route:SetAttribute("type", "click")
    route:SetAttribute("useOnKeyDown", false)
    route:SetAttribute("clickbutton", _G.TalentMicroButton)
end

-- The talents key clicks the toggle while the feature is on. Setting an
-- override fires UPDATE_BINDINGS itself, so unchanged keys are left alone.
local function Bind()
    if InCombatLockdown() then
        CludesUI.CombatQueue.Defer(QUEUE_KEY, Bind)
        return
    end
    local on = F.Enabled()
    if on and not toggle then
        toggle = CreateFrame("Button", TOGGLE_NAME, UIParent)
        toggle:SetScript("OnClick", Toggle)
        toggle:SetScript("OnEvent", Bind)
    end
    local target = on and toggle or _G.TalentMicroButton
    if route and route:GetAttribute("clickbutton") ~= target then
        route:SetAttribute("clickbutton", target)
    end
    if not toggle then return end
    if on then
        toggle:RegisterEvent("UPDATE_BINDINGS")
        if not microLayer then microLayer = module.MicroClickLayer("TalentMicroButton", Toggle) end
    else
        toggle:UnregisterAllEvents()
        if window then window:Hide() end
    end
    if microLayer then microLayer:SetShown(on) end
    local keyList = on and table.concat({ GetBindingKey("TOGGLETALENTS") }, " ") or ""
    if keyList == boundKeys then return end
    boundKeys = keyList
    ClearOverrideBindings(toggle)
    for key in keyList:gmatch("%S+") do
        SetOverrideBindingClick(toggle, true, key, TOGGLE_NAME)
    end
end

-- Options-page entry points.
CludesUI._ClassicTalents = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Bind,
    Place = Place,
    Close = Close,
}

F.Start(Bind)
