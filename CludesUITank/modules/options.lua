local addonName, ns = ...
if ns.standalone then return end
local K = ns.K

-- ── Color palette (deep blue dark theme) ───────────────────────────────────
local C = {
    bg        = {0.05, 0.07, 0.11, 0.97},
    titleBg   = {0.03, 0.04, 0.08, 1.00},
    tabBg     = {0.07, 0.10, 0.15, 1.00},
    tabActive = {0.09, 0.14, 0.22, 1.00},
    rule      = {0.15, 0.55, 0.95, 1.00},
    accent    = {0.35, 0.78, 1.00},
    border    = {0.14, 0.22, 0.34},
    btnBg     = {0.10, 0.15, 0.22},
    btnHover  = {0.18, 0.45, 0.80},
    btnDanger = {0.44, 0.10, 0.12},
    text      = {0.90, 0.92, 0.96},
    dim       = {0.40, 0.50, 0.62},
    ok        = {0.30, 0.80, 0.48},
    warn      = {0.95, 0.70, 0.12},
}

-- Note-type colours for preset spell list
local NOTE_CLR = {
    ["tank swap"]     = {1.00, 0.60, 0.15},
    ["tank debuff"]   = {0.35, 0.78, 1.00},
    ["tank physical"] = {0.85, 0.68, 0.40},
    ["tank dot"]      = {1.00, 0.35, 0.35},
    ["tank bleed"]    = {1.00, 0.40, 0.40},
    ["tank tether"]   = {0.75, 0.50, 1.00},
    ["tank marker"]   = {0.35, 1.00, 0.60},
    ["tank attack"]   = {0.85, 0.68, 0.40},
    ["tank target"]   = {0.35, 1.00, 0.60},
}

local PW   = 620
local PH   = 590
local TILE = "Interface\\Buttons\\WHITE8X8"

-- ── Low-level widget helpers ────────────────────────────────────────────────
local function PixelBorder(f, r, g, b)
    r, g, b = r or C.border[1], g or C.border[2], b or C.border[3]
    local t = f:CreateTexture(nil, "BORDER")
    t:SetColorTexture(r, g, b, 1)
    t:SetPoint("TOPLEFT",     f, "TOPLEFT",     -1,  1)
    t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  1, -1)
    t:SetDrawLayer("BORDER", -1)
end

local function Btn(parent, w, h, lbl, bgColor)
    bgColor = bgColor or C.btnBg
    local b  = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3]); b.bg = bg
    PixelBorder(b)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetAllPoints(); fs:SetJustifyH("CENTER"); fs:SetText(lbl or ""); b.label = fs
    b.SetText = function(_, t) if fs then fs:SetText(tostring(t or "")) end end
    b.GetText = function(_)   return fs:GetText() end
    b:SetScript("OnEnter", function() bg:SetColorTexture(C.btnHover[1], C.btnHover[2], C.btnHover[3]) end)
    b:SetScript("OnLeave", function() bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3]) end)
    return b
end

local function AccentBtn(parent, w, h, lbl)
    local b = Btn(parent, w, h, lbl)
    b.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    return b
end

local function DangerBtn(parent, w, h, lbl)
    local b = Btn(parent, w, h, lbl, C.btnDanger)
    b.label:SetTextColor(1, 0.48, 0.48)
    b:SetScript("OnEnter", function() b.bg:SetColorTexture(0.62, 0.14, 0.14) end)
    b:SetScript("OnLeave", function() b.bg:SetColorTexture(C.btnDanger[1], C.btnDanger[2], C.btnDanger[3]) end)
    return b
end

local function SecHdr(parent, label, y)
    local bar = parent:CreateTexture(nil, "ARTWORK")
    bar:SetHeight(1)
    bar:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    bar:SetColorTexture(C.rule[1], C.rule[2], C.rule[3], 1)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
    fs:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    fs:SetText(label)
    return fs, bar
end

local function Divider(parent, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    t:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.6)
    return t
end

local function EB(parent, w, h, numeric)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(w or 140, h or 26)
    eb:SetAutoFocus(false)
    eb:SetBackdrop({bgFile = TILE, edgeFile = TILE, edgeSize = 1})
    eb:SetBackdropColor(0.04, 0.06, 0.10, 1)
    eb:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    eb:SetFont("Fonts\\ARIALN.TTF", 11, "")
    eb:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    eb:SetTextInsets(6, 6, 2, 2)
    eb:SetMaxLetters(80)
    if numeric then eb:SetNumeric(true) end
    eb:SetScript("OnEscapePressed",   function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
    end)
    eb:SetScript("OnEditFocusLost",   function(self)
        self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    end)
    return eb
end

-- ── Dropdown helper ────────────────────────────────────────────────────────
local activeDropPopup = nil
local ddDismiss = CreateFrame("Frame", nil, UIParent)
ddDismiss:SetAllPoints(); ddDismiss:SetFrameStrata("FULLSCREEN"); ddDismiss:EnableMouse(true); ddDismiss:Hide()
ddDismiss:SetScript("OnMouseDown", function()
    if activeDropPopup then activeDropPopup:Hide(); activeDropPopup = nil end
    ddDismiss:Hide()
end)

local function MakeDropdown(parent, w, options, onSelect)
    local btn = Btn(parent, w, 26, "")
    btn.label:SetJustifyH("LEFT")
    btn.label:ClearAllPoints()
    btn.label:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btn.label:SetPoint("RIGHT", btn, "RIGHT", -16, 0)
    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    arrow:SetText("v"); arrow:SetTextColor(C.dim[1], C.dim[2], C.dim[3])

    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetFrameStrata("TOOLTIP"); popup:SetWidth(w)
    popup:SetBackdrop({bgFile = TILE, edgeFile = TILE, edgeSize = 1})
    popup:SetBackdropColor(0.06, 0.09, 0.14, 0.98)
    popup:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    popup:Hide()

    local optH = 24
    popup:SetHeight(#options * optH + 4)
    for i, opt in ipairs(options) do
        local ob = CreateFrame("Button", nil, popup)
        ob:SetSize(w - 2, optH)
        ob:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -(i - 1) * optH - 2)
        local obBg = ob:CreateTexture(nil, "BACKGROUND"); obBg:SetAllPoints()
        obBg:SetColorTexture(0, 0, 0, 0); ob.bg = obBg
        local obLbl = ob:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        obLbl:SetPoint("LEFT", ob, "LEFT", 8, 0)
        obLbl:SetText(opt.label); obLbl:SetTextColor(C.text[1], C.text[2], C.text[3])
        ob:SetScript("OnEnter", function() obBg:SetColorTexture(C.btnHover[1], C.btnHover[2], C.btnHover[3], 0.7) end)
        ob:SetScript("OnLeave", function() obBg:SetColorTexture(0, 0, 0, 0) end)
        ob:SetScript("OnClick", function()
            btn:SetText(opt.label)
            popup:Hide(); activeDropPopup = nil; ddDismiss:Hide()
            onSelect(opt)
        end)
    end

    btn:SetScript("OnClick", function()
        if activeDropPopup == popup then
            popup:Hide(); activeDropPopup = nil; ddDismiss:Hide(); return
        end
        if activeDropPopup then activeDropPopup:Hide() end
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        popup:Show(); activeDropPopup = popup; ddDismiss:Show()
    end)

    btn.SetSelected = function(_, label) btn:SetText(label or "") end
    btn._popup = popup
    return btn
end

-- Colour swatch that opens the game's colour picker. `key` is the saved
-- variable holding an {r, g, b} table; `onChange` re-applies the setting.
local function ColorSwatch(parent, size, key, onChange)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 18, size or 18)
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1)
    b.fill = fill
    PixelBorder(b)

    function b:Sync()
        fill:SetColorTexture(ns.FontColor(key))
    end
    b:Sync()

    b:SetScript("OnClick", function()
        local r, g, b2 = ns.FontColor(key)
        local function apply()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            ns.SetFontColor(key, nr, ng, nb)
            b:Sync()
            if onChange then onChange() end
        end
        local info = {
            r = r, g = g, b = b2,
            swatchFunc = apply,
            cancelFunc = function()
                ns.SetFontColor(key, r, g, b2)
                b:Sync()
                if onChange then onChange() end
            end,
            hasOpacity = false,
        }
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            ColorPickerFrame.func        = info.swatchFunc
            ColorPickerFrame.cancelFunc  = info.cancelFunc
            ColorPickerFrame.hasOpacity  = false
            ColorPickerFrame:SetColorRGB(r, g, b2)
            ColorPickerFrame:Show()
        end
    end)
    return b
end

-- ── Module state ───────────────────────────────────────────────────────────
local TABS = {
    {id = "general", label = "General"},
    {id = "alerts",  label = "Alerts"},
    {id = "tools",   label = "Tools"},
}
local tabPages  = {}
local activeTab = "general"
local optPanel  = nil

