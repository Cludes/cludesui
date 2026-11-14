if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Presets.lua
--
--  Spec assignment popup for the global profile system.
--  Split from CludesUI.lua -- see CludesUI.lua for the base addon code.
--
--  Load order (via TOC):
--    1. CludesUI.lua        -- constants, utils, popups, main frame
--    2. CludesUI_Widgets.lua -- shared widget helpers, widget factory
--    3. CludesUI_Presets.lua -- THIS FILE
-------------------------------------------------------------------------------

local CludesUI = _G.CludesUI
local Pix = CludesUI.PanelPP

-- Utility functions
local MakeFont = CludesUI.MakeFont
local DisablePixelSnap = CludesUI.DisablePixelSnap
local lerp = CludesUI.lerp
local MakeDropdownArrow = CludesUI.MakeDropdownArrow

-- Visual constants
local CLUDES_GREEN = CludesUI.CLUDES_GREEN
local CLASS_COLOR_MAP = CludesUI.CLASS_COLOR_MAP

-- Numeric constants used in spec assignment popup
local BORDER_R = CludesUI.BORDER_R
local BORDER_G = CludesUI.BORDER_G
local BORDER_B = CludesUI.BORDER_B
local CB_BOX_R = CludesUI.CB_BOX_R
local CB_BOX_G = CludesUI.CB_BOX_G
local CB_BOX_B = CludesUI.CB_BOX_B
local CB_BRD_A = CludesUI.CB_BRD_A
local CB_ACT_BRD_A = CludesUI.CB_ACT_BRD_A

