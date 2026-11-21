if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_Macros_Options.lua
--  Builds the "Macros" page inside the Forever Essentials module: the Macro
--  Manager. Its Enable Macro Manager row heads the page; while it is on, the
--  content header holds a centered dropdown (Account Macros / Character
--  Macros) over that list's macros as centered icons, and the page below
--  holds the selected macro's settings, its lines and the macro text. The
--  model (builder, parser, spellbook, macro access) is
--  CUI_ForeverEssentials_MacroModel_Options.lua.
--
--  Structural edits rebuild the page (RefreshPage(true)); value edits refresh
--  widgets in place; a macro change repaints the header alone unless the
--  macro being edited changed. The icon grid is built once and re-parented
--  into each header: a list holds up to 120 macros.
-------------------------------------------------------------------------------
if not CludesUI._ModuleNS["CludesUIForeverEssentials"] then return end -- module disabled: no options page

local floor, max, min = math.floor, math.max, math.min
local Pix = CludesUI.PanelPP
local SolidTex = CludesUI.SolidTex
local MakeFont = CludesUI.MakeFont
local MakeBorder = CludesUI.MakeBorder
local MODEL = CludesUI._ModuleNS["CludesUIForeverEssentials"]._MacroModel
local B, S, MM = MODEL.B, MODEL.S, MODEL.MM
-- Page reuse: the frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua, the options addon's first file), which hands a
-- kept page its previous build's frames back reset to new; on any other
-- parent it is the plain CreateFrame. The page's event frame, kept across
-- builds, leaves the pool once made (Pool.Keep); the header's icon grid is
-- never pooled (LayoutGrid); deferred work on a pooled frame checks its
-- dress (Pool.Gen).
local CreateFrame = CludesUI._Pool.CreateFrame
local PoolKeep, PoolGen = CludesUI._Pool.Keep, CludesUI._Pool.Gen

local function L(s) return CludesUI.L(s) end

local ICONS = "Interface\\AddOns\\CludesUI\\media\\icons\\"
local CELL = 46 -- icon grid step (42 icon + 4 gap)
local GRID_ROWS = 3 -- grid rows shown before it scrolls
local TEXT_H = 130 -- macro text block
local LIST_ORDER = { "account", "char" }
local TIP_LEFT = { justify = "LEFT" } -- tooltips that show macro text

local cur -- the macro being edited (survives rebuilds)
local mode = "account" -- the list in the header: account | char
local edCtx = { headers = {} }
local macroGrid, gridList = {}, {} -- the pooled icon grid and the list it shows
local D = {} -- widgets of the page on screen
local boxes = {} -- the text fields of the page on screen (set)
local statusText, statusBad -- the status line, kept across rebuilds
local builtFor, builtHadRef -- the editor state the page body was built for
local hdrFrame, hdrDD, hdrValues, hdrY, hdrW -- the header on screen, painted in place
local snap = { n = {}, i = {}, b = {} } -- both macro lists as the page last showed them
local evf, pendingEvent, pendingRebuild, textDirty, isShown, hiddenAt
local HeaderBuilder, CellClick, CellDrag

local function RebuildPage() CludesUI:RefreshPage(true) end
local function Refresh() CludesUI:RefreshPage() end

local function Accent() return CludesUI.CLUDES_GREEN end

local function IconPath(icon)
    if type(icon) == "string" and not icon:find("\\", 1, true) then return "Interface\\Icons\\" .. icon end
    return icon or MM.QUESTION
end

-------------------------------------------------------------------------------
--  Shared parts
-------------------------------------------------------------------------------
-- Small icon button (row move / remove glyphs).
local function Glyph(hostFrame, size, file, onClick, tipText)
    local widget = CreateFrame("Button", nil, hostFrame)
    widget:SetSize(size, size)
    widget:SetFrameLevel(hostFrame:GetFrameLevel() + 6)
    local tex = widget:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    if file then tex:SetTexture(ICONS .. file) end
    widget.tex = tex
    widget:SetAlpha(0.5)
    widget:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self:SetAlpha(0.9) end
        if tipText then CludesUI.ShowWidgetTooltip(self, tipText) end
    end)
    widget:SetScript("OnLeave", function(self)
        self:SetAlpha(self:IsEnabled() and 0.5 or 0.15)
        if tipText then CludesUI.HideWidgetTooltip() end
    end)
    widget:SetScript("OnEnable", function(self) self:SetAlpha(0.5) end)
    widget:SetScript("OnDisable", function(self) self:SetAlpha(0.15) end)
    widget:SetScript("OnClick", onClick)
    return widget
end

-- A scroll inside the page: Shift + wheel scales the panel, and the wheel goes
-- on to the page while there is nothing to scroll.
local function AttachScroll(scroll, childFrame)
    return CludesUI.AttachSmoothScrollbar(scroll, {
        step = 60,
        thumbMin = 20,
        rightInset = 0,
        topInset = 2,
        level = 5,
        trackAlpha = 0.05,
        thumbAlpha = 0.22,
        child = childFrame,
        panelWheel = true,
        passWheel = true,
    })
end

local function PaintCounter(fontStr, num)
    fontStr:SetText(num .. " / " .. MM.MAX_LETTERS)
    if num > MM.MAX_LETTERS then
        fontStr:SetTextColor(1, 0.35, 0.35, 1)
    elseif num > MM.MAX_LETTERS - 25 then
        local ac = Accent()
        fontStr:SetTextColor(ac.r, ac.g, ac.b, 1)
    else
        fontStr:SetTextColor(1, 1, 1, CludesUI.TEXT_DIM_A)
    end
end

