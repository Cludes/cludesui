-- The Keys and Guild views: tables drawn in the plot's place, with the same
-- surfaces, ink and spacing as the graph.

local _, mod = ...
if mod.standalone then
    return
end
local C = mod.COLORS

local Views = {}
mod.Views = Views

local ROW_H = 20

-- Each view's regions are pooled on the panel and reset per draw.
local function Kit(panelFrame)
    local ui = mod.UI
    if not panelFrame.kit then
        -- Cells and wrapped paragraphs pool apart, so a cell never inherits a
        -- paragraph's width and alignment.
        panelFrame.kit = {
            text = ui.Pool(function()
                local fontStr = panelFrame:CreateFontString(nil, "OVERLAY")
                fontStr:SetWordWrap(false)
                return fontStr
            end),
            para = ui.Pool(function()
                local fontStr = panelFrame:CreateFontString(nil, "OVERLAY")
                fontStr:SetWordWrap(true)
                fontStr:SetWidth(ui.PANEL_W)
                fontStr:SetJustifyH("LEFT")
                return fontStr
            end),
            fill = ui.Pool(function()
                return panelFrame:CreateTexture(nil, "BACKGROUND")
            end),
            mark = ui.Pool(function()
                return panelFrame:CreateTexture(nil, "ARTWORK")
            end),
            line = ui.Pool(function()
                return panelFrame:CreateTexture(nil, "OVERLAY")
            end),
            -- Clickable rows (guildmates' names open their keys).
            hit = ui.Pool(function()
                local b = CreateFrame("Button", nil, panelFrame)
                b.glow = b:CreateTexture(nil, "BACKGROUND")
                b.glow:SetAllPoints()
                ui.Color(b.glow, C.ink, 0)
                b:SetScript("OnEnter", function(self)
                    ui.Color(self.glow, C.ink, 0.05)
                end)
                b:SetScript("OnLeave", function(self)
                    ui.Color(self.glow, C.ink, 0)
                end)
                return b
            end),
        }
    end
    for _, p in pairs(panelFrame.kit) do
        p:Reset()
    end
    return panelFrame.kit
end

-- Text from the panel's top left. A right-aligned column passes its right edge.
local function Put(panelFrame, font, c, posX, posY, s, right)
    return mod.UI.Text(
        panelFrame.kit.text,
        font,
        c,
        right and "TOPRIGHT" or "TOPLEFT",
        panelFrame,
        "TOPLEFT",
        posX,
        posY,
        s
    )
end

-- A wrapped line of explanation across the panel; returns the y below it.
local function Para(panelFrame, posY, s)
    local fontStr =
        mod.UI.Text(panelFrame.kit.para, "tiny", C.muted, "TOPLEFT", panelFrame, "TOPLEFT", 0, posY, s)
    return posY - fontStr:GetStringHeight() - 4
end

local function Rect(pool, panelFrame, posX, posY, wid, hgt, c, a)
    local t = pool:Get()
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", posX, posY)
    t:SetSize(wid, hgt)
    mod.UI.Color(t, c, a)
    return t
end

-- Keys -----------------------------------------------------------------------------

-- Your best key in each dungeon as a bar, lowest first, against two lines:
-- each title as one key level timed in every dungeon.
function Views.keys(panelFrame, context)
    panelFrame.scroll = nil
    if panelFrame.bar then
        panelFrame.bar:Hide()
    end
    local kit, wid = Kit(panelFrame), mod.UI.PANEL_W
    local goals, rowList = mod.Targets(context.maps, context.myRuns, context.summary.tiers)
    if #rowList == 0 then
        Put(
            panelFrame,
            "body",
            C.ink2,
            0,
            0,
            "No dungeons yet. Open the Mythic+ tab once so the game loads them."
        )
        return
    end

    local atEnd = goals[1] and goals[1].atEnd
    local when = atEnd
            and (context.summary.endsEstimated and " by the season end (est.)" or " by the season end")
        or " today"
    local posY = Para(
        panelFrame,
        0,
        "Your best key in each dungeon. Each line is a title as one key level timed in every dungeon"
            .. when
            .. "."
    )
    posY = Para(panelFrame, posY, mod.SCORING_NOTE) - 6

    -- Legend: the two lines and their levels.
    local posX = 0
    for _, g in ipairs(goals) do
        Rect(kit.mark, panelFrame, posX, posY - 7, 12, 2, g.tier.color)
        local fontStr =
            Put(panelFrame, "small", C.ink2, posX + 18, posY, ("%s  +%d"):format(g.tier.label, g.level))
        posX = posX + 18 + fontStr:GetStringWidth() + 28
    end
    posY = posY - 26

    -- A level scale wide enough for every best and both lines.
    local lo, hi = math.huge, -math.huge
    for _, r in ipairs(rowList) do
        if r.played then
            lo, hi = math.min(lo, r.best), math.max(hi, r.best)
        end
    end
    for _, g in ipairs(goals) do
        lo, hi = math.min(lo, g.level), math.max(hi, g.level)
    end
    lo, hi = math.max(0, lo - 2), hi + 2
    local X0, X1 = 230, wid - 90
    local function LX(level)
        return X0 + (level - lo) / (hi - lo) * (X1 - X0)
    end

    local topY = posY
    for _, r in ipairs(rowList) do
        Put(panelFrame, "body", C.ink, 14, posY, C_ChallengeMode.GetMapUIInfo(r.map) or "?")
        Rect(kit.fill, panelFrame, X0, posY - 5, X1 - X0, 6, C.grid)
        if r.played then
            local c = r.timed and mod.YOU_COLOR or C.ink2
            local x1 = LX(r.best)
            Rect(kit.mark, panelFrame, X0, posY - 5, math.max(2, x1 - X0), 6, c, r.timed and 1 or 0.5)
            Put(
                panelFrame,
                "small",
                r.timed and C.ink2 or C.muted,
                x1 + 6,
                posY - 1,
                ("+%d"):format(r.best) .. (r.timed and "" or " over time")
            )
        else
            Put(panelFrame, "small", C.muted, X0 + 4, posY - 1, "not run")
        end
        posY = posY - ROW_H
    end

    -- The title lines, through every row.
    for _, g in ipairs(goals) do
        Rect(kit.line, panelFrame, LX(g.level) - 1, topY + 2, 2, topY - posY - 2, g.tier.color)
    end

    -- The level axis under the rows.
    local step = (hi - lo) > 14 and 5 or 2
    for level = math.ceil(lo / step) * step, hi, step do
        mod.UI.Text(
            kit.text,
            "tiny",
            C.muted,
            "TOP",
            panelFrame,
            "TOPLEFT",
            LX(level),
            posY - 2,
            "+" .. level
        )
    end
end

-- Guild ------------------------------------------------------------------------------

local GUILD_STATES = {
    none = "You are not in a guild.",
    hidden = "Guild ratings are hidden while you are in combat in an instance. They come back afterwards.",
    loading = "Loading the guild roster...",
}

-- Your guild ranked by rating, with each title line slotted in where it
-- falls. The list scrolls (wheel, or drag the bar) and opens on you.
local SCROLL_STEP = 3 -- rows per wheel notch
local BAR_W = 4

local function Clamp(st)
    st.offset = math.max(0, math.min(st.offset, math.max(0, #st.entries - st.capacity)))
end

local function DrawGuild(panelFrame)
    local st = panelFrame.scroll
    local kit, wid = Kit(panelFrame), mod.UI.PANEL_W
    Clamp(st)
    Para(panelFrame, 0, st.header)

    local scrolls = #st.entries > st.capacity
    local right = scrolls and (wid - BAR_W - 10) or wid
    local RANK, NAME = 30, 40
    local posY = st.top
    for idx = st.offset + 1, math.min(#st.entries, st.offset + st.capacity) do
        local e = st.entries[idx]
        if e.line then
            local s = e.line
            local c = s.tier.color
            Rect(kit.mark, panelFrame, NAME, posY - 8, 12, 2, c)
            Put(panelFrame, "small", C.ink2, NAME + 18, posY - 1, s.tier.label .. " line")
            Rect(kit.fill, panelFrame, NAME + 130, posY - 8, right - NAME - 200, 1, c, 0.5)
            Put(panelFrame, "small", C.ink2, right, posY - 1, mod.Fmt(s.lineNow), true)
        else
            local m = e.member
            if m.isSelf then
                Rect(kit.fill, panelFrame, 0, posY + 3, right + 4, ROW_H, C.raised)
                Rect(kit.mark, panelFrame, 0, posY + 3, 3, ROW_H, mod.YOU_COLOR)
            end
            Put(panelFrame, "small", C.muted, RANK, posY, e.rank .. ".", true)
            local name = Put(panelFrame, "body", mod.ClassColor(m.class), NAME, posY, "")
            name:SetText(m.name or "?")
            Put(panelFrame, "body", C.ink, right, posY, mod.Fmt(m.score), true)
            -- Click a guildmate for their keys.
            if not m.isSelf and m.key then
                local hit = kit.hit:Get()
                hit:ClearAllPoints()
                hit:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 0, posY + 3)
                hit:SetSize(right + 4, ROW_H)
                hit.member = m
                hit:SetScript("OnClick", function(self)
                    Views.OpenCard(panelFrame, self.member)
                end)
            end
        end
        posY = posY - ROW_H
    end

    -- The scroll bar: a hairline track, and a thumb sized to the share in view.
    local bar = panelFrame.bar
    bar:SetShown(scrolls)
    if scrolls then
        local trackH = st.capacity * ROW_H
        local thumbH = math.max(20, trackH * st.capacity / #st.entries)
        local travel = trackH - thumbH
        Rect(kit.fill, panelFrame, wid - BAR_W, st.top + 3, BAR_W, trackH, C.grid)
        bar.travel, bar.trackH = travel, trackH
        bar:SetSize(BAR_W, thumbH)
        bar:ClearAllPoints()
        bar:SetPoint(
            "TOPLEFT",
            panelFrame,
            "TOPLEFT",
            wid - BAR_W,
            st.top + 3 - travel * st.offset / (#st.entries - st.capacity)
        )
    end
end

-- Move the list by `rows`, redrawing only if it actually moved.
local function ScrollBy(panelFrame, rowList)
    local st = panelFrame.scroll
    if not st then
        return
    end
    local before = st.offset
    st.offset = st.offset + rowList
    Clamp(st)
    if st.offset ~= before then
        DrawGuild(panelFrame)
    end
end

-- Wheel and scroll bar handlers, attached to the panel once.
local function SetUpScrolling(panelFrame)
    if panelFrame.bar then
        return
    end
    panelFrame:EnableMouseWheel(true)
    panelFrame:SetScript("OnMouseWheel", function(_, delta)
        ScrollBy(panelFrame, -delta * SCROLL_STEP)
    end)
    -- Leaving the Guild view forgets the position, so it reopens on you,
    -- and closes any open card.
    panelFrame:SetScript("OnHide", function()
        panelFrame.scroll = nil
        if panelFrame.card then
            panelFrame.card:Hide()
        end
    end)

    local bar = CreateFrame("Button", nil, panelFrame)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetAllPoints()
    mod.UI.Color(bar.fill, C.ink2, 0.45)
    bar:SetScript("OnEnter", function()
        mod.UI.Color(bar.fill, C.ink2, 0.8)
    end)
    bar:SetScript("OnLeave", function()
        if not bar.dragging then
            mod.UI.Color(bar.fill, C.ink2, 0.45)
        end
    end)
    -- Dragging: rows follow the cursor at the track's scale.
    bar:SetScript("OnMouseDown", function(self)
        local st = panelFrame.scroll
        if not st or self.travel <= 0 then
            return
        end
        local _, posY = GetCursorPosition()
        self.dragging, self.startY, self.startOffset = true, posY / self:GetEffectiveScale(), st.offset
        self:SetScript("OnUpdate", function()
            local _, cy = GetCursorPosition()
            local moved = self.startY - cy / self:GetEffectiveScale()
            local rowList = (#st.entries - st.capacity) * moved / self.travel
            ScrollBy(panelFrame, math.floor(self.startOffset + rowList + 0.5) - st.offset)
        end)
    end)
    bar:SetScript("OnMouseUp", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        if not self:IsMouseOver() then
            mod.UI.Color(self.fill, C.ink2, 0.45)
        end
    end)
    bar:Hide()
    panelFrame.bar = bar
end

-- A guildmate's keys, as a card over the list: their best in each dungeon,
-- from their own TitleLine if it answers, else from when you last grouped.
local CARD_ROWS = 8

local function SetUpCard(panelFrame)
    if panelFrame.card then
        return panelFrame.card
    end
    local ui = mod.UI
    local cardFrame = CreateFrame("Frame", nil, panelFrame)
    cardFrame:SetFrameLevel(panelFrame:GetFrameLevel() + 20)
    cardFrame:EnableMouse(true)
    -- The list underneath must not scroll while the card is up.
    cardFrame:EnableMouseWheel(true)
    cardFrame:SetScript("OnMouseWheel", function() end)
    local backdrop = cardFrame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    ui.Color(backdrop, C.raised)
    ui.Hairlines(cardFrame, 0.12)
    local close = ui.MakeClose(cardFrame)
    close:SetPoint("TOPRIGHT", -6, -6)
    cardFrame.kit = {
        text = ui.Pool(function()
            local fontStr = cardFrame:CreateFontString(nil, "OVERLAY")
            fontStr:SetWordWrap(false)
            return fontStr
        end),
        para = ui.Pool(function()
            local fontStr = cardFrame:CreateFontString(nil, "OVERLAY")
            fontStr:SetWordWrap(true)
            fontStr:SetJustifyH("LEFT")
            return fontStr
        end),
    }
    cardFrame:Hide()
    panelFrame.card = cardFrame
    return cardFrame
end

local function Ago(at, nowTime)
    if not at then
        return nil
    end
    return nowTime - at < 120 and "just now" or mod.DateText(at)
end

local function DrawCard(panelFrame)
    local cardFrame, m = panelFrame.card, panelFrame.cardFor
    if not cardFrame or not m or not cardFrame:IsShown() then
        return
    end
    local ui, kit = mod.UI, cardFrame.kit
    for _, p in pairs(kit) do
        p:Reset()
    end
    local context = panelFrame.cardCtx
    local nowTime = time()
    local wid = mod.UI.PANEL_W - 28
    local function textValue(font, c, posX, posY, s, right)
        return ui.Text(
            kit.text,
            font,
            c,
            right and "TOPRIGHT" or "TOPLEFT",
            cardFrame,
            "TOPLEFT",
            posX,
            posY,
            s
        )
    end

    local name = textValue("title", mod.ClassColor(m.class), 14, -12, "")
    name:SetText(m.name or "?")

    local payload, source = mod.Share.Keys(m.key)
    local asking = mod.Share.AskState(m.key)
    local sub
    if source == "shared" then
        sub = ("%s rating, from their TitleLine %s"):format(mod.Fmt(m.score), Ago(payload.at, nowTime))
        if (payload.count or 0) > 0 then
            sub = sub .. (", %d keys this season"):format(payload.count)
        end
    elseif source == "grouped" then
        sub = ("%s rating. Keys as of when you grouped, %s"):format(
            mod.Fmt(m.score),
            Ago(payload.at, nowTime) or "earlier"
        )
    else
        sub = mod.Fmt(m.score) .. " rating"
    end
    if asking == "asking" then
        sub = sub .. ". Asking their TitleLine..."
    end
    textValue("small", C.muted, 14, -36, sub)

    if not payload then
        local why
        if asking == "asking" then
            why = "Waiting for an answer from their TitleLine."
        elseif not m.online then
            why =
                "They are offline. Their keys show once they are online with TitleLine, or after you group with them."
        else
            why = "No answer: they may not have TitleLine. Their keys show after you group with them."
        end
        local fontStr = ui.Text(kit.para, "body", C.ink2, "TOPLEFT", cardFrame, "TOPLEFT", 14, -66, why)
        fontStr:SetWidth(wid)
        return
    end

    -- Every dungeon this season, their best first; ones without a run last.
    local byMap = {}
    for _, r in ipairs(payload.runs) do
        byMap[r.map] = r
    end
    local rowList = {}
    for _, map in ipairs(context.maps) do
        rowList[#rowList + 1] = byMap[map] or { map = map }
    end
    table.sort(rowList, function(a, b)
        return (a.level or 0) > (b.level or 0)
    end)

    local NAME, BEST, SCORE, WHEN = 14, 300, 470, wid
    local posY = -66
    textValue("tiny", C.muted, NAME, posY, "Dungeon")
    textValue("tiny", C.muted, BEST, posY, "Best")
    textValue("tiny", C.muted, SCORE, posY, "Score", true)
    textValue("tiny", C.muted, WHEN, posY, "When", true)
    posY = posY - 20
    for idx = 1, math.min(#rowList, CARD_ROWS) do
        local r = rowList[idx]
        textValue("body", C.ink, NAME, posY, C_ChallengeMode.GetMapUIInfo(r.map) or "?")
        if r.level then
            textValue(
                "body",
                r.timed and C.ink2 or C.muted,
                BEST,
                posY,
                ("+%d"):format(r.level) .. (r.timed and "" or " over time")
            )
            textValue("body", C.ink2, SCORE, posY, mod.Fmt(r.score), true)
            local when = r.day and mod.DateText(context.region.startsAt + r.day * mod.DAY) or "-"
            textValue("body", C.muted, WHEN, posY, when, true)
        else
            textValue("body", C.muted, BEST, posY, "not run")
        end
        posY = posY - ROW_H
    end
end

-- Open a guildmate's card, asking their TitleLine if they are online.
function Views.OpenCard(panelFrame, m)
    local cardFrame = SetUpCard(panelFrame)
    cardFrame:ClearAllPoints()
    cardFrame:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 0, panelFrame.scroll.top + 4)
    cardFrame:SetSize(mod.UI.PANEL_W, mod.UI.PANEL_H + panelFrame.scroll.top - 4)
    panelFrame.cardFor, panelFrame.cardCtx = m, panelFrame.scroll.ctx
    cardFrame:Show()
    if m.online and mod.Share.AskState(m.key) ~= "asking" and mod.Share.Ask(m.key) then
        -- Redraw when an unanswered ask times out into "no answer".
        C_Timer.After(16, function()
            DrawCard(panelFrame)
        end)
    end
    DrawCard(panelFrame)
end

-- A reply arrived: redraw the card if it is that player's.
function Views.OnShared(sender)
    local panelFrame = Views.guildPanel
    if panelFrame and panelFrame.cardFor and panelFrame.cardFor.key == sender then
        DrawCard(panelFrame)
    end
end

function Views.guild(panelFrame, context)
    Views.guildPanel = panelFrame
    SetUpScrolling(panelFrame)
    Kit(panelFrame)
    local g = mod.Guild(context.region.startsAt, context.now)
    if g.state ~= "ok" then
        panelFrame.scroll = nil
        panelFrame.bar:Hide()
        Put(panelFrame, "body", C.ink2, 0, 0, GUILD_STATES[g.state])
        return
    end
    local members, tiers = g.members, context.summary.tiers

    -- The lines, highest first, slotted into the ranking where they fall.
    local lines = {}
    for _, s in ipairs(tiers) do
        lines[#lines + 1] = s
    end
    table.sort(lines, function(a, b)
        return a.lineNow > b.lineNow
    end)
    local counts = {}
    for _, s in ipairs(lines) do
        local num = 0
        for _, m in ipairs(members) do
            if m.score >= s.lineNow then
                num = num + 1
            end
        end
        counts[#counts + 1] = ("%d above %s"):format(num, s.tier.short)
    end

    local entries, li, selfAt = {}, 1, nil
    for rank, m in ipairs(members) do
        while lines[li] and m.score < lines[li].lineNow do
            entries[#entries + 1] = { line = lines[li] }
            li = li + 1
        end
        entries[#entries + 1] = { member = m, rank = rank }
        if m.isSelf then
            selfAt = #entries
        end
    end
    while lines[li] do
        entries[#entries + 1] = { line = lines[li] }
        li = li + 1
    end

    -- A roster refresh keeps your place; a fresh open centres on you.
    local fresh = not panelFrame.scroll
    local st = panelFrame.scroll or { offset = 0 }
    panelFrame.scroll = st
    st.entries, st.ctx = entries, context
    st.header = #members > 0
            and ("%d guildmates with a rating this season: %s."):format(#members, table.concat(counts, ", "))
        or "Nobody in the guild has a rating this season yet."
    -- The roster keeps old seasons' ratings; say how many were left out.
    if g.stale > 0 then
        st.header = st.header
            .. (" %d not online since the season began are left out, as their rating is from an earlier season."):format(
                g.stale
            )
    end
    st.top = Para(panelFrame, 0, st.header) - 8
    st.capacity = math.max(1, math.floor((mod.UI.PANEL_H + st.top) / ROW_H))
    if fresh and selfAt then
        st.offset = selfAt - math.ceil(st.capacity / 2)
    end
    DrawGuild(panelFrame)
end
