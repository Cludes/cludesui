if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_GroupFinder_Extras.lua - the extra filters and looks:
--  has / missing rows, specific roles, menu icons, group settings columns,
--  region tags, row art, the scrolling strips, the person / raid icons
-------------------------------------------------------------------------------
local FOLDER, mod = ...
if CUI.HELD_BACK_ADDONS[FOLDER] then return end -- held back (CludesUIGroupFinder.lua)
mod.CUI = CUI

-- runs fn once blizzard's group finder loads
function mod.WhenGroupFinder(func)
    -- module off: nothing hooks in
    if not mod.Enabled() or mod.Blocked() then return end
    if C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder") and PVEFrame then
        func()
        return
    end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(self, _, label)
        if label ~= "Blizzard_GroupFinder" then return end
        self:UnregisterAllEvents()
        func()
    end)
end
local GFNS = mod

-- specific roles: match all (and) or match any (or)
GFNS.ExtraRolesAny = function()
    local cfg = GFNS.Cfg and GFNS.Cfg()
    return cfg and cfg.extraRolesAny == true or false
end

local CM = mod.CUI
local Secret = CUI.IsSecret
local HINT_GREY = 0.35 -- the (and) / (or) bit, never takes the accent
-- dim label grey
local DIM_HEX = CUI.COLOR_CODES.DIM

-- label + grey hint
local function TwoPart(ownerFrame, SortKit)
    local main = ownerFrame:CreateFontString(nil, "OVERLAY")
    SortKit.Font(main, SortKit.ITEM_FONT)
    main:SetPoint("LEFT", ownerFrame, "LEFT", 7, 0)
    local hintText = ownerFrame:CreateFontString(nil, "OVERLAY")
    SortKit.Font(hintText, SortKit.ITEM_FONT)
    hintText:SetPoint("LEFT", main, "RIGHT", 3, 0)
    hintText:SetTextColor(HINT_GREY, HINT_GREY, HINT_GREY, 1)
    return main, hintText
end

local ARROW = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\cui-arrow.png"

-- our dropdowns can hang outside the menu: clicks in them keep it open
local pops = {}
GFNS.ExtraInside = function()
    for _, frame in ipairs(pops) do
        if frame:IsShown() and frame:IsMouseOver() then return true end
    end
    return false
end

local MASK = "Interface\\AddOns\\" .. FOLDER .. "\\media\\masks\\rounded.png"

-- an atlas name, or a spell's texture (cropped to lose its built-in border)
local function PaintIcon(ic, iconTex)
    if type(iconTex) == "number" then
        ic:SetTexture(iconTex)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        ic:SetAtlas(iconTex)
    end
end

-- rounded icon after the text
local function RoundIcon(hostFrame, iconTex, after)
    local ic = hostFrame:CreateTexture(nil, "OVERLAY")
    ic:SetSize(12, 12)
    ic:SetPoint("LEFT", after, "RIGHT", 4, 0)
    if iconTex then PaintIcon(ic, iconTex) end
    local mask = hostFrame:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(ic)
    ic:AddMaskTexture(mask)
    ic.mask = mask
    return ic
end

-- skinned dropdown button: label, grey hint, arrow
local function ArrowButton(ownerFrame, SortKit)
    local button = CreateFrame("Button", nil, ownerFrame)
    button:SetNormalFontObject("GameFontHighlight")
    button:SetText(" ")
    button.Arrow = button:CreateTexture(nil, "OVERLAY")
    button.Arrow:SetTexture(ARROW)
    button.Arrow:SetSize(13, 13) -- how it looks in the settings
    button.Arrow:SetPoint("CENTER", button, "RIGHT", -10, 0)
    button.Label, button.Hint = TwoPart(button, SortKit)
    button.Label:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
    -- icon room, made before the skin so it survives
    button.Icon = RoundIcon(button, nil, button.Label)
    button.IconMask = button.Icon.mask
    button.Icon:Hide()
    local skin = CM._ModuleNS and CM._ModuleNS.CludesUIBlizzardSkin
    local S = skin and skin.WSkin
    if S and S.Button then
        S.Button(button, { "Arrow", "Label", "Hint", "Icon", "IconMask" })
    else
        local backdrop = button:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        CM.MakeBorder(button, SortKit.ThemeBorder())
        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.1)
    end
    return button
end

-- under the button, or above it if it'd hang off the menu
local function OpenNear(popup, button, bounds, pad)
    pad = pad or 0
    popup:ClearAllPoints()
    local bb, mb = button:GetBottom(), bounds and bounds:GetBottom()
    if
        bb
        and mb
        and (bb - 2 - popup:GetHeight()) * button:GetEffectiveScale() < mb * bounds:GetEffectiveScale()
    then
        popup:SetPoint("BOTTOMLEFT", button, "TOPLEFT", -pad, 2)
        popup:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", pad, 2)
    else
        popup:SetPoint("TOPLEFT", button, "BOTTOMLEFT", -pad, -2)
        popup:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", pad, -2)
    end
    popup:Show()
end

