if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_LootFeed.lua  (WoW Forever only)
--  A stack of short-lived rows for what the player gains: looted items, money,
--  reputation, currencies and skill ups. Each row fades out after a while; a
--  repeat gain of the same thing adds to its row instead of opening another.
--  The Gold per Hour Tracker pins one row that adds up the session's loot.
--  Chat lines are matched against the client's own localized format strings,
--  so this works in every client language.
-------------------------------------------------------------------------------
local _, module = ...
-- The options page pool's table (made by the core, filled in place when the
-- options addon loads): the settings preview reads a dress generation from
-- it at call time.
local POOL = CludesUI._Pool

local FADE_IN = 0.35
local FADE_OUT = 0.8
local SLIDE = 24 -- px a new row glides in from the left
local CALLOUT_GAP = 6 -- Icon Tray: space between the name row and the tiles
local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local REP_ICON = "Interface\\Icons\\INV_Misc_Note_02"
local SKILL_ICON = "Interface\\Icons\\INV_Misc_Book_08"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local RATE_FLOOR = 60 -- seconds: the shortest session the hourly rate divides by
local RATE_TICK = 60 -- seconds between repaints of the hourly rate

-- Settings live in CludesUIDB.lootFeed; unset keys read these.
local DEFAULTS = {
    enabled = false,
    items = true,
    money = true,
    reputation = true,
    currency = true,
    skills = true,
    rolls = false,
    minQuality = 0,
    showIlvl = true,
    showPrice = true,
    tracker = false,
    auctionPrices = false,
    -- BOX: bordered rows, BAR: accent bar on a fading background, TRAY: icon
    -- tiles with a name row, TOAST: framed plates.
    style = "BAR",
    width = 300,
    rowHeight = 36,
    spacing = 2,
    maxRows = 6,
    duration = 5,
    grow = "UP",
    textSize = 13,
    barWidth = 3,
    bgTexture = "none",
    bgR = 0.05,
    bgG = 0.05,
    bgB = 0.05,
    bgA = 0.3,
    borderSize = 1,
    borderR = 0,
    borderG = 0,
    borderB = 0,
    qualityBorder = true,
    -- An unset borderTexture keeps the original pixel borders.
    borderBehind = false,
    separator = false,
}
local F = module.Feature(
    "lootFeed",
    DEFAULTS,
    { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -320, y = 260 }
)
local Get, Cfg, Enabled = F.Get, F.Cfg, F.Enabled

local anchor, events
local isActive = {} -- shown rows, newest first
local pool = {}
-- A row set: the frame its rows are laid out in, its rows (newest first) and
-- the Icon Tray name row. The live feed and the options preview are one each.
local feed = { rows = isActive }

-- v when it is a readable value of type kind (never a secret one).
local function Plain(val, kind)
    if not issecretvalue(val) and type(val) == kind then
        return val
    end
end

