if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_SpecOverrides_Popups.lua
--
--  Group icons, the toolbar button and its indicator, group creation, the
--  cards popup and the Conditional Overrides UI.
--  Reads the earlier Spec Overrides files through CUI_NS._soInternals.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)
local Inner = CUI_NS._soInternals
-- CludesUI_SpecOverrides.lua or an earlier Spec Overrides file failed to
-- load.
if not Inner or Inner.broken then return end
Inner.broken = true

local ACCENT_B, ACCENT_G, ACCENT_R = Inner.ACCENT_B, Inner.ACCENT_G, Inner.ACCENT_R
local CLASS_COORDS, CLASS_ORDER, ConflictSpec = Inner.CLASS_COORDS, Inner.CLASS_ORDER, Inner.ConflictSpec
local CurrentSpecID, DeepCopy = Inner.CurrentSpecID, Inner.DeepCopy
local EntryHolderGroup, GetGroups, GetStore = Inner.EntryHolderGroup, Inner.GetGroups, Inner.GetStore
local GLYPH_SPRITE, GroupById, L, LIST_PAGE = Inner.GLYPH_SPRITE, Inner.GroupById, Inner.L, Inner.LIST_PAGE
local MatchOwnedFKey, MODERN_SPRITE = Inner.MatchOwnedFKey, Inner.MODERN_SPRITE
local MULTISPEC_ICON, NextGroupId = Inner.MULTISPEC_ICON, Inner.NextGroupId
local PROFILES_MODULE, RebuildFKeyIndex = Inner.PROFILES_MODULE, Inner.RebuildFKeyIndex
local ROLE_ICONS, ROLE_ORDER, RunRefreshers = Inner.ROLE_ICONS, Inner.ROLE_ORDER, Inner.RunRefreshers
local SpecInAnyGroup, SpecName = Inner.SpecInAnyGroup, Inner.SpecName
local SpecStrandedOnEntry, OwnerGid, Cond = Inner.SpecStrandedOnEntry, Inner.OwnerGid, Inner.Cond
local IsExcludedContext, RequestGoldWalk = Inner.IsExcludedContext, Inner.RequestGoldWalk
local EnsurePanelHideHook, EnterGroupEdit = Inner.EnsurePanelHideHook, Inner.EnterGroupEdit
local ExitGroupEdit, SetUpdateIndicator = Inner.ExitGroupEdit, Inner.SetUpdateIndicator
local SetRefreshCardsPopup = Inner.SetRefreshCardsPopup

