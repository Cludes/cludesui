if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CooldownManager_BarGlowConditions.lua
--  Bar Glows page rows for the per-glow conditions (runtime:
--  CludesUICdmBarGlowConditions.lua). A glow entry on the page reads:
--
--    When (icon) Fingers of Frost is [Active v]  | And [(icon) Brain Freeze v] is [Missing v]  [toggle]
--    At Stacks      (gear) [toggle]              | Glow Type       [Pixel Glow v]
--    Only In Combat [toggle]                     | Hero Talent     [Any v]
--    Glow Color     ...                          | (icon) [Duplicate] [Remove]
--
--  Left of row 1 is the glow's own Glow When (entry.mode). The And toggle is
--  entry.andMode = "and" | nil (its buff and state grey out while off); the
--  second buff and its state are entry.conditions[1]. Each glow starts with a
--  collapse bar (collapsed: buff icon + name only, entry.collapsed); Duplicate
--  inserts a full copy right below.
--  Frames are built with the page; nothing exists until it is opened.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUICooldownManager"]
if not mod then
    return
end

-- The options page pool (CludesUI_FramePool.lua): a frame the page's rows
-- make under a pool host (a reused page) is handed out again reset to fresh;
-- anywhere else (the buff menu, built once on UIParent) the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

local function Cond(record)
    if type(record.conditions) ~= "table" then
        record.conditions = {}
    end
    if type(record.conditions[1]) ~= "table" then
        record.conditions[1] = {}
    end
    return record.conditions[1]
end

local function SpellLabel(spellRef)
    spellRef = tonumber(spellRef)
    if not spellRef or spellRef <= 0 then
        return CludesUI.L("Choose Buff"), nil
    end
    local details = C_Spell.GetSpellInfo(spellRef)
    return (details and details.name) or ("Spell " .. spellRef), details and details.iconID
end

-- A spell icon that shows the spell's tooltip on hover.
function mod.BarGlowSpellIcon(hostFrame, size, spellId)
    local f = CreateFrame("Frame", nil, hostFrame)
    f:SetSize(size, size)
    f:SetFrameLevel(hostFrame:GetFrameLevel() + 3)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local spellRef = tonumber(spellId)
    local details = spellRef and spellRef > 0 and C_Spell.GetSpellInfo(spellRef)
    if details and details.iconID then
        f.tex:SetTexture(details.iconID)
    end
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if not (spellRef and spellRef > 0) then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(spellRef)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return f
end

-------------------------------------------------------------------------------
--  Bar Glows buff menu, shared by the add-glow picker (several buffs, stays
--  open) and the glow's When / And pickers (one buff): tracked buffs, then
--  untracked, then tracked bars. ONE menu frame and a row pool, reused by every
--  open (none is built until the first open).
--    opts.isChecked(spellID) -> bool    box state of a row
--    opts.onClick(sp, refreshChecks)    a row click: call refreshChecks() to
--                                       repaint the boxes, or hide the menu
--    opts.emptyText                     shown when nothing is listed (nil: the
--                                       menu does not open then)
--    opts.usableItem = { icon = id }    adds a top "Glow When Usable" row (the
--                                       button's own ability; spellID 0, usable = true)
--  Returns the menu frame, or nil when it did not open.
-------------------------------------------------------------------------------
local MENU_W, ITEM_H, MAX_H = 240, 26, 300
local dropMenu, scroll, inner, emptyText, menuOpts, menuAnchor
local rowList, divs = {}, {}

local function RefreshChecks()
    local options = menuOpts
    if not options then
        return
    end
    local ACCENT = CludesUI.CLUDES_GREEN
    for idx = 1, #rowList do
        local r = rowList[idx]
        if r:IsShown() then
            if options.isChecked(r.sp.spellID) then
                r.fill:Show()
                r.brd:SetColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.8)
            else
                r.fill:Hide()
                r.brd:SetColor(0.224, 0.215, 0.207, 0.6)
            end
        end
    end