-- arrow button + its list. modes = { label, hint, icon }, get() = index,
-- set(i) on pick, up opens it above the button. caller places it
local function Dropdown(ownerFrame, SortKit, modes, Get, Set, up)
    local button = ArrowButton(ownerFrame, SortKit)
    function button:ShowMode()
        local modeName = modes[Get()] or modes[1]
        self.Label:SetText(modeName.button or modeName.label)
        if modeName.button then
            self.Label:SetTextColor(1, 1, 1, 1)
        else
            self.Label:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
        end
        self.Hint:SetText(modeName.hint or "")
        if modeName.icon then
            PaintIcon(self.Icon, modeName.icon)
            self.Icon:Show()
        else
            self.Icon:Hide()
        end
    end
    button:ShowMode()

    local entries = CreateFrame("Frame", nil, SortKit.parent or ownerFrame)
    entries:SetFrameStrata("FULLSCREEN_DIALOG")
    entries:SetFrameLevel(330)
    entries:SetClampedToScreen(true)
    entries:EnableMouse(true)
    local lbg = entries:CreateTexture(nil, "BACKGROUND")
    lbg:SetAllPoints()
    lbg:SetColorTexture(0, 0, 0, 1)
    CM.MakeBorder(entries, SortKit.ThemeBorder())
    entries.items = {}
    for index, modeName in ipairs(modes) do
        local entry = CreateFrame("Button", nil, entries)
        entry:SetHeight(SortKit.ITEM_H)
        entry:SetPoint("TOPLEFT", entries, "TOPLEFT", 1, -(2 + (index - 1) * SortKit.ITEM_H))
        entry:SetPoint("TOPRIGHT", entries, "TOPRIGHT", -1, -(2 + (index - 1) * SortKit.ITEM_H))
        entry.text, entry.hint = TwoPart(entry, SortKit)
        entry.text:SetText(modeName.label)
        entry.hint:SetText(modeName.hint or "")
        if modeName.icon then RoundIcon(entry, modeName.icon, entry.text) end
        local ihl = entry:CreateTexture(nil, "HIGHLIGHT")
        ihl:SetAllPoints()
        ihl:SetColorTexture(1, 1, 1, CM.DD_ITEM_HL_A or 0.08)
        entry:SetScript("OnClick", function()
            Set(index)
            button:ShowMode()
            entries:Hide()
            SortKit.Refilter()
            SortKit.Paint()
        end)
        entries.items[index] = entry
    end
    entries:SetHeight(4 + #modes * SortKit.ITEM_H)
    button.list = entries
    pops[#pops + 1] = entries
    SortKit.ClickOff(entries, function(self) return self:IsMouseOver() or button:IsMouseOver() end)
    entries:Hide()

    button:SetScript("OnClick", function()
        if entries:IsShown() then
            entries:Hide()
            return
        end
        SortKit.Untip()
        -- picked one in the accent color
        local ar, ag, ab = SortKit.Accent()
        for index, entry in ipairs(entries.items) do
            if index == Get() then
                entry.text:SetTextColor(ar, ag, ab, 1)
            else
                entry.text:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
            end
        end
        entries:ClearAllPoints()
        if up then
            entries:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 2)
            entries:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 2)
        else
            entries:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
            entries:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -2)
        end
        entries:Show()
    end)
    button:SetScript("OnHide", function() entries:Hide() end)
    button:SetScript("OnShow", function(self) self:ShowMode() end)
    button:SetScript("OnLeave", SortKit.Untip)
    return button
end

local function Divider(m, posY)
    local div = m:CreateTexture(nil, "ARTWORK")
    if mod.GFHairline then
        mod.GFHairline(div)
    else
        div:SetHeight(CM.PP.mult)
    end
    div:SetColorTexture(1, 1, 1, 0.10)
    div:SetPoint("TOPLEFT", m, "TOPLEFT", 10, -posY - 3)
    div:SetPoint("TOPRIGHT", m, "TOPRIGHT", -10, -posY - 3)
    return posY + 7
end

-------------------------------------------------------------------------------
--  specific roles: a dropdown with match exact / any and the role count rows
-------------------------------------------------------------------------------
local function Block(m, posY)
    local frame = CreateFrame("Frame", nil, m)
    frame:SetPoint("TOPLEFT", m, "TOPLEFT", 0, -posY)
    frame:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, -posY)
    return frame
end

local function PlaceBlock(frame, m, posY)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", m, "TOPLEFT", 0, -posY)
    frame:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, -posY)
end

local MATCH = {
    {
        any = false,
        label = CUI.L("Match All"),
        hint = "(and)",
        tip = CUI.L("Match all of the selected options below."),
    },
    {
        any = true,
        label = CUI.L("Match Any"),
        hint = "(or)",
        tip = CUI.L("Match any of the selected options below."),
    },
}

local function CountsOn(cfg)
    local num = 0
    for _, rule in pairs(type(cfg.roleCounts) == "table" and cfg.roleCounts or {}) do
        if type(rule) == "table" and rule.on then num = num + 1 end
    end
    return num
end

