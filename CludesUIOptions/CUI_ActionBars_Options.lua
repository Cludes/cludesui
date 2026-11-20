if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBar_Options.lua
--  Registers the Action Bars module. All get/set calls go to EAB.db.profile.
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUIActionBars"
local mod = CludesUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page
-- Options page pool (CludesUI_FramePool.lua, first in this addon): a frame
-- made here on a pool host (a kept page or header root and every frame it
-- hands out) is reset and dressed again by the next build instead of made
-- anew; on any other parent this is CreateFrame. Captured once here.
local CreateFrame = CludesUI._Pool.CreateFrame
-- Keep: an object this file holds across builds leaves the pool. Gen: the
-- dress generation of a pooled object (nil when it is not pooled).
local PoolKeep, PoolGen = CludesUI._Pool.Keep, CludesUI._Pool.Gen
local ABAR = mod.EAB
local VisibilityCompat = ABAR and ABAR.VisibilityCompat
-- Anchor dropdown for the three button texts (keybind / charges / macro name);
-- "default" = stock placement, stored as nil in the profile.
local TEXT_ANCHOR_LABELS = {
    default = "Default",
    TOPLEFT = "Top Left",
    TOP = "Top",
    TOPRIGHT = "Top Right",
    BOTTOMLEFT = "Bottom Left",
    BOTTOM = "Bottom",
    BOTTOMRIGHT = "Bottom Right",
}
local TEXT_ANCHOR_DROPDOWN_ORDER = { "default" }
for idx, a in ipairs(ABAR and ABAR.TEXT_ANCHOR_ORDER or {}) do
    TEXT_ANCHOR_DROPDOWN_ORDER[idx + 1] = a
end

-- The registry offsets/shifts a border renders with when the user has set none
-- (the Border Options cog's shown Shift defaults; the Width/Height Offset row
-- resolves its own): its step's "actionbars" entry, scaled to an exact size
-- (CludesUI.BorderPx) the way ApplyBorderStyle scales it; px nil = the
-- step's own values, the legacy path.
local function ShownBorderDefaults(texture, sizeKey, step, px)
    local dox, doy, dsx, dsy = CludesUI.GetBorderDefaults("actionbars", texture, sizeKey)
    if px then
        local gamePP = CludesUI.PP
        local EDGE_MAP = CludesUI.BORDER_EDGE_MAP
        local f = (px * gamePP.mult) / (EDGE_MAP[step] or EDGE_MAP[1])
        dox, doy, dsx, dsy =
            gamePP.Snap(dox * f), gamePP.Snap(doy * f), gamePP.Snap(dsx * f), gamePP.Snap(dsy * f)
    end
    return dox, doy, dsx, dsy
end

-------------------------------------------------------------------------------
--  Section / page names  (edit here to rename everywhere)
-------------------------------------------------------------------------------
local PAGE_DISPLAY = "Bar Display"
local PAGE_XPBAR = "XP Bar"
local PAGE_MENUBAGSREP = "Menu, Bags & Rep Bars"
local PAGE_ANIMATIONS = "Bar Animations"
local SECTION_ICON_APPEARANCE = "APPEARANCE"
local SECTION_LAYOUT = "LAYOUT"
local SECTION_TEXT = "TEXT"
local SECTION_VISIBILITY = "VISIBILITY & FADING"

