if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
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
local mod = CUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not mod then return end -- module disabled: no options page

local PAGE_DATABARS = "Info Bar"

CUI.AtOptionsLogin(function()
    local Pix = CUI.PP
    local Loc = CUI.L
    local Lf = CUI.Lf
    local format = string.format
    local floor = math.floor
    -- Page reuse (CludesUI_FramePool.lua): a frame made under a page pool
    -- host comes from the pool and is dressed again by every later build; under
    -- any other parent it is a plain new frame.
    local Pool = CUI._Pool
    local CreateFrame = Pool.CreateFrame

    -- A colour swatch that only means something while another setting is on
    -- gets a cover over it, `level` above, that takes the mouse and names
    -- that setting in its tooltip.
    local function SwatchCover(swatch, gateName, level)
        local cover = CreateFrame("Frame", nil, swatch)
        cover:SetAllPoints()
        cover:SetFrameLevel(swatch:GetFrameLevel() + level)
        cover:EnableMouse(true)
        cover:SetScript(
            "OnEnter",
            function() CUI.ShowWidgetTooltip(swatch, CUI.DisabledTooltip(gateName)) end
        )
        cover:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        return cover
    end

    -- The shell of the header's kept menus (bar, add block, segment): a
    -- hidden, screen-clamped panel over the options window, in the
    -- dropdown's background and border.
    local function MenuShell(width)
        local DropStyle = CUI.DD_STYLE
        local menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(300)
        menu:SetClampedToScreen(true)
        if width then menu:SetWidth(width) end
        menu:Hide()
        local backdrop = menu:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(DropStyle.BG_R, DropStyle.BG_G, DropStyle.BG_B, DropStyle.BG_HA)
        CUI.MakeRoundedBorder(menu, 1, 1, 1, DropStyle.BRD_A, backdrop, nil, true)
        return menu
    end

    -- A menu opened from a button (menu._anchor) closes on a left click
    -- outside both: each open runs menu._closeOutside as its OnUpdate, and
    -- hiding clears it.
    local function CloseOnOutsideClick(menu)
        menu._closeOutside = function(frame)
            if
                not frame:IsMouseOver()
                and not frame._anchor:IsMouseOver()
                and IsMouseButtonDown("LeftButton")
            then
                frame:Hide()
            end
        end
        menu:HookScript("OnHide", function(m) m:SetScript("OnUpdate", nil) end)
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
        CUI.RegisterWidgetRefresh(function()
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
    for _, kind in ipairs(mod.BLOCK_TYPES) do
        TYPE_LABEL[kind.key] = kind.label
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
    local function BlockHidden(block) return not mod.BlockFactories[block.type] end

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
    local function Profile() return mod.GetProfile() end

    -- Selected bar, validated (falls back to the first bar).
    local function SelectedBar()
        local profile = Profile()
        if not profile then return nil end
        local barList = profile.bars
        if #barList == 0 then return nil end
        if profile.selectedBarId then
            local bar = mod.GetBar(profile.selectedBarId)
            if bar then return bar end
        end
        profile.selectedBarId = barList[1].id
        return barList[1]
    end

    local function ResolvedBarLength(rowConf)
        if rowConf.lengthMode == "full" then
            if rowConf.orientation == "V" then return UIParent:GetHeight() end
            return UIParent:GetWidth()
        end
        if rowConf.length then return rowConf.length end
        return 400
    end

    -- Structural change: rebuild the content header AND the page body. The
    -- page build sets the header itself (zero bars = NO content header at
    -- all: the page falls back to the full-body starting screen, template
    -- cards, same as first open), so one forced refresh builds both.
    local function FullRefresh() CUI:RefreshPage(true) end

    -- Header-only change (template card strip open/close): the header is
    -- built again in place (under page reuse, on its kept root).
    local function HeaderOnly()
        if SelectedBar() then
            CUI:SetContentHeader(_edbHeaderBuilder)
        else
            CUI:ClearContentHeader()
        end
    end

    -- Live theme feedback for the preview strip (swatch drag / dim slider).
    local function PaintPreviewTheme()
        local rowConf = SelectedBar()
        if _edbPreviewHost and _edbPreviewHost:IsShown() and rowConf then
            mod.MakePreviewBackdrop(_edbPreviewHost, rowConf.theme, not rowConf.hideBorder)
        end
    end

    ---------------------------------------------------------------------------
    --  Shared popup flows (header menu + body buttons)
    ---------------------------------------------------------------------------
    local function PromptRenameBar(rowConf)
        local oldName = rowConf.name
        if oldName == nil then oldName = "" end
        CUI:ShowInputPopup({
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
                if newName == "" or newName == oldName then return end
                mod.RenameBar(rowConf.id, newName)
                CUI:InvalidateModulePageCache("CludesUIDataBars")
                FullRefresh()
            end,
        })
    end

    local function PromptDeleteBar(rowConf)
        local delName = rowConf.name
        if delName == nil then delName = "" end
        CUI:ShowConfirmPopup({
            title = "Delete DataBar",
            message = Lf('Are you sure you want to delete "%1$s"?', delName),
            confirmText = "Delete",
            cancelText = "Cancel",
            onConfirm = function()
                mod.DeleteBar(rowConf.id)
                local profile = Profile()
                local barList = mod.BarsInOrder()
                if profile and barList[1] then profile.selectedBarId = barList[1].id end
                CUI:InvalidateModulePageCache("CludesUIDataBars")
                FullRefresh()
                -- The rebuilt page (possibly the zero-bar empty state) can
                -- be shorter than the old scroll offset, which leaves the
                -- viewport past the content = blank page. Always return to
                -- the top after a delete.
                if CUI.SmoothScrollTo then CUI.SmoothScrollTo(0) end
            end,
        })
    end

    local function CreateBarFromTemplate(barKey)
        mod.CreateBar(barKey)
        _cardsExpanded = false
        FullRefresh()
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

    local function MakeTemplateCard(host, posX, cursorY, wid, cardH, def)
        local EGc = CUI.CLUDES_GREEN
        local cardFrame = CreateFrame("Button", nil, host)
        Pix.Size(cardFrame, wid, cardH)
        Pix.Point(cardFrame, "TOPLEFT", host, "TOPLEFT", posX, cursorY)
        cardFrame:SetFrameLevel(host:GetFrameLevel() + 2)

        local cbrd = CUI.MakeRoundedCard(cardFrame, 0.12, 0.50, 2)
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

        local titleFs = CUI.MakeFont(cardFrame, 12, nil, 1, 1, 1, 0.9)
        Pix.Point(titleFs, "TOPLEFT", cIcon, "TOPRIGHT", 12, 1)
        Pix.Point(titleFs, "RIGHT", cardFrame, "RIGHT", -8, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        titleFs:SetText(Loc(def.title))

        local descFs = CUI.MakeFont(cardFrame, 10, nil, 1, 1, 1, 0.35)
        Pix.Point(descFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -4)
        Pix.Point(descFs, "RIGHT", cardFrame, "RIGHT", -8, 0)
        descFs:SetJustifyH("LEFT")
        descFs:SetWordWrap(false)
        descFs:SetText(Loc(def.desc))

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
        cardFrame:SetScript("OnClick", function() CreateBarFromTemplate(def.key) end)
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
        if not (CUI:IsShown()) or CUI._panelCollapsed then return false end
        -- nil = mid-build (page state not stamped yet); only a definite
        -- mismatch blocks, mirroring the TBB popout gate.
        local am = CUI:GetActiveModule()
        local ap = CUI:GetActivePage()
        if am and ap and (am ~= "CludesUIDataBars" or ap ~= PAGE_DATABARS) then return false end
        return true
    end

    local function GetPreviewPopout()
        if _edbPopout then return _edbPopout end
        local popout = CreateFrame("Frame", nil, UIParent)
        popout:SetFrameStrata("FULLSCREEN_DIALOG")
        popout:SetFrameLevel(10)
        popout:SetClampedToScreen(true)
        popout:Hide()
        local backdrop = popout:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0, 0, 0, 0.9)
        local title = CUI.MakeFont(popout, 13, nil, 1, 1, 1, 0.9)
        title:SetPoint("TOP", popout, "TOP", 0, -7)
        title:SetText(Loc("Preview"))
        popout._title = title
        local hintText = CUI.MakeFont(popout, 10, nil, 1, 1, 1, 0.4)
        -- Edge-anchored so the text wraps inside the narrow popout instead
        -- of spilling past its sides (height grows upward from the bottom).
        hintText:SetPoint("BOTTOMLEFT", popout, "BOTTOMLEFT", 8, 7)
        hintText:SetPoint("BOTTOMRIGHT", popout, "BOTTOMRIGHT", -8, 7)
        hintText:SetJustifyH("CENTER")
        hintText:SetText(Loc("Drag to Reorder. Click to Scroll. Right Click to Remove."))
        popout._hint = hintText
        -- Self-heal (runs ONLY while shown = zero cost hidden): hide when
        -- the panel closes or another page fronts, like the TBB popout.
        local acc = 0
        popout:SetScript("OnUpdate", function(self, elapsed)
            acc = acc + elapsed
            if acc < 0.25 then return end
            acc = 0
            if not PreviewPopoutAllowed() then self:Hide() end
        end)
        _edbPopout = popout
        return popout
    end

    -- The popout sits on UIParent beside the panel: it folds away with the panel
    -- and comes back with it while a vertical bar is still the one selected (the
    -- header's own condition for showing it).
    CUI:RegisterOnCollapse(function(enabled)
        if not _edbPopout then return end
        if enabled then
            _edbPopout:Hide()
        elseif _edbPopout._strip and PreviewPopoutAllowed() then
            local rowConf = SelectedBar()
            if rowConf and rowConf.orientation == "V" then _edbPopout:Show() end
        end
    end)

    _edbHeaderBuilder = function(heading, hdrW)
        local PAD = CUI.CONTENT_PAD
        if not PAD then PAD = 10 end
        local DropStyle = CUI.DD_STYLE
        local EGc = CUI.CLUDES_GREEN
        local tDimR = CUI.TEXT_DIM_R
        if tDimR == nil then tDimR = 0.7 end
        local tDimG = CUI.TEXT_DIM_G
        if tDimG == nil then tDimG = 0.7 end
        local tDimB = CUI.TEXT_DIM_B
        if tDimB == nil then tDimB = 0.7 end
        local tDimA = CUI.TEXT_DIM_A
        if tDimA == nil then tDimA = 0.85 end
        local rowY = -8

        local rowConf = SelectedBar()
        _edbPreviewHost = nil
        _edbStripRelayout = nil
        _edbStripBarId = nil

        -----------------------------------------------------------------------
        --  Row 1: bar selector dropdown | + New Bar (centered as a pair)
        -----------------------------------------------------------------------
        local DD_H = 30
        local ddW = 280
        local NEWBTN_W = 110
        local dropdownBtn = CreateFrame("Button", nil, heading)
        Pix.Size(dropdownBtn, ddW, DD_H)
        Pix.Point(dropdownBtn, "TOPLEFT", heading, "TOPLEFT", (hdrW - (ddW + 10 + NEWBTN_W)) / 2, rowY)
        dropdownBtn:SetFrameLevel(heading:GetFrameLevel() + 5)
        local ddBg = dropdownBtn:CreateTexture(nil, "BACKGROUND")
        ddBg:SetAllPoints()
        ddBg:SetColorTexture(DropStyle.BG_R, DropStyle.BG_G, DropStyle.BG_B, DropStyle.BG_A)
        local ddBrd = CUI.MakeRoundedBorder(dropdownBtn, 1, 1, 1, DropStyle.BRD_A, ddBg)
        local dropCaption = CUI.MakeFont(dropdownBtn, 13, nil, 1, 1, 1, DropStyle.TXT_A)
        dropCaption:SetJustifyH("LEFT")
        dropCaption:SetWordWrap(false)
        dropCaption:SetMaxLines(1)
        dropCaption:SetPoint("LEFT", dropdownBtn, "LEFT", 12, 0)
        local arrow = CUI.MakeDropdownArrow(dropdownBtn, 12, CUI.PanelPP)
        dropCaption:SetPoint("RIGHT", arrow, "LEFT", -5, 0)
        if rowConf then
            local nm = rowConf.name
            if nm == nil then nm = "" end
            dropCaption:SetText(nm)
        else
            dropCaption:SetText(Loc("No Info Bar"))
        end

        -- The bar menu is built on its first open and kept across header builds
        -- (_edbMenus.bar), its bar rows pooled by index: each open points it at
        -- this header's selector and re-applies every row to the current bars.
        local function BuildBarMenu()
            local ITEM_H = 26
            local ICON_SZ = 14
            local hlA = DropStyle.ITEM_HL_A
            local selA = DropStyle.ITEM_SEL_A
            local dropMenu = _edbMenus.bar
            if dropMenu then
                if dropMenu:IsShown() then dropMenu:Hide() end
            else
                dropMenu = MenuShell()
                dropMenu._rows = {}

                -- One bar row; its bar and selected state are set per open
                -- (item._bar, item._isSel), and item._rest puts it in its
                -- resting look.
                dropMenu._makeRow = function()
                    local entry = CreateFrame("Button", nil, dropMenu)
                    entry:SetHeight(ITEM_H)
                    entry:SetFrameLevel(dropMenu:GetFrameLevel() + 2)

                    local itemCaption = CUI.MakeFont(entry, 11, nil, tDimR, tDimG, tDimB, tDimA)
                    itemCaption:SetJustifyH("LEFT")
                    itemCaption:SetWordWrap(false)
                    itemCaption:SetMaxLines(1)
                    itemCaption:SetPoint("LEFT", entry, "LEFT", 10, 0)

                    local iHl = entry:CreateTexture(nil, "ARTWORK")
                    iHl:SetAllPoints()
                    iHl:SetColorTexture(1, 1, 1, 1)

                    -- Rename and Delete inline at the right edge (every bar is
                    -- user-made): dim at rest, lit with the row on hover.
                    local delBtn, editBtn
                    local function Rest()
                        delBtn:SetAlpha(0.75)
                        editBtn:SetAlpha(0.75)
                        itemCaption:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        iHl:SetAlpha(entry._isSel and selA or 0)
                    end
                    entry._rest = Rest
                    entry._lbl = itemCaption
                    local function OverAny()
                        return entry:IsMouseOver() or delBtn:IsMouseOver() or editBtn:IsMouseOver()
                    end
                    local function InlineIcon(anchor, relPoint, x, file, tip, act)
                        local button = CreateFrame("Button", nil, entry)
                        button:SetSize(ICON_SZ, ICON_SZ)
                        button:SetPoint("RIGHT", anchor, relPoint, x, 0)
                        button:SetFrameLevel(entry:GetFrameLevel() + 2)
                        local icon = button:CreateTexture(nil, "OVERLAY")
                        icon:SetSize(ICON_SZ, ICON_SZ)
                        icon:SetPoint("CENTER", button, "CENTER", 0, 0)
                        if icon.SetSnapToPixelGrid then
                            icon:SetSnapToPixelGrid(false)
                            icon:SetTexelSnappingBias(0)
                        end
                        icon:SetTexture(MEDIA_ICONS .. file)
                        button:SetScript("OnEnter", function(self)
                            self:SetAlpha(1)
                            itemCaption:SetTextColor(1, 1, 1, 1)
                            iHl:SetAlpha(hlA)
                            delBtn:SetAlpha(0.85)
                            editBtn:SetAlpha(0.85)
                            CUI.ShowWidgetTooltip(self, CUI.L(tip))
                        end)
                        button:SetScript("OnLeave", function(self)
                            if OverAny() then
                                self:SetAlpha(0.85)
                            else
                                Rest()
                            end
                            CUI.HideWidgetTooltip()
                        end)
                        button:SetScript("OnClick", function()
                            dropMenu:Hide()
                            act(entry._bar)
                        end)
                        return button
                    end
                    delBtn = InlineIcon(entry, "RIGHT", -8, "cui-close.png", "Delete", PromptDeleteBar)
                    editBtn = InlineIcon(delBtn, "LEFT", -4, "cui-edit.png", "Rename", PromptRenameBar)
                    itemCaption:SetPoint("RIGHT", editBtn, "LEFT", -4, 0)

                    entry:SetScript("OnEnter", function()
                        itemCaption:SetTextColor(1, 1, 1, 1)
                        iHl:SetAlpha(hlA)
                        delBtn:SetAlpha(1)
                        editBtn:SetAlpha(1)
                    end)
                    entry:SetScript("OnLeave", function()
                        if not (delBtn:IsMouseOver() or editBtn:IsMouseOver()) then Rest() end
                    end)
                    entry:SetScript("OnClick", function()
                        dropMenu:Hide()
                        local profile = Profile()
                        if profile then profile.selectedBarId = entry._bar.id end
                        FullRefresh()
                    end)
                    return entry
                end

                local div = dropMenu:CreateTexture(nil, "ARTWORK")
                div:SetHeight(1)
                div:SetColorTexture(1, 1, 1, 0.10)
                dropMenu._div = div

                -- "+ Create New DataBar..." action row (expands the card strip)
                local addEntry = CreateFrame("Button", nil, dropMenu)
                addEntry:SetHeight(ITEM_H)
                addEntry:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                local addCaption = CUI.MakeFont(addEntry, 11, nil, tDimR, tDimG, tDimB, tDimA)
                addCaption:SetPoint("LEFT", addEntry, "LEFT", 10, 0)
                addCaption:SetJustifyH("LEFT")
                addCaption:SetText(Loc("+ Create New DataBar..."))
                local addHl = addEntry:CreateTexture(nil, "ARTWORK")
                addHl:SetAllPoints()
                addHl:SetColorTexture(1, 1, 1, 1)
                addEntry:SetScript("OnEnter", function()
                    addCaption:SetTextColor(1, 1, 1, 1)
                    addHl:SetAlpha(hlA)
                end)
                addEntry:SetScript("OnLeave", function()
                    addCaption:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    addHl:SetAlpha(0)
                end)
                addEntry:SetScript("OnClick", function()
                    dropMenu:Hide()
                    _cardsExpanded = true
                    HeaderOnly()
                end)
                addEntry._lbl, addEntry._hl = addCaption, addHl
                dropMenu._addItem = addEntry

                CloseOnOutsideClick(dropMenu)
                _edbMenus.bar = dropMenu
            end

            dropMenu._anchor = dropdownBtn
            dropMenu:ClearAllPoints()
            dropMenu:SetPoint("TOPLEFT", dropdownBtn, "BOTTOMLEFT", 0, -2)
            dropMenu:SetPoint("TOPRIGHT", dropdownBtn, "BOTTOMRIGHT", 0, -2)

            local menuH = 4
            local barList = mod.BarsInOrder()
            local rowList = dropMenu._rows
            for position = 1, #barList do
                local bar = barList[position]
                local entry = rowList[position]
                if not entry then
                    entry = dropMenu._makeRow()
                    rowList[position] = entry
                end
                entry._bar = bar
                entry._isSel = rowConf ~= nil and bar.id == rowConf.id
                entry:ClearAllPoints()
                entry:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -menuH)
                entry:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -menuH)
                entry._lbl:SetText(bar.name or "")
                entry._rest()
                entry:Show()
                menuH = menuH + ITEM_H
            end
            for position = #barList + 1, #rowList do
                rowList[position]:Hide()
            end

            local div = dropMenu._div
            if #barList > 0 then
                div:ClearAllPoints()
                div:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -menuH - 4)
                div:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -menuH - 4)
                div:Show()
                menuH = menuH + 9
            else
                div:Hide()
            end

            local addEntry = dropMenu._addItem
            addEntry:ClearAllPoints()
            addEntry:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -menuH)
            addEntry:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -menuH)
            addEntry._lbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            addEntry._hl:SetAlpha(0)
            menuH = menuH + ITEM_H

            dropMenu:SetHeight(menuH + 4)
            dropMenu:SetScript("OnUpdate", dropMenu._closeOutside)
            dropMenu:Show()
        end

        -- The value's alpha lives in its text colour alone (built at TXT_A),
        -- so a hover and a leave land back on the resting look.
        dropdownBtn:SetScript("OnEnter", function()
            dropCaption:SetTextColor(1, 1, 1, 1)
            local brdHA = DropStyle.BRD_HA
            if brdHA == nil then brdHA = 0.30 end
            ddBrd:SetColor(1, 1, 1, brdHA)
            ddBg:SetColorTexture(DropStyle.BG_R, DropStyle.BG_G, DropStyle.BG_B, DropStyle.BG_HA)
        end)
        dropdownBtn:SetScript("OnLeave", function()
            local ddMenu = _edbMenus.bar
            if ddMenu and ddMenu:IsShown() then return end
            dropCaption:SetTextColor(1, 1, 1, DropStyle.TXT_A)
            ddBrd:SetColor(1, 1, 1, DropStyle.BRD_A)
            ddBg:SetColorTexture(DropStyle.BG_R, DropStyle.BG_G, DropStyle.BG_B, DropStyle.BG_A)
        end)
        dropdownBtn:SetScript("OnClick", function()
            local ddMenu = _edbMenus.bar
            if ddMenu and ddMenu:IsShown() then
                ddMenu:Hide()
            else
                BuildBarMenu()
            end
        end)
        dropdownBtn:HookScript("OnHide", function()
            if _edbMenus.bar then _edbMenus.bar:Hide() end
        end)

        -- "+ New Bar" (toggles the template card strip)
        local newBtn = CreateFrame("Button", nil, heading)
        Pix.Size(newBtn, 110, DD_H)
        Pix.Point(newBtn, "LEFT", dropdownBtn, "RIGHT", 10, 0)
        newBtn:SetFrameLevel(heading:GetFrameLevel() + 5)
        CUI.MakeStyledButton(newBtn, "+ New Bar", 12, CUI.WB_COLOURS, function()
            _cardsExpanded = not _cardsExpanded
            HeaderOnly()
        end)

        -- (Bar enable lives in the BAR SETTINGS section, not the header.)

        rowY = rowY - DD_H - 10

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
            Pix.Point(host, "TOPLEFT", heading, "TOPLEFT", PAD, rowY)
            for i = 1, 4 do
                MakeTemplateCard(host, (i - 1) * (cw + gap), 0, cw, ch, TEMPLATE_CARDS[i])
            end
            rowY = rowY - ch - 12
        end

        -----------------------------------------------------------------------
        --  Zero bars: hint only, no preview
        -----------------------------------------------------------------------
        if not rowConf then
            local hintText = CUI.MakeFont(heading, 12, nil, 1, 1, 1, 0.4)
            hintText:SetPoint("TOPLEFT", heading, "TOPLEFT", PAD + 4, rowY - 2)
            hintText:SetText(Loc("Create a DataBar to get started."))
            rowY = rowY - 24
            return math.abs(rowY) + 6
        end

        -----------------------------------------------------------------------
        --  Interactive preview strip
        -----------------------------------------------------------------------
        -- Extra breathing room above the preview strip.
        rowY = rowY - 10

        local isVertical = rowConf.orientation == "V"
        local stripLen, stripThick
        local stripParent = heading
        if isVertical then
            -- Vertical: the strip lives in the docked overlay popout, which persists
            -- across header rebuilds. The strip and its add tile (parented to the
            -- popout too, not to the strip) are kept frames there (Pool.Kept, below):
            -- every header build dresses the same two again, so a rebuild never
            -- strands an old one beside the new.
            local popout = GetPreviewPopout()
            stripParent = popout
            stripThick = STRIP_V_THICK
            stripLen = STRIP_V_LEN
            local scrollFrame = CUI._scrollFrame
            local sfH = scrollFrame and scrollFrame:GetHeight()
            if sfH and sfH > 260 then stripLen = math.min(520, sfH - 150) end
        else
            if _edbPopout then _edbPopout:Hide() end
            stripLen = hdrW - PAD * 2 - (STRIP_H_THICK + 8) -- room for the + tile
            stripThick = STRIP_H_THICK
        end

        -- Vertical: the popout's kept strip, the popout sized around it, its
        -- title and hint and the add tile below (the extra tail room is for
        -- the bottom hint, which wraps inside the narrow popout) and docked
        -- left of the options window. Horizontal: a strip under the header.
        local barStrip
        if isVertical then
            local popout = stripParent
            barStrip = Pool.Kept(_edbKeep, "popStrip", "Frame", popout)
            Pix.Size(barStrip, stripThick, stripLen)
            popout._strip = barStrip
            Pix.Size(popout, math.max(stripThick + 90, 150), stripLen + stripThick + 92)
            barStrip:ClearAllPoints()
            barStrip:SetPoint("TOP", popout, "TOP", 0, -28)
            barStrip:SetFrameLevel(popout:GetFrameLevel() + 3)
            popout:ClearAllPoints()
            local scrollFrame = CUI._scrollFrame
            if scrollFrame then
                popout:SetPoint("RIGHT", scrollFrame, "LEFT", 0, 0)
            else
                popout:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
            popout:Show()
        else
            barStrip = CreateFrame("Frame", nil, stripParent)
            Pix.Size(barStrip, stripLen, stripThick)
            Pix.Point(barStrip, "TOPLEFT", heading, "TOPLEFT", PAD, rowY)
            barStrip:SetFrameLevel(heading:GetFrameLevel() + 3)
        end
        -- Border handle set BEFORE the backdrop so the theme pass can fade
        -- it with Bar Opacity, exactly like the live bar.
        barStrip._edbBorder = Pix.CreateBorder(barStrip, 0, 0, 0, 0.8, 1, "OVERLAY", 7)
        mod.MakePreviewBackdrop(barStrip, rowConf.theme, not rowConf.hideBorder)
        _edbPreviewHost = barStrip

        local stripUsable = stripLen - SEDGE * 2
        local blocks = rowConf.blocks
        local nBlocks = #blocks
        -- Hidden blocks keep their index in every per-segment array below (the
        -- reorder commit works in the bar's own order) but draw nothing.
        local nShown = nBlocks
        for i = 1, nBlocks do
            if BlockHidden(blocks[i]) then nShown = nShown - 1 end
        end

        if nShown == 0 then
            local hintFS = CUI.MakeFont(barStrip, 11, nil, 1, 1, 1, 0.4)
            hintFS:SetPoint("CENTER", barStrip, "CENTER", 0, 0)
            if isVertical then
                -- The vertical strip is only a few px wide; cap the hint to
                -- the popout's inner width so it wraps instead of spilling.
                hintFS:SetWidth(130)
                hintFS:SetJustifyH("CENTER")
            end
            hintFS:SetText(Loc("Click + to add your first block"))
        end

        -- Segment overlays: one invisible button per block, retargeted by
        -- LayoutStrip below (built once per header build). dragIdx is shared
        -- with the reorder machinery below; hover borders are suppressed
        -- while a drag is live (only the insertion line marks placement).
        local dragIdx
        local dragEndTime = 0
        local segBtns, shareFSs = {}, {}
        for i = 1, nBlocks do
            local block = blocks[i]
            local button = CreateFrame("Button", nil, barStrip)
            button:SetFrameLevel(barStrip:GetFrameLevel() + 5)
            local hb = Pix.CreateBorder(button, EGc.r, EGc.g, EGc.b, 1, 2, "OVERLAY", 7)
            hb:Hide()
            button._brd = hb
            button:SetScript("OnEnter", function(s2)
                if dragIdx then return end
                s2._brd:Show()
                -- Hovering a preview segment lights the real bar's block
                -- the same way hovering its Width % setting does.
                _edbSegHoverId = block.id
                if mod.SetBlockEditHighlight then mod.SetBlockEditHighlight(rowConf.id, block.id) end
            end)
            button:SetScript("OnLeave", function(s2)
                s2._brd:Hide()
                if _edbSegHoverId == block.id then
                    _edbSegHoverId = nil
                    if mod.SetBlockEditHighlight then mod.SetBlockEditHighlight(nil, nil) end
                end
            end)

            -- Two centred one-line labels: the block's type above, its
            -- share of the bar (set by LayoutStrip) below.
            local function Label(size, alpha, y)
                local fs = CUI.MakeFont(button, size, nil, 1, 1, 1, alpha)
                fs:SetPoint("LEFT", button, "LEFT", 2, y)
                fs:SetPoint("RIGHT", button, "RIGHT", -2, y)
                fs:SetJustifyH("CENTER")
                fs:SetWordWrap(false)
                fs:SetMaxLines(1)
                return fs
            end
            Label(10, 0.85, 6):SetText(Loc(TYPE_LABEL[block.type] or block.type))
            local shareFS = Label(9, 0.5, -7)

            -- Settings-section hover wash (driven by the body watcher).
            local ehl = button:CreateTexture(nil, "OVERLAY", nil, 5)
            ehl:SetAllPoints()
            ehl:SetColorTexture(1, 1, 1, 0.08)
            ehl:Hide()
            button._editHL = ehl

            segBtns[i] = button
            shareFSs[i] = shareFS
            if BlockHidden(block) then button:Hide() end
        end

        -- Hovering a block's settings section washes its preview segment.
        _edbSegHighlightFn = function(hlBlockId)
            for keyName = 1, nBlocks do
                local scrollBar = segBtns[keyName]
                if scrollBar and scrollBar._editHL then
                    scrollBar._editHL:SetShown(hlBlockId ~= nil and blocks[keyName].id == hlBlockId)
                end
            end
        end

        -- A 1px seam line at each boundary, shown where the two segments touch.
        local lines = {}
        for i = 1, nBlocks - 1 do
            local line = barStrip:CreateTexture(nil, "OVERLAY", nil, 2)
            line:SetColorTexture(1, 1, 1, 0.12)
            if isVertical then
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
            local barUsable = ResolvedBarLength(rowConf) - 2 * mod.EDGE_PAD
            if barUsable < 1 then barUsable = 1 end
            local scale = stripUsable / barUsable
            local function measure(bc)
                -- Zero, as the live bar measures a block with no instance.
                if BlockHidden(bc) then return 0 end
                local wid = mod.GetLiveAutoLength(rowConf.id, bc.id)
                if not wid or wid <= 0 then wid = EST_LEN[bc.type] or 80 end
                return wid
            end
            -- Solve in REAL bar px (Auto Sized extents and gaps are real pixels), then
            -- map each segment's own edges into strip px. Segments may be
            -- NON-contiguous (a Force Centered block leaves pads beside it); touching
            -- neighbors still telescope because they share the same real edge. _touch
            -- marks real seams -- boundary lines draw only there.
            local segs = mod.SolveLayout(rowConf, barUsable, measure)
            for i = 1, #segs do
                local segment = segs[i]
                local rAt = segment.at or 0
                local a = floor(rAt * scale + 0.5)
                local e = floor((rAt + segment.px) * scale + 0.5)
                -- Seam lines run between shown segments only: a hidden one
                -- draws none and is skipped as a neighbor.
                local nxt
                if not BlockHidden(segment.block) then
                    local keyName = i + 1
                    while segs[keyName] and BlockHidden(segs[keyName].block) do
                        keyName = keyName + 1
                    end
                    nxt = segs[keyName]
                end
                if nxt then
                    local d = (nxt.at or 0) - (rAt + segment.px)
                    segment._touch = d > -0.75 and d < 0.75
                else
                    segment._touch = false
                end
                segment.pos = SEDGE + a
                segment.px = e - a
            end
            lastSegs = segs
            for i = 1, #segs do
                local segment = segs[i]
                local px = segment.px
                if px < 1 then px = 1 end
                local cursor = segment.pos
                local button = segBtns[i]
                if button then
                    button:ClearAllPoints()
                    if isVertical then
                        button:SetSize(stripThick, px)
                        button:SetPoint("TOP", barStrip, "TOP", 0, -cursor)
                    else
                        button:SetSize(px, stripThick)
                        button:SetPoint("LEFT", barStrip, "LEFT", cursor, 0)
                    end
                    -- Base position for the drag-reorder nudge animation.
                    button._basePos = cursor
                    button._curOff = 0
                    button._tgtOff = 0
                    if segment.isFill then
                        shareFSs[i]:SetText(Loc("fill"))
                    else
                        shareFSs[i]:SetText(format("%.1f%%", mod.NormalizedShare(rowConf, segment.block.id)))
                    end
                end
                cursor = cursor + px
                local lineTex = lines[i]
                if lineTex then
                    lineTex:SetShown(segment._touch and true or false)
                    lineTex:ClearAllPoints()
                    if isVertical then
                        lineTex:SetPoint("LEFT", barStrip, "TOPLEFT", 0, -cursor)
                        lineTex:SetPoint("RIGHT", barStrip, "TOPRIGHT", 0, -cursor)
                    else
                        lineTex:SetPoint("TOP", barStrip, "TOPLEFT", cursor, 0)
                        lineTex:SetPoint("BOTTOM", barStrip, "BOTTOMLEFT", cursor, 0)
                    end
                end
            end
        end
        _edbStripRelayout = LayoutStrip
        _edbStripBarId = rowConf.id
        LayoutStrip()

        -----------------------------------------------------------------------
        -- Drag-to-reorder segments (CDM preview pattern): while dragging, the other
        -- segments ease apart around the hovered boundary via a small animated nudge
        -- and an accent insertion line marks the drop point; release commits the move.
        -----------------------------------------------------------------------
        local dropLine = barStrip:CreateTexture(nil, "OVERLAY", nil, 7)
        do
            local ar2, ag2, ab3 = mod.GetAccent()
            dropLine:SetColorTexture(ar2, ag2, ab3, 0.9)
        end
        if isVertical then
            dropLine:SetSize(stripThick, 2)
        else
            dropLine:SetSize(2, stripThick)
        end
        dropLine:Hide()

        local NUDGE = 6
        local animTicker
        local function EnsureAnimTicker()
            if animTicker then return end
            -- A strip of the page pool that a newer header build dressed again
            -- holds that build's segments: the ticker ends with this build.
            local gen = Pool.Gen(barStrip)
            animTicker = C_Timer.NewTicker(0.016, function()
                if Pool.Gen(barStrip) ~= gen or Pool.IsIdle(barStrip) then
                    animTicker:Cancel()
                    animTicker = nil
                    return
                end
                local moving = false
                for keyName = 1, #segBtns do
                    local scrollBar = segBtns[keyName]
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
                        if isVertical then
                            scrollBar:SetPoint("TOP", barStrip, "TOP", 0, -(scrollBar._basePos + current))
                        else
                            scrollBar:SetPoint("LEFT", barStrip, "LEFT", scrollBar._basePos + current, 0)
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
            local curX, curY = GetCursorPosition()
            local es = barStrip:GetEffectiveScale()
            if not es or es == 0 then es = 1 end
            if isVertical then return (barStrip:GetTop() or 0) - curY / es end
            return curX / es - (barStrip:GetLeft() or 0)
        end

        local function ComputeInsertIdx()
            if not lastSegs then return nil end
            -- Before the first segment whose middle lies past the cursor.
            local place = CursorStripPos()
            for keyName, segment in ipairs(lastSegs) do
                if place < (segment.pos or 0) + (segment.px or 0) / 2 then return keyName end
            end
            return #lastSegs + 1
        end

        -- A drop is a no-op when only hidden segments (see BlockHidden) lie
        -- between the target boundary and the dragged segment: the move
        -- would change nothing on screen and only shift a hidden entry.
        local function IsNoopDrop(from, to)
            if to == from or to == from + 1 then return true end
            local lo, hi = to, from - 1
            if to > from then
                lo, hi = from + 1, to - 1
            end
            for keyName = lo, hi do
                if not BlockHidden(blocks[keyName]) then return false end
            end
            return true
        end

        local function UpdateDragVisuals()
            if not dragIdx or not lastSegs then return end
            local targetIdx = ComputeInsertIdx()
            -- Boundaries adjoining the dragged segment are a no-op drop.
            local noop = IsNoopDrop(dragIdx, targetIdx)
            -- Counted without the dragged segment, everything at or after the
            -- insertion point eases toward the end and everything before it
            -- back toward the start.
            local insertAt = targetIdx > dragIdx and targetIdx - 1 or targetIdx
            for keyName = 1, #segBtns do
                local off = 0
                if keyName ~= dragIdx and not noop then
                    local at = keyName > dragIdx and keyName - 1 or keyName
                    off = at >= insertAt and NUDGE or -NUDGE
                end
                segBtns[keyName]._tgtOff = off
            end
            EnsureAnimTicker()
            if noop then
                dropLine:Hide()
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
            dropLine:ClearAllPoints()
            if isVertical then
                dropLine:SetPoint("TOP", barStrip, "TOP", 0, -(linePos - 1))
            else
                dropLine:SetPoint("LEFT", barStrip, "LEFT", linePos - 1, 0)
            end
            dropLine:Show()
        end

        -- Pickup ghost: a floating half-scale copy of the segment that rides
        -- the cursor while dragging (CDM preview pattern); the segment itself
        -- stays in place dimmed to 0.3.
        local dragShadow
        local function EnsureDragGhost()
            if dragShadow then return dragShadow end
            -- One kept ghost for the session (Pool.Kept on UIParent): the first
            -- drag of each header build dresses it again.
            dragShadow = Pool.Kept(_edbKeep, "dragGhost", "Frame", UIParent)
            dragShadow:SetFrameStrata("TOOLTIP")
            dragShadow:SetFrameLevel(500)
            local gBg = dragShadow:CreateTexture(nil, "BACKGROUND")
            gBg:SetAllPoints()
            gBg:SetColorTexture(0.111, 0.103, 0.096, 0.95)
            local ar2, ag2, ab3 = mod.GetAccent()
            CUI.MakeBorder(dragShadow, ar2, ag2, ab3, 0.9, Pix)
            local gl = CUI.MakeFont(dragShadow, 10, nil, 1, 1, 1, 0.9)
            gl:SetPoint("CENTER")
            dragShadow._lbl = gl
            dragShadow:Hide()
            return dragShadow
        end

        local function FinishDrag()
            barStrip:SetScript("OnUpdate", nil)
            local from = dragIdx
            dragIdx = nil
            dragEndTime = GetTime()
            if dragShadow then dragShadow:Hide() end
            dropLine:Hide()
            if from and segBtns[from] then segBtns[from]:SetAlpha(1) end
            for keyName = 1, #segBtns do
                segBtns[keyName]._tgtOff = 0
            end
            local targetIdx = ComputeInsertIdx()
            if not (from and targetIdx) then return end
            if IsNoopDrop(from, targetIdx) then return end
            mod.MoveBlockTo(rowConf.id, blocks[from].id, targetIdx)
            -- Full refresh: the preview strip lives in the content header,
            -- which a plain RefreshPage never rebuilds.
            FullRefresh()
        end

        local function BeginDrag(fromIdx)
            dragIdx = fromIdx
            local scrollBar = segBtns[fromIdx]
            if scrollBar._brd then scrollBar._brd:Hide() end
            scrollBar:SetAlpha(0.3)
            -- The ghost: the segment's size (at least 24 long; a squashed
            -- one takes the strip's thickness) and its type label.
            local ghost = EnsureDragGhost()
            local gw, gh = scrollBar:GetSize()
            if not gh or gh < 12 then gh = stripThick end
            ghost:SetSize(math.max(gw or 0, 24), gh)
            local kind = blocks[fromIdx].type
            ghost._lbl:SetText(Loc(TYPE_LABEL[kind] or kind))
            ghost:SetScale(0.5)
            ghost:Show()
            EnsureAnimTicker()
            -- Cursor follow + release detection (mouse-up can land anywhere).
            barStrip:SetScript("OnUpdate", function()
                if not IsMouseButtonDown("LeftButton") then
                    FinishDrag()
                    return
                end
                local curX, curY = GetCursorPosition()
                local uiScale = UIParent:GetEffectiveScale()
                curX, curY = curX / uiScale, curY / uiScale
                local gs = dragShadow:GetScale() or 1
                dragShadow:ClearAllPoints()
                dragShadow:SetPoint("CENTER", UIParent, "BOTTOMLEFT", curX / gs, curY / gs)
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
                if dropMenu:IsShown() then dropMenu:Hide() end
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
                    local labelFS = CUI.MakeFont(row, 11, nil, 1, 1, 1, 0.9)
                    labelFS:SetPoint("LEFT", row, "LEFT", 10, 0)
                    labelFS:SetText(textValue)
                    row:SetScript("OnClick", function()
                        dropMenu:Hide()
                        onClick()
                    end)
                    rowY = rowY - ROW_H2
                end
                AddRow(Loc("Remove Block"), function()
                    mod.RemoveBlock(dropMenu._barId, dropMenu._blockId)
                    -- Full refresh: the preview strip lives in the content
                    -- header, which a plain RefreshPage never rebuilds.
                    FullRefresh()
                    -- The page just lost a whole section; a bottom-scrolled view
                    -- would be left staring at blank space.
                    if CUI.SmoothScrollTo then CUI.SmoothScrollTo(0) end
                end)
                dropMenu:SetHeight(-rowY + 3)
                -- Click-away dismiss. The opening right-button is STILL DOWN on
                -- the first frames (the menu opens on RightButtonDown) -- without
                -- the guard (menu._openGuard, set per open) the menu dismissed
                -- itself instantly.
                dropMenu:SetScript("OnUpdate", function(frame)
                    if frame._openGuard then
                        if not IsMouseButtonDown("RightButton") then frame._openGuard = nil end
                        return
                    end
                    if
                        not frame:IsMouseOver()
                        and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
                    then
                        frame:Hide()
                    end
                end)
                _edbMenus.seg = dropMenu
            end
            dropMenu._barId = rowConf.id
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
                if GetTime() - dragEndTime < 0.2 then return end
                if mbtn == "RightButton" then
                    ShowSegmentMenu(scrollBar, segBlockId)
                elseif mbtn == "LeftButton" then
                    if _edbNavigateFn then _edbNavigateFn("block:" .. segBlockId) end
                end
            end)
            segBtn:SetScript("OnMouseDown", function(scrollBar, mbtn)
                if mbtn ~= "LeftButton" then return end
                if dragIdx then return end
                local curX, curY = GetCursorPosition()
                scrollBar._pendX, scrollBar._pendY = curX, curY
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
        local addButton
        if isVertical then
            addButton = Pool.Kept(_edbKeep, "popAddBtn", "Button", stripParent)
            Pix.Size(addButton, stripThick, stripThick)
            Pix.Point(addButton, "TOP", barStrip, "BOTTOM", 0, -4)
        else
            addButton = CreateFrame("Button", nil, stripParent)
            Pix.Size(addButton, stripThick, stripThick)
            Pix.Point(addButton, "LEFT", barStrip, "RIGHT", 4, 0)
        end
        addButton:SetFrameLevel(barStrip:GetFrameLevel() + 2)
        local addBg = addButton:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints()
        addBg:SetColorTexture(0.08, 0.08, 0.08, 0.6)
        if addBg.SetSnapToPixelGrid then
            addBg:SetSnapToPixelGrid(false)
            addBg:SetTexelSnappingBias(0)
        end
        Pix.CreateBorder(addButton, 0.3, 0.3, 0.3, 0.5, 1, "OVERLAY", 7)
        local addCaption = CUI.MakeFont(addButton, 22, nil, EGc.r, EGc.g, EGc.b, 0.7)
        addCaption:SetPoint("CENTER", 0, 1)
        addCaption:SetText("+")
        local addHlCont = CreateFrame("Frame", nil, addButton)
        addHlCont:SetAllPoints()
        addHlCont:SetFrameLevel(addButton:GetFrameLevel() + 1)
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
            local hlA = DropStyle.ITEM_HL_A
            if not dropMenu then
                dropMenu = MenuShell(190)
                dropMenu._rows = {}
                local menuH = 4
                for _, t in ipairs(mod.OfferedBlockTypes()) do
                    local entry = CreateFrame("Button", nil, dropMenu)
                    entry:SetHeight(ITEM_H)
                    entry:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -menuH)
                    entry:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -menuH)
                    entry:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                    local itemCaption = CUI.MakeFont(entry, 11, nil, tDimR, tDimG, tDimB, tDimA)
                    itemCaption:SetPoint("LEFT", entry, "LEFT", 10, 0)
                    itemCaption:SetJustifyH("LEFT")
                    itemCaption:SetText(Loc(t.label))
                    local iHl = entry:CreateTexture(nil, "ARTWORK")
                    iHl:SetAllPoints()
                    iHl:SetColorTexture(1, 1, 1, 1)
                    -- item._baseA / item._hoverA: this open's label alphas.
                    entry:SetScript("OnEnter", function()
                        itemCaption:SetTextColor(1, 1, 1, entry._hoverA)
                        iHl:SetAlpha(hlA)
                    end)
                    entry:SetScript("OnLeave", function()
                        itemCaption:SetTextColor(tDimR, tDimG, tDimB, entry._baseA)
                        iHl:SetAlpha(0)
                    end)
                    local typeKey = t.key
                    entry:SetScript("OnClick", function()
                        dropMenu:Hide()
                        local nb = mod.AddBlock(dropMenu._barId, typeKey)
                        FullRefresh()
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
                                if _edbNavigateFn then _edbNavigateFn(navKey) end
                            end)
                        end
                    end)
                    entry._typeKey, entry._lbl, entry._hl = typeKey, itemCaption, iHl
                    dropMenu._rows[#dropMenu._rows + 1] = entry
                    menuH = menuH + ITEM_H
                end
                dropMenu:SetHeight(menuH + 4)
                CloseOnOutsideClick(dropMenu)
                _edbMenus.add = dropMenu
            end
            local rowList = dropMenu._rows
            for i = 1, #rowList do
                local entry = rowList[i]
                local typeKey = entry._typeKey
                -- Types already on this bar render dimmed -- still fully clickable
                -- (duplicates are legal), just an at-a-glance cue for what the bar is
                -- missing. Re-applied on every open, so this never goes stale.
                local onBar = false
                for bi = 1, #rowConf.blocks do
                    if rowConf.blocks[bi].type == typeKey then
                        onBar = true
                        break
                    end
                end
                -- Spacers are the one type meant to repeat on a bar, so the
                -- already-on-bar dim cue never applies to them. Broker blocks
                -- repeat for the same reason: one per plugin is the normal setup,
                -- so a second one is not the accident the dim cue warns about.
                if typeKey == "spacer" or typeKey == "ldb" then onBar = false end
                local baseA = tDimA
                local hoverA = 1
                if onBar then
                    baseA = 0.28
                    hoverA = 0.55
                end
                entry._baseA, entry._hoverA = baseA, hoverA
                entry._lbl:SetTextColor(tDimR, tDimG, tDimB, baseA)
                entry._hl:SetAlpha(0)
            end
            dropMenu._barId = rowConf.id
            dropMenu._anchor = addButton
            dropMenu:ClearAllPoints()
            dropMenu:SetPoint("TOPRIGHT", addButton, "BOTTOMRIGHT", 0, -2)
            dropMenu:SetScript("OnUpdate", dropMenu._closeOutside)
            dropMenu:Show()
        end
        addButton:SetScript("OnClick", ToggleAddMenu)
        addButton:SetScript("OnEnter", function()
            addCaption:SetTextColor(EGc.r, EGc.g, EGc.b, 1)
            addBrd:Show()
            CUI.ShowWidgetTooltip(addButton, Loc("Add a block to this bar"))
        end)
        addButton:SetScript("OnLeave", function()
            addCaption:SetTextColor(EGc.r, EGc.g, EGc.b, 0.7)
            addBrd:Hide()
            CUI.HideWidgetTooltip()
        end)
        addButton:HookScript("OnHide", function()
            if _edbMenus.add then _edbMenus.add:Hide() end
        end)

        if isVertical then
            -- The strip lives in the docked popout; the header only carries
            -- a pointer to it.
            local vh = CUI.MakeFont(heading, 12, nil, 1, 1, 1, 0.4)
            vh:SetPoint("TOP", heading, "TOP", 0, rowY - 2)
            vh:SetJustifyH("CENTER")
            vh:SetText(Loc("Vertical bar: the interactive preview is docked beside this window."))
            rowY = rowY - 24
        else
            rowY = rowY - stripThick - 8
            -- Interaction hint directly below the preview (CDM preview pattern).
            local ph = CUI.MakeFont(heading, 11, nil, 0.62, 0.62, 0.62, 0.9)
            ph:SetPoint("TOP", barStrip, "BOTTOM", 0, -8)
            ph:SetWidth(stripLen - 20)
            ph:SetJustifyH("CENTER")
            ph:SetWordWrap(true)
            ph:SetText(Loc("Drag to Reorder. Click to Scroll. Right Click to Remove."))
            rowY = rowY - 16 - 10
        end

        return math.abs(rowY)
    end

    ---------------------------------------------------------------------------
    --  Page body
    ---------------------------------------------------------------------------
    local function BuildDataBarsPage(page, hostFrame, yOffset)
        local W = CUI.Widgets
        local cursorY = yOffset
        local _, height, heading
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
        local PlaySettingGlow = CUI.MakeSettingGlow({ color = CUI.CLUDES_GREEN })

        local function GlowTargetOf(m)
            if not m.slotSide then return m.target end
            local regionFrame
            if m.slotSide == "left" then
                regionFrame = m.target._leftRegion
            else
                regionFrame = m.target._rightRegion
            end
            return regionFrame or m.target
        end

        local function NavigateToSetting(barKey)
            local targets = hostFrame._edbClickTargets
            if not targets then return end
            local m = targets[barKey]
            if not m or not m.section or not m.target then return end
            local _, _, _, _, headerY = m.section:GetPoint(1)
            if not headerY then return end
            CUI.SmoothScrollTo(math.max(0, math.abs(headerY) - 40))
            local glowTarget = GlowTargetOf(m)
            if m.holdWhile then
                _edbHeldGlowKey, _edbHeldGlowY = barKey, headerY
            end
            -- A target of the page pool that is dressed again for another row by
            -- then belongs to a newer build (which re-arms its own glow).
            local gen = Pool.Gen(glowTarget)
            C_Timer.After(0.15, function()
                if Pool.Gen(glowTarget) ~= gen or Pool.IsIdle(glowTarget) then return end
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
            if not _edbHeldGlowKey then return end
            local targets = hostFrame._edbClickTargets
            local m = targets and targets[_edbHeldGlowKey]
            -- Absent from this build (another bar is selected): keep the key so
            -- coming back re-arms. Only a satisfied predicate retires it.
            if not (m and m.section and m.target and m.holdWhile) then return end
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
        if not CUI._prebuilding then _edbNavigateFn = NavigateToSetting end

        local profile = Profile()
        if not profile then return math.abs(cursorY) end
        local rowConf = SelectedBar()

        -- Bar selected -> editor chrome; zero bars -> no header, the body
        -- below renders the full starting screen.
        if rowConf then
            CUI:SetContentHeader(_edbHeaderBuilder)
        else
            CUI:ClearContentHeader()
        end

        -------------------------------------------------------------------
        --  Zero bars: template-card empty state
        -------------------------------------------------------------------
        if not rowConf then
            local PADC = CUI.CONTENT_PAD
            if not PADC then PADC = 10 end
            local hostW = hostFrame:GetWidth() - PADC * 2
            local gap = 12
            local cw = floor((hostW - gap) / 2)
            local ch = 76
            local hostH = 40 + ch * 2 + gap + 10
            -- Explicit size + single TOPLEFT anchor (search contract); the
            -- host doubles as a search pseudo-section.
            local host = CreateFrame("Frame", nil, hostFrame)
            Pix.Size(host, hostW, hostH)
            Pix.Point(host, "TOPLEFT", hostFrame, "TOPLEFT", PADC, cursorY)
            host._isSectionHeader = true
            host._sectionName = "Create New DataBar"
            local hintText = CUI.MakeFont(host, 13, nil, 1, 1, 1, 0.55)
            hintText:SetPoint("TOPLEFT", host, "TOPLEFT", 4, -8)
            hintText:SetText(Loc("Create your first DataBar from a starter template, or start empty."))
            for i = 1, 4 do
                local col = (i - 1) % 2
                local rowI = floor((i - 1) / 2)
                MakeTemplateCard(host, col * (cw + gap), -40 - rowI * (ch + gap), cw, ch, TEMPLATE_CARDS[i])
            end
            cursorY = cursorY - hostH - 10
            return math.abs(cursorY)
        end

        local barId = rowConf.id
        local isVertical = rowConf.orientation == "V"
        local skinName = rowConf.theme
        if not skinName then
            skinName =
                { style = "cui", cuiAlpha = 0.5, modernColor = { r = 0.067, g = 0.067, b = 0.067, a = 0.95 } }
            rowConf.theme = skinName
        end

        local function ApplyBar() mod.ApplyBar(barId) end

        -- Sizing mode: centered segmented two-button toggle (the shared
        -- segmented control), in its OWN space between
        -- the preview header and BAR SETTINGS with 15px above and below.
        -- BAR-level -- it owns every block's width: Auto Sized = content +
        -- per-side gaps with one Fill Remaining block; Even Split = equal
        -- segments. Switching rebuilds the page (block sections gain/lose
        -- their sizing rows).
        cursorY = cursorY - 15
        do
            local BTN_W, BTN_H = 150, 26
            local segment = CUI.BuildSegmentedControl({
                parent = hostFrame,
                keys = { "auto", "even" },
                labels = { auto = "Auto Sized", even = "Even Split" },
                width = BTN_W * 2,
                square = true,
                height = BTN_H,
                getChecked = function(barKey) return mod.BarSizingMode(rowConf) == barKey end,
                onToggle = function(barKey)
                    if mod.BarSizingMode(rowConf) == barKey then return end
                    rowConf.sizingMode = barKey
                    mod.ApplyBar(barId)
                    FullRefresh()
                end,
            })
            segment:SetPoint("TOP", hostFrame, "TOP", 0, cursorY)
            cursorY = cursorY - (BTN_H + 15)
        end

        -------------------------------------------------------------------
        --  BAR SETTINGS
        -------------------------------------------------------------------
        heading, height = W:SectionHeader(hostFrame, "BAR SETTINGS", cursorY)
        cursorY = cursorY - height
        -- The Move in Unlock Mode button on the selected bar's first section:
        -- the key is read at the click, so it highlights the bar the selector shows.
        CUI.BuildSectionUnlockJump(heading, {
            key = function()
                local c = SelectedBar()
                return c and ("EDB_" .. c.id) or nil
            end,
        })

        -- Visibility | Visibility Options (renaming lives in the selector's
        -- inline edit; "Never" visibility fully disables the bar's work).
        local visRow
        visRow, height = CUI.BuildVisibilityRow(
            W,
            hostFrame,
            cursorY,
            {
                getStore = function() return mod.GetBar(barId) end,
                legacyKey = "visibility",
                caps = mod.EDB_VIS_CAPS,
                onChanged = function()
                    -- "Never" tears the bar down entirely (and un-Never
                    -- rebuilds), so run the full apply, not just the vis pass.
                    mod.ApplyBar(barId)
                    mod.UpdateAllBarVisibility()
                end,
                onOptionChanged = function() mod.UpdateAllBarVisibility() end,
            },
            -- Hide Border moved up from the section's old trailing half-row into the slot
            -- the Visibility Options dropdown left behind, so neither row is half empty.
            {
                type = "toggle",
                text = "Hide Border",
                tooltip = "Hide the 1-pixel outline around the bar.",
                getValue = function() return rowConf.hideBorder == true end,
                setValue = function(val)
                    rowConf.hideBorder = val and true or false
                    mod.ApplyTheme(barId)
                    PaintPreviewTheme()
                end,
            }
        )
        cursorY = cursorY - height
        -- Inline cog on the Visibility dropdown: Bar Strata. Lives here rather
        -- than as a row of its own because it answers the same question the
        -- visibility controls do -- when and where this bar shows up -- and it
        -- is a set-once setting that should not cost a row.
        do
            local leftRegion = visRow._leftRegion
            CUI.BuildInlineCog(leftRegion, {
                title = "Bar Layer",
                rows = {
                    {
                        type = "dropdown",
                        label = "Bar Strata",
                        tooltip = "Screen layer this bar renders on. Raise it to draw over other frames, lower it to sit behind them.",
                        values = CUI.FRAME_STRATA_LABELS,
                        order = CUI.FRAME_STRATA_ORDER_BASE,
                        get = function()
                            local c = mod.GetBar(barId)
                            return (c and c.barStrata) or "MEDIUM"
                        end,
                        set = function(val)
                            local c = mod.GetBar(barId)
                            if not c then return end
                            c.barStrata = val
                            mod.ApplyBar(barId)
                        end,
                    },
                },
            })
        end

        -- Orientation | Theme (inline cog = CludesUI Backdrop Dim)
        local themeRow
        themeRow, height = W:DualRow(hostFrame, cursorY, {
            type = "segmented",
            text = "Orientation",
            tooltip = "Horizontal bars lay blocks left to right; vertical bars stack them top to bottom.",
            values = { H = "Horizontal", V = "Vertical" },
            order = { "H", "V" },
            getValue = function()
                if rowConf.orientation == "V" then return "V" end
                return "H"
            end,
            setValue = function(val)
                rowConf.orientation = val
                -- An edge snap that no longer matches the orientation
                -- remaps to the nearest valid edge.
                local e = rowConf.snapEdge
                if val == "V" and (e == "bottom" or e == "top") then
                    rowConf.snapEdge = "left"
                elseif val == "H" and (e == "left" or e == "right") then
                    rowConf.snapEdge = "bottom"
                end
                mod.ApplyBar(barId)
                FullRefresh()
            end,
        }, {
            type = "segmented",
            text = "Background Style",
            tooltip = "CludesUI matches the window-skin shell; Modern is a flat color.",
            values = { cui = "CludesUI", modern = "Modern" },
            order = { "cui", "modern" },
            getValue = function()
                if skinName.style == "modern" then return "modern" end
                return "cui"
            end,
            setValue = function(val)
                skinName.style = val
                -- Selecting Modern starts Bar Opacity at 95.
                if val == "modern" then
                    local color = skinName.modernColor
                    if not color then
                        color = { r = 0.067, g = 0.067, b = 0.067 }
                        skinName.modernColor = color
                    end
                    color.a = 0.95
                end
                mod.ApplyTheme(barId)
                FullRefresh()
            end,
        })
        cursorY = cursorY - height
        CUI.BuildInlineCog(themeRow._rightRegion, {
            title = "CludesUI Background",
            disabled = function() return skinName.style ~= "cui" end,
            disabledTooltip = "the CludesUI theme",
            rows = {
                {
                    type = "slider",
                    label = "Backdrop Dim",
                    min = 0,
                    max = 100,
                    step = 1,
                    get = function()
                        local a = skinName.cuiAlpha
                        if a == nil then a = 0.5 end
                        return floor(a * 100 + 0.5)
                    end,
                    set = function(val)
                        skinName.cuiAlpha = val / 100
                        mod.ApplyTheme(barId)
                        PaintPreviewTheme()
                    end,
                },
            },
        })

        -- Bar Texture: 1:1 with the Unit Frames picker -- same built-in texture set
        -- plus SharedMedia statusbars appended live on every build (late-registered
        -- packs always appear), with texture preview backgrounds on the menu items.
        local function BuildBarTexDropdown()
            CUI.AppendSharedMediaTextures(
                mod.barTextureNames or {},
                mod.barTextureOrder or {},
                nil,
                mod.barTextures
            )
            local btValues, btOrder = {}, {}
            local texNames = mod.barTextureNames or {}
            local texOrder = mod.barTextureOrder or {}
            for _, barKey in ipairs(texOrder) do
                if barKey ~= "---" then
                    btValues[barKey] = texNames[barKey] or barKey
                    btOrder[#btOrder + 1] = barKey
                end
            end
            local texLookup = mod.barTextures or {}
            btValues._menuOpts = {
                itemHeight = 28,
                background = function(barKey) return texLookup[barKey] end,
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
            disabled = function() return (skinName and skinName.style) ~= "modern" end,
            disabledTooltip = "Modern Background Style is required.",
            values = btValues,
            order = btOrder,
            getValue = function() return rowConf.barTexture or "none" end,
            setValue = function(val)
                rowConf.barTexture = val
                if mod.ApplyTheme then mod.ApplyTheme(barId) end
                ApplyBar()
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
                local val = rowConf.fontScale
                if val == nil then val = 100 end
                return val
            end,
            setValue = function(val)
                rowConf.fontScale = val
                ApplyBar()
            end,
        }
        -- One bar-wide switch (was a per-block toggle).
        local hoverBlocksCfg = {
            type = "toggle",
            text = "Hover Highlight Blocks",
            tooltip = "Shows a faint white wash over each block on mouseover.",
            getValue = function() return rowConf.hoverHighlight == true end,
            setValue = function(val)
                rowConf.hoverHighlight = val and true or false
                ApplyBar()
            end,
        }
        -- Bar Opacity drives BOTH styles: the Modern flat color's alpha or
        -- the CludesUI shell's backdrop dim, whichever is active.
        local opacityRow
        opacityRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Bar Opacity",
            min = 0,
            max = 100,
            step = 1,
            tooltip = "Opacity of the bar's background; the swatch picks the Modern color.",
            getValue = function()
                if skinName.style == "modern" then
                    local color = skinName.modernColor
                    local a = color and color.a
                    if a == nil then a = 0.95 end
                    return floor(a * 100 + 0.5)
                end
                local a = skinName.cuiOpacity
                if a == nil then a = 1 end
                return floor(a * 100 + 0.5)
            end,
            setValue = function(val)
                if skinName.style == "modern" then
                    local color = skinName.modernColor
                    if not color then
                        color = { r = 0.067, g = 0.067, b = 0.067 }
                        skinName.modernColor = color
                    end
                    color.a = val / 100
                else
                    skinName.cuiOpacity = val / 100
                end
                mod.ApplyTheme(barId)
                PaintPreviewTheme()
            end,
        }, barTexCfg)
        cursorY = cursorY - height
        if not CUI._prebuilding then
            -- Inline Modern-background swatch: always present, disabled
            -- (house pattern) while the CludesUI style is active. Style
            -- changes HardRefresh, so the state re-evaluates on switch.
            local region = opacityRow._leftRegion
            local colorSwatch = CUI.BuildColorSwatch(region, opacityRow:GetFrameLevel() + 3, function()
                local color = skinName.modernColor
                if not color then return 0.067, 0.067, 0.067 end
                local red = color.r
                if red == nil then red = 0.067 end
                local green = color.g
                if green == nil then green = 0.067 end
                local b2 = color.b
                if b2 == nil then b2 = 0.067 end
                return red, green, b2
            end, function(red, green, blue)
                local color = skinName.modernColor
                if not color then
                    color = { a = 0.95 }
                    skinName.modernColor = color
                end
                color.r = red
                color.g = green
                color.b = blue
                mod.ApplyTheme(barId)
                PaintPreviewTheme()
            end, false, 20)
            Pix.Point(colorSwatch, "RIGHT", region._control, "LEFT", -8, 0)
            if skinName.style ~= "modern" then
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
        if isVertical then
            lenLabel, fullLabel, thickLabel = "Height", "Full Screen Height", "Width"
        else
            lenLabel, fullLabel, thickLabel = "Width", "Full Screen Width", "Height"
        end
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = fullLabel,
            tooltip = "Sizes the bar to the full screen extent along its axis.",
            getValue = function() return rowConf.lengthMode == "full" end,
            setValue = function(val)
                if val then
                    rowConf.lengthMode = "full"
                else
                    rowConf.lengthMode = "custom"
                end
                mod.ApplyBar(barId)
                if _edbStripRelayout then _edbStripRelayout() end
                CUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Snap to Screen Edge",
            tooltip = "Pins the bar flush against a screen edge; moving the bar in layout mode sets this back to None.",
            values = { none = "None", bottom = "Bottom", top = "Top", left = "Left", right = "Right" },
            order = { "none", "bottom", "top", "left", "right" },
            itemDisabled = function(val)
                if isVertical then return val == "bottom" or val == "top" end
                return val == "left" or val == "right"
            end,
            itemDisabledTooltip = function(val)
                if val == "bottom" or val == "top" then return "Not available for vertical bars" end
                return "Not available for horizontal bars"
            end,
            getValue = function()
                local val = rowConf.snapEdge
                if val == nil then val = "none" end
                return val
            end,
            setValue = function(val)
                rowConf.snapEdge = val
                mod.ApplyBar(barId)
            end,
        })
        cursorY = cursorY - height

        -- Width | Height (length + thickness in screen terms)
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = lenLabel,
            min = 100,
            max = 3000,
            step = 10,
            tooltip = "Size of the bar along its block axis in pixels.",
            disabled = function() return rowConf.lengthMode == "full" end,
            disabledTooltip = CUI.Lf("Disabled while %1$s is enabled.", CUI.L(fullLabel)),
            rawTooltip = true,
            getValue = function()
                local val = rowConf.length
                if val == nil then val = 400 end
                return val
            end,
            setValue = function(val)
                rowConf.length = val
                mod.ApplyBar(barId)
                if _edbStripRelayout then _edbStripRelayout() end
            end,
        }, {
            type = "slider",
            text = thickLabel,
            min = 16,
            max = 3000,
            step = 1,
            tooltip = "Size of the bar across its block axis in pixels.",
            getValue = function()
                local val = rowConf.thickness
                if val == nil then val = 30 end
                return val
            end,
            setValue = function(val)
                rowConf.thickness = val
                ApplyBar()
            end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, scaleCfg, hoverBlocksCfg)
        cursorY = cursorY - height

        -- Bar deletion lives in the selector dropdown's inline delete -- no
        -- body row. Visibility moved to the top of the section; rename =
        -- selector inline edit.

        -------------------------------------------------------------------
        --  One section per block
        -------------------------------------------------------------------
        local blocks = rowConf.blocks
        if CUI.IS_FOREVER then
            -- Hidden blocks get no section (see BlockHidden); the rest keep
            -- bar order.
            local isShown = {}
            for i = 1, #blocks do
                if not BlockHidden(blocks[i]) then isShown[#isShown + 1] = blocks[i] end
            end
            blocks = isShown
        end
        local blockHoverRegions = {} -- { id, rgn } Width % control regions
        for i = 1, #blocks do
            local block = blocks[i]
            local blockId = block.id
            local cfg = block.settings
            -- Row accessors over s: a key read (or its default) and written.
            local function SFieldThen(barKey)
                return function(value)
                    cfg[barKey] = value
                    ApplyBar()
                end
            end
            local function SFieldOr(barKey, default)
                return function() return cfg[barKey] or default end
            end
            if not cfg then
                cfg = {}
                block.settings = cfg
            end
            local isSpacer = block.type == "spacer"
            local typeLabel = TYPE_LABEL[block.type]
            if not typeLabel then typeLabel = block.type end

            local secHdr
            secHdr, height = W:SectionHeader(hostFrame, string.upper(CUI.L(typeLabel)), cursorY)
            cursorY = cursorY - height

            -- Bar-level sizing owns all widths now (Auto Sized / Even Split toggle at
            -- the top of Bar Settings). Auto mode: every block except the single Fill
            -- Remaining block gets a per-side gaps row, and every block gets the fill
            -- designation toggle. Even Split: no per-block sizing rows at all.
            local barMode = mod.BarSizingMode(rowConf)
            local isFillBlock = barMode == "auto" and mod.EnsureFillBlock(rowConf) == blockId
            local sizingRow
            if barMode == "auto" and not isFillBlock then
                local gapLLabel, gapRLabel
                if isVertical then
                    gapLLabel, gapRLabel = "Top Gap", "Bottom Gap"
                else
                    gapLLabel, gapRLabel = "Left Gap", "Right Gap"
                end
                sizingRow, height = W:DualRow(hostFrame, cursorY, {
                    type = "slider",
                    text = gapLLabel,
                    min = 0,
                    max = 200,
                    step = 1,
                    tooltip = "Empty space reserved on this side of the block's content.",
                    getValue = function()
                        local l = mod.ContentGapsOf(block)
                        return l
                    end,
                    setValue = function(val)
                        block.contentGapL = val
                        ApplyBar()
                        if _edbStripRelayout then _edbStripRelayout() end
                    end,
                }, {
                    type = "slider",
                    text = gapRLabel,
                    min = 0,
                    max = 200,
                    step = 1,
                    tooltip = "Empty space reserved on this side of the block's content.",
                    getValue = function()
                        local _, r = mod.ContentGapsOf(block)
                        return r
                    end,
                    setValue = function(val)
                        block.contentGapR = val
                        ApplyBar()
                        if _edbStripRelayout then _edbStripRelayout() end
                    end,
                })
                cursorY = cursorY - height
            end
            if barMode == "auto" then
                local fillRow
                fillRow, height = W:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Set as 'Fill Remaining Space' Block",
                    tooltip = "Stretches this block to absorb the space the sized blocks leave over; exactly one block per bar fills.",
                    disabled = function() return mod.EnsureFillBlock(rowConf) == blockId end,
                    disabledTooltip = "This block is already the 'Fill Remaining Space' block. Check another block to move the role.",
                    rawTooltip = true,
                    getValue = function() return mod.EnsureFillBlock(rowConf) == blockId end,
                    setValue = function(val)
                        if val then
                            mod.SetFillBlock(barId, blockId)
                            FullRefresh()
                        end
                    end,
                }, {
                    type = "toggle",
                    text = "Force Centered",
                    tooltip = "Pins this block's content to the exact center of the bar; blocks before it pack left, blocks after pack right. Combined with Fill Remaining, the block also absorbs the leftover space around the center.",
                    getValue = function() return rowConf.centerBlockId == blockId end,
                    setValue = function(val)
                        if val then
                            mod.SetCenterBlock(barId, blockId)
                        elseif rowConf.centerBlockId == blockId then
                            mod.SetCenterBlock(barId, nil)
                        end
                        FullRefresh()
                    end,
                })
                cursorY = cursorY - height
                if not sizingRow then sizingRow = fillRow end
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
                if isVertical then
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
                if block.type == "micromenu" then
                    alignLeftCfg = {
                        type = "toggle",
                        text = "Enable Text",
                        tooltip = "Shows the online friend and guild counters.",
                        getValue = function() return cfg.hideSocialText ~= true end,
                        setValue = function(val)
                            cfg.hideSocialText = not val
                            ApplyBar()
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
                            local a = block.align
                            if a == nil then a = "CENTER" end
                            return a
                        end,
                        setValue = function(val)
                            block.align = val
                            -- XP / Rep: a picked alignment also places the bar's
                            -- label (unset keeps the label left, as it always was).
                            if block.type == "xprep" then block.labelAlign = val end
                            ApplyBar()
                        end,
                    }
                end
                local alignRow
                alignRow, height = W:DualRow(hostFrame, cursorY, alignLeftCfg, {
                    type = "slider",
                    text = "Content Scale",
                    min = 50,
                    max = 200,
                    step = 5,
                    tooltip = "Scales this block's content as a group inside its slot.",
                    getValue = function()
                        local val = block.scale
                        if val == nil then val = 100 end
                        return val
                    end,
                    setValue = function(val)
                        block.scale = val
                        ApplyBar()
                    end,
                })
                cursorY = cursorY - height
                do
                    -- Text Position cog: offsets the TEXT only (factories
                    -- inject these into every text anchor; icons stay put).
                    CUI.BuildInlineCog(alignRow._leftRegion, {
                        title = "Text Position",
                        rows = {
                            {
                                type = "slider",
                                label = "X Offset",
                                min = -50,
                                max = 50,
                                step = 1,
                                get = function()
                                    local val = block.textXOff
                                    if val == nil then val = 0 end
                                    return val
                                end,
                                set = function(val)
                                    block.textXOff = val
                                    if mod.ReflowBlocks then mod.ReflowBlocks(barId) end
                                end,
                            },
                            {
                                type = "slider",
                                label = "Y Offset",
                                min = -50,
                                max = 50,
                                step = 1,
                                get = function()
                                    local val = block.textYOff
                                    if val == nil then val = 0 end
                                    return val
                                end,
                                set = function(val)
                                    block.textYOff = val
                                    if mod.ReflowBlocks then mod.ReflowBlocks(barId) end
                                end,
                            },
                        },
                    })

                    -- Content Position cog (next to Content Scale): offsets
                    -- the WHOLE block content group, text included.
                    CUI.BuildInlineCog(alignRow._rightRegion, {
                        title = "Content Position",
                        rows = {
                            {
                                type = "slider",
                                label = "X Offset",
                                min = -50,
                                max = 50,
                                step = 1,
                                get = function()
                                    local val = block.xOff
                                    if val == nil then val = 0 end
                                    return val
                                end,
                                set = function(val)
                                    block.xOff = val
                                    ApplyBar()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Y Offset",
                                min = -50,
                                max = 50,
                                step = 1,
                                get = function()
                                    local val = block.yOff
                                    if val == nil then val = 0 end
                                    return val
                                end,
                                set = function(val)
                                    block.yOff = val
                                    ApplyBar()
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
            local function ReflowBar()
                if mod.ReflowBlocks then mod.ReflowBlocks(barId) end
            end
            local colorCfg = {
                type = "multiSwatch",
                text = "Text Color",
                swatches = {
                    {
                        tooltip = "Custom Color",
                        hasAlpha = false,
                        getValue = function()
                            local color = block.color
                            if color then return color.r or 1, color.g or 1, color.b or 1 end
                            return 1, 1, 1
                        end,
                        setValue = function(red, green, blue)
                            block.color = { r = red, g = green, b = blue }
                            ReflowBar()
                        end,
                        onClick = function(self)
                            if block.useClassColor or block.useAccentColor then
                                block.useClassColor = nil
                                block.useAccentColor = nil
                                ReflowBar()
                                CUI:RefreshPage()
                                return
                            end
                            if self._eabOrigClick then self._eabOrigClick(self) end
                        end,
                        refreshAlpha = function()
                            return (block.useClassColor or block.useAccentColor) and 0.3 or 1
                        end,
                    },
                    {
                        tooltip = "Class Colored",
                        hasAlpha = false,
                        getValue = function()
                            local _, class = UnitClass("player")
                            local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                            if classColor then return classColor.r, classColor.g, classColor.b end
                            return 1, 1, 1
                        end,
                        setValue = function() end,
                        onClick = function()
                            block.useClassColor = true
                            block.useAccentColor = nil
                            ReflowBar()
                            CUI:RefreshPage()
                        end,
                        refreshAlpha = function() return block.useClassColor and 1 or 0.3 end,
                    },
                    {
                        tooltip = "Accent Color",
                        hasAlpha = false,
                        getValue = function() return mod.GetAccent() end,
                        setValue = function() end,
                        onClick = function()
                            block.useAccentColor = true
                            block.useClassColor = nil
                            ReflowBar()
                            CUI:RefreshPage()
                        end,
                        refreshAlpha = function() return block.useAccentColor and 1 or 0.3 end,
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
                local function Flag() return block[flag] end
                local off, on = opts.off or Flag, opts.on or Flag
                local sw = colorCfg.swatches
                local customClick, customAlpha = sw[1].onClick, sw[1].refreshAlpha
                sw[1].onClick = function(self)
                    if off() then
                        block[flag] = nil
                        if opts.toCustom then opts.toCustom() end
                        ReflowBar()
                        CUI:RefreshPage()
                        return
                    end
                    customClick(self)
                end
                sw[1].refreshAlpha = function()
                    if off() then return 0.3 end
                    return customAlpha()
                end
                for i = 2, 3 do
                    local click = sw[i].onClick
                    sw[i].onClick = function(...)
                        block[flag] = nil
                        return click(...)
                    end
                end
                sw[4] = {
                    tooltip = tip,
                    hasAlpha = false,
                    getValue = getValue,
                    setValue = function() end,
                    onClick = function()
                        block[flag] = true
                        block.useClassColor = nil
                        block.useAccentColor = nil
                        ReflowBar()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function() return on() and 1 or 0.3 end,
                }
            end
            -- Gold: "Coin Colored" -- white numbers, coin-tinted g/s/c
            -- letters; the forced default (see the factory's coinForced
            -- one-shot).
            if block.type == "gold" then
                -- E2AC7A -- matches DENOMINATIONS' gold letter (user-set).
                ModeSwatch("useCoinColor", "Coin Colored", function() return 0.886, 0.675, 0.478 end)
            end
            -- Crests: "Crest Colors" -- each amount tinted with its own tier
            -- colour. Unlike Gold's coin mode this is the nothing-stored
            -- DEFAULT, resolved by ns.CrestColorMode rather than a forced
            -- write, so Custom has to SEED b.color to take the selection
            -- (same shape as the Icon Color row's Custom/Default pair below).
            if block.type == "crests" then
                -- Myth gold: the top crest, and the most recognizable of the
                -- five as a single preview swatch.
                ModeSwatch("useCrestColor", "Crest Colors", function() return 1, 0.82, 0 end, {
                    off = function()
                        return mod.CrestColorMode(block) or block.useClassColor or block.useAccentColor
                    end,
                    toCustom = function()
                        block.useClassColor = nil
                        block.useAccentColor = nil
                        if block.color == nil then block.color = { r = 1, g = 1, b = 1 } end
                    end,
                    on = function() return mod.CrestColorMode(block) end,
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
            if DYNAMIC_TEXT_BLOCKS[block.type] then
                ModeSwatch(
                    "useDynamicColor",
                    DYNAMIC_TEXT_BLOCKS[block.type],
                    function() return mod.BlockTextDynamic(block.type) end
                )
            end
            local bgRow
            local bgRightCfg
            if isSpacer then
                bgRightCfg = { type = "label", text = "" }
            else
                bgRightCfg = colorCfg
            end
            bgRow, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Block Background",
                tooltip = "Tints this block's slot with its own color.",
                getValue = function() return block.bg ~= nil end,
                setValue = function(val)
                    if val then
                        if not block.bg then block.bg = { r = 0, g = 0, b = 0, a = 0.5 } end
                    else
                        block.bg = nil
                    end
                    ApplyBar()
                    CUI:RefreshPage()
                end,
            }, bgRightCfg)
            cursorY = cursorY - height
            if not CUI._prebuilding then
                local region = bgRow._leftRegion
                local control = region._control
                local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
                    region,
                    bgRow:GetFrameLevel() + 3,
                    function()
                        local color = block.bg
                        if not color then return 0, 0, 0, 0.5 end
                        local red = color.r
                        if red == nil then red = 0 end
                        local green = color.g
                        if green == nil then green = 0 end
                        local b2 = color.b
                        if b2 == nil then b2 = 0 end
                        local a = color.a
                        if a == nil then a = 0.5 end
                        return red, green, b2, a
                    end,
                    function(red, green, blue, a)
                        block.bg = { r = red, g = green, b = blue, a = a }
                        ApplyBar()
                    end,
                    true,
                    20
                )
                Pix.Point(colorSwatch, "RIGHT", control, "LEFT", -8, 0)
                GatedSwatch(
                    colorSwatch,
                    updateSwatch,
                    "Enable Block Background",
                    10,
                    function() return block.bg end
                )
            end

            -- Toggle row for a setting whose default is ON: nil has to read as
            -- true, which the `== true` of MkToggle (further down) cannot
            -- express. Declared here because the icon row below needs it too.
            local function MkToggleOn(labelText, barKey, tipText)
                return {
                    type = "toggle",
                    text = labelText,
                    tooltip = tipText,
                    getValue = function() return cfg[barKey] ~= false end,
                    setValue = function(val)
                        cfg[barKey] = val and true or false
                        ApplyBar()
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
            if ICON_COLOR_BLOCKS[block.type] then
                local function IconFlagsOff()
                    return not block.useIconClassColor
                        and not block.useIconAccentColor
                        and not block.useIconDefaultColor
                end
                local iconColorCfg = {
                    type = "multiSwatch",
                    text = "Icon Color",
                    swatches = {
                        {
                            tooltip = "Custom Color",
                            hasAlpha = false,
                            getValue = function()
                                local color = block.iconColor
                                if color then return color.r or 1, color.g or 1, color.b or 1 end
                                return mod.BlockIconDefault(block.type, cfg)
                            end,
                            setValue = function(red, green, blue)
                                block.iconColor = { r = red, g = green, b = blue }
                                ReflowBar()
                            end,
                            onClick = function(self)
                                -- Switching from Class/Accent/Default: SEED the custom color
                                -- (from the themed default) so custom actually lights on this
                                -- click -- unlike the Text Color row, flag-less with nothing
                                -- stored means DEFAULT here, so clearing flags alone landed
                                -- the selection on Default until the picker stored a color.
                                -- Second click opens the picker as usual.
                                if not IconFlagsOff() or block.iconColor == nil then
                                    block.useIconClassColor = nil
                                    block.useIconAccentColor = nil
                                    block.useIconDefaultColor = nil
                                    if block.iconColor == nil then
                                        local dr, dg2, db2 = mod.BlockIconDefault(block.type, cfg)
                                        block.iconColor = { r = dr, g = dg2, b = db2 }
                                    end
                                    ReflowBar()
                                    CUI:RefreshPage()
                                    return
                                end
                                if self._eabOrigClick then self._eabOrigClick(self) end
                            end,
                            refreshAlpha = function()
                                return (IconFlagsOff() and block.iconColor ~= nil) and 1 or 0.3
                            end,
                        },
                        {
                            tooltip = "Class Colored",
                            hasAlpha = false,
                            getValue = function()
                                local _, class = UnitClass("player")
                                local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                                if classColor then return classColor.r, classColor.g, classColor.b end
                                return 1, 1, 1
                            end,
                            setValue = function() end,
                            onClick = function()
                                block.useIconClassColor = true
                                block.useIconAccentColor = nil
                                block.useIconDefaultColor = nil
                                ReflowBar()
                                CUI:RefreshPage()
                            end,
                            refreshAlpha = function() return block.useIconClassColor and 1 or 0.3 end,
                        },
                        {
                            tooltip = "Accent Color",
                            hasAlpha = false,
                            getValue = function() return mod.GetAccent() end,
                            setValue = function() end,
                            onClick = function()
                                block.useIconAccentColor = true
                                block.useIconClassColor = nil
                                block.useIconDefaultColor = nil
                                ReflowBar()
                                CUI:RefreshPage()
                            end,
                            refreshAlpha = function() return block.useIconAccentColor and 1 or 0.3 end,
                        },
                        {
                            tooltip = "Default",
                            hasAlpha = false,
                            getValue = function() return mod.BlockIconDefault(block.type, cfg) end,
                            setValue = function() end,
                            onClick = function()
                                -- Mode switch only -- the stored custom color stays
                                -- stashed for the Custom swatch.
                                block.useIconDefaultColor = true
                                block.useIconClassColor = nil
                                block.useIconAccentColor = nil
                                ReflowBar()
                                CUI:RefreshPage()
                            end,
                            refreshAlpha = function()
                                return (
                                    block.useIconDefaultColor or (IconFlagsOff() and block.iconColor == nil)
                                )
                                        and 1
                                    or 0.3
                            end,
                        },
                    },
                }
                if block.type == "durability" then
                    -- Durability's default tint is DYNAMIC (red -> green by
                    -- lowest durability); same mode semantics, clearer name.
                    iconColorCfg.swatches[4].tooltip = "Dynamic"
                end
                if block.type == "spec" and cfg.iconStyle ~= "wow" then
                    -- Spec defaults to CLASS color: no Default swatch; the Class swatch
                    -- reads as selected in the nothing-stored state, and a legacy
                    -- stored Default-mode flag (from when the swatch existed) lights it
                    -- too -- both render class color.
                    iconColorCfg.swatches[4] = nil
                    iconColorCfg.swatches[2].refreshAlpha = function()
                        if block.useIconClassColor or block.useIconDefaultColor then return 1 end
                        return (IconFlagsOff() and block.iconColor == nil) and 1 or 0.3
                    end
                end
                if (block.type == "profession" or block.type == "profession2") and cfg.iconStyle ~= "wow" then
                    -- Professions default to ACCENT (matches the skill-bar
                    -- fill), so they carry no Default swatch -- and Accent
                    -- reads as selected in the nothing-stored state too.
                    iconColorCfg.swatches[4] = nil
                    iconColorCfg.swatches[3].refreshAlpha = function()
                        if block.useIconAccentColor then return 1 end
                        return (IconFlagsOff() and block.iconColor == nil) and 1 or 0.3
                    end
                end
                -- Gold / travel: a type row rides the Icon Color row's
                -- otherwise-empty right slot instead of trailing alone below.
                local iconRowRight = { type = "label", text = "" }
                if block.type == "travel" and not CUI.IS_FOREVER then
                    -- Default ON (nil = shown), so this can't use MkToggle's
                    -- `== true` read.
                    iconRowRight = {
                        type = "toggle",
                        text = "Show M+ Portals",
                        tooltip = "Show the Mythic+ teleport section in the tooltip. Ready rows are click-to-teleport.",
                        getValue = function() return cfg.clickableTeleports ~= false end,
                        setValue = function(val)
                            cfg.clickableTeleports = val and true or false
                            ApplyBar()
                        end,
                    }
                end
                if block.type == "audio" then
                    -- Default ON (nil = shown), so this can't use MkToggle's
                    -- `== true` read.
                    iconRowRight = {
                        type = "toggle",
                        text = "Show Icon",
                        tooltip = "Shows the audio icon next to the volume bar.",
                        getValue = function() return cfg.showIcon ~= false end,
                        setValue = function(val)
                            cfg.showIcon = val and true or false
                            ApplyBar()
                        end,
                    }
                end
                if block.type == "profession" or block.type == "profession2" then
                    -- Default ON (nil = shown), so this can't use MkToggle's
                    -- `== true` read.
                    iconRowRight = {
                        type = "toggle",
                        text = "Show Icon",
                        tooltip = "Shows the profession icons next to the text.",
                        getValue = function() return cfg.showIcon ~= false end,
                        setValue = function(val)
                            cfg.showIcon = val and true or false
                            ApplyBar()
                        end,
                    }
                end
                if block.type == "spec" then
                    -- Default ON (nil = shown), so this can't use MkToggle's
                    -- `== true` read.
                    iconRowRight = {
                        type = "toggle",
                        text = "Show Icon",
                        tooltip = "Shows the spec icon next to the text.",
                        getValue = function() return cfg.showIcon ~= false end,
                        setValue = function(val)
                            cfg.showIcon = val and true or false
                            ApplyBar()
                        end,
                    }
                end
                if block.type == "supplies" then
                    iconRowRight = MkToggleOn("Show Icon", "showIcon")
                elseif block.type == "location" then
                    iconRowRight =
                        MkToggleOn("Show Icon", "showIcon", "Shows the map pin next to the zone name.")
                elseif block.type == "coords" then
                    iconRowRight =
                        MkToggleOn("Show Icon", "showIcon", "Shows the marker icon next to the coordinates.")
                elseif block.type == "bags" then
                    iconRowRight =
                        MkToggleOn("Show Icon", "showIcon", "Shows the bag icon next to the slot count.")
                end
                if block.type == "durability" then
                    iconRowRight = {
                        type = "toggle",
                        text = "Show Icon",
                        tooltip = "Shows the icon next to the durability readout.",
                        getValue = function() return cfg.showIcon == true end,
                        setValue = function(val)
                            cfg.showIcon = val and true or false
                            ApplyBar()
                        end,
                    }
                end
                if block.type == "ilvl" then
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
                            local profile = cfg.prefix
                            if profile == nil then profile = "short" end
                            return profile
                        end,
                        setValue = SFieldThen("prefix"),
                    }
                end
                if block.type == "gold" then
                    iconRowRight = {
                        type = "toggle",
                        text = "Show Silver and Copper",
                        tooltip = "Shows silver and copper, not just gold.",
                        getValue = function() return cfg.showSmall == true end,
                        setValue = function(val)
                            cfg.showSmall = val and true or false
                            ApplyBar()
                        end,
                    }
                end
                if block.type == "travel" and CUI.IS_FOREVER then
                    travelIconCfg = iconColorCfg
                else
                    _, height = W:DualRow(hostFrame, cursorY, iconColorCfg, iconRowRight)
                    cursorY = cursorY - height
                end
            end

            -- Type-specific rows (sequential DualRow fill; odd tail gets a
            -- blank label in the remaining slot)
            local function ToggleRow(labelText, barKey, tipText)
                return {
                    type = "toggle",
                    text = labelText,
                    tooltip = tipText,
                    getValue = function() return cfg[barKey] == true end,
                    setValue = function(val)
                        cfg[barKey] = val and true or false
                        ApplyBar()
                    end,
                }
            end

            local typeRowList = {}
            -- Travel: its three click dropdowns, set by the row loop below.
            local travelClickDD
            if block.type == "audio" then
                typeRowList = {
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
            elseif block.type == "clock" then
                -- The two time toggles show the EFFECTIVE mode: untouched,
                -- the clock follows the game's Time Manager CVars (same as
                -- the minimap clock); toggling stores a per-block override.
                typeRowList = {
                    {
                        type = "toggle",
                        text = "Local Time",
                        tooltip = "Local computer time instead of server time.",
                        getValue = function()
                            if cfg.localTime == nil then return GetCVar("timeMgrUseLocalTime") == "1" end
                            return cfg.localTime == true
                        end,
                        setValue = function(val)
                            cfg.localTime = val and true or false
                            ApplyBar()
                        end,
                    },
                    {
                        type = "toggle",
                        text = "24 Hour Clock",
                        tooltip = "Use 24-hour time.",
                        getValue = function()
                            if cfg.twentyFour == nil then return GetCVar("timeMgrUseMilitaryTime") == "1" end
                            return cfg.twentyFour == true
                        end,
                        setValue = function(val)
                            cfg.twentyFour = val and true or false
                            ApplyBar()
                        end,
                    },
                    ToggleRow("Mail Alert", "showMail", "Shows an envelope icon when you have unread mail."),
                    ToggleRow(
                        "Resting Icon",
                        "showResting",
                        "Shows a rest icon while your character is resting."
                    ),
                }
            elseif block.type == "combat" then
                typeRowList = {
                    ToggleRow(
                        "Show Only In Combat",
                        "onlyInCombat",
                        "Shows the combat status text only while your character is in combat."
                    ),
                }
            elseif block.type == "ms" then
                typeRowList = {
                    {
                        type = "segmented",
                        text = "Latency",
                        tooltip = "Which latency to show: home, world, or both side by side.",
                        values = { home = "Home", world = "World", both = "Both" },
                        order = { "home", "world", "both" },
                        getValue = function() return mod.LatencyMode(cfg) end,
                        setValue = SFieldThen("latencyMode"),
                    },
                    -- Not MkToggle: the inline icon-color swatches below key
                    -- their disabled state off this toggle, so it has to
                    -- rebuild the page (house pattern for inline controls).
                    {
                        type = "toggle",
                        text = "Show Icon",
                        tooltip = "Shows a house or globe icon marking which latency each value is.",
                        getValue = function() return cfg.showIcon == true end,
                        setValue = function(val)
                            cfg.showIcon = val and true or false
                            ApplyBar()
                            CUI:RefreshPage()
                        end,
                    },
                }
            elseif block.type == "location" then
                -- Width only reaches the layout when the solver actually reads
                -- this block's measured extent. Even Split hands every block an
                -- equal share, and the Fill Remaining block gets the leftover:
                -- in both the setting would silently do nothing, so say so rather than
                -- shipping a control that lies. EnsureFillBlock, not the raw
                -- cfg.fillBlockId: an unset or stale id heals to the last block, and
                -- reading the field directly would leave the control enabled on a block
                -- that IS the fill -- the very case this guards.
                local function WidthLocked()
                    if mod.BarSizingMode(rowConf) ~= "auto" then return true end
                    return mod.EnsureFillBlock(rowConf) == blockId
                end
                local INERT_TIP =
                    "This bar sizes its blocks itself, so the width is not this block's to choose."
                typeRowList = {
                    {
                        type = "segmented",
                        text = "Width",
                        tooltip = "Automatic follows the zone name. Manual holds the block at a fixed width and clips longer names, so it never shifts the blocks beside it.",
                        values = { auto = "Automatic", manual = "Manual" },
                        order = { "auto", "manual" },
                        disabled = WidthLocked,
                        disabledTooltip = INERT_TIP,
                        getValue = function() return mod.LocationWidthMode(cfg) end,
                        setValue = function(val)
                            cfg.widthMode = val
                            -- Every switch to Manual re-arms the pulse, whether
                            -- the block is new or was already configured: the
                            -- slider is the control that just took over, so it
                            -- has to announce itself each time.
                            _edbWidthPulse[block] = (val == "manual") or nil
                            ApplyBar()
                            -- The slider's disabled state keys off this value.
                            CUI:RefreshPage()
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
                            if WidthLocked() then return true end
                            return mod.LocationWidthMode(cfg) ~= "manual"
                        end,
                        -- Two reasons to be disabled, two different sentences:
                        -- a fixed "Manual width is required." would be plainly
                        -- wrong on an Even Split bar.
                        disabledTooltip = function()
                            if WidthLocked() then return INERT_TIP end
                            return "Manual width is required."
                        end,
                        getValue = function()
                            local val = cfg.maxWidth
                            if val == nil then val = mod.LOC_MAX_WIDTH_DEFAULT end
                            return val
                        end,
                        setValue = function(val)
                            cfg.maxWidth = val
                            -- Touched: the pulse has done its job.
                            _edbWidthPulse[block] = nil
                            ApplyBar()
                        end,
                    },
                    MkToggleOn(
                        "Zone and Subzone",
                        "showSubZone",
                        "Shows the zone and the subzone together instead of the subzone alone."
                    ),
                }
            elseif block.type == "coords" then
                typeRowList = {
                    {
                        type = "dropdown",
                        text = "Decimals",
                        tooltip = "How precise the coordinates read. More decimals make the block wider.",
                        values = { [0] = "None", [1] = "One", [2] = "Two" },
                        order = { 0, 1, 2 },
                        getValue = function()
                            local profile = cfg.precision
                            if profile == nil then profile = 0 end
                            return profile
                        end,
                        setValue = SFieldThen("precision"),
                    },
                    MkToggleOn(
                        "Hide in Instance",
                        "hideInInstance",
                        "Removes the block from the bar in instanced content, where player coordinates are unavailable."
                    ),
                }
            elseif block.type == "gold" then
                typeRowList = {
                    ToggleRow("Show Icon", "showIcons", "Shows the coin icon next to the amount."),
                    ToggleRow("Show Bag Space", "showBagSpace", "Shows your free bag slots."),
                    -- Off (default) = the letter suffixes; on = coin textures.
                    -- Independent of Coin Colored, which tints those letters.
                    ToggleRow(
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
                        getValue = function() return "__placeholder" end,
                        setValue = function() end,
                    },
                    ToggleRow(
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
                        getValue = function() return CUI.GetGoldLedger().IsTracking() end,
                        setValue = function(val) CUI.GetGoldLedger().SetTracking(val) end,
                    },
                }
                -- Force English Units: only where the effective locale actually
                -- has its own abbreviation algorithm (currently the CJK wan/yi
                -- grouping tables in CludesUI_NumberFormat.lua); every other
                -- locale already gets K/M/B, so the toggle would be a no-op.
                -- Mirrors the Damage Meters options row (CUI_DamageMeters_Options.lua).
                if CUI.LocaleHasNumberAbbreviation() then
                    typeRowList[#typeRowList + 1] = ToggleRow(
                        "Force English Units (K/M/B)",
                        "forceEnglishUnits",
                        "Always use K/M/B instead of localized units."
                    )
                end
            elseif block.type == "profession" or block.type == "profession2" then
                typeRowList = {
                    {
                        type = "segmented",
                        text = "Text Display",
                        values = { name = "Name and Bar", values = "Values" },
                        order = { "name", "values" },
                        getValue = SFieldOr("textDisplay", "name"),
                        setValue = SFieldThen("textDisplay"),
                    },
                }
            elseif block.type == "xprep" then
                typeRowList = {
                    {
                        type = "dropdown",
                        text = "Text Display",
                        values = { off = "Off", values = "Values", percentage = "Percentage" },
                        order = { "off", "values", "percentage" },
                        getValue = function() return mod.GetXPRepTextDisplay(cfg) end,
                        setValue = SFieldThen("textDisplay"),
                    },
                    {
                        type = "dropdown",
                        text = "Text Format",
                        values = { context = "With Level / Faction", plain = "Value Only" },
                        order = { "context", "plain" },
                        getValue = SFieldOr("textFormat", "context"),
                        setValue = SFieldThen("textFormat"),
                        disabled = function() return mod.GetXPRepTextDisplay(cfg) == "off" end,
                    },
                    {
                        type = "dropdown",
                        text = "Mode",
                        tooltip = "Automatic shows XP while leveling and reputation at max level.",
                        values = { auto = "Automatic", xp = "Experience", rep = "Reputation" },
                        order = { "auto", "xp", "rep" },
                        getValue = function()
                            local m = cfg.mode
                            if m == nil then m = "auto" end
                            return m
                        end,
                        setValue = SFieldThen("mode"),
                    },
                }
            elseif block.type == "spec" then
                typeRowList = {
                    ToggleRow("Show Loadout Name", "showLoadout", "Shows the active talent loadout name."),
                    ToggleRow("Uppercase Text", "useUppercase", "Renders the spec text in uppercase."),
                }
            elseif block.type == "travel" then
                local function ChoiceOf(button) return mod.TravelClickChoice(cfg, button) end
                -- Houses arrive asynchronously: the page refresh lists them (the refill below).
                mod.TravelRequestHouseList(function()
                    if CUI:GetActiveModule() == "CludesUIDataBars" then CUI:RefreshPage() end
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
                    for gi, group in ipairs(groups) do
                        local entries, curInGroup = {}, false
                        if group.ids and group.usable then
                            for _, ident in ipairs(group.ids) do
                                if ident == current then curInGroup = true end
                                if group.usable(ident) and ident ~= current then
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
                            table.sort(entries, function(a, z) return nameList[a] < nameList[z] end)
                            sequence[#sequence + 1] = group.key
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
                typeRowList = {}
                local clickVals, clickOrd = {}, {}
                for button = 1, 3 do
                    local vals, ord = BuildClickValues(button, {}, {})
                    clickVals[button], clickOrd[button] = vals, ord
                    typeRowList[#typeRowList + 1] = {
                        type = "dropdown",
                        text = CLICK_LABELS[button],
                        tooltip = CLICK_TIPS[button],
                        values = vals,
                        order = ord,
                        getValue = function() return ChoiceOf(button) end,
                        setValue = function(val)
                            cfg[CLICK_KEYS[button]] = val
                            -- Mirrored for old readers/exports of the legacy boolean.
                            if button == 1 then cfg.randomizeHs = (val == "random") end
                            ApplyBar()
                            CUI:RefreshPage()
                        end,
                    }
                    typeRowList[#typeRowList + 1] = {
                        type = "dropdown",
                        text = TEXT_LABELS[button],
                        tooltip = "What the bar shows for this click.",
                        values = TEXT_VALUES,
                        order = TEXT_ORDER,
                        getValue = function() return mod.TravelClickTextMode(cfg, button) end,
                        setValue = function(val)
                            cfg[TEXT_KEYS[button]] = val
                            ApplyBar()
                        end,
                        disabled = function() return ChoiceOf(button) == "none" end,
                        disabledTooltip = "Set this click to something other than None.",
                        rawTooltip = true,
                    }
                end
                -- Last, so each click keeps its choice and text on one row.
                if travelIconCfg then typeRowList[#typeRowList + 1] = travelIconCfg end
                typeRowList[#typeRowList + 1] = ToggleRow(
                    "Show Other Characters",
                    "altHearths",
                    "Lists your other characters' hearthstones in the tooltip, once each has logged in with this on."
                )
                -- A house list that arrived after the build: refill the three menus in place.
                if not CUI._prebuilding then
                    travelClickDD = {}
                    local clickDD, listGen = travelClickDD, mod.TravelHouseListGen()
                    CUI.RegisterWidgetRefresh(function()
                        local gen = mod.TravelHouseListGen()
                        if gen == listGen then return end
                        listGen = gen
                        for button = 1, 3 do
                            BuildClickValues(button, clickVals[button], clickOrd[button])
                            local dropdown = clickDD[button]
                            if dropdown and dropdown._invalidateMenu then dropdown._invalidateMenu() end
                        end
                    end)
                end
            elseif block.type == "micromenu" then
                -- Align Content returns here as a type row (its shared-row
                -- slot hosts the Enable Text toggle instead): anchors the
                -- whole icon strip within the block's slot via b.align.
                local mmAlignValues
                if isVertical then
                    mmAlignValues = { LEFT = "Top", CENTER = "Center", RIGHT = "Bottom" }
                else
                    mmAlignValues = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
                end
                typeRowList = {
                    {
                        type = "dropdown",
                        text = "Align Content",
                        tooltip = "Where the icon strip sits inside its slot.",
                        values = mmAlignValues,
                        order = { "LEFT", "CENTER", "RIGHT" },
                        getValue = function()
                            local a = block.align
                            if a == nil then a = "CENTER" end
                            return a
                        end,
                        setValue = function(val)
                            block.align = val
                            ApplyBar()
                        end,
                    },
                    ToggleRow(
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
                            local val = cfg.mainMenuSpacing
                            if val == nil then val = 4 end
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
                            local val = cfg.iconSpacing
                            if val == nil then val = 2 end
                            return val
                        end,
                        setValue = SFieldThen("iconSpacing"),
                    },
                    -- Individual button toggles live in the "Menu Elements"
                    -- checklist dropdown appended after the shared row loop.
                }
            elseif block.type == "supplies" then
                typeRowList = {
                    {
                        type = "dropdown",
                        text = "Visible Items",
                        values = { __placeholder = "..." },
                        order = { "__placeholder" },
                        getValue = function() return "__placeholder" end,
                        setValue = function() end,
                    },
                    ToggleRow("Show Label", "showLabel"),
                }
            elseif block.type == "currency" then
                local cValues, cOrder = mod.BuildCurrencyList()
                cValues._noLoc = true
                cValues._menuOpts = { searchable = true, itemHeight = 26 }
                cValues[0] = Loc("Select a currency")
                table.insert(cOrder, 1, 0)
                typeRowList = {
                    {
                        type = "dropdown",
                        text = "Currency",
                        tooltip = "Pick any currency your character has discovered.",
                        values = cValues,
                        order = cOrder,
                        getValue = function()
                            local ident = cfg.currencyId
                            if ident == nil then ident = 0 end
                            return ident
                        end,
                        setValue = function(val)
                            if val == 0 then
                                cfg.currencyId = nil
                            else
                                cfg.currencyId = val
                            end
                            ApplyBar()
                        end,
                    },
                    ToggleRow("Show Icon", "showIcon", "Shows the currency icon next to the amount."),
                    MkToggleOn(
                        "Show Description",
                        "showDescription",
                        "Shows the currency's description text in the tooltip. Turn off for a compact tooltip with just the name and the amount."
                    ),
                }
            elseif block.type == "crests" then
                typeRowList = {
                    -- Placeholder: the checklist dropdown swaps into this slot
                    -- after the row loop (crestListRow capture), same idiom as
                    -- the gold tooltip checklist.
                    {
                        type = "dropdown",
                        text = "Crests Shown",
                        tooltip = "Which of the season's crests this block shows.",
                        values = { __placeholder = "..." },
                        order = { "__placeholder" },
                        getValue = function() return "__placeholder" end,
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
                            local val = cfg.separator
                            if val == nil then val = "slash" end
                            return val
                        end,
                        setValue = SFieldThen("separator"),
                    },
                    MkToggleOn("Show Icons", "showIcons", "Shows each crest's icon in front of its amount."),
                    -- Not an addition but a SWAP: the leading number stops
                    -- being the spendable amount and becomes the season total.
                    -- The tooltip always shows both, so it stays the reference.
                    ToggleRow(
                        "Show Season Progress",
                        "showSeasonProgress",
                        "Replaces the spendable amount with the crests you have earned this season, out of the season cap. The tooltip lists both numbers side by side."
                    ),
                    ToggleRow(
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
                            if cfg.reverse == true then return "desc" end
                            return "asc"
                        end,
                        setValue = function(val)
                            cfg.reverse = (val == "desc")
                            ApplyBar()
                        end,
                    },
                }
            elseif block.type == "bags" then
                -- Show Icon rides the Icon Color row's right slot above.
                typeRowList = {
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
                    ToggleRow(
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
                            local wasOn = (cfg.lowThreshold or 0) > 0
                            cfg.lowThreshold = val
                            ApplyBar()
                            -- Swatch enable state flips only when crossing zero.
                            if wasOn ~= (val > 0) then CUI:RefreshPage() end
                        end,
                    },
                }
            elseif block.type == "mplussummary" then
                typeRowList = {
                    ToggleRow(
                        "Hide When Empty",
                        "hideWhenEmpty",
                        "Removes the block from the bar until a Mythic+ run has been recorded."
                    ),
                }
            elseif block.type == "timeplayed" then
                typeRowList = {
                    ToggleRow(
                        "Always Show Total",
                        "alwaysTotal",
                        "Shows this character's total time played instead of the time played at the current level."
                    ),
                }
            elseif block.type == "ilvl" then
                -- Prefix rides the Icon Color row's right slot above.
                typeRowList = {
                    {
                        type = "segmented",
                        text = "Item Level",
                        tooltip = "Equipped counts your worn gear. Total also counts upgrades sitting in your bags.",
                        values = { equipped = "Equipped", total = "Total", both = "Both" },
                        order = { "equipped", "total", "both" },
                        getValue = function()
                            local val = cfg.value
                            if val == nil then val = "equipped" end
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
                            local profile = cfg.precision
                            if profile == nil then profile = 0 end
                            return profile
                        end,
                        setValue = SFieldThen("precision"),
                    },
                }
            elseif block.type == "ldb" then
                -- Rebuilt on every page draw, never cached: plugins register on
                -- their own schedule and some only appear once their addon has
                -- finished loading.
                local lValues, lOrder = mod.BuildLDBList()
                lValues._noLoc = true
                lValues._menuOpts = { searchable = true, itemHeight = 26 }
                lValues[""] = Loc("Select a plugin")
                table.insert(lOrder, 1, "")
                -- A source whose addon is not loaded this session still has to
                -- read as the current pick: an empty-looking dropdown invites a
                -- change the player never meant to make, and the block itself is
                -- only collapsed, not unconfigured.
                if cfg.source and not lValues[cfg.source] then
                    lValues[cfg.source] = cfg.source .. " |cff808080(" .. Loc("not loaded") .. ")|r"
                    lOrder[#lOrder + 1] = cfg.source
                end
                typeRowList = {
                    {
                        type = "dropdown",
                        text = "Plugin",
                        tooltip = "Any LibDataBroker plugin registered right now. One block per plugin -- add the block again for a second one.",
                        values = lValues,
                        order = lOrder,
                        getValue = SFieldOr("source", ""),
                        setValue = function(val)
                            if val == "" then
                                cfg.source = nil
                            else
                                cfg.source = val
                            end
                            ApplyBar()
                        end,
                    },
                    MkToggleOn("Show Icon", "showIcon", "Shows the plugin's own icon next to its text."),
                    MkToggleOn(
                        "Show Text",
                        "showText",
                        "Shows the plugin's text. Off leaves an icon-only block that still carries the plugin's tooltip and clicks."
                    ),
                    ToggleRow("Show Label", "showLabel", "Prefixes the plugin's own name to its text."),
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
                                cfg.maxWidth = nil
                            else
                                cfg.maxWidth = val
                            end
                            ApplyBar()
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
            if mod.BlockHasIconStyle(block.type) then
                iconStyleCfg = {
                    type = "segmented",
                    text = "Icon Style",
                    values = { custom = "Custom", wow = "Blizzard" },
                    order = { "custom", "wow" },
                    -- Item Level shows its icon only as the "Icon" prefix.
                    disabled = function()
                        if block.type == "ilvl" then return cfg.prefix ~= "icon" end
                        if block.type == "gold" then return cfg.showIcons == false end
                        return cfg.showIcon == false
                    end,
                    disabledTooltip = block.type == "ilvl" and "Prefix: Icon" or "Show Icon",
                    getValue = SFieldOr("iconStyle", "custom"),
                    setValue = function(val)
                        cfg.iconStyle = val
                        ApplyBar()
                        -- Rebuild: the icon color swatches depend on the style.
                        CUI:RefreshPage(true)
                    end,
                }
                if block.type ~= "micromenu" then typeRowList[#typeRowList + 1] = iconStyleCfg end
            end
            for keyName = 1, #typeRowList, 2 do
                local rightCfg = typeRowList[keyName + 1]
                if not rightCfg then rightCfg = { type = "label", text = "" } end
                row, height = W:DualRow(hostFrame, cursorY, typeRowList[keyName], rightCfg)
                cursorY = cursorY - height
                -- Travel: the first three rows hold the click dropdowns on their left.
                if travelClickDD and keyName <= 5 then
                    travelClickDD[(keyName + 1) / 2] = row._leftRegion._control
                end
                if block.type == "supplies" and keyName == 1 and not CUI._prebuilding then
                    local regionFrame = row._leftRegion
                    if regionFrame._control then regionFrame._control:Hide() end
                    local dropdown, refresh = CUI.BuildVisOptsCBDropdown(
                        regionFrame,
                        210,
                        regionFrame:GetFrameLevel() + 2,
                        mod.ClassResourceChoices,
                        function(barKey) return mod.ClassResourceShown(cfg, barKey) end,
                        function(barKey, value)
                            cfg.hiddenItems = cfg.hiddenItems or {}
                            cfg.hiddenItems[barKey] = not value
                            ApplyBar()
                        end,
                        nil,
                        10,
                        true
                    )
                    CUI.PanelPP.Point(dropdown, "RIGHT", regionFrame, "RIGHT", -20, 0)
                    regionFrame._control = dropdown
                    regionFrame._lastInline = nil
                    if refresh then CUI.RegisterWidgetRefresh(refresh) end
                    hostFrame._edbClickTargets["block:" .. blockId .. ":resources"] =
                        { section = secHdr, target = row, slotSide = "left" }
                end
                -- Latency: the Show Icon toggle rides this row's right slot and
                -- carries the inline icon-color swatches built after the loop.
                if block.type == "ms" and keyName == 1 then msIconRow = row end
                -- Gold: Show Tooltip Data rides the Coin Icons row's right slot.
                if block.type == "gold" and keyName == 3 then goldTipRow = row end
                -- Crests: the Crests Shown checklist heads the type rows, so
                -- its placeholder is this row's LEFT slot.
                if block.type == "crests" and keyName == 1 then crestListRow = row end
                -- Bags: Low Space Warning heads the second row (left slot).
                if block.type == "bags" and keyName == 3 then bagsLowRow = row end
                -- Deep-link target for an unconfigured currency block: clicking
                -- its "Select a currency" placeholder on the live bar lands on
                -- the picker itself, not just the section (ns.OpenBlockSettings).
                -- k == 1 IS the Currency dropdown: it heads the currency
                -- typeRows built above. Prepend a row there and retarget here.
                if block.type == "currency" and keyName == 1 then
                    hostFrame._edbClickTargets["block:" .. blockId .. ":currency"] = {
                        section = secHdr,
                        target = row,
                        slotSide = "left",
                        -- Pulse until the player actually picks one.
                        holdWhile = function() return cfg.currencyId == nil end,
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
                if block.type == "ldb" and keyName == 1 then
                    hostFrame._edbClickTargets["block:" .. blockId .. ":ldb"] = {
                        section = secHdr,
                        target = row,
                        slotSide = "left",
                        holdWhile = function() return cfg.source == nil end,
                    }
                end
                if block.type == "location" and keyName == 1 then
                    hostFrame._edbClickTargets["block:" .. blockId .. ":maxwidth"] = {
                        section = secHdr,
                        target = row,
                        slotSide = "right",
                        holdWhile = function() return _edbWidthPulse[block] == true end,
                    }
                end
            end

            -- Latency icon color: the same Custom / Class / Accent trio as the
            -- Text Color row above, inline on Show Icon instead of a row of its
            -- own (the block has one icon set, not a second colorable element).
            -- Stores on the shared per-block icon keys that IconColorOf already
            -- reads, so nothing stored = Custom white, matching the block's
            -- untinted default -- no migration and no new default key.
            if msIconRow and not CUI._prebuilding then
                local region = msIconRow._rightRegion
                local anchor = region._control
                local function IconOn() return cfg.showIcon == true end
                local function FlagsOff()
                    return not block.useIconClassColor
                        and not block.useIconAccentColor
                        and not block.useIconDefaultColor
                end
                local function ClearIconFlags()
                    block.useIconClassColor = nil
                    block.useIconAccentColor = nil
                    block.useIconDefaultColor = nil
                end

                -- Built right-to-left off the toggle so they read
                -- Custom | Class | Accent left-to-right, like Text Color.
                local specs = {
                    {
                        tip = "Accent Color",
                        get = function() return mod.GetAccent() end,
                        click = function()
                            ClearIconFlags()
                            block.useIconAccentColor = true
                            ReflowBar()
                            CUI:RefreshPage()
                        end,
                        on = function() return block.useIconAccentColor == true end,
                    },
                    {
                        tip = "Class Colored",
                        get = function()
                            local _, class = UnitClass("player")
                            local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                            if classColor then return classColor.r, classColor.g, classColor.b end
                            return 1, 1, 1
                        end,
                        click = function()
                            ClearIconFlags()
                            block.useIconClassColor = true
                            ReflowBar()
                            CUI:RefreshPage()
                        end,
                        on = function() return block.useIconClassColor == true end,
                    },
                    {
                        tip = "Custom Color",
                        get = function()
                            local color = block.iconColor
                            if color then return color.r or 1, color.g or 1, color.b or 1 end
                            return 1, 1, 1
                        end,
                        set = function(red, green, blue)
                            block.iconColor = { r = red, g = green, b = blue }
                            ReflowBar()
                        end,
                        -- House multiSwatch convention: a click on an inactive
                        -- custom swatch only selects custom; the picker opens on
                        -- the second click, once custom is already active.
                        click = function(self)
                            if not FlagsOff() then
                                ClearIconFlags()
                                ReflowBar()
                                CUI:RefreshPage()
                                return
                            end
                            if self._eabOrigClick then self._eabOrigClick(self) end
                        end,
                        on = FlagsOff,
                    },
                }

                for i = 1, #specs do
                    local sp = specs[i]
                    local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
                        region,
                        msIconRow:GetFrameLevel() + 3,
                        function()
                            local red, green, blue = sp.get()
                            return red, green, blue, 1
                        end,
                        sp.set or function() end,
                        false,
                        20
                    )
                    colorSwatch._eabOrigClick = colorSwatch:GetScript("OnClick")
                    colorSwatch:SetScript("OnClick", function(self) sp.click(self) end)
                    colorSwatch:HookScript(
                        "OnEnter",
                        function() CUI.ShowWidgetTooltip(colorSwatch, sp.tip) end
                    )
                    colorSwatch:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                    Pix.Point(colorSwatch, "RIGHT", anchor, "LEFT", -8, 0)
                    anchor = colorSwatch

                    -- Blocking overlay while Show Icon is off: the icons are
                    -- not drawn, so their color is not editable.
                    GatedSwatch(
                        colorSwatch,
                        updateSwatch,
                        "Show Icon",
                        10,
                        IconOn,
                        function() return sp.on() and 1 or 0.3 end
                    )
                end
                region._lastInline = anchor
            end

            -- Bags low space color: inline on the threshold slider, disabled
            -- (house pattern) while the threshold is zero.
            if bagsLowRow and not CUI._prebuilding then
                local region = bagsLowRow._leftRegion
                local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
                    region,
                    bagsLowRow:GetFrameLevel() + 3,
                    function()
                        local d = mod.BAGS_LOW_COLOR
                        local color = cfg.lowColor
                        if color then return color.r or d[1], color.g or d[2], color.b or d[3] end
                        return d[1], d[2], d[3]
                    end,
                    function(red, green, blue)
                        cfg.lowColor = { r = red, g = green, b = blue }
                        ApplyBar()
                    end,
                    false,
                    20
                )
                Pix.Point(colorSwatch, "RIGHT", region._control, "LEFT", -8, 0)
                GatedSwatch(
                    colorSwatch,
                    updateSwatch,
                    "Low Space Warning",
                    5,
                    function() return (cfg.lowThreshold or 0) > 0 end
                )
                region._lastInline = colorSwatch
            end

            if block.type == "gold" and goldTipRow then
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
                if not CUI._prebuilding then
                    local rightRegion = goldTipRow._rightRegion
                    if rightRegion._control then rightRegion._control:Hide() end
                    local checkDrop, cbDDRefresh = CUI.BuildVisOptsCBDropdown(
                        rightRegion,
                        210,
                        rightRegion:GetFrameLevel() + 2,
                        GOLD_TIP_ELEMENTS,
                        function(keyName) return cfg[keyName] ~= false end,
                        function(keyName, val)
                            if val then
                                cfg[keyName] = true
                            else
                                cfg[keyName] = false
                            end
                        end
                    )
                    CUI.PanelPP.Point(checkDrop, "RIGHT", rightRegion, "RIGHT", -20, 0)
                    rightRegion._control = checkDrop
                    rightRegion._lastInline = nil
                    if cbDDRefresh then CUI.RegisterWidgetRefresh(cbDDRefresh) end
                end
            end

            if block.type == "crests" and crestListRow then
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
                            if details then name = details.name end
                        end
                        result[i] = { key = c.key, label = name or ("#" .. c.id) }
                    end
                    return result
                end
                if not CUI._prebuilding then
                    local leftRegion = crestListRow._leftRegion
                    if leftRegion._control then leftRegion._control:Hide() end
                    local checkDrop, cbDDRefresh = CUI.BuildVisOptsCBDropdown(
                        leftRegion,
                        210,
                        leftRegion:GetFrameLevel() + 2,
                        CrestElements,
                        function(keyName) return cfg[keyName] ~= false end,
                        function(keyName, val)
                            if val then
                                cfg[keyName] = true
                            else
                                cfg[keyName] = false
                            end
                            ApplyBar()
                        end
                    )
                    CUI.PanelPP.Point(checkDrop, "RIGHT", leftRegion, "RIGHT", -20, 0)
                    leftRegion._control = checkDrop
                    leftRegion._lastInline = nil
                    if cbDDRefresh then CUI.RegisterWidgetRefresh(cbDDRefresh) end
                end
            end

            if block.type == "micromenu" then
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
                if CUI.IS_FOREVER then
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
                mmRow, height = W:DualRow(hostFrame, cursorY, {
                    type = "dropdown",
                    text = "Menu Elements",
                    tooltip = "Which micro menu buttons this block shows, and their order.",
                    values = { __placeholder = "..." },
                    order = { "__placeholder" },
                    getValue = function() return "__placeholder" end,
                    setValue = function() end,
                }, iconStyleCfg or CUI.BlankRowCfg())
                cursorY = cursorY - height
                do
                    local leftRegion = mmRow._leftRegion
                    if leftRegion._control then leftRegion._control:Hide() end
                    -- Rows follow the block's saved button order.
                    local labels, itemList = {}, {}
                    for _, el in ipairs(MM_ELEMENTS) do
                        labels[el.key] = el.label
                    end
                    for _, barKey in ipairs(mod.GetMicroMenuOrder(cfg, {})) do
                        if labels[barKey] then
                            itemList[#itemList + 1] = { key = barKey, label = labels[barKey] }
                        end
                    end
                    local checkDrop, cbDDRefresh = CUI.BuildReorderCBDropdown(
                        leftRegion,
                        210,
                        leftRegion:GetFrameLevel() + 2,
                        itemList,
                        function(keyName) return mod.MicroMenuButtonOn(cfg, keyName) end,
                        function(keyName, val)
                            if val then
                                cfg[keyName] = true
                            else
                                cfg[keyName] = false
                            end
                            ApplyBar()
                        end,
                        {
                            setOrder = function(keyList)
                                mod.SetMicroMenuOrder(cfg, keyList)
                                ApplyBar()
                            end,
                        }
                    )
                    CUI.PanelPP.Point(checkDrop, "RIGHT", leftRegion, "RIGHT", -20, 0)
                    leftRegion._control = checkDrop
                    leftRegion._lastInline = nil
                    if cbDDRefresh then CUI.RegisterWidgetRefresh(cbDDRefresh) end
                end

                local notesRow
                notesRow, height = W:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Show Guild Notes",
                    tooltip = "Shows each online member's public note after their name in the Guild tooltip.",
                    getValue = function() return cfg.showGuildNotes == true end,
                    setValue = function(val)
                        cfg.showGuildNotes = val and true or false
                        ApplyBar()
                        CUI:RefreshPage()
                    end,
                }, CUI.BlankRowCfg())
                cursorY = cursorY - height
                if not CUI._prebuilding then
                    local region = notesRow._leftRegion
                    local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
                        region,
                        notesRow:GetFrameLevel() + 3,
                        function()
                            local color = cfg.guildNoteColor
                            if not color then return 0.925, 0.839, 0.447 end
                            return color.r or 0.925, color.g or 0.839, color.b or 0.447
                        end,
                        function(red, green, blue)
                            cfg.guildNoteColor = { r = red, g = green, b = blue }
                            ApplyBar()
                        end,
                        false,
                        20
                    )
                    Pix.Point(colorSwatch, "RIGHT", region._control, "LEFT", -8, 0)
                    region._lastInline = colorSwatch
                    GatedSwatch(
                        colorSwatch,
                        updateSwatch,
                        "Show Guild Notes",
                        10,
                        function() return cfg.showGuildNotes == true end
                    )
                end
            end

            -- Reordering = drag the segment in the preview strip; removal =
            -- right-click the segment (Remove Block). No body rows for either.
        end

        -- Width % hover highlight: while the cursor is over a block's Width % control
        -- (just that control, not the whole section), wash that block 8 percent white
        -- on BOTH the preview segment and the live bar slot. Poll watcher is parented
        -- to the page wrapper, so it stops (and clears) when the page hides.
        if #blockHoverRegions > 0 and not CUI._prebuilding then
            local watcher = CreateFrame("Frame", nil, hostFrame)
            watcher:SetSize(1, 1)
            local acc = 0
            local curHL
            local function SetHighlight(ident)
                if ident == curHL then return end
                curHL = ident
                if _edbSegHighlightFn then _edbSegHighlightFn(ident) end
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
                if acc < 0.1 then return end
                acc = 0
                if not hostFrame:GetTop() or not hostFrame:IsMouseOver() then
                    SetHighlight(nil)
                    return
                end
                -- The preview header (and the vertical popout) float OVER the scrolled
                -- body, and IsMouseOver is a pure rect test that ignores clipping -- a
                -- control scrolled under the preview would highlight while the cursor
                -- is on the strip. Only count the cursor inside the scroll viewport.
                local scrollFrame = CUI._scrollFrame
                if scrollFrame and not scrollFrame:IsMouseOver() then
                    SetHighlight(nil)
                    return
                end
                local hit
                for keyName = 1, #blockHoverRegions do
                    local hr = blockHoverRegions[keyName]
                    if hr.rgn and hr.rgn:IsMouseOver() then
                        hit = hr.id
                        break
                    end
                end
                SetHighlight(hit)
            end)
            watcher:HookScript("OnHide", function() SetHighlight(nil) end)
        end

        -- Adding blocks lives in the preview strip's "+" tile only -- no body section.
        W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - 20

        -- Every click target of this build is registered by now. Same settle delay the
        -- navigation paths use, and the same pre-build guard: a hidden search pre-build
        -- would steal the shared glow frame for rows nobody can see.
        if not CUI._prebuilding then
            -- A kept page wrapper dressed again by a newer build by then holds
            -- that build's rows, and that build re-arms on its own.
            local gen = Pool.Gen(hostFrame)
            C_Timer.After(0.05, function()
                if Pool.Gen(hostFrame) ~= gen then return end
                RearmHeldGlow()
            end)
        end

        return math.abs(cursorY)
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
            CUI.PrintError("Cannot open options during combat.")
            return
        end
        local barKey = "block:" .. blockId .. ":" .. settingKey
        CUI:NavigateToElementSettings("CludesUIDataBars", PAGE_DATABARS, nil, function()
            local profile = Profile()
            if profile then profile.selectedBarId = barId end
        end)
        -- The click-target map belongs to the page build the call above kicks
        -- off; resolve the scroll target once it has repopulated (same settle
        -- delay NavigateToElementSettings uses for its own section lookup).
        C_Timer.After(0.05, function()
            if _edbNavigateFn then _edbNavigateFn(barKey) end
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
        if barId ~= _edbStripBarId or not (_edbStripRelayout and host and host:IsVisible()) then return end
        -- A reorder drag (the strip's only OnUpdate) owns the segment
        -- positions until it ends.
        if host:GetScript("OnUpdate") then return end
        _edbStripRelayout()
    end

    ---------------------------------------------------------------------------
    --  Module registration
    ---------------------------------------------------------------------------
    CUI:RegisterModule("CludesUIDataBars", {
        title = "Info Bar",
        description = "User-created info bars: clock, gold, XP, micro menu and more.",
        pages = { PAGE_DATABARS },
        buildPage = function(page, hostFrame, yOffset) return BuildDataBarsPage(page, hostFrame, yOffset) end,
        getHeaderBuilder = function(page)
            if page == PAGE_DATABARS then return _edbHeaderBuilder end
            return nil
        end,
        onPageCacheRestore = function(page)
            -- Bars can be resized/width-matched via unlock mode between
            -- visits; re-solve the restored preview from the live cfg.
            if page == PAGE_DATABARS and _edbStripRelayout then _edbStripRelayout() end
        end,
        -- Reset CUI Module Settings' question names the one bar this reset touches.
        resetMessage = function()
            local p = mod.GetProfile()
            local rowConf = p
                and ((p.selectedBarId and mod.GetBar(p.selectedBarId)) or (p.bars and p.bars[1]))
            if not (rowConf and rowConf.name) then return nil end
            return CUI.Lf(
                "Are you sure you want to reset the data bar selected on the Data Bars page (%1$s) to its default look? Its blocks are kept. This will reload your UI.",
                rowConf.name
            )
        end,
        onReset = function()
            -- Resets the SELECTED bar's appearance/behavior to defaults;
            -- keeps its id, name and blocks. Never wipes the bar list.
            -- (Reset CUI Module Settings confirms and reloads for us.)
            local p = mod.GetProfile()
            if not p then return end
            local rowConf = nil
            if p.selectedBarId then rowConf = mod.GetBar(p.selectedBarId) end
            if not rowConf then rowConf = p.bars[1] end
            if not rowConf then return end
            rowConf.orientation = "H"
            rowConf.lengthMode = "custom"
            rowConf.length = 400
            rowConf.thickness = 30
            rowConf.fontScale = 100
            rowConf.theme =
                { style = "cui", cuiAlpha = 0.5, modernColor = { r = 0.067, g = 0.067, b = 0.067, a = 0.95 } }
            rowConf.hideBorder = nil
            rowConf.visibility = "always"
            rowConf.visibilityModes = nil
            rowConf.visibilityMatch = nil
            -- VIS_OPT_KEYS, not VIS_OPT_ITEMS: the counter-lane keys have no row in the
            -- legacy item list, and a reset that skipped them would leave a bar hidden.
            for _, keyName in ipairs(CUI.VIS_OPT_KEYS) do
                rowConf[keyName] = nil
            end
            rowConf.savedPos = nil
            mod.ApplyBar(rowConf.id)
            mod.UpdateAllBarVisibility()
            CUI:InvalidatePageCache()
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
        CUI:ShowModule("CludesUIDataBars")
    end
end)
