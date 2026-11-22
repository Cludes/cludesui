if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Panel.lua
--  The options panel shell: main frame, sidebar, header, tabs, content
--  area, inline search, module registration, page selection, show/hide
--  and the sidebar unlock tip. Loads right after CludesUI.lua.
-------------------------------------------------------------------------------
local CUI = _G.CludesUI
-- Private namespace shared with CludesUI.lua (module registry, sidebar model).
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)

local PP = CUI.PP
local PanelPP = CUI.PanelPP
local MakeFont = CUI.MakeFont
local SolidTex = CUI.SolidTex
local lerp = CUI.lerp
local RegAccent = CUI.RegAccent
local ResetRowCounters = CUI.ResetRowCounters
local ResolveFactionTheme = CUI._ResolveFactionTheme
local CLUDES_GREEN = CUI.CLUDES_GREEN
local BORDER_COLOR = CUI.BORDER_COLOR
local DARK_BG = CUI.DARK_BG
local TEXT_DIM = CUI.TEXT_DIM
local TEXT_SECTION = CUI.TEXT_SECTION
local CONTENT_PAD = CUI.CONTENT_PAD
local STYLE = CUI._STYLE
local THEME_BG_FILES = CUI._THEME_BG_FILES
local IS_STANDALONE = CUI._IS_STANDALONE
local MEDIA_PATH = CUI.MEDIA_PATH
local ICONS_PATH = CUI.ICONS_PATH
local ADDON_ROSTER = CUI.ADDON_ROSTER
local CLASS_ART_MAP = CUI.CLASS_ART_MAP
local playerClass = CUI._playerClass
local moduleList = CUI_NS.modules
local _widgetRefreshList = CUI._widgetRefreshList
local IsAddonLoaded = C_AddOns.IsAddOnLoaded

-- ONE paste point for a Twitch channel link (nil = no link shown).
CUI.TWITCH_URL = nil

-- Sidebar nav states
local NAV_SELECTED_TEXT = { r = STYLE.TEXT_WHITE_R, g = STYLE.TEXT_WHITE_G, b = STYLE.TEXT_WHITE_B, a = 1 }
local NAV_SELECTED_ICON_A = 1
local NAV_ENABLED_TEXT = { r = STYLE.TEXT_WHITE_R, g = STYLE.TEXT_WHITE_G, b = STYLE.TEXT_WHITE_B, a = 0.6 }
local NAV_ENABLED_ICON_A = 0.60
local NAV_DISABLED_TEXT = { r = 1, g = 1, b = 1, a = 0.11 }
local NAV_DISABLED_ICON_A = 0.20
local NAV_HOVER_ENABLED_TEXT = { r = 1, g = 1, b = 1, a = 0.86 }
local NAV_HOVER_DISABLED_TEXT = { r = 1, g = 1, b = 1, a = 0.39 }

local BG_WIDTH, BG_HEIGHT = 1500, 1154
local CLICK_W, CLICK_H = 1300, 946
local SIDEBAR_W = 295
local HEADER_H = 138 -- title + desc + banner glow + dark band for tabs
local TAB_BAR_H = 40
local FOOTER_H = 82

local panelFrame, backdrop, hitArea, navBar, contentFrame
local headerFrame, tabStrip, contentScroll, contentChild, footerBar, headStrip
local sidebarButtons = {}
CUI_NS.sidebarButtons = sidebarButtons
local currentModule, activePage
local _lastPagePerModule = {}
local scrollTarget = 0
local smoothing = false
local smoother
local UpdateScrollThumb
local suppressScrollRangeChanged = false
local lastHeaderPadded = false
local skipScrollChildReanchor = false

local function WipeWidgetRefreshes()
    for i = 1, #_widgetRefreshList do
        _widgetRefreshList[i] = nil
    end
end

-- Snapshot/restore the refresh registry around off-screen widget builds (search-index
-- pre-build) so an unviewed page never leaks refresh closures into the displayed list.
function CUI._SnapshotAndClearWidgetRefreshList()
    local snap = {}
    for i = 1, #_widgetRefreshList do
        snap[i] = _widgetRefreshList[i]
    end
    WipeWidgetRefreshes()
    return snap
end
function CUI._RestoreWidgetRefreshList(snap)
    WipeWidgetRefreshes()
    for i = 1, #snap do
        _widgetRefreshList[i] = snap[i]
    end
end

