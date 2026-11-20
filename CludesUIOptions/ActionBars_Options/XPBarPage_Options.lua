if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ActionBars_Options\XPBarPage_Options.lua
--  Action Bars options: the XP Bar page (BuildXPBarPage), in CORE, CORE TEXT
--  POSITIONS and DISPLAY sections. The data bar controls it shares with the
--  reputation and House Favor bars come from the data bar kit
--  (ns.ABO_DataBarKit, defined in MenuBagsRepPage_Options.lua and read at
--  build time); this file holds the XP bar's own: XP Bar Style, Show Dividers
--  and its settings row, Fill Style, Rested Color, Background, Quest XP
--  Overlay and its cog, the bar's texts (a list of the ones that show
--  something: what each shows, the position it sits at, its Size, offsets
--  and Show Rested cog; Add Text Slot), Text Background and the Visibility
--  cog (with Click Through). Definitions only; the shared helpers come from
--  ns._ABO_OptEnv (filled by CUI_ActionBars_Options.lua).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIActionBars"]
if not mod then
    return
end -- module disabled: no options page
-- Options page pool (CludesUI_FramePool.lua, first in this addon): a frame
-- made here on a pool host (a kept page and every frame it hands out) is reset
-- and dressed again by the next build instead of made anew; on any other
-- parent this is CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

local XP = "XPBar"

-- The profession skill-bar flipbooks Fill Style can offer (atlas, label).
local FLIP_CANDS = {
    { "Skillbar_Fill_Flipbook_Alchemy", "Alchemy" },
    { "Skillbar_Fill_Flipbook_Blacksmithing", "Blacksmithing" },
    { "Skillbar_Fill_Flipbook_Enchanting", "Enchanting" },
    { "Skillbar_Fill_Flipbook_Engineering", "Engineering" },
    { "Skillbar_Fill_Flipbook_Herbalism", "Herbalism" },
    { "Skillbar_Fill_Flipbook_Inscription", "Inscription" },
    { "Skillbar_Fill_Flipbook_Jewelcrafting", "Jewelcrafting" },
    { "Skillbar_Fill_Flipbook_Leatherworking", "Leatherworking" },
    { "Skillbar_Fill_Flipbook_Mining", "Mining" },
    { "Skillbar_Fill_Flipbook_Skinning", "Skinning" },
    { "Skillbar_Fill_Flipbook_Tailoring", "Tailoring" },
    { "Skillbar_Fill_Flipbook_Cooking", "Cooking" },
    { "Skillbar_Fill_Flipbook_Fishing", "Fishing" },
}

-- What a text can show (the bar reads a text's value through ns.XPTextItems):
-- the top items combine, " - " between them in the order dragged; a bottom
-- item shows on its own.
local TOP_ITEMS = {
    { key = "pct", label = "Current %" },
    { key = "cur", label = "Current" },
    { key = "curMax", label = "Current / Max" },
    { key = "curMaxRem", label = "Current / Max (Remaining)" },
    { key = "restVal", label = "Rested" },
    { key = "restPct", label = "Rested %" },
    { key = "questVal", label = "Completed Quests" },
    { key = "questPct", label = "Completed Quests %" },
    { key = "level", label = "Level" },
}
local SOLO_ITEMS = {
    { key = "xpPerHour", label = "XP per Hour" },
    { key = "levelingIn", label = "Leveling In" },
    { key = "timeLevel", label = "Time This Level" },
    { key = "timeSession", label = "Time This Session" },
}
local ITEM_LABEL = {}
for _, list in ipairs({ TOP_ITEMS, SOLO_ITEMS }) do
    for _, it in ipairs(list) do
        ITEM_LABEL[it.key] = it.label
    end
end
-- Show Rested adds the rested XP after the first of these in a text.
local RESTED_ITEM = { pct = true, cur = true, curMax = true }
-- The text Add Text Slot just wrote (its key), across the rebuild it causes:
-- the new text's row reports the write to Spec Overrides once it exists.
local addedKey

---------------------------------------------------------------------------
--  XP Bar page  (dedicated tab)
--    CORE            XP Bar Style | Visibility, Width | Height, Show
--                    Dividers | Orientation (and 5% Line Style | Divider
--                    Text while dividers are on)
--    CORE TEXT POSITIONS  one slot per text that shows something (two to
--                    a row), then Add Text Slot
--    DISPLAY         Text Size | Text Background, Border Style | Border
--                    Size (and the offsets of a textured style), Fill
--                    Style | Rested Color, Background | Bar Texture,
--                    Quest XP Overlay
--  While the bar's visibility is Never only the first row is built.
---------------------------------------------------------------------------

---------------------------------------------------------------------------
--  Header preview: the XP bar as the live bar draws it (ns.StyleDataBarFrame,
--  ns.PaintXPFill and ns.PaintXPText on a frame of its own, never the live
--  bar) at sample values: 62% XP, 20% rested, and for the Quest XP Overlay 5%
--  completed and 10% incomplete. Shown while the bar is ours and not Never;
--  ns.ApplyDataBarLayout repaints it. Built once and hung into each new
--  header (a header rebuild drops frames the page pool does not own).
---------------------------------------------------------------------------
local PV_MAX = 125000
local PV_CUR, PV_RESTED = PV_MAX * 0.62, PV_MAX * 0.2
local PV_QDONE, PV_QINC = PV_MAX * 0.05, PV_MAX * 0.1
local PV_PAD = 15 -- header margin above and below the drawn bar and texts
local PV_BAR_H = 120 -- the tallest bar drawn (a vertical bar shrinks to it)
local PV_MAX_H = 200 -- the tallest bar and texts drawn together
-- frame, hdrW, h; pageWanted: the page on screen was built with a preview;
-- retry: a repaint queued for a rect not resolved yet
local preview = {}
local XPPreviewRepaint -- forward: the queued retry calls it

-- As the page's Never gating (K.BarIsNever, after GetVisibilityKey
-- normalizes legacy settings) and the live bar's XPBarCanShow switches.
local function XPPreviewWanted()
    local environ = mod._ABO_OptEnv
    local p = environ.EAB.db.profile
    local s = p.bars[XP]
    if not s or p.useBlizzardDataBars or s.enabled == false then
        return false
    end
    return environ.GetVisibilityKey(s) ~= "never" and not s.alwaysHidden
end

-- One text's reach past each of the bar's edges (l r t b), its Text
-- Background box when that shows (it encloses the text), folded into the
-- running maxima.
local function XPPreviewReach(fontStr, backdrop, l, r, t, b, oL, oR, oT, oB)
    if not (fontStr:IsShown() and (fontStr:GetText() or "") ~= "") then
        return oL, oR, oT, oB
    end
    local region = (backdrop and backdrop:IsShown()) and backdrop or fontStr
    local rl = region:GetLeft()
    if not rl then
        return oL, oR, oT, oB
    end
    return math.max(oL, l - rl),
        math.max(oR, region:GetRight() - r),
        math.max(oT, region:GetTop() - t),
        math.max(oB, b - region:GetBottom())
end

-- How far the shown texts reach past the bar's left, right, top and bottom
-- edges (frame units): texts can sit outside the bar. A rotated Center text
-- is placed inside the bar, and its region is the unrotated string's, so it
-- is left out. nil while the frame's rect is not resolved yet.
local function XPPreviewOverhang(f)
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not l then
        return nil
    end
    local oL, oR, oT, oB = 0, 0, 0, 0
    if not f._textRotated then
        oL, oR, oT, oB = XPPreviewReach(f._text, f._textBg, l, r, t, b, oL, oR, oT, oB)
    end
    local recs = f._xpAny and f._xpRecs
    if recs then
        for i = 1, #recs do
            oL, oR, oT, oB = XPPreviewReach(recs[i].fs, recs[i].bg, l, r, t, b, oL, oR, oT, oB)
        end
    end
    return oL, oR, oT, oB