-------------------------------------------------------------------------------
--  Chat line matching
-------------------------------------------------------------------------------
-- A Blizzard format string as a Lua pattern with one capture per %s / %d.
-- swap marks a format that puts its second argument first (%2$d before %1$s);
-- the formats read here have at most two.
local function Compile(fmt, anchored)
    local parts, index, first = {}, 1, nil
    while true do
        local s, e, place, kind = fmt:find("%%(%d?)%$?([sd])", index)
        parts[#parts + 1] = (fmt:sub(index, s and s - 1):gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"))
        if not s then
            break
        end
        first = first or tonumber(place)
        parts[#parts + 1] = kind == "d" and "(%d+)" or "(.-)"
        index = e + 1
    end
    local p = table.concat(parts)
    return { pat = anchored and "^" .. p .. "$" or p, swap = first == 2 }
end

-- The captures of text against the global format string key, in argument
-- order: the whole line, or anywhere in it when loose. Compiled once per key;
-- a key the client lacks never matches.
local compiled = {}
local function Match(key, textValue, loose)
    local c = compiled[key]
    if c == nil then
        local fmt = _G[key]
        c = type(fmt) == "string" and fmt ~= "" and Compile(fmt, not loose) or false
        compiled[key] = c
    end
    if not c then
        return
    end
    local a, b = textValue:match(c.pat)
    if c.swap then
        return b, a
    end
    return a, b
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local function StyleFont(fontStr, size)
    CludesUI.ApplyModuleFont(fontStr, nil, size, "essentials")
end

-- Toast plates draw a frame 1 px outside the row, so they need more space.
local function Gap()
    return Get("spacing") + (Get("style") == "TOAST" and 2 or 0)
end

-- Space the pinned tracker row takes at the anchor end of the feed.
local function Pin()
    if not Get("tracker") then
        return 0
    end
    return Get("rowHeight") + (Get("style") == "TRAY" and CALLOUT_GAP or Gap())
end

-- Icon Tray: tiles per line and lines needed for n tiles.
local function TrayGrid(num)
    local gap = Get("spacing")
    local step = Get("rowHeight") + gap
    local cols = math.max(1, math.floor((Get("width") + gap) / step))
    return cols, math.ceil(num / cols)
end

-- Height of a set with n rows (Max Rows when nil) plus the tracker row.
local function AnchorHeight(num)
    local hgt = Get("rowHeight")
    local pin = Pin()
    num = num or Get("maxRows")
    if Get("style") == "TRAY" then
        local _, lines = TrayGrid(num)
        local gap = Get("spacing")
        return pin + hgt + CALLOUT_GAP + lines * (hgt + gap) - gap
    end
    local gap = Gap()
    return pin + num * (hgt + gap) - gap
end

local function Accent()
    local color = CludesUI.CLUDES_GREEN
    if color then
        return color.r, color.g, color.b
    end
    return 0.30, 0.79, 0.94
end

-- Gradient end colours, refilled for each paint (SetGradient copies them).
local gradFrom, gradTo = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0)

local backgroundTextures
local function SetBackgroundTexture(texture)
    local key = Get("bgTexture")
    if key == "none" then
        texture:SetColorTexture(1, 1, 1, 1)
        return
    end
    if not backgroundTextures then
        backgroundTextures = CludesUI.BuildBarTextureTables()
    end
    texture:SetTexture(CludesUI.ResolveTexturePath(backgroundTextures, key, "Interface\\Buttons\\WHITE8x8"))
    texture:SetVertexColor(1, 1, 1, 1)
end

-- Solid, or a two-colour fade to transparent (BAR).
local function PaintBackground(texture, fade)
    local red, green, blue, a = Get("bgR"), Get("bgG"), Get("bgB"), Get("bgA")
    SetBackgroundTexture(texture)
    gradFrom:SetRGBA(red, green, blue, a)
    gradTo:SetRGBA(red, green, blue, fade and 0 or a)
    texture:SetGradient("HORIZONTAL", gradFrom, gradTo)
end

-- Item rows take their quality colour when quality colouring is on;
-- everything else the accent (BAR, the Icon Tray name row) or the border colour.
local function RowColor(skinData, accent)
    if skinData.border and Get("qualityBorder") then
        return skinData.border.r, skinData.border.g, skinData.border.b
    end
    if accent then
        return Accent()
    end
    return Get("borderR"), Get("borderG"), Get("borderB")
end

local TOAST_GOLD = { 0.69, 0.54, 0.23 }
local TOAST_EDGE = { 0.35, 0.27, 0.14 } -- icon frame of rows without a quality
local TOAST_TOP = { 0.19, 0.14, 0.09 }
local TOAST_BOTTOM = { 0.055, 0.04, 0.024 }

-- TOAST: a black 1 px frame around the gold one, with a gold stud at each
-- end. Made the first time a row is drawn as a toast.
local function ToastChrome(region)
    if region.outer then
        return region.outer
    end
    local o = CreateFrame("Frame", nil, region)
    o:SetPoint("TOPLEFT", -1, 1)
    o:SetPoint("BOTTOMRIGHT", 1, -1)
    CludesUI.PP.CreateBorder(o, 0, 0, 0, 1, 1, "OVERLAY", 1)
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local edge = o:CreateTexture(nil, "OVERLAY", nil, 3)
        edge:SetColorTexture(0, 0, 0, 1)
        edge:SetSize(8, 8)
        edge:SetRotation(math.rad(45))
        edge:SetPoint("CENTER", o, side)
        local stud = o:CreateTexture(nil, "OVERLAY", nil, 4)
        stud:SetColorTexture(0.85, 0.70, 0.34, 1)
        stud:SetSize(6, 6)
        stud:SetRotation(math.rad(45))
        stud:SetPoint("CENTER", edge)
    end
    region.outer = o
    return o
end

-- The tracker row is never a tile: the Icon Tray draws it as an accent bar.
local function RowStyle(region)
    local style = Get("style")
    return region.pinned and style == "TRAY" and "BAR" or style
end

local function LayoutSeparator(sep)
    CludesUI.PlaceBorderDividerV(
        sep.tex,
        sep,
        sep.right,
        true,
        sep.key,
        sep.size,
        sep.px,
        sep:GetEffectiveScale()
    )
end

local function StyleSeparator(region, style, size, texture, px)
    local sep = region.separator
    local callout = style == "CALLOUT"
    if
        (style ~= "BOX" and not callout)
        or not Get("separator")
        or size <= 0
        or (callout and Get("barWidth") <= 0)
        or not CludesUI.GetBorderCompanion(texture, "sepV")
    then
        if sep then
            sep:Hide()
            CludesUI.RegisterPxReapply(sep, nil)
        end
        return
    end
    if not sep then
        sep = CreateFrame("Frame", nil, region)
        sep.tex = sep:CreateTexture(nil, "OVERLAY")
        region.separator = sep
    end
    sep:ClearAllPoints()
    sep:SetAllPoints(callout and region.bar or region.icon)
    sep:SetFrameLevel(region:GetFrameLevel() + 3)
    sep.key, sep.size, sep.px, sep.right = texture, size, px, callout
    sep.tex:SetVertexColor(RowColor(region.data, false))
    LayoutSeparator(sep)
    sep:Show()
    CludesUI.RegisterPxReapply(sep, px and LayoutSeparator or nil)
end

local function StyleBorder(region, style)
    local Pix = CludesUI.PP
    local size, texture, owner = Get("borderSize"), Get("borderTexture"), region.lootBorder
    local px = texture and CludesUI.BorderPx(Get("borderSizePx"), size, texture)
    -- The white Pixels artwork takes the item's quality colour without a baked-in tint.
    if texture == "pixels-textured" and region.data.border and Get("qualityBorder") then
        texture = "pixels"
    end
    if Get("separator") or region.separator then
        StyleSeparator(region, style, size, texture, px)
    end
    if size <= 0 or ((style == "BAR" or style == "CALLOUT") and not texture) then
        Pix.HideBorder(region)
        if owner then
            CludesUI.HideBorderStyle(owner)
            owner:Hide()
        end
        return
    end
    local br, backdrop, bb
    if style == "TOAST" then
        br, backdrop, bb = TOAST_GOLD[1], TOAST_GOLD[2], TOAST_GOLD[3]
    else
        br, backdrop, bb = RowColor(region.data, false)
    end
    if not texture or style == "TOAST" then
        if owner then
            CludesUI.HideBorderStyle(owner)
            owner:Hide()
        end
        Pix.UpdateBorder(region, size, br, backdrop, bb, 1)
        Pix.ShowBorder(region)
        return
    end
    Pix.HideBorder(region)
    if not owner then
        owner = CreateFrame("Frame", nil, region)
        region.lootBorder = owner
    end
    owner:ClearAllPoints()
    owner:SetAllPoints(style == "BAR" and region.icon or region)
    owner:SetFrameLevel(Get("borderBehind") and math.max(0, region:GetFrameLevel() - 1) or region:GetFrameLevel() + 1)
    CludesUI.ApplyBorderStyle(
        owner,
        size,
        br,
        backdrop,
        bb,
        1,
        texture,
        Get("borderTextureOffset"),
        Get("borderTextureOffsetY"),
        Get("borderTextureShiftX"),
        Get("borderTextureShiftY"),
        nil,
        nil,
        nil,
        px
    )
end

local function StyleRow(region)
    local hgt, size, style = Get("rowHeight"), Get("textSize"), RowStyle(region)
    local tray, barFrame, toast = style == "TRAY", style == "BAR", style == "TOAST"
    region:SetSize(tray and hgt or Get("width"), hgt)
    region.icon:ClearAllPoints()
    if barFrame then
        local bw = Get("barWidth")
        region.bar:SetWidth(math.max(bw, 1))
        region.bar:SetShown(bw > 0)
        region.icon:SetSize(hgt - 8, hgt - 8)
        region.icon:SetPoint("LEFT", bw > 0 and bw + 5 or 4, 0)
    elseif toast then
        region.bar:Hide()
        region.icon:SetSize(hgt - 10, hgt - 10)
        region.icon:SetPoint("LEFT", 6, 0)
    else
        region.bar:Hide()
        region.icon:SetSize(hgt, hgt)
        region.icon:SetPoint("LEFT")
    end
    -- Legacy BAR icon: 1 px black; TOAST: 2 px quality colour (set by Fill).
    local edge = toast and 2 or 1
    region.iconBg:ClearAllPoints()
    region.iconBg:SetPoint("TOPLEFT", region.icon, "TOPLEFT", -edge, edge)
    region.iconBg:SetPoint("BOTTOMRIGHT", region.icon, "BOTTOMRIGHT", edge, -edge)
    if barFrame then
        region.iconBg:SetColorTexture(0, 0, 0, 1)
    end
    region.iconBg:SetShown((barFrame and not Get("borderTexture")) or toast)
    if toast then
        ToastChrome(region):SetShown(Get("borderSize") > 0)
        local a = Get("bgA")
        SetBackgroundTexture(region.bg)
        gradFrom:SetRGBA(TOAST_BOTTOM[1], TOAST_BOTTOM[2], TOAST_BOTTOM[3], a)
        gradTo:SetRGBA(TOAST_TOP[1], TOAST_TOP[2], TOAST_TOP[3], a)
        region.bg:SetGradient("VERTICAL", gradFrom, gradTo)
    else
        if region.outer then
            region.outer:Hide()
        end
        if not tray then
            PaintBackground(region.bg, barFrame)
        end
    end
    region.bg:SetShown(not tray)
    region.name:SetShown(not tray)
    region.value:SetShown(not tray)
    region.badge:SetShown(tray)
    -- Second line: game gold on toasts, a quiet grey on bars.
    if toast then
        region.sub:SetTextColor(1, 0.82, 0)
    elseif barFrame then
        region.sub:SetTextColor(0.7, 0.7, 0.7)
    else
        region.sub:SetTextColor(1, 1, 1)
    end
    StyleFont(region.name, size)
    StyleFont(region.value, size)
    StyleFont(region.sub, size - 2)
    StyleFont(region.badge, size - 1)
    region.fade.alpha:SetStartDelay(Get("duration"))
end

local function Text(region)
    local fontStr = region:CreateFontString(nil, "OVERLAY")
    fontStr:SetJustifyH("LEFT")
    fontStr:SetWordWrap(false)
    return fontStr
end

-- Icon Tray: the newest gain's name row above the tiles (on top with grow
-- Down). It is a child of that gain's tile, so it fades with it.
local function ShowCallout(set)
    local c = set.callout
    if not c then
        c = CreateFrame("Frame", nil, set.frame)
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetAllPoints()
        c.bar = c:CreateTexture(nil, "ARTWORK")
        c.bar:SetPoint("TOPRIGHT")
        c.bar:SetPoint("BOTTOMRIGHT")
        c.name, c.sub, c.value = Text(c), Text(c), Text(c)
        c.value:SetJustifyH("RIGHT")
        set.callout = c
    end
    local region = set.rows[1]
    local skinData = region.data
    local hgt, bw, size = Get("rowHeight"), Get("barWidth"), Get("textSize")
    local pin = Pin()
    c:SetParent(region)
    c:SetSize(Get("width"), hgt)
    c:ClearAllPoints()
    if Get("grow") == "UP" then
        local _, lines = TrayGrid(#set.rows)
        local gap = Get("spacing")
        c:SetPoint("BOTTOMRIGHT", set.frame, "BOTTOMRIGHT", 0, pin + lines * (hgt + gap) - gap + CALLOUT_GAP)
    else
        c:SetPoint("TOPRIGHT", set.frame, "TOPRIGHT", 0, -pin)
    end
    PaintBackground(c.bg, false)
    c.bar:SetWidth(math.max(bw, 1))
    c.bar:SetShown(bw > 0)
    c.bar:SetColorTexture(RowColor(skinData, true))
    if Get("borderTexture") or c.lootBorder then
        c.data = skinData
        StyleBorder(c, "CALLOUT")
    end
    StyleFont(c.name, size)
    StyleFont(c.value, size)
    StyleFont(c.sub, size - 2)
    c.name:SetText(skinData.text)
    c.value:SetText(skinData.value or "")
    c.sub:SetText(skinData.sub or "")
    c.sub:SetShown(skinData.sub ~= nil)
    c.name:ClearAllPoints()
    c.sub:ClearAllPoints()
    c.value:ClearAllPoints()
    local right = -(bw + 8)
    if skinData.sub then
        -- Name across the top, progress and value below it.
        c.name:SetPoint("BOTTOMLEFT", c, "LEFT", 8, 1)
        c.name:SetPoint("RIGHT", c, "RIGHT", right, 0)
        c.value:SetPoint("TOPRIGHT", c, "RIGHT", right, -1)
        c.sub:SetPoint("TOPLEFT", c, "LEFT", 8, -1)
        c.sub:SetPoint("RIGHT", c.value, "LEFT", -8, 0)
    else
        c.value:SetPoint("RIGHT", c, "RIGHT", right, 0)
        c.name:SetPoint("LEFT", c, "LEFT", 8, 0)
        c.name:SetPoint("RIGHT", c.value, "LEFT", -8, 0)
    end
    c:Show()
end

local function Layout(set)
    set = set or feed
    local widget = set.frame
    local up = Get("grow") == "UP"
    local tray = Get("style") == "TRAY"
    local step = Get("rowHeight") + (tray and Get("spacing") or Gap())
    local cols = TrayGrid(1)
    local below = Get("rowHeight") + CALLOUT_GAP -- grow Down: tiles start under the name row
    local pin = Pin() -- the rows start past the tracker row
    for index, region in ipairs(set.rows) do
        region:ClearAllPoints()
        if tray then
            local colour, line = (index - 1) % cols, math.floor((index - 1) / cols)
            if up then
                region:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -colour * step, pin + line * step)
            else
                region:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -colour * step, -(pin + below + line * step))
            end
        elseif up then
            region:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", 0, pin + (index - 1) * step)
        else
            region:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, -(pin + (index - 1) * step))
        end
    end
    if tray and set.rows[1] then
        ShowCallout(set)
    elseif set.callout then
        set.callout:Hide()
    end