-- The refresh RefreshPage put off while the panel was closed or folded to the
-- mini window (a forced pass, or the fast path's widget re-read): run once, for
-- the page then shown, when the panel shows again (the on-show callback ahead
-- of the module OnShow handlers, and the unfold).
local function RunDeferredRefresh()
    if CUI._pendingForceRefresh then
        CUI._pendingForceRefresh = nil
        -- the pass dresses every widget at its current value
        CUI._pendingFastRefresh = nil
        CUI:RefreshPage(true)
    elseif CUI._pendingFastRefresh then
        CUI._pendingFastRefresh = nil
        for i = 1, #_widgetRefreshList do
            _widgetRefreshList[i]()
        end
    end
end

-- Hide all children/regions of a frame without orphaning them
local HideAllChildren
do
    local _hideAllScratch = {}
    local function _packIntoScratch(...)
        local count = select("#", ...)
        for i = 1, count do
            _hideAllScratch[i] = select(i, ...)
        end
        return count
    end
    -- Hiders of the custom root frames modules parent to the scroll frame itself
    -- (beside the scroll child: manager pages, Profiles): every registered one runs.
    local _scrollRootHiders = {}
    function CUI._AddScrollRootHider(fn)
        for i = 1, #_scrollRootHiders do
            if _scrollRootHiders[i] == fn then return end
        end
        _scrollRootHiders[#_scrollRootHiders + 1] = fn
    end
    HideAllChildren = function(parent, keepSet)
        -- Pack children into reusable scratch table (one GetChildren call)
        local count = _packIntoScratch(parent:GetChildren())
        for i = 1, count do
            if not (keepSet and keepSet[_hideAllScratch[i]]) then _hideAllScratch[i]:Hide() end
            _hideAllScratch[i] = nil
        end
        count = _packIntoScratch(parent:GetRegions())
        for i = 1, count do
            if not (keepSet and keepSet[_hideAllScratch[i]]) then _hideAllScratch[i]:Hide() end
            _hideAllScratch[i] = nil
        end
        -- Also hide custom root frames parented to contentScroll (bypass scroll child)
        for i = 1, #_scrollRootHiders do
            _scrollRootHiders[i]()
        end
        if CUI._hideScrollFrameRoots then CUI._hideScrollFrameRoots() end
    end
end

-- Page reuse (CludesUIOptions/CludesUI_FramePool.lua). The owners of the
-- pool's kept page wrappers and header roots, and the header roots' state: one
-- kept root per suite page (key "module::page"), its height when it was left,
-- and whether it must be dressed again before it shows (stale).
CUI_NS.wrapperOwner = CUI_NS.wrapperOwner or {}
CUI_NS.headerOwner = CUI_NS.headerOwner or {}
CUI_NS.hdr = CUI_NS.hdr or { roots = {}, isRoot = {}, height = {}, stale = {}, active = nil }

-- A kept header root's children and regions the pool does not manage (made by
-- builders that create without it) are dropped exactly as a header's children
-- always were, hidden and detached, when the header is cleared or invalidated:
-- code that tests GetParent() sees them gone, as before.
function CUI_NS.DropRootForeign(rootFrame)
    local managed = CUI_NS.PoolManaged
    local kids = { rootFrame:GetChildren() }
    for i = 1, #kids do
        local k = kids[i]
        if not (managed and managed(k)) then
            k:Hide()
            k:SetParent(nil)
        end
    end
    local regs = { rootFrame:GetRegions() }
    for i = 1, #regs do
        local r = regs[i]
        if not (managed and managed(r)) then
            r:Hide()
            r:SetParent(nil)
        end
    end
end

-- OnShow callbacks -- available immediately; panelFrame hooks in when created
local _onShowCallbacks = {}
function CUI:RegisterOnShow(fn) _onShowCallbacks[#_onShowCallbacks + 1] = fn end

-- OnHide callbacks -- fired when the settings panel closes
local _onHideCallbacks = {}
function CUI:RegisterOnHide(fn) _onHideCallbacks[#_onHideCallbacks + 1] = fn end

-------------------------------------------------------------------------------
--  Tab helpers  (forward-declared, defined before CreateMainFrame uses them)
-------------------------------------------------------------------------------
local ClearTabs, CreateTabButton, BuildTabs, UpdateTabHighlight
local UpdateSidebarHighlight, ClearContent

-------------------------------------------------------------------------------
--  Build Main Frame
-------------------------------------------------------------------------------
local function BuildFrame()
    -----------------------------------------------------------------------
    --  Root frame + scaling
    -----------------------------------------------------------------------
    panelFrame = CreateFrame("Frame", "CludesUIFrame", UIParent)
    CUI._mainFrame = panelFrame
    panelFrame:SetSize(BG_WIDTH, BG_HEIGHT)
    panelFrame:SetPoint("CENTER")
    panelFrame:SetFrameStrata("DIALOG")
    panelFrame:SetFrameLevel(100)
    panelFrame:Hide()
    panelFrame:EnableMouse(false)
    panelFrame:SetMovable(true)
    panelFrame:SetScript("OnShow", function()
        -- Recalculate pixel-perfect base scale on every open so resolution / UIParent scale changes apply
        local physW2 = (GetPhysicalScreenSize())
        local baseScale2 = GetScreenWidth() / physW2
        local userScale2 = (CludesUIDB and CludesUIDB.panelScale) or 1.0
        panelFrame:SetScale(baseScale2 * userScale2)
        -- Re-sync PanelPP mult for the (possibly new) scale
        if CUI.PanelPP then CUI.PanelPP.UpdateMult() end
        -- The mini window was dragged and then closed: open with the panel on screen.
        if CUI._panelNudge then CUI._KeepPanelOnScreen() end
        -- Panel borders are resnapped by the tab-switch ResnapBordersUnder (active page only, ~2ms);
        -- a global ResnapAllBorders here costs ~74ms and is unnecessary, since non-panel borders have their own scale and resnap triggers.
        for _, fn in ipairs(_onShowCallbacks) do
            fn()
        end
        -- Controller cursor: every open is one the player asked for (slash, button,
        -- binding, pause menu), so bring the gamepad pointer up.
        if CUI.PadNative() then CUI.RaiseGamePadCursor() end
    end)
    panelFrame:SetScript("OnHide", function()
        -- Every close path (Escape, combat, the mini window's X) unfolds a collapsed
        -- window, so the next open is always the full panel. A parent hiding it
        -- (Alt-Z, a cinematic) leaves it shown: it stays folded and comes back as it was.
        if CUI._panelCollapsed and not panelFrame:IsShown() then CUI._SetPanelCollapsed(false) end
        -- Close the sidebar sync popup so it never lingers after the window is dismissed.
        CUI.CloseSyncPopup()
        if _onHideCallbacks then
            for _, fn in ipairs(_onHideCallbacks) do
                fn()
            end
        end
        -- Built pages stay cached for the session: frames can never be freed, so
        -- dropping them on close would only turn every revisit into a rebuild.
    end)

    -- Pixel-perfect scale: make 1 WoW unit = 1 screen pixel
    local physW = (GetPhysicalScreenSize())
    local baseScale = GetScreenWidth() / physW
    local userScale = (CludesUIDB and CludesUIDB.panelScale) or 1.0
    panelFrame:SetScale(baseScale * userScale)
    -- Initialize PanelPP mult for the saved user scale
    if CUI.PanelPP then CUI.PanelPP.UpdateMult() end

    CUI.RegisterEscapeClose(panelFrame)

    -- Panel body: every surface of the window hangs under it (parent panel-owned
    -- frames to CludesUI._panelBody, not to panelFrame), so collapsing hides the
    -- whole window while panelFrame -- the open options session -- stays shown.
    local body = CreateFrame("Frame", nil, panelFrame)
    body:SetAllPoints(panelFrame)
    body:SetFrameLevel(panelFrame:GetFrameLevel())
    CUI._panelBody = body

    -----------------------------------------------------------------------
    --  Background texture  (dual-layer crossfade for smooth transitions)
    -----------------------------------------------------------------------
    backdrop = CreateFrame("Frame", nil, body)
    backdrop:SetAllPoints(panelFrame)
    backdrop:SetFrameLevel(panelFrame:GetFrameLevel())
    backdrop:EnableMouse(false)
    backdrop:SetAlpha(1) -- panelFrame controls overall window opacity

    -- Permanent base background: backdrop shadow (always visible behind everything)
    local bgBase = backdrop:CreateTexture(nil, "BACKGROUND", nil, -1)
    bgBase:SetTexture(MEDIA_PATH .. "backgrounds\\cui-bg.png")
    bgBase:SetAllPoints()
    bgBase:SetAlpha(1)

    -- Two crossfade layers (A = current, B = incoming). Only the active layer holds a
    -- texture; the idle one is cleared after each transition to free GPU memory.
    local bgA = backdrop:CreateTexture(nil, "BACKGROUND", nil, 0)
    bgA:SetAllPoints()
    bgA:SetAlpha(1)

    local bgB = backdrop:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgB:SetAllPoints()
    bgB:SetAlpha(0)

    -- Track which layer is "front" (the one fading in)
    local frontBg, bgBack = bgA, bgB
    local bgFadeProgress = 1 -- 1 = fully transitioned (front is fully visible)
    local BG_FADE_DURATION = 0.5

    -- Title-bar theme boxes (the collapse button's box and the collapsed mini
    -- window): one table, so they cost this function a single local. See titleBoxes.Paint.
    local titleBoxes = {}

    -- Every theme's frame art is drawn as is: the flat frame is neutral and takes the
    -- theme's accent through its logo overlay and the controls, and CludesUI Forever
    -- has its own bronze art. So no layer is desaturated or tinted.
    function titleBoxes.TintColor() return nil end
    local function ApplyBgTintToLayer(layer, skinName, red, green, blue)
        local fr, fg, fb = titleBoxes.TintColor(skinName, red, green, blue)
        if fr then
            layer:SetDesaturated(true)
            layer:SetVertexColor(fr, fg, fb, 1)
        else
            layer:SetDesaturated(false)
            layer:SetVertexColor(1, 1, 1, 1)
        end
    end

    -- A colour picked off the art (r, g, b), as the art shows it under the theme's tint.
    function titleBoxes.Tinted(skinName, tr, tg, tb, red, green, blue)
        local fr, fg, fb = titleBoxes.TintColor(skinName, tr, tg, tb)
        if not fr then return red, green, blue end
        local lum = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return lum * fr, lum * fg, lum * fb
    end

    -- Active theme and its colour (the tint input), for painting outside a theme change.
    function titleBoxes.Theme()
        local skinName = ResolveFactionTheme(CludesUIDB and CludesUIDB.activeTheme or CUI.DEFAULT_THEME)
        return skinName, CUI.ResolveThemeColor(skinName)
    end

    -- Glyph cuts of CludesUI.RESIZE_ICON (texcoords), plus an optical nudge
    -- (x, y canvas units; y down): the expand arrow 1 toward its tail, the
    -- collapse arrow 1 right and 1 down. Field 7: size change from the art's
    -- glyph size (the collapse arrow 1 smaller).
    titleBoxes.GLYPH = {
        collapse = { 5 / 30, 15 / 30, 16 / 30, 26 / 30, 1, 1, -1 }, -- down-left
        expand = { 17 / 30, 27 / 30, 4 / 30, 14 / 30, -1, 1 }, -- up-right
    }

    -- Canvas distance from the painted close box to its copy (the collapse box).
    -- A multiple of 4 keeps the copy on the art's pixel grid at the 75% and 125%
    -- panel scales as well as at 100/150/200%, so its border matches the original.
    titleBoxes.DX = 48

    -- A theme box is a copy of the close box painted into the theme art
    -- (CludesUI.THEME_CLOSE_BOX), cut from the same art: its border as four
    -- strips (top and bottom carry the corners; the open centre shows the art
    -- below), dx canvas units left of the painted box, plus an arrow glyph in the
    -- X's colours. owner holds the textures; canvas point (ox, oy) sits on
    -- anchor's TOPLEFT. With no glyph it is a hover glow instead: the border
    -- ring alone, additive, in owner's highlight layer.
    function titleBoxes.New(owner, anchor, ox, oy, dx, glyph)
        local boxState = { anchor = anchor, ox = ox, oy = oy, dx = dx, glyph = glyph, alpha = 1, s = {} }
        for i = 1, 4 do
            local tex = owner:CreateTexture(nil, glyph and "BACKGROUND" or "HIGHLIGHT")
            if not glyph then tex:SetBlendMode("ADD") end
            boxState.s[i] = tex
        end
        if glyph then
            local tc = titleBoxes.GLYPH[glyph]
            local iconTex = CUI.RESIZE_ICON
            boxState.shadow = owner:CreateTexture(nil, "BORDER")
            boxState.base = owner:CreateTexture(nil, "BORDER")
            boxState.acc = owner:CreateTexture(nil, "BORDER")
            boxState.shadow:SetTexture(iconTex)
            boxState.base:SetTexture(iconTex)
            boxState.acc:SetTexture(iconTex)
            boxState.shadow:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            boxState.base:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            boxState.acc:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            boxState.shadow:SetVertexColor(0, 0, 0, 1)
            local acc = boxState.acc
            RegAccent({
                type = "callback",
                fn = function(red, green, blue) acc:SetVertexColor(red, green, blue, acc:GetAlpha()) end,
            })
        end
        return boxState
    end

    -- Draw order of a glyph set: strips at BACKGROUND stripSub, glyph pieces
    -- (rim, colour, accent) at BORDER glyphSub, +2, +4.
    function titleBoxes.Layer(boxState, stripSub, glyphSub)
        for i = 1, 4 do
            boxState.s[i]:SetDrawLayer("BACKGROUND", stripSub)
        end
        boxState.shadow:SetDrawLayer("BORDER", glyphSub)
        boxState.base:SetDrawLayer("BORDER", glyphSub + 2)
        boxState.acc:SetDrawLayer("BORDER", glyphSub + 4)
    end

    -- Show a set at alpha a (0 hides it). Texture alpha and vertex alpha are one
    -- channel, so every repaint ends here to put the set's alpha back.
    function titleBoxes.Alpha(boxState, a)
        boxState.alpha = a
        local artSpec = boxState.spec
        local shown = a > 0 and artSpec ~= nil
        for i = 1, 4 do
            local box = boxState.s[i]
            box:SetShown(shown)
            box:SetAlpha(a)
        end
        if boxState.base then
            boxState.base:SetShown(shown)
            boxState.base:SetAlpha(a)
            local sh = shown and artSpec.sh or 0
            boxState.shadow:SetShown(sh > 0)
            boxState.shadow:SetAlpha(sh * a)
            local acc = shown and artSpec.acc or 0
            boxState.acc:SetShown(acc > 0)
            boxState.acc:SetAlpha(acc * a)
        end
    end

    -- Paint a set from the theme's art (tr, tg, tb = the theme colour, the tint input).
    function titleBoxes.Paint(boxState, skinName, tr, tg, tb)
        local file = THEME_BG_FILES[skinName] or THEME_BG_FILES["CludesUI"]
        local artSpec = CUI.THEME_CLOSE_BOX[file]
        boxState.spec = artSpec
        if artSpec then
            local path = MEDIA_PATH .. file
            -- A copy takes the whole tight rect at a 6 unit depth (halo, border and
            -- inner line, clear of the X); a glow takes just the border line, so the
            -- flat fill and the corners outside the rounded border never light up.
            local x, rowY, w, h, S = artSpec.x, artSpec.y, artSpec.w, artSpec.h, 6
            if not boxState.base then
                x, rowY, w, h, S = artSpec.bx, artSpec.by, artSpec.bw, artSpec.bh, artSpec.bd
            end
            local px, py = x - boxState.dx - boxState.ox, rowY - boxState.oy
            for i = 1, 4 do
                local sx, sy, sw, sh = 0, 0, w, S -- top
                if i == 2 then
                    sy = h - S -- bottom
                elseif i == 3 then
                    sy, sw, sh = S, S, h - 2 * S -- left
                elseif i == 4 then
                    sx, sy, sw, sh = w - S, S, S, h - 2 * S -- right
                end
                local box = boxState.s[i]
                box:SetTexture(path)
                box:SetTexCoord(
                    (x + sx) / BG_WIDTH,
                    (x + sx + sw) / BG_WIDTH,
                    (rowY + sy) / BG_HEIGHT,
                    (rowY + sy + sh) / BG_HEIGHT
                )
                box:SetSize(sw, sh)
                box:ClearAllPoints()
                box:SetPoint("TOPLEFT", boxState.anchor, "TOPLEFT", px + sx, -(py + sy))
                ApplyBgTintToLayer(box, skinName, tr, tg, tb)
            end
            if boxState.base then
                local tc = titleBoxes.GLYPH[boxState.glyph]
                local cx, centerY =
                    artSpec.gx - boxState.dx + tc[5] - boxState.ox, artSpec.gy + tc[6] - boxState.oy
                local gs = (artSpec.gs or 16) + (tc[7] or 0) -- the rim is 2 units wider than the glyph
                boxState.shadow:SetSize(gs + 2, gs + 2)
                boxState.base:SetSize(gs, gs)
                boxState.acc:SetSize(gs, gs)
                boxState.shadow:ClearAllPoints()
                boxState.shadow:SetPoint("CENTER", boxState.anchor, "TOPLEFT", cx, -centerY)
                boxState.base:ClearAllPoints()
                boxState.base:SetPoint("CENTER", boxState.anchor, "TOPLEFT", cx, -centerY)
                boxState.acc:ClearAllPoints()
                boxState.acc:SetPoint("CENTER", boxState.anchor, "TOPLEFT", cx, -centerY)
                local red, green, blue =
                    titleBoxes.Tinted(skinName, tr, tg, tb, artSpec.r, artSpec.g, artSpec.b)
                boxState.base:SetVertexColor(red, green, blue, 1)
                boxState.acc:SetVertexColor(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 1)
            end
        end
        titleBoxes.Alpha(boxState, boxState.alpha)
    end

    -- Hover glow and tooltip for a title-bar box's hit area: the box border again,
    -- additive, shown by the button's highlight layer and brighter while pressed.
    -- Painted on enter from the art in use, so it costs nothing until hovered.
    function titleBoxes.Hover(button, anchor, ox, oy, dx, tip)
        local glow = titleBoxes.New(button, anchor, ox, oy, dx)
        button:SetScript("OnEnter", function(self)
            glow.alpha = 0.5
            titleBoxes.Paint(glow, titleBoxes.Theme())
            if tip then CUI.ShowWidgetTooltip(self, tip) end
        end)
        button:SetScript("OnLeave", function()
            if tip then CUI.HideWidgetTooltip() end
        end)
        button:SetScript("OnMouseDown", function() titleBoxes.Alpha(glow, 0.85) end)
        button:SetScript("OnMouseUp", function() titleBoxes.Alpha(glow, 0.5) end)
    end

    -- The collapse box: a front/back pair on backdrop that swaps and crossfades
    -- with the theme art it is cut from (ApplyThemeBG, bgFadeTicker).
    titleBoxes.front = titleBoxes.New(backdrop, backdrop, 0, 0, titleBoxes.DX, "collapse")
    titleBoxes.back = titleBoxes.New(backdrop, backdrop, 0, 0, titleBoxes.DX, "collapse")
    titleBoxes.Layer(titleBoxes.front, 4, 1)
    titleBoxes.Layer(titleBoxes.back, 3, 0)

    -- Background crossfade ticker: old stays solid, new fades in on top with the same
    -- ease-in-out curve as the accent transition, so both animations track visually.
    local bgFadeTicker = CreateFrame("Frame", nil, backdrop)
    bgFadeTicker:Hide()
    bgFadeTicker:SetScript("OnUpdate", function(self, timePassed)
        bgFadeProgress = bgFadeProgress + timePassed / BG_FADE_DURATION
        -- The accent overlay sits above both layers, so it is driven here only while
        -- a theme that has one is entering (dir 1) or leaving (dir -1).
        local overlay = backdrop._accentOverlayDir and backdrop._accentOverlay
        if bgFadeProgress >= 1 then
            bgFadeProgress = 1
            frontBg:SetAlpha(1)
            -- The collapse box pair is not occluded (its rect differs per art), so
            -- the outgoing one hides.
            titleBoxes.Alpha(titleBoxes.front, 1)
            titleBoxes.Alpha(titleBoxes.back, 0)
            -- bgBack stays solid behind bgFront (occluded, zero cost). NEVER clear it
            -- here (single-frame flash); the next ApplyThemeBG replaces its texture.
            if overlay then
                if backdrop._accentOverlayDir > 0 then
                    overlay:SetAlpha(1)
                else
                    -- Faded out over the new theme: empty it so it holds no texture.
                    overlay:Hide()
                    overlay:SetTexture(nil)
                    backdrop._accentOverlayPath = nil
                end
                backdrop._accentOverlayDir = nil
            end
            self:Hide()
        else
            -- Ease-in-out: slow start, fast middle, slow end
            local t = bgFadeProgress
            t = t < 0.5 and (2 * t * t) or (1 - (-2 * t + 2) * (-2 * t + 2) / 2)
            bgBack:SetAlpha(1)
            frontBg:SetAlpha(t)
            titleBoxes.Alpha(titleBoxes.front, t)
            -- The outgoing box stays near solid until late, like bgBack: a plain
            -- 1 - t leaves both boxes part-transparent mid-fade and they dim.
            titleBoxes.Alpha(titleBoxes.back, 1 - t * t * t)
            if overlay then
                local from = backdrop._accentOverlayFrom
                if backdrop._accentOverlayDir > 0 then
                    overlay:SetAlpha(from + (1 - from) * t)
                else
                    overlay:SetAlpha(from * (1 - t))
                end
            end
        end
    end)

    -- Accent overlay (CludesUI.THEME_ACCENT_OVERLAYS): one texture above the
    -- crossfade pair (BACKGROUND 2), on our own backdrop, tinted with the live UI
    -- accent through a single RegAccent entry made when it is created. It is built
    -- on the first apply of a theme that has one; a theme without one fades it out
    -- and empties it, so it costs nothing while unused. faded = false (the panel's
    -- first build) shows it at once instead of fading it in.
    local function ApplyThemeAccentOverlay(skinName, faded)
        local artSpec = CUI.THEME_ACCENT_OVERLAYS[skinName]
        local overlay = backdrop._accentOverlay
        if not artSpec then
            if overlay and overlay:IsShown() then
                backdrop._accentOverlayFrom = overlay:GetAlpha()
                backdrop._accentOverlayDir = -1
            end
            return
        end
        if not overlay then
            overlay = backdrop:CreateTexture(nil, "BACKGROUND", nil, 2)
            backdrop._accentOverlay = overlay
            overlay:SetVertexColor(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 1)
            -- A callback, not a "vertex" entry: on a texture the vertex alpha IS its
            -- alpha, and the vertex entry writes 1, which would stomp the crossfade
            -- (every theme pick re-applies the accent right after starting it).
            RegAccent({
                type = "callback",
                fn = function(red, green, blue) overlay:SetVertexColor(red, green, blue, overlay:GetAlpha()) end,
            })
        end
        local path = MEDIA_PATH .. artSpec.file
        -- A re-pick (or a return mid fade-out) keeps the art and fades on from its alpha.
        if not (overlay:IsShown() and backdrop._accentOverlayPath == path) then
            overlay:ClearAllPoints()
            overlay:SetPoint("TOPLEFT", backdrop, "TOPLEFT", artSpec.x, -artSpec.y)
            overlay:SetSize(artSpec.w, artSpec.h)
            overlay:SetTexture(path)
            backdrop._accentOverlayPath = path
            overlay:SetAlpha(0)
            overlay:Show()
        end
        if faded then
            backdrop._accentOverlayFrom = overlay:GetAlpha()
            backdrop._accentOverlayDir = 1
        else
            overlay:SetAlpha(1)
            backdrop._accentOverlayDir = nil
        end
    end

    --- Apply the full theme: crossfade to new background image + tint
    local function ApplyThemeBG(skinName, red, green, blue)
        skinName = ResolveFactionTheme(skinName)
        local file = THEME_BG_FILES[skinName] or THEME_BG_FILES["CludesUI"]
        local newPath = MEDIA_PATH .. file

        -- Swap roles: old front becomes back, new incoming becomes front
        bgBack, frontBg = frontBg, bgBack

        -- New front layer gets the target texture + tint on top; this SetTexture is also
        -- the lazy cleanup of the previous transition's idle layer.
        frontBg:SetTexture(newPath)
        ApplyBgTintToLayer(frontBg, skinName, red, green, blue)
        frontBg:SetDrawLayer("BACKGROUND", 1)
        frontBg:SetAlpha(0)

        -- Old layer stays fully solid underneath
        bgBack:SetDrawLayer("BACKGROUND", 0)
        bgBack:SetAlpha(1)

        -- The collapse box is cut from the same art: its pair swaps the same way.
        titleBoxes.front, titleBoxes.back = titleBoxes.back, titleBoxes.front
        titleBoxes.Layer(titleBoxes.front, 4, 1)
        titleBoxes.Layer(titleBoxes.back, 3, 0)
        titleBoxes.front.alpha = 0
        titleBoxes.Paint(titleBoxes.front, skinName, red, green, blue)
        titleBoxes.Alpha(titleBoxes.back, 1)
        -- A collapsed window shows the mini instead: it takes the new art at once.
        if CUI._panelCollapsed then titleBoxes.SkinMini(skinName, red, green, blue) end

        -- Start crossfade (the accent overlay, if either theme has one, rides it)
        bgFadeProgress = 0
        ApplyThemeAccentOverlay(skinName, true)
        bgFadeTicker:Show()

        -- The sidebar opacity slider's orientation follows the theme.
        if CUI._layoutOpacitySlider then CUI._layoutOpacitySlider() end
    end

    -- For tint-only updates (Custom Color picker dragging), update the front layer directly
    local function ApplyBgTint(red, green, blue)
        local skinName = ResolveFactionTheme((CludesUIDB or {}).activeTheme or CUI.DEFAULT_THEME)
        ApplyBgTintToLayer(frontBg, skinName, red, green, blue)
        titleBoxes.Paint(titleBoxes.front, skinName, red, green, blue)
        if CUI._panelCollapsed then titleBoxes.SkinMini(skinName, red, green, blue) end
    end

    -- Apply initial theme at creation (no crossfade, just set correct texture + tint)
    -- Resolve theme color directly -- CLUDES_GREEN is the UI accent which may differ
    local _initTheme = ResolveFactionTheme((CludesUIDB or {}).activeTheme or CUI.DEFAULT_THEME)
    local _initFile = THEME_BG_FILES[_initTheme] or THEME_BG_FILES["CludesUI"]
    local _initR, _initG, _initB = CUI.ResolveThemeColor(_initTheme)
    bgA:SetTexture(MEDIA_PATH .. _initFile)
    ApplyBgTintToLayer(bgA, _initTheme, _initR, _initG, _initB)
    titleBoxes.Paint(titleBoxes.front, _initTheme, _initR, _initG, _initB)
    ApplyThemeAccentOverlay(_initTheme, false)
    CUI._bgTexture = bgA
    CUI._applyBgTint = ApplyBgTint
    CUI._applyThemeBG = ApplyThemeBG

    -----------------------------------------------------------------------
    --  Click area  (1300x946, centred)
    -----------------------------------------------------------------------
    hitArea = CreateFrame("Frame", "CludesUIClickArea", body)
    CUI._clickArea = hitArea
    hitArea:SetSize(CLICK_W, CLICK_H)
    hitArea:SetPoint("CENTER", panelFrame, "CENTER", 0, 0)
    hitArea:SetFrameLevel(panelFrame:GetFrameLevel() + 1)
    hitArea:EnableMouse(true)
    hitArea:SetMovable(true)
    hitArea:RegisterForDrag("LeftButton")
    -- No SetClampedToScreen: the whole window moves as one and drags freely off any edge.
    hitArea:SetScript("OnDragStart", function() panelFrame:StartMoving() end)
    hitArea:SetScript("OnDragStop", function() panelFrame:StopMovingOrSizing() end)
    -- Shift + mouse wheel over any part of the panel without a wheel of its own (the
    -- header, the footer, the margins) scales it too; a plain wheel there does nothing.
    hitArea:EnableMouseWheel(true)
    hitArea:SetScript("OnMouseWheel", function(_, stepDelta) CUI._ShiftWheelScale(stepDelta) end)
    -- Controller cursor: the drag surface is not a stop; its children are.
    CUI.PadHint(hitArea, "nodepass")

    -----------------------------------------------------------------------
    --  Close button  (invisible hit area over background X graphic)
    -----------------------------------------------------------------------
    local closeBtn = CreateFrame("Button", nil, hitArea)
    closeBtn:SetSize(40, 40)
    closeBtn:SetPoint("TOPRIGHT", hitArea, "TOPRIGHT", -14, -11)
    closeBtn:SetFrameLevel(hitArea:GetFrameLevel() + 20)
    closeBtn:SetScript("OnClick", function() CUI:Hide() end)
    titleBoxes.Hover(closeBtn, backdrop, 0, 0, 0)
    -- Controller cursor: its cancel press closes the window through this button.
    if CUI.PadCP() then panelFrame.CloseButton = closeBtn end

    -----------------------------------------------------------------------
    --  Collapse button  (hit area over titleBoxes.front/back, left of the close X)
    --  and the mini window it folds the panel to
    -----------------------------------------------------------------------
    do
        local collapseBtn = CreateFrame("Button", nil, hitArea)
        collapseBtn:SetSize(40, 40)
        collapseBtn:SetPoint("TOPRIGHT", hitArea, "TOPRIGHT", -(titleBoxes.DX + 14), -11)
        collapseBtn:SetFrameLevel(hitArea:GetFrameLevel() + 20)
        collapseBtn:SetScript("OnClick", function() CUI._SetPanelCollapsed(true) end)
        titleBoxes.Hover(collapseBtn, backdrop, 0, 0, titleBoxes.DX, CUI.L("Collapse"))
    end

    -- Built on the first collapse. Every piece is a rect of art the panel already
    -- has loaded, drawn exactly where it sits on the panel, so nothing moves under
    -- the cursor: the bar is the panel's own top-right corner (its painted close
    -- box included) with its top rows flipped under it as the bottom edge, the
    -- expand box lands on the collapse box, and the badge is the painted logo
    -- emblem cut to a circle. No events and no OnUpdate.
    function titleBoxes.BuildMini()
        local MX, MY = 1206, 98 -- canvas point of the mini window's top-left
        local W, Hdr = 197, 76
        local MASK = MEDIA_PATH .. "portraits\\circle_mask.tga"
        local miniBox = CreateFrame("Frame", nil, panelFrame)
        miniBox:Hide()
        miniBox:SetSize(W, Hdr)
        miniBox:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", MX, -MY)
        miniBox:SetFrameLevel(panelFrame:GetFrameLevel() + 2)
        -- Composed as one image before the panel opacity applies, so at reduced
        -- opacity the stacked pieces (bar, ring, badge) never show through each other.
        miniBox:SetFlattensRenderLayers(true)
        miniBox:EnableMouse(true)
        miniBox:RegisterForDrag("LeftButton")
        miniBox:SetScript("OnDragStart", function() panelFrame:StartMoving() end)
        miniBox:SetScript("OnDragStop", function()
            panelFrame:StopMovingOrSizing()
            CUI._panelNudge = true
        end)
        CUI._panelMini = miniBox

        -- Shadow: the panel shadow around the same corner (rows 24-135) and those
        -- rows flipped below, symmetric about the bar's middle; the cut end fades.
        local shadowFile = MEDIA_PATH .. "backgrounds\\cui-bg.png"
        local fadeFrom, fadeTo = CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 1)
        for half = 0, 1 do
            for piece = 0, 1 do
                local x0 = (piece == 0) and 1244 or 1314
                local x1 = (piece == 0) and 1314 or 1480
                local top, bot = 24 / BG_HEIGHT, 136 / BG_HEIGHT
                if half == 1 then
                    top, bot = bot, top
                end
                local tex = miniBox:CreateTexture(nil, "BACKGROUND", nil, -8)
                tex:SetTexture(shadowFile)
                tex:SetTexCoord(x0 / BG_WIDTH, x1 / BG_WIDTH, top, bot)
                tex:SetSize(x1 - x0, 112)
                tex:SetPoint("TOPLEFT", miniBox, "TOPLEFT", x0 - MX, (half == 0) and 74 or -38)
                if piece == 0 then tex:SetGradient("HORIZONTAL", fadeFrom, fadeTo) end
            end
        end

        -- Bar: canvas 1244-1403 x 101-157, then rows 101-113 flipped as its bottom edge.
        local barTop = miniBox:CreateTexture(nil, "BACKGROUND", nil, 0)
        barTop:SetSize(159, 57)
        barTop:SetPoint("TOPLEFT", miniBox, "TOPLEFT", 1244 - MX, -(101 - MY))
        barTop:SetTexCoord(1244 / BG_WIDTH, 1403 / BG_WIDTH, 101 / BG_HEIGHT, 158 / BG_HEIGHT)
        local barCap = miniBox:CreateTexture(nil, "BACKGROUND", nil, 0)
        barCap:SetSize(159, 13)
        barCap:SetPoint("TOPLEFT", miniBox, "TOPLEFT", 1244 - MX, -(158 - MY))
        barCap:SetTexCoord(1244 / BG_WIDTH, 1403 / BG_WIDTH, 114 / BG_HEIGHT, 101 / BG_HEIGHT)
        local barOv = miniBox:CreateTexture(nil, "BACKGROUND", nil, 1)

        -- Expand box and its hit areas (the close X is the painted one in the bar).
        local expandBox = titleBoxes.New(miniBox, miniBox, MX, MY, titleBoxes.DX, "expand")
        titleBoxes.Layer(expandBox, 2, 0)
        local expandBtn = CreateFrame("Button", nil, miniBox)
        expandBtn:SetSize(40, 40)
        expandBtn:SetPoint("TOPLEFT", miniBox, "TOPLEFT", (1346 - titleBoxes.DX) - MX, -(115 - MY))
        expandBtn:SetFrameLevel(miniBox:GetFrameLevel() + 5)
        expandBtn:SetScript("OnClick", function() CUI._SetPanelCollapsed(false) end)
        titleBoxes.Hover(expandBtn, miniBox, MX, MY, titleBoxes.DX, CUI.L("Expand"))
        local miniClose = CreateFrame("Button", nil, miniBox)
        miniClose:SetSize(40, 40)
        miniClose:SetPoint("TOPLEFT", miniBox, "TOPLEFT", 1346 - MX, -(115 - MY))
        miniClose:SetFrameLevel(miniBox:GetFrameLevel() + 5)
        miniClose:SetScript("OnClick", function() CUI:Hide() end)
        titleBoxes.Hover(miniClose, miniBox, MX, MY, 0)

        -- Badge: a thin ring (a disc 2 units wider behind it) and the emblem square.
        local ring = miniBox:CreateTexture(nil, "ARTWORK", nil, 0)
        ring:SetSize(Hdr + 4, Hdr + 4)
        ring:SetPoint("CENTER", miniBox, "TOPLEFT", Hdr / 2, -Hdr / 2)
        local ringMask = miniBox:CreateMaskTexture()
        ringMask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ringMask:SetSize((Hdr + 4) * 128 / 104, (Hdr + 4) * 128 / 104) -- mask circle = 104/128
        ringMask:SetPoint("CENTER", ring, "CENTER")
        ring:AddMaskTexture(ringMask)
        local badge = miniBox:CreateTexture(nil, "ARTWORK", nil, 1)
        badge:SetSize(Hdr, Hdr)
        badge:SetPoint("TOPLEFT", miniBox, "TOPLEFT", 0, 0)
        local badgeOv = miniBox:CreateTexture(nil, "ARTWORK", nil, 2)
        local badgeMask = miniBox:CreateMaskTexture()
        badgeMask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        badgeMask:SetSize(Hdr * 128 / 104, Hdr * 128 / 104)
        badgeMask:SetPoint("CENTER", badge, "CENTER")
        badge:AddMaskTexture(badgeMask)
        badgeOv:AddMaskTexture(badgeMask)

        -- A theme's accent overlay (CludesUI.THEME_ACCENT_OVERLAYS) cut to the
        -- canvas rect x0,y0 - x1,y1 with canvas point (ax, ay) on the mini's
        -- TOPLEFT; hidden when the theme has none or the rect misses it.
        local function CutOverlay(texture, overlay, x0, y0, x1, y1, ax, ay)
            if overlay then
                x0, y0 = math.max(x0, overlay.x), math.max(y0, overlay.y)
                x1, y1 = math.min(x1, overlay.x + overlay.w), math.min(y1, overlay.y + overlay.h)
            end
            if not overlay or x1 <= x0 or y1 <= y0 then
                texture:Hide()
                return
            end
            texture:SetTexture(MEDIA_PATH .. overlay.file)
            texture:SetTexCoord(
                (x0 - overlay.x) / overlay.w,
                (x1 - overlay.x) / overlay.w,
                (y0 - overlay.y) / overlay.h,
                (y1 - overlay.y) / overlay.h
            )
            texture:SetSize(x1 - x0, y1 - y0)
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", miniBox, "TOPLEFT", x0 - ax, -(y0 - ay))
            texture:SetVertexColor(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 1)
            texture:Show()
        end
        RegAccent({
            type = "callback",
            fn = function(red, green, blue)
                barOv:SetVertexColor(red, green, blue, 1)
                badgeOv:SetVertexColor(red, green, blue, 1)
            end,
        })

        -- Re-skinned on each collapse (and on a theme change while collapsed).
        function titleBoxes.SkinMini(skinName, tr, tg, tb)
            local file = THEME_BG_FILES[skinName] or THEME_BG_FILES["CludesUI"]
            local artSpec = CUI.THEME_CLOSE_BOX[file] or CUI.THEME_CLOSE_BOX[THEME_BG_FILES["CludesUI"]]
            local path = MEDIA_PATH .. file
            barTop:SetTexture(path)
            ApplyBgTintToLayer(barTop, skinName, tr, tg, tb)
            barCap:SetTexture(path)
            ApplyBgTintToLayer(barCap, skinName, tr, tg, tb)
            local ex, ey = artSpec.ex, artSpec.ey
            badge:SetTexture(path)
            badge:SetTexCoord(ex / BG_WIDTH, (ex + Hdr) / BG_WIDTH, ey / BG_HEIGHT, (ey + Hdr) / BG_HEIGHT)
            ApplyBgTintToLayer(badge, skinName, tr, tg, tb)
            local rr, rg, rb = titleBoxes.Tinted(skinName, tr, tg, tb, artSpec.rr, artSpec.rg, artSpec.rb)
            ring:SetColorTexture(rr, rg, rb, 1)
            local overlay = CUI.THEME_ACCENT_OVERLAYS[skinName]
            CutOverlay(barOv, overlay, 1244, 101, 1403, 158, MX, MY)
            CutOverlay(badgeOv, overlay, ex, ey, ex + Hdr, ey + Hdr, ex, ey)
            titleBoxes.Paint(expandBox, skinName, tr, tg, tb)
        end
        return miniBox
    end

    -- Fold the window to the mini window (on) or back. panelFrame stays shown, so
    -- the options session goes on: no show/hide callback runs, and previews and
    -- editing sessions keep going. Popups that close on an outside click are
    -- closed by the click itself; the rest close here, and panel-owned surfaces
    -- parented outside the body follow through CludesUI:RegisterOnCollapse.
    function CUI._SetPanelCollapsed(on)
        local miniBox = CUI._panelMini
        local hooks = CUI._onCollapseCallbacks
        CUI.HideWidgetTooltip(true)
        if on then
            if CUI._panelCollapsed or not panelFrame:IsShown() then return end
            CUI._panelCollapsed = true
            CUI.CloseSyncPopup()
            -- Name/icon popups sit on UIParent with no click-off (the panel's own
            -- OnHide closes them for the same reason).
            if CUI._specOvNamePopup then CUI._specOvNamePopup:Hide() end
            local cond = CUI._CondOv
            if cond and cond._namePopup then cond._namePopup:Hide() end
            body:Hide()
            miniBox = miniBox or titleBoxes.BuildMini()
            titleBoxes.SkinMini(titleBoxes.Theme())
            miniBox:Show()
            for i = 1, #hooks do
                hooks[i](true)
            end
        elseif CUI._panelCollapsed then
            CUI._panelCollapsed = nil
            miniBox:Hide()
            body:Show()
            -- Unfolded by a close (panelFrame's OnHide): the OnHide callbacks take it
            -- from here, and a deferred page rebuild waits for the next open.
            if not panelFrame:IsShown() then return end
            -- Dropped somewhere else: keep the unfolded panel on screen.
            if CUI._panelNudge then CUI._KeepPanelOnScreen() end
            -- Pages are only ever built or re-read on screen (RefreshPage defers while folded).
            RunDeferredRefresh()
            for i = 1, #hooks do
                hooks[i](false)
            end
        end
    end

    -- Shift the window so the panel itself (the click area, not the art's shadow
    -- margin) is on screen; a panel taller or wider than the screen keeps its top
    -- left corner. Runs once after the mini window was dragged.
    function CUI._KeepPanelOnScreen()
        CUI._panelNudge = nil
        local l, r, t, b = hitArea:GetLeft(), hitArea:GetRight(), hitArea:GetTop(), hitArea:GetBottom()
        local ml, mb = panelFrame:GetLeft(), panelFrame:GetBottom()
        if not (l and r and t and b and ml and mb) then return end
        local isv = issecretvalue
        if isv and (isv(l) or isv(r) or isv(t) or isv(b) or isv(ml) or isv(mb)) then return end
        local uiScale = UIParent:GetEffectiveScale() / panelFrame:GetEffectiveScale()
        local sw, sh = UIParent:GetWidth() * uiScale, UIParent:GetHeight() * uiScale
        local dx, dy = 0, 0
        if r > sw then dx = sw - r end
        if l + dx < 0 then dx = -l end
        if b < 0 then dy = -b end
        if t + dy > sh then dy = sh - t end
        if dx ~= 0 or dy ~= 0 then
            panelFrame:ClearAllPoints()
            panelFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", ml + dx, mb + dy)
        end
    end
end

local function BuildSidebar()
    -----------------------------------------------------------------------
    --  Sidebar
    -----------------------------------------------------------------------
    navBar = CreateFrame("Frame", nil, hitArea)
    navBar:SetSize(SIDEBAR_W, CLICK_H)
    navBar:SetPoint("TOPLEFT", hitArea, "TOPLEFT", 0, 0)
    navBar:SetFrameLevel(hitArea:GetFrameLevel() + 2)
    CUI._sidebar = navBar

    -- Nav buttons -- start below the logo area with proper spacing
    local NAV_TOP = -114 -- distance from sidebar top to first nav item
    local NAV_ROW_H = 40 -- height per nav row (Layout Mode / Global / Profiles / Patch Notes)
    local NAV_ICON_W = 45 -- the 52x37 icon art drawn at 52:37 (45:32 is the
    local NAV_ICON_H = 32 -- nearest whole-pixel pair); even height centres on a 40px row
    local NAV_LEFT = 20 -- left padding for icon
    local NAV_TXT_GAP = 10 -- gap between icon and label

    -- Helper: create a 1px horizontal glow line on a sidebar button (TOP or BOTTOM edge)
    local function MakeNavEdgeLine(button, edge)
        local g = button:CreateTexture(nil, "BORDER")
        g:SetHeight(1)
        PanelPP.Point(g, edge .. "LEFT", button, edge .. "LEFT", 0, 0)
        PanelPP.Point(g, edge .. "RIGHT", button, edge .. "RIGHT", 0, 0)
        g:SetColorTexture(0.7, 0.7, 0.7, 1)
        g:SetGradient("HORIZONTAL", CreateColor(0.7, 0.7, 0.7, 0.5), CreateColor(0.7, 0.7, 0.7, 0))
        g:Hide()
        return g
    end

    -- Flat wash across a sidebar button, anchored top+bottom so it scales with
    -- the row height (group headers and child rows differ).
    local function MakeNavGradient(button, red, green, blue, startA)
        local texture = button:CreateTexture(nil, "BACKGROUND")
        texture:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        texture:SetColorTexture(red, green, blue, startA)
        texture:Hide()
        return texture
    end

    -- Helper: attach the shared decoration set to a sidebar nav button
    -- (active indicator, selection glow, top/bottom edge lines, hover glow, hover indicator)
    -- A nav row's icon and caption: the white icon (offPath) over a hidden
    -- accent-tinted glow copy of its lit version (onPath), then the dim
    -- caption to their right. Both paths are kept on the button for the
    -- selected/unselected swap. Returns the icon and the caption.
    local function AddNavIconAndLabel(button, onPath, offPath, caption)
        local glow = button:CreateTexture(nil, "ARTWORK", nil, 0)
        glow:SetTexture(onPath)
        glow:SetSize(NAV_ICON_W, NAV_ICON_H)
        glow:SetPoint("LEFT", button, "LEFT", NAV_LEFT, 0)
        glow:SetDesaturated(true)
        glow:SetVertexColor(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 1)
        glow:Hide()
        button._iconGlow = glow
        RegAccent({ type = "vertex", obj = glow })
        local iconTex = button:CreateTexture(nil, "ARTWORK", nil, 1)
        iconTex:SetTexture(offPath)
        iconTex:SetSize(NAV_ICON_W, NAV_ICON_H)
        iconTex:SetPoint("LEFT", button, "LEFT", NAV_LEFT, 0)
        button._icon = iconTex
        button._iconOn = onPath
        button._iconOff = offPath
        local navLabel = MakeFont(button, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        navLabel:SetPoint("LEFT", iconTex, "RIGHT", NAV_TXT_GAP, 0)
        navLabel:SetText(caption)
        button._label = navLabel
        return iconTex, navLabel
    end

    local function DecorateSidebarButton(button)
        local EG = CLUDES_GREEN
        button._indicator = SolidTex(button, "ARTWORK", EG.r, EG.g, EG.b, 1)
        button._indicator:SetWidth(3)
        button._indicator:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 0)
        button._indicator:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -1, 0)
        button._indicator:Hide()
        RegAccent({ type = "solid", obj = button._indicator, a = 1 })

        button._glow = MakeNavGradient(button, EG.r, EG.g, EG.b, 0.13)
        RegAccent({ type = "solid", obj = button._glow, a = 0.13 })
        button._glowTop = MakeNavEdgeLine(button, "TOP")
        button._glowBot = MakeNavEdgeLine(button, "BOTTOM")

        local hR, hG, hB = 0.85, 0.95, 0.90
        button._hoverGlow = MakeNavGradient(button, hR, hG, hB, 0.04)
        button._hoverIndicator = SolidTex(button, "ARTWORK", hR, hG, hB, 0.25)
        button._hoverIndicator:SetWidth(3)
        button._hoverIndicator:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 0)
        button._hoverIndicator:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -1, 0)
        button._hoverIndicator:Hide()
    end

    -- A fixed nav row (not an addon) at height y down the sidebar, with the
    -- shared row decoration.
    local function NewNavButton(rowY)
        local button = CreateFrame("Button", nil, navBar)
        button:SetSize(SIDEBAR_W, NAV_ROW_H)
        button:SetPoint("TOPLEFT", navBar, "TOPLEFT", 0, rowY)
        button:SetFrameLevel(navBar:GetFrameLevel() + 1)
        DecorateSidebarButton(button)
        return button
    end

    -- The resting look of a row that is always available: full caption
    -- colour and an undimmed icon.
    local function ShowNavEnabled(iconTex, navLabel)
        navLabel:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
        iconTex:SetDesaturated(false)
        iconTex:SetAlpha(NAV_ENABLED_ICON_A)
    end

    -------------------------------------------------------------------
    --  Unlock Mode button  (always top, not a module -- just triggers unlock)
    -------------------------------------------------------------------
    do
        local button = NewNavButton(NAV_TOP)

        local iconTex, navLabel = AddNavIconAndLabel(
            button,
            ICONS_PATH .. "sidebar\\unlockmode-ig-on.png",
            ICONS_PATH .. "sidebar\\unlockmode-ig.png",
            CUI.L("Layout Mode")
        )

        -- Always "loaded" appearance
        ShowNavEnabled(iconTex, navLabel)

        local hoverFill = SolidTex(button, "HIGHLIGHT", 1, 1, 1, 0)
        hoverFill:SetAllPoints()
        button:SetScript("OnEnter", function(self)
            hoverFill:SetAlpha(0.06)
            self._hoverGlow:Show()
            self._hoverIndicator:Show()
            self._label:SetTextColor(
                NAV_HOVER_ENABLED_TEXT.r,
                NAV_HOVER_ENABLED_TEXT.g,
                NAV_HOVER_ENABLED_TEXT.b,
                NAV_HOVER_ENABLED_TEXT.a
            )
        end)
        button:SetScript("OnLeave", function(self)
            hoverFill:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            self._label:SetTextColor(
                NAV_ENABLED_TEXT.r,
                NAV_ENABLED_TEXT.g,
                NAV_ENABLED_TEXT.b,
                NAV_ENABLED_TEXT.a
            )
        end)
        button:SetScript("OnClick", function()
            if CUI._openUnlockMode then
                CUI._unlockReturnModule = currentModule
                CUI._unlockReturnPage = activePage
                C_Timer.After(0, CUI._openUnlockMode)
            end
        end)

        CUI._unlockSidebarBtn = button
    end

    -------------------------------------------------------------------
    --  Global Settings button  (always second, not an addon)
    -------------------------------------------------------------------
    local GLOBAL_KEY = "_CUIGlobal"
    do
        local button = NewNavButton(NAV_TOP - NAV_ROW_H)

        local iconTex, navLabel = AddNavIconAndLabel(
            button,
            ICONS_PATH .. "sidebar\\settings-ig-on-2.png",
            ICONS_PATH .. "sidebar\\settings-ig-2.png",
            CUI.L("Global Settings")
        )

        -- No download icon for global settings
        local dlIcon = button:CreateTexture(nil, "ARTWORK")
        dlIcon:SetSize(18, 18)
        dlIcon:SetPoint("RIGHT", button, "RIGHT", -14, 0)
        dlIcon:Hide()
        button._dlIcon = dlIcon

        -- Always "loaded" -- global settings is built-in
        ShowNavEnabled(iconTex, navLabel)
        button._folder = GLOBAL_KEY
        button._loaded = true

        local hoverFill = SolidTex(button, "HIGHLIGHT", 1, 1, 1, 0)
        hoverFill:SetAllPoints()
        button:SetScript("OnEnter", function(self)
            if self._ovLocked then
                if CUI.ShowWidgetTooltip then
                    CUI.ShowWidgetTooltip(
                        self,
                        "This module can't be overridden. Exit the override editing session to open it."
                    )
                end
                return
            end
            hoverFill:SetAlpha(0.06)
            if currentModule ~= self._folder then
                self._hoverGlow:Show()
                self._hoverIndicator:Show()
                self._label:SetTextColor(
                    NAV_HOVER_ENABLED_TEXT.r,
                    NAV_HOVER_ENABLED_TEXT.g,
                    NAV_HOVER_ENABLED_TEXT.b,
                    NAV_HOVER_ENABLED_TEXT.a
                )
            end
        end)
        button:SetScript("OnLeave", function(self)
            if CUI.HideWidgetTooltip then CUI.HideWidgetTooltip() end
            if self._ovLocked then return end
            hoverFill:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            if currentModule ~= self._folder then
                self._label:SetTextColor(
                    NAV_ENABLED_TEXT.r,
                    NAV_ENABLED_TEXT.g,
                    NAV_ENABLED_TEXT.b,
                    NAV_ENABLED_TEXT.a
                )
            end
        end)
        button:SetScript("OnClick", function(self)
            if self._ovLocked then return end
            if moduleList[self._folder] then CUI:SelectModule(self._folder) end
        end)

        sidebarButtons[GLOBAL_KEY] = button
    end

    -------------------------------------------------------------------
    --  Patch Notes button  (own page -- selects the _CUIPatchNotes module)
    -------------------------------------------------------------------
    do
        local button = NewNavButton(NAV_TOP - NAV_ROW_H * 3)

        local iconTex, navLabel = AddNavIconAndLabel(
            button,
            ICONS_PATH .. "sidebar\\notes-on.png",
            ICONS_PATH .. "sidebar\\notes-off.png",
            CUI.L("Patch Notes")
        )

        ShowNavEnabled(iconTex, navLabel)

        button._folder = "_CUIPatchNotes"
        button._loaded = true

        local hoverFill = SolidTex(button, "HIGHLIGHT", 1, 1, 1, 0)
        hoverFill:SetAllPoints()
        button:SetScript("OnEnter", function(self)
            if self._ovLocked then
                if CUI.ShowWidgetTooltip then
                    CUI.ShowWidgetTooltip(
                        self,
                        "This module can't be overridden. Exit the override editing session to open it."
                    )
                end
                return
            end
            hoverFill:SetAlpha(0.06)
            if currentModule ~= self._folder then
                self._hoverGlow:Show()
                self._hoverIndicator:Show()
                self._label:SetTextColor(
                    NAV_HOVER_ENABLED_TEXT.r,
                    NAV_HOVER_ENABLED_TEXT.g,
                    NAV_HOVER_ENABLED_TEXT.b,
                    NAV_HOVER_ENABLED_TEXT.a
                )
            end
        end)
        button:SetScript("OnLeave", function(self)
            if CUI.HideWidgetTooltip then CUI.HideWidgetTooltip() end
            if self._ovLocked then return end
            hoverFill:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            if currentModule ~= self._folder then
                self._label:SetTextColor(
                    NAV_ENABLED_TEXT.r,
                    NAV_ENABLED_TEXT.g,
                    NAV_ENABLED_TEXT.b,
                    NAV_ENABLED_TEXT.a
                )
            end
        end)
        button:SetScript("OnClick", function(self)
            if self._ovLocked then return end
            -- Opening Patch Notes consumes the new-patch reminder dot; it
            -- re-arms only on the next version increase.
            if CludesUIDB and CludesUIDB.patchDotPending then
                CludesUIDB.patchDotPending = nil
                if CUI._UpdatePatchDot then CUI._UpdatePatchDot() end
            end
            if moduleList[self._folder] then CUI:SelectModule(self._folder) end
        end)

        -- Pulsing "new patch" dot: shown while patchDotPending is raised (version-increase
        -- stamp near CludesUI.VERSION) and patchDotDisabled is unset. Built lazily.
        local dotTex
        CUI._UpdatePatchDot = function()
            local show = CludesUIDB
                    and CludesUIDB.patchDotPending
                    and not CludesUIDB.patchDotDisabled
                    and true
                or false
            if not dotTex then
                if not show then return end
                dotTex = CreateFrame("Frame", nil, button)
                dotTex:SetFrameLevel(button:GetFrameLevel() + 5)
                dotTex:SetSize(9, 9)
                dotTex:SetPoint("RIGHT", button, "RIGHT", -14, 0)
                local tex = dotTex:CreateTexture(nil, "OVERLAY")
                tex:SetAllPoints()
                tex:SetColorTexture(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 1)
                CUI.RegAccent({ type = "solid", obj = tex, a = 1 })
                -- Round: run the solid color through the portrait circle mask.
                local mask = dotTex:CreateMaskTexture()
                mask:SetTexture(
                    "Interface\\AddOns\\CludesUI\\media\\portraits\\circle_mask.tga",
                    "CLAMPTOBLACKADDITIVE",
                    "CLAMPTOBLACKADDITIVE"
                )
                mask:SetAllPoints(tex)
                tex:AddMaskTexture(mask)
                local anim = dotTex:CreateAnimationGroup()
                anim:SetLooping("REPEAT")
                local a1 = anim:CreateAnimation("Alpha")
                a1:SetFromAlpha(1)
                a1:SetToAlpha(0.35)
                a1:SetDuration(0.7)
                a1:SetOrder(1)
                a1:SetSmoothing("IN_OUT")
                local a2 = anim:CreateAnimation("Alpha")
                a2:SetFromAlpha(0.35)
                a2:SetToAlpha(1)
                a2:SetDuration(0.7)
                a2:SetOrder(2)
                a2:SetSmoothing("IN_OUT")
                dotTex._ag = anim
            end
            dotTex:SetShown(show)
            if show then
                dotTex._ag:Play()
            else
                dotTex._ag:Stop()
            end
        end
        CUI._UpdatePatchDot()

        sidebarButtons["_CUIPatchNotes"] = button
        CUI._patchNotesSidebarBtn = button
    end

    -------------------------------------------------------------------
    --  Profiles button  (own page -- selects the _CUIProfiles module)
    -------------------------------------------------------------------
    do
        local button = NewNavButton(NAV_TOP - NAV_ROW_H * 2)

        local iconTex, navLabel = AddNavIconAndLabel(
            button,
            ICONS_PATH .. "sidebar\\profiles-on.png",
            ICONS_PATH .. "sidebar\\profiles-off.png",
            CUI.L("Profiles")
        )

        ShowNavEnabled(iconTex, navLabel)

        button._folder = "_CUIProfiles"
        button._loaded = true

        local hoverFill = SolidTex(button, "HIGHLIGHT", 1, 1, 1, 0)
        hoverFill:SetAllPoints()
        button:SetScript("OnEnter", function(self)
            if self._ovLocked then
                if CUI.ShowWidgetTooltip then
                    CUI.ShowWidgetTooltip(
                        self,
                        "This module can't be overridden. Exit the override editing session to open it."
                    )
                end
                return
            end
            hoverFill:SetAlpha(0.06)
            if currentModule ~= self._folder then
                self._hoverGlow:Show()
                self._hoverIndicator:Show()
                self._label:SetTextColor(
                    NAV_HOVER_ENABLED_TEXT.r,
                    NAV_HOVER_ENABLED_TEXT.g,
                    NAV_HOVER_ENABLED_TEXT.b,
                    NAV_HOVER_ENABLED_TEXT.a
                )
            end
        end)
        button:SetScript("OnLeave", function(self)
            if CUI.HideWidgetTooltip then CUI.HideWidgetTooltip() end
            if self._ovLocked then return end
            hoverFill:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            if currentModule ~= self._folder then
                self._label:SetTextColor(
                    NAV_ENABLED_TEXT.r,
                    NAV_ENABLED_TEXT.g,
                    NAV_ENABLED_TEXT.b,
                    NAV_ENABLED_TEXT.a
                )
            end
        end)
        button:SetScript("OnClick", function(self)
            if self._ovLocked then return end
            if moduleList[self._folder] then CUI:SelectModule(self._folder) end
        end)

        sidebarButtons["_CUIProfiles"] = button
        CUI._profilesSidebarBtn = button
    end

    -- First addon starts four rows down (Layout Mode, Global, Profiles, Patch Notes)
    local ORIG_ADDON_NAV_TOP = NAV_TOP - NAV_ROW_H * 4

    -----------------------------------------------------------------------
    --  Sidebar search bar (filters addon list by display name or page name)
    -----------------------------------------------------------------------
    local SB_TOP_PAD = 13 -- gap between CUI Legends and the search bar
    local SB_H = 28
    local SB_BOT_PAD = 6
    local SB_SIDE_INSET = 20
    local SB_TOTAL = SB_TOP_PAD + SB_H + SB_BOT_PAD

    local sidebarSearchFrame = CreateFrame("Frame", nil, navBar)
    sidebarSearchFrame:SetSize(SIDEBAR_W - SB_SIDE_INSET * 2, SB_H)
    sidebarSearchFrame:SetPoint(
        "TOPLEFT",
        navBar,
        "TOPLEFT",
        SB_SIDE_INSET + 2,
        ORIG_ADDON_NAV_TOP - SB_TOP_PAD
    )
    sidebarSearchFrame:SetFrameLevel(navBar:GetFrameLevel() + 3)

    local sbBg = SolidTex(
        sidebarSearchFrame,
        "BACKGROUND",
        CUI.SL_INPUT_R,
        CUI.SL_INPUT_G,
        CUI.SL_INPUT_B,
        CUI.SL_INPUT_A + 0.10
    )
    sbBg:SetAllPoints()
    local sbBrd =
        CUI.MakeRoundedBorder(sidebarSearchFrame, CUI.BORDER_R, CUI.BORDER_G, CUI.BORDER_B, 0.10, sbBg)

    local sidebarEdit = CreateFrame("EditBox", nil, sidebarSearchFrame)
    sidebarEdit:SetAllPoints()
    sidebarEdit:SetAutoFocus(false)
    sidebarEdit:SetFont(CUI.EXPRESSWAY, 13, "")
    sidebarEdit:SetTextColor(1, 1, 1, 1)
    sidebarEdit:SetTextInsets(10, 24, 0, 0)
    sidebarEdit:SetMaxLetters(40)

    local sbPlaceholder = MakeFont(sidebarSearchFrame, 12, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.3)
    sbPlaceholder:SetPoint("LEFT", sidebarSearchFrame, "LEFT", 10, 0)
    sbPlaceholder:SetText(CUI.L("Search Features..."))

    local clearSearchBtn = CreateFrame("Button", nil, sidebarSearchFrame)
    clearSearchBtn:SetSize(20, 20)
    clearSearchBtn:SetPoint("RIGHT", sidebarSearchFrame, "RIGHT", -4, 0)
    clearSearchBtn:SetFrameLevel(sidebarEdit:GetFrameLevel() + 2)
    clearSearchBtn:Hide()
    local sbClearLabel = MakeFont(clearSearchBtn, 15, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.35)
    sbClearLabel:SetPoint("CENTER")
    sbClearLabel:SetText("x")
    clearSearchBtn:SetScript("OnEnter", function() sbClearLabel:SetTextColor(1, 1, 1, 1) end)
    clearSearchBtn:SetScript(
        "OnLeave",
        function() sbClearLabel:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.35) end
    )
    clearSearchBtn:SetScript("OnClick", function()
        sidebarEdit:SetText("")
        sidebarEdit:ClearFocus()
    end)

    local function _sbBorderHover(a) sbBrd:SetColor(CUI.BORDER_R, CUI.BORDER_G, CUI.BORDER_B, a) end
    sidebarSearchFrame:SetScript("OnEnter", function() _sbBorderHover(0.15) end)
    sidebarSearchFrame:SetScript("OnLeave", function() _sbBorderHover(0.10) end)
    sidebarEdit:SetScript("OnEditFocusGained", function() _sbBorderHover(0.15) end)
    sidebarEdit:SetScript("OnEditFocusLost", function() _sbBorderHover(0.10) end)
    sidebarEdit:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    sidebarEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    CUI._sidebarSearchBox = sidebarEdit
    CUI._sidebarSearchText = ""

    sidebarEdit:SetScript("OnTextChanged", function(self)
        local textValue = self:GetText() or ""
        if textValue == "" then
            sbPlaceholder:Show()
            clearSearchBtn:Hide()
        else
            sbPlaceholder:Hide()
            clearSearchBtn:Show()
        end
        CUI._sidebarSearchText = textValue
        -- Deliberately NO sidebar filtering here: the global search results popup
        -- (CludesUI_GlobalSearch.lua) lists matches without reshuffling the nav.
    end)

    -- Addon scroll area sits below the search bar
    local ADDON_NAV_TOP = ORIG_ADDON_NAV_TOP - SB_TOTAL

    -----------------------------------------------------------------------
    --  Scrollable addon nav container
    --  The roster exceeds the space between ADDON_NAV_TOP and the class art, so addon
    --  buttons live in a ScrollFrame with smooth wheel scrolling and a thin right thumb.
    -----------------------------------------------------------------------
    local ADDON_VISIBLE_ROWS = 11 -- 40px rows; one less than before the CUI Legends row, so the viewport still ends at the same spot
    -- +30 = 20px viewport bonus plus 10px offsetting the SB_TOP_PAD bump, so growing the
    -- search-bar padding cannot shrink the viewport. ARROW_RESERVE = strip for the arrow.
    local ADDON_ARROW_RESERVE = 24
    local ADDON_SCROLL_H = ADDON_VISIBLE_ROWS * NAV_ROW_H - SB_TOTAL + 30 - ADDON_ARROW_RESERVE
    local ADDON_SCROLL_STEP = 60 -- match the main content scroll
    local ADDON_SMOOTH_SPEED = 12 -- match the main content scroll

    local addonScroller = CreateFrame("ScrollFrame", nil, navBar)
    addonScroller:SetWidth(SIDEBAR_W)
    addonScroller:SetHeight(ADDON_SCROLL_H)
    addonScroller:SetPoint("TOPLEFT", navBar, "TOPLEFT", 0, ADDON_NAV_TOP)
    addonScroller:SetFrameLevel(navBar:GetFrameLevel() + 1)
    addonScroller:EnableMouseWheel(true)
    addonScroller:SetClipsChildren(true)

    local addonScrollChild = CreateFrame("Frame", nil, addonScroller)
    addonScrollChild:SetWidth(SIDEBAR_W)
    -- Placeholder height; the button-build loop below sets the real value from
    -- cumulative GROUP_ROW_H / CHILD_ROW_H offsets.
    addonScrollChild:SetHeight(1)
    addonScroller:SetScrollChild(addonScrollChild)

    CUI._addonScrollFrame = addonScroller
    CUI._addonScrollChild = addonScrollChild

    -- Thin scrollbar thumb on the right edge of the scroll area
    local addonRail = CreateFrame("Frame", nil, addonScroller)
    addonRail:SetWidth(3)
    addonRail:SetPoint("TOPRIGHT", addonScroller, "TOPRIGHT", -2, -2)
    addonRail:SetPoint("BOTTOMRIGHT", addonScroller, "BOTTOMRIGHT", -2, 2)
    addonRail:SetFrameLevel(addonScroller:GetFrameLevel() + 3)
    local addonTrackBg = SolidTex(addonRail, "BACKGROUND", 1, 1, 1, 0.03)
    addonTrackBg:SetAllPoints()

    local addonThumb = SolidTex(addonRail, "ARTWORK", 1, 1, 1, 0.25)
    addonThumb:SetPoint("TOP", addonRail, "TOP", 0, 0)
    addonThumb:SetWidth(3)
    addonThumb:SetHeight(40)

    -- Scroll-to-bottom arrow below the viewport: dims at the bottom (or when the list
    -- does not scroll), click animates down. OnClick is wired below, once the
    -- smooth-scroll state locals exist. Alpha tiers live on the frame (ours to write).
    local arrowButton = CreateFrame("Button", nil, navBar)
    arrowButton:SetSize(22, 19)
    arrowButton:SetPoint("TOP", addonScroller, "BOTTOM", 0, -5)
    arrowButton:SetFrameLevel(navBar:GetFrameLevel() + 5)
    arrowButton:SetHitRectInsets(-12, -12, -6, -8)
    arrowButton._aEnabled, arrowButton._aDisabled, arrowButton._aHover = 0.7, 0.2, 1.0
    arrowButton._atBottom = false
    do
        local tex = arrowButton:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(ICONS_PATH .. "cui-arrow-down3.png")
        tex:SetAllPoints()
    end
    arrowButton:SetAlpha(arrowButton._aEnabled)
    arrowButton:SetScript("OnEnter", function(self)
        if not self._atBottom then self:SetAlpha(self._aHover) end
    end)
    arrowButton:SetScript(
        "OnLeave",
        function(self) self:SetAlpha(self._atBottom and self._aDisabled or self._aEnabled) end
    )
    CUI._addonScrollArrow = arrowButton

    local function SyncAddonThumb()
        local scrollMax = CUI.SafeScrollRange(addonScroller) or 0
        -- A shorter list (a group collapsed) pulls the offset back into range.
        if (tonumber(addonScroller:GetVerticalScroll()) or 0) > scrollMax then
            addonScroller:SetVerticalScroll(math.max(0, scrollMax))
        end
        -- Arrow state: dimmed when nothing is below. Runs before the no-scroll return.
        do
            local cur = tonumber(addonScroller:GetVerticalScroll()) or 0
            local atBottom = (scrollMax <= 0.5) or (cur >= scrollMax - 0.5)
            arrowButton._atBottom = atBottom
            if atBottom then
                arrowButton:SetAlpha(arrowButton._aDisabled)
            elseif arrowButton:IsMouseOver() then
                arrowButton:SetAlpha(arrowButton._aHover)
            else
                arrowButton:SetAlpha(arrowButton._aEnabled)
            end
        end
        if scrollMax <= 0 then
            addonRail:Hide()
            return
        end
        addonRail:Show()
        local trackH = addonRail:GetHeight()
        local visH = addonScroller:GetHeight()
        local ratio = visH / (visH + scrollMax)
        local thumbH = math.max(30, trackH * ratio)
        addonThumb:SetHeight(thumbH)
        local scrollRatio = (tonumber(addonScroller:GetVerticalScroll()) or 0) / scrollMax
        addonThumb:ClearAllPoints()
        addonThumb:SetPoint("TOP", addonRail, "TOP", 0, -(scrollRatio * (trackH - thumbH)))
    end

    -- Smooth mouse-wheel scroll (lerp towards target)
    local addonScrollTarget = 0
    local addonIsSmoothing = false
    local addonSmoothFrame = CreateFrame("Frame")
    addonSmoothFrame:Hide()
    -- Pixel-snap the scroll offset in EFFECTIVE-PIXEL space (not raw WoW units), like the
    -- main content scroll. Rounding in the direction of travel keeps the lerp monotonic
    -- so it never bounces at settlement. Fractional offsets leave glyphs on sub-pixel
    -- positions and the rasterizer picks different pixels per frame: 1px scroll jitter.
    addonSmoothFrame:SetScript("OnUpdate", function(_, timePassed)
        local cur = addonScroller:GetVerticalScroll()
        local scrollMax = CUI.SafeScrollRange(addonScroller) or 0
        local zoom = addonScroller:GetEffectiveScale()
        -- Snap max down to a pixel boundary so target can't exceed it.
        scrollMax = math.floor(scrollMax * zoom) / zoom
        addonScrollTarget = math.max(0, math.min(scrollMax, addonScrollTarget))
        local diff = addonScrollTarget - cur
        if math.abs(diff) < 0.3 then
            addonScroller:SetVerticalScroll(addonScrollTarget)
            SyncAddonThumb()
            addonIsSmoothing = false
            addonSmoothFrame:Hide()
            return
        end
        local nextScroll = cur + diff * math.min(1, ADDON_SMOOTH_SPEED * timePassed)
        nextScroll = math.max(0, math.min(scrollMax, nextScroll))
        if diff > 0 then
            nextScroll = math.ceil(nextScroll * zoom) / zoom
        else
            nextScroll = math.floor(nextScroll * zoom) / zoom
        end
        nextScroll = math.max(0, math.min(scrollMax, nextScroll))
        addonScroller:SetVerticalScroll(nextScroll)
        SyncAddonThumb()
    end)

    addonScroller:SetScript("OnMouseWheel", function(self, stepDelta)
        if CUI._ShiftWheelScale(stepDelta) then return end
        local scrollMax = CUI.SafeScrollRange(self) or 0
        if scrollMax <= 0 then return end
        local zoom = self:GetEffectiveScale()
        scrollMax = math.floor(scrollMax * zoom) / zoom
        local base = addonIsSmoothing and addonScrollTarget or self:GetVerticalScroll()
        local target = math.max(0, math.min(scrollMax, base - stepDelta * ADDON_SCROLL_STEP))
        -- Snap the resting target to a pixel boundary so settlement lands on an integer row offset.
        target = math.floor(target * zoom + 0.5) / zoom
        addonScrollTarget = math.min(target, scrollMax)
        if not addonIsSmoothing then
            addonIsSmoothing = true
            addonSmoothFrame:Show()
        end
    end)
    addonScroller:SetScript("OnScrollRangeChanged", SyncAddonThumb)
    addonScroller:HookScript("OnSizeChanged", SyncAddonThumb)
    -- Controller cursor: it scrolls the list itself to reach a row, so the thumb
    -- follows (the lerp already paints its own frames).
    if CUI.PadCP() then
        addonScroller:HookScript("OnVerticalScroll", function()
            if not addonIsSmoothing and not addonRail:GetScript("OnUpdate") then SyncAddonThumb() end
        end)
    end

    -- Arrow click: smooth-animate to the bottom, reusing the wheel's scroll state.
    arrowButton:SetScript("OnClick", function()
        local scrollMax = CUI.SafeScrollRange(addonScroller) or 0
        if scrollMax <= 0 then return end
        local zoom = addonScroller:GetEffectiveScale()
        scrollMax = math.floor(scrollMax * zoom) / zoom
        addonScrollTarget = scrollMax
        if not addonIsSmoothing then
            addonIsSmoothing = true
            addonSmoothFrame:Show()
        end
    end)

    -- Click/drag the scrollbar track: a click jumps to that position, holding drags.
    -- The visible track is 3px, so a wider invisible hit rect is added.
    addonRail:EnableMouse(true)
    addonRail:SetHitRectInsets(-8, -2, 0, 0)
    local function _scrollToCursor()
        local scrollMax = CUI.SafeScrollRange(addonScroller) or 0
        if scrollMax <= 0 then return end
        local trackH = addonRail:GetHeight()
        local thumbH = addonThumb:GetHeight()
        local travel = math.max(1, trackH - thumbH)
        local _, centerY = GetCursorPosition()
        local zoom = addonRail:GetEffectiveScale()
        local trackTop = addonRail:GetTop() or 0
        -- Center the thumb on the cursor, then clamp to travel range.
        local offset = (trackTop - centerY / zoom) - thumbH / 2
        offset = math.max(0, math.min(travel, offset))
        local rawScroll = (offset / travel) * scrollMax
        -- Snap to an effective-pixel boundary so labels land on exact pixels.
        local scale = addonScroller:GetEffectiveScale()
        local nextScroll = math.floor(rawScroll * scale + 0.5) / scale
        nextScroll = math.max(0, math.min(scrollMax, nextScroll))
        addonScrollTarget = nextScroll
        addonScroller:SetVerticalScroll(nextScroll)
        SyncAddonThumb()
    end
    addonRail:SetScript("OnMouseDown", function(self)
        _scrollToCursor()
        addonIsSmoothing = false
        addonSmoothFrame:Hide()
        self:SetScript("OnUpdate", _scrollToCursor)
    end)
    addonRail:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    addonRail:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    -- Controller cursor: a pointer-position control, never a stop.
    CUI.PadHint(addonRail, "nodeignore")

    -- Grouped-sidebar row heights (groups = text-only headers, children = indented rows
    -- with label + power), sized to fit all addons without scrolling. On CludesUI so
    -- RefreshSidebarStates reads the same values.
    CUI.SIDEBAR_GROUP_ROW_H = 28
    CUI.SIDEBAR_CHILD_ROW_H = 28 -- includes 6px air gap between addons
    CUI.SIDEBAR_GROUP_GAP = 10 -- extra vertical space between groups
    local GROUP_ROW_H = CUI.SIDEBAR_GROUP_ROW_H
    local CHILD_ROW_H = CUI.SIDEBAR_CHILD_ROW_H
    local CHILD_INDENT_X = NAV_LEFT + 16 -- label indent past the group label

    -- Register the addon-enable helper once (on CludesUI to avoid new upvalues).
    if not CUI._addonToggleInit then
        CUI._addonToggleInit = true
        CUI.IsAddonEnabled = function(name)
            if C_AddOns and C_AddOns.GetAddOnEnableState then
                return C_AddOns.GetAddOnEnableState(name) > 0
            end
            return true
        end
    end

    -- Create a group header row: the accent-colored label, then right after its
    -- text the quest tracker section headers' +/- art in the accent, shown only
    -- while the row is hovered. A click anywhere on the row collapses or
    -- expands the group; RefreshSidebarStates lays the rows out and sets the
    -- +/- for the saved state.
    local function CreateGroupHeader(navGroup)
        local line = CreateFrame("Button", nil, addonScrollChild)
        line:SetSize(SIDEBAR_W, GROUP_ROW_H)
        line:SetFrameLevel(addonScrollChild:GetFrameLevel() + 1)

        local EG = CLUDES_GREEN
        -- The label takes its text's width (one anchor), so the +/- follows the text.
        local navLabel = MakeFont(line, 15, nil, EG.r, EG.g, EG.b, 1)
        navLabel:SetPoint("LEFT", line, "LEFT", NAV_LEFT, 0)
        navLabel:SetWordWrap(false)
        navLabel:SetMaxLines(1)
        navLabel:SetText(CUI.L(navGroup.label))

        local toggleBtn = line:CreateTexture(nil, "ARTWORK")
        toggleBtn:SetSize(14, 14)
        toggleBtn:SetPoint("LEFT", navLabel, "RIGHT", 4, 0)
        toggleBtn:SetAtlas("ui-questtrackerbutton-secondary-collapse")
        toggleBtn:SetDesaturated(true)
        toggleBtn:SetVertexColor(EG.r, EG.g, EG.b, 1)
        toggleBtn:Hide()

        -- Hovering the row shows the +/- and lightens it and the label by 25%.
        local cr, cg, cb = EG.r, EG.g, EG.b
        local function Paint(lit)
            local m = lit and 1.25 or 1
            local red, green, blue = math.min(1, cr * m), math.min(1, cg * m), math.min(1, cb * m)
            navLabel:SetTextColor(red, green, blue, 1)
            toggleBtn:SetVertexColor(red, green, blue, 1)
            toggleBtn:SetShown(lit)
        end
        RegAccent({
            type = "callback",
            fn = function(red, green, blue)
                cr, cg, cb = red, green, blue
                Paint(line:IsMouseOver())
            end,
        })
        line:SetScript("OnEnter", function() Paint(true) end)
        line:SetScript("OnLeave", function() Paint(false) end)

        local entryKey = navGroup.key
        line:SetScript("OnClick", function() CUI_NS.ToggleSidebarGroup(entryKey) end)

        line._isGroup = true
        line._label = navLabel
        line._toggle = toggleBtn
        return line
    end

    -- Create a child (addon) row: indented label + power on the right, no left icon.
    local function CreateAddonChildRow(navInfo)
        local button = CreateFrame("Button", nil, addonScrollChild)
        button:SetSize(SIDEBAR_W, CHILD_ROW_H)
        button:SetFrameLevel(addonScrollChild:GetFrameLevel() + 1)

        DecorateSidebarButton(button)

        local navLabel = MakeFont(button, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        navLabel:SetPoint("LEFT", button, "LEFT", CHILD_INDENT_X, 0)
        navLabel:SetText(CUI.L(navInfo.display))
        button._label = navLabel

        -- Download icon (shown for uninstalled addons)
        local dlIcon = button:CreateTexture(nil, "ARTWORK")
        dlIcon:SetSize(18, 18)
        dlIcon:SetPoint("RIGHT", button, "RIGHT", -14, 0)
        dlIcon:SetTexture(ICONS_PATH .. "cui-download.png")
        dlIcon:SetDesaturated(true)
        dlIcon:SetAlpha(0.6)
        dlIcon:Hide()
        button._dlIcon = dlIcon

        -- Power toggle (hidden for comingSoon/maintenance/alwaysLoaded, and entirely in
        -- standalone builds: one module, which cannot toggle itself off).
        if
            not IS_STANDALONE
            and not navInfo.comingSoon
            and not navInfo.maintenance
            and not navInfo.alwaysLoaded
        then
            local pwrBtn = CreateFrame("Button", nil, button)
            pwrBtn:SetSize(13, 13)
            pwrBtn:SetPoint("RIGHT", button, "RIGHT", -18, 0)
            pwrBtn:SetFrameLevel(button:GetFrameLevel() + 5)
            local pwrTex = pwrBtn:CreateTexture(nil, "ARTWORK")
            pwrTex:SetAllPoints()
            pwrTex:SetTexture(ICONS_PATH .. "power.png")
            pwrTex:SetAlpha(0.75)
            pwrBtn._tex = pwrTex
            pwrBtn._folder = navInfo.folder
            pwrBtn._display = navInfo.display
            pwrBtn:SetScript("OnEnter", function(self)
                local isEnabled = IsAddonLoaded(self._folder)
                if isEnabled then
                    self._tex:SetVertexColor(0.824, 0.212, 0.212, 1)
                else
                    self._tex:SetVertexColor(0.212, 0.824, 0.325, 1)
                end
                if CUI.ShowWidgetTooltip then
                    CUI.ShowWidgetTooltip(
                        self,
                        isEnabled and "Disable " .. self._display or "Enable " .. self._display
                    )
                end
            end)
            pwrBtn:SetScript("OnLeave", function(self)
                local isEnabled = IsAddonLoaded(self._folder)
                self._tex:SetVertexColor(1, 1, 1, isEnabled and 1 or 0.5)
                if CUI.HideWidgetTooltip then CUI.HideWidgetTooltip() end
            end)
            pwrBtn:SetScript("OnClick", function(self)
                local isEnabled = IsAddonLoaded(self._folder)
                local action = isEnabled and "disable" or "enable"
                local moduleKey = self._folder
                CUI:ShowConfirmPopup({
                    title = CUI.Lf("%1$s Module", isEnabled and CUI.L("Disable") or CUI.L("Enable")),
                    message = CUI.Lf(
                        "Are you sure you want to %1$s %2$s?",
                        CUI.L(action),
                        CUI.L(self._display)
                    ),
                    confirmText = isEnabled and "Disable & Reload" or "Enable & Reload",
                    cancelText = "Cancel",
                    reload = true,
                    onConfirm = function()
                        if moduleKey == "CludesUIBags" and CludesUIDB then
                            CludesUIDB.bagsUserChosen = true
                        end
                        if isEnabled then
                            C_AddOns.DisableAddOn(moduleKey)
                        else
                            C_AddOns.EnableAddOn(moduleKey)
                        end
                    end,
                })
            end)
            button._pwrBtn = pwrBtn
        end

        -- Sync icon (to the left of power button, hidden for exempt/single-profile).
        -- Also hidden entirely in standalone builds (no cross-module sync surface).
        if
            not IS_STANDALONE
            and not navInfo.comingSoon
            and not navInfo.maintenance
            and not navInfo.plugin
            and not CUI._syncExempt[navInfo.folder]
        then
            local syncButton = CreateFrame("Button", nil, button)
            syncButton:SetSize(15, 15)
            if button._pwrBtn then
                syncButton:SetPoint("RIGHT", button._pwrBtn, "LEFT", -8, 0)
            else
                syncButton:SetPoint("RIGHT", button, "RIGHT", -20, 0)
            end
            syncButton:SetFrameLevel(button:GetFrameLevel() + 5)
            local syncTex = syncButton:CreateTexture(nil, "ARTWORK")
            syncTex:SetAllPoints()
            syncTex:SetTexture(CUI.SYNC_ICON)
            syncTex:SetVertexColor(1, 1, 1, 1)
            syncButton._tex = syncTex
            -- syncFolder/syncDisplay let an entry drive the sync of a DIFFERENT profile
            -- folder (Dragon Riding lives in the BlizzardSkin entry); the loaded check
            -- still uses info.folder, only the sync state/group target is redirected.
            local syncFolder = navInfo.syncFolder or navInfo.folder
            syncButton._folder = syncFolder
            syncButton._display = navInfo.syncDisplay or navInfo.display
            local SYNC_ON_R, SYNC_ON_G, SYNC_ON_B = 0x32 / 255, 0xbc / 255, 0x53 / 255
            local SYNC_HOVER_R = math.min(1, SYNC_ON_R * 1.25)
            local SYNC_HOVER_G = math.min(1, SYNC_ON_G * 1.25)
            local SYNC_HOVER_B = math.min(1, SYNC_ON_B * 1.25)
            local isGlobalOnly = CUI._syncGlobalOnly and CUI._syncGlobalOnly[navInfo.folder]
            local function RefreshSyncState()
                -- Hide the sync icon for disabled modules (no live settings to sync);
                -- same loaded check as the power button so the two stay consistent.
                if not IsAddonLoaded(navInfo.folder) then
                    syncButton:Hide()
                    return
                end
                -- Hide if only one profile exists
                local profCount = 0
                if CludesUIDB and CludesUIDB.profiles then
                    for _ in pairs(CludesUIDB.profiles) do
                        profCount = profCount + 1
                        if profCount > 1 then break end
                    end
                end
                if profCount <= 1 then
                    syncButton:Hide()
                    return
                end
                -- Green when the ACTIVE profile is a member of this module's sync group;
                -- dim white otherwise, including when a group exists without it.
                local activeProf = CludesUIDB and CludesUIDB.activeProfile or "Default"
                local activeSynced = isGlobalOnly or CUI.IsProfileSynced(syncFolder, activeProf)
                -- Check global hide settings
                if CludesUIDB then
                    if CludesUIDB.hideSyncIcons then
                        if CludesUIDB.hideSyncIconsOnlyFull then
                            if activeSynced then
                                syncButton:Hide()
                                return
                            end
                        else
                            syncButton:Hide()
                            return
                        end
                    end
                end
                syncButton:Show()
                if activeSynced then
                    syncTex:SetVertexColor(SYNC_ON_R, SYNC_ON_G, SYNC_ON_B, 1)
                else
                    syncTex:SetVertexColor(1, 1, 1, 0.5)
                end
            end
            RefreshSyncState()
            syncButton._refreshAlpha = RefreshSyncState
            -- Bulk-refresh registry (e.g. after profile deletion), keyed by folder so a
            -- sidebar rebuild overwrites the old closure instead of accumulating stale ones.
            if not CUI._syncRefreshFns then CUI._syncRefreshFns = {} end
            CUI._syncRefreshFns[navInfo.folder] = RefreshSyncState
            syncButton:SetScript("OnEnter", function(self)
                if isGlobalOnly then
                    self._tex:SetVertexColor(SYNC_HOVER_R, SYNC_HOVER_G, SYNC_HOVER_B, 1)
                    if CUI.ShowWidgetTooltip then
                        CUI.ShowWidgetTooltip(self, "No Profile Level Customizations")
                    end
                    return
                end
                local activeProf = CludesUIDB and CludesUIDB.activeProfile or "Default"
                local activeSynced = CUI.IsProfileSynced(self._folder, activeProf)
                if activeSynced then
                    self._tex:SetVertexColor(SYNC_HOVER_R, SYNC_HOVER_G, SYNC_HOVER_B, 1)
                else
                    self._tex:SetVertexColor(1, 1, 1, 1)
                end
                if CUI.ShowWidgetTooltip then
                    local tip = activeSynced and "Profile Synced" or "Sync " .. self._display
                    CUI.ShowWidgetTooltip(self, tip)
                end
            end)
            syncButton:SetScript("OnLeave", function(self)
                RefreshSyncState()
                if CUI.HideWidgetTooltip then CUI.HideWidgetTooltip() end
            end)
            syncButton:SetScript("OnClick", function(self)
                if isGlobalOnly then return end
                CUI.OpenSyncPopup(self._folder, self._display, self)
            end)
            button._syncBtn = syncButton
        end

        -- Bound the label to the leftmost right-side icon so long translated names
        -- ellipsize instead of overlapping the sync/power icons. The download icon always
        -- exists, so there is always a right anchor reserving the cluster's space.
        navLabel:SetJustifyH("LEFT")
        navLabel:SetWordWrap(false)
        navLabel:SetMaxLines(1)
        local rightEdge = button._syncBtn or button._pwrBtn or button._dlIcon
        if rightEdge then navLabel:SetPoint("RIGHT", rightEdge, "LEFT", -6, 0) end

        -- Default to unloaded appearance (refreshed each time panel opens)
        navLabel:SetTextColor(
            NAV_DISABLED_TEXT.r,
            NAV_DISABLED_TEXT.g,
            NAV_DISABLED_TEXT.b,
            NAV_DISABLED_TEXT.a
        )
        button._folder = navInfo.folder
        button._loaded = false
        button._alwaysLoaded = navInfo.alwaysLoaded or false
        button._comingSoon = navInfo.comingSoon or false
        button._maintenance = navInfo.maintenance or false

        local hoverFill = SolidTex(button, "HIGHLIGHT", 1, 1, 1, 0)
        hoverFill:SetAllPoints()
        button:SetScript("OnEnter", function(self)
            if self._comingSoon then
                if CUI.ShowWidgetTooltip then CUI.ShowWidgetTooltip(self, "Coming soon") end
                return
            end
            if self._maintenance then
                if CUI.ShowWidgetTooltip then CUI.ShowWidgetTooltip(self, "In Maintenance") end
                return
            end
            if self._ovLocked then
                if CUI.ShowWidgetTooltip then
                    CUI.ShowWidgetTooltip(
                        self,
                        "This module can't be overridden. Exit the override editing session to open it."
                    )
                end
                return
            end
            if self._notEnabled then return end
            hoverFill:SetAlpha(0.06)
            if currentModule ~= self._folder then
                self._hoverGlow:Show()
                self._hoverIndicator:Show()
                if self._loaded then
                    self._label:SetTextColor(
                        NAV_HOVER_ENABLED_TEXT.r,
                        NAV_HOVER_ENABLED_TEXT.g,
                        NAV_HOVER_ENABLED_TEXT.b,
                        NAV_HOVER_ENABLED_TEXT.a
                    )
                else
                    self._label:SetTextColor(
                        NAV_HOVER_DISABLED_TEXT.r,
                        NAV_HOVER_DISABLED_TEXT.g,
                        NAV_HOVER_DISABLED_TEXT.b,
                        NAV_HOVER_DISABLED_TEXT.a
                    )
                end
            end
        end)
        button:SetScript("OnLeave", function(self)
            if CUI.HideWidgetTooltip then CUI.HideWidgetTooltip() end
            if self._comingSoon then return end
            if self._maintenance then return end
            if self._ovLocked then return end
            if self._notEnabled then return end
            hoverFill:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            if currentModule ~= self._folder then
                if self._loaded then
                    self._label:SetTextColor(
                        NAV_ENABLED_TEXT.r,
                        NAV_ENABLED_TEXT.g,
                        NAV_ENABLED_TEXT.b,
                        NAV_ENABLED_TEXT.a
                    )
                else
                    self._label:SetTextColor(
                        NAV_DISABLED_TEXT.r,
                        NAV_DISABLED_TEXT.g,
                        NAV_DISABLED_TEXT.b,
                        NAV_DISABLED_TEXT.a
                    )
                end
            end
        end)
        button:SetScript("OnClick", function(self)
            if self._comingSoon then return end
            if self._maintenance then return end
            if self._ovLocked then return end
            if self._notEnabled then return end
            if self._loaded and moduleList[self._folder] then CUI:SelectModule(self._folder) end
        end)

        return button
    end

    -- Build the sidebar in group order; positions are assigned once and re-stacked by
    -- RefreshSidebarStates. Group/roster references go through
    -- the private CUI_NS model (one upvalue instead of one per name, keeps BuildSidebar well under the 60-upvalue cap);
    -- cumulative `_y` walks each row so group and child heights can differ.
    -- Outside addons' own groups and pages join the model first (see the Plugin API).
    CUI_NS.SyncExternal()
    local _y = 0
    local _groupHeaders = CUI_NS.sidebarGroupButtons
    local _infoByFolder = CUI_NS.navInfo
    local GROUP_GAP = CUI.SIDEBAR_GROUP_GAP
    for i, navGroup in ipairs(CUI_NS.navGroups) do
        if i > 1 then _y = _y + GROUP_GAP end
        local header = CreateGroupHeader(navGroup)
        header:SetPoint("TOPLEFT", addonScrollChild, "TOPLEFT", 0, -_y)
        _groupHeaders[navGroup.key] = header
        _y = _y + GROUP_ROW_H
        for _, moduleKey in ipairs(navGroup.members) do
            local navInfo = _infoByFolder[moduleKey]
            if navInfo then
                local button = CreateAddonChildRow(navInfo)
                button:SetPoint("TOPLEFT", addonScrollChild, "TOPLEFT", 0, -_y)
                sidebarButtons[navInfo.folder] = button
                _y = _y + CHILD_ROW_H
            end
        end
    end
    -- Row factories for plugin sections registered after the panel is built
    -- (the plugin registry creates their header and rows on the fly; positions
    -- come from the next RefreshSidebarStates).
    CUI_NS.CreateSidebarGroupHeader = CreateGroupHeader
    CUI_NS.CreateSidebarChildRow = CreateAddonChildRow
    -- The two functions below are public: a local pairs means setfenv on them
    -- cannot swap in one that is handed the private button table.
    local pairs = pairs
    -- Lock/unlock excluded modules during an override editing session: their settings cannot be
    -- captured, so the row grays out and blocks clicks. Called from the session enter/exit paths in CUI_SpecOverrides_Session.lua.
    CUI.RefreshSidebarOverrideLocks = function()
        local active = CUI.SpecOverrides_EditSessionActive and CUI.SpecOverrides_EditSessionActive() or false
        for moduleKey, button in pairs(sidebarButtons) do
            local lock = (
                active
                and CUI.SpecOverrides_ModuleExcluded
                and CUI.SpecOverrides_ModuleExcluded(moduleKey)
            ) or false
            if lock then
                -- Re-assert UNCONDITIONALLY: RefreshSidebarStates recolors every row by
                -- loaded state on module switches and would otherwise wash the lock out.
                button._ovLocked = true
                button._label:SetTextColor(
                    NAV_DISABLED_TEXT.r,
                    NAV_DISABLED_TEXT.g,
                    NAV_DISABLED_TEXT.b,
                    NAV_DISABLED_TEXT.a
                )
                if button._icon then
                    button._icon:SetDesaturated(true)
                    button._icon:SetAlpha(0.35)
                end
            elseif button._ovLocked then
                button._ovLocked = nil
                if button._loaded then
                    button._label:SetTextColor(
                        NAV_ENABLED_TEXT.r,
                        NAV_ENABLED_TEXT.g,
                        NAV_ENABLED_TEXT.b,
                        NAV_ENABLED_TEXT.a
                    )
                    if button._icon then
                        button._icon:SetDesaturated(false)
                        button._icon:SetAlpha(NAV_ENABLED_ICON_A)
                    end
                end
            end
        end
    end
    -- Refresh all sync icons (called from global settings toggle)
    CUI._refreshAllSyncIcons = function()
        for _, button in pairs(sidebarButtons) do
            if button._syncBtn and button._syncBtn._refreshAlpha then button._syncBtn._refreshAlpha() end
        end
    end
    addonScrollChild:SetHeight(_y)

    -- Class art (decorative, purely visual -- does not affect layout of any other element)
    do
        local artFile = CLASS_ART_MAP[playerClass] or "warrior.png"
        local classArt = navBar:CreateTexture(nil, "BACKGROUND", nil, -1)
        classArt:SetTexture(ICONS_PATH .. "sidebar\\class-accent\\" .. artFile)
        classArt:SetSize(156, 145)
        classArt:SetPoint("BOTTOM", navBar, "BOTTOM", 10, 200)
        classArt:SetAlpha(1)
    end

    -- Version text
    local versionText = MakeFont(navBar, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    versionText:SetPoint("BOTTOMLEFT", navBar, "BOTTOMLEFT", 18, 18)
    versionText:SetText("v" .. (CUI.VERSION or "1.0"))
    versionText:SetAlpha(0.5)

    ---------------------------------------------------------------------------
    --  Build deferred opacity slider: vertical above versionText in the
    --  sidebar, or horizontal beside it under the CludesUI and CludesUI
    --  Forever themes (their art shares one frame layout).
    --  The orientation follows the theme live (ApplyThemeBG re-lays it out).
    ---------------------------------------------------------------------------
    do
        local SLIDER_H = 60 -- vertical: track height
        local SLIDER_W = 90 -- horizontal: track length
        local THUMB_W = 14 -- thumb size across the track
        local THUMB_H = 8 -- thumb size along the track (thin bar)
        local TRACK_W = 2 -- thin track line
        local MIN_ALPHA = 0.50
        local MAX_ALPHA = 0.99
        local DEFAULT_A = 0.99
        local horizontal = false
        local currentAlpha = DEFAULT_A

        local opacityPanel = CreateFrame("Frame", nil, navBar)
        opacityPanel:SetFrameLevel(navBar:GetFrameLevel() + 5)

        -- Track background (thin line)
        local rail = opacityPanel:CreateTexture(nil, "BACKGROUND")
        rail:SetColorTexture(1, 1, 1, 0.10)

        -- Thumb (sits on top of track, hides the line behind it)
        local knob = CreateFrame("Frame", nil, opacityPanel)
        knob:SetFrameLevel(opacityPanel:GetFrameLevel() + 2)

        -- Thumb texture (ARTWORK layer, above track's BACKGROUND)
        local thumbTex = knob:CreateTexture(nil, "ARTWORK")
        thumbTex:SetAllPoints()
        thumbTex:SetColorTexture(1, 1, 1, 0.25)

        -- Solid blocker behind thumb to hide the track line
        local thumbBlocker = knob:CreateTexture(nil, "BORDER")
        thumbBlocker:SetPoint("TOPLEFT", thumbTex, "TOPLEFT", 0, 0)
        thumbBlocker:SetPoint("BOTTOMRIGHT", thumbTex, "BOTTOMRIGHT", 0, 0)
        thumbBlocker:SetColorTexture(DARK_BG.r, DARK_BG.g, DARK_BG.b, 1)

        -- Click on track to jump AND begin dragging immediately
        local trackFrame = CreateFrame("Button", nil, opacityPanel)
        trackFrame:SetFrameLevel(opacityPanel:GetFrameLevel())

        -- Track length along the slider axis (falls back before the first layout pass)
        local function TrackLength()
            local len = horizontal and rail:GetWidth() or rail:GetHeight()
            if not len or len < 1 then len = horizontal and SLIDER_W or SLIDER_H end
            return len
        end

        local function SetOpacity(alpha)
            alpha = math.max(MIN_ALPHA, math.min(MAX_ALPHA, alpha))
            currentAlpha = alpha
            panelFrame:SetAlpha(alpha)
            -- Thumb position: MIN at the bottom / left end, MAX at the top / right end
            local fraction = (alpha - MIN_ALPHA) / (MAX_ALPHA - MIN_ALPHA)
            local pos = fraction * (TrackLength() - THUMB_H)
            knob:ClearAllPoints()
            if horizontal then
                knob:SetPoint("LEFT", rail, "LEFT", pos, 0)
            else
                knob:SetPoint("BOTTOM", rail, "BOTTOM", 0, pos)
            end
        end

        -- Cursor position along the track as a 0..1 fraction (nil until the track has a size)
        local function CursorFrac()
            local curX, centerY = GetCursorPosition()
            local len = horizontal and rail:GetWidth() or rail:GetHeight()
            if not len or len < 1 then return nil end
            local origin = horizontal and rail:GetLeft() or rail:GetBottom()
            if not origin then return nil end
            local cur = (horizontal and curX or centerY) / opacityPanel:GetEffectiveScale()
            local fraction = (cur - origin - THUMB_H / 2) / (len - THUMB_H)
            return math.max(0, math.min(1, fraction))
        end

        -- Dragging (OnUpdate only while active); a click on the track jumps, then drags too
        local dragging = false
        local function StartDrag()
            dragging = true
            knob:SetScript("OnUpdate", function()
                if not dragging then return end
                local fraction = CursorFrac()
                if fraction then SetOpacity(MIN_ALPHA + fraction * (MAX_ALPHA - MIN_ALPHA)) end
            end)
        end
        local function StopDrag()
            dragging = false
            knob:SetScript("OnUpdate", nil)
        end
        knob:EnableMouse(true)
        knob:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then StartDrag() end
        end)
        knob:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then StopDrag() end
        end)
        trackFrame:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            local fraction = CursorFrac()
            if fraction then SetOpacity(MIN_ALPHA + fraction * (MAX_ALPHA - MIN_ALPHA)) end
            StartDrag()
        end)
        trackFrame:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then StopDrag() end
        end)

        -- Mouse wheel on the whole area
        opacityPanel:EnableMouseWheel(true)
        opacityPanel:SetScript("OnMouseWheel", function(self, stepDelta)
            if CUI._ShiftWheelScale(stepDelta) then return end
            local cur = panelFrame:GetAlpha()
            SetOpacity(cur + stepDelta * 0.05)
        end)

        -- Orientation from the active theme. Sizes resolve a frame after the
        -- anchors change, so the thumb is re-placed on the next frame.
        local function Layout()
            local skinName = CUI.GetActiveTheme()
            horizontal = (
                skinName == "CludesUI"
                or skinName == "CludesUI Forever"
                or skinName == "CludesUI Clean"
            )
            opacityPanel:ClearAllPoints()
            rail:ClearAllPoints()
            trackFrame:ClearAllPoints()
            if horizontal then
                opacityPanel:SetSize(SLIDER_W, THUMB_W + 4)
                opacityPanel:SetPoint("LEFT", versionText, "RIGHT", 10, 0)
                rail:SetSize(SLIDER_W, TRACK_W)
                rail:SetPoint("LEFT", opacityPanel, "LEFT", 0, 0)
                rail:SetPoint("RIGHT", opacityPanel, "RIGHT", 0, 0)
                knob:SetSize(THUMB_H, THUMB_W)
                trackFrame:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, THUMB_W / 2)
                trackFrame:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 0, -(THUMB_W / 2))
            else
                opacityPanel:SetSize(THUMB_W + 12, SLIDER_H + 26)
                opacityPanel:SetPoint("BOTTOM", versionText, "TOP", 0, 16)
                rail:SetSize(TRACK_W, SLIDER_H)
                rail:SetPoint("TOP", opacityPanel, "TOP", 0, -16)
                rail:SetPoint("BOTTOM", opacityPanel, "BOTTOM", 0, 0)
                knob:SetSize(THUMB_W, THUMB_H)
                trackFrame:SetPoint("TOPLEFT", rail, "TOPLEFT", -(THUMB_W / 2), 0)
                trackFrame:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", (THUMB_W / 2), 0)
            end
            C_Timer.After(0, function() SetOpacity(currentAlpha) end)
        end
        CUI._layoutOpacitySlider = Layout

        -- First layout; its deferred re-place applies DEFAULT_A once the track has a size.
        Layout()
    end

    -- CPU metric keys for the sidebar performance tracker
    local CPU_METRICS = {}
    if Enum and Enum.AddOnProfilerMetric then
        CPU_METRICS = {
            {
                key = "SessionAvg",
                enum = Enum.AddOnProfilerMetric.SessionAverageTime,
                label = "Session Avg",
            },
            {
                key = "RecentAvg",
                enum = Enum.AddOnProfilerMetric.RecentAverageTime,
                label = "Recent Avg",
            },
            {
                key = "EncounterAvg",
                enum = Enum.AddOnProfilerMetric.EncounterAverageTime,
                label = "Encounter Avg",
            },
            {
                key = "Last",
                enum = Enum.AddOnProfilerMetric.LastTime,
                label = "Last",
            },
            {
                key = "Peak",
                enum = Enum.AddOnProfilerMetric.PeakTime,
                label = "Peak",
            },
        }
    end

    local function GatherCUICPU()
        local cpuByKey = {}
        for _, metric in ipairs(CPU_METRICS) do
            cpuByKey[metric.key] = 0
        end
        for _, navInfo in ipairs(ADDON_ROSTER) do
            if IsAddonLoaded(navInfo.folder) then
                if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric then
                    for _, metric in ipairs(CPU_METRICS) do
                        cpuByKey[metric.key] = cpuByKey[metric.key]
                            + (C_AddOnProfiler.GetAddOnMetric(navInfo.folder, metric.enum) or 0)
                    end
                end
            end
        end
        return cpuByKey
    end

    -- Resource usage tracker (CPU for all CUI addons). Only ticks while the panel is
    -- visible: parented to sidebar, a descendant of panelFrame (hidden frames never tick).

    local resCpuText = MakeFont(navBar, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    resCpuText:SetPoint("BOTTOMRIGHT", navBar, "BOTTOMRIGHT", -20, 18)
    resCpuText:SetJustifyH("RIGHT")
    resCpuText:SetAlpha(0.5)

    local resCpuLabel = MakeFont(navBar, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    resCpuLabel:SetPoint("BOTTOMRIGHT", resCpuText, "TOPRIGHT", 0, 3)
    resCpuLabel:SetJustifyH("RIGHT")
    resCpuLabel:SetAlpha(0.5)
    resCpuLabel:SetText(CUI.L("CPU Usage:"))

    local resPerfLabel = MakeFont(navBar, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    resPerfLabel:SetPoint("BOTTOMRIGHT", resCpuLabel, "TOPRIGHT", 0, 11)
    resPerfLabel:SetJustifyH("RIGHT")
    resPerfLabel:SetAlpha(0.5)
    resPerfLabel:SetText(CUI.L("All CUI Addons"))

    local resDivider = navBar:CreateTexture(nil, "ARTWORK")
    resDivider:SetColorTexture(1, 1, 1, 0.15)
    resDivider:SetHeight(1)
    resDivider:SetPoint("BOTTOMRIGHT", resPerfLabel, "BOTTOMRIGHT", 0, -5)
    resDivider:SetPoint("BOTTOMLEFT", resPerfLabel, "BOTTOMLEFT", 0, -5)

    local RES_UPDATE_INTERVAL = 5
    local UpdateResourceText

    UpdateResourceText = function()
        local cpuByKey = GatherCUICPU()
        local cpuVal = cpuByKey["RecentAvg"] or 0
        if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric then
            local fps = GetFramerate() or 0
            local pct = 0
            if fps > 0 then pct = cpuVal / (1000 / fps) * 100 end
            resCpuText:SetText(
                CUI.COLOR_CODES.WHITE .. string.format("%.3f MS (%.1f%%)", cpuVal, pct) .. "|r"
            )
        else
            resCpuText:SetText("|cffffffffN/A|r")
        end
    end

    local resUpdateFrame = CreateFrame("Frame", nil, navBar)
    local resTicker
    resUpdateFrame:SetScript("OnShow", function()
        UpdateResourceText()
        if not resTicker then resTicker = C_Timer.NewTicker(RES_UPDATE_INTERVAL, UpdateResourceText) end
    end)
    resUpdateFrame:SetScript("OnHide", function()
        if resTicker then
            resTicker:Cancel()
            resTicker = nil
        end
    end)
end

-- The public header API below iterates private tables; a local pairs means setfenv on it
-- cannot swap in one that is handed those tables.
local function BuildContent()
    local pairs = pairs
    -----------------------------------------------------------------------
    --  Right-side content region
    -----------------------------------------------------------------------
    local rightX = SIDEBAR_W
    local rightW = CLICK_W - SIDEBAR_W -- 1030

    -- Header  (module title + description, sits over the banner artwork)
    headerFrame = CreateFrame("Frame", nil, hitArea)
    headerFrame:SetSize(rightW, HEADER_H)
    headerFrame:SetPoint("TOPLEFT", hitArea, "TOPLEFT", rightX, 0)
    headerFrame:SetFrameLevel(hitArea:GetFrameLevel() + 3)

    local headerTitle = MakeFont(headerFrame, 36, "", 1, 1, 1)
    headerTitle:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", CONTENT_PAD, -35)
    headerFrame._title = headerTitle

    local headerDesc = MakeFont(headerFrame, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    headerDesc:SetPoint("TOPLEFT", headerTitle, "BOTTOMLEFT", 2, -12)
    headerDesc:SetWidth(rightW - CONTENT_PAD * 2)
    headerDesc:SetJustifyH("LEFT")
    headerFrame._desc = headerDesc

    -----------------------------------------------------------------------
    --  Tab bar  (sits below the header, above scrollable content)
    -----------------------------------------------------------------------
    tabStrip = CreateFrame("Frame", nil, hitArea)
    tabStrip:SetSize(rightW, TAB_BAR_H)
    tabStrip:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", -9, 0)
    tabStrip:SetFrameLevel(hitArea:GetFrameLevel() + 4)

    tabStrip._tabButtons = {}
    CUI._tabBar = tabStrip

    -----------------------------------------------------------------------
    --  Content header  (optional non-scrolling region above the scroll area)
    --  Modules call CludesUI:SetContentHeader(buildFunc) to populate it.
    --  buildFunc(frame, width) should build UI into frame and return height.
    -----------------------------------------------------------------------
    local contentBaseTop = HEADER_H + TAB_BAR_H
    local contentMaxH = CLICK_H - contentBaseTop - FOOTER_H

    headStrip = CreateFrame("Frame", nil, hitArea)
    PanelPP.Size(headStrip, rightW, 1)
    PanelPP.Point(headStrip, "TOPLEFT", hitArea, "TOPLEFT", rightX, -contentBaseTop)
    headStrip:SetFrameLevel(hitArea:GetFrameLevel() + 4)
    headStrip:EnableMouseWheel(true)
    headStrip:SetScript("OnMouseWheel", function(_, stepDelta)
        if contentScroll then contentScroll:GetScript("OnMouseWheel")(contentScroll, stepDelta) end
    end)
    headStrip:SetClipsChildren(true)
    headStrip:Hide()
    CUI._contentHeader = headStrip
    local contentHeaderH = 0 -- current header height

    -- Subtle background tint (only visible when header is active)
    local contentHeaderBg = headStrip:CreateTexture(nil, "BACKGROUND")
    contentHeaderBg:SetColorTexture(0, 0, 0, 0.1)
    PanelPP.DisablePixelSnap(contentHeaderBg)
    contentHeaderBg:SetAllPoints()

    -- 1px divider at the bottom edge of the content header
    local contentHeaderDiv = headStrip:CreateTexture(nil, "OVERLAY")
    contentHeaderDiv:SetColorTexture(1, 1, 1, 0.06)
    PanelPP.DisablePixelSnap(contentHeaderDiv)
    PanelPP.Point(contentHeaderDiv, "BOTTOMLEFT", headStrip, "BOTTOMLEFT", 0, 0)
    PanelPP.Point(contentHeaderDiv, "BOTTOMRIGHT", headStrip, "BOTTOMRIGHT", 0, 0)
    contentHeaderDiv:SetHeight(1)

    local function LayoutContent()
        local wasSuppressed = suppressScrollRangeChanged
        suppressScrollRangeChanged = true

        contentScroll:ClearAllPoints()
        PanelPP.Point(
            contentScroll,
            "TOPLEFT",
            hitArea,
            "TOPLEFT",
            rightX,
            -(contentBaseTop + contentHeaderH)
        )
        -- Anchor bottom to footer top so WoW resolves height from both edges, avoiding
        -- the PanelPP.Point vs PanelPP.Height rounding mismatch (1px flicker at the
        -- scroll area's bottom edge when the content header height changes).
        if footerBar then
            PanelPP.Point(contentScroll, "BOTTOMRIGHT", footerBar, "TOPRIGHT", 0, 0)
        else
            local newH = contentMaxH - contentHeaderH
            PanelPP.Height(contentScroll, newH)
        end

        suppressScrollRangeChanged = wasSuppressed
        UpdateScrollThumb()
    end

    -----------------------------------------------------------------------
    --  Scrollable content area
    -----------------------------------------------------------------------
    contentScroll = CreateFrame("ScrollFrame", "CludesUIScrollFrame", hitArea)
    CUI._scrollFrame = contentScroll
    PanelPP.Size(contentScroll, rightW, contentMaxH)
    PanelPP.Point(contentScroll, "TOPLEFT", hitArea, "TOPLEFT", rightX, -contentBaseTop)
    contentScroll:SetFrameLevel(hitArea:GetFrameLevel() + 3)
    contentScroll:EnableMouseWheel(true)
    -- Clip children to the viewport so off-screen widgets are skipped; without it every
    -- widget on the page renders each frame regardless of scroll position.
    contentScroll:SetClipsChildren(true)

    contentChild = CreateFrame("Frame", nil, contentScroll)
    PanelPP.Size(contentChild, rightW, 1)
    contentScroll:SetScrollChild(contentChild)

    -- Thin scrollbar  (hidden when content fits)
    local thumbRail = CreateFrame("Frame", nil, contentScroll)
    thumbRail:SetWidth(4)
    thumbRail:SetPoint("TOPRIGHT", contentScroll, "TOPRIGHT", -12, -4)
    thumbRail:SetPoint("BOTTOMRIGHT", contentScroll, "BOTTOMRIGHT", -12, 4)
    thumbRail:SetFrameLevel(contentScroll:GetFrameLevel() + 1)
    thumbRail:Hide()

    local trackBg = SolidTex(thumbRail, "BACKGROUND", 1, 1, 1, 0.02)
    trackBg:SetAllPoints()

    local thumbKnob = CreateFrame("Button", nil, thumbRail)
    thumbKnob:SetWidth(4)
    thumbKnob:SetHeight(60)
    thumbKnob:SetPoint("TOP", thumbRail, "TOP", 0, 0)
    thumbKnob:SetFrameLevel(thumbRail:GetFrameLevel() + 1)
    thumbKnob:EnableMouse(true)
    -- Register for drag so the thumb captures drag events before hitArea
    thumbKnob:RegisterForDrag("LeftButton")
    thumbKnob:SetScript("OnDragStart", function() end)
    thumbKnob:SetScript("OnDragStop", function() end)

    -- Invisible wider hit area so the scrollbar is easier to grab
    local scrollHit = CreateFrame("Button", nil, contentScroll)
    scrollHit:SetWidth(16)
    scrollHit:SetPoint("TOPRIGHT", contentScroll, "TOPRIGHT", -6, -4)
    scrollHit:SetPoint("BOTTOMRIGHT", contentScroll, "BOTTOMRIGHT", -6, 4)
    scrollHit:SetFrameLevel(thumbRail:GetFrameLevel() + 2)
    scrollHit:EnableMouse(true)
    scrollHit:RegisterForDrag("LeftButton")
    scrollHit:SetScript("OnDragStart", function() end)
    scrollHit:SetScript("OnDragStop", function() end)

    local thumbTex = SolidTex(thumbKnob, "ARTWORK", 1, 1, 1, 0.27)
    thumbTex:SetAllPoints()

    local SCROLL_STEP = 60
    local SMOOTH_SPEED = 12 -- lerp speed (higher = snappier, 10-15 feels good)
    local isDragging = false
    local dragStartY, dragStartScroll

    -- Smooth scroll state
    scrollTarget = 0
    smoothing = false

    local function EndScrollDrag()
        if not isDragging then return end
        isDragging = false
        thumbKnob:SetScript("OnUpdate", nil)
    end

    UpdateScrollThumb = function()
        local scrollMax = CUI.SafeScrollRange(contentScroll)
        if scrollMax <= 0 then
            thumbRail:Hide()
            return
        end
        thumbRail:Show()
        local trackH = thumbRail:GetHeight()
        local visH = contentScroll:GetHeight()
        local visibleRatio = visH / (visH + scrollMax)
        local thumbH = math.max(30, trackH * visibleRatio)
        thumbKnob:SetHeight(thumbH)
        local scrollRatio = (tonumber(contentScroll:GetVerticalScroll()) or 0) / scrollMax
        local maxThumbTravel = trackH - thumbH
        thumbKnob:ClearAllPoints()
        thumbKnob:SetPoint("TOP", thumbRail, "TOP", 0, -(scrollRatio * maxThumbTravel))
    end

    -- Smooth scroll OnUpdate: lerp toward scrollTarget then stop
    smoother = CreateFrame("Frame")
    smoother:Hide()
    smoother:SetScript("OnUpdate", function(_, timePassed)
        local cur = contentScroll:GetVerticalScroll()
        local scrollMax = CUI.SafeScrollRange(contentScroll)
        -- Snap max downward so we never try to scroll past a pixel-aligned boundary
        local zoom = contentScroll:GetEffectiveScale()
        scrollMax = math.floor(scrollMax * zoom) / zoom
        -- Re-clamp target in case scroll range changed
        scrollTarget = math.max(0, math.min(scrollMax, scrollTarget))
        local diff = scrollTarget - cur
        if math.abs(diff) < 0.3 then
            -- Close enough -- snap to target and stop
            contentScroll:SetVerticalScroll(scrollTarget)
            UpdateScrollThumb()
            smoothing = false
            smoother:Hide()
            return
        end
        local nextScroll = cur + diff * math.min(1, SMOOTH_SPEED * timePassed)
        -- Clamp to valid range
        nextScroll = math.max(0, math.min(scrollMax, nextScroll))
        -- Round toward the target so the last frames approach monotonically, never bouncing
        if diff > 0 then
            nextScroll = math.ceil(nextScroll * zoom) / zoom
        else
            nextScroll = math.floor(nextScroll * zoom) / zoom
        end
        -- Re-clamp after rounding (ceil could push past max)
        nextScroll = math.max(0, math.min(scrollMax, nextScroll))
        contentScroll:SetVerticalScroll(nextScroll)
        UpdateScrollThumb()
    end)

    local function SmoothScrollTo(target)
        local scrollMax = CUI.SafeScrollRange(contentScroll)
        local zoom = contentScroll:GetEffectiveScale()
        -- Snap max downward so target never exceeds a pixel-aligned boundary
        scrollMax = math.floor(scrollMax * zoom) / zoom
        scrollTarget = math.max(0, math.min(scrollMax, target))
        -- Snap target to pixel boundary so content is pixel-perfect at rest
        scrollTarget = math.floor(scrollTarget * zoom + 0.5) / zoom
        -- Re-clamp after snapping (rounding could push above max)
        scrollTarget = math.min(scrollTarget, scrollMax)
        if not smoothing then
            smoothing = true
            smoother:Show()
        end
    end
    CUI.SmoothScrollTo = SmoothScrollTo

    -- Current content scroll offset: the in-flight target while animating, else the
    -- settled position. Lets callers capture and restore scroll across a page rebuild.
    function CUI.GetContentScroll()
        if smoothing then return scrollTarget or 0 end
        return (contentScroll and tonumber(contentScroll:GetVerticalScroll())) or 0
    end

    contentScroll:SetScript("OnMouseWheel", function(self, stepDelta)
        if CUI._ShiftWheelScale(stepDelta) then return end
        local scrollMax = CUI.SafeScrollRange(self)
        if scrollMax <= 0 then return end
        -- Accumulate on top of the current target (not current position) for responsive chained scrolls
        local base = smoothing and scrollTarget or self:GetVerticalScroll()
        SmoothScrollTo(base - stepDelta * SCROLL_STEP)
    end)
    contentScroll:SetScript("OnScrollRangeChanged", function(self)
        if suppressScrollRangeChanged then return end
        -- An offset past the new range would strand the view: the thumb hides
        -- and the wheel ignores a zero range, so pull it back in.
        local scrollMax = CUI.SafeScrollRange(self)
        if (tonumber(self:GetVerticalScroll()) or 0) > scrollMax then
            self:SetVerticalScroll(scrollMax)
            if scrollTarget > scrollMax then scrollTarget = scrollMax end
        end
        UpdateScrollThumb()
    end)

    local function ScrollThumbOnUpdate(self)
        -- Auto-release when mouse button is no longer held
        if not IsMouseButtonDown("LeftButton") then
            EndScrollDrag()
            return
        end
        -- Cancel any smooth animation during drag
        smoothing = false
        smoother:Hide()
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / self:GetEffectiveScale()
        local deltaY = dragStartY - cursorY
        local trackH = thumbRail:GetHeight()
        local maxThumbTravel = trackH - self:GetHeight()
        if maxThumbTravel <= 0 then return end
        local scrollMax = CUI.SafeScrollRange(contentScroll)
        local nextScroll =
            math.max(0, math.min(scrollMax, dragStartScroll + (deltaY / maxThumbTravel) * scrollMax))
        -- Snap to whole pixels to prevent sub-pixel widget jitter
        local zoom = contentScroll:GetEffectiveScale()
        nextScroll = math.floor(nextScroll * zoom + 0.5) / zoom
        scrollTarget = nextScroll
        contentScroll:SetVerticalScroll(nextScroll)
        UpdateScrollThumb()
    end

    thumbKnob:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        smoothing = false
        smoother:Hide()
        isDragging = true
        local _, cursorY = GetCursorPosition()
        dragStartY = cursorY / self:GetEffectiveScale()
        dragStartScroll = contentScroll:GetVerticalScroll()
        self:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    thumbKnob:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        EndScrollDrag()
    end)

    -- Hit area: click to jump + drag (same as track click but with wider target)
    scrollHit:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        -- Cancel any smooth animation
        smoothing = false
        smoother:Hide()
        local scrollMax = CUI.SafeScrollRange(contentScroll)
        if scrollMax <= 0 then return end
        -- Jump to cursor position
        local _, centerY = GetCursorPosition()
        centerY = centerY / thumbRail:GetEffectiveScale()
        local top = thumbRail:GetTop() or 0
        local trackH = thumbRail:GetHeight()
        local thumbH = thumbKnob:GetHeight()
        if trackH <= thumbH then return end
        local fraction = (top - centerY - thumbH / 2) / (trackH - thumbH)
        fraction = math.max(0, math.min(1, fraction))
        local nextScroll = fraction * scrollMax
        local zoom = contentScroll:GetEffectiveScale()
        nextScroll = math.floor(nextScroll * zoom + 0.5) / zoom
        scrollTarget = nextScroll
        contentScroll:SetVerticalScroll(nextScroll)
        UpdateScrollThumb()
        -- Begin dragging via thumb
        isDragging = true
        dragStartY = centerY
        dragStartScroll = nextScroll
        thumbKnob:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    scrollHit:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        EndScrollDrag()
    end)
    -- Controller cursor: pointer-position controls are never stops, and its own
    -- scrolling of the content moves the thumb (the lerp and drag paint their own).
    CUI.PadHint(thumbKnob, "nodeignore")
    CUI.PadHint(scrollHit, "nodeignore")
    if CUI.PadCP() then
        contentScroll:HookScript("OnVerticalScroll", function()
            if not smoothing and not isDragging then UpdateScrollThumb() end
        end)
    end

    contentFrame = contentChild

    -----------------------------------------------------------------------
    --  Content header API  (non-scrolling region above scroll area)
    -----------------------------------------------------------------------
    local _contentHeaderCache = {} -- keyed by "module::page"
    local _chStash = CreateFrame("Frame") -- hidden off-screen stash for cached header children
    _chStash:Hide()

    -- Page reuse: a suite page's header is built into its own kept root
    -- (CUI_NS.hdr, a frame of the page pool covering the header frame) that every
    -- later build dresses again; the roots are hidden here, never detached. Every
    -- other header (plugin and outside pages, every page while reuse is off) is
    -- built into the header frame itself and dropped or stashed as always.
    local function ClearContentHeaderInner()
        local Hdr = CUI_NS.hdr
        local isRoot = Hdr.isRoot
        local ch = { headStrip:GetChildren() }
        for _, child in ipairs(ch) do
            child:Hide()
            if not isRoot[child] then child:SetParent(nil) end
        end
        local rg = { headStrip:GetRegions() }
        for _, r in ipairs(rg) do
            if r ~= contentHeaderBg and r ~= contentHeaderDiv then
                r:Hide()
                r:SetParent(nil)
            end
        end
        -- The root that showed is cleared like the header frame's own parts
        -- (stale until built again); a saved root keeps its parts. What still
        -- shows over it (an open popup) is pinned first, before the header
        -- collapses under it (Pool.Pin, CludesUI_FramePool.lua).
        local activeFlag = Hdr.active
        if activeFlag then
            if CUI_NS.PoolPin then CUI_NS.PoolPin(activeFlag) end
            Hdr.stale[isRoot[activeFlag]] = true
            CUI_NS.DropRootForeign(activeFlag)
            Hdr.active = nil
        end
        headStrip:Hide()
        headStrip:SetHeight(1)
        contentHeaderH = 0
        LayoutContent()
    end

    -- Cache the content header's children/regions, reparented to a hidden stash so
    -- ClearContentHeaderInner cannot destroy them while clearing for other pages.
    -- A kept root is only hidden, its height kept for the restore.
    local function SaveContentHeaderToCache(pageKey)
        if not headStrip:IsShown() then return false end
        local Hdr = CUI_NS.hdr
        local rootFrame = Hdr.roots[pageKey]
        if rootFrame and Hdr.active == rootFrame then
            rootFrame:Hide()
            -- what still shows over it stays put while the header collapses
            if CUI_NS.PoolPin then CUI_NS.PoolPin(rootFrame) end
            Hdr.active = nil
            Hdr.height[pageKey] = contentHeaderH
            headStrip:Hide()
            headStrip:SetHeight(1)
            contentHeaderH = 0
            LayoutContent()
            return true
        end
        local children = {}
        for _, child in ipairs({ headStrip:GetChildren() }) do
            if not Hdr.isRoot[child] then children[#children + 1] = child end
        end
        local regions = {}
        for _, r in ipairs({ headStrip:GetRegions() }) do
            if r ~= contentHeaderBg and r ~= contentHeaderDiv then regions[#regions + 1] = r end
        end
        if #children == 0 and #regions == 0 then return false end
        -- Move children and regions to stash so ClearContentHeaderInner can't touch them
        for _, c in ipairs(children) do
            c:Hide()
            c:SetParent(_chStash)
        end
        for _, r in ipairs(regions) do
            r:Hide()
            r:SetParent(_chStash)
        end
        _contentHeaderCache[pageKey] = {
            children = children,
            regions = regions,
            height = contentHeaderH,
        }
        headStrip:Hide()
        headStrip:SetHeight(1)
        contentHeaderH = 0
        LayoutContent()
        return true
    end

    -- Restore a previously saved content header from cache. A kept root shows
    -- again with each part's own shown state; a stale one returns false, so the
    -- page and its header are built again together.
    local function RestoreContentHeaderFromCache(pageKey)
        local Hdr = CUI_NS.hdr
        local rootFrame = Hdr.roots[pageKey]
        if rootFrame and Hdr.height[pageKey] ~= nil then
            if Hdr.stale[pageKey] then return false end
            for _, child in ipairs({ headStrip:GetChildren() }) do
                child:Hide()
            end
            for _, r in ipairs({ headStrip:GetRegions() }) do
                if r ~= contentHeaderBg and r ~= contentHeaderDiv then r:Hide() end
            end
            rootFrame:Show()
            Hdr.active = rootFrame
            headStrip:Show()
            contentHeaderH = Hdr.height[pageKey]
            PanelPP.Height(headStrip, contentHeaderH)
            LayoutContent()
            return true
        end
        local record = _contentHeaderCache[pageKey]
        if not record then return false end
        -- Hide any current header children first (without orphaning)
        local ch = { headStrip:GetChildren() }
        for _, child in ipairs(ch) do
            child:Hide()
        end
        local rg = { headStrip:GetRegions() }
        for _, r in ipairs(rg) do
            if r ~= contentHeaderBg and r ~= contentHeaderDiv then r:Hide() end
        end
        -- Reparent cached children and regions back to headStrip and show
        for _, c in ipairs(record.children) do
            c:SetParent(headStrip)
            c:Show()
        end
        for _, r in ipairs(record.regions) do
            r:SetParent(headStrip)
            r:Show()
        end
        headStrip:Show()
        contentHeaderH = record.height
        PanelPP.Height(headStrip, record.height)
        LayoutContent()
        return true
    end

    -- Stashed headers are dropped; kept roots are marked stale (the one showing
    -- stays until its next build dresses it again).
    local function InvalidateContentHeaderCache()
        for entryKey, record in pairs(_contentHeaderCache) do
            for _, c in ipairs(record.children) do
                c:Hide()
                c:SetParent(nil)
            end
            for _, r in ipairs(record.regions) do
                r:Hide()
                r:SetParent(nil)
            end
            _contentHeaderCache[entryKey] = nil
        end
        -- (the stashed copies' parts are dropped at once, as above; the root that
        -- shows keeps its parts until its rebuild clears them)
        local Hdr = CUI_NS.hdr
        for entryKey, rootFrame in pairs(Hdr.roots) do
            Hdr.stale[entryKey] = true
            if rootFrame ~= Hdr.active then CUI_NS.DropRootForeign(rootFrame) end
        end
    end

    -- One page's header only (search-sensitive pages, CludesUI._InvalidateSearchSensitive).
    function CUI_NS.InvalidateHeaderKey(entryKey)
        local record = _contentHeaderCache[entryKey]
        if record then
            for _, c in ipairs(record.children) do
                c:Hide()
                c:SetParent(nil)
            end
            for _, r in ipairs(record.regions) do
                r:Hide()
                r:SetParent(nil)
            end
            _contentHeaderCache[entryKey] = nil
        end
        local Hdr = CUI_NS.hdr
        local rootFrame = Hdr.roots[entryKey]
        if rootFrame then
            Hdr.stale[entryKey] = true
            if rootFrame ~= Hdr.active then CUI_NS.DropRootForeign(rootFrame) end
        end
    end

    function CUI:SetContentHeader(buildFunc)
        ClearContentHeaderInner()
        headStrip:Show()
        -- A suite page under page reuse builds into its kept root: the header
        -- frame's size, and its frame level, so the builders' level math holds.
        local entryKey = CUI_NS.HeaderReuseKey and CUI_NS.HeaderReuseKey()
        local target = headStrip
        if entryKey then
            local Hdr = CUI_NS.hdr
            -- A saved root built again drops its old parts first, as above.
            if Hdr.roots[entryKey] then CUI_NS.DropRootForeign(Hdr.roots[entryKey]) end
            local rootFrame = CUI_NS.PoolKept(CUI_NS.headerOwner, entryKey, "Frame", headStrip)
            rootFrame:SetAllPoints(headStrip)
            rootFrame:SetFrameLevel(headStrip:GetFrameLevel())
            Hdr.roots[entryKey] = rootFrame
            Hdr.isRoot[rootFrame] = entryKey
            Hdr.active = rootFrame
            target = rootFrame
        end
        local h = buildFunc(target, rightW) or 0
        contentHeaderH = h
        PanelPP.Height(headStrip, h)
        if entryKey then
            local Hdr = CUI_NS.hdr
            Hdr.height[entryKey] = h
            Hdr.stale[entryKey] = nil
            -- dev mode: an idle pooled object left showing on the kept root
            if CUI_NS.PoolDevEndPass then CUI_NS.PoolDevEndPass(target, entryKey) end
        end
        LayoutContent()
    end

    function CUI:UpdateContentHeaderHeight(h)
        if not headStrip:IsShown() then return end
        local oldActualH = headStrip:GetHeight()
        -- Save scroll state BEFORE ApplyContentLayout, which may clobber it
        -- if WoW returns a stale scroll range after the resize.
        local savedScroll = contentScroll and contentScroll:GetVerticalScroll() or 0
        local savedTarget = scrollTarget
        contentHeaderH = h
        PanelPP.Height(headStrip, h)
        -- Use the ACTUAL height change after PixelUtil snapping, not the requested
        -- delta: rounding to physical pixels at the frame's effective scale makes the
        -- real change differ from h-oldH by a sub-pixel amount (1px content shift).
        local newActualH = headStrip:GetHeight()
        local stepDelta = newActualH - oldActualH
        LayoutContent()
        -- The scroll frame moved by |delta| px; scroll content the same to hold the viewport.
        if stepDelta ~= 0 and contentScroll then
            local adjusted = math.max(0, savedScroll + stepDelta)
            contentScroll:SetVerticalScroll(adjusted)
            if smoothing then
                scrollTarget = math.max(0, savedTarget + stepDelta)
            else
                scrollTarget = adjusted
            end
            UpdateScrollThumb()
        end
    end

    -- Silent variant: resizes the header with no scroll compensation, for cosmetic
    -- height changes (buff icons toggled) that must not jump the scroll.
    function CUI:SetContentHeaderHeightSilent(h)
        if not headStrip:IsShown() then return end
        contentHeaderH = h
        PanelPP.Height(headStrip, h)
        LayoutContent()
    end

    function CUI:ClearContentHeader() ClearContentHeaderInner() end

    -- Lightweight hide (no orphaning), for when the header is already cached.
    -- A kept root hidden this way is built again before it shows (stale), as a
    -- hidden header never reached the stash; its parts go as the next clear
    -- would have dropped them.
    function CUI:HideContentHeader()
        local Hdr = CUI_NS.hdr
        local activeFlag = Hdr.active
        if activeFlag then
            Hdr.stale[Hdr.isRoot[activeFlag]] = true
            CUI_NS.DropRootForeign(activeFlag)
            Hdr.active = nil
        end
        local ch = { headStrip:GetChildren() }
        for _, child in ipairs(ch) do
            child:Hide()
        end
        local rg = { headStrip:GetRegions() }
        for _, r in ipairs(rg) do
            if r ~= contentHeaderBg and r ~= contentHeaderDiv then r:Hide() end
        end
        -- what still shows over the root stays put while the header collapses
        if activeFlag and CUI_NS.PoolPin then CUI_NS.PoolPin(activeFlag) end
        headStrip:Hide()
        headStrip:SetHeight(1)
        contentHeaderH = 0
        LayoutContent()
    end

    -- Expose cache functions for SelectPage (outside CreateMainFrame scope)
    function CUI:SaveContentHeaderToCache(pageKey) return SaveContentHeaderToCache(pageKey) end
    function CUI:RestoreContentHeaderFromCache(pageKey) return RestoreContentHeaderFromCache(pageKey) end
    function CUI:InvalidateContentHeaderCache() InvalidateContentHeaderCache() end

    return rightW, rightX
end

local function BuildFooter(rightW, rightX)
    -----------------------------------------------------------------------
    --  Footer  (Reset to Defaults + Reload UI | Done)
    -----------------------------------------------------------------------
    footerBar = CreateFrame("Frame", nil, hitArea)
    PanelPP.Size(footerBar, rightW, FOOTER_H)
    PanelPP.Point(footerBar, "BOTTOMLEFT", hitArea, "BOTTOMLEFT", rightX, 0)
    footerBar:SetFrameLevel(hitArea:GetFrameLevel() + 5)

    -----------------------------------------------------------------------
    --  Footer button hover colours  (tweak these to adjust fade targets)
    -----------------------------------------------------------------------
    -- Reset to Defaults / Reload UI  (white, muted)
    local RS_TEXT_R, RS_TEXT_G, RS_TEXT_B, RS_TEXT_A = 1, 1, 1, 0.5
    local RS_TEXT_HR, RS_TEXT_HG, RS_TEXT_HB, RS_TEXT_HA = 1, 1, 1, 0.7
    local RS_BRD_R, RS_BRD_G, RS_BRD_B, RS_BRD_A = 1, 1, 1, 0.4
    local RS_BRD_HR, RS_BRD_HG, RS_BRD_HB, RS_BRD_HA = 1, 1, 1, 0.6

    -- Helper: build a footer button with fade hover
    local function MakeFooterBtn(
        parent,
        w,
        h,
        anchorPoint,
        anchorTo,
        anchorRel,
        ax,
        ay,
        textR,
        textG,
        textB,
        textA,
        textHR,
        textHG,
        textHB,
        textHA,
        brdR,
        brdG,
        brdB,
        brdA,
        brdHR,
        brdHG,
        brdHB,
        brdHA,
        navLabel,
        onClick
    )
        local button = CreateFrame("Button", nil, parent)
        PanelPP.Size(button, w, h)
        PanelPP.Point(button, anchorPoint, anchorTo, anchorRel, ax, ay)
        button:SetFrameLevel(parent:GetFrameLevel() + 1)
        local bg = SolidTex(button, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
        bg:SetAllPoints()
        local brd = CUI.MakeRoundedBorder(button, brdR, brdG, brdB, brdA, bg, 2)
        local captionText = MakeFont(button, 13, nil, textR, textG, textB)
        captionText:SetAlpha(textA)
        captionText:SetPoint("CENTER")
        captionText:SetText(CUI.L(navLabel))
        button._label = captionText
        do
            local FADE_DUR = 0.1
            local fadeProgress, target = 0, 0
            local function Apply(t)
                captionText:SetTextColor(
                    lerp(textR, textHR, t),
                    lerp(textG, textHG, t),
                    lerp(textB, textHB, t),
                    lerp(textA, textHA, t)
                )
                brd:SetColor(
                    lerp(brdR, brdHR, t),
                    lerp(brdG, brdHG, t),
                    lerp(brdB, brdHB, t),
                    lerp(brdA, brdHA, t)
                )
            end
            local function OnUpdate(self, timePassed)
                local dir = (target == 1) and 1 or -1
                fadeProgress = fadeProgress + dir * (timePassed / FADE_DUR)
                if (dir == 1 and fadeProgress >= 1) or (dir == -1 and fadeProgress <= 0) then
                    fadeProgress = target
                    self:SetScript("OnUpdate", nil)
                end
                Apply(fadeProgress)
            end
            button:SetScript("OnEnter", function(self)
                target = 1
                self:SetScript("OnUpdate", OnUpdate)
            end)
            button:SetScript("OnLeave", function(self)
                target = 0
                self:SetScript("OnUpdate", OnUpdate)
            end)
        end
        button:SetScript("OnClick", function()
            if onClick then onClick() end
        end)
        return button
    end

    local FOOTER_BTN_W, FOOTER_BTN_H = 150, 30
    local FOOTER_BTN_GAP = 10 -- gap between Reset and Reload
    local DONE_BTN_W = 120 -- Done button width
    local FOOTER_PAD = 24 -- symmetric inset from left/right edges
    local FOOTER_Y = 27 -- vertical offset from bottom (centres the 30px buttons where the 36px ones sat)

    -- Reset button  (left side, FOOTER_PAD from left edge). Plugin and other addons'
    -- pages only: the suite's own resets are in Global Settings' Reset CUI Module
    -- Settings menu (CludesUI._ShowModuleResetMenu).
    local resetBtn = MakeFooterBtn(
        footerBar,
        FOOTER_BTN_W,
        FOOTER_BTN_H,
        "BOTTOMLEFT",
        footerBar,
        "BOTTOMLEFT",
        FOOTER_PAD,
        FOOTER_Y,
        RS_TEXT_R,
        RS_TEXT_G,
        RS_TEXT_B,
        RS_TEXT_A,
        RS_TEXT_HR,
        RS_TEXT_HG,
        RS_TEXT_HB,
        RS_TEXT_HA,
        RS_BRD_R,
        RS_BRD_G,
        RS_BRD_B,
        RS_BRD_A,
        RS_BRD_HR,
        RS_BRD_HG,
        RS_BRD_HB,
        RS_BRD_HA,
        "Reset",
        function()
            if
                not currentModule
                or not moduleList[currentModule]
                or not moduleList[currentModule].onReset
            then
                return
            end
            local moduleConfig = moduleList[currentModule]
            local addonTitle = moduleConfig.title or currentModule
            local msg = CUI.Lf(
                "Are you sure you want to reset all %1$s settings to their defaults? This will reload your UI.",
                CUI.L(addonTitle)
            )
            CUI:ShowConfirmPopup({
                title = CUI.Lf("Reset %1$s", CUI.L(addonTitle)),
                message = msg,
                confirmText = "Reset & Reload",
                cancelText = "Cancel",
                reload = true,
                onConfirm = function() moduleConfig.onReset() end,
            })
        end
    )
    footerBar._resetBtn = resetBtn

    -- Reload UI  (next to Reset, 40px gap, same white/muted style)
    local reloadBtn = MakeFooterBtn(
        footerBar,
        FOOTER_BTN_W,
        FOOTER_BTN_H,
        "BOTTOMLEFT",
        resetBtn,
        "BOTTOMRIGHT",
        FOOTER_BTN_GAP,
        0,
        RS_TEXT_R,
        RS_TEXT_G,
        RS_TEXT_B,
        RS_TEXT_A,
        RS_TEXT_HR,
        RS_TEXT_HG,
        RS_TEXT_HB,
        RS_TEXT_HA,
        RS_BRD_R,
        RS_BRD_G,
        RS_BRD_B,
        RS_BRD_A,
        RS_BRD_HR,
        RS_BRD_HG,
        RS_BRD_HB,
        RS_BRD_HA,
        "Reload UI",
        function() CUI.RequestReload(CUI.L("Reload UI"), CUI.L("Reload the UI now?")) end
    )
    footerBar._reloadBtn = reloadBtn

    -- Per-module Reset visibility: suite pages and pages with no onReset hide Reset and
    -- slide Reload UI left into its slot. Called from SelectModule.
    CUI._UpdateResetButtonVisible = function(hasReset)
        local resetBtn, reloadBtn = footerBar._resetBtn, footerBar._reloadBtn
        if not resetBtn or not reloadBtn then return end
        reloadBtn:ClearAllPoints()
        if hasReset then
            resetBtn:Show()
            reloadBtn:SetPoint("BOTTOMLEFT", resetBtn, "BOTTOMRIGHT", FOOTER_BTN_GAP, 0)
        else
            resetBtn:Hide()
            reloadBtn:SetPoint("BOTTOMLEFT", footerBar, "BOTTOMLEFT", FOOTER_PAD, FOOTER_Y)
        end
    end

    -- Social icons  (to the left of Done button)
    do
        local SOCIAL_SIZE = 40
        local SOCIAL_GAP = 12
        local SOCIAL_ALPHA = 0.35
        local SOCIAL_HOVER = 0.70
        local SOCIAL_FADE = 0.1

        -- Reusable link popup (created once, shared by all social icons)
        local linkDialog, linkShade
        local function HideLinkPopup()
            if linkDialog then linkDialog:Hide() end
            if linkShade then linkShade:Hide() end
        end
        local function ShowLinkPopup(url, anchorBtn)
            if not linkDialog then
                -- Controller cursor: overlay parent (UIParent unless a controller cursor is loaded).
                local overlayParent = CUI.OverlayParent()
                linkShade = CreateFrame("Button", nil, overlayParent)
                linkShade:SetFrameStrata("DIALOG")
                linkShade:SetFrameLevel(499)
                linkShade:SetAllPoints(UIParent)
                local bdTex = linkShade:CreateTexture(nil, "BACKGROUND")
                bdTex:SetAllPoints()
                bdTex:SetColorTexture(0, 0, 0, 0.20)
                local fadeIn = linkShade:CreateAnimationGroup()
                fadeIn:SetToFinalAlpha(true)
                local fade = fadeIn:CreateAnimation("Alpha")
                fade:SetFromAlpha(0)
                fade:SetToAlpha(1)
                fade:SetDuration(0.2)
                linkShade._fadeIn = fadeIn
                linkShade:RegisterForClicks("AnyUp")
                linkShade:SetScript("OnClick", HideLinkPopup)
                linkShade:Hide()

                linkDialog = CreateFrame("Frame", nil, overlayParent)
                linkDialog:SetFrameStrata("DIALOG")
                linkDialog:SetFrameLevel(500)
                linkDialog:SetSize(380, 72)
                local popFade = linkDialog:CreateAnimationGroup()
                popFade:SetToFinalAlpha(true)
                local pa = popFade:CreateAnimation("Alpha")
                pa:SetFromAlpha(0)
                pa:SetToAlpha(1)
                pa:SetDuration(0.2)
                linkDialog._fadeIn = popFade

                local bg = SolidTex(linkDialog, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.97)
                bg:SetAllPoints()
                CUI.MakeRoundedBorder(linkDialog, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15, bg)

                local hintText = MakeFont(
                    linkDialog,
                    11,
                    nil,
                    TEXT_SECTION.r,
                    TEXT_SECTION.g,
                    TEXT_SECTION.b,
                    TEXT_SECTION.a
                )
                hintText:SetPoint("TOP", linkDialog, "TOP", 0, -10)
                hintText:SetText("Press Ctrl+C to copy, then Escape to close")

                local eb = CreateFrame("EditBox", nil, linkDialog)
                eb:SetSize(340, 26)
                eb:SetPoint("TOP", hintText, "BOTTOM", 0, -8)
                eb:SetFontObject(GameFontHighlight)
                eb:SetAutoFocus(false)
                eb:SetJustifyH("CENTER")
                local ebBg = SolidTex(eb, "BACKGROUND", 0.098, 0.108, 0.120, 1)
                ebBg:SetPoint("TOPLEFT", -6, 4)
                ebBg:SetPoint("BOTTOMRIGHT", 6, -4)
                CUI.RoundBody(eb, ebBg)
                CUI.MakeRoundedBorder(eb, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.02)
                eb:SetScript("OnEscapePressed", function(self)
                    self:ClearFocus()
                    HideLinkPopup()
                end)
                eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
                linkDialog:EnableMouse(true)
                linkDialog:SetScript("OnMouseDown", function()
                    linkDialog._eb:SetFocus()
                    linkDialog._eb:HighlightText()
                end)
                linkDialog._eb = eb
                -- Controller cursor: the backdrop blocks what is under it without being a stop.
                CUI.TrackOverlay(linkShade)
                CUI.TrackOverlay(linkDialog)
                CUI.PadHint(linkShade, "nodepass")
                -- Controller cursor: its cancel press clicks the backdrop, which closes.
                if CUI.PadCP() then linkDialog.CloseButton = linkShade end
            end
            linkDialog._eb:SetText(url)
            linkDialog:ClearAllPoints()
            linkDialog:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 8)
            linkShade:SetAlpha(0)
            linkShade:Show()
            linkShade._fadeIn:Play()
            linkDialog:SetAlpha(0)
            linkDialog:Show()
            linkDialog._fadeIn:Play()
            linkDialog._eb:SetFocus()
            linkDialog._eb:HighlightText()
        end
        -- The same copy box for a link elsewhere in the panel (url, the frame it
        -- opens above): the CUI Legends page's Twitch link.
        CUI.ShowLinkPopup = ShowLinkPopup

        local socialDefs = {}

        -- Anchor: rightmost icon sits SOCIAL_GAP to the left of where Done starts
        -- Done is at BOTTOMRIGHT -FOOTER_PAD, so first icon anchor = Done left edge - gap
        local prevAnchor = nil
        for i = #socialDefs, 1, -1 do
            local def = socialDefs[i]
            local button = CreateFrame("Button", nil, footerBar)
            PanelPP.Size(button, SOCIAL_SIZE, SOCIAL_SIZE)
            button:SetFrameLevel(footerBar:GetFrameLevel() + 1)
            if not prevAnchor then
                -- Rightmost icon: anchor relative to Done button position
                PanelPP.Point(
                    button,
                    "BOTTOMRIGHT",
                    footerBar,
                    "BOTTOMRIGHT",
                    -(FOOTER_PAD + DONE_BTN_W + SOCIAL_GAP + 15),
                    FOOTER_Y + (FOOTER_BTN_H - SOCIAL_SIZE) / 2
                )
            else
                PanelPP.Point(button, "RIGHT", prevAnchor, "LEFT", -SOCIAL_GAP, 0)
            end
            prevAnchor = button

            local texture = button:CreateTexture(nil, "ARTWORK")
            texture:SetAllPoints()
            texture:SetTexture(def.icon)
            texture:SetAlpha(SOCIAL_ALPHA)
            PanelPP.DisablePixelSnap(texture)

            local fadeProgress, target = 0, 0
            local function Apply(t) texture:SetAlpha(lerp(SOCIAL_ALPHA, SOCIAL_HOVER, t)) end
            local function OnUpdate(self, timePassed)
                local dir = (target == 1) and 1 or -1
                fadeProgress = fadeProgress + dir * (timePassed / SOCIAL_FADE)
                if (dir == 1 and fadeProgress >= 1) or (dir == -1 and fadeProgress <= 0) then
                    fadeProgress = target
                    self:SetScript("OnUpdate", nil)
                end
                Apply(fadeProgress)
            end
            button:SetScript("OnEnter", function(self)
                target = 1
                self:SetScript("OnUpdate", OnUpdate)
                if def.tooltip and CUI.ShowWidgetTooltip then CUI.ShowWidgetTooltip(self, def.tooltip) end
            end)
            button:SetScript("OnLeave", function(self)
                target = 0
                self:SetScript("OnUpdate", OnUpdate)
                if CUI.HideWidgetTooltip then CUI.HideWidgetTooltip() end
            end)
            button:SetScript("OnClick", function() ShowLinkPopup(def.url, button) end)
        end
    end

    -- Close  (right side, FOOTER_PAD from right edge, green, closes window)
    do
        local button = CreateFrame("Button", nil, footerBar)
        PanelPP.Size(button, DONE_BTN_W, FOOTER_BTN_H)
        PanelPP.Point(button, "BOTTOMRIGHT", footerBar, "BOTTOMRIGHT", -FOOTER_PAD, FOOTER_Y)
        button:SetFrameLevel(footerBar:GetFrameLevel() + 1)
        local bg = SolidTex(button, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
        bg:SetAllPoints()
        local brd = CUI.MakeRoundedBorder(button, CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 0.7, bg, 2)
        local captionText = MakeFont(button, 13, nil, CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b)
        captionText:SetAlpha(0.7)
        captionText:SetPoint("CENTER")
        captionText:SetText(CUI.L("Close"))
        -- Hover animation reads from CLUDES_GREEN live
        local FADE_DUR = 0.1
        local fadeProgress, target = 0, 0
        local function Apply(t)
            local EG = CLUDES_GREEN
            captionText:SetTextColor(EG.r, EG.g, EG.b, lerp(0.7, 1, t))
            brd:SetColor(EG.r, EG.g, EG.b, lerp(0.7, 1, t))
        end
        local function OnUpdate(self, timePassed)
            local dir = (target == 1) and 1 or -1
            fadeProgress = fadeProgress + dir * (timePassed / FADE_DUR)
            if (dir == 1 and fadeProgress >= 1) or (dir == -1 and fadeProgress <= 0) then
                fadeProgress = target
                self:SetScript("OnUpdate", nil)
            end
            Apply(fadeProgress)
        end
        button:SetScript("OnEnter", function(self)
            target = 1
            self:SetScript("OnUpdate", OnUpdate)
        end)
        button:SetScript("OnLeave", function(self)
            target = 0
            self:SetScript("OnUpdate", OnUpdate)
        end)
        button:SetScript("OnClick", function()
            if panelFrame then panelFrame:Hide() end
        end)
        -- Register for accent updates
        RegAccent({
            type = "callback",
            fn = function(red, green, blue)
                captionText:SetTextColor(red, green, blue, lerp(0.7, 1, fadeProgress))
                brd:SetColor(red, green, blue, lerp(0.7, 1, fadeProgress))
            end,
        })
    end
end

local function BuildMainFrame()
    if panelFrame then return panelFrame end

    BuildFrame()
    BuildSidebar()
    local rightW, rightX = BuildContent()
    BuildFooter(rightW, rightX)

    return panelFrame
end

-------------------------------------------------------------------------------
--  Tab Bar helpers
-------------------------------------------------------------------------------
-- Display-only tab label overrides ([page identity] = shown label), registered by module options
-- files. Page IDENTITY stays the original string everywhere else (SelectPage, nav targets, unlock elements, spec overrides, saved state); only the tab text changes.
CUI.TAB_LABEL_OVERRIDES = CUI.TAB_LABEL_OVERRIDES or {}

-- A page's tab label (not localized): a suite module's own config.tabLabels[page] first,
-- so a label never lands on another module's page of the same name, then the shared
-- TAB_LABEL_OVERRIDES, else the page identity itself. tabLabels is suite-only (plugin
-- configs are ignored), and on CUI_NS, not CludesUI: a public slot would let any
-- addon relabel the suite's tabs.
function CUI_NS.GetTabLabel(moduleFolder, page)
    local m = moduleFolder and CUI_NS.IsSuiteKey(moduleFolder) and moduleList[moduleFolder]
    local own = m and type(m.tabLabels) == "table" and m.tabLabels[page]
    return own or CUI.TAB_LABEL_OVERRIDES[page] or page
end

-- Tab buttons are pooled by position (tabStrip._tabPool) and re-labelled for each
-- module; tabStrip._tabButtons lists the ones in use, in order.
ClearTabs = function()
    for _, button in ipairs(tabStrip._tabButtons) do
        button:Hide()
    end
    wipe(tabStrip._tabButtons)
end

CreateTabButton = function(index, name)
    local pool = tabStrip._tabPool
    if not pool then
        pool = {}
        tabStrip._tabPool = pool
    end
    local button = pool[index]
    if not button then
        button = CreateFrame("Button", nil, tabStrip)
        button:SetHeight(TAB_BAR_H)
        button:SetFrameLevel(tabStrip:GetFrameLevel() + 1)

        -- A tab is a squared chip, 6px inside the bar top and bottom: a faint
        -- plate always, and for the active tab an accent wash with an accent cap
        -- along its top edge.
        local chip = SolidTex(button, "BACKGROUND", 1, 1, 1, 0.045)
        chip:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -6)
        chip:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 6)
        button._chip = chip

        local fill = SolidTex(button, "BORDER", CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 0.16)
        fill:SetAllPoints(chip)
        fill:Hide()
        button._fill = fill
        RegAccent({ type = "solid", obj = fill, a = 0.16 })

        local navLabel = MakeFont(button, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        navLabel:SetPoint("CENTER", 0, 0)
        button._label = navLabel

        -- Accent cap on the active tab (kept under the old field name).
        local underline = SolidTex(button, "ARTWORK", CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 1)
        underline:SetHeight(2)
        underline:SetPoint("TOPLEFT", chip, "TOPLEFT", 0, 0)
        underline:SetPoint("TOPRIGHT", chip, "TOPRIGHT", 0, 0)
        button._underline = underline
        RegAccent({ type = "solid", obj = underline, a = 1 })

        -- A disabled tab with a reason (btn._tip) shows it on hover; a disabled
        -- tab swallows its click.
        button:SetScript("OnEnter", function(self)
            if self._tip then
                if CUI.ShowWidgetTooltip then CUI.ShowWidgetTooltip(self, self._tip) end
            elseif activePage ~= self._name then
                self._label:SetTextColor(1, 1, 1, 0.86)
            end
        end)
        button:SetScript("OnLeave", function(self)
            if self._tip then
                if CUI.HideWidgetTooltip then CUI.HideWidgetTooltip() end
            elseif activePage ~= self._name then
                self._label:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
            end
        end)
        button:SetScript("OnClick", function(self)
            if not self._disabled then CUI:SelectPage(self._name) end
        end)
        pool[index] = button
    end

    button._name = name
    button._disabled = nil
    button._tip = nil
    local navLabel = button._label
    navLabel:SetText(CUI.L(CUI_NS.GetTabLabel(currentModule, name)))
    navLabel:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    navLabel:SetAlpha(1)

    local textW = navLabel:GetStringWidth() or 60
    button:SetWidth(textW + 28)
    button._underline:Hide()
    button._fill:Hide()
    button:ClearAllPoints()
    button:Show()

    return button
end

BuildTabs = function(pageNames, disabledPages, disabledTooltips)
    ClearTabs()
    if not pageNames or #pageNames == 0 then
        tabStrip:SetHeight(0.001)
        return
    end
    tabStrip:SetHeight(TAB_BAR_H)
    local disabledSet = {}
    if disabledPages then
        for _, name in ipairs(disabledPages) do
            disabledSet[name] = true
        end
    end
    local xOff = CONTENT_PAD
    for i, name in ipairs(pageNames) do
        local button = CreateTabButton(i, name)
        button:SetPoint("BOTTOMLEFT", tabStrip, "BOTTOMLEFT", xOff, 0)
        xOff = xOff + button:GetWidth() + 4
        tabStrip._tabButtons[i] = button
        -- Disable tab if in disabledPages list
        if disabledSet[name] then
            button:EnableMouse(true) -- keep mouse enabled for tooltip
            button._label:SetAlpha(0.30)
            -- The tab's scripts show this reason on hover and swallow the click.
            button._disabled = true
            button._tip = disabledTooltips and disabledTooltips[name] or nil
        end
    end

    ---------------------------------------------------------------------------
    --  Inline search EditBox  (right-aligned in tab bar, always visible)
    ---------------------------------------------------------------------------
    if not tabStrip._searchBox then
        local SEARCH_W, SEARCH_H = 210, 28
        local searchPanel = CreateFrame("Frame", nil, tabStrip)
        searchPanel:SetSize(SEARCH_W, SEARCH_H)
        searchPanel:SetPoint("BOTTOMRIGHT", tabStrip, "BOTTOMRIGHT", -10, (TAB_BAR_H - SEARCH_H) / 2 + 2)
        searchPanel:SetFrameLevel(tabStrip:GetFrameLevel() + 2)

        local searchBg = SolidTex(
            searchPanel,
            "BACKGROUND",
            STYLE.SL_INPUT_R,
            STYLE.SL_INPUT_G,
            STYLE.SL_INPUT_B,
            STYLE.SL_INPUT_A + 0.10
        )
        searchBg:SetAllPoints()
        local searchBrd =
            CUI.MakeRoundedBorder(searchPanel, STYLE.BORDER_R, STYLE.BORDER_G, STYLE.BORDER_B, 0.10, searchBg)

        local inputBox = CreateFrame("EditBox", nil, searchPanel)
        inputBox:SetAllPoints()
        inputBox:SetAutoFocus(false)
        inputBox:SetFont(CUI.EXPRESSWAY, 13, "")
        inputBox:SetTextColor(STYLE.TEXT_WHITE_R, STYLE.TEXT_WHITE_G, STYLE.TEXT_WHITE_B, 1)
        inputBox:SetTextInsets(10, 24, 0, 0)
        inputBox:SetMaxLetters(40)

        local placeholder =
            MakeFont(searchPanel, 12, nil, STYLE.TEXT_DIM_R, STYLE.TEXT_DIM_G, STYLE.TEXT_DIM_B, 0.3)
        placeholder:SetPoint("LEFT", searchPanel, "LEFT", 10, 0)
        placeholder:SetText(CUI.L("Search Module Settings..."))

        -- Clear button (X) on right side -- frame level above editBox so clicks register
        local clearBtn = CreateFrame("Button", nil, searchPanel)
        clearBtn:SetSize(20, 20)
        clearBtn:SetPoint("RIGHT", searchPanel, "RIGHT", -4, 0)
        clearBtn:SetFrameLevel(inputBox:GetFrameLevel() + 2)
        clearBtn:Hide()
        local clearLabel =
            MakeFont(clearBtn, 15, nil, STYLE.TEXT_DIM_R, STYLE.TEXT_DIM_G, STYLE.TEXT_DIM_B, 0.35)
        clearLabel:SetPoint("CENTER")
        clearLabel:SetText("x")
        clearBtn:SetScript("OnEnter", function() clearLabel:SetTextColor(1, 1, 1, 1) end)
        clearBtn:SetScript(
            "OnLeave",
            function() clearLabel:SetTextColor(STYLE.TEXT_DIM_R, STYLE.TEXT_DIM_G, STYLE.TEXT_DIM_B, 0.35) end
        )
        clearBtn:SetScript("OnClick", function()
            inputBox:SetText("")
            inputBox:ClearFocus()
        end)

        -- Disabled (a page the inline search cannot filter, SelectPage): greyed
        -- like a disabled option, under a blocker that takes the mouse and says why.
        local searchBlock = CreateFrame("Frame", nil, searchPanel)
        searchBlock:SetAllPoints()
        searchBlock:SetFrameLevel(clearBtn:GetFrameLevel() + 1)
        searchBlock:EnableMouse(true)
        searchBlock:Hide()
        searchBlock:SetScript(
            "OnEnter",
            function() CUI.ShowWidgetTooltip(searchPanel, CUI.L("Search is not available on this page.")) end
        )
        searchBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        tabStrip._setSearchDisabled = function(off)
            if off then inputBox:ClearFocus() end
            searchPanel:SetAlpha(off and 0.3 or 1)
            searchBlock:SetShown(off)
        end

        -- Border hover effect
        searchPanel:SetScript(
            "OnEnter",
            function() searchBrd:SetColor(STYLE.BORDER_R, STYLE.BORDER_G, STYLE.BORDER_B, 0.15) end
        )
        searchPanel:SetScript(
            "OnLeave",
            function() searchBrd:SetColor(STYLE.BORDER_R, STYLE.BORDER_G, STYLE.BORDER_B, 0.10) end
        )
        inputBox:SetScript(
            "OnEditFocusGained",
            function() searchBrd:SetColor(STYLE.BORDER_R, STYLE.BORDER_G, STYLE.BORDER_B, 0.15) end
        )
        inputBox:SetScript(
            "OnEditFocusLost",
            function() searchBrd:SetColor(STYLE.BORDER_R, STYLE.BORDER_G, STYLE.BORDER_B, 0.10) end
        )

        local searchDebounceTimer
        inputBox:SetScript("OnTextChanged", function(self, userInput)
            local textValue = self:GetText() or ""
            if textValue == "" then
                placeholder:Show()
                clearBtn:Hide()
            else
                placeholder:Hide()
                clearBtn:Show()
            end
            if searchDebounceTimer then
                searchDebounceTimer:Cancel()
                searchDebounceTimer = nil
            end
            CUI:ApplyInlineSearch(textValue, true)
            if textValue ~= "" then
                searchDebounceTimer = C_Timer.NewTimer(0.5, function()
                    searchDebounceTimer = nil
                    CUI:ApplyInlineSearch(textValue)
                end)
            end
        end)

        inputBox:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            self:ClearFocus()
        end)

        inputBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

        tabStrip._searchBox = inputBox
        tabStrip._searchFrame = searchPanel

        -- Spec Override capture toggle (left of the search box). All look
        -- and behavior live in CUI_SpecOverrides_Popups.lua (SpecOverrides_SetupButton).
        if CUI.SpecOverrides_SetupButton then
            local soBtn = CreateFrame("Button", nil, tabStrip)
            soBtn:SetSize(26, 26)
            soBtn:SetPoint("RIGHT", searchPanel, "LEFT", -10, 0)
            soBtn:SetFrameLevel(tabStrip:GetFrameLevel() + 2)
            CUI.SpecOverrides_SetupButton(soBtn)
            tabStrip._specOvBtn = soBtn
        end
        -- Conditional Overrides has no toolbar button: its cards render as a second section in the spec popup.
    end
    tabStrip._searchFrame:Show()
    -- Clear search text when tabs are rebuilt (module switch)
    if tabStrip._searchBox:GetText() ~= "" then tabStrip._searchBox:SetText("") end

    -- Defer a relayout so GetStringWidth returns correct values after render
    tabStrip:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        local x = CONTENT_PAD
        for _, btn in ipairs(self._tabButtons) do
            local tw = btn._label:GetStringWidth() or 60
            btn:SetWidth(tw + 28)
            btn:ClearAllPoints()
            btn:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 0)
            x = x + btn:GetWidth() + 4
        end
    end)
end

UpdateTabHighlight = function(selectedName)
    for _, button in ipairs(tabStrip._tabButtons) do
        if button._disabled then
            -- disabled tab: keep dimmed, no accent
        elseif button._name == selectedName then
            button._label:SetTextColor(1, 1, 1, 1)
            button._underline:Show()
            button._fill:Show()
        else
            button._label:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
            button._underline:Hide()
            button._fill:Hide()
        end
    end
end

-------------------------------------------------------------------------------
--  Inline Search  (filter sections on the current page)
-------------------------------------------------------------------------------
local _pageCache -- forward declaration; initialized below in page-cache section
-- Pool of reusable highlight border frames (accent-colored, fade-in only)
local _searchHighlightPool = {}
local _searchHighlightsActive = {}

local function GetSearchHighlight()
    local pulse = table.remove(_searchHighlightPool)
    if not pulse then
        pulse = CreateFrame("Frame")
        local color = CLUDES_GREEN
        local function MkEdge()
            local tex = pulse:CreateTexture(nil, "OVERLAY", nil, 7)
            tex:SetColorTexture(color.r, color.g, color.b, 1)
            return tex
        end
        pulse._top = MkEdge()
        pulse._bot = MkEdge()
        pulse._lft = MkEdge()
        pulse._rgt = MkEdge()
        pulse._top:SetHeight(1)
        pulse._top:SetPoint("TOPLEFT")
        pulse._top:SetPoint("TOPRIGHT")
        pulse._bot:SetHeight(1)
        pulse._bot:SetPoint("BOTTOMLEFT")
        pulse._bot:SetPoint("BOTTOMRIGHT")
        pulse._lft:SetWidth(1)
        pulse._lft:SetPoint("TOPLEFT", pulse._top, "BOTTOMLEFT")
        pulse._lft:SetPoint("BOTTOMLEFT", pulse._bot, "TOPLEFT")
        pulse._rgt:SetWidth(1)
        pulse._rgt:SetPoint("TOPRIGHT", pulse._top, "BOTTOMRIGHT")
        pulse._rgt:SetPoint("BOTTOMRIGHT", pulse._bot, "TOPRIGHT")
    end
    _searchHighlightsActive[#_searchHighlightsActive + 1] = pulse
    return pulse
end

-- detach: also take each highlight off the row it pulsed on (a page pass of the
-- page pool runs this first, so no highlight rides on a row it resets).
local function RecycleAllSearchHighlights(detach)
    for i = #_searchHighlightsActive, 1, -1 do
        local pulse = _searchHighlightsActive[i]
        pulse:Hide()
        pulse:SetScript("OnUpdate", nil)
        pulse:ClearAllPoints()
        if detach then pulse:SetParent(nil) end
        _searchHighlightPool[#_searchHighlightPool + 1] = pulse
        _searchHighlightsActive[i] = nil
    end
    -- An inline search run recycles without detaching, so a highlight it put
    -- back can still sit hidden on the row it pulsed on: a page pass takes
    -- those off too.
    if detach then
        for i = 1, #_searchHighlightPool do
            local pulse = _searchHighlightPool[i]
            if pulse:GetParent() then pulse:SetParent(nil) end
        end
    end
end

local function PlaySearchHighlight(pulse, targetFrame)
    pulse:SetParent(targetFrame)
    pulse:SetAllPoints(targetFrame)
    pulse:SetFrameLevel(targetFrame:GetFrameLevel() + 5)
    pulse:SetAlpha(0)
    pulse:Show()
    local timePassed = 0
    pulse:SetScript("OnUpdate", function(self, elapsed)
        timePassed = timePassed + elapsed
        if timePassed >= 0.3 then
            self:SetAlpha(0.5)
            self:SetScript("OnUpdate", nil)
            return
        end
        self:SetAlpha(0.5 * (timePassed / 0.3))
    end)
end

CUI.PlaySearchHighlight = PlaySearchHighlight
CUI.GetSearchHighlight = GetSearchHighlight

-- Collect a wrapper's direct children sorted by original Y (top to bottom) into sections
-- { header=frame, members={frame,...} }: each child belongs to the nearest section header above
-- it, children before any header become leading orphans. Split column containers (_leftCol/_rightCol) are single blocks -- searched inside, never re-anchored per child.
local function CollectAllChildren(wrapper)
    local children = { wrapper:GetChildren() }
    -- Objects the page pool parked (idle, hidden) are not part of the page.
    local isIdle = CUI_NS.PoolIsIdle
    if isIdle then
        for i = #children, 1, -1 do
            if isIdle(children[i]) then table.remove(children, i) end
        end
    end
    -- Save original anchor info on first encounter so we can restore later.
    for _, kid in ipairs(children) do
        if not kid._origAnchor then
            local point, relTo, relPoint, x, rowY = kid:GetPoint(1)
            if point then kid._origAnchor = { point, relTo, relPoint, x, rowY } end
        end
        -- For split containers, build a searchable label from all children inside
        if kid._leftCol or kid._rightCol then
            if not kid._splitSearchLabels then
                local labels = {}
                local labelsLoc = {}
                local function GatherLabels(col)
                    if not col then return end
                    local subs = { col:GetChildren() }
                    for _, sub in ipairs(subs) do
                        -- (a parked object keeps its last dress's labels)
                        if not (isIdle and isIdle(sub)) then
                            if sub._sectionName then
                                labels[#labels + 1] = sub._sectionName
                                labelsLoc[#labelsLoc + 1] = sub._sectionNameLoc or sub._sectionName
                            end
                            if sub._labelText then
                                labels[#labels + 1] = sub._labelText
                                labelsLoc[#labelsLoc + 1] = sub._labelTextLoc or sub._labelText
                            end
                        end
                    end
                end
                GatherLabels(kid._leftCol)
                GatherLabels(kid._rightCol)
                kid._splitSearchLabels = table.concat(labels, " ")
                -- Bilingual search: localized variant, only stored when it differs (nil on English).
                local _loc = table.concat(labelsLoc, " ")
                if _loc ~= kid._splitSearchLabels then kid._splitSearchLabelsLoc = _loc end
            end
        end
    end
    table.sort(children, function(lhs, rhs)
        local ay = lhs._origAnchor and lhs._origAnchor[5] or 0
        local by = rhs._origAnchor and rhs._origAnchor[5] or 0
        return ay > by -- y offsets are negative, so higher (less negative) = higher on page
    end)

    local sections = {} -- { { header=frame, members={frame,...} }, ... }
    local orphans = {} -- children before any section header
    local current = nil -- current section entry

    for _, kid in ipairs(children) do
        if kid._searchIgnore then
            -- Managed outside the inline search (e.g. party sync overlays); never
            -- collect it so the search can't re-anchor or hide/show it.
        elseif kid._isSectionHeader then
            current = { header = kid, members = {} }
            sections[#sections + 1] = current
        elseif current then
            current.members[#current.members + 1] = kid
        else
            orphans[#orphans + 1] = kid
        end
    end
    return sections, orphans
end

function CUI:NavigateToElementSettings(moduleName, pageTitle, sectionName, preSelectFn, highlightText)
    -- For split rows (DualRow etc.), narrow a deep-link highlight to the half/slot whose own
    -- label matches instead of pulsing the whole row; returns that child region, or nil to fall
    -- back to the full row. Inline, not a file-scope local: the main chunk is at the 200-local cap.
    local function ResolveHighlightSlot(line, textValue, exactOnly)
        if not textValue or not line.GetChildren then return nil end
        local locText = CUI.L(textValue) or textValue
        local regions = { line:GetChildren() }
        -- Objects the page pool parked keep their last dress's labels: not slots.
        local isIdle = CUI_NS.PoolIsIdle
        if isIdle then
            for i = #regions, 1, -1 do
                if isIdle(regions[i]) then table.remove(regions, i) end
            end
        end
        -- A label equal to the text first, so "Sidebar Icons" lands on its own slot rather
        -- than on an earlier "Sidebar Icons Color"; then the first label containing it.
        for _, regionObj in ipairs(regions) do
            local captionText = regionObj._label
            if captionText and captionText.GetText then
                local t = captionText:GetText()
                if t and t ~= "" and (t == textValue or t == locText) then return regionObj end
            end
        end
        if exactOnly then return nil end
        for _, regionObj in ipairs(regions) do
            local captionText = regionObj._label
            if captionText and captionText.GetText then
                local text = captionText:GetText()
                if
                    text
                    and text ~= ""
                    and (
                        text:find(textValue, 1, true)
                        or (locText ~= textValue and text:find(locText, 1, true))
                    )
                then
                    return regionObj
                end
            end
        end
        return nil
    end

    -- Refused in combat like Show (see there), before the page selection below
    -- runs, which has no combat check of its own.
    if InCombatLockdown() then
        CUI.PrintError("Cannot open options during combat.")
        return
    end

    -- First-open split (see _SplitFirstOpen): Show() below returns without
    -- building the panel on the session's first open, so run the whole deep
    -- link next frame rather than navigating a panel that does not exist yet.
    if
        self:_SplitFirstOpen(
            function()
                CUI:NavigateToElementSettings(moduleName, pageTitle, sectionName, preSelectFn, highlightText)
            end
        )
    then
        return
    end

    self:Show()
    self:SelectModule(moduleName)
    self:SelectPage(pageTitle)

    -- Switch dropdown AFTER the page is loaded, then force a full rebuild.
    -- This mirrors exactly what the dropdown's own onChange handler does. A page
    -- of the page pool rebuilds page and header together in the one pass (and a
    -- page invalidated while it showed is built again before the highlight).
    local navEntry = _pageCache[moduleName .. "::" .. pageTitle]
    if preSelectFn then
        preSelectFn()
        if navEntry and navEntry.reuse then
            self:RefreshPage(true)
        else
            self:InvalidateContentHeaderCache()
            local moduleConfig = moduleList[moduleName]
            if moduleConfig and moduleConfig.getHeaderBuilder then
                local hb = moduleConfig.getHeaderBuilder(pageTitle)
                if hb then self:SetContentHeader(hb) end
            end
            self:RefreshPage(true)
        end
    elseif
        navEntry
        and navEntry.reuse
        and navEntry.stale
        and currentModule == moduleName
        and activePage == pageTitle
    then
        self:RefreshPage(true)
    end

    C_Timer.After(0.05, function()
        local pageKey = moduleName .. "::" .. pageTitle
        local cachedPage = _pageCache[pageKey]
        if not cachedPage or not cachedPage.wrapper then return end

        local sections = CollectAllChildren(cachedPage.wrapper)
        for _, section in ipairs(sections) do
            if section.header._sectionName == sectionName then
                -- Find the row to scroll to; narrow the highlight to the matching
                -- slot (DualRow half) when possible, otherwise pulse the whole row.
                local target = section.header
                local hlTarget = section.header
                if highlightText then
                    -- The first row whose label or slot equals the text, so a later exact
                    -- match wins over an earlier row that only contains it; failing that,
                    -- the first row containing it.
                    for pass = 1, 2 do
                        for _, m in ipairs(section.members) do
                            if
                                (m._labelText and m._labelText:find(highlightText, 1, true))
                                or (m._labelTextLoc and m._labelTextLoc:find(highlightText, 1, true))
                            then
                                local slot = ResolveHighlightSlot(m, highlightText, pass == 1)
                                if
                                    pass == 2
                                    or slot
                                    or m._labelText == highlightText
                                    or m._labelTextLoc == highlightText
                                then
                                    target = m
                                    hlTarget = slot or ResolveHighlightSlot(m, highlightText) or m
                                    break
                                end
                            end
                        end
                        if target ~= section.header then break end
                    end
                end

                local a = target._origAnchor
                if a then
                    local scrollPos = math.abs(a[5]) - 40
                    CUI.SmoothScrollTo(scrollPos)
                    -- A page-pool rebuild in between dresses the row again (for
                    -- another slot, maybe): no pulse then.
                    local Gen = CUI_NS.PoolGen
                    local hlGen = Gen and Gen(hlTarget)
                    C_Timer.After(0.15, function()
                        if Gen and Gen(hlTarget) ~= hlGen then return end
                        local pulse = GetSearchHighlight()
                        PlaySearchHighlight(pulse, hlTarget)
                    end)
                end
                return
            end
        end
    end)
end

-- Searchable label for any child frame. On translated clients the localized variant is
-- appended so search matches either language; on English the *Loc fields are nil.
local function GetSearchLabel(kid)
    local en = kid._labelText or kid._sectionName or kid._splitSearchLabels
    if not en then return "" end
    local loc = kid._labelTextLoc or kid._sectionNameLoc or kid._splitSearchLabelsLoc
    if loc then return en .. " " .. loc end
    return en
end

-- Resolve the current display text of a dropdown on a region (if any)
local function GetDropdownValueText(regionObj)
    if not regionObj._ddGetValue or not regionObj._ddValues then return nil end
    local entryKey = regionObj._ddGetValue()
    if entryKey == nil then return nil end
    local val = regionObj._ddValues[entryKey]
    if val == nil then return nil end
    if type(val) == "table" then return val.text end
    return tostring(val)
end

-- "No results" hint for the module search box, with a link that hands the
-- query to the sidebar search. Built on first use, parented to the scroll
-- child (not the page wrapper, so the filter never sees it). nil hides it.
local SetInlineEmptyHint
do
    local hintText
    SetInlineEmptyHint = function(searchQuery)
        if not searchQuery then
            if hintText then hintText:Hide() end
            return
        end
        if not hintText then
            hintText = CreateFrame("Frame", nil, contentFrame)
            PanelPP.Size(hintText, 600, 100)
            -- Blizzard's own search box magnifier (SearchBoxTemplate).
            local iconTex = hintText:CreateTexture(nil, "ARTWORK")
            iconTex:SetAtlas("common-search-magnifyingglass")
            iconTex:SetDesaturated(true)
            iconTex:SetVertexColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.6)
            PanelPP.Size(iconTex, 24, 24)
            PanelPP.Point(iconTex, "TOP", hintText, "TOP", 0, 0)
            hintText._text = MakeFont(hintText, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
            PanelPP.Point(hintText._text, "TOPLEFT", hintText, "TOPLEFT", 0, -34)
            PanelPP.Point(hintText._text, "TOPRIGHT", hintText, "TOPRIGHT", 0, -34)
            hintText._text:SetJustifyH("CENTER")
            hintText._text:SetWordWrap(false)
            local linkText = CreateFrame("Button", nil, hintText)
            linkText:SetPoint("TOP", hintText._text, "BOTTOM", 0, -8)
            local linkFS = MakeFont(linkText, 13, nil, CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 1)
            linkFS:SetPoint("LEFT")
            linkFS:SetText(CUI.L("Search all modules"))
            local arrow = linkText:CreateTexture(nil, "ARTWORK")
            arrow:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-right.png")
            arrow:SetVertexColor(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 1)
            PanelPP.Size(arrow, 12, 12)
            PanelPP.Point(arrow, "LEFT", linkFS, "RIGHT", 4, 0)
            RegAccent({
                type = "callback",
                fn = function(red, green, blue)
                    linkFS:SetTextColor(red, green, blue, 1)
                    arrow:SetVertexColor(red, green, blue, 1)
                end,
            })
            PanelPP.Size(linkText, linkFS:GetStringWidth() + 16, 18)
            linkText:SetAlpha(0.8)
            linkText:SetScript("OnEnter", function() linkText:SetAlpha(1) end)
            linkText:SetScript("OnLeave", function() linkText:SetAlpha(0.8) end)
            linkText:SetScript("OnClick", function()
                local box = tabStrip and tabStrip._searchBox
                local q = box and box:GetText() or ""
                -- Clear this box first: it restores the page and cancels its
                -- debounce; then the sidebar search takes over the query.
                if box then
                    box:SetText("")
                    box:ClearFocus()
                end
                local sb = CUI._sidebarSearchBox
                if sb and q ~= "" then
                    sb:SetText(q)
                    sb:SetFocus()
                    sb:SetCursorPosition(#q)
                end
            end)
        end
        local q = searchQuery:gsub("||", "|"):gsub("|", "||")
        hintText._text:SetText(CUI.Lf("No results for %s", '"' .. q .. '"'))
        hintText:ClearAllPoints()
        PanelPP.Point(hintText, "TOP", contentFrame, "TOP", 0, -40)
        hintText:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        hintText:Show()
    end
end

function CUI:ApplyInlineSearch(searchQuery, skipHighlights)
    SetInlineEmptyHint(nil)
    if not currentModule or not activePage then return end
    -- Active search force-expands every "Show Less Common" section (links hidden);
    -- clearing collapses back to session state. MUST run before the cache lookup below:
    -- a state transition rebuilds and replaces this page's cache entry.
    if CUI.SetLessCommonSearchActive then
        CUI.SetLessCommonSearchActive(searchQuery ~= nil and searchQuery ~= "")
    end
    local pageKey = currentModule .. "::" .. activePage
    local cachedPage = _pageCache[pageKey]
    if not cachedPage or not cachedPage.wrapper then return end

    -- Per-page search-state hook (e.g. the party tab hides its sync overlays
    -- while a search is active). Fires for both filtering and restore.
    if CUI._onInlineSearch then CUI._onInlineSearch(searchQuery or "") end

    RecycleAllSearchHighlights()
    -- Section cards (CludesUI_Widgets.lua) step aside while a query moves rows.
    if CUI._SetSectionCardsShown then CUI._SetSectionCardsShown(not searchQuery or searchQuery == "") end

    local sections, orphans = CollectAllChildren(cachedPage.wrapper)

    -- Empty query: restore everything
    if not searchQuery or searchQuery == "" then
        for _, section in ipairs(sections) do
            section.header:Show()
            if section.header._origAnchor then
                section.header:ClearAllPoints()
                local a = section.header._origAnchor
                PanelPP.Point(section.header, a[1], a[2], a[3], a[4], a[5])
            end
            for _, m in ipairs(section.members) do
                m:Show()
                if m._origAnchor then
                    m:ClearAllPoints()
                    local a = m._origAnchor
                    PanelPP.Point(m, a[1], a[2], a[3], a[4], a[5])
                end
            end
        end
        for _, orphan in ipairs(orphans) do
            orphan:Show()
            if orphan._origAnchor then
                orphan:ClearAllPoints()
                local a = orphan._origAnchor
                PanelPP.Point(orphan, a[1], a[2], a[3], a[4], a[5])
            end
        end
        -- Restore original scroll height
        contentFrame:SetHeight(cachedPage.totalH + 30)
        if contentScroll and contentScroll.SetVerticalScroll then
            scrollTarget = 0
            smoothing = false
            if smoother then smoother:Hide() end
            contentScroll:SetVerticalScroll(0)
            UpdateScrollThumb()
        end
        cachedPage._searchFiltered = nil
        return
    end

    local lowerQuery = searchQuery:lower()

    -- Determine which sections are visible and which rows/slots match
    local visibleSections = {}
    for _, section in ipairs(sections) do
        local sectionName = section.header._sectionName or ""
        local sectionMatch = sectionName:lower():find(lowerQuery, 1, true)
        -- Bilingual: also match the localized section name on translated clients.
        if not sectionMatch and section.header._sectionNameLoc then
            sectionMatch = section.header._sectionNameLoc:lower():find(lowerQuery, 1, true)
        end
        -- Per-page section exclusion hook (e.g. the party tab hides sections that
        -- are synced with raid settings). Only consulted during a live search.
        local excluded = CUI._searchExcludeSection and CUI._searchExcludeSection(sectionName)

        local anyMemberMatch = false
        local matchingMembers = {}
        for _, m in ipairs(section.members) do
            local navLabel = GetSearchLabel(m)
            local matched = navLabel ~= "" and navLabel:lower():find(lowerQuery, 1, true)
            if not matched then
                -- Also check current dropdown selected values on this row's regions
                for _, rgn in ipairs({ m._leftRegion, m._midRegion, m._rightRegion }) do
                    if rgn then
                        local ddText = GetDropdownValueText(rgn)
                        if ddText and ddText:lower():find(lowerQuery, 1, true) then
                            matched = true
                            break
                        end
                    end
                end
            end
            if matched then
                anyMemberMatch = true
                matchingMembers[m] = true
            end
        end

        if (sectionMatch or anyMemberMatch) and not excluded then
            visibleSections[#visibleSections + 1] = {
                sec = section,
                sectionMatch = sectionMatch,
                matchingMembers = matchingMembers,
            }
        else
            section.header:Hide()
            for _, m in ipairs(section.members) do
                m:Hide()
            end
        end
    end

    -- Orphans are by construction the LEADING widgets on a page: created before its first
    -- SectionHeader call, so _currentSection is nil when TagOptionRow tags them. Match them like
    -- section members instead of hiding them unconditionally, or a query matching only an orphan (a lead "Activate X" button) leaves the page empty.
    local visibleOrphans = {}
    for _, orphan in ipairs(orphans) do
        local navLabel = GetSearchLabel(orphan)
        local matched = navLabel ~= "" and navLabel:lower():find(lowerQuery, 1, true)
        if not matched then
            for _, rgn in ipairs({ orphan._leftRegion, orphan._midRegion, orphan._rightRegion }) do
                if rgn then
                    local ddText = GetDropdownValueText(rgn)
                    if ddText and ddText:lower():find(lowerQuery, 1, true) then
                        matched = true
                        break
                    end
                end
            end
        end
        if matched then
            visibleOrphans[#visibleOrphans + 1] = orphan
        else
            orphan:Hide()
        end
    end

    -- Build per-slot highlight targets and count totals to decide if we suppress
    -- highlights (when every visible slot is highlighted, none should glow).
    local litTargets = {} -- list of { frame = region_or_member }
    local slotTotal = 0
    local litSlots = 0

    for _, vs in ipairs(visibleSections) do
        for _, m in ipairs(vs.sec.members) do
            -- Skip spacer frames -- they have no content to highlight
            if m._isSpacer then
                -- still counts as nothing
            else
                -- Collect the slots this member exposes
                local slots = {}
                if m._leftRegion then
                    slots[#slots + 1] = { region = m._leftRegion, label = m._leftRegion._slotLabel or "" }
                end
                if m._midRegion then
                    slots[#slots + 1] = { region = m._midRegion, label = m._midRegion._slotLabel or "" }
                end
                if m._rightRegion then
                    slots[#slots + 1] = { region = m._rightRegion, label = m._rightRegion._slotLabel or "" }
                end

                if #slots > 0 then
                    -- Split row: check each slot individually
                    for _, slot in ipairs(slots) do
                        if slot.label ~= "" then
                            slotTotal = slotTotal + 1
                            local slotMatch = slot.label:lower():find(lowerQuery, 1, true)
                            if not slotMatch then
                                local ddText = GetDropdownValueText(slot.region)
                                if ddText then slotMatch = ddText:lower():find(lowerQuery, 1, true) end
                            end
                            if vs.sectionMatch or slotMatch then
                                litSlots = litSlots + 1
                                litTargets[#litTargets + 1] = slot.region
                            end
                        end
                    end
                else
                    -- Non-split row: whole member is one slot
                    slotTotal = slotTotal + 1
                    local navLabel = GetSearchLabel(m)
                    local memberMatch = navLabel ~= "" and navLabel:lower():find(lowerQuery, 1, true)
                    if vs.sectionMatch or memberMatch then
                        litSlots = litSlots + 1
                        litTargets[#litTargets + 1] = m
                    end
                end
            end -- _isSpacer else
        end
    end

    -- Same slot/highlight accounting for visible orphans: they already passed the match check, so unlike section members there is no "section matched" bypass to OR in.
    for _, orphan in ipairs(visibleOrphans) do
        if not orphan._isSpacer then
            local slots = {}
            if orphan._leftRegion then
                slots[#slots + 1] =
                    { region = orphan._leftRegion, label = orphan._leftRegion._slotLabel or "" }
            end
            if orphan._midRegion then
                slots[#slots + 1] = { region = orphan._midRegion, label = orphan._midRegion._slotLabel or "" }
            end
            if orphan._rightRegion then
                slots[#slots + 1] =
                    { region = orphan._rightRegion, label = orphan._rightRegion._slotLabel or "" }
            end

            if #slots > 0 then
                for _, slot in ipairs(slots) do
                    if slot.label ~= "" then
                        slotTotal = slotTotal + 1
                        local slotMatch = slot.label:lower():find(lowerQuery, 1, true)
                        if not slotMatch then
                            local ddText = GetDropdownValueText(slot.region)
                            if ddText then slotMatch = ddText:lower():find(lowerQuery, 1, true) end
                        end
                        if slotMatch then
                            litSlots = litSlots + 1
                            litTargets[#litTargets + 1] = slot.region
                        end
                    end
                end
            else
                slotTotal = slotTotal + 1
                litSlots = litSlots + 1
                litTargets[#litTargets + 1] = orphan
            end
        end
    end

    -- If every visible slot is highlighted, suppress all highlights
    local suppressHighlights = (litSlots >= slotTotal)

    -- Build a fast lookup for highlight targets
    local litSet = {}
    if not suppressHighlights then
        for _, target in ipairs(litTargets) do
            litSet[target] = true
        end
    end

    -- Re-anchor visible items sequentially from top
    local startY = -6
    local rowY = startY

    -- Matching orphans lead the page (always before the first section in the source
    -- layout), so place and highlight them first; the sections loop continues from y.
    for _, orphan in ipairs(visibleOrphans) do
        if orphan._isSpacer then
            orphan:Hide()
        else
            local ox = orphan._origAnchor and orphan._origAnchor[4] or CONTENT_PAD
            orphan:ClearAllPoints()
            PanelPP.Point(orphan, "TOPLEFT", cachedPage.wrapper, "TOPLEFT", ox, rowY)
            orphan:Show()

            if not suppressHighlights and not skipHighlights then
                if orphan._leftRegion and litSet[orphan._leftRegion] then
                    local pulse = GetSearchHighlight()
                    PlaySearchHighlight(pulse, orphan._leftRegion)
                end
                if orphan._midRegion and litSet[orphan._midRegion] then
                    local pulse = GetSearchHighlight()
                    PlaySearchHighlight(pulse, orphan._midRegion)
                end
                if orphan._rightRegion and litSet[orphan._rightRegion] then
                    local pulse = GetSearchHighlight()
                    PlaySearchHighlight(pulse, orphan._rightRegion)
                end
                if not orphan._leftRegion and litSet[orphan] then
                    local pulse = GetSearchHighlight()
                    PlaySearchHighlight(pulse, orphan)
                end
            end

            rowY = rowY - orphan:GetHeight()
        end
    end

    for _, vs in ipairs(visibleSections) do
        local section = vs.sec
        local hdrX = section.header._origAnchor and section.header._origAnchor[4] or CONTENT_PAD
        section.header:ClearAllPoints()
        PanelPP.Point(section.header, "TOPLEFT", cachedPage.wrapper, "TOPLEFT", hdrX, rowY)
        section.header:Show()
        rowY = rowY - section.header:GetHeight()

        for _, m in ipairs(section.members) do
            -- Hide spacers during search -- they're just empty gaps
            if m._isSpacer then
                m:Hide()
            else
                local mx = m._origAnchor and m._origAnchor[4] or CONTENT_PAD
                m:ClearAllPoints()
                PanelPP.Point(m, "TOPLEFT", cachedPage.wrapper, "TOPLEFT", mx, rowY)
                m:Show()

                if not suppressHighlights and not skipHighlights then
                    -- Check slot-level highlights for split rows
                    if m._leftRegion and litSet[m._leftRegion] then
                        local pulse = GetSearchHighlight()
                        PlaySearchHighlight(pulse, m._leftRegion)
                    end
                    if m._midRegion and litSet[m._midRegion] then
                        local pulse = GetSearchHighlight()
                        PlaySearchHighlight(pulse, m._midRegion)
                    end
                    if m._rightRegion and litSet[m._rightRegion] then
                        local pulse = GetSearchHighlight()
                        PlaySearchHighlight(pulse, m._rightRegion)
                    end
                    -- Non-split row highlight
                    if not m._leftRegion and litSet[m] then
                        local pulse = GetSearchHighlight()
                        PlaySearchHighlight(pulse, m)
                    end
                end

                rowY = rowY - m:GetHeight()
            end -- _isSpacer else
        end
    end

    -- Resize content to fit visible items only
    local visibleH = math.abs(rowY - startY)
    if #visibleSections == 0 and #visibleOrphans == 0 and searchQuery:match("%S") then
        SetInlineEmptyHint(searchQuery)
        visibleH = 140
    end
    contentFrame:SetHeight(visibleH + 30)

    if contentScroll and contentScroll.SetVerticalScroll then
        scrollTarget = 0
        smoothing = false
        if smoother then smoother:Hide() end
        contentScroll:SetVerticalScroll(0)
        UpdateScrollThumb()
    end
    -- Mark this page as currently search-filtered so it is reliably restored when
    -- shown again, even if the search box was cleared on a tab/module switch.
    cachedPage._searchFiltered = true
end

-------------------------------------------------------------------------------
--  Sidebar highlight  (icon on/off swap)
-------------------------------------------------------------------------------
UpdateSidebarHighlight = function(selectedFolder)
    for moduleKey, button in pairs(sidebarButtons) do
        button._hoverGlow:Hide()
        button._hoverIndicator:Hide()
        if moduleKey == selectedFolder then
            button._indicator:Show()
            button._glow:Show()
            button._label:SetTextColor(
                NAV_SELECTED_TEXT.r,
                NAV_SELECTED_TEXT.g,
                NAV_SELECTED_TEXT.b,
                NAV_SELECTED_TEXT.a
            )
            if button._icon then
                button._icon:SetTexture(button._iconOff)
                button._icon:SetDesaturated(false)
                button._icon:SetAlpha(NAV_SELECTED_ICON_A)
            end
            if button._iconGlow then button._iconGlow:Show() end
        else
            button._indicator:Hide()
            button._glow:Hide()
            button._glowTop:Hide()
            button._glowBot:Hide()
            if button._iconGlow then button._iconGlow:Hide() end
            if button._loaded then
                button._label:SetTextColor(
                    NAV_ENABLED_TEXT.r,
                    NAV_ENABLED_TEXT.g,
                    NAV_ENABLED_TEXT.b,
                    NAV_ENABLED_TEXT.a
                )
                if button._icon then
                    button._icon:SetTexture(button._iconOff)
                    button._icon:SetDesaturated(false)
                    button._icon:SetAlpha(NAV_ENABLED_ICON_A)
                end
            else
                button._label:SetTextColor(
                    NAV_DISABLED_TEXT.r,
                    NAV_DISABLED_TEXT.g,
                    NAV_DISABLED_TEXT.b,
                    NAV_DISABLED_TEXT.a
                )
                if button._icon then
                    button._icon:SetDesaturated(true)
                    button._icon:SetAlpha(NAV_DISABLED_ICON_A)
                end
            end
        end
    end
    -- Controller cursor: the selected row is its first stop when the window opens.
    if CUI.PadCP() then
        for moduleKey, button in pairs(sidebarButtons) do
            CUI.PadHint(button, "nodepriority", moduleKey == selectedFolder and 1 or false)
        end
    end
end

-------------------------------------------------------------------------------
--  Content clearing
-------------------------------------------------------------------------------
-- Empties the content area when the selected module has no pages: clears the
-- refresh list, the content header and the row counters, then hides every child
-- and region of contentChild. The cached page wrappers among them stay attached
-- (_pageCache still holds them and shows them again).
ClearContent = function()
    if not contentChild then return end
    -- Clear widget refresh registry
    WipeWidgetRefreshes()
    -- Clear content header (non-scrolling region) if active
    if CUI.ClearContentHeader then CUI:ClearContentHeader() end
    -- Reset alternating row counters
    ResetRowCounters()
    -- Clear per-page layout flags so they don't bleed into the next page
    if contentChild then contentChild._showRowDivider = nil end
    -- Hide copy popup if visible
    if CUI._copyPopup then CUI._copyPopup:Hide() end
    if CUI._copyBackdrop then CUI._copyBackdrop:Hide() end
    -- Hidden, never detached: a detached cached wrapper would show again
    -- detached from the panel when its page is revisited.
    local children = { contentChild:GetChildren() }
    for _, kid in ipairs(children) do
        kid:Hide()
    end
    local regions = { contentChild:GetRegions() }
    for _, regionObj in ipairs(regions) do
        regionObj:Hide()
    end
end

-------------------------------------------------------------------------------
--  SPLIT COLUMN LAYOUT
--  Creates two side-by-side scrollable column frames with a 1px divider.
--  Usage:  local left, right, splitFrame = CludesUI:CreateSplitColumns(parent, yOffset)
--  Widgets anchor to left/right using the same TOPLEFT + yOffset pattern.
--  Call splitFrame:SetHeight(maxH) after populating both columns.
-------------------------------------------------------------------------------
function CUI:CreateSplitColumns(parent, yOffset)
    local PAD = 20 -- space between column edge and divider
    local DIV_W = 1 -- divider width
    local totalW = parent:GetWidth()
    local colW = math.floor((totalW - PAD * 2 - DIV_W) / 2)
    -- Pooled with the page on a page-pool host (CludesUI_FramePool.lua).
    local NewFrame = CUI_NS.PoolCreateFrame or CreateFrame

    local columns = NewFrame("Frame", nil, parent)
    columns:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset or 0)
    columns:SetWidth(totalW)
    columns:SetHeight(1) -- caller sets final height

    local leftCol = NewFrame("Frame", nil, columns)
    leftCol:SetPoint("TOPLEFT", columns, "TOPLEFT", 0, 0)
    leftCol:SetSize(colW, 1)

    local divider = columns:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.08)
    divider:SetWidth(DIV_W)
    divider:SetPoint("TOP", columns, "TOP", 0, 0)
    divider:SetPoint("BOTTOM", columns, "BOTTOM", 0, 0)

    local rightCol = NewFrame("Frame", nil, columns)
    rightCol:SetPoint("TOPRIGHT", columns, "TOPRIGHT", 0, 0)
    rightCol:SetSize(colW, 1)

    columns._leftCol = leftCol
    columns._rightCol = rightCol
    columns._divider = divider
    columns._colW = colW

    -- Mark columns with split parent so RowBg can extend backgrounds full width
    leftCol._splitParent = columns
    rightCol._splitParent = columns

    return leftCol, rightCol, columns
end

-------------------------------------------------------------------------------
--  Module Registration
--  RegisterModule is the suite's own entry point. Third-party addons use
--  CludesUI.RegisterPlugin (see the Plugin API section), which can only create
--  new sidebar sections; a page an older addon registers here under a key of its
--  own still registers as it always did (see "Pages from addons written before
--  this API"). For the suite's own pages:
--   * the caller's file must resolve to a trusted folder; every other caller,
--     including one without a file path (a loadstring chunk, a call routed
--     through a C function), and every key that is not a suite page, takes that
--     outside path, which never takes a suite key;
--   * outside standalone builds the only trusted caller is the options addon, and
--     only while it loads or the core drains its deferred inits
--     (CUI_NS.CoreRegistrationOpen), so a suite key cannot be claimed ahead of
--     the real registration;
--   * only suite keys are accepted (suite folders + the fixed panel pages), and
--     each one is sealed on first registration: it cannot be registered again.
-------------------------------------------------------------------------------
do
    -- Locals, not globals: setfenv on the public RegisterModule must not be
    -- able to swap the functions that see the caller's config and stack.
    local type, debugstack = type, debugstack
    -- Non-roster suite pages that register through RegisterModule.
    local CORE_PAGE_KEYS = {
        [CUI.GLOBAL_KEY] = true,
        _CUIProfiles = true,
        _CUIPatchNotes = true,
        _CUILegends = true,
    }
    local sealed = {}
    -- The suite's own addon folders (callers in standalone builds; the suite-core
    -- marker below).
    local ALLOWED = {
        CludesUI = true,
        CludesUIOptions = true, -- the LoadOnDemand options surface: every module's options file registers from here
        CludesUIActionBars = true,
        CludesUIAuraBuffReminders = true,
        CludesUICooldownManager = true,
        CludesUINameplates = true,
        CludesUIRaidFrames = true,
        CludesUIResourceBars = true,
        CludesUIUnitFrames = true,
        CludesUIMythicTimer = true,
        CludesUITank = true,
        CludesUIRaidLead = true,
        CludesUITitleLine = true,
        -- v6.6 split
        CludesUIQoL = true,
        CludesUIBlizzardSkin = true,
        CludesUIQuestTracker = true,
        CludesUIMinimap = true,
        CludesUIFriends = true,
        CludesUIChat = true,
        CludesUIDamageMeters = true,
        CludesUIBags = true,
        CludesUIDataBars = true,
        CludesUIQuickdraw = true,
        CludesUILoadoutManager = true,
        CludesUIGroupFinder = true,
        CludesUIForeverEssentials = true,
        CludesUISimpleLootCouncil = true,
    }

    -- Shared tail of every accepted registration. Only reachable from the
    -- trusted paths below and from the plugin registry. open: an outside
    -- addon's own key, which it may register again (as it always could).
    function CUI_NS.StoreModule(moduleFolder, moduleConfig, open)
        if not open then sealed[moduleFolder] = true end
        moduleList[moduleFolder] = moduleConfig
        -- If the UI is built, update the sidebar button now; else RefreshSidebarStates does it on first open
        local button = sidebarButtons[moduleFolder]
        if button then
            button._loaded = true
            button._label:SetTextColor(
                NAV_ENABLED_TEXT.r,
                NAV_ENABLED_TEXT.g,
                NAV_ENABLED_TEXT.b,
                NAV_ENABLED_TEXT.a
            )
            if button._icon then
                button._icon:SetDesaturated(false)
                button._icon:SetAlpha(NAV_ENABLED_ICON_A)
            end
        end
        -- Don't auto-select here; RefreshSidebarStates handles default selection in roster order
    end

    function CUI_NS.IsModuleKeyTaken(moduleFolder) return sealed[moduleFolder] == true end

    -- One of the suite's own addon folders (exact names: an outside addon may
    -- start its folder name with "CludesUI" too).
    function CUI_NS.IsSuiteFolder(moduleKey) return ALLOWED[moduleKey] == true end

    -- A suite page's key: any suite folder (including one the running client
    -- hides from the sidebar), one of the fixed panel pages, or a key the core
    -- registered itself.
    function CUI_NS.IsSuiteKey(entryKey)
        if CUI_NS.IsPluginKey(entryKey) then return false end
        return ALLOWED[entryKey] == true or CORE_PAGE_KEYS[entryKey] == true or sealed[entryKey] == true
    end

    -- Internal registration for pages the core file builds itself (no caller check).
    function CUI_NS.RegisterCoreModule(moduleFolder, moduleConfig, isCore)
        if type(moduleFolder) ~= "string" or type(moduleConfig) ~= "table" then return false end
        if sealed[moduleFolder] or CUI_NS.IsPluginKey(moduleFolder) then return false end
        moduleConfig._cuiCore = isCore == true
        moduleConfig._plugin = nil
        CUI_NS.StoreModule(moduleFolder, moduleConfig)
        return true
    end

    function CUI:RegisterModule(moduleFolder, moduleConfig)
        if type(moduleFolder) ~= "string" or type(moduleConfig) ~= "table" then return end
        -- The caller's addon folder, from its file path (nil without one).
        local caller = debugstack(2, 1, 0) or ""
        local callerFolder = caller:match("AddOns/([^/]+)/")
        -- A suite page from one of our folders: accepted from the options addon
        -- inside the registration window, never from anywhere else. Standalone
        -- builds bundle the options files flat into the one addon.
        if
            callerFolder
            and ALLOWED[callerFolder]
            and (ALLOWED[moduleFolder] or CORE_PAGE_KEYS[moduleFolder])
        then
            if IS_STANDALONE or (callerFolder == "CludesUIOptions" and CUI_NS.CoreRegistrationOpen()) then
                -- Suite-core marker (module key is a suite folder), gating the toolbar whitelists:
                -- the overrides icon renders for core modules only, the inline search for core
                -- modules + Global Settings. Companion/external pages stay unmarked, so neither
                -- control renders for them (see SelectModule).
                CUI_NS.RegisterCoreModule(moduleFolder, moduleConfig, ALLOWED[moduleFolder] == true)
            end
            return
        end
        -- Anything else is another addon's, whatever folder its caller names: a
        -- page under a key of its own registers as it did before the plugin API;
        -- a suite page is never replaced.
        CUI_NS.RegisterExternal(callerFolder, moduleFolder, moduleConfig)
    end
    -- The core registers the suite's own pages through this one, never through
    -- whatever may sit on the public slot by then (CludesUI.lua).
    CUI_NS.CoreRegisterModule = CUI.RegisterModule
end

-------------------------------------------------------------------------------
--  Page / Module Selection
-------------------------------------------------------------------------------
-- From here on the public functions iterate private tables (page cache, a
-- module's page list): local iterators mean setfenv cannot swap in one that
-- is handed those tables. (Declared after CreateMainFrame and its Build*
-- functions; BuildSidebar and BuildContent declare their own pairs, the others
-- use none.)
local pairs, ipairs = pairs, ipairs
-- Page cache: maps "moduleName::pageName" -> { wrapper, totalH, headerBuilder }
-- On revisit, we show the cached wrapper and refresh widget values instead of rebuilding.
_pageCache = {}
-- Private: an entry's headerBuilder / wrapper is live page content, so the
-- cache is shared with the core files only (global search reads it).
CUI_NS.pageCache = _pageCache
local _activePageWrapper -- the currently-visible wrapper frame

-- Page reuse (CludesUIOptions/CludesUI_FramePool.lua). A suite page under
-- the one switch (CludesUI._reusePages) keeps ONE wrapper for the session:
-- every pass of the page dresses it again (entry.reuse), an invalidation only
-- marks the entry stale (the page stays on screen until its rebuild), and its
-- header gets a kept root. Every other page (plugins, other addons' pages, every
-- page while the switch is off) is built anew and dropped as it always was.
-- An entry keeps the mode it was made with.
local function ReuseFor(moduleName)
    return CUI._reusePages and CUI_NS.PoolKept ~= nil and CUI_NS.IsSuiteKey(moduleName) or false
end

-- The page whose content header is being built, when it builds into a kept
-- root: the page pass's page, else the active one (selector handlers).
function CUI_NS.HeaderReuseKey()
    local m, p = CUI._buildingModule, CUI._buildingPage
    if not (m and p) then
        m, p = currentModule, activePage
    end
    if not (m and p) or not ReuseFor(m) then return nil end
    return m .. "::" .. p
end

-- A build-and-drop page's teardown: hidden, detached (WoW never frees it), dropped.
local function DropLegacyPage(entryKey, record)
    if record.wrapper then
        record.wrapper:Hide()
        record.wrapper:SetParent(nil)
    end
    _pageCache[entryKey] = nil
end

-- The active page lost its entry, or holds a stale one, while the panel is closed
-- or folded: it is rebuilt as the panel shows again instead of showing blank
-- (RefreshPage's deferral, consumed by the on-show callback and the unfold).
local function PendActiveRebuild()
    if not (currentModule and activePage) then return end
    if panelFrame and panelFrame:IsShown() and not CUI._panelCollapsed then return end
    local e = _pageCache[currentModule .. "::" .. activePage]
    if not e or e.stale then CUI._pendingForceRefresh = true end
end

-- Invalidate all cached pages (called on profile reset, module reload, etc.)
function CUI:InvalidatePageCache()
    local keepActive
    for entryKey, record in pairs(_pageCache) do
        if record.reuse then
            record.stale = true
            if record.wrapper == _activePageWrapper then keepActive = true end
        else
            DropLegacyPage(entryKey, record)
        end
    end
    if not keepActive then _activePageWrapper = nil end
    if CUI.InvalidateContentHeaderCache then CUI:InvalidateContentHeaderCache() end
    PendActiveRebuild()
end

-- Invalidate cached pages for a SINGLE module (key prefix "Module::"), e.g. on spec change
-- where only the per-spec module's pages go stale. Panel OPEN: the shown page's wrapper is kept
-- so the screen is not blanked (the caller rebuilds it in place via RefreshPage(true)). Panel
-- CLOSED: every cached page is dropped for a fresh build. Teardown matches RefreshPage: Hide + SetParent(nil) the wrapper, then drop the entry.
function CUI:InvalidateModulePageCache(moduleName)
    if not moduleName then return end
    local prefix = moduleName .. "::"
    local keepKey
    if self.IsShown and self:IsShown() and currentModule and activePage then
        keepKey = currentModule .. "::" .. activePage
    end
    for entryKey, record in pairs(_pageCache) do
        if entryKey:sub(1, #prefix) == prefix and entryKey ~= keepKey then
            if record.reuse then
                record.stale = true
            else
                DropLegacyPage(entryKey, record)
            end
        end
    end
    PendActiveRebuild()
end

-- Every page whose last build read the search flag (the "Show Less Common"
-- sections, Bar Glows): stale (page reuse) or dropped, with its header. True when
-- the active page is one of them (the caller rebuilds it).
function CUI._InvalidateSearchSensitive()
    local activeKey = currentModule and activePage and (currentModule .. "::" .. activePage)
    local hit = false
    for entryKey, record in pairs(_pageCache) do
        if record.searchSensitive then
            if entryKey == activeKey then hit = true end
            if record.reuse then
                record.stale = true
            else
                DropLegacyPage(entryKey, record)
            end
            if CUI_NS.InvalidateHeaderKey then CUI_NS.InvalidateHeaderKey(entryKey) end
        end
    end
    return hit
end

-- Page passes in progress (pageKey -> true), and the forced refreshes that
-- reached a page while it was being built (pageKey -> true): each of those
-- runs once, after the build in progress.
local _passing, _passAgain = {}, {}

-- One page pass: the page is built anew (build-and-drop) or its kept wrapper is
-- dressed again (page reuse), then its cache entry is recorded. refresh: the
-- RefreshPage slow path (the old page goes first, the scroll range is held
-- during the build); else the SelectPage cold path. buildPage and the header
-- getter run under xpcall: an error reaches the error handler and the page is
-- built again on its next visit (a reuse entry stays stale; a failed
-- build-and-drop page records no entry, as before).
local function PagePassBody(pageKey, pageTitle, moduleConfig, refresh)
    local record = _pageCache[pageKey]
    local reuse
    if record then
        reuse = record.reuse
    else
        reuse = ReuseFor(currentModule)
    end
    -- stale until this pass completes: a pass that stops half way is built again
    if reuse and record then record.stale = true end
    local wrapper
    if reuse then
        RecycleAllSearchHighlights(true)
        WipeWidgetRefreshes()
        if CUI.ClearContentHeader then CUI:ClearContentHeader() end
        ResetRowCounters()
        if contentChild then contentChild._showRowDivider = nil end
        if CUI._copyPopup then CUI._copyPopup:Hide() end
        if CUI._copyBackdrop then CUI._copyBackdrop:Hide() end
        if refresh then
            skipScrollChildReanchor = true
            suppressScrollRangeChanged = true
        end
        -- The reset of the kept wrapper is the teardown: its visible parts get
        -- OnHide with their old scripts, what it held is parked or buried.
        wrapper = CUI_NS.PoolKept(CUI_NS.wrapperOwner, pageKey, "Frame", contentChild)
        wrapper:SetAllPoints(contentChild)
    elseif refresh then
        -- Invalidate the current page's cache entry and destroy ONLY its wrapper. CRITICAL: do NOT
        -- call ClearContent() here -- other cached pages' wrappers are still referenced by
        -- _pageCache and are restored when the user switches back to their tab.
        if record and record.wrapper then
            record.wrapper:Hide()
            record.wrapper:SetParent(nil)
        end
        _pageCache[pageKey] = nil
        record = nil
        -- Clear widget refresh registry and header (safe -- these are per-page)
        WipeWidgetRefreshes()
        if CUI.ClearContentHeader then CUI:ClearContentHeader() end
        ResetRowCounters()
        if contentChild then contentChild._showRowDivider = nil end
        if CUI._copyPopup then CUI._copyPopup:Hide() end
        if CUI._copyBackdrop then CUI._copyBackdrop:Hide() end
        skipScrollChildReanchor = true
        suppressScrollRangeChanged = true
        -- Create a fresh wrapper for the rebuilt page
        wrapper = CreateFrame("Frame", nil, contentChild)
        wrapper:SetAllPoints(contentChild)
    else
        -- Cold path: clear the content header, then a wrapper frame for this page
        lastHeaderPadded = false
        WipeWidgetRefreshes()
        ResetRowCounters()
        if CUI._copyPopup then CUI._copyPopup:Hide() end
        if CUI._copyBackdrop then CUI._copyBackdrop:Hide() end
        if CUI.ClearContentHeader then CUI:ClearContentHeader() end
        wrapper = CreateFrame("Frame", nil, contentChild)
        wrapper:SetAllPoints(contentChild)
    end
    _activePageWrapper = wrapper

    local ok, totalH = true, 0
    if moduleConfig.buildPage then
        CUI._passReadSearchFlag = nil
        CUI._buildingModule = currentModule
        CUI._buildingPage = pageTitle
        local h
        ok, h = xpcall(moduleConfig.buildPage, CUI_NS.ReportError, pageTitle, wrapper, -6)
        if CUI._CloseSectionCards then CUI._CloseSectionCards() end
        CUI._buildingModule = nil
        CUI._buildingPage = nil
        CUI._buildingSelector = nil
        totalH = (ok and h ~= nil and tonumber(h)) or 600
        contentFrame:SetHeight(totalH + 30)
    end

    -- The content header builder for this page (if one was set); a getter that
    -- fails counts as a failed build
    local headerBuilder = nil
    if moduleConfig.getHeaderBuilder then
        local okH, hb = xpcall(moduleConfig.getHeaderBuilder, CUI_NS.ReportError, pageTitle)
        if okH then
            headerBuilder = hb
        else
            ok = false
        end
    end
    local searchSensitive = CUI._passReadSearchFlag or nil
    CUI._passReadSearchFlag = nil

    if reuse then
        if not record then
            record = { reuse = true, refreshList = {} }
            _pageCache[pageKey] = record
        end
        record.wrapper = wrapper
        record.totalH = totalH
        record.headerBuilder = headerBuilder
        local rl = record.refreshList
        for i = #rl, 1, -1 do
            rl[i] = nil
        end
        for i = 1, #_widgetRefreshList do
            rl[i] = _widgetRefreshList[i]
        end
        record.stale = (not ok) or nil
        record._searchFiltered = nil
        record.searchSensitive = searchSensitive
    elseif ok then
        -- Cache this page's refresh list
        local cachedRefreshList = {}
        for i = 1, #_widgetRefreshList do
            cachedRefreshList[i] = _widgetRefreshList[i]
        end
        _pageCache[pageKey] = {
            wrapper = wrapper,
            totalH = totalH,
            headerBuilder = headerBuilder,
            refreshList = cachedRefreshList,
            searchSensitive = searchSensitive,
        }
    end
    CUI._pageBuildSerial = (CUI._pageBuildSerial or 0) + 1
    if reuse and CUI_NS.PoolDevEndPass then CUI_NS.PoolDevEndPass(wrapper, pageKey) end
end

-- rerun: this pass runs a forced refresh that reached the page during its
-- previous pass. Whatever fails inside, no pass state outlives the pass.
local function RunPagePass(pageKey, pageTitle, moduleConfig, refresh, rerun)
    if _passing[pageKey] then
        _passAgain[pageKey] = true
        return
    end
    _passing[pageKey] = true
    xpcall(PagePassBody, CUI_NS.ReportError, pageKey, pageTitle, moduleConfig, refresh)
    CUI._buildingModule = nil
    CUI._buildingPage = nil
    CUI._buildingSelector = nil
    CUI._passReadSearchFlag = nil
    if refresh then
        skipScrollChildReanchor = false
        suppressScrollRangeChanged = false
    end
    _passing[pageKey] = nil
    if _passAgain[pageKey] then
        _passAgain[pageKey] = nil
        if not rerun then
            RunPagePass(pageKey, pageTitle, moduleConfig, true, true)
        elseif CUI.IsDevModeActive and CUI.IsDevModeActive() then
            -- a build that asks for its own rebuild on every pass: one rerun only
            CUI.PrintError(pageKey .. " asked for its own rebuild again while rebuilding; dropped")
        end
    end
end

-- A root a module renders itself after the page built (manager pages, General's
-- panes): wrapped in _BeginRootRender(key) / _EndRootRender(key), the refresh
-- callbacks the previous render of that root registered leave the live list
-- before the new render records its own (no stale refreshers on dressed-again
-- widgets, no growing list).
do
    local renders, drop = {}, {}
    function CUI._BeginRootRender(entryKey)
        if entryKey == nil then return end
        local record = renders[entryKey]
        if not record then
            record = { fns = {} }
            renders[entryKey] = record
        end
        local fns = record.fns
        if #fns > 0 then
            for i = 1, #fns do
                drop[fns[i]] = true
                fns[i] = nil
            end
            local entryList, n = _widgetRefreshList, 0
            for i = 1, #entryList do
                local fn = entryList[i]
                if not drop[fn] then
                    n = n + 1
                    entryList[n] = fn
                end
            end
            for i = #entryList, n + 1, -1 do
                entryList[i] = nil
            end
            wipe(drop)
        end
        record.mark = #_widgetRefreshList
    end
    function CUI._EndRootRender(entryKey)
        local record = entryKey ~= nil and renders[entryKey]
        if not (record and record.mark) then return end
        local fns, entryList = record.fns, _widgetRefreshList
        for i = record.mark + 1, #entryList do
            fns[#fns + 1] = entryList[i]
        end
        record.mark = nil
    end
end

-- The tab switch's re-snap roots: the page shown and its content header (weak:
-- a scratch set never keeps a dropped page alive).
local tabResnapRoots = setmetatable({}, { __mode = "k" })

function CUI:SelectPage(pageTitle)
    -- Excluded pages (CDM Bar Glows / Tracking Bars) lock during an override editing
    -- session: their systems keep their own per-spec storage, outside the capture.
    if
        CUI.SpecOverrides_EditSessionActive
        and CUI.SpecOverrides_EditSessionActive()
        and CUI.SpecOverrides_PageExcluded
        and CUI.SpecOverrides_PageExcluded(currentModule, pageTitle)
    then
        return
    end
    if not currentModule or not moduleList[currentModule] then return end
    if pageTitle == activePage then return end

    -- A link tab (config.pageLinks[pageTitle] = { module =, page = }) opens another
    -- module's page instead of one of its own. Nothing here changes, so coming
    -- back lands on the page that was open.
    local links = moduleList[currentModule].pageLinks
    local linkText = links and links[pageTitle]
    if linkText then
        if moduleList[linkText.module] then
            -- SelectModule opens a module on its last page: make that the target,
            -- so the module's previous page is never built on the way.
            _lastPagePerModule[linkText.module] = linkText.page
            self:SelectModule(linkText.module)
            if activePage ~= linkText.page then self:SelectPage(linkText.page) end
        end
        return
    end

    -- "Unlock Mode" is a fake nav item -- fire unlock mode without changing page state.
    -- Capture the current module + page so DoClose can restore them exactly.
    if pageTitle == "Layout Mode" then
        if CUI._openUnlockMode then
            CUI._unlockReturnModule = currentModule
            CUI._unlockReturnPage = activePage
            C_Timer.After(0, CUI._openUnlockMode)
        end
        return
    end

    -- "Disable Addons" is a fake nav item -- close CUI and open the Blizzard addon list.
    if pageTitle == "Disable Addons" then
        if CUI._mainFrame then CUI._mainFrame:Hide() end
        C_Timer.After(0, function()
            if not AddonList then C_AddOns.LoadAddOn("Blizzard_AddonList") end
            if AddonList then ShowUIPanel(AddonList) end
        end)
        return
    end

    -- Restore the page's inline-search filter and clear the box BEFORE switching activePage:
    -- SetText("") fires ApplyInlineSearch("") via OnTextChanged, which keys off activePage, so it
    -- must still point at the filtered page or it stays stuck in its filtered layout (looks "searched" with an empty box) until re-search.
    -- _selectingPage: the page being left is only marked for a rebuild, never rebuilt now.
    if tabStrip and tabStrip._searchBox and tabStrip._searchBox:GetText() ~= "" then
        CUI._selectingPage = true
        tabStrip._searchBox:SetText("")
        CUI._selectingPage = nil
    end

    -- Save current page's refresh list before switching
    if activePage then
        local oldKey = currentModule .. "::" .. activePage
        if _pageCache[oldKey] then
            local rl = _pageCache[oldKey].refreshList
            if not rl then
                rl = {}
                _pageCache[oldKey].refreshList = rl
            end
            -- Wipe and repopulate in-place
            for i = #rl, 1, -1 do
                rl[i] = nil
            end
            for i = 1, #_widgetRefreshList do
                rl[i] = _widgetRefreshList[i]
            end
        end
        -- Save current content header to cache before leaving this page
        CUI:SaveContentHeaderToCache(oldKey)
    end

    activePage = pageTitle
    _lastPagePerModule[currentModule] = pageTitle
    UpdateTabHighlight(pageTitle)
    -- A page that draws its own layout over the scroll frame (a manager page,
    -- config.noSearchPages) has nothing the inline search can filter: the box
    -- shows disabled there.
    if tabStrip and tabStrip._setSearchDisabled then
        local noSearch = moduleList[currentModule].noSearchPages
        tabStrip._setSearchDisabled(noSearch ~= nil and noSearch[pageTitle] == true)
    end

    local pageKey = currentModule .. "::" .. pageTitle
    local cachedPage = _pageCache[pageKey]

    -- Reconcile the two independent caches before the fast path. The page wrapper (_pageCache)
    -- and the content-header PREVIEW (_contentHeaderCache) cache separately, but the preview's
    -- interactive hit overlays are created ONLY by buildPage. If InvalidateContentHeaderCache ran
    -- while this page's wrapper stayed cached, a header-only SetContentHeader rebuild recreates
    -- the preview with NO overlays -- visible but dead to hover/click until /reload. So a page
    -- that HAS a preview but misses its header cache discards the stale wrapper (RefreshPage teardown) and falls through to a cold rebuild; pages without a headerBuilder stay on the fast path.
    -- A page-reuse entry that is stale, or whose header root is, keeps its wrapper: the cold
    -- path dresses it again in place, page and header together.
    if cachedPage and cachedPage.wrapper then
        HideAllChildren(contentChild)
        if cachedPage.reuse and cachedPage.stale then
            cachedPage = nil
        elseif not CUI:RestoreContentHeaderFromCache(pageKey) then
            if cachedPage.headerBuilder then
                if not cachedPage.reuse then
                    cachedPage.wrapper:Hide()
                    cachedPage.wrapper:SetParent(nil)
                    _pageCache[pageKey] = nil
                end
                cachedPage = nil
            elseif CUI.ClearContentHeader then
                CUI:ClearContentHeader()
            end
        end
    end

    if cachedPage and cachedPage.wrapper then
        -- Fast path (both caches in sync): show the cached wrapper, set child height
        cachedPage.wrapper:Show()
        _activePageWrapper = cachedPage.wrapper
        contentFrame:SetHeight(cachedPage.totalH + 30)

        -- Restore elements hidden by a previous inline search, keyed off the page's own filtered
        -- flag and NOT the search box: clearing the box on a tab/module switch does not reliably
        -- restore the page being left, so a cached page can stay filtered while the box reads empty. The flag tracks the real state.
        if cachedPage._searchFiltered then CUI:ApplyInlineSearch("") end

        -- Restore this page's refresh list
        WipeWidgetRefreshes()
        if cachedPage.refreshList then
            for i = 1, #cachedPage.refreshList do
                _widgetRefreshList[i] = cachedPage.refreshList[i]
            end
        end

        -- Refresh all widget values in-place
        for i = 1, #_widgetRefreshList do
            _widgetRefreshList[i]()
        end

        -- Fire module-level refresh hooks (preview update, etc.)
        local moduleConfig = moduleList[currentModule]
        if moduleConfig.onPageCacheRestore then moduleConfig.onPageCacheRestore(pageTitle) end
    else
        -- Cold path: build page for the first time (or dress its kept wrapper again)
        HideAllChildren(contentChild)
        RunPagePass(pageKey, pageTitle, moduleList[currentModule], false)
    end

    -- Reset scroll to top on tab switch
    if contentScroll and contentScroll.SetVerticalScroll then
        scrollTarget = 0
        smoothing = false
        if smoother then smoother:Hide() end
        contentScroll:SetVerticalScroll(0)
        UpdateScrollThumb()
    end

    -- Re-snap PP borders after a tab switch: cached frames re-show without
    -- CreateBorder's built-in 2-frame re-snap, so borders misalign until reopen. Wait
    -- 1 frame so the hierarchy has finished layout before recalculating effective scales.
    -- The content header goes with the page (one shown after a scale change it missed);
    -- the kept header roots of other pages wait for their own tab switch.
    C_Timer.After(0, function()
        if PP and _activePageWrapper then
            wipe(tabResnapRoots)
            tabResnapRoots[_activePageWrapper] = true
            if headStrip then tabResnapRoots[headStrip] = true end
            -- the active kept header root is a root of its own (its parts sit one
            -- level deeper than the walk from the header frame reaches)
            local Hdr = CUI_NS.hdr
            for _, rootFrame in pairs(Hdr.roots) do
                tabResnapRoots[rootFrame] = (rootFrame == Hdr.active) or "skip"
            end
            PP.ResnapBordersUnderRoots(tabResnapRoots)
        elseif PP and PP.ResnapAllBorders then
            PP.ResnapAllBorders()
        end
    end)
end

-- Rebuild the current page content without resetting scroll position
-- Pass force=true to bypass the fast refresh path (e.g. when widget layout changes).
function CUI:RefreshPage(force)
    if not currentModule or not activePage then return end
    -- Panel hidden: a rebuild here would run buildPage with nothing on screen, firing page-open
    -- side effects (preview flags, placeholder shows) AFTER the OnHide cleanup already cleared
    -- them -- they then stick until the next open (e.g. CDM buff previews staying visible when
    -- an override edit session tears down on panel close). Defer the rebuild to the next show instead; the on-show callback below consumes the flag before module OnShow handlers run.
    -- Folded to the mini window counts as hidden: a page built under the hidden body
    -- never shows, so its OnHide teardown (page-scoped event listeners) never runs.
    -- The unfold consumes the flag (CludesUI._SetPanelCollapsed).
    local hidden = not (panelFrame and panelFrame:IsShown()) or CUI._panelCollapsed
    -- Fast path: if widgets registered refresh callbacks, just re-read
    -- DB values in-place.  No frame teardown, no allocations.
    if not force and #_widgetRefreshList > 0 then
        -- Nothing on the page can be seen: the re-read waits for the next show
        -- (RunDeferredRefresh), so a closed panel repaints nothing.
        if hidden then
            CUI._pendingFastRefresh = true
            return
        end
        for i = 1, #_widgetRefreshList do
            _widgetRefreshList[i]()
        end
        return
    end
    if hidden then
        CUI._pendingForceRefresh = true
        return
    end
    -- A forced refresh reaching the page while it is being built runs once,
    -- right after that build (a nested build would leave the half-built page
    -- orphaned on screen).
    local pageKey = currentModule .. "::" .. activePage
    if _passing[pageKey] then
        _passAgain[pageKey] = true
        return
    end
    -- Slow path: full teardown + rebuild (page reuse: the kept wrapper dressed again)
    local savedScroll = contentScroll and contentScroll:GetVerticalScroll() or 0
    local savedTarget = scrollTarget

    RunPagePass(pageKey, activePage, moduleList[currentModule], true)

    smoothing = false
    if smoother then smoother:Hide() end
    if contentScroll then
        -- The range is stale right after the height change; recompute it so a
        -- shrunken page (card collapsed) clamps instead of keeping the old offset.
        contentScroll:UpdateScrollChildRect()
        local scrollMax = CUI.SafeScrollRange(contentScroll)
        local restored = math.min(savedScroll, scrollMax)
        scrollTarget = math.min(savedTarget, scrollMax)
        contentScroll:SetVerticalScroll(restored)
        UpdateScrollThumb()
    end
    -- The rebuilt wrapper is unfiltered while the search box still holds its text (a
    -- section-gate toggle clicked under a live search): re-apply the query so the page
    -- stays filtered. Highlights are skipped, like the box's own immediate pass.
    local sbox = tabStrip and tabStrip._searchBox
    local sq = sbox and sbox:GetText() or ""
    if sq ~= "" then
        CUI:ApplyInlineSearch(sq, true)
        -- The filter pass scrolls to the top (its keystroke behaviour); put the user
        -- back where the click happened, clamped to the filtered range.
        if contentScroll then
            local maxFiltered = CUI.SafeScrollRange(contentScroll)
            local back = math.min(savedScroll, maxFiltered)
            scrollTarget = back
            contentScroll:SetVerticalScroll(back)
            UpdateScrollThumb()
        end
    end
end

-- Consume a rebuild or re-read that was requested while the panel was hidden (see the
-- deferral inside RefreshPage). Registered here, before any module files load, so it runs
-- ahead of module OnShow callbacks -- they then observe the current page.
CUI:RegisterOnShow(RunDeferredRefresh)

-- Public: snap the settings scroll back to the top (e.g. in resource bars clicking on a
-- simple section to the Advanced page)
function CUI:ScrollToTop()
    if contentScroll and contentScroll.SetVerticalScroll then
        scrollTarget = 0
        smoothing = false
        if smoother then smoother:Hide() end
        contentScroll:SetVerticalScroll(0)
        UpdateScrollThumb()
    end
end

function CUI:GetActiveModule() return currentModule end

function CUI:GetModuleTitle(moduleFolder)
    local m = moduleFolder and moduleList[moduleFolder]
    return m and m.title
end

-------------------------------------------------------------------------------
--  Reset CUI Module Settings (Global Settings): the suite's module resets
--  in one menu, each behind the typed confirm. A module's config may set
--  resetScope ("account": settings every profile shares, "character": this
--  character's own; default: the current profile) and resetMessage (a
--  string, or a function returning one, in place of the standard question).
--  The reset runs as RequestReload's pre-reload work, as Reset ALL's wipe does.
-------------------------------------------------------------------------------
local RESET_SCOPE_TEXT = {
    profile = "Only your current profile is reset; your other profiles keep their settings.",
    account = "These settings are shared by every profile, so all of them are reset.",
    character = "Only this character's settings are reset.",
}

local function ConfirmModuleReset(entryKey, name)
    local moduleConfig = moduleList[entryKey]
    if not (moduleConfig and moduleConfig.onReset) then return end
    local title = CUI.Lf("Reset %1$s", name)
    local msg = moduleConfig.resetMessage
    if type(msg) == "function" then msg = msg() end
    CUI:ShowConfirmPopup({
        title = title,
        message = msg
            or CUI.Lf(
                "Are you sure you want to reset all %1$s settings to their defaults? This will reload your UI.",
                name
            ),
        disclaimer = CUI.L(RESET_SCOPE_TEXT[moduleConfig.resetScope] or RESET_SCOPE_TEXT.profile),
        typeToConfirm = "Confirm",
        confirmText = "Reset & Reload",
        cancelText = "Cancel",
        onConfirm = function()
            CUI.RequestReload(title, CUI.L("Reload to finish the reset."), function()
                local c = moduleList[entryKey]
                if c and c.onReset then c.onReset() end
            end)
        end,
    })
end

-- The menu under anchor: ALL Settings (onAll, the whole-account reset), then each
-- loaded suite module with a reset, Global Settings first and the rest in sidebar
-- order. Plugin and other addons' pages keep the footer Reset instead.
function CUI._ShowModuleResetMenu(anchor, onAll)
    local items = {
        {
            text = CUI.COLOR_CODES.BAD .. CUI.L("ALL Settings") .. "|r",
            noLoc = true,
            onClick = onAll,
        },
        "---",
    }
    local function Add(entryKey)
        local moduleConfig = moduleList[entryKey]
        if not (moduleConfig and moduleConfig.onReset and CUI_NS.IsSuiteKey(entryKey)) then return end
        local nav = CUI_NS.navInfo[entryKey]
        local name = CUI.L((nav and nav.display) or moduleConfig.title or entryKey)
        items[#items + 1] = {
            text = name,
            noLoc = true,
            onClick = function() ConfirmModuleReset(entryKey, name) end,
        }
    end
    Add(CUI.GLOBAL_KEY)
    for _, navGroup in ipairs(CUI_NS.coreGroups) do
        for _, entryKey in ipairs(navGroup.members) do
            Add(entryKey)
        end
    end
    CUI.ShowContextMenu(anchor, items, { below = true, scaleToAnchor = true })
end

function CUI:SelectModule(moduleFolder)
    if not moduleList[moduleFolder] then return end
    -- The panel is not always built when we get here: on the session's first
    -- open the first-open split (see _SplitFirstOpen) makes Show()/Toggle()
    -- return BEFORE CreateMainFrame, so a caller that opens the panel and
    -- selects a module in the same execution arrives with headerFrame nil.
    -- Bail before currentModule is written -- a half-applied selection also
    -- suppresses CreateMainFrame's default-module pick, leaving a blank panel.
    if not headerFrame then return end
    if moduleFolder == currentModule then return end
    -- Excluded modules are locked while an override editing session is
    -- active; blocking at the choke point covers every navigation path
    -- (sidebar, list rows, links), not just the grayed buttons.
    if
        CUI.SpecOverrides_EditSessionActive
        and CUI.SpecOverrides_EditSessionActive()
        and CUI.SpecOverrides_ModuleExcluded
        and CUI.SpecOverrides_ModuleExcluded(moduleFolder)
    then
        return
    end

    -- Re-sync pixel perfect mult on every addon switch
    if CUI.PanelPP then CUI.PanelPP.UpdateMult() end

    -- Save current page's content header under the CORRECT old key
    -- before we overwrite currentModule.
    if activePage and currentModule then
        local oldKey = currentModule .. "::" .. activePage
        if _pageCache[oldKey] then
            local rl = _pageCache[oldKey].refreshList
            if not rl then
                rl = {}
                _pageCache[oldKey].refreshList = rl
            end
            for i = #rl, 1, -1 do
                rl[i] = nil
            end
            for i = 1, #_widgetRefreshList do
                rl[i] = _widgetRefreshList[i]
            end
        end
        CUI:SaveContentHeaderToCache(oldKey)
    end

    -- Notify the module being left (mirrors onReset). No-op if unset.
    if currentModule and moduleList[currentModule] and moduleList[currentModule].onModuleLeave then
        moduleList[currentModule].onModuleLeave()
    end

    -- Restore the old module page's inline-search filter and clear the search box BEFORE
    -- switching modules, while currentModule/activePage still point to the filtered page.
    -- SetText("") fires ApplyInlineSearch("") via OnTextChanged; doing this after the switch would target the new module and leave the old page stuck in its filtered layout.
    if tabStrip and tabStrip._searchBox and tabStrip._searchBox:GetText() ~= "" then
        CUI._selectingPage = true
        tabStrip._searchBox:SetText("")
        CUI._selectingPage = nil
    end

    currentModule = moduleFolder
    local moduleConfig = moduleList[moduleFolder]
    CUI_NS.RevealSidebarRow(moduleFolder)
    UpdateSidebarHighlight(moduleFolder)
    headerFrame._title:SetText(CUI.L(moduleConfig.title or moduleFolder))
    local rb = footerBar and footerBar._resetBtn
    if rb and rb._label then
        local navEntry = CUI_NS.navInfo[moduleFolder]
        local displayName = (navEntry and navEntry.display) or moduleConfig.title or moduleFolder
        rb._label:SetText(CUI.Lf("Reset %1$s", CUI.L(displayName)))
        rb._label:SetWidth(rb:GetWidth() * 0.85)
        rb._label:SetWordWrap(false)
        rb._label:SetMaxLines(1)
    end
    if CUI._UpdateResetButtonVisible then
        CUI._UpdateResetButtonVisible(moduleConfig.onReset ~= nil and not CUI_NS.IsSuiteKey(moduleFolder))
    end
    headerFrame._desc:SetText(CUI.L(moduleConfig.description or ""))
    BuildTabs(moduleConfig.pages, moduleConfig.disabledPages, moduleConfig.disabledPageTooltips)
    -- Toolbar whitelists: the overrides icon and the inline search operate on suite data only
    -- (override capture, search index), so they render solely for whitelisted pages -- overrides:
    -- core modules; search: core modules + Global Settings. Foreign/companion pages get neither. (BuildTabs unconditionally shows the search frame; gate it here.)
    if tabStrip then
        local core = moduleConfig._cuiCore == true
        if tabStrip._searchFrame then
            tabStrip._searchFrame:SetShown(core or moduleFolder == CUI.GLOBAL_KEY)
        end
        if tabStrip._specOvBtn then tabStrip._specOvBtn:SetShown(core) end
    end
    local savedPage = _lastPagePerModule[moduleFolder]
    -- Validate saved page still exists in this module's page list
    local validPage = nil
    if savedPage and moduleConfig.pages then
        for _, p in ipairs(moduleConfig.pages) do
            if p == savedPage then
                validPage = savedPage
                break
            end
        end
    end
    local targetPage = validPage or (moduleConfig.pages and moduleConfig.pages[1])
    -- Clear activePage so SelectPage doesn't bail when the target page
    -- has the same name as the previous module's page (e.g. both have "General").
    activePage = nil
    if targetPage then
        self:SelectPage(targetPage)
    else
        activePage = nil
        ClearContent()
    end
end

-------------------------------------------------------------------------------
--  Show / Hide / Toggle
-------------------------------------------------------------------------------
local function SyncNavStates()
    -- Refresh global settings button state (unchanged -- still a dedicated
    -- always-visible row above the grouped scroll area).
    local globalButton = sidebarButtons["_CUIGlobal"]
    if globalButton then
        if "_CUIGlobal" == currentModule then
            globalButton._label:SetTextColor(
                NAV_SELECTED_TEXT.r,
                NAV_SELECTED_TEXT.g,
                NAV_SELECTED_TEXT.b,
                NAV_SELECTED_TEXT.a
            )
            globalButton._icon:SetTexture(globalButton._iconOff)
            globalButton._icon:SetDesaturated(false)
            globalButton._icon:SetAlpha(NAV_SELECTED_ICON_A)
            globalButton._iconGlow:Show()
        else
            globalButton._label:SetTextColor(
                NAV_ENABLED_TEXT.r,
                NAV_ENABLED_TEXT.g,
                NAV_ENABLED_TEXT.b,
                NAV_ENABLED_TEXT.a
            )
            globalButton._icon:SetTexture(globalButton._iconOff)
            globalButton._icon:SetDesaturated(false)
            globalButton._icon:SetAlpha(NAV_ENABLED_ICON_A)
            globalButton._iconGlow:Hide()
        end
    end

    local contentChild = CUI._addonScrollChild
    if not contentChild then return end

    local firstLoaded = nil
    local groupHeaders = CUI_NS.sidebarGroupButtons
    local infoByFolder = CUI_NS.navInfo

    local GROUP_H = CUI.SIDEBAR_GROUP_ROW_H
    local CHILD_H = CUI.SIDEBAR_CHILD_ROW_H
    local GROUP_GAP = CUI.SIDEBAR_GROUP_GAP
    -- Collapsed groups keep their header and hide their rows; the rows below close up.
    -- The gap between groups follows only a group that shows rows, so collapsed
    -- headers stack at the row pitch.
    local collapsed = CludesUIDB and CludesUIDB.sidebarCollapsed
    local rowY = 0
    local afterRows = false
    for _, navGroup in ipairs(CUI_NS.navGroups) do
        if afterRows then rowY = rowY + GROUP_GAP end
        afterRows = false
        local shut = collapsed and collapsed[navGroup.key] and true or false
        local header = groupHeaders[navGroup.key]
        if header then
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", contentChild, "TOPLEFT", 0, -rowY)
            header:Show()
            local toggleBtn = header._toggle
            if toggleBtn then
                toggleBtn:SetAtlas(
                    shut and "ui-questtrackerbutton-secondary-expand"
                        or "ui-questtrackerbutton-secondary-collapse"
                )
                toggleBtn:SetDesaturated(true)
            end
            rowY = rowY + GROUP_H
        end
        for _, moduleKey in ipairs(navGroup.members) do
            local navInfo = infoByFolder[moduleKey]
            local button = navInfo and sidebarButtons[moduleKey]
            if button then
                button:ClearAllPoints()
                if shut then
                    button:Hide()
                else
                    button:SetPoint("TOPLEFT", contentChild, "TOPLEFT", 0, -rowY)
                    button:Show()
                    rowY = rowY + CHILD_H
                    afterRows = true
                end

                local loaded = navInfo.alwaysLoaded or IsAddonLoaded(navInfo.folder)
                local isSpecial = navInfo.comingSoon or navInfo.maintenance
                -- Coming-soon / maintenance rows render as disabled regardless
                -- of whether their placeholder folder happens to be loaded.
                local effectiveLoaded = loaded and not isSpecial
                button._loaded = effectiveLoaded
                button._notEnabled = (not loaded) and not isSpecial
                button._dlIcon:Hide()

                -- Refresh sync icon state
                if button._syncBtn and button._syncBtn._refreshAlpha then button._syncBtn._refreshAlpha() end

                if effectiveLoaded and moduleKey == currentModule then
                    button._label:SetTextColor(
                        NAV_SELECTED_TEXT.r,
                        NAV_SELECTED_TEXT.g,
                        NAV_SELECTED_TEXT.b,
                        NAV_SELECTED_TEXT.a
                    )
                    if button._pwrBtn then button._pwrBtn._tex:SetAlpha(1) end
                elseif effectiveLoaded then
                    button._label:SetTextColor(
                        NAV_ENABLED_TEXT.r,
                        NAV_ENABLED_TEXT.g,
                        NAV_ENABLED_TEXT.b,
                        NAV_ENABLED_TEXT.a
                    )
                    if button._pwrBtn then button._pwrBtn._tex:SetAlpha(1) end
                    if not firstLoaded then firstLoaded = moduleKey end
                else
                    button._label:SetTextColor(
                        NAV_DISABLED_TEXT.r,
                        NAV_DISABLED_TEXT.g,
                        NAV_DISABLED_TEXT.b,
                        NAV_DISABLED_TEXT.a
                    )
                    if button._pwrBtn then button._pwrBtn._tex:SetAlpha(0.5) end
                    button._indicator:Hide()
                    button._glow:Hide()
                    button._glowTop:Hide()
                    button._glowBot:Hide()
                end
            end
        end
    end

    if contentChild.SetHeight then contentChild:SetHeight(math.max(CHILD_H, rowY)) end

    -- Default to Global Settings if no module is active
    if not currentModule then
        currentModule = nil
        if moduleList["_CUIGlobal"] then
            CUI:SelectModule("_CUIGlobal")
        elseif firstLoaded and moduleList[firstLoaded] then
            CUI:SelectModule(firstLoaded)
        end
    end

    -- (Sidebar search no longer filters the addon rows -- the global search
    -- results popup replaced that behavior -- so there is no filter state to
    -- re-apply across refreshes anymore.)

    -- Re-assert override-session locks LAST: the recolor loop above paints by loaded
    -- state and would otherwise wash out locked rows on every module/page switch.
    if CUI.RefreshSidebarOverrideLocks then CUI.RefreshSidebarOverrideLocks() end
end

-- Collapse or expand a sidebar group (header click). The state is account-wide,
-- in CludesUIDB.sidebarCollapsed keyed by group key (true = collapsed).
function CUI_NS.ToggleSidebarGroup(entryKey)
    if not CludesUIDB then return end
    local c = CludesUIDB.sidebarCollapsed
    if not c then
        c = {}
        CludesUIDB.sidebarCollapsed = c
    end
    c[entryKey] = (not c[entryKey]) or nil
    SyncNavStates()
end

-- Selecting a module whose group is collapsed expands that group, so the
-- selected row shows (Global Search, link tabs and slash commands select
-- modules the player cannot see).
function CUI_NS.RevealSidebarRow(moduleKey)
    local c = CludesUIDB and CludesUIDB.sidebarCollapsed
    if not (c and next(c)) then return end
    for _, navGroup in ipairs(CUI_NS.navGroups) do
        if c[navGroup.key] then
            for _, member in ipairs(navGroup.members) do
                if member == moduleKey then
                    c[navGroup.key] = nil
                    SyncNavStates()
                    return
                end
            end
        end
    end
end

-----------------------------------------------------------------------
--  Sidebar Unlock Mode tip  (one-time, shown on first panel open)
-----------------------------------------------------------------------
local _sidebarUnlockTip
local function ShowNavUnlockTip()
    if CludesUIDB and CludesUIDB.sidebarUnlockTipSeen then return end
    if _sidebarUnlockTip and _sidebarUnlockTip:IsShown() then return end
    local anchor = CUI._unlockSidebarBtn
    if not anchor then return end

    if not _sidebarUnlockTip then
        local tip = CUI.BuildTipCallout(CUI._panelBody, {
            width = 320,
            height = 100,
            text = CUI.L("Layout Mode is where you can adjust\npositioning for all the elements of CludesUI"),
            onOkay = function()
                if CludesUIDB then CludesUIDB.sidebarUnlockTipSeen = true end
            end,
        })
        -- Center horizontally on the Unlock Mode label text
        local captionText = anchor._label
        if captionText then
            tip:SetPoint("TOP", captionText, "BOTTOM", 0, -12)
        else
            tip:SetPoint("TOP", anchor, "BOTTOM", 60, -12)
        end
        _sidebarUnlockTip = tip
    end

    CUI.ShowTipCallout(_sidebarUnlockTip)
end

-- FIRST-OPEN SPLIT: the session's first open pays two heavy bills --
-- EnsureLoaded (LoadAddOn parsing the whole LoD options addon + every deferred
-- init) and the full panel build -- and the per-execution watchdog meters them
-- TOGETHER when both run in one hardware-event handler (field: "script ran too
-- long" aborting mid-sidebar on the very first open). Split them: the
-- triggering execution only LOADS; afterFn (the caller re-invoking itself)
-- runs next frame with its own fresh budget. Later opens (already loaded) stay
-- fully synchronous -- returns false and the caller proceeds as before.
-- EnsureLoaded itself stays synchronous: direct callers (DataBars' block
-- settings path) use the deferred inits' results in the same execution. A
-- failed load (options addon disabled) also returns false so the caller runs
-- the exact legacy failure path; _openPending swallows re-clicks during the
-- one-frame gap so a Toggle can't double-fire.
function CUI:_SplitFirstOpen(afterFn)
    if self._deferredLoaded then return false end
    self:EnsureLoaded()
    if not self._deferredLoaded then return false end
    self._openPending = true
    C_Timer.After(0, function()
        CUI._openPending = nil
        afterFn()
    end)
    return true
end

-- The panel never opens in combat (it closes as combat starts). Callers check
-- before they ask, but an open can still land after combat began: the
-- first-open split and the Settings button run it a frame later, and a deep
-- link (NavigateToElementSettings) can come from a click on a game frame.
-- Pages built then would call widget methods that are blocked in combat.
function CUI:Show()
    if self._openPending then return end
    if InCombatLockdown() then
        CUI.PrintError("Cannot open options during combat.")
        return
    end
    if self:_SplitFirstOpen(function() CUI:Show() end) then return end
    BuildMainFrame()
    SyncNavStates()
    panelFrame:Show()
    -- An open request while folded to the mini window unfolds it.
    if self._panelCollapsed then self._SetPanelCollapsed(false) end
    ShowNavUnlockTip()
end
function CUI:Hide()
    if panelFrame then panelFrame:Hide() end
end
function CUI:Toggle()
    if self._openPending then return end
    -- Closing still works in combat; opening or unfolding the mini window does
    -- not (see Show).
    if InCombatLockdown() and not (panelFrame and panelFrame:IsShown() and not self._panelCollapsed) then
        CUI.PrintError("Cannot open options during combat.")
        return
    end
    if self:_SplitFirstOpen(function() CUI:Toggle() end) then return end
    BuildMainFrame()
    if self._panelCollapsed then
        -- Folded to the mini window: the toggle asks for the options back.
        self._SetPanelCollapsed(false)
    elseif panelFrame:IsShown() then
        panelFrame:Hide()
    else
        SyncNavStates()
        panelFrame:Show()
        ShowNavUnlockTip()
        -- Refresh widget disabled states (e.g. width-match may have
        -- changed in unlock mode since the page was last shown).
        if self.RefreshPage then self:RefreshPage() end
    end
end
function CUI:IsShown() return panelFrame and panelFrame:IsShown() end
-- The main settings window frame. Used e.g. to scope popup click-catchers to the
-- panel instead of UIParent, so an open popup doesn't block world mouse/mouselook.
function CUI:GetMainFrame() return panelFrame end
function CUI:GetActivePage() return activePage end

--- Apply a user-defined panel scale on top of the pixel-perfect base scale.
--- @param userScale number  multiplier (1.0 = default, PANEL_SCALE_MIN-MAX)
--- @param pin table|string|nil  what stays put on screen while the panel glides to
---   the new scale: a region of the panel (the header's Window Scale slider passes
---   its track, so it never slides out from under the cursor), "cursor" (Shift +
---   mouse wheel zooms about the point under the mouse), or nil for the panel's
---   own centre.
do
    local scaleAnimFrame = CreateFrame("Frame")
    local scaleFrom, scaleTo, scaleElapsed
    local SCALE_DUR = 0.12
    local isAnimating = false
    -- Zoom origin: the pin's screen point (effective-scale-1 units) and its offset
    -- from panelFrame's bottom-left in panel units. pinX nil = no pin.
    local pinX, pinY, pinOX, pinOY
    local settleRoots = setmetatable({}, { __mode = "k" }) -- weak: a scratch set

    -- Re-anchor the panel so the pin's point lands back on its screen spot at the
    -- current scale (anchor offsets are in the panel's own units). The final call
    -- measures the same spot from the screen centre, so a centred panel stays
    -- centred through later resolution changes.
    local function HoldPin(final)
        if not pinX then return end
        local scale = panelFrame:GetEffectiveScale()
        local x, rowY = pinX / scale - pinOX, pinY / scale - pinOY
        panelFrame:ClearAllPoints()
        if final then
            local k = UIParent:GetEffectiveScale() / scale
            panelFrame:SetPoint(
                "CENTER",
                UIParent,
                "CENTER",
                x + (panelFrame:GetWidth() - UIParent:GetWidth() * k) / 2,
                rowY + (panelFrame:GetHeight() - UIParent:GetHeight() * k) / 2
            )
        else
            panelFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, rowY)
        end
    end

    -- Once the glide lands, every border in the panel body (the visible page, its
    -- content header, the chrome and the body's popups, shown or hidden) and the
    -- popups (rescaled just before by their _onScaleChanged hook) re-snap to whole
    -- pixels in one registry pass. Hidden cached pages are skipped: the tab switch
    -- re-snaps a page whenever it is shown. The page and header are roots of their
    -- own (their borders sit deeper than the walk reaches from the body).
    local function ResnapAfterScale()
        wipe(settleRoots)
        settleRoots[CUI._panelBody] = true
        for _, record in pairs(_pageCache) do
            local w = record.wrapper
            if w then settleRoots[w] = "skip" end
        end
        if _activePageWrapper then settleRoots[_activePageWrapper] = true end
        if headStrip then settleRoots[headStrip] = true end
        -- Kept header roots of other pages re-snap at their own tab switch; the
        -- active one is a root of its own (its parts sit one level deeper).
        local Hdr = CUI_NS.hdr
        for _, rootFrame in pairs(Hdr.roots) do
            settleRoots[rootFrame] = (rootFrame == Hdr.active) or "skip"
        end
        local pops = CUI._popupFrames
        if pops then
            for i = 1, #pops do
                local rootFrame = pops[i].dimmer or pops[i].popup
                if rootFrame then settleRoots[rootFrame] = true end
            end
        end
        PP.ResnapBordersUnderRoots(settleRoots)
    end

    local function OnScaleUpdate(self, dt)
        scaleElapsed = scaleElapsed + dt
        local t = math.min(1, scaleElapsed / SCALE_DUR)
        local ease = t * (2 - t) -- ease-out quad
        local done = t >= 1
        panelFrame:SetScale(done and scaleTo or (scaleFrom + (scaleTo - scaleFrom) * ease))
        HoldPin(done)
        if done then
            self:SetScript("OnUpdate", nil)
            isAnimating = false
            pinX = nil
            if CUI._onScaleChanged then
                for _, fn in ipairs(CUI._onScaleChanged) do
                    fn()
                end
            end
            ResnapAfterScale()
        end
    end

    function CUI:SetPanelScale(userScale, pin)
        if not panelFrame then return end
        local physW = (GetPhysicalScreenSize())
        local baseScale = GetScreenWidth() / physW
        local targetScale = baseScale * (userScale or 1.0)
        if CludesUIDB then CludesUIDB.panelScale = userScale end
        -- Recalculate PanelPP mult for the new scale
        if CUI.PanelPP then CUI.PanelPP.UpdateMult() end
        -- The pin shares the panel's scale, so its centre and the panel's edges read
        -- in the same units (the cursor is converted into them).
        pinX = nil
        local cx, centerY
        if pin == "cursor" then
            local scale = panelFrame:GetEffectiveScale()
            local x, rowY = GetCursorPosition()
            cx, centerY = x / scale, rowY / scale
        else
            cx, centerY = (pin or panelFrame):GetCenter()
        end
        local ml, mb = panelFrame:GetLeft(), panelFrame:GetBottom()
        local isv = issecretvalue
        if cx and centerY and ml and mb and not (isv and (isv(cx) or isv(centerY) or isv(ml) or isv(mb))) then
            local scale = panelFrame:GetEffectiveScale()
            pinOX, pinOY = cx - ml, centerY - mb
            pinX, pinY = cx * scale, centerY * scale
        end
        -- Every change glides on from where the panel is now, so a new target
        -- mid-glide (a fast scroll) carries on smoothly instead of jumping.
        scaleFrom = panelFrame:GetScale()
        scaleTo = targetScale
        scaleElapsed = 0
        if not isAnimating then
            isAnimating = true
            scaleAnimFrame:SetScript("OnUpdate", OnScaleUpdate)
        end
    end

    --- One 5% step of the panel scale (delta > 0 grows), clamped to
    --- PANEL_SCALE_MIN-MAX and gliding about `pin` as SetPanelScale does. An off-step
    --- value (an older seed) steps to the next 5% mark. True when it changed.
    function CUI:StepPanelScale(stepDelta, pin)
        local cur = ((CludesUIDB and CludesUIDB.panelScale) or 1) * 100
        local v
        if stepDelta > 0 then
            v = math.floor(cur / 5 + 1e-6) * 5 + 5
        else
            v = math.ceil(cur / 5 - 1e-6) * 5 - 5
        end
        v = math.max(CUI.PANEL_SCALE_MIN * 100, math.min(CUI.PANEL_SCALE_MAX * 100, v))
        if math.abs(v - cur) < 0.01 then return false end
        self:SetPanelScale(v / 100, pin)
        return true
    end

    -- Shift + mouse wheel anywhere on the panel: one step about the cursor, then
    -- the header's Window Scale control lights up so the change can be traced
    -- (CludesUI._FlashWindowScale, set by that control once it is built). The
    -- panel's wheel handlers call this first; true = the wheel was used here.
    function CUI._ShiftWheelScale(stepDelta)
        if not IsShiftKeyDown() or CUI._sliderDragging then return false end
        if CUI:StepPanelScale(stepDelta, "cursor") and CUI._FlashWindowScale then CUI._FlashWindowScale() end
        return true
    end
end

-- Open the panel with a specific addon's tab selected
function CUI:ShowModule(moduleFolder)
    if InCombatLockdown() then
        CUI.PrintError("Cannot open options during combat.")
        return
    end
    if self._openPending then return end
    -- First-open split (see _SplitFirstOpen): the combat check above stays in
    -- the click execution; the deferred re-invoke re-checks it harmlessly.
    if self:_SplitFirstOpen(function() CUI:ShowModule(moduleFolder) end) then return end
    BuildMainFrame()
    SyncNavStates()
    panelFrame:Show()
    if self._panelCollapsed then self._SetPanelCollapsed(false) end
    ShowNavUnlockTip()
    if moduleList[moduleFolder] then self:SelectModule(moduleFolder) end
end

-------------------------------------------------------------------------------
--  Plugin API
--  Third-party addons add their own settings pages through RegisterPlugin. A
--  plugin always gets a NEW sidebar section of its own; it can never add a row
--  to one of the suite's sections, add a tab to a suite module, or replace a
--  suite page:
--   * plugin module keys live in the "plugin:<id>:<module>" namespace, which
--     RegisterModule refuses, so they never collide with a suite key;
--   * the section and its rows go to private lists that the sidebar renders
--     only above or below the suite's block of groups (CUI_NS.RebuildNavGroups);
--   * the registry keeps its own copy of every field it uses, so editing the
--     spec table after registration has no effect;
--   * every plugin callback runs through xpcall: a plugin error is reported
--     through the error handler and never breaks the panel.
--  Plugin pages take part in the global search like suite pages: widget rows
--  are indexed on live navigation and by the search's hidden pre-build pass
--  (a module can opt out of the latter with searchPrebuild = false).
--  Developer guide: PLUGINS_API.md.
-------------------------------------------------------------------------------
CUI.PLUGIN_API_VERSION = 5

do
    local PREFIX = CUI_NS.PLUGIN_PREFIX
    local MAX_MODULES = 20
    local MAX_PAGES = 20
    local MAX_ID_LEN = 40
    local MAX_LABEL_CHARS = 32
    local MAX_TITLE_CHARS = 48
    local MAX_DESC_CHARS = 300

    -- id -> { label, position, keys = { [moduleKey] = fullKey }, firstKey }
    local plugins = {}

    local ReportError = CUI_NS.ReportError

    local function Reject(pluginId, msg)
        ReportError(("CludesUI.RegisterPlugin(%s): %s"):format(tostring(pluginId), msg))
        return false
    end

    -- Caps s at maxChars UTF-8 characters.
    local function CapChars(text, maxChars)
        local n, cut = 0, nil
        for pos in text:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do
            n = n + 1
            if n > maxChars then
                cut = pos
                break
            end
        end
        if cut then text = text:sub(1, cut - 1):gsub("%s+$", "") end
        return text
    end

    -- Plain single-line text: drops every UI escape sequence (colors, textures,
    -- atlases, hyperlinks, line breaks) so a label cannot borrow suite styling.
    local function PlainText(text, maxChars)
        if type(text) ~= "string" then return nil end
        text = text:gsub("|[Tt].-|[Tt]", "")
            :gsub("|[Aa].-|[Aa]", "")
            :gsub("|[Kk].-|[Kk]", "")
            :gsub("|H.-|h(.-)|h", "%1")
            :gsub("|c%x%x%x%x%x%x%x%x", "")
            :gsub("|cn[^:]*:", "")
            :gsub("|r", "")
            :gsub("|n", " ")
            :gsub("|", "")
            :gsub("%c", " ")
            :gsub("%s+", " ")
            :gsub("^ ", "")
            :gsub(" $", "")
        if text == "" then return nil end
        return CapChars(text, maxChars)
    end

    -- Section labels a plugin may not use: the suite's own group labels (English
    -- and localized), the fixed panel entries, and the suite name itself.
    local function IsReservedLabel(navLabel)
        local lower = navLabel:lower()
        if lower:find("^cludes") or lower:find("^cui") then return true end
        local reserved = { "Global Settings", "Profiles", "Patch Notes", "CUI Legends" }
        for _, group in ipairs(CUI_NS.coreGroups) do
            reserved[#reserved + 1] = group.label
        end
        for _, r in ipairs(reserved) do
            if lower == r:lower() or lower == tostring(CUI.L(r)):lower() then return true end
        end
        return false
    end

    local function ValidId(text)
        return type(text) == "string" and #text <= MAX_ID_LEN and text:find("^%a[%w_%-]*$") ~= nil
    end

    local function Guard(fn)
        if fn == nil then return nil end
        return function(...)
            local ok, a = xpcall(fn, ReportError, ...)
            if ok then return a end
        end
    end

    -- Guarded header builders, cached so a page keeps one builder identity.
    local guardedHeaders = setmetatable({}, { __mode = "k" })
    local function GuardHeaderSource(getHeaderBuilder)
        if getHeaderBuilder == nil then return nil end
        local get = Guard(getHeaderBuilder)
        return function(pageTitle)
            local hb = get(pageTitle)
            if type(hb) ~= "function" then return nil end
            local g = guardedHeaders[hb]
            if not g then
                g = Guard(hb)
                guardedHeaders[hb] = g
            end
            return g
        end
    end

    local CALLBACKS = { "buildPage", "getHeaderBuilder", "onPageCacheRestore", "onReset", "onModuleLeave" }

    -- Validates one module spec and returns the registry's private config copy.
    local function BuildModuleConfig(pluginId, navLabel, m, index, seenKeys)
        if type(m) ~= "table" then return nil, ("modules[%d] must be a table"):format(index) end
        if not ValidId(m.key) then
            return nil,
                ("modules[%d].key must match ^%%a[%%w_%%-]*$ (max %d chars)"):format(index, MAX_ID_LEN)
        end
        if seenKeys[m.key] then return nil, ("duplicate module key %q"):format(m.key) end
        local title = PlainText(m.title, MAX_TITLE_CHARS)
        if not title then return nil, ("modules[%d].title must be a non-empty string"):format(index) end
        if m.description ~= nil and type(m.description) ~= "string" then
            return nil, ("modules[%d].description must be a string"):format(index)
        end
        if type(m.pages) ~= "table" or #m.pages == 0 or #m.pages > MAX_PAGES then
            return nil, ("modules[%d].pages must be a list of 1-%d page names"):format(index, MAX_PAGES)
        end
        local pages, seenPages = {}, {}
        for i, p in ipairs(m.pages) do
            -- Page names are handed back to buildPage verbatim, so they are
            -- validated rather than cleaned: plain text only.
            if type(p) ~= "string" or p == "" or p:find("[|%c]") or seenPages[p] then
                return nil, ("modules[%d].pages[%d] must be a unique plain-text string"):format(index, i)
            end
            seenPages[p] = true
            pages[i] = p
        end
        for _, cb in ipairs(CALLBACKS) do
            if m[cb] ~= nil and type(m[cb]) ~= "function" then
                return nil, ("modules[%d].%s must be a function"):format(index, cb)
            end
        end
        if type(m.buildPage) ~= "function" then
            return nil, ("modules[%d].buildPage is required"):format(index)
        end
        if m.searchPrebuild ~= nil and type(m.searchPrebuild) ~= "boolean" then
            return nil, ("modules[%d].searchPrebuild must be a boolean"):format(index)
        end
        seenKeys[m.key] = true
        return {
            title = title,
            description = m.description and CapChars(m.description, MAX_DESC_CHARS) or nil,
            pages = pages,
            buildPage = Guard(m.buildPage),
            getHeaderBuilder = GuardHeaderSource(m.getHeaderBuilder),
            onPageCacheRestore = Guard(m.onPageCacheRestore),
            onReset = Guard(m.onReset),
            onModuleLeave = Guard(m.onModuleLeave),
            _cuiCore = false,
            _plugin = pluginId,
            _pluginLabel = navLabel,
            _searchPrebuild = m.searchPrebuild ~= false,
        }
    end

    -- Builds the header and rows of a section registered after the panel exists.
    local function BuildLateSection(navGroup)
        local createHeader = CUI_NS.CreateSidebarGroupHeader
        local createRow = CUI_NS.CreateSidebarChildRow
        if not (createHeader and createRow) then return end
        CUI_NS.sidebarGroupButtons[navGroup.key] = createHeader(navGroup)
        for _, entryKey in ipairs(navGroup.members) do
            sidebarButtons[entryKey] = createRow(CUI_NS.navInfo[entryKey])
        end
        if CUI.RefreshSidebarOverrideLocks then CUI.RefreshSidebarOverrideLocks() end
        if panelFrame and panelFrame:IsShown() then SyncNavStates() end
    end

    -- Adds one validated module to a plugin's record and section.
    local function CommitModule(pluginId, record, entryKey, fullKey, moduleConfig)
        CUI_NS.navInfo[fullKey] = {
            folder = fullKey,
            display = moduleConfig.title,
            search_name = record.label .. " " .. moduleConfig.title,
            alwaysLoaded = true,
            plugin = pluginId,
        }
        local members = record.group.members
        members[#members + 1] = fullKey
        record.keys[entryKey] = fullKey
        record.firstKey = record.firstKey or fullKey
        CUI_NS.StoreModule(fullKey, moduleConfig)
    end

    --- Registers a plugin and its sidebar section.
    --- @param id string   unique plugin id (letters, digits, "_" and "-")
    --- @param spec table  { label, position = "bottom"|"top", modules = { ... } }
    --- @return boolean    true when the plugin was registered
    function CUI.RegisterPlugin(pluginId, pluginSpec)
        if not ValidId(pluginId) then
            return Reject(pluginId, ("id must match ^%%a[%%w_%%-]*$ (max %d chars)"):format(MAX_ID_LEN))
        end
        if plugins[pluginId] then return Reject(pluginId, "a plugin with this id is already registered") end
        if type(pluginSpec) ~= "table" then return Reject(pluginId, "spec must be a table") end

        local navLabel = PlainText(pluginSpec.label, MAX_LABEL_CHARS)
        if not navLabel then return Reject(pluginId, "label must be a non-empty string") end
        if IsReservedLabel(navLabel) then
            return Reject(pluginId, ("label %q is reserved"):format(navLabel))
        end

        local position = pluginSpec.position
        if position == nil then position = "bottom" end
        if position ~= "bottom" and position ~= "top" then
            return Reject(pluginId, 'position must be "bottom" or "top"')
        end

        if
            type(pluginSpec.modules) ~= "table"
            or #pluginSpec.modules == 0
            or #pluginSpec.modules > MAX_MODULES
        then
            return Reject(pluginId, ("modules must be a list of 1-%d module specs"):format(MAX_MODULES))
        end

        -- Validate everything before touching any shared state.
        local configs, seenKeys = {}, {}
        for i, m in ipairs(pluginSpec.modules) do
            local moduleConfig, err = BuildModuleConfig(pluginId, navLabel, m, i, seenKeys)
            if not moduleConfig then return Reject(pluginId, err) end
            local fullKey = PREFIX .. pluginId .. ":" .. m.key
            if CUI_NS.IsModuleKeyTaken(fullKey) then
                return Reject(pluginId, ("module key %q is already registered"):format(fullKey))
            end
            configs[i] = { key = m.key, fullKey = fullKey, config = moduleConfig }
        end

        local navGroup = { key = PREFIX .. pluginId, label = navLabel, members = {}, plugin = pluginId }
        local record = { label = navLabel, position = position, keys = {}, group = navGroup }
        for _, c in ipairs(configs) do
            CommitModule(pluginId, record, c.key, c.fullKey, c.config)
        end
        plugins[pluginId] = record

        local entryList = (position == "top") and CUI_NS.pluginGroupsTop or CUI_NS.pluginGroupsBottom
        entryList[#entryList + 1] = navGroup
        CUI_NS.RebuildNavGroups()
        BuildLateSection(navGroup)
        return true
    end

    function CUI.IsPluginRegistered(pluginId) return plugins[pluginId] ~= nil end

    --- True while the global search's hidden pre-build pass is running a page
    --- builder. The builder then gets a stub widget factory; skip side effects
    --- (event registration, hooks, previews) while this is true.
    function CUI.IsSearchPrebuild() return CUI._prebuilding == true end

    --- Full module key of a plugin module ("plugin:<id>:<moduleKey>"), for the
    --- panel calls that take one (GetActiveModule comparisons,
    --- InvalidateModulePageCache). Nil when not registered.
    function CUI.GetPluginModuleKey(pluginId, moduleKey)
        local record = plugins[pluginId]
        return record and record.keys[moduleKey] or nil
    end

    --- Opens the panel on a plugin module (its first module when moduleKey is
    --- nil), optionally on a given page. Returns false when nothing matches.
    function CUI.OpenPlugin(pluginId, moduleKey, pageTitle)
        local record = plugins[pluginId]
        if not record then return false end
        local entryKey = (moduleKey == nil) and record.firstKey or record.keys[moduleKey]
        local moduleConfig = entryKey and moduleList[entryKey]
        if not moduleConfig then return false end
        if InCombatLockdown() then
            CUI.PrintError("Cannot open options during combat.")
            return false
        end
        if pageTitle ~= nil then
            local valid = false
            for _, p in ipairs(moduleConfig.pages) do
                if p == pageTitle then
                    valid = true
                    break
                end
            end
            if not valid then return false end
            -- SelectModule opens the module on its last page.
            _lastPagePerModule[entryKey] = pageTitle
        end
        CUI:ShowModule(entryKey)
        -- Already on this module: SelectModule was a no-op, switch the page here.
        if
            pageTitle
            and currentModule == entryKey
            and activePage ~= pageTitle
            and panelFrame
            and panelFrame:IsShown()
        then
            CUI:SelectPage(pageTitle)
        end
        return true
    end

    ---------------------------------------------------------------------------
    --  Pages from addons written before this API
    --  Such an addon registered a page under a key of its own (RegisterModule
    --  from its own code, a loadstring chunk included, or a write into
    --  CludesUI._modules) and listed it in a group of its own in the public
    --  CludesUI.ADDON_GROUPS. Both still work as they did: the page keeps its
    --  key (Spec Overrides, profile sync and search treat it as before), and the
    --  addon's group shows above or below the suite's block, wherever the addon
    --  inserted it. A row placed inside one of the suite's groups moves to a
    --  section of its own, as does a page with no row (named after its addon).
    --  Anything aimed at a suite page is ignored (a replaced or hooked
    --  RegisterModule is put back before the suite registers, CludesUI.lua),
    --  no suite config is ever handed out, and the addon is named once in a
    --  notice when the panel opens.
    ---------------------------------------------------------------------------
    -- owner: outside key -> the addon that registered it (false: unknown).
    -- sections: source -> its section, a group table in the plugin lists.
    local owner, placed, sections, offenders = {}, {}, {}, {}
    local suiteGroup = {}
    for _, group in ipairs(CUI_NS.coreGroups) do
        suiteGroup[group.key] = true
    end

    -- An addon whose change to a suite page was ignored (named in the notice).
    local function Offend(moduleKey) offenders[moduleKey] = true end
    CUI_NS.RecordLegacyOffender = Offend -- the RegisterModule reclaim (CludesUI.lua)

    -- An addon's TOC title as plain text (nil if it has none).
    local function AddonTitle(moduleKey)
        local ok, title = pcall(C_AddOns.GetAddOnMetadata, moduleKey, "Title")
        return ok and PlainText(title, MAX_LABEL_CHARS) or nil
    end

    -- The outside addon that last wrote t[key] (nil for the suite's own writes
    -- and for anything that is not an installed addon). Taint names the writer
    -- even where the stack cannot: a wrapper's tail call, a path-less chunk,
    -- a chunk named after one of our files.
    local function WriterOf(t, entryKey)
        local _, by = issecurevariable(t, entryKey)
        if type(by) == "string" and not CUI_NS.IsSuiteFolder(by) and AddonTitle(by) then return by end
    end
    CUI_NS.WriterOf = WriterOf -- the RegisterModule reclaim (CludesUI.lua)

    -- The outside addon that built a table, from its fields' writers.
    local function Author(t)
        for key in pairs(t) do
            if type(key) == "string" then
                local by = WriterOf(t, key)
                if by then return by end
            end
        end
    end

    -- The roster entry an addon published for one of its keys, if any.
    local function PublicInfo(entryKey)
        local navInfo = CUI._addonInfoByFolder and CUI._addonInfoByFolder[entryKey]
        if type(navInfo) == "table" then return navInfo end
        for _, entry in ipairs(ADDON_ROSTER) do
            if type(entry) == "table" and entry.folder == entryKey then return entry end
        end
    end

    local function Section(source, navLabel, top)
        local s = sections[source]
        if not s then
            navLabel = navLabel or "Other Addons"
            if IsReservedLabel(navLabel) then navLabel = CapChars("Plugin: " .. navLabel, MAX_LABEL_CHARS) end
            s = { key = "ext:" .. source, label = navLabel, members = {} }
            sections[source] = s
            local entryList = top and CUI_NS.pluginGroupsTop or CUI_NS.pluginGroupsBottom
            entryList[#entryList + 1] = s
        end
        return s
    end

    -- Gives an outside key its row in section s, labelled from the roster entry
    -- its addon published, else from its page. Returns true for a new row.
    local function Place(entryKey, s)
        if placed[entryKey] or #s.members >= MAX_MODULES then return false end
        local pub = PublicInfo(entryKey)
        local page = moduleList[entryKey]
        local display = (pub and PlainText(pub.display, MAX_LABEL_CHARS))
            or (page and PlainText(page.title, MAX_LABEL_CHARS))
            or PlainText(entryKey, MAX_LABEL_CHARS)
            or "?"
        CUI_NS.navInfo[entryKey] = {
            folder = entryKey,
            display = display,
            search_name = (pub and PlainText(pub.search_name, MAX_DESC_CHARS)) or display,
            alwaysLoaded = pub == nil or pub.alwaysLoaded == true,
            comingSoon = pub and pub.comingSoon == true or nil,
            maintenance = pub and pub.maintenance == true or nil,
        }
        s.members[#s.members + 1] = entryKey
        placed[entryKey] = true
        return true
    end

    -- Places every outside page and every row an addon listed in a group of its
    -- own. Runs as the panel is built, whenever it opens and on a late
    -- registration; once everything has its row it only reads.
    function CUI_NS.SyncExternal()
        local added
        local afterSuite = false
        for _, group in ipairs(CUI.ADDON_GROUPS or {}) do
            if type(group) == "table" and suiteGroup[group.key] then
                afterSuite = true
            elseif type(group) == "table" and type(group.members) == "table" then
                for _, m in ipairs(group.members) do
                    if
                        type(m) == "string"
                        and not placed[m]
                        and not CUI_NS.IsSuiteKey(m)
                        and not CUI_NS.IsPluginKey(m)
                    then
                        local s = Section(
                            "group:" .. tostring(group.key),
                            PlainText(group.label, MAX_LABEL_CHARS),
                            not afterSuite
                        )
                        if Place(m, s) then
                            added = added or {}
                            added[s] = true
                        end
                    end
                end
            end
        end
        for entryKey, moduleKey in pairs(owner) do
            if not placed[entryKey] then
                local s = Section(
                    "addon:" .. (moduleKey or "?"),
                    moduleKey and (AddonTitle(moduleKey) or PlainText(moduleKey, MAX_LABEL_CHARS)) or nil,
                    false
                )
                if Place(entryKey, s) then
                    added = added or {}
                    added[s] = true
                end
            end
        end
        if not added then return end
        CUI_NS.RebuildNavGroups()
        if not panelFrame then return end
        for s in pairs(added) do
            if CUI_NS.sidebarGroupButtons[s.key] then
                -- Its section is already on the sidebar: add the new rows.
                for _, entryKey in ipairs(s.members) do
                    if not sidebarButtons[entryKey] and CUI_NS.CreateSidebarChildRow then
                        sidebarButtons[entryKey] = CUI_NS.CreateSidebarChildRow(CUI_NS.navInfo[entryKey])
                    end
                end
            else
                BuildLateSection(s)
            end
        end
        if CUI.RefreshSidebarOverrideLocks then CUI.RefreshSidebarOverrideLocks() end
        if panelFrame:IsShown() then SyncNavStates() end
    end

    -- A page another addon registers under a key of its own (folder: that
    -- addon as the stack names it). It may register again.
    function CUI_NS.RegisterExternal(moduleKey, entryKey, moduleConfig)
        if type(entryKey) ~= "string" or type(moduleConfig) ~= "table" then return end
        -- No folder on the stack, or one of ours: the page's builder names it.
        if not moduleKey or CUI_NS.IsSuiteFolder(moduleKey) then moduleKey = Author(moduleConfig) end
        if CUI_NS.IsSuiteKey(entryKey) then
            if moduleKey then Offend(moduleKey) end
            return
        end
        if CUI_NS.IsPluginKey(entryKey) then return end
        moduleConfig._cuiCore = false
        CUI_NS.StoreModule(entryKey, moduleConfig, true)
        if owner[entryKey] == nil then owner[entryKey] = moduleKey or false end
        if panelFrame then CUI_NS.SyncExternal() end
    end

    -- The old public registry, kept as an inbox: writes register the page,
    -- reads only ever return an outside addon's own pages.
    CUI._modules = setmetatable({}, {
        __index = function(_, entryKey)
            if owner[entryKey] ~= nil then return moduleList[entryKey] end
        end,
        __newindex = function(_, entryKey, page)
            CUI_NS.RegisterExternal((debugstack(2, 1, 0) or ""):match("AddOns/([^/]+)/"), entryKey, page)
        end,
        __metatable = false,
    })

    -- Whenever the panel opens: places what the outside addons added since.
    CUI:RegisterOnShow(function() CUI_NS.SyncExternal() end)
end