GFNS.ExtraRoleCounts = function(m, posY, SortKit)
    local sg = Block(m, posY)
    sg:SetHeight(SortKit.ITEM_H)
    m.extraSpecGrp = sg
    local button = ArrowButton(sg, SortKit)
    button:SetHeight(SortKit.ITEM_H - 2)
    button:SetPoint("TOPLEFT", sg, "TOPLEFT", 9, -1)
    button:SetPoint("TOPRIGHT", sg, "TOPRIGHT", -9, -1)
    button.Label:SetText(CUI.L("Specific Roles"))

    local popup = CreateFrame("Frame", nil, SortKit.parent or m)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(325)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    local pbg = popup:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    local fr, fg, fb = SortKit.ThemeFill()
    pbg:SetColorTexture(fr, fg, fb, 0.98)
    CM.MakeBorder(popup, SortKit.ThemeBorder())
    pops[#pops + 1] = popup

    -- while open: veil over both columns, eats clicks
    local shade = CreateFrame("Button", nil, SortKit.parent or m)
    shade:SetFrameStrata("FULLSCREEN_DIALOG")
    shade:SetFrameLevel(m:GetFrameLevel() + 8)
    local vt = shade:CreateTexture(nil, "BACKGROUND")
    vt:SetAllPoints()
    vt:SetColorTexture(fr, fg, fb, 0.7)
    shade:Hide()

    local py, toggles = 2, {}
    local function PaintMatch()
        local any = SortKit.Cfg().extraRolesAny == true
        for _, t in ipairs(toggles) do
            t:SetChecked(t.any == any)
        end
    end
    for _, modeName in ipairs(MATCH) do
        local t = SortKit.MenuItem(popup, py, modeName.label, function()
            SortKit.Cfg().extraRolesAny = modeName.any or nil
            PaintMatch()
            SortKit.Refilter()
            SortKit.Paint()
        end)
        t.any = modeName.any
        local _, callback = t.label:GetPoint(1)
        t.label:ClearAllPoints()
        t.label:SetPoint("LEFT", callback, "RIGHT", 7, 0)
        local hintText = t:CreateFontString(nil, "OVERLAY")
        SortKit.Font(hintText, SortKit.ITEM_FONT)
        hintText:SetPoint("LEFT", t.label, "RIGHT", 3, 0)
        hintText:SetTextColor(HINT_GREY, HINT_GREY, HINT_GREY, 1)
        hintText:SetText(modeName.hint)
        t:HookScript("OnEnter", function(self) SortKit.Tip(self, modeName.tip) end)
        t:HookScript("OnLeave", SortKit.Untip)
        toggles[#toggles + 1] = t
        py = py + SortKit.ITEM_H
    end
    py = Divider(popup, py)
    -- count rows go in m.counts so the menu paints them
    m.counts = m.counts or {}
    popup.counts = m.counts
    for _, region in ipairs(SortKit.COUNT_ROLES) do
        py = SortKit.AddCountRow(popup, py, region.key, region.label)
    end
    popup:SetHeight(py + 2)
    SortKit.ClickOff(
        popup,
        function(self)
            return self:IsMouseOver()
                or button:IsMouseOver()
                or (SortKit.OpListOver and SortKit.OpListOver())
                or false
        end
    )
    popup:Hide()

    -- "(2 active)" so ticked rows aren't forgotten
    local function ShowHint()
        local num = CountsOn(SortKit.Cfg())
        button.Hint:SetText(num > 0 and CUI.Lf("(%1$d active)", num) or "")
    end
    local sgLevel = sg:GetFrameLevel()
    popup:HookScript("OnShow", function()
        PaintMatch()
        shade:ClearAllPoints()
        shade:SetPoint("TOPLEFT", m.side or m, "TOPLEFT", 0, 0)
        shade:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 0, 0)
        shade:Show()
        sg:SetFrameLevel(shade:GetFrameLevel() + 1) -- keeps the button lit
    end)
    popup:HookScript("OnHide", function()
        shade:Hide()
        sg:SetFrameLevel(sgLevel)
        ShowHint()
    end)
    button:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
            return
        end
        OpenNear(popup, button, m)
    end)
    button:SetScript("OnShow", ShowHint)
    button:SetScript("OnHide", function() popup:Hide() end)
    ShowHint()
    return posY + SortKit.ITEM_H
end

-------------------------------------------------------------------------------
--  raids and delves: squares in one sideways-scrolling line instead of a
--  grid that pushes the list down
-------------------------------------------------------------------------------
local ARROW_W = 14
local ARROW_DIR = "Interface\\AddOns\\CludesUI\\media\\icons\\"

