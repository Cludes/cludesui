if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_GroupFinder_Extras.lua - the extra filters and looks:
--  has / missing rows, specific roles, menu icons, group settings columns,
--  region tags, row art, the scrolling strips, the person / raid icons
-------------------------------------------------------------------------------
local FOLDER, mod = ...
if CludesUI.HELD_BACK_ADDONS[FOLDER] then
    return
end -- held back (CludesUIGroupFinder.lua)
mod.CUI = CludesUI

-- runs fn once blizzard's group finder loads
function mod.WhenGroupFinder(func)
    -- module off: nothing hooks in
    if not mod.Enabled() or mod.Blocked() then
        return
    end
    if C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder") and PVEFrame then
        func()
        return
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, name)
        if name ~= "Blizzard_GroupFinder" then
            return
        end
        self:UnregisterAllEvents()
        func()
    end)
end
local GFNS = mod

-- specific roles: match all (and) or match any (or)
GFNS.ExtraRolesAny = function()
    local c = GFNS.Cfg and GFNS.Cfg()
    return c and c.extraRolesAny == true or false
end

local CM = mod.CUI
local Secret = CludesUI.IsSecret
local HINT_GREY = 0.35 -- the (and) / (or) bit, never takes the accent
-- dim label grey
local DIM_HEX = CludesUI.COLOR_CODES.DIM

-- label + grey hint
local function TwoPart(ownerFrame, K)
    local main = ownerFrame:CreateFontString(nil, "OVERLAY")
    K.Font(main, K.ITEM_FONT)
    main:SetPoint("LEFT", ownerFrame, "LEFT", 7, 0)
    local hint = ownerFrame:CreateFontString(nil, "OVERLAY")
    K.Font(hint, K.ITEM_FONT)
    hint:SetPoint("LEFT", main, "RIGHT", 3, 0)
    hint:SetTextColor(HINT_GREY, HINT_GREY, HINT_GREY, 1)
    return main, hint
end

local ARROW = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\cui-arrow.png"

-- our dropdowns can hang outside the menu: clicks in them keep it open
local pops = {}
GFNS.ExtraInside = function()
    for _, f in ipairs(pops) do
        if f:IsShown() and f:IsMouseOver() then
            return true
        end
    end
    return false
end

local MASK = "Interface\\AddOns\\" .. FOLDER .. "\\media\\masks\\rounded.png"

-- an atlas name, or a spell's texture (cropped to lose its built-in border)
local function PaintIcon(ic, glyph)
    if type(glyph) == "number" then
        ic:SetTexture(glyph)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        ic:SetAtlas(glyph)
    end
end

-- rounded icon after the text
local function RoundIcon(hostFrame, glyph, after)
    local ic = hostFrame:CreateTexture(nil, "OVERLAY")
    ic:SetSize(12, 12)
    ic:SetPoint("LEFT", after, "RIGHT", 4, 0)
    if glyph then
        PaintIcon(ic, glyph)
    end
    local maskTex = hostFrame:CreateMaskTexture()
    maskTex:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    maskTex:SetAllPoints(ic)
    ic:AddMaskTexture(maskTex)
    ic.mask = maskTex
    return ic
end

-- skinned dropdown button: label, grey hint, arrow
local function ArrowButton(ownerFrame, K)
    local btn = CreateFrame("Button", nil, ownerFrame)
    btn:SetNormalFontObject("GameFontHighlight")
    btn:SetText(" ")
    btn.Arrow = btn:CreateTexture(nil, "OVERLAY")
    btn.Arrow:SetTexture(ARROW)
    btn.Arrow:SetSize(13, 13) -- how it looks in the settings
    btn.Arrow:SetPoint("CENTER", btn, "RIGHT", -10, 0)
    btn.Label, btn.Hint = TwoPart(btn, K)
    btn.Label:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
    -- icon room, made before the skin so it survives
    btn.Icon = RoundIcon(btn, nil, btn.Label)
    btn.IconMask = btn.Icon.mask
    btn.Icon:Hide()
    local skin = CM._ModuleNS and CM._ModuleNS.CludesUIBlizzardSkin
    local Stl = skin and skin.WSkin
    if Stl and Stl.Button then
        Stl.Button(btn, { "Arrow", "Label", "Hint", "Icon", "IconMask" })
    else
        local backdrop = btn:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        CM.MakeBorder(btn, K.ThemeBorder())
        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.1)
    end
    return btn
end

-- under the button, or above it if it'd hang off the menu
local function OpenNear(pop, btn, bounds, pad)
    pad = pad or 0
    pop:ClearAllPoints()
    local bb, mb = btn:GetBottom(), bounds and bounds:GetBottom()
    if
        bb
        and mb
        and (bb - 2 - pop:GetHeight()) * btn:GetEffectiveScale() < mb * bounds:GetEffectiveScale()
    then
        pop:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", -pad, 2)
        pop:SetPoint("BOTTOMRIGHT", btn, "TOPRIGHT", pad, 2)
    else
        pop:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", -pad, -2)
        pop:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", pad, -2)
    end
    pop:Show()