-- CludesUI is created by another addon in the suite; wait for it.
CludesUI.AtOptionsLogin(function()
    local Pix = CludesUI.PanelPP
    if not ABAR or not ABAR.db then
        return
    end

    ---------------------------------------------------------------------------
    --  Local references from the addon namespace
    ---------------------------------------------------------------------------
    local BAR_DROPDOWN_VALUES = mod.BAR_DROPDOWN_VALUES
    local BAR_DROPDOWN_ORDER = mod.BAR_DROPDOWN_ORDER
    local VISIBILITY_ONLY = mod.VISIBILITY_ONLY
    local BAR_LOOKUP = mod.BAR_LOOKUP
    local DATA_BAR = mod.DATA_BAR or {}

    -- Filtered bar list for multi-edit: action bars only (no MicroBar/BagBar)
    local GROUP_BAR_ORDER = {}
    for _, key in ipairs(BAR_DROPDOWN_ORDER) do
        if not VISIBILITY_ONLY[key] then
            GROUP_BAR_ORDER[#GROUP_BAR_ORDER + 1] = key
        end
    end

    -- Bar enabled state; we control all bars, so default is true.
    local function IsBarEnabled(barId)
        if not ABAR or not ABAR.db then
            return true
        end
        local s = ABAR.db.profile.bars[barId]
        if s and s.enabled ~= nil then
            return s.enabled
        end
        return true
    end

    local InCombatLockdown = InCombatLockdown
    local pcall = pcall
    local floor = math.floor
    local RANGE_INDICATOR = RANGE_INDICATOR or "\226\128\162"

    ---------------------------------------------------------------------------
    --  Helpers
    ---------------------------------------------------------------------------
    local _selectedBarKey = "MainBar"
    local function SelectedKey()
        return _selectedBarKey
    end

    local function SB()
        return ABAR.db.profile.bars[SelectedKey()] or {}
    end

    local function IsVisOnly()
        return VISIBILITY_ONLY[SelectedKey()]
    end

    local function IsDataBar()
        return DATA_BAR[SelectedKey()]
    end

    -- First button of a bar (source of default size): our EABButton, else the
    -- native Blizzard button. nil for custom bars (Bar9/Bar10) which have no
    -- native button -- callers default the size; avoids concatenating a nil prefix.
    local function FirstBarButton(key)
        local eb = mod.barButtons and mod.barButtons[key]
        if eb and eb[1] then
            return eb[1]
        end
        local bi = BAR_LOOKUP[key]
        if bi and bi.buttonPrefix then
            return _G[bi.buttonPrefix .. "1"]
        end
        return nil
    end

    ---------------------------------------------------------------------------
    --  Ordered dropdown values for the bar selector
    ---------------------------------------------------------------------------
    local barLabels = {}
    local barOrder = {}
    for _, key in ipairs(BAR_DROPDOWN_ORDER) do
        -- XP lives on the "XP Bar" tab and Micro/Bag/Rep/Favor on the "Menu,
        -- Bags & Rep Bars" tab, not the Bar Display bar selector.
        if
            key ~= "MicroBar"
            and key ~= "BagBar"
            and key ~= "XPBar"
            and key ~= "RepBar"
            and key ~= "FavorBar"
        then
            barLabels[key] = BAR_DROPDOWN_VALUES[key]
            barOrder[#barOrder + 1] = key
        end
    end

    -- Unlock Mode "Element Options" pre-selects a bar before the Bar Display page
    -- builds (mirrors the unit-frame path): direct setter (already built) + pending
    -- value consumed at build time. Both ignore non-dropdown keys (Micro/Bag/XP/Rep)
    -- so the selector never blanks.
    CludesUI._setActionBarKey = function(key)
        if barLabels[key] then
            _selectedBarKey = key
        end
    end
    CludesUI._consumePendingActionBarSelect = function()
        local pending = CludesUI._pendingActionBarSelect
        CludesUI._pendingActionBarSelect = nil
        if pending and barLabels[pending] then
            _selectedBarKey = pending
        end
    end

    ---------------------------------------------------------------------------
    --  Edit Overlay System
    --  Non-draggable unlock-mode-style overlay at the real bar position during
    --  Single Bar Edit. XP/Rep: always when selected. BagBar/MicroBar: only
    --  when hidden or mouseover-fade.
    ---------------------------------------------------------------------------
    local EXTRA_BARS = mod.EXTRA_BARS or {}
    local editOverlayFrame = nil -- reusable overlay frame

    local function GetEditOverlayTarget(barId)
        -- Data bars: show overlay only if not using Blizzard data bars
        if DATA_BAR[barId] then
            if ABAR.db.profile.useBlizzardDataBars then
                return nil
            end
            local df = mod.dataBarFrames and mod.dataBarFrames[barId]
            return df
        end
        -- BagBar / MicroBar: show only when hidden or mouseover
        if barId == "BagBar" or barId == "MicroBar" then
            local s = ABAR.db.profile.bars[barId]
            if s and (s.alwaysHidden or s.mouseoverEnabled) then
                for _, details in ipairs(EXTRA_BARS) do
                    if details.key == barId and details.frameName then
                        return _G[details.frameName]
                    end
                end
            end
        end
        return nil
    end

    local function ShowEditOverlay(barId)
        local target = GetEditOverlayTarget(barId)
        if not target then
            if editOverlayFrame then
                editOverlayFrame:Hide()
            end
            return
        end

        if not editOverlayFrame then
            editOverlayFrame = CreateFrame("Frame", "CludesEAB_EditOverlay", UIParent)
            editOverlayFrame:SetFrameStrata("HIGH")
            editOverlayFrame:SetFrameLevel(100)
            editOverlayFrame:EnableMouse(false) -- non-interactive, no dragging

            local backdrop = editOverlayFrame:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(0.088, 0.098, 0.111, 0.85)
            editOverlayFrame._bg = backdrop

            if CludesUI and CludesUI.MakeBorder then
                local brandGreen = CludesUI.CLUDES_GREEN
                local ar, ag, ab = 1, 1, 1
                if brandGreen then
                    ar, ag, ab = brandGreen.r, brandGreen.g, brandGreen.b
                end
                editOverlayFrame._border =
                    CludesUI.MakeBorder(editOverlayFrame, ar, ag, ab, 0.6, CludesUI.PanelPP)
            end

            local label = editOverlayFrame:CreateFontString(nil, "OVERLAY")
            local fontFile = CludesUI and CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
            label:SetFont(fontFile, 10, CludesUI.GetFontOutlineFlag())
            label:SetTextColor(1, 1, 1, 0.75)
            label:SetPoint("CENTER")
            label:SetWordWrap(false)
            editOverlayFrame._label = label
        end

        local s = target:GetEffectiveScale()
        local uiS = UIParent:GetEffectiveScale()
        local wid = (target:GetWidth() or 50) * s / uiS
        local height = (target:GetHeight() or 50) * s / uiS
        editOverlayFrame:SetSize(wid, height)

        local leftX, topY = target:GetLeft(), target:GetTop()
        if leftX and topY then
            local uiH = UIParent:GetHeight()
            local cx = leftX * s / uiS + wid * 0.5
            local cy = topY * s / uiS - height * 0.5
            editOverlayFrame:ClearAllPoints()
            editOverlayFrame:SetPoint("CENTER", UIParent, "TOPLEFT", cx, cy - uiH)
        end

        local labelText = BAR_DROPDOWN_VALUES[barId] or barId
        editOverlayFrame._label:SetText(labelText)
        editOverlayFrame:Show()
    end

    local function HideEditOverlay()
        if editOverlayFrame then
            editOverlayFrame:Hide()
        end
    end

    CludesUI:RegisterOnHide(HideEditOverlay)

    -- Sync Edit Mode icon counts on panel close (numIcons may have changed).
    CludesUI:RegisterOnHide(function()
        ABAR:SyncEditModeIcons()
    end)

    ---------------------------------------------------------------------------
    --  Live Preview System
    --  Child frames are created ONCE; :Update() re-reads DB values and applies
    --  them to the existing objects. Widget callbacks call UpdatePreview(): no
    --  frame creation, no GC pressure, just SetPoint/SetSize/SetColorTexture/
    --  SetTexCoord on already-existing objects.
    ---------------------------------------------------------------------------
    -- Mutable state shared with the page builders under ActionBars_Options\.
    -- A table instead of locals so every file reads and writes the live value.
    -- activePreview: reference to the current preview frame (if any).
    local optionState = {}
    local headerFixedH = 0 -- fixed height in content header (dropdown + label + padding), excluding preview
    local _barsHeaderBuilder -- stored header builder for cache restore
    local _abPreviewHintFS -- hint FontString for Single Bar Edit
    -- The header Bar Display's own builds use, and the header the hint's host
    -- was last moved into (page reuse gives each page a header of its own).
    local _abDisplayHdr, _abHintHdr
    local barsHeaderBaseH = 0 -- bars header height WITHOUT hint

    local function IsPreviewHintDismissed()
        return CludesUIDB and CludesUIDB.previewHintDismissed
    end

    -- Lightweight refresh: re-read settings, update visuals.
    local function UpdatePreview()
        -- Recover activePreview from this module's header preview slot if lost
        -- (e.g. page cache restore)
        if not optionState.activePreview and CludesUI._abHeaderPreview then
            optionState.activePreview = CludesUI._abHeaderPreview
        end
        if optionState.activePreview and optionState.activePreview.Update then
            optionState.activePreview:Update()
        end
    end

    -- Full refresh also recalculates content header height (for bar scale changes)
    local function UpdatePreviewAndResize()
        if not optionState.activePreview and CludesUI._abHeaderPreview then
            optionState.activePreview = CludesUI._abHeaderPreview
        end
        if optionState.activePreview and optionState.activePreview.Update then
            optionState.activePreview:Update()
            if headerFixedH > 0 then
                local hintH = (not IsPreviewHintDismissed()) and 29 or 0
                local wrapH = optionState.activePreview._wrapper
                        and optionState.activePreview._wrapper:GetHeight()
                    or (optionState.activePreview:GetHeight() * optionState.activePreview:GetScale())
                local newTotal = headerFixedH + wrapH + hintH
                CludesUI:UpdateContentHeaderHeight(newTotal)
            end
        end
    end

    CludesUI:RegisterOnShow(UpdatePreview)

    -- Rebuild the preview on spec change (new talent group).
    do
        local specChangeFrame = CreateFrame("Frame")
        specChangeFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        specChangeFrame:SetScript("OnEvent", function(self, evt)
            if evt == "ACTIVE_TALENT_GROUP_CHANGED" and _barsHeaderBuilder then
                optionState.activePreview = nil
                if CludesUI:IsShown() and CludesUI:GetActiveModule() == "CludesUIActionBars" then
                    CludesUI:SetContentHeader(_barsHeaderBuilder)
                    UpdatePreviewAndResize()
                end
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Short labels for sync icon multi-apply
    ---------------------------------------------------------------------------
    local SHORT_LABELS = {
        MainBar = "Bar 1",
        Bar2 = "Bar 2",
        Bar3 = "Bar 3",
        Bar4 = "Bar 4",
        Bar5 = "Bar 5",
        Bar6 = "Bar 6",
        Bar7 = "Bar 7",
        Bar8 = "Bar 8",
        StanceBar = "Stance",
        PetBar = "Pet",
        MicroBar = "Micro",
        BagBar = "Bags",
        XPBar = "XP",
        RepBar = "Rep",
        FavorBar = "Favor",
    }

    -- Spec Overrides capture: label captured entries with the selected bar's element (e.g. "Action Bars > Bar 1 > ...").
    CludesUI.RegisterCaptureContext("CludesUIActionBars", function()
        local key = SelectedKey()
        return SHORT_LABELS[key] or key
    end)

    -- Legacy boolean flags and the visibility-mode dropdown must stay in sync: the runtime reads both shapes.
    local function GetVisibilityKey(s)
        if not VisibilityCompat then
            return s.barVisibility or "always"
        end
        return VisibilityCompat.Normalize(s)
    end

    local function ApplyVisibilityKey(s, value)
        if VisibilityCompat then
            VisibilityCompat.ApplyMode(s, value)
            return
        end

        s.barVisibility = value
        s.alwaysHidden = (value == "never")

        local wasMouseover = s.mouseoverEnabled
        s.mouseoverEnabled = (value == "mouseover")
        if value == "mouseover" then
            if not wasMouseover then
                s._savedBarAlpha = s.mouseoverAlpha or 1
            end
            s.mouseoverAlpha = 0
        elseif wasMouseover and s._savedBarAlpha then
            s.mouseoverAlpha = s._savedBarAlpha
            s._savedBarAlpha = nil
        end

        s.combatHideEnabled = (value == "out_of_combat")
        s.combatShowEnabled = (value == "in_combat")
    end

    local function CopyVisibilitySettings(dst, source, dstKey)
        -- The merged Visibility control owns the option booleans too, so every copy
        -- carries them alongside the mode selection.
        local optKeys = CludesUI.VIS_OPT_KEYS
        if optKeys then
            for idx = 1, #optKeys do
                dst[optKeys[idx]] = source[optKeys[idx]] or nil
            end
        end
        if VisibilityCompat then
            -- Pet Bar ignores group modes: strip them from a copied multi-selection.
            VisibilityCompat.Copy(dst, source, dstKey == "PetBar")
            return
        end

        local value = source.barVisibility or "always"
        dst.barVisibility = value
        dst.visibilityMatch = source.visibilityMatch or nil
        dst.alwaysHidden = source.alwaysHidden
        dst.mouseoverEnabled = source.mouseoverEnabled
        dst.mouseoverAlpha = source.mouseoverAlpha
        dst._savedBarAlpha = source._savedBarAlpha
        dst.combatHideEnabled = source.combatHideEnabled
        dst.combatShowEnabled = source.combatShowEnabled
        dst.dragShow = source.dragShow
    end

    -- An End Caps row: the End Caps checklist (Left Endcap / Right Endcap) and
    -- its cog (the CludesUI style's art, size, offsets), per bar through the
    -- runtime's own readers (ns.AB_CapsSides / AB_CapsVal: an unset Action Bar
    -- 1 key reads the profile-wide one, a bar carrying one of bar 1's caps reads
    -- bar 1's). Horizontal bars only: the art sits at the bar's two ends.
    --   o.key()          the bar
    --   o.store()        its settings table
    --   o.label          the row text
    --   o.vertical()     true greys the row
    --   o.write(k, v)    stores cog value v under k (k nil: the checklist has
    --                    already stored both sides) and repaints
    --   o.copyApply(key) repaints another bar after an Apply to All copy
    --   o.syncKeys, o.syncLabels  the Apply to All link's bars (nil = no link)
    local function EndCapsCtl(o)
        local C = {}
        C.stock = CludesUI.BlizzStyle.Get("actionbars") and true or false
        C.forever = C.stock and CludesUI.BlizzStyle.Forever("actionbars")
        C.Vertical = o.vertical
        -- True while the bar shows a cap at neither end.
        function C.Off()
            local l, r = mod.AB_CapsSides(o.key())
            return not (l or r)
        end
        -- The row slot C.Build swaps for the checklist; its label carries the
        -- tooltip and dims on a vertical bar.
        function C.Cfg()
            local classic = CludesUI.BlizzStyle.Active("actionbars") == "classic"
            return {
                type = "dropdown",
                text = o.label,
                tooltip = (not C.stock) and "Which ends of the bar show end cap art; the cog picks the art."
                    or classic and "Which ends of the bar show the gryphons."
                    or "Which ends of the bar show the gryphons or wyverns.",
                values = { __placeholder = "..." },
                order = { "__placeholder" },
                disabled = C.Vertical,
                disabledTooltip = "Vertical Orientation",
                requireState = "disabled",
                getValue = function()
                    return "__placeholder"
                end,
                setValue = function() end,
            }
        end
        -- A bar's whole end cap setting onto bar `dst`, as this bar resolves
        -- it (sides, the CludesUI style's art, size, offsets).
        function C.CopyTo(dst)
            local source = o.key()
            local d = ABAR.db.profile.bars[dst]
            if dst == source or not d then
                return
            end
            d.endCapLeft, d.endCapRight = mod.AB_CapsSides(source)
            if not C.stock then
                d.endCapArt = mod.AB_CapsArt(source)
            end
            local _, dx, dy, sc = mod.AB_CapsTweak(source)
            d.endCapScale, d.endCapOffsetX, d.endCapOffsetY = sc, dx, dy
            o.copyApply(dst)
        end
        function C.Same(key)
            local source = o.key()
            local sl, sr = mod.AB_CapsSides(source)
            local kl, kr = mod.AB_CapsSides(key)
            if sl ~= kl or sr ~= kr then
                return false
            end
            if not (sl or sr) then
                return true
            end
            if not C.stock and mod.AB_CapsArt(source) ~= mod.AB_CapsArt(key) then
                return false
            end
            local _, sx, sy, ss = mod.AB_CapsTweak(source)
            local _, kx, ky, ks = mod.AB_CapsTweak(key)
            return ss == ks and sx == kx and sy == ky
        end
        -- The checklist in `rgn` (a DualRow half built from C.Cfg), its cog
        -- and its Apply to All link.
        function C.Build(region)
            if CludesUI._prebuilding then
                return
            end
            if region._control then
                region._control:Hide()
            end
            local checkDrop, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                region,
                170,
                region:GetFrameLevel() + 2,
                { { key = "L", label = "Left Endcap" }, { key = "R", label = "Right Endcap" } },
                function(keyName)
                    local l, r = mod.AB_CapsSides(o.key())
                    if keyName == "L" then
                        return l
                    end
                    return r
                end,
                function(keyName, value)
                    -- Both sides are written, the untouched one as the bar
                    -- shows it now: a written side never reads a default.
                    local s = o.store()
                    local l, r = mod.AB_CapsSides(o.key())
                    if keyName == "L" then
                        l = value and true or false
                    else
                        r = value and true or false
                    end
                    s.endCapLeft, s.endCapRight = l, r
                    o.write()
                end,
                nil,
                nil,
                nil,
                nil,
                nil,
                -- Spec Overrides see each click as it happens (the slot's capture).
                { notifyWrites = true }
            )
            Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
            region._control = checkDrop
            region._lastInline = nil
            CludesUI.RegisterWidgetRefresh(cbDDRefresh)
            -- The checklist has no disabled state of its own: grey it and
            -- block clicks on a vertical bar (the row label explains).
            local function ApplyCapsDisabled()
                local off = C.Vertical()
                checkDrop:SetAlpha(off and 0.3 or 1)
                checkDrop:EnableMouse(not off)
            end
            ApplyCapsDisabled()
            CludesUI.RegisterWidgetRefresh(ApplyCapsDisabled)

            local rowList = {}
            if not C.stock then
                -- WoW Forever's own art exists only on that client.
                local values = { blizzard = "Modern", classic = "Classic" }
                local sequence = { "blizzard", "classic" }
                if CludesUI.IS_FOREVER then
                    values.forever = "WoW Forever"
                    sequence[#sequence + 1] = "forever"
                end
                rowList[#rowList + 1] = {
                    type = "dropdown",
                    label = "Art",
                    values = values,
                    order = sequence,
                    tooltip = CludesUI.IS_FOREVER
                            and "Modern shows gryphons or wyverns by faction, Classic the vanilla gryphons, WoW Forever this client's own."
                        or "Modern shows gryphons or wyverns by faction, Classic the vanilla gryphons.",
                    get = function()
                        return mod.AB_CapsArt(o.key())
                    end,
                    set = function(value)
                        o.write("endCapArt", value)
                    end,
                }
            end
            rowList[#rowList + 1] = {
                type = "slider",
                label = "Size",
                min = 50,
                max = 200,
                step = 5,
                tooltip = "Percent of the end caps' normal size.",
                get = function()
                    return mod.AB_CapsVal(o.key(), "endCapScale") or 100
                end,
                set = function(value)
                    o.write("endCapScale", value)
                end,
            }
            rowList[#rowList + 1] = {
                type = "slider",
                label = "X Offset",
                min = -100,
                max = 100,
                step = 1,
                tooltip = "Positive values move both end caps away from the bar.",
                get = function()
                    return mod.AB_CapsVal(o.key(), "endCapOffsetX") or 0
                end,
                set = function(value)
                    o.write("endCapOffsetX", value)
                end,
            }
            rowList[#rowList + 1] = {
                type = "slider",
                label = "Y Offset",
                min = -100,
                max = 100,
                step = 1,
                get = function()
                    return mod.AB_CapsVal(o.key(), "endCapOffsetY") or 5
                end,
                set = function(value)
                    o.write("endCapOffsetY", value)
                end,
            }
            CludesUI.BuildInlineCog(region, {
                title = "End Cap Settings",
                disabled = function()
                    return C.Vertical() or C.Off()
                end,
                disabledTooltip = function()
                    if C.Vertical() then
                        return CludesUI.DisabledTooltip("Vertical Orientation", "disabled")
                    end
                    return CludesUI.DisabledTooltip("Left Endcap or Right Endcap")
                end,
                rawTooltip = true,
                rows = rowList,
            })

            if o.syncKeys then
                CludesUI.BuildSyncIcon({
                    region = region,
                    tooltip = "Apply End Caps to all Bars",
                    onClick = function()
                        for _, key in ipairs(o.syncKeys) do
                            C.CopyTo(key)
                        end
                        CludesUI:RefreshPage()
                    end,
                    isSynced = function()
                        for _, key in ipairs(o.syncKeys) do
                            if not C.Same(key) then
                                return false
                            end
                        end
                        return true
                    end,
                    flashTargets = function()
                        return { region }
                    end,
                    multiApply = {
                        elementKeys = o.syncKeys,
                        elementLabels = o.syncLabels,
                        getCurrentKey = function()
                            return o.key()
                        end,
                        onApply = function(checkedKeys)
                            for _, key in ipairs(checkedKeys) do
                                C.CopyTo(key)
                            end
                            CludesUI:RefreshPage()
                        end,
                    },
                })
            end
        end
        return C
    end

    local function BuildSharedBarSettings(hostFrame, cursorY)
        local W = CludesUI.Widgets

        ---------------------------------------------------------------
        --  Unified Get / Set / DB abstraction
        ---------------------------------------------------------------
        local function SGet(key)
            return SB()[key]
        end
        local function SSet(key, val, applyFn)
            SB()[key] = val
            if applyFn then
                applyFn(SelectedKey())
            end
            CludesUI:RefreshPage()
        end
        local function SDB()
            return SB()
        end
        local function SVal(key, default)
            local value = SB()[key]
            return value ~= nil and value or default
        end
        local function SSetColor(key, red, green, blue, a, applyFn)
            SB()[key] = { r = red, g = green, b = blue, a = a }
            if applyFn then
                applyFn(SelectedKey())
            end
            CludesUI:RefreshPage()
        end
        local function SUpdatePreview()
            UpdatePreview()
        end

        -- The stock spacing lives in the offset boxes, not in the placement. A
        -- position pick swaps the old placement's spacing for the new one's on each
        -- axis and keeps whatever the user added on top (Default carries none: its
        -- stock lines hold their own spacing). Opting in, moving between positions
        -- and going back to Default therefore never move the text by the spacing,
        -- whatever the boxes held (a Cropped shape's preset included).
        local function SSeedTextOffsets(kind, anchorKey, oxKey, oyKey, anchor)
            local prev = SVal(anchorKey, nil)
            if prev == anchor then
                return
            end
            local px, py, nx, ny = 0, 0, 0, 0
            if prev then
                px, py = ABAR.StockTextOffsets(kind, prev)
            end
            if anchor then
                nx, ny = ABAR.StockTextOffsets(kind, anchor)
            end
            SB()[oxKey] = SVal(oxKey, 0) - px + nx
            SB()[oyKey] = SVal(oyKey, 0) - py + ny
        end
        local function SUpdatePreviewAndResize()
            UpdatePreviewAndResize()
        end
        hostFrame._showRowDivider = true

        local visOnly = IsVisOnly()
        -- Row / section references for click-navigation
        local iconsSectionHeader, textSectionHeader
        local keybindRow, chargesRow

        local function BgDisabled()
            return not SB().bgEnabled
        end

        -- The sections live in ActionBars_Options\BarVisibilityLayout_Options.lua
        -- (Bar 10 caution, VISIBILITY & FADING, LAYOUT) and BarAppearance_Options.lua
        -- (APPEARANCE, EFFECTS, BEHAVIOR & PAGING, TEXT); the second returns the
        -- rows the click navigation below maps to.
        local context = {
            BgDisabled = BgDisabled,
            SDB = SDB,
            SGet = SGet,
            SSeedTextOffsets = SSeedTextOffsets,
            SSet = SSet,
            SSetColor = SSetColor,
            SUpdatePreview = SUpdatePreview,
            SUpdatePreviewAndResize = SUpdatePreviewAndResize,
            SVal = SVal,
            visOnly = visOnly,
            W = W,
        }
        cursorY = mod.ABO_BuildBarVisibilityLayout(hostFrame, cursorY, context)

        if not visOnly then
            local classColorBorderRow
            cursorY, iconsSectionHeader, textSectionHeader, keybindRow, chargesRow, classColorBorderRow =
                mod.ABO_BuildBarAppearance(hostFrame, cursorY, context)

            -------------------------------------------------------------------
            --  CLICK NAVIGATION
            -------------------------------------------------------------------
            local PlaySettingGlow = CludesUI.MakeSettingGlow({
                color = CludesUI.CLUDES_GREEN,
                thickness = function()
                    return Pix.Scale(2)
                end,
                noSnap = true,
            })

            local clickMappings = {
                icon = { section = iconsSectionHeader, target = classColorBorderRow },
                keybind = { section = textSectionHeader, target = keybindRow, slotSide = "right" },
                charges = { section = textSectionHeader, target = chargesRow, slotSide = "right" },
            }

            local function NavigateToSetting(key)
                local m = clickMappings[key]
                if not m or not m.section or not m.target then
                    return
                end

                CludesUI.DismissPreviewHint(_abPreviewHintFS, barsHeaderBaseH, 29, 17)

                local scrollFrame = CludesUI._scrollFrame
                if not scrollFrame then
                    return
                end
                local _, _, _, _, headerY = m.section:GetPoint(1)
                if not headerY then
                    return
                end
                local scrollPos = math.max(0, math.abs(headerY) - 40)
                CludesUI.SmoothScrollTo(scrollPos)
                local glowTarget = m.target
                if m.slotSide and m.target then
                    local regionFrame = (m.slotSide == "left") and m.target._leftRegion
                        or m.target._rightRegion
                    if regionFrame then
                        glowTarget = regionFrame
                    end
                end
                -- The glow is for the row of the build that was clicked: a row
                -- the page pool dressed again in the meantime (a rebuild) gets none.
                local glowGen = PoolGen(glowTarget)
                C_Timer.After(0.15, function()
                    if PoolGen(glowTarget) ~= glowGen then
                        return
                    end
                    PlaySettingGlow(glowTarget)
                end)
            end

            local hitStyle = { tightText = true }
            local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, options)
                return (
                    CludesUI.CreatePreviewHitOverlay(
                        element,
                        NavigateToSetting,
                        mappingKey,
                        isText,
                        frameLevelOverride,
                        options,
                        hitStyle
                    )
                )
            end

            local textOverlays = {}
            if optionState.activePreview then
                local preview = optionState.activePreview
                local pvButtons = preview._buttons
                local iconLevel = (
                    pvButtons[1] and pvButtons[1].frame and pvButtons[1].frame:GetFrameLevel() or 5
                ) + 10
                local textOnIconLevel = iconLevel + 10
                local iconHlOpts = { hlBehindText = true }
                for idx = 1, preview._barInfo.count do
                    local record = pvButtons[idx]
                    if record and record.frame then
                        CreateHitOverlay(record.frame, "icon", false, iconLevel, iconHlOpts)
                        if record.keybind then
                            textOverlays[#textOverlays + 1] =
                                CreateHitOverlay(record.keybind, "keybind", true, textOnIconLevel)
                        end
                        if record.count then
                            textOverlays[#textOverlays + 1] =
                                CreateHitOverlay(record.count, "charges", true, textOnIconLevel)
                        end
                    end
                end
                preview._textOverlays = textOverlays
            end
        end -- if not visOnly

        return cursorY
    end

    local function BuildBarDisplayPage(page, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local cursorY = yOffset
        local _, height

        optionState.activePreview = nil

        -- Consume any pending bar selection from Element Options navigation.
        if CludesUI._consumePendingActionBarSelect then
            CludesUI._consumePendingActionBarSelect()
        end

        -- Tag every option registered while building this page with the selected bar, so a global-search
        -- jump to a bar-specific setting restores this exact selection first via _setActionBarKey
        -- (full reasoning: the matching _buildingSelector comment in CUI_CooldownManager_Options.lua).
        CludesUI._buildingSelector = { setter = CludesUI._setActionBarKey, key = SelectedKey() }

        ShowEditOverlay(SelectedKey())

        -------------------------------------------------------------------
        --  CONTENT HEADER  (dropdown + preview)
        -------------------------------------------------------------------
        _barsHeaderBuilder = function(heading, hdrW)
            if CludesUI:GetActivePage() == PAGE_DISPLAY then
                _abDisplayHdr = heading
            end
            local PAD = CludesUI.CONTENT_PAD
            local PV_PAD = 10 -- internal padding inside BuildLivePreview
            local fy = -20

            -- Centered dropdown (same pattern as Multi Bar Edit)
            local DD_H = 34
            local availW = hdrW - PAD * 2
            local ddW = 350
            local dropdownBtn, dropCaption = CludesUI.BuildDropdownControl(
                heading,
                ddW,
                heading:GetFrameLevel() + 5,
                barLabels,
                barOrder,
                function()
                    return SelectedKey()
                end,
                function(value)
                    _selectedBarKey = value
                    -- Always force a full rebuild: visibility-only bars and StanceBar share visOnly/dataBar flags, so a conditional misses transitions.
                    -- The rebuild builds this header as well (BuildBarDisplayPage sets it), so no header is built here first.
                    CludesUI:RefreshPage(true)
                    ShowEditOverlay(value)
                end,
                function(key)
                    -- Bar9/Bar10 default to Hidden visibility but must stay selectable so they can be configured -- never show the disabled effect.
                    if key == "Bar9" or key == "Bar10" then
                        return nil
                    end
                    if not IsBarEnabled(key) then
                        return CludesUI.DisabledTooltip("this action bar")
                    end
                end
            )
            -- The Quick Keybind Mode key button sits KB_GAP left of the
            -- dropdown, and the two are centred as one block.
            local KB_GAP = 5
            Pix.Point(dropdownBtn, "TOP", heading, "TOP", (DD_H + KB_GAP) / 2, fy)
            dropdownBtn:SetHeight(DD_H)

            -- Quick Keybind Mode: a square key button in the dropdown's style.
            do
                local kbBtn = CreateFrame("Button", nil, heading)
                Pix.Size(kbBtn, DD_H, DD_H)
                Pix.Point(kbBtn, "RIGHT", dropdownBtn, "LEFT", -KB_GAP, 0)
                kbBtn:SetFrameLevel(heading:GetFrameLevel() + 5)
                CludesUI.MakeStyledButton(kbBtn, "", 13, CludesUI.RD_DD_COLOURS, function()
                    if InCombatLockdown() then
                        return
                    end
                    if not C_AddOns.IsAddOnLoaded("Blizzard_QuickKeybind") then
                        C_AddOns.LoadAddOn("Blizzard_QuickKeybind")
                    end
                    if QuickKeybindFrame then
                        CludesUI.HideWidgetTooltip()
                        CludesUI:Toggle()
                        QuickKeybindFrame:Show()
                    end
                end)
                local kbIcon = kbBtn:CreateTexture(nil, "ARTWORK")
                kbIcon:SetSize(24, 24)
                kbIcon:SetPoint("CENTER")
                if kbIcon.SetSnapToPixelGrid then
                    kbIcon:SetSnapToPixelGrid(false)
                    kbIcon:SetTexelSnappingBias(0)
                end
                kbIcon:SetTexture(CludesUI.MEDIA_PATH .. "icons\\cui-keyboard.png")
                kbIcon:SetAlpha(CludesUI.DD_TXT_A)
                kbBtn:HookScript("OnEnter", function(self)
                    kbIcon:SetAlpha(CludesUI.DD_TXT_HA)
                    CludesUI.ShowWidgetTooltip(self, "Quick Keybind Mode (/kb)")
                end)
                kbBtn:HookScript("OnLeave", function()
                    kbIcon:SetAlpha(CludesUI.DD_TXT_A)
                    CludesUI.HideWidgetTooltip()
                end)
            end
            fy = fy - DD_H - PV_PAD

            local previewH = mod.ABO_BuildLivePreview(heading, fy)
            fy = fy - previewH - PV_PAD

            headerFixedH = 20 + DD_H + PV_PAD + PV_PAD

            if _abPreviewHintFS and not _abPreviewHintFS:GetParent() then
                _abPreviewHintFS = nil
            end
            local hintH = 0
            if not IsPreviewHintDismissed() then
                if not _abPreviewHintFS then
                    local hintHost = CreateFrame("Frame", nil, heading)
                    -- Built once and held by this file across builds (each
                    -- build moves it into its header below): out of the page pool.
                    PoolKeep(hintHost)
                    hintHost:SetAllPoints(heading)
                    _abPreviewHintFS = CludesUI.MakeFont(hintHost, 11, nil, 1, 1, 1)
                    _abPreviewHintFS:SetAlpha(0.45)
                    _abPreviewHintFS:SetText(
                        CludesUI.L("Click elements to scroll to and highlight their options")
                    )
                end
                _abPreviewHintFS:GetParent():SetParent(heading)
                _abHintHdr = heading
                -- The level a new host gets: a header the page pool dressed
                -- again may have raised its kept host on the way.
                _abPreviewHintFS:GetParent():SetFrameLevel(heading:GetFrameLevel() + 1)
                _abPreviewHintFS:GetParent():Show()
                _abPreviewHintFS:ClearAllPoints()
                _abPreviewHintFS:SetPoint("BOTTOM", heading, "BOTTOM", 0, 17)
                _abPreviewHintFS:SetAlpha(0.45)
                _abPreviewHintFS:Show()
                hintH = 29
            elseif _abPreviewHintFS then
                _abPreviewHintFS:Hide()
            end

            barsHeaderBaseH = math.abs(fy)
            return barsHeaderBaseH + hintH
        end
        CludesUI:SetContentHeader(_barsHeaderBuilder)

        -------------------------------------------------------------------
        --  Build shared settings (single mode)
        -------------------------------------------------------------------
        cursorY = BuildSharedBarSettings(hostFrame, cursorY)

        return math.abs(cursorY)
    end

    -- Bar Animations page (ActionBars_Options\AnimationsPage_Options.lua). Called
    -- here so its Custom Proc Glow site registers at the original point in the load order.
    local BuildAnimationsPage = mod.ABO_InitAnimationsPage(Pix, ABAR, PAGE_ANIMATIONS)

    ---------------------------------------------------------------------------
    --  Unlock Mode page  (opens CludesUI Unlock Mode overlay)
    ---------------------------------------------------------------------------
    local function BuildUnlockPage(page, hostFrame, yOffset)
        -- Defer to next frame so the page switch completes first
        C_Timer.After(0, function()
            if mod.OpenUnlockMode then
                mod.OpenUnlockMode()
            end
        end)
        return 0
    end

    -- Shared with the page builders under ActionBars_Options\ (read in their
    -- prologs). Every field is final here: optState holds the mutable state.
    mod._ABO_OptEnv = {
        ApplyVisibilityKey = ApplyVisibilityKey,
        BAR_LOOKUP = BAR_LOOKUP,
        CopyVisibilitySettings = CopyVisibilitySettings,
        EAB = ABAR,
        EndCapsCtl = EndCapsCtl,
        FirstBarButton = FirstBarButton,
        floor = floor,
        GetVisibilityKey = GetVisibilityKey,
        GROUP_BAR_ORDER = GROUP_BAR_ORDER,
        InCombatLockdown = InCombatLockdown,
        IsDataBar = IsDataBar,
        optState = optionState,
        pcall = pcall,
        PP = Pix,
        RANGE_INDICATOR = RANGE_INDICATOR,
        SB = SB,
        SECTION_ICON_APPEARANCE = SECTION_ICON_APPEARANCE,
        SECTION_LAYOUT = SECTION_LAYOUT,
        SECTION_TEXT = SECTION_TEXT,
        SECTION_VISIBILITY = SECTION_VISIBILITY,
        SelectedKey = SelectedKey,
        SHORT_LABELS = SHORT_LABELS,
        ShownBorderDefaults = ShownBorderDefaults,
        TEXT_ANCHOR_DROPDOWN_ORDER = TEXT_ANCHOR_DROPDOWN_ORDER,
        TEXT_ANCHOR_LABELS = TEXT_ANCHOR_LABELS,
    }

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    CludesUI:RegisterModule("CludesUIActionBars", {
        title = "Action Bars",
        description = "Configure visuals and behavior for your action bars.",
        pages = { PAGE_DISPLAY, PAGE_XPBAR, PAGE_MENUBAGSREP, PAGE_ANIMATIONS },
        buildPage = function(page, hostFrame, yOffset)
            -- BuildBarDisplayPage calls ShowEditOverlay() unconditionally at build time, showing a
            -- real UIParent-parented overlay over the live action bars. A hidden search pre-build
            -- would flash it onscreen, so skip PAGE_DISPLAY here; it indexes on first visit.
            if CludesUI._prebuilding then
                if page == PAGE_XPBAR then
                    return mod.ABO_BuildXPBarPage(page, hostFrame, yOffset)
                elseif page == PAGE_MENUBAGSREP then
                    return mod.ABO_BuildMenuBagsRepPage(page, hostFrame, yOffset)
                elseif page == PAGE_ANIMATIONS then
                    return BuildAnimationsPage(page, hostFrame, yOffset)
                end
                return
            end
            if page ~= PAGE_DISPLAY then
                HideEditOverlay()
            end
            if page == PAGE_DISPLAY then
                return BuildBarDisplayPage(page, hostFrame, yOffset)
            elseif page == PAGE_XPBAR then
                return mod.ABO_BuildXPBarPage(page, hostFrame, yOffset)
            elseif page == PAGE_MENUBAGSREP then
                return mod.ABO_BuildMenuBagsRepPage(page, hostFrame, yOffset)
            elseif page == PAGE_ANIMATIONS then
                return BuildAnimationsPage(page, hostFrame, yOffset)
            end
        end,
        getHeaderBuilder = function(page)
            if page == PAGE_DISPLAY then
                return _barsHeaderBuilder
            elseif page == PAGE_XPBAR then
                return mod.ABO_XPHeaderBuilder()
            end
            return nil
        end,
        onPageCacheRestore = function(page)
            if page == PAGE_DISPLAY then
                UpdatePreview()
                ShowEditOverlay(SelectedKey())
                local dismissed = IsPreviewHintDismissed()
                if _abPreviewHintFS then
                    if dismissed then
                        _abPreviewHintFS:Hide()
                    else
                        _abPreviewHintFS:SetAlpha(0.45)
                        _abPreviewHintFS:Show()
                        local host = _abPreviewHintFS:GetParent()
                        if host then
                            -- The spec change handler built a bars header for
                            -- another page and took the host along (page reuse
                            -- gives each page its own header): back into this one.
                            if _abDisplayHdr and _abHintHdr ~= _abDisplayHdr then
                                _abHintHdr = _abDisplayHdr
                                host:SetParent(_abDisplayHdr)
                                host:SetFrameLevel(_abDisplayHdr:GetFrameLevel() + 1)
                                _abPreviewHintFS:ClearAllPoints()
                                _abPreviewHintFS:SetPoint("BOTTOM", _abDisplayHdr, "BOTTOM", 0, 17)
                            end
                            host:Show()
                        end
                    end
                end
                if barsHeaderBaseH > 0 then
                    CludesUI:SetContentHeaderHeightSilent(barsHeaderBaseH + (dismissed and 0 or 29))
                end
            else
                HideEditOverlay()
                if page == PAGE_XPBAR then
                    mod.ABO_XPPreviewRefresh()
                end
            end
        end,
        onReset = function()
            ABAR.db:ResetProfile()
            -- Clear the per-install capture flag: the snapshot re-runs post-reload and re-reads Blizzard's bar layout.
            if ABAR.db and ABAR.db.sv then
                ABAR.db.sv._capturedOnce_EAB = nil
            end
            -- No reload here: Reset CUI Module Settings reloads after this returns.
        end,
    })
end)
