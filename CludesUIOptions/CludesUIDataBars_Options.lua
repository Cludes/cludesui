if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIDataBars_Options.lua
--  The "DataBars" options page for the multi-bar engine.
--
--  Layout:
--    * Content header: bar selector dropdown (rename/delete inline), "+ New
--      Bar" template card strip, and an interactive preview of the selected
--      bar. Preview segments click-navigate to their block's section.
--    * Body: Bar Settings (topped by the Auto Sized / Even Split mode
--      toggle), then one section per block (in bar order); adding blocks =
--      the preview strip's "+" tile. Zero bars renders a template-card
--      empty state instead.
--
--  Everything here talks to the runtime exclusively through the ns.* API
--  listed at the top of CludesUIDataBars.lua.
-------------------------------------------------------------------------------

local ADDON_NAME = "CludesUIDataBars"
local mod = CludesUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page

local PAGE_DATABARS = "Info Bar"

CludesUI.AtOptionsLogin(function()
    local Pix = CludesUI.PP
    local L = CludesUI.L
    local Lf = CludesUI.Lf
    local format = string.format
    local floor = math.floor
    -- Page reuse (CludesUI_FramePool.lua): a frame made under a page pool
    -- host comes from the pool and is dressed again by every later build; under
    -- any other parent it is a plain new frame.
    local Pool = CludesUI._Pool
    local CreateFrame = Pool.CreateFrame

    -- A colour swatch that only means something while another setting is on
    -- gets a cover over it, `level` above, that takes the mouse and names
    -- that setting in its tooltip.
    local function SwatchCover(swatch, gateName, level)
        local cover = CreateFrame("Frame", nil, swatch)
        cover:SetAllPoints()
        cover:SetFrameLevel(swatch:GetFrameLevel() + level)
        cover:EnableMouse(true)
        cover:SetScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(swatch, CludesUI.DisabledTooltip(gateName))
        end)
        cover:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        return cover
    end

    -- The shell of the header's kept menus (bar, add block, segment): a
    -- hidden, screen-clamped panel over the options window, in the
    -- dropdown's background and border.
    local function MenuShell(width)
        local DDS = CludesUI.DD_STYLE
        local menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(300)
        menu:SetClampedToScreen(true)
        if width then
            menu:SetWidth(width)
        end
        menu:Hide()
        local backdrop = menu:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(DDS.BG_R, DDS.BG_G, DDS.BG_B, DDS.BG_HA)
        CludesUI.MakeRoundedBorder(menu, 1, 1, 1, DDS.BRD_A, backdrop, nil, true)
        return menu
    end

    -- A menu opened from a button (menu._anchor) closes on a left click
    -- outside both: each open runs menu._closeOutside as its OnUpdate, and
    -- hiding clears it.
    local function CloseOnOutsideClick(menu)
        menu._closeOutside = function(m)
            if not m:IsMouseOver() and not m._anchor:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                m:Hide()
            end
        end
        menu:HookScript("OnHide", function(m)
            m:SetScript("OnUpdate", nil)
        end)
    end

    -- The live form: dimmed and covered while isOn() is false, at liveAlpha()
    -- (default full) while it is true, re-read on every widget refresh.
    local function GatedSwatch(swatch, updateSwatch, gateName, level, isOn, liveAlpha)
        local cover = SwatchCover(swatch, gateName, level)
        local function Paint()
            if isOn() then
                swatch:SetAlpha(liveAlpha and liveAlpha() or 1)
                cover:Hide()
            else
                swatch:SetAlpha(0.3)
                cover:Show()
            end
        end
        CludesUI.RegisterWidgetRefresh(function()
            updateSwatch()
            Paint()
        end)
        Paint()
    end

    ---------------------------------------------------------------------------
    --  Module upvalues (survive page rebuilds; closures re-target each build)
    ---------------------------------------------------------------------------
    local _edbHeaderBuilder -- content-header closure (getHeaderBuilder returns it)
    local _edbNavigateFn -- set per page build: click-to-scroll handler
    local _edbSegHighlightFn -- set per header build: preview segment wash
    local _edbSegHoverId -- block id whose SEGMENT hover owns the live
    -- bar highlight (the watcher must not clear it)
    local _edbStripRelayout -- set per header build: re-solves + repositions the preview
    local _edbStripBarId -- set per header build: the bar that preview shows
    local _edbPreviewHost -- the preview strip frame (live theme feedback)
    local _edbHeldGlowKey -- click-target key whose glow pulses until the
    -- setting is filled in; outlives page builds
    local _edbHeldGlowY -- its section offset when last shown: sections
    -- follow bar order, so a change means the row
    -- moved and the view has to follow it
    -- Location blocks whose Width was just switched to Manual, keyed by the
    -- block cfg table. Marks a choice the player made SECONDS ago, not a
    -- setting -- so it is transient by design and never saved. Set on the
    -- switch, cleared by the first Max Width drag and by switching back to
    -- Automatic. Keying the pulse off "maxWidth == nil" instead would fire
    -- once per block ever, and never again on a later mode change.
    -- Weak keys: a deleted block must not be held alive by this marker.
    local _edbWidthPulse = setmetatable({}, { __mode = "k" })
    -- The header's menus (bar selector, segment, add block): each built on its
    -- first open and kept across header builds.
    local _edbMenus = {}
    -- Owner of the header's kept frames (Pool.Kept): the vertical preview's
    -- strip and add tile in the docked popout, and the drag ghost.
    local _edbKeep = {}
    local _cardsExpanded = false -- template card strip open/closed

    ---------------------------------------------------------------------------
    --  Block-type registry views
    ---------------------------------------------------------------------------
    local TYPE_LABEL = {}
    for _, t in ipairs(mod.BLOCK_TYPES) do
        TYPE_LABEL[t.key] = t.label
    end

    -- A saved block whose type registers no factory on this client (crests,
    -- spec, great vault on WoW Forever; supplies on Midnight) builds no slot
    -- there. The live bar
    -- measures it at zero, so it collapses out of the solve, except in a role:
    -- as the bar's Fill Remaining block it still takes the leftover span, and
    -- as its Force Centered block it still splits the bar at the center (the
    -- toggles on any shown block move either role). The page mirrors the live
    -- bar: no preview segment and no settings section. The entry stays in the
    -- bar's saved list untouched, so the profile still carries it back to
    -- the other client.
    local function BlockHidden(b)
        return not mod.BlockFactories[b.type]
    end

    -- Typical content extents (real-bar px) for auto-fit blocks that have no
    -- live instance yet; the preview scales these into strip space.
    local EST_LEN = {
        clock = 150,
        fps = 70,
        ms = 70,
        gold = 150,
        xprep = 140,
        spec = 130,
        profession = 120,
        travel = 40,
        micromenu = 340,
        currency = 90,
        spacer = 40,
        durability = 70,
        combat = 105,
        profession2 = 120,
        greatvault = 100,
        location = 140,
        coords = 70,
        crests = 160,
        ilvl = 70,
        supplies = 70,
        bags = 50,
        mplussummary = 150,
        timeplayed = 60,
    }

    ---------------------------------------------------------------------------
    --  Profile helpers
    ---------------------------------------------------------------------------
    local function Profile()
        return mod.GetProfile()
    end

    -- Selected bar, validated (falls back to the first bar).
    local function SelectedBar()
        local p = Profile()
        if not p then
            return nil
        end
        local barList = p.bars
        if #barList == 0 then
            return nil
        end
        if p.selectedBarId then
            local b = mod.GetBar(p.selectedBarId)
            if b then
                return b
            end
        end
        p.selectedBarId = barList[1].id
        return barList[1]
    end

    local function ResolvedBarLength(conf)
        if conf.lengthMode == "full" then
            if conf.orientation == "V" then
                return UIParent:GetHeight()
            end
            return UIParent:GetWidth()
        end
        if conf.length then
            return conf.length
        end
        return 400
    end

    -- Structural change: rebuild the content header AND the page body. The
    -- page build sets the header itself (zero bars = NO content header at
    -- all: the page falls back to the full-body starting screen, template
    -- cards, same as first open), so one forced refresh builds both.
    local function HardRefresh()
        CludesUI:RefreshPage(true)
    end

    -- Header-only change (template card strip open/close): the header is
    -- built again in place (under page reuse, on its kept root).
    local function HeaderOnly()
        if SelectedBar() then
            CludesUI:SetContentHeader(_edbHeaderBuilder)
        else
            CludesUI:ClearContentHeader()
        end
    end

    -- Live theme feedback for the preview strip (swatch drag / dim slider).
    local function RefreshPreviewTheme()
        local conf = SelectedBar()
        if _edbPreviewHost and _edbPreviewHost:IsShown() and conf then
            mod.MakePreviewBackdrop(_edbPreviewHost, conf.theme, not conf.hideBorder)
        end
    end

    ---------------------------------------------------------------------------
    --  Shared popup flows (header menu + body buttons)
    ---------------------------------------------------------------------------
    local function PromptRenameBar(conf)
        local oldName = conf.name
        if oldName == nil then
            oldName = ""
        end
        CludesUI:ShowInputPopup({
            title = "Rename DataBar",
            message = Lf('Enter a new name for "%1$s":', oldName),
            placeholder = oldName,
            confirmText = "Rename",
            cancelText = "Cancel",
            onConfirm = function(newName)
                if newName then
                    newName = strtrim(newName)
                else
                    newName = ""
                end
                if newName == "" or newName == oldName then
                    return
                end
                mod.RenameBar(conf.id, newName)
                CludesUI:InvalidateModulePageCache("CludesUIDataBars")
                HardRefresh()
            end,
        })
    end

    local function PromptDeleteBar(conf)
        local delName = conf.name
        if delName == nil then
            delName = ""
        end
        CludesUI:ShowConfirmPopup({
            title = "Delete DataBar",
            message = Lf('Are you sure you want to delete "%1$s"?', delName),
            confirmText = "Delete",
            cancelText = "Cancel",
            onConfirm = function()
                mod.DeleteBar(conf.id)
                local p = Profile()
                local barList = mod.BarsInOrder()
                if p and barList[1] then
                    p.selectedBarId = barList[1].id
                end
                CludesUI:InvalidateModulePageCache("CludesUIDataBars")
                HardRefresh()
                -- The rebuilt page (possibly the zero-bar empty state) can
                -- be shorter than the old scroll offset, which leaves the
                -- viewport past the content = blank page. Always return to
                -- the top after a delete.
                if CludesUI.SmoothScrollTo then
                    CludesUI.SmoothScrollTo(0)
                end
            end,
        })
    end

    local function CreateBarFromTemplate(key)
        mod.CreateBar(key)
        _cardsExpanded = false
        HardRefresh()
    end

    ---------------------------------------------------------------------------
    --  Template cards (header strip + zero-bars empty state)
    ---------------------------------------------------------------------------
    local TEMPLATE_CARDS = {
        {
            key = "empty",
            icon = "cui-edit.png",
            title = "Start Empty",
            desc = "A blank bar to build from scratch.",
        },
        {
            key = "bottom",
            icon = "grid.png",
            title = "Top/Bottom Info Bar",
            desc = "Full-width bar with the classic info blocks.",
        },
        {
            key = "minimapc",
            icon = "coordinates.png",
            title = "Minimap Companion",
            desc = "Compact clock and FPS readout.",
        },
        {
            key = "microstrip",
            icon = "cogs.png",
            title = "Micro Menu Strip",
            desc = "Just the micro menu buttons.",
        },
    }
    local MEDIA_ICONS = "Interface\\AddOns\\CludesUI\\media\\icons\\"

    local function MakeTemplateCard(host, posX, posY, wid, cardH, def)
        local EGc = CludesUI.CLUDES_GREEN
        local cardFrame = CreateFrame("Button", nil, host)
        Pix.Size(cardFrame, wid, cardH)
        Pix.Point(cardFrame, "TOPLEFT", host, "TOPLEFT", posX, posY)
        cardFrame:SetFrameLevel(host:GetFrameLevel() + 2)

        local cbrd = CludesUI.MakeRoundedCard(cardFrame, 0.12, 0.50, 2)
        local cbg, accentLine = cbrd.bg, cbrd.accent

        accentLine:SetColorTexture(EGc.r, EGc.g, EGc.b, 0.6)

        local cIcon = cardFrame:CreateTexture(nil, "ARTWORK")
        cIcon:SetSize(24, 24)
        Pix.Point(cIcon, "LEFT", cardFrame, "LEFT", 14, 0)
        cIcon:SetTexture(MEDIA_ICONS .. def.icon)
        cIcon:SetVertexColor(EGc.r, EGc.g, EGc.b)
        cIcon:SetAlpha(0.6)
        if cIcon.SetSnapToPixelGrid then
            cIcon:SetSnapToPixelGrid(false)
            cIcon:SetTexelSnappingBias(0)
        end

        local titleFs = CludesUI.MakeFont(cardFrame, 12, nil, 1, 1, 1, 0.9)
        Pix.Point(titleFs, "TOPLEFT", cIcon, "TOPRIGHT", 12, 1)
        Pix.Point(titleFs, "RIGHT", cardFrame, "RIGHT", -8, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        titleFs:SetText(L(def.title))

        local descFs = CludesUI.MakeFont(cardFrame, 10, nil, 1, 1, 1, 0.35)
        Pix.Point(descFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -4)
        Pix.Point(descFs, "RIGHT", cardFrame, "RIGHT", -8, 0)
        descFs:SetJustifyH("LEFT")
        descFs:SetWordWrap(false)
        descFs:SetText(L(def.desc))

        cardFrame:SetScript("OnEnter", function()
            cbg:SetColorTexture(0.100, 0.110, 0.124, 0.50)
            cbrd:SetColor(1, 1, 1, 0.22)
            titleFs:SetAlpha(1)
            cIcon:SetAlpha(0.85)
        end)
        cardFrame:SetScript("OnLeave", function()
            cbg:SetColorTexture(0.062, 0.070, 0.082, 0.50)
            cbrd:SetColor(1, 1, 1, 0.12)
            titleFs:SetAlpha(0.9)
            cIcon:SetAlpha(0.6)
        end)
        cardFrame:SetScript("OnClick", function()
            CreateBarFromTemplate(def.key)
        end)
        return cardFrame
    end

    ---------------------------------------------------------------------------
    --  Content header: selector row + template cards + interactive preview
    ---------------------------------------------------------------------------
    local STRIP_H_THICK = 40 -- horizontal preview strip height
    local STRIP_V_LEN = 150 -- vertical preview strip length (height)
    local STRIP_V_THICK = 40 -- vertical preview strip width
    local SEDGE = 0 -- strip edge pad (mirrors ns.EDGE_PAD visually)

    ---------------------------------------------------------------------------
    --  Vertical preview popout (TBB pattern): a vertical bar's interactive
    --  strip renders in an overlay docked to the panel's left edge -- a tall
    --  strip cannot live in the content header. Horizontal bars keep the
    --  in-header strip untouched.
    ---------------------------------------------------------------------------
    local _edbPopout
    local function PreviewPopoutAllowed()
        -- Folded to the mini window counts as closed (the page is off screen).
        if not (CludesUI:IsShown()) or CludesUI._panelCollapsed then
            return false
        end
        -- nil = mid-build (page state not stamped yet); only a definite
        -- mismatch blocks, mirroring the TBB popout gate.
        local am = CludesUI:GetActiveModule()
        local ap = CludesUI:GetActivePage()
        if am and ap and (am ~= "CludesUIDataBars" or ap ~= PAGE_DATABARS) then
            return false
        end
        return true
    end

    local function GetPreviewPopout()
        if _edbPopout then
            return _edbPopout
        end
        local oc = CreateFrame("Frame", nil, UIParent)
        oc:SetFrameStrata("FULLSCREEN_DIALOG")
        oc:SetFrameLevel(10)
        oc:SetClampedToScreen(true)
        oc:Hide()
        local backdrop = oc:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0, 0, 0, 0.9)
        local title = CludesUI.MakeFont(oc, 13, nil, 1, 1, 1, 0.9)
        title:SetPoint("TOP", oc, "TOP", 0, -7)
        title:SetText(L("Preview"))
        oc._title = title
        local hint = CludesUI.MakeFont(oc, 10, nil, 1, 1, 1, 0.4)
        -- Edge-anchored so the text wraps inside the narrow popout instead
        -- of spilling past its sides (height grows upward from the bottom).
        hint:SetPoint("BOTTOMLEFT", oc, "BOTTOMLEFT", 8, 7)
        hint:SetPoint("BOTTOMRIGHT", oc, "BOTTOMRIGHT", -8, 7)
        hint:SetJustifyH("CENTER")
        hint:SetText(L("Drag to Reorder. Click to Scroll. Right Click to Remove."))
        oc._hint = hint
        -- Self-heal (runs ONLY while shown = zero cost hidden): hide when
        -- the panel closes or another page fronts, like the TBB popout.
        local acc = 0
        oc:SetScript("OnUpdate", function(self, elapsed)
            acc = acc + elapsed
            if acc < 0.25 then
                return
            end
            acc = 0
            if not PreviewPopoutAllowed() then
                self:Hide()
            end
        end)
        _edbPopout = oc
        return oc
    end

    -- The popout sits on UIParent beside the panel: it folds away with the panel
    -- and comes back with it while a vertical bar is still the one selected (the
    -- header's own condition for showing it).
    CludesUI:RegisterOnCollapse(function(enabled)
        if not _edbPopout then
            return
        end
        if enabled then
            _edbPopout:Hide()
        elseif _edbPopout._strip and PreviewPopoutAllowed() then
            local conf = SelectedBar()
            if conf and conf.orientation == "V" then
                _edbPopout:Show()
            end
        end
    end)

    _edbHeaderBuilder = function(heading, hdrW)
        local PAD = CludesUI.CONTENT_PAD
        if not PAD then
            PAD = 10
        end
        local DDS = CludesUI.DD_STYLE
        local EGc = CludesUI.CLUDES_GREEN
        local tDimR = CludesUI.TEXT_DIM_R
        if tDimR == nil then
            tDimR = 0.7
        end
        local tDimG = CludesUI.TEXT_DIM_G
        if tDimG == nil then
            tDimG = 0.7
        end
        local tDimB = CludesUI.TEXT_DIM_B
        if tDimB == nil then
            tDimB = 0.7
        end
        local tDimA = CludesUI.TEXT_DIM_A
        if tDimA == nil then
            tDimA = 0.85
        end
        local fy = -8

        local conf = SelectedBar()
        _edbPreviewHost = nil
        _edbStripRelayout = nil
        _edbStripBarId = nil

        -----------------------------------------------------------------------
        --  Row 1: bar selector dropdown | + New Bar (centered as a pair)
        -----------------------------------------------------------------------
        local DD_H = 30
        local ddW = 280
        local NEWBTN_W = 110
        local ddBtn = CreateFrame("Button", nil, heading)
        Pix.Size(ddBtn, ddW, DD_H)
        Pix.Point(ddBtn, "TOPLEFT", heading, "TOPLEFT", (hdrW - (ddW + 10 + NEWBTN_W)) / 2, fy)
        ddBtn:SetFrameLevel(heading:GetFrameLevel() + 5)
        local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
        ddBg:SetAllPoints()
        ddBg:SetColorTexture(DDS.BG_R, DDS.BG_G, DDS.BG_B, DDS.BG_A)
        local ddBrd = CludesUI.MakeRoundedBorder(ddBtn, 1, 1, 1, DDS.BRD_A, ddBg)
        local ddLbl = CludesUI.MakeFont(ddBtn, 13, nil, 1, 1, 1, DDS.TXT_A)
        ddLbl:SetJustifyH("LEFT")
        ddLbl:SetWordWrap(false)
        ddLbl:SetMaxLines(1)
        ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 12, 0)
        local arrow = CludesUI.MakeDropdownArrow(ddBtn, 12, CludesUI.PanelPP)
        ddLbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)
        if conf then
            local nm = conf.name
            if nm == nil then
                nm = ""
            end
            ddLbl:SetText(nm)
        else
            ddLbl:SetText(L("No Info Bar"))
        end

        -- The bar menu is built on its first open and kept across header builds
        -- (_edbMenus.bar), its bar rows pooled by index: each open points it at
        -- this header's selector and re-applies every row to the current bars.
        local function BuildBarMenu()
            local ITEM_H = 26
            local ICON_SZ = 14
            local hlA = DDS.ITEM_HL_A
            local selA = DDS.ITEM_SEL_A
            local dropMenu = _edbMenus.bar
            if dropMenu then
                if dropMenu:IsShown() then
                    dropMenu:Hide()
                end
            else
                dropMenu = MenuShell()
                dropMenu._rows = {}

                -- One bar row; its bar and selected state are set per open
                -- (item._bar, item._isSel), and item._rest puts it in its
                -- resting look.
                dropMenu._makeRow = function()
                    local item = CreateFrame("Button", nil, dropMenu)
                    item:SetHeight(ITEM_H)
                    item:SetFrameLevel(dropMenu:GetFrameLevel() + 2)

                    local iLbl = CludesUI.MakeFont(item, 11, nil, tDimR, tDimG, tDimB, tDimA)
                    iLbl:SetJustifyH("LEFT")
                    iLbl:SetWordWrap(false)
                    iLbl:SetMaxLines(1)
                    iLbl:SetPoint("LEFT", item, "LEFT", 10, 0)

                    local iHl = item:CreateTexture(nil, "ARTWORK")
                    iHl:SetAllPoints()
                    iHl:SetColorTexture(1, 1, 1, 1)

                    -- Rename and Delete inline at the right edge (every bar is
                    -- user-made): dim at rest, lit with the row on hover.
                    local delBtn, editBtn
                    local function Rest()
                        delBtn:SetAlpha(0.75)
                        editBtn:SetAlpha(0.75)
                        iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        iHl:SetAlpha(item._isSel and selA or 0)
                    end
                    item._rest = Rest
                    item._lbl = iLbl
                    local function OverAny()
                        return item:IsMouseOver() or delBtn:IsMouseOver() or editBtn:IsMouseOver()
                    end
                    local function InlineIcon(anchor, relPoint, x, file, tip, act)
                        local btn = CreateFrame("Button", nil, item)
                        btn:SetSize(ICON_SZ, ICON_SZ)
                        btn:SetPoint("RIGHT", anchor, relPoint, x, 0)
                        btn:SetFrameLevel(item:GetFrameLevel() + 2)
                        local icon = btn:CreateTexture(nil, "OVERLAY")
                        icon:SetSize(ICON_SZ, ICON_SZ)
                        icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
                        if icon.SetSnapToPixelGrid then
                            icon:SetSnapToPixelGrid(false)
                            icon:SetTexelSnappingBias(0)
                        end
                        icon:SetTexture(MEDIA_ICONS .. file)
                        btn:SetScript("OnEnter", function(self)
                            self:SetAlpha(1)
                            iLbl:SetTextColor(1, 1, 1, 1)
                            iHl:SetAlpha(hlA)
                            delBtn:SetAlpha(0.85)
                            editBtn:SetAlpha(0.85)
                            CludesUI.ShowWidgetTooltip(self, CludesUI.L(tip))
                        end)
                        btn:SetScript("OnLeave", function(self)
                            if OverAny() then
                                self:SetAlpha(0.85)
                            else
                                Rest()
                            end
                            CludesUI.HideWidgetTooltip()
                        end)
                        btn:SetScript("OnClick", function()
                            dropMenu:Hide()
                            act(item._bar)
                        end)
                        return btn
                    end
                    delBtn = InlineIcon(item, "RIGHT", -8, "cui-close.png", "Delete", PromptDeleteBar)
                    editBtn = InlineIcon(delBtn, "LEFT", -4, "cui-edit.png", "Rename", PromptRenameBar)
                    iLbl:SetPoint("RIGHT", editBtn, "LEFT", -4, 0)

                    item:SetScript("OnEnter", function()
                        iLbl:SetTextColor(1, 1, 1, 1)
                        iHl:SetAlpha(hlA)
                        delBtn:SetAlpha(1)
                        editBtn:SetAlpha(1)
                    end)
                    item:SetScript("OnLeave", function()
                        if not (delBtn:IsMouseOver() or editBtn:IsMouseOver()) then
                            Rest()
                        end
                    end)
                    item:SetScript("OnClick", function()
                        dropMenu:Hide()
                        local p = Profile()
                        if p then
                            p.selectedBarId = item._bar.id
                        end
                        HardRefresh()
                    end)
                    return item
                end

                local div = dropMenu:CreateTexture(nil, "ARTWORK")
                div:SetHeight(1)
                div:SetColorTexture(1, 1, 1, 0.10)
                dropMenu._div = div

                -- "+ Create New DataBar..." action row (expands the card strip)
                local addItem = CreateFrame("Button", nil, dropMenu)
                addItem:SetHeight(ITEM_H)
                addItem:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                local addLbl = CludesUI.MakeFont(addItem, 11, nil, tDimR, tDimG, tDimB, tDimA)
                addLbl:SetPoint("LEFT", addItem, "LEFT", 10, 0)
                addLbl:SetJustifyH("LEFT")
                addLbl:SetText(L("+ Create New DataBar..."))
                local addHl = addItem:CreateTexture(nil, "ARTWORK")
                addHl:SetAllPoints()
                addHl:SetColorTexture(1, 1, 1, 1)
                addItem:SetScript("OnEnter", function()
                    addLbl:SetTextColor(1, 1, 1, 1)
                    addHl:SetAlpha(hlA)
                end)
                addItem:SetScript("OnLeave", function()
                    addLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    addHl:SetAlpha(0)
                end)
                addItem:SetScript("OnClick", function()
                    dropMenu:Hide()
                    _cardsExpanded = true
                    HeaderOnly()
                end)
                addItem._lbl, addItem._hl = addLbl, addHl
                dropMenu._addItem = addItem

                CloseOnOutsideClick(dropMenu)
                _edbMenus.bar = dropMenu
            end

            dropMenu._anchor = ddBtn
            dropMenu:ClearAllPoints()
            dropMenu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
            dropMenu:SetPoint("TOPRIGHT", ddBtn, "BOTTOMRIGHT", 0, -2)

            local mH = 4
            local barList = mod.BarsInOrder()
            local rowList = dropMenu._rows
            for position = 1, #barList do
                local b = barList[position]
                local item = rowList[position]
                if not item then
                    item = dropMenu._makeRow()
                    rowList[position] = item
                end
                item._bar = b
                item._isSel = conf ~= nil and b.id == conf.id
                item:ClearAllPoints()
                item:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -mH)
                item:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -mH)
                item._lbl:SetText(b.name or "")
                item._rest()
                item:Show()
                mH = mH + ITEM_H
            end
            for position = #barList + 1, #rowList do
                rowList[position]:Hide()
            end

            local div = dropMenu._div
            if #barList > 0 then
                div:ClearAllPoints()
                div:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -mH - 4)
                div:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -mH - 4)
                div:Show()
                mH = mH + 9
            else
                div:Hide()
            end

            local addItem = dropMenu._addItem
            addItem:ClearAllPoints()
            addItem:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -mH)
            addItem:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -mH)
            addItem._lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            addItem._hl:SetAlpha(0)
            mH = mH + ITEM_H

            dropMenu:SetHeight(mH + 4)
            dropMenu:SetScript("OnUpdate", dropMenu._closeOutside)
            dropMenu:Show()
        end

        -- The value's alpha lives in its text colour alone (built at TXT_A),
        -- so a hover and a leave land back on the resting look.
        ddBtn:SetScript("OnEnter", function()
            ddLbl:SetTextColor(1, 1, 1, 1)
            local brdHA = DDS.BRD_HA
            if brdHA == nil then
                brdHA = 0.30
            end
            ddBrd:SetColor(1, 1, 1, brdHA)
            ddBg:SetColorTexture(DDS.BG_R, DDS.BG_G, DDS.BG_B, DDS.BG_HA)
        end)
        ddBtn:SetScript("OnLeave", function()
            local ddMenu = _edbMenus.bar
            if ddMenu and ddMenu:IsShown() then
                return
            end
            ddLbl:SetTextColor(1, 1, 1, DDS.TXT_A)
            ddBrd:SetColor(1, 1, 1, DDS.BRD_A)
            ddBg:SetColorTexture(DDS.BG_R, DDS.BG_G, DDS.BG_B, DDS.BG_A)
        end)
        ddBtn:SetScript("OnClick", function()
            local ddMenu = _edbMenus.bar
            if ddMenu and ddMenu:IsShown() then
                ddMenu:Hide()
            else
                BuildBarMenu()
            end
        end)
        ddBtn:HookScript("OnHide", function()
            if _edbMenus.bar then
                _edbMenus.bar:Hide()
            end
        end)

        -- "+ New Bar" (toggles the template card strip)
        local newBtn = CreateFrame("Button", nil, heading)
        Pix.Size(newBtn, 110, DD_H)
        Pix.Point(newBtn, "LEFT", ddBtn, "RIGHT", 10, 0)
        newBtn:SetFrameLevel(heading:GetFrameLevel() + 5)
        CludesUI.MakeStyledButton(newBtn, "+ New Bar", 12, CludesUI.WB_COLOURS, function()
            _cardsExpanded = not _cardsExpanded
            HeaderOnly()
        end)

        -- (Bar enable lives in the BAR SETTINGS section, not the header.)

        fy = fy - DD_H - 10

        -----------------------------------------------------------------------
        --  Template card strip (expanded state)
        -----------------------------------------------------------------------
        if _cardsExpanded then
            local stripW = hdrW - PAD * 2
            local gap = 10
            local cw = floor((stripW - gap * 3) / 4)
            local ch = 64
            local host = CreateFrame("Frame", nil, heading)
            Pix.Size(host, stripW, ch)
            Pix.Point(host, "TOPLEFT", heading, "TOPLEFT", PAD, fy)
            for i = 1, 4 do
                MakeTemplateCard(host, (i - 1) * (cw + gap), 0, cw, ch, TEMPLATE_CARDS[i])
            end
            fy = fy - ch - 12
        end

        -----------------------------------------------------------------------
        --  Zero bars: hint only, no preview
        -----------------------------------------------------------------------
        if not conf then
            local hint = CludesUI.MakeFont(heading, 12, nil, 1, 1, 1, 0.4)
            hint:SetPoint("TOPLEFT", heading, "TOPLEFT", PAD + 4, fy - 2)
            hint:SetText(L("Create a DataBar to get started."))
            fy = fy - 24
            return math.abs(fy) + 6
        end

        -----------------------------------------------------------------------
        --  Interactive preview strip
        -----------------------------------------------------------------------
        -- Extra breathing room above the preview strip.
        fy = fy - 10

        local vertical = conf.orientation == "V"
        local stripLen, stripThick
        local stripParent = heading
        if vertical then
            -- Vertical: the strip lives in the docked overlay popout, which persists
            -- across header rebuilds. The strip and its add tile (parented to the
            -- popout too, not to the strip) are kept frames there (Pool.Kept, below):
            -- every header build dresses the same two again, so a rebuild never
            -- strands an old one beside the new.
            local oc = GetPreviewPopout()
            stripParent = oc
            stripThick = STRIP_V_THICK
            stripLen = STRIP_V_LEN
            local scrollFrame = CludesUI._scrollFrame
            local sfH = scrollFrame and scrollFrame:GetHeight()
            if sfH and sfH > 260 then
                stripLen = math.min(520, sfH - 150)
            end
        else
            if _edbPopout then
                _edbPopout:Hide()
            end
            stripLen = hdrW - PAD * 2 - (STRIP_H_THICK + 8) -- room for the + tile
            stripThick = STRIP_H_THICK
        end

        -- Vertical: the popout's kept strip, the popout sized around it, its
        -- title and hint and the add tile below (the extra tail room is for
        -- the bottom hint, which wraps inside the narrow popout) and docked
        -- left of the options window. Horizontal: a strip under the header.
        local strip
        if vertical then
            local oc = stripParent
            strip = Pool.Kept(_edbKeep, "popStrip", "Frame", oc)
            Pix.Size(strip, stripThick, stripLen)
            oc._strip = strip
            Pix.Size(oc, math.max(stripThick + 90, 150), stripLen + stripThick + 92)
            strip:ClearAllPoints()
            strip:SetPoint("TOP", oc, "TOP", 0, -28)
            strip:SetFrameLevel(oc:GetFrameLevel() + 3)
            oc:ClearAllPoints()
            local scrollFrame = CludesUI._scrollFrame
            if scrollFrame then
                oc:SetPoint("RIGHT", scrollFrame, "LEFT", 0, 0)
            else
                oc:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
            oc:Show()
        else
            strip = CreateFrame("Frame", nil, stripParent)
            Pix.Size(strip, stripLen, stripThick)
            Pix.Point(strip, "TOPLEFT", heading, "TOPLEFT", PAD, fy)
            strip:SetFrameLevel(heading:GetFrameLevel() + 3)
        end
        -- Border handle set BEFORE the backdrop so the theme pass can fade
        -- it with Bar Opacity, exactly like the live bar.
        strip._edbBorder = Pix.CreateBorder(strip, 0, 0, 0, 0.8, 1, "OVERLAY", 7)
        mod.MakePreviewBackdrop(strip, conf.theme, not conf.hideBorder)
        _edbPreviewHost = strip

        local stripUsable = stripLen - SEDGE * 2
        local blocks = conf.blocks
        local nBlocks = #blocks
        -- Hidden blocks keep their index in every per-segment array below (the
        -- reorder commit works in the bar's own order) but draw nothing.
        local nShown = nBlocks
        for i = 1, nBlocks do
            if BlockHidden(blocks[i]) then
                nShown = nShown - 1
            end
        end

        if nShown == 0 then
            local hintFS = CludesUI.MakeFont(strip, 11, nil, 1, 1, 1, 0.4)
            hintFS:SetPoint("CENTER", strip, "CENTER", 0, 0)
            if vertical then
                -- The vertical strip is only a few px wide; cap the hint to
                -- the popout's inner width so it wraps instead of spilling.
                hintFS:SetWidth(130)
                hintFS:SetJustifyH("CENTER")
            end
            hintFS:SetText(L("Click + to add your first block"))
        end

        -- Segment overlays: one invisible button per block, retargeted by
        -- LayoutStrip below (built once per header build). dragIdx is shared
        -- with the reorder machinery below; hover borders are suppressed
        -- while a drag is live (only the insertion line marks placement).
        local dragIdx
        local dragEndTime = 0
        local segBtns, shareFSs = {}, {}
        for i = 1, nBlocks do
            local b = blocks[i]
            local button = CreateFrame("Button", nil, strip)
            button:SetFrameLevel(strip:GetFrameLevel() + 5)
            local hb = Pix.CreateBorder(button, EGc.r, EGc.g, EGc.b, 1, 2, "OVERLAY", 7)
            hb:Hide()
            button._brd = hb
            button:SetScript("OnEnter", function(s2)
                if dragIdx then
                    return
                end
                s2._brd:Show()
                -- Hovering a preview segment lights the real bar's block
                -- the same way hovering its Width % setting does.
                _edbSegHoverId = b.id
                if mod.SetBlockEditHighlight then
                    mod.SetBlockEditHighlight(conf.id, b.id)
                end
            end)
            button:SetScript("OnLeave", function(s2)
                s2._brd:Hide()
                if _edbSegHoverId == b.id then
                    _edbSegHoverId = nil
                    if mod.SetBlockEditHighlight then
                        mod.SetBlockEditHighlight(nil, nil)
                    end
                end
            end)

            -- Two centred one-line labels: the block's type above, its
            -- share of the bar (set by LayoutStrip) below.
            local function Label(size, alpha, y)
                local fs = CludesUI.MakeFont(button, size, nil, 1, 1, 1, alpha)
                fs:SetPoint("LEFT", button, "LEFT", 2, y)
                fs:SetPoint("RIGHT", button, "RIGHT", -2, y)
                fs:SetJustifyH("CENTER")
                fs:SetWordWrap(false)
                fs:SetMaxLines(1)
                return fs
            end
            Label(10, 0.85, 6):SetText(L(TYPE_LABEL[b.type] or b.type))
            local shareFS = Label(9, 0.5, -7)

            -- Settings-section hover wash (driven by the body watcher).
            local ehl = button:CreateTexture(nil, "OVERLAY", nil, 5)
            ehl:SetAllPoints()
            ehl:SetColorTexture(1, 1, 1, 0.08)
            ehl:Hide()
            button._editHL = ehl

            segBtns[i] = button
            shareFSs[i] = shareFS
            if BlockHidden(b) then
                button:Hide()
            end
        end

        -- Hovering a block's settings section washes its preview segment.
        _edbSegHighlightFn = function(hlBlockId)
            for k = 1, nBlocks do
                local scrollBar = segBtns[k]
                if scrollBar and scrollBar._editHL then
                    scrollBar._editHL:SetShown(hlBlockId ~= nil and blocks[k].id == hlBlockId)
                end
            end
        end

        -- A 1px seam line at each boundary, shown where the two segments touch.
        local lines = {}
        for i = 1, nBlocks - 1 do
            local line = strip:CreateTexture(nil, "OVERLAY", nil, 2)
            line:SetColorTexture(1, 1, 1, 0.12)
            if vertical then
                line:SetHeight(1)
            else
                line:SetWidth(1)
            end
            lines[i] = line
        end

        -- Solve + position everything. Also called by the body's Width %
        -- and Length sliders for live feedback (no header rebuild).
        local lastSegs
        local function LayoutStrip()
            local barUsable = ResolvedBarLength(conf) - 2 * mod.EDGE_PAD
            if barUsable < 1 then
                barUsable = 1
            end
            local scale = stripUsable / barUsable
            local function measure(bc)
                -- Zero, as the live bar measures a block with no instance.
                if BlockHidden(bc) then
                    return 0
                end
                local wid = mod.GetLiveAutoLength(conf.id, bc.id)
                if not wid or wid <= 0 then
                    wid = EST_LEN[bc.type] or 80
                end
                return wid
            end
            -- Solve in REAL bar px (Auto Sized extents and gaps are real pixels), then
            -- map each segment's own edges into strip px. Segments may be
            -- NON-contiguous (a Force Centered block leaves pads beside it); touching
            -- neighbors still telescope because they share the same real edge. _touch
            -- marks real seams -- boundary lines draw only there.
            local segs = mod.SolveLayout(conf, barUsable, measure)
            for i = 1, #segs do
                local seg = segs[i]
                local rAt = seg.at or 0
                local a = floor(rAt * scale + 0.5)
                local e = floor((rAt + seg.px) * scale + 0.5)
                -- Seam lines run between shown segments only: a hidden one
                -- draws none and is skipped as a neighbor.
                local nxt
                if not BlockHidden(seg.block) then
                    local k = i + 1
                    while segs[k] and BlockHidden(segs[k].block) do
                        k = k + 1
                    end
                    nxt = segs[k]
                end
                if nxt then
                    local d = (nxt.at or 0) - (rAt + seg.px)
                    seg._touch = d > -0.75 and d < 0.75
                else
                    seg._touch = false
                end
                seg.pos = SEDGE + a
                seg.px = e - a
            end
            lastSegs = segs
            for i = 1, #segs do
                local seg = segs[i]
                local px = seg.px
                if px < 1 then
                    px = 1
                end
                local cursor = seg.pos
                local button = segBtns[i]
                if button then
                    button:ClearAllPoints()
                    if vertical then
                        button:SetSize(stripThick, px)
                        button:SetPoint("TOP", strip, "TOP", 0, -cursor)
                    else
                        button:SetSize(px, stripThick)
                        button:SetPoint("LEFT", strip, "LEFT", cursor, 0)
                    end
                    -- Base position for the drag-reorder nudge animation.
                    button._basePos = cursor
                    button._curOff = 0
                    button._tgtOff = 0
                    if seg.isFill then
                        shareFSs[i]:SetText(L("fill"))
                    else
                        shareFSs[i]:SetText(format("%.1f%%", mod.NormalizedShare(conf, seg.block.id)))
                    end
                end
                cursor = cursor + px
                local lineTex = lines[i]
                if lineTex then
                    lineTex:SetShown(seg._touch and true or false)
                    lineTex:ClearAllPoints()
                    if vertical then
                        lineTex:SetPoint("LEFT", strip, "TOPLEFT", 0, -cursor)
                        lineTex:SetPoint("RIGHT", strip, "TOPRIGHT", 0, -cursor)
                    else
                        lineTex:SetPoint("TOP", strip, "TOPLEFT", cursor, 0)
                        lineTex:SetPoint("BOTTOM", strip, "BOTTOMLEFT", cursor, 0)
                    end
                end
            end
        end
        _edbStripRelayout = LayoutStrip
        _edbStripBarId = conf.id
        LayoutStrip()

        -----------------------------------------------------------------------
        -- Drag-to-reorder segments (CDM preview pattern): while dragging, the other
        -- segments ease apart around the hovered boundary via a small animated nudge
        -- and an accent insertion line marks the drop point; release commits the move.
        -----------------------------------------------------------------------
        local reorderLine = strip:CreateTexture(nil, "OVERLAY", nil, 7)
        do
            local ar2, ag2, ab3 = mod.GetAccent()
            reorderLine:SetColorTexture(ar2, ag2, ab3, 0.9)
        end
        if vertical then
            reorderLine:SetSize(stripThick, 2)
        else
            reorderLine:SetSize(2, stripThick)
        end
        reorderLine:Hide()

        local NUDGE = 6
        local animTicker
        local function EnsureAnimTicker()
            if animTicker then
                return
            end
            -- A strip of the page pool that a newer header build dressed again
            -- holds that build's segments: the ticker ends with this build.
            local gen = Pool.Gen(strip)
            animTicker = C_Timer.NewTicker(0.016, function()
                if Pool.Gen(strip) ~= gen or Pool.IsIdle(strip) then
                    animTicker:Cancel()
                    animTicker = nil
                    return
                end
                local moving = false
                for k = 1, #segBtns do
                    local scrollBar = segBtns[k]
                    local current = scrollBar._curOff or 0
                    local tgt = scrollBar._tgtOff or 0
                    if math.abs(current - tgt) > 0.4 then
                        current = current + (tgt - current) * 0.35
                        moving = true
                    else
                        current = tgt
                    end
                    scrollBar._curOff = current
                    if scrollBar._basePos then
                        scrollBar:ClearAllPoints()
                        if vertical then
                            scrollBar:SetPoint("TOP", strip, "TOP", 0, -(scrollBar._basePos + current))
                        else
                            scrollBar:SetPoint("LEFT", strip, "LEFT", scrollBar._basePos + current, 0)
                        end
                    end
                end
                if not moving and not dragIdx then
                    animTicker:Cancel()
                    animTicker = nil
                end
            end)
        end

        local function CursorStripPos()
            local cx, cy = GetCursorPosition()
            local es = strip:GetEffectiveScale()
            if not es or es == 0 then
                es = 1
            end
            if vertical then
                return (strip:GetTop() or 0) - cy / es
            end
            return cx / es - (strip:GetLeft() or 0)
        end

        local function ComputeInsertIdx()
            if not lastSegs then
                return nil
            end
            -- Before the first segment whose middle lies past the cursor.
            local place = CursorStripPos()
            for k, seg in ipairs(lastSegs) do
                if place < (seg.pos or 0) + (seg.px or 0) / 2 then
                    return k
                end
            end
            return #lastSegs + 1
        end

        -- A drop is a no-op when only hidden segments (see BlockHidden) lie
        -- between the target boundary and the dragged segment: the move
        -- would change nothing on screen and only shift a hidden entry.
        local function IsNoopDrop(from, to)
            if to == from or to == from + 1 then
                return true
            end
            local lo, hi = to, from - 1
            if to > from then
                lo, hi = from + 1, to - 1
            end
            for k = lo, hi do
                if not BlockHidden(blocks[k]) then
                    return false
                end
            end
            return true
        end

        local function UpdateDragVisuals()
            if not dragIdx or not lastSegs then
                return
            end
            local targetIdx = ComputeInsertIdx()
            -- Boundaries adjoining the dragged segment are a no-op drop.
            local noop = IsNoopDrop(dragIdx, targetIdx)
            -- Counted without the dragged segment, everything at or after the
            -- insertion point eases toward the end and everything before it
            -- back toward the start.
            local insertAt = targetIdx > dragIdx and targetIdx - 1 or targetIdx
            for k = 1, #segBtns do
                local off = 0
                if k ~= dragIdx and not noop then
                    local at = k > dragIdx and k - 1 or k
                    off = at >= insertAt and NUDGE or -NUDGE
                end
                segBtns[k]._tgtOff = off
            end
            EnsureAnimTicker()
            if noop then
                reorderLine:Hide()
                return
            end
            -- The insertion line: the target segment's leading edge, or the
            -- last one's trailing edge for a drop at the end.
            local linePos
            local target = lastSegs[targetIdx]
            if target then
                linePos = target.pos or SEDGE
            else
                local last = lastSegs[#lastSegs]
                linePos = (last.pos or SEDGE) + (last.px or 0)
            end
            reorderLine:ClearAllPoints()
            if vertical then
                reorderLine:SetPoint("TOP", strip, "TOP", 0, -(linePos - 1))
            else
                reorderLine:SetPoint("LEFT", strip, "LEFT", linePos - 1, 0)
            end
            reorderLine:Show()
        end

        -- Pickup ghost: a floating half-scale copy of the segment that rides
        -- the cursor while dragging (CDM preview pattern); the segment itself
        -- stays in place dimmed to 0.3.
        local dragGhost
        local function EnsureDragGhost()
            if dragGhost then
                return dragGhost
            end
            -- One kept ghost for the session (Pool.Kept on UIParent): the first
            -- drag of each header build dresses it again.
            dragGhost = Pool.Kept(_edbKeep, "dragGhost", "Frame", UIParent)
            dragGhost:SetFrameStrata("TOOLTIP")
            dragGhost:SetFrameLevel(500)
            local gBg = dragGhost:CreateTexture(nil, "BACKGROUND")
            gBg:SetAllPoints()
            gBg:SetColorTexture(0.111, 0.103, 0.096, 0.95)
            local ar2, ag2, ab3 = mod.GetAccent()
            CludesUI.MakeBorder(dragGhost, ar2, ag2, ab3, 0.9, Pix)
            local gl = CludesUI.MakeFont(dragGhost, 10, nil, 1, 1, 1, 0.9)
            gl:SetPoint("CENTER")
            dragGhost._lbl = gl
            dragGhost:Hide()
            return dragGhost
        end

        local function FinishDrag()
            strip:SetScript("OnUpdate", nil)
            local from = dragIdx
            dragIdx = nil
            dragEndTime = GetTime()
            if dragGhost then
                dragGhost:Hide()
            end
            reorderLine:Hide()
            if from and segBtns[from] then
                segBtns[from]:SetAlpha(1)
            end
            for k = 1, #segBtns do
                segBtns[k]._tgtOff = 0
            end
            local targetIdx = ComputeInsertIdx()
            if not (from and targetIdx) then
                return
            end
            if IsNoopDrop(from, targetIdx) then
                return
            end
            mod.MoveBlockTo(conf.id, blocks[from].id, targetIdx)
            -- Full refresh: the preview strip lives in the content header,
            -- which a plain RefreshPage never rebuilds.
            HardRefresh()
        end

        local function BeginDrag(fromIdx)
            dragIdx = fromIdx
            local scrollBar = segBtns[fromIdx]
            if scrollBar._brd then
                scrollBar._brd:Hide()
            end
            scrollBar:SetAlpha(0.3)
            -- The ghost: the segment's size (at least 24 long; a squashed
            -- one takes the strip's thickness) and its type label.
            local ghost = EnsureDragGhost()
            local gw, gh = scrollBar:GetSize()
            if not gh or gh < 12 then
                gh = stripThick
            end
            ghost:SetSize(math.max(gw or 0, 24), gh)
            local kind = blocks[fromIdx].type
            ghost._lbl:SetText(L(TYPE_LABEL[kind] or kind))
            ghost:SetScale(0.5)
            ghost:Show()
            EnsureAnimTicker()
            -- Cursor follow + release detection (mouse-up can land anywhere).
            strip:SetScript("OnUpdate", function()
                if not IsMouseButtonDown("LeftButton") then
                    FinishDrag()
                    return
                end
                local cx, cy = GetCursorPosition()
                local sc = UIParent:GetEffectiveScale()
                cx, cy = cx / sc, cy / sc
                local gs = dragGhost:GetScale() or 1
                dragGhost:ClearAllPoints()
                dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / gs, cy / gs)
                UpdateDragVisuals()
            end)
        end

        -- Right-click context menu on a segment: block actions only
        -- (bar deletion = the selector dropdown's inline delete). Built on its
        -- first open and kept across header builds (_edbMenus.seg); each open
        -- points it at that segment's bar and block.
        local function ShowSegmentMenu(anchorBtn, blockId)
            local dropMenu = _edbMenus.seg
            if dropMenu then
                if dropMenu:IsShown() then
                    dropMenu:Hide()
                end
            else
                local ROW_H2 = 24
                dropMenu = MenuShell(150)
                local rowY = -3
                local function AddRow(textValue, onClick)
                    local row = CreateFrame("Button", nil, dropMenu)
                    row:SetHeight(ROW_H2)
                    row:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, rowY)
                    row:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, rowY)
                    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
                    highlight:SetAllPoints()
                    highlight:SetColorTexture(1, 1, 1, 0.08)
                    local labelFS = CludesUI.MakeFont(row, 11, nil, 1, 1, 1, 0.9)
                    labelFS:SetPoint("LEFT", row, "LEFT", 10, 0)
                    labelFS:SetText(textValue)
                    row:SetScript("OnClick", function()
                        dropMenu:Hide()
                        onClick()
                    end)
                    rowY = rowY - ROW_H2
                end
                AddRow(L("Remove Block"), function()
                    mod.RemoveBlock(dropMenu._barId, dropMenu._blockId)
                    -- Full refresh: the preview strip lives in the content
                    -- header, which a plain RefreshPage never rebuilds.
                    HardRefresh()
                    -- The page just lost a whole section; a bottom-scrolled view
                    -- would be left staring at blank space.
                    if CludesUI.SmoothScrollTo then
                        CludesUI.SmoothScrollTo(0)
                    end
                end)
                dropMenu:SetHeight(-rowY + 3)
                -- Click-away dismiss. The opening right-button is STILL DOWN on
                -- the first frames (the menu opens on RightButtonDown) -- without
                -- the guard (menu._openGuard, set per open) the menu dismissed
                -- itself instantly.
                dropMenu:SetScript("OnUpdate", function(m)
                    if m._openGuard then
                        if not IsMouseButtonDown("RightButton") then
                            m._openGuard = nil
                        end
                        return
                    end
                    if
                        not m:IsMouseOver()
                        and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
                    then
                        m:Hide()
                    end
                end)
                _edbMenus.seg = dropMenu
            end
            dropMenu._barId = conf.id
            dropMenu._blockId = blockId
            dropMenu:ClearAllPoints()
            dropMenu:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
            dropMenu._openGuard = true
            dropMenu:Show()
        end

        -- Manual 3px drag threshold (CDM preview pattern -- WoW's native
        -- drag threshold is too coarse for small segments). Left press arms
        -- the pending tracker; movement starts the drag; right-click opens
        -- the context menu. dragEndTime guards the release-click.
        local DRAG_THRESHOLD = 3
        for i = 1, nBlocks do
            local segBtn = segBtns[i]
            local segBlockId = blocks[i].id
            segBtn:RegisterForClicks("LeftButtonUp", "RightButtonDown")
            segBtn:SetScript("OnClick", function(scrollBar, mbtn)
                -- The dragEndTime guard swallows the release-click of a
                -- drag; a press that never crossed the 3px threshold is a
                -- TRUE click (drag starts never fire OnClick at all).
                if GetTime() - dragEndTime < 0.2 then
                    return
                end
                if mbtn == "RightButton" then
                    ShowSegmentMenu(scrollBar, segBlockId)
                elseif mbtn == "LeftButton" then
                    if _edbNavigateFn then
                        _edbNavigateFn("block:" .. segBlockId)
                    end
                end
            end)
            segBtn:SetScript("OnMouseDown", function(scrollBar, mbtn)
                if mbtn ~= "LeftButton" then
                    return
                end
                if dragIdx then
                    return
                end
                local cx, cy = GetCursorPosition()
                scrollBar._pendX, scrollBar._pendY = cx, cy
                scrollBar:SetScript("OnUpdate", function(s3)
                    if not IsMouseButtonDown("LeftButton") then
                        s3:SetScript("OnUpdate", nil)
                        s3._pendX, s3._pendY = nil, nil
                        return
                    end
                    local nx, nyy = GetCursorPosition()
                    if
                        math.abs(nx - (s3._pendX or nx)) > DRAG_THRESHOLD
                        or math.abs(nyy - (s3._pendY or nyy)) > DRAG_THRESHOLD
                    then
                        s3:SetScript("OnUpdate", nil)
                        s3._pendX, s3._pendY = nil, nil
                        BeginDrag(i)
                    end
                end)
            end)
        end

        -- "+" add-block tile (CDM preview add-button look): bar-height
        -- square, 4px off the strip, dark fill, colored "+" glyph that
        -- lights up with an accent border on hover.
        -- Vertical: kept in the popout with the strip, under it.
        local addBtn
        if vertical then
            addBtn = Pool.Kept(_edbKeep, "popAddBtn", "Button", stripParent)
            Pix.Size(addBtn, stripThick, stripThick)
            Pix.Point(addBtn, "TOP", strip, "BOTTOM", 0, -4)
        else
            addBtn = CreateFrame("Button", nil, stripParent)
            Pix.Size(addBtn, stripThick, stripThick)
            Pix.Point(addBtn, "LEFT", strip, "RIGHT", 4, 0)
        end
        addBtn:SetFrameLevel(strip:GetFrameLevel() + 2)
        local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints()
        addBg:SetColorTexture(0.08, 0.08, 0.08, 0.6)
        if addBg.SetSnapToPixelGrid then
            addBg:SetSnapToPixelGrid(false)
            addBg:SetTexelSnappingBias(0)
        end
        Pix.CreateBorder(addBtn, 0.3, 0.3, 0.3, 0.5, 1, "OVERLAY", 7)
        local addLbl = CludesUI.MakeFont(addBtn, 22, nil, EGc.r, EGc.g, EGc.b, 0.7)
        addLbl:SetPoint("CENTER", 0, 1)
        addLbl:SetText("+")
        local addHlCont = CreateFrame("Frame", nil, addBtn)
        addHlCont:SetAllPoints()
        addHlCont:SetFrameLevel(addBtn:GetFrameLevel() + 1)
        local addBrd = Pix.CreateBorder(addHlCont, EGc.r, EGc.g, EGc.b, 1, 2, "OVERLAY", 7)
        addBrd:Hide()

        -- The add-block menu: built on its first open and kept across header
        -- builds (_edbMenus.add); each open points it at this header's tile
        -- and re-applies the on-bar dimming for this bar.
        local function ToggleAddMenu()
            local dropMenu = _edbMenus.add
            if dropMenu and dropMenu:IsShown() then
                dropMenu:Hide()
                return
            end
            local ITEM_H = 24
            local hlA = DDS.ITEM_HL_A
            if not dropMenu then
                dropMenu = MenuShell(190)
                dropMenu._rows = {}
                local mH = 4
                for _, t in ipairs(mod.OfferedBlockTypes()) do
                    local item = CreateFrame("Button", nil, dropMenu)
                    item:SetHeight(ITEM_H)
                    item:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -mH)
                    item:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -mH)
                    item:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                    local iLbl = CludesUI.MakeFont(item, 11, nil, tDimR, tDimG, tDimB, tDimA)
                    iLbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                    iLbl:SetJustifyH("LEFT")
                    iLbl:SetText(L(t.label))
                    local iHl = item:CreateTexture(nil, "ARTWORK")
                    iHl:SetAllPoints()
                    iHl:SetColorTexture(1, 1, 1, 1)
                    -- item._baseA / item._hoverA: this open's label alphas.
                    item:SetScript("OnEnter", function()
                        iLbl:SetTextColor(1, 1, 1, item._hoverA)
                        iHl:SetAlpha(hlA)
                    end)
                    item:SetScript("OnLeave", function()
                        iLbl:SetTextColor(tDimR, tDimG, tDimB, item._baseA)
                        iHl:SetAlpha(0)
                    end)
                    local typeKey = t.key
                    item:SetScript("OnClick", function()
                        dropMenu:Hide()
                        local nb = mod.AddBlock(dropMenu._barId, typeKey)
                        HardRefresh()
                        if nb then
                            -- A Currency or broker block lands unusable until its
                            -- currency or plugin is picked, so aim at that picker: it
                            -- pulses until filled in, instead of the one-shot
                            -- section glow.
                            local navKey = "block:" .. nb.id
                            if typeKey == "currency" or typeKey == "ldb" then
                                navKey = navKey .. ":" .. typeKey
                            end
                            C_Timer.After(0.05, function()
                                if _edbNavigateFn then
                                    _edbNavigateFn(navKey)
                                end
                            end)
                        end
                    end)
                    item._typeKey, item._lbl, item._hl = typeKey, iLbl, iHl
                    dropMenu._rows[#dropMenu._rows + 1] = item
                    mH = mH + ITEM_H
                end
                dropMenu:SetHeight(mH + 4)
                CloseOnOutsideClick(dropMenu)
                _edbMenus.add = dropMenu
            end
            local rowList = dropMenu._rows
            for i = 1, #rowList do
                local item = rowList[i]
                local typeKey = item._typeKey
                -- Types already on this bar render dimmed -- still fully clickable
                -- (duplicates are legal), just an at-a-glance cue for what the bar is
                -- missing. Re-applied on every open, so this never goes stale.
                local onBar = false
                for bi = 1, #conf.blocks do
                    if conf.blocks[bi].type == typeKey then
                        onBar = true
                        break
                    end
                end
                -- Spacers are the one type meant to repeat on a bar, so the
                -- already-on-bar dim cue never applies to them. Broker blocks
                -- repeat for the same reason: one per plugin is the normal setup,
                -- so a second one is not the accident the dim cue warns about.
                if typeKey == "spacer" or typeKey == "ldb" then
                    onBar = false
                end
                local baseA = tDimA
                local hoverA = 1
                if onBar then
                    baseA = 0.28
                    hoverA = 0.55
                end
                item._baseA, item._hoverA = baseA, hoverA
                item._lbl:SetTextColor(tDimR, tDimG, tDimB, baseA)
                item._hl:SetAlpha(0)
            end
            dropMenu._barId = conf.id
            dropMenu._anchor = addBtn
            dropMenu:ClearAllPoints()
            dropMenu:SetPoint("TOPRIGHT", addBtn, "BOTTOMRIGHT", 0, -2)
            dropMenu:SetScript("OnUpdate", dropMenu._closeOutside)
            dropMenu:Show()
        end
        addBtn:SetScript("OnClick", ToggleAddMenu)
        addBtn:SetScript("OnEnter", function()
            addLbl:SetTextColor(EGc.r, EGc.g, EGc.b, 1)
            addBrd:Show()
            CludesUI.ShowWidgetTooltip(addBtn, L("Add a block to this bar"))
        end)
        addBtn:SetScript("OnLeave", function()
            addLbl:SetTextColor(EGc.r, EGc.g, EGc.b, 0.7)
            addBrd:Hide()
            CludesUI.HideWidgetTooltip()
        end)
        addBtn:HookScript("OnHide", function()
            if _edbMenus.add then
                _edbMenus.add:Hide()
            end
        end)

        if vertical then
            -- The strip lives in the docked popout; the header only carries
            -- a pointer to it.
            local vh = CludesUI.MakeFont(heading, 12, nil, 1, 1, 1, 0.4)
            vh:SetPoint("TOP", heading, "TOP", 0, fy - 2)
            vh:SetJustifyH("CENTER")
            vh:SetText(L("Vertical bar: the interactive preview is docked beside this window."))
            fy = fy - 24
        else
            fy = fy - stripThick - 8
            -- Interaction hint directly below the preview (CDM preview pattern).
            local ph = CludesUI.MakeFont(heading, 11, nil, 0.62, 0.62, 0.62, 0.9)
            ph:SetPoint("TOP", strip, "BOTTOM", 0, -8)
            ph:SetWidth(stripLen - 20)
            ph:SetJustifyH("CENTER")
            ph:SetWordWrap(true)
            ph:SetText(L("Drag to Reorder. Click to Scroll. Right Click to Remove."))
            fy = fy - 16 - 10
        end

        return math.abs(fy)
    end

    ---------------------------------------------------------------------------
    --  Page body
    ---------------------------------------------------------------------------
    local function BuildDataBarsPage(page, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local posY = yOffset
        local _, hgt, heading
        local row

        hostFrame._showRowDivider = true
        hostFrame._edbClickTargets = {}

        -------------------------------------------------------------------
        --  Click navigation (preview segments -> block sections). The map
        --  lives on parent._edbClickTargets; the header overlays call the
        --  current build's closure through the _edbNavigateFn upvalue so a
        --  cached/restored header never fires a stale closure.
        -------------------------------------------------------------------
        -- Second arg holdWhile keeps the glow pulsing while the setting still
        -- needs filling in (a 0.75s flash is gone before they finish reading).
        local PlaySettingGlow = CludesUI.MakeSettingGlow({ color = CludesUI.CLUDES_GREEN })

        local function GlowTargetOf(m)
            if not m.slotSide then
                return m.target
            end
            local regionFrame
            if m.slotSide == "left" then
                regionFrame = m.target._leftRegion
            else
                regionFrame = m.target._rightRegion
            end
            return regionFrame or m.target
        end

        local function NavigateToSetting(key)
            local targets = hostFrame._edbClickTargets
            if not targets then
                return
            end
            local m = targets[key]
            if not m or not m.section or not m.target then
                return
            end
            local _, _, _, _, headerY = m.section:GetPoint(1)
            if not headerY then
                return
            end
            CludesUI.SmoothScrollTo(math.max(0, math.abs(headerY) - 40))
            local glowTarget = GlowTargetOf(m)
            if m.holdWhile then
                _edbHeldGlowKey, _edbHeldGlowY = key, headerY
            end
            -- A target of the page pool that is dressed again for another row by
            -- then belongs to a newer build (which re-arms its own glow).
            local gen = Pool.Gen(glowTarget)
            C_Timer.After(0.15, function()
                if Pool.Gen(glowTarget) ~= gen or Pool.IsIdle(glowTarget) then
                    return
                end
                PlaySettingGlow(glowTarget, m.holdWhile)
            end)
        end

        -- A held glow belongs to the SETTING, not to the navigation that first
        -- showed it. A page rebuild -- reordering a block, switching bars,
        -- adding or removing one -- destroys the row it was parented to, which
        -- released the pulse for good even though the setting was still empty.
        -- Re-attach it to the freshly built row.
        --
        -- Scope: rebuilds only. Reopening the panel takes SelectPage's warm
        -- path (CludesUI.lua), which re-shows the cached wrapper without
        -- running the page builder, so nothing calls this -- the pulse stays
        -- dead until the next rebuild. Covering that means driving this from
        -- onPageCacheRestore too, the way _edbStripRelayout is.
        local function RearmHeldGlow()
            if not _edbHeldGlowKey then
                return
            end
            local targets = hostFrame._edbClickTargets
            local m = targets and targets[_edbHeldGlowKey]
            -- Absent from this build (another bar is selected): keep the key so
            -- coming back re-arms. Only a satisfied predicate retires it.
            if not (m and m.section and m.target and m.holdWhile) then
                return
            end
            if not m.holdWhile() then
                _edbHeldGlowKey = nil
                return
            end
            -- Sections are laid out in bar order, so reordering blocks moves
            -- this row: re-glowing in place would pulse off-screen. Follow it
            -- only when it actually moved -- yanking the view on an unrelated
            -- rebuild (a Fill toggle, a theme change) would be worse.
            local _, _, _, _, headerY = m.section:GetPoint(1)
            if headerY ~= _edbHeldGlowY then
                NavigateToSetting(_edbHeldGlowKey)
                return
            end
            PlaySettingGlow(GlowTargetOf(m), m.holdWhile)
        end

        -- Never retarget the live header's click handler from a hidden
        -- global-search pre-build: its targets belong to an off-screen
        -- wrapper. (SetContentHeader itself is stubbed out during pre-builds
        -- by the search module, so that call needs no guard.)
        if not CludesUI._prebuilding then
            _edbNavigateFn = NavigateToSetting
        end

        local p = Profile()
        if not p then
            return math.abs(posY)
        end
        local conf = SelectedBar()

        -- Bar selected -> editor chrome; zero bars -> no header, the body
        -- below renders the full starting screen.
        if conf then
            CludesUI:SetContentHeader(_edbHeaderBuilder)
        else
            CludesUI:ClearContentHeader()
        end

        -------------------------------------------------------------------
        --  Zero bars: template-card empty state
        -------------------------------------------------------------------
        if not conf then
            local PADC = CludesUI.CONTENT_PAD
            if not PADC then
                PADC = 10
            end
            local hostW = hostFrame:GetWidth() - PADC * 2
            local gap = 12
            local cw = floor((hostW - gap) / 2)
            local ch = 76
            local hostH = 40 + ch * 2 + gap + 10
            -- Explicit size + single TOPLEFT anchor (search contract); the
            -- host doubles as a search pseudo-section.
            local host = CreateFrame("Frame", nil, hostFrame)
            Pix.Size(host, hostW, hostH)
            Pix.Point(host, "TOPLEFT", hostFrame, "TOPLEFT", PADC, posY)
            host._isSectionHeader = true
            host._sectionName = "Create New DataBar"
            local hint = CludesUI.MakeFont(host, 13, nil, 1, 1, 1, 0.55)
            hint:SetPoint("TOPLEFT", host, "TOPLEFT", 4, -8)
            hint:SetText(L("Create your first DataBar from a starter template, or start empty."))
            for i = 1, 4 do
                local col = (i - 1) % 2
                local rowI = floor((i - 1) / 2)
                MakeTemplateCard(host, col * (cw + gap), -40 - rowI * (ch + gap), cw, ch, TEMPLATE_CARDS[i])
            end
            posY = posY - hostH - 10
            return math.abs(posY)
        end

        local barId = conf.id
        local vertical = conf.orientation == "V"
        local theme = conf.theme
        if not theme then
            theme =
                { style = "cui", cuiAlpha = 0.5, modernColor = { r = 0.067, g = 0.067, b = 0.067, a = 0.95 } }
            conf.theme = theme
        end

        local function Apply()
            mod.ApplyBar(barId)
        end

        -- Sizing mode: centered segmented two-button toggle (the shared
        -- segmented control), in its OWN space between
        -- the preview header and BAR SETTINGS with 15px above and below.
        -- BAR-level -- it owns every block's width: Auto Sized = content +
        -- per-side gaps with one Fill Remaining block; Even Split = equal
        -- segments. Switching rebuilds the page (block sections gain/lose
        -- their sizing rows).
        posY = posY - 15
        do
            local BTN_W, BTN_H = 150, 26
            local seg = CludesUI.BuildSegmentedControl({
                parent = hostFrame,
                keys = { "auto", "even" },
                labels = { auto = "Auto Sized", even = "Even Split" },
                width = BTN_W * 2,
                square = true,
                height = BTN_H,
                getChecked = function(key)
                    return mod.BarSizingMode(conf) == key
                end,
                onToggle = function(key)
                    if mod.BarSizingMode(conf) == key then
                        return
                    end
                    conf.sizingMode = key
                    mod.ApplyBar(barId)
                    HardRefresh()
                end,
            })
            seg:SetPoint("TOP", hostFrame, "TOP", 0, posY)
            posY = posY - (BTN_H + 15)
        end

        -------------------------------------------------------------------
        --  BAR SETTINGS
        -------------------------------------------------------------------
        heading, hgt = W:SectionHeader(hostFrame, "BAR SETTINGS", posY)
        posY = posY - hgt
        -- The Move in Unlock Mode button on the selected bar's first section:
        -- the key is read at the click, so it highlights the bar the selector shows.
        CludesUI.BuildSectionUnlockJump(heading, {
            key = function()
                local c = SelectedBar()
                return c and ("EDB_" .. c.id) or nil
            end,
        })

        -- Visibility | Visibility Options (renaming lives in the selector's
        -- inline edit; "Never" visibility fully disables the bar's work).
        local visRow
        visRow, hgt = CludesUI.BuildVisibilityRow(
            W,
            hostFrame,
            posY,
            {
                getStore = function()
                    return mod.GetBar(barId)
                end,
                legacyKey = "visibility",
                caps = mod.EDB_VIS_CAPS,
                onChanged = function()
                    -- "Never" tears the bar down entirely (and un-Never
                    -- rebuilds), so run the full apply, not just the vis pass.
                    mod.ApplyBar(barId)
                    mod.UpdateAllBarVisibility()
                end,
                onOptionChanged = function()
                    mod.UpdateAllBarVisibility()
                end,
            },
            -- Hide Border moved up from the section's old trailing half-row into the slot
            -- the Visibility Options dropdown left behind, so neither row is half empty.
            {
                type = "toggle",
                text = "Hide Border",
                tooltip = "Hide the 1-pixel outline around the bar.",
                getValue = function()
                    return conf.hideBorder == true
                end,
                setValue = function(val)
                    conf.hideBorder = val and true or false
                    mod.ApplyTheme(barId)
                    RefreshPreviewTheme()
                end,
            }
        )
        posY = posY - hgt
        -- Inline cog on the Visibility dropdown: Bar Strata. Lives here rather
        -- than as a row of its own because it answers the same question the
        -- visibility controls do -- when and where this bar shows up -- and it
        -- is a set-once setting that should not cost a row.
        do
            local leftRgn = visRow._leftRegion
            CludesUI.BuildInlineCog(leftRgn, {
                title = "Bar Layer",
                rows = {
                    {
                        type = "dropdown",
                        label = "Bar Strata",
                        tooltip = "Screen layer this bar renders on. Raise it to draw over other frames, lower it to sit behind them.",
                        values = CludesUI.FRAME_STRATA_LABELS,
                        order = CludesUI.FRAME_STRATA_ORDER_BASE,
                        get = function()
                            local c = mod.GetBar(barId)
                            return (c and c.barStrata) or "MEDIUM"
                        end,
                        set = function(val)
                            local c = mod.GetBar(barId)
                            if not c then
                                return
                            end
                            c.barStrata = val
                            mod.ApplyBar(barId)
                        end,
                    },
                },
            })
        end

        -- Orientation | Theme (inline cog = CludesUI Backdrop Dim)
        local themeRow
        themeRow, hgt = W:DualRow(hostFrame, posY, {
            type = "segmented",
            text = "Orientation",
            tooltip = "Horizontal bars lay blocks left to right; vertical bars stack them top to bottom.",
            values = { H = "Horizontal", V = "Vertical" },
            order = { "H", "V" },
            getValue = function()
                if conf.orientation == "V" then
                    return "V"
                end
                return "H"
            end,
            setValue = function(val)
                conf.orientation = val
                -- An edge snap that no longer matches the orientation
                -- remaps to the nearest valid edge.
                local e = conf.snapEdge
                if val == "V" and (e == "bottom" or e == "top") then
                    conf.snapEdge = "left"
                elseif val == "H" and (e == "left" or e == "right") then
                    conf.snapEdge = "bottom"
                end
                mod.ApplyBar(barId)
                HardRefresh()
            end,
        }, {
            type = "segmented",
            text = "Background Style",
            tooltip = "CludesUI matches the window-skin shell; Modern is a flat color.",
            values = { cui = "CludesUI", modern = "Modern" },
            order = { "cui", "modern" },
            getValue = function()
                if theme.style == "modern" then
                    return "modern"
                end
                return "cui"
            end,
            setValue = function(val)
                theme.style = val
                -- Selecting Modern starts Bar Opacity at 95.
                if val == "modern" then
                    local c = theme.modernColor
                    if not c then
                        c = { r = 0.067, g = 0.067, b = 0.067 }
                        theme.modernColor = c
                    end
                    c.a = 0.95
                end
                mod.ApplyTheme(barId)
                HardRefresh()
            end,
        })
        posY = posY - hgt
        CludesUI.BuildInlineCog(themeRow._rightRegion, {
            title = "CludesUI Background",
            disabled = function()
                return theme.style ~= "cui"
            end,
            disabledTooltip = "the CludesUI theme",
            rows = {
                {
                    type = "slider",
                    label = "Backdrop Dim",
                    min = 0,
                    max = 100,
                    step = 1,
                    get = function()
                        local a = theme.cuiAlpha
                        if a == nil then
                            a = 0.5
                        end
                        return floor(a * 100 + 0.5)
                    end,
                    set = function(val)
                        theme.cuiAlpha = val / 100
                        mod.ApplyTheme(barId)
                        RefreshPreviewTheme()
                    end,
                },
            },
        })

        -- Bar Texture: 1:1 with the Unit Frames picker -- same built-in texture set
        -- plus SharedMedia statusbars appended live on every build (late-registered
        -- packs always appear), with texture preview backgrounds on the menu items.
        local function BuildBarTexDropdown()
            CludesUI.AppendSharedMediaTextures(
                mod.barTextureNames or {},
                mod.barTextureOrder or {},
                nil,
                mod.barTextures
            )
            local btValues, btOrder = {}, {}
            local texNames = mod.barTextureNames or {}
            local texOrder = mod.barTextureOrder or {}
            for _, key in ipairs(texOrder) do
                if key ~= "---" then
                    btValues[key] = texNames[key] or key
                    btOrder[#btOrder + 1] = key
                end
            end
            local texLookup = mod.barTextures or {}
            btValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    return texLookup[key]
                end,
            }
            return btValues, btOrder
        end
        local btValues, btOrder = BuildBarTexDropdown()
        local barTexCfg = {
            type = "dropdown",
            text = "Bar Texture",
            tooltip = "Background texture for this bar, tinted by the bar's color and opacity.",
            -- Textures are a Modern-style feature; the CludesUI style
            -- always renders its own untextured art stack.
            disabled = function()
                return (theme and theme.style) ~= "modern"
            end,
            disabledTooltip = "Modern Background Style is required.",
            values = btValues,
            order = btOrder,
            getValue = function()
                return conf.barTexture or "none"
            end,
            setValue = function(val)
                conf.barTexture = val
                if mod.ApplyTheme then
                    mod.ApplyTheme(barId)
                end
                Apply()
            end,
        }
        local scaleCfg = {
            type = "slider",
            text = "Text Scale",
            min = 50,
            max = 150,
            step = 5,
            tooltip = "Scales every text element on this bar.",
            getValue = function()
                local val = conf.fontScale
                if val == nil then
                    val = 100
                end
                return val
            end,
            setValue = function(val)
                conf.fontScale = val
                Apply()
            end,
        }
        -- One bar-wide switch (was a per-block toggle).
        local hoverBlocksCfg = {
            type = "toggle",
            text = "Hover Highlight Blocks",
            tooltip = "Shows a faint white wash over each block on mouseover.",
            getValue = function()
                return conf.hoverHighlight == true
            end,
            setValue = function(val)
                conf.hoverHighlight = val and true or false
                Apply()
            end,
        }
        -- Bar Opacity drives BOTH styles: the Modern flat color's alpha or
        -- the CludesUI shell's backdrop dim, whichever is active.
        local opacityRow
        opacityRow, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Bar Opacity",
            min = 0,
            max = 100,
            step = 1,
            tooltip = "Opacity of the bar's background; the swatch picks the Modern color.",
            getValue = function()
                if theme.style == "modern" then
                    local c = theme.modernColor
                    local a = c and c.a
                    if a == nil then
                        a = 0.95
                    end
                    return floor(a * 100 + 0.5)
                end
                local a = theme.cuiOpacity
                if a == nil then
                    a = 1
                end
                return floor(a * 100 + 0.5)
            end,
            setValue = function(val)
                if theme.style == "modern" then
                    local c = theme.modernColor
                    if not c then
                        c = { r = 0.067, g = 0.067, b = 0.067 }
                        theme.modernColor = c
                    end
                    c.a = val / 100
                else
                    theme.cuiOpacity = val / 100
                end
                mod.ApplyTheme(barId)
                RefreshPreviewTheme()
            end,
        }, barTexCfg)
        posY = posY - hgt
        if not CludesUI._prebuilding then
            -- Inline Modern-background swatch: always present, disabled
            -- (house pattern) while the CludesUI style is active. Style
            -- changes HardRefresh, so the state re-evaluates on switch.
            local rgn = opacityRow._leftRegion
            local colorSwatch = CludesUI.BuildColorSwatch(rgn, opacityRow:GetFrameLevel() + 3, function()
                local c = theme.modernColor
                if not c then
                    return 0.067, 0.067, 0.067
                end
                local r = c.r
                if r == nil then
                    r = 0.067
                end
                local g = c.g
                if g == nil then
                    g = 0.067
                end
                local b2 = c.b
                if b2 == nil then
                    b2 = 0.067
                end
                return r, g, b2
            end, function(r, g, b2)
                local c = theme.modernColor
                if not c then
                    c = { a = 0.95 }
                    theme.modernColor = c
                end
                c.r = r
                c.g = g
                c.b = b2
                mod.ApplyTheme(barId)
                RefreshPreviewTheme()
            end, false, 20)
            Pix.Point(colorSwatch, "RIGHT", rgn._control, "LEFT", -8, 0)
            if theme.style ~= "modern" then
                colorSwatch:SetAlpha(0.3)
                SwatchCover(colorSwatch, "the Modern background style", 5)
            end
        end

        -- Full Screen Width/Height | Snap to Screen Edge, then Width +
        -- Height together on the next row. The sizing labels are PURELY a
        -- front-end relabel: cfg.length is always the along-axis extent
        -- and cfg.thickness the cross-axis, unchanged -- the labels flip
        -- with orientation so users read screen terms.
        local lenLabel, fullLabel, thickLabel
        if vertical then
            lenLabel, fullLabel, thickLabel = "Height", "Full Screen Height", "Width"
        else
            lenLabel, fullLabel, thickLabel = "Width", "Full Screen Width", "Height"
        end
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = fullLabel,
            tooltip = "Sizes the bar to the full screen extent along its axis.",
            getValue = function()
                return conf.lengthMode == "full"
            end,
            setValue = function(val)
                if val then
                    conf.lengthMode = "full"
                else
                    conf.lengthMode = "custom"
                end
                mod.ApplyBar(barId)
                if _edbStripRelayout then
                    _edbStripRelayout()
                end
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Snap to Screen Edge",
            tooltip = "Pins the bar flush against a screen edge; moving the bar in layout mode sets this back to None.",
            values = { none = "None", bottom = "Bottom", top = "Top", left = "Left", right = "Right" },
            order = { "none", "bottom", "top", "left", "right" },
            itemDisabled = function(val)
                if vertical then
                    return val == "bottom" or val == "top"
                end
                return val == "left" or val == "right"
            end,
            itemDisabledTooltip = function(val)
                if val == "bottom" or val == "top" then
                    return "Not available for vertical bars"
                end
                return "Not available for horizontal bars"
            end,
            getValue = function()
                local val = conf.snapEdge
                if val == nil then
                    val = "none"
                end
                return val
            end,
            setValue = function(val)
                conf.snapEdge = val
                mod.ApplyBar(barId)
            end,
        })
        posY = posY - hgt

        -- Width | Height (length + thickness in screen terms)
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = lenLabel,
            min = 100,
            max = 3000,
            step = 10,
            tooltip = "Size of the bar along its block axis in pixels.",
            disabled = function()
                return conf.lengthMode == "full"
            end,
            disabledTooltip = CludesUI.Lf("Disabled while %1$s is enabled.", CludesUI.L(fullLabel)),
            rawTooltip = true,
            getValue = function()
                local val = conf.length
                if val == nil then
                    val = 400
                end
                return val
            end,
            setValue = function(val)
                conf.length = val
                mod.ApplyBar(barId)
                if _edbStripRelayout then
                    _edbStripRelayout()
                end
            end,
        }, {
            type = "slider",
            text = thickLabel,
            min = 16,
            max = 3000,
            step = 1,
            tooltip = "Size of the bar across its block axis in pixels.",
            getValue = function()
                local val = conf.thickness
                if val == nil then
                    val = 30
                end
                return val
            end,
            setValue = function(val)
                conf.thickness = val
                Apply()
            end,
        })
        posY = posY - hgt

        _, hgt = W:DualRow(hostFrame, posY, scaleCfg, hoverBlocksCfg)
        posY = posY - hgt

        -- Bar deletion lives in the selector dropdown's inline delete -- no
        -- body row. Visibility moved to the top of the section; rename =
        -- selector inline edit.

        -------------------------------------------------------------------
        --  One section per block
        -------------------------------------------------------------------
        local blocks = conf.blocks
        if CludesUI.IS_FOREVER then
            -- Hidden blocks get no section (see BlockHidden); the rest keep
            -- bar order.
            local isShown = {}
            for i = 1, #blocks do
                if not BlockHidden(blocks[i]) then
                    isShown[#isShown + 1] = blocks[i]
                end
            end
            blocks = isShown
        end
        local blockHoverRegions = {} -- { id, rgn } Width % control regions
        for i = 1, #blocks do
            local b = blocks[i]
            local blockId = b.id
            local s = b.settings
            -- Row accessors over s: a key read (or its default) and written.
            local function SFieldThen(key)
                return function(v)
                    s[key] = v
                    Apply()
                end
            end
            local function SFieldOr(key, default)
                return function()
                    return s[key] or default
                end
            end
            if not s then
                s = {}
                b.settings = s
            end
            local isSpacer = b.type == "spacer"
            local typeLabel = TYPE_LABEL[b.type]
            if not typeLabel then
                typeLabel = b.type
            end

            local secHdr
            secHdr, hgt = W:SectionHeader(hostFrame, string.upper(CludesUI.L(typeLabel)), posY)
            posY = posY - hgt

            -- Bar-level sizing owns all widths now (Auto Sized / Even Split toggle at
            -- the top of Bar Settings). Auto mode: every block except the single Fill
            -- Remaining block gets a per-side gaps row, and every block gets the fill
            -- designation toggle. Even Split: no per-block sizing rows at all.
            local barMode = mod.BarSizingMode(conf)
            local isFillBlock = barMode == "auto" and mod.EnsureFillBlock(conf) == blockId
            local sizingRow
            if barMode == "auto" and not isFillBlock then
                local gapLLabel, gapRLabel
                if vertical then
                    gapLLabel, gapRLabel = "Top Gap", "Bottom Gap"
                else
                    gapLLabel, gapRLabel = "Left Gap", "Right Gap"
                end
                sizingRow, hgt = W:DualRow(hostFrame, posY, {
                    type = "slider",
                    text = gapLLabel,
                    min = 0,
                    max = 200,
                    step = 1,
                    tooltip = "Empty space reserved on this side of the block's content.",
                    getValue = function()
                        local l = mod.ContentGapsOf(b)
                        return l
                    end,
                    setValue = function(val)
                        b.contentGapL = val
                        Apply()
                        if _edbStripRelayout then
                            _edbStripRelayout()
                        end
                    end,
                }, {
                    type = "slider",
                    text = gapRLabel,
                    min = 0,
                    max = 200,
                    step = 1,
                    tooltip = "Empty space reserved on this side of the block's content.",
                    getValue = function()
                        local _, r = mod.ContentGapsOf(b)
                        return r
                    end,
                    setValue = function(val)
                        b.contentGapR = val
                        Apply()
                        if _edbStripRelayout then
                            _edbStripRelayout()
                        end
                    end,
                })
                posY = posY - hgt
            end
            if barMode == "auto" then
                local fillRow
                fillRow, hgt = W:DualRow(hostFrame, posY, {
                    type = "toggle",
                    text = "Set as 'Fill Remaining Space' Block",
                    tooltip = "Stretches this block to absorb the space the sized blocks leave over; exactly one block per bar fills.",
                    disabled = function()
                        return mod.EnsureFillBlock(conf) == blockId
                    end,
                    disabledTooltip = "This block is already the 'Fill Remaining Space' block. Check another block to move the role.",
                    rawTooltip = true,
                    getValue = function()
                        return mod.EnsureFillBlock(conf) == blockId
                    end,
                    setValue = function(val)
                        if val then
                            mod.SetFillBlock(barId, blockId)
                            HardRefresh()
                        end
                    end,
                }, {
                    type = "toggle",
                    text = "Force Centered",
                    tooltip = "Pins this block's content to the exact center of the bar; blocks before it pack left, blocks after pack right. Combined with Fill Remaining, the block also absorbs the leftover space around the center.",
                    getValue = function()
                        return conf.centerBlockId == blockId
                    end,
                    setValue = function(val)
                        if val then
                            mod.SetCenterBlock(barId, blockId)
                        elseif conf.centerBlockId == blockId then
                            mod.SetCenterBlock(barId, nil)
                        end
                        HardRefresh()
                    end,
                })
                posY = posY - hgt
                if not sizingRow then
                    sizingRow = fillRow
                end
            end

            -- The sizing rows drive the hover highlight (auto mode only;
            -- Even Split blocks light up from segment hover alone).
            if sizingRow then
                blockHoverRegions[#blockHoverRegions + 1] = {
                    id = blockId,
                    rgn = sizingRow,
                }
            end

            hostFrame._edbClickTargets["block:" .. blockId] =
                { section = secHdr, target = sizingRow or secHdr }

            -- Text Align + X/Y offsets (skipped for spacers)
            if not isSpacer then
                local alignValues
                if vertical then
                    alignValues = { LEFT = "Top", CENTER = "Center", RIGHT = "Bottom" }
                else
                    alignValues = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
                end
                -- Text Align (X/Y offsets live in the inline cog) | Content
                -- Scale (icons + texts scale together as a group). Micro menu:
                -- alignment is meaningless (the button strip lays itself out), so its
                -- slot hosts an Enable Text toggle instead -- a view over the existing
                -- hideSocialText key (default enabled). The Text Position cog still
                -- moves the counter texts.
                local alignLeftCfg
                if b.type == "micromenu" then
                    alignLeftCfg = {
                        type = "toggle",
                        text = "Enable Text",
                        tooltip = "Shows the online friend and guild counters.",
                        getValue = function()
                            return s.hideSocialText ~= true
                        end,
                        setValue = function(val)
                            s.hideSocialText = not val
                            Apply()
                        end,
                    }
                else
                    alignLeftCfg = {
                        type = "dropdown",
                        text = "Text Align",
                        tooltip = "Where the block's content sits inside its slot.",
                        values = alignValues,
                        order = { "LEFT", "CENTER", "RIGHT" },
                        getValue = function()
                            local a = b.align
                            if a == nil then
                                a = "CENTER"
                            end
                            return a
                        end,
                        setValue = function(val)
                            b.align = val
                            -- XP / Rep: a picked alignment also places the bar's
                            -- label (unset keeps the label left, as it always was).
                            if b.type == "xprep" then
                                b.labelAlign = val
                            end
                            Apply()
                        end,
                    }
                end
                local alignRow
                alignRow, hgt = W:DualRow(hostFrame, posY, alignLeftCfg, {
                    type = "slider",
                    text = "Content Scale",
                    min = 50,
                    max = 200,
                    step = 5,
                    tooltip = "Scales this block's content as a group inside its slot.",
                    getValue = function()
                        local val = b.scale
                        if val == nil then
                            val = 100
                        end
                        return val
                    end,
                    setValue = function(val)
                        b.scale = val
                        Apply()
                    end,
                })
                posY = posY - hgt
                do
                    -- Text Position cog: offsets the TEXT only (factories
                    -- inject these into every text anchor; icons stay put).
                    CludesUI.BuildInlineCog(alignRow._leftRegion, {
                        title = "Text Position",
                        rows = {
                            {
                                type = "slider",
                                label = "X Offset",
                                min = -50,
                                max = 50,
                                step = 1,
                                get = function()
                                    local val = b.textXOff
                                    if val == nil then
                                        val = 0
                                    end
                                    return val
                                end,
                                set = function(val)
                                    b.textXOff = val
                                    if mod.ReflowBlocks then
                                        mod.ReflowBlocks(barId)
                                    end
                                end,
                            },
                            {
                                type = "slider",
                                label = "Y Offset",
                                min = -50,
                                max = 50,
                                step = 1,
                                get = function()
                                    local val = b.textYOff
                                    if val == nil then
                                        val = 0
                                    end
                                    return val
                                end,
                                set = function(val)
                                    b.textYOff = val
                                    if mod.ReflowBlocks then
                                        mod.ReflowBlocks(barId)
                                    end
                                end,
                            },
                        },
                    })

                    -- Content Position cog (next to Content Scale): offsets
                    -- the WHOLE block content group, text included.
                    CludesUI.BuildInlineCog(alignRow._rightRegion, {
                        title = "Content Position",
                        rows = {
                            {
                                type = "slider",
                                label = "X Offset",
                                min = -50,
                                max = 50,
                                step = 1,
                                get = function()
                                    local val = b.xOff
                                    if val == nil then
                                        val = 0
                                    end
                                    return val
                                end,
                                set = function(val)
                                    b.xOff = val
                                    Apply()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Y Offset",
                                min = -50,
                                max = 50,
                                step = 1,
                                get = function()
                                    local val = b.yOff
                                    if val == nil then
                                        val = 0
                                    end
                                    return val
                                end,
                                set = function(val)
                                    b.yOff = val
                                    Apply()
                                end,
                            },
                        },
                    })
                end
            end

            -- Block Background (inline swatch) | Text Color (Custom/Class/
            -- Accent swatches: text tint; icon-bearing blocks tint icons via the
            -- separate Icon Color row below, other icon users -- micro menu, social --
            -- still ride this color). (Hover Highlight is a bar-level setting in BAR
            -- SETTINGS now.) Colors apply during block re-render, so force a full
            -- reflow (a plain apply skips blocks whose width did not change).
            local function ApplyBlockColor()
                if mod.ReflowBlocks then
                    mod.ReflowBlocks(barId)
                end
            end
            local colorCfg = {
                type = "multiSwatch",
                text = "Text Color",
                swatches = {
                    {
                        tooltip = "Custom Color",
                        hasAlpha = false,
                        getValue = function()
                            local c = b.color
                            if c then
                                return c.r or 1, c.g or 1, c.b or 1
                            end
                            return 1, 1, 1
                        end,
                        setValue = function(r, g, bl)
                            b.color = { r = r, g = g, b = bl }
                            ApplyBlockColor()
                        end,
                        onClick = function(self)
                            if b.useClassColor or b.useAccentColor then
                                b.useClassColor = nil
                                b.useAccentColor = nil
                                ApplyBlockColor()
                                CludesUI:RefreshPage()
                                return
                            end
                            if self._eabOrigClick then
                                self._eabOrigClick(self)
                            end
                        end,
                        refreshAlpha = function()
                            return (b.useClassColor or b.useAccentColor) and 0.3 or 1
                        end,
                    },
                    {
                        tooltip = "Class Colored",
                        hasAlpha = false,
                        getValue = function()
                            local _, class = UnitClass("player")
                            local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                            if cc then
                                return cc.r, cc.g, cc.b
                            end
                            return 1, 1, 1
                        end,
                        setValue = function() end,
                        onClick = function()
                            b.useClassColor = true
                            b.useAccentColor = nil
                            ApplyBlockColor()
                            CludesUI:RefreshPage()
                        end,
                        refreshAlpha = function()
                            return b.useClassColor and 1 or 0.3
                        end,
                    },
                    {
                        tooltip = "Accent Color",
                        hasAlpha = false,
                        getValue = function()
                            return mod.GetAccent()
                        end,
                        setValue = function() end,
                        onClick = function()
                            b.useAccentColor = true
                            b.useClassColor = nil
                            ApplyBlockColor()
                            CludesUI:RefreshPage()
                        end,
                        refreshAlpha = function()
                            return b.useAccentColor and 1 or 0.3
                        end,
                    },
                },
            }
            -- A 4th Text Color swatch for a block-specific colour mode stored
            -- as b[flag]: picking it clears Class/Accent, picking Class or
            -- Accent clears it, and Custom takes the selection back from it.
            -- opts.off() says when Custom is NOT selected because of the mode
            -- (default: the flag is set); opts.toCustom() runs as Custom takes
            -- the selection back; opts.on() lights the 4th swatch (default:
            -- the flag is set).
            local function ModeSwatch(flag, tip, getValue, opts)
                opts = opts or {}
                local function Flag()
                    return b[flag]
                end
                local off, on = opts.off or Flag, opts.on or Flag
                local sw = colorCfg.swatches
                local customClick, customAlpha = sw[1].onClick, sw[1].refreshAlpha
                sw[1].onClick = function(self)
                    if off() then
                        b[flag] = nil
                        if opts.toCustom then
                            opts.toCustom()
                        end
                        ApplyBlockColor()
                        CludesUI:RefreshPage()
                        return
                    end
                    customClick(self)
                end
                sw[1].refreshAlpha = function()
                    if off() then
                        return 0.3
                    end
                    return customAlpha()
                end
                for i = 2, 3 do
                    local click = sw[i].onClick
                    sw[i].onClick = function(...)
                        b[flag] = nil
                        return click(...)
                    end
                end
                sw[4] = {
                    tooltip = tip,
                    hasAlpha = false,
                    getValue = getValue,
                    setValue = function() end,
                    onClick = function()
                        b[flag] = true
                        b.useClassColor = nil
                        b.useAccentColor = nil
                        ApplyBlockColor()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return on() and 1 or 0.3
                    end,
                }
            end
            -- Gold: "Coin Colored" -- white numbers, coin-tinted g/s/c
            -- letters; the forced default (see the factory's coinForced
            -- one-shot).
            if b.type == "gold" then
                -- E2AC7A -- matches DENOMINATIONS' gold letter (user-set).
                ModeSwatch("useCoinColor", "Coin Colored", function()
                    return 0.886, 0.675, 0.478
                end)
            end
            -- Crests: "Crest Colors" -- each amount tinted with its own tier
            -- colour. Unlike Gold's coin mode this is the nothing-stored
            -- DEFAULT, resolved by ns.CrestColorMode rather than a forced
            -- write, so Custom has to SEED b.color to take the selection
            -- (same shape as the Icon Color row's Custom/Default pair below).
            if b.type == "crests" then
                -- Myth gold: the top crest, and the most recognizable of the
                -- five as a single preview swatch.
                ModeSwatch("useCrestColor", "Crest Colors", function()
                    return 1, 0.82, 0
                end, {
                    off = function()
                        return mod.CrestColorMode(b) or b.useClassColor or b.useAccentColor
                    end,
                    toCustom = function()
                        b.useClassColor = nil
                        b.useAccentColor = nil
                        if b.color == nil then
                            b.color = { r = 1, g = 1, b = 1 }
                        end
                    end,
                    on = function()
                        return mod.CrestColorMode(b)
                    end,
                })
            end
            -- State-driven: Durability gets the red->green gradient its
            -- icon's Dynamic mode uses; the location blocks the zone's PvP
            -- ruleset colour; Item Level the crest colour of the upgrade
            -- track the gear sits in (Adventurer green through Myth gold).
            -- Never the default: nothing stored stays custom/white.
            local DYNAMIC_TEXT_BLOCKS = {
                durability = "Dynamic",
                location = "Reactive",
                coords = "Reactive",
                ilvl = "Band",
            }
            if DYNAMIC_TEXT_BLOCKS[b.type] then
                ModeSwatch("useDynamicColor", DYNAMIC_TEXT_BLOCKS[b.type], function()
                    return mod.BlockTextDynamic(b.type)
                end)
            end
            local bgRow
            local bgRightCfg
            if isSpacer then
                bgRightCfg = { type = "label", text = "" }
            else
                bgRightCfg = colorCfg
            end
            bgRow, hgt = W:DualRow(hostFrame, posY, {
                type = "toggle",
                text = "Block Background",
                tooltip = "Tints this block's slot with its own color.",
                getValue = function()
                    return b.bg ~= nil
                end,
                setValue = function(val)
                    if val then
                        if not b.bg then
                            b.bg = { r = 0, g = 0, b = 0, a = 0.5 }
                        end
                    else
                        b.bg = nil
                    end
                    Apply()
                    CludesUI:RefreshPage()
                end,
            }, bgRightCfg)
            posY = posY - hgt
            if not CludesUI._prebuilding then
                local rgn = bgRow._leftRegion
                local ctrl = rgn._control
                local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                    rgn,
                    bgRow:GetFrameLevel() + 3,
                    function()
                        local c = b.bg
                        if not c then
                            return 0, 0, 0, 0.5
                        end
                        local r = c.r
                        if r == nil then
                            r = 0
                        end
                        local g = c.g
                        if g == nil then
                            g = 0
                        end
                        local b2 = c.b
                        if b2 == nil then
                            b2 = 0
                        end
                        local a = c.a
                        if a == nil then
                            a = 0.5
                        end
                        return r, g, b2, a
                    end,
                    function(r, g, b2, a)
                        b.bg = { r = r, g = g, b = b2, a = a }
                        Apply()
                    end,
                    true,
                    20
                )
                Pix.Point(colorSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                GatedSwatch(colorSwatch, updateSwatch, "Enable Block Background", 10, function()
                    return b.bg
                end)
            end

            -- Toggle row for a setting whose default is ON: nil has to read as
            -- true, which the `== true` of MkToggle (further down) cannot
            -- express. Declared here because the icon row below needs it too.
            local function MkToggleOn(labelText, key, tipText)
                return {
                    type = "toggle",
                    text = labelText,
                    tooltip = tipText,
                    getValue = function()
                        return s[key] ~= false
                    end,
                    setValue = function(val)
                        s[key] = val and true or false
                        Apply()
                    end,
                }
            end

            -- Icon Color (icon-bearing blocks only): the same three swatches
            -- as Text Color plus a "Default" swatch. Nothing stored resolves
            -- to the block's themed default (ns.BlockIconDefault).
            -- Deliberately absent: crests. Its icons are inline |T|t escapes
            -- inside one FontString, which cannot be vertex-tinted (see the
            -- note by ICON_DEFAULTS in Blocks\Shared.lua).
            -- WoW Forever has no Mythic+ teleports, so the travel block builds
            -- no Show M+ Portals toggle there: its Icon Color row is handed to
            -- the type rows instead, where it pairs with Left Click.
            local travelIconCfg
            local ICON_COLOR_BLOCKS = {
                durability = true,
                gold = true,
                travel = true,
                spec = true,
                profession = true,
                profession2 = true,
                currency = true,
                greatvault = true,
                audio = true,
                location = true,
                coords = true,
                ilvl = true,
                bags = true,
                ldb = true,
                supplies = true,
            }
            if ICON_COLOR_BLOCKS[b.type] then
                local function IconFlagsOff()
                    return not b.useIconClassColor and not b.useIconAccentColor and not b.useIconDefaultColor
                end
                local iconColorCfg = {
                    type = "multiSwatch",
                    text = "Icon Color",
                    swatches = {
                        {
                            tooltip = "Custom Color",
                            hasAlpha = false,
                            getValue = function()
                                local c = b.iconColor
                                if c then
                                    return c.r or 1, c.g or 1, c.b or 1
                                end
                                return mod.BlockIconDefault(b.type, s)
                            end,
                            setValue = function(r, g, bl)
                                b.iconColor = { r = r, g = g, b = bl }
                                ApplyBlockColor()
                            end,
                            onClick = function(self)
                                -- Switching from Class/Accent/Default: SEED the custom color
                                -- (from the themed default) so custom actually lights on this
                                -- click -- unlike the Text Color row, flag-less with nothing
                                -- stored means DEFAULT here, so clearing flags alone landed
                                -- the selection on Default until the picker stored a color.
                                -- Second click opens the picker as usual.
                                if not IconFlagsOff() or b.iconColor == nil then
                                    b.useIconClassColor = nil
                                    b.useIconAccentColor = nil
                                    b.useIconDefaultColor = nil
                                    if b.iconColor == nil then
                                        local dr, dg2, db2 = mod.BlockIconDefault(b.type, s)
                                        b.iconColor = { r = dr, g = dg2, b = db2 }
                                    end
                                    ApplyBlockColor()
                                    CludesUI:RefreshPage()
                                    return
                                end
                                if self._eabOrigClick then
                                    self._eabOrigClick(self)
                                end
                            end,
                            refreshAlpha = function()
                                return (IconFlagsOff() and b.iconColor ~= nil) and 1 or 0.3
                            end,
                        },
                        {
                            tooltip = "Class Colored",
                            hasAlpha = false,
                            getValue = function()
                                local _, class = UnitClass("player")
                                local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                                if cc then
                                    return cc.r, cc.g, cc.b
                                end
                                return 1, 1, 1
                            end,
                            setValue = function() end,
                            onClick = function()
                                b.useIconClassColor = true
                                b.useIconAccentColor = nil
                                b.useIconDefaultColor = nil
                                ApplyBlockColor()
                                CludesUI:RefreshPage()
                            end,
                            refreshAlpha = function()
                                return b.useIconClassColor and 1 or 0.3
                            end,
                        },
                        {
                            tooltip = "Accent Color",
                            hasAlpha = false,
                            getValue = function()
                                return mod.GetAccent()
                            end,
                            setValue = function() end,
                            onClick = function()
                                b.useIconAccentColor = true
                                b.useIconClassColor = nil
                                b.useIconDefaultColor = nil
                                ApplyBlockColor()
                                CludesUI:RefreshPage()
                            end,
                            refreshAlpha = function()
                                return b.useIconAccentColor and 1 or 0.3
                            end,
                        },
                        {
                            tooltip = "Default",
                            hasAlpha = false,
                            getValue = function()
                                return mod.BlockIconDefault(b.type, s)
                            end,
                            setValue = function() end,
                            onClick = function()
                                -- Mode switch only -- the stored custom color stays
                                -- stashed for the Custom swatch.
                                b.useIconDefaultColor = true
                                b.useIconClassColor = nil
                                b.useIconAccentColor = nil
                                ApplyBlockColor()
                                CludesUI:RefreshPage()
                            end,
                            refreshAlpha = function()
                                return (b.useIconDefaultColor or (IconFlagsOff() and b.iconColor == nil))
                                        and 1
                                    or 0.3
                            end,
                        },
                    },
                }
                if b.type == "durability" then
                    -- Durability's default tint is DYNAMIC (red -> green by
                    -- lowest durability); same mode semantics, clearer name.
                    iconColorCfg.swatches[4].tooltip = "Dynamic"
                end
                if b.type == "spec" and s.iconStyle ~= "wow" then
                    -- Spec defaults to CLASS color: no Default swatch; the Class swatch
                    -- reads as selected in the nothing-stored state, and a legacy
                    -- stored Default-mode flag (from when the swatch existed) lights it
                    -- too -- both render class color.
                    iconColorCfg.swatches[4] = nil
                    iconColorCfg.swatches[2].refreshAlpha = function()
                        if b.useIconClassColor or b.useIconDefaultColor then
                            return 1
                        end
                        return (IconFlagsOff() and b.iconColor == nil) and 1 or 0.3
                    end
                end
                if (b.type == "profession" or b.type == "profession2") and s.iconStyle ~= "wow" then
                    -- Professions default to ACCENT (matches the skill-bar
                    -- fill), so they carry no Default swatch -- and Accent
                    -- reads as selected in the nothing-stored state too.
                    iconColorCfg.swatches[4] = nil
                    iconColorCfg.swatches[3].refreshAlpha = function()
                        if b.useIconAccentColor then
                            return 1
                        end
                        return (IconFlagsOff() and b.iconColor == nil) and 1 or 0.3
                    end
                end
                -- Gold / travel: a type row rides the Icon Color row's
                -- otherwise-empty right slot instead of trailing alone below.
                local iconRowRight = { type = "label", text = "" }
                if b.type == "travel" and not CludesUI.IS_FOREVER then
                    -- Default ON (nil = shown), so this can't use MkToggle's
                    -- `== true` read.
                    iconRowRight = {
                        type = "toggle",
                        text = "Show M+ Portals",
                        tooltip = "Show the Mythic+ teleport section in the tooltip. Ready rows are click-to-teleport.",
                        getValue = function()
                            return s.clickableTeleports ~= false
                        end,
                        setValue = function(val)
                            s.clickableTeleports = val and true or false
                            Apply()
                        end,
                    }
                end
                if b.type == "audio" then
                    -- Default ON (nil = shown), so this can't use MkToggle's
                    -- `== true` read.
                    iconRowRight = {
                        type = "toggle",
                        text = "Show Icon",
                        tooltip = "Shows the audio icon next to the volume bar.",
                        getValue = function()
                            return s.showIcon ~= false
                        end,
                        setValue = function(val)
                            s.showIcon = val and true or false
                            Apply()
                        end,
                    }
                end
                if b.type == "profession" or b.type == "profession2" then
                    -- Default ON (nil = shown), so this can't use MkToggle's
                    -- `== true` read.
                    iconRowRight = {
                        type = "toggle",
                        text = "Show Icon",
                        tooltip = "Shows the profession icons next to the text.",
                        getValue = function()
                            return s.showIcon ~= false
                        end,
                        setValue = function(val)
                            s.showIcon = val and true or false
                            Apply()
                        end,
                    }
                end
                if b.type == "spec" then
                    -- Default ON (nil = shown), so this can't use MkToggle's
                    -- `== true` read.
                    iconRowRight = {
                        type = "toggle",
                        text = "Show Icon",
                        tooltip = "Shows the spec icon next to the text.",
                        getValue = function()
                            return s.showIcon ~= false
                        end,
                        setValue = function(val)
                            s.showIcon = val and true or false
                            Apply()
                        end,
                    }
                end
                if b.type == "supplies" then
                    iconRowRight = MkToggleOn("Show Icon", "showIcon")
                elseif b.type == "location" then
                    iconRowRight =
                        MkToggleOn("Show Icon", "showIcon", "Shows the map pin next to the zone name.")
                elseif b.type == "coords" then
                    iconRowRight =
                        MkToggleOn("Show Icon", "showIcon", "Shows the marker icon next to the coordinates.")
                elseif b.type == "bags" then
                    iconRowRight =
                        MkToggleOn("Show Icon", "showIcon", "Shows the bag icon next to the slot count.")
                end
                if b.type == "durability" then
                    iconRowRight = {
                        type = "toggle",
                        text = "Show Icon",
                        tooltip = "Shows the icon next to the durability readout.",
                        getValue = function()
                            return s.showIcon == true
                        end,
                        setValue = function(val)
                            s.showIcon = val and true or false
                            Apply()
                        end,
                    }
                end
                if b.type == "ilvl" then
                    -- The icon is one of four prefix modes, so the choice
                    -- rides the Icon Color row rather than a toggle.
                    iconRowRight = {
                        type = "dropdown",
                        text = "Prefix",
                        tooltip = "What sits in front of the number. Icon shows the character icon; the color swatches on the left tint it.",
                        values = {
                            none = "None",
                            short = "ILVL",
                            long = "Item Level",
                            icon = "Icon",
                        },
                        order = { "none", "short", "long", "icon" },
                        getValue = function()
                            local p = s.prefix
                            if p == nil then
                                p = "short"
                            end
                            return p
                        end,
                        setValue = SFieldThen("prefix"),
                    }
                end
                if b.type == "gold" then
                    iconRowRight = {
                        type = "toggle",
                        text = "Show Silver and Copper",
                        tooltip = "Shows silver and copper, not just gold.",
                        getValue = function()
                            return s.showSmall == true
                        end,
                        setValue = function(val)
                            s.showSmall = val and true or false
                            Apply()
                        end,
                    }
                end
                if b.type == "travel" and CludesUI.IS_FOREVER then
                    travelIconCfg = iconColorCfg
                else
                    _, hgt = W:DualRow(hostFrame, posY, iconColorCfg, iconRowRight)
                    posY = posY - hgt
                end
            end

            -- Type-specific rows (sequential DualRow fill; odd tail gets a
            -- blank label in the remaining slot)
            local function MkToggle(labelText, key, tipText)
                return {
                    type = "toggle",
                    text = labelText,
                    tooltip = tipText,
                    getValue = function()
                        return s[key] == true
                    end,
                    setValue = function(val)
                        s[key] = val and true or false
                        Apply()
                    end,
                }
            end

            local typeRows = {}
            -- Travel: its three click dropdowns, set by the row loop below.
            local travelClickDD
            if b.type == "audio" then
                typeRows = {
                    {
                        type = "dropdown",
                        text = "Audio Channel",
                        tooltip = "Which audio channel the block's volume bar adjusts.",
                        values = {
                            master = "Master",
                            sfx = "Sound Effects",
                            music = "Music",
                            ambience = "Ambience",
                            dialog = "Dialog",
                        },
                        order = { "master", "sfx", "music", "ambience", "dialog" },
                        getValue = SFieldOr("channel", "master"),
                        setValue = SFieldThen("channel"),
                    },
                }
            elseif b.type == "clock" then
                -- The two time toggles show the EFFECTIVE mode: untouched,
                -- the clock follows the game's Time Manager CVars (same as
                -- the minimap clock); toggling stores a per-block override.
                typeRows = {
                    {
                        type = "toggle",
                        text = "Local Time",
                        tooltip = "Local computer time instead of server time.",
                        getValue = function()
                            if s.localTime == nil then
                                return GetCVar("timeMgrUseLocalTime") == "1"
                            end
                            return s.localTime == true
                        end,
                        setValue = function(val)
                            s.localTime = val and true or false
                            Apply()
                        end,
                    },
                    {
                        type = "toggle",
                        text = "24 Hour Clock",
                        tooltip = "Use 24-hour time.",
                        getValue = function()
                            if s.twentyFour == nil then
                                return GetCVar("timeMgrUseMilitaryTime") == "1"
                            end
                            return s.twentyFour == true
                        end,
                        setValue = function(val)
                            s.twentyFour = val and true or false
                            Apply()
                        end,
                    },
                    MkToggle("Mail Alert", "showMail", "Shows an envelope icon when you have unread mail."),
                    MkToggle(
                        "Resting Icon",
                        "showResting",
                        "Shows a rest icon while your character is resting."
                    ),
                }
            elseif b.type == "combat" then
                typeRows = {
                    MkToggle(
                        "Show Only In Combat",
                        "onlyInCombat",
                        "Shows the combat status text only while your character is in combat."
                    ),
                }
            elseif b.type == "ms" then
                typeRows = {
                    {
                        type = "segmented",
                        text = "Latency",
                        tooltip = "Which latency to show: home, world, or both side by side.",
                        values = { home = "Home", world = "World", both = "Both" },
                        order = { "home", "world", "both" },
                        getValue = function()
                            return mod.LatencyMode(s)
                        end,
                        setValue = SFieldThen("latencyMode"),
                    },
                    -- Not MkToggle: the inline icon-color swatches below key
                    -- their disabled state off this toggle, so it has to
                    -- rebuild the page (house pattern for inline controls).
                    {
                        type = "toggle",
                        text = "Show Icon",
                        tooltip = "Shows a house or globe icon marking which latency each value is.",
                        getValue = function()
                            return s.showIcon == true
                        end,
                        setValue = function(val)
                            s.showIcon = val and true or false
                            Apply()
                            CludesUI:RefreshPage()
                        end,
                    },
                }
            elseif b.type == "location" then
                -- Width only reaches the layout when the solver actually reads
                -- this block's measured extent. Even Split hands every block an
                -- equal share, and the Fill Remaining block gets the leftover:
                -- in both the setting would silently do nothing, so say so rather than
                -- shipping a control that lies. EnsureFillBlock, not the raw
                -- cfg.fillBlockId: an unset or stale id heals to the last block, and
                -- reading the field directly would leave the control enabled on a block
                -- that IS the fill -- the very case this guards.
                local function WidthInert()
                    if mod.BarSizingMode(conf) ~= "auto" then
                        return true
                    end
                    return mod.EnsureFillBlock(conf) == blockId
                end
                local INERT_TIP =
                    "This bar sizes its blocks itself, so the width is not this block's to choose."
                typeRows = {
                    {
                        type = "segmented",
                        text = "Width",
                        tooltip = "Automatic follows the zone name. Manual holds the block at a fixed width and clips longer names, so it never shifts the blocks beside it.",
                        values = { auto = "Automatic", manual = "Manual" },
                        order = { "auto", "manual" },
                        disabled = WidthInert,
                        disabledTooltip = INERT_TIP,
                        getValue = function()
                            return mod.LocationWidthMode(s)
                        end,
                        setValue = function(val)
                            s.widthMode = val
                            -- Every switch to Manual re-arms the pulse, whether
                            -- the block is new or was already configured: the
                            -- slider is the control that just took over, so it
                            -- has to announce itself each time.
                            _edbWidthPulse[b] = (val == "manual") or nil
                            Apply()
                            -- The slider's disabled state keys off this value.
                            CludesUI:RefreshPage()
                            -- Deferred so the REBUILT row is the one that lights
                            -- up, not the one this handler is running on.
                            if val == "manual" then
                                C_Timer.After(0, function()
                                    if _edbNavigateFn then
                                        _edbNavigateFn("block:" .. blockId .. ":maxwidth")
                                    end
                                end)
                            end
                        end,
                    },
                    {
                        type = "slider",
                        pixel = true,
                        text = "Max Width",
                        min = 60,
                        max = 400,
                        step = 5,
                        tooltip = "How wide the block stays, whatever the zone is called.",
                        disabled = function()
                            if WidthInert() then
                                return true
                            end
                            return mod.LocationWidthMode(s) ~= "manual"
                        end,
                        -- Two reasons to be disabled, two different sentences:
                        -- a fixed "Manual width is required." would be plainly
                        -- wrong on an Even Split bar.
                        disabledTooltip = function()
                            if WidthInert() then
                                return INERT_TIP
                            end
                            return "Manual width is required."
                        end,
                        getValue = function()
                            local val = s.maxWidth
                            if val == nil then
                                val = mod.LOC_MAX_WIDTH_DEFAULT
                            end
                            return val
                        end,
                        setValue = function(val)
                            s.maxWidth = val
                            -- Touched: the pulse has done its job.
                            _edbWidthPulse[b] = nil
                            Apply()
                        end,
                    },
                    MkToggleOn(
                        "Zone and Subzone",
                        "showSubZone",
                        "Shows the zone and the subzone together instead of the subzone alone."
                    ),
                }
            elseif b.type == "coords" then
                typeRows = {
                    {
                        type = "dropdown",
                        text = "Decimals",
                        tooltip = "How precise the coordinates read. More decimals make the block wider.",
                        values = { [0] = "None", [1] = "One", [2] = "Two" },
                        order = { 0, 1, 2 },
                        getValue = function()
                            local p = s.precision
                            if p == nil then
                                p = 0
                            end
                            return p
                        end,
                        setValue = SFieldThen("precision"),
                    },
                    MkToggleOn(
                        "Hide in Instance",
                        "hideInInstance",
                        "Removes the block from the bar in instanced content, where player coordinates are unavailable."
                    ),
                }
            elseif b.type == "gold" then
                typeRows = {
                    MkToggle("Show Icon", "showIcons", "Shows the coin icon next to the amount."),
                    MkToggle("Show Bag Space", "showBagSpace", "Shows your free bag slots."),
                    -- Off (default) = the letter suffixes; on = coin textures.
                    -- Independent of Coin Colored, which tints those letters.
                    MkToggle(
                        "Coin Icons",
                        "coinIcons",
                        "Uses Blizzard's coin textures instead of the letter suffixes."
                    ),
                    -- Rides the slot next to Coin Icons; the checklist
                    -- dropdown swaps in after the loop (goldTipRow capture).
                    {
                        type = "dropdown",
                        text = "Show Tooltip Data",
                        tooltip = "Which sections the gold tooltip shows.",
                        values = { __placeholder = "..." },
                        order = { "__placeholder" },
                        getValue = function()
                            return "__placeholder"
                        end,
                        setValue = function() end,
                    },
                    MkToggle(
                        "Abbreviate Amount",
                        "abbreviate",
                        "Shows large amounts using K/M suffixes (284,208g becomes 284.2Kg) instead of the full grouped number. The tooltip always shows the exact amount."
                    ),
                    -- Account-wide switch shared with the Bags options (noCapture: Spec
                    -- Overrides never capture an account setting).
                    {
                        type = "toggle",
                        text = "Gold Tracking and History",
                        noCapture = true,
                        tooltip = "Track and display gold amounts from all your characters on hover.",
                        getValue = function()
                            return CludesUI.GetGoldLedger().IsTracking()
                        end,
                        setValue = function(val)
                            CludesUI.GetGoldLedger().SetTracking(val)
                        end,
                    },
                }
                -- Force English Units: only where the effective locale actually
                -- has its own abbreviation algorithm (currently the CJK wan/yi
                -- grouping tables in CludesUI_NumberFormat.lua); every other
                -- locale already gets K/M/B, so the toggle would be a no-op.
                -- Mirrors the Damage Meters options row (CUI_DamageMeters_Options.lua).
                if CludesUI.LocaleHasNumberAbbreviation() then
                    typeRows[#typeRows + 1] = MkToggle(
                        "Force English Units (K/M/B)",
                        "forceEnglishUnits",
                        "Always use K/M/B instead of localized units."
                    )
                end
            elseif b.type == "profession" or b.type == "profession2" then
                typeRows = {
                    {
                        type = "segmented",
                        text = "Text Display",
                        values = { name = "Name and Bar", values = "Values" },
                        order = { "name", "values" },
                        getValue = SFieldOr("textDisplay", "name"),
                        setValue = SFieldThen("textDisplay"),
                    },
                }
            elseif b.type == "xprep" then
                typeRows = {
                    {
                        type = "dropdown",
                        text = "Text Display",
                        values = { off = "Off", values = "Values", percentage = "Percentage" },
                        order = { "off", "values", "percentage" },
                        getValue = function()
                            return mod.GetXPRepTextDisplay(s)
                        end,
                        setValue = SFieldThen("textDisplay"),
                    },
                    {
                        type = "dropdown",
                        text = "Text Format",
                        values = { context = "With Level / Faction", plain = "Value Only" },
                        order = { "context", "plain" },
                        getValue = SFieldOr("textFormat", "context"),
                        setValue = SFieldThen("textFormat"),
                        disabled = function()
                            return mod.GetXPRepTextDisplay(s) == "off"
                        end,
                    },
                    {
                        type = "dropdown",
                        text = "Mode",
                        tooltip = "Automatic shows XP while leveling and reputation at max level.",
                        values = { auto = "Automatic", xp = "Experience", rep = "Reputation" },
                        order = { "auto", "xp", "rep" },
                        getValue = function()
                            local m = s.mode
                            if m == nil then
                                m = "auto"
                            end
                            return m
                        end,
                        setValue = SFieldThen("mode"),
                    },
                }
            elseif b.type == "spec" then
                typeRows = {
                    MkToggle("Show Loadout Name", "showLoadout", "Shows the active talent loadout name."),
                    MkToggle("Uppercase Text", "useUppercase", "Renders the spec text in uppercase."),
                }
            elseif b.type == "travel" then
                local function ChoiceOf(button)
                    return mod.TravelClickChoice(s, button)
                end
                -- Houses arrive asynchronously: the page refresh lists them (the refill below).
                mod.TravelRequestHouseList(function()
                    if CludesUI:GetActiveModule() == "CludesUIDataBars" then
                        CludesUI:RefreshPage()
                    end
                end)
                -- Fills values / order in place: a built dropdown keeps reading these tables.
                local function BuildClickValues(button, values, sequence)
                    wipe(values)
                    wipe(sequence)
                    if button == 3 then
                        values.none = "None"
                        sequence[1] = "none"
                    end
                    values.random = "Random Hearthstone"
                    sequence[#sequence + 1] = "random"
                    local current = ChoiceOf(button)
                    -- A saved house missing from the list (not loaded yet, or sold) stays listed as "Home".
                    local houses = mod.TravelHouseChoices()
                    local curIsHouse = type(current) == "string" and current:find("house:", 1, true) == 1
                    if #houses > 0 or curIsHouse then
                        sequence[#sequence + 1] = "---house"
                        for _, house in ipairs(houses) do
                            values[house.key] = house.name
                            sequence[#sequence + 1] = house.key
                        end
                        if curIsHouse and not values[current] then
                            values[current] = "Home"
                            sequence[#sequence + 1] = current
                        end
                    end
                    local curPlaced = type(current) ~= "number"
                    local groups = {
                        { key = "---travel", ids = mod.TravelExtraIDs, usable = mod.TravelExtraUsable },
                        { key = "---hearth", ids = mod.TravelHearthstoneIDs, usable = mod.TravelIsUsable },
                    }
                    for gi, g in ipairs(groups) do
                        local entries, curInGroup = {}, false
                        if g.ids and g.usable then
                            for _, ident in ipairs(g.ids) do
                                if ident == current then
                                    curInGroup = true
                                end
                                if g.usable(ident) and ident ~= current then
                                    entries[#entries + 1] = ident
                                end
                            end
                        end
                        -- Keep the current pick listed even if it went unowned,
                        -- so the dropdown shows its label instead of a blank.
                        if not curPlaced and (curInGroup or gi == #groups) then
                            entries[#entries + 1] = current
                            curPlaced = true
                        end
                        if #entries > 0 then
                            local nameList = {}
                            for _, ident in ipairs(entries) do
                                nameList[ident] = mod.TravelEntryName(ident) or ("Item " .. ident)
                            end
                            table.sort(entries, function(a, z)
                                return nameList[a] < nameList[z]
                            end)
                            sequence[#sequence + 1] = g.key
                            for _, ident in ipairs(entries) do
                                values[ident] = nameList[ident]
                                sequence[#sequence + 1] = ident
                            end
                        end
                    end
                    return values, sequence
                end
                local CLICK_LABELS = { "Left Click", "Right Click", "Middle Click" }
                local CLICK_KEYS = { "hsChoice", "hsChoiceRight", "hsChoiceMiddle" }
                local CLICK_TIPS = {
                    "Where left-clicking the block takes you.",
                    "Where right-clicking the block takes you.",
                    "Where middle-clicking the block takes you.",
                }
                local TEXT_LABELS = { "Left Click Text", "Right Click Text", "Middle Click Text" }
                local TEXT_KEYS = { "textLeft", "textRight", "textMiddle" }
                local TEXT_VALUES = {
                    location = "Destination",
                    smart = "Cooldown Else Destination",
                    both = "Destination and Cooldown",
                    cooldown = "Cooldown Only",
                    none = "None",
                }
                local TEXT_ORDER = { "location", "smart", "both", "cooldown", "none" }
                typeRows = {}
                local clickVals, clickOrd = {}, {}
                for button = 1, 3 do
                    local vals, ord = BuildClickValues(button, {}, {})
                    clickVals[button], clickOrd[button] = vals, ord
                    typeRows[#typeRows + 1] = {
                        type = "dropdown",
                        text = CLICK_LABELS[button],
                        tooltip = CLICK_TIPS[button],
                        values = vals,
                        order = ord,
                        getValue = function()
                            return ChoiceOf(button)
                        end,
                        setValue = function(val)
                            s[CLICK_KEYS[button]] = val
                            -- Mirrored for old readers/exports of the legacy boolean.
                            if button == 1 then
                                s.randomizeHs = (val == "random")
                            end
                            Apply()
                            CludesUI:RefreshPage()
                        end,
                    }
                    typeRows[#typeRows + 1] = {
                        type = "dropdown",
                        text = TEXT_LABELS[button],
                        tooltip = "What the bar shows for this click.",
                        values = TEXT_VALUES,
                        order = TEXT_ORDER,
                        getValue = function()
                            return mod.TravelClickTextMode(s, button)
                        end,
                        setValue = function(val)
                            s[TEXT_KEYS[button]] = val
                            Apply()
                        end,
                        disabled = function()
                            return ChoiceOf(button) == "none"
                        end,
                        disabledTooltip = "Set this click to something other than None.",
                        rawTooltip = true,
                    }
                end
                -- Last, so each click keeps its choice and text on one row.
                if travelIconCfg then
                    typeRows[#typeRows + 1] = travelIconCfg
                end
                typeRows[#typeRows + 1] = MkToggle(
                    "Show Other Characters",
                    "altHearths",
                    "Lists your other characters' hearthstones in the tooltip, once each has logged in with this on."
                )
                -- A house list that arrived after the build: refill the three menus in place.
                if not CludesUI._prebuilding then
                    travelClickDD = {}
                    local clickDD, listGen = travelClickDD, mod.TravelHouseListGen()
                    CludesUI.RegisterWidgetRefresh(function()
                        local gen = mod.TravelHouseListGen()
                        if gen == listGen then
                            return
                        end
                        listGen = gen
                        for button = 1, 3 do
                            BuildClickValues(button, clickVals[button], clickOrd[button])
                            local dd = clickDD[button]
                            if dd and dd._invalidateMenu then
                                dd._invalidateMenu()
                            end
                        end
                    end)
                end
            elseif b.type == "micromenu" then
                -- Align Content returns here as a type row (its shared-row
                -- slot hosts the Enable Text toggle instead): anchors the
                -- whole icon strip within the block's slot via b.align.
                local mmAlignValues
                if vertical then
                    mmAlignValues = { LEFT = "Top", CENTER = "Center", RIGHT = "Bottom" }
                else
                    mmAlignValues = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
                end
                typeRows = {
                    {
                        type = "dropdown",
                        text = "Align Content",
                        tooltip = "Where the icon strip sits inside its slot.",
                        values = mmAlignValues,
                        order = { "LEFT", "CENTER", "RIGHT" },
                        getValue = function()
                            local a = b.align
                            if a == nil then
                                a = "CENTER"
                            end
                            return a
                        end,
                        setValue = function(val)
                            b.align = val
                            Apply()
                        end,
                    },
                    MkToggle(
                        "Hide Blizzard Micro Menu",
                        "disableBlizzardMicroMenu",
                        "Hides Blizzard's own micro menu while any bar has this on."
                    ),
                    {
                        type = "slider",
                        pixel = true,
                        text = "Menu Spacing",
                        min = 0,
                        max = 16,
                        step = 1,
                        tooltip = "Gap between the main menu button and the icon row.",
                        getValue = function()
                            local val = s.mainMenuSpacing
                            if val == nil then
                                val = 4
                            end
                            return val
                        end,
                        setValue = SFieldThen("mainMenuSpacing"),
                    },
                    {
                        type = "slider",
                        pixel = true,
                        text = "Icon Spacing",
                        min = 0,
                        max = 16,
                        step = 1,
                        tooltip = "Gap between the micro menu icons.",
                        getValue = function()
                            local val = s.iconSpacing
                            if val == nil then
                                val = 2
                            end
                            return val
                        end,
                        setValue = SFieldThen("iconSpacing"),
                    },
                    -- Individual button toggles live in the "Menu Elements"
                    -- checklist dropdown appended after the shared row loop.
                }
            elseif b.type == "supplies" then
                typeRows = {
                    {
                        type = "dropdown",
                        text = "Visible Items",
                        values = { __placeholder = "..." },
                        order = { "__placeholder" },
                        getValue = function()
                            return "__placeholder"
                        end,
                        setValue = function() end,
                    },
                    MkToggle("Show Label", "showLabel"),
                }
            elseif b.type == "currency" then
                local cValues, cOrder = mod.BuildCurrencyList()
                cValues._noLoc = true
                cValues._menuOpts = { searchable = true, itemHeight = 26 }
                cValues[0] = L("Select a currency")
                table.insert(cOrder, 1, 0)
                typeRows = {
                    {
                        type = "dropdown",
                        text = "Currency",
                        tooltip = "Pick any currency your character has discovered.",
                        values = cValues,
                        order = cOrder,
                        getValue = function()
                            local ident = s.currencyId
                            if ident == nil then
                                ident = 0
                            end
                            return ident
                        end,
                        setValue = function(val)
                            if val == 0 then
                                s.currencyId = nil
                            else
                                s.currencyId = val
                            end
                            Apply()
                        end,
                    },
                    MkToggle("Show Icon", "showIcon", "Shows the currency icon next to the amount."),
                    MkToggleOn(
                        "Show Description",
                        "showDescription",
                        "Shows the currency's description text in the tooltip. Turn off for a compact tooltip with just the name and the amount."
                    ),
                }
            elseif b.type == "crests" then
                typeRows = {
                    -- Placeholder: the checklist dropdown swaps into this slot
                    -- after the row loop (crestListRow capture), same idiom as
                    -- the gold tooltip checklist.
                    {
                        type = "dropdown",
                        text = "Crests Shown",
                        tooltip = "Which of the season's crests this block shows.",
                        values = { __placeholder = "..." },
                        order = { "__placeholder" },
                        getValue = function()
                            return "__placeholder"
                        end,
                        setValue = function() end,
                    },
                    {
                        type = "dropdown",
                        text = "Separator",
                        tooltip = "What sits between the crest amounts.",
                        values = {
                            slash = "Slash",
                            line = "Line",
                            dash = "Dash",
                            space = "Space",
                        },
                        order = { "slash", "line", "dash", "space" },
                        getValue = function()
                            local val = s.separator
                            if val == nil then
                                val = "slash"
                            end
                            return val
                        end,
                        setValue = SFieldThen("separator"),
                    },
                    MkToggleOn("Show Icons", "showIcons", "Shows each crest's icon in front of its amount."),
                    -- Not an addition but a SWAP: the leading number stops
                    -- being the spendable amount and becomes the season total.
                    -- The tooltip always shows both, so it stays the reference.
                    MkToggle(
                        "Show Season Progress",
                        "showSeasonProgress",
                        "Replaces the spendable amount with the crests you have earned this season, out of the season cap. The tooltip lists both numbers side by side."
                    ),
                    MkToggle(
                        "Hide Empty Crests",
                        "hideEmpty",
                        "Drops crests you own none of, keeping the block short early in a season. They stay listed in the tooltip."
                    ),
                    {
                        type = "dropdown",
                        text = "Order",
                        tooltip = "Which end of the crest ladder comes first.",
                        values = { asc = "Lowest First", desc = "Highest First" },
                        order = { "asc", "desc" },
                        getValue = function()
                            if s.reverse == true then
                                return "desc"
                            end
                            return "asc"
                        end,
                        setValue = function(val)
                            s.reverse = (val == "desc")
                            Apply()
                        end,
                    },
                }
            elseif b.type == "bags" then
                -- Show Icon rides the Icon Color row's right slot above.
                typeRows = {
                    {
                        type = "dropdown",
                        text = "Display",
                        tooltip = "Which slot count the block shows.",
                        values = {
                            free = "Free",
                            used = "Used",
                            freeTotal = "Free / Total",
                            usedTotal = "Used / Total",
                        },
                        order = { "free", "used", "freeTotal", "usedTotal" },
                        getValue = SFieldOr("value", "free"),
                        setValue = SFieldThen("value"),
                    },
                    MkToggle(
                        "Include Reagent Bag",
                        "reagent",
                        "Counts the reagent bag's slots along with your regular bags."
                    ),
                    -- Inline color swatch built after the row loop (bagsLowRow).
                    {
                        type = "slider",
                        text = "Low Space Warning",
                        min = 0,
                        max = 50,
                        step = 1,
                        tooltip = "Colors the number when free slots drop below this many; the swatch picks the color. Zero turns it off.",
                        getValue = SFieldOr("lowThreshold", 0),
                        setValue = function(val)
                            local wasOn = (s.lowThreshold or 0) > 0
                            s.lowThreshold = val
                            Apply()
                            -- Swatch enable state flips only when crossing zero.
                            if wasOn ~= (val > 0) then
                                CludesUI:RefreshPage()
                            end
                        end,
                    },
                }
            elseif b.type == "mplussummary" then
                typeRows = {
                    MkToggle(
                        "Hide When Empty",
                        "hideWhenEmpty",
                        "Removes the block from the bar until a Mythic+ run has been recorded."
                    ),
                }
            elseif b.type == "timeplayed" then
                typeRows = {
                    MkToggle(
                        "Always Show Total",
                        "alwaysTotal",
                        "Shows this character's total time played instead of the time played at the current level."
                    ),
                }
            elseif b.type == "ilvl" then
                -- Prefix rides the Icon Color row's right slot above.
                typeRows = {
                    {
                        type = "segmented",
                        text = "Item Level",
                        tooltip = "Equipped counts your worn gear. Total also counts upgrades sitting in your bags.",
                        values = { equipped = "Equipped", total = "Total", both = "Both" },
                        order = { "equipped", "total", "both" },
                        getValue = function()
                            local val = s.value
                            if val == nil then
                                val = "equipped"
                            end
                            return val
                        end,
                        setValue = SFieldThen("value"),
                    },
                    {
                        type = "dropdown",
                        text = "Decimals",
                        tooltip = "How many decimal places the number carries.",
                        values = { [0] = "None", [1] = "One", [2] = "Two" },
                        order = { 0, 1, 2 },
                        getValue = function()
                            local p = s.precision
                            if p == nil then
                                p = 0
                            end
                            return p
                        end,
                        setValue = SFieldThen("precision"),
                    },
                }
            elseif b.type == "ldb" then
                -- Rebuilt on every page draw, never cached: plugins register on
                -- their own schedule and some only appear once their addon has
                -- finished loading.
                local lValues, lOrder = mod.BuildLDBList()
                lValues._noLoc = true
                lValues._menuOpts = { searchable = true, itemHeight = 26 }
                lValues[""] = L("Select a plugin")
                table.insert(lOrder, 1, "")
                -- A source whose addon is not loaded this session still has to
                -- read as the current pick: an empty-looking dropdown invites a
                -- change the player never meant to make, and the block itself is
                -- only collapsed, not unconfigured.
                if s.source and not lValues[s.source] then
                    lValues[s.source] = s.source .. " |cff808080(" .. L("not loaded") .. ")|r"
                    lOrder[#lOrder + 1] = s.source
                end
                typeRows = {
                    {
                        type = "dropdown",
                        text = "Plugin",
                        tooltip = "Any LibDataBroker plugin registered right now. One block per plugin -- add the block again for a second one.",
                        values = lValues,
                        order = lOrder,
                        getValue = SFieldOr("source", ""),
                        setValue = function(val)
                            if val == "" then
                                s.source = nil
                            else
                                s.source = val
                            end
                            Apply()
                        end,
                    },
                    MkToggleOn("Show Icon", "showIcon", "Shows the plugin's own icon next to its text."),
                    MkToggleOn(
                        "Show Text",
                        "showText",
                        "Shows the plugin's text. Off leaves an icon-only block that still carries the plugin's tooltip and clicks."
                    ),
                    MkToggle("Show Label", "showLabel", "Prefixes the plugin's own name to its text."),
                    -- Default ON: broker text arrives carrying the plugin's color
                    -- codes, which would otherwise silently beat the Text Color
                    -- row above and the accent hover.
                    MkToggleOn(
                        "Strip Colors",
                        "stripColors",
                        "Removes the color codes the plugin writes into its own text, so this block's Text Color applies. Off keeps the plugin's colors."
                    ),
                    {
                        type = "slider",
                        pixel = true,
                        text = "Max Width",
                        min = 0,
                        max = 400,
                        step = 5,
                        tooltip = "Holds the block at this width and clips longer text, so a plugin whose text keeps changing length never shifts the blocks beside it. Zero sizes the block to whatever the plugin currently says.",
                        getValue = SFieldOr("maxWidth", 0),
                        setValue = function(val)
                            if val == 0 then
                                s.maxWidth = nil
                            else
                                s.maxWidth = val
                            end
                            Apply()
                        end,
                    },
                }
            end

            local msIconRow
            local goldTipRow
            local crestListRow
            local bagsLowRow
            -- Icon Style: a plain dropdown, as on the Damage Meters page. It
            -- fills the next free type-row slot; micromenu puts it beside
            -- Menu Elements instead. The page refresh re-evaluates the
            -- style-dependent swatches.
            local iconStyleCfg
            if mod.BlockHasIconStyle(b.type) then
                iconStyleCfg = {
                    type = "segmented",
                    text = "Icon Style",
                    values = { custom = "Custom", wow = "Blizzard" },
                    order = { "custom", "wow" },
                    -- Item Level shows its icon only as the "Icon" prefix.
                    disabled = function()
                        if b.type == "ilvl" then
                            return s.prefix ~= "icon"
                        end
                        if b.type == "gold" then
                            return s.showIcons == false
                        end
                        return s.showIcon == false
                    end,
                    disabledTooltip = b.type == "ilvl" and "Prefix: Icon" or "Show Icon",
                    getValue = SFieldOr("iconStyle", "custom"),
                    setValue = function(val)
                        s.iconStyle = val
                        Apply()
                        -- Rebuild: the icon color swatches depend on the style.
                        CludesUI:RefreshPage(true)
                    end,
                }
                if b.type ~= "micromenu" then
                    typeRows[#typeRows + 1] = iconStyleCfg
                end
            end
            for k = 1, #typeRows, 2 do
                local rightCfg = typeRows[k + 1]
                if not rightCfg then
                    rightCfg = { type = "label", text = "" }
                end
                row, hgt = W:DualRow(hostFrame, posY, typeRows[k], rightCfg)
                posY = posY - hgt
                -- Travel: the first three rows hold the click dropdowns on their left.
                if travelClickDD and k <= 5 then
                    travelClickDD[(k + 1) / 2] = row._leftRegion._control
                end
                if b.type == "supplies" and k == 1 and not CludesUI._prebuilding then
                    local regionFrame = row._leftRegion
                    if regionFrame._control then
                        regionFrame._control:Hide()
                    end
                    local dropdown, refresh = CludesUI.BuildVisOptsCBDropdown(
                        regionFrame,
                        210,
                        regionFrame:GetFrameLevel() + 2,
                        mod.ClassResourceChoices,
                        function(key)
                            return mod.ClassResourceShown(s, key)
                        end,
                        function(key, value)
                            s.hiddenItems = s.hiddenItems or {}
                            s.hiddenItems[key] = not value
                            Apply()
                        end,
                        nil,
                        10,
                        true
                    )
                    CludesUI.PanelPP.Point(dropdown, "RIGHT", regionFrame, "RIGHT", -20, 0)
                    regionFrame._control = dropdown
                    regionFrame._lastInline = nil
                    if refresh then
                        CludesUI.RegisterWidgetRefresh(refresh)
                    end
                    hostFrame._edbClickTargets["block:" .. blockId .. ":resources"] =
                        { section = secHdr, target = row, slotSide = "left" }
                end
                -- Latency: the Show Icon toggle rides this row's right slot and
                -- carries the inline icon-color swatches built after the loop.
                if b.type == "ms" and k == 1 then
                    msIconRow = row
                end
                -- Gold: Show Tooltip Data rides the Coin Icons row's right slot.
                if b.type == "gold" and k == 3 then
                    goldTipRow = row
                end
                -- Crests: the Crests Shown checklist heads the type rows, so
                -- its placeholder is this row's LEFT slot.
                if b.type == "crests" and k == 1 then
                    crestListRow = row
                end
                -- Bags: Low Space Warning heads the second row (left slot).
                if b.type == "bags" and k == 3 then
                    bagsLowRow = row
                end
                -- Deep-link target for an unconfigured currency block: clicking
                -- its "Select a currency" placeholder on the live bar lands on
                -- the picker itself, not just the section (ns.OpenBlockSettings).
                -- k == 1 IS the Currency dropdown: it heads the currency
                -- typeRows built above. Prepend a row there and retarget here.
                if b.type == "currency" and k == 1 then
                    hostFrame._edbClickTargets["block:" .. blockId .. ":currency"] = {
                        section = secHdr,
                        target = row,
                        slotSide = "left",
                        -- Pulse until the player actually picks one.
                        holdWhile = function()
                            return s.currencyId == nil
                        end,
                    }
                end
                -- Same contract for the location block's Max Width: switching
                -- Width to Manual hands the decision to a slider the player has
                -- never touched, so point at it and hold the pulse until they
                -- do. k == 1 is the Width dropdown; the slider rides its right
                -- slot. Released by the first drag (maxWidth stops being nil).
                -- Same contract for a broker block with no plugin picked:
                -- clicking its placeholder on the live bar lands on the picker,
                -- which pulses until it is filled in.
                if b.type == "ldb" and k == 1 then
                    hostFrame._edbClickTargets["block:" .. blockId .. ":ldb"] = {
                        section = secHdr,
                        target = row,
                        slotSide = "left",
                        holdWhile = function()
                            return s.source == nil
                        end,
                    }
                end
                if b.type == "location" and k == 1 then
                    hostFrame._edbClickTargets["block:" .. blockId .. ":maxwidth"] = {
                        section = secHdr,
                        target = row,
                        slotSide = "right",
                        holdWhile = function()
                            return _edbWidthPulse[b] == true
                        end,
                    }
                end
            end

            -- Latency icon color: the same Custom / Class / Accent trio as the
            -- Text Color row above, inline on Show Icon instead of a row of its
            -- own (the block has one icon set, not a second colorable element).
            -- Stores on the shared per-block icon keys that IconColorOf already
            -- reads, so nothing stored = Custom white, matching the block's
            -- untinted default -- no migration and no new default key.
            if msIconRow and not CludesUI._prebuilding then
                local rgn = msIconRow._rightRegion
                local anchor = rgn._control
                local function IconOn()
                    return s.showIcon == true
                end
                local function FlagsOff()
                    return not b.useIconClassColor and not b.useIconAccentColor and not b.useIconDefaultColor
                end
                local function ClearFlags()
                    b.useIconClassColor = nil
                    b.useIconAccentColor = nil
                    b.useIconDefaultColor = nil
                end

                -- Built right-to-left off the toggle so they read
                -- Custom | Class | Accent left-to-right, like Text Color.
                local specs = {
                    {
                        tip = "Accent Color",
                        get = function()
                            return mod.GetAccent()
                        end,
                        click = function()
                            ClearFlags()
                            b.useIconAccentColor = true
                            ApplyBlockColor()
                            CludesUI:RefreshPage()
                        end,
                        on = function()
                            return b.useIconAccentColor == true
                        end,
                    },
                    {
                        tip = "Class Colored",
                        get = function()
                            local _, class = UnitClass("player")
                            local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                            if cc then
                                return cc.r, cc.g, cc.b
                            end
                            return 1, 1, 1
                        end,
                        click = function()
                            ClearFlags()
                            b.useIconClassColor = true
                            ApplyBlockColor()
                            CludesUI:RefreshPage()
                        end,
                        on = function()
                            return b.useIconClassColor == true
                        end,
                    },
                    {
                        tip = "Custom Color",
                        get = function()
                            local c = b.iconColor
                            if c then
                                return c.r or 1, c.g or 1, c.b or 1
                            end
                            return 1, 1, 1
                        end,
                        set = function(r, g, bl)
                            b.iconColor = { r = r, g = g, b = bl }
                            ApplyBlockColor()
                        end,
                        -- House multiSwatch convention: a click on an inactive
                        -- custom swatch only selects custom; the picker opens on
                        -- the second click, once custom is already active.
                        click = function(self)
                            if not FlagsOff() then
                                ClearFlags()
                                ApplyBlockColor()
                                CludesUI:RefreshPage()
                                return
                            end
                            if self._eabOrigClick then
                                self._eabOrigClick(self)
                            end
                        end,
                        on = FlagsOff,
                    },
                }

                for i = 1, #specs do
                    local sp = specs[i]
                    local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                        rgn,
                        msIconRow:GetFrameLevel() + 3,
                        function()
                            local r, g, bl = sp.get()
                            return r, g, bl, 1
                        end,
                        sp.set or function() end,
                        false,
                        20
                    )
                    colorSwatch._eabOrigClick = colorSwatch:GetScript("OnClick")
                    colorSwatch:SetScript("OnClick", function(self)
                        sp.click(self)
                    end)
                    colorSwatch:HookScript("OnEnter", function()
                        CludesUI.ShowWidgetTooltip(colorSwatch, sp.tip)
                    end)
                    colorSwatch:HookScript("OnLeave", function()
                        CludesUI.HideWidgetTooltip()
                    end)
                    Pix.Point(colorSwatch, "RIGHT", anchor, "LEFT", -8, 0)
                    anchor = colorSwatch

                    -- Blocking overlay while Show Icon is off: the icons are
                    -- not drawn, so their color is not editable.
                    GatedSwatch(colorSwatch, updateSwatch, "Show Icon", 10, IconOn, function()
                        return sp.on() and 1 or 0.3
                    end)
                end
                rgn._lastInline = anchor
            end

            -- Bags low space color: inline on the threshold slider, disabled
            -- (house pattern) while the threshold is zero.
            if bagsLowRow and not CludesUI._prebuilding then
                local rgn = bagsLowRow._leftRegion
                local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                    rgn,
                    bagsLowRow:GetFrameLevel() + 3,
                    function()
                        local d = mod.BAGS_LOW_COLOR
                        local c = s.lowColor
                        if c then
                            return c.r or d[1], c.g or d[2], c.b or d[3]
                        end
                        return d[1], d[2], d[3]
                    end,
                    function(r, g, bl)
                        s.lowColor = { r = r, g = g, b = bl }
                        Apply()
                    end,
                    false,
                    20
                )
                Pix.Point(colorSwatch, "RIGHT", rgn._control, "LEFT", -8, 0)
                GatedSwatch(colorSwatch, updateSwatch, "Low Space Warning", 5, function()
                    return (s.lowThreshold or 0) > 0
                end)
                rgn._lastInline = colorSwatch
            end

            if b.type == "gold" and goldTipRow then
                -- Show Tooltip Data: ONE checklist dropdown for the gold
                -- tooltip's sections (same placeholder-swap idiom as the
                -- micro menu's Menu Elements below). Characters includes the
                -- Warbank row and the Total. All three default ON. The
                -- placeholder itself is the Coin Icons row's right slot.
                local GOLD_TIP_ELEMENTS = {
                    { key = "tipSession", label = "Session" },
                    { key = "tipCharacters", label = "Characters" },
                    { key = "tipToken", label = "WoW Token" },
                }
                if not CludesUI._prebuilding then
                    local rightRgn = goldTipRow._rightRegion
                    if rightRgn._control then
                        rightRgn._control:Hide()
                    end
                    local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                        rightRgn,
                        210,
                        rightRgn:GetFrameLevel() + 2,
                        GOLD_TIP_ELEMENTS,
                        function(k)
                            return s[k] ~= false
                        end,
                        function(k, val)
                            if val then
                                s[k] = true
                            else
                                s[k] = false
                            end
                        end
                    )
                    CludesUI.PanelPP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
                    rightRgn._control = cbDD
                    rightRgn._lastInline = nil
                    if cbDDRefresh then
                        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
                    end
                end
            end

            if b.type == "crests" and crestListRow then
                -- Crests Shown: ONE checklist dropdown for the season's crest
                -- tiers (same placeholder-swap idiom as Menu Elements below).
                -- Labels come from the live currency names so they follow the
                -- client's locale; the tier keys (t1..t5) are what gets stored,
                -- so a season's id swap keeps the selection. All default ON.
                -- Function form: the list re-evaluates on every menu open, so a
                -- crest whose name had not landed yet at page-build time is not
                -- stuck showing its id.
                local function CrestElements()
                    local result = {}
                    for i = 1, #mod.CRESTS do
                        local c = mod.CRESTS[i]
                        local name
                        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                            local details = C_CurrencyInfo.GetCurrencyInfo(c.id)
                            if details then
                                name = details.name
                            end
                        end
                        result[i] = { key = c.key, label = name or ("#" .. c.id) }
                    end
                    return result
                end
                if not CludesUI._prebuilding then
                    local leftRgn = crestListRow._leftRegion
                    if leftRgn._control then
                        leftRgn._control:Hide()
                    end
                    local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                        leftRgn,
                        210,
                        leftRgn:GetFrameLevel() + 2,
                        CrestElements,
                        function(k)
                            return s[k] ~= false
                        end,
                        function(k, val)
                            if val then
                                s[k] = true
                            else
                                s[k] = false
                            end
                            Apply()
                        end
                    )
                    CludesUI.PanelPP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
                    leftRgn._control = cbDD
                    leftRgn._lastInline = nil
                    if cbDDRefresh then
                        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
                    end
                end
            end

            if b.type == "micromenu" then
                -- Menu Elements: ONE checklist dropdown for the individual
                -- micro menu buttons (same placeholder-swap idiom as the
                -- bar's Visibility Options row above).
                local MM_ELEMENTS = {
                    { key = "menu", label = "Menu" },
                    { key = "guild", label = "Guild" },
                    { key = "social", label = "Social" },
                    { key = "char", label = "Character" },
                    { key = "spell", label = "Spellbook" },
                    { key = "ach", label = "Achievements" },
                    { key = "quest", label = "Quests" },
                    { key = "lfg", label = "Group Finder" },
                    { key = "pvp", label = "PvP" },
                    { key = "housing", label = "Housing" },
                    { key = "journal", label = "Adventure Journal" },
                    { key = "pet", label = "Collections" },
                    { key = "shop", label = "Shop" },
                    { key = "help", label = "Help" },
                }
                -- WoW Forever has separate Talents, Professions and Legacy
                -- buttons, right after the Spellbook.
                if CludesUI.IS_FOREVER then
                    for i, el in ipairs(MM_ELEMENTS) do
                        if el.key == "spell" then
                            table.insert(MM_ELEMENTS, i + 1, { key = "talent", label = "Talents" })
                            table.insert(MM_ELEMENTS, i + 2, { key = "profession", label = "Professions" })
                            table.insert(MM_ELEMENTS, i + 3, { key = "legacy", label = "Legacy" })
                            break
                        end
                    end
                end
                local mmRow
                mmRow, hgt = W:DualRow(hostFrame, posY, {
                    type = "dropdown",
                    text = "Menu Elements",
                    tooltip = "Which micro menu buttons this block shows, and their order.",
                    values = { __placeholder = "..." },
                    order = { "__placeholder" },
                    getValue = function()
                        return "__placeholder"
                    end,
                    setValue = function() end,
                }, iconStyleCfg or CludesUI.BlankRowCfg())
                posY = posY - hgt
                do
                    local leftRgn = mmRow._leftRegion
                    if leftRgn._control then
                        leftRgn._control:Hide()
                    end
                    -- Rows follow the block's saved button order.
                    local labels, itemList = {}, {}
                    for _, el in ipairs(MM_ELEMENTS) do
                        labels[el.key] = el.label
                    end
                    for _, key in ipairs(mod.GetMicroMenuOrder(s, {})) do
                        if labels[key] then
                            itemList[#itemList + 1] = { key = key, label = labels[key] }
                        end
                    end
                    local cbDD, cbDDRefresh = CludesUI.BuildReorderCBDropdown(
                        leftRgn,
                        210,
                        leftRgn:GetFrameLevel() + 2,
                        itemList,
                        function(k)
                            return mod.MicroMenuButtonOn(s, k)
                        end,
                        function(k, val)
                            if val then
                                s[k] = true
                            else
                                s[k] = false
                            end
                            Apply()
                        end,
                        {
                            setOrder = function(keyList)
                                mod.SetMicroMenuOrder(s, keyList)
                                Apply()
                            end,
                        }
                    )
                    CludesUI.PanelPP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
                    leftRgn._control = cbDD
                    leftRgn._lastInline = nil
                    if cbDDRefresh then
                        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
                    end
                end

                local notesRow
                notesRow, hgt = W:DualRow(hostFrame, posY, {
                    type = "toggle",
                    text = "Show Guild Notes",
                    tooltip = "Shows each online member's public note after their name in the Guild tooltip.",
                    getValue = function()
                        return s.showGuildNotes == true
                    end,
                    setValue = function(val)
                        s.showGuildNotes = val and true or false
                        Apply()
                        CludesUI:RefreshPage()
                    end,
                }, CludesUI.BlankRowCfg())
                posY = posY - hgt
                if not CludesUI._prebuilding then
                    local rgn = notesRow._leftRegion
                    local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                        rgn,
                        notesRow:GetFrameLevel() + 3,
                        function()
                            local c = s.guildNoteColor
                            if not c then
                                return 0.925, 0.839, 0.447
                            end
                            return c.r or 0.925, c.g or 0.839, c.b or 0.447
                        end,
                        function(r, g, b2)
                            s.guildNoteColor = { r = r, g = g, b = b2 }
                            Apply()
                        end,
                        false,
                        20
                    )
                    Pix.Point(colorSwatch, "RIGHT", rgn._control, "LEFT", -8, 0)
                    rgn._lastInline = colorSwatch
                    GatedSwatch(colorSwatch, updateSwatch, "Show Guild Notes", 10, function()
                        return s.showGuildNotes == true
                    end)
                end
            end

            -- Reordering = drag the segment in the preview strip; removal =
            -- right-click the segment (Remove Block). No body rows for either.
        end

        -- Width % hover highlight: while the cursor is over a block's Width % control
        -- (just that control, not the whole section), wash that block 8 percent white
        -- on BOTH the preview segment and the live bar slot. Poll watcher is parented
        -- to the page wrapper, so it stops (and clears) when the page hides.
        if #blockHoverRegions > 0 and not CludesUI._prebuilding then
            local watcher = CreateFrame("Frame", nil, hostFrame)
            watcher:SetSize(1, 1)
            local acc = 0
            local curHL
            local function SetHL(ident)
                if ident == curHL then
                    return
                end
                curHL = ident
                if _edbSegHighlightFn then
                    _edbSegHighlightFn(ident)
                end
                if mod.SetBlockEditHighlight then
                    if ident then
                        mod.SetBlockEditHighlight(barId, ident)
                    elseif not _edbSegHoverId then
                        -- A segment hover owns the live highlight right now;
                        -- clearing here would kill it 0.1s after OnEnter.
                        mod.SetBlockEditHighlight(nil, nil)
                    end
                end
            end
            watcher:SetScript("OnUpdate", function(_, elapsed)
                acc = acc + elapsed
                if acc < 0.1 then
                    return
                end
                acc = 0
                if not hostFrame:GetTop() or not hostFrame:IsMouseOver() then
                    SetHL(nil)
                    return
                end
                -- The preview header (and the vertical popout) float OVER the scrolled
                -- body, and IsMouseOver is a pure rect test that ignores clipping -- a
                -- control scrolled under the preview would highlight while the cursor
                -- is on the strip. Only count the cursor inside the scroll viewport.
                local scrollFrame = CludesUI._scrollFrame
                if scrollFrame and not scrollFrame:IsMouseOver() then
                    SetHL(nil)
                    return
                end
                local hit
                for k = 1, #blockHoverRegions do
                    local hr = blockHoverRegions[k]
                    if hr.rgn and hr.rgn:IsMouseOver() then
                        hit = hr.id
                        break
                    end
                end
                SetHL(hit)
            end)
            watcher:HookScript("OnHide", function()
                SetHL(nil)
            end)
        end

        -- Adding blocks lives in the preview strip's "+" tile only -- no body section.
        W:Spacer(hostFrame, posY, 20)
        posY = posY - 20

        -- Every click target of this build is registered by now. Same settle delay the
        -- navigation paths use, and the same pre-build guard: a hidden search pre-build
        -- would steal the shared glow frame for rows nobody can see.
        if not CludesUI._prebuilding then
            -- A kept page wrapper dressed again by a newer build by then holds
            -- that build's rows, and that build re-arms on its own.
            local gen = Pool.Gen(hostFrame)
            C_Timer.After(0.05, function()
                if Pool.Gen(hostFrame) ~= gen then
                    return
                end
                RearmHeldGlow()
            end)
        end

        return math.abs(posY)
    end

    ---------------------------------------------------------------------------
    --  Deep link from a live block to its own settings row. A block whose
    --  empty state invites a click (the currency picker's placeholder) calls
    --  this so the invitation leads to the control that fulfills it; the
    --  preview strip navigates through _edbNavigateFn directly.
    ---------------------------------------------------------------------------
    function mod.OpenBlockSettings(barId, blockId, settingKey)
        -- The options never open in combat; nor does the scroll below run then.
        if InCombatLockdown() then
            CludesUI.PrintError("Cannot open options during combat.")
            return
        end
        local key = "block:" .. blockId .. ":" .. settingKey
        CludesUI:NavigateToElementSettings("CludesUIDataBars", PAGE_DATABARS, nil, function()
            local p = Profile()
            if p then
                p.selectedBarId = barId
            end
        end)
        -- The click-target map belongs to the page build the call above kicks
        -- off; resolve the scroll target once it has repopulated (same settle
        -- delay NavigateToElementSettings uses for its own section lookup).
        C_Timer.After(0.05, function()
            if _edbNavigateFn then
                _edbNavigateFn(key)
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  The live bar measures its auto-sized blocks in its own layout pass,
    --  which the runtime runs a frame after a change applies, so a strip
    --  solved in the same frame as the change (a new bar, an added block)
    --  holds the extents from before that pass. The runtime reports each
    --  finished pass here, and the strip re-solves while it shows that bar.
    ---------------------------------------------------------------------------
    function mod.OnBarLaidOut(barId)
        local host = _edbPreviewHost
        if barId ~= _edbStripBarId or not (_edbStripRelayout and host and host:IsVisible()) then
            return
        end
        -- A reorder drag (the strip's only OnUpdate) owns the segment
        -- positions until it ends.
        if host:GetScript("OnUpdate") then
            return
        end
        _edbStripRelayout()
    end

    ---------------------------------------------------------------------------
    --  Module registration
    ---------------------------------------------------------------------------
    CludesUI:RegisterModule("CludesUIDataBars", {
        title = "Info Bar",
        description = "User-created info bars: clock, gold, XP, micro menu and more.",
        pages = { PAGE_DATABARS },
        buildPage = function(page, hostFrame, yOffset)
            return BuildDataBarsPage(page, hostFrame, yOffset)
        end,
        getHeaderBuilder = function(page)
            if page == PAGE_DATABARS then
                return _edbHeaderBuilder
            end
            return nil
        end,
        onPageCacheRestore = function(page)
            -- Bars can be resized/width-matched via unlock mode between
            -- visits; re-solve the restored preview from the live cfg.
            if page == PAGE_DATABARS and _edbStripRelayout then
                _edbStripRelayout()
            end
        end,
        -- Reset CUI Module Settings' question names the one bar this reset touches.
        resetMessage = function()
            local p = mod.GetProfile()
            local conf = p and ((p.selectedBarId and mod.GetBar(p.selectedBarId)) or (p.bars and p.bars[1]))
            if not (conf and conf.name) then
                return nil
            end
            return CludesUI.Lf(
                "Are you sure you want to reset the data bar selected on the Data Bars page (%1$s) to its default look? Its blocks are kept. This will reload your UI.",
                conf.name
            )
        end,
        onReset = function()
            -- Resets the SELECTED bar's appearance/behavior to defaults;
            -- keeps its id, name and blocks. Never wipes the bar list.
            -- (Reset CUI Module Settings confirms and reloads for us.)
            local p = mod.GetProfile()
            if not p then
                return
            end
            local conf = nil
            if p.selectedBarId then
                conf = mod.GetBar(p.selectedBarId)
            end
            if not conf then
                conf = p.bars[1]
            end
            if not conf then
                return
            end
            conf.orientation = "H"
            conf.lengthMode = "custom"
            conf.length = 400
            conf.thickness = 30
            conf.fontScale = 100
            conf.theme =
                { style = "cui", cuiAlpha = 0.5, modernColor = { r = 0.067, g = 0.067, b = 0.067, a = 0.95 } }
            conf.hideBorder = nil
            conf.visibility = "always"
            conf.visibilityModes = nil
            conf.visibilityMatch = nil
            -- VIS_OPT_KEYS, not VIS_OPT_ITEMS: the counter-lane keys have no row in the
            -- legacy item list, and a reset that skipped them would leave a bar hidden.
            for _, k in ipairs(CludesUI.VIS_OPT_KEYS) do
                conf[k] = nil
            end
            conf.savedPos = nil
            mod.ApplyBar(conf.id)
            mod.UpdateAllBarVisibility()
            CludesUI:InvalidatePageCache()
        end,
    })

    ---------------------------------------------------------------------------
    --  Slash command  /cdb  opens CludesUI to the DataBars module
    ---------------------------------------------------------------------------
    SLASH_CLUDESDATABARS1 = "/cdb"
    SlashCmdList.CLUDESDATABARS = function()
        if InCombatLockdown and InCombatLockdown() then
            print("Cannot open options in combat")
            return
        end
        CludesUI:ShowModule("CludesUIDataBars")
    end
end)