end

-- arrow button + its list. modes = { label, hint, icon }, get() = index,
-- set(i) on pick, up opens it above the button. caller places it
local function Dropdown(ownerFrame, K, modes, Get, Set, up)
    local btn = ArrowButton(ownerFrame, K)
    function btn:ShowMode()
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
    btn:ShowMode()

    local entries = CreateFrame("Frame", nil, K.parent or ownerFrame)
    entries:SetFrameStrata("FULLSCREEN_DIALOG")
    entries:SetFrameLevel(330)
    entries:SetClampedToScreen(true)
    entries:EnableMouse(true)
    local lbg = entries:CreateTexture(nil, "BACKGROUND")
    lbg:SetAllPoints()
    lbg:SetColorTexture(0, 0, 0, 1)
    CM.MakeBorder(entries, K.ThemeBorder())
    entries.items = {}
    for idx, modeName in ipairs(modes) do
        local it = CreateFrame("Button", nil, entries)
        it:SetHeight(K.ITEM_H)
        it:SetPoint("TOPLEFT", entries, "TOPLEFT", 1, -(2 + (idx - 1) * K.ITEM_H))
        it:SetPoint("TOPRIGHT", entries, "TOPRIGHT", -1, -(2 + (idx - 1) * K.ITEM_H))
        it.text, it.hint = TwoPart(it, K)
        it.text:SetText(modeName.label)
        it.hint:SetText(modeName.hint or "")
        if modeName.icon then
            RoundIcon(it, modeName.icon, it.text)
        end
        local ihl = it:CreateTexture(nil, "HIGHLIGHT")
        ihl:SetAllPoints()
        ihl:SetColorTexture(1, 1, 1, CM.DD_ITEM_HL_A or 0.08)
        it:SetScript("OnClick", function()
            Set(idx)
            btn:ShowMode()
            entries:Hide()
            K.Refilter()
            K.Paint()
        end)
        entries.items[idx] = it
    end
    entries:SetHeight(4 + #modes * K.ITEM_H)
    btn.list = entries
    pops[#pops + 1] = entries
    K.ClickOff(entries, function(self)
        return self:IsMouseOver() or btn:IsMouseOver()
    end)
    entries:Hide()

    btn:SetScript("OnClick", function()
        if entries:IsShown() then
            entries:Hide()
            return
        end
        K.Untip()
        -- picked one in the accent color
        local ar, ag, ab = K.Accent()
        for idx, it in ipairs(entries.items) do
            if idx == Get() then
                it.text:SetTextColor(ar, ag, ab, 1)
            else
                it.text:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
            end
        end
        entries:ClearAllPoints()
        if up then
            entries:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 2)
            entries:SetPoint("BOTTOMRIGHT", btn, "TOPRIGHT", 0, 2)
        else
            entries:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            entries:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
        end
        entries:Show()
    end)
    btn:SetScript("OnHide", function()
        entries:Hide()
    end)
    btn:SetScript("OnShow", function(self)
        self:ShowMode()
    end)
    btn:SetScript("OnLeave", K.Untip)
    return btn
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
    local f = CreateFrame("Frame", nil, m)
    f:SetPoint("TOPLEFT", m, "TOPLEFT", 0, -posY)
    f:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, -posY)
    return f
end

local function PlaceBlock(f, m, posY)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", m, "TOPLEFT", 0, -posY)
    f:SetPoint("TOPRIGHT", m, "TOPRIGHT", 0, -posY)
end

local MATCH = {
    {
        any = false,
        label = CludesUI.L("Match All"),
        hint = "(and)",
        tip = CludesUI.L("Match all of the selected options below."),
    },
    {
        any = true,
        label = CludesUI.L("Match Any"),
        hint = "(or)",
        tip = CludesUI.L("Match any of the selected options below."),
    },
}

local function CountsOn(c)
    local num = 0
    for _, rule in pairs(type(c.roleCounts) == "table" and c.roleCounts or {}) do
        if type(rule) == "table" and rule.on then
            num = num + 1
        end
    end
    return num
end