-- This file's copies of shared names; Set<Name> keeps every copy current
-- (the lists are built at the end of CludesUI_SpecOverrides.lua).
local _editGroup = nil
Inner.editGroupSetters[#Inner.editGroupSetters + 1] = function(val) _editGroup = val end
local _activeSpec = nil
Inner.activeSpecSetters[#Inner.activeSpecSetters + 1] = function(val) _activeSpec = val end

-- Forward declarations (assigned further down in this file)
local UpdateIndicator, RefreshCardsPopup

-------------------------------------------------------------------------------
--  Group icon rendering
-------------------------------------------------------------------------------
local function ApplyGroupIcon(texture, glyph)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetDesaturated(false)
    texture:SetVertexColor(1, 1, 1, 1)
    if glyph and glyph.kind == "cond" and Cond.ICONS[glyph.key] then
        texture:SetTexture(Cond.ICON_DIR .. Cond.ICONS[glyph.key])
    elseif glyph and glyph.kind == "multi" then
        texture:SetTexture(MULTISPEC_ICON)
    elseif glyph and glyph.kind == "role" and ROLE_ICONS[glyph.key] then
        texture:SetTexture(ROLE_ICONS[glyph.key])
    elseif glyph and glyph.kind == "class" and CLASS_COORDS[glyph.key] then
        texture:SetTexture(MODERN_SPRITE)
        local c = CLASS_COORDS[glyph.key]
        texture:SetTexCoord(c[1], c[2], c[3], c[4])
    else
        -- Default (no group icon): the player's class glyph in natural colors,
        -- matching the toolbar button.
        texture:SetTexture(GLYPH_SPRITE)
        local _, class = UnitClass("player")
        local c = class and CLASS_COORDS[class]
        if c then texture:SetTexCoord(c[1], c[2], c[3], c[4]) end
    end
end
CUI.SpecOverrides_ApplyGroupIcon = ApplyGroupIcon

-- Pages (by module) that list override groups and are rebuilt after a group
-- is renamed, re-specced or deleted; modules add theirs: [module][page] = true.
CUI.SpecOverrides_GroupListingPages = CUI.SpecOverrides_GroupListingPages or {}

-- Forced rebuild of the pages that list override groups: the overrides list
-- page and every page a module registered above.
local function RedrawGroupListing()
    local ap = CUI:GetActivePage()
    local pages = CUI.SpecOverrides_GroupListingPages[CUI:GetActiveModule()]
    if ap == LIST_PAGE or (pages and pages[ap]) then CUI:RefreshPage(true) end
end

-------------------------------------------------------------------------------
--  Toolbar button + active-group indicator
-------------------------------------------------------------------------------
local specButton, indicatorBtn

-- The overrides button keeps ONE identity: its layers mark and the standard
-- tooltip regardless of editing/active state (no icon or tooltip morphing).
-- The second indicator icon stays retired.
UpdateIndicator = function()
    if indicatorBtn then indicatorBtn:Hide() end -- retired second icon
end
SetUpdateIndicator(UpdateIndicator)

--- The toolbar button is DISABLED while the active page is excluded from the
--- override systems (blacklisted module pages, QoL Shifter/Upgrade Calc):
--- dimmed, click refused, explanatory tooltip. Re-evaluated on every
--- module/page selection (called from OnPageRebuilt).
CUI._specOvBtnPageState = function()
    if not specButton then return end
    local off = IsExcludedContext()
    -- Buff Manager page bound to a live fork: block the dropdown entirely (the
    -- page edits that fork no matter what).
    local bmLock = false
    if not off and CUI.SpecOverrides_BmPageLocked then bmLock = CUI.SpecOverrides_BmPageLocked() end
    if not bmLock and not off and CUI.SpecOverrides_DmPageLocked then
        bmLock = CUI.SpecOverrides_DmPageLocked()
    end
    specButton._ovPageDisabled = off or nil
    specButton._ovBmLocked = bmLock or nil
    specButton:SetAlpha((off or bmLock) and 0.35 or 0.9)
end

--- Draws attention to the toolbar glyph: a gold pulsing wash + ring over the
--- button for ~8 pulses, or until it is clicked. Used by the Settings Overrides
--- announcement's "Show Me" landing.
local function StopButtonPulse()
    if specButton and specButton._pulse then
        specButton._pulseAG:Stop()
        specButton._pulse:Hide()
    end
    if specButton and specButton._pulseTip then
        specButton._pulseTipAG:Stop()
        specButton._pulseTip:Hide()
    end
end

function CUI.SpecOverrides_PulseButton()
    if not specButton then return end
    local dialog = specButton._pulse
    if not dialog then
        dialog = CreateFrame("Frame", nil, specButton)
        dialog:SetPoint("TOPLEFT", specButton, "TOPLEFT", -5, 5)
        dialog:SetPoint("BOTTOMRIGHT", specButton, "BOTTOMRIGHT", 5, -5)
        -- Soft gold wash (low alpha so the glyph stays readable) plus a gold
        -- ring; the whole frame's alpha is what pulses.
        local wash = dialog:CreateTexture(nil, "ARTWORK")
        wash:SetAllPoints()
        wash:SetColorTexture(1, 0.82, 0.30, 0.14)
        CUI.MakeBorder(dialog, 1, 0.82, 0.30, 0.9)
        local accG = dialog:CreateAnimationGroup()
        accG:SetLooping("REPEAT")
        local a1 = accG:CreateAnimation("Alpha")
        a1:SetFromAlpha(1)
        a1:SetToAlpha(0.15)
        a1:SetDuration(0.45)
        a1:SetOrder(1)
        a1:SetSmoothing("IN_OUT")
        local a2 = accG:CreateAnimation("Alpha")
        a2:SetFromAlpha(0.15)
        a2:SetToAlpha(1)
        a2:SetDuration(0.45)
        a2:SetOrder(2)
        a2:SetSmoothing("IN_OUT")
        accG:SetScript("OnLoop", function(self)
            self._loops = (self._loops or 0) + 1
            if self._loops >= 8 then StopButtonPulse() end
        end)
        specButton._pulse = dialog
        specButton._pulseAG = accG
    end
    -- Bouncing callout chip below the button: "New Overrides System".
    local tipText = specButton._pulseTip
    if not tipText then
        tipText = CreateFrame("Frame", nil, specButton)
        tipText:SetFrameStrata("DIALOG") -- above the page content below the bar
        local labelFS = CUI.MakeFont(tipText, 12, nil, 1, 0.82, 0.30, 1)
        labelFS:SetPoint("CENTER")
        labelFS:SetText(L("New Overrides System"))
        local wid = (labelFS:GetStringWidth() or 120) + 20
        tipText:SetSize(wid, 24)
        tipText:SetPoint("TOP", specButton, "BOTTOM", 0, -8)
        local tbg = CUI.SolidTex(tipText, "BACKGROUND", 0.062, 0.050, 0.039, 0.95)
        tbg:SetAllPoints()
        CUI.MakeRoundedBorder(tipText, 1, 0.82, 0.30, 0.85, tbg)
        local accG = tipText:CreateAnimationGroup()
        accG:SetLooping("REPEAT")
        local t1 = accG:CreateAnimation("Translation")
        t1:SetOffset(0, -4)
        t1:SetDuration(0.45)
        t1:SetOrder(1)
        t1:SetSmoothing("IN_OUT")
        local t2 = accG:CreateAnimation("Translation")
        t2:SetOffset(0, 4)
        t2:SetDuration(0.45)
        t2:SetOrder(2)
        t2:SetSmoothing("IN_OUT")
        specButton._pulseTip = tipText
        specButton._pulseTipAG = accG
    end
    specButton._pulseAG._loops = 0
    dialog:Show()
    tipText:Show()
    specButton._pulseAG:Play()
    specButton._pulseTipAG:Play()
end

--- Decorates and wires the toolbar button created in the tab bar (main panel).
function CUI.SpecOverrides_SetupButton(button)
    specButton = button
    -- A square chip the height of the search field beside it, drawn in code:
    -- one sheet laid over another (an override sits on top of a setting), the
    -- top sheet in the accent colour.
    button:SetSize(28, 28)
    local backing = CUI.SolidTex(button, "BACKGROUND", 1, 1, 1, 0.04)
    backing:SetAllPoints()
    local brd = CUI.MakeRoundedBorder(button, 1, 1, 1, 0.10, backing, 2)
    button._brd = brd
    local under = button:CreateTexture(nil, "ARTWORK", nil, 1)
    under:SetSize(11, 11)
    under:SetPoint("CENTER", button, "CENTER", 3, 3)
    under:SetColorTexture(1, 1, 1, 0.38)
    local gap = button:CreateTexture(nil, "ARTWORK", nil, 2)
    gap:SetSize(13, 13)
    gap:SetPoint("CENTER", button, "CENTER", -3, -3)
    gap:SetColorTexture(0.07, 0.09, 0.11, 1)
    local texture = button:CreateTexture(nil, "ARTWORK", nil, 3)
    texture:SetSize(11, 11)
    texture:SetPoint("CENTER", button, "CENTER", -3, -3)
    local brandGreen = CUI.CLUDES_GREEN
    texture:SetColorTexture(brandGreen.r, brandGreen.g, brandGreen.b, 1)
    CUI.RegAccent({ type = "solid", obj = texture, a = 1 })
    button._tex = texture
    button:SetAlpha(0.9)
    button:SetScript("OnEnter", function(self)
        if self._ovPageDisabled then
            CUI.ShowWidgetTooltip(self, L("This page is excluded from overrides."))
            return
        end
        if self._ovBmLocked then
            CUI.ShowWidgetTooltip(
                self,
                L(
                    "Overrides are locked: this page's custom Buff Manager is active. Leave the Buff Manager tab to manage overrides."
                )
            )
            return
        end
        self:SetAlpha(1)
        if self._brd then self._brd:SetColor(1, 1, 1, 0.22) end
        CUI.ShowWidgetTooltip(self, L("Settings Overrides"))
    end)
    button:SetScript("OnLeave", function(self)
        if self._brd then self._brd:SetColor(1, 1, 1, 0.10) end
        self:SetAlpha((self._ovPageDisabled or self._ovBmLocked) and 0.35 or 0.9)
        CUI.HideWidgetTooltip()
    end)
    button:SetScript("OnClick", function(self)
        StopButtonPulse() -- attention served the moment it is clicked
        if self._ovPageDisabled then return end
        if self._ovBmLocked then
            -- Blocked: explain at the icon instead of opening the dropdown.
            CUI.ShowWidgetTooltip(
                self,
                L(
                    "Overrides are locked: this page's custom Buff Manager is active. Leave the Buff Manager tab to manage overrides."
                )
            )
            return
        end
        CUI.SpecOverrides_ToggleCardsPopup(self)
    end)
    UpdateIndicator()
    CUI._specOvBtnPageState()
end

-------------------------------------------------------------------------------
--  Group creation: spec picker -> name + icon popup
-------------------------------------------------------------------------------
local nameIconDialog

-- Name + icon popup chrome shared by spec groups and conditional groups: an
-- icon grid built from defs, Create runs onCreate(p). Callers set the title,
-- button label, name text and icon selection on every show.
local function BuildNameIconPopup(groupDefs, onCreate)
    -- Controller cursor: overlay parent (UIParent unless a controller cursor is loaded).
    local dialog = CreateFrame("Frame", nil, CUI.OverlayParent())
    dialog:SetSize(380, 300)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(220)
    dialog:EnableMouse(true)
    local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.062, 0.070, 0.082, 0.97)
    CUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, backdrop)
    local cap = dialog:CreateTexture(nil, "ARTWORK", nil, 3)
    cap:SetPoint("TOPLEFT")
    cap:SetPoint("TOPRIGHT")
    cap:SetHeight(2)
    cap:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.9) -- house look: accent cap

    local title = CUI.MakeFont(dialog, 14, nil, 1, 1, 1, 1)
    title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -16)
    dialog._title = title

    local nameLbl = CUI.MakeFont(dialog, 12, nil, 1, 1, 1, 0.6)
    nameLbl:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -44)
    nameLbl:SetText(L("Name"))

    local nameInput = CreateFrame("EditBox", nil, dialog)
    nameInput:SetSize(340, 26)
    nameInput:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -62)
    nameInput:SetAutoFocus(false)
    nameInput:SetFont(CUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 13, "")
    nameInput:SetTextColor(1, 1, 1, 1)
    nameInput:SetTextInsets(8, 8, 0, 0)
    nameInput:SetMaxLetters(24)
    local nameBoxBg = CUI.SolidTex(nameInput, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    nameBoxBg:SetAllPoints()
    CUI.MakeRoundedBorder(nameInput, 1, 1, 1, 0.12, nameBoxBg)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    dialog._nameBox = nameInput

    local iconLbl = CUI.MakeFont(dialog, 12, nil, 1, 1, 1, 0.6)
    iconLbl:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -102)
    iconLbl:SetText(L("Icon"))

    dialog._iconBtns = {}
    local PER_ROW, SZ, GAP = 8, 34, 8
    for idx, groupDef in ipairs(groupDefs) do
        local col = (idx - 1) % PER_ROW
        local rowI = math.floor((idx - 1) / PER_ROW)
        local widget = CreateFrame("Button", nil, dialog)
        widget:SetSize(SZ, SZ)
        widget:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20 + col * (SZ + GAP), -122 - rowI * (SZ + GAP))
        local tex = widget:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        ApplyGroupIcon(tex, groupDef)
        -- The icon takes the tile's round shape.
        local brd = CUI.MakeRoundedBorder(widget, 1, 1, 1, 0.10, tex)
        widget._def = groupDef
        widget._brd = brd
        widget:SetScript("OnClick", function(self)
            dialog._selectedIcon = self._def
            for _, otherBtn in ipairs(dialog._iconBtns) do
                if otherBtn._brd and otherBtn._brd.SetColor then
                    otherBtn._brd:SetColor(1, 1, 1, otherBtn == self and 0 or 0.10)
                end
                if otherBtn._brd and otherBtn._brd.SetColor and otherBtn == self then
                    otherBtn._brd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
                end
                otherBtn:SetAlpha(otherBtn == self and 1 or 0.7)
            end
        end)
        widget:SetAlpha(0.7)
        dialog._iconBtns[#dialog._iconBtns + 1] = widget
    end

    local create = CreateFrame("Button", nil, dialog)
    create:SetSize(110, 28)
    -- +44 centers the action+cancel pair (110 + 8 gap + 80 = 198 wide).
    create:SetPoint("BOTTOM", dialog, "BOTTOM", 44, 14)
    local createBg = CUI.SolidTex(create, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    createBg:SetAllPoints()
    local cbrd = CUI.MakeRoundedBorder(create, ACCENT_R, ACCENT_G, ACCENT_B, 0.5, createBg)
    local clbl = CUI.MakeFont(create, 12, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
    clbl:SetPoint("CENTER")
    dialog._createLbl = clbl
    create:SetScript("OnEnter", function()
        if cbrd and cbrd.SetColor then cbrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9) end
    end)
    create:SetScript("OnLeave", function()
        if cbrd and cbrd.SetColor then cbrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.5) end
    end)
    create:SetScript("OnClick", function() onCreate(dialog) end)

    local cancelBtn = CreateFrame("Button", nil, dialog)
    cancelBtn:SetSize(80, 28)
    cancelBtn:SetPoint("RIGHT", create, "LEFT", -8, 0)
    local cancelBg = CUI.SolidTex(cancelBtn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    cancelBg:SetAllPoints()
    local xbrd = CUI.MakeRoundedBorder(cancelBtn, 1, 1, 1, 0.22, cancelBg)
    local xlbl = CUI.MakeFont(cancelBtn, 12, nil, 1, 1, 1, 0.7)
    xlbl:SetPoint("CENTER")
    xlbl:SetText(L("Cancel"))
    cancelBtn:SetScript("OnEnter", function()
        if xbrd and xbrd.SetColor then xbrd:SetColor(1, 1, 1, 0.4) end
    end)
    cancelBtn:SetScript("OnLeave", function()
        if xbrd and xbrd.SetColor then xbrd:SetColor(1, 1, 1, 0.22) end
    end)
    cancelBtn:SetScript("OnClick", function() dialog:Hide() end)

    -- Controller cursor: its cancel press backs out through Cancel, and the
    -- panel is a blocker, not a stop.
    if CUI.PadCP() then dialog.CloseButton = cancelBtn end
    CUI.TrackOverlay(dialog)
    CUI.PadHint(dialog, "nodepass")
    return dialog
end

local function ShowNameIconPopup(specIDs, isEditing)
    if not nameIconDialog then
        -- Icon grid: multi-spec + 3 modern role icons + 13 modern class icons
        local groupDefs = { { kind = "multi" } }
        for _, role in ipairs(ROLE_ORDER) do
            groupDefs[#groupDefs + 1] = { kind = "role", key = role }
        end
        for _, cls in ipairs(CLASS_ORDER) do
            groupDefs[#groupDefs + 1] = { kind = "class", key = cls }
        end
        nameIconDialog = BuildNameIconPopup(groupDefs, function(dialog)
            -- EDIT mode: rename/re-icon the existing group (specs were already
            -- applied by the picker's Next step).
            local isEditing = dialog._editing
            if isEditing then
                local label = dialog._nameBox:GetText()
                local changed = false
                if label and label ~= "" and label ~= isEditing.name then
                    isEditing.name = label
                    changed = true
                end
                local sel, current = dialog._selectedIcon, isEditing.icon
                if sel and not (current and current.kind == sel.kind and current.key == sel.key) then
                    isEditing.icon = sel
                    changed = true
                end
                dialog:Hide()
                if UpdateIndicator then UpdateIndicator() end
                if RefreshCardsPopup then RefreshCardsPopup() end
                -- SetGroupSpecs already rebuilt the listing pages; only a new
                -- name or icon needs another rebuild.
                if changed then RedrawGroupListing() end
                return
            end
            local specList = dialog._specs
            if not specList or #specList == 0 then
                dialog:Hide()
                return
            end
            local groupList = GetGroups(true)
            if not groupList then
                dialog:Hide()
                return
            end
            local ident = NextGroupId()
            local label = dialog._nameBox:GetText()
            if not label or label == "" then label = L("Group") .. " " .. ident end
            local group = {
                id = ident,
                name = label,
                icon = dialog._selectedIcon or { kind = "role", key = "DAMAGER" },
                specs = specList,
            }
            groupList[#groupList + 1] = group
            dialog:Hide()
            -- WoW Forever: the new group can move the spec the class acts as.
            -- Apply it before the session opens, so every exit of that session
            -- (and a create the page lock refuses) sees it. While a session is
            -- open this stands down and that session's user exit applies it.
            if CUI.IS_FOREVER then CUI._SO_ForeverConverge() end
            -- Auto-activate: a new group goes straight into its "Editing as"
            -- session. EnterGroupEdit self-guards the BM page lock and tears
            -- down any active session.
            EnterGroupEdit(group)
            if UpdateIndicator then UpdateIndicator() end -- current spec may have joined
            if RefreshCardsPopup then RefreshCardsPopup() end
        end)
        CUI._specOvNamePopup = nameIconDialog -- panel-hide hook closes it (lexical: local declared below the hook)
    end
    nameIconDialog._specs = specIDs
    nameIconDialog._editing = isEditing
    nameIconDialog._title:SetText(
        isEditing and string.format(L("Edit Group: %s"), isEditing.name or "?") or L("New Spec Group")
    )
    nameIconDialog._createLbl:SetText(isEditing and L("Save") or L("Create Group"))
    nameIconDialog._nameBox:SetText(isEditing and (isEditing.name or "") or "")
    nameIconDialog._selectedIcon = nil
    for _, otherBtn in ipairs(nameIconDialog._iconBtns) do
        -- EDIT mode pre-selects the group's current icon.
        local sel = isEditing
                and isEditing.icon
                and otherBtn._def
                and otherBtn._def.kind == isEditing.icon.kind
                and otherBtn._def.key == isEditing.icon.key
            or false
        if sel then nameIconDialog._selectedIcon = otherBtn._def end
        otherBtn:SetAlpha(sel and 1 or 0.7)
        if otherBtn._brd and otherBtn._brd.SetColor then
            if sel then
                otherBtn._brd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
            else
                otherBtn._brd:SetColor(1, 1, 1, 0.10)
            end
        end
    end
    nameIconDialog:Show()
    -- Controller cursor: move it into the popup.
    CUI.PadFocus(nameIconDialog)
end

local function StartGroupCreation()
    if not CUI.ShowSpecAssignPopup then return end
    local dummyDB = { _specOv = { _specs = {} } }
    CUI:ShowSpecAssignPopup({
        db = dummyDB,
        dbKey = "_specOv",
        presetKey = "_specs",
        title = L("New Spec Group"),
        subtitle = L("Select the specs this group edits:"),
        buttonText = L("Next"),
        preCheckedSpecs = {},
        onConfirm = function(assignments)
            -- Specs may belong to multiple groups; settings a shared spec
            -- already overrides in another group are conflict-locked (red)
            -- while editing this one.
            local specList = {}
            for specID, on in pairs(assignments or {}) do
                if on and type(specID) == "number" then specList[#specList + 1] = specID end
            end
            table.sort(specList)
            if #specList == 0 then return end
            ShowNameIconPopup(specList)
        end,
    })
end

-------------------------------------------------------------------------------
--  Cards popup
-------------------------------------------------------------------------------
local cardsDialog

-- Card rows are pooled by position on the popup (parent._cards; parent._cardN is the
-- next one RefreshCardsPopup lays out), and every per-card piece is re-applied here.
local function BuildCardRow(hostFrame, posY, options)
    local cards = hostFrame._cards
    if not cards then
        cards = {}
        hostFrame._cards = cards
    end
    local num = (hostFrame._cardN or 0) + 1
    hostFrame._cardN = num
    local line = cards[num]
    if not line then
        line = CreateFrame("Button", nil, hostFrame)
        local highlight = line:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.05)
        line._brd = CUI.MakeRoundedBorder(line, 1, 1, 1, 0.08, highlight)
        local glyph = line:CreateTexture(nil, "ARTWORK")
        glyph:SetSize(26, 26)
        glyph:SetPoint("LEFT", line, "LEFT", 8, 0)
        line._icon = glyph
        local label = CUI.MakeFont(line, 13, nil, 1, 1, 1, 0.9)
        label:SetPoint("LEFT", glyph, "RIGHT", 10, 0)
        line._nameFS = label
        cards[num] = line
    end
    line:SetSize(hostFrame:GetWidth() - 20, 40)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 10, posY)
    line:SetAlpha(1)
    line:Show()
    local brd = line._brd
    if options.active then
        brd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
    else
        brd:SetColor(1, 1, 1, 0.08)
    end
    local glyph = line._icon
    glyph:SetTexture(nil)
    glyph:SetTexCoord(0, 1, 0, 1)
    glyph:SetDesaturated(false)
    glyph:SetVertexColor(1, 1, 1, 1)
    if options.iconApply then options.iconApply(glyph) end
    local label = line._nameFS
    label:SetTextColor(1, 1, 1, options.dim and 0.55 or 0.9)
    label:SetText(options.name)
    if options.tooltip then
        line:SetScript("OnEnter", function(self) CUI.ShowWidgetTooltip(self, options.tooltip) end)
        line:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
    else
        line:SetScript("OnEnter", nil)
        line:SetScript("OnLeave", nil)
    end
    if options.locked then
        -- BM page lock: not selectable while another override's Buff Manager is
        -- bound to the open page. Dim + inert (tooltip only).
        line:SetAlpha(0.4)
        line:SetScript(
            "OnClick",
            function(self)
                CUI.ShowWidgetTooltip(
                    self,
                    L(
                        "The active override's Buff Manager is bound to the open page. Leave the Buff Manager tab to switch overrides."
                    )
                )
            end
        )
    else
        line:SetScript("OnClick", options.onClick)
    end
    local deleteBtn
    if options.deletable then
        deleteBtn = line._del
        if not deleteBtn then
            deleteBtn = CreateFrame("Button", nil, line)
            deleteBtn:SetSize(20, 20)
            deleteBtn:SetPoint("RIGHT", line, "RIGHT", -6, 1)
            deleteBtn:SetFrameLevel(line:GetFrameLevel() + 2)
            -- Same close glyph the Blizzard window skins use.
            local xt = deleteBtn:CreateTexture(nil, "OVERLAY")
            xt:SetAtlas("uitools-icon-close")
            xt:SetSize(15, 15)
            xt:SetPoint("CENTER", deleteBtn, "CENTER", 0, -2)
            deleteBtn._xt = xt
            deleteBtn:SetScript("OnEnter", function(self)
                xt:SetVertexColor(1, 1, 1, 1)
                CUI.ShowWidgetTooltip(self, L("Delete Override Group"))
            end)
            deleteBtn:SetScript("OnLeave", function()
                xt:SetVertexColor(1, 1, 1, 0.75)
                CUI.HideWidgetTooltip()
            end)
            line._del = deleteBtn
        end
        deleteBtn._xt:SetVertexColor(1, 1, 1, 0.75)
        deleteBtn:SetScript("OnClick", options.onDelete)
        deleteBtn:Show()
    elseif line._del then
        line._del:Hide()
    end
    local editBtn
    if options.onEdit then
        editBtn = line._ed
        if not editBtn then
            editBtn = CreateFrame("Button", nil, line)
            editBtn:SetSize(16, 16)
            editBtn:SetFrameLevel(line:GetFrameLevel() + 2)
            local ico = editBtn:CreateTexture(nil, "OVERLAY")
            ico:SetAllPoints()
            if ico.SetSnapToPixelGrid then
                ico:SetSnapToPixelGrid(false)
                ico:SetTexelSnappingBias(0)
            end
            ico:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-edit.png")
            editBtn:SetScript("OnEnter", function(self)
                self:SetAlpha(1)
                CUI.ShowWidgetTooltip(self, L("Edit Override Group"))
            end)
            editBtn:SetScript("OnLeave", function(self)
                self:SetAlpha(0.75)
                CUI.HideWidgetTooltip()
            end)
            line._ed = editBtn
        end
        editBtn:ClearAllPoints()
        if deleteBtn then
            -- del sits 1px high; -2 relative lands the pencil 1px low on the row.
            editBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -1, -2)
        else
            editBtn:SetPoint("RIGHT", line, "RIGHT", -5, -1)
        end
        editBtn:SetAlpha(0.75)
        editBtn:SetScript("OnClick", options.onEdit)
        editBtn:Show()
    elseif line._ed then
        line._ed:Hide()
    end
    if options.onUnlock then
        local unbindBtn = line._ub
        if not unbindBtn then
            unbindBtn = CreateFrame("Button", nil, line)
            -- Native art is 37x42; keep the aspect ratio at 16px height.
            unbindBtn:SetSize(16 * 37 / 42, 16)
            unbindBtn:SetFrameLevel(line:GetFrameLevel() + 2)
            local ico = unbindBtn:CreateTexture(nil, "OVERLAY")
            ico:SetAllPoints()
            if ico.SetSnapToPixelGrid then
                ico:SetSnapToPixelGrid(false)
                ico:SetTexelSnappingBias(0)
            end
            ico:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-unlocked-small.png")
            line._ub = unbindBtn
        end
        unbindBtn:ClearAllPoints()
        if editBtn then
            -- The pencil sits 1px low; +1 recenters the unlock icon on the row.
            unbindBtn:SetPoint("RIGHT", editBtn, "LEFT", -4, 1)
        elseif deleteBtn then
            unbindBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -4, -1)
        else
            unbindBtn:SetPoint("RIGHT", line, "RIGHT", -8, 0)
        end
        unbindBtn:Show()
        local enabled = options.unlockEnabled
        unbindBtn:SetAlpha(enabled and 0.75 or 0.3)
        unbindBtn:SetScript("OnEnter", function(self)
            if enabled then self:SetAlpha(1) end
            if CUI.ShowWidgetTooltip then
                local tipText
                if enabled then
                    tipText = L("Customize Layout Mode")
                else
                    -- Owner-locked (another group provides this spec's unlock mode) has
                    -- its own text; non-membership gets the switch-spec hint.
                    tipText = options.unlockLockedTooltip
                        or L("Switch to a spec in this group to customize its Layout Mode")
                end
                CUI.ShowWidgetTooltip(self, tipText)
            end
        end)
        unbindBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(enabled and 0.75 or 0.3)
            CUI.HideWidgetTooltip()
        end)
        unbindBtn:SetScript("OnClick", function()
            if enabled then options.onUnlock() end
        end)
    elseif line._ub then
        line._ub:Hide()
    end
    return line, 44
end

-- Seed-map copy for membership adds, MINUS match-owned size keys: a seed member's map
-- can carry stale match-engine widths, and copying them forward replicates the poison
-- onto every spec added to the group. Returns a fresh filtered table per call (never
-- aliases one table across member ids), nil when nothing survives.
local function CopySeedMap(seedMap)
    if not seedMap then return nil end
    local result
    for key, val in pairs(seedMap) do
        if not MatchOwnedFKey(key) then
            result = result or {}
            result[key] = (type(val) == "table") and DeepCopy(val) or val
        end
    end
    return result
end

-- Applies a membership change: ADDED specs receive the group's current override values
-- (copied from the seed member, falling back to the defaults), REMOVED specs lose their
-- stored values (reverting to the baseline on their next apply). The live profile
-- re-syncs immediately so a current-spec join/leave takes effect without a spec swap.
local function SetGroupSpecs(group, newSpecs)
    if _editGroup == group then ExitGroupEdit(true) end
    -- Bank live Buff/Debuff Manager edits into the layer that holds them before
    -- the membership change can move fork ownership (the apply below never harvests).
    CUI.SpecOverrides_HarvestBmLayout()
    CUI.SpecOverrides_HarvestDmLayout()
    local oldSet, newSet = {}, {}
    for _, ident in ipairs(group.specs or {}) do
        oldSet[ident] = true
    end
    for _, ident in ipairs(newSpecs) do
        newSet[ident] = true
    end
    local seed = group.specs and group.specs[1]
    for _, record in ipairs(GetStore() or {}) do
        if record.group == group.id then
            -- capture the group's canonical values BEFORE removals (the seed
            -- member itself may be leaving)
            local seedMap = seed and record.values[seed]
            for ident in pairs(oldSet) do
                if not newSet[ident] then record.values[ident] = nil end
            end
            for _, ident in ipairs(newSpecs) do
                if not oldSet[ident] then
                    -- Seed ONLY from a real member map: a verbatim copy of
                    -- values.default would pin the new member at the CURRENT
                    -- default forever (the sticky harvest retains held values).
                    -- With no map, WriteSpecValues' per-key default fallback
                    -- gives the same live result and keeps following future
                    -- default edits. Match-owned keys are filtered out.
                    record.values[ident] = CopySeedMap(seedMap)
                end
            end
        end
    end
    group.specs = newSpecs
    -- Added specs must receive the group's values EVERYWHERE those values live, not
    -- only on creator-tagged entries: auto-capture binds edits to an existing entry
    -- by slot identity across the WHOLE store, and session exits bank into every
    -- non-conflicting entry, so a group's member values routinely sit on entries it
    -- never created. The owned-entry loop above misses those, leaving the added spec
    -- with NO map there, so WriteSpecValues' per-key default fallback would resolve
    -- it to the shared default at every apply instead ("the override took my live
    -- value" for a joining CURRENT spec). Mirrors HarvestGroup's store-wide scope.
    -- Runs AFTER g.specs = newSpecs so conflicts judge against NEW membership, and
    -- BEFORE the ex-member sweep so a leaving seed member's foreign maps are still
    -- readable. Empty/absent seed maps write NOTHING, so the default fallback keeps
    -- following future edits and a foreign entry's existing legacy data is untouched.
    for _, record in ipairs(GetStore() or {}) do
        if record.group ~= group.id and record.values and not ConflictSpec(record, group) then
            local seedMap = seed and record.values[seed]
            if seedMap and next(seedMap) ~= nil then
                for _, ident in ipairs(newSpecs) do
                    if not oldSet[ident] then
                        -- Fresh filtered copy PER id; nil when only
                        -- match-owned keys existed.
                        local copy = CopySeedMap(seedMap)
                        if copy then record.values[ident] = copy end
                    end
                end
            end
        end
    end
    -- Removed specs must lose their values EVERYWHERE, not only on this group's
    -- creator-tagged entries: session exits bank into every non-conflicting entry
    -- (shared slots), so a removed spec's values can live on another group's
    -- entries the loop above never looked at, leaving the spec overridden forever
    -- while "not assigned" to anything. Only specs left in NO group are cleared; a
    -- spec still in another group keeps its maps (that group's flows re-derive
    -- them). LEGACY entries (group == nil) are exempt: their per-spec values are
    -- user data this group never owned.
    for ident in pairs(oldSet) do
        if not newSet[ident] and not SpecInAnyGroup(ident) then
            for _, record in ipairs(GetStore() or {}) do
                if record.values and record.group ~= nil then record.values[ident] = nil end
            end
        end
    end
    -- Ingress guard for STRANDED values: a removed spec still in ANOTHER group is
    -- skipped by the blanket sweep above, but values THIS group's sessions banked
    -- onto foreign non-conflicting entries stay behind -- and when every group the
    -- spec still belongs to is conflict-locked against that entry's owner, no
    -- session can ever edit or remove them again (permanently pinned off the shared
    -- default, invisible in the list's group buckets). Removing the spec from this
    -- group means "stop overriding it here", so clear exactly those: only entries
    -- this group could reach BEFORE the change (its own swept in the first loop),
    -- and only values stranded under the NEW membership; values another group can
    -- still reach are kept. Pre-existing strays this group never could reach are
    -- untouched -- the management list surfaces those with a Remove control.
    local oldGroupView = { id = group.id, specs = {} }
    for ident in pairs(oldSet) do
        oldGroupView.specs[#oldGroupView.specs + 1] = ident
    end
    for ident in pairs(oldSet) do
        if not newSet[ident] and SpecInAnyGroup(ident) then
            for _, record in ipairs(GetStore() or {}) do
                if
                    record.values
                    and record.values[ident] ~= nil
                    and record.group ~= nil
                    and record.group ~= group.id
                    and not ConflictSpec(record, oldGroupView)
                    and SpecStrandedOnEntry(record, ident)
                then
                    record.values[ident] = nil
                end
            end
        end
    end
    -- WoW Forever: when the new membership moves the spec the class acts as,
    -- the converge banks the live layers and values into the outgoing state,
    -- then applies the new spec (one apply). While an editing session or a
    -- spec transition is open it stands down, and that exit applies it.
    local r = CUI.IS_FOREVER and CurrentSpecID()
    if r and r ~= _activeSpec then
        CUI._SO_ForeverConverge()
    else
        CUI.SpecOverrides_Apply(_activeSpec or CurrentSpecID())
    end
    UpdateIndicator()
    RequestGoldWalk()
    RefreshCardsPopup()
    -- The membership already changed here, even if the name/icon step is cancelled.
    RedrawGroupListing()
end

local function EditGroupSpecs(group)
    if not CUI.ShowSpecAssignPopup then return end
    if cardsDialog then cardsDialog:Hide() end
    local preChecked = {}
    for _, ident in ipairs(group.specs or {}) do
        preChecked[ident] = true
    end
    local dummyDB = { _specOv = { _specs = {} } }
    CUI:ShowSpecAssignPopup({
        db = dummyDB,
        dbKey = "_specOv",
        presetKey = "_specs",
        title = string.format(L("Edit Group: %s"), group.name or "?"),
        subtitle = L("Select the specs this group edits:"),
        buttonText = L("Next"),
        preCheckedSpecs = preChecked,
        onConfirm = function(assignments)
            local specList = {}
            for specID, on in pairs(assignments or {}) do
                if on and type(specID) == "number" then specList[#specList + 1] = specID end
            end
            table.sort(specList)
            SetGroupSpecs(group, specList)
            -- Step 2: name + icon (same screen the creation flow ends on).
            ShowNameIconPopup(nil, group)
        end,
    })
end

RefreshCardsPopup = function()
    local dialog = cardsDialog
    if not dialog or not dialog:IsShown() then return end
    -- The card rows are pooled (BuildCardRow): hide them all, then lay out the
    -- ones this refresh uses again from the first.
    local cards = dialog._cards
    if cards then
        for idx = 1, #cards do
            cards[idx]:Hide()
        end
    end
    dialog._cardN = 0

    local posY = -40
    local function add(_, hgt) posY = posY - hgt end

    -- Default editing mode (exit editing-as). The border tracks the EDITING selection
    -- only (which card's values the panel edits), never the runtime-applied state:
    -- standing in a dungeon must not light the dungeon card while Default is selected.
    add(BuildCardRow(dialog, posY, {
        name = L("Default Editing Mode"),
        active = not _editGroup and not Cond._edit,
        iconApply = function(texture) ApplyGroupIcon(texture, nil) end,
        tooltip = L("Edit normally: changes apply to your current spec"),
        onClick = function()
            ExitGroupEdit()
            if Cond.ExitEdit then Cond.ExitEdit() end
            RefreshCardsPopup()
        end,
    }))

    -- BM page lock: while the Buff Manager page is bound to a live fork,
    -- every group card except the bound one is dimmed and inert.
    local bmLockKind, bmLockGid
    if CUI.SpecOverrides_BmPageLockInfo then
        bmLockKind, bmLockGid = CUI.SpecOverrides_BmPageLockInfo()
    end
    if not bmLockKind and CUI.SpecOverrides_DmPageLockInfo then
        bmLockKind, bmLockGid = CUI.SpecOverrides_DmPageLockInfo()
    end

    -- Saved groups
    local curSpec = CurrentSpecID()
    -- Exclusive unlock-layer ownership: a shared spec's unlock mode belongs to
    -- ONE group (first in creation order with a layout). Every other group's
    -- unlock button is owner-locked for this spec: dimmed with a tooltip naming
    -- the owner (the entry function refuses too; this shows it before a click).
    local curOwnerGid = OwnerGid(curSpec)
    local curOwnerName
    if curOwnerGid then
        local og = GroupById(curOwnerGid)
        curOwnerName = (og and og.name) or "?"
    end
    for _, group in ipairs(GetGroups() or {}) do
        local nameList = {}
        local isMember = false
        for _, ident in ipairs(group.specs or {}) do
            nameList[#nameList + 1] = SpecName(ident)
            if ident == curSpec then isMember = true end
        end
        if CUI.IS_FOREVER then nameList = CUI._SO_ForeverGroupNames(group.specs, curSpec) end
        local ownerLocked = (isMember and curOwnerGid and curOwnerGid ~= group.id) or false
        add(BuildCardRow(dialog, posY, {
            name = group.name or "?",
            active = _editGroup == group,
            locked = (bmLockKind and not (bmLockKind == "spec" and bmLockGid == group.id)) or nil,
            iconApply = function(texture) ApplyGroupIcon(texture, group.icon) end,
            tooltip = table.concat(nameList, "\n"),
            deletable = true,
            unlockEnabled = isMember and not ownerLocked,
            unlockLockedTooltip = ownerLocked
                    and string.format(
                        L(
                            "This spec's custom layout mode is owned by '%s'. Customize it there, or remove the spec from that group."
                        ),
                        curOwnerName
                    )
                or nil,
            onUnlock = function()
                dialog:Hide()
                CUI.SpecOverrides_EnterUnlockForGroup(group)
            end,
            onEdit = function() CUI.SpecOverrides_EditOverrideGroup("spec", group.id) end,
            onClick = function()
                if _editGroup == group then
                    ExitGroupEdit()
                else
                    EnterGroupEdit(group)
                end
                RefreshCardsPopup()
            end,
            onDelete = function()
                CUI:ShowConfirmPopup({
                    title = L("Delete Spec Group"),
                    message = string.format(
                        L(
                            "Delete the group '%s'? Its captured overrides are removed with it; settings keep their current live values."
                        ),
                        group.name or "?"
                    ),
                    confirmText = L("Delete"),
                    cancelText = L("Cancel"),
                    onConfirm = function()
                        if _editGroup == group then ExitGroupEdit(true) end
                        local groupList = GetGroups()
                        if groupList then
                            for idx, gg in ipairs(groupList) do
                                if gg == group then
                                    table.remove(groupList, idx)
                                    break
                                end
                            end
                        end
                        -- The group's overrides go with it (settings keep
                        -- whatever is live; with the panel open that is the
                        -- Default view's baseline).
                        local st = GetStore()
                        if st then
                            -- Values-aware removal: entries CREATED by this group can carry
                            -- OTHER groups' banked values (session exits bank into every
                            -- non-conflicting entry), so deleting wholesale would destroy
                            -- those overrides plus the shared default. RETAG to the first
                            -- surviving group holding values on the entry; delete only when
                            -- none does (the group is already off the list, so
                            -- EntryHolderGroup sees only survivors).
                            for idx = #st, 1, -1 do
                                local e = st[idx]
                                if e.group == group.id then
                                    local holderFrame = EntryHolderGroup(e)
                                    if holderFrame then
                                        e.group = holderFrame.id
                                    else
                                        table.remove(st, idx)
                                    end
                                end
                            end
                            -- Ex-members now in NO group also lose their values on SURVIVING
                            -- entries (other groups' / shared slots): session exits bank into
                            -- every non-conflicting entry, and without this sweep the deleted
                            -- group's values keep applying to its ex-members forever with no
                            -- card or list row showing why. LEGACY entries (group == nil) are
                            -- exempt: user data this group never owned.
                            for _, spellRef in ipairs(group.specs or {}) do
                                if not SpecInAnyGroup(spellRef) then
                                    for _, entry in ipairs(st) do
                                        if entry.values and entry.group ~= nil then
                                            entry.values[spellRef] = nil
                                        end
                                    end
                                end
                            end
                        end
                        -- The group's custom unlock mode goes with it; if it
                        -- was live, the baseline layout is applied back.
                        CUI.SpecOverrides_RemoveUnlockLayout(group.id)
                        -- Same for its custom Buff Manager: otherwise the fork stays
                        -- orphaned AND live, with the BM page and preview showing it
                        -- until a reload's establish heals the dangling pointer.
                        CUI.SpecOverrides_RemoveBmLayout(group.id)
                        CUI.SpecOverrides_RemoveDmLayout(group.id)
                        RebuildFKeyIndex()
                        RequestGoldWalk()
                        -- WoW Forever: the delete can move the spec the class acts as.
                        if CUI.IS_FOREVER then CUI._SO_ForeverConverge() end
                        UpdateIndicator() -- current spec may have been a member
                        RefreshCardsPopup()
                        RedrawGroupListing()
                    end,
                })
            end,
        }))
    end

    -- Add new group
    add(BuildCardRow(dialog, posY, {
        name = L("+ Add New Spec Group"),
        dim = true,
        iconApply = function(texture)
            texture:SetTexture(GLYPH_SPRITE)
            texture:SetTexCoord(0, 0.125, 0, 0.125)
            texture:SetDesaturated(true)
            texture:SetVertexColor(1, 1, 1, 0.25)
        end,
        onClick = function()
            dialog:Hide()
            StartGroupCreation()
        end,
    }))

    -- ---- Conditional Overrides section (one popup, two systems) ----
    -- Centered, matching the "Spec Overrides" title at the top of the popup.
    do
        local heading = dialog._condHdr
        if not heading then
            heading = CreateFrame("Frame", nil, dialog)
            local highlight = CUI.MakeFont(heading, 13, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
            highlight:SetPoint("BOTTOM", heading, "BOTTOM", 0, 4)
            highlight:SetText(L("Conditional Overrides"))
            local sub = CUI.MakeFont(heading, 12, nil, 0.55, 0.55, 0.55, 1)
            sub:SetPoint("TOP", highlight, "BOTTOM", 0, -2)
            sub:SetText(L("(Spec prio'd for settings conflicts)"))
            dialog._condHdr = heading
        end
        heading:SetSize(dialog:GetWidth() - 20, 26)
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", dialog, "TOPLEFT", 10, posY - 6)
        posY = posY - 52
    end

    for _, group in ipairs(CUI.Conditions_GetGroups and CUI.Conditions_GetGroups() or {}) do
        add(BuildCardRow(dialog, posY, {
            -- Border = editing selection only (never the runtime-applied
            -- state); the keybind toggle state gets a text badge.
            name = (group.name or "?")
                .. (
                    group.conds
                        and group.conds.keybind
                        and group.keyOn
                        and ("  |cffc7a65a" .. L("On") .. "|r")
                    or ""
                ),
            active = Cond._edit == group,
            locked = (bmLockKind and not (bmLockKind == "cond" and bmLockGid == group.id)) or nil,
            iconApply = function(texture) ApplyGroupIcon(texture, group.icon) end,
            tooltip = Cond.GroupTooltip(group),
            deletable = true,
            -- Dark Mode groups are values-only: no custom unlock mode can exist
            -- for them, so the button is not built.
            unlockEnabled = not (group.conds and group.conds.darkmode),
            onUnlock = (not (group.conds and group.conds.darkmode)) and function()
                dialog:Hide()
                CUI.Conditions_EnterUnlockForGroup(group)
            end or nil,
            onEdit = function() CUI.SpecOverrides_EditOverrideGroup("cond", group.id) end,
            onClick = function()
                -- Click = editing-as toggle, exactly like spec group cards.
                if Cond._edit == group then
                    Cond.ExitEdit()
                else
                    Cond.EnterEdit(group)
                end
                RefreshCardsPopup()
            end,
            onDelete = function()
                CUI:ShowConfirmPopup({
                    title = L("Delete Conditional Group"),
                    message = string.format(
                        L(
                            "Delete the conditional '%s'? Its captured overrides and custom layout mode are removed with it."
                        ),
                        group.name or "?"
                    ),
                    confirmText = L("Delete"),
                    cancelText = L("Cancel"),
                    onConfirm = function()
                        if Cond._edit == group then Cond.ExitEdit() end
                        local groupList = CUI.Conditions_GetGroups()
                        if groupList then
                            for idx, gg in ipairs(groupList) do
                                if gg == group then
                                    table.remove(groupList, idx)
                                    break
                                end
                            end
                        end
                        local st = Cond.GetStore()
                        if st then
                            -- Put each entry's recorded default back on the live profile
                            -- BEFORE dropping it: while this conditional is applied its
                            -- values ARE the live values (the Default view swap covers the
                            -- spec store only), and a removed entry with no writer left would
                            -- silently leave its values as the profile's settings.
                            -- Value-equal no-op when the group was not applied.
                            local touched = {}
                            for idx = #st, 1, -1 do
                                if st[idx].group == group.id then
                                    Cond.RestoreEntryDefaults(st[idx], touched)
                                    table.remove(st, idx)
                                end
                            end
                            if next(touched) then RunRefreshers(touched) end
                        end
                        Cond.RebuildIndex()
                        CUI.Conditions_RemoveUnlockLayout(group.id)
                        -- The group's custom Buff Manager goes with it; if it was live
                        -- (or session-applied) the runtime layer is applied back, else
                        -- the fork stays orphaned AND live until a reload.
                        CUI.Conditions_RemoveBmLayout(group.id)
                        CUI.Conditions_RemoveDmLayout(group.id)
                        if CUI.Conditions_RebuildKeyBindings then
                            CUI.Conditions_RebuildKeyBindings()
                        end
                        if CUI.Conditions_Recheck then CUI.Conditions_Recheck() end
                        RequestGoldWalk()
                        RefreshCardsPopup()
                        -- FORCED rebuild on EVERY page, not just the management tabs: deleting
                        -- an APPLIED conditional changes live values (default restore above
                        -- plus the transition's writes for surviving entries), so open widgets
                        -- would show the deleted override's values until they re-read. Forced
                        -- because restored values can change page STRUCTURE too.
                        CUI:RefreshPage(true)
                    end,
                })
            end,
        }))
    end

    add(BuildCardRow(dialog, posY, {
        name = L("+ Add New Conditional Group"),
        dim = true,
        iconApply = function(texture)
            texture:SetTexture(Cond.ICON_DIR .. Cond.ICONS.dungeon)
            texture:SetTexCoord(0, 1, 0, 1)
            texture:SetDesaturated(true)
            texture:SetVertexColor(1, 1, 1, 0.25)
        end,
        onClick = function()
            dialog:Hide()
            Cond.ShowPickerPopup(nil)
        end,
    }))

    -- Link to the management list (one link for both systems).
    local itemLink = dialog._link
    if not itemLink then
        itemLink = CreateFrame("Button", nil, dialog)
        local ll = CUI.MakeFont(itemLink, 12, nil, ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
        ll:SetPoint("CENTER")
        ll:SetText(L("View All / Remove Overrides"))
        itemLink._ll = ll
        itemLink:SetScript("OnEnter", function() ll:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1) end)
        itemLink:SetScript("OnLeave", function() ll:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9) end)
        itemLink:SetScript("OnClick", function()
            dialog:Hide()
            -- Profiles & Presets is session-locked (excluded module): leave any
            -- editing session first or the navigation is refused.
            CUI.SpecOverrides_CloseEditSessions()
            CUI:SelectModule(PROFILES_MODULE)
            CUI:SelectPage(LIST_PAGE)
        end)
        dialog._link = itemLink
    end
    itemLink:SetSize(dialog:GetWidth() - 20, 22)
    itemLink:ClearAllPoints()
    itemLink:SetPoint("TOPLEFT", dialog, "TOPLEFT", 10, posY - 2)
    itemLink._ll:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
    posY = posY - 26

    dialog:SetHeight(-posY + 12)
    -- The height lands after the outline's seat: refit so the bottom edge stays sharp.
    if dialog._brd then dialog._brd:Fit() end
end
SetRefreshCardsPopup(RefreshCardsPopup)

function CUI.SpecOverrides_ToggleCardsPopup(anchorBtn)
    if cardsDialog and cardsDialog:IsShown() then
        cardsDialog:Hide()
        return
    end
    if not cardsDialog then
        local dialog = CreateFrame("Frame", nil, CUI._panelBody or UIParent)
        dialog:Hide() -- born hidden so the first Show() fires OnShow (click-off arming)
        dialog:SetSize(280, 100)
        dialog:SetFrameStrata("DIALOG")
        dialog:SetFrameLevel(210)
        dialog:EnableMouse(true)
        dialog:SetClampedToScreen(true)
        local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.062, 0.070, 0.082, 0.99)
        dialog._brd = CUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, backdrop)
        local cap = dialog:CreateTexture(nil, "ARTWORK", nil, 3)
        cap:SetPoint("TOPLEFT")
        cap:SetPoint("TOPRIGHT")
        cap:SetHeight(2)
        cap:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.9) -- house look: accent cap
        local title = CUI.MakeFont(dialog, 13, nil, 1, 1, 1, 1)
        title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 14, -12)
        title:SetText(L("Spec Overrides"):upper())

        -- Click-anywhere-to-close, same pattern as the dropdown widgets: a
        -- global mouse-down listener (non-blocking, world clicks pass through).
        -- Clicks on the spec button / indicator are excluded so their own
        -- OnClick handles the toggle instead of close-then-reopen.
        local clickOff = CreateFrame("Frame")
        clickOff:Hide()
        clickOff:SetScript("OnEvent", function()
            -- A modal dialog (delete confirm / spec picker) owns clicks while
            -- shown; interacting with it must not close the popup.
            local confirmDim = _G.CUIConfirmDimmer
            if confirmDim and confirmDim:IsShown() then return end
            local assignDim = _G.CUISpecAssignDimmer
            if assignDim and assignDim:IsShown() then return end
            if
                dialog:IsShown()
                and not dialog:IsMouseOver()
                and not (specButton and specButton:IsMouseOver())
                and not (indicatorBtn and indicatorBtn:IsShown() and indicatorBtn:IsMouseOver())
            then
                dialog:Hide()
            end
        end)
        dialog:HookScript("OnShow", function()
            -- Defer registration one frame so the mouse-down that opened the
            -- popup does not immediately close it.
            C_Timer.After(0, function()
                if dialog:IsShown() then
                    clickOff:RegisterEvent("GLOBAL_MOUSE_DOWN")
                    clickOff:Show()
                end
            end)
        end)
        dialog:HookScript("OnHide", function()
            clickOff:UnregisterEvent("GLOBAL_MOUSE_DOWN")
            clickOff:Hide()
        end)

        cardsDialog = dialog
        CUI._specOvCardsPopup = dialog
    end
    cardsDialog:ClearAllPoints()
    if anchorBtn then
        cardsDialog:SetPoint("TOPRIGHT", anchorBtn, "BOTTOMRIGHT", 4, -8)
    else
        cardsDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end
    cardsDialog:Show()
    RefreshCardsPopup()
    EnsurePanelHideHook()
end

--- Editing-as toggle for one override group, like clicking its card in the
--- cards popup, but switching directly past the manager page lock (the
--- manager sidebar's override list). kind "spec"|"cond". The lock is only
--- skipped when the target's fork can go live here; otherwise the page would
--- open covered by the "info" overlay, so the lock's popup explains instead.
function CUI.SpecOverrides_ToggleOverrideEdit(kindName, groupId)
    local lockKind, lockGid = CUI.SpecOverrides_BmPageLockInfo()
    if not lockKind then
        lockKind, lockGid = CUI.SpecOverrides_DmPageLockInfo()
    end
    if kindName == "spec" then
        local group = GroupById(groupId)
        if not group then return end
        -- Eligible: a member spec, and no OTHER group owns the live spec fork.
        local current, member = CurrentSpecID(), false
        for _, spellRef in ipairs(group.specs or {}) do
            if spellRef == current then
                member = true
                break
            end
        end
        local force = member and not (lockKind == "spec" and lockGid ~= group.id)
        if _editGroup == group then
            ExitGroupEdit()
        else
            EnterGroupEdit(group, force)
        end
    elseif kindName == "cond" then
        local group = CUI.Conditions_GroupById(groupId)
        if not group then return end
        -- A live spec fork means a spec owner exists, and spec wins.
        local force = lockKind ~= "spec"
        if Cond._edit == group then
            Cond.ExitEdit()
        else
            Cond.EnterEdit(group, force)
        end
    end
    RefreshCardsPopup()
end

--- The cards popup's pencil for one override group (spec: specs, then name and
--- icon; cond: the condition picker), for the manager sidebar's override list.
function CUI.SpecOverrides_EditOverrideGroup(kindName, groupId)
    if kindName == "spec" then
        local group = GroupById(groupId)
        if group then EditGroupSpecs(group) end
    elseif kindName == "cond" then
        local group = CUI.Conditions_GroupById(groupId)
        if not group then return end
        if cardsDialog then cardsDialog:Hide() end
        Cond.ShowPickerPopup(group)
    end
end

-------------------------------------------------------------------------------
--  CONDITIONAL OVERRIDES UI: toolbar button, cards popup, condition picker
--  (with keybind capture), name/icon popup. Mirrors the spec-overrides UI
--  one-for-one; the group icon picker reuses the class/role set.
-------------------------------------------------------------------------------

function Cond.GroupTooltip(group)
    local parts = {}
    for _, groupDef in ipairs(CUI.CONDITIONS or {}) do
        if group.conds and group.conds[groupDef.id] then
            local line = L(groupDef.label)
            if groupDef.id == "keybind" then
                line = line
                    .. ": "
                    .. (
                        group.key and (GetBindingText and GetBindingText(group.key) or group.key)
                        or L("no key set")
                    )
            end
            parts[#parts + 1] = line
        end
    end
    return table.concat(parts, "\n")
end

-- ---- name + icon popup (cond variant; icon grid reuses role/class art) ------
function Cond.ShowNameIconPopup(conds, keyStr, current)
    local dialog = Cond._namePopup
    if not dialog then
        -- Conditional icon set (one per condition), in ladder/display order.
        local groupDefs = {}
        for _, condDef in ipairs(CUI.CONDITIONS or {}) do
            if Cond.ICONS[condDef.id] then groupDefs[#groupDefs + 1] = { kind = "cond", key = condDef.id } end
        end
        dialog = BuildNameIconPopup(groupDefs, function(dialog)
            local conds2 = dialog._conds
            if not conds2 or not next(conds2) then
                dialog:Hide()
                return
            end
            local label = dialog._nameBox:GetText()
            local newGroup
            if dialog._existing then
                local group = dialog._existing
                if label and label ~= "" then group.name = label end
                if dialog._selectedIcon then group.icon = dialog._selectedIcon end
                group.conds = conds2
                group.key = conds2.keybind and dialog._key or nil
                if not conds2.keybind then group.keyOn = nil end
            else
                local groupList = CUI.Conditions_GetGroups(true)
                if not groupList then
                    dialog:Hide()
                    return
                end
                local ident = CUI.Conditions_NewGroupId()
                if not label or label == "" then label = L("Conditional") .. " " .. ident end
                -- Default icon: the first checked condition (ladder order).
                local defIcon = dialog._selectedIcon
                if not defIcon then
                    for _, condDef in ipairs(CUI.CONDITIONS or {}) do
                        if conds2[condDef.id] and Cond.ICONS[condDef.id] then
                            defIcon = { kind = "cond", key = condDef.id }
                            break
                        end
                    end
                end
                newGroup = {
                    id = ident,
                    name = label,
                    icon = defIcon or { kind = "cond", key = "dungeon" },
                    conds = conds2,
                    key = conds2.keybind and dialog._key or nil,
                }
                groupList[#groupList + 1] = newGroup
            end
            dialog:Hide()
            if CUI.Conditions_RebuildKeyBindings then CUI.Conditions_RebuildKeyBindings() end
            if CUI.Conditions_Recheck then CUI.Conditions_Recheck() end
            -- Auto-activate: a new conditional goes straight into its edit
            -- session (matches the spec-group create flow). Cond.EnterEdit
            -- self-guards the BM page lock and any active session.
            if newGroup then Cond.EnterEdit(newGroup) end
            Cond.RefreshCards()
            RedrawGroupListing()
        end)
        Cond._namePopup = dialog
    end
    dialog._conds = conds
    dialog._key = keyStr
    dialog._existing = current
    dialog._title:SetText(current and L("Edit Conditional Group") or L("New Conditional Group"))
    dialog._createLbl:SetText(current and L("Save") or L("Create Group"))
    dialog._nameBox:SetText(current and (current.name or "") or "")
    -- Pre-select the group's saved icon, else the icon matching its first
    -- checked condition (ladder order).
    local wanted
    if current and current.icon then
        wanted = current.icon
    else
        for _, condDef in ipairs(CUI.CONDITIONS or {}) do
            if conds and conds[condDef.id] and Cond.ICONS[condDef.id] then
                wanted = { kind = "cond", key = condDef.id }
                break
            end
        end
    end
    dialog._selectedIcon = nil
    for _, otherBtn in ipairs(dialog._iconBtns) do
        local sel = wanted
            and otherBtn._def
            and wanted.kind == otherBtn._def.kind
            and wanted.key == otherBtn._def.key
        otherBtn:SetAlpha(sel and 1 or 0.7)
        if otherBtn._brd and otherBtn._brd.SetColor then
            if sel then
                otherBtn._brd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
                dialog._selectedIcon = otherBtn._def
            else
                otherBtn._brd:SetColor(1, 1, 1, 0.10)
            end
        end
    end
    dialog:Show()
    -- Controller cursor: move it into the popup.
    CUI.PadFocus(dialog)
end

-- ---- condition picker popup (checklist + keybind capture) -------------------
-- Its key capture uses SetPropagateKeyboardInput, which is blocked in combat on
-- every frame: the picker never opens in combat and closes with the panel
-- (which closes as combat starts). It lets go of the keyboard when it hides out
-- of combat, and on every open.
function Cond.ShowPickerPopup(current)
    if InCombatLockdown() then return end
    EnsurePanelHideHook()
    local dialog = Cond._pickerPopup
    if not dialog then
        -- Controller cursor: overlay parent (UIParent unless a controller cursor is loaded).
        dialog = CreateFrame("Frame", nil, CUI.OverlayParent())
        dialog:SetSize(340, 100)
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(220)
        dialog:EnableMouse(true)
        local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.062, 0.070, 0.082, 0.97)
        dialog._brd = CUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, backdrop)
        local cap = dialog:CreateTexture(nil, "ARTWORK", nil, 3)
        cap:SetPoint("TOPLEFT")
        cap:SetPoint("TOPRIGHT")
        cap:SetHeight(2)
        cap:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.9) -- house look: accent cap

        local title = CUI.MakeFont(dialog, 14, nil, 1, 1, 1, 1)
        title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -14)
        dialog._title = title
        local sub = CUI.MakeFont(dialog, 11, nil, 1, 1, 1, 0.5)
        sub:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -32)
        sub:SetText(L("Select the conditions that activate this group:"))

        dialog._rows = {}
        local posY = -52
        for _, groupDef in ipairs(CUI.CONDITIONS) do
            local line = CreateFrame("Button", nil, dialog)
            line:SetSize(300, 24)
            line:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, posY)
            local box = line:CreateTexture(nil, "ARTWORK")
            box:SetSize(14, 14)
            box:SetPoint("LEFT", line, "LEFT", 0, 0)
            box:SetColorTexture(0.10, 0.10, 0.11, 0.9)
            CUI.RoundBody(line, box)
            local check = line:CreateTexture(nil, "OVERLAY")
            check:SetSize(8, 8)
            check:SetPoint("CENTER", box, "CENTER", 0, 0)
            check:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            CUI.RoundBody(line, check, 1)
            check:Hide()
            local labelFS = CUI.MakeFont(line, 12, nil, 1, 1, 1, groupDef.comingSoon and 0.35 or 0.85)
            labelFS:SetPoint("LEFT", box, "RIGHT", 8, 0)
            labelFS:SetText(
                L(groupDef.label)
                    .. (groupDef.comingSoon and ("  |cff888888" .. L("Coming Soon") .. "|r") or "")
            )
            line._check = check
            line._condID = groupDef.id
            if groupDef.comingSoon then
                line:SetScript(
                    "OnEnter",
                    function(self)
                        CUI.ShowWidgetTooltip(self, L("This condition is coming in a future update."))
                    end
                )
                line:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            elseif groupDef.requires then
                -- Requirement-gated condition (e.g. Dark Mode needs every Dark Mode row
                -- but Class Resource Bar on). CHECKING is refused while unmet;
                -- UNchecking always works, so an existing group can never be trapped
                -- by a requirement that later went false. Dim state is per-open (rows
                -- build once, the popup is reused).
                line._reqFn = groupDef.requires
                line._lbl = labelFS
                line:SetScript("OnClick", function(self)
                    if not dialog._staged[self._condID] and not self._reqFn() then return end
                    dialog._staged[self._condID] = not dialog._staged[self._condID] or nil
                    self._check:SetShown(dialog._staged[self._condID] and true or false)
                    dialog._syncKeyRow()
                    if dialog._refreshReqRows then dialog._refreshReqRows() end
                end)
                line:SetScript("OnEnter", function(self)
                    -- The requirement hint while it would refuse a check, else
                    -- the condition's own tooltip (what keeps it active).
                    local tipText = groupDef.tooltip
                    if not dialog._staged[self._condID] and not self._reqFn() and groupDef.requiresHint then
                        tipText = groupDef.requiresHint
                    end
                    if tipText and CUI.ShowWidgetTooltip then
                        CUI.ShowWidgetTooltip(self, L(tipText))
                    end
                end)
                line:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            else
                line:SetScript("OnClick", function(self)
                    dialog._staged[self._condID] = not dialog._staged[self._condID] or nil
                    self._check:SetShown(dialog._staged[self._condID] and true or false)
                    dialog._syncKeyRow()
                end)
                -- A plain condition with a tooltip (WoW Forever's Gamepad Mode) shows it on hover.
                if groupDef.tooltip then
                    line:SetScript(
                        "OnEnter",
                        function(self) CUI.ShowWidgetTooltip(self, L(groupDef.tooltip)) end
                    )
                    line:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                end
            end
            dialog._rows[#dialog._rows + 1] = line
            posY = posY - 26
        end

        -- Re-evaluated per open and per click: requirement-gated rows dim while
        -- unmet; checked rows stay bright (uncheckable-only, never trapped).
        dialog._refreshReqRows = function()
            for _, r in ipairs(dialog._rows) do
                if r._reqFn and r._lbl then
                    local bright = r._reqFn() or dialog._staged[r._condID]
                    r._lbl:SetAlpha(bright and 1 or 0.4)
                end
            end
        end

        -- Keybind capture row (shown only while the keybind condition is
        -- checked): click, press a key, ESC cancels.
        local keyRow = CreateFrame("Frame", nil, dialog)
        keyRow:SetSize(300, 26)
        keyRow:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, posY - 4)
        local keyLbl = CUI.MakeFont(keyRow, 12, nil, 1, 1, 1, 0.6)
        keyLbl:SetPoint("LEFT", keyRow, "LEFT", 0, 0)
        keyLbl:SetText(L("Toggle Key"))
        local keyBtn = CreateFrame("Button", nil, keyRow)
        keyBtn:SetSize(150, 22)
        keyBtn:SetPoint("LEFT", keyLbl, "RIGHT", 12, 0)
        local keyBtnBg = CUI.SolidTex(keyBtn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        keyBtnBg:SetAllPoints()
        local kbrd = CUI.MakeRoundedBorder(keyBtn, 1, 1, 1, 0.22, keyBtnBg)
        local kl = CUI.MakeFont(keyBtn, 11, nil, 1, 1, 1, 0.85)
        kl:SetPoint("CENTER")
        dialog._keyRow, dialog._keyLblFS = keyRow, kl
        local function SyncKeyText()
            if dialog._capturing then
                kl:SetText(L("Press a key..."))
            elseif dialog._stagedKey then
                kl:SetText(GetBindingText and GetBindingText(dialog._stagedKey) or dialog._stagedKey)
            else
                kl:SetText(L("Click to Set Key"))
            end
        end
        dialog._showKeyText = SyncKeyText
        -- Ends a capture. Its keyboard calls run out of combat only (a hide at
        -- combat start skips them: a hidden popup takes no keys), so every open
        -- releases again.
        local function ReleaseKeys()
            dialog._capturing = false
            if InCombatLockdown() then return end
            dialog:EnableKeyboard(false)
            if dialog.SetPropagateKeyboardInput then dialog:SetPropagateKeyboardInput(true) end
        end
        dialog._releaseKeys = ReleaseKeys
        dialog:SetScript("OnHide", ReleaseKeys)
        keyBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            dialog._capturing = not dialog._capturing
            dialog:EnableKeyboard(dialog._capturing and true or false)
            if dialog.SetPropagateKeyboardInput then
                dialog:SetPropagateKeyboardInput(not dialog._capturing)
            end
            SyncKeyText()
        end)
        dialog:SetScript("OnKeyDown", function(_, key)
            if not dialog._capturing or InCombatLockdown() then return end
            if
                key == "LSHIFT"
                or key == "RSHIFT"
                or key == "LCTRL"
                or key == "RCTRL"
                or key == "LALT"
                or key == "RALT"
            then
                return
            end
            ReleaseKeys()
            -- The key that ends the capture stays here: an Escape that cancels
            -- it must not close the options (and the picker with them). The
            -- keyboard is off now, and the next open restores propagation.
            if dialog.SetPropagateKeyboardInput then dialog:SetPropagateKeyboardInput(false) end
            if key ~= "ESCAPE" then
                local mods = ""
                if IsAltKeyDown() then mods = mods .. "ALT-" end
                if IsControlKeyDown() then mods = mods .. "CTRL-" end
                if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                dialog._stagedKey = mods .. key
            end
            SyncKeyText()
        end)
        local keyClear = CreateFrame("Button", nil, keyRow)
        keyClear:SetSize(20, 20)
        keyClear:SetPoint("LEFT", keyBtn, "RIGHT", 6, 0)
        local kx = CUI.MakeFont(keyClear, 13, nil, 1, 1, 1, 0.6)
        kx:SetPoint("CENTER")
        kx:SetText("x")
        keyClear:SetScript("OnEnter", function() kx:SetTextColor(1, 0.4, 0.4, 1) end)
        keyClear:SetScript("OnLeave", function() kx:SetTextColor(1, 1, 1, 0.6) end)
        keyClear:SetScript("OnClick", function()
            dialog._stagedKey = nil
            SyncKeyText()
        end)

        dialog._syncKeyRow = function()
            keyRow:SetShown(dialog._staged.keybind and true or false)
            local extra = dialog._staged.keybind and 34 or 0
            dialog:SetHeight(-posY + 56 + extra)
            -- Toggled while shown (Keybind checkbox): refit the bottom edge.
            dialog._brd:Fit()
            SyncKeyText()
        end

        local nextBtn = CreateFrame("Button", nil, dialog)
        nextBtn:SetSize(110, 28)
        -- +44 centers the action+cancel pair (110 + 8 gap + 80 = 198 wide).
        nextBtn:SetPoint("BOTTOM", dialog, "BOTTOM", 44, 14)
        local nextBtnBg = CUI.SolidTex(nextBtn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        nextBtnBg:SetAllPoints()
        local nbrd = CUI.MakeRoundedBorder(nextBtn, ACCENT_R, ACCENT_G, ACCENT_B, 0.5, nextBtnBg)
        local nlbl = CUI.MakeFont(nextBtn, 12, nil, ACCENT_R, ACCENT_G, ACCENT_B, 1)
        nlbl:SetPoint("CENTER")
        nlbl:SetText(L("Next"))
        nextBtn:SetScript("OnEnter", function()
            if nbrd and nbrd.SetColor then nbrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9) end
        end)
        nextBtn:SetScript("OnLeave", function()
            if nbrd and nbrd.SetColor then nbrd:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.5) end
        end)
        nextBtn:SetScript("OnClick", function()
            if not next(dialog._staged) then return end
            if dialog._staged.keybind and not dialog._stagedKey then
                CUI.ShowWidgetTooltip(nextBtn, L("Set the toggle key first (or uncheck Keybind)."))
                return
            end
            local conds = {}
            for key, val in pairs(dialog._staged) do
                conds[key] = val
            end
            dialog:Hide()
            Cond.ShowNameIconPopup(conds, dialog._stagedKey, dialog._editing)
        end)

        local cancelBtn = CreateFrame("Button", nil, dialog)
        cancelBtn:SetSize(80, 28)
        cancelBtn:SetPoint("RIGHT", nextBtn, "LEFT", -8, 0)
        local cancelBg = CUI.SolidTex(cancelBtn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
        cancelBg:SetAllPoints()
        local xbrd2 = CUI.MakeRoundedBorder(cancelBtn, 1, 1, 1, 0.22, cancelBg)
        local xlbl2 = CUI.MakeFont(cancelBtn, 12, nil, 1, 1, 1, 0.7)
        xlbl2:SetPoint("CENTER")
        xlbl2:SetText(L("Cancel"))
        cancelBtn:SetScript("OnEnter", function()
            if xbrd2 and xbrd2.SetColor then xbrd2:SetColor(1, 1, 1, 0.4) end
        end)
        cancelBtn:SetScript("OnLeave", function()
            if xbrd2 and xbrd2.SetColor then xbrd2:SetColor(1, 1, 1, 0.22) end
        end)
        -- The OnHide releases a capture in progress.
        cancelBtn:SetScript("OnClick", function() dialog:Hide() end)

        -- Controller cursor: its cancel press backs out through Cancel, and the
        -- panel is a blocker, not a stop.
        if CUI.PadCP() then dialog.CloseButton = cancelBtn end
        CUI.TrackOverlay(dialog)
        CUI.PadHint(dialog, "nodepass")
        Cond._pickerPopup = dialog
    end
    dialog._editing = current
    dialog._staged = {}
    dialog._stagedKey = current and current.key or nil
    dialog._releaseKeys()
    if current and current.conds then
        for key, val in pairs(current.conds) do
            dialog._staged[key] = val
        end
    end
    for _, line in ipairs(dialog._rows) do
        line._check:SetShown(dialog._staged[line._condID] and true or false)
    end
    if dialog._refreshReqRows then dialog._refreshReqRows() end
    dialog._title:SetText(
        current and string.format(L("Edit Conditional: %s"), current.name or "?")
            or L("New Conditional Group")
    )
    dialog._syncKeyRow()
    dialog:Show()
    -- Controller cursor: move it into the popup.
    CUI.PadFocus(dialog)
end

-- ---- cards popup: UNIFIED with the spec overrides popup ----------------------
-- Conditional cards render as a second section inside RefreshCardsPopup; this alias
-- points every cond-side refresh at the one popup.
Cond.RefreshCards = function()
    if RefreshCardsPopup then RefreshCardsPopup() end
end

Inner.broken = false
