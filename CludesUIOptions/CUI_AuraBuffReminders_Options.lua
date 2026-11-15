if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_AuraBuffReminders_Options.lua
--  Registers the AuraBuff Reminders module with CludesUI
--  Two pages: Auras, Buffs & Consumables | Talent Reminders | Unlock Mode
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUIAuraBuffReminders"
local ns = CludesUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not ns then
    return
end -- module disabled: no options page

local PAGE_REMINDERS = "Auras, Buffs & Consumables"
local PAGE_TALENTS = "Talent Reminders"
local PAGE_UNLOCK = "Layout Mode"

-- WoW Forever: the page keeps CORE, DISPLAY and RAID BUFFS (that client's
-- locations and its own buffs) and swaps every other retail section for the one
-- Forever section (Camp Benefits + custom spell IDs); the Talent Reminders
-- page does not exist there.
local FOREVER = CludesUI.IS_FOREVER == true
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

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not CludesUI or not CludesUI.RegisterModule then
        return
    end
    local PP = CludesUI.PanelPP
    -- Page reuse (CludesUI_FramePool.lua): a frame made under a page pool
    -- host comes from the pool and is dressed again by every later build; under
    -- any other parent it is a plain new frame.
    local Pool = CludesUI._Pool
    local CreateFrame = Pool.CreateFrame

    local function GetABROptOutline()
        return CludesUI.GetFontOutlineFlag("auraBuff")
    end

    ---------------------------------------------------------------------------
    --  DB helpers
    ---------------------------------------------------------------------------
    local db
    C_Timer.After(0, function()
        db = _G._CUABR_AceDB
    end)

    local function DB()
        if not db then
            db = _G._CUABR_AceDB
        end
        return db and db.profile
    end
    -- One profile table's accessor (nil until the profile loads).
    local function Section(key)
        return function()
            local p = DB()
            return p and p[key]
        end
    end
    local DDB = Section("display")
    local RDB = Section("raidBuffs")
    local ADB = Section("auras")
    local CDB = Section("consumables")
    local FDB = Section("forever") -- the WoW Forever section (nil on retail)

    -- The reminder name font: the display's own pick, else the module font.
    local function GetNameFontPath()
        local d = DDB()
        local pick = d and d.nameFont
        if pick and pick ~= "__global" and CludesUI.ResolveFontName then
            local path = CludesUI.ResolveFontName(pick)
            if path and path ~= "" then
                return path
            end
        end
        return CludesUI.GetFontPath("auraBuff") or "Fonts\\ARIALN.TTF"
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
    local function RefreshAll()
        if _G._CUABR_RequestRefresh then
            _G._CUABR_RequestRefresh()
        end
    end

    ---------------------------------------------------------------------------
    --  Preview Header shows potential buff/aura icons for current class/spec
    ---------------------------------------------------------------------------
    local _previewHeaderBuilder
    local _previewIcons = {}
    local _previewContainer
    local _previewHintFS

    local function IsPreviewHintDismissed()
        return CludesUIDB and CludesUIDB.previewHintDismissed
    end

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
        if word then
            return CludesUI.L(word)
        end
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
        return function()
            return C_Item.GetItemIconByID(id) or fallback
        end
    end
    local GENERAL_CONSUMABLES = {
        {
            key = "flask",
            label = "Flask",
            icon = function()
                return 134830
            end,
        },
        {
            key = "food",
            label = "Food",
            icon = function()
                return 134062
            end,
        },
        { key = "augment_rune", label = "Rune", icon = ItemIcon(259085, 134400) },
        { key = "healthstone", label = "Stone", icon = ItemIcon(5512, 134400), onWhenUnset = true },
        { key = "inky_black", label = "Inky", icon = ItemIcon(124640, 136122) },
    }

    local function ForSpec(specs, specID)
        if not specs then
            return true
        end
        for _, s in ipairs(specs) do
            if s == specID then
                return true
            end
        end
        return false
    end

    -- Every icon the preview can show for the player's class and spec, in
    -- order: enabled raid buffs, enabled auras (one Beacon), the class
    -- consumable (else a weapon oil), then the general consumables. None
    -- on WoW Forever (no preview, and the spec lookups are retail-only).
    local function CollectPreviewIcons()
        local icons = {}
        if FOREVER then
            return icons
        end
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
                if not (isBeacon and beacon) then
                    AddSpell(aura, "aura")
                end
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
                Add(oils[1].icon or 134400, CludesUI.L("Weapon"), "consumable", "weapon_enchant")
            end
        end

        for _, item in ipairs(GENERAL_CONSUMABLES) do
            local v = on and on[item.key]
            if v or (item.onWhenUnset and on and v == nil) then
                Add(item.icon(), CludesUI.L(item.label), "consumable", item.key)
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
        local edgeX = boxW / 2 - CludesUI.CONTENT_PAD
        if growDir == "RIGHT" then
            return -edgeX + (sz / 2)
        end
        local totalW = (count * sz) + ((count - 1) * spacing)
        if growDir == "LEFT" then
            return edgeX - totalW + (sz / 2)
        end
        return -(totalW / 2) + (sz / 2)
    end

    -- Places the first limit preview icons (default all) along the row,
    -- skipping a slot with no frame.
    local function PlaceIcons(d, sz, spacing, limit)
        local x = PreviewStartX(d, #_previewIcons, sz, spacing, _previewContainer:GetWidth())
        for i = 1, limit or #_previewIcons do
            local btn = _previewIcons[i].frame
            if btn then
                btn:ClearAllPoints()
                btn:SetPoint("TOP", btn:GetParent(), "TOP", x + (i - 1) * (sz + spacing), 0)
            end
        end
    end

    local _eabrHeaderBaseH = 0
    local PREVIEW_H = 80

    -- One preview icon dressed as live: size, opacity, border, glow (the
    -- live renderer's own spec, nil = off) and its text.
    local function StyleIcon(btn, d, sz, iconH, glowSpec)
        btn:SetSize(sz, iconH)
        btn:SetAlpha(d.opacity or 1.0)
        if _G._CUABR_ApplyIconBorder then
            _G._CUABR_ApplyIconBorder(btn, false)
        end
        if not btn._glowWrapper then
            local wrap = CreateFrame("Frame", nil, btn)
            wrap:SetAllPoints(btn)
            wrap:SetFrameLevel(btn:GetFrameLevel() + 4)
            btn._glowWrapper = wrap
        end
        local wrap = btn._glowWrapper
        if glowSpec then
            local extra = btn._eabrShape and ns.IconGlowExtra(btn, true) or CludesUI.Glows.PANEL_EXTRA
            CludesUI.Glows.StartSpecGlow(wrap, glowSpec, sz, iconH, "icon", extra)
            wrap:Show()
        else
            CludesUI.Glows.StopAllGlows(wrap)
            wrap:Hide()
        end
        local text = btn._text
        if d.showText then
            local tc = d.textColor or { r = 1, g = 1, b = 1 }
            CludesUI.ApplyModuleFont(text, GetNameFontPath(), d.textSize or 11, "auraBuff")
            text:ClearAllPoints()
            local own, onIcon = GetPreviewTextAnchor(d)
            text:SetPoint(own, btn, onIcon, d.textXOffset or 0, d.textYOffset or -2)
            text:SetTextColor(tc.r, tc.g, tc.b, 1)
            text:Show()
        else
            text:Hide()
        end
        btn:Show()
    end

    local function UpdatePreviewHeader()
        if not _previewIcons or #_previewIcons == 0 then
            return
        end
        local d = DDB()
        if not d then
            return
        end
        local sz, iconH, spacing = IconMetrics(d)
        local glowSpec = _G._CUABR_GlowSpec and _G._CUABR_GlowSpec(d, {})
        -- Up to the first slot with no frame.
        local placed = 0
        while _previewIcons[placed + 1] and _previewIcons[placed + 1].frame do
            placed = placed + 1
        end
        PlaceIcons(d, sz, spacing, placed)
        for i = 1, placed do
            StyleIcon(_previewIcons[i].frame, d, sz, iconH, glowSpec)
        end

        -- The row is centred in the header, as tall as the icons plus any
        -- text hanging below them; the header itself stays 80 (plus the hint).
        local overhang = d.showText and (math.abs(d.textYOffset or -2) + (d.textSize or 11)) or 0
        if _previewContainer then
            _previewContainer:SetHeight(iconH + overhang)
            _previewContainer:ClearAllPoints()
            _previewContainer:SetPoint("CENTER", _previewContainer:GetParent(), "CENTER", 0, 0)
        end
        _eabrHeaderBaseH = PREVIEW_H
        local hintH = (_previewHintFS and _previewHintFS:IsShown()) and 35 or 0
        -- Silent: resizing the header never triggers scroll compensation
        -- (the height rarely changes here).
        CludesUI:SetContentHeaderHeightSilent(PREVIEW_H + hintH)
    end

    local function RefreshBorders()
        if _G._CUABR_ApplyAllIconBorders then
            _G._CUABR_ApplyAllIconBorders()
        end
        RefreshAll()
        UpdatePreviewHeader()
    end

    ---------------------------------------------------------------------------
    --  Preview click-to-scroll infrastructure
    ---------------------------------------------------------------------------

    -- Rebuilds the preview header (SetContentHeader tears it down and builds
    -- it again). No preview header on WoW Forever.
    local function RebuildPreviewHeader()
        if FOREVER then
            return
        end
        CludesUI:SetContentHeader(_previewHeaderBuilder)
    end

    -- Moves the existing preview icons into place without rebuilding the
    -- header (no scroll jump).
    local function RelayoutPreviewIcons()
        if not _previewIcons or #_previewIcons == 0 then
            return
        end
        local d = DDB()
        local sz, _, spacing = IconMetrics(d)
        PlaceIcons(d, sz, spacing)
    end

    local _eabrGlow -- made on first click: Widgets helpers load with the panel
    local _eabrClickMappings = {}
    local _eabrHitOverlays = {}

    local function EABRPlaySettingGlow(targetFrame)
        _eabrGlow = _eabrGlow or CludesUI.MakeSettingGlow({ color = CludesUI.CLUDES_GREEN })
        _eabrGlow(targetFrame)
    end

    local function EABRNavigateToSetting(key)
        local m = _eabrClickMappings[key]
        if not m or not m.section or not m.target then
            return
        end

        CludesUI.DismissPreviewHint(_previewHintFS, _eabrHeaderBaseH, 35, 5)

        local sf = CludesUI._scrollFrame
        if not sf then
            return
        end

        -- The glow plays a moment later: a target of the page pool that is
        -- dressed again for another row by then belongs to a newer build.
        local target = m.target
        local gen = Pool.Gen(target)
        local function PlayLater()
            if Pool.Gen(target) ~= gen or Pool.IsIdle(target) then
                return
            end
            EABRPlaySettingGlow(target)
        end

        local child = sf.GetScrollChild and sf:GetScrollChild()
        if child and target.GetTop and child.GetTop then
            local targetTop = target:GetTop()
            local childTop = child:GetTop()
            if targetTop and childTop then
                local scrollPos = math.max(0, childTop - targetTop - 40)
                CludesUI.SmoothScrollTo(scrollPos)
                C_Timer.After(0.15, PlayLater)
                return
            end
        end

        -- Fallback for layouts where the scroll child isn't ready yet.
        local _, _, _, _, headerY = m.section:GetPoint(1)
        if headerY then
            local scrollPos = math.max(0, math.abs(headerY) - 40)
            CludesUI.SmoothScrollTo(scrollPos)
        end
        C_Timer.After(0.15, PlayLater)
    end

    local function EABRCreateHitOverlay(element, mappingKey, frameLevelOverride)
        local btn = CludesUI.CreatePreviewHitOverlay(
            element,
            EABRNavigateToSetting,
            mappingKey,
            false,
            frameLevelOverride
        )
        _eabrHitOverlays[#_eabrHitOverlays + 1] = btn
        return btn
    end

    -- One preview icon: the spell texture, the live border (the reminder
    -- icons' own helper, so the header matches them exactly) and its text
    -- on an overlay above the icon.
    local function MakePreviewIcon(container, data, d, sz, iconH, x)
        local btn = CreateFrame("Button", nil, container)
        btn:SetSize(sz, iconH)
        btn:EnableMouse(true)
        btn:SetPoint("TOP", container, "TOP", x, 0)
        btn:SetAlpha((d and d.opacity) or 1.0)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:SetTexture(data.texture or 134400)
        if icon.SetSnapToPixelGrid then
            icon:SetSnapToPixelGrid(false)
            icon:SetTexelSnappingBias(0)
        end
        btn._icon = icon
        _G._CUABR_ApplyIconBorder(btn, false)

        local layer = CreateFrame("Frame", nil, btn)
        layer:SetAllPoints()
        layer:SetFrameLevel(btn:GetFrameLevel() + 5)
        local text = layer:CreateFontString(nil, "OVERLAY")
        local own, onIcon = GetPreviewTextAnchor(d)
        text:SetPoint(own, btn, onIcon, (d and d.textXOffset) or 0, (d and d.textYOffset) or -2)
        CludesUI.ApplyModuleFont(text, GetNameFontPath(), (d and d.textSize) or 11, "auraBuff")
        local tc = (d and d.textColor) or { r = 1, g = 1, b = 1 }
        text:SetTextColor(tc.r, tc.g, tc.b, 1)
        text:SetText(data.label or "")
        if not (d and d.showText) then
            text:Hide()
        end
        btn._text = text
        return btn
    end

    -- The hint under the icons, kept across builds (out of the container's
    -- pool). Returns the height it adds.
    local function PlacePreviewHint(hdr, container)
        if _previewHintFS and not _previewHintFS:GetParent() then
            _previewHintFS = nil
        end
        if IsPreviewHintDismissed() then
            if _previewHintFS then
                _previewHintFS:Hide()
            end
            return 0
        end
        if not _previewHintFS then
            _previewHintFS = Pool.Keep(CludesUI.MakeFont(container, 11, nil, 1, 1, 1))
            _previewHintFS:SetAlpha(0.45)
            _previewHintFS:SetText(CludesUI.L("Click elements to scroll to and highlight their options"))
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
        local d = DDB()

        -- The levels the first build gave the container and its icons (a
        -- kept header root's own dress can raise what it holds).
        if _previewContainer and #_previewIcons == #icons then
            local box = _previewContainer
            box:SetParent(hdr) -- may have been orphaned by ClearContentHeader
            box:SetFrameLevel(hdr:GetFrameLevel() + 1)
            box:ClearAllPoints()
            box:SetPoint("CENTER", hdr, "CENTER", 0, 0)
            box:SetSize(hdrW, box:GetHeight())
            box:Show()
            for i, entry in ipairs(_previewIcons) do
                local btn, data = entry.frame, icons[i]
                if btn then
                    btn:SetFrameLevel(box:GetFrameLevel() + 1)
                    if data then
                        if btn._icon then
                            btn._icon:SetTexture(data.texture or 134400)
                        end
                        if btn._text then
                            btn._text:SetText(data.label or "")
                        end
                        entry.data = data
                    end
                end
            end
            UpdatePreviewHeader()
            -- The full build's height (never nil, which would collapse the header).
            return PREVIEW_H + ((not IsPreviewHintDismissed()) and 35 or 0)
        end

        local sz, iconH, spacing = IconMetrics(d)
        local showText = d and d.showText
        local overhang = showText and (math.abs((d and d.textYOffset) or -2) + ((d and d.textSize) or 11))
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
            if entry.frame then
                entry.frame:Hide()
            end
        end
        wipe(_previewIcons)
        local x = PreviewStartX(d, #icons, sz, spacing, hdrW)
        for i, data in ipairs(icons) do
            local btn = MakePreviewIcon(container, data, d, sz, iconH, x + (i - 1) * (sz + spacing))
            _previewIcons[i] = { frame = btn, data = data }
        end
        UpdatePreviewHeader() -- glows

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
            if showText then
                EABRCreateHitOverlay(entry.frame._text, "showText", level)
            end
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
        return function(k)
            local t = store()
            return not (t and t[k] == false)
        end
    end
    local function WhereSet(store, onChange)
        return function(k, v)
            local t = store(true)
            if not t then
                return
            end
            t[k] = v and true or false
            if onChange then
                onChange()
            end
        end
    end
    local function WhenGet(store)
        return function(k)
            local t = store()
            return t and t[k] == true
        end
    end
    local function WhenSet(store, onChange)
        return function(k, v)
            local t = store()
            if not t then
                return
            end
            t[k] = v and true or false
            if onChange then
                onChange()
            end
        end
    end

    -- A section's own sub-table accessor (the table is made on first use).
    local function SubTable(section, field)
        return function()
            local t = section()
            if not t then
                return nil
            end
            t[field] = t[field] or {}
            return t[field]
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
            if not (c and S) then
                return nil
            end
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
        local names = CludesUI._groupDeathSoundNames or { none = "None" }
        local order = CludesUI._groupDeathSoundOrder or { "none" }
        return names, order
    end
    local SOUND_TIP = "Play a sound once when a reminder in this section newly appears."
    -- Plays a picked sound once, so the choice is heard.
    local function PreviewSound(key)
        local paths = CludesUI._groupDeathSoundPaths
        local path = paths and paths[key]
        if path then
            PlaySoundFile(path, "Master")
        end
    end

    -- Inline cog holding a single "Sound" dropdown bound to getSec()[field]
    -- ("none"/nil = silent), plus any extraRows. One reminder sound applies
    -- to the whole section.
    local function AddSectionSoundCog(rgn, getSec, field, extraRows, title)
        local names, order = SoundNamesOrder()
        local rows = {
            {
                type = "dropdown",
                label = "Sound",
                tooltip = SOUND_TIP,
                values = names,
                order = order,
                get = function()
                    local t = getSec()
                    return (t and t[field]) or "none"
                end,
                set = function(v)
                    local t = getSec()
                    if not t then
                        return
                    end
                    t[field] = v ~= "none" and v or nil
                    PreviewSound(v)
                end,
            },
        }
        for _, extra in ipairs(extraRows or {}) do
            rows[#rows + 1] = extra
        end
        return CludesUI.BuildInlineCog(
            rgn,
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
            getValue = function()
                return "_placeholder"
            end,
            setValue = function() end,
        }
    end

    -- The full "Reminder Sound" dropdown for a section's right slot. A
    -- class-special section looks its field up per call (the map is
    -- exported in ABR's OnEnable, see EABR.SPECIALS) and stores "none"
    -- rather than clearing it (see EABR.SpecialsSound).
    local function SoundDropdownCfg(cfg)
        local names, order = SoundNamesOrder()
        local sec, special = cfg.soundSec, cfg.specialClass
        local own = cfg.soundField or "sectionSound"
        local function Field()
            if not special then
                return own
            end
            local S = _G._CUABR_SPECIALS
            return S and S[special].sound
        end
        return {
            type = "dropdown",
            text = "Reminder Sound",
            dropdownWidth = 220,
            tooltip = SOUND_TIP,
            values = names,
            order = order,
            getValue = function()
                local t = sec()
                local f = t and Field()
                if not f then
                    return "none"
                end
                if special and _G._CUABR_SpecialsSound then
                    return _G._CUABR_SpecialsSound(t, f) or "none"
                end
                return t[f] or "none"
            end,
            setValue = function(v)
                local t = sec()
                local f = t and Field()
                if not f then
                    return
                end
                if v == "none" and not special then
                    t[f] = nil
                else
                    t[f] = v
                end
                PreviewSound(v)
            end,
        }
    end

    -- Puts a checkbox dropdown in a DualRow region in place of its control.
    local function CheckList(rgn, items, get, set)
        if rgn._control then
            rgn._control:Hide()
        end
        local dd, refresh =
            CludesUI.BuildVisOptsCBDropdown(rgn, 220, rgn:GetFrameLevel() + 2, items, get, set)
        PP.Point(dd, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = dd
        rgn._lastInline = nil
        CludesUI.RegisterWidgetRefresh(refresh)
    end

    -- Per-section control dual-row: a "Where to Show" checkbox dropdown on
    -- the left. Right slot: for raid buffs the "Show When" checkbox
    -- dropdown (+ reminder-sound cog beside it); for a section with a sound
    -- a full "Reminder Sound" dropdown fills the slot instead of a cog; else
    -- the section's own cfg.rightCfg (the caller dresses row._rightRegion).
    local function SectionControlRow(parent, y, cfg)
        local rightCfg = cfg.rightCfg
        if cfg.showWhenStore then
            rightCfg = Placeholder("Show When", cfg.showWhenTooltip)
        elseif cfg.soundSec then
            rightCfg = SoundDropdownCfg(cfg)
        end
        local row, h = CludesUI.Widgets:DualRow(
            parent,
            y,
            Placeholder("Where to Show", cfg.whereTooltip),
            rightCfg or { type = "label", text = "" }
        )
        if CludesUI._prebuilding then
            return row, h
        end

        local where = cfg.whereStore
        CheckList(
            row._leftRegion,
            cfg.whereItems or WHERE_ITEMS,
            WhereGet(where),
            WhereSet(where, cfg.onChange)
        )
        if cfg.showWhenStore then
            local rrgn = row._rightRegion
            CheckList(
                rrgn,
                SHOWWHEN_ITEMS,
                WhenGet(cfg.showWhenStore),
                WhenSet(cfg.showWhenStore, function()
                    if cfg.onShowWhenChange then
                        cfg.onShowWhenChange()
                    end
                    if cfg.onChange then
                        cfg.onChange()
                    end
                end)
            )
            if cfg.soundSec then
                AddSectionSoundCog(
                    rrgn,
                    cfg.soundSec,
                    cfg.soundField or "sectionSound",
                    cfg.cogRows,
                    cfg.cogTitle
                )
            end
        end
        return row, h
    end

    -- "(min)" in smaller, dimmer text after each slider label of a dual row.
    local function AddMinSuffix(threshRow, leftLabel, rightLabel)
        if CludesUI._prebuilding then
            return
        end
        local function LabelOf(rgn, text)
            for _, reg in ipairs({ rgn:GetRegions() }) do
                -- (an idle pooled region still holds the text of an earlier dress)
                if reg.GetText and not Pool.IsIdle(reg) and CludesUI.EnKey(reg:GetText()) == text then
                    return reg
                end
            end
        end
        local sides = { { threshRow._leftRegion, leftLabel }, { threshRow._rightRegion, rightLabel } }
        for _, side in ipairs(sides) do
            local rgn, text = side[1], side[2]
            local suffix = rgn:CreateFontString(nil, "OVERLAY")
            suffix:SetFont(CludesUI.EXPRESSWAY, 11, "")
            suffix:SetTextColor(1, 1, 1, 0.35)
            local label = LabelOf(rgn, text)
            if label then
                suffix:SetPoint("LEFT", label, "RIGHT", 5, -1)
            end
            suffix:SetText(CludesUI.L("(min)"))
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
    local GRID_PAD = CludesUI.CONTENT_PAD or 16
    local GRID_SIDE_PAD = 20
    local BOX_BORDER = { 0.224, 0.215, 0.207, 0.6 }

    local function NoSnap(tex)
        if tex.SetSnapToPixelGrid then
            tex:SetSnapToPixelGrid(false)
            tex:SetTexelSnappingBias(0)
        end
        return tex
    end

    -- One cell: the label (in its class colour) on the left, the checkbox
    -- on the right, the whole cell clickable, and an optional cog just left
    -- of the box (no item sets cogRows yet; the hook is for per-item
    -- condition sets). Returns the cell.
    local function GridCell(rowFrame, item, x, w, refreshFn, accent)
        local cell = CreateFrame("Frame", nil, rowFrame)
        cell:SetSize(w, GRID_ROW_H)
        cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", x, 0)

        local cc = item.classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[item.classToken]
        local label = CludesUI.MakeFont(cell, 13, nil, cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1)
        label:SetPoint("LEFT", cell, "LEFT", GRID_SIDE_PAD, 0)
        label:SetText(item.label)

        local box = CreateFrame("Frame", nil, cell)
        box:SetSize(GRID_BOX_SZ, GRID_BOX_SZ)
        box:SetPoint("RIGHT", cell, "RIGHT", -GRID_SIDE_PAD, 0)
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints()
        boxBg:SetColorTexture(0.114, 0.106, 0.099, 1)
        NoSnap(boxBg)
        local border =
            CludesUI.MakeRoundedBorder(box, BOX_BORDER[1], BOX_BORDER[2], BOX_BORDER[3], BOX_BORDER[4], boxBg)
        local check = box:CreateTexture(nil, "ARTWORK")
        check:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
        check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
        check:SetColorTexture(accent.r, accent.g, accent.b, 1)
        CludesUI.RoundBody(box, check, 1)
        NoSnap(check)

        local click = CreateFrame("Button", nil, cell)
        click:SetAllPoints(cell)
        click:SetFrameLevel(cell:GetFrameLevel() + 2)

        local function Paint()
            local on = item.getVal() and true or false
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
            item.setVal(not item.getVal())
            Paint()
            if refreshFn then
                refreshFn()
            end
        end)
        click:SetScript("OnEnter", function()
            if not item.getVal() then
                label:SetAlpha(0.8)
            end
            if item.tooltip then
                CludesUI.ShowWidgetTooltip(cell, item.tooltip)
            end
        end)
        click:SetScript("OnLeave", function()
            if not item.getVal() then
                label:SetAlpha(0.5)
            end
            if item.tooltip then
                CludesUI.HideWidgetTooltip()
            end
        end)

        if item.cogRows then
            CludesUI.BuildInlineCog(cell, {
                title = item.cogTitle or "Reminder Conditions",
                rows = item.cogRows,
                minWidth = 220,
                anchorTo = box,
                chain = false,
                size = 16,
                gap = 10,
            })
        end
        CludesUI.RegisterWidgetRefresh(Paint)
        return cell
    end

    -- The grid, row by row: a full-width row frame (as a DualRow) with 1px
    -- column dividers, then its cells. cellRefTable[item.key] gets each
    -- keyed cell (preview click navigation). Returns the height.
    local function BuildCheckboxGrid(parent, y, items, refreshFn, cellRefTable)
        local rows = math.ceil(#items / GRID_COLS)
        local totalW = parent:GetWidth() - GRID_PAD * 2
        local colW = math.floor(totalW / GRID_COLS)
        local accent = CludesUI.CLUDES_GREEN or { r = 0, g = 0.82, b = 0.62 }
        for row = 0, rows - 1 do
            local rowFrame = CreateFrame("Frame", nil, parent)
            PP.Size(rowFrame, totalW, GRID_ROW_H)
            PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", GRID_PAD, y - row * GRID_ROW_H)
            rowFrame._skipRowDivider = true
            CludesUI.RowBg(rowFrame, parent)
            for col = 1, GRID_COLS - 1 do
                local div = NoSnap(rowFrame:CreateTexture(nil, "ARTWORK"))
                div:SetColorTexture(1, 1, 1, 0.06)
                div:SetWidth(1)
                PP.Point(div, "TOP", rowFrame, "TOPLEFT", col * colW, 0)
                PP.Point(div, "BOTTOM", rowFrame, "BOTTOMLEFT", col * colW, 0)
            end
            for col = 0, GRID_COLS - 1 do
                local item = items[row * GRID_COLS + col + 1]
                if not item then
                    break
                end
                local cell = GridCell(rowFrame, item, col * colW, colW, refreshFn, accent)
                if cellRefTable and item.key then
                    cellRefTable[item.key] = cell
                end
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
        RefreshAll()
        CludesUI:RefreshPage(true)
    end
    local function RebuildSoon()
        RefreshAll()
        C_Timer.After(0, function()
            CludesUI:RefreshPage(true)
        end)
    end

    -- A spell's row text: its name, then its ID dimmed.
    local function SpellText(id)
        return _G._CUABR_SpellName(id, tostring(id)) .. " " .. CludesUI.COLOR_CODES.DIM .. id .. "|r"
    end

    -- Adds the spell ID typed into an Add ... Spell input to list: digits only,
    -- a spell the client knows, no duplicates.
    local function AddSpellIDToList(list, text)
        local spellID = tonumber((text or ""):match("^%s*(%d+)%s*$"))
        if not (spellID and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)) then
            return
        end
        if tContains(list, spellID) then
            return
        end
        list[#list + 1] = spellID
        RebuildSoon()
    end

    -- Names a new spell group (set nil) or renames set.
    local function PromptSpellGroupName(set)
        CludesUI:ShowInputPopup({
            title = set and "Rename Spell Group" or "New Spell Group",
            message = "Enter a name for the group:",
            placeholder = "Group name",
            initialText = set and set.name or "",
            confirmText = set and "Rename" or "Create",
            onConfirm = function(text)
                local name = strtrim(text or "")
                local f = FDB()
                if name == "" or not f then
                    return
                end
                if set then
                    set.name = name
                else
                    f.customGroups[#f.customGroups + 1] = { name = name, ids = {} }
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
        for k = 1, #slots, 2 do
            local row, h =
                CludesUI.Widgets:DualRow(parent, y, slots[k], slots[k + 1] or CludesUI.BlankRowCfg())
            if dress then
                dress(row, k)
            end
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
        if set.castSpellID == spellID then
            set.castSpellID = nil
        end
        if set.castRanks then
            set.castRanks[spellID] = nil
            if not next(set.castRanks) then
                set.castRanks = nil
            end
        end
        Rebuild()
    end

    local function BuildForeverGroupSections(parent, y)
        local f = FDB()
        for groupIndex, set in ipairs(f.customGroups) do
            local slots = {
                {
                    type = "input",
                    text = "Add Spell ID",
                    inputStyle = "popup",
                    placeholder = "Spell ID",
                    inputWidth = 110,
                    tooltip = GROUP_ADD_TIP,
                    getValue = function()
                        return ""
                    end,
                    setValue = function(text)
                        AddSpellIDToList(set.ids, text)
                    end,
                },
                ButtonSlot("Rename Group", "Rename", "Change this group's name.", function()
                    PromptSpellGroupName(set)
                end),
            }
            for spellIndex, spellID in ipairs(set.ids) do
                slots[#slots + 1] = ButtonSlot(
                    SpellText(spellID),
                    "Remove",
                    "Remove this spell from the group.",
                    function()
                        RemoveGroupSpell(set, spellIndex, spellID)
                    end
                )
            end
            slots[#slots + 1] = ButtonSlot(
                "Remove Group",
                "Remove",
                "Deletes this group and its spells.",
                function()
                    table.remove(f.customGroups, groupIndex)
                    Rebuild()
                end
            )
            local _, headerH =
                CludesUI.Widgets:SectionHeader(parent, CludesUI.Lf("SPELL GROUP: %1$s", set.name), y)
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
        local f = FDB()
        local list = f and f.customIDs
        if not list then
            return
        end
        for j = #list, 1, -1 do
            if list[j] == id then
                table.remove(list, j)
            end
        end
        if f.customClasses then
            f.customClasses[id] = nil
        end
        Rebuild()
    end

    -- Whether spell id reminds class token (on unless unticked).
    local function CustomClassOn(id, token)
        local f = FDB()
        local off = f and f.customClasses and f.customClasses[id]
        return not (off and off[token] == false)
    end
    -- Ticks or unticks class token for spell id; only unticked classes are
    -- stored, and an entry with none left goes.
    local function SetCustomClass(id, token, on)
        local f = FDB()
        if not f then
            return
        end
        f.customClasses = f.customClasses or {}
        local all = f.customClasses
        local off = all[id]
        if on then
            if off then
                off[token] = nil
                if not next(off) then
                    all[id] = nil
                end
            end
        else
            off = off or {}
            all[id] = off
            off[token] = false
        end
        RefreshAll()
    end

    -- The class checklist's items: Remove at the top, then each class in its colour.
    local function CustomClassItems(id)
        local items = {
            {
                key = "_remove",
                label = "Remove",
                isTopAction = true,
                onClick = function()
                    RemoveCustomSpell(id)
                end,
            },
        }
        for _, token in ipairs(CludesUI.ForeverClasses()) do
            local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
            local name = CludesUI.ForeverClassName(token)
            items[#items + 1] =
                { key = token, label = c and c.colorStr and ("|c" .. c.colorStr .. name .. "|r") or name }
        end
        return items
    end

    -- A tracked spell's slot: its icon before the name, and its classes
    -- (Remove at the top) on the right.
    local function DressCustomSlot(rgn, id)
        if not id then
            return
        end
        local label = rgn._label
        if label then
            local icon = rgn:CreateTexture(nil, "ARTWORK")
            icon:SetSize(22, 22)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:SetTexture(Tex(id))
            PP.Point(icon, "LEFT", rgn, "LEFT", 20, 0)
            label:ClearAllPoints()
            PP.Point(label, "LEFT", icon, "RIGHT", 8, 0)
        end
        local dd, refresh = CludesUI.BuildVisOptsCBDropdown(
            rgn,
            170,
            rgn:GetFrameLevel() + 2,
            CustomClassItems(id),
            function(token)
                return CustomClassOn(id, token)
            end,
            function(token, on)
                SetCustomClass(id, token, on)
            end
        )
        PP.Point(dd, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = dd
        rgn._lastInline = nil
        CludesUI.RegisterWidgetRefresh(refresh)
    end

    local function BuildForeverCustomRows(parent, y, lead)
        local f = FDB()
        local ids = f and f.customIDs
        local slots = {
            lead,
            ButtonSlot(
                "New Spell Group",
                "Create",
                "Creates a group of spells. A reminder shows if none of the auras from the group are active.",
                function()
                    PromptSpellGroupName()
                end
            ),
        }
        for _, id in ipairs(ids or {}) do
            slots[#slots + 1] = {
                type = "label",
                text = SpellText(id),
                tooltip = "Reminds you whenever this buff is missing, on the classes ticked here.",
            }
        end
        return SlotRows(parent, y, slots, function(row, k)
            if ids and not CludesUI._prebuilding then
                DressCustomSlot(row._leftRegion, ids[k - 2])
                DressCustomSlot(row._rightRegion, ids[k - 1])
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Glow site: the reminder icon glow as a shared glow descriptor, used by the
    --  Reminders page and the Global Settings Glows page.
    ---------------------------------------------------------------------------
    local abrGlowDesc
    do
        local GO = CludesUI.GlowOptions
        abrGlowDesc = _G._CUABR_GLOW_VIEW
            and {
                view = _G._CUABR_GLOW_VIEW,
                host = "icon",
                excludes = { [4] = true },
                caps = { mode = true, params = true, bg = true },
                defaultColor = { r = 1.0, g = 0.788, b = 0.137 },
                onChange = function()
                    RefreshAll()
                    UpdatePreviewHeader()
                end,
                get = function(f)
                    local d = DDB()
                    if not d then
                        return nil
                    end
                    if f == "style" then
                        return d.glowType or 0
                    elseif f == "mode" then
                        -- Read-path migration: a profile activated mid-session may not
                        -- have a mode key yet; derive it from the stored color.
                        if _G._CUABR_EnsureGlowModeMigrated then
                            _G._CUABR_EnsureGlowModeMigrated(d)
                        end
                        return d.glowColorMode or "default"
                    end
                    return CludesUI.GlowOptions.FlatGet(d, "glow", f)
                end,
                set = function(f, a, b2, c2)
                    local d = DDB()
                    if not d then
                        return
                    end
                    if f == "style" then
                        d.glowType = a
                    elseif f == "mode" then
                        d.glowColorMode = a
                    else
                        CludesUI.GlowOptions.FlatSet(d, "glow", f, a, b2, c2)
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
        local watch, builtHoly, queued
        local function IsHoly()
            local spec = C_SpecializationInfo.GetSpecialization()
            return spec ~= nil and C_SpecializationInfo.GetSpecializationInfo(spec) == 65
        end
        -- One rebuild per burst, a frame later: a cached page has finished showing
        local function Flush()
            queued = nil
            if watch:IsVisible() and IsHoly() ~= builtHoly then
                CludesUI:RefreshPage(true)
            end
        end
        local function Queue()
            if queued then
                return
            end
            queued = true
            C_Timer.After(0, Flush)
        end
        -- Each build of the page: whether the toggle shows
        BeaconRowShown = function(parent)
            if not paladin then
                return false
            end
            local holy = IsHoly()
            if CludesUI._prebuilding then
                return holy
            end
            builtHoly = holy
            if not watch then
                watch = CreateFrame("Frame")
                watch._searchIgnore = true -- the inline search never hides it
                watch:SetScript("OnEvent", Queue)
                watch:SetScript("OnShow", function(self)
                    self:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
                    if IsHoly() ~= builtHoly then
                        Queue()
                    end
                end)
                watch:SetScript("OnHide", function(self)
                    self:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
                end)
            end
            watch:Hide()
            watch:SetParent(parent)
            -- On a kept page wrapper the watcher rides it as an attachment: the
            -- wrapper's next dress hides it (as dropping the page did) and
            -- never moves it to the pool's graveyard.
            Pool.Attach(parent, watch)
            watch:Show()
            return holy
        end
    end

    -- Display field binders for the page's rows: Get(key, default) reads
    -- display[key] (default when unset or false), Set(key, after) writes it
    -- and runs after (default: refresh the reminders and the preview).
    local function Live()
        RefreshAll()
        UpdatePreviewHeader()
    end
    local function Get(key, default)
        return function()
            local d = DDB()
            return d and d[key] or default
        end
    end
    local function Set(key, after)
        return function(v)
            local d = DDB()
            if not d then
                return
            end
            d[key] = v;
            (after or Live)(v)
        end
    end

    -- The page's opening line: what the reminder icons' clicks do.
    local function ClickInfoLine(parent, y)
        local info = CreateFrame("Frame", nil, parent)
        info:SetSize(parent:GetWidth(), 20)
        info:SetPoint("TOP", parent, "TOP", 0, y - 15)
        info._isSpacer = true
        local text = info:CreateFontString(nil, "OVERLAY")
        text:SetFont(CludesUI.GetFontPath("auraBuff") or "Fonts\\FRIZQT__.TTF", 15, "")
        text:SetTextColor(1, 1, 1, 0.75)
        text:SetPoint("TOP", info, "TOP", 0, 0)
        text:SetJustifyH("CENTER")
        text:SetText(
            CludesUI.L(
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
        if CludesUI._prebuilding then
            return y - (GAP + height + 14)
        end
        local R, G, B = FOREVER_RED[1], FOREVER_RED[2], FOREVER_RED[3]
        local function Red(host)
            return CludesUI.MakeFont(host, 16, nil, R, G, B, 1)
        end
        local PAD = CludesUI.CONTENT_PAD
        local w = parent:GetWidth() - PAD * 2
        local host = CreateFrame("Frame", nil, parent)
        PP.Point(host, "TOPLEFT", parent, "TOPLEFT", PAD, y - GAP)
        local first = Red(host)
        first:SetPoint("TOP", host, "TOP", 0, 0)
        first:SetWidth(w)
        first:SetWordWrap(true)
        first:SetJustifyH("CENTER")
        first:SetText(
            CludesUI.L("This module is for OUT OF COMBAT non-rotational buff/consumable reminders,")
        )

        -- The second line: the text either side of the link.
        local template = CludesUI.L("for in combat aura/rotational reminders please use the %s") or ""
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
        linkFs:SetText(CludesUI.L("CDM module"))
        link:SetSize(math.ceil(linkFs:GetStringWidth() or 80) + 1, 20)
        link:SetPoint("LEFT", beforeFs, "RIGHT", 0, 0)
        local afterFs = Red(second)
        afterFs:SetPoint("LEFT", link, "RIGHT", 0, 0)
        afterFs:SetText(after)
        if CludesUI._ModuleNS["CludesUICooldownManager"] then
            local EG = CludesUI.CLUDES_GREEN
            linkFs:SetTextColor(EG.r, EG.g, EG.b, 1)
            linkFs:SetAlpha(0.85)
            link:SetScript("OnEnter", function(self)
                linkFs:SetAlpha(1)
                CludesUI.ShowWidgetTooltip(self, CludesUI.L("Open the Cooldown Manager's Buffs bar"))
            end)
            link:SetScript("OnLeave", function()
                linkFs:SetAlpha(0.85)
                CludesUI.HideWidgetTooltip()
            end)
            link:SetScript("OnClick", function()
                CludesUI.HideWidgetTooltip()
                CludesUI:NavigateToElementSettings("CludesUICooldownManager", "CDM Bars", nil, function()
                    if CludesUI._setCDMBar then
                        CludesUI._setCDMBar("buffs")
                    end
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
        local W = CludesUI.Widgets
        local _
        local header, h = W:SectionHeader(parent, SECTION_CORE, y, nil, {
            tooltip = "Master toggle for all aura, buff, and consumable reminders. Talent reminders are not affected.",
            getValue = function()
                local d = DDB()
                return d and d.remindersEnabled ~= false
            end,
            setValue = Set("remindersEnabled", function()
                if _G._CUABR_UpdateGroupAuraRegistration then
                    _G._CUABR_UpdateGroupAuraRegistration()
                end
                RefreshAll()
                CludesUI:RefreshPage()
            end),
        })
        y = y - h
        CludesUI.BuildSectionUnlockJump(header, { key = "EABR_Reminders" })

        _, h = W:DualRow(parent, y, {
            type = "dropdown",
            text = "Grow Direction",
            values = GROW_DIR_VALUES,
            order = GROW_DIR_ORDER,
            tooltip = "Which part of the row stays in place as reminders appear and disappear.",
            getValue = Get("growDirection", "CENTER"),
            setValue = function(v)
                CludesUI.SetAuraBuffGrowDir(v)
                RefreshAll()
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
                disabled = function()
                    return not CludesUI._ModuleNS["CludesUIRaidFrames"]
                end,
                disabledTooltip = CludesUI.DisabledTooltip("CludesUI Raid & Party Frames"),
                getValue = function()
                    local d = DDB()
                    return d and d.beaconMPlus == true
                end,
                setValue = function(v)
                    local d = DDB()
                    if d then
                        d.beaconMPlus = v or nil
                        RefreshAll()
                    end
                end,
            }, CludesUI.BlankRowCfg())
            y = y - h
        end
        return y, header
    end

    -- A display field as read (nil when unset) and a write with no follow-up.
    local function Raw(key)
        return function()
            local d = DDB()
            return d and d[key]
        end
    end
    local function Store(key)
        return function(v)
            local d = DDB()
            if d then
                d[key] = v
            end
        end
    end
    local function BorderTex()
        local d = DDB()
        return (d and d.borderTexture) or "solid"
    end
    local function BorderStep()
        local d = DDB()
        return (d and d.borderSize) or 1
    end
    -- A shape change re-masks the reminder icons and the preview.
    local function Reshape()
        ns.RefreshIconShapes()
        UpdatePreviewHeader()
    end

    -- Icon Shape (+ crop cog) | Icon Zoom.
    local function BuildShapeRow(parent, y)
        local values, order = ns.IconShapeValues()
        local row, h = CludesUI.Widgets:DualRow(parent, y, {
            type = "dropdown",
            text = "Icon Shape",
            values = values,
            order = order,
            itemDisabled = function(v)
                local d = DDB()
                return v ~= "none" and v ~= "cropped" and d and (d.borderTexture or "solid") ~= "solid"
            end,
            itemDisabledTooltip = "This option requires Border Style to be set to Solid",
            getValue = Get("iconShape", "none"),
            setValue = Set("iconShape", function()
                Reshape()
                CludesUI:RefreshPage(true)
            end),
        }, {
            type = "slider",
            text = "Icon Zoom",
            min = 0,
            max = 15,
            step = 0.5,
            getValue = function()
                local d = DDB()
                return ((d and d.iconZoom) or 0.07) * 100
            end,
            setValue = function(v)
                local d = DDB()
                if d then
                    d.iconZoom = v / 100
                    Reshape()
                end
            end,
        })
        CludesUI.BuildInlineCog(row._leftRegion, {
            title = "Icon Shape",
            disabled = function()
                local d = DDB()
                return not d or d.iconShape ~= "cropped"
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
                    get = function()
                        return ns.CropPercent(DDB())
                    end,
                    set = Set("iconCropPercent", Reshape),
                },
            },
        })
        return y - h
    end

    -- A new border style starts from that style's own colour, layering and
    -- size, with no leftover offsets, shifts or exact pixels.
    local function PickBorderStyle(v)
        local d = DDB()
        if not d then
            return
        end
        d.borderTexture = v
        d.borderTextureOffset, d.borderTextureOffsetY = nil, nil
        d.borderTextureShiftX, d.borderTextureShiftY = nil, nil
        local color, behind = CludesUI.GetBorderStyleSelectDefaults(v)
        d.borderR, d.borderG, d.borderB, d.borderA = color.r, color.g, color.b, 1
        d.borderBehind = behind
        d.borderSize = CludesUI.GetBorderDefaultSize("aurabuffreminders", v) or d.borderSize
        if d.borderSizePx then
            d.borderSizePx = false
        end
        RefreshBorders()
        -- Rebuild: the Width | Height Offset row follows the Solid / textured pick.
        CludesUI:RefreshPage(true)
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
                    local d = DDB()
                    return d and (d.borderSize or 1) > 0 and "strong" or "none"
                end,
                setValue = function(v)
                    local d = DDB()
                    if not d then
                        return
                    end
                    if v ~= "strong" then
                        d.borderSize = 0
                    elseif (d.borderSize or 1) <= 0 then
                        d.borderSize = 1
                    end
                    RefreshBorders()
                end,
            }
        end
        return CludesUI.BorderPxSliderCfg({
            text = "Border Size",
            getStep = BorderStep,
            setStep = Store("borderSize"),
            getTex = BorderTex,
            getPx = Raw("borderSizePx"),
            setPx = Store("borderSizePx"),
            apply = RefreshBorders,
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
                local d = DDB()
                if not d then
                    return 0
                end
                if d[key] ~= nil then
                    return d[key]
                end
                return (
                    select(
                        which,
                        CludesUI.GetBorderDefaults(
                            "aurabuffreminders",
                            d.borderTexture or "solid",
                            d.borderSize or 1
                        )
                    )
                )
            end,
            set = function(v)
                local d = DDB()
                if d then
                    d[key] = (v ~= 0) and v or nil
                    RefreshBorders()
                end
            end,
        }
    end

    -- Border Style (+ options cog, textured styles only) | Border Size (+
    -- colour swatch), then for a textured style its Width | Height Offset
    -- row (each slider shows what is drawn, the override else the registry
    -- default for the step, and stores nothing while it follows the default).
    local function BuildBorderRows(parent, y)
        local W = CludesUI.Widgets
        local values, order = CludesUI.GetBorderTextureDropdown()
        local row, h = W:DualRow(parent, y, {
            type = "dropdown",
            text = "Border Style",
            disabled = function()
                return ns.IconShapeMasked(DDB())
            end,
            disabledTooltip = "This option requires Icon Shape to be set to None or Cropped",
            values = values,
            order = order,
            getValue = Get("borderTexture", "solid"),
            setValue = PickBorderStyle,
        }, BorderSizeCfg())
        y = y - h

        local tex = BorderTex()
        if tex ~= "" and tex ~= "solid" then
            local left, right = CludesUI.BorderOffsetRowCfgs({
                addonKey = "aurabuffreminders",
                getTex = BorderTex,
                getStep = BorderStep,
                getSizeKey = BorderStep,
                getPx = Raw("borderSizePx"),
                getX = Raw("borderTextureOffset"),
                setX = Store("borderTextureOffset"),
                getY = Raw("borderTextureOffsetY"),
                setY = Store("borderTextureOffsetY"),
                apply = RefreshBorders,
            })
            local _, offsetH = W:DualRow(parent, y, left, right)
            y = y - offsetH
        end
        if CludesUI._prebuilding then
            return y, row
        end

        local cog = CludesUI.BuildInlineCog(row._leftRegion, {
            title = "Border Options",
            rows = {
                ShiftRow("Shift X", "borderTextureShiftX", 3),
                ShiftRow("Shift Y", "borderTextureShiftY", 4),
                {
                    type = "toggle",
                    label = "Show Behind",
                    get = function()
                        local d = DDB()
                        return d and d.borderBehind == true
                    end,
                    set = function(v)
                        local d = DDB()
                        if d then
                            d.borderBehind = v
                            RefreshBorders()
                        end
                    end,
                },
            },
        })
        local function CogShown()
            local d = DDB()
            cog:SetShown(d and (d.borderTexture or "solid") ~= "solid")
        end
        CogShown()
        CludesUI.RegisterWidgetRefresh(CogShown)

        local rgn = row._rightRegion
        local swatch, refresh = CludesUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, function()
            local d = DDB()
            return (d and d.borderR) or 0,
                (d and d.borderG) or 0,
                (d and d.borderB) or 0,
                (d and d.borderA) or 1
        end, function(r, g, b, a)
            local d = DDB()
            if d then
                d.borderR, d.borderG, d.borderB, d.borderA = r, g, b, a or 1
                RefreshBorders()
            end
        end, true, 20)
        swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
        rgn._lastInline = swatch
        CludesUI.RegisterWidgetRefresh(refresh)
        return y, row
    end

    local function BuildRemindersPage(pageName, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h, row

        -- Cell reference table for preview icon specific toggle navigation
        local _gridCellRefs = {}

        -- The preview header (retail only; WoW Forever has no preview).
        if not FOREVER then
            CludesUI:SetContentHeader(_previewHeaderBuilder)
        end
        parent._showRowDivider = true

        y = ClickInfoLine(parent, y)
        if FOREVER then
            y = ForeverPurposeBanner(parent, y)
        end
        local coreSection
        y, coreSection = BuildCoreSection(parent, y)

        -----------------------------------------------------------------------
        --  DISPLAY section
        -----------------------------------------------------------------------
        local displaySection
        displaySection, h = W:SectionHeader(parent, SECTION_DISPLAY, y)
        y = y - h

        y = BuildShapeRow(parent, y)
        local borderRow
        y, borderRow = BuildBorderRows(parent, y)

        -- Row 2: Show Name (+ inline cog + swatch) | Show Item Count (+ cog)
        local rowText
        rowText, h = W:DualRow(parent, y, {
            type = "toggle",
            text = "Show Name",
            getValue = function()
                local d = DDB()
                return d and d.showText
            end,
            setValue = function(v)
                local d = DDB()
                if not d then
                    return
                end
                d.showText = v
                RefreshAll()
                UpdatePreviewHeader()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "toggle",
            text = "Show Item Count",
            tooltip = "Show how many of the consumable you have left in your bags.",
            getValue = function()
                local d = DDB()
                return not d or d.showCount ~= false
            end,
            setValue = function(v)
                local d = DDB()
                if not d then
                    return
                end
                d.showCount = v
                RefreshAll()
                UpdatePreviewHeader()
                CludesUI:RefreshPage()
            end,
        })
        y = y - h

        -- Inline cog on Show Item Count (right of row 2): size + offsets
        if not CludesUI._prebuilding then
            local rgn = rowText._rightRegion
            local countFontValues, countFontOrder = CludesUI.BuildFontDropdownData()
            CludesUI.BuildInlineCog(rgn, {
                title = "Item Count Settings",
                disabled = function()
                    local d = DDB()
                    return d and d.showCount == false
                end,
                disabledTooltip = "Show Item Count",
                rows = {
                    {
                        type = "dropdown",
                        label = "Item Count Font",
                        values = countFontValues,
                        order = countFontOrder,
                        get = function()
                            local d = DDB()
                            return (d and d.countFont) or "__global"
                        end,
                        set = function(v)
                            local d = DDB()
                            if not d then
                                return
                            end
                            d.countFont = (v ~= "__global") and v or nil
                            RefreshAll()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 6,
                        max = 30,
                        step = 1,
                        get = function()
                            local d = DDB()
                            return d and d.countSize or 16
                        end,
                        set = function(v)
                            local d = DDB()
                            if not d then
                                return
                            end
                            d.countSize = v
                            RefreshAll()
                            UpdatePreviewHeader()
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            local d = DDB()
                            return d and d.countXOffset or 0
                        end,
                        set = function(v)
                            local d = DDB()
                            if not d then
                                return
                            end
                            d.countXOffset = v
                            RefreshAll()
                            UpdatePreviewHeader()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            local d = DDB()
                            return d and d.countYOffset or 0
                        end,
                        set = function(v)
                            local d = DDB()
                            if not d then
                                return
                            end
                            d.countYOffset = v
                            RefreshAll()
                            UpdatePreviewHeader()
                        end,
                    },
                },
            })
        end

        -- Row 3: Glow Type (shared glow controls) | Attach Important Buffs to Cursor
        local GO = CludesUI.GlowOptions
        local abrDesc = abrGlowDesc
        local rowGlow
        rowGlow, h = W:DualRow(
            parent,
            y,
            abrDesc and GO.DropdownSpec(abrDesc, "Glow Type") or CludesUI.BlankRowCfg(),
            {
                type = "toggle",
                text = "Attach Important Buffs to Cursor",
                tooltip = "This option only affects Raid Buffs and Paladin Beacons",
                getValue = function()
                    local d = DDB()
                    return d and d.cursorAttach
                end,
                setValue = function(v)
                    local d = DDB()
                    if not d then
                        return
                    end
                    d.cursorAttach = v
                    RefreshAll()
                    CludesUI:RefreshPage()
                end,
            }
        )
        y = y - h
        if abrDesc then
            GO.AttachInline(rowGlow._leftRegion, abrDesc)
        end

        -- Inline cog on Attach Important Buffs to Cursor (right of row 3)
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(rowGlow._rightRegion, {
                title = "Cursor Settings",
                disabled = function()
                    local d = DDB()
                    return not (d and d.cursorAttach)
                end,
                disabledTooltip = "Attach Important Buffs to Cursor",
                rows = {
                    {
                        type = "toggle",
                        label = "Only on Cursor in Combat",
                        tooltip = "Out of combat, important buffs show with your other reminders.",
                        get = function()
                            local d = DDB()
                            return d and d.cursorAttachCombatOnly == true
                        end,
                        set = function(v)
                            local d = DDB()
                            if not d then
                                return
                            end
                            d.cursorAttachCombatOnly = v
                            RefreshAll()
                        end,
                    },
                },
            })
        end

        -- Inline cog + color swatch on Show Name (left of row 2)
        if not CludesUI._prebuilding then
            local rgn = rowText._leftRegion
            -- Inline cog for name settings (font, size, anchor, x/y offset)
            local nameFontValues, nameFontOrder = CludesUI.BuildFontDropdownData()
            CludesUI.BuildInlineCog(rgn, {
                title = "Name Settings",
                disabled = function()
                    local d = DDB()
                    return not d or not d.showText
                end,
                disabledTooltip = "Show Name",
                rows = {
                    {
                        type = "dropdown",
                        label = "Name Font",
                        values = nameFontValues,
                        order = nameFontOrder,
                        get = function()
                            local d = DDB()
                            return (d and d.nameFont) or "__global"
                        end,
                        set = function(v)
                            local d = DDB()
                            if not d then
                                return
                            end
                            d.nameFont = (v ~= "__global") and v or nil
                            RefreshAll()
                            UpdatePreviewHeader()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 6,
                        max = 30,
                        step = 1,
                        get = function()
                            local d = DDB()
                            return d and d.textSize or 11
                        end,
                        set = function(v)
                            local d = DDB()
                            if not d then
                                return
                            end
                            d.textSize = v
                            RefreshAll()
                            UpdatePreviewHeader()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Anchor",
                        values = {
                            BOTTOM = "Below Icon",
                            TOP = "Above Icon",
                            CENTER = "On Icon",
                            LEFT = "Left of Icon",
                            RIGHT = "Right of Icon",
                        },
                        order = { "BOTTOM", "TOP", "CENTER", "LEFT", "RIGHT" },
                        get = function()
                            local d = DDB()
                            return d and d.textAnchor or "BOTTOM"
                        end,
                        set = function(v)
                            local d = DDB()
                            if not d then
                                return
                            end
                            d.textAnchor = v
                            RefreshAll()
                            UpdatePreviewHeader()
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            local d = DDB()
                            return d and d.textXOffset or 0
                        end,
                        set = function(v)
                            local d = DDB()
                            if not d then
                                return
                            end
                            d.textXOffset = v
                            RefreshAll()
                            UpdatePreviewHeader()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            local d = DDB()
                            return d and d.textYOffset or -2
                        end,
                        set = function(v)
                            local d = DDB()
                            if not d then
                                return
                            end
                            d.textYOffset = v
                            RefreshAll()
                            UpdatePreviewHeader()
                        end,
                    },
                },
            })

            local swatch = CludesUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, function()
                local d = DDB()
                local tc = d and d.textColor or { r = 1, g = 1, b = 1 }
                return tc.r, tc.g, tc.b, 1
            end, function(r, g, b)
                local d = DDB()
                if not d then
                    return
                end
                d.textColor = { r = r, g = g, b = b }
                RefreshAll()
                UpdatePreviewHeader()
            end, false, 20)
            swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = swatch

            -- Disabled overlay for swatch when Show Name is off
            local swatchBlock = CreateFrame("Frame", nil, swatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            swatchBlock:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(swatch, CludesUI.DisabledTooltip("Show Name"))
            end)
            swatchBlock:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            local function UpdateTextInlinesDisabled()
                local d = DDB()
                local off = not d or not d.showText
                swatch:SetAlpha(off and 0.3 or 1)
                swatchBlock:SetShown(off)
            end
            UpdateTextInlinesDisabled()
            CludesUI.RegisterWidgetRefresh(UpdateTextInlinesDisabled)
        end

        -- Row 4: Icon Spacing (+ directions cog) | Frame Strata
        local rowSliders
        rowSliders, h = W:DualRow(parent, y, {
            type = "slider",
            pixel = true,
            text = "Icon Spacing",
            min = 0,
            max = 50,
            step = 1,
            getValue = function()
                local d = DDB()
                return d and d.iconSpacing or 8
            end,
            setValue = function(v)
                local d = DDB()
                if not d then
                    return
                end
                d.iconSpacing = v
                RefreshAll()
                RelayoutPreviewIcons()
            end,
        }, {
            type = "dropdown",
            text = "Frame Strata",
            values = _G._CUABR_STRATA_VALUES or { MEDIUM = "Medium" },
            order = _G._CUABR_STRATA_ORDER or { "MEDIUM" },
            getValue = function()
                local d = DDB()
                return d and d.frameStrata or "MEDIUM"
            end,
            setValue = function(v)
                local d = DDB()
                if not d then
                    return
                end
                d.frameStrata = v
                if _G._CUABR_ApplyStrata then
                    _G._CUABR_ApplyStrata()
                end
            end,
        })
        y = y - h

        -- Inline DIRECTIONS cog on Icon Spacing (left of row 3) for Y offset
        if not CludesUI._prebuilding then
            local rgn = rowSliders._leftRegion
            CludesUI.BuildInlineCog(rgn, {
                title = "Layout Settings",
                rows = {
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -600,
                        max = 600,
                        step = 1,
                        get = function()
                            local d = DDB()
                            return d and d.yOffset or 0
                        end,
                        set = function(v)
                            local d = DDB()
                            if not d then
                                return
                            end
                            d.yOffset = v
                            if _G._CUABR_ApplyUnlockPos then
                                _G._CUABR_ApplyUnlockPos()
                            end
                        end,
                    },
                },
            })
        end

        -- Row 5: Show Below | Show Below Pre-Key (global timing, minutes)
        -- No expiry thresholds on WoW Forever (its reminders are absence only): the row is not built there.
        if not FOREVER then
            local timingRow
            timingRow, h = W:DualRow(parent, y, {
                type = "slider",
                text = "Show Below",
                min = 0,
                max = 60,
                step = 1,
                tooltip = "Show reminders when remaining buff time is below this many minutes.\n0 = only when fully expired.\nIgnored in combat and during Mythic+ keys (then only when the buff is gone).",
                getValue = function()
                    local d = DDB()
                    return d and d.showUnder or 5
                end,
                setValue = function(v)
                    local d = DDB()
                    if not d then
                        return
                    end
                    d.showUnder = v
                    RefreshAll()
                end,
            }, {
                type = "slider",
                text = "Show Below Pre-Key",
                min = 0,
                max = 60,
                step = 1,
                tooltip = "Reminder threshold while you are in a dungeon before a Mythic+ key starts (Mythic 0 / keystone lobby). Set it high enough that you top up buffs and food before pulling, so you begin the key with enough duration to last it.\n0 = only when fully expired.\nIgnored once the key is active or you are in combat (then only when the buff is fully gone).",
                getValue = function()
                    local d = DDB()
                    return d and d.showUnderMPlus or 40
                end,
                setValue = function(v)
                    local d = DDB()
                    if not d then
                        return
                    end
                    d.showUnderMPlus = v
                    RefreshAll()
                end,
            })
            y = y - h
            AddMinSuffix(timingRow, "Show Below", "Show Below Pre-Key")
        end -- not FOREVER

        -- Row 6: Show Tooltips | Opacity
        _, h = W:DualRow(parent, y, {
            type = "toggle",
            text = "Show Tooltips",
            tooltip = "Show item or spell tooltips when hovering reminder icons.",
            getValue = function()
                local d = DDB()
                return not d or d.showTooltips ~= false
            end,
            setValue = function(v)
                local d = DDB()
                if not d then
                    return
                end
                d.showTooltips = v
            end,
        }, {
            type = "slider",
            text = "Opacity",
            min = 0,
            max = 1,
            step = 0.05,
            getValue = function()
                local d = DDB()
                return d and d.opacity or 1
            end,
            setValue = function(v)
                local d = DDB()
                if not d then
                    return
                end
                d.opacity = v
                RefreshAll()
                UpdatePreviewHeader()
            end,
        })
        y = y - h

        if FOREVER then
            _, h = W:DualRow(parent, y, {
                type = "toggle",
                text = "Action Picker",
                tooltip = "Right-click a spell group or Class Buffs reminder that has more than one spell to choose the spell its left click casts. Scroll over a spell in the picker to choose its rank.",
                getValue = function()
                    local f = FDB()
                    return f and f.pickerEnabled == true
                end,
                setValue = function(v)
                    local f = FDB()
                    if not f then
                        return
                    end
                    f.pickerEnabled = v
                    RefreshAll()
                end,
            }, CludesUI.BlankRowCfg())
            y = y - h
        end

        _, h = W:Spacer(parent, y, 20)
        y = y - h

        -----------------------------------------------------------------------
        --  RAID BUFFS section (WoW Forever: its own locations and its own
        --  buffs, which the module exports as the raid buff list there)
        -----------------------------------------------------------------------
        local raidBufHdr
        raidBufHdr, h = W:SectionHeader(parent, SECTION_RAID_BUFFS, y)
        y = y - h

        -- Where to Show | Show When (+ reminder sound cog)
        _, h = SectionControlRow(parent, y, {
            whereStore = RWhere,
            whereItems = FOREVER and FOREVER_WHERE_ITEMS or nil,
            whereTooltip = "Pick which content this section's reminders appear in.\nRested areas (cities and inns) always stay hidden.",
            showWhenStore = RShowWhen,
            showWhenTooltip = "Others are missing my buff: remind when a groupmate is missing a buff you can cast.\nI am missing others' buffs: remind when you are missing a buff a groupmate could give you (only shown when someone who can cast it is present). Off by default.",
            soundSec = RDB,
            soundField = "sectionSound",
            cogTitle = (not FOREVER) and "Raid Buff Options" or nil,
            cogRows = not FOREVER
                    and {
                        {
                            type = "toggle",
                            label = "Click to Request Buff",
                            tooltip = "Click a buff or Healthstone to ask for it.",
                            get = function()
                                local r = RDB()
                                return r and r.requestOnClick == true
                            end,
                            set = function(v)
                                local r = RDB()
                                if r then
                                    r.requestOnClick = v
                                    RefreshAll()
                                end
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Custom Request Text",
                            tooltip = "Send your own text instead of the default.",
                            disabled = function()
                                local r = RDB()
                                return not (r and r.requestOnClick)
                            end,
                            disabledTooltip = "Click to Request Buff",
                            get = function()
                                local r = RDB()
                                return r and r.requestCustom == true
                            end,
                            set = function(v)
                                local r = RDB()
                                if r then
                                    r.requestCustom = v
                                end
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
                                if not r then
                                    return ""
                                end
                                return r.requestText or _G._CUABR_RequestExample()
                            end,
                            set = function(v)
                                local r = RDB()
                                if not r then
                                    return
                                end
                                local clean = _G._CUABR_CleanRequestText(v)
                                -- The untouched example stays unsaved, so it follows the client language.
                                if clean == _G._CUABR_RequestExample() then
                                    clean = nil
                                end
                                r.requestText = clean
                                if clean and not _G._CUABR_HasRequestToken(clean) then
                                    UIErrorsFrame:AddMessage(
                                        CludesUI.Lf("Request text must include %1$s", _G._CUABR_REQUEST_TOKEN),
                                        1.0,
                                        0.3,
                                        0.3,
                                        1.0
                                    )
                                end
                            end,
                        },
                    }
                or nil,
            onChange = RefreshAll,
            onShowWhenChange = function()
                if _G._CUABR_UpdateGroupAuraRegistration then
                    _G._CUABR_UpdateGroupAuraRegistration()
                end
            end,
        })
        y = y - h

        -- 4-column checkbox grid for individual raid buffs
        do
            local RAID_BUFFS = _G._CUABR_RAID_BUFFS or {}
            local gridItems = {}
            for _, buff in ipairs(RAID_BUFFS) do
                gridItems[#gridItems + 1] = {
                    label = _G._CUABR_SpellName(buff.castSpell, buff.name),
                    classToken = buff.class,
                    key = buff.key,
                    getVal = function()
                        local r = RDB()
                        return r and r.enabled and r.enabled[buff.key]
                    end,
                    setVal = function(v)
                        local r = RDB()
                        if r and r.enabled then
                            r.enabled[buff.key] = v
                        end
                    end,
                }
            end
            h = BuildCheckboxGrid(parent, y, gridItems, function()
                RefreshAll()
                RebuildPreviewHeader()
            end, _gridCellRefs)
            y = y - h
        end

        _, h = W:Spacer(parent, y, 20)
        y = y - h

        -----------------------------------------------------------------------
        --  WOW FOREVER section: on that client the rest of the page.
        --  Camp Benefits | Sleeping Bag, Well Fed | Gathering Tracking,
        --  Find Treasure | Weapon Buffs, Mage Armors or Class Buffs, then the
        --  spell-ID entry
        --  that adds a custom reminder followed by one slot per tracked spell;
        --  the retail sections below never build.
        -----------------------------------------------------------------------
        if FOREVER then
            _, h = W:SectionHeader(parent, SECTION_FOREVER, y)
            y = y - h

            -- Where to Show | Reminder Sound
            _, h = SectionControlRow(parent, y, {
                whereStore = FWhere,
                whereItems = FOREVER_SECTION_WHERE_ITEMS,
                whereTooltip = "Pick which content the WoW Forever reminders appear in.\nRested areas (cities and inns) always stay hidden.",
                soundSec = FDB,
                soundField = "sectionSound",
                onChange = RefreshAll,
            })
            y = y - h

            -- Camp Benefits | Sleeping Bag
            _, h = W:DualRow(parent, y, {
                type = "toggle",
                text = "Camp Benefits",
                tooltip = "Reminds you when the Camp Benefits campfire buff is missing.",
                getValue = function()
                    local f = FDB()
                    return not f or f.camp ~= false
                end,
                setValue = function(v)
                    local f = FDB()
                    if not f then
                        return
                    end
                    f.camp = v
                    RefreshAll()
                end,
            }, {
                type = "toggle",
                text = "Sleeping Bag",
                tooltip = "Reminds you when your Well-Rested buff is missing or under 3 stacks.\nOnly while a Cozy Sleeping Bag is in your bags and you are below max level.\nClick the icon to use it.",
                getValue = function()
                    local f = FDB()
                    return f and f.sleepingBag == true
                end,
                setValue = function(v)
                    local f = FDB()
                    if not f then
                        return
                    end
                    f.sleepingBag = v
                    RefreshAll()
                end,
            })
            y = y - h

            -- Well Fed | Gathering Tracking (+ class tracking cog)
            local gatherRow
            gatherRow, h = W:DualRow(
                parent,
                y,
                -- The client's own name for the buff (19705, EABR.WELL_FED), so it reads localized.
                {
                    type = "toggle",
                    text = _G._CUABR_SpellName(19705, "Well Fed"),
                    tooltip = "Reminds you when you have no Well Fed buff.",
                    getValue = function()
                        local f = FDB()
                        return f and f.wellFed == true
                    end,
                    setValue = function(v)
                        local f = FDB()
                        if not f then
                            return
                        end
                        f.wellFed = v
                        RefreshAll()
                    end,
                },
                {
                    type = "toggle",
                    text = "Gathering Tracking",
                    tooltip = "Reminds you when no gathering tracking is on.",
                    getValue = function()
                        local f = FDB()
                        return f and f.gather == true
                    end,
                    setValue = function(v)
                        local f = FDB()
                        if not f then
                            return
                        end
                        f.gather = v
                        RefreshAll()
                        CludesUI:RefreshPage()
                    end,
                }
            )
            y = y - h

            if not CludesUI._prebuilding then
                CludesUI.BuildInlineCog(gatherRow._rightRegion, {
                    title = "Gathering Tracking",
                    disabled = function()
                        local f = FDB()
                        return not (f and f.gather == true)
                    end,
                    disabledTooltip = "Gathering Tracking",
                    rows = {
                        {
                            type = "toggle",
                            label = "Ignore If Class Tracking Is Active",
                            get = function()
                                local f = FDB()
                                return not f or f.gatherClassTrack ~= false
                            end,
                            set = function(v)
                                local f = FDB()
                                if f then
                                    f.gatherClassTrack = v
                                    RefreshAll()
                                end
                            end,
                        },
                    },
                })
            end

            local class = select(2, UnitClass("player"))
            local classBuffs = not MAGE and _G._CUABR_FvClassBuffs and _G._CUABR_FvClassBuffs()[class]
            local weaponRow
            weaponRow, h = W:DualRow(parent, y, {
                type = "toggle",
                text = _G._CUABR_SpellName(2481, "Find Treasure"),
                tooltip = "Reminds Dwarves when Find Treasure is off.",
                getValue = function()
                    local f = FDB()
                    return f and f.treasure == true
                end,
                setValue = function(v)
                    local f = FDB()
                    if not f then
                        return
                    end
                    f.treasure = v
                    RefreshAll()
                end,
            }, {
                type = "toggle",
                text = "Weapon Buffs",
                tooltip = "Reminds you when a weapon has no poison, imbue, stone or oil.\nClick the icon to apply one from your bags.",
                getValue = function()
                    local f = FDB()
                    return f and f.weapon == true
                end,
                setValue = function(v)
                    local f = FDB()
                    if not f then
                        return
                    end
                    f.weapon = v
                    RefreshAll()
                    CludesUI:RefreshPage()
                end,
            })
            y = y - h

            local classRow
            if MAGE or classBuffs then
                classRow, h = W:DualRow(parent, y, MAGE and {
                    type = "toggle",
                    text = "Mage Armors",
                    tooltip = "Reminds you when no Frost Armor, Ice Armor or Mage Armor is up.\nThe icon is the one you last had on; click it to cast it.",
                    getValue = function()
                        local f = FDB()
                        return f and f.mageArmor == true
                    end,
                    setValue = function(v)
                        local f = FDB()
                        if not f then
                            return
                        end
                        f.mageArmor = v
                        RefreshAll()
                    end,
                } or {
                    type = "label",
                    text = "Class Buffs",
                    tooltip = "Reminds you when one of your class's own buffs is missing.\nClick the icon to cast it.\nA custom spell or spell group for a ticked buff pauses meanwhile.",
                }, CludesUI.BlankRowCfg())
                y = y - h
            end

            -- Class Buffs: one checkbox per buff of the class (ticked: its own
            -- default until picked, EABR.FvClassBuffOn)
            if classBuffs and not CludesUI._prebuilding then
                local items, byKey = {}, {}
                for _, b in ipairs(classBuffs) do
                    local text, tip
                    if b.label then
                        local names, seen = {}, {}
                        for _, line in ipairs(b.lines) do
                            for _, id in ipairs({ line[1], line[#line] }) do
                                local n = _G._CUABR_SpellName(id)
                                if n and not seen[n] then
                                    seen[n] = true
                                    names[#names + 1] = n
                                end
                            end
                        end
                        text, tip = b.menu or b.label, table.concat(names, "\n")
                        if b.own then
                            tip = tip .. "\n\n" .. CludesUI.L("Only your own counts.")
                        end
                    else
                        local line = b.lines[1]
                        text = _G._CUABR_SpellName(line[#line], b.key)
                    end
                    items[#items + 1] = { key = b.key, label = text, tooltip = tip }
                    byKey[b.key] = b
                end
                local isOn = _G._CUABR_FvClassBuffOn
                local rgn = classRow._leftRegion
                local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                    rgn,
                    170,
                    rgn:GetFrameLevel() + 2,
                    items,
                    function(key)
                        local f = FDB()
                        return isOn(byKey[key], f and f.classBuffPicks)
                    end,
                    function(key, v)
                        local f = FDB()
                        if not f then
                            return
                        end
                        f.classBuffPicks = f.classBuffPicks or {}
                        f.classBuffPicks[key] = v and true or false
                        RefreshAll()
                    end
                )
                CludesUI.PanelPP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
                rgn._control = cbDD
                rgn._lastInline = nil
                CludesUI.RegisterWidgetRefresh(cbDDRefresh)
            end

            if not CludesUI._prebuilding then
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
                local function HandRow(label, field, values, order)
                    return {
                        type = "dropdown",
                        label = label,
                        values = values,
                        order = order,
                        ddWidth = 200,
                        get = function()
                            local f = FDB()
                            local t = f and f.weaponHands and f.weaponHands[class]
                            return t and t[field] or "auto"
                        end,
                        set = function(v)
                            local f = FDB()
                            if not f then
                                return
                            end
                            f.weaponHands = f.weaponHands or {}
                            local t = f.weaponHands[class]
                            if not t then
                                t = {}
                                f.weaponHands[class] = t
                            end
                            t[field] = v ~= "auto" and v or nil
                            RefreshAll()
                        end,
                    }
                end
                local imbueValues, imbueOrder = Choices(true)
                local tempValues, tempOrder = Choices(false)
                local hasImbues = #imbueOrder > 2
                local rogue = class == "ROGUE"
                local offHand = not CanDualWield or CanDualWield()
                local rows = {}
                if hasImbues then
                    rows[#rows + 1] = HandRow(
                        rogue and "Main Hand Poison" or "Main Hand Imbue",
                        "mhImbue",
                        imbueValues,
                        imbueOrder
                    )
                end
                rows[#rows + 1] = HandRow("Main Hand Stone or Oil", "mhTemp", tempValues, tempOrder)
                if offHand then
                    if hasImbues then
                        rows[#rows + 1] = HandRow(
                            rogue and "Off Hand Poison" or "Off Hand Imbue",
                            "ohImbue",
                            imbueValues,
                            imbueOrder
                        )
                    end
                    rows[#rows + 1] = HandRow("Off Hand Stone or Oil", "ohTemp", tempValues, tempOrder)
                end
                rows[#rows + 1] = {
                    type = "dropdown",
                    label = "Rank to Use",
                    ddWidth = 200,
                    values = { high = "Highest Owned", low = "Lowest Owned" },
                    order = { "high", "low" },
                    get = function()
                        local f = FDB()
                        return f and f.weaponLowRank and "low" or "high"
                    end,
                    set = function(v)
                        local f = FDB()
                        if f then
                            f.weaponLowRank = v == "low"
                            RefreshAll()
                        end
                    end,
                }
                rows[#rows + 1] = {
                    type = "toggle",
                    label = "Hide When None in Bags",
                    tooltip = "Hides a reminder when you have none of its item in your bags.\nOff: a chosen item still shows, greyed out. Auto only ever picks items you have.",
                    get = function()
                        local f = FDB()
                        return not f or f.weaponHideNoItem ~= false
                    end,
                    set = function(v)
                        local f = FDB()
                        if f then
                            f.weaponHideNoItem = v
                            RefreshAll()
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
                        local f = FDB()
                        return f and f.weaponShowBelow or 1
                    end,
                    set = function(v)
                        local f = FDB()
                        if f then
                            f.weaponShowBelow = v
                            RefreshAll()
                        end
                    end,
                }
                CludesUI.BuildInlineCog(weaponRow._rightRegion, {
                    title = "Weapon Buffs",
                    disabled = function()
                        local f = FDB()
                        return not (f and f.weapon == true)
                    end,
                    disabledTooltip = "Weapon Buffs",
                    minWidth = 320,
                    rows = rows,
                })
            end

            -- Add Custom Spell, paired with the tracked spells
            y = BuildForeverCustomRows(parent, y, {
                type = "input",
                text = "Add Custom Spell",
                inputStyle = "popup",
                placeholder = "Spell ID",
                inputWidth = 110,
                tooltip = "Type a spell ID and press Enter to be reminded whenever that buff is missing.\nUnknown IDs are ignored.",
                getValue = function()
                    return ""
                end,
                setValue = function(text)
                    local f = FDB()
                    if not f then
                        return
                    end
                    f.customIDs = f.customIDs or {}
                    AddSpellIDToList(f.customIDs, text)
                end,
            })
            y = BuildForeverGroupSections(parent, y)

            -- No preview header here, so no click-to-scroll mappings to wire.
            return math.abs(y)
        end

        -----------------------------------------------------------------------
        --  AURAS section
        -----------------------------------------------------------------------
        local auraHdr
        auraHdr, h = W:SectionHeader(parent, SECTION_AURAS, y)
        y = y - h

        -- Where to Show (+ reminder sound cog)
        _, h = SectionControlRow(parent, y, {
            whereStore = AWhere,
            whereTooltip = "Pick which content these aura reminders appear in.\nRested areas (cities and inns) always stay hidden.",
            soundSec = ADB,
            soundField = "sectionSound",
            onChange = RefreshAll,
        })
        y = y - h

        -- 4-column checkbox grid for individual auras
        do
            local AURAS = _G._CUABR_AURAS or {}
            local gridItems = {}
            for _, aura in ipairs(AURAS) do
                -- Soulstone is a Warlock-specific group utility reminder and
                -- is configured in the Warlock section below.
                if aura.key ~= "soulstone" then
                    gridItems[#gridItems + 1] = {
                        label = _G._CUABR_SpellName(aura.castSpell, aura.name),
                        classToken = aura.class,
                        key = aura.key,
                        tooltip = (aura.combatOnly and aura.isStance)
                                and "Shows in combat only, while you are out of this form."
                            or nil,
                        getVal = function()
                            local a = ADB()
                            return a and a.enabled and a.enabled[aura.key]
                        end,
                        setVal = function(v)
                            local a = ADB()
                            if a and a.enabled then
                                a.enabled[aura.key] = v
                            end
                        end,
                    }
                end
            end
            h = BuildCheckboxGrid(parent, y, gridItems, function()
                if _G._CUABR_UpdateGroupAuraRegistration then
                    _G._CUABR_UpdateGroupAuraRegistration()
                end
                RefreshAll()
                RebuildPreviewHeader()
            end, _gridCellRefs)
            y = y - h
        end

        _, h = W:Spacer(parent, y, 20)
        y = y - h

        -----------------------------------------------------------------------
        --  ROGUE POISONS sub-section
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_ROGUE, y)
        y = y - h
        _, h = SectionControlRow(parent, y, {
            whereStore = CSpecialWhere("ROGUE"),
            whereTooltip = SPECIAL_WHERE_TIP,
            soundSec = CDB,
            specialClass = "ROGUE",
            onChange = RefreshAll,
        })
        y = y - h

        do
            local POISONS = _G._CUABR_ROGUE_POISONS or {}
            local gridItems = {}
            for _, poison in ipairs(POISONS) do
                gridItems[#gridItems + 1] = {
                    label = _G._CUABR_SpellName(poison.castSpell, poison.name),
                    classToken = "ROGUE",
                    key = poison.key,
                    getVal = function()
                        local c = CDB()
                        return c and c.enabled and c.enabled[poison.key]
                    end,
                    setVal = function(v)
                        local c = CDB()
                        if c and c.enabled then
                            c.enabled[poison.key] = v
                        end
                    end,
                }
            end
            h = BuildCheckboxGrid(parent, y, gridItems, function()
                RefreshAll()
                RebuildPreviewHeader()
            end, _gridCellRefs)
            y = y - h
        end

        _, h = W:Spacer(parent, y, 10)
        y = y - h

        -----------------------------------------------------------------------
        --  PALADIN RITES sub-section
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_PALADIN, y)
        y = y - h
        _, h = SectionControlRow(parent, y, {
            whereStore = CSpecialWhere("PALADIN"),
            whereTooltip = SPECIAL_WHERE_TIP,
            soundSec = CDB,
            specialClass = "PALADIN",
            onChange = RefreshAll,
        })
        y = y - h

        do
            local RITES = _G._CUABR_PALADIN_RITES or {}
            local gridItems = {}
            for _, rite in ipairs(RITES) do
                gridItems[#gridItems + 1] = {
                    label = _G._CUABR_SpellName(rite.castSpell, rite.name),
                    classToken = "PALADIN",
                    key = rite.key,
                    getVal = function()
                        local c = CDB()
                        return c and c.enabled and c.enabled[rite.key]
                    end,
                    setVal = function(v)
                        local c = CDB()
                        if c and c.enabled then
                            c.enabled[rite.key] = v
                        end
                    end,
                }
            end
            h = BuildCheckboxGrid(parent, y, gridItems, function()
                RefreshAll()
                RebuildPreviewHeader()
            end, _gridCellRefs)
            y = y - h
        end

        _, h = W:Spacer(parent, y, 10)
        y = y - h

        -----------------------------------------------------------------------
        --  SHAMAN IMBUES & SHIELDS sub-section
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_SHAMAN, y)
        y = y - h
        _, h = SectionControlRow(parent, y, {
            whereStore = CSpecialWhere("SHAMAN"),
            whereTooltip = SPECIAL_WHERE_TIP,
            soundSec = CDB,
            specialClass = "SHAMAN",
            onChange = RefreshAll,
        })
        y = y - h

        do
            local gridItems = {}
            local IMBUES = _G._CUABR_SHAMAN_IMBUES or {}
            for _, imbue in ipairs(IMBUES) do
                gridItems[#gridItems + 1] = {
                    label = _G._CUABR_SpellName(imbue.castSpell, imbue.name),
                    classToken = "SHAMAN",
                    key = imbue.key,
                    getVal = function()
                        local c = CDB()
                        return c and c.enabled and c.enabled[imbue.key]
                    end,
                    setVal = function(v)
                        local c = CDB()
                        if c and c.enabled then
                            c.enabled[imbue.key] = v
                        end
                    end,
                }
            end
            local SHIELDS = _G._CUABR_SHAMAN_SHIELDS or {}
            for _, shield in ipairs(SHIELDS) do
                gridItems[#gridItems + 1] = {
                    label = CludesUI.L(shield.name),
                    classToken = "SHAMAN",
                    key = shield.key,
                    tooltip = shield.key == "es_ally"
                            and "Out of combat, reminds you when no groupmate has your Earth Shield (Elemental Orbit)."
                        or nil,
                    getVal = function()
                        local c = CDB()
                        return c and c.enabled and c.enabled[shield.key]
                    end,
                    setVal = function(v)
                        local c = CDB()
                        if c and c.enabled then
                            c.enabled[shield.key] = v
                        end
                    end,
                }
            end
            -- Earth Shield (Ally) turns group tracking on or off.
            h = BuildCheckboxGrid(parent, y, gridItems, function()
                if _G._CUABR_UpdateGroupAuraRegistration then
                    _G._CUABR_UpdateGroupAuraRegistration()
                end
                RefreshAll()
                RebuildPreviewHeader()
            end, _gridCellRefs)
            y = y - h
        end

        _, h = W:Spacer(parent, y, 10)
        y = y - h

        -----------------------------------------------------------------------
        --  PETS section
        -----------------------------------------------------------------------
        local petHdr
        petHdr, h = W:SectionHeader(parent, "PETS", y)
        y = y - h

        local petFirstRow
        petFirstRow, h = SectionControlRow(parent, y, {
            whereStore = CSpecialWhere("PET"),
            whereTooltip = "Pick which content the Missing Pet and Passive Pet reminders appear in.\nWarlock's Wrong Demon reminder uses the Where to Show in the Warlock section.\nRested areas (cities and inns) always stay hidden.",
            onChange = RefreshAll,
            rightCfg = {
                type = "toggle",
                text = "Missing Pet",
                tooltip = "Show a reminder when you don't have an active pet summoned. Only applies to pet classes (Hunter, Warlock, Death Knight, Mage).",
                getValue = function()
                    local c = CDB()
                    return c and c.enabled and c.enabled.pet ~= false
                end,
                setValue = function(v)
                    local c = CDB()
                    if c and c.enabled then
                        c.enabled.pet = v
                        RefreshAll()
                        RebuildPreviewHeader()
                    end
                end,
            },
        })
        y = y - h

        _, h = W:DualRow(parent, y, {
            type = "toggle",
            text = "Passive Pet",
            tooltip = "Show a reminder when your active pet is set to Passive stance. Only applies to pet classes (Hunter, Warlock, Death Knight, Mage).",
            getValue = function()
                local c = CDB()
                return c and c.enabled and c.enabled.pet_passive ~= false
            end,
            setValue = function(v)
                local c = CDB()
                if c and c.enabled then
                    c.enabled.pet_passive = v
                    RefreshAll()
                    RebuildPreviewHeader()
                end
            end,
        }, CludesUI.BlankRowCfg())
        y = y - h

        _eabrClickMappings.pet = { section = petHdr, target = petFirstRow }

        _, h = W:Spacer(parent, y, 10)
        y = y - h

        -----------------------------------------------------------------------
        --  WARLOCK section
        -----------------------------------------------------------------------
        local warlockHdr
        warlockHdr, h = W:SectionHeader(parent, SECTION_WARLOCK, y)
        y = y - h

        -- Where to Show | Allowed Demons, then Wrong Demon | Soulstone.
        local warlockCtrlRow
        warlockCtrlRow, h = SectionControlRow(parent, y, {
            whereStore = CWarlockWhere,
            whereTooltip = "Pick which content these Warlock reminders appear in.\nMissing Pet and Passive Pet use the Where to Show in the Pets section.\nRested areas (cities and inns) always stay hidden.",
            onChange = RefreshAll,
            rightCfg = {
                type = "dropdown",
                text = "Allowed Demons",
                tooltip = "Pick which demons count as correct for Wrong Demon. A demon only counts while its summon spell is known; with none picked (or everything picked), the reminder never fires.",
                values = { _placeholder = "..." },
                order = { "_placeholder" },
                getValue = function()
                    return "_placeholder"
                end,
                setValue = function() end,
            },
        })
        y = y - h

        local WARLOCK_PET_ITEMS = {}
        for _, pet in ipairs(_G._CUABR_WARLOCK_PETS or {}) do
            local unlearned = function()
                return not (_G._CUABR_Known and _G._CUABR_Known(pet.castSpell))
            end
            WARLOCK_PET_ITEMS[#WARLOCK_PET_ITEMS + 1] = {
                key = pet.key,
                label = pet.name,
                lockedFn = unlearned,
                excludeFromSummaryFn = unlearned,
                lockedTooltip = function()
                    local spellName = _G._CUABR_SpellName and _G._CUABR_SpellName(pet.castSpell, pet.name)
                        or pet.name
                    return CludesUI.Lf("You have not learned %1$s.", spellName)
                end,
            }
        end
        local warlockRow
        warlockRow, h = W:DualRow(parent, y, {
            type = "toggle",
            text = "Wrong Demon",
            tooltip = "Show a reminder when your Warlock's active pet isn't one of the demons picked in Allowed Demons. A demon only counts while its summon spell is known, so leaving only Felguard picked stays silent for specs/builds that haven't talented Summon Felguard.",
            getValue = function()
                local c = CDB()
                return c and c.enabled and c.enabled.wrong_pet ~= false
            end,
            setValue = function(v)
                local c = CDB()
                if c and c.enabled then
                    c.enabled.wrong_pet = v
                    RefreshAll()
                    RebuildPreviewHeader()
                end
            end,
        }, {
            type = "toggle",
            text = _G._CUABR_SpellName(20707, "Soulstone"),
            tooltip = "Show a reminder until your own Soulstone is active on you or another group member.",
            getValue = function()
                local a = ADB()
                return a and a.enabled and a.enabled.soulstone ~= false
            end,
            setValue = function(v)
                local a = ADB()
                if a and a.enabled then
                    a.enabled.soulstone = v
                end
                if _G._CUABR_UpdateGroupAuraRegistration then
                    _G._CUABR_UpdateGroupAuraRegistration()
                end
                RefreshAll()
                RebuildPreviewHeader()
            end,
        })
        y = y - h

        local wcc = RAID_CLASS_COLORS and RAID_CLASS_COLORS.WARLOCK
        if wcc then
            if warlockCtrlRow._rightRegion._label then
                warlockCtrlRow._rightRegion._label:SetTextColor(wcc.r, wcc.g, wcc.b, 1)
            end
            if warlockRow._leftRegion._label then
                warlockRow._leftRegion._label:SetTextColor(wcc.r, wcc.g, wcc.b, 1)
            end
            if warlockRow._rightRegion._label then
                warlockRow._rightRegion._label:SetTextColor(wcc.r, wcc.g, wcc.b, 1)
            end
        end

        if not CludesUI._prebuilding then
            local rrgn = warlockCtrlRow._rightRegion
            if rrgn._control then
                rrgn._control:Hide()
            end
            local petDD, petDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                rrgn,
                220,
                rrgn:GetFrameLevel() + 2,
                WARLOCK_PET_ITEMS,
                function(k)
                    local c = CDB()
                    return c and c.wrongPetAllowed and c.wrongPetAllowed[k]
                end,
                function(k, v)
                    local c = CDB()
                    if c then
                        c.wrongPetAllowed = c.wrongPetAllowed or {}
                        c.wrongPetAllowed[k] = v
                    end
                    RefreshAll()
                    RebuildPreviewHeader()
                end,
                nil,
                nil,
                nil,
                nil,
                nil,
                { emptyLabel = "All" }
            )
            PP.Point(petDD, "RIGHT", rrgn, "RIGHT", -20, 0)
            rrgn._control = petDD
            rrgn._lastInline = nil
            CludesUI.RegisterWidgetRefresh(petDDRefresh)
        end

        _eabrClickMappings.warlock_demons = { section = warlockHdr, target = warlockRow }

        _, h = W:Spacer(parent, y, 10)
        y = y - h

        -----------------------------------------------------------------------
        --  CONSUMABLES section
        -----------------------------------------------------------------------
        local consumHdr
        consumHdr, h = W:SectionHeader(parent, SECTION_CONSUMABLES, y)
        y = y - h

        -- Where to Show (+ reminder sound cog)
        _, h = SectionControlRow(parent, y, {
            whereStore = CWhere,
            whereTooltip = "Pick which content these consumable reminders appear in.\nRested areas (cities and inns) always stay hidden.",
            soundSec = CDB,
            soundField = "sectionSound",
            onChange = RefreshAll,
        })
        y = y - h

        -- Flask toggle | Preferred Click to Buff dropdown
        local consumFirstRow
        local flaskRow
        do
            local FLASK_ITEMS = _G._CUABR_FLASK_ITEMS or {}
            local flaskValues = { last_used = "Last Used" }
            local flaskOrder = { "last_used" }
            for _, f in ipairs(FLASK_ITEMS) do
                flaskValues[f.key] = f.name
                flaskOrder[#flaskOrder + 1] = f.key
            end
            flaskRow, h = W:DualRow(parent, y, {
                type = "toggle",
                text = "Flask",
                getValue = function()
                    local c = CDB()
                    return c and c.enabled and c.enabled.flask
                end,
                setValue = function(v)
                    local c = CDB()
                    if c and c.enabled then
                        c.enabled.flask = v
                        RefreshAll()
                        RebuildPreviewHeader()
                    end
                end,
            }, {
                type = "dropdown",
                text = "Preferred (Click to Buff)",
                dropdownWidth = 220,
                values = flaskValues,
                order = flaskOrder,
                getValue = function()
                    local c = CDB()
                    return c and c.preferredFlask or "last_used"
                end,
                setValue = function(v)
                    local c = CDB()
                    if c then
                        c.preferredFlask = v
                        RefreshAll()
                    end
                end,
            })
            y = y - h
            consumFirstRow = flaskRow
        end

        -- Food toggle | Preferred Click to Buff dropdown
        local foodRow
        do
            local FOOD_ITEMS = _G._CUABR_FOOD_ITEMS or {}
            local foodValues = { last_used = "Last Used" }
            local foodOrder = { "last_used" }
            for _, f in ipairs(FOOD_ITEMS) do
                foodValues[f.key] = f.name
                foodOrder[#foodOrder + 1] = f.key
            end
            foodRow, h = W:DualRow(parent, y, {
                type = "toggle",
                text = "Food",
                getValue = function()
                    local c = CDB()
                    return c and c.enabled and c.enabled.food
                end,
                setValue = function(v)
                    local c = CDB()
                    if c and c.enabled then
                        c.enabled.food = v
                        RefreshAll()
                        RebuildPreviewHeader()
                    end
                end,
            }, {
                type = "dropdown",
                text = "Preferred (Click to Buff)",
                dropdownWidth = 220,
                values = foodValues,
                order = foodOrder,
                getValue = function()
                    local c = CDB()
                    return c and c.preferredFood or "last_used"
                end,
                setValue = function(v)
                    local c = CDB()
                    if c then
                        c.preferredFood = v
                        RefreshAll()
                    end
                end,
            })
            y = y - h
        end

        -- Weapon Enhancement toggle | Preferred Click to Buff dropdown
        local weaponEnchantRow
        do
            local WE_CHOICES = _G._CUABR_WEAPON_ENCHANT_CHOICES or {}
            local weValues = { last_used = "Last Used" }
            local weOrder = { "last_used" }
            for _, we in ipairs(WE_CHOICES) do
                weValues[we.key] = we.name
                weOrder[#weOrder + 1] = we.key
            end
            weaponEnchantRow, h = W:DualRow(parent, y, {
                type = "toggle",
                text = "Weapon Enhancement",
                getValue = function()
                    local c = CDB()
                    return c and c.enabled and c.enabled.weapon_enchant
                end,
                setValue = function(v)
                    local c = CDB()
                    if c and c.enabled then
                        c.enabled.weapon_enchant = v
                        RefreshAll()
                        RebuildPreviewHeader()
                    end
                end,
            }, {
                type = "dropdown",
                text = "Preferred (Click to Buff)",
                dropdownWidth = 220,
                values = weValues,
                order = weOrder,
                getValue = function()
                    local c = CDB()
                    return c and c.preferredWeaponEnchant or "last_used"
                end,
                setValue = function(v)
                    local c = CDB()
                    if c then
                        c.preferredWeaponEnchant = v
                        RefreshAll()
                    end
                end,
            })
            y = y - h
        end

        -- Augment Rune | Healthstone (neither has a per-item control)
        local runeRow
        runeRow, h = W:DualRow(parent, y, {
            type = "toggle",
            text = "Augment Rune",
            getValue = function()
                local c = CDB()
                return c and c.enabled and c.enabled.augment_rune
            end,
            setValue = function(v)
                local c = CDB()
                if c and c.enabled then
                    c.enabled.augment_rune = v
                    RefreshAll()
                    RebuildPreviewHeader()
                end
            end,
        }, {
            type = "toggle",
            text = "Healthstone",
            tooltip = "Remind you to grab a Healthstone when a Warlock is in your group.",
            getValue = function()
                local c = CDB()
                return c and c.enabled and c.enabled.healthstone ~= false
            end,
            setValue = function(v)
                local c = CDB()
                if c and c.enabled then
                    c.enabled.healthstone = v
                    RefreshAll()
                    RebuildPreviewHeader()
                end
            end,
        })
        y = y - h
        local healthstoneRow = runeRow

        -- Inky Black Potion | Choose Zones (inline on the right)
        local inkyRow
        inkyRow, h = W:DualRow(parent, y, {
            type = "toggle",
            text = "Inky Black Potion",
            getValue = function()
                local c = CDB()
                return c and c.enabled and c.enabled.inky_black
            end,
            setValue = function(v)
                local c = CDB()
                if c and c.enabled then
                    c.enabled.inky_black = v
                    RefreshAll()
                    RebuildPreviewHeader()
                end
                CludesUI:RefreshPage()
            end,
        }, { type = "label", text = "" })
        y = y - h
        row = inkyRow

        -- Inline "Choose Zones" button on the right region (Inky Black)
        if not CludesUI._prebuilding then
            local rgn = row._rightRegion
            local eg = CludesUI.CLUDES_GREEN or { r = 0, g = 0.82, b = 0.62 }
            local lerp = CludesUI.lerp
            local DARK_BG = CludesUI.DARK_BG

            local zoneBtn = CreateFrame("Button", nil, rgn)
            zoneBtn:SetSize(110, 24)
            -- Anchored to the REGION edge, never the slot control: this slot
            -- is an empty label, and anchoring to it while the deferred label
            -- clamp anchors the label back to _lastInline forms an anchor
            -- family cycle (hard client error).
            zoneBtn:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
            zoneBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            rgn._lastInline = zoneBtn

            local zoneBg = CludesUI.SolidTex(zoneBtn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
            zoneBg:SetAllPoints()
            local zoneBrd = CludesUI.MakeRoundedBorder(zoneBtn, 1, 1, 1, 0.3, zoneBg)
            local zoneLbl = CludesUI.MakeFont(zoneBtn, 12, nil, 1, 1, 1)
            zoneLbl:SetPoint("CENTER")
            zoneLbl:SetText(CludesUI.L("Choose Zones"))

            -- Hover animation
            do
                local FADE_DUR = 0.1
                local progress, target = 0, 0
                local function Apply(t)
                    zoneLbl:SetTextColor(1, 1, 1, lerp(0.5, 0.8, t))
                    zoneBrd:SetColor(1, 1, 1, lerp(0.3, 0.5, t))
                end
                local function OnUpdate(self, elapsed)
                    local dir = (target == 1) and 1 or -1
                    progress = progress + dir * (elapsed / FADE_DUR)
                    if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                        progress = target
                        self:SetScript("OnUpdate", nil)
                    end
                    Apply(progress)
                end
                zoneBtn:SetScript("OnEnter", function(self)
                    target = 1
                    self:SetScript("OnUpdate", OnUpdate)
                end)
                zoneBtn:SetScript("OnLeave", function(self)
                    target = 0
                    self:SetScript("OnUpdate", OnUpdate)
                end)
            end

            zoneBtn:SetScript("OnClick", function()
                local c = CDB()
                local current = c and c.inkyBlackZones or ""
                CludesUI:ShowInputPopup({
                    title = "Inky Black Potion Zone IDs",
                    message = "Enter map zone IDs separated by commas.\nThe potion reminder will only show in these zones.",
                    placeholder = "e.g. 2248, 2339",
                    initialText = current,
                    maxLetters = 500,
                    confirmText = "Save",
                    extraButton = {
                        text = "Add Current Zone",
                        onClick = function(editBox)
                            local mapID = C_Map.GetBestMapForUnit("player")
                            if not mapID then
                                return
                            end
                            local txt = editBox:GetText() or ""
                            local idStr = tostring(mapID)
                            if txt == "" then
                                editBox:SetText(idStr)
                            else
                                editBox:SetText(txt .. ", " .. idStr)
                            end
                        end,
                    },
                    onConfirm = function(text)
                        local cc = CDB()
                        if cc then
                            cc.inkyBlackZones = text or ""
                            RefreshAll()
                        end
                    end,
                })
            end)

            -- Disabled overlay when Inky Black Potion is off
            local blockFrame = CreateFrame("Frame", nil, zoneBtn)
            blockFrame:SetAllPoints()
            blockFrame:SetFrameLevel(zoneBtn:GetFrameLevel() + 10)
            blockFrame:EnableMouse(true)
            blockFrame:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(zoneBtn, CludesUI.DisabledTooltip("Inky Black Potion"))
            end)
            blockFrame:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            local function UpdateZoneBtnDisabled()
                local c = CDB()
                local off = not c or not c.enabled or not c.enabled.inky_black
                if off then
                    zoneBtn:SetAlpha(0.3)
                    blockFrame:Show()
                else
                    zoneBtn:SetAlpha(1)
                    blockFrame:Hide()
                end
            end
            UpdateZoneBtnDisabled()
            CludesUI.RegisterWidgetRefresh(UpdateZoneBtnDisabled)
        end

        -- Show Without Item in Bags | Ready Check Mana Warning (eye | swatch | cog inline)
        row, h = W:DualRow(parent, y, {
            type = "toggle",
            text = "Show Without Item in Bags",
            tooltip = "When on, augment rune/flask/food/weapon reminders still show (dimmed) when you have no matching item in your bags, as a prompt to restock.\nWhen off, they are hidden entirely if you don't carry the item.",
            getValue = function()
                local c = CDB()
                return not c or c.showWithoutItem ~= false
            end,
            setValue = function(v)
                local c = CDB()
                if c then
                    c.showWithoutItem = v
                    RefreshAll()
                end
            end,
        }, {
            type = "toggle",
            text = "Ready Check Mana Warning",
            tooltip = "Flashes LOW MANA during an out-of-combat raid ready check while you are a healer under 80% mana.",
            getValue = function()
                local c = CDB()
                return not c or c.rcManaWarn ~= false
            end,
            setValue = function(v)
                local c = CDB()
                if c then
                    c.rcManaWarn = v
                end
                if not v and _G._CUABR_RCWarnHidePreview then
                    _G._CUABR_RCWarnHidePreview()
                end
                if _G._CUABR_RCWarnUpdateReg then
                    _G._CUABR_RCWarnUpdateReg()
                end
                CludesUI:RefreshPage()
            end,
        })
        y = y - h

        -- Inline: eyeball | color swatch | cog on the mana warning toggle
        if not CludesUI._prebuilding then
            local leftRgn = row._rightRegion
            local function rcwOff()
                local c = CDB()
                return c ~= nil and c.rcManaWarn == false
            end
            local rcwPreviewShown = false
            local RefreshRcwEye -- assigned below; cog offset sliders flip the eye on

            -- Cog (rightmost inline, closest to toggle): Text Size + X/Y Offset.
            -- Offset edits force the preview on (and light the eye) so the
            -- warning is visible while moving it.
            local function ShowPreviewFromCog()
                rcwPreviewShown = true
                if RefreshRcwEye then
                    RefreshRcwEye()
                end
                if _G._CUABR_RCWarnPreview then
                    _G._CUABR_RCWarnPreview()
                end
            end
            leftRgn._rcwFontValues, leftRgn._rcwFontOrder = CludesUI.BuildFontDropdownData()
            CludesUI.BuildInlineCog(leftRgn, {
                title = "Mana Warning Settings",
                disabled = rcwOff,
                disabledTooltip = "Ready Check Mana Warning",
                rows = {
                    {
                        type = "dropdown",
                        label = "Mana Warning Font",
                        values = leftRgn._rcwFontValues,
                        order = leftRgn._rcwFontOrder,
                        get = function()
                            local c = CDB()
                            return (c and c.rcManaWarnFont) or "__global"
                        end,
                        set = function(v)
                            local c = CDB()
                            if not c then
                                return
                            end
                            c.rcManaWarnFont = (v ~= "__global") and v or nil
                            if _G._CUABR_RCWarnApply then
                                _G._CUABR_RCWarnApply()
                            end
                            ShowPreviewFromCog()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 10,
                        max = 72,
                        step = 1,
                        get = function()
                            local c = CDB()
                            return c and c.rcManaWarnSize or 48
                        end,
                        set = function(v)
                            local c = CDB()
                            if not c then
                                return
                            end
                            c.rcManaWarnSize = v
                            if _G._CUABR_RCWarnApply then
                                _G._CUABR_RCWarnApply()
                            end
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -600,
                        max = 600,
                        step = 1,
                        get = function()
                            local c = CDB()
                            return c and c.rcManaWarnX or 0
                        end,
                        set = function(v)
                            local c = CDB()
                            if not c then
                                return
                            end
                            c.rcManaWarnX = v
                            ShowPreviewFromCog()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -600,
                        max = 600,
                        step = 1,
                        get = function()
                            local c = CDB()
                            return c and c.rcManaWarnY or 0
                        end,
                        set = function(v)
                            local c = CDB()
                            if not c then
                                return
                            end
                            c.rcManaWarnY = v
                            ShowPreviewFromCog()
                        end,
                    },
                },
            })

            -- Color swatch (left of the cog). Default shows the brightened
            -- mana color the warning uses when no custom is set.
            local swatch = CludesUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, function()
                local c = CDB()
                local col = c and c.rcManaWarnColor
                if col then
                    return col.r, col.g, col.b, 1
                end
                local mc = CludesUI.GetPowerColor("MANA")
                if mc then
                    return math.min(mc.r * 1.5, 1), math.min(mc.g * 1.5, 1), math.min(mc.b * 1.5, 1), 1
                end
                return 0, 0.825, 1, 1
            end, function(r, g, b)
                local c = CDB()
                if not c then
                    return
                end
                c.rcManaWarnColor = { r = r, g = g, b = b }
                if _G._CUABR_RCWarnApply then
                    _G._CUABR_RCWarnApply()
                end
            end, false, 20)
            swatch:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = swatch

            local swatchBlock = CreateFrame("Frame", nil, swatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            swatchBlock:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(swatch, CludesUI.DisabledTooltip("Ready Check Mana Warning"))
            end)
            swatchBlock:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            -- Eye icon toggles a live preview (left of the swatch)
            local EYE_VISIBLE = CludesUI.EYE_VISIBLE_ICON
            local EYE_INVISIBLE = CludesUI.EYE_INVISIBLE_ICON
            local eyeBtn = CreateFrame("Button", nil, leftRgn)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -8, 0)
            leftRgn._lastInline = eyeBtn
            eyeBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            CludesUI.SetGlyphAlpha(eyeBtn, 0.4)
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            RefreshRcwEye = function()
                eyeTex:SetTexture(rcwPreviewShown and EYE_INVISIBLE or EYE_VISIBLE)
            end
            RefreshRcwEye()
            eyeBtn:SetScript("OnEnter", function(self)
                CludesUI.SetGlyphAlpha(self, 0.7)
                CludesUI.ShowWidgetTooltip(self, "Preview mana warning")
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                CludesUI.HideWidgetTooltip()
                CludesUI.SetGlyphAlpha(self, 0.4)
            end)
            eyeBtn:SetScript("OnClick", function()
                rcwPreviewShown = not rcwPreviewShown
                RefreshRcwEye()
                if rcwPreviewShown then
                    if _G._CUABR_RCWarnPreview then
                        _G._CUABR_RCWarnPreview()
                    end
                else
                    if _G._CUABR_RCWarnHidePreview then
                        _G._CUABR_RCWarnHidePreview()
                    end
                end
            end)

            local eyeBlock = CreateFrame("Frame", nil, eyeBtn)
            eyeBlock:SetAllPoints()
            eyeBlock:SetFrameLevel(eyeBtn:GetFrameLevel() + 10)
            eyeBlock:EnableMouse(true)
            eyeBlock:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(eyeBtn, CludesUI.DisabledTooltip("Ready Check Mana Warning"))
            end)
            eyeBlock:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            -- Shared disabled-state refresh for all three inlines
            local function UpdateRcwInlinesDisabled()
                local off = rcwOff()
                if off then
                    rcwPreviewShown = false
                    RefreshRcwEye()
                    swatch:SetAlpha(0.3)
                    swatchBlock:Show()
                    CludesUI.SetGlyphAlpha(eyeBtn, 0.15)
                    eyeBlock:Show()
                else
                    swatch:SetAlpha(1)
                    swatchBlock:Hide()
                    CludesUI.SetGlyphAlpha(eyeBtn, 0.4)
                    eyeBlock:Hide()
                end
            end
            UpdateRcwInlinesDisabled()
            CludesUI.RegisterWidgetRefresh(UpdateRcwInlinesDisabled)
        end

        -- Wire up click mappings for preview hit overlays.
        wipe(_eabrClickMappings)
        _eabrClickMappings.display = { section = displaySection, target = borderRow }
        _eabrClickMappings.showText = { section = displaySection, target = rowText }
        _eabrClickMappings.raidbuff = { section = raidBufHdr, target = raidBufHdr }
        _eabrClickMappings.aura = { section = auraHdr, target = auraHdr }
        _eabrClickMappings.consumable = { section = consumHdr, target = consumFirstRow }
        _eabrClickMappings["item:soulstone"] = { section = warlockHdr, target = warlockRow }

        -- Per-item mappings: grid cells for individual raid buffs / auras
        for k, cell in pairs(_gridCellRefs) do
            _eabrClickMappings["item:" .. k] = { section = cell, target = cell }
        end
        -- Per-item mappings: consumable toggle rows
        if flaskRow then
            _eabrClickMappings["item:flask"] = { section = flaskRow, target = flaskRow }
        end
        if foodRow then
            _eabrClickMappings["item:food"] = { section = foodRow, target = foodRow }
        end
        if weaponEnchantRow then
            _eabrClickMappings["item:weapon_enchant"] =
                { section = weaponEnchantRow, target = weaponEnchantRow }
        end
        if runeRow then
            _eabrClickMappings["item:augment_rune"] = { section = runeRow, target = runeRow }
        end
        if healthstoneRow then
            _eabrClickMappings["item:healthstone"] = { section = healthstoneRow, target = healthstoneRow }
        end
        if inkyRow then
            _eabrClickMappings["item:inky_black"] = { section = inkyRow, target = inkyRow }
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Talent Reminders Page
    ---------------------------------------------------------------------------
    -- Owner of the page's kept popups (Pool.Kept): the zone popup and the
    -- talent popup are made once for the session, on UIParent.
    local _trPopups = {}

    local function BuildTalentRemindersPage(pageName, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h
        local fontPath = (CludesUI.GetFontPath("auraBuff"))
            or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

        parent._showRowDivider = true

        -- State for the add-reminder form
        local selectedZoneMap = {} -- [zoneIdx] = true/false
        local selectedTalentSpellID = nil
        local selectedTalentName = nil
        local selectedTalentSource = nil -- "class" or "spec"

        -- Zone data
        local zones = _G._CUABR_TALENT_REMINDER_ZONES or {}

        local zoneByName = {}
        for _, z in ipairs(zones) do
            if z.name then
                zoneByName[z.name] = z
            end
        end

        local function GetZoneDisplayName(zoneName)
            if not zoneName or zoneName == "" then
                return CludesUI.L("Unknown")
            end
            local z = zoneByName[zoneName]
            local name = CludesUI.L(zoneName)
            if z and z.type == "raid" then
                return name .. CludesUI.L(" (Raid)")
            end
            return name
        end

        -- Whether a reminder covers a zone. One saved with the single zone of
        -- an older version holds it in zoneName while it has no list.
        local function ReminderHasZone(r, zn)
            local list = r.zoneNames
            if list and #list > 0 then
                for i = 1, #list do
                    if list[i] == zn then
                        return true
                    end
                end
                return false
            end
            return r.zoneName == zn
        end
        -- A reminder's zone list for an edit; an older version's single zone
        -- moves into it on the first edit.
        local function EditableZoneList(r)
            local list = r.zoneNames
            if not list then
                list = {}
                r.zoneNames = list
            end
            if #list == 0 and r.zoneName then
                list[1] = r.zoneName
            end
            return list
        end

        -----------------------------------------------------------------------
        --  Talent enumeration helpers (live from C_Traits)
        -----------------------------------------------------------------------
        local function GetAllTalents()
            local talents = {}
            local configID = C_ClassTalents
                and C_ClassTalents.GetActiveConfigID
                and C_ClassTalents.GetActiveConfigID()
            if not configID then
                return talents
            end
            local configInfo = C_Traits and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
            if not configInfo or not configInfo.treeIDs or not configInfo.treeIDs[1] then
                return talents
            end
            local treeID = configInfo.treeIDs[1]
            local nodes = C_Traits.GetTreeNodes(treeID)
            if not nodes then
                return talents
            end

            local seenSpells = {}
            for _, nodeID in ipairs(nodes) do
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                if
                    nodeInfo
                    and nodeInfo.ID
                    and nodeInfo.ID > 0
                    and nodeInfo.entryIDs
                    and #nodeInfo.entryIDs > 0
                    and not nodeInfo.subTreeID
                then
                    for _, entryID in ipairs(nodeInfo.entryIDs) do
                        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
                        if entryInfo and entryInfo.definitionID then
                            local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                            if defInfo and defInfo.spellID and not seenSpells[defInfo.spellID] then
                                local spellName = C_Spell.GetSpellName(defInfo.spellID)
                                if spellName and spellName ~= "" then
                                    seenSpells[defInfo.spellID] = true
                                    talents[#talents + 1] = { spellID = defInfo.spellID, name = spellName }
                                end
                            end
                        end
                    end
                end
            end

            table.sort(talents, function(a, b)
                return a.name < b.name
            end)
            return talents
        end

        -----------------------------------------------------------------------
        --  SECTION: ADD REMINDER (no header clean layout)
        -----------------------------------------------------------------------

        -- Helper: build comma-separated zone label from selectedZoneMap
        local function GetSelectedZoneLabel()
            local names = {}
            for idx in pairs(selectedZoneMap) do
                if selectedZoneMap[idx] then
                    local z = zones[idx]
                    if z then
                        names[#names + 1] = GetZoneDisplayName(z.name)
                    end
                end
            end
            if #names == 0 then
                return "Select Dungeon/Raid/PvP Zone"
            end
            table.sort(names)
            return table.concat(names, ", ")
        end

        -- Wide centered zone dropdown (no label, multi-select checkbox popup)
        local CONTENT_PAD = 45
        local ZONE_DD_W = 350
        local ZONE_DD_H = 38
        y = y - 30 -- 30px space above dropdown
        local ZONE_ROW_H = ZONE_DD_H + 30
        local zoneRow = CreateFrame("Frame", nil, parent)
        local zoneRowW = parent:GetWidth() - CONTENT_PAD * 2
        PP.Size(zoneRow, zoneRowW, ZONE_ROW_H)
        PP.Point(zoneRow, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)

        local zoneDDBtn = CreateFrame("Button", nil, zoneRow)
        PP.Size(zoneDDBtn, ZONE_DD_W, ZONE_DD_H)
        PP.Point(zoneDDBtn, "TOP", zoneRow, "TOP", 0, 0)
        zoneDDBtn:SetFrameLevel(zoneRow:GetFrameLevel() + 1)
        local zoneDDBg = zoneDDBtn:CreateTexture(nil, "BACKGROUND")
        zoneDDBg:SetAllPoints()
        zoneDDBg:SetColorTexture(0.088, 0.098, 0.111, 0.9)
        CludesUI.MakeRoundedBorder(zoneDDBtn, 1, 1, 1, 0.20, zoneDDBg)

        local zoneDDLbl = zoneDDBtn:CreateFontString(nil, "OVERLAY")
        zoneDDLbl:SetFont(fontPath, 13, GetABROptOutline())
        zoneDDLbl:SetTextColor(1, 1, 1, 0.50)
        zoneDDLbl:SetMaxLines(1)
        zoneDDLbl:SetJustifyH("LEFT")
        zoneDDLbl:SetWordWrap(false)
        zoneDDLbl:SetText(CludesUI.L("Select Dungeon/Raid/PvP Zone"))

        local zoneArrow = CludesUI.MakeDropdownArrow(zoneDDBtn, 14, CludesUI.PanelPP)
        zoneDDLbl:SetPoint("LEFT", zoneDDBtn, "LEFT", 14, 0)
        zoneDDLbl:SetPoint("RIGHT", zoneArrow, "LEFT", -5, 0)

        -- Multi-select checkbox popup: one kept frame for the session that
        -- every build of the page dresses again. The global search's hidden
        -- pre-build makes none (the popup holds nothing to index).
        local SEARCH_H = 26
        local ITEM_H = 28
        if not CludesUI._prebuilding then
            local zonePopup = Pool.Kept(_trPopups, "zone", "Frame", UIParent)
            zonePopup:SetFrameStrata("FULLSCREEN_DIALOG")
            zonePopup:SetFrameLevel(200)
            zonePopup:SetClampedToScreen(true)
            local popupH = math.min(#zones * ITEM_H + 8, 300) + SEARCH_H + 10
            zonePopup:SetSize(ZONE_DD_W, popupH)
            zonePopup:Hide()

            local popupBg = zonePopup:CreateTexture(nil, "BACKGROUND")
            popupBg:SetAllPoints()
            popupBg:SetColorTexture(0.098, 0.090, 0.082, 0.97)
            CludesUI.MakeRoundedBorder(zonePopup, 1, 1, 1, 0.12, popupBg, nil, true)

            -- Search box at top of zone popup
            local zoneSearch = CreateFrame("EditBox", nil, zonePopup)
            zoneSearch:SetSize(ZONE_DD_W - 16, SEARCH_H)
            zoneSearch:SetPoint("TOP", zonePopup, "TOP", 0, -6)
            zoneSearch:SetFrameLevel(zonePopup:GetFrameLevel() + 3)
            zoneSearch:SetFont(fontPath, 11, "")
            zoneSearch:SetTextColor(1, 1, 1, 0.9)
            zoneSearch:SetJustifyH("LEFT")
            zoneSearch:SetAutoFocus(false)
            zoneSearch:SetMaxLetters(30)
            zoneSearch:SetTextInsets(4, 4, 0, 0)
            local zsBg = zoneSearch:CreateTexture(nil, "BACKGROUND")
            zsBg:SetAllPoints()
            zsBg:SetColorTexture(0, 0, 0, 0.4)
            CludesUI.RoundBody(zoneSearch, zsBg)
            local zsPlaceholder = zoneSearch:CreateFontString(nil, "OVERLAY")
            zsPlaceholder:SetFont(fontPath, 11, "")
            zsPlaceholder:SetTextColor(0.5, 0.5, 0.5, 0.6)
            zsPlaceholder:SetPoint("LEFT", zoneSearch, "LEFT", 4, 0)
            zsPlaceholder:SetText(CludesUI.L("Search..."))
            zoneSearch:SetScript("OnTextChanged", function(self)
                local t = self:GetText()
                zsPlaceholder:SetShown(t == "")
            end)
            zoneSearch:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
            end)

            -- Scroll frame for items with smooth scroll + scrollbar
            local sf = CreateFrame("ScrollFrame", nil, zonePopup)
            sf:SetPoint("TOPLEFT", zonePopup, "TOPLEFT", 0, -(SEARCH_H + 10))
            sf:SetPoint("BOTTOMRIGHT", zonePopup, "BOTTOMRIGHT", 0, 4)
            sf:SetFrameLevel(zonePopup:GetFrameLevel() + 1)
            sf:EnableMouseWheel(true)
            local child = CreateFrame("Frame", nil, sf)
            child:SetWidth(ZONE_DD_W)
            sf:SetScrollChild(child)

            local _, zScrollTo = CludesUI.AttachSmoothScrollbar(sf, {
                step = 40,
                thumbMin = 20,
                rightInset = 4,
                child = child,
            })
            zonePopup:SetScript("OnMouseWheel", function(_, delta)
                sf:GetScript("OnMouseWheel")(sf, delta)
            end)

            local eg = CludesUI.CLUDES_GREEN or { r = 0.298, g = 0.788, b = 0.941 }
            local checkItems = {}
            for i, z in ipairs(zones) do
                local item = CreateFrame("Button", nil, child)
                item:SetHeight(ITEM_H)
                item:SetPoint("TOPLEFT", child, "TOPLEFT", 1, -(i - 1) * ITEM_H)
                item:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, -(i - 1) * ITEM_H)

                local hl = item:CreateTexture(nil, "ARTWORK")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0)

                -- Checkbox square
                local cb = CreateFrame("Frame", nil, item)
                cb:SetSize(14, 14)
                cb:SetPoint("LEFT", item, "LEFT", 10, 0)
                local cbBg = cb:CreateTexture(nil, "BACKGROUND")
                cbBg:SetAllPoints()
                cbBg:SetColorTexture(0.064, 0.052, 0.041, 1)
                CludesUI.MakeRoundedBorder(cb, 1, 1, 1, 0.12, cbBg)
                local cbCheck = cb:CreateTexture(nil, "OVERLAY")
                cbCheck:SetSize(10, 10)
                cbCheck:SetPoint("CENTER")
                cbCheck:SetColorTexture(eg.r, eg.g, eg.b, 1)
                CludesUI.RoundBody(cb, cbCheck, 2)
                cbCheck:Hide()
                item._cbCheck = cbCheck

                local lbl = item:CreateFontString(nil, "OVERLAY")
                lbl:SetFont(fontPath, 11, GetABROptOutline())
                lbl:SetTextColor(0.75, 0.75, 0.78, 1)
                lbl:SetPoint("LEFT", cb, "RIGHT", 8, 0)
                lbl:SetPoint("RIGHT", item, "RIGHT", -8, 0)
                lbl:SetJustifyH("LEFT")
                lbl:SetWordWrap(false)
                lbl:SetText(GetZoneDisplayName(z.name))

                local function UpdateCheck()
                    cbCheck:SetShown(selectedZoneMap[i] == true)
                end
                UpdateCheck()

                item:SetScript("OnClick", function()
                    selectedZoneMap[i] = not selectedZoneMap[i]
                    UpdateCheck()
                    zoneDDLbl:SetText(GetSelectedZoneLabel())
                end)
                item:SetScript("OnEnter", function()
                    lbl:SetTextColor(1, 1, 1, 1)
                    hl:SetColorTexture(1, 1, 1, 0.08)
                end)
                item:SetScript("OnLeave", function()
                    lbl:SetTextColor(0.75, 0.75, 0.78, 1)
                    hl:SetColorTexture(1, 1, 1, 0)
                end)
                checkItems[i] = item
                item._zoneName = z.name
            end
            child:SetHeight(math.max(1, #zones * ITEM_H))

            -- Wire zone search filtering
            zoneSearch:SetScript("OnTextChanged", function(self)
                local t = strlower(strtrim(self:GetText()))
                zsPlaceholder:SetShown(t == "")
                local visIdx = 0
                for idx, item in ipairs(checkItems) do
                    if t == "" or strfind(strlower(item._zoneName), t, 1, true) then
                        item:Show()
                        item:ClearAllPoints()
                        item:SetPoint("TOPLEFT", child, "TOPLEFT", 1, -visIdx * ITEM_H)
                        item:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, -visIdx * ITEM_H)
                        visIdx = visIdx + 1
                    else
                        item:Hide()
                    end
                end
                child:SetHeight(math.max(1, visIdx * ITEM_H))
                zScrollTo(0)
            end)

            zonePopup:SetScript("OnShow", function()
                zonePopup:ClearAllPoints()
                zonePopup:SetPoint("TOPLEFT", zoneDDBtn, "BOTTOMLEFT", 0, -2)
                zoneSearch:SetText("")
                zoneSearch:SetFocus()
                zScrollTo(0)
                -- Refresh checks
                for i, item in ipairs(checkItems) do
                    item._cbCheck:SetShown(selectedZoneMap[i] == true)
                end
            end)
            -- Close when clicking outside
            zonePopup:SetScript("OnUpdate", function()
                if
                    not zonePopup:IsMouseOver()
                    and not zoneDDBtn:IsMouseOver()
                    and IsMouseButtonDown("LeftButton")
                then
                    zonePopup:Hide()
                end
            end)

            zoneDDBtn:SetScript("OnClick", function()
                if zonePopup:IsShown() then
                    zonePopup:Hide()
                else
                    zonePopup:Show()
                end
            end)
            -- The zone list closes with its page (rebuild, tab switch, panel
            -- close), as the talent list does.
            zoneDDBtn:SetScript("OnHide", function()
                zonePopup:Hide()
            end)
        end -- not prebuilding
        zoneDDBtn:SetScript("OnEnter", function()
            zoneDDBg:SetColorTexture(0.128, 0.120, 0.113, 1)
        end)
        zoneDDBtn:SetScript("OnLeave", function()
            zoneDDBg:SetColorTexture(0.088, 0.098, 0.111, 0.9)
        end)

        y = y - ZONE_ROW_H

        -- Row 2: Single talent dropdown
        local allTalents = GetAllTalents()

        -- Talent dropdown: single centered
        local TALENT_DD_W = 350
        local TALENT_DD_H = 30
        local TALENT_LABEL_H = 16
        local TALENT_GAP_Y = 6
        local TALENT_ROW_H = TALENT_LABEL_H + TALENT_GAP_Y + TALENT_DD_H + 12
        local talentRow = CreateFrame("Frame", nil, parent)
        local talentRowW = parent:GetWidth() - CONTENT_PAD * 2
        PP.Size(talentRow, talentRowW, TALENT_ROW_H)
        PP.Point(talentRow, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, y)

        local talentStartX = (talentRowW - TALENT_DD_W) / 2

        -- Helper: build a talent dropdown with search inside the popup
        local function MakeTalentDropdown(parentRow, xOff, labelText, allTalents)
            -- Label
            local lbl = parentRow:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(fontPath, 11, GetABROptOutline())
            lbl:SetTextColor(
                CludesUI.TEXT_SECTION_R or 0.45,
                CludesUI.TEXT_SECTION_G or 0.50,
                CludesUI.TEXT_SECTION_B or 0.55,
                CludesUI.TEXT_SECTION_A or 1
            )
            PP.Point(lbl, "TOP", parentRow, "TOPLEFT", xOff + TALENT_DD_W / 2, 0)
            lbl:SetText(CludesUI.L(labelText))

            -- Button (styled like zone dropdown)
            local btn = CreateFrame("Button", nil, parentRow)
            PP.Size(btn, TALENT_DD_W, TALENT_DD_H)
            PP.Point(btn, "TOPLEFT", parentRow, "TOPLEFT", xOff, -(TALENT_LABEL_H + TALENT_GAP_Y))
            btn:SetFrameLevel(parentRow:GetFrameLevel() + 1)
            local btnBg = btn:CreateTexture(nil, "BACKGROUND")
            btnBg:SetAllPoints()
            btnBg:SetColorTexture(0.088, 0.098, 0.111, 0.9)
            CludesUI.MakeRoundedBorder(btn, 1, 1, 1, 0.20, btnBg)
            local btnLbl = btn:CreateFontString(nil, "OVERLAY")
            btnLbl:SetFont(fontPath, 13, GetABROptOutline())
            btnLbl:SetTextColor(1, 1, 1, 0.50)
            btnLbl:SetMaxLines(1)
            btnLbl:SetJustifyH("LEFT")
            btnLbl:SetWordWrap(false)
            btnLbl:SetText(CludesUI.L("Select a talent..."))
            local arrow = CludesUI.MakeDropdownArrow(btn, 12, CludesUI.PanelPP)
            btnLbl:SetPoint("LEFT", btn, "LEFT", 12, 0)
            btnLbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)
            btn:SetScript("OnEnter", function()
                btnBg:SetColorTexture(0.128, 0.120, 0.113, 1)
            end)
            btn:SetScript("OnLeave", function()
                btnBg:SetColorTexture(0.088, 0.098, 0.111, 0.9)
            end)

            -- Popup with search: kept like the zone popup above (one per
            -- dropdown), and likewise not made by the global search's pre-build.
            if CludesUI._prebuilding then
                return btn, btnLbl
            end
            local T_ITEM_H = 26
            local popupH = math.min(#allTalents * T_ITEM_H + 8, 250) + SEARCH_H + 10
            local popup = Pool.Kept(_trPopups, "talent:" .. labelText, "Frame", UIParent)
            popup:SetFrameStrata("FULLSCREEN_DIALOG")
            popup:SetFrameLevel(200)
            popup:SetClampedToScreen(true)
            popup:SetSize(TALENT_DD_W, popupH)
            popup:Hide()
            local popBg = popup:CreateTexture(nil, "BACKGROUND")
            popBg:SetAllPoints()
            popBg:SetColorTexture(0.098, 0.090, 0.082, 0.97)
            CludesUI.MakeRoundedBorder(popup, 1, 1, 1, 0.12, popBg, nil, true)

            -- Search
            local search = CreateFrame("EditBox", nil, popup)
            search:SetSize(TALENT_DD_W - 16, SEARCH_H)
            search:SetPoint("TOP", popup, "TOP", 0, -6)
            search:SetFrameLevel(popup:GetFrameLevel() + 3)
            search:SetFont(fontPath, 11, "")
            search:SetTextColor(1, 1, 1, 0.9)
            search:SetJustifyH("LEFT")
            search:SetAutoFocus(false)
            search:SetMaxLetters(30)
            search:SetTextInsets(4, 4, 0, 0)
            local sBg = search:CreateTexture(nil, "BACKGROUND")
            sBg:SetAllPoints()
            sBg:SetColorTexture(0, 0, 0, 0.4)
            CludesUI.RoundBody(search, sBg)
            local sPh = search:CreateFontString(nil, "OVERLAY")
            sPh:SetFont(fontPath, 11, "")
            sPh:SetTextColor(0.5, 0.5, 0.5, 0.6)
            sPh:SetPoint("LEFT", search, "LEFT", 4, 0)
            sPh:SetText(CludesUI.L("Search..."))
            search:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
            end)

            -- Scroll frame
            local sf = CreateFrame("ScrollFrame", nil, popup)
            sf:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, -(SEARCH_H + 10))
            sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", 0, 4)
            sf:SetFrameLevel(popup:GetFrameLevel() + 1)
            sf:EnableMouseWheel(true)
            local child = CreateFrame("Frame", nil, sf)
            child:SetWidth(TALENT_DD_W)
            sf:SetScrollChild(child)

            -- Items
            local items = {}
            for i, t in ipairs(allTalents) do
                local item = CreateFrame("Button", nil, child)
                item:SetHeight(T_ITEM_H)
                item:SetPoint("TOPLEFT", child, "TOPLEFT", 1, -(i - 1) * T_ITEM_H)
                item:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, -(i - 1) * T_ITEM_H)
                local hl = item:CreateTexture(nil, "ARTWORK")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0)
                local iLbl = item:CreateFontString(nil, "OVERLAY")
                iLbl:SetFont(fontPath, 11, GetABROptOutline())
                iLbl:SetTextColor(0.75, 0.75, 0.78, 1)
                iLbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                iLbl:SetPoint("RIGHT", item, "RIGHT", -8, 0)
                iLbl:SetJustifyH("LEFT")
                iLbl:SetWordWrap(false)
                iLbl:SetText(t.name)
                item._lbl = iLbl
                item._talentName = t.name
                item._spellID = t.spellID
                item:SetScript("OnClick", function()
                    selectedTalentSpellID = t.spellID
                    selectedTalentName = t.name
                    selectedTalentSource = nil
                    btnLbl:SetText(t.name)
                    btnLbl:SetTextColor(1, 1, 1, 0.9)
                    popup:Hide()
                end)
                item:SetScript("OnEnter", function()
                    iLbl:SetTextColor(1, 1, 1, 1)
                    hl:SetColorTexture(1, 1, 1, 0.08)
                end)
                item:SetScript("OnLeave", function()
                    iLbl:SetTextColor(0.75, 0.75, 0.78, 1)
                    hl:SetColorTexture(1, 1, 1, 0)
                end)
                items[i] = item
            end
            child:SetHeight(math.max(1, #allTalents * T_ITEM_H))

            -- Search filter (tScrollTo is set by the scrollbar attached below)
            local tScrollTo
            search:SetScript("OnTextChanged", function(self)
                local t = strlower(strtrim(self:GetText()))
                sPh:SetShown(t == "")
                local visIdx = 0
                for _, item in ipairs(items) do
                    if t == "" or strfind(strlower(item._talentName), t, 1, true) then
                        item:Show()
                        item:ClearAllPoints()
                        item:SetPoint("TOPLEFT", child, "TOPLEFT", 1, -visIdx * T_ITEM_H)
                        item:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, -visIdx * T_ITEM_H)
                        visIdx = visIdx + 1
                    else
                        item:Hide()
                    end
                end
                child:SetHeight(math.max(1, visIdx * T_ITEM_H))
                tScrollTo(0)
            end)

            -- Scrollbar + smooth scroll
            local _
            _, tScrollTo = CludesUI.AttachSmoothScrollbar(sf, {
                step = 40,
                thumbMin = 20,
                rightInset = 4,
                child = child,
            })
            popup:SetScript("OnMouseWheel", function(_, delta)
                sf:GetScript("OnMouseWheel")(sf, delta)
            end)

            -- Show/hide. The talent icons are made on the first open, so the
            -- page build pays nothing for them.
            local iconsMade = false
            popup:SetScript("OnShow", function()
                popup:ClearAllPoints()
                popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
                if not iconsMade then
                    iconsMade = true
                    for _, item in ipairs(items) do
                        local ico = item:CreateTexture(nil, "ARTWORK", nil, 1)
                        ico:SetSize(18, 18)
                        ico:SetPoint("LEFT", item, "LEFT", 10, 0)
                        ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                        ico:SetTexture(C_Spell.GetSpellTexture(item._spellID) or 134400)
                        item._lbl:SetPoint("LEFT", ico, "RIGHT", 6, 0)
                    end
                end
                search:SetText("")
                search:SetFocus()
                tScrollTo(0)
            end)
            popup:SetScript("OnUpdate", function()
                if not popup:IsMouseOver() and not btn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                    popup:Hide()
                end
            end)
            btn:SetScript("OnClick", function()
                if popup:IsShown() then
                    popup:Hide()
                else
                    popup:Show()
                end
            end)
            btn:HookScript("OnHide", function()
                popup:Hide()
            end)

            return btn, btnLbl
        end

        -- Single talent dropdown
        local talentDDBtn, talentDDLbl =
            MakeTalentDropdown(talentRow, talentStartX, "Select Talent", allTalents)

        y = y - TALENT_ROW_H

        -- "Add Reminder" button (styled like Done button)
        _, h = W:Spacer(parent, y, 10)
        y = y - h

        local addBtnFrame = CreateFrame("Frame", nil, parent)
        PP.Size(addBtnFrame, parent:GetWidth() or 400, 36)
        PP.Point(addBtnFrame, "TOPLEFT", parent, "TOPLEFT", 0, y)

        local addBtn = CreateFrame("Button", nil, addBtnFrame)
        addBtn:SetSize(160, 36)
        addBtn:SetPoint("CENTER", addBtnFrame, "CENTER", 0, 0)

        local DARK_BG = CludesUI.DARK_BG
        local addBtnBg = CludesUI.SolidTex(addBtn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
        addBtnBg:SetAllPoints()

        local eg = CludesUI.CLUDES_GREEN or { r = 0.298, g = 0.788, b = 0.941 }
        local addBtnBorder = CludesUI.MakeRoundedBorder(addBtn, eg.r, eg.g, eg.b, 0.7, addBtnBg)

        local addBtnText = addBtn:CreateFontString(nil, "OVERLAY")
        addBtnText:SetPoint("CENTER")
        addBtnText:SetFont(fontPath, 13, GetABROptOutline())
        addBtnText:SetTextColor(eg.r, eg.g, eg.b, 0.7)
        addBtnText:SetText(CludesUI.L("Add Reminder"))

        do
            local lerp = CludesUI.lerp
            local FADE_DUR = 0.1
            local progress, target = 0, 0
            local function Apply(t)
                addBtnText:SetTextColor(eg.r, eg.g, eg.b, lerp(0.7, 1, t))
                addBtnBorder:SetColor(eg.r, eg.g, eg.b, lerp(0.7, 1, t))
            end
            local function OnUpdate(self, elapsed)
                local dir = (target == 1) and 1 or -1
                progress = progress + dir * (elapsed / FADE_DUR)
                if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                    progress = target
                    self:SetScript("OnUpdate", nil)
                end
                Apply(progress)
            end
            addBtn:SetScript("OnEnter", function(self)
                target = 1
                self:SetScript("OnUpdate", OnUpdate)
            end)
            addBtn:SetScript("OnLeave", function(self)
                target = 0
                self:SetScript("OnUpdate", OnUpdate)
            end)
        end

        y = y - 36

        -----------------------------------------------------------------------
        --  Red border pulse animation for validation
        -----------------------------------------------------------------------
        local pulseTarget = nil
        local pulseAG = nil

        local function PulseRedBorder(targetRow)
            if not targetRow then
                return
            end
            -- Create a red border overlay on the row
            if not targetRow._redPulse then
                local rf = CreateFrame("Frame", nil, targetRow)
                rf:SetAllPoints()
                rf:SetFrameLevel(targetRow:GetFrameLevel() + 10)
                local border = CludesUI.MakeBorder(rf, 1, 0.2, 0.2, 1, CludesUI.PanelPP)
                rf._border = border
                targetRow._redPulse = rf
            end
            local rf = targetRow._redPulse
            rf:Show()
            rf:SetAlpha(1)
            -- Fade out after 1.5 seconds
            local elapsed = 0
            rf:SetScript("OnUpdate", function(self, dt)
                elapsed = elapsed + dt
                if elapsed < 0.8 then
                    -- Pulse: oscillate alpha
                    local a = 0.5 + 0.5 * math.sin(elapsed * 10)
                    self:SetAlpha(a)
                elseif elapsed < 1.5 then
                    self:SetAlpha(math.max(0, 1 - (elapsed - 0.8) / 0.7))
                else
                    self:SetScript("OnUpdate", nil)
                    self:Hide()
                end
            end)
        end

        -----------------------------------------------------------------------
        --  Reminder list (dynamic, rebuilt on add/remove)
        -----------------------------------------------------------------------
        local listContainer = CreateFrame("Frame", nil, parent)
        listContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        listContainer:SetSize(parent:GetWidth() or 400, 1) -- height grows dynamically

        local listRows = {}
        local listRowCount = 0 -- manual alternating row counter

        -- Where a reminder's 'Not Needed' reminder shows (notNeededMode).
        local NOT_NEEDED_VALUES = {
            never = "Never",
            season = "Current Season Instances",
            all = "All Instances",
        }
        local NOT_NEEDED_ORDER = { "never", "season", "all" }
        -- Both dropdowns of a reminder row; wide enough for the longest zone name.
        local ROW_DD_W = 220
        -- The zone dropdowns' labels, in the picker's order.
        local zoneLabels = {}
        for i = 1, #zones do
            zoneLabels[i] = GetZoneDisplayName(zones[i].name)
        end

        local function RebuildReminderList()
            -- The global search's pre-build makes no rows: they hold nothing to index.
            if CludesUI._prebuilding then
                return 0
            end
            -- Clear existing rows. On a page pool host the rows go back to the
            -- container's pool and the list below dresses them again in order.
            Pool.Begin(listContainer)
            for _, row in ipairs(listRows) do
                row:Hide()
            end
            wipe(listRows)
            listRowCount = 0

            local p = DB()
            if not p then
                return 0
            end
            local reminders = p.talentReminders or {}

            -- Current-season filter: only reminders targeting at least one
            -- zone still on the picker list are shown. Rotated-out zones
            -- keep their stored reminders (hidden here, never deleted) --
            -- re-adding a zone to the season list revives them.
            local zoneSet = {}
            for _, z in ipairs(_G._CUABR_TALENT_REMINDER_ZONES or {}) do
                zoneSet[z.name] = true
            end
            local visible = {}
            for idx, reminder in ipairs(reminders) do
                local cur = false
                if reminder.zoneNames and #reminder.zoneNames > 0 then
                    for _, zn in ipairs(reminder.zoneNames) do
                        if zoneSet[zn] then
                            cur = true
                            break
                        end
                    end
                elseif reminder.zoneName and zoneSet[reminder.zoneName] then
                    cur = true
                end
                if cur then
                    visible[#visible + 1] = idx
                end
            end

            if #visible == 0 then
                listRowCount = listRowCount + 1
                local ROW_H = 50
                local CONTENT_PAD = 45
                local totalW = listContainer:GetWidth() - CONTENT_PAD * 2
                local emptyRow = CreateFrame("Frame", nil, listContainer)
                PP.Size(emptyRow, totalW, ROW_H)
                PP.Point(emptyRow, "TOPLEFT", listContainer, "TOPLEFT", CONTENT_PAD, 0)
                local alpha = (listRowCount % 2 == 0) and 0.2 or 0.1
                local bg = emptyRow:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0, 0, 0, alpha)
                local div = emptyRow:CreateTexture(nil, "ARTWORK")
                div:SetColorTexture(1, 1, 1, 0.06)
                div:SetWidth(1)
                PP.Point(div, "TOP", emptyRow, "TOP", 0, 0)
                PP.Point(div, "BOTTOM", emptyRow, "BOTTOM", 0, 0)
                local emptyFS = emptyRow:CreateFontString(nil, "OVERLAY")
                emptyFS:SetFont(fontPath, 13, GetABROptOutline())
                emptyFS:SetTextColor(0.5, 0.5, 0.5, 1)
                emptyFS:SetPoint("CENTER")
                emptyFS:SetText(CludesUI.L("No talent reminders configured"))
                emptyRow:Show()
                listRows[1] = emptyRow
                listContainer:SetHeight(ROW_H)
                return ROW_H
            end

            local ROW_H = 50
            local SIDE_PAD = 20
            local CONTENT_PAD = 45
            local totalW = listContainer:GetWidth() - CONTENT_PAD * 2
            local totalH = 0

            -- Helper: create a DualRow-styled frame
            local function MakeListRow(yOff)
                listRowCount = listRowCount + 1
                local row = CreateFrame("Frame", nil, listContainer)
                PP.Size(row, totalW, ROW_H)
                PP.Point(row, "TOPLEFT", listContainer, "TOPLEFT", CONTENT_PAD, yOff)
                -- Alternating row background
                local alpha = (listRowCount % 2 == 0) and 0.2 or 0.1
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0, 0, 0, alpha)
                -- Center divider
                local div = row:CreateTexture(nil, "ARTWORK")
                div:SetColorTexture(1, 1, 1, 0.06)
                div:SetWidth(1)
                PP.Point(div, "TOP", row, "TOP", 0, 0)
                PP.Point(div, "BOTTOM", row, "BOTTOM", 0, 0)
                return row
            end

            -- Data rows (single row per reminder)
            local Tex = function(id)
                return _G._CUABR_Tex and _G._CUABR_Tex(id)
                    or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id))
                    or 134400
            end
            for _, idx in ipairs(visible) do
                local reminder = reminders[idx]
                local row = MakeListRow(-totalH)
                local capturedIdx = idx
                local function ReminderAt()
                    local p2 = DB()
                    return p2 and p2.talentReminders and p2.talentReminders[capturedIdx]
                end

                -- === LEFT HALF: talent icon + name | its zones dropdown ===

                local spellIcon = row:CreateTexture(nil, "ARTWORK")
                spellIcon:SetSize(22, 22)
                spellIcon:SetPoint("LEFT", row, "LEFT", SIDE_PAD, 0)
                spellIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                spellIcon:SetTexture(Tex(reminder.spellID))

                local spellFS = row:CreateFontString(nil, "OVERLAY")
                spellFS:SetFont(fontPath, 14, GetABROptOutline())
                spellFS:SetTextColor(1, 1, 1, 1)
                spellFS:SetJustifyH("LEFT")
                spellFS:SetWordWrap(false)
                spellFS:SetMaxLines(1)
                spellFS:SetPoint("LEFT", spellIcon, "RIGHT", 8, 0)
                spellFS:SetText(reminder.spellName or CludesUI.L("Unknown"))

                -- The picker's zones for this reminder, with Delete Reminder
                -- pinned above them. Its last zone stays checked: a reminder
                -- always has one, and Delete Reminder removes it.
                local function ZoneCount(r)
                    local n = 0
                    for i = 1, #zones do
                        if ReminderHasZone(r, zones[i].name) then
                            n = n + 1
                        end
                    end
                    return n
                end
                local zoneItems = {
                    {
                        isTopAction = true,
                        label = "Delete Reminder",
                        onClick = function()
                            local p2 = DB()
                            if not (p2 and p2.talentReminders and p2.talentReminders[capturedIdx]) then
                                return
                            end
                            table.remove(p2.talentReminders, capturedIdx)
                            RebuildReminderList()
                            if _G._CUABR_TR_RequestRefresh then
                                _G._CUABR_TR_RequestRefresh()
                            end
                        end,
                    },
                }
                for i = 1, #zones do
                    local zn = zones[i].name
                    zoneItems[#zoneItems + 1] = {
                        key = zn,
                        label = zoneLabels[i],
                        lockedFn = function()
                            local r = ReminderAt()
                            return (r and ReminderHasZone(r, zn) and ZoneCount(r) <= 1) and true or false
                        end,
                        lockedTooltip = "A reminder needs at least one zone.",
                    }
                end
                local zoneDD = CludesUI.BuildVisOptsCBDropdown(
                    row,
                    ROW_DD_W,
                    row:GetFrameLevel() + 3,
                    zoneItems,
                    function(zn)
                        local r = ReminderAt()
                        return r and ReminderHasZone(r, zn) or false
                    end,
                    function(zn, on)
                        local r = ReminderAt()
                        if not r then
                            return
                        end
                        local list = EditableZoneList(r)
                        if on then
                            if not ReminderHasZone(r, zn) then
                                list[#list + 1] = zn
                                table.sort(list)
                            end
                        else
                            for i = #list, 1, -1 do
                                if list[i] == zn then
                                    table.remove(list, i)
                                end
                            end
                        end
                        if _G._CUABR_TR_RequestRefresh then
                            _G._CUABR_TR_RequestRefresh()
                        end
                    end,
                    nil,
                    10,
                    true,
                    false,
                    nil,
                    { noAllLabel = true, dimLocked = true }
                )
                PP.Point(zoneDD, "RIGHT", row, "CENTER", -SIDE_PAD, 0)
                spellFS:SetPoint("RIGHT", zoneDD, "LEFT", -12, 0)

                -- === RIGHT HALF: "Show 'Not Needed' Reminder" label + where-dropdown ===

                local toggleLabel = row:CreateFontString(nil, "OVERLAY")
                toggleLabel:SetFont(fontPath, 14, GetABROptOutline())
                toggleLabel:SetJustifyH("LEFT")
                toggleLabel:SetWordWrap(false)
                toggleLabel:SetMaxLines(1)
                toggleLabel:SetPoint("LEFT", row, "CENTER", SIDE_PAD, 0)
                toggleLabel:SetText(CludesUI.L("Show 'Not Needed' Reminder"))

                -- The runtime's own read of the choice: a reminder saved with the old
                -- checkbox reads on = Current Season Instances, off = Never.
                local function NotNeededOf()
                    local r, read = ReminderAt(), _G._CUABR_TR_NotNeededMode
                    return (r and read) and read(r) or "never"
                end
                -- The label dims while the reminder is off, as it did under the checkbox.
                local function PaintNotNeededLabel()
                    toggleLabel:SetTextColor(1, 1, 1, (NotNeededOf() == "never") and 0.4 or 1)
                end
                PaintNotNeededLabel()

                local notNeededDD = CludesUI.BuildDropdownControl(
                    row,
                    ROW_DD_W,
                    row:GetFrameLevel() + 3,
                    NOT_NEEDED_VALUES,
                    NOT_NEEDED_ORDER,
                    NotNeededOf,
                    function(v)
                        local r = ReminderAt()
                        if not r then
                            return
                        end
                        r.notNeededMode = v
                        -- The old checkbox key follows, for a profile an older version reads.
                        r.showNotNeeded = (v ~= "never")
                        PaintNotNeededLabel()
                        if _G._CUABR_TR_RequestRefresh then
                            _G._CUABR_TR_RequestRefresh()
                        end
                    end
                )
                PP.Point(notNeededDD, "RIGHT", row, "RIGHT", -SIDE_PAD, 0)
                notNeededDD._ttText =
                    "Reminds you to remove this talent in instances you did not pick for it."
                toggleLabel:SetPoint("RIGHT", notNeededDD, "LEFT", -12, 0)

                listRows[#listRows + 1] = row
                totalH = totalH + ROW_H
            end

            listContainer:SetHeight(totalH)
            return totalH
        end

        -- Add button click handler
        addBtn:SetScript("OnClick", function()
            -- Validate: must have at least one zone selected
            local hasZone = false
            for idx, sel in pairs(selectedZoneMap) do
                if sel then
                    hasZone = true
                    break
                end
            end
            if not hasZone then
                PulseRedBorder(zoneDDBtn)
                return
            end

            -- Validate: must have a talent selected
            if not selectedTalentSpellID or selectedTalentSpellID == 0 then
                PulseRedBorder(talentDDBtn)
                return
            end

            local p = DB()
            if not p then
                return
            end
            if not p.talentReminders then
                p.talentReminders = {}
            end

            -- Collect selected zone IDs and names
            local selZoneNames = {}
            for idx, sel in pairs(selectedZoneMap) do
                if sel then
                    local z = zones[idx]
                    if z then
                        selZoneNames[#selZoneNames + 1] = z.name
                    end
                end
            end
            table.sort(selZoneNames)

            -- Check for existing reminder with same spellID: merge zones
            for _, r in ipairs(p.talentReminders) do
                if r.spellID == selectedTalentSpellID then
                    -- Merge new zones into existing reminder
                    local list = EditableZoneList(r)
                    for _, zn in ipairs(selZoneNames) do
                        if not ReminderHasZone(r, zn) then
                            list[#list + 1] = zn
                        end
                    end
                    table.sort(list)
                    -- Reset selection
                    wipe(selectedZoneMap)
                    selectedTalentSpellID = nil
                    selectedTalentName = nil
                    selectedTalentSource = nil
                    zoneDDLbl:SetText(CludesUI.L("Select Dungeon/Raid/PvP Zone"))
                    if talentDDLbl then
                        talentDDLbl:SetText(CludesUI.L("Select a talent..."))
                        talentDDLbl:SetTextColor(1, 1, 1, 0.50)
                    end
                    RebuildReminderList()
                    if _G._CUABR_TR_RequestRefresh then
                        _G._CUABR_TR_RequestRefresh()
                    end
                    return
                end
            end

            local _, playerClass = UnitClass("player")
            p.talentReminders[#p.talentReminders + 1] = {
                zoneNames = selZoneNames,
                spellID = selectedTalentSpellID,
                spellName = selectedTalentName,
                notNeededMode = "never",
                showNotNeeded = false,
                class = playerClass,
            }

            -- Reset selection
            wipe(selectedZoneMap)
            selectedTalentSpellID = nil
            selectedTalentName = nil
            selectedTalentSource = nil
            zoneDDLbl:SetText(CludesUI.L("Select Dungeon/Raid/PvP Zone"))
            if talentDDLbl then
                talentDDLbl:SetText(CludesUI.L("Select a talent..."))
                talentDDLbl:SetTextColor(1, 1, 1, 0.50)
            end

            RebuildReminderList()
            if _G._CUABR_TR_RequestRefresh then
                _G._CUABR_TR_RequestRefresh()
            end
        end)

        -- Spacer before list
        _, h = W:Spacer(parent, y, 15)
        y = y - h

        -- Section header for the list
        _, h = W:SectionHeader(parent, "ACTIVE REMINDERS", y)
        y = y - h

        -- Position the list container
        listContainer:ClearAllPoints()
        listContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

        local listH = RebuildReminderList()
        y = y - listH

        _, h = W:Spacer(parent, y, 20)
        y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    CludesUI:RegisterModule("CludesUIAuraBuffReminders", {
        title = "Auras, Buffs & Consumables",
        description = "Buff Reminders: Raid Buffs, Auras, and Consumables.",
        pages = FOREVER and { PAGE_REMINDERS } or { PAGE_REMINDERS, PAGE_TALENTS },
        buildPage = function(pageName, parent, yOffset)
            if pageName == PAGE_REMINDERS then
                return BuildRemindersPage(pageName, parent, yOffset)
            elseif pageName == PAGE_TALENTS then
                return BuildTalentRemindersPage(pageName, parent, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_REMINDERS and not FOREVER then
                return _previewHeaderBuilder
            end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_REMINDERS and not FOREVER then
                UpdatePreviewHeader()
                -- Refresh hint visibility never recreate here, just show/hide
                local dismissed = IsPreviewHintDismissed()
                if _previewHintFS then
                    if dismissed then
                        _previewHintFS:Hide()
                    else
                        _previewHintFS:SetAlpha(0.45)
                        _previewHintFS:Show()
                    end
                end
                -- Set correct header height based on current hint state
                if _eabrHeaderBaseH > 0 then
                    CludesUI:SetContentHeaderHeightSilent(_eabrHeaderBaseH + (dismissed and 0 or 35))
                end
            end
        end,
        onShow = function()
            if _G._CUABR_HideAllIcons then
                _G._CUABR_HideAllIcons()
            end
        end,
        onHide = function()
            if _G._CUABR_RequestRefresh then
                _G._CUABR_RequestRefresh()
            end
        end,
        onReset = function()
            if _G._CUABR_AceDB then
                _G._CUABR_AceDB:ResetProfile()
            end
            if _G._CUABR_RequestRefresh then
                _G._CUABR_RequestRefresh()
            end
        end,
        -- Tears down the Ready Check Mana Warning preview on module switch.
        onModuleLeave = function()
            if _G._CUABR_RCWarnHidePreview then
                _G._CUABR_RCWarnHidePreview()
            end
        end,
    })

    -- Register unlock elements after a short delay
    C_Timer.After(0.5, function()
        if _G._CUABR_RegisterUnlock then
            _G._CUABR_RegisterUnlock()
        end
    end)

    ---------------------------------------------------------------------------
    --  Slash commands
    ---------------------------------------------------------------------------
    SLASH_EABR1 = "/cabr"
    SLASH_EABR2 = "/cbr"
    SlashCmdList.EABR = function()
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        CludesUI:ShowModule("CludesUIAuraBuffReminders")
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then
    initFrame:GetScript("OnEvent")(initFrame)
end