-- Multi-line macro text box (input popup look). box.onChange(text, user),
-- box.onBlur().
local function TextBox(hostFrame, wid, height)
    local boxFrame = CreateFrame("Frame", nil, hostFrame)
    boxFrame:SetSize(wid, height)
    local boxBg = SolidTex(boxFrame, "BACKGROUND", 0, 0, 0, 0.5)
    boxBg:SetAllPoints()
    local brd = CludesUI.MakeRoundedBorder(boxFrame, 1, 1, 1, 0.2, boxBg)
    local scrollFrame = CreateFrame("ScrollFrame", nil, boxFrame)
    scrollFrame:SetPoint("TOPLEFT", 10, -8)
    scrollFrame:SetSize(wid - 22, height - 16)
    scrollFrame:SetClipsChildren(true)
    local e = CreateFrame("EditBox", nil, scrollFrame)
    boxes[e] = true
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFont(CludesUI.EXPRESSWAY, 12, "")
    e:SetTextColor(1, 1, 1, 0.9)
    e:SetSpacing(3)
    e:SetSize(wid - 26, 20)
    scrollFrame:SetScrollChild(e)
    local update = AttachScroll(scrollFrame, e)
    e:SetScript("OnSizeChanged", function() update() end)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnCursorChanged", function(_, _, cursorY, _, ch)
        cursorY = -cursorY
        local topY, vh = scrollFrame:GetVerticalScroll(), scrollFrame:GetHeight()
        if cursorY < topY then
            scrollFrame:SetVerticalScroll(cursorY)
        elseif cursorY + ch > topY + vh then
            scrollFrame:SetVerticalScroll(cursorY + ch - vh)
        end
        update()
    end)
    e:SetScript("OnTextChanged", function(self, user)
        if boxFrame.onChange then boxFrame.onChange(self:GetText(), user) end
    end)
    e:SetScript("OnEditFocusGained", function()
        local ac = Accent()
        brd:SetColor(ac.r, ac.g, ac.b, 0.8)
    end)
    e:SetScript("OnEditFocusLost", function()
        brd:SetColor(1, 1, 1, 0.2)
        if boxFrame.onBlur then boxFrame.onBlur() end
    end)
    boxFrame:EnableMouse(true)
    boxFrame:SetScript("OnMouseDown", function()
        e:SetFocus()
        e:SetCursorPosition(#(e:GetText() or ""))
    end)
    function boxFrame.SetText(_, t) e:SetText(t or "") end
    return boxFrame
end

-- Info line, counter and text box as one block of the page.
local function TextBlock(hostFrame, cursorY)
    local pad = CludesUI.CONTENT_PAD
    local wid = hostFrame:GetWidth() - pad * 2
    local frame = CreateFrame("Frame", nil, hostFrame)
    frame:SetSize(wid, TEXT_H)
    frame:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", pad, cursorY)
    local details = MakeFont(frame, 11, nil, 1, 1, 1, CludesUI.TEXT_DIM_A)
    details:SetPoint("TOPLEFT", 0, -8)
    local total = MakeFont(frame, 11, nil, 1, 1, 1, CludesUI.TEXT_DIM_A)
    total:SetPoint("TOPRIGHT", 0, -8)
    details:SetPoint("RIGHT", total, "LEFT", -12, 0)
    details:SetJustifyH("LEFT")
    details:SetWordWrap(false)
    local boxFrame = TextBox(frame, wid, TEXT_H - 30)
    boxFrame:SetPoint("TOPLEFT", 0, -26)
    return boxFrame, total, details
end

-- Icon cell of the macro grid. Its scripts read the cell when they run: c.m
-- (the macro it shows) or c.newCell (the "+" cell).
local function NewCell(hostFrame)
    local c = CreateFrame("Button", nil, hostFrame)
    c:SetSize(CELL - 4, CELL - 4)
    c:SetFrameLevel(hostFrame:GetFrameLevel() + 1)
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c:RegisterForDrag("LeftButton")
    SolidTex(c, "BACKGROUND", 0, 0, 0, 0.5):SetAllPoints()
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 1, -1)
    c.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.plus = MakeFont(c, 22, nil, 1, 1, 1, 0.45)
    c.plus:SetPoint("CENTER", 0, 1)
    c.plus:SetText("+")
    c.name = c:CreateFontString(nil, "OVERLAY")
    c.name:SetFont(CludesUI.EXPRESSWAY, 9, "OUTLINE")
    c.name:SetPoint("BOTTOMLEFT", 2, 3)
    c.name:SetPoint("BOTTOMRIGHT", -2, 3)
    c.name:SetJustifyH("CENTER")
    c.name:SetWordWrap(false)
    c.brd = MakeBorder(c, 0, 0, 0, 1, Pix)
    function c.Paint(hover)
        if c.selected then
            local ac = Accent()
            c.brd:SetColor(ac.r, ac.g, ac.b, 1)
        elseif hover then
            c.brd:SetColor(1, 1, 1, 0.5)
        else
            c.brd:SetColor(0, 0, 0, 1)
        end
    end
    c:SetScript("OnEnter", function(self)
        self.Paint(true)
        local m = self.m
        local tipText = m and (m.name .. "\n\n" .. m.body) or (self.newCell and CludesUI.L("New Macro"))
        if tipText then CludesUI.ShowWidgetTooltip(self, tipText, TIP_LEFT) end
    end)
    c:SetScript("OnLeave", function(self)
        self.Paint(false)
        CludesUI.HideWidgetTooltip()
    end)
    c:SetScript("OnClick", CellClick)
    c:SetScript("OnDragStart", CellDrag)
    return c
end

-------------------------------------------------------------------------------
--  Spell suggestions under a text field: the spellbook through the shared
--  context menu, picked on the press (the field loses its focus on a mouse
--  down outside it). The list closes with the field's focus, so the menu runs
--  no click-outside poll. list = true completes the last entry of a comma list.
-------------------------------------------------------------------------------
local SUGGEST_OPTS = { below = true, scaleToAnchor = true, pickOnDown = true, noPoll = true }
local suggestPool, suggestShown = {}, {} -- pooled items; the ones on screen
local suggestPick, suggestOwner

local function SuggestItem(idx)
    local it = suggestPool[idx]
    if not it then
        it = { noLoc = true }
        it.onClick = function()
            if suggestPick then suggestPick(it.text) end
        end
        suggestPool[idx] = it
    end
    return it
end

local function HideSuggest()
    if suggestOwner and CludesUI.ContextMenuOwner() == suggestOwner then CludesUI.CloseContextMenu() end
    suggestOwner = nil
end