end

local function BuildMenu()
    dropMenu = CreateFrame("Frame", nil, UIParent)
    dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    dropMenu:SetFrameLevel(300)
    dropMenu:SetClampedToScreen(true)
    dropMenu:SetSize(MENU_W, 10)
    dropMenu:Hide()
    local backdrop = dropMenu:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(CludesUI.DD_BG_R, CludesUI.DD_BG_G, CludesUI.DD_BG_B, CludesUI.DD_BG_HA)
    CludesUI.MakeRoundedBorder(dropMenu, 1, 1, 1, CludesUI.DD_BRD_A, backdrop, nil, true)

    scroll = CreateFrame("ScrollFrame", nil, dropMenu)
    scroll:SetPoint("TOPLEFT", 0, -1)
    scroll:SetPoint("BOTTOMRIGHT", 0, 1)
    scroll:SetFrameLevel(dropMenu:GetFrameLevel() + 1)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = dropMenu._maxScroll or 0
        if maxScroll <= 0 then
            return
        end
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 30)))
    end)
    inner = CreateFrame("Frame", nil, scroll)
    inner:SetWidth(MENU_W)
    scroll:SetScrollChild(inner)

    emptyText = inner:CreateFontString(nil, "OVERLAY")
    emptyText:SetPoint("TOPLEFT", inner, "TOPLEFT", 10, -8)

    -- Closing: a click outside the menu and its anchor, or the options panel hiding.
    dropMenu:SetScript("OnUpdate", function(m)
        if
            IsMouseButtonDown("LeftButton")
            and not m:IsMouseOver()
            and not (menuAnchor and menuAnchor:IsMouseOver())
        then
            m:Hide()
        end
    end)
    dropMenu:SetScript("OnHide", function()
        menuOpts, menuAnchor = nil, nil
    end)
    CludesUI:RegisterOnHide(function()
        dropMenu:Hide()
    end)
end

local function Row(idx)
    local r = rowList[idx]
    if r then
        return r
    end
    r = CreateFrame("Button", nil, inner)
    r:SetHeight(ITEM_H)
    r:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
    local checkBtn = CreateFrame("Frame", nil, r)
    checkBtn:SetSize(14, 14)
    checkBtn:SetPoint("LEFT", r, "LEFT", 8, 0)
    checkBtn:SetFrameLevel(r:GetFrameLevel() + 1)
    local cbBg = checkBtn:CreateTexture(nil, "BACKGROUND")
    cbBg:SetAllPoints()
    cbBg:SetColorTexture(0.114, 0.106, 0.099, 1)
    r.brd = CludesUI.MakeRoundedBorder(checkBtn, 0.224, 0.215, 0.207, 0.6, cbBg)
    local ACCENT = CludesUI.CLUDES_GREEN
    r.fill = checkBtn:CreateTexture(nil, "ARTWORK")
    r.fill:SetSnapToPixelGrid(false)
    r.fill:SetTexelSnappingBias(0)
    r.fill:SetPoint("TOPLEFT", checkBtn, "TOPLEFT", 3, -3)
    r.fill:SetPoint("BOTTOMRIGHT", checkBtn, "BOTTOMRIGHT", -3, 3)
    CludesUI.RoundBody(checkBtn, r.fill, 1)
    r.fill:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 1)
    r.ico = r:CreateTexture(nil, "ARTWORK")
    r.ico:SetSize(ITEM_H - 4, ITEM_H - 4)
    r.ico:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.lbl = r:CreateFontString(nil, "OVERLAY")
    r.lbl:SetPoint("LEFT", checkBtn, "RIGHT", 6, 0)
    r.lbl:SetPoint("RIGHT", r.ico, "LEFT", -4, 0)
    r.lbl:SetJustifyH("LEFT")
    r.lbl:SetWordWrap(false)
    r.lbl:SetMaxLines(1)
    local highlight = r:CreateTexture(nil, "ARTWORK", nil, -1)
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0)
    r:SetScript("OnEnter", function()
        r.lbl:SetTextColor(1, 1, 1, 1)
        highlight:SetColorTexture(1, 1, 1, CludesUI.DD_ITEM_HL_A)
    end)
    r:SetScript("OnLeave", function()
        r.lbl:SetTextColor(CludesUI.TEXT_DIM_R, CludesUI.TEXT_DIM_G, CludesUI.TEXT_DIM_B, CludesUI.TEXT_DIM_A)
        highlight:SetColorTexture(1, 1, 1, 0)
    end)
    r:SetScript("OnClick", function(self)
        local options = menuOpts
        if options then
            options.onClick(self.sp, RefreshChecks)
        end
    end)
    rowList[idx] = r
    return r
