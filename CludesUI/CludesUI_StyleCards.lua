if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_StyleCards.lua
--
--  The three look cards (CludesUI Style, Blizzard Style, Classic WoW UI),
--  each with a miniature of what the look means, shared by the first-install
--  style picker (CludesUI_StyleChoicePopup.lua) and the header of Global
--  Settings > Style (CUI_Style_Options.lua). The WoW Forever client adds a
--  fourth pick card, WoW Forever. Builds frames only when called.
-------------------------------------------------------------------------------
local CUI = _G.CludesUI
if not CUI then return end

-- The options page pool's table (CludesUI_PixelPerfect.lua makes it, the
-- options addon fills it in place): each builder below takes CreateFrame from
-- it when it runs, so its frames are pooled on a pool host (the Style page)
-- and plain new frames anywhere else (the first-install picker).
local POOL = CUI._Pool

local GOLD_R, GOLD_G, GOLD_B = 1.0, 0.80, 0.18
local BRONZE_R, BRONZE_G, BRONZE_B = 0.86, 0.65, 0.42
local FOREVER_R, FOREVER_G, FOREVER_B = 0.47, 0.75, 0.95
-- The CludesUI card and its mock keep the stock #4CC9F0 teal (the
-- CludesUI theme preset) on every client, whatever accent colour the user
-- has picked.
local CUI_TEAL = CUI.THEME_PRESETS["CludesUI"]
local IS_FOREVER = CUI.IS_FOREVER == true
-- The vanilla frame sheet: the player frame samples it flipped (portrait on
-- the left); 193x77 of visible art at 1x.
local CLASSIC_FRAME = "Interface\\TargetingFrame\\UI-TargetingFrame"
local CLASSIC_EMPTY = "Interface\\Buttons\\UI-Quickslot"
local CLASSIC_FILL = "Interface\\TargetingFrame\\UI-StatusBar"
local CLASSIC_CAP = "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf"

local CARD_W, CARD_H, CARD_GAP = 212, 296, 16
-- Display cards (announcements) have no button: the caption is the last row.
local DISPLAY_CARD_H = 248
local MOCK_W, MOCK_H = 186, 118
CUI.STYLE_CARD_H = CARD_H
CUI.STYLE_CARD_DISPLAY_H = DISPLAY_CARD_H
-- The row of pick cards (four on the WoW Forever client), for callers that
-- size a host round it; display cards stay three.
local PICK_CARDS = IS_FOREVER and 4 or 3
CUI.STYLE_CARDS_W = PICK_CARDS * CARD_W + (PICK_CARDS - 1) * CARD_GAP

local function AtlasExists(name)
    return name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) and true or false
end