local function AttachSuggest(boxFrame, onPick, entries)
    local function Pick(name)
        HideSuggest()
        local t = name
        if entries then
            local head = (boxFrame:GetText() or ""):match("^(.*,)") or ""
            t = (head ~= "" and (head .. " ") or "") .. name
        end
        boxFrame:SetText(t)
        onPick(t)
        boxFrame:ClearFocus()
    end
    local function Show()
        local q = boxFrame:GetText() or ""
        if entries then q = q:match("([^,]*)$") or "" end
        q = strtrim(q):lower()
        wipe(suggestShown)
        for _, s in ipairs(S.Sorted()) do
            if q == "" or s.lname:find(q, 1, true) then
                local it = SuggestItem(#suggestShown + 1)
                it.text, it.icon = s.name, s.icon or MM.QUESTION
                suggestShown[#suggestShown + 1] = it
                if #suggestShown >= 10 then break end
            end
        end
        if #suggestShown == 0 or (#suggestShown == 1 and suggestShown[1].text:lower() == q) then
            HideSuggest()
            return
        end
        suggestPick, suggestOwner = Pick, boxFrame
        SUGGEST_OPTS.minWidth = max(boxFrame:GetWidth(), 220)
        CludesUI.CloseContextMenu() -- a second call from the same anchor would close it
        CludesUI.ShowContextMenu(boxFrame, suggestShown, SUGGEST_OPTS)
    end
    boxFrame:HookScript("OnTextChanged", function(_, user)
        if user then Show() end
    end)
    boxFrame:HookScript("OnEditFocusGained", Show)
    -- A plain mouse down drops the box's focus before a row of the list gets
    -- that press (a modified click keeps the focus), so the list closes a frame
    -- later: a pick on it still lands, a press anywhere else still closes it.
    -- A page rebuild in between may dress the box again: the close then
    -- belongs to the old dress and does nothing.
    local dressGen = PoolGen(boxFrame)
    local function CloseIfUnfocused()
        if PoolGen(boxFrame) ~= dressGen then return end
        if suggestOwner == boxFrame and not boxFrame:HasFocus() then HideSuggest() end
    end
    boxFrame:HookScript("OnEditFocusLost", function()
        if CludesUI.ContextMenuOwner() == boxFrame then C_Timer.After(0, CloseIfUnfocused) end
    end)
    boxFrame:HookScript("OnTabPressed", function()
        if CludesUI.ContextMenuOwner() == boxFrame and suggestShown[1] then Pick(suggestShown[1].text) end
    end)
end

-------------------------------------------------------------------------------
--  Icon picker (popup shell): "?" first, then this open's spellbook icons,
--  then every macro icon the game offers, read once per session (repeats
--  allowed, as in Blizzard's own list). Never Blizzard's
--  IconDataProviderMixin: driven from here it would write the file state
--  Blizzard's macro window shares and force a full collect.
-------------------------------------------------------------------------------
local picker, baseIcons

local function PickerIcon(idx)
    if idx == 1 then return MM.QUESTION end
    local spells = picker.spells
    if idx - 1 <= #spells then return spells[idx - 1] end
    return baseIcons[idx - 1 - #spells]
end

local function PickerClick(self)
    local onPick = picker.onPick
    picker.Close()
    if onPick then onPick(self.value) end
end

local function OpenPicker(onPick)
    local COLS, ROWS, SIZE = 10, 6, 40
    if not picker then
        local p = {}
        function p.Close()
            p.dimmer:Hide()
            p.spells, p.onPick = nil, nil -- the spell list lives only while it is open
        end
        p.dimmer, p.popup = CludesUI.BuildPopupShell("CUIMacroIconPicker", {
            w = COLS * SIZE + 40,
            h = ROWS * SIZE + 132,
            bump = 1,
            onEscape = p.Close,
            onDimmerDown = p.Close,
        })
        local dialog = p.popup
        local title = MakeFont(dialog, 16, "", 1, 1, 1)
        title:SetPoint("TOP", dialog, "TOP", 0, -20)
        title:SetText(CludesUI.L("Choose Icon"))
        local subMenu = MakeFont(dialog, 12, nil, 1, 1, 1, CludesUI.TEXT_DIM_A)
        subMenu:SetPoint("TOP", title, "BOTTOM", 0, -8)
        subMenu:SetText(CludesUI.L("The question mark shows the spell's icon (with #showtooltip)."))
        p.buttons = {}
        for idx = 1, COLS * ROWS do
            local widget = NewCell(dialog)
            widget:SetSize(SIZE - 4, SIZE - 4)
            widget:SetFrameLevel(dialog:GetFrameLevel() + 2) -- above the scroll frame below
            widget:SetPoint("TOPLEFT", 20 + ((idx - 1) % COLS) * SIZE, -70 - floor((idx - 1) / COLS) * SIZE)
            -- Left clicks only, and no drag: a drag would swallow the click.
            widget:RegisterForClicks("LeftButtonUp")
            widget:RegisterForDrag()
            widget.plus:Hide()
            widget:SetScript("OnClick", PickerClick)
            p.buttons[idx] = widget
        end
        -- The shared scroll bar on an empty scroll frame under the grid: its
        -- child is as tall as every icon row, and the scroll value picks the
        -- first row the grid shows (the grid itself stays put).
        local scrollFrame = CreateFrame("ScrollFrame", nil, dialog)
        scrollFrame:SetFrameLevel(dialog:GetFrameLevel() + 1)
        scrollFrame:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -70)
        scrollFrame:SetSize(COLS * SIZE + 12, ROWS * SIZE)
        p.child = CreateFrame("Frame", nil, scrollFrame)
        p.child:SetSize(COLS * SIZE, ROWS * SIZE)
        scrollFrame:SetScrollChild(p.child)
        p.updateThumb, p.scrollTo = CludesUI.AttachSmoothScrollbar(scrollFrame, {
            step = SIZE,
            child = p.child,
            onScroll = function(val)
                local off = floor(val / SIZE + 0.5) * COLS
                if off ~= p.offset then
                    p.offset = off
                    p.Update()
                end
            end,
        })
        function p.Update()
            for idx, btn in ipairs(p.buttons) do
                local icon = PickerIcon(p.offset + idx)
                btn.value = icon
                if icon then
                    btn.icon:SetTexture(IconPath(icon))
                    btn.selected = icon == p.current
                    btn.Paint(false)
                    btn:Show()
                else
                    btn:Hide()
                end
            end
        end
        p.cancel = CludesUI.MakePopupButton(
            dialog,
            "BOTTOM",
            dialog,
            "BOTTOM",
            0,
            18,
            1,
            1,
            1,
            0.75,
            1,
            1,
            1,
            1,
            1,
            1,
            1,
            0.25,
            1,
            1,
            1,
            0.5
        )
        p.cancel._lbl:SetText(CludesUI.L("Cancel"))
        p.cancel:SetScript("OnClick", p.Close)
        picker = p
    end
    if not baseIcons then
        baseIcons = {}
        GetLooseMacroIcons(baseIcons)
        GetLooseMacroItemIcons(baseIcons)
        GetMacroIcons(baseIcons)
        GetMacroItemIcons(baseIcons)
    end
    local spells, seen = {}, {}
    for _, s in ipairs(S.List()) do
        if s.icon and not seen[s.icon] then
            seen[s.icon] = true
            spells[#spells + 1] = s.icon
        end
    end
    picker.spells, picker.offset, picker.onPick, picker.current = spells, 0, onPick, cur.icon
    picker.cancel._resetAnim()
    picker.Update()
    picker.dimmer:Show()
    -- The bar's range: one row per COLS icons, back at the top on every open.
    picker.child:SetHeight(math.ceil((1 + #spells + #baseIcons) / COLS) * SIZE)
    picker.scrollTo(0)
    picker.updateThumb()
end

-------------------------------------------------------------------------------
--  Dropdown value tables
-------------------------------------------------------------------------------
-- Line types in one flyout per group (the { group } rows of B.KINDS). The
-- groups' lists are built once; onSelect(kind) belongs to each menu. A hidden
-- kind is in its group's values but not its order: a line read as one shows
-- its label, and the menu never offers it.
local kindGroups
local function KindValues(onSelect)
    if not kindGroups then
        kindGroups = {}
        local g
        for _, keyName in ipairs(B.KINDS) do
            if keyName.group then
                g = { key = "group" .. (#kindGroups + 1), text = keyName.group, values = {}, order = {} }
                kindGroups[#kindGroups + 1] = g
            else
                g.values[keyName.key] = keyName.label
                if not keyName.hidden then g.order[#g.order + 1] = keyName.key end
            end
        end
    end
    local values, sequence = { __pick = "Choose a type" }, {}
    for idx, group in ipairs(kindGroups) do
        values[group.key] = {
            text = group.text,
            subnav = { values = group.values, order = group.order, onSelect = onSelect },
        }
        sequence[idx] = group.key
    end
    return values, sequence
end

-- { { value, label } } -> values, order; sentinel stands in for an empty value.
local function ListValues(entries, sentinel)
    local values, sequence = {}, {}
    for _, it in ipairs(entries) do
        local keyName = it.value == "" and sentinel or it.value
        values[keyName] = it.label
        sequence[#sequence + 1] = keyName
    end
    return values, sequence
end

-- Channel and target lists once; stances once per page build.
local chanV, chanO, targV, targO, stanceV, stanceO

-------------------------------------------------------------------------------
--  Line editor.
--  ctx: model, open (the expanded line), headers, onChange(structural, clean)
-------------------------------------------------------------------------------
-- Two lanes per condition, as the Show / Hide menus: [cond] left, [nocond]
-- right. Conditions with a value follow under their own header ("p:" keys).
local COND_ITEMS
local function CondItems()
    if not COND_ITEMS then
        COND_ITEMS = { { isHeader = true, label = "Condition", rightLabel = "Not" } }
        for _, d in ipairs(B.CONDS) do
            COND_ITEMS[#COND_ITEMS + 1] = {
                key = d.key,
                label = d.label,
                dual = true,
                tooltip = "[" .. d.key .. "] / [no" .. d.key .. "]  " .. L(d.tip),
            }
        end
        COND_ITEMS[#COND_ITEMS + 1] = { isHeader = true, label = "With a Value", rightLabel = "Not" }
        for _, p in ipairs(B.PARAMS) do
            COND_ITEMS[#COND_ITEMS + 1] = {
                key = "p:" .. p.key,
                label = p.label,
                dual = true,
                tooltip = "[" .. p.key .. ":...]  " .. L(p.tip),
            }
        end
    end
    return COND_ITEMS
end

local function FindParam(val, key)
    for jdx, prm in ipairs(val.params) do
        if prm.key == key then return prm, jdx end
    end
end

-- Multi-select value: "a/b" holds every picked option.
local function HasValue(value, opt)
    for part in (value or ""):gmatch("[^/]+") do
        if part == opt then return true end
    end
end

local function LineCode(idx, l)
    local code = B.LineText(l)
    if code == "" then code = CludesUI.L("(empty line)") end
    return idx .. ".  " .. code
end

local function SetKind(l, kind)
    local K = B.KIND[kind]
    l.kind = kind
    if not K.multi then
        while #l.variants > 1 do
            table.remove(l.variants)
        end
    end
    if not K.arg then
        for _, val in ipairs(l.variants) do
            val.arg = ""
        end
    end
    if kind == "targetmarker" and not (l.variants[1].arg or ""):match("^[0-8]$") then
        l.variants[1].arg = "8"
    end
end

-- A line as one row: its code, then move and remove; a click opens it.
local function LineHeader(body, cursorY, context, idx, l)
    local W = CludesUI.Widgets
    local lines = context.model.lines
    local open = context.open == l
    local row, height = W:DualRow(body, cursorY, { type = "label", text = LineCode(idx, l) })
    local region = row._leftRegion
    local labelText = region._label
    labelText:SetFont(CludesUI.EXPRESSWAY, 13, "")
    context.headers[#context.headers + 1] = { fs = labelText, i = idx, l = l }
    if open then
        local ac = Accent()
        local bar = row:CreateTexture(nil, "ARTWORK", nil, 2)
        bar:SetColorTexture(ac.r, ac.g, ac.b, 1)
        bar:SetPoint("TOPLEFT")
        bar:SetPoint("BOTTOMLEFT")
        bar:SetWidth(2)
    end

    local del = Glyph(region, 16, nil, function()
        table.remove(lines, idx)
        if open then context.open = nil end
        context.onChange(true)
    end, CludesUI.L("Remove line"))
    CludesUI.SetDeleteIcon(del.tex)
    del:SetPoint("RIGHT", region, "RIGHT", -20, 0)
    local function Move(d)
        local jdx = idx + d
        lines[idx], lines[jdx] = lines[jdx], lines[idx]
        context.onChange(true)
    end
    local down = Glyph(region, 18, "cui-arrow-down3.png", function() Move(1) end, CludesUI.L("Move down"))
    down:SetPoint("RIGHT", del, "LEFT", -14, 0)
    down:SetEnabled(idx < #lines)
    local up = Glyph(region, 18, "cui-arrow-up3.png", function() Move(-1) end, CludesUI.L("Move up"))
    up:SetPoint("RIGHT", down, "LEFT", -2, 0)
    up:SetEnabled(idx > 1)
    labelText:SetPoint("RIGHT", up, "LEFT", -12, 0)

    local hit = CreateFrame("Button", nil, row)
    hit:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    hit:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -100, 0)
    hit:SetFrameLevel(region:GetFrameLevel() + 3)
    local highlight = SolidTex(hit, "BACKGROUND", 1, 1, 1, 0)
    highlight:SetAllPoints(row)
    local K = B.KIND[l.kind] or B.KIND.raw
    hit:SetScript("OnEnter", function(self)
        highlight:SetColorTexture(1, 1, 1, 0.03)
        CludesUI.ShowWidgetTooltip(
            self,
            L(K.label)
                .. "\n"
                .. L(K.desc)
                .. "\n\n"
                .. (open and CludesUI.L("Click to close.") or CludesUI.L("Click to edit."))
        )
    end)
    hit:SetScript("OnLeave", function()
        highlight:SetColorTexture(1, 1, 1, 0)
        CludesUI.HideWidgetTooltip()
    end)
    hit:SetScript("OnClick", function()
        context.open = (not open) and l or nil
        context.onChange(true, true)
    end)
    return cursorY - height
end

-- What a DualRow cannot build itself: checkbox dropdowns, suggestions, inline buttons.
local function PostCell(region, rowConf)
    if not rowConf then return end
    if rowConf.type == "input" and region._control then boxes[region._control] = true end
    if rowConf._cb then
        if region._control then region._control:Hide() end
        local checkBtn = rowConf._cb
        local dropdown, refresh = CludesUI.BuildVisOptsCBDropdown(
            region,
            170,
            region:GetFrameLevel() + 2,
            checkBtn.items,
            checkBtn.get,
            checkBtn.set,
            nil,
            14,
            nil,
            nil,
            checkBtn.onClosed,
            { noAllLabel = true }
        )
        Pix.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
        region._control = dropdown
        CludesUI.RegisterWidgetRefresh(refresh)
    end
    if rowConf._suggest and region._control then
        AttachSuggest(region._control, rowConf.setValue, rowConf._suggest == "list")
    end
    if rowConf._maxLetters and region._control then region._control:SetMaxLetters(rowConf._maxLetters) end
    if rowConf._remove then
        CludesUI.BuildInlineButton(region, CludesUI.L("Remove"), rowConf._remove, { width = 80 })
    end
    if rowConf._icon and region._control then
        local texture = region:CreateTexture(nil, "ARTWORK")
        texture:SetSize(28, 28)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        Pix.Point(texture, "RIGHT", region._control, "LEFT", -10, 0)
        texture:SetTexture(IconPath(rowConf._icon()))
        CludesUI.RegisterWidgetRefresh(function() texture:SetTexture(IconPath(rowConf._icon())) end)
    end
end

-- Cells two per row, filled left to right.
local function EmitCells(body, cursorY, cells)
    local W = CludesUI.Widgets
    for idx = 1, #cells, 2 do
        local a, b = cells[idx], cells[idx + 1]
        local row, height = W:DualRow(body, cursorY, a, b or CludesUI.BlankRowCfg())
        PostCell(row._leftRegion, a)
        PostCell(row._rightRegion, b)
        cursorY = cursorY - height
    end
    return cursorY
end

local function Input(textValue, get, set, opts)
    opts = opts or {}
    return {
        type = "input",
        text = textValue,
        inputStyle = "popup",
        inputWidth = opts.width or 200,
        placeholder = opts.ph,
        tooltip = opts.tip,
        disabled = opts.disabled,
        disabledTooltip = opts.disabledTooltip,
        getValue = get,
        -- Every focus loss commits: an unchanged text is no edit.
        setValue = function(t)
            if t ~= (get() or "") then set(t) end
        end,
        _suggest = opts.suggest,
        _maxLetters = opts.maxLetters,
    }
end

local function Dropdown(textValue, values, sequence, get, set, tipText)
    return {
        type = "dropdown",
        text = textValue,
        values = values,
        order = sequence,
        getValue = get,
        setValue = set,
        tooltip = tipText,
    }
end

-- Raid markers 1-8 with their icons, 0 clears.
local MARKER_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local MARKER_ORDER = { "1", "2", "3", "4", "5", "6", "7", "8", "0" }
local markerValues
local function MarkerValues()
    if not markerValues then
        markerValues = { _noLoc = true, ["0"] = CludesUI.L("Clear Marker") }
        for idx = 1, 8 do
            markerValues[tostring(idx)] = _G["RAID_TARGET_" .. idx]
        end
        markerValues._menuOpts = {
            icon = function(key)
                local idx = tonumber(key)
                if not idx or idx < 1 then return nil end
                local l, t = ((idx - 1) % 4) * 0.25, floor((idx - 1) / 4) * 0.25
                return MARKER_ICONS, l, l + 0.25, t, t + 0.25
            end,
        }
    end
    return markerValues
end

-- The settings of one line (and of each of its variants).
local function LineRows(body, cursorY, context, l)
    local K = B.KIND[l.kind] or B.KIND.raw
    local cells = {}
    local function Add(c) cells[#cells + 1] = c end
    local function NotifyChange() context.onChange(false) end
    local v1 = l.variants[1]

    local kv, ko = KindValues(function(keyName)
        SetKind(l, keyName)
        context.onChange(true)
    end)
    Add(Dropdown("Type", kv, ko, function() return l.kind end, function() end, K.desc))

    if K.key == "chat" then
        Add(Input("Message", function() return v1.arg end, function(t)
            v1.arg = t
            NotifyChange()
        end, { ph = K.ph }))
        if not chanV then
            chanV, chanO = ListValues(B.CHANNELS)
        end
        Add(Dropdown("Channel", chanV, chanO, function() return l.chan end, function(c)
            l.chan = c
            NotifyChange()
        end))
    elseif K.arg == "spells" then
        Add(Input("Spells", function() return v1.arg end, function(t)
            v1.arg = t
            NotifyChange()
        end, { ph = K.ph or "Spell1, Spell2, Spell3", suggest = "list" }))
        if K.reset then
            Add(Input("Reset", function() return l.reset end, function(t)
                l.reset = t
                NotifyChange()
            end, {
                ph = "target/combat/8",
                tip = "When the sequence starts over: target (target change), combat (leaving combat), shift/ctrl/alt or seconds. Separate several with /.",
            }))
        end
    end

    local total = K.conds and (K.multi and #l.variants or 1)
        or ((K.arg and K.arg ~= "spells" and K.key ~= "chat") and 1 or 0)
    for keyName = 1, total do
        local val = l.variants[keyName]
        if keyName > 1 then
            Add({
                type = "label",
                text = CludesUI.Lf("Else: Variant %d", keyName),
                tooltip = "Variants are checked top to bottom: the first one whose conditions match is used. A variant without conditions is the fallback.",
                _remove = function()
                    table.remove(l.variants, keyName)
                    context.onChange(true)
                end,
            })
        end
        if K.key == "targetmarker" then
            Add(Dropdown("Marker", MarkerValues(), MARKER_ORDER, function() return val.arg end, function(m)
                val.arg = m
                NotifyChange()
            end))
        elseif K.arg and K.arg ~= "spells" and K.key ~= "chat" then
            local textValue = K.arg == "spell" and "Spell" or (K.arg == "unit" and "Unit or Name" or "Text")
            Add(Input(textValue, function() return val.arg end, function(t)
                val.arg = t
                NotifyChange()
            end, { ph = K.ph, suggest = K.arg == "spell" or nil }))
        end
        if K.conds then
            if not targV then
                targV, targO = ListValues(B.TARGETS, "none")
            end
            Add(
                Dropdown(
                    "Target",
                    targV,
                    targO,
                    function() return val.target ~= "" and val.target or "none" end,
                    function(t)
                        val.target = t == "none" and "" or t
                        NotifyChange()
                    end
                )
            )
            if not stanceV then
                stanceV, stanceO = ListValues(B.Stances(), "any")
            end
            Add(
                Dropdown(
                    "Stance",
                    stanceV,
                    stanceO,
                    function() return val.stance ~= "" and val.stance or "any" end,
                    function(s)
                        val.stance = s == "any" and "" or s
                        NotifyChange()
                    end,
                    "Numbers follow your stance bar; 0 = no stance or normal form."
                )
            )
            -- Checking a condition with a value adds its value row, and Not
            -- renames it ("not ..."): the page rebuilds once the menu closes.
            local addedRows
            local cond = Dropdown(
                "Conditions",
                { _p = "" },
                { "_p" },
                function() return "_p" end,
                function() end,
                "The line only runs while the left ones are true and the right (Not) ones are false."
            )
            cond._cb = {
                items = CondItems(),
                get = function(key, neg)
                    local pk = key:match("^p:(.+)$")
                    if pk then
                        local prm = FindParam(val, pk)
                        return prm ~= nil and (prm.no == true) == (neg == true)
                    end
                    return val.conds[key] == (neg and 2 or 1)
                end,
                set = function(key, on, neg)
                    local pk = key:match("^p:(.+)$")
                    if pk then
                        local prm, jdx = FindParam(val, pk)
                        if on then
                            if not prm then
                                prm = B.NewParam(pk)
                                val.params[#val.params + 1] = prm
                                addedRows = true
                            end
                            if (prm.no == true) ~= (neg == true) then addedRows = true end
                            prm.no = neg == true
                        elseif prm and (prm.no == true) == (neg == true) then
                            table.remove(val.params, jdx)
                            addedRows = true
                        end
                    else
                        local mark = neg and 2 or 1
                        if on then
                            val.conds[key] = mark
                        elseif val.conds[key] == mark then
                            val.conds[key] = nil
                        end
                    end
                    NotifyChange()
                end,
                onClosed = function()
                    if addedRows then
                        addedRows = nil
                        context.onChange(true)
                    end
                end,
            }
            Add(cond)

            -- One value row per condition with a value.
            for _, prm in ipairs(val.params) do
                local P = B.PARAM[prm.key] or {}
                local textValue = (prm.no and (L("not") .. " ") or "") .. L(P.label or prm.key)
                local function SetVal(t)
                    prm.value = t
                    NotifyChange()
                end
                if P.options then
                    local opts = P.options()
                    local itemList = {}
                    for idx, o in ipairs(opts) do
                        itemList[idx] = { key = o.value, label = o.label }
                    end
                    local cell = Dropdown(
                        textValue,
                        { _p = "" },
                        { "_p" },
                        function() return "_p" end,
                        function() end,
                        P.tip
                    )
                    cell._cb = {
                        items = itemList,
                        get = function(key) return HasValue(prm.value, key) end,
                        set = function(key, on)
                            local result = {}
                            for _, o in ipairs(opts) do
                                local keep = o.value == key and on
                                    or (o.value ~= key and HasValue(prm.value, o.value))
                                if keep then result[#result + 1] = o.value end
                            end
                            SetVal(table.concat(result, "/"))
                        end,
                    }
                    Add(cell)
                elseif P.spell then
                    Add(Input(textValue, function() return prm.value end, SetVal, {
                        suggest = true,
                        tip = P.tip,
                        ph = "Spell (several: Spell1/Spell2)",
                    }))
                else
                    Add(
                        Input(
                            textValue,
                            function() return prm.value end,
                            SetVal,
                            { ph = P.text, tip = P.tip }
                        )
                    )
                end
            end
        end
    end
    if K.multi then
        Add({
            type = "button",
            text = "+ Add Else Variant",
            width = 200,
            onClick = function()
                local last = l.variants[#l.variants]
                l.variants[#l.variants + 1] = B.NewVariant(last and last.arg or "")
                context.onChange(true)
            end,
        })
    end
    return EmitCells(body, cursorY, cells)
end

local function BuildLines(body, cursorY, context)
    local W = CludesUI.Widgets
    local _, height = W:SectionHeader(body, "LINES", cursorY)
    cursorY = cursorY - height
    local kv, ko = KindValues(function(keyName)
        local l = B.NewLine(keyName)
        table.insert(context.model.lines, l)
        context.open = l
        context.onChange(true)
    end)
    _, height = W:DualRow(
        body,
        cursorY,
        Dropdown(
            "Add Line",
            kv,
            ko,
            function() return "__pick" end,
            function() end,
            "Adds a line to the macro. Lines run top to bottom."
        ),
        CludesUI.BlankRowCfg()
    )
    cursorY = cursorY - height
    wipe(context.headers)
    local found = false
    for idx, l in ipairs(context.model.lines) do
        cursorY = LineHeader(body, cursorY, context, idx, l)
        if context.open == l then
            found = true
            cursorY = LineRows(body, cursorY, context, l)
        end
    end
    if not found then context.open = nil end
    return cursorY
end

-- Header code labels follow value edits without a rebuild.
local function UpdateHeaders(context)
    for _, hd in ipairs(context.headers) do
        hd.fs:SetText(LineCode(hd.i, hd.l))
    end
end

-------------------------------------------------------------------------------
--  Editor state
-------------------------------------------------------------------------------
local function NewState(perChar)
    return {
        perChar = perChar and true or false,
        name = "",
        icon = MM.QUESTION,
        model = B.New(),
        text = "#showtooltip",
        dirty = false,
        nameTouched = false,
    }
end

-- m: a macro entry; it becomes the editor's ref, the identity every write checks.
local function StateOf(m)
    return {
        ref = m,
        perChar = m.perChar,
        name = m.name,
        icon = MM.StoredIcon(m.index),
        model = B.Parse(m.body),
        text = m.body,
        dirty = false,
        nameTouched = true,
    }
end

-- The page's text field with the keyboard focus commits now, to the macro it
-- was typed for: a click with a modifier held keeps the focus, so its commit
-- would otherwise land on whatever the editor holds next. Only while the page
-- is on screen (a rebuild under way commits nothing), and only the page's own
-- fields: a focused frame of the game or another addon is never touched.
local function FlushField()
    if not isShown then return end
    local frame = GetCurrentKeyBoardFocus()
    if frame and boxes[frame] then frame:ClearFocus() end
end

-- Another macro in the editor: a value typed for the last one commits to it
-- first; then no open line, no status and no unread typed text remain.
local function SetCur(status)
    FlushField()
    cur, statusText, statusBad, edCtx.open, textDirty = status, nil, nil, nil, nil
end

local function Guard(func)
    if cur and cur.dirty then
        CludesUI:ShowConfirmPopup({
            title = CludesUI.L("Unsaved Changes"),
            message = CludesUI.L("Discard your unsaved changes to this macro?"),
            confirmText = CludesUI.L("Discard"),
            cancelText = CludesUI.L("Cancel"),
            onConfirm = func,
        })
    else
        func()
    end
end

local function SetStatus(textValue, bad)
    statusText, statusBad = textValue, bad
    if not D.info then return end
    if bad then
        D.info:SetTextColor(1, 0.35, 0.35, 1)
    else
        local ac = Accent()
        D.info:SetTextColor(ac.r, ac.g, ac.b, 1)
    end
    D.info:SetText(textValue or "")
end

local function UpdateMacroText()
    cur.text = B.Build(cur.model)
    if D.text then D.text:SetText(cur.text) end
    if D.count then PaintCounter(D.count, strlenutf8(cur.text)) end
end

local function MarkUnsaved()
    cur.dirty = true
    SetStatus(CludesUI.L("Unsaved changes"))
end

local function RebuildIfPending()
    if isShown and pendingRebuild then
        pendingRebuild = nil
        RebuildPage()
    end
end

-- The lines are built again once the click under way is done, never from
-- inside a blur (the page may be mid-teardown).
local function RebuildAfterClick()
    pendingRebuild = true
    if IsMouseButtonDown() then
        evf:RegisterEvent("GLOBAL_MOUSE_UP")
    else
        C_Timer.After(0, RebuildIfPending)
    end
end

-- Typed macro text read into lines: on blur, at Save, on hide and before any
-- other edit (a modifier-held click keeps the text box focused, so it can
-- reach a control with the text unread). Returns true when it read.
local function ReadText()
    if not textDirty then return false end
    textDirty = nil
    cur.model = B.Parse(cur.text)
    edCtx.open = nil
    RebuildAfterClick()
    return true
end

-- A click on lines built before the text was read: refused, and said.
local function RefuseClick()
    SetStatus(CludesUI.L("The lines were rebuilt from the macro text. Click again."), true)
end

-- A setting of the macro changed. structural: the lines are built again;
-- clean: nothing to save (a line opened or closed).
local function ApplyEdit(structural, clean)
    if ReadText() then
        RefuseClick()
        return
    end
    if not clean then
        MarkUnsaved()
        if not cur.nameTouched and not cur.ref then cur.name = MM.CleanName(B.FirstSpell(cur.model)) end
    end
    UpdateMacroText()
    if structural then
        RebuildPage()
        return
    end
    UpdateHeaders(edCtx)
    Refresh()
end

-- The lines' widgets hold the line tables they were built with: until the
-- lines are built again after a text edit, their clicks are refused.
edCtx.onChange = function(structural, clean)
    if pendingRebuild then
        RefuseClick()
        return
    end
    ApplyEdit(structural, clean)
end

-------------------------------------------------------------------------------
--  The macro grid in the content header, centered row by row like the action
--  bar preview. Cells are pooled; the grid re-parents into each header.
-------------------------------------------------------------------------------
-- Places count cells centered in rows of w; bind(cell, i) fills each one.
-- Returns the grid's height.
local function LayoutGrid(g, heading, cursorY, wid, total, bind)
    if not g.frame then
        -- Kept for the session and never pooled (the global CreateFrame): the
        -- panel detaches it before each header build (a kept header root's
        -- CUI_NS.DropRootForeign, the plain header's clear) and it is
        -- re-parented below.
        local f = _G.CreateFrame("Frame", nil, heading)
        local scroll = CreateFrame("ScrollFrame", nil, f)
        scroll:SetAllPoints()
        scroll:SetClipsChildren(true)
        local childFrame = CreateFrame("Frame", nil, scroll)
        childFrame:SetSize(10, 10)
        scroll:SetScrollChild(childFrame)
        g.frame, g.child, g.cells = f, childFrame, {}
        g.update = AttachScroll(scroll, childFrame)
    end
    g.frame:SetParent(heading)
    local perRow = max(1, floor((wid + 4) / CELL))
    local rowList = math.ceil(total / perRow)
    local height = max(1, min(rowList, GRID_ROWS)) * CELL
    g.frame:ClearAllPoints()
    g.frame:SetPoint("TOP", heading, "TOP", 0, cursorY)
    g.frame:SetSize(wid, height)
    g.child:SetSize(wid, rowList * CELL)
    for idx = 1, total do
        local cell = g.cells[idx]
        if not cell then
            cell = NewCell(g.child)
            g.cells[idx] = cell
        end
        local row = floor((idx - 1) / perRow)
        local inRow = min(perRow, total - row * perRow)
        local posX = floor((wid - inRow * CELL) / 2) + ((idx - 1) % perRow) * CELL + 2
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", g.child, "TOPLEFT", posX, -row * CELL - 2)
        bind(cell, idx)
        cell:Show()
    end
    for idx = total + 1, #g.cells do
        g.cells[idx]:Hide()
    end
    g.frame:Show()
    g.update()
    return height
end

-- Fills cell i of the macro grid from gridList; past the list is the "+" cell.
local function BindMacroCell(cfg, idx)
    local m = gridList[idx]
    cfg.m, cfg.newCell = m, m == nil
    cfg.icon:SetShown(m ~= nil)
    cfg.plus:SetShown(m == nil)
    cfg.name:SetText(m and m.name or "")
    if m then
        cfg.icon:SetTexture(IconPath(m.icon))
        cfg.selected = cur.ref ~= nil and cur.ref.index == m.index
    else
        cfg.selected = not cur.ref and cur.perChar == (mode == "char")
    end
    cfg.Paint(false)
end

-- The header's list in place: the counts, the grid, and the snapshot a
-- re-show compares with. Returns the header's height.
local function PaintHeader()
    local a, c = GetNumMacros()
    hdrValues.account = CludesUI.L("Account Macros") .. "  (" .. a .. "/" .. MM.MAX_ACCOUNT .. ")"
    hdrValues.char = CludesUI.L("Character Macros") .. "  (" .. c .. "/" .. MM.MAX_CHAR .. ")"
    hdrDD._invalidateMenu() -- the menu is built again from the new labels on its next open
    local perChar = mode == "char"
    gridList = MM.List(perChar)
    local total = #gridList + (MM.Free(perChar) > 0 and 1 or 0)
    local gh = LayoutGrid(macroGrid, hdrFrame, hdrY, hdrW, total, BindMacroCell)
    MM.Diff(snap, true)
    return math.abs(hdrY - gh - 14)
end

-------------------------------------------------------------------------------
--  Following the game
-------------------------------------------------------------------------------
-- The editor's macro after a macro change, ours or from elsewhere. A clean
-- editor follows the game: the macro's icon, its text edited elsewhere (found
-- by its name), or a new macro once it is gone. A dirty one keeps its edits;
-- its Save finds the macro again or refuses.
local function Follow()
    local ref = cur.ref
    if not ref then return end
    local idx = MM.Resolve(ref)
    if cur.dirty then return end
    if idx then
        cur.icon = MM.StoredIcon(idx)
        return
    end
    -- A value typed but not committed yet belongs to this macro: it lands
    -- first, and the editor then keeps it.
    FlushField()
    if cur.dirty then return end
    idx = MM.Resolve(ref, true)
    SetCur(idx and StateOf(MM.Entry(idx)) or NewState(cur.perChar))
end

-- A macro change while shown: the header repaints in place; the body is built
-- again only when the editor changed or a new macro got its slot.
local function OnMacrosChanged()
    Follow()
    if cur ~= builtFor or (cur.ref ~= nil) ~= builtHadRef then
        RebuildPage()
        return
    end
    if hdrDD and hdrDD:IsVisible() then CludesUI:SetContentHeaderHeightSilent(PaintHeader()) end
    Refresh()
end

local function ResyncNow()
    pendingEvent = nil
    if isShown then OnMacrosChanged() end
end

-- Bursts (several macros changed at once) settle in one pass on the next frame.
local function RequestResync()
    if pendingEvent then return end
    pendingEvent = true
    C_Timer.After(0, ResyncNow)
end

-------------------------------------------------------------------------------
--  Macro actions: each write finds its macro again first, or refuses
-------------------------------------------------------------------------------
-- Whether m is the macro the editor holds.
local function IsCur(m)
    local idx = MM.Resolve(m)
    return idx ~= nil and cur.ref ~= nil and MM.Resolve(cur.ref) == idx
end

local function PickupRef(m)
    local success, err = MM.Pickup(m)
    if not success then SetStatus(err, true) end
end

local function Save()
    FlushField() -- a field typed in but not committed (a click with a modifier held keeps its focus)
    ReadText() -- text typed but not read yet: read now, and the lines follow
    local name = MM.CleanName(cur.name)
    if name == "" then name = MM.CleanName(B.FirstSpell(cur.model)) end
    local bad = MM.Check(name, cur.text)
    if bad then
        SetStatus(bad, true)
        return
    end
    local function Commit()
        -- A saved macro keeps the icon it has unless one was picked here: it
        -- may have been changed elsewhere since the editor read it.
        local icon = (cur.iconSet or not cur.ref) and cur.icon or nil
        local m, err = MM.Save(cur.ref, name, icon, cur.text, cur.perChar)
        if not m then
            SetStatus(err, true)
            return
        end
        mode = m.perChar and "char" or "account" -- a saved macro shows in its list
        if m.body == cur.text then
            cur.ref, cur.perChar, cur.name, cur.dirty, cur.iconSet = m, m.perChar, m.name, false, nil
            SetStatus(CludesUI.L("Saved."))
        else
            SetCur(StateOf(m)) -- the game kept another text: show it
            SetStatus(CludesUI.L("Saved, but the game changed the text: this is what it kept."), true)
        end
        RequestResync()
    end
    -- Two macros of one name are allowed, but a key bound by name finds the first.
    if (not cur.ref or name ~= cur.ref.name) and MM.NameTaken(name, cur.perChar) then
        CludesUI:ShowConfirmPopup({
            title = CludesUI.L("Name Taken"),
            message = CludesUI.Lf("Another macro in this list is already named %s. Save anyway?", name),
            confirmText = CludesUI.L("Save"),
            cancelText = CludesUI.L("Cancel"),
            onConfirm = Commit,
        })
        return
    end
    Commit()
end

local function DeleteMacro(m)
    CludesUI:ShowConfirmPopup({
        title = CludesUI.L("Delete Macro"),
        message = CludesUI.Lf("Delete the macro %s?", m.name),
        confirmText = CludesUI.L("Delete"),
        cancelText = CludesUI.L("Cancel"),
        onConfirm = function()
            local isCur = IsCur(m)
            local success, err = MM.Delete(m)
            if not success then
                SetStatus(err, true)
                return
            end
            if isCur then SetCur(NewState(m.perChar)) end
            RequestResync()
        end,
    })
end

-- Account <-> character: the macro is made again in the other list.
local function MoveScope(m)
    local toChar = not m.perChar
    local message = (
        toChar and CludesUI.Lf("Move %s to this character?", m.name)
        or CludesUI.Lf("Move %s to the account?", m.name)
    )
        .. "\n"
        .. CludesUI.L("Action bar buttons with this macro have to be placed again.")
    -- As at Save: a key bound by name finds the first of two macros of one name.
    if MM.NameTaken(m.name, toChar) then
        message = message .. "\n" .. CludesUI.Lf("Another macro in that list is already named %s.", m.name)
    end
    CludesUI:ShowConfirmPopup({
        title = CludesUI.L("Move Macro"),
        message = message,
        confirmText = CludesUI.L("Move"),
        cancelText = CludesUI.L("Cancel"),
        onConfirm = function()
            local isCur = IsCur(m)
            local moved, err = MM.Save(m, m.name, nil, m.body, toChar)
            if not moved then
                SetStatus(err, true)
                return
            end
            if isCur then
                cur.ref, cur.perChar = moved, moved.perChar
                mode = toChar and "char" or "account" -- the editor's macro shows in its list
            end
            RequestResync()
        end,
    })
end

local menuOwner -- the cell whose right-click menu opened last

local function MacroMenu(anchor, m)
    menuOwner = anchor
    CludesUI.ShowContextMenu(anchor, {
        {
            text = m.perChar and "Move to Account" or "Move to Character",
            onClick = function() MoveScope(m) end,
        },
        {
            text = "Pick Up",
            onClick = function() PickupRef(m) end,
        },
        "---",
        {
            text = "Delete",
            onClick = function() DeleteMacro(m) end,
        },
    })
end

CellClick = function(self, button)
    local m = self.m
    if button == "RightButton" then
        if m then MacroMenu(self, m) end
        return
    end
    local perChar = mode == "char"
    if m and cur.ref and cur.ref.index == m.index then return end -- open already
    if not m and not cur.ref and cur.perChar == perChar then return end
    FlushField() -- a value typed but not committed lands first, so Guard sees it
    Guard(function()
        SetCur(m and StateOf(m) or NewState(perChar))
        RebuildPage()
    end)
end

CellDrag = function(self)
    if not self.m then return end
    CludesUI.HideWidgetTooltip()
    PickupRef(self.m)
end

-- Centered list dropdown over the centered icons (the Action Bars header).
HeaderBuilder = function(heading, width)
    hdrFrame, hdrY, hdrW = heading, -20 - 34 - 12, width - CludesUI.CONTENT_PAD * 2
    hdrValues = { _noLoc = true }
    hdrDD = CludesUI.BuildDropdownControl(
        heading,
        350,
        heading:GetFrameLevel() + 5,
        hdrValues,
        LIST_ORDER,
        function() return mode end,
        function(val)
            if val == mode then return end
            FlushField() -- a value typed but not committed lands first: the editor may be dirty then
            mode = val
            -- Another list starts a new macro unless one is being edited.
            if not cur.dirty and cur.perChar ~= (val == "char") then SetCur(NewState(val == "char")) end
            RebuildPage()
        end
    )
    Pix.Point(hdrDD, "TOP", heading, "TOP", 0, -20)
    hdrDD:SetHeight(34)
    return PaintHeader()
end
_G._CUI_MacrosHeaderBuilder = HeaderBuilder

-------------------------------------------------------------------------------
--  Events: while the page is shown
-------------------------------------------------------------------------------
local function OnEvent(self, evt)
    if evt == "GLOBAL_MOUSE_UP" then
        self:UnregisterEvent("GLOBAL_MOUSE_UP")
        C_Timer.After(0, RebuildIfPending) -- next frame: after the click that ended the text edit
    elseif evt == "SPELLS_CHANGED" then
        S.Invalidate() -- read again where it is next used
    else
        RequestResync() -- UPDATE_MACROS
    end
end

-- The icon picker and a cell's right-click menu close with the page once it
-- stays hidden: a rebuild hides and shows it again at once, so a popup the
-- click under way opened stays.
local function ClosePopupsIfHidden()
    if isShown then return end
    if picker then picker.Close() end
    if menuOwner and CludesUI.ContextMenuOwner() == menuOwner then CludesUI.CloseContextMenu() end
end

-- One event frame, re-parented into each build of the page: its show and hide
-- are the page's, so the events are registered only while the page is shown.
-- Made under the page and kept out of its pool (Pool.Keep): a later build of
-- the page hides it with the page instead of handing it out again.
local function WatchEvents(hostFrame)
    if not evf then
        evf = PoolKeep(CreateFrame("Frame", nil, hostFrame))
        evf._searchIgnore = true -- the inline search never hides it
        evf:SetScript("OnEvent", OnEvent)
        evf:SetScript("OnShow", function(self)
            isShown = true
            self:RegisterEvent("UPDATE_MACROS")
            self:RegisterEvent("SPELLS_CHANGED")
            -- Hidden in this same frame: a rebuild, which has just read both.
            if GetTime() == hiddenAt then return end
            -- Shown again: spells and macros may have changed while hidden.
            S.Invalidate()
            if pendingRebuild then
                C_Timer.After(0, RebuildIfPending)
            elseif MM.Diff(snap) then
                RequestResync()
            end
        end)
        evf:SetScript("OnHide", function(self)
            isShown, hiddenAt = nil, GetTime()
            -- Text typed but not read into lines yet: read it now; the lines are
            -- built on the next show.
            ReadText()
            self:UnregisterAllEvents()
            HideSuggest()
            if
                (picker and picker.dimmer:IsShown())
                or (menuOwner and CludesUI.ContextMenuOwner() == menuOwner)
            then
                C_Timer.After(0, ClosePopupsIfHidden)
            end
        end)
    end
    evf:Hide()
    evf:SetParent(hostFrame)
    evf:Show()
end

-------------------------------------------------------------------------------
--  Page body
-------------------------------------------------------------------------------
local function BuildMacroBody(hostFrame, cursorY, enable)
    local W = CludesUI.Widgets
    local _, height
    edCtx.model = cur.model
    cursorY = EmitCells(hostFrame, cursorY, {
        enable,
        Input("Name", function() return cur.name end, function(t)
            t = MM.CleanName(t)
            if t == cur.name then return end
            cur.name, cur.nameTouched = t, true
            MarkUnsaved()
        end, { width = 170, ph = "Max. 16 characters", maxLetters = MM.MAX_NAME }),
        {
            type = "dropdown",
            text = "Saved For",
            values = { account = "Account", char = "Character" },
            order = LIST_ORDER,
            tooltip = "Account macros exist on all your characters, character macros only on this one.",
            getValue = function() return cur.perChar and "char" or "account" end,
            setValue = function(val)
                cur.perChar = val == "char"
                MarkUnsaved()
            end,
            -- A saved macro moves through Move, which warns that its bar buttons go.
            disabled = function() return cur.ref ~= nil end,
            rawTooltip = true,
            disabledTooltip = "A saved macro changes lists through Move in its right-click menu.",
        },
        {
            type = "labeledButton",
            text = "Icon",
            buttonText = "Choose Icon",
            width = 130,
            onClick = function()
                OpenPicker(function(icon)
                    cur.icon, cur.iconSet = icon or MM.QUESTION, true
                    MarkUnsaved()
                    Refresh()
                end)
            end,
            _icon = function() return cur.icon end,
        },
        {
            type = "toggle",
            text = "Show Spell Tooltip",
            tooltip = "#showtooltip: the button shows the spell's icon and tooltip.",
            getValue = function() return cur.model.tooltip end,
            setValue = function(val)
                cur.model.tooltip = val
                ApplyEdit(false)
            end,
        },
        Input("Tooltip Spell", function() return cur.model.tooltipSpell end, function(t)
            cur.model.tooltipSpell = t
            ApplyEdit(false)
        end, {
            ph = "Empty = automatic",
            suggest = true,
            disabled = function() return not cur.model.tooltip end,
            disabledTooltip = "Show Spell Tooltip",
        }),
    })

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height
    -- The LINES rows show live macro text: kept out of the search index (the
    -- flag is restored even when a row errors).
    local prev = CludesUI._searchIndexSuppress
    CludesUI._searchIndexSuppress = true
    local success, ny = pcall(BuildLines, hostFrame, cursorY, edCtx)
    CludesUI._searchIndexSuppress = prev
    if not success then error(ny, 0) end
    cursorY = ny

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height
    _, height = W:SectionHeader(hostFrame, "MACRO TEXT", cursorY)
    cursorY = cursorY - height
    local boxFrame, total, details = TextBlock(hostFrame, cursorY)
    cursorY = cursorY - TEXT_H
    D.text, D.count, D.info = boxFrame, total, details
    boxFrame:SetText(cur.text)
    PaintCounter(total, strlenutf8(cur.text))
    SetStatus(statusText, statusBad)
    -- Typing is read into lines on blur (and at Save), not per keystroke.
    boxFrame.onChange = function(textValue, user)
        if not user then return end
        cur.text, textDirty = textValue, true
        MarkUnsaved()
        PaintCounter(total, strlenutf8(textValue))
    end
    boxFrame.onBlur = ReadText

    local notSaved = { disabled = true, tooltip = CludesUI.L("Save the macro first.") }
    -- Deleting the open macro leaves no ref until the body is built again.
    _, height = W:WideTripleButton(hostFrame, "Save", "Pick Up", "Delete", cursorY, Save, function()
        if cur.ref then PickupRef(cur.ref) end
    end, function()
        if cur.ref then DeleteMacro(cur.ref) end
    end, nil, not cur.ref and { [2] = notSaved, [3] = notSaved } or nil)
    cursorY = cursorY - height
    builtFor, builtHadRef = cur, cur.ref ~= nil
    return cursorY
end

-------------------------------------------------------------------------------
--  Page entry point
-------------------------------------------------------------------------------
_G._CUI_BuildForeverMacrosPage = function(page, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local KIT = CludesUI._MacroManager
    local cursorY = yOffset
    local _, height
    hostFrame._showRowDivider = true
    _, height = W:SectionHeader(hostFrame, "MACRO", cursorY)
    cursorY = cursorY - height
    local enable = {
        type = "toggle",
        text = "Enable Macro Manager",
        tooltip = "Edit your macros by click: a line editor with every option and the live macro text. /cuimacros opens this page.",
        getValue = KIT.Enabled,
        setValue = function(val)
            KIT.Cfg().enabled = val
            if val then
                KIT.Apply()
            else
                -- The header cached while it was on must not come back over the bare page.
                CludesUI:InvalidateContentHeaderCache()
            end
            RebuildPage()
        end,
    }
    -- Off, and in the search pre-build: the switch alone.
    if CludesUI._prebuilding or not KIT.Enabled() then
        _, height = W:DualRow(hostFrame, cursorY, enable, CludesUI.BlankRowCfg())
        cursorY = cursorY - height
        return math.abs(cursorY)
    end
    if not cur then cur = NewState(mode == "char") end
    Follow()
    pendingRebuild = nil -- this build is the one a text edit asked for
    wipe(boxes)
    wipe(D)
    stanceV, stanceO = nil, nil -- forms can be learned between builds
    CludesUI:SetContentHeader(HeaderBuilder)
    cursorY = BuildMacroBody(hostFrame, cursorY, enable)
    WatchEvents(hostFrame) -- after the header: a re-show compares with what it painted
    return math.abs(cursorY)
end
