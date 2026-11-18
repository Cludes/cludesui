if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CooldownManager_Options\SpellPicker_Options.lua
--  Cooldown Manager options: the per-bar spell picker (ShowSpellPicker).
--  Definitions only; the shared helpers come from ns._CDMO_OptEnv (filled by
--  CUI_CooldownManager_Options.lua), the other pickers from Pickers_Options.lua.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUICooldownManager"]
if not mod then
    return
end -- module disabled: no options page

-- The options page pool (CludesUI_FramePool.lua): a frame made under a pool
-- host (a kept menu) is handed out again reset to fresh; anywhere else this is
-- the plain CreateFrame. The picker and the per-icon settings menu are one kept
-- frame each for the session (PoolKept), dressed again on every open: their
-- rows, flyouts, apply strip and scroll parts are pooled under them. A menu
-- remembers its anchor with the anchor's dress generation (PoolGen): an anchor
-- a rebuild dressed again for a new build is another anchor, as a new frame was.
local CreateFrame = CludesUI._Pool.CreateFrame
local PoolKept, PoolGen = CludesUI._Pool.Kept, CludesUI._Pool.Gen

-- A glow-style picker's items: the leading "inherit" entry (val nil, its
-- caption given), then None (val 0) when noneVal is passed, then the seven
-- glow styles in menu order. A fresh list on every call.
-- A sound picker's items, in the shared sound order: one per sound (its
-- name, or the key when it has none) and a divider for each "---" separator
-- (built-in sounds above, LibSharedMedia ones below).
local function SoundItems()
    local items = {}
    for _, key in ipairs(mod.FOCUSKICK_SOUND_ORDER or { "none" }) do
        if type(key) == "string" and key:sub(1, 3) == "---" then
            items[#items + 1] = { divider = true }
        else
            local names = mod.FOCUSKICK_SOUND_NAMES
            items[#items + 1] = { val = key, label = (names and names[key]) or key }
        end
    end
    return items
end

-- Hangs a speaker button on a sound row (none for silence) that plays the
-- row's sound without picking it, as the sound dropdowns' preview does.
local function AddSoundPreviewButton(si, item)
    if not item.val or item.val == "none" then
        return
    end
    local play = CreateFrame("Button", nil, si)
    play:SetSize(16, 16)
    play:SetPoint("RIGHT", si, "RIGHT", -8, 0)
    play:SetFrameLevel(si:GetFrameLevel() + 2)
    play:SetNormalAtlas(CludesUI.SOUND_ICON_ATLAS)
    play:SetPushedAtlas(CludesUI.SOUND_ICON_PRESSED_ATLAS)
    play:SetScript("OnClick", function()
        local paths = mod.FOCUSKICK_SOUND_PATHS
        local filePath = paths and paths[item.val]
        if filePath then
            PlaySoundFile(filePath, "Master")
        end
    end)
    play:SetScript("OnEnter", function()
        CludesUI.ShowWidgetTooltip(play, "Preview Sound")
    end)
    play:SetScript("OnLeave", function()
        CludesUI.HideWidgetTooltip()
    end)
end

local function GlowStyleItems(inheritLabel, noneVal)
    local items = { { val = nil, label = inheritLabel } }
    if noneVal then
        items[2] = { val = noneVal, label = "None" }
    end
    for _, style in ipairs({
        { 1, "Pixel Glow" },
        { 3, "Action Button Glow" },
        { 4, "Auto-Cast Shine" },
        { 2, "Shape Glow" },
        { 5, "GCD" },
        { 6, "Modern WoW Glow" },
        { 7, "Classic WoW Glow" },
    }) do
        items[#items + 1] = { val = style[1], label = style[2] }
    end
    return items
end

local function ShowWrongBarTypePopup(spellName, isSpellBuff)
    if not CludesUI or not CludesUI.ShowConfirmPopup then
        return
    end
    local correctBar = isSpellBuff and "a Buff bar" or "a Cooldown or Utility bar"
    CludesUI:ShowConfirmPopup({
        title = "Wrong Bar Type",
        message = (spellName or "This spell")
            .. " is tracked by Blizzard as "
            .. (isSpellBuff and "a buff/aura" or "a cooldown")
            .. " and should be added to "
            .. correctBar
            .. ".",
        confirmText = "Open Blizzard CDM",
        cancelText = "Close",
        onConfirm = function()
            if CooldownViewerSettings and CooldownViewerSettings.Show then
                CooldownViewerSettings:Show()
            end
            if CludesUI._mainFrame then
                CludesUI._mainFrame:Hide()
            end
        end,
    })
end

-- Locks one subnav flyout item (dimmed, no click, a tooltip naming what to
-- change first) or unlocks it, putting the item's own scripts back. Flyouts
-- run it on every open and after every pick, so the lock and its reason
-- follow the settings they depend on: each call stores the current reason.
local function FlyoutItemNoOp() end
local function FlyoutItemLockedEnter(self)
    CludesUI.ShowWidgetTooltip(self, self._lockTip)
end
-- The item's own OnLeave also runs: an item locked under the cursor (by a pick
-- made on it) drops the hover look it had.
local function FlyoutItemLockedLeave(self)
    local saved = self._lockSaved
    if saved and saved[3] then
        saved[3](self)
    end
    CludesUI.HideWidgetTooltip()
end
local function SetFlyoutItemLocked(si, locked, tipText)
    local saved = si._lockSaved
    if locked then
        si._lockTip = tipText
        if not saved then
            si._lockSaved = { si:GetScript("OnClick"), si:GetScript("OnEnter"), si:GetScript("OnLeave") }
            si:SetScript("OnClick", FlyoutItemNoOp)
            si:SetScript("OnEnter", FlyoutItemLockedEnter)
            si:SetScript("OnLeave", FlyoutItemLockedLeave)
        end
        si:SetAlpha(0.35)
    elseif saved then
        si._lockSaved = nil
        si:SetScript("OnClick", saved[1])
        si:SetScript("OnEnter", saved[2])
        si:SetScript("OnLeave", saved[3])
        si:SetAlpha(1)
    end
end

-- True when keys hold a colour (some xR, xG and xB together): an apply then
-- carries that colour, which the item's own value does not describe.
local function HasColourTriple(keys)
    if not keys then
        return false
    end
    local held = {}
    for _, k in ipairs(keys) do
        held[k] = true
    end
    for k in pairs(held) do
        local base = k:match("^(.+)R$")
        if base and held[base .. "G"] and held[base .. "B"] then
            return true
        end
    end
    return false
end

-- The session gate a charge-style toggle arms when turned on (false: none, as
-- Hide Until Spent is read only by the CD Ready evaluator, which already runs
-- just for icons with that effect). Any other charge key arms the style gate.
local CHARGE_GATES = {
    chargeHideCdText = "_cdmAnyChargeHideCdText",
    hideChargeText = "_cdmAnyHideChargeText",
    suppressGCD = "_cdmAnySuppressGcd",
    chargeHideUntilSpent = false,
}
local function ArmChargeGate(mod, key)
    local gate = CHARGE_GATES[key]
    if gate == nil then
        gate = "_cdmAnyChargeStyle"
    end
    if gate then
        mod[gate] = true
    end
end

-- A plain menu row at y on inner (made at menu level + 2): its label in the dim
-- text colour and a clear highlight. Hovering lights both, closes the menu's open
-- flyout (unless opts.keepSub) and shows opts.tip; leaving puts them back.
-- opts.fit keeps the label to one line inside the row. Kept outside
-- ShowSpellPicker, which sits near Lua's cap on live locals. Returns the row.
local function PlainMenuRow(menu, inner, y, height, text, font, dim, hlA, onClick, opts)
    local row = CreateFrame("Button", nil, inner)
    row:SetHeight(height)
    row:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -y)
    row:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -y)
    row:SetFrameLevel(menu:GetFrameLevel() + 2)
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(font[1], font[2], font[3])
    label:SetPoint("LEFT", 10, 0)
    if opts and opts.fit then
        label:SetPoint("RIGHT", -10, 0)
        label:SetWordWrap(false)
        label:SetMaxLines(1)
    end
    label:SetJustifyH("LEFT")
    label:SetText(text)
    label:SetTextColor(dim[1], dim[2], dim[3], dim[4])
    local highlight = row:CreateTexture(nil, "ARTWORK")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0)
    highlight:SetAlpha(0)
    local tip = opts and opts.tip
    row:SetScript("OnEnter", function()
        label:SetTextColor(1, 1, 1, 1)
        highlight:SetColorTexture(1, 1, 1, hlA)
        highlight:SetAlpha(1)
        if not (opts and opts.keepSub) and menu._openSub and menu._openSub:IsShown() then
            menu._openSub:Hide()
        end
        if tip then
            CludesUI.ShowWidgetTooltip(row, tip)
        end
    end)
    row:SetScript("OnLeave", function()
        label:SetTextColor(dim[1], dim[2], dim[3], dim[4])
        highlight:SetAlpha(0)
        if tip then
            CludesUI.HideWidgetTooltip()
        end
    end)
    row:SetScript("OnClick", onClick)
    return row
end

-- A preset entry of the picker (a trinket slot, the racial, Seals): its label,
-- its icon on the right when it has one, and a clear highlight. While it is on
-- this bar it is greyed (icon too) and says "Already on <onBar>"; otherwise
-- hovering lights it and a click runs onPick. Returns the row.
local function PresetMenuRow(menu, inner, y, height, text, texture, onBar, font, dim, hlA, onPick)
    local row = CreateFrame("Button", nil, inner)
    row:SetHeight(height)
    row:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -y)
    row:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -y)
    row:SetFrameLevel(menu:GetFrameLevel() + 2)
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(font[1], font[2], font[3])
    label:SetPoint("LEFT", 10, 0)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    if texture then
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(height - 2, height - 2)
        icon:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        icon:SetTexture(texture)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if onBar then
            icon:SetDesaturated(true)
            icon:SetAlpha(0.4)
        end
    end
    local highlight = row:CreateTexture(nil, "ARTWORK")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0)
    highlight:SetAlpha(0)
    if onBar then
        label:SetTextColor(dim[1], dim[2], dim[3], dim[4] * 0.4)
        row:SetScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(row, CludesUI.Lf("Already on %s", CludesUI.L(onBar)))
        end)
        row:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        return row
    end
    label:SetTextColor(dim[1], dim[2], dim[3], dim[4])
    row:SetScript("OnEnter", function()
        label:SetTextColor(1, 1, 1, 1)
        highlight:SetColorTexture(1, 1, 1, hlA)
        highlight:SetAlpha(1)
    end)
    row:SetScript("OnLeave", function()
        label:SetTextColor(dim[1], dim[2], dim[3], dim[4])
        highlight:SetAlpha(0)
    end)
    row:SetScript("OnClick", onPick)
    return row
end

-- A list entry with its icon on the right and the label clipped to one line
-- before it, at y on parent (made at owner level + 2). Greyed (label and icon)
-- while already added: then tipBar, when given, names where ("Already on X").
-- Otherwise hovering lights it and a click runs onPick. Returns the row and label.
local function IconMenuRow(
    parent,
    owner,
    y,
    height,
    text,
    texture,
    greyed,
    tipBar,
    font,
    dim,
    hlA,
    onPick,
    anyUp
)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(height)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -y)
    row:SetFrameLevel(owner:GetFrameLevel() + 2)
    if anyUp then
        row:RegisterForClicks("AnyUp")
    end
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(height - 2, height - 2)
    icon:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    icon:SetTexture(texture)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(font[1], font[2], font[3])
    label:SetPoint("LEFT", row, "LEFT", 10, 0)
    label:SetPoint("RIGHT", icon, "LEFT", -5, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetMaxLines(1)
    label:SetText(text)
    local highlight = row:CreateTexture(nil, "ARTWORK")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0)
    highlight:SetAlpha(0)
    if greyed then
        label:SetTextColor(dim[1], dim[2], dim[3], dim[4] * 0.4)
        icon:SetDesaturated(true)
        icon:SetAlpha(0.4)
        if tipBar then
            row:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(row, CludesUI.Lf("Already on %s", CludesUI.L(tipBar)))
            end)
            row:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
        end
        return row, label, icon, highlight
    end
    label:SetTextColor(dim[1], dim[2], dim[3], dim[4])
    row:SetScript("OnEnter", function()
        label:SetTextColor(1, 1, 1, 1)
        highlight:SetColorTexture(1, 1, 1, hlA)
        highlight:SetAlpha(1)
    end)
    row:SetScript("OnLeave", function()
        label:SetTextColor(dim[1], dim[2], dim[3], dim[4])
        highlight:SetAlpha(0)
    end)
    row:SetScript("OnClick", onPick)
    return row, label, icon, highlight
end