-------------------------------------------------------------------------------
--  CludesUI mock: a flat unit frame (teal health, blue power, a name
--  line) over a row of square icons -- the look in miniature.
-------------------------------------------------------------------------------
local function DrawCUIMock(stage, Pix, MakeBorder, teal)
    local CreateFrame = POOL.CreateFrame
    local widget = CreateFrame("Frame", nil, stage)
    widget:SetFrameLevel(stage:GetFrameLevel() + 1)
    Pix.Size(widget, 150, 40)
    Pix.Point(widget, "TOP", stage, "TOP", 0, -14)
    local fbg = widget:CreateTexture(nil, "BACKGROUND")
    fbg:SetAllPoints()
    fbg:SetColorTexture(0.088, 0.098, 0.111, 1)
    MakeBorder(widget, 0, 0, 0, 1, Pix)
    local health = widget:CreateTexture(nil, "ARTWORK")
    health:SetColorTexture(teal.r, teal.g, teal.b, 0.9)
    Pix.Point(health, "TOPLEFT", widget, "TOPLEFT", 1, -1)
    Pix.Size(health, 130, 27)
    local hrest = widget:CreateTexture(nil, "ARTWORK")
    hrest:SetColorTexture(teal.r, teal.g, teal.b, 0.2)
    Pix.Point(hrest, "TOPLEFT", health, "TOPRIGHT", 0, 0)
    Pix.Point(hrest, "BOTTOMRIGHT", widget, "TOPRIGHT", -1, -28)
    local power = widget:CreateTexture(nil, "ARTWORK")
    power:SetColorTexture(0.25, 0.5, 0.9, 0.9)
    Pix.Point(power, "TOPLEFT", widget, "TOPLEFT", 1, -29)
    Pix.Size(power, 104, 10)
    local prest = widget:CreateTexture(nil, "ARTWORK")
    prest:SetColorTexture(0.25, 0.5, 0.9, 0.2)
    Pix.Point(prest, "TOPLEFT", power, "TOPRIGHT", 0, 0)
    Pix.Point(prest, "BOTTOMRIGHT", widget, "BOTTOMRIGHT", -1, 1)
    local nameLine = widget:CreateTexture(nil, "OVERLAY")
    nameLine:SetColorTexture(1, 1, 1, 0.85)
    Pix.Size(nameLine, 50, 5)
    Pix.Point(nameLine, "TOPLEFT", widget, "TOPLEFT", 8, -11)
    local hpLine = widget:CreateTexture(nil, "OVERLAY")
    hpLine:SetColorTexture(1, 1, 1, 0.85)
    Pix.Size(hpLine, 24, 5)
    Pix.Point(hpLine, "TOPRIGHT", widget, "TOPRIGHT", -8, -11)

    local ICON, GAP, N = 24, 4, 5
    local rowW = N * ICON + (N - 1) * GAP
    for idx = 1, N do
        local ic = CreateFrame("Frame", nil, stage)
        ic:SetFrameLevel(stage:GetFrameLevel() + 1)
        Pix.Size(ic, ICON, ICON)
        Pix.Point(ic, "TOPLEFT", stage, "TOP", -rowW / 2 + (idx - 1) * (ICON + GAP), -70)
        local ibg = ic:CreateTexture(nil, "BACKGROUND")
        ibg:SetAllPoints()
        ibg:SetColorTexture(0.16 + idx * 0.03, 0.18, 0.2 + idx * 0.02, 1)
        MakeBorder(ic, 0, 0, 0, 1, Pix)
        if idx == 2 then
            local keyLine = ic:CreateTexture(nil, "OVERLAY")
            keyLine:SetColorTexture(teal.r, teal.g, teal.b, 0.9)
            Pix.Size(keyLine, ICON - 2, 2)
            Pix.Point(keyLine, "BOTTOMLEFT", ic, "BOTTOMLEFT", 1, 1)
        end
    end
end

