if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_ClassicSpellbook.lua  (WoW Forever only)
--  The vanilla spellbook, drawn with the client's own art: school tabs down
--  the right side and twelve spells a page, plus the game's search box and
--  spellbook options. The spellbook key and the micro menu's Spellbook button
--  open it in place of the Talents & Spellbook window (the button only out of
--  combat: in combat the game opens its own window). The window and its
--  buttons are protected and its pages are turned by restricted snippets, so
--  the key, the tabs and the page arrows work in combat. A search or an
--  option changed in combat applies when the fight ends: only code that runs
--  out of combat can hand the snippets a new list of spells. The QoL Shifter
--  moves it like the game's windows.
-------------------------------------------------------------------------------
local _, module = ...

local PER_PAGE = 12
local ROWS = PER_PAGE / 2
local BANK = Enum.SpellBookSpellBank.Player
local ART = "Interface\\Spellbook\\"
local QUEUE_KEY = "ClassicSpellbook"
local TOGGLE_NAME = "CUI_ClassicSpellbookToggle"
local ESCAPE_NAME = "CUI_ClassicSpellbookEscape"

-- Settings live in CludesUIDB.classicSpellbook; unset keys read these.
local F = module.Feature("classicSpellbook", { enabled = false })

local bookFrame, toggle, eventList
local lineList = {} -- shown skill lines: { name, icon, slots = { spellbook slot, ... } }
local line = 1 -- the selected skill line
local pages = {} -- page per skill line (0: the search results), as the snippets last reported
local newSearch -- the search text changed: its results open on page 1
local searchText -- lowercase search text; nil when not searching
local stale -- the spellbook changed while the book was closed
local boundKeys -- the keys the toggle holds, space separated
local found = { slots = {} } -- the search results, shown as a line of their own
local pushed -- the snippet text the snippets last ran

-------------------------------------------------------------------------------
--  Spell data
-------------------------------------------------------------------------------
-- A search matches a spell's name, rank text or description.
local function Matches(slotBtn)
    local spellInfo = C_SpellBook.GetSpellBookItemInfo(slotBtn, BANK)
    if not spellInfo then
        return false
    end
    if spellInfo.name:lower():find(searchText, 1, true) then
        return true
    end
    if spellInfo.subName and spellInfo.subName:lower():find(searchText, 1, true) then
        return true
    end
    local label = C_SpellBook.GetSpellBookItemDescription(slotBtn, BANK)
    return label ~= nil and label:lower():find(searchText, 1, true) ~= nil
end