GFNS.ExtraRoleCounts = function(m, posY, K)
    local sg = Block(m, posY)
    sg:SetHeight(K.ITEM_H)
    m.extraSpecGrp = sg
    local btn = ArrowButton(sg, K)
    btn:SetHeight(K.ITEM_H - 2)
    btn:SetPoint("TOPLEFT", sg, "TOPLEFT", 9, -1)
    btn:SetPoint("TOPRIGHT", sg, "TOPRIGHT", -9, -1)
    btn.Label:SetText(CludesUI.L("Specific Roles"))

    local pop = CreateFrame("Frame", nil, K.parent or m)
    pop:SetFrameStrata("FULLSCREEN_DIALOG")
    pop:SetFrameLevel(325)
    pop:SetClampedToScreen(true)
    pop:EnableMouse(true)
    local pbg = pop:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    local fr, fg, fb = K.ThemeFill()
    pbg:SetColorTexture(fr, fg, fb, 0.98)
    CM.MakeBorder(pop, K.ThemeBorder())
    pops[#pops + 1] = pop

    -- while open: veil over both columns, eats clicks
    local veil = CreateFrame("Button", nil, K.parent or m)
    veil:SetFrameStrata("FULLSCREEN_DIALOG")
    veil:SetFrameLevel(m:GetFrameLevel() + 8)
    local vt = veil:CreateTexture(nil, "BACKGROUND")
    vt:SetAllPoints()
    vt:SetColorTexture(fr, fg, fb, 0.7)
    veil:Hide()

    local py, toggles = 2, {}
    local function PaintMatch()
        local any = K.Cfg().extraRolesAny == true
        for _, t in ipairs(toggles) do
            t:SetChecked(t.any == any)
        end
    end
    for _, modeName in ipairs(MATCH) do
        local t = K.MenuItem(pop, py, modeName.label, function()
            K.Cfg().extraRolesAny = modeName.any or nil
            PaintMatch()
            K.Refilter()
            K.Paint()
        end)
        t.any = modeName.any
        local _, cb = t.label:GetPoint(1)
        t.label:ClearAllPoints()
        t.label:SetPoint("LEFT", cb, "RIGHT", 7, 0)
        local hint = t:CreateFontString(nil, "OVERLAY")
        K.Font(hint, K.ITEM_FONT)
        hint:SetPoint("LEFT", t.label, "RIGHT", 3, 0)
        hint:SetTextColor(HINT_GREY, HINT_GREY, HINT_GREY, 1)
        hint:SetText(modeName.hint)
        t:HookScript("OnEnter", function(self)
            K.Tip(self, modeName.tip)
        end)
        t:HookScript("OnLeave", K.Untip)
        toggles[#toggles + 1] = t
        py = py + K.ITEM_H
    end
    py = Divider(pop, py)
    -- count rows go in m.counts so the menu paints them
    m.counts = m.counts or {}
    pop.counts = m.counts
    for _, r in ipairs(K.COUNT_ROLES) do
        py = K.AddCountRow(pop, py, r.key, r.label)
    end
    pop:SetHeight(py + 2)
    K.ClickOff(pop, function(self)
        return self:IsMouseOver() or btn:IsMouseOver() or (K.OpListOver and K.OpListOver()) or false
    end)
    pop:Hide()

    -- "(2 active)" so ticked rows aren't forgotten
    local function ShowHint()
        local num = CountsOn(K.Cfg())
        btn.Hint:SetText(num > 0 and CludesUI.Lf("(%1$d active)", num) or "")
    end
    local sgLevel = sg:GetFrameLevel()
    pop:HookScript("OnShow", function()
        PaintMatch()
        veil:ClearAllPoints()
        veil:SetPoint("TOPLEFT", m.side or m, "TOPLEFT", 0, 0)
        veil:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 0, 0)
        veil:Show()
        sg:SetFrameLevel(veil:GetFrameLevel() + 1) -- keeps the button lit
    end)
    pop:HookScript("OnHide", function()
        veil:Hide()
        sg:SetFrameLevel(sgLevel)
        ShowHint()
    end)
    btn:SetScript("OnClick", function()
        if pop:IsShown() then
            pop:Hide()
            return
        end
        OpenNear(pop, btn, m)
    end)
    btn:SetScript("OnShow", ShowHint)
    btn:SetScript("OnHide", function()
        pop:Hide()
    end)
    ShowHint()
    return posY + K.ITEM_H
end

-------------------------------------------------------------------------------
--  raids and delves: squares in one sideways-scrolling line instead of a
--  grid that pushes the list down
-------------------------------------------------------------------------------
local ARROW_W = 14
local ARROW_DIR = "Interface\\AddOns\\CludesUI\\media\\icons\\"

local function PlaceStrip(s)
    if not s.list then
        return
    end
    local per = s.size + s.gap
    -- whole steps only, stops once the last square is fully in view
    local full = math.max(1, math.floor((s.clipW + s.gap) / per))
    local maxOff = math.max(0, #s.list - full)
    s.offset = math.max(0, math.min(s.offset, maxOff))
    local shift = -s.offset * per
    for idx, sq in ipairs(s.squares) do
        local d = s.list[idx]
        if d then
            local posX = (idx - 1) * per + shift
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

local function ScrollStrip(s, step)
    s.offset = s.offset + step
    if GFNS.ExtraHideBossPick then
        GFNS.ExtraHideBossPick()
    end
    PlaceStrip(s)
    if s.paint then
        s.paint()
    end -- recolor the squares now in view
end

local function StripArrow(s, rowFrame, file, step)
    local b = CreateFrame("Button", nil, rowFrame)
    b.tex = b:CreateTexture(nil, "OVERLAY")
    b.tex:SetTexture(ARROW_DIR .. file)
    b.tex:SetSize(16, 16)
    b.tex:SetPoint("CENTER")
    b:SetScript("OnClick", function()
        ScrollStrip(s, step)
    end)
    b:SetScript("OnEnter", function(self)
        if self.live then
            self.tex:SetAlpha(1)
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.tex:SetAlpha(self.live and 0.8 or 0.2)
    end)
    return b
end

-- one strip. key = the square's data field, fill dresses a square
local function NewStrip(key, fillTex)
    local s = { offset = 0 }
    return function(entries, squares, Make, dim, after, show, cols, slots, rowFrame, gap, paint)
        s.paint = paint
        if not s.clip then
            s.clip = CreateFrame("Frame", nil, rowFrame)
            s.clip:SetClipsChildren(true)
            s.clip:EnableMouseWheel(true)
            s.clip:SetScript("OnMouseWheel", function(_, delta)
                ScrollStrip(s, delta > 0 and -1 or 1)
            end)
            s.left = StripArrow(s, rowFrame, "cui-arrow-left.png", -1)
            s.right = StripArrow(s, rowFrame, "cui-arrow-right.png", 1)
        end
        if not show or #entries == 0 or not after then
            for _, sq in ipairs(squares) do
                sq[key] = nil
                sq:Hide()
            end
            s.clip:Hide()
            s.left:Hide()
            s.right:Hide()
            s.list = nil
            return 1
        end
        local per = dim + gap
        local startX = gap + (slots - cols) * per
        local room = cols * per - gap
        local fits = #entries * per - gap <= room
        local vis = fits and #entries or math.max(1, math.floor((room - 2 * (ARROW_W + gap) + gap) / per))
        s.clip:ClearAllPoints()
        s.left:ClearAllPoints()
        s.right:ClearAllPoints()
        s.left:SetSize(ARROW_W, dim)
        s.right:SetSize(ARROW_W, dim)
        if fits then
            s.left:Hide()
            s.right:Hide()
            s.clip:SetPoint("LEFT", after, "RIGHT", startX, 0)
        else
            s.left:SetPoint("LEFT", after, "RIGHT", startX, 0)
            s.left:Show()
            s.clip:SetPoint("LEFT", s.left, "RIGHT", gap, 0)
        end
        -- scrolling: runs to the row's right edge
        local clipW = vis * per - gap
        if fits then
            s.clip:SetSize(clipW, dim)
        else
            s.right:SetPoint("RIGHT", rowFrame, "RIGHT", 4, 0) -- a touch wider so the last border isn't clipped
            s.right:Show()
            s.clip:SetPoint("RIGHT", s.right, "LEFT", -gap, 0)
            s.clip:SetHeight(dim)
            clipW = room + 4 - 2 * (ARROW_W + gap)
        end
        s.clip:Show()
        for idx, d in ipairs(entries) do
            local sq = squares[idx]
            if not sq then
                sq = Make()
                squares[idx] = sq
            end
            if sq:GetParent() ~= s.clip then
                sq:SetParent(s.clip)
            end
            sq[key] = d
            fillTex(sq, d)
            sq:SetSize(dim, dim)
        end
        for idx = #entries + 1, #squares do
            squares[idx][key] = nil
            squares[idx]:Hide()
        end
        s.list, s.squares, s.size, s.gap, s.clipW = entries, squares, dim, gap, clipW
        PlaceStrip(s)
        return 1
    end
end

GFNS.ExtraBossStrip = NewStrip("boss", function(sq, d)
    sq.icon:SetTexture(d.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
end)
-- delves: the module dresses its squares
GFNS.ExtraDelveStrip = NewStrip("delve", function(sq, d)
    if GFNS.GFDressDelve then
        GFNS.GFDressDelve(sq, d)
    end
end)

-- filters menu spans search box to refresh
GFNS.ExtraWidenMenu = function(m, anchorFrame, gap, right)
    local sp = LFGListFrame and LFGListFrame.SearchPanel
    local leftX = sp and (sp.SearchBox or sp.BackButton)
    if not (leftX and leftX:IsVisible() and leftX:GetLeft() and anchorFrame:GetLeft()) then
        return
    end
    -- split evenly
    if m.side and right and right:GetRight() then
        local sum = (
            right:GetRight() * right:GetEffectiveScale() - leftX:GetLeft() * leftX:GetEffectiveScale()
        ) / m:GetEffectiveScale()
        if sum > 100 then
            m.side:SetWidth(math.floor(sum / 2 + 0.5))
        end
    end
    local sideW = m.side and m.side:GetWidth() or 0
    local dx = (
        leftX:GetLeft() * leftX:GetEffectiveScale()
        - anchorFrame:GetLeft() * anchorFrame:GetEffectiveScale()
    )
            / m:GetEffectiveScale()
        + sideW
    m:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", dx, -gap)
end

-------------------------------------------------------------------------------
--  has / missing rows: bloodlust, battle res and your class
-------------------------------------------------------------------------------
local LUST = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
local BREZ = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true }

local function MyClass()
    local name, file = UnitClass("player")
    return name, file
end

local CLASS_ROWS = {
    {
        key = "hasLust",
        pick = "extraLustMissing",
        spell = 2825,
        has = CludesUI.L("Has Bloodlust"),
        missing = CludesUI.L("Missing Bloodlust"),
        Tip = function(K)
            return CludesUI.L("Bloodlust"),
                {
                    CludesUI.L("A member whose class has one of these spells:"),
                    K.ClassLine("SHAMAN", CludesUI.L("Bloodlust / Heroism (Shaman)")),
                    K.ClassLine("MAGE", CludesUI.L("Time Warp (Mage)")),
                    K.ClassLine("HUNTER", CludesUI.L("Primal Rage (Hunter pet)")),
                    K.ClassLine("EVOKER", CludesUI.L("Fury of the Aspects (Evoker)")),
                    CludesUI.L("Drums and other items don't count."),
                }
        end,
    },
    {
        key = "hasBrez",
        pick = "extraBrezMissing",
        spell = 20484,
        has = CludesUI.L("Has Battle Res"),
        missing = CludesUI.L("Missing Battle Res"),
        Tip = function(K)
            return CludesUI.L("Battle Res"),
                {
                    CludesUI.L("A member whose class has one of these spells:"),
                    K.ClassLine("DRUID", CludesUI.L("Rebirth (Druid)")),
                    K.ClassLine("DEATHKNIGHT", CludesUI.L("Raise Ally (Death Knight)")),
                    K.ClassLine("WARLOCK", CludesUI.L("Soulstone (Warlock)")),
                    K.ClassLine("PALADIN", CludesUI.L("Intercession (Paladin)")),
                    CludesUI.L("Engineering and other items don't count."),
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
        Tip = function(K)
            local name, file = MyClass()
            return CludesUI.L("Your Class"),
                {
                    CludesUI.Lf(
                        "A member who's your class: %1$s",
                        file and K.ClassLine(file, name) or name or ""
                    ),
                }
        end,
    },
}

-- the row's keys on this tab
local function Keys(rowFrame, raids)
    if raids and rowFrame.raidKey then
        return rowFrame.raidKey, rowFrame.raidPick
    end
    return rowFrame.key, rowFrame.pick
end

local function Missing(c, rowFrame, raids)
    local _, pick = Keys(rowFrame, raids)
    local val = c[pick]
    if val == nil then
        return rowFrame.missingDefault == true
    end
    return val == true
end

GFNS.ExtraClassRows = function(m, posY, K)
    for _, k in ipairs({ "extraMyClass", "raidMyClass" }) do
        if K.FLAG_KEYS and not tContains(K.FLAG_KEYS, k) then
            K.FLAG_KEYS[#K.FLAG_KEYS + 1] = k
        end
    end
    local raids = K.raids
    m.extraRolesEnd = posY
    m.extraItemH = K.ITEM_H
    m.extraK = K
    local roleG, miscG = Block(m, posY), Block(m, posY + K.ITEM_H)
    m.extraClassGrp, m.extraMiscGrp = roleG, miscG
    local ry, my = 0, 0
    for _, rowFrame in ipairs(CLASS_ROWS) do
        local function ShowTip(self)
            if self.list and self.list:IsShown() then
                return
            end
            local titleText, lines = rowFrame.Tip(K)
            K.Tip(self, titleText, unpack(lines))
        end
        local inRoles = rowFrame.key == "extraMyClass"
        local key, pick = Keys(rowFrame, raids)
        local has, missing = rowFrame.has, rowFrame.missing
        local hasBtn, missingBtn
        local glyph = rowFrame.spell and C_Spell.GetSpellTexture(rowFrame.spell)
        if inRoles then
            local name, file = MyClass()
            local cls = (name and file) and K.ClassLine(file, name) or name or CludesUI.L("Class")
            has, missing = CludesUI.L("Has") .. " " .. cls, CludesUI.L("No") .. " " .. cls
            -- full alpha so the class color shows, has / no greyed by hand
            hasBtn, missingBtn =
                DIM_HEX .. CludesUI.L("Has") .. "|r " .. cls, DIM_HEX .. CludesUI.L("No") .. "|r " .. cls
            glyph = file and ("classicon-" .. file:lower())
        end
        local itemInfo = K.MenuItem(inRoles and roleG or miscG, inRoles and ry or my, "", function()
            local c = K.Cfg()
            c[key] = (not c[key]) or nil
            K.Refilter()
            K.Paint()
        end)
        m.items["flag_" .. key] = itemInfo
        itemInfo.label:Hide()
        local btn = Dropdown(itemInfo, K, {
            { label = has, button = hasBtn, icon = glyph },
            { label = missing, button = missingBtn, icon = glyph },
        }, function()
            return Missing(K.Cfg(), rowFrame, raids) and 2 or 1
        end, function(idx)
            -- picking turns the class row on; lust / brez leave the box alone
            local c = K.Cfg()
            c[pick] = (idx == 2)
            if inRoles then
                c[key] = true
            end
        end)
        btn:SetHeight(K.ITEM_H - 2)
        btn:SetPoint("LEFT", itemInfo, "LEFT", 8 + K.CHECK_SZ + 7, 0)
        btn:SetPoint("RIGHT", itemInfo, "RIGHT", -8, 0)
        btn:SetScript("OnEnter", ShowTip)
        if inRoles then
            ry = ry + K.ITEM_H
        else
            my = my + K.ITEM_H
        end
    end
    roleG:SetHeight(ry)
    miscG:SetHeight(my)
    return posY + ry + my
end

-- false = drop the group. secret members don't count
GFNS.ExtraClassKeep = function(ident, details, c, raids)
    local mineKey = raids and "raidMyClass" or "extraMyClass"
    if not (c.hasLust or c.hasBrez or c[mineKey]) then
        return true
    end
    local num = details and details.numMembers
    if type(num) ~= "number" or Secret(num) then
        return true
    end
    local _, mine = MyClass()
    local have = { hasLust = false, hasBrez = false, extraMyClass = false }
    for idx = 1, num do
        local p = C_LFGList.GetSearchResultPlayerInfo(ident, idx)
        if p and (Secret(p) or (canaccesstable and not canaccesstable(p))) then
            p = nil
        end
        local cls = p and p.classFilename
        if cls and not Secret(cls) then
            if LUST[cls] then
                have.hasLust = true
            end
            if BREZ[cls] then
                have.hasBrez = true
            end
            if cls == mine then
                have.extraMyClass = true
            end
        end
    end
    for _, rowFrame in ipairs(CLASS_ROWS) do
        if c[Keys(rowFrame, raids)] and have[rowFrame.key] == Missing(c, rowFrame, raids) then
            return false
        end
    end
    return true
end

-------------------------------------------------------------------------------
--  region tags: where the leader plays from (us: region, eu: realm language)
-------------------------------------------------------------------------------
local function TagsOn()
    local c = GFNS.Cfg and GFNS.Cfg()
    return c and c.extraRegionTags ~= false and mod.RegionList() ~= nil
end

local function RegionOf(resultID)
    local details = C_LFGList.GetSearchResultInfo(resultID)
    if not details or Secret(details) or (canaccesstable and not canaccesstable(details)) then
        return nil
    end
    local leader = details.leaderName
    if not leader or Secret(leader) then
        return nil
    end
    local realm = leader:match("%-(.+)$") or (GetNormalizedRealmName and GetNormalizedRealmName())
    if not realm or Secret(realm) then
        return nil
    end
    return mod.RegionOfRealm(realm)
end

local tagOf = setmetatable({}, { __mode = "k" })

-- for our results list: tag, color, flag
function mod.RegionTagOf(resultID)
    if not TagsOn() then
        return nil
    end
    local d = mod.RegionInfo(RegionOf(resultID))
    if d then
        return d.tag, d.r, d.g, d.b, d.flag
    end
end

-- same tag for an applicant's "name-realm"
function mod.RegionTagOfName(name)
    if not TagsOn() or not name or Secret(name) then
        return nil
    end
    local realm = name:match("%-(.+)$") or (GetNormalizedRealmName and GetNormalizedRealmName())
    if not realm or Secret(realm) then
        return nil
    end
    local d = mod.RegionInfo(mod.RegionOfRealm(realm))
    if d then
        return d.tag, d.r, d.g, d.b, d.flag
    end
end

-- "Relaxed | OCE [flag]" after the playstyle on blizzard's row
local function Parts(record)
    local p = tagOf[record]
    if p then
        return p
    end
    local f = CreateFrame("Frame", nil, record)
    f:SetAllPoints(record)
    f:SetFrameLevel(record:GetFrameLevel() + 4)
    f:EnableMouse(false)
    p = {
        sep = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
        tag = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
        flag = f:CreateTexture(nil, "OVERLAY"),
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
    local c = GFNS.Cfg and GFNS.Cfg()
    return c and c.extraRowArt == true
end

-- instance art by map id: keystone background, else the journal's
local ART_CROP = { 0.205, 0.795, 0.25, 0.50 } -- a strip clear of the art's frame
local artOf = {}
local function Art(mapID)
    if not mapID or Secret(mapID) then
        return nil
    end
    local a = artOf[mapID]
    if a ~= nil then
        return a or nil
    end
    a = false
    local CMode = C_ChallengeMode
    for _, cm in ipairs(CMode and CMode.GetMapTable and CMode.GetMapTable() or {}) do
        local _, _, _, _, bgTex, mid = CMode.GetMapUIInfo(cm)
        if mid == mapID and bgTex then
            a = bgTex
        end
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
    if not details or Secret(details) or (canaccesstable and not canaccesstable(details)) then
        return nil
    end
    local acts = details.activityIDs
    local act = type(acts) == "table" and not Secret(acts) and acts[1]
    if not act or Secret(act) then
        return nil
    end
    local ai = C_LFGList.GetActivityInfoTable(act)
    if not ai or Secret(ai) or (canaccesstable and not canaccesstable(ai)) then
        return nil
    end
    return ai
end

local ART_SHARE, ART_ALPHA = 0.5, 0.2 -- half the row, 20% fading out
local FADE_MASK = "Interface\\AddOns\\" .. FOLDER .. "\\media\\masks\\fade.png"

-- for our results list: a group's art (nil when off)
function mod.RowArtFor(resultID)
    if not RowArtOn() then
        return nil
    end
    local ai = Activity(resultID)
    return ai and Art(ai.mapID)
end
-- the same for an instance's map id (the settings preview)
function mod.RowArtForMap(mapID)
    if not RowArtOn() then
        return nil
    end
    return Art(mapID)
end
mod.ROW_ART = { crop = ART_CROP, share = ART_SHARE, alpha = ART_ALPHA, mask = FADE_MASK }

-- art under blizzard's text, the tag on our overlay above
local function RowArt(record, p)
    local art = RowArtOn() and record.resultID
    local ai = art and Activity(record.resultID)
    art = ai and Art(ai.mapID)
    if not art then
        if p.art then
            p.art:Hide()
        end
        return
    end
    if not p.art then
        p.art = record:CreateTexture(nil, "BACKGROUND", nil, 7)
        p.art:SetAlpha(ART_ALPHA)
        -- curved fade so the art's own frame never shows
        local maskTex = record:CreateMaskTexture()
        maskTex:SetTexture(FADE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        maskTex:SetAllPoints(p.art)
        p.art:AddMaskTexture(maskTex)
    end
    p.art:SetTexture(art)
    p.art:SetTexCoord(unpack(ART_CROP))
    p.art:ClearAllPoints()
    p.art:SetPoint("TOPLEFT", record, "TOPLEFT", 3, -2)
    p.art:SetPoint("BOTTOMLEFT", record, "BOTTOMLEFT", 3, 0)
    p.art:SetWidth(math.max(1, math.floor((record:GetWidth() or 0) * ART_SHARE)))
    p.art:Show()
end

local function TagEntry(record)
    if not (record and record.Playstyle) then
        return
    end
    local p = Parts(record)
    RowArt(record, p)
    p.sep:Hide()
    p.tag:Hide()
    p.flag:Hide()
    if not (TagsOn() and record.resultID) then
        return
    end
    local d = mod.RegionInfo(RegionOf(record.resultID))
    if not d then
        return
    end
    local play = record.Playstyle
    local success, _, dim = pcall(play.GetFont, play)
    if success and type(dim) == "number" and not Secret(dim) and dim > 0 then
        for _, fontStr in ipairs({ p.sep, p.tag }) do
            local filePath, _, flags = fontStr:GetFont()
            if filePath then
                fontStr:SetFont(filePath, dim, flags or "")
            end
        end
    else
        dim = 10
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
    p.tag:SetText(d.tag)
    p.tag:SetTextColor(d.r, d.g, d.b, 1)
    p.tag:Show()
    local art = d.flag
    if art then
        p.flag:SetTexture(art)
        p.flag:SetSize(math.floor(dim * 4 / 3 + 0.5), dim)
        p.flag:ClearAllPoints()
        p.flag:SetPoint("LEFT", p.tag, "RIGHT", 4, 0)
        p.flag:Show()
    end
end

local function RetagRows()
    local sp = LFGListFrame and LFGListFrame.SearchPanel
    local boxFrame = sp and sp.ScrollBox
    if boxFrame and boxFrame.ForEachFrame then
        boxFrame:ForEachFrame(TagEntry)
    end
    -- our results list too
    if mod.OwnListRefresh then
        mod.OwnListRefresh()
    end
end

mod.GFRetagRows = RetagRows -- for the settings page

if mod.WhenGroupFinder then
    mod.WhenGroupFinder(function()
        if LFGListSearchEntry_Update then
            hooksecurefunc("LFGListSearchEntry_Update", TagEntry)
        end
    end)
end

-- results list order (saved as extraSortBy)
mod.SORT_MODES = {
    { key = "default", label = CludesUI.L("Default") },
    { key = "high", label = CludesUI.L("Highest Score") },
    { key = "low", label = CludesUI.L("Lowest Score") },
    { key = "big", label = CludesUI.L("Largest Size") },
    { key = "small", label = CludesUI.L("Lowest Size") },
}

-- a menu row: label + dropdown
local function ChoiceItem(column, posY, specInfo, G, up)
    local itemInfo = CreateFrame("Frame", nil, column)
    itemInfo:SetHeight(G.ITEM_H)
    itemInfo:SetPoint("TOPLEFT", column, "TOPLEFT", 1, -posY)
    itemInfo:SetPoint("TOPRIGHT", column, "TOPRIGHT", -1, -posY)
    itemInfo.label = itemInfo:CreateFontString(nil, "OVERLAY")
    G.Font(itemInfo.label, G.ITEM_FONT)
    itemInfo.label:SetPoint("LEFT", itemInfo, "LEFT", 9, 0)
    itemInfo.label:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
    itemInfo.label:SetText(specInfo.label)
    local modes = specInfo.choice
    local function Get()
        local val = G.Cfg()[specInfo.key]
        for idx, modeName in ipairs(modes) do
            if modeName.key == val then
                return idx
            end
        end
        return 1
    end
    local btn = Dropdown(itemInfo, G, modes, Get, function(idx)
        G.Cfg()[specInfo.key] = modes[idx].key
    end, up)
    btn:SetHeight(G.ITEM_H - 2)
    btn:SetPoint("LEFT", itemInfo.label, "RIGHT", 10, 0)
    btn:SetPoint("RIGHT", itemInfo, "RIGHT", -8, 0)
    itemInfo.btn = btn
    function itemInfo:Paint()
        self.btn:ShowMode()
    end
    return itemInfo
end

-------------------------------------------------------------------------------
--  menu icons: role icons and region flags
-------------------------------------------------------------------------------
local ROLE_DIR = "Interface\\AddOns\\CludesUIRaidFrames\\media\\"
-- same art for the results list's open slots
local ROLE_FILE = { TANK = "tank.png", HEALER = "healer.png", DAMAGER = "dps.png" }
function mod.RoleIconTex(role)
    local f = ROLE_FILE[role]
    return f and (ROLE_DIR .. f)
end
local ICONS = {
    role_needsTank = { ROLE_DIR .. "tank.png", 12, 12 },
    role_needsHealer = { ROLE_DIR .. "healer.png", 12, 12 },
    role_needsDamage = { ROLE_DIR .. "dps.png", 12, 12 },
}
-- the region filter's flags, whichever region you're in
for _, d in ipairs(mod.RegionList() or {}) do
    ICONS["region_" .. d.key] = { d.flag, 13, 10 }
end

-- misc in two columns, lined up with the side panel
local function LayoutMisc(dropMenu, sideName)
    local roleG, miscG, sg = dropMenu.extraClassGrp, dropMenu.extraMiscGrp, dropMenu.extraSpecGrp
    if not (roleG and miscG and sg and dropMenu.extraRolesEnd) then
        return
    end
    local posY = dropMenu.extraRolesEnd
    PlaceBlock(sg, dropMenu, posY)
    posY = posY + sg:GetHeight()
    local miscY, rowsY = sideName and sideName.extraMiscY, sideName and sideName.extraMiscRowsY
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
    local K = dropMenu.extraK
    if K then
        local rowFrame = CreateFrame("Frame", nil, dropMenu)
        rowFrame:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 0, -posY)
        rowFrame:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", 0, -posY)
        rowFrame:SetHeight(K.ITEM_H)
        ChoiceItem(
            rowFrame,
            0,
            { key = "extraSortBy", label = CludesUI.L("Sort By"), choice = mod.SORT_MODES },
            K,
            true
        )
        posY = posY + K.ITEM_H
    end
    local hgt = math.max(sideName and sideName.extraEndY and (sideName.extraEndY + 3) or 0, posY + 3)
    dropMenu:SetHeight(hgt)
    if sideName then
        sideName:SetHeight(hgt)
    end
end

GFNS.ExtraDecorateMenu = function(dropMenu, sideName)
    if dropMenu then
        LayoutMisc(dropMenu, sideName)
    end
    for _, ownerFrame in ipairs({ dropMenu, sideName }) do
        local itemList = ownerFrame and ownerFrame.items
        if itemList then
            for key, art in pairs(ICONS) do
                local itemInfo = itemList[key]
                if itemInfo and itemInfo.label and not itemInfo.extraIcon then
                    local _, cb = itemInfo.label:GetPoint(1)
                    if cb then
                        local texture = itemInfo:CreateTexture(nil, "OVERLAY")
                        texture:SetTexture(art[1])
                        texture:SetSize(art[2], art[3])
                        texture:SetPoint("LEFT", cb, "RIGHT", 6, 0)
                        itemInfo.label:ClearAllPoints()
                        itemInfo.label:SetPoint("LEFT", texture, "RIGHT", 5, 0)
                        itemInfo.label:SetPoint("RIGHT", itemInfo, "RIGHT", -4, 0)
                        itemInfo.extraIcon = texture
                    end
                end
            end
        end
    end
end

GFNS.ExtraRaidTex = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\cui-raid.png"
