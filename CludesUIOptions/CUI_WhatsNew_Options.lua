if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Patch Notes page builder; its content table stays in CUI__General_Options.lua.

-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame
local PoolKeep, PoolGen = CludesUI._Pool.Keep, CludesUI._Pool.Gen

-- An accent-coloured piece repaints itself (paint(r, g, b)) when the accent
-- changes. Keyed by the piece: the page pool forgets the entry when it resets
-- it, and the kept Legends page registers each piece once.
local function OnAccent(object, paint)
    CludesUI.RegAccent({ type = "callback", obj = object, fn = paint })
end

-------------------------------------------------------------------------------
--  What's New page -- one expandable card per patch (the shared module card),
--  newest first. A card's header counts the patch's major features,
--  additional features and bug fixes; open, it shows the three tiers: hero
--  cards (2/row), small clickable listings, fix lines. Content:
--  CludesUI._WHATSNEW_PATCHES (newest first). Entry `nav` deep-links via
--  NavigateToElementSettings (opens page, pulses control); no `nav` = static
--  non-clickable card. File-scope fn so it adds no locals/upvalues to the
--  deferred options closure. whatsNewOpen: the open cards by version, for the
--  session (the newest starts open).
-------------------------------------------------------------------------------
local whatsNewOpen = {}
local NOTES_ICON = "Interface\\AddOns\\CludesUI\\media\\icons\\sidebar\\notes-off.png"
function CludesUI._BuildWhatsNewPage(pageName, hostFrame, yOffset)
    local Pix = CludesUI.PanelPP
    local ACC = CludesUI.CLUDES_GREEN
    local PAD = CludesUI.CONTENT_PAD
    local W = CludesUI.Widgets
    local MakeFont = CludesUI.MakeFont
    local MakeBorder = CludesUI.MakeBorder

    -- This page is a free-form feed, not a DualRow split layout.
    hostFrame._showRowDivider = nil

    local posY = yOffset
    local totalW = hostFrame:GetWidth() - PAD * 2
    local CARD_GAP = 14

    -- Display prefix: "Module: " on every entry, and "WoW Forever - " in the
    -- Forever theme's bronze ahead of it on entries flagged `forever = true`
    -- (changes that apply on WoW Forever only), "Retail - " in blue on entries
    -- flagged `retail = true` (changes that apply on retail only), shown on
    -- WoW Forever alone, or the game patch in violet on entries that apply
    -- from one retail patch on (`patch = "12.1.5"`), so the note text itself
    -- never has to say where it applies. Sorting stays by module, so a
    -- module's lines sit together whatever their tag.
    local FOREVER_TAG = "|cffdca77f" .. CludesUI.L("WoW Forever") .. "|r - "
    local RETAIL_TAG = CludesUI.IS_FOREVER and ("|cff74b9ff" .. CludesUI.L("Retail") .. "|r - ") or nil
    local function PrefixOf(e)
        local tag = (e.forever and FOREVER_TAG)
            or (e.retail and RETAIL_TAG)
            or (e.patch and ("|cffa88bff" .. e.patch .. "|r - "))
            or ""
        return tag .. ((e.module and CludesUI.L(e.module) .. ": ") or "")
    end
    -- Display title: "Module: Title" (see PrefixOf).
    local function TitleOf(e)
        return PrefixOf(e) .. (CludesUI.L(e.title) or "")
    end

    -- Stable sort by module display name; preserves authored order per module.
    local function SortByModule(entries)
        local position = {}
        for i, e in ipairs(entries) do
            position[i] = { e, i }
        end
        table.sort(position, function(a, b)
            local am, bm = a[1].module or "", b[1].module or ""
            if am ~= bm then
                -- Localization always closes the list.
                if am == "Localization" or bm == "Localization" then
                    return bm == "Localization"
                end
                return am < bm
            end
            return a[2] < b[2]
        end)
        local result = {}
        for i = 1, #position do
            result[i] = position[i][1]
        end
        return result
    end

    -- An entry's nav target: its nav while the nav's module is registered, else nil.
    -- A module that is off (or not on this client) has no page to open, and the
    -- nav's preSelect may call that module's own setters; such a card renders static.
    local function NavTarget(nav)
        if nav and nav.module and CludesUI:GetModuleTitle(nav.module) then
            return nav
        end
    end

    -- Deep-link to a setting (opens the page; highlights the control if mapped).
    local function GoTo(nav)
        nav = NavTarget(nav)
        if nav then
            CludesUI:NavigateToElementSettings(
                nav.module,
                nav.page,
                nav.section,
                nav.preSelect,
                nav.highlight
            )
        end
    end

    -- Tier 1: clickable hero card -- dark fill, faint border, green top accent, title + wrapping description, hover lift.
    local function MakeHeroCard(posX, cy, wid, hgt, record)
        local cardFrame = CreateFrame("Button", nil, hostFrame)
        Pix.Size(cardFrame, wid, hgt)
        Pix.Point(cardFrame, "TOPLEFT", hostFrame, "TOPLEFT", posX, cy)
        cardFrame:SetFrameLevel(hostFrame:GetFrameLevel() + 2)

        local brd = CludesUI.MakeRoundedCard(cardFrame, 0.12, 0.50, 2)
        local backdrop, accent = brd.bg, brd.accent

        accent:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.6)
        OnAccent(accent, function(r, g, b)
            accent:SetColorTexture(r, g, b, 0.6)
        end)

        local titleFs = MakeFont(cardFrame, 14, nil, ACC.r, ACC.g, ACC.b, 0.9)
        OnAccent(titleFs, function(r, g, b)
            titleFs:SetTextColor(r, g, b, 0.9)
        end)
        Pix.Point(titleFs, "TOPLEFT", cardFrame, "TOPLEFT", 16, -14)
        Pix.Point(titleFs, "RIGHT", cardFrame, "RIGHT", -16, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        titleFs:SetText(TitleOf(record))

        local descFs = MakeFont(cardFrame, 12, nil, 1, 1, 1, 0.45)
        Pix.Point(descFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -7)
        Pix.Point(descFs, "RIGHT", cardFrame, "RIGHT", -16, 0)
        descFs:SetJustifyH("LEFT")
        descFs:SetJustifyV("TOP")
        descFs:SetWordWrap(true)
        descFs:SetText(CludesUI.L(record.desc) or "")

        -- Clickable only with a nav target. No nav renders a static card: no hover lift, no click, mouse disabled so nothing invites a dead click.
        if record.onClick or NavTarget(record.nav) then
            cardFrame:SetScript("OnEnter", function()
                backdrop:SetColorTexture(0.100, 0.110, 0.124, 0.50)
                brd:SetColor(1, 1, 1, 0.22)
                titleFs:SetAlpha(1)
            end)
            cardFrame:SetScript("OnLeave", function()
                backdrop:SetColorTexture(0.062, 0.070, 0.082, 0.50)
                brd:SetColor(1, 1, 1, 0.12)
                titleFs:SetAlpha(0.9)
            end)
            cardFrame:SetScript("OnClick", function()
                if record.onClick then
                    record.onClick()
                else
                    GoTo(record.nav)
                end
            end)
        else
            cardFrame:EnableMouse(false)
        end
    end

    -- Tier 1b: full-width banner hero (entry.banner = true), styled after our
    -- own announcement popups: solid fill, white 1px border, green top accent, eyebrow
    -- + large centered title/description, plus mirrored mini bar-chart art flanking the
    -- text (cost stepping down left, fps stepping up right). Takes a whole row; height
    -- follows description. Static unless the entry carries a nav.
    local function MakeBannerCard(posX, cy, wid, record)
        local cardFrame = CreateFrame("Button", nil, hostFrame)
        -- Width set FIRST (height provisional): description anchors L+R to the card, so a width-0 card would truncate it to one line instead of wrapping.
        Pix.Size(cardFrame, wid, 100)
        Pix.Point(cardFrame, "TOPLEFT", hostFrame, "TOPLEFT", posX, cy)
        cardFrame:SetFrameLevel(hostFrame:GetFrameLevel() + 2)

        local brd = CludesUI.MakeRoundedCard(cardFrame, 0.15, 0.92, 2)
        local backdrop, accent = brd.bg, brd.accent

        -- Per-entry accent (entry.accent = {r,g,b}); the theme accent otherwise.
        local ac = record.accent or ACC
        -- Only the theme accent follows accent changes; a per-entry one is fixed.
        local function OnBannerAccent(object, paint)
            if not record.accent then
                OnAccent(object, paint)
            end
        end
        accent:SetColorTexture(ac.r, ac.g, ac.b, 0.9)
        OnBannerAccent(accent, function(r, g, b)
            accent:SetColorTexture(r, g, b, 0.9)
        end)

        -- Flanking decorative bar-charts: dim white steps, accent "now" bar, faint baseline.
        -- They are the performance banner's art; a banner that carries its own
        -- logo (entry.logo) keeps its flanks clean instead.
        local BAR_W, BAR_GAP2 = 8, 4
        local function MakeChart(anchorSide, inset, heights, alphas)
            local groupW = #heights * BAR_W + (#heights - 1) * BAR_GAP2
            local base = cardFrame:CreateTexture(nil, "ARTWORK")
            base:SetColorTexture(1, 1, 1, 0.12)
            Pix.Size(base, groupW, 1)
            if anchorSide == "LEFT" then
                Pix.Point(base, "LEFT", cardFrame, "LEFT", inset, -12)
            else
                Pix.Point(base, "RIGHT", cardFrame, "RIGHT", -inset, -12)
            end
            if Pix.DisablePixelSnap then
                Pix.DisablePixelSnap(base)
            end
            for i = 1, #heights do
                local bar = cardFrame:CreateTexture(nil, "ARTWORK")
                local a = alphas[i]
                if a == "green" then
                    bar:SetColorTexture(ac.r, ac.g, ac.b, 0.9)
                    OnBannerAccent(bar, function(r, g, b)
                        bar:SetColorTexture(r, g, b, 0.9)
                    end)
                else
                    bar:SetColorTexture(1, 1, 1, a)
                end
                Pix.Size(bar, BAR_W, heights[i])
                Pix.Point(bar, "BOTTOMLEFT", base, "TOPLEFT", (i - 1) * (BAR_W + BAR_GAP2), 1)
                if Pix.DisablePixelSnap then
                    Pix.DisablePixelSnap(bar)
                end
            end
        end
        if not record.logo then
            -- Left: cost falling to a low accent bar. Right: fps rising to a tall one.
            MakeChart("LEFT", 36, { 34, 26, 19, 13, 8 }, { 0.28, 0.23, 0.18, 0.14, "green" })
            MakeChart("RIGHT", 36, { 8, 13, 19, 26, 34 }, { 0.14, 0.18, 0.23, 0.28, "green" })
        end

        local eyebrow = MakeFont(cardFrame, 11, nil, ac.r, ac.g, ac.b, 0.9)
        OnBannerAccent(eyebrow, function(r, g, b)
            eyebrow:SetTextColor(r, g, b, 0.9)
        end)
        Pix.Point(eyebrow, "TOP", cardFrame, "TOP", 0, -18)
        eyebrow:SetJustifyH("CENTER")
        eyebrow:SetWordWrap(false)
        eyebrow:SetText(CludesUI.L(record.eyebrow or "SPECIAL UPDATE"))

        -- Headline: banner titles stand alone (no "Module:" prefix), rendered
        -- LARGE like popup headlines -- or a logo texture stands in for the
        -- title (entry.logo = { path, coords = {l,r,t,b}, w, h }), the way the
        -- Forever launch popup uses the Forever wordmark as its headline.
        local headline, headH
        if record.logo then
            local lg = cardFrame:CreateTexture(nil, "ARTWORK")
            lg:SetTexture(record.logo.path)
            local c = record.logo.coords
            if c then
                lg:SetTexCoord(c[1], c[2], c[3], c[4])
            end
            Pix.Size(lg, record.logo.w or 250, record.logo.h or 100)
            Pix.Point(lg, "TOP", eyebrow, "BOTTOM", 0, -8)
            headline, headH = lg, record.logo.h or 100
        else
            local titleFs = MakeFont(cardFrame, 24, nil, 1, 1, 1, 1)
            Pix.Point(titleFs, "TOP", eyebrow, "BOTTOM", 0, -8)
            titleFs:SetJustifyH("CENTER")
            titleFs:SetWordWrap(false)
            titleFs:SetText(CludesUI.L(record.title) or "")
            headline, headH = titleFs, 24
        end

        local descFs = MakeFont(cardFrame, 13, nil, 1, 1, 1, 0.5)
        Pix.Point(descFs, "TOP", headline, "BOTTOM", 0, -10)
        Pix.Point(descFs, "LEFT", cardFrame, "LEFT", 110, 0)
        Pix.Point(descFs, "RIGHT", cardFrame, "RIGHT", -110, 0)
        descFs:SetJustifyH("CENTER")
        descFs:SetJustifyV("TOP")
        descFs:SetWordWrap(true)
        descFs:SetText(CludesUI.L(record.desc) or "")

        local dh = math.ceil(descFs:GetStringHeight() or 14)
        local bh = 18 + 11 + 8 + headH + 10 + dh + 28
        Pix.Size(cardFrame, wid, bh)

        if record.onClick or NavTarget(record.nav) then
            cardFrame:SetScript("OnEnter", function()
                brd:SetColor(1, 1, 1, 0.30)
                descFs:SetAlpha(0.65)
            end)
            cardFrame:SetScript("OnLeave", function()
                brd:SetColor(1, 1, 1, 0.15)
                descFs:SetAlpha(0.5)
            end)
            cardFrame:SetScript("OnClick", function()
                if record.onClick then
                    record.onClick()
                else
                    GoTo(record.nav)
                end
            end)
        else
            cardFrame:EnableMouse(false)
        end
        return bh
    end

    -- Tier 2: clickable small listing -- title + subtitle, no card chrome, faint row highlight on hover.
    local function MakeListing(posX, cy, wid, record)
        local ROW_H = 48
        local row = CreateFrame("Button", nil, hostFrame)
        Pix.Size(row, wid, ROW_H)
        Pix.Point(row, "TOPLEFT", hostFrame, "TOPLEFT", posX, cy)
        row:SetFrameLevel(hostFrame:GetFrameLevel() + 2)

        local hov = row:CreateTexture(nil, "BACKGROUND")
        hov:SetAllPoints()
        hov:SetColorTexture(1, 1, 1, 0.07)
        hov:SetAlpha(0)

        local titleFs = MakeFont(row, 13, nil, 1, 1, 1, 0.9)
        Pix.Point(titleFs, "TOPLEFT", row, "TOPLEFT", 6, -5)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        titleFs:SetText(TitleOf(record))

        local subFs = MakeFont(row, 11, nil, 1, 1, 1, 0.4)
        Pix.Point(subFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -4)
        Pix.Point(subFs, "RIGHT", row, "RIGHT", -10, 0)
        subFs:SetJustifyH("LEFT")
        subFs:SetWordWrap(false)
        subFs:SetText(CludesUI.L(record.desc) or "")

        -- Clickable only with a nav target (see MakeHeroCard); else static.
        if record.onClick or NavTarget(record.nav) then
            row:SetScript("OnEnter", function()
                hov:SetAlpha(1)
                titleFs:SetAlpha(1)
            end)
            row:SetScript("OnLeave", function()
                hov:SetAlpha(0)
                titleFs:SetAlpha(0.9)
            end)
            row:SetScript("OnClick", function()
                if record.onClick then
                    record.onClick()
                else
                    GoTo(record.nav)
                end
            end)
        else
            row:EnableMouse(false)
        end
        return ROW_H
    end

    -- Tier 3: a plain bug-fix line (bullet + wrapping text, not clickable),
    -- drawn on `host` (above the patch card's fill) from x to the card's inset.
    local function MakeFixLine(host, posX, rightInset, cy, textValue)
        local dot = MakeFont(host, 12, nil, ACC.r, ACC.g, ACC.b, 0.55)
        OnAccent(dot, function(r, g, b)
            dot:SetTextColor(r, g, b, 0.55)
        end)
        Pix.Point(dot, "TOPLEFT", hostFrame, "TOPLEFT", posX + 2, cy - 1)
        dot:SetText("\226\128\162") -- bullet glyph (ASCII-safe UTF-8 escape)
        local fontStr = MakeFont(host, 12, nil, 1, 1, 1, 0.5)
        Pix.Point(fontStr, "TOPLEFT", hostFrame, "TOPLEFT", posX + 18, cy)
        Pix.Point(fontStr, "RIGHT", hostFrame, "RIGHT", -rightInset, 0)
        fontStr:SetJustifyH("LEFT")
        fontStr:SetWordWrap(true)
        fontStr:SetText(textValue or "")
        local th = fontStr:GetStringHeight() or 14
        return math.max(22, math.ceil(th) + 8)
    end

    -- A tier's title (already localized) inside a patch card: the section label
    -- colour and a faint rule under it, inset with the card's content.
    local function TierHeader(host, posX, cy, wid, textValue)
        local ts = CludesUI.TEXT_SECTION
        local labelText = MakeFont(host, 12, nil, ts.r, ts.g, ts.b, ts.a)
        Pix.Point(labelText, "TOPLEFT", hostFrame, "TOPLEFT", posX, cy - 16)
        labelText:SetText(textValue)
        local rule = host:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(1, 1, 1, 0.07)
        Pix.Size(rule, wid, 1)
        Pix.Point(rule, "TOPLEFT", hostFrame, "TOPLEFT", posX, cy - 34)
        if Pix.DisablePixelSnap then
            Pix.DisablePixelSnap(rule)
        end
        return 40
    end

    local patches = CludesUI._WHATSNEW_PATCHES
    if not patches or #patches == 0 then
        local none = MakeFont(hostFrame, 13, nil, 1, 1, 1, 0.5)
        Pix.Point(none, "TOPLEFT", hostFrame, "TOPLEFT", PAD, posY - 20)
        none:SetText(CludesUI.L("No patch notes yet."))
        return math.abs(posY) + 60
    end

    -- Intro hint: centered, with 20px of breathing room above and below.
    posY = posY - 20
    local hint = MakeFont(hostFrame, 14, nil, 1, 1, 1, 0.5)
    Pix.Point(hint, "TOP", hostFrame, "TOP", 0, posY)
    hint:SetJustifyH("CENTER")
    hint:SetText(CludesUI.L("Click any new feature to go directly to the setting"))

    -- "New Patch Reminder Dot" opt-out for the pulsing sidebar dot shown when the account version increases (Patch Notes button in CludesUI.lua).
    do
        local BOX = 14
        local row = CreateFrame("Button", nil, hostFrame)
        row:SetFrameLevel(hostFrame:GetFrameLevel() + 2)
        local box = CreateFrame("Frame", nil, row)
        Pix.Size(box, BOX, BOX)
        Pix.Point(box, "LEFT", row, "LEFT", 0, 0)
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints()
        boxBg:SetColorTexture(0.088, 0.098, 0.111, 1)
        local boxBrd = CludesUI.MakeRoundedBorder(box, 1, 1, 1, 0.25, boxBg)
        local check = box:CreateTexture(nil, "ARTWORK")
        Pix.Point(check, "TOPLEFT", box, "TOPLEFT", 3, -3)
        Pix.Point(check, "BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
        CludesUI.RoundBody(box, check, 1)
        local labelFS = MakeFont(row, 12, nil, 1, 1, 1, 0.5)
        Pix.Point(labelFS, "LEFT", box, "RIGHT", 7, 0)
        labelFS:SetText(CludesUI.L("New Patch Reminder Dot"))
        row:SetSize(BOX + 10 + (labelFS:GetStringWidth() or 130), 20)
        Pix.Point(row, "TOPRIGHT", hostFrame, "TOPRIGHT", -PAD, posY + 2)
        local function Paint()
            local on = not (CludesUIDB and CludesUIDB.patchDotDisabled)
            check:SetShown(on)
            check:SetColorTexture(ACC.r, ACC.g, ACC.b, 1)
            if on then
                boxBrd:SetColor(ACC.r, ACC.g, ACC.b, 0.85)
            else
                boxBrd:SetColor(1, 1, 1, 0.25)
            end
        end
        Paint()
        OnAccent(check, function()
            Paint()
        end)
        row:SetScript("OnClick", function()
            if not CludesUIDB then
                CludesUIDB = {}
            end
            CludesUIDB.patchDotDisabled = (not CludesUIDB.patchDotDisabled) and true or nil
            Paint()
            if CludesUI._UpdatePatchDot then
                CludesUI._UpdatePatchDot()
            end
        end)
        row:SetScript("OnEnter", function(self)
            labelFS:SetAlpha(0.85)
            CludesUI.ShowWidgetTooltip(
                self,
                CludesUI.L(
                    "Show a pulsing dot on the Patch Notes button whenever CludesUI updates to a new version."
                )
            )
        end)
        row:SetScript("OnLeave", function()
            labelFS:SetAlpha(0.5)
            CludesUI.HideWidgetTooltip()
        end)
    end

    posY = posY - math.ceil(hint:GetStringHeight() or 14) - 20

    -- A patch card's content sits inset from the card's edges.
    local INSET = 16
    local innerX, innerW = PAD + INSET, totalW - INSET * 2

    -- One patch's tiers inside its open card, from cy down; returns the new cy.
    -- Text goes on a holder above the card's fill (frames already sit above it).
    local function BuildPatchContent(patch, cy)
        -- A "mini" patch is bugfix-only: just a `fixes` tier.
        local isMini = patch.mini
        local host = CreateFrame("Frame", nil, hostFrame)
        host:SetAllPoints(hostFrame)
        host:SetFrameLevel(hostFrame:GetFrameLevel() + 2)
        cy = cy - 6

        -- Tier 1: hero cards, two per row, AUTHORED order (not module-sorted like features/fixes) -- reorder entries in _WHATSNEW_PATCHES to reorder cards.
        local heroes = patch.heroes or {}
        if #heroes > 0 then
            local cardW = math.floor((innerW - CARD_GAP) / 2)
            local CARD_H = 96
            -- Column state: heroes flow 2/row in authored order; a `banner` hero takes a full row, breaking then resuming the flow.
            local col = 0
            for _, hero in ipairs(heroes) do
                if hero.banner then
                    if col == 1 then
                        cy = cy - CARD_H - CARD_GAP
                        col = 0
                    end
                    local bh = MakeBannerCard(innerX, cy, innerW, hero)
                    cy = cy - bh - CARD_GAP
                else
                    local cx = innerX + col * (cardW + CARD_GAP)
                    MakeHeroCard(cx, cy, cardW, CARD_H, hero)
                    col = col + 1
                    if col == 2 then
                        cy = cy - CARD_H - CARD_GAP
                        col = 0
                    end
                end
            end
            if col == 1 then
                cy = cy - CARD_H - CARD_GAP
            end
            cy = cy + CARD_GAP - 4
        end

        -- Tier 2: small listings.
        local feats = SortByModule(patch.features or {})
        if #feats > 0 then
            cy = cy - TierHeader(host, innerX, cy, innerW, CludesUI.L("ADDITIONAL FEATURES"))
            cy = cy - 5 -- extra spacing below the divider
            for _, f in ipairs(feats) do
                local rh = MakeListing(innerX, cy, innerW, f)
                cy = cy - rh
            end
            cy = cy - 6
        end

        -- Tier 3: bug-fix lines. Full patches get a "BUG FIXES" header; a fixes-only mini patch drops it (the whole block is fixes), but a mini that also lists features keeps it so the fixes do not run on under them.
        local fixes = SortByModule(patch.fixes or {})
        if #fixes > 0 then
            if not isMini or #feats > 0 then
                cy = cy - TierHeader(host, innerX, cy, innerW, CludesUI.L("BUG FIXES"))
                cy = cy - 10 -- extra spacing below the divider
            end
            for _, fx in ipairs(fixes) do
                local fh =
                    MakeFixLine(host, innerX, PAD + INSET, cy, PrefixOf(fx) .. (CludesUI.L(fx.text) or ""))
                cy = cy - fh
            end
        end
        return cy - 4
    end

    -- One card per patch, newest first: the newest starts open. Show only the
    -- newest MAX_PATCHES entries; older ones may stay in the data table unshown.
    local MAX_PATCHES = 10
    local isShown = math.min(#patches, MAX_PATCHES)
    local newestKey = patches[1].version or 1
    if whatsNewOpen[newestKey] == nil then
        whatsNewOpen[newestKey] = true
    end
    for pi = 1, isShown do
        local patch = patches[pi]
        -- Header counts: hero cards (a launch-video banner is no feature), listings, fix lines.
        local heroN = 0
        for _, hero in ipairs(patch.heroes or {}) do
            heroN = heroN + 1
        end
        local featN, fixN = #(patch.features or {}), #(patch.fixes or {})
        local parts = {}
        if patch.mini then
            parts[#parts + 1] = CludesUI.L("Mini Patch")
        end
        if heroN > 0 then
            parts[#parts + 1] = CludesUI.L("Major Features") .. ": " .. heroN
        end
        if featN > 0 then
            parts[#parts + 1] = CludesUI.L("Additional Features") .. ": " .. featN
        end
        if fixN > 0 then
            parts[#parts + 1] = CludesUI.L("Bug Fixes") .. ": " .. fixN
        end
        local tile = {
            key = patch.version or pi,
            display = "CludesUI " .. (patch.version or ""),
            desc = table.concat(parts, "    "),
            buildContent = function(_, cy)
                return BuildPatchContent(patch, cy)
            end,
        }
        local newest = pi == 1
        posY = CludesUI.BuildModuleCard(hostFrame, posY, W, tile, {
            enabled = true,
            expanded = whatsNewOpen,
            descW = 560,
            noSearch = true,
            glyph = function(heading)
                local icon = heading:CreateTexture(nil, "ARTWORK")
                Pix.Size(icon, 28, 20)
                Pix.Point(icon, "LEFT", heading, "LEFT", 14, 0)
                icon:SetTexture(NOTES_ICON)
                if Pix.DisablePixelSnap then
                    Pix.DisablePixelSnap(icon)
                end
                if newest then
                    icon:SetVertexColor(ACC.r, ACC.g, ACC.b, 0.9)
                    OnAccent(icon, function(r, g, b)
                        icon:SetVertexColor(r, g, b, 0.9)
                    end)
                else
                    icon:SetVertexColor(1, 1, 1, 0.45)
                end
            end,
        })
        -- "Latest" beside the newest card's title (its description hangs off the title).
        if newest then
            local _, title = tile._descFS:GetPoint(1)
            if title then
                local tag = MakeFont(tile._hdr, 11, nil, ACC.r, ACC.g, ACC.b, 0.9)
                OnAccent(tag, function(r, g, b)
                    tag:SetTextColor(r, g, b, 0.9)
                end)
                Pix.Point(tag, "LEFT", title, "RIGHT", 10, 0)
                tag:SetText(CludesUI.L("Latest"))
            end
        end
    end

    return math.abs(posY) + 20
end