-------------------------------------------------------------------------------
--  Blizzard mock: the stock player frame art with its health and mana
--  fills, over four rounded stock button slots flanked by retail's gryphon
--  end caps. Every atlas is validated; a missing one falls back to a plain
--  gold-framed box (or leaves its cap out) so the card never shows a blank
--  stage. forever: the WoW Forever card's base (its own art, its caps drawn
--  by DrawForeverMock). Returns the unit frame.
-------------------------------------------------------------------------------
local function DrawBlizzMock(stage, Pix, MakeBorder, _eg, _font, forever)
    local CreateFrame = POOL.CreateFrame
    local ART = "UI-HUD-UnitFrame-Player-PortraitOn"
    local HEALTH = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"
    local MANA = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana"
    local SLOT = "UI-HUD-ActionBar-IconFrame-Slot"
    local widget = CreateFrame("Frame", nil, stage)
    widget:SetFrameLevel(stage:GetFrameLevel() + 1)
    if AtlasExists(ART) then
        -- The 198x71 art at 0.78, its bars placed from the stock geometry
        -- (the bars sit at 85/40 and 85/61 in the 232x100 box whose art
        -- is centred with 17 and 14.5 of transparent margin).
        local s = 0.78
        Pix.Size(widget, 198 * s, 71 * s)
        Pix.Point(widget, "TOP", stage, "TOP", 0, -8)
        local art = widget:CreateTexture(nil, "ARTWORK", nil, 2)
        art:SetAllPoints()
        -- Plain Blizzard Style draws the retail art on WoW Forever too, as
        -- live (CludesUI.StockAtlas); the WoW Forever card keeps its own.
        if forever then
            art:SetAtlas(ART, false)
        else
            CUI.StockAtlas(art, ART, false)
        end
        if AtlasExists(HEALTH) then
            local hgt = widget:CreateTexture(nil, "ARTWORK", nil, 1)
            hgt:SetAtlas(HEALTH, false)
            Pix.Size(hgt, 124 * s * 0.82, 20 * s)
            Pix.Point(hgt, "TOPLEFT", widget, "TOPLEFT", (85 - 17) * s, -(40 - 14.5) * s)
        end
        if AtlasExists(MANA) then
            local m = widget:CreateTexture(nil, "ARTWORK", nil, 1)
            m:SetAtlas(MANA, false)
            Pix.Size(m, 124 * s * 0.6, 10 * s)
            Pix.Point(m, "TOPLEFT", widget, "TOPLEFT", (85 - 17) * s, -(61 - 14.5) * s)
        end
    else
        Pix.Size(widget, 150, 40)
        Pix.Point(widget, "TOP", stage, "TOP", 0, -14)
        local fbg = widget:CreateTexture(nil, "BACKGROUND")
        fbg:SetAllPoints()
        fbg:SetColorTexture(0.12, 0.10, 0.06, 1)
        MakeBorder(widget, GOLD_R, GOLD_G, GOLD_B, 0.8, Pix)
        local health = widget:CreateTexture(nil, "ARTWORK")
        health:SetColorTexture(0.1, 0.75, 0.1, 0.9)
        Pix.Point(health, "TOPLEFT", widget, "TOPLEFT", 3, -3)
        Pix.Size(health, 122, 20)
        local power = widget:CreateTexture(nil, "ARTWORK")
        power:SetColorTexture(0.1, 0.35, 0.9, 0.9)
        Pix.Point(power, "TOPLEFT", widget, "TOPLEFT", 3, -25)
        Pix.Size(power, 96, 12)
    end

    local ICON, GAP, N = 24, 4, 4
    local rowW = N * ICON + (N - 1) * GAP
    local slotOK = AtlasExists(SLOT)
    for idx = 1, N do
        local ic = CreateFrame("Frame", nil, stage)
        ic:SetFrameLevel(stage:GetFrameLevel() + 1)
        Pix.Size(ic, ICON, ICON)
        Pix.Point(ic, "TOPLEFT", stage, "TOP", -rowW / 2 + (idx - 1) * (ICON + GAP), -76)
        local tex = ic:CreateTexture(nil, "ARTWORK")
        if slotOK then
            if forever then
                tex:SetAtlas(SLOT, false)
            else
                CUI.StockAtlas(tex, SLOT, false)
            end
            Pix.Point(tex, "TOPLEFT", ic, "TOPLEFT", -3, 3)
            Pix.Point(tex, "BOTTOMRIGHT", ic, "BOTTOMRIGHT", 3, -3)
        else
            tex:SetAllPoints()
            tex:SetColorTexture(0.2, 0.17, 0.1, 1)
            MakeBorder(ic, GOLD_R, GOLD_G, GOLD_B, 0.6, Pix)
        end
    end
    -- Blizzard Style: retail's gryphon end caps (retail art on every client,
    -- at the live caps' 104.5x98), bottoms a little below the slots.
    if not forever then
        local CAP_H, OVERLAP = 28, 3
        for side = 1, 2 do
            local name = (side == 1) and "ui-hud-actionbar-gryphon-left" or "ui-hud-actionbar-gryphon-right"
            if AtlasExists(name) then
                local cap = CreateFrame("Frame", nil, stage)
                cap:SetFrameLevel(stage:GetFrameLevel() + 2)
                Pix.Size(cap, CAP_H * 104.5 / 98, CAP_H)
                if side == 1 then
                    Pix.Point(cap, "BOTTOMRIGHT", stage, "TOP", -rowW / 2 + OVERLAP, -104)
                else
                    Pix.Point(cap, "BOTTOMLEFT", stage, "TOP", rowW / 2 - OVERLAP, -104)
                end
                local tex = cap:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints()
                CUI.StockAtlas(tex, name, false)
            end
        end
    end
    return widget, rowW
end