end

local function Unlist(region)
    for index = #isActive, 1, -1 do
        if isActive[index] == region then
            table.remove(isActive, index)
        end
    end
end

local function Release(region)
    Unlist(region)
    region.show:Stop()
    region.fade:Stop()
    region:Hide()
    region.key, region.data = nil, nil
    pool[#pool + 1] = region
    Layout()
end

-- Starts the wait-then-fade-out, unless the row is still fading in (its
-- end starts it) or hovered (leaving starts it).
-- Preview rows never fade.
local function ArmFade(region)
    if region.preview or region.show:IsPlaying() then
        return
    end
    region.fade:Stop()
    region:SetAlpha(1)
    if not region:IsMouseOver() then
        region.fade:Play()
    end
end

-- Hover shows the item tooltip and holds the fade. Icon Tray tiles show no
-- text, so for them the tooltip carries it.
local function RowEnter(region)
    if not region.show:IsPlaying() then
        region.fade:Stop()
        region:SetAlpha(1)
    end
    local skinData = region.data
    if not skinData then
        return
    end
    if skinData.link then
        GameTooltip:SetOwner(region, "ANCHOR_LEFT")
        GameTooltip:SetHyperlink(skinData.link)
        GameTooltip:Show()
    elseif Get("style") == "TRAY" then
        local textValue = skinData.text
        if skinData.sub then
            textValue = textValue .. "\n" .. CludesUI.COLOR_CODES.DIM .. skinData.sub .. "|r"
        end
        if skinData.value then
            textValue = textValue .. "\n" .. skinData.value
        end
        region.tip = true
        CludesUI.ShowWidgetTooltip(region, textValue, { anchor = "left" })
    end
end

local function RowLeave(region)
    if GameTooltip:IsOwned(region) then
        GameTooltip:Hide()
    end
    if region.tip then
        region.tip = nil
        CludesUI.HideWidgetTooltip()
    end
    ArmFade(region)
end

local function ShowDone(g)
    ArmFade(g:GetParent())
end
local function FadeDone(g)
    Release(g:GetParent())
end

-- One animation of group g: step order, seconds, easing.
local function Anim(g, kind, sequence, secs, smoothing)
    local a = g:CreateAnimation(kind)
    a:SetOrder(sequence)
    a:SetDuration(secs)
    if smoothing then
        a:SetSmoothing(smoothing)
    end
    return a
end

local function NewRow(hostFrame)
    local region = CreateFrame("Frame", nil, hostFrame or anchor)
    region.bg = region:CreateTexture(nil, "BACKGROUND")
    region.bg:SetAllPoints()
    region.bar = region:CreateTexture(nil, "ARTWORK")
    region.bar:SetPoint("TOPLEFT")
    region.bar:SetPoint("BOTTOMLEFT")
    region.icon = region:CreateTexture(nil, "ARTWORK", nil, 1)
    region.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon frame
    region.iconBg = region:CreateTexture(nil, "ARTWORK")
    region.badge = region:CreateFontString(nil, "OVERLAY")
    region.badge:SetPoint("BOTTOMRIGHT", -2, 2)
    region.name, region.sub, region.value = Text(region), Text(region), Text(region)
    region.value:SetJustifyH("RIGHT")
    region.value:SetPoint("RIGHT", -6, 0)
    region.sub:SetPoint("TOPLEFT", region.icon, "RIGHT", 6, -1)
    region.sub:SetPoint("RIGHT", region.value, "LEFT", -8, 0)
    CludesUI.PP.CreateBorder(region, 0, 0, 0, 1, 1, "OVERLAY", 2)
    -- Hover only: clicks pass through.
    region:EnableMouseMotion(true)
    region:SetScript("OnEnter", RowEnter)
    region:SetScript("OnLeave", RowLeave)
    -- Fade in while gliding in: a zero-length jump left, then the way back.
    region.show = region:CreateAnimationGroup()
    Anim(region.show, "Translation", 1, 0):SetOffset(-SLIDE, 0)
    Anim(region.show, "Translation", 2, FADE_IN, "OUT"):SetOffset(SLIDE, 0)
    local appear = Anim(region.show, "Alpha", 2, FADE_IN, "OUT")
    appear:SetFromAlpha(0)
    appear:SetToAlpha(1)
    region.show:SetScript("OnFinished", ShowDone)
    -- Wait (the start delay, set by StyleRow), fade out, free the row.
    region.fade = region:CreateAnimationGroup()
    region.fade.alpha = Anim(region.fade, "Alpha", 1, FADE_OUT, "IN_OUT")
    region.fade.alpha:SetFromAlpha(1)
    region.fade.alpha:SetToAlpha(0)
    region.fade:SetScript("OnFinished", FadeDone)
    return region
end

-- Fills a row from its data: icon, text (first line), sub (second line,
-- optional), value (right side, optional), badge (Icon Tray tile text),
-- border (quality colour, optional). Box rows keep their one-line form
-- (flat) and show no quest line.
local function Fill(region)
    local skinData, style = region.data, RowStyle(region)
    local textValue, sub, value = skinData.text, skinData.sub or skinData.questSub, skinData.value
    if style == "BOX" then
        sub = not skinData.flat and skinData.sub or nil
        if skinData.flat then
            textValue, value = skinData.flat, nil
        end
    elseif style == "TRAY" then
        sub = nil
    end
    region.icon:SetTexture(skinData.icon)
    region.name:SetText(textValue)
    region.sub:SetText(sub or "")
    region.sub:SetShown(sub ~= nil)
    region.value:SetText(value or "")
    region.badge:SetText(skinData.badge or "")
    region.name:ClearAllPoints()
    region.name:SetPoint("RIGHT", region.value, "LEFT", -8, 0)
    if sub then
        region.name:SetPoint("BOTTOMLEFT", region.icon, "RIGHT", 6, 1)
    else
        region.name:SetPoint("LEFT", region.icon, "RIGHT", 6, 0)
    end
    if style == "BAR" then
        region.bar:SetColorTexture(RowColor(skinData, true))
    end
    if style == "TOAST" then
        if skinData.border and Get("qualityBorder") then
            region.iconBg:SetColorTexture(skinData.border.r, skinData.border.g, skinData.border.b, 1)
        else
            region.iconBg:SetColorTexture(TOAST_EDGE[1], TOAST_EDGE[2], TOAST_EDGE[3], 1)
        end
    end
    StyleBorder(region, style)
end

local function FindRow(key)
    for _, region in ipairs(isActive) do
        if region.key == key then
            return region
        end
    end
end

-- While the options preview collects its samples, the Show functions add
-- their rows to this list (newest first) instead of the feed.
local collect

-- amount plus what the row showing key already adds up to.
local function Total(key, amount)
    if collect then
        return amount
    end
    local region = FindRow(key)
    return amount + (region and region.data.amount or 0)
end

-- Shows data under key: the row already showing key is refilled, moved to the
-- front and its fade restarted; otherwise a row is taken (the oldest one when
-- all maxRows are in use) and fades in.
local function Push(key, payload)
    local region = FindRow(key)
    local fresh = not region
    if region then
        Unlist(region)
    else
        while #isActive >= Get("maxRows") do
            Release(isActive[#isActive])
        end
        region = table.remove(pool) or NewRow()
        StyleRow(region)
    end
    table.insert(isActive, 1, region)
    region.key, region.data = key, payload
    Fill(region)
    Layout()
    if fresh then
        region.fade:Stop()
        region:SetAlpha(0)
        region:Show()
        region.show:Play()
    else
        ArmFade(region)
    end
end

local function Emit(key, payload)
    if collect then
        collect[#collect + 1] = payload
    else
        Push(key, payload)
    end
end

-------------------------------------------------------------------------------
--  Sources
-------------------------------------------------------------------------------
local function Money(copper)
    return C_CurrencyInfo.GetCoinTextureString(copper, Get("textSize"))
end

-- The largest coin only, for an Icon Tray badge.
local function ShortMoney(copper)
    local unitToken = copper >= 10000 and 10000 or copper >= 100 and 100 or 1
    return Money(copper - copper % unitToken)
end

-------------------------------------------------------------------------------
--  Gold per Hour Tracker: looted coin plus the value of looted items, since
--  the first loot of the session (a reload starts a new one). One pinned row
--  shows the hourly rate, the total and the session's length; Ctrl + Click on
--  its Reset Session button clears it.
-------------------------------------------------------------------------------
local session = { coin = 0, items = 0 } -- copper; start: GetTime() of the first loot
local summary, clock

-- 23m, 1h 5m: started minutes, so a session that has begun never reads 0m
local function Duration(seconds)
    local minutes = math.ceil(seconds / 60)
    if minutes < 60 then
        return string.format(CludesUI.L("%dm"), minutes)
    end
    return string.format(CludesUI.L("%dh %dm"), math.floor(minutes / 60), minutes % 60)
end

-- The hourly rate leads; the session's total and length follow, dimmed.
-- elapsed: seconds since the first loot (0 before it).
local function PaintSummary(region, sum, elapsed)
    local skinData = region.data
    skinData.text = CludesUI.Lf("%s / hr", Money(math.floor(sum / math.max(elapsed, RATE_FLOOR) * 3600)))
    skinData.sub = CludesUI.Lf("%s in %s", Money(sum), Duration(elapsed))
    Fill(region)
end

local function FillSummary()
    PaintSummary(summary, session.coin + session.items, session.start and GetTime() - session.start or 0)
end

-- The rate falls while nothing is looted, so the row is repainted once a
-- minute while it is on screen with a running session.
local function SyncClock()
    local run = session.start and summary and summary:IsVisible()
    if run and not clock then
        clock = C_Timer.NewTicker(RATE_TICK, FillSummary)
    elseif not run and clock then
        clock:Cancel()
        clock = nil
    end
end

local function Earn(kind, copper)
    session.start = session.start or GetTime()
    session[kind] = session[kind] + copper
    if summary then
        FillSummary()
    end
    SyncClock()
end

local AuctionPrice = module.AuctionPrice

-- What one of the item counts for: nothing for a quest-bound item, the vendor
-- price for one that binds when picked up (it cannot be auctioned) and for
-- every item with Use Auctionator Prices off.
local function ItemValue(itemLink, sellPrice, bindType)
    if bindType == Enum.ItemBind.Quest then
        return 0
    end
    if bindType == Enum.ItemBind.OnAcquire then
        return sellPrice or 0
    end
    return Get("auctionPrices") and AuctionPrice(itemLink) or sellPrice or 0
end

local RESET_DIM = 0.7

local function ResetEnter(b)
    b.tip = true
    CludesUI.ShowWidgetTooltip(b, CludesUI.L("Ctrl + Click to reset the session"), { anchor = "left" })
end

local function ResetLeave(b)
    if not b.tip then
        return
    end
    b.tip = nil
    CludesUI.HideWidgetTooltip()
end

-- The button takes the mouse only while Ctrl is held (and lights up), so the
-- row never blocks a click or a camera drag. Only a change of Ctrl (not Shift
-- or Alt) repaints it.
local function ResetArm(b)
    local on = IsControlKeyDown()
    if on == b.armed then
        return
    end
    b.armed = on
    local c = on and 1 or RESET_DIM
    b:EnableMouse(on)
    b.text:SetTextColor(c, c, c)
    if not on then
        ResetLeave(b)
    end
end

-- The button shows and hides with the row: Ctrl is watched, and the minute
-- clock runs, only while the row is on screen.
local function ResetShow(b)
    b:RegisterEvent("MODIFIER_STATE_CHANGED")
    ResetArm(b)
    if summary and session.start then
        FillSummary()
    end
    SyncClock()
end

local function ResetHide(b)
    b:UnregisterEvent("MODIFIER_STATE_CHANGED")
    ResetLeave(b)
    SyncClock()
end

local function ResetClick()
    if not IsControlKeyDown() then
        return
    end
    session.coin, session.items, session.start = 0, 0, nil
    FillSummary()
    SyncClock()
end

-- The Reset Session button ends the second line. The row takes no mouse. With
-- a parent it is the options preview's sample, whose button never does either.
local function NewSummary(hostFrame)
    local region = NewRow(hostFrame)
    region.pinned = true
    region.data = { icon = MONEY_ICON }
    local reset = CreateFrame("Button", nil, region)
    reset:SetPoint("TOPRIGHT", region, "RIGHT", -6, -1)
    reset.text = Text(reset)
    reset.text:SetPoint("RIGHT")
    reset.text:SetTextColor(RESET_DIM, RESET_DIM, RESET_DIM)
    region:SetScript("OnEnter", nil)
    region:SetScript("OnLeave", nil)
    region:EnableMouse(false)
    reset:EnableMouse(false)
    if not hostFrame then
        reset:SetScript("OnEnter", ResetEnter)
        reset:SetScript("OnLeave", ResetLeave)
        reset:SetScript("OnClick", ResetClick)
        reset:SetScript("OnEvent", ResetArm)
        reset:SetScript("OnShow", ResetShow)
        reset:SetScript("OnHide", ResetHide)
        ResetShow(reset)
    end
    region.reset = reset
    region.sub:ClearAllPoints()
    region.sub:SetPoint("TOPLEFT", region.icon, "RIGHT", 6, -1)
    region.sub:SetPoint("RIGHT", reset, "LEFT", -8, 0)
    return region
end

-- Styles a tracker row and pins it to the anchor end of its set.
local function PlaceSummary(region)
    StyleRow(region)
    -- One text size: the second line is set apart by its tone alone.
    local reset, size = region.reset, Get("textSize")
    StyleFont(region.sub, size)
    region.sub:SetTextColor(RESET_DIM, RESET_DIM, RESET_DIM)
    StyleFont(reset.text, size)
    reset.text:SetText(CludesUI.L("Reset Session"))
    reset:SetSize(reset.text:GetStringWidth(), reset.text:GetStringHeight())
    region:ClearAllPoints()
    region:SetPoint(Get("grow") == "UP" and "BOTTOMLEFT" or "TOPLEFT")
    region:Show()
end

-- Built the first time the tracker is on.
local function UpdateSummary()
    if not Get("tracker") then
        if summary then
            summary:Hide()
        end
        SyncClock()
        return
    end
    summary = summary or NewSummary()
    PlaceSummary(summary)
    FillSummary()
    SyncClock()
end

-- Group loot by item name: links from the loot history, and the roll behind each of your wins.
local rollLinks, wins = {}, {}

-- looted: a real loot line (not a preview sample). earned: one the tracker
-- counts (looted or won, not bought or a quest reward), even when item rows
-- are off or the item is below Minimum Quality.
local function ShowItem(itemLink, count, retried, looted, earned)
    local name, _, quality, itemLevel, _, _, _, _, _, iconTex, sellPrice, classID, _, bindType =
        C_Item.GetItemInfo(itemLink)
    if not name then
        -- Not cached yet: try again once the client has it. Only once: the
        -- client also calls back when the item fails to load.
        if not retried then
            Item:CreateFromItemLink(itemLink):ContinueOnItemLoad(function()
                ShowItem(itemLink, count, true, looted, earned)
            end)
        end
        return
    end
    local won = looted and wins[name]
    if won then
        wins[name] = nil
    end
    local each -- what one counts for, priced only when the tracker or the row needs it
    if looted then
        if earned and Get("tracker") then
            each = ItemValue(itemLink, sellPrice, bindType)
            Earn("items", each * count)
        end
        if not Get("items") then
            return
        end
    end
    if (quality or 0) < Get("minQuality") then
        return
    end
    local key = "item:" .. itemLink
    count = Total(key, count)
    local color = ITEM_QUALITY_COLORS[quality or 1] or ITEM_QUALITY_COLORS[1]
    local textValue = color.hex .. name .. "|r"
    if count > 1 then
        textValue = count .. "x " .. textValue
    end
    local sub, questSub
    if Get("showIlvl") and (classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor) then
        local ilvl = C_Item.GetDetailedItemLevelInfo(itemLink) or itemLevel
        if ilvl and ilvl > 0 then
            sub = CludesUI.Lf("ilvl: %d", ilvl)
        end
    elseif classID == Enum.ItemClass.Questitem and ITEM_BIND_QUEST then
        questSub = "|cffffd100" .. ITEM_BIND_QUEST .. "|r"
    end
    if won then
        won = CludesUI.Lf("Won: %s", won)
        sub = sub and (won .. "  " .. sub) or won
    end
    -- The row shows the tracker's price; the plain vendor one with Use Auctionator Prices off.
    local value
    if Get("showPrice") then
        local price = Get("auctionPrices") and (each or ItemValue(itemLink, sellPrice, bindType))
            or sellPrice
            or 0
        if price > 0 then
            value = Money(price * count)
        end
    end
    Emit(key, {
        icon = iconTex,
        text = textValue,
        sub = sub,
        questSub = questSub,
        value = value,
        border = color,
        link = itemLink,
        amount = count,
        badge = count > 1 and count or nil,
    })
end

local function ShowMoney(copper)
    copper = Total("money", copper)
    Emit("money", {
        icon = MONEY_ICON,
        text = CludesUI.L("Money"),
        value = Money(copper),
        amount = copper,
        badge = ShortMoney(copper),
    })
end

-- A faction's or skill line's data by name. ids keeps the id a scan of the
-- (expanded) list found, so later lookups go straight to it.
local factionIDs, skillIDs = {}, {}
local function Lookup(ids, name, byID, count, byIndex, idKey)
    local ident = ids[name]
    if ident then
        return byID(ident)
    end
    for index = 1, count() do
        local skinData = byIndex(index)
        if skinData and skinData.name == name then
            ids[name] = skinData[idKey]
            return skinData
        end
    end
end

-- With the progress within the current standing.
local function ShowReputation(faction, delta)
    local key = "rep:" .. faction
    delta = Total(key, delta)
    local change = (delta >= 0 and "|cff00ff00+" or "|cffff4040") .. delta .. "|r"
    local flat = change .. " " .. faction
    local skinData = Lookup(
        factionIDs,
        faction,
        C_Reputation.GetFactionDataByID,
        C_Reputation.GetNumFactions,
        C_Reputation.GetFactionDataByIndex,
        "factionID"
    )
    local progress
    if skinData then
        progress = string.format(
            "%s / %s",
            BreakUpLargeNumbers(skinData.currentStanding - skinData.currentReactionThreshold),
            BreakUpLargeNumbers(skinData.nextReactionThreshold - skinData.currentReactionThreshold)
        )
        flat = flat .. " (" .. progress .. ")"
    end
    Emit(key, {
        icon = REP_ICON,
        text = faction,
        sub = progress,
        value = change,
        flat = flat,
        badge = change,
        amount = delta,
    })
end

-- With the total held, red at the cap.
local function ShowCurrency(ident, change)
    local details = C_CurrencyInfo.GetCurrencyInfo(ident)
    if not (details and details.name) then
        return
    end
    local key = "currency:" .. ident
    change = Total(key, change)
    local sum = BreakUpLargeNumbers(details.quantity)
    if details.maxQuantity > 0 then
        sum = sum .. " / " .. BreakUpLargeNumbers(details.maxQuantity)
        if details.quantity >= details.maxQuantity then
            sum = "|cffff4040" .. sum .. "|r"
        end
    end
    local textValue = change .. "x " .. details.name
    Emit(key, {
        icon = details.iconFileID,
        text = textValue,
        sub = sum,
        flat = textValue .. " (" .. sum .. ")",
        badge = change,
        amount = change,
    })
end

local function ShowSkill(skill, rank)
    local skinData = Lookup(
        skillIDs,
        skill,
        C_SkillInfo.GetSkillLineInfoByID,
        C_SkillInfo.GetNumSkillLines,
        C_SkillInfo.GetSkillLineInfo,
        "skillID"
    )
    local max = skinData and skinData.maxRank > 0 and (" / " .. skinData.maxRank) or ""
    Emit("skill:" .. skill, {
        icon = SKILL_ICON,
        text = skill,
        value = rank .. max,
        badge = rank,
        flat = skill .. " " .. CludesUI.COLOR_CODES.WHITE .. rank .. max .. "|r",
    })
end

-- Own loot only: the *_SELF lines, the multiple-item formats (link and count)
-- first, since the single-item ones match their lines too. The flag: the
-- tracker counts it (a pushed item, bought or a quest reward, and a crafted one
-- show but are no gain).
local ITEM_KEYS = {
    { "LOOT_ITEM_SELF_MULTIPLE", true },
    { "LOOT_ITEM_SELF", true },
    { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", false },
    { "LOOT_ITEM_PUSHED_SELF", false },
    { "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", true },
    { "LOOT_ITEM_BONUS_ROLL_SELF", true },
    { "LOOT_ITEM_CREATED_SELF_MULTIPLE", false },
    { "LOOT_ITEM_CREATED_SELF", false },
}

-- Forever sends some loot lines, like fishing and crafting, with a plain [Name] instead of a link.
local function ItemString(textValue)
    if textValue:find("|Hitem:", 1, true) then
        return textValue
    end
    local name = textValue:match("^%[(.-)%]$")
    if not name then
        return
    end
    if rollLinks[name] then
        return rollLinks[name]
    end
    local ident = C_Item.GetItemInfoInstant(name)
    return ident and "item:" .. ident
end

local function OnLoot(textValue)
    for _, k in ipairs(ITEM_KEYS) do
        local entry, count = Match(k[1], textValue)
        if entry then
            local itemLink = ItemString(entry)
            if itemLink then
                ShowItem(itemLink, tonumber(count) or 1, nil, true, k[2])
            end
            return
        end
    end
end

-- The game's own words for each Enum.EncounterLootDropRollState, English when it lacks one.
local ROLL_LABELS = {
    NeedMainSpec = { "NEED", "Need" },
    NeedOffSpec = { "NEED", "Need" },
    Transmog = { "TRANSMOGRIFY", "Transmog" },
    Greed = { "GREED", "Greed" },
}

local function RollText(details)
    local roll = details and Plain(details.roll, "number")
    if not roll then
        return
    end
    local status = Plain(details.state, "number")
    for key, value in pairs(Enum.EncounterLootDropRollState or {}) do
        local labelText = value == status and ROLL_LABELS[key]
        if labelText then
            return (_G[labelText[1]] or labelText[2]) .. " " .. roll
        end
    end
    return tostring(roll)
end

-- A nil winner means everyone passed.
local function ShowRoll(key, itemLink, itemName, winner, class, roll, retried)
    local name, quality, iconTex, _
    if itemLink then
        name, _, quality, _, _, _, _, _, _, iconTex = C_Item.GetItemInfo(itemLink)
        if not name and not retried then
            Item:CreateFromItemLink(itemLink):ContinueOnItemLoad(function()
                ShowRoll(key, itemLink, itemName, winner, class, roll, true)
            end)
            return
        end
    end
    local color = ITEM_QUALITY_COLORS[quality or 1] or ITEM_QUALITY_COLORS[1]
    local entry = color.hex .. (name or itemName or "?") .. "|r"
    local textValue
    if winner then
        -- The suite's class colour (custom class colours included); an unknown class stays uncoloured.
        local cc = class and RAID_CLASS_COLORS[class] and CludesUI.GetClassColor(class)
        if cc then
            winner = CludesUI.HexColor(cc.r, cc.g, cc.b) .. winner .. "|r"
        end
        textValue = CludesUI.Lf("%s won %s", winner, entry)
    else
        textValue = CludesUI.Lf("Everyone passed on %s", entry)
    end
    Emit(key, {
        icon = iconTex or UNKNOWN_ICON,
        text = textValue,
        sub = roll,
        border = color,
        link = itemLink,
        flat = roll and (textValue .. " (" .. roll .. ")") or textValue,
        badge = roll and roll:match("%d+"),
    })
end

-- The history updates a drop on every pick; it is shown once, when it has a winner or everyone passed.
local shownDrops = {}
local function OnDrop(encounterID, lootListID)
    local key = "roll:" .. encounterID .. ":" .. lootListID
    if shownDrops[key] then
        return
    end
    local drop = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID)
    local winner = drop and drop.winner
    if not (winner or (drop and drop.allPassed == true)) then
        return
    end
    shownDrops[key] = true
    local raw = Plain(drop.itemHyperlink, "string")
    local name = raw and raw:match("%[(.-)%]")
    local itemLink = raw and raw:find("|Hitem:", 1, true) and raw or nil
    if itemLink and name then
        rollLinks[name] = itemLink
    end
    local roll = RollText(winner)
    if winner and winner.isSelf == true then
        if name and roll then
            wins[name] = roll
        end
        return
    end
    ShowRoll(
        key,
        itemLink,
        name,
        winner and Plain(winner.playerName, "string"),
        winner and Plain(winner.playerClass, "string"),
        roll
    )
end

-- Money lines spell out each coin with the client's own "%d Gold" etc.
local COIN_KEYS = { GOLD_AMOUNT = 10000, SILVER_AMOUNT = 100, COPPER_AMOUNT = 1 }
local function OnMoney(textValue)
    local copper = 0
    for key, mult in pairs(COIN_KEYS) do
        local num = Match(key, textValue, true)
        if num then
            copper = copper + tonumber(num) * mult
        end
    end
    if copper <= 0 then
        return
    end
    if Get("tracker") then
        Earn("coin", copper)
    end
    if Get("money") then
        ShowMoney(copper)
    end
end

local function OnFaction(textValue)
    local faction, amount = Match("FACTION_STANDING_INCREASED", textValue)
    if faction then
        return ShowReputation(faction, tonumber(amount))
    end
    faction, amount = Match("FACTION_STANDING_DECREASED", textValue)
    if faction then
        return ShowReputation(faction, -tonumber(amount))
    end
end

local function OnSkill(textValue)
    local skill, rank = Match("SKILL_RANK_UP", textValue)
    if skill then
        ShowSkill(skill, tonumber(rank))
    end
end

-- tracked: the tracker counts these, so it listens while their rows are off.
local CHAT_EVENTS = {
    CHAT_MSG_LOOT = { setting = "items", handler = OnLoot, tracked = true },
    CHAT_MSG_MONEY = { setting = "money", handler = OnMoney, tracked = true },
    CHAT_MSG_COMBAT_FACTION_CHANGE = { setting = "reputation", handler = OnFaction },
    CHAT_MSG_SKILL = { setting = "skills", handler = OnSkill },
}

local function OnEvent(_, evt, ...)
    local chat = CHAT_EVENTS[evt]
    if chat then
        local textValue = Plain((...), "string")
        if textValue then
            chat.handler(textValue)
        end
    elseif evt == "CURRENCY_DISPLAY_UPDATE" then
        local ident, _, change = ...
        ident, change = Plain(ident, "number"), Plain(change, "number")
        if ident and change and change > 0 then
            ShowCurrency(ident, change)
        end
    elseif evt == "LOOT_HISTORY_UPDATE_DROP" then
        local encounterID, lootListID = ...
        encounterID, lootListID = Plain(encounterID, "number"), Plain(lootListID, "number")
        if encounterID and lootListID then
            OnDrop(encounterID, lootListID)
        end
    end
end

-------------------------------------------------------------------------------
--  Setup
-------------------------------------------------------------------------------
local RefreshPreview

local function ApplyStyle()
    RefreshPreview()
    if not anchor then
        return
    end
    anchor:SetSize(Get("width"), AnchorHeight())
    -- Pooled rows are styled when Push takes them.
    for _, region in ipairs(isActive) do
        StyleRow(region)
        Fill(region)
    end
    while #isActive > Get("maxRows") do
        Release(isActive[#isActive])
    end
    UpdateSummary()
    Layout()
end

local function CreateAnchor()
    if anchor then
        return
    end
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetFrameStrata("MEDIUM")
    feed.frame = anchor
    ApplyStyle()
    F.Place(anchor)
end

local function ClearRows()
    while isActive[1] do
        Release(isActive[1])
    end
end

local function Apply()
    if events then
        events:UnregisterAllEvents()
    end
    if not Enabled() then
        ClearRows()
        if summary then
            summary:Hide()
        end
        SyncClock()
        return
    end
    CreateAnchor()
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    for evt, chat in pairs(CHAT_EVENTS) do
        if Get(chat.setting) or (chat.tracked and Get("tracker")) then
            events:RegisterEvent(evt)
        end
    end
    if Get("currency") then
        events:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    end
    if Get("rolls") and C_LootHistory then
        events:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
    end
end

-- A sample of every enabled source: the player's capital for reputation and
-- classic items of three qualities (item id / count pairs). The rows fade like
-- real ones.
local PREVIEW_ITEMS = { 19019, 1, 4306, 5, 14047, 12 }
local function PreviewRoll()
    local _, itemLink = C_Item.GetItemInfo(PREVIEW_ITEMS[1])
    if itemLink then
        ShowRoll("roll:preview", itemLink, nil, "Thrall", "SHAMAN", (GREED or "Greed") .. " 87")
    end
end

local function Preview()
    if not Enabled() then
        return
    end
    CreateAnchor()
    ClearRows()
    if Get("skills") then
        ShowSkill(CludesUI.L("Swords"), 42)
    end
    if Get("reputation") then
        local capital = C_Reputation.GetFactionDataByID(UnitFactionGroup("player") == "Horde" and 76 or 72)
        if capital then
            ShowReputation(capital.name, 250)
        end
    end
    if Get("money") then
        ShowMoney(12345)
    end
    if Get("items") then
        for index = 1, #PREVIEW_ITEMS, 2 do
            ShowItem("item:" .. PREVIEW_ITEMS[index], PREVIEW_ITEMS[index + 1])
        end
    end
    if Get("rolls") then
        PreviewRoll()
    end
end

-------------------------------------------------------------------------------
--  Options preview: the same rows with a sample of every enabled source,
--  drawn in the options content header. Built when the Loot page first
--  opens; it never fades and listens to no events.
-------------------------------------------------------------------------------
local preview -- row set plus its view and every row frame made so far

local SAMPLE_TOTAL, SAMPLE_TIME = 61400, 1200 -- the sample tracker row: copper, seconds

local requested = {} -- preview items asked of the client, once each

-- The Preview samples, newest first, as data. An item the client has not
-- cached yet is asked for once a session and redraws the preview when its
-- load ends; the client also calls back when the load fails, so asking again
-- from the redraw would never stop.
local function PreviewSamples()
    local entries, itemList = {}, Get("items")
    collect = entries
    if Get("rolls") then
        PreviewRoll()
    end
    if itemList then
        for index = 1, #PREVIEW_ITEMS, 2 do
            local itemLink = "item:" .. PREVIEW_ITEMS[index]
            if C_Item.GetItemInfo(itemLink) then
                ShowItem(itemLink, PREVIEW_ITEMS[index + 1])
            end
        end
    end
    if Get("money") then
        ShowMoney(12345)
    end
    if Get("reputation") then
        local capital = C_Reputation.GetFactionDataByID(UnitFactionGroup("player") == "Horde" and 76 or 72)
        if capital then
            ShowReputation(capital.name, 250)
        end
    end
    if Get("skills") then
        ShowSkill(CludesUI.L("Swords"), 42)
    end
    collect = nil
    -- Asked for once the samples are in: the callback can run right away.
    if itemList or Get("rolls") then
        for index = 1, #PREVIEW_ITEMS, 2 do
            local ident = PREVIEW_ITEMS[index]
            if not requested[ident] and not C_Item.GetItemInfo(ident) then
                requested[ident] = true
                Item:CreateFromItemID(ident):ContinueOnItemLoad(function()
                    RefreshPreview()
                end)
            end
        end
    end
    return entries
end

-- force: draw while the header is still being built (not shown yet).
RefreshPreview = function(force)
    local val = preview
    if not (val and (force or val.view:IsVisible())) then
        return
    end
    local samples = PreviewSamples()
    local num = math.min(#samples, Get("maxRows"))
    for index = 1, num do
        local region = val.all[index]
        if not region then
            region = NewRow(val.frame)
            region.preview = true
            val.all[index] = region
        end
        region.data = samples[index]
        StyleRow(region)
        Fill(region)
        region:SetAlpha(1)
        region:Show()
        val.rows[index] = region
    end
    for index = num + 1, #val.all do
        val.all[index]:Hide()
        val.rows[index] = nil
    end
    if Get("tracker") then
        val.summary = val.summary or NewSummary(val.frame)
        PlaceSummary(val.summary)
        PaintSummary(val.summary, SAMPLE_TOTAL, SAMPLE_TIME)
    elseif val.summary then
        val.summary:Hide()
    end
    local wid = Get("width")
    local hgt = num > 0 and AnchorHeight(num) or Get("rowHeight")
    local pw = val.view:GetParent():GetWidth()
    local available = (pw > 0 and pw) or val.availableWidth or wid + 40
    local scale = math.min(1, math.max(100, available - 40) / wid)
    val.frame:SetSize(wid, hgt)
    val.frame:SetScale(scale)
    Layout(val)
    val.previewHeight = hgt * scale + 30
    val.view:SetHeight(val.previewHeight)
    if val.onHeightChanged then
        val.onHeightChanged(val.previewHeight)
    end
end

-- parent -> the dress its size hook was made for: the options page pool
-- (CludesUI_FramePool.lua) resets a kept header root before each build,
-- which drops the hook, so a new dress (Pool.Gen) hooks again; a plain frame
-- (no Gen) is hooked once.
local hookedParents = {}
local function CreateSettingsPreview(hostFrame, availableWidth, onHeightChanged)
    local val = preview
    if not val then
        val = { rows = {}, all = {} }
        val.view = CreateFrame("Frame", nil, hostFrame)
        val.frame = CreateFrame("Frame", nil, val.view)
        val.frame:SetPoint("CENTER")
        val.view:SetScript("OnShow", function()
            RefreshPreview()
        end)
        preview = val
    end
    -- Frames outlive a page rebuild, so the view is reused.
    val.availableWidth, val.onHeightChanged = availableWidth, onHeightChanged
    val.view:SetParent(hostFrame)
    val.view:ClearAllPoints()
    val.view:SetPoint("TOPLEFT")
    val.view:SetPoint("TOPRIGHT")
    local dress = POOL.Gen and POOL.Gen(hostFrame) or true
    if hookedParents[hostFrame] ~= dress then
        hookedParents[hostFrame] = dress
        local lastWidth
        hostFrame:HookScript("OnSizeChanged", function(_, width)
            if width == lastWidth then
                return
            end
            lastWidth = width
            if val.view:GetParent() == hostFrame then
                RefreshPreview()
            end
        end)
    end
    val.view:Show()
    RefreshPreview(true)
    return val
end

-- Options-page entry points.
CludesUI._LootFeed = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    ApplyStyle = ApplyStyle,
    ApplyPosition = function()
        F.Place(anchor)
    end,
    Preview = Preview,
    CreateSettingsPreview = CreateSettingsPreview,
    RefreshPreview = function()
        RefreshPreview()
    end,
}

F.Start(Apply, {
    key = "CUI_LootFeed",
    label = "Loot Feed",
    order = 732,
    minWidth = 150,
    frame = function(build)
        if build then
            CreateAnchor()
        end
        return anchor
    end,
    -- Follows Max Rows and Row Height.
    height = AnchorHeight,
    applyStyle = ApplyStyle,
})