end

-- The queued measurement (pv.retry while queued). Its own paint does not
-- queue again when the rect is still unresolved; every other paint may.
local function XPPreviewRetry()
    preview.retry = nil
    XPPreviewRepaint(false, false, true)
end

-- Scales the preview to UIParent's scale (shrunk so the bar and its texts
-- fit the header's width and PV_MAX_H), centres bar and texts together,
-- paints it and returns the header height. The scale is taken from the
-- frame's parent: a cache restore moves the header's frames to another root.
-- A rect not resolved yet (a header just built) is measured again on the
-- next frame.
-- Styles and paints the preview at its current scale (the PP snapping in
-- the style pass reads it).
local function XPPreviewStyle(f, s)
    mod.StyleDataBarFrame(f, s)
    f._xpQuestXP, f._xpQuestDone, f._xpQuestInc = PV_QDONE, PV_QDONE, PV_QINC
    mod.PaintXPFill(f, s, PV_CUR, PV_MAX, PV_RESTED)
    mod.PaintXPText(f, s, nil, PV_CUR, PV_MAX, PV_RESTED, UnitLevel("player"))
end

-- The scale factor that fits the bar (w x h) and an overhang (frame units)
-- into availW across, PV_BAR_H for the bar and PV_MAX_H with its texts.
local function XPPreviewFit(availW, wid, height, scale, oL, oR, oT, oB)
    return math.min(
        1,
        availW / ((wid + oL + oR) * scale),
        PV_BAR_H / (height * scale),
        PV_MAX_H / ((height + oT + oB) * scale)
    )
end

local function XPPreviewPaint(noRetry)
    local s = mod._ABO_OptEnv.EAB.db.profile.bars[XP]
    local f = preview.frame
    local hostFrame = f:GetParent()
    local wid, height = s.width or 400, s.height or 18
    local scale = UIParent:GetEffectiveScale() / hostFrame:GetEffectiveScale()
    -- The header's width now (a resized panel), else the one it was built at.
    local hdrW = hostFrame:GetWidth()
    if not hdrW or hdrW <= 0 then
        hdrW = preview.hdrW
    end
    local availW = hdrW - CludesUI.CONTENT_PAD * 2
    -- Started from the last paint's overhang, so an unchanged layout styles
    -- once; a different one is styled again at its own scale, so its 1px
    -- lines snap to it (texts keep their frame-unit places across a rescale).
    local fit = XPPreviewFit(availW, wid, height, scale, preview.oL or 0, preview.oR or 0, preview.oT or 0, preview.oB or 0)
    f:SetScale(scale * fit)
    XPPreviewStyle(f, s)
    local oL, oR, oT, oB = XPPreviewOverhang(f)
    if oL then
        preview.oL, preview.oR, preview.oT, preview.oB = oL, oR, oT, oB
    else
        oL, oR, oT, oB = 0, 0, 0, 0
        if not (preview.retry or noRetry) then
            preview.retry = true
            C_Timer.After(0, XPPreviewRetry)
        end
    end
    local fit2 = XPPreviewFit(availW, wid, height, scale, oL, oR, oT, oB)
    if math.abs(fit2 - fit) > 0.001 then
        fit = fit2
        f:SetScale(scale * fit)
        XPPreviewStyle(f, s)
    end
    local fullH = height + oT + oB
    f:ClearAllPoints()
    mod._ABO_OptEnv.PP.Point(f, "CENTER", hostFrame, "CENTER", (oL - oR) / 2, (oB - oT) / 2)
    return math.floor(fullH * scale * fit + PV_PAD * 2 + 0.5)
end

-- Repaints a shown preview and fits the header to it. valueOnly: only the
-- fill changed (a colour), so the layout and texts are left as they are.
-- force: the header height is written even when unchanged (a restored
-- header comes back at its cached height). noRetry: the queued measurement.
XPPreviewRepaint = function(valueOnly, force, noRetry)
    local f = preview.frame
    if not (f and f:IsVisible()) then
        return
    end
    if valueOnly then
        mod.PaintXPFill(f, mod._ABO_OptEnv.EAB.db.profile.bars[XP], PV_CUR, PV_MAX, PV_RESTED)
        return
    end
    local height = XPPreviewPaint(noRetry)
    if force or height ~= preview.h then
        preview.h = height
        CludesUI:SetContentHeaderHeightSilent(height)
    end
end

local function XPHeaderBuilder(heading, hdrW)
    -- Every header root sits at the content header's own level
    -- (SetContentHeader), so the levels the frame set up when built (text
    -- host, border) hold in each header it moves into.
    local f = preview.frame
    if not f then
        f = mod.CreateXPBarFrame(nil, heading)
        preview.frame = f
    else
        f:SetParent(heading)
    end
    f:ClearAllPoints()
    mod._ABO_OptEnv.PP.Point(f, "CENTER", heading, "CENTER", 0, 0)
    f:Show()
    preview.hdrW = hdrW
    preview.h = XPPreviewPaint()
    return preview.h
end

-- The header for the XP Bar page (nil: none), also for getHeaderBuilder.
function mod.ABO_XPHeaderBuilder()
    return XPPreviewWanted() and XPHeaderBuilder or nil
end

