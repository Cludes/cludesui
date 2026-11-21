if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_Nameplates_Options.lua: registers the Nameplates module with CludesUI.
--  All get/set calls go to ns.db.profile (centralized store); does NOT touch nameplate rendering logic.
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUINameplates"
local mod = CUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not mod then return end -- module disabled: no options page

-- The options page frame pool (CludesUI_FramePool.lua): frames made under a
-- pooled page or header part are handed back to its next build.
local CreateFrame = CUI._Pool.CreateFrame
local PoolGen, PoolKeep = CUI._Pool.Gen, CUI._Pool.Keep

-- Body-text preview flag, already slug-gated at the source (GetFontOutlineFlag).
local function GetNPOptOutline() return CUI.GetFontOutlineFlag("nameplates") end

-- Rows the Blizzard kit replaces but the classic plate leaves to the user
-- (bar background, cast bar texture, cast background and colours, the
-- border wrap): gated only while Blizzard Style renders, live under Classic
-- WoW UI. ns fields so the page builders gain no upvalue; the gate returns
-- cfg for inline use like BlizzStyle.Gate.
function mod.NP_BlizzOnly() return CUI.BlizzStyle.Active("nameplates") == "blizzard" end
function mod.NP_BlizzOnlyGate(rowConf)
    if mod.NP_BlizzOnly() then return CUI.BlizzStyle.Gate("nameplates", rowConf) end
    return rowConf
end

-------------------------------------------------------------------------------
--  Page / section names
-------------------------------------------------------------------------------
local PAGE_GENERAL = "General"
local PAGE_DISPLAY = "Display"
local PAGE_COLORS = "Colors"

local SECTION_FRIENDLY = "OTHER NAMEPLATES"
local SECTION_ENEMY_NP = "NAMEPLATE SPACING"
local SECTION_MISC = "EXTRAS"
local SECTION_AURA = "EXTRA AURA OPTIONS"

local SECTION_ENEMY = "ENEMY COLORS"
local SECTION_CASTBAR = "CAST COLORS AND EFFECTS"
local SECTION_THREAT = "THREAT COLORS"
local SECTION_OTHER = "OTHER COLORS"

-- Threat % Position dropdown (WoW Forever only, so nil on retail).
local THREAT_PCT_POSITIONS, THREAT_PCT_POSITION_ORDER
if CUI.IS_FOREVER then
    THREAT_PCT_POSITIONS = { RIGHT = "Inside Right", LEFT = "Inside Left", CENTER = "Inside Center" }
    THREAT_PCT_POSITION_ORDER = { "RIGHT", "LEFT", "CENTER" }
end