local function ShowSpellPicker(anchor, barId, slotIndex, excludeSet, onSelect, removeOnly)
    local environ = mod._CDMO_OptEnv
    local FONT_PATH, FitMenuWidth, GetCDMOptOutline, RefreshCDPreview =
        environ.FONT_PATH, environ.FitMenuWidth, environ.GetCDMOptOutline, environ.RefreshCDPreview
    local SelectedCDMBar, durationPositionOrder, durationPositionValues, optionState =
        environ.SelectedCDMBar,
        environ.durationPositionOrder,
        environ.durationPositionValues,
        environ.optState
    local EnsureAssignedSpells, ShowAlphaPopup, ShowBuffToCDPicker, ShowCustomItemIDPopup =
        mod.CDMO_EnsureAssignedSpells,
        mod.CDMO_ShowAlphaPopup,
        mod.CDMO_ShowBuffToCDPicker,
        mod.CDMO_ShowCustomItemIDPopup
    local ShowDurationPopup, ShowEquipmentSlotPopup, ShowThresholdSecondsPopup =
        mod.CDMO_ShowDurationPopup, mod.CDMO_ShowEquipmentSlotPopup, mod.CDMO_ShowThresholdSecondsPopup
    -- Toggle: if the picker is already open for this same icon, close it
    local open = optionState._spellPickerMenu
    if open and open:IsShown() and open._anchorFrame == anchor and open._anchorGen == PoolGen(anchor) then
        open:Hide()
        return
    end
    -- Close existing
    if optionState._spellPickerMenu then
        optionState._spellPickerMenu:Hide()
    end

    local edge = SelectedCDMBar()
    local isCustomBuff = edge and edge.barType == "custom_buff"
    local isBuffBar = edge and mod.IsBarBuffFamily(edge)

    -- Per-icon buff settings key = the slot's DISPLAYED spell (canonical /
    -- GetSpellID-derived _previewSpellID), NOT the cooldownInfo base: some buffs'
    -- base is an unrelated GENERIC spec spell shared by several icons (e.g.
    -- Consecration -> Protection Paladin 137028), which both collides (settings leak
    -- onto a "random" icon) and never matches the real buff. The displayed id is
    -- buff-specific and the render resolves the same id canon-first
    -- (RefreshCDMIconAppearance), so writer/reader agree. Custom/injected buffs' own positive id as _previewSpellID works too.
    local function ResolveBuffSettingsKey(af)
        local spellRef = af and af._previewSpellID
        if not spellRef then
            return nil
        end
        -- Same-spellID collision (Diabolist Demonic Art vs Diabolic Ritual): when two
        -- viewer slots share this displayed id, key THIS slot by its own cooldownID so each is configured independently; non-collided buffs keep the stable spellID key (survives talent swaps).
        local cdID = af and (af._previewCdID or af.cooldownID)
        if type(cdID) == "number" then
            local ckey = "c" .. cdID
            -- Read-your-writes: once a per-cooldownID entry exists, keep editing it even
            -- if the collision later ends (re-talent), so the menu never splits from what the runtime resolver reads (which prefers an existing c-entry whenever present).
            local bstore = mod.GetSpellSettingsStore and mod.GetSpellSettingsStore("buffs")
            if bstore and bstore[ckey] then
                return ckey
            end
            if mod.IsCollidedBuffSid and mod.IsCollidedBuffSid(spellRef) then
                return ckey
            end
            -- A slot this bar claims by cooldownID (tracked trinket row) keys the
            -- same way whether or not its spell resolves, as on CD/utility bars.
            local claims = mod.CollectCdClaimSet(mod.GetBarSpellData(barId))
            if claims and claims[cdID] then
                return ckey
            end
        end
        return spellRef
    end

    -- No early return on an empty Blizzard list: the picker also hosts the Custom
    -- Spell ID / Custom Item ID / Equipment Slot entries and the trinket / racial /
    -- potion presets, which are the only way onto the bar while the viewer has no
    -- data for it (before COOLDOWN_VIEWER_DATA_LOADED, or every entry set to Not
    -- Displayed). The list sections below already render nothing for an empty set,
    -- and the "Missing Spells?" footer is the right prompt in that state.
    local allSpells = {}
    if not removeOnly and not isCustomBuff then
        allSpells = mod.GetCDMSpellsForBar(barId) or {}
    end

    -- Standard CludesUI dropdown colors
    local mBgR = CludesUI.DD_BG_R or 0.075
    local mBgG = CludesUI.DD_BG_G or 0.113
    local mBgB = CludesUI.DD_BG_B or 0.141
    local mBgA = CludesUI.DD_BG_HA or 0.98
    local mBrdA = CludesUI.DD_BRD_A or 0.20
    local hlA = CludesUI.DD_ITEM_HL_A or 0.08
    local tDimR = CludesUI.TEXT_DIM_R or 0.7
    local tDimG = CludesUI.TEXT_DIM_G or 0.7
    local tDimB = CludesUI.TEXT_DIM_B or 0.7
    local tDimA = CludesUI.TEXT_DIM_A or 0.85

    local menuW = 210
    local ITEM_H = 26
    local MAX_H = 400 -- full picker scrolls past this; the per-spell menu has no scroll and sizes to its rows

    local dropMenu = PoolKept(optionState, removeOnly and "spSettings" or "spPicker", "Frame", UIParent)
    -- Per-build state of the kept frame: the row a rebuild reopens, and a rebuild request.
    dropMenu._cseRow, dropMenu._rebuildPending = nil, nil
    dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    dropMenu:SetFrameLevel(300)
    dropMenu:SetClampedToScreen(true)
    dropMenu:SetSize(menuW, 10)
    dropMenu:EnableMouse(true)

    -- Background + border (standard dropdown style)
    local backdrop = dropMenu:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
    CludesUI.MakeRoundedBorder(dropMenu, 1, 1, 1, mBrdA, backdrop, nil, true)

    -- Build item list: tracked first (minus current), divider, rest, disabled at bottom
    local tracked = {}
    local edge = SelectedCDMBar()
    local sd = edge and mod.GetBarSpellData(edge.key)
    if sd and sd.assignedSpells then
        for _, spellRef in ipairs(sd.assignedSpells) do
            tracked[spellRef] = true
        end
    end

    -- Primary/secondary category order by bar type: cooldown-type bars = Essential(0)
    -- first, Utility(1) second; utility-type bars = reversed.
    local resolvedType = mod.GetBarType and mod.GetBarType(edge or barId) or barId
    local isCooldownType = (resolvedType == "cooldowns")
    local isUtilityType = (resolvedType == "utility")
    local isCDorUtil = isCooldownType or isUtilityType
    local primaryCat = isCooldownType and 0 or (isUtilityType and 1 or nil)
    local secondaryCat = isCooldownType and 1 or (isUtilityType and 0 or nil)

    local isBuffBar = edge and mod.IsBarBuffFamily(edge)

    -- Buckets for cooldown/utility bars (three-section layout)
    local priUnassigned, priAssigned = {}, {}
    local secUnassigned, secAssigned = {}, {}
    local notTracked = {}
    local itemsExtra = {}
    -- Single bucket for buff/trinket/other bars (picker only enumerates live pool members, so all spells are tracked + learned).
    local itemsDisplayed = {}

    for _, sp in ipairs(allSpells) do
        if sp.isExtra then
            if not isBuffBar then
                itemsExtra[#itemsExtra + 1] = sp
            end
        elseif isCDorUtil then
            if sp.cdmCat == primaryCat then
                if sp.onCUIBar then
                    priAssigned[#priAssigned + 1] = sp
                else
                    priUnassigned[#priUnassigned + 1] = sp
                end
            elseif sp.cdmCat == secondaryCat then
                if sp.onCUIBar then
                    secAssigned[#secAssigned + 1] = sp
                else
                    secUnassigned[#secUnassigned + 1] = sp
                end
            else
                notTracked[#notTracked + 1] = sp
            end
        else
            itemsDisplayed[#itemsDisplayed + 1] = sp
        end
    end

    -- Inner scroll container
    local inner = CreateFrame("Frame", nil, dropMenu)
    inner:SetWidth(menuW)
    inner:SetPoint("TOPLEFT")

    local mH = 4
    local allItems = {}

    -- "Remove Spell" option at top (right-click on existing icon only). The default
    -- buff bar (key=="buffs") can't remove Blizzard-tracked buffs (Blizzard's CDM owns
    -- visibility), BUT injected custom/preset buffs ARE removable there; extra buff + CD/util bars always allow removal.
    local rmSpellID = nil
    local rmIsInjected = false
    do
        local rmSd = mod.GetBarSpellData(barId)
        -- Buff bars: prefer the slot's own _previewSpellID (the default buffs bar's slots don't map to assignedSpells -- see the settings block).
        if isBuffBar then
            rmSpellID = ResolveBuffSettingsKey(anchor)
                or (rmSd and rmSd.assignedSpells and rmSd.assignedSpells[slotIndex])
        else
            rmSpellID = rmSd and rmSd.assignedSpells and rmSd.assignedSpells[slotIndex]
            if (not rmSpellID or rmSpellID == 0) and anchor and anchor._previewSpellID then
                rmSpellID = anchor._previewSpellID
            end
        end
        rmIsInjected = (
            rmSpellID
            and rmSd
            and (
                (rmSd.spellDurations and (rmSd.spellDurations[rmSpellID] or 0) > 0)
                or (rmSd.customSpellIDs and rmSd.customSpellIDs[rmSpellID])
            )
        )
                and true
            or false
    end
    if slotIndex and (barId ~= "buffs" or rmIsInjected) then
        allItems[#allItems + 1] = PlainMenuRow(
            dropMenu,
            inner,
            mH,
            ITEM_H,
            CludesUI.L("Remove Spell"),
            { FONT_PATH, 11, GetCDMOptOutline() },
            { tDimR, tDimG, tDimB, tDimA },
            hlA,
            function()
                dropMenu:Hide()
                if barId == "buffs" then
                    -- Main buffs bar: slotIndex maps to the mixed preview list (Blizzard
                    -- buffs + customs), not assignedSpells, so remove the injected custom
                    -- by spellID and clean its metadata.
                    if rmSpellID then
                        mod.RemoveSpellFromBar(barId, rmSpellID)
                        local sdR = mod.GetBarSpellData(barId)
                        if sdR and sdR.spellDurations then
                            sdR.spellDurations[rmSpellID] = nil
                        end
                        if mod.RebuildSpellRouteMap then
                            mod.RebuildSpellRouteMap()
                        end
                        if mod.QueueReanchor then
                            mod.QueueReanchor()
                        end
                    end
                else
                    -- A legacy-duplicate buff slot covers >1 assignedSpells entry
                    -- (anchorFrame._dataGroup): remove them all, highest index first.
                    -- Normal slots (cd-claim marker slots for collided buffs included,
                    -- which carry a real single-entry index) have one entry or no group.
                    local grp = anchor and anchor._dataGroup
                    if grp and #grp > 1 then
                        local sequence = {}
                        for _, v in ipairs(grp) do
                            sequence[#sequence + 1] = v
                        end
                        table.sort(sequence, function(a, b)
                            return a > b
                        end)
                        for _, gi in ipairs(sequence) do
                            mod.RemoveTrackedSpell(barId, gi)
                        end
                    else
                        mod.RemoveTrackedSpell(barId, slotIndex)
                    end
                end
                RefreshCDPreview()
            end
        )
        mH = mH + ITEM_H
    end

    -- Main buffs bar, Blizzard-tracked buff (not injected custom): can't be removed in
    -- CUI (Blizzard owns tracking), so offer a "Delete Spell" row that opens Blizzard's CDM (closes CUI options), matching the page's link behavior.
    if slotIndex and barId == "buffs" and not rmIsInjected and rmSpellID then
        allItems[#allItems + 1] = PlainMenuRow(
            dropMenu,
            inner,
            mH,
            ITEM_H,
            CludesUI.L("Delete Spell"),
            { FONT_PATH, 11, GetCDMOptOutline() },
            { tDimR, tDimG, tDimB, tDimA },
            hlA,
            function()
                dropMenu:Hide()
                if mod.OpenBlizzardCDMTab then
                    mod.OpenBlizzardCDMTab(true)
                end
            end
        )
        mH = mH + ITEM_H
    end

    -- "Talent Conditions: N" (opens the talent conditions popup for the spell).
    local function AddTalentConditionsRow(spellId, ss, ensureSettings)
        local tcConds = rawget(ss, "talentConditions")
        local tcCount = type(tcConds) == "table" and #tcConds or 0
        PlainMenuRow(
            dropMenu,
            inner,
            mH,
            ITEM_H,
            CludesUI.Lf("Talent Conditions: %1$s", tcCount > 0 and tostring(tcCount) or CludesUI.L("None")),
            { FONT_PATH, 11, GetCDMOptOutline() },
            { tDimR, tDimG, tDimB, tDimA },
            hlA,
            function()
                CludesUI.HideWidgetTooltip()
                dropMenu:Hide()
                mod.ShowCDMTalentConditionsPopup(spellId, tcConds, function(newConds)
                    ensureSettings()
                    ss.talentConditions = newConds
                    if newConds then
                        mod._cdmAnyTalentCond = true
                    end
                    RefreshCDPreview()
                end)
            end,
            {
                fit = true,
                tip = CludesUI.L("Show this icon only while the talents you pick are taken, or not taken."),
            }
        )
        mH = mH + ITEM_H
    end

    if removeOnly then
        -- Per-icon settings: CD/utility bars get the full menu; buff-family bars get a
        -- buff-specific subset. custom_buff (Auras) bars excluded here (separate system).
        -- Override editing sessions: settings would leak outside the override, so Remove only.
        if slotIndex and not isCustomBuff and not CludesUI.SpecOverrides_EditSessionActive() then
            local sd = mod.GetBarSpellData(barId)
            -- Buff bars: the preview slot's own _previewSpellID is authoritative. The
            -- default buffs bar's preview maps to a MIXED list (Blizzard buffs +
            -- injected customs), NOT to assignedSpells, so indexing assignedSpells by the
            -- preview slot returns the WRONG entry. CD/utility slots map 1:1 to assignedSpells (carrying negative trinket/item markers _previewSpellID doesn't), so keep the index path for those.
            local spellId
            if isBuffBar then
                spellId = ResolveBuffSettingsKey(anchor)
                    or (sd and sd.assignedSpells and sd.assignedSpells[slotIndex])
                -- Unresolved cd-claim slot (tracked trinket row with its buff down):
                -- key it the way the runtime reads cd-claimed slots.
                local cdClaimB = type(spellId) == "number" and mod.CdClaimMarkerToCdID(spellId)
                if cdClaimB then
                    spellId = "c" .. cdClaimB
                end
            else
                spellId = sd and sd.assignedSpells and sd.assignedSpells[slotIndex]
                if (not spellId or spellId == 0) and anchor and anchor._previewSpellID then
                    spellId = anchor._previewSpellID
                end
                -- Cd-claimed collided-buff slot: settings key is the collision "c"..
                -- cooldownID form directly -- the marker's mere presence already proves
                -- this slot's identity (no ambiguity, unlike ResolveBuffSettingsKey's buff-bar case). Matches ResolveSpellSettings' runtime key exactly (CUI_CDM_HookResolve.lua, settings["c"..cdID]).
                local cdClaimS = spellId and mod.CdClaimMarkerToCdID and mod.CdClaimMarkerToCdID(spellId)
                if cdClaimS then
                    spellId = "c" .. cdClaimS
                -- Hosted-buff MARKER slot: settings key by the DECODED spell id (the id the render resolver and the buffs bar key by), never the raw marker.
                elseif spellId and mod.HostedBuffMarkerToSpell and mod.HostedBuffMarkerToSpell(spellId) then
                    spellId = mod.HostedBuffMarkerToSpell(spellId)
                end
            end
            if mod.IsEmptySlotMarker(spellId) then
                -- Empty slots only expose identity-level conditions, never icon styling.
                if not isBuffBar and not (edge and edge.isGhostBar) then
                    local storage = mod.GetSpellSettingsStore(barId, true)
                    if storage then
                        local ss = storage[spellId] or {}
                        AddTalentConditionsRow(spellId, ss, function()
                            storage[spellId] = ss
                        end)
                    end
                end
            elseif spellId and spellId ~= 0 then
                -- Hosted-buff SLOT? The slot decides, not the flag alone: the same
                -- spellID can also be this bar's cooldown entry, which must keep the CD
                -- store + cd/util menu. Legacy fallback: flag set with no marker entry yet means the plain entry is the buff (pre-marker data).
                local isHostedBuff = (anchor and anchor._previewHostedBuff) or false
                if
                    not isHostedBuff
                    and sd
                    and sd.hostedBuffSpellIDs
                    and sd.hostedBuffSpellIDs[spellId]
                    and not (
                        mod.ListHasHostedMarker
                        and sd.assignedSpells
                        and mod.ListHasHostedMarker(sd.assignedSpells, spellId)
                    )
                then
                    isHostedBuff = true
                end
                -- Per-spell entries live in the spec FAMILY store (travel with the spell
                -- across bars); bar tiers sit below them: sd.barSettings ("Apply to Bar")
                -- -> bd.barSpellSettings ("Apply to Bar (All Specs)"). A hosted buff uses the BUFF store (same entry as on the buffs bar) and never chains to this bar's cd/util tiers.
                local storage = mod.GetSpellSettingsStore(isHostedBuff and "buffs" or barId, true)
                local bdSel = mod.barDataByKey and mod.barDataByKey[barId]
                local famKey = mod.SettingsFamilyKey(isHostedBuff and "buffs" or barId)
                -- Effective-read view: the entry (or a not-yet-persisted fresh table)
                -- chained to the bar tiers, so the menu shows the values the icon actually renders with; EnsureSS() persists the entry on first WRITE.
                local ss = storage and storage[spellId]
                -- An entry saved under another form of this spell (its base or
                -- its talent override: the spell was added to this bar in
                -- another form than the one its settings were made on) is the
                -- one the icon renders with: show and edit that one.
                if not ss and storage then
                    ss = mod.ResolveVariantValue(storage, spellId)
                    if type(ss) ~= "table" then
                        ss = nil
                    end
                end
                if not ss then
                    -- A cooldownID-keyed slot with no entry yet renders its spell's entry
                    -- (the runtime falls back to it): start from a copy, so the first
                    -- write keeps those values instead of shadowing them.
                    local source = type(spellId) == "string"
                        and storage
                        and anchor
                        and anchor._previewSpellID
                        and storage[anchor._previewSpellID]
                    ss = type(source) == "table" and CopyTable(source) or {}
                end
                mod.ChainSettings(ss, (not isHostedBuff) and mod.GetBarTierSettings(sd, barId) or nil)
                local function EnsureSS()
                    -- An entry found under another form of the spell is stored already.
                    if
                        storage
                        and not storage[spellId]
                        and mod.ResolveVariantValue(storage, spellId) ~= ss
                    then
                        storage[spellId] = ss
                        -- New per-spell entry: retire memoized resolution results so every icon re-resolves against it.
                        mod._cdmResGen = (mod._cdmResGen or 0) + 1
                        -- Flip the runtime hot-path gate the moment a cooldownID-scoped buff entry is first persisted.
                        if
                            type(spellId) == "string"
                            and string.byte(spellId, 1) == 99
                            and mod.MarkBuffFamHasCdKey
                        then
                            mod.MarkBuffFamHasCdKey()
                        end
                    end
                    return ss
                end
                -- Own-value writer for clearable keys: writing nil would let an inherited
                -- bar-tier value show through; when that would change the effective value,
                -- store explicit false instead (render-equivalent to nil, but blocks inheritance).
                local function SetOwn(key, val)
                    ss[key] = val
                    if val == nil and ss[key] ~= nil then
                        ss[key] = false
                    end
                end

                -----------------------------------------------------------
                --  "Apply to Bar" machinery (hover strip on flyout items). One table
                --  local (AB) instead of individual locals: this function is enormous and Lua 5.1 caps active locals at 200.
                -----------------------------------------------------------
                local AB = {}
                -- A new menu row at the menu's current bottom (mH): the row button,
                -- full width less a pixel each side, and its left-hand caption.
                AB.NewMenuRow = function(caption)
                    local row = CreateFrame("Button", nil, inner)
                    row:SetHeight(ITEM_H)
                    row:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                    row:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                    row:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                    local labelFS = row:CreateFontString(nil, "OVERLAY")
                    labelFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    labelFS:SetPoint("LEFT", 10, 0)
                    labelFS:SetJustifyH("LEFT")
                    labelFS:SetText(CludesUI.L(caption))
                    return row, labelFS
                end
                -- A colour row's Custom item ("<key>" set to "custom", the colour in
                -- <key>R/G/B, default 1, g, b): CustomColorSwatch is its flyout hook,
                -- a swatch on the Custom item whose first click also picks Custom and
                -- keeps the flyout open, re-lit; CustomColorApply is the row's Apply to
                -- Bar, carrying the colour with the mode when the mode is Custom.
                AB.CustomColorSwatch = function(key, g, b)
                    local rKey, gKey, bKey = key .. "R", key .. "G", key .. "B"
                    return function(si, item, sub)
                        if item.val ~= "custom" then
                            return
                        end
                        si._noCapture = true
                        local swatchBtn, refreshSwatch = CludesUI.BuildColorSwatch(
                            si,
                            si:GetFrameLevel() + 3,
                            function()
                                return ss[rKey] or 1, ss[gKey] or g, ss[bKey] or b, 1
                            end,
                            function(nr, ng, nb)
                                ss[rKey], ss[gKey], ss[bKey] = nr, ng, nb
                                if mod.RefreshCDMIconAppearance then
                                    mod.RefreshCDMIconAppearance(barId)
                                end
                            end,
                            false,
                            14
                        )
                        swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                        si._refreshSwatch = refreshSwatch
                        swatchBtn:HookScript("PreClick", function()
                            EnsureSS()
                            ss[key] = "custom"
                            if not ss[rKey] then
                                ss[rKey], ss[gKey], ss[bKey] = 1, g, b
                            end
                            if sub._refreshSelection then
                                sub._refreshSelection()
                            end
                        end)
                    end
                end
                AB.CustomColorApply = function(key, g, b)
                    local rKey, gKey, bKey = key .. "R", key .. "G", key .. "B"
                    return {
                        apply = {
                            keys = { key, rKey, gKey, bKey },
                            write = function(t, v)
                                t[key] = v
                                if v == "custom" then
                                    t[rKey], t[gKey], t[bKey] = ss[rKey] or 1, ss[gKey] or g, ss[bKey] or b
                                else
                                    t[rKey], t[gKey], t[bKey] = nil, nil, nil
                                end
                            end,
                        },
                    }
                end
                -- The value a scope table holds for an apply key, read the way the
                -- Cooldown State Effect pair reads it (raw = the table's own value
                -- only). A glow saved in cdStateEffect, the single-value form,
                -- belongs to the glow key: for the hide key it reads as a blocking
                -- false while a hide below would otherwise show through, else as
                -- nothing. A glow reads as its menu value, a button* name moved
                -- into cdStateGlow included. Every other key reads as stored.
                AB.ScopeVal = function(t, k, raw)
                    if not t then
                        return nil
                    end
                    local v
                    if raw then
                        v = rawget(t, k)
                    else
                        v = t[k]
                    end
                    if k == "cdStateEffect" and v and mod.CD_STATE_GLOWS[v] then
                        local mt = getmetatable(t)
                        local p = mt and mt.__index
                        if type(p) == "table" and mod.CdStateHideOf(p) ~= nil then
                            return false
                        end
                        return nil
                    elseif k == "cdStateGlow" then
                        if v == nil then
                            if raw then
                                v = rawget(t, "cdStateEffect")
                            else
                                v = t.cdStateEffect
                            end
                            if not (v and mod.CD_STATE_GLOWS[v]) then
                                return nil
                            end
                        end
                        return (v and mod.CD_STATE_GLOWS[v]) or v
                    end
                    return v
                end
                -- True when an apply's keys hold either half of the pair: such an
                -- apply moves a single-value glow into cdStateGlow on every table it
                -- stamps or clears first (ns.CdStateSplitLegacy).
                AB.TouchesCdState = function(keyList)
                    if not keyList then
                        return false
                    end
                    for _, k in ipairs(keyList) do
                        if k == "cdStateEffect" or k == "cdStateGlow" then
                            return true
                        end
                    end
                    return false
                end
                -- Run fn(sid, entry) for every per-spell entry belonging to a bar in the
                -- given spec profile. The DEFAULT buffs bar owns every buff-store entry not claimed by another buff bar (Blizzard-tracked buffs aren't in assignedSpells).
                AB.ForEachMemberEntry = function(prof, bsX, func)
                    local st = prof and prof[famKey]
                    if not st then
                        return
                    end
                    if barId == "buffs" then
                        local claimed = {}
                        local bsAll = prof.barSpells
                        if bsAll then
                            for k2, b2 in pairs(bsAll) do
                                if
                                    k2 ~= "buffs"
                                    and type(b2) == "table"
                                    and mod.IsBarBuffFamily
                                    and mod.IsBarBuffFamily(k2)
                                    and type(b2.assignedSpells) == "table"
                                then
                                    for _, sid2 in ipairs(b2.assignedSpells) do
                                        claimed[sid2] = true
                                        -- A cd-claimed member is listed by its MARKER but stores
                                        -- its settings under "c"..cooldownID; claim both or this
                                        -- bar's entry reads as unclaimed and gets wiped.
                                        local cdID2 = mod.CdClaimMarkerToCdID
                                            and mod.CdClaimMarkerToCdID(sid2)
                                        if cdID2 then
                                            claimed["c" .. cdID2] = true
                                        end
                                    end
                                end
                                -- Also exclude HOSTED buffs (on cd/util bars): removed from Apply-to-Bar,
                                -- so a default-buffs-bar apply must not treat their buff-store entry as unclaimed and wipe it.
                                AB.ForEachHostedKey(b2, function(hkey)
                                    claimed[hkey] = true
                                end)
                            end
                        end
                        for sid2, e in pairs(st) do
                            if type(e) == "table" and not claimed[sid2] then
                                func(sid2, e)
                            end
                        end
                    elseif bsX and type(bsX.assignedSpells) == "table" then
                        -- Hosted buffs are excluded from Apply-to-Bar: never treat one as a
                        -- bar member (so a bar apply can't clear/overwrite its per-spell settings).
                        local hosted = bsX.hostedBuffSpellIDs
                        for _, sid2 in ipairs(bsX.assignedSpells) do
                            if not (hosted and hosted[sid2]) then
                                local e = st[sid2]
                                if type(e) == "table" then
                                    func(sid2, e)
                                end
                            end
                        end
                    end
                end

                -- Zero-cost feature gates: a bar-tier write can enable features
                -- the per-spell setters normally arm -- flip the same flags.
                AB.FlipSessionGates = function(t)
                    if not t then
                        return
                    end
                    if t.reverseSwipe then
                        mod._cdmAnyReverseSwipe = true
                    end
                    if t.hideCDSwipe then
                        mod._cdmAnyHideCDSwipe = true
                    end
                    if (tonumber(t.thresholdSeconds) or 0) > 0 then
                        mod._cdmAnyThresholdText = true
                    end
                    if t.maxStacksGlow and t.maxStacksGlow > 0 then
                        mod._cdmAnyMaxStacksGlow = true
                    end
                    if t.desatNotActive then
                        mod._cdmAnyDesatNotActive = true
                    end
                    if t.noDesatOnCD then
                        mod._cdmAnyNoDesatOnCD = true
                    end
                    if t.noResourceTint then
                        mod._cdmAnyNoResourceTint = true
                    end
                    if t.chargeHideCdText then
                        mod._cdmAnyChargeHideCdText = true
                    end
                    if t.hideChargeText then
                        mod._cdmAnyHideChargeText = true
                    end
                    if t.suppressGCD then
                        mod._cdmAnySuppressGcd = true
                    end
                    if t.chargeHideSwipe or t.hideRechargeEdge then
                        mod._cdmAnyChargeStyle = true
                    end
                    if t.cdReadySoundKey and t.cdReadySoundKey ~= "none" then
                        mod._cdmAnyCdReadySound = true
                    end
                    if
                        (t.buffActiveSoundKey and t.buffActiveSoundKey ~= "none")
                        or (t.buffLostSoundKey and t.buffLostSoundKey ~= "none")
                    then
                        mod._cdmAnyBuffSound = true
                    end
                end

                -- Any Resource Aware CD-ready glow already saved in this spec
                -- (per-spell entries or bar tiers, in either saved form)? Gates the
                -- one-time perf confirm popup, mirroring the per-spell setter.
                AB.AnyResourceAwareGlowSaved = function()
                    local function hit(b)
                        return AB.ScopeVal(b, "cdStateGlow", true) == "pixelGlowReadyUsable"
                    end
                    local st = mod.GetSpellSettingsStore and mod.GetSpellSettingsStore(barId)
                    if st then
                        for _, e in pairs(st) do
                            if type(e) == "table" and hit(e) then
                                return true
                            end
                        end
                    end
                    local cb = mod.ECME
                        and mod.ECME.db
                        and mod.ECME.db.profile
                        and mod.ECME.db.profile.cdmBars
                    local barsList = cb and cb.bars
                    if barsList then
                        for _, b2 in ipairs(barsList) do
                            if hit(b2.barSpellSettings) then
                                return true
                            end
                            local bsd = mod.GetBarSpellData and mod.GetBarSpellData(b2.key)
                            if bsd and hit(bsd.barSettings) then
                                return true
                            end
                        end
                    end
                    return false
                end

                -- Keys that preset/custom icons route through the profile-level
                -- customActiveStates store instead of the ss/tier chain (Fake-Active
                -- engine reads rule.cas first); a bar apply touching any of these also stamps each preset member's cas entry, so "Apply to Bar" styles preset icons too.
                AB.CAS_KEYS = {
                    activeSwipeMode = true,
                    activeSwipeClassColor = true,
                    activeSwipeR = true,
                    activeSwipeG = true,
                    activeSwipeB = true,
                    activeSwipeA = true,
                    activeGlow = true,
                    glowColor = true,
                    glowColorR = true,
                    glowColorG = true,
                    glowColorB = true,
                    cdStateEffect = true,
                    cdStateLowerAlpha = true,
                    cdStateGlow = true,
                    cdStateGlowStyle = true,
                    cdStateGlowAlpha = true,
                    reverseSwipe = true,
                    hideCDSwipe = true,
                    stanceBarHide = true,
                    thresholdSeconds = true,
                    thresholdDecimals = true,
                    thresholdColorEnabled = true,
                    thresholdColorR = true,
                    thresholdColorG = true,
                    thresholdColorB = true,
                }
                -- Keys a bar apply also stamps onto the bar's HOSTED buffs. A hosted buff
                -- never chains to the bar tiers -- the tier carries cd-bar meaning for shared
                -- keys (Duration Text, Border) and its entry is the same one the spell uses on
                -- a buffs bar -- so a bar apply otherwise skips it entirely. These keys read
                -- the same on any icon, so they stamp directly, like preset icons do through
                -- StampMemberCas. Only rows whose keys are ALL in here stamp.
                AB.HOSTED_KEYS = {
                    thresholdSeconds = true,
                    thresholdDecimals = true,
                    thresholdColorEnabled = true,
                    thresholdColorR = true,
                    thresholdColorG = true,
                    thresholdColorB = true,
                }
                -- Hosted buffs keep their entries in the BUFF family store whatever family the host bar belongs to.
                AB.hostedFamKey = mod.SettingsFamilyKey("buffs")
                AB.TouchesHosted = function(keyList)
                    if not keyList or #keyList == 0 then
                        return false
                    end
                    for _, k in ipairs(keyList) do
                        if not AB.HOSTED_KEYS[k] then
                            return false
                        end
                    end
                    return true
                end
                -- Every BUFF-store key the bar's hosted buffs use. Two shapes: a plain spell id
                -- from hostedBuffSpellIDs, and "c"..cooldownID for a CD-CLAIMED slot, whose
                -- marker lives in assignedSpells while hostedBuffSpellIDs carries only the
                -- existence sentinel AddHostedBuffByCdID sets. That sentinel doubles as the
                -- gate: a buff-family bar never sets it, so its own cd-claim markers (ordinary
                -- members via AddTrackedBuffByCdID, not hosted) are never read as hosted slots.
                -- Whether a bar member is one of the bar's injected icons (a preset,
                -- one of your racials or a custom spell, whose settings live in
                -- customActiveStates), not a hosted buff's marker, which is a real
                -- Blizzard buff frame moved onto the bar.
                AB.IsInjectedMember = function(bsX, sid)
                    local injected = (type(sid) == "number" and sid < 0)
                        or (mod._myRacialsSet and mod._myRacialsSet[sid])
                        or (bsX.customSpellIDs and bsX.customSpellIDs[sid])
                    if not injected then
                        return false
                    end
                    return not (mod.HostedBuffMarkerToSpell and mod.HostedBuffMarkerToSpell(sid))
                end
                AB.ForEachHostedKey = function(bsX, func)
                    if type(bsX) ~= "table" or type(bsX.hostedBuffSpellIDs) ~= "table" then
                        return
                    end
                    for hsid in pairs(bsX.hostedBuffSpellIDs) do
                        func(hsid)
                    end
                    if type(bsX.assignedSpells) == "table" and mod.CdClaimMarkerToCdID then
                        for _, sid2 in ipairs(bsX.assignedSpells) do
                            local cdID = mod.CdClaimMarkerToCdID(sid2)
                            if cdID then
                                func("c" .. cdID)
                            end
                        end
                    end
                end
                -- Stamp one spec profile's hosted buffs on this bar. Blocking-false has nothing
                -- to block here (hosted entries chain to no tier), so an "off" apply clears the
                -- keys instead, and an entry left empty is dropped.
                AB.StampHostedBuffs = function(prof, bsX, applyWrite, val, keyList)
                    local st
                    local mintedCdKey = false
                    AB.ForEachHostedKey(bsX, function(hkey)
                        -- Resolved on the first hosted key, not up front: an All Specs apply on
                        -- a bar with no hosted buffs would otherwise mint an empty family store
                        -- in every spec profile.
                        st = st
                            or (
                                mod.GetSpellSettingsStoreForProf
                                and mod.GetSpellSettingsStoreForProf(prof, AB.hostedFamKey, true)
                            )
                        if not st then
                            return
                        end
                        local e, fresh = st[hkey], false
                        if not e then
                            e = {}
                            st[hkey] = e
                            fresh = true
                        end
                        applyWrite(e, val)
                        -- Only the keys this apply wrote: reaching across the whole set would
                        -- drop blocking-false values the apply never touched, and the un-stamp
                        -- walks `keys` too, so it could not put them back.
                        for _, k in ipairs(keyList) do
                            if rawget(e, k) == false then
                                e[k] = nil
                            end
                        end
                        if next(e) == nil then
                            st[hkey] = nil
                        elseif fresh and type(hkey) == "string" then
                            mintedCdKey = true
                        end
                    end)
                    -- A newly minted "c"..cooldownID entry stays invisible to the runtime until
                    -- the buff-family cd-key gate flips, the same call the menu's EnsureSS makes.
                    if mintedCdKey and mod.MarkBuffFamHasCdKey then
                        mod.MarkBuffFamHasCdKey()
                    end
                end
                AB.StampMemberCas = function(bsX, applyWrite, val, keyList)
                    if not (bsX and type(bsX.assignedSpells) == "table") then
                        return
                    end
                    if not (mod.GetCustomActiveState and mod.ResolveCustomActiveKey) then
                        return
                    end
                    -- cas semantics: nil = no cd-state effect (PresetHasCdState checks effect
                    -- presence); explicit blocking-false is a tier/per-trinket-exclusion concept -- strip it from stamps. Threshold Text keys share the same cas semantics.
                    local function StripFalse(e)
                        if e.cdStateEffect == false then
                            e.cdStateEffect = nil
                        end
                        if e.cdStateGlow == false then
                            e.cdStateGlow = nil
                        end
                        if e.thresholdSeconds == false then
                            e.thresholdSeconds = nil
                        end
                        if e.thresholdDecimals == false then
                            e.thresholdDecimals = nil
                        end
                        if e.thresholdColorEnabled == false then
                            e.thresholdColorEnabled = nil
                        end
                    end
                    for _, sid2 in ipairs(bsX.assignedSpells) do
                        if AB.IsInjectedMember(bsX, sid2) then
                            if mod.SlotIDFromKey(sid2) then
                                -- Equipment slots stamp the SLOT entry: one bar application
                                -- covers whatever item is equipped, now or after any swap -- no entry minted per equipped item.
                                local e = mod.GetCustomActiveState(sid2, true)
                                if e then
                                    applyWrite(e, val)
                                    StripFalse(e)
                                end
                                -- Clear the applied keys from the EQUIPPED trinket's own
                                -- (item-keyed) entry so the apply visibly takes effect on it
                                -- (mirrors the member-entry clear RunBarApply does for family keys).
                                -- A per-trinket exclusion is re-chosen in the menu AFTER an apply; benched trinkets keep their per-item choices untouched.
                                local itemId = GetInventoryItemID("player", -sid2)
                                local own = itemId and mod.GetCustomActiveState(-itemId) or nil
                                if own and keyList then
                                    -- A single-value glow there first moves to cdStateGlow,
                                    -- read over the slot entry as the icon reads it.
                                    if AB.TouchesCdState(keyList) then
                                        mod.ChainSettings(own, e)
                                        mod.CdStateSplitLegacy(own)
                                    end
                                    for _, k2 in ipairs(keyList) do
                                        own[k2] = nil
                                    end
                                end
                            else
                                local e = mod.GetCustomActiveState(mod.ResolveCustomActiveKey(sid2), true)
                                if e then
                                    applyWrite(e, val)
                                    StripFalse(e)
                                end
                            end
                        end
                    end
                end

                -- How many existing values would this apply REPLACE? Counts member per-spell
                -- entries (and preset cas entries / other specs' bar-tier values for All Specs)
                -- whose own value for a touched key differs -- equal values cost zero and don't count. Drives the "overwrite?" confirm popup.
                AB.CountApplyOverwrites = function(keyList, applyWrite, val, allSpecs)
                    keyList = keyList or {}
                    if #keyList == 0 or not applyWrite then
                        return 0
                    end
                    -- Simulate the write to learn the concrete per-key values.
                    local temp = {}
                    applyWrite(temp, val)
                    local touchesCas = false
                    for _, k in ipairs(keyList) do
                        if AB.CAS_KEYS[k] then
                            touchesCas = true
                            break
                        end
                    end
                    local touchesHosted = AB.TouchesHosted(keyList)
                    local count = 0
                    local CAS_FALSE_STRIPPED = {
                        cdStateEffect = true,
                        cdStateGlow = true,
                        thresholdSeconds = true,
                        thresholdDecimals = true,
                        thresholdColorEnabled = true,
                    }
                    -- The value a table holds for a key, as the count compares it: a
                    -- button* glow with no Glow Style of its own holds the Action
                    -- Button Glow style its name implies, which an apply with another
                    -- style replaces.
                    local function ownOf(t, k, raw)
                        local own = AB.ScopeVal(t, k, raw)
                        if own == nil and k == "cdStateGlowStyle" then
                            local g = rawget(t, "cdStateGlow")
                            if g == nil then
                                g = rawget(t, "cdStateEffect")
                            end
                            local cg = g and mod.CD_STATE_GLOWS[g]
                            if cg and cg ~= g then
                                own = 3
                            end
                        end
                        return own
                    end
                    local function entryLoses(e, isCas)
                        for _, k in ipairs(keyList) do
                            local own = ownOf(e, k, true)
                            local new = temp[k]
                            -- cas stamping normalizes the blocking-false away.
                            if isCas and CAS_FALSE_STRIPPED[k] and new == false then
                                new = nil
                            end
                            if own ~= nil and own ~= new then
                                return true
                            end
                        end
                        return false
                    end
                    local function sweep(prof)
                        if type(prof) ~= "table" then
                            return
                        end
                        local bsX = prof.barSpells and prof.barSpells[barId]
                        if allSpecs and bsX and type(bsX.barSettings) == "table" then
                            for _, k in ipairs(keyList) do
                                local own = ownOf(bsX.barSettings, k)
                                if own ~= nil and own ~= temp[k] then
                                    count = count + 1
                                    break
                                end
                            end
                        end
                        AB.ForEachMemberEntry(prof, bsX, function(_, e)
                            if entryLoses(e, false) then
                                count = count + 1
                            end
                        end)
                        if
                            touchesCas
                            and bsX
                            and type(bsX.assignedSpells) == "table"
                            and mod.GetCustomActiveState
                            and mod.ResolveCustomActiveKey
                        then
                            for _, sid2 in ipairs(bsX.assignedSpells) do
                                if AB.IsInjectedMember(bsX, sid2) then
                                    -- Trinket slots resolve to the EQUIPPED item's own entry
                                    -- (the values the stamp will clear); the slot entry is the bar-level stamp itself (analogous to the tier) and is not counted.
                                    local e = mod.GetCustomActiveState(mod.ResolveCustomActiveKey(sid2))
                                    if e and entryLoses(e, true) then
                                        count = count + 1
                                    end
                                end
                            end
                        end
                        -- Hosted buffs stamp their own entries (StampHostedBuffs), under the same blocking-false normalization the cas stamps use.
                        if touchesHosted then
                            local st = prof[AB.hostedFamKey]
                            if st then
                                AB.ForEachHostedKey(bsX, function(hkey)
                                    local e = st[hkey]
                                    if type(e) == "table" and entryLoses(e, true) then
                                        count = count + 1
                                    end
                                end)
                            end
                        end
                    end
                    local spAll = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
                    if allSpecs then
                        if spAll then
                            for _, prof in pairs(spAll) do
                                sweep(prof)
                            end
                        end
                    else
                        local specKeyA = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
                        local prof = spAll and specKeyA and spAll[specKeyA]
                        if prof then
                            sweep(prof)
                        end
                    end
                    return count
                end

                -- Write a picked value into a bar tier and clear the shadowing per-spell
                -- overrides from the bar's member spells, so the apply visibly takes effect
                -- everywhere. allSpecs writes the profile-level bd tier (which specs with no CDM data yet inherit) and sweeps every spec's spec-tier + overrides.
                AB.RunBarApply = function(applyKeys, applyWrite, val, allSpecs)
                    if not applyWrite then
                        return
                    end
                    local keyList = applyKeys or {}
                    -- Resolve the value ONCE, before anything below clears a thing. A payload
                    -- writer (custom colour, Threshold Seconds) reads the source spell's own keys
                    -- back out of its entry, and the sweeps clear exactly those keys -- re-running
                    -- it per tier and per stamp would make the result depend on sweep order.
                    local temp = {}
                    applyWrite(temp, val)
                    -- A Cooldown State Effect apply first moves a single-value glow on
                    -- every table it stamps or clears into cdStateGlow, so the half of
                    -- the pair it leaves alone keeps its look.
                    local splitCd = AB.TouchesCdState(keyList)
                    local function stamp(t)
                        if splitCd then
                            mod.CdStateSplitLegacy(t)
                        end
                        for _, k in ipairs(keyList) do
                            t[k] = temp[k]
                        end
                    end
                    local touchesCas = false
                    for _, k in ipairs(keyList) do
                        if AB.CAS_KEYS[k] then
                            touchesCas = true
                            break
                        end
                    end
                    local touchesHosted = AB.TouchesHosted(keyList)
                    local function sweepProf(prof)
                        if type(prof) ~= "table" then
                            return
                        end
                        -- Sweeps can delete emptied member entries and the per-spec tier: retire memoized resolution results.
                        mod._cdmResGen = (mod._cdmResGen or 0) + 1
                        local bsX = prof.barSpells and prof.barSpells[barId]
                        local absX = bdSel and bdSel.barSpellSettings
                        if allSpecs and bsX and type(bsX.barSettings) == "table" then
                            if splitCd then
                                mod.ChainSettings(bsX.barSettings, absX)
                                mod.CdStateSplitLegacy(bsX.barSettings)
                            end
                            for _, k in ipairs(keyList) do
                                bsX.barSettings[k] = nil
                            end
                            if next(bsX.barSettings) == nil then
                                bsX.barSettings = nil
                            end
                        end
                        -- The bar tier a member entry of this spec renders over: a split
                        -- reads the entry through it, as the icon does.
                        local tierX = absX
                        if splitCd and bsX and type(bsX.barSettings) == "table" then
                            mod.ChainSettings(bsX.barSettings, absX)
                            tierX = bsX.barSettings
                        end
                        AB.ForEachMemberEntry(prof, bsX, function(sid2, e)
                            if splitCd then
                                mod.ChainSettings(e, tierX)
                                mod.CdStateSplitLegacy(e)
                            end
                            for _, k in ipairs(keyList) do
                                rawset(e, k, nil)
                            end
                            if next(e) == nil then
                                local st = prof[famKey]
                                if st then
                                    st[sid2] = nil
                                end
                            end
                        end)
                        if touchesCas then
                            AB.StampMemberCas(bsX, stamp, val, keyList)
                        end
                        if touchesHosted then
                            AB.StampHostedBuffs(prof, bsX, stamp, val, keyList)
                        end
                    end
                    if allSpecs then
                        if not bdSel then
                            return
                        end
                        local abs = bdSel.barSpellSettings
                        if not abs then
                            abs = {}
                            bdSel.barSpellSettings = abs
                            -- New tier table: chained results are stale.
                            mod._cdmResGen = (mod._cdmResGen or 0) + 1
                        end
                        stamp(abs)
                        AB.FlipSessionGates(abs)
                        local spAll = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
                        if spAll then
                            for _, prof in pairs(spAll) do
                                sweepProf(prof)
                            end
                        end
                    else
                        -- Mutual exclusivity: applying to THIS bar (this spec) removes any
                        -- "Apply to Bar (All Specs)" apply for these keys, so the two scopes are
                        -- never both active (the reverse -- an All Specs apply clearing the
                        -- per-spec tier across every spec -- is handled by sweepProf above).
                        -- The canonical unapply also cleans up preset cas stamps; the per-spec write below then re-stamps THIS spec's members. No-op (and no refresh) when All Specs isn't active.
                        AB.RunBarUnapply(keyList, true)
                        local bs = sd.barSettings
                        if not bs then
                            bs = {}
                            sd.barSettings = bs
                            -- New tier table: chained results are stale.
                            mod._cdmResGen = (mod._cdmResGen or 0) + 1
                        end
                        mod.ChainSettings(bs, bdSel and bdSel.barSpellSettings)
                        -- A hide stamped here shadows a single-value glow the all-specs
                        -- tier holds: this tier keeps the glow it showed, as saved, as
                        -- a menu pick does.
                        local glowBefore = splitCd and mod.CdStateGlowOf(bs) or nil
                        stamp(bs)
                        if
                            glowBefore
                            and rawget(bs, "cdStateGlow") == nil
                            and mod.CdStateGlowOf(bs) == nil
                        then
                            bs.cdStateGlow = glowBefore
                        end
                        AB.FlipSessionGates(bs)
                        local spAll = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
                        local specKeyA = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
                        local prof = spAll and specKeyA and spAll[specKeyA]
                        if prof then
                            sweepProf(prof)
                        end
                    end
                    -- The open menu's view keeps reading through the (possibly freshly created) tier chain.
                    mod.ChainSettings(ss, mod.GetBarTierSettings(sd, barId))
                    if touchesCas and mod.FakeActive_Rearm then
                        mod.FakeActive_Rearm()
                    end
                    if mod.RefreshCDMIconAppearance then
                        mod.RefreshCDMIconAppearance(barId)
                    end
                    if mod.QueueReanchor then
                        mod.QueueReanchor()
                    end
                end

                -- True when a BAR tier drives this setting -- "Apply to Bar" (this spec) or
                -- "Apply to Bar (All Specs)" holds a value for any of these keys. A blocking
                -- false counts (bar-spec "= Default" apply). Exclusion is per-spell now (SpellHasOwn), so there's no spec-level carve-out here: this only answers "does the bar drive this setting".
                AB.KeysBarApplied = function(keyList)
                    if not keyList then
                        return false
                    end
                    local bs = sd.barSettings
                    local abs = bdSel and bdSel.barSpellSettings
                    for _, k in ipairs(keyList) do
                        if
                            (bs and AB.ScopeVal(bs, k, true) ~= nil) or (abs and AB.ScopeVal(abs, k) ~= nil)
                        then
                            return true
                        end
                    end
                    return false
                end

                -- True when the SPELL holds its OWN value for any of these keys (a
                -- per-spell override in THIS spec's store) -- the "excluded from the bar"
                -- state, having broken out of the bar apply. Inherently per spell AND spec (store is the active spec's profile).
                AB.SpellHasOwn = function(keyList)
                    if not (keyList and ss) then
                        return false
                    end
                    for _, k in ipairs(keyList) do
                        if AB.ScopeVal(ss, k, true) ~= nil then
                            return true
                        end
                        -- An own hide or None that shadows a single-value glow the
                        -- bar tiers hold is the spell's own "no glow": it reads as
                        -- excluded from the bar's glow, and Include rejoins it.
                        if
                            k == "cdStateGlow"
                            and rawget(ss, "cdStateGlow") == nil
                            and rawget(ss, "cdStateEffect") ~= nil
                            and mod.CdStateGlowOf(ss) == nil
                        then
                            local mt = getmetatable(ss)
                            local p = mt and mt.__index
                            if type(p) == "table" and mod.CdStateGlowOf(p) ~= nil then
                                return true
                            end
                        end
                    end
                    return false
                end

                -- Include This Spell: drop this spell's own value for these keys so it
                -- rejoins the bar apply (per spell+spec; caller does the UI refresh). Shared by the b3 button and by Apply to Bar/All Specs on an already-excluded spell (same thing).
                AB.IncludeSpell = function(keyList)
                    if not (keyList and ss) then
                        return
                    end
                    -- A single-value glow on the spell moves to cdStateGlow first, so
                    -- the half of the pair these keys leave keeps its look.
                    local glowKeys = false
                    if AB.TouchesCdState(keyList) then
                        mod.CdStateSplitLegacy(ss)
                        for _, k in ipairs(keyList) do
                            if k == "cdStateGlow" then
                                glowKeys = true
                            end
                        end
                    end
                    for _, k in ipairs(keyList) do
                        rawset(ss, k, nil)
                    end
                    local tier = mod.GetBarTierSettings(sd, barId)
                    mod.ChainSettings(ss, tier)
                    -- A bar glow saved in the single-value form is shadowed by a hide
                    -- this spell keeps: to rejoin it, the tier holding it moves it to
                    -- cdStateGlow, which no hide above shadows.
                    if glowKeys and tier and AB.MenuGlow(ss) ~= AB.MenuGlow(tier) then
                        local t = tier
                        for _ = 1, 2 do
                            if type(t) ~= "table" or mod.CdStateSplitLegacy(t) then
                                break
                            end
                            local mt = getmetatable(t)
                            t = mt and mt.__index
                        end
                    end
                end

                -- Remove an active apply from one scope: clears the setting's keys from that
                -- tier only. Per-spell values and the OTHER scope are left alone (bar falls
                -- through to all-specs/defaults). Preset members' cas stamps are removed only when they still EQUAL the removed value -- per-icon cas tweaks made after the apply survive.
                AB.RunBarUnapply = function(applyKeys, allSpecs)
                    local keyList = applyKeys or {}
                    local t
                    if allSpecs then
                        t = bdSel and bdSel.barSpellSettings
                    else
                        t = sd.barSettings
                    end
                    if not t then
                        return
                    end
                    -- Cooldown State Effect: removing the glow takes a single-value glow
                    -- too (moved to cdStateGlow first). That glow is no hide apply, so
                    -- removing the hide leaves it, unless it blocks a hide below: then
                    -- it moves first and only the block it held goes.
                    local glowKeys, hideKeys = false, false
                    for _, k in ipairs(keyList) do
                        if k == "cdStateGlow" then
                            glowKeys = true
                        elseif k == "cdStateEffect" then
                            hideKeys = true
                        end
                    end
                    if glowKeys or hideKeys then
                        if not allSpecs then
                            mod.ChainSettings(t, bdSel and bdSel.barSpellSettings)
                        end
                        if glowKeys or AB.ScopeVal(t, "cdStateEffect", true) == false then
                            mod.CdStateSplitLegacy(t)
                        end
                    end
                    local removed = {}
                    local touchesCas = false
                    for _, k in ipairs(keyList) do
                        if AB.CAS_KEYS[k] then
                            touchesCas = true
                        end
                        local own = rawget(t, k)
                        if not (k == "cdStateEffect" and own and mod.CD_STATE_GLOWS[own]) then
                            removed[k] = own
                            rawset(t, k, nil)
                        end
                    end
                    local touchesHosted = AB.TouchesHosted(keyList)
                    if next(t) == nil then
                        if allSpecs then
                            if bdSel then
                                bdSel.barSpellSettings = nil
                            end
                        else
                            sd.barSettings = nil
                        end
                        -- Tier table dropped: chained results are stale.
                        mod._cdmResGen = (mod._cdmResGen or 0) + 1
                    end
                    if touchesCas and mod.GetCustomActiveState and mod.ResolveCustomActiveKey then
                        -- Remove still-equal stamped values from one cas entry. rawget: a
                        -- trinket item entry may be CHAINED to its slot entry, and an inherited
                        -- value must not read as an own stamp (clearing own nil is a no-op, but the equality test has to see own values only).
                        local function unstampEntry(e)
                            if not e then
                                return
                            end
                            -- A stamped single-value glow is compared as the cdStateGlow it moves to.
                            if glowKeys then
                                mod.CdStateSplitLegacy(e)
                            end
                            for _, k in ipairs(keyList) do
                                local rv = removed[k]
                                -- cas never stores the blocking-false (cdStateEffect, cdStateGlow + Threshold Text keys).
                                if
                                    rv == false
                                    and (
                                        k == "cdStateEffect"
                                        or k == "cdStateGlow"
                                        or k == "thresholdSeconds"
                                        or k == "thresholdDecimals"
                                        or k == "thresholdColorEnabled"
                                    )
                                then
                                    rv = nil
                                end
                                if rv ~= nil and rawget(e, k) == rv then
                                    e[k] = nil
                                end
                            end
                        end
                        local function unstamp(prof, bsX)
                            if touchesHosted then
                                local st = prof and prof[AB.hostedFamKey]
                                if st then
                                    AB.ForEachHostedKey(bsX, function(hkey)
                                        local e = st[hkey]
                                        if not e then
                                            return
                                        end
                                        unstampEntry(e)
                                        -- Mirror the stamp: an entry the un-stamp empties is dropped, so it cannot linger and defeat the resolver's empty-store shortcut.
                                        if next(e) == nil then
                                            st[hkey] = nil
                                        end
                                    end)
                                end
                            end
                            if not (bsX and type(bsX.assignedSpells) == "table") then
                                return
                            end
                            for _, sid2 in ipairs(bsX.assignedSpells) do
                                if AB.IsInjectedMember(bsX, sid2) then
                                    if mod.SlotIDFromKey(sid2) then
                                        -- Equipment slots: the stamp lives on the SLOT entry. Also
                                        -- sweep the equipped item's own entry -- it may carry a legacy per-item stamp from before slot stamping.
                                        local slotE = mod.GetCustomActiveState(sid2)
                                        unstampEntry(slotE)
                                        local itemId = GetInventoryItemID("player", -sid2)
                                        if itemId then
                                            local itemE = mod.GetCustomActiveState(-itemId)
                                            -- Its split reads it over the slot entry, as the icon does.
                                            if itemE and glowKeys then
                                                mod.ChainSettings(itemE, slotE)
                                            end
                                            unstampEntry(itemE)
                                        end
                                    else
                                        unstampEntry(
                                            mod.GetCustomActiveState(mod.ResolveCustomActiveKey(sid2))
                                        )
                                    end
                                end
                            end
                        end
                        local spAll = mod.GetActiveSpecProfiles and mod.GetActiveSpecProfiles()
                        if allSpecs then
                            if spAll then
                                for _, prof in pairs(spAll) do
                                    if type(prof) == "table" then
                                        unstamp(prof, prof.barSpells and prof.barSpells[barId])
                                    end
                                end
                            end
                        else
                            local specKeyA = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
                            local prof = spAll and specKeyA and spAll[specKeyA]
                            if prof then
                                unstamp(prof, prof.barSpells and prof.barSpells[barId])
                            end
                        end
                        if mod.FakeActive_Rearm then
                            mod.FakeActive_Rearm()
                        end
                    end
                    mod.ChainSettings(ss, mod.GetBarTierSettings(sd, barId))
                    if mod.RefreshCDMIconAppearance then
                        mod.RefreshCDMIconAppearance(barId)
                    end
                    if mod.QueueReanchor then
                        mod.QueueReanchor()
                    end
                end

                -- The scope flyout itself: a vertical list (Apply to This Spell / Apply to
                -- Bar / Apply to Bar (All Specs) / conditional Exclude this spec) docked to the right of the hovered flyout item. One shared frame per menu; context swapped on each hover.
                AB.GetApplyStrip = function()
                    if dropMenu._applyStrip then
                        return dropMenu._applyStrip
                    end
                    -- Styled exactly like a subnav flyout: rows with a left-aligned label and the same white hover/selected overlay.
                    local SUBW = 180
                    local s = CreateFrame("Frame", nil, dropMenu)
                    s:SetFrameStrata("FULLSCREEN_DIALOG")
                    s:SetFrameLevel(dropMenu:GetFrameLevel() + 8)
                    s:SetClampedToScreen(true)
                    s:SetWidth(SUBW)
                    s:EnableMouse(true)
                    local backdrop = s:CreateTexture(nil, "BACKGROUND")
                    backdrop:SetAllPoints()
                    backdrop:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
                    CludesUI.MakeRoundedBorder(s, 1, 1, 1, mBrdA, backdrop, nil, true)
                    local sInner = CreateFrame("Frame", nil, s)
                    sInner:SetWidth(SUBW)
                    sInner:SetPoint("TOPLEFT")
                    -- One scope row: _active drives BOTH the accent label colour and the
                    -- persistent white overlay (the "selected" look, same as a subnav item); _rest repaints from it.
                    local function MakeScopeItem(textValue)
                        local b = CreateFrame("Button", nil, sInner)
                        b:SetHeight(ITEM_H)
                        b:SetFrameLevel(s:GetFrameLevel() + 2)
                        local l = b:CreateFontString(nil, "OVERLAY")
                        l:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                        l:SetPoint("LEFT", 10, 0)
                        l:SetJustifyH("LEFT")
                        l:SetText(textValue)
                        l:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        local highlight = b:CreateTexture(nil, "ARTWORK")
                        highlight:SetAllPoints()
                        highlight:SetColorTexture(1, 1, 1, hlA)
                        highlight:SetAlpha(0)
                        b._label = l
                        b._hl = highlight
                        b._active = false
                        b._rest = function()
                            if b._active then
                                local aR, aG, aB = CludesUI.GetAccentColor()
                                l:SetTextColor(aR, aG, aB, 1)
                                highlight:SetAlpha(1)
                            else
                                l:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                highlight:SetAlpha(0)
                            end
                        end
                        b:SetScript("OnEnter", function()
                            l:SetTextColor(1, 1, 1, 1)
                            highlight:SetAlpha(1)
                        end)
                        b:SetScript("OnLeave", function()
                            b._rest()
                        end)
                        b._setText = function(t)
                            l:SetText(t)
                        end
                        return b
                    end
                    local thisBtn = MakeScopeItem(CludesUI.L("Apply to This Spell"))
                    local b1 = MakeScopeItem(CludesUI.L("Apply to Bar"))
                    local b2 = MakeScopeItem(CludesUI.L("Apply to Bar (All Specs)"))
                    local b3 = MakeScopeItem(CludesUI.L("Exclude This Spell"))
                    b3._shown = false
                    -- Exclude/Include This Spell reads apart from the scope rows: soft red
                    -- when it will Exclude, soft green when it will Include, and NO persistent
                    -- white overlay when active (hover overlay only) -- b3._excluded (set in _updateActive) picks the colour.
                    b3._rest = function()
                        if b3._excluded then
                            b3._label:SetTextColor(0.55, 0.82, 0.55, 1) -- Include: soft green
                        else
                            b3._label:SetTextColor(0.90, 0.45, 0.45, 1) -- Exclude: soft red
                        end
                        b3._hl:SetAlpha(0)
                    end
                    b3:SetScript("OnEnter", function()
                        -- Hover overlay same as the other rows (the texture's own
                        -- colour is already hlA, so SetAlpha(1) shows it); only the
                        -- ACTIVE/persistent overlay is suppressed, in _rest.
                        b3._rest()
                        b3._hl:SetAlpha(1)
                    end)
                    b3:SetScript("OnLeave", function()
                        b3._rest()
                    end)
                    -- (Re)stack the visible rows top-to-bottom and size the frame.
                    -- Row 1 is "Apply to This Spell" normally, but a bar apply
                    -- REPLACES it with "Exclude / Include This Spell" (b3._shown) --
                    -- the two are mutually exclusive there. Then Apply to Bar / All
                    -- Specs.
                    local function Relayout()
                        local posY = 4
                        local function place(it)
                            it:ClearAllPoints()
                            it:SetPoint("TOPLEFT", sInner, "TOPLEFT", 1, -posY)
                            it:SetPoint("TOPRIGHT", sInner, "TOPRIGHT", -1, -posY)
                            it:Show()
                            posY = posY + ITEM_H
                        end
                        if b3._shown then
                            place(b3)
                            thisBtn:Hide()
                        else
                            place(thisBtn)
                            b3:Hide()
                        end
                        place(b1)
                        place(b2)
                        local sum = posY + 4
                        sInner:SetHeight(sum)
                        s:SetHeight(sum)
                        -- Widen to the longest scope caption. Relayout runs after
                        -- the Exclude/Include row is re-captioned, so the swapped
                        -- text is measured; all four rows count, so swapping row 1
                        -- never resizes the strip under the cursor.
                        local fitW = FitMenuWidth({ thisBtn._label, b1._label, b2._label, b3._label }, SUBW)
                        s:SetWidth(fitW)
                        sInner:SetWidth(fitW)
                    end
                    -- Accent (and overlay) a scope ONLY when it holds an OWN value
                    -- for these keys that EQUALS the hovered item's value -- so the
                    -- highlight tracks the specific choice under the cursor, not
                    -- merely "this scope has some value applied".
                    s._updateActive = function()
                        local context = s._ctx
                        local keyList = (context and context.keys) or {}
                        -- Simulate the write once: the hovered item's value as it would land in a tier table (false-blocks and all).
                        local temp = {}
                        if context and context.write and context.valueOf then
                            context.write(temp, context.valueOf())
                        end
                        local function holds(tier, raw)
                            if not tier then
                                return false
                            end
                            local anyOwn, match = false, true
                            for _, k in ipairs(keyList) do
                                local own = AB.ScopeVal(tier, k, raw)
                                if own ~= nil then
                                    anyOwn = true
                                end
                                if own ~= temp[k] then
                                    match = false
                                end
                            end
                            return anyOwn and match
                        end
                        -- Excluded = the spell holds its OWN value for these keys. Exactly
                        -- ONE scope is the effective source: this spell when excluded, otherwise
                        -- whichever bar tier drives it -- so the overlay never sits on Apply to Bar while the spell is off on its own (even though the bar still holds it for others).
                        local excluded = AB.SpellHasOwn(keyList)
                        -- "Apply to This Spell" only shows when NO bar apply drives the setting
                        -- (a bar apply REPLACES it with Exclude/Include -- see Relayout), so it
                        -- just lights on the value the spell owns. Toggles light whenever the spell has its own value (on OR off); OR settings match the specific value.
                        if context and context.isToggle then
                            thisBtn._active = excluded
                        else
                            thisBtn._active = holds(ss, true)
                        end
                        b1._active = (not excluded) and holds(sd.barSettings, true)
                        b2._active = (not excluded) and holds(bdSel and bdSel.barSpellSettings, false)
                        thisBtn._rest()
                        b1._rest()
                        b2._rest()
                        -- Exclude/Include This Spell: shown whenever a bar apply drives the
                        -- setting (so this spell+spec can opt out/back in). Label + soft red/green colour flip on the excluded state (b3._excluded drives the colour -- see b3._rest above).
                        if AB.KeysBarApplied(keyList) then
                            b3._excluded = excluded
                            b3._setText(
                                excluded and ("+ " .. CludesUI.L("Include This Spell"))
                                    or ("+ " .. CludesUI.L("Exclude This Spell"))
                            )
                            b3._shown = true
                        else
                            b3._excluded = false
                            b3._shown = false
                        end
                        b3._rest()
                        Relayout()
                    end
                    -- Flash the border of whichever bar scope currently holds a value for
                    -- the hovered keys ("selected apply to bar setting"). Called when a
                    -- subnav click was a no-op because the bar already drives the setting -- the standard white border flash used across the UI, as a "look here" cue.
                    s._flashScopeFor = function()
                        local context = s._ctx
                        local keyList = context and context.keys
                        if not keyList then
                            return
                        end
                        local abs = bdSel and bdSel.barSpellSettings
                        local allActive = false
                        if abs then
                            for _, k in ipairs(keyList) do
                                if AB.ScopeVal(abs, k) ~= nil then
                                    allActive = true
                                    break
                                end
                            end
                        end
                        local target = allActive and b2 or b1
                        if CludesUI.PlayWhiteFlash then
                            CludesUI.PlayWhiteFlash(target)
                        end
                    end
                    local function DoApply(allSpecs)
                        local context = s._ctx
                        if not context then
                            return
                        end
                        local val = context.valueOf and context.valueOf()
                        local keyList = context.keys or {}
                        -- Simulate the write once: drives the rejoin match test, the toggle-off check, and the replace warning below.
                        local temp = {}
                        if context.write then
                            context.write(temp, val)
                        end
                        local scopeT
                        if allSpecs then
                            scopeT = bdSel and bdSel.barSpellSettings
                        else
                            scopeT = sd.barSettings
                        end
                        local scopeActive, valuesMatch = false, true
                        for _, k in ipairs(keyList) do
                            local own
                            if scopeT then
                                own = AB.ScopeVal(scopeT, k, not allSpecs)
                            end
                            if own ~= nil then
                                scopeActive = true
                            end
                            if own ~= temp[k] then
                                valuesMatch = false
                            end
                        end
                        -- On an EXCLUDED spell the flyout sits on the bar's own value, so
                        -- Apply to Bar/All Specs means "rejoin the bar" (same as Include This
                        -- Spell) -- not re-applying the bar's value, which would just toggle it
                        -- off. Items with a payload the flyout val doesn't capture (scalar
                        -- Threshold Seconds; custom colour, where "custom" is fixed and the RGB
                        -- lives in ss; + Border Color's flag + RGBA): rejoin ONLY when the payload matches this scope; otherwise fall through and push it -- rejoining would silently discard it.
                        if
                            AB.KeysBarApplied(keyList)
                            and AB.SpellHasOwn(keyList)
                            and (
                                not (context.scalarApply or context.payloadValue)
                                or (scopeActive and valuesMatch)
                            )
                        then
                            AB.IncludeSpell(keyList)
                            if mod.RefreshCDMIconAppearance then
                                mod.RefreshCDMIconAppearance(barId)
                            end
                            if mod.QueueReanchor then
                                mod.QueueReanchor()
                            end
                            if context.refresh then
                                context.refresh()
                            end
                            if s._updateActive then
                                s._updateActive()
                            end
                            return
                        end
                        -- Toggle OFF: clicking a scope that already holds this exact value
                        -- un-applies it. Binary toggles carry no value, so any active scope is
                        -- an un-apply gesture -- EXCEPT + Border Color, whose RGBA payload makes
                        -- equality meaningful: un-apply only on a colour match, else push the new
                        -- one (un-applying would discard it). Custom-colour value items aren't toggles; isToggle already gates them -- only the rejoin branch above needed the payloadValue guard.
                        if
                            scopeActive and (valuesMatch or (context.isToggle and not context.payloadValue))
                        then
                            -- Payload items (custom colour RGB, scalar seconds): the apply swept
                            -- the per-icon originals, so this scope holds the ONLY copy of the
                            -- value -- a plain un-apply would discard it and snap the setting to
                            -- default. Seed the removed value back into the spell in hand first, so toggle-off is an undo (recreates its pre-apply own value) instead of a silent reset.
                            if (context.scalarApply or context.payloadValue) and ss and scopeT then
                                -- EnsureSS, not ss directly: the apply's member sweep prunes an
                                -- entry it empties from the store (a spell whose ONLY settings were
                                -- the swept keys), leaving this closure's ss orphaned -- a seed into it
                                -- would be lost. EnsureSS re-persists the same table (no-op when it is still in the store).
                                local target = EnsureSS()
                                for _, k in ipairs(keyList) do
                                    local own
                                    if allSpecs then
                                        own = scopeT[k]
                                    else
                                        own = rawget(scopeT, k)
                                    end
                                    if own ~= nil then
                                        rawset(target, k, own)
                                    end
                                end
                            end
                            AB.RunBarUnapply(keyList, allSpecs)
                            if context.refresh then
                                context.refresh()
                            end
                            if s._updateActive then
                                s._updateActive()
                            end
                            return
                        end
                        local function go()
                            AB.RunBarApply(keyList, context.write, val, allSpecs)
                            if context.refresh then
                                context.refresh()
                            end
                            if s._updateActive then
                                s._updateActive()
                            end
                        end
                        -- Confirm before anything destructive or costly: a first-time Resource
                        -- Aware glow (perf note), replacing this scope's active apply with a
                        -- different value (mutually exclusive selections un-check each other), and/or replacing existing per-icon values. One composed popup, never two in a row.
                        local needRA = context.confirmRA and not AB.AnyResourceAwareGlowSaved()
                        local replacing = scopeActive -- (values differ, else un-applied above)
                        local overwrites = AB.CountApplyOverwrites(keyList, context.write, val, allSpecs)
                        if not needRA and not replacing and overwrites == 0 then
                            go()
                            return
                        end
                        local title, message
                        if needRA then
                            title = CludesUI.L("CD Ready Glow (Resource Aware)")
                            message = CludesUI.L(
                                "Resource Aware CD Ready Glow may cause a slight loss in performance efficiency."
                            )
                        else
                            title = CludesUI.L("Overwrite Existing Settings")
                            message = ""
                        end
                        if replacing then
                            local line = allSpecs
                                    and CludesUI.L(
                                        "This setting's active Apply to Bar (All Specs) value will be replaced."
                                    )
                                or CludesUI.L("This setting's active Apply to Bar value will be replaced.")
                            if message ~= "" then
                                message = message .. "\n\n" .. line
                            else
                                message = line
                            end
                        end
                        if overwrites > 0 then
                            -- The English key is itself a valid "%d" format string, so if a locale's
                            -- translation mangles the specifier and string.format errors, fall back to formatting the untranslated key.
                            local key = allSpecs
                                    and "This replaces %d existing value(s) for this setting across your specs."
                                or "This replaces %d existing value(s) for this setting on this bar."
                            local success, line = pcall(string.format, CludesUI.L(key), overwrites)
                            if not success then
                                line = string.format(key, overwrites)
                            end
                            if message ~= "" then
                                message = message .. "\n\n" .. line
                            else
                                message = line
                            end
                        end
                        message = message .. " " .. CludesUI.L("Do you want to continue?")
                        dropMenu:Hide()
                        CludesUI:ShowConfirmPopup({
                            title = title,
                            message = message,
                            confirmText = "Apply",
                            cancelText = "Cancel",
                            onConfirm = go,
                        })
                    end
                    -- One write into the spell's OWN entry: the row's own writer when it has
                    -- one (ctx.writeOwn: the Cooldown State Effect hide keeps the glow the
                    -- spell shows), else the apply write, after a single-value glow on the
                    -- entry moved to cdStateGlow when these keys touch the pair.
                    local function WriteSpellOwn(context, v)
                        if context.writeOwn then
                            context.writeOwn(v)
                            return
                        end
                        EnsureSS()
                        if AB.TouchesCdState(context.keys) then
                            mod.CdStateSplitLegacy(ss)
                        end
                        context.write(ss, v)
                    end
                    -- Apply to This Spell: write the hovered value into the spell's OWN entry
                    -- in THIS spec's store (a per-spell override = excluding this spell+spec from the bar). No dissolve, no popup -- only this one spell changes; the bar apply stays for every other spell.
                    thisBtn:SetScript("OnClick", function()
                        local context = s._ctx
                        if not (context and context.write) then
                            return
                        end
                        WriteSpellOwn(context, context.valueOf and context.valueOf())
                        if mod.RefreshCDMIconAppearance then
                            mod.RefreshCDMIconAppearance(barId)
                        end
                        if mod.QueueReanchor then
                            mod.QueueReanchor()
                        end
                        if context.refresh then
                            context.refresh()
                        end
                        if s:IsShown() and s._updateActive then
                            s._updateActive()
                        end
                    end)
                    b1:SetScript("OnClick", function()
                        DoApply(false)
                    end)
                    b2:SetScript("OnClick", function()
                        DoApply(true)
                    end)
                    -- Exclude / Include This Spell (per spell+spec, via ss).
                    b3:SetScript("OnClick", function()
                        local context = s._ctx
                        if not (context and context.write) then
                            return
                        end
                        local keyList = context.keys or {}
                        if AB.SpellHasOwn(keyList) then
                            -- Include: drop this spell's own value -> rejoin the bar.
                            AB.IncludeSpell(keyList)
                        else
                            -- Exclude: break this spell out with its own value. OR
                            -- settings copy the current value (look unchanged); the
                            -- "+" toggles and choices (ctx.excludeOff) exclude by turning
                            -- OFF for this spell.
                            local v
                            if context.isToggle or context.excludeOff then
                                v = false
                            else
                                v = context.valueOf and context.valueOf()
                            end
                            WriteSpellOwn(context, v)
                        end
                        if mod.RefreshCDMIconAppearance then
                            mod.RefreshCDMIconAppearance(barId)
                        end
                        if mod.QueueReanchor then
                            mod.QueueReanchor()
                        end
                        if context.refresh then
                            context.refresh()
                        end
                        if s._updateActive then
                            s._updateActive()
                        end
                    end)
                    Relayout()
                    s:Hide()
                    dropMenu._applyStrip = s
                    return s
                end
                -- Attach the strip to a hovered flyout item. ctx carries the row/item apply info + a flyout-refresh closure.
                AB.ShowApplyStripFor = function(itemBtn, context)
                    local s = AB.GetApplyStrip()
                    s._ctx = context
                    s._ownerItem = itemBtn
                    if s._updateActive then
                        s._updateActive()
                    end
                    s:ClearAllPoints()
                    -- Same 2px offset as the subnav flyouts, top-aligned to the hovered item.
                    -- Like a subnav, the strip does NOT hide on hover-out (crossing the gap
                    -- would kill it otherwise) -- it hides when its owner item goes away (flyout closed/rebuilt), when another item retargets it, or when the menu closes.
                    s:SetPoint("TOPLEFT", itemBtn, "TOPRIGHT", 2, 0)
                    s:Show()
                end

                -- Divider
                local div1 = inner:CreateTexture(nil, "ARTWORK")
                div1:SetHeight(1)
                div1:SetColorTexture(1, 1, 1, 0.10)
                div1:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
                div1:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
                mH = mH + 9

                local GLOW_ITEMS = GlowStyleItems("Default", 0)
                local ACTIVE_GLOW_ITEMS = GlowStyleItems("None")
                local ACTIVE_SWIPE_ITEMS = {
                    { val = "custom", label = "CD Swipe Color" },
                    { val = "class", label = "CD Swipe Class Colored" },
                    { val = "none", label = "Hide Active State" },
                    -- Independent toggle+swatch (NOT part of the swipe single-select above):
                    -- recolors the icon's border during active state. Its bar-apply writes only the border keys (never the swipe ones).
                    {
                        activeBorder = true,
                        label = "+ Border Color",
                        applyKeys = {
                            "activeBorderEnabled",
                            "activeBorderR",
                            "activeBorderG",
                            "activeBorderB",
                            "activeBorderA",
                        },
                        applyWrite = function(t, v)
                            t.activeBorderEnabled = v and true or false
                            if v then
                                t.activeBorderR = ss.activeBorderR or 1
                                t.activeBorderG = ss.activeBorderG or 0.776
                                t.activeBorderB = ss.activeBorderB or 0.376
                                t.activeBorderA = ss.activeBorderA or 1
                            end
                        end,
                    },
                }

                -----------------------------------------------------------
                --  Cooldown State Effect (spell and preset menus): one hide effect
                --  (the single-select, cdStateEffect) plus at most one glow (the
                --  "+ Glow" choices, cdStateGlow), read through ns.CdStateOf and
                --  written on the menu's own entry through ns.CdStateWriteHide /
                --  ns.CdStateWriteGlow, so each pick keeps the other half.
                -----------------------------------------------------------
                -- The glow a settings table shows, as its menu value. The preset menu
                -- offers no Resource Aware glow (the preset engine reads no
                -- usability): one stamped there by a bar apply shows as the plain CD
                -- Ready glow it renders as.
                AB.MenuGlow = function(source, preset)
                    local g = mod.CdStateGlowOf(source)
                    g = g and mod.CD_STATE_GLOWS[g]
                    if preset and g == "pixelGlowReadyUsable" then
                        return "pixelGlowReady"
                    end
                    return g
                end
                -- itemState for a Cooldown State Effect flyout: greys a glow that can
                -- never show beside the chosen hide and a hide that would leave the
                -- chosen glow nothing to light (ns.CdStateGlowConflicts), each with a
                -- tooltip naming the blocking choice by its menu label
                -- (AB.CD_STATE_LABELS, built from the spell menu's items). The
                -- selected item of either group stays clickable, so a pair inherited
                -- from a bar can still be cleared. procLocked (spell menu): the other
                -- glows also lock while a Proc Glow is set, a reason that wins over a
                -- conflict; the glow shown stays clickable, since clearing it adds
                -- nothing.
                AB.CdStateItemState = function(source, procLocked, preset)
                    return function(si, item)
                        local tipText
                        if item.choiceGet then
                            if AB.MenuGlow(source, preset) ~= item.val then
                                if procLocked and procLocked() then
                                    tipText = "Disable Proc Glow first"
                                else
                                    local hide = mod.CdStateHideOf(source)
                                    if mod.CdStateGlowConflicts(hide, item.val) then
                                        tipText = CludesUI.Lf(
                                            "Disabled while %1$s is enabled.",
                                            CludesUI.L(AB.CD_STATE_LABELS[hide] or hide)
                                        )
                                    end
                                end
                            end
                        elseif item.val ~= nil and mod.CD_STATE_HIDE[item.val] then
                            local glow = AB.MenuGlow(source, preset)
                            if
                                mod.CdStateHideOf(source) ~= item.val
                                and mod.CdStateGlowConflicts(item.val, glow)
                            then
                                tipText = CludesUI.Lf(
                                    "Disabled while %1$s is enabled.",
                                    CludesUI.L(AB.CD_STATE_LABELS[glow] or glow)
                                )
                            end
                        else
                            return
                        end
                        SetFlyoutItemLocked(si, tipText ~= nil, tipText)
                    end
                end
                -- Bar-apply write of the hide (src = the menu's entry): "None" applied
                -- bar-wide is explicitly no hide (false blocks the all-specs tier
                -- below); Lower Alpha pushes src's current percent, read before t
                -- (src itself for the strip's own writes) is written.
                AB.CdHideWrite = function(source)
                    return function(t, v)
                        local pct = source.cdStateLowerAlpha
                        t.cdStateEffect = v or false
                        if v == "lowerAlphaOnCD" then
                            t.cdStateLowerAlpha = pct or 0.5
                        else
                            t.cdStateLowerAlpha = nil
                        end
                    end
                end
                -- Bar-apply write of a glow (src = the menu's entry). Its style
                -- resolves as a direct pick would: src's own Glow Style wins, a
                -- button* single value keeps its Action Button Glow look, else the
                -- glow's default; read before t is written.
                AB.CdGlowWrite = function(source)
                    return function(t, v)
                        local current = mod.CdStateGlowOf(source)
                        t.cdStateGlow = v or false
                        local st
                        if v then
                            if current and mod.CD_STATE_GLOWS[current] ~= current then
                                st = mod.CdReadyGlowStyle(current, source)
                            else
                                st = mod.CdReadyGlowStyle(v, source)
                            end
                        end
                        t.cdStateGlowStyle = st
                        if st == 8 then
                            t.cdStateGlowAlpha = source.cdStateGlowAlpha
                        else
                            t.cdStateGlowAlpha = nil
                        end
                    end
                end
                AB.CD_GLOW_KEYS = { "cdStateGlow", "cdStateGlowStyle", "cdStateGlowAlpha" }
                -- One "+ Glow" choice of a menu m ({ get, set, write, view }): it picks
                -- the glow beside the hide, or clears it when it is the glow shown.
                -- The "+ " look is composed from the glow's own label. Its bar apply
                -- works on the glow keys alone: another glow replaces the applied one,
                -- and Exclude This Spell turns the glow off for the spell.
                AB.CdGlowItem = function(m, val, labelText, tooltip)
                    return {
                        val = val,
                        label = labelText,
                        tooltip = tooltip,
                        dynamicLabel = function()
                            return "+ " .. CludesUI.L(labelText)
                        end,
                        choiceGet = m.get,
                        choiceSet = m.set,
                        applyKeys = AB.CD_GLOW_KEYS,
                        applyWrite = m.write,
                        applyView = m.view,
                    }
                end
                -- The spell menu's glow pick (nil clears it). The Resource Aware glow
                -- runs an event-driven usability watcher shared by every spell that
                -- uses one, so only the first in the spec confirms its small cost (a
                -- spell's own saved value counts, so re-picks never prompt).
                AB.SsGlowSet = function(v)
                    local function commit()
                        mod.CdStateWriteGlow(EnsureSS(), v)
                        if mod.RefreshCDMIconAppearance then
                            mod.RefreshCDMIconAppearance(barId)
                        end
                    end
                    if v == "pixelGlowReadyUsable" and not AB.AnyResourceAwareGlowSaved() then
                        dropMenu:Hide()
                        CludesUI:ShowConfirmPopup({
                            title = "CD Ready Glow (Resource Aware)",
                            message = "Resource Aware CD Ready Glow may cause a slight loss in performance efficiency. Do you want to enable it?",
                            confirmText = "Enable",
                            cancelText = "Cancel",
                            onConfirm = commit,
                        })
                        return
                    end
                    commit()
                end
                local ssGlowMenu = {
                    get = function()
                        return AB.MenuGlow(ss)
                    end,
                    set = AB.SsGlowSet,
                    write = AB.CdGlowWrite(ss),
                    view = function(t)
                        return AB.MenuGlow(t)
                    end,
                }
                local CD_STATE_ITEMS = {
                    { val = nil, label = "None" },
                    -- Charge-spell toggle (independent boolean, NOT part of the single-select
                    -- cdStateEffect below); handled as a toggle in the item loop (item.charge names the ss key). Bar-apply writes an explicit true/false (false blocks the all-specs tier).
                    -- Hides the charge counter text outright (alpha 0 on
                    -- the shared zero-charge-text channel; see
                    -- WatchZeroChargeTextIfEnabled in CdmHooks).
                    -- Per-spell twin of the bar's Suppress GCD toggle
                    -- (ORed at every enforcement site, so the bar toggle
                    -- being ON makes this a natural no-op).
                    {
                        charge = "suppressGCD",
                        label = "+ Suppress GCD",
                        applyKeys = { "suppressGCD" },
                        applyWrite = function(t, v)
                            t.suppressGCD = v and true or false
                        end,
                    },
                    {
                        charge = "hideChargeText",
                        label = "+ Hide Charge Text",
                        applyKeys = { "hideChargeText" },
                        applyWrite = function(t, v)
                            t.hideChargeText = v and true or false
                        end,
                    },
                    {
                        charge = "chargeHideSwipe",
                        label = "+ Hide Swipe (Charges)",
                        applyKeys = { "chargeHideSwipe" },
                        applyWrite = function(t, v)
                            t.chargeHideSwipe = v and true or false
                        end,
                    },
                    {
                        charge = "hideRechargeEdge",
                        label = "+ Hide Recharge Edge",
                        applyKeys = { "hideRechargeEdge" },
                        applyWrite = function(t, v)
                            t.hideRechargeEdge = v and true or false
                        end,
                    },
                    {
                        charge = "chargeHideCdText",
                        label = "+ Hide Duration (Charges > 0)",
                        applyKeys = { "chargeHideCdText" },
                        applyWrite = function(t, v)
                            t.chargeHideCdText = v and true or false
                        end,
                    },
                    -- Charge reading for the two Hidden (CD Ready) modes only: they normally
                    -- treat a charge spell as ready at MAX charges (icon appears on the first
                    -- spent charge and tracks the recharge); this opts the spell into "stay
                    -- hidden while any charge remains" (show only once fully spent). No effect on the other effects (already "no charges left") or non-charge spells.
                    {
                        charge = "chargeHideUntilSpent",
                        label = "+ Stay Hidden While Charges Remain",
                        applyKeys = { "chargeHideUntilSpent" },
                        applyWrite = function(t, v)
                            t.chargeHideUntilSpent = v and true or false
                        end,
                    },
                    -- The glow beside the hide effect: at most one, picked or cleared like
                    -- the "+" toggles above. The style is its own row below
                    -- (cdStateGlowStyle); a button* single value still renders as Action
                    -- Button Glow and reads back as the matching choice here.
                    AB.CdGlowItem(ssGlowMenu, "pixelGlowReady", "Glow (CD Ready)"),
                    -- Resource Aware: also requires the spell to be castable
                    -- (resources/form), through the event-driven usability watcher. That
                    -- watcher has a small cost, so it is its own opt-in choice (with a
                    -- confirm popup) and the plain glows stay cost-free.
                    AB.CdGlowItem(
                        ssGlowMenu,
                        "pixelGlowReadyUsable",
                        "Glow CD Ready (Resource Aware)",
                        "Glow CD Ready (Resource Aware)"
                    ),
                    -- Mirror of the ready glow: glows for the whole cooldown instead of at
                    -- readiness. Shares the Glow Style picker and the Proc Glow priority gate.
                    AB.CdGlowItem(ssGlowMenu, "glowOnCD", "Glow (On CD)"),
                    -- Same logic as Hidden (On CD) but with a customizable opacity instead of
                    -- a hard 0. Click prompts for the percent; the label shows it (e.g. "50%
                    -- Lower Alpha (On CD)") while selected. Its bar apply skips the popup and pushes the current percent.
                    {
                        val = "lowerAlphaOnCD",
                        label = "Lower Alpha (On CD)",
                        dynamicLabel = function()
                            local base = CludesUI.L("Lower Alpha (On CD)")
                            if ss and ss.cdStateEffect == "lowerAlphaOnCD" then
                                local pct = math.floor(((ss.cdStateLowerAlpha or 0.5) * 100) + 0.5)
                                return pct .. "% " .. base
                            end
                            return base
                        end,
                    },
                    -- Shift variants: same hide as the plain modes below, but the bar re-lays out so the remaining icons close the gap.
                    { val = "hiddenOnCDShift", label = "Hidden on CD (Shift Icons)" },
                    { val = "hiddenReadyShift", label = "Hidden CD Ready (Shift Icons)" },
                    {
                        val = "hiddenUnusableShift",
                        label = "Hidden Until Usable (Shift Icons)",
                        tooltip = "Only shown while usable and off cooldown, such as Overpower or Victory Rush after a proc. Low resources do not hide it.",
                    },
                    {
                        val = "hiddenFormShift",
                        label = "Hidden Outside Form/Stance (Shift Icons)",
                        tooltip = "Only shown in the form or stance the spell needs, even while it is on cooldown.",
                    },
                    { val = "hiddenOnCD", label = "Hidden (On CD)" },
                    { val = "hiddenReady", label = "Hidden (CD Ready)" },
                    {
                        val = "hiddenUnusable",
                        label = "Hidden (Until Usable)",
                        tooltip = "Only shown while usable and off cooldown, such as Overpower or Victory Rush after a proc. Low resources do not hide it.",
                    },
                    {
                        val = "hiddenForm",
                        label = "Hidden (Outside Form/Stance)",
                        tooltip = "Only shown in the form or stance the spell needs, even while it is on cooldown.",
                    },
                }
                -- The English label of every hide and glow value, for the lock
                -- tooltips that name the choice blocking an item (both menus: the
                -- preset menu's values are a subset of these).
                AB.CD_STATE_LABELS = {}
                for _, it in ipairs(CD_STATE_ITEMS) do
                    if it.val ~= nil then
                        AB.CD_STATE_LABELS[it.val] = it.label
                    end
                end
                -- Glow style picker (CDM saved numbering, every icon style), shared by
                -- both the CD Ready and On CD glow effects.
                local CD_READY_STYLE_ITEMS = {}
                for _, idx in ipairs(mod.GLOW_VIEW.ordered) do
                    local record = mod.GLOW_STYLES[idx]
                    CD_READY_STYLE_ITEMS[#CD_READY_STYLE_ITEMS + 1] = { val = idx, label = record.name }
                end
                -- Reverse Swipe single-select (per-spell / per-preset), shared by both the regular-spell (ss) and preset/custom (cas) menus below.
                local REVERSE_SWIPE_ITEMS = {
                    { val = nil, label = "Off" },
                    { val = true, label = "Reverse Swipe" },
                }
                -- Glow When Visible (per-spell, buff icons): the icon glows whenever it is
                -- shown, so a Show When Missing buff lights up the moment it drops.
                local GLOW_VISIBLE_ITEMS = {
                    { val = nil, label = "Off" },
                    { val = true, label = "On" },
                }
                local function SetGlowWhenVisible(v)
                    EnsureSS()
                    SetOwn("glowWhenVisible", v or nil)
                    if mod.RefreshCDMIconAppearance then
                        mod.RefreshCDMIconAppearance(barId)
                    end
                end
                local GLOW_VISIBLE_APPLY = {
                    apply = {
                        keys = { "glowWhenVisible" },
                        write = function(t, v)
                            t.glowWhenVisible = v or false
                        end,
                    },
                }
                -- Cooldown Swipe (cd/utility spells + presets): a 3-way single-select over
                -- two independent keys (reverseSwipe, hideCDSwipe). "Off" clears both; getVal/setVal below map the selection to the keys.
                local CD_SWIPE_ITEMS = {
                    { val = nil, label = "Off" },
                    { val = "reverse", label = "Reverse Swipe" },
                    { val = "hide", label = "Hide CD Swipe" },
                }
                -- Stance Bar single-select, shared by the regular-spell (ss) and
                -- preset/custom (cas) menus: hidden in / outside each of the class's
                -- stance bar pages (CludesUI.CLASS_PAGING_STATES), stored as
                -- "<mode>:<state id>". nil for a class with no stance bar.
                local stanceStates = CludesUI.CLASS_PAGING_STATES[select(2, UnitClass("player"))]
                if stanceStates then
                    local STANCE_LABELS = {
                        inShift = {
                            "Hidden in %s (Shift Icons)",
                            function(s)
                                return CludesUI.Lf("Hidden in %1$s (Shift Icons)", s)
                            end,
                        },
                        outShift = {
                            "Hidden outside %s (Shift Icons)",
                            function(s)
                                return CludesUI.Lf("Hidden outside %1$s (Shift Icons)", s)
                            end,
                        },
                        ["in"] = {
                            "Hidden in %s",
                            function(s)
                                return CludesUI.Lf("Hidden in %1$s", s)
                            end,
                        },
                        out = {
                            "Hidden outside %s",
                            function(s)
                                return CludesUI.Lf("Hidden outside %1$s", s)
                            end,
                        },
                    }
                    local itemList = { { val = nil, label = "None" } }
                    local function AddStanceItem(mode, st)
                        local fmt = STANCE_LABELS[mode]
                        itemList[#itemList + 1] = {
                            val = mode .. ":" .. st.id,
                            label = fmt[1]:format(st.label),
                            dynamicLabel = function()
                                return fmt[2](CludesUI.L(st.label))
                            end,
                        }
                    end
                    -- Shift Icons variants first, like the Cooldown State Effect list.
                    for _, st in ipairs(stanceStates) do
                        AddStanceItem("inShift", st)
                        AddStanceItem("outShift", st)
                    end
                    for _, st in ipairs(stanceStates) do
                        AddStanceItem("in", st)
                        AddStanceItem("out", st)
                    end
                    AB.STANCE_BAR_ITEMS = itemList
                end

                -- Track open subnavs on the menu frame so OnUpdate can see them

                -- Hosted buffs are fully removed from the Apply-to-Bar system: this flag (set
                -- per-icon below, once isHostedBuff is known) suppresses the "Apply to Bar" hover strip on every row for a hosted buff.
                local hostedBuffNoApply = false

                -- Helper: subnav flyout (same style as Potions & Healthstone)
                -- isDefault: function returning true when the setting is at default value
                -- onItemCreated: optional callback(si, item, sub) for custom widgets per subnav item;
                --   runs once, when the flyout is first built (a swatch built there stores its
                --   refresh as si._refreshSwatch so every later open repaints it)
                -- opts.itemState: optional callback(si, item, sub) for an item look that depends on
                --   another setting; runs at build, on every later open and after every pick
                -- opts.apply: { keys, write(t, v) } for the Apply to Bar strip, plus optional
                --   view(t) (the value a bar tier applies, in item.val form) and writeOwn(v)
                --   (the strip's write into the spell's own entry); an item may carry its own
                --   applyKeys / applyWrite / applyView / applyWriteOwn instead
                -- item.choiceGet() / item.choiceSet(v): a pick-one group beside the row's value
                --   (see the item loop)
                local function MakeSubnavRow(
                    labelText,
                    itemList,
                    getVal,
                    setVal,
                    isDefault,
                    onItemCreated,
                    options
                )
                    local row, labelFS = AB.NewMenuRow(labelText)
                    local acR, acG, acB = CludesUI.GetAccentColor()

                    -- Optional disabled state (opts.disabled = function -> bool): greys the row, blocks the flyout, and shows a tooltip.
                    local function RowDisabled()
                        return options and options.disabled and options.disabled() or false
                    end

                    local function UpdateLabelColor()
                        if RowDisabled() then
                            labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                        elseif not isDefault() then
                            labelFS:SetTextColor(acR, acG, acB, 1)
                        else
                            labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        end
                        -- opts.onRefresh: runs whenever the row repaints (build, every pick, a bar apply, hover-out)
                        if options and options.onRefresh then
                            options.onRefresh()
                        end
                    end
                    UpdateLabelColor()
                    -- The apply strip, when open, re-reads which scope holds the value.
                    local function PokeStrip()
                        local strip = dropMenu._applyStrip
                        if strip and strip:IsShown() and strip._updateActive then
                            strip._updateActive()
                        end
                    end
                    -- After a pick: the row's own cue, the icons when the value
                    -- reaches them, then the strip.
                    local function Repaint(icons)
                        UpdateLabelColor()
                        if icons then
                            if mod.RefreshCDMIconAppearance then
                                mod.RefreshCDMIconAppearance(barId)
                            end
                            if mod.QueueReanchor then
                                mod.QueueReanchor()
                            end
                        end
                        PokeStrip()
                    end

                    local arrow = row:CreateTexture(nil, "ARTWORK")
                    arrow:SetSize(10, 10)
                    arrow:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                    arrow:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\right-arrow.png")
                    arrow:SetAlpha(RowDisabled() and 0.2 or 0.7)

                    local highlight = row:CreateTexture(nil, "ARTWORK")
                    highlight:SetAllPoints()
                    highlight:SetColorTexture(1, 1, 1, 0)
                    highlight:SetAlpha(0)

                    local sub
                    -- Set by the first build: re-applies what a fresh open shows.
                    local reshowSub
                    local function ShowSub()
                        if dropMenu._openSub and dropMenu._openSub ~= sub and dropMenu._openSub.Hide then
                            dropMenu._openSub:Hide()
                        end
                        if sub and sub:IsShown() then
                            return
                        end
                        -- Built once per row; a later hover refreshes the same flyout in place.
                        if sub then
                            if reshowSub then
                                reshowSub()
                            end
                            sub:Show()
                            dropMenu._openSub = sub
                            return
                        end
                        sub = CreateFrame("Frame", nil, dropMenu)
                        sub:SetFrameStrata("FULLSCREEN_DIALOG")
                        sub:SetFrameLevel(dropMenu:GetFrameLevel() + 5)
                        sub:SetClampedToScreen(true)
                        sub:EnableMouse(true)

                        local SUB_BASE_W = 180
                        local subW = SUB_BASE_W
                        sub:SetSize(subW, 10)
                        sub:ClearAllPoints()
                        sub:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 0)

                        local subBg = sub:CreateTexture(nil, "BACKGROUND")
                        subBg:SetAllPoints()
                        subBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
                        CludesUI.MakeRoundedBorder(sub, 1, 1, 1, mBrdA, subBg, nil, true)

                        local subInner = CreateFrame("Frame", nil, sub)
                        subInner:SetWidth(subW)
                        subInner:SetPoint("TOPLEFT")

                        local subH = 4
                        local flyoutEntries = {}
                        -- opts.itemState(si, item, sub): an item look that depends on
                        -- another setting (a lock), applied at build and on every open.
                        local itemState = options and options.itemState
                        -- Widens the flyout to its longest caption. Runs once the items
                        -- exist (the sizing below reads subW) and again after a caption
                        -- is recomposed in place, since a dynamic label can grow while
                        -- the flyout is open ("Lower Alpha (On CD)" gaining "50% ").
                        local function RefitSub()
                            local labels = {}
                            for _, e in ipairs(flyoutEntries) do
                                labels[#labels + 1] = e.label
                            end
                            local fitW = FitMenuWidth(labels, subW)
                            if fitW ~= subW then
                                subW = fitW
                                sub:SetWidth(subW)
                                subInner:SetWidth(subW)
                            end
                        end
                        -- After a pick or a bar apply the flyout stays open and repaints
                        -- in place (a rebuild would lose the scroll, the search and the
                        -- apply strip's owner): each item's live selection (a bar apply
                        -- included), its caption, its arrow and its lock, then the width.
                        local function RefreshFlyoutSelection()
                            for _, e in ipairs(flyoutEntries) do
                                if not e.isDivider then
                                    e.setSelected(e.computeSelected())
                                    e.refreshLabel()
                                    e.updateArrow()
                                    if itemState then
                                        itemState(e.frame, e.item, sub)
                                    end
                                end
                            end
                            RefitSub()
                        end
                        -- onItemCreated swatches live outside this scope and reach it through sub.
                        sub._refreshSelection = RefreshFlyoutSelection
                        for _, item in ipairs(itemList) do
                            if item.divider then
                                -- A thin separator (built-in sounds above, LibSharedMedia
                                -- ones below); never selectable.
                                local div = subInner:CreateTexture(nil, "ARTWORK")
                                div:SetHeight(1)
                                div:SetColorTexture(1, 1, 1, 0.10)
                                div:SetPoint("TOPLEFT", subInner, "TOPLEFT", 6, -subH - 4)
                                div:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -6, -subH - 4)
                                flyoutEntries[#flyoutEntries + 1] = { frame = div, isDivider = true }
                                subH = subH + 9
                            else
                                local si = CreateFrame("Button", nil, subInner)
                                si:SetHeight(ITEM_H)
                                si:SetPoint("TOPLEFT", subInner, "TOPLEFT", 1, -subH)
                                si:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -1, -subH)
                                si:SetFrameLevel(sub:GetFrameLevel() + 2)

                                local sLbl = si:CreateFontString(nil, "OVERLAY")
                                sLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                                sLbl:SetPoint("LEFT", 10, 0)
                                sLbl:SetJustifyH("LEFT")
                                -- item.dynamicLabel returns a caption composed (and
                                -- localized) at render time, "50% Lower Alpha (On CD)".
                                local function Recaption()
                                    if item.dynamicLabel then
                                        sLbl:SetText(item.dynamicLabel())
                                    end
                                end
                                if item.dynamicLabel then
                                    Recaption()
                                else
                                    sLbl:SetText(CludesUI.L(item.label))
                                end

                                -- What the item is. A toggle flips one boolean of its own:
                                -- ssKey names it in the spell's settings (item.charge, or
                                -- Border Color's activeBorderEnabled), item.toggleGet /
                                -- toggleSet reach any store (so one item list serves the
                                -- spell, buff and customActiveStates rows). A choice
                                -- (item.choiceGet / choiceSet) is a pick-one group of its
                                -- own beside the row's value. Anything else is one value
                                -- of the row (item.val).
                                local ssKey = item.charge
                                    or (item.activeBorder == true and "activeBorderEnabled")
                                    or nil
                                local isFnToggle = item.toggleGet ~= nil
                                local isChoice = item.choiceGet ~= nil
                                local isToggle = ssKey ~= nil or isFnToggle
                                -- Toggles and choices show "on" as accent text only; a
                                -- chosen value also keeps the white overlay lit.
                                local plusLook = isToggle or isChoice
                                -- The live selection, from effective (chained) values, so
                                -- a bar tier's apply shows as well as the spell's own.
                                local function SelectedNow()
                                    if ssKey then
                                        return ss[ssKey] == true
                                    elseif isFnToggle then
                                        return item.toggleGet() and true or false
                                    elseif isChoice then
                                        return item.choiceGet() == item.val
                                    end
                                    -- None/default is stored as a blocking false.
                                    local cv = getVal()
                                    if cv == false then
                                        cv = nil
                                    end
                                    return cv == item.val
                                end

                                local sHl = si:CreateTexture(nil, "ARTWORK")
                                sHl:SetAllPoints()
                                sHl:SetColorTexture(1, 1, 1, hlA)
                                sHl:SetAlpha(0)
                                local isSelected
                                -- The unhovered look of a selection state.
                                local function ShowState(sel)
                                    isSelected = sel
                                    if sel then
                                        local r, g, b = CludesUI.GetAccentColor()
                                        sLbl:SetTextColor(r, g, b, 1)
                                    else
                                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                    end
                                    if not plusLook then
                                        sHl:SetAlpha(sel and 1 or 0)
                                    end
                                end
                                ShowState(SelectedNow())

                                -- Apply to Bar: every value and toggle offers it (only the
                                -- action rows, which have no flyout, do not). The keys and
                                -- write come from the item or else the row; view(t) reads
                                -- the value a bar tier applies in item.val form, writeOwn(v)
                                -- is the strip's write into the spell's own entry. An item
                                -- with keys of its own never borrows the row's views.
                                local rowApply = options and options.apply
                                local applyKeys = item.applyKeys or (rowApply and rowApply.keys)
                                local applyWrite = item.applyWrite or (rowApply and rowApply.write)
                                local borrow = item.applyKeys == nil and rowApply
                                local applyView = item.applyView or (borrow and rowApply.view) or nil
                                local applyWriteOwn = item.applyWriteOwn
                                    or (borrow and rowApply.writeOwn)
                                    or nil
                                -- A hosted buff never takes part in Apply to Bar.
                                local canApply = applyWrite ~= nil and not hostedBuffNoApply
                                -- True when a bar apply drives this setting with THIS item's
                                -- value (a bar-applied toggle counts): that item then carries
                                -- an arrow and is managed through the strip, not clicked.
                                local function itemIsBarApplied()
                                    -- A hosted buff never chains to the bar tiers, and it has
                                    -- no strip to escape through, so it is never bar applied
                                    -- (else its toggles would lock).
                                    if
                                        hostedBuffNoApply or not (applyKeys and AB.KeysBarApplied(applyKeys))
                                    then
                                        return false
                                    end
                                    if isToggle then
                                        return true
                                    end
                                    local barTier = mod.GetBarTierSettings
                                        and mod.GetBarTierSettings(sd, barId)
                                    if not barTier then
                                        return false
                                    end
                                    if applyView then
                                        return applyView(barTier) == item.val
                                    end
                                    local pk = applyKeys[1]
                                    if not pk then
                                        return false
                                    end
                                    local probe = {}
                                    applyWrite(probe, item.val)
                                    return AB.ScopeVal(barTier, pk) == probe[pk]
                                end
                                local sArrow = si:CreateTexture(nil, "ARTWORK")
                                sArrow:SetSize(10, 10)
                                sArrow:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                sArrow:SetTexture(
                                    "Interface\\AddOns\\CludesUI\\media\\icons\\right-arrow.png"
                                )
                                sArrow:SetAlpha(0.7)
                                local function updateArrow()
                                    sArrow:SetShown(canApply and itemIsBarApplied())
                                end
                                updateArrow()
                                si:SetScript("OnEnter", function()
                                    if not isSelected then
                                        sLbl:SetTextColor(1, 1, 1, 1)
                                    end
                                    sHl:SetAlpha(1)
                                    -- item.tooltip: the full text of a caption the flyout clips.
                                    if item.tooltip then
                                        CludesUI.ShowWidgetTooltip(si, item.tooltip)
                                    end
                                    if not canApply then
                                        return
                                    end
                                    -- While a bar apply drives a value setting, only the item
                                    -- holding the bar's value keeps the strip (the arrow row);
                                    -- the others are plain values, whatever the spell itself
                                    -- holds. Toggles always keep theirs, and so does a scalar
                                    -- popup value (Threshold Seconds is a single item: a number
                                    -- unlike the bar's must not hide Apply to Bar).
                                    if
                                        not (item.scalarApply or isToggle)
                                        and AB.KeysBarApplied(applyKeys)
                                        and not itemIsBarApplied()
                                    then
                                        if dropMenu._applyStrip then
                                            dropMenu._applyStrip:Hide()
                                        end
                                        return
                                    end
                                    AB.ShowApplyStripFor(si, {
                                        keys = applyKeys,
                                        write = applyWrite,
                                        writeOwn = applyWriteOwn,
                                        scalarApply = item.scalarApply,
                                        isToggle = isToggle,
                                        -- A choice applies its value like a value item, but
                                        -- Exclude This Spell turns its group off (false).
                                        excludeOff = isChoice,
                                        -- The item's val alone does not say what it holds when
                                        -- its keys carry a colour (an R/G/B triple), the row
                                        -- flags another payload (apply.payload: the Blackout
                                        -- opacity) or it is a scalar (Threshold Seconds, Also
                                        -- Show Below): equality is then judged on the values,
                                        -- so the rejoin and toggle-off shortcuts keep them.
                                        payloadValue = HasColourTriple(applyKeys)
                                            or (rowApply and rowApply.payload and rowApply.payload(item))
                                            or item.scalarApply
                                            or false,
                                        -- A toggle's apply turns the feature ON (pressing it again
                                        -- where it is held un-applies); never read the selection
                                        -- here, or changing scope would flip an on toggle off.
                                        valueOf = function()
                                            if isToggle then
                                                return true
                                            end
                                            return item.val
                                        end,
                                        confirmRA = rowApply
                                            and rowApply.confirmRA
                                            and (
                                                item.val == "pixelGlowReadyUsable"
                                                or item.val == "buttonGlowReadyUsable"
                                            ),
                                        -- Repaint in place, never rebuild: a rebuild would take
                                        -- the strip's owner item away mid-use.
                                        refresh = function()
                                            RefreshFlyoutSelection()
                                            UpdateLabelColor()
                                        end,
                                    })
                                end)
                                si:SetScript("OnLeave", function()
                                    if not isSelected then
                                        sLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                    end
                                    sHl:SetAlpha((not plusLook and isSelected) and 1 or 0)
                                    if item.tooltip then
                                        CludesUI.HideWidgetTooltip()
                                    end
                                end)
                                -- A pick writes into the spell's OWN entry and keeps both the
                                -- menu and the flyout open.
                                local function doWrite()
                                    -- A choice picks itself, or clears the group when it is
                                    -- the one shown; its setter persists and refreshes.
                                    if isChoice then
                                        if item.choiceGet() ~= item.val then
                                            item.choiceSet(item.val)
                                        else
                                            item.choiceSet(nil)
                                        end
                                        RefreshFlyoutSelection()
                                        Repaint(false)
                                        return
                                    end
                                    -- A store toggle: its setter persists, arms and refreshes.
                                    if isFnToggle and item.toggleSet then
                                        item.toggleSet(not item.toggleGet())
                                        ShowState(item.toggleGet() and true or false)
                                        Repaint(false)
                                        return
                                    end
                                    -- A settings toggle (charge styles, Border Color). It never
                                    -- touches the row's own value.
                                    if ssKey then
                                        EnsureSS()
                                        if ss[ssKey] == true then
                                            SetOwn(ssKey, nil)
                                        else
                                            ss[ssKey] = true
                                        end
                                        local on = ss[ssKey] == true
                                        if on and item.charge then
                                            ArmChargeGate(mod, item.charge)
                                        elseif on and not ss.activeBorderR then
                                            -- Border Color starts from the accent gold; the
                                            -- inline swatch picks another.
                                            ss.activeBorderR = 1
                                            ss.activeBorderG = 0.776
                                            ss.activeBorderB = 0.376
                                            ss.activeBorderA = 1
                                        end
                                        ShowState(on)
                                        Repaint(true)
                                        return
                                    end
                                    setVal(item.val)
                                    RefreshFlyoutSelection()
                                    Repaint(true)
                                end
                                si:SetScript("OnClick", function()
                                    -- The bar's own value is the arrow row: it is managed
                                    -- through the strip (Exclude / Include / Apply to Bar).
                                    if itemIsBarApplied() then
                                        return
                                    end
                                    -- While the bar drives this setting and the spell holds
                                    -- nothing of its own, picking the value the bar already
                                    -- applies changes nothing, so the strip flashes the scope
                                    -- that holds it. Anything else (another value, a toggle,
                                    -- a choice) breaks this spell out with a value of its own
                                    -- and leaves the bar apply for the rest. Rows without a
                                    -- strip (hosted buffs) just write.
                                    if
                                        canApply
                                        and not plusLook
                                        and AB.KeysBarApplied(applyKeys)
                                        and not AB.SpellHasOwn(applyKeys)
                                    then
                                        local cv = getVal()
                                        if cv == item.val then
                                            local strip = dropMenu._applyStrip
                                            if strip and strip._flashScopeFor then
                                                strip._flashScopeFor()
                                            end
                                            return
                                        end
                                    end
                                    doWrite()
                                end)

                                if onItemCreated then
                                    onItemCreated(si, item, sub)
                                    -- The hook may attach a dynamic caption (the Blackout percent).
                                    Recaption()
                                end
                                if itemState then
                                    itemState(si, item, sub)
                                end
                                flyoutEntries[#flyoutEntries + 1] = {
                                    frame = si,
                                    label = sLbl,
                                    name = item.label,
                                    item = item,
                                    computeSelected = SelectedNow,
                                    setSelected = ShowState,
                                    -- A fresh open: no hover overlay left on a "+" item.
                                    resetShown = function(sel)
                                        sHl:SetAlpha(0)
                                        ShowState(sel)
                                    end,
                                    refreshLabel = Recaption,
                                    updateArrow = updateArrow,
                                }
                                subH = subH + ITEM_H
                            end
                        end

                        RefitSub()

                        -- A long list (the Audio Effect sounds) caps at the dropdowns'
                        -- 200px and scrolls smoothly under the wheel; a short one sizes
                        -- to fit. Returns the scroll's jump-to function.
                        local totalSubH = subH + 4
                        subInner:SetHeight(totalSubH)
                        local FLYOUT_MAX_H = 200
                        local function ScrollFrom(top)
                            subInner:ClearAllPoints()
                            local scrollFrame = CreateFrame("ScrollFrame", nil, sub)
                            scrollFrame:SetPoint("TOPLEFT", 0, -top)
                            scrollFrame:SetPoint("BOTTOMRIGHT", 0, 1)
                            scrollFrame:SetFrameLevel(sub:GetFrameLevel() + 1)
                            scrollFrame:EnableMouseWheel(true)
                            scrollFrame:SetScrollChild(subInner)
                            subInner:SetWidth(subW)
                            local _, jump =
                                CludesUI.AttachSmoothScrollbar(scrollFrame, { step = 40, thumb = false })
                            return jump
                        end
                        -- Kept for reshowSub: the search box and its filter, or the scroll's jump.
                        local searchEdit, filterList, scrollTop
                        if options and options.searchable then
                            -- A filter box on top, the list scrolling under it. Rows are all
                            -- ITEM_H tall, so a query just restacks the matches (separators
                            -- show only for the full list).
                            local SEARCH_H = 24
                            local searchPad = SEARCH_H + 8
                            sub:SetSize(subW, FLYOUT_MAX_H + searchPad)

                            searchEdit = CreateFrame("EditBox", nil, sub)
                            searchEdit:SetSize(subW - 12, SEARCH_H)
                            searchEdit:SetPoint("TOP", sub, "TOP", 0, -4)
                            searchEdit:SetFrameLevel(sub:GetFrameLevel() + 6)
                            searchEdit:SetFont(FONT_PATH, 11, "")
                            searchEdit:SetTextColor(1, 1, 1, 0.9)
                            searchEdit:SetJustifyH("LEFT")
                            searchEdit:SetAutoFocus(false)
                            searchEdit:SetMaxLetters(30)
                            searchEdit:SetTextInsets(4, 4, 0, 0)
                            local seBg = searchEdit:CreateTexture(nil, "BACKGROUND")
                            seBg:SetAllPoints()
                            seBg:SetColorTexture(0, 0, 0, 0.4)
                            CludesUI.RoundBody(searchEdit, seBg)
                            local sePh = searchEdit:CreateFontString(nil, "OVERLAY")
                            sePh:SetFont(FONT_PATH, 11, "")
                            sePh:SetTextColor(0.5, 0.5, 0.5, 0.6)
                            sePh:SetPoint("LEFT", searchEdit, "LEFT", 4, 0)
                            sePh:SetText(CludesUI.L("Search..."))
                            local function Unfocus(self)
                                self:ClearFocus()
                            end
                            searchEdit:SetScript("OnEscapePressed", Unfocus)
                            searchEdit:SetScript("OnHide", Unfocus)

                            local scrollTo = ScrollFrom(searchPad)
                            filterList = function(raw)
                                local q = strlower(strtrim(raw or ""))
                                sePh:SetShown(q == "")
                                local yy = 4
                                for _, e in ipairs(flyoutEntries) do
                                    local shown
                                    if e.isDivider then
                                        shown = q == ""
                                    else
                                        local nm = e.name or (e.label and e.label:GetText()) or ""
                                        shown = q == "" or strfind(strlower(tostring(nm)), q, 1, true) ~= nil
                                    end
                                    e.frame:SetShown(shown)
                                    if shown then
                                        -- A separator sits 4px into its 9px slot, inset 6.
                                        local inset, dy = 1, 0
                                        if e.isDivider then
                                            inset, dy = 6, 4
                                        end
                                        e.frame:ClearAllPoints()
                                        e.frame:SetPoint("TOPLEFT", subInner, "TOPLEFT", inset, -yy - dy)
                                        e.frame:SetPoint("TOPRIGHT", subInner, "TOPRIGHT", -inset, -yy - dy)
                                        yy = yy + (e.isDivider and 9 or ITEM_H)
                                    end
                                end
                                subInner:SetHeight(math.max(1, yy + 4))
                                scrollTo(0)
                            end
                            searchEdit:SetScript("OnTextChanged", function(self)
                                filterList(self:GetText())
                            end)
                            filterList("")
                        elseif totalSubH > FLYOUT_MAX_H then
                            sub:SetSize(subW, FLYOUT_MAX_H)
                            scrollTop = ScrollFrom(1)
                        else
                            sub:SetSize(subW, totalSubH)
                        end

                        -- A later open re-derives everything a fresh build would show:
                        -- each item's selection, caption, arrow, lock and swatch colour,
                        -- the width from the base, an empty search and the top of the list.
                        reshowSub = function()
                            for _, e in ipairs(flyoutEntries) do
                                if e.resetShown then
                                    e.resetShown(e.computeSelected())
                                    e.refreshLabel()
                                    e.updateArrow()
                                    if itemState then
                                        itemState(e.frame, e.item, sub)
                                    end
                                    if e.frame._refreshSwatch then
                                        e.frame._refreshSwatch()
                                    end
                                end
                            end
                            subW = SUB_BASE_W
                            sub:SetWidth(subW)
                            subInner:SetWidth(subW)
                            RefitSub()
                            if searchEdit then
                                searchEdit:SetWidth(subW - 12)
                                searchEdit:SetText("")
                                filterList("")
                            elseif scrollTop then
                                scrollTop(0)
                            end
                        end
                        sub:Show()
                        dropMenu._openSub = sub
                    end

                    -- Opens this row's flyout from code (a rebuilt menu reopens the one it had open).
                    row._showSub = ShowSub
                    row:SetScript("OnEnter", function()
                        if RowDisabled() then
                            if options.disabledTooltip then
                                CludesUI.ShowWidgetTooltip(row, options.disabledTooltip)
                            end
                            return
                        end
                        labelFS:SetTextColor(1, 1, 1, 1)
                        highlight:SetColorTexture(1, 1, 1, hlA)
                        highlight:SetAlpha(1)
                        ShowSub()
                    end)
                    row:SetScript("OnLeave", function()
                        if options and options.disabledTooltip then
                            CludesUI.HideWidgetTooltip()
                        end
                        UpdateLabelColor()
                        highlight:SetAlpha(0)
                        -- Don't auto-close sub here. It closes when:
                        -- 1. A different subnav row is hovered (ShowSub closes _openSub)
                        -- 2. The parent menu closes (OnHide propagates)
                        -- 3. An option is clicked (OnClick hides sub)
                    end)

                    mH = mH + ITEM_H
                    return row, sub
                end

                -- "Threshold Text" per-spell subnav, shared by the buff, cd/util
                -- and preset/custom branches. Threshold Seconds arms the feature for the
                -- spell (0 = off = zero cost); Threshold Color and Threshold Decimals are
                -- independent toggles applied below that boundary (rendered by the engine
                -- countdown formatter -- ns.ApplyThresholdFormatter). acc bridges the
                -- branch's store (per-spell family entry or customActiveStates):
                --   get(key) effective read; set(key,v) own write (persists entry first);
                --   clear(key) own clear (tier-blocking where applicable); refresh() post-change gate flip + apply calls.
                local function AddThresholdTextRow(acc)
                    local function armedSeconds()
                        return tonumber(acc.get("thresholdSeconds")) or 0
                    end
                    local TT_ITEMS = {
                        {
                            val = "seconds",
                            label = "Threshold Seconds",
                            -- Scalar popup value (not a discrete flyout choice): the number lives
                            -- in the store, entered via a popup, and applyWrite pushes the spell's
                            -- current seconds live. The Apply-to-Bar strip must treat it as "always
                            -- push my value", never a discrete value item -- otherwise the rejoin shortcut discards the entered number and the suppress-strip rule hides the strip whenever the bar's number differs (see scalarApply guards below).
                            scalarApply = true,
                            dynamicLabel = function()
                                local base = CludesUI.L("Threshold Seconds")
                                local s = armedSeconds()
                                if s > 0 then
                                    return base .. " (" .. s .. "s)"
                                end
                                return base
                            end,
                            tooltip = "Seconds remaining below which Threshold Color and Threshold Decimals apply (0 = off).",
                            toggleGet = function()
                                return armedSeconds() > 0
                            end,
                            applyKeys = { "thresholdSeconds" },
                            applyWrite = function(t, v)
                                -- Push this spell's current seconds; "off" (0, or Exclude This
                                -- Spell's false) blocks the tier below.
                                local s = (v ~= false) and armedSeconds() or 0
                                t.thresholdSeconds = (s > 0) and s or false
                            end,
                        },
                        {
                            val = "color",
                            label = "Threshold Color",
                            tooltip = "Recolor the countdown text below Threshold Seconds.",
                            toggleGet = function()
                                return acc.get("thresholdColorEnabled") == true
                            end,
                            toggleSet = function(v)
                                if v then
                                    acc.set("thresholdColorEnabled", true)
                                    if not acc.get("thresholdColorR") then
                                        acc.set("thresholdColorR", 1)
                                        acc.set("thresholdColorG", 0.2)
                                        acc.set("thresholdColorB", 0.2)
                                    end
                                else
                                    acc.clear("thresholdColorEnabled")
                                end
                                acc.refresh()
                            end,
                            applyKeys = {
                                "thresholdColorEnabled",
                                "thresholdColorR",
                                "thresholdColorG",
                                "thresholdColorB",
                            },
                            applyWrite = function(t, v)
                                t.thresholdColorEnabled = v or false
                                if v then
                                    -- Push this spell's current color.
                                    t.thresholdColorR = acc.get("thresholdColorR") or 1
                                    t.thresholdColorG = acc.get("thresholdColorG") or 0.2
                                    t.thresholdColorB = acc.get("thresholdColorB") or 0.2
                                else
                                    -- Colour keys belong to the enabled state only; clear them so a stale colour can't linger in the tier and make valuesMatch always fail.
                                    t.thresholdColorR = nil
                                    t.thresholdColorG = nil
                                    t.thresholdColorB = nil
                                end
                            end,
                        },
                        {
                            val = "decimals",
                            label = "Threshold Decimals",
                            tooltip = "Show a 1-decimal countdown (2.7) below Threshold Seconds.",
                            toggleGet = function()
                                return acc.get("thresholdDecimals") == true
                            end,
                            toggleSet = function(v)
                                if v then
                                    acc.set("thresholdDecimals", true)
                                else
                                    acc.clear("thresholdDecimals")
                                end
                                acc.refresh()
                            end,
                            applyKeys = { "thresholdDecimals" },
                            applyWrite = function(t, v)
                                t.thresholdDecimals = v or false
                            end,
                        },
                    }
                    return MakeSubnavRow("Threshold Text", TT_ITEMS, function()
                        return nil
                    end, function() end, function()
                        return armedSeconds() == 0
                            and acc.get("thresholdColorEnabled") ~= true
                            and acc.get("thresholdDecimals") ~= true
                    end, function(si, item, sub)
                        if item.val == "seconds" then
                            -- Popup flow (mirrors Lower Alpha): close the menu so only the popup shows; 0 disarms.
                            si:SetScript("OnClick", function()
                                local current = armedSeconds()
                                dropMenu:Hide()
                                ShowThresholdSecondsPopup(current > 0 and current or nil, function(v)
                                    if v and v > 0 then
                                        acc.set("thresholdSeconds", v)
                                    else
                                        acc.clear("thresholdSeconds")
                                    end
                                    acc.refresh()
                                end)
                            end)
                        elseif item.val == "color" then
                            -- Inline color swatch (same shape as the Active State swipe swatch): picking a color also enables the toggle.
                            si._noCapture = true
                            local swatchBtn, refreshSwatch = CludesUI.BuildColorSwatch(
                                si,
                                si:GetFrameLevel() + 3,
                                function()
                                    return acc.get("thresholdColorR") or 1,
                                        acc.get("thresholdColorG") or 0.2,
                                        acc.get("thresholdColorB") or 0.2,
                                        1
                                end,
                                function(r, g, b)
                                    acc.set("thresholdColorR", r)
                                    acc.set("thresholdColorG", g)
                                    acc.set("thresholdColorB", b)
                                    acc.refresh()
                                end,
                                false,
                                14
                            )
                            swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                            si._refreshSwatch = refreshSwatch
                            swatchBtn:HookScript("PreClick", function()
                                acc.set("thresholdColorEnabled", true)
                                if not acc.get("thresholdColorR") then
                                    acc.set("thresholdColorR", 1)
                                    acc.set("thresholdColorG", 0.2)
                                    acc.set("thresholdColorB", 0.2)
                                end
                                -- Keep the dropdown AND flyout open (OnUpdate cpOpen guard); re-highlight the now-on toggle.
                                if sub._refreshSelection then
                                    sub._refreshSelection()
                                end
                                acc.refresh()
                            end)
                        end
                    end)
                end

                -- A HOSTED buff (buff placed on a CD/util bar) is a real Blizzard buff frame
                -- reparented onto the bar, so it takes the BUFF per-icon menu, not the CD/util
                -- one (same settings as on a buffs bar); isHostedBuff is resolved above
                -- (slot-based). Hosted buffs are removed from Apply-to-Bar entirely (no strip, no bar-tier chaining in ResolveSpellSettings).
                hostedBuffNoApply = isHostedBuff
                if isBuffBar or isHostedBuff then
                    -- Injected custom/preset buffs (cast-timer driven, identified by a stored
                    -- spellDuration) are show-on-cast only, so the Always Show Buffs/Desaturate Inactive overrides (which act on Blizzard-tracked inactive placeholders) don't apply to them.
                    local isInjectedCustom = (sd.spellDurations and (sd.spellDurations[spellId] or 0) > 0)
                        or (sd.customSpellIDs and sd.customSpellIDs[spellId])
                        or false

                    -- Visibility When Missing (HOSTED buffs only): nil = desaturated
                    -- placeholder; "hidden" keeps the reserved slot but renders nothing;
                    -- "hiddenShift" skips the placeholder so later icons close the gap (same
                    -- outcome as Hidden on CD (Shift Icons)). Purely per-spell: no apply opts, hosted rows never get the Apply-to-Bar strip anyway (entries chain to no tier).
                    if isHostedBuff then
                        local MISSING_VIS_ITEMS = {
                            { val = nil, label = "Desaturated" },
                            { val = "hidden", label = "Hidden" },
                            { val = "hiddenShift", label = "Hidden (Shift Icons)" },
                        }
                        MakeSubnavRow("Visibility When Missing", MISSING_VIS_ITEMS, function()
                            return ss.hostedMissingVis
                        end, function(v)
                            EnsureSS()
                            SetOwn("hostedMissingVis", v)
                            -- Re-collect so the placeholder is re-injected, skipped, or re-marked immediately.
                            if mod.QueueReanchor then
                                mod.QueueReanchor()
                            end
                        end, function()
                            return ss.hostedMissingVis == nil
                        end)
                    end

                    -- Always Show Buff heads a buff's menu: per-icon tri-state override of the bar
                    -- toggle, for Blizzard-tracked buffs on a buff bar only (injected custom/preset
                    -- buffs are show-on-cast; a hosted buff has no such bar toggle to override).
                    -- Default = inherit bar; Show = force the inactive placeholder on; Hide = force it off. A reanchor (queued by the row's setVal) creates/removes the placeholder.
                    if not isInjectedCustom and not isHostedBuff then
                        local ALWAYS_SHOW_ITEMS = {
                            { val = nil, label = "Default" },
                            { val = "on", label = "Show" },
                            { val = "off", label = "Hide" },
                            -- Inverse reminder mode: placeholder renders while the
                            -- buff is MISSING, and the ACTIVE buff renders hidden
                            -- (layout gap closes).
                            { val = "missing", label = "Show When Missing" },
                            -- Independent of the choice above, used with Show When Missing: the
                            -- active buff also shows for its last N seconds (0 = off). Scalar popup
                            -- value, same shape as Threshold Seconds.
                            {
                                val = "below",
                                label = "Also Show Below",
                                scalarApply = true,
                                dynamicLabel = function()
                                    local base = CludesUI.L("Also Show Below")
                                    local s = tonumber(ss.missingShowBelow) or 0
                                    if s > 0 then
                                        return base .. " (" .. s .. "s)"
                                    end
                                    return base
                                end,
                                tooltip = "With Show When Missing, also show the buff for its last seconds. Buffs whose timers are hidden from addons in instances stay hidden there.",
                                toggleGet = function()
                                    return (tonumber(ss.missingShowBelow) or 0) > 0
                                end,
                                applyKeys = { "missingShowBelow" },
                                applyWrite = function(t, v)
                                    local s = (v ~= false) and tonumber(ss.missingShowBelow) or 0
                                    t.missingShowBelow = (s > 0) and s or false
                                end,
                            },
                        }
                        MakeSubnavRow(
                            "Always Show Buff",
                            ALWAYS_SHOW_ITEMS,
                            function()
                                return ss.alwaysShow
                            end,
                            function(v)
                                -- Also Show Below opens its own popup; any other value is not this row's.
                                if v ~= nil and v ~= "on" and v ~= "off" and v ~= "missing" then
                                    return
                                end
                                EnsureSS()
                                SetOwn("alwaysShow", v)
                                -- Refresh the page so "Keep Buffs in Same Place" grays/ungrays as this per-icon override flips.
                                CludesUI:RefreshPage()
                            end,
                            function()
                                return ss.alwaysShow == nil
                            end,
                            function(si, item)
                                if item.val ~= "below" then
                                    return
                                end
                                -- Popup flow (mirrors Threshold Seconds): 0 turns it off.
                                si:SetScript("OnClick", function()
                                    local current = tonumber(ss.missingShowBelow) or 0
                                    dropMenu:Hide()
                                    ShowThresholdSecondsPopup(
                                        current > 0 and current or nil,
                                        function(v)
                                            EnsureSS()
                                            SetOwn("missingShowBelow", (v and v > 0) and v or nil)
                                            mod.QueueReanchor()
                                        end,
                                        CludesUI.L("Also Show Below"),
                                        CludesUI.L("Seconds left when the buff shows again (0 = off)")
                                    )
                                end)
                            end,
                            -- Mutually exclusive with the bar's "Keep Buffs in Same Place": that
                            -- mode reserves every buff's slot and ignores per-icon overrides, so
                            -- disable this row while it's on. Escape hatch: if THIS icon is the one
                            -- already forcing "on" (legacy both-enabled data), keep the row editable so the user can clear it, which re-enables Keep Buffs.
                            {
                                disabled = function()
                                    local edge = mod.barDataByKey and mod.barDataByKey[barId]
                                    return edge and edge.hidePlaceholderIcon == true and ss.alwaysShow ~= "on"
                                        or false
                                end,
                                disabledTooltip = "Disabled while Keep Buffs in Same Place is enabled",
                                -- Also Show Below acts only with Show When Missing: locked
                                -- otherwise, unless it holds a value (clickable to clear it).
                                itemState = function(si, item)
                                    if item.val ~= "below" then
                                        return
                                    end
                                    SetFlyoutItemLocked(
                                        si,
                                        ss.alwaysShow ~= "missing"
                                            and (tonumber(ss.missingShowBelow) or 0) <= 0,
                                        "Requires Show When Missing"
                                    )
                                end,
                                apply = {
                                    keys = { "alwaysShow" },
                                    write = function(t, v)
                                        t.alwaysShow = v
                                    end,
                                },
                            }
                        )
                    end

                    -- BUFF BAR per-icon menu. "Buff Glow" reuses the glow-style picker but is
                    -- driven by the while-shown buff-glow path (not proc). nil = inherit the bar's Buff Glow; 0 = None (force the glow off on this one icon).
                    local BUFF_GLOW_ITEMS = GlowStyleItems("Default", 0)
                    MakeSubnavRow(
                        "Buff Glow",
                        BUFF_GLOW_ITEMS,
                        function()
                            return ss.buffGlow
                        end,
                        function(v)
                            EnsureSS()
                            SetOwn("buffGlow", v)
                        end,
                        function()
                            return ss.buffGlow == nil
                        end,
                        nil,
                        {
                            apply = {
                                keys = { "buffGlow" },
                                write = function(t, v)
                                    t.buffGlow = v
                                end,
                            },
                        }
                    )

                    -- Glow When Visible: glows while the icon shows (Show When Missing placeholder
                    -- or present buff), using the Buff Glow style above (Modern WoW Glow if None).
                    MakeSubnavRow(
                        "Glow When Visible",
                        GLOW_VISIBLE_ITEMS,
                        function()
                            return ss.glowWhenVisible and true or nil
                        end,
                        SetGlowWhenVisible,
                        function()
                            return ss.glowWhenVisible == nil
                        end,
                        nil,
                        GLOW_VISIBLE_APPLY
                    )

                    local BUFF_GLOW_COLOR_ITEMS = {
                        { val = nil, label = "Default" },
                        { val = "class", label = "Class Color" },
                        { val = "custom", label = "Custom" },
                    }
                    MakeSubnavRow(
                        "Glow Effect Color",
                        BUFF_GLOW_COLOR_ITEMS,
                        function()
                            return ss.buffGlowColor
                        end,
                        function(v)
                            EnsureSS()
                            SetOwn("buffGlowColor", v)
                            if v == "custom" and not ss.buffGlowColorR then
                                ss.buffGlowColorR = 1
                                ss.buffGlowColorG = 0.776
                                ss.buffGlowColorB = 0.376
                            end
                        end,
                        function()
                            return ss.buffGlowColor == nil
                        end,
                        AB.CustomColorSwatch("buffGlowColor", 0.776, 0.376),
                        AB.CustomColorApply("buffGlowColor", 0.776, 0.376)
                    )

                    -- Cooldown Swipe (buffs only): tints the aura-duration swipe. Default =
                    -- the bar's swipe colour; Class/Custom mirror Glow Effect Color; None fully hides the swipe (alpha 0). Applied on the buff frame by the SetSwipeColor hook (which reads these keys).
                    local CD_SWIPE_COLOR_ITEMS = {
                        { val = nil, label = "Default" },
                        { val = "class", label = "Class Color" },
                        { val = "custom", label = "Custom" },
                        { val = "none", label = "None" },
                    }
                    MakeSubnavRow(
                        "Cooldown Swipe",
                        CD_SWIPE_COLOR_ITEMS,
                        function()
                            return ss.cdSwipeColor
                        end,
                        function(v)
                            EnsureSS()
                            SetOwn("cdSwipeColor", v)
                            if v == "custom" and not ss.cdSwipeColorR then
                                ss.cdSwipeColorR = 1
                                ss.cdSwipeColorG = 0.776
                                ss.cdSwipeColorB = 0.376
                            end
                            if mod.RefreshCDMIconAppearance then
                                mod.RefreshCDMIconAppearance(barId)
                            end
                        end,
                        function()
                            return ss.cdSwipeColor == nil
                        end,
                        AB.CustomColorSwatch("cdSwipeColor", 0.776, 0.376),
                        AB.CustomColorApply("cdSwipeColor", 0.776, 0.376)
                    )

                    -- Duration Text + Charge/Stack Size: each row opens a cog popup mirroring
                    -- the bar's control. Per-icon values override the bar; untouched fields inherit (get falls back to bar).
                    local cdmBd = mod.barDataByKey and mod.barDataByKey[barId]
                    -- Accent cue helpers: "changed" = override set AND its EFFECTIVE value
                    -- differs from the bar's, so an override matching the bar (or a bar edit
                    -- catching up) shows no accent. valChanged for scalars/toggles; colChanged for an RGB triple (nil components fall back to the bar's).
                    local function valChanged(sv, bv)
                        return sv ~= nil and sv ~= bv
                    end
                    local function colChanged(sr, sg, scrollBar, br, backdrop, bb)
                        if sr == nil and sg == nil and scrollBar == nil then
                            return false
                        end
                        return (sr or br) ~= br or (sg or backdrop) ~= backdrop or (scrollBar or bb) ~= bb
                    end
                    -- isChanged: a function returning true when this cog's per-icon values
                    -- DIFFER from the bar; the row label then rests at accent instead of dim (same "this is customized" cue as tri-state rows).
                    local function MakeCogRow(labelText, isChanged, buildCog)
                        local row, labelFS = AB.NewMenuRow(labelText)
                        -- Resting label color: accent when this cog's values differ from the bar, dim when they all match/inherit it.
                        local function UpdateLabel()
                            if isChanged() then
                                local aR, aG, aB = CludesUI.GetAccentColor()
                                labelFS:SetTextColor(aR, aG, aB, 1)
                            else
                                labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                            end
                        end
                        row._updateLabel = UpdateLabel
                        UpdateLabel()
                        local arrow = row:CreateTexture(nil, "ARTWORK")
                        arrow:SetSize(10, 10)
                        arrow:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                        arrow:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\right-arrow.png")
                        arrow:SetAlpha(0.7)
                        local highlight = row:CreateTexture(nil, "ARTWORK")
                        highlight:SetAllPoints()
                        highlight:SetColorTexture(1, 1, 1, 0)
                        highlight:SetAlpha(0)
                        -- Show on hover, anchored to the side, like the other subnav flyouts.
                        -- Reuse BuildCogPopup but drop its slide animation + click-outside dismiss so the menu's _openSub machinery (hover-to-switch, close-with-menu) controls it.
                        local _, showFn, popFrame
                        local function ShowCog()
                            if not showFn then
                                _, showFn = buildCog(row)
                            end
                            if not popFrame then
                                showFn(row) -- first call creates + shows it
                                popFrame = showFn._popupFrame
                            else
                                if popFrame._refresh then
                                    popFrame._refresh()
                                end
                                popFrame:Show()
                            end
                            if popFrame then
                                popFrame:SetScript("OnUpdate", nil)
                                popFrame:SetAlpha(1)
                                popFrame:ClearAllPoints()
                                popFrame:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 0)
                            end
                        end
                        row:SetScript("OnEnter", function()
                            labelFS:SetTextColor(1, 1, 1, 1)
                            highlight:SetColorTexture(1, 1, 1, hlA)
                            highlight:SetAlpha(1)
                            if
                                dropMenu._openSub
                                and dropMenu._openSub ~= popFrame
                                and dropMenu._openSub.Hide
                            then
                                dropMenu._openSub:Hide()
                            end
                            ShowCog()
                            dropMenu._openSub = popFrame
                        end)
                        row:SetScript("OnLeave", function()
                            UpdateLabel()
                            highlight:SetAlpha(0)
                        end)
                        mH = mH + ITEM_H
                        return row
                    end

                    MakeCogRow("Duration Text", function()
                        local b = cdmBd
                        return valChanged(ss.showCooldownText, (b and b.showCooldownText) ~= false)
                            or valChanged(ss.cooldownFontSize, (b and b.cooldownFontSize) or 12)
                            or colChanged(
                                ss.cooldownTextR,
                                ss.cooldownTextG,
                                ss.cooldownTextB,
                                (b and b.cooldownTextR) or 1,
                                (b and b.cooldownTextG) or 1,
                                (b and b.cooldownTextB) or 1
                            )
                            or valChanged(ss.cooldownTextPosition, (b and b.cooldownTextPosition) or "center")
                            or valChanged(ss.cooldownTextX, (b and b.cooldownTextX) or 0)
                            or valChanged(ss.cooldownTextY, (b and b.cooldownTextY) or 0)
                    end, function(row)
                        return CludesUI.BuildCogPopup({
                            -- Level 350: above the spell-picker menu (300) but below the shared
                            -- color picker (FULLSCREEN_DIALOG 400) so the picker renders on top. The dropdown menu is bumped above the popup in BuildCogPopup's dropdown OnClick hook.
                            title = "Duration Text",
                            noOwnerDim = true,
                            frameStrata = "FULLSCREEN_DIALOG",
                            frameLevel = 350,
                            rows = {
                                {
                                    type = "toggle",
                                    label = "Show Duration",
                                    get = function()
                                        if ss.showCooldownText ~= nil then
                                            return ss.showCooldownText
                                        end
                                        return (cdmBd and cdmBd.showCooldownText) ~= false
                                    end,
                                    set = function(v)
                                        EnsureSS()
                                        ss.showCooldownText = v
                                        mod._cdmAnySpellDurationText = true
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                                {
                                    type = "slider",
                                    label = "Size",
                                    min = 6,
                                    max = 30,
                                    step = 1,
                                    get = function()
                                        return ss.cooldownFontSize or (cdmBd and cdmBd.cooldownFontSize) or 12
                                    end,
                                    set = function(v)
                                        EnsureSS()
                                        ss.cooldownFontSize = v
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                                {
                                    type = "colorpicker",
                                    label = "Color",
                                    get = function()
                                        return ss.cooldownTextR or (cdmBd and cdmBd.cooldownTextR) or 1,
                                            ss.cooldownTextG or (cdmBd and cdmBd.cooldownTextG) or 1,
                                            ss.cooldownTextB or (cdmBd and cdmBd.cooldownTextB) or 1
                                    end,
                                    set = function(r, g, b)
                                        EnsureSS()
                                        ss.cooldownTextR = r
                                        ss.cooldownTextG = g
                                        ss.cooldownTextB = b
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                                {
                                    type = "dropdown",
                                    label = "Position",
                                    values = durationPositionValues,
                                    order = durationPositionOrder,
                                    get = function()
                                        return ss.cooldownTextPosition
                                            or (cdmBd and cdmBd.cooldownTextPosition)
                                            or "center"
                                    end,
                                    set = function(v)
                                        EnsureSS()
                                        ss.cooldownTextPosition = v
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                                {
                                    type = "slider",
                                    label = "X Offset",
                                    min = -50,
                                    max = 50,
                                    step = 1,
                                    get = function()
                                        return ss.cooldownTextX or (cdmBd and cdmBd.cooldownTextX) or 0
                                    end,
                                    set = function(v)
                                        EnsureSS()
                                        ss.cooldownTextX = v
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
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
                                        return ss.cooldownTextY or (cdmBd and cdmBd.cooldownTextY) or 0
                                    end,
                                    set = function(v)
                                        EnsureSS()
                                        ss.cooldownTextY = v
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                            },
                        })
                    end)

                    MakeCogRow("Stack Text and Glows", function()
                        local b = cdmBd
                        return valChanged(ss.showChargeStackText, (b and b.showChargeStackText) ~= false)
                            or ss.buffGlowStackEnabled == true
                            or valChanged(ss.stackCountSize, (b and b.stackCountSize) or 11)
                            or colChanged(
                                ss.stackCountR,
                                ss.stackCountG,
                                ss.stackCountB,
                                (b and b.stackCountR) or 1,
                                (b and b.stackCountG) or 1,
                                (b and b.stackCountB) or 1
                            )
                            or valChanged(
                                ss.stackCountPosition,
                                (b and b.stackCountPosition) or "bottomright"
                            )
                            or valChanged(ss.stackCountX, (b and b.stackCountX) or 0)
                            or valChanged(ss.stackCountY, (b and b.stackCountY) or 0)
                    end, function(row)
                        return CludesUI.BuildCogPopup({
                            title = "Stack Text and Glows",
                            noOwnerDim = true,
                            frameStrata = "FULLSCREEN_DIALOG",
                            frameLevel = 350,
                            rows = {
                                {
                                    type = "toggle",
                                    label = "Glow at Stacks",
                                    tooltip = "Replaces Buff Glow: the icon glows when its stack count matches the comparison below, using this spell's Buff Glow style (Modern WoW Glow if none is set).",
                                    get = function()
                                        return ss.buffGlowStackEnabled == true
                                    end,
                                    set = function(v)
                                        EnsureSS()
                                        ss.buffGlowStackEnabled = v or nil
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                                {
                                    type = "dropdown",
                                    label = "Comparison",
                                    values = {
                                        lt = "Below (<)",
                                        lte = "At Most (<=)",
                                        eq = "Exactly (=)",
                                        gte = "At Least (>=)",
                                        gt = "Above (>)",
                                    },
                                    order = { "lt", "lte", "eq", "gte", "gt" },
                                    disabled = function()
                                        return not ss.buffGlowStackEnabled
                                    end,
                                    disabledTooltip = "Enable Glow at Stacks",
                                    get = function()
                                        return ss.buffGlowStackOperator or "gte"
                                    end,
                                    set = function(v)
                                        EnsureSS()
                                        ss.buffGlowStackOperator = v ~= "gte" and v or nil
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                                {
                                    type = "input",
                                    label = "Stack Count",
                                    inputWidth = 42,
                                    commitOnBlur = true,
                                    disabled = function()
                                        return not ss.buffGlowStackEnabled
                                    end,
                                    disabledTooltip = "Enable Glow at Stacks",
                                    get = function()
                                        return tostring(tonumber(ss.buffGlowStackThreshold) or 2)
                                    end,
                                    set = function(v)
                                        local t = math.floor(tonumber(v) or 0)
                                        if t < 1 then
                                            t = 1
                                        end
                                        if t > 99 then
                                            t = 99
                                        end
                                        EnsureSS()
                                        ss.buffGlowStackThreshold = t
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                                {
                                    type = "toggle",
                                    label = "Show Stack Text",
                                    get = function()
                                        if ss.showChargeStackText ~= nil then
                                            return ss.showChargeStackText
                                        end
                                        return (cdmBd and cdmBd.showChargeStackText) ~= false
                                    end,
                                    set = function(v)
                                        EnsureSS()
                                        ss.showChargeStackText = v
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                                {
                                    type = "slider",
                                    label = "Size",
                                    min = 6,
                                    max = 30,
                                    step = 1,
                                    get = function()
                                        return ss.stackCountSize or (cdmBd and cdmBd.stackCountSize) or 11
                                    end,
                                    set = function(v)
                                        EnsureSS()
                                        ss.stackCountSize = v
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                                {
                                    type = "colorpicker",
                                    label = "Color",
                                    get = function()
                                        return ss.stackCountR or (cdmBd and cdmBd.stackCountR) or 1,
                                            ss.stackCountG or (cdmBd and cdmBd.stackCountG) or 1,
                                            ss.stackCountB or (cdmBd and cdmBd.stackCountB) or 1
                                    end,
                                    set = function(r, g, b)
                                        EnsureSS()
                                        ss.stackCountR = r
                                        ss.stackCountG = g
                                        ss.stackCountB = b
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                                {
                                    type = "dropdown",
                                    label = "Position",
                                    values = {
                                        bottomright = "Bottom Right",
                                        bottom = "Bottom",
                                        bottomleft = "Bottom Left",
                                        left = "Left",
                                        topleft = "Top Left",
                                        top = "Top",
                                        topright = "Top Right",
                                        right = "Right",
                                        center = "Center",
                                    },
                                    order = {
                                        "bottomright",
                                        "bottom",
                                        "bottomleft",
                                        "left",
                                        "topleft",
                                        "top",
                                        "topright",
                                        "right",
                                        "center",
                                    },
                                    get = function()
                                        return ss.stackCountPosition
                                            or (cdmBd and cdmBd.stackCountPosition)
                                            or "bottomright"
                                    end,
                                    set = function(v)
                                        EnsureSS()
                                        ss.stackCountPosition = v
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                                {
                                    type = "slider",
                                    label = "X Offset",
                                    min = -150,
                                    max = 150,
                                    step = 1,
                                    get = function()
                                        return ss.stackCountX or (cdmBd and cdmBd.stackCountX) or 0
                                    end,
                                    set = function(v)
                                        EnsureSS()
                                        ss.stackCountX = v
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                                {
                                    type = "slider",
                                    label = "Y Offset",
                                    min = -150,
                                    max = 150,
                                    step = 1,
                                    get = function()
                                        return ss.stackCountY or (cdmBd and cdmBd.stackCountY) or 0
                                    end,
                                    set = function(v)
                                        EnsureSS()
                                        ss.stackCountY = v
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                            },
                        })
                    end)

                    -- Border: per-icon override of the bar's border SIZE + COLOR (never style).
                    -- Mirrors the Charges/Stacks cog exactly; the render side reads (ssb and ssb.border*) or the bar value in ApplyShapeToCDMIcon.
                    MakeCogRow("Border", function()
                        local b = cdmBd
                        return valChanged(ss.borderSize, (b and b.borderSize) or 1)
                            or colChanged(
                                ss.borderR,
                                ss.borderG,
                                ss.borderB,
                                (b and b.borderR) or 0,
                                (b and b.borderG) or 0,
                                (b and b.borderB) or 0
                            )
                    end, function(row)
                        return CludesUI.BuildCogPopup({
                            title = "Border",
                            noOwnerDim = true,
                            frameStrata = "FULLSCREEN_DIALOG",
                            frameLevel = 350,
                            rows = {
                                {
                                    type = "slider",
                                    label = "Size",
                                    min = 0,
                                    max = 8,
                                    step = 1,
                                    get = function()
                                        return ss.borderSize or (cdmBd and cdmBd.borderSize) or 1
                                    end,
                                    set = function(v)
                                        EnsureSS()
                                        ss.borderSize = v
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                                {
                                    type = "colorpicker",
                                    label = "Color",
                                    get = function()
                                        return ss.borderR or (cdmBd and cdmBd.borderR) or 0,
                                            ss.borderG or (cdmBd and cdmBd.borderG) or 0,
                                            ss.borderB or (cdmBd and cdmBd.borderB) or 0
                                    end,
                                    set = function(r, g, b)
                                        EnsureSS()
                                        ss.borderR = r
                                        ss.borderG = g
                                        ss.borderB = b
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if row._updateLabel then
                                            row._updateLabel()
                                        end
                                    end,
                                },
                            },
                        })
                    end)

                    -- Audio on Buff Gain/Loss sound list + speaker-preview decorator. Defined
                    -- once here so the Blizzard-tracked-buff rows AND the self-timed preset/custom
                    -- gain row share the same list + preview (entries mirror the Focus Cast Sound dropdown via the shared ns.FOCUSKICK_SOUND_* tables).
                    local AUDIO_ITEMS = SoundItems()
                    -- Speaker-preview decorator: plays a row's focused sound without selecting it (mirrors the dropdown's preview icon).
                    -- "Audio on Buff Gain": stored per-icon as ss.buffActiveSoundKey ("none"/nil
                    -- = silent). Blizzard-tracked buffs fire it via the apply-edge hook
                    -- (EnsureBuffSoundHook -> TriggerAuraAppliedAlert); self-timed preset/custom buffs fire it from the cast-timer gain edge in UpdateCustomBuffBars (CdmHooks) off the SAME stored key.
                    local function AddBuffGainRow()
                        MakeSubnavRow(
                            "Audio on Buff Gain",
                            AUDIO_ITEMS,
                            function()
                                return ss.buffActiveSoundKey or "none"
                            end,
                            function(v)
                                EnsureSS()
                                SetOwn("buffActiveSoundKey", (v ~= "none" and v) or nil)
                                -- Flip the 0-cost gate live so the edge hook/cast timer starts playing on the next activation.
                                if ss.buffActiveSoundKey then
                                    mod._cdmAnyBuffSound = true
                                end
                            end,
                            function()
                                return ss.buffActiveSoundKey == nil
                            end,
                            AddSoundPreviewButton,
                            {
                                searchable = true,
                                apply = {
                                    keys = { "buffActiveSoundKey" },
                                    write = function(t, v)
                                        -- "None" applied bar-wide = explicitly silent (false blocks the tier below).
                                        t.buffActiveSoundKey = (v ~= "none" and v) or false
                                    end,
                                },
                            }
                        )
                    end
                    -- "Audio on Buff Loss": stored per-icon as ss.buffLostSoundKey.
                    local function AddBuffLossRow()
                        MakeSubnavRow(
                            "Audio on Buff Loss",
                            AUDIO_ITEMS,
                            function()
                                return ss.buffLostSoundKey or "none"
                            end,
                            function(v)
                                EnsureSS()
                                SetOwn("buffLostSoundKey", (v ~= "none" and v) or nil)
                                if ss.buffLostSoundKey then
                                    mod._cdmAnyBuffSound = true
                                end
                            end,
                            function()
                                return ss.buffLostSoundKey == nil
                            end,
                            AddSoundPreviewButton,
                            {
                                searchable = true,
                                apply = {
                                    keys = { "buffLostSoundKey" },
                                    write = function(t, v)
                                        t.buffLostSoundKey = (v ~= "none" and v) or false
                                    end,
                                },
                            }
                        )
                    end

                    -- Desaturate Inactive applies only to Blizzard-tracked buffs (inactive
                    -- placeholders); injected custom/preset buffs skip it and get only the gain row.
                    if not isInjectedCustom then
                        -- Hosted buffs (on a CD/util bar) OMIT this bar-toggle override: desaturate-inactive
                        -- is baked in (a cd/util bar has no such bar toggle to override). Audio rows below still apply, so they stay outside this guard.
                        if not isHostedBuff then
                            -- Desaturate Inactive: per-icon tri-state override of the bar's Always
                            -- Show Buffs "Desaturate Off CD" cog setting. Applies to this buff's inactive placeholder. Default = inherit bar.
                            local DESAT_ITEMS = {
                                { val = nil, label = "Default" },
                                { val = "on", label = "Desaturate" },
                                { val = "off", label = "Full Color" },
                            }
                            MakeSubnavRow(
                                "Desaturate Inactive",
                                DESAT_ITEMS,
                                function()
                                    return ss.desatInactive
                                end,
                                function(v)
                                    EnsureSS()
                                    SetOwn("desatInactive", v)
                                end,
                                function()
                                    return ss.desatInactive == nil
                                end,
                                nil,
                                {
                                    apply = {
                                        keys = { "desatInactive" },
                                        write = function(t, v)
                                            t.desatInactive = v
                                        end,
                                    },
                                }
                            )
                        end -- if not isHostedBuff (bar-toggle override omitted)

                        AddBuffGainRow()
                        AddBuffLossRow()
                    else
                        -- Self-timed preset/custom buffs: both edges driven off the displayed timer in UpdateCustomBuffBars (no real aura event).
                        AddBuffGainRow()
                        AddBuffLossRow()
                    end

                    -- Reverse Swipe (buffs/custom buffs/buff presets): reverses the buff's fill
                    -- direction. Default off. Same per-spell store (ss) + runtime apply + zero-cost gate as cd/utility spells; placed outside the injected split so it's offered for every buff type.
                    MakeSubnavRow(
                        "Reverse Swipe",
                        REVERSE_SWIPE_ITEMS,
                        function()
                            return ss.reverseSwipe and true or nil
                        end,
                        function(v)
                            EnsureSS()
                            SetOwn("reverseSwipe", v or nil)
                            if v then
                                mod._cdmAnyReverseSwipe = true
                            end
                            if mod.RefreshCDMIconAppearance then
                                mod.RefreshCDMIconAppearance(barId)
                            end
                        end,
                        function()
                            return ss.reverseSwipe == nil
                        end,
                        nil,
                        {
                            apply = {
                                keys = { "reverseSwipe" },
                                write = function(t, v)
                                    -- "Off" applied bar-wide blocks the tier below.
                                    t.reverseSwipe = v or false
                                end,
                            },
                        }
                    )

                    -- Threshold Text (every buff type): decimals/color change on the aura
                    -- countdown below the spell's Threshold Seconds. Same per-spell store (ss) +
                    -- engine countdown formatter as cd/utility spells; the engine evaluates it, so secret aura durations format fine.
                    do
                        local acc = {}
                        acc.get = function(k)
                            return ss[k]
                        end
                        acc.set = function(k, v)
                            EnsureSS()
                            ss[k] = v
                        end
                        acc.clear = function(k)
                            EnsureSS()
                            SetOwn(k, nil)
                        end
                        acc.refresh = function()
                            if (tonumber(ss.thresholdSeconds) or 0) > 0 then
                                mod._cdmAnyThresholdText = true
                            end
                            if mod.RefreshCDMIconAppearance then
                                mod.RefreshCDMIconAppearance(barId)
                            end
                            if mod.QueueReanchor then
                                mod.QueueReanchor()
                            end
                        end
                        AddThresholdTextRow(acc)
                    end
                else
                    local isCustomInjected = spellId < 0
                        or (mod._myRacialsSet and mod._myRacialsSet[spellId])
                        or (sd.customSpellIDs and sd.customSpellIDs[spellId])

                    if isCustomInjected then
                        -- Custom Active State for preset icons (trinkets/potions/racials/custom
                        -- spell IDs): these have no Blizzard active detection, so the only setting is
                        -- a user-defined active overlay (CludesUICdmFakeActive.lua) -- a timer plus
                        -- the standard Active Swipe/Active Glow/Glow Effect Color. It lives in a
                        -- PROFILE-level store keyed by the spell (ns.GetCustomActiveState), so it
                        -- travels with the spell across every bar and spec, not in this bar's per-spell settings. Trinket slots key by the EQUIPPED item, so each tracks separately (casKey).
                        local casKey = (mod.ResolveCustomActiveKey and mod.ResolveCustomActiveKey(spellId))
                            or spellId
                        local cas = mod.GetCustomActiveState and mod.GetCustomActiveState(casKey) or nil
                        -- Trinket slots: the menu DISPLAYS the effective view -- the equipped item's
                        -- own entry chained per-key over the slot's "Apply to Bar" stamp
                        -- (GetEffectiveCustomActiveState uses the same chain at render time) -- while
                        -- WRITES stay item-keyed (casKey), so each trinket still tracks separately.
                        -- casKey == spellID means no item is equipped (writes then target the slot entry itself); never chain an entry to itself.
                        local casSlot = nil
                        if mod.SlotIDFromKey(spellId) and casKey ~= spellId and mod.GetCustomActiveState then
                            casSlot = mod.GetCustomActiveState(spellId)
                        end
                        -- Not-yet-persisted fresh view, persisted on first WRITE -- same contract as the family-store EnsureSS above.
                        if not cas then
                            cas = {}
                        end
                        if mod.ChainSettings then
                            mod.ChainSettings(cas, casSlot)
                        end
                        local function EnsureCAS()
                            local storeC = mod.GetCustomActiveStates and mod.GetCustomActiveStates()
                            if storeC and not storeC[casKey] then
                                storeC[casKey] = cas
                            end
                            return cas
                        end
                        -- Own-value writer for nil-off keys: writing nil would let a
                        -- slot-stamp value show through the chain; when that would
                        -- change the effective value, store explicit false instead
                        -- (render-equivalent to nil, but blocks the inheritance --
                        -- the per-trinket exclusion). Mirrors the family SetOwn.
                        local function SetCasOwn(key, v2)
                            local e = EnsureCAS()
                            e[key] = v2
                            if v2 == nil and e[key] ~= nil then
                                e[key] = false
                            end
                        end
                        local hasActive = (cas.duration or 0) > 0

                        -- (The divider above the per-icon settings is already drawn
                        -- before the buff/CD branch, so we don't add another here.)

                        -- Plain clickable action row (label + hover highlight).
                        local function MakeActionRow(textValue, onClick)
                            local row, labelFS = AB.NewMenuRow(textValue)
                            labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                            local highlight = row:CreateTexture(nil, "ARTWORK")
                            highlight:SetAllPoints()
                            highlight:SetColorTexture(1, 1, 1, 0)
                            highlight:SetAlpha(0)
                            row:SetScript("OnEnter", function()
                                labelFS:SetTextColor(1, 1, 1, 1)
                                highlight:SetColorTexture(1, 1, 1, hlA)
                                highlight:SetAlpha(1)
                                if dropMenu._openSub and dropMenu._openSub:IsShown() then
                                    dropMenu._openSub:Hide()
                                end
                            end)
                            row:SetScript("OnLeave", function()
                                labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                highlight:SetAlpha(0)
                            end)
                            row:SetScript("OnClick", onClick)
                            mH = mH + ITEM_H
                            return row
                        end

                        local GLOW_COLOR_ITEMS = {
                            { val = nil, label = "Default" },
                            { val = "class", label = "Class Color" },
                            { val = "custom", label = "Custom" },
                        }
                        local CA_SWIPE_ITEMS = {
                            { val = "custom", label = "Swipe Color" },
                            { val = "class", label = "Swipe Class Colored" },
                            { val = "none", label = "Hide Active State" },
                        }
                        -- The preset menu's glow choices, written on this icon's own entry;
                        -- the preset engine then re-arms. A bar that applies the Resource
                        -- Aware glow shows it here as the CD Ready choice, whose bar apply
                        -- keeps that variant: the bar's scope then reads as holding it, and
                        -- an apply never swaps the bar's spells to the plain glow.
                        local casGlowWrite = AB.CdGlowWrite(cas)
                        local casGlowMenu = {
                            get = function()
                                return AB.MenuGlow(cas, true)
                            end,
                            set = function(v)
                                mod.CdStateWriteGlow(EnsureCAS(), v)
                                if mod.FakeActive_Rearm then
                                    mod.FakeActive_Rearm()
                                end
                            end,
                            write = function(t, v)
                                if
                                    v == "pixelGlowReady"
                                    and AB.MenuGlow(mod.GetBarTierSettings(sd, barId))
                                        == "pixelGlowReadyUsable"
                                then
                                    v = "pixelGlowReadyUsable"
                                end
                                casGlowWrite(t, v)
                            end,
                            view = function(t)
                                return AB.MenuGlow(t, true)
                            end,
                        }
                        local CD_STATE_ITEMS = {
                            { val = nil, label = "None" },
                            -- The glow beside the hide effect, picked or cleared like a "+"
                            -- toggle. No Resource Aware choice: the preset engine reads no
                            -- usability.
                            AB.CdGlowItem(casGlowMenu, "pixelGlowReady", "Glow (CD Ready)"),
                            AB.CdGlowItem(casGlowMenu, "glowOnCD", "Glow (On CD)"),
                            -- Same logic as Hidden (On CD) with a customizable opacity.
                            {
                                val = "lowerAlphaOnCD",
                                label = "Lower Alpha (On CD)",
                                dynamicLabel = function()
                                    local base = CludesUI.L("Lower Alpha (On CD)")
                                    if cas and cas.cdStateEffect == "lowerAlphaOnCD" then
                                        local pct = math.floor(((cas.cdStateLowerAlpha or 0.5) * 100) + 0.5)
                                        return pct .. "% " .. base
                                    end
                                    return base
                                end,
                            },
                            -- Shift variants: same hide as the plain modes below, but
                            -- the bar re-lays out so remaining icons close the gap.
                            { val = "hiddenOnCDShift", label = "Hidden on CD (Shift Icons)" },
                            { val = "hiddenReadyShift", label = "Hidden CD Ready (Shift Icons)" },
                            {
                                val = "hiddenUnusableShift",
                                label = "Hidden Until Usable (Shift Icons)",
                                tooltip = "Only shown while usable and off cooldown, such as Overpower or Victory Rush after a proc. Low resources do not hide it.",
                            },
                            {
                                val = "hiddenFormShift",
                                label = "Hidden Outside Form/Stance (Shift Icons)",
                                tooltip = "Only shown in the form or stance the spell needs, even while it is on cooldown.",
                            },
                            { val = "hiddenOnCD", label = "Hidden (On CD)" },
                            { val = "hiddenReady", label = "Hidden (CD Ready)" },
                            {
                                val = "hiddenUnusable",
                                label = "Hidden (Until Usable)",
                                tooltip = "Only shown while usable and off cooldown, such as Overpower or Victory Rush after a proc. Low resources do not hide it.",
                            },
                            {
                                val = "hiddenForm",
                                label = "Hidden (Outside Form/Stance)",
                                tooltip = "Only shown in the form or stance the spell needs, even while it is on cooldown.",
                            },
                        }
                        local KEEP_COLORED_ITEMS = {
                            { val = nil, label = "None" },
                            { val = true, label = "Keep Colored (On CD)" },
                        }
                        local RANGE_COLOR_ITEMS = {
                            { val = nil, label = "Off" },
                            { val = true, label = "Color Out of Range" },
                        }

                        -- Right-aligned colour swatch on a subnav item.
                        -- Per-spell settings are outside Spec Overrides, so the swatch opts out of capture.
                        local function MakeColorSwatch(si, getR, getG, getB, onChanged)
                            si._noCapture = true
                            local sw, refreshSwatch = CludesUI.BuildColorSwatch(
                                si,
                                si:GetFrameLevel() + 3,
                                function()
                                    return getR(), getG(), getB(), 1
                                end,
                                function(r, g, b)
                                    onChanged(r, g, b)
                                end,
                                false,
                                14
                            )
                            sw:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                            si._refreshSwatch = refreshSwatch
                        end

                        -- Combat Potion Icon (the three combat potion presets): the order the
                        -- icon tracks the families in and whether a family out of bags swaps
                        -- to the next (CUI_CDM_HookPresetCooldowns.lua, PotSwap). A flyout of
                        -- its own: the swap toggle, then one row per family, dragged into the
                        -- icon's priority order through the shared row reorder. Both settings
                        -- sit on the icon's customActiveStates entry (potSwap, potOrder), so
                        -- they travel with the entry across bars and specs; an unset toggle
                        -- reads the old profile-wide switch.
                        local potPreset = mod.ItemPresetForKey and mod.ItemPresetForKey(spellId)
                        if
                            potPreset
                            and potPreset.potFamily
                            and mod.COMBAT_POTION_FAMILIES
                            and #mod.COMBAT_POTION_FAMILIES > 0
                        then
                            local function PotSwapOn()
                                if cas.potSwap == nil then
                                    return mod.PotSwapLegacyDefault()
                                end
                                return cas.potSwap == true
                            end
                            local function PotIsDefault()
                                return cas.potSwap == nil and cas.potOrder == nil
                            end
                            local function PotChanged()
                                if mod._BumpPotResolveGen then
                                    mod._BumpPotResolveGen()
                                end
                                if mod._MarkPresetCdDirty then
                                    mod._MarkPresetCdDirty()
                                end
                                if mod.FakeActive_Rearm then
                                    mod.FakeActive_Rearm()
                                end
                                if mod.QueueReanchor then
                                    mod.QueueReanchor()
                                end
                            end

                            local row, labelFS = AB.NewMenuRow("Combat Potion Icon")
                            local acR, acG, acB = CludesUI.GetAccentColor()
                            local function PaintRow()
                                if PotIsDefault() then
                                    labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                else
                                    labelFS:SetTextColor(acR, acG, acB, 1)
                                end
                            end
                            PaintRow()
                            local arrow = row:CreateTexture(nil, "ARTWORK")
                            arrow:SetSize(10, 10)
                            arrow:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                            arrow:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\right-arrow.png")
                            arrow:SetAlpha(0.7)
                            local highlight = row:CreateTexture(nil, "ARTWORK")
                            highlight:SetAllPoints()
                            highlight:SetColorTexture(1, 1, 1, 0)
                            highlight:SetAlpha(0)

                            local sub
                            local function ShowPotSub()
                                if
                                    dropMenu._openSub
                                    and dropMenu._openSub ~= sub
                                    and dropMenu._openSub.Hide
                                then
                                    dropMenu._openSub:Hide()
                                end
                                if sub then
                                    if not sub:IsShown() then
                                        sub:Show()
                                    end
                                    dropMenu._openSub = sub
                                    return
                                end
                                sub = CreateFrame("Frame", nil, dropMenu)
                                sub:SetFrameStrata("FULLSCREEN_DIALOG")
                                sub:SetFrameLevel(dropMenu:GetFrameLevel() + 5)
                                sub:SetClampedToScreen(true)
                                sub:EnableMouse(true)
                                sub:SetPoint("TOPLEFT", row, "TOPRIGHT", 2, 0)
                                local subBg = sub:CreateTexture(nil, "BACKGROUND")
                                subBg:SetAllPoints()
                                subBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
                                CludesUI.MakeRoundedBorder(sub, 1, 1, 1, mBrdA, subBg, nil, true)
                                local labels = {}
                                local subH = 4

                                -- Swap Combat Pots When Missing: an independent toggle with
                                -- the "+" look (accent text while on).
                                local tg = CreateFrame("Button", nil, sub)
                                tg:SetHeight(ITEM_H)
                                tg:SetPoint("TOPLEFT", sub, "TOPLEFT", 1, -subH)
                                tg:SetPoint("TOPRIGHT", sub, "TOPRIGHT", -1, -subH)
                                tg:SetFrameLevel(sub:GetFrameLevel() + 2)
                                local tgLbl = tg:CreateFontString(nil, "OVERLAY")
                                tgLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                                tgLbl:SetPoint("LEFT", 10, 0)
                                tgLbl:SetJustifyH("LEFT")
                                tgLbl:SetText(CludesUI.L("Swap Combat Pots When Missing"))
                                labels[#labels + 1] = tgLbl
                                local tgHl = tg:CreateTexture(nil, "ARTWORK")
                                tgHl:SetAllPoints()
                                tgHl:SetColorTexture(1, 1, 1, hlA)
                                tgHl:SetAlpha(0)
                                local function PaintToggle()
                                    if PotSwapOn() then
                                        tgLbl:SetTextColor(acR, acG, acB, 1)
                                    else
                                        tgLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                    end
                                end
                                PaintToggle()
                                tg:SetScript("OnEnter", function()
                                    tgLbl:SetTextColor(1, 1, 1, 1)
                                    tgHl:SetAlpha(1)
                                    CludesUI.ShowWidgetTooltip(
                                        tg,
                                        CludesUI.L(
                                            "When your bags hold none of the potion the icon tracks, it tracks the next potion in the priority order that you own."
                                        )
                                    )
                                end)
                                tg:SetScript("OnLeave", function()
                                    PaintToggle()
                                    tgHl:SetAlpha(0)
                                    CludesUI.HideWidgetTooltip()
                                end)
                                tg:SetScript("OnClick", function()
                                    EnsureCAS().potSwap = not PotSwapOn()
                                    PaintToggle()
                                    PaintRow()
                                    PotChanged()
                                end)
                                subH = subH + ITEM_H

                                -- Priority Order: one row per family at a fixed slot, the top
                                -- one the potion the icon tracks; a drop shuffles the rows'
                                -- contents (CludesUI.AttachRowReorder).
                                local head = sub:CreateFontString(nil, "OVERLAY")
                                head:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                                head:SetTextColor(1, 1, 1, 0.35)
                                head:SetPoint("TOPLEFT", sub, "TOPLEFT", 10, -subH - 6)
                                head:SetText(CludesUI.L("Priority Order"))
                                labels[#labels + 1] = head
                                local hint = sub:CreateFontString(nil, "OVERLAY")
                                hint:SetFont(FONT_PATH, 9, GetCDMOptOutline())
                                hint:SetTextColor(1, 1, 1, 0.25)
                                hint:SetPoint("RIGHT", sub, "TOPRIGHT", -10, -subH - 11)
                                hint:SetText(CludesUI.L("Drag to Reorder"))
                                subH = subH + 20
                                local rowsTop = subH
                                local famByKey = {}
                                for _, fam in ipairs(mod.COMBAT_POTION_FAMILIES) do
                                    famByKey[fam.key] = fam
                                end
                                local movable = {}
                                for _, k in ipairs(mod.PotOrderFor(potPreset, cas.potOrder)) do
                                    local fam = famByKey[k]
                                    if fam then
                                        movable[#movable + 1] = {
                                            key = k,
                                            label = fam.name,
                                            icon = fam.preset.icon
                                                or (
                                                    fam.preset.itemID
                                                    and C_Item.GetItemIconByID(fam.preset.itemID)
                                                ),
                                        }
                                    end
                                end
                                local function SlotY(idx)
                                    return -(rowsTop + (idx - 1) * ITEM_H)
                                end
                                local rowList = {}
                                local dragState = { dragging = false }
                                for idx = 1, #movable do
                                    local r = CreateFrame("Button", nil, sub)
                                    r:SetHeight(ITEM_H)
                                    r:SetPoint("TOPLEFT", sub, "TOPLEFT", 1, SlotY(idx))
                                    r:SetPoint("TOPRIGHT", sub, "TOPRIGHT", -1, SlotY(idx))
                                    r:SetFrameLevel(sub:GetFrameLevel() + 2)
                                    r._item = movable[idx]
                                    r._slotY = SlotY(idx)
                                    local rIco = r:CreateTexture(nil, "ARTWORK")
                                    rIco:SetSize(ITEM_H - 6, ITEM_H - 6)
                                    rIco:SetPoint("RIGHT", r, "RIGHT", -26, 0)
                                    rIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                                    local rLbl = r:CreateFontString(nil, "OVERLAY")
                                    rLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                                    rLbl:SetPoint("LEFT", 10, 0)
                                    rLbl:SetPoint("RIGHT", rIco, "LEFT", -5, 0)
                                    rLbl:SetJustifyH("LEFT")
                                    rLbl:SetWordWrap(false)
                                    rLbl:SetMaxLines(1)
                                    labels[#labels + 1] = rLbl
                                    -- The three-dash drag handle of the reorder dropdowns.
                                    for g = 1, 3 do
                                        local bar = r:CreateTexture(nil, "ARTWORK")
                                        bar:SetSize(10, 1)
                                        bar:SetPoint("RIGHT", r, "RIGHT", -10, (2 - g) * 3)
                                        bar:SetColorTexture(1, 1, 1, 0.35)
                                    end
                                    local rHl = r:CreateTexture(nil, "ARTWORK")
                                    rHl:SetAllPoints()
                                    rHl:SetColorTexture(1, 1, 1, hlA)
                                    rHl:SetAlpha(0)
                                    local function Paint()
                                        rLbl:SetText(CludesUI.L(r._item.label))
                                        rLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                        rIco:SetTexture(CludesUI.ClientIcon(r._item.icon))
                                    end
                                    Paint()
                                    r._paint = Paint
                                    r:SetScript("OnEnter", function()
                                        if dragState.dragging then
                                            return
                                        end
                                        rLbl:SetTextColor(1, 1, 1, 1)
                                        rHl:SetAlpha(1)
                                    end)
                                    r:SetScript("OnLeave", function()
                                        if dragState.dragging then
                                            return
                                        end
                                        rLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                                        rHl:SetAlpha(0)
                                    end)
                                    rowList[idx] = r
                                end
                                local insLine = sub:CreateTexture(nil, "OVERLAY", nil, 7)
                                insLine:SetHeight(2)
                                local ACC = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
                                insLine:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.9)
                                insLine:Hide()
                                CludesUI.AttachRowReorder(sub, {
                                    rows = rowList,
                                    items = movable,
                                    itemH = ITEM_H,
                                    slotY = SlotY,
                                    insLine = insLine,
                                    state = dragState,
                                    refresh = function()
                                        for idx = 1, #rowList do
                                            rowList[idx]._item = movable[idx]
                                            rowList[idx]._paint()
                                        end
                                    end,
                                    onDragStart = function()
                                        for idx = 1, #rowList do
                                            rowList[idx]._paint()
                                        end
                                    end,
                                    onDrop = function(keyList)
                                        EnsureCAS().potOrder = table.concat(keyList, ",")
                                        PaintRow()
                                        PotChanged()
                                    end,
                                })
                                subH = rowsTop + #movable * ITEM_H
                                sub:SetSize(FitMenuWidth(labels, 200, 64), subH + 4)
                                sub:Show()
                                dropMenu._openSub = sub
                            end
                            row:SetScript("OnEnter", function()
                                labelFS:SetTextColor(1, 1, 1, 1)
                                highlight:SetColorTexture(1, 1, 1, hlA)
                                highlight:SetAlpha(1)
                                ShowPotSub()
                            end)
                            row:SetScript("OnLeave", function()
                                PaintRow()
                                highlight:SetAlpha(0)
                            end)
                            mH = mH + ITEM_H
                        end

                        -- Cooldown State Effect (always available for presets; driven by the live
                        -- cooldown, independent of the active overlay): the hide single-select
                        -- plus the "+ Glow" choices beside it (see the regular-spell row). The
                        -- strip's own-entry writes keep the spell entry, as every preset row's do.
                        -- Picking or clearing a glow (or a bar apply doing so) rebuilds the menu,
                        -- which adds or drops the Glow Style row below.
                        local hadGlowC = mod.CdStateGlowOf(cas) ~= nil
                        dropMenu._cseRow = MakeSubnavRow("Cooldown State Effect", CD_STATE_ITEMS, function()
                            return mod.CdStateHideOf(cas)
                        end, function(v)
                            mod.CdStateWriteHide(EnsureCAS(), v)
                            if mod.FakeActive_Rearm then
                                mod.FakeActive_Rearm()
                            end
                        end, function()
                            return not cas.cdStateEffect and not cas.cdStateGlow
                        end, function(si, item, sub)
                            -- Lower Alpha (On CD): prompt for the opacity percent,
                            -- then select the effect (mirrors the setVal above).
                            if item.val == "lowerAlphaOnCD" then
                                si:SetScript("OnClick", function()
                                    local current =
                                        math.floor((((cas and cas.cdStateLowerAlpha) or 0.5) * 100) + 0.5)
                                    -- Close the per-spell dropdown so only the popup shows.
                                    dropMenu:Hide()
                                    ShowAlphaPopup(current, function(pct)
                                        local c = EnsureCAS()
                                        c.cdStateLowerAlpha = pct / 100
                                        mod.CdStateWriteHide(c, "lowerAlphaOnCD")
                                        if mod.FakeActive_Rearm then
                                            mod.FakeActive_Rearm()
                                        end
                                    end)
                                end)
                            end
                        end, {
                            itemState = AB.CdStateItemState(cas, nil, true),
                            onRefresh = function()
                                if (mod.CdStateGlowOf(cas) ~= nil) ~= hadGlowC then
                                    dropMenu._rebuildPending = true
                                end
                            end,
                            apply = {
                                keys = { "cdStateEffect", "cdStateLowerAlpha" },
                                write = AB.CdHideWrite(cas),
                                view = mod.CdStateHideOf,
                            },
                        })

                        -- Glow Style (preset/custom): mirror of the regular-spell row, shown only
                        -- while a glow is picked in Cooldown State Effect.
                        if hadGlowC then
                            MakeSubnavRow("Glow Style", CD_READY_STYLE_ITEMS, function()
                                return mod.CdReadyGlowStyle(mod.CdStateGlowOf(cas), cas)
                            end, function(v)
                                SetCasOwn("cdStateGlowStyle", v)
                                if mod.FakeActive_Rearm then
                                    mod.FakeActive_Rearm()
                                end
                            end, function()
                                return cas.cdStateGlowStyle == nil
                            end, function(si, item, sub)
                                -- Blackout: clicking prompts for the opacity percent, then
                                -- selects this style (mirrors Lower Alpha's onClick above).
                                if item.val == 8 then
                                    item.dynamicLabel = function()
                                        local base = CludesUI.L(mod.GLOW_STYLES[8].name)
                                        if mod.CdReadyGlowStyle(mod.CdStateGlowOf(cas), cas) == 8 then
                                            local pct = math.floor(((cas.cdStateGlowAlpha or 1) * 100) + 0.5)
                                            return pct .. "% " .. base
                                        end
                                        return base
                                    end
                                    si:SetScript("OnClick", function()
                                        local current =
                                            math.floor((((cas and cas.cdStateGlowAlpha) or 1) * 100) + 0.5)
                                        dropMenu:Hide()
                                        ShowAlphaPopup(
                                            current,
                                            function(pct)
                                                local c = EnsureCAS()
                                                c.cdStateGlowAlpha = pct / 100
                                                c.cdStateGlowStyle = 8
                                                if mod.FakeActive_Rearm then
                                                    mod.FakeActive_Rearm()
                                                end
                                            end,
                                            CludesUI.L("Glow Opacity"),
                                            CludesUI.L("Blackout glow opacity (1-100%)")
                                        )
                                    end)
                                end
                            end, {
                                apply = {
                                    keys = { "cdStateGlowStyle", "cdStateGlowAlpha" },
                                    write = function(t, v)
                                        t.cdStateGlowStyle = v
                                        t.cdStateGlowAlpha = (v == 8) and cas and cas.cdStateGlowAlpha or nil
                                    end,
                                },
                            })
                        end -- hadGlowC

                        -- Cooldown Saturation (preset/custom): mirror of the regular-spell row.
                        -- These icons are greyed by the Fake-Active engine rather than by Blizzard, so the runtime reads this key in PresetKeepsColor instead of the SetDesaturated hook -- same setting, same key name.
                        -- Spells added by Spell ID also get "+ Ignore Resource Cost" (racials and
                        -- items carry no resource tint); the runtime reads it in PresetIgnoresResourceTint.
                        local satItems = KEEP_COLORED_ITEMS
                        if
                            sd.customSpellIDs
                            and sd.customSpellIDs[spellId]
                            and not (mod._myRacialsSet and mod._myRacialsSet[spellId])
                        then
                            satItems = {
                                KEEP_COLORED_ITEMS[1],
                                KEEP_COLORED_ITEMS[2],
                                {
                                    val = "ignoreResource",
                                    label = "+ Ignore Resource Cost",
                                    tooltip = "Keeps the icon in full color while you lack the resource to cast it. Out of range still tints it red.",
                                    toggleGet = function()
                                        return cas.noResourceTint == true
                                    end,
                                    toggleSet = function(v)
                                        SetCasOwn("noResourceTint", v or nil)
                                        if v then
                                            mod._cdmAnyNoResourceTint = true
                                        end
                                        if mod._MarkPresetCdDirty then
                                            mod._MarkPresetCdDirty()
                                        end
                                    end,
                                    applyKeys = { "noResourceTint" },
                                    applyWrite = function(t, v)
                                        t.noResourceTint = v and true or false
                                    end,
                                },
                            }
                        end
                        MakeSubnavRow(
                            "Cooldown Saturation",
                            satItems,
                            function()
                                local v = cas.noDesatOnCD
                                if v == false then
                                    v = nil
                                end -- blocked slot value = None
                                return v and true or nil
                            end,
                            function(v)
                                SetCasOwn("noDesatOnCD", v or nil)
                                if v then
                                    mod._cdmAnyNoDesatOnCD = true
                                end
                                if mod.FakeActive_Rearm then
                                    mod.FakeActive_Rearm()
                                end
                                if mod.RefreshCDMIconAppearance then
                                    mod.RefreshCDMIconAppearance(barId)
                                end
                            end,
                            function()
                                return not cas.noDesatOnCD and not cas.noResourceTint
                            end,
                            nil,
                            {
                                apply = {
                                    keys = { "noDesatOnCD" },
                                    write = function(t, v)
                                        t.noDesatOnCD = v or false
                                    end,
                                },
                            }
                        )

                        -- Threshold Text (preset/custom): decimals/color change on this icon's
                        -- countdowns (item/spell cooldown and the fake-active window) below its
                        -- Threshold Seconds. Stored in the profile customActiveStates so it travels with the spell; the Fake-Active engine and the appearance pass both read it.
                        do
                            local acc = {}
                            acc.get = function(k)
                                return cas[k]
                            end
                            acc.set = function(k, v)
                                local e = EnsureCAS()
                                e[k] = v
                            end
                            acc.clear = function(k)
                                -- Own clear; when a slot-stamp value would show
                                -- through the chain, store the blocking false.
                                cas[k] = nil
                                if cas[k] ~= nil then
                                    SetCasOwn(k, false)
                                end
                            end
                            acc.refresh = function()
                                if (tonumber(cas.thresholdSeconds) or 0) > 0 then
                                    mod._cdmAnyThresholdText = true
                                end
                                if mod.RefreshCDMIconAppearance then
                                    mod.RefreshCDMIconAppearance(barId)
                                end
                                if mod.FakeActive_Rearm then
                                    mod.FakeActive_Rearm()
                                end
                                if mod.QueueReanchor then
                                    mod.QueueReanchor()
                                end
                            end
                            AddThresholdTextRow(acc)
                        end

                        -- Cooldown Swipe (preset/custom): Reverse Swipe flips this icon's swipe
                        -- direction; Hide CD Swipe removes it. Default off. Stored in the profile customActiveStates so it travels with the spell.
                        MakeSubnavRow(
                            "Cooldown Swipe",
                            CD_SWIPE_ITEMS,
                            function()
                                if cas and cas.hideCDSwipe then
                                    return "hide"
                                end
                                if cas and cas.reverseSwipe then
                                    return "reverse"
                                end
                                return nil
                            end,
                            function(v)
                                SetCasOwn("reverseSwipe", (v == "reverse") or nil)
                                SetCasOwn("hideCDSwipe", (v == "hide") or nil)
                                if v == "reverse" then
                                    mod._cdmAnyReverseSwipe = true
                                end
                                if v == "hide" then
                                    mod._cdmAnyHideCDSwipe = true
                                end
                                if mod.RefreshCDMIconAppearance then
                                    mod.RefreshCDMIconAppearance(barId)
                                end
                                if mod.FakeActive_Rearm then
                                    mod.FakeActive_Rearm()
                                end
                            end,
                            function()
                                return not (cas and (cas.reverseSwipe or cas.hideCDSwipe))
                            end,
                            nil,
                            {
                                apply = {
                                    keys = { "reverseSwipe", "hideCDSwipe" },
                                    write = function(t, v)
                                        t.reverseSwipe = (v == "reverse") or false
                                        t.hideCDSwipe = (v == "hide") or false
                                    end,
                                },
                            }
                        )

                        -- Stance Bar (preset/custom): as on the regular-spell menu, stored in
                        -- customActiveStates; the Fake-Active engine runs it.
                        if AB.STANCE_BAR_ITEMS then
                            MakeSubnavRow(
                                "Stance Bar",
                                AB.STANCE_BAR_ITEMS,
                                function()
                                    return cas.stanceBarHide or nil
                                end,
                                function(v)
                                    SetCasOwn("stanceBarHide", v)
                                    if v then
                                        mod._cdmAnyStanceBar = true
                                    end
                                    if mod.RefreshCDMIconAppearance then
                                        mod.RefreshCDMIconAppearance(barId)
                                    end
                                    if mod.FakeActive_Rearm then
                                        mod.FakeActive_Rearm()
                                    end
                                end,
                                function()
                                    return not cas.stanceBarHide
                                end,
                                nil,
                                {
                                    apply = {
                                        keys = { "stanceBarHide" },
                                        write = function(t, v)
                                            t.stanceBarHide = v or false
                                            if v then
                                                mod._cdmAnyStanceBar = true
                                            end
                                        end,
                                    },
                                }
                            )
                        end

                        -- Out of Range Coloring (spells added by Spell ID only): they have no
                        -- Blizzard viewer frame, so nothing tinted them out of range. Default off;
                        -- stored in customActiveStates so it travels with the spell. Racials and
                        -- items are not offered it (item range checks are protected in combat).
                        -- Greyed for a spell with no range in its base or live form, unless
                        -- already on (so it can still be cleared).
                        if
                            sd.customSpellIDs
                            and sd.customSpellIDs[spellId]
                            and not (mod._myRacialsSet and mod._myRacialsSet[spellId])
                        then
                            MakeSubnavRow(
                                "Out of Range Coloring",
                                RANGE_COLOR_ITEMS,
                                function()
                                    return cas.outOfRangeColoring and true or nil
                                end,
                                function(v)
                                    SetCasOwn("outOfRangeColoring", v or nil)
                                    if v then
                                        mod._cdmAnyCustomRangeColor = true
                                    end
                                    mod.RefreshCustomSpellRange()
                                end,
                                function()
                                    return not cas.outOfRangeColoring
                                end,
                                nil,
                                {
                                    disabled = function()
                                        if cas.outOfRangeColoring then
                                            return false
                                        end
                                        if C_Spell.SpellHasRange(spellId) then
                                            return false
                                        end
                                        local ovr = C_SpellBook.FindSpellOverrideByID(spellId)
                                        return not (ovr and ovr > 0 and C_Spell.SpellHasRange(ovr))
                                    end,
                                    disabledTooltip = "Requires a spell with a range",
                                }
                            )
                        end

                        -- Audio Effect on CD Ready (preset/trinket/racial/custom): fired when the
                        -- ability comes off cooldown via the FakeActive poll (PresetOnCD). Stored in
                        -- customActiveStates so it travels with the item (own list/preview: the buff-bar branch's shared AUDIO_ITEMS is out of scope in this branch).
                        local CDR_ITEMS = SoundItems()
                        MakeSubnavRow("Audio Effect on CD Ready", CDR_ITEMS, function()
                            return (cas and cas.cdReadySoundKey) or "none"
                        end, function(v)
                            local e = EnsureCAS()
                            e.cdReadySoundKey = (v ~= "none" and v) or nil
                            if mod.FakeActive_Rearm then
                                mod.FakeActive_Rearm()
                            end
                        end, function()
                            return not (cas and cas.cdReadySoundKey)
                        end, AddSoundPreviewButton, { searchable = true })

                        if not hasActive then
                            MakeActionRow("Add Active State", function()
                                ShowDurationPopup(nil, function(seconds)
                                    EnsureCAS().duration = seconds
                                    if mod.FakeActive_Rearm then
                                        mod.FakeActive_Rearm()
                                    end
                                end)
                                dropMenu:Hide()
                            end)
                        else
                            -- Active State (swipe colour / class / hide)
                            MakeSubnavRow("Active State", CA_SWIPE_ITEMS, function()
                                if cas and cas.activeSwipeMode == "none" then
                                    return "none"
                                end
                                if cas and cas.activeSwipeClassColor then
                                    return "class"
                                end
                                return "custom"
                            end, function(v)
                                local e = EnsureCAS()
                                if v == "class" then
                                    SetCasOwn("activeSwipeMode", nil)
                                    SetCasOwn("activeSwipeClassColor", true)
                                elseif v == "none" then
                                    SetCasOwn("activeSwipeMode", "none")
                                    SetCasOwn("activeSwipeClassColor", nil)
                                else
                                    SetCasOwn("activeSwipeMode", "custom")
                                    SetCasOwn("activeSwipeClassColor", nil)
                                    -- Chained read: a slot-stamp color showing
                                    -- through is kept as the starting custom color.
                                    if not e.activeSwipeR then
                                        e.activeSwipeR = 1
                                        e.activeSwipeG = 0.776
                                        e.activeSwipeB = 0.376
                                        e.activeSwipeA = 0.7
                                    end
                                end
                            end, function()
                                return cas
                                    and cas.activeSwipeMode ~= "none"
                                    and not cas.activeSwipeClassColor
                                    and not cas.activeSwipeR
                            end, function(si, item)
                                if item.val == "custom" then
                                    MakeColorSwatch(si, function()
                                        return (cas and cas.activeSwipeR) or 1
                                    end, function()
                                        return (cas and cas.activeSwipeG) or 0.776
                                    end, function()
                                        return (cas and cas.activeSwipeB) or 0.376
                                    end, function(r, g, b)
                                        local e = EnsureCAS()
                                        e.activeSwipeMode = "custom"
                                        SetCasOwn("activeSwipeClassColor", nil)
                                        e.activeSwipeR = r
                                        e.activeSwipeG = g
                                        e.activeSwipeB = b
                                        e.activeSwipeA = e.activeSwipeA or 0.7
                                    end)
                                end
                            end, {
                                apply = {
                                    keys = {
                                        "activeSwipeMode",
                                        "activeSwipeClassColor",
                                        "activeSwipeR",
                                        "activeSwipeG",
                                        "activeSwipeB",
                                        "activeSwipeA",
                                    },
                                    write = function(t, v)
                                        -- Read the source colour BEFORE the clear below: a bar
                                        -- apply stamps every preset member's cas entry, this icon's included, so clearing first would wipe the colour this write then reads back.
                                        local pr, pg, pb, pa
                                        if cas then
                                            pr, pg, pb, pa =
                                                cas.activeSwipeR,
                                                cas.activeSwipeG,
                                                cas.activeSwipeB,
                                                cas.activeSwipeA
                                        end
                                        -- Colour keys belong to Custom only; clear them for
                                        -- class/none so a stale colour from an earlier Custom
                                        -- apply can't linger in the tier. Leftover R/G/B/A
                                        -- make valuesMatch always fail, so the apply never
                                        -- toggles off and re-prompts the overwrite popup
                                        -- forever without visibly changing anything.
                                        t.activeSwipeR = nil
                                        t.activeSwipeG = nil
                                        t.activeSwipeB = nil
                                        t.activeSwipeA = nil
                                        if v == "class" then
                                            t.activeSwipeMode = false
                                            t.activeSwipeClassColor = true
                                        elseif v == "none" then
                                            t.activeSwipeMode = "none"
                                            t.activeSwipeClassColor = false
                                        else
                                            -- Custom: push this icon's current color.
                                            t.activeSwipeMode = "custom"
                                            t.activeSwipeClassColor = false
                                            t.activeSwipeR = pr or 1
                                            t.activeSwipeG = pg or 0.776
                                            t.activeSwipeB = pb or 0.376
                                            t.activeSwipeA = pa or 0.7
                                        end
                                    end,
                                },
                            })

                            -- Active State Glow
                            MakeSubnavRow(
                                "Active State Glow",
                                ACTIVE_GLOW_ITEMS,
                                function()
                                    local v = cas.activeGlow
                                    if v == false then
                                        v = nil
                                    end -- blocked slot value = None
                                    return v
                                end,
                                function(v)
                                    SetCasOwn("activeGlow", v)
                                end,
                                function()
                                    return not cas.activeGlow
                                end,
                                nil,
                                {
                                    apply = {
                                        keys = { "activeGlow" },
                                        write = function(t, v)
                                            t.activeGlow = v
                                        end,
                                    },
                                }
                            )
                        end

                        -- Glow Effect Color (colours the active glow AND the CD-ready glow).
                        MakeSubnavRow("Glow Effect Color", GLOW_COLOR_ITEMS, function()
                            if cas and cas.glowColor == "class" then
                                return "class"
                            end
                            if cas and cas.glowColor == "custom" then
                                return "custom"
                            end
                            return nil
                        end, function(v)
                            SetCasOwn("glowColor", v)
                            -- Chained read: a slot-stamp color showing through
                            -- is kept as the starting custom color.
                            if v == "custom" and not cas.glowColorR then
                                local e = EnsureCAS()
                                e.glowColorR = 1
                                e.glowColorG = 0.788
                                e.glowColorB = 0.137
                            end
                        end, function()
                            return not (cas and cas.glowColor)
                        end, function(si, item)
                            if item.val == "custom" then
                                MakeColorSwatch(si, function()
                                    return (cas and cas.glowColorR) or 1
                                end, function()
                                    return (cas and cas.glowColorG) or 0.788
                                end, function()
                                    return (cas and cas.glowColorB) or 0.137
                                end, function(r, g, b)
                                    local e = EnsureCAS()
                                    e.glowColor = "custom"
                                    e.glowColorR = r
                                    e.glowColorG = g
                                    e.glowColorB = b
                                end)
                            end
                        end, {
                            apply = {
                                keys = { "glowColor", "glowColorR", "glowColorG", "glowColorB" },
                                write = function(t, v)
                                    t.glowColor = v
                                    if v == "custom" then
                                        -- Push this icon's current color.
                                        t.glowColorR = (cas and cas.glowColorR) or 1
                                        t.glowColorG = (cas and cas.glowColorG) or 0.788
                                        t.glowColorB = (cas and cas.glowColorB) or 0.137
                                    else
                                        t.glowColorR = nil
                                        t.glowColorG = nil
                                        t.glowColorB = nil
                                    end
                                end,
                            },
                        })

                        -- Remove Active State (clears only the cast-triggered overlay; any Cooldown State Effect stays).
                        if hasActive then
                            MakeActionRow(
                                CludesUI.L("Remove Active State") .. " (" .. (cas.duration or 0) .. "s)",
                                function()
                                    local storage = mod.GetCustomActiveStates and mod.GetCustomActiveStates()
                                    local e = storage and storage[casKey]
                                    if e then
                                        e.duration = nil
                                        -- Prune only when nothing but active-overlay keys is left:
                                        -- the other rows (cd state, saturation, swipe, range, glow
                                        -- colour, sound, threshold) store here too. pairs walks own
                                        -- keys only, so a chained slot stamp never holds it alive.
                                        local keep
                                        for k in pairs(e) do
                                            if
                                                k ~= "activeSwipeMode"
                                                and k ~= "activeSwipeClassColor"
                                                and k ~= "activeSwipeR"
                                                and k ~= "activeSwipeG"
                                                and k ~= "activeSwipeB"
                                                and k ~= "activeSwipeA"
                                                and k ~= "activeGlow"
                                            then
                                                keep = true
                                                break
                                            end
                                        end
                                        if not keep then
                                            storage[casKey] = nil
                                        end
                                    end
                                    if mod.FakeActive_Rearm then
                                        mod.FakeActive_Rearm()
                                    end
                                    dropMenu:Hide()
                                end
                            )
                        end
                    else -- regular Blizzard-tracked cooldown: full per-spell menu
                        local customDisabledTip = "Not available for custom injected spells"
                        -- On a custom injected spell, a row that does not apply to it is
                        -- dimmed, and hovering it shows why in place of its flyout.
                        AB.DimForCustom = function(row)
                            if not (isCustomInjected and row) then
                                return
                            end
                            row:SetAlpha(0.35)
                            row:SetScript("OnEnter", function()
                                CludesUI.ShowWidgetTooltip(row, customDisabledTip)
                            end)
                            row:SetScript("OnLeave", function()
                                CludesUI.HideWidgetTooltip()
                            end)
                        end

                        -- Custom-shaped bars always render Shape Glow, so the per-spell proc
                        -- glow choice is locked (custom = any Icon Shape other than None/Cropped).
                        local cdmBd = mod.barDataByKey and mod.barDataByKey[barId]
                        local barCustomShape = cdmBd
                            and cdmBd.iconShape
                            and cdmBd.iconShape ~= "none"
                            and cdmBd.iconShape ~= "cropped"

                        -- 1. Proc Glow (default = nil)
                        local procRow = MakeSubnavRow(
                            "Proc Glow",
                            GLOW_ITEMS,
                            function()
                                return ss.procGlow
                            end,
                            function(v)
                                EnsureSS()
                                SetOwn("procGlow", v)
                            end,
                            function()
                                return ss.procGlow == nil
                            end,
                            nil,
                            {
                                apply = {
                                    keys = { "procGlow" },
                                    write = function(t, v)
                                        t.procGlow = v
                                    end,
                                },
                                -- Glow choices lock while the Cooldown State Effect has a glow
                                -- (CD Ready or On CD): the reverse of that row's Proc Glow gate.
                                itemState = function(si, item)
                                    if item.val and item.val > 0 then
                                        SetFlyoutItemLocked(
                                            si,
                                            mod.CdStateGlowOf(ss) ~= nil,
                                            "Disable the Cooldown State glow first"
                                        )
                                    end
                                end,
                            }
                        )
                        if procRow and (isCustomInjected or barCustomShape) then
                            local procDisabledTip = isCustomInjected and customDisabledTip
                                or "Custom shapes always use Shape Glow. Set the bar's Icon Shape to None or Cropped to pick a different glow."
                            procRow:SetAlpha(0.35)
                            procRow:SetScript("OnEnter", function()
                                CludesUI.ShowWidgetTooltip(procRow, procDisabledTip)
                            end)
                            procRow:SetScript("OnLeave", function()
                                CludesUI.HideWidgetTooltip()
                            end)
                        end

                        -- 2. Active State (default = "custom" / CD Swipe Color #FFC660)
                        local activeRow = MakeSubnavRow("Active State", ACTIVE_SWIPE_ITEMS, function()
                            if ss.activeSwipeMode == "none" then
                                return "none"
                            end
                            if ss.activeSwipeClassColor then
                                return "class"
                            end
                            return "custom"
                        end, function(v)
                            EnsureSS()
                            if v == "class" then
                                SetOwn("activeSwipeMode", nil)
                                ss.activeSwipeClassColor = true
                            elseif v == "none" then
                                ss.activeSwipeMode = "none"
                                SetOwn("activeSwipeClassColor", nil)
                            else
                                -- Custom: keep existing color, only set defaults if none
                                ss.activeSwipeMode = "custom"
                                SetOwn("activeSwipeClassColor", nil)
                                if not ss.activeSwipeR then
                                    ss.activeSwipeR = 1
                                    ss.activeSwipeG = 0.776
                                    ss.activeSwipeB = 0.376
                                    ss.activeSwipeA = 0.7
                                end
                            end
                        end, function()
                            if ss.activeBorderEnabled then
                                return false
                            end
                            if ss.activeSwipeMode == "none" or ss.activeSwipeClassColor then
                                return false
                            end
                            -- Check if custom color differs from default #FFC660
                            local dr, dg, db = 1, 0.776, 0.376
                            local cr = ss.activeSwipeR or dr
                            local cg = ss.activeSwipeG or dg
                            local cb = ss.activeSwipeB or db
                            if
                                math.abs(cr - dr) > 0.01
                                or math.abs(cg - dg) > 0.01
                                or math.abs(cb - db) > 0.01
                            then
                                return false
                            end
                            return true
                        end, function(si, item, sub)
                            if item.val == "custom" then
                                -- Clickable color swatch on right (opens color picker)
                                si._noCapture = true
                                local swatchBtn, refreshSwatch = CludesUI.BuildColorSwatch(
                                    si,
                                    si:GetFrameLevel() + 3,
                                    function()
                                        return ss.activeSwipeR or 1,
                                            ss.activeSwipeG or 0.776,
                                            ss.activeSwipeB or 0.376,
                                            ss.activeSwipeA or 0.7
                                    end,
                                    function(r, g, b, a)
                                        ss.activeSwipeR = r
                                        ss.activeSwipeG = g
                                        ss.activeSwipeB = b
                                        ss.activeSwipeA = a
                                        if mod.QueueReanchor then
                                            mod.QueueReanchor()
                                        end
                                    end,
                                    true,
                                    14
                                )
                                swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                si._refreshSwatch = refreshSwatch
                                swatchBtn:HookScript("PreClick", function()
                                    -- Persist before mutating: for a spell with no saved settings yet
                                    -- (e.g. a freshly added Hero-talent spell like Wither/Celestial
                                    -- Conduit), `ss` is a throwaway {} -- without EnsureSS the picked
                                    -- colour is written to a temporary table and lost, so the swipe never changes and reverts to default on reopen.
                                    EnsureSS()
                                    -- Ensure custom mode is selected. SetOwn: a plain nil write would inherit a bar-tier "none"/class value instead of meaning custom.
                                    SetOwn("activeSwipeMode", nil)
                                    SetOwn("activeSwipeClassColor", nil)
                                    if not ss.activeSwipeR then
                                        ss.activeSwipeR = 1
                                        ss.activeSwipeG = 0.776
                                        ss.activeSwipeB = 0.376
                                        ss.activeSwipeA = 0.7
                                    end
                                    -- Keep the dropdown AND flyout open (OnUpdate cpOpen guard); re-highlight the now-selected Custom row.
                                    if sub._refreshSelection then
                                        sub._refreshSelection()
                                    end
                                    if mod.QueueReanchor then
                                        mod.QueueReanchor()
                                    end
                                end)
                            elseif item.activeBorder then
                                -- Border Color swatch (mirrors CD Swipe Color): the swatch picks the color and enables the override; the row itself toggles it on/off (handled in the item loop).
                                si._noCapture = true
                                local swatchBtn, refreshSwatch = CludesUI.BuildColorSwatch(
                                    si,
                                    si:GetFrameLevel() + 3,
                                    function()
                                        return ss.activeBorderR or 1,
                                            ss.activeBorderG or 0.776,
                                            ss.activeBorderB or 0.376,
                                            ss.activeBorderA or 1
                                    end,
                                    function(r, g, b, a)
                                        ss.activeBorderR = r
                                        ss.activeBorderG = g
                                        ss.activeBorderB = b
                                        ss.activeBorderA = a
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                        if mod.QueueReanchor then
                                            mod.QueueReanchor()
                                        end
                                    end,
                                    true,
                                    14
                                )
                                swatchBtn:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                                si._refreshSwatch = refreshSwatch
                                swatchBtn:HookScript("PreClick", function()
                                    EnsureSS()
                                    ss.activeBorderEnabled = true
                                    if not ss.activeBorderR then
                                        ss.activeBorderR = 1
                                        ss.activeBorderG = 0.776
                                        ss.activeBorderB = 0.376
                                        ss.activeBorderA = 1
                                    end
                                    -- Keep the dropdown AND flyout open (OnUpdate cpOpen guard). The border toggle row manages its own highlight, so no selection refresh here.
                                    if mod.RefreshCDMIconAppearance then
                                        mod.RefreshCDMIconAppearance(barId)
                                    end
                                    if mod.QueueReanchor then
                                        mod.QueueReanchor()
                                    end
                                end)
                            end
                        end, {
                            apply = {
                                keys = {
                                    "activeSwipeMode",
                                    "activeSwipeClassColor",
                                    "activeSwipeR",
                                    "activeSwipeG",
                                    "activeSwipeB",
                                    "activeSwipeA",
                                },
                                write = function(t, v)
                                    -- Read the source colour BEFORE the clear below: "Apply to This
                                    -- Spell" passes ss itself, so clearing first would wipe the picked colour this write then reads back, resetting it to the default.
                                    local pr, pg, pb, pa =
                                        ss.activeSwipeR, ss.activeSwipeG, ss.activeSwipeB, ss.activeSwipeA
                                    -- Colour keys belong to Custom only; clear them for class/none so a
                                    -- stale colour from an earlier Custom apply can't linger in the tier and make valuesMatch always fail (perpetual overwrite popup, no change).
                                    t.activeSwipeR = nil
                                    t.activeSwipeG = nil
                                    t.activeSwipeB = nil
                                    t.activeSwipeA = nil
                                    if v == "class" then
                                        t.activeSwipeMode = false
                                        t.activeSwipeClassColor = true
                                    elseif v == "none" then
                                        t.activeSwipeMode = "none"
                                        t.activeSwipeClassColor = false
                                    else
                                        -- Custom: push this spell's effective color.
                                        t.activeSwipeMode = "custom"
                                        t.activeSwipeClassColor = false
                                        t.activeSwipeR = pr or 1
                                        t.activeSwipeG = pg or 0.776
                                        t.activeSwipeB = pb or 0.376
                                        t.activeSwipeA = pa or 0.7
                                    end
                                end,
                            },
                        })
                        AB.DimForCustom(activeRow)

                        -- 3. Active State Glow (default = nil / none)
                        local glowRow = MakeSubnavRow(
                            "Active State Glow",
                            ACTIVE_GLOW_ITEMS,
                            function()
                                return ss.activeGlow
                            end,
                            function(v)
                                EnsureSS()
                                SetOwn("activeGlow", v)
                                if v and v > 0 then
                                    mod._cdmAnyActiveGlow = true
                                end
                            end,
                            function()
                                return ss.activeGlow == nil
                            end,
                            nil,
                            {
                                apply = {
                                    keys = { "activeGlow" },
                                    write = function(t, v)
                                        t.activeGlow = v
                                        if v and v > 0 then
                                            mod._cdmAnyActiveGlow = true
                                        end
                                    end,
                                },
                            }
                        )
                        AB.DimForCustom(glowRow)

                        -- 3a. Max Charges Glow (default = nil/none), 1:1 with Active State Glow:
                        -- glows the icon while a charge spell is at max charges. Shares the unified Glow Effect Color below. The stored key stays maxStacksGlow (label-only rename).
                        local maxStacksGlowRow = MakeSubnavRow(
                            "Max Charges Glow",
                            ACTIVE_GLOW_ITEMS,
                            function()
                                return ss.maxStacksGlow
                            end,
                            function(v)
                                EnsureSS()
                                SetOwn("maxStacksGlow", v)
                                if v and v > 0 then
                                    mod._cdmAnyMaxStacksGlow = true
                                end
                            end,
                            function()
                                return ss.maxStacksGlow == nil
                            end,
                            nil,
                            {
                                apply = {
                                    keys = { "maxStacksGlow" },
                                    write = function(t, v)
                                        t.maxStacksGlow = v
                                    end,
                                },
                            }
                        )
                        AB.DimForCustom(maxStacksGlowRow)

                        -- 3b. Non Active State (default = nil/none): desaturates the icon when its active-state is NOT active -- the mirror of the runtime's active-branch SetDesaturated(false).
                        local NONACTIVE_ITEMS = {
                            { val = nil, label = "None" },
                            { val = true, label = "Desaturate When Not Active" },
                        }
                        local nonActiveRow = MakeSubnavRow(
                            "Non Active State",
                            NONACTIVE_ITEMS,
                            function()
                                return ss.desatNotActive and true or nil
                            end,
                            function(v)
                                EnsureSS()
                                SetOwn("desatNotActive", v or nil)
                                if v then
                                    mod._cdmAnyDesatNotActive = true
                                end
                            end,
                            function()
                                return ss.desatNotActive == nil
                            end,
                            nil,
                            {
                                apply = {
                                    keys = { "desatNotActive" },
                                    write = function(t, v)
                                        t.desatNotActive = v or false
                                    end,
                                },
                            }
                        )
                        AB.DimForCustom(nonActiveRow)

                        -- 3c. Cooldown Saturation (default = nil/none): suppresses the grey-out
                        -- Blizzard applies while the spell is on cooldown -- grouped with Non Active State above because both own the icon's saturation.
                        -- "+ Ignore Resource Cost" is an independent toggle (NOT part of the
                        -- single-select): drops Blizzard's blue short-on-resource tint, keeps red out of range.
                        local KEEP_COLORED_ITEMS = {
                            { val = nil, label = "None" },
                            { val = true, label = "Keep Colored (On CD)" },
                            {
                                val = "ignoreResource",
                                label = "+ Ignore Resource Cost",
                                tooltip = "Keeps the icon in full color while you lack the resource to cast it. Out of range still tints it red.",
                                toggleGet = function()
                                    return ss.noResourceTint == true
                                end,
                                toggleSet = function(v)
                                    EnsureSS()
                                    SetOwn("noResourceTint", v or nil)
                                    if v then
                                        mod._cdmAnyNoResourceTint = true
                                    end
                                    if mod.RefreshCDMIconAppearance then
                                        mod.RefreshCDMIconAppearance(barId)
                                    end
                                end,
                                applyKeys = { "noResourceTint" },
                                applyWrite = function(t, v)
                                    t.noResourceTint = v and true or false
                                end,
                            },
                        }
                        local cdSatRow = MakeSubnavRow(
                            "Cooldown Saturation",
                            KEEP_COLORED_ITEMS,
                            function()
                                return ss.noDesatOnCD and true or nil
                            end,
                            function(v)
                                EnsureSS()
                                SetOwn("noDesatOnCD", v or nil)
                                if v then
                                    mod._cdmAnyNoDesatOnCD = true
                                end
                                if mod.RefreshCDMIconAppearance then
                                    mod.RefreshCDMIconAppearance(barId)
                                end
                            end,
                            function()
                                return ss.noDesatOnCD == nil and ss.noResourceTint == nil
                            end,
                            nil,
                            {
                                apply = {
                                    keys = { "noDesatOnCD" },
                                    write = function(t, v)
                                        t.noDesatOnCD = v or false
                                    end,
                                },
                            }
                        )
                        AB.DimForCustom(cdSatRow)

                        -- 4. Cooldown State Effect (default = nil / none): the hide single-select
                        -- (cdStateEffect) plus the "+ Glow" choices beside it (cdStateGlow, see
                        -- CD_STATE_ITEMS); each pick keeps the other half. Pairs that can never
                        -- show both grey out, and the glows lock while a Proc Glow is set.
                        -- Picking or clearing a glow (or a bar apply doing so) rebuilds the menu,
                        -- which adds or drops the Glow Style row below.
                        local hadGlow = mod.CdStateGlowOf(ss) ~= nil
                        local cdStateRow = MakeSubnavRow("Cooldown State Effect", CD_STATE_ITEMS, function()
                            return mod.CdStateHideOf(ss)
                        end, function(v)
                            mod.CdStateWriteHide(EnsureSS(), v)
                            if mod.RefreshCDMIconAppearance then
                                mod.RefreshCDMIconAppearance(barId)
                            end
                        end, function()
                            return ss.cdStateEffect == nil
                                and ss.cdStateGlow == nil
                                and not ss.suppressGCD
                                and not ss.hideChargeText
                                and not ss.chargeHideSwipe
                                and not ss.hideRechargeEdge
                                and not ss.chargeHideCdText
                                and not ss.chargeHideUntilSpent
                        end, function(si, item, sub)
                            -- Lower Alpha (On CD): clicking prompts for the opacity percent, then selects the effect (mirrors the setVal above).
                            if item.val == "lowerAlphaOnCD" then
                                si:SetScript("OnClick", function()
                                    local current = math.floor(((ss.cdStateLowerAlpha or 0.5) * 100) + 0.5)
                                    -- Close the per-spell dropdown so only the popup shows.
                                    dropMenu:Hide()
                                    ShowAlphaPopup(current, function(pct)
                                        local e = EnsureSS()
                                        e.cdStateLowerAlpha = pct / 100
                                        mod.CdStateWriteHide(e, "lowerAlphaOnCD")
                                        if mod.RefreshCDMIconAppearance then
                                            mod.RefreshCDMIconAppearance(barId)
                                        end
                                    end)
                                end)
                            end
                        end, {
                            itemState = AB.CdStateItemState(ss, function()
                                return (ss.procGlow and ss.procGlow > 0) and true or false
                            end),
                            onRefresh = function()
                                if (mod.CdStateGlowOf(ss) ~= nil) ~= hadGlow then
                                    dropMenu._rebuildPending = true
                                end
                            end,
                            apply = {
                                confirmRA = true,
                                keys = { "cdStateEffect", "cdStateLowerAlpha" },
                                write = AB.CdHideWrite(ss),
                                -- The strip's own-entry write: an explicit value (None =
                                -- false, the exclusion), keeping the glow the spell shows.
                                -- Lower Alpha asks for its percent first, as a click on
                                -- its row does.
                                writeOwn = function(v)
                                    if v == "lowerAlphaOnCD" then
                                        local current =
                                            math.floor(((ss.cdStateLowerAlpha or 0.5) * 100) + 0.5)
                                        dropMenu:Hide()
                                        ShowAlphaPopup(current, function(pct)
                                            local e = EnsureSS()
                                            e.cdStateLowerAlpha = pct / 100
                                            mod.CdStateWriteHide(e, "lowerAlphaOnCD")
                                            if mod.RefreshCDMIconAppearance then
                                                mod.RefreshCDMIconAppearance(barId)
                                            end
                                        end)
                                        return
                                    end
                                    local e = EnsureSS()
                                    mod.CdStateWriteHide(e, v or false)
                                    e.cdStateLowerAlpha = nil
                                end,
                                view = mod.CdStateHideOf,
                            },
                        })
                        dropMenu._cseRow = cdStateRow
                        AB.DimForCustom(cdStateRow)

                        -- 4b. Glow Style: the style the CD Ready and On CD glows use, shown only
                        -- while a glow is picked in Cooldown State Effect.
                        if not isCustomInjected and hadGlow then
                            MakeSubnavRow("Glow Style", CD_READY_STYLE_ITEMS, function()
                                return mod.CdReadyGlowStyle(mod.CdStateGlowOf(ss), ss)
                            end, function(v)
                                EnsureSS()
                                SetOwn("cdStateGlowStyle", v)
                                if mod.RefreshCDMIconAppearance then
                                    mod.RefreshCDMIconAppearance(barId)
                                end
                            end, function()
                                return ss.cdStateGlowStyle == nil
                            end, function(si, item, sub)
                                -- Blackout: clicking prompts for the opacity percent, then
                                -- selects this style (mirrors Lower Alpha's onClick above).
                                if item.val == 8 then
                                    item.dynamicLabel = function()
                                        local base = CludesUI.L(mod.GLOW_STYLES[8].name)
                                        if mod.CdReadyGlowStyle(mod.CdStateGlowOf(ss), ss) == 8 then
                                            local pct = math.floor(((ss.cdStateGlowAlpha or 1) * 100) + 0.5)
                                            return pct .. "% " .. base
                                        end
                                        return base
                                    end
                                    si:SetScript("OnClick", function()
                                        local current = math.floor(((ss.cdStateGlowAlpha or 1) * 100) + 0.5)
                                        dropMenu:Hide()
                                        ShowAlphaPopup(
                                            current,
                                            function(pct)
                                                EnsureSS()
                                                ss.cdStateGlowAlpha = pct / 100
                                                SetOwn("cdStateGlowStyle", 8)
                                                if mod.RefreshCDMIconAppearance then
                                                    mod.RefreshCDMIconAppearance(barId)
                                                end
                                            end,
                                            CludesUI.L("Glow Opacity"),
                                            CludesUI.L("Blackout glow opacity (1-100%)")
                                        )
                                    end)
                                end
                            end, {
                                apply = {
                                    keys = { "cdStateGlowStyle", "cdStateGlowAlpha" },
                                    -- The Blackout opacity rides along with the Blackout value
                                    -- only: a spell that set its own opacity pushes it to the bar
                                    -- instead of rejoining the bar's (see payloadValue).
                                    payload = function(item)
                                        return item.val == 8
                                    end,
                                    write = function(t, v)
                                        t.cdStateGlowStyle = v
                                        t.cdStateGlowAlpha = (v == 8) and ss.cdStateGlowAlpha or nil
                                    end,
                                },
                            })
                        end

                        -- 4a. Threshold Text: decimals/color change on this spell's countdowns
                        -- (cooldown, recharge and active state) below its Threshold Seconds. Engine countdown formatter -- see ns.ApplyThresholdFormatter; zero cost until armed.
                        do
                            local acc = {}
                            acc.get = function(k)
                                return ss[k]
                            end
                            acc.set = function(k, v)
                                EnsureSS()
                                ss[k] = v
                            end
                            acc.clear = function(k)
                                EnsureSS()
                                SetOwn(k, nil)
                            end
                            acc.refresh = function()
                                if (tonumber(ss.thresholdSeconds) or 0) > 0 then
                                    mod._cdmAnyThresholdText = true
                                end
                                if mod.RefreshCDMIconAppearance then
                                    mod.RefreshCDMIconAppearance(barId)
                                end
                                if mod.QueueReanchor then
                                    mod.QueueReanchor()
                                end
                            end
                            AddThresholdTextRow(acc)
                        end

                        -- 4b. Cooldown Swipe (per-spell): Reverse Swipe flips the swipe direction;
                        -- Hide CD Swipe removes it. Default off. Runtime apply + zero-cost gates live in RefreshCDMIconAppearance/RescanReverseSwipeFlag and the SetDrawSwipe hook.
                        MakeSubnavRow(
                            "Cooldown Swipe",
                            CD_SWIPE_ITEMS,
                            function()
                                if ss.hideCDSwipe then
                                    return "hide"
                                end
                                if ss.reverseSwipe then
                                    return "reverse"
                                end
                                return nil
                            end,
                            function(v)
                                EnsureSS()
                                SetOwn("reverseSwipe", (v == "reverse") or nil)
                                SetOwn("hideCDSwipe", (v == "hide") or nil)
                                if ss.reverseSwipe then
                                    mod._cdmAnyReverseSwipe = true
                                end
                                if ss.hideCDSwipe then
                                    mod._cdmAnyHideCDSwipe = true
                                end
                                if mod.RefreshCDMIconAppearance then
                                    mod.RefreshCDMIconAppearance(barId)
                                end
                            end,
                            function()
                                return ss.reverseSwipe == nil and ss.hideCDSwipe == nil
                            end,
                            nil,
                            {
                                apply = {
                                    keys = { "reverseSwipe", "hideCDSwipe" },
                                    write = function(t, v)
                                        -- "Off" applied bar-wide blocks the tier below.
                                        t.reverseSwipe = (v == "reverse") or false
                                        t.hideCDSwipe = (v == "hide") or false
                                    end,
                                },
                            }
                        )

                        -- 4b2. Stance Bar (per-spell, classes with stance bar pages): hidden in or
                        -- outside one of the class's paging stances, for keys that cast something
                        -- else on that page. Runtime in CludesUICdmStanceBar.lua, gated by
                        -- ns._cdmAnyStanceBar.
                        if AB.STANCE_BAR_ITEMS then
                            MakeSubnavRow(
                                "Stance Bar",
                                AB.STANCE_BAR_ITEMS,
                                function()
                                    return ss.stanceBarHide or nil
                                end,
                                function(v)
                                    EnsureSS()
                                    SetOwn("stanceBarHide", v)
                                    if v then
                                        mod._cdmAnyStanceBar = true
                                    end
                                    if mod.RefreshCDMIconAppearance then
                                        mod.RefreshCDMIconAppearance(barId)
                                    end
                                end,
                                function()
                                    return not ss.stanceBarHide
                                end,
                                nil,
                                {
                                    apply = {
                                        keys = { "stanceBarHide" },
                                        write = function(t, v)
                                            t.stanceBarHide = v or false
                                            if v then
                                                mod._cdmAnyStanceBar = true
                                            end
                                        end,
                                    },
                                }
                            )
                        end

                        -- 4c. Audio Effect on CD Ready (cd/utility per-icon): play a sound the moment
                        -- the spell's real cooldown finishes. Same sound list + speaker preview as the
                        -- buff Audio rows/Focus Cast Sound (shared ns.FOCUSKICK_SOUND_* tables); stored
                        -- as ss.cdReadySoundKey ("none"/nil = silent). The per-frame SetDesaturated edge hook (gated by ns._cdmAnyCdReadySound) fires it on the on-CD -> ready edge.
                        local CDR_AUDIO_ITEMS = SoundItems()
                        local cdReadySoundRow = MakeSubnavRow(
                            "Audio Effect on CD Ready",
                            CDR_AUDIO_ITEMS,
                            function()
                                return ss.cdReadySoundKey or "none"
                            end,
                            function(v)
                                EnsureSS()
                                SetOwn("cdReadySoundKey", (v ~= "none" and v) or nil)
                                -- Flip the 0-cost gate live so the edge hook starts evaluating on the next
                                -- desaturation tick, and refresh so a CHARGE spell registers on the SPELL_UPDATE_CHARGES watcher immediately.
                                if ss.cdReadySoundKey then
                                    mod._cdmAnyCdReadySound = true
                                end
                                if mod.RefreshCDMIconAppearance then
                                    mod.RefreshCDMIconAppearance(barId)
                                end
                            end,
                            function()
                                return ss.cdReadySoundKey == nil
                            end,
                            AddSoundPreviewButton,
                            {
                                searchable = true,
                                apply = {
                                    keys = { "cdReadySoundKey" },
                                    write = function(t, v)
                                        -- "None" applied bar-wide = explicitly silent.
                                        t.cdReadySoundKey = (v ~= "none" and v) or false
                                    end,
                                },
                            }
                        )
                        -- Custom-injected spells drive their cd-state through the Fake-Active engine,
                        -- not the SetDesaturated/GetSpellCooldown edge this sound rides, so dim the row for them (same as Cooldown State Effect above).
                        AB.DimForCustom(cdReadySoundRow)

                        -- 5. Glow Effect Color (unified color for all glow types)
                        local GLOW_COLOR_ITEMS = {
                            { val = nil, label = "Default" },
                            { val = "class", label = "Class Color" },
                            { val = "custom", label = "Custom" },
                        }
                        local glowColorRow = MakeSubnavRow(
                            "Glow Effect Color",
                            GLOW_COLOR_ITEMS,
                            function()
                                if ss.glowColor == "class" then
                                    return "class"
                                end
                                if ss.glowColor == "custom" then
                                    return "custom"
                                end
                                return nil
                            end,
                            function(v)
                                EnsureSS()
                                SetOwn("glowColor", v)
                                if v == "custom" and not ss.glowColorR then
                                    ss.glowColorR = 1
                                    ss.glowColorG = 0.788
                                    ss.glowColorB = 0.137
                                end
                                if mod.RefreshCDMIconAppearance then
                                    mod.RefreshCDMIconAppearance(barId)
                                end
                            end,
                            function()
                                return ss.glowColor == nil
                            end,
                            AB.CustomColorSwatch("glowColor", 0.788, 0.137),
                            AB.CustomColorApply("glowColor", 0.788, 0.137)
                        )
                    end -- not isCustomInjected
                end -- isBuffBar per-icon rows

                -- (The per-setting "Apply to Bar / (All Specs)" strip superseded
                -- "Sync All Bar Buttons"; cdm_spell_settings_tiers_v1 migrated it.)

                -- Replace with Buff (cd/util family, real spells only; per-spell ONLY like
                -- Custom Icon -- a slot identity choice, no tiers, no apply strip). Picks a
                -- tracked buff whose viewer frame takes this cooldown's slot while the aura
                -- is active; the cooldown returns when it ends. Closes the menu (popup flow).
                if
                    not isBuffBar
                    and not isHostedBuff
                    and not (edge and edge.isGhostBar)
                    and type(spellId) == "number"
                    and spellId > 0
                    and not (
                        (mod._myRacialsSet and mod._myRacialsSet[spellId])
                        or (sd.customSpellIDs and sd.customSpellIDs[spellId])
                    )
                then
                    local repSID = rawget(ss, "replaceBuffID")
                    local repName = repSID and C_Spell.GetSpellName(repSID)
                    local rbRow
                    rbRow = PlainMenuRow(
                        dropMenu,
                        inner,
                        mH,
                        ITEM_H,
                        CludesUI.L("Replace with Buff") .. ": " .. (repName or CludesUI.L("None")),
                        { FONT_PATH, 11, GetCDMOptOutline() },
                        { tDimR, tDimG, tDimB, tDimA },
                        hlA,
                        function()
                            CludesUI.HideWidgetTooltip()
                            dropMenu:Hide()
                            ShowBuffToCDPicker(rbRow, barId, nil, function(buffSID, buffCdID)
                                if mod.SetCooldownBuffReplacement then
                                    mod.SetCooldownBuffReplacement(barId, spellId, buffSID, buffCdID)
                                end
                                RefreshCDPreview()
                            end)
                        end,
                        {
                            keepSub = true,
                            fit = true,
                            tip = CludesUI.L("Show a tracked buff in this slot while it is active."),
                        }
                    )
                    mH = mH + ITEM_H
                end

                -- Talent Conditions (cd/util family, real spells only; per-spell ONLY like
                -- Replace with Buff -- no tiers, no apply strip). The icon shows only while
                -- every picked condition holds (CludesUICdmTalentConditions.lua); the
                -- tree popup lives in CUI_CooldownManager_TalentConditions.lua (on WoW Forever,
                -- the three vanilla trees). Closes the menu (popup flow).
                if
                    not isBuffBar
                    and not isHostedBuff
                    and not (edge and edge.isGhostBar)
                    and type(spellId) == "number"
                    and spellId > 0
                    and not (
                        (mod._myRacialsSet and mod._myRacialsSet[spellId])
                        or (sd.customSpellIDs and sd.customSpellIDs[spellId])
                    )
                then
                    AddTalentConditionsRow(spellId, ss, EnsureSS)
                end

                -- Custom Icon (per-spell ONLY -- deliberately outside the Apply-to-Bar
                -- tiers: an icon replacement is a per-slot identity choice, so no tiers, no
                -- apply strip, no false-blocking; a plain nil write removes it). The render
                -- side re-stamps after every Blizzard icon repaint against the frame's full
                -- identity set, so it follows every transform. At the COMMON rejoin point
                -- (both families); skipped for preset/item entries (negative ids -- their settings live in customActiveStates, which nothing reads customIcon from). Popup flow closes the menu, matching Lower Alpha.
                if not (type(spellId) == "number" and spellId < 0) then
                    local hasCI = type(rawget(ss, "customIcon")) == "number"
                    PlainMenuRow(
                        dropMenu,
                        inner,
                        mH,
                        ITEM_H,
                        CludesUI.L(hasCI and "Edit Custom Icon" or "Add Custom Icon"),
                        { FONT_PATH, 11, GetCDMOptOutline() },
                        { tDimR, tDimG, tDimB, tDimA },
                        hlA,
                        function()
                            -- Close the per-spell dropdown so only the popup shows.
                            dropMenu:Hide()
                            mod.ShowCDMCustomIconPopup(rawget(ss, "customIcon"), function(ident)
                                EnsureSS()
                                ss.customIcon = ident
                                if ident then
                                    -- Live-arm the session gate (monotonic; the login rescan covers already-saved settings).
                                    mod._cdmAnyCustomIcon = true
                                end
                                -- Stamp/restore on every claimed frame now: DecorateFrame runs from
                                -- the reanchor pass (the only re-style path for the default Essential/Utility bars).
                                if mod.QueueReanchor then
                                    mod.QueueReanchor()
                                end
                                -- Aura-tracked custom buffs render in an engine container the
                                -- reanchor never reaches; their sync pass rebuilds it when the
                                -- icon changes (a signature no-op for every other bar).
                                if mod.UpdateCustomBuffAuraTracking then
                                    mod.UpdateCustomBuffAuraTracking()
                                end
                            end)
                        end
                    )
                    mH = mH + ITEM_H
                end

                -- Copy to Other Specs (user Custom Spell/Buff IDs only, gated on the
                -- customSpellIDs tag -- racials/trinkets/presets never show it). At the
                -- COMMON rejoin point so it appears for custom IDs on any bar type. One-time
                -- copy of the spell + its per-spell settings onto the SAME bar in the picked specs; specs that already have it anywhere are skipped.
                if sd.customSpellIDs and sd.customSpellIDs[spellId] then
                    -- Label flips to Remove once the spell lives on other specs.
                    local otherSpecs = (mod.SpecsWithCustomSpell and mod.SpecsWithCustomSpell(spellId)) or {}
                    local isRemove = next(otherSpecs) ~= nil
                    PlainMenuRow(
                        dropMenu,
                        inner,
                        mH,
                        ITEM_H,
                        CludesUI.L(isRemove and "Remove from Other Specs" or "Copy to Other Specs"),
                        { FONT_PATH, 11, GetCDMOptOutline() },
                        { tDimR, tDimG, tDimB, tDimA },
                        hlA,
                        function()
                            dropMenu:Hide()
                            local specs = (mod.GetCDMSpecInfo and mod.GetCDMSpecInfo()) or {}
                            local curKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
                            if isRemove then
                                -- Remove picker: only specs that HAVE the spell are pre-checked +
                                -- selectable; the rest (and current) are disabled. Confirm removes from the checked specs.
                                local disabled = {}
                                for _, s in ipairs(specs) do
                                    s.checked = otherSpecs[s.key] and true or false
                                    if s.key == curKey then
                                        disabled[s.key] = "You're on this spec."
                                    elseif not otherSpecs[s.key] then
                                        disabled[s.key] = "This spec doesn't have this spell."
                                    end
                                end
                                CludesUI:ShowCDMSpecPickerPopup({
                                    title = "Remove from Other Specs",
                                    subtitle = "Uncheck a spec to keep it. Confirm removes this custom spell and its settings from the checked specs.",
                                    confirmText = "Remove",
                                    specs = specs,
                                    disabledSpecs = disabled,
                                    foreverAllKeys = true,
                                    foreverActiveKey = curKey,
                                    onConfirm = function(selectedSpecs)
                                        if mod.RemoveCustomSpellFromSpecs then
                                            mod.RemoveCustomSpellFromSpecs(spellId, selectedSpecs)
                                        end
                                    end,
                                })
                            else
                                local disabled
                                if curKey then
                                    disabled = { [curKey] = "You're on this spec." }
                                end
                                CludesUI:ShowCDMSpecPickerPopup({
                                    title = "Copy to Other Specs",
                                    subtitle = "Copies this custom spell and its settings to the same bar on the specs you pick. Specs that already have it are skipped.",
                                    confirmText = "Copy",
                                    specs = specs,
                                    disabledSpecs = disabled,
                                    foreverActiveKey = curKey,
                                    onConfirm = function(selectedSpecs)
                                        if mod.CopyCustomSpellToSpecs then
                                            mod.CopyCustomSpellToSpecs(barId, spellId, selectedSpecs)
                                        end
                                    end,
                                })
                            end
                        end
                    )
                    mH = mH + ITEM_H
                end
            end
        end

        -- Size and show
        inner:SetHeight(mH + 4)
        dropMenu:SetSize(menuW, mH + 4)
        dropMenu:ClearAllPoints()
        dropMenu:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
        dropMenu._anchorFrame = anchor
        dropMenu._anchorGen = PoolGen(anchor)
        optionState._spellPickerMenu = dropMenu
        dropMenu._openSub = nil -- track open subnav for close checks
        dropMenu:SetScript("OnUpdate", function(m)
            -- A glow picked or cleared in Cooldown State Effect adds or drops the
            -- Glow Style row: rebuild the menu here, outside the click that asked
            -- for it, and reopen the Cooldown State Effect flyout where it was.
            if m._rebuildPending then
                m._rebuildPending = nil
                m:Hide()
                ShowSpellPicker(anchor, barId, slotIndex, excludeSet, onSelect, removeOnly)
                local r = m._cseRow
                if m:IsShown() and r and r._showSub then
                    r._showSub()
                end
                return
            end
            local overMenu = m:IsMouseOver() or anchor:IsMouseOver()
            -- A cog flyout (Duration/Charge-Stack) drives itself through this menu, so also
            -- treat "mouse over the flyout's open dropdown menu" as over-the-sub. Without this, picking a Position option whose list extends below the flyout reads as an outside click and closes the whole menu.
            local sub = m._openSub
            local overSub = sub
                and sub:IsShown()
                and (sub:IsMouseOver() or (sub._anyDropdownHovered and sub._anyDropdownHovered()))
            -- "Apply to Bar" strip: same lifecycle as a subnav flyout -- it never hides on
            -- hover-out (that made the 2px gap unreachable). It dies with its owner item: flyout closed, rebuilt, or the items reparented away (IsVisible sees through a hidden parent; IsShown would not).
            local strip = m._applyStrip
            local overStrip = strip and strip:IsShown() and strip:IsMouseOver()
            if strip and strip:IsShown() then
                local ownerFrame = strip._ownerItem
                if not (ownerFrame and ownerFrame:IsVisible()) then
                    strip:Hide()
                end
            end
            -- Keep the menu open while the shared color picker is up: it's a separate popup, so interacting with it must not dismiss the menu (and its cog/subnav flyout).
            local cp = CludesUI._colorPickerPopup
            local cpOpen = cp and cp:IsShown()
            if
                not overMenu
                and not overSub
                and not overStrip
                and not cpOpen
                and IsMouseButtonDown("LeftButton")
            then
                m:Hide()
            end
        end)
        dropMenu:SetScript("OnHide", function(m)
            m:SetScript("OnUpdate", nil)
            if m._openSub and m._openSub:IsShown() then
                m._openSub:Hide()
            end
            if m._applyStrip then
                m._applyStrip:Hide()
            end
        end)
        dropMenu:Show()
        return
    end

    -- Divider after Remove Spell (only in full picker mode)
    if slotIndex then
        local div = inner:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetColorTexture(1, 1, 1, 0.10)
        div:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        div:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9
    end

    -- The picker's own entries (hovering one leaves an open flyout alone).
    local function PickerRow(text, onClick)
        local row = PlainMenuRow(
            dropMenu,
            inner,
            mH,
            ITEM_H,
            CludesUI.L(text),
            { FONT_PATH, 11, GetCDMOptOutline() },
            { tDimR, tDimG, tDimB, tDimA },
            hlA,
            function()
                dropMenu:Hide()
                onClick()
            end,
            { keepSub = true }
        )
        allItems[#allItems + 1] = row
        mH = mH + ITEM_H
    end

    -- "Custom Spell ID": CD/utility and custom_buff bars (regular buff bars list
    -- only Blizzard CDM spells). Only this caller offers Show Charges (CD/utility).
    if not isBuffBar then
        PickerRow("Custom Spell ID", function()
            mod.CDMO_ShowCustomSpellIDPopup(edge and edge.key, function(spellRef)
                if mod.UpdateCustomBuffAuraTracking then
                    mod.UpdateCustomBuffAuraTracking()
                end
                if onSelect then
                    onSelect(spellRef, true)
                end
            end, not isCustomBuff)
        end)
    end

    -- CD/utility bars only (custom aura bars are cast-timer driven and draw no
    -- item cooldowns): "Custom Item ID" (an item by ID, stored as -itemID),
    -- "Equipment Slot" (whatever is equipped there, stored as -slotID, the
    -- trinket-slot encoding: covers enchant / tinker use effects such as Nitro
    -- Boosts on any belt) and "Empty Slot" (a placeholder holding a grid spot; each
    -- add mints a fresh marker, so several can sit on one bar, moved and removed
    -- like any entry).
    if not isBuffBar and not isCustomBuff then
        local function Added(marker)
            if onSelect then
                onSelect(marker, true)
            end
        end
        PickerRow("Custom Item ID", function()
            ShowCustomItemIDPopup(edge and edge.key, function(marker)
                mod._cdmAnyCustomItem = true
                Added(marker)
            end)
        end)
        PickerRow("Equipment Slot", function()
            ShowEquipmentSlotPopup(edge and edge.key, Added)
        end)
        PickerRow("Empty Slot", function()
            EnsureAssignedSpells(barId)
            mod.AddTrackedSpell(barId, mod.NewEmptySlotMarker())
            RefreshCDPreview()
        end)
    end

    if not isBuffBar and not isCustomBuff then
        -- Divider below Custom Spell ID (CD/utility bars only -- custom buff bars have their own divider before presets)
        local csDiv = inner:CreateTexture(nil, "ARTWORK")
        csDiv:SetHeight(1)
        csDiv:SetColorTexture(1, 1, 1, 0.10)
        csDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        csDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9
    end

    -- Trinket slots + potion presets for CD/utility bars only (not buff bars, not custom buff bars)
    if not isBuffBar and not isCustomBuff then
        -- Build already-tracked set (this bar + other bars)
        local alreadyOnBar = {}
        local usedOnOtherBar = {} -- [sid] = barName
        local sdTrk = edge and mod.GetBarSpellData(edge.key)
        if sdTrk and sdTrk.assignedSpells then
            for _, spellRef in ipairs(sdTrk.assignedSpells) do
                alreadyOnBar[spellRef] = true
            end
        end
        -- Check all other non-buff bars for cross-bar duplicate detection
        local prof = mod.ECME and mod.ECME.db and mod.ECME.db.profile
        if prof and prof.cdmBars and prof.cdmBars.bars then
            for _, otherBar in ipairs(prof.cdmBars.bars) do
                if otherBar.key ~= barId then
                    local otherType = otherBar.barType or otherBar.key
                    if otherType ~= "buffs" then
                        local osd = mod.GetBarSpellData(otherBar.key)
                        if osd and osd.assignedSpells then
                            for _, spellRef in ipairs(osd.assignedSpells) do
                                if spellRef and spellRef ~= 0 and not usedOnOtherBar[spellRef] then
                                    usedOnOtherBar[spellRef] = otherBar.name or otherBar.key
                                end
                            end
                        end
                    end
                end
            end
        end

        -- The presets: greyed only while on THIS bar; one on another bar stays
        -- claimable (AddTrackedSpell moves it, as it does a regular spell).
        local thisBar = edge and (edge.name or edge.key) or barId
        local function Preset(text, texture, id)
            allItems[#allItems + 1] = PresetMenuRow(
                dropMenu,
                inner,
                mH,
                ITEM_H,
                text,
                texture,
                alreadyOnBar[id] and thisBar or nil,
                { FONT_PATH, 11, GetCDMOptOutline() },
                { tDimR, tDimG, tDimB, tDimA },
                hlA,
                function()
                    dropMenu:Hide()
                    EnsureAssignedSpells(barId)
                    mod.AddTrackedSpell(barId, id)
                    RefreshCDPreview()
                end
            )
            mH = mH + ITEM_H
        end
        -- Trinket Slot 1 & 2 (stored as -slot).
        for _, slot in ipairs({ 13, 14 }) do
            local itemId = GetInventoryItemID("player", slot)
            Preset(
                CludesUI.L((slot == 13) and "Trinket Slot 1" or "Trinket Slot 2"),
                itemId and C_Item.GetItemIconByID(itemId),
                -slot
            )
        end
        -- Racial: one generic entry following the character's race. It adds this
        -- character's active racial; ns.NormalizeRacialAssignments rewrites it on
        -- every other race, so a shared profile needs the racial added only once.
        local racial = mod._activeRacialSpellID
        if racial then
            Preset(CludesUI.L("Racial"), C_Spell.GetSpellTexture(racial), racial)
        end
        -- WoW Forever Paladins: Seals, the stand-in for Blizzard's Seals entry
        -- (CUI_CDM_ForeverSeals.lua), named by the client's own spell name.
        local seals = mod.CDM_SEALS_SPELL
        local sealsName = seals and C_Spell.GetSpellName(seals)
        if sealsName then
            Preset(sealsName, C_Spell.GetSpellTexture(seals), seals)
        end

        -- "Potions & Healthstone" flyout subnav
        local _potionsSub
        dropMenu._potionsSub = nil -- reference for OnUpdate close-check
        local itemPresets = mod.CDM_ITEM_PRESETS
        if itemPresets and #itemPresets > 0 then
            local potItem = CreateFrame("Button", nil, inner)
            potItem:SetHeight(ITEM_H)
            potItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            potItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            potItem:SetFrameLevel(dropMenu:GetFrameLevel() + 2)

            local potHl = potItem:CreateTexture(nil, "ARTWORK")
            potHl:SetAllPoints()
            potHl:SetColorTexture(1, 1, 1, 0)
            potHl:SetAlpha(0)

            local potLbl = potItem:CreateFontString(nil, "OVERLAY")
            potLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            potLbl:SetPoint("LEFT", 10, 0)
            potLbl:SetJustifyH("LEFT")
            potLbl:SetText(CludesUI.L("Potions & Healthstone"))
            potLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)

            local potArrow = potItem:CreateTexture(nil, "ARTWORK")
            potArrow:SetSize(10, 10)
            potArrow:SetPoint("RIGHT", potItem, "RIGHT", -8, 0)
            potArrow:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\right-arrow.png")
            potArrow:SetAlpha(0.7)

            local function ShowPotionsSub()
                -- Built once per picker: the presets and their on-bar states do not
                -- change while it is open, so a later hover shows the same flyout.
                if _potionsSub then
                    if not _potionsSub:IsShown() then
                        _potionsSub:Show()
                    end
                    return
                end
                _potionsSub = CreateFrame("Frame", nil, dropMenu)
                dropMenu._potionsSub = _potionsSub
                _potionsSub:SetFrameStrata("FULLSCREEN_DIALOG")
                _potionsSub:SetFrameLevel(dropMenu:GetFrameLevel() + 5)
                _potionsSub:SetClampedToScreen(true)
                _potionsSub:EnableMouse(true)

                local subW = 220
                local SUB_ITEM_H = 26
                -- Captions collected as the rows are built so the frame can be
                -- widened to the longest preset name instead of ellipsising it.
                local subLabels = {}
                _potionsSub:SetSize(subW, 10)
                _potionsSub:ClearAllPoints()
                _potionsSub:SetPoint("TOPLEFT", potItem, "TOPRIGHT", 2, 0)

                local subBg = _potionsSub:CreateTexture(nil, "BACKGROUND")
                subBg:SetAllPoints()
                subBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
                CludesUI.MakeRoundedBorder(_potionsSub, 1, 1, 1, mBrdA, subBg, nil, true)

                local subInner = CreateFrame("Frame", nil, _potionsSub)
                subInner:SetWidth(subW)
                subInner:SetPoint("TOPLEFT")

                local subH = 4
                local nativeOnly = sdTrk and sdTrk.nativeItems
                for _, preset in ipairs(itemPresets) do
                    -- The two legacy combat potion entries resolve bars saved with
                    -- their keys but are not offered: Combat Potion is the one entry.
                    if not preset.legacy then
                        local pID = -preset.itemID
                        -- Combat Potion counts as on this bar under any of its family keys.
                        -- An entry the reseed listed for Blizzard's own row of the item
                        -- (nativeItems) is not the preset's yet: the pick adopts it.
                        local famKeys = preset.potFamily
                                and mod.CDM_NATIVE_ITEM_KEYS
                                and mod.CDM_NATIVE_ITEM_KEYS[preset.nativeCategory]
                            or nil
                        local isAdded = false
                        if famKeys then
                            for _, k in ipairs(famKeys) do
                                if alreadyOnBar[k] and not (nativeOnly and nativeOnly[k]) then
                                    isAdded = true
                                    break
                                end
                            end
                            if not isAdded then
                                -- Its own key here (to adopt), else the family key another
                                -- bar lists (the add moves it, as any preset auto-moves).
                                for _, k in ipairs(famKeys) do
                                    if alreadyOnBar[k] or usedOnOtherBar[k] then
                                        pID = k
                                        break
                                    end
                                end
                            end
                        else
                            isAdded = alreadyOnBar[pID] and not (nativeOnly and nativeOnly[pID]) or false
                        end
                        -- Greyed only while on THIS bar (another bar's stays claimable).
                        local _, label = IconMenuRow(
                            subInner,
                            _potionsSub,
                            subH,
                            SUB_ITEM_H,
                            CludesUI.L(preset.name),
                            CludesUI.ClientIcon(
                                preset.icon or (preset.itemID and C_Item.GetItemIconByID(preset.itemID))
                            ),
                            isAdded,
                            edge and (edge.name or edge.key) or barId,
                            { FONT_PATH, 11, GetCDMOptOutline() },
                            { tDimR, tDimG, tDimB, tDimA },
                            hlA,
                            function()
                                _potionsSub:Hide()
                                dropMenu:Hide()
                                EnsureAssignedSpells(barId)
                                -- Already listed for Blizzard's own row: the entry becomes
                                -- the preset's (the add refuses a key the bar holds).
                                if not mod.AddTrackedSpell(barId, pID) then
                                    mod.AdoptNativeItemEntry(barId, pID)
                                end
                                RefreshCDPreview()
                            end,
                            true
                        )
                        subLabels[#subLabels + 1] = label
                        subH = subH + SUB_ITEM_H
                    end -- not preset.legacy
                end

                -- Widen to the longest preset name (pad leaves room for the text
                -- inset and the row's right-hand item icon).
                subW = FitMenuWidth(subLabels, subW, 48)
                _potionsSub:SetWidth(subW)
                subInner:SetWidth(subW)
                local totalSubH = subH + 4
                subInner:SetHeight(totalSubH)
                _potionsSub:SetHeight(totalSubH)
                subInner:SetParent(_potionsSub)
                subInner:SetPoint("TOPLEFT")
                _potionsSub:Show()
            end

            potItem:SetScript("OnEnter", function()
                potLbl:SetTextColor(1, 1, 1, 1)
                potHl:SetColorTexture(1, 1, 1, hlA)
                potHl:SetAlpha(1)
                ShowPotionsSub()
            end)
            potItem:SetScript("OnLeave", function()
                potLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                potHl:SetAlpha(0)
                -- Stands down once the menu was dressed again for another open:
                -- this flyout and its row belong to the dress that left them.
                local menuGen = PoolGen(dropMenu)
                C_Timer.After(0.3, function()
                    if PoolGen(dropMenu) ~= menuGen then
                        return
                    end
                    if
                        _potionsSub
                        and _potionsSub:IsShown()
                        and not _potionsSub:IsMouseOver()
                        and not potItem:IsMouseOver()
                    then
                        _potionsSub:Hide()
                    end
                end)
            end)

            allItems[#allItems + 1] = potItem
            mH = mH + ITEM_H
        end

        -- Divider after trinkets/potions
        local trDiv = inner:CreateTexture(nil, "ARTWORK")
        trDiv:SetHeight(1)
        trDiv:SetColorTexture(1, 1, 1, 0.10)
        trDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        trDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9
    end

    -- Presets (Heroism, potions, etc.) -- flat list in custom buff bar picker.
    -- Skipped with its divider when the list is empty (WoW Forever has none).
    if isCustomBuff and #mod.BUFF_BAR_PRESETS > 0 then
        -- Divider before presets
        local psDiv = inner:CreateTexture(nil, "ARTWORK")
        psDiv:SetHeight(1)
        psDiv:SetColorTexture(1, 1, 1, 0.10)
        psDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        psDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9

        local _, _pClass = UnitClass("player")
        for _, preset in ipairs(mod.BUFF_BAR_PRESETS) do
            -- tbbOnly presets are excluded here UNLESS they opt in via
            -- customAuraToo (debuff-driven Bloodlust: rendered as a 40s
            -- self-timed icon, armed off the Sated edge instead of a cast).
            if
                (not preset.class or preset.class == _pClass)
                and (not preset.tbbOnly or preset.customAuraToo)
            then
                -- Greyed with no tip while already on the bar.
                allItems[#allItems + 1] = IconMenuRow(
                    inner,
                    dropMenu,
                    mH,
                    ITEM_H,
                    CludesUI.L(preset.name),
                    CludesUI.ClientIcon(preset.icon),
                    mod.IsPresetOnBar(barId, preset),
                    nil,
                    { FONT_PATH, 11, GetCDMOptOutline() },
                    { tDimR, tDimG, tDimB, tDimA },
                    hlA,
                    function()
                        dropMenu:Hide()
                        EnsureAssignedSpells(barId)
                        mod.AddPresetToBar(barId, preset)
                        -- Arm the shared Sated listener now (debuff-driven presets
                        -- like Bloodlust); no-op for cooldown presets.
                        if mod.UpdateLustListener then
                            mod.UpdateLustListener()
                        end
                        RefreshCDPreview()
                    end
                )
                mH = mH + ITEM_H
            end
        end
    end

    -- A spell of the list: its icon on the right and the label clipped before it.
    -- Greyed when disabled; greyed with a tip when already on THIS bar (another
    -- bar's spell is claimable: AddTrackedSpell moves it). An untalented spell
    -- stays pickable, desaturated with a hint, so a layout can be arranged without
    -- swapping talents. A pick keeps the picker open (several can go in a row) and
    -- greys its row in place; a spell of the wrong group for this bar type (a
    -- cooldown on a buff bar, or the reverse) says so instead.
    local function MakeItem(sp, isDisabled)
        local wrongGroup = not isDisabled
            and sp.cdmCatGroup
            and ((isBuffBar and sp.cdmCatGroup == "cooldown") or (not isBuffBar and sp.cdmCatGroup == "buff"))
        local item, label, ico, highlight = IconMenuRow(
            inner,
            dropMenu,
            mH,
            ITEM_H,
            CludesUI.L(sp.name),
            sp.icon,
            isDisabled,
            nil,
            { FONT_PATH, 11, GetCDMOptOutline() },
            { tDimR, tDimG, tDimB, tDimA },
            hlA
        )
        mH = mH + ITEM_H
        allItems[#allItems + 1] = item
        if isDisabled then
            return
        end
        local function MarkOnThisBar()
            label:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
            ico:SetDesaturated(true)
            ico:SetAlpha(0.4)
            item:SetScript("OnClick", nil)
            item:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(
                    item,
                    CludesUI.Lf(
                        "This spell is already being used on %s",
                        CludesUI.L(edge and (edge.name or edge.key) or barId)
                    )
                )
                highlight:SetColorTexture(1, 1, 1, hlA * 0.3)
                highlight:SetAlpha(1)
            end)
            item:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
                highlight:SetAlpha(0)
            end)
        end
        if excludeSet and (excludeSet[sp.cdID] or excludeSet[sp.spellID]) then
            return MarkOnThisBar()
        end
        local notLearned = sp.isKnown == false
        if notLearned then
            ico:SetDesaturated(true)
            ico:SetAlpha(0.5)
        end
        item:SetScript("OnEnter", function()
            label:SetTextColor(1, 1, 1, 1)
            highlight:SetColorTexture(1, 1, 1, hlA)
            highlight:SetAlpha(1)
            if notLearned then
                CludesUI.ShowWidgetTooltip(item, CludesUI.L("Not currently talented"))
            end
        end)
        item:SetScript("OnLeave", function()
            label:SetTextColor(tDimR, tDimG, tDimB, tDimA)
            highlight:SetAlpha(0)
            if notLearned then
                CludesUI.HideWidgetTooltip()
            end
        end)
        item:SetScript("OnClick", function()
            if wrongGroup then
                dropMenu:Hide()
                ShowWrongBarTypePopup(sp.name, sp.cdmCatGroup == "buff")
                return
            end
            -- assignedSpells stores spell ids.
            if onSelect then
                onSelect(sp.spellID, sp.isExtra)
            end
            if notLearned then
                CludesUI.HideWidgetTooltip()
            end
            MarkOnThisBar()
        end)
    end

    local function MakeDivider()
        local div = inner:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetColorTexture(1, 1, 1, 0.10)
        div:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        div:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9
    end

    -- The spell list. Custom buff bars have none (their Custom Spell ID entry is
    -- above). CD / utility bars: the primary group, then the secondary (each
    -- unassigned first, then assigned), then the not tracked ones (unlearned or
    -- removed from Blizzard's CDM) by name, a divider between groups. Other bars:
    -- their spells, then the extras.
    if isCustomBuff then
        -- Nothing: the Custom Spell ID entry above is the list.
    elseif isCDorUtil then
        local groups = {
            { priUnassigned, priAssigned },
            { secUnassigned, secAssigned },
            { notTracked },
        }
        table.sort(notTracked, function(a, b)
            return (a.name or "") < (b.name or "")
        end)
        local started = false
        for _, group in ipairs(groups) do
            local any = false
            for _, list in ipairs(group) do
                any = any or #list > 0
            end
            if any then
                if started then
                    MakeDivider()
                end
                for _, list in ipairs(group) do
                    for _, sp in ipairs(list) do
                        MakeItem(sp, false)
                    end
                end
                started = true
            end
        end
    else
        for _, sp in ipairs(itemsDisplayed) do
            MakeItem(sp, false)
        end
        if #itemsDisplayed > 0 and #itemsExtra > 0 then
            MakeDivider()
        end
        for _, sp in ipairs(itemsExtra) do
            MakeItem(sp, false)
        end
    end

    -- "Missing Spells?": a centred accent prompt that opens Blizzard's CDM and
    -- closes the options (as the link under the buff bar preview does), for the
    -- bars that list Blizzard CDM spells.
    if not isCustomBuff then
        MakeDivider()
        local FOOTER_H = 38
        local footer = CreateFrame("Button", nil, inner)
        footer:SetHeight(FOOTER_H)
        footer:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        footer:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        footer:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
        local text = footer:CreateFontString(nil, "OVERLAY")
        text:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        text:SetAllPoints()
        text:SetJustifyH("CENTER")
        text:SetJustifyV("MIDDLE")
        local function Accented()
            local r, g, b = CludesUI.GetAccentColor()
            text:SetTextColor(r, g, b, 1)
        end
        Accented()
        text:SetText(CludesUI.L("Missing Spells?") .. "\n" .. CludesUI.L("Add in Blizzard CDM"))
        footer:SetScript("OnEnter", function()
            text:SetTextColor(1, 1, 1, 1)
        end)
        footer:SetScript("OnLeave", Accented)
        footer:SetScript("OnClick", function()
            dropMenu:Hide()
            if mod.OpenBlizzardCDMTab then
                mod.OpenBlizzardCDMTab(true)
            end
        end)
        allItems[#allItems + 1] = footer
        mH = mH + FOOTER_H
    end

    -- A tall list scrolls (smooth, no thumb) within MAX_H.
    local totalH = mH + 4
    inner:SetHeight(totalH)
    if totalH > MAX_H then
        dropMenu:SetHeight(MAX_H)
        local scroll = CreateFrame("ScrollFrame", nil, dropMenu)
        scroll:SetPoint("TOPLEFT", 0, -1)
        scroll:SetPoint("BOTTOMRIGHT", 0, 1)
        scroll:SetFrameLevel(dropMenu:GetFrameLevel() + 1)
        scroll:EnableMouseWheel(true)
        scroll:SetScrollChild(inner)
        inner:SetWidth(menuW)
        CludesUI.AttachSmoothScrollbar(scroll, { step = 40, thumb = false })
    else
        dropMenu:SetHeight(totalH)
        inner:SetParent(dropMenu)
        inner:SetPoint("TOPLEFT")
    end

    -- Under the anchor; a left press outside it, the anchor and the potions
    -- flyout closes it (without blocking the world underneath).
    dropMenu:ClearAllPoints()
    dropMenu:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
    dropMenu:SetScript("OnUpdate", function(m)
        local overSub = m._potionsSub and m._potionsSub:IsShown() and m._potionsSub:IsMouseOver()
        if
            not m:IsMouseOver()
            and not anchor:IsMouseOver()
            and not overSub
            and IsMouseButtonDown("LeftButton")
        then
            m:Hide()
        end
    end)
    -- Per-icon cog settings for racials, potions and trinkets are edited here;
    -- closing propagates them to synced specs.
    dropMenu:HookScript("OnHide", function(m)
        m:SetScript("OnUpdate", nil)
        if mod.MaybePropagateRPT then
            mod.MaybePropagateRPT()
        end
    end)

    dropMenu:Show()
    optionState._spellPickerMenu = dropMenu
    dropMenu._anchorFrame = anchor
    dropMenu._anchorGen = PoolGen(anchor)
end

-- Used by CUI_CooldownManager_Options.lua
mod.CDMO_ShowSpellPicker = ShowSpellPicker
