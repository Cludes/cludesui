-- The Keys and Guild views: tables drawn in the plot's place, with the same
-- surfaces, ink and spacing as the graph.

local _, ns = ...
if ns.standalone then
    return
end
local C = ns.COLORS

local Views = {}
ns.Views = Views

local ROW_H = 20

-- Each view's regions are pooled on the panel and reset per draw.
local function Kit(panel)
    local ui = ns.UI
    if not panel.kit then
        -- Cells and wrapped paragraphs pool apart, so a cell never inherits a
        -- paragraph's width and alignment.
        panel.kit = {
            text = ui.Pool(function()
                local fs = panel:CreateFontString(nil, "OVERLAY")
                fs:SetWordWrap(false)
                return fs
            end),
            para = ui.Pool(function()
                local fs = panel:CreateFontString(nil, "OVERLAY")
                fs:SetWordWrap(true)
                fs:SetWidth(ui.PANEL_W)
                fs:SetJustifyH("LEFT")
                return fs
            end),
            fill = ui.Pool(function()
                return panel:CreateTexture(nil, "BACKGROUND")
            end),
            mark = ui.Pool(function()
                return panel:CreateTexture(nil, "ARTWORK")
            end),
            line = ui.Pool(function()
                return panel:CreateTexture(nil, "OVERLAY")
            end),
            -- Clickable rows (guildmates' names open their keys).
            hit = ui.Pool(function()
                local b = CreateFrame("Button", nil, panel)
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
    for _, p in pairs(panel.kit) do
        p:Reset()
    end
    return panel.kit
end

-- Text from the panel's top left. A right-aligned column passes its right edge.
local function Put(panel, font, c, x, y, s, right)
    return ns.UI.Text(panel.kit.text, font, c, right and "TOPRIGHT" or "TOPLEFT", panel, "TOPLEFT", x, y, s)
end

-- A wrapped line of explanation across the panel; returns the y below it.
local function Para(panel, y, s)
    local fs = ns.UI.Text(panel.kit.para, "tiny", C.muted, "TOPLEFT", panel, "TOPLEFT", 0, y, s)
    return y - fs:GetStringHeight() - 4
end

local function Rect(pool, panel, x, y, w, h, c, a)
    local t = pool:Get()
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    t:SetSize(w, h)
    ns.UI.Color(t, c, a)
    return t
end

-- Keys -----------------------------------------------------------------------------

-- Your best key in each dungeon as a bar, lowest first, against two lines:
-- each title as one key level timed in every dungeon.
function Views.keys(panel, ctx)
    panel.scroll = nil
    if panel.bar then
        panel.bar:Hide()
    end
    local kit, w = Kit(panel), ns.UI.PANEL_W
    local goals, rows = ns.Targets(ctx.maps, ctx.myRuns, ctx.summary.tiers)
    if #rows == 0 then
        Put(panel, "body", C.ink2, 0, 0, "No dungeons yet. Open the Mythic+ tab once so the game loads them.")
        return
    end

    local atEnd = goals[1] and goals[1].atEnd
    local when = atEnd and (ctx.summary.endsEstimated and " by the season end (est.)" or " by the season end")
        or " today"
    local y = Para(
        panel,
        0,
        "Your best key in each dungeon. Each line is a title as one key level timed in every dungeon"
            .. when
            .. "."
    )
    y = Para(panel, y, ns.SCORING_NOTE) - 6

    -- Legend: the two lines and their levels.
    local x = 0
    for _, g in ipairs(goals) do
        Rect(kit.mark, panel, x, y - 7, 12, 2, g.tier.color)
        local fs = Put(panel, "small", C.ink2, x + 18, y, ("%s  +%d"):format(g.tier.label, g.level))
        x = x + 18 + fs:GetStringWidth() + 28
    end
    y = y - 26

    -- A level scale wide enough for every best and both lines.
    local lo, hi = math.huge, -math.huge
    for _, r in ipairs(rows) do
        if r.played then
            lo, hi = math.min(lo, r.best), math.max(hi, r.best)
        end
    end
    for _, g in ipairs(goals) do
        lo, hi = math.min(lo, g.level), math.max(hi, g.level)
    end
    lo, hi = math.max(0, lo - 2), hi + 2
    local X0, X1 = 230, w - 90
    local function LX(level)
        return X0 + (level - lo) / (hi - lo) * (X1 - X0)
    end

    local top = y
    for _, r in ipairs(rows) do
        Put(panel, "body", C.ink, 14, y, C_ChallengeMode.GetMapUIInfo(r.map) or "?")
        Rect(kit.fill, panel, X0, y - 5, X1 - X0, 6, C.grid)
        if r.played then
            local c = r.timed and ns.YOU_COLOR or C.ink2
            local x1 = LX(r.best)
            Rect(kit.mark, panel, X0, y - 5, math.max(2, x1 - X0), 6, c, r.timed and 1 or 0.5)
            Put(
                panel,
                "small",
                r.timed and C.ink2 or C.muted,
                x1 + 6,
                y - 1,
                ("+%d"):format(r.best) .. (r.timed and "" or " over time")
            )
        else
            Put(panel, "small", C.muted, X0 + 4, y - 1, "not run")
        end
        y = y - ROW_H
    end

    -- The title lines, through every row.
    for _, g in ipairs(goals) do
        Rect(kit.line, panel, LX(g.level) - 1, top + 2, 2, top - y - 2, g.tier.color)
    end

    -- The level axis under the rows.
    local step = (hi - lo) > 14 and 5 or 2
    for level = math.ceil(lo / step) * step, hi, step do
        ns.UI.Text(kit.text, "tiny", C.muted, "TOP", panel, "TOPLEFT", LX(level), y - 2, "+" .. level)
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

local function DrawGuild(panel)
    local st = panel.scroll
    local kit, w = Kit(panel), ns.UI.PANEL_W
    Clamp(st)
    Para(panel, 0, st.header)

    local scrolls = #st.entries > st.capacity
    local right = scrolls and (w - BAR_W - 10) or w
    local RANK, NAME = 30, 40
    local y = st.top
    for i = st.offset + 1, math.min(#st.entries, st.offset + st.capacity) do
        local e = st.entries[i]
        if e.line then
            local s = e.line
            local c = s.tier.color
            Rect(kit.mark, panel, NAME, y - 8, 12, 2, c)
            Put(panel, "small", C.ink2, NAME + 18, y - 1, s.tier.label .. " line")
            Rect(kit.fill, panel, NAME + 130, y - 8, right - NAME - 200, 1, c, 0.5)
            Put(panel, "small", C.ink2, right, y - 1, ns.Fmt(s.lineNow), true)
        else
            local m = e.member
            if m.isSelf then
                Rect(kit.fill, panel, 0, y + 3, right + 4, ROW_H, C.raised)
                Rect(kit.mark, panel, 0, y + 3, 3, ROW_H, ns.YOU_COLOR)
            end
            Put(panel, "small", C.muted, RANK, y, e.rank .. ".", true)
            local name = Put(panel, "body", ns.ClassColor(m.class), NAME, y, "")
            name:SetText(m.name or "?")
            Put(panel, "body", C.ink, right, y, ns.Fmt(m.score), true)
            -- Click a guildmate for their keys.
            if not m.isSelf and m.key then
                local hit = kit.hit:Get()
                hit:ClearAllPoints()
                hit:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y + 3)
                hit:SetSize(right + 4, ROW_H)
                hit.member = m
                hit:SetScript("OnClick", function(self)
                    Views.OpenCard(panel, self.member)
                end)
            end
        end
        y = y - ROW_H
    end

    -- The scroll bar: a hairline track, and a thumb sized to the share in view.
    local bar = panel.bar
    bar:SetShown(scrolls)
    if scrolls then
        local trackH = st.capacity * ROW_H
        local thumbH = math.max(20, trackH * st.capacity / #st.entries)
        local travel = trackH - thumbH
        Rect(kit.fill, panel, w - BAR_W, st.top + 3, BAR_W, trackH, C.grid)
        bar.travel, bar.trackH = travel, trackH
        bar:SetSize(BAR_W, thumbH)
        bar:ClearAllPoints()
        bar:SetPoint(
            "TOPLEFT",
            panel,
            "TOPLEFT",
            w - BAR_W,
            st.top + 3 - travel * st.offset / (#st.entries - st.capacity)
        )
    end
end

-- Move the list by `rows`, redrawing only if it actually moved.
local function ScrollBy(panel, rows)
    local st = panel.scroll
    if not st then
        return
    end
    local before = st.offset
    st.offset = st.offset + rows
    Clamp(st)
    if st.offset ~= before then
        DrawGuild(panel)
    end
end

-- Wheel and scroll bar handlers, attached to the panel once.
local function SetUpScrolling(panel)
    if panel.bar then
        return
    end
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        ScrollBy(panel, -delta * SCROLL_STEP)
    end)
    -- Leaving the Guild view forgets the position, so it reopens on you,
    -- and closes any open card.
    panel:SetScript("OnHide", function()
        panel.scroll = nil
        if panel.card then
            panel.card:Hide()
        end
    end)

    local bar = CreateFrame("Button", nil, panel)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetAllPoints()
    ns.UI.Color(bar.fill, C.ink2, 0.45)
    bar:SetScript("OnEnter", function()
        ns.UI.Color(bar.fill, C.ink2, 0.8)
    end)
    bar:SetScript("OnLeave", function()
        if not bar.dragging then
            ns.UI.Color(bar.fill, C.ink2, 0.45)
        end
    end)
    -- Dragging: rows follow the cursor at the track's scale.
    bar:SetScript("OnMouseDown", function(self)
        local st = panel.scroll
        if not st or self.travel <= 0 then
            return
        end
        local _, y = GetCursorPosition()
        self.dragging, self.startY, self.startOffset = true, y / self:GetEffectiveScale(), st.offset
        self:SetScript("OnUpdate", function()
            local _, cy = GetCursorPosition()
            local moved = self.startY - cy / self:GetEffectiveScale()
            local rows = (#st.entries - st.capacity) * moved / self.travel
            ScrollBy(panel, math.floor(self.startOffset + rows + 0.5) - st.offset)
        end)
    end)
    bar:SetScript("OnMouseUp", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        if not self:IsMouseOver() then
            ns.UI.Color(self.fill, C.ink2, 0.45)
        end
    end)
    bar:Hide()
    panel.bar = bar
end

-- A guildmate's keys, as a card over the list: their best in each dungeon,
-- from their own TitleLine if it answers, else from when you last grouped.
local CARD_ROWS = 8

local function SetUpCard(panel)
    if panel.card then
        return panel.card
    end
    local ui = ns.UI
    local card = CreateFrame("Frame", nil, panel)
    card:SetFrameLevel(panel:GetFrameLevel() + 20)
    card:EnableMouse(true)
    -- The list underneath must not scroll while the card is up.
    card:EnableMouseWheel(true)
    card:SetScript("OnMouseWheel", function() end)
    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    ui.Color(bg, C.raised)
    ui.Hairlines(card, 0.12)
    local close = ui.MakeClose(card)
    close:SetPoint("TOPRIGHT", -6, -6)
    card.kit = {
        text = ui.Pool(function()
            local fs = card:CreateFontString(nil, "OVERLAY")
            fs:SetWordWrap(false)
            return fs
        end),
        para = ui.Pool(function()
            local fs = card:CreateFontString(nil, "OVERLAY")
            fs:SetWordWrap(true)
            fs:SetJustifyH("LEFT")
            return fs
        end),
    }
    card:Hide()
    panel.card = card
    return card
end

local function Ago(at, now)
    if not at then
        return nil
    end
    return now - at < 120 and "just now" or ns.DateText(at)
end

local function DrawCard(panel)
    local card, m = panel.card, panel.cardFor
    if not card or not m or not card:IsShown() then
        return
    end
    local ui, kit = ns.UI, card.kit
    for _, p in pairs(kit) do
        p:Reset()
    end
    local ctx = panel.cardCtx
    local now = time()
    local w = ns.UI.PANEL_W - 28
    local function text(font, c, x, y, s, right)
        return ui.Text(kit.text, font, c, right and "TOPRIGHT" or "TOPLEFT", card, "TOPLEFT", x, y, s)
    end

    local name = text("title", ns.ClassColor(m.class), 14, -12, "")
    name:SetText(m.name or "?")

    local data, source = ns.Share.Keys(m.key)
    local asking = ns.Share.AskState(m.key)
    local sub
    if source == "shared" then
        sub = ("%s rating, from their TitleLine %s"):format(ns.Fmt(m.score), Ago(data.at, now))
        if (data.count or 0) > 0 then
            sub = sub .. (", %d keys this season"):format(data.count)
        end
    elseif source == "grouped" then
        sub = ("%s rating. Keys as of when you grouped, %s"):format(
            ns.Fmt(m.score),
            Ago(data.at, now) or "earlier"
        )
    else
        sub = ns.Fmt(m.score) .. " rating"
    end
    if asking == "asking" then
        sub = sub .. ". Asking their TitleLine..."
    end
    text("small", C.muted, 14, -36, sub)

    if not data then
        local why
        if asking == "asking" then
            why = "Waiting for an answer from their TitleLine."
        elseif not m.online then
            why =
                "They are offline. Their keys show once they are online with TitleLine, or after you group with them."
        else
            why = "No answer: they may not have TitleLine. Their keys show after you group with them."
        end
        local fs = ui.Text(kit.para, "body", C.ink2, "TOPLEFT", card, "TOPLEFT", 14, -66, why)
        fs:SetWidth(w)
        return
    end

    -- Every dungeon this season, their best first; ones without a run last.
    local byMap = {}
    for _, r in ipairs(data.runs) do
        byMap[r.map] = r
    end
    local rows = {}
    for _, map in ipairs(ctx.maps) do
        rows[#rows + 1] = byMap[map] or { map = map }
    end
    table.sort(rows, function(a, b)
        return (a.level or 0) > (b.level or 0)
    end)

    local NAME, BEST, SCORE, WHEN = 14, 300, 470, w
    local y = -66
    text("tiny", C.muted, NAME, y, "Dungeon")
    text("tiny", C.muted, BEST, y, "Best")
    text("tiny", C.muted, SCORE, y, "Score", true)
    text("tiny", C.muted, WHEN, y, "When", true)
    y = y - 20
    for i = 1, math.min(#rows, CARD_ROWS) do
        local r = rows[i]
        text("body", C.ink, NAME, y, C_ChallengeMode.GetMapUIInfo(r.map) or "?")
        if r.level then
            text(
                "body",
                r.timed and C.ink2 or C.muted,
                BEST,
                y,
                ("+%d"):format(r.level) .. (r.timed and "" or " over time")
            )
            text("body", C.ink2, SCORE, y, ns.Fmt(r.score), true)
            local when = r.day and ns.DateText(ctx.region.startsAt + r.day * ns.DAY) or "-"
            text("body", C.muted, WHEN, y, when, true)
        else
            text("body", C.muted, BEST, y, "not run")
        end
        y = y - ROW_H
    end
end

-- Open a guildmate's card, asking their TitleLine if they are online.
function Views.OpenCard(panel, m)
    local card = SetUpCard(panel)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, panel.scroll.top + 4)
    card:SetSize(ns.UI.PANEL_W, ns.UI.PANEL_H + panel.scroll.top - 4)
    panel.cardFor, panel.cardCtx = m, panel.scroll.ctx
    card:Show()
    if m.online and ns.Share.AskState(m.key) ~= "asking" and ns.Share.Ask(m.key) then
        -- Redraw when an unanswered ask times out into "no answer".
        C_Timer.After(16, function()
            DrawCard(panel)
        end)
    end
    DrawCard(panel)
end

-- A reply arrived: redraw the card if it is that player's.
function Views.OnShared(sender)
    local panel = Views.guildPanel
    if panel and panel.cardFor and panel.cardFor.key == sender then
        DrawCard(panel)
    end
end

function Views.guild(panel, ctx)
    Views.guildPanel = panel
    SetUpScrolling(panel)
    Kit(panel)
    local g = ns.Guild(ctx.region.startsAt, ctx.now)
    if g.state ~= "ok" then
        panel.scroll = nil
        panel.bar:Hide()
        Put(panel, "body", C.ink2, 0, 0, GUILD_STATES[g.state])
        return
    end
    local members, tiers = g.members, ctx.summary.tiers

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
        local n = 0
        for _, m in ipairs(members) do
            if m.score >= s.lineNow then
                n = n + 1
            end
        end
        counts[#counts + 1] = ("%d above %s"):format(n, s.tier.short)
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
    local fresh = not panel.scroll
    local st = panel.scroll or { offset = 0 }
    panel.scroll = st
    st.entries, st.ctx = entries, ctx
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
    st.top = Para(panel, 0, st.header) - 8
    st.capacity = math.max(1, math.floor((ns.UI.PANEL_H + st.top) / ROW_H))
    if fresh and selfAt then
        st.offset = selfAt - math.ceil(st.capacity / 2)
    end
    DrawGuild(panel)
end
