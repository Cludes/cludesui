if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Widgets_AuraPopups.lua
--  Tracked auras and spell blacklist popups shared by the aura filter
--  options. Loads right after CludesUI_Widgets.lua.
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI

-- The options page pool (CludesUI_FramePool.lua, the options addon's first
-- file): each popup below keeps its dimmer (and a named panel) for the session,
-- reset to new on every open, and every frame made under them is handed out
-- again. Captured once here, never read through the public slot later.
local Pool = CludesUI._Pool
local CreateFrame, PoolKept, PoolGen = Pool.CreateFrame, Pool.Kept, Pool.Gen
-- Owner of the popups' kept frames.
local POPUPS = {}

-- Tracked Auras popup: the shared INCLUDED/EXCLUDED spell-list editor (announcement-popup chrome; two tri-state
-- columns with per-column Add buttons; adding an ID to one list removes it from the other). Storage-agnostic --
-- callers pass list accessors and an onChanged applier. Used by the nameplate slot filters and the target/focus/boss unit frame debuff filters.
-- opts = {
--     eyebrow / title    (header strings)
--     subtitle           (optional: one dim line under the title; the header
--                         band and the lists shift down to make room)
--     fontPath           (optional; defaults to the options font)
--     includeGet/excludeGet  -> tri-state map { [spellID] = true|false }
--     includePrompt/excludePrompt  (Add Spell ID popup messages)
--     onChanged          (engine reapply, called after every edit)
--     onAdd(id)          (optional; called on every Add Spell ID, before onChanged)
--     showAll = { label, get, set }        (optional header toggle)
--     copyFrom = { label, choices = { {key=,label=}, ... }, apply(key) }
--                                          (optional header copy row)
--     includeMine = { anyGet } | { mineGet }  (optional: INCLUDED rows carry a MINE tag.
--                                          anyGet(): entries default to your own casts,
--                                          the map holds any-caster OPT-OUTS (boss);
--                                          mineGet(): entries default to any caster,
--                                          the map holds MINE OPT-INS (target/focus))
-- }
-- showAll and copyFrom are mutually exclusive header bands; with neither the list section shifts up and gains the height.
local _trackedAurasDimmer
-- The kept panel (kept apart from the dimmer, which a close hides alone): hidden
-- before the dimmer's reset shows the dimmer again, so the previous open's panel
-- never shows (and runs its old OnShow scripts) on the way to its own reset.
local _trackedAurasPanel
-- Controller Escape/Back (RegisterEscapeClose): the registration outlives the
-- open that made it, so the close reads the frame it is handed.
local function EscapeTrackedAuras(f)
    f:Hide()
    _trackedAurasDimmer = nil