end

function mod.ShowBarGlowBuffMenu(anchor, options)
    if dropMenu then
        dropMenu:Hide()
    end
    local tracked, untracked = {}, {}
    if mod.GetAllCDMBuffSpells then
        tracked, untracked = mod.GetAllCDMBuffSpells()
    end
    tracked, untracked = tracked or {}, untracked or {}
    local barList = mod.GetTrackedBarSpells and mod.GetTrackedBarSpells() or {}
    if
        #tracked == 0
        and #untracked == 0
        and #barList == 0
        and not options.emptyText
        and not options.usableItem
    then
        return nil
    end
    if not dropMenu then
        BuildMenu()
    end
    menuOpts, menuAnchor = options, anchor
    dropMenu._btnIdx = nil

    local environ = mod._CDMO_OptEnv or {}
    local font = environ.FONT_PATH or STANDARD_TEXT_FONT
    local outline = environ.GetCDMOptOutline and environ.GetCDMOptOutline() or ""
    local num, nd, menuH = 0, 0, 4
    local function Add(sp)
        local spellRef = tonumber(sp.spellID)
        if not spellRef or spellRef <= 0 then
            return
        end
        num = num + 1
        local r = Row(num)
        r.sp = sp
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -menuH)
        r:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -menuH)
        local name, icon = sp.name, sp.icon
        if not (name and icon) then
            local spellName, spellIcon = SpellLabel(spellRef)
            name, icon = name or spellName, icon or spellIcon
        end
        r.ico:SetTexture(icon)
        r.lbl:SetFont(font, 11, outline)
        r.lbl:SetText(CludesUI.L(name))
        r.lbl:SetTextColor(CludesUI.TEXT_DIM_R, CludesUI.TEXT_DIM_G, CludesUI.TEXT_DIM_B, CludesUI.TEXT_DIM_A)
        r:Show()
        menuH = menuH + ITEM_H
    end
    local function AddUsable(entry)
        num = num + 1
        local r = Row(num)
        r.sp = { spellID = 0, usable = true }
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -menuH)
        r:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -menuH)
        r.ico:SetTexture(entry.icon or 134400)
        r.lbl:SetFont(font, 11, outline)
        r.lbl:SetText(CludesUI.L("Glow When Usable"))
        r.lbl:SetTextColor(CludesUI.TEXT_DIM_R, CludesUI.TEXT_DIM_G, CludesUI.TEXT_DIM_B, CludesUI.TEXT_DIM_A)
        r:Show()
        menuH = menuH + ITEM_H
    end
    local function Divider()
        nd = nd + 1
        local d = divs[nd]
        if not d then
            d = inner:CreateTexture(nil, "ARTWORK")
            d:SetHeight(1)
            d:SetColorTexture(1, 1, 1, 0.10)
            divs[nd] = d
        end
        d:ClearAllPoints()
        d:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -menuH - 4)
        d:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -menuH - 4)
        d:Show()
        menuH = menuH + 9
    end

    if options.usableItem then
        AddUsable(options.usableItem)
        if #tracked > 0 or #untracked > 0 or #barList > 0 then
            Divider()
        end
    end
    for _, sp in ipairs(tracked) do
        Add(sp)
    end
    if #tracked > 0 and #untracked > 0 then
        Divider()
    end
    for _, sp in ipairs(untracked) do
        Add(sp)
    end
    if #barList > 0 then
        if #tracked > 0 or #untracked > 0 then
            Divider()
        end
        for _, sp in ipairs(barList) do
            Add(sp)
        end
    end
    for idx = num + 1, #rowList do
        rowList[idx]:Hide()
    end
    for idx = nd + 1, #divs do
        divs[idx]:Hide()
    end
    if num == 0 then
        emptyText:SetFont(font, 11, outline)
        emptyText:SetTextColor(
            CludesUI.TEXT_DIM_R,
            CludesUI.TEXT_DIM_G,
            CludesUI.TEXT_DIM_B,
            CludesUI.TEXT_DIM_A
        )
        emptyText:SetText(CludesUI.L(options.emptyText))
        emptyText:Show()
        menuH = 30
    else
        emptyText:Hide()
    end
    RefreshChecks()

    local totalH = menuH + 4
    inner:SetHeight(totalH)
    dropMenu:SetHeight(math.min(totalH, MAX_H))
    dropMenu._maxScroll = totalH - MAX_H
    scroll:SetVerticalScroll(0)
    dropMenu:ClearAllPoints()
    dropMenu:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
    dropMenu:Show()
    return dropMenu