local function PlaceStrip(s)
    if not s.list then return end
    local per = s.size + s.gap
    -- whole steps only, stops once the last square is fully in view
    local full = math.max(1, math.floor((s.clipW + s.gap) / per))
    local maxOff = math.max(0, #s.list - full)
    s.offset = math.max(0, math.min(s.offset, maxOff))
    local shift = -s.offset * per
    for index, sq in ipairs(s.squares) do
        local skinData = s.list[index]
        if skinData then
            local posX = (index - 1) * per + shift
            sq:ClearAllPoints()
            sq:SetPoint("LEFT", s.clip, "LEFT", posX, 0)
            -- hidden off-window so they can't be clicked
            sq:SetShown(posX + s.size > 0 and posX < s.clipW)
        end
    end
    for _, a in ipairs({ { s.left, s.offset > 0 }, { s.right, s.offset < maxOff } }) do
        local b, live = a[1], a[2]
        b.live = live
        b:EnableMouse(live)
        b.tex:SetAlpha(live and 0.8 or 0.2)
    end
end

local function ScrollStrip(cfg, step)
    cfg.offset = cfg.offset + step
    if GFNS.ExtraHideBossPick then GFNS.ExtraHideBossPick() end
    PlaceStrip(cfg)
    if cfg.paint then cfg.paint() end -- recolor the squares now in view
end

local function StripArrow(s, line, file, step)
    local widget = CreateFrame("Button", nil, line)
    widget.tex = widget:CreateTexture(nil, "OVERLAY")
    widget.tex:SetTexture(ARROW_DIR .. file)
    widget.tex:SetSize(16, 16)
    widget.tex:SetPoint("CENTER")
    widget:SetScript("OnClick", function() ScrollStrip(s, step) end)
    widget:SetScript("OnEnter", function(self)
        if self.live then self.tex:SetAlpha(1) end
    end)
    widget:SetScript("OnLeave", function(self) self.tex:SetAlpha(self.live and 0.8 or 0.2) end)
    return widget
end

-- one strip. key = the square's data field, fill dresses a square
local function NewStrip(key, fillTex)
    local cfg = { offset = 0 }
    return function(entries, squares, Make, px, after, show, cols, slots, line, spacing, paint)
        cfg.paint = paint
        if not cfg.clip then
            cfg.clip = CreateFrame("Frame", nil, line)
            cfg.clip:SetClipsChildren(true)
            cfg.clip:EnableMouseWheel(true)
            cfg.clip:SetScript("OnMouseWheel", function(_, delta) ScrollStrip(cfg, delta > 0 and -1 or 1) end)
            cfg.left = StripArrow(cfg, line, "cui-arrow-left.png", -1)
            cfg.right = StripArrow(cfg, line, "cui-arrow-right.png", 1)
        end
        if not show or #entries == 0 or not after then
            for _, sq in ipairs(squares) do
                sq[key] = nil
                sq:Hide()
            end
            cfg.clip:Hide()
            cfg.left:Hide()
            cfg.right:Hide()
            cfg.list = nil
            return 1
        end
        local per = px + spacing
        local startX = spacing + (slots - cols) * per
        local room = cols * per - spacing
        local fits = #entries * per - spacing <= room
        local vis = fits and #entries
            or math.max(1, math.floor((room - 2 * (ARROW_W + spacing) + spacing) / per))
        cfg.clip:ClearAllPoints()
        cfg.left:ClearAllPoints()
        cfg.right:ClearAllPoints()
        cfg.left:SetSize(ARROW_W, px)
        cfg.right:SetSize(ARROW_W, px)
        if fits then
            cfg.left:Hide()
            cfg.right:Hide()
            cfg.clip:SetPoint("LEFT", after, "RIGHT", startX, 0)
        else
            cfg.left:SetPoint("LEFT", after, "RIGHT", startX, 0)
            cfg.left:Show()
            cfg.clip:SetPoint("LEFT", cfg.left, "RIGHT", spacing, 0)
        end
        -- scrolling: runs to the row's right edge
        local clipW = vis * per - spacing
        if fits then
            cfg.clip:SetSize(clipW, px)
        else
            cfg.right:SetPoint("RIGHT", line, "RIGHT", 4, 0) -- a touch wider so the last border isn't clipped
            cfg.right:Show()
            cfg.clip:SetPoint("RIGHT", cfg.right, "LEFT", -spacing, 0)
            cfg.clip:SetHeight(px)
            clipW = room + 4 - 2 * (ARROW_W + spacing)
        end
        cfg.clip:Show()
        for index, skinData in ipairs(entries) do
            local sq = squares[index]
            if not sq then
                sq = Make()
                squares[index] = sq
            end
            if sq:GetParent() ~= cfg.clip then sq:SetParent(cfg.clip) end
            sq[key] = skinData
            fillTex(sq, skinData)
            sq:SetSize(px, px)
        end
        for index = #entries + 1, #squares do
            squares[index][key] = nil
            squares[index]:Hide()
        end
        cfg.list, cfg.squares, cfg.size, cfg.gap, cfg.clipW = entries, squares, px, spacing, clipW
        PlaceStrip(cfg)
        return 1
    end
end

GFNS.ExtraBossStrip = NewStrip(
    "boss",
    function(sq, skinData) sq.icon:SetTexture(skinData.icon or "Interface\\Icons\\INV_Misc_QuestionMark") end
)
-- delves: the module dresses its squares
GFNS.ExtraDelveStrip = NewStrip("delve", function(sq, skinData)
    if GFNS.GFDressDelve then GFNS.GFDressDelve(sq, skinData) end
end)

-- filters menu spans search box to refresh
GFNS.ExtraWidenMenu = function(m, anchor, spacing, right)
    local searchPane = LFGListFrame and LFGListFrame.SearchPanel
    local leftX = searchPane and (searchPane.SearchBox or searchPane.BackButton)
    if not (leftX and leftX:IsVisible() and leftX:GetLeft() and anchor:GetLeft()) then return end
    -- split evenly
    if m.side and right and right:GetRight() then
        local sum = (
            right:GetRight() * right:GetEffectiveScale() - leftX:GetLeft() * leftX:GetEffectiveScale()
        ) / m:GetEffectiveScale()
        if sum > 100 then m.side:SetWidth(math.floor(sum / 2 + 0.5)) end
    end
    local sideW = m.side and m.side:GetWidth() or 0
    local dx = (leftX:GetLeft() * leftX:GetEffectiveScale() - anchor:GetLeft() * anchor:GetEffectiveScale())
            / m:GetEffectiveScale()
        + sideW
    m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", dx, -spacing)
end

-------------------------------------------------------------------------------
--  has / missing rows: bloodlust, battle res and your class
-------------------------------------------------------------------------------
local LUST = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
local BREZ = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true }