-- A cached page shown again: its header comes back as it was cached. A page
-- built with the other answer (its rows gated by Never too) is built again
-- with its header (the panel has no hook before its own restore, and the
-- answer changes only with Blizzard's bars or Never set elsewhere);
-- otherwise the preview is repainted.
function mod.ABO_XPPreviewRefresh()
    -- nil: no shown build recorded one (only a shown build runs the header
    -- builder), so there is no preview to compare against: repaint only.
    if preview.pageWanted ~= nil and XPPreviewWanted() ~= preview.pageWanted then
        CludesUI:RefreshPage(true)
    else
        XPPreviewRepaint(false, true)
    end
end

-- ns.RefreshDataBarPreview calls this after the live bar's layout or value
-- update (valueOnly).
mod._dataBarPreview = mod._dataBarPreview or {}
mod._dataBarPreview[XP] = XPPreviewRepaint

local function BuildXPBarPage(page, hostFrame, yOffset)
    local ABAR = mod._ABO_OptEnv.EAB
    local W = CludesUI.Widgets
    local K = mod.ABO_DataBarKit(hostFrame)
    local BLIZZ_DIS_TIP, _blizzDis = K.BLIZZ_DIS_TIP, K.BlizzDis
    local function S()
        return ABAR.db.profile.bars[XP]
    end
    local function Vertical()
        return S().orientation == "VERTICAL"
    end
    -- Row chrome (frames: never on the search pre-build's absorber rows).
    local chrome = not CludesUI._prebuilding
    local cursorY = yOffset
    local _, height, heading

    -- The preview header while the bar is ours and not Never (a style or
    -- Never flip rebuilds the page); no bar selector.
    local hb = mod.ABO_XPHeaderBuilder()
    if not CludesUI._prebuilding then
        preview.pageWanted = hb ~= nil
    end
    if hb then
        CludesUI:SetContentHeader(hb)
    else
        CludesUI:ClearContentHeader()
    end
    hostFrame._showRowDivider = true

    -------------------------------------------------------------------
    --  CORE
    -------------------------------------------------------------------
    heading, height = W:SectionHeader(hostFrame, "CORE", cursorY)
    cursorY = cursorY - height
    -- The Move in Unlock Mode button on the bar's first section: greyed while
    -- Blizzard's bars are in use, since our bar (and its mover) is not built then.
    CludesUI.BuildSectionUnlockJump(
        heading,
        { key = "XPBar", disabled = _blizzDis, disabledTooltip = BLIZZ_DIS_TIP, rawTooltip = true }
    )

    -- XP Bar Style: the CludesUI bar, plain, in the profession frame art or
    -- in WoW Forever's border (Forever: the chat and Damage Meters border,
    -- offered only on that client), or Blizzard's own bar. Blizz Default is
    -- the one saved switch for Blizzard's XP, reputation and House Favor bars,
    -- shared with Use Blizzard's Rep Bars (Menu, Bags & Rep Bars).
    local styleValues = { cui = "CludesUI", prof = "Professions", default = "Blizz Default" }
    local styleOrder = { "cui", "prof" }
    if CludesUI._XPBarArtAvailable("forever") then
        styleValues.forever = "Forever"
        styleOrder[#styleOrder + 1] = "forever"
    end
    styleOrder[#styleOrder + 1] = "default"
    -- The setting has no tooltip of its own: Blizz Default explains itself
    -- while hovered in the menu.
    styleValues._menuOpts = {
        onItemHover = function(key, entry)
            if key == "default" and entry then
                CludesUI.ShowWidgetTooltip(
                    entry,
                    "Blizz Default also switches the reputation bars to Blizzard's."
                )
            end
        end,
        onItemLeave = function(key)
            if key == "default" then
                CludesUI.HideWidgetTooltip()
            end
        end,
    }
    -- XP Bar Style | Visibility (its cog: Click Through); a Never flip
    -- rebuilds the page.
    local visOpts = K.VisOpts(XP, "Visibility", _blizzDis, BLIZZ_DIS_TIP, true)
    visOpts.leftCfg = {
        type = "dropdown",
        text = "XP Bar Style",
        values = styleValues,
        order = styleOrder,
        -- A frame art this client lacks shows as the CludesUI bar it draws.
        getValue = function()
            local val = CludesUI._GetXPBarStyle()
            return styleValues[val] and val or "cui"
        end,
        setValue = function(val)
            K.AfterSwitch(CludesUI._SetXPBarStyle(val))
        end,
    }
    local visRow
    visRow, height = CludesUI.BuildVisibilityRow(W, hostFrame, cursorY, visOpts)
    cursorY = cursorY - height
    if chrome then
        local region = visRow._rightRegion
        CludesUI.BuildInlineCog(region, {
            title = "Visibility",
            anchorTo = region._control,
            rows = { K.ClickThroughRow(XP) },
        })
    end
    -- Rows below are hidden while visibility is Never (a Never flip rebuilds).
    if K.BarIsNever(XP) then
        return math.abs(cursorY)
    end

    cursorY = K.SizeRow(cursorY, XP)

    -- Show Dividers (its 5% and 10% colours inline; its settings row below
    -- exists only while it is on) | Orientation (its cog: Vertical Text).
    local divRowTop
    divRowTop, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Dividers",
        disabled = _blizzDis,
        disabledTooltip = BLIZZ_DIS_TIP,
        rawTooltip = true,
        getValue = function()
            return S().showDividers
        end,
        setValue = CludesUI.SectionToggleSetValue(function(val)
            S().showDividers = val
            mod.ApplyDataBarLayout(XP)
        end),
    }, K.OrientCfg({ XP }))
    cursorY = cursorY - height
    K.OrientCog(divRowTop._rightRegion, { XP }, true)
    if chrome then
        -- The 5% Ticks swatch also greys while 5% Line Style is None (its
        -- tooltip then names every lock, the row's included).
        CludesUI.BuildInlineSwatches(divRowTop._leftRegion, {
            {
                tooltip = "5% Ticks",
                hasAlpha = true,
                disabled = function()
                    return S().divider5Style == "none"
                end,
                disabledTooltip = function()
                    if _blizzDis() then
                        return BLIZZ_DIS_TIP
                    end
                    if not S().showDividers then
                        return "Show Dividers"
                    end
                    return "This option requires a 5% Line Style other than None"
                end,
                rawTooltip = _blizzDis,
                getValue = function()
                    local c = S().tick5Color
                    if c then
                        return c.r or 220 / 255, c.g or 167 / 255, c.b or 127 / 255, c.a or 0.9
                    end
                    return 220 / 255, 167 / 255, 127 / 255, 0.9
                end,
                setValue = function(red, green, blue, a)
                    S().tick5Color = { r = red, g = green, b = blue, a = a or 0.9 }
                    mod.ApplyDataBarLayout(XP)
                end,
            },
            {
                tooltip = "10% Lines",
                hasAlpha = true,
                getValue = function()
                    local c = S().tick10Color
                    if c then
                        return c.r or 1, c.g or 1, c.b or 1, c.a or 0.9
                    end
                    return 1, 1, 1, 0.9
                end,
                setValue = function(red, green, blue, a)
                    S().tick10Color = { r = red, g = green, b = blue, a = a or 0.9 }
                    mod.ApplyDataBarLayout(XP)
                end,
            },
        }, {
            size = 20,
            disabled = function()
                return _blizzDis() or not S().showDividers
            end,
            disabledTooltip = function()
                if _blizzDis() then
                    return BLIZZ_DIS_TIP
                end
                return "Show Dividers"
            end,
            rawTooltip = _blizzDis,
        })
    end

    -- 5% Line Style (its cog: Show Ticks Over Fill Bar, the inverse of the
    -- saved smartTicks, which hides the marks the fill has passed) | Divider
    -- Text (its cog: the text's colour, size and offsets), while Show
    -- Dividers is on.
    if S().showDividers then
        local divRow
        divRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "5% Line Style",
            values = { dashed = "Dashed", dotted = "Dotted", solid = "Solid", none = "None" },
            order = { "none", "dashed", "dotted", "solid" },
            disabled = _blizzDis,
            disabledTooltip = BLIZZ_DIS_TIP,
            rawTooltip = true,
            getValue = function()
                return S().divider5Style or "dashed"
            end,
            setValue = function(val)
                S().divider5Style = val
                mod.ApplyDataBarLayout(XP)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "toggle",
            text = "Divider Text",
            disabled = _blizzDis,
            disabledTooltip = BLIZZ_DIS_TIP,
            rawTooltip = true,
            getValue = function()
                return S().showDividerText
            end,
            setValue = function(val)
                S().showDividerText = val
                mod.ApplyDataBarLayout(XP)
                CludesUI:RefreshPage()
            end,
        })
        cursorY = cursorY - height
        if chrome then
            local lRgn, rRgn = divRow._leftRegion, divRow._rightRegion
            CludesUI.BuildInlineCog(lRgn, {
                title = "Ticks",
                anchorTo = lRgn._control,
                captureRegion = lRgn,
                disabled = _blizzDis,
                disabledTooltip = BLIZZ_DIS_TIP,
                rawTooltip = true,
                rows = {
                    {
                        type = "toggle",
                        label = "Show Ticks Over Fill Bar",
                        get = function()
                            return not S().smartTicks
                        end,
                        set = function(val)
                            S().smartTicks = not val
                            mod.ApplyDataBarLayout(XP)
                        end,
                    },
                },
            })
            CludesUI.BuildInlineCog(rRgn, {
                title = "Divider Text",
                anchorTo = rRgn._control,
                captureRegion = rRgn,
                disabled = function()
                    return _blizzDis() or not S().showDividerText
                end,
                disabledTooltip = function()
                    if _blizzDis() then
                        return BLIZZ_DIS_TIP
                    end
                    return "Divider Text"
                end,
                rawTooltip = _blizzDis,
                rows = {
                    {
                        type = "colorpicker",
                        label = "Text Color",
                        get = function()
                            local c = S().dividerTextColor
                            if c then
                                return c.r or 1, c.g or 1, c.b or 1
                            end
                            return 1, 1, 1
                        end,
                        set = function(red, green, blue)
                            S().dividerTextColor = { r = red, g = green, b = blue }
                            mod.ApplyDataBarLayout(XP)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 6,
                        max = 18,
                        step = 1,
                        get = function()
                            return S().dividerTextSize or 8
                        end,
                        set = function(val)
                            S().dividerTextSize = val
                            mod.ApplyDataBarLayout(XP)
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return S().dividerTextOffX or 0
                        end,
                        set = function(val)
                            S().dividerTextOffX = val
                            mod.ApplyDataBarLayout(XP)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return S().dividerTextOffY or 0
                        end,
                        set = function(val)
                            S().dividerTextOffY = val
                            mod.ApplyDataBarLayout(XP)
                        end,
                    },
                },
            })
        end
    end

    _, height = W:Spacer(hostFrame, cursorY, 12)
    cursorY = cursorY - height

    -------------------------------------------------------------------
    --  CORE TEXT POSITIONS
    -------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "CORE TEXT POSITIONS", cursorY)
    cursorY = cursorY - height

    -- The bar's texts, one slot each: only the ones that show something, two
    -- to a row, then Add Text Slot, which asks where the new text goes. Up to
    -- TEXTS_PER_POS texts share a position:
    -- its first is saved as textSlot<Stem> (unset, Center shows the old
    -- Default and the others nothing), the second and third as
    -- textSlot<Stem>2 / 3, each with its own Size, offsets and Show Rested;
    -- Center's first is the bar text, placed by Text Size and the Bar Text
    -- Offsets cog, and the only one a vertical bar shows. A text's name opens
    -- the positions it can move to; its dropdown checks and drags the items it
    -- shows, picks a bottom item instead, or takes it off (Remove, or every
    -- item unchecked by the time the list closes). A value saved before the
    -- items existed shows as its items here (the bar draws it as it was) and
    -- is rewritten only when edited. Structure changes rebuild the page.
    local SLOT_TIP = "What this text shows."
    local MOVE_TIP = "Choose this text's slot position."
    local TEXTS_PER_POS = 3
    local POSITIONS = {
        { stem = "Center", label = "Center Text", name = "Center" },
        { stem = "Left", label = "Left Text", name = "Left" },
        { stem = "Right", label = "Right Text", name = "Right" },
        { stem = "TopLeft", label = "Top Left Text", name = "Top Left" },
        { stem = "TopRight", label = "Top Right Text", name = "Top Right" },
        { stem = "BottomLeft", label = "Bottom Left Text", name = "Bottom Left" },
        { stem = "BottomRight", label = "Bottom Right Text", name = "Bottom Right" },
    }
    local function SlotKey(stem, i)
        return "textSlot" .. stem .. (i > 1 and i or "")
    end
    -- Center's first text: the bar text itself.
    local function IsBarText(stem, i)
        return stem == "Center" and i == 1
    end
    -- A text's saved value (the bar text: unset reads as the old Default).
    local function SlotRaw(stem, i)
        local val = S()[SlotKey(stem, i)]
        if val == nil and IsBarText(stem, i) then
            return "classic"
        end
        return val
    end
    -- Its items (into out) and their kind: "top", "solo" or nil for nothing,
    -- then true for the old Default text, then the value when the bar still
    -- draws it as it was. The bar text reads a value it does not know as
    -- Default, as the bar does.
    local function SlotItems(stem, i, result)
        local val = SlotRaw(stem, i)
        local kind, legacy, render = mod.XPTextItems(val, S(), result)
        if not kind and IsBarText(stem, i) and val ~= "none" then
            kind, legacy, render = mod.XPTextItems("classic", S(), result)
        end
        return kind, legacy, render
    end
    local scratch = {}
    local function Shows(stem, i)
        return SlotItems(stem, i, scratch) ~= nil
    end
    local function FreeIndex(stem)
        for i = 1, TEXTS_PER_POS do
            if not Shows(stem, i) then
                return i
            end
        end
    end
    -- Takes a text off: its value, Show Rested and its own size and offsets
    -- (the bar text: "none", its placement is the bar text's own).
    local function ClearSlot(stem, i)
        local s, key = S(), SlotKey(stem, i)
        s[key .. "Rested"] = nil
        if IsBarText(stem, i) then
            s[key] = "none"
        else
            s[key], s[key .. "Size"], s[key .. "XOffset"], s[key .. "YOffset"] = nil, nil, nil, nil
        end
    end
    local function Rebuild()
        mod.ApplyDataBarLayout(XP)
        CludesUI:RefreshPage(true)
    end
    -- Moves a text to the first free place at another position: its value and
    -- Show Rested, with its size and offsets unless either end is the bar text.
    local function MoveSlot(stem, i, toStem)
        if toStem == stem then
            return
        end
        local jdx = FreeIndex(toStem)
        if not jdx then
            return
        end
        local s, from, to = S(), SlotKey(stem, i), SlotKey(toStem, jdx)
        local val = SlotRaw(stem, i)
        -- The bar text shows a value it does not know as Default: so it moves.
        if not mod.XPTextItems(val, s, scratch) then
            val = "classic"
        end
        local rested = s[from .. "Rested"]
        local carry = not IsBarText(stem, i)
        local size, ox, oy = s[from .. "Size"], s[from .. "XOffset"], s[from .. "YOffset"]
        ClearSlot(stem, i)
        s[to] = val
        s[to .. "Rested"] = rested
        if not IsBarText(toStem, jdx) then
            s[to .. "Size"] = carry and size or nil
            s[to .. "XOffset"] = carry and ox or nil
            s[to .. "YOffset"] = carry and oy or nil
        end
        Rebuild()
    end
    -- Add Text Slot: a fresh text at the first free place of the position the
    -- player picked from the button's list, showing Current % with Show
    -- Rested on. The rebuild is immediate, so the new row reports the write.
    local function AddAt(stem)
        local position = FreeIndex(stem)
        if not position then
            return
        end
        local s, key = S(), SlotKey(stem, position)
        if not IsBarText(stem, position) then
            ClearSlot(stem, position)
        end
        s[key] = "pct"
        s[key .. "Rested"] = true
        addedKey = key
        Rebuild()
        addedKey = nil
    end
    -- Room for another text: any free place, or on a vertical bar the bar
    -- text's own place (the only text a vertical bar draws).
    local function AddRoom()
        if Vertical() then
            return not Shows("Center", 1)
        end
        for _, p in ipairs(POSITIONS) do
            if FreeIndex(p.stem) then
                return true
            end
        end
        return false
    end

    -- The texts that show something, in position order; a position's second
    -- and third are numbered.
    local entries = {}
    for _, p in ipairs(POSITIONS) do
        local rank = 0
        for i = 1, TEXTS_PER_POS do
            if Shows(p.stem, i) then
                rank = rank + 1
                entries[#entries + 1] = { pos = p, i = i, rank = rank }
            end
        end
    end
    local function EntryLabel(e)
        local base = CludesUI.L(e.pos.label)
        return e.rank > 1 and (base .. " " .. e.rank) or base
    end
    -- Every text but the bar text draws on a horizontal bar only.
    local function EntryLocked(e)
        return _blizzDis() or (not IsBarText(e.pos.stem, e.i) and Vertical())
    end
    local function SlotLockTip()
        if _blizzDis() then
            return BLIZZ_DIS_TIP
        end
        return "Horizontal Orientation"
    end
    -- A value's name: its items' names, " - " between them (nil for nothing).
    local labelScratch = {}
    local function ValueLabel(val)
        if not mod.XPTextItems(val, S(), labelScratch) then
            return nil
        end
        local nameList = {}
        for num = 1, #labelScratch do
            nameList[num] = CludesUI.L(ITEM_LABEL[labelScratch[num]])
        end
        return table.concat(nameList, " - ")
    end
    -- The row's own dropdown, hidden under the checkbox list: Spec Overrides
    -- read and write the text's value through it. One entry per item; any
    -- other value is named by its items.
    local PH_VALUES = setmetatable({ none = "Remove" }, {
        __index = function(_, keyName)
            if type(keyName) == "string" and keyName:sub(1, 1) ~= "_" then
                return ValueLabel(keyName)
            end
        end,
    })
    local PH_ORDER = { "none" }
    for _, list in ipairs({ TOP_ITEMS, SOLO_ITEMS }) do
        PH_ORDER[#PH_ORDER + 1] = "---"
        for _, it in ipairs(list) do
            PH_VALUES[it.key] = it.label
            PH_ORDER[#PH_ORDER + 1] = it.key
        end
    end
    local function EntryCfg(e)
        local stem, i = e.pos.stem, e.i
        return {
            type = "dropdown",
            text = EntryLabel(e),
            values = PH_VALUES,
            order = PH_ORDER,
            disabled = function()
                return EntryLocked(e)
            end,
            disabledTooltip = SlotLockTip,
            rawTooltip = _blizzDis,
            getValue = function()
                return SlotRaw(stem, i) or "none"
            end,
            setValue = function(val)
                S()[SlotKey(stem, i)] = val
                mod.ApplyDataBarLayout(XP)
            end,
        }
    end

    -- Saves a text's new value; the old Default text keeps its rested part
    -- (Show Rested) once it is rewritten. rgn: the row, for Spec Overrides,
    -- whose slot is read before the write (a rebuild may dress the row again
    -- for another setting).
    local function WriteSlot(stem, i, val, region)
        local snap = region and CludesUI._SOAttribution(region)
        local s, key = S(), SlotKey(stem, i)
        local _, legacy = SlotItems(stem, i, scratch)
        if legacy and s[key .. "Rested"] == nil then
            s[key .. "Rested"] = true
        end
        s[key] = val
        mod.ApplyDataBarLayout(XP)
        if region then
            CludesUI._NotifySettingWrite(region, snap)
        end
    end

    -- Show Rested: the rested XP after the text's first Current %, Current or
    -- Current / Max (on for the old Default text until set).
    local function RestedRow(stem, i)
        local key = SlotKey(stem, i) .. "Rested"
        local function Eligible()
            if SlotItems(stem, i, scratch) ~= "top" then
                return false
            end
            for num = 1, #scratch do
                if RESTED_ITEM[scratch[num]] then
                    return true
                end
            end
            return false
        end
        return {
            type = "toggle",
            label = "Show Rested",
            disabled = function()
                return not Eligible()
            end,
            disabledTooltip = "This option requires Current %, Current or Current / Max",
            get = function()
                local _, legacy = SlotItems(stem, i, scratch)
                return mod.XPTextRested(S(), key, legacy)
            end,
            set = function(val)
                -- An old value the bar still draws as it was (the old Default
                -- aside, whose rested part follows this) becomes its items.
                local _, _, render = SlotItems(stem, i, scratch)
                if render and render ~= "classic" then
                    S()[SlotKey(stem, i)] = table.concat(scratch, ",")
                end
                S()[key] = val and true or false
                mod.ApplyDataBarLayout(XP)
            end,
        }
    end

    -- The text's items: a checkbox list over its value (the top items, in the
    -- order dragged), Remove above it and the bottom items below it as plain
    -- choices. Checked items come first, in their order, each time it opens;
    -- the text's order is the order of its checked rows. Unchecking every item
    -- takes the text off once the list closes (until then another can be
    -- checked); a bottom item shows alone.
    local function ItemsDropdown(region, e)
        local stem, i = e.pos.stem, e.i
        local own = {}
        local emptied
        local rowList = {}
        for num, it in ipairs(TOP_ITEMS) do
            rowList[num] = { key = it.key, label = it.label }
        end
        local function Checked(keyName)
            if SlotItems(stem, i, own) ~= "top" then
                return false
            end
            for num = 1, #own do
                if own[num] == keyName then
                    return true
                end
            end
            return false
        end
        -- The checked items in the list's order (k turned on or off first).
        local function WriteChecked(sequence, keyName, on)
            local set = {}
            if SlotItems(stem, i, own) == "top" then
                for num = 1, #own do
                    set[own[num]] = true
                end
            end
            if keyName then
                set[keyName] = on or nil
            end
            local result = {}
            for num = 1, #sequence do
                if set[sequence[num]] then
                    result[#result + 1] = sequence[num]
                end
            end
            emptied = (#result == 0)
            WriteSlot(stem, i, emptied and "none" or table.concat(result, ","), region)
            CludesUI:RefreshPage()
        end
        local control = region._control
        local ddW = control and control:GetWidth() or 0
        if ddW < 50 then
            ddW = 210
        end
        local checkDrop, cbRefresh = CludesUI.BuildReorderCBDropdown(
            region,
            ddW,
            region:GetFrameLevel() + 2,
            rowList,
            Checked,
            function(keyName, val, sequence)
                WriteChecked(sequence, keyName, val)
            end,
            {
                hint = "Drag to Reorder",
                head = { { key = "none", label = "Remove" } },
                onHead = function()
                    emptied = nil
                    -- the row's slot, read before the write and the rebuild
                    local snap = CludesUI._SOAttribution(region)
                    ClearSlot(stem, i)
                    CludesUI._NotifySettingWrite(region, snap)
                    Rebuild()
                end,
                tail = SOLO_ITEMS,
                tailSelected = function(keyName)
                    return SlotItems(stem, i, own) == "solo" and own[1] == keyName
                end,
                onTail = function(keyName)
                    emptied = nil
                    WriteSlot(stem, i, keyName, region)
                    CludesUI:RefreshPage()
                end,
                openOrder = function()
                    if SlotItems(stem, i, own) ~= "top" then
                        return nil
                    end
                    local keyList = {}
                    for num = 1, #own do
                        keyList[num] = own[num]
                    end
                    return keyList
                end,
                setOrder = function(sequence)
                    if SlotItems(stem, i, own) == "top" then
                        WriteChecked(sequence)
                    end
                end,
                onClose = function()
                    if emptied and not Shows(stem, i) then
                        emptied = nil
                        -- the row's slot, read before the write and the rebuild
                        local snap = CludesUI._SOAttribution(region)
                        ClearSlot(stem, i)
                        CludesUI._NotifySettingWrite(region, snap)
                        Rebuild()
                    end
                end,
                summaryLabel = function()
                    return ValueLabel(SlotRaw(stem, i)) or CludesUI.L("None")
                end,
            }
        )
        local p1, rel, p2, ax, ay
        if control then
            p1, rel, p2, ax, ay = control:GetPoint(1)
            control:Hide()
        end
        if p1 then
            checkDrop:SetPoint(p1, rel, p2, ax, ay)
        else
            CludesUI.PanelPP.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
        end
        region._control = checkDrop
        region._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbRefresh)
        -- What the text shows, on the list while it is closed (the name above
        -- it is the position button, with its own tooltip).
        checkDrop:HookScript("OnEnter", function(self)
            if self._ddMenu and self._ddMenu:IsShown() then
                return
            end
            CludesUI.ShowWidgetTooltip(self, SLOT_TIP)
        end)
        checkDrop:HookScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        checkDrop:HookScript("OnClick", function()
            CludesUI.HideWidgetTooltip()
        end)
        -- The list has no disabled state of its own: grey it and block clicks;
        -- the row's disabled overlay explains the lock.
        local function SyncLock()
            local off = EntryLocked(e)
            checkDrop:SetAlpha(off and 0.3 or 1)
            checkDrop:EnableMouse(not off)
        end
        SyncLock()
        CludesUI.RegisterWidgetRefresh(SyncLock)
    end
    -- A text's cog (all but the bar text): its Size, offsets and Show Rested.
    local function SlotCog(region, e)
        local stem, i = e.pos.stem, e.i
        local key = SlotKey(stem, i)
        local sizeKey, xKey, yKey = key .. "Size", key .. "XOffset", key .. "YOffset"
        local rowList = {
            {
                type = "slider",
                label = "Size",
                min = 6,
                max = 24,
                step = 1,
                get = function()
                    return S()[sizeKey] or S().textSize or 9
                end,
                set = function(val)
                    S()[sizeKey] = val
                    mod.ApplyDataBarLayout(XP)
                end,
            },
            {
                type = "slider",
                label = "X Offset",
                min = -150,
                max = 150,
                step = 1,
                get = function()
                    return S()[xKey] or 0
                end,
                set = function(val)
                    S()[xKey] = val
                    mod.ApplyDataBarLayout(XP)
                end,
            },
            {
                type = "slider",
                label = "Y Offset",
                min = -150,
                max = 150,
                step = 1,
                get = function()
                    return S()[yKey] or 0
                end,
                set = function(val)
                    S()[yKey] = val
                    mod.ApplyDataBarLayout(XP)
                end,
            },
        }
        rowList[#rowList + 1] = RestedRow(stem, i)
        CludesUI.BuildInlineCog(region, {
            title = EntryLabel(e),
            anchorTo = region._control,
            captureRegion = region,
            disabled = function()
                return EntryLocked(e)
            end,
            disabledTooltip = SlotLockTip,
            rawTooltip = _blizzDis,
            rows = rowList,
        })
    end
    -- The text's name with a white chevron (the accent while hovered or open;
    -- a darker white when the accent itself is white): the standard dropdown
    -- list of the positions it can move to, built on first open (the one it
    -- is in selected, a full one greyed, all but Center on a vertical bar).
    local CHEVRON = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-down3.png"
    local POS_VALUES, POS_ORDER = {}, {}
    for _, p in ipairs(POSITIONS) do
        POS_VALUES[p.stem] = p.name
        POS_ORDER[#POS_ORDER + 1] = p.stem
    end
    local function ChevronHoverColor()
        local ac = CludesUI.CLUDES_GREEN
        if ac.r > 0.9 and ac.g > 0.9 and ac.b > 0.9 then
            return 0.72, 0.72, 0.72
        end
        return ac.r, ac.g, ac.b
    end
    local NO_PAINT = { SetColor = function() end, SetColorTexture = function() end }
    local function PositionPicker(region, e)
        local labelText = region._label
        local button = CreateFrame("Button", nil, region)
        button:SetFrameLevel(region:GetFrameLevel() + 12)
        local arrow = button:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture(CHEVRON)
        arrow:SetSize(17, 17)
        arrow:SetPoint("LEFT", labelText, "LEFT", math.ceil(labelText:GetStringWidth()) + 6, -1)
        button:SetPoint("TOPLEFT", labelText, "TOPLEFT", -4, 5)
        button:SetPoint("BOTTOMRIGHT", arrow, "BOTTOMRIGHT", 2, -2)
        local dropMenu
        -- The name takes the chevron's colour while lit (its own white back).
        local function Lit(on)
            if on then
                local red, green, blue = ChevronHoverColor()
                arrow:SetVertexColor(red, green, blue)
                labelText:SetTextColor(red, green, blue)
            else
                arrow:SetVertexColor(1, 1, 1)
                labelText:SetTextColor(CludesUI.TEXT_WHITE_R, CludesUI.TEXT_WHITE_G, CludesUI.TEXT_WHITE_B)
            end
        end
        Lit(false)
        local function OnEnter()
            if EntryLocked(e) then
                local tipText = SlotLockTip()
                CludesUI.ShowWidgetTooltip(
                    button,
                    _blizzDis() and tipText or CludesUI.DisabledTooltip(tipText)
                )
                return
            end
            Lit(true)
            if not (dropMenu and dropMenu:IsShown()) then
                CludesUI.ShowWidgetTooltip(button, MOVE_TIP)
            end
        end
        local function OnLeave()
            if not (dropMenu and dropMenu:IsShown()) then
                Lit(false)
            end
            CludesUI.HideWidgetTooltip()
        end
        button:SetScript("OnEnter", OnEnter)
        button:SetScript("OnLeave", OnLeave)
        -- The list's label stand-in: the menu writes the picked name there,
        -- never over the text's own name.
        local proxyLbl = CludesUI.MakeFont(button, 12, nil, 1, 1, 1)
        proxyLbl:Hide()
        local function EnsureMenu()
            if dropMenu then
                return dropMenu
            end
            local refresh
            dropMenu, _, refresh = CludesUI.BuildDropdownMenu(
                button,
                170,
                POS_ORDER,
                POS_VALUES,
                function()
                    return e.pos.stem
                end,
                function(val)
                    MoveSlot(e.pos.stem, e.i, val)
                end,
                proxyLbl,
                "regular",
                function(val)
                    if val == e.pos.stem then
                        return nil
                    end
                    if val ~= "Center" and Vertical() then
                        return CludesUI.DisabledTooltip("Horizontal Orientation")
                    end
                    if not FreeIndex(val) then
                        return true
                    end
                end
            )
            -- The standard open/close behaviour (scale, click-away, scroll-away);
            -- the button keeps its own look and clicks.
            CludesUI.WireDropdownScripts(
                button,
                proxyLbl,
                NO_PAINT,
                NO_PAINT,
                dropMenu,
                refresh,
                CludesUI.RD_DD_COLOURS,
                true
            )
            button:HookScript("OnEnter", OnEnter)
            button:HookScript("OnLeave", OnLeave)
            dropMenu:HookScript("OnShow", function()
                Lit(true)
            end)
            dropMenu:HookScript("OnHide", function()
                Lit(button:IsMouseOver())
            end)
            return dropMenu
        end
        button:SetScript("OnClick", function()
            if EntryLocked(e) then
                return
            end
            CludesUI.HideWidgetTooltip()
            local m = EnsureMenu()
            if m:IsShown() then
                m:Hide()
            else
                m:Show()
            end
        end)
        button:HookScript("OnHide", function()
            if dropMenu then
                dropMenu:Hide()
            end
        end)
        local function SyncLock()
            arrow:SetShown(not EntryLocked(e))
        end
        CludesUI.RegisterWidgetRefresh(SyncLock)
        SyncLock()
    end

    -- Add Text Slot opens the list of positions (the standard dropdown menu,
    -- as wide as the button, built on first open; a full position greyed,
    -- and on a vertical bar every position but the bar text's own): the
    -- player picks where the new text goes.
    local ADD_W = 220
    local addOpen -- the button's click, once its row is built
    local function AddPicker(region)
        local button = region._control
        -- Its own hover look, kept past the menu wiring (which takes the scripts).
        local enter, leave = button:GetScript("OnEnter"), button:GetScript("OnLeave")
        local proxyLbl = CludesUI.MakeFont(button, 12, nil, 1, 1, 1)
        proxyLbl:Hide()
        local dropMenu
        local function EnsureMenu()
            if dropMenu then
                return dropMenu
            end
            local refresh
            dropMenu, _, refresh = CludesUI.BuildDropdownMenu(
                button,
                ADD_W,
                POS_ORDER,
                POS_VALUES,
                function()
                    return nil
                end,
                function(val)
                    AddAt(val)
                end,
                proxyLbl,
                "regular",
                function(val)
                    if Vertical() then
                        if val ~= "Center" then
                            return CludesUI.DisabledTooltip("Horizontal Orientation")
                        end
                        if Shows("Center", 1) then
                            return true
                        end
                        return nil
                    end
                    if not FreeIndex(val) then
                        return true
                    end
                end
            )
            CludesUI.WireDropdownScripts(
                button,
                proxyLbl,
                NO_PAINT,
                NO_PAINT,
                dropMenu,
                refresh,
                CludesUI.RD_DD_COLOURS,
                true
            )
            button:HookScript("OnEnter", enter)
            button:HookScript("OnLeave", function(self)
                if not dropMenu:IsShown() then
                    leave(self)
                end
            end)
            dropMenu:HookScript("OnHide", function()
                if not button:IsMouseOver() then
                    leave(button)
                end
            end)
            return dropMenu
        end
        addOpen = function()
            local m = EnsureMenu()
            if m:IsShown() then
                m:Hide()
            else
                m:Show()
            end
        end
        button:HookScript("OnHide", function()
            if dropMenu then
                dropMenu:Hide()
            end
        end)
    end

    -- The texts two to a row, Add Text Slot in the slot after the last.
    local addCfg = {
        type = "button",
        text = "+ Add Text Slot",
        width = ADD_W,
        onClick = function()
            if addOpen then
                addOpen()
            end
        end,
        disabled = function()
            return _blizzDis() or not AddRoom()
        end,
        disabledTooltip = function()
            if _blizzDis() then
                return BLIZZ_DIS_TIP
            end
            if Vertical() then
                return "Horizontal Orientation"
            end
            return "Every text position is full."
        end,
        rawTooltip = function()
            return _blizzDis() or not Vertical()
        end,
    }
    local cells = {}
    for keyName = 1, #entries do
        cells[keyName] = entries[keyName]
    end
    cells[#cells + 1] = addCfg
    local function CellCfg(c)
        if c == nil then
            return CludesUI.BlankRowCfg()
        end
        if c == addCfg then
            return addCfg
        end
        return EntryCfg(c)
    end
    local function CellChrome(region, c)
        if not chrome or c == nil then
            return
        end
        if c == addCfg then
            AddPicker(region)
            return
        end
        PositionPicker(region, c)
        ItemsDropdown(region, c)
        if IsBarText(c.pos.stem, c.i) then
            K.TextCog(region, XP, { RestedRow(c.pos.stem, c.i) })
        else
            SlotCog(region, c)
        end
        -- The text Add Text Slot just made: its own row takes the write, its
        -- slot read now, while this build's row holds it.
        if addedKey and addedKey == SlotKey(c.pos.stem, c.i) then
            addedKey = nil
            local snap = CludesUI._SOAttribution(region)
            CludesUI._NotifySettingWrite(region, snap)
        end
    end
    for keyName = 1, #cells, 2 do
        local l, r = cells[keyName], cells[keyName + 1]
        local row
        row, height = W:DualRow(hostFrame, cursorY, CellCfg(l), CellCfg(r))
        cursorY = cursorY - height
        CellChrome(row._leftRegion, l)
        CellChrome(row._rightRegion, r)
    end

    _, height = W:Spacer(hostFrame, cursorY, 12)
    cursorY = cursorY - height

    -------------------------------------------------------------------
    --  DISPLAY
    -------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "DISPLAY", cursorY)
    cursorY = cursorY - height

    -- Text Size (the bar text's, and every other text's until its own is
    -- set) | Text Background (its colour and opacity inline): a box behind
    -- every text shown.
    local textBgRow
    textBgRow, height = W:DualRow(hostFrame, cursorY, K.TextSizeCfg(XP), {
        type = "toggle",
        text = "Text Background",
        disabled = _blizzDis,
        disabledTooltip = BLIZZ_DIS_TIP,
        rawTooltip = true,
        getValue = function()
            return S().showTextBg
        end,
        setValue = function(val)
            S().showTextBg = val
            mod.ApplyDataBarLayout(XP)
            CludesUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height
    if chrome then
        CludesUI.BuildInlineSwatches(textBgRow._rightRegion, {
            {
                tooltip = "Background Color",
                hasAlpha = true,
                getValue = function()
                    local c = S().textBgColor
                    if c then
                        return c.r or 0.06, c.g or 0.06, c.b or 0.08, c.a or 0.9
                    end
                    return 0.06, 0.06, 0.08, 0.9
                end,
                setValue = function(red, green, blue, a)
                    S().textBgColor = { r = red, g = green, b = blue, a = a or 0.9 }
                    mod.ApplyDataBarLayout(XP)
                end,
            },
        }, {
            size = 20,
            disabled = function()
                return _blizzDis() or not S().showTextBg
            end,
            disabledTooltip = function()
                if _blizzDis() then
                    return BLIZZ_DIS_TIP
                end
                return "Text Background"
            end,
            rawTooltip = _blizzDis,
        })
    end

    -- Border Style | Border Size, no Custom Border toggle: the plain line
    -- shows as Solid 1px until the first edit turns the border on.
    cursorY = K.BorderRows(cursorY, XP, true)

    -- Fill Style: Custom Color (the fill colour swatches inline: Custom,
    -- Accent, Reactive), Horizontal / Vertical Gradient (s.fillGradient; its
    -- Gradient Start and End colours inline, s.fillGradStart / fillGradEnd,
    -- defaults in ns.XPBarGradient) or a profession skill-bar animation (its
    -- cog inline: Animate on XP Gain, on by default -- nil plays, false stops
    -- it -- and Loop Animation, off by default, one turning the other off;
    -- Stretch to Bar draws one copy across the bar instead of tiles at the
    -- art's proportions). Only the flipbooks this client has are offered, and
    -- none on a vertical bar (the art is horizontal). Switching to another
    -- kind rebuilds the page for its inline control.
    local fillVals = { custom = "Custom Color", gradH = "Horizontal Gradient", gradV = "Vertical Gradient" }
    local fillOrder = { "custom", "gradH", "gradV" }
    if not Vertical() then
        for _, c in ipairs(FLIP_CANDS) do
            if C_Texture.GetAtlasInfo(c[1]) then
                if #fillOrder == 3 then
                    fillOrder[4] = "---"
                end
                fillVals[c[1]] = c[2]
                fillOrder[#fillOrder + 1] = c[1]
            end
        end
    end
    local GRAD_KEY = { HORIZONTAL = "gradH", VERTICAL = "gradV" }
    local GRAD_DIR = { gradH = "HORIZONTAL", gradV = "VERTICAL" }
    local function FillKey()
        local f = S().fvFill
        if f and fillVals[f] then
            return f
        end
        return GRAD_KEY[S().fillGradient] or "custom"
    end
    local function FillKind()
        local keyName = FillKey()
        if keyName == "custom" then
            return "custom"
        end
        return GRAD_DIR[keyName] and "gradient" or "flip"
    end
    local function Custom()
        return FillKind() == "custom"
    end
    -- Rested Color: the rested XP shown ahead of the fill (dark blue at half
    -- opacity until set).
    local fillRow
    fillRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Fill Style",
        values = fillVals,
        order = fillOrder,
        disabled = _blizzDis,
        disabledTooltip = BLIZZ_DIS_TIP,
        rawTooltip = true,
        getValue = FillKey,
        setValue = function(val)
            local was = FillKind()
            local s = S()
            s.fillGradient = GRAD_DIR[val]
            s.fvFill = (val ~= "custom" and not GRAD_DIR[val]) and val or nil
            mod.ApplyDataBarLayout(XP)
            -- Another kind needs its own inline control: rebuild.
            if FillKind() ~= was then
                CludesUI:RefreshPage(true)
            else
                CludesUI:RefreshPage()
            end
        end,
    }, {
        type = "colorpicker",
        text = "Rested Color",
        hasAlpha = true,
        disabled = _blizzDis,
        disabledTooltip = BLIZZ_DIS_TIP,
        rawTooltip = true,
        getValue = function()
            local c = S().restedColor
            if c then
                return c.r or 0.15, c.g or 0.30, c.b or 0.60, c.a or 0.5
            end
            return 0.15, 0.30, 0.60, 0.5
        end,
        setValue = function(red, green, blue, a)
            S().restedColor = { r = red, g = green, b = blue, a = a or 0.5 }
            mod.ApplyDataBarLayout(XP)
        end,
    })
    cursorY = cursorY - height
    if chrome then
        local region = fillRow._leftRegion
        if Custom() then
            CludesUI.BuildInlineSwatches(
                region,
                K.ColorSwatches(XP),
                { size = 20, disabled = _blizzDis, disabledTooltip = BLIZZ_DIS_TIP, rawTooltip = true }
            )
        elseif FillKind() == "gradient" then
            CludesUI.BuildInlineSwatches(region, {
                {
                    tooltip = "Gradient Start Color",
                    hasAlpha = true,
                    getValue = function()
                        local _, red, green, blue, a = mod.XPBarGradient(S())
                        return red, green, blue, a
                    end,
                    setValue = function(red, green, blue, a)
                        S().fillGradStart = { r = red, g = green, b = blue, a = a or 1 }
                        mod.ApplyDataBarLayout(XP)
                    end,
                },
                {
                    tooltip = "Gradient End Color",
                    hasAlpha = true,
                    getValue = function()
                        local _, _, _, _, _, red, green, blue, a = mod.XPBarGradient(S())
                        return red, green, blue, a
                    end,
                    setValue = function(red, green, blue, a)
                        S().fillGradEnd = { r = red, g = green, b = blue, a = a or 1 }
                        mod.ApplyDataBarLayout(XP)
                    end,
                },
            }, {
                size = 20,
                disabled = _blizzDis,
                disabledTooltip = BLIZZ_DIS_TIP,
                rawTooltip = true,
            })
        else
            CludesUI.BuildInlineCog(region, {
                title = "Fill Animation",
                anchorTo = region._control,
                captureRegion = region,
                disabled = _blizzDis,
                disabledTooltip = BLIZZ_DIS_TIP,
                rawTooltip = true,
                rows = {
                    {
                        type = "toggle",
                        label = "Animate on XP Gain",
                        tooltip = "Plays the animation once each time you gain XP.",
                        get = function()
                            return S().fvFillSmart ~= false and not S().fvFillAnim
                        end,
                        set = function(on)
                            if on then
                                S().fvFillSmart = nil
                                S().fvFillAnim = nil
                            else
                                S().fvFillSmart = false
                            end
                            mod.ApplyDataBarLayout(XP)
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Loop Animation",
                        tooltip = "Plays the animation continuously.",
                        get = function()
                            return S().fvFillAnim == true
                        end,
                        set = function(on)
                            if on then
                                S().fvFillAnim = true
                                S().fvFillSmart = false
                            else
                                S().fvFillAnim = nil
                            end
                            mod.ApplyDataBarLayout(XP)
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Stretch to Bar",
                        tooltip = "Stretches the animation across the whole bar.",
                        get = function()
                            return S().fvFillStretch
                        end,
                        set = function(on)
                            S().fvFillStretch = on or nil
                            mod.ApplyDataBarLayout(XP)
                        end,
                    },
                },
            })
        end
    end

    -- Background: its opacity (the slider, "Background Opacity" on hover) and
    -- its colour inline, locked at 0%; both fall back to the style's own
    -- background until set, ns.XPBarBackground) | Bar Texture.
    local bgRow
    bgRow, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Background",
        min = 0,
        max = 100,
        step = 1,
        tooltipOnControl = "Background Opacity",
        disabled = _blizzDis,
        disabledTooltip = BLIZZ_DIS_TIP,
        rawTooltip = true,
        getValue = function()
            local _, _, _, op = mod.XPBarBackground(S())
            return op
        end,
        setValue = function(val)
            local _, _, _, was = mod.XPBarBackground(S())
            S().barBgOpacity = val
            mod.ApplyDataBarLayout(XP)
            -- The colour swatch locks at 0%: refresh only on that edge.
            if (was <= 0) ~= (val <= 0) then
                CludesUI:RefreshPage()
            end
        end,
    }, K.TexCfg(XP))
    cursorY = cursorY - height
    if chrome then
        CludesUI.BuildInlineSwatches(bgRow._leftRegion, {
            {
                tooltip = "Background Color",
                getValue = function()
                    local red, green, b = mod.XPBarBackground(S())
                    return red, green, b
                end,
                setValue = function(red, green, blue)
                    S().barBgColor = { r = red, g = green, b = blue }
                    mod.ApplyDataBarLayout(XP)
                end,
            },
        }, {
            size = 20,
            disabled = function()
                if _blizzDis() then
                    return true
                end
                local _, _, _, op = mod.XPBarBackground(S())
                return op <= 0
            end,
            disabledTooltip = function()
                if _blizzDis() then
                    return BLIZZ_DIS_TIP
                end
                return "This option requires Background above 0%"
            end,
            rawTooltip = _blizzDis,
        })
    end

    -- Quest XP Overlay: the completed / incomplete colours as inline swatches
    -- (green / gold at 60% until set, ns.XPQuestColor), the filters in its cog.
    local questRow
    questRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Quest XP Overlay",
        tooltip = "Shows the XP from quests in your quest log ahead of the fill.",
        disabled = _blizzDis,
        disabledTooltip = BLIZZ_DIS_TIP,
        rawTooltip = true,
        getValue = function()
            return S().questOverlay
        end,
        setValue = function(val)
            S().questOverlay = val
            mod.ApplyDataBarLayout(XP)
            CludesUI:RefreshPage()
        end,
    }, CludesUI.BlankRowCfg())
    cursorY = cursorY - height
    if chrome then
        local region = questRow._leftRegion
        local function overlayOff()
            return _blizzDis() or not S().questOverlay
        end
        CludesUI.BuildInlineCog(region, {
            title = "Quest XP Overlay",
            captureRegion = region,
            disabled = overlayOff,
            disabledTooltip = function()
                if _blizzDis() then
                    return BLIZZ_DIS_TIP
                end
                return "Quest XP Overlay"
            end,
            rawTooltip = _blizzDis,
            rows = {
                {
                    type = "toggle",
                    label = "Completed Quests Only",
                    tooltip = "Only counts quests that are ready to turn in.",
                    get = function()
                        return S().questOverlayCompleted
                    end,
                    set = function(val)
                        S().questOverlayCompleted = val or nil
                        mod.ApplyDataBarLayout(XP)
                        CludesUI:RefreshPage()
                    end,
                },
                {
                    type = "toggle",
                    label = "Current Zone Only",
                    tooltip = "Only counts quests in your current zone.",
                    get = function()
                        return S().questOverlayZone
                    end,
                    set = function(val)
                        S().questOverlayZone = val or nil
                        mod.ApplyDataBarLayout(XP)
                    end,
                },
            },
        })
        CludesUI.BuildInlineSwatches(region, {
            {
                tooltip = "Completed Color",
                hasAlpha = true,
                getValue = function()
                    return mod.XPQuestColor(S(), true)
                end,
                setValue = function(red, green, blue, a)
                    S().questOverlayDoneColor = { r = red, g = green, b = blue, a = a or 0.6 }
                    mod.ApplyDataBarLayout(XP)
                end,
            },
            {
                tooltip = "Incomplete Color",
                hasAlpha = true,
                disabled = function()
                    return S().questOverlayCompleted
                end,
                disabledTooltip = function()
                    if _blizzDis() then
                        return BLIZZ_DIS_TIP
                    end
                    if not S().questOverlay then
                        return "Quest XP Overlay"
                    end
                    return "Completed Quests Only"
                end,
                requireState = function()
                    if S().questOverlay and not _blizzDis() then
                        return "disabled"
                    end
                end,
                rawTooltip = _blizzDis,
                getValue = function()
                    return mod.XPQuestColor(S(), false)
                end,
                setValue = function(red, green, blue, a)
                    S().questOverlayColor = { r = red, g = green, b = blue, a = a or 0.6 }
                    mod.ApplyDataBarLayout(XP)
                end,
            },
        }, {
            size = 20,
            disabled = overlayOff,
            disabledTooltip = function()
                if _blizzDis() then
                    return BLIZZ_DIS_TIP
                end
                return "Quest XP Overlay"
            end,
            rawTooltip = _blizzDis,
        })
    end

    return math.abs(cursorY)
end

-- Used by CUI_ActionBars_Options.lua
mod.ABO_BuildXPBarPage = BuildXPBarPage