-- ── Tab switching ──────────────────────────────────────────────────────────
local function ShowTab(id)
    activeTab = id
    for _, def in ipairs(TABS) do
        local pg  = tabPages[def.id]
        local btn = optPanel and optPanel["_tab_" .. def.id]
        if pg then pg:SetShown(def.id == id) end
        if btn then
            if def.id == id then
                btn.bg:SetColorTexture(C.tabActive[1], C.tabActive[2], C.tabActive[3])
                btn.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
                btn.ul:Show()
            else
                btn.bg:SetColorTexture(C.tabBg[1], C.tabBg[2], C.tabBg[3])
                btn.label:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
                btn.ul:Hide()
            end
        end
    end
end

-- ── Status bar ─────────────────────────────────────────────────────────────
local function Status(msg, warn)
    if not optPanel then return end
    local c = warn and C.warn or C.ok
    optPanel._status:SetTextColor(c[1], c[2], c[3])
    optPanel._status:SetText(msg or "")
    if msg and msg ~= "" then
        C_Timer.After(5, function()
            if optPanel and optPanel._status:GetText() == msg then
                optPanel._status:SetText("")
            end
        end)
    end
end

-- ── Preset spell list (built once in BuildPanel) ───────────────────────────
-- Stores {toggleBtn, threshEB, spellId} for each preset row so SyncFromDB
-- can update them without re-creating frames.
local presetRefs = {}

local function BuildPresetRows(child, childW)
    local db = ns.DB()
    local y  = 0
    presetRefs = {}

    for _, raid in ipairs(ns.SpellData.raids) do
        -- Raid header
        local raidHdr = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        raidHdr:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        raidHdr:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        raidHdr:SetText(("-- " .. raid.name):upper())
        y = y - 20

        -- Enable/Disable all for this raid
        local enableAllBtn  = AccentBtn(child, 78, 16, "Enable All")
        local disableAllBtn = Btn(child, 78, 16, "Disable All")
        enableAllBtn:SetPoint("TOPLEFT",  child, "TOPLEFT", 0, y)
        disableAllBtn:SetPoint("LEFT", enableAllBtn, "RIGHT", 4, 0)

        -- collect spell ids for this raid's buttons
        local raidIds = {}
        for _, boss in ipairs(raid.bosses) do
            for _, spell in ipairs(boss.spells) do
                table.insert(raidIds, spell.id)
            end
        end
        enableAllBtn:SetScript("OnClick", function()
            local d = ns.DB()
            for _, sid in ipairs(raidIds) do
                d.spellAlerts[sid] = d.spellAlerts[sid] or {}
                d.spellAlerts[sid].enabled = true
            end
            -- update toggle btns
            for _, ref in ipairs(presetRefs) do
                for _, sid in ipairs(raidIds) do
                    if ref.id == sid then
                        ref.toggleBtn:SetText("|cff44ff88ON|r")
                    end
                end
            end
            ns.Alert:RegisterAuraSounds(CoTankAuras and CoTankAuras:GetAttribute("unit"))
        end)
        disableAllBtn:SetScript("OnClick", function()
            local d = ns.DB()
            for _, sid in ipairs(raidIds) do
                if d.spellAlerts[sid] then d.spellAlerts[sid].enabled = false end
            end
            for _, ref in ipairs(presetRefs) do
                for _, sid in ipairs(raidIds) do
                    if ref.id == sid then
                        ref.toggleBtn:SetText("|cffff6666OFF|r")
                    end
                end
            end
            ns.Alert:RegisterAuraSounds(CoTankAuras and CoTankAuras:GetAttribute("unit"))
        end)
        y = y - 22

        for _, boss in ipairs(raid.bosses) do
            -- Boss sub-header
            local bossHdr = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            bossHdr:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y)
            bossHdr:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
            bossHdr:SetText(boss.name)
            y = y - 17

            for _, spell in ipairs(boss.spells) do
                local row = CreateFrame("Frame", nil, child)
                row:SetSize(childW, 22)
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)

                -- Alternating row background
                if (#presetRefs % 2) == 0 then
                    local bg = row:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.025)
                end

                local sa = db.spellAlerts and db.spellAlerts[spell.id]
                local en = sa and sa.enabled or false

                -- Toggle button
                local tBtn = Btn(row, 36, 18, en and "|cff44ff88ON|r" or "|cffff6666OFF|r")
                tBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
                local captId = spell.id
                tBtn:SetScript("OnClick", function()
                    local d = ns.DB()
                    d.spellAlerts[captId] = d.spellAlerts[captId] or {}
                    d.spellAlerts[captId].enabled = not (d.spellAlerts[captId].enabled or false)
                    local newEn = d.spellAlerts[captId].enabled
                    tBtn:SetText(newEn and "|cff44ff88ON|r" or "|cffff6666OFF|r")
                    -- Engine-side aura sounds are registered per spell, so the
                    -- watch list has to be rebuilt whenever it changes.
                    ns.Alert:RegisterAuraSounds(CoTankAuras and CoTankAuras:GetAttribute("unit"))
                end)

                -- Spell name
                local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                nameFS:SetPoint("LEFT", tBtn, "RIGHT", 6, 0)
                nameFS:SetText(spell.name)
                nameFS:SetTextColor(C.text[1], C.text[2], C.text[3])

                -- Note (colored by type)
                local nc = NOTE_CLR[spell.note] or {C.dim[1], C.dim[2], C.dim[3]}
                local noteFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                noteFS:SetPoint("RIGHT", row, "RIGHT", -80, 0)
                noteFS:SetText(spell.note or "")
                noteFS:SetTextColor(nc[1], nc[2], nc[3])

                -- Threshold label + EB
                local thrLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                thrLbl:SetPoint("RIGHT", row, "RIGHT", -42, 0)
                thrLbl:SetText(">=")
                thrLbl:SetTextColor(C.dim[1], C.dim[2], C.dim[3])

                local thrEB = EB(row, 36, 18, true)
                thrEB:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                local thr = (sa and sa.threshold) or spell.threshold or 1
                thrEB:SetText(thr)
                thrEB:SetScript("OnEditFocusLost", function(self)
                    local v = self:GetNumber()
                    if v and v >= 1 then
                        local d = ns.DB()
                        d.spellAlerts[captId] = d.spellAlerts[captId] or {}
                        d.spellAlerts[captId].threshold = v
                    end
                end)
                thrEB:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

                table.insert(presetRefs, {id = captId, toggleBtn = tBtn, thrEB = thrEB})
                y = y - 22
            end
        end
        y = y - 6
    end

    child:SetHeight(math.abs(y) + 8)
end

-- ── Custom alert list ──────────────────────────────────────────────────────
-- The user's own alerts, listed above the presets with a toggle, an editable
-- threshold and a Remove button. Rows are reused, so each handler reads the
-- spell it currently shows from the row.
local customRows = {}
local customHdr  = nil

local function RegisterSounds()
    ns.Alert:RegisterAuraSounds(CoTankAuras and CoTankAuras:GetAttribute("unit"))
end