end

-- Single choice for the When / And rows: closes on a pick.
local function ShowPicker(anchor, currentSid, onPick)
    local current = tonumber(currentSid)
    mod.ShowBarGlowBuffMenu(anchor, {
        emptyText = "No Cooldown Manager buffs to choose from.",
        isChecked = function(spellRef)
            return tonumber(spellRef) == current
        end,
        onClick = function(sp)
            dropMenu:Hide()
            onPick(tonumber(sp.spellID))
        end,
    })
end

-- Active / Missing: the glow's own state (entry.mode) and the And buff's
-- (c.state = "missing" | nil), both standard option dropdowns.
local STATE_VALUES = { ACTIVE = "Active", MISSING = "Missing" }
local STATE_ORDER = { "ACTIVE", "MISSING" }
-- Glow When Usable has the one state: the button's own ability can be pressed.
local USABLE_VALUES = { USABLE = "Usable" }
local USABLE_ORDER = { "USABLE" }

-- Row 1 of a glow, two columns:
--   left:  When Fingers of Frost Is                               [Active v]
--   right: And [(icon) Brain Freeze v] is [Missing v]                [toggle]
-- The left column is a standard dropdown row (the glow's own Glow When); the
-- right is a standard toggle row labelled "And"; while it is off the buff
-- picker and its state grey out. Returns the new y.
-- ownSid: the button's ability when the entry saves none (CDM icons).
function mod.BuildBarGlowWhenRow(W, hostFrame, cursorY, record, onChange, ownSid)
    local c = Cond(record)
    local Paint -- forward: the toggle repaints the right column
    local usable = record.mode == "USABLE"
    local spellRef = tonumber(usable and (record.actionSpellID or ownSid) or record.spellID) or 0
    local ownName = (spellRef > 0) and SpellLabel(spellRef)
        or (usable and CludesUI.L("this ability") or "buff")

    local row, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = CludesUI.Lf("When %1$s Is", ownName),
        values = usable and USABLE_VALUES or STATE_VALUES,
        order = usable and USABLE_ORDER or STATE_ORDER,
        getValue = function()
            if usable then
                return "USABLE"
            end
            return record.mode == "MISSING" and "MISSING" or "ACTIVE"
        end,
        setValue = function(val)
            if usable then
                return
            end
            record.mode = val
            if onChange then
                onChange()
            end
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "And",
        tooltip = 'Also require a second buff to be active (or missing) for this glow. For an "or", add another glow to the same button.',
        getValue = function()
            return record.andMode == "and"
        end,
        setValue = function(val)
            record.andMode = val and "and" or nil
            if Paint then
                Paint()
            end
            if onChange then
                onChange()
            end
        end,
    })
    cursorY = cursorY - height
    if CludesUI._prebuilding then
        return cursorY
    end

    local leftX, right = row._leftRegion, row._rightRegion
    local lRef = leftX and leftX._label
    local rRef = right and right._label
    local font, size = STANDARD_TEXT_FONT, 13
    if lRef and lRef.GetFont then
        local f, s = lRef:GetFont()
        if f then
            font, size = f, s or size
        end
    end
    local red, green, blue = 1, 1, 1
    if lRef and lRef.GetTextColor then
        red, green, blue = lRef:GetTextColor()
    end
    local CTL_H = 30 -- the options dropdown height (Glow Type)
    local function Word(host, textValue)
        local fontStr = host:CreateFontString(nil, "OVERLAY")
        fontStr:SetFont(font, size, "")
        fontStr:SetTextColor(red, green, blue, 1)
        fontStr:SetText(textValue)
        return fontStr
    end

    -- Right column: after the "And" label, before the toggle -----------------
    local rx = CreateFrame("Frame", nil, right or row)
    rx:SetAllPoints()
    rx:SetFrameLevel((right or row):GetFrameLevel() + 2)
    -- The And buff: a standard dropdown face whose click opens the shared buff
    -- menu (Paint writes its label and icon).
    local buffBtn, buffLbl = CludesUI.BuildDropdownControl(
        rx,
        170,
        rx:GetFrameLevel() + 3,
        { _ = "", _noLoc = true },
        { "_" },
        function()
            return "_"
        end,
        function() end
    )
    buffBtn.icon = buffBtn:CreateTexture(nil, "ARTWORK")
    buffBtn.icon:SetSize(CTL_H - 6, CTL_H - 6)
    buffBtn.icon:SetPoint("LEFT", buffBtn, "LEFT", 3, 0)
    buffBtn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if rRef then
        buffBtn:SetPoint("LEFT", rRef, "RIGHT", 10, 0)
    else
        buffBtn:SetPoint("LEFT", rx, "LEFT", 60, 0)
    end
    local isWord = Word(rx, CludesUI.L("is"))
    isWord:SetPoint("LEFT", buffBtn, "RIGHT", 8, 0)
    local stateDrop = CludesUI.BuildDropdownControl(
        rx,
        96,
        rx:GetFrameLevel() + 3,
        STATE_VALUES,
        STATE_ORDER,
        function()
            return c.state == "missing" and "MISSING" or "ACTIVE"
        end,
        function(val)
            c.state = (val == "MISSING") and "missing" or nil
            Paint()
            if onChange then
                onChange()
            end
        end
    )
    stateDrop:SetPoint("LEFT", isWord, "RIGHT", 8, 0)

    Paint = function()
        local name, icon = SpellLabel(c.spellID)
        buffLbl:SetText(name)
        -- Only the label's LEFT point moves; its RIGHT stays on the arrow.
        if icon then
            buffBtn.icon:SetTexture(icon)
            buffBtn.icon:Show()
            buffLbl:SetPoint("LEFT", buffBtn.icon, "RIGHT", 6, 0)
        else
            buffBtn.icon:Hide()
            buffLbl:SetPoint("LEFT", buffBtn, "LEFT", 12, 0)
        end
        stateDrop._refreshLabel()
        local enabled = record.andMode == "and"
        for _, part in ipairs({ buffBtn, isWord, stateDrop }) do
            part:SetAlpha(enabled and 1 or 0.3)
            if part.EnableMouse then
                part:EnableMouse(enabled)
            end
        end
        -- The "And" label greys with them (the switch itself stays live).
        if rRef then
            rRef:SetAlpha(enabled and 1 or 0.3)
        end
    end

    buffBtn:SetScript("OnClick", function(self)
        ShowPicker(self, c.spellID, function(spellRef)
            c.spellID = spellRef
            Paint()
            if onChange then
                onChange()
            end
        end)
    end)
    Paint()
    return cursorY