-------------------------------------------------------------------------------
--  WoW Forever mock (that client only, where every stock atlas already draws
--  its Forever art): the Blizzard mock with the round level badge on the
--  player frame and the gryphon end caps flanking a four-slot bar. A missing
--  atlas just leaves its piece out.
-------------------------------------------------------------------------------
local function DrawForeverMock(stage, Pix, MakeBorder, ACC, font)
    local CreateFrame = POOL.CreateFrame
    local widget, rowW = DrawBlizzMock(stage, Pix, MakeBorder, ACC, font, true)
    -- Level badge: Blizzard's Forever spot is BOTTOMLEFT 13,7 of the 232x100
    -- box, i.e. -4,-7.5 off the centred art, at the mock's 0.78.
    local BADGE = "UI-HUD-UnitFrame-SmallCircle"
    if AtlasExists(BADGE) then
        local bf = CreateFrame("Frame", nil, stage)
        bf:SetFrameLevel(stage:GetFrameLevel() + 2)
        Pix.Size(bf, 24, 24)
        Pix.Point(bf, "BOTTOMLEFT", widget, "BOTTOMLEFT", -3, -6)
        local disc = bf:CreateTexture(nil, "ARTWORK")
        disc:SetAllPoints()
        disc:SetAtlas(BADGE, false)
        local lvl = bf:CreateFontString(nil, "OVERLAY")
        lvl:SetFont(font, 10, "")
        lvl:SetTextColor(1, 1, 1, 1)
        Pix.Point(lvl, "CENTER", bf, "CENTER", 0, 0)
        lvl:SetText("60")
    end
    -- Gryphon end caps at their own aspect, bottoms level with the slots,
    -- each overlapping the bar's end by a few pixels.
    local CAP_H, OVERLAP = 26, 8
    for side = 1, 2 do
        local name = (side == 1) and "ui-hud-actionbar-gryphon-left" or "ui-hud-actionbar-gryphon-right"
        local details = C_Texture.GetAtlasInfo(name)
        if details and details.width and details.height and details.height > 0 then
            local cap = CreateFrame("Frame", nil, stage)
            cap:SetFrameLevel(stage:GetFrameLevel() + 2)
            Pix.Size(cap, CAP_H * details.width / details.height, CAP_H)
            if side == 1 then
                Pix.Point(cap, "BOTTOMRIGHT", stage, "TOP", -rowW / 2 + OVERLAP, -102)
            else
                Pix.Point(cap, "BOTTOMLEFT", stage, "TOP", rowW / 2 - OVERLAP, -102)
            end
            local tex = cap:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetAtlas(name, false)
        end
    end
end

-------------------------------------------------------------------------------
--  Classic mock: the vanilla player frame sheet (193x77 of art, sampled
--  flipped so the portrait sits on the left) with its health and mana
--  bars at the vanilla spots and the level in its ring, over four vanilla
--  empty slots flanked by the vanilla gryphon end caps. Plain files, so
--  nothing needs validating.
-------------------------------------------------------------------------------
local function DrawClassicMock(stage, Pix, _mb, _eg, font)
    local CreateFrame = POOL.CreateFrame
    local s = 0.78
    local widget = CreateFrame("Frame", nil, stage)
    widget:SetFrameLevel(stage:GetFrameLevel() + 1)
    Pix.Size(widget, 193 * s, 77 * s)
    Pix.Point(widget, "TOP", stage, "TOP", 0, -6)
    -- Bars under the art: the art's tracks are transparent windows. Box
    -- coordinates (232x100) minus the art's centring offset (19.5, 11.5).
    local health = widget:CreateTexture(nil, "ARTWORK", nil, 1)
    health:SetTexture(CLASSIC_FILL)
    health:SetVertexColor(0.0, 0.8, 0.0)
    Pix.Size(health, 119 * s * 0.82, 12 * s)
    Pix.Point(health, "TOPLEFT", widget, "TOPLEFT", (90 - 19.5) * s, -(45 - 11.5) * s)
    local hrest = widget:CreateTexture(nil, "ARTWORK", nil, 1)
    hrest:SetColorTexture(0, 0, 0, 0.5)
    Pix.Point(hrest, "TOPLEFT", health, "TOPRIGHT", 0, 0)
    Pix.Size(hrest, 119 * s * 0.18, 12 * s)
    local mana = widget:CreateTexture(nil, "ARTWORK", nil, 1)
    mana:SetTexture(CLASSIC_FILL)
    mana:SetVertexColor(0.0, 0.0, 1.0)
    Pix.Size(mana, 119 * s * 0.6, 12 * s)
    Pix.Point(mana, "TOPLEFT", widget, "TOPLEFT", (90 - 19.5) * s, -(56 - 11.5) * s)
    local mrest = widget:CreateTexture(nil, "ARTWORK", nil, 1)
    mrest:SetColorTexture(0, 0, 0, 0.5)
    Pix.Point(mrest, "TOPLEFT", mana, "TOPRIGHT", 0, 0)
    Pix.Size(mrest, 119 * s * 0.4, 12 * s)
    local art = widget:CreateTexture(nil, "ARTWORK", nil, 2)
    art:SetTexture(CLASSIC_FRAME)
    art:SetTexCoord(0.85546875, 0.1015625, 0.0625, 0.6640625)
    art:SetAllPoints(widget)
    -- Level in the ring by the portrait: vanilla's PlayerLevelText sits CENTER
    -- at BOTTOMLEFT 35.25,30 of the 232x100 box.
    local lvl = widget:CreateFontString(nil, "OVERLAY")
    lvl:SetFont(font, 9, "")
    lvl:SetTextColor(1, 0.82, 0, 1)
    Pix.Point(lvl, "CENTER", widget, "TOPLEFT", (35.25 - 19.5) * s, -(70 - 11.5) * s)
    lvl:SetText("60")

    local ICON, GAP, N = 24, 4, 4
    local rowW = N * ICON + (N - 1) * GAP
    for idx = 1, N do
        local ic = CreateFrame("Frame", nil, stage)
        ic:SetFrameLevel(stage:GetFrameLevel() + 1)
        Pix.Size(ic, ICON, ICON)
        Pix.Point(ic, "TOPLEFT", stage, "TOP", -rowW / 2 + (idx - 1) * (ICON + GAP), -76)
        -- The vanilla empty slot: 66/36 of the button, a pixel low.
        local slot = ic:CreateTexture(nil, "ARTWORK")
        slot:SetTexture(CLASSIC_EMPTY)
        Pix.Size(slot, ICON * 66 / 36, ICON * 66 / 36)
        Pix.Point(slot, "CENTER", ic, "CENTER", 0, -ICON / 36)
    end
    -- Vanilla's gryphon end caps (one file, the right one mirrored), bottoms a
    -- little below the slots, each overlapping the bar's end.
    local CAP, OVERLAP = 36, 8
    for side = 1, 2 do
        local cap = CreateFrame("Frame", nil, stage)
        cap:SetFrameLevel(stage:GetFrameLevel() + 2)
        Pix.Size(cap, CAP, CAP)
        if side == 1 then
            Pix.Point(cap, "BOTTOMRIGHT", stage, "TOP", -rowW / 2 + OVERLAP, -102)
        else
            Pix.Point(cap, "BOTTOMLEFT", stage, "TOP", rowW / 2 - OVERLAP, -102)
        end
        local tex = cap:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(CLASSIC_CAP)
        if side == 2 then tex:SetTexCoord(1, 0, 0, 1) end
    end