local function RefreshCustomAlerts(block, width, onResized)
    local db   = ns.DB()
    local list = ns.SpellData.CustomAlerts(db)

    if not customHdr then
        customHdr = block:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        customHdr:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
        customHdr:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        customHdr:SetText("-- YOUR CUSTOM ALERTS")
    end
    customHdr:SetShown(#list > 0)

    local y = (#list > 0) and -20 or 0
    for i, entry in ipairs(list) do
        local row = customRows[i]
        if not row then
            row = CreateFrame("Frame", nil, block)
            row:SetSize(width, 22)

            row.toggle = Btn(row, 36, 18, "")
            row.toggle:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.toggle:SetScript("OnClick", function()
                local alert = ns.DB().spellAlerts[row.key]
                if not alert then return end
                alert.enabled = not alert.enabled
                row.toggle:SetText(alert.enabled and "|cff44ff88ON|r" or "|cffff6666OFF|r")
                RegisterSounds()
            end)

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", row.toggle, "RIGHT", 6, 0)
            row.name:SetTextColor(C.text[1], C.text[2], C.text[3])

            row.remove = DangerBtn(row, 58, 18, "Remove")
            row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            row.remove:SetScript("OnClick", function()
                ns.DB().spellAlerts[row.key] = nil
                RegisterSounds()
                Status("Removed: " .. row.label)
                RefreshCustomAlerts(block, width, onResized)
            end)

            row.thrEB = EB(row, 36, 18, true)
            row.thrEB:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
            row.thrEB:SetScript("OnEditFocusLost", function(self)
                local alert = ns.DB().spellAlerts[row.key]
                local v = self:GetNumber()
                if alert and v and v >= 1 then alert.threshold = v end
            end)
            row.thrEB:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

            local thrLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            thrLbl:SetPoint("RIGHT", row.thrEB, "LEFT", -6, 0)
            thrLbl:SetText(">=")
            thrLbl:SetTextColor(C.dim[1], C.dim[2], C.dim[3])

            customRows[i] = row
        end

        row.key   = entry.key
        row.label = ns.Alert.SpellName(entry.id) or ("Spell " .. entry.id)
        row.name:SetText(row.label .. "  |cff556677" .. entry.id .. "|r")
        row.toggle:SetText(entry.alert.enabled and "|cff44ff88ON|r" or "|cffff6666OFF|r")
        row.thrEB:SetText(entry.alert.threshold or 1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", block, "TOPLEFT", 0, y)
        row:Show()
        y = y - 22
    end
    for i = #list + 1, #customRows do customRows[i]:Hide() end

    block:SetHeight(math.max(math.abs(y) + ((#list > 0) and 8 or 0), 1))
    onResized()
end

-- ── Sync widgets from saved DB ─────────────────────────────────────────────
local function SyncFromDB()
    if not optPanel then return end
    local db = ns.DB()

    -- Seed preset defaults (preserves existing user config)
    ns.SpellData.SeedDefaults(db)

    local function sv(sl, vt, key, def)
        local v = db[key] ~= nil and db[key] or def
        sl:SetValue(v); vt:SetText(v)
    end

    local faceId = ns.DB().fontFace or K.DEFAULT_FONT_FACE
    for _, f in ipairs(ns.FontList()) do
        if f.id == faceId then optPanel._fontDD:SetSelected(f.label); break end
    end
    local flagId = ns.DB().fontFlags or "OUTLINE"
    for _, f in ipairs(K.FONT_FLAGS) do
        if f.id == flagId then optPanel._fontFlagsDD:SetSelected(f.label); break end
    end
    for _, sw in ipairs(optPanel._swatches or {}) do sw:Sync() end
    sv(optPanel.sl_nameFont,  optPanel.vt_nameFont,  "nameFontSize",   K.DEFAULT_NAME_FONT_SIZE)
    sv(optPanel.sl_hpFont,    optPanel.vt_hpFont,    "hpFontSize",     K.DEFAULT_HP_FONT_SIZE)
    sv(optPanel.sl_width,     optPanel.vt_width,     "frameWidth",     K.DEFAULT_WIDTH)
    sv(optPanel.sl_height,    optPanel.vt_height,    "frameHeight",    K.DEFAULT_HEIGHT)
    sv(optPanel.sl_debuffs,   optPanel.vt_debuffs,   "maxDebuffs",     K.DEBUFF_DEFAULT_COUNT)
    if optPanel.btn_debuffsToggle then
        optPanel.btn_debuffsToggle:SetText(
            ns.DebuffsEnabled() and "|cff44ff88ON|r" or "|cffff6666OFF|r")
    end
    sv(optPanel.sl_defs,      optPanel.vt_defs,      "maxDefensives",  K.BIG_DEFENSIVES_DEFAULT_COUNT)
    local filterLabel = K.DEBUFF_FILTER_MODES[1].label
    for _, m in ipairs(K.DEBUFF_FILTER_MODES) do
        if m.id == db.debuffFilter then filterLabel = m.label; break end
    end
    optPanel._debuffFilterDD:SetSelected(filterLabel)
    local stackHL = ns.StackHighlightAt()
    optPanel.sl_stackHL:SetValue(stackHL)
    optPanel.vt_stackHL:SetText(stackHL > 0 and stackHL or "off")
    optPanel._stackHLSwatch:Sync()
    for _, toggle in ipairs(optPanel._toggles or {}) do toggle:Sync() end
    sv(optPanel.sl_privAuras,    optPanel.vt_privAuras,    "maxPrivateAuras",  K.PRIVATE_AURAS_DEFAULT_COUNT)
    sv(optPanel.sl_privAuraSize,   optPanel.vt_privAuraSize,   "privateAuraSize",        K.PRIVATE_AURA_SIZE_DEFAULT)
    sv(optPanel.sl_privAuraBorder, optPanel.vt_privAuraBorder, "privateAuraBorderScale", K.PRIVATE_AURA_BORDER_SCALE_DEFAULT)
    sv(optPanel.sl_privAuraStack,  optPanel.vt_privAuraStack,  "privateAuraStackScale",  K.PRIVATE_AURA_STACK_SCALE_DEFAULT)
    local growId = ns.DB().privateAuraGrowDir or "LEFT"
    for _, d in ipairs(K.PRIVATE_AURA_GROW_DIRECTIONS) do
        if d.id == growId then optPanel._privAuraGrowDD:SetSelected(d.label); break end
    end
    sv(optPanel.sl_alertSize, optPanel.vt_alertSize, "alertTextSize",  22)
    sv(optPanel.sl_stackSize, optPanel.vt_stackSize, "stackCountSize", K.STACK_COUNT_DEFAULT_SIZE)
    local cdScale = ns.SettingNumber("cdFontScale", K.CD_FONT_SCALE_DEFAULT)
    optPanel.sl_cdScale:SetValue(cdScale)
    optPanel.vt_cdScale:SetText(string.format("%.1f", cdScale / 10.0))
    sv(optPanel.sl_timerSize, optPanel.vt_timerSize, "timerTextSize", K.TIMER_TEXT_DEFAULT_SIZE)
    sv(optPanel.sl_nudgeX,    optPanel.vt_nudgeX,    "stackCountNudgeX", 0)
    sv(optPanel.sl_nudgeY,    optPanel.vt_nudgeY,    "stackCountNudgeY", 0)
    local posId = db.stackCountPos or "BR_IN"
    for _, pos in ipairs(K.STACK_COUNT_POSITIONS) do
        if pos.id == posId then optPanel._stackPosDD:SetSelected(pos.label); break end
    end
    optPanel._cdPosDD:SetSelected((db.cdAbove) and "Above Icon" or "On Icon")
    local debuffGap = ns.SettingNumber("debuffSpacing", K.DEBUFF_SPACING)
    optPanel.sl_debuffGap:SetValue(debuffGap); optPanel.vt_debuffGap:SetText(tostring(debuffGap))
    local privGap = ns.SettingNumber("privateAuraSpacing", K.DEBUFF_SPACING)
    optPanel.sl_privAuraGap:SetValue(privGap); optPanel.vt_privAuraGap:SetText(tostring(privGap))
    local ct = db.clickThrough or false
    optPanel.clickThruBtn:SetText(ct and "Click-Through: ON" or "Click-Through: OFF")
    optPanel.clickThruBtn.label:SetTextColor(
        ct and C.warn[1] or C.ok[1],
        ct and C.warn[2] or C.ok[2],
        ct and C.warn[3] or C.ok[3])

    optPanel.eb_alertText:SetText(db.alertText or "TAUNT")
    optPanel.testBtn:SetText(ns.isTestMode and "Test Mode: ON" or "Test Mode: OFF")

    -- Lock button
    local locked = db.frameLocked or false
    optPanel.lockBtn:SetText(locked and "Frame: LOCKED" or "Frame: UNLOCKED")
    optPanel.lockBtn.label:SetTextColor(
        locked and C.warn[1] or C.ok[1],
        locked and C.warn[2] or C.ok[2],
        locked and C.warn[3] or C.ok[3])

    -- Pin label
    local pinned = db.pinnedTank
    if pinned then
        optPanel._pinLabel:SetText("Pinned: |cff35c8ff" .. pinned .. "|r")
    else
        local coTank = ns.FindCoTank()
        local name = (coTank and UnitName(coTank)) or "none detected"
        optPanel._pinLabel:SetText("Auto-detect: |cff35c8ff" .. name .. "|r")
    end

    if optPanel._refreshCustomAlerts then optPanel._refreshCustomAlerts() end

    -- Sync preset spell toggles/thresholds
    for _, ref in ipairs(presetRefs) do
        local sa = db.spellAlerts and db.spellAlerts[ref.id]
        if sa then
            ref.toggleBtn:SetText(sa.enabled and "|cff44ff88ON|r" or "|cffff6666OFF|r")
            ref.thrEB:SetText(sa.threshold or 1)
        end
    end

    optPanel._status:SetText("")
    ShowTab(activeTab)
end

-- ── Panel construction ─────────────────────────────────────────────────────
local function BuildPanel()
    local p = CreateFrame("Frame", "CoTankAurasConfig", UIParent, "BackdropTemplate")
    p:SetSize(PW, PH)
    p:SetPoint("CENTER")
    p:SetFrameStrata("HIGH")
    p:SetClampedToScreen(true)
    p:SetMovable(true); p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop",  p.StopMovingOrSizing)
    p:SetBackdrop({bgFile = TILE, edgeFile = TILE, edgeSize = 1})
    p:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], C.bg[4])
    p:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    optPanel = p

    -- ── Title bar ────────────────────────────────────────────────────────
    local titleBar = CreateFrame("Frame", nil, p, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT"); titleBar:SetPoint("TOPRIGHT"); titleBar:SetHeight(34)
    titleBar:SetBackdrop({bgFile = TILE, edgeFile = TILE, edgeSize = 1})
    titleBar:SetBackdropColor(C.titleBg[1], C.titleBg[2], C.titleBg[3], 1)
    titleBar:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

    local accentStrip = titleBar:CreateTexture(nil, "ARTWORK")
    accentStrip:SetWidth(3); accentStrip:SetPoint("TOPLEFT"); accentStrip:SetPoint("BOTTOMLEFT")
    accentStrip:SetColorTexture(C.rule[1], C.rule[2], C.rule[3], 1)

    -- Frog icon
    local iconTex = titleBar:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(24, 24)
    iconTex:SetPoint("LEFT", accentStrip, "RIGHT", 6, 0)
    iconTex:SetTexture("Interface\\AddOns\\CludesUITank\\Media\\HappyBufo")
    iconTex:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local titleLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLbl:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
    titleLbl:SetText("|cff35c8ffCoTankAuras|r  |cff5a7a96Settings|r")

    local hintLbl = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintLbl:SetPoint("RIGHT", titleBar, "RIGHT", -36, 0)
    hintLbl:SetTextColor(0.20, 0.28, 0.40)
    hintLbl:SetText("/ccta  |  right-click frame")

    local closeBtn = Btn(titleBar, 24, 20, "X")
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
    closeBtn.label:SetTextColor(0.70, 0.22, 0.22)
    closeBtn:SetScript("OnClick", function() p:Hide() end)
    closeBtn:SetScript("OnEnter", function() closeBtn.bg:SetColorTexture(0.55, 0.12, 0.12) end)
    closeBtn:SetScript("OnLeave", function() closeBtn.bg:SetColorTexture(C.btnBg[1], C.btnBg[2], C.btnBg[3]) end)

    -- ── Tab bar ──────────────────────────────────────────────────────────
    local tabBar = CreateFrame("Frame", nil, p, "BackdropTemplate")
    tabBar:SetPoint("TOPLEFT",  p, "TOPLEFT",  0, -34)
    tabBar:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -34)
    tabBar:SetHeight(28)
    tabBar:SetBackdrop({bgFile = TILE, edgeFile = TILE, edgeSize = 1})
    tabBar:SetBackdropColor(C.tabBg[1], C.tabBg[2], C.tabBg[3], 1)
    tabBar:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)

    local tabW = math.floor(PW / #TABS)
    for i, def in ipairs(TABS) do
        local b = CreateFrame("Button", nil, tabBar)
        b:SetSize(tabW, 28)
        b:SetPoint("LEFT", tabBar, "LEFT", (i - 1) * tabW, 0)
        local tbg = b:CreateTexture(nil, "BACKGROUND")
        tbg:SetAllPoints(); tbg:SetColorTexture(C.tabBg[1], C.tabBg[2], C.tabBg[3]); b.bg = tbg
        local tlbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tlbl:SetAllPoints(); tlbl:SetJustifyH("CENTER"); tlbl:SetText(def.label)
        tlbl:SetTextColor(C.dim[1], C.dim[2], C.dim[3]); b.label = tlbl
        local ul = b:CreateTexture(nil, "ARTWORK")
        ul:SetHeight(2)
        ul:SetPoint("BOTTOMLEFT",  b, "BOTTOMLEFT",  2, 1)
        ul:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 1)
        ul:SetColorTexture(C.accent[1], C.accent[2], C.accent[3]); ul:Hide(); b.ul = ul
        local id = def.id
        b:SetScript("OnClick", function() ShowTab(id) end)
        b:SetScript("OnEnter", function() if activeTab ~= id then tbg:SetColorTexture(0.12, 0.18, 0.28) end end)
        b:SetScript("OnLeave", function() if activeTab ~= id then tbg:SetColorTexture(C.tabBg[1], C.tabBg[2], C.tabBg[3]) end end)
        p["_tab_" .. def.id] = b
    end

    -- ── Content area ─────────────────────────────────────────────────────
    local CW = PW - 28
    local content = CreateFrame("Frame", nil, p)
    content:SetPoint("TOPLEFT",     p, "TOPLEFT",     14, -66)
    content:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -14, 30)
    for _, def in ipairs(TABS) do
        local pg = CreateFrame("Frame", nil, content)
        pg:SetAllPoints(content); pg:Hide()
        tabPages[def.id] = pg
    end

    -- ── Status bar ───────────────────────────────────────────────────────
    local stBar = CreateFrame("Frame", nil, p, "BackdropTemplate")
    stBar:SetPoint("BOTTOMLEFT"); stBar:SetPoint("BOTTOMRIGHT"); stBar:SetHeight(28)
    stBar:SetBackdrop({bgFile = TILE, edgeFile = TILE, edgeSize = 1})
    stBar:SetBackdropColor(0.03, 0.05, 0.08, 1)
    stBar:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    p._status = stBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p._status:SetPoint("LEFT", stBar, "LEFT", 12, 0)
    p._status:SetText("")

    -- ════════════════════════════════════════════════════════════════════
    -- TAB: GENERAL
    -- ════════════════════════════════════════════════════════════════════
    local gpPage = tabPages["general"]
    local gpSF = CreateFrame("ScrollFrame", nil, gpPage, "UIPanelScrollFrameTemplate")
    gpSF:SetPoint("TOPLEFT",     gpPage, "TOPLEFT",     0,   0)
    gpSF:SetPoint("BOTTOMRIGHT", gpPage, "BOTTOMRIGHT", -20, 0)
    local gp = CreateFrame("Frame", nil, gpSF)
    gp:SetWidth(CW - 20)
    gpSF:SetScrollChild(gp)
    local Y  = 0

    -- DISPLAY
    SecHdr(gp, "DISPLAY", Y); Y = Y - 26

    local lFont = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lFont:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)
    lFont:SetText("Global font"); lFont:SetTextColor(C.text[1], C.text[2], C.text[3])
    local lFontFlags = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lFontFlags:SetPoint("TOPLEFT", gp, "TOPLEFT", 270, Y)
    lFontFlags:SetText("Font outline"); lFontFlags:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 18
    -- The list is the built-in game fonts plus everything LibSharedMedia knows
    -- about, so any font another addon registers is selectable here.
    p._fontDD = MakeDropdown(gp, 222, ns.FontList(), function(opt)
        ns.DB().fontFace = opt.id; ns.RefreshAllFonts()
    end)
    p._fontDD:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)

    p._fontFlagsDD = MakeDropdown(gp, 200, K.FONT_FLAGS, function(opt)
        ns.DB().fontFlags = opt.id; ns.RefreshAllFonts()
    end)
    p._fontFlagsDD:SetPoint("TOPLEFT", gp, "TOPLEFT", 270, Y)
    Y = Y - 32

    local lNameFont = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lNameFont:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)
    lNameFont:SetText("Name font size"); lNameFont:SetTextColor(C.text[1], C.text[2], C.text[3])
    local lHpFont = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lHpFont:SetPoint("TOPLEFT", gp, "TOPLEFT", 270, Y)
    lHpFont:SetText("HP font size"); lHpFont:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 18

    local function MakeSlider(parent, x, y, w, minV, maxV, step)
        local sl = CreateFrame("Slider", nil, parent, "BackdropTemplate")
        sl:SetSize(w or 222, 12); sl:SetOrientation("HORIZONTAL")
        sl:SetMinMaxValues(minV, maxV); sl:SetValueStep(step or 1); sl:SetObeyStepOnDrag(true)
        sl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        sl:SetBackdrop({bgFile = TILE, edgeFile = TILE, edgeSize = 1})
        sl:SetBackdropColor(0.06, 0.09, 0.14, 1); sl:SetBackdropBorderColor(0.18, 0.28, 0.44, 1)
        local thumb = sl:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(8, 18); thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        sl:SetThumbTexture(thumb)
        return sl
    end

    local function SliderVal(parent, sl)
        local vt = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        vt:SetPoint("LEFT", sl, "RIGHT", 8, 0)
        vt:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        return vt
    end

    p.sl_nameFont = MakeSlider(gp, 0,   Y, 222, K.MIN_FONT_SIZE, K.MAX_FONT_SIZE, 1)
    p.vt_nameFont = SliderVal(gp, p.sl_nameFont)
    p.sl_hpFont   = MakeSlider(gp, 270, Y, 222, K.MIN_FONT_SIZE, K.MAX_FONT_SIZE, 1)
    p.vt_hpFont   = SliderVal(gp, p.sl_hpFont)
    Y = Y - 30

    -- FRAME SIZE
    Divider(gp, Y); Y = Y - 10
    SecHdr(gp, "FRAME SIZE", Y); Y = Y - 26

    local lW = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lW:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y); lW:SetText("Width"); lW:SetTextColor(C.text[1], C.text[2], C.text[3])
    local lH = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lH:SetPoint("TOPLEFT", gp, "TOPLEFT", 270, Y); lH:SetText("Height"); lH:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 18

    p.sl_width  = MakeSlider(gp, 0,   Y, 222, K.MIN_WIDTH,  K.MAX_WIDTH,  5)
    p.vt_width  = SliderVal(gp, p.sl_width)
    p.sl_height = MakeSlider(gp, 270, Y, 222, K.MIN_HEIGHT, K.MAX_HEIGHT, 5)
    p.vt_height = SliderVal(gp, p.sl_height)
    Y = Y - 30

    -- ICONS
    Divider(gp, Y); Y = Y - 10
    SecHdr(gp, "ICONS", Y); Y = Y - 26

    -- Tank debuff master switch
    local lTD = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lTD:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)
    lTD:SetText("Tank debuffs  |cff3a4a5a(the co-tank's harmful auras)|r")
    lTD:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 18

    p.btn_debuffsToggle = Btn(gp, 60, 20, "")
    p.btn_debuffsToggle:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)
    p.btn_debuffsToggle:SetScript("OnClick", function()
        ns.ToggleDebuffs()
    end)
    Y = Y - 30

    local lDB = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lDB:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y); lDB:SetText("Debuff icons  |cff3a4a5a(harmful, incl. private)|r"); lDB:SetTextColor(C.text[1], C.text[2], C.text[3])
    local lDF = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lDF:SetPoint("TOPLEFT", gp, "TOPLEFT", 270, Y); lDF:SetText("Defensive icons  |cff3a4a5a(0 = hidden)|r"); lDF:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 18

    p.sl_debuffs = MakeSlider(gp, 0,   Y, 222, K.DEBUFF_MIN_COUNT,        K.DEBUFF_MAX_COUNT,        1)
    p.vt_debuffs = SliderVal(gp, p.sl_debuffs)
    p.sl_defs    = MakeSlider(gp, 270, Y, 222, K.BIG_DEFENSIVES_MIN_COUNT, K.BIG_DEFENSIVES_MAX_COUNT, 1)
    p.vt_defs    = SliderVal(gp, p.sl_defs)
    Y = Y - 30

    -- Which debuffs the row takes, and the stack count that highlights an icon.
    -- Both are applied by the game itself, so they hold during encounters.
    local lDFilter = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lDFilter:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)
    lDFilter:SetText("Debuffs to show"); lDFilter:SetTextColor(C.text[1], C.text[2], C.text[3])
    local lStackHL = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lStackHL:SetPoint("TOPLEFT", gp, "TOPLEFT", 270, Y)
    lStackHL:SetText("Highlight debuff at stacks  |cff3a4a5a(0 = off)|r"); lStackHL:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 18

    p._debuffFilterDD = MakeDropdown(gp, 222, K.DEBUFF_FILTER_MODES, function(opt)
        ns.DB().debuffFilter = opt.id; ns.RefreshDebuffFilter()
    end)
    p._debuffFilterDD:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)

    p.sl_stackHL = MakeSlider(gp, 270, Y, 170, K.STACK_HIGHLIGHT_MIN, K.STACK_HIGHLIGHT_MAX, 1)
    p.vt_stackHL = SliderVal(gp, p.sl_stackHL)
    p._stackHLSwatch = ColorSwatch(gp, 18, "stackHighlightColor", function()
        ns.RefreshAllIconSettings()
        if ns.isTestMode and CoTankAuras then CoTankAuras:UpdateDebuffs() end
    end)
    p._stackHLSwatch:SetPoint("TOPLEFT", gp, "TOPLEFT", 480, Y - 3)
    Y = Y - 34

    -- ON/OFF switches for the remaining icon behaviours.
    local function MakeToggle(x, y, label, key)
        local btn = Btn(gp, 36, 18, "")
        btn:SetPoint("TOPLEFT", gp, "TOPLEFT", x, y)
        local fs = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", btn, "RIGHT", 6, 0)
        fs:SetText(label); fs:SetTextColor(C.text[1], C.text[2], C.text[3])
        function btn:Sync()
            self:SetText(ns.DB()[key] and "|cff44ff88ON|r" or "|cffff6666OFF|r")
        end
        btn:SetScript("OnClick", function(self)
            ns.DB()[key] = not ns.DB()[key]
            self:Sync()
            ns.RefreshAllIconSettings()
            if ns.isTestMode and CoTankAuras then CoTankAuras:UpdateDebuffs() end
        end)
        return btn
    end
    p._toggles = {
        MakeToggle(0,   Y, "Colour borders by debuff type",            "debuffTypeBorders"),
        MakeToggle(270, Y, "On-screen alert text at that stack count", "stackBanner"),
    }
    Y = Y - 24
    p._toggles[3] = MakeToggle(0, Y, "Hide icon tooltips in combat", "hideTooltipsInCombat")
    Y = Y - 30

    local lPA = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lPA:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y); lPA:SetText("Private aura slots  |cff3a4a5a(above frame)|r"); lPA:SetTextColor(C.text[1], C.text[2], C.text[3])
    local lPASz = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lPASz:SetPoint("TOPLEFT", gp, "TOPLEFT", 270, Y); lPASz:SetText("Private aura size"); lPASz:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 18

    p.sl_privAuras = MakeSlider(gp, 0,   Y, 222, K.PRIVATE_AURAS_MIN_COUNT, K.PRIVATE_AURAS_MAX_COUNT, 1)
    p.vt_privAuras = SliderVal(gp, p.sl_privAuras)
    p.sl_privAuraSize = MakeSlider(gp, 270, Y, 222, K.PRIVATE_AURA_SIZE_MIN, K.PRIVATE_AURA_SIZE_MAX, 2)
    p.vt_privAuraSize = SliderVal(gp, p.sl_privAuraSize)
    Y = Y - 30

    -- PRIVATE AURA STYLE
    Divider(gp, Y); Y = Y - 10
    SecHdr(gp, "PRIVATE AURA STYLE", Y); Y = Y - 24

    local lPAGrow = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lPAGrow:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)
    lPAGrow:SetText("Grow direction"); lPAGrow:SetTextColor(C.text[1], C.text[2], C.text[3])
    local lPABorder = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lPABorder:SetPoint("TOPLEFT", gp, "TOPLEFT", 270, Y)
    lPABorder:SetText("Border scale  (0 = hidden)"); lPABorder:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 16

    p._privAuraGrowDD = MakeDropdown(gp, 200, K.PRIVATE_AURA_GROW_DIRECTIONS, function(opt)
        ns.DB().privateAuraGrowDir = opt.id; ns.RefreshPrivateAuraGrow()
    end)
    p._privAuraGrowDD:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)
    p.sl_privAuraBorder = MakeSlider(gp, 270, Y, 222, K.PRIVATE_AURA_BORDER_SCALE_MIN, K.PRIVATE_AURA_BORDER_SCALE_MAX, 1)
    p.vt_privAuraBorder = SliderVal(gp, p.sl_privAuraBorder)
    Y = Y - 32

    local lPAStack = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lPAStack:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)
    lPAStack:SetText("Stack & timer scale  (raise to increase visibility)"); lPAStack:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 16

    p.sl_privAuraStack = MakeSlider(gp, 0, Y, 222, K.PRIVATE_AURA_STACK_SCALE_MIN, K.PRIVATE_AURA_STACK_SCALE_MAX, 1)
    p.vt_privAuraStack = SliderVal(gp, p.sl_privAuraStack)
    Y = Y - 30

    -- ICON LABELS
    Divider(gp, Y); Y = Y - 10
    SecHdr(gp, "ICON LABELS", Y); Y = Y - 24

    local lStkSz = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lStkSz:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)
    lStkSz:SetText("Stack count size  (0 = hidden)"); lStkSz:SetTextColor(C.text[1], C.text[2], C.text[3])
    local lCdSc = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lCdSc:SetPoint("TOPLEFT", gp, "TOPLEFT", 270, Y)
    lCdSc:SetText("On-icon timer scale  (0 = hidden)"); lCdSc:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 16

    p.sl_stackSize = MakeSlider(gp, 0,   Y, 222, K.STACK_COUNT_MIN_SIZE, K.STACK_COUNT_MAX_SIZE, 1)
    p.vt_stackSize = SliderVal(gp, p.sl_stackSize)
    p.sl_cdScale   = MakeSlider(gp, 270, Y, 222, K.CD_FONT_SCALE_MIN,    K.CD_FONT_SCALE_MAX,    1)
    p.vt_cdScale   = SliderVal(gp, p.sl_cdScale)
    Y = Y - 22

    local lTimerSz = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lTimerSz:SetPoint("TOPLEFT", gp, "TOPLEFT", 270, Y)
    lTimerSz:SetText("Above-icon timer size"); lTimerSz:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 16

    p.sl_timerSize = MakeSlider(gp, 270, Y, 222, K.TIMER_TEXT_MIN_SIZE, K.TIMER_TEXT_MAX_SIZE, 1)
    p.vt_timerSize = SliderVal(gp, p.sl_timerSize)
    Y = Y - 22

    local lStkPos = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lStkPos:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)
    lStkPos:SetText("Stack count position"); lStkPos:SetTextColor(C.text[1], C.text[2], C.text[3])
    local lCdPos = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lCdPos:SetPoint("TOPLEFT", gp, "TOPLEFT", 270, Y)
    lCdPos:SetText("Timer position"); lCdPos:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 16

    p._stackPosDD = MakeDropdown(gp, 222, K.STACK_COUNT_POSITIONS, function(opt)
        ns.DB().stackCountPos = opt.id; ns.RefreshAllIconSettings()
    end)
    p._stackPosDD:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)

    p._cdPosDD = MakeDropdown(gp, 200, {
        {id = false, label = "On Icon"},
        {id = true,  label = "Above Icon"},
    }, function(opt)
        ns.DB().cdAbove = opt.id; ns.RefreshAllIconSettings()
    end)
    p._cdPosDD:SetPoint("TOPLEFT", gp, "TOPLEFT", 270, Y)
    Y = Y - 30

    -- Free nudge on top of the position preset, and per-element text colours.
    local lNudge = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lNudge:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)
    lNudge:SetText("Stack count nudge  X / Y"); lNudge:SetTextColor(C.text[1], C.text[2], C.text[3])
    local lColors = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lColors:SetPoint("TOPLEFT", gp, "TOPLEFT", 270, Y)
    lColors:SetText("Text colours"); lColors:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 16

    p.sl_nudgeX = MakeSlider(gp, 0,   Y, 100, K.STACK_NUDGE_MIN, K.STACK_NUDGE_MAX, 1)
    p.vt_nudgeX = SliderVal(gp, p.sl_nudgeX)
    p.sl_nudgeY = MakeSlider(gp, 122, Y, 100, K.STACK_NUDGE_MIN, K.STACK_NUDGE_MAX, 1)
    p.vt_nudgeY = SliderVal(gp, p.sl_nudgeY)

    local swatches = {
        {key = "stackCountColor", label = "Stack"},
        {key = "timerTextColor",  label = "Timer"},
        {key = "nameTextColor",   label = "Name"},
        {key = "hpTextColor",     label = "HP"},
    }
    p._swatches = {}
    for i, sw in ipairs(swatches) do
        local x = 270 + ((i - 1) * 58)
        local btn = ColorSwatch(gp, 18, sw.key, function()
            ns.RefreshAllFonts()
        end)
        btn:SetPoint("TOPLEFT", gp, "TOPLEFT", x, Y + 2)
        local lbl = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", btn, "RIGHT", 4, 0)
        lbl:SetText(sw.label); lbl:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        p._swatches[#p._swatches + 1] = btn
    end
    Y = Y - 32

    local lDGap = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lDGap:SetPoint("TOPLEFT", gp, "TOPLEFT", 0, Y)
    lDGap:SetText("Debuff icon gap"); lDGap:SetTextColor(C.text[1], C.text[2], C.text[3])
    local lPGap = gp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lPGap:SetPoint("TOPLEFT", gp, "TOPLEFT", 270, Y)
    lPGap:SetText("Private aura gap"); lPGap:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 16

    p.sl_debuffGap  = MakeSlider(gp, 0,   Y, 222, K.ICON_SPACING_MIN, K.ICON_SPACING_MAX, 1)
    p.vt_debuffGap  = SliderVal(gp, p.sl_debuffGap)
    p.sl_privAuraGap = MakeSlider(gp, 270, Y, 222, K.ICON_SPACING_MIN, K.ICON_SPACING_MAX, 1)
    p.vt_privAuraGap = SliderVal(gp, p.sl_privAuraGap)
    Y = Y - 24

    -- General slider scripts
    p.sl_nameFont:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().nameFontSize = v; p.vt_nameFont:SetText(v)
        if CoTankAuras and CoTankAuras.nameText then CoTankAuras.nameText:SetFont(ns.FontPath(), v, ns.FontFlags()) end
    end)
    p.sl_hpFont:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().hpFontSize = v; p.vt_hpFont:SetText(v)
        if CoTankAuras and CoTankAuras.hpText then CoTankAuras.hpText:SetFont(ns.FontPath(), v, ns.FontFlags()) end
    end)
    p.sl_width:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v/5+0.5)*5; ns.DB().frameWidth = v; p.vt_width:SetText(v)
        if CoTankAuras and not InCombatLockdown() then CoTankAuras:SetWidth(v); CoTankAuras:FitNameToWidth() end
    end)
    p.sl_height:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v/5+0.5)*5; ns.DB().frameHeight = v; p.vt_height:SetText(v)
        if CoTankAuras and not InCombatLockdown() then CoTankAuras:SetHeight(v) end
        -- Defensive icons sit inside the health bar, so their size follows the
        -- frame height and both the layout and the buttons need re-applying.
        ns.RefreshAuraContainerLayout(CoTankAuras)
        ns.RestyleAuraButtons()
    end)
    p.sl_debuffs:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().maxDebuffs = v; p.vt_debuffs:SetText(v)
        if CoTankAuras then
            CoTankAuras:UpdateAndRefreshDebuffLayout(v)
            if ns.isTestMode then CoTankAuras:ShowMockDebuffs() end
        end
    end)
    p.sl_defs:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().maxDefensives = v; p.vt_defs:SetText(v)
        if CoTankAuras then
            CoTankAuras:UpdateAndRefreshDefensiveLayout(v)
            if ns.isTestMode then CoTankAuras:UpdateBigDefensives() end
        end
    end)
    p.sl_stackHL:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().stackHighlightAt = v
        p.vt_stackHL:SetText(v > 0 and v or "off")
        ns.RefreshAllIconSettings()
        if ns.isTestMode and CoTankAuras then CoTankAuras:UpdateDebuffs() end
    end)
    p.sl_privAuras:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().maxPrivateAuras = v; p.vt_privAuras:SetText(v)
        if CoTankAuras then
            CoTankAuras:UpdateAndRefreshAuraLayout(v)
            if ns.isTestMode then CoTankAuras:ShowMockPrivateAuras() end
        end
    end)
    p.sl_privAuraSize:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v/2+0.5)*2; ns.DB().privateAuraSize = v; p.vt_privAuraSize:SetText(v)
        ns.RefreshPrivateAuraSize()
        if ns.isTestMode and CoTankAuras then CoTankAuras:ShowMockPrivateAuras() end
    end)
    p.sl_privAuraBorder:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().privateAuraBorderScale = v; p.vt_privAuraBorder:SetText(v)
        ns.RefreshPrivateAuraGrow()
    end)
    p.sl_privAuraStack:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().privateAuraStackScale = v; p.vt_privAuraStack:SetText(v)
        ns.RefreshPrivateAuraGrow()
    end)
    p.sl_stackSize:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().stackCountSize = v; p.vt_stackSize:SetText(v)
        ns.RefreshAllIconSettings()
    end)
    p.sl_cdScale:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().cdFontScale = v
        p.vt_cdScale:SetText(string.format("%.1f", v / 10.0))
        ns.RefreshAllIconSettings()
    end)
    p.sl_timerSize:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().timerTextSize = v; p.vt_timerSize:SetText(v)
        ns.RefreshAllIconSettings()
    end)
    p.sl_nudgeX:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().stackCountNudgeX = v; p.vt_nudgeX:SetText(v)
        ns.RefreshAllIconSettings()
    end)
    p.sl_nudgeY:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().stackCountNudgeY = v; p.vt_nudgeY:SetText(v)
        ns.RefreshAllIconSettings()
    end)
    p.sl_debuffGap:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().debuffSpacing = v; p.vt_debuffGap:SetText(v)
        ns.RefreshDebuffSpacing()
    end)
    p.sl_privAuraGap:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.DB().privateAuraSpacing = v; p.vt_privAuraGap:SetText(v)
        ns.RefreshPrivateAuraSpacing()
    end)

    gp:SetHeight(math.abs(Y) + 16)

    -- ════════════════════════════════════════════════════════════════════
    -- TAB: ALERTS
    -- ════════════════════════════════════════════════════════════════════
    local al = tabPages["alerts"]
    Y = 0

    SecHdr(al, "PRESET RAID ALERTS", Y); Y = Y - 26
    local d1 = al:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d1:SetPoint("TOPLEFT", al, "TOPLEFT", 0, Y)
    d1:SetText("Toggle spells ON to fire an alert when the co-tank's debuff reaches the stack threshold.")
    d1:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    Y = Y - 18

    -- Preset scroll frame
    local SF_H   = 218
    local SF_W   = CW - 20   -- 20px for scrollbar
    local sf = CreateFrame("ScrollFrame", nil, al, "UIPanelScrollFrameTemplate")
    sf:SetSize(SF_W, SF_H)
    sf:SetPoint("TOPLEFT", al, "TOPLEFT", 0, Y)

    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(SF_W - 22)
    child:SetHeight(1)
    sf:SetScrollChild(child)

    -- The user's own alerts sit above the presets and change height as they
    -- are added and removed, so each list gets its own block.
    local customBlock = CreateFrame("Frame", nil, child)
    customBlock:SetWidth(SF_W - 22)
    customBlock:SetHeight(1)
    customBlock:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    local presetBlock = CreateFrame("Frame", nil, child)
    presetBlock:SetWidth(SF_W - 22)
    presetBlock:SetPoint("TOPLEFT", customBlock, "BOTTOMLEFT", 0, 0)

    BuildPresetRows(presetBlock, SF_W - 22)
    p._refreshCustomAlerts = function()
        RefreshCustomAlerts(customBlock, SF_W - 22, function()
            child:SetHeight(customBlock:GetHeight() + presetBlock:GetHeight())
        end)
    end
    p._refreshCustomAlerts()
    Y = Y - SF_H - 10

    Divider(al, Y); Y = Y - 14

    -- ADD CUSTOM ALERT
    SecHdr(al, "ADD CUSTOM ALERT", Y); Y = Y - 26

    local cID = al:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cID:SetPoint("TOPLEFT", al, "TOPLEFT", 0, Y); cID:SetText("Spell ID"); cID:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    local cST = al:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cST:SetPoint("TOPLEFT", al, "TOPLEFT", 136, Y); cST:SetText("Stack threshold"); cST:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    Y = Y - 18

    local eb_id = EB(al, 116, 26, true)
    eb_id:SetPoint("TOPLEFT", al, "TOPLEFT", 0, Y); p.eb_spellId = eb_id

    local eb_st = EB(al, 72, 26, true)
    eb_st:SetPoint("LEFT", eb_id, "RIGHT", 8, 0); p.eb_threshold = eb_st

    local addBtn = AccentBtn(al, 80, 26, "Add Alert")
    addBtn:SetPoint("LEFT", eb_st, "RIGHT", 8, 0)
    Y = Y - 36

    Divider(al, Y); Y = Y - 14

    -- ALERT MESSAGE & SIZE
    SecHdr(al, "ALERT MESSAGE & SIZE", Y); Y = Y - 26

    local lMsg = al:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lMsg:SetPoint("TOPLEFT", al, "TOPLEFT", 0, Y); lMsg:SetText("On-screen message prefix"); lMsg:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 18

    p.eb_alertText = EB(al, 190, 26)
    p.eb_alertText:SetPoint("TOPLEFT", al, "TOPLEFT", 0, Y)

    local saveBtn = AccentBtn(al, 56, 26, "Save")
    saveBtn:SetPoint("LEFT", p.eb_alertText, "RIGHT", 6, 0)
    local testAlertBtn = AccentBtn(al, 96, 26, "Test Alert")
    testAlertBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
    Y = Y - 34

    local lASz = al:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lASz:SetPoint("TOPLEFT", al, "TOPLEFT", 0, Y); lASz:SetText("Alert font size"); lASz:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 18

    p.sl_alertSize = MakeSlider(al, 0, Y, 200, 12, 48, 1)
    p.vt_alertSize = SliderVal(al, p.sl_alertSize)

    -- Alerts scripts
    addBtn:SetScript("OnClick", function()
        local sid = eb_id:GetNumber(); local thr = eb_st:GetNumber()
        if not sid or sid <= 0   then Status("Enter a valid Spell ID.", true); return end
        if not thr or thr < 1   then Status("Stack threshold must be >= 1.", true); return end
        local db = ns.DB(); db.spellAlerts = db.spellAlerts or {}
        local isPreset = ns.SpellData.IsPreset(sid)
        db.spellAlerts[sid] = {enabled = true, threshold = thr, preset = isPreset or nil}
        -- Engine alert sounds are registered per spell, so the new one needs
        -- a rebuild like any toggle, or it stays silent until the next one.
        RegisterSounds()
        eb_id:SetText(""); eb_st:SetText("")
        local n = ns.Alert.SpellName(sid) or ("Spell " .. sid)
        if isPreset then
            -- Already in the preset list: switch that row on instead of
            -- listing the same spell twice.
            for _, ref in ipairs(presetRefs) do
                if ref.id == sid then
                    ref.toggleBtn:SetText("|cff44ff88ON|r")
                    ref.thrEB:SetText(thr)
                end
            end
            Status("Enabled preset: " .. n .. " at >=" .. thr .. " stacks.")
        else
            p._refreshCustomAlerts()
            sf:SetVerticalScroll(0)
            Status("Added: " .. n .. " at >=" .. thr .. " stacks.")
        end
    end)
    eb_id:SetScript("OnEnterPressed", function() eb_st:SetFocus() end)
    eb_st:SetScript("OnEnterPressed", function() addBtn:GetScript("OnClick")() end)
    saveBtn:SetScript("OnClick", function()
        ns.Alert:SetText(p.eb_alertText:GetText()); p.eb_alertText:ClearFocus(); Status("Alert message saved.")
    end)
    p.eb_alertText:SetScript("OnEnterPressed", function(self) ns.Alert:SetText(self:GetText()); self:ClearFocus(); Status("Alert message saved.") end)
    p.eb_alertText:SetScript("OnEditFocusLost", function(self) ns.Alert:SetText(self:GetText()) end)
    testAlertBtn:SetScript("OnClick", function() ns.Alert:Test() end)
    p.sl_alertSize:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v+0.5); ns.Alert:SetTextSize(v); p.vt_alertSize:SetText(v)
    end)

    -- ════════════════════════════════════════════════════════════════════
    -- TAB: TOOLS
    -- ════════════════════════════════════════════════════════════════════
    local tp = tabPages["tools"]

    -- Wrap all Tools content in a scroll frame so nothing overflows
    local tpSF = CreateFrame("ScrollFrame", nil, tp, "UIPanelScrollFrameTemplate")
    tpSF:SetPoint("TOPLEFT",     tp, "TOPLEFT",     0,   0)
    tpSF:SetPoint("BOTTOMRIGHT", tp, "BOTTOMRIGHT", -20, 0)

    local tpc = CreateFrame("Frame", nil, tpSF)
    tpc:SetWidth(CW - 20)
    tpSF:SetScrollChild(tpc)

    Y = 0

    -- TEST MODE
    SecHdr(tpc, "TEST MODE", Y); Y = Y - 26
    local tdesc = tpc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tdesc:SetPoint("TOPLEFT", tpc, "TOPLEFT", 0, Y)
    tdesc:SetText("Simulates a co-tank with mock name, health, debuffs (with stacks and timers), power bar, and private aura slots.")
    tdesc:SetTextColor(C.dim[1], C.dim[2], C.dim[3]); Y = Y - 18

    p.testBtn = AccentBtn(tpc, 170, 28, "Test Mode: OFF")
    p.testBtn:SetPoint("TOPLEFT", tpc, "TOPLEFT", 0, Y)
    Y = Y - 44

    -- FRAME LOCK
    Divider(tpc, Y); Y = Y - 14
    SecHdr(tpc, "FRAME LOCK", Y); Y = Y - 26
    local ldesc = tpc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ldesc:SetPoint("TOPLEFT", tpc, "TOPLEFT", 0, Y)
    ldesc:SetText("Lock the frame in place to prevent accidental dragging.")
    ldesc:SetTextColor(C.dim[1], C.dim[2], C.dim[3]); Y = Y - 18

    p.lockBtn = Btn(tpc, 170, 28, "Frame: UNLOCKED")
    p.lockBtn:SetPoint("TOPLEFT", tpc, "TOPLEFT", 0, Y)
    p.lockBtn.label:SetTextColor(C.ok[1], C.ok[2], C.ok[3])
    Y = Y - 44

    -- PIN CO-TANK
    Divider(tpc, Y); Y = Y - 14
    SecHdr(tpc, "PIN CO-TANK", Y); Y = Y - 26
    local pdesc = tpc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pdesc:SetPoint("TOPLEFT", tpc, "TOPLEFT", 0, Y)
    pdesc:SetText("Pin a specific player as your co-tank when multiple tanks are in the group.")
    pdesc:SetTextColor(C.dim[1], C.dim[2], C.dim[3]); Y = Y - 18

    p._pinLabel = tpc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p._pinLabel:SetPoint("TOPLEFT", tpc, "TOPLEFT", 0, Y)
    p._pinLabel:SetText("Auto-detect: |cff35c8ffnone|r")
    p._pinLabel:SetTextColor(C.text[1], C.text[2], C.text[3])
    Y = Y - 26

    -- Row 1: pin current detected tank / unpin
    p._pinBtn = AccentBtn(tpc, 110, 26, "Pin Current")
    p._pinBtn:SetPoint("TOPLEFT", tpc, "TOPLEFT", 0, Y)
    p._pinBtn.label:SetTextColor(C.ok[1], C.ok[2], C.ok[3])

    local clearPinBtn = DangerBtn(tpc, 80, 26, "Unpin")
    clearPinBtn:SetPoint("LEFT", p._pinBtn, "RIGHT", 6, 0)
    Y = Y - 34

    -- Row 2: manual name entry
    local pinNameLbl = tpc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pinNameLbl:SetPoint("TOPLEFT", tpc, "TOPLEFT", 0, Y)
    pinNameLbl:SetText("Or type a name:")
    pinNameLbl:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    Y = Y - 18

    p._pinNameEB = EB(tpc, 200, 26)
    p._pinNameEB:SetPoint("TOPLEFT", tpc, "TOPLEFT", 0, Y)
    p._pinNameEB:SetMaxLetters(60)

    local pinNameBtn = AccentBtn(tpc, 72, 26, "Pin Name")
    pinNameBtn:SetPoint("LEFT", p._pinNameEB, "RIGHT", 6, 0)
    pinNameBtn.label:SetTextColor(C.ok[1], C.ok[2], C.ok[3])
    Y = Y - 44

    -- RESET POSITION
    Divider(tpc, Y); Y = Y - 14
    SecHdr(tpc, "FRAME POSITION", Y); Y = Y - 26
    local posdesc = tpc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    posdesc:SetPoint("TOPLEFT", tpc, "TOPLEFT", 0, Y)
    posdesc:SetText("Left-drag the frame to reposition it (when unlocked). Reset returns it to center.")
    posdesc:SetTextColor(C.dim[1], C.dim[2], C.dim[3]); Y = Y - 18

    local resetBtn = DangerBtn(tpc, 150, 28, "Reset Position")
    resetBtn:SetPoint("TOPLEFT", tpc, "TOPLEFT", 0, Y)
    Y = Y - 44

    -- CLICK-THROUGH
    Divider(tpc, Y); Y = Y - 14
    SecHdr(tpc, "CLICK-THROUGH", Y); Y = Y - 26
    local ctdesc = tpc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ctdesc:SetPoint("TOPLEFT", tpc, "TOPLEFT", 0, Y)
    ctdesc:SetText("Ignore all mouse clicks on the frame. Use /ccta to toggle this back off.")
    ctdesc:SetTextColor(C.dim[1], C.dim[2], C.dim[3]); Y = Y - 18

    p.clickThruBtn = Btn(tpc, 170, 28, "Click-Through: OFF")
    p.clickThruBtn:SetPoint("TOPLEFT", tpc, "TOPLEFT", 0, Y)
    p.clickThruBtn.label:SetTextColor(C.ok[1], C.ok[2], C.ok[3])
    Y = Y - 44

    -- COMMANDS
    Divider(tpc, Y); Y = Y - 14
    SecHdr(tpc, "COMMANDS", Y); Y = Y - 26
    for _, pair in ipairs({
        {"|cffffff00/ccta|r",                       "open this settings panel"},
        {"|cffffff00/ccta|r |cffffff00test|r",      "toggle test mode"},
        {"|cffffff00/ccta|r |cffffff00reset|r",     "reset frame position"},
        {"|cffffff00/ccta|r |cffffff00lock|r / |cffffff00unlock|r", "lock/unlock frame"},
        {"|cffffff00/ccta|r |cffffff00pin|r [name]", "pin co-tank"},
        {"|cffffff00/ccta|r |cffffff00unpin|r",     "clear pin"},
        {"|cffffff00/ccta|r |cffffff00help|r",      "list all commands"},
        {"|cffffff00/cta|r",                        "alias for /ccta"},
    }) do
        local row = tpc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetPoint("TOPLEFT", tpc, "TOPLEFT", 0, Y)
        row:SetText("  " .. pair[1] .. "  |cff2a3a4a-|r  |cff556677" .. pair[2] .. "|r")
        Y = Y - 18
    end

    tpc:SetHeight(math.abs(Y) + 16)

    -- Tools scripts
    p.testBtn:SetScript("OnClick", function()
        if not ns.SetTestMode(not ns.isTestMode) then
            Status("Cannot change test mode during combat.", true)
            return
        end
        Status(ns.isTestMode and "Test mode ON - watching yourself." or "Test mode OFF.")
    end)

    p.lockBtn:SetScript("OnClick", function()
        local db = ns.DB()
        db.frameLocked = not (db.frameLocked or false)
        local locked = db.frameLocked
        p.lockBtn:SetText(locked and "Frame: LOCKED" or "Frame: UNLOCKED")
        p.lockBtn.label:SetTextColor(
            locked and C.warn[1] or C.ok[1],
            locked and C.warn[2] or C.ok[2],
            locked and C.warn[3] or C.ok[3])
        Status(locked and "Frame locked." or "Frame unlocked.")
    end)

    local function ApplyPin(name)
        name = name and name:match("^%s*(.-)%s*$")
        if not name or name == "" then
            Status("Enter a player name to pin.", true)
            return
        end
        ns.DB().pinnedTank = name
        p._pinLabel:SetText("Pinned: |cff35c8ff" .. name .. "|r")
        p._pinNameEB:SetText("")
        p._pinNameEB:ClearFocus()
        Status("Pinned co-tank: " .. name)
    end

    p._pinBtn:SetScript("OnClick", function()
        local coTank = ns.FindCoTank()
        local name = coTank and UnitName(coTank)
        if name then
            ApplyPin(name)
        else
            Status("No co-tank detected. Type a name below.", true)
        end
    end)

    clearPinBtn:SetScript("OnClick", function()
        ns.DB().pinnedTank = nil
        p._pinNameEB:SetText("")
        local coTank = ns.FindCoTank()
        local name = (coTank and UnitName(coTank)) or "none detected"
        p._pinLabel:SetText("Auto-detect: |cff35c8ff" .. name .. "|r")
        Status("Pin cleared.")
    end)

    pinNameBtn:SetScript("OnClick", function()
        ApplyPin(p._pinNameEB:GetText())
    end)
    p._pinNameEB:SetScript("OnEnterPressed", function(self)
        ApplyPin(self:GetText())
    end)

    resetBtn:SetScript("OnClick", function()
        if InCombatLockdown() then Status("Cannot reset during combat.", true); return end
        if CoTankAuras then ns.ResetPosition(CoTankAuras) end
        Status("Position reset to center.")
    end)

    p.clickThruBtn:SetScript("OnClick", function()
        -- The frame is secure, so EnableMouse on it is blocked in combat.
        if InCombatLockdown() then Status("Cannot change click-through during combat.", true); return end
        local db = ns.DB()
        db.clickThrough = not (db.clickThrough or false)
        local ct = db.clickThrough
        p.clickThruBtn:SetText(ct and "Click-Through: ON" or "Click-Through: OFF")
        p.clickThruBtn.label:SetTextColor(
            ct and C.warn[1] or C.ok[1],
            ct and C.warn[2] or C.ok[2],
            ct and C.warn[3] or C.ok[3])
        if CoTankAuras then CoTankAuras:EnableMouse(not ct) end
        Status(ct and "Click-through ON. Use /ccta to open menu." or "Click-through OFF.")
    end)

    -- ── Final setup ───────────────────────────────────────────────────────
    p:HookScript("OnShow", function()
        SyncFromDB()
    end)
    p:Hide()
    tinsert(UISpecialFrames, "CoTankAurasConfig")
    ShowTab("general")
end

-- ── Public API ─────────────────────────────────────────────────────────────
ns.Options = {}

function ns.Options:Initialize() end

function ns.Options:Open()
    if not optPanel then
        local ok, err = pcall(BuildPanel)
        if not ok then
            ns.Print("|cffff4040Failed to build settings panel: " .. tostring(err) .. "|r")
            return
        end
    end
    if optPanel:IsShown() then
        optPanel:Hide()
    else
        SyncFromDB()
        optPanel:Show()
    end
end

function ns.Options:SyncTestButton()
    if not optPanel then return end
    if optPanel.testBtn then
        optPanel.testBtn:SetText(ns.isTestMode and "Test Mode: ON" or "Test Mode: OFF")
    end
    if optPanel.btn_debuffsToggle then
        optPanel.btn_debuffsToggle:SetText(
            ns.DebuffsEnabled() and "|cff44ff88ON|r" or "|cffff6666OFF|r")
    end
end