-- Every learned spell of the player's own skill lines. The game's spellbook
-- options (Hide Passives, Show All Spell Ranks) apply, except to a search,
-- which looks through every spell as the game's own does.
local function ReadLines()
    wipe(lineList)
    wipe(found.slots)
    local allRanks = searchText or GetCVarBool("ShowAllSpellRanks")
    local passives = searchText or not GetCVarBool("spellBookHidePassives")
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local spellInfo = C_SpellBook.GetSpellBookSkillLineInfo(i)
        if spellInfo and not spellInfo.shouldHide and not spellInfo.offSpecID then
            local slotList = {}
            for slotBtn = spellInfo.itemIndexOffset + 1, spellInfo.itemIndexOffset + spellInfo.numSpellBookItems do
                if
                    C_SpellBook.GetSpellBookItemType(slotBtn, BANK) == Enum.SpellBookItemType.Spell
                    and (allRanks or not C_SpellBook.IsSpellBookItemLowRank(slotBtn, BANK))
                    and (passives or not C_SpellBook.IsSpellBookItemPassive(slotBtn, BANK))
                then
                    slotList[#slotList + 1] = slotBtn
                    if searchText and Matches(slotBtn) then
                        found.slots[#found.slots + 1] = slotBtn
                    end
                end
            end
            lineList[#lineList + 1] = { name = spellInfo.name, icon = spellInfo.iconID, slots = slotList }
        end
    end
    if line > #lineList then
        line = 1
    end
end

-- The line on show: the search results while searching.
local function Shown()
    if searchText then
        return found, 0
    end
    return lineList[line], line
end

local function PageCount()
    local l = Shown()
    return l and math.max(1, math.ceil(#l.slots / PER_PAGE)) or 1
end

-------------------------------------------------------------------------------
--  Spell buttons
-------------------------------------------------------------------------------
local function SpellEnter(b)
    if not b.slot then
        return
    end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetSpellBookItem(b.slot, BANK)
    GameTooltip:Show()
end

local function SpellLeave()
    GameTooltip:Hide()
end

local function SpellDrag(b)
    if b.spellID and not b.passive and not InCombatLockdown() then
        C_Spell.PickupSpell(b.spellID)
    end
end

local function NewSpellButton(i)
    local widget = CreateFrame("Button", nil, bookFrame, "SecureActionButtonTemplate")
    widget:SetSize(37, 37)
    -- Down the left column, then down the right one.
    local colour, row = math.floor((i - 1) / ROWS), (i - 1) % ROWS
    widget:SetPoint("TOPLEFT", bookFrame, "TOPLEFT", 34 + colour * 157, -85 - row * 51)
    widget:RegisterForClicks("AnyUp", "AnyDown") -- the action fires on whichever the client's key-down setting picks
    widget:RegisterForDrag("LeftButton")

    local empty = widget:CreateTexture(nil, "BACKGROUND")
    empty:SetTexture(ART .. "UI-Spellbook-SpellBackground")
    empty:SetSize(64, 64)
    empty:SetPoint("TOPLEFT", -3, 3)

    widget.icon = widget:CreateTexture(nil, "BORDER")
    widget.icon:SetAllPoints()
    widget.cooldown = CreateFrame("Cooldown", nil, widget, "CooldownFrameTemplate")
    widget.cooldown:SetAllPoints()

    widget.name = widget:CreateFontString(nil, "BORDER", "GameFontNormal")
    widget.name:SetJustifyH("LEFT")
    widget.name:SetWidth(103)
    widget.name:SetMaxLines(3)
    widget.name:SetPoint("LEFT", widget, "RIGHT", 5, 3)

    widget.sub = widget:CreateFontString(nil, "BORDER", SubSpellFont and "SubSpellFont" or "GameFontHighlightSmall")
    widget.sub:SetJustifyH("LEFT")
    widget.sub:SetPoint("TOPLEFT", widget.name, "BOTTOMLEFT", 0, -2)

    widget:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    local normal = widget:GetNormalTexture()
    normal:ClearAllPoints()
    normal:SetSize(64, 64)
    normal:SetPoint("CENTER")
    widget.border = normal
    widget:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    widget:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    widget:SetScript("OnEnter", SpellEnter)
    widget:SetScript("OnLeave", SpellLeave)
    widget:SetScript("OnDragStart", SpellDrag)
    return widget
end

-- What the button shows. What it casts is set by the AIM snippet.
local function FillSpellButton(b, slotBtn)
    local spellInfo = slotBtn and C_SpellBook.GetSpellBookItemInfo(slotBtn, BANK)
    local spellID = spellInfo and spellInfo.spellID
    if not spellID then
        b.slot, b.spellID, b.passive = nil, nil, nil
        b.icon:Hide()
        b.name:Hide()
        b.sub:Hide()
        b.border:SetVertexColor(1, 1, 1)
        return
    end
    b.slot, b.spellID, b.passive = slotBtn, spellID, spellInfo.isPassive
    b.icon:SetTexture(spellInfo.iconID)
    b.icon:Show()
    b.name:SetText(spellInfo.name)
    b.name:Show()
    local sub = spellInfo.subName
    if not sub or sub == "" then
        sub = C_Spell.GetSpellSubtext(spellID)
    end
    if (not sub or sub == "") and spellInfo.isPassive then
        sub = SPELL_PASSIVE
    end
    b.sub:SetText(sub or "")
    b.sub:Show()
    local c = spellInfo.isPassive and PASSIVE_SPELL_FONT_COLOR or NORMAL_FONT_COLOR
    b.name:SetTextColor(c.r, c.g, c.b)
    -- A passive has no button frame, as in the vanilla book.
    local v = spellInfo.isPassive and 0 or 1
    b.border:SetVertexColor(v, v, v)
end

-- The cooldown swirls of the page on show. The duration goes straight from
-- the game to the swirl: its numbers can be secret in combat.
local function PaintCooldowns()
    for _, b in ipairs(bookFrame.spells) do
        local duration = b.slot
            and not b.passive
            and C_SpellBook.GetSpellBookItemCooldownDuration(b.slot, BANK)
        if duration then
            b.cooldown:SetCooldownFromDurationObject(duration)
        else
            b.cooldown:Clear()
        end
    end
end

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
-- Restricted snippets, all run in the book's environment: LINES[n] lists what
-- each slot of skill line n casts (0: nothing; n = 0 is the search results),
-- COUNTS[n] its length, PAGES[n] its page and LINE the line on show.
-- AIM points the twelve buttons at the page on show, then has the page drawn.
local AIM = [[
    local list = LINES[LINE]
    local count = COUNTS[LINE] or 0
    local last = (count - count % 12) / 12
    if count % 12 > 0 or last < 1 then last = last + 1 end
    local page = PAGES[LINE] or 1
    if page > last then page = last end
    if page < 1 then page = 1 end
    PAGES[LINE] = page
    for i = 1, 12 do
        local id = list and list[(page - 1) * 12 + i]
        local b = SPELLS[i]
        if id and id > 0 then
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", id)
        else
            b:SetAttribute("type", nil)
            b:SetAttribute("spell", nil)
        end
    end
    BOOK:CallMethod("Painted", LINE, page)
]]

local function TabEnter(tabBtn)
    CludesUI.ShowWidgetTooltip(tabBtn, tabBtn.tooltip, { anchor = "right" })
end

local function TabLeave()
    CludesUI.HideWidgetTooltip()
end

local function TurnSound(b)
    if not b.idle then
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
    end
end

-- Out of combat only, like every frame made here. A click shows its line.
local function NewTab(i)
    local tabBtn = CreateFrame("CheckButton", nil, bookFrame, "SecureFrameTemplate")
    tabBtn:SetSize(32, 32)
    tabBtn:SetPoint("TOPLEFT", bookFrame, "TOPRIGHT", -32, -65 - (i - 1) * 49)
    local bgTex = tabBtn:CreateTexture(nil, "BACKGROUND")
    bgTex:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    bgTex:SetSize(64, 64)
    bgTex:SetPoint("TOPLEFT", -3, 11)
    tabBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tabBtn:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    tabBtn:GetCheckedTexture():SetBlendMode("ADD")
    tabBtn:SetScript("OnEnter", TabEnter)
    tabBtn:SetScript("OnLeave", TabLeave)
    tabBtn:SetScript("PostClick", TurnSound)
    bookFrame:WrapScript(tabBtn, "OnClick", ("LINE = %d\n"):format(i) .. AIM)
    return tabBtn
end

-- A click turns step pages; AIM keeps the page inside the line.
local function NewArrow(direction, x, step)
    local widget = CreateFrame("Button", nil, bookFrame, "SecureFrameTemplate")
    widget:SetSize(32, 32)
    widget:SetPoint("CENTER", bookFrame, "BOTTOMLEFT", x, 105)
    local texture = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
    widget.art = texture
    widget:SetNormalTexture(texture .. "Up")
    widget:SetPushedTexture(texture .. "Down")
    widget:SetDisabledTexture(texture .. "Disabled")
    widget:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    widget:SetScript("PostClick", TurnSound)
    bookFrame:WrapScript(widget, "OnClick", ("PAGES[LINE] = (PAGES[LINE] or 1) + (%d)\n"):format(step) .. AIM)
    return widget
end

-- An arrow with nowhere to go shows its disabled art and cannot be clicked. The arrows are
-- secure frames, so only out of combat can they be disabled: combat starts with
-- both enabled (the idle one clicks silently) and the fight's end syncs them.
local function ArrowsFor(pageNum)
    local canPrev, canNext = pageNum > 1, pageNum < PageCount()
    for arrow, can in pairs({ [bookFrame.prev] = canPrev, [bookFrame.next] = canNext }) do
        arrow:SetNormalTexture(arrow.art .. (can and "Up" or "Disabled"))
        arrow.idle = not can
    end
    if InCombatLockdown() then
        CludesUI.CombatQueue.Defer(QUEUE_KEY .. "Arrows", function()
            local _, spellKey = Shown()
            ArrowsFor(pages[spellKey] or 1)
        end)
        return
    end
    bookFrame.prev:SetEnabled(canPrev)
    bookFrame.next:SetEnabled(canNext)
end

-- Draws the page on show. No protected call: it also runs in combat.
local function Paint()
    local l, spellKey = Shown()
    local pageNum = pages[spellKey] or 1
    for i, b in ipairs(bookFrame.spells) do
        FillSpellButton(b, l and l.slots[(pageNum - 1) * PER_PAGE + i])
    end
    for i, tabBtn in ipairs(bookFrame.tabs) do
        tabBtn:SetChecked(not searchText and i == line)
    end
    ArrowsFor(pageNum)
    bookFrame.pageText:SetFormattedText(PAGE_NUMBER, pageNum)
    PaintCooldowns()
end

-- AIM's report: the line and page now on show. A line of its own ends a search.
local function Painted(_, shown, pageNum)
    if shown > 0 then
        line = shown
        if searchText then
            searchText = nil
            bookFrame.search:SetText("")
        end
    end
    pages[shown] = pageNum
    Paint()
end

-- One line of the LINES table, as snippet text.
local function LineText(result, spellKey, slotList)
    result[#result + 1] = ("local t = newtable() LINES[%d] = t COUNTS[%d] = %d"):format(spellKey, spellKey, #slotList)
    for i, slotBtn in ipairs(slotList) do
        local spellInfo = C_SpellBook.GetSpellBookItemInfo(slotBtn, BANK)
        local id = spellInfo and not spellInfo.isPassive and spellInfo.spellID or 0
        result[#result + 1] = ("t[%d] = %d"):format(i, id)
    end
end

-- Out of combat only: hands the snippets the spell lists and has them aim.
local function Push()
    for i, data in ipairs(lineList) do
        local tabBtn = bookFrame.tabs[i]
        if not tabBtn then
            tabBtn = NewTab(i)
            bookFrame.tabs[i] = tabBtn
        end
        tabBtn:SetNormalTexture(data.icon)
        tabBtn.tooltip = data.name
        tabBtn:Show()
    end
    for i = #lineList + 1, #bookFrame.tabs do
        bookFrame.tabs[i]:Hide()
    end

    local result = { "LINES = newtable() COUNTS = newtable()" }
    for i, data in ipairs(lineList) do
        LineText(result, i, data.slots)
    end
    if searchText then
        LineText(result, 0, found.slots)
    end
    local reset = newSearch
    if reset then
        result[#result + 1] = "PAGES[0] = 1"
    end
    newSearch = nil
    result[#result + 1] = ("LINE = %d"):format(searchText and 0 or line)
    result[#result + 1] = AIM
    -- The snippets already hold these lists (a refresh that found no change,
    -- as most of the ones a pull starts do): only the page is drawn again.
    local label = table.concat(result, "\n")
    if label == pushed and not reset then
        Paint()
        return
    end
    pushed = label
    bookFrame:Execute(label)
end

-- Rereads the spellbook and repaints; waits out combat.
local function Refresh()
    if not bookFrame then
        return
    end
    if InCombatLockdown() then
        CludesUI.CombatQueue.Defer(QUEUE_KEY, Refresh)
        return
    end
    stale = nil
    ReadLines()
    Push()
end

-- The talent window stands beside the open book and takes its place when it
-- closes (the book is protected, so it is the one that never moves).
local function PlaceTalents()
    local talents = CludesUI._ClassicTalents
    if talents then
        talents.Place()
    end
end

-- Cooldowns are followed only while the book is open.
local function BookShown()
    PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN)
    eventList:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    PaintCooldowns()
    PlaceTalents()
    Refresh() -- also picks up a spellbook option changed in the game's own book
end

local function BookHidden()
    PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE)
    eventList:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    PlaceTalents()
end

-- A search or an option changed in combat applies when the fight ends.
local function Changed()
    if InCombatLockdown() then
        UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1)
    end
    Refresh()
end

local function SearchChanged(box)
    local label = strtrim(box:GetText()):lower()
    label = label ~= "" and label or nil
    if label == searchText then
        return
    end
    searchText, newSearch = label, true
    Changed()
end

-- A spellbook option of the game's: a checkbox over its console variable.
local function Option(root, label, cvar)
    root:CreateCheckbox(label, function()
        return GetCVarBool(cvar)
    end, function()
        SetCVar(cvar, not GetCVarBool(cvar))
        Changed()
    end)
end

-- Warriors and rogues have no spell ranks to show, as in the game's own menu.
local function OptionsMenu(_, root)
    Option(root, SPELLBOOK_FILTER_PASSIVES, "spellBookHidePassives")
    local _, class = UnitClass("player")
    if class ~= "ROGUE" and class ~= "WARRIOR" then
        Option(root, SHOW_ALL_SPELL_RANKS, "ShowAllSpellRanks")
    end
end

local TOGGLE_SNIPPET = [[
    local book = self:GetFrameRef("book")
    if book:IsShown() then book:Hide() else book:Show() end
]]

-- The micro menu's Spellbook button opens the book too, through a click layer
-- of ours over it (module.MicroClickLayer). An addon's click cannot show the
-- protected book in combat, so from a fight's start to its end the layer lets
-- the clicks through to the game's button, which opens its own window.
local microButtons
-- Our other panels that open the spellbook (the Data Bars micro menu block,
-- Quickdraw) click CUI_SpellbookRoute: a secure click that goes to the book's
-- toggle while the feature is on and to the game's Spellbook micro button
-- otherwise, so it works in combat either way. Made at load, out of combat.
local route

local function Build()
    if bookFrame then
        return
    end
    bookFrame = CreateFrame("Frame", "CUI_ClassicSpellbook", UIParent, "SecureHandlerShowHideTemplate")
    bookFrame:Hide()
    bookFrame:SetSize(384, 512)
    bookFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
    bookFrame:SetFrameStrata("MEDIUM")
    bookFrame:SetToplevel(true)
    bookFrame:EnableMouse(true)
    bookFrame:SetHitRectInsets(0, 30, 0, 70)
    -- Escape closes the open book, in combat too.
    bookFrame:SetAttribute("_onshow", ([[ self:SetBindingClick(true, "ESCAPE", %q) ]]):format(ESCAPE_NAME))
    bookFrame:SetAttribute("_onhide", [[ self:ClearBindings() ]])
    bookFrame:HookScript("OnShow", BookShown)
    bookFrame:HookScript("OnHide", BookHidden)

    local portrait = bookFrame:CreateTexture(nil, "BACKGROUND")
    portrait:SetTexture(ART .. "Spellbook-Icon")
    portrait:SetSize(58, 58)
    portrait:SetPoint("TOPLEFT", 10, -8)
    for _, part in ipairs({
        { "TopLeft", "TOPLEFT", 256 },
        { "TopRight", "TOPRIGHT", 128 },
        { "BotLeft", "BOTTOMLEFT", 256 },
        { "BotRight", "BOTTOMRIGHT", 128 },
    }) do
        local texture = bookFrame:CreateTexture(nil, "ARTWORK")
        texture:SetTexture(ART .. "UI-SpellbookPanel-" .. part[1])
        texture:SetSize(part[3], 256)
        texture:SetPoint(part[2])
    end
    local title = bookFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("CENTER", 6, 230)
    title:SetText(SPELLBOOK)
    bookFrame.pageText = bookFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bookFrame.pageText:SetWidth(102)
    bookFrame.pageText:SetPoint("BOTTOM", -14, 99) -- between the page arrows

    toggle = CreateFrame("Button", TOGGLE_NAME, UIParent, "SecureHandlerClickTemplate")
    toggle:SetFrameRef("book", bookFrame)
    toggle:SetAttribute("_onclick", TOGGLE_SNIPPET)

    -- Escape also closes the talent window that stands beside the book.
    local escape = CreateFrame("Button", ESCAPE_NAME, UIParent, "SecureHandlerClickTemplate")
    escape:SetFrameRef("book", bookFrame)
    escape:SetAttribute("_onclick", [[ self:GetFrameRef("book"):Hide() ]])
    escape:SetScript("PostClick", function()
        local talents = CludesUI._ClassicTalents
        if talents then
            talents.Close()
        end
    end)

    local closeBtn = CreateFrame("Button", nil, bookFrame, "SecureHandlerClickTemplate")
    closeBtn:SetSize(32, 32)
    closeBtn:SetPoint("CENTER", bookFrame, "TOPRIGHT", -44, -25)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    closeBtn:SetFrameRef("book", bookFrame)
    closeBtn:SetAttribute("_onclick", [[ self:GetFrameRef("book"):Hide() ]])

    -- The game's own search box and options button, under the title.
    bookFrame.options = CreateFrame("DropdownButton", nil, bookFrame, "UIPanelArrowDropdownButtonTemplate")
    bookFrame.options:SetPoint("TOPRIGHT", -62, -47)
    bookFrame.options:SetupMenu(OptionsMenu)
    bookFrame.search = CreateFrame("EditBox", nil, bookFrame, "SearchBoxTemplate")
    bookFrame.search:SetHeight(20)
    bookFrame.search:SetPoint("TOPLEFT", 84, -42)
    bookFrame.search:SetPoint("RIGHT", bookFrame.options, "LEFT", -6, 0)
    bookFrame.search.Instructions:SetText(SPELLBOOK_SEARCH_INSTRUCTIONS)
    bookFrame.search:HookScript("OnTextChanged", SearchChanged)

    bookFrame.tabs, bookFrame.spells = {}, {}
    for i = 1, PER_PAGE do
        bookFrame.spells[i] = NewSpellButton(i)
        bookFrame:SetFrameRef("spell" .. i, bookFrame.spells[i])
    end
    bookFrame.Painted = Painted
    bookFrame:Execute([[
        BOOK, LINE = self, 1
        LINES, COUNTS, PAGES, SPELLS = newtable(), newtable(), newtable(), newtable()
        for i = 1, 12 do SPELLS[i] = self:GetFrameRef("spell" .. i) end
    ]])
    bookFrame.prev = NewArrow("Prev", 50, -1)
    bookFrame.next = NewArrow("Next", 314, 1)
    if CludesUI._ShifterAdopt then
        CludesUI._ShifterAdopt("CUI_ClassicSpellbook")
    end
end

-- The click layer's click: out of combat, where an addon may show the book.
local function MicroToggle()
    if not bookFrame or InCombatLockdown() then
        return
    end
    if bookFrame:IsShown() then
        bookFrame:Hide()
    else
        bookFrame:Show()
    end
end

local function MicroClicksBack()
    if microButtons then
        microButtons:SetMouseClickEnabled(true)
    end
end

-- The route clicks the book's toggle while the feature is on, else the game's
-- micro button. Out of combat only (Apply defers itself).
local function AimRoute(on)
    if not route then
        return
    end
    local target = on and toggle or _G.SpellbookMicroButton
    if route:GetAttribute("clickbutton") ~= target then
        route:SetAttribute("clickbutton", target)
    end
end

if not InCombatLockdown() then
    route = CreateFrame("Button", "CUI_SpellbookRoute", UIParent, "SecureActionButtonTemplate")
    route:SetAttribute("type", "click")
    route:SetAttribute("useOnKeyDown", false)
    AimRoute(false)
end

-------------------------------------------------------------------------------
--  Setup
-------------------------------------------------------------------------------
-- The spellbook key clicks the toggle while the feature is on. Setting an
-- override fires UPDATE_BINDINGS itself, so unchanged keys are left alone.
local function Bind()
    if InCombatLockdown() then
        CludesUI.CombatQueue.Defer(QUEUE_KEY .. "Bind", Bind)
        return
    end
    if not toggle then
        return
    end
    local keys = F.Enabled() and table.concat({ GetBindingKey("TOGGLESPELLBOOK") }, " ") or ""
    if keys == boundKeys then
        return
    end
    boundKeys = keys
    ClearOverrideBindings(toggle)
    for spellKey in keys:gmatch("%S+") do
        SetOverrideBindingClick(toggle, true, spellKey, TOGGLE_NAME)
    end
end

-- A closed book only notes that the spellbook changed. It catches up when it
-- opens, or as combat starts (this event runs before the lockdown does), so a
-- book first opened in a fight still holds the right spells.
local function OnEvent(_, event)
    if event == "UPDATE_BINDINGS" then
        Bind()
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        PaintCooldowns()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if stale then
            Refresh()
        end
        if bookFrame then
            bookFrame.prev:SetEnabled(true)
            bookFrame.next:SetEnabled(true)
        end
        -- The game's own window opens from the micro button until the fight ends.
        if microButtons then
            microButtons:SetMouseClickEnabled(false)
            CludesUI.CombatQueue.Defer(QUEUE_KEY .. "Micro", MicroClicksBack)
        end
    elseif bookFrame:IsShown() then
        Refresh()
    else
        stale = true
    end
end

local function Apply()
    if InCombatLockdown() then
        CludesUI.CombatQueue.Defer(QUEUE_KEY .. "Apply", Apply)
        return
    end
    if eventList then
        eventList:UnregisterAllEvents()
    end
    if not F.Enabled() then
        if microButtons then
            microButtons:Hide()
        end
        AimRoute(false)
        if bookFrame then
            bookFrame:Hide()
        end
        Bind()
        return
    end
    if not eventList then
        eventList = CreateFrame("Frame")
        eventList:SetScript("OnEvent", OnEvent)
    end
    Build()
    AimRoute(true)
    if not microButtons then
        microButtons = module.MicroClickLayer("SpellbookMicroButton", MicroToggle)
    end
    if microButtons then
        microButtons:SetMouseClickEnabled(true)
        microButtons:Show()
    end
    eventList:RegisterEvent("SPELLS_CHANGED")
    eventList:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
    eventList:RegisterEvent("UPDATE_BINDINGS")
    eventList:RegisterEvent("PLAYER_REGEN_DISABLED")
    if bookFrame:IsShown() then
        eventList:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    end
    Bind()
    Refresh()
end

-- Options-page entry points.
CludesUI._ClassicSpellbook = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply)