-------------------------------------------------------------------------------
--  SPEC ASSIGNMENT POPUP
--
--  Shows every spec sorted by class with checkboxes in a 5-column layout.
--  Stores assignments in db[dbKey][presetKey] = { [specID] = true, ... }
-------------------------------------------------------------------------------
do
    -- All WoW Retail classes and their specs (as of TWW / 12.0)
    local SPEC_DATA = {
        {
            class = "DEATHKNIGHT",
            name = "Death Knight",
            specs = {
                { id = 250, name = "Blood" },
                { id = 251, name = "Frost" },
                { id = 252, name = "Unholy" },
            },
        },
        {
            class = "DEMONHUNTER",
            name = "Demon Hunter",
            specs = {
                { id = 577, name = "Havoc" },
                { id = 581, name = "Vengeance" },
                { id = 1480, name = "Devourer" },
            },
        },
        {
            class = "DRUID",
            name = "Druid",
            specs = {
                { id = 102, name = "Balance" },
                { id = 103, name = "Feral" },
                { id = 104, name = "Guardian" },
                { id = 105, name = "Restoration" },
            },
        },
        {
            class = "EVOKER",
            name = "Evoker",
            specs = {
                { id = 1467, name = "Devastation" },
                { id = 1468, name = "Preservation" },
                { id = 1473, name = "Augmentation" },
            },
        },
        {
            class = "HUNTER",
            name = "Hunter",
            specs = {
                { id = 253, name = "Beast Mastery" },
                { id = 254, name = "Marksmanship" },
                { id = 255, name = "Survival" },
            },
        },
        {
            class = "MAGE",
            name = "Mage",
            specs = {
                { id = 62, name = "Arcane" },
                { id = 63, name = "Fire" },
                { id = 64, name = "Frost" },
            },
        },
        {
            class = "MONK",
            name = "Monk",
            specs = {
                { id = 268, name = "Brewmaster" },
                { id = 270, name = "Mistweaver" },
                { id = 269, name = "Windwalker" },
            },
        },
        {
            class = "PALADIN",
            name = "Paladin",
            specs = {
                { id = 65, name = "Holy" },
                { id = 66, name = "Protection" },
                { id = 70, name = "Retribution" },
            },
        },
        {
            class = "PRIEST",
            name = "Priest",
            specs = {
                { id = 256, name = "Discipline" },
                { id = 257, name = "Holy" },
                { id = 258, name = "Shadow" },
            },
        },
        {
            class = "ROGUE",
            name = "Rogue",
            specs = {
                { id = 259, name = "Assassination" },
                { id = 260, name = "Outlaw" },
                { id = 261, name = "Subtlety" },
            },
        },
        {
            class = "SHAMAN",
            name = "Shaman",
            specs = {
                { id = 262, name = "Elemental" },
                { id = 263, name = "Enhancement" },
                { id = 264, name = "Restoration" },
            },
        },
        {
            class = "WARLOCK",
            name = "Warlock",
            specs = {
                { id = 265, name = "Affliction" },
                { id = 266, name = "Demonology" },
                { id = 267, name = "Destruction" },
            },
        },
        {
            class = "WARRIOR",
            name = "Warrior",
            specs = {
                { id = 71, name = "Arms" },
                { id = 72, name = "Fury" },
                { id = 73, name = "Protection" },
            },
        },
    }
    CludesUI._SPEC_DATA = SPEC_DATA

    ---------------------------------------------------------------------------
    --  WoW Forever spec translation. Forever has ONE spec per class (named
    --  after the class). Every spec-keyed store keeps RETAIL spec IDs, so
    --  profiles move between the clients unchanged; on Forever the player
    --  counts as every retail spec of the class. Where saved data differs
    --  between specs of the class, the first spec in SPEC_DATA order (the
    --  class's spec index order) wins. Data a store holds under the Forever
    --  spec ID itself is what the client shows for it, so where a caller
    --  allows it that key is read first.
    --  Retail never builds these tables: the entry points return their input.
    ---------------------------------------------------------------------------
    -- Forever class -> Forever spec ID (ChrSpecialization, Forever 1.60.1).
    CludesUI.FOREVER_CLASS_SPEC = {
        MAGE = 1482,
        DRUID = 1484,
        HUNTER = 1485,
        PALADIN = 1486,
        PRIEST = 1487,
        ROGUE = 1488,
        SHAMAN = 1489,
        WARLOCK = 1490,
        WARRIOR = 1491,
    }
    -- Heals a Forever class range-checks with, best first: the retail-parity
    -- heal (learned at level 12-20 there), then the class's level-1 heal.
    CludesUI.FOREVER_HEAL_SPELLS = {
        PRIEST = { 2061, 2050 }, -- Flash Heal, Lesser Heal
        PALADIN = { 19750, 635 }, -- Flash of Light, Holy Light
        SHAMAN = { 8004, 331 }, -- Lesser Healing Wave, Healing Wave
        DRUID = { 8936, 5185 }, -- Regrowth, Healing Touch
    }
    local FOREVER_CLASS_ID = {
        WARRIOR = 1,
        PALADIN = 2,
        HUNTER = 3,
        ROGUE = 4,
        PRIEST = 5,
        SHAMAN = 7,
        MAGE = 8,
        WARLOCK = 9,
        DRUID = 11,
    }

    local fv -- lookup tables, built on first use (Forever only)
    local playerClass -- the player's class token (never changes in a session)

    local function FV()
        if fv then
            return fv
        end
        -- specs/order: the Forever classes only. class/name/specName: every
        -- class in SPEC_DATA, plus each Forever spec ID -> its class.
        fv = { specs = {}, order = {}, class = {}, name = {}, specName = {} }
        for i = 1, #SPEC_DATA do
            local cls = SPEC_DATA[i]
            fv.name[cls.class] = cls.name
            for jdx = 1, #cls.specs do
                local s = cls.specs[jdx]
                fv.class[s.id] = cls.class
                fv.specName[s.id] = s.name
            end
            local fid = CludesUI.FOREVER_CLASS_SPEC[cls.class]
            if fid then
                local ids = {}
                for jdx = 1, #cls.specs do
                    ids[jdx] = cls.specs[jdx].id
                end
                fv.specs[cls.class] = ids
                fv.order[#fv.order + 1] = cls.class
                fv.class[fid] = cls.class
            end
        end
        return fv
    end

    local function PlayerClass()
        if not playerClass then
            playerClass = select(2, UnitClass("player"))
        end
        return playerClass
    end

    -- First candidate pred accepts: the legacy Forever ID (when given), then
    -- the retail specs in class order. None -> the class's first retail spec,
    -- the key new data is written under.
    local function Pick(ids, legacyID, pred, arg)
        if pred then
            if legacyID and pred(legacyID, arg) then
                return legacyID
            end
            for i = 1, #ids do
                if pred(ids[i], arg) then
                    return ids[i]
                end
            end
        end
        return ids[1]
    end

    --- Forever: the retail spec ID a class acts as in one store. pred(id, arg)
    --- answers "this store holds data for spec id"; pred nil = the first spec.
    --- withLegacy also offers the class's Forever spec ID, first (stores that
    --- can hold data under it: the CDM spell store). token nil = the player.
    --- nil on retail and for a class Forever does not have.
    function CludesUI.ForeverClassSpec(token, pred, arg, withLegacy)
        if not CludesUI.IS_FOREVER then
            return nil
        end
        token = token or PlayerClass()
        local ids = token and FV().specs[token]
        if not ids then
            return nil
        end
        return Pick(ids, withLegacy and CludesUI.FOREVER_CLASS_SPEC[token] or nil, pred, arg)
    end

    --- The spec ID the client reports, translated to the spec ID that keys a
    --- retail-keyed store. Returned unchanged on retail, for nil / 0, and for
    --- a retail spec ID of any class. Otherwise (the client's own spec,
    --- 1482-1491, 1493 or any unknown ID): the raw ID itself when pred holds
    --- (data held under it), else the player's class retail specs in class
    --- order, else the class's first retail spec.
    function CludesUI.SpecFor(rawID, pred, arg)
        if not CludesUI.IS_FOREVER or not rawID or rawID == 0 then
            return rawID
        end
        local t = FV()
        local ownerFrame = t.class[rawID]
        if ownerFrame and CludesUI.FOREVER_CLASS_SPEC[ownerFrame] ~= rawID then
            return rawID
        end
        local ids = t.specs[PlayerClass() or ""]
        if not ids then
            return rawID
        end
        return Pick(ids, rawID, pred, arg)
    end

    --- True when specID is a spec the player counts as: retail = the live spec;
    --- Forever = any retail spec of the player's class, or its Forever spec ID.
    function CludesUI.IsPlayerSpec(specID)
        if not specID then
            return false
        end
        if CludesUI.IS_FOREVER then
            return FV().class[specID] == PlayerClass()
        end
        local live = CludesUI._specID
        if not live or live == 0 then
            CludesUI._RefreshSpecID()
            live = CludesUI._specID
        end
        return live ~= 0 and specID == live
    end

    --- Forever only (callers gate): class tokens in SPEC_DATA order; a Forever
    --- class's retail spec IDs in class order (shared tables, read only); the
    --- class owning a retail spec ID of ANY class or a Forever spec ID; the
    --- English spec name of a retail spec ID; class display name and icon.
    function CludesUI.ForeverClasses()
        return FV().order
    end
    function CludesUI.ForeverClassSpecIDs(token)
        return token and FV().specs[token] or nil
    end
    function CludesUI.SpecClassOf(specID)
        return specID and FV().class[specID] or nil
    end
    function CludesUI.RetailSpecName(specID)
        return specID and FV().specName[specID] or nil
    end
    function CludesUI.ForeverClassName(token)
        return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or FV().name[token] or token
    end
    function CludesUI.ForeverClassIcon(token)
        local cid = FOREVER_CLASS_ID[token]
        if not (cid and GetSpecializationInfoForClassID) then
            return nil
        end
        local _, _, _, icon = GetSpecializationInfoForClassID(cid, 1)
        return icon
    end

    --- Forever: a spec-ID-keyed set where each Forever spec ID stands for
    --- every retail spec of its class (a new table; the input is untouched).
    --- Retail: the input.
    function CludesUI.ForeverExpandSpecSet(set)
        if not CludesUI.IS_FOREVER or not set then
            return set
        end
        local t, result = FV(), {}
        for ident, val in pairs(set) do
            local ownerFrame = t.class[ident]
            if not (ownerFrame and CludesUI.FOREVER_CLASS_SPEC[ownerFrame] == ident) then
                result[ident] = val
            end
        end
        for ident, val in pairs(set) do
            local ownerFrame = t.class[ident]
            if ownerFrame and CludesUI.FOREVER_CLASS_SPEC[ownerFrame] == ident then
                local ids = t.specs[ownerFrame]
                for i = 1, #ids do
                    if result[ids[i]] == nil then
                        result[ids[i]] = val
                    end
                end
            end
        end
        return result
    end

    -- Store predicates for ForeverClassSpec / SpecFor (plain functions, so no
    -- call site builds a closure).
    function CludesUI.SpecHasEntry(ident, tbl)
        return tbl ~= nil and tbl[ident] ~= nil
    end
    function CludesUI.SpecHasStringEntry(ident, tbl)
        return tbl ~= nil and tbl[tostring(ident)] ~= nil
    end

    -- 5-column layout, sorted alphabetically left-to-right, top-to-bottom
    local NUM_COLS = 5
    local COL_LISTS = { { 1, 6, 11 }, { 2, 7, 12 }, { 3, 8, 13 }, { 4, 9 }, { 5, 10 } }
    -- WoW Forever: the class loop runs over no classes (it still hides the
    -- pooled rows) and one row per class is built instead, in two rows that
    -- need a shorter popup.
    local NO_CLASSES = {}
    local FOREVER_POPUP_H = 380

    local specPopup -- reusable popup frame

    function CludesUI:ShowSpecAssignPopup(options)
        local saved = options.db
        local dbKey = options.dbKey
        local presetKey = options.presetKey
        local defaultKey = options.defaultKey
        local allPresetKeysFn = options.allPresetKeys
        local onDefaultChanged = options.onDefaultChanged
        local onDone = options.onDone

        -- Ensure assignments table exists
        if not saved[dbKey] then
            saved[dbKey] = {}
        end
        if not saved[dbKey][presetKey] then
            saved[dbKey][presetKey] = {}
        end
        local assignments = saved[dbKey][presetKey]

        -- Build or reuse the popup
        if not specPopup then
            local FONT = CludesUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
            local COL_W = 165
            local COL_GAP = 12
            local CONTENT_LEFT = 41
            local CONTENT_RIGHT = 36
            local CONTENT_TOP = 120
            local CLASS_H = 32
            local CLASS_PAD_TOP = 4
            local CLASS_PAD_BOT = 2
            local SPEC_H = 28
            local CLASS_GAP = 10

            local POPUP_W = CONTENT_LEFT + CONTENT_RIGHT + NUM_COLS * COL_W + (NUM_COLS - 1) * COL_GAP
            local POPUP_H = 740
            local ppScale = CludesUI.GetPopupScale()

            -- Dimmer
            local dimmer = CreateFrame("Frame", "CUISpecAssignDimmer", UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)
            dimmer:EnableMouseWheel(true)
            dimmer:SetScript("OnMouseWheel", function() end)
            dimmer:Hide()
            dimmer:SetScale(ppScale)

            local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints()
            dimTex:SetColorTexture(0, 0, 0, 0.25)

            -- Popup frame
            local dialog = CreateFrame("Frame", "CUISpecAssignPopup", dimmer)
            dialog:SetScale(CludesUI.PopupBump(1))
            dialog:SetFrameStrata("FULLSCREEN_DIALOG")
            dialog:SetFrameLevel(dimmer:GetFrameLevel() + 10)

            local popFrame = CludesUI._popupFrames
            if popFrame then
                popFrame[#popFrame + 1] = { popup = dialog, dimmer = dimmer }
            end
            Pix.Size(dialog, POPUP_W, POPUP_H)
            Pix.Point(dialog, "CENTER", CludesUI._mainFrame, "CENTER", 0, 0)

            -- Background
            local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(0.062, 0.070, 0.082, 1)

            -- Rounded 1 px outline like the other popups (was a square 2 px edge).
            local BRD_A_SP = 0.15
            dialog._brd = CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, BRD_A_SP, backdrop)

            -- Title
            local title = dialog:CreateFontString(nil, "OVERLAY")
            title:SetFont(FONT, 22, "")
            title:SetTextColor(1, 1, 1, 1)
            Pix.Point(title, "TOP", dialog, "TOP", 0, -32)
            -- WoW Forever has no specs: its rows are classes, and so is the wording.
            title:SetText(
                CludesUI.IS_FOREVER and CludesUI.L("Assign Preset to Classes")
                    or CludesUI.L("Assign Preset to Specs")
            )
            dialog._title = title

            -- Subtitle
            local sub = dialog:CreateFontString(nil, "OVERLAY")
            sub:SetFont(FONT, 14, "")
            sub:SetTextColor(1, 1, 1, 0.45)
            Pix.Point(sub, "TOP", title, "BOTTOM", 0, -8)
            sub:SetWidth(POPUP_W - 60)
            sub:SetJustifyH("CENTER")
            sub:SetWordWrap(true)
            dialog._subtitle = sub

            -- Check All | Check Tanks | Check Healers | Check DPS | Uncheck All
            local LINK_Y = -103
            local LINK_GAP = 20

            local prevLink
            local function MakeLink(textValue)
                local button = CreateFrame("Button", nil, dialog)
                button:SetFrameLevel(dialog:GetFrameLevel() + 2)
                local labelFS = button:CreateFontString(nil, "OVERLAY")
                labelFS:SetFont(FONT, 14, "")
                labelFS:SetText(CludesUI.L(textValue))
                labelFS:SetTextColor(1, 1, 1, 0.45)
                labelFS:SetPoint("CENTER")
                button:SetSize(labelFS:GetStringWidth() + 4, 20)
                if prevLink then
                    local div = dialog:CreateTexture(nil, "OVERLAY", nil, 7)
                    div:SetColorTexture(1, 1, 1, 0.18)
                    if div.SetSnapToPixelGrid then
                        div:SetSnapToPixelGrid(false)
                        div:SetTexelSnappingBias(0)
                    end
                    Pix.Point(div, "LEFT", prevLink, "RIGHT", LINK_GAP / 2, 0)
                    div:SetWidth(1)
                    div:SetHeight(12)
                    button._div = div
                    Pix.Point(button, "LEFT", prevLink, "RIGHT", LINK_GAP, 0)
                else
                    Pix.Point(button, "TOPLEFT", dialog, "TOPLEFT", CONTENT_LEFT, LINK_Y)
                end
                button:SetScript("OnEnter", function()
                    labelFS:SetTextColor(1, 1, 1, 0.80)
                end)
                button:SetScript("OnLeave", function()
                    labelFS:SetTextColor(1, 1, 1, 0.45)
                end)
                prevLink = button
                return button
            end

            dialog._checkAll = MakeLink("Check All")
            dialog._checkTanks = MakeLink("Check Tanks")
            dialog._checkHealers = MakeLink("Check Healers")
            dialog._checkDPS = MakeLink("Check DPS")
            dialog._uncheckAll = MakeLink("Uncheck All")
            -- WoW Forever specs carry no role: the role links are hidden and
            -- Uncheck All sits right after Check All.
            if CludesUI.IS_FOREVER then
                dialog._checkTanks:Hide()
                dialog._checkTanks._div:Hide()
                dialog._checkHealers:Hide()
                dialog._checkHealers._div:Hide()
                dialog._checkDPS:Hide()
                dialog._checkDPS._div:Hide()
                local un = dialog._uncheckAll
                un:ClearAllPoints()
                Pix.Point(un, "LEFT", dialog._checkAll, "RIGHT", LINK_GAP, 0)
                un._div:ClearAllPoints()
                Pix.Point(un._div, "LEFT", dialog._checkAll, "RIGHT", LINK_GAP / 2, 0)
            end

            -- Column container frames
            dialog._columns = {}
            for colIdx = 1, NUM_COLS do
                local col = CreateFrame("Frame", nil, dialog)
                col:SetFrameLevel(dialog:GetFrameLevel() + 1)
                local colX = CONTENT_LEFT + (colIdx - 1) * (COL_W + COL_GAP)
                Pix.Point(col, "TOPLEFT", dialog, "TOPLEFT", colX, -CONTENT_TOP)
                Pix.Size(col, COL_W, POPUP_H - CONTENT_TOP - 80)
                col._rows = {}
                dialog._columns[colIdx] = col
            end

            -- Bottom area: default dropdown + Done button
            local BOTTOM_ROW_Y = 88
            local DEFAULT_DD_W = 280
            local DEFAULT_DD_H = 30

            -- Default Profile dropdown container (hidden by default)
            local defDDContainer = CreateFrame("Frame", nil, dialog)
            defDDContainer:SetFrameLevel(dialog:GetFrameLevel() + 2)
            Pix.Size(defDDContainer, POPUP_W - 52, 68)
            Pix.Point(defDDContainer, "BOTTOM", dialog, "BOTTOM", 0, BOTTOM_ROW_Y)
            defDDContainer:Hide()
            dialog._defDDContainer = defDDContainer

            local defDDLabel = defDDContainer:CreateFontString(nil, "OVERLAY")
            defDDLabel:SetFont(FONT, 14, "")
            defDDLabel:SetTextColor(1, 1, 1, 0.45)
            Pix.Point(defDDLabel, "BOTTOM", defDDContainer, "CENTER", 0, 7)
            defDDLabel:SetText(
                CludesUI.IS_FOREVER and CludesUI.L("Default Profile (for non-assigned classes)")
                    or CludesUI.L("Default Profile (for non-assigned specs)")
            )
            dialog._defDDLabel = defDDLabel

            local defDDBtn = CreateFrame("Button", nil, defDDContainer)
            defDDBtn:SetFrameLevel(defDDContainer:GetFrameLevel() + 2)
            Pix.Size(defDDBtn, DEFAULT_DD_W, DEFAULT_DD_H)
            Pix.Point(defDDBtn, "TOP", defDDContainer, "CENTER", 0, -7)

            local defDDBg = defDDBtn:CreateTexture(nil, "BACKGROUND")
            defDDBg:SetAllPoints()
            defDDBg:SetColorTexture(0.088, 0.098, 0.111, 0.9)

            dialog._defBrd = CludesUI.MakeRoundedBorder(defDDBtn, 1, 1, 1, 0.20, defDDBg)

            local defDDLbl = defDDBtn:CreateFontString(nil, "OVERLAY")
            defDDLbl:SetFont(FONT, 13, "")
            defDDLbl:SetPoint("LEFT", defDDBtn, "LEFT", 12, 0)
            defDDLbl:SetTextColor(1, 1, 1, 0.50)
            dialog._defDDLbl = defDDLbl

            local defArrow = MakeDropdownArrow(defDDBtn, 12, Pix)
            dialog._defDDBtn = defDDBtn

            -- Flash animation for error state on the default dropdown
            local defFlashFrame = CreateFrame("Frame", nil, defDDBtn)
            defFlashFrame:Hide()
            local defFlashElapsed = 0
            local DEF_FLASH_DUR = 0.7
            defFlashFrame:SetScript("OnUpdate", function(self, elapsed)
                defFlashElapsed = defFlashElapsed + elapsed
                if defFlashElapsed >= DEF_FLASH_DUR then
                    self:Hide()
                    dialog._defBrd:SetColor(1, 1, 1, 0.20)
                    return
                end
                local t = defFlashElapsed / DEF_FLASH_DUR
                local lr = lerp(0.9, 1, t)
                local lg = lerp(0.15, 1, t)
                local lb = lerp(0.15, 1, t)
                local la = lerp(0.7, 0.20, t)
                dialog._defBrd:SetColor(lr, lg, lb, la)
            end)
            dialog._flashDefaultDD = function()
                defFlashElapsed = 0
                dialog._defBrd:SetColor(0.9, 0.15, 0.15, 0.7)
                defFlashFrame:Show()
            end

            -- Default dropdown menu (popout list). Controller cursor: overlay
            -- parent (UIParent unless a controller cursor is loaded).
            local defMenu = CreateFrame("Frame", nil, CludesUI.OverlayParent())
            defMenu:SetFrameStrata("FULLSCREEN_DIALOG")
            defMenu:SetFrameLevel(300)
            defMenu:SetClampedToScreen(true)
            defMenu:SetSize(DEFAULT_DD_W, 4)
            defMenu:SetPoint("TOPLEFT", defDDBtn, "BOTTOMLEFT", 0, -2)
            defMenu:Hide()
            local defMenuBg = defMenu:CreateTexture(nil, "BACKGROUND")
            defMenuBg:SetAllPoints()
            defMenuBg:SetColorTexture(0.088, 0.098, 0.111, 0.98)
            dialog._defMenuBrd = CludesUI.MakeRoundedBorder(defMenu, 1, 1, 1, 0.20, defMenuBg)
            dialog._defMenu = defMenu
            dialog._defMenuItems = {}

            defDDBtn:SetScript("OnEnter", function()
                defDDBg:SetColorTexture(0.088, 0.098, 0.111, 0.98)
                defDDLbl:SetTextColor(1, 1, 1, 0.60)
                dialog._defBrd:SetColor(1, 1, 1, 0.30)
            end)
            defDDBtn:SetScript("OnLeave", function()
                if not defMenu:IsShown() then
                    defDDBg:SetColorTexture(0.088, 0.098, 0.111, 0.9)
                    defDDLbl:SetTextColor(1, 1, 1, 0.50)
                    dialog._defBrd:SetColor(1, 1, 1, 0.20)
                end
            end)
            defDDBtn:SetScript("OnClick", function()
                if defMenu:IsShown() then
                    defMenu:Hide()
                else
                    if dialog._rebuildDefMenu then
                        dialog._rebuildDefMenu()
                    end
                    defMenu:Show()
                    -- Controller cursor: move it into the list.
                    CludesUI.PadFocus(defMenu)
                end
            end)
            defDDBtn:HookScript("OnHide", function()
                defMenu:Hide()
            end)

            defMenu:SetScript("OnShow", function(self)
                local btnScale = defDDBtn:GetEffectiveScale()
                local uiScale = UIParent:GetEffectiveScale()
                self:SetScale(btnScale / uiScale)
                -- The outline seated before this scale: refit it.
                dialog._defMenuBrd:Fit()
                self:SetScript("OnUpdate", function(m)
                    if not defDDBtn:IsMouseOver() and not m:IsMouseOver() then
                        if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                            m:Hide()
                        end
                    end
                end)
            end)
            defMenu:SetScript("OnHide", function(self)
                self:SetScript("OnUpdate", nil)
                if defDDBtn:IsMouseOver() then
                    defDDBg:SetColorTexture(0.088, 0.098, 0.111, 0.98)
                    defDDLbl:SetTextColor(1, 1, 1, 0.60)
                    dialog._defBrd:SetColor(1, 1, 1, 0.30)
                else
                    defDDBg:SetColorTexture(0.088, 0.098, 0.111, 0.9)
                    defDDLbl:SetTextColor(1, 1, 1, 0.50)
                    dialog._defBrd:SetColor(1, 1, 1, 0.20)
                end
            end)
            CludesUI.TrackOverlay(defMenu)
            -- Controller cursor: its cancel press clicks the dropdown button,
            -- which folds the list.
            if CludesUI.PadCP() then
                defMenu.CloseButton = defDDBtn
            end

            -- Done button
            local ACC = CLUDES_GREEN
            local closeBtn = CreateFrame("Button", nil, dialog)
            closeBtn:SetFrameLevel(dialog:GetFrameLevel() + 2)
            Pix.Size(closeBtn, 200, 39)
            Pix.Point(closeBtn, "BOTTOM", dialog, "BOTTOM", 0, 38)
            local closeBg = closeBtn:CreateTexture(nil, "BACKGROUND")
            closeBg:SetAllPoints()
            closeBg:SetColorTexture(0.062, 0.070, 0.082, 0.92)
            local closeBrd = CludesUI.MakeRoundedBorder(closeBtn, ACC.r, ACC.g, ACC.b, 0.9, closeBg)
            local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY")
            closeLbl:SetFont(FONT, 16, "")
            Pix.Point(closeLbl, "CENTER", closeBtn, "CENTER", 0, 0)
            closeLbl:SetText(CludesUI.L("Done"))
            closeLbl:SetTextColor(ACC.r, ACC.g, ACC.b, 0.9)
            closeBtn:SetScript("OnEnter", function()
                closeLbl:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
                closeBrd:SetColor(ACC.r, ACC.g, ACC.b, 1)
            end)
            closeBtn:SetScript("OnLeave", function()
                closeLbl:SetTextColor(ACC.r, ACC.g, ACC.b, 0.9)
                closeBrd:SetColor(ACC.r, ACC.g, ACC.b, 0.9)
            end)
            dialog._closeBtn = closeBtn
            dialog._closeLbl = closeLbl

            -- Cancel button (hidden by default, shown when onCancel is provided)
            local cancelBtn = CreateFrame("Button", nil, dialog)
            cancelBtn:SetFrameLevel(dialog:GetFrameLevel() + 2)
            Pix.Size(cancelBtn, 200, 39)
            Pix.Point(cancelBtn, "BOTTOM", dialog, "BOTTOM", 0, 38)
            local cancelBg = cancelBtn:CreateTexture(nil, "BACKGROUND")
            cancelBg:SetAllPoints()
            cancelBg:SetColorTexture(0.062, 0.070, 0.082, 0.92)
            local cancelBrd = CludesUI.MakeRoundedBorder(cancelBtn, 1, 1, 1, 0.25, cancelBg)
            local cancelLbl = cancelBtn:CreateFontString(nil, "OVERLAY")
            cancelLbl:SetFont(FONT, 16, "")
            Pix.Point(cancelLbl, "CENTER", cancelBtn, "CENTER", 0, 0)
            cancelLbl:SetText(CludesUI.L("Cancel"))
            cancelLbl:SetTextColor(1, 1, 1, 0.50)
            cancelBtn:SetScript("OnEnter", function()
                cancelLbl:SetTextColor(1, 1, 1, 0.75)
                cancelBrd:SetColor(1, 1, 1, 0.40)
            end)
            cancelBtn:SetScript("OnLeave", function()
                cancelLbl:SetTextColor(1, 1, 1, 0.50)
                cancelBrd:SetColor(1, 1, 1, 0.25)
            end)
            cancelBtn:SetScript("OnClick", function()
                dimmer:Hide()
                if dialog._onCancel then
                    dialog._onCancel()
                end
            end)
            cancelBtn:Hide()
            dialog._cancelBtn = cancelBtn

            dialog:EnableMouse(true)

            dimmer:SetScript("OnMouseDown", function(self)
                if not dialog:IsMouseOver() then
                    self:Hide()
                    if dialog._onCancel then
                        dialog._onCancel()
                    end
                end
            end)

            CludesUI.PopupTakeKeys(dialog, dimmer)
            dialog:SetScript("OnKeyDown", function(self, key)
                if InCombatLockdown() then
                    return
                end
                if key == "ESCAPE" then
                    self:SetPropagateKeyboardInput(false)
                    dimmer:Hide()
                    if dialog._onCancel then
                        dialog._onCancel()
                    end
                else
                    self:SetPropagateKeyboardInput(true)
                end
            end)

            -- Controller Back takes the same route as Escape. It counts only when
            -- a controller is in use at the show, so the keyboard path never changes.
            if CludesUI.RegisterEscapeClose then
                CludesUI.RegisterEscapeClose(dimmer, {
                    padOnly = true,
                    onEscape = function()
                        dimmer:Hide()
                        if dialog._onCancel then
                            dialog._onCancel()
                        end
                    end,
                })
            end
            -- Controller cursor: the panel is a blocker, not a stop.
            CludesUI.PadHint(dialog, "nodepass")

            dialog._CLASS_H = CLASS_H
            dialog._CLASS_PAD_TOP = CLASS_PAD_TOP
            dialog._CLASS_PAD_BOT = CLASS_PAD_BOT
            dialog._SPEC_H = SPEC_H
            dialog._COL_W = COL_W
            dialog._CLASS_GAP = CLASS_GAP
            dialog._dimmer = dimmer
            dialog._POPUP_W = POPUP_W
            dialog._POPUP_H = POPUP_H
            specPopup = dialog
        end

        -- Update title / subtitle
        if options.title then
            specPopup._title:SetText(CludesUI.L(options.title))
        else
            specPopup._title:SetText(
                CludesUI.IS_FOREVER and CludesUI.L("Assign Preset to Classes")
                    or CludesUI.L("Assign Preset to Specs")
            )
        end
        if options.subtitle then
            specPopup._subtitle:SetText(CludesUI.L(options.subtitle))
        else
            local presetName
            if presetKey == "custom" then
                presetName = CludesUI.L("Custom")
            elseif presetKey == "cludesui" then
                presetName = "CludesUI"
            elseif presetKey and type(presetKey) == "string" and presetKey:sub(1, 5) == "user:" then
                presetName = presetKey:sub(6)
            else
                presetName = presetKey or ""
            end
            specPopup._subtitle:SetText(
                CludesUI.IS_FOREVER
                        and CludesUI.Lf("Select which classes you want %1$s to be assigned to", presetName)
                    or CludesUI.Lf("Select which specs you want %1$s to be assigned to", presetName)
            )
        end
        -- Per-call subtitle color (default dim white). Lets a caller render a red
        -- overwrite warning in the subtitle slot. Reset every call (popup is cached).
        if options.subtitleColor then
            local c = options.subtitleColor
            specPopup._subtitle:SetTextColor(c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or 1)
        else
            specPopup._subtitle:SetTextColor(1, 1, 1, 0.45)
        end
        -- Placement: a bottom warning (CDM export/import) drops into the blank
        -- space above the buttons -- the spec grid never fills the full height,
        -- so no resize is needed (the popup stays the same height as every other
        -- spec picker). Normal callers keep the subtitle under the title. The
        -- warning also renders 2px larger for emphasis.
        specPopup._subtitle:ClearAllPoints()
        Pix.Size(specPopup, specPopup._POPUP_W, CludesUI.IS_FOREVER and FOREVER_POPUP_H or specPopup._POPUP_H)
        specPopup._brd:Fit()
        local subFont = specPopup._subtitle:GetFont()
        if options.subtitleAtBottom then
            specPopup._subtitle:SetFont(subFont, 16, "")
            -- Buttons sit 38px up at 39px tall (top edge ~77px); ~30px gap above.
            Pix.Point(specPopup._subtitle, "BOTTOM", specPopup, "BOTTOM", 0, 107)
        else
            specPopup._subtitle:SetFont(subFont, 14, "")
            Pix.Point(specPopup._subtitle, "TOP", specPopup._title, "BOTTOM", 0, -8)
        end

        -- Update Done button text
        if specPopup._closeLbl then
            specPopup._closeLbl:SetText(CludesUI.L(options.buttonText or "Done"))
        end

        -- Populate columns
        local FONT = CludesUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
        local CLASS_H = specPopup._CLASS_H
        local CLASS_PAD_TOP = specPopup._CLASS_PAD_TOP
        local CLASS_PAD_BOT = specPopup._CLASS_PAD_BOT
        local SPEC_H = specPopup._SPEC_H
        local COL_W = specPopup._COL_W
        local CLASS_GAP = specPopup._CLASS_GAP
        local allCheckboxes = {}
        local BOX_SZ = 18
        local CHECK_INSET = 3

        -- Build lookup: specID -> presetKey for specs assigned to OTHER presets
        local lockedSpecs = {}
        local disabledSpecs = options.disabledSpecs or {}
        local lockedOnSpecs = options.lockedOnSpecs or {}
        local preCheckedSpecs = options.preCheckedSpecs
        do
            local fullMap = saved and saved[dbKey]
            if fullMap then
                for pKey, specList in pairs(fullMap) do
                    if pKey ~= presetKey and type(specList) == "table" then
                        for sID in pairs(specList) do
                            local dName
                            if pKey == "custom" then
                                dName = CludesUI.L("Custom")
                            elseif pKey == "cludesui" then
                                dName = "CludesUI"
                            elseif pKey:sub(1, 5) == "user:" then
                                dName = pKey:sub(6)
                            else
                                dName = pKey
                            end
                            lockedSpecs[sID] = dName
                        end
                    end
                end
            end
        end

        -- Pre-check specs if requested
        if preCheckedSpecs then
            for sID in pairs(preCheckedSpecs) do
                assignments[sID] = true
            end
        end
        -- Locked-on specs are always checked and cannot be toggled off.
        for sID in pairs(lockedOnSpecs) do
            assignments[sID] = true
        end

        -- Spec checkbox row at one column slot (pooled; built on first use).
        local function EnsureSpecRow(col, rowIdx)
            local row = col._rows[rowIdx]
            if not row then
                row = CreateFrame("Button", nil, col)
                col._rows[rowIdx] = row

                local box = CreateFrame("Frame", nil, row)
                Pix.Size(box, BOX_SZ, BOX_SZ)
                Pix.Point(box, "LEFT", row, "LEFT", 8, 0)
                box:SetFrameLevel(row:GetFrameLevel() + 1)
                local boxBg = box:CreateTexture(nil, "BACKGROUND")
                boxBg:SetAllPoints()
                boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
                row._boxBg = boxBg
                local boxBorder =
                    CludesUI.MakeRoundedBorder(box, BORDER_R, BORDER_G, BORDER_B, CB_BRD_A, boxBg)
                row._boxBorder = boxBorder
                local check = box:CreateTexture(nil, "ARTWORK")
                Pix.Point(check, "TOPLEFT", box, "TOPLEFT", CHECK_INSET, -CHECK_INSET)
                Pix.Point(check, "BOTTOMRIGHT", box, "BOTTOMRIGHT", -CHECK_INSET, CHECK_INSET)
                check:SetColorTexture(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 1)
                -- The outline's radius less the inset, so the fill's corners follow it.
                CludesUI.RoundBody(box, check, 1)
                row._check = check
                row._box = box

                local labelFS = row:CreateFontString(nil, "OVERLAY")
                labelFS:SetFont(FONT, 17, "")
                Pix.Point(labelFS, "LEFT", box, "RIGHT", 8, 0)
                labelFS:SetTextColor(1, 1, 1, 0.65)
                row._lbl = labelFS
            end
            return row
        end
        local ACC = CLUDES_GREEN
        local function UpdateVisual(r)
            if r._lockedOn then
                -- Always-on (e.g. the sync source): checked but locked/grayed.
                r._check:Show()
                r._boxBorder:SetColor(ACC.r, ACC.g, ACC.b, CB_ACT_BRD_A * 0.5)
                r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 0.5)
                r._lbl:SetTextColor(1, 1, 1, 0.4)
            elseif r._locked or r._disabled then
                r._check:Hide()
                r._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A * 0.4)
                r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 0.35)
                r._lbl:SetTextColor(1, 1, 1, 0.25)
            elseif r._checked then
                r._check:Show()
                r._boxBorder:SetColor(ACC.r, ACC.g, ACC.b, CB_ACT_BRD_A)
                r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
                r._lbl:SetTextColor(1, 1, 1, 0.65)
            else
                r._check:Hide()
                r._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A)
                r._boxBg:SetColorTexture(CB_BOX_R, CB_BOX_G, CB_BOX_B, 1)
                r._lbl:SetTextColor(1, 1, 1, 0.65)
            end
        end

        for colIdx = 1, NUM_COLS do
            local col = specPopup._columns[colIdx]
            for _, row in ipairs(col._rows) do
                row:Hide()
            end

            local entries = CludesUI.IS_FOREVER and NO_CLASSES or COL_LISTS[colIdx]
            local rowIdx = 0
            local yOff = 0
            local isFirstClass = true

            for _, classIdx in ipairs(entries) do
                local cls = SPEC_DATA[classIdx]

                if not isFirstClass then
                    yOff = yOff + CLASS_GAP
                end
                isFirstClass = false

                -- Class header
                yOff = yOff + CLASS_PAD_TOP
                rowIdx = rowIdx + 1
                local heading = col._rows[rowIdx]
                if not heading then
                    heading = CreateFrame("Frame", nil, col)
                    col._rows[rowIdx] = heading
                end
                Pix.Size(heading, COL_W, CLASS_H)
                heading:ClearAllPoints()
                Pix.Point(heading, "TOPLEFT", col, "TOPLEFT", 0, -yOff)
                heading:Show()

                if not heading._label then
                    heading._label = heading:CreateFontString(nil, "OVERLAY")
                    heading._label:SetFont(FONT, 18, "")
                    Pix.Point(heading._label, "BOTTOMLEFT", heading, "BOTTOMLEFT", 4, 4)
                end
                local clr = CLASS_COLOR_MAP[cls.class]
                if clr then
                    heading._label:SetTextColor(clr.r, clr.g, clr.b, 0.9)
                else
                    heading._label:SetTextColor(1, 1, 1, 0.7)
                end
                heading._label:SetText(
                    (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls.class]) or cls.name
                )
                yOff = yOff + CLASS_H + CLASS_PAD_BOT

                -- Spec checkboxes
                for _, specInfo in ipairs(cls.specs) do
                    rowIdx = rowIdx + 1
                    local row = EnsureSpecRow(col, rowIdx)
                    Pix.Size(row, COL_W, SPEC_H)
                    row:ClearAllPoints()
                    Pix.Point(row, "TOPLEFT", col, "TOPLEFT", 0, -yOff)
                    row:Show()

                    local locSpecName = specInfo.name
                    if GetSpecializationInfoByID then
                        local sn = select(2, GetSpecializationInfoByID(specInfo.id))
                        if sn and sn ~= "" then
                            locSpecName = sn
                        end
                    end
                    row._lbl:SetText(locSpecName)
                    row._specID = specInfo.id

                    local lockedBy = lockedSpecs[specInfo.id]
                    local disabledTip = disabledSpecs[specInfo.id]
                    local lockedOnTip = lockedOnSpecs[specInfo.id]
                    row._locked = lockedBy ~= nil
                    row._disabled = disabledTip ~= nil
                    row._lockedOn = lockedOnTip ~= nil and lockedOnTip ~= false

                    local checked = assignments[specInfo.id] == true
                    row._checked = checked
                    UpdateVisual(row)
                    allCheckboxes[#allCheckboxes + 1] = row

                    row:SetScript("OnClick", function(self)
                        if self._lockedOn or self._locked or self._disabled then
                            return
                        end
                        self._checked = not self._checked
                        assignments[specInfo.id] = self._checked or nil
                        UpdateVisual(self)
                    end)
                    row:SetScript("OnEnter", function(self)
                        if self._disabled and disabledTip then
                            CludesUI.ShowWidgetTooltip(self._box, CludesUI.DisabledTooltip(disabledTip))
                        elseif self._lockedOn and type(lockedOnTip) == "string" then
                            CludesUI.ShowWidgetTooltip(self._box, CludesUI.DisabledTooltip(lockedOnTip))
                        end
                        if self._lockedOn or self._locked or self._disabled then
                            return
                        end
                        self._lbl:SetTextColor(1, 1, 1, 0.90)
                    end)
                    row:SetScript("OnLeave", function(self)
                        CludesUI.HideWidgetTooltip()
                        if self._lockedOn or self._locked or self._disabled then
                            return
                        end
                        self._lbl:SetTextColor(1, 1, 1, 0.65)
                    end)

                    yOff = yOff + SPEC_H
                end
            end
        end

        -- Check All / Uncheck All wiring
        specPopup._checkAll:SetScript("OnClick", function()
            local EG2 = CLUDES_GREEN
            for _, row in ipairs(allCheckboxes) do
                if not row._locked and not row._disabled and not row._lockedOn then
                    row._checked = true
                    assignments[row._specID] = true
                    row._check:Show()
                    row._boxBorder:SetColor(EG2.r, EG2.g, EG2.b, CB_ACT_BRD_A)
                end
            end
        end)
        specPopup._uncheckAll:SetScript("OnClick", function()
            for _, row in ipairs(allCheckboxes) do
                if not row._locked and not row._disabled and not row._lockedOn then
                    row._checked = false
                    assignments[row._specID] = nil
                    row._check:Hide()
                    row._boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB_BRD_A)
                end
            end
        end)

        -- Role shortcuts: additively check every spec of one role, so roles
        -- can be combined (Tanks + Healers) without unchecking the rest.
        local function CheckRole(role)
            local EG2 = CLUDES_GREEN
            for _, row in ipairs(allCheckboxes) do
                if not row._locked and not row._disabled and not row._lockedOn and row._specID then
                    -- The by-id lookup is not registered on WoW Forever: no role there.
                    local specRole
                    if GetSpecializationInfoByID then
                        specRole = select(5, GetSpecializationInfoByID(row._specID))
                    end
                    if specRole == role then
                        row._checked = true
                        assignments[row._specID] = true
                        row._check:Show()
                        row._boxBorder:SetColor(EG2.r, EG2.g, EG2.b, CB_ACT_BRD_A)
                    end
                end
            end
        end
        specPopup._checkTanks:SetScript("OnClick", function()
            CheckRole("TANK")
        end)
        specPopup._checkHealers:SetScript("OnClick", function()
            CheckRole("HEALER")
        end)
        specPopup._checkDPS:SetScript("OnClick", function()
            CheckRole("DAMAGER")
        end)

        -- WoW Forever: one checkbox row per class (the client has one spec per
        -- class; the stores keep retail spec IDs). A row stands for every
        -- retail spec of its class and follows the class's owner: the first of
        -- its specs (class order) assigned anywhere, the one the spec lookups
        -- pick. The row reads ticked when this preset holds that spec, and
        -- locked when another preset holds it with no free spec ahead of it;
        -- a free spec ahead leaves the row open, because ticking it makes this
        -- preset the owner. Ticking assigns every spec of the class no other
        -- preset holds; unticking clears them. Specs of classes Forever does
        -- not have stay in the assignments untouched.
        if CludesUI.IS_FOREVER then
            local rowList = specPopup._fvRows or {}
            specPopup._fvRows = rowList
            local function LockedOn(ident)
                local val = lockedOnSpecs[ident]
                return val ~= nil and val ~= false
            end
            -- Label in the class colour at the given alpha.
            local function Tint(row, a)
                local c = row._fvClr
                if c then
                    row._lbl:SetTextColor(c.r, c.g, c.b, a)
                else
                    row._lbl:SetTextColor(1, 1, 1, a)
                end
            end
            local function State(row)
                local ids = row._fvIDs
                row._lockedOn, row._disabled, row._checked, row._locked = false, false, false, false
                row._fvOnTip, row._fvDisTip, row._fvBy = nil, nil, nil
                for i = 1, #ids do
                    local ident = ids[i]
                    if LockedOn(ident) then
                        row._lockedOn = true
                        if not row._fvOnTip and type(lockedOnSpecs[ident]) == "string" then
                            row._fvOnTip = lockedOnSpecs[ident]
                        end
                    end
                    local dis = disabledSpecs[ident]
                    if dis ~= nil then
                        row._disabled = true
                        if not row._fvDisTip and dis then
                            row._fvDisTip = dis
                        end
                    end
                end
                -- Owner: the first spec of the class assigned anywhere, in class
                -- order. Another preset's spec locks the row only when no free
                -- spec comes before it.
                local free = false
                for i = 1, #ids do
                    local ident = ids[i]
                    if assignments[ident] == true then
                        row._checked = true
                        break
                    end
                    if lockedSpecs[ident] then
                        if not free then
                            row._locked = true
                            row._fvBy = lockedSpecs[ident]
                        end
                        break
                    end
                    free = true
                end
                UpdateVisual(row)
                local _, _, _, a = row._lbl:GetTextColor()
                Tint(row, a)
            end
            local function SetOn(row, enabled)
                if row._lockedOn or row._locked or row._disabled then
                    return
                end
                local ids = row._fvIDs
                for i = 1, #ids do
                    local ident = ids[i]
                    if enabled then
                        if not lockedSpecs[ident] and disabledSpecs[ident] == nil then
                            assignments[ident] = true
                        end
                    elseif not LockedOn(ident) then
                        assignments[ident] = nil
                    end
                end
                State(row)
            end
            local classes = CludesUI.ForeverClasses()
            for num = 1, #classes do
                local token = classes[num]
                local col = specPopup._columns[((num - 1) % NUM_COLS) + 1]
                -- One row per class in a column, so the pool slot is the row number.
                local r = math.floor((num - 1) / NUM_COLS) + 1
                local row = EnsureSpecRow(col, r)
                Pix.Size(row, COL_W, SPEC_H)
                row:ClearAllPoints()
                Pix.Point(row, "TOPLEFT", col, "TOPLEFT", 0, -(CLASS_GAP + (r - 1) * (SPEC_H + CLASS_GAP)))
                row:Show()
                row._lbl:SetText(CludesUI.ForeverClassName(token))
                row._fvClr = CLASS_COLOR_MAP[token]
                row._fvIDs = CludesUI.ForeverClassSpecIDs(token)
                row._specID = nil
                rowList[num] = row
                State(row)
                row:SetScript("OnClick", function(self)
                    SetOn(self, not self._checked)
                end)
                row:SetScript("OnEnter", function(self)
                    if self._disabled and self._fvDisTip then
                        CludesUI.ShowWidgetTooltip(self._box, CludesUI.DisabledTooltip(self._fvDisTip))
                    elseif self._lockedOn and self._fvOnTip then
                        CludesUI.ShowWidgetTooltip(self._box, CludesUI.DisabledTooltip(self._fvOnTip))
                    elseif self._locked and self._fvBy then
                        CludesUI.ShowWidgetTooltip(
                            self._box,
                            CludesUI.Lf("Already assigned to %s", self._fvBy)
                        )
                    end
                    if self._lockedOn or self._locked or self._disabled then
                        return
                    end
                    Tint(self, 0.90)
                end)
                row:SetScript("OnLeave", function(self)
                    CludesUI.HideWidgetTooltip()
                    if self._lockedOn or self._locked or self._disabled then
                        return
                    end
                    Tint(self, 0.65)
                end)
            end
            for num = #classes + 1, #rowList do
                rowList[num] = nil
            end
            specPopup._checkAll:SetScript("OnClick", function()
                for i = 1, #rowList do
                    SetOn(rowList[i], true)
                end
            end)
            specPopup._uncheckAll:SetScript("OnClick", function()
                for i = 1, #rowList do
                    SetOn(rowList[i], false)
                end
            end)
        end

        -- Default Profile dropdown (populate phase)
        local selectedDefaultKey = defaultKey and saved[defaultKey] or nil

        if defaultKey and allPresetKeysFn then
            specPopup._defDDContainer:Show()

            local function DefPresetDisplayName(key)
                if not key then
                    return ""
                end
                if key == "custom" then
                    return CludesUI.L("Custom")
                end
                if key == "cludesui" then
                    return "CludesUI"
                end
                if key:sub(1, 5) == "user:" then
                    return key:sub(6)
                end
                return key
            end

            if selectedDefaultKey then
                specPopup._defDDLbl:SetText(DefPresetDisplayName(selectedDefaultKey))
                specPopup._defDDLbl:SetTextColor(1, 1, 1, 0.50)
            else
                specPopup._defDDLbl:SetText("")
                specPopup._defDDLbl:SetTextColor(1, 1, 1, 0.35)
            end

            specPopup._rebuildDefMenu = function()
                local itemList = specPopup._defMenuItems
                for _, itm in ipairs(itemList) do
                    itm:Hide()
                end

                local presetList = allPresetKeysFn()
                local mH = 4
                local ITEM_FONT = CludesUI._font
                    or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

                for position, record in ipairs(presetList) do
                    local itm = itemList[position]
                    if not itm then
                        itm = CreateFrame("Button", nil, specPopup._defMenu)
                        itm:SetHeight(26)
                        itm:SetFrameLevel(specPopup._defMenu:GetFrameLevel() + 1)
                        local labelFS = itm:CreateFontString(nil, "OVERLAY")
                        labelFS:SetFont(ITEM_FONT, 13, "")
                        labelFS:SetPoint("LEFT", itm, "LEFT", 10, 0)
                        labelFS:SetTextColor(0.55, 0.60, 0.65, 1)
                        itm._lbl = labelFS
                        local highlight = itm:CreateTexture(nil, "ARTWORK")
                        highlight:SetAllPoints()
                        highlight:SetColorTexture(1, 1, 1, 1)
                        highlight:SetAlpha(0)
                        itm._hl = highlight
                        itm:SetScript("OnEnter", function()
                            labelFS:SetTextColor(1, 1, 1, 1)
                            highlight:SetAlpha(0.08)
                        end)
                        itm:SetScript("OnLeave", function()
                            local isSel = (itm._key == selectedDefaultKey)
                            labelFS:SetTextColor(0.55, 0.60, 0.65, 1)
                            highlight:SetAlpha(isSel and 0.04 or 0)
                        end)
                        itemList[position] = itm
                    end
                    itm:SetPoint("TOPLEFT", specPopup._defMenu, "TOPLEFT", 1, -mH)
                    itm:SetPoint("TOPRIGHT", specPopup._defMenu, "TOPRIGHT", -1, -mH)
                    itm._lbl:SetText(record.name)
                    itm._key = record.key
                    local isSel = (record.key == selectedDefaultKey)
                    itm._hl:SetAlpha(isSel and 0.04 or 0)
                    itm:SetScript("OnClick", function()
                        selectedDefaultKey = record.key
                        specPopup._defDDLbl:SetText(record.name)
                        specPopup._defDDLbl:SetTextColor(1, 1, 1, 0.50)
                        specPopup._defMenu:Hide()
                    end)
                    itm:Show()
                    mH = mH + 26
                end
                specPopup._defMenu:SetHeight(mH + 4)
            end
        else
            specPopup._defDDContainer:Hide()
        end

        -- Store callbacks on the popup for dimmer/ESC access
        specPopup._onCancel = options.onCancel

        -- Show/hide Cancel button and reposition Done button
        local BTN_GAP = 12
        if options.onCancel then
            specPopup._cancelBtn:Show()
            specPopup._closeBtn:ClearAllPoints()
            Pix.Point(specPopup._closeBtn, "BOTTOMRIGHT", specPopup, "BOTTOM", -(BTN_GAP / 2), 38)
            specPopup._cancelBtn:ClearAllPoints()
            Pix.Point(specPopup._cancelBtn, "BOTTOMLEFT", specPopup, "BOTTOM", (BTN_GAP / 2), 38)
        else
            specPopup._cancelBtn:Hide()
            specPopup._closeBtn:ClearAllPoints()
            Pix.Point(specPopup._closeBtn, "BOTTOM", specPopup, "BOTTOM", 0, 38)
        end
        -- Controller cursor: its cancel press backs out through a visible Cancel.
        if CludesUI.PadCP() then
            specPopup.CloseButton = options.onCancel and specPopup._cancelBtn or nil
        end

        -- Done button: validate default selection if spec feature is active
        specPopup._closeBtn:SetScript("OnClick", function()
            if defaultKey and allPresetKeysFn and not selectedDefaultKey then
                specPopup._flashDefaultDD()
                return
            end
            if defaultKey and selectedDefaultKey then
                saved[defaultKey] = selectedDefaultKey
                if onDefaultChanged then
                    onDefaultChanged()
                end
            end
            specPopup._dimmer:Hide()
            if options.onConfirm then
                options.onConfirm(assignments)
            elseif onDone then
                onDone()
            end
        end)

        specPopup._dimmer:Show()
        -- Controller cursor: move it into the popup.
        CludesUI.PadFocus(specPopup)
    end
end