end

-------------------------------------------------------------------------------
--  CludesUI.BuildStyleCards(parent, topY, opts) -> handles
--
--  Three cards in a row (four pick cards on the WoW Forever client,
--  CludesUI.STYLE_CARDS_W wide), centred on parent's centre line, their
--  tops topY below parent's TOP. Each card is one click target: the whole
--  card and its button pick that style, and hover lights the card in its own
--  colour. opts:
--    onPick(styleKey)  called on a pick ("cui" | "blizzard" | "classic",
--                      or "forever" on the WoW Forever client)
--    buttonText        a string for every card, or a table keyed by style
--    display           true: announcement cards -- no button, no click or
--                      hover, DISPLAY_CARD_H tall (onPick/buttonText unused)
--    defaultKey        the pick card tagged DEFAULT (nil or "cui" = the
--                      CludesUI card); the order stays, CludesUI first
--    inUseAlpha        the card's opacity while it is IN USE (1); its
--                      badge stays whole
--    badgeSize         the IN USE badge's font size (11)
--  Returns a table keyed by style; handle:SetState(inUse, pickable, label)
--  keeps a card lit with an IN USE badge, and dims its button (picks then do
--  nothing) with an optional label while it has nothing to apply.
-------------------------------------------------------------------------------
function CUI.BuildStyleCards(hostFrame, topY, options)
    local CreateFrame = POOL.CreateFrame
    local Pix = CUI.PanelPP
    local MakeBorder = CUI.MakeBorder
    if not (Pix and MakeBorder) then return nil end
    local L = CUI.L or function(s) return s end
    -- The options font once it has loaded, else the locale-aware core font
    -- (the picker runs before the options addon loads).
    local FONT = CUI._font or CUI.EXPRESSWAY or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
    options = options or {}

    local DEFS = {
        {
            key = "cui",
            r = CUI_TEAL.r,
            g = CUI_TEAL.g,
            b = CUI_TEAL.b,
            title = "CludesUI Style",
            tag = "DEFAULT",
            caption = "Flat, clean and modern. The look CludesUI was designed around.",
            draw = DrawCUIMock,
        },
        {
            key = "blizzard",
            r = GOLD_R,
            g = GOLD_G,
            b = GOLD_B,
            title = "Blizzard Style",
            tag = "BLIZZARD ART",
            caption = "Blizzard's own frame and button art, with CludesUI's features.",
            draw = DrawBlizzMock,
        },
        {
            key = "classic",
            r = BRONZE_R,
            g = BRONZE_G,
            b = BRONZE_B,
            title = "Classic WoW UI",
            tag = "VANILLA ART",
            caption = "The original frames, rings and slots where the game has them, with CludesUI's features.",
            draw = DrawClassicMock,
        },
    }

    local display = options.display == true
    local inUseAlpha = options.inUseAlpha or 1
    -- WoW Forever: its own pick card on that client, second in the row (the
    -- announcement cards never show there).
    if IS_FOREVER and not display then
        table.insert(DEFS, 2, {
            key = "forever",
            r = FOREVER_R,
            g = FOREVER_G,
            b = FOREVER_B,
            title = "WoW Forever",
            tag = "FOREVER ART",
            caption = "Forever's bronze frames, gryphons and round badges, with CludesUI's features.",
            draw = DrawForeverMock,
        })
    end
    -- Another default look: its card takes the DEFAULT tag where it stands,
    -- so the CludesUI card still leads the row.
    local dk = options.defaultKey
    if dk and dk ~= "cui" and not display then
        for idx = 2, #DEFS do
            if DEFS[idx].key == dk then
                DEFS[1].tag = "FLAT & MODERN"
                DEFS[idx].tag = "DEFAULT"
                break
            end
        end
    end
    local mid = (#DEFS + 1) / 2
    local handles = {}
    for index, def in ipairs(DEFS) do
        local accentR, accentG, accentB = def.r, def.g, def.b
        local cardFrame = CreateFrame(display and "Frame" or "Button", nil, hostFrame)
        cardFrame:SetFrameLevel(hostFrame:GetFrameLevel() + 1)
        Pix.Size(cardFrame, CARD_W, display and DISPLAY_CARD_H or CARD_H)
        Pix.Point(cardFrame, "TOP", hostFrame, "TOP", (index - mid) * (CARD_W + CARD_GAP), topY)
        -- Accent band along the top edge: the colour is the first indicator.
        local brd = CUI.MakeRoundedCard(cardFrame, 0.14, 1, 3, 0.088, 0.098, 0.111)
        brd.accent:SetColorTexture(accentR, accentG, accentB, 0.9)

        local ct = cardFrame:CreateFontString(nil, "OVERLAY")
        ct:SetFont(FONT, 17, "")
        ct:SetTextColor(accentR, accentG, accentB, 1)
        Pix.Point(ct, "TOP", cardFrame, "TOP", 0, -16)
        ct:SetText(L(def.title))

        -- Small tag under the title (DEFAULT / BLIZZARD ART).
        local tagFS = cardFrame:CreateFontString(nil, "OVERLAY")
        tagFS:SetFont(FONT, 11, "")
        tagFS:SetTextColor(accentR, accentG, accentB, 0.7)
        Pix.Point(tagFS, "TOP", ct, "BOTTOM", 0, -3)
        tagFS:SetText(L(def.tag))

        -- IN USE badge just above the card (clear of the centred title),
        -- shown by SetState. Drawn on the parent, so the card's IN USE
        -- alpha leaves it whole.
        local badge = hostFrame:CreateFontString(nil, "OVERLAY")
        badge:SetFont(FONT, options.badgeSize or 11, "")
        badge:SetTextColor(accentR, accentG, accentB, 1)
        Pix.Point(badge, "BOTTOM", cardFrame, "TOP", 0, 6)
        badge:SetText(L("IN USE"))
        badge:Hide()

        -- Mock area: a dark stage the style mock is drawn on.
        local stage = CreateFrame("Frame", nil, cardFrame)
        stage:SetFrameLevel(cardFrame:GetFrameLevel() + 1)
        Pix.Size(stage, MOCK_W, MOCK_H)
        Pix.Point(stage, "TOP", tagFS, "BOTTOM", 0, -12)
        local sbg = stage:CreateTexture(nil, "BACKGROUND")
        sbg:SetAllPoints()
        sbg:SetColorTexture(0.051, 0.040, 0.030, 1)
        MakeBorder(stage, 1, 1, 1, 0.08, Pix)
        def.draw(stage, Pix, MakeBorder, CUI_TEAL, FONT)

        local cap = cardFrame:CreateFontString(nil, "OVERLAY")
        cap:SetFont(FONT, 12, "")
        cap:SetTextColor(1, 1, 1, 0.7)
        cap:SetWidth(CARD_W - 28)
        cap:SetJustifyH("CENTER")
        cap:SetWordWrap(true)
        -- Three lines fit between the stage and the button; a longer wrap
        -- (wider fallback font) is cut rather than run into the button.
        if cap.SetMaxLines then cap:SetMaxLines(3) end
        Pix.Point(cap, "TOP", stage, "BOTTOM", 0, -10)
        cap:SetText(L(def.caption))

        if display then
            -- Announcement card: nothing to press, only an IN USE state.
            handles[def.key] = {
                card = cardFrame,
                SetState = function(_, isInUse)
                    local enabled = isInUse and true or false
                    badge:SetShown(enabled)
                    cardFrame:SetAlpha(enabled and inUseAlpha or 1)
                    if enabled then
                        brd:SetColor(accentR, accentG, accentB, 0.9)
                    else
                        brd:SetColor(1, 1, 1, 0.14)
                    end
                end,
            }
        else
            local button = CreateFrame("Button", nil, cardFrame)
            button:SetFrameLevel(cardFrame:GetFrameLevel() + 2)
            Pix.Size(button, CARD_W - 32, 34)
            Pix.Point(button, "BOTTOM", cardFrame, "BOTTOM", 0, 14)
            local bbg = button:CreateTexture(nil, "BACKGROUND")
            bbg:SetAllPoints()
            local bbrd = CUI.MakeRoundedBorder(button, accentR, accentG, accentB, 0.8, bbg)
            local labelFS = button:CreateFontString(nil, "OVERLAY")
            labelFS:SetFont(FONT, 14, "")
            Pix.Point(labelFS, "CENTER", button, "CENTER", 0, 0)
            local bt = options.buttonText
            local btnText = (type(bt) == "table" and bt[def.key]) or (type(bt) == "string" and bt) or ""
            labelFS:SetText(L(btnText))

            local inUse, pickable, hovered = false, true, false
            local function PaintCard()
                local lit = inUse or (hovered and pickable)
                if lit then
                    brd:SetColor(accentR, accentG, accentB, 0.9)
                else
                    brd:SetColor(1, 1, 1, 0.14)
                end
                if not pickable then
                    bbg:SetColorTexture(accentR, accentG, accentB, 0.06)
                    bbrd:SetColor(accentR, accentG, accentB, 0.35)
                    labelFS:SetTextColor(1, 1, 1, 0.45)
                elseif hovered then
                    bbg:SetColorTexture(accentR, accentG, accentB, 0.28)
                    bbrd:SetColor(accentR, accentG, accentB, 1)
                    labelFS:SetTextColor(1, 1, 1, 0.95)
                else
                    bbg:SetColorTexture(accentR, accentG, accentB, 0.12)
                    bbrd:SetColor(accentR, accentG, accentB, 0.8)
                    labelFS:SetTextColor(1, 1, 1, 0.95)
                end
            end
            local function Enter()
                hovered = true
                PaintCard()
            end
            local function Leave()
                hovered = false
                PaintCard()
            end
            local function Pick()
                if pickable and options.onPick then options.onPick(def.key) end
            end
            cardFrame:SetScript("OnEnter", Enter)
            cardFrame:SetScript("OnLeave", Leave)
            cardFrame:SetScript("OnClick", Pick)
            button:SetScript("OnEnter", Enter)
            button:SetScript("OnLeave", Leave)
            button:SetScript("OnClick", Pick)
            PaintCard()

            handles[def.key] = {
                card = cardFrame,
                SetState = function(_, isInUse, canPick, labelText)
                    inUse, pickable = isInUse and true or false, canPick ~= false
                    badge:SetShown(inUse)
                    cardFrame:SetAlpha(inUse and inUseAlpha or 1)
                    labelFS:SetText(L(labelText or btnText))
                    PaintCard()
                end,
            }
        end
    end
    return handles
end
