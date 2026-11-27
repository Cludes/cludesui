if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_AuraBuffReminders_Options.lua
--  Registers the AuraBuff Reminders module with CludesUI
--  Two pages: Auras, Buffs & Consumables | Talent Reminders | Unlock Mode
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUIAuraBuffReminders"
local ns = CUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not ns then return end -- module disabled: no options page

local PAGE_REMINDERS = "Auras, Buffs & Consumables"
local PAGE_TALENTS = "Talent Reminders"
local PAGE_UNLOCK = "Layout Mode"

-- WoW Forever: the page keeps CORE, DISPLAY and RAID BUFFS (that client's
-- locations and its own buffs) and swaps every other retail section for the one
-- Forever section (Camp Benefits + custom spell IDs); the Talent Reminders
-- page does not exist there.
local FOREVER = CUI.IS_FOREVER == true
-- The Mage Armors and Class Buffs slots are the WOW FOREVER rows that are
-- class-only. Class never changes mid-session, so unlike the Beacon M+ row no
-- watcher is needed.
local MAGE = FOREVER and select(2, UnitClass("player")) == "MAGE"

local SECTION_CORE = "CORE"
local SECTION_FOREVER = "WOW FOREVER"
local SECTION_DISPLAY = "DISPLAY"
local SECTION_RAID_BUFFS = "RAID BUFFS"
local SECTION_AURAS = "AURAS"
local SECTION_CONSUMABLES = "CONSUMABLES"
local SECTION_ROGUE = "ROGUE POISONS"
local SECTION_PALADIN = "PALADIN RITES"
local SECTION_SHAMAN = "SHAMAN IMBUES & SHIELDS"
local SECTION_WARLOCK = "WARLOCK"
local SPECIAL_WHERE_TIP =
    "Pick which content these reminders appear in.\nRested areas (cities and inns) always stay hidden."