local function MyClass()
    local label, file = UnitClass("player")
    return label, file
end

local CLASS_ROWS = {
    {
        key = "hasLust",
        pick = "extraLustMissing",
        spell = 2825,
        has = CUI.L("Has Bloodlust"),
        missing = CUI.L("Missing Bloodlust"),
        Tip = function(SortKit)
            return CUI.L("Bloodlust"),
                {
                    CUI.L("A member whose class has one of these spells:"),
                    SortKit.ClassLine("SHAMAN", CUI.L("Bloodlust / Heroism (Shaman)")),
                    SortKit.ClassLine("MAGE", CUI.L("Time Warp (Mage)")),
                    SortKit.ClassLine("HUNTER", CUI.L("Primal Rage (Hunter pet)")),
                    SortKit.ClassLine("EVOKER", CUI.L("Fury of the Aspects (Evoker)")),
                    CUI.L("Drums and other items don't count."),
                }
        end,
    },
    {
        key = "hasBrez",
        pick = "extraBrezMissing",
        spell = 20484,
        has = CUI.L("Has Battle Res"),
        missing = CUI.L("Missing Battle Res"),
        Tip = function(SortKit)
            return CUI.L("Battle Res"),
                {
                    CUI.L("A member whose class has one of these spells:"),
                    SortKit.ClassLine("DRUID", CUI.L("Rebirth (Druid)")),
                    SortKit.ClassLine("DEATHKNIGHT", CUI.L("Raise Ally (Death Knight)")),
                    SortKit.ClassLine("WARLOCK", CUI.L("Soulstone (Warlock)")),
                    SortKit.ClassLine("PALADIN", CUI.L("Intercession (Paladin)")),
                    CUI.L("Engineering and other items don't count."),
                }
        end,
    },
    {
        key = "extraMyClass",
        pick = "extraMyClassMissing",
        missingDefault = true,
        raidKey = "raidMyClass",
        raidPick = "raidMyClassMissing", -- the raids tab keeps its own
        has = "Has Class",
        missing = "No Class", -- class name added at build
        Tip = function(SortKit)
            local label, file = MyClass()
            return CUI.L("Your Class"),
                {
                    CUI.Lf(
                        "A member who's your class: %1$s",
                        file and SortKit.ClassLine(file, label) or label or ""
                    ),
                }
        end,
    },
}

-- the row's keys on this tab
local function Keys(line, raids)
    if raids and line.raidKey then return line.raidKey, line.raidPick end
    return line.key, line.pick
end

local function Missing(cfg, line, raids)
    local _, pick = Keys(line, raids)
    local val = cfg[pick]
    if val == nil then return line.missingDefault == true end
    return val == true
end