end

-- The Only In Combat toggle's row config.
function mod.BarGlowCombatCfg(record, onChange)
    return {
        type = "toggle",
        text = "Only In Combat",
        getValue = function()
            return record.onlyInCombat == true
        end,
        setValue = function(val)
            record.onlyInCombat = val or nil
            if onChange then
                onChange()
            end
        end,
    }
end

-- Only In Combat | Hero Talent (the current spec's hero trees; glows are
-- saved per spec). Retail only: WoW Forever has no hero talents, so the page
-- pairs Only In Combat with Glow Color there instead. Returns the new y.
function mod.BuildBarGlowCombatRow(W, hostFrame, cursorY, record, onChange)
    local combatCfg = mod.BarGlowCombatCfg(record, onChange)
    local heroValues, heroOrder = { any = CludesUI.L("Any") }, { "any" }
    for _, t in ipairs(mod.BarGlowHeroTrees and mod.BarGlowHeroTrees() or {}) do
        local key = tostring(t.id)
        heroValues[key] = t.name
        heroOrder[#heroOrder + 1] = key
    end
    local current = tonumber(record.heroTree)
    if current and not heroValues[tostring(current)] then
        heroValues[tostring(current)] = "Hero Tree " .. current
        heroOrder[#heroOrder + 1] = tostring(current)
    end
    local _, height = W:DualRow(hostFrame, cursorY, combatCfg, {
        type = "dropdown",
        text = "Hero Talent",
        tooltip = "Only use this glow while the chosen hero talent tree is active. Any: always.",
        values = heroValues,
        order = heroOrder,
        getValue = function()
            local t = tonumber(record.heroTree)
            return t and tostring(t) or "any"
        end,
        setValue = function(val)
            record.heroTree = (val ~= "any") and tonumber(val) or nil
            if onChange then
                onChange()
            end
        end,
    })
    return cursorY - height
end

-- "Duplicate" left of a glow's Remove button: inserts a full copy of the glow
-- (buff, style, colour, stacks, And condition, hero talent) right below it, so
-- variants of the same buff (e.g. one per hero tree) start from the original.
-- Returns the button so the buff icon can sit to its left.
function mod.BarGlowDuplicateButton(regionFrame, removeBtn, buffList, index, onDone)
    if CludesUI._prebuilding or not (regionFrame and removeBtn and buffList) then
        return nil
    end
    local Pix = CludesUI.PanelPP or CludesUI.PP
    local b = CreateFrame("Button", nil, regionFrame)
    Pix.Size(b, 110, removeBtn:GetHeight())
    b:SetFrameLevel(removeBtn:GetFrameLevel())
    b:SetPoint("RIGHT", removeBtn, "LEFT", -8, 0)
    CludesUI.MakeStyledButton(b, CludesUI.L("Duplicate"), 13, CludesUI.RB_COLOURS, function()
        local source = buffList[index]
        if type(source) ~= "table" then
            return
        end
        local copy = CopyTable(source)
        copy.collapsed = nil -- the copy opens expanded
        table.insert(buffList, index + 1, copy)
        if onDone then
            onDone()
        end
    end)
    return b
end

-- Bar Glows button preview: the CDM bar's live icon width as it appears on
-- screen (covers width/height match and the UI scale), converted into the
-- preview panel's scale. nil when no icon is laid out yet (the page then uses
-- the stored iconSize).
function mod.BarGlowPreviewIconSize(icons, previewParent)
    if type(icons) ~= "table" then
        return nil
    end
    local ps = previewParent and previewParent.GetEffectiveScale and previewParent:GetEffectiveScale()
    for idx = 1, #icons do
        local f = icons[idx]
        if f and f.GetWidth then
            local wid = f:GetWidth()
            if wid and not (issecretvalue and issecretvalue(wid)) and wid > 1 then
                local es = f:GetEffectiveScale()
                if es and ps and ps > 0 then
                    wid = wid * es / ps
                end
                return math.floor(wid + 0.5)
            end
        end
    end
    return nil
end

-- Collapse bar across the top of each glow, the same height either way: the
-- arrow, the buff icon and its name. Expanded: a down arrow above the glow's
-- rows. Collapsed (entry.collapsed = true, saved): a right arrow, and the rows
-- are skipped. A click flips it and rebuilds the page. The hidden search pre-build
-- and an active search always build every row. Returns the new y and whether
-- the caller should build the rows.
local ARROW_DOWN = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-down3.png"
local ARROW_RIGHT = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-right.png"

function mod.BuildBarGlowHeader(hostFrame, cursorY, record, aIdx, ownSid)
    if not CludesUI._prebuilding then
        CludesUI._passReadSearchFlag = true
    end -- reads the search flag below
    if CludesUI._prebuilding or CludesUI._lessCommonSearchActive then
        return cursorY, true
    end
    local collapsed = record.collapsed == true
    if aIdx > 1 then
        cursorY = cursorY - 8
    end
    local H = 38
    local pad = CludesUI.CONTENT_PAD or 20
    local bar = CreateFrame("Button", nil, hostFrame)
    bar:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", pad, cursorY)
    bar:SetPoint("TOPRIGHT", hostFrame, "TOPRIGHT", -pad, cursorY)
    bar:SetHeight(H)
    bar:SetFrameLevel(hostFrame:GetFrameLevel() + 5)
    local backdrop = bar:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(1, 1, 1, 0.04)

    -- The arrow drawn three times, 1px apart, for a bolder stroke than the icon art.
    local arrows = {}
    for idx, off in ipairs({ { 0, 0 }, { 1, 0 }, { 0, -1 } }) do
        local t = bar:CreateTexture(nil, "OVERLAY")
        t:SetSize(16, 16)
        t:SetTexture(collapsed and ARROW_RIGHT or ARROW_DOWN)
        t:SetPoint("LEFT", bar, "LEFT", 10 + off[1], off[2])
        arrows[idx] = t
    end
    local arrow = arrows[1]
    local function PaintArrow(red, green, blue, a)
        for _, t in ipairs(arrows) do
            t:SetVertexColor(red, green, blue)
            t:SetAlpha(a)
        end
    end
    PaintArrow(1, 1, 1, 0.7)

    local usable = record.mode == "USABLE"
    local ico = mod.BarGlowSpellIcon(bar, 26, usable and (record.actionSpellID or ownSid) or record.spellID)
    ico:SetPoint("LEFT", arrow, "RIGHT", 11, 0)
    local title = CludesUI.MakeFont(bar, 13, nil, 1, 1, 1)
    title:SetPoint("LEFT", ico, "RIGHT", 10, 0)
    title:SetText(usable and CludesUI.L("Glow When Usable") or (SpellLabel(record.spellID)))

    local ACC = CludesUI.CLUDES_GREEN
    bar:SetScript("OnEnter", function()
        backdrop:SetColorTexture(1, 1, 1, 0.08)
        PaintArrow(ACC.r, ACC.g, ACC.b, 1)
        title:SetTextColor(ACC.r, ACC.g, ACC.b)
    end)
    bar:SetScript("OnLeave", function()
        backdrop:SetColorTexture(1, 1, 1, 0.04)
        PaintArrow(1, 1, 1, 0.7)
        title:SetTextColor(1, 1, 1)
    end)
    bar:SetScript("OnClick", function()
        record.collapsed = (not collapsed) and true or nil
        CludesUI:RefreshPage(true)
    end)
    return cursorY - H - (collapsed and 0 or 4), not collapsed
end