end
local TRACKED_AURAS_ESC = { padOnly = true, onEscape = EscapeTrackedAuras }
function CludesUI.ShowTrackedAurasPopup(options)
    -- The panel's pixel helper, like every popup scaled by GetPopupScale:
    -- the real-UI-scale PP lands 1px borders on fractional pixels here.
    local Pix = CludesUI.PanelPP or CludesUI.PP
    local fontFile = options.fontPath or CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
    local ppScale = (CludesUI.GetPopupScale()) or 1
    local ACC = CludesUI.CLUDES_GREEN

    if _trackedAurasDimmer then
        _trackedAurasDimmer:Hide()
        _trackedAurasDimmer = nil
    end
    if _trackedAurasPanel then
        _trackedAurasPanel:Hide()
    end

    -- Kept hidden: shown below once dressed, so the Escape/Back hooks a named
    -- dimmer keeps through resets run at that show alone, never at the reset.
    local shade = PoolKept(POPUPS, "trackedAuras", "Button", UIParent, nil, "CUITrackedAurasDimmer", true)
    -- This open's dress: a list refresh that arrives from an earlier open (an
    -- Add Spell ID confirm) leaves the rows this open dressed alone.
    local dressGen = PoolGen(shade)
    shade:SetAllPoints(UIParent)
    shade:SetFrameStrata("FULLSCREEN_DIALOG")
    shade:SetScale(ppScale)
    shade:EnableMouseWheel(true)
    shade:SetScript("OnMouseWheel", function() end)
    local size = shade:CreateTexture(nil, "BACKGROUND")
    size:SetAllPoints()
    size:SetColorTexture(0, 0, 0, 0.35)
    shade:SetScript("OnClick", function()
        shade:Hide()
        _trackedAurasDimmer = nil
    end)
    _trackedAurasDimmer = shade

    local panelFrame = PoolKept(POPUPS, "trackedAurasPanel", "Frame", shade, nil, "CUITrackedAurasPopup")
    _trackedAurasPanel = panelFrame
    panelFrame:SetSize(520, 470)
    panelFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    panelFrame:SetFrameLevel(shade:GetFrameLevel() + 10)
    panelFrame:EnableMouse(true)
    local pbg = panelFrame:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    pbg:SetColorTexture(0.062, 0.070, 0.082, 1)
    -- One-physical-pixel border (announcement-popup chrome): four edge textures, snap disabled, scale-derived thickness.
    do
        local onePhys = 1 / (panelFrame:GetEffectiveScale() or 1)
        local function Edge()
            local t = panelFrame:CreateTexture(nil, "BORDER")
            t:SetColorTexture(1, 1, 1, 0.15)
            if t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false)
                t:SetTexelSnappingBias(0)
            end
            return t
        end
        local eT = Edge()
        eT:SetPoint("TOPLEFT", 0, 0)
        eT:SetPoint("TOPRIGHT", 0, 0)
        eT:SetHeight(onePhys)
        local eB = Edge()
        eB:SetPoint("BOTTOMLEFT", 0, 0)
        eB:SetPoint("BOTTOMRIGHT", 0, 0)
        eB:SetHeight(onePhys)
        local eL = Edge()
        eL:SetPoint("TOPLEFT", eT, "BOTTOMLEFT")
        eL:SetPoint("BOTTOMLEFT", eB, "TOPLEFT")
        eL:SetWidth(onePhys)
        local eR = Edge()
        eR:SetPoint("TOPRIGHT", eT, "BOTTOMRIGHT")
        eR:SetPoint("BOTTOMRIGHT", eB, "TOPRIGHT")
        eR:SetWidth(onePhys)
    end
    -- Header: accent eyebrow + large title (announcement style).
    local eyebrow = panelFrame:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(fontFile, 11, "")
    eyebrow:SetPoint("TOP", panelFrame, "TOP", 0, -16)
    eyebrow:SetTextColor(ACC.r, ACC.g, ACC.b, 0.9)
    eyebrow:SetText(CludesUI.L(options.eyebrow or "TRACKED AURAS"))
    local title = panelFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontFile, 20, "")
    title:SetPoint("TOP", panelFrame, "TOP", 0, -32)
    title:SetTextColor(1, 1, 1, 0.95)
    title:SetText(CludesUI.L(options.title or "Tracked Auras"))
    -- Optional one-line description under the title; everything below the
    -- header (band + lists) shifts down by hdrY and the panel grows to match.
    local hdrY = 0
    if options.subtitle then
        local subMenu = panelFrame:CreateFontString(nil, "OVERLAY")
        subMenu:SetFont(fontFile, 12, "")
        subMenu:SetPoint("TOP", title, "BOTTOM", 0, -4)
        subMenu:SetWidth(470)
        subMenu:SetJustifyH("CENTER")
        subMenu:SetTextColor(1, 1, 1, 0.6)
        subMenu:SetText(CludesUI.L(options.subtitle))
        hdrY = 18
        panelFrame:SetHeight(470 + hdrY)
    end

    local function ClosePopup()
        shade:Hide()
        _trackedAurasDimmer = nil
    end

    -- Escape closes (consume Escape only; other keys propagate so chat/UI shortcuts keep working behind the dimmer).
    CludesUI.PopupTakeKeys(panelFrame, shade)
    panelFrame:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then
            return
        end
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then
            ClosePopup()
        end
    end)

    -- X close (standard popup chrome: borderless cui-close, top right)
    local closeBtn = CreateFrame("Button", nil, panelFrame)
    closeBtn:SetSize(19, 19)
    closeBtn:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -10, -10)
    local closeTex = closeBtn:CreateTexture(nil, "OVERLAY")
    closeTex:SetAllPoints()
    closeTex:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png")
    closeBtn:SetAlpha(0.5)
    closeBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(0.9)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(0.5)
    end)
    closeBtn:SetScript("OnClick", ClosePopup)

    local RefreshBoth

    -- Header band: the Show All toggle OR the copy-from row (mutually exclusive by contract; with neither the list section shifts up).
    if options.showAll then
        local sa = options.showAll
        local tog = CreateFrame("Button", nil, panelFrame)
        tog:SetSize(170, 20)
        tog:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 24, -68 - hdrY)
        local boxFrame = CreateFrame("Frame", nil, tog)
        boxFrame:SetSize(16, 16)
        boxFrame:SetPoint("LEFT", tog, "LEFT", 0, 0)
        local bbg = boxFrame:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints()
        bbg:SetColorTexture(0.114, 0.106, 0.099, 1)
        local bbrd = CludesUI.MakeRoundedBorder(boxFrame, 0.4, 0.4, 0.4, 0.6, bbg)
        local chk = boxFrame:CreateTexture(nil, "ARTWORK")
        Pix.SetInside(chk, boxFrame, 2, 2)
        chk:SetColorTexture(ACC.r, ACC.g, ACC.b, 1)
        CludesUI.RoundBody(boxFrame, chk, 2)
        local tl = tog:CreateFontString(nil, "OVERLAY")
        tl:SetFont(fontFile, 13, "")
        tl:SetPoint("LEFT", boxFrame, "RIGHT", 8, 0)
        tl:SetTextColor(0.85, 0.85, 0.85)
        tl:SetText(CludesUI.L(sa.label or "Show All"))
        local function UpdAll()
            if PoolGen(shade) ~= dressGen then
                return
            end
            local enabled = sa.get() == true
            chk:SetShown(enabled)
            if bbrd and bbrd.SetColor then
                if enabled then
                    bbrd:SetColor(ACC.r, ACC.g, ACC.b, 0.8)
                else
                    bbrd:SetColor(0.4, 0.4, 0.4, 0.6)
                end
            end
        end
        tog:SetScript("OnClick", function()
            sa.set(not (sa.get() == true))
            UpdAll()
        end)
        UpdAll()
    elseif options.copyFrom then
        local castFrame = options.copyFrom
        local labelFS = panelFrame:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont(fontFile, 12, "")
        labelFS:SetPoint("LEFT", panelFrame, "TOPLEFT", 24, -80 - hdrY)
        labelFS:SetTextColor(0.85, 0.85, 0.85)
        labelFS:SetText(CludesUI.L(castFrame.label or "Copy From:"))

        -- Apply (rightmost), source dropdown to its left.
        local applyBtn = CreateFrame("Button", nil, panelFrame)
        applyBtn:SetSize(64, 24)
        applyBtn:SetPoint("RIGHT", panelFrame, "TOPRIGHT", -24, -80 - hdrY)
        local apBg = applyBtn:CreateTexture(nil, "BACKGROUND")
        apBg:SetAllPoints()
        apBg:SetColorTexture(0.062, 0.070, 0.082, 0.92)
        local apBrd = CludesUI.MakeRoundedBorder(applyBtn, ACC.r, ACC.g, ACC.b, 0.35, apBg)
        local apLbl = applyBtn:CreateFontString(nil, "OVERLAY")
        apLbl:SetFont(fontFile, 12, "")
        apLbl:SetPoint("CENTER")
        apLbl:SetTextColor(ACC.r, ACC.g, ACC.b, 0.7)
        apLbl:SetText(CludesUI.L("Apply"))
        applyBtn:SetScript("OnEnter", function()
            apLbl:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
            if apBrd and apBrd.SetColor then
                apBrd:SetColor(ACC.r, ACC.g, ACC.b, 0.8)
            end
        end)
        applyBtn:SetScript("OnLeave", function()
            apLbl:SetTextColor(ACC.r, ACC.g, ACC.b, 0.7)
            if apBrd and apBrd.SetColor then
                apBrd:SetColor(ACC.r, ACC.g, ACC.b, 0.35)
            end
        end)

        local dropdownBtn = CreateFrame("Button", nil, panelFrame)
        dropdownBtn:SetSize(110, 24)
        dropdownBtn:SetPoint("RIGHT", applyBtn, "LEFT", -8, 0)
        local ddBg = dropdownBtn:CreateTexture(nil, "BACKGROUND")
        ddBg:SetAllPoints()
        ddBg:SetColorTexture(0.114, 0.106, 0.099, 1)
        CludesUI.MakeRoundedBorder(dropdownBtn, 0.4, 0.4, 0.4, 0.6, ddBg)
        local dropCaption = dropdownBtn:CreateFontString(nil, "OVERLAY")
        dropCaption:SetFont(fontFile, 12, "")
        dropCaption:SetPoint("LEFT", dropdownBtn, "LEFT", 8, 0)
        dropCaption:SetPoint("RIGHT", dropdownBtn, "RIGHT", -18, 0)
        dropCaption:SetJustifyH("LEFT")
        dropCaption:SetWordWrap(false)
        dropCaption:SetTextColor(1, 1, 1, 0.8)
        dropCaption:SetText(CludesUI.L("Select..."))
        CludesUI.MakeDropdownArrow(dropdownBtn, 10, Pix)

        local chosen
        local dropMenu = CreateFrame("Frame", nil, panelFrame)
        dropMenu:SetFrameLevel(panelFrame:GetFrameLevel() + 20)
        dropMenu:SetPoint("TOPLEFT", dropdownBtn, "BOTTOMLEFT", 0, -2)
        dropMenu:SetSize(110, #castFrame.choices * 22 + 8)
        local mBg = dropMenu:CreateTexture(nil, "BACKGROUND")
        mBg:SetAllPoints()
        mBg:SetColorTexture(0.062, 0.070, 0.082, 0.98)
        CludesUI.MakeRoundedBorder(dropMenu, 1, 1, 1, 0.15, mBg, nil, true)
        dropMenu:Hide()
        for idx = 1, #castFrame.choices do
            local choice = castFrame.choices[idx]
            local mrow = CreateFrame("Button", nil, dropMenu)
            mrow:SetHeight(22)
            mrow:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -4 - (idx - 1) * 22)
            mrow:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -4 - (idx - 1) * 22)
            local highlight = mrow:CreateTexture(nil, "BACKGROUND")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0)
            local rl = mrow:CreateFontString(nil, "OVERLAY")
            rl:SetFont(fontFile, 12, "")
            rl:SetPoint("LEFT", mrow, "LEFT", 8, 0)
            rl:SetTextColor(0.85, 0.85, 0.85)
            rl:SetText(CludesUI.L(choice.label))
            mrow:SetScript("OnEnter", function()
                highlight:SetColorTexture(1, 1, 1, 0.06)
            end)
            mrow:SetScript("OnLeave", function()
                highlight:SetColorTexture(1, 1, 1, 0)
            end)
            mrow:SetScript("OnClick", function()
                chosen = choice.key
                dropCaption:SetText(CludesUI.L(choice.label))
                dropCaption:SetTextColor(1, 1, 1, 1)
                dropMenu:Hide()
            end)
        end
        dropdownBtn:SetScript("OnClick", function()
            dropMenu:SetShown(not dropMenu:IsShown())
        end)
        -- Controller cursor: Cancel inside the list clicks the button (closing just the list).
        if CludesUI.PadCP() then
            dropMenu.CloseButton = dropdownBtn
        end

        applyBtn:SetScript("OnClick", function()
            if not chosen then
                return
            end
            castFrame.apply(chosen)
            if RefreshBoth then
                RefreshBoth()
            end
        end)
    end

    local hasBand = (options.showAll or options.copyFrom) and true or false

    -- The two tri-state spell lists. INCLUDED renders through the caller's include machinery; EXCLUDED rides the caller's exclude machinery. Without a header band the whole section shifts up and the lists gain the reclaimed height.
    local secY = (hasBand and -104 or -68) - hdrY
    local div = panelFrame:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 20, secY)
    div:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -20, secY)
    div:SetColorTexture(1, 1, 1, 0.08)

    -- Vertical divider down the column gutter (panel center), spanning the list section. One PHYSICAL pixel via the panel border's recipe above (snap disabled, scale-derived width): an unsnapped quad exactly 1 physical px wide always rasterizes exactly one pixel column at any UI scale.
    local vdiv = panelFrame:CreateTexture(nil, "ARTWORK")
    vdiv:SetWidth(1 / (panelFrame:GetEffectiveScale() or 1))
    if vdiv.SetSnapToPixelGrid then
        vdiv:SetSnapToPixelGrid(false)
        vdiv:SetTexelSnappingBias(0)
    end
    vdiv:SetPoint("TOP", panelFrame, "TOP", 0, secY - 8)
    vdiv:SetPoint("BOTTOM", panelFrame, "BOTTOM", 0, 62)
    vdiv:SetColorTexture(1, 1, 1, 0.08)

    local COL_W = 228
    -- withMine: the caller's includeMine descriptor (INCLUDED column only). Two
    -- polarities: anyGet() = entries default to Only My Casts and the map holds
    -- any-caster OPT-OUTS; mineGet() = entries default to any caster and the map
    -- holds MINE OPT-INS. Either way the tag reads "MINE" and lights when the
    -- entry is restricted to your casts.
    local function MakeSpellColumn(posX, titleText, promptText, listFn, otherFn, withMine)
        local function ScopeMap()
            if not withMine then
                return nil
            end
            if withMine.mineGet then
                return withMine.mineGet()
            end
            return withMine.anyGet and withMine.anyGet()
        end
        local function MineOn(ident)
            local map = ScopeMap()
            if withMine and withMine.mineGet then
                return map ~= nil and map[ident] == true
            end
            return not (map and map[ident])
        end
        -- Both polarities toggle by flipping the entry's presence in the map.
        local function ToggleMine(ident)
            local map = ScopeMap()
            if not map then
                return
            end
            if map[ident] then
                map[ident] = nil
            else
                map[ident] = true
            end
        end
        -- Section label (options-page section style: small gray caps).
        local colTitle = panelFrame:CreateFontString(nil, "OVERLAY")
        colTitle:SetFont(fontFile, 11, "")
        colTitle:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", posX, secY - 16)
        colTitle:SetTextColor(1, 1, 1, 0.45)
        colTitle:SetText(CludesUI.L(titleText))

        -- Add Spell ID: the announcement popup's bordered accent button, secondary weight (dim border, brightens on hover).
        local addBtn = CreateFrame("Button", nil, panelFrame)
        addBtn:SetSize(96, 24)
        addBtn:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", posX + COL_W - 520, secY - 8)
        local abg = addBtn:CreateTexture(nil, "BACKGROUND")
        abg:SetAllPoints()
        abg:SetColorTexture(0.062, 0.070, 0.082, 0.92)
        local abrd = CludesUI.MakeRoundedBorder(addBtn, ACC.r, ACC.g, ACC.b, 0.35, abg)
        local al = addBtn:CreateFontString(nil, "OVERLAY")
        al:SetFont(fontFile, 12, "")
        al:SetPoint("CENTER")
        al:SetTextColor(ACC.r, ACC.g, ACC.b, 0.7)
        al:SetText(CludesUI.L("Add Spell ID"))
        addBtn:SetScript("OnEnter", function()
            al:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
            if abrd and abrd.SetColor then
                abrd:SetColor(ACC.r, ACC.g, ACC.b, 0.8)
            end
        end)
        addBtn:SetScript("OnLeave", function()
            al:SetTextColor(ACC.r, ACC.g, ACC.b, 0.7)
            if abrd and abrd.SetColor then
                abrd:SetColor(ACC.r, ACC.g, ACC.b, 0.35)
            end
        end)

        local scroll = CreateFrame("ScrollFrame", nil, panelFrame)
        scroll:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", posX, secY - 44)
        scroll:SetPoint("BOTTOMRIGHT", panelFrame, "BOTTOMRIGHT", posX + COL_W - 520, 62)
        local childFrame = CreateFrame("Frame", nil, scroll)
        childFrame:SetWidth(COL_W)
        scroll:SetScrollChild(childFrame)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local maxS = math.max(0, childFrame:GetHeight() - self:GetHeight())
            local current = self:GetVerticalScroll() - delta * 30
            if current < 0 then
                current = 0
            elseif current > maxS then
                current = maxS
            end
            self:SetVerticalScroll(current)
        end)

        -- Rows: checkbox (enable/disable the entry without deleting it) + spell icon + name with the spell ID in gray parentheses + delete X. Disabled entries stay stored (false) and dim the whole row; only true entries reach the engine.
        local rowList = {}
        local function RefreshList()
            if PoolGen(shade) ~= dressGen then
                return
            end
            for idx = 1, #rowList do
                rowList[idx]:Hide()
            end
            local entries = listFn() or {}
            local sorted = {}
            for ident, val in pairs(entries) do
                local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(ident)
                sorted[#sorted + 1] = { id = ident, on = val == true, name = nm or tostring(ident) }
            end
            table.sort(sorted, function(a, b)
                return a.name < b.name
            end)
            for idx = 1, #sorted do
                local row = rowList[idx]
                if not row then
                    row = CreateFrame("Button", nil, childFrame)
                    row:SetSize(COL_W, 28)
                    row:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, -(idx - 1) * 29)
                    row.hl = row:CreateTexture(nil, "BACKGROUND")
                    row.hl:SetAllPoints()
                    row.hl:SetColorTexture(1, 1, 1, 0)
                    -- Checkbox (checkbox-dropdown visuals)
                    row.box = CreateFrame("Frame", nil, row)
                    row.box:SetSize(16, 16)
                    row.box:SetPoint("LEFT", row, "LEFT", 2, 0)
                    local bxbg = row.box:CreateTexture(nil, "BACKGROUND")
                    bxbg:SetAllPoints()
                    bxbg:SetColorTexture(0.114, 0.106, 0.099, 1)
                    row.boxBrd = CludesUI.MakeRoundedBorder(row.box, 0.4, 0.4, 0.4, 0.6, bxbg)
                    row.chk = row.box:CreateTexture(nil, "ARTWORK")
                    Pix.SetInside(row.chk, row.box, 2, 2)
                    row.chk:SetColorTexture(ACC.r, ACC.g, ACC.b, 1)
                    CludesUI.RoundBody(row.box, row.chk, 2)
                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(20, 20)
                    row.icon:SetPoint("LEFT", row.box, "RIGHT", 6, 0)
                    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    row.name = row:CreateFontString(nil, "OVERLAY")
                    row.name:SetFont(fontFile, 13, "")
                    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                    row.name:SetPoint("RIGHT", row, "RIGHT", withMine and -52 or -24, 0)
                    row.name:SetJustifyH("LEFT")
                    row.name:SetWordWrap(false)
                    row.x = CreateFrame("Button", nil, row)
                    row.x:SetSize(14, 14)
                    row.x:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                    row.x:SetFrameLevel(row:GetFrameLevel() + 2)
                    if withMine then
                        -- Only My Casts tag: accent when restricted to your
                        -- casts, gray when the entry shows from any caster.
                        row.mine = CreateFrame("Button", nil, row)
                        row.mine:SetSize(30, 16)
                        row.mine:SetPoint("RIGHT", row.x, "LEFT", -2, 0)
                        row.mine:SetFrameLevel(row:GetFrameLevel() + 2)
                        row.mine.txt = row.mine:CreateFontString(nil, "OVERLAY")
                        row.mine.txt:SetFont(fontFile, 11, "")
                        row.mine.txt:SetPoint("CENTER")
                        row.mine.txt:SetText(CludesUI.L("MINE"))
                        row.mine:SetScript("OnClick", function()
                            ToggleMine(row._id)
                            if options.onChanged then
                                options.onChanged()
                            end
                            RefreshList()
                        end)
                        row.mine:SetScript("OnEnter", function(self)
                            local tipText
                            if MineOn(row._id) then
                                tipText = CludesUI.L(
                                    "Showing this aura from your casts only; click for any caster."
                                )
                            else
                                tipText = CludesUI.L(
                                    "Showing this aura from any caster; click for your casts only."
                                )
                            end
                            CludesUI.ShowWidgetTooltip(self, tipText)
                        end)
                        row.mine:SetScript("OnLeave", function()
                            CludesUI.HideWidgetTooltip()
                        end)
                    end
                    row.x.tex = row.x:CreateTexture(nil, "OVERLAY")
                    row.x.tex:SetAllPoints()
                    row.x.tex:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png")
                    row.x:SetAlpha(0.5)
                    row.x:SetScript("OnEnter", function(self)
                        self:SetAlpha(0.9)
                        CludesUI.ShowWidgetTooltip(self, CludesUI.L("Remove"))
                    end)
                    row.x:SetScript("OnLeave", function(self)
                        self:SetAlpha(0.5)
                        CludesUI.HideWidgetTooltip()
                    end)
                    row:SetScript("OnEnter", function(self)
                        self.hl:SetColorTexture(1, 1, 1, 0.04)
                    end)
                    row:SetScript("OnLeave", function(self)
                        self.hl:SetColorTexture(1, 1, 1, 0)
                    end)
                    rowList[idx] = row
                end
                local record = sorted[idx]
                row._id = record.id
                local texture = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(record.id)
                row.icon:SetTexture(texture or 134400)
                row.name:SetText(record.name .. " |cff808080(" .. record.id .. ")|r")
                -- Checked = entry active; unchecked entries dim.
                row.chk:SetShown(record.on)
                if row.boxBrd and row.boxBrd.SetColor then
                    if record.on then
                        row.boxBrd:SetColor(ACC.r, ACC.g, ACC.b, 0.8)
                    else
                        row.boxBrd:SetColor(0.4, 0.4, 0.4, 0.6)
                    end
                end
                row.icon:SetDesaturated(not record.on)
                row.icon:SetAlpha(record.on and 1 or 0.45)
                row.name:SetAlpha(record.on and 0.9 or 0.45)
                if row.mine then
                    if MineOn(row._id) then
                        -- Restricted to your own casts: accent tag.
                        row.mine.txt:SetTextColor(ACC.r, ACC.g, ACC.b, record.on and 1 or 0.45)
                    else
                        -- Any caster: dim gray tag.
                        row.mine.txt:SetTextColor(0.6, 0.6, 0.6, record.on and 0.4 or 0.25)
                    end
                end
                row:SetScript("OnClick", function()
                    local l2 = listFn()
                    if l2 then
                        l2[row._id] = not (l2[row._id] == true)
                        if options.onChanged then
                            options.onChanged()
                        end
                        RefreshList()
                    end
                end)
                row.x:SetScript("OnClick", function()
                    local l2 = listFn()
                    if l2 then
                        l2[row._id] = nil
                    end
                    if withMine then
                        local map = ScopeMap()
                        if map then
                            map[row._id] = nil
                        end
                    end
                    if options.onChanged then
                        options.onChanged()
                    end
                    RefreshList()
                end)
                row:Show()
            end
            childFrame:SetHeight(math.max(1, #sorted * 29))
        end
        addBtn:SetScript("OnClick", function()
            CludesUI:ShowInputPopup({
                title = CludesUI.L("Add Spell ID"),
                message = promptText,
                confirmText = CludesUI.L("Add"),
                cancelText = CludesUI.L("Cancel"),
                onConfirm = function(textValue)
                    local ident = tonumber(textValue or "")
                    local entries = ident and listFn()
                    if entries then
                        -- One list per spell: adding here removes it from the opposite list.
                        local other = otherFn()
                        if other then
                            other[ident] = nil
                        end
                        if options.onAdd then
                            options.onAdd(ident)
                        end
                        entries[ident] = true
                        if options.onChanged then
                            options.onChanged()
                        end
                        if RefreshBoth then
                            RefreshBoth()
                        end
                    end
                end,
            })
        end)
        return RefreshList
    end

    local refreshInc = MakeSpellColumn(
        24,
        "INCLUDED DEBUFFS",
        CludesUI.L(options.includePrompt or "Enter the spell ID to always show."),
        options.includeGet,
        options.excludeGet,
        options.includeMine
    )
    local refreshEx = MakeSpellColumn(
        268,
        "EXCLUDED DEBUFFS",
        CludesUI.L(options.excludePrompt or "Enter the spell ID to exclude."),
        options.excludeGet,
        options.includeGet
    )
    RefreshBoth = function()
        refreshInc()
        refreshEx()
    end

    -- Done (announcement popup's primary action: green border and label, brighten on hover). Everything applies live, so Done = close.
    local doneBtn = CreateFrame("Button", nil, panelFrame)
    doneBtn:SetSize(150, 32)
    doneBtn:SetPoint("BOTTOM", panelFrame, "BOTTOM", 0, 14)
    local dbg2 = doneBtn:CreateTexture(nil, "BACKGROUND")
    dbg2:SetAllPoints()
    dbg2:SetColorTexture(0.062, 0.070, 0.082, 0.92)
    local dbrd = CludesUI.MakeRoundedBorder(doneBtn, ACC.r, ACC.g, ACC.b, 0.9, dbg2)
    local dl2 = doneBtn:CreateFontString(nil, "OVERLAY")
    dl2:SetFont(fontFile, 14, "")
    dl2:SetPoint("CENTER")
    dl2:SetText(CludesUI.L("Done"))
    dl2:SetTextColor(ACC.r, ACC.g, ACC.b, 0.9)
    doneBtn:SetScript("OnEnter", function()
        dl2:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
        if dbrd and dbrd.SetColor then
            dbrd:SetColor(ACC.r, ACC.g, ACC.b, 1)
        end
    end)
    doneBtn:SetScript("OnLeave", function()
        dl2:SetTextColor(ACC.r, ACC.g, ACC.b, 0.9)
        if dbrd and dbrd.SetColor then
            dbrd:SetColor(ACC.r, ACC.g, ACC.b, 0.9)
        end
    end)
    doneBtn:SetScript("OnClick", ClosePopup)

    -- Controller in use: the popup joins the controller cursor and answers the
    -- controller's Back (registered while hidden, so it counts from this show);
    -- the full-screen dimmer and the panel are no stops, Cancel clicks the X, the
    -- cursor starts on Done.
    local pad = CludesUI.PadInUse()
    if pad then
        -- Every open asks: the call returns at once while the kept dimmer is
        -- still registered (a named dimmer stays so through the pool's resets).
        CludesUI.RegisterEscapeClose(shade, TRACKED_AURAS_ESC)
        CludesUI.PadHint(shade, "nodepass")
        CludesUI.PadHint(panelFrame, "nodepass")
        if CludesUI.PadCP() then
            panelFrame.CloseButton = closeBtn
        end
    end
    shade:Show()
    if pad and CludesUI.PadCursorShown() then
        CludesUI.PadFocus(doneBtn)
    end

    RefreshBoth()
end

-------------------------------------------------------------------------------
-- Spell-ID blacklist editor: small standalone modal (dimmer, click-outside close) listing the current blacklist
-- with per-row remove plus an Add box. Storage-agnostic -- callers pass get/add/remove accessors and an onChanged
-- applier. Reused by the player-frame, Player Aura Bars and Buff Manager buff filter dropdowns ("Edit Blacklist" pinned actions).
-- Controller Escape/Back (RegisterEscapeClose): the registration outlives the
-- open that made it, so the close reads the frame it is handed.
local function EscapeBlacklist(f)
    f:Hide()
    CludesUI._blacklistPopup = nil
end
local BLACKLIST_ESC = { padOnly = true, onEscape = EscapeBlacklist }
function CludesUI.ShowSpellBlacklistPopup(options)
    if CludesUI._blacklistPopup then
        CludesUI._blacklistPopup:Hide()
        CludesUI._blacklistPopup = nil
    end
    options = options or {}
    local fontFile = CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
    local eg = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
    local PW, PH = 320, 400

    -- Controller cursor loaded: the dimmer is a named Button, so the cursor can
    -- take the popup as a window and its Cancel press can click the dimmer shut.
    -- One kept dimmer per kind (a kept frame never changes its type).
    local padCP = CludesUI.PadCP()
    -- Kept hidden: shown below once dressed (see ShowTrackedAurasPopup).
    local shade = PoolKept(
        POPUPS,
        padCP and "spellBlacklistPad" or "spellBlacklist",
        padCP and "Button" or "Frame",
        UIParent,
        nil,
        padCP and "CUISpellBlacklistDimmer" or nil,
        true
    )
    -- This open's dress (see ShowTrackedAurasPopup).
    local dressGen = PoolGen(shade)
    shade:SetFrameStrata("FULLSCREEN_DIALOG")
    shade:SetAllPoints(UIParent)
    shade:EnableMouse(true)
    shade:EnableMouseWheel(true)
    shade:SetScript("OnMouseWheel", function() end)
    local function CloseBlacklist()
        shade:Hide()
        CludesUI._blacklistPopup = nil
    end
    shade:SetScript("OnMouseDown", CloseBlacklist)
    CludesUI.SolidTex(shade, "BACKGROUND", 0, 0, 0, 0.25):SetAllPoints(shade)
    CludesUI._blacklistPopup = shade

    local dialog = CreateFrame("Frame", nil, shade)
    dialog:SetSize(PW, PH)
    dialog:SetPoint("CENTER")
    dialog:EnableMouse(true)
    dialog:SetFrameLevel(shade:GetFrameLevel() + 2)
    if CludesUI.GetPopupScale then
        dialog:SetScale(CludesUI.GetPopupScale())
    end
    local popBg = CludesUI.SolidTex(dialog, "BACKGROUND", 13 / 255, 17 / 255, 25 / 255, 0.98)
    popBg:SetAllPoints(dialog)
    CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.22, popBg)

    local title = dialog:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontFile, 14, "")
    title:SetPoint("TOP", dialog, "TOP", 0, -12)
    title:SetTextColor(1, 1, 1, 0.95)
    title:SetText(CludesUI.L(options.title or "Blacklist"))

    local hint = dialog:CreateFontString(nil, "OVERLAY")
    hint:SetFont(fontFile, 11, "")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
    hint:SetWidth(PW - 32)
    hint:SetJustifyH("CENTER")
    hint:SetTextColor(1, 1, 1, 0.45)
    hint:SetText(CludesUI.L("Blacklisted spells never display."))

    local addBox = CreateFrame("EditBox", nil, dialog)
    addBox:SetSize(PW - 24 - 70 - 8, 26)
    addBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 12, -58)
    addBox:SetFont(fontFile, 12, "")
    addBox:SetTextColor(1, 1, 1, 0.9)
    addBox:SetAutoFocus(false)
    addBox:SetNumeric(true)
    addBox:SetMaxLetters(9)
    addBox:SetTextInsets(6, 6, 0, 0)
    addBox:SetJustifyH("LEFT")
    -- Every open starts empty: the dress sets the text itself rather than rely on
    -- the kept box's reset (set before OnTextChanged, so nothing fires).
    addBox:SetText("")
    local addBg = CludesUI.SolidTex(addBox, "BACKGROUND", 0, 0, 0, 0.4)
    addBg:SetAllPoints(addBox)
    CludesUI.MakeRoundedBorder(addBox, 1, 1, 1, 0.15, addBg)
    local ph = addBox:CreateFontString(nil, "OVERLAY")
    ph:SetFont(fontFile, 11, "")
    ph:SetPoint("LEFT", addBox, "LEFT", 6, 0)
    ph:SetTextColor(0.5, 0.5, 0.5, 0.6)
    ph:SetText(CludesUI.L("Spell ID..."))
    addBox:SetScript("OnTextChanged", function(self)
        ph:SetShown(self:GetText() == "")
    end)
    addBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    local addBtn = CreateFrame("Button", nil, dialog)
    addBtn:SetSize(70, 26)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 8, 0)
    local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
    addBg:SetAllPoints()
    addBg:SetColorTexture(eg.r, eg.g, eg.b, 0.8)
    CludesUI.RoundBody(addBtn, addBg)
    local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
    addLbl:SetFont(fontFile, 11, "")
    addLbl:SetPoint("CENTER")
    addLbl:SetTextColor(1, 1, 1)
    addLbl:SetText(CludesUI.L("Add"))
    addBtn:SetScript("OnEnter", nil) -- CludesUI.OutlineButton below sets the hover
    CludesUI.OutlineButton(addBtn, addBg, true)

    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog)
    scrollFrame:SetPoint("TOPLEFT", dialog, "TOPLEFT", 12, -94)
    scrollFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -12, 12)
    local childFrame = CreateFrame("Frame", nil, scrollFrame)
    childFrame:SetWidth(PW - 24)
    childFrame:SetHeight(1)
    scrollFrame:SetScrollChild(childFrame)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxS = math.max(0, childFrame:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxS, math.max(0, self:GetVerticalScroll() - delta * 30)))
    end)

    local emptyLbl = childFrame:CreateFontString(nil, "OVERLAY")
    emptyLbl:SetFont(fontFile, 11, "")
    emptyLbl:SetPoint("TOP", childFrame, "TOP", 0, -10)
    emptyLbl:SetTextColor(1, 1, 1, 0.35)
    emptyLbl:SetText(CludesUI.L("No blacklisted spells."))

    local rowList = {}
    local RebuildList
    RebuildList = function()
        if PoolGen(shade) ~= dressGen then
            return
        end
        for idx = 1, #rowList do
            rowList[idx]:Hide()
        end
        local map = (options.get and options.get()) or {}
        local ids = {}
        for ident in pairs(map) do
            ids[#ids + 1] = ident
        end
        table.sort(ids)
        local cursorY = 0
        for idx = 1, #ids do
            local ident = ids[idx]
            local row = rowList[idx]
            if not row then
                row = CreateFrame("Frame", nil, childFrame)
                row:SetSize(PW - 24, 26)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(18, 18)
                row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
                row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                row.rm = CreateFrame("Button", nil, row)
                row.rm:SetSize(18, 18)
                row.rm:SetPoint("RIGHT", row, "RIGHT", -2, 0)
                row.rmX = row.rm:CreateFontString(nil, "OVERLAY")
                row.rmX:SetFont(fontFile, 12, "")
                row.rmX:SetPoint("CENTER")
                row.rmX:SetText("X")
                row.rmX:SetTextColor(1, 0.3, 0.3, 0.7)
                row.rm:SetScript("OnEnter", function()
                    row.rmX:SetTextColor(1, 0.3, 0.3, 1)
                end)
                row.rm:SetScript("OnLeave", function()
                    row.rmX:SetTextColor(1, 0.3, 0.3, 0.7)
                end)
                row.idText = row:CreateFontString(nil, "OVERLAY")
                row.idText:SetFont(fontFile, 10, "")
                row.idText:SetTextColor(1, 1, 1, 0.35)
                row.idText:SetPoint("RIGHT", row.rm, "LEFT", -6, 0)
                row.name = row:CreateFontString(nil, "OVERLAY")
                row.name:SetFont(fontFile, 12, "")
                row.name:SetTextColor(1, 1, 1, 0.85)
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.name:SetPoint("RIGHT", row.idText, "LEFT", -6, 0)
                row.name:SetJustifyH("LEFT")
                row.name:SetWordWrap(false)
                rowList[idx] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, cursorY)
            local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(ident)
            row.icon:SetTexture((details and details.iconID) or 134400)
            row.name:SetText((details and details.name) or ("Spell " .. tostring(ident)))
            row.idText:SetText(tostring(ident))
            row.rm:SetScript("OnClick", function()
                if options.remove then
                    options.remove(ident)
                end
                if options.onChanged then
                    options.onChanged()
                end
                RebuildList()
            end)
            row:Show()
            cursorY = cursorY - 26
        end
        childFrame:SetHeight(math.max(1, -cursorY))
        emptyLbl:SetShown(#ids == 0)
    end

    local function AddFromBox()
        local ident = tonumber(addBox:GetText() or "")
        addBox:SetText("")
        addBox:ClearFocus()
        if not (ident and ident > 0) then
            return
        end
        local map = options.get and options.get()
        if map and map[ident] then
            return
        end
        if options.add then
            options.add(ident)
        end
        if options.onChanged then
            options.onChanged()
        end
        RebuildList()
    end
    addBtn:SetScript("OnClick", AddFromBox)
    addBox:SetScript("OnEnterPressed", AddFromBox)

    -- Controller in use: the popup joins the controller cursor and answers the
    -- controller's Back (registered while hidden, so it counts from this show);
    -- the dimmer and the panel are no stops, Cancel clicks the dimmer (the popup
    -- has no close button), and the cursor starts inside the popup.
    if padCP or CludesUI.PadNative() then
        if padCP then
            shade:SetScript("OnClick", CloseBlacklist)
            CludesUI.PadHint(shade, "nodepass")
            CludesUI.PadHint(dialog, "nodepass")
            dialog.CloseButton = shade
        end
        -- Every open asks: a named dimmer stays registered through the pool's
        -- resets (the call returns at once), an unnamed one is registered anew.
        CludesUI.RegisterEscapeClose(shade, BLACKLIST_ESC)
    end
    shade:Show()

    RebuildList()
    if padCP and CludesUI.PadCursorShown() then
        CludesUI.PadFocus(dialog)
    end
end