-- Wait for CludesUI to exist
CUI.AtOptionsLogin(function()
    local Pix = CUI.PanelPP

    ---------------------------------------------------------------------------
    --  Local references from the addon namespace
    ---------------------------------------------------------------------------
    local defaultSet = mod.defaults
    local SetFSFont = mod.SetFSFont
    local GetEnemyNameTextSize = mod.GetEnemyNameTextSize
    local GetDebuffTextColor = mod.GetDebuffTextColor
    local BAR_W = mod.BAR_W
    local plates = mod.plates
    local GetNPOutline = mod.GetNPOutline or function() return "OUTLINE, SLUG" end
    local GetNPUseShadow = mod.GetNPUseShadow or function() return false end

    local pcall = pcall
    local pairs = pairs

    -- Preview font setter: the plates' own font families (SetFSFont), so a
    -- preview name, title or cast target draws as on a live plate. Every font
    -- write to a preview text goes through it, never a plain SetFont.
    local function SetPVFont(fontStr, fontFile, size, flags)
        CUI.ApplyModuleFontFamily(fontStr, fontFile, size, "nameplates", flags)
    end
    local floor = math.floor
    local NAME_RAID_MARKER_GAP = 3

    ---------------------------------------------------------------------------
    --  DB helper reads from the centralized profile via ns.db
    ---------------------------------------------------------------------------
    local function PlatesProfile() return mod.db and mod.db.profile end

    local function DbValue(key)
        local saved = PlatesProfile()
        if saved and saved[key] ~= nil then return saved[key] end
        return defaultSet[key]
    end

    local function DBColor(key)
        local saved = PlatesProfile()
        local color = (saved and saved[key]) or defaultSet[key]
        return color.r, color.g, color.b
    end

    local FOCUS_LETTER_ANCHORS = {
        CENTER = "Center",
        LEFT = "Left",
        RIGHT = "Right",
        TOP = "Top",
        BOTTOM = "Bottom",
        TOPLEFT = "Top Left",
        TOPRIGHT = "Top Right",
        BOTTOMLEFT = "Bottom Left",
        BOTTOMRIGHT = "Bottom Right",
    }
    local FOCUS_LETTER_ANCHOR_ORDER = {
        "CENTER",
        "LEFT",
        "RIGHT",
        "TOP",
        "BOTTOM",
        "TOPLEFT",
        "TOPRIGHT",
        "BOTTOMLEFT",
        "BOTTOMRIGHT",
    }
    local function GetFocusLetterAnchor()
        local anchor = DbValue("focusLetterAnchor") or defaultSet.focusLetterAnchor
        return FOCUS_LETTER_ANCHORS[anchor] and anchor or defaultSet.focusLetterAnchor
    end

    ---------------------------------------------------------------------------
    --  Refresh helpers
    ---------------------------------------------------------------------------
    local function RedrawPlates()
        -- Color Casting Enemies repaints its tint colors (its swatches, Modify Out of Combat).
        if mod.NP_CastTintsDirty then mod.NP_CastTintsDirty() end
        for _, backing in pairs(plates) do
            backing:UpdateHealth()
        end
    end

    local function RefreshAllAuras()
        if mod.NPC_ReloadAll then mod.NPC_ReloadAll() end
    end

    ---------------------------------------------------------------------------
    --  Health bar texture dropdown values (built from ns tables)
    ---------------------------------------------------------------------------
    -- Append SharedMedia textures to the runtime ns tables first so both the dropdown AND the live nameplate rendering can resolve SM keys.
    CUI.AppendSharedMediaTextures(
        mod.healthBarTextureNames or {},
        mod.healthBarTextureOrder or {},
        nil,
        mod.healthBarTextures
    )

    local hbtValues = {}
    local hbtOrder = {}
    do
        local texNames = mod.healthBarTextureNames or {}
        local texOrder2 = mod.healthBarTextureOrder or {}
        for _, key in ipairs(texOrder2) do
            if key ~= "---" then hbtValues[key] = texNames[key] or key end
            hbtOrder[#hbtOrder + 1] = key
        end
        local texLookup = mod.healthBarTextures or {}
        hbtValues._menuOpts = {
            itemHeight = 28,
            background = function(key) return texLookup[key] end,
        }
    end

    ---------------------------------------------------------------------------
    --  Live Preview System: cosmetic-only enemy nameplate preview built once
    --  and updated via :Update() (no rebuild/GC pressure), reading live DB settings for colors, sizes, font, etc.
    ---------------------------------------------------------------------------
    -- Mutable state shared with the page builders under Nameplates_Options\.
    -- A table instead of locals so every file reads and writes the live value.
    -- Nil until set: activePreview (preview frame), _previewHintFS (hint
    -- FontString), RefreshCoreEyes (Display page), _colorPreviewRefreshAll
    -- (Colors page, refreshes all color preview bars on cache restore).
    local optionState = {}
    local _displayHeaderBuilder -- stored for page cache re-use
    local _headerBaseH = 0 -- header height WITHOUT hint (for cache restore)

    local function IsPreviewHintDismissed() return CludesUIDB and CludesUIDB.previewHintDismissed end

    -- Raid marker hidden by default, toggled via eye icon; optState fields so both the preview and the Display page can access them.
    optionState.showRaidMarkerPreview = false
    optionState.showClassificationPreview = false
    optionState.showQuestTextPreview = false
    optionState.showTargetGlowPreview = false
    optionState.showAbsorbPreview = false

    -- Transient flags: force-show indicators during slider drag
    optionState._sliderDragShowRaidMarker = false
    optionState._sliderDragShowClassification = false

    -- Random preview values regenerate only on tab switch, not on profile changes or setting tweaks (those trigger fast-path RefreshPage rebuilds).
    -- optState._previewHpPct, _previewCastFill, _previewCastIconIdx: set below.
    local displayCastIcons = { 136197, 236802, 135808, 136116, 135735, 136048, 135812, 136075 }
    local function RandomizePreviewValues()
        optionState._previewHpPct = math.floor(60 + math.random() * 15)
        optionState._previewCastFill = 0.40 + math.random() * 0.20
        optionState._previewCastIconIdx = math.random(#displayCastIcons)
    end

    -- Only while the preview is on screen: setters of other pages and the panel's
    -- show callback reach it from any page, and the Display page's cache restore
    -- updates it when it shows again.
    local function RepaintPreview()
        local preview = optionState.activePreview
        if preview and preview.Update and preview:IsVisible() then preview:Update() end
    end

    -- Refresh the preview every time the panel is reopened
    CUI:RegisterOnShow(RepaintPreview)

    ---------------------------------------------------------------------------
    --  Glow sites: the Dispel, Pandemic, Important Cast and Cast Targets You glows as shared glow
    --  descriptors, used by the page rows and the Global Settings Glows page.
    ---------------------------------------------------------------------------
    local npDispelGlowDesc, npImpCastGlowDesc, npPandemicGlowDesc, npCastTargetGlowDesc
    do
        local GO = CUI.GlowOptions
        -- The aura glows (Dispel, Pandemic) share one refresh, so the Glows
        -- page runs it once per Apply.
        local function RefreshAuraGlows()
            RefreshAllAuras()
            RepaintPreview()
        end
        -- Engine aura buttons (no Auto-Cast/Shape); an unset color is the
        -- suite default (gold).
        -- Blizzard Border: Blizzard's static stealable art, outside the view.
        local BLIZZ_BORDER = CUI.Glows.STEALABLE_BORDER
        -- Blizzard Pandemic Border: the Cooldown Manager's static pandemic
        -- art, outside the view, never tinted (noColor locks the swatches);
        -- the default of both aura glows.
        local PAN_BORDER = CUI.Glows.PANDEMIC_BORDER
        npDispelGlowDesc = {
            view = mod.NP_GLOW_VIEW,
            host = "engine",
            extras = {
                {
                    value = PAN_BORDER,
                    label = "Blizzard Pandemic Border",
                    style = PAN_BORDER,
                    noColor = true,
                },
                { value = BLIZZ_BORDER, label = "Blizzard Border", style = BLIZZ_BORDER },
            },
            caps = { mode = true, params = true, bg = true },
            defaultColor = CUI.Glows.DEFAULT_COLOR,
            isOff = function() return DbValue("dispelGlow") ~= true end,
            -- Color by Type replaces the swatch color on every group.
            colorDisabled = function() return DbValue("dispelGlowUseTypeColor") == true end,
            colorDisabledTooltip = "Color by Type (Magic/Enrage)",
            onChange = RefreshAuraGlows,
            get = function(f)
                local profile = PlatesProfile()
                if f == "style" then
                    return mod.GetDispelGlowStyle and mod.GetDispelGlowStyle() or defaultSet.dispelGlowStyle
                elseif f == "mode" then
                    return profile.dispelGlowColorMode or (profile.dispelGlowColor and "custom" or "default")
                end
                return CUI.GlowOptions.FlatGet(profile, "dispelGlow", f)
            end,
            set = function(f, a, b2, c2)
                local profile = PlatesProfile()
                if f == "style" then
                    if a == 0 then
                        profile.dispelGlow = false
                    else
                        profile.dispelGlow = true
                        profile.dispelGlowPick = a
                    end
                elseif f == "mode" then
                    profile.dispelGlowColorMode = a
                else
                    CUI.GlowOptions.FlatSet(profile, "dispelGlow", f, a, b2, c2)
                end
            end,
            -- Magic buffs and enrages are separate groups in the buff row, so the
            -- color can follow the type; it overrides the color above per group.
            cogRows = {
                {
                    type = "toggle",
                    label = "Color by Type (Magic/Enrage)",
                    get = function() return DbValue("dispelGlowUseTypeColor") or false end,
                    set = function(value)
                        PlatesProfile().dispelGlowUseTypeColor = value
                        RefreshAuraGlows()
                        CUI:RefreshPage()
                    end,
                },
            },
        }
        -- The cast bar glows (flat <prefix>* keys, on/off in <prefix>): the cast bar is a
        -- bar host (no Shape). An edit reaches the casts already showing.
        local function RefreshCastGlows()
            if mod.NP_RefreshCastGlows then mod.NP_RefreshCastGlows() end
        end
        local function CastBarGlowDesc(prefixText)
            local keyName = CUI.Glows.FlatKeys(prefixText)
            return {
                view = mod.NP_GLOW_VIEW,
                host = "bar",
                caps = { mode = true, params = true, bg = true },
                defaultColor = defaultSet[keyName.color],
                isOff = function() return DbValue(prefixText) ~= true end,
                onChange = RefreshCastGlows,
                get = function(f)
                    local profile = PlatesProfile()
                    if f == "style" then
                        return profile[keyName.style] or defaultSet[keyName.style] or 1
                    elseif f == "mode" then
                        return profile[keyName.mode] or "custom"
                    end
                    return GO.FlatGet(profile, prefixText, f, defaultSet)
                end,
                set = function(f, a, b2, c2)
                    local profile = PlatesProfile()
                    if f == "style" then
                        if a == 0 then
                            profile[prefixText] = false
                        else
                            profile[prefixText] = true
                            profile[keyName.style] = a
                        end
                    elseif f == "mode" then
                        profile[keyName.mode] = a
                    else
                        GO.FlatSet(profile, prefixText, f, a, b2, c2)
                    end
                end,
            }
        end
        npImpCastGlowDesc = CastBarGlowDesc("importantCastGlow")
        -- Casts targeting the player (off by default).
        npCastTargetGlowDesc = CastBarGlowDesc("castTargetGlow")
        -- Debuffs in their pandemic window (pandemicGlow* keys; the same mode
        -- key the CDM pandemic sync writes). An unset color mode is Custom:
        -- the swatch color this glow always drew (the profile merge fills it
        -- with the default gold).
        npPandemicGlowDesc = {
            view = mod.NP_GLOW_VIEW,
            host = "engine",
            extras = {
                {
                    value = PAN_BORDER,
                    label = "Blizzard Pandemic Border",
                    style = PAN_BORDER,
                    noColor = true,
                },
            },
            caps = { mode = true, params = true, bg = true },
            defaultColor = defaultSet.pandemicGlowColor,
            isOff = function() return DbValue("pandemicGlow") ~= true end,
            onChange = RefreshAuraGlows,
            get = function(f)
                local profile = PlatesProfile()
                if f == "style" then
                    return mod.GetPandemicGlowStyle()
                elseif f == "mode" then
                    return profile.pandemicGlowMode or "custom"
                end
                return CUI.GlowOptions.FlatGet(profile, "pandemicGlow", f, defaultSet)
            end,
            set = function(f, a, b2, c2)
                local profile = PlatesProfile()
                if f == "style" then
                    if a == 0 then
                        profile.pandemicGlow = false
                    else
                        profile.pandemicGlow = true
                        profile.pandemicGlowPick = a
                    end
                elseif f == "mode" then
                    profile.pandemicGlowMode = a
                else
                    CUI.GlowOptions.FlatSet(profile, "pandemicGlow", f, a, b2, c2)
                end
            end,
        }
        GO.RegisterSite({
            id = "np_dispel",
            label = "Dispel Glow",
            group = "module",
            module = "CludesUINameplates",
            page = PAGE_GENERAL,
            section = SECTION_AURA,
            highlight = "Dispel Glow Style",
            desc = npDispelGlowDesc,
        })
        GO.RegisterSite({
            id = "np_pandemic",
            label = "Pandemic Glow",
            group = "module",
            module = "CludesUINameplates",
            page = PAGE_GENERAL,
            section = SECTION_AURA,
            highlight = "Pandemic Glow Style",
            desc = npPandemicGlowDesc,
        })
        GO.RegisterSite({
            id = "np_importantcast",
            label = "Important Cast Glow",
            group = "module",
            module = "CludesUINameplates",
            page = PAGE_DISPLAY,
            section = SECTION_CASTBAR,
            highlight = "Important Cast Glow",
            desc = npImpCastGlowDesc,
        })
        GO.RegisterSite({
            id = "np_casttarget",
            label = "Cast Targets You Glow",
            group = "module",
            module = "CludesUINameplates",
            page = PAGE_DISPLAY,
            section = SECTION_CASTBAR,
            highlight = "Cast Targets You Glow",
            desc = npCastTargetGlowDesc,
        })
    end

    ---------------------------------------------------------------------------
    --  Display page  (preview in content header + settings in scroll area)
    ---------------------------------------------------------------------------
    local LazyColorPreviewBar -- forward declaration; defined with the Colors page helpers below

    local function BuildDisplayPage(pageName, hostFrame, yOffset)
        local W = CUI.Widgets
        local cursorY = yOffset
        local _, height

        -- Set content header with preview centered above nameplate preview
        _displayHeaderBuilder = function(headerParent, headerW)
            local PRESET_HEADER_H = 0
            local PREVIEW_TOP_PAD = 5
            local PREVIEW_BOTTOM_PAD = 5
            local previewH = mod.NPO_BuildNameplatePreview(headerParent, headerW)
            -- Position the preview at the top of the header area. pf's SetScale matches the UIParent/panel ratio, so SetPoint offsets (in that scaled space) must divide by the same ratio for the correct visual offset.
            if optionState.activePreview then
                optionState.activePreview:ClearAllPoints()
                local correction = UIParent:GetEffectiveScale() / headerParent:GetEffectiveScale()
                optionState.activePreview:SetPoint(
                    "TOP",
                    headerParent,
                    "TOP",
                    0,
                    -(PRESET_HEADER_H + PREVIEW_TOP_PAD) / correction
                )
                optionState.activePreview._headerExtra = PRESET_HEADER_H
                    + PREVIEW_TOP_PAD
                    + PREVIEW_BOTTOM_PAD
            end

            -- "Click elements" hint: parented to activePreview (not headerParent directly, which orphaned it via ClearContentHeaderInner on page switch) so the FontString travels through the content-header cache; if orphaned (parent gone), nil it to recreate.
            if optionState._previewHintFS and not optionState._previewHintFS:GetParent() then
                optionState._previewHintFS = nil
            end
            local hintShown = not IsPreviewHintDismissed()
            if hintShown then
                if not optionState._previewHintFS then
                    -- Held across builds: out of the preview's frame pool for good
                    -- (its later builds only hide it with the preview).
                    optionState._previewHintFS = PoolKeep(
                        CUI.MakeFont(optionState.activePreview or headerParent, 11, nil, 1, 1, 1)
                    )
                    optionState._previewHintFS:SetAlpha(0.45)
                    optionState._previewHintFS:SetText(
                        CUI.L("Click elements to scroll to and highlight their options")
                    )
                end
                optionState._previewHintFS:SetParent(optionState.activePreview or headerParent)
                optionState._previewHintFS:ClearAllPoints()
                optionState._previewHintFS:SetPoint("BOTTOM", headerParent, "BOTTOM", 0, 17)
                optionState._previewHintFS:SetAlpha(0.45)
                optionState._previewHintFS:Show()
            elseif optionState._previewHintFS then
                optionState._previewHintFS:Hide()
            end

            _headerBaseH = previewH + PRESET_HEADER_H + PREVIEW_TOP_PAD + PREVIEW_BOTTOM_PAD
            return _headerBaseH + (hintShown and 29 or 0)
        end
        CUI:SetContentHeader(_displayHeaderBuilder)

        -- Enable per-row center divider for the dual-column layout
        hostFrame._showRowDivider = true

        -----------------------------------------------------------------------
        --  AURA POSITIONS
        -----------------------------------------------------------------------
        local slotKeys =
            { "debuffSlot", "buffSlot", "ccSlot", "raidMarkerPos", "classificationSlot", "factionSlot" }

        -- Inverted mapping: position element (for CORE POSITIONS dropdowns)
        local elementToKey = {
            debuffs = "debuffSlot",
            buffs = "buffSlot",
            ccs = "ccSlot",
            raidmarker = "raidMarkerPos",
            classification = "classificationSlot",
            faction = "factionSlot",
        }
        local keyToElement = {}
        for elem, key in pairs(elementToKey) do
            keyToElement[key] = elem
        end

        local function GetElementAtPosition(place)
            local saved = PlatesProfile()
            for _, key in ipairs(slotKeys) do
                -- A leftover Faction slot is ignored while Rare/Quest + Faction is on
                -- (the badge rides the classification slot), so it is not shown here either.
                local ignored = key == "factionSlot" and saved.classificationIncludeFaction
                if not ignored and (saved[key] or defaultSet[key]) == place then
                    -- "Debuffs + CC" is a VIEW over the debuff slot: same position key + the debuffIncludeCC flag.
                    if key == "debuffSlot" and saved.debuffIncludeCC then return "debuffsccs" end
                    -- "Rare/Quest + Faction" is a VIEW over the classification slot + classificationIncludeFaction.
                    if key == "classificationSlot" and saved.classificationIncludeFaction then
                        return "classfaction"
                    end
                    return keyToElement[key]
                end
            end
            return "none"
        end

        local function SetElementAtPosition(place, element)
            -- The Quest Objective Text view reads the Rare/Quest slot and its Quest
            -- half: fix its own keys before either can move.
            mod.NP_MaterializeQuestText(PlatesProfile())
            if element == "none" then
                -- Clear: find whatever element is at this position and move it to "none"
                local saved = PlatesProfile()
                for _, key in ipairs(slotKeys) do
                    if (saved[key] or defaultSet[key]) == place then saved[key] = "none" end
                end
                if mod.NP_GetQuestTextSlot(saved) == place then saved.questTextSlot = "none" end
                return
            end
            -- "Debuffs + CC" rides the debuff slot key; the two entries differ only by debuffIncludeCC.
            if element == "debuffsccs" then
                PlatesProfile().debuffIncludeCC = true
                element = "debuffs"
            elseif element == "debuffs" then
                PlatesProfile().debuffIncludeCC = false
            end
            -- "Rare/Quest + Faction" rides the classification slot key and takes the
            -- faction badge with it (its own Faction slot is cleared); picking either
            -- one alone splits them again.
            if element == "classfaction" then
                PlatesProfile().classificationIncludeFaction = true
                PlatesProfile().factionSlot = "none"
                element = "classification"
            elseif element == "classification" or element == "faction" then
                PlatesProfile().classificationIncludeFaction = false
            end
            local key = elementToKey[element]
            if not key then return end
            local saved = PlatesProfile()
            -- Clear old holder of this position (set to "none"), no swapping
            for _, otherKey in ipairs(slotKeys) do
                if otherKey ~= key and (saved[otherKey] or defaultSet[otherKey]) == place then
                    saved[otherKey] = "none"
                end
            end
            saved[key] = place
        end

        local slotValues = {
            ["top"] = "Top",
            ["left"] = "Left",
            ["right"] = "Right",
            ["topleft"] = "Top Left",
            ["topright"] = "Top Right",
            ["bottom"] = "Bottom",
            ["none"] = "None",
        }
        local slotOrder = { "top", "left", "right", "topleft", "topright", "bottom", "none" }
        local function RefreshAllSlots()
            RefreshAllAuras()
            for _, backing in pairs(plates) do
                backing:UpdateRaidIcon()
                backing:UpdateClassification()
                -- Rare/Quest + Faction: the classification pass already ran it.
                if not DbValue("classificationIncludeFaction") then backing:UpdateFaction() end
                if mod.ApplySlotStrata then mod.ApplySlotStrata(backing) end
            end
            mod.NP_RefreshFriendlyFaction()
            RepaintPreview()
            CUI:RefreshPage()
        end

        -----------------------------------------------------------------------
        --  Helpers for position-swapping dropdowns
        -----------------------------------------------------------------------

        -- Exclusive slot assignment for the new Core Text Positions system.
        local textSlotKeys = mod.textSlotKeys
        local function SetTextElementAtSlot(slotKey, element)
            local saved = PlatesProfile()
            -- Custom keeps its template per slot: any number of slots may show it.
            if element ~= "none" and element ~= "custom" then
                for _, key in ipairs(textSlotKeys) do
                    if key ~= slotKey then
                        local current = saved[key] or defaultSet[key]
                        -- Name-family variants (name and the level+name combos) all render through the plate's single name FontString, so slotting any of
                        -- them evicts whichever family member occupies another slot -- same rule as an exact match. STANDALONE level has its own FontString and only exact-match evicts, so name + level can coexist.
                        if
                            current == element or (mod.IsNameElement(element) and mod.IsNameElement(current))
                        then
                            saved[key] = "none"
                        end
                    end
                end
            end
            saved[slotKey] = element
        end

        local timerPosValues = {
            ["topleft"] = "Top Left",
            ["center"] = "Center",
            ["topright"] = "Top Right",
            ["bottomleft"] = "Bottom Left",
            ["bottomright"] = "Bottom Right",
            ["none"] = "None",
        }
        local timerPosOrder = { "none", "topleft", "topright", "bottomleft", "bottomright", "center" }

        local function AuraDurationVal(kind, suffix)
            local saved = PlatesProfile()
            local key = kind .. "DurationText" .. suffix
            local oldKey = "auraDurationText" .. suffix
            if saved and saved[key] ~= nil then return saved[key] end
            if saved and saved[oldKey] ~= nil then return saved[oldKey] end
            return defaultSet[oldKey]
        end

        -- Aura duration and stack text draw through the aura containers' style
        -- pass, which a settings edit re-runs (fingerprint-guarded).
        local function LiveApplyAuraText()
            if mod.NPC_ReloadAll then mod.NPC_ReloadAll() end
        end

        local atFallback = DbValue("auraTextPosition") or defaultSet.auraTextPosition
        local asFallback = DbValue("auraStackTextPosition") or defaultSet.auraStackTextPosition

        -- The sections live in Nameplates_Options\DisplayLayout_Options.lua
        -- (which calls CoreTextColoring_Options.lua) and DisplayBars_Options.lua;
        -- they return the rows the click navigation below maps to.
        local context = {
            W = W,
            GetElementAtPosition = GetElementAtPosition,
            RefreshAllSlots = RefreshAllSlots,
            SetElementAtPosition = SetElementAtPosition,
            SetTextElementAtSlot = SetTextElementAtSlot,
            asFallback = asFallback,
            atFallback = atFallback,
            AuraDurationVal = AuraDurationVal,
            LiveApplyAuraText = LiveApplyAuraText,
            timerPosOrder = timerPosOrder,
            timerPosValues = timerPosValues,
        }
        local styleHeader, coreHeader, coreRow1, coreRow2, coreRow3, coreTextHeader, textSlotCells
        local textFirstRow
        cursorY, styleHeader, coreHeader, coreRow1, coreRow2, coreRow3, coreTextHeader, textSlotCells, textFirstRow, context.ShowCogPopup, context.CogPopupOpen, context.RefreshAllTextures =
            mod.NPO_BuildDisplayLayout(hostFrame, cursorY, context)
        local healthBarHeader, healthBarHeightRow, castBarHeightRow, showCastIconRow, castTimerRow
        local tfxHeader, targetGlowRow, classResourceHeader, classResourceSection, generalTextHeader
        local auraDurPosRow, auraTimerStackRow, spellNameRow
        cursorY, healthBarHeader, healthBarHeightRow, castBarHeightRow, showCastIconRow, castTimerRow, tfxHeader, targetGlowRow, classResourceHeader, classResourceSection, generalTextHeader, auraDurPosRow, auraTimerStackRow, spellNameRow =
            mod.NPO_BuildDisplayBars(hostFrame, cursorY, context)

        -- The search pre-build indexes rows only. The click navigation below
        -- rewires the live preview's hit overlays, which a hidden build of
        -- this page must leave alone.
        if CUI._prebuilding then return math.abs(cursorY) end

        -----------------------------------------------------------------------
        --  CLICK NAVIGATION: glow, scroll, mapping, hit overlays
        -----------------------------------------------------------------------
        local PlaySettingGlow = CUI.MakeSettingGlow({
            color = CUI.CLUDES_GREEN,
            thickness = function() return Pix.Scale(2) end,
            noSnap = true,
        })

        -- Maps Core Text Position slot keys to their row/region (the cells of
        -- the texts the list shows)
        local textSlotToRow = textSlotCells

        -- Reverse lookup: find which Core Position slot holds a given element
        local function FindCorePosForElement(element)
            local saved = PlatesProfile()
            local key = elementToKey[element]
            if not key then return nil end
            local place = saved[key] or defaultSet[key]
            if place == "none" then return nil end
            return place
        end

        -- Reverse lookup: find which text slot holds a given element
        local function FindTextSlotForElement(element)
            local saved = PlatesProfile()
            for _, key in ipairs(textSlotKeys) do
                if (saved[key] or defaultSet[key]) == element then return key end
            end
            return nil
        end

        -- Resolve a dynamic click mapping to the Core Positions row of a position
        -- (the first row while the element sits in none)
        local function ResolveCorePos(place)
            if not place or place == "none" then return { section = coreHeader, target = coreRow1 } end
            local details = context.corePosToRegion[place]
            if not details then return { section = coreHeader, target = coreRow1 } end
            return {
                section = coreHeader,
                target = details[1],
                slotSide = (details[2] == "_leftRegion") and "left" or "right",
            }
        end
        -- The same for the slot holding an icon element
        local function ResolveCoreMapping(element) return ResolveCorePos(FindCorePosForElement(element)) end

        local clickMappings = {
            debuffDuration = { section = generalTextHeader, target = auraDurPosRow, slotSide = "left" },
            buffDuration = { section = generalTextHeader, target = auraDurPosRow, slotSide = "right" },
            ccDuration = { section = generalTextHeader, target = auraTimerStackRow, slotSide = "left" },
            auraStack = { section = generalTextHeader, target = auraTimerStackRow, slotSide = "right" },
            castBar = { section = healthBarHeader, target = castBarHeightRow, slotSide = "left" },
            castIcon = { section = healthBarHeader, target = showCastIconRow, slotSide = "right" },
            castTimer = { section = healthBarHeader, target = castTimerRow, slotSide = "left" },
            castName = { section = generalTextHeader, target = spellNameRow, slotSide = "left" },
            castTarget = { section = generalTextHeader, target = spellNameRow, slotSide = "right" },
            healthBar = { section = healthBarHeader, target = healthBarHeightRow },
            classResource = { section = classResourceHeader, target = classResourceSection },
            targetArrows = {
                section = tfxHeader,
                target = targetGlowRow,
                slotSide = "right",
            },
        }

        -- Dynamic resolvers for elements assigned to Core Positions / Core Text Positions
        local dynamicMappings = {
            -- Classic WoW UI: the level in the health border's plate. Its row
            -- exists only on that style, so this resolves to nothing elsewhere.
            classicLevel = function()
                local row = hostFrame._classicPlateRow
                if not row then return nil end
                return { section = styleHeader, target = row, slotSide = "left" }
            end,
            -- WoW Forever: the level box, whose row exists only under that
            -- variant.
            foreverLevelBox = function()
                local row = hostFrame._foreverBoxRow
                if not row then return nil end
                return { section = styleHeader, target = row, slotSide = "left" }
            end,
            debuffIcon = function() return ResolveCoreMapping("debuffs") end,
            buffIcon = function() return ResolveCoreMapping("buffs") end,
            ccIcon = function() return ResolveCoreMapping("ccs") end,
            raidMarker = function() return ResolveCoreMapping("raidmarker") end,
            classIcon = function() return ResolveCoreMapping("classification") end,
            -- The Quest Objective Text's effective slot.
            questText = function() return ResolveCorePos(mod.NP_GetQuestTextSlot(PlatesProfile())) end,
            -- Combined with Rare/Quest, the badge's settings live on that row.
            factionIcon = function()
                if PlatesProfile().classificationIncludeFaction then
                    return ResolveCoreMapping("classification")
                end
                return ResolveCoreMapping("faction")
            end,
            enemyName = function()
                -- The name FontString renders whichever name-family variant is slotted; resolve the row for any of them.
                local slot = FindTextSlotForElement("enemyName")
                    or FindTextSlotForElement("levelName")
                    or FindTextSlotForElement("nameLevel")
                if not slot then return { section = coreTextHeader, target = textFirstRow } end
                local details = textSlotToRow[slot]
                if not details then return { section = coreTextHeader, target = textFirstRow } end
                return {
                    section = coreTextHeader,
                    target = details.row,
                    slotSide = (details.side == "_leftRegion") and "left" or "right",
                }
            end,
            healthText = function()
                local slot = FindTextSlotForElement("healthPercent")
                    or FindTextSlotForElement("healthPercentNoSign")
                    or FindTextSlotForElement("healthPctNum")
                    or FindTextSlotForElement("healthNumPct")
                    or FindTextSlotForElement("healthPctNumDash")
                    or FindTextSlotForElement("healthNumPctDash")
                if not slot then return { section = coreTextHeader, target = textFirstRow } end
                local details = textSlotToRow[slot]
                if not details then return { section = coreTextHeader, target = textFirstRow } end
                return {
                    section = coreTextHeader,
                    target = details.row,
                    slotSide = (details.side == "_leftRegion") and "left" or "right",
                }
            end,
        }
        -- Custom texts: each position's own font string, that position's row.
        for _, slotKey in ipairs(mod.textSlotKeys) do
            dynamicMappings["custom_" .. slotKey] = function()
                local details = textSlotToRow[slotKey]
                if not details then return { section = coreTextHeader, target = textFirstRow } end
                return {
                    section = coreTextHeader,
                    target = details.row,
                    slotSide = (details.side == "_leftRegion") and "left" or "right",
                }
            end
        end
        -- The font strings a single element owns: the row of the slot showing it.
        for mapKey, element in pairs({
            healthNumber = "healthNumber",
            levelText = "level",
            targetOfTarget = "targetOfTarget",
        }) do
            dynamicMappings[mapKey] = function()
                local details = textSlotToRow[FindTextSlotForElement(element) or ""]
                if not details then return { section = coreTextHeader, target = textFirstRow } end
                return {
                    section = coreTextHeader,
                    target = details.row,
                    slotSide = (details.side == "_leftRegion") and "left" or "right",
                }
            end
        end

        local function NavigateToSetting(key)
            local m = clickMappings[key]
            -- Check dynamic mappings (icon/text elements assigned to Core Positions)
            if not m then
                local resolver = dynamicMappings[key]
                if resolver then m = resolver() end
            end
            if not m or not m.section or not m.target then return end

            -- Header grows by 29 but shrinks by 39 (kept as shipped).
            CUI.DismissPreviewHint(optionState._previewHintFS, _headerBaseH, 29, 17)

            local scrollFrame = CUI._scrollFrame
            if not scrollFrame then return end
            local _, _, _, _, headerY = m.section:GetPoint(1)
            if not headerY then return end
            local scrollPos = math.max(0, math.abs(headerY) - 40)
            CUI.SmoothScrollTo(scrollPos)
            local glowTarget = m.target
            if m.slotSide and m.target then
                local regionFrame = (m.slotSide == "left") and m.target._leftRegion or m.target._rightRegion
                if regionFrame then glowTarget = regionFrame end
            end
            -- A page built again before the glow plays dressed the row anew: no glow.
            local glowGen = PoolGen(glowTarget)
            C_Timer.After(0.15, function()
                if PoolGen(glowTarget) ~= glowGen then return end
                PlaySettingGlow(glowTarget)
            end)
        end

        -- Hit overlay factory for preview elements. opts (optional): hlAnchor = frame to draw the highlight around (instead of btn); hlBehindText = true draws it on a child frame at icon level+1 (text lives at icon level+2).
        local function SnapPreview(val)
            local s = optionState.activePreview and optionState.activePreview:GetEffectiveScale() or 1
            if s <= 0 then s = 1 end
            return math.floor(val * s + 0.5) / s
        end
        -- Every build of this page runs right after its header built the preview
        -- again (the SetContentHeader call above), so the overlays below go on a
        -- preview that has none: a new one, or (page reuse) the same frames dressed
        -- again with their overlays parked by the preview's pool.
        local hitStyle = { container = true }
        local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, options)
            local button = CUI.CreatePreviewHitOverlay(
                element,
                NavigateToSetting,
                mappingKey,
                isText,
                frameLevelOverride,
                options,
                hitStyle
            )
            return button
        end

        -- Create hit overlays for all interactive preview elements
        local textOverlays = {} -- collect text overlays for size refresh
        if optionState.activePreview then
            local preview = optionState.activePreview
            -- Icon overlays need to be above the icon frames (health:GetFrameLevel() + 9, or + 13 with Raise Strata)
            local iconLevel = (preview._health and preview._health:GetFrameLevel() or 20) + 15
            -- Text overlays on icons need to be above the icon overlays
            local textOnIconLevel = iconLevel + 10
            -- Aura icons (all debuffs, buffs, ccs)
            local iconHlOpts = { hlBehindText = true }
            if preview._ccs then
                for i = 1, #preview._ccs do
                    if preview._ccs[i] then
                        CreateHitOverlay(preview._ccs[i], "ccIcon", false, iconLevel, iconHlOpts)
                        if preview._ccs[i].durationText then
                            local shade = CreateHitOverlay(
                                preview._ccs[i].durationText,
                                "ccDuration",
                                true,
                                textOnIconLevel
                            )
                            textOverlays[#textOverlays + 1] = shade
                        end
                    end
                end
            end
            if preview._buffs then
                for i = 1, #preview._buffs do
                    if preview._buffs[i] then
                        CreateHitOverlay(preview._buffs[i], "buffIcon", false, iconLevel, iconHlOpts)
                        if preview._buffs[i].durationText then
                            local shade = CreateHitOverlay(
                                preview._buffs[i].durationText,
                                "buffDuration",
                                true,
                                textOnIconLevel
                            )
                            textOverlays[#textOverlays + 1] = shade
                        end
                    end
                end
            end
            if preview._debuffs then
                for i = 1, #preview._debuffs do
                    if preview._debuffs[i] then
                        CreateHitOverlay(preview._debuffs[i], "debuffIcon", false, iconLevel, iconHlOpts)
                        if preview._debuffs[i].durationText then
                            local shade = CreateHitOverlay(
                                preview._debuffs[i].durationText,
                                "debuffDuration",
                                true,
                                textOnIconLevel
                            )
                            textOverlays[#textOverlays + 1] = shade
                        end
                        if preview._debuffs[i].stackText then
                            local shade = CreateHitOverlay(
                                preview._debuffs[i].stackText,
                                "auraStack",
                                true,
                                textOnIconLevel
                            )
                            textOverlays[#textOverlays + 1] = shade
                        end
                    end
                end
            end
            -- Cast icon overlay (separate from cast bar navigates to Show Spell Icon row)
            local castOverlayLevel
            if preview._cast then
                castOverlayLevel = preview._cast:GetFrameLevel() + 20
                local classColor = CUI.CLUDES_GREEN
                -- Cast icon overlay
                if preview._castIconFrame then
                    local iconOv = CreateFrame("Button", nil, preview._cast:GetParent())
                    iconOv:SetAllPoints(preview._castIconFrame)
                    iconOv:SetFrameLevel(castOverlayLevel)
                    iconOv:RegisterForClicks("LeftButtonDown")
                    local ioBrd = CUI.PP.CreateBorder(
                        iconOv,
                        classColor.r,
                        classColor.g,
                        classColor.b,
                        1,
                        2,
                        "OVERLAY",
                        7
                    )
                    ioBrd:Hide()
                    iconOv:SetScript("OnEnter", function() ioBrd:Show() end)
                    iconOv:SetScript("OnLeave", function() ioBrd:Hide() end)
                    iconOv:SetScript("OnMouseDown", function() NavigateToSetting("castIcon") end)
                end
                -- Cast bar overlay (bar only, not icon)
                local castOverlay = CreateFrame("Button", nil, preview._cast:GetParent())
                castOverlay:SetAllPoints(preview._cast)
                castOverlay:SetFrameLevel(castOverlayLevel)
                castOverlay:RegisterForClicks("LeftButtonDown")
                local coBrd = CUI.PP.CreateBorder(
                    castOverlay,
                    classColor.r,
                    classColor.g,
                    classColor.b,
                    1,
                    2,
                    "OVERLAY",
                    7
                )
                coBrd:Hide()
                castOverlay:SetScript("OnEnter", function() coBrd:Show() end)
                castOverlay:SetScript("OnLeave", function() coBrd:Hide() end)
                castOverlay:SetScript("OnMouseDown", function() NavigateToSetting("castBar") end)
            end
            -- Cast spell name and target text (above the cast bar overlay)
            local castTextLevel = (castOverlayLevel or 30) + 5
            if preview._castNameFS and preview._castNameFS:IsShown() then
                local shade = CreateHitOverlay(preview._castNameFS, "castName", true, castTextLevel)
                textOverlays[#textOverlays + 1] = shade
            end
            if preview._castTargetFS and preview._castTargetFS:IsShown() then
                local shade = CreateHitOverlay(preview._castTargetFS, "castTarget", true, castTextLevel)
                textOverlays[#textOverlays + 1] = shade
            end
            if preview._castTimerFS and preview._castTimerFS:IsShown() then
                local shade = CreateHitOverlay(preview._castTimerFS, "castTimer", true, castTextLevel)
                textOverlays[#textOverlays + 1] = shade
            end
            -- Enemy name text
            if preview._nameFS then
                local shade = CreateHitOverlay(preview._nameFS, "enemyName", true)
                textOverlays[#textOverlays + 1] = shade
            end
            -- Health text
            if preview._hpText then
                local shade = CreateHitOverlay(preview._hpText, "healthText", true)
                textOverlays[#textOverlays + 1] = shade
            end
            -- Health #, standalone level and Target of Target: each on its own font
            -- string, shown only while a slot holds it, so the overlay follows the
            -- text's shown state (_syncFS, re-read on every preview update).
            for fsKey, mapKey in pairs({
                _hpNumber = "healthNumber",
                _lvlText = "levelText",
                _totFS = "targetOfTarget",
            }) do
                local fontStr = preview[fsKey]
                if fontStr then
                    local shade = CreateHitOverlay(fontStr, mapKey, true)
                    shade._syncFS = fontStr
                    shade:SetShown(fontStr:IsShown())
                    textOverlays[#textOverlays + 1] = shade
                end
            end
            -- Custom texts: one font string per position, shown while it holds one.
            if preview._customFS then
                for slotKey, fontStr in pairs(preview._customFS) do
                    local shade = CreateHitOverlay(fontStr, "custom_" .. slotKey, true)
                    shade._syncFS = fontStr
                    shade:SetShown(fontStr:IsShown())
                    textOverlays[#textOverlays + 1] = shade
                end
            end
            -- Classic WoW UI: the level in the health border's plate
            if preview._classicLevel then
                local shade = CreateHitOverlay(preview._classicLevel, "classicLevel", true)
                textOverlays[#textOverlays + 1] = shade
            end
            -- WoW Forever: the level box (its child, so it hides with it)
            if preview._fvLevelBox then CreateHitOverlay(preview._fvLevelBox, "foreverLevelBox") end
            -- Health bar
            if preview._health then CreateHitOverlay(preview._health, "healthBar") end
            -- Raid marker
            local raidOverlay
            if preview._raidFrame then
                raidOverlay = CreateHitOverlay(preview._raidFrame, "raidMarker")
                if not optionState.showRaidMarkerPreview then raidOverlay:Hide() end
            end
            -- Rare/elite icon
            local classOverlay
            if preview._classIcon then
                classOverlay = CreateHitOverlay(preview._classIcon, "classIcon")
                if not optionState.showClassificationPreview then classOverlay:Hide() end
            end
            -- Faction badge: shown and hidden with the badge by the preview update.
            if preview._factionIcon then
                preview._factionOverlay = CreateHitOverlay(preview._factionIcon, "factionIcon")
                preview._factionOverlay:SetShown(preview._factionIcon:IsShown())
            end
            -- Quest Objective Text sample (its child, so it shows and hides with it)
            if preview._questTextFrame then CreateHitOverlay(preview._questTextFrame, "questText") end
            -- Class resource pips wrapper button spanning all visible pips
            local cpOverlay
            if preview._cpPips then
                local firstVis, lastVis
                for i = 1, preview._cpMax do
                    if preview._cpPips[i] and preview._cpPips[i]:IsShown() then
                        if not firstVis then firstVis = preview._cpPips[i] end
                        lastVis = preview._cpPips[i]
                    end
                end
                -- Bar-type resource: use the bar frame as anchor
                local useBar = (not firstVis) and preview._cpBar and preview._cpBar:IsShown()
                local anchorFirst = firstVis or (useBar and preview._cpBar)
                local anchorLast = lastVis or (useBar and preview._cpBar)
                if anchorFirst and anchorLast then
                    local cpBtn = CreateFrame("Button", nil, preview)
                    cpBtn:SetPoint("TOPLEFT", anchorFirst, "TOPLEFT", -2, 2)
                    cpBtn:SetPoint("BOTTOMRIGHT", anchorLast, "BOTTOMRIGHT", 2, -2)
                    cpBtn:SetFrameLevel((preview._health and preview._health:GetFrameLevel() or 20) + 15)
                    cpBtn:RegisterForClicks("LeftButtonDown")
                    local classColor = CUI.CLUDES_GREEN
                    local function MkCPHL()
                        local tex = cpBtn:CreateTexture(nil, "OVERLAY", nil, 7)
                        tex:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)
                        if tex.SetSnapToPixelGrid then
                            tex:SetSnapToPixelGrid(false)
                            tex:SetTexelSnappingBias(0)
                        end
                        return tex
                    end
                    local cpPx = SnapPreview(2)
                    local cpt = MkCPHL()
                    cpt:SetHeight(cpPx)
                    cpt:SetPoint("TOPLEFT")
                    cpt:SetPoint("TOPRIGHT")
                    local cpb = MkCPHL()
                    cpb:SetHeight(cpPx)
                    cpb:SetPoint("BOTTOMLEFT")
                    cpb:SetPoint("BOTTOMRIGHT")
                    local cpl = MkCPHL()
                    cpl:SetWidth(cpPx)
                    cpl:SetPoint("TOPLEFT", cpt, "BOTTOMLEFT")
                    cpl:SetPoint("BOTTOMLEFT", cpb, "TOPLEFT")
                    local cpr = MkCPHL()
                    cpr:SetWidth(cpPx)
                    cpr:SetPoint("TOPRIGHT", cpt, "BOTTOMRIGHT")
                    cpr:SetPoint("BOTTOMRIGHT", cpb, "TOPRIGHT")
                    cpBtn._hlTextures = { cpt, cpb, cpl, cpr }
                    local function ShowCPHL()
                        for _, tex in ipairs(cpBtn._hlTextures) do
                            tex:Show()
                        end
                    end
                    local function HideCPHL()
                        for _, tex in ipairs(cpBtn._hlTextures) do
                            tex:Hide()
                        end
                    end
                    HideCPHL()
                    cpBtn:SetScript("OnEnter", function() ShowCPHL() end)
                    cpBtn:SetScript("OnLeave", function() HideCPHL() end)
                    cpBtn:SetScript("OnMouseDown", function() NavigateToSetting("classResource") end)
                    cpOverlay = cpBtn
                    -- Disable hover/click when class resource setting is off
                    local function UpdateCPOverlay()
                        local off = DbValue("showClassPower") ~= true
                        cpBtn:EnableMouse(not off)
                        cpBtn:SetAlpha(off and 0 or 1)
                    end
                    CUI.RegisterWidgetRefresh(UpdateCPOverlay)
                    UpdateCPOverlay()
                end
            end
            -- Sync overlay visibility with preview toggles
            preview._raidOverlay = raidOverlay
            preview._classOverlay = classOverlay
            -- Target arrows wrapper button spanning both arrow textures
            local arrowOverlay
            if preview._arrows then
                local arrowBtn = CreateFrame("Button", nil, preview)
                arrowBtn:SetPoint("TOPLEFT", preview._arrows.left, "TOPLEFT", -2, 2)
                arrowBtn:SetPoint("BOTTOMRIGHT", preview._arrows.right, "BOTTOMRIGHT", 2, -2)
                arrowBtn:SetFrameLevel((preview._health and preview._health:GetFrameLevel() or 20) + 15)
                arrowBtn:RegisterForClicks("LeftButtonDown")
                local classColor = CUI.CLUDES_GREEN
                local function MkAHL()
                    local tex = arrowBtn:CreateTexture(nil, "OVERLAY", nil, 7)
                    tex:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)
                    if tex.SetSnapToPixelGrid then
                        tex:SetSnapToPixelGrid(false)
                        tex:SetTexelSnappingBias(0)
                    end
                    return tex
                end
                -- Highlight on left arrow
                local aPx = SnapPreview(2)
                local alt = MkAHL()
                alt:SetHeight(aPx)
                alt:SetPoint("TOPLEFT", preview._arrows.left, -2, 2)
                alt:SetPoint("TOPRIGHT", preview._arrows.left, 2, 2)
                local alb = MkAHL()
                alb:SetHeight(aPx)
                alb:SetPoint("BOTTOMLEFT", preview._arrows.left, -2, -2)
                alb:SetPoint("BOTTOMRIGHT", preview._arrows.left, 2, -2)
                local all = MkAHL()
                all:SetWidth(aPx)
                all:SetPoint("TOPLEFT", alt, "BOTTOMLEFT")
                all:SetPoint("BOTTOMLEFT", alb, "TOPLEFT")
                local alr = MkAHL()
                alr:SetWidth(aPx)
                alr:SetPoint("TOPRIGHT", alt, "BOTTOMRIGHT")
                alr:SetPoint("BOTTOMRIGHT", alb, "TOPRIGHT")
                -- Highlight on right arrow
                local art = MkAHL()
                art:SetHeight(aPx)
                art:SetPoint("TOPLEFT", preview._arrows.right, -2, 2)
                art:SetPoint("TOPRIGHT", preview._arrows.right, 2, 2)
                local arb = MkAHL()
                arb:SetHeight(aPx)
                arb:SetPoint("BOTTOMLEFT", preview._arrows.right, -2, -2)
                arb:SetPoint("BOTTOMRIGHT", preview._arrows.right, 2, -2)
                local arl = MkAHL()
                arl:SetWidth(aPx)
                arl:SetPoint("TOPLEFT", art, "BOTTOMLEFT")
                arl:SetPoint("BOTTOMLEFT", arb, "TOPLEFT")
                local arr = MkAHL()
                arr:SetWidth(aPx)
                arr:SetPoint("TOPRIGHT", art, "BOTTOMRIGHT")
                arr:SetPoint("BOTTOMRIGHT", arb, "TOPRIGHT")
                arrowBtn._hlTextures = { alt, alb, all, alr, art, arb, arl, arr }
                local function ShowAHL()
                    for _, tex in ipairs(arrowBtn._hlTextures) do
                        tex:Show()
                    end
                end
                local function HideAHL()
                    for _, tex in ipairs(arrowBtn._hlTextures) do
                        tex:Hide()
                    end
                end
                HideAHL()
                arrowBtn:SetScript("OnEnter", function() ShowAHL() end)
                arrowBtn:SetScript("OnLeave", function() HideAHL() end)
                arrowBtn:SetScript("OnMouseDown", function() NavigateToSetting("targetArrows") end)
                -- Only show when arrows are visible
                if not preview._arrows.left:IsShown() then arrowBtn:Hide() end
                arrowOverlay = arrowBtn
            end
            preview._arrowOverlay = arrowOverlay
            -- Store text overlays for size refresh on preview update
            preview._textOverlays = textOverlays
        end

        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Colors page
    ---------------------------------------------------------------------------

    -- Spell icon pool for cast bar previews, cycled in order
    local castIconPool = { 136197, 236802, 135808, 136116, 135735, 136048, 135812, 136075 }
    local castIconIdx = 0
    local function NextCastIcon()
        castIconIdx = castIconIdx + 1
        if castIconIdx > #castIconPool then castIconIdx = 1 end
        return castIconPool[castIconIdx]
    end

    -- Cast fill values: each at least 5% apart, range 40 90%
    local castFillUsed = {}
    local function NextCastFill()
        for _ = 1, 50 do
            local value = 0.40 + math.random() * 0.20
            local success = true
            for _, prev in ipairs(castFillUsed) do
                if math.abs(value - prev) < 0.05 then
                    success = false
                    break
                end
            end
            if success then
                castFillUsed[#castFillUsed + 1] = value
                return value
            end
        end
        -- fallback if somehow can't find a valid value
        local value = 0.40 + math.random() * 0.20
        castFillUsed[#castFillUsed + 1] = value
        return value
    end

    -- Shared preview bar list and lazy builder (used by both Display and Colors pages).
    -- One entry per bar (colorType and colorKey): each build of the row that shows a
    -- bar replaces that bar's entry, so the list keeps the latest build's bars only.
    local _colorPagePreviews = {}
    local _colorPreviewSlot = {} -- "colorType:colorKey" -> index in _colorPagePreviews

    LazyColorPreviewBar = function(parentRow, colorType, colorKey, anchorFrame)
        local real = nil
        local proxy = {}
        local _disabled = false
        local _colorOverrideFn = nil
        -- The row's dress this bar belongs to (page reuse): once the row is dressed
        -- again for a later build, this proxy and its bar are that build's no more.
        local rowGen = PoolGen(parentRow)
        local function BuiltRow()
            if real and PoolGen(parentRow) == rowGen then return real end
        end
        local function BuildRowOnce()
            if PoolGen(parentRow) ~= rowGen then return nil end
            if real then return real end
            real = mod.NPO_MakeColorPreviewBar(parentRow, colorType, colorKey, anchorFrame)
            if _disabled and real._health then real._health:SetAlpha(0.3) end
            return real
        end
        proxy.GetFrame = function() return BuildRowOnce() end
        proxy.UpdateColor = function()
            local r = BuildRowOnce()
            if r and r.UpdateColor then
                if _colorOverrideFn then
                    local cr, cg, checkBtn = _colorOverrideFn()
                    if cr and r._health then
                        r._health:SetStatusBarColor(cr, cg, checkBtn, 1)
                        return
                    end
                end
                r.UpdateColor()
            end
        end
        proxy.UpdateOverlay = function()
            local r = BuildRowOnce()
            if r and r.UpdateOverlay then r.UpdateOverlay() end
        end
        proxy.RefreshBorderStyle = function()
            local r = BuiltRow()
            if r and r.RefreshBorderStyle then r.RefreshBorderStyle() end
        end
        proxy.RefreshBorderColor = function()
            local r = BuiltRow()
            if r and r.RefreshBorderColor then r.RefreshBorderColor() end
        end
        proxy.Randomize = function()
            local r = BuiltRow()
            if r and r.Randomize then r.Randomize() end
        end
        proxy.RefreshHealthText = function()
            local r = BuiltRow()
            if r and r.RefreshHealthText then r.RefreshHealthText() end
        end
        proxy.SetDisabled = function(off)
            _disabled = off
            local r = BuiltRow()
            if r and r._health then r._health:SetAlpha(off and 0.3 or 1) end
        end
        proxy.SetColorOverride = function(func) _colorOverrideFn = func end
        parentRow:HookScript("OnShow", function()
            if not real then
                BuildRowOnce()
                -- Listed once: page reuse can hand the same bar frame to a later build.
                local entries = _G._CUI_ColorPreviews
                local listed = false
                for i = 1, #entries do
                    if entries[i] == real then
                        listed = true
                        break
                    end
                end
                if not listed then entries[#entries + 1] = real end
            end
            if real and real._health then real._health:SetAlpha(_disabled and 0.3 or 1) end
        end)
        if parentRow:IsVisible() then BuildRowOnce() end
        local slot = colorType .. ":" .. tostring(colorKey)
        local position = _colorPreviewSlot[slot]
        if not position then
            position = #_colorPagePreviews + 1
            _colorPreviewSlot[slot] = position
        end
        _colorPagePreviews[position] = proxy
        return proxy
    end

    -- Textured Background: the Texture Settings cog row, shared by the Display
    -- page and Global Settings > Textures. kind: "health" or "cast"; apply: the
    -- page's own refresh after a write.
    local function TexBgRowCfg(kind, apply)
        local cast = kind == "cast"
        local key = cast and "castTextureBg" or "healthTextureBg"
        local texKey = cast and "castBarTexture" or "healthBarTexture"
        return mod.NP_BlizzOnlyGate({
            type = "toggle",
            label = "Textured Background",
            tooltip = cast and "Draws the bar texture on the cast bar background too."
                or "Draws the bar texture on the health bar background too.",
            disabled = function() return (DbValue(texKey) or "none") == "none" end,
            disabledTooltip = cast and "This option requires a Cast Bar Texture other than None."
                or "This option requires a Bar Texture other than None.",
            get = function() return DbValue(key) == true end,
            set = function(value)
                PlatesProfile()[key] = value and true or false
                apply()
            end,
        })
    end
    -- Shared with the page builders under Nameplates_Options\ (read in their
    -- prologs). Every field is final here: optState holds the mutable state.
    mod._NPO_OptEnv = {
        TexBgRowCfg = TexBgRowCfg,
        _colorPagePreviews = _colorPagePreviews,
        ADDON_NAME = ADDON_NAME,
        BAR_W = BAR_W,
        DB = PlatesProfile,
        DBColor = DBColor,
        DBVal = DbValue,
        defaults = defaultSet,
        displayCastIcons = displayCastIcons,
        FOCUS_LETTER_ANCHOR_ORDER = FOCUS_LETTER_ANCHOR_ORDER,
        FOCUS_LETTER_ANCHORS = FOCUS_LETTER_ANCHORS,
        GetFocusLetterAnchor = GetFocusLetterAnchor,
        GetNPOptOutline = GetNPOptOutline,
        hbtOrder = hbtOrder,
        hbtValues = hbtValues,
        LazyColorPreviewBar = LazyColorPreviewBar,
        NAME_RAID_MARKER_GAP = NAME_RAID_MARKER_GAP,
        NextCastFill = NextCastFill,
        NextCastIcon = NextCastIcon,
        npDispelGlowDesc = npDispelGlowDesc,
        npImpCastGlowDesc = npImpCastGlowDesc,
        npPandemicGlowDesc = npPandemicGlowDesc,
        npCastTargetGlowDesc = npCastTargetGlowDesc,
        optState = optionState,
        pairs = pairs,
        pcall = pcall,
        plates = plates,
        PP = Pix,
        RandomizePreviewValues = RandomizePreviewValues,
        RefreshAllAuras = RefreshAllAuras,
        RefreshAllPlates = RedrawPlates,
        SECTION_AURA = SECTION_AURA,
        SECTION_CASTBAR = SECTION_CASTBAR,
        SECTION_ENEMY = SECTION_ENEMY,
        SECTION_ENEMY_NP = SECTION_ENEMY_NP,
        SECTION_FRIENDLY = SECTION_FRIENDLY,
        SECTION_MISC = SECTION_MISC,
        SECTION_THREAT = SECTION_THREAT,
        SetFSFont = SetFSFont,
        SetPVFont = SetPVFont,
        THREAT_PCT_POSITION_ORDER = THREAT_PCT_POSITION_ORDER,
        THREAT_PCT_POSITIONS = THREAT_PCT_POSITIONS,
        UpdatePreview = RepaintPreview,
    }

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    -- Rebuild preview when spec changes (class resource pips may appear/disappear)
    local npOptSpecFrame = CreateFrame("Frame")
    npOptSpecFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    npOptSpecFrame:SetScript("OnEvent", function(_, _, unitToken)
        if unitToken ~= "player" then return end
        -- Only invalidate + rebuild when the panel is open; invalidating while closed destroys all cached pages, causing a blank panel on next open.
        if CUI._mainFrame and CUI._mainFrame:IsShown() then
            CUI:InvalidatePageCache()
            C_Timer.After(0.2, function() CUI:RefreshPage(true) end)
        elseif
            CUI:GetActiveModule() == "CludesUINameplates"
            and CUI:GetActivePage() == PAGE_DISPLAY
        then
            -- Closed on the Display page: a spec preset can rewrite the texts, and
            -- a reopen shows the cached page without a restore. RefreshPage only
            -- flags a hidden panel, so the next open rebuilds this page once.
            CUI:RefreshPage(true)
        end
    end)

    CUI:RegisterModule("CludesUINameplates", {
        title = "Nameplates",
        description = "Custom nameplate design and behavior.",
        pages = { PAGE_DISPLAY, PAGE_COLORS, PAGE_GENERAL },
        buildPage = function(pageName, hostFrame, yOffset)
            if pageName == PAGE_GENERAL then
                return mod.NPO_BuildGeneralPage(pageName, hostFrame, yOffset)
            elseif pageName == PAGE_DISPLAY then
                return BuildDisplayPage(pageName, hostFrame, yOffset)
            elseif pageName == PAGE_COLORS then
                return mod.NPO_BuildColorsPage(pageName, hostFrame, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_DISPLAY then return _displayHeaderBuilder end
            return nil -- General and Colors have no content header
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_DISPLAY then
                -- Rebuild when the texts' structure changed behind the cached
                -- page (a spec change while the panel was closed, a preset, a
                -- Style swap), so Core Text Positions and Core Text Coloring
                -- match the profile.
                if optionState._npTextFP and mod.NPO_TextStructureFP() ~= optionState._npTextFP then
                    C_Timer.After(0, function()
                        if
                            CUI:GetActiveModule() == "CludesUINameplates"
                            and CUI:GetActivePage() == PAGE_DISPLAY
                        then
                            CUI:RefreshPage(true)
                        end
                    end)
                end
                -- Re-evaluate Set as Default button visibility (cache restore blanket-shows all children, which can ghost the button).
                local pState = CUI._presetState and CUI._presetState[""]
                if pState and pState.UpdateDefaultBtnState then pState.UpdateDefaultBtnState() end
                -- Randomize preview values when switching TO this tab
                RandomizePreviewValues()
                -- Refresh the preview after cache restore
                if optionState.activePreview and optionState.activePreview.Update then
                    optionState.activePreview:Update()
                end
                -- Refresh hint visibility only; never recreate here.
                local dismissed = IsPreviewHintDismissed()
                if optionState._previewHintFS then
                    if dismissed then
                        optionState._previewHintFS:Hide()
                    else
                        optionState._previewHintFS:SetAlpha(0.45)
                        optionState._previewHintFS:Show()
                    end
                end
                -- Set correct header height based on current hint state
                if _headerBaseH > 0 then
                    CUI:SetContentHeaderHeightSilent(_headerBaseH + (dismissed and 0 or 29))
                end
            elseif pageName == PAGE_COLORS then
                -- Refresh all color preview bars (colors from DB)
                if optionState._colorPreviewRefreshAll then optionState._colorPreviewRefreshAll() end
            end
        end,
        onReset = function()
            -- Invalidate page cache so pages are rebuilt with fresh defaults
            CUI:InvalidatePageCache()
            -- Preserve user-saved presets (display + color), Custom presets, AND spec assignments across reset
            local old = PlatesProfile()
            if old then
                local pD = old._presets
                local oD = old._presetOrder
                local pC = old._color_presets
                local oC = old._color_presetOrder
                local cD = old._customPreset
                local cC = old._color_customPreset
                local sA = old._specAssignments
                local sCA = old._color_specAssignments
                local sDP = old._specDefaultPreset
                for keyName in pairs(old) do
                    old[keyName] = nil
                end
                if pD and next(pD) then
                    old._presets = pD
                    old._presetOrder = oD
                end
                if pC and next(pC) then
                    old._color_presets = pC
                    old._color_presetOrder = oC
                end
                if cD then old._customPreset = cD end
                if cC then old._color_customPreset = cC end
                if sA and next(sA) then old._specAssignments = sA end
                if sCA and next(sCA) then old._color_specAssignments = sCA end
                if sDP then old._specDefaultPreset = sDP end
                -- Explicitly activate CludesUI for both preset systems
                old._activePreset = "cludesui"
                old._color_activePreset = "cludesui"
            end
        end,
    })

    ---------------------------------------------------------------------------
    --  Slash command  /cnp  opens CludesUI to the Nameplates module
    ---------------------------------------------------------------------------
    SLASH_CLUDESNAMEPLATES1 = "/cnp"
    SlashCmdList.CLUDESNAMEPLATES = function(msg)
        if InCombatLockdown and InCombatLockdown() then
            print("Cannot open options in combat")
            return
        end

        if msg == "reset" then
            -- The reload first (RequestReload); the reset below lands before it.
            CUI.RequestReload()
            local _db = PlatesProfile()
            if _db then
                local pD = _db._presets
                local oD = _db._presetOrder
                local pC = _db._color_presets
                local oC = _db._color_presetOrder
                local cD = _db._customPreset
                local cC = _db._color_customPreset
                local sA = _db._specAssignments
                local sCA = _db._color_specAssignments
                local sDP = _db._specDefaultPreset
                for keyName in pairs(_db) do
                    _db[keyName] = nil
                end
                if pD and next(pD) then
                    _db._presets = pD
                    _db._presetOrder = oD
                end
                if pC and next(pC) then
                    _db._color_presets = pC
                    _db._color_presetOrder = oC
                end
                if cD then _db._customPreset = cD end
                if cC then _db._color_customPreset = cC end
                if sA and next(sA) then _db._specAssignments = sA end
                if sCA and next(sCA) then _db._color_specAssignments = sCA end
                if sDP then _db._specDefaultPreset = sDP end
                _db._activePreset = "cludesui"
                _db._color_activePreset = "cludesui"
            end
            return
        end

        CUI:ShowModule("CludesUINameplates")
    end
end)