GFNS.ExtraClassRows = function(m, posY, SortKit)
    for _, k in ipairs({ "extraMyClass", "raidMyClass" }) do
        if SortKit.FLAG_KEYS and not tContains(SortKit.FLAG_KEYS, k) then
            SortKit.FLAG_KEYS[#SortKit.FLAG_KEYS + 1] = k
        end
    end
    local raids = SortKit.raids
    m.extraRolesEnd = posY
    m.extraItemH = SortKit.ITEM_H
    m.extraK = SortKit
    local roleG, miscG = Block(m, posY), Block(m, posY + SortKit.ITEM_H)
    m.extraClassGrp, m.extraMiscGrp = roleG, miscG
    local ry, my = 0, 0
    for _, line in ipairs(CLASS_ROWS) do
        local function ShowTip(self)
            if self.list and self.list:IsShown() then return end
            local title, lines = line.Tip(SortKit)
            SortKit.Tip(self, title, unpack(lines))
        end
        local inRoles = line.key == "extraMyClass"
        local key, pick = Keys(line, raids)
        local has, missing = line.has, line.missing
        local hasBtn, missingBtn
        local iconTex = line.spell and C_Spell.GetSpellTexture(line.spell)
        if inRoles then
            local label, file = MyClass()
            local cls = (label and file) and SortKit.ClassLine(file, label) or label or CUI.L("Class")
            has, missing = CUI.L("Has") .. " " .. cls, CUI.L("No") .. " " .. cls
            -- full alpha so the class color shows, has / no greyed by hand
            hasBtn, missingBtn =
                DIM_HEX .. CUI.L("Has") .. "|r " .. cls, DIM_HEX .. CUI.L("No") .. "|r " .. cls
            iconTex = file and ("classicon-" .. file:lower())
        end
        local entry = SortKit.MenuItem(inRoles and roleG or miscG, inRoles and ry or my, "", function()
            local c = SortKit.Cfg()
            c[key] = (not c[key]) or nil
            SortKit.Refilter()
            SortKit.Paint()
        end)
        m.items["flag_" .. key] = entry
        entry.label:Hide()
        local button = Dropdown(entry, SortKit, {
            { label = has, button = hasBtn, icon = iconTex },
            { label = missing, button = missingBtn, icon = iconTex },
        }, function() return Missing(SortKit.Cfg(), line, raids) and 2 or 1 end, function(index)
            -- picking turns the class row on; lust / brez leave the box alone
            local c = SortKit.Cfg()
            c[pick] = (index == 2)
            if inRoles then c[key] = true end
        end)
        button:SetHeight(SortKit.ITEM_H - 2)
        button:SetPoint("LEFT", entry, "LEFT", 8 + SortKit.CHECK_SZ + 7, 0)
        button:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
        button:SetScript("OnEnter", ShowTip)
        if inRoles then
            ry = ry + SortKit.ITEM_H
        else
            my = my + SortKit.ITEM_H
        end
    end
    roleG:SetHeight(ry)
    miscG:SetHeight(my)
    return posY + ry + my
end

-- false = drop the group. secret members don't count
GFNS.ExtraClassKeep = function(ident, details, cfg, raids)
    local mineKey = raids and "raidMyClass" or "extraMyClass"
    if not (cfg.hasLust or cfg.hasBrez or cfg[mineKey]) then return true end
    local num = details and details.numMembers
    if type(num) ~= "number" or Secret(num) then return true end
    local _, mine = MyClass()
    local have = { hasLust = false, hasBrez = false, extraMyClass = false }
    for index = 1, num do
        local p = C_LFGList.GetSearchResultPlayerInfo(ident, index)
        if p and (Secret(p) or (canaccesstable and not canaccesstable(p))) then p = nil end
        local cls = p and p.classFilename
        if cls and not Secret(cls) then
            if LUST[cls] then have.hasLust = true end
            if BREZ[cls] then have.hasBrez = true end
            if cls == mine then have.extraMyClass = true end
        end
    end
    for _, line in ipairs(CLASS_ROWS) do
        if cfg[Keys(line, raids)] and have[line.key] == Missing(cfg, line, raids) then return false end
    end
    return true
end

-------------------------------------------------------------------------------
--  region tags: where the leader plays from (us: region, eu: realm language)
-------------------------------------------------------------------------------
local function TagsOn()
    local cfg = GFNS.Cfg and GFNS.Cfg()
    return cfg and cfg.extraRegionTags ~= false and mod.RegionList() ~= nil
end

local function RegionOf(resultID)
    local details = C_LFGList.GetSearchResultInfo(resultID)
    if not details or Secret(details) or (canaccesstable and not canaccesstable(details)) then return nil end
    local leader = details.leaderName
    if not leader or Secret(leader) then return nil end
    local realm = leader:match("%-(.+)$") or (GetNormalizedRealmName and GetNormalizedRealmName())
    if not realm or Secret(realm) then return nil end
    return mod.RegionOfRealm(realm)
end

local tagOf = setmetatable({}, { __mode = "k" })

-- for our results list: tag, color, flag
function mod.RegionTagOf(resultID)
    if not TagsOn() then return nil end
    local skinData = mod.RegionInfo(RegionOf(resultID))
    if skinData then return skinData.tag, skinData.r, skinData.g, skinData.b, skinData.flag end
end

-- same tag for an applicant's "name-realm"
function mod.RegionTagOfName(label)
    if not TagsOn() or not label or Secret(label) then return nil end
    local realm = label:match("%-(.+)$") or (GetNormalizedRealmName and GetNormalizedRealmName())
    if not realm or Secret(realm) then return nil end
    local skinData = mod.RegionInfo(mod.RegionOfRealm(realm))
    if skinData then return skinData.tag, skinData.r, skinData.g, skinData.b, skinData.flag end
end

-- "Relaxed | OCE [flag]" after the playstyle on blizzard's row
local function Parts(record)
    local p = tagOf[record]
    if p then return p end
    local frame = CreateFrame("Frame", nil, record)
    frame:SetAllPoints(record)
    frame:SetFrameLevel(record:GetFrameLevel() + 4)
    frame:EnableMouse(false)
    p = {
        sep = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
        tag = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
        flag = frame:CreateTexture(nil, "OVERLAY"),
    }
    p.sep:SetText("||") -- escaped pipe draws one |
    p.sep:SetTextColor(0.35, 0.35, 0.35, 1)
    tagOf[record] = p
    return p
end

-------------------------------------------------------------------------------
--  row art: the instance's art fading across the left half
-------------------------------------------------------------------------------
local function RowArtOn()
    local cfg = GFNS.Cfg and GFNS.Cfg()
    return cfg and cfg.extraRowArt == true
end

-- instance art by map id: keystone background, else the journal's
local ART_CROP = { 0.205, 0.795, 0.25, 0.50 } -- a strip clear of the art's frame
local artOf = {}
local function MapArt(mapID)
    if not mapID or Secret(mapID) then return nil end
    local a = artOf[mapID]
    if a ~= nil then return a or nil end
    a = false
    local CMode = C_ChallengeMode
    for _, cm in ipairs(CMode and CMode.GetMapTable and CMode.GetMapTable() or {}) do
        local _, _, _, _, bgTex, mid = CMode.GetMapUIInfo(cm)
        if mid == mapID and bgTex then a = bgTex end
    end
    local CEJ = C_EncounterJournal
    if not a and CEJ and CEJ.GetInstanceForGameMap and EJ_GetInstanceInfo then
        local jid = CEJ.GetInstanceForGameMap(mapID)
        if jid then
            local _, _, bgImage, _, loreImage = EJ_GetInstanceInfo(jid)
            a = loreImage or bgImage or false
        end
    end
    artOf[mapID] = a
    return a or nil
end

local function Activity(resultID)
    local details = C_LFGList.GetSearchResultInfo(resultID)
    if not details or Secret(details) or (canaccesstable and not canaccesstable(details)) then return nil end
    local acts = details.activityIDs
    local act = type(acts) == "table" and not Secret(acts) and acts[1]
    if not act or Secret(act) then return nil end
    local ai = C_LFGList.GetActivityInfoTable(act)
    if not ai or Secret(ai) or (canaccesstable and not canaccesstable(ai)) then return nil end
    return ai
end

local ART_SHARE, ART_ALPHA = 0.5, 0.2 -- half the row, 20% fading out
local FADE_MASK = "Interface\\AddOns\\" .. FOLDER .. "\\media\\masks\\fade.png"

-- for our results list: a group's art (nil when off)
function mod.RowArtFor(resultID)
    if not RowArtOn() then return nil end
    local ai = Activity(resultID)
    return ai and MapArt(ai.mapID)
end
-- the same for an instance's map id (the settings preview)
function mod.RowArtForMap(mapID)
    if not RowArtOn() then return nil end
    return MapArt(mapID)
end
mod.ROW_ART = { crop = ART_CROP, share = ART_SHARE, alpha = ART_ALPHA, mask = FADE_MASK }

-- art under blizzard's text, the tag on our overlay above
local function RowArt(record, profile)
    local art = RowArtOn() and record.resultID
    local ai = art and Activity(record.resultID)
    art = ai and MapArt(ai.mapID)
    if not art then
        if profile.art then profile.art:Hide() end
        return
    end
    if not profile.art then
        profile.art = record:CreateTexture(nil, "BACKGROUND", nil, 7)
        profile.art:SetAlpha(ART_ALPHA)
        -- curved fade so the art's own frame never shows
        local mask = record:CreateMaskTexture()
        mask:SetTexture(FADE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(profile.art)
        profile.art:AddMaskTexture(mask)
    end
    profile.art:SetTexture(art)
    profile.art:SetTexCoord(unpack(ART_CROP))
    profile.art:ClearAllPoints()
    profile.art:SetPoint("TOPLEFT", record, "TOPLEFT", 3, -2)
    profile.art:SetPoint("BOTTOMLEFT", record, "BOTTOMLEFT", 3, 0)
    profile.art:SetWidth(math.max(1, math.floor((record:GetWidth() or 0) * ART_SHARE)))
    profile.art:Show()
end

local function TagEntry(record)
    if not (record and record.Playstyle) then return end
    local p = Parts(record)
    RowArt(record, p)
    p.sep:Hide()
    p.tag:Hide()
    p.flag:Hide()
    if not (TagsOn() and record.resultID) then return end
    local skinData = mod.RegionInfo(RegionOf(record.resultID))
    if not skinData then return end
    local play = record.Playstyle
    local success, _, px = pcall(play.GetFont, play)
    if success and type(px) == "number" and not Secret(px) and px > 0 then
        for _, fontStr in ipairs({ p.sep, p.tag }) do
            local filePath, _, flags = fontStr:GetFont()
            if filePath then fontStr:SetFont(filePath, px, flags or "") end
        end
    else
        px = 10
    end
    local okText, textValue = pcall(play.GetText, play)
    local hasPlay = okText and type(textValue) == "string" and not Secret(textValue) and textValue ~= ""
    p.tag:ClearAllPoints()
    if hasPlay then
        p.sep:ClearAllPoints()
        p.sep:SetPoint("LEFT", play, "RIGHT", 5, 0)
        p.sep:Show()
        p.tag:SetPoint("LEFT", p.sep, "RIGHT", 5, 0)
    else
        p.tag:SetPoint("LEFT", play, "LEFT", 0, 0)
    end
    p.tag:SetText(skinData.tag)
    p.tag:SetTextColor(skinData.r, skinData.g, skinData.b, 1)
    p.tag:Show()
    local art = skinData.flag
    if art then
        p.flag:SetTexture(art)
        p.flag:SetSize(math.floor(px * 4 / 3 + 0.5), px)
        p.flag:ClearAllPoints()
        p.flag:SetPoint("LEFT", p.tag, "RIGHT", 4, 0)
        p.flag:Show()
    end
end

local function RetagRows()
    local searchPane = LFGListFrame and LFGListFrame.SearchPanel
    local box = searchPane and searchPane.ScrollBox
    if box and box.ForEachFrame then box:ForEachFrame(TagEntry) end
    -- our results list too
    if mod.OwnListRefresh then mod.OwnListRefresh() end
end

mod.GFRetagRows = RetagRows -- for the settings page

if mod.WhenGroupFinder then
    mod.WhenGroupFinder(function()
        if LFGListSearchEntry_Update then hooksecurefunc("LFGListSearchEntry_Update", TagEntry) end
    end)
end

-- results list order (saved as extraSortBy)
mod.SORT_MODES = {
    { key = "default", label = CUI.L("Default") },
    { key = "high", label = CUI.L("Highest Score") },
    { key = "low", label = CUI.L("Lowest Score") },
    { key = "big", label = CUI.L("Largest Size") },
    { key = "small", label = CUI.L("Lowest Size") },
}

-- a menu row: label + dropdown
local function ChoiceItem(colour, posY, specInfo, G, up)
    local entry = CreateFrame("Frame", nil, colour)
    entry:SetHeight(G.ITEM_H)
    entry:SetPoint("TOPLEFT", colour, "TOPLEFT", 1, -posY)
    entry:SetPoint("TOPRIGHT", colour, "TOPRIGHT", -1, -posY)
    entry.label = entry:CreateFontString(nil, "OVERLAY")
    G.Font(entry.label, G.ITEM_FONT)
    entry.label:SetPoint("LEFT", entry, "LEFT", 9, 0)
    entry.label:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
    entry.label:SetText(specInfo.label)
    local modes = specInfo.choice
    local function Get()
        local val = G.Cfg()[specInfo.key]
        for index, modeName in ipairs(modes) do
            if modeName.key == val then return index end
        end
        return 1
    end
    local button = Dropdown(
        entry,
        G,
        modes,
        Get,
        function(index) G.Cfg()[specInfo.key] = modes[index].key end,
        up
    )
    button:SetHeight(G.ITEM_H - 2)
    button:SetPoint("LEFT", entry.label, "RIGHT", 10, 0)
    button:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
    entry.btn = button
    function entry:Paint() self.btn:ShowMode() end
    return entry
end

-------------------------------------------------------------------------------
--  menu icons: role icons and region flags
-------------------------------------------------------------------------------
local ROLE_DIR = "Interface\\AddOns\\CludesUIRaidFrames\\media\\"
-- same art for the results list's open slots
local ROLE_FILE = { TANK = "tank.png", HEALER = "healer.png", DAMAGER = "dps.png" }
function mod.RoleIconTex(role)
    local frame = ROLE_FILE[role]
    return frame and (ROLE_DIR .. frame)
end
local ICONS = {
    role_needsTank = { ROLE_DIR .. "tank.png", 12, 12 },
    role_needsHealer = { ROLE_DIR .. "healer.png", 12, 12 },
    role_needsDamage = { ROLE_DIR .. "dps.png", 12, 12 },
}
-- the region filter's flags, whichever region you're in
for _, skinData in ipairs(mod.RegionList() or {}) do
    ICONS["region_" .. skinData.key] = { skinData.flag, 13, 10 }
end

-- misc in two columns, lined up with the side panel
local function LayoutMisc(dropMenu, side)
    local roleG, miscG, sg = dropMenu.extraClassGrp, dropMenu.extraMiscGrp, dropMenu.extraSpecGrp
    if not (roleG and miscG and sg and dropMenu.extraRolesEnd) then return end
    local posY = dropMenu.extraRolesEnd
    PlaceBlock(sg, dropMenu, posY)
    posY = posY + sg:GetHeight()
    local miscY, rowsY = side and side.extraMiscY, side and side.extraMiscRowsY
    if miscY and rowsY and miscY >= posY then
        Divider(dropMenu, miscY)
        posY = rowsY
    else
        posY = Divider(dropMenu, posY)
    end
    PlaceBlock(miscG, dropMenu, posY)
    posY = posY + miscG:GetHeight()
    PlaceBlock(roleG, dropMenu, posY)
    posY = posY + roleG:GetHeight()
    -- sort by under your class, its list opening upwards
    local SortKit = dropMenu.extraK
    if SortKit then
        local line = CreateFrame("Frame", nil, dropMenu)
        line:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 0, -posY)
        line:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", 0, -posY)
        line:SetHeight(SortKit.ITEM_H)
        ChoiceItem(
            line,
            0,
            { key = "extraSortBy", label = CUI.L("Sort By"), choice = mod.SORT_MODES },
            SortKit,
            true
        )
        posY = posY + SortKit.ITEM_H
    end
    local hgt = math.max(side and side.extraEndY and (side.extraEndY + 3) or 0, posY + 3)
    dropMenu:SetHeight(hgt)
    if side then side:SetHeight(hgt) end
end

GFNS.ExtraDecorateMenu = function(dropMenu, side)
    if dropMenu then LayoutMisc(dropMenu, side) end
    for _, ownerFrame in ipairs({ dropMenu, side }) do
        local itemList = ownerFrame and ownerFrame.items
        if itemList then
            for key, art in pairs(ICONS) do
                local entry = itemList[key]
                if entry and entry.label and not entry.extraIcon then
                    local _, callback = entry.label:GetPoint(1)
                    if callback then
                        local texture = entry:CreateTexture(nil, "OVERLAY")
                        texture:SetTexture(art[1])
                        texture:SetSize(art[2], art[3])
                        texture:SetPoint("LEFT", callback, "RIGHT", 6, 0)
                        entry.label:ClearAllPoints()
                        entry.label:SetPoint("LEFT", texture, "RIGHT", 5, 0)
                        entry.label:SetPoint("RIGHT", entry, "RIGHT", -4, 0)
                        entry.extraIcon = texture
                    end
                end
            end
        end
    end
end

GFNS.ExtraRaidTex = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\cui-raid.png"