CUI.AtOptionsLogin(function()
    local PP = CUI.PanelPP
    -- Page reuse (CludesUI_FramePool.lua): a frame made under a page pool
    -- host comes from the pool and is dressed again by every later build; under
    -- any other parent it is a plain new frame.
    local Pool = CUI._Pool
    local CreateFrame = Pool.CreateFrame

    local function GetABROptOutline() return CUI.GetFontOutlineFlag("auraBuff") end

    ---------------------------------------------------------------------------
    --  DB helpers
    ---------------------------------------------------------------------------
    local db
    C_Timer.After(0, function() db = _G._CUABR_AceDB end)

    local function DB()
        if not db then db = _G._CUABR_AceDB end
        return db and db.profile
    end
    -- One profile table's accessor (nil until the profile loads).
    local function Section(key)
        return function()
            local profile = DB()
            return profile and profile[key]
        end
    end
    local DDB = Section("display")
    local RDB = Section("raidBuffs")
    local ADB = Section("auras")
    local CDB = Section("consumables")
    local FDB = Section("forever") -- the WoW Forever section (nil on retail)

    -- The reminder name font: the display's own pick, else the module font.
    local function GetNameFontPath()
        local display = DDB()
        local pick = display and display.nameFont
        if pick and pick ~= "__global" and CUI.ResolveFontName then
            local path = CUI.ResolveFontName(pick)
            if path and path ~= "" then return path end
        end
        return CUI.GetFontPath("auraBuff") or "Fonts\\ARIALN.TTF"
    end

    -- The text's own point and the icon's point it sits on (as live).
    local PREVIEW_TEXT_ANCHORS = _G._CUABR_TEXT_ANCHORS
    local function GetPreviewTextAnchor(d)
        local pair = PREVIEW_TEXT_ANCHORS[(d and d.textAnchor) or "BOTTOM"] or PREVIEW_TEXT_ANCHORS.BOTTOM
        return pair[1], pair[2]
    end

    ---------------------------------------------------------------------------
    --  Refresh
    ---------------------------------------------------------------------------
    local function RequestRefresh()
        if _G._CUABR_RequestRefresh then _G._CUABR_RequestRefresh() end
    end

    ---------------------------------------------------------------------------
    --  Preview Header shows potential buff/aura icons for current class/spec
    ---------------------------------------------------------------------------
    local _previewHeaderBuilder
    local _previewIcons = {}
    local _previewContainer
    local _previewHintFS

    local function IsPreviewHintDismissed() return CludesUIDB and CludesUIDB.previewHintDismissed end

    local function Known(id)
        return id
            and (
                C_SpellBook.IsSpellKnown(id)
                or C_SpellBook.IsSpellInSpellBook(id, Enum.SpellBookSpellBank.Player, false)
            )
    end
    local function Tex(id)
        return _G._CUABR_Tex and _G._CUABR_Tex(id)
            or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id))
            or 134400
    end

    -- A buff's preview label: its first word, a short name for a few, or
    -- one word for a whole class family (poisons, imbues, shields).
    local LABEL_OVERRIDES = {
        ["Battle Stance"] = "Stance",
        ["Defensive Stance"] = "Stance",
        ["Berserker Stance"] = "Stance",
        ["Devotion Aura"] = "Aura",
        ["Power Word: Fortitude"] = "Fortitude",
        ["Arcane Intellect"] = "Intellect",
        ["Battle Shout"] = "Shout",
    }
    local LABEL_CLASS_OVERRIDES = {
        ROGUE = "Poison",
        SHAMAN_IMBUE = "Weapon",
        SHAMAN_SHIELD = "Shield",
    }
    local function ShortLabel(name, family)
        local word = family and LABEL_CLASS_OVERRIDES[family]
        if word then return CUI.L(word) end
        return LABEL_OVERRIDES[name] or name:match("^(%S+)") or name
    end

    -- The class consumable families: only the first enabled, known one
    -- shows. [class] = { data global, label family }.
    local CLASS_FAMILIES = {
        ROGUE = { "_CUABR_ROGUE_POISONS", "ROGUE" },
        PALADIN = { "_CUABR_PALADIN_RITES" },
        SHAMAN = { "_CUABR_SHAMAN_IMBUES", "SHAMAN_IMBUE" },
    }
    -- The general consumables, in preview order: key, label, icon (called
    -- only when the row is on). Healthstone is on while unset, as its toggle.
    local function ItemIcon(id, fallback)
        return function() return C_Item.GetItemIconByID(id) or fallback end
    end
    local GENERAL_CONSUMABLES = {
        {
            key = "flask",
            label = "Flask",
            icon = function() return 134830 end,
        },
        {
            key = "food",
            label = "Food",
            icon = function() return 134062 end,
        },
        { key = "augment_rune", label = "Rune", icon = ItemIcon(259085, 134400) },
        { key = "healthstone", label = "Stone", icon = ItemIcon(5512, 134400), onWhenUnset = true },
        { key = "inky_black", label = "Inky", icon = ItemIcon(124640, 136122) },
    }

    local function ForSpec(specs, specID)
        if not specs then return true end
        for _, spec in ipairs(specs) do
            if spec == specID then return true end
        end
        return false
    end

    -- Every icon the preview can show for the player's class and spec, in
    -- order: enabled raid buffs, enabled auras (one Beacon), the class
    -- consumable (else a weapon oil), then the general consumables. None
    -- on WoW Forever (no preview, and the spec lookups are retail-only).
    local function CollectPreviewIcons()
        local icons = {}
        if FOREVER then return icons end
        local function Add(texture, label, cat, key)
            icons[#icons + 1] = { texture = texture, label = label, cat = cat, itemKey = key }
        end
        local function AddSpell(entry, cat, family)
            Add(
                Tex(entry.castSpell),
                ShortLabel(_G._CUABR_SpellName(entry.castSpell, entry.name), family),
                cat,
                entry.key
            )
        end
        local _, class = UnitClass("player")
        local specIdx = GetSpecialization()
        local specID = specIdx and GetSpecializationInfo(specIdx) or nil
        local rb, au, co = RDB(), ADB(), CDB()

        for _, buff in ipairs(_G._CUABR_RAID_BUFFS or {}) do
            if
                buff.class == class
                and Known(buff.castSpell)
                and rb
                and rb.enabled
                and rb.enabled[buff.key]
            then
                AddSpell(buff, "raidbuff")
            end
        end

        local beacon = false
        for _, aura in ipairs(_G._CUABR_AURAS or {}) do
            if
                aura.class == class
                and Known(aura.castSpell)
                and au
                and au.enabled
                and au.enabled[aura.key]
                and ForSpec(aura.specs, specID)
            then
                local isBeacon = aura.key == "bol" or aura.key == "bof"
                if not (isBeacon and beacon) then AddSpell(aura, "aura") end
                beacon = beacon or isBeacon
            end
        end

        local on = co and co.enabled
        local family = CLASS_FAMILIES[class]
        if family then
            for _, entry in ipairs(_G[family[1]] or {}) do
                if Known(entry.castSpell) and on and on[entry.key] then
                    AddSpell(entry, "consumable", family[2])
                    break
                end
            end
        elseif on and on.weapon_enchant then
            local oils = _G._CUABR_WEAPON_ENCHANT_ITEMS or {}
            if #oils > 0 then
                Add(oils[1].icon or 134400, CUI.L("Weapon"), "consumable", "weapon_enchant")
            end
        end

        for _, entry in ipairs(GENERAL_CONSUMABLES) do
            local value = on and on[entry.key]
            if value or (entry.onWhenUnset and on and value == nil) then
                Add(entry.icon(), CUI.L(entry.label), "consumable", entry.key)
            end
        end
        return icons
    end

    -- The preview icons' size (width, height after the icon shape) and gap.
    local function IconMetrics(d)
        local sz = math.floor((_G._CUABR_ICON_SIZE or 40) * ((d and d.scale) or 1.0) + 0.5)
        local h = sz
        if d and d.iconShape and d.iconShape ~= "none" then
            sz, h = ns.IconDimensions(sz, d)
        end
        return sz, h, (d and d.iconSpacing) or 8
    end

    -- x of the first preview icon's center from the container's TOP, following the live grow
    -- direction: Grow Right pins the row's left end and Grow Left its right end to the page's
    -- content column (container edge + CONTENT_PAD); Grow Centered centers the row.
    local function PreviewStartX(d, count, sz, spacing, boxW)
        local growDir = d and d.growDirection
        local edgeX = boxW / 2 - CUI.CONTENT_PAD
        if growDir == "RIGHT" then return -edgeX + (sz / 2) end
        local totalW = (count * sz) + ((count - 1) * spacing)
        if growDir == "LEFT" then return edgeX - totalW + (sz / 2) end
        return -(totalW / 2) + (sz / 2)
    end

    -- Places the first limit preview icons (default all) along the row,
    -- skipping a slot with no frame.
    local function PlaceIcons(d, sz, spacing, limit)
        local x = PreviewStartX(d, #_previewIcons, sz, spacing, _previewContainer:GetWidth())
        for i = 1, limit or #_previewIcons do
            local button = _previewIcons[i].frame
            if button then
                button:ClearAllPoints()
                button:SetPoint("TOP", button:GetParent(), "TOP", x + (i - 1) * (sz + spacing), 0)
            end
        end
    end

    local _eabrHeaderBaseH = 0
    local PREVIEW_H = 80

    -- One preview icon dressed as live: size, opacity, border, glow (the
    -- live renderer's own spec, nil = off) and its text.
    local function StyleIcon(button, d, sz, iconH, glowSpec)
        button:SetSize(sz, iconH)
        button:SetAlpha(d.opacity or 1.0)
        if _G._CUABR_ApplyIconBorder then _G._CUABR_ApplyIconBorder(button, false) end
        if not button._glowWrapper then
            local wrap = CreateFrame("Frame", nil, button)
            wrap:SetAllPoints(button)
            wrap:SetFrameLevel(button:GetFrameLevel() + 4)
            button._glowWrapper = wrap
        end
        local wrap = button._glowWrapper
        if glowSpec then
            local extra = button._eabrShape and ns.IconGlowExtra(button, true) or CUI.Glows.PANEL_EXTRA
            CUI.Glows.StartSpecGlow(wrap, glowSpec, sz, iconH, "icon", extra)
            wrap:Show()
        else
            CUI.Glows.StopAllGlows(wrap)
            wrap:Hide()
        end
        local text = button._text
        if d.showText then
            local textColor = d.textColor or { r = 1, g = 1, b = 1 }
            CUI.ApplyModuleFont(text, GetNameFontPath(), d.textSize or 11, "auraBuff")
            text:ClearAllPoints()
            local own, onIcon = GetPreviewTextAnchor(d)
            text:SetPoint(own, button, onIcon, d.textXOffset or 0, d.textYOffset or -2)
            text:SetTextColor(textColor.r, textColor.g, textColor.b, 1)
            text:Show()
        else
            text:Hide()
        end
        button:Show()
    end

    local function SyncPreviewHeader()
        if not _previewIcons or #_previewIcons == 0 then return end
        local display = DDB()
        if not display then return end
        local sz, iconH, spacing = IconMetrics(display)
        local glowSpec = _G._CUABR_GlowSpec and _G._CUABR_GlowSpec(display, {})
        -- Up to the first slot with no frame.
        local placed = 0
        while _previewIcons[placed + 1] and _previewIcons[placed + 1].frame do
            placed = placed + 1
        end
        PlaceIcons(display, sz, spacing, placed)
        for i = 1, placed do
            StyleIcon(_previewIcons[i].frame, display, sz, iconH, glowSpec)
        end

        -- The row is centred in the header, as tall as the icons plus any
        -- text hanging below them; the header itself stays 80 (plus the hint).
        local overhang = display.showText and (math.abs(display.textYOffset or -2) + (display.textSize or 11))
            or 0
        if _previewContainer then
            _previewContainer:SetHeight(iconH + overhang)
            _previewContainer:ClearAllPoints()
            _previewContainer:SetPoint("CENTER", _previewContainer:GetParent(), "CENTER", 0, 0)
        end
        _eabrHeaderBaseH = PREVIEW_H
        local hintH = (_previewHintFS and _previewHintFS:IsShown()) and 35 or 0
        -- Silent: resizing the header never triggers scroll compensation
        -- (the height rarely changes here).
        CUI:SetContentHeaderHeightSilent(PREVIEW_H + hintH)
    end

    local function ApplyIconBorders()
        if _G._CUABR_ApplyAllIconBorders then _G._CUABR_ApplyAllIconBorders() end
        RequestRefresh()
        SyncPreviewHeader()
    end

    ---------------------------------------------------------------------------
    --  Preview click-to-scroll infrastructure
    ---------------------------------------------------------------------------

    -- Rebuilds the preview header (SetContentHeader tears it down and builds
    -- it again). No preview header on WoW Forever.
    local function RebuildPreviewHeader()
        if FOREVER then return end
        CUI:SetContentHeader(_previewHeaderBuilder)
    end

    -- Moves the existing preview icons into place without rebuilding the
    -- header (no scroll jump).
    local function RelayoutPreviewIcons()
        if not _previewIcons or #_previewIcons == 0 then return end
        local display = DDB()
        local sz, _, spacing = IconMetrics(display)
        PlaceIcons(display, sz, spacing)
    end

    local _eabrGlow -- made on first click: Widgets helpers load with the panel
    local _eabrClickMappings = {}
    local _eabrHitOverlays = {}

    local function EABRPlaySettingGlow(targetFrame)
        _eabrGlow = _eabrGlow or CUI.MakeSettingGlow({ color = CUI.CLUDES_GREEN })
        _eabrGlow(targetFrame)
    end

    local function EABRNavigateToSetting(key)
        local m = _eabrClickMappings[key]
        if not m or not m.section or not m.target then return end

        CUI.DismissPreviewHint(_previewHintFS, _eabrHeaderBaseH, 35, 5)

        local sf = CUI._scrollFrame
        if not sf then return end

        -- The glow plays a moment later: a target of the page pool that is
        -- dressed again for another row by then belongs to a newer build.
        local target = m.target
        local gen = Pool.Gen(target)
        local function PlayLater()
            if Pool.Gen(target) ~= gen or Pool.IsIdle(target) then return end
            EABRPlaySettingGlow(target)
        end

        local child = sf.GetScrollChild and sf:GetScrollChild()
        if child and target.GetTop and child.GetTop then
            local targetTop = target:GetTop()
            local childTop = child:GetTop()
            if targetTop and childTop then
                local scrollPos = math.max(0, childTop - targetTop - 40)
                CUI.SmoothScrollTo(scrollPos)
                C_Timer.After(0.15, PlayLater)
                return
            end
        end

        -- Fallback for layouts where the scroll child isn't ready yet.
        local _, _, _, _, headerY = m.section:GetPoint(1)
        if headerY then
            local scrollPos = math.max(0, math.abs(headerY) - 40)
            CUI.SmoothScrollTo(scrollPos)
        end
        C_Timer.After(0.15, PlayLater)
    end

    local function EABRCreateHitOverlay(element, mappingKey, frameLevelOverride)
        local button = CUI.CreatePreviewHitOverlay(
            element,
            EABRNavigateToSetting,
            mappingKey,
            false,
            frameLevelOverride
        )
        _eabrHitOverlays[#_eabrHitOverlays + 1] = button
        return button
    end

    -- One preview icon: the spell texture, the live border (the reminder
    -- icons' own helper, so the header matches them exactly) and its text
    -- on an overlay above the icon.
    local function MakePreviewIcon(container, data, d, sz, iconH, x)
        local button = CreateFrame("Button", nil, container)
        button:SetSize(sz, iconH)
        button:EnableMouse(true)
        button:SetPoint("TOP", container, "TOP", x, 0)
        button:SetAlpha((d and d.opacity) or 1.0)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:SetTexture(data.texture or 134400)
        if icon.SetSnapToPixelGrid then
            icon:SetSnapToPixelGrid(false)
            icon:SetTexelSnappingBias(0)
        end
        button._icon = icon
        _G._CUABR_ApplyIconBorder(button, false)

        local layer = CreateFrame("Frame", nil, button)
        layer:SetAllPoints()
        layer:SetFrameLevel(button:GetFrameLevel() + 5)
        local text = layer:CreateFontString(nil, "OVERLAY")
        local own, onIcon = GetPreviewTextAnchor(d)
        text:SetPoint(own, button, onIcon, (d and d.textXOffset) or 0, (d and d.textYOffset) or -2)
        CUI.ApplyModuleFont(text, GetNameFontPath(), (d and d.textSize) or 11, "auraBuff")
        local textColor = (d and d.textColor) or { r = 1, g = 1, b = 1 }
        text:SetTextColor(textColor.r, textColor.g, textColor.b, 1)
        text:SetText(data.label or "")
        if not (d and d.showText) then text:Hide() end
        button._text = text
        return button
    end

    -- The hint under the icons, kept across builds (out of the container's
    -- pool). Returns the height it adds.
    local function PlacePreviewHint(hdr, container)
        if _previewHintFS and not _previewHintFS:GetParent() then _previewHintFS = nil end
        if IsPreviewHintDismissed() then
            if _previewHintFS then _previewHintFS:Hide() end
            return 0
        end
        if not _previewHintFS then
            _previewHintFS = Pool.Keep(CUI.MakeFont(container, 11, nil, 1, 1, 1))
            _previewHintFS:SetAlpha(0.45)
            _previewHintFS:SetText(CUI.L("Click elements to scroll to and highlight their options"))
        end
        _previewHintFS:SetParent(container)
        _previewHintFS:ClearAllPoints()
        _previewHintFS:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 15)
        _previewHintFS:Show()
        return 35
    end

    -- The header: one icon per reminder the player could see, click to
    -- scroll to its setting. The container and icons are kept across
    -- builds, and a build with the same number of icons only re-dresses
    -- them (a tab switch then costs no frame churn).
    _previewHeaderBuilder = function(hdr, hdrW)
        local icons = CollectPreviewIcons()
        local display = DDB()

        -- The levels the first build gave the container and its icons (a
        -- kept header root's own dress can raise what it holds).
        if _previewContainer and #_previewIcons == #icons then
            local boxFrame = _previewContainer
            boxFrame:SetParent(hdr) -- may have been orphaned by ClearContentHeader
            boxFrame:SetFrameLevel(hdr:GetFrameLevel() + 1)
            boxFrame:ClearAllPoints()
            boxFrame:SetPoint("CENTER", hdr, "CENTER", 0, 0)
            boxFrame:SetSize(hdrW, boxFrame:GetHeight())
            boxFrame:Show()
            for i, entry in ipairs(_previewIcons) do
                local button, data = entry.frame, icons[i]
                if button then
                    button:SetFrameLevel(boxFrame:GetFrameLevel() + 1)
                    if data then
                        if button._icon then button._icon:SetTexture(data.texture or 134400) end
                        if button._text then button._text:SetText(data.label or "") end
                        entry.data = data
                    end
                end
            end
            SyncPreviewHeader()
            -- The full build's height (never nil, which would collapse the header).
            return PREVIEW_H + ((not IsPreviewHintDismissed()) and 35 or 0)
        end

        local sz, iconH, spacing = IconMetrics(display)
        local showText = display and display.showText
        local overhang = showText
                and (math.abs((display and display.textYOffset) or -2) + ((display and display.textSize) or 11))
            or 0
        if _previewContainer then
            _previewContainer:SetParent(hdr)
            _previewContainer:ClearAllPoints()
        else
            -- Pool.Keep: out of its host's pool, so no later build hands it out as another frame.
            _previewContainer = Pool.Keep(CreateFrame("Frame", nil, hdr))
        end
        local container = _previewContainer
        container:SetFrameLevel(hdr:GetFrameLevel() + 1)
        container:SetSize(hdrW, iconH + overhang)
        container:SetPoint("CENTER", hdr, "CENTER", 0, 0)
        container:Show()

        -- The old set goes before the new one is made: on a pool host the
        -- icons are handed back in order and dressed again.
        Pool.Begin(container)
        for _, entry in ipairs(_previewIcons) do
            if entry.frame then entry.frame:Hide() end
        end
        wipe(_previewIcons)
        local x = PreviewStartX(display, #icons, sz, spacing, hdrW)
        for i, data in ipairs(icons) do
            local button = MakePreviewIcon(container, data, display, sz, iconH, x + (i - 1) * (sz + spacing))
            _previewIcons[i] = { frame = button, data = data }
        end
        SyncPreviewHeader() -- glows

        -- Each icon leads to its own row (else its category); a shown text to Show Name.
        wipe(_eabrHitOverlays)
        local level = container:GetFrameLevel() + 20
        for _, entry in ipairs(_previewIcons) do
            local data = entry.data
            EABRCreateHitOverlay(
                entry.frame,
                data.itemKey and ("item:" .. data.itemKey) or data.cat or "display",
                level
            )
            if showText then EABRCreateHitOverlay(entry.frame._text, "showText", level) end
        end

        _eabrHeaderBaseH = PREVIEW_H
        return PREVIEW_H + PlacePreviewHint(hdr, container)
    end

    ---------------------------------------------------------------------------
    --  Per-section "Where to Show" + "Show When" multi-selects. The stored
    --  table keeps only unchecked buckets (value false); an absent bucket =
    --  shown. Buckets mirror EABR.CurrentWhereBucket in the core file.
    ---------------------------------------------------------------------------
    local WHERE_ITEMS = {
        { key = "open_world", label = "Open World" },
        { key = "raid_mythic", label = "Mythic Raid" },
        { key = "raid_heroic", label = "Heroic Raid" },
        { key = "raid_normal_lfr", label = "Normal/LFR Raid" },
        { key = "dungeon_mythic", label = "Mythic Dungeons" },
        { key = "dungeon_nonmythic", label = "Non-Mythic Dungeons" },
        { key = "timewalking", label = "Timewalking" },
        { key = "delve", label = "Delve" },
        { key = "lair", label = "Lair" },
        { key = "scenario", label = "Scenario" },
        -- Orthogonal state gate (not a location): unchecking hides this
        -- section while in combat.
        { key = "in_combat", label = "In Combat" },
    }
    -- WoW Forever buckets: vanilla dungeons report Normal difficulty and its
    -- raids the legacy 40/20-player ids (mapped in the core file), so Raid
    -- Buffs there offers three locations plus the combat gate.
    local FOREVER_WHERE_ITEMS = {
        { key = "open_world", label = "Open World" },
        { key = "dungeon_nonmythic", label = "Dungeons" },
        { key = "raid_normal_lfr", label = "Raids" },
        { key = "in_combat", label = "In Combat" },
    }
    -- The WoW Forever section never shows in combat: no combat gate to offer
    local FOREVER_SECTION_WHERE_ITEMS = {
        { key = "open_world", label = "Open World" },
        { key = "dungeon_nonmythic", label = "Dungeons" },
        { key = "raid_normal_lfr", label = "Raids" },
    }
    local SHOWWHEN_ITEMS = {
        { key = "othersMissing", label = "Others are missing my buff" },
        { key = "iAmMissing", label = "I am missing others' buffs" },
    }
    local GROW_DIR_VALUES = { CENTER = "Grow Centered", LEFT = "Grow Left", RIGHT = "Grow Right" }
    local GROW_DIR_ORDER = { "CENTER", "LEFT", "RIGHT" }

    -- Values are stored explicitly (true/false) rather than nil-for-on: the
    -- SavedVariables layer re-merges default keys on load, so an absent
    -- bucket whose default is false would silently flip back off across a
    -- logout.
    local function WhereGet(store)
        return function(keyName)
            local tbl = store()
            return not (tbl and tbl[keyName] == false)
        end
    end
    local function WhereSet(store, changed)
        return function(keyName, value)
            local tbl = store(true)
            if not tbl then return end
            tbl[keyName] = value and true or false
            if changed then changed() end
        end
    end
    local function WhenGet(store)
        return function(keyName)
            local tbl = store()
            return tbl and tbl[keyName] == true
        end
    end
    local function WhenSet(store, changed)
        return function(keyName, value)
            local tbl = store()
            if not tbl then return end
            tbl[keyName] = value and true or false
            if changed then changed() end
        end
    end

    -- A section's own sub-table accessor (the table is made on first use).
    local function SubTable(section, field)
        return function()
            local tbl = section()
            if not tbl then return nil end
            tbl[field] = tbl[field] or {}
            return tbl[field]
        end
    end
    -- Per-section "Where to Show" stores.
    local RWhere = SubTable(RDB, "whereToShow")
    local AWhere = SubTable(ADB, "whereToShow")
    local CWhere = SubTable(CDB, "whereToShow")
    -- Per-section sets, see EABR.SPECIALS. The first write stores a copy of
    -- the old shared specials set.
    local function CSpecialWhere(cls)
        return function(forWrite)
            local c, S = CDB(), _G._CUABR_SPECIALS
            if not (c and S) then return nil end
            local field = S[cls].where
            if forWrite and type(c[field]) ~= "table" then
                local src = c.specialsWhereToShow
                c[field] = type(src) == "table" and CopyTable(src) or {}
            end
            return _G._CUABR_SpecialsWhere(c, field)
        end
    end
    local CWarlockWhere = SubTable(CDB, "warlockWhereToShow")
    local FWhere = SubTable(FDB, "whereToShow")
    local RShowWhen = SubTable(RDB, "showWhen")

    -- Shared reminder-sound catalogue (built + LSM-populated by the QoL
    -- module and exposed on CludesUI). Falls back to just "None".
    local function SoundNamesOrder()
        local nameList = CUI._groupDeathSoundNames or { none = "None" }
        local order = CUI._groupDeathSoundOrder or { "none" }
        return nameList, order
    end
    local SOUND_TIP = "Play a sound once when a reminder in this section newly appears."
    -- Plays a picked sound once, so the choice is heard.
    local function PreviewSound(key)
        local paths = CUI._groupDeathSoundPaths
        local path = paths and paths[key]
        if path then PlaySoundFile(path, "Master") end
    end

    -- Inline cog holding a single "Sound" dropdown bound to getSec()[field]
    -- ("none"/nil = silent), plus any extraRows. One reminder sound applies
    -- to the whole section.
    local function AddSectionSoundCog(region, getSec, field, extraRows, title)
        local nameList, order = SoundNamesOrder()
        local rows = {
            {
                type = "dropdown",
                label = "Sound",
                tooltip = SOUND_TIP,
                values = nameList,
                order = order,
                get = function()
                    local tbl = getSec()
                    return (tbl and tbl[field]) or "none"
                end,
                set = function(value)
                    local tbl = getSec()
                    if not tbl then return end
                    tbl[field] = value ~= "none" and value or nil
                    PreviewSound(value)
                end,
            },
        }
        for _, extra in ipairs(extraRows or {}) do
            rows[#rows + 1] = extra
        end
        return CUI.BuildInlineCog(
            region,
            { title = title or "Reminder Sound", rows = rows, minWidth = extraRows and 320 or 220 }
        )
    end

    -- A stand-in dropdown the DualRow lays out; the checklist below takes
    -- its place once the row is built.
    local function Placeholder(text, tooltip)
        return {
            type = "dropdown",
            text = text,
            tooltip = tooltip,
            values = { _placeholder = "..." },
            order = { "_placeholder" },
            getValue = function() return "_placeholder" end,
            setValue = function() end,
        }
    end

    -- The full "Reminder Sound" dropdown for a section's right slot. A
    -- class-special section looks its field up per call (the map is
    -- exported in ABR's OnEnable, see EABR.SPECIALS) and stores "none"
    -- rather than clearing it (see EABR.SpecialsSound).
    local function SoundDropdownCfg(settings)
        local nameList, order = SoundNamesOrder()
        local sec, special = settings.soundSec, settings.specialClass
        local own = settings.soundField or "sectionSound"
        local function Field()
            if not special then return own end
            local S = _G._CUABR_SPECIALS
            return S and S[special].sound
        end
        return {
            type = "dropdown",
            text = "Reminder Sound",
            dropdownWidth = 220,
            tooltip = SOUND_TIP,
            values = nameList,
            order = order,
            getValue = function()
                local tbl = sec()
                local f = tbl and Field()
                if not f then return "none" end
                if special and _G._CUABR_SpecialsSound then
                    return _G._CUABR_SpecialsSound(tbl, f) or "none"
                end
                return tbl[f] or "none"
            end,
            setValue = function(value)
                local tbl = sec()
                local f = tbl and Field()
                if not f then return end
                if value == "none" and not special then
                    tbl[f] = nil
                else
                    tbl[f] = value
                end
                PreviewSound(value)
            end,
        }
    end

    -- Puts a checkbox dropdown in a DualRow region in place of its control.
    local function CheckList(region, items, get, set)
        if region._control then region._control:Hide() end
        local dropdown, refresh =
            CUI.BuildVisOptsCBDropdown(region, 220, region:GetFrameLevel() + 2, items, get, set)
        PP.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
        region._control = dropdown
        region._lastInline = nil
        CUI.RegisterWidgetRefresh(refresh)
    end

    -- Per-section control dual-row: a "Where to Show" checkbox dropdown on
    -- the left. Right slot: for raid buffs the "Show When" checkbox
    -- dropdown (+ reminder-sound cog beside it); for a section with a sound
    -- a full "Reminder Sound" dropdown fills the slot instead of a cog; else
    -- the section's own cfg.rightCfg (the caller dresses row._rightRegion).
    local function SectionToggleRow(parent, y, settings)
        local rightCfg = settings.rightCfg
        if settings.showWhenStore then
            rightCfg = Placeholder("Show When", settings.showWhenTooltip)
        elseif settings.soundSec then
            rightCfg = SoundDropdownCfg(settings)
        end
        local line, h = CUI.Widgets:DualRow(
            parent,
            y,
            Placeholder("Where to Show", settings.whereTooltip),
            rightCfg or { type = "label", text = "" }
        )
        if CUI._prebuilding then return line, h end

        local where = settings.whereStore
        CheckList(
            line._leftRegion,
            settings.whereItems or WHERE_ITEMS,
            WhereGet(where),
            WhereSet(where, settings.onChange)
        )
        if settings.showWhenStore then
            local rrgn = line._rightRegion
            CheckList(
                rrgn,
                SHOWWHEN_ITEMS,
                WhenGet(settings.showWhenStore),
                WhenSet(settings.showWhenStore, function()
                    if settings.onShowWhenChange then settings.onShowWhenChange() end
                    if settings.onChange then settings.onChange() end
                end)
            )
            if settings.soundSec then
                AddSectionSoundCog(
                    rrgn,
                    settings.soundSec,
                    settings.soundField or "sectionSound",
                    settings.cogRows,
                    settings.cogTitle
                )
            end
        end
        return line, h
    end

    -- "(min)" in smaller, dimmer text after each slider label of a dual row.
    local function AddMinSuffix(threshRow, leftLabel, rightLabel)
        if CUI._prebuilding then return end
        local function LabelOf(region, text)
            for _, reg in ipairs({ region:GetRegions() }) do
                -- (an idle pooled region still holds the text of an earlier dress)
                if reg.GetText and not Pool.IsIdle(reg) and CUI.EnKey(reg:GetText()) == text then
                    return reg
                end
            end
        end
        local sides = { { threshRow._leftRegion, leftLabel }, { threshRow._rightRegion, rightLabel } }
        for _, side in ipairs(sides) do
            local region, text = side[1], side[2]
            local suffix = region:CreateFontString(nil, "OVERLAY")
            suffix:SetFont(CUI.EXPRESSWAY, 11, "")
            suffix:SetTextColor(1, 1, 1, 0.35)
            local label = LabelOf(region, text)
            if label then suffix:SetPoint("LEFT", label, "RIGHT", 5, -1) end
            suffix:SetText(CUI.L("(min)"))
        end
    end

    ---------------------------------------------------------------------------
    --  4-column checkbox grid (DualRow-style rows with RowBg + dividers)
    --  items = { { label, classToken, getVal, setVal, tooltip?, key?,
    --  cogRows?, cogTitle? }, ... }
    ---------------------------------------------------------------------------
    local GRID_COLS = 4
    local GRID_ROW_H = 50
    local GRID_BOX_SZ = 18
    local GRID_PAD = CUI.CONTENT_PAD or 16
    local GRID_SIDE_PAD = 20
    local BOX_BORDER = { 0.224, 0.215, 0.207, 0.6 }

    local function NoSnap(texture)
        if texture.SetSnapToPixelGrid then
            texture:SetSnapToPixelGrid(false)
            texture:SetTexelSnappingBias(0)
        end
        return texture
    end

    -- One cell: the label (in its class colour) on the left, the checkbox
    -- on the right, the whole cell clickable, and an optional cog just left
    -- of the box (no item sets cogRows yet; the hook is for per-item
    -- condition sets). Returns the cell.
    local function GridCell(rowFrame, entry, x, w, refreshFn, accent)
        local cell = CreateFrame("Frame", nil, rowFrame)
        cell:SetSize(w, GRID_ROW_H)
        cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", x, 0)

        local classColor = entry.classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classToken]
        local label = CUI.MakeFont(
            cell,
            13,
            nil,
            classColor and classColor.r or 1,
            classColor and classColor.g or 1,
            classColor and classColor.b or 1
        )
        label:SetPoint("LEFT", cell, "LEFT", GRID_SIDE_PAD, 0)
        label:SetText(entry.label)

        local boxFrame = CreateFrame("Frame", nil, cell)
        boxFrame:SetSize(GRID_BOX_SZ, GRID_BOX_SZ)
        boxFrame:SetPoint("RIGHT", cell, "RIGHT", -GRID_SIDE_PAD, 0)
        local boxBg = boxFrame:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints()
        boxBg:SetColorTexture(0.114, 0.106, 0.099, 1)
        NoSnap(boxBg)
        local border = CUI.MakeRoundedBorder(
            boxFrame,
            BOX_BORDER[1],
            BOX_BORDER[2],
            BOX_BORDER[3],
            BOX_BORDER[4],
            boxBg
        )
        local check = boxFrame:CreateTexture(nil, "ARTWORK")
        check:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 3, -3)
        check:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -3, 3)
        check:SetColorTexture(accent.r, accent.g, accent.b, 1)
        CUI.RoundBody(boxFrame, check, 1)
        NoSnap(check)

        local click = CreateFrame("Button", nil, cell)
        click:SetAllPoints(cell)
        click:SetFrameLevel(cell:GetFrameLevel() + 2)

        local function Paint()
            local on = entry.getVal() and true or false
            check:SetShown(on)
            label:SetAlpha(on and 1 or 0.5)
            if on then
                border:SetColor(accent.r, accent.g, accent.b, 0.15)
            else
                border:SetColor(BOX_BORDER[1], BOX_BORDER[2], BOX_BORDER[3], BOX_BORDER[4])
            end
        end
        Paint()
        click:SetScript("OnClick", function()
            entry.setVal(not entry.getVal())
            Paint()
            if refreshFn then refreshFn() end
        end)
        click:SetScript("OnEnter", function()
            if not entry.getVal() then label:SetAlpha(0.8) end
            if entry.tooltip then CUI.ShowWidgetTooltip(cell, entry.tooltip) end
        end)
        click:SetScript("OnLeave", function()
            if not entry.getVal() then label:SetAlpha(0.5) end
            if entry.tooltip then CUI.HideWidgetTooltip() end
        end)

        if entry.cogRows then
            CUI.BuildInlineCog(cell, {
                title = entry.cogTitle or "Reminder Conditions",
                rows = entry.cogRows,
                minWidth = 220,
                anchorTo = boxFrame,
                chain = false,
                size = 16,
                gap = 10,
            })
        end
        CUI.RegisterWidgetRefresh(Paint)
        return cell
    end

    -- The grid, row by row: a full-width row frame (as a DualRow) with 1px
    -- column dividers, then its cells. cellRefTable[item.key] gets each
    -- keyed cell (preview click navigation). Returns the height.
    local function BuildCheckboxGrid(parent, y, items, refreshFn, cellRefTable)
        local rows = math.ceil(#items / GRID_COLS)
        local totalW = parent:GetWidth() - GRID_PAD * 2
        local colW = math.floor(totalW / GRID_COLS)
        local accent = CUI.CLUDES_GREEN or { r = 0, g = 0.82, b = 0.62 }
        for line = 0, rows - 1 do
            local rowFrame = CreateFrame("Frame", nil, parent)
            PP.Size(rowFrame, totalW, GRID_ROW_H)
            PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", GRID_PAD, y - line * GRID_ROW_H)
            rowFrame._skipRowDivider = true
            CUI.RowBg(rowFrame, parent)
            for col = 1, GRID_COLS - 1 do
                local divider = NoSnap(rowFrame:CreateTexture(nil, "ARTWORK"))
                divider:SetColorTexture(1, 1, 1, 0.06)
                divider:SetWidth(1)
                PP.Point(divider, "TOP", rowFrame, "TOPLEFT", col * colW, 0)
                PP.Point(divider, "BOTTOM", rowFrame, "BOTTOMLEFT", col * colW, 0)
            end
            for col = 0, GRID_COLS - 1 do
                local entry = items[line * GRID_COLS + col + 1]
                if not entry then break end
                local cell = GridCell(rowFrame, entry, col * colW, colW, refreshFn, accent)
                if cellRefTable and entry.key then cellRefTable[entry.key] = cell end
            end
        end
        return rows * GRID_ROW_H
    end

    ---------------------------------------------------------------------------
    --  Auras, Buffs & Consumables page
    ---------------------------------------------------------------------------
    -- After a list edit: refresh the reminders and rebuild the page, now or
    -- (soon) a frame later, once an edit box has finished its commit.
    local function Rebuild()
        RequestRefresh()
        CUI:RefreshPage(true)
    end
    local function RebuildSoon()
        RequestRefresh()
        C_Timer.After(0, function() CUI:RefreshPage(true) end)
    end

    -- A spell's row text: its name, then its ID dimmed.
    local function SpellText(id)
        return _G._CUABR_SpellName(id, tostring(id)) .. " " .. CUI.COLOR_CODES.DIM .. id .. "|r"
    end

    -- Adds the spell ID typed into an Add ... Spell input to list: digits only,
    -- a spell the client knows, no duplicates.
    local function AddSpellIDToList(entryList, text)
        local spellID = tonumber((text or ""):match("^%s*(%d+)%s*$"))
        if not (spellID and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)) then
            return
        end
        if tContains(entryList, spellID) then return end
        entryList[#entryList + 1] = spellID
        RebuildSoon()
    end

    -- Names a new spell group (set nil) or renames set.
    local function PromptSpellGroupName(set)
        CUI:ShowInputPopup({
            title = set and "Rename Spell Group" or "New Spell Group",
            message = "Enter a name for the group:",
            placeholder = "Group name",
            initialText = set and set.name or "",
            confirmText = set and "Rename" or "Create",
            onConfirm = function(text)
                local name = strtrim(text or "")
                local foreverCfg = FDB()
                if name == "" or not foreverCfg then return end
                if set then
                    set.name = name
                else
                    foreverCfg.customGroups[#foreverCfg.customGroups + 1] = { name = name, ids = {} }
                end
                RebuildSoon()
            end,
        })
    end

    -- A labelled button slot (Rename, Remove, Create).
    local function ButtonSlot(text, buttonText, tooltip, onClick)
        return {
            type = "labeledButton",
            text = text,
            buttonText = buttonText,
            width = 90,
            tooltip = tooltip,
            onClick = onClick,
        }
    end

    -- Lays slots out two to a row (a blank in an odd last one); returns y.
    local function SlotRows(parent, y, slots, dress)
        for keyName = 1, #slots, 2 do
            local line, h = CUI.Widgets:DualRow(
                parent,
                y,
                slots[keyName],
                slots[keyName + 1] or CUI.BlankRowCfg()
            )
            if dress then dress(line, keyName) end
            y = y - h
        end
        return y
    end

    ---------------------------------------------------------------------------
    --  WoW Forever spell groups: one section per group. Slots, left to right:
    --  Add Spell ID, Rename, one per spell, Remove Group last.
    ---------------------------------------------------------------------------
    local GROUP_ADD_TIP = "Type a spell ID and press Enter to add it to this group. Unknown IDs are ignored.\n"
        .. "The reminder shows the icon of the first spell in the list that you know, "
        .. "or of the spell you picked with the Action Picker."

    -- Takes a spell out of a group, with its picked icon and rank pins.
    local function RemoveGroupSpell(set, index, spellID)
        table.remove(set.ids, index)
        if set.castSpellID == spellID then set.castSpellID = nil end
        if set.castRanks then
            set.castRanks[spellID] = nil
            if not next(set.castRanks) then set.castRanks = nil end
        end
        Rebuild()
    end

    local function BuildForeverGroupSections(parent, y)
        local foreverCfg = FDB()
        for groupIndex, set in ipairs(foreverCfg.customGroups) do
            local slots = {
                {
                    type = "input",
                    text = "Add Spell ID",
                    inputStyle = "popup",
                    placeholder = "Spell ID",
                    inputWidth = 110,
                    tooltip = GROUP_ADD_TIP,
                    getValue = function() return "" end,
                    setValue = function(text) AddSpellIDToList(set.ids, text) end,
                },
                ButtonSlot(
                    "Rename Group",
                    "Rename",
                    "Change this group's name.",
                    function() PromptSpellGroupName(set) end
                ),
            }
            for spellIndex, spellID in ipairs(set.ids) do
                slots[#slots + 1] = ButtonSlot(
                    SpellText(spellID),
                    "Remove",
                    "Remove this spell from the group.",
                    function() RemoveGroupSpell(set, spellIndex, spellID) end
                )
            end
            slots[#slots + 1] = ButtonSlot(
                "Remove Group",
                "Remove",
                "Deletes this group and its spells.",
                function()
                    table.remove(foreverCfg.customGroups, groupIndex)
                    Rebuild()
                end
            )
            local _, headerH =
                CUI.Widgets:SectionHeader(parent, CUI.Lf("SPELL GROUP: %1$s", set.name), y)
            y = SlotRows(parent, y - headerH, slots)
        end
        return y
    end

    ---------------------------------------------------------------------------
    --  WoW Forever custom spells: the lead slot (the Add Custom Spell entry),
    --  the New Spell Group slot, then one slot per tracked spell (its icon,
    --  name and ID, and a checkbox dropdown of the classes it reminds, each
    --  ticked until unticked, forever.customClasses[id][CLASS] = false, with
    --  Remove at its top), filled left to right, a blank label in an odd last
    --  slot. The page rebuilds on add and remove, so the slots never need
    --  in-place updates.
    ---------------------------------------------------------------------------
    local function RemoveCustomSpell(id)
        local foreverCfg = FDB()
        local entryList = foreverCfg and foreverCfg.customIDs
        if not entryList then return end
        for j = #entryList, 1, -1 do
            if entryList[j] == id then table.remove(entryList, j) end
        end
        if foreverCfg.customClasses then foreverCfg.customClasses[id] = nil end
        Rebuild()
    end

    -- Whether spell id reminds class token (on unless unticked).
    local function CustomClassOn(id, token)
        local foreverCfg = FDB()
        local isOff = foreverCfg and foreverCfg.customClasses and foreverCfg.customClasses[id]
        return not (isOff and isOff[token] == false)
    end
    -- Ticks or unticks class token for spell id; only unticked classes are
    -- stored, and an entry with none left goes.
    local function SetCustomClass(id, token, on)
        local foreverCfg = FDB()
        if not foreverCfg then return end
        foreverCfg.customClasses = foreverCfg.customClasses or {}
        local all = foreverCfg.customClasses
        local isOff = all[id]
        if on then
            if isOff then
                isOff[token] = nil
                if not next(isOff) then all[id] = nil end
            end
        else
            isOff = isOff or {}
            all[id] = isOff
            isOff[token] = false
        end
        RequestRefresh()
    end

    -- The class checklist's items: Remove at the top, then each class in its colour.
    local function CustomClassItems(id)
        local items = {
            {
                key = "_remove",
                label = "Remove",
                isTopAction = true,
                onClick = function() RemoveCustomSpell(id) end,
            },
        }
        for _, token in ipairs(CUI.ForeverClasses()) do
            local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
            local name = CUI.ForeverClassName(token)
            items[#items + 1] =
                { key = token, label = c and c.colorStr and ("|c" .. c.colorStr .. name .. "|r") or name }
        end
        return items
    end

    -- A tracked spell's slot: its icon before the name, and its classes
    -- (Remove at the top) on the right.
    local function DressCustomSlot(region, id)
        if not id then return end
        local label = region._label
        if label then
            local icon = region:CreateTexture(nil, "ARTWORK")
            icon:SetSize(22, 22)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:SetTexture(Tex(id))
            PP.Point(icon, "LEFT", region, "LEFT", 20, 0)
            label:ClearAllPoints()
            PP.Point(label, "LEFT", icon, "RIGHT", 8, 0)
        end
        local dropdown, refresh = CUI.BuildVisOptsCBDropdown(
            region,
            170,
            region:GetFrameLevel() + 2,
            CustomClassItems(id),
            function(token) return CustomClassOn(id, token) end,
            function(token, on) SetCustomClass(id, token, on) end
        )
        PP.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
        region._control = dropdown
        region._lastInline = nil
        CUI.RegisterWidgetRefresh(refresh)
    end

    local function BuildForeverCustomRows(parent, y, lead)
        local foreverCfg = FDB()
        local ids = foreverCfg and foreverCfg.customIDs
        local slots = {
            lead,
            ButtonSlot(
                "New Spell Group",
                "Create",
                "Creates a group of spells. A reminder shows if none of the auras from the group are active.",
                function() PromptSpellGroupName() end
            ),
        }
        for _, id in ipairs(ids or {}) do
            slots[#slots + 1] = {
                type = "label",
                text = SpellText(id),
                tooltip = "Reminds you whenever this buff is missing, on the classes ticked here.",
            }
        end
        return SlotRows(parent, y, slots, function(line, keyName)
            if ids and not CUI._prebuilding then
                DressCustomSlot(line._leftRegion, ids[keyName - 2])
                DressCustomSlot(line._rightRegion, ids[keyName - 1])
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Glow site: the reminder icon glow as a shared glow descriptor, used by the
    --  Reminders page and the Global Settings Glows page.
    ---------------------------------------------------------------------------
    local abrGlowDesc
    do
        local GO = CUI.GlowOptions
        abrGlowDesc = _G._CUABR_GLOW_VIEW
            and {
                view = _G._CUABR_GLOW_VIEW,
                host = "icon",
                excludes = { [4] = true },
                caps = { mode = true, params = true, bg = true },
                defaultColor = { r = 1.0, g = 0.788, b = 0.137 },
                onChange = function()
                    RequestRefresh()
                    SyncPreviewHeader()
                end,
                get = function(f)
                    local display = DDB()
                    if not display then return nil end
                    if f == "style" then
                        return display.glowType or 0
                    elseif f == "mode" then
                        -- Read-path migration: a profile activated mid-session may not
                        -- have a mode key yet; derive it from the stored color.
                        if _G._CUABR_EnsureGlowModeMigrated then _G._CUABR_EnsureGlowModeMigrated(display) end
                        return display.glowColorMode or "default"
                    end
                    return CUI.GlowOptions.FlatGet(display, "glow", f)
                end,
                set = function(f, a, b2, c2)
                    local display = DDB()
                    if not display then return end
                    if f == "style" then
                        display.glowType = a
                    elseif f == "mode" then
                        display.glowColorMode = a
                    else
                        CUI.GlowOptions.FlatSet(display, "glow", f, a, b2, c2)
                    end
                end,
            }
        if abrGlowDesc then
            GO.RegisterSite({
                id = "abr_glow",
                label = "Reminder Glow",
                group = "module",
                module = "CludesUIAuraBuffReminders",
                page = PAGE_REMINDERS,
                section = SECTION_DISPLAY,
                highlight = "Glow Type",
                desc = abrGlowDesc,
            })
        end
    end

    ---------------------------------------------------------------------------
    --  Beacon M+ row: the CORE toggle shows only for a retail Holy Paladin. A
    --  page built for one Holy state is rebuilt once the player's no longer
    --  matches it: on a spec change while the page is shown, or when the cached
    --  page is shown again after one. One event frame, re-parented into each
    --  build of the page, so its show and hide are the page's and the event is
    --  registered only while the page is shown. Other classes and WoW Forever
    --  never make it.
    ---------------------------------------------------------------------------
    local BeaconRowShown
    do
        local paladin = not FOREVER and select(2, UnitClass("player")) == "PALADIN"
        local watcher, builtHoly, queued
        local function IsHoly()
            local spec = C_SpecializationInfo.GetSpecialization()
            return spec ~= nil and C_SpecializationInfo.GetSpecializationInfo(spec) == 65
        end
        -- One rebuild per burst, a frame later: a cached page has finished showing
        local function Flush()
            queued = nil
            if watcher:IsVisible() and IsHoly() ~= builtHoly then CUI:RefreshPage(true) end
        end
        local function Queue()
            if queued then return end
            queued = true
            C_Timer.After(0, Flush)
        end
        -- Each build of the page: whether the toggle shows
        BeaconRowShown = function(parent)
            if not paladin then return false end
            local holy = IsHoly()
            if CUI._prebuilding then return holy end
            builtHoly = holy
            if not watcher then
                watcher = CreateFrame("Frame")
                watcher._searchIgnore = true -- the inline search never hides it
                watcher:SetScript("OnEvent", Queue)
                watcher:SetScript("OnShow", function(self)
                    self:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
                    if IsHoly() ~= builtHoly then Queue() end
                end)
                watcher:SetScript(
                    "OnHide",
                    function(self) self:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED") end
                )
            end
            watcher:Hide()
            watcher:SetParent(parent)
            -- On a kept page wrapper the watcher rides it as an attachment: the
            -- wrapper's next dress hides it (as dropping the page did) and
            -- never moves it to the pool's graveyard.
            Pool.Attach(parent, watcher)
            watcher:Show()
            return holy
        end
    end

    -- Display field binders for the page's rows: Get(key, default) reads
    -- display[key] (default when unset or false), Set(key, after) writes it
    -- and runs after (default: refresh the reminders and the preview).
    local function Live()
        RequestRefresh()
        SyncPreviewHeader()
    end
    local function Get(key, default)
        return function()
            local display = DDB()
            return display and display[key] or default
        end
    end
    local function Set(key, after)
        return function(value)
            local display = DDB()
            if not display then return end
            display[key] = value;
            (after or Live)(value)
        end
    end

    -- The page's opening line: what the reminder icons' clicks do.
    local function ClickInfoLine(parent, y)
        local info = CreateFrame("Frame", nil, parent)
        info:SetSize(parent:GetWidth(), 20)
        info:SetPoint("TOP", parent, "TOP", 0, y - 15)
        info._isSpacer = true
        local text = info:CreateFontString(nil, "OVERLAY")
        text:SetFont(CUI.GetFontPath("auraBuff") or "Fonts\\FRIZQT__.TTF", 15, "")
        text:SetTextColor(1, 1, 1, 0.75)
        text:SetPoint("TOP", info, "TOP", 0, 0)
        text:SetJustifyH("CENTER")
        text:SetText(
            CUI.L(
                "Left Click to apply buffs (out of combat), Middle Click to hide until next load screen"
            )
        )
        return y - 32
    end

    -- WoW Forever: what this module is for, in the red of the suite's
    -- warning banners, right above CORE. "CDM module" (the template's %s)
    -- is its own button, and opens
    -- the Cooldown Manager's Buffs bar while that module is loaded. Not
    -- built in the search prebuild (nothing to index); y moves the same.
    local FOREVER_RED = { 1, 0.25, 0.25 }
    local function ForeverPurposeBanner(parent, y)
        local GAP, height = 6, 44
        if CUI._prebuilding then return y - (GAP + height + 14) end
        local R, G, B = FOREVER_RED[1], FOREVER_RED[2], FOREVER_RED[3]
        local function Red(host) return CUI.MakeFont(host, 16, nil, R, G, B, 1) end
        local PAD = CUI.CONTENT_PAD
        local w = parent:GetWidth() - PAD * 2
        local host = CreateFrame("Frame", nil, parent)
        PP.Point(host, "TOPLEFT", parent, "TOPLEFT", PAD, y - GAP)
        local first = Red(host)
        first:SetPoint("TOP", host, "TOP", 0, 0)
        first:SetWidth(w)
        first:SetWordWrap(true)
        first:SetJustifyH("CENTER")
        first:SetText(
            CUI.L("This module is for OUT OF COMBAT non-rotational buff/consumable reminders,")
        )

        -- The second line: the text either side of the link.
        local template = CUI.L("for in combat aura/rotational reminders please use the %s") or ""
        local before, after = template:match("^(.-)%%s(.*)$")
        if not before then
            before, after = template, ""
        end
        local second = CreateFrame("Frame", nil, host)
        local beforeFs = Red(second)
        beforeFs:SetPoint("LEFT", second, "LEFT", 0, 0)
        beforeFs:SetText(before)
        local link = CreateFrame("Button", nil, second)
        local linkFs = Red(link)
        linkFs:SetPoint("LEFT", link, "LEFT", 0, 0)
        linkFs:SetText(CUI.L("CDM module"))
        link:SetSize(math.ceil(linkFs:GetStringWidth() or 80) + 1, 20)
        link:SetPoint("LEFT", beforeFs, "RIGHT", 0, 0)
        local afterFs = Red(second)
        afterFs:SetPoint("LEFT", link, "RIGHT", 0, 0)
        afterFs:SetText(after)
        if CUI._ModuleNS["CludesUICooldownManager"] then
            local EG = CUI.CLUDES_GREEN
            linkFs:SetTextColor(EG.r, EG.g, EG.b, 1)
            linkFs:SetAlpha(0.85)
            link:SetScript("OnEnter", function(self)
                linkFs:SetAlpha(1)
                CUI.ShowWidgetTooltip(self, CUI.L("Open the Cooldown Manager's Buffs bar"))
            end)
            link:SetScript("OnLeave", function()
                linkFs:SetAlpha(0.85)
                CUI.HideWidgetTooltip()
            end)
            link:SetScript("OnClick", function()
                CUI.HideWidgetTooltip()
                CUI:NavigateToElementSettings("CludesUICooldownManager", "CDM Bars", nil, function()
                    if CUI._setCDMBar then CUI._setCDMBar("buffs") end
                end)
            end)
        else
            link:EnableMouse(false)
        end
        local lineW = (beforeFs:GetStringWidth() or 0) + link:GetWidth() + (afterFs:GetStringWidth() or 0)
        PP.Size(second, math.ceil(lineW), 20)
        second:SetPoint("TOP", first, "BOTTOM", 0, -4)
        -- A translation long enough to wrap the first line pushes CORE down.
        height = math.max(height, math.ceil(first:GetStringHeight() or 0) + 24)
        PP.Size(host, w, height)
        return y - (GAP + height + 14)
    end

    -- CORE: the master switch in the card header (the box at its right),
    -- Grow Direction and Scale, and for a retail Holy Paladin Beacon M+.
    local function BuildCoreSection(parent, y)
        local W = CUI.Widgets
        local _
        local header, h = W:SectionHeader(parent, SECTION_CORE, y, nil, {
            tooltip = "Master toggle for all aura, buff, and consumable reminders. Talent reminders are not affected.",
            getValue = function()
                local display = DDB()
                return display and display.remindersEnabled ~= false
            end,
            setValue = Set("remindersEnabled", function()
                if _G._CUABR_UpdateGroupAuraRegistration then _G._CUABR_UpdateGroupAuraRegistration() end
                RequestRefresh()
                CUI:RefreshPage()
            end),
        })
        y = y - h
        CUI.BuildSectionUnlockJump(header, { key = "EABR_Reminders" })

        _, h = W:DualRow(parent, y, {
            type = "dropdown",
            text = "Grow Direction",
            values = GROW_DIR_VALUES,
            order = GROW_DIR_ORDER,
            tooltip = "Which part of the row stays in place as reminders appear and disappear.",
            getValue = Get("growDirection", "CENTER"),
            setValue = function(value)
                CUI.SetAuraBuffGrowDir(value)
                RequestRefresh()
                RelayoutPreviewIcons()
            end,
        }, {
            type = "slider",
            text = "Scale",
            min = 0.5,
            max = 3.0,
            step = 0.05,
            getValue = Get("scale", 1.0),
            setValue = Set("scale"),
        })
        y = y - h

        if BeaconRowShown(parent) then
            _, h = W:DualRow(parent, y, {
                type = "toggle",
                text = "Beacon M+ Reminders",
                tooltip = "During Mythic+ boss fights, shows a glowing red Beacon on your tank's raid frame while they have your Beacon of Light or Beacon of Faith.",
                disabled = function() return not CUI._ModuleNS["CludesUIRaidFrames"] end,
                disabledTooltip = CUI.DisabledTooltip("CludesUI Raid & Party Frames"),
                getValue = function()
                    local display = DDB()
                    return display and display.beaconMPlus == true
                end,
                setValue = function(value)
                    local display = DDB()
                    if display then
                        display.beaconMPlus = value or nil
                        RequestRefresh()
                    end
                end,
            }, CUI.BlankRowCfg())
            y = y - h
        end
        return y, header
    end

    -- A display field as read (nil when unset) and a write with no follow-up.
    local function Raw(key)
        return function()
            local display = DDB()
            return display and display[key]
        end
    end
    local function Store(key)
        return function(value)
            local display = DDB()
            if display then display[key] = value end
        end
    end
    local function BorderTex()
        local display = DDB()
        return (display and display.borderTexture) or "solid"
    end
    local function BorderStep()
        local display = DDB()
        return (display and display.borderSize) or 1
    end
    -- A shape change re-masks the reminder icons and the preview.
    local function Reshape()
        ns.RefreshIconShapes()
        SyncPreviewHeader()
    end

    -- Icon Shape (+ crop cog) | Icon Zoom.
    local function BuildShapeRow(parent, y)
        local values, order = ns.IconShapeValues()
        local line, h = CUI.Widgets:DualRow(parent, y, {
            type = "dropdown",
            text = "Icon Shape",
            values = values,
            order = order,
            itemDisabled = function(value)
                local display = DDB()
                return value ~= "none"
                    and value ~= "cropped"
                    and display
                    and (display.borderTexture or "solid") ~= "solid"
            end,
            itemDisabledTooltip = "This option requires Border Style to be set to Solid",
            getValue = Get("iconShape", "none"),
            setValue = Set("iconShape", function()
                Reshape()
                CUI:RefreshPage(true)
            end),
        }, {
            type = "slider",
            text = "Icon Zoom",
            min = 0,
            max = 15,
            step = 0.5,
            getValue = function()
                local display = DDB()
                return ((display and display.iconZoom) or 0.07) * 100
            end,
            setValue = function(value)
                local display = DDB()
                if display then
                    display.iconZoom = value / 100
                    Reshape()
                end
            end,
        })
        CUI.BuildInlineCog(line._leftRegion, {
            title = "Icon Shape",
            disabled = function()
                local display = DDB()
                return not display or display.iconShape ~= "cropped"
            end,
            disabledTooltip = "This option requires Icon Shape to be set to Cropped",
            rows = {
                {
                    type = "slider",
                    label = "Adjust Crop",
                    min = 5,
                    max = 25,
                    step = 1,
                    tooltip = "How much is trimmed from the icon's top and bottom, per side (10% is the classic cropped look).",
                    get = function() return ns.CropPercent(DDB()) end,
                    set = Set("iconCropPercent", Reshape),
                },
            },
        })
        return y - h
    end

    -- A new border style starts from that style's own colour, layering and
    -- size, with no leftover offsets, shifts or exact pixels.
    local function PickBorderStyle(value)
        local display = DDB()
        if not display then return end
        display.borderTexture = value
        display.borderTextureOffset, display.borderTextureOffsetY = nil, nil
        display.borderTextureShiftX, display.borderTextureShiftY = nil, nil
        local color, behind = CUI.GetBorderStyleSelectDefaults(value)
        display.borderR, display.borderG, display.borderB, display.borderA = color.r, color.g, color.b, 1
        display.borderBehind = behind
        display.borderSize = CUI.GetBorderDefaultSize("aurabuffreminders", value) or display.borderSize
        if display.borderSizePx then display.borderSizePx = false end
        ApplyIconBorders()
        -- Rebuild: the Width | Height Offset row follows the Solid / textured pick.
        CUI:RefreshPage(true)
    end

    -- Border Size: a masked shape draws a ring at any size above 0, so it is
    -- None / Strong there (a pick keeps the square border's own size for the
    -- way back); otherwise exact pixels over borderSize and its borderSizePx
    -- companion (CludesUI.BorderPx).
    local function BorderSizeCfg()
        if ns.IconShapeMasked(DDB()) then
            return {
                type = "segmented",
                text = "Border Size",
                values = { none = "None", strong = "Strong" },
                order = { "none", "strong" },
                getValue = function()
                    local display = DDB()
                    return display and (display.borderSize or 1) > 0 and "strong" or "none"
                end,
                setValue = function(value)
                    local display = DDB()
                    if not display then return end
                    if value ~= "strong" then
                        display.borderSize = 0
                    elseif (display.borderSize or 1) <= 0 then
                        display.borderSize = 1
                    end
                    ApplyIconBorders()
                end,
            }
        end
        return CUI.BorderPxSliderCfg({
            text = "Border Size",
            getStep = BorderStep,
            setStep = Store("borderSize"),
            getTex = BorderTex,
            getPx = Raw("borderSizePx"),
            setPx = Store("borderSizePx"),
            apply = ApplyIconBorders,
        })
    end

    -- A Shift slider of the border cog: the stored shift, else the style's
    -- default (which = the GetBorderDefaults return it reads); 0 stores nothing.
    local function ShiftRow(label, key, which)
        return {
            type = "slider",
            label = label,
            min = -10,
            max = 10,
            step = 1,
            get = function()
                local display = DDB()
                if not display then return 0 end
                if display[key] ~= nil then return display[key] end
                return (
                    select(
                        which,
                        CUI.GetBorderDefaults(
                            "aurabuffreminders",
                            display.borderTexture or "solid",
                            display.borderSize or 1
                        )
                    )
                )
            end,
            set = function(value)
                local display = DDB()
                if display then
                    display[key] = (value ~= 0) and value or nil
                    ApplyIconBorders()
                end
            end,
        }
    end

    -- Border Style (+ options cog, textured styles only) | Border Size (+
    -- colour swatch), then for a textured style its Width | Height Offset
    -- row (each slider shows what is drawn, the override else the registry
    -- default for the step, and stores nothing while it follows the default).
    local function BuildBorderRows(parent, y)
        local W = CUI.Widgets
        local values, order = CUI.GetBorderTextureDropdown()
        local line, h = W:DualRow(parent, y, {
            type = "dropdown",
            text = "Border Style",
            disabled = function() return ns.IconShapeMasked(DDB()) end,
            disabledTooltip = "This option requires Icon Shape to be set to None or Cropped",
            values = values,
            order = order,
            getValue = Get("borderTexture", "solid"),
            setValue = PickBorderStyle,
        }, BorderSizeCfg())
        y = y - h

        local texture = BorderTex()
        if texture ~= "" and texture ~= "solid" then
            local left, right = CUI.BorderOffsetRowCfgs({
                addonKey = "aurabuffreminders",
                getTex = BorderTex,
                getStep = BorderStep,
                getSizeKey = BorderStep,
                getPx = Raw("borderSizePx"),
                getX = Raw("borderTextureOffset"),
                setX = Store("borderTextureOffset"),
                getY = Raw("borderTextureOffsetY"),
                setY = Store("borderTextureOffsetY"),
                apply = ApplyIconBorders,
            })
            local _, offsetH = W:DualRow(parent, y, left, right)
            y = y - offsetH
        end
        if CUI._prebuilding then return y, line end

        local cog = CUI.BuildInlineCog(line._leftRegion, {
            title = "Border Options",
            rows = {
                ShiftRow("Shift X", "borderTextureShiftX", 3),
                ShiftRow("Shift Y", "borderTextureShiftY", 4),
                {
                    type = "toggle",
                    label = "Show Behind",
                    get = function()
                        local display = DDB()
                        return display and display.borderBehind == true
                    end,
                    set = function(value)
                        local display = DDB()
                        if display then
                            display.borderBehind = value
                            ApplyIconBorders()
                        end
                    end,
                },
            },
        })
        local function CogShown()
            local display = DDB()
            cog:SetShown(display and (display.borderTexture or "solid") ~= "solid")
        end
        CogShown()
        CUI.RegisterWidgetRefresh(CogShown)

        local region = line._rightRegion
        local swatch, refresh = CUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, function()
            local display = DDB()
            return (display and display.borderR) or 0,
                (display and display.borderG) or 0,
                (display and display.borderB) or 0,
                (display and display.borderA) or 1
        end, function(red, green, blue, a)
            local display = DDB()
            if display then
                display.borderR, display.borderG, display.borderB, display.borderA = red, green, blue, a or 1
                ApplyIconBorders()
            end
        end, true, 20)
        swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -12, 0)
        region._lastInline = swatch
        CUI.RegisterWidgetRefresh(refresh)
        return y, line
    end

    -- Cog rows bound to a display field: a slider (default when unset) and a
    -- font pick ("__global" = the module font, stored as nil). after runs on
    -- a change (default: refresh the reminders and the preview).
    local function CogSlider(label, key, min, max, default, after)
        return {
            type = "slider",
            label = label,
            min = min,
            max = max,
            step = 1,
            get = Get(key, default),
            set = Set(key, after),
        }
    end
    local function CogFont(label, key, after)
        local values, order = CUI.BuildFontDropdownData()
        return {
            type = "dropdown",
            label = label,
            values = values,
            order = order,
            get = Get(key, "__global"),
            set = function(value)
                local display = DDB()
                if display then
                    display[key] = (value ~= "__global") and value or nil
                    (after or Live)()
                end
            end,
        }
    end
    -- A toggle whose change also rebuilds the page (its cogs follow it).
    local function Rebuilds(key)
        return Set(key, function()
            Live()
            CUI:RefreshPage()
        end)
    end
    local NAME_ANCHORS = {
        BOTTOM = "Below Icon",
        TOP = "Above Icon",
        CENTER = "On Icon",
        LEFT = "Left of Icon",
        RIGHT = "Right of Icon",
    }

    -- Show Name's cog (font, size, anchor, offsets) and colour swatch, both
    -- dimmed while names are off.
    local function NameInlines(region)
        CUI.BuildInlineCog(region, {
            title = "Name Settings",
            disabled = function()
                local display = DDB()
                return not display or not display.showText
            end,
            disabledTooltip = "Show Name",
            rows = {
                CogFont("Name Font", "nameFont"),
                CogSlider("Text Size", "textSize", 6, 30, 11),
                {
                    type = "dropdown",
                    label = "Anchor",
                    values = NAME_ANCHORS,
                    order = { "BOTTOM", "TOP", "CENTER", "LEFT", "RIGHT" },
                    get = Get("textAnchor", "BOTTOM"),
                    set = Set("textAnchor"),
                },
                CogSlider("X Offset", "textXOffset", -50, 50, 0),
                CogSlider("Y Offset", "textYOffset", -50, 50, -2),
            },
        })
        local swatch = CUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, function()
            local display = DDB()
            local textColor = display and display.textColor or { r = 1, g = 1, b = 1 }
            return textColor.r, textColor.g, textColor.b, 1
        end, function(red, green, blue)
            local display = DDB()
            if display then
                display.textColor = { r = red, g = green, b = blue }
                Live()
            end
        end, false, 20)
        swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = swatch
        local block = CUI.NewSwatchBlocker(swatch)
        block:SetScript(
            "OnEnter",
            function() CUI.ShowWidgetTooltip(swatch, CUI.DisabledTooltip("Show Name")) end
        )
        block:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        local function Dim()
            local display = DDB()
            local isOff = not display or not display.showText
            swatch:SetAlpha(isOff and 0.3 or 1)
            block:SetShown(isOff)
        end
        Dim()
        CUI.RegisterWidgetRefresh(Dim)
    end

    -- Show Name (+ cog, swatch) | Show Item Count (+ cog), then Glow Type
    -- (shared glow controls) | Attach Important Buffs to Cursor (+ cog).
    -- Returns y and the name row (the preview's text clicks lead there).
    local function BuildTextRows(parent, y)
        local W = CUI.Widgets
        local building = not CUI._prebuilding
        local nameRow, h = W:DualRow(parent, y, {
            type = "toggle",
            text = "Show Name",
            tooltip = "Shows the name.",
            getValue = Raw("showText"),
            setValue = Rebuilds("showText"),
        }, {
            type = "toggle",
            text = "Show Item Count",
            tooltip = "Show how many of the consumable you have left in your bags.",
            getValue = function()
                local display = DDB()
                return not display or display.showCount ~= false
            end,
            setValue = Rebuilds("showCount"),
        })
        y = y - h
        if building then
            CUI.BuildInlineCog(nameRow._rightRegion, {
                title = "Item Count Settings",
                disabled = function()
                    local display = DDB()
                    return display and display.showCount == false
                end,
                disabledTooltip = "Show Item Count",
                rows = {
                    CogFont("Item Count Font", "countFont", RequestRefresh),
                    CogSlider("Text Size", "countSize", 6, 30, 16),
                    CogSlider("X Offset", "countXOffset", -50, 50, 0),
                    CogSlider("Y Offset", "countYOffset", -50, 50, 0),
                },
            })
        end

        local GO = CUI.GlowOptions
        local glowRow
        glowRow, h = W:DualRow(
            parent,
            y,
            abrGlowDesc and GO.DropdownSpec(abrGlowDesc, "Glow Type") or CUI.BlankRowCfg(),
            {
                type = "toggle",
                text = "Attach Important Buffs to Cursor",
                tooltip = "This option only affects Raid Buffs and Paladin Beacons",
                getValue = Raw("cursorAttach"),
                setValue = Set("cursorAttach", function()
                    RequestRefresh()
                    CUI:RefreshPage()
                end),
            }
        )
        y = y - h
        if abrGlowDesc then GO.AttachInline(glowRow._leftRegion, abrGlowDesc) end
        if building then
            CUI.BuildInlineCog(glowRow._rightRegion, {
                title = "Cursor Settings",
                disabled = function()
                    local display = DDB()
                    return not (display and display.cursorAttach)
                end,
                disabledTooltip = "Attach Important Buffs to Cursor",
                rows = {
                    {
                        type = "toggle",
                        label = "Only on Cursor in Combat",
                        tooltip = "Out of combat, important buffs show with your other reminders.",
                        get = function()
                            local display = DDB()
                            return display and display.cursorAttachCombatOnly == true
                        end,
                        set = Set("cursorAttachCombatOnly", RequestRefresh),
                    },
                },
            })
            NameInlines(nameRow._leftRegion)
        end
        return y, nameRow
    end

    local SHOW_BELOW_TIP = "Show reminders when remaining buff time is below this many minutes.\n"
        .. "0 = only when fully expired.\n"
        .. "Ignored in combat and during Mythic+ keys (then only when the buff is gone)."
    local PRE_KEY_TIP = "Reminder threshold while you are in a dungeon before a Mythic+ key starts "
        .. "(Mythic 0 / keystone lobby). Set it high enough that you top up buffs and food before "
        .. "pulling, so you begin the key with enough duration to last it.\n"
        .. "0 = only when fully expired.\n"
        .. "Ignored once the key is active or you are in combat (then only when the buff is fully gone)."

    -- The rest of DISPLAY: Icon Spacing (+ layout cog) | Frame Strata, the
    -- expiry thresholds (retail only: WoW Forever's reminders are absence
    -- only), Show Tooltips | Opacity, and on WoW Forever the Action Picker.
    local function BuildLayoutRows(parent, y)
        local W = CUI.Widgets
        local _
        local spacingRow, h = W:DualRow(parent, y, {
            type = "slider",
            pixel = true,
            text = "Icon Spacing",
            min = 0,
            max = 50,
            step = 1,
            getValue = Get("iconSpacing", 8),
            setValue = Set("iconSpacing", function()
                RequestRefresh()
                RelayoutPreviewIcons()
            end),
        }, {
            type = "dropdown",
            text = "Frame Strata",
            tooltip = "Which layer it draws on, above or below other frames.",
            values = _G._CUABR_STRATA_VALUES or { MEDIUM = "Medium" },
            order = _G._CUABR_STRATA_ORDER or { "MEDIUM" },
            getValue = Get("frameStrata", "MEDIUM"),
            setValue = Set("frameStrata", function()
                if _G._CUABR_ApplyStrata then _G._CUABR_ApplyStrata() end
            end),
        })
        y = y - h
        if not CUI._prebuilding then
            CUI.BuildInlineCog(spacingRow._leftRegion, {
                title = "Layout Settings",
                rows = {
                    CogSlider("Y Offset", "yOffset", -600, 600, 0, function()
                        if _G._CUABR_ApplyUnlockPos then _G._CUABR_ApplyUnlockPos() end
                    end),
                },
            })
        end

        if not FOREVER then
            local timingRow
            timingRow, h = W:DualRow(parent, y, {
                type = "slider",
                text = "Show Below",
                min = 0,
                max = 60,
                step = 1,
                tooltip = SHOW_BELOW_TIP,
                getValue = Get("showUnder", 5),
                setValue = Set("showUnder", RequestRefresh),
            }, {
                type = "slider",
                text = "Show Below Pre-Key",
                min = 0,
                max = 60,
                step = 1,
                tooltip = PRE_KEY_TIP,
                getValue = Get("showUnderMPlus", 40),
                setValue = Set("showUnderMPlus", RequestRefresh),
            })
            y = y - h
            AddMinSuffix(timingRow, "Show Below", "Show Below Pre-Key")
        end

        _, h = W:DualRow(parent, y, {
            type = "toggle",
            text = "Show Tooltips",
            tooltip = "Show item or spell tooltips when hovering reminder icons.",
            getValue = function()
                local display = DDB()
                return not display or display.showTooltips ~= false
            end,
            setValue = Store("showTooltips"),
        }, {
            type = "slider",
            text = "Opacity",
            min = 0,
            max = 1,
            step = 0.05,
            getValue = Get("opacity", 1),
            setValue = Set("opacity"),
        })
        y = y - h

        if FOREVER then
            _, h = W:DualRow(parent, y, {
                type = "toggle",
                text = "Action Picker",
                tooltip = "Right-click a spell group or Class Buffs reminder that has more than one spell to choose the spell its left click casts. Scroll over a spell in the picker to choose its rank.",
                getValue = function()
                    local foreverCfg = FDB()
                    return foreverCfg and foreverCfg.pickerEnabled == true
                end,
                setValue = function(value)
                    local foreverCfg = FDB()
                    if foreverCfg then
                        foreverCfg.pickerEnabled = value
                        RequestRefresh()
                    end
                end,
            }, CUI.BlankRowCfg())
            y = y - h
        end
        _, h = W:Spacer(parent, y, 20)
        return y - h
    end

    -- A checkbox grid item that ticks entry.key in section().enabled.
    local function EnabledItem(section, entry, label, class, tooltip)
        return {
            label = label,
            classToken = class,
            key = entry.key,
            tooltip = tooltip,
            getVal = function()
                local tbl = section()
                return tbl and tbl.enabled and tbl.enabled[entry.key]
            end,
            setVal = function(value)
                local tbl = section()
                if tbl and tbl.enabled then tbl.enabled[entry.key] = value end
            end,
        }
    end
    local function SpellLabel(entry) return _G._CUABR_SpellName(entry.castSpell, entry.name) end
    -- After a grid tick: refresh, rebuild the preview, and first (groupAuras)
    -- re-register group aura tracking where an item turns it on or off.
    local function GridChanged(groupAuras)
        return function()
            if groupAuras and _G._CUABR_UpdateGroupAuraRegistration then
                _G._CUABR_UpdateGroupAuraRegistration()
            end
            RequestRefresh()
            RebuildPreviewHeader()
        end
    end

    -- Raid Buffs' cog: click a reminder to ask for the buff, optionally with
    -- your own text ([spell] marks the buff's name; the untouched example
    -- stays unsaved, so it follows the client language).
    local function RequestRows()
        local function RequestOn()
            local r = RDB()
            return r and r.requestOnClick
        end
        return {
            {
                type = "toggle",
                label = "Click to Request Buff",
                tooltip = "Click a buff or Healthstone to ask for it.",
                get = function()
                    local r = RDB()
                    return r and r.requestOnClick == true
                end,
                set = function(value)
                    local r = RDB()
                    if r then
                        r.requestOnClick = value
                        RequestRefresh()
                    end
                end,
            },
            {
                type = "toggle",
                label = "Custom Request Text",
                tooltip = "Send your own text instead of the default.",
                disabled = function() return not RequestOn() end,
                disabledTooltip = "Click to Request Buff",
                get = function()
                    local r = RDB()
                    return r and r.requestCustom == true
                end,
                set = function(value)
                    local r = RDB()
                    if r then r.requestCustom = value end
                end,
            },
            {
                type = "input",
                label = "Request Text",
                inputWidth = 170,
                inputJustify = "LEFT",
                tooltip = "Type [spell] where the buff's name goes.",
                disabled = function()
                    local r = RDB()
                    return not (r and r.requestOnClick and r.requestCustom)
                end,
                disabledTooltip = "Custom Request Text",
                get = function()
                    local r = RDB()
                    if not r then return "" end
                    return r.requestText or _G._CUABR_RequestExample()
                end,
                set = function(value)
                    local r = RDB()
                    if not r then return end
                    local clean = _G._CUABR_CleanRequestText(value)
                    if clean == _G._CUABR_RequestExample() then clean = nil end
                    r.requestText = clean
                    if clean and not _G._CUABR_HasRequestToken(clean) then
                        local msg = CUI.Lf("Request text must include %1$s", _G._CUABR_REQUEST_TOKEN)
                        UIErrorsFrame:AddMessage(msg, 1.0, 0.3, 0.3, 1.0)
                    end
                end,
            },
        }
    end

    -- RAID BUFFS (WoW Forever: its own locations and its own buffs, which
    -- the module exports as the raid buff list there): Where to Show | Show
    -- When (+ sound cog, retail: the request options), then the buff grid.
    -- Returns y and the header.
    local function BuildRaidBuffSection(parent, y, refs)
        local W = CUI.Widgets
        local _
        local header, h = W:SectionHeader(parent, SECTION_RAID_BUFFS, y)
        y = y - h
        _, h = SectionToggleRow(parent, y, {
            whereStore = RWhere,
            whereItems = FOREVER and FOREVER_WHERE_ITEMS or nil,
            whereTooltip = "Pick which content this section's reminders appear in.\nRested areas (cities and inns) always stay hidden.",
            showWhenStore = RShowWhen,
            showWhenTooltip = "Others are missing my buff: remind when a groupmate is missing a buff you can cast.\nI am missing others' buffs: remind when you are missing a buff a groupmate could give you (only shown when someone who can cast it is present). Off by default.",
            soundSec = RDB,
            soundField = "sectionSound",
            cogTitle = (not FOREVER) and "Raid Buff Options" or nil,
            cogRows = (not FOREVER) and RequestRows() or nil,
            onChange = RequestRefresh,
            onShowWhenChange = function()
                if _G._CUABR_UpdateGroupAuraRegistration then _G._CUABR_UpdateGroupAuraRegistration() end
            end,
        })
        y = y - h
        local items = {}
        for _, buff in ipairs(_G._CUABR_RAID_BUFFS or {}) do
            items[#items + 1] = EnabledItem(RDB, buff, SpellLabel(buff), buff.class)
        end
        y = y - BuildCheckboxGrid(parent, y, items, GridChanged(false), refs)
        _, h = W:Spacer(parent, y, 20)
        return y - h, header
    end

    local STANCE_TIP = "Shows in combat only, while you are out of this form."
    local EARTH_SHIELD_ALLY_TIP =
        "Out of combat, reminds you when no groupmate has your Earth Shield (Elemental Orbit)."

    -- AURAS: Where to Show (+ sound cog) and the aura grid (Soulstone is
    -- the Warlock section's). Returns y and the header.
    local function BuildAuraSection(parent, y, refs)
        local W = CUI.Widgets
        local _
        local header, h = W:SectionHeader(parent, SECTION_AURAS, y)
        y = y - h
        _, h = SectionToggleRow(parent, y, {
            whereStore = AWhere,
            whereTooltip = "Pick which content these aura reminders appear in.\nRested areas (cities and inns) always stay hidden.",
            soundSec = ADB,
            soundField = "sectionSound",
            onChange = RequestRefresh,
        })
        y = y - h
        local items = {}
        for _, aura in ipairs(_G._CUABR_AURAS or {}) do
            if aura.key ~= "soulstone" then
                local tip = (aura.combatOnly and aura.isStance) and STANCE_TIP or nil
                items[#items + 1] = EnabledItem(ADB, aura, SpellLabel(aura), aura.class, tip)
            end
        end
        y = y - BuildCheckboxGrid(parent, y, items, GridChanged(true), refs)
        _, h = W:Spacer(parent, y, 20)
        return y - h, header
    end

    -- A class consumable section (Rogue Poisons, Paladin Rites, Shaman
    -- Imbues & Shields): its own Where to Show and sound, then its grid.
    local function BuildClassSection(parent, y, title, class, items, groupAuras, refs)
        local W = CUI.Widgets
        local _
        local h
        _, h = W:SectionHeader(parent, title, y)
        y = y - h
        _, h = SectionToggleRow(parent, y, {
            whereStore = CSpecialWhere(class),
            whereTooltip = SPECIAL_WHERE_TIP,
            soundSec = CDB,
            specialClass = class,
            onChange = RequestRefresh,
        })
        y = y - h
        y = y - BuildCheckboxGrid(parent, y, items, GridChanged(groupAuras), refs)
        _, h = W:Spacer(parent, y, 10)
        return y - h
    end

    -- The class consumable sections, in page order.
    local function BuildClassSections(parent, y, refs)
        local function Items(entryList, class)
            local items = {}
            for _, entry in ipairs(entryList or {}) do
                items[#items + 1] = EnabledItem(CDB, entry, SpellLabel(entry), class)
            end
            return items
        end
        y = BuildClassSection(
            parent,
            y,
            SECTION_ROGUE,
            "ROGUE",
            Items(_G._CUABR_ROGUE_POISONS, "ROGUE"),
            false,
            refs
        )
        y = BuildClassSection(
            parent,
            y,
            SECTION_PALADIN,
            "PALADIN",
            Items(_G._CUABR_PALADIN_RITES, "PALADIN"),
            false,
            refs
        )
        local shaman = Items(_G._CUABR_SHAMAN_IMBUES, "SHAMAN")
        for _, shield in ipairs(_G._CUABR_SHAMAN_SHIELDS or {}) do
            local tip = shield.key == "es_ally" and EARTH_SHIELD_ALLY_TIP or nil
            shaman[#shaman + 1] = EnabledItem(CDB, shield, CUI.L(shield.name), "SHAMAN", tip)
        end
        -- Earth Shield (Ally) turns group tracking on or off.
        return BuildClassSection(parent, y, SECTION_SHAMAN, "SHAMAN", shaman, true, refs)
    end

    -- A default-on toggle over section().enabled[key]; a change refreshes
    -- the reminders and rebuilds the preview.
    local function EnabledToggle(section, key, text, tooltip)
        return {
            type = "toggle",
            text = text,
            tooltip = tooltip,
            getValue = function()
                local tbl = section()
                return tbl and tbl.enabled and tbl.enabled[key] ~= false
            end,
            setValue = function(value)
                local tbl = section()
                if tbl and tbl.enabled then
                    tbl.enabled[key] = value
                    RequestRefresh()
                    RebuildPreviewHeader()
                end
            end,
        }
    end
    local PET_CLASSES = " Only applies to pet classes (Hunter, Warlock, Death Knight, Mage)."

    -- PETS: Where to Show | Missing Pet, then Passive Pet.
    local function BuildPetSection(parent, y)
        local W = CUI.Widgets
        local _
        local h
        _, h = W:SectionHeader(parent, "PETS", y)
        y = y - h
        _, h = SectionToggleRow(parent, y, {
            whereStore = CSpecialWhere("PET"),
            whereTooltip = "Pick which content the Missing Pet and Passive Pet reminders appear in.\nWarlock's Wrong Demon reminder uses the Where to Show in the Warlock section.\nRested areas (cities and inns) always stay hidden.",
            onChange = RequestRefresh,
            rightCfg = EnabledToggle(
                CDB,
                "pet",
                "Missing Pet",
                "Show a reminder when you don't have an active pet summoned." .. PET_CLASSES
            ),
        })
        y = y - h
        _, h = W:DualRow(
            parent,
            y,
            EnabledToggle(
                CDB,
                "pet_passive",
                "Passive Pet",
                "Show a reminder when your active pet is set to Passive stance." .. PET_CLASSES
            ),
            CUI.BlankRowCfg()
        )
        y = y - h
        _, h = W:Spacer(parent, y, 10)
        return y - h
    end

    -- Allowed Demons' items: each demon, locked (and left out of the
    -- summary) until its summon spell is known.
    local function DemonItems()
        local items = {}
        for _, pet in ipairs(_G._CUABR_WARLOCK_PETS or {}) do
            local function Unlearned() return not (_G._CUABR_Known and _G._CUABR_Known(pet.castSpell)) end
            items[#items + 1] = {
                key = pet.key,
                label = pet.name,
                lockedFn = Unlearned,
                excludeFromSummaryFn = Unlearned,
                lockedTooltip = function()
                    local name = _G._CUABR_SpellName and _G._CUABR_SpellName(pet.castSpell, pet.name)
                        or pet.name
                    return CUI.Lf("You have not learned %1$s.", name)
                end,
            }
        end
        return items
    end

    -- WARLOCK: Where to Show | Allowed Demons, then Wrong Demon | Soulstone,
    -- their labels in the Warlock colour. Returns y, the header and the
    -- Wrong Demon row (Soulstone's preview click leads there).
    local function BuildWarlockSection(parent, y)
        local W = CUI.Widgets
        local _
        local header, h = W:SectionHeader(parent, SECTION_WARLOCK, y)
        y = y - h
        local ctrlRow
        ctrlRow, h = SectionToggleRow(parent, y, {
            whereStore = CWarlockWhere,
            whereTooltip = "Pick which content these Warlock reminders appear in.\nMissing Pet and Passive Pet use the Where to Show in the Pets section.\nRested areas (cities and inns) always stay hidden.",
            onChange = RequestRefresh,
            rightCfg = Placeholder(
                "Allowed Demons",
                "Pick which demons count as correct for Wrong Demon. A demon only counts while its summon spell is known; with none picked (or everything picked), the reminder never fires."
            ),
        })
        y = y - h
        local items = DemonItems()
        local line
        line, h = W:DualRow(
            parent,
            y,
            EnabledToggle(
                CDB,
                "wrong_pet",
                "Wrong Demon",
                "Show a reminder when your Warlock's active pet isn't one of the demons picked in Allowed Demons. A demon only counts while its summon spell is known, so leaving only Felguard picked stays silent for specs/builds that haven't talented Summon Felguard."
            ),
            {
                type = "toggle",
                text = _G._CUABR_SpellName(20707, "Soulstone"),
                tooltip = "Show a reminder until your own Soulstone is active on you or another group member.",
                getValue = function()
                    local a = ADB()
                    return a and a.enabled and a.enabled.soulstone ~= false
                end,
                setValue = function(value)
                    local a = ADB()
                    if a and a.enabled then a.enabled.soulstone = value end
                    GridChanged(true)()
                end,
            }
        )
        y = y - h

        local wcc = RAID_CLASS_COLORS and RAID_CLASS_COLORS.WARLOCK
        if wcc then
            for _, region in ipairs({ ctrlRow._rightRegion, line._leftRegion, line._rightRegion }) do
                if region._label then region._label:SetTextColor(wcc.r, wcc.g, wcc.b, 1) end
            end
        end
        if not CUI._prebuilding then
            local region = ctrlRow._rightRegion
            if region._control then region._control:Hide() end
            local dropdown, refresh = CUI.BuildVisOptsCBDropdown(
                region,
                220,
                region:GetFrameLevel() + 2,
                items,
                function(keyName)
                    local cfg = CDB()
                    return cfg and cfg.wrongPetAllowed and cfg.wrongPetAllowed[keyName]
                end,
                function(keyName, value)
                    local cfg = CDB()
                    if cfg then
                        cfg.wrongPetAllowed = cfg.wrongPetAllowed or {}
                        cfg.wrongPetAllowed[keyName] = value
                    end
                    RequestRefresh()
                    RebuildPreviewHeader()
                end,
                nil,
                nil,
                nil,
                nil,
                nil,
                { emptyLabel = "All" }
            )
            PP.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
            region._control = dropdown
            region._lastInline = nil
            CUI.RegisterWidgetRefresh(refresh)
        end
        _, h = W:Spacer(parent, y, 10)
        return y - h, header, line
    end

    -- An overlay that swallows the mouse over target and says which toggle
    -- turns it on. Shown while that toggle is off.
    local function OffBlocker(target, toggleName)
        local block = CUI.NewSwatchBlocker(target)
        block:SetScript(
            "OnEnter",
            function() CUI.ShowWidgetTooltip(target, CUI.DisabledTooltip(toggleName)) end
        )
        block:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        return block
    end

    -- A consumable reminder's switch (off until ticked).
    local function ConsumableToggle(key, text, tooltip, after)
        return {
            type = "toggle",
            text = text,
            tooltip = tooltip,
            getValue = function()
                local cfg = CDB()
                return cfg and cfg.enabled and cfg.enabled[key]
            end,
            setValue = function(value)
                local cfg = CDB()
                if cfg and cfg.enabled then
                    cfg.enabled[key] = value
                    RequestRefresh()
                    RebuildPreviewHeader()
                end
                if after then after() end
            end,
        }
    end

    -- A consumable with a pick for what Click to Buff uses: its switch |
    -- Preferred (Last Used, then each choice). Returns the row and height.
    local function PreferredRow(parent, y, key, text, choices, prefKey)
        local values, order = { last_used = "Last Used" }, { "last_used" }
        for _, choice in ipairs(choices or {}) do
            values[choice.key] = choice.name
            order[#order + 1] = choice.key
        end
        return CUI.Widgets:DualRow(parent, y, ConsumableToggle(key, text), {
            type = "dropdown",
            text = "Preferred (Click to Buff)",
            dropdownWidth = 220,
            values = values,
            order = order,
            getValue = function()
                local cfg = CDB()
                return cfg and cfg[prefKey] or "last_used"
            end,
            setValue = function(value)
                local cfg = CDB()
                if cfg then
                    cfg[prefKey] = value
                    RequestRefresh()
                end
            end,
        })
    end

    -- Inky Black Potion's zone list: map IDs, comma separated, the current
    -- zone one click away.
    local function ChooseInkyZones()
        local cfg = CDB()
        CUI:ShowInputPopup({
            title = "Inky Black Potion Zone IDs",
            message = "Enter map zone IDs separated by commas.\nThe potion reminder will only show in these zones.",
            placeholder = "e.g. 2248, 2339",
            initialText = cfg and cfg.inkyBlackZones or "",
            maxLetters = 500,
            confirmText = "Save",
            extraButton = {
                text = "Add Current Zone",
                onClick = function(editBox)
                    local mapID = C_Map.GetBestMapForUnit("player")
                    if not mapID then return end
                    local text = editBox:GetText() or ""
                    editBox:SetText(text == "" and tostring(mapID) or (text .. ", " .. mapID))
                end,
            },
            onConfirm = function(text)
                local classColor = CDB()
                if classColor then
                    classColor.inkyBlackZones = text or ""
                    RequestRefresh()
                end
            end,
        })
    end

    -- The Choose Zones button on Inky Black's row, with a short hover fade.
    -- Anchored to the REGION edge, never the slot control: this slot is an
    -- empty label, and anchoring to it while the deferred label clamp
    -- anchors the label back to _lastInline forms an anchor family cycle
    -- (hard client error).
    local function InkyZonesButton(region)
        local button = CreateFrame("Button", nil, region)
        button:SetSize(110, 24)
        button:SetPoint("RIGHT", region, "RIGHT", -20, 0)
        button:SetFrameLevel(region:GetFrameLevel() + 5)
        region._lastInline = button
        local dark = CUI.DARK_BG
        local bg = CUI.SolidTex(button, "BACKGROUND", dark.r, dark.g, dark.b, 0.92)
        bg:SetAllPoints()
        local border = CUI.MakeRoundedBorder(button, 1, 1, 1, 0.3, bg)
        local label = CUI.MakeFont(button, 12, nil, 1, 1, 1)
        label:SetPoint("CENTER")
        label:SetText(CUI.L("Choose Zones"))

        local FADE = 0.1
        local lerp = CUI.lerp
        local progress, target = 0, 0
        local function Step(self, elapsed)
            local dir = (target == 1) and 1 or -1
            progress = progress + dir * (elapsed / FADE)
            if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                progress = target
                self:SetScript("OnUpdate", nil)
            end
            label:SetTextColor(1, 1, 1, lerp(0.5, 0.8, progress))
            border:SetColor(1, 1, 1, lerp(0.3, 0.5, progress))
        end
        button:SetScript("OnEnter", function(self)
            target = 1
            self:SetScript("OnUpdate", Step)
        end)
        button:SetScript("OnLeave", function(self)
            target = 0
            self:SetScript("OnUpdate", Step)
        end)
        button:SetScript("OnClick", ChooseInkyZones)

        local block = OffBlocker(button, "Inky Black Potion")
        local function Dim()
            local cfg = CDB()
            local isOff = not cfg or not cfg.enabled or not cfg.enabled.inky_black
            button:SetAlpha(isOff and 0.3 or 1)
            block:SetShown(isOff)
        end
        Dim()
        CUI.RegisterWidgetRefresh(Dim)
    end

    -- CONSUMABLES' reminder rows: Where to Show (+ sound cog), Flask, Food
    -- and Weapon Enhancement each with their Preferred pick, Augment Rune |
    -- Healthstone, Inky Black Potion | Choose Zones. Returns y and the rows
    -- the preview's clicks lead to.
    local function BuildConsumableRows(parent, y)
        local W = CUI.Widgets
        local _
        local rows = {}
        local h
        rows.header, h = W:SectionHeader(parent, SECTION_CONSUMABLES, y)
        y = y - h
        _, h = SectionToggleRow(parent, y, {
            whereStore = CWhere,
            whereTooltip = "Pick which content these consumable reminders appear in.\nRested areas (cities and inns) always stay hidden.",
            soundSec = CDB,
            soundField = "sectionSound",
            onChange = RequestRefresh,
        })
        y = y - h
        rows.flask, h = PreferredRow(parent, y, "flask", "Flask", _G._CUABR_FLASK_ITEMS, "preferredFlask")
        y = y - h
        rows.food, h = PreferredRow(parent, y, "food", "Food", _G._CUABR_FOOD_ITEMS, "preferredFood")
        y = y - h
        rows.weapon, h = PreferredRow(
            parent,
            y,
            "weapon_enchant",
            "Weapon Enhancement",
            _G._CUABR_WEAPON_ENCHANT_CHOICES,
            "preferredWeaponEnchant"
        )
        y = y - h
        -- Neither has a per-item control.
        rows.rune, h = W:DualRow(
            parent,
            y,
            ConsumableToggle("augment_rune", "Augment Rune"),
            EnabledToggle(
                CDB,
                "healthstone",
                "Healthstone",
                "Remind you to grab a Healthstone when a Warlock is in your group."
            )
        )
        y = y - h
        rows.inky, h = W:DualRow(
            parent,
            y,
            ConsumableToggle("inky_black", "Inky Black Potion", nil, function() CUI:RefreshPage() end),
            { type = "label", text = "" }
        )
        y = y - h
        if not CUI._prebuilding then InkyZonesButton(rows.inky._rightRegion) end
        return y, rows
    end

    local MANA_WARN = "Ready Check Mana Warning"
    -- The mana warning text shown for a moment, as its cog's edits are made.
    local function ApplyManaWarning()
        if _G._CUABR_RCWarnApply then _G._CUABR_RCWarnApply() end
    end

    -- Ready Check Mana Warning's inlines, right to left: its cog (font,
    -- size, offsets; font and offset edits switch the live preview on), the
    -- colour swatch (unset: the brightened mana colour the warning uses)
    -- and the eye that toggles the live preview. All three dim while the
    -- warning is off, which also ends the preview.
    local function ManaWarningInlines(region)
        local function Off()
            local cfg = CDB()
            return cfg ~= nil and cfg.rcManaWarn == false
        end
        local previewing = false
        local RefreshEye
        local function PreviewOn()
            previewing = true
            if RefreshEye then RefreshEye() end
            if _G._CUABR_RCWarnPreview then _G._CUABR_RCWarnPreview() end
        end
        local function Field(key, default, after)
            return function()
                local cfg = CDB()
                return cfg and cfg[key] or default
            end, function(value)
                local cfg = CDB()
                if cfg then
                    cfg[key] = value
                    after()
                end
            end
        end
        local function Slider(label, key, min, max, default, after)
            local get, set = Field(key, default, after)
            return { type = "slider", label = label, min = min, max = max, step = 1, get = get, set = set }
        end
        region._rcwFontValues, region._rcwFontOrder = CUI.BuildFontDropdownData()
        CUI.BuildInlineCog(region, {
            title = "Mana Warning Settings",
            disabled = Off,
            disabledTooltip = MANA_WARN,
            rows = {
                {
                    type = "dropdown",
                    label = "Mana Warning Font",
                    values = region._rcwFontValues,
                    order = region._rcwFontOrder,
                    get = function()
                        local cfg = CDB()
                        return (cfg and cfg.rcManaWarnFont) or "__global"
                    end,
                    set = function(value)
                        local cfg = CDB()
                        if cfg then
                            cfg.rcManaWarnFont = (value ~= "__global") and value or nil
                            ApplyManaWarning()
                            PreviewOn()
                        end
                    end,
                },
                Slider("Text Size", "rcManaWarnSize", 10, 72, 48, ApplyManaWarning),
                Slider("X Offset", "rcManaWarnX", -600, 600, 0, PreviewOn),
                Slider("Y Offset", "rcManaWarnY", -600, 600, 0, PreviewOn),
            },
        })

        local swatch = CUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, function()
            local cfg = CDB()
            local col = cfg and cfg.rcManaWarnColor
            if col then return col.r, col.g, col.b, 1 end
            local mana = CUI.GetPowerColor("MANA")
            if mana then
                return math.min(mana.r * 1.5, 1), math.min(mana.g * 1.5, 1), math.min(mana.b * 1.5, 1), 1
            end
            return 0, 0.825, 1, 1
        end, function(red, green, blue)
            local cfg = CDB()
            if cfg then
                cfg.rcManaWarnColor = { r = red, g = green, b = blue }
                ApplyManaWarning()
            end
        end, false, 20)
        swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = swatch
        local swatchBlock = OffBlocker(swatch, MANA_WARN)

        local eye = CreateFrame("Button", nil, region)
        eye:SetSize(26, 26)
        eye:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = eye
        eye:SetFrameLevel(region:GetFrameLevel() + 5)
        CUI.SetGlyphAlpha(eye, 0.4)
        local eyeTex = eye:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        RefreshEye = function()
            eyeTex:SetTexture(previewing and CUI.EYE_INVISIBLE_ICON or CUI.EYE_VISIBLE_ICON)
        end
        RefreshEye()
        eye:SetScript("OnEnter", function(self)
            CUI.SetGlyphAlpha(self, 0.7)
            CUI.ShowWidgetTooltip(self, "Preview mana warning")
        end)
        eye:SetScript("OnLeave", function(self)
            CUI.HideWidgetTooltip()
            CUI.SetGlyphAlpha(self, 0.4)
        end)
        eye:SetScript("OnClick", function()
            previewing = not previewing
            RefreshEye()
            local step
            if previewing then
                step = _G._CUABR_RCWarnPreview
            else
                step = _G._CUABR_RCWarnHidePreview
            end
            if step then step() end
        end)
        local eyeBlock = OffBlocker(eye, MANA_WARN)

        local function Dim()
            local isOff = Off()
            if isOff then
                previewing = false
                RefreshEye()
            end
            swatch:SetAlpha(isOff and 0.3 or 1)
            swatchBlock:SetShown(isOff)
            CUI.SetGlyphAlpha(eye, isOff and 0.15 or 0.4)
            eyeBlock:SetShown(isOff)
        end
        Dim()
        CUI.RegisterWidgetRefresh(Dim)
    end

    -- Show Without Item in Bags | Ready Check Mana Warning (+ eye, swatch, cog).
    local function BuildConsumableExtras(parent, y)
        local line, h = CUI.Widgets:DualRow(parent, y, {
            type = "toggle",
            text = "Show Without Item in Bags",
            tooltip = "When on, augment rune/flask/food/weapon reminders still show (dimmed) when you have no matching item in your bags, as a prompt to restock.\nWhen off, they are hidden entirely if you don't carry the item.",
            getValue = function()
                local cfg = CDB()
                return not cfg or cfg.showWithoutItem ~= false
            end,
            setValue = function(value)
                local cfg = CDB()
                if cfg then
                    cfg.showWithoutItem = value
                    RequestRefresh()
                end
            end,
        }, {
            type = "toggle",
            text = MANA_WARN,
            tooltip = "Flashes LOW MANA during an out-of-combat raid ready check while you are a healer under 80% mana.",
            getValue = function()
                local cfg = CDB()
                return not cfg or cfg.rcManaWarn ~= false
            end,
            setValue = function(value)
                local cfg = CDB()
                if cfg then cfg.rcManaWarn = value end
                if not value and _G._CUABR_RCWarnHidePreview then _G._CUABR_RCWarnHidePreview() end
                if _G._CUABR_RCWarnUpdateReg then _G._CUABR_RCWarnUpdateReg() end
                CUI:RefreshPage()
            end,
        })
        if not CUI._prebuilding then ManaWarningInlines(line._rightRegion) end
        return y - h
    end

    -- A WoW Forever reminder switch over forever[key]: off until ticked, or
    -- (defaultOn) on until unticked. rebuild: the page follows it (a cog).
    local function ForeverToggle(key, text, tooltip, defaultOn, rebuild)
        return {
            type = "toggle",
            text = text,
            tooltip = tooltip,
            getValue = function()
                local foreverCfg = FDB()
                if defaultOn then return not foreverCfg or foreverCfg[key] ~= false end
                return foreverCfg and foreverCfg[key] == true
            end,
            setValue = function(value)
                local foreverCfg = FDB()
                if not foreverCfg then return end
                foreverCfg[key] = value
                RequestRefresh()
                if rebuild then CUI:RefreshPage() end
            end,
        }
    end

    -- A Class Buffs checklist entry: a buff with lines names the first and
    -- last rank of each line in its tooltip (and says when only your own
    -- counts); a single buff is named after its top rank.
    local function ClassBuffItem(buff)
        if not buff.label then
            local line = buff.lines[1]
            return { key = buff.key, label = _G._CUABR_SpellName(line[#line], buff.key) }
        end
        local nameList, seen = {}, {}
        for _, line in ipairs(buff.lines) do
            for _, id in ipairs({ line[1], line[#line] }) do
                local name = _G._CUABR_SpellName(id)
                if name and not seen[name] then
                    seen[name] = true
                    nameList[#nameList + 1] = name
                end
            end
        end
        local tip = table.concat(nameList, "\n")
        if buff.own then tip = tip .. "\n\n" .. CUI.L("Only your own counts.") end
        return { key = buff.key, label = buff.menu or buff.label, tooltip = tip }
    end

    -- Class Buffs: one checkbox per buff of the class (ticked: its own
    -- default until picked, EABR.FvClassBuffOn).
    local function ClassBuffList(region, classBuffs)
        local items, byKey = {}, {}
        for _, buff in ipairs(classBuffs) do
            items[#items + 1] = ClassBuffItem(buff)
            byKey[buff.key] = buff
        end
        local dropdown, refresh = CUI.BuildVisOptsCBDropdown(
            region,
            170,
            region:GetFrameLevel() + 2,
            items,
            function(key)
                local foreverCfg = FDB()
                return _G._CUABR_FvClassBuffOn(byKey[key], foreverCfg and foreverCfg.classBuffPicks)
            end,
            function(key, value)
                local foreverCfg = FDB()
                if foreverCfg then
                    foreverCfg.classBuffPicks = foreverCfg.classBuffPicks or {}
                    foreverCfg.classBuffPicks[key] = value and true or false
                    RequestRefresh()
                end
            end
        )
        PP.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
        region._control = dropdown
        region._lastInline = nil
        CUI.RegisterWidgetRefresh(refresh)
    end

    -- Weapon Buffs' cog rows for the player's class: what each hand gets
    -- (imbue or poison where the class has them, then stone or oil; the off
    -- hand only when it can dual wield), the rank, hide with none in bags,
    -- and how early to remind.
    local function WeaponBuffRows(class)
        local function Choices(isImbue)
            local values, order = { auto = "Auto", off = "Off" }, { "auto", "off" }
            for _, b in ipairs(_G._CUABR_FV_WEAPON_BUFFS or {}) do
                if (b.imbue == true) == isImbue and (not b.class or b.class == class) then
                    values[b.key] = b.name or _G._CUABR_SpellName(b.spells[#b.spells], b.key)
                    order[#order + 1] = b.key
                end
            end
            return values, order
        end
        local function Hand(label, field, values, order)
            return {
                type = "dropdown",
                label = label,
                values = values,
                order = order,
                ddWidth = 200,
                get = function()
                    local foreverCfg = FDB()
                    local tbl = foreverCfg and foreverCfg.weaponHands and foreverCfg.weaponHands[class]
                    return tbl and tbl[field] or "auto"
                end,
                set = function(value)
                    local foreverCfg = FDB()
                    if not foreverCfg then return end
                    foreverCfg.weaponHands = foreverCfg.weaponHands or {}
                    foreverCfg.weaponHands[class] = foreverCfg.weaponHands[class] or {}
                    foreverCfg.weaponHands[class][field] = value ~= "auto" and value or nil
                    RequestRefresh()
                end,
            }
        end
        local imbueValues, imbueOrder = Choices(true)
        local tempValues, tempOrder = Choices(false)
        local hasImbues = #imbueOrder > 2
        local imbueWord = class == "ROGUE" and "Poison" or "Imbue"
        local rows = {}
        local function Hands(side, prefix)
            if hasImbues then
                rows[#rows + 1] = Hand(side .. " " .. imbueWord, prefix .. "Imbue", imbueValues, imbueOrder)
            end
            rows[#rows + 1] = Hand(side .. " Stone or Oil", prefix .. "Temp", tempValues, tempOrder)
        end
        Hands("Main Hand", "mh")
        if not CanDualWield or CanDualWield() then Hands("Off Hand", "oh") end
        rows[#rows + 1] = {
            type = "dropdown",
            label = "Rank to Use",
            ddWidth = 200,
            values = { high = "Highest Owned", low = "Lowest Owned" },
            order = { "high", "low" },
            get = function()
                local foreverCfg = FDB()
                return foreverCfg and foreverCfg.weaponLowRank and "low" or "high"
            end,
            set = function(value)
                local foreverCfg = FDB()
                if foreverCfg then
                    foreverCfg.weaponLowRank = value == "low"
                    RequestRefresh()
                end
            end,
        }
        rows[#rows + 1] = {
            type = "toggle",
            label = "Hide When None in Bags",
            tooltip = "Hides a reminder when you have none of its item in your bags.\nOff: a chosen item still shows, greyed out. Auto only ever picks items you have.",
            get = function()
                local foreverCfg = FDB()
                return not foreverCfg or foreverCfg.weaponHideNoItem ~= false
            end,
            set = function(value)
                local foreverCfg = FDB()
                if foreverCfg then
                    foreverCfg.weaponHideNoItem = value
                    RequestRefresh()
                end
            end,
        }
        rows[#rows + 1] = {
            type = "slider",
            label = "Show Below (Minutes)",
            min = 0,
            max = 10,
            step = 1,
            tooltip = "Show a reminder before a poison, imbue, stone or oil runs out.\n0 = only once it has run out.\n1-10 = when it has less than this many minutes left.",
            get = function()
                local foreverCfg = FDB()
                return foreverCfg and foreverCfg.weaponShowBelow or 1
            end,
            set = function(value)
                local foreverCfg = FDB()
                if foreverCfg then
                    foreverCfg.weaponShowBelow = value
                    RequestRefresh()
                end
            end,
        }
        return rows
    end

    -- WOW FOREVER: on that client the rest of the page. Where to Show |
    -- Reminder Sound, Camp Benefits | Sleeping Bag, Well Fed | Gathering
    -- Tracking (+ cog), Find Treasure | Weapon Buffs (+ cog), Mage Armors or
    -- Class Buffs, then Add Custom Spell with the tracked spells and the
    -- spell groups. Returns y.
    local function BuildForeverSection(parent, y)
        local W = CUI.Widgets
        local _
        local h
        local building = not CUI._prebuilding
        _, h = W:SectionHeader(parent, SECTION_FOREVER, y)
        y = y - h
        _, h = SectionToggleRow(parent, y, {
            whereStore = FWhere,
            whereItems = FOREVER_SECTION_WHERE_ITEMS,
            whereTooltip = "Pick which content the WoW Forever reminders appear in.\nRested areas (cities and inns) always stay hidden.",
            soundSec = FDB,
            soundField = "sectionSound",
            onChange = RequestRefresh,
        })
        y = y - h
        _, h = W:DualRow(
            parent,
            y,
            ForeverToggle(
                "camp",
                "Camp Benefits",
                "Reminds you when the Camp Benefits campfire buff is missing.",
                true
            ),
            ForeverToggle(
                "sleepingBag",
                "Sleeping Bag",
                "Reminds you when your Well-Rested buff is missing or under 3 stacks.\nOnly while a Cozy Sleeping Bag is in your bags and you are below max level.\nClick the icon to use it."
            )
        )
        y = y - h
        -- Well Fed reads the client's own name for the buff (19705, EABR.WELL_FED), so it is localized.
        local gatherRow
        gatherRow, h = W:DualRow(
            parent,
            y,
            ForeverToggle(
                "wellFed",
                _G._CUABR_SpellName(19705, "Well Fed"),
                "Reminds you when you have no Well Fed buff."
            ),
            ForeverToggle(
                "gather",
                "Gathering Tracking",
                "Reminds you when no gathering tracking is on.",
                false,
                true
            )
        )
        y = y - h
        if building then
            CUI.BuildInlineCog(gatherRow._rightRegion, {
                title = "Gathering Tracking",
                disabled = function()
                    local foreverCfg = FDB()
                    return not (foreverCfg and foreverCfg.gather == true)
                end,
                disabledTooltip = "Gathering Tracking",
                rows = {
                    {
                        type = "toggle",
                        label = "Ignore If Class Tracking Is Active",
                        get = function()
                            local foreverCfg = FDB()
                            return not foreverCfg or foreverCfg.gatherClassTrack ~= false
                        end,
                        set = function(value)
                            local foreverCfg = FDB()
                            if foreverCfg then
                                foreverCfg.gatherClassTrack = value
                                RequestRefresh()
                            end
                        end,
                    },
                },
            })
        end

        local class = select(2, UnitClass("player"))
        local classBuffs = not MAGE and _G._CUABR_FvClassBuffs and _G._CUABR_FvClassBuffs()[class]
        local weaponRow
        weaponRow, h = W:DualRow(
            parent,
            y,
            ForeverToggle(
                "treasure",
                _G._CUABR_SpellName(2481, "Find Treasure"),
                "Reminds Dwarves when Find Treasure is off."
            ),
            ForeverToggle(
                "weapon",
                "Weapon Buffs",
                "Reminds you when a weapon has no poison, imbue, stone or oil.\nClick the icon to apply one from your bags.",
                false,
                true
            )
        )
        y = y - h
        local classRow
        if MAGE then
            classRow, h = W:DualRow(
                parent,
                y,
                ForeverToggle(
                    "mageArmor",
                    "Mage Armors",
                    "Reminds you when no Frost Armor, Ice Armor or Mage Armor is up.\nThe icon is the one you last had on; click it to cast it."
                ),
                CUI.BlankRowCfg()
            )
            y = y - h
        elseif classBuffs then
            classRow, h = W:DualRow(parent, y, {
                type = "label",
                text = "Class Buffs",
                tooltip = "Reminds you when one of your class's own buffs is missing.\nClick the icon to cast it.\nA custom spell or spell group for a ticked buff pauses meanwhile.",
            }, CUI.BlankRowCfg())
            y = y - h
        end
        if building then
            if classBuffs then ClassBuffList(classRow._leftRegion, classBuffs) end
            CUI.BuildInlineCog(weaponRow._rightRegion, {
                title = "Weapon Buffs",
                disabled = function()
                    local foreverCfg = FDB()
                    return not (foreverCfg and foreverCfg.weapon == true)
                end,
                disabledTooltip = "Weapon Buffs",
                minWidth = 320,
                rows = WeaponBuffRows(class),
            })
        end

        -- Add Custom Spell, paired with the tracked spells, then the groups.
        y = BuildForeverCustomRows(parent, y, {
            type = "input",
            text = "Add Custom Spell",
            inputStyle = "popup",
            placeholder = "Spell ID",
            inputWidth = 110,
            tooltip = "Type a spell ID and press Enter to be reminded whenever that buff is missing.\nUnknown IDs are ignored.",
            getValue = function() return "" end,
            setValue = function(text)
                local foreverCfg = FDB()
                if foreverCfg then
                    foreverCfg.customIDs = foreverCfg.customIDs or {}
                    AddSpellIDToList(foreverCfg.customIDs, text)
                end
            end,
        })
        return BuildForeverGroupSections(parent, y)
    end

    -- DISPLAY: shape, border, name / count / glow and layout rows. Returns
    -- y, the header and the two rows the preview's clicks lead to.
    local function BuildDisplaySection(parent, y)
        local header, h = CUI.Widgets:SectionHeader(parent, SECTION_DISPLAY, y)
        y = BuildShapeRow(parent, y - h)
        local borderRow, nameRow
        y, borderRow = BuildBorderRows(parent, y)
        y, nameRow = BuildTextRows(parent, y)
        return BuildLayoutRows(parent, y), header, borderRow, nameRow
    end

    -- Where each preview icon's click leads: its category's section and row,
    -- each raid buff / aura grid cell, and each consumable's own row.
    local function MapPreviewClicks(cfg, cells)
        local map = _eabrClickMappings
        wipe(map)
        local function To(key, section, target) map[key] = { section = section, target = target or section } end
        To("display", cfg.display, cfg.border)
        To("showText", cfg.display, cfg.name)
        To("raidbuff", cfg.raid)
        To("aura", cfg.aura)
        To("consumable", cfg.consum.header, cfg.consum.flask)
        To("item:soulstone", cfg.warlock, cfg.warlockRow)
        for key, cell in pairs(cells) do
            To("item:" .. key, cell)
        end
        local c = cfg.consum
        for key, line in pairs({
            flask = c.flask,
            food = c.food,
            weapon_enchant = c.weapon,
            augment_rune = c.rune,
            healthstone = c.rune,
            inky_black = c.inky,
        }) do
            To("item:" .. key, line)
        end
    end

    local function BuildRemindersPage(pageName, parent, yOffset)
        local y = yOffset
        local cells = {} -- [item key] = its grid cell (the preview's item clicks)
        local cfg = {} -- the sections and rows the preview's clicks lead to

        -- The preview header (retail only; WoW Forever has no preview).
        if not FOREVER then CUI:SetContentHeader(_previewHeaderBuilder) end
        parent._showRowDivider = true

        y = ClickInfoLine(parent, y)
        if FOREVER then y = ForeverPurposeBanner(parent, y) end
        y = BuildCoreSection(parent, y)
        y, cfg.display, cfg.border, cfg.name = BuildDisplaySection(parent, y)
        y, cfg.raid = BuildRaidBuffSection(parent, y, cells)
        if FOREVER then
            -- No preview header here, so no click-to-scroll mappings to wire.
            return math.abs(BuildForeverSection(parent, y))
        end
        y, cfg.aura = BuildAuraSection(parent, y, cells)
        y = BuildClassSections(parent, y, cells)
        y = BuildPetSection(parent, y)
        y, cfg.warlock, cfg.warlockRow = BuildWarlockSection(parent, y)
        y, cfg.consum = BuildConsumableRows(parent, y)
        y = BuildConsumableExtras(parent, y)
        MapPreviewClicks(cfg, cells)
        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Talent Reminders Page
    ---------------------------------------------------------------------------
    -- Owner of the page's kept popups (Pool.Kept): the zone popup and the
    -- talent popup are made once for the session, on UIParent.
    local _trPopups = {}

    local function TalentRemindersChanged()
        if _G._CUABR_TR_RequestRefresh then _G._CUABR_TR_RequestRefresh() end
    end

    -- Whether a reminder covers a zone. One saved with the single zone of
    -- an older version holds it in zoneName while it has no list.
    local function ReminderHasZone(r, zoneName)
        local entryList = r.zoneNames
        if entryList and #entryList > 0 then return tContains(entryList, zoneName) end
        return r.zoneName == zoneName
    end
    -- A reminder's zone list for an edit; an older version's single zone
    -- moves into it on the first edit.
    local function EditableZoneList(r)
        r.zoneNames = r.zoneNames or {}
        local entryList = r.zoneNames
        if #entryList == 0 and r.zoneName then entryList[1] = r.zoneName end
        return entryList
    end

    -- Every talent of the active loadout's class and spec trees (hero trees
    -- left out), once per spell, by name, live from C_Traits.
    local function GetAllTalents()
        local talents = {}
        local configID = C_ClassTalents
            and C_ClassTalents.GetActiveConfigID
            and C_ClassTalents.GetActiveConfigID()
        local config = configID and C_Traits and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
        local treeID = config and config.treeIDs and config.treeIDs[1]
        local nodes = treeID and C_Traits.GetTreeNodes(treeID)
        if not nodes then return talents end
        local seen = {}
        local function Add(entryID)
            local entry = C_Traits.GetEntryInfo(configID, entryID)
            local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
            local id = def and def.spellID
            if id and not seen[id] then
                local name = C_Spell.GetSpellName(id)
                if name and name ~= "" then
                    seen[id] = true
                    talents[#talents + 1] = { spellID = id, name = name }
                end
            end
        end
        for _, nodeID in ipairs(nodes) do
            local node = C_Traits.GetNodeInfo(configID, nodeID)
            if
                node
                and node.ID
                and node.ID > 0
                and node.entryIDs
                and #node.entryIDs > 0
                and not node.subTreeID
            then
                for _, entryID in ipairs(node.entryIDs) do
                    Add(entryID)
                end
            end
        end
        table.sort(talents, function(lhs, rhs) return lhs.name < rhs.name end)
        return talents
    end

    local TR_DD_BG = { 0.088, 0.098, 0.111, 0.9 }
    local TR_DD_BG_HOVER = { 0.128, 0.120, 0.113, 1 }
    local TR_ROW_TEXT = { 0.75, 0.75, 0.78, 1 }
    local TR_SEARCH_H = 26

    -- A wide dropdown button: dark box, border, a one-line label (dim until
    -- a pick) before the arrow, lighter while hovered.
    -- place(button) anchors it before the art is made (the arrow's pixel fit reads where it sits).
    local function TRDropdownButton(parent, w, h, text, fontPath, arrowSize, place)
        local button = CreateFrame("Button", nil, parent)
        PP.Size(button, w, h)
        place(button)
        button:SetFrameLevel(parent:GetFrameLevel() + 1)
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(unpack(TR_DD_BG))
        CUI.MakeRoundedBorder(button, 1, 1, 1, 0.20, bg)
        local label = button:CreateFontString(nil, "OVERLAY")
        label:SetFont(fontPath, 13, GetABROptOutline())
        label:SetTextColor(1, 1, 1, 0.50)
        label:SetMaxLines(1)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetText(CUI.L(text))
        local arrow = CUI.MakeDropdownArrow(button, arrowSize, CUI.PanelPP)
        -- The label's inset matches the arrow's size (14 on the zone box, 12 on the talent box).
        label:SetPoint("LEFT", button, "LEFT", arrowSize, 0)
        label:SetPoint("RIGHT", arrow, "LEFT", -5, 0)
        button._bg = bg
        return button, label
    end
    local function TRDropdownHover(button)
        button:SetScript("OnEnter", function() button._bg:SetColorTexture(unpack(TR_DD_BG_HOVER)) end)
        button:SetScript("OnLeave", function() button._bg:SetColorTexture(unpack(TR_DD_BG)) end)
    end

    -- A kept list popup under button: a search box (placeholder while
    -- empty, Escape lets go), a smooth-scrolling list child, closed by a
    -- click outside it or the button, opened and closed by the button and
    -- closed when the button hides. Returns the popup, its list child, the
    -- search box, its placeholder and the list's ScrollTo.
    local function TRSearchPopup(key, button, w, listH, fontPath)
        local dialog = Pool.Kept(_trPopups, key, "Frame", UIParent)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(200)
        dialog:SetClampedToScreen(true)
        dialog:SetSize(w, listH + TR_SEARCH_H + 10)
        dialog:Hide()
        local bg = dialog:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.098, 0.090, 0.082, 0.97)
        CUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.12, bg, nil, true)

        local searchBox = CreateFrame("EditBox", nil, dialog)
        searchBox:SetSize(w - 16, TR_SEARCH_H)
        searchBox:SetPoint("TOP", dialog, "TOP", 0, -6)
        searchBox:SetFrameLevel(dialog:GetFrameLevel() + 3)
        searchBox:SetFont(fontPath, 11, "")
        searchBox:SetTextColor(1, 1, 1, 0.9)
        searchBox:SetJustifyH("LEFT")
        searchBox:SetAutoFocus(false)
        searchBox:SetMaxLetters(30)
        searchBox:SetTextInsets(4, 4, 0, 0)
        local searchBg = searchBox:CreateTexture(nil, "BACKGROUND")
        searchBg:SetAllPoints()
        searchBg:SetColorTexture(0, 0, 0, 0.4)
        CUI.RoundBody(searchBox, searchBg)
        local placeholder = searchBox:CreateFontString(nil, "OVERLAY")
        placeholder:SetFont(fontPath, 11, "")
        placeholder:SetTextColor(0.5, 0.5, 0.5, 0.6)
        placeholder:SetPoint("LEFT", searchBox, "LEFT", 4, 0)
        placeholder:SetText(CUI.L("Search..."))
        searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        local scroll = CreateFrame("ScrollFrame", nil, dialog)
        scroll:SetPoint("TOPLEFT", dialog, "TOPLEFT", 0, -(TR_SEARCH_H + 10))
        scroll:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", 0, 4)
        scroll:SetFrameLevel(dialog:GetFrameLevel() + 1)
        scroll:EnableMouseWheel(true)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetWidth(w)
        scroll:SetScrollChild(child)
        local _, scrollTo = CUI.AttachSmoothScrollbar(scroll, {
            step = 40,
            thumbMin = 20,
            rightInset = 4,
            child = child,
        })
        dialog:SetScript(
            "OnMouseWheel",
            function(_, delta) scroll:GetScript("OnMouseWheel")(scroll, delta) end
        )
        dialog:SetScript("OnUpdate", function()
            if not dialog:IsMouseOver() and not button:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                dialog:Hide()
            end
        end)
        button:SetScript("OnClick", function() dialog:SetShown(not dialog:IsShown()) end)
        return dialog, child, searchBox, placeholder, scrollTo
    end

    -- A popup list row at slot i, with its (clear) hover tint.
    local function TRPopupRow(child, i, h)
        local line = CreateFrame("Button", nil, child)
        line:SetHeight(h)
        line:SetPoint("TOPLEFT", child, "TOPLEFT", 1, -(i - 1) * h)
        line:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, -(i - 1) * h)
        local highlight = line:CreateTexture(nil, "ARTWORK")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0)
        line._hl = highlight
        return line
    end
    local function TRRowLabel(line, fontPath, text)
        local label = line:CreateFontString(nil, "OVERLAY")
        label:SetFont(fontPath, 11, GetABROptOutline())
        label:SetTextColor(unpack(TR_ROW_TEXT))
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetText(text)
        line:SetScript("OnEnter", function()
            label:SetTextColor(1, 1, 1, 1)
            line._hl:SetColorTexture(1, 1, 1, 0.08)
        end)
        line:SetScript("OnLeave", function()
            label:SetTextColor(unpack(TR_ROW_TEXT))
            line._hl:SetColorTexture(1, 1, 1, 0)
        end)
        return label
    end

    -- Shows the rows whose name (row[field]) holds the search text, packed
    -- from the top; returns how many show.
    local function TRFilter(rows, child, h, query, field)
        local shown = 0
        for _, line in ipairs(rows) do
            if query == "" or strfind(strlower(line[field]), query, 1, true) then
                line:Show()
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", child, "TOPLEFT", 1, -shown * h)
                line:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, -shown * h)
                shown = shown + 1
            else
                line:Hide()
            end
        end
        child:SetHeight(math.max(1, shown * h))
        return shown
    end

    -- A red border that pulses for a moment on a row that is missing its pick.
    local function PulseRedBorder(line)
        if not line then return end
        if not line._redPulse then
            local frame = CreateFrame("Frame", nil, line)
            frame:SetAllPoints()
            frame:SetFrameLevel(line:GetFrameLevel() + 10)
            frame._border = CUI.MakeBorder(frame, 1, 0.2, 0.2, 1, CUI.PanelPP)
            line._redPulse = frame
        end
        local frame = line._redPulse
        frame:Show()
        frame:SetAlpha(1)
        local t = 0
        frame:SetScript("OnUpdate", function(self, elapsed)
            t = t + elapsed
            if t < 0.8 then
                self:SetAlpha(0.5 + 0.5 * math.sin(t * 10))
            elseif t < 1.5 then
                self:SetAlpha(math.max(0, 1 - (t - 0.8) / 0.7))
            else
                self:SetScript("OnUpdate", nil)
                self:Hide()
            end
        end)
    end

    -- The page's green call-to-action button (as Done), brightening on hover.
    local function GreenButton(parent, w, h, text, fontPath)
        local button = CreateFrame("Button", nil, parent)
        button:SetSize(w, h)
        local dark = CUI.DARK_BG
        local bg = CUI.SolidTex(button, "BACKGROUND", dark.r, dark.g, dark.b, 0.92)
        bg:SetAllPoints()
        local brandGreen = CUI.CLUDES_GREEN or { r = 0.298, g = 0.788, b = 0.941 }
        local border = CUI.MakeRoundedBorder(button, brandGreen.r, brandGreen.g, brandGreen.b, 0.7, bg)
        local label = button:CreateFontString(nil, "OVERLAY")
        label:SetPoint("CENTER")
        label:SetFont(fontPath, 13, GetABROptOutline())
        label:SetTextColor(brandGreen.r, brandGreen.g, brandGreen.b, 0.7)
        label:SetText(CUI.L(text))
        local lerp = CUI.lerp
        local FADE = 0.1
        local progress, target = 0, 0
        local function Step(self, elapsed)
            local dir = (target == 1) and 1 or -1
            progress = progress + dir * (elapsed / FADE)
            if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                progress = target
                self:SetScript("OnUpdate", nil)
            end
            label:SetTextColor(brandGreen.r, brandGreen.g, brandGreen.b, lerp(0.7, 1, progress))
            border:SetColor(brandGreen.r, brandGreen.g, brandGreen.b, lerp(0.7, 1, progress))
        end
        button:SetScript("OnEnter", function(self)
            target = 1
            self:SetScript("OnUpdate", Step)
        end)
        button:SetScript("OnLeave", function(self)
            target = 0
            self:SetScript("OnUpdate", Step)
        end)
        return button
    end

    local NOT_NEEDED_VALUES = {
        never = "Never",
        season = "Current Season Instances",
        all = "All Instances",
    }
    local NOT_NEEDED_ORDER = { "never", "season", "all" }
    local TR_PAD = 45 -- the page's content inset
    local TR_ROW_H = 50
    local TR_SIDE_PAD = 20
    -- Both dropdowns of a reminder row; wide enough for the longest zone name.
    local TR_ROW_DD_W = 220

    -- A DualRow-styled list row at yOff: alternating background and a centre divider.
    local function TRListRow(container, yOff, index)
        local line = CreateFrame("Frame", nil, container)
        PP.Size(line, container:GetWidth() - TR_PAD * 2, TR_ROW_H)
        PP.Point(line, "TOPLEFT", container, "TOPLEFT", TR_PAD, yOff)
        local bg = line:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, (index % 2 == 0) and 0.2 or 0.1)
        local divider = line:CreateTexture(nil, "ARTWORK")
        divider:SetColorTexture(1, 1, 1, 0.06)
        divider:SetWidth(1)
        PP.Point(divider, "TOP", line, "TOP", 0, 0)
        PP.Point(divider, "BOTTOM", line, "BOTTOM", 0, 0)
        return line
    end

    -- The saved reminders the picker can still reach: at least one of their
    -- zones is still on this season's list. Rotated-out zones keep their
    -- reminders (hidden here, never deleted); re-adding a zone revives them.
    local function VisibleReminders(reminders)
        local current = {}
        for _, z in ipairs(_G._CUABR_TALENT_REMINDER_ZONES or {}) do
            current[z.name] = true
        end
        local visible = {}
        for idx, r in ipairs(reminders) do
            local entryList = r.zoneNames
            local live = false
            if entryList and #entryList > 0 then
                for _, zoneName in ipairs(entryList) do
                    live = live or current[zoneName] == true
                end
            else
                live = r.zoneName ~= nil and current[r.zoneName] == true
            end
            if live then visible[#visible + 1] = idx end
        end
        return visible
    end

    local function BuildTalentRemindersPage(pageName, parent, yOffset)
        local W = CUI.Widgets
        local y = yOffset
        local _, h
        local fontPath = CUI.GetFontPath("auraBuff")
            or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
        parent._showRowDivider = true

        -- The add form's picks.
        local pickedZones = {} -- [zone index] = true
        local pickedSpellID, pickedName

        local zones = _G._CUABR_TALENT_REMINDER_ZONES or {}
        local zoneByName = {}
        for _, z in ipairs(zones) do
            if z.name then zoneByName[z.name] = z end
        end
        local function ZoneName(name)
            if not name or name == "" then return CUI.L("Unknown") end
            local z = zoneByName[name]
            local text = CUI.L(name)
            return (z and z.type == "raid") and (text .. CUI.L(" (Raid)")) or text
        end
        -- The zone button's text: the picked zones, sorted, else the prompt.
        local function PickedZonesText()
            local nameList = {}
            for idx, on in pairs(pickedZones) do
                if on and zones[idx] then nameList[#nameList + 1] = ZoneName(zones[idx].name) end
            end
            if #nameList == 0 then return "Select Dungeon/Raid/PvP Zone" end
            table.sort(nameList)
            return table.concat(nameList, ", ")
        end

        -- The zone picker: a wide centred dropdown with a checkbox list.
        local DD_W = 350
        local ZONE_H = 38
        y = y - 30
        local zoneRow = CreateFrame("Frame", nil, parent)
        PP.Size(zoneRow, parent:GetWidth() - TR_PAD * 2, ZONE_H + 30)
        PP.Point(zoneRow, "TOPLEFT", parent, "TOPLEFT", TR_PAD, y)
        local zoneBtn, zoneLabel = TRDropdownButton(
            zoneRow,
            DD_W,
            ZONE_H,
            "Select Dungeon/Raid/PvP Zone",
            fontPath,
            14,
            function(button) PP.Point(button, "TOP", zoneRow, "TOP", 0, 0) end
        )
        -- Kept for the session and dressed again by every build; the global
        -- search's hidden pre-build makes none (nothing in it to index).
        if not CUI._prebuilding then
            local ITEM_H = 28
            local dialog, child, searchBox, placeholder, scrollTo =
                TRSearchPopup("zone", zoneBtn, DD_W, math.min(#zones * ITEM_H + 8, 300), fontPath)
            local brandGreen = CUI.CLUDES_GREEN or { r = 0.298, g = 0.788, b = 0.941 }
            local rows = {}
            for i, z in ipairs(zones) do
                local line = TRPopupRow(child, i, ITEM_H)
                local boxFrame = CreateFrame("Frame", nil, line)
                boxFrame:SetSize(14, 14)
                boxFrame:SetPoint("LEFT", line, "LEFT", 10, 0)
                local boxBg = boxFrame:CreateTexture(nil, "BACKGROUND")
                boxBg:SetAllPoints()
                boxBg:SetColorTexture(0.064, 0.052, 0.041, 1)
                CUI.MakeRoundedBorder(boxFrame, 1, 1, 1, 0.12, boxBg)
                local check = boxFrame:CreateTexture(nil, "OVERLAY")
                check:SetSize(10, 10)
                check:SetPoint("CENTER")
                check:SetColorTexture(brandGreen.r, brandGreen.g, brandGreen.b, 1)
                CUI.RoundBody(boxFrame, check, 2)
                check:Hide()
                line._cbCheck = check
                local label = TRRowLabel(line, fontPath, ZoneName(z.name))
                label:SetPoint("LEFT", boxFrame, "RIGHT", 8, 0)
                label:SetPoint("RIGHT", line, "RIGHT", -8, 0)
                check:SetShown(pickedZones[i] == true)
                line:SetScript("OnClick", function()
                    pickedZones[i] = not pickedZones[i]
                    check:SetShown(pickedZones[i] == true)
                    zoneLabel:SetText(PickedZonesText())
                end)
                rows[i] = line
                line._zoneName = z.name
            end
            child:SetHeight(math.max(1, #zones * ITEM_H))
            searchBox:SetScript("OnTextChanged", function(self)
                local query = strlower(strtrim(self:GetText()))
                placeholder:SetShown(query == "")
                TRFilter(rows, child, ITEM_H, query, "_zoneName")
                scrollTo(0)
            end)
            dialog:SetScript("OnShow", function()
                dialog:ClearAllPoints()
                dialog:SetPoint("TOPLEFT", zoneBtn, "BOTTOMLEFT", 0, -2)
                searchBox:SetText("")
                searchBox:SetFocus()
                scrollTo(0)
                for i, line in ipairs(rows) do
                    line._cbCheck:SetShown(pickedZones[i] == true)
                end
            end)
            -- Closes with its page (rebuild, tab switch, panel close), as the talent list does.
            zoneBtn:SetScript("OnHide", function() dialog:Hide() end)
        end
        TRDropdownHover(zoneBtn)
        y = y - (ZONE_H + 30)

        -- The talent picker: a labelled dropdown, centred, with a searchable list.
        local talents = GetAllTalents()
        local LABEL_H, GAP_Y, TALENT_H = 16, 6, 30
        local TALENT_ROW_H = LABEL_H + GAP_Y + TALENT_H + 12
        local talentRow = CreateFrame("Frame", nil, parent)
        local talentRowW = parent:GetWidth() - TR_PAD * 2
        PP.Size(talentRow, talentRowW, TALENT_ROW_H)
        PP.Point(talentRow, "TOPLEFT", parent, "TOPLEFT", TR_PAD, y)
        local talentX = (talentRowW - DD_W) / 2
        local caption = talentRow:CreateFontString(nil, "OVERLAY")
        caption:SetFont(fontPath, 11, GetABROptOutline())
        caption:SetTextColor(
            CUI.TEXT_SECTION_R or 0.45,
            CUI.TEXT_SECTION_G or 0.50,
            CUI.TEXT_SECTION_B or 0.55,
            CUI.TEXT_SECTION_A or 1
        )
        PP.Point(caption, "TOP", talentRow, "TOPLEFT", talentX + DD_W / 2, 0)
        caption:SetText(CUI.L("Select Talent"))
        local talentBtn, talentLabel = TRDropdownButton(
            talentRow,
            DD_W,
            TALENT_H,
            "Select a talent...",
            fontPath,
            12,
            function(button) PP.Point(button, "TOPLEFT", talentRow, "TOPLEFT", talentX, -(LABEL_H + GAP_Y)) end
        )
        TRDropdownHover(talentBtn)
        if not CUI._prebuilding then
            local ITEM_H = 26
            local dialog, child, searchBox, placeholder, scrollTo = TRSearchPopup(
                "talent:Select Talent",
                talentBtn,
                DD_W,
                math.min(#talents * ITEM_H + 8, 250),
                fontPath
            )
            local rows = {}
            for i, t in ipairs(talents) do
                local line = TRPopupRow(child, i, ITEM_H)
                local label = TRRowLabel(line, fontPath, t.name)
                label:SetPoint("LEFT", line, "LEFT", 10, 0)
                label:SetPoint("RIGHT", line, "RIGHT", -8, 0)
                line._lbl, line._talentName, line._spellID = label, t.name, t.spellID
                line:SetScript("OnClick", function()
                    pickedSpellID, pickedName = t.spellID, t.name
                    talentLabel:SetText(t.name)
                    talentLabel:SetTextColor(1, 1, 1, 0.9)
                    dialog:Hide()
                end)
                rows[i] = line
            end
            child:SetHeight(math.max(1, #talents * ITEM_H))
            searchBox:SetScript("OnTextChanged", function(self)
                local query = strlower(strtrim(self:GetText()))
                placeholder:SetShown(query == "")
                TRFilter(rows, child, ITEM_H, query, "_talentName")
                scrollTo(0)
            end)
            -- The talent icons are made on the first open, so the page build
            -- pays nothing for them.
            local iconsMade = false
            dialog:SetScript("OnShow", function()
                dialog:ClearAllPoints()
                dialog:SetPoint("TOPLEFT", talentBtn, "BOTTOMLEFT", 0, -2)
                if not iconsMade then
                    iconsMade = true
                    for _, line in ipairs(rows) do
                        local icon = line:CreateTexture(nil, "ARTWORK", nil, 1)
                        icon:SetSize(18, 18)
                        icon:SetPoint("LEFT", line, "LEFT", 10, 0)
                        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                        icon:SetTexture(C_Spell.GetSpellTexture(line._spellID) or 134400)
                        line._lbl:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                    end
                end
                searchBox:SetText("")
                searchBox:SetFocus()
                scrollTo(0)
            end)
            talentBtn:HookScript("OnHide", function() dialog:Hide() end)
        end
        y = y - TALENT_ROW_H

        _, h = W:Spacer(parent, y, 10)
        y = y - h
        local addHost = CreateFrame("Frame", nil, parent)
        PP.Size(addHost, parent:GetWidth() or 400, 36)
        PP.Point(addHost, "TOPLEFT", parent, "TOPLEFT", 0, y)
        local addBtn = GreenButton(addHost, 160, 36, "Add Reminder", fontPath)
        addBtn:SetPoint("CENTER", addHost, "CENTER", 0, 0)
        y = y - 36

        -- The saved reminders (rebuilt on add and remove).
        local entryList = CreateFrame("Frame", nil, parent)
        entryList:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        entryList:SetSize(parent:GetWidth() or 400, 1)
        local listRows = {}
        -- The zone dropdowns' labels, in the picker's order.
        local zoneLabels = {}
        for i = 1, #zones do
            zoneLabels[i] = ZoneName(zones[i].name)
        end

        local RebuildList
        -- One reminder's row: the talent's icon and name | its zones (Delete
        -- Reminder pinned on top; its last zone stays ticked), then "Show
        -- 'Not Needed' Reminder" | where that shows.
        local function ReminderRow(index, idx, reminder, yOff)
            local line = TRListRow(entryList, yOff, index)
            local function Saved()
                local profile = DB()
                return profile and profile.talentReminders and profile.talentReminders[idx]
            end
            local icon = line:CreateTexture(nil, "ARTWORK")
            icon:SetSize(22, 22)
            icon:SetPoint("LEFT", line, "LEFT", TR_SIDE_PAD, 0)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            icon:SetTexture(Tex(reminder.spellID))
            local name = line:CreateFontString(nil, "OVERLAY")
            name:SetFont(fontPath, 14, GetABROptOutline())
            name:SetTextColor(1, 1, 1, 1)
            name:SetJustifyH("LEFT")
            name:SetWordWrap(false)
            name:SetMaxLines(1)
            name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            name:SetText(reminder.spellName or CUI.L("Unknown"))

            local function ZoneCount(r)
                local count = 0
                for i = 1, #zones do
                    if ReminderHasZone(r, zones[i].name) then count = count + 1 end
                end
                return count
            end
            local items = {
                {
                    isTopAction = true,
                    label = "Delete Reminder",
                    onClick = function()
                        local profile = DB()
                        if profile and profile.talentReminders and profile.talentReminders[idx] then
                            table.remove(profile.talentReminders, idx)
                            RebuildList()
                            TalentRemindersChanged()
                        end
                    end,
                },
            }
            for i = 1, #zones do
                local zoneName = zones[i].name
                items[#items + 1] = {
                    key = zoneName,
                    label = zoneLabels[i],
                    lockedFn = function()
                        local r = Saved()
                        return (r and ReminderHasZone(r, zoneName) and ZoneCount(r) <= 1) and true or false
                    end,
                    lockedTooltip = "A reminder needs at least one zone.",
                }
            end
            local zoneDD = CUI.BuildVisOptsCBDropdown(
                line,
                TR_ROW_DD_W,
                line:GetFrameLevel() + 3,
                items,
                function(zoneName)
                    local r = Saved()
                    return r and ReminderHasZone(r, zoneName) or false
                end,
                function(zoneName, on)
                    local r = Saved()
                    if not r then return end
                    local zl = EditableZoneList(r)
                    if on then
                        if not ReminderHasZone(r, zoneName) then
                            zl[#zl + 1] = zoneName
                            table.sort(zl)
                        end
                    else
                        for i = #zl, 1, -1 do
                            if zl[i] == zoneName then table.remove(zl, i) end
                        end
                    end
                    TalentRemindersChanged()
                end,
                nil,
                10,
                true,
                false,
                nil,
                { noAllLabel = true, dimLocked = true }
            )
            PP.Point(zoneDD, "RIGHT", line, "CENTER", -TR_SIDE_PAD, 0)
            name:SetPoint("RIGHT", zoneDD, "LEFT", -12, 0)

            local caption2 = line:CreateFontString(nil, "OVERLAY")
            caption2:SetFont(fontPath, 14, GetABROptOutline())
            caption2:SetJustifyH("LEFT")
            caption2:SetWordWrap(false)
            caption2:SetMaxLines(1)
            caption2:SetPoint("LEFT", line, "CENTER", TR_SIDE_PAD, 0)
            caption2:SetText(CUI.L("Show 'Not Needed' Reminder"))
            -- The runtime's own read of the choice: a reminder saved with the
            -- old checkbox reads on = Current Season Instances, off = Never.
            local function Mode()
                local r, read = Saved(), _G._CUABR_TR_NotNeededMode
                return (r and read) and read(r) or "never"
            end
            -- The label dims while the reminder is off, as it did under the checkbox.
            local function Paint() caption2:SetTextColor(1, 1, 1, (Mode() == "never") and 0.4 or 1) end
            Paint()
            local modeDD = CUI.BuildDropdownControl(
                line,
                TR_ROW_DD_W,
                line:GetFrameLevel() + 3,
                NOT_NEEDED_VALUES,
                NOT_NEEDED_ORDER,
                Mode,
                function(value)
                    local r = Saved()
                    if not r then return end
                    r.notNeededMode = value
                    -- The old checkbox key follows, for a profile an older version reads.
                    r.showNotNeeded = (value ~= "never")
                    Paint()
                    TalentRemindersChanged()
                end
            )
            PP.Point(modeDD, "RIGHT", line, "RIGHT", -TR_SIDE_PAD, 0)
            modeDD._ttText = "Reminds you to remove this talent in instances you did not pick for it."
            caption2:SetPoint("RIGHT", modeDD, "LEFT", -12, 0)
            return line
        end

        -- The list, or the empty notice; returns its height. The global
        -- search's pre-build makes no rows: they hold nothing to index.
        RebuildList = function()
            if CUI._prebuilding then return 0 end
            -- On a page pool host the rows go back to the container's pool
            -- and are dressed again below, in order.
            Pool.Begin(entryList)
            for _, line in ipairs(listRows) do
                line:Hide()
            end
            wipe(listRows)
            local profile = DB()
            if not profile then return 0 end
            local reminders = profile.talentReminders or {}
            local visible = VisibleReminders(reminders)
            if #visible == 0 then
                local line = TRListRow(entryList, 0, 1)
                local text = line:CreateFontString(nil, "OVERLAY")
                text:SetFont(fontPath, 13, GetABROptOutline())
                text:SetTextColor(0.5, 0.5, 0.5, 1)
                text:SetPoint("CENTER")
                text:SetText(CUI.L("No talent reminders configured"))
                line:Show()
                listRows[1] = line
                entryList:SetHeight(TR_ROW_H)
                return TR_ROW_H
            end
            local height = 0
            for n, idx in ipairs(visible) do
                listRows[#listRows + 1] = ReminderRow(n, idx, reminders[idx], -height)
                height = height + TR_ROW_H
            end
            entryList:SetHeight(height)
            return height
        end

        -- After a save: the form back to empty and the list rebuilt.
        local function ResetForm()
            wipe(pickedZones)
            pickedSpellID, pickedName = nil, nil
            zoneLabel:SetText(CUI.L("Select Dungeon/Raid/PvP Zone"))
            talentLabel:SetText(CUI.L("Select a talent..."))
            talentLabel:SetTextColor(1, 1, 1, 0.50)
            RebuildList()
            TalentRemindersChanged()
        end
        -- Add Reminder: needs a zone and a talent (a missing one pulses red);
        -- a reminder for the same talent gains the new zones instead.
        addBtn:SetScript("OnClick", function()
            local nameList = {}
            for idx, on in pairs(pickedZones) do
                if on and zones[idx] then nameList[#nameList + 1] = zones[idx].name end
            end
            local anyPicked = false
            for _, on in pairs(pickedZones) do
                anyPicked = anyPicked or on == true
            end
            if not anyPicked then
                PulseRedBorder(zoneBtn)
                return
            end
            if not pickedSpellID or pickedSpellID == 0 then
                PulseRedBorder(talentBtn)
                return
            end
            local profile = DB()
            if not profile then return end
            profile.talentReminders = profile.talentReminders or {}
            table.sort(nameList)
            for _, r in ipairs(profile.talentReminders) do
                if r.spellID == pickedSpellID then
                    local zl = EditableZoneList(r)
                    for _, zoneName in ipairs(nameList) do
                        if not ReminderHasZone(r, zoneName) then zl[#zl + 1] = zoneName end
                    end
                    table.sort(zl)
                    ResetForm()
                    return
                end
            end
            local _, class = UnitClass("player")
            profile.talentReminders[#profile.talentReminders + 1] = {
                zoneNames = nameList,
                spellID = pickedSpellID,
                spellName = pickedName,
                notNeededMode = "never",
                showNotNeeded = false,
                class = class,
            }
            ResetForm()
        end)

        _, h = W:Spacer(parent, y, 15)
        y = y - h
        _, h = W:SectionHeader(parent, "ACTIVE REMINDERS", y)
        y = y - h
        entryList:ClearAllPoints()
        entryList:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        y = y - RebuildList()
        _, h = W:Spacer(parent, y, 20)
        return math.abs(y - h)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    -- The Reminders page shown again from the cache (retail: it has the
    -- preview): the icons refreshed, the hint only shown or hidden (never
    -- made here), and the header sized for it.
    local function RestoreRemindersPage()
        SyncPreviewHeader()
        local dismissed = IsPreviewHintDismissed()
        if _previewHintFS then
            if dismissed then
                _previewHintFS:Hide()
            else
                _previewHintFS:SetAlpha(0.45)
                _previewHintFS:Show()
            end
        end
        if _eabrHeaderBaseH > 0 then
            CUI:SetContentHeaderHeightSilent(_eabrHeaderBaseH + (dismissed and 0 or 35))
        end
    end

    local PAGE_BUILDERS = { [PAGE_REMINDERS] = BuildRemindersPage, [PAGE_TALENTS] = BuildTalentRemindersPage }
    -- A module hook that calls a reminder global when the module has set it.
    local function Call(name)
        return function()
            local fn = _G[name]
            if fn then fn() end
        end
    end

    CUI:RegisterModule("CludesUIAuraBuffReminders", {
        title = "Auras, Buffs & Consumables",
        description = "Buff Checks: raid buffs, auras and consumables.",
        pages = FOREVER and { PAGE_REMINDERS } or { PAGE_REMINDERS, PAGE_TALENTS },
        buildPage = function(pageName, parent, yOffset)
            local build = PAGE_BUILDERS[pageName]
            if build then return build(pageName, parent, yOffset) end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_REMINDERS and not FOREVER then return _previewHeaderBuilder end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_REMINDERS and not FOREVER then RestoreRemindersPage() end
        end,
        onShow = Call("_CUABR_HideAllIcons"),
        onHide = Call("_CUABR_RequestRefresh"),
        onReset = function()
            if _G._CUABR_AceDB then _G._CUABR_AceDB:ResetProfile() end
            Call("_CUABR_RequestRefresh")()
        end,
        -- Tears down the Ready Check Mana Warning preview on module switch.
        onModuleLeave = Call("_CUABR_RCWarnHidePreview"),
    })

    -- The unlock elements register a moment later.
    C_Timer.After(0.5, Call("_CUABR_RegisterUnlock"))

    ---------------------------------------------------------------------------
    --  Slash commands
    ---------------------------------------------------------------------------
    SLASH_EABR1 = "/cabr"
    SLASH_EABR2 = "/cbr"
    SlashCmdList.EABR = function()
        if InCombatLockdown and InCombatLockdown() then return end
        CUI:ShowModule("CludesUIAuraBuffReminders")
    end
end)
